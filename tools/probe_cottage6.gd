extends SceneTree
# ============================================================================
# tools/probe_cottage6.gd  —  T4/Phase6 verification (headless)
#   1) beam occluders: count / yaw / world center / coverage  (ray-box replicated)
#   2) perches: downward raycast must hit the real roof surface (< 0.08 m gap),
#      world normal.y sane, contract fields kept
#   3) attic glass: independent near-transparent materials, not in window_mats,
#      outside halo removed (window_halos == 5)
#   4) attic interior lights: 2 lights inside the room
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path <project> \
#       --script res://tools/probe_cottage6.gd
# ============================================================================
const Cott = preload("res://scripts/cottage.gd")
const M = preload("res://scripts/isle_math.gd")

var _pass: int = 0
var _fail: int = 0
var _tris: Array = []          # [[a:Vector3,b:Vector3,c:Vector3], ...]  world space
var _root: Node3D = null
var _C: Dictionary = {}
var _boxes: Array = []
var _mmi_skipped: Array = []      # headless 下 MultiMesh 实例变换读不回来 → 跳过并记录节点名
var _roof_mm_rebuilt: int = 0     # 用 cottage 导出的 _roof_cap_data/_roof_tile_data 重建的屋面实例数

func _init() -> void:
	print("==================== [PROBE6] cottage Phase6 ====================")
	var holder := Node3D.new()
	holder.name = "ProbeHolder"
	var t0 := Time.get_ticks_msec()
	var d: Dictionary = Cott.build(holder)
	var ms := Time.get_ticks_msec() - t0
	_root = d["root"]
	_C = _root.get_meta("cottage_ctx")
	_boxes = d["beam_occluders"]
	print("[BUILD] cottage built in %d ms, children=%d, perches=%d, lights=%d" % [
		ms, _root.get_child_count(), d["perches"].size(), d["light_sources"].size()])

	_collect_tris(_root, _root.transform, _root)
	# headless（dummy renderer）下 MultiMesh 实例变换读不回来（get_instance_transform 返回 Identity），
	# 所以 _collect_tris 会跳过所有 MMI；屋面瓦片用 cottage 导出的同一份 _roof_cap_data/_roof_tile_data
	# 重建三角形，保证探针验证的就是实际渲染用的实例几何（而不是复制一份公式）。
	_add_roof_multimesh_tris()
	print("[TRIS] collected %d triangles (world), rebuilt %d roof instances, skipped %d MMI" % [
		_tris.size(), _roof_mm_rebuilt, _mmi_skipped.size()])

	_check_occluders(d)
	_check_occlusion_math(d)
	_check_perches(d)
	_check_attic_glass(d)
	_check_attic_lights(d)
	_check_halos(d)

	holder.free()
	print("[PROBE6] RESULT pass=%d fail=%d -> %s" % [_pass, _fail, "OK" if _fail == 0 else "FAILED"])
	print("==================== [PROBE6] done ====================")
	quit(1 if _fail > 0 else 0)

# 用 cottage 导出的屋面 MultiMesh 数据重建三角形（与 _roof 实际渲染用的 xform/mesh 同一份）。
func _add_roof_multimesh_tris() -> void:
	var cap: Dictionary = Cott._roof_cap_data(_C)
	_add_instanced_mesh(cap["mesh"], cap["xforms"])
	var tile: Dictionary = Cott._roof_tile_data(_C)
	_add_instanced_mesh(tile["mesh"], tile["xforms"])

func _add_instanced_mesh(mesh: Mesh, xforms: Array) -> void:
	for x in xforms:
		_add_mesh_tris(mesh, _root.transform * (x as Transform3D))
		_roof_mm_rebuilt += 1

