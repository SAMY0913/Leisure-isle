extends SceneTree
## P7-V2 task-3 自由飞行观景相机探针（headless，全部逻辑用固定 dt，不读真实时钟）
## 运行：
##   "$ENG" --headless --path "D:/休闲小岛幻境/游戏工程" --script res://tools/probe_flycam_p7v2.gd
## 判据：exit 0 且 [FLYCAM] RESULT fail=0。
## 覆盖：
##   1  InputMap 8 个动作（存在/键位/deadzone）+ P7-V1 toggle_auto_orbit 未被破坏
##   2  API 契约（active/configure/enter/request_exit/handle_event/update/apply_to/help_text/debug_state/saved_home）
##   3  校准值实测（IsleMath.coast_radius / terrain_height 采样 + D=2×边界半径 R=260，§7.2 口径）与常量一致性
##   4  WASD 仅按 yaw 水平方向（不含 pitch）、斜向归一化
##   5  速度=每秒世界单位、指数阻尼；30/60/120fps 位移一致（帧率无关）
##   6  Ctrl 加速倍率 / 平滑上升 / 松开立即回落；FOV 加速与恢复
##   7  Space 上升 / Shift 下降
##   8  水平圆形边界 clamp + 切向滑动（不瞬移）、高度上限、地形净高与海平面下限
##   9  鼠标视角 pitch clamp ±1.45、yaw 环绕、事件吞噬/放行
##   10 退出 smoothstep 回位（精确 home 位姿 + home FOV，active=false）
##   11 apply_to(cam) 写 global_transform + fov

const FlyCamScript := preload("res://scripts/isle_flycam.gd")
const MathScript := preload("res://scripts/isle_math.gd")
const DT := 1.0 / 60.0

var _pass := 0
var _fail := 0
var _fails: Array[String] = []
var _terrain: Callable
var _coast_min := 0.0
var _coast_max := 0.0
var _coast_avg := 0.0
var _terrain_min := 0.0
var _terrain_max := 0.0
var _tmax_pos := Vector3.ZERO
var _sea_pos := Vector3.ZERO
var _sea_ground := 0.0
var _safe_y := 20.0

const ACTIONS := {
	"fly_toggle": 70,
	"fly_forward": 87,
	"fly_back": 83,
	"fly_left": 65,
	"fly_right": 68,
	"fly_up": 32,
	"fly_down": 4194325,
	"fly_boost": 4194326,
}


func _initialize() -> void:
	_terrain = func(x: float, z: float) -> float:
		return MathScript.terrain_height(x, z)
	print("[FLYCAM] P7-V2 task-3 free-fly camera probe start (fixed dt, headless)")
	await process_frame
	_probe_class_and_api()
	_probe_input_map()
	_probe_calibration()
	_probe_configure()
	_probe_enter_and_home()
	_probe_direction_yaw_only()
	_probe_framerate_independence()
	_probe_boost()
	_probe_vertical()
	_probe_bounds_radial()
	_probe_bounds_tangential_slide()
	_probe_bounds_ceiling()
	_probe_terrain_floor()
	_probe_look()
	_probe_fov_and_apply_to()
	_probe_exit_blend()
	_release_all_actions()
	print("[FLYCAM] RESULT pass=%d fail=%d" % [_pass, _fail])
	for m in _fails:
		print("[FLYCAM] FAIL: ", m)
	quit(0 if _fail == 0 else 1)


# ============================================================
# 基础工具
# ============================================================
func _check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("[FLYCAM] [OK] " + msg)
	else:
		_fail += 1
		_fails.append(msg)
		print("[FLYCAM] [FAIL] " + msg)


func _new_fly(overrides: Dictionary = {}):
	_release_all_actions()
	var fly = FlyCamScript.new()
	var cfg: Dictionary = FlyCamScript.default_config()
	for k in overrides:
		cfg[k] = overrides[k]
	fly.configure(cfg)
	return fly


func _fly_at(yaw: float, pitch: float, pos: Vector3):
	var fly = _new_fly()
	fly.enter(Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0.0)), pos), 42.0)
	return fly


func _sky() -> Vector3:
	return Vector3(_sea_pos.x, _safe_y, _sea_pos.z)


func _run(fly, seconds: float, dt: float = DT) -> void:
	var t := 0.0
	while t < seconds - 1e-9:
		var h: float = minf(dt, seconds - t)
		fly.update(h, _terrain)
		t += h


## 逐步驱动并统计单帧最大位移/最小离地净高/是否触界。
func _run_track(fly, seconds: float, dt: float = DT) -> Dictionary:
	var t := 0.0
	var prev: Vector3 = fly.debug_state()["pos"]
	var max_step := 0.0
	var hit_any := false
	var min_margin := 1e9
	var samples: Array = []
	var total := 0.0
	while t < seconds - 1e-9:
		var h: float = minf(dt, seconds - t)
		fly.update(h, _terrain)
		total += h
		var d: Dictionary = fly.debug_state()
		var p: Vector3 = d["pos"]
		var step := p.distance_to(prev)
		max_step = maxf(max_step, step)
		var margin: float = p.y - MathScript.terrain_height(p.x, p.z)
		min_margin = minf(min_margin, margin)
		if bool(d.get("hit_bound", false)):
			hit_any = true
		samples.append({"t": total, "pos": p})
		prev = p
		t += h
	return {
		"time": total,
		"max_step": max_step,
		"hit_any": hit_any,
		"min_margin": min_margin,
		"samples": samples,
		"last": fly.debug_state(),
	}


func _expected_disp(speed: float, t: float) -> float:
	var k: float = FlyCamScript.MOVE_RESPONSE
	return speed * (t - (1.0 - exp(-k * t)) / k)


func _release_all_actions() -> void:
	for a in ACTIONS:
		if InputMap.has_action(a):
			Input.action_release(a)


