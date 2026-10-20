extends SceneTree

func _initialize() -> void:
	var scene: PackedScene = load("res://isle.tscn")
	var m: Node = scene.instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	await process_frame
	m.set("_mode", 1)
	m.set("_started", true)
	m.set("_blending", "")
	if m.has_method("_apply_pose"):
		pass
	await process_frame
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	await process_frame
	var up := InputEventKey.new()
	up.keycode = KEY_ESCAPE
	up.physical_keycode = KEY_ESCAPE
	up.pressed = false
	Input.parse_input_event(up)
	await process_frame
	var menu: Node = m.get("_menu")
	print("[ESC] mode=", m.get("_mode"), " blending=", m.get("_blending"))
	print("[ESC] menu_visible=", menu.get("menu_visible"), " menu_node_visible=", menu.visible, " anim=", menu.get_anim_state())
	print("[ESC] hud_visible=", m.get("_hud").get("_visible_now") if m.get("_hud") != null else "n/a")
	quit(0)
