class_name IsleFx
extends RefCounted
## Ambience particles (chimney smoke, fireflies, petals), pooled 3D water
## splashes (true circular foam rings + volume water columns + sphere droplet
## particles), boat wakes, circular expanding ripples, jumping fish and a
## 10-bird flock with a day/night perch/landing state machine.
##
## Everything that spawns repeatedly is pooled and bounded; every mesh,
## material and texture that can be shared is created once and cached in
## static dictionaries, so gameplay frames never allocate resources.

const M := preload("res://scripts/isle_math.gd")

# ---- shared tuning constants (also read by tools/probe_fx_p4.gd) ----
const BIRD_COUNT := 10
const BIRD_DAY_TARGET := 6
const BIRD_FLY_LOW := 5
const BIRD_FLY_HIGH := 7
const BIRD_TIMER_MIN := 8.0
const BIRD_TIMER_MAX := 20.0
const BIRD_TRANSITION_MIN := 0.6
const BIRD_TRANSITION_MAX := 1.0
const BIRD_MIN_AIR_GAP := 1.6
const SPLASH_MAX_ACTIVE := 10
const SPLASH_MAX_UNITS := 12
const RIPPLE_MAX_ACTIVE := 24
const RIPPLE_MAX_UNITS := 30
const CLICK_FISH_COUNT := 5
const CLICK_FISH_WINDOW := 2.5
# ---- Phase6 停栖面（世界法线）约束：海鸥站在瓦面/枝头而不是悬空或穿模 ----
const PERCH_MIN_NORMAL_Y := 0.35      # 法线 y 分量下限（约 <=69.5° 坡）
const PERCH_MAX_SLOPE := 1.047198     # 60°，超过视为不可停栖
const BODY_TILT_MAX := 0.610865       # 35°，身体 up 最大倾角（与飞行 PITCH_MAX 一致）
const PERCH_FOOT_LIFT := 0.02         # 脚底沿法线抬起，避免与瓦面 z-fighting

# ============================================================
# 共享资源缓存（全局只创建一次）
# ============================================================
static var _mesh_cache: Dictionary = {}
static var _mat_cache: Dictionary = {}
static var _tex_cache: Dictionary = {}
static var _ramp_cache: Dictionary = {}

static func _finite_vec(v: Vector3) -> bool:
	return not (is_nan(v.x) or is_nan(v.y) or is_nan(v.z)) and absf(v.x) < 1.0e6 and absf(v.y) < 1.0e6 and absf(v.z) < 1.0e6

static func _ring_tex() -> Texture2D:
	if not _tex_cache.has("ring128"):
		_tex_cache["ring128"] = M.ring_texture(128)
	return _tex_cache["ring128"]

# 手写 XZ 平面内的环面网格：外径 outer、管径 tube。整个网格位于 XZ 平面，
# 因此节点只需在 XZ 等比缩放即为真正圆环（不再用旋转过的 QuadMesh）。
static func _torus_ring_mesh() -> ArrayMesh:
	if not _mesh_cache.has("ring_mesh"):
		_mesh_cache["ring_mesh"] = _build_torus(56, 8, 1.0, 0.16)
	return _mesh_cache["ring_mesh"]

static func _build_torus(seg: int, tube_seg: int, outer: float, tube_r: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(seg):
		var a0: float = TAU * float(i) / float(seg)
		var a1: float = TAU * float(i + 1) / float(seg)
		for j in range(tube_seg):
			var b0: float = TAU * float(j) / float(tube_seg)
			var b1: float = TAU * float(j + 1) / float(tube_seg)
			_torus_vertex(st, a0, b0, outer, tube_r)
			_torus_vertex(st, a1, b0, outer, tube_r)
			_torus_vertex(st, a1, b1, outer, tube_r)
			_torus_vertex(st, a0, b0, outer, tube_r)
			_torus_vertex(st, a1, b1, outer, tube_r)
			_torus_vertex(st, a0, b1, outer, tube_r)
	return st.commit()

static func _torus_vertex(st: SurfaceTool, a: float, b: float, outer: float, tube_r: float) -> void:
	var rr: float = outer + tube_r * cos(b)
	var n := Vector3(cos(b) * cos(a), sin(b), cos(b) * sin(a))
	st.set_normal(n)
	st.set_uv(Vector2(a / TAU, b / TAU))
	st.add_vertex(Vector3(rr * cos(a), tube_r * sin(b), rr * sin(a)))

static func _column_mesh() -> CylinderMesh:
	if not _mesh_cache.has("column_mesh"):
		var c := CylinderMesh.new()
		c.top_radius = 0.55
		c.bottom_radius = 1.0
		c.height = 1.0
		c.radial_segments = 10
		c.rings = 1
		_mesh_cache["column_mesh"] = c
	return _mesh_cache["column_mesh"]

# 低模球体（水滴 / 鸟身共用）：半径 1，高 2。
static func _sphere_mesh() -> SphereMesh:
	if not _mesh_cache.has("sphere_mesh"):
		var s := SphereMesh.new()
		s.radius = 1.0
		s.height = 2.0
		s.radial_segments = 12
		s.rings = 6
		_mesh_cache["sphere_mesh"] = s
	return _mesh_cache["sphere_mesh"]

static func _box_mesh() -> BoxMesh:
	if not _mesh_cache.has("box_mesh"):
		var b := BoxMesh.new()
		b.size = Vector3(1.0, 1.0, 1.0)
		_mesh_cache["box_mesh"] = b
	return _mesh_cache["box_mesh"]

static func _cone_mesh() -> CylinderMesh:
	if not _mesh_cache.has("cone_mesh"):
		var c := CylinderMesh.new()
		c.top_radius = 0.0
		c.bottom_radius = 1.0
		c.height = 1.0
		c.radial_segments = 6
		c.rings = 1
		_mesh_cache["cone_mesh"] = c
	return _mesh_cache["cone_mesh"]

static func _plane_xz_mesh() -> PlaneMesh:
	if not _mesh_cache.has("plane_xz"):
		var p := PlaneMesh.new()
		p.size = Vector2(1.0, 1.0)
		p.orientation = PlaneMesh.FACE_Y
		_mesh_cache["plane_xz"] = p
	return _mesh_cache["plane_xz"]

static func _fish_body_mesh() -> SphereMesh:
	if not _mesh_cache.has("fish_body"):
		var s := SphereMesh.new()
		s.radius = 1.0
		s.height = 2.0
		s.radial_segments = 8
		s.rings = 4
		_mesh_cache["fish_body"] = s
	return _mesh_cache["fish_body"]

static func _fish_tail_mesh() -> PrismMesh:
	if not _mesh_cache.has("fish_tail"):
		var p := PrismMesh.new()
		p.size = Vector3(0.26, 0.30, 0.02)
		_mesh_cache["fish_tail"] = p
	return _mesh_cache["fish_tail"]

# ============================================================
# 海鸥模型（顶点色低模）：
#   白身 / 灰背灰翼 / 黑翼尖 / 黄喙 / 深色眼 / 橙脚；双翼分内外两段 + 每翼 6 根初级飞羽。
#   所有部件共享一个 toon 顶点色材质，网格资源静态缓存（10 只鸟共 ~11 个网格）。
#   顶点色沿用项目惯例直接使用 sRGB hex（材质 albedo=white，着色器里 base *= v_lcol）。
# 模型局部坐标：+Z = 头/喙方向，+Y = 背/上，+X = 右翼（与契约一致）。
# 节点原点在脚底（y=0 即栖枝表面），总长 ~0.65m，展开翼展 ~1.21m。
# ============================================================
static func _gull_primary_count() -> int:
	return 6

# 海鸥顶点色：着色器把顶点色当线性空间使用、输出时再做 linear→sRGB，
# 因此这里先把“想看到的目标 sRGB 颜色”转成线性值，渲染出来才接近目标色。
# （项目里其它顶点色网格直接写 sRGB，会整体偏亮；海鸥需要准确的灰/黑对比。）
static func _gull_col(hex: String) -> Color:
	return Color(hex).srgb_to_linear()

# 双面三角形：正面 (a,b,c) 用 ca/cb/cc，背面用 col_back；flip=true 用于 -X 侧镜像网格。
static func _gull_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color, flip: bool) -> void:
	_gull_tri4(st, a, b, c, col, col, col, col, flip)

static func _gull_tri4(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color, col_back: Color, flip: bool) -> void:
	var va: Vector3 = a
	var vb: Vector3 = b
	var vc: Vector3 = c
	var c1: Color = ca
	var c2: Color = cb
	var c3: Color = cc
	if flip:
		vb = c
		vc = b
		c2 = cc
		c3 = cb
	var n: Vector3 = (vb - va).cross(vc - va)
	if n.length_squared() < 1.0e-12:
		return
	n = n.normalized()
	# 注意 Godot 的正面 = 屏幕空间顺时针，即右手法线指向观察者的反方向。
	# 因此 (va,vb,vc) 这一面真正朝向 -n 侧，法线必须写 -n；反向 (va,vc,vb) 朝向 +n 侧，写 +n。
	# 之前两面法线写反，导致所有海鸥表面把「底面光照」用到顶面，白/灰/黑全部渲染成暖褐色。
	st.set_normal(-n)
	st.set_color(c1)
	st.add_vertex(va)
	st.set_normal(-n)
	st.set_color(c2)
	st.add_vertex(vb)
	st.set_normal(-n)
	st.set_color(c3)
	st.add_vertex(vc)
	st.set_normal(n)
	st.set_color(col_back)
	st.add_vertex(va)
	st.set_normal(n)
	st.set_color(col_back)
	st.add_vertex(vc)
	st.set_normal(n)
	st.set_color(col_back)
	st.add_vertex(vb)

static func _gull_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col_front: Color, col_back: Color, flip: bool) -> void:
	_gull_tri4(st, a, b, c, col_front, col_front, col_front, col_back, flip)
	_gull_tri4(st, a, c, d, col_front, col_front, col_front, col_back, flip)

static func _gull_quad4(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ca: Color, cb: Color, cc: Color, cd: Color, col_back: Color, flip: bool) -> void:
	_gull_tri4(st, a, b, c, ca, cb, cc, col_back, flip)
	_gull_tri4(st, a, c, d, ca, cc, cd, col_back, flip)

# 轴对齐盒子（双面，用于腿/脚趾等小部件）
static func _gull_box(st: SurfaceTool, center: Vector3, size: Vector3, ca: Color, cb: Color) -> void:
	var h: Vector3 = size * 0.5
	var p000 := center + Vector3(-h.x, -h.y, -h.z)
	var p100 := center + Vector3(h.x, -h.y, -h.z)
	var p010 := center + Vector3(-h.x, h.y, -h.z)
	var p110 := center + Vector3(h.x, h.y, -h.z)
	var p001 := center + Vector3(-h.x, -h.y, h.z)
	var p101 := center + Vector3(h.x, -h.y, h.z)
	var p011 := center + Vector3(-h.x, h.y, h.z)
	var p111 := center + Vector3(h.x, h.y, h.z)
	_gull_quad(st, p000, p100, p110, p010, ca, cb, false)
	_gull_quad(st, p001, p101, p111, p011, ca, cb, false)
	_gull_quad(st, p000, p100, p101, p001, ca, cb, false)
	_gull_quad(st, p010, p110, p111, p011, ca, cb, false)
	_gull_quad(st, p000, p010, p011, p001, ca, cb, false)
	_gull_quad(st, p100, p110, p111, p101, ca, cb, false)

# 八面体（眼睛等小块，双面同色）
static func _gull_octa(st: SurfaceTool, center: Vector3, radii: Vector3, col: Color) -> void:
	var px := center + Vector3(radii.x, 0.0, 0.0)
	var nx := center + Vector3(-radii.x, 0.0, 0.0)
	var py := center + Vector3(0.0, radii.y, 0.0)
	var ny := center + Vector3(0.0, -radii.y, 0.0)
	var pz := center + Vector3(0.0, 0.0, radii.z)
	var nz := center + Vector3(0.0, 0.0, -radii.z)
	_gull_tri(st, px, py, pz, col, false)
	_gull_tri(st, py, nx, pz, col, false)
	_gull_tri(st, nx, ny, pz, col, false)
	_gull_tri(st, ny, px, pz, col, false)
	_gull_tri(st, py, px, nz, col, false)
	_gull_tri(st, nx, py, nz, col, false)
	_gull_tri(st, ny, nx, nz, col, false)
	_gull_tri(st, px, ny, nz, col, false)

# 椭球体（躯干/头）：逐顶点色，sRGB 直接写顶点色
static func _gull_ellipsoid(st: SurfaceTool, center: Vector3, radii: Vector3, seg: int, rings: int, white: Color, grey: Color, dark: Color, mantle: bool) -> void:
	for j in range(rings):
		var v0: float = PI * float(j) / float(rings)
		var v1: float = PI * float(j + 1) / float(rings)
		for i in range(seg):
			var u0: float = TAU * float(i) / float(seg)
			var u1: float = TAU * float(i + 1) / float(seg)
			var p00: Vector3 = center + Vector3(radii.x * sin(v0) * cos(u0), radii.y * cos(v0), radii.z * sin(v0) * sin(u0))
			var p10: Vector3 = center + Vector3(radii.x * sin(v0) * cos(u1), radii.y * cos(v0), radii.z * sin(v0) * sin(u1))
			var p11: Vector3 = center + Vector3(radii.x * sin(v1) * cos(u1), radii.y * cos(v1), radii.z * sin(v1) * sin(u1))
			var p01: Vector3 = center + Vector3(radii.x * sin(v1) * cos(u0), radii.y * cos(v1), radii.z * sin(v1) * sin(u0))
			var c00 := _gull_ell_tone(p00 - center, radii, white, grey, dark, mantle)
			var c10 := _gull_ell_tone(p10 - center, radii, white, grey, dark, mantle)
			var c11 := _gull_ell_tone(p11 - center, radii, white, grey, dark, mantle)
			var c01 := _gull_ell_tone(p01 - center, radii, white, grey, dark, mantle)
			_gull_tri4(st, p00, p10, p11, c00, c10, c11, c00, false)
			_gull_tri4(st, p00, p11, p01, c00, c11, c01, c00, false)

static func _gull_ell_tone(rel: Vector3, radii: Vector3, white: Color, grey: Color, dark: Color, mantle: bool) -> Color:
	var n := Vector3(rel.x / radii.x, rel.y / radii.y, rel.z / radii.z)
	if n.length_squared() > 0.0000001:
		n = n.normalized()
	if not mantle:
		# 头：白色为主，头顶一点点灰，增强体积
		return white.lerp(grey, smoothstep(0.35, 0.95, n.y) * 0.22)
	var top: float = smoothstep(-0.10, 0.55, n.y)
	var back: float = 1.0 - smoothstep(-0.30, 0.40, n.z)
	var k: float = top * clampf(0.30 + 0.70 * back, 0.0, 1.0)
	var col: Color = white.lerp(grey, k)
	if k > 0.55:
		col = col.lerp(dark, (k - 0.55) * 0.55)
	return col

