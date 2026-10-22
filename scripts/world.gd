class_name IsleWorld
extends RefCounted
## Procedural island world (v4).
## Everything is generated at build time from IsleMath helpers: a smooth layered
## terrain, wind-swept grass / clover, four real flower species (tulip / daisy /
## bluebell / poppy), layered low-poly trees, a walled kitchen garden with a
## vegetable plot, a tall lighthouse (which replaces the old windmill), a detailed
## dock with one large sailing boat, six rock families with near/far LOD meshes,
## lamps, sail routes and distant island silhouettes.
## Only M (IsleMath) is used for layout / colours / material caches.

const M := preload("res://scripts/isle_math.gd")

# ---------------------------------------------------------------- layout ----
const GARDEN_X0 := -9.75
const GARDEN_X1 := -5.90
const GARDEN_Z0 := -9.45
const GARDEN_Z1 := -2.95
const FIELD_X0 := -4.90
const FIELD_X1 := -1.70
const FIELD_Z0 := -9.60
const FIELD_Z1 := -6.90
# Lighthouse replaces the old windmill on the very same headland site.
# Total structure height = 1.5x the measured old-windmill AABB height:
#   old "Windmill" node AABB height = 12.1839389801025 m (probe measured)
#   target lighthouse height        = 18.2759084701538 m
const LIGHTHOUSE_X := -17.00
const LIGHTHOUSE_Z := 9.00
const LIGHTHOUSE_OLD_H := 12.1839389801025
const LIGHTHOUSE_H := 18.2759084701538
const DECK_WORLD_Y := 0.72
# Exact rock LOD triangle budgets (single winding, so mesh tri count == budget).
const ROCK_NEAR_TRIS := 320
const ROCK_FAR_TRIS := 80
const SWING_PIVOT_X := -7.90
const SWING_PIVOT_Z := 4.20
const SWING_LIMB_Y := 5.55
const GRASS_NEAR_TARGET := 16000
const GRASS_FAR_TARGET := 6500

# ------------------------------------------------------------ build cache ----
static var _path_segs := PackedVector2Array()
static var _path_widths := PackedFloat32Array()
static var _bed_rects: Array = []
static var _tree_spots: Array = []
# Sail-route clearance cache: flat list of Vector2 point pairs (out + back legs).
static var _sail_segs: Array = []

# ============================================================== entry point ==
# Builds the whole island under "parent" and returns the handle dictionary the
# main scene relies on (old keys kept, new keys appended).
## P8.1: include_winter 默认 false —— 旧探针（P7-V2 perch/bird 等）调用 build(parent)
## 仍得到 16/22/36 点契约；游戏内 main.gd 显式传 true 获得 41 点（world 27 + cottage 14）。
static func build(parent: Node3D, include_winter: bool = false) -> Dictionary:
    _prepare()
    # Sail routes are planned first so that rock placement can keep clear of them.
    var route_plan: Dictionary = _sail_routes()
    var sail_routes: Array = route_plan["routes"]
    var sail_anchor: Vector3 = route_plan["anchor"]
    var sail_heading: float = route_plan["heading"]
    var island_diameter: float = route_plan["island_diameter"]
    var sail_return_paths: Dictionary = route_plan["return_paths"]

    var root := Node3D.new()
    root.name = "Island"
    parent.add_child(root)

    var terrain := _build_terrain(root)
    var grass_counts := _scatter_grass(root)
    _scatter_clover(root)
    var flower_stats := _scatter_flowers(root)
    var winter_bloom := _winter_blooms(root)
    _scatter_bushes(root)
    var rock_stats := _rocks(root)
    _stepping_stones(root)
    var big := _big_tree(root)
    _bg_trees(root)
    var dock_info := _dock(root)
    var sail_info := _sailboat(root, sail_routes)
    _garden(root)
    _field(root)
    var lighthouse := _lighthouse(root)
    var swing := _swing(root, big)

    # P5: six street lamps along the real path curves (3 main + 3 garden).
    # With the dock lantern and the lighthouse lamp this keeps light_sources at 8.
    var lamps: Array = _street_lamps(root)
    var lamp_mats: Array = []
    var lamp_halos: Array = []
    var light_sources: Array = []
    for l in lamps:
        lamp_mats.append(l[0])
        lamp_halos.append(l[1])
        light_sources.append(l[2])
    lamp_mats.append(dock_info["lantern_mat"])
    lamp_halos.append(dock_info["lantern_halo"])
    light_sources.append(dock_info["light"])
    lamp_mats.append(sail_info["lantern_mat"])
    lamp_halos.append(sail_info["lantern_halo"])
    # The lighthouse lamp is a real light source as well (8 lights total = shader budget).
    lamp_mats.append(lighthouse["lamp_mat"])
    lamp_halos.append(lighthouse["lamp_halo"])
    light_sources.append(lighthouse["light"])

    _distant_isles(root)

    # P7-V2: pass the real street lamps so each lantern cap gets a "lamp" roost.
    # P8.1: include_winter=true adds five bare-branch roosts for the leaf-off season.
    # build() 默认 false，旧探针直接调用 build(parent) 仍是 16/22/36 点契约；
    # main.gd 显式传 true（world 27 点 + cottage 14 = 41）。
    var perches: Array[Dictionary] = _build_perches(big, dock_info, lighthouse, lamps, include_winter)

    return {
        "root": root,
        "terrain": terrain,
        "perches": perches,
        "dock_end": dock_info["end"],
        "dock_perch": dock_info["perch"],
        "dock": dock_info,
        "big_tree": big["pos"],
        "big_tree_canopy": big["canopy"],
        "lamps": lamps,
        "lamp_mats": lamp_mats,
        "lamp_halos": lamp_halos,
        "light_sources": light_sources,
        "swing": swing,
        "swing_axis": Vector3(1.0, 0.0, 0.0),
        "sailboat": sail_info["node"],
        "sailboat_path": sail_info["path"],
        "sailboat_speed": sail_info["speed"],
        "grass_count": int(grass_counts[0]) + int(grass_counts[1]),
        "sail_routes": sail_routes,
        "sail_dock_pos": sail_anchor,
        "sail_dock_heading": sail_heading,
        "island_diameter": island_diameter,
        "sail_return_paths": sail_return_paths,
        "sail_return_path": func(entry: Vector3) -> PackedVector3Array: return _sail_return_path(entry),
        "dock_deck_world_y": DECK_WORLD_Y,
        "sailboat_lantern_mat": sail_info["lantern_mat"],
        "sailboat_lantern_halo": sail_info["lantern_halo"],
        "sailboat_lantern_local_pos": sail_info["lantern_local_pos"],
        "sailboat_spot_node": sail_info["spot_node"],
        "sailboat_spot_lens_pos": sail_info["spot_lens_pos"],
        "sailboat_spot_cone_mat": sail_info["spot_cone_mat"],
        "sailboat_fade_mats": sail_info["fade_mats"],
        # ---- lighthouse (replaces the removed windmill) ----
        "lighthouse": lighthouse["node"],
        "lighthouse_height": lighthouse["height"],
        # Telemetry for the main.gd selftest: measured old windmill AABB height.
        "windmill_old_height": LIGHTHOUSE_OLD_H,
        "lighthouse_lamp": lighthouse["lamp"],
        "lighthouse_beam_origin": lighthouse["beam_origin"],
        "lighthouse_platform": lighthouse["platform"],
        "lighthouse_perches": lighthouse["perches"],
        "lighthouse_light": lighthouse["light"],
        "lighthouse_lamp_mat": lighthouse["lamp_mat"],
        "lighthouse_lamp_halo": lighthouse["lamp_halo"],
        "lighthouse_rotation_axis": lighthouse["rotation_axis"],
        # ---- probe / telemetry ----
        "rock_stats": rock_stats,
        "flower_stats": flower_stats,
        "winter_bloom": winter_bloom,
    }

# ================================================================= layout ===
static func _prepare() -> void:
    _path_segs = PackedVector2Array()
    _path_widths = PackedFloat32Array()
    var door := M.door_approach()
    var dock := M.dock_start()
    # main gravel path: house door -> dock
    _add_path([Vector2(door.x, door.z), Vector2(5.6, 8.6), Vector2(9.6, 10.2),
        Vector2(14.2, 11.8), Vector2(dock.x, dock.z)], 0.62)
    # garden spur off the main path
    _add_path([Vector2(door.x, door.z), Vector2(1.2, 7.1), Vector2(-1.6, 6.55),
        Vector2(-3.9, 4.9), Vector2(-5.4, 2.6), Vector2(-6.4, 0.0),
        Vector2(-7.05, -1.9), Vector2(-7.45, -2.95)], 0.50)
    # cross paths inside the walled garden
    _add_path([Vector2(-7.82, -2.95), Vector2(-7.82, -9.45)], 0.44)
    _add_path([Vector2(-9.45, -6.20), Vector2(-6.20, -6.20)], 0.44)
    # garden east gate -> vegetable plot
    _add_path([Vector2(-5.90, -6.20), Vector2(-5.30, -6.55),
        Vector2(FIELD_X0, -6.90)], 0.40)
    _bed_rects = [
        Vector4(-9.40, -8.32, -9.10, -6.70),
        Vector4(-7.33, -6.25, -9.10, -6.70),
        Vector4(-9.40, -8.32, -5.70, -3.30),
        Vector4(-7.33, -6.25, -5.70, -3.30),
    ]
    _tree_spots = [
        Vector2(-10.9, 4.2), Vector2(10.4, -9.0), Vector2(14.9, -4.6),
        Vector2(-15.6, 0.4), Vector2(6.8, -12.5),
    ]

static func _add_path(pts: Array, width: float) -> void:
    for i in range(pts.size() - 1):
        var a: Vector2 = pts[i]
        var b: Vector2 = pts[i + 1]
        _path_segs.append(a)
        _path_segs.append(b)
        _path_widths.append(width)

## Distance to the nearest path edge (negative => on the path surface).
static func _path_clearance(px: float, pz: float) -> float:
    var best := 9999.0
    var i := 0
    var count := _path_segs.size()
    while i + 1 < count:
        var a: Vector2 = _path_segs[i]
        var b: Vector2 = _path_segs[i + 1]
        var w: float = _path_widths[i >> 1]
        var vx := b.x - a.x
        var vz := b.y - a.y
        var wx := px - a.x
        var wz := pz - a.y
        var l2 := vx * vx + vz * vz
        var t := 0.0
        if l2 > 0.00001:
            t = clampf((wx * vx + wz * vz) / l2, 0.0, 1.0)
        var dx := wx - vx * t
        var dz := wz - vz * t
        var d := sqrt(dx * dx + dz * dz) - w
        if d < best:
            best = d
        i += 2
    return best

## Probe helper: nearest path centre line point / distance / half width.
static func path_center_info(x: float, z: float) -> Dictionary:
    var best := 1.0e20
    var best_c := Vector2.ZERO
    var best_w := 0.0
    var i := 0
    var count := _path_segs.size()
    while i + 1 < count:
        var a: Vector2 = _path_segs[i]
        var b: Vector2 = _path_segs[i + 1]
        var w: float = _path_widths[i >> 1]
        var vx := b.x - a.x
        var vz := b.y - a.y
        var l2 := vx * vx + vz * vz
        var t := 0.0
        if l2 > 0.00001:
            t = clampf(((x - a.x) * vx + (z - a.y) * vz) / l2, 0.0, 1.0)
        var cx := a.x + vx * t
        var cz := a.y + vz * t
        var d := Vector2(cx, cz).distance_to(Vector2(x, z))
        if d < best:
            best = d
            best_c = Vector2(cx, cz)
            best_w = w
        i += 2
    return {"dist": best, "centre": best_c, "half_w": best_w}

# =========================================================== ground maths ===
static func _vnoise(x: float, z: float) -> float:
    var ix := floori(x)
    var iz := floori(z)
    var fx := x - float(ix)
    var fz := z - float(iz)
    var ux := fx * fx * (3.0 - 2.0 * fx)
    var uz := fz * fz * (3.0 - 2.0 * fz)
    var a := M.noise01(float(ix), float(iz))
    var b := M.noise01(float(ix + 1), float(iz))
    var c := M.noise01(float(ix), float(iz + 1))
    var d := M.noise01(float(ix + 1), float(iz + 1))
    return lerpf(lerpf(a, b, ux), lerpf(c, d, ux), uz)

static func _fbm(x: float, z: float) -> float:
    var s := 0.5 * _vnoise(x, z)
    s += 0.3 * _vnoise(x * 2.07 + 13.1, z * 2.07 - 7.3)
    s += 0.2 * _vnoise(x * 4.31 - 5.7, z * 4.31 + 11.9)
    return s

## Terrain height including three meadow mounds that keep the flat area alive.
static func _h(x: float, z: float) -> float:
    var h := M.terrain_height(x, z)
    var dx := x - 13.5
    var dz := z + 4.0
    var d2 := dx * dx + dz * dz
    if d2 < 23.04:
        var t := 1.0 - sqrt(d2) / 4.8
        h += 0.34 * t * t * (3.0 - 2.0 * t)
    dx = x - 5.3
    dz = z - 16.3
    d2 = dx * dx + dz * dz
    if d2 < 17.64:
        var t2 := 1.0 - sqrt(d2) / 4.2
        h += 0.30 * t2 * t2 * (3.0 - 2.0 * t2)
    dx = x + 16.0
    dz = z - 12.2
    d2 = dx * dx + dz * dz
    if d2 < 20.25:
        var t3 := 1.0 - sqrt(d2) / 4.5
        h += 0.32 * t3 * t3 * (3.0 - 2.0 * t3)
    return h

## P7-V4 public walk-surface accessor: terrain height incl. meadow mounds, for characters/probes.
static func surface_y(x: float, z: float) -> float:
    return _h(x, z)

## P7-V4 public trail accessor: signed distance to nearest trail edge (negative => on trail).
static func trail_clearance(x: float, z: float) -> float:
    return _path_clearance(x, z)

static func _hn(x: float, z: float) -> Vector3:
    var e := 0.32
    var hl := _h(x - e, z)
    var hr := _h(x + e, z)
    var hd := _h(x, z - e)
    var hu := _h(x, z + e)
    return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()

## Cheap slope gate (two extra height samples instead of four); ny >= ~0.72.
static func _slope_ok(x: float, z: float, h: float) -> bool:
    var e := 0.36
    var dx := (_h(x + e, z) - h) / e
    var dz := (_h(x, z + e) - h) / e
    return dx * dx + dz * dz < 0.92

static func _norm_radius(x: float, z: float) -> float:
    var r := sqrt(x * x + z * z)
    return r / M.coast_radius(atan2(z, x))

static func _in_house(x: float, z: float, pad: float) -> bool:
    var dx := x - M.HOUSE_X
    var dz := z - M.HOUSE_Z
    var c := cos(M.HOUSE_YAW)
    var s := sin(M.HOUSE_YAW)
    var lx := dx * c - dz * s
    var lz := dx * s + dz * c
    return absf(lx) < M.HOUSE_W * 0.5 + pad and absf(lz) < M.HOUSE_D * 0.5 + pad

static func _in_garden(x: float, z: float, pad: float) -> bool:
    return x > GARDEN_X0 - pad and x < GARDEN_X1 + pad and z > GARDEN_Z0 - pad and z < GARDEN_Z1 + pad

static func _in_field(x: float, z: float, pad: float) -> bool:
    return x > FIELD_X0 - pad and x < FIELD_X1 + pad and z > FIELD_Z0 - pad and z < FIELD_Z1 + pad

## Cottage porch / deck footprint in house-local coordinates (grass must not sprout between the planks).
static func _in_porch(x: float, z: float, pad: float) -> bool:
    var dx := x - M.HOUSE_X
    var dz := z - M.HOUSE_Z
    var c := cos(M.HOUSE_YAW)
    var s := sin(M.HOUSE_YAW)
    var lx := dx * c - dz * s
    var lz := dx * s + dz * c
    return absf(lx) < 4.30 + pad and lz > 3.40 - pad and lz < 7.45 + pad

## Distance to the dock centre line in XZ, minus half the deck width (negative on the boards).
static func _dock_clearance(x: float, z: float) -> float:
    var start := M.dock_start()
    var d := M.dock_dir()
    var ax := start.x
    var az := start.z
    var vx := d.x * (M.DOCK_LENGTH + 1.6)
    var vz := d.z * (M.DOCK_LENGTH + 1.6)
    var t := clampf(((x - ax) * vx + (z - az) * vz) / (vx * vx + vz * vz), 0.0, 1.0)
    var px := ax + vx * t - x
    var pz := az + vz * t - z
    return sqrt(px * px + pz * pz) - M.DOCK_WIDTH * 0.5

## Signed distance to the garden rectangle (<0 inside).
static func _garden_sd(x: float, z: float) -> float:
    var dx := maxf(GARDEN_X0 - x, x - GARDEN_X1)
    var dz := maxf(GARDEN_Z0 - z, z - GARDEN_Z1)
    return maxf(dx, dz)

static func _in_bed(x: float, z: float, pad: float) -> bool:
    for bed in _bed_rects:
        var r: Vector4 = bed
        if x > r.x - pad and x < r.y + pad and z > r.z - pad and z < r.w + pad:
            return true
    return false

static func _tree_min_dist(x: float, z: float) -> float:
    var best := 9999.0
    for spot in _tree_spots:
        var v: Vector2 = spot
        var dx := x - v.x
        var dz := z - v.y
        var d := sqrt(dx * dx + dz * dz)
        if d < best:
            best = d
    return best

static func _rect_max_h(r: Vector4, inset: float) -> float:
    var best := -999.0
    for ix in range(3):
        for iz in range(3):
            var x := lerpf(r.x + inset, r.y - inset, float(ix) * 0.5)
            var z := lerpf(r.z + inset, r.w - inset, float(iz) * 0.5)
            best = maxf(best, _h(x, z))
    return best

static func _rect_min_h(r: Vector4, inset: float) -> float:
    var best := 999.0
    for ix in range(3):
        for iz in range(3):
            var x := lerpf(r.x + inset, r.y - inset, float(ix) * 0.5)
            var z := lerpf(r.z + inset, r.w - inset, float(iz) * 0.5)
            best = minf(best, _h(x, z))
    return best

# ================================================================ terrain ===
static func _build_terrain(root: Node3D) -> MeshInstance3D:
    var angles := 240
    var ns: Array = []
    for i in range(32):
        ns.append(0.018 + 0.0131 * float(i))
    for i in range(20):
        ns.append(0.440 + 0.0188 * float(i))
    for i in range(28):
        ns.append(0.807 + 0.0088 * float(i))
    for i in range(13):
        ns.append(1.055 + 0.0435 * float(i))
    var ring_count: int = ns.size()
    var vert_count: int = 1 + ring_count * angles

    var pos := PackedVector3Array()
    pos.resize(vert_count)
    var nrad := PackedFloat32Array()
    nrad.resize(vert_count)
    var center_h := _h(0.0, 0.0)
    pos[0] = Vector3(0.0, center_h, 0.0)
    nrad[0] = 0.0
    for ri in range(ring_count):
        var n: float = ns[ri]
        for ai in range(angles):
            var a: float = TAU * float(ai) / float(angles)
            var cr := M.coast_radius(a)
            var x := cos(a) * n * cr
            var z := sin(a) * n * cr
            var idx: int = 1 + ri * angles + ai
            pos[idx] = Vector3(x, _h(x, z), z)
            nrad[idx] = n

    # smooth normals from the grid neighbourhood (uses the mound heights too)
    var norms := PackedVector3Array()
    norms.resize(vert_count)
    for ri in range(ring_count):
        var row: int = 1 + ri * angles
        for ai in range(angles):
            var ai_p := (ai + angles - 1) % angles
            var ai_n := (ai + 1) % angles
            var p: Vector3 = pos[row + ai]
            var p_prev: Vector3 = pos[row + ai_p]
            var p_next: Vector3 = pos[row + ai_n]
            var p_in := Vector3.ZERO
            var p_out := Vector3.ZERO
            if ri == 0:
                p_in = pos[0]
            else:
                p_in = pos[1 + (ri - 1) * angles + ai]
            if ri == ring_count - 1:
                p_out = p + (p - p_in)
            else:
                p_out = pos[1 + (ri + 1) * angles + ai]
            var t_ang := p_next - p_prev
            var t_rad := p_out - p_in
            var nrm := t_rad.cross(t_ang)
            if nrm.y < 0.0:
                nrm = -nrm
            norms[row + ai] = nrm.normalized()
    var centre := Vector3.ZERO
    for ai in range(angles):
        centre += norms[1 + ai]
    norms[0] = (centre / float(angles)).normalized()

    var cols := PackedColorArray()
    cols.resize(vert_count)
    var uvs := PackedVector2Array()
    uvs.resize(vert_count)
    uvs[0] = Vector2(0.0, 0.0)
    cols[0] = _terrain_color(0.0, 0.0, center_h, 0.0, 1.0)
    for ri in range(ring_count):
        var row: int = 1 + ri * angles
        for ai in range(angles):
            var idx: int = row + ai
            var p: Vector3 = pos[idx]
            cols[idx] = _terrain_color(p.x, p.z, p.y, nrad[idx], norms[idx].y)
            uvs[idx] = Vector2(p.x, p.z) * 0.09

    var idxs := PackedInt32Array()
    for ai in range(angles):
        var a1 := (ai + 1) % angles
        idxs.append(0)
        idxs.append(1 + ai)
        idxs.append(1 + a1)
    for ri in range(ring_count - 1):
        var row0: int = 1 + ri * angles
        var row1: int = row0 + angles
        for ai in range(angles):
            var a1 := (ai + 1) % angles
            idxs.append(row0 + ai)
            idxs.append(row1 + ai)
            idxs.append(row0 + a1)
            idxs.append(row0 + a1)
            idxs.append(row1 + ai)
            idxs.append(row1 + a1)

    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = pos
    arrays[Mesh.ARRAY_NORMAL] = norms
    arrays[Mesh.ARRAY_COLOR] = cols
    arrays[Mesh.ARRAY_TEX_UV] = uvs
    arrays[Mesh.ARRAY_INDEX] = idxs
    var am := ArrayMesh.new()
    am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    var mi := MeshInstance3D.new()
    mi.name = "Terrain"
    mi.mesh = am
    mi.material_override = M.terrain_material()
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    root.add_child(mi)
    return mi

## Layer colours by height / slope / distance masks.
static func _terrain_color(x: float, z: float, h: float, n: float, ny: float) -> Color:
    var m1 := _fbm(x * 0.055 + 3.0, z * 0.055 - 7.0)
    var m2 := _fbm(x * 0.21 - 31.7, z * 0.21 + 12.3)
    var m3 := _vnoise(x * 0.73 + 5.1, z * 0.73 - 8.9)
    var grass := M.C_GRASS.lerp(M.C_GRASS_LIGHT, clampf(m1 * 1.5 - 0.05, 0.0, 1.0))
    grass = grass.lerp(M.C_GRASS_DARK, clampf(m2 * 0.42, 0.0, 1.0))
    grass = grass.lerp(Color("b5b98a"), smoothstep(0.55, 0.92, m1) * 0.34)
    grass = grass.lerp(M.C_GRASS_LIGHT, m3 * 0.10)
    var c := grass
    # --- bare soil: paths, tree roots, plots ---
    var soil := M.C_SOIL.lerp(Color("8a6c50"), m2 * 0.55)
    soil = soil.lerp(Color("5d4736"), m3 * 0.35)
    var dirt := smoothstep(1.15, 0.15, _path_clearance(x, z) + (m3 - 0.5) * 0.45)
    dirt = maxf(dirt, smoothstep(3.6, 1.1, _tree_min_dist(x, z)) * 0.82)
    if _in_field(x, z, 0.35):
        dirt = maxf(dirt, 0.92)
    var gsd := _garden_sd(x, z)
    if gsd < 0.30:
        dirt = maxf(dirt, smoothstep(0.30, -0.20, gsd) * 0.55)
    c = c.lerp(soil, clampf(dirt, 0.0, 1.0))
    # garden gravel floor
    if gsd < 0.20:
        var gravel := Color("a89a83").lerp(M.C_STONE_DARK, m3 * 0.55)
        c = c.lerp(gravel, smoothstep(0.20, -0.15, gsd) * 0.55)
    if _in_bed(x, z, 0.06):
        c = c.lerp(M.C_SOIL.darkened(0.18), 0.85)
    # --- rock faces on steep slopes and the coastal cliff band ---
    var rock := M.C_ROCK.lerp(M.C_ROCK_DARK, clampf(m2 * 0.85 + m3 * 0.25, 0.0, 1.0))
    rock = rock.lerp(Color("8a8174"), 0.22)
    var steep := smoothstep(0.88, 0.58, ny)
    var cliff := smoothstep(0.82, 0.94, n) * (1.0 - smoothstep(1.04, 1.16, n)) * smoothstep(3.6, 0.2, h)
    c = c.lerp(rock, clampf(maxf(steep, cliff * 0.92), 0.0, 1.0))
    # --- sand ring ---
    var sand := smoothstep(2.8, 0.30, h) * smoothstep(0.79, 0.90, n)
    sand *= smoothstep(-0.6, 0.55, h)
    c = c.lerp(M.C_SAND.lerp(Color("c2b08c"), m2 * 0.5), clampf(sand, 0.0, 1.0) * 0.94)
    # --- damp shoreline ---
    var wet := smoothstep(0.62, -0.18, h) * smoothstep(0.83, 0.94, n)
    c = c.lerp(Color("8b8066"), clampf(wet, 0.0, 1.0) * 0.72)
    # --- seabed (mostly hidden by the opaque sea) ---
    if h < 0.05:
        var uw := clampf(-h / 1.8, 0.0, 1.0)
        c = c.lerp(Color("8f8468").lerp(Color("4f6a60"), uw), smoothstep(0.05, -0.35, h))
    return c * 0.90

