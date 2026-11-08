extends SceneTree
## P7-V3 场景统计探针（headless，确定性快照）
## 用途：基线 / 回归对比的客观计数——节点数、各类渲染节点、材质唯一数、三角形数、灯光数、
##       房屋 cottage 内部导出（light_sources / perches / halo 数量等）、船、猫咪部件。
## 运行：
##   "D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe" --headless --path <PROJ> --script res://tools/probe_stats_p7v3.gd
## 输出：[STATS] key=value 每行一条，最后 [STATS] RESULT ok=1；任何异常 quit(1)。

var _fail: int = 0
var _stats: Dictionary = {}
var _unique_materials: Dictionary = {}

func _initialize() -> void:
	await process_frame
	var packed: PackedScene = load("res://isle.tscn") as PackedScene
	if packed == null:
		print("[STATS] FAIL cannot load res://isle.tscn")
		quit(1)
		return
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
	await process_frame
	# 固定时间（正午）后再统计灯光/材质，保证可重复
	if main.has_method("_set_time_of_day"):
		main.call("_set_time_of_day", 740.0)
	if main.has_method("_update_lighting"):
		main.call("_update_lighting")
	await process_frame
	await process_frame

	var root := get_root()
	var type_counts: Dictionary = {}
	var node_total: int = 0
	var mesh_instances: int = 0
	var multimesh_instances: int = 0
	var light_nodes: int = 0
	var tris: int = 0
	var verts: int = 0
	var unique_meshes: Dictionary = {}
	var aabb_total := AABB()
	var has_aabb := false

	var stack: Array = [root]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		node_total += 1
		var tn := n.get_class()
		type_counts[tn] = int(type_counts.get(tn, 0)) + 1
		if n is Light3D:
			light_nodes += 1
		if n is MeshInstance3D:
			mesh_instances += 1
			var mi: MeshInstance3D = n
			if mi.mesh != null:
				unique_meshes[mi.mesh.get_instance_id()] = true
				_collect_mesh_geo(mi.mesh)
				for s in range(mi.mesh.get_surface_count()):
					var m: Material = mi.mesh.surface_get_material(s)
					_note_mat(m)
				_note_mat(mi.material_override)
				var bb: AABB = mi.get_aabb()
				if not has_aabb:
					aabb_total = bb
					has_aabb = true
				else:
					aabb_total = aabb_total.merge(bb)
		elif n is MultiMeshInstance3D:
			multimesh_instances += 1
			var mmi: MultiMeshInstance3D = n
			if mmi.multimesh != null:
				unique_meshes[mmi.multimesh.mesh.get_instance_id() if mmi.multimesh.mesh != null else 0] = true
				if mmi.multimesh.mesh != null:
					_collect_mesh_geo(mmi.multimesh.mesh)
				_note_mat(mmi.material_override)
		for c in n.get_children():
			stack.append(c)

	_stats["nodes_total"] = node_total
	_stats["node3d"] = int(type_counts.get("Node3D", 0))
	_stats["mesh_instance3d"] = mesh_instances
	_stats["multimesh_instance3d"] = multimesh_instances
	_stats["light3d"] = light_nodes
	_stats["unique_meshes"] = unique_meshes.size()
	_stats["unique_materials"] = _unique_materials.size()
	if has_aabb:
		var sz: Vector3 = aabb_total.size
		_stats["scene_aabb_size"] = "%0.2f,%0.2f,%0.2f" % [sz.x, sz.y, sz.z]
		_stats["scene_aabb_pos"] = "%0.2f,%0.2f,%0.2f" % [aabb_total.position.x, aabb_total.position.y, aabb_total.position.z]

	# 关键类型计数
	for key in ["MeshInstance3D", "MultiMeshInstance3D", "Light3D", "OmniLight3D", "SpotLight3D", "DirectionalLight3D", "Camera3D", "GPUParticles3D", "CPUParticles3D", "AudioStreamPlayer3D", "AudioStreamPlayer", "Label", "Control", "CanvasLayer", "AnimationPlayer", "Tween"]:
		_stats["type_" + key] = int(type_counts.get(key, 0))

	# 房屋 cottage 导出
	var cottage: Dictionary = main.get("_cottage")
	if cottage == null:
		print("[STATS] FAIL no _cottage")
		_fail += 1
	else:
		_stats["cottage_light_sources"] = (cottage.get("light_sources", []) as Array).size()
		_stats["cottage_perches"] = (cottage.get("perches", []) as Array).size()
		_stats["cottage_lantern_halos"] = (cottage.get("lantern_halos", []) as Array).size()
		_stats["cottage_window_halos"] = (cottage.get("window_halos", []) as Array).size()
		_stats["cottage_window_mats"] = (cottage.get("window_mats", []) as Array).size()
		var cr: Node = cottage.get("root")
		if cr != null:
			var cstats := _subtree_stats(cr)
			for k in cstats.keys():
				_stats["cottage_" + str(k)] = cstats[k]
			var pivot: Node3D = cottage.get("door_pivot")
			if pivot != null:
				for nm in ["DoorFanlight", "DoorFanlightTrim"]:
					var f := pivot.get_node_or_null(nm)
					_stats["door_" + nm] = "present" if f != null else "missing"
				_stats["door_fanlight_mesh_vertices"] = _mesh_vertex_count(pivot.get_node_or_null("DoorFanlight"))
				_stats["door_fanlight_mesh_triangles"] = _mesh_triangle_count(pivot.get_node_or_null("DoorFanlight"))
				_stats["door_arch_mesh_vertices"] = _mesh_vertex_count(cr.get_node_or_null("DoorArch"))
				_stats["door_arch_mesh_triangles"] = _mesh_triangle_count(cr.get_node_or_null("DoorArch"))
				_stats["door_spandrel_mesh_vertices"] = _mesh_vertex_count(cr.get_node_or_null("DoorSpandrel"))

	# 船 / 猫 / 世界
	var boat: Node3D = main.get("_sailboat")
	_stats["sailboat_present"] = 1 if boat != null else 0
	if boat != null:
		var bs := _subtree_stats(boat)
		for k in bs.keys():
			_stats["sailboat_" + str(k)] = bs[k]
	var cat := _find_node(get_root(), "PorchCat")
	_stats["porchcat_present"] = 1 if cat != null else 0
	if cat != null:
		var cs := _subtree_stats(cat)
		for k in cs.keys():
			_stats["porchcat_" + str(k)] = cs[k]
	_stats["porchcat_script"] = "yes" if cat.get_script() != null else "no"
	_stats["porchcat_world_pos"] = "%0.2f,%0.2f,%0.2f" % [cat.global_position.x, cat.global_position.y, cat.global_position.z]

	# 灯光表（P7 V2+ 灯光由 shader 全局参数驱动，不是 Light3D 节点）
	if main.has_method("_collect_lights"):
		main.call("_collect_lights")
	await process_frame
	var lights_arr: Array = main.get("_lights") if main.get("_lights") != null else []
	_stats["main_lights"] = lights_arr.size()
	var srcs: Array = main.get("_light_sources") if main.get("_light_sources") != null else []
	_stats["main_light_sources"] = srcs.size()
	var lh: Variant = main.get("_lantern_halos")
	_stats["main_lantern_halos"] = (lh as Array).size() if lh is Array else -1
	_stats["main_door_open"] = 1 if main.get("_door_open") == true else 0

	# 输出
	var keys := _stats.keys()
	keys.sort()
	for k in keys:
		print("[STATS] ", k, "=", _stats[k])
	print("[STATS] RESULT fail=", _fail)
	await process_frame
	quit(0 if _fail == 0 else 1)

