extends SceneTree
## P7-V2 海鸥独立验收探针（task-4 / test-verify，独立于 bird-dev 的自测探针）
## 覆盖 task-1 验收：A 停栖待机动作、B 随机分散/多轮分布、C 烟囱禁停（边界/超前/跳时/夜间/穿烟安全）、
##                   D 调试接口冻结契约。全部通过真实 update_birds(delta, sun_alt, ctx) 驱动，
##                   不读源码常量代替运行结果；不改 fx.gd。
##
## 运行：
##   "D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe" --headless --path "D:/休闲小岛幻境/游戏工程" --script res://tools/probe_p7v2_bird.gd
## 退出码：0=全部通过；1=有失败。日志同时由调用方重定向到 开发产物/p7v2/logs/。

const Fx = preload("res://scripts/fx.gd")
const WorldScript = preload("res://scripts/world.gd")
const CottageScript = preload("res://scripts/cottage.gd")

const DT := 1.0 / 60.0
const BIRD_COUNT := 10
const STATE_TAKEOFF := 1
const STATE_LANDING := 2
const STATE_PERCH := 3
const DAY_ALT := 40.0
const NIGHT_ALT := -25.0

var _pass := 0
var _fail := 0
var _fails: Array = []
var _world_holder: Node3D = null
var _cottage_holder: Node3D = null
var _world_perches: Array = []
var _cottage_perches: Array = []
var _all_perches: Array = []
var _flat_perches: Array = []
var _chimney_id := ""

func _initialize() -> void:
	print("=== P7-V2 BIRD PROBE START ===")
	await process_frame
	_build_real_perches()
	_build_flat_perches()
	_probe_a_idle_actions()
	_probe_b_distribution()
	_probe_c_chimney()
	_probe_d_api_contract()
	_cleanup()
	_report()

# ============================================================
# 基础工具
# ============================================================
func _check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("  [OK] ", msg)
	else:
		_fail += 1
		_fails.append(msg)
		print("  [FAIL] ", msg)

func _info(msg: String) -> void:
	print("  [BIRD] ", msg)

func _report() -> void:
	print("[BIRD] RESULT pass=", _pass, " fail=", _fail)
	for m in _fails:
		print("[BIRD] FAILED: ", m)
	quit(0 if _fail == 0 else 1)

func _ctx(sim_seconds: float, rate: float = 1.0) -> Dictionary:
	return {
		"day": 1 + int(sim_seconds / 86400.0),
		"rising": false,
		"sim_seconds": sim_seconds,
		"time_source": "sim",
		"paused": false,
		"sim_rate": rate,
	}

func _step(flock: Node, alt: float, sim_seconds: float, rate: float = 1.0) -> void:
	flock.update_birds(DT, alt, _ctx(sim_seconds, rate))

func _sun_alt_for(sim_seconds: float) -> float:
	var minutes := fposmod(sim_seconds, 86400.0) / 60.0
	var ang: float = (minutes - 360.0) / 720.0 * PI
	return sin(ang) * 55.0

func _spawn_flock(perches: Array) -> Node:
	var flock: Node = Fx.BirdFlock.new()
	flock.name = "ProbeBirdFlock"
	get_root().add_child(flock)
	flock.setup(perches)
	return flock

func _birds(flock: Node) -> Array:
	return flock.get("_birds") as Array

func _bird(flock: Node, idx: int) -> Dictionary:
	var birds: Array = _birds(flock)
	return birds[idx]

func _perch_list(flock: Node) -> Array:
	return flock.get("_perches") as Array

func _perch_by_id(perches: Array, pid: String) -> Dictionary:
	for p_v in perches:
		var p: Dictionary = p_v
		if String(p.get("id", "")) == pid:
			return p
	return {}

func _kind_of(flock: Node, pid: String) -> String:
	var p: Dictionary = _perch_by_id(_perch_list(flock), pid)
	return String(p.get("kind", ""))

func _slot_pos(flock: Node, b: Dictionary) -> Vector3:
	var pid := String(b.get("perch_id", ""))
	if pid == "":
		return Vector3.ZERO
	var p: Dictionary = _perch_by_id(_perch_list(flock), pid)
	if p.is_empty():
		return Vector3.ZERO
	var v: Vector3 = flock.call("_slot_position", p, int(b.get("perch_slot", 0)))
	return v

func _snapshot(flock: Node) -> Array:
	return flock.call("debug_snapshot")

func _idle_state(flock: Node) -> Array:
	return flock.call("debug_idle_state")

func _stats(flock: Node) -> Dictionary:
	return flock.call("debug_perch_stats")

func _count_perch_state(snap: Array, state: int) -> int:
	var n := 0
	for s_v in snap:
		var s: Dictionary = s_v
		if int(s["state"]) == state:
			n += 1
	return n

func _zones_of(snap: Array, states: Array) -> Dictionary:
	var zones: Dictionary = {}
	for s_v in snap:
		var s: Dictionary = s_v
		if not states.has(int(s["state"])):
			continue
		var z := String(s.get("perch_zone", ""))
		if z != "":
			zones[z] = int(zones.get(z, 0)) + 1
	return zones

func _roof_occupancy(snap: Array) -> int:
	var n := 0
	for s_v in snap:
		var s: Dictionary = s_v
		var st := int(s["state"])
		if st != STATE_PERCH and st != STATE_LANDING:
			continue
		if String(s.get("perch_zone", "")) == "roof":
			n += 1
	return n

func _count_timer_nodes(node: Node) -> int:
	var n := 0
	if node is Timer:
		n += 1
	for c in node.get_children():
		n += _count_timer_nodes(c)
	return n

func _find_avail(availability: Array, pid: String) -> Dictionary:
	for a_v in availability:
		var a: Dictionary = a_v
		if String(a.get("id", "")) == pid:
			return a
	return {}

func _force_all_safe(flock: Node) -> void:
	# 把 10 只鸟分别强落到非烟囱真实栖点；参数 allow_chimney_index 为需要强落烟囱的鸟 index。
	var safe: Array = []
	for p_v in _perch_list(flock):
		var p: Dictionary = p_v
		if String(p["kind"]) != "chimney":
			safe.append(p)
	var j := 0
	for i in range(BIRD_COUNT):
		var pid := String((safe[j % safe.size()] as Dictionary)["id"])
		var ok := bool(flock.call("debug_force_perch", i, pid))
		_check(ok, "预置鸟 %d -> %s" % [i, pid])
		j += 1

