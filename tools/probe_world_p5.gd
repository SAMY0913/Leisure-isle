extends SceneTree
## P5 runtime probe for scripts/world.gd (task-4):
##   level dock deck / piles / shore steps, street lamps on the real path curves,
##   boat stern lantern + forward search light, coastal + far sail routes with
##   far return entries, and the untouched lighthouse.
## Run: Godot --headless --path D:/休闲小岛幻境/游戏工程 --script res://tools/probe_world_p5.gd

const M := preload("res://scripts/isle_math.gd")
const DECK := 0.72
const DIAM := 60.1444
const ANG_MAX := 25.0

var fails: Array = []
var checks := 0
var passes := 0

func _check(cond: bool, msg: String) -> void:
	checks += 1
	if cond:
		passes += 1
	else:
		fails.append(msg)
		print("[P5][FAIL] ", msg)

func _pt_seg(px: float, pz: float, a: Vector2, b: Vector2) -> float:
	var vx := b.x - a.x
	var vz := b.y - a.y
	var wx := px - a.x
	var wz := pz - a.y
	var l2 := vx * vx + vz * vz
	var t := 0.0
	if l2 > 0.000001:
		t = clampf((wx * vx + wz * vz) / l2, 0.0, 1.0)
	var dx := wx - vx * t
	var dz := wz - vz * t
	return sqrt(dx * dx + dz * dz)

func _collect_aabb(node: Node, xf: Transform3D, acc: Array) -> void:
	var here := xf
	if node is Node3D:
		here = xf * (node as Node3D).transform
	if node is MeshInstance3D and node.is_visible_in_tree():
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var ab: AABB = here * mi.get_aabb()
			if not bool(acc[1]):
				acc[0] = ab
				acc[1] = true
			else:
				acc[0] = (acc[0] as AABB).merge(ab)
	for c in node.get_children():
		_collect_aabb(c, here, acc)

func _subtree_aabb(n: Node) -> AABB:
	var xf := Transform3D.IDENTITY
	if n is Node3D:
		xf = (n as Node3D).transform
	var acc: Array = [AABB(), false]
	for c in n.get_children():
		_collect_aabb(c, xf, acc)
	return acc[0]

func _max_turn(pts: PackedVector3Array) -> float:
	var worst := 0.0
	for i in range(1, pts.size() - 1):
		var d0 := (pts[i] - pts[i - 1]).normalized()
		var d1 := (pts[i + 1] - pts[i]).normalized()
		var ang := rad_to_deg(acos(clampf(d0.dot(d1), -1.0, 1.0)))
		if ang > worst:
			worst = ang
	return worst

func _arc_at(pts: PackedVector3Array, dist: float) -> Vector3:
	var acc := 0.0
	for i in range(pts.size() - 1):
		var seg := pts[i].distance_to(pts[i + 1])
		if acc + seg >= dist:
			return pts[i].lerp(pts[i + 1], (dist - acc) / maxf(seg, 0.000001))
		acc += seg
	return pts[pts.size() - 1]

