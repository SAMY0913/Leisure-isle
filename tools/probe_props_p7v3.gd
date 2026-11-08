extends SceneTree
## P7-V3.2 T3 家具比例审计探针（headless）
##
## 目标：用真实构建出来的网格 AABB（不是读 DIMS 表）逐件复核 isle_house_props.gd 的 25 类家具，
## 并检查人体工学关键子高度与家具之间的配合约束，最后打印可被日志抓取的 RESULT 行。
##
## 判定来源：scripts/isle_scale_spec.gd 的 _REGISTRY（PASS 阈值=该件 tol，默认 5%）；
## 各件 AABB 尺寸语义：Vector3(x=宽, y=高, z=深)；DIMS 存的是 Vector3(宽, 深, 高)。
##
## 保留的旧契约断言：返回键、节点命名/原点/朝向、footprint/height 与 DIMS 一致、部件/网格数、
## 材质全部为 toon ShaderMaterial 且带 0.02 描边、无 Light3D、重复 build 材质不新增、
## NaN/Inf 检查、释放归零、未知 kind 返回空、width/depth/height 覆盖、color/cushion/rot 覆盖。
##
## 运行：
##   & <GODOT> --headless --path <proj> --script res://tools/probe_props_p7v3.gd
## 输出以 "[PROPS] RESULT ..." 结尾；fail==0 时 exit 0。

const PROPS := preload("res://scripts/isle_house_props.gd")
const SPEC := preload("res://scripts/isle_scale_spec.gd")
const BATCH := preload("res://scripts/isle_batch.gd")

const ALL_KINDS := [
	"armchair", "bed", "bookshelf", "chair", "coat_rack", "coffee_table", "curtain",
	"desk", "dining_table", "doormat", "firewood_basket", "floor_lamp", "nightstand",
	"picture_frame", "plant_pot", "reading_chair", "rug", "shoe_bench", "side_table",
	"sideboard", "sofa", "table_lamp", "tall_cupboard", "wall_clock", "wardrobe",
]
const WALL_KINDS := ["coat_rack", "curtain", "picture_frame", "wall_clock"]

var checks := 0
var pass_n := 0
var warn_n := 0
var fail_n := 0

var stage: Node3D = null
var round1: Dictionary = {}
var spec_results: Array = []
var mats_before: Dictionary = {}
var round1_mesh_count := 0
# 成本统计（P7-V3.2 家具重建前后对比用）
var cost_parts := 0
var cost_surfaces := 0
var cost_verts := 0
var cost_tris := 0
var cost_glow := 0
var cost_mats := 0
var cost_merged_inst := 0
var cost_merged_surf := 0
var cost_merged_tris := 0

func _initialize() -> void:
	print("[PROPS] ===== P7-V3.2 T3 家具比例审计（1 世界单位 = 1 m；AABB 实测） =====")
	stage = Node3D.new()
	stage.name = "PropsStage"
	root.add_child(stage)
	_check_registry()
	_print_dims_table()
	_build_round1()
	_check_roles()
	_check_relations()
	_cost_probe()
	await _second_round()
	await _free_round()
	await _extra_contract_checks()
	_print_summary()
	quit(0 if fail_n == 0 else 1)

# ============================================================
# 注册表 / DIMS 自洽
# ============================================================
func _check_registry() -> void:
	print("[PROPS] ---- 注册表 / DIMS / spec 自洽 ----")
	var kinds: Array = PROPS.kinds()
	_check(kinds.size() == ALL_KINDS.size(), "家具类别数 %d == %d" % [kinds.size(), ALL_KINDS.size()])
	for kind in ALL_KINDS:
		_check(PROPS.has_kind(kind), "kind 已注册：%s" % kind)
	var d: Vector3 = PROPS.dims("bed")
	_check(is_finite(d.x) and is_finite(d.y) and is_finite(d.z), "DIMS 数值有限：bed %s" % str(d))
	var bad := 0
	for kind in ALL_KINDS:
		var dd: Vector3 = PROPS.dims(kind)
		if not (is_finite(dd.x) and is_finite(dd.y) and is_finite(dd.z)) or dd.x <= 0.02 or dd.y <= 0.02 or dd.z <= 0.0:
			bad += 1
			print("    [WARN] DIMS 异常：%s %s" % [kind, str(dd)])
	_check(bad == 0, "25 类 DIMS 全部有限且为正（异常 %d）" % bad)
	# DIMS ↔ spec 对齐：DIMS=(w,d,h)，spec=(w,h,d)
	var mismatch := 0
	for kind in ALL_KINDS:
		var dim: Dictionary = SPEC.dimension(kind)
		if dim.is_empty():
			mismatch += 1
			continue
		var t: Vector3 = dim["size"]
		var dd: Vector3 = PROPS.dims(kind)
		if absf(dd.x - t.x) > 0.001 or absf(dd.y - t.z) > 0.001 or absf(dd.z - t.y) > 0.001:
			mismatch += 1
			print("    [WARN] DIMS/spec 不对齐：%s DIMS%s spec(宽%.2f 高%.2f 深%.2f)" % [kind, str(dd), t.x, t.y, t.z])
	_check(mismatch == 0, "DIMS 与 isle_scale_spec 目标表逐项对齐（不对齐 %d）" % mismatch)
	# 墙挂标记
	var wm_bad := 0
	for kind in ALL_KINDS:
		if PROPS.is_wall_mounted(kind) != WALL_KINDS.has(kind):
			wm_bad += 1
	_check(wm_bad == 0, "墙挂 kind 标记与约定一致（%s）" % str(WALL_KINDS))

