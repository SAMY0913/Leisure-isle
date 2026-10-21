class_name IsleMath
extends RefCounted
## Shared island math, layout, palette constants and procedural mesh/material helpers.

# ---------------- layout ----------------
const HOUSE_X := 0.8
const HOUSE_Z := -0.6
const HOUSE_YAW := 0.30
# P7-V3.2 比例校准后的木屋外廓（单位米，1 世界单位 = 1 m）：
#   占地 7.6 × 6.2 m；地板面 fy = 0.55（自地形基准）；
#   一层净高 2.42 + 阁楼楼板 0.20 → 阁楼地板 3.17；檐口/屋顶基线 3.73（= fy + 3.18）；
#   屋面高 2.47（坡度 atan(2.47/3.8)≈33.0°）→ 屋脊 6.20 m。
const HOUSE_W := 7.6
const HOUSE_D := 6.2
const HOUSE_WALL_H := 3.18
const HOUSE_ROOF_H := 2.47
const BIG_TREE_X := -10.9
const BIG_TREE_Z := 4.2
const SMALL_TREE_X := 10.4
const SMALL_TREE_Z := -9.0
const DOCK_ANGLE := 0.62
const DOCK_LENGTH := 11.0
const DOCK_WIDTH := 3.4
const GARDEN_X := -7.0
const GARDEN_Z := -5.8
const SWING_X := -9.4
const SWING_Z := 6.2
const CAM_TARGET := Vector3(0.0, 5.0, 0.0)
const CAM_START_THETA := 0.74
const CAM_START_PHI := 1.42
const CAM_START_R := 82.0

# ---------------- palette ----------------
const C_GRASS := Color("7c8b6e")
const C_GRASS_LIGHT := Color("98a582")
const C_GRASS_DARK := Color("5e6e52")
const C_ROCK := Color("9c9282")
const C_ROCK_DARK := Color("6d675d")
const C_SAND := Color("d9c9a6")
const C_WOOD := Color("7a5a41")
const C_WOOD_DARK := Color("523b2b")
const C_WOOD_LIGHT := Color("9c7457")
const C_STONE := Color("c3b5a1")
const C_STONE_DARK := Color("8f8578")
const C_TERRACOTTA := Color("b07155")
const C_TERRACOTTA_DARK := Color("8c553f")
const C_WALL := Color("f2e6cb")
const C_LEAF_A := Color("6f8a5a")
const C_LEAF_B := Color("88a46a")
const C_LEAF_C := Color("54704a")
const C_SOIL := Color("6b5340")
const C_FLOWER_WHITE := Color("f3ead6")
const C_FLOWER_YELLOW := Color("e9c86a")
const C_FLOWER_PINK := Color("d9919b")
const C_BOAT := Color("8a6a4e")
const C_SAIL := Color("e8ddc4")

static var _toon_shader: Shader = null
static var _outline_shader: Shader = null
static var _mat_cache: Dictionary = {}
static var _outline_cache: Dictionary = {}

# ---------------- island math ----------------
static func coast_radius(a: float) -> float:
	return 25.5 + 2.8 * sin(3.0 * a + 0.70) + 1.9 * cos(5.0 * a - 1.20) \
		+ 1.1 * sin(7.0 * a + 2.10) + 0.7 * cos(11.0 * a + 0.40)

static func profile_at(n: float) -> float:
	var pts := [
		[0.00, 7.55], [0.40, 7.45], [0.54, 7.05], [0.64, 6.10], [0.73, 4.95],
		[0.81, 3.60], [0.88, 2.10], [0.94, 0.85], [1.00, 0.00], [1.05, -1.05],
		[1.14, -3.10], [1.30, -5.60], [1.60, -7.20]
	]
	if n <= 0.0:
		return 7.55
	if n >= 1.60:
		return -7.20
	for i in range(pts.size() - 1):
		var a: Array = pts[i]
		var b: Array = pts[i + 1]
		if n >= float(a[0]) and n <= float(b[0]):
			var u: float = (n - float(a[0])) / (float(b[0]) - float(a[0]))
			var s: float = u * u * (3.0 - 2.0 * u)
			return lerpf(float(a[1]), float(b[1]), s)
	return 0.0

