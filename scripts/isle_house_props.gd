class_name IsleHouseProps
extends RefCounted
## P7-V3 室内家具程序化库（task-4，G 阶段家具库）。
##
## 设计约定
## ------------------------------------------------------------------
## * build(parent, kind, pos, yaw=0.0, opts={}) 在 parent 下新建一个 Node3D：
##   - 节点原点 = 占地中心；rotation.y = yaw（局部 +Z 为家具正面朝向）。
##   - 落地家具：原点在“地面”的高度 pos.y，全部部件 y >= 0。
##   - 墙挂家具（coat_rack / wall_clock / picture_frame / curtain）：原点在“墙面基准点”，
##     部件沿局部 +Z（向室内）展开；垂直方向以原点为中心（curtain 由原点向下悬挂）。
##   - footprint = 局部 X/Z 占地（米），height = 局部 Y 总高（米）；墙挂件 height 为垂直跨度。
## * 返回 {node, footprint: Vector2(w,d), height, kind, lights}；lights 恒为空数组——
##   灯具只用自发光灯罩（self_lit），不建 Light3D，光源由 main.gd 统一注册。
## * 材质统一走 isle_math 的 toon 材质缓存（M.C_WOOD / M.C_WOOD_LIGHT / M.C_WOOD_DARK +
##   布艺色），所有可见部件描边 0.02（{outline: 0.02}），避免方块堆观感。
## * 自动命名 Prop_<kind>_<seq>，重复 build 不会出现节点重名。
##
## opts（全部可选，未给出的沿用默认尺寸/配色）
## ------------------------------------------------------------------
##   color:   主木材/主色 Color（门垫、地毯、花盆等为“主色”）
##   cushion: 布艺/坐垫/灯罩等副色 Color
##   width/depth/height: 覆盖声明占地与高度（通过节点缩放实现，默认不缩放）
##   rot:     Vector3 覆盖整体欧拉旋转（默认只用 yaw）
##   mattress/quilt/pillow: 床品三色微调（仅 bed 使用）
##
## kind 清单（25 类）
## ------------------------------------------------------------------
## 落地：doormat / shoe_bench / dining_table / chair / sofa / armchair / coffee_table /
##       rug / bookshelf / sideboard / tall_cupboard / bed / nightstand / wardrobe / desk /
##       reading_chair / side_table / table_lamp / floor_lamp / firewood_basket / plant_pot
## 墙挂：coat_rack / wall_clock / picture_frame / curtain

const M := preload("res://scripts/isle_math.gd")

# ---- 局部调色板（与 isle_math 调色板/旧 cottage 家具保持一致） ----
const C_BRASS := Color("b08a5a")
const C_IRON := Color("3f454c")
const C_CERAMIC := Color("d8cbb2")
const C_PAPER := Color("e8dcc0")
const C_GLOW := Color("ffd79b")
const C_ROSE := Color("c98e7f")
const C_CREAM := Color("efe4cf")
const C_SAGE := Color("6f7f6a")
const C_BROWN := Color("8a6f5a")
const C_BLUE := Color("7d8fa6")
const C_PILLOW := Color("f6efe0")
const C_DOORMAT := Color("9a6b5c")
const C_WICKER := Color("8a6a4e")

# 声明尺寸：Vector3(宽 X, 深 Z, 高 Y)，单位米
const DIMS := {
	"doormat": Vector3(1.40, 0.85, 0.026),
	"coat_rack": Vector3(1.00, 0.16, 0.82),
	"shoe_bench": Vector3(0.90, 0.35, 0.47),
	"dining_table": Vector3(1.60, 0.95, 0.78),
	"chair": Vector3(0.46, 0.46, 0.90),
	"sofa": Vector3(1.80, 0.85, 0.87),
	"armchair": Vector3(0.86, 0.84, 0.84),
	"coffee_table": Vector3(1.10, 0.55, 0.42),
	"rug": Vector3(2.60, 1.90, 0.026),
	"bookshelf": Vector3(0.95, 0.32, 1.90),
	"sideboard": Vector3(1.20, 0.42, 0.88),
	"tall_cupboard": Vector3(0.90, 0.44, 1.95),
	"bed": Vector3(1.40, 2.05, 0.95),
	"nightstand": Vector3(0.45, 0.40, 0.55),
	"wardrobe": Vector3(1.25, 0.60, 1.75),
	"desk": Vector3(1.70, 0.90, 0.76),
	"reading_chair": Vector3(0.80, 0.78, 1.20),
	"side_table": Vector3(0.45, 0.45, 0.55),
	"table_lamp": Vector3(0.28, 0.28, 0.51),
	"floor_lamp": Vector3(0.40, 0.40, 1.51),
	"wall_clock": Vector3(0.48, 0.12, 0.48),
	"picture_frame": Vector3(0.62, 0.05, 0.48),
	"curtain": Vector3(0.78, 0.09, 1.67),
	"firewood_basket": Vector3(0.60, 0.44, 0.50),
	"plant_pot": Vector3(0.50, 0.50, 0.78),
}

const WALL_KINDS := ["coat_rack", "wall_clock", "picture_frame", "curtain"]

static var _seq: int = 0
# Glow 光晕材质按颜色缓存（避免重复 build 每次新建 StandardMaterial3D / 纹理）
static var _glow_mats: Dictionary = {}

# ============================================================
# 公共 API
# ============================================================

static func kinds() -> Array:
	var out: Array = []
	for k in DIMS.keys():
		out.append(String(k))
	out.sort()
	return out

static func has_kind(kind: String) -> bool:
	return DIMS.has(kind)

static func is_wall_mounted(kind: String) -> bool:
	return WALL_KINDS.has(kind)

static func dims(kind: String) -> Vector3:
	if DIMS.has(kind):
		return DIMS[kind]
	return Vector3.ZERO

static func footprint_of(kind: String) -> Vector2:
	var d: Vector3 = dims(kind)
	return Vector2(d.x, d.y)

static func height_of(kind: String) -> float:
	return dims(kind).z