# ============================================================ grass layer ===
## Returns the ground height when grass may grow here, or 0.0 when it may not.
static func _grass_spot(x: float, z: float, check_slope: bool = true) -> float:
    var n := _norm_radius(x, z)
    if n < 0.02 or n > 0.86:
        return 0.0
    # keep the cottage base, porch, garden, field and all foot paths clear
    if _in_house(x, z, 0.85) or _in_porch(x, z, 0.70):
        return 0.0
    if _in_garden(x, z, 0.42) or _in_field(x, z, 0.42):
        return 0.0
    # no grass on the beach ring / rocks / water (cheap early out)
    var h := _h(x, z)
    if h < 2.55:
        return 0.0
    if _path_clearance(x, z) < 0.60:
        return 0.0
    if _dock_clearance(x, z) < 0.55:
        return 0.0
    if _tree_min_dist(x, z) < 1.55:
        return 0.0
    var swx := x - SWING_PIVOT_X
    var swz := z - SWING_PIVOT_Z
    if swx * swx + swz * swz < 2.25:
        return 0.0
    var wmx := x - LIGHTHOUSE_X
    var wmz := z - LIGHTHOUSE_Z
    if wmx * wmx + wmz * wmz < 17.0:
        return 0.0
    if check_slope and not _slope_ok(x, z, h):
        return 0.0
    return h

## 0..1 density hint: the meadow is lush where the player looks first.
static func _grass_weight(x: float, z: float) -> float:
    var w := 0.30
    var ddx := x - M.HOUSE_X
    var ddz := z - M.HOUSE_Z
    w += 1.15 * smoothstep(18.0, 5.0, sqrt(ddx * ddx + ddz * ddz))
    w += 1.00 * smoothstep(4.8, 0.4, _path_clearance(x, z))
    var gdx := x - M.GARDEN_X
    var gdz := z - M.GARDEN_Z
    w += 0.95 * smoothstep(12.0, 2.0, sqrt(gdx * gdx + gdz * gdz))
    w += 0.45 * smoothstep(9.0, 2.0, _tree_min_dist(x, z))
    w += 0.30 * smoothstep(0.20, 0.85, _fbm(x * 0.07 + 3.0, z * 0.07 - 6.0))
    # 中尺度成簇：让草地呈“草丘 + 裸地”的自然斑块，而不是均匀铺满
    var clump := 0.52 + 0.92 * smoothstep(0.22, 0.74, _fbm(x * 0.16 + 11.0, z * 0.16 - 4.0))
    return clampf(w * clump, 0.0, 1.0)

static func _scatter_grass(root: Node3D) -> Array:
    var rng := RandomNumberGenerator.new()
    rng.seed = 20261021
    var near_xf: Array = []
    var near_col: Array = []
    var far_xf: Array = []
    var far_col: Array = []
    var tries := 0
    while near_xf.size() < GRASS_NEAR_TARGET and tries < 110000:
        tries += 1
        var a := rng.randf_range(0.0, TAU)
        var n := sqrt(rng.randf()) * 0.80
        var x := cos(a) * n * M.coast_radius(a)
        var z := sin(a) * n * M.coast_radius(a)
        var w := _grass_weight(x, z)
        if w < 0.06 or rng.randf() > w:
            continue
        var h := _grass_spot(x, z)
        if h <= 0.0:
            continue
        var s := rng.randf_range(0.62, 0.92)
        var sy := rng.randf_range(0.26, 0.52)
        var lean := Vector3(rng.randf_range(-0.10, 0.10), 0.0, rng.randf_range(-0.10, 0.10))
        var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)) * Basis.from_euler(lean)
        near_xf.append(Transform3D(basis.scaled(Vector3(s, sy, s)),
            Vector3(x, h - 0.02, z)))
        var col := M.C_GRASS.lerp(M.C_GRASS_DARK, rng.randf() * 0.55)
        col = col.lerp(M.C_GRASS_LIGHT, 0.10 + rng.randf() * 0.22)
        col = col.lerp(Color("8f9a62"), rng.randf() * 0.16)
        col = col.lerp(Color("b3ad76"), rng.randf() * 0.14)
        near_col.append(col)
    tries = 0
    while far_xf.size() < GRASS_FAR_TARGET and tries < 56000:
        tries += 1
        var fa := rng.randf_range(0.0, TAU)
        var fn := sqrt(rng.randf()) * 0.82
        var fx := cos(fa) * fn * M.coast_radius(fa)
        var fz := sin(fa) * fn * M.coast_radius(fa)
        var fclump := 0.55 + 0.65 * smoothstep(0.18, 0.78, _fbm(fx * 0.13 - 7.0, fz * 0.13 + 5.0))
        if rng.randf() > 0.58 + 0.30 * fclump:
            continue
        var fh := _grass_spot(fx, fz, false)
        if fh <= 0.0:
            continue
        var fs := rng.randf_range(0.85, 1.20)
        var fsy := rng.randf_range(0.32, 0.58)
        far_xf.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(fs, fsy, fs)),
            Vector3(fx, fh - 0.03, fz)))
        var fcol := M.C_GRASS.lerp(M.C_GRASS_DARK, 0.30 + rng.randf() * 0.55)
        fcol = fcol.lerp(Color("82905e"), rng.randf() * 0.22)
        far_col.append(fcol)

    var near_mat := M.grass_material(Color(0.88, 0.99, 0.85), 0.55)
    var far_mat := M.grass_material(Color(0.83, 0.94, 0.80), 0.85)
    M.multis(root, "GrassNear", _tuft_mesh(3, 0.50, 1.0), near_xf, near_col, near_mat)
    M.multis(root, "GrassFar", _tuft_mesh(2, 0.78, 1.0), far_xf, far_col, far_mat)
    return [near_xf.size(), far_xf.size()]

static func _tuft_mesh(quads: int, width: float, height: float) -> ArrayMesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var hw := width * 0.5
    for qi in range(quads):
        var ang := PI * float(qi) / float(quads)
        var dx := cos(ang)
        var dz := sin(ang)
        var nrm := Vector3(-dz, 0.0, dx).normalized()
        var a := Vector3(-dx * hw, 0.0, -dz * hw)
        var b := Vector3(dx * hw, 0.0, dz * hw)
        var c := Vector3(dx * hw, height, dz * hw)
        var d := Vector3(-dx * hw, height, -dz * hw)
        st.set_normal(nrm)
        st.set_uv(Vector2(0.0, 1.0))
        st.add_vertex(a)
        st.set_uv(Vector2(1.0, 1.0))
        st.add_vertex(b)
        st.set_uv(Vector2(1.0, 0.0))
        st.add_vertex(c)
        st.set_uv(Vector2(0.0, 1.0))
        st.add_vertex(a)
        st.set_uv(Vector2(1.0, 0.0))
        st.add_vertex(c)
        st.set_uv(Vector2(0.0, 0.0))
        st.add_vertex(d)
    st.index()
    return st.commit()

# ------------------------------------------------------------ clover mat ---
static func _scatter_clover(root: Node3D) -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = 8821
    var xforms: Array = []
    var colors: Array = []
    var tries := 0
    while xforms.size() < 1600 and tries < 16000:
        tries += 1
        var a := rng.randf_range(0.0, TAU)
        var n := sqrt(rng.randf()) * 0.86
        var x := cos(a) * n * M.coast_radius(a)
        var z := sin(a) * n * M.coast_radius(a)
        if _grass_weight(x, z) < 0.32:
            continue
        var h := _grass_spot(x, z)
        if h <= 0.0:
            continue
        var s := rng.randf_range(0.8, 1.6)
        xforms.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(s, s, s)),
            Vector3(x, h + 0.01, z)))
        var col := M.C_GRASS_DARK.lerp(M.C_GRASS_LIGHT, rng.randf() * 0.7)
        colors.append(col.lerp(Color("9fb46a"), 0.22))
    M.multis(root, "Clover", _clover_mesh(), xforms, colors,
        M.toon_material(Color.WHITE, {"vertex_color": true, "bands": 3.0, "rim": 0.0}))

static func _clover_mesh() -> ArrayMesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var up := Vector3(0.0, 0.03, 0.0)
    for i in range(3):
        var ang := TAU * float(i) / 3.0 + 0.4
        var dirv := Vector3(cos(ang), 0.0, sin(ang))
        var side := Vector3(-sin(ang), 0.0, cos(ang))
        var p0 := side * 0.035 + dirv * 0.012 + up * 0.2
        var p1 := -side * 0.035 + dirv * 0.012 + up * 0.2
        var p2 := -side * 0.030 + dirv * 0.13 + up
        var p3 := side * 0.030 + dirv * 0.13 + up
        _add_quad2(st, p0, p1, p2, p3, Vector3.UP)
    return st.commit()

# ============================================================== flowers ====
# Four real flower species, each generated as a small merged mesh:
#   stem+leaves part (baked green vertex colours) and one head mesh per colour
#   variant. Instancing is done with MultiMeshes, clustered on the meadow and in
#   tidy rows inside the four raised garden beds.
static func _bed_top(r: Vector4) -> float:
    return _rect_max_h(r, 0.18) + 0.30

# Species table: name / stem height / stem bend (x per t^2) / bloom type / colours.
static func _flower_species() -> Array:
    return [
        {"name": "Tulip", "height": 0.46, "bend": 0.04, "variants": ["d9919b", "f3ead6"]},
        {"name": "Daisy", "height": 0.34, "bend": 0.03, "variants": ["f3ead6"]},
        {"name": "Bluebell", "height": 0.44, "bend": 0.20, "variants": ["a98ac0", "9db4d8"]},
        {"name": "Poppy", "height": 0.52, "bend": 0.06, "variants": ["c25b4e", "d97b45"]},
    ]

# [centre: Vector2, species index, variant index, count, cluster radius]
static func _flower_clusters() -> Array:
    return [
        [Vector2(-8.40, -2.05), 1, 0, 16, 1.30],
        [Vector2(-6.30, -2.10), 3, 1, 14, 1.20],
        [Vector2(-10.45, -5.20), 0, 0, 14, 1.30],
        [Vector2(-5.30, -8.20), 2, 0, 10, 0.90],
        [Vector2(-5.35, -4.40), 1, 0, 12, 1.10],
        [Vector2(3.60, 5.00), 3, 0, 18, 1.60],
        [Vector2(-1.80, 4.60), 0, 1, 12, 1.20],
        [Vector2(11.00, 1.80), 2, 1, 16, 1.80],
        [Vector2(-13.00, 7.80), 1, 0, 14, 1.40],
        [Vector2(-9.20, 1.60), 0, 0, 12, 1.20],
        [Vector2(16.50, 7.50), 2, 0, 12, 1.40],
        [Vector2(6.50, -4.00), 3, 1, 12, 1.30],
        [Vector2(-14.00, -1.50), 1, 0, 12, 1.30],
        [Vector2(-4.00, -11.60), 3, 0, 14, 1.40],
        [Vector2(12.50, -11.50), 0, 1, 12, 1.50],
    ]

# --- tiny triangle/quad emitters with baked vertex colours (double sided) ------
static func _fl_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
    var n := (b - a).cross(c - a)
    if n.length_squared() < 1e-12:
        return
    n = n.normalized()
    st.set_normal(n)
    st.set_color(col)
    st.add_vertex(a)
    st.set_normal(n)
    st.set_color(col)
    st.add_vertex(b)
    st.set_normal(n)
    st.set_color(col)
    st.add_vertex(c)
    st.set_normal(-n)
    st.set_color(col)
    st.add_vertex(a)
    st.set_normal(-n)
    st.set_color(col)
    st.add_vertex(c)
    st.set_normal(-n)
    st.set_color(col)
    st.add_vertex(b)

static func _fl_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
    _fl_tri(st, a, b, c, col)
    _fl_tri(st, a, c, d, col)

static func _fl_ico(st: SurfaceTool, centre: Vector3, scl: Vector3, col: Color) -> void:
    var verts: Array = _ico_verts()
    var faces: Array = _ico_faces()
    var vs: Array = []
    for v in verts:
        vs.append(centre + (v as Vector3) * scl)
    for f in faces:
        _fl_tri(st, vs[f[0]], vs[f[1]], vs[f[2]], col)

# --- stem + leaves -----------------------------------------------------------
static func _flower_stem_mesh(species: int, height: float, bend: float) -> ArrayMesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var green := Color("5f7f4a")
    var green_l := Color("7d9a5e")
    var green_d := Color("47613a")
    var sides := 4
    var segs := 4
    var pts: Array = []
    for i in range(segs + 1):
        var t := float(i) / float(segs)
        pts.append(Vector3(bend * height * t * t, height * t, 0.0))
    for i in range(segs):
        var p0: Vector3 = pts[i]
        var p1: Vector3 = pts[i + 1]
        var r0 := lerpf(0.0110, 0.0058, float(i) / float(segs))
        var r1 := lerpf(0.0110, 0.0058, float(i + 1) / float(segs))
        var c := green_d.lerp(green, float(i) / float(segs))
        for k in range(sides):
            var a0 := TAU * float(k) / float(sides)
            var a1 := TAU * float(k + 1) / float(sides)
            var o0 := Vector3(cos(a0) * r0, 0.0, sin(a0) * r0)
            var o1 := Vector3(cos(a1) * r0, 0.0, sin(a1) * r0)
            var o2 := Vector3(cos(a0) * r1, 0.0, sin(a0) * r1)
            var o3 := Vector3(cos(a1) * r1, 0.0, sin(a1) * r1)
            _fl_quad(st, p0 + o0, p0 + o1, p1 + o3, p1 + o2, c)
    # two leaves, one on each side of the lower stem
    var leaf_specs := [[0.30, 0.95, 0.115], [0.55, -0.85, 0.095]]
    for ls in leaf_specs:
        var t: float = ls[0]
        var ang: float = ls[1]
        var ln: float = ls[2]
        var base := Vector3(bend * height * t * t, height * t, 0.0)
        var dir := Vector3(cos(ang), 0.26, sin(ang)).normalized()
        var side := dir.cross(Vector3.UP).normalized()
        var p1 := base + dir * ln * 0.45 + Vector3(0.0, ln * 0.07, 0.0)
        var p2 := base + dir * ln + Vector3(0.0, ln * 0.20, 0.0)
        var w := ln * 0.30
        _fl_quad(st, base - side * 0.004, base + side * 0.004, p1 + side * w, p1 - side * w, green_l.darkened(0.05))
        _fl_quad(st, p1 - side * w, p1 + side * w, p2, p2 - side * 0.004, green_l)
    return st.commit()

# --- tulip: closed cup of 6 petals (3 outer + 3 inner) -----------------------
static func _tulip_head_mesh(col: Color, height: float, bend: float) -> ArrayMesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var top := Vector3(bend * height, height, 0.0)
    var cup := Color("3f6b3a")
    var petal := col
    # green receptacle at the tip of the stem
    for k in range(5):
        var a0 := TAU * float(k) / 5.0
        var a1 := TAU * float(k + 1) / 5.0
        var v0 := top + Vector3(cos(a0) * 0.024, 0.006, sin(a0) * 0.024)
        var v1 := top + Vector3(cos(a1) * 0.024, 0.006, sin(a1) * 0.024)
        _fl_tri(st, top, v0, v1, cup)
    for ring in range(2):
        var pn := 3
        var rot := 0.0 if ring == 0 else PI / 3.0
        var ln := 0.125 if ring == 0 else 0.108
        var wid := 0.048 if ring == 0 else 0.042
        var raise := 0.0 if ring == 0 else 0.016
        for k in range(pn):
            var ang := rot + TAU * float(k) / float(pn)
            var radial := Vector3(cos(ang), 0.0, sin(ang))
            var tangent := Vector3(-sin(ang), 0.0, cos(ang))
            var base := top + radial * 0.014 + Vector3(0.0, 0.012 + raise, 0.0)
            var prev_l := Vector3.ZERO
            var prev_r := Vector3.ZERO
            for i in range(4):
                var t := float(i) / 3.0
                var out := ln * (sin(PI * t * 0.60) - 0.24 * t * t)
                var up := ln * (0.40 * t + 0.90 * t * t)
                var p := base + radial * out + Vector3(0.0, up, 0.0)
                var hw := wid * (0.30 + 0.70 * sin(PI * clampf(t * 1.12, 0.0, 1.0)))
                var l := p - tangent * hw
                var r := p + tangent * hw
                if i > 0:
                    _fl_quad(st, prev_l, prev_r, r, l, petal.lerp(petal.darkened(0.18), t * 0.75))
                prev_l = l
                prev_r = r
    return st.commit()

# --- daisy: 12 flat white petals + yellow disc --------------------------------
static func _daisy_head_mesh(height: float, bend: float) -> ArrayMesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var top := Vector3(bend * height, height, 0.0)
    var petal := Color("f3ead6")
    var petal_d := Color("d8cdb6")
    # green calyx
    for k in range(6):
        var a0 := TAU * float(k) / 6.0
        var a1 := TAU * float(k + 1) / 6.0
        _fl_tri(st, top + Vector3(0.0, -0.010, 0.0), top + Vector3(cos(a0) * 0.020, 0.004, sin(a0) * 0.020), top + Vector3(cos(a1) * 0.020, 0.004, sin(a1) * 0.020), Color("5f7f4a"))
    var n := 12
    for k in range(n):
        var ang := TAU * float(k) / float(n)
        var radial := Vector3(cos(ang), 0.0, sin(ang))
        var tangent := Vector3(-sin(ang), 0.0, cos(ang))
        var base := top + radial * 0.016 + Vector3(0.0, 0.006, 0.0)
        var ln := 0.082 + 0.010 * float(k % 2)
        var prev_l := Vector3.ZERO
        var prev_r := Vector3.ZERO
        for i in range(3):
            var t := float(i) / 2.0
            var p := base + radial * (ln * t) + Vector3(0.0, ln * 0.13 * t * t, 0.0)
            var hw := 0.017 * (0.35 + 0.65 * sin(PI * clampf(t * 1.10, 0.0, 1.0)))
            var l := p - tangent * hw
            var r := p + tangent * hw
            if i > 0:
                _fl_quad(st, prev_l, prev_r, r, l, petal.lerp(petal_d, t * 0.55))
            prev_l = l
            prev_r = r
    _fl_ico(st, top + Vector3(0.0, 0.018, 0.0), Vector3(0.034, 0.020, 0.034), Color("e9c86a"))
    return st.commit()

# --- bluebell: arched stem with 4 hanging bell flowers -----------------------
static func _bluebell_head_mesh(col: Color, height: float, bend: float) -> ArrayMesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for b in range(4):
        var t := 0.58 + 0.125 * float(b)
        var attach := Vector3(bend * height * t * t, height * t, 0.0)
        var hang := Vector3(0.018 * float(b % 2), -0.072 - 0.008 * float(b % 2), 0.014 * float(b % 2))
        var bot := attach + hang
        for k in range(6):
            var a0 := TAU * float(k) / 6.0
            var a1 := TAU * float(k + 1) / 6.0
            var r0 := 0.008
            var r1 := 0.022
            var o0 := Vector3(cos(a0) * r0, 0.0, sin(a0) * r0)
            var o1 := Vector3(cos(a1) * r0, 0.0, sin(a1) * r0)
            var o2 := Vector3(cos(a0) * r1, 0.0, sin(a0) * r1)
            var o3 := Vector3(cos(a1) * r1, 0.0, sin(a1) * r1)
            _fl_quad(st, attach + o0, attach + o1, bot + o3, bot + o2, col.lerp(col.darkened(0.22), 0.45))
            var mid_ang := (a0 + a1) * 0.5
            var tip := bot + Vector3(cos(mid_ang) * 0.028, -0.014, sin(mid_ang) * 0.028)
            _fl_tri(st, bot + o2, bot + o3, tip, col.lightened(0.10))
    return st.commit()

# --- poppy: 4 crinkled petals + dark centre ---------------------------------
static func _poppy_head_mesh(col: Color, height: float, bend: float) -> ArrayMesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var top := Vector3(bend * height, height, 0.0)
    var petal := col
    for k in range(4):
        var ang := TAU * float(k) / 4.0 + 0.35
        var radial := Vector3(cos(ang), 0.0, sin(ang))
        var tangent := Vector3(-sin(ang), 0.0, cos(ang))
        var base := top + radial * 0.008 + Vector3(0.0, 0.004, 0.0)
        var ln := 0.070
        var prev_l := Vector3.ZERO
        var prev_r := Vector3.ZERO
        for i in range(4):
            var t := float(i) / 3.0
            var p := base + radial * (ln * t) + Vector3(0.0, 0.020 * (1.0 - t) + 0.045 * t * t, 0.0)
            p += radial * (0.005 * sin(t * PI * 3.0 + float(k) * 1.3))
            var hw := 0.052 * (0.42 + 0.58 * sin(PI * clampf(t * 1.06, 0.0, 1.0)))
            var l := p - tangent * hw
            var r := p + tangent * hw
            if i > 0:
                _fl_quad(st, prev_l, prev_r, r, l, petal.lerp(petal.darkened(0.24), t * 0.55))
            prev_l = l
            prev_r = r
    _fl_ico(st, top + Vector3(0.0, 0.030, 0.0), Vector3(0.040, 0.024, 0.040), Color("3a3230"))
    for k in range(6):
        var a := TAU * float(k) / 6.0
        var b := a + 0.5
        _fl_tri(st, top + Vector3(0.0, 0.046, 0.0), top + Vector3(cos(a) * 0.020, 0.040, sin(a) * 0.020), top + Vector3(cos(b) * 0.024, 0.041, sin(b) * 0.024), Color("c9b48a"))
    return st.commit()

static func _flower_head_mesh(species: int, variant: int, height: float, bend: float) -> ArrayMesh:
    var sp: Dictionary = _flower_species()[species]
    var variants: Array = sp["variants"]
    var col := Color(str(variants[variant]))
    match species:
        0:
            return _tulip_head_mesh(col, height, bend)
        1:
            return _daisy_head_mesh(height, bend)
        2:
            return _bluebell_head_mesh(col, height, bend)
        _:
            return _poppy_head_mesh(col, height, bend)

static func _scatter_flowers(root: Node3D) -> Dictionary:
    var species := _flower_species()
    var stats: Dictionary = {"species": {}, "total": 0, "clusters": 0, "head_meshes": 0}
    for sp in species:
        stats["species"][str(sp["name"])] = 0
    var stem_meshes: Array = []
    var head_meshes: Array = []
    for si in range(species.size()):
        var sp: Dictionary = species[si]
        var h: float = sp["height"]
        var b: float = sp["bend"]
        stem_meshes.append(_flower_stem_mesh(si, h, b))
        var vlist: Array = []
        for vi in range((sp["variants"] as Array).size()):
            vlist.append(_flower_head_mesh(si, vi, h, b))
        head_meshes.append(vlist)
    var stem_xf: Array = []
    var head_xf: Array = []
    for si in range(species.size()):
        stem_xf.append([])
        head_xf.append([])
        for vi in range((species[si]["variants"] as Array).size()):
            head_xf[si].append([])
    var rng := RandomNumberGenerator.new()
    rng.seed = 424242
    var clusters := _flower_clusters()
    for entry in clusters:
        var centre: Vector2 = entry[0]
        var si: int = entry[1]
        var vi: int = entry[2]
        var count: int = entry[3]
        var radius: float = entry[4]
        var placed := 0
        var guard := 0
        while placed < count and guard < count * 50:
            guard += 1
            var ang := rng.randf() * TAU
            var rr := radius * sqrt(rng.randf())
            var x := centre.x + cos(ang) * rr
            var z := centre.y + sin(ang) * rr
            var gy := _grass_spot(x, z)
            if gy <= 0.0:
                continue
            var s := 0.86 + rng.randf() * 0.38
            var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(x, gy - 0.01, z))
            stem_xf[si].append(xf)
            head_xf[si][vi].append(xf)
            placed += 1
    # tidy rows inside the four raised beds
    var bed_species := [[1, 0], [3, 1], [0, 0], [2, 0]]
    for bi in range(_bed_rects.size()):
        var r: Vector4 = _bed_rects[bi]
        var cfg: Array = bed_species[bi % bed_species.size()]
        var si: int = cfg[0]
        var vi: int = cfg[1]
        var top := _bed_top(r)
        for row in range(2):
            for col_i in range(5):
                var x := lerpf(r.x, r.y, 0.20 + 0.15 * float(col_i))
                var z := lerpf(r.z, r.w, 0.34 + 0.32 * float(row))
                var s := 0.92 + 0.10 * float((row + col_i) % 3)
                var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(x, top, z))
                stem_xf[si].append(xf)
                head_xf[si][vi].append(xf)
    var mat_flower := M.toon_material(Color.WHITE, {"vertex_color": true, "bands": 3, "rim": 0.04, "outline": 0.0})
    for si in range(species.size()):
        M.multis(root, "FlowerStems_" + str(species[si]["name"]), stem_meshes[si], stem_xf[si], [], mat_flower)
        stats["total"] += stem_xf[si].size()
        for vi in range(head_xf[si].size()):
            var list: Array = head_xf[si][vi]
            if list.is_empty():
                continue
            var nm := "FlowerHeads_%s_%d" % [str(species[si]["name"]), vi]
            M.multis(root, nm, head_meshes[si][vi], list, [], mat_flower)
            stats["species"][str(species[si]["name"])] += list.size()
            stats["head_meshes"] += 1
    stats["clusters"] = clusters.size() + _bed_rects.size()
    return stats