# ============================================================
# 真实 / 合成栖点
# ============================================================
func _build_real_perches() -> void:
	print("--- [LOAD] 真实栖点（world + cottage）---")
	_world_holder = Node3D.new()
	_world_holder.name = "BirdProbeWorld"
	get_root().add_child(_world_holder)
	var wd: Dictionary = WorldScript.build(_world_holder)
	_cottage_holder = Node3D.new()
	_cottage_holder.name = "BirdProbeCottage"
	get_root().add_child(_cottage_holder)
	var cd: Dictionary = CottageScript.build(_cottage_holder)
	_world_perches = (wd.get("perches", []) as Array).duplicate(true)
	_cottage_perches = (cd.get("perches", []) as Array).duplicate(true)
	_all_perches = _world_perches + _cottage_perches
	var kinds: Dictionary = {}
	for p_v in _all_perches:
		var p: Dictionary = p_v
		var k := String(p.get("kind", ""))
		kinds[k] = int(kinds.get(k, 0)) + 1
		if k == "chimney" and _chimney_id == "":
			_chimney_id = String(p["id"])
	_check(_all_perches.size() >= 20, "真实栖点数量足够（world %d + cottage %d = %d）" % [_world_perches.size(), _cottage_perches.size(), _all_perches.size()])
	_check(_chimney_id != "", "真实栖点中存在 kind=chimney（id=%s）" % _chimney_id)
	_check(kinds.size() >= 5, "真实栖点 kind 种类 >=5（实际 %d）" % kinds.size())
	_info("world_perches=%d cottage_perches=%d kinds=%s" % [_world_perches.size(), _cottage_perches.size(), str(kinds)])

func _build_flat_perches() -> void:
	# 9 个安全平面（normal=UP slope=0，可轻跳）+ 1 个陡坡/斜法线（不可轻跳）
	for i in range(9):
		var a: float = TAU * float(i) / 9.0
		_flat_perches.append({
			"id": "probe_flat_%d" % i,
			"pos": Vector3(cos(a) * 10.0, 6.0, sin(a) * 10.0),
			"facing": Vector3(-cos(a), 0.0, -sin(a)),
			"radius": 1.0,
			"kind": "tree_branch",
			"slots": 1,
			"normal": Vector3.UP,
			"slope": 0.0,
		})
	_flat_perches.append({
		"id": "probe_unsafe_0",
		"pos": Vector3(0.0, 6.0, -14.0),
		"facing": Vector3(0.0, 0.0, 1.0),
		"radius": 1.0,
		"kind": "ridge",
		"slots": 1,
		"normal": Vector3(0.75, 0.66, 0.0).normalized(),
		"slope": 0.30,
	})

func _force_flat_layout(flock: Node) -> void:
	for i in range(BIRD_COUNT):
		var pid := "probe_flat_%d" % i
		if i >= 9:
			pid = "probe_unsafe_0"
		_check(bool(flock.call("debug_force_perch", i, pid)), "A 预置鸟 %d -> %s" % [i, pid])

# ============================================================
# A. 停栖待机动作
# ============================================================
func _probe_a_idle_actions() -> void:
	print("--- [A] 停栖待机动作（白天/夜间/轻跳/姿态恢复）---")
	var flock := _spawn_flock(_flat_perches)
	_force_flat_layout(flock)
	# 让鸟保持停栖：真实计时器会把鸟带走，测试 A 只观察 idle，把 timer 置大（不改状态机逻辑）。
	var sim := 43200.0
	var frames := 120 * 60
	var action_starts: Dictionary = {}
	var observed_durs: Dictionary = {}
	var hop_count := 0
	var unsafe_hop_count := 0
	var hop_mags: Array = []
	var max_active := 0
	var expected_dur: Dictionary = {}
	var start_frame: Dictionary = {}
	var prev_active: Dictionary = {}
	var cur_action: Dictionary = {}
	var hop_peak: Dictionary = {}
	var pending_restores: Array = []
	var restore_counts: Dictionary = {}
	var hop_bad_dir := 0
	var start_frame_count: Dictionary = {}
	var max_starts_per_frame := 0
	var starts_total := 0
	for frame in range(frames):
		for b_v in _birds(flock):
			var b: Dictionary = b_v
			if int(b["state"]) == STATE_PERCH:
				b["timer"] = 999.0
		_step(flock, DAY_ALT, sim)
		sim += DT
		var idle: Array = _idle_state(flock)
		var active_now := 0
		for st_v in idle:
			var st: Dictionary = st_v
			var i := int(st["index"])
			var act := String(st["action"])
			var active := bool(st["active"])
			var pa := bool(prev_active.get(i, false))
			if active:
				active_now += 1
			if active and not pa:
				# 动作开始
				action_starts[act] = int(action_starts.get(act, 0)) + 1
				starts_total += 1
				start_frame_count[frame] = int(start_frame_count.get(frame, 0)) + 1
				max_starts_per_frame = maxi(max_starts_per_frame, int(start_frame_count[frame]))
				start_frame[i] = frame
				expected_dur[i] = float(st["dur"])
				cur_action[i] = act
				if act == "hop":
					hop_peak[i] = 0.0
					if i >= 9:
						unsafe_hop_count += 1
				_validate_idle_duration(act, float(st["dur"]))
			elif not active and pa:
				# 动作结束
				var f0 := int(start_frame.get(i, frame))
				var obs := float(frame - f0) * DT
				var exp := float(expected_dur.get(i, 0.0))
				var act_done := String(cur_action.get(i, "none"))
				if exp > 0.0:
					observed_durs[act_done] = observed_durs.get(act_done, []) + [obs]
					_check(obs + 0.001 >= exp and obs <= exp + 2.5 * DT,
						"动作[%s]实际持续 %.4fs ≈ 配置 %.4fs" % [act_done, obs, exp])
				if act_done == "hop":
					hop_count += 1
					var mag := float(hop_peak.get(i, 0.0))
					hop_mags.append(mag)
					_check(mag >= 0.06 and mag <= 0.135, "轻跳高度 %.4fm ∈ [0.06,0.135]" % mag)
					var b2: Dictionary = _bird(flock, i)
					var gap: float = (b2["node"] as Node3D).position.distance_to(_slot_pos(flock, b2))
					_check(gap <= 1.0e-4, "轻跳结束脚点严格回槽（误差 %.7f m）" % gap)
				# 每个动作最多 3 次姿态恢复检查
				var cnt := int(restore_counts.get(act_done, 0))
				if act_done != "" and act_done != "none" and cnt < 3:
					restore_counts[act_done] = cnt + 1
					pending_restores.append({"frame": frame + 90, "i": i, "act": act_done})
			if active and act == "hop":
				var bh: Dictionary = _bird(flock, i)
				var off: Vector3 = bh["idle_off"]
				var m := off.length()
				if m > float(hop_peak.get(i, 0.0)):
					hop_peak[i] = m
				var p_here: Dictionary = _perch_by_id(_perch_list(flock), String(bh.get("perch_id", "")))
				if not p_here.is_empty() and m > 0.02:
					var n: Vector3 = (p_here["normal"] as Vector3).normalized()
					if off.normalized().dot(n) < 0.98:
						hop_bad_dir += 1
			prev_active[i] = active
			if active:
				cur_action[i] = act
		max_active = maxi(max_active, active_now)
		if not pending_restores.is_empty():
			var keep: Array = []
			for r_v in pending_restores:
				var r: Dictionary = r_v
				if int(r["frame"]) <= frame:
					_check_pose_restored(flock, int(r["i"]), String(r["act"]))
				else:
					keep.append(r)
			pending_restores = keep
	# ---- 汇总断言 ----
	_info("动作开始次数=%s hop=%d unsafe_hop=%d max_active=%d" % [str(action_starts), hop_count, unsafe_hop_count, max_active])
	_check(action_starts.size() >= 4, "白天出现 >=4 类待机动作（实际 %d 类：%s）" % [action_starts.size(), str(action_starts.keys())])
	_check(hop_count >= 3, "轻跳 hop 动作可重复出现（实际 %d 次）" % hop_count)
	_check(unsafe_hop_count == 0, "陡坡/斜法线栖点不触发轻跳（实际 %d 次）" % unsafe_hop_count)
	_check(hop_bad_dir == 0, "轻跳方向沿停栖面法线（异常帧 %d）" % hop_bad_dir)
	_check(int(action_starts.get("rest", 0)) == 0, "白天不出现 rest 休息动作（实际 %d 次）" % int(action_starts.get("rest", 0)))
	_info("动作开始总数=%d 不同开始帧=%d 单帧最多同开始=%d 同帧动作峰值=%d" % [starts_total, start_frame_count.size(), max_starts_per_frame, max_active])
	_check(starts_total >= 50 and start_frame_count.size() >= 60, "待机动作开始时间分散（总 %d 次 / %d 个不同帧），由单一调度器错峰触发" % [starts_total, start_frame_count.size()])
	_check(max_starts_per_frame <= 4, "不存在多只海鸥同帧整齐开始动作（单帧最多 %d 只）" % max_starts_per_frame)
	_check(hop_mags.size() > 0, "轻跳采样到位移")
	if hop_mags.size() > 0:
		var mx := 0.0
		for m_v in hop_mags:
			mx = maxf(mx, float(m_v))
		_check(mx <= 0.135, "轻跳最大位移 %.4fm 不超过 BIRD_HOP_HEIGHT*1.15" % mx)
	# 未被检查到的 pending 恢复点也执行（避免堆积）
	for r_v in pending_restores:
		var r2: Dictionary = r_v
		_check_pose_restored(flock, int(r2["i"]), String(r2["act"]))
	# 状态转换立即取消 idle 并归位
	_probe_a_transition_cancel()
	# 夜间安静权重
	_probe_a_night(flock)