static func _gull_body_mesh() -> ArrayMesh:
	if _mesh_cache.has("gull_body"):
		return _mesh_cache["gull_body"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_gull_ellipsoid(st, Vector3(0.0, 0.200, 0.0), Vector3(0.086, 0.082, 0.180), 12, 5,
		_gull_col("f2efe7"), _gull_col("8f9aa6"), _gull_col("6f7a86"), true)
	var mesh: ArrayMesh = st.commit()
	_mesh_cache["gull_body"] = mesh
	return mesh

static func _gull_head_mesh() -> ArrayMesh:
	if _mesh_cache.has("gull_head"):
		return _mesh_cache["gull_head"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_gull_ellipsoid(st, Vector3.ZERO, Vector3(0.062, 0.060, 0.066), 10, 4,
		_gull_col("f4f1ea"), _gull_col("a7b1bb"), _gull_col("8f9aa6"), false)
	var mesh: ArrayMesh = st.commit()
	_mesh_cache["gull_head"] = mesh
	return mesh

static func _gull_eyes_mesh() -> ArrayMesh:
	if _mesh_cache.has("gull_eyes"):
		return _mesh_cache["gull_eyes"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var eye := _gull_col("23262b")
	_gull_octa(st, Vector3(-0.045, 0.010, 0.033), Vector3(0.017, 0.014, 0.011), eye)
	_gull_octa(st, Vector3(0.045, 0.010, 0.033), Vector3(0.017, 0.014, 0.011), eye)
	var mesh: ArrayMesh = st.commit()
	_mesh_cache["gull_eyes"] = mesh
	return mesh

static func _gull_tail_mesh() -> ArrayMesh:
	if _mesh_cache.has("gull_tail"):
		return _mesh_cache["gull_tail"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var white := _gull_col("f2efe7")
	var under := _gull_col("dfe4e2")
	var tip := _gull_col("c9d2d8")
	# 尾羽：根部窄、末端宽的扇形薄片，轻微上翘。
	# 注意：坐标是 tail 节点局部空间（节点自身放在躯干后方 y=0.196 处），
	# 这里 y 只写相对高度（0~0.010），不要写躯干绝对高度，否则会双倍偏移成悬浮板。
	var secs: Array = [
		Vector4(0.0, 0.055, 0.0, 0.000),
		Vector4(-0.085, 0.074, 0.006, 0.002),
		Vector4(-0.165, 0.094, 0.010, 0.006),
		Vector4(-0.235, 0.104, 0.012, 0.010),
	]
	for i in range(secs.size() - 1):
		var a: Vector4 = secs[i]
		var b: Vector4 = secs[i + 1]
		var ta: Color = tip if i == secs.size() - 2 else white
		var p0l := Vector3(-a.y, a.w + 0.004, a.x)
		var p0r := Vector3(a.y, a.w + 0.004, a.x)
		var p1l := Vector3(-b.y, b.w + 0.004, b.x)
		var p1r := Vector3(b.y, b.w + 0.004, b.x)
		_gull_quad4(st, p0l, p0r, p1r, p1l, white, white, ta, ta, under, false)
		var q0l := Vector3(-a.y, a.w - 0.004, a.x)
		var q0r := Vector3(a.y, a.w - 0.004, a.x)
		var q1l := Vector3(-b.y, b.w - 0.004, b.x)
		var q1r := Vector3(b.y, b.w - 0.004, b.x)
		_gull_quad4(st, q0l, q0r, q1r, q1l, under, under, under, under, white, false)
		_gull_quad(st, p0l, p0r, q0r, q0l, white, under, false)
		_gull_quad(st, p1l, p1r, q1r, q1l, ta, under, false)
	var mesh: ArrayMesh = st.commit()
	_mesh_cache["gull_tail"] = mesh
	return mesh

static func _gull_legs_mesh() -> ArrayMesh:
	if _mesh_cache.has("gull_legs"):
		return _mesh_cache["gull_legs"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var orange := _gull_col("d98436")
	var orange_d := _gull_col("b96f28")
	for side in [-1.0, 1.0]:
		var sx: float = 0.030 * float(side)
		_gull_box(st, Vector3(sx, 0.088, 0.016), Vector3(0.019, 0.070, 0.020), orange_d, orange)
		_gull_box(st, Vector3(sx + 0.002 * float(side), 0.040, 0.014), Vector3(0.014, 0.072, 0.014), orange, orange_d)
		for toe in [-1, 0, 1]:
			var ang: float = 0.0
			if toe == -1:
				ang = -0.42
			elif toe == 1:
				ang = 0.42
			var dir := Vector3(sin(ang), 0.0, cos(ang))
			var sidev := Vector3(cos(ang), 0.0, -sin(ang))
			var base := Vector3(sx + 0.002 * float(side), 0.006, 0.028)
			var tip_p := base + dir * 0.052
			var hw := 0.009
			_gull_quad(st, base - sidev * hw, base + sidev * hw, tip_p + sidev * hw * 0.45, tip_p - sidev * hw * 0.45, orange, orange_d, false)
	var mesh: ArrayMesh = st.commit()
	_mesh_cache["gull_legs"] = mesh
	return mesh

# 翼面剖面插值：返回 x 处的后缘 z
static func _gull_wing_te(secs: Array, x: float) -> float:
	for i in range(secs.size() - 1):
		var a: Vector4 = secs[i]
		var b: Vector4 = secs[i + 1]
		if x <= b.x:
			var t: float = clampf((x - a.x) / maxf(b.x - a.x, 0.000001), 0.0, 1.0)
			return lerpf(a.z, b.z, t)
	var last: Vector4 = secs[secs.size() - 1]
	return last.z

# 翼面薄板：剖面 Vector4(x, 前缘z, 后缘z, 上表面半厚)；sign=-1 生成左翼镜像。
static func _gull_wing_plate(st: SurfaceTool, secs: Array, sign: float, flip: bool, grey: Color, le_col: Color, under: Color, edge: Color) -> void:
	var le_frac: float = 0.16
	for i in range(secs.size() - 1):
		var a: Vector4 = secs[i]
		var b: Vector4 = secs[i + 1]
		var x0: float = a.x * sign
		var x1: float = b.x * sign
		var yt0: float = a.w
		var yt1: float = b.w
		var yb0: float = -a.w * 0.80
		var yb1: float = -b.w * 0.80
		var le0 := Vector3(x0, yt0, a.y)
		var le1 := Vector3(x1, yt1, b.y)
		var ml0 := Vector3(x0, yt0, lerpf(a.y, a.z, le_frac))
		var ml1 := Vector3(x1, yt1, lerpf(b.y, b.z, le_frac))
		var te0 := Vector3(x0, yt0, a.z)
		var te1 := Vector3(x1, yt1, b.z)
		_gull_quad4(st, le0, le1, ml1, ml0, le_col, le_col, le_col, le_col, grey, flip)
		_gull_quad4(st, ml0, ml1, te1, te0, grey, grey, grey, grey, under, flip)
		var bl0 := Vector3(x0, yb0, a.y)
		var bl1 := Vector3(x1, yb1, b.y)
		var bt0 := Vector3(x0, yb0, a.z)
		var bt1 := Vector3(x1, yb1, b.z)
		_gull_quad4(st, bl0, bl1, bt1, bt0, under, under, under, under, grey, flip)
		_gull_quad4(st, le0, le1, bl1, bl0, le_col, le_col, le_col, le_col, edge, flip)
		_gull_quad4(st, te0, te1, bt1, bt0, grey, grey, under, under, edge, flip)
	var last: Vector4 = secs[secs.size() - 1]
	var lx: float = last.x * sign
	var lyt: float = last.w
	var lyb: float = -last.w * 0.80
	var cap_a := Vector3(lx, lyt, last.y)
	var cap_b := Vector3(lx, lyt, last.z)
	var cap_c := Vector3(lx, lyb, last.z)
	var cap_d := Vector3(lx, lyb, last.y)
	_gull_quad4(st, cap_a, cap_b, cap_c, cap_d, grey, grey, under, under, grey, flip)

static func _gull_wing_inner_mesh(sign: float) -> ArrayMesh:
	var key: String = "gull_wing_inner_r" if sign >= 0.0 else "gull_wing_inner_l"
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var flip: bool = sign < 0.0
	var grey := _gull_col("96a1ad")
	var le_col := _gull_col("f2efe7")
	var under := _gull_col("e2e7e6")
	var edge := _gull_col("c2cad1")
	var secs: Array = [
		Vector4(0.000, 0.105, -0.100, 0.017),
		Vector4(0.115, 0.086, -0.094, 0.013),
		Vector4(0.230, 0.050, -0.086, 0.009),
	]
	_gull_wing_plate(st, secs, sign, flip, grey, le_col, under, edge)
	# 次级飞羽：4 片灰羽白尖，从翼后缘继续向后展开
	for k in range(4):
		var kf: float = float(k) / 3.0
		var root_x: float = 0.045 + 0.045 * float(k)
		var root := Vector3(root_x * sign, 0.001, _gull_wing_te(secs, root_x))
		var ang: float = lerpf(0.66, 0.38, kf)
		var dir := Vector3(sin(ang) * sign, 0.0, -cos(ang))
		var length: float = lerpf(0.070, 0.092, kf)
		var sidev := Vector3(-dir.z, 0.0, dir.x)
		var hw: float = 0.020
		var p0a := root - sidev * hw
		var p0b := root + sidev * hw
		var p1a := root + dir * (length * 0.68) - sidev * hw * 0.92
		var p1b := root + dir * (length * 0.68) + sidev * hw * 0.92
		var p2a := root + dir * length - sidev * hw * 0.30
		var p2b := root + dir * length + sidev * hw * 0.30
		_gull_quad4(st, p0a, p0b, p1b, p1a, grey, grey, grey, grey, under, flip)
		_gull_quad4(st, p1a, p1b, p2b, p2a, grey, grey, le_col, le_col, under, flip)
	var mesh: ArrayMesh = st.commit()
	_mesh_cache[key] = mesh
	return mesh

static func _gull_wing_outer_mesh(sign: float) -> ArrayMesh:
	var key: String = "gull_wing_outer_r" if sign >= 0.0 else "gull_wing_outer_l"
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var flip: bool = sign < 0.0
	var grey := _gull_col("95a0ac")
	var le_col := _gull_col("f2efe7")
	var under := _gull_col("e2e7e6")
	var edge := _gull_col("bfc7cf")
	var secs: Array = [
		Vector4(0.000, 0.050, -0.086, 0.009),
		Vector4(0.100, 0.028, -0.074, 0.007),
		Vector4(0.190, 0.002, -0.052, 0.005),
		Vector4(0.215, -0.008, -0.032, 0.004),
	]
	_gull_wing_plate(st, secs, sign, flip, grey, le_col, under, edge)
	# 初级飞羽：6 根，越靠翼尖越长、越朝外；外 45% 渐变为黑色
	var c_grey := _gull_col("8d98a4")
	var c_mid := _gull_col("59626d")
	var c_black := _gull_col("23262b")
	var c_under := _gull_col("dfe4e5")
	var n_prim: int = _gull_primary_count()
	for k in range(n_prim):
		var kf: float = float(k) / float(n_prim - 1)
		var root_x: float = 0.030 + 0.029 * (float(k) * 5.0 / float(n_prim - 1))
		var root := Vector3(root_x * sign, 0.0015 + 0.0004 * float(k), _gull_wing_te(secs, root_x))
		var sweep: float = lerpf(1.08, 0.17, kf)
		var dir := Vector3(cos(sweep) * sign, 0.0, -sin(sweep))
		var length: float = lerpf(0.100, 0.150, kf)
		var sidev := Vector3(-dir.z, 0.0, dir.x)
		var w_root: float = 0.034
		var w_mid: float = 0.030
		var w_tip: float = 0.007
		var p0a := root - sidev * w_root * 0.5
		var p0b := root + sidev * w_root * 0.5
		var p1a := root + dir * (length * 0.55) - sidev * w_mid * 0.5
		var p1b := root + dir * (length * 0.55) + sidev * w_mid * 0.5
		var p2a := root + dir * length - sidev * w_tip * 0.5
		var p2b := root + dir * length + sidev * w_tip * 0.5
		_gull_quad4(st, p0a, p0b, p1b, p1a, c_grey, c_grey, c_mid, c_mid, c_under, flip)
		_gull_quad4(st, p1a, p1b, p2b, p2a, c_mid, c_mid, c_black, c_black, c_under, flip)
	var mesh: ArrayMesh = st.commit()
	_mesh_cache[key] = mesh
	return mesh

# ---- 共享材质 ----
static func _water_add_material(color: Color, tex: Texture2D = null, additive: bool = true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.disable_receive_shadows = true
	m.albedo_color = color
	if tex != null:
		m.albedo_texture = tex
	return m

static func _ring_base_material() -> StandardMaterial3D:
	if not _mat_cache.has("ring_base"):
		# 水花泡沫环用 MIX 混合：加色混合在明亮海面上会整圈过曝成纯白，MIX 保持泡沫可读的层次
		_mat_cache["ring_base"] = _water_add_material(Color(0.88, 0.95, 1.0, 0.55), null, false)
	return _mat_cache["ring_base"]

static func _column_base_material() -> StandardMaterial3D:
	if not _mat_cache.has("column_base"):
		_mat_cache["column_base"] = _water_add_material(Color(0.82, 0.92, 1.0, 0.60), null, false)
	return _mat_cache["column_base"]

static func _ripple_base_material() -> StandardMaterial3D:
	if not _mat_cache.has("ripple_base"):
		_mat_cache["ripple_base"] = _water_add_material(Color(0.85, 0.93, 1.0, 0.70), _ring_tex())
	return _mat_cache["ripple_base"]

static func _drop_material() -> StandardMaterial3D:
	if not _mat_cache.has("drop"):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.vertex_color_use_as_albedo = true
		m.albedo_color = Color(0.74, 0.88, 1.0, 0.92)
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
		m.disable_receive_shadows = true
		_mat_cache["drop"] = m
	return _mat_cache["drop"]

static func _drop_mesh() -> SphereMesh:
	if not _mesh_cache.has("drop_mesh"):
		var s := SphereMesh.new()
		s.radius = 1.0
		s.height = 2.0
		s.radial_segments = 6
		s.rings = 4
		s.material = _drop_material()
		_mesh_cache["drop_mesh"] = s
	return _mesh_cache["drop_mesh"]

static func _drop_ramp() -> Gradient:
	if not _ramp_cache.has("drop_ramp"):
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.10, 0.62, 1.0])
		g.colors = PackedColorArray([Color(0.85, 0.95, 1.0, 0.0), Color(0.92, 0.98, 1.0, 0.95), Color(0.82, 0.93, 1.0, 0.72), Color(0.75, 0.88, 1.0, 0.0)])
		_ramp_cache["drop_ramp"] = g
	return _ramp_cache["drop_ramp"]

# ============================================================
# 氛围粒子（烟囱白烟 / 萤火虫 / 落花）
# ============================================================
# ------------------------------------------------------------
# Phase6 炊烟：由游戏内模拟时钟驱动（main 每帧调用 set_sim_seconds）
# 窗口 11:00-13:00 / 17:00-19:00 发射，其余时间停止新粒子并让已存在的烟自然消散；
# 进入窗口用 SMOKE_RAMP_SECONDS 模拟秒渐变增强，边界精确到秒。
# 控制器只创建一次（同一 parent 下幂等复用），时间更新是纯状态更新、不新建发射器。
# ------------------------------------------------------------
const SMOKE_DAY_SECONDS := 86400.0
const SMOKE_RAMP_SECONDS := 1.5
const SMOKE_WINDOW_A_START := 11.0 * 3600.0
const SMOKE_WINDOW_A_END := 13.0 * 3600.0
const SMOKE_WINDOW_B_START := 17.0 * 3600.0
const SMOKE_WINDOW_B_END := 19.0 * 3600.0

## 双时间窗判定：sim_seconds = 游戏内当天秒（0..86400），边界左闭右开。
static func is_smoke_window(sim_seconds: float) -> bool:
	var t: float = fposmod(sim_seconds, SMOKE_DAY_SECONDS)
	return (t >= SMOKE_WINDOW_A_START and t < SMOKE_WINDOW_A_END) \
		or (t >= SMOKE_WINDOW_B_START and t < SMOKE_WINDOW_B_END)

static func smoke_time_label(sim_seconds: float) -> String:
	var t: float = fposmod(sim_seconds, SMOKE_DAY_SECONDS)
	var total: int = int(floor(t))
	var h: int = int(total / 3600) % 24
	var m: int = (total / 60) % 60
	var s: int = total % 60
	return "%02d:%02d:%02d" % [h, m, s]

class ChimneySmoke extends Node3D:
	var particles: GPUParticles3D = null
	var mat: StandardMaterial3D = null
	var created_count := 1
	var _last_sim := -1.0
	var _in_window := false
	var _ramp := 0.0
	var _ratio := 0.0
	var _emitting := false
	var _time_label := ""

	func _exit_tree() -> void:
		IsleFx._smoke_unregister(self)

	## main 每帧调用；sim_seconds = 游戏内当天秒（0..86400），不用系统时间/独立计时器。
	func set_sim_seconds(sim_seconds: float) -> void:
		if particles == null or not is_instance_valid(particles):
			return
		var t: float = fposmod(sim_seconds, IsleFx.SMOKE_DAY_SECONDS)
		var first: bool = _last_sim < 0.0
		var dt := 0.0
		if not first:
			dt = t - _last_sim
			if dt < -1.0:
				dt += IsleFx.SMOKE_DAY_SECONDS
			dt = maxf(dt, 0.0)
		_last_sim = t
		var in_win: bool = IsleFx.is_smoke_window(t)
		# 时间跳转（跨日 / scrubber 拖拽 / 重载首帧）直接给满强度，正常播放则渐变增强
		var jump: bool = first or dt > 30.0
		if in_win:
			if not _in_window:
				_ramp = IsleFx.SMOKE_RAMP_SECONDS if jump else 0.0
			_ramp = clampf(_ramp + dt, 0.0, IsleFx.SMOKE_RAMP_SECONDS)
		else:
			_ramp = 0.0
		_in_window = in_win
		_ratio = clampf(_ramp / IsleFx.SMOKE_RAMP_SECONDS, 0.0, 1.0) if in_win else 0.0
		_emitting = in_win and _ratio > 0.001
		particles.amount_ratio = _ratio
		if particles.emitting != _emitting:
			particles.emitting = _emitting
		_time_label = IsleFx.smoke_time_label(t)

	func update_smoke(sim_seconds: float) -> void:
		set_sim_seconds(sim_seconds)

	func smoke_debug() -> Dictionary:
		var emitters: Array = []
		if particles != null and is_instance_valid(particles):
			emitters.append({
				"name": String(particles.name),
				"emitting": bool(particles.emitting),
				"amount_ratio": float(particles.amount_ratio),
				"lifetime": float(particles.lifetime),
			})
		return {
			"active_window": _in_window,
			"emitting": _emitting,
			"time_label": _time_label,
			"created_count": created_count,
			"ratio": _ratio,
			"sim_seconds": _last_sim,
			"emitters": emitters,
		}

	## main.gd 自检（main.gd:2147）的兼容入口，字段与 smoke_debug() 完全一致。
	func debug_state() -> Dictionary:
		return smoke_debug()

static var _smoke_nodes: Array = []

static func _smoke_unregister(ctrl) -> void:
	_smoke_nodes.erase(ctrl)

static func _smoke_prune() -> void:
	var alive: Array = []
	for c in _smoke_nodes:
		if is_instance_valid(c):
			alive.append(c)
	_smoke_nodes = alive

## 备用入口：没有 main 引用时也可直接驱动全部已创建的炊烟（纯状态更新，不新建）。
static func update_smoke(sim_seconds: float) -> void:
	_smoke_prune()
	for c in _smoke_nodes:
		if is_instance_valid(c) and c.has_method("update_smoke"):
			c.update_smoke(sim_seconds)

static func smoke_debug() -> Dictionary:
	_smoke_prune()
	if _smoke_nodes.is_empty():
		return {
			"active_window": false, "emitting": false, "time_label": "",
			"created_count": 0, "ratio": 0.0, "sim_seconds": -1.0, "emitters": [],
		}
	return (_smoke_nodes[_smoke_nodes.size() - 1] as ChimneySmoke).smoke_debug()

static func smoke(parent: Node3D, pos: Vector3) -> Dictionary:
	# 幂等：同一 parent 下已有控制器时复用（场景重载 / 重复调用不会叠加发射器）
	if parent != null:
		var existing: Node = parent.get_node_or_null("ChimneySmokeCtrl")
		if existing != null and existing.has_method("set_sim_seconds"):
			var ctrl0: ChimneySmoke = existing as ChimneySmoke
			return {"node": ctrl0.particles, "mat": ctrl0.mat, "ctl": ctrl0, "ctrl": ctrl0}
	var ctrl := ChimneySmoke.new()
	ctrl.name = "ChimneySmokeCtrl"
	ctrl.position = pos
	var p := GPUParticles3D.new()
	p.name = "ChimneySmoke"
	p.amount = 60
	p.lifetime = 7.0
	p.preprocess = 3.0
	# 初始不发射：等 main 第一帧把模拟时钟喂进来后再按时间窗决定（避免加载画面冒烟）
	p.emitting = false
	p.position = Vector3.ZERO
	p.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 9, 6))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 14.0
	pm.initial_velocity_min = 0.60
	pm.initial_velocity_max = 1.30
	pm.gravity = Vector3(0.52, 0.12, 0.0)
	pm.scale_min = 1.10
	pm.scale_max = 2.40
	pm.angular_velocity_min = -12.0
	pm.angular_velocity_max = 12.0
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.18
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.12, 0.55, 1.0])
	grad.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.62), Color(1, 1, 1, 0.30), Color(1, 1, 1, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(1.25, 1.25)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = M.smoke_texture(64)
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.72, 0.72, 0.75, 0.72)
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.disable_receive_shadows = true
	quad.material = mat
	p.draw_pass_1 = quad
	ctrl.add_child(p)
	ctrl.particles = p
	ctrl.mat = mat
	parent.add_child(ctrl)
	_smoke_nodes.append(ctrl)
	return {"node": p, "mat": mat, "ctl": ctrl, "ctrl": ctrl}

