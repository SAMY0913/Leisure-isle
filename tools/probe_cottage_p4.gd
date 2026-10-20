extends SceneTree
## P4 cottage 专用探针：不加载 isle.tscn、不截图，只 build 岛屿小屋并做数值/共面/穿模检查。
## 运行：console --headless --path D:/休闲小岛幻境/游戏工程 --script res://tools/probe_cottage_p4.gd

const M := preload("res://scripts/isle_math.gd")

var _boxes: Array = []       # 同轴 BoxMesh（非玻璃）：{xf, size, path}
var _occluders: Array = []   # 所有网格（含旋转/MultiMesh）的局部 AABB，用于判断共面面是否被遮挡
var _glass_paths: Array = []
var _bbox_min := Vector3(1e9, 1e9, 1e9)
var _bbox_max := Vector3(-1e9, -1e9, -1e9)
var _mesh_total: int = 0
var _box_total: int = 0

func _init() -> void:
	var holder := Node3D.new()
	holder.name = "ProbeHolder"
	var d: Dictionary = IsleCottage.build(holder)
	var root: Node3D = d["root"] as Node3D
	print("[COTTAGE] built root=", root.name, " children=", root.get_child_count())
	_collect(root, Transform3D.IDENTITY, "Cottage")
	_check_coplanar()
	_check_steps(root, d)
	_check_attic(root, d)
	_check_opening(root)
	_check_perches(d)
	_check_keys(d)
	print("[COTTAGE] bbox_local=min(%.2f,%.2f,%.2f) max(%.2f,%.2f,%.2f) size(%.2f,%.2f,%.2f)" % [
		_bbox_min.x, _bbox_min.y, _bbox_min.z, _bbox_max.x, _bbox_max.y, _bbox_max.z,
		_bbox_max.x - _bbox_min.x, _bbox_max.y - _bbox_min.y, _bbox_max.z - _bbox_min.z])
	print("[COTTAGE] meshes=%d boxes=%d glass=%d window_mats=%d glass_mats=%d window_halos=%d light_sources=%d" % [
		_mesh_total, _box_total, _glass_paths.size(), (d["window_mats"] as Array).size(), (d["glass_mats"] as Array).size(),
		(d["window_halos"] as Array).size(), (d["light_sources"] as Array).size()])
	print("[COTTAGE] glass_paths=%s" % str(_glass_paths))
	print("[COTTAGE] done")
	holder.free()
	quit()

func _is_glass_mi(mi: MeshInstance3D) -> bool:
	var mat: Material = mi.material_override
	if mat is ShaderMaterial:
		var shader: Shader = (mat as ShaderMaterial).shader
		if shader != null and String(shader.resource_path).contains("glass"):
			return true
	return false

func _collect(node: Node, xf: Transform3D, path: String) -> void:
	if node is MeshInstance3D:
		_mesh_total += 1
		var mi := node as MeshInstance3D
		var mesh: Mesh = mi.mesh
		if mesh != null:
			_expand_aabb(xf, mesh.get_aabb())
			_occluders.append(_aabb_of(xf, mesh.get_aabb()))
		if (mi as MeshInstance3D).mesh is BoxMesh:
			_box_total += 1
			if _is_glass_mi(mi):
				_glass_paths.append(path)
			else:
				_boxes.append({"xf": xf, "size": (mesh as BoxMesh).size, "path": path})
	elif node is MultiMeshInstance3D:
		var mm := (node as MultiMeshInstance3D).multimesh
		if mm != null and mm.mesh != null:
			for i in range(mm.instance_count):
				var x: Transform3D = xf * mm.get_instance_transform(i)
				_expand_aabb(x, mm.mesh.get_aabb())
				_occluders.append(_aabb_of(x, mm.mesh.get_aabb()))
	for c in node.get_children():
		if c is Node3D:
			_collect(c, xf * (c as Node3D).transform, path + "/" + String(c.name))
		else:
			_collect(c, xf, path + "/" + String(c.name))

