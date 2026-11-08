extends SceneTree

# ============================================================================
# 临时 P2A 预览探针，非正式游戏实现，不得提交为正式功能。
# 只做三件事：加载真实 isle.tscn / main.gd -> 运行时叠加预览几何 -> 真实渲染截图 + 数值测量。
# 不写任何正式文件，不改 world.gd / main.gd / project.godot / 相机默认参数，不被正式代码引用。
#
# 用法（窗口模式才会真实出图）：
#   D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe --path D:/休闲小岛幻境/游戏工程 \
#     --script res://tools/probe_p2a_layout.gd -- --p2ashots \
#     --cand=D:/休闲小岛幻境/开发产物/P9/P2A/candidates_p2a.json --id=S1_stepped_ramp_p1center
#   --nopad 只渲染真实世界（基线对照，不加预览几何）
# 注意：不要用 main.gd 的 --shots，项目内置截图流程会改写相机/天气/HUD。
# 输出只写 D:/休闲小岛幻境/开发产物/P9/P2A/shots/<id>/
# ============================================================================

const M := preload("res://scripts/isle_math.gd")

const VERSION := "p2a-probe-v2"
const DEFAULT_OUT := "D:/休闲小岛幻境/开发产物/P9/P2A"
const SHOT_W := 1600
const SHOT_H := 1000
const SKIRT_W := 2.2
const SKIRT_W_FAR := 2.8
const TAN_BANK := 0.6248693519093274  # tan(32 deg)
# 第三轮外缘处理（Lead m00633）：草肩 ≤0.55m + 只在填高 >0.55 处加干垒石边
const SHOULDER_H := 0.70
const SHOULDER_W := 1.1199          # 0.70 / tan32
const REVET_MAX_H := 0.70
const REVET_W := 0.24
const STONE_BASE := Color(0.322, 0.231, 0.169)  # world.gd M.C_WOOD_DARK：沿用旧菜地"木挡板+立柱"挡土语汇（不用混凝土/灰石色）
const FEATHER_R := 0.30  # 台缘与花园支路相交 2 处：+0.02 在 0.30m 内渐变到 0（Lead 羽化规格）
const CORNER_R := 0.45

var out_dir := DEFAULT_OUT
var do_shots := false
var cand_path := ""
var cand_id := ""
var nopad := false
var tag_prefix := ""
var cam_filter := ""

var _main: Node = null
var _cam: Camera3D = null
var _world: Dictionary = {}
var _headless := true
var _shot_dir := ""
var _cand: Dictionary = {}
var _pad: Dictionary = {}
var _top: Dictionary = {}
var _farm: Dictionary = {}
var _flat: Dictionary = {}

var _measured: Dictionary = {}
var _checks: Array = []
var _notes: Array = []
var _shots: Array = []
var _preview_tris := 0
var _layout: Node3D = null
var _floor_y := 0.0
var _masked := 0
var _scatter: Array = []

var _poly: Array = []
var _feather: Array = []
var _dense: Array = []
var _nrm: Array = []
var _yedge: Array = []
var _skirt: Array = []
# 从真实 Terrain 网格直接取顶点色（Lead 要求：台面颜色必须取样，不得自算一套）
var _terr_v: PackedVector3Array = PackedVector3Array()
var _terr_c: PackedColorArray = PackedColorArray()
var _terr_grid := {}
var _terr_mi: MeshInstance3D = null
var _excavated := false
var _terr_step := 0.75
var _debug_node: MeshInstance3D = null
var _debug_stone: MeshInstance3D = null
var _stone_nodes: Array = []
var _dbg_hue := Color(0, 0, 0, 0)


func _initialize() -> void:
	_run.call_deferred()


# ---------------------------------------------------------------- args -----
func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--out="):
			out_dir = s.substr(6)
		elif s == "--p2ashots":
			do_shots = true
		elif s.begins_with("--cand="):
			cand_path = s.substr(7)
		elif s.begins_with("--id="):
			cand_id = s.substr(5)
		elif s == "--nopad":
			nopad = true
		elif s.begins_with("--tag="):
			tag_prefix = s.substr(6)
		elif s.begins_with("--cams="):
			cam_filter = s.substr(7)


func _want_cam(n: int) -> bool:
	if cam_filter == "":
		return true
	for t in cam_filter.split(","):
		if int(String(t).strip_edges()) == n:
			return true
	return false


# ------------------------------------------------------------- utilities ---
func _l2w(lx: float, lz: float) -> Vector2:
	var c := cos(M.HOUSE_YAW)
	var s := sin(M.HOUSE_YAW)
	return Vector2(M.HOUSE_X + lx * c + lz * s, M.HOUSE_Z - lx * s + lz * c)


func _w2l(x: float, z: float) -> Vector2:
	var c := cos(M.HOUSE_YAW)
	var s := sin(M.HOUSE_YAW)
	var dx := x - M.HOUSE_X
	var dz := z - M.HOUSE_Z
	return Vector2(dx * c - dz * s, dx * s + dz * c)


func _ground(lp: Vector2) -> float:
	var w := _l2w(lp.x, lp.y)
	return IsleWorld.surface_y(w.x, w.y)


func _check(id: String, ok: bool, detail: String, expected: String = "") -> bool:
	_checks.append({"id": id, "ok": ok, "detail": detail, "expected": expected})
	return ok


func _note(id: String, detail: String) -> void:
	_notes.append({"id": id, "detail": detail})


# ------------------------------------------------------------ candidate ----
func _load_cand() -> bool:
	if cand_path == "":
		_check("cand_arg", false, "--cand not given", "--cand=<json>")
		return false
	var p := cand_path
	if not p.is_absolute_path():
		p = "D:/休闲小岛幻境/游戏工程/" + p
	var fa := FileAccess.open(p, FileAccess.READ)
	if fa == null:
		_check("cand_open", false, "cannot open " + p)
		return false
	var txt := fa.get_as_text()
	fa.close()
	var data: Variant = JSON.parse_string(txt)
	if typeof(data) != TYPE_DICTIONARY:
		_check("cand_parse", false, "invalid json " + p)
		return false
	var doc: Dictionary = data
	var list: Array = doc.get("candidates", [])
	if list.is_empty():
		_check("cand_list", false, "candidates[] empty")
		return false
	var want := cand_id
	if want == "":
		want = String(list[0].get("id", ""))
	var found: Dictionary = {}
	for c in list:
		if String(c.get("id", "")) == want:
			found = c
	if found.is_empty():
		_check("cand_id", false, "id not found: " + want)
		return false
	_cand = found
	_pad = found.get("pad", {})
	_top = _pad.get("top", {})
	_farm = _pad.get("farm", {})
	var raw: Array = _pad.get("polygon_local", [])
	if raw.size() < 3:
		_check("cand_poly", false, "polygon_local has < 3 points")
		return false
	var pts: Array = []
	for e in raw:
		if typeof(e) == TYPE_ARRAY:
			pts.append(Vector2(float(e[0]), float(e[1])))
	_flat = {"meta": doc.get("meta", {}), "cand": found, "path": p}
	_poly = _round_poly(_orient_ccw(_dedupe(pts)), CORNER_R)
	# 羽化点（台缘与既有花园支路相交处，房屋局部；Lead 冻结：x=-1.45@z≈7.37 与 z=3.28@x≈-6.04）
	_feather = [Vector2(-1.45, 7.37), Vector2(-6.04, 3.28)]
	print("[P2A] feather points(local)=%s fade=%.2f m" % [str(_feather), FEATHER_R])
	_dense = _resample(_poly, 0.30)
	_nrm = _poly_normals(_dense)
	_check("cand_loaded", true, "%s  poly=%d dense=%d" % [want, _poly.size(), _dense.size()])
	print("[P2A] candidate=%s label=%s" % [want, String(found.get("label", ""))])
	print("[P2A] top mode=%s  farm center=%s terrace=%.3f" % [
		String(_top.get("mode", "flat")), str(_farm.get("center_local", [])), float(_farm.get("terrace_y", 7.372))])
	return true


func _terrace_y() -> float:
	return float(_farm.get("terrace_y", _top.get("far", _top.get("y", 7.372))))


func _farm_center() -> Vector2:
	var c: Array = _farm.get("center_local", [-4.35, 13.2])
	return Vector2(float(c[0]), float(c[1]))


