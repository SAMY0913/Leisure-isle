extends SceneTree
## P9 / P4-CLOSE —— 中心格（slot 4）真实可达性的几何/路径契约探针（headless）。
##
## 目的：为「岛民踩上前排苗床顶面、走到中心格操作站位」这一最小修复提供可复现的
## 实测证据，覆盖四件必须分开确认的事：
##   A. 图节点/边走行契约（导航目标点可达）
##   B. 站位高度与上台剖面（身体不会被埋进床体、不会浮空过高）
##   C. 站位到中心格格心的水平距离 <= 1.30 m（P4 交互臂展判据）
##   D. 0.5 m 草坪缝仍然不可通行（缝内无节点、床面节点之间无跨缝边）
##
## 运行：ENG --headless --path GAME --script res://tools/probe_p4c_bed_access.gd -- --out=DIR
## 纪律：只读正式场景事实，不写存档、不改农田/库存、不注入时间。

const SPOTS := preload("res://scripts/isle_villager_spots.gd")
const WORLD := preload("res://scripts/world.gd")

const DEFAULT_OUT := "D:/休闲小岛幻境/开发产物/P9/P4/bed_access"
const BED_TOP_TOL := 0.002
const STEP_TOL := 0.002
const REACH := 1.30

var out_dir := DEFAULT_OUT
var _pass := 0
var _fail := 0
var _lines: Array = []
var _fail_names: Array = []
var _main: Node = null
var _villager: Node = null
var _nodes: Dictionary = {}
var _adj: Dictionary = {}
var _facts: Dictionary = {}
var _slots: Array = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--out="):
			out_dir = s.substr(6).strip_edges().trim_suffix("/").trim_suffix("\\")
	if out_dir == "":
		out_dir = DEFAULT_OUT
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	print("[P4C] out=%s headless=%s godot=%s" % [out_dir,
		str(DisplayServer.get_name() == "headless"),
		String(Engine.get_version_info().get("string", ""))])
	await _boot()
	if _main == null:
		print("[RESULT] FAIL")
		quit(1)
		return
	_section_graph()
	_section_heights()
	_section_reach()
	_section_gap_invariant()
	_section_step_profile()
	_section_route()
	_write()
	print("[SUMMARY] checks=%d fail=%d" % [_pass + _fail, _fail])
	print("[RESULT] ", "PASS" if _fail == 0 else "FAIL")
	quit(0 if _fail == 0 else 1)