# ====================================================== winter ground blooms ==
# P8.1: five red winter poppies on the front lawn (never on the tree). They are a
# dedicated pair of MultiMeshes (stem + poppy head, same transforms) so they do not
# depend on _grass_spot / flower_keep and stay invisible except in winter. The main
# script re-writes their transforms every season update to bloom in/out.
# Node names must NOT start with "Flower": _setup_season_visuals() picks those up.
static func _winter_blooms(root: Node3D) -> Dictionary:
    var rng := RandomNumberGenerator.new()
    rng.seed = 8102
    # world XZ anchors (front lawn, checked against _in_porch / path clearance).
    var spots := [
        Vector2(0.123, 8.716),
        Vector2(1.285, 9.089),
        Vector2(1.968, 8.250),
        Vector2(1.014, 9.906),
        Vector2(-0.309, 9.687),
    ]
    var xforms: Array = []
    var base: Array = []
    for i in range(spots.size()):
        var xz: Vector2 = spots[i]
        var gy := _h(xz.x, xz.y) - 0.01
        var yaw := rng.randf_range(0.0, TAU)
        # P8.1：放大花株，让 5 朵红花在深色冬草上可读。
        var s := rng.randf_range(1.30, 1.60)
        var pos := Vector3(xz.x, gy, xz.y)
        xforms.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), pos))
        base.append({"pos": pos, "yaw": yaw, "scale": s})
    var mat_flower := M.toon_material(Color.WHITE,
        {"vertex_color": true, "bands": 3.0, "rim": 0.04, "outline": 0.0})
    # P8.1：花头抬到 0.62 m 并改用亮朱红——旧 c0392b 在阴天绿草里几乎读不出红。
    var bloom_h := 0.62
    var stems := M.multis(root, "WinterBloomStems",
        _flower_stem_mesh(3, bloom_h, 0.06), xforms, [], mat_flower)
    var heads := M.multis(root, "WinterBloomHeads",
        _poppy_head_mesh(Color("e14a3f"), bloom_h, 0.06), xforms, [], mat_flower)
    stems.visible = false
    heads.visible = false
    return {"stems": stems, "heads": heads, "base": base}

# =============================================================== bushes ====
static func _bush_spot(x: float, z: float) -> float:
    var n := _norm_radius(x, z)
    if n < 0.05 or n > 0.86:
        return 0.0
    if _in_house(x, z, 0.6) or _in_porch(x, z, 0.8) or _in_garden(x, z, 0.15) or _in_field(x, z, 0.1):
        return 0.0
    var wmx := x - LIGHTHOUSE_X
    var wmz := z - LIGHTHOUSE_Z
    if wmx * wmx + wmz * wmz < 17.0:
        return 0.0
    if _path_clearance(x, z) < 0.55:
        return 0.0
    if _tree_min_dist(x, z) < 1.3:
        return 0.0
    var h := _h(x, z)
    if h < 0.9 or _hn(x, z).y < 0.65:
        return 0.0
    return h

static func _scatter_bushes(root: Node3D) -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = 55109
    var specs := [
        [Vector2(-12.4, 0.6), 6, 1.8],
        [Vector2(-7.2, 8.6), 5, 1.6],
        [Vector2(5.2, 6.4), 6, 1.8],
        [Vector2(15.2, 9.0), 6, 2.0],
        [Vector2(8.0, -6.0), 5, 1.6],
        [Vector2(-14.6, 5.2), 5, 1.6],
        [Vector2(13.0, 4.6), 5, 1.6],
        [Vector2(-3.0, -3.2), 4, 1.2],
        [Vector2(-11.6, -10.0), 5, 1.6],
        [Vector2(10.4, 12.4), 5, 1.8],
        [Vector2(-5.45, -7.6), 3, 0.5],
        [Vector2(-10.3, -7.4), 3, 0.6],
    ]
    var xforms: Array = []
    var colors: Array = []
    for spec in specs:
        var centre: Vector2 = spec[0]
        var count: int = spec[1]
        var radius: float = spec[2]
        for i in range(count):
            var a := rng.randf_range(0.0, TAU)
            var rr := rng.randf_range(0.0, radius)
            var x := centre.x + cos(a) * rr
            var z := centre.y + sin(a) * rr
            var h := _bush_spot(x, z)
            if h <= 0.0:
                continue
            var sx := rng.randf_range(0.30, 0.60)
            var sy := rng.randf_range(0.22, 0.42)
            var sz := rng.randf_range(0.30, 0.60)
            xforms.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(sx, sy, sz)),
                Vector3(x, h + sy * 0.30, z)))
            var col := M.C_LEAF_C.lerp(M.C_LEAF_B, rng.randf())
            col = col.lerp(Color("94a86e"), rng.randf() * 0.35)
            colors.append(col)
    M.multis(root, "Bushes", _sphere_mesh(8, 5), xforms, colors,
        M.toon_material(Color.WHITE, {"vertex_color": true, "bands": 3.0, "rim": 0.12, "wind": 0.1}))

# ======================================================= shared mesh cache ==
static var _sphere_cache: Dictionary = {}
static var _cyl_cache: Dictionary = {}

static func _sphere_mesh(radial: int, rings: int) -> SphereMesh:
    var key := str(radial) + "_" + str(rings)
    if _sphere_cache.has(key):
        return _sphere_cache[key]
    var sm := SphereMesh.new()
    sm.radius = 1.0
    sm.height = 2.0
    sm.radial_segments = radial
    sm.rings = rings
    _sphere_cache[key] = sm
    return sm

static func _cylinder_mesh(top_r: float, bot_r: float, h: float, sides: int) -> CylinderMesh:
    var key := "c" + str(snappedf(top_r, 0.001)) + "_" + str(snappedf(bot_r, 0.001)) + "_" + str(h) + "_" + str(sides)
    if _cyl_cache.has(key):
        return _cyl_cache[key]
    var cm := CylinderMesh.new()
    cm.top_radius = top_r
    cm.bottom_radius = bot_r
    cm.height = h
    cm.radial_segments = sides
    cm.rings = 1
    _cyl_cache[key] = cm
    return cm

# ------------------------------------------------------- geometry helper ---
## Adds a quad (two windings, flat normal) to a SurfaceTool.
static func _add_quad2(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, nrm: Vector3) -> void:
    st.set_normal(nrm)
    st.add_vertex(a)
    st.add_vertex(b)
    st.add_vertex(c)
    st.set_normal(nrm)
    st.add_vertex(a)
    st.add_vertex(c)
    st.add_vertex(d)
    var nb := -nrm
    st.set_normal(nb)
    st.add_vertex(a)
    st.add_vertex(c)
    st.add_vertex(b)
    st.set_normal(nb)
    st.add_vertex(a)
    st.add_vertex(d)
    st.add_vertex(c)

## Tapered cylinder between two points (used for trunks, branches, ropes, poles).
static func _seg(parent: Node3D, a: Vector3, b: Vector3, r0: float, r1: float,
        color: Color, opts: Dictionary = {}, sides: int = 7) -> MeshInstance3D:
    var dirv := b - a
    var length := maxf(dirv.length(), 0.001)
    var mi := MeshInstance3D.new()
    var cm := CylinderMesh.new()
    cm.top_radius = r1
    cm.bottom_radius = r0
    cm.height = length
    cm.radial_segments = sides
    cm.rings = 1
    mi.mesh = cm
    mi.material_override = M.toon_material(color, opts)
    mi.position = (a + b) * 0.5
    mi.quaternion = Quaternion(Vector3.UP, dirv / length)
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    parent.add_child(mi)
    return mi

## Box beam between two points (length along the segment, no roll).
static func _bar(parent: Node3D, a: Vector3, b: Vector3, w: float, h: float,
        color: Color, opts: Dictionary = {}) -> MeshInstance3D:
    var dirv := b - a
    var length := maxf(dirv.length(), 0.001)
    var zaxis := dirv / length
    var xaxis := Vector3.UP.cross(zaxis)
    if xaxis.length_squared() < 0.0001:
        xaxis = Vector3.RIGHT
    xaxis = xaxis.normalized()
    var yaxis := zaxis.cross(xaxis).normalized()
    var mi := MeshInstance3D.new()
    var bm := BoxMesh.new()
    bm.size = Vector3(w, h, length)
    mi.mesh = bm
    mi.material_override = M.toon_material(color, opts)
    mi.transform = Transform3D(Basis(xaxis, yaxis, zaxis), (a + b) * 0.5)
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    parent.add_child(mi)
    return mi

# ================================================================= rocks ===
# Six rock families, two LOD meshes each:
#   near mesh = exactly 320 triangles, far mesh = exactly 80 triangles,
#   single winding (so the mesh triangle count equals the budget).
# Families 0/3/5 (pebble / large reef / tidal wet rock) use smooth averaged
# normals, families 1/2/4 (angular block / flat slab / cluster rock) use hard
# per-face normals. Colour layers are baked into vertex colours.

static func _ico_verts() -> Array:
    var t := (1.0 + sqrt(5.0)) * 0.5
    return [
        Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
        Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
        Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1),
    ]

static func _ico_faces() -> Array:
    return [
        [0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
        [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
        [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
        [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
    ]

static func _ico_mid(verts: Array, cache: Dictionary, i0: int, i1: int) -> int:
    var key := i0 * 100000 + i1 if i0 < i1 else i1 * 100000 + i0
    if cache.has(key):
        return int(cache[key])
    var v: Vector3 = ((verts[i0] as Vector3) + (verts[i1] as Vector3)).normalized()
    verts.append(v)
    cache[key] = verts.size() - 1
    return verts.size() - 1

# Returns {"verts": Array[Vector3], "tris": Array[[i0,i1,i2]]}.
# subdiv 0 => 20 tris, 1 => 80 tris, 2 => 320 tris.
static func _ico_sphere(subdiv: int) -> Dictionary:
    var verts: Array = []
    for v in _ico_verts():
        verts.append((v as Vector3).normalized())
    var faces: Array = []
    for f in _ico_faces():
        faces.append([int(f[0]), int(f[1]), int(f[2])])
    for _lv in range(subdiv):
        var cache: Dictionary = {}
        var nxt: Array = []
        for f in faces:
            var a: int = f[0]
            var b: int = f[1]
            var c: int = f[2]
            var ab := _ico_mid(verts, cache, a, b)
            var bc := _ico_mid(verts, cache, b, c)
            var ca := _ico_mid(verts, cache, c, a)
            nxt.append([a, ab, ca])
            nxt.append([b, bc, ab])
            nxt.append([c, ca, bc])
            nxt.append([ab, bc, ca])
        faces = nxt
    return {"verts": verts, "tris": faces}

static func _rock_families() -> Array:
    return ["Pebble", "AngularBlock", "FlatSlab", "LargeReef", "ClusterRock", "TidalWetRock"]

static func _rock_family_smooth() -> Array:
    return [true, false, false, true, false, true]

# Deterministic shape deformation of a unit-sphere point for each family.
static func _rock_deform(kind: int, p: Vector3, seed_val: int) -> Vector3:
    var nrm := p.normalized()
    var n1 := M.noise01(nrm.x * 2.7 + nrm.y * 1.9 + float(seed_val) * 0.37, nrm.z * 2.3 - nrm.y * 1.1)
    var n2 := M.noise01(nrm.x * 5.9 - 1.7, nrm.z * 5.1 + 2.3)
    var q := p
    match kind:
        0:  # pebble: rounded, flattened river stone
            q *= 1.0 + 0.16 * n1 + 0.05 * n2
            q.y *= 0.62
        1:  # angular block: cube-ish fractured block
            var m := maxf(absf(q.x), maxf(absf(q.y), absf(q.z)))
            var cube := q / maxf(m, 1e-4) * 0.86
            q = q.lerp(cube, 0.55)
            q *= 1.0 + 0.20 * n1
            q.y *= 0.94
        2:  # flat slab: wide, thin, layered
            q.x *= 1.55
            q.z *= 1.28
            q.y *= 0.20
            q *= 1.0 + 0.10 * n1
            q.y += 0.06 * sin(q.x * 9.0 + n2 * 6.0)
        3:  # large reef: tall, chunky, wave-beaten
            q *= 1.0 + 0.34 * n1 + 0.10 * n2
            q.y *= 0.74
            q.x += 0.10 * q.y * n1
        4:  # cluster rock (single lobe form, repeated per lobe)
            q *= 1.0 + 0.22 * n1 + 0.07 * n2
            q.y *= 0.80
        _:  # tidal wet rock: low, wide, smooth
            q.y *= 0.30
            q.x *= 1.25
            q.z *= 1.10
            q *= 1.0 + 0.14 * n1
            q.y = maxf(q.y, -0.10)
    return q

# Layered rock colour: sediment bands, darker wet base, bleached top, algae.
static func _rock_layer_color(kind: int, p: Vector3, shade: float, seed_val: int) -> Color:
    var base := Color("9c9282")
    var light := Color("b8ae9a")
    match kind:
        0:
            base = Color("9c9282")
            light = Color("b8ae9a")
        1:
            base = Color("8b8274")
            light = Color("a79c8a")
        2:
            base = Color("a2988a")
            light = Color("bcb2a0")
        3:
            base = Color("7f7668")
            light = Color("9a9082")
        4:
            base = Color("8d8476")
            light = Color("a89d8a")
        _:
            base = Color("6f6a60")
            light = Color("8f8a7e")
    var t := clampf(p.y * 0.5 + 0.5, 0.0, 1.0)
    var col := base.lerp(light, smoothstep(0.15, 0.95, t) * 0.75)
    if kind == 2:
        var band := 0.5 + 0.5 * sin(p.y * 34.0 + 0.7 + float(seed_val) * 0.01)
        col = col.lerp(base.darkened(0.18), band * 0.30)
    if kind == 3:
        col = col.lerp(Color("66735e"), smoothstep(0.10, -0.35, p.y) * 0.30)
    if kind == 4:
        col = col.lerp(Color("6f7a5c"), smoothstep(0.35, 0.90, t) * 0.22)
    if kind == 5:
        col = col.lerp(Color("4a4f47"), smoothstep(-0.02, -0.30, p.y) * 0.55)
        col = col.lerp(Color("7d8a6a"), smoothstep(0.10, 0.45, t) * 0.18)
    var f := 0.90 + 0.20 * shade
    return Color(col.r * f, col.g * f, col.b * f, 1.0)

static func _flat_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3,
        ca: Color, cb: Color, cc: Color) -> void:
    st.set_normal(n)
    st.set_color(ca)
    st.add_vertex(a)
    st.set_normal(n)
    st.set_color(cb)
    st.add_vertex(b)
    st.set_normal(n)
    st.set_color(cc)
    st.add_vertex(c)

static func _smooth_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
        na: Vector3, nb: Vector3, nc: Vector3, ca: Color, cb: Color, cc: Color) -> void:
    st.set_normal(na)
    st.set_color(ca)
    st.add_vertex(a)
    st.set_normal(nb)
    st.set_color(cb)
    st.add_vertex(b)
    st.set_normal(nc)
    st.set_color(cc)
    st.add_vertex(c)

static func _emit_rock_form(st: SurfaceTool, form: Dictionary, kind: int, seed_val: int,
        xf: Transform3D, smooth: bool) -> void:
    var verts: Array = form["verts"]
    var tris: Array = form["tris"]
    var pos: Array = []
    var cols: Array = []
    var nrms: Array = []
    for i in range(verts.size()):
        var p: Vector3 = xf * _rock_deform(kind, verts[i] as Vector3, seed_val)
        pos.append(p)
        var shade := M.noise01(p.x * 3.1 + float(seed_val) * 0.13, p.z * 2.9 - p.y * 1.7)
        cols.append(_rock_layer_color(kind, p, shade, seed_val))
        if smooth:
            var n: Vector3 = p.normalized()
            n.y = maxf(n.y, 0.05)
            nrms.append(n.normalized())
        else:
            nrms.append(Vector3.ZERO)
    for f in tris:
        var ia: int = f[0]
        var ib: int = f[1]
        var ic: int = f[2]
        var pa: Vector3 = pos[ia]
        var pb: Vector3 = pos[ib]
        var pc: Vector3 = pos[ic]
        var fn := (pb - pa).cross(pc - pa)
        if fn.length_squared() < 1e-12:
            continue
        fn = fn.normalized()
        # Godot front faces are clockwise from outside => emit (a, c, b).
        if smooth:
            _smooth_tri(st, pa, pc, pb, nrms[ia], nrms[ic], nrms[ib], cols[ia], cols[ic], cols[ib])
        else:
            _flat_tri(st, pa, pc, pb, fn, cols[ia], cols[ic], cols[ib])

static func _rock_mesh(kind: int, near: bool, seed_val: int) -> ArrayMesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var smooth := bool(_rock_family_smooth()[kind])
    if kind == 4:
        # Cluster rock: four merged lobes (near 4*80 = 320 tris, far 4*20 = 80).
        var subdiv := 1 if near else 0
        var lobes := [
            [Vector3(-0.36, 0.02, -0.10), 0.80, seed_val + 3],
            [Vector3(0.36, 0.14, 0.14), 0.88, seed_val + 7],
            [Vector3(0.02, 0.32, -0.30), 0.66, seed_val + 11],
            [Vector3(0.06, -0.10, 0.36), 0.72, seed_val + 17],
        ]
        for lobe in lobes:
            var c: Vector3 = lobe[0]
            var s: float = lobe[1]
            var sd: int = lobe[2]
            var xf := Transform3D(Basis.from_scale(Vector3(s, s, s)), c)
            _emit_rock_form(st, _ico_sphere(subdiv), kind, sd, xf, smooth)
        return st.commit()
    var subdiv2 := 2 if near else 1
    _emit_rock_form(st, _ico_sphere(subdiv2), kind, seed_val, Transform3D(), smooth)
    return st.commit()

static func _mesh_tri_count(mesh: ArrayMesh) -> int:
    if mesh == null or mesh.get_surface_count() == 0:
        return 0
    var arr := mesh.surface_get_arrays(0)
    var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
    return v.size() / 3

static func _rock_xform(x: float, z: float, sc: float, rng: RandomNumberGenerator, embed: float) -> Transform3D:
    var sx := sc * rng.randf_range(0.85, 1.35)
    var sy := sc * rng.randf_range(0.72, 1.12)
    var sz := sc * rng.randf_range(0.85, 1.30)
    var y := _h(x, z) - sy * embed
    var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sx, sy, sz))
    return Transform3D(basis, Vector3(x, y, z))

static func _route_clearance(x: float, z: float) -> float:
    if _sail_segs.is_empty():
        return 999.0
    var best := 999.0
    for s in _sail_segs:
        var d := _seg_dist_2d(x, z, s[0], s[1])
        if d < best:
            best = d
    return best

# Placement guard: rocks keep clear of the house, porch, garden, field, paths,
# the dock, the big trees and every sail route.
static func _rock_clearance_ok(x: float, z: float, r: float) -> bool:
    if _in_house(x, z, 0.60 + r):
        return false
    if _in_porch(x, z, 0.55 + r):
        return false
    if _in_garden(x, z, 0.45 + r):
        return false
    if _in_field(x, z, 0.45 + r):
        return false
    if _path_clearance(x, z) < 0.18 + r:
        return false
    if _dock_clearance(x, z) < 1.0 + r:
        return false
    if _tree_min_dist(x, z) < 1.30 + r:
        return false
    if _route_clearance(x, z) < 3.0 + r:
        return false
    return true

static func _rock_place(layers: Array, rng: RandomNumberGenerator, kind: int, x: float, z: float,
        sc: float, embed: float) -> void:
    var xf := _rock_xform(x, z, sc, rng, embed)
    layers[kind]["near"].append(xf)
    layers[kind]["far"].append(xf)

static func _rocks(root: Node3D) -> Dictionary:
    var rng := RandomNumberGenerator.new()
    rng.seed = 90210
    var families := _rock_families()
    var smooth := _rock_family_smooth()
    var near_meshes: Array = []
    var far_meshes: Array = []
    for kind in range(families.size()):
        var sd := 7000 + kind * 131
        near_meshes.append(_rock_mesh(kind, true, sd))
        far_meshes.append(_rock_mesh(kind, false, sd))
    var layers: Array = []
    for kind in range(families.size()):
        layers.append({"near": [], "far": []})

    # ---- shoreline clusters: large reefs, angular blocks, slabs, wet rocks ----
    for i in range(14):
        var ang := rng.randf() * TAU
        var n := rng.randf_range(0.94, 1.03)
        var cx := cos(ang) * M.coast_radius(ang) * n
        var cz := sin(ang) * M.coast_radius(ang) * n
        var group_scale := rng.randf_range(0.85, 1.55)
        for j in range(rng.randi_range(3, 6)):
            var x := cx + rng.randf_range(-2.4, 2.4)
            var z := cz + rng.randf_range(-2.4, 2.4)
            var pick := rng.randf()
            var kind := 3
            if pick < 0.28:
                kind = 3
            elif pick < 0.52:
                kind = 1
            elif pick < 0.72:
                kind = 2
            elif pick < 0.88:
                kind = 5
            else:
                kind = 4
            var sc := group_scale * rng.randf_range(0.40, 0.95)
            if not _rock_clearance_ok(x, z, sc * 0.9):
                continue
            _rock_place(layers, rng, kind, x, z, sc, 0.55)

    # ---- tidal wet rocks: low smooth boulders right at the waterline ----
    for i in range(22):
        var ang := rng.randf() * TAU
        var n := rng.randf_range(0.97, 1.05)
        var x := cos(ang) * M.coast_radius(ang) * n
        var z := sin(ang) * M.coast_radius(ang) * n
        if not _rock_clearance_ok(x, z, 0.5):
            continue
        _rock_place(layers, rng, 5, x, z, rng.randf_range(0.30, 0.85), 0.68)

    # ---- flat slabs half-buried in the sand ----
    for i in range(16):
        var ang := rng.randf() * TAU
        var n := rng.randf_range(0.93, 1.02)
        var x := cos(ang) * M.coast_radius(ang) * n
        var z := sin(ang) * M.coast_radius(ang) * n
        if not _rock_clearance_ok(x, z, 0.7):
            continue
        _rock_place(layers, rng, 2, x, z, rng.randf_range(0.45, 1.05), 0.62)

    # ---- inland boulder spots: rocky meadow landmarks ----
    var spots := [
        [Vector2(-16.5, -6.0), 1.10], [Vector2(15.5, -7.5), 1.00], [Vector2(-3.6, 10.5), 0.90],
        [Vector2(9.8, 6.8), 1.20], [Vector2(-12.5, 13.0), 1.00], [Vector2(18.5, 2.0), 0.85],
        [Vector2(2.5, -15.0), 1.10], [Vector2(-18.0, 2.0), 0.90], [Vector2(-6.9, 12.9), 0.85],
    ]
    for spot in spots:
        var c: Vector2 = spot[0]
        var sc0: float = spot[1]
        var group_kind := 4 if rng.randf() < 0.55 else 3
        var placed := 0
        var guard := 0
        while placed < 4 and guard < 30:
            guard += 1
            var x := c.x + rng.randf_range(-2.0, 2.0)
            var z := c.y + rng.randf_range(-2.0, 2.0)
            if not _rock_clearance_ok(x, z, sc0):
                continue
            var kind := group_kind
            if placed > 0:
                kind = 1 if rng.randf() < 0.45 else (4 if rng.randf() < 0.6 else 3)
            _rock_place(layers, rng, kind, x, z, sc0 * rng.randf_range(0.55, 1.05), 0.50)
            placed += 1
        M.shadow_blob(root, Vector3(c.x, _h(c.x, c.y) + 0.03, c.y), sc0 * 2.6, 0.28)

    # ---- path rubble: small stones at the verge of every trail ----
    var i := 0
    while i + 1 < _path_segs.size():
        var a: Vector2 = _path_segs[i]
        var b: Vector2 = _path_segs[i + 1]
        var w: float = _path_widths[i >> 1]
        var seg := b - a
        var ln := seg.length()
        if ln > 0.05:
            var dir := seg / ln
            var nrm := Vector2(-dir.y, dir.x)
            var t := 0.45
            while t < ln:
                for side in [-1.0, 1.0]:
                    var side_f: float = side
                    if rng.randf() < 0.70:
                        var off := w + rng.randf_range(0.10, 0.80)
                        var pp := a + dir * t + nrm * off * side_f
                        if _rock_clearance_ok(pp.x, pp.y, 0.18):
                            var kind := 0 if rng.randf() < 0.7 else 1
                            _rock_place(layers, rng, kind, pp.x, pp.y, rng.randf_range(0.07, 0.24), 0.55)
                t += rng.randf_range(0.8, 1.4)
        i += 2

    # ---- beach pebbles ----
    for k in range(240):
        var ang := rng.randf() * TAU
        var n := rng.randf_range(0.90, 1.03)
        var x := cos(ang) * M.coast_radius(ang) * n
        var z := sin(ang) * M.coast_radius(ang) * n
        if _dock_clearance(x, z) < 0.6:
            continue
        if _route_clearance(x, z) < 2.0:
            continue
        _rock_place(layers, rng, 0, x, z, rng.randf_range(0.06, 0.26), 0.60)

    var mat := M.toon_material(Color.WHITE, {"vertex_color": true, "bands": 3, "rim": 0.06, "outline": 0.015})
    # Placement audit (computed from the source transforms; MultiMesh buffers are
    # not readable in headless runs): how close did any rock end up to a route?
    var min_route_clear := 999.0
    var closest_rock := Vector3.ZERO
    for kind in range(families.size()):
        for xf in layers[kind]["near"]:
            var oo: Vector3 = (xf as Transform3D).origin
            var dd := _route_clearance(oo.x, oo.z)
            if dd < min_route_clear:
                min_route_clear = dd
                closest_rock = oo
    var stats: Dictionary = {
        "families": [], "near_tris": [], "far_tris": [],
        "near_instances": 0, "far_instances": 0, "per_family": [], "smooth": smooth,
        "min_route_clearance": min_route_clear, "closest_rock": closest_rock,
    }
    # Visual hero: the rock cluster showing the most distinct families inside one
    # camera frame (consumed by main.gd's screenshot routine to prove the six forms).
    var hero_best := 0
    var hero_pos := Vector3.ZERO
    for kind in range(families.size()):
        for xf in layers[kind]["near"]:
            var ho: Vector3 = (xf as Transform3D).origin
            var near_kinds := {}
            for k2 in range(families.size()):
                for xf2 in layers[k2]["near"]:
                    if (xf2 as Transform3D).origin.distance_squared_to(ho) < 20.25:
                        near_kinds[k2] = true
            if near_kinds.size() > hero_best:
                hero_best = near_kinds.size()
                hero_pos = ho
    stats["hero_pos"] = hero_pos
    stats["hero_kinds"] = hero_best
    for kind in range(families.size()):
        var nx: Array = layers[kind]["near"]
        var fx: Array = layers[kind]["far"]
        var near_node := M.multis(root, "Rocks_%s_Near" % families[kind], near_meshes[kind], nx, [], mat)
        var far_node := M.multis(root, "Rocks_%s_Far" % families[kind], far_meshes[kind], fx, [], mat)
        near_node.visibility_range_end = 28.0
        far_node.visibility_range_begin = 24.0
        stats["families"].append(families[kind])
        stats["near_tris"].append(_mesh_tri_count(near_meshes[kind]))
        stats["far_tris"].append(_mesh_tri_count(far_meshes[kind]))
        stats["near_instances"] += nx.size()
        stats["far_instances"] += fx.size()
        stats["per_family"].append(nx.size())
    return stats

