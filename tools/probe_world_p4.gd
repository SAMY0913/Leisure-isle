extends SceneTree
## P4 runtime probe for scripts/world.gd: lighthouse / rocks / flowers / routes / perches.
## Run: Godot ... --headless --path D:/休闲小岛幻境/游戏工程 --script res://tools/probe_world_p4.gd

const OLD_WINDMILL_H := 12.1839389801025
const TARGET_H := 18.2759084701538

var fails: Array = []

func _add_fail(msg: String) -> void:
    fails.append(msg)

func _check(cond: bool, msg: String) -> void:
    if not cond:
        _add_fail(msg)

func _point_seg_dist(px: float, pz: float, a: Vector2, b: Vector2) -> float:
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

func _dist2_xz(p: Vector3, o: Vector3) -> float:
    return sqrt((p.x - o.x) * (p.x - o.x) + (p.z - o.z) * (p.z - o.z))

# P5 contract (docs/P5_INTERFACES.md section 4): every sail route starts and ends at
# the dock anchor returned as sail_dock_pos, which the design places 3.41 m beyond
# dock_end (dock length 11.0 m, anchor at dock_start + 14.4 m along the pier axis).
# Skip that anchor zone here so the P4 >=5 m dock clearance still measures the
# open-water course instead of the mandated start/end berth. Modified for P5 only;
# all other P4 assertions are unchanged.
func _near_sail_anchor(p: Vector3, anchor: Vector3) -> bool:
    if anchor == Vector3.ZERO:
        return false
    return _dist2_xz(p, anchor) < 8.0

func _collect_aabb(node: Node, xf: Transform3D, acc: Array) -> void:
    var here := xf
    if node is Node3D:
        here = xf * (node as Node3D).transform
    if node is MeshInstance3D:
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

func _mm_tris(mmi: MultiMeshInstance3D) -> int:
    if mmi.multimesh == null or mmi.multimesh.mesh == null:
        return 0
    var mesh := mmi.multimesh.mesh
    if mesh.get_surface_count() == 0:
        return 0
    var arr := mesh.surface_get_arrays(0)
    var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
    return int(verts.size() / 3)

func _mesh_tris(mi: MeshInstance3D) -> int:
    if mi.mesh == null or mi.mesh.get_surface_count() == 0:
        return 0
    var arr := mi.mesh.surface_get_arrays(0)
    var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
    return int(verts.size() / 3)

