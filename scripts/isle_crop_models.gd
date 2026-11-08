class_name IsleCropModels
extends RefCounted
## P3 作物模型层：五种作物 × 三阶段 = 15 个程序化低多边形网格。
##
## 职责边界（P3 契约）：
##   * 本模块只做「作物 id + 视觉阶段 id -> ArrayMesh」的纯几何构建与共享缓存；
##   * 不持有农田状态、不读系统时间、不调用 IsleFarm.advance_to、不增删库存；
##   * 正式农田由 IsleFarmView 读取 IsleFarm 的权威状态后调用 mesh_for() 取网格；
##   * 同 (作物, 阶段) 的网格只构建一次并共享，材质全局共享；
##   * 每株植物 = 1 个 MeshInstance3D + 1 个顶点色 ArrayMesh，不产生每片叶子独立节点。
##
## 坐标约定：模型原点 = 苗床土面中心，+Y 向上，单位米。
## 单株活动范围收在 1x1 米苗床内（西瓜横向铺展半径 <= 0.42 m）。

const CROPS := preload("res://scripts/isle_crops.gd")
const M := preload("res://scripts/isle_math.gd")

const STAGE_IDS := ["seedling", "growing", "mature"]

# ---------------- 共享配色 ----------------
# 统一绘本色系：中低饱和 + 明确明暗层次；各作物靠轮廓/体量/果实形态区分。
const C_STEM := Color("6f8f45")
const C_STEM_DARK := Color("53703a")

# 小麦：细长禾本科 + 金黄麦穗
const C_WHEAT_STEM := Color("8ba75a")
const C_WHEAT_LEAF := Color("9cbb63")
const C_WHEAT_LEAF_DEEP := Color("7a9a4a")
const C_WHEAT_SPIKE := Color("dcb75f")
const C_WHEAT_SPIKE_DEEP := Color("c08f3a")
const C_WHEAT_AWN := Color("ecd9a2")

# 玉米：高直中心茎 + 宽剑叶 + 金黄玉米棒
const C_CORN_STEM := Color("6d9144")
const C_CORN_LEAF := Color("7ba64b")
const C_CORN_LEAF_DEEP := Color("5b8239")
const C_CORN_HUSK := Color("90b45c")
const C_CORN_HUSK_DEEP := Color("6d9445")
const C_CORN_COB := Color("e9c757")
const C_CORN_KERNEL := Color("d0a43c")
const C_CORN_EAR_GREEN := Color("a9c96e")
const C_CORN_SILK := Color("b98d55")
const C_CORN_TASSEL := Color("cbb679")

# 西瓜：低矮藤蔓 + 宽叶 + 条纹圆果
const C_MELON_VINE := Color("58803c")
const C_MELON_LEAF := Color("62914a")
const C_MELON_LEAF_DEEP := Color("47702f")
const C_MELON_RIND_DARK := Color("34693b")
const C_MELON_RIND_LIGHT := Color("89bd5f")
const C_MELON_YOUNG := Color("a6ca78")

# 番茄：分枝灌木 + 复叶 + 红果
const C_TOMATO_STEM := Color("60873f")
const C_TOMATO_LEAF := Color("6d9a4b")
const C_TOMATO_LEAF_DEEP := Color("4e7534")
const C_TOMATO_FRUIT := Color("cf432c")
const C_TOMATO_FRUIT_LIGHT := Color("e8725a")
const C_TOMATO_UNRIPE := Color("8fbb5f")
const C_TOMATO_FLOWER := Color("f2d95c")
const C_TOMATO_CALYX := Color("4f7a38")

# 羽衣甘蓝：蓝绿宽叶莲座
const C_KALE_OUTER := Color("1b3a26")
const C_KALE_MID := Color("27543a")
const C_KALE_INNER := Color("3a7a4e")
const C_KALE_STEM := Color("35563a")
const C_KALE_PALE := Color("8cc47f")

static var _mesh_cache: Dictionary = {}
static var _material: ShaderMaterial = null
static var _geom_cache: Dictionary = {}

# ============================================================ 公开 API ====
## 五种作物的稳定 id（顺序即展示顺序）。
static func crop_ids() -> Array:
	return CROPS.CROP_IDS.duplicate()


## 该 (作物, 阶段) 是否有正式模型（不做通用占位）。
static func has_model(crop_id: String, stage_id: String) -> bool:
	return CROPS.CROP_IDS.has(crop_id) and STAGE_IDS.has(stage_id)


## 全部 15 个模型状态的清单，供探针/展示遍历。
static func all_models() -> Array:
	var out: Array = []
	for crop_id in CROPS.CROP_IDS:
		for stage_id in STAGE_IDS:
			out.append({"crop_id": String(crop_id), "stage_id": String(stage_id)})
	return out


## 共享材质：顶点色 + 3 段卡通明暗 + 轻轮廓。全场景只有这一份。
static func material() -> ShaderMaterial:
	if _material == null:
		_material = M.toon_material(Color.WHITE, {
			"vertex_color": true,
			"bands": 3.0,
			"soft": 0.45,
			"rim": 0.06,
			"outline": 0.0,
		})
	return _material


## 取共享网格（首次构建后缓存；绝不在每帧重建）。
static func mesh_for(crop_id: String, stage_id: String) -> ArrayMesh:
	var key: String = crop_id + "|" + stage_id
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var mesh := _build(crop_id, stage_id)
	_mesh_cache[key] = mesh
	return mesh