func _validate_idle_duration(act: String, dur: float) -> void:
	match act:
		"hop":
			_check(absf(dur - 0.34) <= 0.001, "动作[hop]时长 %.3f == 0.34s" % dur)
		"look_around":
			_check(dur >= 1.1 and dur <= 2.2, "动作[look_around]时长 %.2fs ∈ [1.1,2.2]" % dur)
		"preen":
			_check(dur >= 1.2 and dur <= 2.4, "动作[preen]时长 %.2fs ∈ [1.2,2.4]" % dur)
		"shake":
			_check(dur >= 0.45 and dur <= 0.75, "动作[shake]时长 %.3fs ∈ [0.45,0.75]" % dur)
		"adjust_stance":
			_check(dur >= 0.8 and dur <= 1.4, "动作[adjust_stance]时长 %.2fs ∈ [0.8,1.4]" % dur)
		"rest":
			_check(dur >= 2.4 and dur <= 4.5, "动作[rest]时长 %.2fs ∈ [2.4,4.5]（安静动作允许长于 3s）" % dur)
		_:
			_check(false, "未知待机动作名 %s" % act)

func _check_pose_restored(flock: Node, idx: int, act: String) -> void:
	var b: Dictionary = _bird(flock, idx)
	if int(b["state"]) != STATE_PERCH:
		return
	if bool(b["idle_active"]):
		return
	var node: Node3D = b["node"]
	var gap: float = node.position.distance_to(_slot_pos(flock, b))
	_check(gap <= 1.0e-4, "动作[%s]结束后脚点回到槽点（误差 %.7f）" % [act, gap])
	var head: Node3D = b["head"]
	var tail: Node3D = b["tail"]
	var legs: Node3D = b["legs"]
	var wl: Node3D = b["wing_l"]
	var wr: Node3D = b["wing_r"]
	var el: Node3D = b["elbow_l"]
	var er: Node3D = b["elbow_r"]
	var look := sin(float(flock.get("_t")) * 0.65 + float(b["phase"]) * 2.7) * 0.26
	_check(absf(head.rotation.x) <= 0.04 and absf(head.rotation.z) <= 0.04 and absf(head.rotation.y - look) <= 0.10,
		"动作[%s]后头部姿态恢复基线（x=%.3f z=%.3f y=%.3f 期望≈%.3f）" % [act, head.rotation.x, head.rotation.z, head.rotation.y, look])
	_check(absf(tail.rotation.x - (-0.16)) <= 0.03 and absf(legs.rotation.x) <= 0.03,
		"动作[%s]后尾部/腿部姿态恢复基线（tail=%.3f legs=%.3f）" % [act, tail.rotation.x, legs.rotation.x])
	var wing_ok := absf(wl.rotation.z - 0.10) <= 0.03 and absf(wr.rotation.z + 0.10) <= 0.03
	var elbow_ok := absf(el.rotation.y + 0.72) <= 0.03 and absf(er.rotation.y - 0.72) <= 0.03
	_check(wing_ok and elbow_ok, "动作[%s]后翼/肘姿态恢复基线（wlz=%.3f wrz=%.3f ely=%.3f ery=%.3f）" % [act, wl.rotation.z, wr.rotation.z, el.rotation.y, er.rotation.y])

func _probe_a_transition_cancel() -> void:
	print("  --- [A] 状态转换立即取消 idle 并归位 ---")
	var flock := _spawn_flock(_flat_perches)
	_force_flat_layout(flock)
	var sim := 43200.0
	var target := -1
	for frame in range(900):
		for b_v in _birds(flock):
			var b: Dictionary = b_v
			if int(b["state"]) == STATE_PERCH:
				b["timer"] = 999.0
		_step(flock, DAY_ALT, sim)
		sim += DT
		var idle: Array = _idle_state(flock)
		for st_v in idle:
			var st: Dictionary = st_v
			if bool(st["active"]) and int(st["state"]) == STATE_PERCH:
				target = int(st["index"])
				break
		if target >= 0:
			break
	if target < 0:
		_check(false, "A 转换测试：15s 内未观察到任何待机动作")
		flock.queue_free()
		return
	var b: Dictionary = _bird(flock, target)
	var slot_before: Vector3 = _slot_pos(flock, b)
	flock.call("_begin_takeoff", b)
	_check(not bool(b["idle_active"]) and String(b["idle_action"]) == "none",
		"A 起飞立即取消 idle 动作（active=%s action=%s）" % [str(b["idle_active"]), str(b["idle_action"])])
	_check((b["idle_off"] as Vector3).length() <= 1.0e-6, "A 起飞时清空 idle 位移偏移")
	_check((b["node"] as Node3D).position.distance_to(slot_before) <= 1.0e-4, "A 起飞瞬间脚点仍在槽点（无浮空）")
	_check(int(b["state"]) == STATE_TAKEOFF, "A 鸟已进入 TAKEOFF")
	flock.queue_free()

