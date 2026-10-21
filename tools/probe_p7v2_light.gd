extends SceneTree
## P7-V2 独立验收探针：夜间道路照明（任务 D）
## 验收点：五档画质下 6 盏路灯全部进入点光数组、位置与 world["lamps"] 世界坐标一致、
##          低/中档道路照明不为零、强度不过曝、切换档位不闪断、昼夜亮度差异真实生效。
## 两种模式：
##  headless（逻辑）：
##   "D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe" --headless --path "D:/休闲小岛幻境/游戏工程" --script res://tools/probe_p7v2_light.gd
##  窗口（追加截图像素统计；global shader uniform 在本引擎 --script 窗口模式仍读不到（返回 null），
##        因此「6 盏灯是否真实参与照地」改由逐盏隔离的真实帧像素证据承担）：
##   "D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe" --path "D:/休闲小岛幻境/游戏工程" --resolution 1600x900 --script res://tools/probe_p7v2_light.gd -- --window --out=D:/休闲小岛幻境/开发产物/p7v2/shots/light_probe/
## 退出码：0=全部通过；1=有失败；窗口模式的像素断言只在窗口模式执行。

const TIME_NIGHT := 22.0 * 60.0 + 10.0
const TIME_DAY := 12.0 * 60.0
const EXP_BUDGET := [7, 8, 9, 11, 12]
const LAMP_EPS := 0.01
const OUT_DEFAULT := "D:/休闲小岛幻境/开发产物/p7v2/shots/light_probe/"
const IsleMathScript := preload("res://scripts/isle_math.gd")
const WARM_EPS := 0.002

var _main: Node = null
var _lamp_positions: Array = []
var _lamp_light_pos: Array = []
var _quality_states: Array = []
var _out_dir := OUT_DEFAULT
var _window := false
var _pass := 0
var _fail := 0
var _fails: Array = []

func _initialize() -> void:
	print("=== P7-V2 LIGHT PROBE START (headless_logic + window_uniform/pixel) ===")
	await process_frame
	# 自动判定窗口模式（DisplayServer=headless 时为纯逻辑模式）；--window 可强制打开、
	# --headless-logic 可强制只跑逻辑断言（用于窗口环境里复现 headless 结果）。
	_window = DisplayServer.get_name() != "headless"
	for a in OS.get_cmdline_user_args():
		if a == "--window":
			_window = true
		elif a == "--headless-logic":
			_window = false
		elif a.begins_with("--out="):
			_out_dir = a.substr(6)
	print("[LIGHT] mode=", "window" if _window else "headless", " out=", _out_dir)
	var scene: PackedScene = load("res://isle.tscn")
	if scene == null:
		_check(false, "isle.tscn 可加载")
		_report()
		return
	_main = scene.instantiate()
	root.add_child(_main)
	await process_frame
	await process_frame
	await process_frame
	_check(_main != null and _main.has_method("debug_light_state"), "main 实例化成功且暴露 debug_light_state()")
	if not _main.has_method("debug_light_state"):
		_report()
		return
	_setup_playing_state()
	_probe_scene_and_lamps()
	_probe_five_quality_logic()
	await _probe_quality_switch_no_flash()
	if _window:
		await _probe_uniforms_day_night()
		await _window_pixel_checks()
		await _window_isolation_checks()
	_report()

func _setup_playing_state() -> void:
	# 复刻 main 进入 PLAYING 后的稳定状态：固定机位、暂停自动运镜、时间由探针控制。
	var menu: Variant = _main.get("_menu")
	if menu != null and menu.has_method("instant_finish"):
		menu.call("instant_finish")
	_main.set("_mode", 1)
	_main.set("_time_source", "sim")
	_main.set("_realtime", false)
	_main.set("_started", true)
	_main.set("_paused", true)
	_main.set("_auto_orbit", false)
	_main.set("_blending", "")

func _check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("  [OK] ", msg)
	else:
		_fail += 1
		_fails.append(msg)
		print("  [FAIL] ", msg)

