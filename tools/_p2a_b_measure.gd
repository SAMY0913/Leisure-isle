extends SceneTree
## P9 / P2A —— Subagent B 临时测量脚本（只读 + 只打印；不写任何文件、不改任何共享场景/脚本）。
##
## 运行：
##   "$ENG" --path "D:/休闲小岛幻境/游戏工程" --headless --script res://tools/_p2a_b_measure.gd -- --center=-4.00,13.20
## 可选：--center=lx,lz 可重复；--plateau=7.50；--no-vis（跳过遮挡采样）
## 输出：人类可读 [B]... 行 + 末尾一行 "B_JSON <json>"（供外部解析）。

const M := preload("res://scripts/isle_math.gd")
const W := preload("res://scripts/world.gd")
const FSC := preload("res://scripts/isle_farm.gd")
const SPEC := preload("res://scripts/isle_scale_spec.gd")

# ---- P0 定稿尺寸（开发产物/P9/P0/farm_site_report.md §3-§5）----
const CELL := 1.00
const GAP := 0.50
const BORDER := 0.65
const POST_R := 0.045
const POST_H := 0.80
const RAIL_R := 0.030
const RAIL_CIRC := 0.0325          # 八棱横杆外接半径（0.030/cos22.5°），遮挡判定取保守值
const RAIL_YS := [0.34, 0.64]
const GATE_W := 1.10
const RIM_HALF := 0.57
const SOIL_HALF := 0.52
const POST_SPACING := 0.70
const RAIL_SEG_MAX := 0.60
const P1_PLATEAU := 7.372
const CUT := 0.04                  # P0: 台面 = 包络最高地形 - 0.04

var centers: Array = []
var plateau_override := -1.0
var do_vis := true
var cands_mode := false
var surf_mode := false
var v3_mode := false
var plateau_list: Array = []
var _res: Dictionary = {}

const CAND_CENTERS := [Vector2(-4.35, 13.20), Vector2(-4.35, 12.60), Vector2(-4.35, 12.90)]
const CAND_NAMES := ["S1", "S2", "S3"]
const CAND_TERRACE := [7.372, 7.55, 7.372]
const PADS := [
	[Vector2(-7.7, 3.18), Vector2(-2.88, 3.18), Vector2(-2.88, 4.74), Vector2(-1.08, 4.74),
		Vector2(-1.08, 5.62), Vector2(-0.21, 5.62), Vector2(0.1, 6.6), Vector2(-1.45, 6.6),
		Vector2(-1.45, 16.06), Vector2(-7.7, 16.06)],
	[Vector2(-7.7, 3.18), Vector2(-2.88, 3.18), Vector2(-2.88, 4.74), Vector2(-1.08, 4.74),
		Vector2(-1.08, 5.62), Vector2(-0.21, 5.62), Vector2(-1.45, 5.62), Vector2(-1.45, 15.66),
		Vector2(-7.7, 15.66)],
	[Vector2(-7.85, 0.85), Vector2(-3.9, 0.85), Vector2(-3.9, 3.18), Vector2(-2.88, 3.18),
		Vector2(-2.88, 4.74), Vector2(-1.08, 4.74), Vector2(-1.08, 5.62), Vector2(-0.21, 5.62),
		Vector2(0.1, 6.6), Vector2(-1.45, 6.6), Vector2(-1.45, 15.8), Vector2(-7.85, 15.8)],
]
const LAMPS := [
	["GardenLamp2", Vector2(-6.502, 4.183)],
	["PathLamp1", Vector2(1.405, 7.525)],
]


func _initialize() -> void:
	_run.call_deferred()


func _p(k: String, v) -> void:
	print("[B] " + k + " = " + str(v))


func _parse() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--center="):
			var pp := s.substr(9).split(",")
			if pp.size() >= 2:
				centers.append(Vector2(float(pp[0]), float(pp[1])))
		elif s.begins_with("--plateau="):
			plateau_override = float(s.substr(10))
		elif s == "--no-vis":
			do_vis = false
		elif s == "--cands":
			cands_mode = true
		elif s == "--surf":
			surf_mode = true
		elif s == "--v3":
			v3_mode = true


# ---------------------------------------------------------------- 坐标变换 ---
func l2w(lx: float, lz: float) -> Vector2:
	var c := cos(M.HOUSE_YAW)
	var s := sin(M.HOUSE_YAW)
	return Vector2(M.HOUSE_X + lx * c + lz * s, M.HOUSE_Z - lx * s + lz * c)


func w2l(x: float, z: float) -> Vector2:
	var dx := x - M.HOUSE_X
	var dz := z - M.HOUSE_Z
	var c := cos(M.HOUSE_YAW)
	var s := sin(M.HOUSE_YAW)
	return Vector2(dx * c - dz * s, dx * s + dz * c)


func f2w(center: Vector2, fx: float, fz: float) -> Vector2:
	return l2w(center.x + fx, center.y + fz)


func w2f(center: Vector2, x: float, z: float) -> Vector2:
	var l := w2l(x, z)
	return l - center


func cell_world(center: Vector2, i: int, j: int) -> Vector2:
	return f2w(center, float(i - 1) * (CELL + GAP), float(j - 1) * (CELL + GAP))


# --------------------------------------------------------------- 地形/包络 ---
func env_terrain(center: Vector2, half: float, step: float) -> Dictionary:
	var lo := 1e9
	var hi := -1e9
	var lo_p := Vector2.ZERO
	var hi_p := Vector2.ZERO
	var n := int(ceil(2.0 * half / step))
	for a in range(n + 1):
		for b in range(n + 1):
			var fx := -half + 2.0 * half * float(a) / float(n)
			var fz := -half + 2.0 * half * float(b) / float(n)
			var w := f2w(center, fx, fz)
			var h := W.surface_y(w.x, w.y)
			if h < lo:
				lo = h
				lo_p = Vector2(fx, fz)
			if h > hi:
				hi = h
				hi_p = Vector2(fx, fz)
	return {"min": lo, "max": hi, "argmin_local": lo_p, "argmax_local": hi_p}


func env_terrain_edge(center: Vector2, half: float, step: float) -> Dictionary:
	# 只在包络边界上采样（用于“台面是否被地形侵入”的判定）
	var lo := 1e9
	var hi := -1e9
	var n := int(ceil(2.0 * half / step))
	for a in range(n + 1):
		var t := -half + 2.0 * half * float(a) / float(n)
		for sz in [Vector2(-half, t), Vector2(half, t), Vector2(t, -half), Vector2(t, half)]:
			var w := f2w(center, sz.x, sz.y)
			var h := W.surface_y(w.x, w.y)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return {"min": lo, "max": hi}


# ------------------------------------------------------------- 几何包络表 ---
func envelopes() -> Dictionary:
	var pitch: float = CELL + GAP
	var hc: float = pitch + CELL * 0.5
	var hp: float = hc + BORDER
	var hf: float = hp + 0.06
	var podium: float = hf + 0.10
	var r := {
		"pitch": pitch, "cell": CELL, "gap": GAP, "border": BORDER,
		"soil_top_half": SOIL_HALF, "soil_rim_half": RIM_HALF,
		"half_cells_nominal": hc, "half_cells_rim": pitch + RIM_HALF,
		"half_plot": hp, "half_fence": hf, "half_post_outer": hf + POST_R, "half_podium": podium,
	}
	return r


# --------------------------------------------------------------- 相机数学 ---
func cam_xform(theta: float, elev: float, r: float, target: Vector3, fov: float) -> Dictionary:
	var pos := target + Vector3(r * cos(elev) * sin(theta), r * sin(elev), r * cos(elev) * cos(theta))
	var dir := target - pos
	var up := Vector3.UP
	var right := dir.cross(up)
	if right.length_squared() < 0.000001:
		right = Vector3.RIGHT
	right = right.normalized()
	var cam_up := right.cross(dir.normalized()).normalized()
	var basis := Basis(right, cam_up, -dir.normalized())
	var min_y := maxf(1.1, M.terrain_height(pos.x, pos.z) + 1.2)
	var clamped := pos.y < min_y
	var p2 := Vector3(pos.x, maxf(pos.y, min_y), pos.z)
	return {"pos": p2, "raw_pos": pos, "basis": basis, "fov": fov, "clamped": clamped, "min_y": min_y,
		"transform": Transform3D(basis, p2)}


func ndc(cam: Dictionary, p: Vector3) -> Vector2:
	var b: Basis = cam["basis"]
	var pos: Vector3 = cam["pos"]
	var rel := p - pos
	var v := Vector3(rel.dot(b.x), rel.dot(b.y), rel.dot(b.z))   # 相机空间（-Z 朝前）
	var fov: float = float(cam["fov"])
	var aspect := 16.0 / 9.0
	var tanh := tan(deg_to_rad(fov) * 0.5)
	if absf(v.z) < 1e-6:
		return Vector2(1e9, 1e9)
	return Vector2((v.x / -v.z) / (tanh * aspect), (v.y / -v.z) / tanh)


# ------------------------------------------------------------ 有限圆柱求交 ---
func cyl_hit(ro: Vector3, rd: Vector3, a: Vector3, b: Vector3, rad: float) -> bool:
	var ax := b - a
	var ln := ax.length()
	if ln < 1e-6:
		return false
	var d := ax / ln
	var oc := ro - a
	var rd_d := rd.dot(d)
	var oc_d := oc.dot(d)
	var rdp := rd - d * rd_d
	var ocp := oc - d * oc_d
	var qa := rdp.dot(rdp)
	if qa < 1e-9:
		return false
	var qb := 2.0 * ocp.dot(rdp)
	var qc := ocp.dot(ocp) - rad * rad
	var disc := qb * qb - 4.0 * qa * qc
	if disc < 0.0:
		return false
	var sq := sqrt(disc)
	var t0 := (-qb - sq) / (2.0 * qa)
	var t1 := (-qb + sq) / (2.0 * qa)
	for tt: float in [t0, t1]:
		if tt > 1e-4:
			var u: float = (ro + rd * tt - a).dot(d)
			if u >= -1e-4 and u <= ln + 1e-4:
				return true
	return false


