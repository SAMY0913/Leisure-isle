extends SceneTree
## P7-V3.2 T2 房屋专项探针（headless）：外壳 / 门洞 / 窗 / 屋顶 / 楼梯 / 阁楼 / 家具布局 / 契约。
## 断言尽量从 IsleMath.HOUSE_* 与 IsleScaleSpec 推导（不硬编码旧数）。
## 运行：console --headless --path <proj> --script res://tools/probe_scale_house_p7v32.gd
## 日志：D:/休闲小岛幻境/开发产物/p7v32/logs/t2_probe_scale_house.log

const M := preload("res://scripts/isle_math.gd")
const TAG := "[T2-HOUSE]"
const ROOF_PANEL_T := 0.14

var _ok_n := 0
var _fail := 0
var _warn := 0
var _fails: Array = []
var _warns: Array = []
var _root: Node3D
var _d: Dictionary
var _C: Dictionary
var _boxes: Array = []          # root 合批清单盒（root 局部 AABB）
var _props: Array = []          # 家具 {node,kind,floor,mounted,aabb}
var _mats: Array = []           # 全部 MeshInstance3D 的 root 局部 AABB（用于整体包络/最高点）

var _run_pending := false

func _initialize() -> void:
	_run_pending = true

func _process(_delta: float) -> bool:
	if not _run_pending:
		return true
	_run_pending = false
	_run_all()
	return false

func _run_all() -> void:
	var holder := Node3D.new()
	holder.name = "T2ProbeHolder"
	get_root().add_child(holder)
	_d = IsleCottage.build(holder)
	_root = _d["root"] as Node3D
	_C = _root.get_meta("cottage_ctx", {})
	if _C.is_empty():
		print(TAG, " FATAL root 缺少 cottage_ctx meta")
		quit(1)
		return
	_walk_boxes(_root, Transform3D.IDENTITY)
	_walk_mats(_root, "Cottage")
	var ia := _root.get_node_or_null("AtticInterior")
	_walk_props(_root, "ground")
	if ia != null:
		_walk_props(ia, "attic")

	if OS.get_environment("T2_CANOPY") == "1":
		_dump_canopy()
		quit(0)
		return

	if OS.get_environment("T2_RAY") != "":
		_dump_ray()
		quit(0)
		return

	_check_house_dims()
	_check_shell()
	_check_front_wall_door()
	_check_windows()
	_check_door_parts()
	_check_roof()
	_check_chimney()
	_check_porch()
	_check_stairs()
	_check_attic_interior()
	_check_furniture_dims()
	_check_furniture_overlap()
	_check_layout_zones()
	_check_attic_clearance()
	_check_corridor()
	_check_contract()
	_check_scales()
	_print_tables()

	print(TAG, " RESULT checks=%d pass=%d warn=%d fail=%d" % [_ok_n + _fail, _ok_n, _warn, _fail])
	for s in _fails:
		print(TAG, "   FAIL ", s)
	for s in _warns:
		print(TAG, "   WARN ", s)
	if _fail == 0:
		print(TAG, " RESULT_OK 房屋尺度/几何/布局校验通过")
		holder.free()
		quit(0)
	else:
		print(TAG, " RESULT_FAIL 存在 %d 条失败" % _fail)
		holder.free()
		quit(1)

# ============================================================
# 工具
# ============================================================
func _ok(cond: bool, id: String, detail: String, warn_only: bool = false) -> void:
	if cond:
		_ok_n += 1
		print(TAG, " OK   ", id, " | ", detail)
	elif warn_only:
		_warn += 1
		_warns.append(id + " | " + detail)
		print(TAG, " WARN ", id, " | ", detail)
	else:
		_fail += 1
		_fails.append(id + " | " + detail)
		print(TAG, " FAIL ", id, " | ", detail)

func _near(id: String, actual: float, want: float, tol: float) -> void:
	_ok(absf(actual - want) <= tol, id, "actual=%.4f want=%.4f tol=%.4f" % [actual, want, tol])

func _vec_near(id: String, actual: Vector3, want: Vector3, tol: float) -> void:
	var e: Vector3 = (actual - want).abs()
	_ok(e.x <= tol and e.y <= tol and e.z <= tol, id, "actual=(%.4f,%.4f,%.4f) want=(%.4f,%.4f,%.4f)" % [actual.x, actual.y, actual.z, want.x, want.y, want.z])

func _entry_aabb(kind: String, size: Vector3, xf: Transform3D) -> AABB:
	var half := Vector3(0.001, 0.001, 0.001)
	match kind:
		"Box":
			half = size * 0.5
		"Cyl":
			half = Vector3(maxf(size.x, size.z), size.y * 0.5, maxf(size.x, size.z))
		"Sphere":
			half = Vector3(size.x, size.y * 0.5, size.x)
		"Quad":
			half = Vector3(size.x * 0.5, size.y * 0.5, 0.001)
		"Prism":
			half = size * 0.5
	var mn := Vector3(1e9, 1e9, 1e9)
	var mx := Vector3(-1e9, -1e9, -1e9)
	for i in range(8):
		var p := Vector3(
			half.x if (i & 1) != 0 else -half.x,
			half.y if (i & 2) != 0 else -half.y,
			half.z if (i & 4) != 0 else -half.z)
		var w: Vector3 = xf * p
		mn = Vector3(minf(mn.x, w.x), minf(mn.y, w.y), minf(mn.z, w.z))
		mx = Vector3(maxf(mx.x, w.x), maxf(mx.y, w.y), maxf(mx.z, w.z))
	return AABB(mn, mx - mn)

func _union_aabb(a: AABB, b: AABB) -> AABB:
	var mn := Vector3(minf(a.position.x, b.position.x), minf(a.position.y, b.position.y), minf(a.position.z, b.position.z))
	var mx := Vector3(maxf(a.end.x, b.end.x), maxf(a.end.y, b.end.y), maxf(a.end.z, b.end.z))
	return AABB(mn, mx - mn)