static func fireflies(parent: Node3D, center: Vector3) -> Dictionary:
	var p := GPUParticles3D.new()
	p.name = "Fireflies"
	p.amount = 90
	p.lifetime = 9.0
	p.preprocess = 6.0
	p.emitting = false
	p.position = center
	p.visibility_aabb = AABB(Vector3(-24, -12, -24), Vector3(48, 24, 48))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.32
	pm.gravity = Vector3(0, 0.012, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(12.0, 2.4, 12.0)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.22, 0.5, 0.78, 1.0])
	grad.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.95), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0.85), Color(1, 1, 1, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.42, 0.42)
	var mat := M.additive_material(M.soft_dot_texture(64), Color(2.2, 1.9, 0.75))
	quad.material = mat
	p.draw_pass_1 = quad
	parent.add_child(p)
	return {"node": p, "mat": mat}

static func petals(parent: Node3D, pos: Vector3) -> Dictionary:
	var p := GPUParticles3D.new()
	p.name = "Petals"
	p.amount = 40
	p.lifetime = 8.0
	p.preprocess = 4.0
	p.emitting = true
	p.position = pos
	p.visibility_aabb = AABB(Vector3(-9, -12, -9), Vector3(18, 16, 18))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.15, 1.0, 0.1)
	pm.spread = 55.0
	pm.initial_velocity_min = 0.12
	pm.initial_velocity_max = 0.45
	pm.gravity = Vector3(0.26, -0.28, 0.08)
	pm.scale_min = 0.5
	pm.scale_max = 1.1
	pm.angular_velocity_min = -90.0
	pm.angular_velocity_max = 90.0
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 3.4
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	grad.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.65), Color(1, 1, 1, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.22, 0.22)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = M.soft_dot_texture(32)
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.96, 0.78, 0.74, 0.85)
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	quad.material = mat
	p.draw_pass_1 = quad
	parent.add_child(p)
	return {"node": p, "mat": mat}

# ============================================================
# 立体水花（池化，点击 / 鱼跃 / 船尾共用）
# ============================================================
class Splash extends Node3D:
	## 水花池：活跃 unit 才作为子节点挂载（get_child_count() 只统计活跃水花），
	## 空闲 unit 留在池里复用，总 unit 数与活跃数都有上限。
	const MAX_ACTIVE := 10
	const MAX_UNITS := 12

	var _units: Array = []
	var _free: Array = []
	var _created := 0
	var _rng := RandomNumberGenerator.new()
	var _inited := false

	func _ready() -> void:
		_ensure_init()

	func _ensure_init() -> void:
		if _inited:
			return
		_inited = true
		_rng.seed = 99173

	func get_state_counts() -> Dictionary:
		return {
			"active": _units.size(),
			"created": _created,
			"free": _free.size(),
			"max_active": MAX_ACTIVE,
			"max_units": MAX_UNITS,
		}

	## 退出/销毁时释放池内"已脱离场景树"的复用单元。
	## 这些单元在 _finish() 里 remove_child() 后只由 _free 数组持有（运行期计入
	## Performance.OBJECT_ORPHAN_NODE_COUNT），场景树退出/池节点销毁时父节点已不再
	## 持有它们，若不显式 free() 会在退出阶段造成 ObjectDB/RID 泄漏（T1 生命周期修复）。
	## 仅在池退出或销毁时执行，不影响运行期"只有活跃 unit 是子节点"的语义；可重复调用。
	func _exit_tree() -> void:
		_release_detached()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE:
			_release_detached()

	func _release_detached() -> void:
		for unit_v in _free:
			var unit: Dictionary = unit_v
			var root_v: Variant = unit.get("root")
			if not is_instance_valid(root_v):
				continue
			var root: Node3D = root_v as Node3D
			if root != null:
				if root.get_parent() == self:
					remove_child(root)
				root.free()
		_free.clear()

	## 通用入口：power 1.0 ≈ 普通点击，>1.6 ≈ 大鱼跃出，<0.6 ≈ 船尾小水花。
	func splash_at(p: Vector3, power: float = 1.0) -> void:
		_ensure_init()
		if _units.size() >= MAX_ACTIVE:
			return
		var unit: Dictionary = {}
		if not _free.is_empty():
			unit = _free.pop_back()
		elif _created < MAX_UNITS:
			unit = _make_unit()
		if unit.is_empty():
			return
		_activate(unit, p, clampf(power, 0.35, 2.6))
		_units.append(unit)

	func splash_click(p: Vector3) -> void:
		splash_at(p, 0.9)

	func splash_fish(p: Vector3, power: float = 1.8) -> void:
		splash_at(p, power)

	func splash_stern(p: Vector3, speed: float) -> void:
		# 船尾小水花：只保留低功率的小尺寸环，避免在船周形成刺眼的大白圈。
		var pw: float = clampf(0.26 + speed * 0.022, 0.30, 0.44)
		var before: int = _units.size()
		splash_at(p, pw)
		if _units.size() > before:
			var unit: Dictionary = _units[_units.size() - 1]
			var root: Node3D = unit["root"]
			root.scale = Vector3(0.52, 0.34, 0.52)

	func _make_unit() -> Dictionary:
		if _created >= MAX_UNITS:
			return {}
		_created += 1
		var root := Node3D.new()
		root.name = "SplashUnit"
		# 3 圈泡沫环（不同半径/高度/寿命）
		var rings: Array = []
		for i in range(3):
			var mi := MeshInstance3D.new()
			mi.name = "Ring%d" % i
			mi.mesh = IsleFx._torus_ring_mesh()
			var base: StandardMaterial3D = IsleFx._ring_base_material()
			var mat: StandardMaterial3D = base.duplicate()
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visible = false
			root.add_child(mi)
			rings.append({"node": mi, "mat": mat, "delay": 0.0, "life": 1.0, "r0": 0.4, "r1": 2.0, "y": 0.04})
		# 3 根有体积的水柱（交叉，快速升起再落下）
		var cols: Array = []
		for i in range(3):
			var mi := MeshInstance3D.new()
			mi.name = "Column%d" % i
			mi.mesh = IsleFx._column_mesh()
			var base2: StandardMaterial3D = IsleFx._column_base_material()
			var mat2: StandardMaterial3D = base2.duplicate()
			mi.material_override = mat2
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visible = false
			root.add_child(mi)
			cols.append({"node": mi, "mat": mat2, "delay": 0.0, "life": 0.5, "r": 0.3, "h": 1.4})
		# 3 组球体水滴粒子（尺寸/速度/寿命三层次）
		var drops: Array = []
		for i in range(3):
			var ps := CPUParticles3D.new()
			ps.name = "Drops%d" % i
			ps.mesh = IsleFx._drop_mesh()
			ps.one_shot = true
			ps.emitting = false
			ps.color_ramp = IsleFx._drop_ramp()
			ps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ps.visibility_aabb = AABB(Vector3(-9, -4, -9), Vector3(18, 16, 18))
			root.add_child(ps)
			drops.append(ps)
		return {"root": root, "rings": rings, "cols": cols, "particles": drops, "t": 0.0, "life": 1.5}

	func _activate(unit: Dictionary, p: Vector3, pw: float) -> void:
		var root: Node3D = unit["root"]
		root.position = Vector3(p.x, 0.03, p.z)
		root.rotation = Vector3(0.0, _rng.randf_range(0.0, TAU), 0.0)
		root.visible = true
		root.scale = Vector3.ONE
		unit["t"] = 0.0
		var max_life := 0.0
		var rings: Array = unit["rings"]
		for i in range(rings.size()):
			var info: Dictionary = rings[i]
			var mi: MeshInstance3D = info["node"]
			var mat: StandardMaterial3D = info["mat"]
			info["delay"] = 0.10 * float(i)
			info["life"] = 0.74 + 0.16 * float(i) + 0.16 * pw
			info["r0"] = (0.32 + 0.30 * pw) * (1.0 + 0.30 * float(i))
			info["r1"] = (2.05 + 1.30 * pw) * (1.0 + 0.55 * float(i))
			info["y"] = 0.03 + 0.035 * float(i)
			var s0: float = float(info["r0"])
			mi.scale = Vector3(s0, s0 * 0.42, s0)
			mi.position = Vector3(0.0, float(info["y"]), 0.0)
			mi.rotation = Vector3(0.0, _rng.randf_range(0.0, TAU), 0.0)
			mi.visible = false
			mat.albedo_color = Color(0.88, 0.95, 1.0, lerpf(0.42, 0.62, clampf((pw - 0.35) / 1.30, 0.0, 1.0)))
			max_life = maxf(max_life, float(info["delay"]) + float(info["life"]))
		var cols: Array = unit["cols"]
		for i in range(cols.size()):
			var info2: Dictionary = cols[i]
			var mi2: MeshInstance3D = info2["node"]
			var mat2: StandardMaterial3D = info2["mat"]
			info2["delay"] = 0.03 * float(i)
			info2["life"] = 0.44 + 0.10 * float(i) + 0.18 * pw
			info2["r"] = (0.15 + 0.19 * pw) * (1.0 + 0.28 * float(i))
			info2["h"] = (0.85 + 1.35 * pw) * (1.0 - 0.14 * float(i))
			mi2.rotation = Vector3(_rng.randf_range(-0.42, 0.42), _rng.randf_range(0.0, TAU), _rng.randf_range(-0.30, 0.30))
			mi2.visible = false
			mat2.albedo_color = Color(0.82, 0.92, 1.0, lerpf(0.26, 0.46, clampf((pw - 0.35) / 1.30, 0.0, 1.0)))
			max_life = maxf(max_life, float(info2["delay"]) + float(info2["life"]))
		# 水滴层次：主喷射 / 外散碎滴 / 慢速水雾（全部 3D 小球 + 重力弧线）
		var drops: Array = unit["particles"]
		_configure_drops(drops[0], int(20.0 + 26.0 * pw), 0.62 + 0.10 * pw, 0.92, 34.0, 0.9 + 2.4 * pw, 1.4 + 5.2 * pw, -15.0, 0.030 + 0.020 * pw, 0.080 + 0.050 * pw, 0.16 + 0.14 * pw, 0.30)
		_configure_drops(drops[1], int(12.0 + 18.0 * pw), 0.96 + 0.14 * pw, 0.55, 74.0, 0.5 + 0.8 * pw, 1.3 + 2.2 * pw, -10.5, 0.018, 0.048 + 0.026 * pw, 0.30 + 0.20 * pw, 0.55)
		_configure_drops(drops[2], int(8.0 + 10.0 * pw), 1.15 + 0.10 * pw, 0.35, 120.0, 0.30, 1.4, -3.0, 0.050, 0.130 + 0.090 * pw, 0.40 + 0.22 * pw, 1.10)
		unit["life"] = max_life + 0.34
		add_child(root)
		for d_v in drops:
			var ps: CPUParticles3D = d_v
			ps.emitting = false
			ps.emitting = true

	func _configure_drops(ps: CPUParticles3D, amount: int, life: float, explosiveness: float, spread: float, vmin: float, vmax: float, gravity_y: float, smin: float, smax: float, radius: float, damping: float) -> void:
		ps.amount = maxi(4, amount)
		ps.lifetime = life
		ps.explosiveness = explosiveness
		ps.randomness = 0.55
		ps.direction = Vector3(0, 1, 0)
		ps.spread = spread
		ps.initial_velocity_min = vmin
		ps.initial_velocity_max = vmax
		ps.gravity = Vector3(0.0, gravity_y, 0.0)
		ps.damping_min = damping
		ps.damping_max = damping + 0.45
		ps.scale_amount_min = smin
		ps.scale_amount_max = smax
		ps.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		ps.emission_sphere_radius = radius

	func _finish(unit: Dictionary) -> void:
		var root: Node3D = unit["root"]
		for d_v in unit["particles"]:
			var ps: CPUParticles3D = d_v
			ps.emitting = false
		for info_v in unit["rings"]:
			var info: Dictionary = info_v
			(info["node"] as MeshInstance3D).visible = false
		for info_v2 in unit["cols"]:
			var info2: Dictionary = info_v2
			(info2["node"] as MeshInstance3D).visible = false
		root.visible = false
		if root.get_parent() == self:
			remove_child(root)
		_free.append(unit)

	func update(delta: float) -> void:
		if _units.is_empty():
			return
		var alive: Array = []
		for unit_v in _units:
			var unit: Dictionary = unit_v
			unit["t"] = float(unit["t"]) + delta
			var t: float = unit["t"]
			for info_v in unit["rings"]:
				var info: Dictionary = info_v
				var mi: MeshInstance3D = info["node"]
				var mat: StandardMaterial3D = info["mat"]
				var local: float = (t - float(info["delay"])) / maxf(float(info["life"]), 0.001)
				if local <= 0.0 or local >= 1.0:
					mi.visible = false
					continue
				mi.visible = true
				var grow: float = 1.0 - pow(1.0 - local, 2.2)
				var s: float = lerpf(float(info["r0"]), float(info["r1"]), grow)
				mi.scale = Vector3(s, s * 0.42, s)
				var alpha: float = pow(1.0 - local, 1.30) * 0.62
				mat.albedo_color = Color(0.88, 0.95, 1.0, alpha)
			for info_v2 in unit["cols"]:
				var info2: Dictionary = info_v2
				var mi2: MeshInstance3D = info2["node"]
				var mat2: StandardMaterial3D = info2["mat"]
				var local2: float = (t - float(info2["delay"])) / maxf(float(info2["life"]), 0.001)
				if local2 <= 0.0 or local2 >= 1.0:
					mi2.visible = false
					continue
				mi2.visible = true
				var hf: float = sin(PI * clampf(pow(local2, 0.70), 0.0, 1.0))
				var h: float = float(info2["h"])
				var rr: float = float(info2["r"]) * (0.62 + 0.52 * hf)
				mi2.scale = Vector3(rr, maxf(h * hf, 0.02), rr)
				mi2.position = Vector3(0.0, 0.04 + h * hf * 0.5, 0.0)
				var alpha2: float = pow(1.0 - local2, 1.10) * 0.50
				mat2.albedo_color = Color(0.82, 0.92, 1.0, alpha2)
			if t >= float(unit["life"]):
				_finish(unit)
			else:
				alive.append(unit)
		_units = alive