# --------------------------------------------------------------- 围栏构件 ---
func build_occluders(center: Vector2, plateau: float) -> Array:
	var list: Array = []
	var hf: float = envelopes()["half_fence"]
	var gh := GATE_W * 0.5
	var sides := [
		[Vector2(-hf, -hf), Vector2(hf, -hf)],
		[Vector2(-hf, hf), Vector2(hf, hf)],
		[Vector2(-hf, -hf), Vector2(-hf, hf)],
		[Vector2(hf, -hf), Vector2(hf, hf)],
	]
	for si in range(4):
		var p0: Vector2 = sides[si][0]
		var p1: Vector2 = sides[si][1]
		var segs := [[p0, p1]]
		if si == 0:
			segs = [[p0, Vector2(-gh, -hf)], [Vector2(gh, -hf), p1]]
		for sg in segs:
			var a: Vector2 = sg[0]
			var b: Vector2 = sg[1]
			var ln := a.distance_to(b)
			if ln < 0.05:
				continue
			var nposts := maxi(2, int(ceil(ln / POST_SPACING)) + 1)
			for s in range(nposts):
				var t := float(s) / float(nposts - 1)
				var cf := a.lerp(b, t)
				var w := f2w(center, cf.x, cf.y)
				list.append({"a": Vector3(w.x, plateau, w.y), "b": Vector3(w.x, plateau + POST_H, w.y),
					"r": POST_R, "kind": "post"})
			var nseg := maxi(1, int(ceil(ln / RAIL_SEG_MAX)))
			for s in range(nseg):
				var t0 := float(s) / float(nseg)
				var t1 := float(s + 1) / float(nseg)
				var fa := a.lerp(b, t0)
				var fb := a.lerp(b, t1)
				var wa := f2w(center, fa.x, fa.y)
				var wb := f2w(center, fb.x, fb.y)
				for rh in RAIL_YS:
					list.append({"a": Vector3(wa.x, plateau + float(rh), wa.y),
						"b": Vector3(wb.x, plateau + float(rh), wb.y), "r": RAIL_CIRC, "kind": "rail"})
	return list


func occ_counts(occ: Array) -> Dictionary:
	var posts := 0
	var rails := 0
	for o in occ:
		if String(o["kind"]) == "post":
			posts += 1
		else:
			rails += 1
	return {"posts": posts, "rails": rails}


# ------------------------------------------------------------- 可见性采样 ---
func vis_cell(cam: Dictionary, center: Vector2, i: int, j: int, top_y: float, occ: Array, n: int) -> Dictionary:
	var cw := cell_world(center, i, j)
	var c := cos(M.HOUSE_YAW)
	var s := sin(M.HOUSE_YAW)
	var cp: Vector3 = cam["pos"]
	var vis := 0
	var tot := 0
	var by_post := 0
	var by_rail := 0
	for aa in range(n):
		for bb in range(n):
			var u := -SOIL_HALF + 2.0 * SOIL_HALF * float(aa) / float(n - 1)
			var v := -SOIL_HALF + 2.0 * SOIL_HALF * float(bb) / float(n - 1)
			# 格面局部轴与房屋局部轴同向（rot=0）：+fx 世界方向 (c,-s)，+fz 世界方向 (s,c)
			var p := Vector3(cw.x + u * c + v * s, top_y, cw.y - u * s + v * c)
			var rd := (p - cp)
			var dist := rd.length()
			rd = rd / dist
			tot += 1
			var blocked := ""
			for o in occ:
				if cyl_hit(cp, rd, o["a"], o["b"], float(o["r"])):
					blocked = String(o["kind"])
					break
			if blocked == "":
				vis += 1
			elif blocked == "post":
				by_post += 1
			else:
				by_rail += 1
	return {"vis": vis, "tot": tot, "frac": float(vis) / float(maxi(tot, 1)), "by_post": by_post, "by_rail": by_rail}


## 保守“实墙”判定：把围栏四条边当成 0.80 m 高的实墙（门洞除外），看视线是否被墙面切断。
func wall_blocked(cam: Dictionary, center: Vector2, target: Vector3, plateau: float) -> Dictionary:
	var cp: Vector3 = cam["pos"]
	var cl := w2f(center, cp.x, cp.z)
	var tl := w2f(center, target.x, target.z)
	var hf: float = envelopes()["half_fence"]
	var seg_a := cl
	var seg_b := tl
	var best_s := -1.0
	var best_hit := Vector3.ZERO
	for s in [seg_b.x]:
		pass
	# 与四条边求交，取 0<s<1 的交点（相机在方形外、目标在内，正常只有 1 个）
	var edges := [
		[Vector2(-hf, -hf), Vector2(hf, -hf), "z-"],
		[Vector2(-hf, hf), Vector2(hf, hf), "z+"],
		[Vector2(-hf, -hf), Vector2(-hf, hf), "x-"],
		[Vector2(hf, -hf), Vector2(hf, hf), "x+"],
	]
	var hits := []
	for e in edges:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var tag := String(e[2])
		var d1 := seg_b - seg_a
		var d2 := b - a
		var den := d1.x * d2.y - d1.y * d2.x
		if absf(den) < 1e-9:
			continue
		var q := a - seg_a
		var t := (q.x * d2.y - q.y * d2.x) / den
		var u := (q.x * d1.y - q.y * d1.x) / den
		if t > 1e-6 and t < 1.0 - 1e-6 and u >= -1e-6 and u <= 1.0 + 1e-6:
			var hit := seg_a + d1 * t
			hits.append({"t": t, "local": hit, "edge": tag, "u": u})
	if hits.is_empty():
		return {"blocked": false, "reason": "no_edge_crossing"}
	hits.sort_custom(func(x, y): return float(x["t"]) < float(y["t"]))
	var h: Dictionary = hits[0]
	var hit: Vector2 = h["local"]
	var y := lerpf(cp.y, target.y, float(h["t"]))
	var gate_half := GATE_W * 0.5
	var in_gate := String(h["edge"]) == "z-" and absf(hit.x) <= gate_half
	var top := plateau + POST_H
	return {"blocked": (not in_gate) and y < top, "y_at_fence": y, "fence_top": top,
		"local": hit, "edge": String(h["edge"]), "in_gate": in_gate}


# ---------------------------------------------------------------- 距离量测 ---
func fence_ring_points(hf: float, step: float) -> Array:
	var pts: Array = []
	var n := int(ceil(2.0 * hf / step))
	for a in range(n + 1):
		var t := -hf + 2.0 * hf * float(a) / float(n)
		pts.append(Vector2(-hf, t))
		pts.append(Vector2(hf, t))
		pts.append(Vector2(t, -hf))
		pts.append(Vector2(t, hf))
	return pts


func rect_dist_house_rect(lx: float, lz: float, x0: float, x1: float, z0: float, z1: float) -> float:
	var dx := maxf(maxf(x0 - lx, 0.0), lx - x1)
	var dz := maxf(maxf(z0 - lz, 0.0), lz - z1)
	return sqrt(dx * dx + dz * dz)


func dist_to_house(center: Vector2) -> Dictionary:
	# 房屋前墙（外皮，房屋局部 z=+D/2，x∈[-W/2,W/2]）
	var hw: float = M.HOUSE_W * 0.5
	var hd: float = M.HOUSE_D * 0.5
	var pts := fence_ring_points(envelopes()["half_fence"], 0.02)
	var best_wall := 1e9
	var best_wall_local := Vector2.ZERO
	var best_porch := 1e9
	var best_wall_pt := Vector2.ZERO
	for p in pts:
		var w := f2w(center, p.x, p.y)
		var l := w2l(w.x, w.y)
		var d1 := rect_dist_house_rect(l.x, l.y, -hw, hw, hd, hd)   # 前墙外皮线
		if d1 < best_wall:
			best_wall = d1
			best_wall_local = p
			best_wall_pt = l
		var d2 := rect_dist_house_rect(l.x, l.y, -4.30, 4.30, 3.40, 7.45)
		if d2 < best_porch:
			best_porch = d2
	return {"to_front_wall": best_wall, "front_wall_local": best_wall_local,
		"front_wall_house_local": best_wall_pt, "to_porch": best_porch}


func dist_to_path(center: Vector2) -> Dictionary:
	var pts := fence_ring_points(envelopes()["half_fence"], 0.01)
	var best := 1e9
	var best_p := Vector2.ZERO
	var best_w := Vector2.ZERO
	for p in pts:
		var w := f2w(center, p.x, p.y)
		var d := W._path_clearance(w.x, w.y)
		if d < best:
			best = d
			best_p = p
			best_w = w
	var info := W.path_center_info(best_w.x, best_w.y)
	return {"min_clear": best, "local": best_p, "world": best_w,
		"nearest_path_centre": info["centre"], "nearest_path_half_w": info["half_w"]}


func gate_world(center: Vector2, plateau: float) -> Dictionary:
	var hf: float = envelopes()["half_fence"]
	var gw := f2w(center, 0.0, -hf)
	return {"centre": gw, "left_post": f2w(center, -GATE_W * 0.5, -hf),
		"right_post": f2w(center, GATE_W * 0.5, -hf), "y": plateau}