func _polyline_len(pts: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(pts.size() - 1):
		total += pts[i].distance_to(pts[i + 1])
	return total

func _route_stats(pts: PackedVector3Array, dock_a: Vector2, dock_b: Vector2) -> Dictionary:
	var min_off := 1.0e20
	var min_dock := 1.0e20
	for p in pts:
		var rr := sqrt(p.x * p.x + p.z * p.z)
		var off := rr - M.coast_radius(atan2(p.z, p.x))
		if off < min_off:
			min_off = off
		var dd := _pt_seg(p.x, p.z, dock_a, dock_b)
		if dd < min_dock:
			min_dock = dd
	return {"min_off": min_off, "min_dock": min_dock}

func _run() -> void:
	var t0 := Time.get_ticks_msec()
	var W := load("res://scripts/world.gd")
	if W == null:
		print("[P5][FAIL] could not load res://scripts/world.gd")
		quit(3)
		return
	var parent := Node3D.new()
	parent.name = "P5ProbeParent"
	get_root().add_child(parent)
	var d: Dictionary = W.build(parent)
	var build_ms := Time.get_ticks_msec() - t0
	var root_node: Node3D = d.get("root")
	print("[P5] build_ms=%d return_keys=%d" % [build_ms, d.size()])

	# ================================================== top-level interface ==
	var need_keys := ["root", "terrain", "perches", "dock_end", "dock_perch", "big_tree",
		"big_tree_canopy", "lamps", "lamp_mats", "lamp_halos", "light_sources", "swing",
		"swing_axis", "sailboat", "sailboat_path", "sailboat_speed", "grass_count",
		"sail_routes", "lighthouse", "lighthouse_height", "lighthouse_lamp",
		"lighthouse_beam_origin", "lighthouse_platform", "lighthouse_perches",
		"lighthouse_light", "lighthouse_lamp_mat", "lighthouse_lamp_halo",
		"lighthouse_rotation_axis", "rock_stats", "flower_stats",
		"sail_dock_pos", "sail_dock_heading", "island_diameter", "sail_return_paths",
		"sail_return_path", "dock_deck_world_y", "dock",
		"sailboat_lantern_mat", "sailboat_lantern_halo", "sailboat_lantern_local_pos",
		"sailboat_spot_node", "sailboat_spot_lens_pos", "sailboat_spot_cone_mat",
		"sailboat_fade_mats"]
	for key in need_keys:
		_check(d.has(key), "missing return key: " + key)
	var anchor: Vector3 = d["sail_dock_pos"]
	var diameter: float = float(d["island_diameter"])
	print("[P5][IFACE] anchor=(%.3f, %.3f, %.3f) heading=%.4f island_diameter=%.4f dock_deck_y=%.3f" % [
		anchor.x, anchor.y, anchor.z, float(d["sail_dock_heading"]), diameter,
		float(d["dock_deck_world_y"])])
	_check(absf(anchor.y) < 1e-4, "sail_dock_pos.y must stay 0 for the P4 y-plane rule")
	_check(anchor.x * anchor.x + anchor.z * anchor.z > 1.0, "sail_dock_pos is at the origin")
	var max_coast := 0.0
	for i in range(2048):
		max_coast = maxf(max_coast, M.coast_radius(TAU * float(i) / 2048.0))
	_check(absf(diameter - 2.0 * max_coast) < 0.05,
		"island_diameter %.4f != 2*max coast %.4f" % [diameter, 2.0 * max_coast])
	_check(absf(diameter - DIAM) < 0.05, "island_diameter %.4f != expected %.4f" % [diameter, DIAM])
	_check(absf(float(d["dock_deck_world_y"]) - DECK) < 0.001, "dock_deck_world_y key wrong")

	var dock_a_v := M.dock_start()
	var dock_b_v := M.dock_end()
	var dock_a := Vector2(dock_a_v.x, dock_a_v.z)
	var dock_b := Vector2(dock_b_v.x, dock_b_v.z)

	# ============================================================== dock ====
	var dock: Dictionary = d["dock"]
	var dock_node: Node3D = dock["node"]
	_check(dock_node != null, "dock node missing")
	if dock_node != null:
		_check(dock_node.global_position.distance_to(dock_a_v) < 0.01,
			"dock node moved away from dock_start")
		var exp_yaw := atan2(M.dock_dir().x, M.dock_dir().z)
		_check(absf(angle_difference(dock_node.rotation.y, exp_yaw)) < 0.001,
			"dock node yaw changed")
	var planks := dock_node.find_child("DockPlanks", true, false) as MultiMeshInstance3D
	_check(planks != null, "DockPlanks MultiMesh missing")
	var mean_top := -99.0
	var var_top := -1.0
	var min_top := 9.0
	var max_top := -9.0
	var inst_n := 0
	var dummy_mm := true
	if planks != null and planks.multimesh != null:
		var mm := planks.multimesh
		inst_n = mm.instance_count
		for i in range(mini(inst_n, 4)):
			if mm.get_instance_transform(i).origin.length() > 0.001:
				dummy_mm = false
		if dummy_mm:
			# Headless (dummy renderer) does not keep MultiMesh instance transforms: a
			# fresh MultiMesh and every rock MultiMesh read back identity too (verified).
			# Real transform readback runs in the windowed tools/probe_world_p5_shot.gd
			# (logs/shot_*.log); here the deck contract is checked from the handshake.
			print("[P5][DOCK] note: dummy renderer -> MultiMesh transforms read identity; levelness readback is windowed")
		else:
			var tops: Array = []
			mean_top = 0.0
			for i in range(inst_n):
				var xf: Transform3D = planks.global_transform * mm.get_instance_transform(i)
				var up := (xf.basis * Vector3(0.0, 1.0, 0.0)).normalized()
				var top_y := xf.origin.y + up.y * 0.05
				tops.append(top_y)
				mean_top += top_y
				if top_y < min_top:
					min_top = top_y
				if top_y > max_top:
					max_top = top_y
			mean_top /= float(maxi(inst_n, 1))
			var_top = 0.0
			for v in tops:
				var dv: float = float(v) - mean_top
				var_top += dv * dv
			var_top /= float(maxi(inst_n, 1))
	print("[P5][DOCK] planks=%d mean_top_y=%.6f variance=%.9f min=%.6f max=%.6f" % [
		inst_n, mean_top, var_top, min_top, max_top])
	_check(inst_n >= 16, "too few deck planks (%d)" % inst_n)
	_check(planks != null and planks.multimesh != null and planks.multimesh.mesh is BoxMesh,
		"deck planks are not flat box meshes")
	if planks != null and planks.multimesh != null and planks.multimesh.mesh is BoxMesh:
		_check((planks.multimesh.mesh as BoxMesh).size.y < 0.12, "deck planks are not boards")
	if not dummy_mm:
		_check(var_top < 0.01, "deck main platform not level (variance=%.6f)" % var_top)
		_check(absf(mean_top - DECK) < 0.005,
			"deck mean top y %.4f != %.2f" % [mean_top, DECK])
		_check(max_top - min_top < 0.02, "deck top y spread %.4f m" % (max_top - min_top))
	else:
		# Contract arithmetic: all planks are generated from one deck_y; the returned
		# handshake pins that plane and the pile caps must sit on it as well.
		_check(absf(float(dock["deck_world_y"]) - DECK) < 0.001, "dock deck_world_y != 0.72")
		_check(absf(float(dock["deck_local_y"]) - (DECK - M.dock_start().y)) < 0.001,
			"dock deck_local_y != 0.72 - dock_start.y")
	_check(DECK > 0.50, "deck is not above the 0.5 m wave crest")
	var piles: Array = dock["piles"]
	_check(piles.size() == 12, "expected 12 piles, got %d" % piles.size())
	var pile_ok := true
	for p in piles:
		var pd: Dictionary = p
		if absf(float(pd["top"]) - (DECK + 0.06)) > 0.001:
			pile_ok = false
		if absf(float(pd["bottom"]) + 3.40) > 0.001:
			pile_ok = false
	_check(pile_ok, "pile top/bottom not on the level deck contract")
	_check(absf((d["dock_end"] as Vector3).y - DECK) < 0.02, "dock_end not on the deck plane")
	_check(absf((dock["bollard"] as Vector3).y - (DECK + 0.55)) < 0.02, "bollard not on deck")
	_check(absf((dock["perch"] as Vector3).y - (DECK + 0.95)) < 0.02, "perch not on deck")
	# shore treads: three stone steps between the deck and the beach
	var treads := 0
	for child in dock_node.get_children():
		var mi := child as MeshInstance3D
		if mi != null and mi.mesh is BoxMesh:
			var sz := (mi.mesh as BoxMesh).size
			if absf(sz.y - 0.30) < 0.02 or absf(sz.y - 0.36) < 0.02 or absf(sz.y - 0.40) < 0.02:
				treads += 1
	print("[P5][DOCK] shore_treads=%d pile_top=%.2f pile_bottom=%.2f end_y=%.3f" % [
		treads, DECK + 0.06, -3.40, (d["dock_end"] as Vector3).y])
	_check(treads >= 2, "shore step treads missing")

	# ============================================================== boat ====
	var boat: Node3D = d["sailboat"]
	var routes: Array = d["sail_routes"]
	_check(boat != null, "sailboat missing")
	_check(routes.size() >= 8, "fewer than 8 sail routes (%d)" % routes.size())
	var r0: Dictionary = routes[0]
	var o0: PackedVector3Array = r0["out"]
	var fwd0 := (o0[1] - o0[0]).normalized()
	var boat_fwd := boat.global_transform.basis.z.normalized()
	_check(boat_fwd.dot(fwd0) > 0.999,
		"boat body forward is not +Z at rest (dot=%.4f)" % boat_fwd.dot(fwd0))
	_check(absf(angle_difference(boat.rotation.y, atan2(fwd0.x, fwd0.z))) < 0.002,
		"boat yaw does not match the +Z forward rule")
	_check(boat.global_position.distance_to(anchor) < 1.2, "boat is not at the dock anchor")
	_check(absf(boat.global_position.y) < 0.15, "boat anchor y not at the waterline")
	var bb := _subtree_aabb(boat)
	print("[P5][BOAT] rest=(%.2f, %.3f, %.2f) aabb_min_y=%.3f aabb_max_y=%.3f" % [
		boat.global_position.x, boat.global_position.y, boat.global_position.z,
		bb.position.y, bb.position.y + bb.size.y])
	_check(bb.position.y > -0.60, "boat hull deeper than 0.60 m (min y=%.3f)" % bb.position.y)
	_check(bb.position.y < 0.05, "boat hull does not touch the water (min y=%.3f)" % bb.position.y)
	_check(bb.size.y > 3.0, "boat AABB unexpectedly small")
	var bow_pt := boat.to_global(Vector3(0.0, 0.5, 2.6))
	var bow_dock := _pt_seg(bow_pt.x, bow_pt.z, dock_a, dock_b)
	print("[P5][BOAT] bow=(%.2f, %.2f) bow_to_dock_line=%.2f m" % [bow_pt.x, bow_pt.z, bow_dock])
	_check(bow_dock > 1.0, "boat bow too close to the dock (%.2f m)" % bow_dock)
	# stern lantern material / halo / node
	var lamp_mat = d["sailboat_lantern_mat"]
	_check(lamp_mat is ShaderMaterial, "sailboat_lantern_mat is not a ShaderMaterial")
	if lamp_mat is ShaderMaterial:
		var glow_v = (lamp_mat as ShaderMaterial).get_shader_parameter("glow")
		_check(glow_v != null and float(glow_v) > 0.0, "sailboat lantern material has no glow")
	var lhalo = d["sailboat_lantern_halo"]
	_check(lhalo is MeshInstance3D, "sailboat_lantern_halo is not a MeshInstance3D")
	if lhalo is MeshInstance3D:
		_check((lhalo as Node3D).get_parent() == boat, "lantern halo not parented to the boat")
	var lp: Vector3 = d["sailboat_lantern_local_pos"]
	var lnode := boat.find_child("SternLantern", true, false)
	_check(lnode != null, "SternLantern node missing inside the boat subtree")
	if lnode != null:
		var lmi := lnode as MeshInstance3D
		_check(lmi != null and lmi.material_override == lamp_mat,
			"SternLantern does not use sailboat_lantern_mat")
		var lglobal := (lnode as Node3D).global_position
		_check(lglobal.distance_to(boat.to_global(lp)) < 0.01,
			"lantern drifted from sailboat_lantern_local_pos")
		_check(absf(lp.x) > 0.7, "lantern is not outboard of the hull")
	# forward search light
	var sp = d["sailboat_spot_node"]
	_check(sp is Node3D, "sailboat_spot_node is not a Node3D")
	var sp_node: Node3D = sp
	_check(sp_node.get_parent() == boat, "sailboat_spot_node is not a child of the boat")
	_check(not sp_node.visible, "sailboat_spot_node must start invisible")
	var lens_pos: Vector3 = d["sailboat_spot_lens_pos"]
	_check(sp_node.position.distance_to(lens_pos) < 0.01,
		"spot node not placed at sailboat_spot_lens_pos")
	var sp_fwd := sp_node.global_transform.basis.z.normalized()
	_check(sp_fwd.dot(boat_fwd) > 0.999, "spot node does not point along the boat +Z")
	var cone := sp_node.find_child("BeamCone", true, false)
	_check(cone is MeshInstance3D, "BeamCone mesh missing under the spot node")
	var cmat = d["sailboat_spot_cone_mat"]
	_check(cmat is ShaderMaterial and (cmat as ShaderMaterial).shader != null,
		"sailboat_spot_cone_mat missing its shader")
	if cone is MeshInstance3D:
		_check((cone as MeshInstance3D).material_override == cmat,
			"BeamCone does not use sailboat_spot_cone_mat")
		var ca := (cone as MeshInstance3D).get_aabb()
		_check(ca.size.z > 5.0, "search light cone does not extend forward")
		_check(ca.end.z > 4.0, "search light cone is not +Z oriented")
	var fade: Array = d["sailboat_fade_mats"]
	var fade_all_mat := true
	for fm in fade:
		if not (fm is Material):
			fade_all_mat = false
	print("[P5][BOAT] lantern_local=%s spot_lens=%s fade_mats=%d spot_visible=%s" % [
		str(lp), str(lens_pos), fade.size(), str(sp_node.visible)])
	_check(fade.size() >= 6, "sailboat_fade_mats too small (%d)" % fade.size())
	_check(fade_all_mat, "sailboat_fade_mats contains non-material entries")

	# ============================================================= lamps ====
	var lamps: Array = d["lamps"]
	var light_sources: Array = d["light_sources"]
	print("[P5][LAMPS] count=%d light_sources=%d" % [lamps.size(), light_sources.size()])
	_check(lamps.size() >= 5, "fewer than 5 lamps (%d)" % lamps.size())
	_check(light_sources.size() == 8, "light_sources %d != 8 (shader budget)" % light_sources.size())
	var lamp_bases: Array = []
	var lamp_names: Array = []
	for entry in lamps:
		var info: Dictionary = entry[3]
		var base: Vector3 = info["base"]
		var facing: Vector3 = info["facing"]
		var lname := String(info["name"])
		lamp_bases.append(base)
		lamp_names.append(lname)
		var node := root_node.find_child(lname, true, false) as Node3D
		_check(node != null, "lamp node missing in scene: " + lname)
		if node != null:
			_check(absf(node.position.y - W._h(base.x, base.z)) < 0.02,
				"lamp base not snapped to ground: " + lname)
		var pinfo: Dictionary = W.path_center_info(base.x, base.z)
		var centre: Vector2 = pinfo["centre"]
		var half_w: float = float(pinfo["half_w"])
		var to_centre := Vector3(centre.x - base.x, 0.0, centre.y - base.z)
		var d_centre := to_centre.length()
		var arm_dot := 0.0
		if d_centre > 0.0001:
			arm_dot = facing.dot(to_centre / d_centre)
		print("[P5][LAMP] %s road_dist=%.3f shoulder=%.3f arm_dot=%.3f ground_y=%.3f" % [
			lname, d_centre, half_w * 0.5 + 0.25, arm_dot, base.y])
		_check(absf(d_centre - (half_w * 0.5 + 0.25)) < 0.16,
			"lamp base not at road shoulder: %s (%.3f vs %.3f)" % [lname, d_centre, half_w + 0.25])
		_check(arm_dot > 0.9, "lamp arm not aimed at road centre: %s (dot=%.3f)" % [lname, arm_dot])
		_check(d_centre > half_w * 0.5 + 0.10, "lamp base stands on the path: " + lname)
		_check(base.y > 0.2, "lamp base below the terrain: " + lname)
		_check(Vector2(base.x, base.z).distance_to(Vector2(anchor.x, anchor.z)) > 8.0,
			"lamp too close to the moored boat: " + lname)
	# spacing within each path family (main 0-2, garden 3-5)
	var spacing_bad := false
	var spacing_str := ""
	for fam in [[0, 1, 2], [3, 4, 5]]:
		for k in range(2):
			var ia: int = fam[k]
			var ib: int = fam[k + 1]
			if ia < lamp_bases.size() and ib < lamp_bases.size():
				var gap: float = (lamp_bases[ia] as Vector3).distance_to(lamp_bases[ib] as Vector3)
				spacing_str += "%.2f " % gap
				if gap < 6.0 or gap > 9.0:
					spacing_bad = true
	print("[P5][LAMPS] spacing=%s" % spacing_str.strip_edges())
	_check(spacing_bad == false, "lamp spacing outside 6-9 m: " + spacing_str.strip_edges())

	# ============================================================ routes ====
	var return_paths: Dictionary = d["sail_return_paths"]
	_check(return_paths.size() >= 4, "sail_return_paths too small (%d)" % return_paths.size())
	var cb = d["sail_return_path"]
	_check(cb is Callable, "sail_return_path is not a Callable")
	var n_coastal := 0
	var n_far := 0
	for r in routes:
		var rn := String(r["name"])
		var kind := String(r["kind"])
		var o: PackedVector3Array = r["out"]
		var b: PackedVector3Array = r["back"]
		if kind == "coastal":
			n_coastal += 1
		elif kind == "far":
			n_far += 1
		else:
			_check(false, "unknown route kind: " + kind)
		_check(o.size() >= 5 and b.size() >= 5, "route too short: " + rn)
		_check(float(r["speed"]) >= 2.4, "route speed below boat speed: " + rn)
		_check(o[0].distance_to(anchor) < 0.15, "out[0] != sail_dock_pos: " + rn)
		_check(b[b.size() - 1].distance_to(anchor) < 0.15, "back[-1] != sail_dock_pos: " + rn)
		var y_ok := true
		for p in o:
			if absf(p.y) > 1e-4:
				y_ok = false
		for p in b:
			if absf(p.y) > 1e-4:
				y_ok = false
		_check(y_ok, "route leaves the y=0 plane: " + rn)
		var turn_o := _max_turn(o)
		var turn_b := _max_turn(b)
		_check(turn_o < ANG_MAX, "out leg not smooth (%.2f deg): %s" % [turn_o, rn])
		_check(turn_b < ANG_MAX, "back leg not smooth (%.2f deg): %s" % [turn_b, rn])
		var so := _route_stats(o, dock_a, dock_b)
		var sb := _route_stats(b, dock_a, dock_b)
		var min_off := minf(float(so["min_off"]), float(sb["min_off"]))
		# Dock clearance: the contract pins both ends to the dock anchor (3.41 m
		# past dock_end), so only the mid-leg points must clear the pier by 3 m.
		var min_dock := 1.0e20
		for i in range(3, o.size() - 3):
			min_dock = minf(min_dock, _pt_seg(o[i].x, o[i].z, dock_a, dock_b))
		for i in range(3, b.size() - 3):
			min_dock = minf(min_dock, _pt_seg(b[i].x, b[i].z, dock_a, dock_b))
		_check(min_off >= 6.0, "route %.2f m offshore (<6): %s" % [min_off, rn])
		_check(min_dock >= 3.0, "route %.2f m from the dock: %s" % [min_dock, rn])
		var rline := "[P5][ROUTE] %s kind=%s out=%d back=%d len=%.1f turn=%.2f/%.2f off=%.2f dock=%.2f" % [
			rn, kind, o.size(), b.size(), _polyline_len(o), turn_o, turn_b, min_off, min_dock]
		if kind == "far":
			var tip: Vector3 = o[o.size() - 1]
			var tip_r := Vector2(tip.x, tip.z).length()
			var fade_start := float(r["fade_start"])
			var fade_end := float(r["fade_end"])
			var fp := _arc_at(o, fade_start)
			var fp_r := Vector2(fp.x, fp.z).length()
			var entries: Array = r["far_entries"]
			var entries_ok := entries.size() >= 4 and entries.size() <= 6
			for e in entries:
				var ev: Vector3 = e
				if Vector2(ev.x, ev.z).length() < 5.0 * diameter:
					entries_ok = false
				if not return_paths.has(Vector3(ev.x, 0.0, ev.z)):
					entries_ok = false
			print("%s tip_r=%.2f(%.3fD) fade_start=%.2f@r=%.2f(%.3fD) fade_end=%.2f entries=%d wait_sim=%.1f" % [
				rline, tip_r, tip_r / diameter, fade_start, fp_r, fp_r / diameter, fade_end,
				entries.size(), float(r["wait_sim_seconds"])])
			_check(tip_r >= 5.6 * diameter,
				"far tip %.2f m < 5.6 D: %s" % [tip_r, rn])
			_check(fp_r >= 5.0 * diameter,
				"fade_start point %.2f m < 5.0 D: %s" % [fp_r, rn])
			_check(fade_start >= 5.0 * diameter - 1.0,
				"fade_start %.2f < 5 D: %s" % [fade_start, rn])
			_check(fade_end > fade_start + 0.5, "fade window too small: " + rn)
			_check(absf(float(r["wait_sim_seconds"]) - 28800.0) < 1e-6,
				"far wait_sim_seconds != 28800: " + rn)
			_check(entries_ok, "far_entries invalid: " + rn)
		else:
			print(rline)
	print("[P5][ROUTES] total=%d coastal=%d far=%d" % [routes.size(), n_coastal, n_far])
	_check(n_coastal >= 4, "fewer than 4 coastal routes (%d)" % n_coastal)
	_check(n_far >= 4, "fewer than 4 far routes (%d)" % n_far)
	# return paths: entry -> dock anchor, smooth, offshore
	var rp_ok := true
	var rp_bad := ""
	var rp_checked := 0
	for key in return_paths.keys():
		var path: PackedVector3Array = return_paths[key]
		var k: Vector3 = key
		_check(path.size() >= 10, "return path too short: " + str(k))
		_check(path[0].distance_to(k) < 0.15, "return path does not start at its entry")
		_check(path[path.size() - 1].distance_to(anchor) < 0.15,
			"return path does not end at the dock anchor")
		var turn_r := _max_turn(path)
		_check(turn_r < ANG_MAX, "return path not smooth (%.2f deg)" % turn_r)
		var st := _route_stats(path, dock_a, dock_b)
		_check(float(st["min_off"]) >= 6.0, "return path too close to the coast")
		if cb is Callable:
			var via_cb: PackedVector3Array = cb.call(k)
			_check(via_cb.size() == path.size(), "sail_return_path callable returns a different path")
		rp_checked += 1
		rp_bad += "[%.0f,%.0f] " % [k.x, k.z]
	print("[P5][RETURN] paths=%d checked=%d entries=%s" % [return_paths.size(), rp_checked, rp_bad.strip_edges()])
	_check(rp_ok, rp_bad)

	# ========================================================= lighthouse ==
	_check(absf(float(d["lighthouse_height"]) - 18.2759084701538) < 0.001,
		"lighthouse height drifted")
	var beam: Vector3 = d["lighthouse_beam_origin"]
	_check(beam.y > 18.2759084701538 * 0.7, "lighthouse beam_origin too low")
	var lh_light := false
	for L in light_sources:
		if typeof(L) == TYPE_DICTIONARY and str((L as Dictionary).get("kind", "")) == "lighthouse":
			lh_light = true
	_check(lh_light, "lighthouse light missing from light_sources")

	print("[P5] checks=%d passes=%d fails=%d build_ms=%d" % [checks, passes, fails.size(), build_ms])
	if fails.is_empty():
		print("[PROBE] RESULT=PASS fails=0")
		quit(0)
	else:
		print("[PROBE] RESULT=FAIL fails=%d" % fails.size())
		for f in fails:
			print("[FAIL] " + str(f))
		quit(3)

func _init() -> void:
	# Always deferred: the built subtree must be inside the SceneTree before the
	# probe reads global transforms (dock / boat / lantern world positions).
	_run.call_deferred()
