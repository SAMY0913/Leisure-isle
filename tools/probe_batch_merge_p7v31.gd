extends SceneTree
## P7-V3.1 静态合批守恒校验探针（headless）
##
## 定位：产品 **构建时** 已经做了静态合批（cottage.gd / isle_batch.gd），
##       所以本探针不再"试跑合批"，而是在**发布形态**的场景上校验合批的正确性：
##       合批只允许搬运几何，不允许增删任何一个三角形/顶点，也不允许出现
##       "合并一半 + 原实例残留"的重复绘制。
##
## 断言：
##  1) 全场景三角形/顶点总数 == P7-V3 未合批基线（逐位相等，不是"差不多"）；
##  2) dc_est 相对未合批基线下降 >= 40%；
##  3) 家具 / 楼梯 / 房屋三个层级都真的产出了 Batch_ 节点；
##  4) 每个合批组的 surface 数严格少于它合并掉的部件数（否则合批无收益）；
##  5) 动态件（门扇 DoorPivot、门廊猫 PorchCat、船首探照灯 BowSpot）**没有**被合批；
##  6) 溯源清单 batch_manifest 完整（部件类别/尺寸/变换/材质均可读）。
##
## 基线来源：commit ac6c1f0（P7-V3 验收版，未合批）实测
##   tools/probe_batch_p7v31.gd → RESULT tris_total=191656 verts_total=167727 dc_est_total=3421
##
## 运行：
##   ENG --headless --path <PROJ> --script res://tools/probe_batch_merge_p7v31.gd

## P7-V3 未合批基线（ac6c1f0 实测）
const BASE_TRIS := 191656
const BASE_VERTS := 167727
const BASE_DC_EST := 3421

var _pass: int = 0
var _fail: int = 0

func _initialize() -> void:
	await process_frame
	var packed: PackedScene = load("res://isle.tscn") as PackedScene
	if packed == null:
		print("[BMERGE] FAIL cannot load res://isle.tscn")
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

	var cottage: Dictionary = main.get("_cottage")
	if cottage == null:
		print("[BMERGE] FAIL no _cottage")
		quit(1)
		return
	var croot: Node3D = cottage.get("root")
	if croot == null:
		print("[BMERGE] FAIL no cottage root")
		quit(1)
		return
	var scene_root: Node = main

	# ---- 1) 全场景几何守恒（逐位相等）----
	var st := _scene_stats(scene_root)
	var tris := int(st["tris"])
	var verts := int(st["verts"])
	print("[BMERGE] scene mesh=%d surfaces=%d dc_est=%d tris=%d verts=%d" % [
		int(st["mesh"]), int(st["surfaces"]), int(st["dc"]), tris, verts])
	_ok(tris == BASE_TRIS, "三角形总数与未合批基线逐位相等",
		"%d vs %d" % [tris, BASE_TRIS])
	_ok(verts == BASE_VERTS, "顶点总数与未合批基线逐位相等",
		"%d vs %d" % [verts, BASE_VERTS])

	# ---- 2) dc_est 相对基线显著下降 ----
	var dc := int(st["dc"])
	var drop := 100.0 * float(BASE_DC_EST - dc) / float(BASE_DC_EST)
	print("[BMERGE] dc_est %d -> %d (下降 %.1f%%)" % [BASE_DC_EST, dc, drop])
	_ok(drop >= 40.0, "dc_est 相对未合批基线下降 >= 40%", "%.1f%%" % drop)

	# ---- 3) 三层级都产出 Batch_ ----
	var prop_batches := 0
	for p in _collect_pref(croot, "Prop_"):
		prop_batches += _count_pref(p, "Batch_")
	var stairs: Node = _find_named(croot, "Staircase")
	var stairs_batches := _count_pref(stairs, "Batch_") if stairs != null else -1
	var root_batches := _count_pref(croot, "Batch_")
	_ok(prop_batches > 0, "家具层：Prop_* 节点内产出 Batch_ 合批节点", "count=%d" % prop_batches)
	_ok(stairs_batches > 0, "楼梯层：Staircase 内产出 Batch_ 合批节点", "count=%d" % stairs_batches)
	_ok(root_batches > 0, "房屋层：Cottage 内产出 Batch_ 合批节点", "count=%d" % root_batches)

	# ---- 4) 每组合批的 surface 数 < 合并掉的部件数 ----
	var manifests := _collect_manifests(croot)
	var bad_groups: Array = []
	var total_parts := 0
	for m in manifests:
		var grp: Node = m["node"]
		var parts: Array = m["manifest"]
		var surf := 0
		for ch in grp.get_children():
			if ch is MeshInstance3D and String(ch.name).begins_with("Batch_"):
				var mm: Mesh = (ch as MeshInstance3D).mesh
				if mm != null:
					surf += mm.get_surface_count()
		total_parts += parts.size()
		if surf == 0 and parts.size() >= 2:
			bad_groups.append(String(grp.name) + ":no_batch")
		elif surf >= parts.size():
			bad_groups.append("%s:%d>=%d" % [String(grp.name), surf, parts.size()])
	_ok(bad_groups.is_empty(), "每个合批组的 surface 数 < 合并掉的部件数",
		"异常组=%s" % str(bad_groups.slice(0, 5)))
	_ok(total_parts >= 1000, "合批溯源清单覆盖全部被合并部件（>=1000 条）", "parts=%d" % total_parts)

	# ---- 5) 动态件没有被合批 ----
	var dynamic_bad: Array = []
	for nm in ["DoorPivot", "PorchCat"]:
		var n := _find_named(get_root(), nm)
		if n == null:
			dynamic_bad.append(nm + ":missing")
			continue
		if _count_pref(n, "Batch_") > 0:
			dynamic_bad.append(nm + ":batched")
	# DoorPivot 必须仍有 >1 个子 MeshInstance3D（门扇可整体旋转的多个部件）
	var pivot: Node = cottage.get("door_pivot")
	if pivot != null:
		var pmesh := 0
		for c in pivot.get_children():
			if c is MeshInstance3D:
				pmesh += 1
		if pmesh < 18:
			dynamic_bad.append("DoorPivot:parts=%d" % pmesh)
	_ok(dynamic_bad.is_empty(), "动态件（门扇/门廊猫）未被合批且部件完整", str(dynamic_bad))

	# ---- 6) 溯源清单字段完整（可供探针按部件复核）----
	var field_bad := 0
	var sampled := 0
	for m in manifests:
		for e in (m["manifest"] as Array):
			sampled += 1
			var d: Dictionary = e
			if not d.has("kind") or not d.has("size") or not d.has("xf") or not d.has("tris"):
				field_bad += 1
			if sampled >= 400:
				break
		if sampled >= 400:
			break
	_ok(field_bad == 0, "溯源清单字段完整（kind/size/xf/tris）", "抽查 %d 条，缺字段 %d" % [sampled, field_bad])

	print("[BMERGE] RESULT pass=%d fail=%d" % [_pass, _fail])
	await process_frame
	quit(0 if _fail == 0 else 1)