# --------------------------------------------------------- stepping stones --
static func _stepping_stones(root: Node3D) -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = 30371
    var xf: Array = []
    var cols: Array = []
    var i := 0
    while i + 1 < _path_segs.size():
        var a: Vector2 = _path_segs[i]
        var b: Vector2 = _path_segs[i + 1]
        var length := a.distance_to(b)
        var steps := maxi(1, int(length / 0.72))
        for k in range(steps):
            var t := (float(k) + 0.5) / float(steps)
            var px := lerpf(a.x, b.x, t) + rng.randf_range(-0.10, 0.10)
            var pz := lerpf(a.y, b.y, t) + rng.randf_range(-0.10, 0.10)
            var h := _h(px, pz)
            var sc := rng.randf_range(0.23, 0.34)
            var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(
                Vector3(sc, rng.randf_range(0.05, 0.09), sc * rng.randf_range(0.7, 1.0)))
            xf.append(Transform3D(basis, Vector3(px, h + 0.035, pz)))
            cols.append(M.C_STONE.lerp(M.C_SAND, rng.randf() * 0.6).lerp(M.C_STONE_DARK, rng.randf() * 0.3))
        i += 2
    M.multis(root, "PathStones", _cylinder_mesh(1.0, 1.0, 1.0, 6), xf, cols,
        M.toon_material(Color.WHITE, {"vertex_color": true, "bands": 3.0, "rim": 0.06, "outline": 0.012}))

# ============================================================== big tree ====
static func _big_tree(root: Node3D) -> Dictionary:
    var px := M.BIG_TREE_X
    var pz := M.BIG_TREE_Z
    var base := Vector3(px, _h(px, pz), pz)
    var node := Node3D.new()
    node.name = "BigTree"
    node.position = base
    root.add_child(node)
    var rng := RandomNumberGenerator.new()
    rng.seed = 1207
    var o := {"outline": 0.05}
    var dark := M.C_WOOD_DARK
    var mid := M.C_WOOD.lerp(M.C_WOOD_DARK, 0.35)
    var light := M.C_WOOD
    # trunk: four tapered sections with a gentle lean
    _seg(node, Vector3(0.0, -0.45, 0.0), Vector3(0.10, 1.9, 0.06), 1.10, 0.86, dark, o, 10)
    _seg(node, Vector3(0.10, 1.9, 0.06), Vector3(0.26, 3.9, 0.02), 0.86, 0.70, dark, o, 10)
    _seg(node, Vector3(0.26, 3.9, 0.02), Vector3(0.34, 5.9, 0.00), 0.70, 0.56, mid, o, 9)
    _seg(node, Vector3(0.34, 5.9, 0.00), Vector3(0.22, 8.1, -0.05), 0.56, 0.34, mid, o, 9)
    _seg(node, Vector3(0.22, 8.1, -0.05), Vector3(0.10, 9.30, 0.02), 0.34, 0.13, light, o, 8)
    # exposed root claws that follow the terrain
    var root_dirs := [Vector2(1.0, 0.3), Vector2(-0.9, 0.5), Vector2(0.2, -1.0),
        Vector2(-0.5, -0.8), Vector2(0.78, 0.72)]
    for rd in root_dirs:
        var rdir: Vector2 = rd
        var rlen := rng.randf_range(2.1, 3.4)
        var ex := rdir.x * rlen
        var ez := rdir.y * rlen
        var end_local := Vector3(ex, _h(px + ex, pz + ez) + 0.02 - base.y, ez)
        var start := Vector3(rdir.x * 0.35, -0.30, rdir.y * 0.35)
        var midpt := Vector3(rdir.x * rlen * 0.55, -0.12, rdir.y * rlen * 0.55)
        _seg(node, start, midpt, 0.34, 0.20, dark, o, 7)
        _seg(node, midpt, end_local, 0.20, 0.07, dark, o, 6)
        M.sphere(node, rng.randf_range(0.16, 0.27), end_local, mid, Vector3(1.5, 0.55, 1.0), o)
    # four main branches plus secondary limbs
    var main_dirs := [Vector3(3.0, 1.2, 1.0), Vector3(-3.2, 1.5, 0.6),
        Vector3(0.9, 1.6, 3.2), Vector3(-1.5, 1.4, 3.1)]
    var main_hs := [4.5, 5.1, 5.8, 6.4]
    for bi in range(4):
        var start2 := Vector3(0.32, float(main_hs[bi]), 0.0)
        var end2: Vector3 = start2 + Vector3(main_dirs[bi])
        _seg(node, start2, end2, 0.30, 0.13, light, o, 8)
        for k in range(2 + (bi % 2)):
            var t := rng.randf_range(0.42, 0.78)
            var mp := start2.lerp(end2, t)
            var se := mp + Vector3(rng.randf_range(-1.1, 1.1), rng.randf_range(0.8, 1.6),
                rng.randf_range(-1.1, 1.1))
            _seg(node, mp, se, 0.12, 0.05, light, o, 6)
    # dedicated horizontal limb that carries the swing
    _seg(node, Vector3(0.34, 4.55, 0.0), Vector3(0.42, 5.48, 0.02), 0.40, 0.34, mid, o, 9)
    var limb_a := Vector3(0.42, 5.50, 0.02)
    var limb_b := Vector3(3.75, SWING_LIMB_Y, 0.0)
    _seg(node, limb_a, limb_b, 0.34, 0.24, light, o, 9)
    _seg(node, limb_b, Vector3(5.2, 6.7, 0.8), 0.22, 0.07, light, o, 7)
    _seg(node, limb_b, Vector3(4.3, 6.8, -1.1), 0.18, 0.06, light, o, 6)
    # canopy: four layers of blobs that fade from dark under-leaf green to sunlit tips
    var layers := [
        [7.4, 4.0, 12, 1.95, 1.70],
        [8.7, 3.6, 13, 1.75, 1.60],
        [10.0, 3.0, 11, 1.55, 1.45],
        [11.2, 2.2, 8, 1.35, 1.25],
    ]
    var blob_xf: Array = []
    var blob_col: Array = []
    var centers: Array = []
    for li in range(layers.size()):
        var ld: Array = layers[li]
        var ly: float = ld[0]
        var rad: float = ld[1]
        var cnt: int = ld[2]
        var smin: float = ld[3]
        var smax: float = ld[4]
        for i in range(cnt):
            var ang := TAU * float(i) / float(cnt) + rng.randf_range(-0.25, 0.25) + float(li) * 0.55
            var rr := rad * sqrt(rng.randf_range(0.30, 1.0))
            var cx := cos(ang) * rr + 0.28
            var cz := sin(ang) * rr - 0.05
            var cy := ly + rng.randf_range(-0.55, 0.55)
            var s := rng.randf_range(smin, smax)
            var basis := Basis.from_euler(Vector3(rng.randf_range(-0.25, 0.25), rng.randf_range(0.0, TAU),
                rng.randf_range(-0.25, 0.25))).scaled(Vector3(s, s * rng.randf_range(0.62, 0.78), s))
            blob_xf.append(Transform3D(basis, Vector3(cx, cy, cz)))
            var pick := rng.randf()
            var col := M.C_LEAF_C.lerp(M.C_LEAF_A, pick)
            if li == 1:
                col = M.C_LEAF_A.lerp(M.C_LEAF_B, pick)
            elif li == 2:
                col = M.C_LEAF_B.lerp(Color("a3b877"), pick * 0.7)
            elif li == 3:
                col = M.C_LEAF_B.lerp(Color("b2c583"), 0.4 + pick * 0.5)
            blob_col.append(col)
            centers.append(Vector3(cx, cy, cz))
    M.multis(node, "Canopy", _sphere_mesh(9, 5), blob_xf, blob_col,
        M.toon_material(Color.WHITE, {"vertex_color": true, "bands": 4.0, "rim": 0.20,
            "wind": 0.22, "outline": 0.05, "soft": 0.6}))
    # leaf cards on the silhouette for broken edges
    var cards: Array = []
    var card_cols: Array = []
    for i2 in range(80):
        var bc: Vector3 = centers[rng.randi_range(0, centers.size() - 1)]
        var dirv := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.4, 0.8),
            rng.randf_range(-1.0, 1.0)).normalized()
        var p := bc + dirv * rng.randf_range(0.70, 1.30)
        var sc := rng.randf_range(0.45, 0.85)
        var basis2 := Basis.from_euler(Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.0, TAU),
            rng.randf_range(-1.0, 1.0))).scaled(Vector3(sc, sc, sc))
        cards.append(Transform3D(basis2, p))
        card_cols.append(M.C_LEAF_B.lerp(Color("aec27c"), rng.randf() * 0.7))
    M.multis(node, "LeafCards", _leaf_card_mesh(), cards, card_cols,
        M.toon_material(Color.WHITE, {"vertex_color": true, "bands": 3.0, "rim": 0.25, "wind": 0.44}))
    M.shadow_blob(node, Vector3(0.0, 0.03, 0.0), 6.2, 0.30)
    var perches: Array = [
        base + Vector3(2.3, 11.7, 0.9),
        base + Vector3(-2.1, 11.9, -0.6),
        base + Vector3(0.8, 12.4, 1.4),
        base + Vector3(3.2, 10.9, -1.1),
        base + Vector3(-3.0, 10.6, 1.3),
        base + Vector3(0.2, 11.3, -2.3),
    ]
    return {"pos": base, "canopy": base + Vector3(0.25, 9.4, 0.0), "perches": perches}

static func _leaf_card_mesh() -> ArrayMesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    _add_quad2(st, Vector3(-0.5, -0.5, 0.0), Vector3(0.5, -0.5, 0.0),
        Vector3(0.5, 0.5, 0.0), Vector3(-0.5, 0.5, 0.0), Vector3(0.0, 0.0, 1.0))
    return st.commit()

# ========================================================= background trees ==
static func _bg_trees(root: Node3D) -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = 4402
    var specs := [
        [Vector3(M.SMALL_TREE_X, 0.0, M.SMALL_TREE_Z), 1.0],
        [Vector3(14.9, 0.0, -4.6), 0.86],
        [Vector3(-15.6, 0.0, 0.4), 1.14],
        [Vector3(6.8, 0.0, -12.5), 0.92],
    ]
    var blob_xf: Array = []
    var blob_col: Array = []
    var o := {"outline": 0.04}
    for spec in specs:
        var p: Vector3 = spec[0]
        var sc: float = spec[1]
        var base := Vector3(p.x, _h(p.x, p.z), p.z)
        var h := 4.6 * sc
        _seg(root, base + Vector3(0.0, -0.4, 0.0), base + Vector3(0.08, h * 0.55, 0.03),
            0.30 * sc, 0.22 * sc, M.C_WOOD_DARK, o, 8)
        _seg(root, base + Vector3(0.08, h * 0.55, 0.03), base + Vector3(0.14, h, 0.05),
            0.22 * sc, 0.11 * sc, M.C_WOOD, o, 8)
        for k in range(2):
            var ang := TAU * float(k) / 2.0 + rng.randf_range(-0.6, 0.6)
            var bstart := base + Vector3(0.12 * sc, h * 0.62, 0.05 * sc)
            var bend := bstart + Vector3(cos(ang) * 1.1 * sc, 0.85 * sc, sin(ang) * 1.1 * sc)
            _seg(root, bstart, bend, 0.10 * sc, 0.05 * sc, M.C_WOOD, o, 6)
            var bs := 0.85 * sc * rng.randf_range(0.9, 1.2)
            blob_xf.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(
                Vector3(bs, bs * 0.8, bs)), bend))
            blob_col.append(M.C_LEAF_A.lerp(M.C_LEAF_B, rng.randf()))
        for i in range(6):
            var ang2 := TAU * float(i) / 6.0 + rng.randf_range(-0.3, 0.3)
            var rr := rng.randf_range(0.3, 1.5) * sc
            var cx := cos(ang2) * rr + 0.10 * sc
            var cz := sin(ang2) * rr
            var cy := h + rng.randf_range(0.2, 1.3) * sc
            var bs2 := rng.randf_range(0.75, 1.25) * sc
            blob_xf.append(Transform3D(Basis.from_euler(Vector3(rng.randf_range(-0.4, 0.4),
                rng.randf_range(0.0, TAU), rng.randf_range(-0.4, 0.4))).scaled(
                Vector3(bs2, bs2 * 0.75, bs2)), base + Vector3(cx, cy, cz)))
            blob_col.append(M.C_LEAF_C.lerp(M.C_LEAF_B, rng.randf()).lerp(
                Color("9cb878"), rng.randf() * 0.3))
        M.shadow_blob(root, base + Vector3(0.15, 0.0, 0.05), 2.6 * sc, 0.30)
    M.multis(root, "BgTreeCanopy", _sphere_mesh(8, 5), blob_xf, blob_col,
        M.toon_material(Color.WHITE, {"vertex_color": true, "bands": 3.0, "rim": 0.14, "wind": 0.12}))

# ================================================================ garden ====
static func _fence(parent: Node3D, a: Vector2, b: Vector2) -> void:
    var length := a.distance_to(b)
    var spans := maxi(1, int(round(length / 1.05)))
    var prev_top := Vector3.ZERO
    for i in range(spans + 1):
        var t := float(i) / float(spans)
        var x := lerpf(a.x, b.x, t)
        var z := lerpf(a.y, b.y, t)
        var h := _h(x, z)
        M.cyl(parent, 0.062, 0.080, 1.26, Vector3(x, h + 0.55, z), M.C_WOOD, 0.0, {"outline": 0.022})
        var top := Vector3(x, h, z)
        if i > 0:
            _bar(parent, Vector3(prev_top.x, prev_top.y + 0.40, prev_top.z),
                Vector3(top.x, top.y + 0.40, top.z), 0.05, 0.075, M.C_WOOD_LIGHT, {"outline": 0.018})
            _bar(parent, Vector3(prev_top.x, prev_top.y + 0.92, prev_top.z),
                Vector3(top.x, top.y + 0.92, top.z), 0.05, 0.075, M.C_WOOD_LIGHT, {"outline": 0.018})
        prev_top = top

static func _garden(root: Node3D) -> void:
    var node := Node3D.new()
    node.name = "Garden"
    root.add_child(node)
    var rng := RandomNumberGenerator.new()
    rng.seed = 42424
    var o := {"outline": 0.02}
    # --- four raised beds with stone sides, wood caps and dark soil ---
    for bi in range(_bed_rects.size()):
        var r: Vector4 = _bed_rects[bi]
        var top := _bed_top(r)
        var bottom := _rect_min_h(r, 0.1) - 0.15
        var w := r.y - r.x
        var d := r.w - r.z
        var cx := (r.x + r.y) * 0.5
        var cz := (r.z + r.w) * 0.5
        var wh := top - bottom
        var wall_col := M.C_STONE.lerp(M.C_STONE_DARK, rng.randf_range(0.25, 0.65))
        M.box(node, Vector3(w + 0.20, wh, 0.16), Vector3(cx, bottom + wh * 0.5, r.z - 0.02), wall_col, 0.0, o)
        M.box(node, Vector3(w + 0.20, wh, 0.16), Vector3(cx, bottom + wh * 0.5, r.w + 0.02), wall_col.lightened(0.06), 0.0, o)
        M.box(node, Vector3(0.16, wh, d), Vector3(r.x - 0.02, bottom + wh * 0.5, cz), wall_col, 0.0, o)
        M.box(node, Vector3(0.16, wh, d), Vector3(r.y + 0.02, bottom + wh * 0.5, cz), wall_col.darkened(0.05), 0.0, o)
        M.box(node, Vector3(w + 0.34, 0.09, 0.24), Vector3(cx, top + 0.045, r.z - 0.02), M.C_WOOD_LIGHT, 0.0, o)
        M.box(node, Vector3(w + 0.34, 0.09, 0.24), Vector3(cx, top + 0.045, r.w + 0.02), M.C_WOOD_LIGHT, 0.0, o)
        M.box(node, Vector3(0.24, 0.09, d + 0.34), Vector3(r.x - 0.02, top + 0.045, cz), M.C_WOOD_LIGHT, 0.0, o)
        M.box(node, Vector3(0.24, 0.09, d + 0.34), Vector3(r.y + 0.02, top + 0.045, cz), M.C_WOOD_LIGHT, 0.0, o)
        M.box(node, Vector3(w - 0.16, 0.18, d - 0.16), Vector3(cx, top - 0.05, cz), M.C_SOIL.darkened(0.06), 0.0, o)
    # --- fence with a south gate and an east gate ---
    _fence(node, Vector2(GARDEN_X0, GARDEN_Z1), Vector2(GARDEN_X0, GARDEN_Z0))
    _fence(node, Vector2(GARDEN_X0, GARDEN_Z0), Vector2(GARDEN_X1, GARDEN_Z0))
    _fence(node, Vector2(GARDEN_X1, GARDEN_Z0), Vector2(GARDEN_X1, -6.65))
    _fence(node, Vector2(GARDEN_X1, -5.75), Vector2(GARDEN_X1, GARDEN_Z1))
    _fence(node, Vector2(GARDEN_X0, GARDEN_Z1), Vector2(-8.45, GARDEN_Z1))
    _fence(node, Vector2(-7.20, GARDEN_Z1), Vector2(GARDEN_X1, GARDEN_Z1))
    for g in [Vector2(-8.45, GARDEN_Z1), Vector2(-7.20, GARDEN_Z1),
            Vector2(GARDEN_X1, -6.65), Vector2(GARDEN_X1, -5.75)]:
        var gp: Vector2 = g
        var gh := _h(gp.x, gp.y)
        M.cyl(node, 0.092, 0.112, 1.48, Vector3(gp.x, gh + 0.62, gp.y), M.C_WOOD_DARK, 0.0, {"outline": 0.025})
        M.sphere(node, 0.082, Vector3(gp.x, gh + 1.40, gp.y), M.C_WOOD_LIGHT, Vector3.ONE, {"outline": 0.02})
    # --- bench just outside the south fence ---
    var bp := Vector2(-6.15, -2.30)
    var bh := _h(bp.x, bp.y)
    M.box(node, Vector3(1.70, 0.10, 0.44), Vector3(bp.x, bh + 0.46, bp.y), M.C_WOOD_LIGHT, 0.0, {"outline": 0.025})
    M.box(node, Vector3(1.70, 0.42, 0.09), Vector3(bp.x, bh + 0.72, bp.y + 0.18), M.C_WOOD, 0.0, {"outline": 0.025})
    for sx in [-0.66, 0.66]:
        M.box(node, Vector3(0.12, 0.42, 0.40), Vector3(bp.x + sx, bh + 0.21, bp.y), M.C_WOOD_DARK, 0.0, {"outline": 0.025})
    # --- terracotta pots ---
    for ps in [Vector2(-9.00, -2.52), Vector2(-8.15, -2.28), Vector2(-6.55, -2.44), Vector2(-5.52, -3.10)]:
        var pp: Vector2 = ps
        var ph := _h(pp.x, pp.y)
        M.cyl(node, 0.19, 0.14, 0.34, Vector3(pp.x, ph + 0.17, pp.y), M.C_TERRACOTTA, 0.0, o)
        M.cyl(node, 0.21, 0.20, 0.06, Vector3(pp.x, ph + 0.35, pp.y), M.C_TERRACOTTA_DARK, 0.0, o)
        M.sphere(node, 0.24, Vector3(pp.x, ph + 0.52, pp.y),
            M.C_LEAF_A.lerp(M.C_LEAF_B, 0.4), Vector3(1.0, 0.7, 1.0), o)
    # --- stone trough with water ---
    var tp := Vector2(-10.42, -8.55)
    var th := _h(tp.x, tp.y)
    M.box(node, Vector3(1.10, 0.36, 0.56), Vector3(tp.x, th + 0.28, tp.y), M.C_STONE_DARK, 0.0, {"outline": 0.025})
    var water := M.box(node, Vector3(0.94, 0.05, 0.40), Vector3(tp.x, th + 0.44, tp.y), Color.WHITE, 0.0, {})
    water.material_override = M.glass_material(0.10)
    M.cyl(node, 0.045, 0.055, 0.40, Vector3(tp.x + 0.62, th + 0.24, tp.y), M.C_STONE, 0.0, o)
    # --- herbs and small shrubs inside the garden ---
    for hs in [Vector2(-8.55, -3.42), Vector2(-6.62, -3.46), Vector2(-8.62, -8.62), Vector2(-6.60, -8.66)]:
        var hp: Vector2 = hs
        var hh := _h(hp.x, hp.y)
        M.sphere(node, 0.30, Vector3(hp.x, hh + 0.20, hp.y),
            M.C_LEAF_C.lerp(M.C_LEAF_B, rng.randf()), Vector3(1.25, 0.72, 1.15), o)

# ========================================================== vegetable plot ==
static func _field(root: Node3D) -> void:
    var node := Node3D.new()
    node.name = "VegetablePlot"
    root.add_child(node)
    var rng := RandomNumberGenerator.new()
    rng.seed = 6131
    var o := {"outline": 0.022}
    var r := Vector4(FIELD_X0, FIELD_X1, FIELD_Z0, FIELD_Z1)
    var top := _rect_max_h(r, 0.15) + 0.16
    var bottom := _rect_min_h(r, 0.15) - 0.12
    var w := FIELD_X1 - FIELD_X0
    var d := FIELD_Z1 - FIELD_Z0
    var cx := (FIELD_X0 + FIELD_X1) * 0.5
    var cz := (FIELD_Z0 + FIELD_Z1) * 0.5
    M.box(node, Vector3(w, top - bottom, d), Vector3(cx, (top + bottom) * 0.5, cz),
        M.C_SOIL.darkened(0.06), 0.0, o)
    M.box(node, Vector3(w + 0.16, 0.10, d + 0.16), Vector3(cx, top - 0.05, cz),
        M.C_SOIL.lerp(Color("8a6a4e"), 0.4), 0.0, o)
    # timber retaining on the downhill (east / south) edges
    M.box(node, Vector3(0.12, top - bottom + 0.10, d + 0.12),
        Vector3(FIELD_X1 + 0.05, (top + bottom) * 0.5, cz), M.C_WOOD_DARK, 0.0, o)
    M.box(node, Vector3(w + 0.12, top - bottom + 0.10, 0.12),
        Vector3(cx, (top + bottom) * 0.5, FIELD_Z1 + 0.05), M.C_WOOD_DARK, 0.0, o)
    # 4 ridged rows along X
    var ridge_count := 4
    for i in range(ridge_count):
        var rz := lerpf(FIELD_Z0 + 0.42, FIELD_Z1 - 0.42, float(i) / float(ridge_count - 1))
        M.box(node, Vector3(w - 0.34, 0.16, 0.30), Vector3(cx, top + 0.07, rz),
            M.C_SOIL.lerp(Color("9c7955"), 0.45), 0.0, o)
    # leafy crops along every ridge
    var crop_xf: Array = []
    var crop_col: Array = []
    for i in range(ridge_count):
        var rz2 := lerpf(FIELD_Z0 + 0.42, FIELD_Z1 - 0.42, float(i) / float(ridge_count - 1))
        for k in range(8):
            var px := lerpf(FIELD_X0 + 0.30, FIELD_X1 - 0.30, float(k) / 7.0)
            var sc := rng.randf_range(0.12, 0.19)
            crop_xf.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(
                Vector3(sc, sc * 0.8, sc)), Vector3(px + rng.randf_range(-0.03, 0.03),
                top + 0.15, rz2 + rng.randf_range(-0.05, 0.05))))
            crop_col.append(M.C_LEAF_A.lerp(M.C_LEAF_B, rng.randf()).lerp(
                Color("9cb46e"), rng.randf() * 0.4))
    M.multis(node, "Crops", _sphere_mesh(6, 4), crop_xf, crop_col,
        M.toon_material(Color.WHITE, {"vertex_color": true, "bands": 3.0, "rim": 0.08, "wind": 0.14}))
    # bean poles on the back ridge with a top rail
    for i in range(6):
        var px := lerpf(FIELD_X0 + 0.35, FIELD_X1 - 0.35, float(i) / 5.0)
        _seg(node, Vector3(px, top + 0.14, FIELD_Z0 + 0.52), Vector3(px + 0.12, top + 1.75, FIELD_Z0 + 0.40),
            0.030, 0.018, M.C_WOOD_LIGHT, o, 5)
    _bar(node, Vector3(FIELD_X0 + 0.28, top + 1.52, FIELD_Z0 + 0.42),
        Vector3(FIELD_X1 - 0.28, top + 1.52, FIELD_Z0 + 0.42), 0.035, 0.035, M.C_WOOD, o)
    # two stone steps down to the garden gate
    M.box(node, Vector3(0.46, 0.14, 0.90), Vector3(FIELD_X0 - 0.22, top - 0.18, -7.30), M.C_STONE, 0.0, o)
    M.box(node, Vector3(0.46, 0.14, 0.90), Vector3(FIELD_X0 - 0.22, top - 0.38, -7.78), M.C_STONE_DARK, 0.0, o)
    # little sign board near the path
    var sxp := FIELD_X1 - 0.32
    var szp := FIELD_Z1 + 0.62
    _seg(node, Vector3(sxp, _h(sxp, szp), szp), Vector3(sxp, top + 1.12, szp),
        0.038, 0.030, M.C_WOOD_DARK, o, 5)
    M.box(node, Vector3(0.46, 0.30, 0.05), Vector3(sxp, top + 1.02, szp), M.C_WOOD_LIGHT, 0.0, o)

