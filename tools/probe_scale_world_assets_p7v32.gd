extends SceneTree
## P7-V3.2 T4 环境/船只/灯塔/码头/灯/秋千/猫/海鸥 尺度测量探针（headless）。
## 构建真实 procedural world，输出 [M] 机器可读测量行，供开发产物/p7v32/notes/world_audit.md。
## RESULT 行: [SCALE] RESULT lines=N issues=M ；exit 0（issues 是审计发现，不是崩溃）。
## 用法: godot --headless --path <proj> --script res://tools/probe_scale_world_assets_p7v32.gd

const M := preload("res://scripts/isle_math.gd")
const WORLD := preload("res://scripts/world.gd")

var _lines := 0
var _issues := 0

func _initialize() -> void:
	var host := Node3D.new()
	host.name = "ProbeHost"
	get_root().add_child(host)
	var t0 := Time.get_ticks_msec()
	var world: Dictionary = WORLD.build(host)
	_line("build_ms=%d" % (Time.get_ticks_msec() - t0))
	_measure_math()
	_measure_dock(world)
	_measure_boat(world)
	_measure_lighthouse(world)
	_measure_swing(world)
	_measure_lamps(world)
	_measure_perches(world)
	_measure_cat(host)
	_measure_gull(host, world)
	print("=== P7-V3.2 SCALE WORLD ASSET RESULT: lines=%d issues=%d ===" % [_lines, _issues])
	host.queue_free()
	quit(0)

# ------------------------------------------------------------------ output --
func _line(text: String) -> void:
	_lines += 1
	print("[M] " + text)

func _issue(text: String) -> void:
	_issues += 1
	print("[M][ISSUE] " + text)