func _print_dims_table() -> void:
	print("[PROPS] ---- DIMS（声明：宽, 深, 高）与 spec 目标（宽, 高, 深） ----")
	for kind in ALL_KINDS:
		var d: Vector3 = PROPS.dims(kind)
		var t: Vector3 = SPEC.size_of(kind)
		var wall := "WALL" if PROPS.is_wall_mounted(kind) else "floor"
		print("  DIMS %-16s %-5s 宽 %.3f 深 %.3f 高 %.3f | spec 宽 %.3f 高 %.3f 深 %.3f" % [
			String(kind), wall, d.x, d.y, d.z, t.x, t.y, t.z])

# ============================================================
# 第一轮：逐件构建 + 真实 AABB / 契约 / 描边 / 自发光
# ============================================================
func _build_round1() -> void:
	print("[PROPS] ---- 第一轮构建 + 真实 AABB vs spec ----")
	var pos := Vector3(1.0, 0.55, -2.0)
	var yaw := 0.37
	for kind in ALL_KINDS:
		var r: Dictionary = PROPS.build(stage, kind, pos, yaw)
		if not _check(not r.is_empty(), "[%s] build 返回非空" % kind):
			continue
		var n: Node3D = r.get("node")
		if not _check(n is Node3D and n.get_parent() == stage, "[%s] node 已挂到 stage" % kind):
			continue
		var fp: Vector2 = r.get("footprint", Vector2.ZERO)
		var ht: float = float(r.get("height", 0.0))
		var d: Vector3 = PROPS.dims(kind)
		# --- 返回契约 ---
		var contract_ok := r.has("node") and r.has("footprint") and r.has("height") and r.has("kind") and r.has("lights")
		_check(contract_ok, "[%s] 返回契约含 node/footprint/height/kind/lights" % kind)
		_check(String(r.get("kind", "")) == kind, "[%s] 返回 kind 一致" % kind)
		var lights: Variant = r.get("lights", null)
		_check(lights is Array and (lights as Array).is_empty(), "[%s] lights 为空数组（不建 Light3D）" % kind)
		# --- 节点身份 ---
		var ident_ok: bool = n.name.begins_with("Prop_%s_" % kind) \
			and n.position.is_equal_approx(pos) \
			and absf(n.rotation.y - yaw) < 0.001 \
			and String(n.get_meta("prop_kind", "")) == kind \
			and bool(n.get_meta("prop_wall_mounted", false)) == PROPS.is_wall_mounted(kind)
		_check(ident_ok, "[%s] 命名/原点/yaw/prop_kind/prop_wall_mounted 正确" % kind)
		_check(fp.is_equal_approx(Vector2(d.x, d.y)) and absf(ht - d.z) < 0.001,
			"[%s] footprint=(%.2f,%.2f)/height=%.2f 与 DIMS 一致" % [kind, fp.x, fp.y, ht])
		# --- 部件 / 网格 ---
		var parts: int = n.get_child_count()
		var meshes: int = _count_meshes(n)
		_check(parts >= 3 and meshes >= 4, "[%s] 部件 %d / 网格 %d（>=3 / >=4）" % [kind, parts, meshes])
		# --- 材质：toon + 描边 + self_lit ---
		var bad_mat := 0
		var lit := 0
		var glow_parts := 0
		for c in n.get_children():
			var mi := c as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			if String(mi.name).begins_with("Glow"):
				glow_parts += 1
				continue
			var sm := mi.material_override as ShaderMaterial
			if sm == null:
				bad_mat += 1
				continue
			if sm.next_pass == null:
				bad_mat += 1
			if float(sm.get_shader_parameter("self_lit")) > 0.5:
				lit += 1
		_check(bad_mat == 0, "[%s] 非 Glow 部件全部 toon ShaderMaterial + 0.02 描边（异常 %d）" % [kind, bad_mat])
		_check(not _has_light3d(n), "[%s] 无 Light3D" % kind)
		if kind == "table_lamp" or kind == "floor_lamp":
			_check(lit >= 1 and glow_parts >= 1, "[%s] 自发光部件 %d / 光晕 %d" % [kind, lit, glow_parts])
		# --- 真实 AABB ---
		var ab: AABB = _aabb_of(n)
		_check(ab.size.x > 0.0 and ab.size.y > 0.0 and ab.size.z > 0.0, "[%s] AABB 非零" % kind)
		_check(_aabb_finite(ab), "[%s] AABB 数值有限" % kind)
		_check(_aabb_placement_ok(kind, ab, d),
			"[%s] AABB 落位 floor/wall 约定（min %s max %s）" % [kind,
				"(%.3f,%.3f,%.3f)" % [ab.position.x, ab.position.y, ab.position.z],
				"(%.3f,%.3f,%.3f)" % [ab.end.x, ab.end.y, ab.end.z]])
		# 声明尺寸 vs 实测（应该自洽；与 spec 的对照交给 SPEC.check）
		var tol_x := maxf(0.012, d.x * 0.02)
		var tol_z := maxf(0.012, d.y * 0.02)
		var tol_y := maxf(0.012, d.z * 0.02)
		_check(absf(ab.size.x - d.x) <= tol_x and absf(ab.size.z - d.y) <= tol_z and absf(ab.size.y - d.z) <= tol_y,
			"[%s] 实测 AABB %.3f×%.3f×%.3f ≈ DIMS 宽%.3f 深%.3f 高%.3f" % [
				kind, ab.size.x, ab.size.y, ab.size.z, d.x, d.y, d.z])
		print("[PROPS] MEASURE %-16s size=(%.3f, %.3f, %.3f) min=(%.3f, %.3f, %.3f)" % [
			kind, ab.size.x, ab.size.y, ab.size.z, ab.position.x, ab.position.y, ab.position.z])
		_spec_check(kind, ab.size)
		round1[kind] = {"node": n, "aabb": ab, "parts": parts, "meshes": meshes}
	# 首轮材质快照 / 网格总数
	round1_mesh_count = _count_meshes(stage)
	_collect_material_ids(stage, mats_before)
	_check(round1_mesh_count > 0 and mats_before.size() > 0,
		"首轮构建完成：props %d / meshes %d / 材质实例 %d" % [round1.size(), round1_mesh_count, mats_before.size()])

