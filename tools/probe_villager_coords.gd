extends SceneTree
## P7-V4 T1: dump authoritative world coordinates for the villager's activity spots,
## door/porch route, stair treads and outdoor wander nodes (house-local -> world).
## Run: Godot_v4.7.2-stable_win64_console.exe --headless --path PROJ --script res://tools/probe_villager_coords.gd

const M := preload("res://scripts/isle_math.gd")
const W := preload("res://scripts/world.gd")

var _main: Node = null
var _world: Dictionary = {}
var _cottage: Dictionary = {}
var _root: Node3D = null
var _fy := 0.55
var _fl := 0.57
var _attic_floor := 3.17
var _attic_top := 3.181
var _ground_w := 0.0

func _initialize() -> void:
    await process_frame
    var packed: PackedScene = load("res://isle.tscn") as PackedScene
    if packed == null:
        print("[VCOORD] FAIL cannot load isle.tscn")
        quit(1)
        return
    _main = packed.instantiate()
    get_root().add_child(_main)
    await process_frame
    await process_frame
    var menu = _main.get("_menu")
    if menu != null and menu.has_method("instant_finish"):
        menu.call("instant_finish")
    _main.set("_mode", 1)
    _main.set("_time_source", "sim")
    _main.set("_realtime", false)
    _main.set("_started", true)
    _main.set("_paused", true)
    _main.set("_auto_orbit", false)
    _main.set("_blending", "")
    _main.set("_sim_seconds", 0.0)
    await process_frame
    if _main.has_method("_set_time_of_day"):
        _main.call("_set_time_of_day", 740.0)
    if _main.has_method("_update_lighting"):
        _main.call("_update_lighting")
    await process_frame
    _world = _main.get("_world")
    _cottage = _main.get("_cottage")
    _root = _cottage["root"] as Node3D
    var ctx: Dictionary = _root.get_meta("cottage_ctx", {})
    if not ctx.is_empty():
        _fy = float(ctx.get("fy", _fy))
    _fl = _fy + 0.02
    _attic_floor = float(ctx.get("attic_floor", _attic_floor))
    _attic_top = _attic_floor + 0.011
    _ground_w = _root.position.y
    _dump()
    quit(0)

func _a(p: Vector3) -> Array:
    return [snappedf(p.x, 0.0001), snappedf(p.y, 0.0001), snappedf(p.z, 0.0001)]

func _wl(local: Vector3) -> Vector3:
    return _root.to_global(local)

func _spot(id: String, local: Vector3, yaw: float, seat_h: float, approach_off: Vector3, extra: Dictionary = {}) -> Dictionary:
    var ap_local := local + approach_off
    var d := {
        "id": id,
        "local": _a(local),
        "yaw_local": snappedf(yaw, 0.0001),
        "world": _a(_wl(local)),
        "approach_local": _a(ap_local),
        "approach_world": _a(_wl(ap_local)),
        "seat_h": snappedf(seat_h, 0.0001),
    }
    d.merge(extra)
    return d

func _outdoor(id: String, xz: Vector2, kind: String = "ground", y_override: float = -1.0) -> Dictionary:
    var y := W.surface_y(xz.x, xz.y)
    if y_override >= 0.0:
        y = y_override
    var a := atan2(xz.y, xz.x)
    var r := xz.length()
    var cr := M.coast_radius(a)
    var slope := 0.0
    var e := 0.30
    var hs := [W.surface_y(xz.x - e, xz.y), W.surface_y(xz.x + e, xz.y), W.surface_y(xz.x, xz.y - e), W.surface_y(xz.x, xz.y + e)]
    for h in hs:
        slope = maxf(slope, absf(float(h) - y) / e)
    return {
        "id": id,
        "kind": kind,
        "world": _a(Vector3(xz.x, y, xz.y)),
        "ground_y": snappedf(W.surface_y(xz.x, xz.y), 0.0001),
        "slope": snappedf(slope, 0.001),
        "trail_clearance": snappedf(W.trail_clearance(xz.x, xz.y), 0.001),
        "coast_margin": snappedf(cr - r, 0.001),
    }

