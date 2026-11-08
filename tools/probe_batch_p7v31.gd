extends SceneTree
## P7-V3.1 Draw Call 归因探针（headless，确定性快照）
##
## 用途：把场景里的渲染提交量按"归属区段"聚合，定位 P7-V3 新增开销的实际来源，
##       并在合批优化前后量化每组的 mesh 实例数 / surface 数 / 估算 draw call / 三角形数。
##
## 估算口径（与 Godot Forward+ 实测对齐）：
##   * 每个 MeshInstance3D 的每个 surface 提交一次 draw call；
##   * 材质带 next_pass（toon 描边）时该 surface 再提交一次 → ×2；
##   * MultiMeshInstance3D 整组只提交一次（× pass）；
##   * GPUParticles3D / Label / Light3D 不在此统计（不产生 mesh 提交）。
##   * 本探针是"提交量估算"，不是 RENDER_TOTAL_DRAW_CALLS_IN_FRAME 的替代；
##     实测以 --perf 的 draw_calls 为准，本表只做归因与前后对照。
##
## 运行：
##   "D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe" --headless --path <PROJ> --script res://tools/probe_batch_p7v31.gd
## 输出：[BATCH] 行（按 draw call 估算降序）+ 末行 [BATCH] RESULT groups=N ...

## 归属区段判定：从节点向上找最近的"区段锚点"，找不到就用场景根下的一级分组名。
const SECTION_ANCHORS := [
	"PorchCat", "Sailboat", "Staircase", "AtticInterior", "DoorPivot",
	"Chimney", "RoofCap", "FrontGable", "Cottage",
]

var _groups: Dictionary = {}

func _initialize() -> void:
	await process_frame
	var packed: PackedScene = load("res://isle.tscn") as PackedScene
	if packed == null:
		print("[BATCH] FAIL cannot load res://isle.tscn")
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
	if main.has_method("_set_time_of_day"):
		main.call("_set_time_of_day", 740.0)
	if main.has_method("_update_lighting"):
		main.call("_update_lighting")
	await process_frame
	await process_frame

	_walk(main, "")

	var rows: Array = []
	for k in _groups.keys():
		var g: Dictionary = _groups[k]
		rows.append({
			"name": String(k), "mesh": int(g["mesh"]), "mmesh": int(g["mmesh"]),
			"surfaces": int(g["surfaces"]), "dc": int(g["dc"]),
			"tris": int(g["tris"]), "verts": int(g["verts"]),
			"mats": (g["mats"] as Dictionary).size(),
		})
	rows.sort_custom(func(a, b): return int(a["dc"]) > int(b["dc"]))
	var total_mesh := 0
	var total_surf := 0
	var total_dc := 0
	var total_tris := 0
	var total_verts := 0
	for r in rows:
		print("[BATCH] %-30s mesh=%-5d mmesh=%-3d surfaces=%-5d dc_est=%-5d tris=%-7d verts=%-7d mats=%d" % [
			String(r["name"]), int(r["mesh"]), int(r["mmesh"]), int(r["surfaces"]),
			int(r["dc"]), int(r["tris"]), int(r["verts"]), int(r["mats"]),
		])
		total_mesh += int(r["mesh"])
		total_surf += int(r["surfaces"])
		total_dc += int(r["dc"])
		total_tris += int(r["tris"])
		total_verts += int(r["verts"])
	print("[BATCH] RESULT groups=%d mesh_total=%d surfaces_total=%d dc_est_total=%d tris_total=%d verts_total=%d" % [
		rows.size(), total_mesh, total_surf, total_dc, total_tris, total_verts,
	])
	await process_frame
	quit(0)

func _walk(n: Node, sec: String) -> void:
	var cur := sec
	var nm := String(n.name)
	if nm.begins_with("Prop_"):
		cur = "prop:" + String(n.get_meta("prop_kind", "?"))
	elif SECTION_ANCHORS.has(nm):
		cur = nm
	elif cur == "" and n != get_root():
		cur = nm
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n
		_note(cur, false, mi.mesh, mi.material_override)
	elif n is MultiMeshInstance3D:
		var mmi: MultiMeshInstance3D = n
		var mmesh: Mesh = mmi.multimesh.mesh if mmi.multimesh != null else null
		_note(cur, true, mmesh, mmi.material_override)
	for c in n.get_children():
		_walk(c, cur)

func _group(key: String) -> Dictionary:
	var k := key if key != "" else "root"
	if not _groups.has(k):
		_groups[k] = {"mesh": 0, "mmesh": 0, "surfaces": 0, "dc": 0, "tris": 0, "verts": 0, "mats": {}}
	return _groups[k]

func _note(key: String, is_multimesh: bool, mesh: Mesh, mat: Material) -> void:
	if mesh == null:
		return
	var g := _group(key)
	var surf_n: int = mesh.get_surface_count()
	var pass_n: int = 1
	var mats: Dictionary = g["mats"]
	for s in range(surf_n):
		var sm: Material = mesh.surface_get_material(s)
		if sm != null:
			mats[sm.get_instance_id()] = true
			if sm.next_pass != null:
				pass_n = 2
	if mat != null:
		mats[mat.get_instance_id()] = true
		if mat.next_pass != null:
			pass_n = 2
	if is_multimesh:
		g["mmesh"] = int(g["mmesh"]) + 1
		g["dc"] = int(g["dc"]) + pass_n
	else:
		g["mesh"] = int(g["mesh"]) + 1
		g["dc"] = int(g["dc"]) + surf_n * pass_n
	g["surfaces"] = int(g["surfaces"]) + surf_n
	for s in range(surf_n):
		var arr := mesh.surface_get_arrays(s)
		if arr.size() <= Mesh.ARRAY_VERTEX or arr[Mesh.ARRAY_VERTEX] == null:
			continue
		var vc: int = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		g["verts"] = int(g["verts"]) + vc
		var ic: int = 0
		if arr.size() > Mesh.ARRAY_INDEX and arr[Mesh.ARRAY_INDEX] != null:
			ic = (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
		g["tris"] = int(g["tris"]) + (ic / 3 if ic > 0 else vc / 3)