## 落位约束：落地件贴地且 AABB 在声明占地内；墙挂件从 z=0 向 +Z 展开、垂直以原点为中心（curtain 向下）。
func _aabb_placement_ok(kind: String, ab: AABB, d: Vector3) -> bool:
	if PROPS.is_wall_mounted(kind):
		if ab.position.z < -0.02 or ab.position.z > 0.001:
			return false
		if ab.end.z > d.y + 0.012:
			return false
		if absf(ab.get_center().x) > d.x * 0.5 + 0.012:
			return false
		if kind == "curtain":
			return ab.position.y >= -d.z - 0.012 and ab.end.y <= 0.06
		return ab.position.y >= -d.z * 0.5 - 0.012 and ab.end.y <= d.z * 0.5 + 0.012
	if ab.position.y < -0.006 or ab.position.y > 0.03:
		return false
	if ab.end.y > d.z + 0.012:
		return false
	if absf(ab.get_center().x) > 0.02 or absf(ab.get_center().z) > 0.02:
		return false
	return true

func _spec_check(kind: String, actual: Vector3) -> void:
	var st: Dictionary = SPEC.check(kind, actual)
	spec_results.append(st)
	checks += 1
	var status := String(st.get("status", "FAIL"))
	if status == "PASS":
		pass_n += 1
		print("  [PASS] SPEC %s" % String(st.get("detail", kind)))
	elif status == "WARN":
		warn_n += 1
		print("  [WARN] SPEC %s" % String(st.get("detail", kind)))
	else:
		fail_n += 1
		print("  [FAIL] SPEC %s" % String(st.get("detail", kind)))