func _report() -> void:
	print("[LIGHT] RESULT pass=", _pass, " fail=", _fail)
	for m in _fails:
		print("[LIGHT] FAILED: ", m)
	quit(0 if _fail == 0 else 1)

func _finite_vec(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)

func _float_close(a: float, b: float, eps: float) -> bool:
	return absf(a - b) <= eps

# ---------------- 场景与真实路灯坐标 ----------------
func _probe_scene_and_lamps() -> void:
	print("--- [SCENE] world lamps / light_sources ---")
	var wv: Variant = _main.get("_world")
	_check(wv is Dictionary, "_world 为 Dictionary")
	if not (wv is Dictionary):
		return
	var world: Dictionary = wv
	var lamps: Array = world.get("lamps", [])
	_check(lamps.size() == 6, "world[\"lamps\"] 恰好 6 盏（实际 %d）" % lamps.size())
	for l in lamps:
		if not (l is Array) or (l as Array).size() < 3:
			_check(false, "lamps 元素为 [?, ?, dict] 结构")
			continue
		var ld: Variant = (l as Array)[2]
		if typeof(ld) != TYPE_DICTIONARY:
			_check(false, "lamps[i][2] 为 Dictionary")
			continue
		var p: Vector3 = (ld as Dictionary).get("pos", Vector3.ZERO)
		_check(_finite_vec(p), "路灯世界坐标有限 %s" % str(p))
		_lamp_light_pos.append(p)
	# 探针独立取 main.debug_light_state().lamp_positions 作为对照基准（不假设 main 内部命名）
	var st: Dictionary = _main.call("debug_light_state")
	_lamp_positions = (st.get("lamp_positions", []) as Array).duplicate()
	_check(_lamp_positions.size() == 6, "debug_light_state().lamp_positions = 6（实际 %d）" % _lamp_positions.size())
	var pos_ok := true
	for i in range(mini(_lamp_positions.size(), _lamp_light_pos.size())):
		if (_lamp_positions[i] as Vector3).distance_to(_lamp_light_pos[i] as Vector3) > LAMP_EPS:
			pos_ok = false
	_check(pos_ok, "debug_light_state().lamp_positions 与 world[\"lamps\"] 世界坐标一一一致（eps=%s）" % str(LAMP_EPS))
	# 六盏灯必须在空间上互不重合；高度按「相对村庄地形」判定：
	# 灯位在灯柱顶的灯罩中心（绝对 y≈5.3-10.5，村庄地形 y≈7.5-8.5），不是贴地假点。
	var min_gap := 1.0e30
	var rel_heights: Array = []
	var h_ok := true
	for i in range(_lamp_positions.size()):
		var a: Vector3 = _lamp_positions[i]
		var gh: float = IsleMathScript.terrain_height(a.x, a.z)
		var rel := a.y - gh
		rel_heights.append(rel)
		if rel < 1.2 or rel > 2.6:
			h_ok = false
		for j in range(i + 1, _lamp_positions.size()):
			var b: Vector3 = _lamp_positions[j]
			min_gap = minf(min_gap, a.distance_to(b))
	_check(min_gap >= 1.0, "六盏路灯位置互不重合（最小间距 %.3f m）" % min_gap)
	print("[LIGHT] lamp rel heights above terrain=", str(rel_heights))
	_check(h_ok, "路灯相对地形高度均在 [1.2,2.6] m（真实灯具位置而非地面假点）")
	var src: Array = world.get("light_sources", [])
	var sw: Array = []
	for s in src:
		if typeof(s) == TYPE_DICTIONARY:
			sw.append(String((s as Dictionary).get("kind", "other")))
	print("[LIGHT] world light_sources=", src.size(), " kinds=", sw)
	_check(src.size() >= 8, "world light_sources >= 8 盏（含 6 路灯 + 灯塔/码头/小屋灯）")