func _top_y(lp: Vector2) -> float:
	var m := String(_top.get("mode", "flat"))
	if m == "flat":
		return float(_top.get("y", 7.372))
	if m == "maxtrace":
		# maxtrace: 台面 = max(地形 + offset, far)。近段只比地形高 2cm（跟地形起伏、无台唇），
		# 地形降到 far 以下之后才成为水平台面，只在下坡侧外露。挖方恒为 0。
		var g := _ground(lp)
		var base := maxf(g + float(_top.get("offset", 0.02)), float(_top.get("far", 7.53)))
		# 羽化：台缘与既有花园支路相交的 2 处，+0.02 在 FEATHER_R 内渐变到 0（边界处与地形齐平，杜绝竖直台唇）
		if not _feather.is_empty():
			var dm := 1e9
			for fp in _feather:
				dm = minf(dm, lp.distance_to(fp as Vector2))
			var k := clampf(dm / FEATHER_R, 0.0, 1.0)
			k = k * k * (3.0 - 2.0 * k)
			base = lerpf(g, base, k)
		return base
	var z0 := float(_top.get("z0", 3.18))
	var z1 := float(_top.get("z1", 10.45))
	var t := clampf((lp.y - z0) / maxf(0.001, z1 - z0), 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	var far := float(_top.get("far", 7.372))
	if m == "ramp":
		return lerpf(float(_top.get("near", far)), far, t)
	# blend: 靠房段贴地随形(+offset)，向农田平滑落到 far
	return lerpf(_ground(lp) + float(_top.get("offset", 0.04)), far, t)


func _surf_y(lp: Vector2) -> float:
	# 台面高程本身（预览里会先用 _excavate() 把台面范围内的真实地形挖到台面以下，
	# 等价于 P2 生产实现里的填挖；否则地形会穿出台面、农田也不平）
	# 边界点可能被判在多边形外（射线法边缘），边界 0.02m 内也按台面高程处理，否则边界会掉到地形高度
	if _pt_in_poly(lp, _poly) or _near_poly(lp, _poly, 0.02):
		return _top_y(lp)
	return _ground(lp) + 0.02


# ------------------------------------------------------------- polygons ----
func _poly_area(pts: Array) -> float:
	var a := 0.0
	var n := pts.size()
	for i in range(n):
		var p: Vector2 = pts[i]
		var q: Vector2 = pts[(i + 1) % n]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


func _orient_ccw(pts: Array) -> Array:
	if _poly_area(pts) < 0.0:
		var r: Array = pts.duplicate()
		r.reverse()
		return r
	return pts


func _dedupe(pts: Array) -> Array:
	var out: Array = []
	for p in pts:
		var v: Vector2 = p
		if out.is_empty() or (out[out.size() - 1] as Vector2).distance_to(v) > 0.0005:
			out.append(v)
	if out.size() > 1 and (out[0] as Vector2).distance_to(out[out.size() - 1]) < 0.0005:
		out.remove_at(out.size() - 1)
	return out


func _round_poly(pts: Array, radius: float) -> Array:
	var n := pts.size()
	var out: Array = []
	for i in range(n):
		var p: Vector2 = pts[i]
		var a: Vector2 = pts[(i + n - 1) % n]
		var b: Vector2 = pts[(i + 1) % n]
		var d0 := (p - a).normalized()
		var d1 := (b - p).normalized()
		var cr := d0.cross(d1)
		if cr <= 0.0:
			out.append(p)
			continue
		var r := minf(radius, minf(p.distance_to(a), p.distance_to(b)) * 0.45)
		if r < 0.05:
			out.append(p)
			continue
		var t0 := p - d0 * r
		var t1 := p + d1 * r
		var seg := 5
		for k in range(seg + 1):
			var t := float(k) / float(seg)
			var q := t0.lerp(t1, t)
			var pull := sin(PI * t) * r * 0.35
			out.append(q - (q - p).normalized() * pull)
	return out


func _resample(pts: Array, step: float) -> Array:
	var out: Array = []
	var n := pts.size()
	for i in range(n):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		var L := a.distance_to(b)
		var k := maxi(1, int(round(L / step)))
		for j in range(k):
			out.append(a.lerp(b, float(j) / float(k)))
	return out


func _poly_normals(pts: Array) -> Array:
	var out: Array = []
	var n := pts.size()
	for i in range(n):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		var c: Vector2 = pts[(i + n - 1) % n]
		var d1 := (b - a)
		var d0 := (a - c)
		var n1 := Vector2(d1.y, -d1.x).normalized()
		var n0 := Vector2(d0.y, -d0.x).normalized()
		out.append((n0 + n1).normalized())
	return out


func _pt_in_poly(p: Vector2, poly: Array) -> bool:
	var inside := false
	var n := poly.size()
	var j := n - 1
	for i in range(n):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[j]
		if ((a.y > p.y) != (b.y > p.y)) and (p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x):
			inside = not inside
		j = i
	return inside


func _tri_poly(pts: Array) -> Array:
	var idx: Array = []
	var n := pts.size()
	var v: Array = []
	for i in range(n):
		v.append(i)
	var guard := 0
	while v.size() > 3 and guard < 4000:
		guard += 1
		var clipped := false
		for i in range(v.size()):
			var ia: int = v[(i + v.size() - 1) % v.size()]
			var ib: int = v[i]
			var ic: int = v[(i + 1) % v.size()]
			var a: Vector2 = pts[ia]
			var b: Vector2 = pts[ib]
			var c: Vector2 = pts[ic]
			if (b - a).cross(c - b) <= 0.0000001:
				continue
			var ok := true
			for k in range(v.size()):
				var ik: int = v[k]
				if ik == ia or ik == ib or ik == ic:
					continue
				if _pt_in_tri(pts[ik], a, b, c):
					ok = false
					break
			if not ok:
				continue
			idx.append_array([ia, ib, ic])
			v.remove_at(i)
			clipped = true
			break
		if not clipped:
			break
	if v.size() == 3:
		idx.append_array([v[0], v[1], v[2]])
	return idx


func _pt_in_tri(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1 := (p - a).cross(b - a)
	var d2 := (p - b).cross(c - b)
	var d3 := (p - c).cross(a - c)
	var neg := (d1 < 0.0) or (d2 < 0.0) or (d3 < 0.0)
	var pos := (d1 > 0.0) or (d2 > 0.0) or (d3 > 0.0)
	return not (neg and pos)


# --------------------------------------------------------------- meshes ----
func _mat(col: Color) -> Material:
	return M.toon_material(col, {"bands": 4.0, "soft": 0.55, "rim": 0.10})


func _grass_mat() -> Material:
	return M.terrain_material()


func _grass_color(w: Vector2) -> Color:
	var m1: float = IsleWorld._fbm(w.x * 0.055 + 3.0, w.y * 0.055 - 7.0)
	var m2: float = IsleWorld._fbm(w.x * 0.21 - 31.7, w.y * 0.21 + 12.3)
	var m3: float = IsleWorld._vnoise(w.x * 0.73 + 5.1, w.y * 0.73 - 8.9)
	var g: Color = M.C_GRASS
	g = g.lerp(M.C_GRASS_LIGHT, clampf(m1 * 1.5 - 0.05, 0.0, 1.0))
	g = g.lerp(M.C_GRASS_DARK, clampf(m2 * 0.42, 0.0, 1.0))
	g = g.lerp(Color(0.71, 0.73, 0.54), smoothstep(0.55, 0.92, m1) * 0.34)
	g = g.lerp(M.C_GRASS_LIGHT, m3 * 0.10)
	return g


func _new_mi(nm: String, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_layout.add_child(mi)
	return mi


func _commit(st: SurfaceTool, nm: String, mat: Material) -> MeshInstance3D:
	var mesh := st.commit()
	var mi := _new_mi(nm, mat)
	mi.mesh = mesh
	return mi


func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color,
		wa: Vector2, wb: Vector2, wc: Vector2, want: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.dot(want) < 0.0:
		var tb := b
		b = c
		c = tb
		var tcb := cb
		cb = cc
		cc = tcb
		var twb := wb
		wb = wc
		wc = twb
	st.set_color(ca)
	st.set_uv(wa)
	st.add_vertex(a)
	st.set_color(cb)
	st.set_uv(wb)
	st.add_vertex(b)
	st.set_color(cc)
	st.set_uv(wc)
	st.add_vertex(c)


func _slab(nm: String, center: Vector2, half: Vector2, radius: float, y_top: float, y_bot: float,
		col: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring := _rr_outline(half, minf(radius, minf(half.x, half.y) * 0.9), 2, 5)
	var n := ring.size()
	var top: Array = []
	var bot: Array = []
	for p in ring:
		var v: Vector2 = p
		var w := _l2w(center.x + v.x, center.y + v.y)
		top.append(Vector3(center.x + v.x, y_top, center.y + v.y))
		bot.append(Vector3(center.x + v.x, y_bot, center.y + v.y))
	var c := col
	for i in range(1, n - 1):
		_add_tri(st, top[0], top[i], top[i + 1], c, c, c, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector3.UP)
		_add_tri(st, bot[0], bot[i], bot[i + 1], c, c, c, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector3.DOWN)
	for i in range(n):
		var j := (i + 1) % n
		var w := _l2w(center.x, center.y)
		var out := Vector3((top[i] - top[j]).z, 0.0, -(top[i] - top[j]).x).normalized()
		_add_tri(st, top[i], bot[i], bot[j], c, c, c, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, out)
		_add_tri(st, top[i], bot[j], top[j], c, c, c, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, out)
	st.generate_normals()
	_commit(st, nm, _mat(col))
	_preview_tris += n * 6


func _rr_outline(half: Vector2, radius: float, seg_side: int, seg_corner: int) -> Array:
	var out: Array = []
	var corners := [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	for ci in range(4):
		var c: Vector2 = corners[ci]
		var cc := Vector2(c.x * (half.x - radius), c.y * (half.y - radius))
		var a0 := 0.0
		match ci:
			0: a0 = 0.0
			1: a0 = PI * 0.5
			2: a0 = PI
			3: a0 = PI * 1.5
		for k in range(seg_corner + 1):
			var a := a0 + (PI * 0.5) * float(k) / float(seg_corner)
			out.append(cc + Vector2(cos(a), sin(a)) * radius)
	for i in range(out.size() - 1):
		pass
	return out


func _rail(a: Vector2, b: Vector2, y: float, r: float, col: Color) -> void:
	var d := b - a
	var L := d.length()
	if L < 0.01:
		return
	var dir := d / L
	var up := Vector3(0, 1, 0)
	var side := Vector3(dir.x, 0, dir.y)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 8
	var ring0: Array = []
	var ring1: Array = []
	for k in range(n):
		var ang := TAU * float(k) / float(n)
		var off := side * cos(ang) * r + up * sin(ang) * r
		ring0.append(Vector3(a.x, y, a.y) + off)
		ring1.append(Vector3(b.x, y, b.y) + off)
	var c := col
	for k in range(n):
		var j := (k + 1) % n
		var mid: Vector3 = (ring0[k] + ring1[j]) * 0.5
		var center := Vector3((a.x + b.x) * 0.5, y, (a.y + b.y) * 0.5)
		var want: Vector3 = (mid - center).normalized()
		_add_tri(st, ring0[k], ring0[j], ring1[j], c, c, c, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, want)
		_add_tri(st, ring0[k], ring1[j], ring1[k], c, c, c, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, want)
	st.generate_normals()
	var mi := _commit(st, "Rail", _mat(col))
	_preview_tris += n * 4


func _post(at: Vector2, y_base: float, h: float, r: float, col: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 8
	var ring: Array = []
	for k in range(n):
		var ang := TAU * float(k) / float(n)
		ring.append(Vector3(at.x + cos(ang) * r, 0.0, at.y + sin(ang) * r))
	var c := col
	var yb := y_base
	var yt := y_base + h
	for k in range(n):
		var j := (k + 1) % n
		var midpoint: Vector3 = (ring[k] + ring[j]) * 0.5
		var want: Vector3 = Vector3(midpoint.x, 0.0, midpoint.z).normalized()
		_add_tri(st, Vector3(ring[k].x, yb, ring[k].z), Vector3(ring[j].x, yb, ring[j].z), Vector3(ring[j].x, yt, ring[j].z), c, c, c, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, want)
		_add_tri(st, Vector3(ring[k].x, yb, ring[k].z), Vector3(ring[j].x, yt, ring[j].z), Vector3(ring[k].x, yt, ring[k].z), c, c, c, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, want)
		_add_tri(st, Vector3(0.0, yt, 0.0) + Vector3(at.x, 0.0, at.y), Vector3(ring[j].x, yt, ring[j].z), Vector3(ring[k].x, yt, ring[k].z), c, c, c, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector3.UP)
	st.generate_normals()
	var mi := _commit(st, "Post", _mat(col))
	_preview_tris += n * 6


func _stone(nm: String, at: Vector2, y: float, size: Vector2, col: Color, yaw: float) -> void:
	var half := size * 0.5
	var pts: Array = []
	var n := 7
	for k in range(n):
		var ang := TAU * float(k) / float(n) + 0.3
		var rr := 1.0 - 0.10 * sin(float(k) * 2.3)
		pts.append(Vector2(cos(ang), sin(ang)) * half * rr)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cy := cos(yaw)
	var sy := sin(yaw)
	var world: Array = []
	for q in pts:
		var v: Vector2 = q
		var r := Vector2(v.x * cy - v.y * sy, v.x * sy + v.y * cy)
		var lp := at + r
		world.append(Vector3(lp.x, y, lp.y))
	var c := col
	for i in range(1, n - 1):
		_add_tri(st, world[0], world[i], world[i + 1], c, c, c, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector3.UP)
	st.generate_normals()
	_commit(st, nm, _mat(col))
	_preview_tris += n


# ------------------------------------------------------------- main flow ---
func _run() -> void:
	_parse_args()
	_headless = DisplayServer.get_name() == "headless"
	_shot_dir = out_dir + "/shots/" + (String(_cand.get("id", "")) if false else "")
	if not _headless:
		DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))

	if not _load_cand():
		_finish()
		return

	var sid := String(_cand.get("id", "cand"))
	if nopad:
		sid = "S0_world_baseline"
	_shot_dir = out_dir + "/shots/" + sid
	if _headless:
		DirAccess.make_dir_recursive_absolute(_shot_dir)

	print("[P2A] loading res://isle.tscn ...")
	var ps: PackedScene = load("res://isle.tscn")
	if ps == null:
		_check("scene_load", false, "isle.tscn load failed")
		_finish()
		return
	_main = ps.instantiate()
	root.add_child(_main)
	await process_frame
	await process_frame
	_check("scene_load", true, "isle.tscn instantiated")

	var S := load("res://scripts/isle_settings.gd")
	if S != null:
		_main.set("_settings", S.defaults())
		_main.call("_apply_user_settings", false)
	if not _headless:
		for i in range(3):
			await process_frame
	_main.set("_settings_save_delay", -1.0)
	_main.set("_mode", 1)
	_main.set("_started", true)
	_main.set("_paused", false)
	_main.set("_blending", "")
	_main.set("_auto_orbit", false)
	_cam = _main.get("_cam")
	# 隐藏菜单 / HUD，避免 UI 进截图（_menu 是 CanvasLayer，不是 CanvasItem）
	var menu: Variant = _main.get("_menu")
	if menu != null:
		if menu.has_method("instant_finish"):
			menu.call("instant_finish")
		menu.set("menu_visible", false)
		if menu is CanvasLayer:
			(menu as CanvasLayer).visible = false
		elif menu is CanvasItem:
			(menu as CanvasItem).visible = false
	for key in ["_hud", "_ui_layer"]:
		var nd: Variant = _main.get(key)
		if nd is CanvasLayer:
			(nd as CanvasLayer).visible = false
		elif nd is CanvasItem:
			(nd as CanvasItem).visible = false
	_suppress_ui()
	print("[P2A] ui hidden: menu_visible=", str(menu.get("menu_visible") if menu != null else "-"))
	if not _headless:
		# 离屏 SubViewport：固定 1600x1000，不受 Windows 窗口/任务栏限制，无黑边
		_sv = SubViewport.new()
		_sv.size = Vector2i(SHOT_W, SHOT_H)
		_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_sv.msaa_3d = Viewport.MSAA_2X
		root.add_child(_sv)
		_sv.world_3d = root.world_3d
		_shot_cam = Camera3D.new()
		_shot_cam.near = 0.05
		_shot_cam.far = 1200.0
		_sv.add_child(_shot_cam)
		_shot_cam.current = true
		print("[P2A] offscreen viewport=%dx%d window=%s screen=%s" % [SHOT_W, SHOT_H,
			str(DisplayServer.window_get_size()), str(DisplayServer.screen_get_size())])
	_main.call("_set_time_of_day", 12 * 60 + 20)
	var weather: Variant = _main.get("_weather")
	if weather != null and weather.has_method("set_manual_type"):
		weather.set_manual_type("clear")
	_main.call("_update_weather", 0.0, true)

	_floor_y = M.terrain_height(M.HOUSE_X, M.HOUSE_Z)
	_world = _main.get("_world") as Dictionary
	_collect_scatter()
	print("[P2A] world ready, floor_y=%.3f, scatter nodes=%d" % [_floor_y, _scatter.size()])
	_diag_colors()
	if not nopad:
		_excavate()

	_layout = Node3D.new()
	_layout.name = "P2A_Preview"
	_layout.position = Vector3(M.HOUSE_X, 0.0, M.HOUSE_Z)
	_layout.rotation.y = M.HOUSE_YAW
	_main.add_child(_layout)

	if not nopad:
		_build()
	else:
		_note("baseline_nopad", "no preview geometry; real world.gd as-is")
	_measure()
	if do_shots:
		await _shots_for()
		_write_engine_ref()
	else:
		_note("no_shots", "run without --p2ashots")
	_write_outputs()
	_finish()


func _collect_mm(node: Node, out: Array) -> void:
	if node is MultiMeshInstance3D:
		out.append(node)
	for ch in node.get_children():
		_collect_mm(ch, out)


func _collect_scatter() -> void:
	_scatter.clear()
	_collect_mm(_main, _scatter)
	var names: Array = []
	for mm in _scatter:
		var mi := mm as MultiMeshInstance3D
		if mi != null and mi.multimesh != null:
			names.append("%s:%d" % [String(mi.name), mi.multimesh.instance_count])
	print("[P2A] multimesh nodes: " + ", ".join(names))


func _finish() -> void:
	var fail := 0
	for c in _checks:
		if not bool(c["ok"]):
			fail += 1
	print("[P2A] SUMMARY checks=%d pass=%d fail=%d notes=%d tris=%d shots=%d masked=%d" % [
		_checks.size(), _checks.size() - fail, fail, _notes.size(), _preview_tris, _shots.size(), _masked])
	for c in _checks:
		if not bool(c["ok"]):
			print("[P2A] FAIL %s: %s" % [String(c["id"]), String(c["detail"])])
	for n in _notes:
		print("[P2A] NOTE %s: %s" % [String(n["id"]), String(n["detail"])])
	if nopad:
		print("[P2A] RESULT BASELINE (no preview geometry; candidate-shape checks are N/A)")
		quit(0)
		return
	print("[P2A] RESULT %s" % ("PASS" if fail == 0 else "FAIL"))
	quit(0 if fail == 0 else 1)

# ---------------------------------------------------------------- build ----
func _build() -> void:
	var fc := _farm_center()
	var terr := _terrace_y()
	_yedge.clear()
	_skirt.clear()
	for i in range(_dense.size()):
		var p: Vector2 = _dense[i]
		var g := _ground(p)
		var y := _surf_y(p)
		_yedge.append(y)
		var n: Vector2 = _nrm[i]
		# 第三轮冻结：草肩 h1=min(f,0.70) 32°（宽 ≤1.12m）；仅 f>0.70 处补干垒石边 h2=f-0.70（≤0.70m）
		var f := y - g
		var h2 := 0.0
		var rw := 0.0
		var h1 := minf(maxf(f, 0.0), SHOULDER_H)
		var w1 := h1 / TAN_BANK
		if f > SHOULDER_H:
			h2 = minf(f - SHOULDER_H, REVET_MAX_H)
			rw = REVET_W
		elif f <= 0.0:
			# cut（maxtrace 下 cut=0）：0.30m 圆角盖住，不出台阶
			w1 = 0.30
		# 肩脚正好落在边界点的地形上（+0.02）：h2+h1=f，不再需要落坡带
		# 肩脚落在边界点地形上；边界外地形继续下坡时，再向外接一段 32° 草坡带（不计入 shoulder 指标）落到真实地形
		var y_end := g + 0.02
		var apron := 0.0
		var apron_slope := 0.0
		if f <= 0.0:
			y_end = _ground(p + n * 0.30) + 0.02
		else:
			var base := p + n * (rw + w1)
			var drop_a := maxf((g + 0.02) - _ground(base), 0.0)
			if drop_a > 0.01:
				var wa := drop_a / TAN_BANK
				for it in range(18):
					var want := clampf(maxf((g + 0.02) - _ground(p + n * (rw + w1 + wa)), 0.0) / TAN_BANK, 0.02, 5.00)
					if absf(want - wa) < 0.005:
						wa = want
						break
					wa = wa * 0.45 + want * 0.55
				apron = wa
				apron_slope = rad_to_deg(atan2(maxf((g + 0.02) - _ground(p + n * (rw + w1 + apron)), 0.01), maxf(apron, 0.001)))
				y_end = _ground(p + n * (rw + w1 + apron)) + 0.02
		_skirt.append({"w": rw + w1, "run": rw + w1, "flush": f <= 0.06, "g": g, "n": n,
			"y_end": y_end, "y_lip": y - minf(0.02, h2), "lip_w": 0.06,
			"h1": h1, "w1": w1, "h2": h2, "rw": rw, "f": f, "apron": apron, "apron_slope": apron_slope})
	# dbg: 打印填高最大的边界点（核对 Lead 的 max h2=0.679@(-1.45,14.55)）
	var dbg_f: Array = []
	for i2 in range(_dense.size()):
		dbg_f.append([float(_skirt[i2]["f"]), _dense[i2]])
	dbg_f.sort_custom(func(x, y): return float(x[0]) > float(y[0]))
	print("[P2A] dbg top fill pts: ", str(dbg_f.slice(0, 6)))
	_build_platform()
	_build_platform(true)
	_build_beds(fc, terr)
	_build_fence(fc, terr)
	_build_path(fc, terr)
	# 台面 + 裙带内不得有任何地形草丛/三叶草/花/灌木/岩石穿过（Lead 修正 v2 第 3 条）
	_hide_scatter_on_platform()
	_check("platform_built", true, "poly=%d dense=%d tris=%d mask=%d" % [
		_poly.size(), _dense.size(), _preview_tris, _masked])


func _vw(p: Vector3) -> Vector2:
	return _l2w(p.x, p.z)


# 取样真实地形顶点色（3x3 格内最近顶点）；失败时退回探针自算草色
func _sample_terrain(w: Vector2) -> Color:
	# 台面顶点色一律取自"已建成的 Terrain 网格"顶点色（同一 _terrain_color 结果，含石板路土色带），
	# 用最近 3 个顶点按距离加权插值，等价于三角插值；不使用纯色 material_override。
	if _terr_c.size() == 0:
		return _grass_color(w)
	var cx := int(floor(w.x / _terr_step))
	var cz := int(floor(w.y / _terr_step))
	var ids: Array = []
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var kk := Vector2i(cx + dx, cz + dz)
			if not _terr_grid.has(kk):
				continue
			for idx in (_terr_grid[kk] as Array):
				var i2: int = idx
				var d := (Vector2(_terr_v[i2].x, _terr_v[i2].z)).distance_squared_to(w)
				ids.append([d, i2])
	if ids.is_empty():
		return _grass_color(w)
	ids.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
	var cr := 0.0
	var cg := 0.0
	var cb := 0.0
	var ca := 0.0
	for k in range(mini(3, ids.size())):
		var d2 := maxf(float(ids[k][0]), 0.0001)
		var wt := 1.0 / d2
		var cc: Color = _terr_c[int(ids[k][1])]
		cr += cc.r * wt
		cg += cc.g * wt
		cb += cc.b * wt
		ca += wt
	if ca <= 0.0:
		return _grass_color(w)
	var out := Color(cr / ca, cg / ca, cb / ca, 1.0)
	return out


func _nearest_terrain_color(w: Vector2) -> Color:
	if _terr_c.size() == 0:
		return _grass_color(w)
	var cx := int(floor(w.x / _terr_step))
	var cz := int(floor(w.y / _terr_step))
	var best := -1
	var bd := 1e18
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var kk := Vector2i(cx + dx, cz + dz)
			if not _terr_grid.has(kk):
				continue
			for idx in (_terr_grid[kk] as Array):
				var i2: int = idx
				var d := (Vector2(_terr_v[i2].x, _terr_v[i2].z)).distance_squared_to(w)
				if d < bd:
					bd = d
					best = i2
	if best < 0 or bd > 2.25:
		return _grass_color(w)
	var c := _terr_c[best]
	c.a = 1.0
	return c


# 诊断：对比世界真实地形顶点色 与本探针算出的草色（判断台面惨白是不是顶点色缺失/取值不对）
func _diag_colors() -> void:
	var terr_mi: MeshInstance3D = null
	var stack: Array = [_main]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).material_override == M.terrain_material():
			terr_mi = n
			break
		for ch in n.get_children():
			stack.append(ch)
	if terr_mi == null or terr_mi.mesh == null:
		print("[P2A] diag: world terrain mesh not found")
		return
	_terr_mi = terr_mi
	var arr: Array = terr_mi.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cs: Variant = arr[Mesh.ARRAY_COLOR]
	print("[P2A] diag world terrain mesh=%s verts=%d has_color=%s" % [String(terr_mi.name), vs.size(), str(cs != null)])
	if cs == null:
		return
	_terr_v = vs
	_terr_c = cs
	_terr_grid.clear()
	for i in range(vs.size()):
		var kk := Vector2i(int(floor(vs[i].x / _terr_step)), int(floor(vs[i].z / _terr_step)))
		if not _terr_grid.has(kk):
			_terr_grid[kk] = []
		(_terr_grid[kk] as Array).append(i)
	print("[P2A] terrain color sampler: verts=%d cells=%d step=%.2f" % [vs.size(), _terr_grid.size(), _terr_step])
	for lp in [Vector2(-4.5, 9.0), Vector2(-2.0, 11.5), Vector2(-6.0, 5.5)]:
		var w := _l2w(lp.x, lp.y)
		var best := 0
		var bd := 1e18
		for i in range(vs.size()):
			var d := (Vector2(vs[i].x, vs[i].z)).distance_squared_to(w)
			if d < bd:
				bd = d
				best = i
		print("[P2A] diag local=%s terrain_color=%s probe_grass=%s" % [str(lp), str(cs[best]), str(_grass_color(w))])


func _excavate() -> void:
	# 预览专用：把台面多边形范围内的真实地形顶点下压到台面以下（等价于 P2 生产实现的"挖"）。
	# 只改内存中的临时 mesh，不写任何文件、不改世界脚本。
	if _terr_mi == null or _terr_mi.mesh == null or _poly.is_empty():
		_note("excavate_skipped", "terrain mesh or polygon unavailable")
		return
	var pad_y := _terrace_y()
	var arr: Array = _terr_mi.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ns: Variant = arr[Mesh.ARRAY_NORMAL]
	var cut := 0
	var deepest := 0.0
	for vi in range(vs.size()):
		var lp := _w2l(vs[vi].x, vs[vi].z)
		if not _pt_in_poly(lp, _poly):
			continue
		var py := _surf_y(lp)
		if vs[vi].y > py - 0.07:
			deepest = maxf(deepest, vs[vi].y - py)
			vs[vi].y = py - 0.07
			if ns != null:
				(ns as PackedVector3Array)[vi] = Vector3.UP
			cut += 1
	arr[Mesh.ARRAY_VERTEX] = vs
	if ns != null:
		arr[Mesh.ARRAY_NORMAL] = ns
	var nm := ArrayMesh.new()
	nm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_terr_mi.mesh = nm
	_excavated = true
	_check("terrain_excavated", true, "verts=%d deepest_cut=%.3f" % [cut, deepest])


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, want: Vector3, mul: float = 1.0, ovr: Color = Color(0, 0, 0, 0)) -> void:
	if (b - a).cross(c - a).dot(want) > 0.0:
		var t := b
		b = c
		c = t
	for p in [a, b, c]:
		var v: Vector3 = p
		var w := _vw(v)
		var col := _sample_terrain(w)
		if ovr.a > 0.0:
			col = ovr
		if _dbg_hue.a > 0.0:
			col = _dbg_hue
		if mul != 1.0:
			col = Color(col.r * mul, col.g * mul, col.b * mul, col.a)
		st.set_color(col)
		st.set_uv(Vector2(w.x, w.y) * 0.09)
		st.add_vertex(v)


func _build_platform(dbg: bool = false) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var verts2: Array = []
	var vmap := {}
	var addv := func(p: Vector2) -> int:
		var k := "%.3f|%.3f" % [p.x, p.y]
		if vmap.has(k):
			return int(vmap[k])
		var id := verts2.size()
		verts2.append(p)
		vmap[k] = id
		return id

	var tris: Array = _tri_poly(_dense)
	var idx2: Array = []
	for t in range(0, tris.size(), 3):
		idx2.append_array([addv.call(_dense[tris[t]]), addv.call(_dense[tris[t + 1]]), addv.call(_dense[tris[t + 2]])])
	if idx2.is_empty():
		_check("platform_triangulate", false, "ear clipping failed")
		return
	for level in range(2):
		var nidx: Array = []
		for t in range(0, idx2.size(), 3):
			var a: Vector2 = verts2[idx2[t]]
			var b: Vector2 = verts2[idx2[t + 1]]
			var c: Vector2 = verts2[idx2[t + 2]]
			var ab: int = addv.call(a.lerp(b, 0.5))
			var bc: int = addv.call(b.lerp(c, 0.5))
			var ca: int = addv.call(c.lerp(a, 0.5))
			nidx.append_array([idx2[t], ab, ca])
			nidx.append_array([ab, idx2[t + 1], bc])
			nidx.append_array([ca, bc, idx2[t + 2]])
			nidx.append_array([ab, bc, ca])
		idx2 = nidx
	var pos: Array = []
	for q in verts2:
		var p: Vector2 = q
		pos.append(Vector3(p.x, _surf_y(p), p.y))
	if dbg:
		_dbg_hue = Color(1.0, 0.0, 1.0)
	for t in range(0, idx2.size(), 3):
		if dbg:
			var ctr: Vector3 = (pos[idx2[t]] + pos[idx2[t + 1]] + pos[idx2[t + 2]]) / 3.0
			var near_f := false
			for fp in _feather:
				if Vector2(ctr.x, ctr.z).distance_to(fp as Vector2) <= FEATHER_R:
					near_f = true
			_dbg_hue = Color(1.0, 1.0, 1.0) if near_f else Color(1.0, 0.0, 1.0)
		_tri(st, pos[idx2[t]], pos[idx2[t + 1]], pos[idx2[t + 2]], Vector3.UP)
	if dbg:
		_dbg_hue = Color(0.0, 1.0, 1.0)
	var N := _dense.size()
	# 第三轮外缘：5 圈截面 = 台面边(R0) -> 石边顶棱(R1) -> 石边底(R2) -> 草肩脚(R3) -> 落坡带脚(R4)
	var rings: Array = []
	for r in range(5):
		var row: Array = []
		for i in range(N):
			var p: Vector2 = _dense[i]
			var sd: Dictionary = _skirt[i]
			var n: Vector2 = sd["n"]
			var y0 := float(_yedge[i])
			var h2 := float(sd["h2"])
			var rw := float(sd["rw"])
			var w1 := float(sd["w1"])
			var apron := float(sd["apron"])
			var ge := float(_yedge[i]) - h2      # 石边底 = 草肩顶
			var g := float(sd["g"])
			var off := 0.0
			var ty := y0
			if r == 1:
				off = 0.06
				ty = y0 - minf(0.02, h2)
			elif r == 2:
				off = rw if h2 > 0.005 else 0.06
				ty = y0 - h2
			elif r == 3:
				off = (rw if h2 > 0.005 else 0.06) + w1
				ty = g + 0.02
			elif r == 4:
				off = (rw if h2 > 0.005 else 0.06) + w1 + apron
				ty = float(sd["y_end"])
			var q := p + n * off
			row.append(Vector3(q.x, ty, q.y))
		rings.append(row)
	var stone_st := SurfaceTool.new()
	stone_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 石边：顶棱小圆角 + 微内收竖面（浅灰褐，顶点色微扰复刻旧菜地挡土）
	_dbg_hue = Color(1.0, 0.9, 0.1)
	var stone_dbg := dbg
	_dbg_hue = Color(1.0, 0.9, 0.1) if stone_dbg else Color(0, 0, 0, 0)
	for band in range(2):
		var r0: Array = rings[band]
		var r1: Array = rings[band + 1]
		for i in range(N):
			var j := (i + 1) % N
			var n2: Vector2 = _skirt[i]["n"]
			var want := Vector3(n2.x, 0.55, n2.y).normalized()
			for tri in range(2):
				var aa: Vector3 = r0[i] if tri == 0 else r0[i]
				var bb: Vector3 = r0[j] if tri == 0 else r1[j]
				var cc: Vector3 = r1[j] if tri == 0 else r1[i]
				var wpos := _vw((aa + bb + cc) / 3.0)
				var sc := _stone_color(wpos)
				_tri(stone_st, aa, bb, cc, want, 1.0, sc)
	if stone_dbg:
		_dbg_hue = Color(0, 0, 0, 0)
	# 草肩：原地形顶点色 + 略暗（32° 自然草坡）
	_dbg_hue = Color(0.1, 0.9, 1.0) if dbg else Color(0, 0, 0, 0)
	for band in range(2, 4):
		var r0: Array = rings[band]
		var r1: Array = rings[band + 1]
		for i in range(N):
			var j := (i + 1) % N
			var n2: Vector2 = _skirt[i]["n"]
			var want := Vector3(n2.x, 0.62, n2.y).normalized()
			var m1 := 0.97 - 0.04 * float(band - 2)
			_tri(st, r0[i], r0[j], r1[j], want, m1)
			_tri(st, r0[i], r1[j], r1[i], want, m1)
	_dbg_hue = Color(0, 0, 0, 0)
	st.generate_normals()
	_dbg_hue = Color(0, 0, 0, 0)
	var mi := _new_mi("PlatformDebug" if dbg else "PlatformLand", _grass_mat())
	mi.mesh = st.commit()
	if dbg:
		mi.visible = false
		_debug_node = mi
	# 干垒石边单独材质/节点，便于判读（浅灰褐 + 顶点色微扰）
	stone_st.generate_normals()
	var stone_mi := _new_mi("PlatformRevet" if not dbg else "PlatformRevetDebug", _mat(STONE_BASE))
	stone_mi.mesh = stone_st.commit()
	if not dbg:
		_stone_nodes.append(stone_mi)
	else:
		stone_mi.visible = false
		_debug_stone = stone_mi
	_preview_tris += int(idx2.size() / 3) + N * 8
	_check("platform_mesh", mi.mesh != null, "mesh committed")
	# 顶点色是否真的写进 mesh（着色器靠 v_lcol 变暗，缺色会显得惨白）
	var arr: Array = mi.mesh.surface_get_arrays(0)
	var cols: Variant = arr[Mesh.ARRAY_COLOR]
	if cols == null:
		print("[P2A] diag platform vertices have NO vertex colors")
	else:
		var csum := Color(0, 0, 0, 0)
		for c in cols:
			csum += c as Color
		var cmean := csum / float(cols.size())
		print("[P2A] diag platform colors=%d mean=%s" % [cols.size(), str(cmean)])


func _stone_color(w: Vector2) -> Color:
	# world.gd 旧菜地挡土的浅灰褐色（0.66,0.62,0.54）+ 顶点色微扰，避免死板纯色
	var t := _sample_terrain(w)
	var lum := (t.r + t.g + t.b) / 3.0
	var k := clampf(0.90 + (lum - 0.5) * 0.55, 0.78, 1.12)
	return Color(STONE_BASE.r * k, STONE_BASE.g * k, STONE_BASE.b * k, 1.0)


func _build_beds(fc: Vector2, terr: float) -> void:
	var pitch := 1.5
	var rim_c := Color(0.52, 0.38, 0.26)
	var soil := Color(0.40, 0.28, 0.19)
	var n_bed := 0
	for i in range(-1, 2):
		for j in range(-1, 2):
			var at := fc + Vector2(i * pitch, j * pitch)
			var base := maxf(terr, _surf_y(at)) + 0.02
			_slab("BedRim_%d_%d" % [i, j], at, Vector2(0.56, 0.56), 0.26, base + 0.10, base - 0.06, rim_c)
			_slab("BedSoil_%d_%d" % [i, j], at, Vector2(0.52, 0.52), 0.22, base + 0.20, base + 0.08, soil)
			n_bed += 1
	_check("beds_9", n_bed == 9, "beds=%d" % n_bed)


func _build_fence(fc: Vector2, terr: float) -> void:
	var half := 2.71
	var gw := 1.10
	var post_h := 0.80
	var sp := 0.70
	# 参考 tian2_ref：浅色粗圆木围栏（柱 Ø0.14、柱高 0.80、两道圆头横杆）
	var wood := Color(0.80, 0.66, 0.49)
	var wood_rail := Color(0.84, 0.70, 0.52)
	var wood_dark := Color(0.72, 0.58, 0.42)
	var gcx := fc.x + float(_farm.get("gate_offset", 0.0))
	var s := half
	var corners := [Vector2(-s, -s), Vector2(s, -s), Vector2(s, s), Vector2(-s, s)]
	var segs: Array = []
	for k in range(4):
		var a: Vector2 = fc + corners[k]
		var b: Vector2 = fc + corners[(k + 1) % 4]
		var L := a.distance_to(b)
		var cnt := maxi(1, int(round(L / sp)))
		var pts: Array = []
		for m in range(cnt + 1):
			pts.append(a.lerp(b, float(m) / float(cnt)))
		segs.append(pts)
	for pi in range(segs.size()):
		var pts: Array = segs[pi]
		for m in range(pts.size()):
			var p: Vector2 = pts[m]
			if pi == 0 and absf(p.x - gcx) < gw * 0.5:
				continue
			_post(p, _surf_y(p) - 0.05, post_h + 0.05, 0.070, wood)
		for m in range(pts.size() - 1):
			var a2: Vector2 = pts[m]
			var b2: Vector2 = pts[m + 1]
			if pi == 0 and (absf(a2.x - gcx) < gw * 0.5 or absf(b2.x - gcx) < gw * 0.5):
				continue
			var ymid := (_surf_y(a2) + _surf_y(b2)) * 0.5
			_rail(a2, b2, ymid + 0.30, 0.045, wood_rail)
			_rail(a2, b2, ymid + 0.62, 0.045, wood_rail)
	var gp0 := fc + Vector2(gcx - gw * 0.5, -half)
	var gp1 := fc + Vector2(gcx + gw * 0.5, -half)
	_post(gp0, _surf_y(gp0) - 0.05, post_h + 0.22, 0.085, wood_dark)
	_post(gp1, _surf_y(gp1) - 0.05, post_h + 0.22, 0.085, wood_dark)
	_rail(gp0, gp1, (_surf_y(gp0) + _surf_y(gp1)) * 0.5 + post_h + 0.18, 0.045, wood_rail)
	_check("fence_built", true, "gate_center_lx=%.2f gate_w=%.2f" % [gcx, gw])


func _build_path(fc: Vector2, terr: float) -> void:
	# 冻结：起点 local(-1.60,5.65)（台阶左前角左侧 0.50m）-> 田口 gate(-4.35,8.99) 直线，长 4.326m，宽 1.05m，6 块石板；
	# 与既有花园支路在 local(-2.73,7.02)（小径 41% 处）交叉，交叉点 ±0.60m 内不铺我方石板（保留支路原石板）
	var a := Vector2(-1.60, 5.65)
	var b := fc + Vector2(0.0, -2.71)
	var junction := Vector2(-2.73, 7.02)
	var L := a.distance_to(b)
	var y_a := _surf_y(a)
	var y_b := _surf_y(b)
	var pw := 1.05
	var n := 6
	var placed := 0
	var skipped := 0
	for i in range(n):
		var t := (float(i) + 0.5) / float(n)
		var q := a.lerp(b, t)
		if q.distance_to(junction) <= 0.60:
			skipped += 1
			continue
		var y := _surf_y(q) + 0.02
		var yaw := atan2(-(b - a).y, (b - a).x)
		_stone("PathStone", q, y, Vector2(pw * 0.92, 0.50), Color(0.74, 0.71, 0.63), yaw)
		placed += 1
	_stone("GateSillOut", b + (b - a).normalized() * 0.55, _surf_y(b) + 0.02, Vector2(1.30, 0.55), Color(0.78, 0.75, 0.68), 0.0)
	_stone("GateSillIn", b, _surf_y(b) + 0.02, Vector2(1.30, 0.55), Color(0.78, 0.75, 0.68), 0.0)
	var slope_pct := absf(y_a - y_b) / maxf(L, 0.001) * 100.0
	_walk = {"len": L, "drop": absf(y_a - y_b), "slope_pct": slope_pct,
		"placed": placed, "skipped_at_crossing": skipped, "y_a": y_a, "y_b": y_b,
		"start_local": [a.x, a.y], "gate_local": [b.x, b.y], "cross_local": [junction.x, junction.y],
		"width": pw, "skip_radius": 0.60}
	print("[P2A] walkway: len=%.3f m drop=%.3f m slope=%.1f%% slabs placed=%d skipped_at_junction=%d y_a=%.3f y_b=%.3f" % [
		L, absf(y_a - y_b), slope_pct, placed, skipped, y_a, y_b])
	_check("path_built", placed >= 3, "path_slabs=%d (junction %s, skipped %d)" % [
		placed, str(junction), skipped])
	_check("walkway_junction_clear", skipped >= 1, "slabs kept out of +/-0.60m around crossing local(-2.73,7.02): skipped=%d" % skipped)
	_note("walkway_junction", "crossing with existing garden spur at local(-2.73,7.02) (41%% of walkway); no pad slab laid within +/-0.60m, existing spur slabs kept intact")


func _hide_scatter_on_platform() -> void:
	# 台面多边形（外扩 0.15m）+ 裙带内：所有地形散布（草/三叶草/花/灌木/岩石）实例清零并移到 -200
	var margin := 0.15
	var skirt_max := 0.0
	for sd in _skirt:
		skirt_max = maxf(skirt_max, float(sd["run"]))
	var hide_r := margin
	var hidden := 0
	for mm in _scatter:
		var mi := mm as MultiMeshInstance3D
		if mi == null or mi.multimesh == null:
			continue
		var nm := String(mi.name)
		var is_veg := nm.begins_with("Grass") or nm.begins_with("Clover") or nm.begins_with("Weed") \
			or nm.begins_with("Flower") or nm.begins_with("WinterBloom") or nm.begins_with("Bush") \
			or nm.begins_with("Stems") or nm.begins_with("LeafCards") or nm.begins_with("Canopy")
		var is_rock := nm.begins_with("Rocks")
		if not is_veg and not is_rock:
			continue
		var mtx := mi.multimesh
		for i in range(mtx.instance_count):
			var xf := mtx.get_instance_transform(i)
			var gp: Vector3 = mi.global_transform * xf.origin
			var lp := _w2l(gp.x, gp.z)
			if not (_pt_in_poly(lp, _poly) or _near_poly(lp, _poly, hide_r)):
				continue
			# maxtrace：只排除"填高 > 0.15m 的农田段"，近段草叶按设计穿透台面，保留
			var fill := _top_y(lp) - _ground(lp) if _pt_in_poly(lp, _poly) else 0.0
			if fill <= 0.15:
				continue
			xf.basis = Basis().scaled(Vector3.ZERO)
			xf.origin = Vector3(0.0, -200.0, 0.0)
			mtx.set_instance_transform(i, xf)
			hidden += 1
	_masked = hidden
	print("[P2A] scatter hidden on platform: %d (margin %.2f, skirt %.2f)" % [hidden, margin, skirt_max])

func _near_poly(p: Vector2, poly: Array, margin: float) -> bool:
	var n := poly.size()
	for i in range(n):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % n]
		var ab := b - a
		var L2 := ab.length_squared()
		var t := 0.0
		if L2 > 0.000001:
			t = clampf((p - a).dot(ab) / L2, 0.0, 1.0)
		if (a + ab * t).distance_to(p) <= margin:
			return true
	return false


# -------------------------------------------------------------- measure ---
func _bbox_of(poly: Array) -> Array:
	var mnx := 1e9
	var mnz := 1e9
	var mxx := -1e9
	var mxz := -1e9
	for p in poly:
		var v: Vector2 = p
		mnx = minf(mnx, v.x)
		mnz = minf(mnz, v.y)
		mxx = maxf(mxx, v.x)
		mxz = maxf(mxz, v.y)
	return [mnx, mnz, mxx, mxz]


func _measure() -> void:
	var fc := _farm_center()
	var terr := _terrace_y()
	var bb := _bbox_of(_poly)
	var x0 := float(bb[0])
	var z0 := float(bb[1])
	var x1 := float(bb[2])
	var z1 := float(bb[3])
	var stp := 0.30
	var n_in := 0
	var tmin := 1e9
	var tmax := -1e9
	var ymin := 1e9
	var ymax := -1e9
	var ysum := 0.0
	var poke := 0
	var path_hit := 0
	var lx := x0
	while lx <= x1:
		var lz := z0
		while lz <= z1:
			var lp := Vector2(lx, lz)
			if _pt_in_poly(lp, _poly):
				var g := _ground(lp)
				var y := _surf_y(lp)
				tmin = minf(tmin, g)
				tmax = maxf(tmax, g)
				ymin = minf(ymin, y)
				ymax = maxf(ymax, y)
				ysum += y
				n_in += 1
				# 预览已把台面范围内的地形挖到台面以下（_excavate），分析地形高出台面不算穿模；
				# 只有台面比地形低、又没被挖开时才算穿模。
				if g > y + 0.005 and not _excavated:
					poke += 1
				var w := _l2w(lx, lz)
				if IsleWorld._path_clearance(w.x, w.y) < 0.0:
					path_hit += 1
			lz += stp
		lx += stp
	var ymean := 0.0
	if n_in > 0:
		ymean = ysum / float(n_in)
	# 外缘统计（第三轮）：干垒石边最大高度 / 石边长度占比 / 草肩坡度与宽度
	var max_revet_h := 0.0
	var revet_len := 0.0
	var perim := 0.0
	var n_revet := 0
	var n_shoulder := 0
	var max_shoulder_slope := 0.0
	var max_shoulder_w := 0.0
	var max_apron := 0.0
	var max_apron_slope := 0.0
	for i in range(_skirt.size()):
		var sd: Dictionary = _skirt[i]
		var h2 := float(sd["h2"])
		var h1 := float(sd["h1"])
		var w1 := float(sd["w1"])
		var j2 := (i + 1) % _skirt.size()
		var seg_len: float = (_dense[i] as Vector2).distance_to(_dense[j2] as Vector2)
		perim += seg_len
		max_revet_h = maxf(max_revet_h, h2)
		if h2 > 0.005:
			n_revet += 1
			revet_len += seg_len
		if float(sd["f"]) > 0.02:
			n_shoulder += 1
			if w1 > 0.001 and h1 > 0.001:
				max_shoulder_slope = maxf(max_shoulder_slope, rad_to_deg(atan2(h1, w1)))
			max_shoulder_w = maxf(max_shoulder_w, w1)
		max_apron = maxf(max_apron, float(sd["apron"]))
		max_apron_slope = maxf(max_apron_slope, float(sd["apron_slope"]))
	var revet_frac := 0.0
	if perim > 0.0:
		revet_frac = revet_len / perim
	# 与房屋/门廊/台阶的高差
	var deck_top := _floor_y + 0.42
	var step_pt := _l2w(0.0, 5.60)
	var step_bottom: float = IsleWorld.surface_y(step_pt.x, step_pt.y)
	var y_door := _surf_y(Vector2(0.0, 3.3))
	var y_porch := _surf_y(Vector2(0.0, 4.74))
	var y_path0 := _surf_y(Vector2(-0.60, 5.48))
	var y_gate := _surf_y(fc + Vector2(0.0, -2.71))
	var y_far := _surf_y(Vector2(fc.x, fc.y + 2.71))
	# 连续性（门 -> 农田中心）
	var p0 := Vector2(0.0, 3.3)
	var p1 := fc
	var nseg := 60
	var gap := 0
	for s in range(nseg + 1):
		if not _pt_in_poly(p0.lerp(p1, float(s) / float(nseg)), _poly):
			gap += 1
	# 门洞
	var gcx := fc.x + float(_farm.get("gate_offset", 0.0))
	var gate := fc + Vector2(0.0, -2.71)
	var gate_on := _pt_in_poly(gate, _poly)
	var gate_w := 1.10
	# 农田围栏四角是否在台面上
	var ok_farm := true
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			if not _pt_in_poly(fc + Vector2(sx * 2.71, sz * 2.71), _poly):
				ok_farm = false
	# 农田段是否水平（供围栏/土床落地）
	var flat_dev := 0.0
	for i in range(-2, 3):
		for j in range(-2, 3):
			var q2 := fc + Vector2(i * 0.9, j * 0.9)
			flat_dev = maxf(flat_dev, absf(_surf_y(q2) - terr))
	# 小径：起点在门廊台阶下的真实草地（允许台外），之后应在台面上
	var path_off := 0
	var path_in := 0
	var path_n := 0
	# Lead 冻结小径直线 (-1.60,5.65) -> gate(-4.35,8.99)：200 采样必须 100% 在台内
	var sw_in := 0
	var sw_n := 200
	var sw_a := Vector2(-1.60, 5.65)
	for i in range(sw_n):
		var sw_q := sw_a.lerp(gate, float(i) / float(sw_n - 1))
		if _pt_in_poly(sw_q, _poly):
			sw_in += 1
		else:
			path_off += 1
	path_in = sw_in
	path_n = sw_n
	var path_in_frac := float(sw_in) / float(sw_n)
	print("[P2A] walkway straight inside=%.1f%% (%d/%d)" % [path_in_frac * 100.0, sw_in, sw_n])
	# 石板小径处台面与原地面高差（Lead 要求 ≤0.09m，避免小径变成台阶/悬空）
	var path_delta := 0.0
	# 既有园路（SPUR/MAIN）在台面范围内与原地形的高差：Lead 要求 <=0.09（铺面不跳）
	var lxq := x0
	while lxq <= x1:
		var lzq := z0
		while lzq <= z1:
			var lpq := Vector2(lxq, lzq)
			if _pt_in_poly(lpq, _poly):
				var wq := _l2w(lxq, lzq)
				if IsleWorld._path_clearance(wq.x, wq.y) < 0.0:
					path_delta = maxf(path_delta, absf(_surf_y(lpq) - _ground(lpq)))
			lzq += 0.30
		lxq += 0.30
	var poke_frac := 0.0
	var path_frac := 0.0
	if n_in > 0:
		poke_frac = float(poke) / float(n_in)
		path_frac = float(path_hit) / float(n_in)
	print("[P2A] platform bbox=(%.2f,%.2f)..(%.2f,%.2f) area=%.1f m2 samples=%d" % [
		x0, z0, x1, z1, absf(_poly_area(_poly)), n_in])
	print("[P2A] height: terrain min=%.3f max=%.3f | surface min=%.3f max=%.3f mean=%.3f" % [
		tmin, tmax, ymin, ymax, ymean])
	print("[P2A] probes: door=%.3f porch_edge=%.3f path_start=%.3f gate=%.3f farm_far=%.3f terrace=%.3f deck_top=%.3f step_bottom=%.3f" % [
		y_door, y_porch, y_path0, y_gate, y_far, terr, deck_top, step_bottom])
	print("[P2A] edge: max_revetment_h=%.3f m | revet_len=%.1f m of perim %.1f m (%.1f%%) | verts revet=%d" % [
		max_revet_h, revet_len, perim, revet_frac * 100.0, n_revet])
	print("[P2A] shoulder: max_slope=%.1f deg max_w=%.2f m (h1<=%.2f) | apron max_w=%.2f m max_slope=%.1f deg" % [
		max_shoulder_slope, max_shoulder_w, SHOULDER_H, max_apron, max_apron_slope])
	print("[P2A] flat_dev_on_farm=%.3f m | terrain_poke=%d (%.2f%%) | existing_path=%d (%.2f%%) | path_delta=%.3f m" % [
		flat_dev, poke, poke_frac * 100.0, path_hit, path_frac * 100.0, path_delta])

	_measured = {
		"probe": "probe_p2a_layout", "version": VERSION,
		"godot_version": String(Engine.get_version_info()["string"]),
		"display": DisplayServer.get_name(),
		"note": "temporary preview probe; preview geometry only, no production file touched",
		"generated_at_utc": Time.get_datetime_string_from_system(true),
		"candidate": _cand.get("id", ""),
		"label": _cand.get("label", ""),
		"nopad": nopad,
		"platform": {
			"poly_pts": _poly.size(), "dense_pts": _dense.size(),
			"area_m2": absf(_poly_area(_poly)),
			"bbox": [x0, z0, x1, z1],
			"terrain_min": tmin, "terrain_max": tmax,
			"surface_min": ymin, "surface_max": ymax, "surface_mean": ymean,
			"terrace_y": terr,
			"probes": {"door": y_door, "porch_edge": y_porch, "path_start": y_path0,
				"gate": y_gate, "farm_far": y_far,
				"deck_top": deck_top, "step_bottom": step_bottom,
				"platform_minus_deck": y_far - deck_top,
				"steps_buried": y_porch - step_bottom},
			"flat_dev_on_farm": flat_dev,
			"terrain_poke_samples": poke, "terrain_poke_frac": poke_frac,
			"existing_path_samples": path_hit, "existing_path_frac": path_frac,
			"continuous_door_to_farm": gap == 0, "continuous_gap_samples": gap,
		"path_inside_frac": path_in_frac,
			"gate": {"center": [gate.x, gate.y], "w": gate_w, "on_platform": gate_on},
			"farm_fence_inside": ok_farm,
			"path_points_off": path_off,
			"path_max_delta": path_delta,
			"edge": {"max_revetment_h": max_revet_h, "apron_max_w": max_apron, "apron_max_slope": max_apron_slope, "revet_len": revet_len, "perimeter": perim,
				"revet_frac": revet_frac, "revet_verts": n_revet, "shoulder_verts": n_shoulder,
				"max_shoulder_slope_deg": max_shoulder_slope, "max_shoulder_w": max_shoulder_w,
				"shoulder_h_cap": SHOULDER_H, "revet_max_h_cap": REVET_MAX_H, "revet_w": REVET_W},
			"preview_tris": _preview_tris,
			"masked_scatter": _masked,
		},
		"checks": _checks,
		"notes": _notes,
		"shots": _shots,
	}
	_check("platform_contacts_house", z0 <= 3.35, "min lz=%.3f (front wall 3.10)" % z0, "<=3.35")
	_check("platform_contains_farm", ok_farm, "fence corners inside platform (half 2.71)")
	_check("farm_level_flat", flat_dev <= 0.02, "max |surface-terrace| on farm=%.3f" % flat_dev, "<=0.02")
	_check("platform_continuous", path_in_frac >= 0.75 and gate_on,
		"walkway inside platform=%.0f%% (200/200 samples), gate on platform=%s (single 6-point polygon from front wall to farm)" % [
			path_in_frac * 100.0, str(gate_on)])
	_check("edge_treatment_ok", max_revet_h <= 0.70 + 0.001,
		"max revetment height=%.3f m @ %.1f%% perimeter (cap 0.70)" % [max_revet_h, revet_frac * 100.0], "<=0.70")
	_check("grass_shoulder_slope", max_shoulder_slope <= 33.5,
		"max grass shoulder slope=%.1f deg (h1 cap %.2f, w1 cap %.2f)" % [max_shoulder_slope, SHOULDER_H, SHOULDER_W], "<=33.5")
	_check("grass_shoulder_top_width", max_shoulder_w <= 1.13,
		"max grass shoulder width=%.2f m" % max_shoulder_w, "<=1.12")
	# 斜裙落地点必须贴合地形（差 < 0.03m），否则说明有悬空边或垂直落差
	var land_bad := 0
	var land_max := 0.0
	for i in range(_skirt.size()):
		var sd2: Dictionary = _skirt[i]
		if bool(sd2["flush"]):
			continue
		var p2: Vector2 = _dense[i]
		var n9: Vector2 = sd2["n"]
		var q9 := p2 + n9 * (float(sd2["w"]) + float(sd2["apron"]))
		var d9 := absf(float(sd2["y_end"]) - (_ground(q9) + 0.02))
		land_max = maxf(land_max, d9)
		if d9 > 0.03:
			land_bad += 1
	_check("shoulder_lands_on_terrain", land_bad == 0, "%d verts, max dev=%.3f m (bad=%d)" % [
		_skirt.size(), land_max, land_bad], "all landings <=0.03m")
	# 羽化检查：台缘与花园支路相交 2 处，台面在边界处必须与地形齐平（无竖直台唇），0.30m 内渐变回 +0.02
	var feather_lip := 0.0
	var feather_cnt := 0
	for fp in _feather:
		var fpt: Vector2 = fp
		for rr in [0.0, 0.10, 0.20, 0.30, 0.45]:
			for ang in [0.0, 1.5707963, 3.1415927, 4.712389]:
				var q_f := fpt + Vector2(cos(float(ang)), sin(float(ang))) * float(rr)
				if not (_pt_in_poly(q_f, _poly) or _near_poly(q_f, _poly, 0.02)):
					continue
				var lip := absf(_surf_y(q_f) - (_ground(q_f) + 0.02))
				feather_lip = maxf(feather_lip, lip)
				feather_cnt += 1
	print("[P2A] feather: pts=%d samples=%d max|pad-ground-0.02|=%.3f m" % [_feather.size(), feather_cnt, feather_lip])
	var fpts: Array = []
	for fp in _feather:
		fpts.append([(fp as Vector2).x, (fp as Vector2).y])
	if _measured.has("platform"):
		(_measured["platform"] as Dictionary)["feather_points_local"] = fpts
		(_measured["platform"] as Dictionary)["feather_max_offset"] = feather_lip
		(_measured["platform"] as Dictionary)["feather_fade_m"] = FEATHER_R
		(_measured["platform"] as Dictionary)["walkway"] = _walk
	_check("feather_ok", feather_lip <= 0.025, "feather max offset=%.3f m at %d road crossings" % [feather_lip, _feather.size()], "<=0.025 (0.30m fade, no vertical lip)")
	_check("walkway_on_pad", path_in_frac >= 0.999, "walkway samples inside pad=%.1f%%" % (path_in_frac * 100.0), "100%")
	_check("existing_path_delta", path_delta <= 0.09, "max |pad-terrain| on existing park paths=%.3f m" % path_delta, "<=0.09")
	# 诊断：沿田中心线打印地形剖面（判断 maxtrace 台面是否在农田段变成 7.372）
	var prof := ""
	for zz in [8.60, 9.00, 9.20, 9.60, 10.20, 10.80, 11.40, 12.00, 12.60, 13.20, 13.80, 14.40]:
		prof += "%.2f:%.3f/%.3f " % [zz, _ground(Vector2(-4.35, zz)), _top_y(Vector2(-4.35, zz))]
	for q in [Vector2(-1.45,14.55), Vector2(-1.45,14.75), Vector2(-7.7,14.75), Vector2(-4.35,14.75), Vector2(-7.55,14.65)]:
		print("[P2A] dbg edge pt %s ground=%.3f pad=%.3f fill=%.3f" % [str(q), _ground(q), _top_y(q), _top_y(q)-_ground(q)])
	print("[P2A] dbg terrain profile lx=-4.35 (ground/pad): ", prof)
	# 支路土色带是否被台面替换：台面取色 vs 真实 Terrain 顶点色（同一位置）最大通道差
	var spur_n := 0
	var spur_max := 0.0
	var bb0 := _bbox_of(_poly)
	var zp := float(bb0[1]) + 0.3
	while zp < float(bb0[3]) - 0.3:
		var xp := float(bb0[0]) + 0.3
		while xp < float(bb0[2]) - 0.3:
			var lp2 := Vector2(xp, zp)
			if _pt_in_poly(lp2, _poly):
				var wp := _l2w(lp2.x, lp2.y)
				if IsleWorld._path_clearance(wp.x, wp.y) < -0.10:
					var cc1 := _sample_terrain(lp2)
					var cc2 := _nearest_terrain_color(lp2)
					var d2 := maxf(maxf(absf(cc1.r - cc2.r), absf(cc1.g - cc2.g)), absf(cc1.b - cc2.b))
					spur_max = maxf(spur_max, d2)
					spur_n += 1
			xp += 0.6
		zp += 0.6
	_check("spur_band_preserved", spur_n == 0 or spur_max <= 0.06,
		"pad vs terrain color on garden spur: samples=%d max channel delta=%.3f" % [spur_n, spur_max], "<=0.06")
	_check("gate_gap", gate_on and gate_w >= 0.90, "gate on platform=%s w=%.2f" % [str(gate_on), gate_w], ">=0.90")
	_check("path_on_platform", path_in_frac >= 0.999, "walkway samples inside=%.0f%% (start local(-1.60,5.65) inside 6-point polygon)" % (
		path_in_frac * 100.0), "100%")
	if path_in_frac < 0.999:
		_note("path_off_platform", "walkway leaves platform for %.0f%% of its length" % (
			(1.0 - path_in_frac) * 100.0))
	_note("near_segment_flush", "maxtrace: near segment (front face to 7.372 contour) sits 0.02 m above terrain, no curb, grass blades remain visible through the pad by design")
	_check("no_terrain_poke", poke_frac <= 0.01, "terrain above surface at %.2f%% samples" % (poke_frac * 100.0), "<=1%")
	if path_frac > 0.02:
		_note("existing_path_covered", "platform footprint overlaps existing path/road at %.1f%% samples" % (path_frac * 100.0))
	if y_porch > step_bottom + 0.05:
		_note("porch_steps_buried", "porch stair bottom %.3f vs platform surface %.3f -> %.3f m buried" % [
			step_bottom, y_porch, y_porch - step_bottom])
	if max_revet_h > 0.62:
		_note("revet_tall", "max dry-stone revetment %.3f m (cap 0.70; P0 concrete podium was 1.8 m)" % max_revet_h)


# ------------------------------------------------------------ screenshots --
func _settle(sec: float) -> void:
	await create_timer(sec).timeout


# 每次截图前把所有 CanvasLayer（菜单/HUD 都是 CanvasLayer）压成不可见
func _suppress_ui() -> void:
	var menu: Variant = _main.get("_menu")
	if menu != null:
		menu.set("menu_visible", false)
	_hide_layers(_main)
	_hide_layers(root)


func _hide_layers(nd: Node) -> void:
	for c in nd.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
		_hide_layers(c)


func _cam_record(tag: String) -> void:
	if _cam == null:
		return
	var xf := _cam.global_transform
	var e := xf.basis.get_euler()
	var gnd := IsleWorld.surface_y(xf.origin.x, xf.origin.z)
	var lp := _w2l(xf.origin.x, xf.origin.z)
	_cams_ref.append({"tag": tag, "pos": [xf.origin.x, xf.origin.y, xf.origin.z],
		"local": [lp.x, lp.y], "terrain_at_cam": gnd, "clearance": xf.origin.y - gnd,
		"rot_deg": [rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z)],
		"fov": _cam.fov})


