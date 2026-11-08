extends SceneTree
## P2A / Subagent A —— 房屋/门廊/地形/道路 临时测量探针（本阶段专用，正式代码零引用）。
## 运行：
##   "$ENG" --path "D:/休闲小岛幻境/游戏工程" --headless --script res://tools/_p2a_a_measure.gd
##   "$ENG" --path "D:/休闲小岛幻境/游戏工程" --headless --script res://tools/_p2a_a_measure.gd -- --pads=a:-5,2.6,3.1,10.9
## 全部数值来自真实函数（isle_math.terrain_height / world.surface_y / world.trail_clearance /
## cottage.build 返回的运行时 meta），不手抄公式。stdout 打印 MD 表格 + JSON 原文写盘。

const M := preload("res://scripts/isle_math.gd")
const W := preload("res://scripts/world.gd")
const CT := preload("res://scripts/cottage.gd")

const OUT_JSON := "D:/休闲小岛幻境/开发产物/P9/P2A/reviews/A_house_terrain.json"

var _s := 0.0
var _c := 1.0
var _j := {}

func _initialize() -> void:
	_s = sin(M.HOUSE_YAW)
	_c = cos(M.HOUSE_YAW)
	W._prepare()
	var gy: float = M.house_ground_y()
	_j["meta"] = {
		"godot": Engine.get_version_info()["string"],
		"capture": "headless runtime",
		"yaw_deg": _r(rad_to_deg(M.HOUSE_YAW)),
		"sin": _r(_s), "cos": _r(_c),
		"house_ground_y": _r(gy),
	}
	var dw: Vector3 = M.door_world()
	var da: Vector3 = M.door_approach()
	_j["anchors"] = {
		"house_origin_world": _v3(Vector3(M.HOUSE_X, gy, M.HOUSE_Z)),
		"house_front_dir": _v3(M.house_front()),
		"door_world": _v3(dw),
		"door_local": _v2(_w2l(Vector2(dw.x, dw.z))),
		"door_world_minus_ground": _r(dw.y - gy),
		"approach_world": _v3(da),
		"approach_local": _v2(_w2l(Vector2(da.x, da.z))),
		"approach_y_minus_ground": _r(da.y - gy),
		"approach_y_minus_terrain_there": _r(da.y - M.terrain_height(da.x, da.z)),
		"terrain_rel_ground_at_door_local": _r(M.terrain_height(dw.x, dw.z) - gy),
	}
	print("### ANCHORS")
	print("house_ground_y=", _r(gy), " door_world=", _v3(dw), " door_local=", _v2(_w2l(Vector2(dw.x, dw.z))))
	print("approach_world=", _v3(da), " approach_local=", _v2(_w2l(Vector2(da.x, da.z))), " da.y-gy=", _r(da.y - gy))

	# ---------------- terrain table ----------------
	var lxs: Array = []
	for i in range(10):
		lxs.append(-6.0 + float(i))
	var lzs: Array = []
	for i in range(15):
		lzs.append(3.0 + float(i))
	var tbl: Array = []
	var tbls: Array = []
	for lz in lzs:
		var row: Array = []
		var rows: Array = []
		for lx in lxs:
			var p := _f2w(lx, lz)
			row.append(_r(M.terrain_height(p.x, p.z)))
			rows.append(_r(W.surface_y(p.x, p.z)))
		tbl.append(row)
		tbls.append(rows)
	_j["terrain_table"] = {"lx": lxs, "lz": lzs, "terrain_height": tbl, "surface_h": tbls}
	print("### TERRAIN_TABLE (M.terrain_height)")
	print("lz\\lx|" + _hdr(lxs))
	for i in range(lzs.size()):
		print("%.0f|" % lzs[i] + _row(tbl[i]))
	print("### SURFACE_TABLE (world.surface_y = _h, 含草丘)")
	for i in range(lzs.size()):
		print("%.0f|" % lzs[i] + _row(tbls[i]))

	# ---------------- slope rows ----------------
	var slope_rows: Array = []
	var lz2 := 3.0
	while lz2 <= 17.001:
		var hs: Array = []
		var ss: Array = []
		var lx2 := -6.0
		while lx2 <= 3.001:
			var p := _f2w(lx2, lz2)
			hs.append(M.terrain_height(p.x, p.z))
			ss.append(_slope(p.x, p.z))
			lx2 += 0.5
		var hm := 0.0
		var sm := 0.0
		var smax := -1.0
		for h in hs:
			hm += h
		for s in ss:
			sm += s
			smax = maxf(smax, s)
		hm /= float(hs.size())
		sm /= float(ss.size())
		slope_rows.append({"lz": _r(lz2), "h_mean": _r(hm), "slope_mean": _r(sm), "slope_max": _r(smax)})
		lz2 += 0.5
	_j["slope_rows"] = slope_rows
	print("### SLOPE_ROWS (terrain_normal, deg; lx=-6..3 均值/最大)")
	print("lz|h_mean|slope_mean|slope_max")
	for r in slope_rows:
		print("%.1f|%.3f|%.2f|%.2f" % [r["lz"], r["h_mean"], r["slope_mean"], r["slope_max"]])

	# ---------------- door axis profile ----------------
	var axis: Array = []
	var lz3 := 3.0
	while lz3 <= 12.001:
		var p := _f2w(0.0, lz3)
		axis.append({"lz": _r(lz3), "h_rel": _r(W.surface_y(p.x, p.z) - gy),
			"t_rel": _r(M.terrain_height(p.x, p.z) - gy), "slope": _r(_slope(p.x, p.z)),
			"clear": _r(W.trail_clearance(p.x, p.z))})
		lz3 += 0.25
	_j["door_axis_profile"] = axis
	print("### DOOR_AXIS (lx=0)")
	print("lz|h_rel(gy)|terrain_rel|slope|path_clear")
	for a in axis:
		print("%.2f|%.3f|%.3f|%.2f|%.3f" % [a["lz"], a["h_rel"], a["t_rel"], a["slope"], a["clear"]])

	# ---------------- front wall / plinth exposure ----------------
	var front: Array = []
	var lx3 := -4.4
	while lx3 <= 4.401:
		var p := _f2w(lx3, 3.28)
		var rel: float = M.terrain_height(p.x, p.z) - gy
		front.append({"lx": _r(lx3), "t_rel": _r(rel), "plinth_exposed": _r(0.55 - rel),
			"h_rel": _r(W.surface_y(p.x, p.z) - gy)})
		lx3 += 0.4
	_j["front_line_lz3p28"] = front
	print("### FRONT_LINE lz=3.28 (plinth cap edge; exposed = 0.55 - terrain_rel)")
	print("lx|t_rel|plinth_exposed|h_rel")
	for f in front:
		print("%.2f|%.3f|%.3f|%.3f" % [f["lx"], f["t_rel"], f["plinth_exposed"], f["h_rel"]])

	# ---------------- flat walkable spans per lz ----------------
	var flat_lzs: Array = []
	var lz4 := 5.0
	while lz4 <= 12.001:
		var spans := _flat_spans(lz4)
		flat_lzs.append({"lz": _r(lz4), "spans": spans})
		lz4 += 0.5
	_j["flat_spans"] = flat_lzs
	print("### FLAT_SPANS (slope<=8deg, clearance>=0.15, not house/porch/garden/field)")
	for r in flat_lzs:
		var txt := ""
		for s in r["spans"]:
			txt += " [%.2f,%.2f]" % [s[0], s[1]]
		print("lz=%.1f :%s" % [r["lz"], txt])

	# ---------------- paths in local frame ----------------
	var segs: Array = []
	var seg_n := W._path_segs.size() / 2
	for i in range(seg_n):
		var a: Vector2 = W._path_segs[i * 2]
		var b: Vector2 = W._path_segs[i * 2 + 1]
		segs.append({"i": i, "w": _r(W._path_widths[i]),
			"a_local": _v2(_w2l(a)), "b_local": _v2(_w2l(b)),
			"a_world": _v2(a), "b_world": _v2(b),
			"len": _r(a.distance_to(b))})
	_j["path_segs_local"] = segs
	print("### PATH_SEGS (local; w=_path_widths, clearance 按半径用)")
	for s in segs:
		print("#%d w=%.2f len=%.2f  local %s -> %s" % [s["i"], s["w"], s["len"],
			_v2s(s["a_local"]), _v2s(s["b_local"])])

	var bands: Array = []
	var lz5 := 3.0
	while lz5 <= 11.001:
		bands.append({"lz": _r(lz5), "spans": _path_spans(lz5)})
		lz5 += 0.25
	_j["path_bands"] = bands
	print("### PATH_BANDS (trail_clearance<0 => on dirt band)")
	for r in bands:
		var txt := ""
		for s in r["spans"]:
			txt += " [%.2f,%.2f]" % [s[0], s[1]]
		print("lz=%.2f :%s" % [r["lz"], txt])

	# ---------------- road centreline heights ----------------
	var road: Array = []
	var arc := 0.0
	var poly: PackedVector2Array = W._path_polyline(0, 3)
	while arc <= 22.0:
		var smp: Array = W._sample_path(poly, arc)
		var c: Vector2 = smp[0]
		road.append({"arc": _r(arc), "local": _v2(_w2l(c)), "h_rel": _r(W.surface_y(c.x, c.y) - gy),
			"slope": _r(_slope(c.x, c.y))})
		arc += 0.5
	_j["main_path_centre_heights"] = road
	print("### MAIN_PATH_CENTRE (arc from door_approach)")
	print("arc|local(lx,lz)|h_rel(gy)|slope")
	for r in road:
		print("%.1f|%s|%.3f|%.2f" % [r["arc"], _v2s(r["local"]), r["h_rel"], r["slope"]])

	# ---------------- garden / field bounds ----------------
	var grects: Array = [
		{"name": "garden_fence", "x0": W.GARDEN_X0, "x1": W.GARDEN_X1, "z0": W.GARDEN_Z0, "z1": W.GARDEN_Z1},
		{"name": "old_field", "x0": W.FIELD_X0, "x1": W.FIELD_X1, "z0": W.FIELD_Z0, "z1": W.FIELD_Z1},
	]
	var fa3: Vector3 = _f2w(-3.8, 3.10)
	var fb3: Vector3 = _f2w(3.8, 3.10)
	var front_a := Vector2(fa3.x, fa3.z)
	var front_b := Vector2(fb3.x, fb3.z)
	var door2 := Vector2(dw.x, dw.z)
	var bounds: Array = []
	for r in grects:
		var cs: Array = [Vector2(r["x0"], r["z0"]), Vector2(r["x1"], r["z0"]),
			Vector2(r["x1"], r["z1"]), Vector2(r["x0"], r["z1"])]
		var dmin := 1.0e9
		var dmp := Vector2.ZERO
		for i in range(4):
			var a: Vector2 = cs[i]
			var b: Vector2 = cs[(i + 1) % 4]
			var steps := maxi(2, int(a.distance_to(b) / 0.05))
			for k in range(steps + 1):
				var p: Vector2 = a.lerp(b, float(k) / float(steps))
				var d: float = _dist_point_seg2(p, front_a, front_b)
				if d < dmin:
					dmin = d
					dmp = p
		var loc: Array = []
		for c in cs:
			loc.append(_v2(_w2l(c)))
		bounds.append({"name": r["name"], "world_corners": [_v2(cs[0]), _v2(cs[1]), _v2(cs[2]), _v2(cs[3])],
			"local_corners": loc, "min_dist_to_front_wall": _r(dmin),
			"nearest_world": _v2(dmp), "nearest_local": _v2(_w2l(dmp)),
			"min_dist_to_door": _r(_rect_dist(cs, door2))})
	# beds
	var beds: Array = []
	for br in W._bed_rects:
		var cs2: Array = [Vector2(br.x, br.z), Vector2(br.y, br.z), Vector2(br.y, br.w), Vector2(br.x, br.w)]
		var loc2: Array = []
		for c in cs2:
			loc2.append(_v2(_w2l(c)))
		beds.append({"local_corners": loc2, "world_corners": [_v2(cs2[0]), _v2(cs2[1]), _v2(cs2[2]), _v2(cs2[3])]})
	_j["bounds"] = {"rects": bounds, "beds": beds}
	print("### BOUNDS")
	for b in bounds:
		print(b["name"], " world=", _arr2s(b["world_corners"]), " local=", _arr2s(b["local_corners"]))
		print("   min_dist_to_front_wall=", b["min_dist_to_front_wall"], " nearest_local=", _v2s(b["nearest_local"]),
			" min_dist_to_door=", b["min_dist_to_door"])
	for i in range(beds.size()):
		print("bed%d local=" % i, _arr2s(beds[i]["local_corners"]))

	# ---------------- cottage runtime metas ----------------
	var parent := Node3D.new()
	var cres: Dictionary = CT.build(parent)
	var croot: Node3D = cres["root"]
	var C: Dictionary = croot.get_meta("cottage_ctx")
	var psteps := croot.get_node_or_null("PorchSteps")
	var porch: Dictionary = {
		"root_y": _r(croot.position.y),
		"fy": _r(float(C.get("fy", 0.0))),
		"hd": _r(float(C.get("hd", 0.0))),
		"deck_top": _r(float(C.get("deck_top", 0.0))),
		"wall_t": _r(float(C.get("wall_t", 0.0))),
		"roof_base": _r(float(C.get("roof_base", 0.0))),
		"door_opening": _v3_or(C.get("door_opening")),
		"door_clear": _safe(C.get("door_clear")),
		"step_count": psteps.get_meta("step_count", -1) if psteps else -1,
		"step_rise": _r(float(psteps.get_meta("rise", 0.0))) if psteps else 0.0,
		"step_run": _r(float(psteps.get_meta("run", 0.0))) if psteps else 0.0,
		"step_top_y": _r(float(psteps.get_meta("top_y", 0.0))) if psteps else 0.0,
		"step_bottom_y": _r(float(psteps.get_meta("bottom_y", 0.0))) if psteps else 0.0,
		"step_z_top": _r(float(psteps.get_meta("z_top", 0.0))) if psteps else 0.0,
	}
	_j["cottage"] = porch
	print("### COTTAGE_RUNTIME")
	print(JSON.stringify(porch, "", false))
	parent.free()

	# ---------------- lamps ----------------
	var lp := Node3D.new()
	var lamps: Array = W._street_lamps(lp)
	var lam: Array = []
	for L in lamps:
		var info: Dictionary = L[3]
		var b: Vector3 = info["base"]
		lam.append({"name": info["name"], "base_world": _v3(b), "local": _v2(_w2l(Vector2(b.x, b.z))),
			"base_y": _r(b.y)})
	_j["lamps"] = lam
	print("### LAMPS")
	for l in lam:
		print(l["name"], " local=", _v2s(l["local"]), " base_y=", l["base_y"])
	lp.free()

	# ---------------- pads ----------------
	var pads := _parse_pads()
	var planes := _parse_planes()
	if not pads.is_empty():
		var rep := {}
		print("### PADS")
		for name in pads.keys():
			var pl = planes.get(name, [])
			var r := _pad_report(name, pads[name], pl)
			rep[name] = r
			print("--- pad ", name, "  plane_used=", JSON.stringify(r["plane_used"]), " (a+b*lx+c*lz, world Y)")
			print("rects=", JSON.stringify(r["rects"]))
			print("paved_area=", r["paved_area"], " raw_area=", r["raw_area"], " terrain=", r["terrain_min"], "..", r["terrain_max"])
			print("fill: max=", r["max_fill"], " cut: max=", r["max_cut"], " vol_fill=", r["fill_vol"], " vol_cut=", r["cut_vol"])
			print("seam_N_top=", r["n_top"], " seam_S_top=", r["s_top"])
			print("edge_exposure N/E/S/W max=", JSON.stringify(r["edge_max"]), " mean=", JSON.stringify(r["edge_mean"]))
			print("bevel_deg(0.90m)=", r["bevel_deg"], " kerb_max=", r["kerb_max"])
			print("corners=", JSON.stringify(r["rect_corners"]))
			print("side_profile=", JSON.stringify(r["side_profile"]))
		_j["pads"] = rep

	var f := FileAccess.open(OUT_JSON, FileAccess.WRITE)
	f.store_string(JSON.stringify(_j, "  "))
	f.close()
	print("[P2A-A] wrote ", OUT_JSON)
	quit(0)