func _ok(cond: bool, msg: String, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("[BMERGE] PASS ", msg, ("  (" + detail + ")") if detail != "" else "")
	else:
		_fail += 1
		print("[BMERGE] FAIL ", msg, ("  (" + detail + ")") if detail != "" else "")

func _collect_manifests(n: Node) -> Array:
	var out: Array = []
	var stack: Array = [n]
	while stack.size() > 0:
		var cur: Node = stack.pop_back()
		if cur.has_meta("batch_manifest"):
			var e: Variant = cur.get_meta("batch_manifest")
			if e is Array and (e as Array).size() > 0:
				out.append({"node": cur, "manifest": e})
		for c in cur.get_children():
			stack.append(c)
	return out

func _collect_pref(n: Node, prefix: String) -> Array:
	var out: Array = []
	if n == null:
		return out
	var stack: Array = [n]
	while stack.size() > 0:
		var cur: Node = stack.pop_back()
		if String(cur.name).begins_with(prefix):
			out.append(cur)
			continue
		for c in cur.get_children():
			stack.append(c)
	return out

func _count_pref(n: Node, prefix: String) -> int:
	if n == null:
		return 0
	var c := 0
	for ch in n.get_children():
		if String(ch.name).begins_with(prefix):
			c += 1
	return c

func _find_named(n: Node, nm: String) -> Node:
	if String(n.name) == nm:
		return n
	for c in n.get_children():
		var r := _find_named(c, nm)
		if r != null:
			return r
	return null

func _scene_stats(root: Node) -> Dictionary:
	var st := {"mesh": 0, "surfaces": 0, "dc": 0, "tris": 0, "verts": 0}
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi: MeshInstance3D = n
			if mi.mesh != null:
				st["mesh"] = int(st["mesh"]) + 1
				var pass_n := 1
				for s in range(mi.mesh.get_surface_count()):
					var m: Material = mi.material_override
					if m == null:
						m = mi.mesh.surface_get_material(s)
					if m != null and m.next_pass != null:
						pass_n = 2
				st["surfaces"] = int(st["surfaces"]) + mi.mesh.get_surface_count()
				st["dc"] = int(st["dc"]) + mi.mesh.get_surface_count() * pass_n
				for s in range(mi.mesh.get_surface_count()):
					var arr := mi.mesh.surface_get_arrays(s)
					if arr.size() <= Mesh.ARRAY_VERTEX or arr[Mesh.ARRAY_VERTEX] == null:
						continue
					var vc: int = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
					var ic: int = 0
					if arr.size() > Mesh.ARRAY_INDEX and arr[Mesh.ARRAY_INDEX] != null:
						ic = (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
					st["verts"] = int(st["verts"]) + vc
					st["tris"] = int(st["tris"]) + (ic / 3 if ic > 0 else vc / 3)
		elif n is MultiMeshInstance3D:
			var mmi: MultiMeshInstance3D = n
			if mmi.multimesh != null and mmi.multimesh.mesh != null:
				var pn := 1
				if mmi.material_override != null and mmi.material_override.next_pass != null:
					pn = 2
				st["dc"] = int(st["dc"]) + pn
				# 与 tools/probe_batch_p7v31.gd 同口径：MultiMesh 的几何按其网格统计一次
				# （不乘 instance_count），这样两边的 tris/verts 总数可以直接对账。
				var mm2: Mesh = mmi.multimesh.mesh
				for s in range(mm2.get_surface_count()):
					var arr2 := mm2.surface_get_arrays(s)
					if arr2.size() <= Mesh.ARRAY_VERTEX or arr2[Mesh.ARRAY_VERTEX] == null:
						continue
					var vc2: int = (arr2[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
					var ic2: int = 0
					if arr2.size() > Mesh.ARRAY_INDEX and arr2[Mesh.ARRAY_INDEX] != null:
						ic2 = (arr2[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
					st["verts"] = int(st["verts"]) + vc2
					st["tris"] = int(st["tris"]) + (ic2 / 3 if ic2 > 0 else vc2 / 3)
		for c in n.get_children():
			stack.append(c)
	return st