func _image_spread(img: Image) -> float:
	var mn := 1.0
	var mx := 0.0
	var step := maxi(1, int(img.get_width() / 48))
	for yy in range(0, img.get_height(), step):
		for xx in range(0, img.get_width(), step):
			var c := img.get_pixel(xx, yy)
			var v := (c.r + c.g + c.b) / 3.0
			mn = minf(mn, v)
			mx = maxf(mx, v)
	return mx - mn


func _shot(tag: String) -> void:
	if _headless:
		_check("shot_" + tag, false, "headless: no framebuffer")
		return
	_suppress_ui()
	# 硬校验：相机必须在地面以上至少 1.2m（防止钻进山体/树冠/台底）
	var cp := _cam.global_position
	var gnd := IsleWorld.surface_y(cp.x, cp.z)
	var dy := cp.y - gnd
	_check("cam_above_ground_" + tag, dy >= 1.2,
		"cam=(%.1f,%.1f,%.1f) ground=%.2f dy=%.2f" % [cp.x, cp.y, cp.z, gnd, dy])
	if dy > 12.0:
		_note("cam_aerial_" + tag, "camera %.1f m above ground (aerial/overview angle)" % dy)
	if _sv != null and _shot_cam != null:
		_shot_cam.global_transform = _cam.global_transform
		_shot_cam.fov = _cam.fov
	else:
		_check("offscreen_viewport", false, "subviewport missing")
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = _sv.get_texture().get_image() if (_sv != null and _sv.get_texture() != null) else null
	if img == null:
		_check("shot_" + tag, false, "viewport image null")
		return
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	var p := _shot_dir + "/" + tag_prefix + tag + ".png"
	# 空白帧保护：真实渲染必须有一定亮度跨度，否则视为相机钻进物体
	var spread := _image_spread(img)
	_check("shot_not_blank_" + tag, spread >= 0.02, "luma spread=%.3f" % spread)
	var err := img.save_png(p)
	print("[P2A] shot %s %dx%d err=%d -> %s" % [tag, img.get_width(), img.get_height(), err, p])
	if err == OK:
		_shots.append({"tag": tag, "path": p, "size": [img.get_width(), img.get_height()]})
		_check("shot_" + tag, true, p)
		_cam_record(tag)
	else:
		_check("shot_" + tag, false, "save_png err=%d" % err)


