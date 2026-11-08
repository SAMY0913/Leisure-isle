extends SceneTree
## P7-V3 task E probe: sailing boat model deepening.
## headless: structural assertions on a standalone IsleWorld._sailboat() build plus
##           integration assertions against the real isle.tscn / main.gd wiring.
## window:   P7V3_BOAT_SHOTS=1 -> noon cruise / close side / close oblique / deck top /
##           night stern lantern / night bow spotlight screenshots into 开发产物/p7v3/shots/.

const MainScene := preload("res://isle.tscn")
const SHOTS_DIR := "D:/休闲小岛幻境/开发产物/p7v3/shots/"

var _pass := 0
var _fail := 0
var _shot_ok := 0
var _shot_fail := 0

func _initialize() -> void:
	print("=== P7-V3 BOAT PROBE START ===")
	await process_frame
	if OS.get_environment("P7V3_BOAT_SHOTS") == "1":
		await _run_shots()
		print("=== P7-V3 BOAT SHOTS RESULT: %s ok=%d fail=%d ===" % [
			"PASS" if _shot_fail == 0 else "FAIL", _shot_ok, _shot_fail])
	else:
		await _check_standalone()
		await _check_main_scene()
		print("=== P7-V3 BOAT PROBE RESULT: %s pass=%d fail=%d ===" % [
			"PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit(0 if _fail == 0 and _shot_fail == 0 else 1)

# ============================================================
# assertions / helpers
# ============================================================
func _ok(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("[FAIL] ", msg)

func _shot_check(cond: bool, msg: String) -> void:
	if cond:
		_shot_ok += 1
	else:
		_shot_fail += 1
		print("[SHOT-FAIL] ", msg)

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _descendants_mesh(root: Node, prefix: String) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and String(n.name).begins_with(prefix):
			out.append(n)
		for c in n.get_children():
			stack.push_back(c)
	return out

func _find_mesh(root: Node, node_name: String) -> MeshInstance3D:
	return root.find_child(node_name, true, false) as MeshInstance3D

func _find_node(root: Node, node_name: String) -> Node:
	return root.find_child(node_name, true, false)

func _mat_of(root: Node, node_name: String) -> Material:
	var n := root.find_child(node_name, true, false)
	if n is MeshInstance3D:
		return (n as MeshInstance3D).material_override
	if n != null:
		for c in n.get_children():
			if c is MeshInstance3D:
				return (c as MeshInstance3D).material_override
	return null

func _subtree_aabb(root: Node, include_invisible: bool) -> AABB:
	var out := AABB()
	var started := false
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh != null and (include_invisible or mi.is_visible_in_tree()):
				var b: AABB = mi.global_transform * mi.mesh.get_aabb()
				if started:
					out = out.merge(b)
				else:
					out = b
					started = true
		for c in n.get_children():
			stack.push_back(c)
	return out

# Independent hull-skin half width at height y, derived by walking the actual
# upper hull curve from _hull_pt (bilge to sheer) instead of trusting helpers.
func _probe_hull_wall(stations: Array, z: float, y: float) -> float:
	var sv: Vector4 = IsleWorld._boat_station_at(stations, z)
	if y >= sv.z:
		return 0.0
	var prev_t := 0.0
	var prev_y: float = sv.w
	for i in range(1, 501):
		var t: float = float(i) / 500.0
		var p: Vector3 = IsleWorld._hull_pt(sv, t, 1.0, 1.0, 0.0)
		if p.y >= y:
			var span: float = p.y - prev_y
			var f: float = clampf((y - prev_y) / maxf(span, 0.000001), 0.0, 1.0)
			var x_prev: float = sv.y * pow(prev_t, 0.72)
			return lerpf(x_prev, p.x, f)
		prev_t = t
		prev_y = p.y
	return sv.y

# ============================================================
# 1) standalone: build the boat in isolation from the world generator
# ============================================================
func _check_standalone() -> void:
	print("[part] standalone sailboat build")
	var pivot := Node3D.new()
	pivot.name = "ProbePivot"
	get_root().add_child(pivot)
	var routes: Array = [{
		"out": PackedVector3Array([Vector3.ZERO, Vector3(0.0, 0.0, 1.0)]),
		"back": PackedVector3Array([Vector3(0.0, 0.0, 1.0), Vector3.ZERO]),
		"kind": "probe",
		"name": "probe_route",
	}]
	var info: Dictionary = IsleWorld._sailboat(pivot, routes)
	var loft: Array = IsleWorld._sailboat_loft()
	var stations: Array = loft[0]
	var boat := info.get("node", null) as Node3D
	_ok(boat != null, "standalone: sailboat node built")
	if boat == null:
		return
	_ok(boat.name == "Sailboat", "standalone: root node named Sailboat")
	_ok(boat.get_parent() == pivot, "standalone: boat parented to pivot")
	_ok(boat.get_meta("route_count", -1) == 1, "standalone: route_count meta set")
	_ok(info.get("path", null) is PackedVector3Array and (info["path"] as PackedVector3Array).size() == 2,
		"standalone: returned path is the out route")
	_ok(is_equal_approx(float(info.get("speed", 0.0)), 2.4), "standalone: returned speed 2.4")

	# ---- returned dictionary contract used by main.gd
	for k in ["node", "path", "speed", "lantern_mat", "lantern_halo", "lantern_local_pos",
			"spot_node", "spot_lens_pos", "spot_cone_mat", "fade_mats", "routes"]:
		_ok(info.has(k), "standalone: return dict has key " + k)
	_ok(info.get("routes", null) == routes, "standalone: return dict routes identity")

	# ---- readable hierarchy groups
	for g in ["Hull", "Deck", "Interior", "Fittings", "Cabin", "Rig"]:
		_ok(boat.get_node_or_null(g) != null, "standalone: child group " + g)

	# ---- hull / liner / gunwale
	var hull_aabb := AABB()
	var hull_meshes: Array = []
	for m in (boat.get_node("Hull") as Node).get_children():
		if m is MeshInstance3D and not String(m.name).begins_with("Gunwale"):
			hull_meshes.append(m)
	_ok(hull_meshes.size() == 2, "standalone: hull + liner meshes inside Hull group")
	if hull_meshes.size() == 2:
		hull_aabb = (hull_meshes[0] as MeshInstance3D).mesh.get_aabb()
		_ok(hull_aabb.size.x > 1.3 and hull_aabb.size.x < 1.7,
			"standalone: hull beam %.3f m in [1.3, 1.7]" % hull_aabb.size.x)
	var gunwales := _descendants_mesh(boat, "Gunwale")
	_ok(gunwales.size() == 16, "standalone: 16 gunwale segments (got %d)" % gunwales.size())
	if gunwales.size() > 0:
		var gw_aabb: AABB = (gunwales[0] as MeshInstance3D).mesh.get_aabb()
		_ok(gw_aabb.size.y > 0.07 and gw_aabb.size.y < 0.11,
			"standalone: gunwale timber height %.3f ~ 0.09" % gw_aabb.size.y)
	var inwales := _descendants_mesh(boat, "Inwale")
	_ok(inwales.size() == 6, "standalone: 6 inwale strips, decked ends only (got %d)" % inwales.size())
	if inwales.size() > 0:
		var iw := inwales[0] as MeshInstance3D
		_ok(absf(iw.position.y - 0.51) < 0.01, "standalone: inwale top flush under deck (y=%.3f)" % iw.position.y)

	# ---- deck: 2 stern boards + 1 bow board around the open cockpit, face y=0.52
	var planks := _descendants_mesh(boat, "DeckPlank")
	_ok(planks.size() == 3, "deck: plank count %d == 3 (P7-V3.2 cockpit spec: 2 stern + 1 bow)" % planks.size())
	var tops: Array = []
	var halfs: Array = []
	var z_lo: Array = []
	var z_hi: Array = []
	var thick_ok := true
	for p in planks:
		var mi := p as MeshInstance3D
		var ab: AABB = mi.mesh.get_aabb()
		tops.append(ab.end.y)
		halfs.append(ab.size.x * 0.5)
		z_lo.append(ab.position.z)
		z_hi.append(ab.end.z)
		if absf(ab.size.y - 0.06) > 0.004:
			thick_ok = false
	var top_ok := true
	var top_sum := 0.0
	for t in tops:
		top_sum += float(t)
		if float(t) < 0.510 or float(t) > 0.530:
			top_ok = false
	_ok(top_ok, "deck: every plank top within [0.510, 0.530] (stagger +-0.004)")
	_ok(absf(top_sum / maxf(1.0, float(tops.size())) - 0.520) < 0.003,
		"deck: mean plank top %.4f ~ 0.520 (standable face)" % (top_sum / maxf(1.0, float(tops.size()))))
	_ok(thick_ok, "deck: plank thickness 0.06")
	# seams ~2 cm; planks ordered by z
	var idx: Array = []
	for i in planks.size():
		idx.append(i)
	idx.sort_custom(func(a, b): return float(z_lo[a]) < float(z_lo[b]))
	if idx.size() == 3:
		var gap_aft: float = float(z_lo[idx[1]]) - float(z_hi[idx[0]])
		_ok(absf(gap_aft - 0.02) <= 0.006, "deck: stern board seam 0.02 (gap %.3f)" % gap_aft)
		_ok(absf(float(z_hi[idx[1]]) + 0.72) < 0.02,
			"deck: stern deck ends at z=-0.72 (got %.3f)" % float(z_hi[idx[1]]))
		_ok(absf(float(z_lo[idx[2]]) - 1.44) < 0.02,
			"deck: bow deck starts at z=1.44 (got %.3f)" % float(z_lo[idx[2]]))
		var cockpit_len: float = float(z_lo[idx[2]]) - float(z_hi[idx[1]])
		_ok(cockpit_len > 2.0 and cockpit_len < 2.3,
			"deck: open cockpit %.2f m between the decked ends" % cockpit_len)
	# every board edge must land on the hull skin at deck height (not on a fixed
	# inset): that is what keeps the planked deck sealed against the rising bow
	# sheer instead of leaving a dark slit you can see from above
	var half_max := 0.0
	var half_min := 9.0
	for h in halfs:
		half_max = maxf(half_max, float(h))
		half_min = minf(half_min, float(h))
	var wall_bad := 0
	for pz in [-2.10, -1.50, -0.90, -0.30, 0.30, 0.90, 1.50, 1.90, 2.03]:
		var sv: Vector4 = IsleWorld._boat_station_at(stations, pz)
		var wall: float = _probe_hull_wall(stations, pz, 0.52)
		var dh: Vector2 = IsleWorld._boat_deck_half(stations, pz, 0.52, 0.06)
		var expect: float = wall if wall > 0.0 else sv.y - 0.05
		if absf(dh.x - expect) > 0.008:
			wall_bad += 1
			print("[detail] deck/hull mismatch z=%.2f half=%.4f wall=%.4f" % [pz, dh.x, expect])
	_ok(wall_bad == 0, "deck: board half width tracks hull skin at y=0.52 along the length")
	var bow_wall: float = _probe_hull_wall(stations, 2.03, 0.52)
	var bow_half: float = IsleWorld._boat_deck_half(stations, 2.03, 0.52, 0.06).x
	_ok(bow_half >= bow_wall - 0.008,
		"deck: bow board reaches hull wall (%.3f >= %.3f, no dark slit)" % [bow_half, bow_wall])
	var bow_inset: float = IsleWorld._boat_section_at(stations, 2.03).x - 0.05
	_ok(bow_half > bow_inset + 0.01,
		"deck: bow board beats the old fixed inset (%.3f > %.3f)" % [bow_half, bow_inset])
	_ok(half_max <= hull_aabb.size.x * 0.5 + 0.002,
		"deck: widest plank half %.3f stays inside hull half %.3f" % [half_max, hull_aabb.size.x * 0.5])
	_ok(half_min < half_max - 0.12, "deck: planks taper with hull width (%.3f .. %.3f)" % [half_min, half_max])
	# inwale meets the deck edge
	if inwales.size() > 0:
		var iw0 := inwales[0] as MeshInstance3D
		_ok(absf(iw0.position.x) - 0.035 <= half_max + 0.05,
			"deck: inwale inner face reaches deck edge")

	# ---- interior: floor / 4 frames / 2 thwarts / bow & stern fill blocks
	var floor_mi := _find_mesh(boat, "InnerFloor")
	_ok(floor_mi != null, "interior: InnerFloor mesh present")
	if floor_mi != null:
		var fa: AABB = floor_mi.mesh.get_aabb()
		_ok(fa.size.y > 0.03 and fa.size.z > 3.0, "interior: bilge floor spans the hull")
	var ribs := _descendants_mesh(boat, "Rib")
	_ok(ribs.size() == 16, "interior: 16 frame bars (4 frames x 2 sides x 2 segments, got %d)" % ribs.size())
	var bow_fill := _find_mesh(boat, "BowFill")
	var stern_fill := _find_mesh(boat, "SternFill")
	_ok(bow_fill != null and absf(bow_fill.mesh.get_aabb().end.y - 0.520) < 0.006,
		"interior: bow fill top flush with the planked deck (0.52)")
	_ok(stern_fill != null and absf(stern_fill.mesh.get_aabb().end.y - 0.520) < 0.006,
		"interior: stern fill top flush with the planked deck (0.52)")
	if bow_fill != null:
		var bfa: AABB = bow_fill.mesh.get_aabb()
		_ok(absf(bfa.position.z - 2.07) < 0.02,
			"interior: bow fill starts where the last plank ends (z=%.3f)" % bfa.position.z)
	var thwart_names := ["Thwart00", "Thwart01"]
	var thwart_tops: Array = []
	var thwart_widths: Array = []
	for tn in thwart_names:
		var tw := _find_mesh(boat, tn)
		_ok(tw != null, "interior: " + tn + " present")
		if tw == null:
			continue
		var tab: AABB = tw.mesh.get_aabb()
		var seat_top: float = tw.position.y + tab.end.y
		thwart_tops.append(seat_top)
		thwart_widths.append(tab.size.x)
		_ok(absf(seat_top - 0.60) < 0.008, tn + " seat top %.3f ~ 0.60" % seat_top)
		_ok(absf(tab.size.y - 0.06) < 0.004, tn + " board thickness 0.06")
		_ok(absf(tab.size.z - 0.30) < 0.004, tn + " board depth 0.30")
		_ok(tab.size.x > 1.0 and tab.size.x < 1.6, tn + " width %.3f fits local beam" % tab.size.x)
	if thwart_widths.size() == 2:
		_ok(absf(float(thwart_widths[0]) - float(thwart_widths[1])) > 0.1,
			"interior: thwarts follow the local width (%.3f vs %.3f)" % [thwart_widths[0], thwart_widths[1]])
	_ok(_descendants_mesh(boat, "ThwartLeg").size() == 4, "interior: 4 thwart legs standing on the sole")
	var tw0 := _find_mesh(boat, "Thwart00")
	var tw1 := _find_mesh(boat, "Thwart01")
	_ok(tw0 != null and absf(tw0.position.z + 0.30) < 0.001, "interior: thwart00 at z=-0.30")
	_ok(tw1 != null and absf(tw1.position.z - 1.20) < 0.001, "interior: thwart01 at z=1.20")
	_ok(thwart_tops.size() > 0 and float(thwart_tops[0]) > 0.52,
		"interior: thwarts sit above the deck (seat top 0.60)")

	# ---- P7-V3.2 cockpit: sole at 0.20, coaming rim, boom headroom
	var sole := _find_mesh(boat, "Sole")
	_ok(sole != null, "interior: cockpit Sole present")
	if sole != null:
		var sa: AABB = sole.mesh.get_aabb()
		_ok(absf(sa.end.y - 0.20) < 0.008,
			"interior: sole top %.3f == 0.20 m (stand/row height for a 1.50 m crew)" % sa.end.y)
		_ok(sa.position.z > -0.76 and sa.end.z < 1.48, "interior: sole spans the open cockpit")
	var coamings := _descendants_mesh(boat, "Coaming")
	_ok(coamings.size() == 5,
		"interior: coaming rim 5 pieces (2 sides + fore + split aft, got %d)" % coamings.size())
	var boom_mi := _find_mesh(boat, "Boom")
	_ok(boom_mi != null, "rig: Boom named for probes")
	if boom_mi != null:
		var ba: AABB = boom_mi.mesh.get_aabb()
		_ok(absf(boom_mi.position.y - 1.90) < 0.01,
			"rig: boom centre %.3f == 1.90 m above waterline (1.66 m sole headroom)" % boom_mi.position.y)
	var main_sail := _find_mesh(boat, "MainSail")
	_ok(main_sail != null, "rig: MainSail present")
	if main_sail != null:
		var sail_h: float = main_sail.transform.basis.y.length() * 2.0
		var sail_foot: float = main_sail.position.y - sail_h * 0.5
		_ok(absf(sail_foot - 1.90) < 0.02,
			"rig: main sail foot %.3f sits on the 1.90 m boom" % sail_foot)
		_ok(absf(sail_h - 2.45) < 0.02, "rig: main sail height %.2f == 2.45 m" % sail_h)
	# ---- fittings: 2 oars, 2 rowlocks, 2 mooring cleats
	_ok(_descendants_mesh(boat, "OarShaft").size() == 2, "fittings: 2 oar shafts")
	_ok(_descendants_mesh(boat, "OarBlade").size() == 2, "fittings: 2 oar blades")
	_ok(_descendants_mesh(boat, "OarGrip").size() == 2, "fittings: 2 oar grips")
	_ok(_find_node(boat, "OarlockP") != null and _find_node(boat, "OarlockS") != null,
		"fittings: rowlocks P/S present")
	var oar := _find_mesh(boat, "OarShaftP")
	if oar != null:
		var oa: AABB = oar.mesh.get_aabb()
		_ok(absf(oa.size.y - 1.55) < 0.02, "fittings: oar shaft length %.2f m == 1.55 (local axis)" % oa.size.y)
		_ok(absf(oar.position.y - 0.65) < 0.006,
			"fittings: oar shaft bottom rests on the 0.60 thwarts (y=%.3f)" % oar.position.y)
		var oz0: float = oar.position.z - oa.size.y * 0.5
		var oz1: float = oar.position.z + oa.size.y * 0.5
		_ok(absf(oz0 + 0.40) < 0.02 and absf(oz1 - 1.15) < 0.02,
			"fittings: oar spans z %.2f..%.2f (covers both thwarts)" % [oz0, oz1])
		if tw0 != null and tw1 != null:
			var t0a: AABB = tw0.mesh.get_aabb()
			var t1a: AABB = tw1.mesh.get_aabb()
			_ok(oz0 <= tw0.position.z + t0a.end.z and oz1 >= tw1.position.z + t1a.position.z,
				"fittings: oar actually overhangs both thwarts (seated, not floating)")
	_ok(_find_node(boat, "MooringCleatBow") != null and _find_node(boat, "MooringCleatStern") != null,
		"fittings: bow/stern mooring cleats present")

	# ---- cabin details
	var door := _find_mesh(boat, "CabinDoor")
	var door_win := _find_mesh(boat, "CabinDoorWindow")
	_ok(door != null, "cabin: CabinDoor panel present")
	_ok(door_win != null, "cabin: CabinDoorWindow present")
	var portholes: Array = []
	var glass_nodes: Array = []
	for n in _descendants_mesh(boat, "Porthole"):
		if String(n.name).begins_with("PortholeGlass"):
			glass_nodes.append(n)
		else:
			portholes.append(n)
	_ok(portholes.size() == 4, "cabin: 4 side portholes (got %d)" % portholes.size())
	_ok(glass_nodes.size() == 4, "cabin: 4 porthole glasses")
	if door_win != null and glass_nodes.size() > 0:
		_ok(door_win.material_override == (glass_nodes[0] as MeshInstance3D).material_override,
			"cabin: door window and portholes share the glass material")

	# ---- stern lantern / bow search light contracts
	var lantern := _find_mesh(boat, "SternLantern")
	_ok(lantern != null, "lights: SternLantern present")
	var lpos: Vector3 = info["lantern_local_pos"]
	if lantern != null:
		_ok(lantern.material_override == info["lantern_mat"], "lights: SternLantern uses returned lantern_mat")
		_ok(lantern.position.distance_to(lpos) < 0.001, "lights: SternLantern at returned local pos")
		_ok(absf(lpos.x) > 0.7, "lights: stern lantern hangs outboard (x=%.2f)" % lpos.x)
	var halo := info.get("lantern_halo", null) as MeshInstance3D
	_ok(halo != null and halo.get_parent() == boat, "lights: lantern halo is a direct child of Sailboat")
	var spot := info.get("spot_node", null) as Node3D
	_ok(spot != null and spot.get_parent() == boat, "lights: BowSpot is a direct child of Sailboat")
	if spot != null:
		_ok(not spot.visible, "lights: BowSpot hidden by default")
		_ok(spot.position.distance_to(info["spot_lens_pos"] as Vector3) < 0.001,
			"lights: BowSpot at returned lens pos")
		var cone := spot.get_node_or_null("BeamCone") as MeshInstance3D
		_ok(cone != null, "lights: BeamCone under BowSpot")
		if cone != null:
			_ok(cone.material_override == info["spot_cone_mat"], "lights: BeamCone uses returned cone material")
			_ok(cone.mesh.get_aabb().size.z > 5.0, "lights: BeamCone length %.1f m" % cone.mesh.get_aabb().size.z)

	# ---- fade inventory covers the new materials
	var fade: Array = info.get("fade_mats", [])
	_ok(fade.size() >= 12, "fade: fade_mats size %d >= 12" % fade.size())
	var all_material := true
	var fade_has_fade_alpha := false
	for fm in fade:
		if not (fm is Material):
			all_material = false
		elif fm is ShaderMaterial and (fm as ShaderMaterial).shader != null:
			for u in (fm as ShaderMaterial).shader.get_shader_uniform_list():
				if String(u.get("name", "")) == "fade_alpha":
					fade_has_fade_alpha = true
	_ok(all_material, "fade: every fade_mats entry is a Material")
	_ok(fade_has_fade_alpha, "fade: toon shader exposes fade_alpha")
	var new_parts := ["GunwaleP00", "InwaleP00", "InnerFloor", "Thwart00", "OarShaftP",
		"MooringCleatBow", "Rib00PA", "BowFill", "SternFill", "CabinDoor"]
	for pn in new_parts:
		var mat0 := _mat_of(boat, pn)
		_ok(mat0 != null and fade.has(mat0), "fade: material of new part " + pn + " collected")
	var plank_mat: Material = (planks[0] as MeshInstance3D).material_override
	_ok(plank_mat != null and fade.has(plank_mat), "fade: deck plank material collected")

	# ---- whole-boat bounds (BeamCone is hidden, so it is excluded here)
	var bb := _subtree_aabb(boat, false)
	_ok(bb.size.y > 3.5, "bounds: boat height %.2f m includes mast" % bb.size.y)
	_ok(bb.size.x > 1.0 and bb.size.x < 2.8, "bounds: boat beam %.2f m sane" % bb.size.x)
	_ok(bb.size.z > 5.0 and bb.size.z < 12.0, "bounds: boat length %.2f m sane" % bb.size.z)
	_ok(bb.position.y > -0.7 and bb.position.y < 0.1, "bounds: keel y=%.3f near waterline" % bb.position.y)

	# ---- every new part follows the boat transform (wave / pitch / roll)
	var plank0 := planks[0] as MeshInstance3D
	_ok(boat.is_ancestor_of(plank0), "transform: deck plank descends from Sailboat root")
	var oar_node := _find_mesh(boat, "OarShaftP")
	_ok(oar_node != null and boat.is_ancestor_of(oar_node), "transform: oar descends from Sailboat root")
	boat.position = Vector3(3.0, 0.0, -2.0)
	boat.rotation = Vector3(0.10, 0.70, 0.05)
	await process_frame
	var want: Vector3 = boat.transform * plank0.transform.origin
	_ok(plank0.global_position.distance_to(want) < 0.001,
		"transform: plank tracks the boat transform")
	_ok(boat.is_ancestor_of(_find_mesh(boat, "SternLantern")), "transform: stern lantern rides the boat")

# ============================================================
# 2) integration: real isle.tscn, main.gd wiring, fade + night spot
# ============================================================
func _check_main_scene() -> void:
	print("[part] isle.tscn integration")
	var m: Node = MainScene.instantiate()
	get_root().add_child(m)
	var frames := 0
	while frames < 900:
		var wv = m.get("_world")
		if wv is Dictionary and not (wv as Dictionary).is_empty() and m.get("_sailboat") != null:
			break
		await process_frame
		frames += 1
	_ok(frames < 900, "main: world built within 900 frames (used %d)" % frames)
	var wv = m.get("_world")
	if not (wv is Dictionary) or (wv as Dictionary).is_empty():
		print("[FAIL] main: world dictionary missing (main.gd/isle.tscn failed to load - check for concurrent parse errors)")
		_fail += 1
		return
	var world: Dictionary = wv as Dictionary
	var boat := m.get("_sailboat") as Node3D
	_ok(boat != null and boat.name == "Sailboat", "main: _sailboat is the Sailboat root")
	if boat == null:
		return
	_ok(world.get("sailboat", null) == boat, "main: world[\"sailboat\"] is the same root node")

	for k in ["sailboat", "sailboat_path", "sailboat_speed", "sail_routes", "sail_dock_pos",
			"sail_dock_heading", "sailboat_lantern_mat", "sailboat_lantern_halo",
			"sailboat_lantern_local_pos", "sailboat_spot_node", "sailboat_spot_lens_pos",
			"sailboat_spot_cone_mat", "sailboat_fade_mats"]:
		_ok(world.has(k), "main: world dict has key " + k)
	_ok(is_equal_approx(float(world.get("sailboat_speed", 0.0)), float(m.get("_sail_speed"))),
		"main: sail speed wired from world")
	_ok(not (world.get("sail_routes", []) as Array).is_empty(), "main: sail_routes not empty")
	for g in ["Hull", "Deck", "Interior", "Fittings", "Cabin", "Rig"]:
		_ok(boat.get_node_or_null(g) != null, "main: boat group " + g)
	var planks := _descendants_mesh(boat, "DeckPlank")
	_ok(planks.size() == 3, "main: 3 deck planks in the live scene (open cockpit)")
	_ok(_descendants_mesh(boat, "OarShaft").size() == 2, "main: 2 oars in the live scene")
	_ok(_descendants_mesh(boat, "Rib").size() == 16, "main: 16 frame bars in the live scene")
	var lantern := _find_mesh(boat, "SternLantern")
	_ok(m.get("_boat_lantern_mat") == world.get("sailboat_lantern_mat"),
		"main: _boat_lantern_mat wired from the world lantern material")
	# main.gd duplicates every boat ShaderMaterial for the distant fade, so the
	# node override is the duplicate; the original stays referenced by main for glow.
	_ok(lantern != null and lantern.material_override is ShaderMaterial,
		"main: SternLantern still carries a toon ShaderMaterial")
	if lantern != null:
		_ok(lantern.global_position.distance_to(
			boat.to_global(m.get("_boat_lantern_local") as Vector3)) < 0.01,
			"main: stern lantern matches _boat_lantern_local")
	var spot := m.get("_boat_spot_node") as Node3D
	_ok(spot != null and spot.get_parent() == boat, "main: BowSpot parent unchanged")
	_ok(m.get("_boat_lantern_halo") != null, "main: lantern halo wired")

	# ---- fade collection: every material duplicated + new parts included
	var fm: Array = m.get("_boat_fade_mats") as Array
	var fstd: Array = m.get("_boat_fade_std") as Array
	_ok(fm.size() >= 10, "fade: _boat_fade_mats size %d >= 10" % fm.size())
	var fm_all := true
	for x in fm:
		if not (x is ShaderMaterial):
			fm_all = false
	_ok(fm_all, "fade: _boat_fade_mats holds ShaderMaterials")
	_ok(fm.has((planks[0] as MeshInstance3D).material_override),
		"fade: live deck plank material registered")
	var glass := _find_mesh(boat, "PortholeGlassP0")
	_ok(glass != null, "fade: porthole glass present")
	_ok(fstd.size() >= 1, "fade: lantern halo StandardMaterial3D registered in _boat_fade_std")
	var glass_fm := false
	if glass != null and glass.material_override is ShaderMaterial:
		for d in fm:
			if d == glass.material_override:
				glass_fm = true
	_ok(glass_fm, "fade: porthole glass ShaderMaterial registered in _boat_fade_mats")
	_ok(lantern != null and fm.has(lantern.material_override as Material),
		"fade: stern lantern material registered for the boat fade")
	# drive fade and verify the shader parameter actually changes
	var sm: ShaderMaterial = null
	for x in fm:
		var cand := x as ShaderMaterial
		if bool(m.call("_shader_has_uniform", cand, "fade_alpha")):
			sm = cand
			break
	_ok(sm != null, "fade: found a boat ShaderMaterial with fade_alpha")
	if sm != null:
		m.set("_boat_fade", 0.37)
		m.call("_apply_boat_fade")
		var got := float(sm.get_shader_parameter("fade_alpha"))
		_ok(absf(got - 0.37) < 0.002, "fade: _apply_boat_fade writes fade_alpha=0.37 (got %.3f)" % got)
		m.set("_boat_fade", 1.0)
		m.call("_apply_boat_fade")
		_ok(absf(float(sm.get_shader_parameter("fade_alpha")) - 1.0) < 0.002,
			"fade: fade_alpha restored to 1.0")
	_ok(bool(m.get("_sail_boat_visible")) and boat.visible, "fade: boat visible at fade=1.0")

	# ---- night bow spotlight: reuse the P5 runtime contract
	m.set("_boat_state", "COASTAL_CRUISE")
	m.set("_boat_fade", 1.0)
	m.set("_boat_speed_cur", 2.0)
	m.set("_sail_boat_visible", true)
	m.set("_sun_alt", -12.0)
	boat.position = m.get("_boat_dock_pos") as Vector3
	m.call("_update_boat_spot")
	var strength := float(m.get("_dbg_spot_strength"))
	_ok(strength > 0.2, "night: spot strength %.2f > 0.2" % strength)
	_ok(spot != null and spot.visible, "night: BowSpot visible at night")
	if spot != null:
		var origin := m.get("_dbg_spot_origin") as Vector3
		var want := boat.to_global(m.get("_boat_spot_lens") as Vector3)
		_ok(origin.distance_to(want) < 0.05, "night: beam origin at the lens")
		var dir := (m.get("_dbg_spot_dir") as Vector3).normalized()
		var bow := (boat.global_basis.z as Vector3).normalized()
		_ok(dir.dot(bow) > 0.6 and dir.y < -0.05, "night: beam points forward and down")
	m.set("_sun_alt", 20.0)
	m.call("_update_boat_spot")
	_ok(not spot.visible, "night: BowSpot hidden again in daylight")
	m.queue_free()
	await process_frame

# ============================================================
# 3) window screenshots (GPU, run under the exclusive gpu.lock)
# ============================================================
func _pick_coastal_route(m: Node) -> Dictionary:
	var routes: Array = (m.get("_sail_routes") as Array)
	for r in routes:
		if r is Dictionary and String((r as Dictionary).get("kind", "")) == "coastal":
			return r as Dictionary
	if not routes.is_empty() and routes[0] is Dictionary:
		return routes[0] as Dictionary
	return {}

func _aim(m: Node, target: Vector3, theta: float, elev: float, radius: float, fov: float) -> void:
	m.set("_cam_target", target)
	m.set("_theta", theta)
	m.set("_elev", elev)
	m.set("_radius", radius)
	m.set("_fov", fov)
	await _frames(3)

func _shoot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := SHOTS_DIR + shot_name + ".png"
	var err := img.save_png(path)
	_shot_check(err == OK and img.get_width() > 0 and img.get_height() > 0,
		"shot " + shot_name + " saved")
	print("[SHOT] ", shot_name, " ", img.get_width(), "x", img.get_height(), " -> ", path)
	await process_frame

func _run_shots() -> void:
	print("[part] window screenshots")
	DirAccess.make_dir_recursive_absolute(SHOTS_DIR)
	get_root().size = Vector2i(2560, 1440)
	await process_frame
	print("[stage] window=", DisplayServer.window_get_size(), " root=", get_root().size, " vis=", get_root().get_visible_rect().size)
	var m: Node = MainScene.instantiate()
	get_root().add_child(m)
	var frames := 0
	while frames < 1500:
		var wv = m.get("_world")
		if wv is Dictionary and not (wv as Dictionary).is_empty() and m.get("_sailboat") != null:
			break
		await process_frame
		frames += 1
	_shot_check(frames < 1500, "main scene ready for shots")
	if frames >= 1500:
		return
	# game state: playing, time frozen, hud/menu hidden
	m.set("_mode", 1)
	m.set("_started", true)
	m.set("_paused", true)
	m.set("_blending", "")
	m.set("_auto_orbit", false)
	m.set("_time_source", "sim")
	m.set("_sail_boat_visible", true)
	m.set("_boat_fade", 1.0)
	var menu = m.get("_menu")
	if menu != null:
		menu.set("menu_visible", false)
		menu.set_process(false)
		menu.set("visible", false)
	var hud = m.get("_hud")
	if hud != null and hud.has_method("set_hud_visible"):
		hud.call("set_hud_visible", false, false)
	# stage the boat on the coastal route at 46% then freeze it with the shot hold hook
	var route: Dictionary = _pick_coastal_route(m)
	_shot_check(not route.is_empty(), "coastal route found")
	m.call("_shot_boat_cruise", route, 0.46)
	await _frames(2)
	var boat := m.get("_sailboat") as Node3D
	var heading := float(m.get("_sail_heading"))
	var bp: Vector3 = boat.global_position
	m.set("_shot_boat_hold_pos", bp)
	m.set("_shot_boat_hold_heading", heading)
	m.set("_shot_boat_hold", true)
	m.set("_boat_speed_cur", 2.4)
	m.set("_boat_state", "COASTAL_CRUISE")
	m.set("_boat_fade", 1.0)
	await _frames(6)
	bp = boat.global_position
	heading = float(m.get("_sail_heading"))
	var bow := Vector3(sin(heading), 0.0, cos(heading))
	var right := Vector3(cos(heading), 0.0, -sin(heading))
	print("[stage] boat at ", bp, " heading=", heading)

	# 1) noon cruise, same framing as the P5 04_boat_route shot
	m.call("_set_time_of_day", 12.0 * 60.0 + 5.0)
	await _frames(5)
	await _aim(m, bp + Vector3(0.0, 1.35, 0.0), atan2(bp.x, bp.z) + 0.55, 0.17, 17.0, 50.0)
	await _shoot("boat_noon_cruise")

	# 2) close side view from starboard, whole hull in frame
	await _aim(m, bp + Vector3(0.0, 0.55, 0.0), atan2(right.x, right.z), 0.07, 7.6, 44.0)
	await _shoot("boat_close_side")

	# 2b) bow close-up: from ahead, looking back along the hull
	var cb: Vector3 = bp + bow * 5.0 + right * 1.3 + Vector3(0.0, 1.25, 0.0)
	m.call("_pose_look", cb, bp + bow * 1.6 + Vector3(0.0, 0.80, 0.0), 45.0)
	await _frames(3)
	await _shoot("boat_close_bow")

	# 2c) stern close-up: from astern, looking forward over the tiller / lantern
	var cs: Vector3 = bp - bow * 4.6 + right * 1.4 + Vector3(0.0, 1.15, 0.0)
	m.call("_pose_look", cs, bp - bow * 1.3 + Vector3(0.0, 0.70, 0.0), 45.0)
	await _frames(3)
	await _shoot("boat_close_stern")

	# 3) close three-quarter view from the bow quarter
	var ob := (bow * 0.62 + right * 0.78).normalized()
	await _aim(m, bp + Vector3(0.0, 0.72, 0.0), atan2(ob.x, ob.z), 0.22, 7.2, 46.0)
	await _shoot("boat_close_oblique")

	# 4) high three-quarter looking down into the deck / thwarts / oars
	await _aim(m, bp + Vector3(0.0, 0.35, 0.0), heading + 2.45, 0.95, 6.0, 55.0)
	await _shoot("boat_deck_top")

	# 5) night stern lantern close-up from the port quarter (lantern hangs to port)
	m.call("_set_time_of_day", 21.0 * 60.0 + 40.0)
	await _frames(6)
	var port := -right
	await _aim(m, bp + Vector3(0.0, 1.00, 0.0), atan2(port.x, port.z), 0.16, 5.8, 48.0)
	await _shoot("boat_night_lantern")

	# 6) night bow search light + beam, from ahead to starboard looking back
	var spot := m.get("_boat_spot_node") as Node3D
	m.call("_update_boat_spot")
	_shot_check(spot != null and spot.visible, "night: bow spotlight visible for the shot")
	var cam_pos: Vector3 = bp + bow * 4.2 + right * 7.4 + Vector3(0.0, 2.35, 0.0)
	var cam_target: Vector3 = bp + bow * 2.6 + Vector3(0.0, 0.75, 0.0)
	m.call("_pose_look", cam_pos, cam_target, 52.0)
	await _frames(4)
	await _shoot("boat_night_spotlight")
	print("=== P7-V3 BOAT SHOTS DONE ===")