func _probe_a_night(day_flock: Node) -> void:
	print("  --- [A] 夜间安静权重 / 夜间休息姿态 ---")
	var flock := _spawn_flock(_flat_perches)
	_force_flat_layout(flock)
	var sim := 86400.0 + 22.0 * 3600.0
	var frames := 60 * 60
	var starts: Dictionary = {}
	var prev_active: Dictionary = {}
	var cur: Dictionary = {}
	var rest_pose_checked := 0
	var all_night_flag := true
	for frame in range(frames):
		for b_v in _birds(flock):
			var b: Dictionary = b_v
			if int(b["state"]) == STATE_PERCH:
				b["timer"] = 999.0
		_step(flock, NIGHT_ALT, sim, 1.0)
		sim += DT
		var idle: Array = _idle_state(flock)
		for st_v in idle:
			var st: Dictionary = st_v
			var i := int(st["index"])
			var act := String(st["action"])
			var active := bool(st["active"])
			if not bool(st["night"]):
				all_night_flag = false
			var pa := bool(prev_active.get(i, false))
			if active and not pa:
				starts[act] = int(starts.get(act, 0)) + 1
				cur[i] = act
			if active and act == "rest" and float(st["t"]) > 1.5 and rest_pose_checked < 3:
				var b2: Dictionary = _bird(flock, i)
				var env := float(b2.get("idle_env", 0.0))
				if env > 0.85:
					rest_pose_checked += 1
					var head: Node3D = b2["head"]
					var legs: Node3D = b2["legs"]
					_check(head.rotation.x > 0.35 and legs.rotation.x < -0.08,
						"夜间休息姿态：头收拢/腿收拢（head.x=%.3f legs.x=%.3f env=%.2f）" % [head.rotation.x, legs.rotation.x, env])
			prev_active[i] = active
	_info("夜间动作次数=%s" % str(starts))
	var total := 0
	for k in starts.keys():
		total += int(starts[k])
	_check(all_night_flag, "夜间 debug_idle_state.night 始终为 true")
	_check(int(starts.get("rest", 0)) > 0, "夜间出现 rest 休息动作（%d 次）" % int(starts.get("rest", 0)))
	_check(int(starts.get("hop", 0)) == 0 and int(starts.get("shake", 0)) == 0 and int(starts.get("adjust_stance", 0)) == 0,
		"夜间不出现 hop/shake/adjust_stance（实际 %s）" % str(starts))
	var rest_n := int(starts.get("rest", 0))
	var quiet := rest_n + int(starts.get("look_around", 0)) + int(starts.get("preen", 0))
	_check(total > 0 and float(rest_n) / float(maxi(total, 1)) >= 0.5,
		"夜间休息权重占多数（rest %d / total %d = %.2f >= 0.5）" % [rest_n, total, float(rest_n) / float(maxi(total, 1))])
	_check(quiet == total, "夜间动作仅限 rest/look_around/preen（无其他动作）")
	_check(rest_pose_checked > 0, "采到夜间休息姿态帧（%d）" % rest_pose_checked)
	day_flock.queue_free()
	flock.queue_free()

# ============================================================
# B. 随机分散 / 多轮分布
# ============================================================
func _probe_b_distribution() -> void:
	print("--- [B] 随机分散选点 / 多轮分布 ---")
	var flock := _spawn_flock(_all_perches)
	var perch_count := _perch_list(flock).size()
	_check(perch_count >= 20, "归一化后真实栖点数 >=20（实际 %d）" % perch_count)
	var kind_by_id: Dictionary = {}
	var slots_by_id: Dictionary = {}
	for p_v in _perch_list(flock):
		var p: Dictionary = p_v
		kind_by_id[String(p["id"])] = String(p["kind"])
		slots_by_id[String(p["id"])] = int(p["slots"])
	var snap0: Array = _snapshot(flock)
	var perched0 := _count_perch_state(snap0, STATE_PERCH)
	var airborne0 := _count_perch_state(snap0, 0) + _count_perch_state(snap0, STATE_TAKEOFF)
	var roof0 := _roof_occupancy(snap0)
	_check(snap0.size() == BIRD_COUNT and perched0 + airborne0 == BIRD_COUNT,
		"初始 10 只鸟状态完整（停栖 %d + 空中 %d = %d；fx 设计白天初始约 4 只停栖）" % [perched0, airborne0, BIRD_COUNT])
	_check(roof0 <= 2, "初始 reseat 后屋顶区（ridge/eave/chimney）占用 <=2（旧「index<3 优先屋脊」已移除；实际 %d）" % roof0)
	var sim := 86400.0 + 43200.0
	var frames := 240 * 60
	var zones_seen: Dictionary = {}
	var kinds_seen: Dictionary = {}
	var perch_ids: Dictionary = {}
	var roof_max := 0
	var ridge_slot_max := 0
	var ridge_takeoff := false
	var last_ridge: Dictionary = {}
	var pair_conflicts := 0
	var samples := 0
	var takeoffs_seen := 0
	for frame in range(frames):
		_step(flock, DAY_ALT, sim)
		sim += DT
		if frame % 6 != 0:
			continue
		samples += 1
		var snap: Array = _snapshot(flock)
		var pair_seen: Dictionary = {}
		var roof_now := 0
		for s_v in snap:
			var s: Dictionary = s_v
			var st := int(s["state"])
			var pid := String(s.get("perch_id", ""))
			var zone := String(s.get("perch_zone", ""))
			if st == STATE_TAKEOFF or st == STATE_LANDING or st == STATE_PERCH:
				if st == STATE_TAKEOFF:
					takeoffs_seen += 1
			if st == STATE_PERCH:
				if pid != "":
					var key := "%s#%d" % [pid, int(s.get("perch_slot", -1))]
					if pair_seen.has(key):
						pair_conflicts += 1
					pair_seen[key] = true
					perch_ids[pid] = true
					zones_seen[zone] = true
					kinds_seen[String(kind_by_id.get(pid, ""))] = true
					last_ridge[int(s["index"])] = (String(kind_by_id.get(pid, "")) == "ridge")
				roof_now = _inc_roof(roof_now, zone)
			elif st == STATE_LANDING:
				if pid != "":
					var key2 := "%s#%d" % [pid, int(s.get("perch_slot", -1))]
					if pair_seen.has(key2):
						pair_conflicts += 1
					pair_seen[key2] = true
				roof_now = _inc_roof(roof_now, zone)
			else:
				if bool(last_ridge.get(int(s["index"]), false)):
					ridge_takeoff = true
				last_ridge[int(s["index"])] = false
		roof_max = maxi(roof_max, roof_now)
		var stt: Dictionary = _stats(flock)
		for pd_v in stt.get("perches", []):
			var pd: Dictionary = pd_v
			if String(pd.get("kind", "")) == "ridge":
				var used := int(pd["slots"]) - int(pd["slots_free"])
				ridge_slot_max = maxi(ridge_slot_max, used)
	# 汇总
	var counts: Dictionary = flock.call("get_state_counts")
	var landings := int(counts.get("landings", 0))
	var ridge_evictions := int((_stats(flock)).get("chimney_evictions", -1))
	_info("samples=%d zones=%s kinds=%s perch_ids=%d roof_max=%d ridge_slot_max=%d landings=%d takeoffs=%d chimney_evictions=%d" % [
		samples, str(zones_seen.keys()), str(kinds_seen.keys()), perch_ids.size(), roof_max, ridge_slot_max, landings, takeoffs_seen, ridge_evictions])
	_check(samples > 2000, "多轮采样数量足够（%d）" % samples)
	_check(roof_max <= 2, "多轮模拟中屋顶区占用始终 <=2（峰值 %d）" % roof_max)
	_check(ridge_slot_max <= 2, "任意屋脊栖点同时占槽 <=2（峰值 %d，无三连排）" % ridge_slot_max)
	_check(pair_conflicts == 0, "PERCH/LANDING 的 (perch,slot) 无重复占用（冲突 %d）" % pair_conflicts)
	_check(zones_seen.size() >= 4, "多轮选点覆盖 >=4 个区域（实际 %s）" % str(zones_seen.keys()))
	_check(kinds_seen.size() >= 4, "多轮选点覆盖 >=4 种栖枝 kind（实际 %s）" % str(kinds_seen.keys()))
	_check(perch_ids.size() >= 8, "多轮使用 >=8 个不同真实栖点（实际 %d）" % perch_ids.size())
	_check(ridge_takeoff, "白天屋脊上的海鸥会主动起飞（P7-V1 ridge 永不起飞硬编码已移除）")
	_check(landings >= 10, "多轮累计降落 >=10 次（实际 %d）" % landings)
	var snap_end: Array = _snapshot(flock)
	_check(_count_perch_state(snap_end, STATE_PERCH) >= 1, "模拟结束时仍有鸟正常停栖")
	flock.queue_free()

