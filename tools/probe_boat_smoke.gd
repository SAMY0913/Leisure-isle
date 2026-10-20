extends SceneTree
const MainScene := preload("res://isle.tscn")
func _initialize() -> void:
	await process_frame
	var m = MainScene.instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	print("main children=", m.get_child_count())
	for k in ["_sailboat","_sail_routes","_boat_state","_boat_dock_pos","_boat_route_kind","_sail_phase","_wake"]:
		var v = m.get(k)
		print(k, " = ", (v if not (v is Object) else v.get_class()))
	if m.get("_sail_routes") != null:
		for r in m._sail_routes:
			print("route ", r.get("name","?"), " keys=", r.keys())
	print("dock=", m._boat_dock_pos, " heading=", m._boat_dock_heading, " state=", m._boat_state)
	quit(0)