func _aabb_of(xf: Transform3D, aabb: AABB) -> Dictionary:
	var mn := Vector3(1e9, 1e9, 1e9)
	var mx := Vector3(-1e9, -1e9, -1e9)
	for i in range(8):
		var p: Vector3 = aabb.position + Vector3(
			aabb.size.x if (i & 1) != 0 else 0.0,
			aabb.size.y if (i & 2) != 0 else 0.0,
			aabb.size.z if (i & 4) != 0 else 0.0)
		var w: Vector3 = xf * p
		mn = Vector3(minf(mn.x, w.x), minf(mn.y, w.y), minf(mn.z, w.z))
		mx = Vector3(maxf(mx.x, w.x), maxf(mx.y, w.y), maxf(mx.z, w.z))
	return {"mn": mn, "mx": mx}

func _expand_aabb(xf: Transform3D, aabb: AABB) -> void:
	var a: Dictionary = _aabb_of(xf, aabb)
	var mn: Vector3 = a["mn"]
	var mx: Vector3 = a["mx"]
	_bbox_min = Vector3(minf(_bbox_min.x, mn.x), minf(_bbox_min.y, mn.y), minf(_bbox_min.z, mn.z))
	_bbox_max = Vector3(maxf(_bbox_max.x, mx.x), maxf(_bbox_max.y, mx.y), maxf(_bbox_max.z, mx.z))

func _identity_basis(b: Basis) -> bool:
	for i in range(3):
		for j in range(3):
			var want: float = 1.0 if i == j else 0.0
			if absf(b[i][j] - want) > 0.0005:
				return false
	return true

func _hidden(axis: int, coord: float, side: int, rmn: Vector2, rmx: Vector2) -> bool:
	# 面朝向为 side*axis；若在朝向一侧紧贴平面处存在覆盖整个重叠区的实体，则该面不可见（内部面）
	var a1: int = (axis + 1) % 3
	var a2: int = (axis + 2) % 3
	for o in _occluders:
		var mn: Vector3 = o["mn"]
		var mx: Vector3 = o["mx"]
		if side > 0:
			if mn[axis] > coord + 0.002:
				continue
			if mx[axis] < coord + 0.05:
				continue
		else:
			if mx[axis] < coord - 0.002:
				continue
			if mn[axis] > coord - 0.05:
				continue
		var omn := Vector2(mn[a1], mn[a2])
		var omx := Vector2(mx[a1], mx[a2])
		if omn.x <= rmn.x + 0.004 and omn.y <= rmn.y + 0.004 and omx.x >= rmx.x - 0.004 and omx.y >= rmx.y - 0.004:
			return true
	return false

func _check_coplanar() -> void:
	var faces: Array = []
	for b in _boxes:
		var xf: Transform3D = b["xf"]
		if not _identity_basis(xf.basis):
			continue
		var bs: Vector3 = b["size"]
		var mn: Vector3 = xf.origin - bs * 0.5
		var mx: Vector3 = xf.origin + bs * 0.5
		for axis in range(3):
			for side in [-1, 1]:
				var coord: float = mx[axis] if side > 0 else mn[axis]
				var a1: int = (axis + 1) % 3
				var a2: int = (axis + 2) % 3
				faces.append({
					"axis": axis, "side": side, "coord": coord,
					"rmn": Vector2(mn[a1], mn[a2]), "rmx": Vector2(mx[a1], mx[a2]),
					"origin": xf.origin, "size": bs, "path": b["path"],
				})
	var total: int = 0
	var hidden: int = 0
	var hidden_shown: int = 0
	var visible: int = 0
	var shown: int = 0
	for i in range(faces.size()):
		var f1: Dictionary = faces[i]
		for j in range(i + 1, faces.size()):
			var f2: Dictionary = faces[j]
			if f1["axis"] != f2["axis"] or f1["side"] != f2["side"]:
				continue
			if absf(float(f1["coord"]) - float(f2["coord"])) > 0.0005:
				continue
			var m1: Vector2 = f1["rmn"]
			var m2: Vector2 = f2["rmn"]
			var x1: Vector2 = f1["rmx"]
			var x2: Vector2 = f2["rmx"]
			var ovx: float = minf(x1.x, x2.x) - maxf(m1.x, m2.x)
			var ovy: float = minf(x1.y, x2.y) - maxf(m1.y, m2.y)
			if ovx <= 0.0001 or ovy <= 0.0001:
				continue
			var area: float = ovx * ovy
			if area <= 0.004:
				continue
			total += 1
			if _hidden(f1["axis"], f1["coord"], f1["side"], Vector2(maxf(m1.x, m2.x), maxf(m1.y, m2.y)), Vector2(minf(x1.x, x2.x), minf(x1.y, x2.y))):
				hidden += 1
				if hidden_shown < 12:
					print("[COTTAGE]   hidden axis=%d side=%d coord=%.3f area=%.4f A=%s B=%s" % [
						f1["axis"], f1["side"], f1["coord"], area, String(f1["path"]), String(f2["path"])])
					hidden_shown += 1
				continue
			visible += 1
			if shown < 30:
				print("[COTTAGE]   zfight axis=%d side=%d coord=%.3f area=%.4f A:o(%.2f,%.2f,%.2f)s(%.2f,%.2f,%.2f) B:o(%.2f,%.2f,%.2f)s(%.2f,%.2f,%.2f)" % [
					f1["axis"], f1["side"], f1["coord"], area,
					(f1["origin"] as Vector3).x, (f1["origin"] as Vector3).y, (f1["origin"] as Vector3).z,
					(f1["size"] as Vector3).x, (f1["size"] as Vector3).y, (f1["size"] as Vector3).z,
					(f2["origin"] as Vector3).x, (f2["origin"] as Vector3).y, (f2["origin"] as Vector3).z,
					(f2["size"] as Vector3).x, (f2["size"] as Vector3).y, (f2["size"] as Vector3).z])
				shown += 1
	print("[COTTAGE] coplanar_pairs=%d visible_zfight=%d hidden_internal=%d sample_hidden_printed=%d" % [total, visible, hidden, hidden_shown])