# ---------------- 五档逻辑断言 ----------------
func _probe_five_quality_logic() -> void:
	print("--- [QUALITY] 五档：路灯固定占位 + active/budget ---")
	_quality_states.clear()
	for q in range(5):
		_main.call("_apply_quality", q)
		_main.call("_set_time_of_day", TIME_NIGHT)
		_main.call("_update_lighting")
		var st: Dictionary = _main.call("debug_light_state")
		_quality_states.append(st)
		var lights: Array = st.get("lights", [])
		var budget: int = int(st.get("budget", -1))
		var active: int = int(st.get("active", -1))
		var lamp_count: int = int(st.get("lamp_count", -1))
		var qv: int = int(st.get("quality", -1))
		_check(qv == q, "q=%d debug_light_state().quality 一致（实际 %d）" % [q, qv])
		_check(budget == EXP_BUDGET[q], "q=%d light_budget=%d（契约 %d）" % [q, budget, EXP_BUDGET[q]])
		_check(lamp_count == 6, "q=%d lamp_count=6" % q)
		_check(lights.size() >= 7, "q=%d 参与排序的光源 >= 7（实际 %d）" % [q, lights.size()])
		var first6_ok := true
		for i in range(6):
			var L: Dictionary = lights[i] if i < lights.size() else {}
			if String(L.get("kind", "")) != "street_lamp":
				first6_ok = false
				break
			var p: Vector3 = L.get("pos", Vector3.ZERO)
			if p.distance_to(_lamp_positions[i] as Vector3) > LAMP_EPS:
				first6_ok = false
				break
		_check(first6_ok, "q=%d 前 6 盏均为 street_lamp 且坐标与真实路灯一一对应" % q)
		# 低/中档不能把路灯挤掉：active 至少 6 路灯 + 1 环境灯
		_check(active >= 7, "q=%d active=%d >= 7（6 路灯 + >=1 环境灯）" % [q, active])
		_check(active <= 12, "q=%d active=%d <= 12（shader 点光上限）" % [q, active])
		# 路灯参数不能被清成 0
		var lit_ok := true
		var warm_ok := true
		for i in range(6):
			var L: Dictionary = lights[i]
			var en := float(L.get("energy", 0.0))
			var rng := float(L.get("range", 0.0))
			var col: Color = L.get("color", Color.BLACK)
			if en <= 0.0 or rng < 0.6:
				lit_ok = false
			if col.r < col.b:
				warm_ok = false
		_check(lit_ok, "q=%d 6 路灯 energy>0 且 range>=0.6（不发黑）" % q)
		_check(warm_ok, "q=%d 路灯色温为暖色（r>=b）" % q)
		# 环境灯种类标签：至少 lighthouse 或 dock 之一存在（夜景地标）
		var kinds: Array = []
		for i in range(6, lights.size()):
			kinds.append(String((lights[i] as Dictionary).get("kind", "?")))
		var has_env := kinds.has("lighthouse") or kinds.has("dock") or kinds.has("other")
		_check(has_env, "q=%d 环境灯 kind 标签存在（%s）" % [q, str(kinds)])
		print("[LIGHT] q=", q, " budget=", budget, " active=", active, " lights=", lights.size(), " kinds=", str(kinds),
			" lamp0=", str((lights[0] as Dictionary).get("pos")), " en=", float((lights[0] as Dictionary).get("energy", 0.0)),
			" range=", float((lights[0] as Dictionary).get("range", 0.0)))
	# 档位之间前 6 盏路灯必须完全同源（低档不是"另一种灯"）
	var same_ok := true
	for q in range(1, 5):
		var a: Array = (_quality_states[0] as Dictionary).get("lights", [])
		var b: Array = (_quality_states[q] as Dictionary).get("lights", [])
		for i in range(6):
			var la: Dictionary = a[i]
			var lb: Dictionary = b[i]
			if (la.get("pos", Vector3.ZERO) as Vector3).distance_to(lb.get("pos", Vector3.ONE) as Vector3) > LAMP_EPS:
				same_ok = false
			if not _float_close(float(la.get("energy", 0.0)), float(lb.get("energy", 0.0)), 0.001):
				same_ok = false
			if not _float_close(float(la.get("range", 0.0)), float(lb.get("range", 0.0)), 0.001):
				same_ok = false
	_check(same_ok, "五档前 6 盏路灯同源（pos/energy/range 完全一致）")

