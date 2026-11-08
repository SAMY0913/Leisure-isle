extends SceneTree
## P8.2-03 强风 CPU 优化的等价性/回归探针（headless，不截图）：
##   D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe --headless --path D:/休闲小岛幻境/游戏工程 --script res://tools/probe_p82_wind_cpu.gd
## 目的（优化只允许改"怎么算/何时写"，不允许改视觉结果）：
##   Phase A 纯函数等价：swing_wind_targets_into / swing_spring_step_into 与被测纯函数逐位一致；
##           落叶/萤火参数缓存与逐帧重算的偏差上界（缓存只在输入变化 < 写入阈值时复用）。
##   Phase B 集成等价：真实 isle.tscn 上驱动风场渐变，节点属性必须在门控阈值内跟住纯函数值
##           （证明"只在变化时写"不会留下陈旧值），秋千夹紧/连续性/弹簧轨迹与纯函数一致。
## 退出码：0 = 全部通过；1 = 有失败。

const MainScene := preload("res://isle.tscn")
const MainScript := preload("res://scripts/main.gd")
const Season := preload("res://scripts/isle_season.gd")

const DT := 1.0 / 60.0
const WD_135 := Vector2(0.70710678, 0.70710678)
const WD_225 := Vector2(-0.70710678, 0.70710678)
const WD_UP := Vector2(0.0, -1.0)

var _pass := 0
var _fail := 0
var _fails: Array = []
var m: Node = null
var _leaf_pm: ParticleProcessMaterial = null
var _ff_node: GPUParticles3D = null
var _ff_mat: StandardMaterial3D = null
var _ff_pm: ParticleProcessMaterial = null
var _pivot: Node3D = null

func _initialize() -> void:
	print("=== P8.2-03 WIND CPU PROBE START ===")
	await process_frame
	_phase_pure_equiv()
	m = MainScene.instantiate()
	get_root().add_child(m)
	await process_frame
	await process_frame
	m.set_process(false)
	m.set("_paused", true)
	_phase_bind()
	_phase_leaf_cache()
	_phase_firefly_gate()
	_phase_swing_runtime()
	var total := _pass + _fail
	print("=== P8.2-03 WIND CPU PROBE RESULT: ", "PASS" if _fail == 0 else "FAIL",
		" pass=", _pass, " fail=", _fail, " checks=", total, " ===")
	for msg in _fails:
		print("[FAILED] ", msg)
	quit(0 if _fail == 0 else 1)

func _check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("  [OK] ", msg)
	else:
		_fail += 1
		_fails.append(msg)
		print("  [FAIL] ", msg)

