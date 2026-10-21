extends SceneTree
## P7-V2 task-2 验收探针（headless，不加载 isle.tscn、不开窗口）：
##   D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe --headless --path D:/休闲小岛幻境/游戏工程 --script res://tools/probe_p7v2_perch.gd
## 覆盖（全部基于真实构建出来的网格几何，不看源码常量）：
##   [COUNTS]  world 栖枝 16 旧 + 6 lamp = 22；cottage 10 旧 + 4 porch_rail = 14；
##             旧栖枝字典契约保持不变（world 旧 16 点仍 5 键，cottage 旧 10 点无 slots）
##   [RAIL]    cottage 4 个 porch_rail：找到真实侧/前扶手 BoxMesh，pos 距真实顶面 0.03（±1mm），
##             落点在扶手顶面矩形与立柱间自由段内，最近下方实体表面就是扶手顶面（不悬空），
##             facing 沿扶手方向（侧栏局部 +Z、前栏局部 +X）、normal=UP、slope=0、slots=1，
##             脚点/鸟体/腿趾采样不落入任何 cottage 实体 AABB
##   [LAMP]    world 6 个 lamp：找到真实灯帽 CylinderMesh（top_r 0.13 / bottom_r 0.17 / h 0.06），
##             pos 距真实灯帽顶面 0.03，局部坐标 = (0.42, 2.21, 0.105)，水平落在灯帽顶面 r=0.13 内，
##             最近下方实体表面就是灯帽顶面，facing = 横臂朝路方向、normal=UP、slope=0、slots=1，
##             脚点/鸟体包围采样不穿模（脚点与吊杆水平净空 >= 0.05）
##   [FX]      fx.gd 归一化接受全部 36 个栖点（新 kind 不被丢弃）、slots=1 保持；
##             debug_force_perch 把鸟分别放到 porch_rail / lamp 后，夜间 update_birds 仍停栖在真实灯帽/扶手上，
##             脚点 = perch.pos + normal*0.02（idle 轻跳只允许沿法线向上偏移），无槽位冲突
## 退出码：0 = 全部断言通过。

const World := preload("res://scripts/world.gd")
const Cottage := preload("res://scripts/cottage.gd")

const DT := 1.0 / 60.0
const GAP := 0.03            # 栖点相对真实支撑面顶面的脚部间隙（验收 0.02~0.03）
const FOOT_LIFT := 0.02      # fx.PERCH_FOOT_LIFT：鸟节点原点（脚底）沿法线抬起量
const EPS := 0.001
const BIRD_COUNT := 10
const STATE_PERCH := 3

var _pass := 0
var _fail := 0
var _island: Dictionary = {}
var _cottage: Dictionary = {}
var _world_root: Node3D = null
var _cot_root: Node3D = null
var _cot_aabbs: Array = []
var _legs_aabb: AABB = AABB()
var _legs_mesh: ArrayMesh = null
var _fx_script: GDScript = null
var _fx_ok := false
var _support: Dictionary = {}   # perch id -> {kind, support_top, gap, pos, facing, normal, slope, slots, foot}

func _initialize() -> void:
	print("=== P7-V2 PERCH PROBE START ===")
	await process_frame
	var world_holder := Node3D.new()
	world_holder.name = "PerchProbeWorld"
	get_root().add_child(world_holder)
	_island = World.build(world_holder)
	await process_frame
	var cot_holder := Node3D.new()
	cot_holder.name = "PerchProbeCottage"
	get_root().add_child(cot_holder)
	_cottage = Cottage.build(cot_holder)
	await process_frame
	_world_root = _island["root"] as Node3D
	_cot_root = _cottage["root"] as Node3D
	var wp: Array = (_island["perches"] as Array).duplicate()
	var cp: Array = (_cottage["perches"] as Array).duplicate()
	print("[LOAD] world_perches=", wp.size(), " cottage_perches=", cp.size())
	_cot_aabbs = _aabb_entries(_all_geometry(_cot_root))
	_fx_script = load("res://scripts/fx.gd") as GDScript
	_fx_ok = _fx_script != null
	if _fx_ok:
		_legs_mesh = _fx_script._gull_legs_mesh()
		_legs_aabb = _legs_mesh.get_aabb()
	print("[LOAD] cottage_geometry_aabbs=", _cot_aabbs.size(), " fx_ok=", _fx_ok, " gull_legs_aabb=", _legs_aabb)
	_probe_counts(wp, cp)
	_probe_rails(cp)
	_probe_lamps(wp)
	_probe_global(wp, cp)
	_probe_fx(wp, cp)
	_print_new_points(wp, cp)
	world_holder.free()
	cot_holder.free()
	print("=== P7-V2 PERCH PROBE RESULT: ", "PASS" if _fail == 0 else "FAIL", " pass=", _pass, " fail=", _fail, " ===")
	quit(0 if _fail == 0 else 1)

func _check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("  [OK] ", msg)
	else:
		_fail += 1
		print("  [FAIL] ", msg)

