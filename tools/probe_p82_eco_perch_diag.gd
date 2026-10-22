extends SceneTree
## P8.2-04 诊断：perch4 沿支撑枝候选位置（世界坐标）。
const World := preload("res://scripts/world.gd")
var _cyls: Array = []
var _winter: Array = []
var _base := Vector3.ZERO

func _initialize() -> void:
	print("=== P8.2-04 PERCH4 CAND START ===")
	await process_frame
	var holder := Node3D.new()
	get_root().add_child(holder)
	var isl := World.build(holder, true)
	_base = isl["big_tree"] as Vector3
	var big := (isl["root"] as Node3D).find_child("BigTree", true, false) as Node3D
	_collect(big)
	for p in (isl["perches"] as Array):
		var pd: Dictionary = p
		if String(pd.get("kind", "")) == "winter_branch":
			_winter.append(pd)
	_winter.sort_custom(func(x, y): return String(x["id"]) < String(y["id"]))
	_focus(4, 3)
	_focus(4, 2)
	holder.free()
	print("=== P8.2-04 PERCH4 CAND END ===")
	quit(0)

func _fmtv(v: Vector3) -> String:
	return "(%.4f, %.4f, %.4f)" % [v.x, v.y, v.z]

func _collect(node: Node) -> void:
	for c in node.get_children():
		var mi := c as MeshInstance3D
		if mi != null and mi.mesh is CylinderMesh:
			var cm := mi.mesh as CylinderMesh
			var xf := mi.global_transform
			_cyls.append({"name": String(mi.name), "xf": xf, "axis": xf.basis.y.normalized(),
				"r0": cm.bottom_radius, "r1": cm.top_radius, "h": cm.height, "mid": xf.origin})
		_collect(c)

func _eval(i: int, wp: Vector3) -> Dictionary:
	var c: Dictionary = _cyls[i]
	var lv: Vector3 = (c["xf"] as Transform3D).affine_inverse() * wp
	var h: float = float(c["h"])
	var y := clampf(lv.y, -h * 0.5, h * 0.5)
	var t := (y + h * 0.5) / h
	var r: float = lerpf(float(c["r0"]), float(c["r1"]), t)
	var horiz := Vector2(lv.x, lv.z).length()
	return {"t": t, "r": r, "horiz": horiz, "surf": horiz - r, "within": absf(lv.y) <= h * 0.5 + 0.03}

func _support(sp: Vector3) -> int:
	var bi := -1
	var ba := 1e9
	for i in range(_cyls.size()):
		var e := _eval(i, sp)
		if bool(e["within"]) and absf(float(e["surf"])) < ba:
			ba = absf(float(e["surf"]))
			bi = i
	return bi

func _focus(idx: int, other_idx: int) -> void:
	var sp: Vector3 = _winter[idx]["pos"]
	var si := _support(sp)
	var sc: Dictionary = _cyls[si]
	var axis: Vector3 = sc["axis"]
	var mid: Vector3 = sc["mid"]
	var h: float = float(sc["h"])
	var upr := (Vector3.UP - axis * Vector3.UP.dot(axis)).normalized()
	var e_cur := _eval(si, sp)
	print("[FOCUS-%d] support=%s axis=%s len=%.3f r0=%.3f r1=%.3f t_cur=%.4f upr=%s slope=%.2fdeg" % [
		idx, String(sc["name"]), _fmtv(axis), h, float(sc["r0"]), float(sc["r1"]), float(e_cur["t"]), _fmtv(upr), rad_to_deg(acos(clampf(upr.y, -1.0, 1.0)))])
	print("   cur world=%s local=%s" % [_fmtv(sp), _fmtv(sp - _base)])
	var rows: Array = []
	for j in range(201):
		var t := float(j) / 200.0
		if t < 0.12 or t > 0.92:
			continue
		var r: float = lerpf(float(sc["r0"]), float(sc["r1"]), t)
		var cand := mid + axis * ((t - 0.5) * h) + upr * r
		var min_clear := 1e9
		for kk in [0.04, 0.06, 0.08, 0.10, 0.12, 0.14, 0.16, 0.20, 0.24, 0.28]:
			var q := cand + upr * float(kk)
			for j2 in range(_cyls.size()):
				if j2 == si:
					continue
				var e := _eval(j2, q)
				if bool(e["within"]) and float(e["surf"]) < min_clear:
					min_clear = float(e["surf"])
		var dt := absf(t - float(e_cur["t"]))
		rows.append({"t": t, "p": cand, "r": r, "min_clear": min_clear, "dt": dt})
	rows.sort_custom(func(x, y): return float(x["dt"]) < float(y["dt"]))
	var shown := 0
	for rr in rows:
		if float(rr["min_clear"]) >= 0.05 and float(rr["dt"]) >= 0.01:
			var pp: Vector3 = rr["p"]
			var d_other := (pp - (_winter[other_idx]["pos"] as Vector3)).length()
			print("   t=%.3f dt=%.3f world=%s local=%s r=%.3f min_clear=%+.4f dist_other=%.3f" % [
				float(rr["t"]), float(rr["dt"]), _fmtv(pp), _fmtv(pp - _base), float(rr["r"]), float(rr["min_clear"]), d_other])
			shown += 1
			if shown >= 6:
				break
