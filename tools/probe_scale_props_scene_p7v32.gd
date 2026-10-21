extends SceneTree
## P7-V3.2 T3 场景级家具布局校验探针（headless）
##
## 目的：真正构建一遍 cottage.build()，在“合批后的真实网格”上量每件家具的世界/小屋局部 AABB，
## 校验：家具↔墙/柱/楼梯无穿插；家具↔家具无重叠；门内侧 1.2 m 通行区；楼梯口 1.2 m 通道；
## 主通道（可行走区域 clearance ≥ 0.30 → 通道 ≥ 0.60 m）；床/床头柜/桌边可用空间；
## 门板开启（main.gd: rotation.y 0 → -1.85）扫掠扇区不扫家具；
## 墙挂件（挂钟/挂衣板/画框/窗帘）贴墙 + 高度区间；台灯/落地灯与 light_sources 锚点；
## 阁楼净高（屋顶下皮）与楼梯洞口禁放区；顺带统计家具/全屋的 mesh/surface/triangle 成本。
##
## 运行：
##   & <GODOT> --headless --path <proj> --script res://tools/probe_scale_props_scene_p7v32.gd
## 输出以 "[SCENE] RESULT ..." 结尾；fail==0 时 exit 0。

const COTTAGE := preload("res://scripts/cottage.gd")
const PROPS := preload("res://scripts/isle_house_props.gd")
const MATH := preload("res://scripts/isle_math.gd")

const WALL_KINDS := ["coat_rack", "wall_clock", "picture_frame", "curtain"]
const FLAT_KINDS := ["rug", "doormat"]
const SEAT_KINDS := ["chair", "sofa", "armchair", "reading_chair", "shoe_bench"]
const FRONT_CLEAR_KINDS := ["wardrobe", "tall_cupboard", "bookshelf", "sideboard"]
const SKIP_PREFIX := ["Glow", "Halo", "Blob"]

# 墙挂件合理高度区间（相对本层地面；单位 m）
const RANGE_WALL_CLOCK := Vector2(1.45, 1.75)
const RANGE_COAT_TOP := Vector2(1.35, 1.70)
const RANGE_COAT_HOOK := Vector2(1.05, 1.40)
const RANGE_PICTURE := Vector2(1.44, 1.70)
const RANGE_CURTAIN_ROD := Vector2(2.05, 2.25)
const RANGE_CURTAIN_ROD_ATTIC := Vector2(1.70, 2.40)
# 门：spec 派生 —— 门扇宽 = 门洞净宽 − 2×门框
const DOOR_CLEAR_W := 1.14
const DOOR_FRAME := 0.06
# 坐面高 / 桌面高（isle_scale_spec，用于腿部空间与床垫顶推算）
const SEAT_H := 0.40
const SHOE_BENCH_SEAT_H := 0.42
const BED_MATTRESS_TOP := 0.45
const ROOF_PANEL_T := 0.14

var checks := 0
var pass_n := 0
var warn_n := 0
var fail_n := 0
var fail_msgs: Array = []

var stage: Node3D = null
var root3d: Node3D = null
var C: Dictionary = {}
var fy := 0.55
var attic_floor := 0.0
var hw := 3.8
var hd := 3.1
var wall_t := 0.36
var ridge_y := 0.0
var rh := 0.0
var ceiling_y := 0.0          # 一层天花板下皮（小屋局部 y）
var win_lights_local: Array = []  # C["win_lights"] 位置转到小屋局部（一层 5 扇）
var attic_win_local := Vector3.ZERO  # 阁楼山墙窗中心（小屋局部）

var props: Array = []          # 每件家具一条（见 _collect_props）
var by_kind: Dictionary = {}   # kind -> Array[entry]
var light_sources: Array = []
var door_pivot: Node3D = null
var scene_cost: Dictionary = {}

var grid := {}                 # 一层通行性网格

var _pending := true

func _initialize() -> void:
	print("[SCENE] ===== P7-V3.2 T3 场景级家具布局校验（真实 build + 合批后网格 AABB） =====")

## 注意：不能在 _initialize() 里 build —— 此时 SceneTree.root(Window) 尚未 is_inside_tree()，
## 任何 global_transform / to_local(global_position) 都会报错并返回单位阵（P7-V3.2 首跑踩过）。
## 等第一帧 _process（此时整棵树已入树）再构建与测量。
func _process(_delta: float) -> bool:
	if not _pending:
		return true
	_pending = false
	_run_all()
	return true

func _run_all() -> void:
	stage = Node3D.new()
	stage.name = "SceneStage"
	root.add_child(stage)
	var ret: Dictionary = COTTAGE.build(stage)
	if ret.is_empty() or not ret.has("root"):
		_fail("cottage.build 返回空 / 缺 root")
		_print_summary()
		quit(1)
		return
	root3d = ret["root"] as Node3D
	C = root3d.get_meta("cottage_ctx")
	light_sources = ret.get("light_sources", [])
	door_pivot = ret.get("door_pivot", C.get("door_pivot", null))
	_read_ctx()
	_print_ctx()
	_collect_props()
	_print_props()
	_check_bounds_and_support()
	_check_wall_mounts()
	_check_overlaps()
	_check_front_clearance()
	_check_relations()
	_check_door()
	_check_stairs()
	_grid_build()
	_check_passage()
	_check_lamp_lights()
	_check_attic_headroom()
	_cost_probe()
	_print_summary()
	quit(0 if fail_n == 0 else 1)

# ============================================================
# 基础工具
# ============================================================
func _ok(cond: bool, msg: String) -> bool:
	checks += 1
	if cond:
		pass_n += 1
		print("  [PASS] " + msg)
	else:
		fail_n += 1
		fail_msgs.append(msg)
		print("  [FAIL] " + msg)
	return cond

func _warn(cond: bool, msg: String) -> bool:
	checks += 1
	if cond:
		pass_n += 1
		print("  [PASS] " + msg)
	else:
		warn_n += 1
		print("  [WARN] " + msg)
	return cond

func _fail(msg: String) -> void:
	checks += 1
	fail_n += 1
	fail_msgs.append(msg)
	print("  [FAIL] " + msg)

func _fmt(v: Vector3) -> String:
	return "(%.2f,%.2f,%.2f)" % [v.x, v.y, v.z]

func _aabb_str(b: AABB) -> String:
	return "min%s max%s size%s" % [_fmt(b.position), _fmt(b.position + b.size), _fmt(b.size)]

func _merge_aabb(cur: Array, bb: AABB) -> void:
	if cur.is_empty():
		cur.append(bb)
	else:
		cur[0] = (cur[0] as AABB).merge(bb)

## 把一个局部 AABB 经变换后求 8 角点的 AABB
func _xf_aabb(xf: Transform3D, bb: AABB) -> AABB:
	var out: Array = []
	for i in range(8):
		var p: Vector3 = bb.get_endpoint(i)
		var q: Vector3 = xf * p
		var one := AABB(q, Vector3.ZERO)
		_merge_aabb(out, one)
	return out[0] as AABB

func _is_skip(node_name: String) -> bool:
	for pre in SKIP_PREFIX:
		if node_name.begins_with(pre):
			return true
	return false

## 累加 node 子树里所有可见网格的 AABB（相对 node 自身坐标）；跳过 Glow/Halo/Blob
func _subtree_aabb(node: Node, xf: Transform3D, out: Array) -> void:
	for c in node.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			var mi := c as MeshInstance3D
			if not _is_skip(String(mi.name)):
				var t: Transform3D = xf * mi.transform
				_merge_aabb(out, _xf_aabb(t, mi.mesh.get_aabb()))
		if c is Node3D:
			_subtree_aabb(c, xf * (c as Node3D).transform, out)

func _local_aabb_of(node: Node) -> AABB:
	var out: Array = []
	_subtree_aabb(node, Transform3D.IDENTITY, out)
	if out.is_empty():
		return AABB()
	return out[0] as AABB

