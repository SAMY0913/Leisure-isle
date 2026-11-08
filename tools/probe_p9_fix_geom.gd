extends SceneTree
## P9 / P6 visual-fix —— 只读几何探针：码头木板真实几何 / 站位候选 / 路径图 / 鱼竿挂点世界变换。
## 用法：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path 游戏工程 --script res://tools/probe_p9_fix_geom.gd -- --out=DIR

const S := preload("res://scripts/isle_villager_spots.gd")
const W := preload("res://scripts/world.gd")
const M := preload("res://scripts/isle_math.gd")

var _out_dir := "D:/休闲小岛幻境/开发产物/P9/P6/visual-fix/geom"
var _lines: Array = []
var _main: Node = null


func _initialize() -> void:
    for raw in OS.get_cmdline_user_args():
        var s := String(raw)
        if s.begins_with("--out="):
            _out_dir = s.substr(6).strip_edges().trim_suffix("/").trim_suffix("\\")
    DirAccess.make_dir_recursive_absolute(_out_dir)
    _run.call_deferred()


func _emit(s: String) -> void:
    print(s)
    _lines.append(s)


func _run() -> void:
    _emit("=== P9/P6 visual-fix geometry probe ===")
    var ps := load("res://isle.tscn") as PackedScene
    var inst := ps.instantiate()
    root.add_child(inst)
    _main = inst
    _main.set_process(false)
    for i in range(4):
        await process_frame

    var start := M.dock_start()
    var dir := M.dock_dir()
    var yaw := atan2(dir.x, dir.z)
    var wdict: Dictionary = _main.get("_world") as Dictionary
    var dinfo: Dictionary = wdict.get("dock", {}) as Dictionary
    var dnode: Node3D = dinfo.get("node", null) as Node3D
    _emit("[DOCK] start=%s dir=%s yaw=%.5f deck_world_y=%.3f" % [str(start), str(dir), yaw, W.DECK_WORLD_Y])
    _emit("[DOCK] node_origin=%s node_yaw=%.5f" % [str(dnode.global_position), dnode.rotation.y])
    var basis := Basis(Vector3.UP, yaw)
    _emit("[DOCK] basis_check start+dir*11=%s dock_end=%s" % [str(start + dir * M.DOCK_LENGTH), str(M.dock_end())])

    # 木板平面（来自 world.gd _dock：plank_z0=2.05, 18 块, 0.525 间距, 尺寸 3.4 x 0.10 x 0.50）
    var z_lo := 2.05 - 0.25
    var z_hi := 2.05 + 17.0 * 0.525 + 0.25
    _emit("[PLANKS] local x=[-%.2f, %.2f] z=[%.2f, %.2f] top_world_y=%.3f" % [
        M.DOCK_WIDTH * 0.5, M.DOCK_WIDTH * 0.5, z_lo, z_hi, W.DECK_WORLD_Y])

    # 栏杆（posts 在 x=+-1.68, 每根 0.95 高, 沿 z 连接相邻 post）
    var pile_zs := [2.20, 3.92, 5.64, 7.36, 9.08, 10.40]
    _emit("[RAIL] post_x=+-%.2f post_z=%s top_y=%.3f (first pair at z=2.20 has no rail)" % [
        M.DOCK_WIDTH * 0.5 - 0.02, str(pile_zs), W.DECK_WORLD_Y + 0.95])
    _emit("[RAIL] railing spans z=%.2f..%.2f ; z>%.2f (head) has NO side railing" % [
        float(pile_zs[1]), float(pile_zs[5]), float(pile_zs[5])])
    _emit("[BODY] bollards local x=+-1.10 z=9.65 ; lantern post local x=1.52 z=9.35 ; ladder local x=+-0.44 z=11.18")
    _emit("[BODY] deck head z>10.40 is open; plank z ends %.2f" % z_hi)

    # 候选站位（dock-local）→ 世界
    var cands := [9.9, 9.6, 10.4, 8.6, 10.9]
    for lz in cands:
        var lx := 0.0
        var wpos: Vector3 = start + basis * Vector3(lx, W.DECK_WORLD_Y - start.y, float(lz))
        var dist_rail := 1.68 - absf(lx)
        var shore_y := W.surface_y(wpos.x, wpos.z)
        _emit("[CAND] local=(%.2f, deck, %.2f) world=%s terrain_surface_y=%.3f rail_clear=%.2f" % [
            lx, float(lz), str(wpos), shore_y, dist_rail])

    # 世界 AABB：遍历 Dock 子树，收集所有 MeshInstance3D 顶点世界坐标里落在甲板平面附近的
    var deck_min := Vector3(1e9, 1e9, 1e9)
    var deck_max := Vector3(-1e9, -1e9, -1e9)
    var boxes := 0
    for n in _all(dnode):
        var mi := n as MeshInstance3D
        if mi == null or mi.mesh == null:
            continue
        var xf := mi.global_transform
        var aabb := mi.mesh.get_aabb()
        for i in range(8):
            var p := xf * aabb.get_endpoint(i)
            deck_min = Vector3(minf(deck_min.x, p.x), minf(deck_min.y, p.y), minf(deck_min.z, p.z))
            deck_max = Vector3(maxf(deck_max.x, p.x), maxf(deck_max.y, p.y), maxf(deck_max.z, p.z))
        boxes += 1
    _emit("[DOCK_AABB] meshes=%d min=%s max=%s" % [boxes, str(deck_min), str(deck_max)])

    # 船 / 水面等大型遮挡：列出 world 根下所有 Node3D 名字含 Boat/Sail，并给出世界 AABB
    var world_root: Node3D = (wdict.get("root", null) as Node3D)
    if world_root == null:
        world_root = _main.get("_world_root") as Node3D
    var boat_nodes: Array = []
    if world_root != null:
        for n in _all(world_root):
            if n is Node3D and (String(n.name).to_lower().contains("boat") or String(n.name).to_lower().contains("sail")):
                boat_nodes.append(n)
    _emit("[BOATS] count=%d world_root=%s" % [boat_nodes.size(), str(world_root)])
    for bn in boat_nodes:
        var bmin := Vector3(1e9, 1e9, 1e9)
        var bmax := Vector3(-1e9, -1e9, -1e9)
        var anym := false
        for n2 in _all(bn):
            var mi2 := n2 as MeshInstance3D
            if mi2 == null or mi2.mesh == null:
                continue
            var a2 := mi2.mesh.get_aabb()
            for i2 in range(8):
                var p2 := mi2.global_transform * a2.get_endpoint(i2)
                bmin = Vector3(minf(bmin.x, p2.x), minf(bmin.y, p2.y), minf(bmin.z, p2.z))
                bmax = Vector3(maxf(bmax.x, p2.x), maxf(bmax.y, p2.y), maxf(bmax.z, p2.z))
            anym = true
        if anym:
            _emit("[BOAT] %s origin=%s aabb_min=%s aabb_max=%s" % [str(bn.get_path()), str((bn as Node3D).global_position), str(bmin), str(bmax)])
    _emit("[SAIL_ANCHOR] %s" % str(wdict.get("sail_dock_pos", null)))
    # 船体真实 footprint：所有 mesh 顶点投影到 dock-local，统计 x/z 范围（排除桅杆/帆的高处部件）
    var dock_basis := Basis(Vector3.UP, atan2(dir.x, dir.z))
    var hull_min := Vector3(1e9, 1e9, 1e9)
    var hull_max := Vector3(-1e9, -1e9, -1e9)
    if boat_nodes.size() > 0:
        for n3 in _all(boat_nodes[0]):
            var mi3 := n3 as MeshInstance3D
            if mi3 == null or mi3.mesh == null:
                continue
            var a3 := mi3.mesh.get_aabb()
            for i3 in range(8):
                var wp3: Vector3 = mi3.global_transform * a3.get_endpoint(i3)
                if wp3.y > 1.2:
                    continue
                var rel: Vector3 = wp3 - start
                var lx3: float = rel.dot(dock_basis.x)
                var lz3: float = rel.dot(dock_basis.z)
                hull_min = Vector3(minf(hull_min.x, lx3), minf(hull_min.y, wp3.y), minf(hull_min.z, lz3))
                hull_max = Vector3(maxf(hull_max.x, lx3), maxf(hull_max.y, wp3.y), maxf(hull_max.z, lz3))
    _emit("[HULL_LOCAL] y<=1.2 mesh-vertex aabb in dock-local: x=[%.2f, %.2f] z=[%.2f, %.2f] y=[%.2f, %.2f]" % [
        hull_min.x, hull_max.x, hull_min.z, hull_max.z, hull_min.y, hull_max.y])
    # 精确船体：用 loft 的已知 AABB（x +-0.76, y -0.34..0.66, z -2.40..2.55）按真实船节点变换判定
    var boat_node: Node3D = boat_nodes[0] as Node3D
    var bn_inv := boat_node.global_transform.affine_inverse()
    _emit("[BOATPOSE] pos=%s yaw=%.5f heading_dir=%s" % [
        str(boat_node.global_position), boat_node.rotation.y,
        str((boat_node.global_transform.basis * Vector3(0.0, 0.0, 1.0)).normalized())])
    # 船体在 dock-local 的 8 角
    var bh_min := Vector3(1e9, 1e9, 1e9)
    var bh_max := Vector3(-1e9, -1e9, -1e9)
    for i4 in range(8):
        var lp4 := Vector3(
            0.78 if (i4 & 1) else -0.78,
            0.66 if (i4 & 2) else -0.34,
            2.55 if (i4 & 4) else -2.40)
        var wp4: Vector3 = boat_node.global_transform * lp4
        var rel4: Vector3 = wp4 - start
        var lx4: float = rel4.dot(dock_basis.x)
        var lz4: float = rel4.dot(dock_basis.z)
        bh_min = Vector3(minf(bh_min.x, lx4), minf(bh_min.y, wp4.y), minf(bh_min.z, lz4))
        bh_max = Vector3(maxf(bh_max.x, lx4), maxf(bh_max.y, wp4.y), maxf(bh_max.z, lz4))
    _emit("[HULL_EXACT] dock-local x=[%.2f, %.2f] z=[%.2f, %.2f]" % [bh_min.x, bh_max.x, bh_min.z, bh_max.z])
    # 真实钓位（spots.FISH_SPOT_NODE）的落点离船体多远
    var sp_graph: Dictionary = S.build(_main.get("_cottage"))
    var sp_now: Dictionary = S.fishing_spot(sp_graph)
    if not sp_now.is_empty():
        var scp: Vector3 = sp_now["cast_point"]
        var sbl: Vector3 = bn_inv * scp
        var sdx: float = maxf(0.0, absf(sbl.x) - 0.76)
        var sdz: float = maxf(0.0, maxf(-2.40 - sbl.z, sbl.z - 2.55))
        var sp_point: Vector3 = sp_now["point"]
        var spl: Vector3 = sp_point - start
        var scl: Vector3 = scp - start
        _emit("[SPOT_HULL_CLEAR] cast_point=%s boat_local=%s clearance=%.2f m" % [
            str(scp), str(sbl), sqrt(sdx * sdx + sdz * sdz)])
        _emit("[SPOT_HULL_CLEAR] stand_dock_local=(%.2f, %.2f) cast_dock_local=(%.2f, %.2f)" % [
            spl.dot(dock_basis.x), spl.dot(dock_basis.z), scl.dot(dock_basis.x), scl.dot(dock_basis.z)])

    # 候选抛竿落点：从 (0,10.55) 与 (-0.75,10.60) 沿不同角度 3.2 m，检查与船体 footprint 的间隙
    for cand in [[0.0, 10.55], [-0.75, 10.60]]:
        var cx: float = float(cand[0])
        var cz: float = float(cand[1])
        for deg in [0.0, 20.0, 35.0, 50.0, 70.0, 90.0, -20.0, -35.0, -50.0, -70.0, -90.0]:
            var a := deg_to_rad(float(deg))
            var tx := cx + sin(a) * 3.2
            var tz := cz + cos(a) * 3.2
            var wp5: Vector3 = start + dock_basis * Vector3(tx, W.DECK_WORLD_Y - start.y, tz)
            var bl: Vector3 = bn_inv * wp5
            var inside := absf(bl.x) <= 0.85 and bl.z >= -2.60 and bl.z <= 2.75
            # 也检查离船体的平面距离（绝对值越小越危险）
            var dxb: float = maxf(0.0, absf(bl.x) - 0.76)
            var dzb: float = maxf(0.0, maxf(-2.40 - bl.z, bl.z - 2.55))
            var clearance: float = sqrt(dxb * dxb + dzb * dzb)
            _emit("[CASTTRY] stand=(%.2f,%.2f) deg=%6.1f target_local=(%.2f,%.2f) in_hull=%s hull_clear=%.2f" % [
                cx, cz, float(deg), tx, tz, str(inside), clearance])

    # 图节点
    var cottage: Dictionary = _main.get("_cottage")
    var graph := S.build(cottage)
    var nodes: Dictionary = graph["nodes"]
    for id in ["front_path_1", "front_path_2", "shore_path_1", "shore_path_2",
            "dock_shoreside", "dock_step_a", "dock_step_b", "dock_deck_in",
            "dock_walk_mid", "dock_fishing_stand",
            "shore_bank", "shore_sand", "shore_stand"]:
        if nodes.has(id):
            var n: Dictionary = nodes[id]
            var p: Vector3 = n["pos"]
            _emit("[NODE] %-16s pos=%s surface_y=%.3f" % [id, str(p), W.surface_y(p.x, p.z)])
    var spot := S.fishing_spot(graph)
    _emit("[SPOT] %s" % str(spot))
    if not spot.is_empty():
        var cp: Vector3 = spot["cast_point"]
        _emit("[SPOT] cast_point=%s surface_y=%.3f (WATER_Y=0 => 若 surface_y>0 则落点在陆上)" % [
            str(cp), W.surface_y(cp.x, cp.z)])
    var pth := S.find_path(graph, "yard_path_a", "dock_fishing_stand")
    _emit("[PATH] yard_path_a -> dock_fishing_stand = %s" % str(pth))
    _emit("[PATH] valid_issues=%s" % str(S.validate(graph)))
    if not spot.is_empty():
        _emit("[SPOT] surface_under_stand=%.3f (deck=0.72)" % W.surface_y((spot["point"] as Vector3).x, (spot["point"] as Vector3).z))

    # 沿 dock-local 中心线采样地形高度，找 0.72 交线与水线
    _emit("[PROFILE] dock-local z / terrain_y / world xz")
    var z := 0.0
    while z <= 13.0:
        var wp: Vector3 = start + basis * Vector3(0.0, 0.0, z)
        var ty := W.surface_y(wp.x, wp.z)
        _emit("[PROFILE] z=%5.2f terrain_y=%7.3f world=(%.3f, %.3f)" % [z, ty, wp.x, wp.z])
        z += 0.5

    # 鱼竿：村民模型 hand_r 世界变换在 fish_hold 姿态下
    var model = load("res://scripts/isle_villager_model.gd")
    var built: Dictionary = model.create(0)
    var root_node: Node3D = built["root"]
    root.add_child(root_node)
    root_node.position = start + basis * Vector3(0.0, W.DECK_WORLD_Y - start.y, 9.9)
    root_node.rotation.y = atan2(-dir.x, -dir.z)
    await process_frame
    var anim: AnimationPlayer = built["anim"]
    anim.play("fish_hold")
    for i in range(3):
        await process_frame
    var hand: Node3D = (root_node as Object).call("get_joint", "hand_r") as Node3D
    _emit("[MODEL] root_pos=%s yaw=%.4f" % [str(root_node.global_position), root_node.rotation.y])
    _emit("[MODEL] forward(-Z)=%s  hand_r_local=%s hand_r_world=%s" % [
        str(-root_node.global_transform.basis.z.normalized()),
        str(hand.position), str(hand.global_position)])
    _emit("[MODEL] hand_r_basis.x=%s .y=%s .z=%s" % [
        str(hand.global_transform.basis.x.normalized()),
        str(hand.global_transform.basis.y.normalized()),
        str(hand.global_transform.basis.z.normalized())])
    var rod_dir_hand := Vector3(0.0, 0.86, -0.51).normalized()
    _emit("[ROD] current base dir in hand space=%s -> world=%s" % [
        str(rod_dir_hand), str((hand.global_transform.basis * rod_dir_hand).normalized())])
    for name in ["shoulder_r", "elbow_r", "torso", "head"]:
        var j: Node3D = (root_node as Object).call("get_joint", name)
        _emit("[JOINT] %-10s world=%s" % [name, str(j.global_position)])

    var f := FileAccess.open("%s/probe_p9_fix_geom.log" % _out_dir, FileAccess.WRITE)
    if f != null:
        for line in _lines:
            f.store_line(String(line))
        f.close()
    print("[RESULT] geom probe done (%d lines)" % _lines.size())
    quit(0)


func _all(n: Node) -> Array:
    var out: Array = [n]
    for c in n.get_children():
        out.append_array(_all(c))
    return out