# ---------------- 切档不闪断 ----------------
func _probe_quality_switch_no_flash() -> void:
	print("--- [SWITCH] 切档不闪断（逻辑：路灯槽位不得出现空档） ---")
	_main.call("_set_time_of_day", TIME_NIGHT)
	var order := [4, 3, 2, 1, 0, 4, 0]
	var bad_frames := 0
	var samples := 0
	var min_active := 99
	var uniform_readable := false
	var uniform_bad := 0
	for q in order:
		_main.call("_apply_quality", q)
		# 逐帧观察：主循环每帧都会 _update_lighting，切档瞬间也不能把路灯槽关掉
		for f in range(3):
			await process_frame
			samples += 1
			var st: Dictionary = _main.call("debug_light_state")
			var lights: Array = st.get("lights", [])
			var active := int(st.get("active", -1))
			min_active = mini(min_active, active)
			var frame_ok := active >= 7 and lights.size() >= 7
			for i in range(6):
				if not frame_ok:
					break
				var L: Dictionary = lights[i]
				if String(L.get("kind", "")) != "street_lamp":
					frame_ok = false
				elif float(L.get("energy", 0.0)) <= 0.0 or float(L.get("range", 0.0)) < 0.6:
					frame_ok = false
				elif (L.get("pos", Vector3.ZERO) as Vector3).distance_to(_lamp_positions[i] as Vector3) > LAMP_EPS:
					frame_ok = false
			if not frame_ok:
				bad_frames += 1
			# 真实 uniform 若可读则一并核对（实测该引擎 --script 下返回 null，降级为信息）
			var gc: Variant = RenderingServer.global_shader_parameter_get("g_light_count")
			if gc != null:
				uniform_readable = true
				if int(round(float(gc))) < 6:
					uniform_bad += 1
	_check(bad_frames == 0, "切档过程 %d 帧中路灯槽位始终有效（坏帧 %d，最小 active=%d）" % [samples, bad_frames, min_active])
	_check(min_active >= 7, "切档全程 active >= 7（最小 %d）" % min_active)
	if uniform_readable:
		_check(uniform_bad == 0, "切档过程真实 g_light_count 不低于 6（坏帧 %d）" % uniform_bad)
	else:
		print("  [INFO] 该引擎 --script 下 RenderingServer.global_shader_parameter_get 返回 null；g_light_count 真实值由窗口像素断言覆盖（见 [PIXEL]/[SWITCH-PIXEL]）")

# ---------------- 窗口模式：uniform 可读性（不可读不判失败，真实参与照地改用像素证据） ----------------
func _probe_uniforms_day_night() -> void:
	print("--- [UNIFORM] 窗口模式：尝试读取 g_light_count / g_l*_pos / g_l*_col 真实值 ---")
	_main.call("_apply_quality", 2)
	_main.call("_set_time_of_day", TIME_NIGHT)
	for i in range(4):
		await process_frame
	_main.call("_update_lighting")
	var gc: Variant = RenderingServer.global_shader_parameter_get("g_light_count")
	if gc == null:
		print("  [INFO] global shader uniform 在本引擎 --script 模式下不可读（返回 null；headless 与窗口均实测）；不用参数值冒充，")
		print("         6 盏灯是否真实参与照地改由 [PIXEL-ISOLATION] 逐盏隔离真实帧 delta 断言。")
		return
	var st: Dictionary = _main.call("debug_light_state")
	var active_real := int(round(float(gc)))
	_check(active_real >= 7, "夜间 g_light_count=%d >= 7" % active_real)
	_check(active_real <= 12, "夜间 g_light_count=%d <= 12" % active_real)
	var pos_ok := true
	var col_ok := true
	var night_alpha := 0.0
	for i in range(6):
		var pv: Variant = RenderingServer.global_shader_parameter_get("g_l%d_pos" % i)
		var cv: Variant = RenderingServer.global_shader_parameter_get("g_l%d_col" % i)
		if not (pv is Vector4) or not (cv is Vector4):
			pos_ok = false
			col_ok = false
			continue
		var v4: Vector4 = pv
		var want: Vector3 = _lamp_positions[i] as Vector3
		if Vector3(v4.x, v4.y, v4.z).distance_to(want) > LAMP_EPS:
			pos_ok = false
		var c4: Vector4 = cv
		if c4.w <= 0.05:
			col_ok = false
		if i == 0:
			night_alpha = c4.w
	_check(pos_ok, "g_l0..5_pos 与真实路灯世界坐标一致（写进 shader 的是同一坐标）")
	_check(col_ok, "g_l0..5_col.w（强度）夜间全部 > 0.05（路灯真实参与着色）")
	_check(night_alpha > 0.2, "夜间 g_l0_col.w=%.3f > 0.2" % night_alpha)
	# 白天：同一槽位强度应显著变小
	_main.call("_set_time_of_day", TIME_DAY)
	for i in range(4):
		await process_frame
	_main.call("_update_lighting")
	var cv_day: Variant = RenderingServer.global_shader_parameter_get("g_l0_col")
	var day_alpha := 0.0
	if cv_day is Vector4:
		day_alpha = (cv_day as Vector4).w
	_check(cv_day is Vector4 and day_alpha < night_alpha * 0.35, "白天 g_l0_col.w=%.3f 显著小于夜间 %.3f（昼夜灯光渐变生效）" % [day_alpha, night_alpha])
	var gc_day: Variant = RenderingServer.global_shader_parameter_get("g_light_count")
	_check(gc_day != null and int(round(float(gc_day))) == active_real, "白天 g_light_count 与夜间一致（灯槽不变，仅强度渐变，不闪断）")
	print("[LIGHT] uniform night count=%d alpha=%.3f | day alpha=%.3f" % [active_real, night_alpha, day_alpha])