## 在 parent 下建造一件家具。返回空字典表示 kind 非法。
static func build(parent: Node3D, kind: String, pos: Vector3, yaw: float = 0.0, opts: Dictionary = {}) -> Dictionary:
	var k := String(kind)
	if parent == null:
		push_error("IsleHouseProps.build: parent 为空（kind=%s）" % k)
		return {}
	if not DIMS.has(k):
		push_error("IsleHouseProps.build: 未知 kind=%s（可用：%s）" % [k, str(kinds())])
		return {}
	var base: Vector3 = DIMS[k]
	var fw := float(opts.get("width", base.x))
	var fd := float(opts.get("depth", base.y))
	var fh := float(opts.get("height", base.z))
	if not is_finite(fw) or fw <= 0.02:
		fw = base.x
	if not is_finite(fd) or fd <= 0.02:
		fd = base.y
	if not is_finite(fh) or fh <= 0.02:
		fh = base.z

	_seq += 1
	var n := Node3D.new()
	n.name = "Prop_%s_%03d" % [k, _seq]
	n.position = pos
	n.rotation.y = yaw
	n.set_meta("prop_kind", k)
	n.set_meta("prop_wall_mounted", is_wall_mounted(k))
	parent.add_child(n)

	match k:
		"doormat":
			_build_doormat(n, opts)
		"coat_rack":
			_build_coat_rack(n, opts)
		"shoe_bench":
			_build_shoe_bench(n, opts)
		"dining_table":
			_build_dining_table(n, opts)
		"chair":
			_build_chair(n, opts)
		"sofa":
			_build_sofa(n, opts)
		"armchair":
			_build_armchair(n, opts)
		"coffee_table":
			_build_coffee_table(n, opts)
		"rug":
			_build_rug(n, opts)
		"bookshelf":
			_build_bookshelf(n, opts)
		"sideboard":
			_build_sideboard(n, opts)
		"tall_cupboard":
			_build_tall_cupboard(n, opts)
		"bed":
			_build_bed(n, opts)
		"nightstand":
			_build_nightstand(n, opts)
		"wardrobe":
			_build_wardrobe(n, opts)
		"desk":
			_build_desk(n, opts)
		"reading_chair":
			_build_reading_chair(n, opts)
		"side_table":
			_build_side_table(n, opts)
		"table_lamp":
			_build_table_lamp(n, opts)
		"floor_lamp":
			_build_floor_lamp(n, opts)
		"wall_clock":
			_build_wall_clock(n, opts)
		"picture_frame":
			_build_picture_frame(n, opts)
		"curtain":
			_build_curtain(n, opts)
		"firewood_basket":
			_build_firewood_basket(n, opts)
		"plant_pot":
			_build_plant_pot(n, opts)
		_:
			push_error("IsleHouseProps.build: 未实现 kind=%s" % k)

	# 整体欧拉角覆盖（默认保持 yaw）
	if opts.has("rot") and opts["rot"] is Vector3:
		n.rotation = opts["rot"]
	# 宽/深/高微调（局部缩放；描边宽度会随缩放略有变化，属可接受微调）
	var scl := Vector3(fw / base.x, fh / base.z, fd / base.y)
	if not scl.is_equal_approx(Vector3.ONE):
		n.scale = scl

	n.set_meta("footprint", Vector2(fw, fd))
	n.set_meta("height", fh)
	return {"node": n, "footprint": Vector2(fw, fd), "height": fh, "kind": k, "lights": []}

# ============================================================
# 通用小工具
# ============================================================

static func _col(opts: Dictionary, key: String, def: Color) -> Color:
	var v: Variant = opts.get(key)
	if v is Color:
		return v
	return def

static func _bx(p: Node3D, size: Vector3, pos: Vector3, c: Color, ry: float = 0.0) -> MeshInstance3D:
	return M.box(p, size, pos, c, ry, {"outline": 0.02})

static func _bxr(p: Node3D, size: Vector3, pos: Vector3, c: Color, rot: Vector3) -> MeshInstance3D:
	return M.box_rot(p, size, pos, c, rot, {"outline": 0.02})

static func _cy(p: Node3D, top_r: float, bot_r: float, h: float, pos: Vector3, c: Color, ry: float = 0.0) -> MeshInstance3D:
	return M.cyl(p, top_r, bot_r, h, pos, c, ry, {"outline": 0.02})

static func _cyr(p: Node3D, top_r: float, bot_r: float, h: float, pos: Vector3, c: Color, rot: Vector3) -> MeshInstance3D:
	return M.cyl_rot(p, top_r, bot_r, h, pos, c, rot, {"outline": 0.02})