## 构建一株植物的显示节点（根节点位置由调用方决定，网格原点即土面中心）。
static func make_instance(crop_id: String, stage_id: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "CropModel"
	mi.mesh = mesh_for(crop_id, stage_id)
	mi.material_override = material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("crop_id", crop_id)
	mi.set_meta("stage_id", stage_id)
	return mi


## 模型包围盒（探针用它检查根基准、离地高度与越界）。
static func bounds_of(crop_id: String, stage_id: String) -> AABB:
	var key: String = crop_id + "|" + stage_id
	if _geom_cache.has(key):
		return _geom_cache[key]["aabb"]
	_cache_geometry(crop_id, stage_id)
	if _geom_cache.has(key):
		return _geom_cache[key]["aabb"]
	return AABB()


## 三角面数（探针用它排除「空模型/占位球」）。
static func triangle_count(crop_id: String, stage_id: String) -> int:
	var key: String = crop_id + "|" + stage_id
	if not _geom_cache.has(key):
		_cache_geometry(crop_id, stage_id)
	if _geom_cache.has(key):
		return int(_geom_cache[key]["tris"])
	return 0


static func _cache_geometry(crop_id: String, stage_id: String) -> void:
	var mesh := mesh_for(crop_id, stage_id)
	if mesh == null or mesh.get_surface_count() <= 0:
		_geom_cache[crop_id + "|" + stage_id] = {"aabb": AABB(), "tris": 0}
		return
	var arr: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	_geom_cache[crop_id + "|" + stage_id] = {
		"aabb": mesh.get_aabb(),
		"tris": int(verts.size() / 3),
	}


## 权威阶段 -> 实际展示阶段。
## 唯一规则：采收后的再生长周期里植株仍然存在，不能缩回幼苗；只有真正成熟
## （IsleFarm.is_mature，即权威的 next_ready_at 到达）才切成熟外观。
## 这里只做只读映射，不重写任何成熟时间算法。
static func display_stage(stage_id: String, regrow_cycle: bool) -> String:
	if not STAGE_IDS.has(stage_id):
		return ""
	if not regrow_cycle:
		return stage_id
	return "mature" if stage_id == "mature" else "growing"


# ============================================================ 构建分派 ====
static func _build(crop_id: String, stage_id: String) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	match crop_id:
		"wheat":
			_wheat(st, stage_id)
		"corn":
			_corn(st, stage_id)
		"watermelon":
			_watermelon(st, stage_id)
		"tomato":
			_tomato(st, stage_id)
		"kale":
			_kale(st, stage_id)
		_:
			push_warning("IsleCropModels: 未知作物 id: " + crop_id)
	var mesh := st.commit()
	if mesh == null:
		mesh = ArrayMesh.new()
	return mesh


# ============================================================ 基础图元 ====
## 写入一个前向面三角形。a/b/c 按任意环绕给出，out_n 指定外法线方向，
## 函数内部按 Godot 4 的「顺时针 = 前向面」规则把写入顺序修正为 a, c, b。
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ca: Color, cb: Color, cc: Color, out_n: Vector3) -> void:
	var n: Vector3 = (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	if n.dot(out_n) < 0.0:
		var pb: Vector3 = b
		b = c
		c = pb
		var pc: Color = cb
		cb = cc
		cc = pc
		n = -n
	n = n.normalized()
	st.set_color(ca)
	st.set_normal(n)
	st.add_vertex(a)
	st.set_color(cc)
	st.set_normal(n)
	st.add_vertex(c)
	st.set_color(cb)
	st.set_normal(n)
	st.add_vertex(b)


## 四边形 a->b->c->d（闭环顺序），拆成两个前向三角形。
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ca: Color, cb: Color, cc: Color, cd: Color, out_n: Vector3) -> void:
	_tri(st, a, b, c, ca, cb, cc, out_n)
	_tri(st, a, c, d, ca, cc, cd, out_n)


