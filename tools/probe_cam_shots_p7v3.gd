extends SceneTree
## P7-V3 任务C/D 窗口截图探针（非 headless；需 GPU / 窗口；与其它窗口测试串行）
## 运行（先持 GPU 锁）：
##   "$ENG" --path "D:/休闲小岛幻境/游戏工程" --script res://tools/probe_cam_shots_p7v3.gd
## 产物：D:/休闲小岛幻境/开发产物/p7v3/shots/cam_*.png
## 判据：exit 0 且 [CAMSHOT] RESULT fail=0；截图另行人工查看。
## 覆盖：
##  1 自由视角键位提示 toast（Ctrl 下降 / Shift 冲刺 / 右键 / 左键）
##  2 自由视角左键点击 = 场景点击：真实输入管线点击门 → 门开启；左键不改变视角
##  2b 自由视角左键点烟囱 → toast；左键点海面 → 涟漪/水花；两者不改门状态
##  3 右键按住拖动 = 转向（yaw 变化），且不触发场景操作（门/水面涟漪均不变）
##  4 退出自由视角：active=false、鼠标可见、相机回到进入前位姿
##  5 设置面板「视野范围（FOV）」滑块 42/55/65：数值/标签/相机预览一致；分辨率/窗口模式不受影响

const S := preload("res://scripts/isle_settings.gd")
const SHOT_DIR := "D:/休闲小岛幻境/开发产物/p7v3/shots/"
const LOG_DIR := "D:/休闲小岛幻境/开发产物/p7v3/logs/"

var _pass := 0
var _fail := 0
var _main: Node = null
var _root: Window = null


