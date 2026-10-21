class_name IsleVillagerSpots
extends RefCounted
## P7-V4: authoritative activity-spot + walk-graph data for the lone islander.
##
## No physics colliders exist in this project, so this graph is the single source of
## truth for where the villager may stand.  Indoor/porch nodes are authored in
## cottage-local metres and converted with the real cottage transform; outdoor nodes
## are world metres and take their height from IsleWorld.surface_y() (terrain+mounds).
##
## Node "mode":
##   "flat"    - y is already the walk surface (interior floor / porch / landing)
##   "stair"   - y is a tread top; segment height lerps between tread tops
##   "terrain" - y follows IsleWorld.surface_y(x,z) every frame
##
## Spot kinds: "bed" | "eat" | "sit" | "view".
## A spot anchor is where the villager root sits for the final pose
## (sit = pelvis on seat surface, bed = pelvis on mattress, view = feet on ground).
## approach() returns the standing point in front of / behind the seat (feet anchor);
## the villager tweens its root from that feet anchor to the seat/mattress anchor while
## playing the sit_down / lie_down clip, so seat height never has to be assumed.
##
## Furniture yaw convention (isle_house_props.gd:16): node origin = footprint centre,
## rotation.y = yaw, local +Z is the furniture front.  So front = (sin yaw, 0, cos yaw).
##   "back"  side: stand behind the seat, i.e. anchor - front * dist (dining chairs,
##                 desk chairs, armchair whose front is blocked by a coffee table).
##   "front" side: stand in front of the seat and step backwards onto it (sofa /
##                 wall benches / reading chair whose back is close to the roof slope).

const W := preload("res://scripts/world.gd")

const BODY_R := 0.10   # pathing guard radius: the sofa/coffee-table gap is only 0.45 m
                      # wide, so generous 0.2 m clearance would make the sofa unreachable

const NODE_DEFS := [
    # ---- outdoor (world metres) -------------------------------------------------
    ["front_path_1", 2.20, 6.40, 0.0, "terrain", "outdoor"],
    ["front_path_2", 5.60, 8.60, 0.0, "terrain", "outdoor"],
    ["garden_0", 1.20, 7.10, 0.0, "terrain", "outdoor"],
    ["garden_1", -1.60, 6.55, 0.0, "terrain", "outdoor"],
    ["garden_2", -3.90, 4.90, 0.0, "terrain", "outdoor"],
    ["garden_3", -5.40, 2.60, 0.0, "terrain", "outdoor"],
    ["garden_4", -6.40, 0.00, 0.0, "terrain", "outdoor"],
    ["garden_5", -7.05, -1.90, 0.0, "terrain", "outdoor"],
    ["garden_6", -7.45, -2.95, 0.0, "terrain", "outdoor"],
    ["garden_7", -7.82, -2.95, 0.0, "terrain", "outdoor"],
    ["garden_8", -7.82, -6.20, 0.0, "terrain", "outdoor"],
    ["garden_cross", -6.20, -6.20, 0.0, "terrain", "outdoor"],
    ["tree_view", -8.47, 3.27, 0.0, "terrain", "outdoor"],
    ["swing_view", -8.06, 5.32, 0.0, "terrain", "outdoor"],
    # ---- porch / door (house-local) ---------------------------------------------
    ["lawn", 0.0, 5.95, 0.0, "terrain_local", "porch"],
    ["step3", 0.0, 5.45, 0.00, "flat", "porch"],
    ["step2", 0.0, 5.15, 0.14, "flat", "porch"],
    ["step1", 0.0, 4.85, 0.28, "flat", "porch"],
    ["deck", 0.0, 4.55, 0.42, "flat", "porch"],
    ["deck_out", 0.0, 4.05, 0.42, "flat", "porch"],
    ["porch_bench_front", 1.75, 3.80, 0.42, "flat", "porch"],
    ["door_sill", 0.0, 3.18, 0.55, "flat", "porch"],
    # ---- ground floor (house-local) ---------------------------------------------
    ["room_in", 0.0, 2.70, 0.57, "flat", "floor1"],
    ["doormat", 0.0, 2.30, 0.57, "flat", "floor1"],
    ["hall", 0.0, 1.85, 0.57, "flat", "floor1"],
    # north of the dining table: route along z >= 2.0 so it clears the north chair,
    # then turn south through the east aisle.
    ["east_top", 2.20, 2.05, 0.57, "flat", "floor1"],
    ["shoe_front", 1.15, 2.02, 0.57, "flat", "floor1"],
    # east aisle: z stays > 0.08 so it clears the stair footprint
    ["aisle_e", 2.55, 1.25, 0.57, "flat", "floor1"],
    ["stair_foot", 3.065, 0.16, 0.57, "flat", "floor1"],
    ["mid", 0.00, 0.60, 0.57, "flat", "floor1"],
    ["south_mid", 0.00, -0.60, 0.57, "flat", "floor1"],
    ["dining_s", 1.45, -0.60, 0.57, "flat", "floor1"],
    ["sofa_front", -2.10, 1.60, 0.57, "flat", "floor1"],
    ["armchair_front", -0.20, 1.40, 0.57, "flat", "floor1"],
    ["desk_front", -2.05, 0.30, 0.57, "flat", "floor1"],
    # ---- attic (house-local) -----------------------------------------------------
    ["attic_exit", 0.55, -2.05, 3.181, "flat", "attic"],
    ["attic_1", 0.45, -1.70, 3.181, "flat", "attic"],
    ["attic_2", -0.35, -1.65, 3.181, "flat", "attic"],
    ["attic_3", -0.60, -1.05, 3.181, "flat", "attic"],
    ["attic_4", -0.80, -0.15, 3.181, "flat", "attic"],
    ["bed_stand", -2.00, -0.10, 3.181, "flat", "attic"],
    ["attic_aisle_1", 1.10, -1.68, 3.181, "flat", "attic"],
    ["attic_aisle_2", 0.80, 0.20, 3.181, "flat", "attic"],
    ["reading_front", 0.98, 1.10, 3.181, "flat", "attic"],
    ["attic_north", 1.10, 2.00, 3.181, "flat", "attic"],
    ["attic_window", 1.00, 2.30, 3.181, "flat", "attic"],
    ["attic_plant_view", 2.05, 1.70, 3.181, "flat", "attic"],
    ["attic_desk_front", 0.00, 1.40, 3.181, "flat", "attic"],
]