static func terrain_height(x: float, z: float) -> float:
	var r: float = sqrt(x * x + z * z)
	var a: float = atan2(z, x)
	var cr: float = coast_radius(a)
	var n: float = r / cr
	var h: float = profile_at(n)
	var meadow: float = smoothstep(0.60, 0.38, n)
	h += meadow * (0.16 * sin(x * 0.33 + 1.4) * cos(z * 0.29 - 0.8)
		+ 0.07 * sin(x * 0.91 + z * 0.73 + 2.1))
	var cliff: float = smoothstep(0.55, 0.68, n) * (1.0 - smoothstep(0.93, 1.02, n))
	h += cliff * (0.22 * sin(a * 7.0 + r * 0.55 + 1.3) + 0.12 * cos(a * 13.0 - r * 0.8))
	var hb: float = exp(-((x + 13.5) * (x + 13.5) + (z + 11.0) * (z + 11.0)) / 130.0)
	h += hb * 2.9 * smoothstep(0.98, 0.63, n)
	h += 0.18 * exp(-pow((n - 0.99) / 0.035, 2.0))
	return h

static func terrain_normal(x: float, z: float, e: float = 0.35) -> Vector3:
	var h_l: float = terrain_height(x - e, z)
	var h_r: float = terrain_height(x + e, z)
	var h_d: float = terrain_height(x, z - e)
	var h_u: float = terrain_height(x, z + e)
	return Vector3(h_l - h_r, 2.0 * e, h_d - h_u).normalized()

static func house_ground_y() -> float:
	return terrain_height(HOUSE_X, HOUSE_Z)

static func house_front() -> Vector3:
	return Vector3(sin(HOUSE_YAW), 0.0, cos(HOUSE_YAW))

static func door_world() -> Vector3:
	# 门前廊台/台阶处（墙面外 0.45 m），y = 室内地板面高度。
	var d: float = HOUSE_D * 0.5 + 0.45
	return Vector3(HOUSE_X + sin(HOUSE_YAW) * d, house_ground_y() + 0.55, HOUSE_Z + cos(HOUSE_YAW) * d)

static func door_approach() -> Vector3:
	# 门前道路的起点（墙面外 2.4 m），y 取地形高度。
	var d: float = HOUSE_D * 0.5 + 2.4
	return Vector3(HOUSE_X + sin(HOUSE_YAW) * d, house_ground_y(), HOUSE_Z + cos(HOUSE_YAW) * d)

static func dock_dir() -> Vector3:
	return Vector3(cos(DOCK_ANGLE), 0.0, sin(DOCK_ANGLE))

static func dock_start() -> Vector3:
	var a: float = DOCK_ANGLE
	var r: float = coast_radius(a) * 0.90
	return Vector3(cos(a) * r, terrain_height(cos(a) * r, sin(a) * r), sin(a) * r)

static func dock_end() -> Vector3:
	var s: Vector3 = dock_start()
	return s + dock_dir() * DOCK_LENGTH

# ---------------- theme time ----------------
static func theme_time(sun_alt: float, rising: bool) -> float:
	if rising:
		if sun_alt <= -18.0:
			return 0.02
		elif sun_alt <= -6.0:
			return lerpf(0.02, 0.14, smoothstep(-18.0, -6.0, sun_alt))
		elif sun_alt <= -0.833:
			return lerpf(0.14, 0.225, smoothstep(-6.0, -0.833, sun_alt))
		elif sun_alt <= 6.0:
			return lerpf(0.225, 0.30, smoothstep(-0.833, 6.0, sun_alt))
		else:
			return lerpf(0.30, 0.44, smoothstep(6.0, 62.0, sun_alt))
	else:
		if sun_alt >= 6.0:
			return lerpf(0.44, 0.60, smoothstep(62.0, 6.0, sun_alt))
		elif sun_alt >= -0.833:
			return lerpf(0.60, 0.70, smoothstep(6.0, -0.833, sun_alt))
		elif sun_alt >= -6.0:
			return lerpf(0.70, 0.84, smoothstep(-0.833, -6.0, sun_alt))
		elif sun_alt >= -18.0:
			return lerpf(0.84, 0.92, smoothstep(-6.0, -18.0, sun_alt))
		else:
			return 0.96

static func sun_dir(alt_deg: float, az_deg: float) -> Vector3:
	var alt: float = deg_to_rad(alt_deg)
	var az: float = deg_to_rad(az_deg)
	return Vector3(cos(alt) * sin(az), sin(alt), -cos(alt) * cos(az)).normalized()

# ---------------- materials ----------------
static func _get_toon() -> Shader:
	if _toon_shader == null:
		_toon_shader = load("res://shaders/toon.gdshader")
	return _toon_shader

static func _get_outline() -> Shader:
	if _outline_shader == null:
		_outline_shader = load("res://shaders/outline.gdshader")
	return _outline_shader