# ============================================================= lighthouse ==
static func _sail_quad_mesh() -> ArrayMesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var segs := 4
    var prev_l := Vector3.ZERO
    var prev_r := Vector3.ZERO
    for i in range(segs + 1):
        var t := float(i) / float(segs)
        var y := lerpf(-1.0, 1.0, t)
        var bulge := sin(t * PI) * 0.10
        var l := Vector3(-0.5, y, bulge)
        var r := Vector3(0.5, y, bulge)
        if i > 0:
            _add_quad2(st, prev_l, prev_r, r, l, Vector3(0.0, 0.0, 1.0))
        prev_l = l
        prev_r = r
    return st.commit()

# --- lighthouse -------------------------------------------------------------
# Replaces the old windmill on the same headland site. The floating structure
# (node "Lighthouse") is exactly LIGHTHOUSE_H tall above the terrace:
#   LIGHTHOUSE_H = 1.5 x measured old windmill AABB height (12.1839389801025 m).
# Only nodes / meshes / materials are built here; the rotating beam shader is
# owned by main.gd, which consumes the lighthouse_* return keys.
## Fresnel lens assembly for the rotating lamp: a central lens drum, four
## horizontal prism rings and four vertical ribs, merged into ONE ArrayMesh so the
## whole assembly costs a single draw call. It shares the lamp material (which
## main.gd drives at night) and is parented to the "Lamp" node, so it rotates.
static func _fresnel_lens_mesh() -> ArrayMesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    _lens_ring(st, 0.30, 0.30, -0.46, 0.46, 12)
    for ry in [-0.36, -0.12, 0.12, 0.36]:
        var yy: float = ry
        _lens_ring(st, 0.44, 0.44, yy - 0.038, yy + 0.038, 12)
    for k in range(4):
        var la := TAU * float(k) / 4.0 + PI * 0.25
        _lens_rib(st, 0.47, la, 0.055, -0.42, 0.42)
    st.index()
    return st.commit()


## Closed ring band (straight or slightly conical) around the Y axis.
static func _lens_ring(st: SurfaceTool, top_r: float, bot_r: float, y0: float, y1: float, segs: int) -> void:
    for i in range(segs):
        var a0 := TAU * float(i) / float(segs)
        var a1 := TAU * float(i + 1) / float(segs)
        var p00 := Vector3(cos(a0) * bot_r, y0, sin(a0) * bot_r)
        var p01 := Vector3(cos(a0) * top_r, y1, sin(a0) * top_r)
        var p11 := Vector3(cos(a1) * top_r, y1, sin(a1) * top_r)
        var p10 := Vector3(cos(a1) * bot_r, y0, sin(a1) * bot_r)
        M._add_quad(st, p00, p01, p11, p10)


## Flat vertical rib (thin outward facing strip) used for the lens prisms.
static func _lens_rib(st: SurfaceTool, radius: float, centre_a: float, half_a: float, y0: float, y1: float) -> void:
    var a0 := centre_a - half_a
    var a1 := centre_a + half_a
    var p00 := Vector3(cos(a0) * radius, y0, sin(a0) * radius)
    var p01 := Vector3(cos(a0) * radius, y1, sin(a0) * radius)
    var p11 := Vector3(cos(a1) * radius, y1, sin(a1) * radius)
    var p10 := Vector3(cos(a1) * radius, y0, sin(a1) * radius)
    M._add_quad(st, p00, p01, p11, p10)


static func _lighthouse(root: Node3D) -> Dictionary:
    var o := {"outline": 0.024}
    # ---- stone terrace (kept from the old windmill footprint) ----------------
    var site := Vector4(LIGHTHOUSE_X - 2.35, LIGHTHOUSE_X + 2.35, LIGHTHOUSE_Z - 2.35, LIGHTHOUSE_Z + 2.35)
    var top := _rect_max_h(site, 0.30) + 0.12
    var base_site := Vector4(LIGHTHOUSE_X - 3.25, LIGHTHOUSE_X + 3.25, LIGHTHOUSE_Z - 3.25, LIGHTHOUSE_Z + 3.25)
    var bottom := _rect_min_h(base_site, 0.10) - 0.30
    var lower_top := top - 0.95
    var lower_h := maxf(lower_top - bottom, 0.40)
    M.box(root, Vector3(6.40, lower_h, 6.40), Vector3(LIGHTHOUSE_X, bottom + lower_h * 0.5, LIGHTHOUSE_Z), M.C_STONE_DARK, 0.0, o)
    M.box(root, Vector3(5.40, 0.95, 5.40), Vector3(LIGHTHOUSE_X, lower_top + 0.475, LIGHTHOUSE_Z), M.C_STONE, 0.0, o)
    M.box(root, Vector3(5.70, 0.16, 5.70), Vector3(LIGHTHOUSE_X, top - 0.08, LIGHTHOUSE_Z), M.C_STONE.lightened(0.08), 0.0, o)
    for s in range(3):
        var tt := float(s) / 2.0
        var sy := lerpf(top - 0.42, bottom + 0.30, tt)
        var sw := lerpf(1.05, 1.65, tt)
        M.box(root, Vector3(sw, 0.30, 1.55), Vector3(LIGHTHOUSE_X + 3.05 + tt * 0.85, sy, LIGHTHOUSE_Z + 1.75), M.C_STONE, 0.0, o)

    # ---- floating lighthouse node -------------------------------------------
    var node := Node3D.new()
    node.name = "Lighthouse"
    node.position = Vector3(LIGHTHOUSE_X, top, LIGHTHOUSE_Z)
    root.add_child(node)
    node.set_meta("height", LIGHTHOUSE_H)

    var stone := M.C_STONE.lightened(0.12)
    var stone_d := M.C_STONE_DARK
    var iron := Color("3f433e")
    var band_col := Color("a9604a")

    # plinth (cap top = local y 1.12, the doorway rests on it)
    var plinth := M.cyl(node, 1.98, 2.32, 1.05, Vector3(0, 0.525, 0), stone_d, 0.0, o)
    plinth.name = "PlinthBase"
    var plinth_cap := M.cyl(node, 2.00, 2.00, 0.14, Vector3(0, 1.05, 0), stone, 0.0, o)
    plinth_cap.name = "PlinthCap"

    # tower shaft: 6 tapered sections, cream stone with two terracotta bands
    var shaft_y0 := 1.05
    var shaft_y1 := 13.10
    var sections := 6
    for s in range(sections):
        var t0 := float(s) / float(sections)
        var t1 := float(s + 1) / float(sections)
        var y0 := lerpf(shaft_y0, shaft_y1, t0)
        var y1 := lerpf(shaft_y0, shaft_y1, t1)
        var r0 := lerpf(1.72, 1.02, t0)
        var r1 := lerpf(1.72, 1.02, t1)
        var col := stone if s % 2 == 0 else stone.lerp(stone_d, 0.20)
        M.cyl(node, r1, r0, y1 - y0, Vector3(0, (y0 + y1) * 0.5, 0), col, 0.0, o)
    for by in [5.90, 10.30]:
        var byf: float = by
        var bt := (byf - shaft_y0) / (shaft_y1 - shaft_y0)
        var br := lerpf(1.72, 1.02, bt) + 0.035
        M.cyl(node, br, br, 0.44, Vector3(0, byf, 0), band_col, 0.0, o)

    # narrow glass windows spiralling up the shaft
    var win_defs := [[3.60, 0.40], [6.90, 2.10], [9.60, 3.80], [11.40, 5.50]]
    for wd in win_defs:
        var wy: float = wd[0]
        var wa: float = wd[1]
        var wt := (wy - shaft_y0) / (shaft_y1 - shaft_y0)
        var wr := lerpf(1.72, 1.02, wt) + 0.01
        var wpos := Vector3(cos(wa) * wr, wy, sin(wa) * wr)
        var win := M.box_rot(node, Vector3(0.34, 0.66, 0.12), wpos, stone_d, Vector3(0.0, -wa + PI * 0.5, 0.0), o)
        win.material_override = M.glass_material(0.35)

    # door facing the island centre; the doorway now rests on the plinth cap (top 1.12)
    # so a 1.50 m visitor does not have to step down into the stone base any more.
    var door_dir := Vector3(-LIGHTHOUSE_X, 0.0, -LIGHTHOUSE_Z).normalized()
    var door_rot := atan2(door_dir.x, door_dir.z)
    var door_base := Vector3(door_dir.x * 1.66, 0.0, door_dir.z * 1.66)
    var door_lift := 0.23
    var door_frame := M.box_rot(node, Vector3(1.34, 2.42, 0.22), door_base + Vector3(0.0, 2.10 + door_lift, 0.0), stone_d, Vector3(0.0, door_rot, 0.0), o)
    door_frame.name = "DoorFrame"
    var door_leaf := M.box_rot(node, Vector3(0.94, 1.86, 0.16), door_base + Vector3(0.0, 1.90 + door_lift, 0.0) + door_dir * 0.10, M.C_WOOD_DARK, Vector3(0.0, door_rot, 0.0), o)
    door_leaf.name = "DoorLeaf"
    var door_inner := M.box_rot(node, Vector3(0.42, 1.62, 0.10), door_base + Vector3(0.0, 1.86 + door_lift, 0.0) + door_dir * 0.19, M.C_WOOD, Vector3(0.0, door_rot, 0.0), o)
    door_inner.name = "DoorInner"
    var door_lintel := M.box_rot(node, Vector3(1.52, 0.24, 0.40), door_base + Vector3(0.0, 3.20 + door_lift, 0.0) + door_dir * 0.04, stone, Vector3(0.0, door_rot, 0.0), o)
    door_lintel.name = "DoorLintel"
    var door_threshold := M.box_rot(node, Vector3(1.50, 0.08, 0.40), door_base + door_dir * 0.18 + Vector3(0.0, 1.16, 0.0), stone, Vector3(0.0, door_rot, 0.0), o)
    door_threshold.name = "DoorThreshold"
    # Seven external wrapping stone steps (rise 0.16 m each) around the tapered
    # plinth, from the threshold (top 1.20) down to the terrace top (0.16).
    # Each tread is an external ring segment: its inner radius is derived from the
    # plinth radius at that tread's own height, so the tread always protrudes at
    # least 0.02 m past the cone there (radial depth 0.38, outer radius <= 2.85).
    var stair_rise := 0.16
    var stair_step := 0.15
    var stair_depth := 0.38
    var stair_gap := 0.02
    var door_ang := atan2(door_dir.x, door_dir.z)
    for i in range(7):
        var top_y := stair_rise * float(7 - i)
        # plinth profile: cone r = 2.32 - (0.34/1.05)*y up to y 0.98, cap r = 2.00
        var r_plinth := 2.00 if top_y > 0.98 else 2.32 - (0.34 / 1.05) * top_y
        var r_in := r_plinth + stair_gap
        var r_mid := r_in + stair_depth * 0.5
        var ang := door_ang - (float(i) + 0.5) * stair_step
        # tangential width derived from the sector arc, plus 6 mm so neighbouring
        # treads interlock instead of leaving a visible gap or coplanar z-fighting.
        var tang := 2.0 * r_mid * tan(stair_step * 0.5) + 0.006
        var c := Vector3(sin(ang) * r_mid, 0.0, cos(ang) * r_mid)
        var step := M.box_rot(node, Vector3(tang, top_y, stair_depth), c + Vector3(0.0, top_y * 0.5, 0.0), stone if i % 2 == 0 else stone_d, Vector3(0.0, ang, 0.0), o)
        step.name = "DoorStep%d" % i

    # ---- gallery deck (inside) + railing (outside) ----------------------------
    var gallery_y := shaft_y1
    M.cyl(node, 2.06, 1.62, 0.34, Vector3(0.0, gallery_y + 0.17, 0.0), stone_d, 0.0, o)
    var deck_y := gallery_y + 0.34
    M.cyl(node, 2.22, 2.22, 0.16, Vector3(0.0, deck_y + 0.08, 0.0), stone, 0.0, o)
    var deck_top := deck_y + 0.16
    var rail_r := 2.10
    var rail_n := 14
    for k in range(rail_n):
        var a := TAU * float(k) / float(rail_n)
        var pp := Vector3(cos(a) * rail_r, deck_top + 0.48, sin(a) * rail_r)
        M.cyl(node, 0.032, 0.046, 0.96, pp, iron, 0.0, o)
    for k in range(rail_n):
        var a0 := TAU * float(k) / float(rail_n)
        var a1 := TAU * float(k + 1) / float(rail_n)
        var t0 := Vector3(cos(a0) * rail_r, deck_top + 0.94, sin(a0) * rail_r)
        var t1 := Vector3(cos(a1) * rail_r, deck_top + 0.94, sin(a1) * rail_r)
        _seg(node, t0, t1, 0.036, 0.036, iron, o, 6)
        var m0 := Vector3(cos(a0) * rail_r, deck_top + 0.48, sin(a0) * rail_r)
        var m1 := Vector3(cos(a1) * rail_r, deck_top + 0.48, sin(a1) * rail_r)
        _seg(node, m0, m1, 0.020, 0.020, iron, o, 5)

    # lantern room: base drum, glass cylinder, mullions and hoops
    M.cyl(node, 1.30, 1.46, 0.22, Vector3(0.0, deck_top + 0.11, 0.0), stone_d, 0.0, o)
    var lantern_y0 := deck_top + 0.22
    var lantern_y1 := lantern_y0 + 1.60
    var glass := M.cyl(node, 1.16, 1.16, 1.60, Vector3(0.0, (lantern_y0 + lantern_y1) * 0.5, 0.0), Color.WHITE, 0.0, {})
    # thinner, slightly warmer lantern glass: at night the fresnel lens must read
    # through it, at noon it still looks like a static glass room.
    var lantern_glass := M.glass_material(0.30)
    lantern_glass.set_shader_parameter("opacity", 0.18)
    glass.material_override = lantern_glass
    for k in range(8):
        var a := TAU * float(k) / 8.0
        var mpos := Vector3(cos(a) * 1.19, (lantern_y0 + lantern_y1) * 0.5, sin(a) * 1.19)
        M.box_rot(node, Vector3(0.10, 1.62, 0.10), mpos, iron, Vector3(0.0, -a, 0.0), o)
    for hy in [lantern_y0 + 0.26, lantern_y1 - 0.26]:
        M.cyl(node, 1.20, 1.20, 0.07, Vector3(0.0, hy, 0.0), iron, 0.0, o)

    # ---- rotating lamp -------------------------------------------------------
    var lamp := Node3D.new()
    lamp.name = "Lamp"
    lamp.position = Vector3(0.0, (lantern_y0 + lantern_y1) * 0.5, 0.0)
    node.add_child(lamp)
    var lamp_mat := M.toon_material(Color("ffd9a0"), {"self_lit": true, "bands": 2, "glow": 0.65, "outline": 0.0})
    # fresnel lens assembly: one merged mesh, shares lamp_mat so main.gd's night
    # glow animation lights it up (self_lit => colour * glow). It sits under the
    # rotating "Lamp" node so the prism rings / ribs sweep with the beam.
    var lens := MeshInstance3D.new()
    lens.name = "FresnelLens"
    lens.mesh = _fresnel_lens_mesh()
    lens.material_override = lamp_mat
    lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    lamp.add_child(lens)
    # dark iron frame around the lens: four posts, top cap/vent, bottom plate.
    # It rotates with the lamp and reads as structure silhouetted against the
    # warm lens, so the lantern room is not a featureless glowing blob.
    for k in range(4):
        var a := TAU * float(k) / 4.0
        M.box_rot(lamp, Vector3(0.050, 1.06, 0.050), Vector3(cos(a) * 0.62, 0.0, sin(a) * 0.62), iron, Vector3(0.0, -a, 0.0), o)
    M.cyl(lamp, 0.54, 0.50, 0.10, Vector3(0.0, 0.50, 0.0), iron, 0.0, o)
    M.cyl(lamp, 0.07, 0.50, 0.26, Vector3(0.0, 0.66, 0.0), iron, 0.0, o)
    M.cyl(lamp, 0.55, 0.55, 0.10, Vector3(0.0, -0.50, 0.0), iron, 0.0, o)
    var lamp_centre := lamp.position

    # dome, vent ball and lightning rod (rod tip is exactly LIGHTHOUSE_H)
    var dome_y0 := lantern_y1
    M.cyl(node, 0.10, 1.44, 0.85, Vector3(0.0, dome_y0 + 0.425, 0.0), M.C_TERRACOTTA_DARK, 0.0, o)
    for k in range(8):
        var a := TAU * float(k) / 8.0
        var rim := Vector3(cos(a) * 1.40, dome_y0 + 0.03, sin(a) * 1.40)
        var apex := Vector3(0.0, dome_y0 + 0.84, 0.0)
        _seg(node, rim, apex, 0.030, 0.014, M.C_TERRACOTTA_DARK.darkened(0.12), o, 5)
    var dome_top := dome_y0 + 0.85
    M.sphere(node, 0.22, Vector3(0.0, dome_top + 0.14, 0.0), stone_d, Vector3(1.0, 1.0, 1.0), o)
    _seg(node, Vector3(0.0, dome_top + 0.30, 0.0), Vector3(0.0, LIGHTHOUSE_H, 0.0), 0.048, 0.018, iron, o, 6)
    M.sphere(node, 0.055, Vector3(0.0, dome_top + 0.95, 0.0), M.C_TERRACOTTA, Vector3(1.0, 1.0, 1.0), o)

    # ---- platform node + perches --------------------------------------------
    var platform := Node3D.new()
    platform.name = "GalleryPlatform"
    platform.position = Vector3(0.0, deck_top, 0.0)
    node.add_child(platform)
    var perches: Array[Vector3] = []
    for k in range(4):
        var a := 0.60 + TAU * float(k) / 4.0
        perches.append(node.transform * Vector3(cos(a) * rail_r, deck_top + 1.02, sin(a) * rail_r))

    var beam_origin: Vector3 = node.transform * lamp_centre
    var lamp_halo := M.halo(root, beam_origin, 3.60, Color("ffd9a0"))
    var light := {
        "pos": beam_origin,
        "color": Color(1.0, 0.82, 0.55),
        "range": 17.0,
        "intensity": 1.65,
        "kind": "lighthouse",
    }
    return {
        "node": node,
        "height": LIGHTHOUSE_H,
        "lamp": lamp,
        "beam_origin": beam_origin,
        "platform": platform,
        "perches": perches,
        "light": light,
        "lamp_mat": lamp_mat,
        "lamp_halo": lamp_halo,
        "rotation_axis": Vector3.UP,
    }

# ================================================================= swing ===
static func _swing(root: Node3D, big: Dictionary) -> Node3D:
    var base: Vector3 = big["pos"]
    var pivot := Vector3(base.x + 3.0, base.y + SWING_LIMB_Y, base.z)
    var ground := _h(pivot.x, pivot.z)
    # seat top 0.585 m above ground: right for a 1.50 m islander to sit with feet down
    var rope_len := maxf(2.6, pivot.y - (ground + 0.55))
    var node := Node3D.new()
    node.name = "Swing"
    node.position = pivot
    root.add_child(node)
    var o := {"outline": 0.018}
    var rope_col := Color("c9b48f")
    for sx in [-0.52, 0.52]:
        var x := float(sx)
        var y0 := -0.30
        var y1 := -rope_len - 0.02
        var segs := 3
        for i in range(segs):
            var ya := lerpf(y0, y1, float(i) / float(segs))
            var yb := lerpf(y0, y1, float(i + 1) / float(segs))
            _seg(node, Vector3(x, ya, 0.0), Vector3(x, yb, 0.0), 0.031, 0.028,
                rope_col, {"outline": 0.0}, 5)
        M.sphere(node, 0.060, Vector3(x, -0.30, 0.0), M.C_WOOD_DARK, Vector3(1.0, 1.3, 1.0), o)
        M.sphere(node, 0.054, Vector3(x, -rope_len + 0.07, 0.0), M.C_STONE_DARK, Vector3(1.0, 1.2, 1.0), o)
        M.box(node, Vector3(0.05, 0.12, 0.12), Vector3(x, -rope_len - 0.03, 0.0),
            Color("5c5b57"), 0.0, o)
    var seat := M.box(node, Vector3(1.12, 0.07, 0.46), Vector3(0.0, -rope_len, 0.0),
        M.C_WOOD_LIGHT, 0.0, {"outline": 0.02})
    seat.name = "SwingSeat"
    M.box(node, Vector3(1.14, 0.025, 0.05), Vector3(0.0, -rope_len - 0.047, 0.0), M.C_WOOD, 0.0, {})
    return node

# ================================================================== dock ====
# ================================================================== dock ====
# P5 deck contract: the whole walking surface is ONE horizontal plane at
# DECK_WORLD_Y = 0.72 m (clears the tuned ~0.5 m wave crest, below normal step
# height). The beach profile crosses 0.72 m at z ~= 1.7 m in dock-local space,
# which is where the three shore treads hand the sand over to the deck. The dock
# node itself still sits at M.dock_start() as the P4/P5 interfaces require.
static func _dock(root: Node3D) -> Dictionary:
    var start := M.dock_start()
    var dir := M.dock_dir()
    var node := Node3D.new()
    node.name = "Dock"
    node.position = start
    node.rotation.y = atan2(dir.x, dir.z)
    root.add_child(node)
    var rng := RandomNumberGenerator.new()
    rng.seed = 5150
    var o := {"outline": 0.02}
    var L: float = M.DOCK_LENGTH
    var W: float = M.DOCK_WIDTH
    var deck_y := DECK_WORLD_Y - start.y
    # --- deck planks: one level plane, one MultiMesh, individual wood tones ---
    var plank_mesh := BoxMesh.new()
    plank_mesh.size = Vector3(W, 0.10, 0.50)
    var plank_xf: Array = []
    var plank_col: Array = []
    var plank_z0 := 2.05
    var planks := 18
    for i in range(planks):
        var z := plank_z0 + float(i) * 0.525
        plank_xf.append(Transform3D(Basis.IDENTITY,
            Vector3(rng.randf_range(-0.015, 0.015), deck_y - 0.05, z)))
        plank_col.append(M.C_WOOD.lerp(M.C_WOOD_LIGHT, rng.randf()).lerp(
            M.C_WOOD_DARK, rng.randf() * 0.35))
    M.multis(node, "DockPlanks", plank_mesh, plank_xf, plank_col,
        M.toon_material(Color.WHITE, {"vertex_color": true, "bands": 4.0, "rim": 0.10, "outline": 0.02}))
    # --- level stringers under the deck ---
    for sx in [-1.0, 0.0, 1.0]:
        var x := float(sx) * (W * 0.5 - 0.34)
        _bar(node, Vector3(x, deck_y - 0.22, plank_z0 - 0.35), Vector3(x, deck_y - 0.22, L),
            0.18, 0.26, M.C_WOOD_DARK, {"outline": 0.018})
    # --- piles, bracers and railings: every top follows the level deck ---
    var pile_zs := [2.20, 3.92, 5.64, 7.36, 9.08, 10.40]
    var pile_bottom := -3.40 - start.y
    var piles_info: Array = []
    var prev_z := float(pile_zs[0])
    var first_rail := true
    for pz in pile_zs:
        var z := float(pz)
        for sx in [-1.0, 1.0]:
            var x := float(sx) * (W * 0.5 - 0.20)
            var top := deck_y + 0.06
            M.cyl(node, 0.105, 0.130, top - pile_bottom,
                Vector3(x, (top + pile_bottom) * 0.5, z), M.C_WOOD_DARK, 0.0, o)
            M.box(node, Vector3(0.30, 0.055, 0.30), Vector3(x, top + 0.02, z), M.C_WOOD_LIGHT, 0.0, o)
            piles_info.append({"x": x, "z": z, "top": DECK_WORLD_Y + 0.06, "bottom": -3.40})
        _bar(node, Vector3(-(W * 0.5 - 0.20), deck_y - 0.32, z),
            Vector3(W * 0.5 - 0.20, deck_y - 0.32, z), 0.12, 0.12, M.C_WOOD, {"outline": 0.015})
        # railings: the shore landing pair stays open, everything else is level
        if first_rail:
            first_rail = false
        else:
            for sx in [-1.0, 1.0]:
                var x := float(sx) * (W * 0.5 - 0.02)
                M.box(node, Vector3(0.09, 0.95, 0.09), Vector3(x, deck_y + 0.475, z),
                    M.C_WOOD, 0.0, o)
                _bar(node, Vector3(x, deck_y + 0.92, prev_z), Vector3(x, deck_y + 0.92, z),
                    0.075, 0.08, M.C_WOOD_LIGHT, {"outline": 0.015})
                _bar(node, Vector3(x, deck_y + 0.52, prev_z), Vector3(x, deck_y + 0.52, z),
                    0.05, 0.06, M.C_WOOD, {"outline": 0.012})
        prev_z = z
    # --- bollards and cleats on the level head ---
    for sx in [-1.0, 1.0]:
        var x := float(sx) * 1.10
        M.cyl(node, 0.15, 0.17, 0.52, Vector3(x, deck_y + 0.26, 9.65), M.C_WOOD_DARK, 0.0, o)
        M.cyl(node, 0.20, 0.20, 0.07, Vector3(x, deck_y + 0.55, 9.65), M.C_STONE_DARK, 0.0, o)
    # --- ladder down from the level head ---
    for sx in [-1.0, 1.0]:
        var x := float(sx) * 0.44
        _bar(node, Vector3(x, deck_y + 0.05, L + 0.18), Vector3(x, -2.20 - start.y, L + 0.18),
            0.09, 0.09, M.C_WOOD_DARK, {"outline": 0.015})
    for i in range(5):
        var y := deck_y - 0.20 - float(i) * 0.46
        _bar(node, Vector3(-0.44, y, L + 0.18), Vector3(0.44, y, L + 0.18),
            0.07, 0.06, M.C_WOOD_LIGHT, {"outline": 0.012})
    # --- shore link: three stone treads up the beach (0.72 -> 0.78 -> 0.86 -> 0.94) ---
    # Natural sand on the centre line is ~0.91 m at z=1.15, ~0.76 m at z=1.60 and
    # ~0.42 m at the first plank edge, so the treads sit on the slope instead of
    # cutting a long ramp into it (the old 1.4 m ramp is gone with the slope).
    M.box(node, Vector3(2.70, 0.30, 0.50), Vector3(0.0, 0.78 - start.y - 0.15, 1.70), M.C_STONE, 0.0, o)
    M.box(node, Vector3(2.70, 0.36, 0.50), Vector3(0.0, 0.86 - start.y - 0.18, 1.42), M.C_STONE_DARK, 0.0, o)
    M.box(node, Vector3(2.70, 0.40, 0.50), Vector3(0.0, 0.94 - start.y - 0.20, 1.14), M.C_STONE, 0.0, o)
    for sx in [-1.0, 1.0]:
        var kx := float(sx) * 1.42
        _bar(node, Vector3(kx, 0.94 - start.y, 0.92), Vector3(kx, 0.80 - start.y, 1.98),
            0.16, 0.20, M.C_STONE_DARK, {"outline": 0.016})
    # --- hanging lantern on the head post ---
    var post_z := 9.35
    M.box(node, Vector3(0.12, 0.12, 0.12), Vector3(1.52, deck_y + 0.05, post_z), M.C_STONE_DARK, 0.0, o)
    M.cyl(node, 0.055, 0.075, 2.10, Vector3(1.52, deck_y + 1.05, post_z), M.C_WOOD_DARK, 0.0, o)
    _bar(node, Vector3(1.52, deck_y + 2.05, post_z), Vector3(0.72, deck_y + 2.05, post_z),
        0.07, 0.07, M.C_WOOD_DARK, {"outline": 0.015})
    M.cyl(node, 0.012, 0.012, 0.36, Vector3(0.72, deck_y + 1.86, post_z), Color("4a4a46"), 0.0, {})
    var lamp_local := Vector3(0.72, deck_y + 1.55, post_z)
    var lantern_mat: ShaderMaterial = M.toon_material(Color("ffd7a0"), {"self_lit": true, "glow": 1.0})
    var lamp_box := M.box(node, Vector3(0.26, 0.30, 0.26), lamp_local, Color.WHITE, 0.0, o)
    lamp_box.material_override = lantern_mat
    M.cyl(node, 0.15, 0.19, 0.08, Vector3(0.72, deck_y + 1.72, post_z), M.C_WOOD_DARK, 0.0, o)
    var lantern_world: Vector3 = node.transform * lamp_local
    var lantern_halo := M.halo(root, lantern_world, 1.25, Color(1.50, 1.02, 0.53, 1.0))
    var perch_z := 8.60
    var perch: Vector3 = node.transform * Vector3(W * 0.5 - 0.02, deck_y + 0.95, perch_z)
    var end: Vector3 = node.transform * Vector3(0.0, deck_y, L + 0.85)
    var bollard: Vector3 = node.transform * Vector3(1.10, deck_y + 0.55, 9.65)
    return {
        "node": node,
        "end": end,
        "perch": perch,
        "bollard": bollard,
        "deck_world_y": DECK_WORLD_Y,
        "deck_local_y": deck_y,
        "piles": piles_info,
        "lantern_mat": lantern_mat,
        "lantern_halo": lantern_halo,
        "light": {"pos": lantern_world, "color": Color(1.0, 0.76, 0.45), "range": 8.0, "intensity": 1.40},
    }