const EDGE_DEFS := [
    ["front_path_1", "front_path_2"],
    ["front_path_1", "lawn"],
    ["garden_0", "lawn"],
    ["garden_0", "garden_1"],
    ["garden_1", "garden_2"],
    ["garden_2", "garden_3"],
    ["garden_2", "tree_view"],
    ["tree_view", "swing_view"],
    ["garden_3", "garden_4"],
    ["garden_4", "garden_5"],
    ["garden_5", "garden_6"],
    ["garden_6", "garden_7"],
    ["garden_7", "garden_8"],
    ["garden_8", "garden_cross"],
    ["lawn", "step3"],
    ["step3", "step2"],
    ["step2", "step1"],
    ["step1", "deck"],
    ["deck", "deck_out"],
    ["deck", "porch_bench_front"],
    ["deck_out", "door_sill"],
    ["door_sill", "room_in"],
    ["room_in", "doormat"],
    ["doormat", "hall"],
    ["hall", "shoe_front"],
    ["shoe_front", "east_top"],
    ["east_top", "aisle_e"],
    ["hall", "sofa_front"],
    ["hall", "armchair_front"],
    ["mid", "desk_front"],
    ["hall", "mid"],
    ["mid", "south_mid"],
    ["south_mid", "dining_s"],
    ["aisle_e", "stair_foot"],
    ["attic_exit", "attic_1"],
    ["attic_1", "attic_2"],
    ["attic_2", "attic_3"],
    ["attic_3", "attic_4"],
    ["attic_4", "bed_stand"],
    ["attic_1", "attic_aisle_1"],
    ["attic_aisle_1", "attic_aisle_2"],
    ["attic_aisle_2", "reading_front"],
    ["attic_aisle_2", "attic_desk_front"],
    ["attic_aisle_2", "attic_north"],
    ["attic_north", "attic_window"],
    ["attic_north", "attic_plant_view"],
]

