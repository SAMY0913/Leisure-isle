extends SceneTree

## P7.1 路由探针：打印岛民可行走图（户外节点/边）、砾石路折线、五盏路灯世界坐标（P7.1 删门前一盏），
## 以及"农田→钓点"当前最短路与候选直连段的几何代价（路灯/围栏/台面/床面/地形高差）。
## 只读。用法：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path 游戏工程 --script res://tools/probe_p9_route.gd -- --out=DIR

const S := preload("res://scripts/isle_villager_spots.gd")
const W := preload("res://scripts/world.gd")
const CAL := preload("res://scripts/isle_calendar.gd")

const DEFAULT_OUT := "D:/休闲小岛幻境/开发产物/P9/P7/after/route"
var _out_dir: Variant = DEFAULT_OUT
var _lines: Array = []
var _main: Node = null
var _graph: Dictionary = {}
var _pass := 0
var _fail := 0
var _fails: Array = []


func _initialize() -> void:
	for raw in OS.get_cmdline_user_args():
		var s: Variant = String(raw)
		if s.begins_with("--out="):
			var v: Variant = s.substr(6).strip_edges()
			while v.ends_with("/") or v.ends_with(String.chr(92)):
				v = v.substr(0, v.length() - 1)
			if v != "":
				_out_dir = v
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()


func _run() -> void:
	print("=== P7.1 route probe ===")
	await _boot()
	_dump_nodes()
	_dump_edges()
	_dump_paths()
	_dump_lamps()
	_dump_current_route()
	_dump_candidates()
	_audit_all_pairs()
	_assert_after_fix()
	_write()
	print("[SUMMARY] checks=%d fail=%d" % [_pass, _fail])
	print("[RESULT] ", "PASS" if _fail == 0 else "FAIL")
	quit(0 if _fail == 0 else 1)


func _boot() -> void:
	var ps: Variant = load("res://isle.tscn") as PackedScene
	var inst: Variant = ps.instantiate()
	root.add_child(inst)
	_main = inst
	_main.set_process(false)
	_main.set("_mode", 1)
	for i in range(4):
		await process_frame
	_main.set("_time_source", "sim")
	_main.set("_realtime", false)
	_main.set("_paused", true)
	_main.call("_on_time_set", 12.0 * 3600.0)
	var cottage: Dictionary = _main.get("_cottage")
	_graph = S.build(cottage)
	var world: Dictionary = _main.get("_world")
	print("[PROBE] nodes=%d spots=%d lamps=%d perches=%d" % [
		int((_graph["nodes"] as Dictionary).size()),
		int((_graph["spots"] as Dictionary).size()),
		int((world.get("lamps", []) as Array).size()),
		int((world.get("perches", []) as Array).size())])


func _p(x: float, z: float) -> void:
	_lines.append("[PT] %.4f %.4f" % [x, z])


func _emit(s: String) -> void:
	print(s)
	_lines.append(s)


func _nodes() -> Dictionary:
	return _graph["nodes"] as Dictionary


func _pos(id: String) -> Vector3:
	var n: Dictionary = _nodes()
	return (n[id] as Dictionary)["pos"] as Vector3


func _adj() -> Dictionary:
	return _graph["adj"] as Dictionary


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


func _dump_nodes() -> void:
	_emit("[NODES]")
	for id in (_nodes().keys() as Array):
		var n: Dictionary = _nodes()[id]
		if String(n["region"]) != "outdoor":
			continue
		var p: Vector3 = n["pos"]
		_emit("[NODE] %s %.4f %.4f %.4f mode=%s" % [String(id), p.x, p.y, p.z, String(n["mode"])])