# ============================================================
# 关键子高度（按 prop_role 实测真实子件 AABB）
# ============================================================
func _check_roles() -> void:
	print("[PROPS] ---- 人体工学关键子高度（按 prop_role 实测） ----")
	# 桌面 / 台面顶：餐桌 0.65、书桌 0.65、茶几 0.38、矮柜 0.80、床头柜 0.50、边桌 0.50
	var tabletops := {
		"dining_table": 0.65, "desk": 0.65, "coffee_table": 0.38,
		"sideboard": 0.80, "nightstand": 0.50, "side_table": 0.50,
	}
	for kind in tabletops:
		var ab: AABB = _role_aabb(_node(kind), "tabletop")
		if _check(_record_has_role(_node(kind), "tabletop"), "[%s] 有 prop_role=tabletop 子件" % kind):
			_scalar("%s.tabletop_top" % kind, ab.end.y, float(tabletops[kind]), 0.05)
	# 座面：椅/沙发/扶手椅/阅读椅 0.40，换鞋凳 0.42
	var seats := {"chair": 0.40, "sofa": 0.40, "armchair": 0.40, "reading_chair": 0.40, "shoe_bench": 0.42}
	for kind in seats:
		var ab: AABB = _role_aabb(_node(kind), "seat")
		if _check(_record_has_role(_node(kind), "seat"), "[%s] 有 prop_role=seat 子件" % kind):
			_scalar("%s.seat_top" % kind, ab.end.y, float(seats[kind]), 0.05)
	# 床垫顶 0.45 / 枕头顶 0.52–0.66
	var bed_node := _node("bed")
	var mat_ab: AABB = _role_aabb(bed_node, "mattress")
	if _check(_record_has_role(bed_node, "mattress"), "[bed] 有 prop_role=mattress 子件"):
		_scalar("bed.mattress_top", mat_ab.end.y, 0.45, 0.05)
		var pil_ab: AABB = _role_aabb(bed_node, "pillow")
		if _check(_record_has_role(bed_node, "pillow"), "[bed] 有 prop_role=pillow 子件"):
			_range("bed.pillow_top", pil_ab.end.y, 0.52, 0.66)
			_range("bed.pillow_vs_mattress", pil_ab.end.y - mat_ab.end.y, 0.06, 0.20)
	# 书架：5 层板，层距 0.28–0.34
	var shelf_abs: Array = _role_aabbs(_node("bookshelf"), "shelf")
	_check(shelf_abs.size() == 5, "[bookshelf] 层板数 5（实测 %d）" % shelf_abs.size())
	if shelf_abs.size() >= 2:
		var tops: Array = []
		for s in shelf_abs:
			var a: AABB = s
			tops.append(a.end.y)
		tops.sort()
		for i in range(1, tops.size()):
			var pitch: float = float(tops[i]) - float(tops[i - 1])
			_check(pitch >= 0.28 - 0.001 and pitch <= 0.34 + 0.001,
				"[bookshelf] 层距 %.3f ∈ [0.28, 0.34]" % pitch)
	# 柜类操作高度：衣柜 / 高柜把手 0.40–1.60
	for kind in ["wardrobe", "tall_cupboard"]:
		var hs: Array = _role_aabbs(_node(kind), "door_handle") + _role_aabbs(_node(kind), "drawer_handle")
		if _check(hs.size() >= 2, "[%s] 把手子件 ≥2（实测 %d）" % [kind, hs.size()]):
			var lo := INF
			var hi := -INF
			for h in hs:
				var a: AABB = h
				lo = minf(lo, a.get_center().y)
				hi = maxf(hi, a.get_center().y)
			_check(lo >= 0.40 - 0.001 and hi <= 1.60 + 0.001,
				"[%s] 门/抽屉把手操作高度 %.3f–%.3f ∈ [0.40, 1.60]" % [kind, lo, hi])
	# 灯具灯罩位置/高度随新尺寸
	var t_sh: AABB = _role_aabb(_node("table_lamp"), "light_shade")
	if _check(_record_has_role(_node("table_lamp"), "light_shade"), "[table_lamp] 有 prop_role=light_shade 子件"):
		_range("table_lamp.shade_center_y", t_sh.get_center().y, 0.30, 0.45)
		_range("table_lamp.shade_h", t_sh.size.y, 0.18, 0.22)
	var f_sh: AABB = _role_aabb(_node("floor_lamp"), "light_shade")
	if _check(_record_has_role(_node("floor_lamp"), "light_shade"), "[floor_lamp] 有 prop_role=light_shade 子件"):
		_range("floor_lamp.shade_center_y", f_sh.get_center().y, 1.20, 1.36)
		_range("floor_lamp.shade_h", f_sh.size.y, 0.24, 0.30)