func _yaw_of_home(home: Transform3D) -> float:
	var f := -home.basis.z
	return atan2(-f.x, -f.z)


func _pitch_of_home(home: Transform3D) -> float:
	var f := -home.basis.z
	return asin(clampf(f.y, -1.0, 1.0))


# ============================================================
# 1. 类注册 / API 契约
# ============================================================
func _probe_class_and_api() -> void:
	print("[FLYCAM] --- 1 class & API contract ---")
	var fly0 = FlyCamScript.new()
	_check(fly0 != null and fly0 is RefCounted, "isle_flycam.gd 可实例化")
	var found := false
	var found_path := ""
	for e in ProjectSettings.get_global_class_list():
		if String(e.get("class", "")) == "IsleFlyCam":
			found = true
			found_path = String(e.get("path", ""))
			break
	_check(found, "IsleFlyCam 已注册到全局类缓存（main.gd 可直接用类名）")
	_check(found_path == "res://scripts/isle_flycam.gd", "全局类路径正确: " + found_path)
	var fly = FlyCamScript.new()
	_check(fly is RefCounted, "IsleFlyCam extends RefCounted")
	var methods := ["configure", "enter", "request_exit", "handle_event", "update", "apply_to", "help_text", "debug_state", "saved_home"]
	for m in methods:
		_check(fly.has_method(m), "API 存在: " + m)
	_check(fly.get("active") == false, "初始 active=false")
	_check(fly.update(DT, _terrain) == false, "未进入时 update 返回 false")
	var help: String = fly.help_text()
	_check(help.length() > 8, "help_text 非空")
	for kw in ["WASD", "Space", "Shift", "Ctrl", "F"]:
		_check(help.contains(kw), "help_text 含键位说明: " + kw)
	var d0: Dictionary = fly.debug_state()
	for k in ["active", "exiting", "pos", "yaw", "pitch", "speed", "boost_scale", "hit_bound", "fov", "bounds", "home_pos", "home_fov"]:
		_check(d0.has(k), "debug_state 含键: " + k)
	var sh0: Dictionary = fly.saved_home()
	_check(sh0.has("transform") and sh0.has("fov") and sh0.has("yaw") and sh0.has("pitch"), "saved_home 含 transform/fov/yaw/pitch")


# ============================================================
# 2. InputMap
# ============================================================
func _probe_input_map() -> void:
	print("[FLYCAM] --- 2 InputMap actions ---")
	var keys_seen: Array = []
	for a in ACTIONS:
		var code: int = ACTIONS[a]
		_check(InputMap.has_action(a), "InputMap.has_action: " + a)
		_check(ProjectSettings.has_setting("input/" + a), "project.godot 持久化: input/" + a)
		var evs: Array = InputMap.action_get_events(a)
		_check(evs.size() == 1, "%s 事件数=1 (实际 %d)" % [a, evs.size()])
		var key_ok := false
		var dev_ok := false
		for ev in evs:
			if ev is InputEventKey:
				var ke := ev as InputEventKey
				if int(ke.physical_keycode) == code:
					key_ok = true
				if ke.device == -1:
					dev_ok = true
		_check(key_ok, "%s physical_keycode=%d" % [a, code])
		_check(dev_ok, "%s device=-1" % a)
		_check(is_equal_approx(InputMap.action_get_deadzone(a), 0.5), "%s deadzone=0.5" % a)
		keys_seen.append(code)
	var uniq := {}
	for k in keys_seen:
		uniq[k] = true
	_check(uniq.size() == keys_seen.size(), "8 个动作键位互不重复")
	_check(InputMap.has_action("toggle_auto_orbit"), "P7-V1 toggle_auto_orbit 动作保留")
	_check(not InputMap.has_action("fly_exit"), "未引入多余动作 fly_exit（退出走 request_exit）")


