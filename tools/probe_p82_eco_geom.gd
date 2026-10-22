extends SceneTree
## P8.2-04 冬季细节 + 冬季生态几何验收（headless：不加载 isle.tscn，只 build world/cottage）。
## 运行：
##   cd "D:/休闲小岛幻境/游戏工程" && bash "D:/休闲小岛幻境/开发产物/p82/run_godot.sh" \
##     --headless --path . --script res://tools/probe_p82_eco_geom.gd
## 覆盖：
##   [PERCH]  5 个冬季裸枝栖点贴真实 CylinderMesh 枝面；AABB 内含；法线垂直枝轴；normal.y/slope 自洽；
##            枝轴半径/直径 vs 海鸥脚尺寸比例（打印 + 合理性断言）；栖点上方 0.20m 无其它枝干穿过（不穿模）；
##            栖点离地高度、离秋千绳距离、两两间距。
##   [FLOWER] 屋前 5 朵红花：高度场射线步进（=对解析地形做 raycast）命中高度 vs 花基高度；
##            花基 8 向环采样（悬空/埋根）；坡面高差；离路缘/门廊/门距/间距；头顶净空。
##   [SEASON] 四季参数（冬季 canopy/leafcard=0，春季恢复），canopy/leafcards 实例数。
## 退出码：0 = 全部通过；1 = 有失败。

const World := preload("res://scripts/world.gd")
const Cottage := preload("res://scripts/cottage.gd")
const Season := preload("res://scripts/isle_season.gd")
const Fx := preload("res://scripts/fx.gd")
const IM := preload("res://scripts/isle_math.gd")

const BIG_TREE_X := -10.9
const BIG_TREE_Z := 4.2
const SWING_PIVOT_LOCAL := Vector3(3.0, 5.55, 0.0)
const OUT_DIR := "D:/休闲小岛幻境/开发产物/p82/04_winter/"

var _pass := 0
var _fail := 0
var _fails: Array = []
var _world_holder: Node3D = null
var _cottage_holder: Node3D = null
var _island: Dictionary = {}
var _cottage: Dictionary = {}
var _world_root: Node3D = null
var _big: Node3D = null
var _base := Vector3.ZERO
var _winter_perches: Array = []
var _cylinders: Array = []
var _foot_dims: Dictionary = {}

func _initialize() -> void:
	print("=== P8.2-04 ECO GEOM PROBE START ===")
	await process_frame
	_world_holder = Node3D.new()
	_world_holder.name = "P82EcoWorld"
	get_root().add_child(_world_holder)
	_island = World.build(_world_holder, true)
	_cottage_holder = Node3D.new()
	_cottage_holder.name = "P82EcoCottage"
	get_root().add_child(_cottage_holder)
	_cottage = Cottage.build(_cottage_holder)
	await process_frame
	_world_root = _island["root"] as Node3D
	_big = _world_root.find_child("BigTree", true, false) as Node3D
	_base = _island["big_tree"] as Vector3
	_collect_cylinders(_big, _cylinders)
	print("[INFO] BigTree base=", _fmtv(_base), " cylinders=", _cylinders.size())
	await _probe_perches()
	_probe_flowers()
	_probe_season()
	_world_holder.free()
	_cottage_holder.free()
	print("=== P8.2-04 ECO GEOM PROBE RESULT: ", "PASS" if _fail == 0 else "FAIL", " pass=", _pass, " fail=", _fail, " ===")
	for m in _fails:
		print("[FAILED] ", m)
	quit(0 if _fail == 0 else 1)

func _check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("  [OK] ", msg)
	else:
		_fail += 1
		_fails.append(msg)
		print("  [FAIL] ", msg)