# ============================================================
# 家具之间的配合约束
# ============================================================
func _check_relations() -> void:
	print("[PROPS] ---- 家具间人体工学配合 ----")
	var chair_seat: float = _role_aabb(_node("chair"), "seat").end.y
	var table_top: float = _role_aabb(_node("dining_table"), "tabletop").end.y
	var apron_bottom: float = _role_aabb(_node("dining_table"), "apron").position.y
	# 桌面 0.65 - 椅面 0.40 = 0.25（±0.03 → 相对 12%）
	_scalar("relation.dining_table_minus_chair_seat", table_top - chair_seat, 0.25, 0.12)
	_check(apron_bottom > chair_seat + 0.05,
		"relation.餐桌望板下沿 %.3f > 椅面 %.3f + 0.05（腿部空间）" % [apron_bottom, chair_seat])
	_check(chair_seat + 0.02 < apron_bottom,
		"relation.椅面 %.3f + 0.02 < 望板下沿 %.3f（椅可推入桌下不穿望板）" % [chair_seat, apron_bottom])
	var clearance: float = _inner_clearance(_node("dining_table"), "leg")
	var chair_w: float = PROPS.dims("chair").x
	_check(clearance > chair_w + 0.10,
		"relation.餐桌腿内侧净宽 %.3f > 椅宽 %.3f + 0.10（推入不穿桌腿）" % [clearance, chair_w])
	# 床头柜面比床垫顶高 0.03–0.10
	var ns_top: float = _role_aabb(_node("nightstand"), "tabletop").end.y
	var mat_top: float = _role_aabb(_node("bed"), "mattress").end.y
	_range("relation.nightstand_minus_mattress", ns_top - mat_top, 0.03, 0.10)
	# 书桌膝空间 ≥ 0.40（左右 pedestal 内侧净距）
	var knee: float = _inner_clearance(_node("desk"), "pedestal")
	_check(knee >= 0.40, "relation.书桌膝空间 %.3f >= 0.40" % knee)
	# 茶几低于沙发坐面且不高于 0.40（取放合理）
	var sofa_seat: float = _role_aabb(_node("sofa"), "seat").end.y
	var coffee_top: float = _role_aabb(_node("coffee_table"), "tabletop").end.y
	_check(coffee_top < sofa_seat and coffee_top >= 0.25,
		"relation.茶几台面 %.3f < 沙发坐面 %.3f 且 >= 0.25" % [coffee_top, sofa_seat])
	# 边桌 + 台灯 = 阅读灯高 0.90–1.10
	var side_top: float = _role_aabb(_node("side_table"), "tabletop").end.y
	var lamp_h: float = float(round1["table_lamp"]["aabb"].size.y)
	_range("relation.side_table_plus_table_lamp", side_top + lamp_h, 0.90, 1.10)
	# 书架最高层在抬手可达内；床长容纳 1.50 m 人体
	_check(PROPS.height_of("bookshelf") <= SPEC.HUMAN_REACH_UP_H + 0.001,
		"relation.书架高 %.2f <= 抬手可达 %.2f" % [PROPS.height_of("bookshelf"), SPEC.HUMAN_REACH_UP_H])
	_check(PROPS.dims("bed").y >= SPEC.HUMAN_HEIGHT + 0.30,
		"relation.床长 %.2f >= 人体 %.2f + 0.30" % [PROPS.dims("bed").y, SPEC.HUMAN_HEIGHT])
	# 门垫可入门洞
	_check(PROPS.dims("doormat").x <= SPEC.DOOR_CLEAR_W,
		"relation.门垫宽 %.2f <= 门洞净宽 %.2f" % [PROPS.dims("doormat").x, SPEC.DOOR_CLEAR_W])

# ============================================================
# 第二轮：重复构建 / 材质复用 / 数值稳定
# ============================================================
func _second_round() -> void:
	print("[PROPS] ---- 第二轮构建：命名唯一 / 材质复用 / 无 NaN ----")
	var pos := Vector3(2.0, 0.55, -3.0)
	var yaw := -0.21
	for kind in ALL_KINDS:
		var r: Dictionary = PROPS.build(stage, kind, pos, yaw)
		if not _check(not r.is_empty(), "[%s] 第二轮 build 成功" % kind):
			continue
	await process_frame
	var node_total: int = stage.get_child_count()
	_check(node_total == ALL_KINDS.size() * 2, "第二轮后节点数 %d == %d" % [node_total, ALL_KINDS.size() * 2])
	var names: Dictionary = {}
	for c in stage.get_children():
		names[String(c.name)] = true
	_check(names.size() == node_total, "节点名唯一（%d / %d）" % [names.size(), node_total])
	var meshes2: int = _count_meshes(stage)
	_check(meshes2 == round1_mesh_count * 2, "网格数翻倍 %d == %d × 2" % [meshes2, round1_mesh_count])
	var mats2: Dictionary = {}
	_collect_material_ids(stage, mats2)
	var new_mats := 0
	for k in mats2:
		if not mats_before.has(k):
			new_mats += 1
	_check(mats2.size() == mats_before.size() and new_mats == 0,
		"重复构建未新增材质实例（%d → %d，新 %d）" % [mats_before.size(), mats2.size(), new_mats])
	var nan_nodes: Array = []
	_collect_nan(stage, nan_nodes)
	_check(nan_nodes.is_empty(), "全舞台无 NaN/Inf 变换（异常 %d）" % nan_nodes.size())
	if not nan_nodes.is_empty():
		print("    首个异常节点：%s" % String(nan_nodes[0]))