# ============================================================
# 3. 校准值实测
# ============================================================
func _probe_calibration() -> void:
	print("[FLYCAM] --- 3 calibration vs real project measurements ---")
	var n := 4096
	var rmin := 1e9
	var rmax := -1e9
	var rsum := 0.0
	for i in range(n):
		var a := TAU * float(i) / float(n)
		var r: float = MathScript.coast_radius(a)
		rmin = minf(rmin, r)
		rmax = maxf(rmax, r)
		rsum += r
	_coast_min = rmin
	_coast_max = rmax
	_coast_avg = rsum / float(n)
	var mean_dia := 2.0 * _coast_avg
	var max_dia := 2.0 * _coast_max
	_check(rmin > 18.0 and rmax < 33.0, "实测岸线半径 %.3f~%.3f m 落在公式理论范围" % [rmin, rmax])
	_check(_coast_avg > 24.0 and _coast_avg < 27.0, "实测岸线平均半径 %.3f m" % _coast_avg)

	# 地形采样（地形网格外缘 ≈40m，探针扫 -45..45 覆盖海滩/海面）
	var tmin := 1e9
	var tmax := -1e9
	var step := 0.5
	var x := -45.0
	while x <= 45.0 + 1e-9:
		var z := -45.0
		while z <= 45.0 + 1e-9:
			var h: float = MathScript.terrain_height(x, z)
			if h < tmin:
				tmin = h
			if h > tmax:
				tmax = h
				_tmax_pos = Vector3(x, h, z)
			z += step
		x += step
	_terrain_min = tmin
	_terrain_max = tmax
	_safe_y = maxf(20.0, tmax + 5.0)
	_check(tmin < 0.0, "采样到海平面以下地形 min=%.3f m（海平面=0）" % tmin)
	_check(tmax > 5.0, "采样到岛上高地 max=%.3f m @ (%.1f, %.1f)" % [tmax, _tmax_pos.x, _tmax_pos.z])

	# 找一处外海点（岸线最大 33m 之外、地形网格外缘 40m 之外）
	var sea_found := false
	var rr := 45.0
	while rr <= 95.0 and not sea_found:
		var ang := 0.0
		while ang < TAU:
			var sx := cos(ang) * rr
			var sz := sin(ang) * rr
			var g: float = MathScript.terrain_height(sx, sz)
			if g < -1.0:
				_sea_pos = Vector3(sx, 0.0, sz)
				_sea_ground = g
				sea_found = true
				break
			ang += 0.15
		rr += 5.0
	_check(sea_found, "找到外海点 (%.1f, %.1f) ground=%.2f" % [_sea_pos.x, _sea_pos.z, _sea_ground])

	var fly = _new_fly()
	var R: float = fly.radius
	var D := 2.0 * R
	var t_reg: float = D / float(fly.speed_regular)
	var t_boost: float = D / float(fly.speed_boost)
	print("[FLYCAM][CAL] coast_radius min=%.3f max=%.3f avg=%.3f | island mean_dia=%.3f max_dia=%.3f | formula_max_radius=32.0 -> formula_max_dia=63.6" % [rmin, rmax, _coast_avg, mean_dia, max_dia])
	print("[FLYCAM][CAL] terrain min=%.3f max=%.3f @(%.1f,%.1f) | sea_pt=(%.1f,%.1f) ground=%.2f | safe_y=%.1f" % [tmin, tmax, _tmax_pos.x, _tmax_pos.z, _sea_pos.x, _sea_pos.z, _sea_ground, _safe_y])
	print("[FLYCAM][CAL] R=%.2f | D=2R=%.2f | speed_regular=%.4f (D/25=%.4f, traverse=%.2fs) | speed_boost=%.4f (D/12=%.4f, traverse=%.2fs) | boost=%.4fx" % [R, D, fly.speed_regular, D / 25.0, t_reg, fly.speed_boost, D / 12.0, t_boost, fly.speed_boost / fly.speed_regular])
	print("[FLYCAM][CAL] vertical=%.2f | look_sens=%.5f | boost_fov_add=%.2f | exit_blend=%.2f | radius=%.1f | min_y=%.2f | max_y=%.2f" % [fly.vertical_speed, fly.look_sensitivity, fly.boost_fov_add, fly.exit_blend_dur, fly.radius, fly.min_y, fly.max_y])

	# 任务书 §7.2 最终标定：R=130、D=2R=260、普通=D/25=10.4、加速=D/12=21.7（≈2.09x）、垂直=5.5。
	_check(is_equal_approx(FlyCamScript.REF_RANGE_D, D) and absf(D - 260.0) < 1e-6, "REF_RANGE_D=%.2f = D=2×半径 %.1f = 260（§7.2 口径）" % [D, R])
	_check(is_equal_approx(R, 130.0), "水平边界半径 R=%.2f = 130（≈2.0× 岛最大直径 63.6m）" % R)
	_check(absf(fly.speed_regular - D / 25.0) <= (D / 25.0) * 0.01, "普通速度 %.3f ≈ D/25=%.3f（±1%%）" % [fly.speed_regular, D / 25.0])
	_check(t_reg >= 20.0 and t_reg <= 30.0, "普通速度穿越 D 用时 %.2fs 落在 20–30s 验收区间" % t_reg)
	var mult: float = fly.speed_boost / fly.speed_regular
	_check(absf(fly.speed_boost - D / 12.0) <= (D / 12.0) * 0.01, "加速速度 %.3f ≈ D/12=%.3f（±1%%）" % [fly.speed_boost, D / 12.0])
	_check(absf(mult - 2.0865) < 0.02 and mult > 2.0 and mult < 2.2, "加速倍率 %.4fx ≈ 21.7/10.4=2.0865（[2.0,2.2]）" % mult)
	_check(t_boost >= 10.0 and t_boost <= 15.0, "加速穿越 D 用时 %.2fs 落在 10–15s 验收区间" % t_boost)
	_check(absf(fly.vertical_speed - 5.5) < 1e-6, "垂直速度 5.5 m/s")
	_check(is_equal_approx(fly.max_y, 130.0), "高度上限 max_y=%.1f = 130（≈2.0× 岛最大直径）" % fly.max_y)
	_check(R >= 2.0 * mean_dia - 1e-6, "水平半径 %.1f ≥ 2× 岛平均直径 %.1f" % [R, mean_dia])
	_check(R > 2.0 * _coast_max + 40.0, "水平半径 %.1f > 岸线最大直径 %.1f + 40m 安全余量" % [R, max_dia])
	_check(fly.max_y >= 2.4 * mean_dia - 1e-6, "高度上限 %.1f ≥ 2.4× 岛平均直径 %.1f" % [fly.max_y, mean_dia])
	_check(fly.min_y >= 1.2 - 1e-6 and fly.min_y > 0.0, "最低高度 %.2f 不低于海平面（≥1.2m）" % fly.min_y)
	_check(fly.exit_blend_dur >= 0.3 and fly.exit_blend_dur <= 1.2, "退出回位混合 %.2fs 合理" % fly.exit_blend_dur)
	_check(fly.boost_fov_add > 0.0 and fly.boost_fov_add <= 10.0, "加速 FOV 增量 %.1f° 合理" % fly.boost_fov_add)