# ============================================================
# Phase A：纯函数等价
# ============================================================
func _phase_pure_equiv() -> void:
	print("--- PHASE A: PURE FUNCTION EQUIVALENCE ---")
	# A1 swing_wind_targets_into == swing_wind_targets（逐字段完全一致）
	var worst := 0.0
	var n := 0
	for wv in [0.0, 0.2, 0.4, 0.6, 0.8, 0.92, 1.0]:
		for wd in [WD_135, WD_225, WD_UP, Vector2.ZERO]:
			for t in [0.0, 0.7, 3.1, 11.9, 47.3]:
				var ref: Dictionary = MainScript.swing_wind_targets(wv, wd, t)
				var out: Dictionary = {"roll": 0.0, "pitch": 0.0, "acc": 0.0, "gust": 1.0, "tr": 0.0}
				MainScript.swing_wind_targets_into(out, wv, wd, t)
				for k in ["roll", "pitch", "acc", "gust", "tr"]:
					worst = maxf(worst, absf(float(ref[k]) - float(out[k])))
				n += 1
	_check(worst < 1e-12, "A1 swing_wind_targets_into 与 swing_wind_targets 逐字段一致（%d 组，最大差 %s）" % [n, str(worst)])
	# A2 swing_spring_step_into == swing_spring_step
	var worst2 := 0.0
	var n2 := 0
	for x in [-0.3, 0.0, 0.15]:
		for v in [-2.0, 0.0, 3.0]:
			for tg in [-0.45, 0.0, 0.42]:
				for dt in [DT, 0.0, 0.05, 0.2]:
					var ref2: Array = MainScript.swing_spring_step(x, v, tg, dt)
					var out2: Array = [0.0, 0.0]
					MainScript.swing_spring_step_into(out2, x, v, tg, dt)
					worst2 = maxf(worst2, absf(float(ref2[0]) - float(out2[0])))
					worst2 = maxf(worst2, absf(float(ref2[1]) - float(out2[1])))
					n2 += 1
	_check(worst2 < 1e-12, "A2 swing_spring_step_into 与 swing_spring_step 逐位一致（%d 组，最大差 %s）" % [n2, str(worst2)])
	# A3 复用容器不会带入上一次调用结果
	var out3: Array = [123.0, -456.0]
	MainScript.swing_spring_step_into(out3, 0.0, 0.0, 0.1, DT)
	var a3 := [float(out3[0]), float(out3[1])]
	MainScript.swing_spring_step_into(out3, 0.9, -1.0, -0.1, DT)
	_check(float(out3[0]) != a3[0] or float(out3[1]) != a3[1], "A3 复用容器每次被完整覆写（无上次状态残留）")
	# A4 落叶参数缓存误差上界：按线上同一条件（|Δwv|<=0.0005 且 |Δwd|^2<=2.5e-7 时复用）
	var cache: Dictionary = {}
	var cwv := -999.0
	var cwd := Vector2(0.0, -1.0)
	var valid := false
	var max_g := 0.0
	var max_d := 0.0
	var max_a := 0.0
	var step := 0.0002
	var wv2 := 0.0
	while wv2 <= 1.0:
		var wd2 := WD_135
		if not valid or absf(wv2 - cwv) > 0.0005 or wd2.distance_squared_to(cwd) > 0.00000025:
			cache = MainScript.wind_leaf_params(wv2, wd2)
			cwv = wv2
			cwd = wd2
			valid = true
		var fresh: Dictionary = MainScript.wind_leaf_params(wv2, wd2)
		var cg: Vector3 = cache["gravity"]
		var fg: Vector3 = fresh["gravity"]
		var cd: Vector3 = cache["direction"]
		var fd: Vector3 = fresh["direction"]
		max_g = maxf(max_g, cg.distance_to(fg))
		max_d = maxf(max_d, cd.distance_to(fd))
		max_a = maxf(max_a, absf(float(cache["angular_max"]) - float(fresh["angular_max"])))
		wv2 += step
	_check(max_g < 0.02 and max_d < 0.02 and max_a < 1.5,
		"A4 落叶缓存与逐帧重算偏差上界（gravity %.4f < 0.02, direction %.4f < 0.02, angular %.3f < 1.5）" % [max_g, max_d, max_a])
	# A5 萤火 activity 缓存误差上界（线上同条件：|Δweather_f|<=0.0005）
	var acache: Dictionary = {}
	var awf := -999.0
	var avalid := false
	var m_ratio := 0.0
	var m_box := 0.0
	var m_spd := 0.0
	var m_alb := 0.0
	var m_life := 0.0
	for wi in range(0, 101):
		var w := float(wi) / 100.0
		for ri in range(0, 3):
			var rain := float(ri) * 0.5
			var wf: float = MainScript.firefly_wind_ratio(1.0, rain, 0.0, w, 0.1)
			if not avalid or absf(wf - awf) > 0.0005:
				acache = MainScript.firefly_wind_activity(wf)
				awf = wf
				avalid = true
			var afresh: Dictionary = MainScript.firefly_wind_activity(wf)
			m_ratio = maxf(m_ratio, absf(float(acache["amount_ratio"]) - float(afresh["amount_ratio"])))
			var ab: Vector3 = acache["box_extents"]
			var ab2: Vector3 = afresh["box_extents"]
			m_box = maxf(m_box, ab.distance_to(ab2))
			m_spd = maxf(m_spd, absf(float(acache["speed_scale"]) - float(afresh["speed_scale"])))
			var ac: Color = acache["albedo"]
			var ac2: Color = afresh["albedo"]
			m_alb = maxf(m_alb, maxf(absf(ac.r - ac2.r), maxf(absf(ac.g - ac2.g), absf(ac.b - ac2.b))))
			m_life = maxf(m_life, absf(float(acache["lifetime"]) - float(afresh["lifetime"])))
	_check(m_ratio < 0.002 and m_box < 0.02 and m_spd < 0.002 and m_alb < 0.003 and m_life < 0.02,
		"A5 萤火 activity 缓存偏差上界（ratio %.4f box %.4f speed %.4f albedo %.4f life %.4f）" % [m_ratio, m_box, m_spd, m_alb, m_life])
	# A6 目标角夹紧范围不因 in-place 版本改变
	var tg_all_ok := true
	for wv3 in [0.0, 0.35, 0.6, 0.92, 1.0]:
		for wd3 in [WD_135, WD_225]:
			var out6: Dictionary = {}
			MainScript.swing_wind_targets_into(out6, wv3, wd3, 5.5)
			if float(out6["roll"]) > 0.42 + 1e-9 or float(out6["roll"]) < -0.18 - 1e-9:
				tg_all_ok = false
			if absf(float(out6["pitch"])) > 0.45 + 1e-9:
				tg_all_ok = false
	_check(tg_all_ok, "A6 in-place 目标角仍被夹紧到 roll∈[-0.18,0.42] / |pitch|<=0.45")