## 叶片：沿 dir 生长，side 给叶面横向；正反两面都写（双面可读）。
## 叶面中线隆起 cup*width，形成有体积的「折叶」：低多边形下靠这条中脊的明暗
## 就能读出叶片体积，避免整株看起来像几片平放的纸。
## shape_exp 越小叶身越宽（羽衣甘蓝的宽倒卵叶）；droop 让叶梢下垂；
## round_base 给圆钝叶基；wave>0 时叶缘做正弦起伏（波状/缺刻感）。
static func _leaf_along(st: SurfaceTool, base: Vector3, dir: Vector3, side_in: Vector3,
		length: float, width: float, droop: float,
		c_base: Color, c_tip: Color, segs: int = 3,
		round_base: bool = false, wave: float = 0.0,
		cup: float = 0.30, shape_exp: float = 0.60) -> void:
	if length <= 0.0 or width <= 0.0:
		return
	var axis: Vector3 = dir.normalized()
	var side: Vector3 = side_in.normalized()
	if side.length_squared() < 1e-6:
		side = Vector3.RIGHT
	var nf: Vector3 = side.cross(axis)
	if nf.length_squared() < 1e-8:
		nf = Vector3.UP
	nf = nf.normalized()
	segs = maxi(1, segs)
	var pts: Array[Vector3] = []
	var lats: Array[Vector3] = []
	var mids: Array[Vector3] = []
	var cols: Array[Color] = []
	for i in range(segs + 1):
		var t: float = float(i) / float(segs)
		var p: Vector3 = base + axis * (length * t) + Vector3(0.0, -droop * length * t * t, 0.0)
		var w: float = 0.0
		if round_base:
			w = width * (0.62 + 0.38 * sin(PI * t))
		else:
			w = width * pow(sin(PI * clampf(t, 0.015, 0.995)), shape_exp)
		if wave > 0.0:
			w = maxf(0.0, w + wave * width * sin(TAU * 1.7 * t))
		pts.append(p)
		lats.append(side * w)
		mids.append(p + nf * (cup * w))
		cols.append(c_base.lerp(c_tip, t))
	var n_l: Vector3 = (nf - side * 0.45).normalized()
	var n_r: Vector3 = (nf + side * 0.45).normalized()
	for i in range(segs):
		var l0: Vector3 = pts[i] - lats[i]
		var m0: Vector3 = mids[i]
		var r0: Vector3 = pts[i] + lats[i]
		var l1: Vector3 = pts[i + 1] - lats[i + 1]
		var m1: Vector3 = mids[i + 1]
		var r1: Vector3 = pts[i + 1] + lats[i + 1]
		var c0: Color = cols[i]
		var c1: Color = cols[i + 1]
		# 正面：中脊略亮、叶缘略深；背面整体压暗（叶背/重叠的层次感）
		_quad(st, l0, m0, m1, l1, c0.darkened(0.07), c0.lightened(0.06), c1.lightened(0.06), c1.darkened(0.07), n_l)
		_quad(st, m0, r0, r1, m1, c0.lightened(0.06), c0.darkened(0.07), c1.darkened(0.07), c1.lightened(0.06), n_r)
		_quad(st, l1, m1, m0, l0, c1.darkened(0.12), c1, c0, c0.darkened(0.12), -n_l)
		_quad(st, m1, r1, r0, m0, c1, c1.darkened(0.12), c0.darkened(0.12), c0, -n_r)


## 叶片（极坐标包装）：yaw 水平朝向，pitch 初始上扬角。
static func _leaf(st: SurfaceTool, base: Vector3, yaw: float, pitch: float,
		length: float, width: float, droop: float,
		c_base: Color, c_tip: Color, segs: int = 3,
		round_base: bool = false, wave: float = 0.0,
		cup: float = 0.30, shape_exp: float = 0.60) -> void:
	var ca: float = cos(pitch)
	var dir := Vector3(cos(yaw) * ca, sin(pitch), sin(yaw) * ca)
	var side := Vector3(-sin(yaw), 0.0, cos(yaw))
	_leaf_along(st, base, dir, side, length, width, droop, c_base, c_tip, segs, round_base, wave, cup, shape_exp)


## 管状（茎/藤/叶轴/穗轴）：沿折线 pts 生成 sides 边棱柱，半径按 radii 渐变。
static func _tube(st: SurfaceTool, pts: Array, radii: Array, sides: int,
		c0: Color, c1: Color, cap: bool = false) -> void:
	var n: int = pts.size()
	if n < 2:
		return
	sides = maxi(3, sides)
	var dirs: Array[Vector3] = []
	for i in range(n):
		var pv: Vector3 = pts[maxi(0, i - 1)]
		var nv: Vector3 = pts[mini(n - 1, i + 1)]
		var d: Vector3 = nv - pv
		dirs.append(d.normalized() if d.length_squared() > 1e-10 else Vector3.UP)
	var rings: Array = []
	for i in range(n):
		var d: Vector3 = dirs[i]
		var ref: Vector3 = Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT
		var u: Vector3 = ref.cross(d).normalized()
		var v: Vector3 = d.cross(u).normalized()
		var ring: Array[Vector3] = []
		for s in range(sides):
			var ang: float = TAU * float(s) / float(sides)
			ring.append(pts[i] + (u * cos(ang) + v * sin(ang)) * float(radii[i]))
		rings.append(ring)
	var span: float = float(maxi(1, n - 1))
	for i in range(n - 1):
		var t0: float = float(i) / span
		var t1: float = float(i + 1) / span
		var c_a: Color = c0.lerp(c1, t0)
		var c_b: Color = c0.lerp(c1, t1)
		var midp: Vector3 = pts[i].lerp(pts[i + 1], 0.5)
		var d2: Vector3 = (dirs[i] + dirs[i + 1])
		if d2.length_squared() < 1e-10:
			d2 = dirs[i]
		d2 = d2.normalized()
		for s in range(sides):
			var s2: int = (s + 1) % sides
			var p0: Vector3 = rings[i][s]
			var p1: Vector3 = rings[i][s2]
			var p2: Vector3 = rings[i + 1][s2]
			var p3: Vector3 = rings[i + 1][s]
			var out_n: Vector3 = ((p0 + p1 + p2 + p3) * 0.25) - midp
			if out_n.length_squared() < 1e-12:
				out_n = d2
			_quad(st, p0, p1, p2, p3, c_a, c_a, c_b, c_b, out_n)
	if cap:
		var tp: Vector3 = pts[n - 1] + dirs[n - 1] * (float(radii[n - 1]) * 0.8)
		for s in range(sides):
			var s2: int = (s + 1) % sides
			_tri(st, rings[n - 1][s], rings[n - 1][s2], tp, c1, c1, c1, dirs[n - 1])