# ================================================================= boats ===
## One cross-section point of a lofted hull: t=0 at the keel, t=1 at the sheer.
static func _hull_pt(s: Vector4, t: float, sign: float, shrink: float, inset: float) -> Vector3:
    var w := s.y * shrink
    var sheer := s.z - inset
    var keel := s.w + inset
    var x := sign * w * pow(t, 0.72)
    var y := lerpf(keel, sheer, t) + sin(t * PI) * 0.02
    return Vector3(x, y, s.x)

## Lofted hull surface (both windings per quad, flat normals).
static func _hull_mesh(stations: Array, shrink: float, inset: float) -> ArrayMesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var ts := [0.0, 0.16, 0.36, 0.60, 0.81, 1.0]
    for sign_i in [-1.0, 1.0]:
        var sign := float(sign_i)
        for i in range(stations.size() - 1):
            var s0: Vector4 = stations[i]
            var s1: Vector4 = stations[i + 1]
            for j in range(ts.size() - 1):
                var a := _hull_pt(s0, ts[j], sign, shrink, inset)
                var b := _hull_pt(s1, ts[j], sign, shrink, inset)
                var c := _hull_pt(s1, ts[j + 1], sign, shrink, inset)
                var d := _hull_pt(s0, ts[j + 1], sign, shrink, inset)
                var n := (b - a).cross(d - a).normalized()
                if n.x * a.x < 0.0:
                    n = -n
                _add_quad2(st, a, b, c, d, n)
    return st.commit()

static func _hull_sheer_y(stations: Array, shrink: float, inset: float) -> Array:
    var ys: Array = []
    for s in stations:
        var sv: Vector4 = s
        ys.append(sv.z - inset)
    return ys

# --------------------------------------------------------------- sail routes --
# P5 itinerary planner. The legs are built from control points and then shaped by
# _smooth_path (Chaikin -> uniform arc-length resample -> Laplacian smoothing with
# pinned ends), which keeps every polyline smooth and free of kinks. All legs lie
# on the y = 0 sea plane, start AND end at the same dock anchor (sail_dock_pos) so
# the boat never teleports, stay >= 7 m offshore and keep clear of the dock.
#
# kind == "coastal": short 4-leg coastal cruises near the island.
# kind == "far":      long offshore runs. The far end sits at 5.9 * island_diameter
#                     from the island centre, the fade window starts at 5.02 * D
#                     (>= 5 D as the contract requires) and 28800 simulated seconds
#                     of absence are used for the day/night cycle. Five return
#                     entries on a 5.3 * D ring feed sail_return_paths / the
#                     sail_return_path() callback.

const SAIL_RETURN_ENTRY_AZ := [0.35, 1.50, 2.70, 3.90, 5.10]

static var _sail_return_paths: Dictionary = {}
static var _sail_return_default := PackedVector3Array()

static func _seg_dist_2d(px: float, pz: float, a: Vector2, b: Vector2) -> float:
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

static func _dock_segment_2d() -> Array:
    var s := M.dock_start()
    var e := M.dock_end()
    return [Vector2(s.x, s.z), Vector2(e.x, e.z)]

# --- polyline helpers (kept small and side-effect free) ----------------------
static func _prune_pts(pts: PackedVector3Array, eps: float = 0.06) -> PackedVector3Array:
    var out := PackedVector3Array()
    for p in pts:
        if out.is_empty() or out[out.size() - 1].distance_to(p) > eps:
            out.append(p)
    return out

static func _chaikin_pts(pts: PackedVector3Array, iters: int = 1) -> PackedVector3Array:
    var cur := _prune_pts(pts)
    for _it in range(iters):
        if cur.size() < 3:
            return cur
        var nxt := PackedVector3Array([cur[0]])
        for i in range(cur.size() - 1):
            var a := cur[i]
            var b := cur[i + 1]
            nxt.append(a * 0.75 + b * 0.25)
            nxt.append(a * 0.25 + b * 0.75)
        nxt.append(cur[cur.size() - 1])
        cur = nxt
    return cur

static func _polyline_len(pts: PackedVector3Array) -> float:
    var total := 0.0
    for i in range(pts.size() - 1):
        total += pts[i].distance_to(pts[i + 1])
    return total

static func _resample_pts(pts: PackedVector3Array, step: float) -> PackedVector3Array:
    var src := _prune_pts(pts)
    if src.size() < 2:
        return src
    var out := PackedVector3Array([src[0]])
    var acc := 0.0
    var next := step
    for i in range(src.size() - 1):
        var a := src[i]
        var b := src[i + 1]
        var seg := a.distance_to(b)
        if seg < 0.000001:
            continue
        while next <= acc + seg - 0.000001:
            out.append(a.lerp(b, (next - acc) / seg))
            next += step
        acc += seg
    var last := src[src.size() - 1]
    var dlast := out[out.size() - 1].distance_to(last)
    if dlast > step * 0.35:
        out.append(last)
    elif dlast > 0.01:
        out[out.size() - 1] = last
    return out

static func _laplacian_pts(pts: PackedVector3Array, iters: int) -> PackedVector3Array:
    var cur := pts
    for _it in range(iters):
        if cur.size() < 3:
            return cur
        var nxt := PackedVector3Array()
        nxt.resize(cur.size())
        nxt[0] = cur[0]
        nxt[cur.size() - 1] = cur[cur.size() - 1]
        for i in range(1, cur.size() - 1):
            nxt[i] = (cur[i - 1] + cur[i] * 2.0 + cur[i + 1]) * 0.25
        cur = nxt
    return cur

static func _smooth_path(ctrl: PackedVector3Array, step: float, iters: int) -> PackedVector3Array:
    return _prune_pts(_laplacian_pts(_resample_pts(_chaikin_pts(_prune_pts(ctrl), 1), step), iters), 0.05)

static func _path_arc_point(pts: PackedVector3Array, dist: float) -> Vector3:
    var acc := 0.0
    for i in range(pts.size() - 1):
        var seg := pts[i].distance_to(pts[i + 1])
        if acc + seg >= dist:
            return pts[i].lerp(pts[i + 1], (dist - acc) / maxf(seg, 0.000001))
        acc += seg
    return pts[pts.size() - 1]

static func _ring_pt(az: float, r: float) -> Vector3:
    return Vector3(cos(az) * r, 0.0, sin(az) * r)

static func _wrap_pi(a: float) -> float:
    var x := a
    while x > PI:
        x -= TAU
    while x < -PI:
        x += TAU
    return x

static func _sstep(t: float) -> float:
    var x := clampf(t, 0.0, 1.0)
    return x * x * (3.0 - 2.0 * x)

# --- island diameter: real maximum width used by the far-route contract ------
static func _island_diameter() -> float:
    var best := 0.0
    var samples := 4096
    for i in range(samples):
        var a := TAU * float(i) / float(samples)
        best = maxf(best, M.coast_radius(a))
    return best * 2.0

# --- four coastal cruises ---------------------------------------------------
# a0/a1: angular sweep, o0/o1: outward legs offshore margin, ob0/ob1: return leg
# margin, bulge_o/bulge_b: sine bulges so the two legs read as different shapes.
static func _coastal_route(route_name: String, a0: float, a1: float, o0: float, o1: float,
        ob0: float, ob1: float, bulge_o: float, bulge_b: float, speed: float,
        az0: float, ra: float, anchor: Vector3) -> Dictionary:
    var pad := 2.0
    var lead2 := ra + 3.0
    var lead_n := 24
    var arc_n := 12
    var out_ctrl := PackedVector3Array([anchor])
    for i in range(1, lead_n + 1):
        var k := float(i) / float(lead_n)
        var az := lerpf(az0, a0, k)
        var base_r: float = M.coast_radius(az) + o0 + pad
        out_ctrl.append(_ring_pt(az, base_r + (lead2 - base_r) * (1.0 - _sstep(k))))
    for j in range(1, arc_n + 1):
        var t := float(j) / float(arc_n)
        var az := lerpf(a0, a1, t)
        var off := o0 + (o1 - o0) * t + bulge_o * sin(PI * t) + pad
        out_ctrl.append(_ring_pt(az, M.coast_radius(az) + off))
    var out := _smooth_path(out_ctrl, 1.4, 60)
    var back_ctrl := PackedVector3Array([out[out.size() - 1]])
    for j in range(arc_n, -1, -1):
        var t := float(j) / float(arc_n)
        var az := lerpf(a0, a1, t)
        var off := ob0 + (ob1 - ob0) * t + bulge_b * sin(PI * t) + pad
        back_ctrl.append(_ring_pt(az, M.coast_radius(az) + off))
    for i in range(lead_n, 0, -1):
        var k := float(i) / float(lead_n)
        var az := lerpf(az0, a0, k)
        var base_r: float = M.coast_radius(az) + ob0 + pad
        back_ctrl.append(_ring_pt(az, base_r + (lead2 - base_r) * (1.0 - _sstep(k))))
    back_ctrl.append(anchor)
    var back := _smooth_path(back_ctrl, 1.4, 60)
    return {
        "name": route_name,
        "kind": "coastal",
        "out": out,
        "back": back,
        "wait": 3.0,
        "speed": speed,
        # P7：近海弧段的方位范围（真实航线几何元数据；远海航线没有这两个字段）。
        "shore_a0": a0,
        "shore_a1": a1,
    }

# --- P7：近海航段触发点 -------------------------------------------------------
# 把「方位角位于 [a0,a1] 的近海弧段」换算成 out 航线上的弧长触发点（main 与探针共用同一几何）。
# 取弧段前段约 28% 处：船刚进入可观察的近海弧段，海鸥有足够时间响应，同时船仍在视野内。
# 返回 -1.0 表示该航线没有可用的近海弧段（例如远海航线）。
static func shore_trigger_dist(out_pts: Array, a0: float, a1: float) -> float:
    if out_pts.size() < 2:
        return -1.0
    var total := 0.0
    var first := -1.0
    var last := -1.0
    var prev: Vector3 = out_pts[0]
    for i in range(out_pts.size()):
        var p: Vector3 = out_pts[i]
        if i > 0:
            total += p.distance_to(prev)
        prev = p
        var az := fposmod(atan2(p.z, p.x), TAU)
        if az >= a0 and az <= a1:
            if first < 0.0:
                first = total
            last = total
    if first < 0.0 or last <= first:
        return -1.0
    return first + (last - first) * 0.28

# --- far offshore runs ------------------------------------------------------
static func _far_route(route_name: String, phi: float, speed: float,
        az0: float, ra: float, anchor: Vector3, diameter: float, entries: Array) -> Dictionary:
    var r_far := 5.9 * diameter
    var n := 96
    var ctrl := PackedVector3Array()
    for i in range(n + 1):
        var t := float(i) / float(n)
        var az := az0 + _wrap_pi(phi - az0) * _sstep(t)
        ctrl.append(_ring_pt(az, ra + (r_far - ra) * t))
    var out := _smooth_path(ctrl, 2.4, 6)
    var total := _polyline_len(out)
    var fade_start := 5.02 * diameter
    var fade_end := minf(total - 2.0, fade_start + 0.5 * diameter)
    var nb := 72
    var back_ctrl := PackedVector3Array([out[out.size() - 1]])
    for i in range(1, nb + 1):
        var t := float(i) / float(nb)
        var az := phi + _wrap_pi(az0 - phi) * _sstep(t) + 0.10 * sin(PI * t)
        back_ctrl.append(_ring_pt(az, r_far + (ra - r_far) * pow(t, 1.25)))
    back_ctrl.append(anchor)
    var back := _smooth_path(back_ctrl, 2.4, 6)
    return {
        "name": route_name,
        "kind": "far",
        "out": out,
        "back": back,
        "wait": 6.0,
        "wait_sim_seconds": 28800.0,
        "speed": speed,
        "fade_start": fade_start,
        "fade_end": fade_end,
        "far_entries": entries,
    }

# Five same-radius return entries spread around the island (>= 5 D from centre).
static func _far_entries(az0: float, diameter: float) -> Array:
    var r_entry := 5.3 * diameter
    var out: Array = []
    for da in SAIL_RETURN_ENTRY_AZ:
        out.append(_ring_pt(az0 + float(da), r_entry))
    return out

# Smooth offshore return path from one far entry back to the dock anchor.
static func _return_path(entry: Vector3, az0: float, ra: float, anchor: Vector3, diameter: float) -> PackedVector3Array:
    var r_entry := 5.3 * diameter
    var az_e := atan2(entry.z, entry.x)
    var n := 72
    var ctrl := PackedVector3Array([entry])
    for i in range(1, n + 1):
        var t := float(i) / float(n)
        var r := r_entry + (ra - r_entry) * _sstep(t)
        var az := az_e + _wrap_pi(az0 - az_e) * _sstep(minf(1.0, t * 1.4))
        ctrl.append(_ring_pt(az, r))
    ctrl.append(anchor)
    var path := _smooth_path(ctrl, 2.4, 6)
    if path.size() > 0:
        path[0] = entry
        path[path.size() - 1] = anchor
    return path

# Callable access for main.gd: sail_return_path(entry) -> PackedVector3Array.
static func _sail_return_path(entry: Vector3) -> PackedVector3Array:
    var key := Vector3(entry.x, 0.0, entry.z)
    if _sail_return_paths.has(key):
        var path: PackedVector3Array = _sail_return_paths[key]
        return path
    return _sail_return_default

static func _sail_routes() -> Dictionary:
    _sail_segs = []
    _sail_return_paths = {}
    var az0: float = M.DOCK_ANGLE
    var ra: float = M.coast_radius(az0) * 0.90 + 14.4
    var anchor := Vector3(cos(az0) * ra, 0.0, sin(az0) * ra)
    var diameter := _island_diameter()
    var routes: Array = []
    # kind == "coastal": four short cruises hugging the island.
    routes.append(_coastal_route("West Reach", 0.98, 1.86, 7.6, 8.8, 9.6, 8.4, 1.2, -1.0, 2.45, az0, ra, anchor))
    routes.append(_coastal_route("Southwest Run", 2.02, 2.92, 8.4, 7.6, 7.6, 9.2, 0.8, 1.0, 2.50, az0, ra, anchor))
    routes.append(_coastal_route("South Passage", 3.10, 3.98, 9.4, 8.2, 7.6, 8.6, 1.0, -0.8, 2.55, az0, ra, anchor))
    routes.append(_coastal_route("Southeast Sweep", 4.10, 4.82, 7.6, 9.0, 9.4, 8.2, 0.9, 1.1, 2.60, az0, ra, anchor))
    # kind == "far": five long offshore runs with fade windows and return entries.
    var entries := _far_entries(az0, diameter)
    var far_az: Array = [az0 - 0.55, az0 - 0.22, az0 + 0.06, az0 + 0.34, az0 + 0.62]
    var far_names: Array = ["Far Reach West", "Far Reach Southwest", "Far Reach South",
        "Far Reach Southeast", "Far Reach East"]
    for i in range(far_az.size()):
        routes.append(_far_route(String(far_names[i]), float(far_az[i]), 2.85 + 0.03 * float(i),
            az0, ra, anchor, diameter, entries))
    # One smooth offshore return path per far entry (>= 5 D -> dock anchor).
    var return_paths := {}
    for e in entries:
        var entry: Vector3 = e
        return_paths[Vector3(entry.x, 0.0, entry.z)] = _return_path(entry, az0, ra, anchor, diameter)
    _sail_return_paths = return_paths
    if return_paths.size() > 0:
        var first_key: Vector3 = return_paths.keys()[0]
        var first_path: PackedVector3Array = return_paths[first_key]
        _sail_return_default = first_path
    # Cache every leg as a flat 2D segment list: rock placement avoids the lanes.
    for r in routes:
        var out: PackedVector3Array = r["out"]
        var back: PackedVector3Array = r["back"]
        for i in range(out.size() - 1):
            _sail_segs.append([Vector2(out[i].x, out[i].z), Vector2(out[i + 1].x, out[i + 1].z)])
        for i in range(back.size() - 1):
            _sail_segs.append([Vector2(back[i].x, back[i].z), Vector2(back[i + 1].x, back[i + 1].z)])
    for key in return_paths.keys():
        var path: PackedVector3Array = return_paths[key]
        for i in range(path.size() - 1):
            _sail_segs.append([Vector2(path[i].x, path[i].z), Vector2(path[i + 1].x, path[i + 1].z)])
    var heading := 0.0
    if routes.size() > 0:
        var first_out: PackedVector3Array = routes[0]["out"]
        if first_out.size() > 1:
            var d := first_out[1] - first_out[0]
            heading = atan2(d.x, d.z)
    return {
        "routes": routes,
        "anchor": anchor,
        "heading": heading,
        "island_diameter": diameter,
        "return_paths": return_paths,
    }

# ------------------------------------------------------------ sailing boat ---
static func _sailboat_loft() -> Array:
    var stations: Array = [
        Vector4(-2.40, 0.32, 0.50, -0.10),
        Vector4(-1.95, 0.55, 0.49, -0.24),
        Vector4(-1.30, 0.70, 0.47, -0.32),
        Vector4(-0.55, 0.76, 0.46, -0.34),
        Vector4(0.25, 0.75, 0.47, -0.33),
        Vector4(1.05, 0.66, 0.50, -0.29),
        Vector4(1.75, 0.50, 0.54, -0.21),
        Vector4(2.25, 0.30, 0.60, -0.10),
        Vector4(2.55, 0.04, 0.66, 0.02),
    ]
    return [stations, _hull_mesh(stations, 1.0, 0.0), _hull_mesh(stations, 0.88, 0.05)]

# ---- P7-V3 deck / interior / fittings ----------------------------------------
## Named identity-transform child group. The boat hierarchy stays readable
## (Hull/Deck/Interior/Fittings/Cabin/Rig); main.gd only ever uses the Sailboat
## root itself, so grouping never changes the animated node reference.
static func _boat_group(parent: Node3D, group_name: String) -> Node3D:
    var g := Node3D.new()
    g.name = group_name
    parent.add_child(g)
    return g

## Interpolated hull station (z, half width, sheer y, keel y) at an arbitrary z.
static func _boat_station_at(stations: Array, z: float) -> Vector4:
    var first: Vector4 = stations[0]
    if z <= first.x:
        return first
    for i in range(stations.size() - 1):
        var a: Vector4 = stations[i]
        var b: Vector4 = stations[i + 1]
        if z <= b.x:
            var u := clampf((z - a.x) / maxf(b.x - a.x, 0.0001), 0.0, 1.0)
            return Vector4(lerpf(a.x, b.x, u), lerpf(a.y, b.y, u),
                lerpf(a.z, b.z, u), lerpf(a.w, b.w, u))
    return stations[stations.size() - 1]

## Half width / sheer height of the lofted hull at an arbitrary z.
static func _boat_section_at(stations: Array, z: float) -> Vector2:
    var s := _boat_station_at(stations, z)
    return Vector2(s.y, s.z)

## Half width of the hull outer skin at height y for station z. Returns 0.0
## when y is at or above the sheer, i.e. the hull has no wall that high (the
## deck there meets the gunwale instead).
static func _boat_hull_half_at(stations: Array, z: float, y: float) -> float:
    var s := _boat_station_at(stations, z)
    if y >= s.z - 0.0001:
        return 0.0
    var lo := 0.0
    var hi := 1.0
    for step_i in 24:
        var mid := (lo + hi) * 0.5
        var my := lerpf(s.w, s.z, mid) + sin(mid * PI) * 0.02
        if my < y:
            lo = mid
        else:
            hi = mid
    var t := (lo + hi) * 0.5
    return s.y * pow(t, 0.72)

## Outboard half width of one deck board: (top edge at deck_y, bottom edge at
## deck_y - thickness). Above the sheer a board stops at the gunwale inner
## face; over the rising bow/stern sheer it follows the hull wall, so the deck
## and inwale actually meet the hull instead of leaving a dark slit.
static func _boat_deck_half(stations: Array, z: float, deck_y: float,
        thickness: float) -> Vector2:
    var s := _boat_station_at(stations, z)
    var gunwale_inner: float = s.y - 0.05
    var top: float = _boat_hull_half_at(stations, z, deck_y)
    if top <= 0.0:
        top = gunwale_inner
    var bottom: float = _boat_hull_half_at(stations, z, deck_y - thickness)
    if bottom <= 0.0:
        bottom = gunwale_inner
    return Vector2(minf(top, s.y), minf(bottom, top))

## Lofted deck board / fill block: samples are Vector3(z, half_top, half_bottom)
## so the flanks follow the hull wall; flat top at deck_y, bottom one thickness
## lower, both ends closed.
static func _boat_deck_mesh(samples: Array, deck_y: float, thickness: float) -> ArrayMesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var bot := deck_y - thickness
    for i in range(samples.size() - 1):
        var a: Vector3 = samples[i]
        var b: Vector3 = samples[i + 1]
        var ta0 := Vector3(-a.y, deck_y, a.x)
        var ta1 := Vector3(a.y, deck_y, a.x)
        var tb1 := Vector3(b.y, deck_y, b.x)
        var tb0 := Vector3(-b.y, deck_y, b.x)
        var ba0 := Vector3(-a.z, bot, a.x)
        var ba1 := Vector3(a.z, bot, a.x)
        var bb1 := Vector3(b.z, bot, b.x)
        var bb0 := Vector3(-b.z, bot, b.x)
        _add_quad2(st, ta0, ta1, tb1, tb0, Vector3.UP)
        _add_quad2(st, ba0, ba1, bb1, bb0, Vector3.DOWN)
        _add_quad2(st, ta0, tb0, bb0, ba0, Vector3.LEFT)
        _add_quad2(st, ta1, tb1, bb1, ba1, Vector3.RIGHT)
    var f: Vector3 = samples[0]
    var l: Vector3 = samples[samples.size() - 1]
    _add_quad2(st, Vector3(-f.y, deck_y, f.x), Vector3(-f.z, bot, f.x),
        Vector3(f.z, bot, f.x), Vector3(f.y, deck_y, f.x), Vector3(0.0, 0.0, -1.0))
    _add_quad2(st, Vector3(-l.y, deck_y, l.x), Vector3(-l.z, bot, l.x),
        Vector3(l.z, bot, l.x), Vector3(l.y, deck_y, l.x), Vector3(0.0, 0.0, 1.0))
    return st.commit()