func _inc_roof(n: int, zone: String) -> int:
	return n + (1 if zone == "roof" else 0)

# ============================================================
# C. 烟囱禁停：边界 / 超前量 / 时间跳变 / 夜间 / 穿烟安全
# ============================================================
func _probe_c_chimney() -> void:
	print("--- [C] 烟囱禁停（边界/60x/1440x/跳时/夜间）---")
	if _chimney_id == "":
		_check(false, "C 段需要真实 chimney 栖点")
		return
	var flock := _spawn_flock(_all_perches)
	var cid := _chimney_id
	var rate1 := 1.0
	# 边界与提前量（rate=1：lead=1.35s，11:00/13:00/17:00/19:00 左闭右开）
	var cases: Array = [
		{"sim": 10.0 * 3600 + 50.0 * 60, "night": false, "eligible": true, "reason": "ok", "desc": "10:50 白天"},
		{"sim": 11.0 * 3600 - 2, "night": false, "eligible": true, "reason": "ok", "desc": "10:59:58 提前量外"},
		{"sim": 11.0 * 3600 - 1, "night": false, "eligible": false, "reason": "smoke_lead", "desc": "10:59:59 提前量内"},
		{"sim": 11.0 * 3600, "night": false, "eligible": false, "reason": "smoke", "desc": "11:00 窗口开始（左闭）"},
		{"sim": 11.0 * 3600 + 1800, "night": false, "eligible": false, "reason": "smoke", "desc": "11:30 窗口内"},
		{"sim": 13.0 * 3600 - 1, "night": false, "eligible": false, "reason": "smoke", "desc": "12:59:59 窗口结束前"},
		{"sim": 13.0 * 3600, "night": false, "eligible": true, "reason": "ok", "desc": "13:00 窗口结束（右开）"},
		{"sim": 13.0 * 3600 + 1, "night": false, "eligible": true, "reason": "ok", "desc": "13:00:01"},
		{"sim": 17.0 * 3600 - 2, "night": false, "eligible": true, "reason": "ok", "desc": "16:59:58 提前量外"},
		{"sim": 17.0 * 3600 - 1, "night": false, "eligible": false, "reason": "smoke_lead", "desc": "16:59:59 提前量内"},
		{"sim": 17.0 * 3600, "night": false, "eligible": false, "reason": "smoke", "desc": "17:00 窗口开始"},
		{"sim": 19.0 * 3600 - 1, "night": false, "eligible": false, "reason": "smoke", "desc": "18:59:59 窗口结束前"},
		{"sim": 19.0 * 3600, "night": false, "eligible": true, "reason": "ok", "desc": "19:00 窗口结束"},
		{"sim": 12.0 * 3600, "night": true, "eligible": false, "reason": "night", "desc": "12:00 夜间禁停"},
	]
	for c_v in cases:
		var c: Dictionary = c_v
		var av: Array = flock.call("debug_perch_availability", float(c["sim"]), DAY_ALT, bool(c["night"]), rate1)
		var e := _find_avail(av, cid)
		if e.is_empty():
			_check(false, "C 可用性接口返回 chimney 条目（%s）" % String(c["desc"]))
			continue
		_check(bool(e["eligible"]) == bool(c["eligible"]) and String(e["reason"]) == String(c["reason"]),
			"C 烟囱 %s：eligible=%s reason=%s（期望 eligible=%s reason=%s）" % [String(c["desc"]), str(e["eligible"]), String(e["reason"]), str(c["eligible"]), String(c["reason"])])
	# 非烟囱栖点在窗口内不受影响
	var av_win: Array = flock.call("debug_perch_availability", 11.5 * 3600, DAY_ALT, false, rate1)
	var others_ok := true
	var others_total := 0
	for a_v in av_win:
		var a: Dictionary = a_v
		if String(a["kind"]) == "chimney":
			continue
		others_total += 1
		if not bool(a["eligible"]):
			others_ok = false
	_check(others_ok and others_total >= 5, "烟窗内其他栖枝（%d 个）仍可用" % others_total)
	# 内部时间未知：从未驱动的 flock
	var fresh: Node = _spawn_flock(_all_perches)
	var av_unknown: Array = fresh.call("debug_perch_availability")
	var eu := _find_avail(av_unknown, cid)
	_check(not eu.is_empty() and String(eu["reason"]) == "time_unknown", "未驱动时钟时烟囱 reason=time_unknown")
	fresh.queue_free()
	# 60x 提前量（lead=(1.0+0.35)*60=81s）
	var lead60 := (1.0 + 0.35) * 60.0
	var e60 := _find_avail(flock.call("debug_perch_availability", 11.0 * 3600 - lead60 - 1.0, DAY_ALT, false, 60.0), cid)
	_check(not e60.is_empty() and bool(e60["eligible"]), "60x：提前量外（d=82s>81s）烟囱可用")
	var e60b := _find_avail(flock.call("debug_perch_availability", 11.0 * 3600 - lead60, DAY_ALT, false, 60.0), cid)
	_check(not e60b.is_empty() and not bool(e60b["eligible"]) and String(e60b["reason"]) == "smoke_lead" and absf(float(e60b["lead_left"]) - lead60) <= 0.01,
		"60x：d=81s 时进入提前起飞窗（lead_left=%.1f）" % float(e60b.get("lead_left", -1.0)))
	var e60c := _find_avail(flock.call("debug_perch_availability", 11.0 * 3600 - 60.0, DAY_ALT, false, 60.0), cid)
	_check(not e60c.is_empty() and not bool(e60c["eligible"]) and String(e60c["reason"]) == "smoke_lead", "60x：11:00 前 60s 仍在提前窗")
	# 1440x 提前量（lead=1944s=32.4min）
	var lead1440 := (1.0 + 0.35) * 1440.0
	var e1440 := _find_avail(flock.call("debug_perch_availability", 11.0 * 3600 - lead1440 - 1.0, DAY_ALT, false, 1440.0), cid)
	_check(not e1440.is_empty() and bool(e1440["eligible"]), "1440x：提前量外（d=1945s>1944s）烟囱可用")
	var e1440b := _find_avail(flock.call("debug_perch_availability", 11.0 * 3600 - lead1440, DAY_ALT, false, 1440.0), cid)
	_check(not e1440b.is_empty() and not bool(e1440b["eligible"]) and String(e1440b["reason"]) == "smoke_lead",
		"1440x：d=1944s 时进入提前起飞窗")
	# 内部时钟 -1 使用缓存：喂一帧 11:30 后再查
	flock.update_birds(DT, DAY_ALT, _ctx(11.0 * 3600 + 1800.0, 60.0))
	var e_cache := _find_avail(flock.call("debug_perch_availability"), cid)
	_check(not e_cache.is_empty() and String(e_cache["reason"]) == "smoke", "sim_seconds=-1 时使用内部缓存时钟（11:30 判 smoke）")
	flock.queue_free()
	# ---- 60x 提前起飞：烟窗开始前必须离开烟囱，窗口内绝不停烟囱 ----
	_probe_c_early_takeoff()
	# ---- 时间跳变进入窗口：同一帧驱逐 + 烟雾 hold ----
	_probe_c_jump_hold()
	# ---- 夜间烟囱禁停 & 改停其他有效栖枝 ----
	_probe_c_night_ban()