# ============================================================
# 4. configure
# ============================================================
func _probe_configure() -> void:
	print("[FLYCAM] --- 4 configure ---")
	var fly = _new_fly()
	fly.configure({
		"center": Vector3(3.0, 0.0, -2.0),
		"radius": 50.0,
		"min_y": 2.0,
		"max_y": 60.0,
		"speed_regular": 10.0,
		"speed_boost": 20.0,
		"vertical_speed": 5.0,
		"look_sensitivity": 0.01,
		"boost_fov_add": 8.0,
		"exit_blend_dur": 0.3,
	})
	_check(is_equal_approx(fly.radius, 50.0) and is_equal_approx(fly.max_y, 60.0) and is_equal_approx(fly.min_y, 2.0), "configure radius/min_y/max_y 生效")
	_check(is_equal_approx(fly.speed_regular, 10.0) and is_equal_approx(fly.speed_boost, 20.0), "configure 速度生效")
	_check(is_equal_approx(fly.vertical_speed, 5.0) and is_equal_approx(fly.look_sensitivity, 0.01), "configure 垂直速度/灵敏度生效")
	_check(is_equal_approx(fly.boost_fov_add, 8.0) and is_equal_approx(fly.exit_blend_dur, 0.3), "configure FOV 增量/混合时长生效")
	_check((fly.center as Vector3).is_equal_approx(Vector3(3.0, 0.0, -2.0)), "configure center 生效")
	var d: Dictionary = fly.debug_state()
	_check(is_equal_approx(float(d["boost_mult"]), 2.0), "速度比自动换算 boost_mult=2.00")
	fly.configure({"min_y": 100.0, "max_y": 10.0, "radius": -5.0, "speed_regular": -1.0})
	_check(fly.max_y >= fly.min_y + 1.0, "非法 min_y/max_y 被修正为 max_y≥min_y+1")
	_check(fly.radius >= 1.0, "非法 radius 被修正 ≥1.0")
	_check(fly.speed_regular >= 0.05, "非法速度被修正 ≥0.05")
	# 用自定义速度驱动一次，确认运动真的用了配置值
	var fly2 = _new_fly({"speed_regular": 10.0, "speed_boost": 20.0})
	fly2.enter(Transform3D(Basis.IDENTITY, _sky()), 42.0)
	Input.action_press("fly_forward")
	_run(fly2, 1.5)
	Input.action_release("fly_forward")
	var d2: Dictionary = fly2.debug_state()
	_check(absf(float(d2["horizontal_speed"]) - 10.0) < 0.05, "自定义 speed_regular=10 后实测水平速度 %.3f" % float(d2["horizontal_speed"]))


# ============================================================
# 5. enter / home
# ============================================================
func _probe_enter_and_home() -> void:
	print("[FLYCAM] --- 5 enter & saved_home ---")
	var fly = _new_fly()
	var from := Transform3D(Basis.from_euler(Vector3(0.0, 0.4, 0.0)), _sky() + Vector3(0.0, 1.0, 0.0))
	var home := Transform3D(Basis.from_euler(Vector3(0.05, -0.9, 0.0)), Vector3(48.0, 9.0, 55.0))
	fly.enter(from, 42.0, home)
	_check(fly.active, "enter 后 active=true")
	var d: Dictionary = fly.debug_state()
	_check((d["pos"] as Vector3).is_equal_approx(from.origin), "enter 起点=from_xf.origin")
	_check(absf(float(d["fov"]) - 42.0) < 1e-6, "enter FOV=42")
	_check(absf(float(d["yaw"]) - 0.4) < 0.02 and absf(float(d["pitch"]) - 0.0) < 0.02, "enter 从 basis 反解 yaw/pitch")
	var sh: Dictionary = fly.saved_home()
	_check((sh["transform"] as Transform3D).is_equal_approx(home), "saved_home.transform == 传入 home_xf")
	_check(absf(float(sh["fov"]) - 42.0) < 1e-6, "saved_home.fov=42")
	_check(absf(float(sh["yaw"]) - _yaw_of_home(home)) < 1e-4, "saved_home.yaw 与 home 朝向一致")
	_check(absf(float(sh["pitch"]) - _pitch_of_home(home)) < 1e-4, "saved_home.pitch 与 home 朝向一致")
	_check(fly.update(DT, _terrain) == true, "enter 后 update 返回 true（仍控制相机）")
	# home 省略时 = from
	var fly2 = _new_fly()
	fly2.enter(from, 40.0)
	var sh2: Dictionary = fly2.saved_home()
	_check((sh2["transform"] as Transform3D).is_equal_approx(from), "home_xf 省略时回位目标=from_xf")
	_check(absf(float(sh2["fov"]) - 40.0) < 1e-6, "home 省略时 FOV 记录=传入 fov")


# ============================================================
# 6. 方向：WASD 仅按 yaw 水平方向
# ============================================================
func _probe_direction_yaw_only() -> void:
	print("[FLYCAM] --- 6 direction (yaw only) ---")
	var start := _sky()
	var cases := [
		{"key": "fly_forward", "yaw": 0.0, "want": Vector3(0.0, 0.0, -1.0)},
		{"key": "fly_back", "yaw": 0.0, "want": Vector3(0.0, 0.0, 1.0)},
		{"key": "fly_left", "yaw": 0.0, "want": Vector3(-1.0, 0.0, 0.0)},
		{"key": "fly_right", "yaw": 0.0, "want": Vector3(1.0, 0.0, 0.0)},
		{"key": "fly_forward", "yaw": PI * 0.5, "want": Vector3(-1.0, 0.0, 0.0)},
		{"key": "fly_forward", "yaw": PI, "want": Vector3(0.0, 0.0, 1.0)},
	]
	for c in cases:
		var fly = _fly_at(float(c["yaw"]), 0.0, start)
		Input.action_press(String(c["key"]))
		_run(fly, 1.0)
		Input.action_release(String(c["key"]))
		var d: Dictionary = fly.debug_state()
		var delta: Vector3 = (d["pos"] as Vector3) - start
		var flat := Vector3(delta.x, 0.0, delta.z)
		var want: Vector3 = c["want"]
		var dir_ok := flat.length() > 4.0 and flat.normalized().dot(want) > 0.999
		_check(dir_ok, "%s @yaw=%.2f 方向正确 (Δxz=%s)" % [c["key"], float(c["yaw"]), str(delta)])
		_check(absf(delta.y) < 1e-6, "%s @yaw=%.2f 不产生垂直位移（y 不变）" % [c["key"], float(c["yaw"])])

	# 向下看（pitch=-1.2）时按 W：只水平移动，不自动下降
	var fly2 = _fly_at(0.0, -1.2, start)
	Input.action_press("fly_forward")
	_run(fly2, 1.0)
	Input.action_release("fly_forward")
	var d2: Dictionary = fly2.debug_state()
	var delta2: Vector3 = (d2["pos"] as Vector3) - start
	_check(absf(delta2.y) < 1e-6, "俯视 -1.2rad 时 W 不产生下降（Δy=%.6f）" % delta2.y)
	_check(delta2.z < -4.0, "俯视时 W 仍按 yaw 前移（Δz=%.3f）" % delta2.z)

	# 斜向归一化：W+D 的速度≈普通速度，不是 √2 倍
	var fly3 = _fly_at(0.0, 0.0, start)
	Input.action_press("fly_forward")
	Input.action_press("fly_right")
	_run(fly3, 1.5)
	Input.action_release("fly_forward")
	Input.action_release("fly_right")
	var d3: Dictionary = fly3.debug_state()
	var hs := float(d3["horizontal_speed"])
	_check(absf(hs - float(d3["speed_regular"])) < 0.05, "W+D 斜向归一化后水平速度 %.3f ≈ speed_regular %.1f" % [hs, float(d3["speed_regular"])])
	var delta3: Vector3 = (d3["pos"] as Vector3) - start
	_check(absf(delta3.x) > 1.0 and delta3.z < -1.0 and absf(absf(delta3.x) - absf(delta3.z)) < 0.2, "W+D 位移为 45° 对角")