func _find(root: Node, target: String) -> Node:
	if String(root.name) == target:
		return root
	for c in root.get_children():
		var r := _find(c, target)
		if r != null:
			return r
	return null

func _check_steps(root: Node3D, d: Dictionary) -> void:
	var steps := _find(root, "PorchSteps") as Node3D
	if steps == null:
		print("[COTTAGE] steps=FAIL missing PorchSteps")
		return
	var n: int = int(steps.get_meta("step_count", 0))
	var rise: float = float(steps.get_meta("rise", 0.0))
	var run: float = float(steps.get_meta("run", 0.0))
	var z_top: float = float(steps.get_meta("z_top", 0.0))
	var boxes: Array = []
	for c in steps.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh is BoxMesh:
			var mi := c as MeshInstance3D
			var bs: Vector3 = (mi.mesh as BoxMesh).size
			boxes.append({"cx": mi.position.x, "mn": mi.position - bs * 0.5, "mx": mi.position + bs * 0.5})
	boxes.sort_custom(func(a, b): return a["mx"].z < b["mx"].z)
	var ok: bool = boxes.size() == n and n >= 6
	var prev_zmax: float = z_top
	var prev_top: float = float(steps.get_meta("top_y", 0.0))
	var floating: int = 0
	for i in range(boxes.size()):
		var b: Dictionary = boxes[i]
		var top: float = b["mx"].y
		if absf(b["mn"].z - prev_zmax) > 0.002:
			ok = false
		if absf(prev_top - top - rise) > 0.003:
			ok = false
		if float(b["mx"].y - b["mn"].y) < top + 0.99:
			pass
		# 每级底面必须低于该级前缘地形（不悬浮）
		var wp: Vector3 = root.transform * Vector3(b["cx"], 0.0, b["mx"].z + 0.02)
		var g: float = M.terrain_height(wp.x, wp.z) - root.position.y
		if b["mn"].y > g + 0.01:
			floating += 1
		prev_zmax = b["mx"].z
		prev_top = top
	var last_top: float = prev_top
	var wpos: Vector3 = root.transform * Vector3(0.0, 0.0, z_top + run * float(n) + 0.05)
	var gy: float = M.terrain_height(wpos.x, wpos.z) - root.position.y
	print("[COTTAGE] steps count=%d rise=%.4f run=%.3f top_y=%.3f bottom_y=%.3f z_top=%.2f geometry_ok=%s floating=%d last_top=%.3f ground_at_bottom=%.3f" % [
		n, rise, run, float(steps.get_meta("top_y", 0.0)), float(steps.get_meta("bottom_y", 0.0)), z_top, str(ok), floating, last_top, gy])

