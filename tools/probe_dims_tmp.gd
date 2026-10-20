extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var scene: PackedScene = load("res://isle.tscn")
	var m = scene.instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	var w = m.get("_world")
	print("[DIM] lighthouse_height=", w.get("lighthouse_height"))
	var lh: Node3D = m.get("_lighthouse")
	print("[DIM] lighthouse_pos=", lh.global_position if lh != null else "null")
	var lamp: Node3D = m.get("_lighthouse_lamp")
	print("[DIM] lamp_pos=", lamp.global_position if lamp != null else "null")
	var origin: Node3D = m.get("_beam_origin_node")
	print("[DIM] beam_origin_pos=", origin.global_position if origin != null else "null")
	print("[DIM] island_diameter=", w.get("island_diameter"))
	print("[DIM] sail_dock_pos=", w.get("sail_dock_pos"))
	print("[DIM] sail_dock_heading=", w.get("sail_dock_heading"))
	print("[DIM] sun_alt=", m.get("_sun_alt"))
	var routes = w.get("sail_routes")
	print("[DIM] routes=", routes.size() if routes != null else -1)
	if routes != null:
		for i in range(routes.size()):
			var r: Dictionary = routes[i]
			print("[DIM] route[" , i, "] name=", r.get("name"), " kind=", r.get("kind"), " out=", (r.get("out", []) as Array).size(), " back=", (r.get("back", []) as Array).size())
	print("[DIM] camera=", m.get("_cam").global_position if m.get("_cam") != null else "null")
	m.queue_free()
	await process_frame
	quit(0)