## Seats: [id, kind, path_node, local x, local z, floor local y (walk surface),
##         seat surface local y, furniture yaw, approach side ("back"/"front"),
##         approach distance, name]
## Seat surface = furniture base (attic: attic_floor+0.02 = 3.19, floor1: 0.57,
## porch deck: 0.42) + 0.40 for every chair/sofa/reading chair; shoe bench 0.42;
## porch bench top = deck 0.42 + 0.45 + 0.045 = 0.915.
const SEAT_DEFS := [
    ["eat_n", "eat", "shoe_front", 1.45, 1.57, 0.57, 0.97, "PI", "back", 0.55, "餐桌椅·北"],
    ["eat_s", "eat", "dining_s", 1.45, 0.03, 0.57, 0.97, "0", "back", 0.55, "餐桌椅·南"],
    ["eat_w", "eat", "mid", 0.93, 0.80, 0.57, 0.97, "PI/2", "back", 0.55, "餐桌椅·西"],
    ["eat_e", "eat", "aisle_e", 1.97, 0.80, 0.57, 0.97, "-PI/2", "back", 0.55, "餐桌椅·东"],
    ["sofa", "sit", "sofa_front", -2.10, 2.22, 0.57, 0.97, "PI", "front", 0.62, "沙发"],
    ["armchair", "sit", "armchair_front", -0.92, 1.12, 0.57, 0.97, "-PI/2", "back", 0.62, "扶手椅"],
    ["desk_chair", "sit", "desk_front", -2.62, 0.30, 0.57, 0.97, "-PI/2", "back", 0.55, "书桌椅"],
    ["shoe_bench", "sit", "shoe_front", 1.15, 2.60, 0.57, 0.99, "PI", "front", 0.55, "鞋凳"],
    ["porch_bench", "sit", "porch_bench_front", 2.30, 3.80, 0.42, 0.915, "-PI/2", "front", 0.55, "门廊长椅"],
    ["reading_chair", "sit", "reading_front", 1.60, 1.10, 3.181, 3.59, "-PI/2", "front", 0.62, "阅读椅"],
    ["attic_desk_chair", "sit", "attic_desk_front", 0.00, 1.95, 3.181, 3.59, "0", "back", 0.55, "阁楼书桌椅"],
]

## Fixed standing/view spots: [id, node, yaw_local_deg, name]
const VIEW_DEFS := [
    ["view_porch", "deck_out", 180.0, "门廊看海"],
    ["view_attic_window", "attic_window", 180.0, "阁楼窗边"],
    ["view_tree", "tree_view", 0.0, "远望大树"],
    ["view_swing", "swing_view", 0.0, "秋千旁"],
    ["view_garden", "garden_8", 0.0, "花园里"],
    ["view_front", "front_path_1", 0.0, "门前小路"],
    ["idle_living", "hall", 0.0, "起居室"],
]

## Bed geometry (attic): mattress top = furniture base 3.19 + 0.45 = 3.64;
## villager pelvis rests 0.02 above it (3.66).  Bed footprint (yaw -PI/2) is
## x [-2.95, -1.05], z [-1.40, -0.40]; headboard is the +X end (nightstand at x -1.15).
## Sitting on the south edge faces +Z (world local yaw PI); lying down rotates the
## root to local yaw -PI/2 so the model's -Z (head) points at +X (headboard).
const BED := {
    "id": "bed_attic",
    "kind": "bed",
    "node": "bed_stand",
    "anchor_local": Vector3(-2.00, 3.66, -0.90),
    "edge_sit_local": Vector3(-2.00, 3.66, -0.55),
    "sit_yaw_local": PI,
    "approach_local": Vector3(-2.00, 3.181, -0.10),
    "approach_yaw_local": PI,
    "yaw_local": -PI * 0.5,
    "name": "阁楼床",
}