# ============================================================
# 基础几何工具：AABB 采样 / 文字格式化
# ============================================================
func _fmtv(v: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [v.x, v.y, v.z]

func _all_geometry(node: Node) -> Array:
	var out: Array = []
	var stack: Array = [node]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		for c in cur.get_children():
			if c is GeometryInstance3D:
				out.append(c)
			stack.append(c)
	return out

func _world_aabb(gi: GeometryInstance3D) -> AABB:
	var local := AABB()
	if gi is MeshInstance3D:
		var mi: MeshInstance3D = gi
		if mi.mesh == null:
			return AABB()
		local = mi.mesh.get_aabb()
	elif gi is MultiMeshInstance3D:
		local = (gi as MultiMeshInstance3D).get_aabb()
	else:
		return AABB()
	if local.size.x <= 0.0 or local.size.y <= 0.0 or local.size.z <= 0.0:
		return AABB()
	return gi.global_transform * local

func _aabb_entries(geoms: Array) -> Array:
	var out: Array = []
	for gi_v in geoms:
		var gi: GeometryInstance3D = gi_v
		var aabb: AABB = _world_aabb(gi)
		if aabb.size == Vector3.ZERO:
			continue
		out.append({"name": String(gi.name), "aabb": aabb})
	return out

func _contains_xz(aabb: AABB, p: Vector3) -> bool:
	return (p.x >= aabb.position.x - 1e-6 and p.x <= aabb.position.x + aabb.size.x + 1e-6
		and p.z >= aabb.position.z - 1e-6 and p.z <= aabb.position.z + aabb.size.z + 1e-6)

func _aabb_point_dist(aabb: AABB, p: Vector3) -> float:
	var dx: float = maxf(aabb.position.x - p.x, maxf(0.0, p.x - (aabb.position.x + aabb.size.x)))
	var dy: float = maxf(aabb.position.y - p.y, maxf(0.0, p.y - (aabb.position.y + aabb.size.y)))
	var dz: float = maxf(aabb.position.z - p.z, maxf(0.0, p.z - (aabb.position.z + aabb.size.z)))
	return sqrt(dx * dx + dy * dy + dz * dz)

func _clearance(entries: Array, points: Array) -> Dictionary:
	var hits: Array = []
	var min_clear := 1.0e9
	for p_v in points:
		var p: Vector3 = p_v
		for e_v in entries:
			var e: Dictionary = e_v
			var aabb: AABB = e["aabb"]
			if aabb.has_point(p):
				if not hits.has(String(e["name"])):
					hits.append(String(e["name"]))
			min_clear = minf(min_clear, _aabb_point_dist(aabb, p))
	return {"hits": hits, "min_clear": min_clear}

## 精确（绕 Y 旋转不被 AABB 膨胀）的网格净空：把点变换到每个网格实例局部空间再用网格 AABB 距离，
## 对轴对齐 BoxMesh/CylinderMesh 等价于点到真实盒/圆柱包围盒的距离；路灯节点带 yaw，必须这样做。
func _clearance_local(geoms: Array, points: Array) -> Dictionary:
	var hits: Array = []
	var min_clear := 1.0e9
	for gi_v in geoms:
		var gi: GeometryInstance3D = gi_v
		var local := AABB()
		if gi is MeshInstance3D:
			var mi: MeshInstance3D = gi
			if mi.mesh == null:
				continue
			local = mi.mesh.get_aabb()
		elif gi is MultiMeshInstance3D:
			local = (gi as MultiMeshInstance3D).get_aabb()
		else:
			continue
		if local.size == Vector3.ZERO:
			continue
		var inv: Transform3D = gi.global_transform.affine_inverse()
		for p_v in points:
			var p: Vector3 = p_v
			var lp2: Vector3 = inv * p
			if local.has_point(lp2):
				if not hits.has(String(gi.name)):
					hits.append(String(gi.name))
			min_clear = minf(min_clear, _aabb_point_dist(local, lp2))
	return {"hits": hits, "min_clear": min_clear}

func _nearest_top_below(entries: Array, p: Vector3, limit_y: float) -> Dictionary:
	var best_top := -1.0e9
	var best_name := ""
	for e_v in entries:
		var e: Dictionary = e_v
		var aabb: AABB = e["aabb"]
		if not _contains_xz(aabb, p):
			continue
		var top: float = aabb.position.y + aabb.size.y
		if top <= limit_y and top > best_top:
			best_top = top
			best_name = String(e["name"])
	return {"top": best_top, "name": best_name}

## 海鸥体包围采样（与 fx.gd _make_bird 的真实网格尺寸一致：原点=脚底，+Z 前向，+Y 上）：
## body 椭球中心 (0,0.200,0) r(0.086,0.082,0.180)；head 椭球中心 (0,0.262,0.150) r(0.062,0.060,0.066)；
## 尾尖 (0,0.196,-0.235)。用 16x9 + 10x6 采样近似椭球表面，检查是否与实体 AABB 相交（保守检测）。
func _bird_points(foot: Vector3, n: Vector3, facing: Vector3) -> Array:
	var out: Array = []
	var up: Vector3 = n.normalized()
	var fwd: Vector3 = facing
	fwd.y = 0.0
	if fwd.length_squared() < 0.000001:
		fwd = Vector3(0.0, 0.0, 1.0)
	fwd = (fwd - up * up.dot(fwd))
	if fwd.length_squared() < 0.000001:
		fwd = Vector3(0.0, 0.0, 1.0)
	fwd = fwd.normalized()
	var right: Vector3 = up.cross(fwd).normalized()
	var bc: Vector3 = foot + up * 0.200
	for it in range(16):
		var th: float = TAU * float(it) / 16.0
		for ip in range(9):
			var ph: float = PI * float(ip) / 8.0
			var o := Vector3(0.086 * sin(ph) * cos(th), 0.082 * cos(ph), 0.180 * sin(ph) * sin(th))
			out.append(bc + right * o.x + up * o.y + fwd * o.z)
	var hc: Vector3 = foot + up * 0.262 + fwd * 0.150
	for it2 in range(10):
		var th2: float = TAU * float(it2) / 10.0
		for ip2 in range(6):
			var ph2: float = PI * float(ip2) / 5.0
			var o2 := Vector3(0.062 * sin(ph2) * cos(th2), 0.060 * cos(ph2), 0.066 * sin(ph2) * sin(th2))
			out.append(hc + right * o2.x + up * o2.y + fwd * o2.z)
	out.append(foot + up * 0.196 - fwd * 0.235)
	return out

## 海鸥腿/趾的真实网格顶点（fx._gull_legs_mesh 的 ArrayMesh 顶点），按鸟基（脚底原点、+Y=normal、
## +Z=facing）变换到世界：这是比体包围更贴近承载面的部位（站立时腿在 y=0.004..0.123，脚趾前伸到 z≈0.08，
## 侧向趾尖 x≈±0.057）。用真实顶点避免 AABB 角点虚构导致净空被低估。
func _leg_points(foot: Vector3, n: Vector3, facing: Vector3) -> Array:
	var out: Array = []
	var up: Vector3 = n.normalized()
	var fwd: Vector3 = facing
	fwd.y = 0.0
	if fwd.length_squared() < 0.000001:
		fwd = Vector3(0.0, 0.0, 1.0)
	fwd = (fwd - up * up.dot(fwd))
	if fwd.length_squared() < 0.000001:
		fwd = Vector3(0.0, 0.0, 1.0)
	fwd = fwd.normalized()
	var right: Vector3 = up.cross(fwd).normalized()
	if _legs_mesh == null or _legs_mesh.get_surface_count() <= 0:
		return out
	var arrays: Array = _legs_mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for v in verts:
		out.append(foot + right * v.x + up * v.y + fwd * v.z)
	return out

func _kind_counts(perches: Array) -> Dictionary:
	var out: Dictionary = {}
	for p_v in perches:
		var p: Dictionary = p_v
		var k: String = String(p.get("kind", "?"))
		out[k] = int(out.get(k, 0)) + 1
	return out

func _has_id(perches: Array, pid: String) -> bool:
	for p_v in perches:
		if String((p_v as Dictionary).get("id", "")) == pid:
			return true
	return false

func _find_perch(perches: Array, pid: String) -> Dictionary:
	for p_v in perches:
		var p: Dictionary = p_v
		if String(p.get("id", "")) == pid:
			return p
	return {}

# ============================================================
# 1) 数量 / 旧契约
# ============================================================
func _probe_counts(wp: Array, cp: Array) -> void:
	print("--- COUNTS / CONTRACT ---")
	var wk: Dictionary = _kind_counts(wp)
	var ck: Dictionary = _kind_counts(cp)
	print("[KINDS] world=", wk, " cottage=", ck)
	_check(wp.size() == 22, "world 栖枝数 == 16 旧 + 6 lamp = 22（实际 %d）" % wp.size())
	_check(cp.size() == 14, "cottage 栖枝数 == 10 旧 + 4 porch_rail = 14（实际 %d）" % cp.size())
	_check(int(wk.get("lamp", 0)) == 6, "world 新增 kind=lamp ×6（实际 %d）" % int(wk.get("lamp", 0)))
	_check(int(ck.get("porch_rail", 0)) == 4, "cottage 新增 kind=porch_rail ×4（实际 %d）" % int(ck.get("porch_rail", 0)))
	_check(int(wk.get("tree_branch", 0)) == 6 and int(wk.get("lighthouse_platform", 0)) == 4
		and int(wk.get("dock", 0)) == 2 and int(wk.get("garden_post", 0)) == 4,
		"world 旧 16 点 kind 分布不变（树6/灯塔4/码头2/花园4）")
	_check(int(ck.get("ridge", 0)) == 3 and int(ck.get("eave", 0)) == 4
		and int(ck.get("chimney", 0)) == 1 and int(ck.get("porch_beam", 0)) == 2,
		"cottage 旧 10 点 kind 分布不变（屋脊3/屋檐4/烟囱1/门廊梁2）")
	# 旧 world 栖枝字典契约：仍只有 5 键，不把 normal/slope/slots 泄漏给旧点
	var bad_world: Array = []
	for i in range(16):
		var d: Dictionary = wp[i]
		if d.keys().size() != 5:
			bad_world.append("%s keys=%d" % [String(d.get("id", "?")), d.keys().size()])
		for k in ["normal", "slope", "slots"]:
			if d.has(k):
				bad_world.append("%s has %s" % [String(d.get("id", "?")), k])
	_check(bad_world.is_empty(), "world 旧 16 点仍为 5 键契约 {id,pos,facing,radius,kind}（异常 %s）" % str(bad_world))
	# cottage 旧 10 点：有 normal/slope（Phase6 既有行为），无 slots
	var bad_cot: Array = []
	for i in range(10):
		var d2: Dictionary = cp[i]
		if not d2.has("normal") or not d2.has("slope"):
			bad_cot.append("%s missing normal/slope" % String(d2.get("id", "?")))
		if d2.has("slots"):
			bad_cot.append("%s has slots" % String(d2.get("id", "?")))
	_check(bad_cot.is_empty(), "cottage 旧 10 点契约不变（有 normal/slope、无 slots）（异常 %s）" % str(bad_cot))
	# 新点必需键
	var missing_new: Array = []
	for p_v in wp:
		var p: Dictionary = p_v
		if String(p.get("kind", "")) != "lamp":
			continue
		for k2 in ["id", "pos", "facing", "radius", "kind", "normal", "slope", "slots"]:
			if not p.has(k2):
				missing_new.append("lamp/%s missing %s" % [String(p.get("id", "?")), k2])
	for p_v2 in cp:
		var p2: Dictionary = p_v2
		if String(p2.get("kind", "")) != "porch_rail":
			continue
		for k3 in ["id", "pos", "facing", "radius", "kind", "normal", "slope", "slots"]:
			if not p2.has(k3):
				missing_new.append("porch_rail/%s missing %s" % [String(p2.get("id", "?")), k3])
	_check(missing_new.is_empty(), "新栖点包含 normal/slope/slots 显式键（缺失 %s）" % str(missing_new))
	# world.build 返回结构（Lead 要求不变）
	_check(_island.has("perches") and _island.has("lamps") and _island.has("light_sources"),
		"world.build 返回仍含 perches/lamps/light_sources")
	_check((_island["light_sources"] as Array).size() == 8, "light_sources 仍为 8（实际 %d）" % (_island["light_sources"] as Array).size())
	var lamp_struct_ok := true
	for entry_v in (_island["lamps"] as Array):
		if (entry_v as Array).size() != 4:
			lamp_struct_ok = false
	_check(lamp_struct_ok, "lamps 每项仍为 4 元组 [mat, halo, light, info]")

# ============================================================
# 2) cottage 门廊扶手 porch_rail：真实 BoxMesh 顶面
# ============================================================
func _find_box_meshes(node: Node, size: Vector3) -> Array:
	var out: Array = []
	var stack: Array = [node]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		for c in cur.get_children():
			if c is MeshInstance3D:
				var mi: MeshInstance3D = c
				if mi.mesh is BoxMesh:
					var bm: BoxMesh = mi.mesh
					if bm.size.distance_to(size) < EPS:
						out.append(mi)
			stack.append(c)
	return out

func _probe_rails(cp: Array) -> void:
	print("--- PORCH RAILS (cottage real box tops) ---")
	var side_rails: Array = _find_box_meshes(_cot_root, Vector3(0.10, 0.09, 2.60))
	var front_rails: Array = _find_box_meshes(_cot_root, Vector3(2.24, 0.09, 0.10))
	_check(side_rails.size() == 2, "找到 2 条真实侧扶手 BoxMesh(0.10,0.09,2.60)（实际 %d）" % side_rails.size())
	_check(front_rails.size() == 2, "找到 2 条真实前扶手 BoxMesh(2.24,0.09,0.10)（实际 %d）" % front_rails.size())
	var posts: Array = _find_box_meshes(_cot_root, Vector3(0.12, 0.95, 0.12))
	print("[RAIL] post_boxes(0.12,0.95,0.12)=", posts.size())
	var rail_ids: Array = ["porch_rail_L", "porch_rail_R", "porch_rail_FL", "porch_rail_FR"]
	var found_ids: Array = []
	for p_v in cp:
		var p: Dictionary = p_v
		if String(p.get("kind", "")) == "porch_rail":
			found_ids.append(String(p["id"]))
	_check(found_ids.size() == 4, "cottage kind=porch_rail 栖点 4 个（实际 %s）" % str(found_ids))
	for pid in rail_ids:
		var p: Dictionary = _find_perch(cp, pid)
		_check(not p.is_empty(), pid + " 存在")
		if p.is_empty():
			continue
		var pos: Vector3 = p["pos"]
		var facing: Vector3 = p["facing"]
		var n: Vector3 = (p["normal"] as Vector3).normalized()
		var lp: Vector3 = _cot_root.to_local(pos)
		var is_front: bool = pid.begins_with("porch_rail_F")
		var sx: float = signf(lp.x)
		var support: MeshInstance3D = null
		if is_front:
			for mi_v in front_rails:
				var mi: MeshInstance3D = mi_v
				if absf(mi.position.x - sx * 3.00) < EPS and absf(mi.position.z - 6.95) < EPS:
					support = mi
		else:
			for mi2_v in side_rails:
				var mi2: MeshInstance3D = mi2_v
				if absf(mi2.position.x - sx * 4.12) < EPS and absf(mi2.position.z - 5.78) < EPS:
					support = mi2
		_check(support != null, pid + " 找到对应真实扶手网格")
		if support == null:
			continue
		var bm: BoxMesh = support.mesh
		var half: Vector3 = bm.size * 0.5
		var support_top: Vector3 = support.global_transform * Vector3(0.0, half.y, 0.0)
		var gap: float = pos.y - support_top.y
		_check(absf(gap - GAP) <= EPS and gap >= 0.02 and gap <= 0.04,
			pid + " pos 距真实扶手顶面垂直间隙 = %.4f m（要求 0.03±0.001）" % gap)
		# 扶手顶面法线（真实网格变换）
		var face_n: Vector3 = (support.global_transform.basis * Vector3.UP).normalized()
		var n_align: float = rad_to_deg(acos(clampf(n.dot(face_n), -1.0, 1.0)))
		_check(n_align <= 0.1 and n.y > 0.9999, pid + " normal == 扶手顶面法线 UP（偏差 %.3f°）" % n_align)
		_check(absf(float(p["slope"])) <= 1e-6, pid + " slope == 0（实际 %.6f）" % float(p["slope"]))
		# 水平落点：扶手顶面矩形 / 立柱间自由段
		var dloc: Vector3 = lp - support.position
		var in_rect: bool = absf(dloc.x) <= half.x + EPS and absf(dloc.z) <= half.z + EPS
		_check(in_rect, pid + " 落点在扶手顶面矩形内（局部偏移 %s，half=%s）" % [_fmtv(dloc), _fmtv(half)])
		var free_ok: bool
		var free_desc: String
		if is_front:
			free_ok = absf(lp.x) >= 1.94 - EPS and absf(lp.x) <= 4.06 + EPS
			free_desc = "x∈[1.94,4.06]（立柱 x=±1.88/±4.12）"
		else:
			free_ok = lp.z >= 4.66 - EPS and lp.z <= 6.89 + EPS
			free_desc = "z∈[4.66,6.89]（立柱 z=4.60/6.95）"
		_check(free_ok, pid + " 落点在立柱间自由段 %s（local=%s）" % [free_desc, _fmtv(lp)])
		# 朝向：任务契约要求 facing 沿栏杆方向（侧栏局部 +Z，前栏局部 +X）；slots=1 故不会产生槽位横向偏移
		var floc: Vector3 = _cot_root.to_local(pos + facing) - lp
		var facing_ok := false
		if is_front:
			facing_ok = absf(floc.z) <= 1e-3 and floc.x > 0.99
		else:
			facing_ok = absf(floc.x) <= 1e-3 and floc.z > 0.99
		_check(facing_ok, pid + " facing 沿扶手方向（局部 %s，侧栏 +Z / 前栏 +X）" % _fmtv(floc))
		_check(int(p.get("slots", 0)) == 1, pid + " slots == 1（实际 %d）" % int(p.get("slots", 0)))
		_check(float(p["radius"]) >= 0.15 and float(p["radius"]) <= 0.20,
			pid + " radius ∈ [0.15,0.20]（语义半径，实际 %.3f；slots=1 已固定单鸟）" % float(p["radius"]))
		# 脚点 / 鸟体不穿模
		var foot: Vector3 = pos + n * FOOT_LIFT
		var foot_clear: Dictionary = _clearance(_cot_aabbs, [foot])
		_check((foot_clear["hits"] as Array).is_empty(),
			pid + " 脚点不在任何 cottage 实体 AABB 内（命中 %s）" % str(foot_clear["hits"]))
		_check(float(foot_clear["min_clear"]) >= 0.03,
			pid + " 脚点距最近 cottage 实体 >= 0.03（实际 %.4f m）" % float(foot_clear["min_clear"]))
		var bird_clear: Dictionary = _clearance(_cot_aabbs, _bird_points(foot, n, facing))
		_check((bird_clear["hits"] as Array).is_empty(),
			pid + " 海鸥体包围采样不穿 cottage 实体（命中 %s）" % str(bird_clear["hits"]))
		_check(float(bird_clear["min_clear"]) >= 0.02,
			pid + " 海鸥体最近实体净空 >= 0.02（实际 %.4f m）" % float(bird_clear["min_clear"]))
		if _fx_ok:
			var leg_clear: Dictionary = _clearance(_cot_aabbs, _leg_points(foot, n, facing))
			_check((leg_clear["hits"] as Array).is_empty(),
				pid + " 海鸥腿/趾真实网格角点不穿 cottage 实体（命中 %s）" % str(leg_clear["hits"]))
			_check(float(leg_clear["min_clear"]) >= 0.02,
				pid + " 海鸥腿/趾最近实体净空 >= 0.02（实际 %.4f m）" % float(leg_clear["min_clear"]))
		# 最近下方实体表面必须就是扶手顶面（不悬空 / 不架在别的物体上）
		var nb: Dictionary = _nearest_top_below(_cot_aabbs, foot, pos.y - 0.0005)
		_check(absf(float(nb["top"]) - support_top.y) <= 0.002,
			pid + " 最近下方实体顶面就是扶手顶面（最近=%.4f 扶手=%.4f）" % [float(nb["top"]), support_top.y])
		# 距最近栏杆立柱的水平距离（避让立柱）
		var min_post := 1.0e9
		for pm_v in posts:
			var pm: MeshInstance3D = pm_v
			var d2 := Vector2(lp.x - pm.position.x, lp.z - pm.position.z)
			min_post = minf(min_post, d2.length())
		_check(min_post >= 0.30, pid + " 距最近栏杆立柱 %.3f m >= 0.30" % min_post)
		_support[pid] = {"kind": "porch_rail", "support_top": support_top.y, "gap": gap, "pos": pos,
			"facing": facing, "normal": n, "slope": float(p["slope"]), "slots": int(p.get("slots", 0)),
			"foot": foot}

# ============================================================
# 3) world 路灯灯帽 lamp：真实 CylinderMesh 顶面
# ============================================================
func _lamp_parts(node: Node3D) -> Dictionary:
	var out := {"cap": null, "rod": null, "arm": null, "pole": null, "base": null, "meshes": []}
	for c in node.get_children():
		if not (c is MeshInstance3D):
			continue
		var mi: MeshInstance3D = c
		(out["meshes"] as Array).append(mi)
		if mi.mesh is CylinderMesh:
			var cm: CylinderMesh = mi.mesh
			if (absf(cm.top_radius - 0.13) < EPS and absf(cm.bottom_radius - 0.17) < EPS
					and absf(cm.height - 0.06) < EPS and absf(mi.position.y - 2.15) < EPS):
				out["cap"] = mi
			elif absf(cm.top_radius - 0.013) < EPS and absf(cm.height - 0.22) < EPS:
				out["rod"] = mi
			elif absf(cm.height - 2.30) < EPS:
				out["pole"] = mi
		elif mi.mesh is BoxMesh:
			var bm: BoxMesh = mi.mesh
			if bm.size.distance_to(Vector3(0.50, 0.07, 0.07)) < EPS:
				out["arm"] = mi
			elif bm.size.distance_to(Vector3(0.44, 0.14, 0.44)) < EPS:
				out["base"] = mi
	return out

func _probe_lamps(wp: Array) -> void:
	print("--- LAMPS (world real hood tops) ---")
	var lamps: Array = _island["lamps"]
	_check(lamps.size() == 6, "world 路灯数 == 6（实际 %d）" % lamps.size())
	var lamp_perches: Dictionary = {}
	for p_v in wp:
		var p: Dictionary = p_v
		if String(p.get("kind", "")) == "lamp":
			lamp_perches[String(p["id"])] = p
	_check(lamp_perches.size() == 6, "kind=lamp 栖点 6 个（实际 %d）" % lamp_perches.size())
	var name_to_node: Dictionary = {}
	for c in _world_root.get_children():
		name_to_node[String(c.name)] = c
	for i in range(lamps.size()):
		var entry: Array = lamps[i]
		var info: Dictionary = entry[3]
		var lname: String = String(info["name"])
		var node: Node3D = name_to_node.get(lname, null) as Node3D
		_check(node != null, "%s 在 world 场景树中找到（真实灯节点）" % lname)
		if node == null:
			continue
		var pid: String = "lamp_%d" % i
		var p: Dictionary = lamp_perches.get(pid, {})
		_check(not p.is_empty(), pid + " 存在（对应 %s）" % lname)
		if p.is_empty():
			continue
		var parts: Dictionary = _lamp_parts(node)
		var cap: MeshInstance3D = parts["cap"]
		_check(cap != null, "%s 找到真实灯帽 CylinderMesh(top 0.13/bottom 0.17/h 0.06, y 2.15)" % lname)
		_check(parts["arm"] != null and parts["rod"] != null and parts["pole"] != null and parts["base"] != null,
			"%s 横臂/吊杆/灯柱/底座网格齐全（%d 个网格）" % [lname, (parts["meshes"] as Array).size()])
		_check(absf(node.rotation.x) < 1e-5 and absf(node.rotation.z) < 1e-5,
			"%s 灯节点只有 yaw 旋转（x=%.6f z=%.6f）" % [lname, node.rotation.x, node.rotation.z])
		if cap == null:
			continue
		var cm: CylinderMesh = cap.mesh
		var cap_top: Vector3 = cap.global_transform * Vector3(0.0, cm.height * 0.5, 0.0)
		var node_cap_top: Vector3 = node.to_global(Vector3(0.42, 2.18, 0.0))
		_check(cap_top.distance_to(node_cap_top) <= 0.002,
			"%s 真实灯帽顶面中心 = 灯节点局部 (0.42,2.18,0)（误差 %.4f m）" % [lname, cap_top.distance_to(node_cap_top)])
		var info_base: Vector3 = info["base"]
		var info_face: Vector3 = info["facing"]
		_check(node.position.distance_to(info_base) <= EPS, "%s info.base == 灯节点世界位置" % lname)
		var face_h: Vector3 = Vector3(info_face.x, 0.0, info_face.z)
		if face_h.length_squared() < 0.000001:
			face_h = Vector3(1.0, 0.0, 0.0)
		face_h = face_h.normalized()
		var expect_cap_top: Vector3 = info_base + face_h * 0.42 + Vector3.UP * 2.18
		_check(expect_cap_top.distance_to(cap_top) <= 0.002,
			"%s 灯帽顶面 == base + facing*0.42 + UP*2.18（误差 %.4f m）" % [lname, expect_cap_top.distance_to(cap_top)])
		var pos: Vector3 = p["pos"]
		var facing: Vector3 = p["facing"]
		var n: Vector3 = (p["normal"] as Vector3).normalized()
		var gap: float = pos.y - cap_top.y
		_check(absf(gap - GAP) <= EPS and gap >= 0.02 and gap <= 0.04,
			pid + " pos 距真实灯帽顶面垂直间隙 = %.4f m（要求 0.03±0.001）" % gap)
		var lpos: Vector3 = node.to_local(pos)
		var expect_lpos := Vector3(0.42, 2.21, 0.105)
		var lpos_err: Vector3 = lpos - expect_lpos
		_check(absf(lpos_err.x) <= 0.002 and absf(lpos_err.y) <= 0.002 and absf(lpos_err.z) <= 0.002,
			pid + " 灯节点局部坐标 = (0.42,2.21,0.105)（实际 %s）" % _fmtv(lpos))
		var hoff: float = Vector2(pos.x - cap_top.x, pos.z - cap_top.z).length()
		_check(absf(hoff - 0.105) <= 0.002, pid + " 水平偏离灯帽中心 0.105 m（实际 %.4f）" % hoff)
		_check(hoff + 0.02 <= 0.13, pid + " 落脚点留出 0.02 m 边缘余量后仍在灯帽顶面 r=0.13 内（实际 %.4f）" % hoff)
		var f_align: float = rad_to_deg(acos(clampf(facing.dot(face_h), -1.0, 1.0)))
		_check(f_align <= 0.1, pid + " facing == 横臂朝路方向（偏差 %.3f°）" % f_align)
		_check(n.y > 0.9999, pid + " normal == UP（%s）" % _fmtv(n))
		_check(absf(float(p["slope"])) <= 1e-6, pid + " slope == 0（实际 %.6f）" % float(p["slope"]))
		_check(int(p.get("slots", 0)) == 1, pid + " slots == 1（实际 %d）" % int(p.get("slots", 0)))
		var lr: float = float(p["radius"])
		_check(lr > 0.0 and lr <= 0.25, pid + " radius ∈ (0,0.25]（实际 %.3f）" % lr)
		if parts["arm"] == null or parts["rod"] == null:
			continue
		var lamp_entries: Array = _aabb_entries(parts["meshes"])
		var foot: Vector3 = pos + n * FOOT_LIFT
		var foot_clear2: Dictionary = _clearance_local(parts["meshes"], [foot])
		_check((foot_clear2["hits"] as Array).is_empty(),
			pid + " 脚点不穿灯体网格（命中 %s）" % str(foot_clear2["hits"]))
		_check(float(foot_clear2["min_clear"]) >= 0.03,
			pid + " 脚点距最近灯体网格 >= 0.03（实际 %.4f m）" % float(foot_clear2["min_clear"]))
		var rod_mi: MeshInstance3D = parts["rod"]
		var rod_local: AABB = rod_mi.mesh.get_aabb()
		var rod_lp: Vector3 = rod_mi.global_transform.affine_inverse() * foot
		var hdx: float = maxf(rod_local.position.x - rod_lp.x, maxf(0.0, rod_lp.x - (rod_local.position.x + rod_local.size.x)))
		var hdz: float = maxf(rod_local.position.z - rod_lp.z, maxf(0.0, rod_lp.z - (rod_local.position.z + rod_local.size.z)))
		var hclear: float = sqrt(hdx * hdx + hdz * hdz)
		_check(hclear >= 0.05, pid + " 脚点距吊杆水平净空 %.4f m >= 0.05（鸟不站在杆上）" % hclear)
		var bird_clear2: Dictionary = _clearance_local(parts["meshes"], _bird_points(foot, n, facing))
		_check((bird_clear2["hits"] as Array).is_empty(),
			pid + " 海鸥体包围采样不穿灯体（命中 %s）" % str(bird_clear2["hits"]))
		_check(float(bird_clear2["min_clear"]) >= 0.02,
			pid + " 海鸥体最近灯体净空 >= 0.02（实际 %.4f m）" % float(bird_clear2["min_clear"]))
		if _fx_ok:
			var leg_pts: Array = _leg_points(foot, n, facing)
			var leg_clear2: Dictionary = _clearance_local(parts["meshes"], leg_pts)
			_check((leg_clear2["hits"] as Array).is_empty(),
				pid + " 海鸥腿/趾真实网格角点不穿灯体（命中 %s）" % str(leg_clear2["hits"]))
			_check(float(leg_clear2["min_clear"]) >= 0.02,
				pid + " 海鸥腿/趾最近灯体净空 >= 0.02（实际 %.4f m）" % float(leg_clear2["min_clear"]))
			var toe_reach := 0.0
			for lp_v in leg_pts:
				var lp2: Vector3 = lp_v
				toe_reach = maxf(toe_reach, Vector2(lp2.x - cap_top.x, lp2.z - cap_top.z).length())
			print("[LAMP] %s foot_side=%.4f rod_horizontal_clear=%.4f body_min_clear=%.4f legs_min_clear=%.4f toe_reach_from_cap_center=%.4f (cap_top_r=0.13, toe_y=%.4f above cap plane)" % [
				pid, hoff, hclear, float(bird_clear2["min_clear"]), float(leg_clear2["min_clear"]),
				toe_reach, (foot.y + _legs_aabb.position.y) - cap_top.y])
			_check(toe_reach <= 0.20,
				pid + " 腿趾足迹半径 <= 0.20（实际 %.4f，灯帽顶面 r=0.13，趾尖在帽面上方 %.3f m，轻微外探属正常站边缘）" % [
					toe_reach, (foot.y + _legs_aabb.position.y) - cap_top.y])
		var nb2: Dictionary = _nearest_top_below(lamp_entries, foot, pos.y - 0.0005)
		_check(absf(float(nb2["top"]) - cap_top.y) <= 0.002,
			pid + " 最近下方实体顶面就是灯帽顶面（最近=%.4f 灯帽=%.4f）" % [float(nb2["top"]), cap_top.y])
		_support[pid] = {"kind": "lamp", "support_top": cap_top.y, "gap": gap, "pos": pos,
			"facing": facing, "normal": n, "slope": float(p["slope"]), "slots": int(p.get("slots", 0)),
			"foot": foot}

# ============================================================
# 4) 合并：id 全局唯一 / 有限值
# ============================================================
func _probe_global(wp: Array, cp: Array) -> void:
	print("--- MERGED (world + cottage) ---")
	var merged: Array = []
	merged.append_array(wp)
	merged.append_array(cp)
	_check(merged.size() == 36, "合并栖点 22 + 14 = 36（实际 %d）" % merged.size())
	var seen: Dictionary = {}
	var dup: Array = []
	var bad_finite: Array = []
	var new_count := 0
	for p_v in merged:
		var p: Dictionary = p_v
		var pid: String = String(p.get("id", ""))
		if seen.has(pid):
			dup.append(pid)
		seen[pid] = true
		var pos: Vector3 = p["pos"]
		var facing: Vector3 = p["facing"]
		# legacy world 栖点无 normal 键（fx 缺省 UP）；新点必须有真实 normal
		var n: Vector3 = p.get("normal", Vector3.UP) as Vector3
		if not (is_finite(pos.x) and is_finite(pos.y) and is_finite(pos.z)
				and is_finite(facing.x) and is_finite(facing.y) and is_finite(facing.z)
				and is_finite(n.x) and is_finite(n.y) and is_finite(n.z)):
			bad_finite.append(pid)
		var k: String = String(p.get("kind", ""))
		if k == "lamp" or k == "porch_rail":
			new_count += 1
			var nn: Vector3 = n.normalized()
			if absf(nn.length() - 1.0) > 1e-4 or nn.y < 0.9999:
				bad_finite.append(pid + "(normal)")
	_check(dup.is_empty(), "合并后 id 全局唯一（重复 %s）" % str(dup))
	_check(bad_finite.is_empty(), "所有栖点坐标/朝向/法线有限且新点 normal=UP（异常 %s）" % str(bad_finite))
	_check(new_count == 10, "新栖点共 10 个（4 porch_rail + 6 lamp，实际 %d）" % new_count)

# ============================================================
# 5) fx.gd 真实消费：归一化 + 强制停栖 + 夜间 update_birds
# ============================================================
func _probe_fx(wp: Array, cp: Array) -> void:
	print("--- FX INTEGRATION ---")
	if not _fx_ok:
		_fx_script = load("res://scripts/fx.gd") as GDScript
		_fx_ok = _fx_script != null
		if _fx_ok:
			_legs_mesh = _fx_script._gull_legs_mesh()
			_legs_aabb = _legs_mesh.get_aabb()
	_check(_fx_ok, "fx.gd 当前工作树可解析（腿/趾真实网格 + BirdFlock 可用；队友编辑期间此断言会失败）")
	if not _fx_ok:
		return
	var merged: Array = []
	merged.append_array(wp)
	merged.append_array(cp)
	var flock = _fx_script.BirdFlock.new()
	get_root().add_child(flock)
	flock.setup(merged)
	var norm: Array = flock.get_perches()
	_check(norm.size() == merged.size(), "fx _normalize_perches 接受全部 36 点（%d vs %d）" % [norm.size(), merged.size()])
	var by_id: Dictionary = {}
	for p_v in norm:
		var p: Dictionary = p_v
		by_id[String(p["id"])] = p
	var missing: Array = []
	var bad_slots: Array = []
	for p_v2 in merged:
		var p2: Dictionary = p_v2
		var pid: String = String(p2["id"])
		if not by_id.has(pid):
			missing.append(pid)
			continue
		var np: Dictionary = by_id[pid]
		if String(p2["kind"]) == "lamp" or String(p2["kind"]) == "porch_rail":
			if int(np["slots"]) != 1:
				bad_slots.append("%s=%d" % [pid, int(np["slots"])])
	_check(missing.is_empty(), "fx 未丢弃任何新栖点（缺失 %s）" % str(missing))
	_check(bad_slots.is_empty(), "新栖点在 fx 中 slots 保持 1（异常 %s）" % str(bad_slots))
	var st: Dictionary = flock.debug_perch_stats()
	print("[FX] perch_count=", int(st["perch_count"]), " total_slots=", int(st["total_slots"]),
		" zones=", st["zones"], " perched=", int(st["perched"]))
	_check(int(st["perch_count"]) == 36, "fx 统计 perch_count == 36（实际 %d）" % int(st["perch_count"]))
	_check(int(st["total_slots"]) == 36, "fx 统计 total_slots == 36（实际 %d）" % int(st["total_slots"]))
	var zones: Dictionary = st["zones"]
	_check(int(zones.get("porch", 0)) == 6, "fx zone 归类 porch == 6（4 porch_rail + 2 porch_beam，实际 %d）" % int(zones.get("porch", 0)))
	_check(int(zones.get("lamp", 0)) == 6, "fx zone 归类 lamp == 6（实际 %d）" % int(zones.get("lamp", 0)))
	_check(int(zones.get("roof", 0)) == 8, "fx zone 归类 roof == 8（实际 %d）" % int(zones.get("roof", 0)))
	# 新 kind 在白天/夜间都可用（烟囱禁停只作用于 chimney）
	var avail_day: Array = flock.debug_perch_availability(-1.0, 30.0, false)
	var avail_night: Array = flock.debug_perch_availability(-1.0, -20.0, true)
	var elig_bad: Array = []
	var avail_map: Dictionary = {}
	for a_v in avail_day:
		var a: Dictionary = a_v
		avail_map[String(a["id"])] = a
	for pid2 in ["porch_rail_L", "porch_rail_R", "porch_rail_FL", "porch_rail_FR", "lamp_0", "lamp_1", "lamp_2", "lamp_3", "lamp_4", "lamp_5"]:
		var a2: Dictionary = avail_map.get(pid2, {})
		if a2.is_empty() or not bool(a2.get("eligible", false)):
			elig_bad.append("day:%s" % pid2)
	for a3_v in avail_night:
		var a3: Dictionary = a3_v
		var pid3: String = String(a3["id"])
		if (pid3.begins_with("porch_rail") or pid3.begins_with("lamp_")) and not bool(a3.get("eligible", false)):
			elig_bad.append("night:%s" % pid3)
	_check(elig_bad.is_empty(), "新栖点在 fx 白天/夜间均 eligible（异常 %s）" % str(elig_bad))
	# 强制把 0 号鸟放到 porch_rail、1 号鸟放到 lamp
	var forced: Array = []
	var rail_id := ""
	for pid4 in ["porch_rail_L", "porch_rail_R", "porch_rail_FL", "porch_rail_FR"]:
		if flock.debug_force_perch(0, pid4):
			rail_id = pid4
			break
	var lamp_id := ""
	for pid5 in ["lamp_0", "lamp_1", "lamp_2", "lamp_3", "lamp_4", "lamp_5"]:
		if flock.debug_force_perch(1, pid5):
			lamp_id = pid5
			break
	_check(rail_id != "", "fx debug_force_perch 把 0 号鸟停到 porch_rail 上（%s）" % rail_id)
	_check(lamp_id != "", "fx debug_force_perch 把 1 号鸟停到 lamp 上（%s）" % lamp_id)
	var birds: Array = flock.get("_birds")
	var check_items: Array = []
	if rail_id != "":
		check_items.append({"bird": birds[0], "id": rail_id})
	if lamp_id != "":
		check_items.append({"bird": birds[1], "id": lamp_id})
	for item_v in check_items:
		var item: Dictionary = item_v
		var b: Dictionary = item["bird"]
		var pid6: String = String(item["id"])
		var np2: Dictionary = by_id[pid6]
		var pos2: Vector3 = np2["pos"]
		var n2: Vector3 = (_support[pid6]["normal"] as Vector3)
		var want_foot: Vector3 = pos2 + n2 * FOOT_LIFT
		var node: Node3D = b["node"]
		_check(int(b["state"]) == STATE_PERCH and String(b["perch_id"]) == pid6,
			"%s 上鸟状态 PERCH 且 perch_id 正确" % pid6)
		_check(node.position.distance_to(want_foot) <= EPS,
			"%s 上鸟脚点 == perch.pos + normal*0.02（误差 %.4f m）" % [pid6, node.position.distance_to(want_foot)])
		var up_align: float = rad_to_deg(acos(clampf((node.basis.y.normalized()).dot(n2), -1.0, 1.0)))
		_check(up_align <= 0.1, "%s 上鸟身体 up 对齐 normal（偏差 %.3f°）" % [pid6, up_align])
	# 夜间 update_birds：鸟必须继续停在真实扶手/灯帽上
	for f in range(90):
		flock.update_birds(DT, -10.0)
	var st2: Dictionary = flock.debug_perch_stats()
	# debug_perch_stats 没有 conflicts 字段：直接用 snapshot + availability 计算槽位互斥/合法性
	var conflicts: Array = []
	var slot_seen: Dictionary = {}
	for s_v in flock.debug_snapshot():
		var s2: Dictionary = s_v
		if int(s2["state"]) != STATE_PERCH:
			continue
		var spid: String = String(s2["perch_id"])
		var sslot: int = int(s2["perch_slot"])
		var key2: String = "%s:%d" % [spid, sslot]
		if slot_seen.has(key2):
			conflicts.append("dup_slot:" + key2)
		slot_seen[key2] = true
		var ps: Dictionary = flock._find_perch(spid)
		if ps.is_empty() or sslot < 0 or sslot >= int(ps["slots"]):
			conflicts.append("bad_slot:%s:%d" % [spid, sslot])
	for a4_v in (st2.get("perches", []) as Array):
		var a4: Dictionary = a4_v
		if int(a4["slots_free"]) < 0 or int(a4["slots_free"]) > int(a4["slots"]):
			conflicts.append("bad_free:%s" % String(a4["id"]))
	if int(st2["used_slots"]) > int(st2["total_slots"]):
		conflicts.append("used>total:%d>%d" % [int(st2["used_slots"]), int(st2["total_slots"])])
	if int(st2["perch_count"]) != norm.size():
		conflicts.append("perch_count:%d!=%d" % [int(st2["perch_count"]), norm.size()])
	print("[FX] after 90 frames: perched=", int(st2["perched"]), " used_slots=", int(st2["used_slots"]), "/", int(st2["total_slots"]), " conflicts=", str(conflicts))
	_check(conflicts.is_empty(), "fx 栖点槽位无冲突（每槽<=1鸟、slot 合法、free>=0、perch_count 一致，实际 %s）" % str(conflicts))
	var idle_states: Array = flock.debug_idle_state()
	var bad_after: Array = []
	var zone_ok := true
	for item2_v in check_items:
		var item2: Dictionary = item2_v
		var b2: Dictionary = item2["bird"]
		var pid7: String = String(item2["id"])
		var np3: Dictionary = by_id[pid7]
		var support: Dictionary = _support[pid7]
		var node2: Node3D = b2["node"]
		var want2: Vector3 = (np3["pos"] as Vector3) + (support["normal"] as Vector3) * FOOT_LIFT
		var drift := Vector2(node2.position.x - want2.x, node2.position.z - want2.z).length()
		var dy: float = node2.position.y - want2.y
		if drift > 0.01 or dy < -0.01 or dy > 0.15 or int(b2["state"]) != STATE_PERCH or String(b2["perch_id"]) != pid7:
			bad_after.append("%s drift=%.4f dy=%.4f state=%d id=%s" % [pid7, drift, dy, int(b2["state"]), String(b2["perch_id"])])
		var footgap: float = node2.position.y - support["support_top"]
		if footgap < 0.04 or footgap > 0.20:
			bad_after.append("%s footgap=%.4f" % [pid7, footgap])
		print("[FX] %s after: node=%s footgap_to_support=%.4f m drift=%.4f dy=%.4f" % [
			pid7, _fmtv(node2.position), footgap, drift, dy])
	_check(bad_after.is_empty(), "夜间 90 帧后鸟仍稳定停在扶手/灯帽上、无悬空/下陷/槽位漂移（异常 %s）" % str(bad_after))
	# debug_idle_state 的 zone 归类（porch / lamp）
	var zone_by_index: Dictionary = {}
	for z_v in idle_states:
		var z: Dictionary = z_v
		zone_by_index[int(z["index"])] = String(z.get("perch_zone", ""))
	if rail_id != "":
		zone_ok = zone_ok and String(zone_by_index.get(0, "")) == "porch"
	if lamp_id != "":
		zone_ok = zone_ok and String(zone_by_index.get(1, "")) == "lamp"
	_check(zone_ok, "fx 把 porch_rail/lamp 鸟归类到 porch/lamp zone（实际 0=%s 1=%s）" % [
		String(zone_by_index.get(0, "?")), String(zone_by_index.get(1, "?"))])
	# 每个新栖点 slots=1 时 _slot_position(perch,0) 必须就是 pos+normal*0.02
	var slot_bad: Array = []
	for p_v3 in norm:
		var p3: Dictionary = p_v3
		var pid8: String = String(p3["id"])
		if not (pid8.begins_with("porch_rail") or pid8.begins_with("lamp_")):
			continue
		var slotpos: Vector3 = flock.call("_slot_position", p3, 0)
		var want3: Vector3 = (p3["pos"] as Vector3) + (p3["normal"] as Vector3).normalized() * FOOT_LIFT
		if slotpos.distance_to(want3) > EPS:
			slot_bad.append("%s d=%.4f" % [pid8, slotpos.distance_to(want3)])
	_check(slot_bad.is_empty(), "fx _slot_position(perch,0) == perch.pos + normal*0.02（异常 %s）" % str(slot_bad))
	flock.free()

# ============================================================
# 6) 打印全部新点
# ============================================================
func _print_new_points(wp: Array, cp: Array) -> void:
	print("--- NEW PERCH POINTS (world coords, normal, slope, support top, gaps) ---")
	var merged: Array = []
	merged.append_array(wp)
	merged.append_array(cp)
	for p_v in merged:
		var p: Dictionary = p_v
		var kind: String = String(p.get("kind", ""))
		if kind != "lamp" and kind != "porch_rail":
			continue
		var pid: String = String(p["id"])
		var info: Dictionary = _support.get(pid, {})
		var n: Vector3 = (p["normal"] as Vector3).normalized()
		var facing: Vector3 = (p["facing"] as Vector3)
		var pos: Vector3 = p["pos"]
		var support_top: float = float(info.get("support_top", 0.0))
		var foot: Vector3 = pos + n * FOOT_LIFT
		print("  %-14s kind=%-10s pos=%s normal=%s slope=%.6f radius=%.3f slots=%d facing=%s support_top=%.4f pos_gap=%.4f foot_y=%.4f foot_gap=%.4f" % [
			pid, kind, _fmtv(pos), _fmtv(n), float(p["slope"]), float(p["radius"]), int(p.get("slots", 0)),
			_fmtv(facing), support_top, pos.y - support_top, foot.y, foot.y - support_top])
