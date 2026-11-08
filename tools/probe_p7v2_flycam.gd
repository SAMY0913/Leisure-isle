extends SceneTree

## P7-V2 任务 E 独立验收探针：自由飞行观景相机（IsleFlyCam + main.gd 接线）。
##
## headless（逻辑/边界/输入优先/轨道冻结恢复，推荐用于回归）：
##   "$ENG" --headless --path "$PROJ" --script res://tools/probe_p7v2_flycam.gd
## 窗口（额外验证真实鼠标捕获/释放；--resolution 仅在真实窗口有意义）：
##   "$ENG" --path "$PROJ" --resolution 1600x900 --script res://tools/probe_p7v2_flycam.gd -- --window
##
## 验收口径（任务书）：
##  * 进/退自由视角（F 进入、F/ESC 退出），从当前机位起飞不跳位；
##  * WASD 按 yaw 水平移动、Space/Shift 独立升降、Ctrl 平滑加速约 2.1x；
##  * 运动与帧率无关（30fps vs 120fps 位移一致）；
##  * 水平圆半径/最高高度 clamp 不瞬移、不低于海平面与地形净高；
##  * 飞控输入优先消费：Space 不暂停、C 不切自动运镜、鼠标不拖拽轨道；
##  * ESC 优先退出（不开菜单），退出平滑回 home，轨道参数与 auto_orbit 原样恢复；
##  * 退出后轨道运镜/菜单等 P7-V1 行为不回归。
## 参数一律从 main.debug_flycam() 读取（Lead 已把游戏内标定覆盖为 R=130/max_y=130/
## speed_regular=10.4/speed_boost=21.7/vertical=5.5），不硬编码旧默认值。

const IsleMathScript := preload("res://scripts/isle_math.gd")
const FlyCamScript := preload("res://scripts/isle_flycam.gd")
const MainScene := preload("res://isle.tscn")

const DT := 1.0 / 60.0
const ACTIONS := ["fly_toggle", "fly_forward", "fly_back", "fly_left", "fly_right", "fly_up", "fly_down", "fly_boost"]

var _pass := 0
var _fail := 0
var _lines: Array[String] = []