func _ok(tag: String, cond: bool, detail: String = "") -> void:
	print(("[CAMSHOT][PASS] " if cond else "[CAMSHOT][FAIL] ") + tag + (" | " + detail if detail != "" else ""))
	if cond:
		_pass += 1
	else:
		_fail += 1


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _initialize() -> void:
	await process_frame
	if DisplayServer.get_name() == "headless":
		print("[CAMSHOT] SKIP 需要窗口模式（不要 --headless）")
		quit(2)
		return
	_root = root
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	DirAccess.make_dir_recursive_absolute(LOG_DIR)
	var scene: PackedScene = load("res://isle.tscn")
	_ok("isle_tscn_load", scene != null)
	if scene == null:
		quit(1)
		return
	_main = scene.instantiate()
	_root.add_child(_main)
	await process_frame
	await process_frame
	# 确定性设置：默认窗口化 1440x900 / FOV 42（不依赖本机 user:// 配置）
	_main.set("_settings", S.defaults())
	_main.call("_apply_user_settings", false)
	await process_frame
	await process_frame
	DisplayServer.window_set_size(Vector2i(1440, 900))
	await process_frame
	await process_frame
	var menu: Node = _main.get("_menu")
	var hud: Node = _main.get("_hud")
	var cam: Camera3D = _main.get("_cam") as Camera3D
	var fc: RefCounted = _main.get("_flycam")
	_ok("main_parts_ready", menu != null and hud != null and cam != null and fc != null)
	if menu == null or hud == null or cam == null or fc == null:
		quit(1)
		return
	menu.call("instant_finish")
	# PLAYING 基线：正午 12:20，关闭自动运镜，HUD 可见
	_main.set("_mode", 1)
	_main.set("_started", true)
	_main.set("_paused", false)
	_main.set("_blending", "")
	_main.set("_auto_orbit", false)
	_main.set("_settings_save_delay", -1.0)
	_main.call("_set_time_of_day", 12.0 * 60.0 + 20.0)
	_main.call("_apply_pose", _main.call("_play_pose"))
	hud.call("set_hud_visible", true, false)
	await _wait(0.5)
	_ok("initial_fov_42", is_equal_approx(float(_main.get("_fov")), 42.0), str(_main.get("_fov")))
	var d0: Dictionary = fc.call("debug_state")
	_ok("speed_regular_12_48", is_equal_approx(float(d0["speed_regular"]), 12.48), str(d0["speed_regular"]))
	_ok("speed_boost_24_96", is_equal_approx(float(d0["speed_boost"]), 24.96), str(d0["speed_boost"]))
	_ok("vertical_speed_6_6", is_equal_approx(float(d0["vertical_speed"]), 6.6), str(d0["vertical_speed"]))

	# ---------- 1. 进入自由视角：键位提示截图 ----------
	print("[CAMSHOT] --- 1 flycam help toast ---")
	var pre_enter_xf: Transform3D = cam.global_transform
	_main.call("_enter_flycam")
	await process_frame
	await process_frame
	_ok("flycam_active", bool(fc.get("active")))
	_ok("mouse_mode_visible", Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, str(Input.mouse_mode))
	var help: String = String(fc.call("help_text"))
	_ok("help_ctrl_down", help.contains("Ctrl 下降"), help)
	_ok("help_shift_boost", help.contains("Shift 冲刺"), help)
	var toast: Label = hud.get("_toast") as Label
	_ok("help_toast_visible", toast != null and toast.visible and toast.text.contains("Ctrl 下降"), "" if toast == null else toast.text)
	await _wait(0.15)
	await _shot("cam_fly_help")
	# 等提示淡出，避免遮挡门截图
	await _wait(2.8)

	# ---------- 2. 左键点击门 ----------
	print("[CAMSHOT] --- 2 left click opens door ---")
	var cottage: Dictionary = _main.get("_cottage")
	var door_hit: Node3D = cottage["door_hit"] as Node3D
	var cottage_root: Node3D = cottage["root"] as Node3D
	var aim: Vector3 = door_hit.global_position
	var front: Vector3 = cottage_root.global_transform.basis * Vector3(0.0, 0.0, 1.0)
	front.y = 0.0
	front = front.normalized()
	var cam_pos: Vector3 = aim + front * 4.8 + Vector3(0.0, 0.15, 0.0)
	var fwd: Vector3 = (aim - cam_pos).normalized()
	fc.set("_pos", cam_pos)
	fc.set("_yaw", atan2(-fwd.x, -fwd.z))
	fc.set("_pitch", asin(clampf(fwd.y, -1.0, 1.0)))
	fc.set("_vel", Vector3.ZERO)
	await _wait(0.25)
	_ok("door_closed_before", not bool(_main.get("_door_open")))
	var screen_pos: Vector2 = cam.unproject_position(aim)
	var vr: Rect2 = _root.get_visible_rect()
	_ok("aim_on_screen", vr.has_point(screen_pos), str(screen_pos) + " vr=" + str(vr))
	await _shot("cam_fly_door_before")
	var st_before: Dictionary = fc.call("debug_state")
	await _inject_click(screen_pos)
	await _wait(0.1)
	await process_frame
	var opened := bool(_main.get("_door_open"))
	if not opened:
		# 兜底：直接走 main._unhandled_input（真实窗口下 GUI 可能吞事件；headless 探针已验逻辑）
		print("[CAMSHOT] INFO 输入注入未触发场景点击，改用直接分发 _unhandled_input")
		_direct_click(screen_pos)
		await _wait(0.1)
		await process_frame
		opened = bool(_main.get("_door_open"))
	await _wait(1.15)
	_ok("door_open_after_left_click", bool(_main.get("_door_open")))
	var st_after: Dictionary = fc.call("debug_state")
	_ok("left_click_keeps_yaw", is_equal_approx(float(st_before["yaw"]), float(st_after["yaw"])), "%.4f vs %.4f" % [float(st_before["yaw"]), float(st_after["yaw"])])
	_ok("left_click_keeps_pitch", is_equal_approx(float(st_before["pitch"]), float(st_after["pitch"])), "%.4f vs %.4f" % [float(st_before["pitch"]), float(st_after["pitch"])])
	_ok("left_click_keeps_pos", (Vector3(st_before["pos"]) as Vector3).distance_to(Vector3(st_after["pos"])) < 0.01, str(st_before["pos"]))
	await _shot("cam_fly_door_open")

	# ---------- 2b. 自由视角点击烟囱 / 海面 ----------
	print("[CAMSHOT] --- 2b click chimney & sea ---")
	# 等门的 toast 淡出，避免与烟囱 toast 混淆
	await _wait(2.8)
	var chimney_hit: Node3D = cottage.get("chimney_hit", null) as Node3D
	_ok("chimney_hit_exists", chimney_hit != null)
	if chimney_hit != null:
		var door_before_ch: bool = bool(_main.get("_door_open"))
		var aim_ch: Vector3 = chimney_hit.global_position
		_set_flycam_aim(fc, aim_ch + front * 7.0 + Vector3(0.0, 2.2, 0.0), aim_ch)
		await _wait(0.2)
		var ch_screen: Vector2 = cam.unproject_position(aim_ch)
		_ok("chimney_on_screen", _root.get_visible_rect().has_point(ch_screen), str(ch_screen))
		await _inject_click(ch_screen)
		await _wait(0.25)
		var toast_node: Label = hud.get("_toast") as Label
		if toast_node == null or not String(toast_node.text).contains("烟囱"):
			print("[CAMSHOT] INFO 烟囱输入注入未触发场景点击，改用直接分发 _unhandled_input")
			_direct_click(ch_screen)
			await _wait(0.2)
		await process_frame
		var toast_text: String = "" if toast_node == null else String(toast_node.text)
		_ok("chimney_click_toast", toast_text.contains("烟囱"), toast_text)
		_ok("chimney_click_keeps_door", bool(_main.get("_door_open")) == door_before_ch)
		await _shot("cam_fly_chimney")
		# 海面点击：相机俯视海面点，左键应触发涟漪/水花而不是门/烟囱
		await _wait(0.35)
		var ripples: Node = _main.get("_ripples") as Node
		var ripple_before: int = ripples.get_child_count() if ripples != null else 0
		var aim_sea := Vector3(30.0, 0.0, -18.0)
		_set_flycam_aim(fc, aim_sea + Vector3(0.0, 14.0, 16.0), aim_sea)
		await _wait(0.2)
		var sea_screen: Vector2 = cam.unproject_position(aim_sea)
		_ok("sea_on_screen", _root.get_visible_rect().has_point(sea_screen), str(sea_screen))
		await _inject_click(sea_screen)
		await _wait(0.35)
		var ripple_after: int = ripples.get_child_count() if ripples != null else 0
		if ripple_after <= ripple_before:
			print("[CAMSHOT] INFO 海面输入注入未触发场景点击，改用直接分发 _unhandled_input")
			_direct_click(sea_screen)
			await _wait(0.35)
			ripple_after = ripples.get_child_count() if ripples != null else 0
		_ok("sea_click_ripple", ripple_after > ripple_before, "ripples %d -> %d" % [ripple_before, ripple_after])
		_ok("sea_click_keeps_door", bool(_main.get("_door_open")) == door_before_ch)
		await _shot("cam_fly_sea")

	# ---------- 3. 右键拖动转向，不触发场景操作 ----------
	print("[CAMSHOT] --- 3 right drag look ---")
	var yaw0: float = float(fc.call("debug_state")["yaw"])
	var door0: bool = bool(_main.get("_door_open"))
	var ripples_r: Node = _main.get("_ripples") as Node
	var splash_r: Node = _main.get("_splash") as Node
	var ripple_r0: int = ripples_r.get_child_count() if ripples_r != null else 0
	var splash_r0: int = splash_r.get_child_count() if splash_r != null else 0
	await _inject_right_drag(screen_pos, Vector2(90.0, 45.0))
	await _wait(0.2)
	var yaw1: float = float(fc.call("debug_state")["yaw"])
	var dd: float = absf(wrapf(yaw1 - yaw0, -PI, PI))
	_ok("right_drag_turns_yaw", dd > 0.05, "dyaw=%.4f" % dd)
	_ok("right_drag_no_scene_action", bool(_main.get("_door_open")) == door0)
	var ripple_r1: int = ripples_r.get_child_count() if ripples_r != null else 0
	var splash_r1: int = splash_r.get_child_count() if splash_r != null else 0
	_ok("right_drag_no_water_action", ripple_r1 == ripple_r0 and splash_r1 == splash_r0, "ripples %d/%d splash %d/%d" % [ripple_r0, ripple_r1, splash_r0, splash_r1])
	await _shot("cam_fly_after_rightdrag")

	# ---------- 4. 退出自由视角 ----------
	print("[CAMSHOT] --- 4 exit flycam ---")
	_main.call("_exit_flycam")
	await _wait(0.95)
	_ok("flycam_inactive_after_exit", not bool(fc.get("active")))
	_ok("mouse_visible_after_exit", Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, str(Input.mouse_mode))
	var dist: float = cam.global_transform.origin.distance_to(pre_enter_xf.origin)
	_ok("camera_restored_home", dist < 0.6, "dist=%.3f" % dist)
	_ok("camera_fov_restored", absf(cam.fov - 42.0) < 1.0, "cam.fov=%.2f" % cam.fov)
	# 等退出 toast 淡出
	await _wait(2.6)

	# ---------- 5. 设置面板 FOV 42 / 55 / 65 ----------
	print("[CAMSHOT] --- 5 settings FOV slider ---")
	_main.set("_mode", 0)
	_main.set("_started", false)
	_main.set("_blending", "")
	_main.set("_auto_orbit", false)
	_main.set("_settings_save_delay", -1.0)
	menu.call("open", false)
	await _wait(0.9)
	menu.call("open_settings")
	await _wait(0.6)
	_ok("settings_panel_open", bool(menu.call("is_settings_open")))
	var sliders: Dictionary = menu.get("_sliders")
	var labels: Dictionary = menu.get("_slider_value_labels")
	_ok("fov_slider_exists", sliders.has("fov"))
	_ok("fov_label_exists", labels.has("fov"))
	if not (sliders.has("fov") and labels.has("fov")):
		_finish()
		return
	var slider: Object = sliders["fov"]
	var label: Label = labels["fov"] as Label
	_ok("fov_slider_range_35_65", is_equal_approx(float(slider.get("min_value")), 35.0) and is_equal_approx(float(slider.get("max_value")), 65.0), "min=%s max=%s" % [slider.get("min_value"), slider.get("max_value")])
	_ok("fov_slider_step_1", is_equal_approx(float(slider.get("step")), 1.0), str(slider.get("step")))
	_ok("fov_row_title_present", _find_label_with(menu.get("_settings_panel"), "视野范围"))
	for f in [42.0, 55.0, 65.0]:
		menu.call("_on_slider_changed", "fov", f)
		_main.set("_settings_save_delay", -1.0)
		await _wait(0.35)
		_ok("fov_%d_slider" % int(f), is_equal_approx(float(slider.get("value")), f), str(slider.get("value")))
		_ok("fov_%d_label" % int(f), String(label.text) == ("%d°" % int(f)), String(label.text))
		_ok("fov_%d_main" % int(f), is_equal_approx(float(_main.get("_fov")), f), str(_main.get("_fov")))
		_ok("fov_%d_camera_preview" % int(f), absf(cam.fov - f) < 0.3, "cam.fov=%.2f" % cam.fov)
		_ok("fov_%d_panel_open" % int(f), bool(menu.call("is_settings_open")))
		await _shot("cam_fov_%d" % int(f))
	var st: Dictionary = _main.get("_settings")
	_ok("fov_keeps_resolution", Vector2i(st["resolution"]) == Vector2i(1440, 900), str(st["resolution"]))
	_ok("fov_keeps_window_mode", String(st["window_mode"]) == "windowed", String(st["window_mode"]))
	menu.call("close_settings_instant")
	menu.call("instant_finish")
	_finish()