## 低模椭球。axis 为极轴方向（西瓜条纹沿极轴经线走）。mode:
##   0 = 沿极轴上下渐变（番茄/麦粒），1 = 纵向条纹（西瓜），2 = 棋盘格（玉米粒）。
static func _ball(st: SurfaceTool, center: Vector3, axis: Vector3, r_axis: float, r_side: float,
		sectors: int, rings: int, col_a: Color, col_b: Color, mode: int = 0) -> void:
	sectors = maxi(4, sectors)
	rings = maxi(2, rings)
	var d: Vector3 = axis.normalized() if axis.length_squared() > 1e-9 else Vector3.UP
	var ref: Vector3 = Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT
	var u: Vector3 = ref.cross(d).normalized()
	var v: Vector3 = d.cross(u).normalized()
	var grid: Array = []
	for r in range(rings + 1):
		var theta: float = PI * float(r) / float(rings)
		var row: Array[Vector3] = []
		for s in range(sectors):
			var phi: float = TAU * float(s) / float(sectors)
			row.append(center + d * (r_axis * cos(theta)) + (u * cos(phi) + v * sin(phi)) * (r_side * sin(theta)))
		grid.append(row)
	for r in range(rings):
		var t0: float = float(r) / float(rings)
		var t1: float = float(r + 1) / float(rings)
		for s in range(sectors):
			var s2: int = (s + 1) % sectors
			var a: Vector3 = grid[r][s]
			var b: Vector3 = grid[r][s2]
			var c: Vector3 = grid[r + 1][s2]
			var e: Vector3 = grid[r + 1][s]
			var out_n: Vector3 = ((a + b + c + e) * 0.25) - center
			if out_n.length_squared() < 1e-12:
				out_n = d
			var ca: Color = col_a
			var cb: Color = col_b
			if mode == 0:
				ca = col_a.lerp(col_b, t0)
				cb = col_a.lerp(col_b, t1)
			elif mode == 1:
				ca = col_a if s % 2 == 0 else col_b
				cb = ca
			else:
				ca = col_a if (s + r) % 2 == 0 else col_b
				cb = ca
			_quad(st, a, b, c, e, ca, ca, cb, cb, out_n)


# ============================================================ 小麦 ========
static func _wheat(st: SurfaceTool, stage_id: String) -> void:
	if stage_id == "seedling":
		# 幼苗：几根细小直立的鲜绿叶芽，从苗床中央附近长出。
		for k in range(7):
			var a: float = TAU * float(k) / 7.0 + 0.35
			_leaf(st, Vector3(cos(a) * 0.016, 0.0, sin(a) * 0.016), a,
					1.30 + 0.06 * float(k % 2), 0.155 + 0.020 * float(k % 3),
					0.020, 0.013, C_WHEAT_LEAF_DEEP, C_WHEAT_LEAF, 3, false, 0.0, 0.34, 0.75)
		return
	# 生长中/成熟：同一丛麦秆骨架（生长中不缩水，成熟只增加金黄麦穗）。
	var mature: bool = stage_id == "mature"
	var h: float = 0.62
	var n_tiller: int = 6
	for k in range(n_tiller):
		var yaw: float = TAU * float(k) / float(n_tiller) + 0.25
		var lean: float = 0.085 + 0.030 * float(k % 3)
		var root := Vector3(cos(yaw) * 0.024, 0.0, sin(yaw) * 0.024)
		var mid := Vector3(cos(yaw) * lean * 0.40, h * 0.46, sin(yaw) * lean * 0.40)
		var top := Vector3(cos(yaw) * lean, h * (0.84 + 0.05 * float(k % 2)), sin(yaw) * lean)
		_tube(st, [root, mid, top], [0.012, 0.009, 0.006], 4, C_WHEAT_STEM, C_WHEAT_STEM, false)
		# 两片狭长麦叶向外舒展（叶面用中脊折起，横向也能看出叶片）
		for m in range(2):
			var bp: Vector3 = mid.lerp(top, 0.42 + 0.30 * float(m))
			_leaf(st, bp, yaw + (0.95 if m == 0 else -0.95), (0.62 if m == 0 else 0.40),
					h * (0.58 - 0.08 * float(m)), 0.023, h * 0.20,
					C_WHEAT_LEAF_DEEP, C_WHEAT_LEAF, 3, false, 0.0, 0.30, 0.55)
		# 只有较高的 4 根麦秆抽穗：数量不多但穗部够醒目，也把面数预算留给轮廓。
		if mature and k < 4:
			_wheat_spike(st, top, (top - mid).normalized(), 0.180 + 0.014 * float(k % 2), yaw)