# ============================================================
# 释放
# ============================================================
func _free_round() -> void:
	for c in stage.get_children():
		c.queue_free()
	await process_frame
	await process_frame
	_check(stage.get_child_count() == 0, "释放后 stage 子节点归零（%d）" % stage.get_child_count())
	round1.clear()
	mats_before.clear()

# ============================================================
# 对外契约 / 覆盖参数
# ============================================================
func _extra_contract_checks() -> void:
	print("[PROPS] ---- 对外契约 / 覆盖参数 ----")
	var empty_ret: Dictionary = PROPS.build(stage, "no_such_kind", Vector3.ZERO, 0.0)
	_check(empty_ret.is_empty() and stage.get_child_count() == 0, "未知 kind 返回空字典且不建节点")
	var d: Vector3 = PROPS.dims("dining_table")
	var r: Dictionary = PROPS.build(stage, "dining_table", Vector3.ZERO, 0.0, {"width": 2.0, "depth": 1.1, "height": 0.8})
	var n: Node3D = r.get("node")
	if _check(n is Node3D, "width/depth/height 覆盖可构建"):
		var want := Vector3(2.0 / d.x, 0.8 / d.z, 1.1 / d.y)
		_check((n.scale - want).length() < 0.0001,
			"覆盖缩放 node.scale=(%.4f,%.4f,%.4f) 期望 (%.4f,%.4f,%.4f)" % [
				n.scale.x, n.scale.y, n.scale.z, want.x, want.y, want.z])
		_check((r.get("footprint", Vector2.ZERO) as Vector2).is_equal_approx(Vector2(2.0, 1.1)),
			"覆盖后 footprint=(2.00,1.10)")
		_check(absf(float(r.get("height", 0.0)) - 0.8) < 0.001, "覆盖后 height=0.80")
	var r2: Dictionary = PROPS.build(stage, "sofa", Vector3(1, 0, 0), 0.2,
		{"color": Color(0.8, 0.2, 0.2), "cushion": Color(0.2, 0.3, 0.8)})
	_check(not r2.is_empty(), "color/cushion 覆盖可构建")
	var r3: Dictionary = PROPS.build(stage, "picture_frame", Vector3(0, 0, 0), 0.0, {"rot": Vector3(0.1, 0.2, 0.3)})
	var n3: Node3D = r3.get("node")
	if _check(n3 is Node3D, "rot 覆盖可构建"):
		_check(n3.rotation.is_equal_approx(Vector3(0.1, 0.2, 0.3)),
			"rot 覆盖生效 %s" % str(n3.rotation))
	await process_frame
	for c in stage.get_children():
		c.queue_free()
	await process_frame
	_check(stage.get_child_count() == 0, "契约检查后清理归零（%d）" % stage.get_child_count())

# ============================================================
# 测量辅助
# ============================================================
func _node(kind: String) -> Node3D:
	if not round1.has(kind):
		return null
	return round1[kind]["node"]

func _record_has_role(prop: Node3D, role: String) -> bool:
	return prop != null and not _role_aabbs(prop, role).is_empty()

func _role_aabbs(prop: Node3D, role: String) -> Array:
	var out: Array = []
	if prop == null:
		return out
	for c in prop.get_children():
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if String(mi.get_meta("prop_role", "")) != role:
			continue
		out.append(_mesh_aabb_local(mi))
	return out

func _role_aabb(prop: Node3D, role: String) -> AABB:
	var list: Array = _role_aabbs(prop, role)
	if list.is_empty():
		return AABB()
	var out: AABB = list[0]
	for i in range(1, list.size()):
		out = out.merge(list[i])
	return out

## 左右同名 role 子件之间的内侧净距（例：桌腿、书桌 pedestal）。
func _inner_clearance(prop: Node3D, role: String) -> float:
	var neg := -INF
	var pos := INF
	for a in _role_aabbs(prop, role):
		var ab: AABB = a
		var cx := ab.get_center().x
		if cx < -0.0001:
			neg = maxf(neg, ab.end.x)
		elif cx > 0.0001:
			pos = minf(pos, ab.position.x)
	if not is_finite(neg) or not is_finite(pos):
		return -1.0
	return pos - neg

