extends SceneTree
# tools/probe_lights_p7v3.gd — 灯光预算核对（Lead）

func _init() -> void:
	var packed: PackedScene = load("res://isle.tscn")
	var main: Node = packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	if main.has_method("debug_light_state"):
		var st: Dictionary = main.call("debug_light_state")
		print("[LIGHTS] active=", st.get("active"), " budget=", st.get("budget"), " lamp_count=", st.get("lamp_count"))
		var lights: Array = st.get("lights", [])
		for i in lights.size():
			var L: Dictionary = lights[i]
			print("  #%d kind=%s energy=%.3f range=%.2f pos=%s" % [i, str(L.get("kind")), float(L.get("energy")), float(L.get("range")), str(L.get("pos"))])
	else:
		print("[LIGHTS] no debug_light_state")
	quit(0)