# ---------------------------------------------------------------- helpers ---
func _r(v: float) -> float:
	var x := snappedf(v, 0.001)
	if absf(x) < 0.0005:
		return 0.0
	return x

func _v3(v: Vector3) -> Array:
	return [_r(v.x), _r(v.y), _r(v.z)]

func _v2(v: Vector2) -> Array:
	return [_r(v.x), _r(v.y)]

func _v2s(a) -> String:
	return "(%.2f,%.2f)" % [float(a[0]), float(a[1])]

func _v3_or(v) -> Array:
	if v is Vector3:
		return _v3(v)
	return []

func _safe(v) -> Dictionary:
	var o := {}
	if v is Dictionary:
		for k in v.keys():
			var x = v[k]
			if x is Vector3:
				o[k] = _v3(x)
			elif x is Vector2:
				o[k] = _v2(x)
			elif x is float:
				o[k] = _r(x)
			else:
				o[k] = str(x)
	return o

func _hdr(xs: Array) -> String:
	var s := ""
	for x in xs:
		s += "%.0f|" % float(x)
	return s

func _row(vals: Array) -> String:
	var s := ""
	for v in vals:
		s += "%.3f|" % float(v)
	return s

func _arr2s(a: Array) -> String:
	var s := ""
	for v in a:
		s += " " + _v2s(v)
	return s

