extends SceneTree
## P7-V3.1 猫咪尾巴 A/B 探针（窗口模式）
##
## 目的：门廊猫在低机位正面时，两耳之间出现一个拱形剪影。为**确定它是不是尾巴**
## （而不是耳朵/头球/其它部件），在同一机位拍两张：尾巴可见 / 尾巴隐藏，做像素差。
## 差集区域即尾巴在画面上的贡献范围；若拱形在差集内，则确认归属。
##
## 运行：
##   ENG --path <PROJ> --resolution 1600x900 --script res://tools/probe_cat_tail_ab_p7v31.gd -- --out=<目录>

var _out := "D:/休闲小岛幻境/开发产物/p7v31/shots/tailab/"

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--out="):
			_out = s.substr(6)
	if not _out.ends_with("/"):
		_out += "/"
	DirAccess.make_dir_recursive_absolute(_out)

	await process_frame
	var packed: PackedScene = load("res://isle.tscn") as PackedScene
	var main: Node = packed.instantiate()
	get_root().add_child(main)
	await process_frame
	await process_frame
	var menu = main.get("_menu")
	if menu != null and menu.has_method("instant_finish"):
		menu.call("instant_finish")
	main.set("_mode", 1)
	main.set("_time_source", "sim")
	main.set("_realtime", false)
	main.set("_started", true)
	main.set("_paused", true)
	main.set("_auto_orbit", false)
	main.set("_blending", "")
	main.set("_sim_seconds", 0.0)
	main.call("_set_time_of_day", 745.0)
	main.call("_update_lighting")
	var hud = main.get("_hud")
	if hud != null and hud.has_method("set_hud_visible"):
		hud.call("set_hud_visible", false, false)
	await process_frame
	await process_frame
	# 关掉 main 的每帧更新：否则主循环会立刻把相机重置回轨道机位，
	# 同时也能让本子树的 toon 材质保持静止，A/B 只剩"尾巴可见性"一个变量。
	main.set_process(false)

	var cat: Node3D = _find_named(get_root(), "PorchCat") as Node3D
	var cam: Camera3D = main.get("_cam") as Camera3D
	if cat == null or cam == null:
		print("[TAILAB] FAIL cat/cam 缺失")
		quit(1)
		return
	# 冻结待机动画，保证两张图除尾巴可见性外完全一致
	var drv: Node = cat.get_node_or_null("CatIdleDriver")
	if drv != null:
		drv.set_process(false)
		var ctl = drv.get("controller")
		if ctl != null:
			ctl.call("_reset_pose")

	var cp := cat.global_position
	var cfwd := (cat.global_transform.basis * Vector3(0.0, 0.0, 1.0)).normalized()
	# 与 probe_frame_p7v3.gd 的 cat_close_front_day 完全一致的机位
	_look(cam, cp + cfwd * 1.25 + Vector3(0.0, 0.80, 0.0), cp + Vector3(0.0, 0.26, 0.0), 35.0)
	for i in range(6):
		await process_frame

	await _shot("cat_tailab_with.png")
	var tail: Node3D = cat.get_node_or_null("Tail") as Node3D
	if tail == null:
		print("[TAILAB] FAIL Tail 缺失")
		quit(1)
		return
	tail.visible = false
	for i in range(4):
		await process_frame
	await _shot("cat_tailab_without.png")
	tail.visible = true
	for i in range(4):
		await process_frame
	await _shot("cat_tailab_with2.png")

	print("[TAILAB] RESULT ok=3 dir=", _out)
	await process_frame
	quit(0)

func _look(cam: Camera3D, from: Vector3, to: Vector3, fov: float) -> void:
	cam.global_position = from
	cam.look_at(to, Vector3.UP)
	cam.fov = fov
	cam.current = true

func _shot(nm: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := _out + nm
	var err := img.save_png(path)
	print("[TAILAB] shot=", path, " err=", err)

func _find_named(n: Node, nm: String) -> Node:
	if String(n.name) == nm:
		return n
	for c in n.get_children():
		var r := _find_named(c, nm)
		if r != null:
			return r
	return null