# ============================================================
# 7. 帧率无关
# ============================================================
func _probe_framerate_independence() -> void:
	print("[FLYCAM] --- 7 framerate independence ---")
	var start := _sky()
	var seconds := 2.0
	var expected := _expected_disp(FlyCamScript.DEFAULT_SPEED_REGULAR, seconds)
	var results: Array = []
	for dt in [1.0 / 30.0, 1.0 / 60.0, 1.0 / 120.0]:
		var fly = _fly_at(0.0, 0.0, start)
		Input.action_press("fly_forward")
		_run(fly, seconds, dt)
		Input.action_release("fly_forward")
		var p: Vector3 = (fly.debug_state()["pos"] as Vector3)
		var disp := (p - start).length()
		results.append(disp)
		_check(absf(disp - expected) < 0.01, "dt=1/%.0f 位移 %.4f ≈ 解析值 %.4f" % [1.0 / dt, disp, expected])
	var spread: float = maxf(maxf(float(results[0]), float(results[1])), float(results[2])) - minf(minf(float(results[0]), float(results[1])), float(results[2]))
	_check(spread < 1e-3, "30/60/120fps 位移差 %.6f m < 1e-3（帧率无关）" % spread)


# ============================================================
# 8. Ctrl 加速 + FOV
# ============================================================
func _probe_boost() -> void:
	print("[FLYCAM] --- 8 boost ---")
	var fly = _fly_at(0.0, 0.0, _sky())
	Input.action_press("fly_forward")
	Input.action_press("fly_boost")
	_run(fly, 0.25)
	var d1: Dictionary = fly.debug_state()
	var bs1 := float(d1["boost_scale"])
	_check(bs1 > 1.5 and bs1 < float(d1["boost_mult"]), "加速上升中 boost_scale=%.3f 平滑（未瞬时到顶）" % bs1)
	_run(fly, 1.25)
	var d2: Dictionary = fly.debug_state()
	var bs2 := float(d2["boost_scale"])
	var target_mult := float(d2["boost_mult"])
	_check(absf(bs2 - target_mult) < 0.01, "持续加速 boost_scale=%.4f ≈ boost_mult=%.2f" % [bs2, target_mult])
	var hs := float(d2["horizontal_speed"])
	_check(absf(hs - float(d2["speed_boost"])) < 0.05, "加速后水平速度 %.3f ≈ speed_boost %.3f" % [hs, float(d2["speed_boost"])])
	var measured_mult := hs / float(d2["speed_regular"])
	_check(measured_mult > 2.0 and measured_mult < 2.2, "实测加速倍率 %.3fx" % measured_mult)
	var fov_boost := float(d2["fov"])
	_check(absf(fov_boost - (42.0 + float(d2["boost_fov_add"]))) < 0.2, "加速时 FOV %.2f ≈ 42+%.1f" % [fov_boost, float(d2["boost_fov_add"])])
	# 松开 Ctrl：立即回落 1x（同一帧），随后速度平滑降回普通速度
	Input.action_release("fly_boost")
	fly.update(DT, _terrain)
	var d3: Dictionary = fly.debug_state()
	_check(absf(float(d3["boost_scale"]) - 1.0) < 1e-9, "松开 Ctrl 当帧 boost_scale 立即回落 1.0")
	_check(not bool(d3["boost_active"]), "松开 Ctrl 后 boost_active=false")
	_run(fly, 0.6)
	var d4: Dictionary = fly.debug_state()
	_check(absf(float(d4["horizontal_speed"]) - float(d4["speed_regular"])) < 0.05, "松开后 0.6s 速度回落 %.3f ≈ 普通速度 %.1f" % [float(d4["horizontal_speed"]), float(d4["speed_regular"])])
	_check(absf(float(d4["fov"]) - 42.0) < 0.1, "松开后 FOV 回落到 %.3f ≈ 42" % float(d4["fov"]))
	Input.action_release("fly_forward")
	_run(fly, 0.5)
	_check(float(fly.debug_state()["speed"]) < 0.02, "松开 W 后速度趋近 0")


