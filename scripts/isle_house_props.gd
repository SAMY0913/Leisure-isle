class_name IsleHouseProps
extends RefCounted
## P7-V3.2 室内家具程序化库（T3 全家具比例重建）。
##
## 尺度基准（P7-V3.2《全岛度量衡与世界比例校准》）
## ------------------------------------------------------------------
## * 1 Godot 世界单位 = 1 米；人体基准身高 1.50 m（eye 1.38 / shoulder 1.24 / hand 0.95）。
## * 所有声明尺寸以 scripts/isle_scale_spec.gd 的 _REGISTRY 为唯一真源，
##   MCP 探针 tools/probe_props_p7v3.gd 用真实网格 AABB 逐件复核（±5% PASS）。
## * 每件家具的内部几何比例（桌面厚 / 桌腿 / 座面 / 靠背 / 床垫 / 层距 / 抽屉分缝 /
##   灯杆灯罩）都按新尺度重算，不是整体缩放。
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
##   本模块不建 Light3D，也不注册光源：光源位置由 cottage.gd 的 light_sources 统一登记，
##   main.gd 每帧写进 toon.gdshader 的解析点光槽（g_l0..g_l15）。
##   P8.1-06 起灯罩（light_shade）self_lit=false + glow=0.85（罩体受光有层次），
##   灯泡仍 self_lit=true 作为高光核心。
## * 材质统一走 isle_math 的 toon 材质缓存（M.C_WOOD / M.C_WOOD_LIGHT / M.C_WOOD_DARK +
##   布艺色），所有可见部件描边 0.02（{outline: 0.02}），避免方块堆观感。
## * 自动命名 Prop_<kind>_<seq>，重复 build 不会出现节点重名。
## * 关键子件写 meta "prop_role"（tabletop / seat / mattress / pillow / shelf /
##   door_handle / drawer_handle / light_shade / leg / apron / pedestal），
##   供探针量真实子高度做人体工学复核；不影响合批与渲染。
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

