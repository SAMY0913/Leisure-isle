extends SceneTree
# P7-V1 任务 C 修复探针（headless）：
#   C1 萤火：main._update_lighting 驱动真实 GPUParticles3D（emitting/amount_ratio），验证夜间开、白天关。
#   C2 夜层：跳时（黄昏→正午）不再单帧 hard-stop，env 按 tau 连续衰减且到 ~-43dB 才 stop。
#   C3 火声：壁炉关闭后音量连续淡出（不再 -12dB→静音），到低谷才 stop。
#   C4 帆船：跳时落在白天时提前结束 RESTING，不再被夜间 rest_until 锁住；正常白天短停靠/夜间休息不变。
# 判据：exit 0 且 [P7C] RESULT fail=0。固定 dt、不使用真实时钟。
# 运行：<godot_console.exe> --headless --path D:/休闲小岛幻境/游戏工程 --script res://tools/probe_p7c.gd

const AudioScript := preload("res://scripts/isle_audio.gd")
const MainScene := preload("res://isle.tscn")

const DAY_ALT := 10.0
const NIGHT_ALT := -8.0
const DT_A := 0.1

var _pass := 0
var _fail := 0
var _fails: Array = []
var _audio: Node = null


func _initialize() -> void:
	print("[P7C] P7-V1 task-C fix probe start")
	await process_frame
	_audio = AudioScript.new() as Node
	_audio.name = "Audio"
	root.add_child(_audio)
	_audio.call("setup", root)
	await process_frame
	_probe_night_jump_fade()
	_probe_fire_fade()
	await _probe_main_coord()
	print("[P7C] RESULT pass=%d fail=%d" % [_pass, _fail])
	for m in _fails:
		print("[P7C] FAIL: ", m)
	quit(0 if _fail == 0 else 1)


func _check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("[P7C] [OK] " + msg)
	else:
		_fail += 1
		_fails.append(msg)
		print("[P7C] [FAIL] " + msg)


func _update(sun_alt: float, night: float, wind: float, fireplace_on: bool, dt: float = DT_A) -> void:
	_audio.call("update_audio", dt, {
		"sun_alt": sun_alt,
		"night": night,
		"wind": wind,
		"fireplace_on": fireplace_on,
	})


func _snap() -> Dictionary:
	return _audio.call("get_debug_info") as Dictionary


func _last_event(ev_type: String, layer: String = "") -> Dictionary:
	var evs: Array = AudioScript.get_event_log()
	for i in range(evs.size() - 1, -1, -1):
		var ev: Dictionary = evs[i]
		if String(ev.get("type", "")) != ev_type:
			continue
		if layer != "" and String(ev.get("layer", "")) != layer:
			continue
		return ev
	return {}


# ============================================================
# C2：夜层跳时淡出（不再单帧 73dB 硬切）
# ============================================================
func _probe_night_jump_fade() -> void:
	print("[P7C] --- C2 night-layer jump fade ---")
	# 先稳定入夜
	for i in range(80):
		_update(NIGHT_ALT, 0.9, 0.6, true, 0.5)
	var info: Dictionary = _snap()
	var loops: Array = info.get("loops", [])
	_check(loops.size() == 3, "夜层存在（loops=3）")
	if loops.size() != 3:
		return
	var night: Dictionary = loops[2]
	_check(bool(night.get("playing", false)), "入夜后夜层在播")
	var env0 := float(night.get("env", 0.0))
	_check(env0 >= 0.95, "入夜 env 收敛 >= 0.95（实际 %.3f）" % env0)

	# 直接跳到正午（模拟 [ / 数字键跳时）：逐帧记录 env / playing / volume
	var env_prev := env0
	var max_env_drop := 0.0
	var playing_after_one := false
	var first := true
	var stopped := false
	var frames_to_stop := -1
	var volume_prev := float(night.get("volume_db", -80.0))
	var max_db_drop := 0.0
	var prev_playing := true
	for i in range(120):
		_update(DAY_ALT, 0.0, 0.3, false, DT_A)
		var s: Dictionary = _snap()
		var ls: Array = s.get("loops", [])
		if ls.size() != 3:
			continue
		var n: Dictionary = ls[2]
		var env := float(n.get("env", 0.0))
		var vol := float(n.get("volume_db", -80.0))
		var cur_playing := bool(n.get("playing", false))
		if first:
			playing_after_one = cur_playing
			first = false
		if not stopped:
			max_env_drop = maxf(max_env_drop, env_prev - env)
			# 只在淡出期间（前后两帧都在播）统计音量跌幅；stop 帧的静音复位不计入
			if prev_playing and cur_playing:
				max_db_drop = maxf(max_db_drop, volume_prev - vol)
			if not cur_playing:
				stopped = true
				frames_to_stop = i + 1
		env_prev = env
		volume_prev = vol
		prev_playing = cur_playing
	_check(playing_after_one, "跳时后第 1 帧夜层仍在播放（不再单帧 hard-stop）")
	_check(max_env_drop < 0.20, "夜层 env 单帧最大跌幅 %.3f < 0.20（连续淡出）" % max_env_drop)
	_check(max_db_drop < 3.0, "夜层音量单帧最大跌幅 %.2f dB < 3 dB（旧实现一次跌 73dB）" % max_db_drop)
	_check(stopped, "夜层在白天窗口内最终停止")
	_check(frames_to_stop >= 20 and frames_to_stop <= 120,
			"夜层淡出约 %.1fs 后停止（期望 2-12s）" % (float(frames_to_stop) * DT_A))
	var stop_ev: Dictionary = _last_event("loop_stop", "Night")
	_check(not stop_ev.is_empty(), "记录 loop_stop:Night 事件")
	if not stop_ev.is_empty():
		var stop_env := float(stop_ev.get("env", 1.0))
		_check(stop_env <= 0.02 and stop_env >= 0.0,
				"停止发生在淡出低谷 env=%.4f（约 -43dB，贴近自然黎明停点）" % stop_env)
		_check(stop_ev.has("fade_tau"), "停止事件带 fade_tau 诊断字段")
	var info_d: Dictionary = _snap()
	var loops_d: Array = info_d.get("loops", [])
	_check(loops_d.size() == 3 and not bool(loops_d[2].get("playing", false)), "白天结束时夜层已停止")
	_check(float(loops_d[2].get("env", 1.0)) <= 0.001, "停止后 env 归零（无残留增益）")