# ---------------- 窗口模式：截图像素统计（照地不为零 / 不过曝 / 低高档接近） ----------------
func _window_pixel_checks() -> void:
	print("--- [PIXEL] 窗口模式：路灯正下方路面像素统计 ---")
	DirAccess.make_dir_recursive_absolute(_out_dir)
	if _lamp_positions.size() < 2:
		_check(false, "像素统计需要 >=2 盏路灯坐标")
		return
	var lamp_mid: Vector3 = ((_lamp_positions[0] as Vector3) + (_lamp_positions[1] as Vector3)) * 0.5
	var ground := Vector3(lamp_mid.x, lamp_mid.y - 1.98, lamp_mid.z)
	var from := ground + Vector3(7.5, 5.0, 10.0)
	var target := ground + Vector3(0.0, 0.4, 0.5)
	_main.call("_set_time_of_day", TIME_NIGHT)
	var means: Dictionary = {}
	var clipped: Dictionary = {}
	var deltas: Dictionary = {}
	for q in range(5):
		_main.call("_apply_quality", q)
		_main.call("_pose_look", from, target, 42.0)
		for i in range(30):
			await process_frame
		var img: Image = await _grab("night_lamp_q%d.png" % q)
		if img == null:
			_check(false, "q=%d 夜景截图成功" % q)
			continue
		var cam: Camera3D = _main.get("_cam")
		var rect := _lamp_box(img, cam, ground)
		var m := _region_mean_luma(img, rect)
		var c := _region_clipped_ratio(img, rect)
		means[q] = m
		clipped[q] = c
		# 关灯参考帧：临时清空 _lights 再恢复，证明该区域亮度来自路灯
		var saved: Array = (_main.get("_lights") as Array).duplicate(true)
		_main.set("_lights", [])
		_main.call("_update_lighting")
		for i in range(3):
			await process_frame
		var dark_img: Image = await _grab("night_lamp_q%d_lightsoff.png" % q)
		_main.set("_lights", saved)
		_main.call("_update_lighting")
		for i in range(3):
			await process_frame
		if dark_img == null:
			_check(false, "q=%d 关灯参考截图成功" % q)
			continue
		var dark_m := _region_mean_luma(dark_img, rect)
		deltas[q] = m - dark_m
		print("[LIGHT] q=%d lamp_box mean=%.4f lightsoff=%.4f delta=%.4f clipped=%.4f rect=%s" % [q, m, dark_m, m - dark_m, c, str(rect)])
		_check(m - dark_m >= 0.005, "q=%d 路灯正下方路面比关灯时亮（delta=%.4f >= 0.005：道路照明不为零）" % [q, m - dark_m])
		_check(c <= 0.05, "q=%d 路灯区域无过曝（亮斑像素占比 %.4f <= 0.05）" % [q, c])
	# 低档与最高档接近（同一盏灯同一机位）
	if means.has(0) and means.has(4):
		var r := float(means[0]) / maxf(float(means[4]), 1.0e-6)
		_check(r >= 0.55 and r <= 1.6, "低档/极致档路灯照地亮度比 %.3f ∈ [0.55,1.6]（低档道路照明不明显偏暗）" % r)
		print("[LIGHT] quality lighting ratio q0/q4=%.3f" % r)
	for q in range(5):
		if deltas.has(q):
			print("[LIGHT] q=%d delta=%.4f" % [q, float(deltas[q])])
	# 昼夜差异：同一机位/同一盏灯，白天「亮灯-关灯」delta 应远小于夜间（灯强度随昼夜渐变真实生效）
	var cam2: Camera3D = _main.get("_cam")
	_main.call("_apply_quality", 2)
	_main.call("_set_time_of_day", TIME_DAY)
	_main.call("_pose_look", from, target, 42.0)
	for i in range(20):
		await process_frame
	var day_img: Image = await _grab("day_lamp_q2.png")
	var saved_day: Array = (_main.get("_lights") as Array).duplicate(true)
	_main.set("_lights", [])
	_main.call("_update_lighting")
	for i in range(3):
		await process_frame
	var day_dark: Image = await _grab("day_lamp_q2_lightsoff.png")
	_main.set("_lights", saved_day)
	_main.call("_update_lighting")
	for i in range(3):
		await process_frame
	if day_img != null and day_dark != null and deltas.has(2):
		var drect := _lamp_box(day_img, cam2, ground)
		var day_m := _region_mean_luma(day_img, drect)
		var day_dark_m := _region_mean_luma(day_dark, drect)
		var day_delta := day_m - day_dark_m
		var night_delta := float(deltas[2])
		print("[LIGHT] day lamp_box mean=%.4f lightsoff=%.4f delta=%.4f | night delta=%.4f" % [day_m, day_dark_m, day_delta, night_delta])
		_check(day_delta < night_delta * 0.6, "白天路灯区域贡献 %.4f < 夜间 %.4f * 0.6（昼暗夜亮渐变真实生效）" % [day_delta, night_delta])
	else:
		_check(false, "昼夜像素对照截图成功")
	# 窗口真实帧切档不闪断：固定机位切档抓帧，灯区亮度不得塌陷（不是靠参数推断）
	var switch_order := [4, 3, 2, 1, 0, 4, 0]
	var switch_ok := true
	var switch_min := 1.0e30
	_main.call("_set_time_of_day", TIME_NIGHT)
	_main.call("_pose_look", from, target, 42.0)
	for q in switch_order:
		_main.call("_apply_quality", q)
		for f in range(3):
			await process_frame
		var simg: Image = await _grab("switch_q%d.png" % q)
		if simg == null:
			switch_ok = false
			continue
		var srect := _lamp_box(simg, cam2, ground)
		var sm := _region_mean_luma(simg, srect)
		switch_min = minf(switch_min, sm)
		var floor_ref := 0.5 * float(means.get(q, 0.2))
		if sm < floor_ref:
			switch_ok = false
		print("[LIGHT] switch q=%d lamp_mean=%.4f floor=%.4f" % [q, sm, floor_ref])
	_check(switch_ok, "窗口真实渲染切档全程灯区亮度无闪断（最小 %.4f）" % switch_min)