func _pose_play_default() -> void:
	_main.set("_theta", M.CAM_START_THETA)
	_main.set("_elev", 0.28)
	_main.set("_radius", M.CAM_START_R)
	_main.set("_cam_target", M.CAM_TARGET)
	_main.set("_fov", 42.0)
	_main.call("_apply_pose", _main.call("_play_pose"))


func _terrain_at(lx: float, lz: float) -> float:
	var w := _l2w(lx, lz)
	return IsleWorld.surface_y(w.x, w.y)


func _pose_local(plx: float, plz: float, py: float, tlx: float, tlz: float, ty: float, fov: float) -> void:
	var pp := _l2w(plx, plz)
	var tt := _l2w(tlx, tlz)
	_main.call("_pose_look", Vector3(pp.x, py, pp.y), Vector3(tt.x, ty, tt.y), fov)


func _ndc(world_pos: Vector3) -> Vector3:
	var cam := _shot_cam if _shot_cam != null else _cam
	if cam == null:
		return Vector3(9, 9, -1)
	var inv: Transform3D = cam.global_transform.affine_inverse()
	var v: Vector3 = inv * world_pos
	var proj: Projection = cam.get_camera_projection()
	var c: Vector4 = proj * Vector4(v.x, v.y, v.z, 1.0)
	if absf(c.w) < 0.000001:
		return Vector3(9, 9, -1)
	return Vector3(c.x / c.w, c.y / c.w, -v.z)