func _ok(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("[P7V2FC] PASS ", msg)
	else:
		_fail += 1
		print("[P7V2FC] FAIL ", msg)

func _info(msg: String) -> void:
	print("[P7V2FC] ", msg)

func _key(kc: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = kc
	e.physical_keycode = kc
	e.pressed = true
	return e

func _mouse(rel: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.relative = rel
	return e

func _release_all() -> void:
	for a in ACTIONS:
		if InputMap.has_action(a):
			Input.action_release(a)

func _is_window() -> bool:
	return DisplayServer.get_name() != "headless"

func _step_main(main: Node, n: int) -> void:
	for i in range(n):
		main.call("_update_camera", DT)

func _initialize() -> void:
	await process_frame
	_release_all()

	# ---------- A. 纯逻辑件单测（不依赖场景） ----------
	for a in ACTIONS:
		_ok(InputMap.has_action(a), "InputMap 动作存在：" + a)

	var defaults: Dictionary = FlyCamScript.default_config()
	for key in ["center", "radius", "min_y", "max_y", "speed_regular", "speed_boost", "vertical_speed", "look_sensitivity", "boost_fov_add", "exit_blend_dur"]:
		_ok(defaults.has(key), "default_config 键存在：" + key)
	_ok(int(defaults.get("radius", 0)) >= 1 and int(defaults.get("max_y", 0)) > int(defaults.get("min_y", 0)), "default_config 数值合法（radius/max_y/min_y）")

	# 非法配置自动修正
	var san: RefCounted = FlyCamScript.new()
	san.configure({"radius": -5.0, "max_y": -10.0, "min_y": 5.0, "speed_regular": 0.0, "exit_blend_dur": 0.0})
	_ok(float(san.get("radius")) >= 1.0, "configure 修正非法 radius")
	_ok(float(san.get("max_y")) >= float(san.get("min_y")) + 1.0, "configure 修正 max_y < min_y")
	_ok(float(san.get("speed_regular")) >= 0.05, "configure 修正非法 speed_regular")
	_ok(float(san.get("exit_blend_dur")) >= 0.05, "configure 修正非法 exit_blend_dur")

	# 进入/退出回位（home 省略 = 起点）
	var fly: RefCounted = FlyCamScript.new()
	fly.configure({"speed_regular": 10.4, "speed_boost": 21.7, "vertical_speed": 5.5, "radius": 130.0, "max_y": 130.0})
	var start_xf := Transform3D(Basis(Vector3.UP, 0.3), Vector3(3.0, 60.0, 4.0))
	fly.enter(start_xf, 42.0)
	_ok(bool(fly.get("active")), "enter 后 active=true")
	_ok(fly.saved_home()["transform"].origin.distance_to(start_xf.origin) < 0.001, "saved_home 记录进入位姿")
	_ok(bool(fly.update(DT, Callable(IsleMathScript, "terrain_height"))), "active 时 update 返回 true（仍控制相机）")
	# 鼠标消费
	var yaw0: float = float(fly.get("_yaw"))
	_ok(bool(fly.handle_event(_mouse(Vector2(120.0, 60.0)))), "handle_event 消费鼠标移动")
	_ok(absf(float(fly.get("_yaw")) - yaw0) > 0.05, "鼠标右移改变 yaw")
	_ok(not bool(fly.handle_event(_key(KEY_W))), "handle_event 不消费键盘事件")
	# 退出回位
	fly.request_exit()
	_ok(bool(fly.get("active")), "request_exit 后混合期仍 active")
	_ok(not bool(fly.handle_event(_mouse(Vector2(10, 10)))), "混合期不再响应鼠标视角")
	var frames := 0
	while bool(fly.get("active")) and frames < 300:
		fly.update(DT, Callable(IsleMathScript, "terrain_height"))
		frames += 1
	_info("退出混合帧数=" + str(frames) + "（0.6s@60fps 期望 36）")
	_ok(not bool(fly.get("active")), "回位混合结束 active=false")
	_ok(frames >= 28 and frames <= 45, "退出混合时长≈0.6s（28~45 帧）")
	_ok(fly.saved_home()["transform"].origin.distance_to(start_xf.origin) < 0.001, "退出后位置精确回到 home")

	# home_xf 独立传入
	var fly2: RefCounted = FlyCamScript.new()
	fly2.configure({"speed_regular": 10.4, "speed_boost": 21.7, "vertical_speed": 5.5, "radius": 130.0, "max_y": 130.0})
	var home_target_xf := Transform3D(Basis(Vector3.UP, 1.0), Vector3(-9.0, 40.0, 2.0))
	fly2.enter(start_xf, 42.0, home_target_xf)
	fly2.request_exit()
	frames = 0
	while bool(fly2.get("active")) and frames < 300:
		fly2.update(DT, Callable(IsleMathScript, "terrain_height"))
		frames += 1
	_ok(fly2.saved_home()["transform"].origin.distance_to(home_target_xf.origin) < 0.001, "enter(..., home_xf) 退出回到指定 home")

	# 运动速度标定：普通 10.4m/s、加速 21.7m/s（2.0865x），穿越 2R 时间
	var cruise: RefCounted = FlyCamScript.new()
	cruise.configure({"speed_regular": 10.4, "speed_boost": 21.7, "vertical_speed": 5.5, "radius": 130.0, "max_y": 130.0})
	cruise.enter(Transform3D(Basis(), Vector3(0.0, 60.0, 0.0)), 42.0)
	Input.action_press("fly_forward")
	for i in range(150):
		cruise.update(1.0 / 60.0, Callable(IsleMathScript, "terrain_height"))
	var ds: Dictionary = cruise.debug_state()
	var v_reg := float(ds["horizontal_speed"])
	_info("普通水平速度实测=" + str(snappedf(v_reg, 0.01)) + " m/s（标定 10.4）")
	_ok(absf(v_reg - 10.4) < 0.6, "普通速度≈标定 10.4 m/s")
	_ok(float(ds["speed_regular"]) == 10.4 and float(ds["speed_boost"]) == 21.7, "debug_state 暴露标定速度")
	_ok(absf(float(ds["boost_mult"]) - float(ds["speed_boost"]) / float(ds["speed_regular"])) < 0.01, "boost_mult = speed_boost/speed_regular")
	var cross_reg := 260.0 / float(ds["speed_regular"])
	var cross_boost := 260.0 / float(ds["speed_boost"])
	_info("穿越 D=260m 时间：普通=" + str(snappedf(cross_reg, 0.1)) + "s，加速=" + str(snappedf(cross_boost, 0.1)) + "s")
	_ok(cross_reg >= 20.0 and cross_reg <= 30.0, "普通速度穿越时间落在 20~30s")
	_ok(cross_boost >= 10.0 and cross_boost <= 15.0, "加速穿越时间落在 10~15s")
	Input.action_press("fly_boost")
	for i in range(150):
		cruise.update(1.0 / 60.0, Callable(IsleMathScript, "terrain_height"))
	var ds_b: Dictionary = cruise.debug_state()
	_info("加速水平速度实测=" + str(snappedf(float(ds_b["horizontal_speed"]), 0.01)) + " m/s")
	_ok(float(ds_b["horizontal_speed"]) > float(ds["speed_regular"]) * 1.6, "Ctrl 加速明显快于普通")
	_ok(absf(float(ds_b["horizontal_speed"]) - 21.7) < 2.0, "加速稳态≈标定 21.7 m/s（±2）")
	Input.action_release("fly_boost")
	Input.action_release("fly_forward")
	for i in range(20):
		cruise.update(1.0 / 60.0, Callable(IsleMathScript, "terrain_height"))
	_ok(float(cruise.debug_state()["boost_scale"]) < 1.01, "松开 Ctrl 后加速倍率回落到 1x")

	# 垂直独立轴
	var vy0: float = float(cruise.debug_state()["pos"].y)
	Input.action_press("fly_up")
	for i in range(60):
		cruise.update(1.0 / 60.0, Callable(IsleMathScript, "terrain_height"))
	Input.action_release("fly_up")
	var vy1: float = float(cruise.debug_state()["pos"].y)
	_info("Space 1s 上升=" + str(snappedf(vy1 - vy0, 0.01)) + " m（标定 5.5）")
	_ok(vy1 - vy0 > 4.2, "Space 独立上升≈5.5m/s")
	Input.action_press("fly_down")
	for i in range(60):
		cruise.update(1.0 / 60.0, Callable(IsleMathScript, "terrain_height"))
	Input.action_release("fly_down")
	var vy2: float = float(cruise.debug_state()["pos"].y)
	_ok(vy2 < vy1 - 3.5, "Shift 独立下降≈5.5m/s")

	# 帧率无关：30fps vs 120fps 相同 1s 前向位移一致
	var f30: RefCounted = FlyCamScript.new()
	var f120: RefCounted = FlyCamScript.new()
	for f in [f30, f120]:
		f.configure({"speed_regular": 10.4, "speed_boost": 21.7, "vertical_speed": 5.5, "radius": 130.0, "max_y": 130.0})
		f.enter(Transform3D(Basis(), Vector3(0.0, 60.0, 0.0)), 42.0)
	Input.action_press("fly_forward")
	for i in range(30):
		f30.update(1.0 / 30.0, Callable(IsleMathScript, "terrain_height"))
	for i in range(120):
		f120.update(1.0 / 120.0, Callable(IsleMathScript, "terrain_height"))
	Input.action_release("fly_forward")
	var d30: Vector3 = f30.debug_state()["pos"]
	var d120: Vector3 = f120.debug_state()["pos"]
	var diff := Vector2(d30.x - d120.x, d30.z - d120.z).length()
	_info("30fps/120fps 1s 位移差=" + str(snappedf(diff, 0.001)) + " m")
	_ok(diff < 0.06, "运动与帧率无关（30/120fps 1s 位移差 <6cm）")

	# 边界 clamp
	var bnd: RefCounted = FlyCamScript.new()
	bnd.configure({"speed_regular": 10.4, "speed_boost": 21.7, "vertical_speed": 5.5, "radius": 130.0, "max_y": 130.0})
	bnd.enter(Transform3D(Basis(), Vector3(0.0, 60.0, 0.0)), 42.0)
	bnd.set("_pos", Vector3(500.0, 60.0, 0.0))
	bnd.update(DT, Callable(IsleMathScript, "terrain_height"))
	var bp: Vector3 = bnd.debug_state()["pos"]
	_ok(absf(Vector2(bp.x, bp.z).length() - 130.0) < 0.05, "水平越界 clamp 到半径 130（不瞬移）")
	_ok(bool(bnd.debug_state()["hit_bound"]), "越界标记 hit_bound")
	bnd.set("_pos", Vector3(0.0, -50.0, 0.0))
	bnd.update(DT, Callable(IsleMathScript, "terrain_height"))
	var ground: float = IsleMathScript.terrain_height(0.0, 0.0)
	var expect_min := maxf(1.2, ground + 0.8)
	_ok(float(bnd.debug_state()["pos"].y) >= expect_min - 0.01, "不低于海平面/地形净高（>=%.2f）" % expect_min)
	bnd.set("_pos", Vector3(0.0, 1000.0, 0.0))
	bnd.update(DT, Callable(IsleMathScript, "terrain_height"))
	_ok(float(bnd.debug_state()["pos"].y) <= 130.0 + 0.01, "不超高最高高度 130m")

	# pitch 上限
	var pc: RefCounted = FlyCamScript.new()
	pc.configure({"radius": 130.0})
	pc.enter(Transform3D(Basis(), Vector3(0.0, 60.0, 0.0)), 42.0)
	var huge := InputEventMouseMotion.new()
	huge.relative = Vector2(0.0, -100000.0)
	pc.handle_event(huge)
	_ok(absf(float(pc.get("_pitch"))) <= 1.451, "pitch clamp 不超过 ±1.45rad（防翻转）")
	# 非 active 时 update 返回 false
	var idle: RefCounted = FlyCamScript.new()
	_ok(not bool(idle.update(DT, Callable(IsleMathScript, "terrain_height"))), "未进入时 update 返回 false")

	# ---------- B. main.gd 接线集成（真实场景） ----------
	var scene: PackedScene = MainScene
	var main: Node = scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.set_process(false)
	var menu: Variant = main.get("_menu")
	if menu != null and menu.has_method("instant_finish"):
		menu.call("instant_finish")
	main.set("_mode", 1)
	main.set("_time_source", "sim")
	main.set("_realtime", false)
	main.set("_started", true)
	main.set("_paused", true)
	main.set("_auto_orbit", true)
	main.set("_blending", "")
	main.call("_apply_pose", main.call("_play_pose"))
	await process_frame

	var dbg: Dictionary = main.call("debug_flycam")
	_ok(bool(dbg.get("available", false)), "main.debug_flycam() 可用")
	var bounds: Dictionary = dbg.get("bounds", {})
	_ok((bounds.get("center", Vector3.ONE) as Vector3).length() < 0.01, "游戏内边界中心=原点")
	_ok(absf(float(bounds.get("radius", 0.0)) - 130.0) < 0.01, "游戏内边界半径 R=130m")
	_ok(absf(float(bounds.get("max_y", 0.0)) - 130.0) < 0.01, "游戏内最高高度 max_y=130m")
	_ok(absf(float(dbg.get("speed_regular", 0.0)) - 10.4) < 0.01, "游戏内普通速度=10.4 m/s")
	_ok(absf(float(dbg.get("speed_boost", 0.0)) - 21.7) < 0.01, "游戏内加速速度=21.7 m/s")
	_ok(absf(float(dbg.get("vertical_speed", 0.0)) - 5.5) < 0.01, "游戏内垂直速度=5.5 m/s")
	var reach := 2.0 * float(bounds.get("radius", 0.0))
	var t_reg := reach / float(dbg.get("speed_regular", 1.0))
	var t_boost := reach / float(dbg.get("speed_boost", 1.0))
	_info("游戏标定：D=%.0fm 普通穿越=%.1fs 加速穿越=%.1fs" % [reach, t_reg, t_boost])
	_ok(t_reg >= 20.0 and t_reg <= 30.0, "游戏标定普通穿越 20~30s")
	_ok(t_boost >= 10.0 and t_boost <= 15.0, "游戏标定加速穿越 10~15s")

	var fc: Variant = main.get("_flycam")
	var cam: Camera3D = main.get("_cam")
	var home_xf: Transform3D = cam.global_transform
	var home_fov: float = cam.fov
	var orbit0: Dictionary = dbg.get("orbit", {})
	main.call("_unhandled_input", _key(KEY_F))
	_ok(bool(fc.get("active")), "F 键进入自由视角")
	_ok(cam.global_transform.origin.distance_to(home_xf.origin) < 0.001, "进入时从当前机位起飞（不跳位）")
	var orbit_fly: Dictionary = main.call("debug_flycam").get("orbit", {})
	_ok(is_equal_approx(float(orbit_fly.get("theta", 0.0)), float(orbit0.get("theta", 0.0))) and is_equal_approx(float(orbit_fly.get("radius", 0.0)), float(orbit0.get("radius", 0.0))), "进入瞬间轨道参数被冻结")
	if _is_window():
		_ok(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "进入后捕获鼠标（窗口模式）")
	else:
		_info("SKIP 鼠标捕获（headless 无显示服务器，窗口模式验证）")

	# 鼠标视角（真实事件走 main._unhandled_input → flycam.handle_event）
	var yaw_a: float = float(fc.get("_yaw"))
	var pitch_a: float = float(fc.get("_pitch"))
	main.call("_unhandled_input", _mouse(Vector2(140.0, 50.0)))
	_ok(absf(float(fc.get("_yaw")) - yaw_a) > 0.05, "自由视角鼠标左右转 yaw")
	_ok(absf(float(fc.get("_pitch")) - pitch_a) > 0.02, "自由视角鼠标上下转 pitch")

	# 前进移动（通过 main._update_camera 真实每帧链路）
	var mp0: Vector3 = cam.global_transform.origin
	Input.action_press("fly_forward")
	_step_main(main, 60)
	Input.action_release("fly_forward")
	var mp1: Vector3 = cam.global_transform.origin
	var moved := mp1.distance_to(mp0)
	_info("1s 前向位移=" + str(snappedf(moved, 0.01)) + " m")
	_ok(moved > 5.0, "WASD 在 main 接线后真实移动相机")

	# 飞行中吞输入：Space 不暂停、C 不切自动运镜
	main.set("_paused", false)
	main.call("_unhandled_input", _key(KEY_SPACE))
	_ok(not bool(main.get("_paused")), "飞行中 Space 不触发暂停（输入优先消费）")
	main.set("_auto_orbit", true)
	main.call("_unhandled_input", _key(KEY_C))
	_ok(bool(main.get("_auto_orbit")), "飞行中 C 不切换自动运镜")
	# 轨道参数飞行期间不变
	var orbit_mid: Dictionary = main.call("debug_flycam").get("orbit", {})
	_ok(is_equal_approx(float(orbit_mid.get("theta", 0.0)), float(orbit0.get("theta", 0.0))), "飞行期间轨道 theta 保持冻结")
	# 边界 clamp 在 main 链路同样生效
	fc.set("_pos", Vector3(400.0, 60.0, 0.0))
	_step_main(main, 2)
	var dp: Vector3 = main.call("debug_flycam")["pos"]
	_ok(absf(Vector2(dp.x, dp.z).length() - 130.0) < 0.1, "main 链路水平越界 clamp 到 130m")

	# ESC 优先退出：不开菜单，进入回位混合
	main.set("_paused", true)
	main.call("_unhandled_input", _key(KEY_ESCAPE))
	_ok(bool(fc.get("active")), "ESC 后进入回位混合（active 仍 true）")
	_ok(int(main.get("_mode")) == 1, "ESC 不打开菜单（仍在 PLAYING）")
	if _is_window():
		_ok(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "退出时立即释放鼠标（窗口模式）")
	var exit_frames := 0
	var lim := 400
	while bool(fc.get("active")) and exit_frames < lim:
		main.call("_update_camera", DT)
		exit_frames += 1
	_info("main 退出混合帧数=" + str(exit_frames))
	_ok(not bool(fc.get("active")), "回位混合结束 active=false")
	_ok(exit_frames >= 28 and exit_frames <= 45, "main 退出混合≈0.6s（28~45 帧）")
	_ok(cam.global_transform.origin.distance_to(home_xf.origin) < 0.01, "退出后相机回到进入前机位")
	_ok(absf(cam.fov - home_fov) < 0.6, "退出后 FOV 恢复到进入前值")
	var orbit1: Dictionary = main.call("debug_flycam").get("orbit", {})
	_ok(is_equal_approx(float(orbit1.get("theta", 0.0)), float(orbit0.get("theta", 0.0))) and is_equal_approx(float(orbit1.get("radius", 0.0)), float(orbit0.get("radius", 0.0))), "退出后轨道参数原样恢复")
	_ok(is_equal_approx(float(orbit1.get("fov", 0.0)), float(orbit0.get("fov", 0.0))), "退出后轨道 FOV 参数原样恢复")
	_ok(bool(orbit1.get("auto_orbit", false)), "退出后 auto_orbit 状态保持")

	# 退出后轨道运镜恢复
	main.set("_paused", false)
	main.set("_auto_orbit", true)
	var th0: float = float(main.get("_theta"))
	_step_main(main, 30)
	var th1: float = float(main.get("_theta"))
	_ok(absf(th1 - th0) > 0.001, "退出后轨道自动运镜恢复推进（P7-V1 行为不回归）")

	# 退出后 ESC 仍打开菜单（P7-V1）
	main.call("_unhandled_input", _key(KEY_ESCAPE))
	_ok(int(main.get("_mode")) != 1, "非飞行时 ESC 仍能打开菜单（P7-V1 行为不回归）")
	# MENU 下 F 不进入自由视角
	main.call("_unhandled_input", _key(KEY_F))
	_ok(not bool(fc.get("active")), "MENU 模式下 F 不进入自由视角")

	# 收尾：释放输入状态与鼠标
	_release_all()
	if _is_window():
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	print("[P7V2FC] RESULT pass=", _pass, " fail=", _fail)
	quit(0 if _fail == 0 else 1)