# ============================================================
# C3：火焰声淡出（不再 -12dB 一步到静音）
# ============================================================
func _probe_fire_fade() -> void:
	print("[P7C] --- C3 fire-loop fade ---")
	# 回到白天、无壁炉
	for i in range(30):
		_update(DAY_ALT, 0.0, 0.5, false, 0.2)
	var info: Dictionary = _snap()
	_check(not bool(info.get("fire_playing", false)), "白天无壁炉时火焰声不播放")

	# 入夜并点燃壁炉
	for i in range(30):
		_update(-1.0, 0.1, 0.5, true, 0.2)
	info = _snap()
	_check(bool(info.get("fire_playing", false)), "壁炉开启后火焰声播放")
	var vol_on := float(info.get("fire_volume_db", -80.0))
	_check(absf(vol_on - (-12.0)) < 0.6, "开启时直接回到 FIRE_BASE_DB=-12dB（实际 %.1f）" % vol_on)

	# 关闭：逐帧记录音量，验证连续淡出
	_update(-1.0, 0.1, 0.5, false, 0.2)
	info = _snap()
	_check(bool(info.get("fire_playing", false)), "关闭后第 1 帧火焰声仍在播放（淡出开始）")
	var vol_prev := float(info.get("fire_volume_db", -80.0))
	var max_db_drop := vol_on - vol_prev
	var stopped := false
	var frames_to_stop := -1
	var last_vol := vol_prev
	for i in range(60):
		_update(-1.0, 0.1, 0.5, false, 0.2)
		var s: Dictionary = _snap()
		var vol := float(s.get("fire_volume_db", -80.0))
		if not stopped:
			var d := last_vol - vol
			if bool(s.get("fire_playing", false)):
				max_db_drop = maxf(max_db_drop, d)
			if not bool(s.get("fire_playing", false)):
				stopped = true
				frames_to_stop = i + 1
		last_vol = vol
	_check(max_db_drop < 4.0, "火焰声音量单帧最大跌幅 %.2f dB < 4 dB（旧实现一次 68dB）" % max_db_drop)
	_check(stopped, "火焰声淡出后最终停止")
	_check(frames_to_stop >= 3 and frames_to_stop <= 40,
			"淡出约 %.1fs 后停止（期望 0.6-8s）" % (float(frames_to_stop) * 0.2))
	var stop_ev: Dictionary = _last_event("fire_stop")
	_check(not stop_ev.is_empty(), "记录 fire_stop 事件")
	if not stop_ev.is_empty():
		var stop_env := float(stop_ev.get("stop_env", 1.0))
		_check(stop_env <= 0.02, "fire_stop 记录 stop_env=%.4f <= 0.02" % stop_env)
		_check(String(stop_ev.get("source", "")) == "fireplace_off", "fire_stop source=fireplace_off")
	var fade_ev: Dictionary = _last_event("fire_fade")
	_check(not fade_ev.is_empty(), "记录 fire_fade 事件（关闭开始淡出）")