# ---------- helpers ---------------------------------------------------------
func _ok(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("PASS  " + msg)
	else:
		_fail += 1
		print("FAIL  " + msg)

func _approx(a: float, b: float, eps: float) -> bool:
	return absf(a - b) <= eps

func _w(local: Vector3) -> Vector3:
	return _root.transform * local

func _rot_dir(local_dir: Vector3) -> Vector3:
	return (_root.transform.basis * local_dir).normalized()

# ---------- triangle collection (MeshInstance3D + MultiMeshInstance3D) ------
func _collect_tris(node: Node, xf: Transform3D, owner_node: Node) -> void:
	for c in node.get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			var xc: Transform3D = xf * mi.transform
			if mi.mesh != null:
				_add_mesh_tris(mi.mesh, xc)
		elif c is MultiMeshInstance3D:
			var mmi := c as MultiMeshInstance3D
			var xc2: Transform3D = xf * mmi.transform
			var mm := mmi.multimesh
			if mm != null and mm.mesh != null and mm.instance_count > 0:
				# headless 下实例变换读不回来（Identity）：不能用来做几何，记为跳过。
				var raw0: Transform3D = mm.get_instance_transform(0)
				var lost: bool = mm.instance_count > 1 and raw0.origin.length() < 1e-6 and raw0.basis.is_equal_approx(Basis.IDENTITY)
				if lost:
					_mmi_skipped.append(String(mmi.name))
				else:
					for i in range(mm.instance_count):
						_add_mesh_tris(mm.mesh, xc2 * mm.get_instance_transform(i))
		elif c is Node3D:
			_collect_tris(c, xf * (c as Node3D).transform, owner_node)
		else:
			_collect_tris(c, xf, owner_node)

func _add_mesh_tris(mesh: Mesh, xf: Transform3D) -> void:
	for s in range(mesh.get_surface_count()):
		var arr: Array = mesh.surface_get_arrays(s)
		if arr.size() == 0:
			continue
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		if verts.is_empty():
			continue
		var idx = arr[Mesh.ARRAY_INDEX]
		if idx == null or (idx as PackedInt32Array).is_empty():
			var i := 0
			while i + 2 < verts.size():
				_tris.append([xf * verts[i], xf * verts[i + 1], xf * verts[i + 2]])
				i += 3
		else:
			var pi: PackedInt32Array = idx
			var k := 0
			while k + 2 < pi.size():
				_tris.append([xf * verts[pi[k]], xf * verts[pi[k + 1]], xf * verts[pi[k + 2]]])
				k += 3

# ---------- 1) occluder data ------------------------------------------------
func _box_local(p: Vector3, box: Dictionary) -> Vector3:
	var yaw: float = box["yaw"]
	var cs := cos(-yaw)
	var sn := sin(-yaw)
	var lp: Vector3 = p - (box["center"] as Vector3)
	return Vector3(cs * lp.x - sn * lp.z, lp.y, sn * lp.x + cs * lp.z)

func _inside_box(p: Vector3, box: Dictionary, margin: float = 0.0) -> bool:
	var v := _box_local(p, box)
	var h: Vector3 = box["half"]
	return absf(v.x) <= h.x - margin and absf(v.y) <= h.y - margin and absf(v.z) <= h.z - margin

func _inside_any(p: Vector3) -> bool:
	for b in _boxes:
		if _inside_box(p, b):
			return true
	return false

func _check_occluders(d: Dictionary) -> void:
	print("---- [1] beam occluders ----")
	_ok(_boxes.size() >= 2 and _boxes.size() <= 4, "beam_occluders count=%d (expect 2..4)" % _boxes.size())
	var root_yaw: float = _root.rotation.y
	_ok(_approx(root_yaw, M.HOUSE_YAW, 0.0001), "root.yaw=%.5f == HOUSE_YAW=%.5f" % [root_yaw, M.HOUSE_YAW])
	for i in range(_boxes.size()):
		var b: Dictionary = _boxes[i]
		var yaw: float = b["yaw"]
		var h: Vector3 = b["half"]
		var ctr: Vector3 = b["center"]
		print("[OCC] box%d center=(%.4f, %.4f, %.4f) half=(%.4f, %.4f, %.4f) yaw=%.5f" % [
			i, ctr.x, ctr.y, ctr.z, h.x, h.y, h.z, yaw])
		# shader: p2 = R2d(-yaw)*(p-center)，Godot 绕 Y +a = R2d(-a) → 要得到世界→盒局部必须 yaw = -rotation.y。
		_ok(_approx(yaw, -root_yaw, 1e-4), "box%d yaw == -root.yaw (shader R2d(-yaw) convention)" % i)
		_ok(h.x > 0.0 and h.y > 0.0 and h.z > 0.0, "box%d half all positive" % i)
	# 手动重算：世界 center 必须等于 root.transform * 局部中心（同一坐标架）
	var b0: Dictionary = _boxes[0]
	var expect0 := _w(Vector3(0.0, float(_C["roof_base"]) * 0.5, 0.0))
	_ok(b0["center"].distance_to(expect0) < 1e-4, "box0 center matches root.transform*local (err=%.6f m)" % b0["center"].distance_to(expect0))
	var b1: Dictionary = _boxes[1]
	var roof_top: float = float(_C["ridge_y"]) + 0.30
	var expect1 := _w(Vector3(0.0, (float(_C["roof_base"]) + roof_top) * 0.5, 0.0))
	_ok(b1["center"].distance_to(expect1) < 1e-4, "box1 center matches root.transform*local")
	_ok(b1["half"].x >= float(_C["eave_x"]) - 1e-4, "box1 half.x=%.4f covers eave_x=%.4f" % [b1["half"].x, _C["eave_x"]])
	# get_beam_occluders(root) 与 build 返回值一致
	var api: Array = Cott.get_beam_occluders(_root)
	_ok(api.size() == _boxes.size(), "get_beam_occluders() count=%d == build()" % api.size())
	var same := true
	for i in range(mini(api.size(), _boxes.size())):
		if (api[i]["center"] as Vector3).distance_to(_boxes[i]["center"]) > 1e-4:
			same = false
		if (api[i]["half"] as Vector3).distance_to(_boxes[i]["half"]) > 1e-4:
			same = false
		if not _approx(float(api[i]["yaw"]), float(_boxes[i]["yaw"]), 1e-4):
			same = false
	_ok(same, "get_beam_occluders(root) == build()[\"beam_occluders\"]")
	# 覆盖：小屋实体关键点必须在某个盒内
	var hw: float = _C["hw"]
	var hd: float = _C["hd"]
	var cover_pts := [
		_w(Vector3(-hw, 2.0, 0.0)), _w(Vector3(hw, 2.0, 0.0)),
		_w(Vector3(0.0, 2.0, hd)), _w(Vector3(0.0, 2.0, -hd)),
		_w(Vector3(0.0, 5.6, 0.0)), _w(Vector3(0.0, 8.0, 0.0)),
		_w(Vector3(float(_C["ch_x"]), 9.50, float(_C["ch_z"]))),
	]
	var covered := 0
	for p in cover_pts:
		if _inside_any(p):
			covered += 1
	_ok(covered == cover_pts.size(), "solid coverage: %d/%d wall/roof/chimney points inside boxes" % [covered, cover_pts.size()])
	# 不包住室外空地
	var open_pts := [
		_w(Vector3(0.0, 0.03, 12.2)), _w(Vector3(0.0, 0.03, -12.2)),
		_w(Vector3(9.5, 0.03, 0.0)), _w(Vector3(-9.5, 0.03, 0.0)),
		_w(Vector3(0.0, 11.2, 0.0)), _w(Vector3(0.0, 14.0, 5.0)),
	]
	var leak := 0
	for p in open_pts:
		if _inside_any(p):
			leak += 1
	_ok(leak == 0, "outdoor empty space not enclosed by boxes (%d/6 leaks)" % leak)

# ---------- 2) occlusion math (replicating toon.gdshader) -------------------
func _smoothstep(e0: float, e1: float, x: float) -> float:
	var t := clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func _occl(p: Vector3, n: Vector3, lamp_pos: Vector3) -> float:
	var ro: Vector3 = p + n * 0.06
	var rd: Vector3 = (lamp_pos - ro).normalized()
	var occl := 1.0
	for b in _boxes:
		var yaw: float = b["yaw"]
		var cs := cos(-yaw)
		var sn := sin(-yaw)
		var lp: Vector3 = ro - (b["center"] as Vector3)
		var p2 := Vector3(cs * lp.x - sn * lp.z, lp.y, sn * lp.x + cs * lp.z)
		var d2 := Vector3(cs * rd.x - sn * rd.z, rd.y, sn * rd.x + cs * rd.z)
		var h: Vector3 = b["half"]
		var tn := -INF
		var tf := INF
		var hit := true
		for a in range(3):
			var dv: float = d2[a]
			var pv: float = p2[a]
			var hv: float = h[a]
			if absf(dv) < 1e-6:
				if absf(pv) > hv:
					hit = false
					break
			else:
				var t1: float = (-hv - pv) / dv
				var t2: float = (hv - pv) / dv
				if t1 > t2:
					var tt := t1
					t1 = t2
					t2 = tt
				tn = maxf(tn, t1)
				tf = minf(tf, t2)
		if hit and tf >= tn and tf > 0.0:
			var stay: float = tf - maxf(tn, 0.0)
			occl = minf(occl, 1.0 - _smoothstep(0.20, 1.20, stay) * 0.94)
	return occl

func _check_occlusion_math(d: Dictionary) -> void:
	print("---- [2] occlusion math (shader-replicated) ----")
	var house := _w(Vector3.ZERO)
	var lamp_a := Vector3(-17.0, 22.0, 9.0)                     # 真实灯塔灯位近似
	var off := lamp_a - house
	var lamp_b := house - Vector3(off.x, 0.0, off.z)            # 镜像（光束扫过另一侧）
	lamp_b.y = lamp_a.y
	var lamp_c := _w(Vector3(-12.0, 22.0, 14.0))                # 正面偏左的灯位（扫过正面山墙）
	var hw: float = _C["hw"]
	var hd: float = _C["hd"]
	# 法线：world = root.basis * local
	var nL := _rot_dir(Vector3(-1.0, 0.0, 0.0))
	var nR := _rot_dir(Vector3(1.0, 0.0, 0.0))
	var nF := _rot_dir(Vector3(0.0, 0.0, 1.0))
	var nB := _rot_dir(Vector3(0.0, 0.0, -1.0))
	var pL := _w(Vector3(-hw, 2.0, 0.0))
	var pR := _w(Vector3(hw, 2.0, 0.0))
	var pF := _w(Vector3(0.0, 2.0, hd))
	var pB := _w(Vector3(0.0, 2.0, -hd))
	var pGable := _w(Vector3(0.0, 8.0, hd))       # 正面山墙/阁楼窗面
	var pRidge := _w(Vector3(0.0, float(_C["ridge_y"]) + 0.32, 0.0))
	var pYardF := _w(Vector3(0.0, 0.03, 12.2))    # 屋前空地
	var lamp_local: Vector3 = _root.transform.affine_inverse() * lamp_a
	var hl := Vector3(lamp_local.x, 0.0, lamp_local.z).normalized()
	var pBehind := _w(Vector3(-hl.x * 10.0, 0.03, -hl.z * 10.0))  # 屋子在地灯连线上更远侧的地面
	var pAtticIn := _w(Vector3(0.55, 6.84, 2.85))
	var pRoomIn := _w(Vector3(0.50, 2.20, 0.40))
	var up := Vector3.UP

	var rows := [
		["LA left wall   (near)", _occl(pL, nL, lamp_a), true],
		["LA right wall  (far)",  _occl(pR, nR, lamp_a), false],
		["LA back wall",           _occl(pB, nB, lamp_a), false],
		["LA front wall",          _occl(pF, nF, lamp_a), false],
		["LA front yard  (open)",  _occl(pYardF, up, lamp_a), true],
		["LA ground behind house", _occl(pBehind, up, lamp_a), false],
		["LA attic interior",      _occl(pAtticIn, up, lamp_a), false],
		["LA room interior",       _occl(pRoomIn, up, lamp_a), false],
		["LA ridge cap top",       _occl(pRidge, up, lamp_a), true],
		["LB right wall  (near)",  _occl(pR, nR, lamp_b), true],
		["LB left wall   (far)",   _occl(pL, nL, lamp_b), false],
		["LC front gable (near)",  _occl(pGable, nF, lamp_c), true],
		["LC back wall   (far)",   _occl(pB, nB, lamp_c), false],
		["LC left wall   (near)",  _occl(pL, nL, lamp_c), true],
		["LC right wall  (far)",   _occl(pR, nR, lamp_c), false],
	]
	var bad := 0
	for row in rows:
		var name: String = row[0]
		var v: float = row[1]
		var want_lit: bool = row[2]
		var okv: bool = (v > 0.90) if want_lit else (v < 0.20)
		if not okv:
			bad += 1
		print("[OCCL] %-24s occl=%.3f  expect=%s  %s" % [name, v, "lit" if want_lit else "shadowed", "ok" if okv else "BAD"])
	_ok(bad == 0, "beam occlusion behaviour: %d/%d probes as expected" % [rows.size() - bad, rows.size()])

# ---------- 3) perches ------------------------------------------------------
func _ray_down_hit(p: Vector3) -> Dictionary:
	var from := p + Vector3(0.0, 1.2, 0.0)
	var to := p + Vector3(0.0, -4.0, 0.0)
	var best_y := -INF
	var best_pt := Vector3.ZERO
	var best_n := Vector3.UP
	var best_gap := INF
	var offs := [Vector3.ZERO, Vector3(0.010, 0, 0), Vector3(-0.010, 0, 0), Vector3(0, 0, 0.010), Vector3(0, 0, -0.010)]
	for o in offs:
		var f: Vector3 = from + o
		var t: Vector3 = to + o
		for tri in _tris:
			# 预筛用三角形 3 顶点的包围盒与射线竖直柱相交（不能用首个顶点：大屋面板/大盒子的首顶点离
			# 落点可能 >1m，会把真正命中的三角形误跳过）。
			var a: Vector3 = tri[0]
			var b: Vector3 = tri[1]
			var c2: Vector3 = tri[2]
			if minf(a.x, minf(b.x, c2.x)) > p.x + 0.30 or maxf(a.x, maxf(b.x, c2.x)) < p.x - 0.30:
				continue
			if minf(a.z, minf(b.z, c2.z)) > p.z + 0.30 or maxf(a.z, maxf(b.z, c2.z)) < p.z - 0.30:
				continue
			if minf(a.y, minf(b.y, c2.y)) > p.y + 0.10 or maxf(a.y, maxf(b.y, c2.y)) < p.y - 1.00:
				continue
			var hit = Geometry3D.segment_intersects_triangle(f, t, tri[0], tri[1], tri[2])
			if hit == null:
				continue
			var hp: Vector3 = hit
			var n: Vector3 = (tri[1] as Vector3 - tri[0] as Vector3).cross(tri[2] as Vector3 - tri[0] as Vector3)
			if n.length() < 1e-8:
				continue
			n = n.normalized()
			if n.y < 0.0:
				n = -n
			var gap: float = p.y - hp.y
			if gap > -0.01 and gap < 0.30 and gap < best_gap:
				# 注意：这里不能 break。同一落点竖直柱会依次扫到更远的顶面（如烟囱顶板 gap=0.24）
				# 和更近的真实表面（小石盒顶 gap=0.03），必须先扫完所有三角形再取最近命中。
				best_gap = gap
				best_y = hp.y
				best_pt = hp
				best_n = n
		if best_gap < INF:
			break
	return {"hit": best_gap < INF, "gap": best_gap, "pt": best_pt, "n": best_n}

func _check_perches(d: Dictionary) -> void:
	print("---- [3] roof perches ----")
	var perches: Array = d["perches"]
	_ok(perches.size() == 10, "perch count=%d (expect 10: ridge3+eave4+chimney1+porch2)" % perches.size())
	var kinds := {}
	for p in perches:
		var k: String = p["kind"]
		kinds[k] = int(kinds.get(k, 0)) + 1
	_ok(int(kinds.get("ridge", 0)) == 3 and int(kinds.get("eave", 0)) == 4 and int(kinds.get("chimney", 0)) == 1 and int(kinds.get("porch_beam", 0)) == 2,
		"perch kinds=%s" % str(kinds))
	var bad := 0
	var ridge_pos := 0
	for p in perches:
		var pid: String = p["id"]
		var pos: Vector3 = p["pos"]
		var nrm: Vector3 = p["normal"]
		var slope: float = p["slope"]
		var radius: float = p["radius"]
		var facing: Vector3 = p["facing"]
		var res := _ray_down_hit(pos)
		var gap: float = res["gap"]
		var hit_n: Vector3 = res["n"]
		var gap_ok: bool = res["hit"] and gap >= 0.012 and gap <= 0.080
		var n_ok: bool = nrm.y >= 0.35 and facing.length() > 0.9 and radius > 0.0
		var hitn_ok: bool = (not res["hit"]) or hit_n.y >= 0.45
		if not (gap_ok and n_ok and hitn_ok):
			bad += 1
		if pid.begins_with("ridge"):
			ridge_pos += 1
		print("[PERCH] %-12s pos=(%.4f, %.4f, %.4f) normal.y=%.3f slope=%.3f radius=%.2f hit=%s gap=%.4f hit_n.y=%.3f %s" % [
			pid, pos.x, pos.y, pos.z, nrm.y, slope, radius, str(res["hit"]), gap, hit_n.y,
			"ok" if (gap_ok and n_ok and hitn_ok) else "BAD"])
	_ok(bad == 0, "perches standing on real roof surface (gap 0.012..0.080 m): %d/%d ok" % [perches.size() - bad, perches.size()])
	_ok(ridge_pos == 3, "ridge perches present")

# ---------- 4) attic glass -------------------------------------------------
func _shader_path(mat: Material) -> String:
	if mat is ShaderMaterial:
		var sm := mat as ShaderMaterial
		if sm.shader != null:
			return sm.shader.resource_path
	return ""

func _collect_nodes_named(node: Node, out: Array, name_sub: String) -> void:
	if node.name.to_lower().contains(name_sub):
		out.append(node)
	for c in node.get_children():
		_collect_nodes_named(c, out, name_sub)

func _collect_glass_meshes(node: Node, mat: Material, out: Array) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.material_override == mat:
			out.append(mi)
	for c in node.get_children():
		_collect_glass_meshes(c, mat, out)

func _check_attic_glass(d: Dictionary) -> void:
	print("---- [4] attic glass ----")
	var mats: Array = d["attic_glass_mats"]
	_ok(mats.size() == 2, "attic_glass_mats count=%d" % mats.size())
	var outer: ShaderMaterial = mats[0]
	var inner: ShaderMaterial = mats[1]
	var p := _shader_path(outer) + " | " + _shader_path(inner)
	print("[GLASS] shader=%s" % p)
	_ok(_shader_path(outer).contains("glass") and _shader_path(inner).contains("glass"), "attic materials use glass.gdshader")
	var wm: Array = d["window_mats"]
	var wm_has := false
	for m in wm:
		if m == outer or m == inner:
			wm_has = true
	_ok(wm.size() == 1 and not wm_has, "attic glass NOT in window_mats (main night glow won't hit it); window_mats=%d" % wm.size())
	var op_o: float = outer.get_shader_parameter("opacity")
	var op_i: float = inner.get_shader_parameter("opacity")
	var rg_o: float = outer.get_shader_parameter("reflection_gain")
	var rg_i: float = inner.get_shader_parameter("reflection_gain")
	var f0_o: float = outer.get_shader_parameter("fresnel_f0")
	var gl_o: float = outer.get_shader_parameter("glow")
	var gl_i: float = inner.get_shader_parameter("glow")
	print("[GLASS] outer opacity=%.3f f0=%.3f refl=%.2f glow=%.2f | inner opacity=%.3f refl=%.2f glow=%.2f" % [
		op_o, f0_o, rg_o, gl_o, op_i, rg_i, gl_i])
	_ok(op_o <= 0.020 and op_i <= 0.020, "opacity low (outer %.3f / inner %.3f <= 0.020)" % [op_o, op_i])
	_ok(rg_o <= 0.40 and rg_i <= 0.40, "reflection_gain low (outer %.2f / inner %.2f)" % [rg_o, rg_i])
	_ok(gl_o == 0.0 and gl_i == 0.0, "independent glass has zero glow parameter")
	# 找 AtticWindow 节点与两片玻璃网格
	var attics: Array = []
	_collect_nodes_named(_root, attics, "atticwindow")
	_ok(attics.size() >= 1, "AtticWindow node found (%d)" % attics.size())
	var outer_meshes: Array = []
	var inner_meshes: Array = []
	_collect_glass_meshes(_root, outer, outer_meshes)
	_collect_glass_meshes(_root, inner, inner_meshes)
	_ok(outer_meshes.size() == 1 and inner_meshes.size() == 1, "attic panes: outer=%d inner=%d" % [outer_meshes.size(), inner_meshes.size()])
	# 估算法线入射 alpha（shader: f_s=f0+front_sheen*(1-f_s); alpha=f_s+absorb*(1-f_s)）
	for nm in [["outer", outer], ["inner", inner]]:
		var sm: ShaderMaterial = nm[1]
		var f0: float = sm.get_shader_parameter("fresnel_f0")
		var sh: float = sm.get_shader_parameter("front_sheen")
		var absorb: float = clampf(float(sm.get_shader_parameter("opacity")), 0.0, 0.92)
		var fs: float = clampf(f0 + sh * (1.0 - f0), 0.0, 1.0)
		var alpha: float = clampf(fs + absorb * (1.0 - fs), 0.02, 0.97)
		print("[GLASS] %s head-on alpha=%.4f -> two-pane transmission=%.3f" % [
			nm[0], alpha, (1.0 - alpha) * (1.0 - alpha)])
	# 窗框仍在（Atlas: 窗套/窗棂 mesh 数量）
	if attics.size() > 0:
		var aw: Node = attics[0]
		print("[GLASS] AtticWindow children=%d (frames/muntins kept)" % aw.get_child_count())

# ---------- 5) attic interior lights ---------------------------------------
func _check_attic_lights(d: Dictionary) -> void:
	print("---- [5] attic interior lights ----")
	var lights: Array = d["light_sources"]
	var inv: Transform3D = _root.transform.affine_inverse()
	var attic_hw: float = _C["attic_hw"]
	var found := 0
	for L in lights:
		var pos: Vector3 = L["pos"]
		var lp: Vector3 = inv * pos
		var is_in: bool = absf(lp.x) < attic_hw and absf(lp.z) < 4.02 and lp.y > 5.70 and lp.y < 8.30
		if is_in:
			found += 1
			print("[LIGHT] attic light local=(%.2f, %.2f, %.2f) intensity=%.2f range=%.2f color=%s" % [
				lp.x, lp.y, lp.z, float(L["intensity"]), float(L["range"]), str(L["color"])])
	_ok(found == 2, "2 attic interior lights in light_sources (found %d)" % found)
	print("[LIGHT] total light_sources=%d (was 9: +1 attic light)" % lights.size())
	# 灯到外墙的最小距离（不泄漏）
	var min_edge := INF
	for L in lights:
		var lp: Vector3 = inv * (L["pos"] as Vector3)
		if absf(lp.x) < attic_hw and absf(lp.z) < 4.02 and lp.y > 5.70 and lp.y < 8.30:
			var edge: float = 4.02 - absf(lp.z)
			if edge < min_edge:
				min_edge = edge
	print("[LIGHT] min distance of attic lights to front wall plane = %.2f m" % min_edge)

# ---------- 6) halos -------------------------------------------------------
func _check_halos(d: Dictionary) -> void:
	print("---- [6] window halos ----")
	var halos: Array = d["window_halos"]
	_ok(halos.size() == 5, "window_halos count=%d (was 6; attic outer halo removed)" % halos.size())
	var quads: Array = []
	_collect_quads(_root, quads)
	print("[HALO] quad meshes under Cottage=%d" % quads.size())
	var bad := 0
	for q in quads:
		var mi := q as MeshInstance3D
		var lp: Vector3 = mi.position
		var qm: QuadMesh = mi.mesh
		var size: float = qm.size.x
		# 阁楼窗外大光晕位置：local (0, 7.0, hd+0.55=4.75)
		if lp.z > 4.40 and absf(lp.x) < 2.0 and lp.y > 5.0 and lp.y < 9.0:
			bad += 1
			print("[HALO] BAD attic outer halo at local=(%.2f, %.2f, %.2f) size=%.2f" % [lp.x, lp.y, lp.z, size])
	_ok(bad == 0, "no ADD halo outside attic window (bad=%d)" % bad)
	# 普通窗 5 个 halo 仍保留且不落在阁楼窗外
	print("[HALO] window halo positions:")
	for h in halos:
		var mi2 := h as MeshInstance3D
		if mi2 != null:
			print("        local=(%.2f, %.2f, %.2f) size=%.2f" % [mi2.position.x, mi2.position.y, mi2.position.z, (mi2.mesh as QuadMesh).size.x])

func _collect_quads(node: Node, out: Array) -> void:
	for c in node.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh is QuadMesh:
			var mi := c as MeshInstance3D
			if mi.material_override != null and _shader_path(mi.material_override) == "":
				out.append(mi)
		_collect_quads(c, out)