# ============================================================
# 9. 垂直升降
# ============================================================
func _probe_vertical() -> void:
	print("[FLYCAM] --- 9 vertical ---")
	var start := _sky()
	var fly = _fly_at(0.0, 0.0, start)
	Input.action_press("fly_up")
	_run(fly, 1.0)
	Input.action_release("fly_up")
	var d1: Dictionary = fly.debug_state()
	var dy := (d1["pos"] as Vector3).y - start.y
	_check(absf(dy - _expected_disp(5.5, 1.0)) < 0.02, "Space 上升 Δy=%.3f ≈ 解析值 %.3f" % [dy, _expected_disp(5.5, 1.0)])
	_check(absf(float(d1["vertical_speed_now"]) - 5.5) < 0.02, "上升速度 %.3f ≈ 5.5 m/s" % float(d1["vertical_speed_now"]))
	var y_top := (d1["pos"] as Vector3).y
	Input.action_press("fly_down")
	_run(fly, 1.5)
	Input.action_release("fly_down")
	var d2: Dictionary = fly.debug_state()
	_check((d2["pos"] as Vector3).y < y_top - 2.0, "Shift 下降 Δy=%.3f" % ((d2["pos"] as Vector3).y - y_top))
	_check(absf(float(d2["vertical_speed_now"]) + 5.5) < 0.05, "下降速度 %.3f ≈ -5.5 m/s" % float(d2["vertical_speed_now"]))
	_check(absf((d2["pos"] as Vector3).x - start.x) < 1e-6 and absf((d2["pos"] as Vector3).z - start.z) < 1e-6, "纯垂直升降不产生水平位移")


# ============================================================
# 10. 水平圆形边界：clamp + 不瞬移
# ============================================================
func _probe_bounds_radial() -> void:
	print("[FLYCAM] --- 10 radial boundary clamp ---")
	var start := Vector3(120.0, _safe_y, 0.0)
	var fly = _fly_at(-PI * 0.5, 0.0, start)  # yaw=-π/2 → forward=+X（正对边界）
	Input.action_press("fly_forward")
	var tr: Dictionary = _run_track(fly, 3.0)
	Input.action_release("fly_forward")
	var d: Dictionary = tr["last"]
	var p: Vector3 = d["pos"]
	var dist := Vector2(p.x, p.z).length()
	_check(absf(dist - 130.0) < 1e-3, "到边界后水平距离 %.4f = radius 130" % dist)
	_check(absf(p.y - _safe_y) < 1e-6, "水平边界不影响高度 y=%.3f" % p.y)
	_check(bool(tr["hit_any"]), "hit_bound 被置位")
	_check(float(tr["max_step"]) < 1.0, "单帧最大位移 %.4f m < 1.0（无瞬移）" % float(tr["max_step"]))
	_check(bool(d["hit_bound"]), "边界帧 debug_state.hit_bound=true")
	# 持续外推仍停在圆上（不抖动/不瞬移）
	Input.action_press("fly_forward")
	var tr2: Dictionary = _run_track(fly, 2.0)
	Input.action_release("fly_forward")
	var p2: Vector3 = tr2["last"]["pos"]
	_check(absf(Vector2(p2.x, p2.z).length() - 130.0) < 1e-3, "持续外推仍精确停在 radius 130 上（不抖动/不瞬移）")


# ============================================================
# 11. 边界切向滑动
# ============================================================
func _probe_bounds_tangential_slide() -> void:
	print("[FLYCAM] --- 11 tangential slide on boundary ---")
	var start := Vector3(125.0, _safe_y, 0.0)
	var fly = _fly_at(-PI * 0.5, 0.0, start)  # forward=+X 外推，D 为 +Z 切向
	Input.action_press("fly_forward")
	Input.action_press("fly_right")
	var tr: Dictionary = _run_track(fly, 2.5)
	Input.action_release("fly_forward")
	Input.action_release("fly_right")
	var d: Dictionary = tr["last"]
	var p: Vector3 = d["pos"]
	var dist := Vector2(p.x, p.z).length()
	var dz := p.z - start.z
	_check(absf(dist - 130.0) < 1e-2, "切向滑动期间始终贴边 dist=%.4f" % dist)
	_check(dz > 5.0, "切向滑动产生沿边界位移 Δz=%.3f（未卡死）" % dz)
	_check(float(tr["max_step"]) < 1.0, "切向滑动单帧最大位移 %.4f m（无瞬移）" % float(tr["max_step"]))
	var bad := 0
	var checked := 0
	var hit_t := -1.0
	for s in tr["samples"]:
		var sp: Vector3 = s["pos"]
		var sd := Vector2(sp.x, sp.z).length()
		if sd > 129.999 and hit_t < 0.0:
			hit_t = float(s["t"])
		if float(s["t"]) < 1.5:
			continue
		checked += 1
		if sd < 129.99 or sd > 130.001:
			bad += 1
	_check(hit_t > 0.0 and hit_t < 1.5, "约 %.2fs 抵达边界（随后持续贴边滑动）" % hit_t)
	_check(checked > 30 and bad == 0, "贴边后逐帧采样 %d 帧全部在圆上（越界帧 %d）" % [checked, bad])


# ============================================================
# 12. 高度上限
# ============================================================
func _probe_bounds_ceiling() -> void:
	print("[FLYCAM] --- 12 ceiling clamp ---")
	var fly = _fly_at(0.0, 0.0, _sky())
	Input.action_press("fly_up")
	var tr: Dictionary = _run_track(fly, 40.0)
	Input.action_release("fly_up")
	var d: Dictionary = tr["last"]
	var y := (d["pos"] as Vector3).y
	_check(absf(y - 130.0) < 1e-3, "持续上升停在 max_y=130（实际 %.4f）" % y)
	_check(bool(tr["hit_any"]) and bool(d["hit_bound"]), "上限 hit_bound 置位")
	_check(float(tr["max_step"]) < 0.5, "上升到顶过程单帧最大位移 %.4f m（无瞬移）" % float(tr["max_step"]))