## 单件家具真实 AABB（局部坐标）：遍历全部 MeshInstance3D，排除 Glow 光晕与空网格。
func _aabb_of(prop: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for c in prop.get_children():
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if String(mi.name).begins_with("Glow"):
			continue
		var ab: AABB = _mesh_aabb_local(mi)
		if first:
			out = ab
			first = false
		else:
			out = out.merge(ab)
	return out

## 单个 MeshInstance3D 在其父节点坐标系的 AABB（mesh AABB 8 角点经节点变换）。
func _mesh_aabb_local(mi: MeshInstance3D) -> AABB:
	var ab: AABB = mi.mesh.get_aabb()
	var out := AABB()
	var first := true
	for i in range(8):
		var corner: Vector3 = ab.position + Vector3(
			ab.size.x * float(i & 1),
			ab.size.y * float((i >> 1) & 1),
			ab.size.z * float((i >> 2) & 1))
		var w: Vector3 = mi.transform * corner
		if first:
			out = AABB(w, Vector3.ZERO)
			first = false
		else:
			out = out.expand(w)
	return out

func _aabb_finite(ab: AABB) -> bool:
	return is_finite(ab.position.x) and is_finite(ab.position.y) and is_finite(ab.position.z) \
		and is_finite(ab.end.x) and is_finite(ab.end.y) and is_finite(ab.end.z)

func _count_meshes(n: Node) -> int:
	var c := 0
	if n is MeshInstance3D:
		c += 1
	for ch in n.get_children():
		c += _count_meshes(ch)
	return c

func _has_light3d(n: Node) -> bool:
	if n is Light3D:
		return true
	for ch in n.get_children():
		if _has_light3d(ch):
			return true
	return false

func _collect_material_ids(n: Node, out: Dictionary) -> void:
	for ch in n.get_children():
		var mi := ch as MeshInstance3D
		if mi != null and mi.material_override != null:
			out[mi.material_override.get_instance_id()] = true
		_collect_material_ids(ch, out)

func _collect_nan(n: Node, out: Array) -> void:
	if n is Node3D:
		var t: Transform3D = (n as Node3D).transform
		var bad := not (is_finite(t.origin.x) and is_finite(t.origin.y) and is_finite(t.origin.z) \
			and is_finite(t.basis.x.x) and is_finite(t.basis.x.y) and is_finite(t.basis.x.z) \
			and is_finite(t.basis.y.x) and is_finite(t.basis.y.y) and is_finite(t.basis.y.z) \
			and is_finite(t.basis.z.x) and is_finite(t.basis.z.y) and is_finite(t.basis.z.z))
		if bad:
			out.append(n)
	for ch in n.get_children():
		_collect_nan(ch, out)

# ============================================================
# 成本统计（P7-V3.2：重建前后 mesh/surface/vertex/triangle 对比）
# ============================================================
func _cost_probe() -> void:
	print("[PROPS] ---- 成本统计（25 类各 1 件；未合批 → 单件合批后） ----")
	var st2 := Node3D.new()
	st2.name = "CostStage"
	root.add_child(st2)
	var acc := {"parts": 0, "surfaces": 0, "verts": 0, "tris": 0, "glow": 0, "mats": {}}
	for kind in ALL_KINDS:
		var r: Dictionary = PROPS.build(st2, kind, Vector3.ZERO, 0.0)
		var n: Node3D = r.get("node")
		var one := {"parts": 0, "surfaces": 0, "verts": 0, "tris": 0, "glow": 0, "mats": {}}
		_cost_of(n, one)
		for key in ["parts", "surfaces", "verts", "tris", "glow"]:
			acc[key] = int(acc[key]) + int(one[key])
		for mid in (one["mats"] as Dictionary).keys():
			(acc["mats"] as Dictionary)[mid] = true
		var mer: Dictionary = BATCH.merge_static(n)
		var after := {"parts": 0, "surfaces": 0, "verts": 0, "tris": 0, "glow": 0, "mats": {}}
		_cost_of(n, after)
		cost_merged_inst += int(after["parts"])
		cost_merged_surf += int(after["surfaces"])
		cost_merged_tris += int(after["tris"])
		print("[COST] %-14s pre parts=%3d surf=%3d verts=%5d tris=%5d glow=%2d mats=%2d | post inst=%2d surf=%2d tris=%5d merged=%s" % [
			kind, int(one["parts"]), int(one["surfaces"]), int(one["verts"]), int(one["tris"]),
			int(one["glow"]), (one["mats"] as Dictionary).size(),
			int(after["parts"]), int(after["surfaces"]), int(after["tris"]),
			str(bool(mer.get("merged", false)))])
	cost_parts = int(acc["parts"])
	cost_surfaces = int(acc["surfaces"])
	cost_verts = int(acc["verts"])
	cost_tris = int(acc["tris"])
	cost_glow = int(acc["glow"])
	cost_mats = (acc["mats"] as Dictionary).size()
	print("[PROPS] COST total pre_batch parts=%d surfaces=%d verts=%d tris=%d glow=%d mats=%d" % [
		cost_parts, cost_surfaces, cost_verts, cost_tris, cost_glow, cost_mats])
	print("[PROPS] COST total post_batch inst=%d surfaces=%d tris=%d（三角形守恒=%s）" % [
		cost_merged_inst, cost_merged_surf, cost_merged_tris,
		str(cost_merged_tris == cost_tris)])
	st2.queue_free()

func _cost_of(n: Node, acc: Dictionary) -> void:
	var mi := n as MeshInstance3D
	if mi != null and mi.mesh != null:
		acc["parts"] = int(acc["parts"]) + 1
		var nm := String(mi.name)
		if nm.begins_with("Glow") or nm.begins_with("Halo") or nm.begins_with("Blob"):
			acc["glow"] = int(acc["glow"]) + 1
		var mesh: Mesh = mi.mesh
		var sc := mesh.get_surface_count()
		acc["surfaces"] = int(acc["surfaces"]) + sc
		for s in range(sc):
			var arr: Array = mesh.surface_get_arrays(s)
			if arr.is_empty():
				continue
			var vcount := (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			acc["verts"] = int(acc["verts"]) + vcount
			var tcount := vcount / 3
			var idx_v: Variant = arr[Mesh.ARRAY_INDEX]
			if idx_v is PackedInt32Array:
				tcount = (idx_v as PackedInt32Array).size() / 3
			acc["tris"] = int(acc["tris"]) + tcount
			var mat: Material = null
			if mi.material_override != null:
				mat = mi.material_override
			else:
				mat = mesh.surface_get_material(s)
			if mat != null:
				(acc["mats"] as Dictionary)[mat.get_instance_id()] = true
	for ch in n.get_children():
		_cost_of(ch, acc)

# ============================================================
# 计数 / 打印
# ============================================================
func _check(ok: bool, msg: String) -> bool:
	checks += 1
	if ok:
		pass_n += 1
		print("  [PASS] " + msg)
	else:
		fail_n += 1
		print("  [FAIL] " + msg)
	return ok

func _scalar(label: String, actual: float, target: float, tol: float) -> void:
	var st: Dictionary = SPEC.check_scalar(label, actual, target, tol)
	checks += 1
	var status := String(st.get("status", "FAIL"))
	if status == "PASS":
		pass_n += 1
		print("  [PASS] " + String(st.get("detail", label)))
	elif status == "WARN":
		warn_n += 1
		print("  [WARN] " + String(st.get("detail", label)))
	else:
		fail_n += 1
		print("  [FAIL] " + String(st.get("detail", label)))

func _range(label: String, value: float, lo: float, hi: float) -> void:
	_check(value >= lo - 0.001 and value <= hi + 0.001,
		"%s 实测 %.3f ∈ [%.3f, %.3f]" % [label, value, lo, hi])

func _print_summary() -> void:
	print("")
	print("[PROPS] ===== 规格对照汇总（isle_scale_spec.gd，PASS=该件 tol 内） =====")
	var sp := 0
	var sw := 0
	var sf := 0
	var worst := ""
	var worst_err := 0.0
	for st in spec_results:
		var status := String(st.get("status", "FAIL"))
		match status:
			"PASS":
				sp += 1
			"WARN":
				sw += 1
			_:
				sf += 1
		var err := float(st.get("max_rel_err", 0.0))
		if err > worst_err:
			worst_err = err
			worst = String(st.get("key", ""))
	print("[PROPS] spec 25 类：PASS %d / WARN %d / FAIL %d；最大相对误差 %.2f%%（%s）" % [
		sp, sw, sf, worst_err * 100.0, worst])
	print("[PROPS] RESULT fail=%d warn=%d pass=%d checks=%d specs_pass=%d specs_warn=%d specs_fail=%d round1_meshes=%d cost_parts=%d cost_tris=%d merged_inst=%d" % [
		fail_n, warn_n, pass_n, checks, sp, sw, sf, round1_mesh_count,
		cost_parts, cost_tris, cost_merged_inst])