## Obstacle footprints for build-time validation: [name, cx, cz, hx, hz, level]
## level 0 = ground floor + porch, level 1 = attic.  Only same-level comparisons
## are meaningful because furniture at different heights overlaps in plan view.
const OBSTACLES := [
    # ---- floor1 (level 0) --------------------------------------------------------
    ["dining_table", 1.45, 0.80, 0.40, 0.65, 0],
    ["chair_eat_n", 1.45, 1.57, 0.21, 0.22, 0],
    ["chair_eat_s", 1.45, 0.03, 0.21, 0.22, 0],
    ["chair_eat_e", 1.97, 0.80, 0.22, 0.21, 0],
    ["chair_eat_w", 0.93, 0.80, 0.22, 0.21, 0],
    ["sofa", -2.10, 2.22, 0.75, 0.40, 0],
    ["coffee_table", -2.10, 1.12, 0.475, 0.25, 0],
    ["armchair", -0.92, 1.12, 0.38, 0.36, 0],
    ["desk_chair", -2.62, 0.30, 0.22, 0.21, 0],
    ["desk", -3.19, 0.30, 0.30, 0.60, 0],
    ["bookshelf", -3.34, -1.00, 0.15, 0.425, 0],
    ["tall_cupboard", -1.00, -2.60, 0.40, 0.20, 0],
    ["sideboard", 0.20, -2.60, 0.50, 0.20, 0],
    ["shoe_bench", 1.15, 2.60, 0.40, 0.16, 0],
    ["firewood_basket", -2.95, -1.70, 0.26, 0.19, 0],
    ["plant_pot_f1", 3.15, 2.52, 0.21, 0.21, 0],
    ["coat_rack", -1.15, 2.79, 0.15, 0.15, 0],
    ["floor_lamp", -3.12, 2.35, 0.18, 0.18, 0],
    # ---- attic (level 1) ---------------------------------------------------------
    ["bed", -2.00, -0.90, 0.95, 0.50, 1],
    ["nightstand", -1.15, -1.61, 0.20, 0.19, 1],
    ["wardrobe", -0.62, -2.515, 0.50, 0.275, 1],
    ["attic_bookshelf", 0.37, -2.63, 0.425, 0.15, 1],
    ["attic_desk", 0.00, 2.44, 0.60, 0.30, 1],
    ["attic_chair", 0.00, 1.95, 0.21, 0.22, 1],
    ["reading_chair", 1.60, 1.10, 0.36, 0.35, 1],
    ["attic_side_table", 1.60, 0.45, 0.20, 0.20, 1],
    ["attic_plant_pot", 2.55, 2.20, 0.21, 0.21, 1],
    # stair well openings in the attic floor (cottage stair_hole_r1 / r2)
    ["stair_hole_r1", 3.065, -1.455, 0.425, 1.335, 1],
    ["stair_hole_r2", 1.73, -2.365, 0.91, 0.425, 1],
]

static func _yaw_from_local(house_yaw: float, local_yaw: float) -> float:
    return wrapf(house_yaw + local_yaw, -PI, PI)

static func _yaw_to_face(forward: Vector3) -> float:
    return atan2(-forward.x, -forward.z)

static func _parse_yaw(s: String) -> float:
    match s:
        "PI":
            return PI
        "0":
            return 0.0
        "PI/2":
            return PI * 0.5
        "-PI/2":
            return -PI * 0.5
        _:
            return 0.0

static func _front_from_yaw(yaw: float) -> Vector3:
    return Vector3(sin(yaw), 0.0, cos(yaw))

static func _level_of_region(region: String) -> int:
    return 1 if region == "attic" else 0