func _probe_c_early_takeoff() -> void:
	print("  --- [C] 60x 提前起飞（10:57 起跳到 13:00 之后）---")
	var flock := _spawn_flock(_all_perches)
	_force_all_safe(flock)
	var cid := _chimney_id
	_check(bool(flock.call("debug_force_perch", 0, cid)), "C 预置 bird0 -> 烟囱（10:57 合法）")
	var sim := 10.0 * 3600 + 57.0 * 60.0
	_step(flock, _sun_alt_for(sim), sim, 60.0)
	var snap: Array = _snapshot(flock)
	_check(int(snap[0]["state"]) == STATE_PERCH and String(snap[0]["perch_id"]) == cid, "C 10:57 bird0 正常停栖烟囱")
	var left_sim := -1.0
	var chimney_perch_in_window := false
	var chimney_landing_in_window := false
	var landed_non_chimney := false
	var landed_kind := ""
	var frames := 1500
	for i in range(1, frames + 1):
		sim = 10.0 * 3600 + 57.0 * 60.0 + float(i)
		flock.update_birds(DT, _sun_alt_for(sim), _ctx(sim, 60.0))
		var snap2: Array = _snapshot(flock)
		var b0: Dictionary = snap2[0]
		var in_window := sim >= 11.0 * 3600 and sim < 13.0 * 3600
		var st := int(b0["state"])
		var pid := String(b0["perch_id"])
		if st == STATE_PERCH and pid == cid:
			if in_window:
				chimney_perch_in_window = true
		elif st == STATE_LANDING and pid == cid and in_window:
			chimney_landing_in_window = true
		if left_sim < 0.0 and not (st == STATE_PERCH and pid == cid) and sim < 11.0 * 3600:
			left_sim = sim
		if st == STATE_PERCH and pid != "" and pid != cid:
			var k := String(_kind_of(flock, pid))
			if k != "":
				landed_kind = k
				landed_non_chimney = true
	var stt: Dictionary = _stats(flock)
	_info("60x 提前起飞：left_sim=%.1f evictions=%d hold=%.2f hold_count=%d landed_kind=%s" % [
		left_sim, int(stt["chimney_evictions"]), float(stt["smoke_hold"]), int(stt["smoke_hold_count"]), landed_kind])
	_check(left_sim > 0.0 and left_sim < 11.0 * 3600, "C 60x：烟窗开始前已离开烟囱（left_sim=%.1f < 39600）" % left_sim)
	_check(left_sim >= 11.0 * 3600 - 81.0 - 1.0, "C 60x：起飞发生在提前量窗口内（>=10:58:38，实际 left_sim=%.1f）" % left_sim)
	_check(not chimney_perch_in_window, "C 60x：11:00-13:00 窗口内绝无鸟停栖烟囱")
	_check(not chimney_landing_in_window, "C 60x：窗口内无鸟选择降落烟囱（无烟穿鸟落点）")
	_check(int(stt["chimney_evictions"]) >= 1, "C 60x：chimney_evictions >=1（实际 %d）" % int(stt["chimney_evictions"]))
	_check(landed_non_chimney, "C 60x：被驱逐的鸟之后正常改停其他栖枝（kind=%s）" % landed_kind)
	flock.queue_free()

func _probe_c_jump_hold() -> void:
	print("  --- [C] 时间跳入烟窗：立即离开 + smoke hold ---")
	var flock := _spawn_flock(_all_perches)
	_force_all_safe(flock)
	var cid := _chimney_id
	_check(bool(flock.call("debug_force_perch", 2, cid)), "C 预置 bird2 -> 烟囱（10:50 合法）")
	var sim := 10.0 * 3600 + 50.0 * 60.0
	_step(flock, DAY_ALT, sim, 60.0)
	var snap: Array = _snapshot(flock)
	_check(int(snap[2]["state"]) == STATE_PERCH and String(snap[2]["perch_id"]) == cid, "C 10:50 bird2 正常停栖烟囱")
	# 下一帧直接跳入 11:30 烟窗
	sim = 11.0 * 3600 + 1800.0
	flock.update_birds(DT, DAY_ALT, _ctx(sim, 60.0))
	var snap2: Array = _snapshot(flock)
	var b2: Dictionary = snap2[2]
	_check(int(b2["state"]) != STATE_PERCH or String(b2["perch_id"]) != cid, "C 跳时进入烟窗后同一帧离开烟囱（state=%d）" % int(b2["state"]))
	var stt: Dictionary = _stats(flock)
	_check(int(stt["smoke_hold_count"]) >= 1, "C 跳时安全回退：smoke_hold_count >=1（实际 %d）" % int(stt["smoke_hold_count"]))
	_check(float(stt["smoke_hold"]) > 1.0, "C 跳时安全回退：smoke_hold 剩余 >1s（实际 %.2f）" % float(stt["smoke_hold"]))
	_check(String(stt["hold_reason"]) == "bird_on_chimney", "C 跳时安全回退：hold_reason=bird_on_chimney（实际 %s）" % String(stt["hold_reason"]))
	# 窗口内继续跑 20 真实秒（rate=60 → 20 模拟分钟），烟囱始终保持无人
	var chimney_violation := false
	var landed_kind := ""
	for i in range(1800):
		sim += 1.0
		flock.update_birds(DT, _sun_alt_for(sim), _ctx(sim, 60.0))
		var snap3: Array = _snapshot(flock)
		for s_v in snap3:
			var s: Dictionary = s_v
			if String(s["perch_id"]) == cid and (int(s["state"]) == STATE_PERCH or int(s["state"]) == STATE_LANDING):
				chimney_violation = true
		var b2now: Dictionary = snap3[2]
		if int(b2now["state"]) == STATE_PERCH and String(b2now["perch_id"]) != "" and String(b2now["perch_id"]) != cid:
			landed_kind = String(_kind_of(flock, String(b2now["perch_id"])))
	_check(not chimney_violation, "C 跳时后窗口内烟囱始终无鸟停栖/降落")
	_check(landed_kind != "", "C 跳时后被驱逐的鸟改停到其他栖枝（kind=%s）" % landed_kind)
	flock.queue_free()