static func _sp(p: Node3D, r: float, pos: Vector3, c: Color, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	return M.sphere(p, r, pos, c, scl, {"outline": 0.02})

## 自发光小件（灯罩/灯泡）：self_lit + glow，不加 Light3D。
static func _lit(p: Node3D, size: Vector3, pos: Vector3, c: Color, glow: float = 0.9) -> MeshInstance3D:
	return M.box(p, size, pos, c, 0.0, {"outline": 0.02, "self_lit": true, "glow": glow})

static func _lit_cyl(p: Node3D, top_r: float, bot_r: float, h: float, pos: Vector3, c: Color, glow: float = 0.9) -> MeshInstance3D:
	return M.cyl(p, top_r, bot_r, h, pos, c, 0.0, {"outline": 0.02, "self_lit": true, "glow": glow})

static func _lit_sphere(p: Node3D, r: float, pos: Vector3, c: Color, glow: float = 1.0) -> MeshInstance3D:
	return M.sphere(p, r, pos, c, Vector3.ONE, {"outline": 0.02, "self_lit": true, "glow": glow})

## 柔和光晕（加色 billboard，无描边；名字 Glow 供探针排除描边/包围盒断言）。
## 材质按颜色缓存（M.additive_material + soft_dot_texture 只建一次），避免重复 build 泄漏材质实例。
static func _glow(p: Node3D, pos: Vector3, size: float, c: Color) -> MeshInstance3D:
	var key := c.to_html()
	var mat: StandardMaterial3D = _glow_mats.get(key)
	if mat == null:
		mat = M.additive_material(M.soft_dot_texture(64), c)
		_glow_mats[key] = mat
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(size, size)
	mi.mesh = qm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "Glow"
	p.add_child(mi)
	return mi

## 四条方腿：hx/hz 为腿心到中心的半距，h 为腿高（从 y0 起）。
static func _legs4(p: Node3D, hx: float, hz: float, h: float, t: float, c: Color, y0: float = 0.0) -> void:
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_bx(p, Vector3(t, h, t), Vector3(float(sx) * hx, y0 + h * 0.5, float(sz) * hz), c)

## 四面望板：w/d 为外沿尺寸，t 为板厚，y 为板中心高。
static func _aprons4(p: Node3D, w: float, d: float, y: float, h: float, t: float, c: Color) -> void:
	_bx(p, Vector3(w - 2.0 * t, h, t), Vector3(0, y, -(d * 0.5 - t * 0.5)), c)
	_bx(p, Vector3(w - 2.0 * t, h, t), Vector3(0, y, d * 0.5 - t * 0.5), c)
	_bx(p, Vector3(t, h, d - 2.0 * t), Vector3(-(w * 0.5 - t * 0.5), y, 0), c)
	_bx(p, Vector3(t, h, d - 2.0 * t), Vector3(w * 0.5 - t * 0.5, y, 0), c)

## 柜门：face_z 为门板前表面 z，门朝 +Z。内嵌凸板和把手均从 face_z 向 +Z 叠层（总外凸 0.012）。
static func _panel_door(p: Node3D, w: float, h: float, cx: float, cy: float, face_z: float, face_c: Color, inner_c: Color, handle_c: Color = C_BRASS, handle_side: float = 1.0) -> void:
	_bx(p, Vector3(w, h, 0.024), Vector3(cx, cy, face_z - 0.012), face_c)
	_bx(p, Vector3(w - 0.09, h - 0.09, 0.008), Vector3(cx, cy, face_z + 0.003), inner_c)
	_bx(p, Vector3(0.014, minf(h * 0.32, 0.20), 0.010), Vector3(cx + w * 0.30 * handle_side, cy, face_z + 0.008), handle_c)

## 抽屉面：face_z 为抽屉前表面 z，朝 +Z。
static func _drawer_front(p: Node3D, w: float, h: float, cx: float, cy: float, face_z: float, face_c: Color, handle_c: Color = C_BRASS) -> void:
	_bx(p, Vector3(w, h, 0.024), Vector3(cx, cy, face_z - 0.012), face_c)
	_bx(p, Vector3(w - 0.06, h - 0.05, 0.006), Vector3(cx, cy, face_z + 0.003), face_c.darkened(0.10))
	_bx(p, Vector3(minf(w * 0.42, 0.16), 0.012, 0.010), Vector3(cx, cy, face_z + 0.008), handle_c)

static func _book_colors() -> Array:
	return [
		Color("8a5a4a"), Color("5d7a6a"), Color("b08a5a"),
		Color("7a6a8a"), Color("9a4f42"), Color("4f6b7a"), Color("8a7a4f"),
	]

## 书架上的一排竖立书：x0 为左沿，y_base 为层板顶面，z 为书深中心。
static func _book_row(p: Node3D, x0: float, z: float, y_base: float, count: int, seed_i: int) -> void:
	var cols: Array = _book_colors()
	var x := x0
	for i in range(count):
		var bw := 0.045 + 0.018 * float((i + seed_i) % 3)
		var bh := 0.19 + 0.022 * float((i * 3 + seed_i) % 4)
		var bd := 0.17 + 0.02 * float((i + seed_i * 2) % 2)
		var bc: Color = cols[(i + seed_i * 3) % cols.size()]
		_bx(p, Vector3(bw, bh, bd), Vector3(x + bw * 0.5, y_base + bh * 0.5, z), bc)
		x += bw + 0.004

# ============================================================
# 入门垫（floor）
# ============================================================
static func _build_doormat(n: Node3D, opts: Dictionary) -> void:
	var c := _col(opts, "color", C_DOORMAT)
	var inner := _col(opts, "cushion", Color("b98a70"))
	var edge := Color("6a4a36")
	var w := 1.40
	var d := 0.85
	# 0.02 厚基底（底面贴地）
	_bx(n, Vector3(w, 0.020, d), Vector3(0, 0.010, 0), c)
	# 深色包边（叠在基底上，底面压入 1.5mm 避免共面）
	_bx(n, Vector3(w - 0.04, 0.007, 0.09), Vector3(0, 0.0215, -(d * 0.5 - 0.055)), edge)
	_bx(n, Vector3(w - 0.04, 0.007, 0.09), Vector3(0, 0.0215, d * 0.5 - 0.055), edge)
	_bx(n, Vector3(0.09, 0.007, d - 0.20), Vector3(-(w * 0.5 - 0.055), 0.0215, 0), edge)
	_bx(n, Vector3(0.09, 0.007, d - 0.20), Vector3(w * 0.5 - 0.055, 0.0215, 0), edge)
	# 内层编织面
	_bx(n, Vector3(w - 0.24, 0.004, d - 0.24), Vector3(0, 0.0225, 0), inner)
	# 三道横向编织条纹
	for i in range(3):
		_bx(n, Vector3(w - 0.30, 0.003, 0.045), Vector3(0, 0.0245, -0.18 + float(i) * 0.18), Color("7a5442"))

# ============================================================
# 挂衣板（wall）
# ============================================================
static func _build_coat_rack(n: Node3D, opts: Dictionary) -> void:
	var c := _col(opts, "color", M.C_WOOD_LIGHT)
	var dark := M.C_WOOD_DARK
	var hook := _col(opts, "cushion", C_BRASS)
	# 背板（z 0.00-0.04）
	_bx(n, Vector3(1.00, 0.72, 0.04), Vector3(0, 0, 0.02), c)
	# 3 条深色竖装饰条
	for i in range(3):
		_bx(n, Vector3(0.030, 0.66, 0.010), Vector3(-0.30 + float(i) * 0.30, 0, 0.045), dark)
	# 顶部小搁板 + 托架
	_bx(n, Vector3(1.00, 0.05, 0.14), Vector3(0, 0.385, 0.07), dark)
	for sx in [-1.0, 1.0]:
		_bx(n, Vector3(0.04, 0.06, 0.10), Vector3(float(sx) * 0.42, 0.325, 0.05), dark)
	# 挂帽横杆
	_bx(n, Vector3(0.92, 0.03, 0.03), Vector3(0, 0.16, 0.10), C_IRON)
	# 4 个黄铜挂钩：横杆 + 球头
	for i in range(4):
		var hx := -0.33 + float(i) * 0.22
		_cyr(n, 0.016, 0.016, 0.09, Vector3(hx, 0.135, 0.075), hook, Vector3(PI * 0.5, 0.0, 0.0))
		_sp(n, 0.024, Vector3(hx, 0.135, 0.122), hook)
	# 底部鞋板/小搁板
	_bx(n, Vector3(1.00, 0.04, 0.16), Vector3(0, -0.385, 0.08), dark)
	for sx in [-1.0, 1.0]:
		_bx(n, Vector3(0.04, 0.05, 0.12), Vector3(float(sx) * 0.42, -0.345, 0.06), dark)

# ============================================================
# 换鞋凳（floor）
# ============================================================
static func _build_shoe_bench(n: Node3D, opts: Dictionary) -> void:
	var c := _col(opts, "color", M.C_WOOD)
	var fab := _col(opts, "cushion", C_ROSE)
	var dark := M.C_WOOD_DARK
	# 座垫（顶面 y=0.47）
	_bx(n, Vector3(0.90, 0.07, 0.35), Vector3(0, 0.435, 0), fab)
	_bx(n, Vector3(0.88, 0.02, 0.33), Vector3(0, 0.395, 0), fab.darkened(0.10))
	# 座框
	_bx(n, Vector3(0.84, 0.05, 0.31), Vector3(0, 0.37, 0), dark)
	# 4 条腿 + 侧枨
	_legs4(n, 0.40, 0.135, 0.36, 0.05, c)
	for sx in [-1.0, 1.0]:
		_bx(n, Vector3(0.03, 0.03, 0.27), Vector3(float(sx) * 0.40, 0.12, 0), c)
	# 底部鞋板 + 2 条分隔条
	_bx(n, Vector3(0.80, 0.02, 0.28), Vector3(0, 0.13, 0), M.C_WOOD_LIGHT)
	_bx(n, Vector3(0.02, 0.055, 0.24), Vector3(-0.27, 0.167, 0), dark)
	_bx(n, Vector3(0.02, 0.055, 0.24), Vector3(0.27, 0.167, 0), dark)

# ============================================================
# 餐桌（floor）
# ============================================================
static func _build_dining_table(n: Node3D, opts: Dictionary) -> void:
	var c := _col(opts, "color", M.C_WOOD)
	var dark := M.C_WOOD_DARK
	var w := 1.60
	var d := 0.95
	# 桌面（0.06 厚，顶面 0.78）+ 下缘压边
	_bx(n, Vector3(w, 0.06, d), Vector3(0, 0.75, 0), c)
	_bx(n, Vector3(w - 0.06, 0.03, d - 0.06), Vector3(0, 0.715, 0), dark)
	# 四面望板
	_aprons4(n, w - 0.14, d - 0.14, 0.655, 0.11, 0.035, dark)
	# 4 条车木腿（圆柱 + 上箍 + 脚垫）
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var lx := float(sx) * 0.71
			var lz := float(sz) * 0.41
			_cy(n, 0.045, 0.055, 0.60, Vector3(lx, 0.30, lz), c)
			_cy(n, 0.075, 0.060, 0.04, Vector3(lx, 0.62, lz), c)
			_cy(n, 0.062, 0.072, 0.03, Vector3(lx, 0.015, lz), dark)
	# 长向/短向横枨
	for sz in [-1.0, 1.0]:
		_bx(n, Vector3(1.30, 0.035, 0.035), Vector3(0, 0.16, float(sz) * 0.41), dark)
	for sx in [-1.0, 1.0]:
		_bx(n, Vector3(0.035, 0.035, 0.80), Vector3(float(sx) * 0.71, 0.16, 0), dark)

# ============================================================
# 餐椅（floor）
# ============================================================
static func _build_chair(n: Node3D, opts: Dictionary) -> void:
	var c := _col(opts, "color", M.C_WOOD)
	var fab := _col(opts, "cushion", C_ROSE)
	var dark := M.C_WOOD_DARK
	# 座板 + 坐垫
	_bx(n, Vector3(0.46, 0.06, 0.46), Vector3(0, 0.435, 0), c)
	_bx(n, Vector3(0.40, 0.035, 0.40), Vector3(0, 0.485, 0), fab)
	# 前腿
	for sx in [-1.0, 1.0]:
		_bx(n, Vector3(0.045, 0.42, 0.045), Vector3(float(sx) * 0.195, 0.21, 0.195), c)
	# 后腿延伸为靠背柱
	for sx in [-1.0, 1.0]:
		_bx(n, Vector3(0.045, 0.88, 0.045), Vector3(float(sx) * 0.195, 0.44, -0.20), c)
	# 靠背板 + 内嵌浅色板 + 顶横档
	_bx(n, Vector3(0.35, 0.30, 0.035), Vector3(0, 0.70, -0.20), c)
	_bx(n, Vector3(0.27, 0.22, 0.014), Vector3(0, 0.70, -0.178), M.C_WOOD_LIGHT)
	_bx(n, Vector3(0.42, 0.055, 0.055), Vector3(0, 0.8725, -0.20), c)
	# 座框望板
	_aprons4(n, 0.42, 0.42, 0.39, 0.06, 0.02, dark)
	# 四向横撑
	for sx in [-1.0, 1.0]:
		_bx(n, Vector3(0.03, 0.03, 0.35), Vector3(float(sx) * 0.195, 0.14, 0), dark)
	_bx(n, Vector3(0.36, 0.03, 0.03), Vector3(0, 0.14, -0.195), dark)
	_bx(n, Vector3(0.36, 0.03, 0.03), Vector3(0, 0.14, 0.195), dark)

# ============================================================
# 沙发（floor）
# ============================================================
static func _build_sofa(n: Node3D, opts: Dictionary) -> void:
	var c := _col(opts, "color", M.C_WOOD)
	var fab := _col(opts, "cushion", C_ROSE)
	var fab_d := fab.darkened(0.14)
	var dark := M.C_WOOD_DARK
	var w := 1.80
	var d := 0.85
	# 底座（深色布艺）
	_bx(n, Vector3(w, 0.22, d), Vector3(0, 0.24, 0), Color("7a4f3f"))
	# 4 条短木腿
	_legs4(n, 0.79, 0.33, 0.13, 0.07, dark)
	# 两块坐垫
	for sx in [-1.0, 1.0]:
		_bx(n, Vector3(0.72, 0.15, 0.62), Vector3(float(sx) * 0.375, 0.425, 0.06), fab)
		_bx(n, Vector3(0.66, 0.02, 0.56), Vector3(float(sx) * 0.375, 0.505, 0.06), fab.lightened(0.06))
	# 靠背主体 + 两块斜靠软垫
	_bx(n, Vector3(w, 0.48, 0.16), Vector3(0, 0.545, -0.345), fab_d)
	for sx in [-1.0, 1.0]:
		_bxr(n, Vector3(0.76, 0.40, 0.12), Vector3(float(sx) * 0.375, 0.575, -0.255), fab, Vector3(-0.10, 0, 0))
	# 靠背顶圆边
	_cyr(n, 0.08, 0.08, w, Vector3(0, 0.785, -0.345), fab_d, Vector3(0, 0, PI * 0.5))
	# 扶手 + 扶手顶圆边
	for sx in [-1.0, 1.0]:
		_bx(n, Vector3(0.18, 0.49, d), Vector3(float(sx) * 0.81, 0.375, 0), fab_d)
		_cyr(n, 0.09, 0.09, d, Vector3(float(sx) * 0.81, 0.62, 0), fab_d, Vector3(PI * 0.5, 0, 0))
	# 坐垫前沿滚边（细条，增加层次）
	for sx in [-1.0, 1.0]:
		_bx(n, Vector3(0.68, 0.03, 0.03), Vector3(float(sx) * 0.375, 0.36, 0.375), fab_d)

# ============================================================
# 扶手椅（floor）
# ============================================================
static func _build_armchair(n: Node3D, opts: Dictionary) -> void:
	var c := _col(opts, "color", M.C_WOOD)
	var fab := _col(opts, "cushion", C_SAGE)
	var fab_d := fab.darkened(0.14)
	var dark := M.C_WOOD_DARK
	# 4 条短腿 + 底座
	_legs4(n, 0.34, 0.34, 0.13, 0.06, dark)
	_bx(n, Vector3(0.86, 0.18, 0.84), Vector3(0, 0.22, 0), fab_d)
	# 座垫
	_bx(n, Vector3(0.52, 0.14, 0.58), Vector3(0, 0.38, 0.05), fab)
	_bx(n, Vector3(0.46, 0.02, 0.52), Vector3(0, 0.455, 0.05), fab.lightened(0.06))
	# 靠背 + 靠垫
	_bx(n, Vector3(0.86, 0.45, 0.16), Vector3(0, 0.545, -0.34), fab_d)
	_bxr(n, Vector3(0.54, 0.36, 0.12), Vector3(0, 0.56, -0.245), fab, Vector3(-0.09, 0, 0))
	_cyr(n, 0.07, 0.07, 0.86, Vector3(0, 0.77, -0.34), fab_d, Vector3(0, 0, PI * 0.5))
	# 扶手 + 圆边
	for sx in [-1.0, 1.0]:
		_bx(n, Vector3(0.17, 0.46, 0.84), Vector3(float(sx) * 0.345, 0.33, 0), fab_d)
		_cyr(n, 0.085, 0.085, 0.84, Vector3(float(sx) * 0.345, 0.56, 0), fab_d, Vector3(PI * 0.5, 0, 0))

# ============================================================
# 茶几（floor）
# ============================================================
static func _build_coffee_table(n: Node3D, opts: Dictionary) -> void:
	var c := _col(opts, "color", M.C_WOOD)
	var dark := M.C_WOOD_DARK
	var w := 1.10
	var d := 0.55
	# 桌面（0.05 厚，顶面 0.42）+ 压边
	_bx(n, Vector3(w, 0.05, d), Vector3(0, 0.395, 0), c)
	_bx(n, Vector3(w - 0.05, 0.025, d - 0.05), Vector3(0, 0.3625, 0), dark)
	# 4 条腿 + 望板
	_legs4(n, 0.49, 0.22, 0.36, 0.055, c)
	_aprons4(n, w - 0.06, d - 0.06, 0.33, 0.07, 0.03, dark)
	# 下层搁板 + 挡条
	_bx(n, Vector3(0.98, 0.025, 0.45), Vector3(0, 0.13, 0), M.C_WOOD_LIGHT)
	for sx in [-1.0, 1.0]:
		_bx(n, Vector3(0.025, 0.03, 0.42), Vector3(float(sx) * 0.488, 0.155, 0), dark)
	# 搁板上的书与托盘（低矮装饰，不超桌面高度）
	_bx(n, Vector3(0.22, 0.035, 0.16), Vector3(-0.20, 0.16, 0.02), Color("8a5a4a"), 0.20)
	_bx(n, Vector3(0.19, 0.03, 0.14), Vector3(-0.19, 0.19, 0.01), Color("5d7a6a"), -0.12)
	_cy(n, 0.09, 0.09, 0.02, Vector3(0.24, 0.155, -0.02), C_BRASS)

# ============================================================
# 地毯（floor，叠层避免 z-fighting）
# ============================================================
static func _build_rug(n: Node3D, opts: Dictionary) -> void:
	var c := _col(opts, "color", Color("9a6b5c"))
	var edge := _col(opts, "cushion", Color("c9a78e"))
	var accent := edge.darkened(0.18)
	var w := 2.60
	var d := 1.90
	# 0.02 厚基底：底面 y=0，顶面 0.020
	_bx(n, Vector3(w, 0.020, d), Vector3(0, 0.010, 0), c)
	# 边框（叠在基底上，底面压入 1.5mm，避免共面 z-fighting）
	_bx(n, Vector3(w, 0.006, 0.12), Vector3(0, 0.0215, -(d * 0.5 - 0.06)), edge)
	_bx(n, Vector3(w, 0.006, 0.12), Vector3(0, 0.0215, d * 0.5 - 0.06), edge)
	_bx(n, Vector3(0.12, 0.006, d - 0.24), Vector3(-(w * 0.5 - 0.06), 0.0215, 0), edge)
	_bx(n, Vector3(0.12, 0.006, d - 0.24), Vector3(w * 0.5 - 0.06, 0.0215, 0), edge)
	# 内层织面（再高 2mm）
	_bx(n, Vector3(w - 0.26, 0.004, d - 0.26), Vector3(0, 0.0225, 0), edge.lightened(0.05))
	# 内层花纹条
	for i in range(3):
		_bx(n, Vector3(w - 0.34, 0.003, 0.05), Vector3(0, 0.0245, -0.32 + float(i) * 0.32), accent)
	# 两端包边上的流苏压线（收在 2.60 以内）
	for i in range(9):
		var z := -0.80 + float(i) * 0.20
		_bx(n, Vector3(0.10, 0.003, 0.03), Vector3(-(w * 0.5 - 0.06), 0.0245, z), accent)
		_bx(n, Vector3(0.10, 0.003, 0.03), Vector3(w * 0.5 - 0.06, 0.0245, z), accent)

# ============================================================
# 书架（floor）
# ============================================================
static func _build_bookshelf(n: Node3D, opts: Dictionary) -> void:
	var c := _col(opts, "color", M.C_WOOD)
	var dark := M.C_WOOD_DARK
	var w := 0.95
	var d := 0.32
	# 侧板 / 顶板 / 底板 / 踢脚 / 背板
	for sx in [-1.0, 1.0]:
		_bx(n, Vector3(0.04, 1.85, d), Vector3(float(sx) * 0.455, 0.975, 0), c)
	_bx(n, Vector3(w, 0.05, d), Vector3(0, 1.875, 0), c)
	_bx(n, Vector3(w - 0.08, 0.05, d - 0.03), Vector3(0, 0.065, 0.015), dark)
	_bx(n, Vector3(w - 0.08, 0.04, d - 0.06), Vector3(0, 0.02, 0.03), dark)
	_bx(n, Vector3(w - 0.08, 1.78, 0.02), Vector3(0, 0.95, -(d * 0.5 - 0.01)), dark)
	# 4 块层板
	var shelf_ys := [0.42, 0.80, 1.18, 1.56]
	for sy in shelf_ys:
		_bx(n, Vector3(w - 0.08, 0.035, d - 0.04), Vector3(0, float(sy), 0.01), c)
	# 各层书 + 小摆件
	var cols: Array = _book_colors()
	for si in range(4):
		var top_y: float = float(shelf_ys[si]) + 0.0175
		_book_row(n, -0.38, -0.01, top_y, 6, si)
		if si == 1:
			_bx(n, Vector3(0.20, 0.032, 0.15), Vector3(0.20, top_y + 0.016, 0.0), cols[(si + 2) % cols.size()])
		elif si == 2:
			_cy(n, 0.035, 0.035, 0.12, Vector3(0.26, top_y + 0.06, 0.02), C_CERAMIC)
		elif si == 3:
			_sp(n, 0.05, Vector3(0.26, top_y + 0.05, 0.0), cols[(si + 4) % cols.size()], Vector3(1.0, 0.7, 1.0))

# ============================================================
# 矮边柜（floor）
# ============================================================
static func _build_sideboard(n: Node3D, opts: Dictionary) -> void:
	var c := _col(opts, "color", M.C_WOOD)
	var dark := M.C_WOOD_DARK
	var w := 1.20
	var d := 0.42
	# 台面 + 柜体 + 4 条腿
	_bx(n, Vector3(w, 0.04, d), Vector3(0, 0.86, 0), c)
	_bx(n, Vector3(w - 0.08, 0.58, d - 0.04), Vector3(0, 0.55, 0), c)
	_legs4(n, 0.52, 0.15, 0.26, 0.05, dark)
	# 台面下压边
	_bx(n, Vector3(w - 0.03, 0.025, d - 0.03), Vector3(0, 0.835, 0), dark)
	# 两扇门 + 内嵌板 + 把手（前表面 z = 0.196）
	_panel_door(n, 0.50, 0.42, -0.29, 0.49, 0.196, c, M.C_WOOD_LIGHT, C_BRASS, 1.0)
	_panel_door(n, 0.50, 0.42, 0.29, 0.49, 0.196, c, M.C_WOOD_LIGHT, C_BRASS, -1.0)
	# 顶部两个抽屉面
	_drawer_front(n, 0.50, 0.12, -0.29, 0.78, 0.196, c, C_BRASS)
	_drawer_front(n, 0.50, 0.12, 0.29, 0.78, 0.196, c, C_BRASS)
	# 柜体分缝线
	_bx(n, Vector3(0.012, 0.55, 0.012), Vector3(0, 0.55, 0.198), dark)

# ============================================================
# 高柜（floor）
# ============================================================
static func _build_tall_cupboard(n: Node3D, opts: Dictionary) -> void:
	var c := _col(opts, "color", M.C_WOOD)
	var dark := M.C_WOOD_DARK
	var w := 0.90
	var d := 0.44
	# 踢脚 / 柜体 / 顶檐
	_bx(n, Vector3(w - 0.06, 0.10, d - 0.04), Vector3(0, 0.05, 0), dark)
	_bx(n, Vector3(w - 0.04, 1.76, d - 0.04), Vector3(0, 0.98, 0), c)
	_bx(n, Vector3(w, 0.09, d), Vector3(0, 1.905, 0), dark)
	_bx(n, Vector3(w - 0.06, 0.02, d - 0.06), Vector3(0, 1.84, 0), c)
	# 两扇长门（前表面 z = 0.208；把手外凸后 0.220 = 深度上限）
	_panel_door(n, 0.40, 1.30, -0.21, 1.10, 0.208, c, M.C_WOOD_LIGHT, C_BRASS, 1.0)
	_panel_door(n, 0.40, 1.30, 0.21, 1.10, 0.208, c, M.C_WOOD_LIGHT, C_BRASS, -1.0)
	# 下部两个抽屉
	_drawer_front(n, 0.40, 0.18, -0.21, 0.27, 0.208, c, C_BRASS)
	_drawer_front(n, 0.40, 0.18, 0.21, 0.27, 0.208, c, C_BRASS)
	# 门中分缝 + 上下压线
	_bx(n, Vector3(0.012, 1.30, 0.012), Vector3(0, 1.10, 0.210), dark)
	_bx(n, Vector3(w - 0.08, 0.02, 0.012), Vector3(0, 0.40, 0.210), dark)
	_bx(n, Vector3(w - 0.08, 0.02, 0.012), Vector3(0, 1.78, 0.210), dark)

# ============================================================
# 床（floor）
# ============================================================
static func _build_bed(n: Node3D, opts: Dictionary) -> void:
	var c := _col(opts, "color", M.C_WOOD)
	var dark := M.C_WOOD_DARK
	var mattress := _col(opts, "mattress", C_CREAM)
	var quilt := _col(opts, "quilt", _col(opts, "cushion", C_ROSE))
	var pillow := _col(opts, "pillow", C_PILLOW)
	var w := 1.40
	var d := 2.05
	# 4 条腿 + 床架底座
	_legs4(n, 0.645, 0.965, 0.22, 0.07, dark)
	_bx(n, Vector3(w, 0.14, d), Vector3(0, 0.29, 0), c)
	# 两侧床梁 + 横撑
	for sx in [-1.0, 1.0]:
		_bx(n, Vector3(0.06, 0.16, d), Vector3(float(sx) * 0.67, 0.33, 0), dark)
	for i in range(3):
		_bx(n, Vector3(w - 0.14, 0.04, 0.04), Vector3(0, 0.24, -0.7 + float(i) * 0.7), dark)
	# 床头板（-Z 端）：2 立柱 + 大面板 + 内嵌板 + 顶横档
	for sx in [-1.0, 1.0]:
		_bx(n, Vector3(0.08, 0.95, 0.05), Vector3(float(sx) * 0.66, 0.475, -1.00), c)
	_bx(n, Vector3(1.28, 0.50, 0.05), Vector3(0, 0.62, -1.00), c)
	_bx(n, Vector3(1.10, 0.34, 0.014), Vector3(0, 0.62, -0.972), M.C_WOOD_LIGHT)
	_bx(n, Vector3(1.40, 0.07, 0.05), Vector3(0, 0.915, -1.00), c)
	# 床尾板
	for sx in [-1.0, 1.0]:
		_bx(n, Vector3(0.07, 0.55, 0.05), Vector3(float(sx) * 0.665, 0.275, 1.00), c)
	_bx(n, Vector3(1.30, 0.32, 0.05), Vector3(0, 0.38, 1.00), c)
	_bx(n, Vector3(1.20, 0.06, 0.05), Vector3(0, 0.56, 1.00), dark)
	# 床垫
	_bx(n, Vector3(1.30, 0.16, 1.92), Vector3(0, 0.44, 0), mattress)
	# 被子（盖下半段）+ 折边 + 两侧下摆
	_bx(n, Vector3(1.34, 0.06, 1.24), Vector3(0, 0.545, 0.33), quilt)
	_bx(n, Vector3(1.34, 0.05, 0.16), Vector3(0, 0.545, -0.30), quilt.lightened(0.12))
	for sx in [-1.0, 1.0]:
		_bx(n, Vector3(0.028, 0.26, 1.24), Vector3(float(sx) * 0.685, 0.41, 0.33), quilt.darkened(0.05))
	# 枕头 + 枕套压线
	for sx in [-1.0, 1.0]:
		_bxr(n, Vector3(0.50, 0.13, 0.32), Vector3(float(sx) * 0.31, 0.585, -0.72), pillow, Vector3(-0.10, 0, 0))
		_bx(n, Vector3(0.46, 0.02, 0.28), Vector3(float(sx) * 0.31, 0.655, -0.715), pillow.darkened(0.07))

# ============================================================
# 床头柜（floor）
# ============================================================
static func _build_nightstand(n: Node3D, opts: Dictionary) -> void:
	var c := _col(opts, "color", M.C_WOOD)
	var dark := M.C_WOOD_DARK
	var w := 0.45
	var d := 0.40
	# 台面 + 柜体 + 4 条腿
	_bx(n, Vector3(w, 0.03, d), Vector3(0, 0.535, 0), c)
	_bx(n, Vector3(w - 0.04, 0.36, d - 0.04), Vector3(0, 0.34, 0), c)
	_legs4(n, 0.175, 0.15, 0.165, 0.04, dark)
	# 抽屉面 + 下部格门
	_drawer_front(n, 0.33, 0.13, 0, 0.445, 0.188, c, C_BRASS)
	_panel_door(n, 0.33, 0.16, 0, 0.255, 0.188, c, M.C_WOOD_LIGHT, C_BRASS, 1.0)
	# 台面下压边
	_bx(n, Vector3(w - 0.02, 0.02, d - 0.02), Vector3(0, 0.512, 0), dark)

# ============================================================
# 衣柜（floor）
# ============================================================
static func _build_wardrobe(n: Node3D, opts: Dictionary) -> void:
	var c := _col(opts, "color", M.C_WOOD)
	var dark := M.C_WOOD_DARK
	var w := 1.25
	var d := 0.60
	# 踢脚 / 柜体 / 顶檐
	_bx(n, Vector3(w - 0.04, 0.08, d - 0.04), Vector3(0, 0.04, 0), dark)
	_bx(n, Vector3(w, 1.60, d - 0.04), Vector3(0, 0.88, 0), c)
	_bx(n, Vector3(w, 0.07, d), Vector3(0, 1.715, 0), dark)
	_bx(n, Vector3(w - 0.06, 0.02, d - 0.06), Vector3(0, 1.665, 0), c)
	# 背板
	_bx(n, Vector3(w - 0.08, 1.52, 0.02), Vector3(0, 0.88, -(d * 0.5 - 0.03)), dark)
	# 两扇门（前表面 z = 0.288；把手外凸后 0.300 = 深度上限）
	_panel_door(n, 0.58, 1.48, -0.30, 0.88, 0.288, c, M.C_WOOD_LIGHT, C_BRASS, 1.0)
	_panel_door(n, 0.58, 1.48, 0.30, 0.88, 0.288, c, M.C_WOOD_LIGHT, C_BRASS, -1.0)
	# 门缝压线
	_bx(n, Vector3(0.012, 1.62, 0.012), Vector3(0, 0.88, 0.290), dark)

# ============================================================
# 书桌（floor）
# ============================================================
static func _build_desk(n: Node3D, opts: Dictionary) -> void:
	var c := _col(opts, "color", M.C_WOOD)
	var dark := M.C_WOOD_DARK
	var w := 1.70
	var d := 0.90
	# 桌面 + 下缘压边
	_bx(n, Vector3(w, 0.05, d), Vector3(0, 0.735, 0), c)
	_bx(n, Vector3(w - 0.06, 0.03, d - 0.06), Vector3(0, 0.695, 0), dark)
	# 左右两侧储物柜（pedestal）
	for sx in [-1.0, 1.0]:
		var px := float(sx) * 0.62
		_bx(n, Vector3(0.42, 0.67, 0.78), Vector3(px, 0.375, 0), c)
		# 底部小脚
		for fx in [-1.0, 1.0]:
			for fz in [-1.0, 1.0]:
				_bx(n, Vector3(0.04, 0.04, 0.04), Vector3(px + float(fx) * 0.16, 0.02, float(fz) * 0.30), dark)
	# 左侧抽屉 3 个（前表面 z = 0.400）
	for i in range(3):
		_drawer_front(n, 0.34, 0.17, -0.62, 0.155 + float(i) * 0.205, 0.400, c, C_BRASS)
	# 右侧：上 2 抽屉 + 下 1 门
	_drawer_front(n, 0.34, 0.17, 0.62, 0.575, 0.400, c, C_BRASS)
	_drawer_front(n, 0.34, 0.17, 0.62, 0.370, 0.400, c, C_BRASS)
	_panel_door(n, 0.34, 0.30, 0.62, 0.20, 0.400, c, M.C_WOOD_LIGHT, C_BRASS, 1.0)
	# 中间背挡板 + 横档
	_bx(n, Vector3(0.80, 0.34, 0.02), Vector3(0, 0.50, -(d * 0.5 - 0.05)), dark)
	_bx(n, Vector3(0.80, 0.05, 0.03), Vector3(0, 0.665, -(d * 0.5 - 0.05)), c)

# ============================================================
# 阅读椅（floor）
# ============================================================
static func _build_reading_chair(n: Node3D, opts: Dictionary) -> void:
	var c := _col(opts, "color", M.C_WOOD_DARK)
	var fab := _col(opts, "cushion", C_SAGE)
	var fab_d := fab.darkened(0.14)
	var cream := C_CREAM
	# 4 条短腿 + 底座
	_legs4(n, 0.34, 0.32, 0.20, 0.05, c)
	_bx(n, Vector3(0.78, 0.30, 0.76), Vector3(0, 0.35, 0), fab_d)
	# 座垫
	_bx(n, Vector3(0.60, 0.12, 0.58), Vector3(0, 0.56, 0.04), fab)
	_bx(n, Vector3(0.54, 0.02, 0.52), Vector3(0, 0.63, 0.04), cream)
	# 高靠背（微后倾）+ 靠背顶圆边 + 内嵌软垫
	_bxr(n, Vector3(0.78, 0.60, 0.18), Vector3(0, 0.86, -0.27), fab_d, Vector3(-0.10, 0, 0))
	_cyr(n, 0.09, 0.09, 0.78, Vector3(0, 1.10, -0.305), fab_d, Vector3(0, 0, PI * 0.5))
	_bxr(n, Vector3(0.52, 0.42, 0.10), Vector3(0, 0.80, -0.12), fab, Vector3(-0.10, 0, 0))
	# 两侧翼板 + 扶手
	for sx in [-1.0, 1.0]:
		_bxr(n, Vector3(0.10, 0.46, 0.34), Vector3(float(sx) * 0.34, 0.86, -0.20), fab_d, Vector3(-0.06, 0, 0))
		_bx(n, Vector3(0.13, 0.20, 0.62), Vector3(float(sx) * 0.335, 0.52, 0.02), fab_d)
		_cyr(n, 0.065, 0.065, 0.62, Vector3(float(sx) * 0.335, 0.62, 0.02), fab_d, Vector3(PI * 0.5, 0, 0))

# ============================================================
# 边几（floor）
# ============================================================
static func _build_side_table(n: Node3D, opts: Dictionary) -> void:
	var c := _col(opts, "color", M.C_WOOD)
	var dark := M.C_WOOD_DARK
	# 圆台面（0.04 厚，顶面 0.55）+ 圆望板
	_cy(n, 0.225, 0.225, 0.04, Vector3(0, 0.53, 0), c)
	_cy(n, 0.19, 0.20, 0.035, Vector3(0, 0.4925, 0), dark)
	# 4 条腿上接圆望板 + 方望板
	_legs4(n, 0.155, 0.155, 0.48, 0.045, c)
	_aprons4(n, 0.34, 0.34, 0.445, 0.05, 0.025, dark)
	# 下层小搁板
	_bx(n, Vector3(0.30, 0.02, 0.30), Vector3(0, 0.14, 0), M.C_WOOD_LIGHT)

# ============================================================
# 台灯（floor，自发光灯罩）
# ============================================================
static func _build_table_lamp(n: Node3D, opts: Dictionary) -> void:
	var base_c := _col(opts, "color", C_BRASS)
	var shade_c := _col(opts, "cushion", Color("ffe3b0"))
	# 底座 + 座身 + 灯杆
	_cy(n, 0.090, 0.110, 0.03, Vector3(0, 0.015, 0), base_c)
	_cy(n, 0.040, 0.070, 0.025, Vector3(0, 0.0425, 0), base_c)
	_cy(n, 0.012, 0.018, 0.20, Vector3(0, 0.155, 0), C_IRON)
	# 自发光灯罩（锥台）+ 上下箍
	_lit_cyl(n, 0.070, 0.140, 0.20, Vector3(0, 0.40, 0), shade_c, 0.85)
	_cy(n, 0.142, 0.142, 0.012, Vector3(0, 0.302, 0), base_c)
	_cy(n, 0.072, 0.072, 0.012, Vector3(0, 0.498, 0), base_c)
	# 灯泡 + 柔光晕（不建 Light3D）
	_lit_sphere(n, 0.045, Vector3(0, 0.40, 0), Color("fff1c8"), 1.0)
	_glow(n, Vector3(0, 0.40, 0.04), 0.55, Color(1.0, 0.82, 0.50, 0.55))

# ============================================================
# 落地灯（floor，自发光灯罩）
# ============================================================
static func _build_floor_lamp(n: Node3D, opts: Dictionary) -> void:
	var base_c := _col(opts, "color", C_BRASS)
	var shade_c := _col(opts, "cushion", Color("ffe3b0"))
	# 圆底盘 + 灯杆 + 中段装饰球
	_cy(n, 0.130, 0.160, 0.04, Vector3(0, 0.02, 0), base_c)
	_cy(n, 0.020, 0.026, 1.18, Vector3(0, 0.63, 0), C_IRON)
	_sp(n, 0.045, Vector3(0, 0.62, 0), base_c)
	# 自发光大灯罩 + 上下箍
	_lit_cyl(n, 0.120, 0.200, 0.28, Vector3(0, 1.36, 0), shade_c, 0.85)
	_cy(n, 0.202, 0.202, 0.014, Vector3(0, 1.222, 0), base_c)
	_cy(n, 0.122, 0.122, 0.014, Vector3(0, 1.498, 0), base_c)
	# 灯泡 + 柔光晕
	_lit_sphere(n, 0.06, Vector3(0, 1.30, 0), Color("fff1c8"), 1.0)
	_glow(n, Vector3(0, 1.30, 0.05), 0.90, Color(1.0, 0.82, 0.50, 0.50))

# ============================================================
# 挂钟（wall）
# ============================================================
static func _build_wall_clock(n: Node3D, opts: Dictionary) -> void:
	var c := _col(opts, "color", M.C_WOOD_DARK)
	var face := _col(opts, "cushion", C_CREAM)
	var ink := Color("2f3438")
	# 外框圆环 + 内圈 + 表盘
	_cyr(n, 0.24, 0.24, 0.06, Vector3(0, 0, 0.03), c, Vector3(PI * 0.5, 0, 0))
	_cyr(n, 0.215, 0.215, 0.03, Vector3(0, 0, 0.062), c, Vector3(PI * 0.5, 0, 0))
	_cyr(n, 0.205, 0.205, 0.012, Vector3(0, 0, 0.079), face, Vector3(PI * 0.5, 0, 0))
	# 12 个刻度
	for i in range(12):
		var ang := float(i) * PI / 6.0
		_bxr(n, Vector3(0.012, 0.030, 0.006), Vector3(sin(ang) * 0.168, cos(ang) * 0.168, 0.086), ink, Vector3(0, 0, -ang))
	# 时针 / 分针 / 中心轴帽
	var hour_ang := 0.9
	var min_ang := 2.2
	_bxr(n, Vector3(0.018, 0.105, 0.006), Vector3(sin(hour_ang) * 0.052, cos(hour_ang) * 0.052, 0.091), ink, Vector3(0, 0, -hour_ang))
	_bxr(n, Vector3(0.014, 0.155, 0.006), Vector3(sin(min_ang) * 0.077, cos(min_ang) * 0.077, 0.093), ink, Vector3(0, 0, -min_ang))
	_sp(n, 0.018, Vector3(0, 0, 0.096), C_BRASS)

# ============================================================
# 画框（wall，内置一幅小风景）
# ============================================================
static func _build_picture_frame(n: Node3D, opts: Dictionary) -> void:
	var c := _col(opts, "color", M.C_WOOD_DARK)
	var canvas := _col(opts, "cushion", C_PAPER)
	# 背板 + 画布
	_bx(n, Vector3(0.62, 0.48, 0.03), Vector3(0, 0, 0.015), c)
	_bx(n, Vector3(0.54, 0.40, 0.01), Vector3(0, 0, 0.036), canvas)
	# 四条外框（前凸 0.05）
	_bx(n, Vector3(0.62, 0.06, 0.05), Vector3(0, 0.21, 0.025), c)
	_bx(n, Vector3(0.62, 0.06, 0.05), Vector3(0, -0.21, 0.025), c)
	_bx(n, Vector3(0.06, 0.36, 0.05), Vector3(-0.28, 0, 0.025), c)
	_bx(n, Vector3(0.06, 0.36, 0.05), Vector3(0.28, 0, 0.025), c)
	# 画内风景：天空 + 草地 + 两座三角山 + 太阳
	_bx(n, Vector3(0.52, 0.24, 0.008), Vector3(0, 0.075, 0.043), canvas.lightened(0.03))
	_bx(n, Vector3(0.52, 0.055, 0.010), Vector3(0, -0.165, 0.043), Color("8a9a6a"))
	M.prism(n, 0.34, 0.17, 0.012, Vector3(-0.07, -0.135, 0.043), Color("6f8a5a"), 0.0, {"outline": 0.02})
	M.prism(n, 0.24, 0.12, 0.012, Vector3(0.13, -0.135, 0.043), Color("54704a"), 0.0, {"outline": 0.02})
	_cyr(n, 0.042, 0.042, 0.008, Vector3(0.155, 0.105, 0.043), M.C_FLOWER_YELLOW, Vector3(PI * 0.5, 0, 0))

# ============================================================
# 窗帘（wall，由原点向下悬挂；两幅并排由 lead 摆放）
# ============================================================
static func _build_curtain(n: Node3D, opts: Dictionary) -> void:
	var c := _col(opts, "color", Color("c9a78e"))
	var rod_c := _col(opts, "cushion", M.C_WOOD_DARK)
	# 窗帘杆（沿局部 X）与两端球
	_cyr(n, 0.015, 0.015, 0.66, Vector3(0, 0.015, 0.06), rod_c, Vector3(0, 0, PI * 0.5))
	_sp(n, 0.030, Vector3(-0.345, 0.015, 0.06), C_BRASS)
	_sp(n, 0.030, Vector3(0.345, 0.015, 0.06), C_BRASS)
	# 帘布主体（顶边 -0.02，底边 -1.62）
	_bx(n, Vector3(0.56, 1.60, 0.030), Vector3(0, -0.82, 0.030), c)
	# 4 道竖向褶皱（前凸）
	for i in range(4):
		_bx(n, Vector3(0.05, 1.60, 0.035), Vector3(-0.21 + float(i) * 0.14, -0.82, 0.050), c.darkened(0.07))
	# 顶部环扣（5 个）
	for i in range(5):
		_cyr(n, 0.022, 0.022, 0.014, Vector3(-0.24 + float(i) * 0.12, -0.012, 0.055), C_BRASS, Vector3(PI * 0.5, 0, 0))
	# 束带 + 结
	_bx(n, Vector3(0.60, 0.05, 0.06), Vector3(0, -0.95, 0.048), Color("b08a5a"))
	_sp(n, 0.030, Vector3(0.10, -0.95, 0.075), Color("b08a5a"))

# ============================================================
# 柴火篮（floor）
# ============================================================
static func _build_firewood_basket(n: Node3D, opts: Dictionary) -> void:
	var c := _col(opts, "color", C_WICKER)
	var dark := c.darkened(0.18)
	var bark := _col(opts, "cushion", Color("6b4f3a"))
	# 篮底 + 四壁 + 上沿
	_bx(n, Vector3(0.52, 0.02, 0.38), Vector3(0, 0.01, 0), dark)
	_bx(n, Vector3(0.54, 0.30, 0.03), Vector3(0, 0.19, -0.185), c)
	_bx(n, Vector3(0.54, 0.30, 0.03), Vector3(0, 0.19, 0.185), c)
	_bx(n, Vector3(0.03, 0.30, 0.34), Vector3(-0.265, 0.19, 0), c)
	_bx(n, Vector3(0.03, 0.30, 0.34), Vector3(0.265, 0.19, 0), c)
	_bx(n, Vector3(0.60, 0.05, 0.44), Vector3(0, 0.365, 0), dark)
	# 横向编织条（略大于壁面，形成绑条观感）
	for i in range(4):
		_bx(n, Vector3(0.56, 0.018, 0.42), Vector3(0, 0.075 + float(i) * 0.075, 0), c.lightened(0.05))
	# 柴火（横放，沿 X）
	var logs := [
		Vector3(0.0, 0.14, -0.075), Vector3(0.0, 0.14, 0.075),
		Vector3(0.0, 0.245, -0.045), Vector3(0.0, 0.245, 0.100),
	]
	for i in range(logs.size()):
		var lp: Vector3 = logs[i]
		_cyr(n, 0.048, 0.052, 0.54, lp, bark, Vector3(0, 0, PI * 0.5))
		_cyr(n, 0.040, 0.040, 0.012, Vector3(-0.275, lp.y, lp.z), Color("b08a5a"), Vector3(0, 0, PI * 0.5))
		_cyr(n, 0.040, 0.040, 0.012, Vector3(0.275, lp.y, lp.z), Color("b08a5a"), Vector3(0, 0, PI * 0.5))
	# 斜插的引火柴
	_bxr(n, Vector3(0.030, 0.24, 0.030), Vector3(-0.10, 0.37, 0.02), bark.lightened(0.10), Vector3(0.30, 0.20, 0.18))
	_bxr(n, Vector3(0.025, 0.22, 0.025), Vector3(0.06, 0.36, -0.02), bark, Vector3(-0.18, -0.25, -0.12))

# ============================================================
# 盆栽（floor）
# ============================================================
static func _build_plant_pot(n: Node3D, opts: Dictionary) -> void:
	var pot_c := _col(opts, "color", M.C_TERRACOTTA)
	var leaf_a := _col(opts, "cushion", M.C_LEAF_A)
	var leaf_b := leaf_a.lightened(0.10)
	var leaf_c := leaf_a.darkened(0.12)
	# 花盆 + 盆沿 + 土
	_cy(n, 0.170, 0.120, 0.28, Vector3(0, 0.14, 0), pot_c)
	_cy(n, 0.185, 0.175, 0.05, Vector3(0, 0.30, 0), pot_c.darkened(0.10))
	_cy(n, 0.160, 0.160, 0.02, Vector3(0, 0.335, 0), M.C_SOIL)
	# 3 根茎（斜向上）
	var stems := [Vector3(-0.04, 0.42, 0.02), Vector3(0.05, 0.45, -0.03), Vector3(0.0, 0.48, 0.05)]
	for sp in stems:
		_bxr(n, Vector3(0.018, 0.22, 0.018), sp, M.C_LEAF_C, Vector3(0.22, 0.0, 0.18))
	# 7 片椭球叶：绕中心放射、略微下垂
	var lcols := [leaf_a, leaf_b, leaf_c]
	for i in range(7):
		var ang := float(i) * TAU / 7.0 + 0.35
		var rr := 0.115
		var ly := 0.50 + 0.045 * float(i % 3)
		var lpos := Vector3(sin(ang) * rr, ly, cos(ang) * rr)
		var leaf := _sp(n, 0.085, lpos, lcols[i % 3], Vector3(1.45, 0.22, 0.55))
		leaf.rotation = Vector3(0.0, ang - PI * 0.5, -0.42)
	# 顶部新叶两片（更竖直）
	for i in range(2):
		var ang2 := 0.9 + float(i) * 2.4
		var leaf2 := _sp(n, 0.070, Vector3(sin(ang2) * 0.05, 0.66 + float(i) * 0.02, cos(ang2) * 0.05), leaf_b, Vector3(1.20, 0.24, 0.50))
		leaf2.rotation = Vector3(0.0, ang2 - PI * 0.5, -0.12)