func _dump_edges() -> void:
	_emit("[EDGES]")
	var adj: Dictionary = _adj()
	var outdoors := {}
	for id in (_nodes().keys() as Array):
		if String((_nodes()[id] as Dictionary)["region"]) == "outdoor":
			outdoors[id] = true
	for a in adj.keys():
		if not outdoors.has(a):
			continue
		for b in (adj[a] as Array):
			if not outdoors.has(b):
				continue
			if String(a) > String(b):
				continue
			_emit("[EDGE] %s %s %.4f" % [String(a), String(b), _flat(_pos(a), _pos(b))])


func _dump_paths() -> void:
	_emit("[PATHS]")
	var segs: PackedVector2Array = W._path_segs
	var widths: PackedFloat32Array = W._path_widths
	var i := 0
	while i + 1 < segs.size():
		var a: Vector2 = segs[i]
		var b: Vector2 = segs[i + 1]
		var w: float = widths[i >> 1]
		_emit("[PATHSEG] %d %.4f %.4f %.4f %.4f w=%.3f len=%.4f" % [i >> 1, a.x, a.y, b.x, b.y, w, a.distance_to(b)])
		i += 2
	# 农田支路（世界折线）
	var from := W.YARD_PATH_FROM
	var gate := W.YARD_PATH_GATE
	for k in range(6):
		var t := float(k) / 5.0
		var l := from.lerp(gate, t)
		var wpt := W._yard_l2w(l.x, l.y)
		_emit("[SPUR] %.4f %.4f local=%.3f,%.3f" % [wpt.x, wpt.y, l.x, l.y])


func _dump_lamps() -> void:
	_emit("[LAMPS]")
	var world: Dictionary = _main.get("_world")
	var lamps: Array = world.get("lamps", [])
	for entry in lamps:
		var info: Dictionary = (entry as Array)[3]
		var base: Vector3 = info["base"]
		var lantern: Vector3 = info["lantern"]
		var clearance: float = W._path_clearance(base.x, base.z)
		var nearest := 9999.0
		var nearest_id := ""
		for id in (_nodes().keys() as Array):
			var n: Dictionary = _nodes()[id]
			if String(n["region"]) != "outdoor":
				continue
			var d := Vector2(base.x, base.z).distance_to(Vector2((n["pos"] as Vector3).x, (n["pos"] as Vector3).z))
			if d < nearest:
				nearest = d
				nearest_id = String(id)
		_emit("[LAMP] %s base=%.4f,%.4f y=%.4f lantern=%.4f,%.4f path_clear=%.4f nearest_node=%s d=%.4f" % [
			String(info["name"]), base.x, base.z, base.y, lantern.x, lantern.z,
			clearance, nearest_id, nearest])
	var fy: Dictionary = world.get("front_yard", {})
	var metrics: Dictionary = fy.get("lamps", {})
	for nm in metrics.keys():
		var rec: Dictionary = metrics[nm]
		var l: Vector2 = rec["local"]
		_emit("[LAMPMETRIC] %s local=%.4f,%.4f in_pad=%s pad_y=%.4f base_y=%.4f buried=%.4f to_pad_edge=%.4f" % [
			String(nm), l.x, l.y, str(rec["in_pad"]), float(rec["pad_y"]),
			float(rec["base_y"]), float(rec["buried"]), float(rec["dist_to_pad_edge"])])
	var perches: Array = world.get("perches", [])
	_emit("[PERCH_TOTAL] %d" % perches.size())


func _dijkstra(from_id: String, to_id: String) -> Dictionary:
	var nodes: Dictionary = _nodes()
	var adj: Dictionary = _adj()
	var dist := {}
	var prev := {}
	var open: Array = [from_id]
	for id in nodes.keys():
		dist[id] = 1.0e18
	dist[from_id] = 0.0
	while not open.is_empty():
		var best := -1
		var bestv := 1.0e18
		for i in range(open.size()):
			var v := float(dist[open[i]])
			if v < bestv:
				bestv = v
				best = i
		var cur := String(open[best])
		open.remove_at(best)
		if cur == to_id:
			break
		for nb in (adj.get(cur, []) as Array):
			var nn := String(nb)
			var w := _flat((nodes[cur] as Dictionary)["pos"], (nodes[nn] as Dictionary)["pos"])
			if float(dist[cur]) + w < float(dist[nn]) - 0.0000001:
				dist[nn] = float(dist[cur]) + w
				prev[nn] = cur
				open.append(nn)
	var path: Array = []
	var cur2 := to_id
	while cur2 != "":
		path.push_front(cur2)
		cur2 = String(prev.get(cur2, ""))
	return {"path": path, "dist": float(dist.get(to_id, -1.0))}


