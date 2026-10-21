extends SceneTree

## P7-V2 任务 D 窗口截图探针：同一机位下 5 档画质 × 白天/黄昏/夜间 实际画面。
## 约定：输出 开发产物/p7v2/shots/light/
## 用法（窗口模式，勿加 --headless）：
##  "D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe" --path "D:/休闲小岛幻境/游戏工程" --resolution 1600x900 --script res://tools/probe_p7v2_light_shots.gd
const OUT := "D:/休闲小岛幻境/开发产物/p7v2/shots/light/"
const SHOT_Q := [0, 1, 2, 3, 4]

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	await process_frame
	var scene: PackedScene = load("res://isle.tscn")
	if scene == null:
		print("[P7V2LS] FAIL isle.tscn load")
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
	# 路灯真实位置（world lamps）→ 用中间一盏做主取景
	var lamp_positions: Array = []
	var wv: Variant = main.get("_world")
	if wv is Dictionary:
		for l in (wv as Dictionary).get("lamps", []):
			if l is Array and (l as Array).size() >= 3 and (l as Array)[2] is Dictionary:
				lamp_positions.append(((l as Array)[2] as Dictionary).get("pos", Vector3.ZERO))
	print("[P7V2LS] lamps=", lamp_positions.size())
	# 机位：斜俯视主路一段，包含 2-3 盏路灯与路面
	var lamp_mid: Vector3 = Vector3(6.0, 9.0, 9.5)
	if lamp_positions.size() >= 2:
		lamp_mid = ((lamp_positions[0] as Vector3) + (lamp_positions[1] as Vector3)) * 0.5
	var ground := Vector3(lamp_mid.x, lamp_mid.y - 1.98, lamp_mid.z)
	var from := ground + Vector3(7.5, 5.0, 10.0)
	var target := ground + Vector3(0.0, 0.4, 0.5)
	print("[P7V2LS] ground=", ground, " from=", from)

	# 夜景：5 档同机位
	main.call("_set_time_of_day", 22.0 * 60.0 + 10.0)
	for q in SHOT_Q:
		main.call("_apply_quality", q)
		main.call("_pose_look", from, target, 42.0)
		for i in range(36):
			await process_frame
		await _grab("night_q%d.png" % q, main)
	# 夜景近景：低档 vs 最高档（同一灯下路面）
	var close_from := ground + Vector3(3.2, 2.2, 4.2)
	for q in [0, 4]:
		main.call("_apply_quality", q)
		main.call("_pose_look", close_from, ground + Vector3(0, 0.1, 0), 40.0)
		for i in range(30):
			await process_frame
		await _grab("night_close_q%d.png" % q, main)
	# 黄昏
	main.call("_set_time_of_day", 18.0 * 60.0 + 20.0)
	for q in [0, 2, 4]:
		main.call("_apply_quality", q)
		main.call("_pose_look", from, target, 42.0)
		for i in range(30):
			await process_frame
		await _grab("dusk_q%d.png" % q, main)
	# 白天（灯应基本不亮）
	main.call("_set_time_of_day", 12.0 * 60.0)
	for q in [0, 4]:
		main.call("_apply_quality", q)
		main.call("_pose_look", from, target, 42.0)
		for i in range(24):
			await process_frame
		await _grab("day_q%d.png" % q, main)
	print("[P7V2LS] DONE")
	quit(0)

func _grab(shot_name: String, main: Node) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = main.get_viewport().get_texture().get_image()
	if img == null:
		print("[P7V2LS] FAIL image ", shot_name)
		return
	img.save_png(OUT + shot_name)
	print("[P7V2LS] SHOT ", OUT, shot_name, " ", img.get_width(), "x", img.get_height())