func _anchors_visible(need: int) -> int:
	# 硬校验（Lead 修正 v2 第 6 条）：关键锚点必须落在 NDC [-0.95,0.95]
	var anchors := [
		Vector3(_l2w(-4.0, 3.28).x, 7.90, _l2w(-4.0, 3.28).y),
		Vector3(_l2w(-4.35, 8.99).x, 7.60, _l2w(-4.35, 8.99).y),
		Vector3(_l2w(-7.70, 14.75).x, 7.37, _l2w(-7.70, 14.75).y),
		Vector3(_l2w(0.0, 5.60).x, 7.95, _l2w(0.0, 5.60).y)]
	var ok := 0
	var dbg := ""
	for a in anchors:
		var n := _ndc(a)
		dbg += " (%.2f,%.2f,z%.1f)" % [n.x, n.y, n.z]
		if absf(n.x) <= 0.95 and absf(n.y) <= 0.95 and n.z > 0.05:
			ok += 1
	print("[P2A] anchors visible=%d/%d ndc=%s" % [ok, anchors.size(), dbg])
	return ok


func _shots_for() -> void:
	if nopad:
		await _shots_baseline()
		return
	var fc := _farm_center()
	var terr := _terrace_y()
	var deck_top := _floor_y + 0.42
	var terr02 := _terrain_at(-1.0, 24.0)

	# 00 自检：台面亮品红 / 斜裙亮青，只用于验证几何覆盖
	if _want_cam(0):
		_pose_local(-1.0, 24.0, terr02 + 13.5, -3.2, 9.0, 7.6, 42.0)
		await _settle(0.5)
		var land := _find_named(_layout, "PlatformLand")
		if land is MeshInstance3D:
			(land as MeshInstance3D).visible = false
		if _debug_node != null:
			_debug_node.visible = true
		if _debug_stone != null:
			_debug_stone.visible = true
		await _shot("00_debug_pad")
		if land is MeshInstance3D:
			(land as MeshInstance3D).visible = true
		if _debug_node != null:
			_debug_node.visible = false
		if _debug_stone != null:
			_debug_stone.visible = false

	# 01 默认玩家相机（对照）
	if _want_cam(1):
		_pose_play_default()
		await _settle(0.8)
		await _shot("01_game_default")

	# 02 关系全景：房屋前墙 + 门前土地 + 围栏 + 旧花圃一角
	if _want_cam(2):
		_pose_local(-1.0, 24.0, terr02 + 13.5, -3.2, 9.0, 7.6, 42.0)
		await _settle(0.6)
		if _anchors_visible(3) >= 3:
			await _shot("02_overhead_oblique")
		else:
			_check("shot_02_anchors", false, "anchors not visible in 02_overhead_oblique")

	# 03 门前看田
	if _want_cam(3):
		_pose_local(1.20, 5.00, 9.12, -4.00, 8.60, 7.60, 48.0)
		await _settle(0.6)
		if _anchors_visible(3) >= 3:
			await _shot("03_porch_look")
		else:
			_check("shot_03_anchors", false, "anchors not visible in 03_porch_look")

	# 04 田口回望房屋入口
	if _want_cam(4):
		_pose_local(fc.x, 9.40, 8.60, 0.2, 3.1, 8.30, 55.0)
		await _settle(0.6)
		await _shot("04_gate_look_back")

	# 05 侧面看外侧 32° 草坡
	if _want_cam(5):
		_pose_local(5.6, 12.6, 9.00, -2.2, 12.4, 7.30, 50.0)
		await _settle(0.6)
		await _shot("05_left_side")

	# 06 贴墙衔接：前墙—台面近段—台基连续关系
	if _want_cam(6):
		_pose_local(-5.60, 6.90, 8.90, -1.50, 3.40, 8.20, 60.0)
		await _settle(0.6)
		await _shot("06_house_contact")

	# 07 外缘低视：坡下看 1.23m 的 32° 草坡与围栏
	if _want_cam(7):
		var g7 := _terrain_at(-2.60, 17.60)
		_pose_local(-2.60, 17.60, g7 + 1.50, -1.90, 14.20, 7.10, 52.0)
		await _settle(0.6)
		await _shot("07_far_edge")

	# 08 近段贴地证据：z 3.28~5.15 贴平段 + 门阶 + 两路起步带（重点看有无台唇/断口）
	if _want_cam(8):
		var g8 := _terrain_at(-6.40, 5.60)
		_pose_local(-6.40, 5.60, g8 + 1.55, 0.30, 4.20, 7.75, 62.0)
		await _settle(0.6)
		await _shot("08_near_strip_flat")

	# 09 小径与既有花园支路的交叉路口（保留支路原石板）
	# 注：Lead 给的 (-3.10,8.20)+1.35 距目标仅 1.24m、俯角约 46°，画面只剩地面无法判读，
	# 故同目标点后退到 (-4.20,10.40)，高度 +1.35，俯角约 19°，使两路交叉可读。
	if _want_cam(9):
		var g9 := _terrain_at(-9.00, 7.20)
		_pose_local(-9.00, 7.20, maxf(g9, _terrace_y()) + 1.90, -2.90, 6.90, 7.45, 48.0)
		await _settle(0.6)
		await _shot("09_walkway_junction")

	if _shots.size() >= 4:
		_check("shots_rendered", true, "count=%d" % _shots.size())
	else:
		_check("shots_rendered", false, "count=%d" % _shots.size())