func _check(name: String, ok: bool, expected: String, actual: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		_fail_names.append(name)
	print("[CHECK] %s | expected=%s actual=%s | %s" % [name, expected, actual, "PASS" if ok else "FAIL"])
	_lines.append("[CHECK] %s | expected=%s actual=%s | %s" % [name, expected, actual, "PASS" if ok else "FAIL"])


func _section(t: String) -> void:
	print("")
	print("== ", t, " ==")
	_lines.append("")
	_lines.append("== " + t + " ==")


func _boot() -> void:
	_section("0. 正式场景加载")
	var ps := load("res://isle.tscn") as PackedScene
	_check("env.scene_load", ps != null, "isle.tscn 可加载", str(ps != null))
	if ps == null:
		return
	_main = ps.instantiate()
	if _main == null:
		_check("env.scene_instance", false, "实例化成功", "null")
		return
	root.add_child(_main)
	_main.set_process(false)
	_main.set("_mode", 1)
	for i in range(4):
		await process_frame
	_villager = _main.get("_villager")
	_check("env.villager", _villager != null, "岛民实例存在", str(_villager))
	if _villager == null:
		return
	var graph: Dictionary = _villager.get("graph")
	_nodes = graph.get("nodes", {})
	_adj = graph.get("adj", {})
	var world_facts: Dictionary = _main.get("_world")
	_facts = world_facts.get("front_yard", {})
	_slots = _facts.get("slots", [])
	_check("env.facts_9", _slots.size() == 9, "9", str(_slots.size()))
	_check("env.bed_top", float(_facts.get("beds", {}).get("bed_top_y", 0.0)) > 7.0,
		">7.0", str(_facts.get("beds", {}).get("bed_top_y", 0.0)))


func _pad() -> float:
	return WORLD._yard_pad_y(WORLD.YARD_FARM_C.x, WORLD.YARD_FARM_C.y) + WORLD.YARD_FLOOR_LIFT


func _bed_top() -> float:
	return float(_facts.get("beds", {}).get("bed_top_y", 0.0))


func _slot_world(idx: int) -> Vector2:
	for row in _slots:
		var d: Dictionary = row
		if int(d.get("index", -1)) == idx:
			return d.get("world", Vector2.ZERO)
	return Vector2.ZERO


func _nxz(nid: String) -> Vector2:
	if not _nodes.has(nid):
		return Vector2(9999, 9999)
	var p: Vector3 = (_nodes[nid] as Dictionary)["pos"]
	return Vector2(p.x, p.z)


func _ny(nid: String) -> float:
	return float(((_nodes[nid] as Dictionary)["pos"] as Vector3).y)


func _section_graph() -> void:
	_section("A. 图节点与建图校验（导航目标点可达的前提）")
	var issues: Array = SPOTS.validate(_villager.get("graph"))
	_check("graph.validate_clean", issues.is_empty(), "无几何问题", str(issues))
	for nid in ["yard_bed_step", "yard_bed_up", "yard_slot_4"]:
		_check("graph.has_" + nid, _nodes.has(nid), "存在", str(_nodes.has(nid)))
	if not (_nodes.has("yard_slot_4") and _nodes.has("yard_bed_step") and _nodes.has("yard_bed_up")):
		return
	_check("graph.slot4_region", String((_nodes["yard_slot_4"] as Dictionary)["region"]) == "outdoor",
		"outdoor", str((_nodes["yard_slot_4"] as Dictionary)["region"]))
	_check("graph.slot4_mode", String((_nodes["yard_slot_4"] as Dictionary)["mode"]) == "yard_bed",
		"yard_bed", str((_nodes["yard_slot_4"] as Dictionary)["mode"]))
	var p := SPOTS.find_path(_villager.get("graph"), "garden_0", "yard_slot_4")
	_check("graph.path_garden0_slot4", p.size() >= 3, ">=3 个节点", str(p))
	_check("graph.path_uses_step", p.has("yard_bed_step"), "经过 yard_bed_step", str(p))
	_check("graph.path_uses_up", p.has("yard_bed_up"), "经过 yard_bed_up", str(p))
	_check("graph.path_uses_gate", p.has("yard_gate_in"), "经过 yard_gate_in", str(p))
	print("[P4C] path garden_0 -> yard_slot_4 = %s" % str(p))
	# 走道 8 格节点仍可达（回归：新边没有破坏原有环）
	for key in [0, 1, 2, 3, 5, 6, 7, 8]:
		var nid2: String = String({0: "yard_slot_0", 1: "yard_gate_in", 2: "yard_slot_2", 3: "yard_slot_3",
			5: "yard_slot_5", 6: "yard_slot_6", 7: "yard_slot_7", 8: "yard_slot_8"}[key])
		var p2 := SPOTS.find_path(_villager.get("graph"), "garden_0", nid2)
		_check("graph.path_garden0_" + nid2, p2.size() >= 2, ">=2", str(p2.size()))


func _section_heights() -> void:
	_section("B1. 站位高度：走道面 / 床顶面")
	if not (_nodes.has("yard_bed_step") and _nodes.has("yard_bed_up") and _nodes.has("yard_slot_4")):
		_check("height.nodes_present", false, "节点存在", "missing")
		return
	var pad := _pad()
	var bed := _bed_top()
	var walk_y := _ny("yard_slot_0")
	_check("height.walkway_node_y", absf(walk_y - pad) <= BED_TOP_TOL, str(pad), str(walk_y))
	_check("height.step_on_walkway", absf(_ny("yard_bed_step") - pad) <= STEP_TOL, str(pad), str(_ny("yard_bed_step")))
	_check("height.up_on_bed_top", absf(_ny("yard_bed_up") - bed) <= STEP_TOL, str(bed), str(_ny("yard_bed_up")))
	_check("height.slot4_on_bed_top", absf(_ny("yard_slot_4") - bed) <= STEP_TOL, str(bed), str(_ny("yard_slot_4")))
	_check("height.rise_0m20", absf((_ny("yard_slot_4") - _ny("yard_bed_step")) - WORLD.YARD_BED_RISE) <= STEP_TOL,
		str(WORLD.YARD_BED_RISE), str(_ny("yard_slot_4") - _ny("yard_bed_step")))


func _section_reach() -> void:
	_section("C. 交互臂展：站位到九格格心的水平距离")
	if not _nodes.has("yard_slot_4"):
		return
	var station := _nxz("yard_slot_4")
	var dist4 := station.distance_to(_slot_world(4))
	print("[P4C] station=%s slot4_center=%s dist=%.4f" % [str(station), str(_slot_world(4)), dist4])
	_check("reach.slot4_within", dist4 <= REACH, "<=%.2f" % REACH, "%.4f" % dist4)
	var near: Array = []
	for row in _slots:
		var d: Dictionary = row
		var dd := station.distance_to(d.get("world", Vector2.ZERO))
		near.append("slot%d=%.3f" % [int(d.get("index", -1)), dd])
	_check("reach.slot4_is_the_target", dist4 <= REACH and dist4 > 1.0, "1.0<d<=1.3", "%.4f" % dist4)
	print("[P4C] distances from station: %s" % ", ".join(near))
	# 站位到本床（slot 1）作物中心的距离：成熟作物最大水平展 0.40（西瓜藤），身体半径 0.10
	var crop_d := station.distance_to(_slot_world(1))
	_check("reach.own_bed_crop_clearance", crop_d - 0.40 - 0.10 > 0.0,
		">0（叶展 0.40 + 身体 0.10）", "%.4f" % (crop_d - 0.50))
	print("[P4C] station -> own-bed crop center = %.4f (crop reach 0.40 + body 0.10)" % crop_d)


func _slot_cell(idx: int) -> Vector2:
	# 九格床心局部坐标 = YARD_FARM_C + (i-1, j-1)*1.5，index = i + 3j
	var i := idx % 3
	var j := int(idx / 3)
	return WORLD.YARD_FARM_C + Vector2(float(i - 1), float(j - 1)) * WORLD.YARD_BED_CELL * 1.5


func _in_bed_top(p: Vector2, c: Vector2) -> bool:
	# 床顶面：中心 c、半宽 0.48、圆角 0.14+0.02（与 world.gd _yard_build_beds 一致）
	var h := 0.48
	var r := WORLD.YARD_BED_CORNER + 0.02
	var dx := absf(p.x - c.x)
	var dz := absf(p.y - c.y)
	if dx > h + 1e-6 or dz > h + 1e-6:
		return false
	if dx <= h - r or dz <= h - r:
		return true
	var ox := dx - (h - r)
	var oz := dz - (h - r)
	return ox * ox + oz * oz <= r * r + 1e-9


func _section_gap_invariant() -> void:
	_section("D. 0.5 m 草坪缝仍然不可通行（不变量）")
	var bed := _bed_top()
	# D1: 站在床顶高度的节点，必须落在某张床的顶面内（不允许悬在缝上）
	var on_bed: Array = []
	var offenders: Array = []
	for id in _nodes.keys():
		var n: Dictionary = _nodes[id]
		var pos: Vector3 = n["pos"]
		if absf(pos.y - bed) > 0.02:
			continue
		var lx: float
		var lz: float
		var loc: Vector3 = n["local"]
		if String(n["mode"]) == "yard_bed":
			lx = loc.x
			lz = loc.z
		else:
			continue
		var ok := false
		for idx in range(9):
			if _in_bed_top(Vector2(lx, lz), _slot_cell(idx)):
				ok = true
				break
		on_bed.append(id)
		if not ok:
			offenders.append(id)
	_check("gap.bed_nodes_inside_beds", offenders.is_empty(), "无悬缝节点", str(offenders))
	_check("gap.bed_nodes_min_count", on_bed.size() >= 2, ">=2 个床面节点", str(on_bed))
	print("[P4C] bed-top nodes = %s" % str(on_bed))
	# D2: 床面节点之间的边不跨床（两端必须落在同一张床上）
	var cross: Array = []
	for a in _adj.keys():
		for b in (_adj[a] as PackedStringArray):
			var sa := String(a)
			var sb := String(b)
			if sa > sb:
				continue
			if not (_nodes.has(sa) and _nodes.has(sb)):
				continue
			var na: Dictionary = _nodes[sa]
			var nb: Dictionary = _nodes[sb]
			var both_bed := absf(float((na["pos"] as Vector3).y) - bed) <= 0.02 \
				and absf(float((nb["pos"] as Vector3).y) - bed) <= 0.02
			if not both_bed:
				continue
			var la: Vector3 = na["local"]
			var lb: Vector3 = nb["local"]
			var same := false
			for idx in range(9):
				var c := _slot_cell(idx)
				if _in_bed_top(Vector2(la.x, la.z), c) and _in_bed_top(Vector2(lb.x, lb.z), c):
					same = true
					break
			if not same:
				cross.append(sa + "-" + sb)
	_check("gap.no_cross_bed_edges", cross.is_empty(), "无跨床边", str(cross))
	# D3: 相邻床之间 0.5 m 草坪缝的窄带内没有节点
	var strips := _strips()
	var in_gap: Array = []
	for id2 in _nodes.keys():
		var n2: Dictionary = _nodes[id2]
		if String(n2["region"]) != "outdoor":
			continue
		var m2 := String(n2["mode"])
		if m2 != "yard" and m2 != "yard_bed":
			continue
		var l2: Vector3 = n2["local"]
		for st in strips:
			if _in_strip(Vector2(l2.x, l2.z), st):
				in_gap.append(id2)
				break
	_check("gap.no_node_in_bed_gaps", in_gap.is_empty(), "缝内无节点", str(in_gap))
	# D4: 没有任何一条边走线横穿草坪缝（缝只能绕行，床面节点只连本床/走道）
	var cross_strip: Array = []
	for a2 in _adj.keys():
		for b2 in (_adj[a2] as PackedStringArray):
			var sa2 := String(a2)
			var sb2 := String(b2)
			if sa2 > sb2 or not (_nodes.has(sa2) and _nodes.has(sb2)):
				continue
			var la2: Vector3 = (_nodes[sa2] as Dictionary)["local"]
			var lb2: Vector3 = (_nodes[sb2] as Dictionary)["local"]
			for st3 in strips:
				if _segment_hits_strip(Vector2(la2.x, la2.z), Vector2(lb2.x, lb2.z), st3):
					cross_strip.append(sa2 + "-" + sb2)
					break
	_check("gap.no_edge_crosses_bed_gaps", cross_strip.is_empty(), "无边横穿缝", str(cross_strip))
	print("[P4C] gap strips=%d nodes_in_gap=%s edges_crossing=%s" % [
		strips.size(), str(in_gap), str(cross_strip)])


## 九格相邻床之间的 0.5 m 草坪缝带（yard-local 坐标 AABB）
func _strips() -> Array:
	var out: Array = []
	for j in range(3):
		for i in range(2):
			var a := _slot_cell(i + 3 * j)
			var b := _slot_cell((i + 1) + 3 * j)
			out.append({"x0": minf(a.x, b.x) + 0.50, "x1": maxf(a.x, b.x) - 0.50,
				"z0": a.y - 0.50, "z1": a.y + 0.50})
	for j in range(2):
		for i in range(3):
			var a2 := _slot_cell(i + 3 * j)
			var b2 := _slot_cell(i + 3 * (j + 1))
			out.append({"x0": a2.x - 0.50, "x1": a2.x + 0.50,
				"z0": minf(a2.y, b2.y) + 0.50, "z1": maxf(a2.y, b2.y) - 0.50})
	return out


func _in_strip(p: Vector2, s: Dictionary) -> bool:
	return p.x > float(s["x0"]) + 1e-6 and p.x < float(s["x1"]) - 1e-6 \
		and p.y > float(s["z0"]) + 1e-6 and p.y < float(s["z1"]) - 1e-6


func _segment_hits_strip(a: Vector2, b: Vector2, s: Dictionary) -> bool:
	for k in range(65):
		if _in_strip(a.lerp(b, float(k) / 64.0), s):
			return true
	return false


func _surface_y_at(x: float, z: float, bed_center: Vector2, bed_top: float, pad: float) -> float:
	# 床体在 x=const 剖面上的外轮廓高度：底环 ±0.50 / 顶环 ±0.48（圆角 0.14/0.16）
	var hb := 0.50
	var rb := WORLD.YARD_BED_CORNER
	var ht := 0.48
	var rt := WORLD.YARD_BED_CORNER + 0.02
	var dx := absf(x - bed_center.x)
	var base_edge := bed_center.y - hb
	if dx > hb - rb:
		var ox := dx - (hb - rb)
		base_edge += rb - sqrt(maxf(rb * rb - ox * ox, 0.0))
	var top_edge := bed_center.y - ht
	if dx > ht - rt:
		var ox2 := dx - (ht - rt)
		top_edge += rt - sqrt(maxf(rt * rt - ox2 * ox2, 0.0))
	if z <= base_edge:
		return pad
	if z >= top_edge:
		return bed_top
	var t := (z - base_edge) / maxf(top_edge - base_edge, 1e-6)
	return pad + (bed_top - pad) * t


func _section_step_profile() -> void:
	_section("B2. 上台剖面：走道 → 床沿 → 床顶（脚不入土、不浮空过高）")
	if not (_nodes.has("yard_bed_step") and _nodes.has("yard_bed_up")):
		return
	var pad := _pad()
	var bed := _bed_top()
	# 上台剖面全部在 yard-local 帧里计算（yard 节点的 local 就是院面局部坐标）
	var lw: Vector3 = (_nodes["yard_bed_step"] as Dictionary)["local"]
	var le: Vector3 = (_nodes["yard_bed_up"] as Dictionary)["local"]
	var ls: Vector3 = (_nodes["yard_slot_4"] as Dictionary)["local"]
	var w := Vector2(lw.x, lw.z)
	var e := Vector2(le.x, le.z)
	var cell := _slot_cell(1)
	var wy := _ny("yard_bed_step")
	var ey := _ny("yard_bed_up")
	var seg := w.distance_to(e)
	var max_sink := 0.0
	var max_float := 0.0
	var mono := true
	var prev_y := -9999.0
	var steps := 400
	for k in range(steps + 1):
		var t := float(k) / float(steps)
		var p := w.lerp(e, t)
		var y := lerpf(wy, ey, t)
		if y < prev_y - 1e-6:
			mono = false
		prev_y = y
		var surf := _surface_y_at(p.x, p.y, cell, bed, pad)
		max_sink = maxf(max_sink, surf - y)
		max_float = maxf(max_float, y - surf)
	# 床顶行走段（E->S）必须保持在同一水平面
	var flat_ok := absf(_ny("yard_slot_4") - _ny("yard_bed_up")) <= STEP_TOL
	print("[P4C] step segment len=%.3f m rise=%.3f m grade=%.2f max_sink=%.4f max_lift=%.4f" % [
		seg, ey - wy, (ey - wy) / maxf(seg, 1e-6), max_sink, max_float])
	_check("step.segment_short", seg > 0.15 and seg < 0.40, "0.15~0.40 m", "%.3f" % seg)
	_check("step.rise_is_bed_height", absf((ey - wy) - WORLD.YARD_BED_RISE) <= STEP_TOL,
		str(WORLD.YARD_BED_RISE), "%.4f" % (ey - wy))
	_check("step.no_ground_sink", max_sink <= 0.02, "<=0.02 m（脚不入土）", "%.4f" % max_sink)
	_check("step.rise_monotonic", mono, "y 单调上升（无下陷/回弹）", str(mono))
	# 线性 y 插值（与门廊台阶同一 _walk_step 机制）在 0.23 m 内抬升 0.20 m 时，
	# 上台中段脚底会高于床壁斜面，最大约 0.14 m —— 这是「抬脚上台」的轮廓，
	# 与门廊 5 级台阶（每级 0.14 m）同一机制。这里只约束不得悬空过高。
	_check("step.lift_bounded", max_float <= 0.16, "<=0.16 m（与台阶机制一致）", "%.4f" % max_float)
	_check("step.bed_walk_flat", flat_ok, "床顶两节点同高", "%.4f" % (_ny("yard_slot_4") - _ny("yard_bed_up")))
	# 走道路径：yard_bed_step 必须在 2.05~2.65 m 环带内（不占用 0.5 m 草缝）
	var r := Vector2(w.x, w.y).distance_to(WORLD.YARD_FARM_C)
	_check("step.on_walkway_band", r >= WORLD.YARD_WALK_INNER and r <= WORLD.YARD_WALK_OUTER,
		"2.05~2.65", "%.3f" % r)
	# 床顶行走段：yard_bed_up -> yard_slot_4 全程贴着床顶面
	var s := Vector2(ls.x, ls.z)
	var d := e.distance_to(s)
	var full := s.distance_to(cell)
	print("[P4C] bed walk segment=%.3f m, station to own-bed center=%.3f" % [d, full])
	_check("step.bed_walk_len", d > 0.5 and d < 0.95, "0.5~0.95 m", "%.3f" % d)


func _section_route() -> void:
	_section("E. 巡田路线：slot 4 有真实节点，且无空节点")
	var route: Array = _main.call("_build_farm_patrol_route")
	_check("route.count_9", route.size() == 9, "9", str(route.size()))
	var empty_nodes: Array = []
	var slot4_row: Dictionary = {}
	for row in route:
		var d: Dictionary = row
		if String(d.get("node", "")) == "":
			empty_nodes.append(int(d.get("slot", -1)))
		if int(d.get("slot", -1)) == 4:
			slot4_row = d
	_check("route.no_empty_nodes", empty_nodes.is_empty(), "无空节点", str(empty_nodes))
	_check("route.slot4_node", String(slot4_row.get("node", "")) == "yard_slot_4",
		"yard_slot_4", String(slot4_row.get("node", "")))
	_check("route.slot4_point", slot4_row.get("point") != null, "非 null", str(slot4_row.get("point")))
	if slot4_row.get("point") != null:
		var gp: Vector3 = slot4_row["point"]
		var dd := Vector2(gp.x, gp.z).distance_to(_slot_world(4))
		_check("route.slot4_point_dist", dd <= REACH, "<=1.30", "%.4f" % dd)
		# point 与节点同点 => 不会再追加一个 goal waypoint（_plan_path 的 0.02 m 规则）
		_check("route.slot4_point_is_node", gp.distance_to((_nodes["yard_slot_4"] as Dictionary)["pos"]) <= 0.02,
			"与节点同点", "differ")
	# 其余 8 格节点未改动（回归）
	for row2 in route:
		var d2: Dictionary = row2
		var nid3 := String(d2.get("node", ""))
		_check("route.node_exists_" + str(int(d2.get("slot", -1))), _nodes.has(nid3), "存在", nid3)
	# P7-FINALIZE：巡田改为每轮随机顺序，不再断言"最后一格是 slot 4"；
	# 只要 route 含 slot 4（中心格可达/可操作）且九格齐全、各出现一次即可。
	var slot_order: Array = []
	for row3 in route:
		slot_order.append(int((row3 as Dictionary).get("slot", -1)))
	var slot_order_sorted: Array = slot_order.duplicate()
	slot_order_sorted.sort()
	_check("route.contains_slot4", slot_order.has(4),
		"route 含 slot 4（中心格）", str(slot_order))
	_check("route.all_slots_once", slot_order_sorted == [0, 1, 2, 3, 4, 5, 6, 7, 8],
		"九格齐全且每格恰好一次（顺序随机无关）", str(slot_order))


func _write() -> void:
	var log_path := out_dir + "/probe_p4c_bed_access.log"
	var fa := FileAccess.open(log_path, FileAccess.WRITE)
	if fa != null:
		fa.store_string("\n".join(_lines) + "\n")
		fa.close()
	var data := {"checks": _pass + _fail, "fail": _fail, "fail_names": _fail_names,
		"bed_top_y": _bed_top(), "pad_y": _pad(),
		"stations": {"yard_bed_step": _nodes.get("yard_bed_step", {}).get("pos", null),
			"yard_bed_up": _nodes.get("yard_bed_up", {}).get("pos", null),
			"yard_slot_4": _nodes.get("yard_slot_4", {}).get("pos", null)},
		"slot4_world": _slot_world(4)}
	var jf := FileAccess.open(out_dir + "/probe_p4c_bed_access.json", FileAccess.WRITE)
	if jf != null:
		jf.store_string(JSON.stringify(data, "  "))
		jf.close()
	print("[P4C] log=", log_path)