# ------------------------------------------------------------------- aabb ---
# NOTE: nodes added to get_root() during SceneTree._initialize() are not reported
# as "inside tree" yet (get_global_transform() warns and returns identity), so the
# probe accumulates the local transforms itself.
func _gxf(n: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf

func _gpos(n: Node3D) -> Vector3:
	return _gxf(n).origin

func _gbox(n: Node) -> AABB:
	var acc: Array = []
	_walk_box(n, acc)
	if acc.is_empty():
		return AABB()
	return acc[0]

func _walk_box(n: Node, acc: Array) -> void:
	if n is VisualInstance3D:
		var vi := n as VisualInstance3D
		var local: AABB = vi.get_aabb()
		if n is MultiMeshInstance3D:
			var mm := n as MultiMeshInstance3D
			if mm.multimesh == null:
				local = AABB()
			else:
				local = mm.get_aabb()
		if local.size.length_squared() > 0.0:
			var b: AABB = _gxf(vi) * local
			if acc.is_empty():
				acc.append(b)
			else:
				acc[0] = (acc[0] as AABB).merge(b)
	for c in n.get_children():
		_walk_box(c, acc)

func _named(root: Node, node_name: String) -> Node:
	return root.find_child(node_name, true, false)

func _named_box(root: Node, node_name: String) -> AABB:
	var n := _named(root, node_name)
	if n == null:
		return AABB()
	return _gbox(n)

func _box_local_excluding(root_n: Node, base_n: Node, skip_substr: String) -> AABB:
	var inv: Transform3D = _gxf(base_n).affine_inverse()
	var acc: Array = []
	_walk_box_rel(root_n, inv, skip_substr, acc)
	if acc.is_empty():
		return AABB()
	return acc[0]

func _walk_box_rel(n: Node, inv: Transform3D, skip_substr: String, acc: Array) -> void:
	if skip_substr != "" and String(n.name).findn(skip_substr) >= 0:
		return
	if n is VisualInstance3D:
		var vi := n as VisualInstance3D
		var local: AABB = vi.get_aabb()
		if n is MultiMeshInstance3D:
			var mm := n as MultiMeshInstance3D
			if mm.multimesh == null:
				local = AABB()
			else:
				local = mm.get_aabb()
		if local.size.length_squared() > 0.0:
			var b: AABB = (inv * _gxf(vi)) * local
			if acc.is_empty():
				acc.append(b)
			else:
				acc[0] = (acc[0] as AABB).merge(b)
	for c in n.get_children():
		_walk_box_rel(c, inv, skip_substr, acc)

func _fmt(b: AABB) -> String:
	return "min(%.3f,%.3f,%.3f) max(%.3f,%.3f,%.3f) size(%.3f,%.3f,%.3f)" % [
		b.position.x, b.position.y, b.position.z,
		b.end.x, b.end.y, b.end.z, b.size.x, b.size.y, b.size.z]

# ----------------------------------------------------------------- anchors --
func _measure_math() -> void:
	_line("math.house_xz=(%.3f,%.3f) HOUSE_W=%.3f HOUSE_D=%.3f WALL_H=%.3f ROOF_H=%.3f" % [
		M.HOUSE_X, M.HOUSE_Z, M.HOUSE_W, M.HOUSE_D, M.HOUSE_WALL_H, M.HOUSE_ROOF_H])
	var gy := M.house_ground_y()
	var dw := M.door_world()
	var da := M.door_approach()
	_line("math.house_ground_y=%.3f door_world=(%.3f,%.3f,%.3f) door_approach=(%.3f,%.3f,%.3f)" % [
		gy, dw.x, dw.y, dw.z, da.x, da.y, da.z])
	var ds := M.dock_start()
	var de := M.dock_end()
	var dd := M.dock_dir()
	_line("math.dock_start=(%.3f,%.3f,%.3f) dock_end=(%.3f,%.3f,%.3f) dock_dir=(%.3f,%.3f) DOCK_LENGTH=%.3f DOCK_WIDTH=%.3f" % [
		ds.x, ds.y, ds.z, de.x, de.y, de.z, dd.x, dd.z, M.DOCK_LENGTH, M.DOCK_WIDTH])
	_line("math.CAM_TARGET=(%.3f,%.3f,%.3f) CAM_START_THETA=%.3f CAM_START_PHI=%.3f CAM_START_R=%.3f" % [
		M.CAM_TARGET.x, M.CAM_TARGET.y, M.CAM_TARGET.z, M.CAM_START_THETA, M.CAM_START_PHI, M.CAM_START_R])

# -------------------------------------------------------------------- dock --
func _measure_dock(world: Dictionary) -> void:
	var d: Dictionary = world["dock"]
	var node: Node3D = d["node"]
	_line("dock.node=(%.3f,%.3f,%.3f) deck_world_y=%.3f deck_local_y=%.3f" % [
		_gpos(node).x, _gpos(node).y, _gpos(node).z,
		float(d["deck_world_y"]), float(d["deck_local_y"])])
	var lands: Vector3 = d["light"]["pos"]
	_line("dock.lantern_world=(%.3f,%.3f,%.3f) mount_above_deck=%.3f range=%.3f intensity=%.3f" % [
		lands.x, lands.y, lands.z, lands.y - float(d["deck_world_y"]),
		float(d["light"]["range"]), float(d["light"]["intensity"])])
	var perch: Vector3 = d["perch"]
	var boll: Vector3 = d["bollard"]
	_line("dock.perch=(%.3f,%.3f,%.3f) perch_above_deck=%.3f bollard_top=(%.3f,%.3f,%.3f)" % [
		perch.x, perch.y, perch.z, perch.y - float(d["deck_world_y"]),
		boll.x, boll.y, boll.z])
	var piles: Array = d["piles"]
	_line("dock.piles=%d pile_top=%.3f pile_bottom=%.3f" % [
		piles.size(), float(piles[0]["top"]) if piles.size() > 0 else 0.0,
		float(piles[0]["bottom"]) if piles.size() > 0 else 0.0])
	var mm := _named(node, "DockPlanks") as MultiMeshInstance3D
	var planks := 0
	if mm != null and mm.multimesh != null:
		planks = mm.multimesh.instance_count
	_line("dock.deck_planks=%d dock_aabb=%s" % [planks, _fmt(_gbox(node))])

# -------------------------------------------------------------------- boat --
func _measure_boat(world: Dictionary) -> void:
	var boat: Node3D = world["sailboat"]
	var b := _gbox(boat)
	_line("boat.aabb=%s" % _fmt(b))
	var bo := _gpos(boat)
	_line("boat.origin=(%.3f,%.3f,%.3f) loa=%.3f beam=%.3f height=%.3f keel_y=%.3f top_y=%.3f" % [
		bo.x, bo.y, bo.z, b.size.z, b.size.x, b.size.y, b.position.y - bo.y, b.end.y - bo.y])
	var deck_top := -999.0
	var deck_n := 0
	for i in 3:
		var n := _named(boat, "DeckPlank%02d" % i)
		if n != null:
			deck_n += 1
			var nb := _gbox(n)
			deck_top = maxf(deck_top, nb.end.y - bo.y)
	_line("boat.deck_planks=%d deck_top_local=%.3f" % [deck_n, deck_top])
	var sole_b := _named_box(boat, "Sole")
	var sole_top := sole_b.end.y - bo.y if sole_b.size.length_squared() > 0.0 else -999.0
	_line("boat.sole_top_local=%.3f" % sole_top)
	if absf(sole_top - 0.20) > 0.008:
		_issue("boat.sol: sole top %.3f != 0.20 (cockpit floor)" % sole_top)
	var hull := _named(boat, "Hull")
	var hull_mi: MeshInstance3D = null
	if hull != null:
		for c in hull.get_children():
			if c is MeshInstance3D and not String(c.name).begins_with("Gunwale"):
				hull_mi = c as MeshInstance3D
				break
	if hull_mi != null and hull_mi.mesh != null:
		var ha: AABB = hull_mi.mesh.get_aabb()
		_line("boat.hull_only loa=%.3f beam=%.3f draft=%.3f sheer_top=%.3f" % [
			ha.size.z, ha.size.x, -ha.position.y, ha.end.y])
	else:
		_line("boat.hull_only=unmeasured")
	var floor_b := _named_box(boat, "InnerFloor")
	var floor_top := floor_b.end.y - bo.y if floor_b.size.length_squared() > 0.0 else -999.0
	_line("boat.inner_floor_top_local=%.3f" % floor_top)
	for nm in ["Thwart00", "Thwart01"]:
		var tb := _named_box(boat, nm)
		if tb.size.length_squared() > 0.0:
			var top: float = tb.end.y - bo.y
			_line("boat.%s seat_top_local=%.3f seat_above_sole=%.3f size=(%.3f,%.3f,%.3f)" % [
				nm, top, top - maxf(sole_top, 0.0), tb.size.x, tb.size.y, tb.size.z])
	var boom_n := _named(boat, "Boom")
	if boom_n != null:
		var bb := _gbox(boom_n)
		_line("boat.boom_local_y=%.3f boom_above_deck=%.3f boom_above_sole=%.3f" % [
			(bb.position.y + bb.end.y) * 0.5 - bo.y,
			(bb.position.y + bb.end.y) * 0.5 - bo.y - deck_top,
			(bb.position.y + bb.end.y) * 0.5 - bo.y - floor_top])
	else:
		_line("boat.boom=unmeasured(no named Boom node)")
	var mast_b := _named_box(boat, "Mast")
	if mast_b.size.length_squared() > 0.0:
		_line("boat.mast_top_local=%.3f" % (mast_b.end.y - bo.y))
	var cabin_b := _named_box(boat, "CabinBody")
	if cabin_b.size.length_squared() > 0.0:
		_line("boat.cabin_body_top_local=%.3f" % (cabin_b.end.y - bo.y))
	var lant: Vector3 = world["sailboat_lantern_local_pos"]
	var spot: Vector3 = world["sailboat_spot_lens_pos"]
	_line("boat.lantern_local=(%.3f,%.3f,%.3f) spot_lens_local=(%.3f,%.3f,%.3f)" % [
		lant.x, lant.y, lant.z, spot.x, spot.y, spot.z])
	# 站立净空：sole 顶到 boom 底（Lead 判据 ≥1.50 m，容 1.50 m 岛民站立）
	if boom_n != null:
		var bb2 := _gbox(boom_n)
		var clearance_sole: float = (bb2.position.y - bo.y) - sole_top
		var clearance_floor: float = (bb2.position.y - bo.y) - floor_top
		_line("boat.standing_clearance_sole_to_boom_min=%.3f (sole=%.3f; inner_floor_ok=%.3f)" % [
			clearance_sole, sole_top, clearance_floor])
		if clearance_sole < 1.50:
			_issue("boat.standing_clearance: %.3f m < 1.50 m above sole" % clearance_sole)

# -------------------------------------------------------------- lighthouse --
func _measure_lighthouse(world: Dictionary) -> void:
	var lh: Node3D = world["lighthouse"]
	var plat: Node3D = world["lighthouse_platform"]
	var beam: Vector3 = world["lighthouse_beam_origin"]
	var b := _gbox(lh)
	_line("lh.node=(%.3f,%.3f,%.3f) height_declared=%.3f aabb_height=%.3f top=%.3f" % [
		_gpos(lh).x, _gpos(lh).y, _gpos(lh).z,
		float(world["lighthouse_height"]), b.size.y, b.end.y])
	_line("lh.platform=(%.3f,%.3f,%.3f) beam_origin=(%.3f,%.3f,%.3f)" % [
		_gpos(plat).x, _gpos(plat).y, _gpos(plat).z,
		beam.x, beam.y, beam.z])
	var perches: Array = world["lighthouse_perches"]
	for p in perches:
		if p is Vector3:
			var pv: Vector3 = p
			_line("lh.perch kind=lighthouse y=%.3f y_above_platform=%.3f" % [
				pv.y, pv.y - _gpos(plat).y])
		else:
			var pd: Dictionary = p
			var pos: Vector3 = pd["pos"]
			_line("lh.perch kind=%s y=%.3f y_above_platform=%.3f radius=%.3f" % [
				String(pd["kind"]), pos.y, pos.y - _gpos(plat).y, float(pd["radius"])])
	var light: Dictionary = world["lighthouse_light"]
	var lp: Vector3 = light["pos"]
	_line("lh.light pos=(%.3f,%.3f,%.3f) range=%.3f intensity=%.3f" % [
		lp.x, lp.y, lp.z, float(light["range"]), float(light["intensity"])])
	var oy := _gpos(lh).y
	var pbase := _named_box(lh, "PlinthBase")
	var pcap := _named_box(lh, "PlinthCap")
	if pbase.size.length_squared() > 0.0:
		_line("lh.plinth_base top_local=%.3f r_bottom=%.3f" % [
			pbase.end.y - oy, pbase.size.x * 0.5])
	else:
		_line("lh.plinth_base=unmeasured")
	if pcap.size.length_squared() > 0.0:
		_line("lh.plinth_cap top_local=%.3f r=%.3f" % [pcap.end.y - oy, pcap.size.x * 0.5])
	else:
		_line("lh.plinth_cap=unmeasured")
	var frame := _named_box(lh, "DoorFrame")
	var leaf := _named_box(lh, "DoorLeaf")
	var thr := _named_box(lh, "DoorThreshold")
	if frame.size.length_squared() > 0.0:
		_line("lh.door_frame_bottom_local=%.3f door_frame_top_local=%.3f" % [
			frame.position.y - oy, frame.end.y - oy])
	if leaf.size.length_squared() > 0.0:
		_line("lh.door_leaf_bottom_local=%.3f door_leaf_top_local=%.3f leaf_w=%.3f leaf_h=%.3f" % [
			leaf.position.y - oy, leaf.end.y - oy, leaf.size.x, leaf.size.y])
	if thr.size.length_squared() > 0.0:
		_line("lh.door_threshold_top_local=%.3f" % (thr.end.y - oy))
	if frame.size.length_squared() > 0.0 and pcap.size.length_squared() > 0.0:
		var ptop: float = pcap.end.y - oy
		var dtop: float = frame.position.y - oy
		if dtop < ptop - 0.01:
			_issue("lighthouse door bottom %.3f is buried %.3f m below plinth top %.3f" % [dtop, ptop - dtop, ptop])
	_measure_lighthouse_stairs(lh, oy)

func _measure_lighthouse_stairs(lh: Node3D, oy: float) -> void:
	var prev_rout := -1.0
	var max_dr := 0.0
	var checked := 0
	for i in 7:
		var n := _named(lh, "DoorStep%d" % i)
		if n == null or not (n is MeshInstance3D):
			_issue("lighthouse step %d missing" % i)
			continue
		var mi := n as MeshInstance3D
		var bm := mi.mesh as BoxMesh
		if bm == null:
			_issue("lighthouse step %d is not a BoxMesh" % i)
			continue
		var top_y: float = mi.position.y + bm.size.y * 0.5
		var bottom_y: float = mi.position.y - bm.size.y * 0.5
		var depth: float = bm.size.z
		var r_center: float = Vector2(mi.position.x, mi.position.z).length()
		var r_in: float = r_center - depth * 0.5
		var r_out: float = r_center + depth * 0.5
		var r_plinth: float = 2.00 if top_y > 0.98 else 2.32 - (0.34 / 1.05) * top_y
		_line("lh.step%d top=%.3f bottom=%.3f r_in=%.3f r_out=%.3f plinth_r=%.3f exposed=%.3f tang=%.3f" % [
			i, top_y, bottom_y, r_in, r_out, r_plinth, r_out - r_plinth, bm.size.x])
		if r_out > 2.85:
			_issue("lighthouse step%d outer radius %.3f exceeds terrace 2.85" % [i, r_out])
		if r_in <= r_plinth + 0.01:
			_issue("lighthouse step%d inner radius %.3f buried inside plinth r %.3f" % [i, r_in, r_plinth])
		if absf(bottom_y) > 0.01:
			_issue("lighthouse step%d floats: bottom %.3f != terrace 0.0" % [i, bottom_y])
		if absf(top_y - 0.16 * float(7 - i)) > 0.002:
			_issue("lighthouse step%d top %.3f != rise %.3f" % [i, top_y, 0.16 * float(7 - i)])
		if prev_rout > 0.0:
			max_dr = maxf(max_dr, absf(r_out - prev_rout))
		prev_rout = r_out
		checked += 1
	if max_dr > 0.45:
		_issue("lighthouse stair outer radius jumps %.3f m between treads (>0.45)" % max_dr)
	var s0 := _named_box(lh, "DoorStep0")
	var thr := _named_box(lh, "DoorThreshold")
	if s0.size.length_squared() > 0.0 and thr.size.length_squared() > 0.0:
		var step0_top: float = s0.end.y - oy
		var thr_top: float = thr.end.y - oy
		_line("lh.step0_to_threshold gap=%.3f (step0 top %.3f, threshold top %.3f)" % [
			thr_top - step0_top, step0_top, thr_top])
		if thr_top - step0_top < 0.0 or thr_top - step0_top > 0.25:
			_issue("lighthouse top step %.3f to threshold %.3f mismatch" % [step0_top, thr_top])
	_line("lh.stairs_checked=%d max_outer_jump=%.3f" % [checked, max_dr])

# ------------------------------------------------------------------- swing --
func _measure_swing(world: Dictionary) -> void:
	var swing: Node3D = world["swing"]
	var pivot := _gpos(swing)
	var ground: float = M.terrain_height(pivot.x, pivot.z)
	_line("swing.pivot=(%.3f,%.3f,%.3f) ground=%.3f pivot_above_ground=%.3f" % [
		pivot.x, pivot.y, pivot.z, ground, pivot.y - ground])
	var seat := _named_box(swing, "SwingSeat")
	if seat.size.length_squared() > 0.0:
		var top: float = seat.end.y
		_line("swing.seat_top_world=%.3f seat_above_ground=%.3f seat_size=(%.3f,%.3f,%.3f)" % [
			top, top - ground, seat.size.x, seat.size.y, seat.size.z])
		if top - ground < 0.40 or top - ground > 0.62:
			_issue("swing seat %.3f m above ground (1.50 m human wants 0.45-0.55)" % (top - ground))
	else:
		_line("swing.seat=unmeasured(no named SwingSeat node)")

# ------------------------------------------------------------------- lamps --
func _measure_lamps(world: Dictionary) -> void:
	var lamps: Array = world["lamps"]
	_line("lamps.count=%d" % lamps.size())
	for i in lamps.size():
		var l: Array = lamps[i]
		var info: Dictionary = l[3]
		var light: Dictionary = l[2]
		var base: Vector3 = info["base"]
		var lantern: Vector3 = info["lantern"]
		var ground: float = M.terrain_height(base.x, base.z)
		var mount: float = lantern.y - ground
		_line("lamp%d name=%s base=(%.3f,%.3f,%.3f) ground=%.3f lantern=(%.3f,%.3f,%.3f) mount_above_ground=%.3f range=%.3f intensity=%.3f" % [
			i, String(info["name"]), base.x, base.y, base.z, ground,
			lantern.x, lantern.y, lantern.z, mount,
			float(light["range"]), float(light["intensity"])])
		var cap_top_derived: float = mount + 0.20
		_line("lamp%d cap_top_derived=%.3f (street_lamp_h target 2.75-3.05)" % [i, cap_top_derived])
		if mount < 2.45 or mount > 2.65:
			_issue("lamp%d lantern centre %.3f m above ground outside 2.45-2.65 target" % [i, mount])
		if cap_top_derived < 2.745 or cap_top_derived > 3.05:
			_issue("lamp%d cap top %.3f outside 2.75-3.05 target" % [i, cap_top_derived])
	var lights: Array = world["light_sources"]
	_line("light_sources.count=%d (expect 8: 6 street + dock + sailboat + lighthouse)" % lights.size())
	for i in lights.size():
		var ld: Dictionary = lights[i]
		var lp: Vector3 = ld["pos"]
		_line("light_source%d pos=(%.3f,%.3f,%.3f) range=%.3f intensity=%.3f" % [
			i, lp.x, lp.y, lp.z, float(ld["range"]), float(ld["intensity"])])

# ----------------------------------------------------------------- perches --
func _measure_perches(world: Dictionary) -> void:
	var perches: Array = world["perches"]
	var kinds := {}
	var dy_min := 1.0e9
	var dy_max := -1.0e9
	for p in perches:
		var pd: Dictionary = p
		var pos: Vector3 = pd["pos"]
		var kind := String(pd["kind"])
		kinds[kind] = int(kinds.get(kind, 0)) + 1
		var g: float = M.terrain_height(pos.x, pos.z)
		var dy: float = pos.y - g
		dy_min = minf(dy_min, dy)
		dy_max = maxf(dy_max, dy)
	_line("perches.count=%d kinds=%s min_dy=%.3f max_dy=%.3f" % [
		perches.size(), str(kinds), dy_min, dy_max])
	for p in perches:
		var pd: Dictionary = p
		var pos: Vector3 = pd["pos"]
		if String(pd["kind"]) == "lighthouse":
			_line("perches.lighthouse id=%s pos=(%.3f,%.3f,%.3f) radius=%.3f" % [
				String(pd["id"]), pos.x, pos.y, pos.z, float(pd["radius"])])

# --------------------------------------------------------------------- cat --
func _measure_cat(host: Node3D) -> void:
	var cat_script = load("res://scripts/isle_cat.gd")
	if cat_script == null:
		_line("cat=unavailable")
		return
	var holder := Node3D.new()
	holder.name = "CatHolder"
	host.add_child(holder)
	var cat: Dictionary = cat_script.build(holder, Vector3.ZERO, 0.0, {"idle": false, "shadow": false})
	var root: Node3D = cat["root"]
	var b := _gbox(root)
	_line("cat.aabb=%s" % _fmt(b))
	_line("cat.seated_ear_tip_height=%.3f body_length_incl_tail=%.3f width=%.3f" % [
		b.end.y, b.size.z, b.size.x])
	var head_core: Node3D = cat["head_core"]
	var hb := _gbox(head_core)
	var nose_z: float = hb.end.z
	var tail_j0: Node3D = cat["tail"][0]
	var tail_root_z: float = _gpos(tail_j0).z - _gpos(root).z
	_line("cat.nose_z=%.3f tail_root_z=%.3f nose_to_tail_root=%.3f" % [
		nose_z, tail_root_z, nose_z - tail_root_z])
	var scale_map: Dictionary = cat_script.get_script_constant_map()
	var cat_k: float = float(scale_map.get("CAT_MODEL_SCALE", 1.0))
	var body_group: Node3D = cat["body"]
	var body_b := _gbox(body_group)
	_line("cat.model_scale=%.3f body_mesh_r_scaled=%.3f head_mesh_r_scaled=%.3f" % [
		cat_k, 0.23 * cat_k, 0.155 * cat_k])
	_line("cat.stand_shoulder_height=%.3f body_width=%.3f" % [
		body_b.end.y - _gpos(root).y, body_b.size.x])
	if b.end.y < 0.40 or b.end.y > 0.50:
		_issue("cat seated ear-tip height %.3f outside 0.40-0.50 target" % b.end.y)
	if nose_z - tail_root_z > 0.55:
		_issue("cat nose-to-tail-root %.3f exceeds 0.55 target" % (nose_z - tail_root_z))
	if body_b.size.x < 0.24 or body_b.size.x > 0.28:
		_issue("cat body width %.3f outside 0.24-0.28 target" % body_b.size.x)
	if body_b.end.y - _gpos(root).y < 0.25 or body_b.end.y - _gpos(root).y > 0.30:
		_issue("cat standing shoulder height %.3f outside 0.25-0.30 target" % (body_b.end.y - _gpos(root).y))
	holder.queue_free()

# -------------------------------------------------------------------- gull --
func _measure_gull(host: Node3D, world: Dictionary) -> void:
	var fx_script = load("res://scripts/fx.gd")
	if fx_script == null:
		_line("gull=unavailable")
		return
	var flock = fx_script.BirdFlock.new()
	host.add_child(flock)
	flock.setup(world["perches"])
	var birds: Array = flock.get("_birds")
	if birds.is_empty():
		_line("gull=no_birds")
		return
	var bird: Dictionary = birds[0]
	var bnode: Node3D = bird["node"]
	# 世界 AABB 会把鸟的 yaw、收翼与栖枝混在一起，所以 body-only 与翼展都在鸟局部系量。
	var body_only := _box_local_excluding(bnode, bnode, "wing")
	_line("gull.body_only_local=%s" % _fmt(body_only))
	_line("gull.body_only_length_incl_beak_tail=%.3f body_only_width=%.3f body_only_height=%.3f" % [
		body_only.size.z, body_only.size.x, body_only.size.y])
	if body_only.size.z > 0.70:
		_issue("gull body-only length %.3f exceeds 0.70 m keep threshold (needs fx.gd sketch params)" % body_only.size.z)
	if body_only.size.z < 0.40:
		_issue("gull body-only length %.3f below 0.40-0.55 reference" % body_only.size.z)
	# 强制起飞，多帧取局部最大水平展向（翼展）
	for b in birds:
		var bd: Dictionary = b
		bd["state"] = 0
	var ctx := {"day": 0, "rising": true, "sim_seconds": 3600.0, "sim_rate": 1.0,
		"time_source": "sim", "paused": false}
	var max_span := 0.0
	for i in 40:
		flock.update_birds(0.05, 0.5, ctx)
		var fb := _box_local_excluding(bnode, bnode, "")
		max_span = maxf(max_span, fb.size.x)
	_line("gull.flight_wing_span_local=%.3f" % max_span)
	if max_span < 1.10 or max_span > 1.40:
		_issue("gull wingspan %.3f outside 1.10-1.40 reference" % max_span)