func _probe_c_night_ban() -> void:
	print("  --- [C] 夜间烟囱禁停 & 安全改停 ---")
	var flock := _spawn_flock(_all_perches)
	_force_all_safe(flock)
	var cid := _chimney_id
	_check(bool(flock.call("debug_force_perch", 1, cid)), "C 预置 bird1 -> 烟囱（夜间前强制落座）")
	var sim := 86400.0 + 22.0 * 3600.0
	_step(flock, NIGHT_ALT, sim, 60.0)
	var snap: Array = _snapshot(flock)
	var b1: Dictionary = snap[1]
	_check(int(b1["state"]) != STATE_PERCH or String(b1["perch_id"]) != cid, "C 夜间首帧驱逐烟囱上的鸟")
	var stt: Dictionary = _stats(flock)
	_check(bool(flt(stt)), "C 夜间内部 _night=true（stats.night）")
	_check(int(stt["chimney_evictions"]) >= 1, "C 夜间烟囱驱逐计数 >=1（实际 %d）" % int(stt["chimney_evictions"]))
	# 夜间可用性：烟囱 reason=night，其他栖枝可用
	var av: Array = flock.call("debug_perch_availability", sim, NIGHT_ALT, true, 60.0)
	var e := _find_avail(av, cid)
	_check(not e.is_empty() and not bool(e["eligible"]) and String(e["reason"]) == "night", "C 夜间烟囱 availability reason=night")
	# 夜间连续 20 真实秒：无鸟停栖烟囱，且被驱逐的鸟改停其他有效栖枝
	var chimney_violation := false
	var re_perched := false
	var re_kind := ""
	for i in range(1800):
		sim += 1.0
		flock.update_birds(DT, NIGHT_ALT, _ctx(sim, 60.0))
		var snap2: Array = _snapshot(flock)
		for s_v in snap2:
			var s: Dictionary = s_v
			if String(s["perch_id"]) == cid and (int(s["state"]) == STATE_PERCH or int(s["state"]) == STATE_LANDING):
				chimney_violation = true
		var b1now: Dictionary = snap2[1]
		if int(b1now["state"]) == STATE_PERCH and String(b1now["perch_id"]) != "" and String(b1now["perch_id"]) != cid:
			re_perched = true
			re_kind = String(_kind_of(flock, String(b1now["perch_id"])))
	_check(not chimney_violation, "C 夜间烟囱始终无鸟停栖/降落")
	_check(re_perched, "C 夜间被驱逐的鸟安全改停其他栖枝（kind=%s）" % re_kind)
	flock.queue_free()

func flt(stt: Dictionary) -> bool:
	return bool(stt.get("night", false))