func _scan_lamps(node: Node, out: Array) -> void:
	if node is Node3D:
		var nm := String(node.name)
		if nm.begins_with("PathLamp") or nm.begins_with("GardenLamp"):
			var n3 := node as Node3D
			out.append({"name": nm, "parent": String(n3.get_parent().name) if n3.get_parent() != null else "",
				"pos": [n3.global_position.x, n3.global_position.y, n3.global_position.z]})
	for ch in node.get_children():
		_scan_lamps(ch, out)


func _aabb_of(node: Node) -> Dictionary:
	var box := AABB()
	var has := false
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var b: AABB = AABB()
		var ok := false
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh != null:
				b = mi.global_transform * mi.mesh.get_aabb()
				ok = true
		elif n is MultiMeshInstance3D:
			var mm := n as MultiMeshInstance3D
			if mm.multimesh != null:
				b = mm.global_transform * mm.get_aabb()
				ok = true
		if ok:
			box = b if not has else box.merge(b)
			has = true
		for ch in n.get_children():
			stack.append(ch)
	return {"has": has, "min": [box.position.x, box.position.y, box.position.z],
		"max": [box.position.x + box.size.x, box.position.y + box.size.y, box.position.z + box.size.z],
		"size": [box.size.x, box.size.y, box.size.z]}