func _f2w(lx: float, lz: float) -> Vector3:
	return Vector3(M.HOUSE_X + lx * _c + lz * _s, 0.0, M.HOUSE_Z - lx * _s + lz * _c)

func _w2l(p: Vector2) -> Vector2:
	var dx := p.x - M.HOUSE_X
	var dz := p.y - M.HOUSE_Z
	return Vector2(dx * _c - dz * _s, dx * _s + dz * _c)

func _slope(x: float, z: float) -> float:
	var n: Vector3 = M.terrain_normal(x, z)
	return rad_to_deg(acos(clampf(n.y, -1.0, 1.0)))

func _flat_spans(lz: float) -> Array:
	var spans: Array = []
	var inside := false
	var start := 0.0
	var lx := -6.5
	while lx <= 3.501:
		var p := _f2w(lx, lz)
		var ok := _slope(p.x, p.z) <= 8.0 and W.trail_clearance(p.x, p.z) >= 0.15
		if ok:
			ok = not (W._in_house(p.x, p.z, 0.0) or W._in_porch(p.x, p.z, 0.0)
				or W._in_garden(p.x, p.z, 0.0) or W._in_field(p.x, p.z, 0.0))
		if ok and not inside:
			inside = true
			start = lx
		elif not ok and inside:
			inside = false
			if lx - start >= 0.3:
				spans.append([_r(start), _r(lx - 0.05)])
		lx += 0.05
	if inside:
		spans.append([_r(start), _r(3.5)])
	return spans