# ============================================================
# 13. 地形净高 / 海平面下限
# ============================================================
func _probe_terrain_floor() -> void:
	print("[FLYCAM] --- 13 terrain floor / sea level ---")
	var high := _tmax_pos
	var high_ground: float = MathScript.terrain_height(high.x, high.z)
	var fly = _new_fly()
	fly.enter(Transform3D(Basis.IDENTITY, Vector3(high.x, 0.5, high.z)), 42.0)
	fly.update(DT, _terrain)
	var p1: Vector3 = fly.debug_state()["pos"]
	var dyn_min := maxf(1.2, high_ground + 0.8)
	_check(absf(p1.y - dyn_min) < 1e-4, "高地(%.1f,%.1f,地形%.2f)起点过低被抬到 %.3f = terrain+0.8" % [high.x, high.z, high_ground, p1.y])
	_check(p1.y > high_ground + 0.79, "相机高于地形 %.2f m" % (p1.y - high_ground))

	# 持续下压：不低于 terrain+0.8
	var fly2 = _new_fly()
	fly2.enter(Transform3D(Basis.IDENTITY, Vector3(high.x, high_ground + 10.0, high.z)), 42.0)
	Input.action_press("fly_down")
	var tr: Dictionary = _run_track(fly2, 5.0)
	Input.action_release("fly_down")
	var p2: Vector3 = tr["last"]["pos"]
	_check(absf(p2.y - maxf(1.2, MathScript.terrain_height(p2.x, p2.z) + 0.8)) < 1e-3, "下压后贴地停 %.3f" % p2.y)
	_check(float(tr["min_margin"]) >= 0.8 - 1e-3, "全程最小离地净高 %.4f ≥ 0.8" % float(tr["min_margin"]))
	_check(p2.y > 0.0, "不低于海平面 y=%.3f" % p2.y)

	# 外海：最低 = max(1.2, 海面地形+0.8) = 1.2
	var fly3 = _new_fly()
	fly3.enter(Transform3D(Basis.IDENTITY, Vector3(_sea_pos.x, 0.5, _sea_pos.z)), 42.0)
	fly3.update(DT, _terrain)
	var p3: Vector3 = fly3.debug_state()["pos"]
	_check(absf(p3.y - 1.2) < 1e-4, "外海低空被抬到 min_y=1.2（实际 %.4f）" % p3.y)
	_check(p3.y > 0.0, "外海相机高于海平面")


# ============================================================
# 14. 鼠标视角
# ============================================================
func _probe_look() -> void:
	print("[FLYCAM] --- 14 mouse look / pitch clamp ---")
	var fly = _fly_at(0.0, 0.0, _sky())
	var mm := InputEventMouseMotion.new()
	mm.relative = Vector2(100.0, 0.0)
	_check(fly.handle_event(mm) == true, "鼠标移动被消费（返回 true）")
	var d: Dictionary = fly.debug_state()
	_check(absf(float(d["yaw"]) + 100.0 * 0.0022) < 1e-5, "鼠标右移 100px → yaw=%.5f" % float(d["yaw"]))
	var mm_down := InputEventMouseMotion.new()
	mm_down.relative = Vector2(0.0, 10000.0)
	fly.handle_event(mm_down)
	_check(absf(float(fly.debug_state()["pitch"]) + 1.45) < 1e-6, "大幅下移 pitch clamp 到 -1.45")
	var mm_up := InputEventMouseMotion.new()
	mm_up.relative = Vector2(0.0, -20000.0)
	fly.handle_event(mm_up)
	_check(absf(float(fly.debug_state()["pitch"]) - 1.45) < 1e-6, "大幅上移 pitch clamp 到 +1.45")
	var mm_wrap := InputEventMouseMotion.new()
	mm_wrap.relative = Vector2(-100000.0, 0.0)
	fly.handle_event(mm_wrap)
	var yaw_wrap := float(fly.debug_state()["yaw"])
	_check(yaw_wrap >= -PI - 1e-6 and yaw_wrap <= PI + 1e-6, "大鼠标位移后 yaw 环绕回 [-π,π] (%.3f)" % yaw_wrap)
	var ke := InputEventKey.new()
	_check(fly.handle_event(ke) == false, "键盘事件不被消费（返回 false）")
	var inactive = _new_fly()
	_check(inactive.handle_event(mm) == false, "未进入时鼠标事件不被消费")
	# 视角变换真实作用于相机基向量
	var fly2 = _fly_at(0.7, 0.3, _sky())
	var cam := Camera3D.new()
	root.add_child(cam)
	fly2.apply_to(cam)
	var fwd := -cam.global_transform.basis.z
	var want := Vector3(-sin(0.7) * cos(0.3), sin(0.3), -cos(0.7) * cos(0.3))
	_check(fwd.normalized().dot(want.normalized()) > 0.9999, "apply_to 后相机朝向与 yaw/pitch 一致")
	cam.queue_free()


# ============================================================
# 15. FOV / apply_to
# ============================================================
func _probe_fov_and_apply_to() -> void:
	print("[FLYCAM] --- 15 FOV & apply_to ---")
	var cam := Camera3D.new()
	root.add_child(cam)
	var fly = _fly_at(0.0, 0.0, _sky())
	fly.apply_to(cam)
	_check(absf(cam.fov - 42.0) < 1e-6, "apply_to 写入基础 FOV 42")
	Input.action_press("fly_forward")
	Input.action_press("fly_boost")
	_run(fly, 2.0)
	Input.action_release("fly_boost")
	var d: Dictionary = fly.debug_state()
	_check(absf(float(d["fov"]) - 46.5) < 0.15, "加速稳定 FOV=%.2f ≈ 46.5（42+4.5）" % float(d["fov"]))
	fly.apply_to(cam)
	_check(absf(cam.fov - float(d["fov"])) < 1e-6, "apply_to 把加速 FOV 写进相机")
	_check(cam.global_transform.origin.is_equal_approx(d["pos"] as Vector3), "apply_to 把位置写进相机")
	_run(fly, 1.0)
	fly.apply_to(cam)
	var d2: Dictionary = fly.debug_state()
	_check(absf(float(d2["fov"]) - 42.0) < 0.1, "松开加速后 FOV 回落 %.2f ≈ 42" % float(d2["fov"]))
	_check(absf(cam.fov - 42.0) < 0.1, "相机 FOV 同步回落")
	Input.action_release("fly_forward")
	# 自定义 boost_fov_add=8 生效
	var fly2 = _new_fly({"boost_fov_add": 8.0})
	fly2.enter(Transform3D(Basis.IDENTITY, _sky()), 42.0)
	Input.action_press("fly_forward")
	Input.action_press("fly_boost")
	_run(fly2, 2.0)
	Input.action_release("fly_boost")
	Input.action_release("fly_forward")
	var d3: Dictionary = fly2.debug_state()
	_check(absf(float(d3["fov"]) - 50.0) < 0.2, "configure boost_fov_add=8 → FOV %.2f ≈ 50" % float(d3["fov"]))
	fly.apply_to(null)
	_check(true, "apply_to(null) 不崩溃")
	cam.queue_free()