func _run() -> void:
    var W := load("res://scripts/world.gd")
    var parent := Node3D.new()
    parent.name = "ProbeParent"
    get_root().add_child(parent)
    var t0 := Time.get_ticks_msec()
    var d: Dictionary = W.build(parent)
    var build_ms := Time.get_ticks_msec() - t0

    # ============================================================== lighthouse
    var lh: Node3D = d.get("lighthouse")
    _check(lh != null, "lighthouse node missing from build dict")
    var measured := 0.0
    if lh != null:
        var ab := _subtree_aabb(lh)
        measured = ab.size.y
        var ratio := measured / OLD_WINDMILL_H
        var target_err := absf(measured - TARGET_H) / TARGET_H * 100.0
        var ratio_err := absf(ratio - 1.5) / 1.5 * 100.0
        print("[LIGHTHOUSE] old_windmill_h=%.6f target_h=%.6f measured_h=%.6f ratio=%.6f target_err_pct=%.4f ratio_err_pct=%.4f" % [
            OLD_WINDMILL_H, TARGET_H, measured, ratio, target_err, ratio_err])
        _check(target_err < 2.0, "lighthouse height off target by >2%% (err=%.3f)" % target_err)
        var platform: Node3D = d.get("lighthouse_platform")
        _check(platform != null, "lighthouse_platform missing")
        var lamp: Node3D = d.get("lighthouse_lamp")
        _check(lamp != null, "lighthouse_lamp missing")
        var beam: Vector3 = d.get("lighthouse_beam_origin")
        var axis: Vector3 = d.get("lighthouse_rotation_axis")
        var lperches: Array = d.get("lighthouse_perches")
        var lmat: ShaderMaterial = d.get("lighthouse_lamp_mat")
        var lhalo = d.get("lighthouse_lamp_halo")
        var llight: Dictionary = d.get("lighthouse_light")
        _check(lperches != null and lperches.size() == 4, "lighthouse_perches != 4")
        _check(lmat != null, "lighthouse_lamp_mat missing")
        _check(lhalo != null, "lighthouse_lamp_halo missing")
        _check(axis.distance_to(Vector3.UP) < 0.001, "lighthouse_rotation_axis != UP")
        _check(lh.find_child("Lamp", true, false) != null, "rotating Lamp node missing inside lighthouse")
        _check(lh.find_child("GalleryPlatform", true, false) != null, "GalleryPlatform node missing")
        _check(beam.y > measured * 0.7, "beam origin unexpectedly low")
        _check("kind" in llight and str(llight["kind"]) == "lighthouse", "lighthouse_light kind wrong")
        print("[LIGHTHOUSE] platform=GalleryPlatform lamp=Lamp beam_origin=(%.2f, %.2f, %.2f) axis=%s perches=%d lamp_mat=%s halo_nodes=%d light_range=%.1f height_key=%.6f" % [
            beam.x, beam.y, beam.z, str(axis), lperches.size(), str(lmat != null), 1,
            float(llight.get("range", 0.0)), float(d.get("lighthouse_height"))])
        _check(absf(float(d.get("lighthouse_height")) - TARGET_H) < 0.001, "lighthouse_height key mismatch")
        _check(absf(float(d.get("windmill_old_height", 0.0)) - OLD_WINDMILL_H) < 1e-9, "windmill_old_height key mismatch")
    # old props must be gone
    _check(parent.find_child("Windmill", true, false) == null, "old Windmill node still present")
    _check(parent.find_child("Boat", true, false) == null, "old small rowboat node still present")
    _check(parent.find_child("Sailboat", true, false) != null, "big Sailboat node missing")
    for gone in ["windmill_blades", "windmill_axis", "boat", "boat_base", "boat_heading"]:
        _check(not d.has(gone), "removed key still present: " + gone)

    # light sources: 3 lamps + dock + lighthouse = 5, shader budget is 8
    var ls: Array = d.get("light_sources")
    _check(ls.size() <= 8, "light_sources exceeds shader budget 8")
    var has_lh_light := false
    for L in ls:
        if typeof(L) == TYPE_DICTIONARY and str((L as Dictionary).get("kind", "")) == "lighthouse":
            has_lh_light = true
    _check(has_lh_light, "lighthouse light not in light_sources")

    # =================================================================== rocks
    var root_island: Node3D = d.get("root")
    var routes: Array = d.get("sail_routes")
    var rs: Dictionary = d.get("rock_stats")
    var fams: Array = rs["families"]
    var ntris: Array = rs["near_tris"]
    var ftris: Array = rs["far_tris"]
    var min_route_clear := float(rs["min_route_clearance"])
    var closest_rock: Vector3 = rs["closest_rock"]
    var near_ok := true
    var far_ok := true
    for k in range(fams.size()):
        if int(ntris[k]) != 320:
            near_ok = false
        if int(ftris[k]) != 80:
            far_ok = false
    _check(fams.size() >= 6, "fewer than 6 rock families")
    _check(near_ok, "rock near LOD not 320 tris for every family")
    _check(far_ok, "rock far LOD not 80 tris for every family")
    _check(int(rs["near_instances"]) >= 60, "too few near rock instances")
    _check(min_route_clear >= 3.0, "rock instances closer than 3 m to a sail route")
    print("[ROCKS] families=%d names=%s near_tris=%s far_tris=%s near_instances=%d far_instances=%d min_route_clearance_m=%.2f at=%s smooth=%s" % [
        fams.size(), str(fams), str(ntris), str(ftris), int(rs["near_instances"]),
        int(rs["far_instances"]), min_route_clear, str(closest_rock), str(rs["smooth"])])
    # near/far LOD split present and disjoint
    var vis_ok := true
    for node in root_island.get_children():
        if node is MultiMeshInstance3D and str(node.name).begins_with("Rocks_") and str(node.name).ends_with("_Near"):
            if (node as MultiMeshInstance3D).visibility_range_end < 1.0:
                vis_ok = false
    _check(vis_ok, "near rock LOD not distance-limited")
    print("[ROCKS] per_family=%s near_nodes=%d far_nodes=%d" % [str(rs["per_family"]), _count_rocks(root_island, "_Near"), _count_rocks(root_island, "_Far")])

    # ================================================================= flowers
    var fs: Dictionary = d.get("flower_stats")
    var sp: Dictionary = fs["species"]
    var species_ok := 0
    var sp_str := ""
    for name in sp.keys():
        sp_str += "%s:%d " % [str(name), int(sp[name])]
        if int(sp[name]) > 0:
            species_ok += 1
    _check(species_ok >= 3, "fewer than 3 flower species placed")
    _check(int(fs["total"]) >= 100, "too few flowers")
    var stem_tris := {}
    for node in root_island.get_children():
        if node is MultiMeshInstance3D and str(node.name).begins_with("FlowerStems_"):
            stem_tris[str(node.name).substr(12)] = _mm_tris(node as MultiMeshInstance3D)
    print("[FLOWERS] species_placed=%d detail=%s total=%d clusters=%d head_meshes=%d stem_tri=%s" % [
        species_ok, sp_str.strip_edges(), int(fs["total"]), int(fs["clusters"]),
        int(fs["head_meshes"]), str(stem_tris)])

    # ================================================================== routes
    _check(routes.size() >= 8, "fewer than 8 sail routes")
    var dock_a := IsleMath.dock_start()
    var dock_b := IsleMath.dock_end()
    var dock2d_a := Vector2(dock_a.x, dock_a.z)
    var dock2d_b := Vector2(dock_b.x, dock_b.z)
    var anchor_v: Vector3 = d.get("sail_dock_pos", Vector3.ZERO)
    var route_str := ""
    var midpoints: Array = []
    for r in routes:
        var rn := str(r["name"])
        var o: PackedVector3Array = r["out"]
        var b: PackedVector3Array = r["back"]
        var min_off := 1.0e20
        var min_dock := 1.0e20
        var y_ok := true
        for p in o:
            if absf(p.y) > 0.0001:
                y_ok = false
            var rr := sqrt(p.x * p.x + p.z * p.z)
            var off := rr - IsleMath.coast_radius(atan2(p.z, p.x))
            if off < min_off:
                min_off = off
            if not _near_sail_anchor(p, anchor_v):
                var dd := _point_seg_dist(p.x, p.z, dock2d_a, dock2d_b)
                if dd < min_dock:
                    min_dock = dd
        for p in b:
            if absf(p.y) > 0.0001:
                y_ok = false
            var rr2 := sqrt(p.x * p.x + p.z * p.z)
            var off2 := rr2 - IsleMath.coast_radius(atan2(p.z, p.x))
            if off2 < min_off:
                min_off = off2
            if not _near_sail_anchor(p, anchor_v):
                var dd2 := _point_seg_dist(p.x, p.z, dock2d_a, dock2d_b)
                if dd2 < min_dock:
                    min_dock = dd2
        var diff := 0
        var n := mini(o.size() - 1, b.size() - 1)
        for i in range(n):
            var to := (o[i + 1] - o[i]).normalized()
            var tb := (b[i + 1] - b[i]).normalized()
            var ang := rad_to_deg(acos(clampf(to.dot(tb), -1.0, 1.0)))
            if ang > 20.0:
                diff += 1
        var mid := (o[o.size() / 2] + b[b.size() / 2]) * 0.5
        midpoints.append(mid)
        _check(o.size() >= 5 and b.size() >= 5, "route too short: " + rn)
        _check(min_off >= 6.0, "route %.2f m offshore (<6): %s" % [min_off, rn])
        _check(min_dock >= 5.0, "route %.2f m from dock: %s" % [min_dock, rn])
        _check(diff >= 3, "route out/back headings too similar (%d): %s" % [diff, rn])
        _check(y_ok, "route point not on y=0: " + rn)
        route_str += "\n[ROUTES]   %s out=%d back=%d wait=%.1f min_offshore=%.2f dock_clear=%.2f outback_dir_diff=%d/%d" % [
            rn, o.size(), b.size(), float(r["wait"]), min_off, min_dock, diff, n]
    # routes must differ from each other (midpoint separation)
    var min_pair := 1.0e20
    for i in range(midpoints.size()):
        for j in range(i + 1, midpoints.size()):
            var dmp: float = (midpoints[i] as Vector3).distance_to(midpoints[j] as Vector3)
            if dmp < min_pair:
                min_pair = dmp
    _check(min_pair > 2.0, "two sail routes nearly identical (midpoint %.2f m)" % min_pair)
    print("[ROUTES] count=%d min_pairwise_midpoint=%.2f%s" % [routes.size(), min_pair, route_str])
    _check(d.get("sailboat_path") != null and (d.get("sailboat_path") as PackedVector3Array).size() > 0, "sailboat_path missing")
    var sb: Node3D = d.get("sailboat")
    _check(sb != null and sb.get_meta("route_count", 0) == routes.size(), "sailboat route_count meta mismatch")

    # ================================================================= perches
    var perches: Array = d.get("perches")
    var kinds := {}
    var ids := {}
    var fields_ok := true
    var dup_id := false
    for p in perches:
        if typeof(p) != TYPE_DICTIONARY:
            fields_ok = false
            continue
        var pd := p as Dictionary
        for k in ["id", "pos", "facing", "radius", "kind"]:
            if not pd.has(k):
                fields_ok = false
        if pd.has("id"):
            var pid := str(pd["id"])
            if ids.has(pid):
                dup_id = true
            ids[pid] = true
        var kk := str(pd.get("kind", "?"))
        kinds[kk] = int(kinds.get(kk, 0)) + 1
    _check(perches.size() >= 20, "fewer than 20 perches")
    _check(fields_ok, "perch dictionary missing required fields")
    _check(not dup_id, "duplicate perch ids")
    for need in ["tree_branch", "roof", "eave", "lighthouse_platform", "dock", "garden_post"]:
        _check(kinds.has(need), "missing perch kind: " + need)
    print("[PERCH] total=%d kinds=%s ids_unique=%s first=%s" % [
        perches.size(), str(kinds), str(not dup_id), str((perches[0] as Dictionary)["id"])])

    # all other legacy feature keys still present
    for key in ["root", "terrain", "perches", "dock_end", "dock_perch", "big_tree", "big_tree_canopy",
            "lamps", "lamp_mats", "lamp_halos", "light_sources", "swing", "swing_axis",
            "sailboat", "sailboat_path", "sailboat_speed", "grass_count", "sail_routes",
            "lighthouse", "lighthouse_height", "lighthouse_lamp", "lighthouse_beam_origin",
            "lighthouse_platform", "lighthouse_perches", "lighthouse_light", "lighthouse_lamp_mat",
            "lighthouse_lamp_halo", "lighthouse_rotation_axis", "rock_stats", "flower_stats"]:
        _check(d.has(key), "missing return key: " + key)

    print("[WORLD] return_keys=%d grass=%d docks=%s lights=%d routes=%d build_ms=%d" % [d.size(), int(d.get("grass_count")), str(d.get("dock_perch") != null), (d.get("light_sources") as Array).size(), (d.get("sail_routes") as Array).size(), build_ms])
    if fails.is_empty():
        print("[PROBE] RESULT=PASS fails=0")
        quit(0)
    else:
        print("[PROBE] RESULT=FAIL fails=%d" % fails.size())
        for f in fails:
            print("[FAIL] " + str(f))
        quit(3)

func _count_rocks(root: Node3D, suffix: String) -> int:
    var c := 0
    for node in root.get_children():
        if node is MultiMeshInstance3D and str(node.name).begins_with("Rocks_") and str(node.name).ends_with(suffix):
            c += 1
    return c

func _init() -> void:
    if get_root() == null:
        _run.call_deferred()
    else:
        _run()