func _node_aabb(node: Node3D, xf_base: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	for c in node.get_children():
		if c is Node3D:
			var a := _node_aabb(c, xf_base * (c as Node3D).transform)
			if a.size != Vector3.ZERO:
				out = a if first else _union_aabb(out, a)
				first = false
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mi := node as MeshInstance3D
		var a2 := _entry_aabb("Other", Vector3.ZERO, Transform3D.IDENTITY)
		a2 = _mesh_aabb(mi.mesh, xf_base)
		out = a2 if first else _union_aabb(out, a2)
		first = false
	return out if not first else AABB(Vector3.ZERO, Vector3.ZERO)

func _mesh_aabb(mesh: Mesh, xf: Transform3D) -> AABB:
	var bb: AABB = mesh.get_aabb()
	var mn := Vector3(1e9, 1e9, 1e9)
	var mx := Vector3(-1e9, -1e9, -1e9)
	for i in range(8):
		var p := bb.position + Vector3(
			bb.size.x if (i & 1) != 0 else 0.0,
			bb.size.y if (i & 2) != 0 else 0.0,
			bb.size.z if (i & 4) != 0 else 0.0)
		var w: Vector3 = xf * p
		mn = Vector3(minf(mn.x, w.x), minf(mn.y, w.y), minf(mn.z, w.z))
		mx = Vector3(maxf(mx.x, w.x), maxf(mx.y, w.y), maxf(mx.z, w.z))
	return AABB(mn, mx - mn)

func _walk_boxes(group: Node, xf_base: Transform3D) -> void:
	if group.has_meta("batch_manifest"):
		var manifest: Array = group.get_meta("batch_manifest")
		for e in manifest:
			var xf_g: Transform3D = e["xf_group"]
			var xf: Transform3D = xf_base * xf_g
			var aabb := _entry_aabb(String(e["kind"]), e["size"], xf)
			_boxes.append({
				"name": String(e["name"]), "parent": String(e["parent"]),
				"kind": String(e["kind"]), "size": e["size"], "xf": xf, "aabb": aabb,
			})
	# 仅 root/Staircase 等顶层 group 调用：家具各自单独收集，不在这里递归

func _walk_mats(node: Node, path: String) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var a := _mesh_aabb(mi.mesh, _rel_xf_to_root(mi))
			_mats.append({"path": path, "node": mi, "aabb": a})
	elif node is MultiMeshInstance3D:
		var mmi := node as MultiMeshInstance3D
		if mmi.multimesh != null and mmi.multimesh.mesh != null:
			var xf := _rel_xf_to_root(mmi)
			for i in range(mmi.multimesh.instance_count):
				var a2 := _mesh_aabb(mmi.multimesh.mesh, xf * mmi.multimesh.get_instance_transform(i))
				_mats.append({"path": path, "node": mmi, "aabb": a2})
	for c in node.get_children():
		_walk_mats(c, path + "/" + String(c.name))

func _rel_xf_to_root(n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != _root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf

func _walk_props(parent: Node, floor_name: String) -> void:
	for c in parent.get_children():
		if not (c is Node3D):
			continue
		var n := c as Node3D
		if not n.has_meta("prop_kind"):
			continue
		var kind := String(n.get_meta("prop_kind"))
		var mounted := bool(n.get_meta("prop_wall_mounted", false))
		var aabb := AABB()
		var first := true
		if n.has_meta("batch_manifest"):
			for e in n.get_meta("batch_manifest"):
				var xfg: Transform3D = e["xf_group"]
				var pa := _entry_aabb(String(e["kind"]), e["size"], n.transform * xfg)
				aabb = pa if first else _union_aabb(aabb, pa)
				first = false
		# 单件未合批、随后被 root 合并收走的部件：root 清单里 parent=Prop 名
		for b in _boxes:
			if String(b["parent"]) == String(n.name):
				var ba: AABB = b["aabb"]
				aabb = ba if first else _union_aabb(aabb, ba)
				first = false
		_props.append({"node": n, "kind": kind, "floor": floor_name, "mounted": mounted, "aabb": aabb})

func _aabb_key(d: Dictionary, k: String) -> AABB:
	return d[k]

func _vec_key(d: Dictionary, k: String) -> Vector3:
	return d[k]

func _count_mats() -> int:
	return _mats.size()

# ============================================================
# 1) 房屋总体尺寸
# ============================================================
func _check_house_dims() -> void:
	var C := _C
	_near("SHELL.w", float(C["w"]), IsleMath.HOUSE_W, 0.001)
	_near("SHELL.d", float(C["d"]), IsleMath.HOUSE_D, 0.001)
	_near("SHELL.wall_h", float(C["wh"]), IsleMath.HOUSE_WALL_H, 0.001)
	_near("SHELL.roof_h", float(C["rh"]), IsleMath.HOUSE_ROOF_H, 0.001)
	_near("SHELL.roof_base", float(C["roof_base"]), IsleMath.HOUSE_FY + IsleMath.HOUSE_WALL_H, 0.001)
	_near("SHELL.ridge_y", float(C["ridge_y"]), IsleMath.HOUSE_RIDGE_Y, 0.001)
	_near("SHELL.fy", float(C["fy"]), IsleMath.HOUSE_FY, 0.001)
	_near("SHELL.wall_t", float(C["wall_t"]), IsleMath.HOUSE_WALL_T, 0.001)
	_near("SHELL.room_clear_h", float(C["in_top"]) - float(C["fy"]), IsleScaleSpec.ROOM_CLEAR_H, 0.001)
	_near("SHELL.attic_floor", float(C["attic_floor"]), IsleMath.HOUSE_ATTIC_FLOOR_Y, 0.001)
	_near("SHELL.attic_slab_t", float(C["attic_slab_t"]), IsleScaleSpec.SLAB_T, 0.001)
	_near("SHELL.attic_knee", float(C["attic_knee"]), IsleScaleSpec.ATTIC_KNEE_H, 0.001)
	var pitch_deg: float = rad_to_deg(atan(float(C["rh"]) / float(C["hw"])))
	_near("SHELL.pitch_deg", pitch_deg, IsleScaleSpec.HOUSE_PITCH_DEG, 0.6)
	var straight: float = sqrt(float(C["hw"]) * float(C["hw"]) + float(C["rh"]) * float(C["rh"]))
	_near("SHELL.eave_ov", float(C["slope_len"]) - straight, IsleScaleSpec.HOUSE_EAVE_OV, 0.01)
	_near("SHELL.roof_z", float(C["roof_z"]), float(C["d"]) + 2.0 * IsleScaleSpec.HOUSE_EAVE_OV, 0.02)
	# root 变换
	_near("ROOT.pos.x", _root.position.x, IsleMath.HOUSE_X, 0.001)
	_near("ROOT.pos.z", _root.position.z, IsleMath.HOUSE_Z, 0.001)
	_near("ROOT.pos.y", _root.position.y, IsleMath.house_ground_y(), 0.001)
	_near("ROOT.yaw", _root.rotation.y, IsleMath.HOUSE_YAW, 0.001)
	# 外壳结构包络：按部件清单（_boxes）量墙板并集与最高/最低构件（不用 _mats，避免光晕/猫/门廊撑大包络）
	var wt2: float = float(C["wall_t"])
	var zf2: float = float(C["hd"]) - wt2 * 0.5
	var xw2: float = float(C["hw"]) - wt2 * 0.5
	var wall := AABB()
	var first := true
	var geom_top := -1e9
	var geom_bottom := 1e9
	for b in _boxes:
		var a: AABB = b["aabb"]
		var s: Vector3 = b["size"]
		var pn := String(b["parent"])
		if String(b["name"]).begins_with("Prop_") or pn.begins_with("Prop_") or pn.begins_with("PorchCat"):
			continue
		geom_top = maxf(geom_top, a.end.y)
		geom_bottom = minf(geom_bottom, a.position.y)
		var c0: Vector3 = a.get_center()
		var on_fb: bool = absf(c0.z - zf2) <= 0.03 or absf(c0.z + zf2) <= 0.03
		var on_side: bool = absf(absf(c0.x) - xw2) <= 0.03
		var is_wall: bool = (String(b["kind"]) == "Box") and ((absf(s.z - wt2) <= 0.02 and on_fb and s.x >= 0.50) or (absf(s.x - wt2) <= 0.02 and on_side and s.z >= 0.50))
		if is_wall:
			wall = a if first else _union_aabb(wall, a)
			first = false
	print(TAG, " INFO wall_aabb size=(%.3f,%.3f,%.3f) geom_top=%.3f geom_bottom=%.3f" % [wall.size.x, wall.size.y, wall.size.z, geom_top, geom_bottom])
	_near("SHELL.wall_x_span", wall.size.x, float(C["w"]), 0.02)
	_near("SHELL.wall_z_span", wall.size.z, float(C["d"]), 0.02)
	_near("SHELL.geometry_top", geom_top, float(C["ch_top"]) + IsleScaleSpec.HOUSE_CHIMNEY_ABOVE_RIDGE, 0.03)
	_ok(geom_bottom > -1.2 and geom_bottom < -0.4, "SHELL.geometry_bottom", "min_y=%.3f (台基底)" % geom_bottom)
	# 层高：阁楼地板顶 = 一层净高 + 楼板
	_near("SHELL.attic_floor_formula", float(C["attic_floor"]) - float(C["fy"]), IsleScaleSpec.ROOM_CLEAR_H + IsleScaleSpec.SLAB_T, 0.001)

# ============================================================
# 2) 外壳构件：台基 / 墙板 / 地板 / 天花 / 半木
# ============================================================
func _check_shell() -> void:
	var C := _C
	var hd: float = C["hd"]
	var fy: float = C["fy"]
	var plinth := _find_box(Vector3(8.6, 1.14, 6.3), 0.02)
	_ok(not plinth.is_empty(), "SHELL.plinth_body", "台基主体 8.60x1.14x6.30")
	var cap := _find_box(Vector3(8.86, 0.16, 6.56), 0.02)
	_ok(not cap.is_empty(), "SHELL.plinth_cap", "压顶石 8.86x0.16x6.56 top=%.3f" % (fy - 0.08 + 0.08))
	var floor_box := _find_box(Vector3(6.98, 0.14, 5.58), 0.02)
	_ok(not floor_box.is_empty(), "SHELL.interior_floor", "一层地板 6.98x0.14x5.58")
	if not floor_box.is_empty():
		_near("SHELL.interior_floor_top", _aabb_key(floor_box, "aabb").end.y, fy, 0.01)
	# 前墙 13 段（z=zf 的 0.30 厚墙板）
	var front: Array = []
	for b in _boxes:
		if String(b["kind"]) != "Box":
			continue
		var s: Vector3 = b["size"]
		var a: AABB = b["aabb"]
		if absf(s.z - float(C["wall_t"])) <= 0.02 and absf(a.get_center().z - float(C["hd"]) + float(C["wall_t"]) * 0.5) <= 0.03:
			front.append(b)
	_ok(front.size() >= 11, "SHELL.front_wall_panels", "前墙 0.30 厚墙板段数=%d (≥11)" % front.size())
	# 侧墙（±hw 处 0.30 厚的 x 向板）
	var side_cnt := 0
	for b in _boxes:
		if String(b["kind"]) != "Box":
			continue
		var s2: Vector3 = b["size"]
		if absf(s2.x - float(C["wall_t"])) <= 0.02 and absf(absf(_aabb_key(b, "aabb").get_center().x) - (float(C["hw"]) - float(C["wall_t"]) * 0.5)) <= 0.02:
			side_cnt += 1
	_ok(side_cnt >= 6, "SHELL.side_wall_panels", "侧墙 0.30 厚板段数=%d" % side_cnt)
	# 半木门窗框：门柱 / 过梁 / 窗下横梁
	var timber := 0
	for b2 in _boxes:
		if String(b2["kind"]) == "Box" and float(_vec_key(b2, "size").z) > 0.10 and float(_vec_key(b2, "size").z) < 0.22 and absf(_aabb_key(b2, "aabb").get_center().z) > hd + 0.05:
			timber += 1
	print(TAG, " INFO half_timber_front_count=%d" % timber)
	# 天花 3 块（L 洞外）
	var ceil_cnt := 0
	for b3 in _boxes:
		if String(b3["kind"]) == "Box" and absf(float(_vec_key(b3, "size").y) - 0.025) <= 0.004:
			ceil_cnt += 1
	_ok(ceil_cnt == 3, "SHELL.ceiling_zones", "一层天花 L 洞外 3 块 (实测 %d)" % ceil_cnt)
	# 石砌勒脚裙（前/后/侧共 4 条）
	var skirt := 0
	for b4 in _boxes:
		if String(b4["kind"]) == "Box" and absf(float(_vec_key(b4, "size").y) - 0.40) <= 0.03 and absf(float(_vec_key(b4, "size").z) - 0.22) <= 0.02:
			skirt += 1
	_ok(skirt >= 2, "SHELL.plinth_skirt", "墙脚石裙段数=%d" % skirt)

func _find_box(want: Vector3, tol: float) -> Dictionary:
	for b in _boxes:
		if String(b["kind"]) != "Box":
			continue
		var s: Vector3 = b["size"]
		if absf(s.x - want.x) <= tol and absf(s.y - want.y) <= tol and absf(s.z - want.z) <= tol:
			return b
	return {}

# ============================================================
# 3) 前墙门洞净尺寸（从合并后的墙板清单实测）
# ============================================================
func _check_front_wall_door() -> void:
	var C := _C
	var fy: float = C["fy"]
	var wall_t: float = C["wall_t"]
	var zf: float = float(C["hd"]) - wall_t * 0.5
	var panels: Array = []
	for b in _boxes:
		if String(b["kind"]) != "Box":
			continue
		var s: Vector3 = b["size"]
		var a: AABB = b["aabb"]
		if absf(s.z - wall_t) <= 0.02 and absf(a.get_center().z - zf) <= 0.03:
			panels.append(a)
	_ok(panels.size() >= 11, "DOOR.wall_panels", "门洞所在前墙板段=%d" % panels.size())
	# 水平净宽（y=fy+0.80，避开拱）
	var y_scan: float = fy + 0.80
	var left := -100.0
	var right := 100.0
	var blocked := false
	for a2 in panels:
		if y_scan >= a2.position.y - 0.001 and y_scan <= a2.end.y + 0.001:
			var x0: float = a2.position.x
			var x1: float = a2.end.x
			if x0 <= 0.0 and x1 >= 0.0:
				blocked = true
			if x1 <= 0.0:
				left = maxf(left, x1)
			if x0 >= 0.0:
				right = minf(right, x0)
	_ok(not blocked, "DOOR.clear_at_0800", "y=fy+0.80 处门洞中心无墙板")
	var clear_w: float = right - left
	_near("DOOR.clear_w_measured", clear_w, IsleScaleSpec.DOOR_CLEAR_W, 0.02)
	# 拱脚处净宽（y=fy+1.42）仍应为 1.14（拱脚立柱内表面）
	var y_spring: float = fy + 1.42
	var l2 := -100.0
	var r2 := 100.0
	for a3 in panels:
		if y_spring >= a3.position.y - 0.001 and y_spring <= a3.end.y + 0.001:
			if a3.end.x <= 0.0:
				l2 = maxf(l2, a3.end.x)
			if a3.position.x >= 0.0:
				r2 = minf(r2, a3.position.x)
	_near("DOOR.clear_w_at_spring", r2 - l2, IsleScaleSpec.DOOR_CLEAR_W, 0.02)
	# 净高（x=0：找门洞上方第一块墙板下沿）
	var h_clear := 100.0
	for a4 in panels:
		if a4.position.x - 0.001 <= 0.0 and a4.end.x + 0.001 >= 0.0:
			if a4.position.y > fy + 1.0:
				h_clear = minf(h_clear, a4.position.y)
	_near("DOOR.clear_h_measured", h_clear - fy, IsleScaleSpec.DOOR_CLEAR_H, 0.02)
	# 拱内通行包络：两侧 1.42 / 中央 1.94
	var dc: Dictionary = _C["door_clear"]
	_near("DOOR.spring_y", float(dc["spring_y"]), fy + 1.42, 0.001)
	_near("DOOR.side_clear", float(dc["spring_y"]) - fy, 1.42, 0.001)
	_near("DOOR.center_clear", float(dc["spring_y"]) + float(dc["arch_ri"]) - fy, IsleScaleSpec.DOOR_CLEAR_H, 0.001)
	_near("DOOR.arch_ri", float(dc["arch_ri"]), 0.52, 0.001)
	_near("DOOR.arch_ro", float(dc["arch_ro"]), 0.66, 0.001)
	_near("DOOR.fanlight_r", float(dc["fanlight_r"]), 0.50, 0.001)
	_near("DOOR.handle_h", float(dc["handle_h"]), IsleScaleSpec.DOOR_HANDLE_H, 0.001)
	_near("DOOR.leaf_w", float(dc["leaf_w"]), 1.00, 0.001)
	_near("DOOR.leaf_h", float(dc["leaf_h"]), 1.40, 0.001)
	var op: Vector3 = _C["door_opening"]
	_near("DOOR.opening_w", op.x, IsleScaleSpec.DOOR_CLEAR_W, 0.001)
	_near("DOOR.opening_h", op.y, IsleScaleSpec.DOOR_CLEAR_H, 0.001)
	_near("DOOR.opening_t", op.z, float(C["wall_t"]), 0.001)
	# DoorPivot 位置 / 轴：合页在左边缘（x=-0.50），main 绕 y 旋转开门
	var pivot: Node3D = _d["door_pivot"]
	_vec_near("DOOR.pivot_local", pivot.position, Vector3(-0.50, fy, float(C["hd"]) - 0.06), 0.001)
	_ok(bool(pivot.get_meta("no_batch", false)), "DOOR.pivot_no_batch", "DoorPivot no_batch 标记")
	_near("DOOR.pivot_closed", pivot.rotation.y, 0.0, 0.001)
	# 门扇：5 竖板 0.20 => 1.00 宽 x 1.40 高
	var plank := 0
	var px_min := 100.0
	var px_max := -100.0
	var py_max := 0.0
	for c in pivot.get_children():
		if not (c is MeshInstance3D):
			continue
		var mi := c as MeshInstance3D
		if not (mi.mesh is BoxMesh):
			continue
		var bs: Vector3 = (mi.mesh as BoxMesh).size
		if absf(bs.x - 0.20) <= 0.002 and absf(bs.y - 1.40) <= 0.002:
			plank += 1
			px_min = minf(px_min, mi.position.x - bs.x * 0.5)
			px_max = maxf(px_max, mi.position.x + bs.x * 0.5)
			py_max = maxf(py_max, mi.position.y + bs.y * 0.5)
	_ok(plank == 5, "DOOR.leaf_planks", "门扇 5 块竖板 (实测 %d)" % plank)
	_near("DOOR.leaf_w_measured", px_max - px_min, 1.00, 0.01)
	_near("DOOR.leaf_h_measured", py_max, 1.40, 0.01)
	# 把手：球 r0.075，中心局部 (0.90, 0.95, 0.11)
	var knob_ok := false
	var knob_detail := "未找到把手球"
	for c2 in pivot.get_children():
		if c2 is MeshInstance3D and (c2 as MeshInstance3D).mesh is SphereMesh:
			var sm := (c2 as MeshInstance3D).mesh as SphereMesh
			var pos: Vector3 = (c2 as MeshInstance3D).position
			knob_detail = "r=%.3f pos=(%.3f,%.3f,%.3f)" % [sm.radius, pos.x, pos.y, pos.z]
			if absf(sm.radius - 0.075) <= 0.002 and absf(pos.x - 0.90) <= 0.01 and absf(pos.y - 0.95) <= 0.01:
				knob_ok = true
	_ok(knob_ok, "DOOR.knob", "金色把手 r0.075 @(0.90,0.95) " + knob_detail)
	# DoorHit 交互体
	var hit: Node = _d["door_hit"]
	_ok(hit != null and String(hit.name) == "DoorHit", "DOOR.hitbox", "DoorHit 节点存在（点击开门用）")

# ============================================================
# 4) 窗：前 2 + 侧 2 + 后 1 + 阁楼 1
# ============================================================
func _check_windows() -> void:
	var C := _C
	var fy: float = C["fy"]
	var zf: float = float(C["hd"]) - float(C["wall_t"]) * 0.5
	var xw: float = float(C["hw"]) - float(C["wall_t"]) * 0.5
	# 窗枢轴节点（合批后窗框盒进 manifest，但枢轴节点保留；玻璃是枢轴子节点仍在树上）
	var expect := {
		"WindowFront_0": {"p": Vector3(-2.30, fy + 1.48, zf), "size": Vector2(1.00, 1.15)},
		"WindowFront_1": {"p": Vector3(2.30, fy + 1.48, zf), "size": Vector2(1.00, 1.15)},
		"WindowSideL": {"p": Vector3(-xw, fy + 1.375, -0.30), "size": Vector2(1.00, 0.95)},
		"WindowSideR": {"p": Vector3(xw, fy + 1.375, -0.30), "size": Vector2(1.00, 0.95)},
		"WindowBack": {"p": Vector3(0.20, 1.90, -zf), "size": Vector2(0.90, 0.90)},
	}
	var found := 0
	for nm in expect.keys():
		var piv := _root.get_node_or_null(String(nm))
		if piv == null or not (piv is Node3D):
			_ok(false, "WIN.missing_" + String(nm), "缺少窗枢轴节点 " + String(nm))
			continue
		found += 1
		var pn := piv as Node3D
		var ed: Dictionary = expect[nm]
		_vec_near("WIN.pivot_" + String(nm), pn.position, ed["p"], 0.02)
		var wv: Vector2 = ed["size"]
		var gs := pn.get_node_or_null("Glass")
		if gs == null or not (gs is MeshInstance3D) or not ((gs as MeshInstance3D).mesh is BoxMesh):
			_ok(false, "WIN.glass_" + String(nm), "窗玻璃节点缺失或非 BoxMesh: " + String(nm))
			continue
		var sk: Vector3 = ((gs as MeshInstance3D).mesh as BoxMesh).size
		_near("WIN.size_" + String(nm), sk.x + 0.02, wv.x, 0.01)
		_near("WIN.height_" + String(nm), sk.y + 0.02, wv.y, 0.01)
		var sill_rel: float = pn.position.y - wv.y * 0.5 - fy
		_near("WIN.sill_" + String(nm), sill_rel, IsleScaleSpec.WINDOW_SILL_H, 0.06)
	_ok(found == 5, "WIN.count", "一层窗枢轴 5 扇 (实测 %d)" % found)
	# 阁楼窗 1.50x1.50，底 = attic_floor + 0.10
	var aw := _root.get_node_or_null("AtticWindow")
	_ok(aw != null, "WIN.attic_node", "AtticWindow 节点存在")
	if aw != null:
		_near("WIN.attic_w", float(aw.get_meta("width")), 1.50, 0.01)
		_near("WIN.attic_h", float(aw.get_meta("height")), 1.50, 0.01)
		var ctr: Vector3 = aw.get_meta("center")
		_near("WIN.attic_bottom", ctr.y - 0.75, float(C["attic_floor"]) + IsleScaleSpec.ATTIC_WINDOW_BOTTOM_ABOVE_FLOOR, 0.02)
		_near("WIN.attic_top", ctr.y + 0.75, float(C["attic_top"]), 0.02)
	# 窗光/光晕契约
	var halos_arr: Array = _d["window_halos"]
	_ok(halos_arr.size() == 5, "WIN.halos", "窗光晕 5 片（每扇一层窗 1 片, 实测 %d）" % halos_arr.size())
	_ok((_d["front_window_world"] as Array).size() == 2, "WIN.front_world_pts", "front_window_world=2")

# ============================================================
# 5) 拱券 / 补墙 / 气窗几何
# ============================================================
func _check_door_parts() -> void:
	var C := _C
	var fy: float = C["fy"]
	var spring: float = fy + 1.42
	var arch := _root.get_node_or_null("DoorArch")
	_ok(arch != null, "ARCH.node", "DoorArch 节点存在")
	if arch != null:
		var a: AABB = _node_aabb(arch as Node3D, Transform3D.IDENTITY)
		_near("ARCH.width", a.size.x, 2.0 * 0.66, 0.03)
		_near("ARCH.height", a.size.y, 0.66, 0.03)
		_near("ARCH.spring", a.position.y, spring, 0.02)
		_near("ARCH.top", a.end.y, fy + 1.94 + 0.12, 0.10)
	var spand := _root.get_node_or_null("DoorSpandrel")
	_ok(spand != null, "SPANDREL.node", "DoorSpandrel 节点存在")
	if spand != null:
		var a2: AABB = _node_aabb(spand as Node3D, Transform3D.IDENTITY)
		_near("SPANDREL.width", a2.size.x, 1.14, 0.03)
		_near("SPANDREL.height", a2.size.y, 0.52, 0.03)
		_near("SPANDREL.bottom", a2.position.y, spring, 0.02)
		_near("SPANDREL.top", a2.end.y, fy + 1.94, 0.02)
	var pivot: Node3D = _d["door_pivot"]
	var fan := pivot.get_node_or_null("DoorFanlight")
	_ok(fan != null, "FANLIGHT.node", "DoorFanlight 节点存在（气窗）")
	if fan != null:
		var a3: AABB = _node_aabb(fan as Node3D, Transform3D.IDENTITY)
		_near("FANLIGHT.width", a3.size.x, 1.00, 0.03)
		_near("FANLIGHT.height", a3.size.y, 0.50, 0.03)
		_near("FANLIGHT.chord_y", a3.position.y, 1.40, 0.02)
		_near("FANLIGHT.world_top", a3.end.y + fy, fy + 1.90, 0.03)

# ============================================================
# 6) 屋顶 / 山墙
# ============================================================
func _check_roof() -> void:
	var C := _C
	var roof_base: float = C["roof_base"]
	var ridge_y: float = C["ridge_y"]
	var pitch: float = C["pitch"]
	# 双坡屋面板（5.13 x 0.14 x 7.4，绕 Z 旋转 ±pitch）
	var slopes: Array = []
	for b in _boxes:
		if String(b["kind"]) != "Box":
			continue
		var s: Vector3 = b["size"]
		if absf(s.y - 0.14) <= 0.005 and absf(s.z - float(C["roof_z"])) <= 0.02 and s.x > 4.5:
			slopes.append(b)
	_ok(slopes.size() == 2, "ROOF.slopes", "双坡屋面板 2 块 (实测 %d)" % slopes.size())
	for b2 in slopes:
		var xf: Transform3D = b2["xf"]
		var slope_pitch: float = absf(asin(clampf(xf.basis.x.y, -1.0, 1.0)))
		_near("ROOF.slope_angle", slope_pitch, pitch, 0.01)
	# 博风板（slope_len+0.06 x 0.24 x 0.10）：结构 AABB 最高点来源 -> 解释 T1 AABB 2.654 口径
	var barge_top := -1e9
	var barge_n := 0
	for b3 in _boxes:
		if String(b3["kind"]) != "Box":
			continue
		var s3: Vector3 = b3["size"]
		if absf(s3.y - 0.24) <= 0.005 and absf(s3.z - 0.10) <= 0.02 and s3.x > 4.8:
			barge_n += 1
			barge_top = maxf(barge_top, _aabb_key(b3, "aabb").end.y)
	_ok(barge_n == 4, "ROOF.barge_boards", "博风板 4 块 (实测 %d)" % barge_n)
	_near("ROOF.barge_top", barge_top - roof_base, IsleMath.HOUSE_ROOF_H + 0.184, 0.05)
	print(TAG, " INFO roof 结构线 roof_h=%.3f (ridge-roof_base) ; 博风板顶=%.3f -> 相对檐口=%.3f ; AABB 口径见简报" % [
		ridge_y - roof_base, barge_top, barge_top - roof_base])
	_near("ROOF.structural_h", ridge_y - roof_base, IsleMath.HOUSE_ROOF_H, 0.001)
	# 脊梁 / 脊瓦 / 筒瓦 / 檐椽 / 封檐板
	var has_ridge_beam := false
	var has_fascia := false
	for b4 in _boxes:
		if String(b4["kind"]) != "Box":
			continue
		var s4: Vector3 = b4["size"]
		if absf(s4.x - 0.34) <= 0.01 and absf(s4.y - 0.26) <= 0.01 and s4.z > 7.0:
			has_ridge_beam = true
		if absf(s4.x - 0.12) <= 0.01 and absf(s4.y - 0.26) <= 0.01 and s4.z > 7.0:
			has_fascia = true
	_ok(has_ridge_beam, "ROOF.ridge_beam", "脊梁 0.34x0.26x7.48")
	_ok(has_fascia, "ROOF.fascia", "封檐板 0.12x0.26")
	var mm_ridge := _find_multimesh("RoofRidgeCaps")
	var mm_tiles := _find_multimesh("RoofTiles")
	var mm_rafters := _find_multimesh("RoofRafters")
	_ok(mm_ridge > 0, "ROOF.ridge_caps", "屋脊瓦 MultiMesh 实例=%d" % mm_ridge)
	_ok(mm_tiles > 50, "ROOF.tiles", "筒瓦 MultiMesh 实例=%d" % mm_tiles)
	_ok(mm_rafters > 5, "ROOF.rafters", "檐椽 MultiMesh 实例=%d" % mm_rafters)
	# 山墙：前山墙带阁楼窗洞（洞口宽 = attic_hw*2），后山墙实体
	var has_gable := _root.get_node_or_null("FrontGable") != null
	for b6 in _boxes:
		if String(b6["name"]) == "FrontGable":
			has_gable = true
	_ok(has_gable, "ROOF.front_gable", "前山墙（带阁楼窗洞）部件存在（合批后节点可能已释放，按清单名判定）")
	# 屋面最高点（按部件清单，排除烟囱 footprint）
	var top_y := -1e9
	for b5 in _boxes:
		var a5: AABB = b5["aabb"]
		var c5: Vector3 = a5.get_center()
		if absf(c5.x - float(C["ch_x"])) < 0.80 and absf(c5.z - float(C["ch_z"])) < 0.80 and a5.position.y > roof_base:
			continue
		top_y = maxf(top_y, a5.end.y)
	_ok(top_y - roof_base > IsleMath.HOUSE_ROOF_H and top_y - roof_base < IsleMath.HOUSE_ROOF_H + 0.30,
		"ROOF.mesh_top", "不含烟囱的几何最高点=%.3f (檐口+%.3f)" % [top_y, top_y - roof_base])

func _find_multimesh(nm: String) -> int:
	var n := _root.find_child(nm, true, false)
	if n != null and n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
		return (n as MultiMeshInstance3D).multimesh.instance_count
	return 0

# ============================================================
# 7) 烟囱
# ============================================================
func _check_chimney() -> void:
	var C := _C
	var ridge_y: float = C["ridge_y"]
	var ch_top: float = C["ch_top"]
	_near("CHIMNEY.body_top", ch_top, ridge_y, 0.001)
	var node: Node3D = _d["chimney_top"]
	_ok(node != null, "CHIMNEY.top_node", "ChimneyTop 标记节点存在")
	if node != null:
		_near("CHIMNEY.top_node_y", node.position.y, ch_top + IsleScaleSpec.HOUSE_CHIMNEY_ABOVE_RIDGE, 0.001)
		_near("CHIMNEY.top_above_ridge", node.position.y - ridge_y, IsleScaleSpec.HOUSE_CHIMNEY_ABOVE_RIDGE, 0.001)
		_near("CHIMNEY.x", node.position.x, float(C["ch_x"]), 0.001)
		_near("CHIMNEY.z", node.position.z, float(C["ch_z"]), 0.001)
	# 烟囱最高石块（顶冠）几何
	var cap_top := -1e9
	for b in _boxes:
		var a: AABB = b["aabb"]
		if absf(a.get_center().x - float(C["ch_x"])) < 0.7 and absf(a.get_center().z - float(C["ch_z"])) < 0.7 and a.position.y > ridge_y - 0.5:
			cap_top = maxf(cap_top, a.end.y)
	_near("CHIMNEY.geom_top", cap_top, ch_top + 0.35, 0.05)
	var hit: Node = _d["chimney_hit"]
	_ok(hit != null and String(hit.name) == "ChimneyHit", "CHIMNEY.hitbox", "ChimneyHit 节点存在")

# ============================================================
# 8) 门廊 / 台阶
# ============================================================
func _check_porch() -> void:
	var C := _C
	var deck: float = C["deck_top"]
	_ok(deck >= 0.42 and deck <= 0.44, "PORCH.deck_top", "廊台面=%.3f ∈[0.42,0.44]" % deck)
	var steps := _root.get_node_or_null("PorchSteps")
	_ok(steps != null, "PORCH.steps_node", "PorchSteps 节点存在")
	if steps != null:
		_near("PORCH.step_count", float(steps.get_meta("step_count")), 3.0, 0.001)
		_near("PORCH.step_rise", float(steps.get_meta("rise")), 0.14, 0.001)
		_near("PORCH.step_run", float(steps.get_meta("run")), 0.30, 0.001)
		_near("PORCH.step_top", float(steps.get_meta("top_y")), deck, 0.001)
		var sb: float = float(steps.get_meta("bottom_y"))
		_ok(sb >= -0.30 and sb <= 0.02, "PORCH.step_bottom", "台阶底局部 y=%.3f ∈[-0.30,0.02]（地形低于屋基时埋入地表）" % sb)
	# 3 级台阶：宽度递减 2.60/2.40/2.20，踏面顶 = deck_top - 0.14*(i+1)
	var widths: Array = []
	var step_tops: Array = []
	for b in _boxes:
		if String(b["parent"]) == "PorchSteps" and String(b["kind"]) == "Box":
			var s: Vector3 = b["size"]
			if s.y > 0.5:
				widths.append(s.x)
				step_tops.append(_aabb_key(b, "aabb").end.y)
	widths.sort()
	_ok(widths.size() == 3, "PORCH.step_boxes", "台阶盒 3 块 (实测 %d)" % widths.size())
	if widths.size() == 3:
		_near("PORCH.steps_w1_2", float(widths[2]), 2.60, 0.05)
		_near("PORCH.steps_w3", float(widths[0]), 2.20, 0.05)
	step_tops.sort()
	step_tops.reverse()
	if step_tops.size() == 3:
		for ti in range(3):
			_near("PORCH.step_top_%d" % (ti + 1), float(step_tops[ti]), deck - 0.14 * float(ti + 1), 0.01)
	# 门廊吊灯位置（局部 ±1.95, 2.05, 4.55）
	_vec_near("PORCH.lantern_l", C["lantern_pos"], Vector3(-1.95, 2.05, 4.55), 0.001)
	_vec_near("PORCH.lantern_r", C["lantern_pos_right"], Vector3(1.95, 2.05, 4.55), 0.001)
	var lw: Vector3 = _d["lantern_world"]
	_vec_near("PORCH.lantern_world", lw, _world(Vector3(-1.95, 2.05, 4.55)), 0.01)

func _world(local: Vector3) -> Vector3:
	return _root.transform * local

# ============================================================
# 9) 楼梯（16 级 L 形）+ 净空 + 洞口
# ============================================================
func _check_stairs() -> void:
	var C := _C
	var fy: float = C["fy"]
	var rise: float = C["stair_rise"]
	var tread: float = C["stair_tread"]
	var ridge_y: float = C["ridge_y"]
	var pitch: float = C["pitch"]
	var attic_floor: float = C["attic_floor"]
	var st := _root.get_node_or_null("Staircase")
	_ok(st != null, "STAIR.node", "Staircase 节点存在")
	var sd: Dictionary = _d["stairs"]
	_ok(not sd.is_empty(), "STAIR.data", "build 返回 stairs 字典")
	_near("STAIR.risers", float(sd["risers"]), IsleScaleSpec.STAIR_COUNT, 0.001)
	_near("STAIR.rise", float(sd["rise"]), IsleScaleSpec.STAIR_RISE, 0.0001)
	_near("STAIR.tread", float(sd["tread"]), IsleScaleSpec.STAIR_TREAD, 0.0001)
	_near("STAIR.width", float(sd["width"]), IsleScaleSpec.STAIR_WIDTH, 0.0001)
	_near("STAIR.handrail_h", float(sd["handrail_h"]), IsleScaleSpec.STAIR_HANDRAIL_H, 0.0001)
	_near("STAIR.land_top", float(sd["land_top"]), fy + 8.0 * rise, 0.001)
	_near("STAIR.attic_floor", float(sd["attic_floor"]), fy + 16.0 * rise, 0.001)
	_near("STAIR.total_rise", float(sd["attic_floor"]) - fy, 16.0 * IsleScaleSpec.STAIR_RISE, 0.001)
	# 每级踏面：15 条（1..7, 9..15, 16）+ 平台
	var treads: Array = sd["treads"]
	_ok(treads.size() == 15, "STAIR.tread_data", "踏面数据 15 条 (实测 %d)" % treads.size())
	var mono := true
	var prev_top := -1e9
	var rise_ok := true
	for t in treads:
		var top: float = t["top"]
		if top <= prev_top:
			mono = false
		prev_top = top
		var lvl: int = int(t["level"])
		if lvl >= 1 and lvl <= 7:
			if absf(top - (fy + float(lvl) * rise)) > 0.002:
				rise_ok = false
		elif lvl >= 9 and lvl <= 15:
			if absf(top - (fy + float(lvl) * rise)) > 0.002:
				rise_ok = false
		elif lvl == 16:
			if absf(top - attic_floor) > 0.002:
				rise_ok = false
	_ok(mono, "STAIR.tread_monotonic", "踏面高度严格递增")
	_ok(rise_ok, "STAIR.tread_levels", "每级踏面高度 = fy + level*rise")
	# 平台 0.85x0.85，顶 = land_top
	var ls: Vector3 = sd["landing_size"]
	_ok(ls.x >= 0.80 and ls.z >= 0.80, "STAIR.landing_size", "平台 %.3f x %.3f (≥0.80 转身空间)" % [ls.x, ls.z])
	_near("STAIR.landing_top", float(sd["land_top"]), fy + 8.0 * rise, 0.001)
	var lc: Vector3 = sd["landing_center"]
	_near("STAIR.landing_y", lc.y, float(sd["land_top"]), 0.01)
	# 洞口覆盖：r1 覆盖 Flight A+平台，r2 覆盖 Flight B
	var r1: Rect2 = sd["hole_r1"]
	var r2: Rect2 = sd["hole_r2"]
	var fa: Dictionary = C["stair_flight_a"]
	var fb: Dictionary = C["stair_flight_b"]
	var ht := 0.01
	var ax0: float = minf(fa["x0"], fa["x1"])
	var ax1: float = maxf(fa["x0"], fa["x1"])
	var az0: float = minf(fa["z0"], fa["z1"])
	var az1: float = maxf(fa["z0"], fa["z1"])
	_ok(r1.position.x <= ax0 + ht and r1.end.x >= ax1 - ht and r1.position.y <= az0 + ht and r1.end.y >= az1 - ht,
		"STAIR.hole_r1_covers_A", "r1=%s 覆盖 A[%.2f..%.2f]x[%.2f..%.2f]" % [str(r1), ax0, ax1, az0, az1])
	var bx0: float = minf(fb["x0"], fb["x1"])
	var bx1: float = maxf(fb["x0"], fb["x1"])
	var bz0: float = minf(fb["z0"], fb["z1"])
	var bz1: float = maxf(fb["z0"], fb["z1"])
	_ok(r2.position.x <= bx0 + ht and r2.end.x >= bx1 - ht and r2.position.y <= bz0 + ht and r2.end.y >= bz1 - ht,
		"STAIR.hole_r2_covers_B", "r2=%s 覆盖 B[%.2f..%.2f]x[%.2f..%.2f]" % [str(r2), bx0, bx1, bz0, bz1])
	# 梯段上方净空（屋面下皮 - 踏面顶 ≥ 1.95），按每级踏面中心线
	var tanp: float = tan(pitch)
	var under_off: float = ROOF_PANEL_T / cos(pitch)
	var hr_min := 1e9
	var hr_worst := 0
	for t2 in treads:
		var lvl2: int = int(t2["level"])
		if lvl2 == 16:
			continue
		var ctr: Vector3 = t2["center"]
		var under: float = ridge_y - absf(ctr.x) * tanp - under_off
		var hr: float = under - float(t2["top"])
		if hr < hr_min:
			hr_min = hr
			hr_worst = lvl2
	# 平台净空
	var under_land: float = ridge_y - absf(lc.x) * tanp - under_off
	var hr_land: float = under_land - float(sd["land_top"])
	_ok(hr_min >= IsleScaleSpec.STAIR_HEADROOM, "STAIR.headroom_flights", "最小净空=%.3f (第 %d 级) ≥ %.2f" % [hr_min, hr_worst, IsleScaleSpec.STAIR_HEADROOM])
	_ok(hr_land >= IsleScaleSpec.STAIR_HEADROOM, "STAIR.headroom_landing", "平台净空=%.3f ≥ %.2f" % [hr_land, IsleScaleSpec.STAIR_HEADROOM])
	# 二层入口净空（第16级/阁楼板面处的屋面下皮）
	var under_entry: float = ridge_y - absf(fb["x1"]) * tanp - under_off
	_ok(under_entry - attic_floor >= IsleScaleSpec.STAIR_HEADROOM,
		"STAIR.headroom_entry", "二层入口净空=%.3f ≥ %.2f" % [under_entry - attic_floor, IsleScaleSpec.STAIR_HEADROOM])
	# 楼梯家具清单语义名（T1 审计用）
	if st != null:
		var names: Array = []
		if st.has_meta("batch_manifest"):
			for e in st.get_meta("batch_manifest"):
				names.append(String(e["name"]))
		var need := ["StairTreadA_01", "StairTreadA_07", "StairRiserA_01", "StairStringerA_L", "StairStringerA_R",
			"StairHandrailA", "StairBalusterA_01", "StairNewelA_0", "StairLanding", "StairLandingNose",
			"StairTreadB_09", "StairTreadB_15", "StairRiserB_09", "StairRiserB_16", "StairStringerB_L",
			"StairHandrailB", "StairBalusterB_09", "StairNewelB_0", "StairNewelB_1"]
		var missing: Array = []
		for nm in need:
			if not names.has(nm):
				missing.append(nm)
		_ok(missing.is_empty(), "STAIR.manifest_names", "语义名齐全 (缺 %s)" % str(missing))
		# Staircase meta（T1 读取口径）
		_near("STAIR.meta_risers", float(st.get_meta("risers")), 16.0, 0.001)
		_near("STAIR.meta_rise", float(st.get_meta("rise")), IsleScaleSpec.STAIR_RISE, 0.0001)
		_near("STAIR.meta_tread", float(st.get_meta("tread")), IsleScaleSpec.STAIR_TREAD, 0.0001)
		_near("STAIR.meta_width", float(st.get_meta("width")), IsleScaleSpec.STAIR_WIDTH, 0.0001)
		_near("STAIR.meta_land_top", float(st.get_meta("land_top")), fy + 8.0 * rise, 0.001)
		_near("STAIR.meta_attic_floor", float(st.get_meta("attic_floor")), attic_floor, 0.001)
		var mr1: Rect2 = st.get_meta("hole_r1")
		var mr2: Rect2 = st.get_meta("hole_r2")
		_ok(mr1 == r1 and mr2 == r2, "STAIR.meta_holes", "Staircase meta hole_r1/r2 与 build 返回一致")
	# root meta stairs 镜像
	var rs: Dictionary = _root.get_meta("stairs", {})
	_ok(not rs.is_empty() and int(rs["risers"]) == 16, "STAIR.root_meta", "root meta stairs.risers=16")

# ============================================================
# 10) 阁楼室内：L 洞 / 楼板 / 护栏 / 吊灯
# ============================================================
func _check_attic_interior() -> void:
	var C := _C
	var ia := _root.get_node_or_null("AtticInterior")
	_ok(ia != null, "ATTIC.node", "AtticInterior 节点存在")
	if ia == null:
		return
	_near("ATTIC.furniture_count_meta", float(ia.get_meta("furniture_count", -1)), 15.0, 0.001)
	# 3 块结构楼板：厚 0.20，顶 = attic_floor
	var slabs: Array = []
	for bsl in _boxes:
		if String(bsl["parent"]) == "AtticInterior" and String(bsl["kind"]) == "Box" and absf(float(_vec_key(bsl, "size").y) - 0.20) <= 0.005:
			slabs.append(bsl)
	_ok(slabs.size() == 3, "ATTIC.slab_zones", "结构楼板 3 块 (实测 %d)" % slabs.size())
	var hole_r1: Rect2 = _d["stairs"]["hole_r1"]
	var hole_r2: Rect2 = _d["stairs"]["hole_r2"]
	var leak := 0
	for e2 in slabs:
		var a: AABB = _entry_aabb(String(e2["kind"]), e2["size"], e2["xf"])
		var rr := Rect2(a.position.x, a.position.z, a.size.x, a.size.z)
		if rr.intersects(hole_r1, true) and rr.intersection(hole_r1).get_area() > 0.01:
			leak += 1
		if rr.intersects(hole_r2, true) and rr.intersection(hole_r2).get_area() > 0.01:
			leak += 1
	_near("ATTIC.slabs_clear_hole", float(leak), 0.0, 0.001)
	# 洞口护栏（3 段 + 4 柱）
	var rails := 0
	for brl in _boxes:
		if String(brl["parent"]) == "AtticInterior" and (String(brl["name"]).begins_with("AtticRail") or String(brl["name"]).begins_with("AtticHole")):
			rails += 1
	print(TAG, " INFO attic_hole_rail_parts=%d" % rails)
	# 阁楼吊灯（C attic_lamp_world 在世界坐标）
	var al: Vector3 = _d["attic_lamp_world"]
	var al_local: Vector3 = _root.transform.affine_inverse() * al
	_ok(al_local.y > float(C["attic_floor"]) + 1.2 and al_local.y < float(C["ridge_y"]), "ATTIC.lamp_y", "阁楼吊灯局部 y=%.3f" % al_local.y)
	# 阁楼可站立区：|x|≤1.8 处屋面下皮 - 阁楼板 ≥ ATTIC_KNEE_H
	var pitch: float = C["pitch"]
	var under_off: float = ROOF_PANEL_T / cos(pitch)
	_near("ATTIC.knee_at_wall", float(C["attic_knee"]), IsleScaleSpec.ATTIC_KNEE_H, 0.02)
	var stand_h: float = float(C["ridge_y"]) - 1.8 * tan(pitch) - under_off - float(C["attic_floor"])
	_ok(stand_h >= 1.50, "ATTIC.stand_zone_net", "|x|≤1.8 可站立净高=%.3f (≥1.50)" % stand_h)

# ============================================================
# 11) 家具尺寸 / 数量
# ============================================================
func _check_furniture_dims() -> void:
	var ground := 0
	var attic := 0
	for it in _props:
		if String(it["floor"]) == "ground":
			ground += 1
		else:
			attic += 1
	_ok(ground == 23, "PROPS.ground_count", "一层家具 23 件 (实测 %d)" % ground)
	_ok(attic == 15, "PROPS.attic_count", "阁楼家具 15 件 (实测 %d)" % attic)
	_ok(_props.size() == 38, "PROPS.total", "家具合计 38 件 (实测 %d)" % _props.size())
	# 与 IsleScaleSpec 注册尺寸比对（旋转感知：AABB=旋转后外接盒；装饰件容差放宽）
	var bad: Array = []
	var warns: Array = []
	for it2 in _props:
		var kind: String = it2["kind"]
		var want: Vector3 = IsleScaleSpec.size_of(kind)
		if want == Vector3.ZERO:
			warns.append(kind + ":no_spec")
			continue
		var a2: AABB = it2["aabb"]
		var got: Vector3 = a2.size
		var yaw_p: float = (it2["node"] as Node3D).rotation.y
		var cc: float = absf(cos(yaw_p))
		var ss: float = absf(sin(yaw_p))
		var ex: float = want.x * cc + want.z * ss
		var ez: float = want.x * ss + want.z * cc
		var hi: float = maxf(ex, ez) + 0.06
		var lo: float = minf(want.x, want.z) * 0.85
		var dims_ok: bool = absf(got.y - want.y) <= 0.05 and got.x <= hi and got.z <= hi and minf(got.x, got.z) >= lo
		if not dims_ok:
			bad.append("%s got=(%.2f,%.2f,%.2f) want=(%.2f,%.2f,%.2f) yaw=%.2f" % [kind, got.x, got.y, got.z, want.x, want.y, want.z, yaw_p])
		elif absf(got.y - want.y) > 0.03 or minf(got.x, got.z) < lo + 0.02:
			warns.append("%s got=(%.2f,%.2f,%.2f) want=(%.2f,%.2f,%.2f)" % [kind, got.x, got.y, got.z, want.x, want.y, want.z])
	_ok(bad.is_empty(), "PROPS.dims_vs_spec", "家具整体尺寸与 IsleScaleSpec 相符 (超差 %s)" % str(bad))
	for w in warns:
		_ok(true, "PROPS.dims_warn", String(w), true)
	# 落地件 y = 楼层地面；墙挂件不应贴地面
	var ground_fl: float = float(_C["fy"]) + 0.02
	var attic_fl: float = float(_C["attic_floor"]) + 0.02
	var pos_bad: Array = []
	for it3 in _props:
		var n: Node3D = it3["node"]
		var want_y: float = ground_fl if String(it3["floor"]) == "ground" else attic_fl
		if (not bool(it3["mounted"])) and String(it3["kind"]) != "table_lamp" and absf(n.position.y - want_y) > 0.02:
			pos_bad.append("%s y=%.3f want=%.3f" % [String(it3["kind"]), n.position.y, want_y])
	_ok(pos_bad.is_empty(), "PROPS.floor_y", "落地家具 y=楼层地面 (异常 %s)" % str(pos_bad))

# ============================================================
# 12) 家具体积重叠（含 T3 允许例外）
# ============================================================
func _check_furniture_overlap() -> void:
	var flat := ["rug", "doormat"]
	var overlaps: Array = []
	for i in range(_props.size()):
		var a: Dictionary = _props[i]
		if bool(a["mounted"]) or flat.has(String(a["kind"])):
			continue
		var aa: AABB = a["aabb"]
		for j in range(i + 1, _props.size()):
			var b: Dictionary = _props[j]
			if String(b["floor"]) != String(a["floor"]):
				continue
			if bool(b["mounted"]) or flat.has(String(b["kind"])):
				continue
			var bb: AABB = b["aabb"]
			var ov := _overlap_size(aa, bb)
			if ov.x <= 0.015 or ov.z <= 0.015 or ov.y <= 0.010:
				continue
			if _overlap_allowed(String(a["kind"]), String(b["kind"]), aa, bb, ov):
				continue
			overlaps.append("%s∩%s ov=(%.2f,%.2f,%.2f)" % [String(a["kind"]), String(b["kind"]), ov.x, ov.y, ov.z])
	_ok(overlaps.is_empty(), "PROPS.no_volume_overlap", "家具无非法体积重叠 %s" % str(overlaps))
	# bed↔nightstand ≤ 0.20
	var bed := _find_prop("bed", "attic")
	var ns := _find_prop("nightstand", "attic")
	if not bed.is_empty() and not ns.is_empty():
		var d: float = _gap_xz(bed["aabb"], ns["aabb"])
		_ok(d <= 0.20, "PROPS.bed_nightstand", "床↔床头柜间距=%.3f ≤0.20" % d)
	# sofa / armchair ↔ coffee_table 0.25~0.60
	var coffee := _find_prop("coffee_table", "ground")
	if not coffee.is_empty():
		for nm in ["sofa", "armchair"]:
			var seat := _find_prop(nm, "ground")
			if not seat.is_empty():
				var gap: float = _gap_xz(seat["aabb"], coffee["aabb"])
				_ok(gap >= 0.25 and gap <= 0.60, "PROPS." + nm + "_coffee_gap", "间距=%.3f ∈[0.25,0.60]" % gap)
	# chair 靠近桌/书桌
	var tables := ["dining_table", "desk"]
	for it in _props:
		if String(it["kind"]) != "chair":
			continue
		var best := 99.0
		for tn in tables:
			for t2 in _props:
				if String(t2["kind"]) == tn and String(t2["floor"]) == String(it["floor"]):
					best = minf(best, _gap_xz(it["aabb"], t2["aabb"]))
		_ok(best <= 0.40, "PROPS.chair_near_table", "椅(%.2f,%.2f) 到桌/书桌=%.3f ≤0.40" % [it["node"].position.x, it["node"].position.z, best])

func _overlap_size(a: AABB, b: AABB) -> Vector3:
	var x := minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x)
	var y := minf(a.end.y, b.end.y) - maxf(a.position.y, b.position.y)
	var z := minf(a.end.z, b.end.z) - maxf(a.position.z, b.position.z)
	return Vector3(maxf(x, 0.0), maxf(y, 0.0), maxf(z, 0.0))

func _overlap_allowed(ka: String, kb: String, a: AABB, b: AABB, ov: Vector3) -> bool:
	# 台灯/落地灯放在台面上 → 允许面接触（Y 重叠很小）
	var lamps := ["table_lamp", "floor_lamp"]
	if lamps.has(ka) or lamps.has(kb):
		if ov.y <= 0.020:
			return true
	# 椅子收进桌下（T3 tuck_pair：重叠≤0.22 且椅心在桌 AABB 外）
	var chairs := ["chair", "reading_chair", "shoe_bench", "armchair", "sofa"]
	var desk_like := ["dining_table", "desk"]
	var chair_name := ""
	var table_aabb := AABB()
	var chair_aabb := AABB()
	if chairs.has(ka) and desk_like.has(kb):
		chair_name = ka
		chair_aabb = a
		table_aabb = b
	elif chairs.has(kb) and desk_like.has(ka):
		chair_name = kb
		chair_aabb = b
		table_aabb = a
	if chair_name != "":
		var cx: float = chair_aabb.get_center().x
		var cz: float = chair_aabb.get_center().z
		var center_out: bool = cx < table_aabb.position.x - 0.001 or cx > table_aabb.end.x + 0.001 or cz < table_aabb.position.z - 0.001 or cz > table_aabb.end.z + 0.001
		var tuck: float = minf(minf(ov.x, ov.z), 0.22)
		if minf(ov.x, ov.z) <= 0.22 and center_out:
			return true
	return false

func _find_prop(kind: String, floor_name: String) -> Dictionary:
	for it in _props:
		if String(it["kind"]) == kind and String(it["floor"]) == floor_name:
			return it
	return {}

func _gap_xz(a: AABB, b: AABB) -> float:
	var dx := maxf(maxf(a.position.x - b.end.x, b.position.x - a.end.x), 0.0)
	var dz := maxf(maxf(a.position.z - b.end.z, b.position.z - a.end.z), 0.0)
	return sqrt(dx * dx + dz * dz)

# ============================================================
# 13) 门内侧 1.2m / 楼梯口 1.2m / 楼梯矩形 占用区
# ============================================================
func _check_layout_zones() -> void:
	var C := _C
	var fy: float = C["fy"]
	var dc: Dictionary = _C["door_clear"]
	var pivot_x: float = float(_vec_key(dc, "pivot_local").x)
	var lid: float = pivot_x - 0.03
	var rid: float = pivot_x + 0.03 + float(dc["leaf_w"])
	var door_zone := AABB(Vector3(lid, fy, 1.60), Vector3(rid - lid, 2.10, 1.20))
	var bad: Array = []
	for it in _props:
		if String(it["floor"]) != "ground" or bool(it["mounted"]):
			continue
		if String(it["kind"]) in ["rug", "doormat"]:
			continue
		var ov := _overlap_size(door_zone, it["aabb"])
		if ov.x > 0.01 and ov.y > 0.01 and ov.z > 0.01:
			bad.append(String(it["kind"]))
	_ok(bad.is_empty(), "LAYOUT.door_inner_12m", "门内侧 1.2m 无家具 %s" % str(bad))
	# 楼梯底部口 1.2m 通行区
	var mouth := AABB(Vector3(2.455, fy, 0.38), Vector3(1.21, 1.90, 1.25))
	var bad2: Array = []
	for it2 in _props:
		if String(it2["floor"]) != "ground" or bool(it2["mounted"]):
			continue
		if String(it2["kind"]) in ["rug", "doormat"]:
			continue
		var ov2 := _overlap_size(mouth, it2["aabb"])
		if ov2.x > 0.01 and ov2.y > 0.01 and ov2.z > 0.01:
			bad2.append(String(it2["kind"]))
	_ok(bad2.is_empty(), "LAYOUT.stair_mouth_12m", "楼梯底部口 1.2m 通行区无家具 %s" % str(bad2))
	# 楼梯矩形（A/B 两跑）不被一层家具占用
	var ra := Rect2(2.64, -1.94, 0.85, 1.82)
	var rb := Rect2(0.82, -2.79, 1.82, 0.85)
	var bad3: Array = []
	for it3 in _props:
		if String(it3["floor"]) != "ground" or bool(it3["mounted"]):
			continue
		var aa: AABB = it3["aabb"]
		var rr := Rect2(aa.position.x, aa.position.z, aa.size.x, aa.size.z)
		if rr.intersects(ra) or rr.intersects(rb):
			var i1: Rect2 = rr.intersection(ra)
			var i2: Rect2 = rr.intersection(rb)
			if i1.get_area() > 0.02 or i2.get_area() > 0.02:
				bad3.append(String(it3["kind"]))
	_ok(bad3.is_empty(), "LAYOUT.stair_rects_clear", "一层家具不占楼梯两跑 %s" % str(bad3))
	# 阁楼家具不占楼梯洞口
	var bad4: Array = []
	for it4 in _props:
		if String(it4["floor"]) != "attic" or bool(it4["mounted"]):
			continue
		var ab: AABB = it4["aabb"]
		var rr2 := Rect2(ab.position.x, ab.position.z, ab.size.x, ab.size.z)
		var i3: Rect2 = rr2.intersection(ra)
		var i4: Rect2 = rr2.intersection(rb)
		if i3.get_area() > 0.02 or i4.get_area() > 0.02:
			bad4.append(String(it4["kind"]))
	_ok(bad4.is_empty(), "LAYOUT.attic_clear_hole", "阁楼家具不占楼梯洞口 %s" % str(bad4))

# ============================================================
# 14) 阁楼家具净高 / 墙挂件高度（T3 口径：屋面下皮）
# ============================================================
func _check_attic_clearance() -> void:
	var C := _C
	var ridge_y: float = C["ridge_y"]
	var pitch: float = C["pitch"]
	var under_off: float = ROOF_PANEL_T / cos(pitch)
	var tanp: float = tan(pitch)
	var attic_floor: float = C["attic_floor"]
	var bad: Array = []
	for it in _props:
		if String(it["floor"]) != "attic":
			continue
		var a: AABB = it["aabb"]
		var xmax: float = maxf(absf(a.position.x), absf(a.end.x))
		var under: float = ridge_y - xmax * tanp - under_off
		var top: float = a.end.y
		var margin: float = 0.03 if bool(it["mounted"]) else 0.02
		if top > under - margin:
			bad.append("%s x_max=%.2f top=%.3f under=%.3f" % [String(it["kind"]), xmax, top, under])
	_ok(bad.is_empty(), "ATTIC.roof_clearance", "阁楼家具均低于屋面下皮 %s" % str(bad))
	# 墙挂件高度（相对阁楼地面）：picture_frame 中心 1.44~1.70；curtain 杆 1.70~2.40
	for nm in ["picture_frame"]:
		var it2 := _find_prop(nm, "attic")
		if not it2.is_empty():
			var c: float = _aabb_key(it2, "aabb").get_center().y - attic_floor
			_ok(c >= 1.44 and c <= 1.70, "ATTIC.picture_center_h", "picture_frame 中心相对阁楼地面=%.3f ∈[1.44,1.70]" % c)
	var curtains := 0
	for it3 in _props:
		if String(it3["kind"]) == "curtain" and String(it3["floor"]) == "attic":
			curtains += 1
			var rod: float = (it3["node"] as Node3D).position.y - attic_floor
			_ok(rod >= 1.70 and rod <= 2.40, "ATTIC.curtain_rod_h", "帘杆相对阁楼地面=%.3f ∈[1.70,2.40]" % rod)
	_ok(curtains == 2, "ATTIC.curtain_count", "阁楼窗帘 2 件 (实测 %d)" % curtains)

# ============================================================
# 15) 通行连通性（0.10 网格 + 净宽判定）
# ============================================================
func _check_corridor() -> void:
	var x0 := -3.44
	var x1 := 3.44
	var z0 := -2.74
	var z1 := 2.74
	var step := 0.10
	var nx: int = int(round((x1 - x0) / step)) + 1
	var nz: int = int(round((z1 - z0) / step)) + 1
	var rects: Array = []
	for it in _props:
		if String(it["floor"]) != "ground":
			continue
		if bool(it["mounted"]):
			continue
		var a: AABB = it["aabb"]
		if a.size.y < 0.10:
			continue
		rects.append(Rect2(a.position.x, a.position.z, a.size.x, a.size.z))
	var st: Dictionary = _C["stairs"]
	rects.append(st["hole_r1"] as Rect2)
	rects.append(st["hole_r2"] as Rect2)
	var clear: Array = []
	for iz in range(nz):
		for ix in range(nx):
			var px: float = x0 + float(ix) * step
			var pz: float = z0 + float(iz) * step
			var d: float = minf(minf(px - x0, x1 - px), minf(pz - z0, z1 - pz))
			for r in rects:
				var rr: Rect2 = r
				var dx: float = maxf(maxf(rr.position.x - px, 0.0), px - (rr.position.x + rr.size.x))
				var dz: float = maxf(maxf(rr.position.y - pz, 0.0), pz - (rr.position.y + rr.size.y))
				d = minf(d, sqrt(dx * dx + dz * dz))
			clear.append(d)
	var door_cell := _grid_index(Vector2(0.01, 2.35), x0, z0, step, nx, nz)
	var mouth_cell := _grid_index(Vector2(3.065, 0.43), x0, z0, step, nx, nz)
	var vals: Array = clear.duplicate()
	vals.sort()
	vals.reverse()
	var best := 0.0
	for v in vals:
		if float(v) <= 0.0:
			break
		if _grid_connected(clear, nx, nz, door_cell, mouth_cell, float(v)):
			best = float(v)
			break
	var door_c: float = float(clear[door_cell])
	var mouth_c: float = float(clear[mouth_cell])
	_ok(2.0 * best >= 0.30, "PASSAGE.connect_clearance", "门内侧→楼梯口连通，最大可行净宽=%.2f (≥0.30)" % (2.0 * best))
	_ok(2.0 * mouth_c >= 0.60, "PASSAGE.stair_mouth_clear", "楼梯口通行净宽=%.2f (≥0.60)" % (2.0 * mouth_c))
	_ok(2.0 * door_c >= 0.60, "PASSAGE.door_clear", "门内侧净宽=%.2f (≥0.60)" % (2.0 * door_c))
	print(TAG, " INFO passage best_threshold=%.2f door_cell=%.2f mouth_cell=%.2f" % [best, door_c, mouth_c])

func _grid_index(p: Vector2, x0: float, z0: float, step: float, nx: int, nz: int) -> int:
	var ix: int = clampi(int(round((p.x - x0) / step)), 0, nx - 1)
	var iz: int = clampi(int(round((p.y - z0) / step)), 0, nz - 1)
	return iz * nx + ix

func _grid_connected(clear: Array, nx: int, nz: int, start: int, goal: int, thr: float) -> bool:
	if float(clear[start]) < thr or float(clear[goal]) < thr:
		return false
	var seen: Dictionary = {start: true}
	var q: Array = [start]
	while not q.is_empty():
		var cur: int = int(q.pop_front())
		if cur == goal:
			return true
		var cx: int = cur % nx
		var cz: int = int(cur / nx)
		for off in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var ax: int = cx + int(off[0])
			var az: int = cz + int(off[1])
			if ax < 0 or ax >= nx or az < 0 or az >= nz:
				continue
			var ni: int = az * nx + ax
			if seen.has(ni) or float(clear[ni]) < thr:
				continue
			seen[ni] = true
			q.append(ni)
	return false

# ============================================================
# 16) build() 返回契约 / 灯光 / 材质 / 合批 / meta
# ============================================================
func _check_contract() -> void:
	var keys := ["root", "door_pivot", "door_hit", "chimney_hit", "chimney_top", "window_mats",
		"window_halos", "lantern_mat", "lantern_halo", "lantern_halos", "perches", "lantern_world",
		"light_sources", "glass_mats", "interior_pos", "front_window_world", "interior_lamp_world",
		"fireplace_world", "attic_window_world", "attic_lamp_world", "attic_lamp2_world",
		"attic_glass_mats", "beam_occluders", "cat", "stairs"]
	var missing: Array = []
	for k in keys:
		if not _d.has(k):
			missing.append(k)
	_ok(missing.is_empty(), "CONTRACT.return_keys", "build 返回 25 键齐全 (缺 %s)" % str(missing))
	_ok(_d.get("root") is Node3D, "CONTRACT.root", "root 节点")
	var C := _C
	var ls: Array = _d["light_sources"]
	var wl: Array = C["win_lights"]
	_ok(ls.size() == wl.size() + 6, "CONTRACT.lights", "light_sources=%d = 6 固定 + %d 窗 (实测 %d)" % [ls.size(), wl.size(), ls.size()])
	for l in ls:
		var ld: Dictionary = l
		var okv: bool = ld.has("pos") and ld.has("range") and ld.has("intensity") and float(ld["range"]) > 0.0 and float(ld["intensity"]) > 0.0
		_ok(okv, "CONTRACT.light_valid", "光源 range=%.2f intensity=%.2f" % [float(ld.get("range", 0.0)), float(ld.get("intensity", 0.0))])
	var lamp_local: Vector3 = _root.to_local(_vec_key(_d, "interior_lamp_world"))
	var want_lamp := Vector3(1.45, float(C["in_top"]) - 0.62, 0.80)
	_ok(lamp_local.distance_to(want_lamp) <= 0.01, "LIGHT.dining_lamp_pos", "一层吊灯光源移餐桌正上方 local=(%.2f,%.2f,%.2f)" % [lamp_local.x, lamp_local.y, lamp_local.z])
	var fire_local: Vector3 = _root.to_local(ls[1]["pos"])
	var want_fire := Vector3(float(C["ch_x"]), float(C["fy"]) + 0.55, -2.30)
	_ok(fire_local.distance_to(want_fire) <= 0.01, "LIGHT.fireplace_pos", "壁炉光源 local=(%.2f,%.2f,%.2f)" % [fire_local.x, fire_local.y, fire_local.z])
	for i in [2, 3]:
		var lp: Vector3 = _root.to_local(ls[i]["pos"])
		_ok(absf(lp.y - 2.05) <= 0.01, "LIGHT.lantern_y", "门廊灯 y=%.2f (局部)" % lp.y)
	var sym := 0
	var lantern_y := 0.0
	for i2 in [2, 3]:
		var lp2: Vector3 = _root.to_local(ls[i2]["pos"])
		lantern_y = lp2.y
		if absf(absf(lp2.x) - 1.95) <= 0.02 and absf(lp2.z - 4.55) <= 0.02:
			sym += 1
	_ok(sym == 2, "LIGHT.lanterns", "门廊对称灯 2 盏 (实测 %d)" % sym)
	var nwin := 0
	for l2 in ls:
		var d2: Dictionary = l2
		if absf(float(d2["range"]) - 3.0) <= 0.01:
			nwin += 1
	_ok(nwin == wl.size(), "LIGHT.window_lights", "窗内光源=%d (实测 %d)" % [wl.size(), nwin])
	_ok(lamp_local.distance_to(want_lamp) <= 0.02 and fire_local.distance_to(want_fire) <= 0.02, "LIGHT.anchors", "吊灯/壁炉光源锚点正确")
	_ok(_vec_key(_d, "interior_lamp_world") != Vector3.ZERO, "LIGHT.lamp_world_set", "interior_lamp_world 有效")
	_ok((C["window_mats"] as Array).size() == 1, "MAT.window_mats", "window_mats=%d (main 写 glow)" % (C["window_mats"] as Array).size())
	_ok((C["glass_mats"] as Array).size() == 2, "MAT.glass_mats", "glass_mats=%d（双层玻璃）" % (C["glass_mats"] as Array).size())
	_ok((C["attic_glass_mats"] as Array).size() == 2, "MAT.attic_glass", "attic_glass_mats=%d" % (C["attic_glass_mats"] as Array).size())
	_ok(C["lantern_mat"] is ShaderMaterial, "MAT.lantern", "lantern_mat 为独立 ShaderMaterial")
	var gm: Array = C["glass_mats"]
	_ok(gm.size() > 0 and gm[0] is ShaderMaterial, "MAT.glass_shader", "玻璃材质为 ShaderMaterial（绘本风格 toon 管线）")
	var pe: Array = _d["perches"]
	_ok(pe.size() == 14, "CONTRACT.perches", "perches=14 (实测 %d)" % pe.size())
	var pbad: Array = []
	for p in pe:
		var pd: Dictionary = p
		for fk in ["id", "pos", "facing", "radius", "kind"]:
			if not pd.has(fk):
				pbad.append(fk)
	_ok(pbad.is_empty(), "CONTRACT.perch_fields", "perch 字段完整 (id/pos/facing/radius/kind)")
	var bo: Array = _d["beam_occluders"]
	_ok(bo.size() == 3, "CONTRACT.beam_occluders", "beam_occluders=3 (实测 %d)" % bo.size())
	var occ_top := -1e9
	for o in bo:
		var od: Dictionary = o
		_near("CONTRACT.occ_yaw", float(od["yaw"]), -float(IsleMath.HOUSE_YAW), 0.001)
		var oc: Vector3 = od["center"]
		var oh: Vector3 = od["half"]
		if oh.z > 2.0:
			occ_top = maxf(occ_top, oc.y - _root.position.y + oh.y)
	_near("CONTRACT.occ_roof_top_local", occ_top, float(C["ridge_y"]) + 0.24, 0.02)
	var cat: Dictionary = _d["cat"]
	_ok(not cat.is_empty(), "CONTRACT.cat", "cat 信息字典非空")
	var splits: Dictionary = {}
	for c2 in _root.get_children():
		if String(c2.name).begins_with("Batch_") and c2.has_meta("batch_split"):
			var k2 := String(c2.get_meta("batch_split"))
			splits[k2] = int(splits.get(k2, 0)) + 1
	_ok(splits.has("shell") and splits.has("interior") and splits.has("attic"), "BATCH.splits", "Batch 三层分裂=%s" % str(splits))
	_ok(_count_mats() > 500, "BATCH.mesh_count", "网格实例=%d" % _count_mats())
	for nn in ["DoorPivot", "Staircase", "AtticInterior", "AtticWindow", "DoorArch", "DoorSpandrel"]:
		_ok(_root.find_child(String(nn), true, false) != null, "CONTRACT.node_" + String(nn), "节点 %s 存在" % String(nn))
	_ok(_root.has_meta("door_clear") and _root.has_meta("door_opening"), "CONTRACT.meta_door", "root meta door_clear/door_opening")
	_ok(_root.has_meta("stairs") and _root.has_meta("cottage_ctx"), "CONTRACT.meta_stairs", "root meta stairs/cottage_ctx")

# ============================================================
# 17) 节点缩放（禁止整节点 scale 冒充重建）
# ============================================================
func _check_scales() -> void:
	var bad: Array = []
	var stack: Array = []
	for c in _root.get_children():
		stack.append(c)
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var p := String(_root.get_path_to(n))
		if p.begins_with("PorchCat"):
			continue
		if n is Node3D:
			var s: Vector3 = (n as Node3D).scale
			if absf(s.x - 1.0) > 0.001 or absf(s.y - 1.0) > 0.001 or absf(s.z - 1.0) > 0.001:
				bad.append(p)
		for c2 in n.get_children():
			stack.append(c2)
	_ok(bad.is_empty(), "SCALE.no_node_scale", "无节点级缩放（装饰件除外契约）%s" % str(bad.slice(0, 8)))
	_near("SCALE.root_scale", _root.scale.x, 1.0, 0.001)

# ============================================================
# 18) 尺寸表（写进简报）
# ============================================================
func _check_tables_roof() -> Dictionary:
	var C := _C
	var roof_base: float = C["roof_base"]
	var ridge_y: float = C["ridge_y"]
	var barge_top := -1e9
	for b3 in _boxes:
		if String(b3["kind"]) != "Box":
			continue
		var s3: Vector3 = b3["size"]
		if absf(s3.y - 0.24) <= 0.005 and absf(s3.z - 0.10) <= 0.02 and s3.x > 4.8:
			barge_top = maxf(barge_top, _aabb_key(b3, "aabb").end.y)
	var top_y := -1e9
	for b5 in _boxes:
		var a5: AABB = b5["aabb"]
		var c5: Vector3 = a5.get_center()
		if absf(c5.x - float(C["ch_x"])) < 0.80 and absf(c5.z - float(C["ch_z"])) < 0.80 and a5.position.y > roof_base:
			continue
		top_y = maxf(top_y, a5.end.y)
	return {"barge_top": barge_top - roof_base, "mesh_top": top_y - roof_base,
		"visual": ridge_y + 0.24 - roof_base}

func _print_tables() -> void:
	var C := _C
	print(TAG, " DIM house_outer w=%.3f d=%.3f wall_h=%.3f wall_t=%.3f fy=%.3f roof_base=%.3f ridge=%.3f roof_h=%.3f pitch_deg=%.2f eave_ov=%.3f" % [
		float(C["w"]), float(C["d"]), float(C["wh"]), float(C["wall_t"]), float(C["fy"]),
		float(C["roof_base"]), float(C["ridge_y"]), float(C["rh"]), rad_to_deg(float(C["pitch"])), IsleScaleSpec.HOUSE_EAVE_OV])
	print(TAG, " DIM storey room_clear_h=%.3f attic_floor=%.3f slab_t=%.3f attic_knee=%.3f in_top=%.3f" % [
		float(C["in_top"]) - float(C["fy"]), float(C["attic_floor"]), float(C["attic_slab_t"]), float(C["attic_knee"]), float(C["in_top"])])
	print(TAG, " DIM door clear=%.2fx%.2f spring=%.3f arch_ri=%.2f arch_ro=%.2f fanlight_r=%.2f leaf=%.2fx%.2f handle_h=%.2f wall_t=%.2f" % [
		IsleScaleSpec.DOOR_CLEAR_W, IsleScaleSpec.DOOR_CLEAR_H, float(_C["door_clear"]["spring_y"]),
		float(_C["door_clear"]["arch_ri"]), float(_C["door_clear"]["arch_ro"]), float(_C["door_clear"]["fanlight_r"]),
		float(_C["door_clear"]["leaf_w"]), float(_C["door_clear"]["leaf_h"]), float(_C["door_clear"]["handle_h"]), float(C["wall_t"])])
	var st: Dictionary = C["stairs"]
	var lg: Vector3 = st["landing_size"]
	print(TAG, " DIM stairs risers=%d rise=%.5f tread=%.2f width=%.2f handrail=%.2f land_top=%.3f landing=%.2fx%.2f attic_floor=%.2f headroom_min=%.3f" % [
		int(st["risers"]), float(st["rise"]), float(st["tread"]), float(st["width"]), float(st["handrail_h"]),
		float(st["land_top"]), lg.x, lg.z, float(st["attic_floor"]), float(st["headroom_min"])])
	var arr: Array = []
	for t in st["treads"]:
		arr.append("%d@%.4f" % [int(t["level"]), float(t["top"])])
	print(TAG, " DIM stair_treads %s" % str(arr))
	var roof := _check_tables_roof()
	print(TAG, " DIM roof structural_h=%.3f (ridge-roof_base) barge_top_above_eave=%.3f mesh_top_above_eave=%.3f visual_AABB=%.3f" % [
		float(C["ridge_y"]) - float(C["roof_base"]), float(roof["barge_top"]), float(roof["mesh_top"]), float(roof["visual"])])
	var cap_top := -1e9
	for b in _boxes:
		var aa: AABB = b["aabb"]
		if absf(aa.get_center().x - float(C["ch_x"])) < 0.7 and absf(aa.get_center().z - float(C["ch_z"])) < 0.7 and aa.position.y > float(C["ridge_y"]) - 0.5:
			cap_top = maxf(cap_top, aa.end.y)
	print(TAG, " DIM chimney ch_top=%.3f cap_top=%.3f above_ridge=%.3f" % [
		float(C["ch_top"]), cap_top, cap_top - float(C["ridge_y"])])
	var steps := _root.get_node_or_null("PorchSteps")
	var sc := int(steps.get_meta("step_count")) if steps != null else 0
	var sr := float(steps.get_meta("rise")) if steps != null else 0.0
	var srun := float(steps.get_meta("run")) if steps != null else 0.0
	var sbot := float(steps.get_meta("bottom_y")) if steps != null else 0.0
	var szt := float(steps.get_meta("z_top")) if steps != null else 0.0
	print(TAG, " DIM porch deck_top=%.3f step_count=%d rise=%.3f run=%.3f bottom=%.3f z_top=%.3f" % [
		float(C["deck_top"]), sc, sr, srun, sbot, szt])
	var wf := IsleScaleSpec.size_of("window_front")
	var ws := IsleScaleSpec.size_of("window_side")
	var wb := IsleScaleSpec.size_of("window_back")
	var wa := IsleScaleSpec.size_of("window_attic")
	print(TAG, " DIM windows front=%.2fx%.2f x2 side=%.2fx%.2f back=%.2fx%.2f attic=%.2fx%.2f sill_h=%.2f" % [
		wf.x, wf.y, ws.x, ws.y, wb.x, wb.y, wa.x, wa.y, IsleScaleSpec.WINDOW_SILL_H])

# ============================================================
# 诊断：门廊雨棚区域网格/材质 dump（T2_CANOPY=1 时运行）
# ============================================================
func _canopy_hit(w: Vector3) -> bool:
	return absf(w.x) <= 3.9 and w.y >= 1.9 and w.y <= 3.6 and w.z >= 2.9 and w.z <= 5.7

func _alb_of(mat: Material) -> String:
	if mat is ShaderMaterial:
		return str((mat as ShaderMaterial).get_shader_parameter("albedo"))
	return str(mat)

func _dump_canopy() -> void:
	print(TAG, " CANOPY begin")
	for b in _boxes:
		var bb: AABB = b["aabb"]
		if _canopy_hit(bb.get_center()):
			print(TAG, " CANOPY box name=%s parent=%s kind=%s size=(%.3f,%.3f,%.3f) c=(%.3f,%.3f,%.3f)" % [
				String(b["name"]), String(b["parent"]), String(b["kind"]),
				bb.size.x, bb.size.y, bb.size.z, bb.get_center().x, bb.get_center().y, bb.get_center().z])
	var stack: Array = [_root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh != null:
				_dump_canopy_mi(mi)
		for c in n.get_children():
			stack.append(c)
	print(TAG, " CANOPY end")

func _dump_canopy_mi(mi: MeshInstance3D) -> void:
	var mesh: Mesh = mi.mesh
	var xf := _rel_xf_to_root(mi)
	var path := String(_root.get_path_to(mi))
	if mesh is ArrayMesh:
		var am := mesh as ArrayMesh
		for s in range(am.get_surface_count()):
			var arr := am.surface_get_arrays(s)
			if arr.size() <= Mesh.ARRAY_VERTEX:
				continue
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr.size() > Mesh.ARRAY_NORMAL and arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var cnt := 0
			var mn := Vector3(1e9, 1e9, 1e9)
			var mx := Vector3(-1e9, -1e9, -1e9)
			var navg := Vector3.ZERO
			for i in range(vs.size()):
				var w: Vector3 = xf * vs[i]
				if _canopy_hit(w):
					cnt += 1
					mn = Vector3(minf(mn.x, w.x), minf(mn.y, w.y), minf(mn.z, w.z))
					mx = Vector3(maxf(mx.x, w.x), maxf(mx.y, w.y), maxf(mx.z, w.z))
					if i < nrm.size():
						navg += xf.basis * nrm[i]
			if cnt > 0:
				navg = navg / float(cnt)
				var alb := _alb_of(am.surface_get_material(s))
				print(TAG, " CANOPY surf node=%s s=%d alb=%s verts=%d bbox min=(%.3f,%.3f,%.3f) max=(%.3f,%.3f,%.3f) n=(%.2f,%.2f,%.2f) tris=%d" % [
					path, s, alb, cnt, mn.x, mn.y, mn.z, mx.x, mx.y, mx.z,
					navg.x, navg.y, navg.z, vs.size() / 3])
	else:
		var bb: AABB = mesh.get_aabb()
		var c: Vector3 = xf * bb.get_center()
		if _canopy_hit(c):
			var m0: Material = mi.material_override if mi.material_override != null else (mesh.surface_get_material(0) if mesh.get_surface_count() > 0 else null)
			var alb2 := _alb_of(m0)
			print(TAG, " CANOPY prim node=%s type=%s alb=%s c=(%.3f,%.3f,%.3f) size=(%.3f,%.3f,%.3f)" % [
				path, mesh.get_class(), alb2, c.x, c.y, c.z, bb.size.x, bb.size.y, bb.size.z])

# ============================================================
# 诊断：指定像素射线-三角形命中（T2_RAY="800,430;700,400" 时运行）
# 用于定位截图里异常颜色像素对应的真实网格面。
# ============================================================
func _front_day_camera() -> Dictionary:
	# 与 tools/probe_house_p7v3.gd _section_exterior_day 的 house_front_day 机位一致
	var b: Basis = _root.global_transform.basis
	var t := _world(Vector3(0.0, float(_C["fy"]) + 2.10, 4.30))
	var cam: Vector3 = t + b * Vector3(0.0, 0.0, 1.0) * 13.0 + b * Vector3(1.0, 0.0, 0.0) * 1.2 + Vector3(0.0, 2.2, 0.0)
	var z := (cam - t).normalized()
	var x := Vector3.UP.cross(z).normalized()
	var y := z.cross(x)
	return {"origin": cam, "target": t, "x": x, "y": y, "z": z, "fov": 50.0, "w": 1600.0, "h": 900.0}

func _cam_ray(c: Dictionary, px: float, py: float) -> Vector3:
	var w := float(c["w"])
	var h := float(c["h"])
	var cx: Vector3 = c["x"]
	var cy: Vector3 = c["y"]
	var cz: Vector3 = c["z"]
	var ndx := (px + 0.5) / w * 2.0 - 1.0
	var ndy := 1.0 - (py + 0.5) / h * 2.0
	var tan_half := tan(deg_to_rad(float(c["fov"]) * 0.5))
	var aspect := w / h
	var dir: Vector3 = cx * ndx * tan_half * aspect + cy * ndy * tan_half - cz
	return dir.normalized()

func _mat_alb(m: Material) -> String:
	if m == null:
		return "null"
	if m is ShaderMaterial:
		return str((m as ShaderMaterial).get_shader_parameter("albedo"))
	if m is StandardMaterial3D:
		return str((m as StandardMaterial3D).albedo_color)
	return m.get_class()

func _ray_tri(orig: Vector3, dir: Vector3, v0: Vector3, v1: Vector3, v2: Vector3) -> float:
	var e1 := v1 - v0
	var e2 := v2 - v0
	var p := dir.cross(e2)
	var det := e1.dot(p)
	if absf(det) < 1e-9:
		return -1.0
	var inv := 1.0 / det
	var tv := orig - v0
	var u := tv.dot(p) * inv
	if u < -0.0001 or u > 1.0001:
		return -1.0
	var q := tv.cross(e1)
	var v := dir.dot(q) * inv
	if v < -0.0001 or u + v > 1.0001:
		return -1.0
	var tt := e2.dot(q) * inv
	return tt if tt > 0.001 else -1.0

func _accum_mesh(mesh: Mesh, mat_owner: GeometryInstance3D, xf: Transform3D, orig: Vector3, dir: Vector3, hits: Array, tag: String) -> void:
	var s_n := mesh.get_surface_count()
	for s in range(s_n):
		var arr := mesh.surface_get_arrays(s)
		if arr.size() <= Mesh.ARRAY_VERTEX:
			continue
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nrm: PackedVector3Array = PackedVector3Array()
		if arr.size() > Mesh.ARRAY_NORMAL and arr[Mesh.ARRAY_NORMAL] != null:
			nrm = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = PackedInt32Array()
		if arr.size() > Mesh.ARRAY_INDEX and arr[Mesh.ARRAY_INDEX] != null:
			idx = arr[Mesh.ARRAY_INDEX]
		var tri_n := idx.size() / 3 if idx.size() > 0 else vs.size() / 3
		var mat: Material = mat_owner.material_override
		if mat == null:
			mat = mesh.surface_get_material(s)
		for ti in range(tri_n):
			var i0: int
			var i1: int
			var i2: int
			if idx.size() > 0:
				i0 = idx[ti * 3]
				i1 = idx[ti * 3 + 1]
				i2 = idx[ti * 3 + 2]
			else:
				i0 = ti * 3
				i1 = ti * 3 + 1
				i2 = ti * 3 + 2
			if i2 >= vs.size():
				continue
			var w0: Vector3 = xf * vs[i0]
			var w1: Vector3 = xf * vs[i1]
			var w2: Vector3 = xf * vs[i2]
			var d := _ray_tri(orig, dir, w0, w1, w2)
			if d < 0.0:
				continue
			var gn := (w1 - w0).cross(w2 - w0).normalized()
			var vn := Vector3.ZERO
			if nrm.size() > i2:
				vn = (xf.basis * (nrm[i0] + nrm[i1] + nrm[i2]) / 3.0).normalized()
			var inv_root := _root.global_transform.affine_inverse()
			hits.append({
				"t": d, "node": tag, "s": s, "alb": _mat_alb(mat),
				"p": inv_root * (orig + dir * d),
				"gn": (inv_root.basis * gn).normalized(),
				"vn": (inv_root.basis * vn).normalized(),
			})

func _dump_ray() -> void:
	var c := _front_day_camera()
	var o: Vector3 = c["origin"]
	var tg: Vector3 = c["target"]
	print(TAG, " RAY cam=(%.3f,%.3f,%.3f) target=(%.3f,%.3f,%.3f) fov=%.1f" % [o.x, o.y, o.z, tg.x, tg.y, tg.z, float(c["fov"])])
	var stack: Array = [_root]
	var nodes: Array = []
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is GeometryInstance3D:
			nodes.append(n)
		for ch in n.get_children():
			stack.append(ch)
	var spec := OS.get_environment("T2_RAY")
	for tok in spec.split(";", false):
		var parts := tok.split(",")
		if parts.size() < 2:
			continue
		var px := int(parts[0])
		var py := int(parts[1])
		var dir := _cam_ray(c, float(px), float(py))
		var hits: Array = []
		for nd in nodes:
			var tag := String(_root.get_path_to(nd))
			if nd is MeshInstance3D:
				var mi := nd as MeshInstance3D
				if mi.mesh != null:
					_accum_mesh(mi.mesh, mi, mi.global_transform, o, dir, hits, tag)
			elif nd is MultiMeshInstance3D:
				var mm := nd as MultiMeshInstance3D
				if mm.multimesh != null and mm.multimesh.mesh != null:
					for i in range(mm.multimesh.instance_count):
						var xfi: Transform3D = mm.global_transform * mm.multimesh.get_instance_transform(i)
						_accum_mesh(mm.multimesh.mesh, mm, xfi, o, dir, hits, tag + "#" + str(i))
		hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["t"]) < float(b["t"]))
		print(TAG, " RAY px=%d,%d dir=(%.3f,%.3f,%.3f) hits=%d" % [px, py, dir.x, dir.y, dir.z, hits.size()])
		var shown := 0
		for h in hits:
			if shown >= 8:
				break
			shown += 1
			var hp: Vector3 = h["p"]
			var gn: Vector3 = h["gn"]
			var vn: Vector3 = h["vn"]
			print(TAG, " RAY   #%d t=%.2f node=%s s=%d alb=%s p=(%.3f,%.3f,%.3f) gn=(%.2f,%.2f,%.2f) vn=(%.2f,%.2f,%.2f)" % [
				shown, float(h["t"]), String(h["node"]), int(h["s"]), String(h["alb"]),
				hp.x, hp.y, hp.z, gn.x, gn.y, gn.z, vn.x, vn.y, vn.z])
	print(TAG, " RAY end")