# ============================================================
# Phase B：真实场景集成
# ============================================================
func _phase_bind() -> void:
	print("--- PHASE B: BIND isle.tscn ---")
	var fx: Dictionary = m.get("_fx")
	var leaf: Dictionary = fx.get("leaves", {})
	var ff: Dictionary = fx.get("fireflies", {})
	_leaf_pm = leaf.get("pm", null) as ParticleProcessMaterial
	_ff_node = ff.get("node", null) as GPUParticles3D
	_ff_mat = ff.get("mat", null) as StandardMaterial3D
	_ff_pm = _ff_node.process_material as ParticleProcessMaterial if _ff_node != null else null
	_pivot = m.get("_swing_pivot") as Node3D
	_check(_leaf_pm != null, "B0 落叶 ProcessMaterial 存在")
	_check(_ff_node != null and _ff_mat != null and _ff_pm != null, "B0 萤火节点/材质/ProcessMaterial 存在")
	_check(_pivot != null, "B0 秋千吊点存在")
	# 深夜：fireflyI≈1.0；秋季
	m.set("_season_weights", [0.0, 0.0, 1.0, 0.0])
	m.set("_season_visuals", Season.visuals([0.0, 0.0, 1.0, 0.0]))
	var secs := float(m.get("_sim_seconds"))
	m.set("_sim_seconds", floorf(secs / 86400.0) * 86400.0 + 23.5 * 3600.0)
	m.set("_sun_alt", -0.5)

func _set_weather(wind: float, wd: Vector2, rain := 0.0, snow := 0.0, storm := 0.0) -> void:
	m.set("_weather_wind", wind)
	m.set("_weather_visual_wind", wind)
	m.set("_weather_wind_dir", wd)
	m.set("_weather_wind_dir_smooth", wd)
	m.set("_weather_rain", rain)
	m.set("_weather_snow", snow)
	m.set("_weather_storm", storm)

func _firefly_i() -> float:
	# 与线上同源：palette 的 fireflyI（深夜≈1.0）
	return clampf(float(m.get("_pal").get("fireflyI", 0.0)), 0.0, 1.0)