## 麦穗：麦秆顶端分节、两列错落麦粒 + 几根芒。金黄麦穗与绿色麦秆形成清楚对比。
static func _wheat_spike(st: SurfaceTool, base: Vector3, dir: Vector3, length: float, yaw: float) -> void:
	var up: Vector3 = dir.normalized()
	var side := Vector3(-sin(yaw), 0.0, cos(yaw))
	var across: Vector3 = side.cross(up).normalized()
	_tube(st, [base, base + up * (length * 0.45), base + up * length],
			[0.009, 0.011, 0.004], 4, C_WHEAT_SPIKE_DEEP, C_WHEAT_SPIKE, false)
	# 5 节、每节左右两粒错开排列：低面数下靠「分节 + 错落」读出麦穗形态。
	for k in range(5):
		var t: float = 0.12 + 0.80 * float(k) / 4.0
		var row: float = 0.008 * float(k % 2)
		for sgn in [-1.0, 1.0]:
			var c: Vector3 = base + up * (length * t) + side * (0.022 * float(sgn)) + across * row
			_ball(st, c, up, 0.034, 0.020, 4, 2, C_WHEAT_SPIKE, C_WHEAT_SPIKE_DEEP, 0)
	for k in range(3):
		var awn_yaw: float = yaw + (float(k) - 1.0) * 0.45
		_leaf(st, base + up * (length * 0.88), awn_yaw, 0.95,
				0.130, 0.009, 0.034, C_WHEAT_AWN, C_WHEAT_AWN, 2, false, 0.0, 0.15, 0.80)


# ============================================================ 玉米 ========
static func _corn(st: SurfaceTool, stage_id: String) -> void:
	if stage_id == "seedling":
		# 幼苗：少量宽而尖的嫩叶向上两侧展开（与小麦细叶形成对比）。
		for k in range(4):
			var a: float = TAU * float(k) / 4.0 + 0.6
			_leaf(st, Vector3(cos(a) * 0.014, 0.0, sin(a) * 0.014), a,
					1.05 + 0.12 * float(k % 2), 0.240 + 0.020 * float(k % 2),
					0.078, 0.070, C_CORN_LEAF_DEEP, C_CORN_LEAF, 3, false, 0.0, 0.55, 0.55)
		return
	var mature: bool = stage_id == "mature"
	var stem_h: float = 1.02
	# 中心茎秆（生长中与成熟同高，成熟只换果穗，不整株缩放）。
	_tube(st, [Vector3(0, 0, 0), Vector3(0.004, stem_h * 0.34, 0.0),
		Vector3(0.0, stem_h * 0.68, 0.0), Vector3(-0.004, stem_h, 0.0)],
		[0.040, 0.032, 0.024, 0.014], 5, C_CORN_STEM, C_CORN_STEM, false)
	# 宽大的剑形叶片：交替方向、先上扬后下垂，形成高直轮廓
	for k in range(7):
		var t: float = 0.12 + 0.105 * float(k)
		var yaw: float = 1.02 * float(k) + 0.3
		_leaf(st, Vector3(0.0, stem_h * t, 0.0), yaw, 0.98 - 0.06 * float(k),
				0.50 - 0.03 * float(k % 3), 0.082, 0.42,
				C_CORN_LEAF_DEEP, C_CORN_LEAF, 4, false, 0.0, 0.45, 0.50)
	_corn_tassel(st, Vector3(-0.004, stem_h, 0.0), 0.185 if mature else 0.145, mature)
	if mature:
		# 成熟：两枚清楚可辨的金黄玉米棒，斜挂在茎上，苞叶只包住下半段。
		var dir_a := Vector3(0.86, 0.22, 0.46).normalized()
		_corn_ear(st, Vector3(0.020, stem_h * 0.52, 0.010), dir_a, 0.235, 0.052,
				C_CORN_COB, C_CORN_KERNEL, C_CORN_HUSK, C_CORN_HUSK_DEEP, 0.30, true)
		var dir_b := Vector3(-0.58, 0.18, -0.80).normalized()
		_corn_ear(st, Vector3(-0.012, stem_h * 0.68, -0.008), dir_b, 0.190, 0.045,
				C_CORN_COB, C_CORN_KERNEL, C_CORN_HUSK, C_CORN_HUSK_DEEP, 0.28, true)
	else:
		# 生长中：一枚尚未成熟的绿色玉米棒，苞叶基本包住，无金黄色。
		var dir_c := Vector3(0.90, 0.34, 0.28).normalized()
		_corn_ear(st, Vector3(0.020, stem_h * 0.52, 0.010), dir_c, 0.155, 0.038,
				C_CORN_EAR_GREEN, C_CORN_HUSK, C_CORN_HUSK, C_CORN_HUSK_DEEP, 0.06, false)


## 玉米雄穗（顶部小分叉穗）：成熟时偏暖色，形态更清楚。
static func _corn_tassel(st: SurfaceTool, base: Vector3, height: float, mature: bool) -> void:
	var col: Color = C_CORN_TASSEL if mature else C_CORN_HUSK
	var top: Vector3 = base + Vector3(0.0, height, 0.0)
	_tube(st, [base, base + Vector3(0.0, height * 0.55, 0.0), top],
			[0.010, 0.007, 0.004], 4, C_CORN_STEM, col, false)
	for k in range(6):
		var a: float = TAU * float(k) / 6.0 + 0.4
		var d := Vector3(cos(a) * 0.62, 1.0, sin(a) * 0.62).normalized()
		_leaf_along(st, base + Vector3(0.0, height * 0.40, 0.0), d,
				Vector3(cos(a + PI * 0.5), 0.0, sin(a + PI * 0.5)),
				height * 0.92, 0.019, 0.012, col, col.lightened(0.15), 2, false, 0.0, 0.20, 0.80)