## Inner bilge floor: the bottom of the hull lofted just inside the liner,
## lifted 0.08 and given a 0.05 board thickness with a closed outer rim. It now
## sits below the P7-V3.2 cockpit sole (top 0.20) so the bilge never pokes through.
static func _boat_floor_mesh(stations: Array) -> ArrayMesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var ts: Array = [0.0, 0.14, 0.30, 0.46]
    var shrink := 0.84
    var low := 0.08
    var thick := 0.05
    for sign_i in [-1.0, 1.0]:
        var sign := float(sign_i)
        var t_top: float = ts[ts.size() - 1]
        for i in range(stations.size() - 1):
            var s0: Vector4 = stations[i]
            var s1: Vector4 = stations[i + 1]
            for j in range(ts.size() - 1):
                var t0: float = ts[j]
                var t1: float = ts[j + 1]
                var a := _hull_pt(s0, t0, sign, shrink, low + thick)
                var b := _hull_pt(s1, t0, sign, shrink, low + thick)
                var c := _hull_pt(s1, t1, sign, shrink, low + thick)
                var d := _hull_pt(s0, t1, sign, shrink, low + thick)
                var n := (b - a).cross(d - a).normalized()
                if n.x * a.x < 0.0:
                    n = -n
                _add_quad2(st, a, b, c, d, n)
            # outer rim that closes the 5 cm board thickness
            var p0 := _hull_pt(s0, t_top, sign, shrink, low)
            var p1 := _hull_pt(s1, t_top, sign, shrink, low)
            var q0 := _hull_pt(s0, t_top, sign, shrink, low + thick)
            var q1 := _hull_pt(s1, t_top, sign, shrink, low + thick)
            _add_quad2(st, p0, p1, q1, q0, Vector3(sign, 0.0, 0.0))
    return st.commit()

## Planked deck, P7-V3.2 cockpit layout: the middle of the hull is open so a
## 1.50 m islander can stand or row inside it. The stern locker deck keeps two
## boards (z -2.24..-0.72) and the bow deck one board (z 1.44..2.08); each is
## tapered to the local hull width so the deck follows the sheer, with 2 cm
## seams and a +-0.05 tint. The outboard ends land on an inwale strip (舷缘内衬)
## that only runs under the decked ends, and a low coaming closes the cockpit
## rim. Interior furniture (sole / frames / thwarts) is _boat_interior's job.
static func _boat_deck(parent: Node3D, stations: Array, deck_y: float, o: Dictionary) -> void:
    var seam := 0.02
    # (z0, z1, board count) for the decked ends; the gap between is the cockpit
    var deck_spans: Array = [[-2.24, -0.72, 2], [1.44, 2.08, 1]]
    var plank_i := 0
    for span in deck_spans:
        var z0: float = span[0]
        var z1: float = span[1]
        var count: int = span[2]
        var seg := (z1 - z0) / float(count)
        for k in range(count):
            var za: float = z0 + seg * float(k) + seam * 0.5
            var zb: float = z0 + seg * float(k + 1) - seam * 0.5
            var top: float = deck_y + (0.004 if plank_i % 2 == 1 else -0.004)
            # sample the hull wall along the board: the deck keeps following the
            # rising sheer up to the bow/stern instead of ending at a fixed inset
            var samples: Array = []
            for k2 in 4:
                var sz: float = lerpf(za, zb, float(k2) / 3.0)
                var hw := _boat_deck_half(stations, sz, top, 0.06)
                samples.append(Vector3(sz, hw.x, hw.y))
            var base: Color = M.C_WOOD_LIGHT if plank_i % 2 == 0 else M.C_WOOD
            var tint := 0.05 if plank_i % 4 < 2 else -0.05
            var col: Color = base.lightened(tint) if tint > 0.0 else base.darkened(-tint)
            var mi := MeshInstance3D.new()
            mi.name = "DeckPlank%02d" % plank_i
            mi.mesh = _boat_deck_mesh(samples, top, 0.06)
            mi.material_override = M.toon_material(col,
                {"bands": 3.5, "soft": 0.5, "rim": 0.08, "outline": 0.02})
            mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
            parent.add_child(mi)
            plank_i += 1
    # inwale: short timber strips inside the gunwale, only under the decked ends
    var inwale_spans: Array = [[-2.24, -0.72, 2], [1.44, 2.08, 1]]
    for sign_i in [-1.0, 1.0]:
        var sign := float(sign_i)
        var tag := "P" if sign < 0.0 else "S"
        var iw_i := 0
        for span in inwale_spans:
            var z0: float = span[0]
            var z1: float = span[1]
            var count: int = span[2]
            for i in range(count):
                var ia: float = lerpf(z0 - 0.02, z1 + 0.02, float(i) / float(count))
                var ib: float = lerpf(z0 - 0.02, z1 + 0.02, float(i + 1) / float(count))
                var ha: float = maxf(_boat_deck_half(stations, ia, deck_y, 0.06).x - 0.02, 0.06)
                var hb: float = maxf(_boat_deck_half(stations, ib, deck_y, 0.06).x - 0.02, 0.06)
                var iw := _bar(parent, Vector3(sign * ha, deck_y - 0.005, ia),
                    Vector3(sign * hb, deck_y - 0.005, ib), 0.08, 0.08, M.C_WOOD_DARK,
                    {"outline": 0.014})
                iw.name = "Inwale%s%02d" % [tag, iw_i]
                iw_i += 1
    # coaming: low timber rim around the open cockpit (z -0.70..1.42)
    var cockpit_z0 := -0.70
    var cockpit_z1 := 1.42
    var coam_y := deck_y + 0.045
    for sign_i in [-1.0, 1.0]:
        var sign := float(sign_i)
        var tag := "P" if sign < 0.0 else "S"
        var h0: float = maxf(_boat_deck_half(stations, cockpit_z0, coam_y, 0.08).x - 0.05, 0.10)
        var h1: float = maxf(_boat_deck_half(stations, cockpit_z1, coam_y, 0.08).x - 0.05, 0.10)
        var cb := _bar(parent, Vector3(sign * h0, coam_y, cockpit_z0),
            Vector3(sign * h1, coam_y, cockpit_z1), 0.06, 0.08, M.C_WOOD_DARK,
            {"outline": 0.012})
        cb.name = "Coaming%s" % tag
    var fh: float = maxf(_boat_deck_half(stations, cockpit_z1, coam_y, 0.08).x - 0.05, 0.10)
    var fore := _bar(parent, Vector3(-fh, coam_y, cockpit_z1), Vector3(fh, coam_y, cockpit_z1),
        0.06, 0.08, M.C_WOOD_DARK, {"outline": 0.012})
    fore.name = "CoamingFore"
    # the aft rim is split: the cuddy door (centre z = -0.713) opens from the cockpit
    var ah: float = maxf(_boat_deck_half(stations, cockpit_z0, coam_y, 0.08).x - 0.05, 0.10)
    for sign_i in [-1.0, 1.0]:
        var sign := float(sign_i)
        var tag := "P" if sign < 0.0 else "S"
        var aft := _bar(parent, Vector3(sign * ah, coam_y, cockpit_z0),
            Vector3(sign * 0.47, coam_y, cockpit_z0), 0.06, 0.08, M.C_WOOD_DARK,
            {"outline": 0.012})
        aft.name = "CoamingAft%s" % tag

## Bilge floor, four frames, two rowing thwarts with knees, and the solid
## bow/stern fill blocks that close the un-decked triangular ends.
static func _boat_interior(parent: Node3D, stations: Array, deck_y: float, o: Dictionary) -> void:
    var floor_mi := MeshInstance3D.new()
    floor_mi.name = "InnerFloor"
    floor_mi.mesh = _boat_floor_mesh(stations)
    floor_mi.material_override = M.toon_material(M.C_WOOD.darkened(0.18),
        {"bands": 3.0, "soft": 0.5, "rim": 0.05, "outline": 0.012})
    floor_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    parent.add_child(floor_mi)
    # P7-V3.2 cockpit sole: flat boards at 0.20 m spanning the open cockpit,
    # so a 1.50 m crew stands 0.40 m below the 0.60 m thwart seats.
    var sole_samples: Array = []
    for k in 5:
        var sz: float = lerpf(-0.70, 1.42, float(k) / 4.0)
        var hw := _boat_deck_half(stations, sz, 0.20, 0.05)
        sole_samples.append(Vector3(sz, hw.x, hw.y))
    var sole := MeshInstance3D.new()
    sole.name = "Sole"
    sole.mesh = _boat_deck_mesh(sole_samples, 0.20, 0.05)
    sole.material_override = M.toon_material(M.C_WOOD.lightened(0.04),
        {"bands": 3.0, "soft": 0.5, "rim": 0.05, "outline": 0.012})
    sole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    parent.add_child(sole)
    # four frames following the liner, 0.8 m apart
    for ri in 4:
        var rz := -1.20 + 0.80 * float(ri)
        var sv := _boat_station_at(stations, rz)
        for sign_i in [-1.0, 1.0]:
            var sign := float(sign_i)
            var tag := "P" if sign < 0.0 else "S"
            var p0 := _hull_pt(sv, 0.22, sign, 0.88, 0.05)
            var p1 := _hull_pt(sv, 0.60, sign, 0.88, 0.05)
            var p2 := _hull_pt(sv, 1.0, sign, 0.88, 0.05)
            var bar0 := _bar(parent, p0, p1, 0.05, 0.05, M.C_WOOD_DARK, {"outline": 0.01})
            bar0.name = "Rib%02d%sA" % [ri, tag]
            var bar1 := _bar(parent, p1, p2, 0.05, 0.05, M.C_WOOD_DARK, {"outline": 0.01})
            bar1.name = "Rib%02d%sB" % [ri, tag]
    # bow / stern fill blocks: solid tapering infill that continues the planked
    # deck into the triangular ends and closes the volume under it
    var bow_samples: Array = []
    for k in 4:
        var bz: float = lerpf(2.07, 2.44, float(k) / 3.0)
        var hb := _boat_deck_half(stations, bz, deck_y, 0.24)
        bow_samples.append(Vector3(bz, hb.x, hb.y))
    var bow := MeshInstance3D.new()
    bow.name = "BowFill"
    bow.mesh = _boat_deck_mesh(bow_samples, deck_y, 0.24)
    bow.material_override = M.toon_material(M.C_WOOD.darkened(0.08),
        {"bands": 3.0, "rim": 0.06, "outline": 0.018})
    bow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    parent.add_child(bow)
    var stern_samples: Array = []
    for k in 4:
        var fz: float = lerpf(-2.38, -2.23, float(k) / 3.0)
        var hf := _boat_deck_half(stations, fz, deck_y, 0.24)
        stern_samples.append(Vector3(fz, hf.x, hf.y))
    var stern := MeshInstance3D.new()
    stern.name = "SternFill"
    stern.mesh = _boat_deck_mesh(stern_samples, deck_y, 0.24)
    stern.material_override = M.toon_material(M.C_WOOD.darkened(0.08),
        {"bands": 3.0, "rim": 0.06, "outline": 0.018})
    stern.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    parent.add_child(stern)
    # two rowing thwarts: seat top at deck_y + 0.08 (=0.60), board 6 cm thick,
    # width exactly the local boat width minus 6 cm. With the open cockpit they
    # stand on two legs (sole top 0.20 -> seat underside 0.54) instead of knees.
    var thwart_z: Array = [-0.30, 1.20]
    for si in 2:
        var tz: float = thwart_z[si]
        var half_w: float = _boat_section_at(stations, tz).x - 0.03
        var seat := M.box(parent, Vector3(half_w * 2.0, 0.06, 0.30),
            Vector3(0.0, deck_y + 0.05, tz), M.C_WOOD_LIGHT.lightened(0.03), 0.0, o)
        seat.name = "Thwart%02d" % si
        for sign_i in [-1.0, 1.0]:
            var sign := float(sign_i)
            var tag := "P" if sign < 0.0 else "S"
            var leg := M.box(parent, Vector3(0.08, 0.34, 0.10),
                Vector3(sign * (half_w - 0.10), 0.37, tz),
                M.C_WOOD_DARK, 0.0, {"outline": 0.01})
            leg.name = "ThwartLeg%02d%s" % [si, tag]

## Two stowed oars lying on the thwarts, two rowlocks on the gunwale and the
## bow / stern mooring cleats.
static func _boat_fittings(parent: Node3D, stations: Array, deck_y: float, o: Dictionary) -> void:
    for sign_i in [-1.0, 1.0]:
        var sign := float(sign_i)
        var tag := "P" if sign < 0.0 else "S"
        var ox: float = sign * 0.42
        # shipped oar: 1.55 m shaft lying across the two thwarts (seat tops at
        # 0.60), so its 0.05 radius puts the centre at 0.65 and both ends rest
        var oar_y: float = deck_y + 0.13
        var shaft := _seg(parent, Vector3(ox, oar_y, -0.40), Vector3(ox, oar_y, 1.15),
            0.05, 0.045, M.C_WOOD_LIGHT, {"outline": 0.012}, 8)
        shaft.name = "OarShaft%s" % tag
        var blade := M.box(parent, Vector3(0.11, 0.024, 0.34),
            Vector3(ox, oar_y, -0.24), M.C_WOOD_LIGHT.lightened(0.04), 0.0,
            {"outline": 0.012})
        blade.name = "OarBlade%s" % tag
        var grip := M.box(parent, Vector3(0.045, 0.045, 0.16),
            Vector3(ox, oar_y, 1.08), M.C_WOOD_DARK, 0.0, {"outline": 0.008})
        grip.name = "OarGrip%s" % tag
    # rowlocks: short post + U yoke on top of the port/starboard gunwale
    var lock_half: float = _boat_section_at(stations, 0.10).x
    var lock_sheer: float = _boat_section_at(stations, 0.10).y
    var gunwale_top := lock_sheer + 0.065
    for sign_i in [-1.0, 1.0]:
        var sign := float(sign_i)
        var tag := "P" if sign < 0.0 else "S"
        var lock := Node3D.new()
        lock.name = "Oarlock%s" % tag
        lock.position = Vector3(sign * (lock_half - 0.07), gunwale_top, 0.10)
        parent.add_child(lock)
        M.cyl(lock, 0.045, 0.055, 0.13, Vector3(0.0, 0.065, 0.0), Color("3a3a38"),
            0.0, {"outline": 0.008})
        _bar(lock, Vector3(-0.045, 0.145, 0.0), Vector3(0.045, 0.145, 0.0),
            0.024, 0.024, Color("3a3a38"), {"outline": 0.006})
        _bar(lock, Vector3(-0.045, 0.145, 0.0), Vector3(-0.045, 0.215, 0.0),
            0.024, 0.024, Color("3a3a38"), {"outline": 0.006})
        _bar(lock, Vector3(0.045, 0.145, 0.0), Vector3(0.045, 0.215, 0.0),
            0.024, 0.024, Color("3a3a38"), {"outline": 0.006})
    # mooring cleats on the bow and stern fill blocks
    var cleat_z: Array = [2.16, -2.28]
    var cleat_names: Array = ["MooringCleatBow", "MooringCleatStern"]
    for ci in 2:
        var cleat := Node3D.new()
        cleat.name = String(cleat_names[ci])
        cleat.position = Vector3(0.0, deck_y - 0.015, float(cleat_z[ci]))
        parent.add_child(cleat)
        M.cyl(cleat, 0.05, 0.06, 0.16, Vector3(0.0, 0.08, 0.0), M.C_WOOD_DARK,
            0.0, {"outline": 0.012})
        M.box(cleat, Vector3(0.20, 0.035, 0.05), Vector3(0.0, 0.175, 0.0),
            M.C_WOOD_DARK, 0.0, {"outline": 0.01})

## Square cabin with a door panel, door window and four side portholes. The
## box body keeps the P5 silhouette; the details are what the close shots read.
static func _boat_cabin(parent: Node3D, deck_y: float, win_mat: ShaderMaterial, o: Dictionary) -> void:
    var cz := -1.35
    var body_h := 0.50
    var body_top := deck_y + body_h
    M.box(parent, Vector3(0.94, body_h, 1.25), Vector3(0.0, deck_y + body_h * 0.5, cz),
        M.C_WALL.darkened(0.10), 0.0, o)
    M.box(parent, Vector3(1.06, 0.07, 1.38), Vector3(0.0, body_top + 0.035, cz),
        M.C_WOOD_DARK, 0.0, o)
    for sx in [-1.0, 1.0]:
        M.box(parent, Vector3(0.05, 0.045, 1.40),
            Vector3(float(sx) * 0.545, body_top + 0.02, cz), M.C_WOOD_DARK, 0.0,
            {"outline": 0.012})
    M.box(parent, Vector3(1.10, 0.045, 0.05), Vector3(0.0, body_top + 0.02, cz - 0.705),
        M.C_WOOD_DARK, 0.0, {"outline": 0.012})
    M.box(parent, Vector3(1.10, 0.045, 0.05), Vector3(0.0, body_top + 0.02, cz + 0.705),
        M.C_WOOD_DARK, 0.0, {"outline": 0.012})
    # door on the forward (+Z) face
    var door_z := cz + 0.625 + 0.012
    var door_y := deck_y + 0.26
    var door := M.box(parent, Vector3(0.30, 0.40, 0.024), Vector3(0.0, door_y, door_z),
        M.C_WOOD, 0.0, {"outline": 0.012})
    door.name = "CabinDoor"
    for sx in [-1.0, 1.0]:
        M.box(parent, Vector3(0.03, 0.44, 0.03),
            Vector3(float(sx) * 0.165, door_y, door_z - 0.002), M.C_WOOD_DARK, 0.0,
            {"outline": 0.008})
    M.box(parent, Vector3(0.36, 0.03, 0.03), Vector3(0.0, door_y + 0.215, door_z - 0.002),
        M.C_WOOD_DARK, 0.0, {"outline": 0.008})
    M.sphere(parent, 0.021, Vector3(0.10, door_y - 0.02, door_z + 0.020),
        Color("c8a24a"), Vector3.ONE, {"outline": 0.006})
    var dwin := M.cyl_rot(parent, 0.055, 0.055, 0.03, Vector3(0.0, door_y + 0.09, door_z + 0.006),
        Color.WHITE, Vector3(PI * 0.5, 0.0, 0.0), {})
    dwin.material_override = win_mat
    dwin.name = "CabinDoorWindow"
    # four side portholes, two per side
    for sx in [-1.0, 1.0]:
        var side := "P" if float(sx) < 0.0 else "S"
        for pi in 2:
            var pz: float = -1.60 + 0.54 * float(pi)
            var rim := M.cyl_rot(parent, 0.095, 0.095, 0.03,
                Vector3(float(sx) * 0.472, 0.88, pz), M.C_WOOD_DARK,
                Vector3(0.0, 0.0, PI * 0.5), {"outline": 0.01})
            rim.name = "Porthole%s%d" % [side, pi]
            var glass := M.cyl_rot(parent, 0.072, 0.072, 0.045,
                Vector3(float(sx) * 0.470, 0.88, pz), Color.WHITE,
                Vector3(0.0, 0.0, PI * 0.5), {})
            glass.material_override = win_mat
            glass.name = "PortholeGlass%s%d" % [side, pi]