func _check_attic(root: Node3D, d: Dictionary) -> void:
	var win := _find(root, "AtticWindow") as Node3D
	var ia := _find(root, "AtticInterior") as Node3D
	if win == null or ia == null:
		print("[COTTAGE] attic=FAIL missing nodes")
		return
	var ww: float = float(win.get_meta("width", 0.0))
	var wh: float = float(win.get_meta("height", 0.0))
	var aw: Vector3 = d["attic_window_world"]
	var expect_win: Vector3 = root.transform * Vector3(0.0, 7.0, M.HOUSE_D * 0.5 + 0.02)
	var expect_lamp: Vector3 = root.transform * Vector3(0.55, 6.84, 2.85)
	var lamp_w: Vector3 = d["attic_lamp_world"]
	print("[COTTAGE] attic_window width=%.2f height=%.2f meta_center=%s world=%s win_world_ok=%s win_delta=%.3f" % [ww, wh, str(win.get_meta("center")), str(aw), str((aw - expect_win).length() < 0.02), (aw - expect_win).length()])
	print("[COTTAGE] attic_lamp world=%s expect=%s lamp_world_ok=%s delta=%.3f" % [str(lamp_w), str(expect_lamp), str((lamp_w - expect_lamp).length() < 0.02), (lamp_w - expect_lamp).length()])
	var pitch: float = atan(M.HOUSE_ROOF_H / (M.HOUSE_W * 0.5))
	var ridge_y: float = 0.55 + M.HOUSE_WALL_H + M.HOUSE_ROOF_H
	var cp: float = cos(pitch)
	var floor_y: float = 5.70
	var fcount: int = int(ia.get_meta("furniture_count", 0))
	var aabbs: Array = []
	_collect_aabb(ia, Transform3D.IDENTITY, aabbs)
	var worst_top: float = -1e9
	var worst_x: float = 0.0
	var bad_top: int = 0
	var bad_floor: int = 0
	for ab in aabbs:
		var mn: Vector3 = ab["mn"]
		var mx: Vector3 = ab["mx"]
		var xmax: float = maxf(absf(mn.x), absf(mx.x))
		var under: float = ridge_y - xmax * tan(pitch) - 0.16 / cp
		if mx.y > worst_top:
			worst_top = mx.y
			worst_x = xmax
		if mx.y > under + 0.002:
			bad_top += 1
		if mn.y < floor_y - 0.03:
			bad_floor += 1
	print("[COTTAGE] attic_furniture meta=%d meshes=%d roof_clip=%d floor_sink=%d worst_top=%.2f abs_x=%.2f roof_under=%.2f" % [
		fcount, aabbs.size(), bad_top, bad_floor, worst_top, worst_x, ridge_y - worst_x * tan(pitch) - 0.16 / cp])

func _collect_aabb(node: Node, xf: Transform3D, out: Array) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh is BoxMesh:
			var bs: Vector3 = (mi.mesh as BoxMesh).size
			var mn: Vector3 = xf.origin - bs * 0.5
			var mx: Vector3 = xf.origin + bs * 0.5
			if _identity_basis(xf.basis):
				out.append({"mn": mn, "mx": mx})
	for c in node.get_children():
		if c is Node3D:
			_collect_aabb(c, xf * (c as Node3D).transform, out)