func _dump_current_route() -> void:
	_emit("[ROUTE_CURRENT]")
	for pair in [["yard_gate_in", "shore_stand"], ["yard_gate_out", "shore_stand"], ["yard_slot_0", "shore_stand"], ["lawn", "shore_stand"]]:
		var from_id := String(pair[0])
		var to_id := String(pair[1])
		var r: Dictionary = _dijkstra(from_id, to_id)
		var path: Array = r["path"]
		if path.is_empty() or String(path[0]) != from_id:
			_emit("[ROUTE] %s->%s UNREACHABLE" % [from_id, to_id])
			continue
		var hops: Array = []
		var total := 0.0
		var sharp := 0
		var backtracks := 0
		for i in range(path.size()):
			var id := String(path[i])
			if i > 0:
				var d := _flat(_pos(String(path[i - 1])), _pos(id))
				total += d
				hops.append("%s(%.2f)" % [id, d])
			else:
				hops.append(id)
		# sharp turn count (angle > 120 deg) and axis backtracks
		for i in range(1, path.size() - 1):
			var a := _pos(String(path[i - 1]))
			var b := _pos(String(path[i]))
			var c := _pos(String(path[i + 1]))
			var v1 := Vector2(b.x - a.x, b.z - a.z)
			var v2 := Vector2(c.x - b.x, c.z - b.z)
			if v1.length() > 0.001 and v2.length() > 0.001:
				if rad_to_deg(v1.angle_to(v2)) > 120.0 or rad_to_deg(v1.angle_to(v2)) < -120.0:
					sharp += 1
		var straight := _flat(_pos(from_id), _pos(to_id))
		_emit("[ROUTE] %s->%s total=%.4f straight=%.4f ratio=%.4f hops=%d sharp_turns=%d seq=%s" % [
			from_id, to_id, total, straight, total / maxf(straight, 0.001), path.size(), sharp, " -> ".join(hops)])


func _seg_stats(a: Vector3, b: Vector3) -> Dictionary:
	var lamps: Array = (_main.get("_world") as Dictionary).get("lamps", [])
	var samples := 21
	var min_lamp := 9999.0
	var min_lamp_name := ""
	var max_clear := -9999.0
	var min_clear := 9999.0
	var max_dy := 0.0
	var pad_frac := 0.0
	var terrain_frac := 0.0
	var fence_min := 9999.0
	var fy: Dictionary = (_main.get("_world") as Dictionary).get("front_yard", {})
	var posts: Array = (fy.get("fence", {}) as Dictionary).get("posts_local", [])
	for k in range(samples):
		var t := float(k) / float(samples - 1)
		var p := a.lerp(b, t)
		var c: float = W._path_clearance(p.x, p.z)
		max_clear = maxf(max_clear, c)
		min_clear = minf(min_clear, c)
		var l: Vector2 = W._yard_w2l(p.x, p.z)
		if W._yard_pad_contains(l.x, l.y, 0.0):
			pad_frac += 1.0 / float(samples)
		else:
			terrain_frac += 1.0 / float(samples)
		var y_terrain: float = W.surface_y(p.x, p.z)
		var y_pad: float = W._yard_pad_y(l.x, l.y) + W.YARD_FLOOR_LIFT
		var y_here: float = y_pad if W._yard_pad_contains(l.x, l.y, 0.0) else y_terrain
		if k > 0:
			var tprev := float(k - 1) / float(samples - 1)
			var pp := a.lerp(b, tprev)
			var lp: Vector2 = W._yard_w2l(pp.x, pp.z)
			var y_prev: float = (W._yard_pad_y(lp.x, lp.y) + W.YARD_FLOOR_LIFT) if W._yard_pad_contains(lp.x, lp.y, 0.0) else W.surface_y(pp.x, pp.z)
			max_dy = maxf(max_dy, absf(y_here - y_prev))
		for entry in lamps:
			var info: Dictionary = (entry as Array)[3]
			var base: Vector3 = info["base"]
			var d := Vector2(p.x, p.z).distance_to(Vector2(base.x, base.z))
			if d < min_lamp:
				min_lamp = d
				min_lamp_name = String(info["name"])
		for pl in posts:
			var wpl: Vector2 = W._yard_l2w(pl.x, pl.y)
			fence_min = minf(fence_min, Vector2(p.x, p.z).distance_to(wpl))
	return {"len": _flat(a, b), "min_lamp": min_lamp, "min_lamp_name": min_lamp_name,
		"min_clear": min_clear, "max_clear": max_clear, "max_step_dy": max_dy,
		"pad_frac": pad_frac, "terrain_frac": terrain_frac, "fence_min": fence_min}