## Build the walk graph + spots. Returns {"nodes", "adj", "spots", "house_yaw", "root", "obstacles"}.
static func build(cottage: Dictionary) -> Dictionary:
    var root: Node3D = cottage["root"] as Node3D
    var house_yaw := root.rotation.y
    var nodes: Dictionary = {}
    for d in NODE_DEFS:
        var id := String(d[0])
        var lx := float(d[1])
        var lz := float(d[2])
        var y := float(d[3])
        var mode := String(d[4])
        var region := String(d[5])
        var world: Vector3
        if mode == "terrain":
            world = Vector3(lx, W.surface_y(lx, lz), lz)
            y = world.y
        elif mode == "terrain_local":
            var w2 := root.to_global(Vector3(lx, 0.0, lz))
            world = Vector3(w2.x, W.surface_y(w2.x, w2.z), w2.z)
            y = world.y
        else:
            world = root.to_global(Vector3(lx, y, lz))
        nodes[id] = {"id": id, "pos": world, "mode": mode, "region": region, "local": Vector3(lx, y, lz)}
    # ---- stairs from authoritative stair data -----------------------------------
    # cottage treads list = 15 entries: flight A levels 1..7, flight B levels 9..15,
    # then level 16 (the attic arrival tread).  The landing (level 8) is separate.
    var st: Dictionary = cottage.get("stairs", {})
    var treads: Array = st.get("treads", [])
    var stair_ids: Array = []
    for i in range(treads.size()):
        var t: Dictionary = treads[i]
        var c: Vector3 = t.get("center", Vector3.ZERO)
        var top := float(t.get("top", 0.0))
        var sid := "tread_%02d" % (i + 1)
        nodes[sid] = {
            "id": sid,
            "pos": root.to_global(Vector3(c.x, top, c.z)),
            "mode": "stair",
            "region": "stairs",
            "local": Vector3(c.x, top, c.z),
        }
        stair_ids.append(sid)
    var landing_center: Vector3 = st.get("landing_center", Vector3.ZERO)
    var land_top := float(st.get("land_top", 1.86))
    nodes["landing"] = {
        "id": "landing",
        "pos": root.to_global(Vector3(landing_center.x, land_top, landing_center.z)),
        "mode": "flat",
        "region": "stairs",
        "local": Vector3(landing_center.x, land_top, landing_center.z),
    }
    nodes["landing"]["local"] = Vector3(landing_center.x, land_top, landing_center.z)
    # ---- adjacency ---------------------------------------------------------------
    var adj: Dictionary = {}
    for e in EDGE_DEFS:
        _add_edge(adj, String(e[0]), String(e[1]))
    # stair chain: foot -> A treads 1..7 -> landing (level 8) -> B treads 9..15
    # (tread_08..tread_14) -> arrival tread 16 (tread_15) -> attic_exit
    if stair_ids.size() >= 15:
        _add_edge(adj, "stair_foot", String(stair_ids[0]))
        for i in range(0, 6):
            _add_edge(adj, String(stair_ids[i]), String(stair_ids[i + 1]))
        _add_edge(adj, String(stair_ids[6]), "landing")
        _add_edge(adj, "landing", String(stair_ids[7]))
        for i in range(7, 14):
            _add_edge(adj, String(stair_ids[i]), String(stair_ids[i + 1]))
        _add_edge(adj, String(stair_ids[14]), "attic_exit")
    # ---- spots -------------------------------------------------------------------
    var spots: Dictionary = {}
    for s in SEAT_DEFS:
        var sid := String(s[0])
        var node_id := String(s[2])
        var lx := float(s[3])
        var lz := float(s[4])
        var floor_y := float(s[5])
        var seat_y := float(s[6])
        var seat_yaw := _parse_yaw(String(s[7]))
        var side := String(s[8])
        var dist := float(s[9])
        var front_local := _front_from_yaw(seat_yaw)
        var sign := -1.0 if side == "back" else 1.0
        var ap_local := Vector3(lx + front_local.x * sign * dist, floor_y, lz + front_local.z * sign * dist)
        var anchor_world := root.to_global(Vector3(lx, seat_y, lz))
        var ap_world := root.to_global(ap_local)
        var front_world := (root.global_transform.basis * front_local).normalized()
        var front_flat := Vector3(front_world.x, 0.0, front_world.z).normalized()
        var yaw_w := _yaw_to_face(front_flat)
        spots[sid] = {
            "id": sid,
            "kind": String(s[1]),
            "anchor": anchor_world,
            "yaw": yaw_w,
            "approach": ap_world,
            "approach_local": ap_local,
            "approach_node": node_id,
            "approach_yaw": yaw_w,
            "seat_h": seat_y - floor_y,
            "level": _level_of_region(String(nodes[node_id]["region"])),
            "name": String(s[10]),
            "region": String(nodes[node_id]["region"]),
            "reserved": false,
        }
    for v in VIEW_DEFS:
        var vid := String(v[0])
        var node_id := String(v[1])
        var node: Dictionary = nodes[node_id]
        var pos: Vector3 = node["pos"]
        var yaw_w := 0.0
        var patch_target := Vector3.ZERO
        var has_target := true
        match vid:
            "view_tree":
                patch_target = Vector3(-10.90, pos.y, 4.20)
            "view_swing":
                patch_target = Vector3(-9.40, pos.y, 6.20)
            "view_garden":
                patch_target = Vector3(-7.00, pos.y, -5.80)
            "view_front":
                patch_target = Vector3(16.0, pos.y, 13.0)
            _:
                has_target = false
        if has_target:
            var fwd := (patch_target - pos)
            fwd.y = 0.0
            if fwd.length() > 0.001:
                yaw_w = _yaw_to_face(fwd.normalized())
        else:
            yaw_w = _yaw_from_local(house_yaw, deg_to_rad(float(v[2])))
        spots[vid] = {
            "id": vid,
            "kind": "view",
            "anchor": pos,
            "yaw": yaw_w,
            "approach": pos,
            "approach_local": node["local"],
            "approach_node": node_id,
            "approach_yaw": yaw_w,
            "seat_h": 0.0,
            "level": _level_of_region(String(node["region"])),
            "name": String(v[3]),
            "region": String(node["region"]),
            "reserved": false,
        }
    var bed_anchor: Vector3 = root.to_global(BED["anchor_local"])
    var bed_edge: Vector3 = root.to_global(BED["edge_sit_local"])
    var bed_ap: Vector3 = root.to_global(BED["approach_local"])
    spots[BED["id"]] = {
        "id": BED["id"],
        "kind": "bed",
        "anchor": bed_anchor,
        "yaw": _yaw_from_local(house_yaw, float(BED["yaw_local"])),
        "sit_yaw": _yaw_from_local(house_yaw, float(BED["sit_yaw_local"])),
        "anchor_edge": bed_edge,
        "approach": bed_ap,
        "approach_local": BED["approach_local"],
        "approach_node": String(BED["node"]),
        "approach_yaw": _yaw_from_local(house_yaw, float(BED["approach_yaw_local"])),
        "seat_h": 0.46,
        "level": 1,
        "name": String(BED["name"]),
        "region": "attic",
        "reserved": false,
    }
    return {
        "nodes": nodes,
        "adj": adj,
        "spots": spots,
        "house_yaw": house_yaw,
        "root": root,
        "obstacles": OBSTACLES,
    }