# ============================================================
# C1 萤火 + C4 帆船跳时解锁（同一 main 实例）
# ============================================================
func _probe_main_coord() -> void:
	print("[P7C] --- C1 fireflies + C4 boat rest ---")
	var m = MainScene.instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	_check(m._birds != null, "main 场景已就绪（海鸥状态机存在）")
	var ff: Dictionary = m._fx.get("fireflies", {})
	var node = ff.get("node", null)
	_check(node is GPUParticles3D, "萤火节点为 GPUParticles3D")
	_check(not (ff.get("mat", null) is ShaderMaterial), "萤火材质不是 ShaderMaterial（C1 根因：原赋值恒为 null）")
	if node is GPUParticles3D:
		var gp := node as GPUParticles3D
		m._paused = true
		m._time_source = "sim"
		m._sim_seconds = 22.0 * 3600.0
		m._update_lighting()
		await process_frame
		_check(gp.emitting, "夜间 22:00 萤火节点 emitting=true（修复前恒为 false）")
		_check(gp.amount_ratio > 0.5, "夜间 22:00 萤火 amount_ratio=%.2f > 0.5" % gp.amount_ratio)
		m._sim_seconds = 12.0 * 3600.0
		m._update_lighting()
		await process_frame
		_check(not gp.emitting, "白天 12:00 萤火节点 emitting=false")
		_check(gp.amount_ratio <= 0.01, "白天 12:00 萤火 amount_ratio 归零")

	# C4：帆船 RESTING 与跳时校准
	m._paused = false
	m._time_source = "sim"
	_check(m._sailboat != null, "小船节点存在")
	if m._sailboat == null:
		return
	# 1) 正常白天短停靠：无跳时不得被提前结束
	m._sim_seconds = 12.0 * 3600.0
	m._boat_state = "RESTING"
	m._boat_rest_until = m._sim_seconds + 30.0
	m._time_jump = 0.0
	m._sync_boat_clock()
	_check(absf(float(m._boat_rest_until) - (m._sim_seconds + 30.0)) < 0.01,
			"白天短停靠（无跳时）不被提前结束（rest_until-now=%.1fs）" % (float(m._boat_rest_until) - m._sim_seconds))
	# 2) 向后拖时间到白天：夜间长休息提前结束
	m._sim_seconds = 22.0 * 3600.0
	m._boat_state = "RESTING"
	m._boat_rest_until = m._sim_seconds + 20.0 * 3600.0
	m._time_jump = -36000.0
	m._sim_seconds = 12.0 * 3600.0
	m._sync_boat_clock()
	_check(float(m._boat_rest_until) <= m._sim_seconds + 0.01,
			"向后拖时间到 12:00 后 rest_until 被收敛到现在（rest_until-now=%.1fs）" % (float(m._boat_rest_until) - m._sim_seconds))
	_check(absf(float(m._time_jump)) < 0.001, "跳时量已被消费（_time_jump 归零）")
	# 3) 向前跳到次日白天：同样提前结束
	m._sim_seconds = 22.0 * 3600.0
	m._boat_state = "RESTING"
	m._boat_rest_until = m._next_rest_end_sim()
	m._time_jump = 10.0 * 3600.0
	m._sim_seconds = 12.0 * 3600.0 + 86400.0
	m._sync_boat_clock()
	_check(float(m._boat_rest_until) <= m._sim_seconds + 0.01,
			"向前跳到次日白天后 rest_until 收敛（rest_until-now=%.1fs）" % (float(m._boat_rest_until) - m._sim_seconds))
	# 4) 夜间跳时不得解除休息（仍锁到 08:00）
	m._sim_seconds = 23.0 * 3600.0
	m._boat_state = "RESTING"
	m._boat_rest_until = m._next_rest_end_sim()
	var night_target := float(m._boat_rest_until)
	m._time_jump = 1800.0
	m._sync_boat_clock()
	_check(float(m._boat_rest_until) >= night_target - 1.0,
			"夜间跳时仍保持休息到 08:00（rest_until-now=%.1fh）" % ((float(m._boat_rest_until) - m._sim_seconds) / 3600.0))
	# 5) 夜间 DOCKED 仍会进入 RESTING（既有规则未回退）
	m._sim_seconds = 19.0 * 3600.0
	m._boat_state = "DOCKED"
	m._time_jump = 3600.0
	m._sync_boat_clock()
	_check(String(m._boat_state) == "RESTING", "夜间 DOCKED 跳时后仍进入 RESTING（既有关门规则不变）")