func _dump_candidates() -> void:
	_emit("[CANDIDATES]")
	var pairs: Array = [
		["yard_path_a", "lawn"],
		["yard_path_a", "front_path_1"],
		["yard_path_a", "garden_0"],
		["garden_0", "front_path_1"],
		["yard_path_a", "front_path_2"],
		["garden_0", "front_path_2"],
	]
	for pair in pairs:
		var a := _pos(String(pair[0]))
		var b := _pos(String(pair[1]))
		var st := _seg_stats(a, b)
		_emit("[CAND] %s -> %s len=%.4f min_lamp=%.4f(%s) clear=[%.4f..%.4f] max_step_dy=%.4f pad=%.2f terrain=%.2f fence_min=%.4f" % [
			String(pair[0]), String(pair[1]), float(st["len"]), float(st["min_lamp"]),
			String(st["min_lamp_name"]), float(st["min_clear"]), float(st["max_clear"]),
			float(st["max_step_dy"]), float(st["pad_frac"]), float(st["terrain_frac"]), float(st["fence_min"])])
	# 候选新节点：农田支路北端与花园支路之间（世界）
	for probe in [Vector2(1.20, 7.10), Vector2(1.44, 6.62), Vector2(2.20, 6.40)]:
		var l: Vector2 = W._yard_w2l(probe.x, probe.y)
		var in_pad: bool = W._yard_pad_contains(l.x, l.y, 0.0)
		_emit("[PROBE_PT] %.4f,%.4f local=%.4f,%.4f in_pad=%s path_clear=%.4f y_terrain=%.4f pad_y=%.4f" % [
			probe.x, probe.y, l.x, l.y, str(in_pad), W._path_clearance(probe.x, probe.y),
			W.surface_y(probe.x, probe.y), W._yard_pad_y(l.x, l.y) + W.YARD_FLOOR_LIFT])