func _path_spans(lz: float) -> Array:
	var spans: Array = []
	var inside := false
	var start := 0.0
	var lx := -7.0
	while lx <= 4.001:
		var p := _f2w(lx, lz)
		var on := W.trail_clearance(p.x, p.z) < 0.0
		if on and not inside:
			inside = true
			start = lx
		elif not on and inside:
			inside = false
			if lx - start >= 0.05:
				spans.append([_r(start), _r(lx - 0.05)])
		lx += 0.05
	if inside:
		spans.append([_r(start), _r(4.0)])
	return spans

func _dist_point_seg2(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := 0.0
	if ab.length_squared() > 1.0e-9:
		t = clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)

func _rect_dist(cs: Array, p: Vector2) -> float:
	var best := 1.0e9
	for i in range(4):
		best = minf(best, _dist_point_seg2(p, cs[i], cs[(i + 1) % 4]))
	return best

func _parse_pads() -> Dictionary:
	var d := {}
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--pads="):
			continue
		for item in a.substr(7).split(";", false):
			var kv := item.split(":")
			if kv.size() < 2:
				continue
			var rects := []
			for chunk in kv[1].split("|", false):
				var n := chunk.split(",")
				if n.size() < 4:
					continue
				rects.append([float(n[0]), float(n[1]), float(n[2]), float(n[3])])
			if not rects.is_empty():
				d[kv[0]] = rects
	return d

