extends SceneTree
## Register persistent InputMap actions (Phase 6). Run once headless:
##   Godot..._console.exe --headless --path <proj> --script res://tools/register_input6.gd
## Idempotent: writes the same action dict again if it already exists.

func _key(code: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.device = -1
	return ev

func _register(action: String, events: Array) -> void:
	var dict := {"deadzone": 0.5, "events": events}
	InputMap.add_action(action, 0.5)
	for ev in events:
		InputMap.action_add_event(action, ev)
	ProjectSettings.set_setting("input/" + action, dict)
	print("[INPUT] registered ", action, " events=", events.size())

func _init() -> void:
	# 自动运镜开关（C 键）；已占用键：R/Space/T/Tab/H/F2/F3/F11/Esc/[ ]/1-5。
	_register("toggle_auto_orbit", [_key(KEY_C)])
	# 宽屏/超宽屏不拉伸：canvas_items + expand 让逻辑画布随窗口扩展，UI 依赖锚点。
	ProjectSettings.set_setting("display/window/stretch/aspect", "expand")
	var err: int = ProjectSettings.save()
	print("[INPUT] ProjectSettings.save() err=", err)
	for a in ["toggle_auto_orbit"]:
		print("[INPUT] exists ", a, "=", InputMap.has_action(a), " setting=", ProjectSettings.has_setting("input/" + a))
	quit(0 if err == OK else 1)