## 玉米棒：棋盘格籽粒的椭球 + 包住下半段的苞叶 + 顶端短玉米须。
## open_level 越大苞叶越外翻（成熟时苞叶被撑开，露出金黄籽粒）。
static func _corn_ear(st: SurfaceTool, base: Vector3, dir: Vector3, length: float, radius: float,
		cob_a: Color, cob_b: Color, husk_a: Color, husk_b: Color,
		open_level: float, silk: bool) -> void:
	var up: Vector3 = dir.normalized()
	var ref: Vector3 = Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT
	var u: Vector3 = ref.cross(up).normalized()
	var v: Vector3 = up.cross(u).normalized()
	_ball(st, base + up * (length * 0.5), up, length * 0.5, radius, 8, 4, cob_a, cob_b, 2)
	# 苞叶：从棒基部斜向外包，长度只到棒身 60%，让顶端金黄籽粒露出
	for k in range(5):
		var ang: float = TAU * float(k) / 5.0 + 0.4
		var radial: Vector3 = u * cos(ang) + v * sin(ang)
		var hdir: Vector3 = (up * 1.0 + radial * (0.55 + open_level)).normalized()
		var hside: Vector3 = radial.cross(hdir).normalized()
		_leaf_along(st, base - up * (length * 0.10) + radial * (radius * 0.35), hdir, hside,
				length * 0.62, radius * 2.1, length * 0.10,
				husk_a, husk_b, 3, false, 0.06, 0.55, 0.35)
	if silk:
		for k in range(3):
			var ang2: float = TAU * float(k) / 3.0 + 0.6
			var radial2: Vector3 = u * cos(ang2) + v * sin(ang2)
			var tip: Vector3 = base + up * length
			_tube(st, [tip, tip + (up * 0.75 + radial2 * 0.25).normalized() * 0.024,
				tip + (up * 0.35 + radial2 * 0.85).normalized() * 0.042],
				[0.004, 0.003, 0.002], 3, C_CORN_SILK, C_CORN_SILK, false)


# ============================================================ 西瓜 ========
static func _watermelon(st: SurfaceTool, stage_id: String) -> void:
	if stage_id == "seedling":
		# 幼苗：贴地小苗，宽子叶 + 一片初生叶。
		for k in range(2):
			var a: float = 0.4 + PI * float(k)
			_leaf(st, Vector3(cos(a) * 0.020, 0.0, sin(a) * 0.020), a, 0.62,
					0.105, 0.085, 0.010, C_MELON_LEAF_DEEP, C_MELON_LEAF, 3, true, 0.0, 0.50, 0.45)
		_leaf(st, Vector3(0.0, 0.012, 0.0), 1.35, 1.15, 0.075, 0.055, 0.008,
				C_MELON_LEAF_DEEP, C_MELON_LEAF, 3, true, 0.0, 0.50, 0.50)
		return
	var mature: bool = stage_id == "mature"
	var spread: float = 0.40 if mature else 0.34
	# 四条藤蔓沿地面向外铺开（低矮贴地，不是竖直灌木）
	for k in range(4):
		var yaw: float = TAU * float(k) / 4.0 + 0.45
		var start := Vector3(cos(yaw) * 0.030, 0.016, sin(yaw) * 0.030)
		var midp := Vector3(cos(yaw) * spread * 0.55, 0.034, sin(yaw) * spread * 0.55)
		var end := Vector3(cos(yaw) * spread, 0.030, sin(yaw) * spread)
		_tube(st, [start, midp, end], [0.015, 0.012, 0.008], 4,
				C_MELON_VINE, C_MELON_VINE, false)
		# 宽大的西瓜叶：叶片有浅裂起伏，几乎平铺但叶面折起可见体积
		for m in range(3):
			var t: float = 0.30 + 0.28 * float(m)
			var bp := Vector3(cos(yaw) * spread * t, 0.032, sin(yaw) * spread * t)
			_leaf(st, bp, yaw + (0.95 if m % 2 == 0 else -0.95), 0.46 + 0.18 * float(m % 2),
					0.155, 0.125, 0.030, C_MELON_LEAF_DEEP, C_MELON_LEAF, 3, true, 0.10, 0.50, 0.45)
		# 卷须
		var curl := end + Vector3(cos(yaw + 1.2) * 0.030, 0.030, sin(yaw + 1.2) * 0.030)
		_tube(st, [end, curl, curl + Vector3(0.0, 0.035, 0.0)],
				[0.006, 0.004, 0.003], 3, C_MELON_VINE, C_MELON_VINE, false)
	if mature:
		# 成熟：低矮藤蔓宽叶下清楚可见的条纹圆果（深浅相间色块）。
		# 瓜心高度 ≈ 0.96r：果底轻微压入土面，看起来是「搁在地上」，又不悬空/不沉底。
		_melon_fruit(st, Vector3(0.150, 0.150, 0.030), Vector3(0.94, -0.12, 0.32), 0.150,
				C_MELON_RIND_DARK, C_MELON_RIND_LIGHT, true)
		_melon_fruit(st, Vector3(-0.160, 0.108, -0.115), Vector3(0.25, -0.08, 0.96), 0.108,
				C_MELON_RIND_DARK, C_MELON_RIND_LIGHT, true)
	else:
		# 生长中：一枚未成熟小瓜（淡绿、条纹很浅），藤蔓结构清楚。
		_melon_fruit(st, Vector3(0.115, 0.062, 0.075), Vector3(0.7, -0.1, 0.5), 0.062,
				C_MELON_YOUNG, C_MELON_LEAF, false)
		_tomato_flower_at(st, Vector3(-0.02, 0.085, 0.13), C_MELON_YOUNG)