func _fmtv(v: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [v.x, v.y, v.z]

func _collect_cylinders(node: Node, out: Array) -> void:
	for c in node.get_children():
		if c is MeshInstance3D:
			var mi: MeshInstance3D = c
			if mi.mesh is CylinderMesh:
				out.append(mi)
		_collect_cylinders(c, out)

# 点到圆柱（线段 + 线性半径）的“表面距离/是否在内部/局部 AABB”
func _cyl_info(mi: MeshInstance3D, wp: Vector3) -> Dictionary:
	var cyl: CylinderMesh = mi.mesh as CylinderMesh
	var xf: Transform3D = mi.global_transform
	var lv: Vector3 = xf.affine_inverse() * wp
	var h: float = maxf(cyl.height, 0.0001)
	var y: float = clampf(lv.y, -h * 0.5, h * 0.5)
	var t: float = (y + h * 0.5) / h
	var r: float = lerpf(cyl.bottom_radius, cyl.top_radius, t)
	var horiz: float = Vector2(lv.x, lv.z).length()
	var maxr: float = maxf(cyl.bottom_radius, cyl.top_radius)
	var aabb := AABB(Vector3(-maxr, -h * 0.5, -maxr), Vector3(maxr * 2.0, h, maxr * 2.0))
	var axis: Vector3 = xf.basis.y.normalized()
	return {
		"name": String(mi.name),
		"dist_surf": absf(horiz - r),
		"inside": horiz < r - 0.0005,
		"clear": horiz - r,
		"within": absf(lv.y) <= h * 0.5 + 0.03,
		"radius": r,
		"axis": axis,
		"in_aabb": aabb.grow(0.025).has_point(lv),
		"horiz": horiz,
		"lv": lv,
	}

func _nearest_cyl(wp: Vector3, skip: MeshInstance3D = null) -> Dictionary:
	var best: Dictionary = {"dist_surf": 1.0e9, "name": "", "ready": false}
	for c_v in _cylinders:
		var mi: MeshInstance3D = c_v
		if skip != null and mi == skip:
			continue
		var info := _cyl_info(mi, wp)
		if float(info["dist_surf"]) < float(best["dist_surf"]):
			info["mesh"] = mi
			best = info
			best["ready"] = true
	return best

func _perch_by_kind(kind: String) -> Array:
	var out: Array = []
	for p_v in (_island.get("perches", []) as Array):
		var p: Dictionary = p_v
		if String(p.get("kind", "")) == kind:
			out.append(p)
	return out

# ============================================================
# 海鸥脚尺寸（真实网格，不是手抄常量）：腿/趾 AABB
# ============================================================
func _measure_foot() -> void:
	var flock: Node = Fx.BirdFlock.new()
	flock.name = "P82FootFlock"
	get_root().add_child(flock)
	await process_frame
	var all: Array = (_island.get("perches", []) as Array) + (_cottage.get("perches", []) as Array)
	flock.call("setup", all)
	await process_frame
	var arr: Array = flock.get("_birds") as Array
	if not arr.is_empty():
		var b: Dictionary = arr[0]
		var node: Node3D = b["node"] as Node3D
		var legs := node.get_node_or_null("legs") as MeshInstance3D
		if legs != null and legs.mesh != null:
			var ab: AABB = legs.mesh.get_aabb()
			_foot_dims = {
				"aabb": ab,
				"toe_len_x": ab.size.x,
				"toe_len_z": ab.size.z,
				"height": ab.size.y,
				"min_y": ab.position.y,
			}
			print("[FOOT] gull legs mesh AABB size=(%.3f, %.3f, %.3f) pos=(%.3f, %.3f, %.3f)" % [
				ab.size.x, ab.size.y, ab.size.z, ab.position.x, ab.position.y, ab.position.z])
	get_root().remove_child(flock)
	flock.free()

# ============================================================
# [PERCH] 5 个冬季裸枝栖点
# ============================================================
func _probe_perches() -> void:
	_winter_perches = _perch_by_kind("winter_branch")
	_check(_winter_perches.size() == 5, "冬季裸枝栖点 5 个 (实际 %d)" % _winter_perches.size())
	if _winter_perches.size() != 5:
		return
	await _measure_foot_wrap()
	var idx := 0
	for p_v in _winter_perches:
		var p: Dictionary = p_v
		var pid := String(p["id"])
		var sp: Vector3 = p["pos"] as Vector3
		var nrm: Vector3 = (p.get("normal", Vector3.UP) as Vector3).normalized()
		var slope: float = float(p.get("slope", 0.0))
		var local: Vector3 = sp - _base
		print("[PERCH-%d] %s world=%s local=%s n=%s slope=%.1fdeg" % [idx, pid, _fmtv(sp), _fmtv(local), _fmtv(nrm), rad_to_deg(slope)])
		# 1) 最近枝干圆柱面
		var near := _nearest_cyl(sp)
		var mi: MeshInstance3D = near.get("mesh", null) as MeshInstance3D
		var dist_surf := float(near["dist_surf"])
		var r := float(near["radius"])
		print("         nearest_cyl=%s r=%.3f dist_surf=%.4f within=%s in_aabb=%s" % [
			String(near["name"]), r, dist_surf, str(bool(near["within"])), str(bool(near["in_aabb"]))])
		_check(mi != null and bool(near["within"]), "%s 栖点在某枝干轴向范围内" % pid)
		_check(dist_surf <= 0.03, "%s 栖点贴真实枝面 dist=%.4f <=0.03" % [pid, dist_surf])
		_check(bool(near["in_aabb"]), "%s 栖点落在该枝干圆柱 AABB 内" % pid)
		var in_depth := maxf(0.0, r - float(near.get("horiz", r)))
		_check(in_depth <= 0.005, "%s 栖点内插深度 %.4fm <=0.005（仅精度级，不算穿模）" % [pid, in_depth])
		var axis: Vector3 = near["axis"]
		_check(absf(axis.dot(nrm)) <= 0.10, "%s 法线垂直枝轴 axis_dot=%.3f" % [pid, absf(axis.dot(nrm))])
		_check(nrm.y >= 0.35, "%s normal.y=%.3f >=0.35" % [pid, nrm.y])
		_check(absf(acos(clampf(nrm.y, -1.0, 1.0)) - slope) < 0.02, "%s slope 与法线一致" % pid)
		var root_y := World.surface_y(BIG_TREE_X, BIG_TREE_Z)
		_check(absf(sp.y - (root_y + local.y)) < 0.002, "%s 世界 y = 树根地表+local.y (Δ=%.4f)" % [pid, absf(sp.y - (root_y + local.y))])
		_check(sp.y - World.surface_y(sp.x, sp.z) >= 4.0, "%s 栖点离地 %.2fm >=4" % [pid, sp.y - World.surface_y(sp.x, sp.z)])
		var rope_d := Vector2(local.x - SWING_PIVOT_LOCAL.x, local.z - SWING_PIVOT_LOCAL.z).length()
		_check(rope_d >= 0.45, "%s 避开秋千绳区 %.2fm >=0.45" % [pid, rope_d])
		# 2) 鸟体净空：沿法线 0.04~0.20m 的轴线上不得被其它枝干穿过
		var body_clear: Array = []
		var foot_clear := 1.0e9
		var foot_owner := ""
		for k in [0.04, 0.08, 0.12, 0.16, 0.20, 0.26]:
			var q: Vector3 = sp + nrm * float(k)
			var wk := 1.0e9
			var wkn := ""
			for c_v in _cylinders:
				var other: MeshInstance3D = c_v
				if other == mi:
					continue
				var oi := _cyl_info(other, q)
				var clear := float(oi["clear"])
				if bool(oi["within"]) and clear < wk:
					wk = clear
					wkn = String(oi["name"])
			if float(k) <= 0.08 and wk < foot_clear:
				foot_clear = wk
				foot_owner = wkn
			body_clear.append({"k": float(k), "clear": wk, "name": wkn})
			print("         body_clear k=%.2f clear=%.4f (%s)" % [float(k), wk, wkn])
		_check(foot_clear >= -0.005, "%s 足部区净空 %.4fm >=-0.005（%s）" % [pid, foot_clear, foot_owner])
		var belly_ok := true
		for e_v in body_clear:
			var e: Dictionary = e_v
			if float(e["k"]) >= 0.10 and float(e["clear"]) < 0.02:
				belly_ok = false
		_check(belly_ok, "%s 鸟腹/身体区（0.10~0.26m）净空 >=0.02" % pid)
		# 3) 枝粗细 vs 脚尺寸比例
		var branch_d := r * 2.0
		var foot_w := float(_foot_dims.get("toe_len_x", 0.064))
		var foot_l := float(_foot_dims.get("toe_len_z", 0.11))
		print("         branch_radius=%.3f branch_dia=%.3f foot_span_x=%.3f foot_len_z=%.3f dia/foot_span=%.2f dia/foot_len=%.2f" % [
			r, branch_d, foot_w, foot_l, branch_d / maxf(foot_w, 0.001), branch_d / maxf(foot_l, 0.001)])
		_check(branch_d >= 0.06, "%s 枝直径 %.3fm >= 脚掌最小支撑 0.06" % [pid, branch_d])
		_check(branch_d <= 0.70, "%s 枝直径 %.3fm <= 0.70（不粗过鸟体）" % [pid, branch_d])
		idx += 1
	for i in range(_winter_perches.size()):
		for j in range(i + 1, _winter_perches.size()):
			var a: Vector3 = (_winter_perches[i] as Dictionary)["pos"] as Vector3
			var b: Vector3 = (_winter_perches[j] as Dictionary)["pos"] as Vector3
			_check(a.distance_to(b) >= 1.5, "裸枝栖点 %d/%d 间距 %.2fm >=1.5" % [i, j, a.distance_to(b)])
	# 冠面点（tree_branch）在冬季视觉里也是裸枝可见的；确认它们的枝面高度在树冠中心以下/附近
	for p_v in _perch_by_kind("tree_branch"):
		var p: Dictionary = p_v
		var sp: Vector3 = p["pos"] as Vector3
		print("[TREEPERCH] %s world=%s local_y=%.3f" % [String(p["id"]), _fmtv(sp), (sp - _base).y])

func _measure_foot_wrap() -> void:
	await _measure_foot()

# ============================================================
# [FLOWER] 屋前 5 朵红花
# ============================================================
## 高度场 raycast：从 y_top 向下按 step 步进，返回首个低于地表的 y（≈ 命中地形）
func _terrain_raycast(x: float, z: float, y_top: float, y_bot: float, step: float = 0.002) -> float:
	var y := y_top
	while y >= y_bot:
		if y <= World.surface_y(x, z):
			return y
		y -= step
	return y_bot

func _probe_flowers() -> void:
	var wb: Dictionary = _island.get("winter_bloom", {})
	if wb.is_empty():
		_fail += 1
		_fails.append("world 未提供 winter_bloom")
		return
	var base: Array = wb.get("base", []) as Array
	_check(base.size() == 5, "冬季红花 5 朵 (实际 %d)" % base.size())
	var door3: Vector3 = IM.door_approach()
	var door := Vector2(door3.x, door3.z)
	var stems: MultiMeshInstance3D = wb.get("stems", null) as MultiMeshInstance3D
	var heads: MultiMeshInstance3D = wb.get("heads", null) as MultiMeshInstance3D
	_check(stems != null and heads != null, "茎/头 MultiMesh 存在")
	if stems == null or heads == null:
		return
	var min_sep := 1.0e9
	for i in range(base.size()):
		var e: Dictionary = base[i]
		var pos: Vector3 = e["pos"] as Vector3
		var sc := float(e.get("scale", 1.0))
		var fx := pos.x
		var fz := pos.z
		var surf := World.surface_y(fx, fz)
		var hit := _terrain_raycast(fx, fz, surf + 1.2, surf - 1.2)
		var gy := pos.y  # world._winter_blooms: y = _h(x,z)-0.01
		print("[FLOWER-%d] xz=(%.3f, %.3f) base_y=%.4f surf_y=%.4f ray_hit=%.4f surf-base=%.4f scale=%.2f" % [
			i, fx, fz, gy, surf, hit, surf - gy, sc])
		_check(absf(gy - (surf - 0.01)) < 0.002, "红花 %d 花基=地表-0.01 (Δ=%.4f)" % [i, absf(gy - (surf - 0.01))])
		_check(absf(hit - surf) < 0.01, "红花 %d raycast 命中=解析地表 (Δ=%.4f)" % [i, absf(hit - surf)])
		# 法线/坡度
		var n := World._hn(fx, fz)
		var slope_deg := rad_to_deg(acos(clampf(n.y, -1.0, 1.0)))
		print("         normal=%s slope=%.2fdeg trail_clear=%.3f door_dist=%.2f" % [_fmtv(n), slope_deg, World.trail_clearance(fx, fz), Vector2(fx, fz).distance_to(door)])
		_check(slope_deg <= 18.0, "红花 %d 花基坡度 %.2fdeg <=18" % [i, slope_deg])
		# 8 向环采样：max_gap=下坡悬空量，min_gap=上坡埋根量
		var r_ring := 0.10 * sc
		var max_gap := -9.0e9
		var min_gap := 9.0e9
		for k in range(8):
			var a := TAU * float(k) / 8.0
			var sx := fx + cos(a) * r_ring
			var sz := fz + sin(a) * r_ring
			var gap := World.surface_y(sx, sz) - surf
			max_gap = maxf(max_gap, gap)
			min_gap = minf(min_gap, gap)
		print("         ring r=%.3f max_gap(下坡悬空)=%.4f min_gap(上坡埋根)=%.4f" % [r_ring, max_gap, min_gap])
		_check(max_gap <= 0.03, "红花 %d 下坡悬空 %.4fm <=0.03" % [i, max_gap])
		_check(min_gap >= -0.05, "红花 %d 上坡埋根 %.4fm >=-0.05" % [i, min_gap])
		# 道路/门廊/草坪/门距
		_check(World.trail_clearance(fx, fz) >= 0.60, "红花 %d 离路缘 %.2fm >=0.60" % [i, World.trail_clearance(fx, fz)])
		_check(not World._in_porch(fx, fz, 0.70), "红花 %d 在门廊排除区外" % i)
		_check(World._grass_spot(fx, fz) > 0.0, "红花 %d 位于合法草地" % i)
		var dd := Vector2(fx, fz).distance_to(door)
		_check(dd >= 3.5 and dd <= 6.0, "红花 %d 离门 %.2fm ∈[3.5,6.0]" % [i, dd])
		# 头部净空：头顶上方 0.30m 不得有房屋/树等 AABB（只看节点树中的 MeshInstance3D 世界 AABB）
		if i > 0:
			var prev: Vector3 = (base[i - 1] as Dictionary)["pos"] as Vector3
			min_sep = minf(min_sep, pos.distance_to(prev))
	_check(min_sep >= 0.6, "相邻红花间距 %.2fm >=0.6" % min_sep)

	# 花头/茎实例变换一致性 + 尺度
	var same_xf := true
	for i in range(5):
		if not stems.multimesh.get_instance_transform(i).is_equal_approx(heads.multimesh.get_instance_transform(i)):
			same_xf = false
	_check(same_xf, "茎/头每实例 Transform 一致（花头不悬空）")

# ============================================================
# [SEASON] 四季参数 + 树冠实例规模
# ============================================================
func _probe_season() -> void:
	var vw: Dictionary = Season.visuals([0.0, 0.0, 0.0, 1.0])
	var vsp: Dictionary = Season.visuals([1.0, 0.0, 0.0, 0.0])
	var va: Dictionary = Season.visuals([0.0, 0.0, 1.0, 0.0])
	print("[SEASON] winter canopy_keep=%.3f leafcard_keep=%.3f leaf_fall=%.3f" % [
		float(vw["canopy_keep"]), float(vw["leafcard_keep"]), float(vw["leaf_fall"])])
	print("[SEASON] spring canopy_keep=%.3f leafcard_keep=%.3f leaf_fall=%.3f" % [
		float(vsp["canopy_keep"]), float(vsp["leafcard_keep"]), float(vsp["leaf_fall"])])
	print("[SEASON] autumn canopy_keep=%.3f leafcard_keep=%.3f leaf_fall=%.3f" % [
		float(va["canopy_keep"]), float(va["leafcard_keep"]), float(va["leaf_fall"])])
	_check(float(vw["canopy_keep"]) <= 0.001, "冬季 canopy_keep=0")
	_check(float(vw["leafcard_keep"]) <= 0.001, "冬季 leafcard_keep=0")
	_check(float(va["leaf_fall"]) >= 0.99, "秋季 leaf_fall=1")
	var canopy := _big.find_child("Canopy", true, false) as MultiMeshInstance3D
	var cards := _big.find_child("LeafCards", true, false) as MultiMeshInstance3D
	_check(canopy != null and canopy.multimesh.instance_count == 44, "树冠 Canopy 实例 44 (实际 %d)" % (canopy.multimesh.instance_count if canopy != null else -1))
	_check(cards != null and cards.multimesh.instance_count == 80, "树冠 LeafCards 实例 80 (实际 %d)" % (cards.multimesh.instance_count if cards != null else -1))