# ============================================================
# 船尾迹（两条带状泡沫 + 船头泡沫粒子 + 船尾小水花）
# ============================================================
class Wake extends Node3D:
	const MAX_PTS := 42
	var _hist: Array = []
	var _im: ImmediateMesh
	var _mi: MeshInstance3D
	var _boat_spray: CPUParticles3D
	var _spray_mat: StandardMaterial3D
	var _mat: StandardMaterial3D
	var _t := 0.0
	var _spawn_acc := 0.0
	var _stern_acc := 0.0
	var _stern_fx = null

	func _ready() -> void:
		_ensure_init()

	func _ensure_init() -> void:
		if _im != null:
			return
		_im = ImmediateMesh.new()
		_mi = MeshInstance3D.new()
		_mi.mesh = _im
		_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_mi)
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		_mat.vertex_color_use_as_albedo = true
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_mat.disable_receive_shadows = true
		_mat.albedo_color = Color(0.80, 0.92, 1.0, 1.0)
		_spray_mat = StandardMaterial3D.new()
		_spray_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_spray_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_spray_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_spray_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_spray_mat.albedo_texture = M.soft_dot_texture(64)
		_spray_mat.albedo_color = Color(0.62, 0.78, 0.90, 0.50)
		_spray_mat.vertex_color_use_as_albedo = true
		_spray_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_spray_mat.disable_receive_shadows = true
		_boat_spray = CPUParticles3D.new()
		_boat_spray.amount = 22
		_boat_spray.lifetime = 0.7
		_boat_spray.emitting = false
		_boat_spray.direction = Vector3(0, 0.6, 0)
		_boat_spray.spread = 55.0
		_boat_spray.initial_velocity_min = 0.5
		_boat_spray.initial_velocity_max = 1.5
		_boat_spray.gravity = Vector3(0, -6.0, 0)
		_boat_spray.scale_amount_min = 0.04
		_boat_spray.scale_amount_max = 0.12
		_boat_spray.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		_boat_spray.emission_sphere_radius = 0.28
		var q := QuadMesh.new()
		q.size = Vector2(1.0, 1.0)
		q.material = _spray_mat
		_boat_spray.mesh = q
		_boat_spray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_boat_spray)
		# 船尾小水花共用同一个池化 Splash 系统（规模由 speed 决定）
		_stern_fx = IsleFx.Splash.new()
		_stern_fx.name = "SternSplash"
		add_child(_stern_fx)

	func update(delta: float, pos: Vector3, heading: float, speed: float) -> void:
		_ensure_init()
		_t += delta
		var fwd := Vector3(sin(heading), 0.0, cos(heading))
		var side := Vector3(fwd.z, 0.0, -fwd.x)
		var stern := pos - fwd * 1.55
		stern.y = 0.06
		var spd: float = maxf(speed, 0.0)
		if spd > 0.30:
			_spawn_acc += delta
			var step: float = clampf(1.15 / maxf(spd, 0.7), 0.02, 0.10)
			if _spawn_acc >= step:
				_spawn_acc = 0.0
				_hist.append({"c": stern, "s": side, "t": 0.0, "spd": spd})
				if _hist.size() > MAX_PTS:
					_hist.pop_front()
		for i in range(_hist.size() - 1, -1, -1):
			var h: Dictionary = _hist[i]
			h["t"] = float(h["t"]) + delta
			if float(h["t"]) > 7.0:
				_hist.remove_at(i)
		_boat_spray.position = pos + fwd * 1.45 + Vector3(0, 0.35, 0)
		_boat_spray.emitting = spd > 1.2
		if _boat_spray.emitting:
			_boat_spray.speed_scale = clampf(spd / 3.2, 0.55, 1.6)
		_rebuild()
		if _stern_fx != null:
			_stern_fx.update(delta)
			if spd > 1.8:
				_stern_acc += delta
				var sstep: float = clampf(1.5 / maxf(spd, 1.0), 0.55, 1.30)
				if _stern_acc >= sstep:
					_stern_acc = 0.0
					_stern_fx.splash_stern(stern - fwd * 0.25, spd)
			else:
				_stern_acc = 0.0

	func _rebuild() -> void:
		_im.clear_surfaces()
		var n := _hist.size()
		if n < 2:
			return
		_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _mat)
		for i in range(n - 1):
			var a: Dictionary = _hist[i]
			var b: Dictionary = _hist[i + 1]
			var ta: float = float(a["t"])
			var tb: float = float(b["t"])
			var sa: float = float(a["spd"])
			var sb: float = float(b["spd"])
			var wa: float = (0.30 + 1.35 * clampf(ta / 6.0, 0.0, 1.0)) * clampf(0.4 + sa / 5.0, 0.5, 1.6)
			var wb: float = (0.30 + 1.35 * clampf(tb / 6.0, 0.0, 1.0)) * clampf(0.4 + sb / 5.0, 0.5, 1.6)
			var fade_a: float = clampf(1.0 - ta / 6.5, 0.0, 1.0)
			var fade_b: float = clampf(1.0 - tb / 6.5, 0.0, 1.0)
			var alpha_a: float = pow(fade_a, 1.4) * clampf(sa / 5.0, 0.15, 1.0) * 0.40
			var alpha_b: float = pow(fade_b, 1.4) * clampf(sb / 5.0, 0.15, 1.0) * 0.40
			var ca: Vector3 = a["c"]
			var cb: Vector3 = b["c"]
			var sa_dir: Vector3 = a["s"]
			var sb_dir: Vector3 = b["s"]
			var al: Vector3 = ca + sa_dir * wa
			var ar: Vector3 = ca - sa_dir * wa
			var bl: Vector3 = cb + sb_dir * wb
			var br: Vector3 = cb - sb_dir * wb
			_add_tri(al, ar, bl, alpha_a * 0.45, alpha_b * 0.45)
			_add_tri(ar, br, bl, alpha_a * 0.45, alpha_b * 0.45)
			var il_a: Vector3 = ca + sa_dir * wa * 0.34
			var ir_a: Vector3 = ca - sa_dir * wa * 0.34
			var il_b: Vector3 = cb + sb_dir * wb * 0.34
			var ir_b: Vector3 = cb - sb_dir * wb * 0.34
			_add_tri(il_a, ir_a, il_b, alpha_a, alpha_b)
			_add_tri(ir_a, ir_b, il_b, alpha_a, alpha_b)
		_im.surface_end()

	func _add_tri(p0: Vector3, p1: Vector3, p2: Vector3, a0: float, a1: float) -> void:
		_im.surface_set_color(Color(0.86, 0.94, 1.0, a0))
		_im.surface_add_vertex(p0)
		_im.surface_set_color(Color(0.86, 0.94, 1.0, a1))
		_im.surface_add_vertex(p1)
		_im.surface_set_color(Color(0.86, 0.94, 1.0, a1))
		_im.surface_add_vertex(p2)

# ============================================================
# 涟漪 + 鱼跃（池化涟漪；五次快速点击触发小鱼）
# ============================================================
class Ripples extends Node3D:
	const MAX_ACTIVE := 24
	const MAX_UNITS := 30

	var _items: Array = []
	var _free: Array = []
	var _created := 0
	var _fish: Array = []
	var _rng := RandomNumberGenerator.new()
	var _fish_timer := 7.0
	var _t := 0.0
	var _click_times: Array = []
	var splash_cb := Callable()
	var _inited := false

	func _ready() -> void:
		_ensure_init()

	func _ensure_init() -> void:
		if _inited:
			return
		_inited = true
		_rng.seed = 424242
		_fish_timer = _rng.randf_range(7.0, 12.0)

	func get_state_counts() -> Dictionary:
		return {"ripples": _items.size(), "created": _created, "free": _free.size(), "fish": _fish.size(), "clicks": _click_times.size()}

	## 退出/销毁时释放池内"已脱离场景树"的复用 MeshInstance3D（同 Splash._release_detached 说明）。
	func _exit_tree() -> void:
		_release_detached()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE:
			_release_detached()

	func _release_detached() -> void:
		for it_v in _free:
			var it: Dictionary = it_v
			var node_v: Variant = it.get("node")
			if not is_instance_valid(node_v):
				continue
			var node: MeshInstance3D = node_v as MeshInstance3D
			if node != null:
				if node.get_parent() == self:
					remove_child(node)
				node.free()
		_free.clear()

	func ripple_at(p: Vector3, power: float = 1.0) -> void:
		_ensure_init()
		_add_ripple(p, clampf(power, 0.3, 2.4))
		_note_click(p)

	func _note_click(p: Vector3) -> void:
		_click_times.append(_t)
		while _click_times.size() > 0 and _t - float(_click_times[0]) > 2.5:
			_click_times.pop_front()
		if _click_times.size() >= 5:
			_click_times.clear()
			spawn_fish_at(p)

	func _make_ripple() -> Dictionary:
		var mi := MeshInstance3D.new()
		mi.name = "Ripple"
		mi.mesh = IsleFx._plane_xz_mesh()
		var base: StandardMaterial3D = IsleFx._ripple_base_material()
		var mat: StandardMaterial3D = base.duplicate()
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return {"node": mi, "mat": mat, "t": 0.0, "life": 2.4, "power": 1.0, "radius": 4.0}

	func _add_ripple(p: Vector3, power: float) -> void:
		if _items.size() >= MAX_ACTIVE:
			return
		var it: Dictionary = {}
		if not _free.is_empty():
			it = _free.pop_back()
		elif _created < MAX_UNITS:
			it = _make_ripple()
			_created += 1
		if it.is_empty():
			return
		var mi: MeshInstance3D = it["node"]
		mi.position = Vector3(p.x, 0.07, p.z)
		mi.rotation = Vector3.ZERO
		mi.scale = Vector3(0.7, 1.0, 0.7)
		mi.visible = true
		it["t"] = 0.0
		it["power"] = power
		it["radius"] = 2.1 + 2.9 * power
		add_child(mi)
		_items.append(it)

	func _fire_splash(p: Vector3, power: float) -> void:
		if splash_cb.is_valid():
			splash_cb.call(p, power)

	func spawn_fish_at(p: Vector3, dir: Vector3 = Vector3.ZERO) -> void:
		_ensure_init()
		if _fish.size() >= 3:
			return
		var dirv: Vector3 = dir
		if dirv.length_squared() < 0.001:
			dirv = Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0))
		if dirv.length_squared() < 0.001:
			dirv = Vector3(1.0, 0.0, 0.0)
		dirv = dirv.normalized()
		var start := Vector3(p.x, 0.05, p.z)
		var node := Node3D.new()
		node.name = "Fish"
		var body := MeshInstance3D.new()
		body.mesh = IsleFx._fish_body_mesh()
		body.material_override = M.toon_material(Color("9fb2c4"), {"bands": 3.0, "rim": 0.35})
		body.scale = Vector3(0.121, 0.121, 0.352)
		body.position = Vector3(0.0, 0.02, 0.0)
		node.add_child(body)
		var tail := MeshInstance3D.new()
		tail.mesh = IsleFx._fish_tail_mesh()
		tail.material_override = body.material_override
		tail.position = Vector3(0.0, 0.02, -0.36)
		tail.rotation.x = PI * 0.5
		node.add_child(tail)
		add_child(node)
		node.position = start
		var dist: float = _rng.randf_range(2.2, 4.0)
		_fish.append({
			"node": node, "t": 0.0, "start": start, "dir": dirv,
			"len": dist, "h": _rng.randf_range(1.0, 2.0),
			"dur": _rng.randf_range(0.95, 1.35),
			"land": Vector3(start.x + dirv.x * dist, 0.05, start.z + dirv.z * dist),
		})
		_add_ripple(start, 1.35)
		_fire_splash(start, 1.05 + _rng.randf() * 0.5)

	func spawn_fish_random() -> void:
		_ensure_init()
		var a: float = _rng.randf_range(0.0, TAU)
		var r: float = (M.coast_radius(a) + _rng.randf_range(-1.5, 3.0))
		var p := Vector3(cos(a) * r, 0.05, sin(a) * r)
		var tangent := Vector3(-sin(a), 0.0, cos(a)) * (1.0 if _rng.randf() > 0.5 else -1.0)
		spawn_fish_at(p, tangent)

	func _spawn_fish() -> void:
		spawn_fish_random()

	func _update_fish(delta: float) -> void:
		if _fish.is_empty():
			return
		var alive: Array = []
		for f_v in _fish:
			var f: Dictionary = f_v
			f["t"] = float(f["t"]) + delta / maxf(float(f["dur"]), 0.05)
			var ft: float = float(f["t"])
			var node: Node3D = f["node"]
			if ft >= 1.0:
				var land: Vector3 = f["land"]
				_fire_splash(land, 1.45)
				_add_ripple(land, 1.6)
				if node.get_parent() == self:
					remove_child(node)
				node.free()
			else:
				var start: Vector3 = f["start"]
				var dirv: Vector3 = f["dir"]
				node.position = start + dirv * (float(f["len"]) * ft) + Vector3(0.0, float(f["h"]) * sin(PI * ft) + 0.05, 0.0)
				node.rotation.x = cos(PI * ft) * -0.85
				node.rotation.y = atan2(dirv.x, dirv.z)
				alive.append(f)
		_fish = alive

	func update(delta: float, sun_alt: float = 12.0) -> void:
		_ensure_init()
		_t += delta
		var alive: Array = []
		for it_v in _items:
			var it: Dictionary = it_v
			it["t"] = float(it["t"]) + delta / float(it["life"])
			var k: float = float(it["t"])
			var mi: MeshInstance3D = it["node"]
			var mat: StandardMaterial3D = it["mat"]
			if k >= 1.0:
				mi.visible = false
				if mi.get_parent() == self:
					remove_child(mi)
				_free.append(it)
				continue
			var s: float = lerpf(0.7, float(it["radius"]), sqrt(clampf(k, 0.0, 1.0)))
			mi.scale = Vector3(s, 1.0, s)
			mat.albedo_color = Color(0.85, 0.93, 1.0, pow(1.0 - k, 1.25) * 0.70)
			alive.append(it)
		_items = alive
		_update_fish(delta)
		_fish_timer -= delta
		if _fish_timer <= 0.0:
			_fish_timer = _rng.randf_range(9.0, 17.0)
			if sun_alt > -2.0 and _fish.size() < 2:
				_spawn_fish()