## 从门口沿 -fz 走，找到主路路面（clearance<=0）的距离（二分）。
func gate_path_distance(center: Vector2) -> Dictionary:
	var hf: float = envelopes()["half_fence"]
	var g := f2w(center, 0.0, -hf)
	var ci := W.path_center_info(g.x, g.y)
	var ray := -1.0
	var t := 0.0
	while t <= 30.0:
		var w := f2w(center, 0.0, -hf - t)
		if W._path_clearance(w.x, w.y) <= 0.0:
			ray = t
			break
		t += 0.01
	return {"edge_dist": ci["dist"] - ci["half_w"], "clear_at_fence": W._path_clearance(g.x, g.y),
		"nearest_centre": a2(ci["centre"]), "nearest_half_w": ci["half_w"], "along_ray": ray}


func steps_table(center: Vector2, plateau: float) -> Array:
	var hf: float = envelopes()["half_fence"]
	var out: Array = []
	for s in range(8):
		var d := 0.16 + float(s) * (2.40 - 0.16) / 7.0
		var w := f2w(center, 0.0, -hf - d)
		var h := W.surface_y(w.x, w.y)
		var top := maxf(h + 0.05, plateau - 0.06)
		out.append({"idx": s, "d_from_fence": d, "world": w, "terrain": h, "top": top,
			"top_above_terrain": top - h})
	return out

# ------------------------------------------------------------------- 主流程 ---
func q(v: float, d: int = 3) -> float:
	var m := pow(10.0, float(d))
	return round(v * m) / m


func a2(v: Vector2) -> Array:
	return [q(v.x), q(v.y)]


func a3(v: Vector3) -> Array:
	return [q(v.x), q(v.y), q(v.z)]


func ring_point_nearest(center: Vector2, fx: float, fz: float, s: float) -> Vector2:
	# 外圈走道中心线 = |max(|fx|,|fz|)| = s 的方形；返回距格心最近的走道点
	var ax := absf(fx)
	var az := absf(fz)
	if ax >= az:
		return Vector2(signf(fx) * s, fz)
	return Vector2(fx, signf(fz) * s)


func ring_param(p: Vector2, s: float) -> float:
	if absf(p.y + s) < 1e-3:
		return p.x + s
	if absf(p.x - s) < 1e-3:
		return 2.0 * s + (p.y + s)
	if absf(p.y - s) < 1e-3:
		return 4.0 * s + (s - p.x)
	return 6.0 * s + (s - p.y)


func transform_check(center: Vector2) -> Dictionary:
	var root_node := get_root()
	var farm := Node3D.new()
	farm.name = "BGridProbe"
	root_node.add_child(farm)
	var cw := f2w(center, 0.0, 0.0)
	farm.position = Vector3(cw.x, 0.0, cw.y)
	farm.rotation = Vector3(0.0, M.HOUSE_YAW, 0.0)
	var max_err := 0.0
	var worst := ""
	for i in range(3):
		for j in range(3):
			var m := Node3D.new()
			m.position = Vector3(float(i - 1) * (CELL + GAP), 0.0, float(j - 1) * (CELL + GAP))
			farm.add_child(m)
			var gp: Vector3 = m.global_position
			var want := f2w(center, m.position.x, m.position.z)
			var err := Vector2(gp.x, gp.z).distance_to(want)
			if err > max_err:
				max_err = err
				worst = "i=%d j=%d engine=(%.6f,%.6f) formula=(%.6f,%.6f)" % [i, j, gp.x, gp.z, want.x, want.y]
	var dxn := Node3D.new()
	dxn.position = Vector3(1.0, 0.0, 0.0)
	farm.add_child(dxn)
	var dzn := Node3D.new()
	dzn.position = Vector3(0.0, 0.0, 1.0)
	farm.add_child(dzn)
	var dir_x := Vector2(dxn.global_position.x - farm.global_position.x, dxn.global_position.z - farm.global_position.z)
	var dir_z := Vector2(dzn.global_position.x - farm.global_position.x, dzn.global_position.z - farm.global_position.z)
	# 房屋帧同样验证：house 原点 + yaw 下 (0,0,1) 应等于 house_front()
	var hnode := Node3D.new()
	hnode.position = Vector3(M.HOUSE_X, 0.0, M.HOUSE_Z)
	hnode.rotation = Vector3(0.0, M.HOUSE_YAW, 0.0)
	root_node.add_child(hnode)
	var hz := Node3D.new()
	hz.position = Vector3(0.0, 0.0, 1.0)
	hnode.add_child(hz)
	var hfront := Vector2(hz.global_position.x - hnode.global_position.x, hz.global_position.z - hnode.global_position.z)
	var hf := M.house_front()
	# 相机方位关系
	var cam_rel := Vector2(0, 0)
	root_node.remove_child(farm)
	root_node.remove_child(hnode)
	farm.queue_free()
	hnode.queue_free()
	return {"max_err": max_err, "worst": worst, "dir_plus_fx": a2(dir_x), "dir_plus_fz": a2(dir_z),
		"house_front_dir": a2(Vector2(hf.x, hf.z)),
		"half_front_err": Vector2(hf.x, hf.z).distance_to(hfront)}


func cells_table(center: Vector2, plateau: float) -> Array:
	var out: Array = []
	var f := FSC.new()
	for j in range(3):
		for i in range(3):
			var s_idx := f.slot_index(i, j)
			var off: Vector2 = f.slot_offset(s_idx)
			var used := Vector2(float(i - 1) * (CELL + GAP), float(j - 1) * (CELL + GAP))
			var cw := f2w(center, used.x, used.y)
			var hl := Vector2(center.x + used.x, center.y + used.y)
			out.append({
				"slot": s_idx, "i": i, "j": j,
				"farm_off": a2(off), "farm_off_check": a2(used),
				"off_match": off.distance_to(used) < 1e-9,
				"house_local": a2(hl), "world": a2(cw),
				"terrain_y": q(W.surface_y(cw.x, cw.y), 4),
				"bed_top_y": q(plateau + 0.20, 4),
				"ij_roundtrip": f.slot_ij(s_idx).x == i and f.slot_ij(s_idx).y == j,
			})
	return out


func station(name: String, center: Vector2, plateau_override_v: float) -> Dictionary:
	var env := envelopes()
	var hf: float = env["half_fence"]
	var te_all := env_terrain(center, hf, 0.05)
	var te_edge := env_terrain_edge(center, hf, 0.05)
	var plateau := plateau_override_v
	var plateau_src := "override"
	if plateau < 0.0:
		plateau = float(te_all["max"]) - CUT
		plateau_src = "env_max-0.04"
	var cw := f2w(center, 0.0, 0.0)
	var st := {
		"name": name, "center_local": a2(center), "center_world": a2(cw),
		"plateau": q(plateau, 4), "plateau_src": plateau_src,
		"env_terrain_min": q(float(te_all["min"]), 4), "env_terrain_max": q(float(te_all["max"]), 4),
		"env_terrain_spread": q(float(te_all["max"]) - float(te_all["min"]), 4),
		"env_edge_min": q(float(te_edge["min"]), 4), "env_edge_max": q(float(te_edge["max"]), 4),
		"env_argmax_local": a2(te_all["argmax_local"]), "env_argmin_local": a2(te_all["argmin_local"]),
		"cut_above_max": q(float(te_all["max"]) - plateau, 4),
		"fence_top_y": q(plateau + POST_H, 4),
		"bed_top_y": q(plateau + 0.20, 4),
		"envelopes": {
			"half_cells_nominal": q(env["half_cells_nominal"]), "half_cells_rim": q(env["half_cells_rim"]),
			"half_plot": q(env["half_plot"]), "half_fence": q(env["half_fence"]),
			"half_post_outer": q(env["half_post_outer"]), "half_podium": q(env["half_podium"]),
			"corners_cells": [a2(Vector2(-env["half_cells_nominal"], -env["half_cells_nominal"]).rotated(0.0)), a2(Vector2(env["half_cells_nominal"], env["half_cells_nominal"]))],
			"corners_plot": [a2(Vector2(-env["half_plot"], -env["half_plot"])), a2(Vector2(env["half_plot"], env["half_plot"]))],
			"corners_fence": [a2(Vector2(-hf, -hf)), a2(Vector2(hf, hf))],
			"corners_podium": [a2(Vector2(-env["half_podium"], -env["half_podium"])), a2(Vector2(env["half_podium"], env["half_podium"]))],
			"corners_fence_world": [a2(f2w(center, -hf, -hf)), a2(f2w(center, hf, hf)),
				a2(f2w(center, -hf, hf)), a2(f2w(center, hf, -hf))],
		},
		"clearances": {
			"gap_net_rim": q((CELL + GAP) - 2.0 * RIM_HALF),
			"gap_net_soil": q((CELL + GAP) - 2.0 * SOIL_HALF),
			"walkway_clear": q((float(env["half_fence"]) - POST_R) - float(env["half_cells_rim"])),
			"fence_to_podium_edge": q(float(env["half_podium"]) - float(env["half_fence"])),
			"walkway_nominal": q(BORDER),
		},
	}
	var cells := cells_table(center, plateau)
	st["cells"] = cells
	# 门口 / 踏步
	var gw := gate_world(center, plateau)
	st["gate"] = {"centre_world": a2(gw["centre"]), "y": q(plateau, 4),
		"left_post": a2(gw["left_post"]), "right_post": a2(gw["right_post"]),
		"post_gap": q(GATE_W)}
	var steps := steps_table(center, plateau)
	var step_json: Array = []
	var prev_top := plateau
	var max_riser := 0.0
	for s in steps:
		var top: float = s["top"]
		var riser := prev_top - top
		max_riser = maxf(max_riser, riser)
		prev_top = top
		step_json.append({"idx": int(s["idx"]), "d": q(float(s["d_from_fence"])), "world": a2(s["world"]),
			"terrain": q(float(s["terrain"]), 4), "top": q(top, 4), "riser_down": q(riser, 4)})
	st["steps"] = step_json
	st["max_riser"] = q(max_riser, 4)
	# 距离
	var dh := dist_to_house(center)
	st["dist_house"] = {"to_front_wall": q(float(dh["to_front_wall"])), "to_porch": q(float(dh["to_porch"])),
		"fence_local": a2(dh["front_wall_local"]), "house_local_pt": a2(dh["front_wall_house_local"])}
	var dp := dist_to_path(center)
	st["dist_path"] = {"min_clear": q(float(dp["min_clear"])), "fence_local": a2(dp["local"]),
		"world": a2(dp["world"])}
	var gpd := gate_path_distance(center)
	st["gate_path"] = {"to_road_edge": q(float(gpd["edge_dist"])), "clear_at_fence": q(float(gpd["clear_at_fence"])),
		"along_ray": q(float(gpd["along_ray"])), "nearest_centre": gpd["nearest_centre"],
		"nearest_half_w": q(float(gpd["nearest_half_w"])),
		"slab_cover": 2.40, "rest_after_slabs": q(maxf(0.0, float(gpd["edge_dist"]) - 2.40))}
	# 步行
	var entry := Vector2(0.0, -hf)
	var ring_s := (float(env["half_cells_nominal"]) + float(env["half_plot"])) * 0.5
	var ring_entry := Vector2(0.0, -ring_s)
	var walk: Array = []
	var per := 8.0 * ring_s
	for c in cells:
		var fx: float = c["farm_off"][0]
		var fz: float = c["farm_off"][1]
		var rp := ring_point_nearest(center, fx, fz, ring_s)
		var d_in := entry.distance_to(ring_entry)
		var pa := ring_param(ring_entry, ring_s)
		var pb := ring_param(rp, ring_s)
		var dd := absf(pa - pb)
		dd = minf(dd, per - dd)
		var radial := rp.distance_to(Vector2(fx, fz))
		walk.append({"slot": c["slot"], "i": c["i"], "j": c["j"],
			"ring_point": a2(rp), "ring_travel": q(dd), "radial_from_ring": q(radial),
			"walk_to_edge": q(d_in + dd + maxf(0.0, radial - SOIL_HALF)),
			"walk_to_centre": q(d_in + dd + radial),
			"straight_from_gate": q(entry.distance_to(Vector2(fx, fz)))})
	st["walk"] = walk
	st["ring_s"] = q(ring_s)
	return st