func _phase_leaf_cache() -> void:
	print("--- PHASE B: LEAF PARAMS (cached path) ---")
	var worst := 0.0
	var w := 0.0
	while w <= 1.0:
		_set_weather(w, WD_135)
		m.call("_update_weather_fx", 0.0)
		var fresh: Dictionary = MainScript.wind_leaf_params(w, WD_135)
		worst = maxf(worst, _leaf_pm.direction.distance_to(fresh["direction"]))
		worst = maxf(worst, _leaf_pm.gravity.distance_to(fresh["gravity"]))
		w += 0.02
	_check(worst < 0.002, "B1 风场渐变 0→1 时运行落叶参数跟住纯函数（最大偏差 %.5f < 0.002）" % worst)
	# 风向 90° 突变：缓存必须立即失效
	_set_weather(0.92, WD_135)
	m.call("_update_weather_fx", 0.0)
	var before := _leaf_pm.direction
	_set_weather(0.92, WD_225)
	m.call("_update_weather_fx", 0.0)
	var after := _leaf_pm.direction
	_check(before.distance_to(after) > 0.5, "B2 风向 135°→225° 突变后落叶方向立即更新（Δ=%.3f）" % before.distance_to(after))
	var fresh2: Dictionary = MainScript.wind_leaf_params(0.92, WD_225)
	_check(_leaf_pm.direction.distance_to(fresh2["direction"]) < 0.002, "B2 更新值与纯函数一致")
	# 同一风场连续 240 帧不漂移
	var d0 := _leaf_pm.direction
	var g0 := _leaf_pm.gravity
	for i in range(240):
		m.call("_update_weather_fx", DT)
	_check(_leaf_pm.direction.distance_to(d0) < 0.0006 and _leaf_pm.gravity.distance_to(g0) < 0.0006,
		"B3 同一风场连续 240 帧落叶参数不漂移（缓存复用正确）")

func _phase_firefly_gate() -> void:
	print("--- PHASE B: FIREFLY WRITE GATING ---")
	_set_weather(0.0, WD_135)
	m.call("_update_lighting")
	var ffi := _firefly_i()
	var worst_ratio := 0.0
	var worst_box := 0.0
	var worst_spd := 0.0
	var worst_alb := 0.0
	# 风 / 雨 / 雪 / 风暴 逐步变化（包含雨雪组合），每步 3 帧，验证门控不会留下陈旧值
	var steps := 0
	for wi in range(0, 21):
		var w := float(wi) / 20.0
		for ri in range(0, 5):
			var rain := float(ri) * 0.25
			var snow := 0.35 if ri == 4 else 0.0
			var storm := 0.5 if ri == 3 else 0.0
			_set_weather(w, WD_135, rain, snow, storm)
			for k in range(3):
				m.call("_update_lighting")
			var ratio: float = MainScript.firefly_wind_ratio(ffi, rain, snow, w, storm)
			var act: Dictionary = MainScript.firefly_wind_activity(
				MainScript.firefly_wind_ratio(1.0, rain, snow, w, storm))
			worst_ratio = maxf(worst_ratio, absf(_ff_node.amount_ratio - ratio))
			worst_box = maxf(worst_box, _ff_pm.emission_box_extents.distance_to(act["box_extents"]))
			worst_spd = maxf(worst_spd, absf(_ff_node.speed_scale - float(act["speed_scale"])))
			var ab: Color = act["albedo"]
			worst_alb = maxf(worst_alb, maxf(absf(_ff_mat.albedo_color.r - ab.r),
				maxf(absf(_ff_mat.albedo_color.g - ab.g), absf(_ff_mat.albedo_color.b - ab.b))))
			steps += 1
	_check(worst_ratio < 0.004, "B4 风/雨/雪/风暴渐变时 amount_ratio 跟住纯函数（最大偏差 %.4f < 0.004，%d 组）" % [worst_ratio, steps])
	_check(worst_box < 0.006, "B5 emission_box_extents 跟住纯函数（最大偏差 %.4f 米）" % worst_box)
	_check(worst_spd < 0.004, "B6 speed_scale 跟住纯函数（最大偏差 %.4f）" % worst_spd)
	_check(worst_alb < 0.006, "B7 albedo 亮度跟住纯函数（最大偏差 %.4f）" % worst_alb)
	# 晴夜 ↔ 强风来回切换 30 次：发射态与可见量必须每次都正确切换（无门控滞后卡死）
	var flip_ok := true
	var clear_ratio := MainScript.firefly_wind_ratio(ffi, 0.0, 0.0, 0.0, 0.0)
	var strong_ratio: float = MainScript.firefly_wind_ratio(ffi, 0.0, 0.0, 0.92, 0.10)
	for i in range(30):
		_set_weather(0.0, WD_135)
		m.call("_update_lighting")
		if absf(_ff_node.amount_ratio - clear_ratio) > 0.004 or not _ff_node.emitting:
			flip_ok = false
		_set_weather(0.92, WD_135, 0.0, 0.0, 0.10)
		m.call("_update_lighting")
		if absf(_ff_node.amount_ratio - strong_ratio) > 0.004:
			flip_ok = false
	_check(flip_ok, "B8 晴夜↔强风反复切换 30 次，发射态与可见量每次正确（门控不滞后）")
	# 台风（ratio≈0）：发射关闭
	_set_weather(1.0, WD_135, 0.95, 0.0, 1.0)
	m.call("_update_lighting")
	_check(not _ff_node.emitting, "B9 台风级萤火 emitting=false（强风+降水合理归零）")
	# 复位到晴夜
	_set_weather(0.0, WD_135)
	m.call("_update_lighting")