# ---------------- 窗口模式：6 盏灯逐盏隔离，证明每盏灯都真实参与照地 ----------------
## 该引擎 --script 模式读不到 global shader uniform（headless 与窗口均 null），
## 因此不用参数值冒充：把 _lights 换成单盏灯、固定机位抓真实帧，与其关灯帧比较灯下地面亮度。
func _window_isolation_checks() -> void:
	print("--- [PIXEL-ISOLATION] 6 盏路灯逐盏隔离：每盏都真实参与照地 ---")
	if _lamp_positions.size() < 6:
		_check(false, "逐盏隔离需要 6 个路灯坐标")
		return
	_main.call("_set_time_of_day", TIME_NIGHT)
	_main.call("_apply_quality", 2)
	var saved_all: Array = (_main.get("_lights") as Array).duplicate(true)
	var lamp_slice: Array = []
	for i in range(mini(6, saved_all.size())):
		var L: Dictionary = saved_all[i]
		if String(L.get("kind", "")) == "street_lamp":
			lamp_slice.append(L)
	_check(lamp_slice.size() == 6, "隔离前 _lights 前 6 项均为 street_lamp（实际 %d）" % lamp_slice.size())
	var iso_ok := 0
	for i in range(lamp_slice.size()):
		var lp: Vector3 = _lamp_positions[i]
		var g := Vector3(lp.x, lp.y - 1.98, lp.z)
		var cfrom := g + Vector3(4.0, 3.2, 5.0)
		_main.set("_lights", [lamp_slice[i]])
		_main.call("_pose_look", cfrom, g, 42.0)
		_main.call("_update_lighting")
		for f in range(4):
			await process_frame
		var on_img: Image = await _grab("iso_lamp%d_on.png" % i)
		_main.set("_lights", [])
		_main.call("_update_lighting")
		for f in range(3):
			await process_frame
		var off_img: Image = await _grab("iso_lamp%d_off.png" % i)
		_main.set("_lights", saved_all)
		_main.call("_update_lighting")
		for f in range(2):
			await process_frame
		if on_img == null or off_img == null:
			_check(false, "灯%d 隔离对比截图成功" % i)
			continue
		var cam: Camera3D = _main.get("_cam")
		var rect := _lamp_box(on_img, cam, g, 44)
		var m := _region_mean_luma(on_img, rect)
		var dm := _region_mean_luma(off_img, rect)
		var delta := m - dm
		print("[LIGHT] iso lamp%d lamp_box mean=%.4f off=%.4f delta=%.4f" % [i, m, dm, delta])
		if delta >= 0.01:
			iso_ok += 1
		_check(delta >= 0.01, "灯%d 单独入槽时其正下方地面显著变亮（delta=%.4f >= 0.01：该灯真实参与照地）" % [i, delta])
	_check(iso_ok == 6, "6 盏路灯逐盏隔离均真实参与照地（%d/6）" % iso_ok)