func viewer(name: String, cam: Dictionary) -> Dictionary:
	return {"name": name, "pos": a3(cam["pos"]), "fov": float(cam["fov"]),
		"clamped": bool(cam["clamped"]), "basis_x": a3(cam["basis"].x), "basis_y": a3(cam["basis"].y),
		"basis_z": a3(cam["basis"].z)}


## 地面标高勘察：房屋局部点 -> 世界 -> surface_y
func _do_surf() -> void:
	W._prepare()
	var hg := M.house_ground_y()
	var dw := M.door_world()
	_p("house_ground_y", hg)
	_p("door_world", str(dw))
	_p("door_approach_world", str(M.door_approach()))
	var pts: Array = [[0, 0], [0, 3.10], [0, 3.40], [0, 5.50], [-0.60, 5.65], [0, 7.45],
		[-4.30, 3.40], [4.30, 3.40], [-4.30, 7.45], [0, 8.50], [0, 9.00], [0, 10.00],
		[-4.35, 10.19], [-4.35, 10.49], [-2.71, 12.9], [-7.06, 13.2], [-1.45, 12.9],
		[-0.60, 6.60], [-6.50, 12.90], [-8.50, 12.90], [-4.35, 15.90], [-4.35, 6.00]]
	var rows: Array = []
	for pt in pts:
		var wl := l2w(float(pt[0]), float(pt[1]))
		rows.append({"local": [float(pt[0]), float(pt[1])], "world": a2(wl),
			"surface_y": q(W.surface_y(wl.x, wl.y), 4),
			"terrain_y": q(M.terrain_height(wl.x, wl.y), 4),
			"path_clear": q(W._path_clearance(wl.x, wl.y), 3),
			"in_porch": W._in_porch(wl.x, wl.y, 0.0)})
		print("SURF " + JSON.stringify(rows))


# ------------------------------------------------- 候选台适配（Lead 数据） ---
func poly_min_dist(p: Vector2, poly: Array) -> float:
	var best := 1e9
	var n := poly.size()
	for i in range(n):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % n]
		var ab := b - a
		var t := 0.0
		if ab.length_squared() > 1e-9:
			t = clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


func point_in_poly(p: Vector2, poly: Array) -> bool:
	var inside := false
	var n := poly.size()
	var j := n - 1
	for i in range(n):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[j]
		if (a.x > p.x) != (b.x > p.x):
			var yy := (b.y - a.y) / (b.x - a.x) * (p.x - a.x) + a.y
			if p.y < yy:
				inside = not inside
		j = i
	return inside


## 点相对多边形：在内部返回 +distance，在外部返回 -distance
func poly_margin(p: Vector2, poly: Array) -> float:
	var d := poly_min_dist(p, poly)
	return d if point_in_poly(p, poly) else -d


func pad_fit(center: Vector2, poly: Array) -> Dictionary:
	var hf: float = envelopes()["half_fence"]
	var hp: float = envelopes()["half_podium"]
	var probes: Array = []
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			probes.append(["fence_corner", Vector2(sx * hf, sz * hf)])
			probes.append(["podium_corner", Vector2(sx * hp, sz * hp)])
	var worst := 1e9
	var worst_row: Array = []
	var rows: Array = []
	for pr in probes:
		var lp: Vector2 = center + (pr[1] as Vector2)
		var m := poly_margin(lp, poly)
		rows.append({"kind": pr[0], "farm_local": a2(pr[1]), "house_local": a2(lp),
			"margin": q(m), "inside": m > 0.0})
		if m < worst:
			worst = m
			worst_row = [pr[0], a2(pr[1]), q(m)]
	# 沿围栏四边细分采样，捕捉窄夹点
	for e in range(4):
		for s in range(1, 10):
			var t := float(s) / 10.0
			var a := Vector2(-hf, -hf)
			var b := Vector2(hf, -hf)
			if e == 1:
				a = Vector2(-hf, hf); b = Vector2(hf, hf)
			elif e == 2:
				a = Vector2(-hf, -hf); b = Vector2(-hf, hf)
			elif e == 3:
				a = Vector2(hf, -hf); b = Vector2(hf, hf)
			var fl: Vector2 = a + (b - a) * t
			var m2 := poly_margin(center + fl, poly)
			if m2 < worst:
				worst = m2
				worst_row = ["fence_edge", a2(fl), q(m2)]
	return {"min_margin": q(worst), "worst": worst_row, "corner_rows": rows,
		"fence_footprint_in_pad": worst > 0.0}