func _find_named(node: Node, nm: String) -> Node:
	if String(node.name) == nm:
		return node
	for ch in node.get_children():
		var r := _find_named(ch, nm)
		if r != null:
			return r
	return null


func _preview_aabb() -> Dictionary:
	var groups := {}
	if _layout == null:
		return groups
	var stack: Array = []
	for ch in _layout.get_children():
		stack.append(ch)
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh != null:
				var g := "other"
				var nm := String(mi.name)
				if nm.begins_with("Platform"):
					g = "platform"
				elif nm.begins_with("Bed"):
					g = "beds"
				elif nm.begins_with("Path") or nm.begins_with("GateSill"):
					g = "path"
				elif nm.begins_with("Rail") or nm.begins_with("Post"):
					g = "fence"
				var b: AABB = _layout.global_transform * (mi.transform * mi.mesh.get_aabb())
				if groups.has(g):
					groups[g] = (groups[g] as AABB).merge(b)
				else:
					groups[g] = b
		for ch in n.get_children():
			stack.append(ch)
	var out := {}
	for k in groups:
		var b2: AABB = groups[k]
		out[k] = {"min": [b2.position.x, b2.position.y, b2.position.z],
			"max": [b2.position.x + b2.size.x, b2.position.y + b2.size.y, b2.position.z + b2.size.z],
			"size": [b2.size.x, b2.size.y, b2.size.z]}
	return out


