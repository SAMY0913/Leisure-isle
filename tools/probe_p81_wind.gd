extends SceneTree
## P8.1-05 强风视觉验收探针（headless，不截图、不开窗口）：
##   D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe --headless --path D:/休闲小岛幻境/游戏工程 --script res://tools/probe_p81_wind.gd
## 覆盖任务书 §5 与计划书 §8 的 F1—F10 / S1—S6：
##   Phase A 纯函数层（与线上同一实现）：落叶风场输运、冬季门控、萤火三通道、阵风包络、秋千弹簧；
##   Phase B 集成层（真实 isle.tscn，手动驱动 update）：落叶 ProcessMaterial、萤火可见参数、
##           秋千无风回归/强风极值/风向 90° 过渡/夹紧、节点与实例不重建（F5/F9）。
## F10 帧时间由窗口模式 --p81windperf 同 build A/B 测量（本探针校验 A/B 开关本身有效）。
## 退出码：0 = 全部通过；1 = 有失败。

const MainScene := preload("res://isle.tscn")
const MainScript := preload("res://scripts/main.gd")
const Season := preload("res://scripts/isle_season.gd")

const DT := 1.0 / 60.0
const WIND_CLEAR := 0.18
const WIND_STRONG := 0.92
const WIND_HURRICANE := 1.0
const WD_135 := Vector2(0.70710678, 0.70710678)
const WD_225 := Vector2(-0.70710678, 0.70710678)

var _pass := 0
var _fail := 0
var _fails: Array = []
var m: Node = null
var _leaf: Dictionary = {}
var _leaf_node: GPUParticles3D = null
var _leaf_pm: ParticleProcessMaterial = null
var _leaf_mat: StandardMaterial3D = null
var _ff: Dictionary = {}
var _ff_node: GPUParticles3D = null
var _ff_mat: StandardMaterial3D = null
var _ff_pm: ParticleProcessMaterial = null
var _pivot: Node3D = null
var _seat: Node3D = null