func cand_block(stations: Array) -> Array:
	var out: Array = []
	var env := envelopes()
	var half_podium: float = env["half_podium"]
	var col: Array = []
	var hg := M.house_ground_y()
	out.append({"note": "house_ground_y", "value": q(hg, 4)})
	for idx in range(CAND_NAMES.size()):
		var nm := String(CAND_NAMES[idx])
		var c: Vector2 = CAND_CENTERS[idx]
		var terr := float(CAND_TERRACE[idx])
		var poly: Array = PADS[idx]
		var obj := {"name": nm, "center_local": a2(c), "center_world": a2(l2w(c.x, c.y)),
			"terrace_y": terr, "gate_y": terr}
		# 台面/围栏/土床标高
		obj["fence_top_y"] = q(terr + POST_H, 4)
		obj["bed_top_y"] = q(terr + 0.20, 4)
		obj["rail_top_y"] = q(terr + 0.64 + RAIL_R, 4)
		# 台适配
		obj["pad_fit"] = pad_fit(c, poly)
		# 地形：包络内 max/min 与台面相对
		var te := env_terrain(c, float(env["half_podium"]), 0.05)
		var sx: Dictionary = stations[idx]
		obj["env_argmax_local"] = sx["env_argmax_local"]
		obj["env_argmin_local"] = sx["env_argmin_local"]
		var dh: Dictionary = sx["dist_house"]
		obj["dist_house"] = dh
		obj["terrace_minus_house_ground"] = q(terr - M.house_ground_y(), 4)
		obj["gate_to_porch_edge"] = q(dh["to_porch"] - float(env["half_fence"]), 3)
		obj["env_terrain_min"] = q(float(te["min"]), 4)
		obj["env_terrain_max"] = q(float(te["max"]), 4)
		obj["terrain_cut_needed"] = q(float(te["max"]) - terr, 4)
		obj["terrain_fill_needed"] = q(maxf(0.0, terr - float(te["max"])), 4)
		obj["terrain_above_podium_top"] = q(maxf(0.0, float(te["max"]) - terr), 4)
		# 九格
		var f := FSC.new()
		var cells: Array = []
		var gate_l := Vector2(0.0, -float(env["half_fence"]))
		for s in range(9):
			var ij: Vector2i = f.slot_ij(s)
			var off: Vector2 = f.slot_offset(s)
			var wl := l2w(c.x + off.x, c.y + off.y)
			var cheb := maxf(absf(off.x), absf(off.y))
			var gate_d := off.distance_to(gate_l)
			var cam := cam_xform(M.CAM_START_THETA, 0.28, M.CAM_START_R, M.CAM_TARGET, 42.0)
			var p3 := Vector3(wl.x, terr + 0.20, wl.y)
			var bx: Vector3 = cam["basis"].x
			var pa := ndc(cam, p3 - bx * (SOIL_HALF))
			var pb := ndc(cam, p3 + bx * (SOIL_HALF))
			var px := absf(pb.x - pa.x) * 960.0
			cells.append({"slot": s, "i": ij.x, "j": ij.y,
				"farm_off": a2(off),
				"house_local": a2(Vector2(c.x + off.x, c.y + off.y)),
				"world": a2(wl),
				"terrain_y": q(W.surface_y(wl.x, wl.y), 4),
				"terrain_dy": q(W.surface_y(wl.x, wl.y) - terr, 3),
				"rim_to_fence_inner": q((float(env["half_fence"]) - POST_R) - (cheb + RIM_HALF)),
				"rim_to_plot_edge": q(float(env["half_plot"]) - (cheb + RIM_HALF)),
				"rim_to_walk_centre": q((float(env["half_cells_nominal"]) + float(env["half_plot"])) * 0.5 - (cheb + RIM_HALF)),
				"gate_centre_dist": q(gate_d), "gate_edge_dist": q(gate_d - SOIL_HALF - 0.5),
				"screen_px_play": q(px, 1),
				"dist_play": q(p3.distance_to(cam["pos"]), 1)})
		obj["cells"] = cells
		# 九格外包络
		obj["cells_bbox_half"] = q(float(env["half_cells_rim"]))
		obj["cells_bbox_w"] = q(2.0 * float(env["half_cells_rim"]))
		# 围栏/走道/门洞净距汇总
		var gaps: Array = []
		for cc in cells:
			gaps.append({"slot": cc["slot"], "rim_to_fence_inner": cc["rim_to_fence_inner"],
				"rim_to_plot_edge": cc["rim_to_plot_edge"]})
		obj["ring_gaps"] = gaps
		# 灯与冲突
		var lamps: Array = []
		for lp in LAMPS:
			var ll: Vector2 = lp[1]
			var fl := ll - c
			var cheb2 := maxf(absf(fl.x), absf(fl.y))
			var dl := Vector2(fl.x, fl.y + float(env["half_fence"])).length()
			lamps.append({"name": lp[0], "house_local": a2(ll), "farm_local": a2(fl),
				"cheb_from_center": q(cheb2),
				"fence_ring_clear": q(cheb2 - (float(env["half_fence"]) + POST_R)),
				"gate_clear": q(dl - GATE_W * 0.5),
				"inside_pad": point_in_poly(ll, poly),
				"pad_margin": q(poly_margin(ll, poly)),
				"inside_fence_footprint": cheb2 < float(env["half_fence"]) + POST_R})
		obj["lamps"] = lamps
		# 路
		var dp := dist_to_path(c)
		obj["path"] = {"min_clear": q(float(dp["min_clear"])), "fence_local": a2(dp["local"]),
			"world": a2(dp["world"])}
		var gpd := gate_path_distance(c)
		obj["gate_path"] = {"to_road_edge": q(float(gpd["edge_dist"])),
			"nearest_centre_local": a2(w2l(float(gpd["nearest_centre"][0]), float(gpd["nearest_centre"][1]))),
			"rest_after_slabs": q(maxf(0.0, float(gpd["edge_dist"]) - 2.40))}
		# 门前小径（candidates.json gate_walkway: (-0.60,5.65) -> gate）交角/长度
		var g0 := Vector2(-0.60, 5.65)
		var g1 := Vector2(c.x, c.y - float(env["half_fence"]))
		obj["gate_walkway"] = {"from_local": a2(g0), "to_local": a2(g1),
			"len": q(g0.distance_to(g1)),
			"grade_dy": q(terr - W.surface_y(l2w(g0.x, g0.y).x, l2w(g0.x, g0.y).y), 3)}
		# 可达性
		var st: Dictionary = stations[idx]
		obj["vis"] = {"play_min": st["vis"]["play"]["min_frac"],
			"play_full": st["vis"]["play"]["full_visible_cells"],
			"play_cells": st["vis"]["play"]["cells"],
			"movie_min": st["vis"]["movie"]["min_frac"],
			"movie_full": st["vis"]["movie"]["full_visible_cells"],
			"porch_min": st["vis"]["porch_eye"]["min_frac"],
			"gate_min": st["vis"]["gate_eye"]["min_frac"],
			"wall_blocked": st["wall_test"]["blocked_cells_total"]}
		obj["walk_min_to_edge"] = q(_min_walk(st, "walk_to_edge"))
		obj["walk_min_to_centre"] = q(_min_walk(st, "walk_to_centre"))
		obj["walk_max_to_edge"] = q(_max_walk(st, "walk_to_edge"))
		obj["walk_max_to_centre"] = q(_max_walk(st, "walk_to_centre"))
		obj["walk_table"] = st["walk"]
		obj["env_terrain_spread"] = st["env_terrain_spread"]
		obj["cut_above_max"] = st["cut_above_max"]
		out.append(obj)
	return out


func _min_walk(st: Dictionary, key: String) -> float:
	var m := 1e9
	for w in st["walk"]:
		m = minf(m, float(w[key]))
	return m


func _max_walk(st: Dictionary, key: String) -> float:
	var m := -1e9
	for w in st["walk"]:
		m = maxf(m, float(w[key]))
	return m


# ------------------------------------ v3-frozen 复算（candidates_p2a.json） ---
const V3_PATH := "D:/休闲小岛幻境/开发产物/P9/P2A/candidates_p2a.json"
const V3_MAIN := [Vector2(0.0, 5.5), Vector2(1.867, 10.208), Vector2(5.215, 12.918), Vector2(9.137, 15.806)]
const V3_SPUR := [Vector2(0.0, 5.5), Vector2(-1.893, 7.474), Vector2(-4.406, 6.121), Vector2(-6.115, 3.865), Vector2(-6.869, 1.225), Vector2(-7.056, -1.555)]
const V3_MAIN_HW := 0.31
const V3_SPUR_HW := 0.25
const TAN32 := 0.624869


func v3_poly(arr: Array) -> Array:
	var out: Array = []
	for p in arr:
		out.append(Vector2(float(p[0]), float(p[1])))
	return out


func v3_area(poly: Array) -> float:
	var a := 0.0
	var n := poly.size()
	for i in range(n):
		var p: Vector2 = poly[i]
		var r: Vector2 = poly[(i + 1) % n]
		a += p.x * r.y - r.x * p.y
	return absf(a) * 0.5


func v3_bbox(poly: Array) -> Array:
	var x0 := 1e9
	var z0 := 1e9
	var x1 := -1e9
	var z1 := -1e9
	for p in poly:
		x0 = minf(x0, p.x)
		x1 = maxf(x1, p.x)
		z0 = minf(z0, p.y)
		z1 = maxf(z1, p.y)
	return [x0, z0, x1, z1]


func v3_terr(lx: float, lz: float) -> float:
	var w := l2w(lx, lz)
	return M.terrain_height(w.x, w.y)


func v3_base(spec: Dictionary, lx: float, lz: float) -> float:
	var mode := String(spec.get("mode", "flat"))
	var h := v3_terr(lx, lz)
	if mode == "flat":
		return float(spec["y"])
	if mode == "blend":
		var z0 := float(spec.get("z0", 0.0))
		var z1 := float(spec.get("z1", 1.0))
		var off := float(spec.get("offset", 0.0))
		var far := float(spec.get("far", h + off))
		var t := clampf((lz - z0) / maxf(z1 - z0, 1e-6), 0.0, 1.0)
		var ss := t * t * (3.0 - 2.0 * t)
		return maxf(lerpf(h + off, far, ss), h + 0.02)
	if mode == "ramp":
		var rz0 := float(spec.get("z0", 0.0))
		var rz1 := float(spec.get("z1", 1.0))
		var near := float(spec.get("near", h))
		var far2 := float(spec.get("far", h))
		var rt := clampf((lz - rz0) / maxf(rz1 - rz0, 1e-6), 0.0, 1.0)
		return lerpf(near, far2, rt * rt * (3.0 - 2.0 * rt))
	return h


func v3_edge_samples(poly: Array, step: float) -> Array:
	var out: Array = []
	var n := poly.size()
	for i in range(n):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % n]
		var ln := a.distance_to(b)
		var k := maxi(1, int(ceil(ln / step)))
		for s in range(k + 1):
			out.append(a.lerp(b, float(s) / float(k)))
	return out


func v3_fp_margin(center: Vector2, poly: Array, half: float, step: float) -> Dictionary:
	var worst := 1e9
	var worst_fl := Vector2.ZERO
	var edges := [
		[Vector2(-half, -half), Vector2(half, -half)],
		[Vector2(-half, half), Vector2(half, half)],
		[Vector2(-half, -half), Vector2(-half, half)],
		[Vector2(half, -half), Vector2(half, half)],
	]
	for e in edges:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var ln := a.distance_to(b)
		var k := maxi(1, int(ceil(ln / step)))
		for s in range(k + 1):
			var fl: Vector2 = a.lerp(b, float(s) / float(k))
			var m := poly_margin(center + fl, poly)
			if m < worst:
				worst = m
				worst_fl = fl
	return {"half": q(half), "min_margin": q(worst), "worst_farm_local": a2(worst_fl)}