static func _melon_fruit(st: SurfaceTool, center: Vector3, axis: Vector3, r: float,
		col_a: Color, col_b: Color, striped: bool) -> void:
	_ball(st, center, axis, r * 1.10, r, 14, 7, col_a, col_b, 1 if striped else 0)
	# 瓜蒂
	var up: Vector3 = axis.normalized()
	_tube(st, [center + up * (r * 1.02), center + up * (r * 1.22)], [r * 0.15, r * 0.10], 3,
			C_MELON_VINE, C_MELON_VINE, false)


# ============================================================ 番茄 ========
static func _tomato(st: SurfaceTool, stage_id: String) -> void:
	if stage_id == "seedling":
		# 幼苗：小型绿株，枝叶少，植株中心与叶片轮廓明确。
		_tube(st, [Vector3(0, 0, 0), Vector3(0.008, 0.13, 0.0)], [0.014, 0.009], 4,
				C_TOMATO_STEM, C_TOMATO_STEM, false)
		for k in range(3):
			var a: float = TAU * float(k) / 3.0 + 0.3
			_tomato_compound_leaf(st, Vector3(0.008, 0.13, 0.0), a, 0.72, 0.085)
		return
	var mature: bool = stage_id == "mature"
	# 主茎（生长中与成熟同体量：成熟只换果实，不把株型缩放）。
	_tube(st, [Vector3(0, 0, 0), Vector3(0.012, 0.20, 0.0), Vector3(0.006, 0.34, 0.0),
		Vector3(0.0, 0.50, 0.0)], [0.022, 0.018, 0.014, 0.009], 5,
		C_TOMATO_STEM, C_TOMATO_STEM, false)
	var nodes := [0.16, 0.26, 0.36, 0.44]
	var tips: Array[Vector3] = []
	for k in range(4):
		var yaw: float = TAU * float(k) / 4.0 + 0.55
		var b := Vector3(0.006, float(nodes[k]), 0.0)
		var reach: float = 0.16 + 0.03 * float(k % 2)
		var midp: Vector3 = b + Vector3(cos(yaw) * reach * 0.55, 0.10, sin(yaw) * reach * 0.55)
		var end: Vector3 = b + Vector3(cos(yaw) * reach, 0.17, sin(yaw) * reach)
		_tube(st, [b, midp, end], [0.013, 0.010, 0.007], 4,
				C_TOMATO_STEM, C_TOMATO_STEM, false)
		tips.append(end)
		_tomato_compound_leaf(st, end, yaw, 0.52, 0.155)
		_tomato_compound_leaf(st, midp, yaw + 1.50, 0.80, 0.142)
		_tomato_compound_leaf(st, b, yaw - 1.20, 1.05, 0.115)
	if mature:
		# 成熟：醒目红色番茄果，成小串挂在分枝间，带绿色花萼。
		for k in range(3):
			var tip: Vector3 = tips[k]
			for m in range(2):
				var ang: float = float(k) * 2.1 + float(m) * 1.7
				var off := Vector3(cos(ang) * 0.045, -0.030 - 0.015 * float(m), sin(ang) * 0.045)
				var c: Vector3 = tip + off
				_tube(st, [tip, c], [0.004, 0.003], 3, C_TOMATO_STEM, C_TOMATO_STEM, false)
				_tomato_fruit(st, c, 0.050 if m == 0 else 0.042, true)
		_tomato_fruit(st, tips[3] + Vector3(0.010, -0.035, -0.010), 0.038, true)
	else:
		# 生长中：绿色未熟果 + 少量黄花。
		for k in range(3):
			var tip: Vector3 = tips[k]
			var c: Vector3 = tip + Vector3(cos(float(k) * 2.3) * 0.035, -0.030, sin(float(k) * 2.3) * 0.035)
			_tube(st, [tip, c], [0.004, 0.003], 3, C_TOMATO_STEM, C_TOMATO_STEM, false)
			_tomato_fruit(st, c, 0.038, false)
		_tomato_flower_at(st, tips[0] + Vector3(0.0, 0.035, 0.0), C_TOMATO_FLOWER)
		_tomato_flower_at(st, tips[1] + Vector3(0.0, 0.035, 0.0), C_TOMATO_FLOWER)


## 番茄复叶：一根叶轴 + 一片主叶 + 两片侧小叶，形成有分枝感的羽状轮廓。
static func _tomato_compound_leaf(st: SurfaceTool, base: Vector3, yaw: float, pitch: float,
		size: float) -> void:
	var ca: float = cos(pitch)
	var dir := Vector3(cos(yaw) * ca, sin(pitch), sin(yaw) * ca)
	var side := Vector3(-sin(yaw), 0.0, cos(yaw))
	var rachis_end: Vector3 = base + dir * (size * 0.55)
	_tube(st, [base, rachis_end], [0.005, 0.003], 3, C_TOMATO_STEM, C_TOMATO_LEAF_DEEP, false)
	_leaf_along(st, base, dir, side, size, size * 0.50, size * 0.18,
			C_TOMATO_LEAF_DEEP, C_TOMATO_LEAF, 2, false, 0.0, 0.34, 0.55)
	for m in [1.0, -1.0]:
		var yaw2: float = yaw + 0.90 * float(m)
		var dir2 := Vector3(cos(yaw2) * ca, sin(pitch) * 0.85, sin(yaw2) * ca)
		_leaf_along(st, base + dir * (size * 0.30), dir2, Vector3(-sin(yaw2), 0.0, cos(yaw2)),
				size * 0.66, size * 0.36, size * 0.14,
				C_TOMATO_LEAF_DEEP, C_TOMATO_LEAF, 2, false, 0.0, 0.34, 0.55)