## Build-time geometry sanity: returns human readable issues (empty = clean).
static func validate(graph: Dictionary) -> Array:
    var issues: Array = []
    var nodes: Dictionary = graph["nodes"]
    var adj: Dictionary = graph["adj"]
    var root: Node3D = graph["root"]
    var seen: Dictionary = {}
    # 1) nodes themselves must not be inside same-level obstacles (except stair treads)
    for id in nodes.keys():
        var n: Dictionary = nodes[id]
        if String(n["mode"]) == "stair" or String(n["region"]) == "stairs":
            continue
        var lp: Vector3 = n["local"]
        var lv := _level_of_region(String(n["region"]))
        var hit := _point_blocked(lp.x, lp.z, 0.0, lv)
        if hit != "":
            issues.append("node %s inside %s" % [id, hit])
    # 2) edges: same-level obstacle sweep + region continuity
    for a in adj.keys():
        for b in (adj[a] as PackedStringArray):
            var sa := String(a)
            var sb := String(b)
            var key: String = sa + "|" + sb if sa < sb else sb + "|" + sa
            if seen.has(key):
                continue
            seen[key] = true
            var issue := _edge_issue(nodes, sa, sb, root)
            if issue != "":
                issues.append(issue)
    # 3) spot approach points must be clear, approach path from its node clear
    for sid in graph["spots"].keys():
        var sp: Dictionary = graph["spots"][sid]
        var ap_local: Vector3 = sp["approach_local"]
        var lv := int(sp["level"])
        var hit := _point_blocked(ap_local.x, ap_local.z, 0.0, lv)
        if hit != "":
            issues.append("spot %s approach inside %s" % [sid, hit])
        var node_id := String(sp["approach_node"])
        if nodes.has(node_id):
            var node_local: Vector3 = nodes[node_id]["local"]
            var seg := _segment_issue(Vector3(node_local.x, ap_local.y, node_local.z), ap_local, lv)
            if seg != "":
                issues.append("spot %s approach path from %s crosses %s" % [sid, node_id, seg])
    return issues

static func _pair_allowed(ra: String, rb: String) -> bool:
    if ra == rb:
        return true
    var pair := [ra, rb]
    pair.sort()
    var joined := String(pair[0]) + "|" + String(pair[1])
    return joined in [
        "attic|stairs", "floor1|stairs", "floor1|porch", "outdoor|porch", "attic|floor1", "outdoor|outdoor",
    ]