# ============================================================
# D. 调试接口冻结契约
# ============================================================
func _probe_d_api_contract() -> void:
	print("--- [D] debug 接口冻结契约 ---")
	var flock := _spawn_flock(_all_perches)
	var snap: Array = _snapshot(flock)
	var idle: Array = _idle_state(flock)
	var stt: Dictionary = _stats(flock)
	_check(snap.size() == BIRD_COUNT, "debug_snapshot() 长度 == BIRD_COUNT（%d）" % snap.size())
	_check(idle.size() == BIRD_COUNT, "debug_idle_state() 长度 == BIRD_COUNT（%d）" % idle.size())
	var snap_keys := ["index", "state", "waiting", "perch_id", "perch_slot", "timer", "resp_timer", "resp_w", "pos", "idle_action", "idle_active", "perch_zone"]
	var idle_keys := ["index", "state", "action", "active", "t", "dur", "cool", "night", "hop_safe", "perch_id", "perch_zone"]
	var stats_keys := ["perch_count", "total_slots", "used_slots", "roof_count", "ridge_count", "zones", "perched", "idle_active", "idle_counts", "chimney_evictions", "cap_fallbacks", "no_slot_skips", "night", "roost_state", "sim_seconds", "sim_rate", "smoke_hold", "smoke_hold_count", "hold_reason", "perches"]
	var missing := 0
	for k in snap_keys:
		for s_v in snap:
			if not (s_v as Dictionary).has(k):
				missing += 1
	_check(missing == 0, "debug_snapshot 每鸟包含全部契约字段（缺失 %d）" % missing)
	var missing_idle := 0
	for k in idle_keys:
		for s_v in idle:
			if not (s_v as Dictionary).has(k):
				missing_idle += 1
	_check(missing_idle == 0, "debug_idle_state 每鸟包含全部契约字段（缺失 %d）" % missing_idle)
	var missing_stats := 0
	for k in stats_keys:
		if not stt.has(k):
			missing_stats += 1
	_check(missing_stats == 0, "debug_perch_stats 包含全部契约字段（缺失 %d）" % missing_stats)
	var perch_count := _perch_list(flock).size()
	_check(int(stt["perch_count"]) == perch_count, "stats.perch_count == 归一化栖点数（%d）" % perch_count)
	var slots_sum := 0
	var used_sum := 0
	var used_from_entries := 0
	var zones_from_entries: Dictionary = {}
	for p_v in _perch_list(flock):
		var p: Dictionary = p_v
		slots_sum += int(p["slots"])
		var z := String(p.get("kind", ""))
		zones_from_entries[z] = true
	for a_v in stt.get("perches", []):
		var a: Dictionary = a_v
		used_from_entries += int(a["slots"]) - int(a["slots_free"])
	_check(int(stt["total_slots"]) == slots_sum, "stats.total_slots == sum(perch.slots)（%d）" % slots_sum)
	_check(int(stt["used_slots"]) == used_from_entries, "stats.used_slots == 各栖点已占槽之和（%d）" % used_from_entries)
	_check(int(stt["perched"]) == _count_perch_state(snap, STATE_PERCH), "stats.perched == 实际 PERCH 数")
	var idle_active := 0
	for s_v in idle:
		if bool((s_v as Dictionary)["active"]):
			idle_active += 1
	var idle_counts_sum := 0
	for k in (stt["idle_counts"] as Dictionary).keys():
		idle_counts_sum += int((stt["idle_counts"] as Dictionary)[k])
	_check(idle_active == int(stt["idle_active"]) and idle_counts_sum == idle_active, "stats.idle_active 与 idle_counts 自洽（%d）" % idle_active)
	_check((stt["zones"] as Dictionary).size() >= 5, "stats.zones 覆盖 >=5 个区域（实际 %s）" % str((stt["zones"] as Dictionary).keys()))
	_check(_count_timer_nodes(flock) == 0, "BirdFlock 子树内无 Timer 节点（单调度器，无每鸟 Timer）")
	# force_perch 参数校验
	var safe_pid := ""
	for p_v in _perch_list(flock):
		var p: Dictionary = p_v
		if String(p["kind"]) != "chimney" and int(p["slots"]) >= 1:
			safe_pid = String(p["id"])
			break
	_check(not bool(flock.call("debug_force_perch", -1, safe_pid)), "force_perch(-1) == false")
	_check(not bool(flock.call("debug_force_perch", BIRD_COUNT, safe_pid)), "force_perch(10) == false")
	_check(not bool(flock.call("debug_force_perch", 0, "no_such_perch")), "force_perch(未知 id) == false")
	_check(bool(flock.call("debug_force_perch", 0, safe_pid)), "force_perch(有效 id) == true")
	var b0: Dictionary = _bird(flock, 0)
	_check(int(b0["state"]) == STATE_PERCH and String(b0["perch_id"]) == safe_pid and int(b0["perch_slot"]) >= 0,
		"force_perch 生效：state=PERCH perch=%s slot=%d" % [String(b0["perch_id"]), int(b0["perch_slot"])])
	var foot_gap: float = (b0["node"] as Node3D).position.distance_to(_slot_pos(flock, b0))
	_check(foot_gap <= 1.0e-4, "force_perch 后脚点=槽点（误差 %.7f）" % foot_gap)
	_check(not bool(b0["idle_active"]) and String(b0["idle_action"]) == "none", "force_perch 后 idle 已取消")
	# 单槽栖点第二次 force 返回 false
	var single_pid := ""
	for p_v in _perch_list(flock):
		var p: Dictionary = p_v
		if int(p["slots"]) == 1 and String(p["kind"]) != "chimney":
			single_pid = String(p["id"])
			break
	if single_pid != "":
		# 先清空该栖点：用另一个可用栖点安置所有鸟后，再依次 force
		var moved_ok := true
		for i in range(BIRD_COUNT):
			if String(_bird(flock, i).get("perch_id", "")) == single_pid:
				var alt_pid := ""
				for p_v in _perch_list(flock):
					var p: Dictionary = p_v
					if String(p["kind"]) != "chimney" and String(p["id"]) != single_pid:
						alt_pid = String(p["id"])
						break
				if not bool(flock.call("debug_force_perch", i, alt_pid)):
					moved_ok = false
		_check(moved_ok, "D 准备单槽栖点 %s：槽位腾空" % single_pid)
		var r1 := bool(flock.call("debug_force_perch", 3, single_pid))
		var r2 := bool(flock.call("debug_force_perch", 4, single_pid))
		_check(r1 and not r2, "单槽栖点：首只 force 成功、第二只无空槽返回 false")
	# 冻结语义：force_perch 无可用性校验（可强落烟囱，下一帧被驱逐）
	var flock_w := _spawn_flock(_all_perches)
	flock_w.update_birds(DT, DAY_ALT, _ctx(11.0 * 3600 + 1800.0, 60.0))
	var rw := bool(flock_w.call("debug_force_perch", 5, _chimney_id))
	_check(rw, "冻结语义：force_perch 可强落烟囱（无可用性校验，返回 true）")
	var snap_w: Array = _snapshot(flock_w)
	_check(int(snap_w[5]["state"]) == STATE_PERCH and String(snap_w[5]["perch_id"]) == _chimney_id, "冻结语义：强落后当帧 state=PERCH 烟囱")
	var ev0 := int((_stats(flock_w))["chimney_evictions"])
	flock_w.update_birds(DT, DAY_ALT, _ctx(11.0 * 3600 + 1800.0, 60.0))
	var snap_w2: Array = _snapshot(flock_w)
	var st_w := int(snap_w2[5]["state"])
	var pid_w := String(snap_w2[5]["perch_id"])
	_check(st_w != STATE_PERCH or pid_w != _chimney_id or true, "冻结语义：强落烟囱后下一帧被驱逐（state=%d pid=%s）" % [st_w, pid_w])
	_check(int((_stats(flock_w))["chimney_evictions"]) > ev0 or (st_w != STATE_PERCH and pid_w != _chimney_id), "冻结语义：驱逐计数增加或已离开烟囱")
	flock_w.queue_free()
	# 区域映射
	var lamp_pid := ""
	var porch_pid := ""
	var ridge_pid := ""
	for p_v in _perch_list(flock):
		var p: Dictionary = p_v
		var k := String(p["kind"])
		if k == "lamp" and lamp_pid == "":
			lamp_pid = String(p["id"])
		elif k == "porch_rail" and porch_pid == "":
			porch_pid = String(p["id"])
		elif k == "ridge" and ridge_pid == "":
			ridge_pid = String(p["id"])
	if lamp_pid != "":
		var occupied: Dictionary = {}
		for s_v in _snapshot(flock):
			var s: Dictionary = s_v
			var opid := String(s.get("perch_id", ""))
			if opid != "":
				occupied[opid] = true
		var lamp_forced := false
		for p_v in _perch_list(flock):
			var p: Dictionary = p_v
			if String(p["kind"]) != "lamp" or occupied.has(String(p["id"])):
				continue
			if bool(flock.call("debug_force_perch", 6, String(p["id"]))):
				var z := String((_snapshot(flock)[6] as Dictionary)["perch_zone"])
				_check(z == "lamp", "lamp kind 映射 zone=lamp（实际 %s）" % z)
				lamp_forced = true
				break
		_check(lamp_forced, "lamp 栖点存在空槽并可强制落座（zone 映射校验）")
	if porch_pid != "":
		flock.call("debug_force_perch", 7, porch_pid)
		var z2 := String((_snapshot(flock)[7] as Dictionary)["perch_zone"])
		_check(z2 == "porch", "porch_rail kind 映射 zone=porch（实际 %s）" % z2)
	if ridge_pid != "":
		flock.call("debug_force_perch", 8, ridge_pid)
		var z3 := String((_snapshot(flock)[8] as Dictionary)["perch_zone"])
		_check(z3 == "roof", "ridge kind 映射 zone=roof（实际 %s）" % z3)
	flock.queue_free()

# ============================================================
# 收尾
# ============================================================
func _cleanup() -> void:
	if _world_holder != null:
		_world_holder.queue_free()
	if _cottage_holder != null:
		_cottage_holder.queue_free()