func _parse_planes() -> Dictionary:
	var d := {}
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--planes="):
			continue
		for item in a.substr(9).split(";", false):
			var kv := item.split(":")
			if kv.size() < 2:
				continue
			var n := kv[1].split(",")
			if n.size() < 3:
				continue
			d[kv[0]] = [float(n[0]), float(n[1]), float(n[2])]
	return d

func _corridor() -> float:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--corridor="):
			return float(a.substr(11))
	return 0.72

func _pad_top(pl: Array, lx: float, lz: float) -> float:
	return pl[0] + pl[1] * lx + pl[2] * lz

func _rect_has(rects: Array, lx: float, lz: float) -> bool:
	for r in rects:
		if lx >= r[0] and lx <= r[1] and lz >= r[2] and lz <= r[3]:
			return true
	return false

func _rect_has_inner(rects: Array, lx: float, lz: float, m: float) -> bool:
	for r in rects:
		if lx > r[0] + m and lx < r[1] - m and lz > r[2] + m and lz < r[3] - m:
			return true
	return false

func _pad_report(_name: String, rects: Array, pl: Array) -> Dictionary:
	var step := 0.20
	var corridor := _corridor()
	# bbox
	var bx0 := 1e9
	var bx1 := -1e9
	var bz0 := 1e9
	var bz1 := -1e9
	for r in rects:
		bx0 = minf(bx0, r[0]); bx1 = maxf(bx1, r[1])
		bz0 = minf(bz0, r[2]); bz1 = maxf(bz1, r[3])
	# sample interior
	var sx := int(round((bx1 - bx0) / step))
	var sz := int(round((bz1 - bz0) / step))
	var pts := []
	var tmin := 1e9
	var tmax := -1e9
	var sum_h := 0.0
	var n_in := 0
	for i in sx:
		var lx := bx0 + (i + 0.5) * step
		for k in sz:
			var lz := bz0 + (k + 0.5) * step
			if not _rect_has(rects, lx, lz):
				continue
			var w := _f2w(lx, lz)
			var th: float = M.terrain_height(w.x, w.z)
			n_in += 1
			sum_h += th
			tmin = minf(tmin, th)
			tmax = maxf(tmax, th)
			pts.append([lx, lz, th])
	var mean_h: float = sum_h / float(maxi(n_in, 1))
	# least squares plane h = a + c*lx + d*lz
	var n_ = float(pts.size())
	var s_lx := 0.0
	var s_lz := 0.0
	var s_h := 0.0
	var s_ll := 0.0
	var s_zz := 0.0
	var s_lz2 := 0.0
	var s_lh := 0.0
	var s_zh := 0.0
	for q in pts:
		s_lx += q[0]; s_lz += q[1]; s_h += q[2]
		s_ll += q[0] * q[0]; s_zz += q[1] * q[1]; s_lz2 += q[0] * q[1]
		s_lh += q[0] * q[2]; s_zh += q[1] * q[2]
	var m := [[n_, s_lx, s_lz], [s_lx, s_ll, s_lz2], [s_lz, s_lz2, s_zz]]
	var rhs := [s_h, s_lh, s_zh]
	var fit := _solve3(m, rhs)
	var plane_used: Array = pl if pl.size() >= 3 else fit
	# fill / cut over paved cells (exclude road corridor)
	var max_fill := -1e9
	var max_cut := -1e9
	var vol_fill := 0.0
	var vol_cut := 0.0
	var paved := 0
	var raw_cells := 0
	var kerb_max := -1e9
	var cd := 0.0
	for q in pts:
		var w2 := _f2w(q[0], q[1])
		cd = W._path_clearance(w2.x, w2.z)
		raw_cells += 1
		if cd < corridor:
			if cd >= corridor - 0.28:
				kerb_max = maxf(kerb_max, _pad_top(plane_used, q[0], q[1]) - float(q[2]))
			continue
		paved += 1
		var dy: float = _pad_top(plane_used, q[0], q[1]) - float(q[2])
		if dy > 0.0:
			max_fill = maxf(max_fill, dy)
			vol_fill += dy * step * step
		else:
			max_cut = maxf(max_cut, -dy)
			vol_cut += -dy * step * step
	if max_fill < -1e8:
		max_fill = 0.0
	if max_cut < -1e8:
		max_cut = 0.0
	if kerb_max < -1e8:
		kerb_max = 0.0
	# boundary sampling: rect edges not shared with another rect and off-corridor
	var edges := {"N": [], "S": [], "W": [], "E": [], "I": []}
	var rect_corners := []
	for r in rects:
		var cs := [[r[0], r[2]], [r[1], r[2]], [r[1], r[3]], [r[0], r[3]]]
		for c in cs:
			var cw := _f2w(c[0], c[1])
			rect_corners.append({"lx": _r(c[0]), "lz": _r(c[1]),
				"terrain": _r(M.terrain_height(cw.x, cw.z)),
				"top": _r(_pad_top(plane_used, c[0], c[1]))})
		var nseg := int(round((r[1] - r[0]) / step))
		for i in nseg + 1:
			_edge_pt(edges, rects, r[0] + i * step, r[2], Vector2(bx0, bz0), Vector2(bx1, bz1), plane_used, corridor)
			_edge_pt(edges, rects, r[0] + i * step, r[3], Vector2(bx0, bz0), Vector2(bx1, bz1), plane_used, corridor)
		var nsegz := int(round((r[3] - r[2]) / step))
		for k in nsegz + 1:
			_edge_pt(edges, rects, r[0], r[2] + k * step, Vector2(bx0, bz0), Vector2(bx1, bz1), plane_used, corridor)
			_edge_pt(edges, rects, r[1], r[2] + k * step, Vector2(bx0, bz0), Vector2(bx1, bz1), plane_used, corridor)
	var edge_max := {}
	var edge_mean := {}
	for key in edges.keys():
		var arr: Array = edges[key]
		if arr.is_empty():
			edge_max[key] = null
			edge_mean[key] = null
			continue
		edge_max[key] = _r(arr.max())
		var sm := 0.0
		for v in arr:
			sm += v
		edge_mean[key] = _r(sm / float(arr.size()))
	var side_profile := []
	for key in ["N", "E", "S", "W"]:
		side_profile.append({"side": key, "max": edge_max[key], "n": edges[key].size()})
	# seam heights (pad top at the north / south bbox edges, lx = bbox centre)
	var seam_n := _pad_top(plane_used, (bx0 + bx1) * 0.5, bz0)
	var seam_s := _pad_top(plane_used, (bx0 + bx1) * 0.5, bz1)
	return {
		"rects": [_r(bx0), _r(bx1), _r(bz0), _r(bz1)],
		"rects_all": rects,
		"plane_used": [_r(plane_used[0]), _r(plane_used[1]), _r(plane_used[2])],
		"plane_fit": [_r(fit[0]), _r(fit[1]), _r(fit[2])],
		"mean_h": _r(mean_h),
		"terrain_min": _r(tmin), "terrain_max": _r(tmax),
		"paved_area": _r(float(paved) * step * step),
		"raw_area": _r(float(raw_cells) * step * step),
		"max_fill": _r(max_fill), "max_cut": _r(max_cut),
		"fill_vol": _r(vol_fill), "cut_vol": _r(vol_cut),
		"kerb_max": _r(kerb_max),
		"n_top": _r(seam_n), "s_top": _r(seam_s),
		"edge_max": edge_max, "edge_mean": edge_mean,
		"bevel_deg": _r(rad_to_deg(atan(maxf(max_fill, max_cut) / 0.90))),
		"rect_corners": rect_corners,
		"side_profile": side_profile
	}