## 从 node 沿父链累加到 ancestor 的相对变换（不依赖场景树/global_transform：
## SceneTree._initialize 阶段 root Window 尚未 is_inside_tree()，global_transform 会报错并返回单位阵）
func _rel_to(node: Node3D, ancestor: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != ancestor:
		var n3 := n as Node3D
		if n3 == null:
			break
		xf = n3.transform * xf
		n = n.get_parent()
	return xf

## 世界 = stage.transform(单位) * root3d.transform * 小屋局部；
## cottage 的 root3d 直接挂在 stage(原点) 下，故 world = root3d.transform * 小屋局部点。
func _cottage_to_world(p: Vector3) -> Vector3:
	if root3d == null:
		return p
	return root3d.transform * p

func _world_aabb_of(node: Node3D) -> AABB:
	var bb := _local_aabb_of(node)
	var xf := _rel_to(node, root3d)
	if bb.size == Vector3.ZERO:
		return AABB()
	return _xf_aabb(xf, bb)

## 家具节点局部 → 小屋局部 的变换（父链局部变换累加，不用 global_transform）
func _cottage_xf(node: Node3D) -> Transform3D:
	if root3d == null:
		return Transform3D.IDENTITY
	return _rel_to(node, root3d)

func _room_of(node: Node3D) -> String:
	var p: Node = node.get_parent()
	while p != null and p != root3d:
		if String(p.name).to_lower().contains("attic"):
			return "attic"
		p = p.get_parent()
	return "ground"

func _xz_gap(a: AABB, b: AABB) -> float:
	var dx: float = maxf(maxf(b.position.x - (a.position.x + a.size.x), a.position.x - (b.position.x + b.size.x)), 0.0)
	var dz: float = maxf(maxf(b.position.z - (a.position.z + a.size.z), a.position.z - (b.position.z + b.size.z)), 0.0)
	return sqrt(dx * dx + dz * dz)

func _xz_overlap(a: AABB, b: AABB) -> Vector2:
	var lo := Vector3(maxf(a.position.x, b.position.x), 0.0, maxf(a.position.z, b.position.z))
	var hi := Vector3(minf(a.position.x + a.size.x, b.position.x + b.size.x), 0.0, minf(a.position.z + a.size.z, b.position.z + b.size.z))
	return Vector2(hi.x - lo.x, hi.z - lo.z)

func _aabb_overlap(a: AABB, b: AABB) -> Vector3:
	var lo := Vector3(maxf(a.position.x, b.position.x), maxf(a.position.y, b.position.y), maxf(a.position.z, b.position.z))
	var hi := Vector3(minf(a.position.x + a.size.x, b.position.x + b.size.x), minf(a.position.y + a.size.y, b.position.y + b.size.y), minf(a.position.z + a.size.z, b.position.z + b.size.z))
	return hi - lo

func _xz_dist_point(a: AABB, p: Vector2) -> float:
	var cx: float = clampf(p.x, a.position.x, a.position.x + a.size.x)
	var cz: float = clampf(p.y, a.position.z, a.position.z + a.size.z)
	return sqrt((p.x - cx) * (p.x - cx) + (p.y - cz) * (p.y - cz))

# ============================================================
# 上下文
# ============================================================
func _read_ctx() -> void:
	fy = float(C.get("fy", 0.55))
	hw = float(C.get("hw", MATH.HOUSE_W * 0.5))
	hd = float(C.get("hd", MATH.HOUSE_D * 0.5))
	wall_t = float(C.get("wall_t", 0.36))
	attic_floor = float(C.get("attic_floor", fy + 2.62))
	ridge_y = float(C.get("ridge_y", fy + MATH.HOUSE_WALL_H + MATH.HOUSE_ROOF_H))
	rh = float(C.get("rh", MATH.HOUSE_ROOF_H))
	ceiling_y = float(C.get("in_top", fy + 2.42))
	if not C.has("in_top"):
		_warn(false, "cottage_ctx 缺 in_top（用 fy+2.42=%.2f 推算一层天花板下皮）" % ceiling_y)
	win_lights_local.clear()
	for wl in C.get("win_lights", []):
		if wl is Dictionary and wl.has("pos"):
			win_lights_local.append(root3d.transform.affine_inverse() * (wl["pos"] as Vector3))
	attic_win_local = Vector3.ZERO
	if C.has("attic_window_world"):
		var aw: Vector3 = C["attic_window_world"]
		if aw != Vector3.ZERO:
			attic_win_local = root3d.transform.affine_inverse() * aw
	if not C.has("attic_floor"):
		_warn(false, "cottage_ctx 缺 attic_floor（用推算值 %.2f）" % attic_floor)
	if not C.has("ridge_y") or not C.has("rh"):
		_warn(false, "cottage_ctx 缺 ridge_y/rh，阁楼净高检查可能不准")

func _print_ctx() -> void:
	print("[SCENE] ---- 上下文（小屋局部坐标） ----")
	print("  外廓 w=%.2f d=%.2f | hw=%.2f hd=%.2f wall_t=%.2f fy=%.2f" % [hw * 2.0, hd * 2.0, hw, hd, wall_t, fy])
	print("  attic_floor=%.2f ridge_y=%.2f rh=%.2f | 墙内表面 |x|<=%.2f |z|<=%.2f" % [
		attic_floor, ridge_y, rh, hw - wall_t, hd - wall_t])
	print("  house ground_y=%.2f HOUSE_X=%.2f HOUSE_Z=%.2f HOUSE_YAW=%.2f" % [
		MATH.house_ground_y(), MATH.HOUSE_X, MATH.HOUSE_Z, MATH.HOUSE_YAW])
	print("  一层天花板下皮=%.3f | 窗中心样本 %d 个 | door_pivot=%s light_sources=%d" % [
		ceiling_y, win_lights_local.size(), str(door_pivot != null), light_sources.size()])

# ============================================================
# 收集家具
# ============================================================
func _collect_props() -> void:
	print("[SCENE] ---- 家具实例（合批后真实网格 AABB） ----")
	var found: Array = []
	_walk_props(root3d, found)
	found.sort_custom(func(a, b): return String(a.name) < String(b.name))
	for node in found:
		var n3 := node as Node3D
		var kind := String(n3.get_meta("prop_kind", "?"))
		var wall := bool(n3.get_meta("prop_wall_mounted", WALL_KINDS.has(kind)))
		var local_bb := _local_aabb_of(n3)
		var xf := _cottage_xf(n3)
		var cbb := _xf_aabb(xf, local_bb)
		var entry := {
			"node": n3, "kind": kind, "wall": wall, "room": _room_of(n3),
			"pos": n3.position, "aabb": cbb, "local": local_bb,
			"flat": FLAT_KINDS.has(kind),
			"fwd": (xf.basis * Vector3(0, 0, 1)).normalized(),
			"right": (xf.basis * Vector3(1, 0, 0)).normalized(),
		}
		props.append(entry)
		if not by_kind.has(kind):
			by_kind[kind] = []
		by_kind[kind].append(entry)

func _walk_props(node: Node, out: Array) -> void:
	for c in node.get_children():
		if c is Node3D and (c as Node3D).has_meta("prop_kind"):
			out.append(c)
		if c is Node3D:
			_walk_props(c, out)

func _kind_entries(kind: String) -> Array:
	return by_kind.get(kind, [])

func _print_props() -> void:
	var g := 0
	var a := 0
	for e in props:
		var bb: AABB = e["aabb"]
		var tag := "WALL" if e["wall"] else "floor"
		if e["room"] == "attic":
			a += 1
		else:
			g += 1
		print("  PROP %-16s %-4s %-5s pos%s | 局部 宽%.3f 高%.3f 深%.3f base=%.3f top=%.3f" % [
			e["kind"], tag, e["room"], _fmt(e["pos"]),
			e["local"].size.x, e["local"].size.y, e["local"].size.z,
			bb.position.y, bb.position.y + bb.size.y])
	print("  合计 家具 %d 件（一层 %d / 阁楼 %d）" % [props.size(), g, a])

# ============================================================
# 贴墙 / 落地 / 支撑
# ============================================================
func _expected_floor(e: Dictionary) -> float:
	return attic_floor if e["room"] == "attic" else fy

func _find_support(e: Dictionary) -> Dictionary:
	var bb: AABB = e["aabb"]
	for o in props:
		if o == e:
			continue
		if o["wall"] or o["flat"]:
			continue
		var ob: AABB = o["aabb"]
		if o["kind"] == e["kind"]:
			continue
		if ob.position.x - 0.02 <= bb.get_center().x and bb.get_center().x <= ob.position.x + ob.size.x + 0.02 \
				and ob.position.z - 0.02 <= bb.get_center().z and bb.get_center().z <= ob.position.z + ob.size.z + 0.02:
			var top: float = ob.position.y + ob.size.y
			if absf(top - bb.position.y) <= 0.03:
				return o
	return {}

func _check_bounds_and_support() -> void:
	print("[SCENE] ---- 家具↔墙内表面 / 落地 / 台面支撑 ----")
	var xlim: float = hw - wall_t
	var zlim: float = hd - wall_t
	for e in props:
		if e["wall"]:
			continue
		var bb: AABB = e["aabb"]
		var kind: String = e["kind"]
		var tag: String = "%s@%s" % [kind, e["room"]]
		_ok(bb.position.x >= -xlim - 0.02 and bb.position.x + bb.size.x <= xlim + 0.02,
			"%s X 在墙内表面范围（%.3f..%.3f ⊂ ±%.3f）" % [tag, bb.position.x, bb.position.x + bb.size.x, xlim])
		_ok(bb.position.z >= -zlim - 0.02 and bb.position.z + bb.size.z <= zlim + 0.02,
			"%s Z 在墙内表面范围（%.3f..%.3f ⊂ ±%.3f）" % [tag, bb.position.z, bb.position.z + bb.size.z, zlim])
		var exp := _expected_floor(e)
		var support := _find_support(e)
		if support.is_empty():
			_ok(absf(bb.position.y - exp) <= 0.03,
				"%s 落地 base=%.3f ≈ 本层地面 %.3f" % [tag, bb.position.y, exp])
		else:
			_ok(absf(bb.position.y - (support["aabb"].position.y + support["aabb"].size.y)) <= 0.03,
				"%s 置于 %s 台面（base=%.3f，支撑顶=%.3f）" % [tag, support["kind"], bb.position.y, support["aabb"].position.y + support["aabb"].size.y])

# ============================================================
# 墙挂件：贴墙 / 朝向 / 高度区间
# ============================================================
func _nearest_wall(pos: Vector3) -> Dictionary:
	var xlim: float = hw - wall_t
	var zlim: float = hd - wall_t
	var best := {"dist": 1e9, "normal": Vector3.ZERO, "name": ""}
	var cand := [
		{"dist": xlim - pos.x, "normal": Vector3(-1, 0, 0), "name": "右墙"},
		{"dist": pos.x + xlim, "normal": Vector3(1, 0, 0), "name": "左墙"},
		{"dist": zlim - pos.z, "normal": Vector3(0, 0, -1), "name": "前墙"},
		{"dist": pos.z + zlim, "normal": Vector3(0, 0, 1), "name": "后墙"},
	]
	for c in cand:
		if absf(float(c["dist"])) < absf(float(best["dist"])):
			best = c
	return best

func _check_wall_mounts() -> void:
	print("[SCENE] ---- 墙挂件：贴墙 / 朝向室内 / 高度区间 ----")
	for kind in WALL_KINDS:
		var arr := _kind_entries(kind)
		if arr.is_empty():
			_warn(false, "场景里没有 %s（若本轮布局未使用可忽略）" % kind)
			continue
		for e in arr:
			var bb: AABB = e["aabb"]
			var pos: Vector3 = e["pos"]
			var room_floor: float = _expected_floor(e)
			var wall := _nearest_wall(pos)
			var dist := float(wall["dist"])
			var allow: float = 0.20 if kind == "curtain" else 0.06
			_ok(absf(dist) <= allow,
				"%s(%s) 原点距%s内表面 %.3f ∈ ±%.2f" % [kind, e["room"], wall["name"], dist, allow])
			if absf(dist) <= allow:
				var dot: float = (e["fwd"] as Vector3).dot(wall["normal"] as Vector3)
				_ok(dot >= 0.80, "%s(%s) 朝向室内（fwd·n=%.3f ≥ 0.80）" % [kind, e["room"], dot])
			var top: float = bb.position.y + bb.size.y
			if kind == "wall_clock":
				var cy: float = pos.y - room_floor
				_ok(cy >= RANGE_WALL_CLOCK.x and cy <= RANGE_WALL_CLOCK.y,
					"wall_clock(%s) 中心高 %.3f ∈ [%.2f, %.2f]" % [e["room"], cy, RANGE_WALL_CLOCK.x, RANGE_WALL_CLOCK.y])
			elif kind == "coat_rack":
				var th: float = top - room_floor
				var hook_y: float = pos.y - room_floor + 0.28
				_ok(th >= RANGE_COAT_TOP.x and th <= RANGE_COAT_TOP.y,
					"coat_rack(%s) 顶高 %.3f ∈ [%.2f, %.2f]（挂衣板 1.20 高、顶=原点+0.575）" % [e["room"], th, RANGE_COAT_TOP.x, RANGE_COAT_TOP.y])
				_ok(hook_y >= RANGE_COAT_HOOK.x and hook_y <= RANGE_COAT_HOOK.y,
					"coat_rack(%s) 挂钩高 %.3f ∈ [%.2f, %.2f]（肩高 1.24 基准）" % [e["room"], hook_y, RANGE_COAT_HOOK.x, RANGE_COAT_HOOK.y])
			elif kind == "picture_frame":
				var cy2: float = pos.y - room_floor
				_ok(cy2 >= RANGE_PICTURE.x and cy2 <= RANGE_PICTURE.y,
					"picture_frame(%s) 中心高 %.3f ∈ [%.2f, %.2f]" % [e["room"], cy2, RANGE_PICTURE.x, RANGE_PICTURE.y])
			elif kind == "curtain":
				var rod: float = pos.y - room_floor
				var rng := RANGE_CURTAIN_ROD_ATTIC if e["room"] == "attic" else RANGE_CURTAIN_ROD
				_ok(rod >= rng.x and rod <= rng.y,
					"curtain(%s) 帘杆高 %.3f ∈ [%.2f, %.2f]" % [e["room"], rod, rng.x, rng.y])
				_ok(bb.position.y >= room_floor - 0.05 or room_floor > fy + 1.0,
					"curtain(%s) 帘布下摆不穿地（bottom=%.3f，地面=%.3f）" % [e["room"], bb.position.y, room_floor])
			# 1) 与落地家具真实三维穿插（XZ 投影 + Y 相交才算碰撞；帘布下摆允许垂在家具前）
			var overlaps: Array = []
			for o in props:
				if o["wall"] or o["flat"] or String(o["kind"]).contains("lamp"):
					continue
				var ov := _aabb_overlap(bb, o["aabb"])
				if ov.x > 0.01 and ov.z > 0.01 and ov.y > 0.005:
					overlaps.append(String(o["kind"]))
			_ok(overlaps.is_empty(), "%s(%s) 不与落地家具穿插（重叠：%s）" % [kind, e["room"], str(overlaps)])
			# 2) 天花板/屋顶下皮净空（一层用 in_top；阁楼用屋面板下皮，取 AABB 最外 |x|）
			var ceil_under: float = _roof_under_for(e) if e["room"] == "attic" else ceiling_y
			_ok(top <= ceil_under - 0.03, "%s(%s) 顶部 %.2f ≤ 天花板/屋顶下皮 %.2f − 0.03" % [
				kind, e["room"], top, ceil_under])
			# 3) 与窗的位置关系（窗中心样本：一层 5 扇 + 阁楼山墙窗；近似判定，注释见文件头）
			var win_pts: Array = []
			win_pts.append_array(win_lights_local)
			if attic_win_local != Vector3.ZERO:
				win_pts.append(attic_win_local)
			if win_pts.is_empty():
				_warn(false, "%s(%s) 无窗中心样本，跳过窗关系" % [kind, e["room"]])
			elif kind == "curtain":
				var nrm: Vector3 = wall["normal"] as Vector3
				var along := Vector3(-nrm.z, 0, nrm.x).normalized()
				var near_win := false
				var best_gap := 1e9
				for wp in win_pts:
					var w: Vector3 = wp as Vector3
					var plane_off: float = absf((Vector3(bb.get_center().x, 0, bb.get_center().z) - Vector3(w.x, 0, w.z)).dot(nrm))
					if plane_off > 0.40:
						continue
					var off_along: float = absf((Vector3(w.x, 0, w.z) - Vector3(bb.get_center().x, 0, bb.get_center().z)).dot(along))
					# 窗洞半宽：一层前窗 ow=1.00、侧/后窗 0.90~1.00、阁楼山墙窗 1.50；用 0.85 统一近似并放宽 0.35
					var gap: float = maxf(0.0, off_along - 0.85 - _fwd_size(bb, along) * 0.5)
					best_gap = minf(best_gap, gap)
					if gap <= 0.35:
						near_win = true
				_ok(near_win, "%s(%s) 帘布对应窗洞开口（与最近窗沿水平差 %.2f ≤ 0.35 m）" % [kind, e["room"], best_gap])
			else:
				var min_wd := 1e9
				for wp in win_pts:
					var w: Vector3 = wp as Vector3
					min_wd = minf(min_wd, Vector2(w.x - bb.get_center().x, w.z - bb.get_center().z).length())
				_ok(min_wd >= 0.55, "%s(%s) 不挡窗（最近窗中心 XZ %.2f ≥ 0.55 m）" % [kind, e["room"], min_wd])

# ============================================================
# 家具两两重叠
# ============================================================
## 是否属于"椅可推入桌下"组合（仅餐椅/书桌椅；茶几/边桌不算）
func _is_tuck_pair(a: Dictionary, b: Dictionary) -> bool:
	if a["kind"] == "chair" and (b["kind"] == "dining_table" or b["kind"] == "desk"):
		return true
	if b["kind"] == "chair" and (a["kind"] == "dining_table" or a["kind"] == "desk"):
		return true
	return false

## 点是否在墙内表面范围内（含 margin）
func _inside_room(p: Vector3, margin: float = 0.02) -> bool:
	var xlim: float = hw - wall_t - margin
	var zlim: float = hd - wall_t - margin
	return p.x >= -xlim and p.x <= xlim and p.z >= -zlim and p.z <= zlim

## AABB 沿给定水平方向的尺寸
func _fwd_size(bb: AABB, fwd: Vector3) -> float:
	return bb.size.x * absf(fwd.x) + bb.size.z * absf(fwd.z)

## 阁楼屋顶下皮：屋面板厚 ROOF_PANEL_T、坡角 pitch = atan(rh/hw)
## 下皮 = ridge_y − |x|·tan(pitch) − ROOF_PANEL_T/cos(pitch)（面板厚度在竖直方向的投影）
func _attic_roof_under(x_abs: float) -> float:
	var pitch: float = atan(rh / hw) if rh > 0.0 and hw > 0.0 else 0.0
	return ridge_y - x_abs * tan(pitch) - ROOF_PANEL_T / cos(pitch)

## 墙挂件/家具顶点处屋顶下皮（取 AABB 最外 |x|，屋脊两侧对称）
func _roof_under_for(e: Dictionary) -> float:
	var bb: AABB = e["aabb"]
	var x_max: float = maxf(absf(bb.position.x), absf(bb.position.x + bb.size.x))
	return _attic_roof_under(x_max)

func _chair_vs_table(chair: Dictionary, table: Dictionary) -> bool:
	# 允许餐椅/书桌椅推入桌下：椅心必须在桌 AABB 之外；重叠深度 ≤ 0.22
	var cb: AABB = chair["aabb"]
	var tb: AABB = table["aabb"]
	var c_center := Vector2(cb.get_center().x, cb.get_center().z)
	var in_x: bool = c_center.x >= tb.position.x and c_center.x <= tb.position.x + tb.size.x
	var in_z: bool = c_center.y >= tb.position.z and c_center.y <= tb.position.z + tb.size.z
	if in_x and in_z:
		return false
	var ov := _aabb_overlap(cb, tb)
	# 推入桌下时只有"朝桌方向"的深度受限（另一个轴必然整段落在桌面投影内），取较浅轴判定
	return (ov.x <= 0.22 or ov.z <= 0.22) and ov.y > 0.0

func _check_overlaps() -> void:
	print("[SCENE] ---- 家具↔家具：重叠 / 间距 ----")
	var solid: Array = []
	for e in props:
		if not e["wall"] and not e["flat"]:
			solid.append(e)
	var bad := 0
	for i in range(solid.size()):
		for j in range(i + 1, solid.size()):
			var a: Dictionary = solid[i]
			var b: Dictionary = solid[j]
			var ov := _aabb_overlap(a["aabb"], b["aabb"])
			if ov.x <= 0.015 or ov.z <= 0.015 or ov.y <= 0.010:
				continue
			# 允许：餐椅/书桌椅推入桌下（浅重叠、椅心在桌外）；茶几/边桌不算可推入
			if _is_tuck_pair(a, b):
				var chair: Dictionary = a if a["kind"] == "chair" else b
				var table: Dictionary = b if a["kind"] == "chair" else a
				if _chair_vs_table(chair, table):
					continue
			# 允许：台灯/落地灯底座与支撑台面为面接触（y 重叠极薄）
			if ov.y <= 0.020 and (a["kind"].contains("lamp") or b["kind"].contains("lamp")):
				continue
			bad += 1
			if bad <= 12:
				print("    [COLLIDE] %s(%s) ∩ %s(%s) 重叠 %s" % [
					a["kind"], a["room"], b["kind"], b["room"], _fmt(ov)])
	_ok(bad == 0, "家具两两无体积重叠（真实碰撞 %d 对）" % bad)
	# 沙发/扶手椅 ↔ 茶几 间距（lead m00287：室内前沿↔茶几边缘 0.30–0.45 m）
	var check_gap := func(kind_seat: String) -> void:
		var seats := _kind_entries(kind_seat)
		var coffee := _kind_entries("coffee_table")
		if seats.is_empty() or coffee.is_empty():
			return
		var min_gap := 1e9
		for s in seats:
			for c in coffee:
				min_gap = minf(min_gap, _xz_gap(s["aabb"], c["aabb"]))
		# lead m00366 G：目标 0.30–0.45；>0.45 放宽为 ≤0.60 也 PASS；>0.60 WARN
		if min_gap < 0.30:
			_ok(false, "%s ↔ 茶几 最近 XZ 间距 %.3f < 0.30（太近：撞腿/不便起身；目标 0.30–0.45）" % [kind_seat, min_gap])
		elif min_gap <= 0.60:
			_ok(true, "%s ↔ 茶几 最近 XZ 间距 %.3f ∈ [0.30,0.60]（目标 0.30–0.45，>0.45 已放宽）" % [kind_seat, min_gap])
		else:
			_warn(false, "%s ↔ 茶几 最近 XZ 间距 %.3f > 0.60（略远，建议拉近到 0.30–0.45）" % [kind_seat, min_gap])
	check_gap.call("sofa")
	check_gap.call("armchair")
	# 沙发/扶手椅：至少一侧（含后方）有 ≥0.60 m 通行/站立空间
	for kind in ["sofa", "armchair"]:
		for s in _kind_entries(kind):
			var sb: AABB = s["aabb"]
			var right: Vector3 = s["right"]
			var half_w: float = _fwd_size(sb, right) * 0.5
			var pass_ok := false
			var where := ""
			for sgn in [-1.0, 1.0]:
				var p: Vector3 = Vector3(sb.get_center().x, fy, sb.get_center().z) + right * (sgn * (half_w + 0.60))
				if _inside_room(p) and _solid_at(p, s) == "":
					pass_ok = true
					where = "侧向"
			if pass_ok:
				_ok(true, "%s(%s) 至少一侧 0.60 m 通行空间（%s）" % [kind, s["room"], where])
			else:
				_ok(false, "%s(%s) 两侧均无 0.60 m 通行空间" % [kind, s["room"]])
	# 床头柜 ↔ 床
	var beds := _kind_entries("bed")
	var stands := _kind_entries("nightstand")
	if not beds.is_empty() and not stands.is_empty():
		var bed: Dictionary = beds[0]
		var best := 1e9
		var best_ns: Dictionary = {}
		for ns in stands:
			var d := _xz_gap(bed["aabb"], ns["aabb"])
			if d < best:
				best = d
				best_ns = ns
		_ok(best <= 0.20, "bed ↔ nightstand 最近 XZ 间距 %.3f ≤ 0.20（床头柜伸手可及）" % best)
		_warn(best >= 0.0, "bed ↔ nightstand 无重叠（间距 %.3f）" % best)
		if not best_ns.is_empty():
			var ntop: float = best_ns["aabb"].position.y + best_ns["aabb"].size.y
			var mattress_top: float = bed["aabb"].position.y + BED_MATTRESS_TOP
			print("    [INFO] nightstand 台面 %.3f vs 床垫顶 %.3f（高差 %+.3f）" % [ntop, mattress_top, ntop - mattress_top])
			_ok(ntop >= mattress_top - 0.02 and ntop <= mattress_top + 0.15,
				"nightstand 台面 %.2f 与床垫顶 %.2f 配套（高差 %+.2f ∈ [−0.02,+0.15]）" % [
					ntop - _expected_floor(best_ns), BED_MATTRESS_TOP, ntop - mattress_top])
	# 椅子必须靠近某张桌子、且朝向桌子
	var chairs := _kind_entries("chair")
	var tables: Array = []
	tables.append_array(_kind_entries("dining_table"))
	tables.append_array(_kind_entries("desk"))
	for ch in chairs:
		var near := false
		for tb in tables:
			var d2 := _xz_gap(ch["aabb"], tb["aabb"])
			if d2 <= 0.35:
				near = true
				var dir: Vector3 = (tb["aabb"].get_center() - ch["aabb"].get_center())
				dir.y = 0.0
				if dir.length() > 1e-4:
					dir = dir.normalized()
				var dot: float = (ch["fwd"] as Vector3).dot(dir)
				_ok(dot >= 0.70, "chair 朝向桌子（fwd·dir=%.2f ≥ 0.70）" % dot)
				break
		_ok(near, "chair 靠近桌子（最近桌边 ≤ 0.35 m）")

# ============================================================
# 柜/书架/衣柜前方操作空间
# ============================================================
func _check_front_clearance() -> void:
	print("[SCENE] ---- 柜类前方操作空间 / 床侧空间 ----")
	for kind in FRONT_CLEAR_KINDS:
		for e in _kind_entries(kind):
			var bb: AABB = e["aabb"]
			var fwd: Vector3 = e["fwd"]
			var half_depth: float = _fwd_size(bb, fwd) * 0.5
			var base_pt: Vector3 = Vector3(bb.get_center().x, 0, bb.get_center().z)
			var p1: Vector3 = base_pt + fwd * (half_depth + 0.30)
			var p2: Vector3 = base_pt + fwd * (half_depth + 0.60)
			# lead m00366 E：保留 0.6 m 柜门/抽屉净空，FAIL 时打印遮挡物名称+位置，便于 T2 改布局
			var blockers: Array = []
			# lead m00404：遮挡物必须三轴 AABB 相交（腿柱采样 y=楼板+0.10；跨层的阁楼家具不判遮挡）
			var col_y: float = bb.position.y + 0.10
			for o in props:
				if o == e or o["wall"] or o["flat"] or o["room"] != e["room"]:
					continue
				var ob: AABB = o["aabb"]
				if not (col_y >= ob.position.y - 0.02 and col_y <= ob.position.y + ob.size.y + 0.02):
					continue
				for pp in [p1, p2]:
					if pp.x >= ob.position.x - 0.05 and pp.x <= ob.position.x + ob.size.x + 0.05 \
							and pp.z >= ob.position.z - 0.05 and pp.z <= ob.position.z + ob.size.z + 0.05:
						blockers.append("%s@%s" % [o["kind"], _fmt(Vector3(ob.get_center().x, ob.position.y, ob.get_center().z))])
						break
			var xlim: float = hw - wall_t
			var zlim: float = hd - wall_t
			var inroom: bool = p2.x > -xlim and p2.x < xlim and p2.z > -zlim and p2.z < zlim
			_ok(blockers.is_empty() and inroom,
				"%s(%s) 前方 0.3/0.6 m 柜门/抽屉净空（在室内 %s；遮挡：%s）" % [
					e["kind"], e["room"], str(inroom), str(blockers)])
	# 床：至少一侧 0.55 m 可站人
	for bed in _kind_entries("bed"):
		var bb: AABB = bed["aabb"]
		var right: Vector3 = bed["right"]
		var cx: float = bb.get_center().x
		var cz: float = bb.get_center().z
		var half_w: float = (bb.size.x * absf(right.x) + bb.size.z * absf(right.z)) * 0.5
		var ok_side := false
		for sgn in [-1.0, 1.0]:
			var p: Vector3 = Vector3(cx, 0, cz) + right * (sgn * (half_w + 0.55))
			var hit := false
			for o in props:
				if o == bed or o["wall"] or o["flat"] or o["room"] != bed["room"]:
					continue
				var ob: AABB = o["aabb"]
				if p.x >= ob.position.x - 0.05 and p.x <= ob.position.x + ob.size.x + 0.05 \
						and p.z >= ob.position.z - 0.05 and p.z <= ob.position.z + ob.size.z + 0.05:
					hit = true
					break
			if not hit:
				ok_side = true
		_ok(ok_side, "bed 至少一侧 0.55 m 站人空间")

# ============================================================
# 家具之间的人体工学配合（站位/坐位/操作高度）
# ============================================================
## 点 p 上是否被实体家具占据（忽略墙挂/平垫/灯/自身）；返回 kind 或 ""
func _solid_at(p: Vector3, skip: Dictionary) -> String:
	for o in props:
		if o == skip or o["wall"] or o["flat"]:
			continue
		if String(o["kind"]).contains("lamp"):
			continue
		var ob: AABB = o["aabb"]
		if p.x >= ob.position.x - 0.05 and p.x <= ob.position.x + ob.size.x + 0.05 \
				and p.z >= ob.position.z - 0.05 and p.z <= ob.position.z + ob.size.z + 0.05:
			return String(o["kind"])
	return ""

## 坐具的配套家具（桌/书桌/茶几/边几）：位于坐具前方、横向对齐、前向距离最近者
func _companion_of(seat: Dictionary) -> Dictionary:
	var fwd: Vector3 = seat["fwd"]
	var right: Vector3 = seat["right"]
	var seat_half_w: float = _fwd_size(seat["aabb"], right) * 0.5
	var best: Dictionary = {}
	var best_fwd := 1e9
	for kind in ["dining_table", "desk", "coffee_table", "side_table"]:
		for o in _kind_entries(kind):
			# 配套家具必须同层：跨层（阁楼椅 vs 一层桌）不是"配套"，且世界 y 混算会产生伪腿部空间
			if o["room"] != seat["room"]:
				continue
			var dir: Vector3 = o["aabb"].get_center() - seat["aabb"].get_center()
			dir.y = 0.0
			var fdist: float = dir.dot(fwd)
			var lateral: float = absf(dir.dot(right))
			if fdist < 0.05:
				continue
			# 横向偏移不能超过坐具半宽 + 0.10 m，否则是旁边的家具而不是"配套"
			if lateral > seat_half_w * 0.9 + 0.10:
				continue
			if fdist < best_fwd:
				best_fwd = fdist
				best = o
	return best

## 坐具后方拉出净距：靠背面 3 个横向采样点到最近家具/墙面的距离
func _back_clearance(e: Dictionary, comp: Dictionary, dir := Vector3.ZERO) -> Dictionary:
	var bb: AABB = e["aabb"]
	var fwd: Vector3 = e["fwd"]
	var right: Vector3 = e["right"]
	var half_d: float = _fwd_size(bb, fwd) * 0.5
	if dir != Vector3.ZERO:
		fwd = dir.normalized()
		right = fwd.cross(Vector3.UP).normalized()
		half_d = _fwd_size(bb, fwd) * 0.5
	var half_w: float = _fwd_size(bb, right) * 0.5
	var c := bb.get_center()
	# 多层：墙距按本层地面口径（attic 用阁楼地面）
	var lim_y: float = attic_floor if e["room"] == "attic" else fy
	var xlim: float = hw - wall_t
	var zlim: float = hd - wall_t
	var best := 1e9
	var best_at := Vector3.ZERO
	var best_who := "墙"
	for lat in [-0.5, 0.0, 0.5]:
		var p3: Vector3 = Vector3(c.x, 0, c.z) - fwd * (half_d + 0.001) + right * (half_w * lat)
		var pt := Vector2(p3.x, p3.z)
		var wd: float = minf(minf(pt.x + xlim, xlim - pt.x), minf(pt.y + zlim, zlim - pt.y))
		if wd < best:
			best = wd
			best_at = Vector3(pt.x, lim_y, pt.y)
			best_who = "墙"
		for o in props:
			if o == e or o == comp or o["wall"] or o["flat"] or o["room"] != e["room"]:
				continue
			if String(o["kind"]).contains("lamp"):
				continue
			var d := _xz_dist_point(o["aabb"], pt)
			if d < best:
				best = d
				best_at = Vector3(pt.x, lim_y, pt.y)
				best_who = String(o["kind"])
	return {"d": best, "at": best_at, "who": best_who}

## 坐具靠背面沿后退方向到墙内表面的距离
func _wall_dist_back(e: Dictionary) -> float:
	var bb: AABB = e["aabb"]
	var fwd: Vector3 = e["fwd"]
	var back := Vector3(bb.get_center().x, 0, bb.get_center().z) - fwd * (_fwd_size(bb, fwd) * 0.5)
	var xlim: float = hw - wall_t
	var zlim: float = hd - wall_t
	if absf(fwd.x) >= absf(fwd.z):
		return (xlim - back.x) if fwd.x < 0.0 else (back.x + xlim)
	return (zlim - back.z) if fwd.z < 0.0 else (back.z + zlim)

## 坐具前沿到配套家具的 XZ 间距（推入桌下时为 0）
func _front_gap(seat: Dictionary, other: Dictionary) -> float:
	return _xz_gap(seat["aabb"], other["aabb"])

func _check_relations() -> void:
	print("[SCENE] ---- 家具配合关系 ----")
	for kind in SEAT_KINDS:
		for e in _kind_entries(kind):
			var bb: AABB = e["aabb"]
			var fwd: Vector3 = e["fwd"]
			if kind == "shoe_bench":
				# lead m00366 C：换鞋座删除"后方拉出"，改查"前侧站立空间 ≥0.45 m"
				_ok(absf(bb.size.y - SHOE_BENCH_SEAT_H) <= 0.03,
					"shoe_bench(%s) 座高 %.2f ≈ %.2f（换鞋座）" % [e["room"], bb.size.y, SHOE_BENCH_SEAT_H])
				var ps: Vector3 = Vector3(bb.get_center().x, fy, bb.get_center().z) + fwd * (_fwd_size(bb, fwd) * 0.5 + 0.45)
				var hit_s := _solid_at(ps, e)
				_ok(hit_s == "" and _inside_room(ps), "shoe_bench(%s) 前侧 0.45 m 站立空间（遮挡：%s，在室内 %s）" % [
					e["room"], hit_s, str(_inside_room(ps))])
				continue
			# lead m00404 #2：只对餐椅/书桌椅（kind=chair）要求"后方拉出 ≥0.30"；
			# armchair/sofa/reading_chair 靠后不靠后拉通行，删除该检查；
			# 正后方不足 0.30 时，允许"侧后方 45° 可进入"作为附加判据（任一方向 ≥0.30 即 PASS）。
			var comp := _companion_of(e)
			if kind == "chair":
				var bc := _back_clearance(e, comp)
				var back_c: float = bc["d"]
				if back_c >= 0.30:
					_ok(true, "chair(%s) 后方拉出空间 %.2f ≥ 0.30 m%s" % [
						e["room"], back_c, "" if comp.is_empty() else "（配套 %s）" % comp["kind"]])
				else:
					var diag_ok := false
					var diag_msg := ""
					for ang in [45.0, -45.0]:
						var ddir: Vector3 = fwd.rotated(Vector3.UP, deg_to_rad(ang))
						var bcd := _back_clearance(e, comp, ddir)
						if float(bcd["d"]) >= 0.30 and not diag_ok:
							diag_ok = true
							diag_msg = "侧后方 %d° 净空 %.2f（%s @ %s）" % [int(ang), bcd["d"], bcd["who"], _fmt(bcd["at"])]
					_ok(diag_ok, "chair(%s) 后方拉出空间 %.2f < 0.30 m；侧后方 45° %s（正后方最近障碍 %s @ %s）" % [
						e["room"], back_c, "可进入" if diag_ok else "也不足", bc["who"], _fmt(bc["at"])])
					if diag_ok:
						print("    [SIDE-BACK] chair(%s) 正后方 %.2f，改为 %s" % [e["room"], back_c, diag_msg])
			if not comp.is_empty() and (comp["kind"] == "dining_table" or comp["kind"] == "desk"):
				var seat_h: float = SEAT_H
				# 腿部空间：桌面高 − 座面高 ∈ [0.20, 0.30]
				var table_top: float = comp["aabb"].position.y + comp["aabb"].size.y
				var leg: float = table_top - (bb.position.y + seat_h)
				_ok(leg >= 0.20 and leg <= 0.30,
					"%s(%s) %s桌面 %.2f − 座面 %.2f = %.2f ∈ [0.20,0.30]（腿部空间）" % [
						kind, e["room"], comp["kind"], table_top, bb.position.y + seat_h, leg])
				# 推到桌边时椅面前沿与桌沿关系：前沿距桌 AABB ≤0.12 m
				var front_pt: Vector3 = Vector3(bb.get_center().x, fy, bb.get_center().z) + fwd * (_fwd_size(bb, fwd) * 0.5)
				var edge_d := _xz_dist_point(comp["aabb"], Vector2(front_pt.x, front_pt.z))
				_ok(edge_d <= 0.12, "%s(%s) 椅面前沿距 %s 桌沿 %.2f ≤ 0.12 m（推入/刚抵桌沿）" % [
					kind, e["room"], comp["kind"], edge_d])
	# 书桌：桌下膝空间纵深 ≥0.44 m + 椅背到墙 ≥0.30 m（lead m00287）
	for desk in _kind_entries("desk"):
		var db: AABB = desk["aabb"]
		var knee_depth: float = _fwd_size(db, desk["fwd"])
		_ok(knee_depth >= 0.44, "desk(%s) 桌下膝空间纵深 %.2f ≥ 0.44 m" % [desk["room"], knee_depth])
		for ch in _kind_entries("chair"):
			if _companion_of(ch) == desk:
				var wd := _wall_dist_back(ch)
				_ok(wd >= 0.30, "desk 椅(%s) 椅背到墙 %.2f ≥ 0.30 m" % [ch["room"], wd])
	# 衣柜/矮柜抽屉操作高度区间
	for kind in ["wardrobe", "tall_cupboard", "sideboard", "nightstand"]:
		for e in _kind_entries(kind):
			var bb: AABB = e["aabb"]
			var top: float = bb.position.y + bb.size.y
			var floor_y: float = _expected_floor(e)
			_ok(top - floor_y >= 0.40 and top - floor_y <= 1.80,
				"%s(%s) 操作高度 %.3f ∈ [0.40, 1.80]" % [kind, e["room"], top - floor_y])
	# 台灯底部必须等于支撑台面
	for kind in ["table_lamp"]:
		for e in _kind_entries(kind):
			var sup := _find_support(e)
			_ok(not sup.is_empty(), "table_lamp(%s) 有支撑台面（%s）" % [e["room"], sup.get("kind", "无")])

# ============================================================
# 门：净宽 / 内侧 1.2 m 通行区 / 开启扫掠
# ============================================================
func _check_door() -> void:
	print("[SCENE] ---- 门：门洞 / 内侧 1.2 m 通行区 / 开启扫掠 ----")
	if door_pivot == null:
		_warn(false, "找不到 door_pivot，跳过门检查")
		return
	var leaf := _local_aabb_of(door_pivot)
	var xf := _cottage_xf(door_pivot)
	var cbb := _xf_aabb(xf, leaf)
	var leaf_w: float = leaf.size.x
	var leaf_h: float = cbb.size.y
	var want_leaf: float = DOOR_CLEAR_W - 2.0 * DOOR_FRAME
	_ok(absf(leaf_w - want_leaf) <= 0.02,
		"门扇宽 %.3f ≈ 门洞净宽 %.2f − 2×门框 %.2f = %.3f（±0.02，spec 派生）" % [
			leaf_w, DOOR_CLEAR_W, DOOR_FRAME, want_leaf])
	_ok(leaf_h >= 1.85 and leaf_h <= 2.10, "门扇高 %.3f ∈ [1.85, 2.10]（目标门洞净高 1.94）" % leaf_h)
	var pivot_pos: Vector3 = door_pivot.position
	var inner_z: float = hd - wall_t
	var zone_top: float = fy + 2.10
	# 内侧 1.2 m 通行区（门洞投影宽度 × 深 1.2，地面以上 2.1）
	var zone := AABB(Vector3(pivot_pos.x - 0.03, fy, inner_z - 1.20), Vector3(leaf_w + 0.06, zone_top - fy, 1.20))
	var blockers: Array = []
	for e in props:
		if e["wall"] or e["flat"]:
			continue
		var ov := _aabb_overlap(zone, e["aabb"])
		if ov.x > 0.01 and ov.z > 0.01 and ov.y > 0.01:
			blockers.append(String(e["kind"]))
	_ok(blockers.is_empty(), "门内侧 1.2 m 通行区内无家具（阻塞：%s）" % str(blockers))
	# 门板开启扫掠：main.gd 开门目标 rotation.y = -1.85（0 → -1.85 扇区，向外/门廊 +Z 扫）
	var sweep_pos := 0
	var pieces: Array = []
	for e in props:
		if e["flat"]:
			continue
		var ab: AABB = e["aabb"]
		var y_lo: float = maxf(ab.position.y, fy)
		var y_hi: float = minf(ab.position.y + ab.size.y, fy + 2.40)
		if y_hi <= y_lo:
			continue
		# 采样家具 XZ AABB 内部 5x5 点
		for ix in range(5):
			for iz in range(5):
				var px: float = ab.position.x + ab.size.x * (float(ix) / 4.0)
				var pz: float = ab.position.z + ab.size.z * (float(iz) / 4.0)
				var dx: float = px - pivot_pos.x
				var dz: float = pz - pivot_pos.z
				var rad: float = sqrt(dx * dx + dz * dz)
				if rad > leaf_w + 0.05 or rad < 0.02:
					continue
				var ang: float = atan2(-dz, dx)  # 门扇方向 (cosθ, -sinθ)
				if ang <= 0.02 and ang >= -1.87:
					sweep_pos += 1
					pieces.append("%s(%s)" % [e["kind"], _fmt(Vector3(px, fy, pz))])
					break
			if sweep_pos > 0:
				break
	_warn(true, "门板开启扫掠扇区诊断（r=%.2f, 0→-1.85 rad）：碰撞采样点 %d 个" % [leaf_w, sweep_pos])
	_ok(sweep_pos == 0, "门板开启不扫到家具（碰撞：%s）" % str(pieces.slice(0, 5)))

# ============================================================
# 楼梯：底部口 1.2 m 通道 / 地面家具不占楼梯投影 / 阁楼洞口禁放
# ============================================================
func _stair_rects_ground() -> Array:
	var rects: Array = []
	var fa: Dictionary = C.get("stair_flight_a", {})
	if not fa.is_empty():
		var x0: float = minf(float(fa.get("x0", 0.0)), float(fa.get("x1", 0.0)))
		var x1: float = maxf(float(fa.get("x0", 0.0)), float(fa.get("x1", 0.0)))
		var z0: float = minf(float(fa.get("z0", 0.0)), float(fa.get("z1", 0.0)))
		var z1: float = maxf(float(fa.get("z0", 0.0)), float(fa.get("z1", 0.0)))
		rects.append(Rect2(x0, z0, x1 - x0, z1 - z0))
	var fb: Dictionary = C.get("stair_flight_b", {})
	if not fb.is_empty():
		var bx0: float = minf(float(fb.get("x0", 0.0)), float(fb.get("x1", 0.0)))
		var bx1: float = maxf(float(fb.get("x0", 0.0)), float(fb.get("x1", 0.0)))
		var bz0: float = minf(float(fb.get("z0", 0.0)), float(fb.get("z1", 0.0)))
		var bz1: float = maxf(float(fb.get("z0", 0.0)), float(fb.get("z1", 0.0)))
		rects.append(Rect2(bx0, bz0, bx1 - bx0, bz1 - bz0))
	return rects

func _stair_mouth_point() -> Vector3:
	var fa: Dictionary = C.get("stair_flight_a", {})
	if fa.is_empty():
		return Vector3(hw * 0.6, fy, hd * 0.6)
	var ax: float = (float(fa.get("x0", 0.0)) + float(fa.get("x1", 0.0))) * 0.5
	var z0: float = maxf(float(fa.get("z0", 0.0)), float(fa.get("z1", 0.0)))
	return Vector3(ax, fy, z0 + 0.55)

func _check_stairs() -> void:
	print("[SCENE] ---- 楼梯：地面投影禁放 / 底部口 1.2 m 通道 / 阁楼洞口禁放 ----")
	var rects := _stair_rects_ground()
	_warn(not rects.is_empty(), "读到楼梯投影数据（%d 个矩形）" % rects.size())
	var bad: Array = []
	for e in props:
		if e["wall"] or e["flat"] or e["room"] != "ground":
			continue
		var bb: AABB = e["aabb"]
		for r in rects:
			var rr := r as Rect2
			if bb.position.x < rr.position.x + rr.size.x - 0.02 and bb.position.x + bb.size.x > rr.position.x + 0.02 \
					and bb.position.z < rr.position.y + rr.size.y - 0.02 and bb.position.z + bb.size.z > rr.position.y + 0.02:
				bad.append(String(e["kind"]))
	_ok(bad.is_empty(), "一层家具不占楼梯投影（占位：%s）" % str(bad))
	# 楼梯底部口：1.2 m 立方通行区无家具
	var mp := _stair_mouth_point()
	var fa: Dictionary = C.get("stair_flight_a", {})
	var aw: float = 0.0
	if not fa.is_empty():
		aw = absf(float(fa.get("x1", 0.0)) - float(fa.get("x0", 0.0)))
	var zone := AABB(Vector3(mp.x - aw * 0.5 - 0.18, fy, mp.z - 0.05), Vector3(aw + 0.36, 1.90, 1.25))
	var hits: Array = []
	for e in props:
		if e["wall"] or e["flat"] or e["room"] != "ground":
			continue
		var ov := _aabb_overlap(zone, e["aabb"])
		if ov.x > 0.01 and ov.z > 0.01 and ov.y > 0.01:
			var hb: AABB = e["aabb"]
			hits.append("%s@%s overlap(%.2f,%.2f,%.2f)" % [
				e["kind"], _fmt(Vector3(hb.get_center().x, hb.position.y, hb.get_center().z)), ov.x, ov.y, ov.z])
	_ok(hits.is_empty(), "楼梯底部口 1.2 m 通道无家具（阻塞：%s）" % str(hits))
	# 阁楼：家具不占楼梯洞口
	var holes: Array = []
	for key in ["stair_hole_r1", "stair_hole_r2"]:
		if C.has(key) and C[key] is Rect2:
			holes.append(C[key])
	var hole_offenders: Array = []
	for e in props:
		if e["wall"] or e["room"] != "attic":
			continue
		var bb: AABB = e["aabb"]
		for h in holes:
			var rr := h as Rect2
			if bb.position.x < rr.position.x + rr.size.x - 0.02 and bb.position.x + bb.size.x > rr.position.x + 0.02 \
					and bb.position.z < rr.position.y + rr.size.y - 0.02 and bb.position.z + bb.size.z > rr.position.y + 0.02:
				hole_offenders.append("%s@%s vs hole%s" % [e["kind"], _fmt(bb.get_center()), str(rr)])
	_ok(hole_offenders.is_empty(), "阁楼家具避开楼梯洞口（%d 个洞口；越界：%s）" % [holes.size(), str(hole_offenders)])

# ============================================================
# 一层通行性网格：门内侧 ↔ 楼梯口 / 各家具使用点
# ============================================================
func _grid_build(room: String = "ground") -> void:
	var floor_y: float = fy if room == "ground" else attic_floor
	var cell := 0.10
	var x0: float = -(hw - wall_t) + 0.06
	var x1: float = (hw - wall_t) - 0.06
	var z0: float = -(hd - wall_t) + 0.06
	var z1: float = (hd - wall_t) - 0.06
	var nx: int = int(floor((x1 - x0) / cell))
	var nz: int = int(floor((z1 - z0) / cell))
	var obs: Array = []
	for e in props:
		if e["wall"] or e["flat"] or e["room"] != room:
			continue
		var bb: AABB = e["aabb"]
		obs.append(AABB(Vector3(bb.position.x, floor_y, bb.position.z), Vector3(bb.size.x, 0.1, bb.size.z)))
	if room == "ground":
		for r in _stair_rects_ground():
			var rr := r as Rect2
			obs.append(AABB(Vector3(rr.position.x, floor_y, rr.position.y), Vector3(rr.size.x, 0.1, rr.size.y)))
	else:
		# 阁楼：楼梯洞口是"洞"（不能站人）
		for key in ["stair_hole_r1", "stair_hole_r2"]:
			if C.has(key) and C[key] is Rect2:
				var hr := C[key] as Rect2
				obs.append(AABB(Vector3(hr.position.x, floor_y, hr.position.y), Vector3(hr.size.x, 0.1, hr.size.y)))
	var clear := PackedFloat32Array()
	clear.resize(nx * nz)
	var min_clear := 1e9
	for iz in range(nz):
		for ix in range(nx):
			var px: float = x0 + (float(ix) + 0.5) * cell
			var pz: float = z0 + (float(iz) + 0.5) * cell
			var c: float = minf(minf(px - x0, x1 - px), minf(pz - z0, z1 - pz))
			for o in obs:
				c = minf(c, _xz_dist_point(o as AABB, Vector2(px, pz)))
			clear[iz * nx + ix] = c
			min_clear = minf(min_clear, c)
	grid = {"cell": cell, "x0": x0, "z0": z0, "nx": nx, "nz": nz, "clear": clear, "floor_y": floor_y, "room": room}
	print("[SCENE] ---- %s通行性网格：%d×%d cell=%.2f m（最大自由 clearance %.2f） ----" % [
		"阁楼" if room == "attic" else "一层", nx, nz, cell, _grid_max_clear()])

func _grid_max_clear() -> float:
	var cl: PackedFloat32Array = grid["clear"]
	var m := 0.0
	for c in cl:
		m = maxf(m, c)
	return m

func _grid_cell_of(p: Vector3) -> Vector2i:
	var cell: float = grid["cell"]
	var ix: int = int(floor((p.x - float(grid["x0"])) / cell))
	var iz: int = int(floor((p.z - float(grid["z0"])) / cell))
	return Vector2i(clampi(ix, 0, int(grid["nx"]) - 1), clampi(iz, 0, int(grid["nz"]) - 1))

func _grid_clear_at(p: Vector3) -> float:
	var c := _grid_cell_of(p)
	var nx: int = grid["nx"]
	var cl: PackedFloat32Array = grid["clear"]
	return cl[c.y * nx + c.x]

func _grid_reach(from: Vector3, to: Vector3, need: float) -> Dictionary:
	var nx: int = grid["nx"]
	var nz: int = grid["nz"]
	var cl: PackedFloat32Array = grid["clear"]
	var floor_y: float = float(grid.get("floor_y", fy))
	var start := _grid_cell_of(from)
	var goal := _grid_cell_of(to)
	if cl[start.y * nx + start.x] < need:
		return {"ok": false, "why": "起点 clearance %.2f < %.2f" % [cl[start.y * nx + start.x], need], "min": 0.0, "at": Vector3(from.x, floor_y, from.z)}
	if cl[goal.y * nx + goal.x] < need:
		return {"ok": false, "why": "终点 clearance %.2f < %.2f" % [cl[goal.y * nx + goal.x], need], "min": 0.0, "at": Vector3(to.x, floor_y, to.z)}
	var visited := PackedByteArray()
	visited.resize(nx * nz)
	var parent := PackedInt32Array()
	parent.resize(nx * nz)
	parent.fill(-1)
	var q: Array = [start]
	visited[start.y * nx + start.x] = 1
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var found := false
	while not q.is_empty():
		var cur: Vector2i = q.pop_front()
		if cur == goal:
			found = true
			break
		for d in dirs:
			var nb: Vector2i = cur + (d as Vector2i)
			if nb.x < 0 or nb.y < 0 or nb.x >= nx or nb.y >= nz:
				continue
			var idx := nb.y * nx + nb.x
			if visited[idx] == 1:
				continue
			if cl[idx] < need:
				continue
			visited[idx] = 1
			parent[idx] = cur.y * nx + cur.x
			q.append(nb)
	if not found:
		# 给出最接近终点的可通行 cell（用于定位阻塞）
		var best_i := 0
		var best_d := 1e9
		for i in range(nx * nz):
			if visited[i] == 1:
				var cx := i % nx
				var cy := i / nx
				var dd: float = float(abs(cx - goal.x) + abs(cy - goal.y))
				if dd < best_d:
					best_d = dd
					best_i = i
		var bx0: float = float(grid["x0"]) + (float(best_i % nx) + 0.5) * float(grid["cell"])
		var bz0: float = float(grid["z0"]) + (float(best_i / nx) + 0.5) * float(grid["cell"])
		return {"ok": false, "why": "不连通（最近可达点 clearance %.2f）" % cl[best_i], "min": cl[best_i],
			"at": Vector3(bx0, floor_y, bz0)}
	# 回溯求路径最小 clearance 及瓶颈位置
	var min_c := 1e9
	var min_idx := goal.y * nx + goal.x
	var idx2 := goal.y * nx + goal.x
	while idx2 >= 0:
		if cl[idx2] < min_c:
			min_c = cl[idx2]
			min_idx = idx2
		idx2 = parent[idx2]
	var bx: float = float(grid["x0"]) + (float(min_idx % nx) + 0.5) * float(grid["cell"])
	var bz: float = float(grid["z0"]) + (float(min_idx / nx) + 0.5) * float(grid["cell"])
	return {"ok": true, "why": "", "min": min_c, "at": Vector3(bx, floor_y, bz)}

func _check_passage() -> void:
	# 判定口径（lead m00366 B）：删除全部逐件"可自门内侧到达"检查，改为两条主通道净宽 + 门内侧站立圈。
	# 人体宽按 1.50 m 高的人形 0.36 m + 两侧各 0.10 m 余量推断 → 净宽 ≥0.55 m ⇔ clearance ≥0.275 m（2×0.275=0.55）。
	print("[SCENE] ---- 主通道净宽：①门内侧↔楼梯底 ②楼梯顶↔阁楼前区（净宽 ≥0.55 m） ----")
	var need := 0.275
	var inner_z: float = hd - wall_t
	var door_x: float = 0.0
	if door_pivot != null:
		door_x = door_pivot.position.x + _local_aabb_of(door_pivot).size.x * 0.5
	var door_pt := Vector3(door_x, fy, inner_z - 0.45)
	var mouth := _stair_mouth_point()
	var r_mouth := _grid_reach(door_pt, mouth, need)
	_ok(r_mouth["ok"], "① 门内侧 → 楼梯底部口 连通（%s；瓶颈 %s 净宽 %.2f m ≥ 0.55）" % [
		r_mouth["why"], _fmt(r_mouth.get("at", Vector3.ZERO)), float(r_mouth.get("min", 0.0)) * 2.0])
	var mouth_clear := _grid_clear_at(mouth) * 2.0
	_warn(mouth_clear >= 0.80, "楼梯底部口局部宽度 %.2f m ≥ 0.80 m（建议值，仅 WARN）" % mouth_clear)
	# ② 楼梯顶（flight_b 上口 x≈0.82, z≈-2.37）→ 阁楼前区（z>1.4 一带）
	_grid_build("attic")
	var attic_start := Vector3(1.70, attic_floor, -1.55)
	var attic_goal := Vector3(0.50, attic_floor, 1.50)
	var r_attic := _grid_reach(attic_start, attic_goal, need)
	_ok(r_attic["ok"], "② 楼梯顶 → 阁楼前区 连通（%s；瓶颈 %s 净宽 %.2f m ≥ 0.55）" % [
		r_attic["why"], _fmt(r_attic.get("at", Vector3.ZERO)), float(r_attic.get("min", 0.0)) * 2.0])
	# ③ 门内侧 1.2 m 站立圈：在 _check_door 内以"门内侧 1.2 m 通行区内无家具"单独判定
	print("  ③ 门内侧 1.2 m 站立圈：由 _check_door 判定（不重复计数）")

# ============================================================
# 灯光锚点随新尺寸
# ============================================================
func _check_lamp_lights() -> void:
	# 判定口径（lead m00287/00230）：
	#  1) 场景 light_sources（C 列表：吊灯/壁炉/门廊灯/阁楼灯/窗光）必须位于室内平面内、地面以上屋顶以下，
	#     range 对 2.42 m 一层净高/阁楼坡顶不过度溢出。
	#  2) 家具台灯/落地灯沿用 V3.1 自发光（Emissive glow + halo）方案，light_sources 里没有独立点光，
	#     故检查"灯罩中心是否被最近场景光源 range 覆盖"，无覆盖才 WARN（判定为暗角风险，不是几何错误）。
	#  3) 灯罩关键高度按家具 spec 反推：台灯罩中心=台面+0.385、罩下沿=台面+0.30；落地灯罩中心=地面+1.32。
	print("[SCENE] ---- 场景光源 ↔ 台灯/落地灯灯罩 + 照射范围对净高 ----")
	var lsrc: Array = light_sources
	var xf_inv: Transform3D = root3d.transform.affine_inverse()
	print("  light_sources 共 %d 个（世界坐标 / 小屋局部）：" % lsrc.size())
	for i in range(lsrc.size()):
		var ls: Dictionary = lsrc[i]
		var pw: Vector3 = ls.get("pos", Vector3.ZERO) # build 用 _world()，已是世界坐标
		var pl: Vector3 = xf_inv * pw
		var rng := float(ls.get("range", 0.0))
		var inten := float(ls.get("intensity", 0.0))
		print("    [#%d] world%s local%s range %.1f intensity %.2f" % [i, _fmt(pw), _fmt(pl), rng, inten])
		# lead m00404 #3：窗光贴在墙面/窗内，本就可能在"室内平面"外，删除平面位置判定（仅打印位置）；
		# 判定保留：高度在层内、range 合理、灯罩附近有光源（见下）。
		var plane_note := "室内" if _inside_room(pl, -0.05) else "墙面/窗外锚点（设计如此，不判 FAIL）"
		print("      光源#%d 平面位置：%s" % [i, plane_note])
		# 高度：地面以上 → 所在层顶部以下
		var y_hi: float = ridge_y if pl.y > attic_floor + 0.05 else ceiling_y
		var layer := "阁楼" if pl.y > attic_floor + 0.05 else "一层"
		_ok(pl.y >= fy + 0.02 and pl.y <= y_hi + 0.02,
			"光源#%d（%s）高度 local y=%.2f ∈ [%.2f, %.2f]" % [i, layer, pl.y, fy + 0.02, y_hi + 0.02])
		# range：合理区间 + 对净高溢出（净高 2.42；阁楼按光源上方到坡顶的距离）
		_warn(rng >= 1.0 and rng <= 6.0, "光源#%d range %.2f ∈ [1.0, 6.0]（对 2.42 m 净高的小屋尺度合理，不穿墙）" % [i, rng])
	var lamp_n := 0
	var uncovered := 0
	for kind in ["table_lamp", "floor_lamp"]:
		for e in _kind_entries(kind):
			lamp_n += 1
			var bb: AABB = e["aabb"]
			var shade_h: float = 0.20 if kind == "table_lamp" else 0.26
			var shade_top: float = bb.position.y + bb.size.y
			var shade_c := Vector3(bb.get_center().x, shade_top - shade_h * 0.5, bb.get_center().z)
			var shade_bot: float = shade_top - shade_h
			if kind == "table_lamp":
				var sup_top: float = _expected_floor(e)
				var sup := _find_support(e)
				if not sup.is_empty():
					var sb: AABB = sup["aabb"]
					sup_top = sb.position.y + sb.size.y
				var rel_c: float = shade_c.y - sup_top
				var rel_b: float = shade_bot - sup_top
				_ok(rel_c >= 0.36 and rel_c <= 0.41,
					"table_lamp(%s) 罩中心 = 台面 + %.3f ∈ [0.36,0.41]" % [e["room"], rel_c])
				_ok(rel_b >= 0.28 and rel_b <= 0.32,
					"table_lamp(%s) 罩下沿 = 台面 + %.3f ∈ [0.28,0.32]" % [e["room"], rel_b])
			else:
				var rel_f: float = shade_c.y - _expected_floor(e)
				_ok(rel_f >= 1.18 and rel_f <= 1.42,
					"floor_lamp(%s) 罩中心 = 地面 + %.3f ∈ [1.18,1.42]" % [e["room"], rel_f])
			# 灯罩中心 ↔ 最近场景光源：3D 距离是否在 range 覆盖内
			var bw := _cottage_to_world(shade_c)
			var best := 1e9
			var best_r := 0.0
			var best_dy := 0.0
			for ls in lsrc:
				var pw2: Vector3 = ls.get("pos", Vector3.ZERO)
				var d := (pw2 - bw).length()
				if d < best:
					best = d
					best_r = float(ls.get("range", 0.0))
					best_dy = absf(pw2.y - bw.y)
			if best <= 0.20 and best_dy <= 0.15:
				_ok(true, "%s(%s) 灯罩中心有独立 light_source（距离 %.2f，Δy %.2f）" % [kind, e["room"], best, best_dy])
			elif best <= maxf(best_r, 1.0):
				_ok(true, "%s(%s) 灯罩中心在最近场景光源 range %.1f 覆盖内（距离 %.2f；自发光方案无独立点光）" % [
					kind, e["room"], best_r, best])
			else:
				uncovered += 1
				_warn(false, "%s(%s) 灯罩中心不在任何光源 range 内（最近 %.2f > range %.1f，存在暗角风险）" % [
					kind, e["room"], best, best_r])
	print("  台灯/落地灯 %d 个：range 覆盖 %d，无覆盖 %d（自发光 glow+halo 仍可见）" % [lamp_n, lamp_n - uncovered, uncovered])

# ============================================================
# 阁楼净高（屋顶下皮）
# ============================================================
func _check_attic_headroom() -> void:
	print("[SCENE] ---- 阁楼净高（屋顶下皮限制） ----")
	if rh <= 0.01 or ridge_y <= 0.01:
		_warn(false, "缺 rh/ridge_y，跳过阁楼净高")
		return
	var slope: float = rh / hw
	var attics: Array = []
	for e in props:
		if e["room"] == "attic":
			attics.append(e)
	if attics.is_empty():
		_warn(false, "阁楼没有家具")
		return
	# 精确下皮：屋面板厚 ROOF_PANEL_T 在竖直方向的投影（cottage.gd 屋面板 0.14 / cos(pitch)）
	var bad := 0
	for e in attics:
		var bb: AABB = e["aabb"]
		var x_max: float = maxf(absf(bb.position.x), absf(bb.position.x + bb.size.x))
		var y_roof: float = _attic_roof_under(x_max)
		var top: float = bb.position.y + bb.size.y
		if top > y_roof - 0.02:
			bad += 1
			print("    [HEADROOM] %s top %.3f > 屋顶下皮 %.3f − 0.02（|x|max %.2f，需内移 %.2f m）" % [
				e["kind"], top, y_roof, x_max, (top - y_roof + 0.02) / maxf(0.01, tan(atan(rh / hw)))])
	_ok(bad == 0, "阁楼家具不穿屋顶下皮（越界 %d 件）" % bad)
	print("  attic_floor=%.2f ridge_y=%.2f slope=%.3f；阁楼家具 %d 件" % [attic_floor, ridge_y, slope, attics.size()])

# ============================================================
# 成本统计（家具 / 整屋 mesh-surface-triangle）
# ============================================================
func _cost_probe() -> void:
	print("[SCENE] ---- 渲染成本（合批后真实网格） ----")
	var prop_set: Dictionary = {}
	for e in props:
		prop_set[e["node"]] = true
	var meshes := 0
	var surf := 0
	var tris := 0
	var p_meshes := 0
	var p_surf := 0
	var p_tris := 0
	var mats: Dictionary = {}
	for node in _all_descendants(root3d):
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			if mi.mesh == null:
				continue
			meshes += 1
			surf += mi.mesh.get_surface_count()
			tris += mi.mesh.get_faces().size() / 3
			if mi.material_override != null:
				mats[mi.material_override.get_instance_id()] = true
			var owner_prop := _prop_owner(node)
			if owner_prop != null:
				p_meshes += 1
				p_surf += mi.mesh.get_surface_count()
				p_tris += mi.mesh.get_faces().size() / 3
	scene_cost = {"meshes": meshes, "surfaces": surf, "tris": tris, "mats": mats.size(),
		"prop_meshes": p_meshes, "prop_surfaces": p_surf, "prop_tris": p_tris, "props": props.size()}
	print("  全屋 meshes=%d surfaces=%d tris=%d 材质实例=%d" % [meshes, surf, tris, mats.size()])
	print("  家具 meshes=%d surfaces=%d tris=%d（%d 件，占 tris %.1f%%）" % [
		p_meshes, p_surf, p_tris, props.size(),
		100.0 * float(p_tris) / maxf(1.0, float(tris))])

func _all_descendants(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		out.append(c)
		out.append_array(_all_descendants(c))
	return out

func _prop_owner(node: Node) -> Node:
	var p: Node = node.get_parent()
	while p != null:
		if p.has_meta("prop_kind"):
			return p
		if p == root3d:
			return null
		p = p.get_parent()
	return null

# ============================================================
# 汇总
# ============================================================
func _print_summary() -> void:
	print("[SCENE] ---- 汇总 ----")
	print("  checks=%d pass=%d warn=%d fail=%d props=%d" % [checks, pass_n, warn_n, fail_n, props.size()])
	if not fail_msgs.is_empty():
		print("  主要失败项（前 10）：")
		for i in range(mini(10, fail_msgs.size())):
			print("    - " + String(fail_msgs[i]))
	var c := scene_cost
	print("[SCENE] RESULT checks=%d pass=%d warn=%d fail=%d props=%d attic_props=%d meshes=%d surfaces=%d tris=%d prop_tris=%d" % [
		checks, pass_n, warn_n, fail_n, props.size(),
		_count_room("attic"), int(c.get("meshes", 0)), int(c.get("surfaces", 0)),
		int(c.get("tris", 0)), int(c.get("prop_tris", 0))])
	if fail_n == 0:
		print("[SCENE] RESULT_OK 场景级家具布局校验通过")

func _count_room(room: String) -> int:
	var n := 0
	for e in props:
		if e["room"] == room:
			n += 1
	return n