func _collect_mesh_geo(mesh: Mesh) -> void:
	if mesh == null:
		return
	for s in range(mesh.get_surface_count()):
		var arr := mesh.surface_get_arrays(s)
		if arr.size() <= Mesh.ARRAY_VERTEX or arr[Mesh.ARRAY_VERTEX] == null:
			continue
		var vcount: int = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var icount: int = 0
		if arr.size() > Mesh.ARRAY_INDEX and arr[Mesh.ARRAY_INDEX] != null:
			icount = (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
		_stats["triangles"] = int(_stats.get("triangles", 0)) + (icount / 3 if icount > 0 else vcount / 3)
		_stats["surface_vertices"] = int(_stats.get("surface_vertices", 0)) + vcount

func _note_mat(m: Material) -> void:
	if m == null:
		return
	_unique_materials[m.get_instance_id()] = true

func _subtree_stats(n: Node) -> Dictionary:
	var out: Dictionary = {"nodes": 0, "mesh": 0, "multimesh": 0, "lights": 0, "materials": 0}
	var mats: Dictionary = {}
	var stack: Array = [n]
	while stack.size() > 0:
		var c: Node = stack.pop_back()
		out["nodes"] = int(out["nodes"]) + 1
		if c is MeshInstance3D:
			out["mesh"] = int(out["mesh"]) + 1
			var mi: MeshInstance3D = c
			_note_mat_map(mats, mi.material_override)
			if mi.mesh != null:
				for s in range(mi.mesh.get_surface_count()):
					_note_mat_map(mats, mi.mesh.surface_get_material(s))
		elif c is MultiMeshInstance3D:
			out["multimesh"] = int(out["multimesh"]) + 1
			_note_mat_map(mats, (c as MultiMeshInstance3D).material_override)
		if c is Light3D:
			out["lights"] = int(out["lights"]) + 1
		for ch in c.get_children():
			stack.append(ch)
	out["materials"] = mats.size()
	return out

func _note_mat_map(m: Dictionary, mat: Material) -> void:
	if mat != null:
		m[mat.get_instance_id()] = true

func _mesh_vertex_count(n: Node) -> int:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mesh: Mesh = (n as MeshInstance3D).mesh
		var total: int = 0
		for s in range(mesh.get_surface_count()):
			var arr := mesh.surface_get_arrays(s)
			if arr.size() > Mesh.ARRAY_VERTEX and arr[Mesh.ARRAY_VERTEX] != null:
				total += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		return total
	return -1

func _mesh_triangle_count(n: Node) -> int:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mesh: Mesh = (n as MeshInstance3D).mesh
		var total: int = 0
		for s in range(mesh.get_surface_count()):
			var arr := mesh.surface_get_arrays(s)
			if arr.size() <= Mesh.ARRAY_VERTEX or arr[Mesh.ARRAY_VERTEX] == null:
				continue
			var ic: int = 0
			if arr.size() > Mesh.ARRAY_INDEX and arr[Mesh.ARRAY_INDEX] != null:
				ic = (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
			total += (ic / 3 if ic > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3)
		return total
	return -1

func _find_node(n: Node, target: String) -> Node:
	if n.name == target:
		return n
	for c in n.get_children():
		var r := _find_node(c, target)
		if r != null:
			return r
	return null