static func _edge_issue(nodes: Dictionary, a: String, b: String, _root: Node3D) -> String:
    var na: Dictionary = nodes[a]
    var nb: Dictionary = nodes[b]
    var la: Vector3 = na["local"]
    var lb: Vector3 = nb["local"]
    var ra := String(na["region"])
    var rb := String(nb["region"])
    if not _pair_allowed(ra, rb):
        return "edge %s-%s crosses regions %s/%s" % [a, b, ra, rb]
    # stair tread edges live inside the stair shaft; the stair geometry itself is
    # guaranteed by construction, and the attic-floor hole obstacles are handled by
    # the stair-mode exemption above.
    if ra == "stairs" or rb == "stairs":
        return ""
    if ra == "outdoor" or rb == "outdoor":
        return ""
    var lv := 1 if (ra == "attic" and rb == "attic") else 0
    if ra == "attic" and rb != "attic":
        lv = 1
    var issue := _segment_issue(la, lb, lv)
    if issue != "":
        return "edge %s-%s crosses %s" % [a, b, issue]
    return ""

static func _point_blocked(x: float, z: float, pad: float, level: int = 0) -> String:
    for o in OBSTACLES:
        if int(o[5]) != level:
            continue
        var ox := float(o[1])
        var oz := float(o[2])
        var hx := float(o[3]) + BODY_R + pad
        var hz := float(o[4]) + BODY_R + pad
        if absf(x - ox) < hx and absf(z - oz) < hz:
            return String(o[0])
    return ""

static func _segment_issue(a: Vector3, b: Vector3, level: int = 0) -> String:
    # sample the segment densely; enough for authored short edges (< 1.5 m)
    var n := maxi(4, int(ceil(a.distance_to(b) / 0.08)))
    for i in range(n + 1):
        var t := float(i) / float(n)
        var p := a.lerp(b, t)
        var hit := _point_blocked(p.x, p.z, 0.0, level)
        if hit != "":
            return hit
    return ""

static func _add_edge(adj: Dictionary, a: String, b: String) -> void:
    if not adj.has(a):
        adj[a] = PackedStringArray()
    if not adj.has(b):
        adj[b] = PackedStringArray()
    var la: PackedStringArray = adj[a]
    if not la.has(b):
        la.append(b)
        adj[a] = la
    var lb: PackedStringArray = adj[b]
    if not lb.has(a):
        lb.append(a)
        adj[b] = lb

## Shortest node path (A* over node distance). Empty = unreachable.
static func find_path(graph: Dictionary, from_id: String, to_id: String) -> PackedStringArray:
    var nodes: Dictionary = graph["nodes"]
    var adj: Dictionary = graph["adj"]
    if not nodes.has(from_id) or not nodes.has(to_id):
        return PackedStringArray()
    if from_id == to_id:
        return PackedStringArray([from_id])
    var open: Array = [from_id]
    var came: Dictionary = {}
    var gscore: Dictionary = {from_id: 0.0}
    var fscore: Dictionary = {from_id: _dist(nodes, from_id, to_id)}
    while not open.is_empty():
        var best_i := 0
        for i in range(1, open.size()):
            if float(fscore.get(open[i], 1e20)) < float(fscore.get(open[best_i], 1e20)):
                best_i = i
        var cur: String = String(open[best_i])
        if cur == to_id:
            var out: PackedStringArray = PackedStringArray()
            var c := cur
            while true:
                out.append(c)
                if not came.has(c):
                    break
                c = String(came[c])
            out.reverse()
            return out
        open.remove_at(best_i)
        for nb in (adj.get(cur, PackedStringArray()) as PackedStringArray):
            var tentative := float(gscore.get(cur, 1e20)) + _dist(nodes, cur, nb)
            if tentative < float(gscore.get(nb, 1e20)):
                came[nb] = cur
                gscore[nb] = tentative
                fscore[nb] = tentative + _dist(nodes, nb, to_id)
                if not open.has(nb):
                    open.append(nb)
    return PackedStringArray()

static func _dist(nodes: Dictionary, a: String, b: String) -> float:
    var pa: Vector3 = nodes[a]["pos"]
    var pb: Vector3 = nodes[b]["pos"]
    return Vector2(pa.x - pb.x, pa.z - pb.z).length() + absf(pa.y - pb.y) * 0.5

static func nearest_node(graph: Dictionary, pos: Vector3, region_filter: String = "") -> String:
    var nodes: Dictionary = graph["nodes"]
    var best := ""
    var best_d := 1e20
    for id in nodes.keys():
        var n: Dictionary = nodes[id]
        if region_filter != "" and String(n["region"]) != region_filter:
            continue
        var p: Vector3 = n["pos"]
        var d := Vector2(p.x - pos.x, p.z - pos.z).length() + absf(p.y - pos.y) * 2.0
        if d < best_d:
            best_d = d
            best = String(id)
    return best