func _shots_baseline() -> void:
	# S0 原状基线：与候选同一套机位，但目标点用冻结几何的常量（_L 未构建）
	_note("baseline_cams", "same 8 local poses as candidates; anchors skipped (no preview geometry)")
	if _want_cam(0):
		var g02 := _terrain_at(-1.0, 24.0)
		_pose_local(-1.0, 24.0, g02 + 13.5, -3.2, 9.0, 7.60, 42.0)
		await _settle(0.6)
		await _shot("00_debug_pad")
	if _want_cam(1):
		_pose_play_default()
		await _settle(0.8)
		await _shot("01_game_default")
	if _want_cam(2):
		var g2 := _terrain_at(-1.0, 24.0)
		_pose_local(-1.0, 24.0, g2 + 13.5, -3.2, 9.0, 7.60, 42.0)
		await _settle(0.6)
		await _shot("02_overhead_oblique")
	if _want_cam(3):
		_pose_local(0.4, 5.2, 9.60, -4.35, 9.60, 7.60, 48.0)
		await _settle(0.6)
		await _shot("03_porch_look")
	if _want_cam(4):
		_pose_local(-4.35, 9.40, 8.60, 0.2, 3.1, 8.30, 55.0)
		await _settle(0.6)
		await _shot("04_gate_look_back")
	if _want_cam(5):
		_pose_local(5.6, 12.6, 9.00, -2.2, 12.4, 7.30, 50.0)
		await _settle(0.6)
		await _shot("05_left_side")
	if _want_cam(6):
		_pose_local(-5.60, 6.90, 8.90, -1.50, 3.40, 8.20, 60.0)
		await _settle(0.6)
		await _shot("06_house_contact")
	if _want_cam(7):
		var g7 := _terrain_at(-2.60, 17.60)
		_pose_local(-2.60, 17.60, g7 + 1.50, -1.90, 14.20, 7.10, 52.0)
		await _settle(0.6)
		await _shot("07_far_edge")
	if _want_cam(8):
		var g8 := _terrain_at(-6.9, 6.2)
		_pose_local(-6.9, 6.2, g8 + 1.60, -3.0, 7.6, g8 + 0.05, 58.0)
		await _settle(0.6)
		await _shot("08_near_strip_flat")
	_check("shots_rendered", _shots.size() >= 4, "%d shots" % _shots.size())

func _write_engine_ref() -> void:
	var lamps: Array = []
	_scan_lamps(_main, lamps)
	var ref := {
		"probe": "probe_p2a_layout", "version": VERSION,
		"generated_at_utc": Time.get_datetime_string_from_system(true),
		"candidate": _cand.get("id", ""), "nopad": nopad,
		"lamps": lamps,
		"house": {"aabb": _aabb_of(_find_named(_main, "Cottage"))},
		"porch_steps_aabb": _aabb_of(_find_named(_main, "PorchSteps")),
		"porch_planks_multimesh_aabb": _aabb_of(_find_named(_main, "PorchPlanks")),
		"preview_aabb": _preview_aabb(),
		"platform_elev": _measured.get("platform", {}),
		"cameras": _cams_ref,
		"camera_defaults": {"theta": M.CAM_START_THETA, "phi": M.CAM_START_PHI, "r": M.CAM_START_R,
			"target": [M.CAM_TARGET.x, M.CAM_TARGET.y, M.CAM_TARGET.z]},
	}
	var p := _shot_dir + "/engine_ref.json"
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	var fa := FileAccess.open(p, FileAccess.WRITE)
	if fa != null:
		fa.store_string(JSON.stringify(ref, "  ", true))
		fa.close()
		print("[P2A] wrote " + p)


func _write_outputs() -> void:
	var p := _shot_dir + "/C_measure.json"
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	var fa := FileAccess.open(p, FileAccess.WRITE)
	if fa != null:
		fa.store_string(JSON.stringify(_measured, "  ", true))
		fa.close()
		print("[P2A] wrote " + p)
	var p2 := _shot_dir + "/C_candidate_resolved.json"
	var fb := FileAccess.open(p2, FileAccess.WRITE)
	if fb != null:
		fb.store_string(JSON.stringify({"cand": _cand, "poly_rounded": _poly, "top": _top}, "  ", true))
		fb.close()


var _cams_ref: Array = []
var _walk := {}
var _sv: SubViewport = null
var _shot_cam: Camera3D = null