func _initialize() -> void:
	print("=== P8.1-05 WIND PROBE START ===")
	await process_frame
	_phase_pure()
	m = MainScene.instantiate()
	get_root().add_child(m)
	await process_frame
	await process_frame
	m.set_process(false)
	m.set("_paused", true)
	_phase_bind()
	_phase_leaf()
	_phase_firefly()
	_phase_swing()
	_phase_source_guard()
	_phase_node_identity()
	var total := _pass + _fail
	print("=== P8.1-05 WIND PROBE RESULT: ", "PASS" if _fail == 0 else "FAIL",
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

func _near(a: float, b: float, eps: float, msg: String) -> void:
	_check(absf(a - b) <= eps, "%s (实际 %.4f, 期望 %.4f ±%.4f)" % [msg, a, b, eps])

func _nearv(a: Vector3, b: Vector3, eps: float, msg: String) -> void:
	_check(a.distance_to(b) <= eps, "%s (实际 %s, 期望 %s)" % [msg, str(a), str(b)])

# ============================================================
# Phase A：纯函数（线上同一实现，无副作用）
# ============================================================
func _phase_pure() -> void:
	print("--- PHASE A: PURE FUNCTIONS ---")
	# F2/F3 落叶输运
	var lp_clear: Dictionary = MainScript.wind_leaf_params(WIND_CLEAR, WD_135)
	var g_clear: Vector3 = lp_clear["gravity"]
	var d_clear: Vector3 = lp_clear["direction"]
	_check(float(lp_clear["tr"]) <= 0.0001, "F2 clear(0.18) tr=0")
	_near(g_clear.y, -0.568, 0.002, "F2 clear gravity.y")
	_check(Vector2(g_clear.x, g_clear.z).length() < 0.11, "F2 clear 横向风载≈0.10")
	_check(d_clear.y > 0.95, "F1 clear 方向近垂直下落 (dir.y>0.95，实际 %.4f)" % d_clear.y)
	near_float_note("F2 clear dir", d_clear)
	var lp_s: Dictionary = MainScript.wind_leaf_params(WIND_STRONG, WD_135)
	var g_s: Vector3 = lp_s["gravity"]
	var d_s: Vector3 = lp_s["direction"]
	_near(float(lp_s["tr"]), 0.9914, 0.003, "F2 strong tr≈0.991")
	_near(g_s.y, -1.9804, 0.01, "F2 strong gravity.y（下落加速）")
	_check(Vector2(g_s.x, g_s.z).length() > 2.2, "F2 strong 横向风载>2.2")
	_check(Vector2(g_s.x, g_s.z).length() > 10.0 * Vector2(g_clear.x, g_clear.z).length(), "F2 横漂风载>clear 的 10 倍")
	_check(d_s.y < 0.36, "F2 strong 输运方向倾角>69°")
	_near(float(lp_s["angular_max"]), 397.94, 2.0, "F2 strong 自旋上限≈398")
	_check(float(lp_s["angular_min"]) < -350.0, "F2 strong 反向自旋下限<-350")
	var lp_r: Dictionary = MainScript.wind_leaf_params(WIND_STRONG, WD_225)
	var d_r: Vector3 = lp_r["direction"]
	_check(d_r.x < -0.5 and d_r.z > 0.5, "F3 风向 90° 改变后 direction.x<0, direction.z>0（新发射立即改向）")
	_check(d_r.y < 0.36, "F3 改向后仍为强风倾角")
	# F4 冬季落叶门控
	_near(MainScript.wind_leaf_gate(0.0), 1.0, 0.0001, "F4 winter_w=0 gate=1")
	_near(MainScript.wind_leaf_gate(0.5), 0.325, 0.001, "F4 winter_w=0.5 gate=0.325（平滑收量）")
	_near(MainScript.wind_leaf_gate(0.74), 0.001, 0.002, "F4 winter_w=0.74 gate≈0（全关）")
	_near(MainScript.wind_leaf_gate(1.0), 0.0, 0.0001, "F4 winter_w=1 gate=0")
	var tint := MainScript.wind_leaf_tint(Color(0.95, 0.52, 0.18, 0.92), 1.0)
	_check(tint.r > 0.9 and tint.g < 0.52 and tint.b < 0.2, "F4 冬季叶色向暖橙偏移（不出现绿叶）")
	# F6/F7 萤火三通道
	_near(MainScript.firefly_wind_ratio(1.0, 0.0, 0.0, WIND_CLEAR, 0.0), 1.0, 0.0001, "F6 clear 萤火 ratio=1")
	_near(MainScript.firefly_wind_ratio(1.0, 0.0, 0.0, WIND_STRONG, 0.10), 0.08358, 0.002, "F6 strong_wind 萤火 ratio≈0.084")
	_near(MainScript.firefly_wind_ratio(1.0, 0.30, 0.0, 0.36, 0.0), 0.43, 0.002, "F7 小雨 ratio≈0.43")
	var mix := MainScript.firefly_wind_ratio(1.0, 0.30, 0.0, WIND_STRONG, 0.10)
	_check(mix > 0.02, "F7 强风+小雨叠加仍保留少量萤火 (ratio=%.4f > 0.02)" % mix)
	_near(MainScript.firefly_wind_ratio(1.0, 0.86, 0.0, 0.64, 0.85), 0.0, 0.0001, "F7 雷暴 ratio=0")
	_near(MainScript.firefly_wind_ratio(1.0, 0.95, 0.0, 1.0, 1.0), 0.0, 0.0001, "F7 台风 ratio=0")
	# F8 可见参数
	var a1: Dictionary = MainScript.firefly_wind_activity(1.0)
	_check(bool(a1["emitting"]), "F8 ratio=1 emitting=true")
	_near(float(a1["lifetime"]), 9.0, 0.01, "F8 ratio=1 恢复原寿命 9s")
	_near(float(a1["amount_ratio"]), 1.0, 0.001, "F8 ratio=1 amount_ratio=1")
	var a0: Dictionary = MainScript.firefly_wind_activity(0.0)
	_check(not bool(a0["emitting"]), "F8 ratio=0 emitting=false")
	_near(float(a0["lifetime"]), 4.0, 0.01, "F8 低谷寿命缩到 4s（真正少算）")
	var a01: Dictionary = MainScript.firefly_wind_activity(0.1)
	var box: Vector3 = a01["box_extents"]
	_near(box.x, 3.9, 0.001, "F8 ratio=0.1 活动范围收窄到 3.9m")
	_near(float(a01["speed_scale"]), 0.505, 0.001, "F8 ratio=0.1 速度降到 0.505")
	_near(float(a01["lifetime"]), 5.0, 0.01, "F8 ratio=0.1 寿命 5.0s")
	var alb: Color = a01["albedo"]
	_near(alb.r, 1.3090, 0.002, "F8 ratio=0.1 亮度压到 0.595x")
	# S4 阵风包络
	var gmin := 9.0
	var gmax := -9.0
	var gsum := 0.0
	var gsum2 := 0.0
	var n := 0
	var t := 0.0
	while t < 30.0:
		var gv: float = MainScript.wind_gust(t, 1.0)
		gmin = minf(gmin, gv)
		gmax = maxf(gmax, gv)
		gsum += gv
		gsum2 += gv * gv
		n += 1
		t += DT
	var gmean := gsum / float(n)
	var gstd := sqrt(maxf(gsum2 / float(n) - gmean * gmean, 0.0))
	var amp := (gmax - gmin) * 0.5
	_check(amp >= 0.10 and amp <= 0.36, "S4 阵风半幅 %.3f 落在 10%%—25%%±包络" % amp)
	_check(gstd > 0.02, "S4 阵风非恒定（std=%.3f）" % gstd)
	_near(MainScript.wind_gust(3.0, 0.0), 1.0, 0.0001, "S4 tr=0 时阵风包络严格=1（无风回归基础）")
	# S2/S3/S6 秋千目标角
	var tg: Dictionary = MainScript.swing_wind_targets(WIND_STRONG, WD_135, 0.0)
	_check(float(tg["roll"]) >= 0.18 and float(tg["roll"]) <= 0.42, "S2 strong_wind roll 目标在下风向 [0.18,0.42]")
	_check(float(tg["pitch"]) < 0.0 and absf(float(tg["pitch"])) <= 0.45, "S2 strong_wind pitch 目标在限内")
	var tg2: Dictionary = MainScript.swing_wind_targets(WIND_STRONG, WD_225, 0.0)
	_check(float(tg2["roll"]) <= -0.10, "S2 风向反转后 roll 目标为负（朝上风侧）")
	var tg6: Dictionary = MainScript.swing_wind_targets(WIND_HURRICANE, WD_135, 3.0)
	_check(float(tg6["roll"]) <= 0.42 + 0.0001 and float(tg6["roll"]) >= -0.18 - 0.0001, "S6 台风级 roll 目标仍被夹紧")
	# S1 无风基准函数（P7-FINALIZE：无风被动摆幅从 ±0.42rad(24°) 收到 7°/2°）
	var idle0: Vector2 = MainScript.swing_idle_rot(0.0)
	_near(idle0.x, 0.0, 1e-7, "S1 idle(0).x=0")
	_near(idle0.y, sin(0.8) * MainScript.SWING_IDLE_ROLL, 1e-7, "S1 idle(0).z=sin(0.8)*SWING_IDLE_ROLL")
	var idle1: Vector2 = MainScript.swing_idle_rot(1.0)
	_near(idle1.x, sin(1.15) * MainScript.SWING_IDLE_PITCH, 1e-7, "S1 idle(1).x=sin(1.15)*SWING_IDLE_PITCH")
	# 用户验收：无风最大摆角 5–10°（单侧、相对自然悬垂）；用合成倾角 sqrt(pitch²+roll²) 也须 <=10°。
	var idle_max_pitch := 0.0
	var idle_max_tilt := 0.0
	for i in range(2000):
		var tt := float(i) * 0.01
		var iv: Vector2 = MainScript.swing_idle_rot(tt)
		idle_max_pitch = maxf(idle_max_pitch, absf(iv.x))
		idle_max_tilt = maxf(idle_max_tilt, sqrt(iv.x * iv.x + iv.y * iv.y))
	_check(idle_max_pitch >= deg_to_rad(5.0) and idle_max_pitch <= deg_to_rad(10.0),
		"S1 无风前后摆幅 5–10°（实际 %.2f°）" % rad_to_deg(idle_max_pitch))
	_check(idle_max_tilt <= deg_to_rad(10.0),
		"S1 无风合成最大倾角 <=10°（实际 %.2f°）" % rad_to_deg(idle_max_tilt))
	# 弹簧收敛
	var sx := 0.0
	var sv := 0.0
	var mx := 0.0
	for i in range(900):
		var res: Array = MainScript.swing_spring_step(sx, sv, 0.27, DT)
		sx = res[0]
		sv = res[1]
		mx = maxf(mx, sx)
	_near(sx, 0.27, 0.01, "S4 弹簧-阻尼收敛到目标角 0.27")
	_check(mx < 0.42, "S6 弹簧过冲仍小于 0.42 夹紧值")

func near_float_note(_tag: String, _v: Vector3) -> void:
	pass

# ============================================================
# Phase B 绑定：真实 isle.tscn
# ============================================================
func _phase_bind() -> void:
	print("--- PHASE B: BIND isle.tscn ---")
	_leaf = (m.get("_fx") as Dictionary).get("leaves", {})
	_leaf_node = _leaf.get("node", null) as GPUParticles3D
	_leaf_pm = _leaf.get("pm", null) as ParticleProcessMaterial
	_leaf_mat = _leaf.get("mat", null) as StandardMaterial3D
	_ff = (m.get("_fx") as Dictionary).get("fireflies", {})
	_ff_node = _ff.get("node", null) as GPUParticles3D
	_ff_mat = _ff.get("mat", null) as StandardMaterial3D
	_ff_pm = _ff.get("pm", null) as ParticleProcessMaterial
	_pivot = m.get("_swing_pivot") as Node3D
	if _pivot != null:
		_seat = _pivot.find_child("SwingSeat", true, false) as Node3D
	_check(_leaf_node != null and _leaf_pm != null and _leaf_mat != null, "B0 落叶 GPUParticles3D/ProcessMaterial/材质存在")
	_check(_ff_node != null and _ff_mat != null and _ff_pm != null, "B0 萤火 GPUParticles3D/ProcessMaterial/材质存在")
	_check(_pivot != null and _seat != null, "B0 秋千 Swing/SwingSeat 存在")

func _season(weights: Array) -> void:
	m.set("_season_weights", weights)
	m.set("_season_visuals", Season.visuals(weights))

func _set_weather(wind: float, wd: Vector2, rain := 0.0, snow := 0.0, storm := 0.0) -> void:
	m.set("_weather_wind", wind)
	m.set("_weather_visual_wind", wind)
	m.set("_weather_wind_dir", wd)
	m.set("_weather_wind_dir_smooth", wd)
	m.set("_weather_rain", rain)
	m.set("_weather_snow", snow)
	m.set("_weather_storm", storm)

func _fx_update() -> void:
	m.call("_update_weather_fx", 0.0)

func _lighting() -> void:
	m.call("_update_lighting")

# ============================================================
# 落叶：F1/F2/F3/F4/F5/F9
# ============================================================
func _phase_leaf() -> void:
	print("--- PHASE B: LEAVES ---")
	# F1 静态参数：寿命/预热/包围盒/发射方式
	_near(_leaf_node.lifetime, 5.0, 0.01, "F1 落叶 lifetime=5.0（落地前结束）")
	_near(_leaf_node.preprocess, 3.0, 0.01, "F1 落叶 preprocess=3.0")
	var aabb := _leaf_node.visibility_aabb
	_check(absf(aabb.size.x - 36.0) < 0.01 and absf(aabb.size.y - 20.0) < 0.01 and absf(aabb.size.z - 36.0) < 0.01,
		"F5 强风输运包围盒放大到 36x20x36（同一节点，不是新粒子系统）")
	_near(_leaf_pm.spread, 50.0, 0.01, "F2 风向 spread 收紧到 50°")
	var ramp_tex := _leaf_pm.color_ramp as GradientTexture1D
	var ramp: Gradient = ramp_tex.gradient if ramp_tex != null else null
	_check(ramp != null, "F1 落叶 color_ramp 存在")
	if ramp != null:
		_near(ramp.offsets[2], 0.55, 0.001, "F1 color_ramp 在 offset 0.55 开始淡出")
		_near(ramp.colors[2].a, 0.30, 0.01, "F1 offset 0.55 alpha=0.30（接地前近透明）")
		_near(ramp.colors[3].a, 0.0, 0.001, "F1 offset 1.0 alpha=0（无地下残留）")
	# 秋季 + 晴天：发射与风场参数
	_season([0.0, 0.0, 1.0, 0.0])
	m.call("_apply_season_visuals")
	_check(_leaf_node.emitting, "F2 秋季晴天落叶发射")
	_near(_leaf_node.amount_ratio, 1.0, 0.01, "F2 秋季 leaf_fall=1 → amount_ratio=1")
	_set_weather(WIND_CLEAR, WD_135)
	_fx_update()
	var p_clear: Dictionary = MainScript.wind_leaf_params(WIND_CLEAR, WD_135)
	_nearv(_leaf_pm.gravity, p_clear["gravity"], 1e-4, "F2 运行时 gravity 与纯函数一致（clear）")
	_nearv(_leaf_pm.direction, p_clear["direction"], 1e-4, "F2 运行时 direction 与纯函数一致（clear）")
	_near(_leaf_pm.angular_velocity_max, 160.0, 0.6, "F2 晴天自旋上限≈160")
	# F2 强风：同一节点参数立即增强（不重建）
	var node_id := _leaf_node.get_instance_id()
	_set_weather(WIND_STRONG, WD_135)
	_fx_update()
	var p_s: Dictionary = MainScript.wind_leaf_params(WIND_STRONG, WD_135)
	_nearv(_leaf_pm.gravity, p_s["gravity"], 1e-4, "F2 运行时 gravity 与纯函数一致（strong）")
	_nearv(_leaf_pm.direction, p_s["direction"], 1e-4, "F2 运行时 direction 与纯函数一致（strong）")
	_near(_leaf_pm.angular_velocity_max, 397.94, 0.6, "F2 强风自旋上限≈398")
	var gs: Vector3 = p_s["gravity"]
	var gc: Vector3 = p_clear["gravity"]
	_check(gs.y < gc.y - 1.0, "F2 强风下落明显更快（gravity.y 从 -0.57 到 -1.98）")
	_check(Vector2(gs.x, gs.z).length() > 5.0 * Vector2(gc.x, gc.z).length(), "F2 强风横向风载>5x")
	_check(_leaf_node.get_instance_id() == node_id, "F5 强风不新建落叶节点（实例 id 不变）")
	# F3 风向 90°
	_set_weather(WIND_STRONG, WD_225)
	_fx_update()
	var p_r: Dictionary = MainScript.wind_leaf_params(WIND_STRONG, WD_225)
	_nearv(_leaf_pm.direction, p_r["direction"], 1e-4, "F3 风向改变后 direction 与纯函数一致（新发射立即改向）")
	# F9：连续 120 帧更新不重启/不改寿命/不丢发射
	for i in range(120):
		_fx_update()
	_check(_leaf_node.emitting, "F9 连续 120 帧更新后落叶仍持续发射（无 restart 空窗）")
	_near(_leaf_node.lifetime, 5.0, 0.01, "F9 连续更新不改寿命、不重建粒子")
	# legacy A/B 开关有效（F10 的同 build 对照基础）
	m.set("_p81wind_legacy", true)
	_fx_update()
	var old_g := Vector3(WD_225.x * WIND_STRONG * 0.55, -0.55 - 0.10 * WIND_STRONG, WD_225.y * WIND_STRONG * 0.55)
	_nearv(_leaf_pm.gravity, old_g, 1e-4, "F10 legacy 开关恢复 P8.1-04 旧落叶风场（同 build A/B 有效）")
	m.set("_p81wind_legacy", false)
	_fx_update()
	# F4 冬季：门控关发射；返回秋季恢复
	_season([0.0, 0.0, 0.0, 1.0])
	m.call("_apply_season_visuals")
	_check(not _leaf_node.emitting, "F4 冬季 canopy_keep=0 时落叶 emitting=false（不再产叶）")
	_near(_leaf_node.amount_ratio, 0.0, 0.0001, "F4 冬季落叶 amount_ratio=0")
	for i in range(120):
		m.call("_apply_season_visuals")
	_check(not _leaf_node.emitting, "F4 冬季连续 120 次季节应用仍无新叶")
	_season([0.0, 0.0, 1.0, 0.0])
	m.call("_apply_season_visuals")
	_check(_leaf_node.emitting, "F4 离开冬季（回到秋季）落叶恢复发射")

# ============================================================
# 萤火虫：F6/F7/F8/F9
# ============================================================
func _phase_firefly() -> void:
	print("--- PHASE B: FIREFLIES ---")
	# 深夜 23:30（调色板 fireflyI=1.0，作为“原始可见量”基准）
	var secs := float(m.get("_sim_seconds"))
	var day := floorf(secs / 86400.0)
	m.set("_sim_seconds", day * 86400.0 + 23.5 * 3600.0)
	m.set("_sun_alt", -0.5)
	_set_weather(WIND_CLEAR, WD_135)
	_lighting()
	var ffi := _firefly_i()
	print("  [INFO] night fireflyI=%.3f" % ffi)
	_check(ffi > 0.95, "F6 深夜 fireflyI≈0.97（P8 原始基准）" )
	_check(_ff_node.emitting, "F6 晴夜萤火发射")
	_near(_ff_node.amount_ratio, ffi, 0.02, "F6 晴夜 amount_ratio≈fireflyI")
	var e0: Vector3 = _ff_pm.emission_box_extents
	_check(absf(e0.x - 12.0) < 0.05 and absf(e0.y - 2.4) < 0.05, "F6 晴夜活动范围=原始 12x2.4x12")
	_near(_ff_node.speed_scale, 1.0, 0.01, "F6 晴夜速度=原始 1.0")
	_near(_ff_node.lifetime, 9.0, 0.01, "F6 晴夜寿命=原始 9s")
	var clear_ratio := _ff_node.amount_ratio
	# 强风
	_set_weather(WIND_STRONG, WD_135)
	_lighting()
	var strong_ratio := _ff_node.amount_ratio
	_check(_ff_node.emitting, "F6 强风夜萤火仍微光可见（阈值化而非硬关）")
	_check(strong_ratio < clear_ratio * 0.25, "F6 强风可见量 <= 晴夜 1/4（实际 %.3f vs %.3f）" % [strong_ratio, clear_ratio])
	_near(strong_ratio, 0.0836, 0.02, "F6 强风 amount_ratio≈0.084")
	var e1: Vector3 = _ff_pm.emission_box_extents
	_check(e1.x < e0.x * 0.45 and e1.x > 2.0, "F6 强风活动范围明显收缩（%.2f m）" % e1.x)
	_check(_ff_node.speed_scale < 0.6, "F6 强风速度降到 <0.6")
	_check(_ff_node.lifetime < 5.2, "F8 强风寿命缩短到 <5.2s（真正减少在飞粒子）")
	# F7 强风+小雨
	_set_weather(WIND_STRONG, WD_135, 0.30, 0.0, 0.10)
	_lighting()
	_check(_ff_node.emitting and _ff_node.amount_ratio > 0.02, "F7 强风+小雨叠加仍有少量萤火 (ratio=%.4f)" % _ff_node.amount_ratio)
	# F8 极端天气
	_set_weather(WIND_HURRICANE, WD_135, 0.95, 0.0, 1.0)
	_lighting()
	_check(not _ff_node.emitting, "F8 台风级 ratio≈0 时 emitting=false")
	_near(_ff_node.lifetime, 4.0, 0.01, "F8 低谷寿命 4s（4—6s 内自然消失）")
	# F9 连续更新稳定
	_set_weather(WIND_STRONG, WD_135)
	_lighting()
	var ff_id := _ff_node.get_instance_id()
	var stable := true
	for i in range(120):
		_lighting()
		stable = stable and _ff_node.emitting and absf(_ff_node.amount_ratio - 0.0836) < 0.02
	_check(stable and _ff_node.get_instance_id() == ff_id, "F9 连续 120 次更新萤火参数稳定、同一节点（无 restart/重建）")

func _firefly_i() -> float:
	var pal: Dictionary = m.get("_pal")
	return clampf(float(pal.get("fireflyI", 0.0)), 0.0, 1.0)

# ============================================================
# 秋千：S1—S6
# ============================================================
func _step_props(n: int) -> void:
	for i in range(n):
		m.set("_frame_t", float(m.get("_frame_t")) + DT)
		m.call("_update_props", DT)

func _phase_swing() -> void:
	print("--- PHASE B: SWING ---")
	var world: Dictionary = m.get("_world")
	var base: Vector3 = world.get("big_tree", Vector3.ZERO)
	var pivot_world: Vector3 = _pivot.global_position
	var expect_pivot := base + Vector3(3.0, 5.55, 0.0)
	_nearv(pivot_world, expect_pivot, 0.02, "S5 悬挂点 world 位置不变 = base+(3,5.55,0)")
	# 几何：绳长/座椅尺寸（不得改）
	var seat_local := _seat.position
	var rope_len := absf(seat_local.y)
	_check(rope_len > 4.5 and rope_len < 6.0, "S5 绳长 %.3f m 未被改动（座椅仍在吊点下方）" % rope_len)
	_check(absf(seat_local.x) < 0.01 and absf(seat_local.z) < 0.01, "S5 座椅仍垂直悬挂在吊点正下方")
	var seat_mesh: BoxMesh = _seat.mesh as BoxMesh
	_check(seat_mesh != null, "S5 SwingSeat 使用 BoxMesh")
	if seat_mesh != null:
		_nearv(seat_mesh.size, Vector3(1.12, 0.07, 0.46), 0.001, "S5 座椅尺寸 1.12x0.07x0.46 不变（P7 契约）")
	# S1 无风回归：逐帧与旧公式（idle）误差 <1e-6
	m.set("_p81wind_legacy", false)
	m.set("_weather_visual_wind", 0.0)
	m.set("_swing_roll", 0.0)
	m.set("_swing_roll_v", 0.0)
	m.set("_swing_pitch", 0.0)
	m.set("_swing_pitch_v", 0.0)
	m.set("_frame_t", 0.0)
	_pivot.rotation = Vector3.ZERO
	var max_err := 0.0
	for i in range(120):
		var ft := float(m.get("_frame_t")) + DT
		m.set("_frame_t", ft)
		m.call("_update_props", DT)
		var idle: Vector2 = MainScript.swing_idle_rot(ft)
		max_err = maxf(max_err, absf(_pivot.rotation.x - idle.x))
		max_err = maxf(max_err, absf(_pivot.rotation.z - idle.y))
	_check(max_err < 1e-6, "S1 wind=0 时逐帧使用无风 idle 公式（最大误差 %.8f < 1e-6）" % max_err)
	# 真实绑定场景：wind=0 连续 20s 无风，秋千实际旋转不得回到旧的 ±24°。
	var real_max := 0.0
	for i in range(240):
		var ft2 := float(m.get("_frame_t")) + DT
		m.set("_frame_t", ft2)
		m.call("_update_props", DT)
		real_max = maxf(real_max, absf(float(_pivot.rotation.x)))
	_check(real_max <= deg_to_rad(10.0) + 1e-5,
		"B1 真实无风 20s 最大前后摆 <=10°（实际 %.2f°）" % rad_to_deg(real_max))
	# S2 强风受迫摆动：20s 统计
	_set_weather(WIND_STRONG, WD_135)
	m.set("_p81wind_legacy", false)
	m.set("_swing_roll", 0.0)
	m.set("_swing_roll_v", 0.0)
	m.set("_swing_pitch", 0.0)
	m.set("_swing_pitch_v", 0.0)
	var rolls: Array = []
	var heights: Array = []
	for i in range(1200):
		m.set("_frame_t", float(m.get("_frame_t")) + DT)
		m.call("_update_props", DT)
		rolls.append(float(_pivot.rotation.z))
		heights.append(_seat.global_position.y)
	var rsum := 0.0
	var rmax := -9.0
	var rmin := 9.0
	for r in rolls:
		rsum += float(r)
		rmax = maxf(rmax, float(r))
		rmin = minf(rmin, float(r))
	var rmean := rsum / float(rolls.size())
	_check(rmean >= 0.15 and rmean <= 0.42, "S2 strong_wind roll 均值在下风向 [0.15,0.42]（实际 %.3f）" % rmean)
	_check(rmax > rmean + 0.005 and rmean > rmin + 0.005, "S2 存在持续受迫摆动而非恒定角（max/mean/min=%.3f/%.3f/%.3f）" % [rmax, rmean, rmin])
	var hsum := 0.0
	var hmax := -9.0
	var hmin := 9.0
	for h in heights:
		hsum += float(h)
		hmax = maxf(hmax, float(h))
		hmin = minf(hmin, float(h))
	var hmean := hsum / float(heights.size())
	_check(hmax > hmean + 0.001 and hmean > hmin + 0.001, "S2 下风侧座面高度>平衡位置>上风侧（%.3f/%.3f/%.3f）" % [hmax, hmean, hmin])
	# S4 阵风起伏（roll 低频起伏肉眼可见：20s 内滑动极差）
	var lo := 9.0
	var hi := -9.0
	for i in range(300, 1200):
		lo = minf(lo, float(rolls[i]))
		hi = maxf(hi, float(rolls[i]))
	_check(hi - lo > 0.005, "S4 秋千摆角随阵风起伏（20s 末段极差 %.4f rad）" % (hi - lo))
	# S3 风向 90°：5s 平滑过渡，无单帧跳变
	_set_weather(WIND_STRONG, WD_135)
	m.set("_weather_wind_dir_smooth", WD_135)
	for i in range(60):
		m.set("_frame_t", float(m.get("_frame_t")) + DT)
		m.call("_update_props", DT)
	var r_before := float(_pivot.rotation.z)
	m.set("_weather_wind_dir", WD_225)
	m.set("_weather_wind_dir_smooth", WD_225)
	var max_step := 0.0
	var prev := r_before
	for i in range(300):
		m.set("_frame_t", float(m.get("_frame_t")) + DT)
		m.call("_update_props", DT)
		max_step = maxf(max_step, absf(float(_pivot.rotation.z) - prev))
		prev = float(_pivot.rotation.z)
	var r_after := float(_pivot.rotation.z)
	_check(max_step < 0.05, "S3 风向 90° 改变后无单帧瞬移（最大单帧变化 %.4f rad）" % max_step)
	_check(r_after < 0.02, "S3 5s 内 roll 跟随新风向转到上风侧（终值 %.3f）" % r_after)
	_check(r_before > 0.05, "S3 改变前 roll 在下风侧（%.3f）" % r_before)
	# S6 台风级夹紧
	_set_weather(WIND_HURRICANE, WD_135, 0.95, 0.0, 1.0)
	var clamp_ok := true
	for i in range(600):
		m.set("_frame_t", float(m.get("_frame_t")) + DT)
		m.call("_update_props", DT)
		if _pivot.rotation.z > 0.42 + 1e-6 or _pivot.rotation.z < -0.18 - 1e-6:
			clamp_ok = false
		if _pivot.rotation.x > 0.62 + 1e-6 or _pivot.rotation.x < -0.62 - 1e-6:
			clamp_ok = false
	_check(clamp_ok, "S6 台风级 roll∈[-0.18,0.42]、pitch∈[-0.62,0.62] 不穿模")
	# legacy 开关同样作用于秋千
	m.set("_p81wind_legacy", true)
	m.set("_weather_visual_wind", WIND_STRONG)
	m.call("_update_props", DT)
	_check(absf(float(_pivot.rotation.z) - MainScript.swing_idle_rot(float(m.get("_frame_t"))).y) < 1e-6, "F10 legacy 开关下秋千退回旧 idle 公式（A/B 有效）")
	m.set("_p81wind_legacy", false)

# ============================================================
# 源码守卫：F9 不重启、冬季门控存在
# ============================================================
func _phase_source_guard() -> void:
	print("--- PHASE B: SOURCE GUARD ---")
	var src := FileAccess.get_file_as_string("res://scripts/main.gd")
	_check(src.find("P8.1-05：强风时加大横向输运") >= 0, "G1 强风落叶逻辑在 _update_weather_fx 中（源码标记存在）")
	_check(src.find("P8.1-05：风/风暴/降水三通道解耦") >= 0, "G2 萤火三通道解耦逻辑存在")
	_check(src.find("P8.1-05：冬季（canopy_keep=0 的裸树）") >= 0, "G3 冬季落叶门控逻辑存在")
	_check(src.find("P8.1-05：idle 正弦保留为") >= 0, "G4 秋千弹簧-阻尼逻辑存在")
	var i_leaf := src.find("P8.1-05：强风时加大横向输运")
	var seg_leaf := src.substr(i_leaf, 1600)
	_check(seg_leaf.find("restart(") == -1, "F9 落叶每帧更新路径无 restart()")
	var i_ff := src.find("P8.1-05：风/风暴/降水三通道解耦")
	var seg_ff := src.substr(i_ff, 1600)
	_check(seg_ff.find("restart(") == -1, "F9 萤火每帧更新路径无 restart()")
	_check(src.find("static func wind_leaf_params") >= 0 and src.find("static func swing_spring_step") >= 0, "G5 纯函数层（probe 与线上同源）存在")

# ============================================================
# F5/F9：节点与实例身份（不重建、不新增）
# ============================================================
func _phase_node_identity() -> void:
	print("--- PHASE B: NODE IDENTITY ---")
	var before := _count_nodes(m)
	var fx_before: Dictionary = m.get("_fx")
	var leaf_id := _leaf_node.get_instance_id()
	var ff_id := _ff_node.get_instance_id()
	var ff_children := _ff_node.get_child_count()
	_season([0.0, 0.0, 1.0, 0.0])
	m.call("_apply_season_visuals")
	_set_weather(WIND_STRONG, WD_135)
	for i in range(240):
		_fx_update()
		_lighting()
	var after := _count_nodes(m)
	_check(after == before, "F5 240 帧强风更新不新增/删除节点（%d → %d）" % [before, after])
	_check(_leaf_node.get_instance_id() == leaf_id and _ff_node.get_instance_id() == ff_id, "F9 落叶/萤火仍是原节点（未重建）")
	_check(_ff_node.get_child_count() == ff_children, "F5 萤火 draw pass 子节点数不变（%d）" % _ff_node.get_child_count())
	_check((m.get("_fx") as Dictionary).get("leaves", {}).get("node", null) == _leaf_node, "F5 _fx.leaves 引用未替换")

func _count_nodes(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count_nodes(ch)
	return c