func _check_opening(root: Node3D) -> void:
	# 门洞上角的拱形墙体补板（自定义网格，非 BoxMesh，不能用洞口遮挡检查）
	var sp := root.find_child("DoorSpandrel", true, false)
	var sp_surf: int = -1
	if sp is MeshInstance3D:
		sp_surf = (sp as MeshInstance3D).mesh.get_surface_count()
	print("[COTTAGE] door_spandrel_present=%s surfaces=%d" % [str(sp != null), sp_surf])
	# 阁楼窗下部洞口（x±1.60, y 5.70..6.15，前墙）不应被任何“大块”盒子覆盖
	var covered: int = 0
	for b in _boxes:
		var xf: Transform3D = b["xf"]
		if not _identity_basis(xf.basis):
			continue
		var bs: Vector3 = b["size"]
		var mn: Vector3 = xf.origin - bs * 0.5
		var mx: Vector3 = xf.origin + bs * 0.5
		if bs.x < 1.0 or bs.y < 0.25:
			continue
		if mx.z < 3.90 or mn.z > 4.35:
			continue
		var ox: float = minf(mx.x, 1.60) - maxf(mn.x, -1.60)
		var oy: float = minf(mx.y, 6.15) - maxf(mn.y, 5.70)
		if ox > 0.01 and oy > 0.01:
			covered += 1
	print("[COTTAGE] attic_opening_clear=%s covered_boxes=%d" % [str(covered == 0), covered])
	# 大门洞口（x±1.30, y 0.55..4.20，前墙 z 3.90..4.35）同样不应被大块盒子盖住
	var door_covered: int = 0
	for b in _boxes:
		var xf: Vector3 = (b["xf"] as Transform3D).origin
		if not _identity_basis((b["xf"] as Transform3D).basis):
			continue
		var bs: Vector3 = b["size"]
		var mn: Vector3 = xf - bs * 0.5
		var mx: Vector3 = xf + bs * 0.5
		if bs.x < 1.0 or bs.y < 0.25:
			continue
		if mx.z < 3.90 or mn.z > 4.35:
			continue
		var ox: float = minf(mx.x, 1.30) - maxf(mn.x, -1.30)
		var oy: float = minf(mx.y, 4.20) - maxf(mn.y, 0.55)
		if ox > 0.01 and oy > 0.01:
			door_covered += 1
	print("[COTTAGE] door_opening_clear=%s covered_boxes=%d" % [str(door_covered == 0), door_covered])

func _check_perches(d: Dictionary) -> void:
	var perches: Array = d["perches"]
	var kinds: Dictionary = {}
	var ids: Dictionary = {}
	var bad: int = 0
	var required: Array = ["id", "pos", "facing", "radius", "kind"]
	for p in perches:
		if not (p is Dictionary):
			bad += 1
			continue
		var pd: Dictionary = p
		for k in required:
			if not pd.has(k):
				bad += 1
		if pd.has("id"):
			ids[String(pd["id"])] = true
		if pd.has("kind"):
			kinds[String(pd["kind"])] = int(kinds.get(String(pd["kind"]), 0)) + 1
		if pd.has("pos"):
			var wp: Vector3 = pd["pos"]
			if wp.y <= M.terrain_height(wp.x, wp.z):
				bad += 1
				print("[COTTAGE]   perch_bad id=%s pos=%s terrain=%.2f" % [String(pd.get("id", "?")), str(wp), M.terrain_height(wp.x, wp.z)])
	print("[COTTAGE] perches=%d unique_ids=%d bad=%d kinds=%s" % [perches.size(), ids.size(), bad, str(kinds)])
	var shown: int = 0
	for p in perches:
		if shown >= 10:
			break
		if p is Dictionary:
			print("[COTTAGE]   perch id=%s kind=%s pos=(%.2f,%.2f,%.2f) facing=(%.2f,%.2f,%.2f) r=%.2f" % [
				p.get("id", "?"), p.get("kind", "?"), (p["pos"] as Vector3).x, (p["pos"] as Vector3).y, (p["pos"] as Vector3).z,
				((p.get("facing", Vector3.ZERO)) as Vector3).x, ((p.get("facing", Vector3.ZERO)) as Vector3).y, ((p.get("facing", Vector3.ZERO)) as Vector3).z,
				float(p.get("radius", 0.0))])
			shown += 1

func _check_keys(d: Dictionary) -> void:
	var keys: Array = ["root", "door_pivot", "door_hit", "chimney_hit", "chimney_top", "window_mats", "window_halos",
		"lantern_mat", "lantern_halo", "perches", "lantern_world", "light_sources", "glass_mats", "interior_pos",
		"front_window_world", "interior_lamp_world", "fireplace_world", "attic_window_world", "attic_lamp_world"]
	var missing: Array = []
	for k in keys:
		if not d.has(k):
			missing.append(k)
	print("[COTTAGE] keys_missing=%s" % str(missing))
	print("[COTTAGE] attic_lamp_world=%s" % str(d.get("attic_lamp_world", "?")))
	print("[COTTAGE] door_hit_pos=%s chimney_hit_pos=%s lantern_world=%s light_count=%d" % [
		str((d["door_hit"] as Node3D).position), str((d["chimney_hit"] as Node3D).position),
		str(d["lantern_world"]), (d["light_sources"] as Array).size()])