static func outline_material(width: float) -> ShaderMaterial:
	var key: String = "%.4f" % width
	if _outline_cache.has(key):
		return _outline_cache[key]
	var m := ShaderMaterial.new()
	m.shader = _get_outline()
	m.set_shader_parameter("outline_width", width)
	_outline_cache[key] = m
	return m

static func toon_material(color: Color, opts: Dictionary = {}) -> ShaderMaterial:
	var bands: float = float(opts.get("bands", 4.0))
	var soft: float = float(opts.get("soft", 0.55))
	var rim: float = float(opts.get("rim", 0.15))
	var wind: float = float(opts.get("wind", 0.0))
	var glow: float = float(opts.get("glow", 0.0))
	var vc: bool = bool(opts.get("vertex_color", false))
	var outline_w: float = float(opts.get("outline", 0.0))
	var self_lit: bool = bool(opts.get("self_lit", false))
	var key: String = "%s|%.1f|%.2f|%.2f|%.2f|%.2f|%s|%.4f|%s" % [
		color.to_html(false), bands, soft, rim, wind, glow, str(vc), outline_w, str(self_lit)
	]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := ShaderMaterial.new()
	m.shader = _get_toon()
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("band_count", bands)
	m.set_shader_parameter("band_soft", soft)
	m.set_shader_parameter("rim_amount", rim)
	m.set_shader_parameter("use_vertex_color", 1.0 if vc else 0.0)
	m.set_shader_parameter("wind", wind)
	m.set_shader_parameter("glow", glow)
	m.set_shader_parameter("self_lit", 1.0 if self_lit else 0.0)
	if opts.has("rim_color"):
		m.set_shader_parameter("rim_color", opts["rim_color"])
	if outline_w > 0.0:
		m.next_pass = outline_material(outline_w)
	_mat_cache[key] = m
	return m

static func additive_material(tex: Texture2D, color: Color = Color.WHITE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = tex
	m.albedo_color = color
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.disable_receive_shadows = true
	return m

static func blob_shadow_material(alpha: float = 0.34) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = soft_dot_texture(64)
	m.albedo_color = Color(0.03, 0.045, 0.07, alpha)
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.disable_receive_shadows = true
	return m

# ---------------- textures ----------------
static func gradient_radial(offsets: PackedFloat32Array, colors: PackedColorArray, size: int = 128) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = offsets
	g.colors = colors
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = size
	t.height = size
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t

static func soft_dot_texture(size: int = 64) -> GradientTexture2D:
	return gradient_radial(
		PackedFloat32Array([0.0, 0.32, 0.66, 1.0]),
		PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.14), Color(1, 1, 1, 0)]),
		size)

static func ring_texture(size: int = 128) -> GradientTexture2D:
	return gradient_radial(
		PackedFloat32Array([0.0, 0.58, 0.74, 0.86, 1.0]),
		PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.25), Color(1, 1, 1, 0)]),
		size)

static func smoke_texture(size: int = 64) -> GradientTexture2D:
	return gradient_radial(
		PackedFloat32Array([0.0, 0.45, 0.8, 1.0]),
		PackedColorArray([Color(1, 1, 1, 0.85), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0.12), Color(1, 1, 1, 0)]),
		size)

# ---------------- mesh helpers ----------------
static func box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, rot_y: float = 0.0, opts: Dictionary = {}) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = toon_material(color, opts)
	mi.position = pos
	mi.rotation.y = rot_y
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

static func box_rot(parent: Node3D, size: Vector3, pos: Vector3, color: Color, rot: Vector3, opts: Dictionary = {}) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = toon_material(color, opts)
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

static func cyl(parent: Node3D, top_r: float, bot_r: float, h: float, pos: Vector3, color: Color, rot_y: float = 0.0, opts: Dictionary = {}) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top_r
	cm.bottom_radius = bot_r
	cm.height = h
	cm.radial_segments = 10
	cm.rings = 2
	mi.mesh = cm
	mi.material_override = toon_material(color, opts)
	mi.position = pos
	mi.rotation.y = rot_y
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

static func cyl_rot(parent: Node3D, top_r: float, bot_r: float, h: float, pos: Vector3, color: Color, rot: Vector3, opts: Dictionary = {}) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top_r
	cm.bottom_radius = bot_r
	cm.height = h
	cm.radial_segments = 10
	cm.rings = 2
	mi.mesh = cm
	mi.material_override = toon_material(color, opts)
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

static func sphere(parent: Node3D, radius: float, pos: Vector3, color: Color, scl: Vector3 = Vector3.ONE, opts: Dictionary = {}) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 14
	sm.rings = 8
	mi.mesh = sm
	mi.material_override = toon_material(color, opts)
	mi.position = pos
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