## 番茄果实 + 绿色花萼。
static func _tomato_fruit(st: SurfaceTool, c: Vector3, r: float, ripe: bool) -> void:
	var col_a: Color = C_TOMATO_FRUIT if ripe else C_TOMATO_UNRIPE
	var col_b: Color = C_TOMATO_FRUIT_LIGHT if ripe else C_TOMATO_UNRIPE.lightened(0.18)
	_ball(st, c, Vector3.UP, r * 1.06, r, 8, 4, col_a, col_b, 0)
	for k in range(5):
		var ang: float = TAU * float(k) / 5.0
		var d := Vector3(cos(ang) * 0.92, 0.30, sin(ang) * 0.92).normalized()
		_leaf_along(st, c + Vector3(0.0, r * 0.86, 0.0), d,
				Vector3(-sin(ang), 0.0, cos(ang)), r * 0.60, r * 0.32, 0.0,
				C_TOMATO_CALYX, C_TOMATO_CALYX.lightened(0.10), 1, false, 0.0, 0.25, 0.55)


## 五瓣小花（番茄用黄色，西瓜生长中也借它点缀一朵）。
static func _tomato_flower_at(st: SurfaceTool, c: Vector3, col: Color) -> void:
	for k in range(5):
		var ang: float = TAU * float(k) / 5.0
		var d := Vector3(cos(ang), 0.55, sin(ang)).normalized()
		_leaf_along(st, c, d, Vector3(-sin(ang), 0.0, cos(ang)),
				0.021, 0.013, 0.0, col, col, 1, false, 0.0, 0.30, 0.60)
	_ball(st, c, Vector3.UP, 0.006, 0.006, 4, 2, col.darkened(0.18), col, 0)


# ============================================================ 羽衣甘蓝 ====
static func _kale(st: SurfaceTool, stage_id: String) -> void:
	# 每层：数量 / 叶长 / 叶宽 / 上扬角 / 起始高度 / 起始基座半径。
	# 莲座结构：外层低而外展、内层高而直立，层间靠色差与前后遮挡形成体积。
	var layers: Array = []
	if stage_id == "seedling":
		layers = [[5, 0.092, 0.078, 0.72, 0.004, 0.014]]
	elif stage_id == "growing":
		layers = [[7, 0.180, 0.115, 0.50, 0.006, 0.036],
			[5, 0.130, 0.095, 0.92, 0.020, 0.014]]
	else:
		# 成熟莲座：三层叶片向外辐射、叶梢略微上扬再弯下，层与层之间留出可见的缝隙，
		# 内层明显更浅（甘蓝的嫩心），外层最深，形成「深外叶 + 浅叶心」的莲座结构。
		layers = [[8, 0.255, 0.128, 0.30, 0.008, 0.050],
			[7, 0.215, 0.120, 0.80, 0.022, 0.028],
			[5, 0.175, 0.108, 1.22, 0.036, 0.010]]
	# 中心短茎
	var stem_h: float = 0.110 if stage_id == "mature" else (0.075 if stage_id == "growing" else 0.030)
	_tube(st, [Vector3(0, 0, 0), Vector3(0.0, stem_h, 0.0)], [0.024, 0.016], 5,
			C_KALE_STEM, C_KALE_STEM, false)
	for li in range(layers.size()):
		var spec: Array = layers[li]
		var n: int = int(spec[0])
		var length: float = float(spec[1])
		var width: float = float(spec[2])
		var pitch: float = float(spec[3])
		var y0: float = float(spec[4])
		var base_r: float = float(spec[5])
		var c_out: Color = C_KALE_OUTER
		var c_in: Color = C_KALE_MID
		if li == 1:
			c_out = C_KALE_MID
			c_in = C_KALE_INNER
		elif li >= 2:
			c_out = C_KALE_INNER
			c_in = C_KALE_PALE
		for k in range(n):
			var yaw: float = TAU * float(k) / float(n) + float(li) * 0.72 + 0.12 * sin(float(li) * 3.7 + float(k) * 1.9)
			var bp := Vector3(cos(yaw) * base_r, y0, sin(yaw) * base_r)
			# 每片叶轻微换色（10%~35% 混向亮色），避免整丛糊成一块同色
			var mix_amt: float = 0.06 + 0.22 * (float((k * 7 + li * 3) % 5) / 4.0)
			var lc_out: Color = c_out.lerp(c_in, mix_amt)
			var lc_in: Color = c_in.lerp(C_KALE_PALE, mix_amt * 0.5)
			# 宽倒卵叶：缓慢波状叶缘 + 中等中脊 + 叶梢先扬后垂，让每片叶的外轮廓可见
			var pitch_k: float = pitch + 0.16 * sin(float(k) * 2.3 + float(li) * 1.7)
			_leaf(st, bp, yaw, pitch_k,
					length, width, length * (0.16 + 0.06 * float(li)),
					lc_out, lc_in, 4, true, 0.16, 0.30, 0.42)