# ============================================================
# 16. 退出回位混合
# ============================================================
func _probe_exit_blend() -> void:
	print("[FLYCAM] --- 16 exit blend ---")
	var fly = _new_fly()
	var from := Transform3D(Basis.from_euler(Vector3(-0.2, 0.6, 0.0)), Vector3(0.0, 25.0, 0.0))
	var home := Transform3D(Basis.from_euler(Vector3(0.15, -1.1, 0.0)), Vector3(55.0, 11.0, -40.0))
	fly.enter(from, 42.0, home)
	var cam := Camera3D.new()
	root.add_child(cam)
	fly.apply_to(cam)
	Input.action_press("fly_forward")
	Input.action_press("fly_boost")
	_run(fly, 1.5)
	Input.action_release("fly_boost")
	Input.action_release("fly_forward")
	var before: Dictionary = fly.debug_state()
	_check(float(before["fov"]) > 45.5, "退出前处于加速 FOV=%.2f" % float(before["fov"]))
	var exit_start: Vector3 = before["pos"]
	# 退出混合期仍按住 W，验证输入不再生效、仍平滑回位
	Input.action_press("fly_forward")
	fly.request_exit()
	_check(fly.active, "request_exit 后混合期 active 仍为 true")
	var d0: Dictionary = fly.debug_state()
	_check(bool(d0["exiting"]), "request_exit 后 exiting=true")
	_check(fly.handle_event(InputEventMouseMotion.new()) == false, "退出混合期鼠标事件不再被消费")
	var first_ret: bool = fly.update(0.05, _terrain)
	_check(first_ret == true, "退出混合首帧 update 返回 true")
	var d1: Dictionary = fly.debug_state()
	var moved := (d1["pos"] as Vector3).distance_to(exit_start)
	var total_dist := exit_start.distance_to(home.origin)
	_check(moved > 1e-6 and moved < total_dist * 0.05, "首帧只走了 %.2f%%（smoothstep 缓入、不瞬移）" % (moved / total_dist * 100.0))
	_check(float(d1["fov"]) > 42.0 and float(d1["fov"]) < float(before["fov"]), "混合期 FOV 从 %.2f 向 42 过渡（%.2f）" % [float(before["fov"]), float(d1["fov"])])
	# 跑完剩余混合
	var total := 0.05
	var ret := true
	while ret and total < 5.0:
		ret = fly.update(DT, _terrain)
		total += DT
	Input.action_release("fly_forward")
	var dur := float(fly.debug_state()["exit_blend_dur"])
	_check(total >= dur - 1e-6 and total <= dur + 2.0 * DT + 1e-6, "混合时长 %.4fs ≈ exit_blend_dur=%.2fs（含末帧）" % [total, dur])
	var df: Dictionary = fly.debug_state()
	_check(fly.active == false, "混合结束后 active=false")
	_check(not bool(df["exiting"]), "混合结束后 exiting=false")
	_check((df["pos"] as Vector3).is_equal_approx(home.origin), "混合结束后位置精确回到 home")
	_check(absf(angle_difference(float(df["yaw"]), _yaw_of_home(home))) < 1e-4, "混合结束后 yaw 回到 home")
	_check(absf(float(df["pitch"]) - _pitch_of_home(home)) < 1e-4, "混合结束后 pitch 回到 home")
	_check(absf(float(df["fov"]) - 42.0) < 1e-6, "混合结束后 FOV 精确恢复 42")
	_check(cam.global_transform.is_equal_approx(home), "末帧已把精确 home 位姿写回 Camera3D")
	_check(absf(cam.fov - 42.0) < 1e-6, "末帧 Camera3D.fov 恢复 42")
	# 结束后完全退出控制
	_check(fly.update(DT, _terrain) == false, "结束后 update 返回 false（交还 main 轨道相机）")
	fly.request_exit()
	_check(fly.active == false, "结束后再次 request_exit 为安全 no-op")
	var sh: Dictionary = fly.saved_home()
	_check((sh["transform"] as Transform3D).is_equal_approx(home) and absf(float(sh["fov"]) - 42.0) < 1e-6, "saved_home 在退出后不变")
	cam.queue_free()

	# 立即退出（无移动）也应正常结束
	var fly2 = _new_fly()
	var at := Transform3D(Basis.IDENTITY, _sky())
	fly2.enter(at, 42.0)
	_check(fly2.active, "再次 enter 后 active=true（可重复进入）")
	fly2.request_exit()
	var t2 := 0.0
	var r2 := true
	while r2 and t2 < 3.0:
		r2 = fly2.update(DT, _terrain)
		t2 += DT
	_check(fly2.active == false and (fly2.debug_state()["pos"] as Vector3).is_equal_approx(at.origin), "未移动就退出：混合结束回到原位且 active=false")