func _phase_swing_runtime() -> void:
	print("--- PHASE B: SWING (in-place spring) ---")
	m.set("_p81wind_legacy", false)
	m.set("_swing_roll", 0.0)
	m.set("_swing_roll_v", 0.0)
	m.set("_swing_pitch", 0.0)
	m.set("_swing_pitch_v", 0.0)
	_set_weather(0.92, WD_135)
	m.set("_frame_t", 0.0)
	# 与纯函数逐帧重放对照：运行时应逐位等于"目标角 + 弹簧步"的纯函数轨迹
	var x_roll := 0.0
	var v_roll := 0.0
	var x_pitch := 0.0
	var v_pitch := 0.0
	var max_traj := 0.0
	var max_step := 0.0
	var prev_roll := 0.0
	var clamp_ok := true
	var ft := 0.0
	for i in range(600):
		ft += DT
		m.set("_frame_t", ft)
		m.call("_update_props", DT)
		var tg: Dictionary = MainScript.swing_wind_targets(0.92, WD_135, ft)
		var sp: Array = MainScript.swing_spring_step(x_pitch, v_pitch, float(tg["pitch"]), DT)
		x_pitch = float(sp[0])
		v_pitch = float(sp[1])
		var sr: Array = MainScript.swing_spring_step(x_roll, v_roll, float(tg["roll"]), DT)
		x_roll = float(sr[0])
		v_roll = float(sr[1])
		max_traj = maxf(max_traj, absf(float(m.get("_swing_roll")) - x_roll))
		max_traj = maxf(max_traj, absf(float(m.get("_swing_pitch")) - x_pitch))
		var idle: Vector2 = MainScript.swing_idle_rot(ft)
		var exp_roll := clampf(idle.y + x_roll, -0.18, 0.42)
		var exp_pitch := clampf(idle.x + x_pitch, -0.62, 0.62)
		# rotation 读回要经 quaternion→euler 反解（~1e-8 浮点误差），用 1e-6 判定
		clamp_ok = clamp_ok and absf(_pivot.rotation.z - exp_roll) < 1e-6 and absf(_pivot.rotation.x - exp_pitch) < 1e-6
		max_step = maxf(max_step, absf(_pivot.rotation.z - prev_roll))
		prev_roll = _pivot.rotation.z
	_check(max_traj < 1e-9, "B10 秋千弹簧状态与纯函数逐帧重放一致（最大差 %s）" % str(max_traj))
	_check(clamp_ok, "B11 秋千 rotation 恒等于夹紧后的 idle+弹簧角（无穿模）")
	_check(max_step < 0.05, "B12 秋千无单帧瞬移（最大单帧 %.4f rad < 0.05）" % max_step)
	# 风向反转：半周期内平滑转向，不出现突然换向
	m.set("_weather_wind_dir", WD_225)
	m.set("_weather_wind_dir_smooth", WD_225)
	var max_step2 := 0.0
	var pv := _pivot.rotation.z
	for i in range(120):
		ft += DT
		m.set("_frame_t", ft)
		m.call("_update_props", DT)
		max_step2 = maxf(max_step2, absf(_pivot.rotation.z - pv))
		pv = _pivot.rotation.z
	_check(max_step2 < 0.05, "B13 风向 90° 反转后秋千平滑换向（最大单帧 %.4f rad）" % max_step2)
	m.set("_p81wind_legacy", false)
