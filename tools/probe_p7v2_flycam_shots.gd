extends SceneTree

## P7-V2 任务 E 窗口截图探针：自由飞行视角实际画面（全岛俯瞰/低空/海岸灯塔/退出恢复）。
## 用法（窗口模式，勿加 --headless）：
##  "D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe" --path "D:/休闲小岛幻境/游戏工程" --resolution 1600x900 --script res://tools/probe_p7v2_flycam_shots.gd
const OUT := "D:/休闲小岛幻境/开发产物/p7v2/shots/flycam/"

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	if DisplayServer.get_name() == "headless":
		print("[P7V2FS] 需要窗口模式（非 headless）才能截图")
		quit(1)
		return
	await process_frame
	var scene: PackedScene = load("res://isle.tscn")
	if scene == null:
		print("[P7V2FS] FAIL load")
		quit(1)
		return
	var main: Node = scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var menu: Variant = main.get("_menu")
	if menu != null and menu.has_method("instant_finish"):
		menu.call("instant_finish")
	main.set("_mode", 1)
	main.set("_time_source", "sim")
	main.set("_realtime", false)
	main.set("_started", true)
	main.set("_paused", true)
	main.set("_auto_orbit", false)
	main.set("_blending", "")
	main.call("_set_time_of_day", 12.0 * 60.0 + 20.0)
	await process_frame
	var cam: Camera3D = main.get("_cam")
	var fc: Variant = main.get("_flycam")
	main.call("_enter_flycam")
	print("[P7V2FS] enter active=", fc.get("active"))
	# 1) 高空全岛俯瞰（最高观察高度附近，岛+周边海）
	_fly_to(main, fc, Vector3(0.0, 126.0, 110.0), Vector3(0.0, 5.0, 0.0))
	await _settle()
	await _grab("01_high_overview_day.png", main)
	# 2) 中空海岸 / 码头方向
	_fly_to(main, fc, Vector3(58.0, 42.0, 62.0), Vector3(10.0, 6.0, 10.0))
	await _settle()
	await _grab("02_mid_coast_day.png", main)
	# 3) 低空贴海看灯塔
	_fly_to(main, fc, Vector3(-52.0, 14.0, -58.0), Vector3(-30.0, 9.0, -30.0))
	await _settle()
	await _grab("03_low_lighthouse_day.png", main)
	# 4) 夜景全岛（验证自由视角在夜景下也正常）
	main.call("_set_time_of_day", 22.0 * 60.0 + 10.0)
	_fly_to(main, fc, Vector3(0.0, 126.0, 110.0), Vector3(0.0, 5.0, 0.0))
	await _settle(80)
	await _grab("04_high_overview_night.png", main)
	# 5) 退出：回位到进入前轨道机位
	var home: Transform3D = cam.global_transform  # 此刻是自由相机位置（仅作对照输出）
	main.call("_exit_flycam")
	var n := 0
	while bool(fc.get("active")) and n < 400:
		await process_frame
		n += 1
	print("[P7V2FS] exit frames=", n, " active=", fc.get("active"), " pos=", cam.global_transform.origin)
	await _settle()
	await _grab("05_restored_orbit.png", main)
	print("[P7V2FS] DONE")
	quit(0)

func _fly_to(main: Node, fc: Variant, pos: Vector3, target: Vector3) -> void:
	var fwd := (target - pos).normalized()
	var pitch := asin(clampf(fwd.y, -1.0, 1.0))
	var yaw := atan2(-fwd.x, -fwd.z)
	fc.set("_pos", pos)
	fc.set("_pitch", pitch)
	fc.set("_yaw", yaw)
	fc.set("_vel", Vector3.ZERO)
	var cam: Camera3D = main.get("_cam")
	fc.call("apply_to", cam)

func _settle(frames: int = 40) -> void:
	for i in range(frames):
		await process_frame

func _grab(shot_name: String, main: Node) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = main.get_viewport().get_texture().get_image()
	if img == null:
		print("[P7V2FS] FAIL image ", shot_name)
		return
	img.save_png(OUT + shot_name)
	print("[P7V2FS] SHOT ", OUT, shot_name, " ", img.get_width(), "x", img.get_height())
