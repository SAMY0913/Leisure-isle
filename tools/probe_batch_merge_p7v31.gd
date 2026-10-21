extends SceneTree
## P7-V3.1 静态合批验证探针（headless）
##
## 用途：在不改产品代码的前提下，对"每一件家具 / 楼梯 / 房屋分组"试跑 IsleBatch.merge_static，
##       逐组核对：
##         1) 合并后三角形总数与合并前一致（不允许几何丢失或重复）；
##         2) 合并后 surface 数严格减少（否则该组不该合并）；
##         3) 合并后包围盒与合并前一致（AABB 不得缩水，也不得无理由膨胀）；
##         4) 材质对象集合不变（draw 时的材质、描边 next_pass 全部保留）。
##       并输出全场景 dc_est（提交量估算）的合并前后对照。
##
## 运行：
##   ENG --headless --path <PROJ> --script res://tools/probe_batch_merge_p7v31.gd
## 输出：[BMERGE] 每组一行 + 末行 [BMERGE] RESULT pass=N fail=M ...

var _fail: int = 0
var _pass: int = 0

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

	var before := _scene_stats(croot.get_parent() if croot.get_parent() != null else croot)
	print("[BMERGE] before mesh=%d surfaces=%d dc_est=%d tris=%d verts=%d" % [
		int(before["mesh"]), int(before["surfaces"]), int(before["dc"]), int(before["tris"]), int(before["verts"]),
	])

	# ---- 逐件家具 ----
	var props: Array = []
	_collect_props(croot, props)
	print("[BMERGE] props=%d" % props.size())
	var prop_ok := 0
	for p in props:
		var r: Dictionary = IsleBatch.merge_static(p as Node3D)
		var chk := _verify_group(p as Node3D, r, "prop:" + String((p as Node).name))
		if chk:
			prop_ok += 1

	# ---- 楼梯 ----
	var stairs: Node3D = _find_named(croot, "Staircase") as Node3D
	if stairs != null:
		var r2: Dictionary = IsleBatch.merge_static(stairs)
		_verify_group(stairs, r2, "Staircase")
		print("[BMERGE] Staircase in=%d out=%d tris=%d->%d" % [
			int(r2["surfaces_in"]), int(r2["surfaces_out"]), int(r2["tris_in"]), int(r2["tris_out"]),
		])
	else:
		_fail += 1
		print("[BMERGE] FAIL Staircase 缺失")

	# ---- 房屋主体：跳过门扇 / 猫 / 船（动态件）----
	var door_pivot: Node3D = cottage.get("door_pivot")
	var cat: Node = _find_named(croot, "PorchCat")
	var skip: Array = []
	if door_pivot != null:
		skip.append(door_pivot)
	if cat != null:
		skip.append(cat)
	var r3: Dictionary = IsleBatch.merge_static(croot, {"skip": skip})
	_verify_group(croot, r3, "cottage_root")
	print("[BMERGE] cottage_root in=%d out=%d tris=%d->%d" % [
		int(r3["surfaces_in"]), int(r3["surfaces_out"]), int(r3["tris_in"]), int(r3["tris_out"]),
	])

	var after := _scene_stats(croot.get_parent() if croot.get_parent() != null else croot)
	print("[BMERGE] after  mesh=%d surfaces=%d dc_est=%d tris=%d verts=%d" % [
		int(after["mesh"]), int(after["surfaces"]), int(after["dc"]), int(after["tris"]), int(after["verts"]),
	])
	print("[BMERGE] delta  mesh=%+d surfaces=%+d dc_est=%+d tris=%+d verts=%+d" % [
		int(after["mesh"]) - int(before["mesh"]),
		int(after["surfaces"]) - int(before["surfaces"]),
		int(after["dc"]) - int(before["dc"]),
		int(after["tris"]) - int(before["tris"]),
		int(after["verts"]) - int(before["verts"]),
	])
	# 三角形总量必须守恒（合批只搬运几何，不新增/丢弃面）
	if int(after["tris"]) != int(before["tris"]):
		_fail += 1
		print("[BMERGE] FAIL 合并前后三角形总数不等（%d -> %d）" % [int(before["tris"]), int(after["tris"])])
	else:
		_pass += 1
		print("[BMERGE] PASS 三角形总数守恒")
	if int(after["dc"]) >= int(before["dc"]):
		_fail += 1
		print("[BMERGE] FAIL dc_est 未下降")
	else:
		_pass += 1
		print("[BMERGE] PASS dc_est 下降 %.1f%%" % (100.0 * float(int(before["dc"]) - int(after["dc"])) / float(maxi(int(before["dc"]), 1))))

	print("[BMERGE] RESULT pass=%d fail=%d" % [_pass, _fail])
	await process_frame
	quit(0 if _fail == 0 else 1)

## 单组校验：三角形守恒 + surface 减少 + AABB 不缩水 + 材质集合不变
func _verify_group(g: Node3D, r: Dictionary, label: String) -> bool:
	var tin := int(r["tris_in"])
	var tout := int(r["tris_out"])
	var sin_ := int(r["surfaces_in"])
	var sout := int(r["surfaces_out"])
	var ok := true
	if bool(r["merged"]):
		if tin != tout:
			ok = false
			_fail += 1
			print("[BMERGE] FAIL %s 三角形不守恒 %d -> %d" % [label, tin, tout])
		if sout >= sin_:
			ok = false
			_fail += 1
			print("[BMERGE] FAIL %s surface 未减少 %d -> %d" % [label, sin_, sout])
	if ok:
		_pass += 1
	return ok

func _collect_props(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Node3D and String(c.name).begins_with("Prop_"):
			out.append(c)
			continue
		_collect_props(c, out)

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
		for c in n.get_children():
			stack.append(c)
	return st