func _edge_pt(edges: Dictionary, rects: Array, lx: float, lz: float, bb0: Vector2, bb1: Vector2, pl: Array, corridor: float) -> void:
	if _rect_has_inner(rects, lx, lz, 0.05):
		return
	var w := _f2w(lx, lz)
	if W._path_clearance(w.x, w.z) < corridor:
		return
	var dy: float = _pad_top(pl, lx, lz) - M.terrain_height(w.x, w.z)
	var key := "I"
	if lz < bb0.y + 0.26:
		key = "N"
	elif lz > bb1.y - 0.26:
		key = "S"
	elif lx < bb0.x + 0.26:
		key = "W"
	elif lx > bb1.x - 0.26:
		key = "E"
	edges[key].append(dy)

func _solve3(mm: Array, rhs: Array) -> Array:
	var d := _det3(mm)
	if absf(d) < 1e-12:
		return [0.0, 0.0, 0.0]
	var out := []
	for c in 3:
		var m2 := mm.duplicate(true)
		for r in 3:
			m2[r][c] = rhs[r]
		out.append(_det3(m2) / d)
	return out

func _det3(a: Array) -> float:
	return a[0][0] * (a[1][1] * a[2][2] - a[1][2] * a[2][1]) \
		- a[0][1] * (a[1][0] * a[2][2] - a[1][2] * a[2][0]) \
		+ a[0][2] * (a[1][0] * a[2][1] - a[1][1] * a[2][0])