# 声明尺寸：Vector3(宽 X, 深 Z, 高 Y)，单位米（与 isle_scale_spec.gd 目标表一致）
const DIMS := {
	"doormat": Vector3(1.00, 0.60, 0.020),
	"coat_rack": Vector3(0.80, 0.14, 1.20),
	"shoe_bench": Vector3(0.80, 0.32, 0.42),
	"dining_table": Vector3(1.30, 0.80, 0.65),
	"chair": Vector3(0.42, 0.44, 0.85),
	"sofa": Vector3(1.50, 0.80, 0.78),
	"armchair": Vector3(0.72, 0.76, 0.78),
	"coffee_table": Vector3(0.95, 0.50, 0.38),
	"rug": Vector3(2.20, 1.60, 0.020),
	"bookshelf": Vector3(0.85, 0.30, 1.75),
	"sideboard": Vector3(1.00, 0.40, 0.80),
	"tall_cupboard": Vector3(0.80, 0.40, 1.70),
	"bed": Vector3(1.00, 1.90, 0.85),
	"nightstand": Vector3(0.40, 0.38, 0.50),
	"wardrobe": Vector3(1.00, 0.55, 1.75),
	"desk": Vector3(1.20, 0.60, 0.65),
	"reading_chair": Vector3(0.70, 0.72, 1.05),
	"side_table": Vector3(0.40, 0.40, 0.50),
	"table_lamp": Vector3(0.24, 0.24, 0.50),
	"floor_lamp": Vector3(0.36, 0.36, 1.45),
	"wall_clock": Vector3(0.40, 0.10, 0.40),
	"picture_frame": Vector3(0.55, 0.04, 0.42),
	"curtain": Vector3(0.70, 0.08, 1.35),
	"firewood_basket": Vector3(0.52, 0.38, 0.44),
	"plant_pot": Vector3(0.42, 0.42, 0.70),
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
	# 宽/深/高微调（局部缩放；仅在显式覆盖时使用，不用于比例重建）
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

## 给关键子件打角色 meta（探针量真实子高度用；不改名、不影响合批）。
static func _role(mi: MeshInstance3D, role: String) -> MeshInstance3D:
	mi.set_meta("prop_role", role)
	return mi

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

## 灯罩（P8.1-06）：罩体不再整体自发光（self_lit=false），只保留 glow 维持"灯罩是亮的"，
## 其余亮度来自解析点光/环境光 → 罩体表面出现受光层次，灯本身也能照亮周围家具与地面。
## 灯泡（_lit_sphere）仍 self_lit=true：小、被罩体半遮挡，作为高光核心。
static func _shade_cyl(p: Node3D, top_r: float, bot_r: float, h: float, pos: Vector3, c: Color, glow: float = 0.85) -> MeshInstance3D:
	return M.cyl(p, top_r, bot_r, h, pos, c, 0.0, {"outline": 0.02, "self_lit": false, "glow": glow})

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

## 四条方腿：hx/hz 为腿心到中心的半距，h 为腿高（从 y0 起）。角色 leg。
static func _legs4(p: Node3D, hx: float, hz: float, h: float, t: float, c: Color, y0: float = 0.0) -> void:
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_role(_bx(p, Vector3(t, h, t), Vector3(float(sx) * hx, y0 + h * 0.5, float(sz) * hz), c), "leg")

## 四面望板：w/d 为外沿尺寸，t 为板厚，y 为板中心高。角色 apron。
static func _aprons4(p: Node3D, w: float, d: float, y: float, h: float, t: float, c: Color) -> void:
	_role(_bx(p, Vector3(w - 2.0 * t, h, t), Vector3(0, y, -(d * 0.5 - t * 0.5)), c), "apron")
	_role(_bx(p, Vector3(w - 2.0 * t, h, t), Vector3(0, y, d * 0.5 - t * 0.5), c), "apron")
	_role(_bx(p, Vector3(t, h, d - 2.0 * t), Vector3(-(w * 0.5 - t * 0.5), y, 0), c), "apron")
	_role(_bx(p, Vector3(t, h, d - 2.0 * t), Vector3(w * 0.5 - t * 0.5, y, 0), c), "apron")

## 柜门：face_z 为门板前表面 z，门朝 +Z。内嵌凸板和把手均从 face_z 向 +Z 叠层（总外凸 0.013）。
## 把手写 prop_role=door_handle 供探针检查操作高度。
static func _panel_door(p: Node3D, w: float, h: float, cx: float, cy: float, face_z: float, face_c: Color, inner_c: Color, handle_c: Color = C_BRASS, handle_side: float = 1.0) -> void:
	_bx(p, Vector3(w, h, 0.024), Vector3(cx, cy, face_z - 0.012), face_c)
	_bx(p, Vector3(w - 0.09, h - 0.09, 0.008), Vector3(cx, cy, face_z + 0.003), inner_c)
	_role(_bx(p, Vector3(0.014, minf(h * 0.30, 0.18), 0.010), Vector3(cx + w * 0.30 * handle_side, cy, face_z + 0.008), handle_c), "door_handle")

## 抽屉面：face_z 为抽屉前表面 z，朝 +Z。
static func _drawer_front(p: Node3D, w: float, h: float, cx: float, cy: float, face_z: float, face_c: Color, handle_c: Color = C_BRASS) -> void:
	_bx(p, Vector3(w, h, 0.024), Vector3(cx, cy, face_z - 0.012), face_c)
	_bx(p, Vector3(w - 0.06, h - 0.045, 0.006), Vector3(cx, cy, face_z + 0.003), face_c.darkened(0.10))
	_role(_bx(p, Vector3(minf(w * 0.42, 0.16), 0.012, 0.010), Vector3(cx, cy, face_z + 0.008), handle_c), "drawer_handle")

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
# 入门垫（floor，1.00 × 0.60 × 0.02）
# ============================================================
static func _build_doormat(n: Node3D, opts: Dictionary) -> void:
	var base: Vector3 = DIMS["doormat"]
	var w := base.x
	var d := base.y
	var c := _col(opts, "color", C_DOORMAT)
	var inner := _col(opts, "cushion", Color("b98a70"))
	var edge := Color("6a4a36")
	# 基底 0..0.012；包边 0.012..0.017；编织面 0.013..0.018；条纹顶 0.020
	_bx(n, Vector3(w, 0.012, d), Vector3(0, 0.006, 0), c)
	_bx(n, Vector3(w - 0.04, 0.005, 0.08), Vector3(0, 0.0145, -(d * 0.5 - 0.05)), edge)
	_bx(n, Vector3(w - 0.04, 0.005, 0.08), Vector3(0, 0.0145, d * 0.5 - 0.05), edge)
	_bx(n, Vector3(0.08, 0.005, d - 0.18), Vector3(-(w * 0.5 - 0.05), 0.0145, 0), edge)
	_bx(n, Vector3(0.08, 0.005, d - 0.18), Vector3(w * 0.5 - 0.05, 0.0145, 0), edge)
	_bx(n, Vector3(w - 0.24, 0.005, d - 0.22), Vector3(0, 0.0155, 0), inner)
	for i in range(3):
		_bx(n, Vector3(w - 0.32, 0.002, 0.05), Vector3(0, 0.019, -0.16 + float(i) * 0.16), Color("7a5442"))

# ============================================================
# 挂衣板（wall，0.80 宽 × 0.14 深 × 1.20 高；挂钩约在 +0.28 → 挂高 1.20 当原点在 0.92）
# ============================================================
static func _build_coat_rack(n: Node3D, opts: Dictionary) -> void:
	var base: Vector3 = DIMS["coat_rack"]
	var w := base.x
	var d := base.y
	var h := base.z
	var c := _col(opts, "color", M.C_WOOD_LIGHT)
	var dark := M.C_WOOD_DARK
	var hook := _col(opts, "cushion", C_BRASS)
	# 背板 z 0..0.03
	_bx(n, Vector3(w - 0.06, h - 0.16, 0.030), Vector3(0, 0, 0.015), c)
	# 顶搁板：宽/深/顶高（±0.60）三向极值
	_bx(n, Vector3(w, 0.05, d), Vector3(0, h * 0.5 - 0.025, d * 0.5), dark)
	# 底搁板：底 -0.60
	_bx(n, Vector3(w, 0.04, d - 0.02), Vector3(0, -(h * 0.5 - 0.02), d * 0.5 - 0.01), dark)
	# 背板竖装饰条 + 挂帽横杆
	for i in range(3):
		_bx(n, Vector3(0.030, h - 0.30, 0.008), Vector3(-0.27 + float(i) * 0.27, 0, 0.034), dark)
	_bx(n, Vector3(w - 0.10, 0.030, 0.030), Vector3(0, h * 0.5 - 0.22, 0.10), C_IRON)
	# 4 个黄铜挂钩：圆柱钩臂（沿 Z）+ 球头，z 极限 0.138 < 0.14
	for i in range(4):
		var hx := -0.26 + float(i) * 0.173
		_cyr(n, 0.014, 0.014, 0.080, Vector3(hx, h * 0.5 - 0.32, 0.09), hook, Vector3(PI * 0.5, 0.0, 0.0))
		_sp(n, 0.010, Vector3(hx, h * 0.5 - 0.32, 0.128), hook)

# ============================================================
# 换鞋凳（floor，0.80 × 0.32 × 0.42；坐垫顶 0.42）
# ============================================================
static func _build_shoe_bench(n: Node3D, opts: Dictionary) -> void:
	var base: Vector3 = DIMS["shoe_bench"]
	var w := base.x
	var d := base.y
	var h := base.z
	var c := _col(opts, "color", M.C_WOOD)
	var fab := _col(opts, "cushion", C_ROSE)
	var dark := M.C_WOOD_DARK
	# 坐垫：顶 0.42，宽/深极值
	_role(_bx(n, Vector3(w, 0.055, d), Vector3(0, h - 0.0275, 0), fab), "seat")
	_bx(n, Vector3(w - 0.02, 0.020, d - 0.02), Vector3(0, h - 0.065, 0), fab.darkened(0.10))
	# 座框
	_bx(n, Vector3(w - 0.06, 0.050, d - 0.05), Vector3(0, 0.325, 0), dark)
	# 四腿 + 侧枨
	_legs4(n, w * 0.5 - 0.05, d * 0.5 - 0.05, 0.30, 0.045, c)
	for sx in [-1.0, 1.0]:
		_bx(n, Vector3(0.030, 0.030, d - 0.10), Vector3(float(sx) * (w * 0.5 - 0.05), 0.10, 0), c)
	# 鞋板 + 分隔条
	_bx(n, Vector3(w - 0.12, 0.020, d - 0.08), Vector3(0, 0.14, 0), M.C_WOOD_LIGHT)
	for sx in [-1.0, 1.0]:
		_bx(n, Vector3(0.020, 0.050, d - 0.10), Vector3(float(sx) * 0.245, 0.165, 0), dark)

# ============================================================
# 餐桌（floor，1.30 × 0.80 × 0.65；桌面顶 0.65，望板下沿 0.515）
# ============================================================
static func _build_dining_table(n: Node3D, opts: Dictionary) -> void:
	var base: Vector3 = DIMS["dining_table"]
	var w := base.x
	var d := base.y
	var h := base.z
	var c := _col(opts, "color", M.C_WOOD)
	var dark := M.C_WOOD_DARK
	# 桌面 0.035 厚（顶 0.65）+ 下缘压边
	_role(_bx(n, Vector3(w, 0.035, d), Vector3(0, h - 0.0175, 0), c), "tabletop")
	_bx(n, Vector3(w - 0.04, 0.020, d - 0.04), Vector3(0, h - 0.045, 0), dark)
	# 四面望板：下沿 0.515，桌面 0.65 与椅面 0.40 之间留 0.115 腿部/坐姿空间
	_aprons4(n, w - 0.18, d - 0.18, 0.565, 0.10, 0.03, dark)
	# 4 条车木腿（脚端 r=0.040 恰好补足占地角）+ 顶箍
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var lx: float = float(sx) * (w * 0.5 - 0.055)
			var lz: float = float(sz) * (d * 0.5 - 0.055)
			_role(_cy(n, 0.032, 0.040, 0.60, Vector3(lx, 0.30, lz), c), "leg")
			_cy(n, 0.055, 0.055, 0.030, Vector3(lx, 0.60, lz), c)
			_cy(n, 0.040, 0.048, 0.028, Vector3(lx, 0.014, lz), dark)
	# 长向/短向横枨
	for sz in [-1.0, 1.0]:
		_bx(n, Vector3(1.16, 0.030, 0.030), Vector3(0, 0.18, float(sz) * 0.345), dark)
	for sx in [-1.0, 1.0]:
		_bx(n, Vector3(0.030, 0.030, 0.66), Vector3(float(sx) * 0.595, 0.18, 0), dark)

# ============================================================
# 餐椅（floor，0.42 × 0.44 × 0.85；座面 0.40，靠背顶 0.85）
# ============================================================
static func _build_chair(n: Node3D, opts: Dictionary) -> void:
	var base: Vector3 = DIMS["chair"]
	var w := base.x
	var d := base.y
	var h := base.z
	var c := _col(opts, "color", M.C_WOOD)
	var fab := _col(opts, "cushion", C_ROSE)
	var dark := M.C_WOOD_DARK
	# 座板（0.045 厚，顶 0.38）+ 坐垫（顶 0.40，座面基准）
	_bx(n, Vector3(w, 0.045, d), Vector3(0, 0.3575, 0), c)
	_role(_bx(n, Vector3(w - 0.02, 0.020, d - 0.02), Vector3(0, 0.39, 0), fab), "seat")
	# 前腿（0..0.335）
	for sx in [-1.0, 1.0]:
		_bx(n, Vector3(0.038, 0.335, 0.038), Vector3(float(sx) * 0.17, 0.1675, 0.17), c)
	# 后腿兼靠背柱（0..0.85，后缘触 -0.22）
	for sx in [-1.0, 1.0]:
		_bx(n, Vector3(0.038, h, 0.038), Vector3(float(sx) * 0.17, h * 0.5, -(d * 0.5 - 0.019)), c)
	# 靠背中板 + 内嵌浅色板 + 顶横档（顶 0.85）
	_bx(n, Vector3(w - 0.10, 0.24, 0.030), Vector3(0, 0.60, -0.20), c)
	_bx(n, Vector3(w - 0.16, 0.18, 0.012), Vector3(0, 0.60, -0.183), M.C_WOOD_LIGHT)
	_bx(n, Vector3(w - 0.02, 0.050, 0.050), Vector3(0, h - 0.025, -0.195), c)
	# 座框望板 + 四向横撑
	_aprons4(n, w - 0.06, d - 0.06, 0.315, 0.05, 0.02, dark)
	for sx in [-1.0, 1.0]:
		_bx(n, Vector3(0.028, 0.028, 0.32), Vector3(float(sx) * 0.17, 0.12, 0), dark)
	_bx(n, Vector3(0.32, 0.028, 0.028), Vector3(0, 0.12, 0.17), dark)
	_bx(n, Vector3(0.32, 0.028, 0.028), Vector3(0, 0.12, -0.17), dark)

# ============================================================
# 沙发（floor，1.50 × 0.80 × 0.78；坐面 0.40，靠背顶 0.78）
# ============================================================
static func _build_sofa(n: Node3D, opts: Dictionary) -> void:
	var base: Vector3 = DIMS["sofa"]
	var w := base.x
	var d := base.y
	var h := base.z
	var c := _col(opts, "color", M.C_WOOD)
	var fab := _col(opts, "cushion", C_ROSE)
	var fab_d := fab.darkened(0.14)
	var dark := M.C_WOOD_DARK
	# 底座 0.13..0.31（宽/深极值）
	_bx(n, Vector3(w, 0.18, d), Vector3(0, 0.22, 0), Color("7a4f3f"))
	_legs4(n, w * 0.5 - 0.09, d * 0.5 - 0.08, 0.13, 0.07, dark)
	# 两块坐垫：顶 0.40（扶手内净宽 = W - 2×0.13）
	var cw: float = (w - 0.26) * 0.5
	for sx in [-1.0, 1.0]:
		var cx: float = float(sx) * (cw * 0.5 + 0.005)
		_role(_bx(n, Vector3(cw, 0.09, d - 0.24), Vector3(cx, 0.355, 0.08), fab), "seat")
		_bx(n, Vector3(cw - 0.02, 0.05, 0.012), Vector3(cx, 0.345, 0.366), fab.darkened(0.10))
	# 靠背主体（z -0.40..-0.24）+ 顶圆边（顶 0.78）
	_bx(n, Vector3(w - 0.02, 0.32, 0.16), Vector3(0, 0.52, -0.32), fab_d)
	_cyr(n, 0.055, 0.055, w - 0.04, Vector3(0, h - 0.055, -0.32), fab_d, Vector3(0, 0, PI * 0.5))
	# 两块斜靠软垫
	for sx in [-1.0, 1.0]:
		_bxr(n, Vector3(cw - 0.03, 0.26, 0.10), Vector3(float(sx) * (cw * 0.5 + 0.005), 0.55, -0.245), fab, Vector3(-0.10, 0, 0))
	# 扶手 + 扶手顶圆边（外侧触 ±0.75）
	for sx in [-1.0, 1.0]:
		var ax: float = float(sx) * (w * 0.5 - 0.065)
		_bx(n, Vector3(0.13, 0.36, d), Vector3(ax, 0.47, 0), fab_d)
		_cyr(n, 0.062, 0.062, d - 0.02, Vector3(ax, 0.65, 0), fab_d, Vector3(PI * 0.5, 0, 0))
	# 前裙板
	_bx(n, Vector3(w - 0.16, 0.055, 0.030), Vector3(0, 0.16, 0.385), dark)

# ============================================================
# 扶手椅（floor，0.72 × 0.76 × 0.78；坐面 0.40，靠背顶 0.78）
# ============================================================
static func _build_armchair(n: Node3D, opts: Dictionary) -> void:
	var base: Vector3 = DIMS["armchair"]
	var w := base.x
	var d := base.y
	var h := base.z
	var c := _col(opts, "color", M.C_WOOD)
	var fab := _col(opts, "cushion", C_SAGE)
	var fab_d := fab.darkened(0.14)
	var dark := M.C_WOOD_DARK
	# 底座 + 四腿
	_bx(n, Vector3(w, 0.18, d), Vector3(0, 0.22, 0), fab_d)
	_legs4(n, w * 0.5 - 0.07, d * 0.5 - 0.07, 0.13, 0.06, dark)
	# 座垫（顶 0.40）
	_role(_bx(n, Vector3(w - 0.26, 0.09, d - 0.30), Vector3(0, 0.355, 0.06), fab), "seat")
	# 靠背 + 靠垫 + 顶圆边（顶 0.78）
	_bx(n, Vector3(w - 0.02, 0.30, 0.15), Vector3(0, 0.52, -0.305), fab_d)
	_cyr(n, 0.055, 0.055, w - 0.06, Vector3(0, h - 0.055, -0.305), fab_d, Vector3(0, 0, PI * 0.5))
	_bxr(n, Vector3(0.44, 0.24, 0.10), Vector3(0, 0.55, -0.23), fab, Vector3(-0.09, 0, 0))
	# 扶手 + 顶圆边（外侧触 ±0.36）
	for sx in [-1.0, 1.0]:
		var ax: float = float(sx) * (w * 0.5 - 0.065)
		_bx(n, Vector3(0.13, 0.36, d), Vector3(ax, 0.47, 0), fab_d)
		_cyr(n, 0.062, 0.062, d - 0.02, Vector3(ax, 0.65, 0), fab_d, Vector3(PI * 0.5, 0, 0))
	# 前裙板
	_bx(n, Vector3(w - 0.16, 0.055, 0.030), Vector3(0, 0.16, 0.365), dark)

# ============================================================
# 茶几（floor，0.95 × 0.50 × 0.38；台面顶 0.38）
# ============================================================
static func _build_coffee_table(n: Node3D, opts: Dictionary) -> void:
	var base: Vector3 = DIMS["coffee_table"]
	var w := base.x
	var d := base.y
	var h := base.z
	var c := _col(opts, "color", M.C_WOOD)
	var dark := M.C_WOOD_DARK
	# 台面 0.03 厚（顶 0.38）+ 压边
	_role(_bx(n, Vector3(w, 0.030, d), Vector3(0, h - 0.015, 0), c), "tabletop")
	_bx(n, Vector3(w - 0.04, 0.018, d - 0.04), Vector3(0, h - 0.039, 0), dark)
	# 4 条方腿 + 望板
	_legs4(n, w * 0.5 - 0.055, d * 0.5 - 0.055, 0.335, 0.05, c)
	_aprons4(n, w - 0.14, d - 0.14, 0.315, 0.05, 0.025, dark)
	# 下层搁板 + 书本/铜盘装饰（全部低于台面）
	_bx(n, Vector3(w - 0.16, 0.020, d - 0.16), Vector3(0, 0.12, 0), M.C_WOOD_LIGHT)
	for sx in [-1.0, 1.0]:
		_bx(n, Vector3(0.020, 0.030, d - 0.20), Vector3(float(sx) * (w * 0.5 - 0.06), 0.14, 0), dark)
	_bx(n, Vector3(0.22, 0.030, 0.16), Vector3(-0.18, 0.145, 0.02), Color("8a5a4a"), 0.20)
	_bx(n, Vector3(0.19, 0.025, 0.14), Vector3(-0.17, 0.1725, 0.01), Color("5d7a6a"), -0.12)
	_cy(n, 0.050, 0.050, 0.030, Vector3(0.20, 0.145, -0.02), C_BRASS)

# ============================================================
# 地毯（floor，2.20 × 1.60 × 0.02，叠层避免 z-fighting）
# ============================================================
static func _build_rug(n: Node3D, opts: Dictionary) -> void:
	var base: Vector3 = DIMS["rug"]
	var w := base.x
	var d := base.y
	var c := _col(opts, "color", Color("9a6b5c"))
	var edge := _col(opts, "cushion", Color("c9a78e"))
	var accent := edge.darkened(0.18)
	# 基底 0..0.012；包边 0.012..0.017；织面 0.013..0.018；花纹顶 0.020
	_bx(n, Vector3(w, 0.012, d), Vector3(0, 0.006, 0), c)
	_bx(n, Vector3(w, 0.005, 0.12), Vector3(0, 0.0145, -(d * 0.5 - 0.06)), edge)
	_bx(n, Vector3(w, 0.005, 0.12), Vector3(0, 0.0145, d * 0.5 - 0.06), edge)
	_bx(n, Vector3(0.12, 0.005, d - 0.24), Vector3(-(w * 0.5 - 0.06), 0.0145, 0), edge)
	_bx(n, Vector3(0.12, 0.005, d - 0.24), Vector3(w * 0.5 - 0.06, 0.0145, 0), edge)
	_bx(n, Vector3(w - 0.26, 0.005, d - 0.26), Vector3(0, 0.0155, 0), edge.lightened(0.05))
	for i in range(3):
		_bx(n, Vector3(w - 0.36, 0.002, 0.06), Vector3(0, 0.019, -0.28 + float(i) * 0.28), accent)
	for i in range(9):
		var z := -0.72 + float(i) * 0.18
		_bx(n, Vector3(0.10, 0.002, 0.03), Vector3(-(w * 0.5 - 0.06), 0.019, z), accent)
		_bx(n, Vector3(0.10, 0.002, 0.03), Vector3(w * 0.5 - 0.06, 0.019, z), accent)

# ============================================================
# 书架（floor，0.85 × 0.30 × 1.75；5 格，层距 0.303/0.333 pitch）
# ============================================================
static func _build_bookshelf(n: Node3D, opts: Dictionary) -> void:
	var base: Vector3 = DIMS["bookshelf"]
	var w := base.x
	var d := base.y
	var h := base.z
	var c := _col(opts, "color", M.C_WOOD)
	var dark := M.C_WOOD_DARK
	# 侧板 / 顶板（宽深高极值）/ 踢脚 / 底板 / 背板
	for sx in [-1.0, 1.0]:
		_bx(n, Vector3(0.032, h - 0.06, d), Vector3(float(sx) * (w * 0.5 - 0.016), 0.875, 0), c)
	_bx(n, Vector3(w, 0.035, d), Vector3(0, h - 0.0175, 0), c)
	_bx(n, Vector3(w - 0.07, 0.030, d - 0.02), Vector3(0, 0.015, 0), dark)
	_role(_bx(n, Vector3(w - 0.064, 0.030, d - 0.02), Vector3(0, 0.065, 0), c), "shelf")
	_bx(n, Vector3(w - 0.07, 1.66, 0.016), Vector3(0, 0.88, -(d * 0.5 - 0.008)), dark)
	# 4 块层板：净高 0.303，层距 0.333（目标 0.28–0.34）
	var shelf_ys := [0.398, 0.731, 1.064, 1.397]
	for sy in shelf_ys:
		_role(_bx(n, Vector3(w - 0.064, 0.030, d - 0.04), Vector3(0, float(sy), 0.01), c), "shelf")
	# 各层书 + 小摆件（书高 0.19–0.256 < 0.303 净高）
	var cols: Array = _book_colors()
	for si in range(4):
		var top_y: float = float(shelf_ys[si]) + 0.015
		_book_row(n, -0.37, -0.01, top_y, 6, si)
		if si == 1:
			_bx(n, Vector3(0.20, 0.032, 0.15), Vector3(0.20, top_y + 0.016, 0.0), cols[(si + 2) % cols.size()])
		elif si == 2:
			_cy(n, 0.035, 0.035, 0.12, Vector3(0.26, top_y + 0.06, 0.02), C_CERAMIC)
		elif si == 3:
			_sp(n, 0.05, Vector3(0.26, top_y + 0.05, 0.0), cols[(si + 4) % cols.size()], Vector3(1.0, 0.7, 1.0))

# ============================================================
# 矮边柜（floor，1.00 × 0.40 × 0.80；台面顶 0.80）
# ============================================================
static func _build_sideboard(n: Node3D, opts: Dictionary) -> void:
	var base: Vector3 = DIMS["sideboard"]
	var w := base.x
	var d := base.y
	var h := base.z
	var c := _col(opts, "color", M.C_WOOD)
	var dark := M.C_WOOD_DARK
	# 台面（宽/深/顶高极值）+ 下缘压边
	_role(_bx(n, Vector3(w, 0.030, d), Vector3(0, h - 0.015, 0), c), "tabletop")
	_bx(n, Vector3(w - 0.02, 0.018, d - 0.02), Vector3(0, h - 0.039, 0), dark)
	# 柜体 0.17..0.75 + 四腿
	_bx(n, Vector3(w - 0.04, 0.58, d - 0.04), Vector3(0, 0.46, 0), c)
	_legs4(n, w * 0.5 - 0.05, d * 0.5 - 0.05, 0.17, 0.04, dark)
	# 两扇门 + 顶部两抽屉（前表面 z=0.18，把手外凸 0.013 → 0.193 < 0.20）
	var face_z: float = d * 0.5 - 0.02
	_panel_door(n, 0.42, 0.34, -0.235, 0.46, face_z, c, M.C_WOOD_LIGHT, C_BRASS, 1.0)
	_panel_door(n, 0.42, 0.34, 0.235, 0.46, face_z, c, M.C_WOOD_LIGHT, C_BRASS, -1.0)
	_drawer_front(n, 0.42, 0.10, -0.235, 0.69, face_z, c, C_BRASS)
	_drawer_front(n, 0.42, 0.10, 0.235, 0.69, face_z, c, C_BRASS)
	# 分缝线
	_bx(n, Vector3(0.012, 0.56, 0.012), Vector3(0, 0.46, face_z + 0.006), dark)
	_bx(n, Vector3(w - 0.08, 0.012, 0.012), Vector3(0, 0.635, face_z + 0.006), dark)

# ============================================================
# 高柜（floor，0.80 × 0.40 × 1.70；抽屉/门把手 0.45/1.06 → 操作高度 0.4–1.6）
# ============================================================
static func _build_tall_cupboard(n: Node3D, opts: Dictionary) -> void:
	var base: Vector3 = DIMS["tall_cupboard"]
	var w := base.x
	var d := base.y
	var h := base.z
	var c := _col(opts, "color", M.C_WOOD)
	var dark := M.C_WOOD_DARK
	# 踢脚 / 柜体 / 顶檐（宽/深/顶高极值）
	_bx(n, Vector3(w - 0.05, 0.090, d - 0.04), Vector3(0, 0.045, 0), dark)
	_bx(n, Vector3(w - 0.02, 1.52, d - 0.03), Vector3(0, 0.85, 0), c)
	_bx(n, Vector3(w, 0.090, d), Vector3(0, h - 0.045, 0), dark)
	_bx(n, Vector3(w - 0.04, 0.020, d - 0.04), Vector3(0, h - 0.10, 0), c)
	# 背板
	_bx(n, Vector3(w - 0.06, 1.50, 0.016), Vector3(0, 0.86, -(d * 0.5 - 0.02)), dark)
	# 下部两抽屉（0.36..0.54）+ 上部两扇门（0.55..1.57）
	var face_z: float = d * 0.5 - 0.02
	_drawer_front(n, 0.34, 0.18, -0.185, 0.45, face_z, c, C_BRASS)
	_drawer_front(n, 0.34, 0.18, 0.185, 0.45, face_z, c, C_BRASS)
	_panel_door(n, 0.34, 1.02, -0.185, 1.06, face_z, c, M.C_WOOD_LIGHT, C_BRASS, 1.0)
	_panel_door(n, 0.34, 1.02, 0.185, 1.06, face_z, c, M.C_WOOD_LIGHT, C_BRASS, -1.0)
	# 门中缝 + 上下压线
	_bx(n, Vector3(0.012, 1.04, 0.012), Vector3(0, 1.06, face_z + 0.006), dark)
	_bx(n, Vector3(w - 0.08, 0.012, 0.012), Vector3(0, 0.545, face_z + 0.006), dark)
	_bx(n, Vector3(w - 0.08, 0.012, 0.012), Vector3(0, 1.585, face_z + 0.006), dark)

# ============================================================
# 床（floor，1.00 × 1.90 × 0.85；床垫顶 0.45，床头板顶 0.85，枕头顶约 0.575）
# ============================================================
static func _build_bed(n: Node3D, opts: Dictionary) -> void:
	var base: Vector3 = DIMS["bed"]
	var w := base.x
	var d := base.y
	var h := base.z
	var c := _col(opts, "color", M.C_WOOD)
	var dark := M.C_WOOD_DARK
	var mattress := _col(opts, "mattress", C_CREAM)
	var quilt := _col(opts, "quilt", _col(opts, "cushion", C_ROSE))
	var pillow := _col(opts, "pillow", C_PILLOW)
	# 四腿 + 床架底座 + 两侧床梁
	_legs4(n, w * 0.5 - 0.06, d * 0.5 - 0.06, 0.17, 0.06, dark)
	_bx(n, Vector3(w - 0.04, 0.10, d - 0.06), Vector3(0, 0.22, 0), c)
	for sx in [-1.0, 1.0]:
		_bx(n, Vector3(0.05, 0.16, d - 0.10), Vector3(float(sx) * (w * 0.5 - 0.025), 0.27, 0), dark)
	for i in range(3):
		_bx(n, Vector3(w - 0.14, 0.04, 0.04), Vector3(0, 0.20, -0.62 + float(i) * 0.62), dark)
	# 床头板（-Z 端）：2 立柱 + 大面板 + 内嵌板 + 顶横档（顶 0.85）
	for sx in [-1.0, 1.0]:
		_bx(n, Vector3(0.06, h, 0.05), Vector3(float(sx) * (w * 0.5 - 0.03), h * 0.5, -(d * 0.5 - 0.025)), c)
	_bx(n, Vector3(w - 0.16, 0.46, 0.05), Vector3(0, 0.60, -(d * 0.5 - 0.025)), c)
	_bx(n, Vector3(w - 0.34, 0.30, 0.012), Vector3(0, 0.60, -(d * 0.5 - 0.045)), M.C_WOOD_LIGHT)
	_bx(n, Vector3(w, 0.060, 0.05), Vector3(0, h - 0.03, -(d * 0.5 - 0.025)), c)
	# 床尾板（+Z 端，高 0.55）
	for sx in [-1.0, 1.0]:
		_bx(n, Vector3(0.06, 0.55, 0.05), Vector3(float(sx) * (w * 0.5 - 0.03), 0.275, d * 0.5 - 0.025), c)
	_bx(n, Vector3(w - 0.16, 0.28, 0.05), Vector3(0, 0.36, d * 0.5 - 0.025), c)
	_bx(n, Vector3(w, 0.050, 0.05), Vector3(0, 0.525, d * 0.5 - 0.025), dark)
	# 床垫：0.90 × 0.18 × 1.66，顶 0.45
	_role(_bx(n, Vector3(0.90, 0.18, 1.66), Vector3(0, 0.36, 0), mattress), "mattress")
	# 被子（盖下半段）+ 折边 + 两侧下摆
	_bx(n, Vector3(0.92, 0.060, 1.10), Vector3(0, 0.48, 0.28), quilt)
	_bx(n, Vector3(0.92, 0.050, 0.14), Vector3(0, 0.49, -0.24), quilt.lightened(0.12))
	for sx in [-1.0, 1.0]:
		_bx(n, Vector3(0.020, 0.22, 1.10), Vector3(float(sx) * 0.47, 0.40, 0.28), quilt.darkened(0.05))
	# 枕头（0.44 × 0.11 × 0.30，后仰 0.10 rad，顶约 0.575）
	for sx in [-1.0, 1.0]:
		_role(_bxr(n, Vector3(0.44, 0.11, 0.30), Vector3(float(sx) * 0.235, 0.505, -0.66), pillow, Vector3(-0.10, 0, 0)), "pillow")
		_bx(n, Vector3(0.40, 0.014, 0.26), Vector3(float(sx) * 0.235, 0.560, -0.655), pillow.darkened(0.07))

# ============================================================
# 床头柜（floor，0.40 × 0.38 × 0.50；台面 0.50，比床垫顶 0.45 高 0.05）
# ============================================================
static func _build_nightstand(n: Node3D, opts: Dictionary) -> void:
	var base: Vector3 = DIMS["nightstand"]
	var w := base.x
	var d := base.y
	var h := base.z
	var c := _col(opts, "color", M.C_WOOD)
	var dark := M.C_WOOD_DARK
	# 台面（顶 0.50，宽/深极值）+ 压边
	_role(_bx(n, Vector3(w, 0.025, d), Vector3(0, h - 0.0125, 0), c), "tabletop")
	_bx(n, Vector3(w - 0.01, 0.015, d - 0.01), Vector3(0, h - 0.032, 0), dark)
	# 柜体 + 四腿
	_bx(n, Vector3(w - 0.02, 0.31, d - 0.02), Vector3(0, 0.315, 0), c)
	_legs4(n, w * 0.5 - 0.045, d * 0.5 - 0.045, 0.16, 0.035, dark)
	# 抽屉（把手 0.40）+ 下部格门
	var face_z: float = d * 0.5 - 0.02
	_drawer_front(n, 0.30, 0.13, 0, 0.40, face_z, c, C_BRASS)
	_panel_door(n, 0.30, 0.14, 0, 0.245, face_z, c, M.C_WOOD_LIGHT, C_BRASS, 1.0)

# ============================================================
# 衣柜（floor，1.00 × 0.55 × 1.75；门把手 1.17，抽屉把手 0.42/0.60，操作高度 0.4–1.6）
# ============================================================
static func _build_wardrobe(n: Node3D, opts: Dictionary) -> void:
	var base: Vector3 = DIMS["wardrobe"]
	var w := base.x
	var d := base.y
	var h := base.z
	var c := _col(opts, "color", M.C_WOOD)
	var dark := M.C_WOOD_DARK
	# 踢脚 / 柜体 / 顶檐（宽/深/顶高极值）
	_bx(n, Vector3(w - 0.04, 0.07, d - 0.04), Vector3(0, 0.035, 0), dark)
	_bx(n, Vector3(w, 1.60, d - 0.03), Vector3(0, 0.87, 0), c)
	_bx(n, Vector3(w, 0.080, d), Vector3(0, h - 0.04, 0), dark)
	# 背板
	_bx(n, Vector3(w - 0.06, 1.56, 0.016), Vector3(0, 0.87, -(d * 0.5 - 0.02)), dark)
	# 下部两只全宽抽屉（0.34..0.50 / 0.52..0.68）+ 上部两扇门（0.74..1.60）
	var face_z: float = d * 0.5 - 0.02
	_drawer_front(n, w - 0.06, 0.16, 0, 0.42, face_z, c, C_BRASS)
	_drawer_front(n, w - 0.06, 0.16, 0, 0.60, face_z, c, C_BRASS)
	_panel_door(n, 0.46, 0.86, -0.24, 1.17, face_z, c, M.C_WOOD_LIGHT, C_BRASS, 1.0)
	_panel_door(n, 0.46, 0.86, 0.24, 1.17, face_z, c, M.C_WOOD_LIGHT, C_BRASS, -1.0)
	# 门缝/横向压线
	_bx(n, Vector3(0.012, 0.88, 0.012), Vector3(0, 1.17, face_z + 0.006), dark)
	_bx(n, Vector3(w - 0.08, 0.012, 0.012), Vector3(0, 0.71, face_z + 0.006), dark)
	_bx(n, Vector3(w - 0.08, 0.012, 0.012), Vector3(0, 0.51, face_z + 0.006), dark)

# ============================================================
# 书桌（floor，1.20 × 0.60 × 0.65；桌面 0.65，膝空间净宽 0.44）
# ============================================================
static func _build_desk(n: Node3D, opts: Dictionary) -> void:
	var base: Vector3 = DIMS["desk"]
	var w := base.x
	var d := base.y
	var h := base.z
	var c := _col(opts, "color", M.C_WOOD)
	var dark := M.C_WOOD_DARK
	# 桌面（顶 0.65，宽/深极值）+ 压边
	_role(_bx(n, Vector3(w, 0.035, d), Vector3(0, h - 0.0175, 0), c), "tabletop")
	_bx(n, Vector3(w - 0.04, 0.020, d - 0.04), Vector3(0, h - 0.045, 0), dark)
	# 左右两侧 pedestal（宽 0.36，x=±0.40 → 膝空间 0.44）
	for sx in [-1.0, 1.0]:
		var px: float = float(sx) * 0.40
		_role(_bx(n, Vector3(0.36, 0.60, d - 0.10), Vector3(px, 0.30, 0), c), "pedestal")
		_bx(n, Vector3(0.34, 0.030, d - 0.14), Vector3(px, 0.015, 0), dark)
	# 中间背挡板 + 后横档
	_bx(n, Vector3(0.38, 0.26, 0.020), Vector3(0, 0.45, -(d * 0.5 - 0.05)), dark)
	_bx(n, Vector3(w - 0.10, 0.10, 0.025), Vector3(0, 0.565, -(d * 0.5 - 0.035)), dark)
	# 前脸 z = 0.25（抽屉面外凸 0.013 → 0.263 < 0.30）
	var face_z: float = d * 0.5 - 0.05
	# 左侧 3 抽屉（把手 0.13/0.30/0.47）
	for i in range(3):
		_drawer_front(n, 0.30, 0.15, -0.40, 0.13 + float(i) * 0.17, face_z, c, C_BRASS)
	# 右侧：上 2 抽屉 + 下 1 门
	_drawer_front(n, 0.30, 0.15, 0.40, 0.47, face_z, c, C_BRASS)
	_drawer_front(n, 0.30, 0.15, 0.40, 0.30, face_z, c, C_BRASS)
	_panel_door(n, 0.30, 0.16, 0.40, 0.10, face_z, c, M.C_WOOD_LIGHT, C_BRASS, 1.0)

# ============================================================
# 阅读椅（floor，0.70 × 0.72 × 1.05；坐面 0.40，高靠背顶 1.05）
# ============================================================
static func _build_reading_chair(n: Node3D, opts: Dictionary) -> void:
	var base: Vector3 = DIMS["reading_chair"]
	var w := base.x
	var d := base.y
	var h := base.z
	var c := _col(opts, "color", M.C_WOOD_DARK)
	var fab := _col(opts, "cushion", C_SAGE)
	var fab_d := fab.darkened(0.14)
	var cream := C_CREAM
	# 四腿 + 底座（宽/深极值）
	_legs4(n, w * 0.5 - 0.06, d * 0.5 - 0.06, 0.16, 0.05, c)
	_bx(n, Vector3(w - 0.06, 0.14, d), Vector3(0, 0.23, 0), fab_d)
	# 座垫（顶 0.40）+ 前沿浅色滚边
	_role(_bx(n, Vector3(w - 0.16, 0.10, d - 0.14), Vector3(0, 0.35, 0.05), fab), "seat")
	_bx(n, Vector3(w - 0.18, 0.020, d - 0.16), Vector3(0, 0.395, 0.045), cream)
	# 高靠背（后倾 0.10 rad）+ 顶圆边（顶 1.05）+ 内嵌软垫
	_bxr(n, Vector3(w - 0.06, 0.58, 0.14), Vector3(0, 0.70, -0.26), fab_d, Vector3(-0.10, 0, 0))
	_cyr(n, 0.050, 0.050, w - 0.06, Vector3(0, 1.00, -0.30), fab_d, Vector3(0, 0, PI * 0.5))
	_bxr(n, Vector3(0.48, 0.34, 0.10), Vector3(0, 0.68, -0.16), fab, Vector3(-0.10, 0, 0))
	# 两侧翼板 + 扶手（外侧触 ±0.35）
	for sx in [-1.0, 1.0]:
		var ax: float = float(sx) * (w * 0.5 - 0.06)
		_bxr(n, Vector3(0.080, 0.30, 0.26), Vector3(float(sx) * 0.285, 0.78, -0.21), fab_d, Vector3(-0.06, 0, 0))
		_bx(n, Vector3(0.12, 0.20, 0.60), Vector3(ax, 0.50, 0.02), fab_d)
		_cyr(n, 0.055, 0.055, 0.60, Vector3(ax, 0.60, 0.02), fab_d, Vector3(PI * 0.5, 0, 0))

# ============================================================
# 边几（floor，0.40 × 0.40 × 0.50；台面 0.50，圆台 r≈0.205）
# ============================================================
static func _build_side_table(n: Node3D, opts: Dictionary) -> void:
	var base: Vector3 = DIMS["side_table"]
	var h := base.z
	var c := _col(opts, "color", M.C_WOOD)
	var dark := M.C_WOOD_DARK
	# 圆台面（顶 0.50）— r=0.205 让 10 段圆柱的 x/z AABB 都落在 ±5% 内
	_role(_cy(n, 0.205, 0.205, 0.030, Vector3(0, h - 0.015, 0), c), "tabletop")
	_cy(n, 0.175, 0.185, 0.030, Vector3(0, h - 0.045, 0), dark)
	# 4 条腿上接圆望板 + 方望板
	_legs4(n, 0.155, 0.155, 0.44, 0.040, c)
	_aprons4(n, 0.34, 0.34, 0.425, 0.045, 0.022, dark)
	# 下层小搁板
	_bx(n, Vector3(0.30, 0.020, 0.30), Vector3(0, 0.14, 0), M.C_WOOD_LIGHT)

# ============================================================
# 台灯（floor，0.24 × 0.24 × 0.50；灯罩 r≈0.123，灯杆 0.24，总高 0.50）
# ============================================================
static func _build_table_lamp(n: Node3D, opts: Dictionary) -> void:
	var base: Vector3 = DIMS["table_lamp"]
	var h := base.z
	var base_c := _col(opts, "color", C_BRASS)
	var shade_c := _col(opts, "cushion", Color("ffe3b0"))
	# 底座 0..0.044 + 灯杆 0.044..0.284
	_cy(n, 0.045, 0.055, 0.024, Vector3(0, 0.012, 0), base_c)
	_cy(n, 0.035, 0.045, 0.020, Vector3(0, 0.034, 0), base_c)
	_cy(n, 0.011, 0.016, 0.240, Vector3(0, 0.164, 0), C_IRON)
	# 自发光灯罩（锥台，0.285..0.485，底 r=0.123）+ 上下箍 + 灯泡
	_role(_shade_cyl(n, 0.062, 0.123, 0.200, Vector3(0, 0.385, 0), shade_c, 0.55), "light_shade")
	_cy(n, 0.124, 0.124, 0.012, Vector3(0, 0.288, 0), base_c)
	_cy(n, 0.064, 0.064, 0.010, Vector3(0, 0.486, 0), base_c)
	_lit_sphere(n, 0.030, Vector3(0, 0.390, 0), Color("fff1c8"), 1.0)
	_sp(n, 0.014, Vector3(0, h - 0.014, 0), base_c)
	_glow(n, Vector3(0, 0.39, 0.024), 0.26, Color(1.0, 0.82, 0.50, 0.55))

# ============================================================
# 落地灯（floor，0.36 × 0.36 × 1.45；灯罩 r≈0.1845，顶球顶 1.45）
# ============================================================
static func _build_floor_lamp(n: Node3D, opts: Dictionary) -> void:
	var base: Vector3 = DIMS["floor_lamp"]
	var h := base.z
	var base_c := _col(opts, "color", C_BRASS)
	var shade_c := _col(opts, "cushion", Color("ffe3b0"))
	# 圆底盘 0..0.03 + 灯杆 0.03..1.13 + 中段装饰球
	_cy(n, 0.140, 0.160, 0.030, Vector3(0, 0.015, 0), base_c)
	_cy(n, 0.016, 0.022, 1.100, Vector3(0, 0.58, 0), C_IRON)
	_sp(n, 0.035, Vector3(0, 0.70, 0), base_c)
	# 自发光大灯罩（1.15..1.41，底 r=0.1845）+ 上下箍 + 灯泡
	_role(_shade_cyl(n, 0.105, 0.1845, 0.260, Vector3(0, 1.28, 0), shade_c, 0.55), "light_shade")
	_cy(n, 0.186, 0.186, 0.012, Vector3(0, 1.153, 0), base_c)
	_cy(n, 0.107, 0.107, 0.010, Vector3(0, 1.412, 0), base_c)
	_lit_sphere(n, 0.040, Vector3(0, 1.270, 0), Color("fff1c8"), 1.0)
	_sp(n, 0.024, Vector3(0, h - 0.024, 0), base_c)
	_glow(n, Vector3(0, 1.27, 0.040), 0.70, Color(1.0, 0.82, 0.50, 0.50))

# ============================================================
# 挂钟（wall，0.40 × 0.10 × 0.40；方形背板定 x/y 极值，全部 z 收在 0..0.099）
# ============================================================
static func _build_wall_clock(n: Node3D, opts: Dictionary) -> void:
	var base: Vector3 = DIMS["wall_clock"]
	var w := base.x
	var h := base.z
	var c := _col(opts, "color", M.C_WOOD_DARK)
	var face := _col(opts, "cushion", C_CREAM)
	var ink := Color("2f3438")
	# 方形木背板（宽/高极值，z 0..0.02）
	_bx(n, Vector3(w, h, 0.020), Vector3(0, 0, 0.010), c)
	# 圆框 + 内圈 + 表盘（z 0.017..0.092）
	_cyr(n, 0.185, 0.185, 0.050, Vector3(0, 0, 0.042), c, Vector3(PI * 0.5, 0, 0))
	_cyr(n, 0.170, 0.170, 0.020, Vector3(0, 0, 0.072), c, Vector3(PI * 0.5, 0, 0))
	_role(_cyr(n, 0.163, 0.163, 0.010, Vector3(0, 0, 0.087), face, Vector3(PI * 0.5, 0, 0)), "clock_face")
	# 12 个刻度（z 0.092..0.097）
	for i in range(12):
		var ang := float(i) * PI / 6.0
		_bxr(n, Vector3(0.012, 0.028, 0.005), Vector3(sin(ang) * 0.150, cos(ang) * 0.150, 0.0945), ink, Vector3(0, 0, -ang))
	# 时针 / 分针 / 中心轴帽（z ≤ 0.099）
	var hour_ang := 0.9
	var min_ang := 2.2
	_bxr(n, Vector3(0.018, 0.100, 0.006), Vector3(sin(hour_ang) * 0.052, cos(hour_ang) * 0.052, 0.096), ink, Vector3(0, 0, -hour_ang))
	_bxr(n, Vector3(0.014, 0.145, 0.005), Vector3(sin(min_ang) * 0.072, cos(min_ang) * 0.072, 0.0965), ink, Vector3(0, 0, -min_ang))
	_cyr(n, 0.012, 0.012, 0.006, Vector3(0, 0, 0.096), C_BRASS, Vector3(PI * 0.5, 0, 0))

# ============================================================
# 画框（wall，0.55 × 0.04 × 0.42；四边框条定宽/高/深极值）
# ============================================================
static func _build_picture_frame(n: Node3D, opts: Dictionary) -> void:
	var base: Vector3 = DIMS["picture_frame"]
	var w := base.x
	var h := base.z
	var c := _col(opts, "color", M.C_WOOD_DARK)
	var canvas := _col(opts, "cushion", C_PAPER)
	# 背板 z 0..0.018 + 画布 z 0.018..0.026
	_bx(n, Vector3(w - 0.06, h - 0.06, 0.018), Vector3(0, 0, 0.009), c)
	_bx(n, Vector3(w - 0.12, h - 0.12, 0.008), Vector3(0, 0, 0.022), canvas)
	# 四条外框（z 0..0.04，x/y 极值）
	_bx(n, Vector3(w, 0.050, 0.040), Vector3(0, h * 0.5 - 0.025, 0.020), c)
	_bx(n, Vector3(w, 0.050, 0.040), Vector3(0, -(h * 0.5 - 0.025), 0.020), c)
	_bx(n, Vector3(0.050, h - 0.10, 0.040), Vector3(-(w * 0.5 - 0.025), 0, 0.020), c)
	_bx(n, Vector3(0.050, h - 0.10, 0.040), Vector3(w * 0.5 - 0.025, 0, 0.020), c)
	# 内框斜压条（z 0.032..0.038）
	_bx(n, Vector3(w - 0.10, 0.012, 0.006), Vector3(0, h * 0.5 - 0.056, 0.035), C_BRASS)
	_bx(n, Vector3(w - 0.10, 0.012, 0.006), Vector3(0, -(h * 0.5 - 0.056), 0.035), C_BRASS)
	# 画内风景：天空 / 草地 / 两座山 / 太阳（z 0.026..0.032）
	var art_w: float = w - 0.16
	_bx(n, Vector3(art_w, h - 0.20, 0.004), Vector3(0, 0.020, 0.028), canvas.lightened(0.03))
	_bx(n, Vector3(art_w, 0.050, 0.004), Vector3(0, -0.145, 0.028), Color("8a9a6a"))
	M.prism(n, 0.300, 0.140, 0.005, Vector3(-0.060, -0.160, 0.028), Color("6f8a5a"), 0.0, {"outline": 0.02})
	M.prism(n, 0.200, 0.100, 0.005, Vector3(0.115, -0.160, 0.028), Color("54704a"), 0.0, {"outline": 0.02})
	_cyr(n, 0.036, 0.036, 0.004, Vector3(0.140, 0.095, 0.028), M.C_FLOWER_YELLOW, Vector3(PI * 0.5, 0, 0))

# ============================================================
# 窗帘（wall，0.70 × 0.08 × 1.35；由原点向下悬挂；墙面支座盒给 z 0..0.08 极值）
# ============================================================
static func _build_curtain(n: Node3D, opts: Dictionary) -> void:
	var base: Vector3 = DIMS["curtain"]
	var w := base.x
	var d := base.y
	var c := _col(opts, "color", Color("c9a78e"))
	var rod_c := _col(opts, "cushion", M.C_WOOD_DARK)
	# 墙面支座（z 0..0.08 深度极值）
	for sx in [-1.0, 1.0]:
		_bx(n, Vector3(0.030, 0.050, d), Vector3(float(sx) * 0.290, 0, d * 0.5), rod_c)
	# 窗帘杆（沿 X，长 0.58）+ 两端球（x 极限 ±0.35）
	_cyr(n, 0.014, 0.014, 0.58, Vector3(0, 0.015, 0.05), rod_c, Vector3(0, 0, PI * 0.5))
	_sp(n, 0.025, Vector3(-0.325, 0.015, 0.05), C_BRASS)
	_sp(n, 0.025, Vector3(0.325, 0.015, 0.05), C_BRASS)
	# 帘布主体（顶 0.0，底 -1.31 → AABB 跨度 = 0.04 - (-1.31) = 1.35）
	_bx(n, Vector3(0.56, 1.31, 0.028), Vector3(0, -0.655, 0.05), c)
	# 4 道竖向褶皱（前凸）
	for i in range(4):
		_bx(n, Vector3(0.050, 1.31, 0.035), Vector3(-0.21 + float(i) * 0.14, -0.655, 0.052), c.darkened(0.07))
	# 顶部环扣（5 个，绕杆）
	for i in range(5):
		_cyr(n, 0.018, 0.018, 0.014, Vector3(-0.24 + float(i) * 0.12, 0.005, 0.05), C_BRASS, Vector3(0, 0, PI * 0.5))
	# 束带 + 结（z ≤ 0.079 < 0.08）
	_bx(n, Vector3(0.60, 0.040, 0.030), Vector3(0, -0.95, 0.05), Color("b08a5a"))
	_sp(n, 0.017, Vector3(0.10, -0.95, 0.062), Color("b08a5a"))

# ============================================================
# 柴火篮（floor，0.52 × 0.38 × 0.44；上沿顶 0.44）
# ============================================================
static func _build_firewood_basket(n: Node3D, opts: Dictionary) -> void:
	var base: Vector3 = DIMS["firewood_basket"]
	var w := base.x
	var d := base.y
	var h := base.z
	var c := _col(opts, "color", C_WICKER)
	var dark := c.darkened(0.18)
	var bark := _col(opts, "cushion", Color("6b4f3a"))
	# 篮底 + 四壁（宽/深极值）
	_bx(n, Vector3(w - 0.02, 0.020, d - 0.02), Vector3(0, 0.010, 0), dark)
	_bx(n, Vector3(w, 0.320, 0.030), Vector3(0, 0.180, -(d * 0.5 - 0.015)), c)
	_bx(n, Vector3(w, 0.320, 0.030), Vector3(0, 0.180, d * 0.5 - 0.015), c)
	_bx(n, Vector3(0.030, 0.320, d - 0.06), Vector3(-(w * 0.5 - 0.015), 0.180, 0), c)
	_bx(n, Vector3(0.030, 0.320, d - 0.06), Vector3(w * 0.5 - 0.015, 0.180, 0), c)
	# 上沿（顶 0.44，宽/深极值）
	_bx(n, Vector3(w, 0.060, d), Vector3(0, h - 0.030, 0), dark)
	# 横向编织条（比壁面略大，形成绑条观感；不超占地）
	for i in range(4):
		_bx(n, Vector3(w - 0.006, 0.016, d - 0.006), Vector3(0, 0.060 + float(i) * 0.070, 0), c.lightened(0.05))
	# 柴火（横放沿 X，端面年轮）+ 斜插引火柴
	var logs := [
		Vector3(0.0, 0.100, -0.070), Vector3(0.0, 0.100, 0.070),
		Vector3(0.0, 0.180, -0.040), Vector3(0.0, 0.180, 0.060),
	]
	for lp in logs:
		_cyr(n, 0.036, 0.038, 0.46, lp, bark, Vector3(0, 0, PI * 0.5))
		_cyr(n, 0.030, 0.030, 0.010, Vector3(-0.232, lp.y, lp.z), Color("b08a5a"), Vector3(0, 0, PI * 0.5))
		_cyr(n, 0.030, 0.030, 0.010, Vector3(0.232, lp.y, lp.z), Color("b08a5a"), Vector3(0, 0, PI * 0.5))
	_bxr(n, Vector3(0.026, 0.20, 0.026), Vector3(-0.090, 0.300, 0.0), bark.lightened(0.10), Vector3(0.28, 0.15, 0.22))
	_bxr(n, Vector3(0.024, 0.18, 0.024), Vector3(0.060, 0.300, -0.020), bark, Vector3(-0.18, -0.25, -0.12))

# ============================================================
# 盆栽（floor，0.42 × 0.42 × 0.70；盆沿 r≈0.155，叶展约 0.40，叶顶约 0.70）
# ============================================================
static func _build_plant_pot(n: Node3D, opts: Dictionary) -> void:
	var base: Vector3 = DIMS["plant_pot"]
	var h := base.z
	var pot_c := _col(opts, "color", M.C_TERRACOTTA)
	var leaf_a := _col(opts, "cushion", M.C_LEAF_A)
	var leaf_b := leaf_a.lightened(0.10)
	var leaf_c := leaf_a.darkened(0.12)
	# 花盆 + 盆沿 + 土（0..0.31）
	_cy(n, 0.145, 0.105, 0.240, Vector3(0, 0.120, 0), pot_c)
	_cy(n, 0.155, 0.150, 0.050, Vector3(0, 0.265, 0), pot_c.darkened(0.10))
	_cy(n, 0.140, 0.140, 0.020, Vector3(0, 0.300, 0), M.C_SOIL)
	# 3 根茎（斜向上）
	var stems := [Vector3(-0.040, 0.42, 0.020), Vector3(0.050, 0.45, -0.030), Vector3(0.0, 0.480, 0.050)]
	for sp in stems:
		_bxr(n, Vector3(0.018, 0.240, 0.018), sp, M.C_LEAF_C, Vector3(0.20, 0.0, 0.15))
	# 7 片椭球叶：绕中心放射、略微下垂（中心 rr=0.105 → 叶展约 0.40–0.43）
	var lcols := [leaf_a, leaf_b, leaf_c]
	for i in range(7):
		var ang := float(i) * TAU / 7.0 + 0.35
		var rr := 0.105
		var ly := 0.490 + 0.045 * float(i % 3)
		var leaf_pos := Vector3(sin(ang) * rr, ly, cos(ang) * rr)
		var leaf := _sp(n, 0.078, leaf_pos, lcols[i % 3], Vector3(1.40, 0.22, 0.55))
		leaf.rotation = Vector3(0.0, ang - PI * 0.5, -0.42)
	# 顶部新叶两片（更竖直，叶顶 ≈ 0.70）
	for i in range(2):
		var ang2 := 0.9 + float(i) * 2.4
		var leaf2 := _sp(n, 0.065, Vector3(sin(ang2) * 0.05, 0.672 + float(i) * 0.012, cos(ang2) * 0.05), leaf_b, Vector3(1.20, 0.24, 0.50))
		leaf2.rotation = Vector3(0.0, ang2 - PI * 0.5, -0.12)