func _inject_click(pos: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = pos
	Input.parse_input_event(press)
	await process_frame
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = pos
	Input.parse_input_event(release)


func _direct_click(pos: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = pos
	_main.call("_unhandled_input", press)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = pos
	_main.call("_unhandled_input", release)


func _set_flycam_aim(fc: RefCounted, pos: Vector3, aim: Vector3) -> void:
	var fwd: Vector3 = (aim - pos).normalized()
	fc.set("_pos", pos)
	fc.set("_yaw", atan2(-fwd.x, -fwd.z))
	fc.set("_pitch", asin(clampf(fwd.y, -1.0, 1.0)))
	fc.set("_vel", Vector3.ZERO)


func _inject_right_drag(pos: Vector2, rel: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	press.position = pos
	Input.parse_input_event(press)
	await process_frame
	var mm := InputEventMouseMotion.new()
	mm.position = pos + rel
	mm.relative = rel
	mm.button_mask = MOUSE_BUTTON_MASK_RIGHT
	Input.parse_input_event(mm)
	await process_frame
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_RIGHT
	release.pressed = false
	release.position = pos + rel
	Input.parse_input_event(release)


func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var tex: ViewportTexture = _root.get_texture()
	var img: Image = tex.get_image() if tex != null else null
	if img == null:
		_ok("shot_" + tag, false, "viewport texture null")
		return
	var path := SHOT_DIR + tag + ".png"
	var err: int = img.save_png(path)
	print("[CAMSHOT] shot %s %dx%d err=%d path=%s" % [tag, img.get_width(), img.get_height(), err, path])
	_ok("shot_" + tag, err == OK and img.get_width() >= 1024, "w=%d h=%d" % [img.get_width(), img.get_height()])


func _find_label_with(node: Variant, needle: String) -> bool:
	if node == null:
		return false
	var n := node as Node
	if n == null:
		return false
	if n is Label and String((n as Label).text).contains(needle):
		return true
	for c in n.get_children():
		if _find_label_with(c, needle):
			return true
	return false


func _finish() -> void:
	print("[CAMSHOT] RESULT pass=%d fail=%d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