func _dump() -> void:
    var data := {}
    data["house"] = {
        "root_pos": _a(_root.position),
        "root_yaw": snappedf(_root.rotation.y, 0.0001),
        "fy": snappedf(_fy, 0.0001),
        "fl": snappedf(_fl, 0.0001),
        "attic_floor": snappedf(_attic_floor, 0.0001),
        "attic_top": snappedf(_attic_top, 0.0001),
        "ground_world_y": snappedf(_ground_w, 0.0001),
        "root_scale": _a(_root.scale),
    }
    # ---- door / porch route (house local) ----
    var front_w := Vector3(0.0, 0.0, 5.75)
    var front_ground_local := W.surface_y(_wl(front_w).x, _wl(front_w).z) - _ground_w
    data["door"] = {
        "deck_out": _a(_wl(Vector3(0.0, 0.42, 3.62))),
        "threshold": _a(_wl(Vector3(0.0, 0.55, 3.10))),
        "inside": _a(_wl(Vector3(0.0, _fl, 2.72))),
        "doormat": _a(_wl(Vector3(0.0, _fl, 2.30))),
        "step1": _a(_wl(Vector3(0.0, 0.28, 4.85))),
        "step2": _a(_wl(Vector3(0.0, 0.14, 5.15))),
        "front_ground_local_y": snappedf(front_ground_local, 0.0001),
        "front_ground_world_y": snappedf(_ground_w + front_ground_local, 0.0001),
        "front_node": _a(_wl(Vector3(0.0, front_ground_local, 5.55))),
    }
    var dp: Node3D = _cottage.get("door_pivot", null) as Node3D
    if dp != null:
        data["door"]["door_pivot_pos"] = _a(dp.position)
    # ---- stairs (from cottage stair_data) ----
    var st: Dictionary = _cottage.get("stairs", {})
    var treads: Array = []
    for t in (st.get("treads", []) as Array):
        var c: Vector3 = t.get("center", Vector3.ZERO)
        var top := float(t.get("top", 0.0))
        treads.append({
            "level": int(t.get("level", 0)),
            "top": snappedf(top, 0.0001),
            "local": _a(Vector3(c.x, top, c.z)),
            "world": _a(_wl(Vector3(c.x, top, c.z))),
            "size": _a(t.get("size", Vector3.ZERO)),
        })
    var landing: Vector3 = st.get("landing_center", Vector3.ZERO)
    data["stairs"] = {
        "risers": int(st.get("risers", 0)),
        "rise": snappedf(float(st.get("rise", 0.0)), 0.00001),
        "tread": snappedf(float(st.get("tread", 0.0)), 0.0001),
        "width": snappedf(float(st.get("width", 0.0)), 0.0001),
        "land_top": snappedf(float(st.get("land_top", 0.0)), 0.0001),
        "attic_floor": snappedf(float(st.get("attic_floor", 0.0)), 0.0001),
        "headroom_min": snappedf(float(st.get("headroom_min", -1.0)), 0.001),
        "treads": treads,
        "landing": _a(_wl(Vector3(landing.x, float(st.get("land_top", 0.0)), landing.z))),
        "foot": _a(_wl(Vector3(3.065, _fl, 0.06))),
        "attic_exit": _a(_wl(Vector3(0.55, _attic_top, -2.365))),
        "attic_exit_in": _a(_wl(Vector3(0.25, _attic_top, -2.20))),
    }
    # ---- one-floor seats / eat / rest spots ----
    var seats := []
    seats.append(_spot("eat_chair_n", Vector3(1.45, _fl, 1.57), PI, 0.40, Vector3(0.0, 0.0, 0.55), {"kind": "eat"}))
    seats.append(_spot("eat_chair_s", Vector3(1.45, _fl, 0.03), 0.0, 0.40, Vector3(0.0, 0.0, -0.55), {"kind": "eat"}))
    seats.append(_spot("eat_chair_w", Vector3(0.93, _fl, 0.80), PI * 0.5, 0.40, Vector3(-0.55, 0.0, 0.0), {"kind": "eat"}))
    seats.append(_spot("eat_chair_e", Vector3(1.97, _fl, 0.80), -PI * 0.5, 0.40, Vector3(0.55, 0.0, 0.0), {"kind": "eat"}))
    seats.append(_spot("sofa", Vector3(-2.10, _fl, 2.22), PI, 0.40, Vector3(0.0, 0.0, 0.60), {"kind": "sit"}))
    seats.append(_spot("armchair", Vector3(-0.92, _fl, 1.12), -PI * 0.5, 0.40, Vector3(-0.60, 0.0, 0.0), {"kind": "sit"}))
    seats.append(_spot("desk_chair", Vector3(-2.62, _fl, 0.30), -PI * 0.5, 0.40, Vector3(0.0, 0.0, 0.58), {"kind": "sit"}))
    seats.append(_spot("shoe_bench", Vector3(1.15, _fl, 2.60), PI, 0.42, Vector3(0.0, 0.0, 0.55), {"kind": "sit"}))
    seats.append(_spot("porch_bench", Vector3(2.30, 0.42, 3.80), -PI * 0.5, 0.495, Vector3(-0.55, 0.0, 0.0), {"kind": "sit", "floor_local_y": 0.42}))
    data["seats_floor1"] = seats
    # ---- attic spots ----
    var attic := []
    attic.append(_spot("reading_chair", Vector3(1.60, _attic_top, 1.10), -PI * 0.5, 0.40, Vector3(-0.60, 0.0, 0.0), {"kind": "sit"}))
    attic.append(_spot("attic_desk_chair", Vector3(0.0, _attic_top, 1.95), 0.0, 0.40, Vector3(0.0, 0.0, -0.58), {"kind": "sit"}))
    attic.append(_spot("attic_plant_view", Vector3(2.30, _attic_top, 1.70), -PI * 0.5, -1.0, Vector3(0.0, 0.0, 0.0), {"kind": "view"}))
    data["seats_attic"] = attic
    data["bed"] = {
        "stand": _a(_wl(Vector3(-2.00, _attic_top, -0.10))),
        "stand_yaw_local": 0.0,
        "lie_pelvis": _a(_wl(Vector3(-2.00, 3.66, -0.90))),
        "lie_yaw_local": -PI * 0.5,
        "mattress_top_local": 3.64,
        "pillow_head_local_x": -1.34,
        "mattress_x_range": [-2.95, -1.05],
        "mattress_z_range": [-1.40, -0.40],
    }
    # ---- outdoor wander nodes ----
    var outdoor := []
    outdoor.append(_outdoor("door_approach", Vector2(M.door_approach().x, M.door_approach().z)))
    outdoor.append(_outdoor("front_path_1", Vector2(2.20, 6.40)))
    outdoor.append(_outdoor("front_path_2", Vector2(5.60, 8.60)))
    outdoor.append(_outdoor("front_path_3", Vector2(9.60, 10.20)))
    outdoor.append(_outdoor("front_path_4", Vector2(14.20, 11.80)))
    var ds := M.dock_start()
    var de := M.dock_end()
    var dd := M.dock_dir()
    var deck_y: float = float((_world.get("dock", {}) as Dictionary).get("deck_world_y", W.DECK_WORLD_Y))
    outdoor.append(_outdoor("dock_start", Vector2(ds.x, ds.z), "ground"))
    outdoor.append(_outdoor("dock_mid", Vector2(ds.x + dd.x * 4.0, ds.z + dd.z * 4.0), "dock", deck_y))
    outdoor.append(_outdoor("dock_end", Vector2(de.x - dd.x * 1.2, de.z - dd.z * 1.2), "dock", deck_y))
    var garden_pts := [Vector2(1.20, 7.10), Vector2(-1.60, 6.55), Vector2(-3.90, 4.90), Vector2(-5.40, 2.60), Vector2(-6.40, 0.0), Vector2(-7.05, -1.90), Vector2(-7.45, -2.95), Vector2(-7.82, -2.95), Vector2(-7.82, -6.20)]
    var gi := 0
    for gp in garden_pts:
        outdoor.append(_outdoor("garden_%d" % gi, gp))
        gi += 1
    outdoor.append(_outdoor("garden_cross_e", Vector2(-6.20, -6.20)))
    # viewpoints: offsets toward island centre so we never stand inside the landmark
    var tree_pos := Vector3(M.BIG_TREE_X, 0.0, M.BIG_TREE_Z)
    var tree_view := tree_pos + (Vector3.ZERO - tree_pos).normalized() * 2.60
    outdoor.append(_outdoor("big_tree_view", Vector2(tree_view.x, tree_view.z)))
    var swing_pos := Vector3(M.SWING_X, 0.0, M.SWING_Z)
    var swing_view := swing_pos + (Vector3.ZERO - swing_pos).normalized() * 1.60
    outdoor.append(_outdoor("swing_view", Vector2(swing_view.x, swing_view.z)))
    data["outdoor"] = outdoor
    data["dock_meta"] = _world.get("dock", {})
    print("[VCOORD] " + JSON.stringify(data))
    print("[VCOORD] RESULT spots_floor1=%d seats_attic=%d outdoor=%d treads=%d" % [seats.size(), attic.size(), outdoor.size(), treads.size()])