func _chk(nm: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		_fails.append(nm + " | " + detail)
	_emit("[CHECK] %s %s %s" % [nm, "PASS" if ok else "FAIL", detail])


func _route_stats(path: Array) -> Dictionary:
	var total := 0.0
	var sharp := 0
	for i in range(1, path.size()):
		total += _flat(_pos(String(path[i - 1])), _pos(String(path[i])))
	for i in range(1, path.size() - 1):
		var a := _pos(String(path[i - 1]))
		var b := _pos(String(path[i]))
		var c := _pos(String(path[i + 1]))
		var v1 := Vector2(b.x - a.x, b.z - a.z)
		var v2 := Vector2(c.x - b.x, c.z - b.z)
		if v1.length() > 0.001 and v2.length() > 0.001:
			var ang := rad_to_deg(v1.angle_to(v2))
			if ang > 120.0 or ang < -120.0:
				sharp += 1
	return {"total": total, "sharp": sharp, "hops": path.size()}


## 全节点对最短路审计：每个可走节点对跑一次 Dijkstra，统计
## 绕行比（实际最短路 / 直线距离）、>120° 折返次数，并列出最差 15 对。
## 目标不是"一切都直"，而是把明显绕圈/无谓回头的边找出来（本次据此新增 yard_path_a↔lawn）。
func _audit_all_pairs() -> void:
	_emit("[AUDIT]")
	# 只审计户外节点：屋内/阁楼节点在 2D 平面上互相重叠（阁楼就在一层正上方，直线距离≈0
	# 而实际必须下楼梯），混进来会让 ratio 变成噪声；用户报告的绕路也只发生在户外。
	# 距离一律用 3D，避免坡大的岸线被低估。
	var ids: Array = []
	for id in (_nodes().keys() as Array):
		if String((_nodes()[id] as Dictionary)["region"]) == "outdoor":
			ids.append(id)
	ids.sort()
	var ratios: Array = []
	var worst: Array = []
	var sharp_pairs := 0
	var unreachable := 0
	var n := 0
	for i in range(ids.size()):
		for j in range(i + 1, ids.size()):
			var a := String(ids[i])
			var b := String(ids[j])
			var path: Array = (_dijkstra(a, b)["path"] as Array)
			if path.size() < 2:
				unreachable += 1
				continue
			var st := _route_stats(path)
			var total3 := 0.0
			for k2 in range(1, path.size()):
				total3 += _pos(String(path[k2 - 1])).distance_to(_pos(String(path[k2])))
			var straight := _pos(a).distance_to(_pos(b))
			var ratio := total3 / maxf(straight, 0.001)
			n += 1
			ratios.append(ratio)
			if int(st["sharp"]) > 0:
				sharp_pairs += 1
			worst.append({"a": a, "b": b, "total": total3, "straight": straight,
				"ratio": ratio, "sharp": int(st["sharp"]), "hops": int(st["hops"]), "path": path})
	ratios.sort()
	var mean := 0.0
	for x in ratios:
		mean += float(x)
	mean /= maxf(1.0, float(ratios.size()))
	var p95 := 0.0
	if not ratios.is_empty():
		p95 = float(ratios[mini(ratios.size() - 1, int(floor(float(ratios.size()) * 0.95)))])
	worst.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["ratio"]) > float(y["ratio"]))
	_emit("[AUDIT_SUM] pairs=%d unreachable=%d mean_ratio=%.4f p95_ratio=%.4f max_ratio=%.4f sharp_pairs=%d" % [
		n, unreachable, mean, p95, float((worst[0] as Dictionary)["ratio"]) if not worst.is_empty() else 0.0, sharp_pairs])
	for k in range(mini(15, worst.size())):
		var w: Dictionary = worst[k]
		_emit("[AUDIT_WORST] %s->%s total=%.3f straight=%.3f ratio=%.3f sharp=%d hops=%d seq=%s" % [
			String(w["a"]), String(w["b"]), float(w["total"]), float(w["straight"]),
			float(w["ratio"]), int(w["sharp"]), int(w["hops"]), " -> ".join(w["path"])])