# ============================================================
# 飞鸟（10 只，昼夜状态机 + 栖枝预订/占用互斥 + 空中分离）
# ============================================================
class BirdFlock extends Node3D:
	enum State { FLY, TAKEOFF, LANDING, PERCH }

	var _birds: Array = []
	var _perches: Array = []
	var _perch_used: Dictionary = {}
	var _rng := RandomNumberGenerator.new()
	# 纯视觉随机（扇翅相位/滑翔时长）单独一条流，避免扰动状态机随机序列
	var _vis_rng := RandomNumberGenerator.new()
	var _t := 0.0
	var _inited := false
	var _night := false
	var _night_known := false
	var _min_air_dist := -1.0
	var _perch_conflicts := 0
	var _takeoffs_total := 0
	var _landings_total := 0
	var _takeoffs_night := 0
	var _check_acc := 0.0
	# ---- P7：生态节奏（黄昏归栖 + 船鸟联动）。只复用现有状态机并补最少事件状态，不另建时钟/状态机。 ----
	const ROOST_NONE := 0
	const ROOST_ACTIVE := 1
	const ROOST_NIGHT := 2
	const DUSK_START_ALT := 4.0       # 太阳高度向下穿过该值视为黄昏启动候选（度，isle_astro 太阳高度）
	const DUSK_CANCEL_ALT := 6.0      # 时间回拖到白天时取消未完成归栖计划（不重演已消费事件）
	const ROOST_GAP_MIN := 0.7        # 分批归栖最小间隔（真实帧时间秒）
	const ROOST_GAP_MAX := 1.5
	const BOAT_RESP_SHIFT := 10.0     # 船鸟联动：轨道中心朝船方位的水平偏移上限（米）
	const BOAT_RESP_DROP := 4.0       # 船鸟联动：轨道高度下调上限（米）
	const BOAT_RESP_UP_TIME := 1.8    # 响应权重上升时间
	const BOAT_RESP_DOWN_TIME := 2.4  # 响应权重回落时间
	const BOAT_RESP_DUR_MIN := 9.0
	const BOAT_RESP_DUR_MAX := 15.0
	const BOAT_RESP_MIN_ALT := 8.0    # 太阳高度低于此值（黄昏/夜间）不响应船只
	var _roost_state: int = ROOST_NONE
	var _roost_day: int = -999999
	var _roost_timer := 0.0
	var _roost_landings := 0
	var _roost_starts := 0
	var _roost_skips := 0
	var _roost_skip_reason := ""
	var _sun_prev := 0.0
	var _sun_prev_valid := false
	var _boat_trip_handled := -1
	var _boat_pass_attempts := 0
	var _boat_pass_birds := 0
	var _boat_skip_reason := ""
	var _eco_paused := false

	func _ready() -> void:
		_ensure_ready()

	func _ensure_ready() -> void:
		if _inited:
			return
		_inited = true
		_rng.seed = 55021
		_vis_rng.seed = 77123

	# ---------------- public API ----------------
	## 由 main 传入 world + cottage 合并后的栖枝数组；元素可为
	## Dictionary{id, pos, facing?, radius?, kind?, slots?} 或 Vector3。
	func setup(perches: Array) -> void:
		_ensure_ready()
		_perches = _normalize_perches(perches)
		_ensure_bird_nodes(IsleFx.BIRD_COUNT)
		_reseat_all(true)

	## 运行时替换栖枝（旧目标失效重选）。
	func set_perches(perches: Array) -> void:
		_ensure_ready()
		_perches = _normalize_perches(perches)
		_reseat_all(false)

	func get_perches() -> Array:
		return _perches

	func get_state_counts() -> Dictionary:
		var flying := 0
		var takeoff := 0
		var landing := 0
		var perched := 0
		var waiting := 0
		for b_v in _birds:
			var b: Dictionary = b_v
			var st: int = int(b["state"])
			if st == State.FLY:
				flying += 1
				if bool(b["waiting"]):
					waiting += 1
			elif st == State.TAKEOFF:
				takeoff += 1
			elif st == State.LANDING:
				landing += 1
			else:
				perched += 1
		var slots := 0
		for p_v in _perches:
			var p: Dictionary = p_v
			slots += int(p["slots"])
		var used := 0
		for k_v in _perch_used.keys():
			var arr: Array = _perch_used[k_v]
			used += arr.size()
		var airborne: int = flying + takeoff + landing
		return {
			"birds": _birds.size(),
			"flying": flying,
			"takeoff": takeoff,
			"landing": landing,
			"perched": perched,
			"airborne": airborne,
			"waiting": waiting,
			"night": _night,
			"target_flying": IsleFx.BIRD_DAY_TARGET,
			"fly_ratio": float(airborne) / maxf(float(_birds.size()), 1.0),
			"flying_ratio": float(flying) / maxf(float(_birds.size()), 1.0),
			"perch_count": _perches.size(),
			"perch_slots": slots,
			"perch_used": used,
			"perch_conflicts": _current_perch_conflicts(),
			"air_min_dist": _min_air_dist,
			"takeoffs": _takeoffs_total,
			"landings": _landings_total,
			"takeoffs_night": _takeoffs_night,
			"roost_state": _roost_state,
			"roost_day": _roost_day,
			"roost_landings": _roost_landings,
			"roost_starts": _roost_starts,
			"roost_skips": _roost_skips,
			"boat_trip_handled": _boat_trip_handled,
			"boat_pass_attempts": _boat_pass_attempts,
		}

	## P7：生态事件可观测状态（只读；探针 / --p7shots / 日志使用）。只含原生类型，便于 JSON.stringify。
	func debug_eco_state() -> Dictionary:
		return {
			"night": _night,
			"roost_state": _roost_state,
			"roost_day": _roost_day,
			"roost_timer": _roost_timer,
			"roost_landings": _roost_landings,
			"roost_starts": _roost_starts,
			"roost_skips": _roost_skips,
			"roost_skip_reason": _roost_skip_reason,
			"boat_trip_handled": _boat_trip_handled,
			"boat_pass_attempts": _boat_pass_attempts,
			"boat_pass_birds": _boat_pass_birds,
			"boat_skip_reason": _boat_skip_reason,
			"paused": _eco_paused,
		}

	## P7：每鸟状态快照（只读；探针验证「不瞬移 / 栖点互斥 / 响应后恢复」）。
	func debug_snapshot() -> Array:
		var out: Array = []
		for b_v in _birds:
			var b: Dictionary = b_v
			var node: Node3D = b["node"]
			out.append({
				"index": _bird_index(b),
				"state": int(b["state"]),
				"waiting": bool(b.get("waiting", false)),
				"perch_id": String(b.get("perch_id", "")),
				"perch_slot": int(b.get("perch_slot", -1)),
				"timer": float(b.get("timer", 0.0)),
				"resp_timer": float(b.get("resp_timer", 0.0)),
				"resp_w": float(b.get("resp_w", 0.0)),
				"pos": node.position,
			})
		return out

	## P7：帆船经过近海航段时的一次性海鸥联动。trip 为 main 的航次号；
	## 同一次航行最多启动一次（成功或跳过都记为已处理，船在范围内持续移动时不会逐帧重试）。
	## 只调用既有起飞/飞行/降落接口，不新建飞行 AI。返回 {ok, birds, reason, trip}。
	func on_boat_shore_pass(trip: int, boat_pos: Vector3, sun_alt: float) -> Dictionary:
		_ensure_ready()
		_boat_pass_attempts += 1
		if _birds.is_empty():
			_boat_skip_reason = "no_birds"
			return {"ok": false, "birds": 0, "reason": "no_birds", "trip": trip}
		if trip == _boat_trip_handled:
			_boat_skip_reason = "trip_done"
			return {"ok": false, "birds": 0, "reason": "trip_done", "trip": trip}
		_boat_trip_handled = trip
		if _night:
			_boat_skip_reason = "night"
			return {"ok": false, "birds": 0, "reason": "night", "trip": trip}
		if _roost_state != ROOST_NONE:
			_boat_skip_reason = "dusk_roost"
			return {"ok": false, "birds": 0, "reason": "dusk_roost", "trip": trip}
		if sun_alt < BOAT_RESP_MIN_ALT:
			_boat_skip_reason = "low_sun"
			return {"ok": false, "birds": 0, "reason": "low_sun", "trip": trip}
		# 候选：已停栖的鸟优先（从原栖点正常起飞）；不足时用可安全打断的空闲巡航个体。
		var perched: Array = []
		var flying: Array = []
		for b_v in _birds:
			var b: Dictionary = b_v
			var st: int = int(b["state"])
			if st == State.PERCH:
				if float(b.get("resp_delay", 0.0)) > 0.0:
					continue
				perched.append(b)
			elif st == State.FLY and not bool(b.get("waiting", false)):
				if _t - float(b.get("fly_since", -100.0)) < 1.2:
					continue
				flying.append(b)
		var pool: Array = perched if not perched.is_empty() else flying
		if pool.is_empty():
			_boat_skip_reason = "no_candidate"
			return {"ok": false, "birds": 0, "reason": "no_candidate", "trip": trip}
		var count := 1
		if pool.size() >= 2 and _rng.randf() < 0.62:
			count = 2
		var boat_az: float = atan2(boat_pos.z, boat_pos.x)
		var picked := 0
		var guard := 0
		while picked < count and guard < 10 and not pool.is_empty():
			guard += 1
			var pick_i: int = _rng.randi_range(0, pool.size() - 1)
			var b: Dictionary = pool[pick_i]
			pool.remove_at(pick_i)
			b["resp_az"] = boat_az + _rng.randf_range(-0.16, 0.16)
			b["resp_timer"] = _rng.randf_range(BOAT_RESP_DUR_MIN, BOAT_RESP_DUR_MAX)
			b["resp_w"] = 0.0
			if int(b["state"]) == State.PERCH:
				# 第二只错峰起飞：延迟到期后由 _update_perched 走既有起飞接口
				b["resp_delay"] = _rng.randf_range(0.5, 1.1) if picked > 0 else 0.0
				if float(b["resp_delay"]) <= 0.0:
					_begin_takeoff(b)
			else:
				b["resp_delay"] = _rng.randf_range(0.4, 0.9) if picked > 0 else 0.0
			picked += 1
		if picked <= 0:
			_boat_skip_reason = "no_candidate"
			return {"ok": false, "birds": 0, "reason": "no_candidate", "trip": trip}
		_boat_pass_birds = picked
		_boat_skip_reason = ""
		print("[ECO] boat_pass trip=", trip, " birds=", picked, " boat_az=", snappedf(boat_az, 0.01), " sun_alt=", snappedf(sun_alt, 0.1))
		return {"ok": true, "birds": picked, "reason": "ok", "trip": trip}

	# ---------------- perches ----------------
	func _normalize_perches(raw_perches: Array) -> Array:
		var out: Array = []
		var idx := 0
		for raw in raw_perches:
			var d: Dictionary = {}
			var t: int = typeof(raw)
			if t == TYPE_DICTIONARY:
				var rd: Dictionary = raw
				var pos_v = rd.get("pos", rd.get("position", null))
				if typeof(pos_v) != TYPE_VECTOR3:
					idx += 1
					continue
				var pos: Vector3 = pos_v
				if not IsleFx._finite_vec(pos):
					idx += 1
					continue
				var facing_v = rd.get("facing", null)
				var radius_v: float = float(rd.get("radius", 1.25))
				# Phase6：radius<=0 表示该面太窄/不可停栖（窄瓦、烟囱窄面等），整条跳过；
				# 旧逻辑把它 clamp 成 0.15 会让鸟“贴”在不可能落脚的地方。
				if radius_v <= 0.0:
					idx += 1
					continue
				# Phase6：停栖面法线（世界空间，向上为 +Y）；缺省 UP 保持旧栖枝行为。
				var normal_v = rd.get("normal", rd.get("up", null))
				var nrm := Vector3.UP
				var has_normal := false
				if typeof(normal_v) == TYPE_VECTOR3:
					var nv: Vector3 = normal_v
					if not IsleFx._finite_vec(nv):
						idx += 1
						continue
					if nv.length_squared() > 0.000001:
						nrm = nv.normalized()
						has_normal = true
				elif normal_v != null:
					idx += 1
					continue
				# slope = 停栖面与水平面夹角（弧度）；也允许直接传“度”（>PI 且 <=180 视为度）
				var slope_v: float = absf(float(rd.get("slope", 0.0)))
				if slope_v > PI:
					if slope_v <= 180.0:
						slope_v = deg_to_rad(slope_v)
					else:
						idx += 1
						continue
				if has_normal and slope_v <= 0.0:
					slope_v = acos(clampf(nrm.y, -1.0, 1.0))
				# 朝下的面或过陡的面不能停栖（法线 y<0.35 或坡角>60°）
				if nrm.y < IsleFx.PERCH_MIN_NORMAL_Y or slope_v > IsleFx.PERCH_MAX_SLOPE:
					idx += 1
					continue
				var slots_v: int = int(rd.get("slots", rd.get("capacity", 0)))
				var id_v: String = String(rd.get("id", "perch_%d" % idx))
				var kind_v: String = String(rd.get("kind", "generic"))
				d = {
					"id": id_v,
					"pos": pos,
					"facing": _facing_yaw(facing_v, pos),
					"radius": radius_v,
					"kind": kind_v,
					"slots": slots_v,
					"normal": nrm,
					"slope": slope_v,
				}
			elif t == TYPE_VECTOR3:
				var pos2: Vector3 = raw
				if not IsleFx._finite_vec(pos2):
					idx += 1
					continue
				d = {
					"id": "perch_%d" % idx,
					"pos": pos2,
					"facing": _facing_yaw(null, pos2),
					"radius": 1.25,
					"kind": "generic",
					"slots": 0,
					"normal": Vector3.UP,
					"slope": 0.0,
				}
			else:
				idx += 1
				continue
			if int(d["slots"]) <= 0:
				d["slots"] = clampi(int(floor(float(d["radius"]) / 0.62)), 1, 6)
			out.append(d)
			idx += 1
		_expand_perch_slots(out)
		return out

	func _expand_perch_slots(out: Array) -> void:
		if out.is_empty():
			return
		var total := 0
		for p_v in out:
			var p: Dictionary = p_v
			total += int(p["slots"])
		# 总槽位不足鸟数时，给槽位最少的栖枝逐个扩容（同一栖枝支持多槽位）
		while total < IsleFx.BIRD_COUNT:
			var best_i := -1
			var best_slots := 99
			for i in range(out.size()):
				var slots_i: int = int(out[i]["slots"])
				if slots_i < 6 and slots_i < best_slots:
					best_slots = slots_i
					best_i = i
			if best_i < 0:
				break
			out[best_i]["slots"] = int(out[best_i]["slots"]) + 1
			total += 1

	func _facing_yaw(facing_v, pos: Vector3) -> float:
		# 统一朝向约定：模型 +Z 为前向，yaw = atan2(v.x, v.z)。
		# world.gd / cottage.gd 传入的 facing 是世界空间方向向量（鸟面朝的方向）。
		var t: int = typeof(facing_v)
		if t == TYPE_VECTOR3:
			var f: Vector3 = facing_v
			if f.length_squared() > 0.0001:
				return atan2(f.x, f.z)
		elif t == TYPE_FLOAT or t == TYPE_INT:
			# 旧 P4 探针/旧数据可能直接给 yaw 浮点数，保持原语义
			return float(facing_v)
		# 缺省：朝向岛屿中心（world.gd 的灯塔/码头等 facing 即指向中心）
		var to_center := Vector3(-pos.x, 0.0, -pos.z)
		if to_center.length_squared() < 0.0001:
			return 0.0
		to_center = to_center.normalized()
		return atan2(to_center.x, to_center.z)

	func _slot_position(perch: Dictionary, slot: int) -> Vector3:
		var n: int = int(perch["slots"])
		var yaw: float = float(perch["facing"])
		var up: Vector3 = _perch_normal(perch)
		var off: float = (float(slot) - (float(n) - 1.0) * 0.5) * 0.98
		# 横向沿停栖面展开：lateral = up × 前向；面接近垂直时退化为水平侧向
		var lateral: Vector3 = up.cross(Vector3(sin(yaw), 0.0, cos(yaw)))
		if lateral.length_squared() < 0.000001:
			lateral = Vector3(cos(yaw), 0.0, -sin(yaw))
		lateral = lateral.normalized()
		var base: Vector3 = perch["pos"]
		# 脚底沿法线抬起 PERCH_FOOT_LIFT，避免贴面 z-fighting/穿瓦
		return base + lateral * off + up * IsleFx.PERCH_FOOT_LIFT

	func _perch_normal(perch: Dictionary) -> Vector3:
		var n_v = perch.get("normal", null)
		if typeof(n_v) == TYPE_VECTOR3:
			var n: Vector3 = n_v
			if n.length_squared() > 0.000001:
				return n.normalized()
		return Vector3.UP

	## 身体朝向基：+Y 对齐停栖面法线（倾角超过 BODY_TILT_MAX 时夹紧），+Z 为鸟朝向。
	## 鸟节点原点在脚底，因此直接把该基赋给 node.basis 即“脚踩在面上、身体垂直于面”。
	func _perch_basis(perch: Dictionary) -> Basis:
		var n: Vector3 = _perch_normal(perch)
		var up_axis: Vector3 = n
		if acos(clampf(n.y, -1.0, 1.0)) > IsleFx.BODY_TILT_MAX:
			var axis: Vector3 = Vector3.UP.cross(n)
			if axis.length_squared() > 0.000001:
				up_axis = Vector3.UP.rotated(axis.normalized(), IsleFx.BODY_TILT_MAX)
			else:
				up_axis = Vector3.UP
			up_axis = up_axis.normalized()
		var yaw: float = float(perch["facing"])
		var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
		# 前向投影到切平面并归一，保证 +Z 与 +Y 正交
		fwd = fwd - up_axis * fwd.dot(up_axis)
		if fwd.length_squared() < 0.000001:
			fwd = Vector3(sin(yaw + PI * 0.5), 0.0, cos(yaw + PI * 0.5))
			fwd = fwd - up_axis * fwd.dot(up_axis)
		fwd = fwd.normalized()
		var right: Vector3 = up_axis.cross(fwd)
		if right.length_squared() < 0.000001:
			right = Vector3.RIGHT
		return Basis(right.normalized(), up_axis, fwd)

	func _apply_perch_pose(b: Dictionary, perch: Dictionary) -> void:
		var node: Node3D = b["node"]
		node.basis = _perch_basis(perch)

	func _find_perch(id: String) -> Dictionary:
		for p_v in _perches:
			var p: Dictionary = p_v
			if String(p["id"]) == id:
				return p
		return {}

	func _find_free_slot(from_pos: Vector3) -> Dictionary:
		var best: Dictionary = {}
		var best_d := 1.0e30
		for p_v in _perches:
			var p: Dictionary = p_v
			var used: Array = _perch_used.get(String(p["id"]), [])
			var slots: int = int(p["slots"])
			for s in range(slots):
				if used.has(s):
					continue
				var pos: Vector3 = _slot_position(p, s)
				var d: float = pos.distance_squared_to(from_pos)
				if d < best_d:
					best_d = d
					best = {"id": p["id"], "slot": s, "pos": pos}
		return best

	func _find_free_slot_kind(from_pos: Vector3, kind: String) -> Dictionary:
		# 只在指定 kind 的栖枝空位里选（用于初始停栖把少数海鸥安排到屋脊）
		var best: Dictionary = {}
		var best_d := 1.0e30
		for p_v in _perches:
			var p: Dictionary = p_v
			if String(p.get("kind", "")) != kind:
				continue
			var used: Array = _perch_used.get(String(p["id"]), [])
			var slots: int = int(p["slots"])
			for s in range(slots):
				if used.has(s):
					continue
				var pos: Vector3 = _slot_position(p, s)
				var d: float = pos.distance_squared_to(from_pos)
				if d < best_d:
					best_d = d
					best = {"id": p["id"], "slot": s, "pos": pos}
		return best

	func _reserve_slot(id: String, slot: int) -> void:
		if not _perch_used.has(id):
			_perch_used[id] = []
		var arr: Array = _perch_used[id]
		if arr.has(slot):
			_perch_conflicts += 1
			return
		arr.append(slot)

	func _release_perch(b: Dictionary) -> void:
		var id: String = String(b["perch_id"])
		if id != "" and _perch_used.has(id):
			var arr: Array = _perch_used[id]
			arr.erase(int(b["perch_slot"]))
		b["perch_id"] = ""
		b["perch_slot"] = -1
		b["perch_pos"] = Vector3.ZERO

	func _clear_allocations() -> void:
		_perch_used.clear()

	func _current_perch_conflicts() -> int:
		var conflicts := 0
		var seen: Dictionary = {}
		for b_v in _birds:
			var b: Dictionary = b_v
			var st: int = int(b["state"])
			if st != State.PERCH and st != State.LANDING:
				continue
			var id: String = String(b["perch_id"])
			if id == "":
				continue
			var key: String = "%s#%d" % [id, int(b["perch_slot"])]
			if seen.has(key):
				conflicts += 1
			seen[key] = true
		return conflicts

	# ---------------- birds ----------------
	func _ensure_bird_nodes(n: int) -> void:
		if _birds.size() == n:
			return
		for b_v in _birds:
			var b: Dictionary = b_v
			var node: Node3D = b["node"]
			if node.get_parent() == self:
				remove_child(node)
			node.free()
		_birds.clear()
		for i in range(n):
			_birds.append(_make_bird(i))

	func _make_bird(idx: int) -> Dictionary:
		var node := Node3D.new()
		node.name = "Bird%d" % idx
		add_child(node)
		var mats: Dictionary = IsleFx._bird_materials()
		var vc: ShaderMaterial = mats["vc"]
		# 节点原点在脚底（y=0 即栖枝表面），模型局部 +Z 为喙/前向。
		var body := MeshInstance3D.new()
		body.name = "body"
		body.mesh = IsleFx._gull_body_mesh()
		body.material_override = vc
		node.add_child(body)
		var head := MeshInstance3D.new()
		head.name = "head"
		head.mesh = IsleFx._gull_head_mesh()
		head.material_override = vc
		head.position = Vector3(0.0, 0.262, 0.150)
		node.add_child(head)
		var eyes := MeshInstance3D.new()
		eyes.name = "eyes"
		eyes.mesh = IsleFx._gull_eyes_mesh()
		eyes.material_override = vc
		head.add_child(eyes)
		var beak := MeshInstance3D.new()
		beak.name = "beak"
		beak.mesh = IsleFx._cone_mesh()
		beak.material_override = mats["beak"]
		beak.scale = Vector3(0.026, 0.140, 0.024)
		beak.position = Vector3(0.0, -0.012, 0.082)
		beak.rotation.x = PI * 0.5 + 0.09
		head.add_child(beak)
		var tail := MeshInstance3D.new()
		tail.name = "tail"
		tail.mesh = IsleFx._gull_tail_mesh()
		tail.material_override = vc
		# 尾根放在躯干后缘内部（躯干后缘 z=-0.180），尾羽网格自带 z 0→-0.235 的延伸。
		tail.position = Vector3(0.0, 0.196, -0.132)
		node.add_child(tail)
		var legs := MeshInstance3D.new()
		legs.name = "legs"
		legs.mesh = IsleFx._gull_legs_mesh()
		legs.material_override = vc
		node.add_child(legs)
		# 双翼：翼根(肩) → 内翼 → 肘 → 外翼(含初级飞羽)，左右镜像。
		var wing_l := Node3D.new()
		wing_l.name = "wing_l"
		wing_l.position = Vector3(-0.056, 0.236, 0.020)
		node.add_child(wing_l)
		var wl_in := MeshInstance3D.new()
		wl_in.name = "wing_l_inner"
		wl_in.mesh = IsleFx._gull_wing_inner_mesh(-1.0)
		wl_in.material_override = vc
		wing_l.add_child(wl_in)
		var elbow_l := Node3D.new()
		elbow_l.name = "elbow_l"
		elbow_l.position = Vector3(-0.230, 0.0, 0.0)
		wing_l.add_child(elbow_l)
		var wl_out := MeshInstance3D.new()
		wl_out.name = "wing_l_outer"
		wl_out.mesh = IsleFx._gull_wing_outer_mesh(-1.0)
		wl_out.material_override = vc
		wl_out.set_meta("primary_count", IsleFx._gull_primary_count())
		elbow_l.add_child(wl_out)
		var wing_r := Node3D.new()
		wing_r.name = "wing_r"
		wing_r.position = Vector3(0.056, 0.236, 0.020)
		node.add_child(wing_r)
		var wr_in := MeshInstance3D.new()
		wr_in.name = "wing_r_inner"
		wr_in.mesh = IsleFx._gull_wing_inner_mesh(1.0)
		wr_in.material_override = vc
		wing_r.add_child(wr_in)
		var elbow_r := Node3D.new()
		elbow_r.name = "elbow_r"
		elbow_r.position = Vector3(0.230, 0.0, 0.0)
		wing_r.add_child(elbow_r)
		var wr_out := MeshInstance3D.new()
		wr_out.name = "wing_r_outer"
		wr_out.mesh = IsleFx._gull_wing_outer_mesh(1.0)
		wr_out.material_override = vc
		wr_out.set_meta("primary_count", IsleFx._gull_primary_count())
		elbow_r.add_child(wr_out)
		return {
			"node": node,
			"wing_l": wing_l,
			"wing_r": wing_r,
			"state": State.PERCH,
			"timer": 0.0,
			"t": 0.0,
			"dur": 0.8,
			"from_p": Vector3.ZERO,
			"to_p": Vector3.ZERO,
			"perch_id": "",
			"perch_slot": -1,
			"perch_pos": Vector3.ZERO,
			"waiting": false,
			"phase": _rng.randf_range(0.0, TAU),
			"flap_phase": _vis_rng.randf_range(0.0, TAU),
			"radius": 15.0 + float(idx % 5) * 2.2,
			"height": 14.0 + float(idx % 4) * 2.4,
			"speed": 0.15 + float(idx % 3) * 0.022 + _rng.randf_range(0.0, 0.02),
			"dir": 1.0 if idx % 2 == 0 else -1.0,
			"index": idx,
			"head": head,
			"tail": tail,
			"legs": legs,
			"elbow_l": elbow_l,
			"elbow_r": elbow_r,
			"prev_pos": Vector3.ZERO,
			"prev_vel": Vector3.ZERO,
			"teleport": true,
			"fold": 1.0,
			"flap_env": 0.0,
			"gliding": false,
			"glide_timer": _vis_rng.randf_range(1.0, 2.5),
			"flap_clock": 0.0,
			"vis_state": -1,
			"motion_pos": Vector3.ZERO,
		}

	func _bird_index(b: Dictionary) -> int:
		return int(b.get("index", 0))

	func _set_fly(b: Dictionary, idx: int) -> void:
		var angle: float = _rng.randf_range(0.0, TAU)
		var node: Node3D = b["node"]
		b["state"] = State.FLY
		b["waiting"] = false
		b["phase"] = angle - _t * float(b["speed"]) * float(b["dir"])
		node.position = _orbit_point(b, angle)
		b["prev_pos"] = node.position
		b["prev_vel"] = Vector3.ZERO
		b["teleport"] = true
		b["timer"] = _rng.randf_range(1.0, 4.0)
		b["fly_since"] = _t

	func _reseat_all(initial: bool) -> void:
		_clear_allocations()
		for b_v in _birds:
			var b: Dictionary = b_v
			_release_perch(b)
			b["waiting"] = false
			if initial:
				# 白天场景初始 ≈60% 已在空中，其余先停在栖枝上
				if _bird_index(b) < 4:
					b["state"] = State.PERCH
				else:
					b["state"] = State.FLY
					_set_fly(b, _bird_index(b))
			else:
				# 栖枝整体替换：已在空中的保持飞行，正在降落的取消重选。
				if int(b["state"]) == State.LANDING:
					_set_fly(b, _bird_index(b))
					b["waiting"] = true
		for b2_v in _birds:
			var b2: Dictionary = b2_v
			if int(b2["state"]) != State.PERCH:
				continue
			var slot: Dictionary = {}
			if initial and _bird_index(b2) < 3:
				# 初始 3 只优先落在屋脊：白天稳态 airborne=BIRD_DAY_TARGET，已停栖的鸟不会主动起飞，
				# 因此 06_bird_roof 的白天镜头能稳定看到海鸥落在屋脊瓦面上。
				slot = _find_free_slot_kind((b2["node"] as Node3D).position, "ridge")
			if slot.is_empty():
				slot = _find_free_slot((b2["node"] as Node3D).position)
			if slot.is_empty():
				_set_fly(b2, _bird_index(b2))
				b2["waiting"] = true
				continue
			_reserve_slot(String(slot["id"]), int(slot["slot"]))
			b2["perch_id"] = slot["id"]
			b2["perch_slot"] = slot["slot"]
			b2["perch_pos"] = slot["pos"]
			var node: Node3D = b2["node"]
			node.position = slot["pos"]
			b2["prev_pos"] = node.position
			b2["teleport"] = true
			b2["fold"] = 1.0
			var perch: Dictionary = _find_perch(String(slot["id"]))
			if not perch.is_empty():
				_apply_perch_pose(b2, perch)
			b2["timer"] = _rng.randf_range(IsleFx.BIRD_TIMER_MIN, IsleFx.BIRD_TIMER_MAX)

	# ---------------- motion helpers ----------------
	func _orbit_point(b: Dictionary, angle: float) -> Vector3:
		var r: float = float(b["radius"])
		# 只依赖 angle（angle 本身已含每鸟相位）——保证起飞完成时重算 phase 后
		# _orbit_point(b, atan2(pos)) 与 to_p 完全一致，不产生高度跳变/收敛螺旋
		var h: float = float(b["height"]) + sin(angle * 2.0) * 1.1
		return Vector3(cos(angle) * r, h, sin(angle) * r)

	# 轨道点对时间的解析导数 = 巡航时的真实速度方向（入巡航瞬间用它对齐朝向）
	func _orbit_velocity(b: Dictionary, angle: float) -> Vector3:
		var omega: float = float(b["speed"]) * float(b["dir"])
		var r: float = float(b["radius"])
		return Vector3(-sin(angle) * r * omega, cos(angle * 2.0) * 2.2 * omega, cos(angle) * r * omega)

	## P7：船只响应期间的飞行目标 = 原轨道点 + 朝船方位的水平偏移 - 高度下沉；权重平滑过渡，无瞬移。
	func _flight_target(b: Dictionary, angle: float) -> Vector3:
		var p: Vector3 = _orbit_point(b, angle)
		var w: float = float(b.get("resp_w", 0.0))
		if w <= 0.0001:
			return p
		var az: float = float(b.get("resp_az", 0.0))
		return p + Vector3(cos(az) * BOAT_RESP_SHIFT * w, -BOAT_RESP_DROP * w, sin(az) * BOAT_RESP_SHIFT * w)

	## P7：响应权重生命周期（延迟 → 上升 → 保持 → 回落）。只改飞行目标，不参与世界时间。
	func _update_boat_response(b: Dictionary, delta: float) -> void:
		var delay: float = float(b.get("resp_delay", 0.0))
		if delay > 0.0:
			b["resp_delay"] = maxf(0.0, delay - delta)
			return
		var timer: float = float(b.get("resp_timer", 0.0))
		var w: float = float(b.get("resp_w", 0.0))
		if timer > 0.0:
			b["resp_timer"] = maxf(0.0, timer - delta)
			b["resp_w"] = minf(1.0, w + delta / BOAT_RESP_UP_TIME)
		elif w > 0.0:
			b["resp_w"] = maxf(0.0, w - delta / BOAT_RESP_DOWN_TIME)

	func _airborne_count() -> int:
		var n := 0
		for b_v in _birds:
			var b: Dictionary = b_v
			var st: int = int(b["state"])
			if st == State.FLY or st == State.TAKEOFF or st == State.LANDING:
				n += 1
		return n

	func _begin_takeoff(b: Dictionary) -> void:
		_release_perch(b)
		var node: Node3D = b["node"]
		b["state"] = State.TAKEOFF
		b["t"] = 0.0
		b["dur"] = _rng.randf_range(IsleFx.BIRD_TRANSITION_MIN, IsleFx.BIRD_TRANSITION_MAX)
		b["from_p"] = node.position
		var a: float = atan2(node.position.z, node.position.x) + _rng.randf_range(-0.25, 0.25)
		b["to_p"] = _orbit_point(b, a + 0.30 * float(b["dir"]))
		_takeoffs_total += 1
		if _night:
			_takeoffs_night += 1

	func _begin_landing(b: Dictionary) -> bool:
		var slot: Dictionary = _find_free_slot((b["node"] as Node3D).position)
		if slot.is_empty():
			b["waiting"] = true
			return false
		_reserve_slot(String(slot["id"]), int(slot["slot"]))
		b["perch_id"] = slot["id"]
		b["perch_slot"] = slot["slot"]
		b["perch_pos"] = slot["pos"]
		b["state"] = State.LANDING
		b["t"] = 0.0
		b["dur"] = _rng.randf_range(IsleFx.BIRD_TRANSITION_MIN, IsleFx.BIRD_TRANSITION_MAX)
		b["from_p"] = (b["node"] as Node3D).position
		b["to_p"] = slot["pos"]
		b["waiting"] = false
		# P7：一旦转入降落，结束船只响应偏置，避免响应状态残留到下一次日常飞行。
		b["resp_delay"] = 0.0
		b["resp_timer"] = 0.0
		b["resp_w"] = 0.0
		_landings_total += 1
		return true

	func _nudge_takeoff() -> void:
		var best: Dictionary = {}
		var best_timer := 1.0e30
		for b_v in _birds:
			var b: Dictionary = b_v
			if int(b["state"]) != State.PERCH:
				continue
			if float(b["timer"]) < best_timer:
				best_timer = float(b["timer"])
				best = b
		if not best.is_empty():
			best["timer"] = 0.35

	# ---------------- day / night ----------------
	func _update_day_night(delta: float, sun_alt: float) -> void:
		if not _night_known:
			_night_known = true
			_night = sun_alt < -2.0
			if _night:
				_request_night_landings()
			return
		if _night:
			if sun_alt > 2.0:
				_night = false
				_on_dawn()
		else:
			if sun_alt < -2.0:
				_night = true
				_request_night_landings()

	func _request_night_landings() -> void:
		for b_v in _birds:
			var b: Dictionary = b_v
			var st: int = int(b["state"])
			if st == State.FLY or st == State.TAKEOFF:
				b["timer"] = _rng.randf_range(0.2, 2.2)

	func _on_dawn() -> void:
		_roost_state = ROOST_NONE
		_roost_timer = 0.0
		_roost_skip_reason = ""
		for b_v in _birds:
			var b: Dictionary = b_v
			if int(b["state"]) == State.PERCH:
				b["timer"] = _rng.randf_range(2.0, 14.0)

	# ---------------- P7：生态节奏（黄昏归栖 / 船鸟联动） ----------------
	## 黄昏归栖的空中目标数：太阳从 +4° 降到 -2° 时由 6 递减到 0（沿用现有 BIRD_DAY_TARGET）。
	func _roost_target_airborne(sun_alt: float) -> int:
		var p: float = clampf((DUSK_START_ALT - sun_alt) / (DUSK_START_ALT + 2.0), 0.0, 1.0)
		return int(round(float(IsleFx.BIRD_DAY_TARGET) * (1.0 - p)))

	## 选择一只可安全转入降落的鸟：只动巡航态（不打断起飞/降落/停栖），并尊重落点占用。
	func _pick_roost_bird() -> Dictionary:
		var pool: Array = []
		for b_v in _birds:
			var b: Dictionary = b_v
			if int(b["state"]) != State.FLY:
				continue
			if bool(b.get("waiting", false)):
				continue
			if _t - float(b.get("fly_since", -100.0)) < 1.0:
				continue
			pool.append(b)
		if pool.is_empty():
			return {}
		return pool[_rng.randi_range(0, pool.size() - 1)]

	## 每帧生态事件推进：世界阶段→触发资格→事件生命周期只依赖权威时间（sun_alt / rising / day），
	## 动画与缓动只消费这些状态，不反向决定世界时间。
	func _update_eco(delta: float, sun_alt: float, ctx: Dictionary) -> void:
		var has_rising: bool = ctx.has("rising")
		var descending: bool
		if has_rising:
			descending = not bool(ctx["rising"])
		else:
			descending = _sun_prev_valid and sun_alt < _sun_prev - 0.0005
		var first_sample := not _sun_prev_valid
		_sun_prev = sun_alt
		_sun_prev_valid = true
		var has_day: bool = ctx.has("day")
		var day: int = int(ctx.get("day", -999999))
		# 夜间：进行中的归栖转为夜间稳定状态，由既有 _request_night_landings 收尾，不补演已错过动画。
		if _night:
			if _roost_state == ROOST_ACTIVE:
				_roost_state = ROOST_NIGHT
				print("[ECO] dusk_roost -> night alt=", snappedf(sun_alt, 0.01))
			_roost_timer = 0.0
			return
		if _roost_state == ROOST_NIGHT:
			_roost_state = ROOST_NONE
		# 时间回拖到白天：取消未完成的归栖计划；但保留 _roost_day，同一模拟日不重演。
		if _roost_state == ROOST_ACTIVE and sun_alt > DUSK_CANCEL_ALT:
			_roost_state = ROOST_NONE
			_roost_timer = 0.0
			_roost_skip_reason = "cancel_return_day"
			print("[ECO] dusk_roost cancel (back to day) alt=", snappedf(sun_alt, 0.01))
			return
		var start_ok: bool = descending and sun_alt <= DUSK_START_ALT and not first_sample
		if _roost_state == ROOST_NONE:
			if start_ok and (not has_day or day != _roost_day):
				_roost_state = ROOST_ACTIVE
				_roost_day = day
				_roost_timer = 0.0
				_roost_starts += 1
				print("[ECO] dusk_roost start day=", day, " alt=", snappedf(sun_alt, 0.01), " target=", _roost_target_airborne(sun_alt))
			return
		# ROOST_ACTIVE：时间前跳跨过午夜后落在新一天的黄昏时，允许新一天重新开始（每日一次）。
		if start_ok and has_day and day != _roost_day:
			_roost_day = day
			_roost_timer = 0.0
			_roost_starts += 1
			print("[ECO] dusk_roost restart new day=", day, " alt=", snappedf(sun_alt, 0.01))
		if _eco_paused:
			return
		var target: int = _roost_target_airborne(sun_alt)
		if _airborne_count() <= target:
			_roost_timer = 0.0
			return
		_roost_timer = float(_roost_timer) - delta
		if _roost_timer > 0.0:
			return
		_roost_timer = _rng.randf_range(ROOST_GAP_MIN, ROOST_GAP_MAX)
		var pick: Dictionary = _pick_roost_bird()
		if pick.is_empty():
			_roost_skips += 1
			_roost_skip_reason = "no_eligible_bird"
			return
		if not _begin_landing(pick):
			_roost_skips += 1
			_roost_skip_reason = "no_free_slot"
			_roost_timer = maxf(float(_roost_timer), 0.9)
			return
		_roost_landings += 1
		_roost_skip_reason = ""
		if _airborne_count() == 0:
			print("[ECO] dusk_roost complete landings=", _roost_landings, " alt=", snappedf(sun_alt, 0.01))

	# ---------------- per-bird state updates ----------------
	func _update_perched(b: Dictionary, delta: float) -> void:
		if _night:
			return
		# P7：船鸟联动的第二只响应鸟延迟起飞（到期后走既有起飞接口）。
		var resp_delay: float = float(b.get("resp_delay", 0.0))
		if resp_delay > 0.0:
			b["resp_delay"] = maxf(0.0, resp_delay - delta)
			if float(b["resp_delay"]) <= 0.0:
				if _roost_state == ROOST_NONE:
					_begin_takeoff(b)
				else:
					b["resp_delay"] = 0.0
			return
		# P7：黄昏归栖进行中不再让停栖鸟起飞；保留既有休息状态，等夜间/清晨规则接管。
		if _roost_state == ROOST_ACTIVE:
			b["timer"] = _rng.randf_range(IsleFx.BIRD_TIMER_MIN, IsleFx.BIRD_TIMER_MAX)
			return
		# 白天停在屋脊上的海鸥做「长时间歇脚」：不主动起飞，其他栖枝仍按原节奏轮换，
		# 保证空中鸟数/起飞降落动画不变，同时白天屋顶始终有海鸥（验收：实际观察降落屋顶）。
		var pid := String(b.get("perch_id", ""))
		if pid != "":
			var roof_p: Dictionary = _find_perch(pid)
			if not roof_p.is_empty() and String(roof_p.get("kind", "")) == "ridge":
				b["timer"] = _rng.randf_range(IsleFx.BIRD_TIMER_MIN, IsleFx.BIRD_TIMER_MAX)
				return
		b["timer"] = float(b["timer"]) - delta
		if float(b["timer"]) > 0.0:
			return
		b["timer"] = _rng.randf_range(IsleFx.BIRD_TIMER_MIN, IsleFx.BIRD_TIMER_MAX)
		if _airborne_count() < IsleFx.BIRD_DAY_TARGET:
			_begin_takeoff(b)

	func _update_takeoff(b: Dictionary, delta: float) -> void:
		b["t"] = float(b["t"]) + delta / maxf(float(b["dur"]), 0.05)
		var k: float = clampf(float(b["t"]), 0.0, 1.0)
		var e: float = k * k * (3.0 - 2.0 * k)
		var node: Node3D = b["node"]
		var from_p: Vector3 = b["from_p"]
		var to_p: Vector3 = b["to_p"]
		node.position = from_p.lerp(to_p, e) + Vector3(0.0, sin(PI * k) * 0.55, 0.0)
		if k >= 1.0:
			b["state"] = State.FLY
			b["phase"] = atan2(node.position.z, node.position.x) - _t * float(b["speed"]) * float(b["dir"])
			b["timer"] = _rng.randf_range(0.2, 1.2) if _night else _rng.randf_range(IsleFx.BIRD_TIMER_MIN, IsleFx.BIRD_TIMER_MAX)
			b["fly_since"] = _t

	func _update_flying(b: Dictionary, delta: float) -> void:
		var node: Node3D = b["node"]
		_update_boat_response(b, delta)
		var angle: float = _t * float(b["speed"]) * float(b["dir"]) + float(b["phase"])
		var target: Vector3 = _flight_target(b, angle)
		var k: float = 1.0 - exp(-3.2 * delta)
		node.position = node.position.lerp(target, k)
		b["timer"] = float(b["timer"]) - delta
		if float(b["timer"]) > 0.0:
			return
		if _night:
			if not _begin_landing(b):
				b["timer"] = 0.8
			return
		# P7：船只响应期间不因日常计时器提前收场；响应结束后恢复原有随机降落启发。
		if float(b.get("resp_w", 0.0)) > 0.05:
			b["timer"] = 1.0
			return
		b["timer"] = _rng.randf_range(IsleFx.BIRD_TIMER_MIN, IsleFx.BIRD_TIMER_MAX)
		var airborne: int = _airborne_count()
		if airborne > IsleFx.BIRD_FLY_HIGH:
			_begin_landing(b)
		elif airborne >= IsleFx.BIRD_DAY_TARGET and _rng.randf() < 0.20:
			_begin_landing(b)

	func _update_landing(b: Dictionary, delta: float) -> void:
		var node: Node3D = b["node"]
		if _find_perch(String(b["perch_id"])).is_empty():
			# 目标栖枝失效 → 中止并重新选点/盘旋
			_release_perch(b)
			_set_fly(b, _bird_index(b))
			b["waiting"] = true
			return
		b["t"] = float(b["t"]) + delta / maxf(float(b["dur"]), 0.05)
		var k: float = clampf(float(b["t"]), 0.0, 1.0)
		var e: float = k * k * (3.0 - 2.0 * k)
		var from_p: Vector3 = b["from_p"]
		var to_p: Vector3 = b["to_p"]
		node.position = from_p.lerp(to_p, e) + Vector3(0.0, sin(PI * k) * 0.40, 0.0)
		if k >= 1.0:
			node.position = to_p
			var perch: Dictionary = _find_perch(String(b["perch_id"]))
			if perch.is_empty():
				_release_perch(b)
				_set_fly(b, _bird_index(b))
				b["waiting"] = true
				return
			_apply_perch_pose(b, perch)
			b["prev_pos"] = node.position
			b["teleport"] = true
			b["state"] = State.PERCH
			b["t"] = 0.0
			b["timer"] = 999.0 if _night else _rng.randf_range(IsleFx.BIRD_TIMER_MIN, IsleFx.BIRD_TIMER_MAX)
			if not _night and _roost_state == ROOST_NONE and _airborne_count() < IsleFx.BIRD_DAY_TARGET:
				_nudge_takeoff()

	func _separate() -> void:
		# 只对 FLY 状态的鸟做空中分离，保证任意两只鸟间距 >= BIRD_MIN_AIR_GAP。
		var air: Array = []
		for b_v in _birds:
			var b: Dictionary = b_v
			if int(b["state"]) == State.FLY:
				air.append(b)
		if air.size() < 2:
			return
		for iter in range(2):
			for i in range(air.size()):
				var a: Dictionary = air[i]
				var na: Node3D = a["node"]
				for j in range(i + 1, air.size()):
					var c: Dictionary = air[j]
					var nc: Node3D = c["node"]
					var d: Vector3 = na.position - nc.position
					var dist: float = d.length()
					if dist >= IsleFx.BIRD_MIN_AIR_GAP:
						continue
					if dist < 0.0001:
						d = Vector3(1.0, 0.0, 0.0)
						dist = 0.0001
					var push: Vector3 = (d / dist) * ((IsleFx.BIRD_MIN_AIR_GAP - dist) * 0.5 + 0.01)
					na.position = na.position + push
					nc.position = nc.position - push

	func _compute_min_air_dist() -> float:
		var air: Array = []
		for b_v in _birds:
			var b: Dictionary = b_v
			if int(b["state"]) == State.FLY:
				air.append(b)
		var min_d := -1.0
		for i in range(air.size()):
			var bi: Dictionary = air[i]
			var na: Node3D = bi["node"]
			for j in range(i + 1, air.size()):
				var bj: Dictionary = air[j]
				var nc: Node3D = bj["node"]
				var d: float = na.position.distance_to(nc.position)
				if min_d < 0.0 or d < min_d:
					min_d = d
		return min_d

	func _check_perch_validity(delta: float) -> void:
		_check_acc += delta
		if _check_acc < 2.0:
			return
		_check_acc = 0.0
		var valid: Dictionary = {}
		for p_v in _perches:
			var p: Dictionary = p_v
			valid[String(p["id"])] = true
		var stale: Array = []
		for id_v in _perch_used.keys():
			if not valid.has(String(id_v)):
				stale.append(id_v)
		for s_v in stale:
			_perch_used.erase(s_v)
		for b_v in _birds:
			var b: Dictionary = b_v
			var pid: String = String(b["perch_id"])
			if pid == "" or valid.has(pid):
				continue
			_release_perch(b)
			var st: int = int(b["state"])
			if st == State.PERCH or st == State.LANDING:
				_set_fly(b, _bird_index(b))
				b["waiting"] = true

	# 朝向限幅（契约）：俯仰 ±35°，横滚 ±0.55 rad
	const PITCH_MAX: float = 0.610865
	const ROLL_MAX: float = 0.55

	# 停栖姿态：收翼贴体、尾巴略翘、偶尔左右张望
	func _pose_perched(b: Dictionary, d: float) -> void:
		var wl: Node3D = b["wing_l"]
		var wr: Node3D = b["wing_r"]
		var el: Node3D = b["elbow_l"]
		var er: Node3D = b["elbow_r"]
		var legs: Node3D = b["legs"]
		var tail: Node3D = b["tail"]
		var head: Node3D = b["head"]
		var fold: float = move_toward(float(b.get("fold", 1.0)), 1.0, d * 3.0)
		b["fold"] = fold
		var k: float = 1.0 - exp(-9.0 * d)
		# 翼根沿身体轴向后收，肘部继续向后折，翼面略上抬贴住身体两侧
		wl.rotation.y = lerpf(wl.rotation.y, lerpf(0.0, -1.42, fold), k)
		wr.rotation.y = lerpf(wr.rotation.y, lerpf(0.0, 1.42, fold), k)
		wl.rotation.z = lerpf(wl.rotation.z, lerpf(0.0, 0.10, fold), k)
		wr.rotation.z = lerpf(wr.rotation.z, lerpf(0.0, -0.10, fold), k)
		el.rotation.y = lerpf(el.rotation.y, lerpf(0.0, -0.72, fold), k)
		er.rotation.y = lerpf(er.rotation.y, lerpf(0.0, 0.72, fold), k)
		el.rotation.z = lerpf(el.rotation.z, lerpf(0.0, 0.16, fold), k)
		er.rotation.z = lerpf(er.rotation.z, lerpf(0.0, -0.16, fold), k)
		legs.rotation.x = lerpf(legs.rotation.x, 0.0, k)
		tail.rotation.x = lerpf(tail.rotation.x, -0.16, k)
		var look: float = sin(_t * 0.65 + float(b["phase"]) * 2.7) * 0.26
		head.rotation.y = lerpf(head.rotation.y, look, 1.0 - exp(-3.0 * d))
		head.rotation.x = lerpf(head.rotation.x, 0.0, k)

	# 飞行姿态：滑翔/振翅交替、内外翼相位差、转弯滚转、降落展翼减速
	func _pose_flying(b: Dictionary, d: float, st: int) -> void:
		var wl: Node3D = b["wing_l"]
		var wr: Node3D = b["wing_r"]
		var el: Node3D = b["elbow_l"]
		var er: Node3D = b["elbow_r"]
		var legs: Node3D = b["legs"]
		var tail: Node3D = b["tail"]
		var head: Node3D = b["head"]
		var k_spread: float = 1.0 - exp(-7.0 * d)
		wl.rotation.y = lerpf(wl.rotation.y, 0.0, k_spread)
		wr.rotation.y = lerpf(wr.rotation.y, 0.0, k_spread)
		el.rotation.y = lerpf(el.rotation.y, 0.0, k_spread)
		er.rotation.y = lerpf(er.rotation.y, 0.0, k_spread)
		b["fold"] = move_toward(float(b.get("fold", 0.0)), 0.0, d * 4.0)
		# ---- 滑翔 / 振翅节奏 ----
		var gliding: bool = bool(b.get("gliding", false))
		var gt: float = float(b.get("glide_timer", 0.0)) - d
		var gain: float = 1.0
		var rate: float = 1.0
		if st == State.TAKEOFF:
			gliding = false
			gain = 1.15
			rate = 1.22
		elif st == State.LANDING:
			gliding = false
			gain = 1.0
			rate = 1.12
		if st == State.FLY:
			if gt <= 0.0:
				gliding = not gliding
				if gliding:
					gt = _vis_rng.randf_range(0.7, 1.7)
				else:
					gt = _vis_rng.randf_range(1.0, 2.4)
		else:
			gt = 0.0
		b["gliding"] = gliding
		b["glide_timer"] = gt
		var env: float = float(b.get("flap_env", 0.0))
		env = move_toward(env, 0.0 if gliding else 1.0, d * 2.6)
		b["flap_env"] = env
		# 用累计相位而非绝对时间：状态切换（振翅速率变化）时不会跳帧
		var clk: float = float(b.get("flap_clock", 0.0)) + d * 13.0 * rate
		b["flap_clock"] = clk
		var t_f: float = clk + float(b["flap_phase"])
		var wave: float = sin(t_f)
		# 内翼根关节；外翼叠加相位滞后 0.85rad 的跟随拍动 → 翅膀有弹性
		var a_root: float = 0.10 + 0.62 * wave * env * gain
		var a_tip: float = 0.10 + 0.40 * sin(t_f - 0.85) * env * gain
		# 降落末段展翼上抬减速 + 尾羽上翘
		if st == State.LANDING:
			var flare: float = smoothstep(0.35, 0.98, clampf(float(b["t"]), 0.0, 1.0))
			a_root += 0.85 * flare
			a_tip += 0.30 * flare
			tail.rotation.x = lerpf(tail.rotation.x, 0.30 * flare, 1.0 - exp(-8.0 * d))
		else:
			tail.rotation.x = lerpf(tail.rotation.x, -0.05, 1.0 - exp(-6.0 * d))
		# 左翼在 -X 侧：rotation.z 正角让 -X 翼尖向下，因此用负号表示上抬
		var k_flap: float = 1.0 - exp(-22.0 * d)
		wl.rotation.z = lerpf(wl.rotation.z, -a_root, k_flap)
		wr.rotation.z = lerpf(wr.rotation.z, a_root, k_flap)
		el.rotation.z = lerpf(el.rotation.z, -(a_tip - a_root), k_flap)
		er.rotation.z = lerpf(er.rotation.z, a_tip - a_root, k_flap)
		# 飞行时腿收在腹下，降落时逐渐放下
		var tuck: float = 1.35
		if st == State.LANDING:
			tuck = lerpf(1.35, 0.12, clampf(float(b["t"]), 0.0, 1.0))
		legs.rotation.x = lerpf(legs.rotation.x, tuck, 1.0 - exp(-8.0 * d))
		head.rotation.y = lerpf(head.rotation.y, 0.0, 1.0 - exp(-5.0 * d))
		head.rotation.x = lerpf(head.rotation.x, 0.0, 1.0 - exp(-5.0 * d))

	# 朝向由每帧真实速度驱动（禁止用“目标点方向”，那会在目标切换瞬间倒飞）
	func _update_visuals(_delta: float) -> void:
		var d: float = maxf(_delta, 0.0001)
		var k_yaw: float = 1.0 - exp(-20.0 * d)
		var k_pitch: float = 1.0 - exp(-11.0 * d)
		var k_roll: float = 1.0 - exp(-6.0 * d)
		for b_v in _birds:
			var b: Dictionary = b_v
			var node: Node3D = b["node"]
			var st: int = int(b["state"])
			var prev_pos: Vector3 = b.get("prev_pos", node.position)
			var motion_pos: Vector3 = b.get("motion_pos", node.position)
			if st == State.PERCH:
				var perch: Dictionary = _find_perch(String(b["perch_id"]))
				if not perch.is_empty():
					# Phase6：身体 up 对齐停栖面法线（限倾 35°），把倾角/朝向一起收敛过去；
					# 原来的 euler x/z→0 会把鸟强行摆成水平，站在斜瓦上就会“脚陷瓦里/悬空”。
					var want: Basis = _perch_basis(perch)
					node.basis = node.basis.slerp(want, 1.0 - exp(-11.0 * d))
				b["prev_vel"] = Vector3.ZERO
				b["vis_state"] = st
				b["prev_pos"] = node.position
				_pose_perched(b, d)
				continue
			# 只取状态更新造成的位移（不含 _separate 的推挤），避免分离抖动被当成转向
			var vel: Vector3 = (motion_pos - prev_pos) / d
			var teleport: bool = bool(b.get("teleport", false))
			b["teleport"] = false
			var speed: float = vel.length()
			if teleport or speed > 34.0:
				vel = b.get("prev_vel", Vector3.ZERO)
				speed = vel.length()
			var yaw_before: float = node.rotation.y
			var last_st: int = int(b.get("vis_state", -1))
			var entering_fly: bool = st == State.FLY and last_st != State.FLY
			var snapped: bool = false
			# 轨道切线方向（近零速度时作为巡航朝向的兜底）
			var angle: float = _t * float(b["speed"]) * float(b["dir"]) + float(b["phase"])
			var tang := Vector3(-sin(angle) * float(b["dir"]), 0.0, cos(angle) * float(b["dir"]))
			if entering_fly:
				# 起飞末段速度方向是径向的，与下一帧真实轨道速度最多差约 1.5rad；
				# 若吸附当帧速度会立刻倒飞。这里吸附到位置模型的解析速度方向，
				# 即随后各帧（位置收敛后）的真实运动方向。
				var ev: Vector3 = _orbit_velocity(b, angle)
				if ev.length_squared() > 0.000001:
					node.rotation.y = atan2(ev.x, ev.z)
					node.rotation.x = clampf(-atan2(ev.y, maxf(sqrt(ev.x * ev.x + ev.z * ev.z), 0.0001)), -PITCH_MAX, PITCH_MAX)
				else:
					node.rotation.y = atan2(tang.x, tang.z)
					node.rotation.x = 0.0
				snapped = true
			elif speed > 0.06:
				var half_h: float = sqrt(vel.x * vel.x + vel.z * vel.z)
				var pitch_t: float = clampf(-atan2(vel.y, maxf(half_h, 0.0001)), -PITCH_MAX, PITCH_MAX)
				node.rotation.y = lerp_angle(node.rotation.y, atan2(vel.x, vel.z), k_yaw)
				node.rotation.x = lerpf(node.rotation.x, pitch_t, k_pitch)
			else:
				# 近零速度兜底：用轨道切线方向，避免朝向乱飘
				node.rotation.y = lerp_angle(node.rotation.y, atan2(tang.x, tang.z), k_yaw)
				node.rotation.x = lerpf(node.rotation.x, 0.0, k_pitch)
			# roll：由 yaw 变化率驱动（右转 yaw 增大 → 右翼下沉 → rotation.z 取负）；
			# 进巡航的吸附帧不算转向，避免瞬时限幅抖动
			var yaw_rate: float = 0.0 if snapped else wrapf(node.rotation.y - yaw_before, -PI, PI) / d
			var roll_t: float = clampf(-yaw_rate * 0.42, -ROLL_MAX, ROLL_MAX)
			node.rotation.z = lerpf(node.rotation.z, roll_t, k_roll)
			b["prev_vel"] = vel
			b["vis_state"] = st
			b["prev_pos"] = node.position
			_pose_flying(b, d, st)

	# ---------------- main update ----------------
	## ctx 可选：{day:int, rising:bool, sim_seconds:float, time_source:String, paused:bool}
	## 只用于生态事件的触发资格（世界阶段/日期/方向），不建立第二套时间推进。
	func update_birds(delta: float, sun_alt: float, ctx: Dictionary = {}) -> void:
		_ensure_ready()
		if _birds.is_empty():
			return
		_t += delta
		_eco_paused = bool(ctx.get("paused", false))
		_update_day_night(delta, sun_alt)
		_update_eco(delta, sun_alt, ctx)
		_check_perch_validity(delta)
		for b_v in _birds:
			var b: Dictionary = b_v
			var st: int = int(b["state"])
			if st == State.PERCH:
				_update_perched(b, delta)
			elif st == State.TAKEOFF:
				_update_takeoff(b, delta)
			elif st == State.FLY:
				_update_flying(b, delta)
			else:
				_update_landing(b, delta)
			b["motion_pos"] = (b["node"] as Node3D).position
		_separate()
		_min_air_dist = _compute_min_air_dist()
		_update_visuals(delta)

# 飞鸟共享材质（M.toon_material 自身按参数缓存，这里再缓存一层）
static func _bird_materials() -> Dictionary:
	if not _mat_cache.has("bird_mats"):
		_mat_cache["bird_mats"] = {
			# 顶点色 toon 材质：一只鸟的全部部件共用它（1 个材质 + 少量共享网格）
			"vc": M.toon_material(Color.WHITE, {"bands": 3.0, "rim": 0.16, "vertex_color": true}),
			"body": M.toon_material(Color("f2efe7"), {"bands": 3.0, "rim": 0.16}),
			"wing": M.toon_material(Color("96a1ad"), {"bands": 3.0, "rim": 0.12}),
			"beak": M.toon_material(Color("e8b24a"), {"bands": 3.0, "rim": 0.0}),
			"eye": M.toon_material(Color("23262b"), {"bands": 2.0, "rim": 0.0}),
			"legs": M.toon_material(Color("d98436"), {"bands": 3.0, "rim": 0.0}),
		}
	return _mat_cache["bird_mats"]