func v3_pl_dist(p: Vector2, pts: Array) -> float:
	var best := 1e9
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var ab := b - a
		var t := 0.0
		if ab.length_squared() > 1e-9:
			t = clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


func v3_cand(c: Dictionary, cam_play: Dictionary, cam_movie: Dictionary, nvis: int) -> Dictionary:
	var pad: Dictionary = c["pad"]
	var poly := v3_poly(pad["polygon_local"])
	var spec: Dictionary = pad["top"]
	var farm: Dictionary = pad["farm"]
	var cid := String(c.get("id", ""))
	var center := Vector2(float(farm["center_local"][0]), float(farm["center_local"][1]))
	var bb := v3_bbox(poly)
	var env := envelopes()
	var hf: float = env["half_fence"]
	var m_fence := v3_fp_margin(center, poly, hf, 0.05)
	var m_post := v3_fp_margin(center, poly, float(env["half_post_outer"]), 0.05)
	var m_walk := v3_fp_margin(center, poly, float(env["half_plot"]), 0.05)
	var m_rim := v3_fp_margin(center, poly, float(env["half_cells_rim"]), 0.05)
	var m_nom := v3_fp_margin(center, poly, float(env["half_cells_nominal"]), 0.05)
	# 农田（围栏占地 ±2.71）内台面标高范围
	var dmin := 1e9
	var dmax := -1e9
	var dl := Vector2.ZERO
	var nz := int(ceil(2.0 * hf / 0.10))
	for a in range(nz + 1):
		for b in range(nz + 1):
			var fl := Vector2(-hf + 2.0 * hf * float(a) / float(nz), -hf + 2.0 * hf * float(b) / float(nz))
			var d := v3_base(spec, center.x + fl.x, center.y + fl.y)
			if d < dmin:
				dmin = d
			if d > dmax:
				dmax = d
				dl = fl
	var terrace := dmax
	# 9 格
	var cells: Array = []
	for s2 in range(9):
		var i2 := s2 % 3
		var j2 := int(s2 / 3)
		var off := Vector2(float(i2 - 1) * float(env["pitch"]), float(j2 - 1) * float(env["pitch"]))
		var hl := center + off
		var terr := v3_terr(hl.x, hl.y)
		var deck := v3_base(spec, hl.x, hl.y)
		cells.append({"slot": s2, "i": i2, "j": j2, "farm_off": a2(off), "house_local": a2(hl),
			"world": a2(l2w(hl.x, hl.y)), "terrain": q(terr), "deck": q(deck),
			"delta": q(deck - terr), "bed_top": q(deck + 0.20), "rim_top": q(deck + 0.055)})
	# 填/切（0.25 栅格，多边形内）
	var fill_max := 0.0
	var cut_max := 0.0
	var fill_at := Vector2.ZERO
	var cut_at := Vector2.ZERO
	var x := float(bb[0])
	while x <= float(bb[2]):
		var z := float(bb[1])
		while z <= float(bb[3]):
			var p := Vector2(x, z)
			if point_in_poly(p, poly):
				var b2 := v3_base(spec, x, z)
				var h2 := v3_terr(x, z)
				if b2 - h2 > fill_max:
					fill_max = b2 - h2
					fill_at = p
				if h2 - b2 > cut_max:
					cut_max = h2 - b2
					cut_at = p
			z += 0.25
		x += 0.25
	# 外沿标高 / 斜裙
	var ebase_min := 1e9
	var ebase_max := -1e9
	var edrop_max := 0.0
	var ew_max := 0.0
	var ew_at := Vector2.ZERO
	for p2 in v3_edge_samples(poly, 0.30):
		var b3 := v3_base(spec, p2.x, p2.y)
		var h3 := v3_terr(p2.x, p2.y)
		ebase_min = minf(ebase_min, b3)
		ebase_max = maxf(ebase_max, b3)
		var drop := b3 - h3
		if drop > edrop_max:
			edrop_max = drop
			if drop > 0.10 and bool(pad.get("bank", true)):
				var bw := clampf(drop / TAN32, 0.8, 3.6)
				if bw > ew_max:
					ew_max = bw
					ew_at = p2
	# 门
	var gate := Vector2(center.x, center.y - hf)
	var gate_deck := v3_base(spec, gate.x, gate.y)
	var gwv := l2w(gate.x, gate.y)
	var gate_clear := W._path_clearance(gwv.x, gwv.y)
	# 门前小径（candidates gate_walkway 起点 (-0.60,5.48) → 门洞）
	var wstart := Vector2(-0.60, 5.48)
	var wk_len := wstart.distance_to(gate)
	var wk_drop := v3_base(spec, wstart.x, wstart.y) - gate_deck
	# 门外 8 块石板（同 station 口径：top=max(surface_y+0.05, 台面-0.06)）
	var stps := steps_table(center, gate_deck)
	var prev_top := gate_deck
	var max_riser := 0.0
	var stp_json: Array = []
	for s0 in stps:
		var top_s: float = float(s0["top"])
		var riser_s := prev_top - top_s
		max_riser = maxf(max_riser, riser_s)
		prev_top = top_s
		stp_json.append({"idx": int(s0["idx"]), "d": q(float(s0["d_from_fence"])), "terrain": q(float(s0["terrain"]), 4), "top": q(top_s, 4), "riser_down": q(riser_s, 4)})
	# 距离（沿围栏占地环）
	var fw_min := 1e9
	var porch_min := 1e9
	var main_min := 1e9
	var spur_min := 1e9
	var pc_min := 1e9
	var pc_at := Vector2.ZERO
	var hw: float = M.HOUSE_W * 0.5
	var hd: float = M.HOUSE_D * 0.5
	for p3 in fence_ring_points(hf, 0.02):
		var hl3: Vector2 = center + p3
		fw_min = minf(fw_min, rect_dist_house_rect(hl3.x, hl3.y, -hw, hw, hd, hd))
		porch_min = minf(porch_min, rect_dist_house_rect(hl3.x, hl3.y, -4.30, 4.30, 3.40, 7.45))
		main_min = minf(main_min, v3_pl_dist(hl3, V3_MAIN) - V3_MAIN_HW)
		spur_min = minf(spur_min, v3_pl_dist(hl3, V3_SPUR) - V3_SPUR_HW)
		var w2 := l2w(hl3.x, hl3.y)
		var d2 := W._path_clearance(w2.x, w2.y)
		if d2 < pc_min:
			pc_min = d2
			pc_at = hl3
	# 灯
	var lamps: Array = []
	for lp in LAMPS:
		var l: Vector2 = lp[1]
		var mi := poly_margin(l, poly)
		var b4 := v3_base(spec, l.x, l.y)
		var h4 := v3_terr(l.x, l.y)
		lamps.append({"name": String(lp[0]), "local": a2(l), "inside_pad": mi > 0.0, "margin": q(mi),
			"terrain": q(h4), "pad_base": q(b4), "delta": q(b4 - h4)})
	# 可见性（play/movie）
	var occ := build_occluders(center, terrace)
	var vp: Array = []
	var vmin := 1.0
	var full := 0
	for s3 in range(9):
		var cc: Dictionary = cells[s3]
		var v := vis_cell(cam_play, center, s3 % 3, int(s3 / 3), float(cc["bed_top"]), occ, nvis)
		vp.append({"frac": q(v["frac"]), "by_post": v["by_post"], "by_rail": v["by_rail"]})
		vmin = minf(vmin, v["frac"])
		if v["frac"] > 0.999:
			full += 1
	var vm: Array = []
	var vmin_m := 1.0
	for s4 in range(9):
		var cc2: Dictionary = cells[s4]
		var v2 := vis_cell(cam_movie, center, s4 % 3, int(s4 / 3), float(cc2["bed_top"]), occ, nvis)
		vm.append(q(v2["frac"]))
		vmin_m = minf(vmin_m, v2["frac"])
	var wb := 0
	for s5 in range(9):
		var cc3: Dictionary = cells[s5]
		var wr := wall_blocked(cam_play, center, Vector3(float(cc3["world"][0]), float(cc3["bed_top"]), float(cc3["world"][1])), terrace)
		if bool(wr["blocked"]):
			wb += 1
	return {
		"id": cid, "label": String(c.get("label", "")),
		"center_farm_local": a2(center), "center_world": a2(l2w(center.x, center.y)),
		"pad": {"area_m2": q(v3_area(poly), 2),
			"bbox_local": [q(float(bb[0])), q(float(bb[1])), q(float(bb[2])), q(float(bb[3]))],
			"polygon_local": pad["polygon_local"], "top_spec": spec, "bank": bool(pad.get("bank", true))},
		"margins": {"fence": m_fence, "post_outer": m_post, "walkway_outer": m_walk,
			"soil_rim": m_rim, "soil_top": m_nom},
		"farm": {"deck_min": q(dmin), "deck_max": q(dmax), "level_delta": q(dmax - dmin),
			"max_at_farm_local": a2(dl), "terrace": q(terrace)},
		"fill_cut": {"fill_max": q(fill_max), "fill_at": a2(fill_at), "cut_max": q(cut_max), "cut_at": a2(cut_at)},
		"edge": {"base_min": q(ebase_min), "base_max": q(ebase_max), "drop_max": q(edrop_max),
			"skirt_max_width": q(ew_max), "skirt_at": a2(ew_at)},
		"gate": {"local": a2(gate), "world": a2(l2w(gate.x, gate.y)), "deck": q(gate_deck),
			"margin_to_pad_edge": q(poly_margin(gate, poly)), "clear_at_gate": q(gate_clear),
			"to_road_edge": q(maxf(0.0, gate_clear)), "rest_after_slabs": q(maxf(0.0, gate_clear - 2.40))},
		"walkway": {"from_local": a2(wstart), "length": q(wk_len), "drop": q(wk_drop),
			"grade": q(wk_drop / maxf(0.001, wk_len), 4)},
		"steps": {"max_riser": q(max_riser, 4), "lip_height": q(float(stp_json[0]["top"]) - gate_deck, 4), "slabs": stp_json},
		"cells": cells,
		"dist": {"front_wall": q(fw_min), "porch": q(porch_min), "main_path_edge": q(main_min),
			"spur_edge": q(spur_min), "any_path_clear": q(pc_min), "any_path_at": a2(pc_at),
			"pad_near_to_wall": q(float(bb[1]) - hd), "pad_near_to_porch": q(3.40 - float(bb[1]))},
		"lamps": lamps,
		"visibility": {"play_min": q(vmin), "play_full": full, "play_cells": vp,
			"movie_min": q(vmin_m), "movie_cells": vm, "wall_blocked_play": wb},
	}


