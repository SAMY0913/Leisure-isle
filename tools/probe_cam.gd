extends Node3D

func _pose_to_transform(p: Dictionary) -> Transform3D:
	var target: Vector3 = p["target"]
	var theta: float = p["theta"]
	var elev: float = p["elev"]
	var r: float = p["r"]
	var pos := target + Vector3(r * cos(elev) * sin(theta), r * sin(elev), r * cos(elev) * cos(theta))
	var t := Transform3D.IDENTITY
	t.origin = pos
	var dir := target - pos
	var right := dir.cross(Vector3.UP)
	if right.length_squared() < 0.000001:
		right = Vector3.RIGHT
	right = right.normalized()
	var cam_up := right.cross(dir.normalized()).normalized()
	t.basis = Basis(right, cam_up, -dir.normalized())
	return t

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	print("[VP] ", get_viewport().get_visible_rect().size)
	var cam := Camera3D.new()
	cam.near = 0.3
	cam.far = 2200.0
	add_child(cam)
	cam.current = true
	var rim: Array = []
	for i in range(64):
		var a: float = TAU * float(i) / 64.0
		var rr: float = IsleMath.coast_radius(a)
		rim.append(Vector3(cos(a) * rr, IsleMath.terrain_height(cos(a) * rr, sin(a) * rr), sin(a) * rr))
	var gy: float = IsleMath.house_ground_y()
	var extra := {
		"roof": Vector3(IsleMath.HOUSE_X, gy + IsleMath.HOUSE_WALL_H + IsleMath.HOUSE_ROOF_H, IsleMath.HOUSE_Z),
		"tree": Vector3(IsleMath.BIG_TREE_X, IsleMath.terrain_height(IsleMath.BIG_TREE_X, IsleMath.BIG_TREE_Z) + 8.5, IsleMath.BIG_TREE_Z),
		"dock_end": IsleMath.dock_end(),
		"boat": IsleMath.dock_end() + Vector3(-IsleMath.dock_dir().z, 0, IsleMath.dock_dir().x) * 2.7 + IsleMath.dock_dir() * 0.9,
	}
	var poses := [
		{"name": "P_cur", "target": Vector3(0, 5.2, 0), "theta": 0.74, "elev": 0.30, "r": 78.0, "fov": 42.0},
		{"name": "A", "target": Vector3(0, 5.0, 0), "theta": 0.74, "elev": 0.28, "r": 82.0, "fov": 42.0},
		{"name": "B", "target": Vector3(0, 4.8, 0), "theta": 0.74, "elev": 0.27, "r": 84.0, "fov": 42.0},
		{"name": "C", "target": Vector3(0, 5.4, 0), "theta": 0.74, "elev": 0.30, "r": 86.0, "fov": 42.0},
		{"name": "D", "target": Vector3(0, 5.6, 0), "theta": 0.74, "elev": 0.32, "r": 82.0, "fov": 42.0},
		{"name": "E", "target": Vector3(0, 4.9, 0), "theta": 0.74, "elev": 0.26, "r": 80.0, "fov": 42.0},
		{"name": "F", "target": Vector3(0, 5.2, 0), "theta": 0.74, "elev": 0.30, "r": 88.0, "fov": 44.0},
	]
	for p in poses:
		cam.fov = float(p["fov"])
		cam.global_transform = _pose_to_transform(p)
		await get_tree().process_frame
		var minx := 1e9
		var maxx := -1e9
		var miny := 1e9
		var maxy := -1e9
		for q in rim:
			var uv: Vector2 = cam.unproject_position(q)
			minx = minf(minx, uv.x); maxx = maxf(maxx, uv.x)
			miny = minf(miny, uv.y); maxy = maxf(maxy, uv.y)
		for k in extra.keys():
			var uv2: Vector2 = cam.unproject_position(extra[k])
			minx = minf(minx, uv2.x); maxx = maxf(maxx, uv2.x)
			miny = minf(miny, uv2.y); maxy = maxf(maxy, uv2.y)
		var uv_d: Vector2 = cam.unproject_position(extra["dock_end"])
		var uv_b: Vector2 = cam.unproject_position(extra["boat"])
		var fwd := -cam.global_transform.basis.z
		var horiz := Vector3(fwd.x, 0.0, fwd.z).normalized()
		var hz: Vector2 = cam.unproject_position(cam.global_position + horiz * 1000.0)
		print("[BBOX] ", String(p["name"]), " x:", int(minx), "-", int(maxx), " y:", int(miny), "-", int(maxy), " horizon_y:", int(hz.y), " dock_y:", int(uv_d.y), " boat_y:", int(uv_b.y), " cam_y:", snappedf(cam.global_position.y, 0.1))
	get_tree().quit()