static func _sailboat(root: Node3D, routes: Array) -> Dictionary:
    # The big ship follows the first named out-and-back route. main.gd animates
    # it between routes; the old circular path is gone, the small rowboat is gone.
    var first: Dictionary = routes[0]
    var path: PackedVector3Array = first["out"]
    var node := Node3D.new()
    node.name = "Sailboat"
    node.position = path[0]
    var d0 := path[1] - path[0]
    node.rotation.y = atan2(d0.x, d0.z)
    root.add_child(node)
    var o := {"outline": 0.02}
    # ---- P7-V3 readable hierarchy. Every fitting still descends from the
    # Sailboat root, so it inherits the wave / pitch / roll animation; main.gd
    # keeps referencing only the root node and the returned dictionary keys.
    var g_hull := _boat_group(node, "Hull")
    var g_deck := _boat_group(node, "Deck")
    var g_int := _boat_group(node, "Interior")
    var g_fit := _boat_group(node, "Fittings")
    var g_cabin := _boat_group(node, "Cabin")
    var g_rig := _boat_group(node, "Rig")
    var pair := _sailboat_loft()
    var stations: Array = pair[0]
    var hull := MeshInstance3D.new()
    hull.mesh = pair[1]
    hull.material_override = M.toon_material(M.C_BOAT.lightened(0.06),
        {"bands": 4.0, "soft": 0.55, "rim": 0.14, "outline": 0.022})
    hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    g_hull.add_child(hull)
    var liner := MeshInstance3D.new()
    liner.mesh = pair[2]
    liner.material_override = M.toon_material(M.C_BOAT.darkened(0.30), {"bands": 3.0, "rim": 0.06})
    liner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    g_hull.add_child(liner)
    # gunwale rim: 0.10 x 0.09 timber stitched along every station so the deck
    # edge (deck half width = hull half width - 0.05) lands on its inner face
    for sign_i in [-1.0, 1.0]:
        var sign := float(sign_i)
        for i in range(stations.size() - 1):
            var s0: Vector4 = stations[i]
            var s1: Vector4 = stations[i + 1]
            var a := Vector3(sign * s0.y, s0.z, s0.x)
            var b := Vector3(sign * s1.y, s1.z, s1.x)
            var gw := _bar(g_hull, a + Vector3(0.0, 0.02, 0.0), b + Vector3(0.0, 0.02, 0.0),
                0.10, 0.09, M.C_WOOD_LIGHT, {"outline": 0.014})
            gw.name = "Gunwale%s%02d" % ["P" if sign < 0.0 else "S", i]
    # deck (2 stern + 1 bow hull-hugging planks with an open cockpit between),
    # interior (bilge floor / frames / thwarts / fill blocks) and the cuddy cabin
    var deck_y := 0.52
    var win_mat := M.glass_material(0.06)
    _boat_deck(g_deck, stations, deck_y, o)
    _boat_interior(g_int, stations, deck_y, o)
    _boat_fittings(g_fit, stations, deck_y, o)
    _boat_cabin(g_cabin, deck_y, win_mat, o)
    # mast, boom, gaff and rigging
    var mast_z := 0.55
    var mast_base := Vector3(0.0, deck_y, mast_z)
    var mast_top := Vector3(0.0, deck_y + 4.25, mast_z)
    _seg(g_rig, mast_base, mast_top, 0.085, 0.045, M.C_WOOD, {"outline": 0.016}, 8)
    M.cyl(g_rig, 0.20, 0.24, 0.10, Vector3(0.0, deck_y + 0.05, mast_z), M.C_WOOD_DARK, 0.0, o)
    # Lead P7-V3.2: boom centre 1.90 m above waterline (deck 0.52 + 1.38) so the
    # 0.075 m spar underside gives a 1.66 m sole-to-boom clearance for a 1.50 m
    # islander. Sail foot follows; head stays on the 4.35 m gaff height.
    var boom := _bar(g_rig, Vector3(0.0, deck_y + 1.38, mast_z),
        Vector3(0.0, deck_y + 1.38, -1.35),
        0.075, 0.075, M.C_WOOD_DARK, {"outline": 0.014})
    boom.name = "Boom"
    _bar(g_rig, Vector3(0.0, deck_y + 3.90, mast_z), Vector3(0.0, deck_y + 3.55, -1.30),
        0.055, 0.055, M.C_WOOD, {"outline": 0.012})
    _seg(g_rig, mast_top, Vector3(0.0, 0.80, 2.45), 0.014, 0.012, Color("4a4a46"), {"outline": 0.0}, 4)
    _seg(g_rig, mast_top, Vector3(0.0, 0.75, -2.30), 0.014, 0.012, Color("4a4a46"), {"outline": 0.0}, 4)
    # main sail (cambered two-sided quad) and jib
    var sail_mesh := _sail_quad_mesh()
    # No inverted-hull outline here: a flat two-sided cloth quad would be fully
    # covered by its own outline shell (the sail rendered near-black).
    var sail_mat := M.toon_material(M.C_SAIL, {"bands": 4.0, "rim": 0.10, "outline": 0.0})
    var main_basis := Basis(Vector3(0.0, 0.0, 1.0), Vector3.UP, Vector3(-1.0, 0.0, 0.0))
    var main_sail := MeshInstance3D.new()
    main_sail.name = "MainSail"
    main_sail.mesh = sail_mesh
    main_sail.material_override = sail_mat
    # foot on the raised 1.90 m boom, head at 4.35 m: height 2.45, centre 3.125
    main_sail.transform = Transform3D(main_basis.scaled(Vector3(1.62, 1.225, 1.0)),
        Vector3(0.0, deck_y + 2.605, -0.42))
    main_sail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    g_rig.add_child(main_sail)
    var jib_basis := Basis(Vector3(0.0, 0.0, 1.0), Vector3.UP, Vector3(-1.0, 0.0, 0.0))
    jib_basis = Basis(Vector3.UP, 0.22) * jib_basis
    var jib := MeshInstance3D.new()
    jib.name = "Jib"
    jib.mesh = sail_mesh
    jib.material_override = M.toon_material(M.C_SAIL.darkened(0.06), {"bands": 4.0, "rim": 0.08})
    jib.transform = Transform3D(jib_basis.scaled(Vector3(1.30, 1.28, 0.8)),
        Vector3(0.0, deck_y + 2.35, 1.52))
    jib.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    g_rig.add_child(jib)
    # sail battens: evenly spaced between the 1.90 m boom and the 4.35 m head,
    # running from the luff (z 0.39) to the leech (z -1.23)
    for by in [-1.0, 0.0, 1.0]:
        var byf := (float(by) + 1.5) / 3.0
        var batten_y := deck_y + 1.38 + byf * 2.45
        _bar(g_rig, Vector3(0.0, batten_y, 0.39),
            Vector3(0.0, batten_y, -1.23),
            0.035, 0.035, M.C_WOOD, {"outline": 0.01})
    # pennant, tiller and P5 running lights
    var pennant := MeshInstance3D.new()
    pennant.mesh = sail_mesh
    pennant.material_override = M.toon_material(M.C_TERRACOTTA, {"bands": 3.0, "rim": 0.05})
    pennant.transform = Transform3D(Basis(Vector3(0.0, 0.0, 1.0), Vector3.UP, Vector3(-1.0, 0.0, 0.0))
        .scaled(Vector3(0.34, 0.17, 1.0)), Vector3(0.0, deck_y + 4.22, -0.05))
    pennant.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    g_rig.add_child(pennant)
    # tiller arrives over the stern fill block (deck top is now 0.52, not 0.56)
    _bar(g_fit, Vector3(0.0, deck_y - 0.02, -2.30), Vector3(0.28, deck_y + 0.42, -2.95),
        0.05, 0.05, M.C_WOOD, {"outline": 0.01})
    # ---- P5 hanging lantern on a port-quarter bracket -----------------------
    # Bracket, chain and lantern are plain children of the boat node, so the
    # running light inherits the boat transform and can never drift away.
    var lantern_local_pos := Vector3(-1.02, 0.86, -1.42)
    _bar(node, Vector3(-0.56, deck_y - 0.10, -1.42), Vector3(-0.98, deck_y + 0.60, -1.42),
        0.055, 0.055, M.C_WOOD_DARK, {"outline": 0.012})
    _bar(node, Vector3(-0.98, deck_y + 0.60, -1.42), Vector3(-1.06, deck_y + 0.60, -1.42),
        0.045, 0.045, M.C_WOOD_DARK, {"outline": 0.012})
    M.cyl(node, 0.010, 0.010, 0.18, Vector3(-1.02, deck_y + 0.545, -1.42), Color("4a4a46"), 0.0, {})
    var lantern_mat: ShaderMaterial = M.toon_material(Color("ffd49c"), {"self_lit": true, "glow": 1.0})
    var lantern := M.box(node, Vector3(0.17, 0.22, 0.17), lantern_local_pos, Color.WHITE, 0.0, o)
    lantern.name = "SternLantern"
    lantern.material_override = lantern_mat
    M.cyl(node, 0.115, 0.150, 0.055, lantern_local_pos + Vector3(0.0, 0.140, 0.0), M.C_WOOD_DARK, 0.0, o)
    M.cyl(node, 0.085, 0.105, 0.050, lantern_local_pos + Vector3(0.0, -0.140, 0.0), M.C_WOOD_DARK, 0.0, o)
    var lantern_halo := M.halo(node, lantern_local_pos, 0.88, Color(1.42, 0.98, 0.52, 1.0))
    # ---- P5 forward search light (housing + mirror + soft volume cone) ------
    var spot_lens_pos := Vector3(0.0, deck_y + 0.92, 2.62)
    var spot_node := Node3D.new()
    spot_node.name = "BowSpot"
    spot_node.position = spot_lens_pos
    # main.gd switches this on for night passes only.
    spot_node.visible = false
    node.add_child(spot_node)
    M.cyl_rot(spot_node, 0.150, 0.130, 0.30, Vector3(0.0, 0.0, -0.10), Color("3f433e"),
        Vector3(PI * 0.5, 0.0, 0.0), o)
    M.cyl_rot(spot_node, 0.158, 0.158, 0.05, Vector3(0.0, 0.0, 0.060), Color("2f332e"),
        Vector3(PI * 0.5, 0.0, 0.0), o)
    var lens_disc := M.cyl_rot(spot_node, 0.118, 0.118, 0.028, Vector3(0.0, 0.0, 0.080),
        Color.WHITE, Vector3(PI * 0.5, 0.0, 0.0), {})
    lens_disc.material_override = M.toon_material(Color("ffe9c0"), {"self_lit": true, "glow": 1.0, "outline": 0.0})
    _bar(node, Vector3(0.0, deck_y - 0.02, 2.34), Vector3(0.0, deck_y + 0.84, 2.34),
        0.06, 0.06, M.C_WOOD_DARK, {"outline": 0.012})
    _bar(node, Vector3(0.0, deck_y + 0.84, 2.34), Vector3(0.0, deck_y + 0.92, 2.56),
        0.05, 0.05, M.C_WOOD_DARK, {"outline": 0.012})
    M.box(node, Vector3(0.36, 0.035, 0.20), Vector3(0.0, deck_y + 1.04, 2.44), Color("3f433e"), 0.0, o)
    var spot_cone_mat: ShaderMaterial = ShaderMaterial.new()
    spot_cone_mat.shader = preload("res://shaders/boat_spot.gdshader")
    spot_cone_mat.set_shader_parameter("beam_color", Color(1.0, 0.86, 0.62, 1.0))
    spot_cone_mat.set_shader_parameter("beam_intensity", 0.85)
    spot_cone_mat.set_shader_parameter("beam_length", 9.0)
    var cone := MeshInstance3D.new()
    cone.name = "BeamCone"
    cone.mesh = _spot_cone_mesh(9.0, 2.6, 20)
    cone.material_override = spot_cone_mat
    cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    spot_node.add_child(cone)
    # ---- P5 fade-inventory: every override / next-pass on the boat subtree ---
    var fade_mats: Array = []
    _collect_boat_fade_mats(node, fade_mats)
    node.set_meta("route_count", routes.size())
    return {
        "node": node,
        "path": path,
        "speed": 2.4,
        "lantern_mat": lantern_mat,
        "lantern_halo": lantern_halo,
        "lantern_local_pos": lantern_local_pos,
        "spot_node": spot_node,
        "spot_lens_pos": spot_lens_pos,
        "spot_cone_mat": spot_cone_mat,
        "fade_mats": fade_mats,
        "routes": routes,
    }

## Searches the boat subtree for every material override (and its next_pass chain)
## so main.gd can drive a dither fade-in / fade-out over the whole ship.
static func _collect_boat_fade_mats(pivot: Node, out: Array) -> void:
    if pivot is GeometryInstance3D:
        var gi := pivot as GeometryInstance3D
        var mat: Material = gi.material_override
        var guard := 0
        while mat != null and guard < 8:
            if not out.has(mat):
                out.append(mat)
            mat = mat.next_pass
            guard += 1
    for child in pivot.get_children():
        _collect_boat_fade_mats(child, out)

## Fan mesh for the search light: apex at the origin, rim at +Z. Two-sided by the
## shader's cull_disabled so the soft cone reads from inside the boat too.
static func _spot_cone_mesh(cone_len: float, cone_radius: float, segs: int) -> ArrayMesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for i in range(segs):
        var a0 := TAU * float(i) / float(segs)
        var a1 := TAU * float(i + 1) / float(segs)
        var p0 := Vector3(cos(a0) * cone_radius, sin(a0) * cone_radius, cone_len)
        var p1 := Vector3(cos(a1) * cone_radius, sin(a1) * cone_radius, cone_len)
        st.set_normal(Vector3(cos(a0), sin(a0), 0.0))
        st.set_uv(Vector2(0.0, 0.0))
        st.add_vertex(Vector3.ZERO)
        st.set_normal(Vector3(cos(a0), sin(a0), 0.0))
        st.set_uv(Vector2(float(i) / float(segs), 1.0))
        st.add_vertex(p0)
        st.set_normal(Vector3(cos(a1), sin(a1), 0.0))
        st.set_uv(Vector2(float(i + 1) / float(segs), 1.0))
        st.add_vertex(p1)
    return st.commit()

# ================================================================= lamps ====
# One wooden street lamp on a ground-height stone base. `facing` is the world-space
# direction the arm has to point at (in P5: the path centre line); the local +X arm
# is rotated into it with rotation.y = atan2(-facing.z, facing.x).
static func _lamp(root: Node3D, pos: Vector3, lamp_name: String, facing: Vector3 = Vector3.ZERO) -> Array:
    var node := Node3D.new()
    node.name = lamp_name
    node.position = Vector3(pos.x, _h(pos.x, pos.z), pos.z)
    if facing.length_squared() > 0.000001:
        node.rotation.y = atan2(-facing.z, facing.x)
    root.add_child(node)
    var o := {"outline": 0.02}
    M.box(node, Vector3(0.44, 0.14, 0.44), Vector3(0.0, 0.07, 0.0), M.C_STONE_DARK, 0.0, o)
    # Lead P7-V3.2 lamp spec: light centre at 2.55 m (2.45-2.65), hood/cap top at
    # 2.75 m (2.75-2.85), so the lantern reads above a 1.50 m islander's shoulder
    # without towering over the 3.18 m cottage walls.
    M.cyl(node, 0.075, 0.110, 2.82, Vector3(0.0, 1.445, 0.0), M.C_WOOD_DARK, 0.0, o)
    M.box(node, Vector3(0.50, 0.07, 0.07), Vector3(0.21, 2.85, 0.0), M.C_WOOD_DARK, 0.0, o)
    M.cyl(node, 0.013, 0.013, 0.20, Vector3(0.42, 2.765, 0.0), Color("4a4a46"), 0.0, {})
    var lantern_mat: ShaderMaterial = M.toon_material(Color("ffd7a0"), {"self_lit": true, "glow": 1.0})
    var lamp := M.box(node, Vector3(0.23, 0.27, 0.23), Vector3(0.42, 2.55, 0.0), Color.WHITE, 0.0, o)
    lamp.material_override = lantern_mat
    M.cyl(node, 0.13, 0.17, 0.06, Vector3(0.42, 2.72, 0.0), M.C_WOOD_DARK, 0.0, o)
    M.cyl(node, 0.10, 0.14, 0.06, Vector3(0.42, 2.40, 0.0), M.C_WOOD_DARK, 0.0, o)
    var lantern_world: Vector3 = node.transform * Vector3(0.42, 2.55, 0.0)
    var halo := M.halo(root, lantern_world, 1.18, Color(1.58, 1.08, 0.55, 1.0))
    var facing_dir := Vector3(1.0, 0.0, 0.0)
    if facing.length_squared() > 0.000001:
        facing_dir = Vector3(facing.x, 0.0, facing.z).normalized()
    return [lantern_mat, halo,
        {"pos": lantern_world, "color": Color(1.0, 0.76, 0.45), "range": 7.5, "intensity": 1.35},
        {"name": lamp_name, "base": node.position, "facing": facing_dir, "lantern": lantern_world}]

# Continuous centre line for a range of layout path segments (segment 0 is the
# first main-path segment; see _prepare()).
static func _path_polyline(seg0: int, seg1: int) -> PackedVector2Array:
    var pts := PackedVector2Array()
    for i in range(seg0, seg1 + 1):
        var a := _path_segs[i * 2]
        var b := _path_segs[i * 2 + 1]
        if pts.is_empty():
            pts.append(a)
        elif pts[pts.size() - 1].distance_to(a) > 0.001:
            pts.append(a)
        pts.append(b)
    return pts

# Arc-length sample of a 2D polyline: [position, unit tangent].
static func _sample_path(pts: PackedVector2Array, dist: float) -> Array:
    var acc := 0.0
    for i in range(pts.size() - 1):
        var a := pts[i]
        var b := pts[i + 1]
        var seg := a.distance_to(b)
        if seg < 0.000001:
            continue
        if acc + seg >= dist:
            var u := (dist - acc) / seg
            return [a.lerp(b, u), (b - a) / seg]
        acc += seg
    var n := pts.size()
    var last := pts[n - 1]
    var prev := pts[maxi(n - 2, 0)]
    return [last, (last - prev).normalized()]

# Score a candidate lamp base: grass shoulder beside the path, never on the path,
# never in the walled garden / cottage / dock landing; higher ground preferred.
static func _lamp_spot_score(p: Vector2) -> float:
    var clearance := _path_clearance(p.x, p.y)
    if clearance < 0.16:
        return -1.0e9
    if (p.x > GARDEN_X0 - 0.55 and p.x < GARDEN_X1 + 0.55
            and p.y > GARDEN_Z0 - 0.55 and p.y < GARDEN_Z1 + 0.55):
        return -1.0e9
    if p.distance_to(Vector2(M.HOUSE_X, M.HOUSE_Z)) < 7.1:
        return -1.0e9
    var dock := M.dock_start()
    var ddir := M.dock_dir()
    var rel := p - Vector2(dock.x, dock.z)
    var along := rel.dot(Vector2(ddir.x, ddir.z))
    var across := absf(rel.dot(Vector2(-ddir.z, ddir.x)))
    if along > -1.0 and along < 12.6 and across < 2.5:
        return -1.0e9
    return _h(p.x, p.y) - absf(clearance - 0.40) * 0.5

# Six P5 street lamps along the real path curves: 3 on the main path to the dock,
# 3 on the garden spur. Each base sits half-width + 0.25 m off the centre line and
# the arm is aimed at the centre line. Together with the dock lantern and the
# lighthouse lamp this keeps world.light_sources at 8.
static func _street_lamps(root: Node3D) -> Array:
    var lamps: Array = []
    # (first segment, last segment, half width, arc positions, name prefix)
    var plans: Array = [
        [0, 3, 0.31, [2.4, 9.6, 16.0], "PathLamp"],
        [4, 10, 0.25, [2.2, 8.4, 14.6], "GardenLamp"],
    ]
    for plan in plans:
        var spec: Array = plan
        var pts := _path_polyline(int(spec[0]), int(spec[1]))
        var half_w: float = spec[2]
        var arcs: Array = spec[3]
        var prefix := String(spec[4])
        var idx := 0
        for arc in arcs:
            var sample: Array = _sample_path(pts, float(arc))
            var centre: Vector2 = sample[0]
            var tangent: Vector2 = sample[1]
            var normal := Vector2(-tangent.y, tangent.x)
            var base_pt := centre
            var facing := -normal
            var best := -1.0e20
            for side in [-1.0, 1.0]:
                var cand := centre + normal * float(side) * (half_w + 0.25)
                var score := _lamp_spot_score(cand)
                if score > best:
                    best = score
                    base_pt = cand
                    facing = (centre - cand).normalized()
            # Both shoulders invalid (e.g. pinch point): walk 0.9 m back and retry.
            if best < -1.0e18:
                var alt: Array = _sample_path(pts, maxf(float(arc) - 0.9, 0.4))
                var alt_centre: Vector2 = alt[0]
                var alt_tan: Vector2 = alt[1]
                var alt_n := Vector2(-alt_tan.y, alt_tan.x)
                for side2 in [-1.0, 1.0]:
                    var cand2 := alt_centre + alt_n * float(side2) * (half_w + 0.25)
                    var score2 := _lamp_spot_score(cand2)
                    if score2 > best:
                        best = score2
                        base_pt = cand2
                        facing = (alt_centre - cand2).normalized()
            idx += 1
            var lamp_name := "%s%d" % [prefix, idx]
            lamps.append(_lamp(root, Vector3(base_pt.x, 0.0, base_pt.y), lamp_name,
                Vector3(facing.x, 0.0, facing.y)))
    return lamps

# ======================================================== distant isles ====
static func _distant_isles(root: Node3D) -> void:
    var node := Node3D.new()
    node.name = "DistantIsles"
    root.add_child(node)
    var c_a := Color("5d7076")
    var c_b := Color("7c8b88")
    var specs := [
        [0.62, 470.0, 40.0, 0.15],
        [1.84, 545.0, 52.0, 0.55],
        [3.05, 505.0, 34.0, 0.30],
        [4.28, 590.0, 58.0, 0.80],
        [5.42, 455.0, 30.0, 0.45],
    ]
    for sp in specs:
        var arr: Array = sp
        var ang: float = arr[0]
        var dist: float = arr[1]
        var radius: float = arr[2]
        var mixv: float = arr[3]
        var c := c_a.lerp(c_b, mixv)
        var cx := cos(ang) * dist
        var cz := sin(ang) * dist
        var mat := M.toon_material(c, {"self_lit": true, "glow": 1.0})
        for k in range(3):
            var lump_r := radius * (0.62 - 0.16 * float(k))
            var ox := (float(k) - 1.0) * radius * 0.55
            var oz := sin(float(k) * 2.2 + ang) * radius * 0.22
            var mi := M.sphere(node, lump_r, Vector3(cx + ox, lump_r * 0.10, cz + oz),
                c.lerp(c_b, float(k) * 0.12), Vector3(1.0, 0.42, 0.86), {})
            mi.material_override = mat
    # two low reefs further out
    for rp in [[2.30, 340.0, 9.0], [5.05, 390.0, 12.0]]:
        var arr2: Array = rp
        var ang2: float = arr2[0]
        var dist2: float = arr2[1]
        var rr: float = arr2[2]
        var mi2 := M.sphere(node, rr, Vector3(cos(ang2) * dist2, -rr * 0.55, sin(ang2) * dist2),
            c_a.lerp(c_b, 0.35), Vector3(1.0, 0.30, 0.75), {})
        mi2.material_override = M.toon_material(c_a.lerp(c_b, 0.35), {"self_lit": true, "glow": 1.0})

# =============================================================== perches ====
# Landing spots handed to the bird flock. Every perch is a dictionary:
# {id: String, pos: Vector3, facing: Vector3, radius: float, kind: String}
# plus optional normal / slope / slots (P7-V2 lamp caps pass them explicitly).
# Kinds: tree_branch / roof / eave / lighthouse_platform / dock / garden_post / lamp.
# The cottage roof + porch perches are owned by scripts/cottage.gd and are appended by main.gd.

static func _perch(perch_id: String, pos: Vector3, facing: Vector3, radius: float, kind: String) -> Dictionary:
    var f := facing
    f.y = 0.0
    if f.length_squared() < 0.000001:
        f = Vector3(-1.0, 0.0, 0.0)
    return {"id": perch_id, "pos": pos, "facing": f.normalized(), "radius": radius, "kind": kind}

# P7-V2: perch on a real horizontal solid face with an explicit up normal / slope and an
# explicit slot count (the street-lamp hood caps are ~0.13 m in radius, so one bird only).
# The legacy 16 perches keep their exact five-key dictionaries; only these new points
# add the optional normal / slope / slots keys that fx.gd already understands.
static func _surface_perch(perch_id: String, pos: Vector3, facing: Vector3, radius: float,
        kind: String, normal: Vector3 = Vector3.UP, slope: float = 0.0,
        slots: int = 0) -> Dictionary:
    var out := _perch(perch_id, pos, facing, radius, kind)
    var n := normal
    if n.length_squared() < 0.000001:
        n = Vector3.UP
    out["normal"] = n.normalized()
    out["slope"] = slope
    if slots > 0:
        out["slots"] = slots
    return out

static func _build_perches(big: Dictionary, dock_info: Dictionary, lighthouse: Dictionary,
        lamps: Array = [], include_winter: bool = false) -> Array[Dictionary]:
    var perches: Array[Dictionary] = []

    # ---- big tree: six roosts along its upper limbs --------------------------
    var tree_base: Vector3 = big["pos"]
    var tree_perches: Array = big["perches"]
    for i in range(tree_perches.size()):
        var tp: Vector3 = tree_perches[i]
        var out := Vector3(tp.x - tree_base.x, 0.0, tp.z - tree_base.z)
        perches.append(_perch("tree_%d" % i, tp, out, 0.85, "tree_branch"))

    # NOTE: cottage roof perches (ridge / eave / chimney) are owned by
    # scripts/cottage.gd (_make_perches) which knows the real tile surface and
    # supplies per-perch "normal"/"slope". They used to be duplicated here with
    # guessed heights that sank the birds into the tiles, so this file only
    # contributes tree / lighthouse / dock / garden roosts.

    # ---- lighthouse gallery: four railing corners ---------------------------
    var lp: Array = lighthouse["perches"]
    for i in range(lp.size()):
        perches.append(_perch("lighthouse_%d" % i, lp[i],
            Vector3(-lp[i].x, 0.0, -lp[i].z), 0.45, "lighthouse_platform"))

    # ---- dock: railing perch and bollard cap --------------------------------
    perches.append(_perch("dock_rail", dock_info["perch"],
        Vector3(-dock_info["perch"].x, 0.0, -dock_info["perch"].z), 0.40, "dock"))
    perches.append(_perch("dock_bollard", dock_info["bollard"],
        Vector3(-dock_info["bollard"].x, 0.0, -dock_info["bollard"].z), 0.32, "dock"))

    # ---- garden gate posts (south gate + east gate) --------------------------
    var gate_spots := [
        Vector2(-8.45, GARDEN_Z1), Vector2(-7.20, GARDEN_Z1),
        Vector2(GARDEN_X1, -6.65), Vector2(GARDEN_X1, -5.75),
    ]
    for i in range(gate_spots.size()):
        var g: Vector2 = gate_spots[i]
        var gp := Vector3(g.x, _h(g.x, g.y) + 1.50, g.y)
        perches.append(_perch("garden_post_%d" % i, gp, Vector3(-g.x, 0.0, -g.y), 0.30, "garden_post"))

    # ---- P7-V2 street-lamp hood caps: one roost per lamp (lamp_0..lamp_5) -----------
    # Real geometry from _lamp() (P7-V3.2: light centre 2.55 m per Lead spec): the
    # lantern hood is M.cyl(top_r 0.13, bottom_r 0.17, h 0.06) centred at local
    # (0.42, 2.72, 0), so its flat top face is the horizontal plane local y = 2.75
    # with radius 0.13 -- the only standable surface on the lamp.
    # The hanger rod (r 0.013, local y 2.665..2.865) runs through the cap centre, so the
    # foot point is shifted 0.105 m along local +Z (side = (-facing.z, 0, facing.x)):
    # gull body min clearance to the 0.50x0.07 arm below, and that is 25 mm inside the
    # 0.13 m cap-top radius.  The lamp node
    # only has a yaw rotation and its origin sits at (base.x, ground, base.z), so the
    # cap-top centre in world space is base + facing * 0.42 + UP * 2.75 and the perch
    # point is 0.03 m above it (same foot gap convention as the roof perches).
    # Legacy three-argument calls (probe stubs) pass no lamps -> still exactly 16 points.
    for i in range(lamps.size()):
        var lamp_entry: Array = lamps[i]
        if lamp_entry.size() < 4:
            continue
        var lamp_info: Dictionary = lamp_entry[3]
        var lbase: Vector3 = lamp_info["base"]
        var lface: Vector3 = lamp_info["facing"]
        lface.y = 0.0
        if lface.length_squared() < 0.000001:
            lface = Vector3(1.0, 0.0, 0.0)
        lface = lface.normalized()
        var cap_top: Vector3 = lbase + lface * 0.42 + Vector3.UP * 2.75
        var to_side := Vector3(-lface.z, 0.0, lface.x)
        var lamp_pos: Vector3 = cap_top + to_side * 0.105 + Vector3.UP * 0.03
        perches.append(_surface_perch("lamp_%d" % i, lamp_pos, lface, 0.20, "lamp",
            Vector3.UP, 0.0, 1))

    # ---- P8.1 winter bare-branch roosts (only when explicitly requested) ---------
    # Winter drops the leafy canopy to zero, so the six canopy-surface tree perches
    # become invisible-air points. These five points sit on the real limb surfaces and
    # are only enabled by fx.gd while the winter weight is high enough.
    # Data derived analytically from the _big_tree limb segments (report §6.1); no rng.
    # P8.2-04: winter_branch_4 was moved 0.316 m along the same limb (t 0.750 -> 0.835,
    # local (-0.777,7.610,2.267) -> (-0.9066,7.7154,2.5349)) because a secondary twig
    # sprouted from that limb right inside the previous foot zone: probe_p82_eco_geom
    # measured -0.0154 m clearance at 0.04 m above the perch surface (bird legs would
    # clip the twig). New spot: +0.0802 m min clearance, 1.974 m to winter_branch_3,
    # same limb axis so normal (0.164,0.926,-0.339) / facing / slope (22.1 deg) stay unchanged.
    if include_winter:
        var winter_local := [
            Vector3(1.248, 5.827, 0.015),
            Vector3(2.818, 5.665, 0.833),
            Vector3(-2.009, 6.382, 0.437),
            Vector3(0.975, 7.155, 2.328),
            Vector3(-0.9066, 7.7154, 2.5349),
        ]
        var winter_normal := [
            Vector3(-0.015, 1.000, 0.000),
            Vector3(-0.337, 0.935, -0.112),
            Vector3(0.411, 0.908, -0.077),
            Vector3(-0.117, 0.901, -0.418),
            Vector3(0.164, 0.926, -0.339),
        ]
        var winter_facing := [
            Vector3(1.0, 0.0, 0.0),
            Vector3(0.949, 0.0, 0.316),
            Vector3(-0.983, 0.0, 0.184),
            Vector3(0.271, 0.0, 0.963),
            Vector3(-0.436, 0.0, 0.900),
        ]
        var winter_slope_deg := [0.9, 20.8, 24.7, 25.7, 22.1]
        for i in range(winter_local.size()):
            var wpos: Vector3 = tree_base + (winter_local[i] as Vector3)
            perches.append(_surface_perch("winter_branch_%d" % i, wpos,
                winter_facing[i], 0.55, "winter_branch", winter_normal[i],
                deg_to_rad(float(winter_slope_deg[i])), 1))

    return perches