func _grab(shot_name: String) -> Image:
	await RenderingServer.frame_post_draw
	var img: Image = _main.get_viewport().get_texture().get_image()
	if img == null:
		return null
	img.save_png(_out_dir + shot_name)
	print("[LIGHT] SHOT ", _out_dir + shot_name, " ", img.get_width(), "x", img.get_height())
	return img

func _lamp_box(img: Image, cam: Camera3D, ground: Vector3, half: int = 26) -> Rect2i:
	# 把路灯正下方地面点投到屏幕，取其周围一块区域做亮度统计
	var sp: Vector2 = cam.unproject_position(ground)
	var x := clampi(int(sp.x) - half, 0, maxi(img.get_width() - 2 * half - 1, 0))
	var y := clampi(int(sp.y) - half, 0, maxi(img.get_height() - 2 * half - 1, 0))
	return Rect2i(x, y, mini(2 * half, img.get_width()), mini(2 * half, img.get_height()))

func _region_mean_luma(img: Image, rect: Rect2i) -> float:
	var sum := 0.0
	var n := 0
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			var c := img.get_pixel(x, y)
			sum += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
	return sum / maxf(float(n), 1.0)

func _region_clipped_ratio(img: Image, rect: Rect2i) -> float:
	var clipped := 0
	var n := 0
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			var c := img.get_pixel(x, y)
			if c.r >= 0.965 and c.g >= 0.965 and c.b >= 0.965:
				clipped += 1
			n += 1
	return float(clipped) / maxf(float(n), 1.0)