static func quad(parent: Node3D, size: Vector2, pos: Vector3, color: Color, rot: Vector3, opts: Dictionary = {}) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = size
	mi.mesh = qm
	mi.material_override = toon_material(color, opts)
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

static func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n: Vector3 = (b - a).cross(c - a).normalized()
	st.set_normal(n)
	st.add_vertex(a)
	st.set_normal(n)
	st.add_vertex(b)
	st.set_normal(n)
	st.add_vertex(c)

static func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var n: Vector3 = (b - a).cross(c - a).normalized()
	for v in [a, b, c, a, c, d]:
		st.set_normal(n)
		st.add_vertex(v)

static func make_prism_mesh(w: float, h: float, d: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw: float = w * 0.5
	var hd: float = d * 0.5
	var a := Vector3(-hw, 0, -hd)
	var b := Vector3(hw, 0, -hd)
	var c := Vector3(0, h, -hd)
	var e := Vector3(-hw, 0, hd)
	var f := Vector3(hw, 0, hd)
	var g := Vector3(0, h, hd)
	_add_tri(st, a, c, b)
	_add_tri(st, e, f, g)
	_add_quad(st, a, b, f, e)
	_add_quad(st, a, e, g, c)
	_add_quad(st, b, c, g, f)
	st.index()
	return st.commit()

static func prism(parent: Node3D, w: float, h: float, d: float, pos: Vector3, color: Color, rot_y: float = 0.0, opts: Dictionary = {}) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = make_prism_mesh(w, h, d)
	mi.material_override = toon_material(color, opts)
	mi.position = pos
	mi.rotation.y = rot_y
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

static func shadow_blob(parent: Node3D, pos: Vector3, radius: float, alpha: float = 0.34) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(radius * 2.0, radius * 2.0)
	mi.mesh = qm
	mi.material_override = blob_shadow_material(alpha)
	mi.position = pos + Vector3(0, 0.035, 0)
	mi.rotation.x = -PI * 0.5
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

static func halo(parent: Node3D, pos: Vector3, size: float, color: Color, tex: Texture2D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(size, size)
	mi.mesh = qm
	mi.material_override = additive_material(tex if tex != null else soft_dot_texture(64), color)
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

static func hitbox(parent: Node3D, node_name: String, pos: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = 2
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	body.position = pos
	parent.add_child(body)
	return body

static func noise01(x: float, y: float) -> float:
	return fposmod(sin(x * 12.9898 + y * 78.233) * 43758.5453, 1.0)

# ---------------- v3 helpers: ground / grass / glass / instancing ----------------
static var _ground_mat: ShaderMaterial = null
static var _ground_tex: Texture2D = null
static var _grass_mat: ShaderMaterial = null
static var _blade_tex: Texture2D = null

static func _new_image(w: int, h: int, fill: Color) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(fill)
	return img

## Soft hand-authored-looking ground detail (grayscale, tiles seamlessly enough at distance).
static func ground_detail_texture() -> Texture2D:
	if _ground_tex != null:
		return _ground_tex
	var s := 256
	var img := _new_image(s, s, Color(0.82, 0.82, 0.82, 1.0))
	var n := FastNoiseLite.new()
	n.seed = 20261019
	n.frequency = 0.026
	n.fractal_octaves = 4
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var n2 := FastNoiseLite.new()
	n2.seed = 9201
	n2.frequency = 0.11
	n2.fractal_octaves = 3
	for y in range(s):
		for x in range(s):
			var fx: float = float(x) / float(s)
			var fy: float = float(y) / float(s)
			var a: float = n.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var b: float = n2.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var v: float = 0.74 + a * 0.20 + b * 0.10
			# faint horizontal/vertical clumps to read as soil + short grass specks
			v -= pow(absf(sin((fy * 3.0 + a * 2.4) * PI)), 6.0) * 0.06
			v += pow(b, 5.0) * 0.10
			var c: Color = Color(v * 0.97, v, v * 0.93, 1.0)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	_ground_tex = ImageTexture.create_from_image(img)
	return _ground_tex

static func terrain_material() -> ShaderMaterial:
	if _ground_mat != null:
		return _ground_mat
	var m := ShaderMaterial.new()
	m.shader = _get_toon()
	m.set_shader_parameter("albedo", Color.WHITE)
	m.set_shader_parameter("use_vertex_color", 1.0)
	m.set_shader_parameter("use_tex", 1.0)
	m.set_shader_parameter("albedo_tex", ground_detail_texture())
	m.set_shader_parameter("uv_scale", Vector2(9.0, 9.0))
	m.set_shader_parameter("tex_strength", 0.55)
	m.set_shader_parameter("detail_bump", 0.45)
	m.set_shader_parameter("band_count", 5.0)
	m.set_shader_parameter("band_soft", 0.72)
	m.set_shader_parameter("rim_amount", 0.03)
	_ground_mat = m
	return m

## Atlas of a few grass blades on transparent background, tinted per instance.
static func grass_blade_texture() -> Texture2D:
	if _blade_tex != null:
		return _blade_tex
	var s := 128
	var img := _new_image(s, s, Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	for b in range(11):
		var bx: float = rng.randf_range(12.0, 116.0)
		var bh: float = rng.randf_range(70.0, 124.0)
		var bw: float = rng.randf_range(3.0, 7.5)
		var lean: float = rng.randf_range(-26.0, 26.0)
		var c0: Color = Color(0.62, 0.70, 0.52, 1.0)
		var c1: Color = Color(0.96, 1.0, 0.86, 1.0)
		for yy in range(s):
			var t: float = (float(s) - float(yy)) / bh
			if t < 0.0 or t > 1.0:
				continue
			var cx: float = bx + lean * t * t
			var hw: float = bw * (1.0 - t) + 0.6
			var x0: int = int(floor(cx - hw))
			var x1: int = int(ceil(cx + hw))
			for xx in range(maxi(0, x0), mini(s - 1, x1) + 1):
				var dd: float = absf(float(xx) - cx)
				var edge: float = 1.0 - dd / maxf(hw, 0.001)
				if edge <= 0.0:
					continue
				var a: float = clampf(edge * 2.4, 0.0, 1.0)
				var col: Color = c0.lerp(c1, pow(t, 1.8))
				col.a = a
				var prev: Color = img.get_pixel(xx, yy)
				if prev.a <= 0.0:
					img.set_pixel(xx, yy, col)
	img.generate_mipmaps()
	_blade_tex = ImageTexture.create_from_image(img)
	return _blade_tex

static func grass_material(tint: Color = Color.WHITE, wind: float = 0.6) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/grass.gdshader")
	m.set_shader_parameter("blade_tex", grass_blade_texture())
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("wind", wind)
	return m

static func glass_material(glow_val: float = 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/glass.gdshader")
	m.set_shader_parameter("tint", Color("9fb4b8"))
	# opacity 现在表示“法线入射吸收率”（薄玻璃 0.10），不是整体 alpha；掠射反射由 shader 的菲涅尔项给。
	m.set_shader_parameter("opacity", 0.10)
	m.set_shader_parameter("glow", glow_val)
	m.set_shader_parameter("glow_col", Color("ffcf9a"))
	m.set_shader_parameter("surface_rough", 0.06)
	m.set_shader_parameter("tint_strength", 0.30)
	m.set_shader_parameter("fresnel_f0", 0.045)
	m.set_shader_parameter("fresnel_power", 5.0)
	m.set_shader_parameter("reflection_gain", 1.65)
	m.set_shader_parameter("sun_spec_gain", 0.85)
	m.set_shader_parameter("sun_shininess", 220.0)
	m.set_shader_parameter("refract_strength", 0.006)
	m.set_shader_parameter("refract_weight", 0.55)
	m.set_shader_parameter("front_sheen", 0.030)
	m.set_shader_parameter("glow_gain", 2.8)
	m.render_priority = 1
	return m

## MultiMesh scatter helper. Casts no shadows by default (matches the rest of the art).
static func multis(parent: Node3D, node_name: String, mesh: Mesh, xforms: Array, colors: Array, mat: Material, cast_shadow: bool = false) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors.size() > 0
	mm.instance_count = xforms.size()
	for i in range(xforms.size()):
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors and i < colors.size():
			mm.set_instance_color(i, colors[i])
	var mi := MultiMeshInstance3D.new()
	mi.name = node_name
	mm.mesh = mesh
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

## Cheap ribbon strip used for boat wakes; the caller updates the instance transform.
static func ribbon_mesh(width: float, length: float, segs: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(segs):
		var t0: float = float(i) / float(segs)
		var t1: float = float(i + 1) / float(segs)
		var z0: float = -t0 * length
		var z1: float = -t1 * length
		var w0: float = width * (1.0 - t0 * 0.55)
		var w1: float = width * (1.0 - t1 * 0.55)
		var a := Vector3(-w0 * 0.5, 0.0, z0)
		var b := Vector3(w0 * 0.5, 0.0, z0)
		var c := Vector3(w1 * 0.5, 0.0, z1)
		var d := Vector3(-w1 * 0.5, 0.0, z1)
		_add_quad(st, a, b, c, d)
	st.index()
	return st.commit()