## 本次 P7.1 改动后的断言（农田出口直连 + 门前路灯删除 + 接驳铺装）。
func _assert_after_fix() -> void:
	_emit("[ASSERT]")
	var world: Dictionary = _main.get("_world")
	var lamps: Array = world.get("lamps", [])
	_chk("env.lamp_count", lamps.size() == 5, "actual=%d" % lamps.size())
	_chk("env.gardenlamp1_removed", _main.find_child("GardenLamp1", true, false) == null,
		"node_found=%s" % str(_main.find_child("GardenLamp1", true, false) != null))
	var adj: Dictionary = _adj()
	var e1: bool = (adj.get("yard_path_a", []) as Array).has("lawn")
	var e2: bool = (adj.get("lawn", []) as Array).has("yard_path_a")
	_chk("graph.edge_yard_path_a_lawn", e1 and e2, "fwd=%s rev=%s" % [str(e1), str(e2)])
	# 每对改动前/后实测（m）：gate_in 37.1827 -> 30.6813，gate_out 36.7327 -> 30.2313，
	# slot_0 38.6827 -> 32.1813，room_in 27.5959。阈值按改动后实测留约 2.3~2.5% 余量；
	# 三对都缩短约 6.5 m，来自接驳铺装 + yard_path_a<->lawn 边（两者缺一都做不到）。
	var limits := {"yard_gate_in": 31.5, "yard_slot_0": 33.0, "room_in": 28.5}
	for pair in [["yard_gate_in", "shore_stand"], ["yard_slot_0", "shore_stand"], ["room_in", "shore_stand"]]:
		var from_id := String(pair[0])
		var to_id := String(pair[1])
		var path: Array = (_dijkstra(from_id, to_id)["path"] as Array)
		var st := _route_stats(path)
		var straight := _flat(_pos(from_id), _pos(to_id))
		var tag := from_id + "_to_" + to_id
		_chk("route." + tag + ".reaches", path.size() >= 2, "hops=%d" % path.size())
		_chk("route." + tag + ".no_garden_detour", not path.has("garden_1") and not path.has("garden_0"),
			"seq=" + " -> ".join(path))
		var lim := float(limits.get(from_id, 33.0))
		_chk("route." + tag + ".total", float(st["total"]) <= lim,
			"total=%.3f limit=%.2f" % [float(st["total"]), lim])
		_chk("route." + tag + ".sharp", int(st["sharp"]) <= 1, "sharp=%d" % int(st["sharp"]))
		_chk("route." + tag + ".ratio", float(st["total"]) / maxf(straight, 0.001) <= 1.32,
			"ratio=%.3f straight=%.3f" % [float(st["total"]) / maxf(straight, 0.001), straight])
	# 接驳铺装：最后一段 = 出田口 -> 门前草坪，宽 0.50，几何与 yard 支路端点对齐
	var segs: PackedVector2Array = W._path_segs
	var widths: PackedFloat32Array = W._path_widths
	_chk("pave.seg_count", segs.size() == 32 and widths.size() == 16,
		"segs=%d widths=%d" % [segs.size(), widths.size()])
	if segs.size() >= 2:
		var a: Vector2 = segs[segs.size() - 2]
		var b: Vector2 = segs[segs.size() - 1]
		var fx: Vector2 = W._yard_l2w(W.YARD_PATH_FROM.x, W.YARD_PATH_FROM.y)
		var lw: Vector2 = W._yard_l2w(0.0, 5.95)
		var geom_ok := (a.distance_to(fx) < 0.02 and b.distance_to(lw) < 0.02) or \
			(a.distance_to(lw) < 0.02 and b.distance_to(fx) < 0.02)
		_chk("pave.connector_geom", geom_ok, "a=%.4f,%.4f b=%.4f,%.4f" % [a.x, a.y, b.x, b.y])
		_chk("pave.connector_len", absf(a.distance_to(b) - 1.63) <= 0.15, "len=%.4f" % a.distance_to(b))
		_chk("pave.connector_width", absf(float(widths[widths.size() - 1]) - 0.50) <= 0.001,
			"w=%.3f" % float(widths[widths.size() - 1]))


func _write() -> void:
	var path := String(_out_dir) + "/probe_p9_route.log"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")
		f.close()
	print("[PROBE] wrote %s lines=%d" % [path, _lines.size()])