func _do_v3() -> void:
	var fh := FileAccess.open(V3_PATH, FileAccess.READ)
	if fh == null:
		print("B_V3_ERR open " + V3_PATH)
		return
	var txt := fh.get_as_text()
	fh.close()
	var data = JSON.parse_string(txt)
	if data == null:
		print("B_V3_ERR parse")
		return
	W._prepare()
	var cam_play := cam_xform(M.CAM_START_THETA, 0.28, M.CAM_START_R, M.CAM_TARGET, 42.0)
	var cam_movie := cam_xform(0.30, 0.50, 106.0, Vector3(0, 4.2, 0), 36.0)
	var out: Array = []
	for c in data["candidates"]:
		var r := v3_cand(c, cam_play, cam_movie, 11)
		out.append(r)
		var mg: Dictionary = r["margins"]
		print("[B] v3 " + String(r["id"]) + " fence_margin=" + str(mg["fence"]["min_margin"]) +
			" post_outer_margin=" + str(mg["post_outer"]["min_margin"]) +
			" soil_margin=" + str(mg["soil_rim"]["min_margin"]) +
			" deck=" + str(r["farm"]["deck_min"]) + ".." + str(r["farm"]["deck_max"]) +
			" fill=" + str(r["fill_cut"]["fill_max"]) + " cut=" + str(r["fill_cut"]["cut_max"]) +
			" wall=" + str(r["dist"]["front_wall"]) + " porch=" + str(r["dist"]["porch"]) +
			" main=" + str(r["dist"]["main_path_edge"]) + " spur=" + str(r["dist"]["spur_edge"]) +
			" vis=" + str(r["visibility"]["play_min"]) + "/" + str(r["visibility"]["play_full"]))
	var payload := {"version": "p2a-v3-frozen", "source": V3_PATH,
		"engine": Engine.get_version_info()["string"], "headless": DisplayServer.get_name() == "headless",
		"house_ground_y": q(M.house_ground_y(), 4), "vis_samples": 11, "candidates": out}
	print("B_V3 " + JSON.stringify(payload))
	print("[B] v3 done")


func _run() -> void:
	_parse()
	_res = {"engine": Engine.get_version_info()["string"], "headless": DisplayServer.get_name() == "headless"}
	if surf_mode:
		_do_surf()
		quit(0)
		return
	if v3_mode:
		_do_v3()
		quit(0)
		return
	if centers.is_empty():
		if cands_mode:
			centers = [CAND_CENTERS[0], CAND_CENTERS[1], CAND_CENTERS[2]]
		else:
			centers = [Vector2(-4.00, 13.20), Vector2(0.0, 0.0)]
	W._prepare()
	# ---------------- 1) 数据层常量与索引 ----------------
	var f := FSC.new()
	var pitch := float(FSC.GRID_PITCH)
	var consts := {"SLOT_COUNT": int(FSC.SLOT_COUNT), "GRID_PITCH": pitch, "pitch_expected": CELL + GAP,
		"slot_count_fn": int(f.slot_count()), "state_version": int(FSC.STATE_VERSION)}
	var grid: Array = []
	for s in range(9):
		var ij: Vector2i = f.slot_ij(s)
		var off: Vector2 = f.slot_offset(s)
		grid.append({"slot": s, "i": ij.x, "j": ij.y, "offset": a2(off)})
	_res["farm_consts"] = consts
	_res["grid_local"] = grid
	_res["slot_index_spot"] = [
		{"i": 0, "j": 0, "s": int(f.slot_index(0, 0))},
		{"i": 2, "j": 0, "s": int(f.slot_index(2, 0))},
		{"i": 0, "j": 2, "s": int(f.slot_index(0, 2))},
		{"i": 2, "j": 2, "s": int(f.slot_index(2, 2))},
		{"i": 5, "j": -3, "s": int(f.slot_index(5, -3))},
	]
	_p("farm_consts", consts)
	# ---------------- 2) 引擎变换实测 ----------------
	var tc := transform_check(centers[0])
	_res["transform_check"] = {"center": a2(centers[0]), "max_err": tc["max_err"], "worst": tc["worst"],
		"dir_plus_fx": tc["dir_plus_fx"], "dir_plus_fz": tc["dir_plus_fz"],
		"house_front_dir": tc["house_front_dir"], "house_front_err": tc["half_front_err"]}
	_p("transform_check max_err", tc["max_err"])
	_p("dir_plus_fx", tc["dir_plus_fx"])
	_p("dir_plus_fz", tc["dir_plus_fz"])
	# 相机
	var cam_play := cam_xform(M.CAM_START_THETA, 0.28, M.CAM_START_R, M.CAM_TARGET, 42.0)
	var cam_movie := cam_xform(0.30, 0.50, 106.0, Vector3(0, 4.2, 0), 36.0)
	_res["camera_play"] = viewer("play_default(theta0.74,elev0.28,r82,fov42,target(0,5,0))", cam_play)
	_res["camera_movie"] = viewer("movie_pose(theta0.30,elev0.50,r106,fov36,target(0,4.2,0))", cam_movie)
	_p("camera_play pos", cam_play["pos"])
	# ---------------- 3) 各田心站位 ----------------
	var stations: Array = []
	for idx in range(centers.size()):
		var c: Vector2 = centers[idx]
		var pv := plateau_override
		var nm := "base_%d" % idx
		if cands_mode and idx < CAND_NAMES.size():
			pv = float(CAND_TERRACE[idx])
			nm = String(CAND_NAMES[idx])
		elif idx == 0 and is_equal_approx(c.x, -4.0) and is_equal_approx(c.y, 13.2):
			pv = P1_PLATEAU
			nm = "P1"
		var st := station(nm, c, pv)
		# 视角与遮挡
		var viewers := {"play": cam_play, "movie": cam_movie}
		var gw := gate_world(c, float(st["plateau"]))
		var approach := f2w(c, 0.0, -float(envelopes()["half_fence"]) - 2.0)
		var slab_top := maxf(W.surface_y(approach.x, approach.y) + 0.05, float(st["plateau"]) - 0.06)
		var gate_cam := {"pos": Vector3(approach.x, slab_top + SPEC.HUMAN_EYE_H, approach.y),
			"basis": Basis.IDENTITY, "fov": 60.0, "clamped": false}
		var door := M.door_world()
		var porch_cam := {"pos": Vector3(door.x, door.y + SPEC.HUMAN_EYE_H, door.z),
			"basis": Basis.IDENTITY, "fov": 60.0, "clamped": false}
		viewers["gate_eye"] = gate_cam
		viewers["porch_eye"] = porch_cam
		var occ := build_occluders(c, float(st["plateau"]))
		var oc := occ_counts(occ)
		st["occluders"] = oc
		var vis_all := {}
		var n := 21
		for vk in ["play", "movie", "gate_eye", "porch_eye"]:
			var cam: Dictionary = viewers[vk]
			var per_cell: Array = []
			var min_frac := 1.0
			var full := 0
			var ndc_ok := true
			var worst_ndc := 0.0
			for cc in st["cells"]:
				var v := vis_cell(cam, c, int(cc["i"]), int(cc["j"]), float(st["plateau"]) + 0.20, occ, n)
				var nd := Vector2(0, 0)
				if vk == "play" or vk == "movie":
					nd = ndc(cam, Vector3(cc["world"][0], float(st["plateau"]) + 0.20, cc["world"][1]))
					worst_ndc = maxf(worst_ndc, maxf(absf(nd.x), absf(nd.y)))
					if absf(nd.x) > 1.0 or absf(nd.y) > 1.0:
						ndc_ok = false
				per_cell.append({"slot": cc["slot"], "i": cc["i"], "j": cc["j"],
					"vis_frac": q(float(v["frac"]), 3), "by_post": int(v["by_post"]), "by_rail": int(v["by_rail"]),
					"ndc": a2(nd), "dist": q(Vector3(cc["world"][0], float(st["plateau"]) + 0.2, cc["world"][1]).distance_to(cam["pos"]), 2)})
				min_frac = minf(min_frac, float(v["frac"]))
				if float(v["frac"]) >= 0.999:
					full += 1
			vis_all[vk] = {"cells": per_cell, "min_frac": q(min_frac, 3), "full_visible_cells": full,
				"all_in_frame": ndc_ok, "worst_abs_ndc": q(worst_ndc, 3)}
		st["vis"] = vis_all
		# 实墙保守判定（play/movie）
		var wall_info: Array = []
		var wall_block := 0
		for vk in ["play", "movie"]:
			var cam: Dictionary = viewers[vk]
			for cc in st["cells"]:
				var wb := wall_blocked(cam, c, Vector3(cc["world"][0], float(st["plateau"]) + 0.20, cc["world"][1]), float(st["plateau"]))
				if bool(wb["blocked"]):
					wall_block += 1
				wall_info.append({"viewer": vk, "slot": cc["slot"], "blocked": bool(wb["blocked"]),
					"y_at_fence": q(float(wb["y_at_fence"]), 3), "fence_top": q(float(wb["fence_top"]), 3),
					"edge": String(wb["edge"]) if wb.has("edge") else ""})
		st["wall_test"] = {"blocked_cells_total": wall_block, "rows": wall_info}
		# 围栏包络四角与格心的 NDC（取景）
		var frustum: Array = []
		for cp in st["envelopes"]["corners_fence_world"]:
			var nd := ndc(cam_play, Vector3(float(cp[0]), float(st["plateau"]) + POST_H, float(cp[1])))
			frustum.append({"corner": cp, "ndc": a2(nd)})
		st["frustum_fence_corners_play"] = frustum
		stations.append(st)
		_p("station " + nm, "local=%s world=%s plateau=%.4f env[min=%.3f max=%.3f] cut=%.4f" % [
			str(a2(c)), str(a2(f2w(c, 0, 0))), float(st["plateau"]),
			float(st["env_terrain_min"]), float(st["env_terrain_max"]), float(st["cut_above_max"])])
		_p("  fence_top", st["fence_top_y"])
		_p("  occluders", oc)
		_p("  dist_path min_clear", st["dist_path"]["min_clear"])
		_p("  gate_path to_road_edge", "%s along_ray=%s nearest_centre=%s" % [str(st["gate_path"]["to_road_edge"]), str(st["gate_path"]["along_ray"]), str(st["gate_path"]["nearest_centre"])])
		_p("  vis play", "min=%.3f full=%d in_frame=%s worst_ndc=%.3f" % [
			float(st["vis"]["play"]["min_frac"]), int(st["vis"]["play"]["full_visible_cells"]),
			str(st["vis"]["play"]["all_in_frame"]), float(st["vis"]["play"]["worst_abs_ndc"])])
		_p("  vis porch_eye", "min=%.3f full=%d" % [float(st["vis"]["porch_eye"]["min_frac"]), int(st["vis"]["porch_eye"]["full_visible_cells"])])
		_p("  wall_blocked_cells", st["wall_test"]["blocked_cells_total"])
	_res["stations"] = stations
	# ---------------- 4) 台面标高假设（院面 7.5±0.2）----------------
	var hypo: Array = []
	for pv in [7.30, 7.50, 7.70]:
		var pvf := float(pv)
		var st2 := station("hypo_plateau_%.2f" % pvf, centers[0], pvf)
		var occ2 := build_occluders(centers[0], pvf)
		var door2 := M.door_world()
		var apron := f2w(centers[0], 0.0, -float(envelopes()["half_fence"]) - 2.0)
		var slab2 := maxf(W.surface_y(apron.x, apron.y) + 0.05, pvf - 0.06)
		var cams := {
			"play": cam_play,
			"porch_eye": {"pos": Vector3(door2.x, door2.y + SPEC.HUMAN_EYE_H, door2.z), "basis": Basis.IDENTITY, "fov": 60.0, "clamped": false},
			"gate_eye": {"pos": Vector3(apron.x, slab2 + SPEC.HUMAN_EYE_H, apron.y), "basis": Basis.IDENTITY, "fov": 60.0, "clamped": false},
		}
		var hv: Dictionary = {}
		for vk in ["play", "porch_eye", "gate_eye"]:
			var cam2: Dictionary = cams[vk]
			var arr: Array = []
			var mn := 1.0
			var fu := 0
			for cc in st2["cells"]:
				var v := vis_cell(cam2, centers[0], int(cc["i"]), int(cc["j"]), pvf + 0.20, occ2, 21)
				arr.append({"slot": cc["slot"], "i": cc["i"], "j": cc["j"], "vis_frac": q(float(v["frac"]), 3)})
				mn = minf(mn, float(v["frac"]))
				if float(v["frac"]) >= 0.999:
					fu += 1
			hv[vk] = {"cells": arr, "min_frac": q(mn, 3), "full_visible_cells": fu}
		var blocked2 := 0
		for cc in st2["cells"]:
			var wb := wall_blocked(cam_play, centers[0], Vector3(cc["world"][0], pvf + 0.20, cc["world"][1]), pvf)
			if bool(wb["blocked"]):
				blocked2 += 1
		hypo.append({"plateau": pvf, "fence_top": st2["fence_top_y"],
			"vis_play_min": hv["play"]["min_frac"], "vis_play_full": hv["play"]["full_visible_cells"],
			"vis_porch_min": hv["porch_eye"]["min_frac"],
			"vis_porch_full": hv["porch_eye"]["full_visible_cells"],
			"vis_gate_min": hv["gate_eye"]["min_frac"], "vis_gate_full": hv["gate_eye"]["full_visible_cells"],
			"wall_blocked": blocked2, "cells_vis_play": hv["play"]["cells"],
			"bed_top": q(pvf + 0.20, 3), "cut_needed": q(float(st2["env_terrain_max"]) - pvf, 3)})
	_res["plateau_hypotheses"] = hypo
	# ---------------- 4b) 候选台适配（--cands） ----------------
	if cands_mode:
		var cb := cand_block(stations)
		_res["candidates"] = cb
		for o in cb:
			if not o.has("name"):
				continue
			_p("CAND %s" % String(o["name"]), "terrace=%s pad_margin=%s cut=%s fill=%s" % [
				str(o["terrace_y"]), str(o["pad_fit"]["min_margin"]),
				str(o["terrain_cut_needed"]), str(o["terrain_fill_needed"])])
			_p("  vis", "play min=%s full=%s | movie min=%s full=%s | porch min=%s | gate min=%s | wall_blocked=%s" % [
				str(o["vis"]["play_min"]), str(o["vis"]["play_full"]), str(o["vis"]["movie_min"]),
				str(o["vis"]["movie_full"]), str(o["vis"]["porch_min"]), str(o["vis"]["gate_min"]),
				str(o["vis"]["wall_blocked"])])
			_p("  walk", "min_edge=%s min_centre=%s max_edge=%s max_centre=%s" % [
				str(o["walk_min_to_edge"]), str(o["walk_min_to_centre"]),
				str(o["walk_max_to_edge"]), str(o["walk_max_to_centre"])])
			_p("  path", "min_clear=%s gate_to_road=%s" % [str(o["path"]["min_clear"]), str(o["gate_path"]["to_road_edge"])])
			_p("  cells_px", str(o["cells"].map(func(x): return x["screen_px_play"])))
			_p("  pad_worst", str(o["pad_fit"]["worst"]))
			_p("  lamps", str(o["lamps"].map(func(l): return [l["name"], l["fence_ring_clear"], l["inside_pad"], l["pad_margin"]])))
		print("B_CAND " + JSON.stringify(cb))
	# ---------------- 5) 比例 ----------------
	var env := envelopes()
	var half_podium: float = env["half_podium"]
	var zeta: float = (4.0 - PI) * 0.52 * 0.52
	var podium_area: float = (2.0 * half_podium) * (2.0 * half_podium) - zeta
	var soil_top_area: float = 9.0 * pow(2.0 * SOIL_HALF, 2.0)
	var soil_rim_area: float = 9.0 * pow(2.0 * RIM_HALF, 2.0)
	var fence_fp: float = pow(2.0 * float(env["half_fence"]), 2.0)
	var plot_area: float = pow(2.0 * float(env["half_plot"]), 2.0)
	_res["proportions"] = {
		"podium_area": q(podium_area, 2), "fence_footprint": q(fence_fp, 2), "plot_area": q(plot_area, 2),
		"soil_top_area": q(soil_top_area, 2), "soil_rim_area": q(soil_rim_area, 2),
		"ratio_soil_top_podium": q(soil_top_area / podium_area, 4),
		"ratio_soil_rim_podium": q(soil_rim_area / podium_area, 4),
		"ratio_soil_top_fence": q(soil_top_area / fence_fp, 4),
		"ratio_soil_rim_fence": q(soil_rim_area / fence_fp, 4),
		"post_d_design": q(2.0 * POST_R, 3), "rail_d_design": q(2.0 * RAIL_R, 3),
		"post_h_design": POST_H,
		"post_h_over_podium_w": q(POST_H / (2.0 * half_podium), 4),
		"post_d_over_podium_w": q(2.0 * POST_R / (2.0 * half_podium), 4),
		"fence_h_over_fence_w": q(POST_H / (2.0 * float(env["half_fence"])), 4),
		"human_shoulder_w": q(SPEC.HUMAN_SHOULDER_W, 3), "human_body_depth": q(SPEC.HUMAN_BODY_DEPTH, 3),
		"human_height": q(SPEC.HUMAN_HEIGHT, 3), "human_eye_h": q(SPEC.HUMAN_EYE_H, 3),
		"human_step_h": q(SPEC.HUMAN_STEP_H, 3),
		"gap_net_rim_vs_shoulder": q(((CELL + GAP) - 2.0 * RIM_HALF) / SPEC.HUMAN_SHOULDER_W, 3),
		"walkway_clear_vs_shoulder": q((((float(env["half_fence"]) - POST_R) - float(env["half_cells_rim"]))) / SPEC.HUMAN_SHOULDER_W, 3),
	}
	_p("proportions", _res["proportions"])
	print("B_JSON " + JSON.stringify(_res))
	quit(0)
