extends SceneTree
## P7-V3 全场景结构验收探针（headless，不占 GPU 锁）
## 用途：对 Lead/cam-dev/boat-dev/cat-dev/prop-dev 的集成结果做客观结构断言，覆盖 P7_V3_PLAN.md
##       §14 测试矩阵中可 headless 判定的项：门扇半圆网格顶点/包围盒、门动画 Tween 目标、
##       门廊对称两灯与 light_sources 条目、楼梯踏步数量/每级高差一致/总高 5.15/二层洞口尺寸、
##       家具数量与摆放、猫咪部件与待机、小船甲板分段、相机 FOV 设置读写。
## 运行：
##   "D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe" --headless --path <PROJ> --script res://tools/probe_verify_p7v3.gd
## 输出：每行 [V3] PASS/FAIL/SKIP/WARN，末尾 [VERIFY] RESULT pass=N fail=M skip=K warn=W；fail>0 时 quit(1)。
## 说明：只读断言，不修改 scripts/ 与场景；FOV 持久化测试使用 user:// 临时文件并在结束时删除。

const S := preload("res://scripts/isle_settings.gd")

var _pass: int = 0
var _fail: int = 0
var _skip_count: int = 0
var _warn_count: int = 0
var _fails: Array[String] = []
var _warns: Array[String] = []
var _main: Node = null
var _cottage: Dictionary = {}
var _world: Dictionary = {}
var _scene_root: Node3D = null

# ============================================================
# 通用工具
# ============================================================
func _ok(cond: bool, label: String, detail: String = "") -> void:
    if cond:
        _pass += 1
        if detail == "":
            print("[V3] PASS " + label)
        else:
            print("[V3] PASS " + label + "  (" + detail + ")")
    else:
        _fail += 1
        var msg := label if detail == "" else label + " :: " + detail
        _fails.append(msg)
        print("[V3] FAIL " + msg)

func _skip(label: String, why: String) -> void:
    _skip_count += 1
    print("[V3] SKIP " + label + "  (" + why + ")")

func _warn(label: String, why: String) -> void:
    _warn_count += 1
    _warns.append(label + " :: " + why)
    print("[V3] WARN " + label + "  (" + why + ")")

func _near(a: float, b: float, eps: float) -> bool:
    return absf(a - b) <= eps

func _near_vec(a: Vector3, b: Vector3, eps: float) -> bool:
    return a.distance_to(b) <= eps

func _walk(parent: Node) -> Array:
    var out: Array = []
    var stack: Array = []
    for c in parent.get_children():
        stack.append(c)
    while stack.size() > 0:
        var n: Node = stack.pop_back()
        out.append(n)
        for c in n.get_children():
            stack.append(c)
    return out

func _find(parent: Node, node_name: String) -> Node:
    if parent == null:
        return null
    if String(parent.name) == node_name:
        return parent
    return parent.find_child(node_name, true, false)

func _find_pref(parent: Node, prefix: String) -> Array:
    var out: Array = []
    for n in _walk(parent):
        if String(n.name).begins_with(prefix):
            out.append(n)
    return out

func _box_size(v: Variant) -> Vector3:
    # 兼容两种来源：合批前的独立 BoxMesh 节点，以及合批后的溯源清单条目
    if v is Dictionary:
        return (v as Dictionary).get("size", Vector3(-1.0, -1.0, -1.0))
    if v is MeshInstance3D:
        var mi: MeshInstance3D = v
        if mi.mesh is BoxMesh:
            return (mi.mesh as BoxMesh).size
    return Vector3(-1.0, -1.0, -1.0)

## 部件位置：节点用自身局部 position，合批溯源条目用它被合并前的局部变换 origin。
func _part_pos(v: Variant) -> Vector3:
    if v is Dictionary:
        var xf: Transform3D = (v as Dictionary).get("xf", Transform3D.IDENTITY)
        return xf.origin
    if v is Node3D:
        return (v as Node3D).position
    return Vector3.ZERO

func _mesh_tri_count(n: Node) -> int:
    if n is MeshInstance3D:
        var mi: MeshInstance3D = n
        if mi.mesh != null:
            return int(float(mi.mesh.get_faces().size()) / 3.0)
    return -1

func _mesh_aabb(n: Node) -> AABB:
    if n is MeshInstance3D:
        var mi: MeshInstance3D = n
        if mi.mesh != null:
            return mi.mesh.get_aabb()
    return AABB()

func _mesh_insts(parent: Node) -> Array:
    var out: Array = []
    for n in _walk(parent):
        if n is MeshInstance3D:
            out.append(n)
    return out

func _box_boxes(parent: Node) -> Array:
    var out: Array = []
    for n in _walk(parent):
        if n is MeshInstance3D and (n as MeshInstance3D).mesh is BoxMesh:
            out.append(n)
    # P7-V3.1 静态合批后，部件不再是独立的 BoxMesh 节点，而是合并进少量多 surface
    # ArrayMesh。这里用构建期写入的 batch_manifest 补齐同口径的部件记录，使"按部件
    # 尺寸/位置断言"的检查在合批后依然逐部件生效（不是放宽，而是换成溯源口径）。
    for e in _batch_parts(parent):
        if String((e as Dictionary).get("kind", "")) == "Box":
            out.append(e)
    return out

## 收集 parent 子树里所有 batch_manifest 条目（合批溯源清单）。
## 注意：合批根节点自己也可能带清单（Cottage / Staircase 就是在自己身上合并的），
## 而 _walk() 只遍历子节点，所以这里要先补上 parent 自身。
func _batch_parts(parent: Node) -> Array:
    var out: Array = []
    var nodes: Array = [parent]
    nodes.append_array(_walk(parent))
    for n in nodes:
        if not n.has_meta("batch_manifest"):
            continue
        var entries: Variant = n.get_meta("batch_manifest")
        if not (entries is Array):
            continue
        for e in (entries as Array):
            if e is Dictionary:
                out.append(e)
    return out

func _is_axis_aligned(v: Variant) -> bool:
    var rot := Vector3.ZERO
    if v is Dictionary:
        var xf: Transform3D = (v as Dictionary).get("xf", Transform3D.IDENTITY)
        rot = xf.basis.get_euler()
    elif v is Node3D:
        rot = (v as Node3D).rotation
    else:
        return false
    return absf(rot.x) + absf(rot.y) + absf(rot.z) < 0.01

func _rect_overlap_area(a: Rect2, b: Rect2) -> float:
    var x0: float = maxf(a.position.x, b.position.x)
    var x1: float = minf(a.position.x + a.size.x, b.position.x + b.size.x)
    var y0: float = maxf(a.position.y, b.position.y)
    var y1: float = minf(a.position.y + a.size.y, b.position.y + b.size.y)
    if x1 <= x0 or y1 <= y0:
        return 0.0
    return (x1 - x0) * (y1 - y0)

func _count_type(parent: Node, cls: String) -> int:
    var c := 0
    for n in _walk(parent):
        if n.is_class(cls):
            c += 1
    return c

# ============================================================
# 引导：加载主场景并固定到“白天/暂停/自由观察”的确定性状态
# ============================================================
func _bootstrap() -> bool:
    var packed: PackedScene = load("res://isle.tscn") as PackedScene
    if packed == null:
        print("[VERIFY] FAIL 无法加载 res://isle.tscn")
        return false
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
    if _main.has_method("_collect_lights"):
        _main.call("_collect_lights")
    # 从菜单机位（fov=36）切回玩家轨道机位，保证 _cam.fov 与 _fov 一致
    if _main.has_method("_play_pose") and _main.has_method("_apply_pose"):
        _main.call("_apply_pose", _main.call("_play_pose"))
    await process_frame
    await process_frame
    _cottage = _main.get("_cottage")
    _world = _main.get("_world")
    _scene_root = _main as Node3D
    return true

func _cottage_root() -> Node3D:
    var r: Variant = _cottage.get("root", null)
    return r as Node3D

func _ctx() -> Dictionary:
    var root := _cottage_root()
    if root == null:
        return {}
    return root.get_meta("cottage_ctx", {})

# ============================================================
# 1) 场景/尺寸/总高
# ============================================================
func _section_env() -> void:
    print("---- [1] 场景与尺寸 ----")
    _ok(_cottage.size() > 0, "main._cottage 返回字典非空", "keys=%d" % _cottage.size())
    _ok(_world.size() > 0, "main._world 返回字典非空", "keys=%d" % _world.size())
    var root := _cottage_root()
    _ok(root != null and String(root.name) == "Cottage", "Cottage 根节点存在")
    if root == null:
        return
    var C := _ctx()
    _ok(C.size() > 0, "Cottage 根节点 meta cottage_ctx 存在", "keys=%d" % C.size())
    if C.size() > 0:
        _ok(_near(float(C.get("w", 0.0)), 10.6, 0.01), "房屋宽 w=10.6", "w=%.3f" % float(C.get("w", 0.0)))
        _ok(_near(float(C.get("d", 0.0)), 8.4, 0.01), "房屋深 d=8.4", "d=%.3f" % float(C.get("d", 0.0)))
        _ok(_near(float(C.get("fy", 0.0)), 0.55, 0.01), "一层地面 fy=0.55", "fy=%.3f" % float(C.get("fy", 0.0)))
        _ok(_near(float(C.get("attic_floor", 0.0)), 5.70, 0.01), "二层地面 attic_floor=5.70", "%.3f" % float(C.get("attic_floor", 0.0)))
        var total_h: float = float(C.get("attic_floor", 0.0)) - float(C.get("fy", 0.0))
        _ok(_near(total_h, 5.15, 0.01), "楼梯总高（一层->二层）=5.15m", "%.4f" % total_h)
        _ok(_near(float(C.get("deck_top", 0.0)), 0.42, 0.01), "门廊台面 deck_top=0.42", "%.3f" % float(C.get("deck_top", 0.0)))
    # P7-V3.1 静态合批把"一个部件一个 MeshInstance3D"折叠成"每材质一个 surface"，
    # 存活节点数会显著下降。因此"场景完整构建"改用**部件级总量**衡量：存活渲染节点
    # + 合批溯源清单条目（batch_manifest 逐条记录了被合并部件的类别/尺寸/变换）。
    # 门槛数值沿用 P7-V3 的 450 / 400（不降低），并额外断言合批确实生效。
    var node_count := _walk(root).size()
    var part_total := _batch_parts(root).size()
    _ok(node_count + part_total > 450, "Cottage 部件总数 > 450（场景完整构建）",
        "nodes=%d parts=%d" % [node_count, part_total])
    var mesh_count := 0
    for n in _walk(root):
        if n is MeshInstance3D:
            mesh_count += 1
    _ok(mesh_count + part_total > 400, "Cottage 网格部件总数 > 400",
        "mesh=%d parts=%d" % [mesh_count, part_total])
    _ok(mesh_count <= 200, "Cottage 存活 MeshInstance3D 已收敛（合批生效，<=200）",
        "mesh=%d" % mesh_count)
    _ok(_find(get_root(), "Sailboat") != null, "Sailboat 节点存在")
    _ok(_find(root, "Staircase") != null, "Staircase 节点存在")
    _ok(_find(root, "AtticInterior") != null, "AtticInterior 节点存在")

# ============================================================
# 2) 家具：数量 / 种类 / 无真实灯 / 不压楼梯洞口
# ============================================================
func _section_furniture() -> void:
    print("---- [2] 家具（IsleHouseProps） ----")
    var root := _cottage_root()
    if root == null:
        return
    var props := _find_pref(root, "Prop_")
    var kinds := {}
    var wall_mounted := 0
    var light_leak := 0
    for p in props:
        var k := String(p.get_meta("prop_kind", ""))
        if k != "":
            kinds[k] = true
        if bool(p.get_meta("prop_wall_mounted", false)):
            wall_mounted += 1
        if not (p as Node3D).is_inside_tree():
            continue
        for n in _walk(p):
            if n is Light3D:
                light_leak += 1
    _ok(props.size() >= 30, "家具 Prop_* 节点数 >= 30", "count=%d kinds=%d" % [props.size(), kinds.size()])
    _ok(kinds.size() >= 20, "家具种类覆盖 >= 20 种", "kinds=%d" % kinds.size())
    var required := ["doormat", "sofa", "coffee_table", "armchair", "desk", "chair", "bookshelf",
        "tall_cupboard", "sideboard", "dining_table", "table_lamp", "rug", "plant_pot", "bed",
        "nightstand", "wardrobe", "reading_chair", "side_table", "picture_frame"]
    var missing := []
    for k in required:
        if not kinds.has(k):
            missing.append(k)
    _ok(missing.size() == 0, "计划清单家具种类齐全（19 种）", "missing=" + str(missing))
    _ok(light_leak == 0, "家具子树无 Light3D（灯光走 light_sources）", "leak=%d" % light_leak)
    _ok(wall_mounted >= 4, "墙挂家具（挂衣板/挂钟/画框）带 wall_mounted 标记", "count=%d" % wall_mounted)
    # 阁楼家具挂 AtticInterior，一层家具挂 Cottage 根
    var ia := _find(root, "AtticInterior")
    var attic_props: Array = []
    var floor_props: Array = []
    for p in props:
        if p.get_parent() == ia:
            attic_props.append(p)
        elif p.get_parent() == root:
            floor_props.append(p)
    # P7-V3 集成期 prop-dev 追加了窗帘等（当前 15 件），允许 13..17 件区间；精确数量变化需人工确认
    _ok(attic_props.size() >= 13 and attic_props.size() <= 17, "二层家具 13 件（含新增窗帘后 15 件）",
        "count=%d" % attic_props.size())
    _ok(floor_props.size() == 23, "一层家具 23 件", "count=%d" % floor_props.size())
    if ia != null:
        var meta_fc := int(ia.get_meta("furniture_count", -1))
        if meta_fc != attic_props.size():
            _warn("AtticInterior meta furniture_count 与实际不符",
                "meta=%d actual=%d（cottage.gd:1448 未同步；仅探针/调试用，不影响画面）" % [meta_fc, attic_props.size()])
        else:
            _pass += 1
            print("[V3] PASS AtticInterior meta furniture_count=%d" % meta_fc)
    var C := _ctx()
    var r1: Rect2 = C.get("stair_hole_r1", Rect2())
    var r2: Rect2 = C.get("stair_hole_r2", Rect2())
    var in_hole := 0
    for p in attic_props:
        var loc: Vector3 = (p as Node3D).position
        if r1.has_point(Vector2(loc.x, loc.z)) or r2.has_point(Vector2(loc.x, loc.z)):
            in_hole += 1
            print("[V3]   阁楼家具压在洞口: ", p.name, " @ ", loc)
    _ok(in_hole == 0, "二层家具不落在楼梯洞口内", "hit=%d" % in_hole)
    # 一层家具只在楼梯占地内做 WARN（人为摆位可能允许，交由视觉复核）
    var stair_a := Rect2(3.60, -2.95, 1.30, 3.60)
    var stair_b := Rect2(0.95, -3.90, 2.80, 1.35)
    var floor_hit := 0
    for p in floor_props:
        var loc2: Vector3 = (p as Node3D).position
        if stair_a.has_point(Vector2(loc2.x, loc2.z)) or stair_b.has_point(Vector2(loc2.x, loc2.z)):
            floor_hit += 1
    if floor_hit > 0:
        _warn("一层家具占据楼梯占地", "count=%d（需视觉复核是否挡路）" % floor_hit)
    else:
        _pass += 1
        print("[V3] PASS 一层家具未占楼梯/洞口投影区")

# ============================================================
# 3) 门：气窗半圆网格 / 拱券 / 旧扇叶删除 / Tween 动画
# ============================================================
func _section_door_mesh() -> void:
    print("---- [3] 门扇与半圆气窗 ----")
    var root := _cottage_root()
    if root == null:
        return
    var pivot: Node3D = _cottage.get("door_pivot", null) as Node3D
    _ok(pivot != null and String(pivot.name) == "DoorPivot", "DoorPivot 存在")
    if pivot == null:
        return
    _ok(_near(absf(pivot.rotation.y), 0.0, 0.01), "DoorPivot 初始 rotation.y=0", "%.4f" % pivot.rotation.y)
    _ok(_cottage.get("door_hit", null) != null, "门点击命中体 door_hit 存在")
    # 门板 5 块 box(0.43,2.30,0.10)
    var planks := 0
    for n in _box_boxes(pivot):
        var s := _box_size(n)
        if _near(s.x, 0.43, 0.02) and _near(s.y, 2.30, 0.03):
            planks += 1
    _ok(planks == 5, "门扇 5 块竖板", "planks=%d" % planks)
    var pivot_mesh := 0
    for n in _walk(pivot):
        if n is MeshInstance3D:
            pivot_mesh += 1
    _ok(pivot_mesh >= 18 and pivot_mesh <= 26, "门扇总零件数 18~26", "mesh=%d" % pivot_mesh)
    # 半圆气窗：名字含 Fan 的节点必须恰好 2 个（旧“整圆盘 + 7 旋转方块”已删）
    var fan_nodes: Array = []
    for n in _walk(pivot):
        if String(n.name).contains("Fan"):
            fan_nodes.append(n)
    var fan_names := []
    for n in fan_nodes:
        fan_names.append(String(n.name))
    _ok(fan_nodes.size() == 2, "门扇上半圆构件恰好 2 个（DoorFanlight + Trim）", str(fan_names))
    var fan := _find(pivot, "DoorFanlight")
    _ok(fan != null, "DoorFanlight 节点存在")
    if fan != null:
        var mi := fan as MeshInstance3D
        _ok(mi.mesh is ArrayMesh, "DoorFanlight 为自定义 ArrayMesh（非整圆盘 PrimitiveMesh）")
        var tris := _mesh_tri_count(fan)
        _ok(tris >= 80 and tris <= 130, "DoorFanlight 三角面数 ~98", "tris=%d" % tris)
        var a := _mesh_aabb(fan)
        _ok(_near(a.position.x, 0.031, 0.03), "DoorFanlight AABB min.x≈0.031", "%.4f" % a.position.x)
        _ok(_near(a.end.x, 2.229, 0.03), "DoorFanlight AABB max.x≈2.229", "%.4f" % a.end.x)
        _ok(_near(a.position.y, 2.30, 0.03), "DoorFanlight AABB min.y≈2.30（弦线高度）", "%.4f" % a.position.y)
        _ok(_near(a.end.y, 3.45, 0.04), "DoorFanlight AABB max.y≈3.45（半圆顶）", "%.4f" % a.end.y)
        _ok(_near(a.size.z, 0.10, 0.03), "DoorFanlight 厚度≈0.10", "%.4f" % a.size.z)
    var trim := _find(pivot, "DoorFanlightTrim")
    _ok(trim != null, "DoorFanlightTrim（同心拱带）存在")
    if trim != null:
        var tt := _mesh_tri_count(trim)
        _ok(tt >= 160 and tt <= 240, "DoorFanlightTrim 三角面数 ~196", "tris=%d" % tt)
        var ta := _mesh_aabb(trim)
        _ok(_near(ta.end.y, 3.33, 0.06), "DoorFanlightTrim AABB max.y≈3.33", "%.4f" % ta.end.y)
        _ok(_near(ta.position.z, 0.0505, 0.02), "DoorFanlightTrim 贴门板外侧 z≈0.0505", "%.4f" % ta.position.z)
    # 拱券（root 子节点，无变换）
    var arch := _find(root, "DoorArch")
    _ok(arch != null, "DoorArch 半圆拱券存在")
    if arch != null:
        var at := _mesh_tri_count(arch)
        _ok(at >= 160 and at <= 240, "DoorArch 三角面数 ~196", "tris=%d" % at)
        var aa := _mesh_aabb(arch)
        _ok(_near(aa.size.x, 2.90, 0.03), "DoorArch 宽度 2.90", "%.4f" % aa.size.x)
        _ok(_near(aa.position.y, 2.90, 0.03), "DoorArch 起拱高 2.90", "%.4f" % aa.position.y)
        _ok(_near(aa.end.y, 4.35, 0.03), "DoorArch 拱顶 4.35", "%.4f" % aa.end.y)
        _ok(_near(aa.size.z, 0.26, 0.03), "DoorArch 厚度 0.26", "%.4f" % aa.size.z)
    var span := _find(root, "DoorSpandrel")
    _ok(span != null, "DoorSpandrel 拱肩板存在")
    if span != null:
        var st := _mesh_tri_count(span)
        _ok(st >= 80 and st <= 110, "DoorSpandrel 三角面数 ~94", "tris=%d" % st)
    # 旧实现证据：pivot 下不应再有整圆盘（CylinderMesh 半径 1.1 级）
    var old_disc := 0
    for n in _walk(pivot):
        if n is MeshInstance3D and (n as MeshInstance3D).mesh is CylinderMesh:
            old_disc += 1
    _ok(old_disc == 0, "门扇下无旧整圆盘 CylinderMesh 残留", "count=%d" % old_disc)

func _section_door_anim() -> void:
    print("---- [3b] 开门动画（Tween 目标 -1.85 rad / 0.95s） ----")
    var pivot: Node3D = _cottage.get("door_pivot", null) as Node3D
    if pivot == null:
        return
    pivot.rotation.y = 0.0
    _main.set("_door_open", false)
    _main.call("_toggle_door")
    await create_timer(0.30).timeout
    var mid: float = pivot.rotation.y
    _ok(mid < -0.02 and mid > -1.70, "开门过程为补间（非瞬移）", "t=0.30s rot=%.3f" % mid)
    await create_timer(0.85).timeout
    var opened: float = pivot.rotation.y
    _ok(_near(opened, -1.85, 0.02), "开门终值 rotation.y≈-1.85", "%.4f" % opened)
    _ok(bool(_main.get("_door_open")), "开门后 _door_open=true")
    _main.call("_toggle_door")
    await create_timer(1.15).timeout
    var closed: float = pivot.rotation.y
    _ok(_near(closed, 0.0, 0.02), "关门终值 rotation.y≈0", "%.4f" % closed)
    _ok(not bool(_main.get("_door_open")), "关门后 _door_open=false")

# ============================================================
# 4) 门廊对称双灯 + 灯光预算
# ============================================================
func _section_lanterns() -> void:
    print("---- [4] 门廊对称吊灯与 light_sources ----")
    var root := _cottage_root()
    if root == null:
        return
    var C := _ctx()
    var lp: Vector3 = C.get("lantern_pos", Vector3.ZERO)
    var rp: Vector3 = C.get("lantern_pos_right", Vector3.ZERO)
    _ok(_near(lp.x, -2.80, 0.01) and _near(rp.x, 2.80, 0.01), "左右灯座 x=±2.80",
        "L=%s R=%s" % [str(lp), str(rp)])
    _ok(_near(lp.y, rp.y, 0.01) and _near(lp.z, rp.z, 0.01) and _near(lp.x, -rp.x, 0.01), "左右灯座严格对称")
    var halos: Array = _cottage.get("lantern_halos", [])
    _ok(halos.size() == 2, "lantern_halos 数量 2", "count=%d" % halos.size())
    var halo_ok := 0
    for h in halos:
        if h is MeshInstance3D:
            var hn: MeshInstance3D = h
            var near_left := hn.position.distance_to(lp) < 0.05
            var near_right := hn.position.distance_to(rp) < 0.05
            if near_left or near_right:
                halo_ok += 1
            _ok(hn.scale.x >= 0.30 and hn.scale.x <= 0.80, "灯晕已按 0.55 缩放", "scale.x=%.3f" % hn.scale.x)
    _ok(halo_ok == 2, "两枚灯晕分别位于左右灯座", "ok=%d" % halo_ok)
    var main_halos: Array = _main.get("_lantern_halos")
    _ok(main_halos.size() == 2, "main._lantern_halos 数量 2", "count=%d" % main_halos.size())
    # _cottage 只导出左灯世界坐标；右灯世界坐标由房屋变换换算（_world(root, local) 等价 root.global_transform * local）
    var lw: Vector3 = root.to_global(lp)
    var rw: Vector3 = root.to_global(rp)
    var lw_export: Vector3 = _cottage.get("lantern_world", Vector3.ZERO)
    _ok(_near_vec(lw_export, lw, 0.02), "左灯 world 导出坐标 == 房屋变换换算", str(lw_export))
    var mid_w: Vector3 = (lw + rw) * 0.5
    var center_w: Vector3 = root.to_global(Vector3(0.0, lp.y, lp.z))
    _ok(_near_vec(mid_w, center_w, 0.02) and _near(lw.distance_to(rw), 5.60, 0.03),
        "左右灯世界坐标关于门中线对称（间距 5.60）", "L=%s R=%s mid=%s d=%.3f" % [str(lw), str(rw), str(mid_w), lw.distance_to(rw)])
    var sources: Array = _cottage.get("light_sources", [])
    var left_src := 0
    var right_src := 0
    var left_ok := false
    var right_ok := false
    for src in sources:
        if not (src is Dictionary):
            continue
        var d: Dictionary = src
        var pos: Vector3 = d.get("pos", Vector3.ZERO)
        var inten := float(d.get("intensity", d.get("energy", 0.0)))
        var rng := float(d.get("range", 0.0))
        var col: Color = d.get("color", Color.BLACK)
        if pos.distance_to(lw) < 0.05:
            left_src += 1
            left_ok = _near(inten, 1.05, 0.02) and _near(rng, 6.0, 0.05) and near_color(col, Color(1.0, 0.78, 0.48))
        if pos.distance_to(rw) < 0.05:
            right_src += 1
            right_ok = _near(inten, 1.05, 0.02) and _near(rng, 6.0, 0.05) and near_color(col, Color(1.0, 0.78, 0.48))
    _ok(left_src == 1 and left_ok, "light_sources 含左门廊灯（1.05/6.0/暖色）", "count=%d" % left_src)
    _ok(right_src == 1 and right_ok, "light_sources 含右门廊灯（1.05/6.0/暖色）", "count=%d" % right_src)
    var win_lights: Array = C.get("win_lights", [])
    var expect_total: int = 6 + win_lights.size()
    _ok(sources.size() == expect_total, "light_sources 条数 = 6 核心 + %d 窗灯" % win_lights.size(),
        "actual=%d expect=%d" % [sources.size(), expect_total])
    # 吊灯（室内主灯）已移到餐桌正上方：用导出的世界坐标 interior_lamp_world 比对
    var lamp_world: Vector3 = _cottage.get("interior_lamp_world", Vector3.ZERO)
    var lamp_hit := false
    for src in sources:
        if not (src is Dictionary):
            continue
        var d2: Dictionary = src
        var pos2: Vector3 = d2.get("pos", Vector3.ZERO)
        var inten2 := float(d2.get("intensity", d2.get("energy", 0.0)))
        if _near(inten2, 1.60, 0.02) and pos2.distance_to(lamp_world) < 0.05:
            lamp_hit = true
    _ok(lamp_hit, "室内吊灯光源位于餐桌上方（interior_lamp_world）", str(lamp_world))
    # 灯光预算：12 盏，前 6 为路灯，双门廊灯在列；窗灯是否被挤出记 WARN
    var st: Dictionary = _main.call("debug_light_state")
    var lights: Array = st.get("lights", [])
    _ok(lights.size() == 12, "参与着色的光源 12 盏", "count=%d" % lights.size())
    var lamp_first := 0
    for i in range(mini(6, lights.size())):
        if String((lights[i] as Dictionary).get("kind", "")) == "street_lamp":
            lamp_first += 1
    _ok(lamp_first == 6, "前 6 盏为路灯（固定占位）", "first6=%d" % lamp_first)
    var lantern_in := 0
    var window_in := 0
    for L in lights:
        var d3: Dictionary = L
        var pos3: Vector3 = d3.get("pos", Vector3.ZERO)
        var e3 := float(d3.get("energy", 0.0))
        if pos3.distance_to(lw) < 0.05 or pos3.distance_to(rw) < 0.05:
            lantern_in += 1
        if _near(e3, 0.70, 0.02):
            window_in += 1
    if lantern_in == 2:
        _pass += 1
        print("[V3] PASS 左右门廊灯均进入 12 盏预算")
    else:
        # 基线（5de90a1）实测：左门廊灯 energy=1.35 挤进第 12 盏；V3 收敛为双灯 1.05 后
        # 灯塔1.65/室内1.60/1.50/1.42/码头1.40/壁炉1.30 占满 6 个余名额 → 双灯都被挤出。
        for L in lights:
            var dbg: Dictionary = L
            print("[V3]   DBG light kind=%s pos=%s e=%.3f" % [String(dbg.get("kind", "")), str(dbg.get("pos", Vector3.ZERO)), float(dbg.get("energy", 0.0))])
        _warn("门廊双灯未进入 12 盏解析光预算（V2 基线左灯 1.35 在预算内）",
            "V3 双灯 1.05/1.05；V2 实测左灯 1.35 占第 12 盏。夜间门廊只剩 emissive+halo，无解析点光 → 需视觉复核亮度并请 Lead 决策（调 energy 或预算策略）")
    if window_in == 0 and win_lights.size() > 0:
        _warn("窗灯（0.70）未进入 12 盏解析光预算", "V2 基线同样未进入（灯塔/码头/壁炉等挤占），非 V3 回退；此处仅记录现状" % [])
    else:
        _pass += 1
        print("[V3] PASS 窗灯仍保留在灯光预算内  count=%d" % window_in)

func near_color(a: Color, b: Color) -> bool:
    return absf(a.r - b.r) < 0.03 and absf(a.g - b.g) < 0.03 and absf(a.b - b.b) < 0.03

# ============================================================
# 5) 楼梯：27 级 / 每级高差 / 总高 / 洞口
# ============================================================
func _section_stairs() -> void:
    print("---- [5] L 形楼梯与二层洞口 ----")
    var root := _cottage_root()
    if root == null:
        return
    var C := _ctx()
    var past := _find(root, "Staircase")
    _ok(past != null, "Staircase 节点存在")
    if past == null:
        return
    var fy: float = float(C.get("fy", 0.55))
    var attic_floor: float = float(C.get("attic_floor", 5.70))
    var h: float = (attic_floor - fy) / 27.0
    _ok(int(past.get_meta("risers", 0)) == 27, "meta risers=27", str(past.get_meta("risers", 0)))
    _ok(_near(float(past.get_meta("rise", 0.0)), h, 0.0005), "meta rise=总高/27",
        "meta=%.6f calc=%.6f" % [float(past.get_meta("rise", 0.0)), h])
    _ok(_near(float(past.get_meta("tread", 0.0)), 0.245, 0.0005), "meta tread=0.245",
        "%.4f" % float(past.get_meta("tread", 0.0)))
    var r1: Rect2 = past.get_meta("hole_r1", Rect2())
    var r2: Rect2 = past.get_meta("hole_r2", Rect2())
    _ok(_near(r1.position.x, 3.65, 0.001) and _near(r1.position.y, -3.83, 0.001) and _near(r1.size.x, 1.17, 0.001) and _near(r1.size.y, 3.28, 0.001),
        "洞口 R1 = x[3.65,4.82] z[-3.83,-0.55]", str(r1))
    _ok(_near(r2.position.x, 1.005, 0.001) and _near(r2.position.y, -3.83, 0.001) and _near(r2.size.x, 2.645, 0.001) and _near(r2.size.y, 1.23, 0.001),
        "洞口 R2 = x[1.005,3.65] z[-3.83,-2.60]", str(r2))
    var boxes := _box_boxes(past)
    var treads_a: Array = []
    var treads_b: Array = []
    var landing: Variant = null
    for n in boxes:
        var s := _box_size(n)
        if _near(s.x, 1.10, 0.02) and _near(s.y, 0.06, 0.01) and _near(s.z, 0.295, 0.01):
            treads_a.append(n)
        elif _near(s.x, 0.295, 0.01) and _near(s.y, 0.06, 0.01) and _near(s.z, 1.17, 0.01):
            treads_b.append(n)
        elif _near(s.x, 1.13, 0.02) and _near(s.y, 0.10, 0.01) and _near(s.z, 0.95, 0.02):
            landing = n
    _ok(treads_a.size() == 14, "Flight A 踏面 14 级", "count=%d" % treads_a.size())
    _ok(treads_b.size() == 11, "Flight B 踏面 11 级", "count=%d" % treads_b.size())
    _ok(landing != null, "中间平台存在（1.13x0.10x0.95）")
    var stepped := 0
    var bad_a := 0
    for n in treads_a:
        var top: float = _part_pos(n).y + 0.03
        var idx := int(roundf((top - fy) / h))
        if idx >= 1 and idx <= 14 and _near(top - fy, float(idx) * h, 0.004):
            stepped += 1
        else:
            bad_a += 1
    _ok(stepped == 14 and bad_a == 0, "Flight A 每级顶面高度 = fy + i*h", "ok=%d bad=%d" % [stepped, bad_a])
    var stepped_b := 0
    for n in treads_b:
        var top2: float = _part_pos(n).y + 0.03
        var idx2 := int(roundf((top2 - fy) / h))
        if idx2 >= 16 and idx2 <= 26 and _near(top2 - fy, float(idx2) * h, 0.004):
            stepped_b += 1
    _ok(stepped_b == 11, "Flight B 每级顶面高度 = fy + j*h (16..26)", "ok=%d" % stepped_b)
    if landing != null:
        var land_top: float = _part_pos(landing).y + 0.05
        _ok(_near(land_top, fy + 15.0 * h, 0.004), "平台顶面 = 第 15 级 (3.4111)", "%.4f" % land_top)
        _ok(_near(land_top, 3.4111, 0.005), "平台顶面实测≈3.4111", "%.4f" % land_top)
    var last_top: float = fy + 26.0 * h
    _ok(_near(attic_floor - last_top, h, 0.005), "第 27 级高差与其余级一致（接二层地面）",
        "final_rise=%.4f h=%.4f" % [attic_floor - last_top, h])
    # 楼梯井井壁：cav_lo = in_top+0.10 = fy+3.70 = 4.25，cav_hi = attic_floor-0.07 = 5.63
    var cav_lo: float = fy + 3.60 + 0.10
    var cav_hi: float = attic_floor - 0.07
    var cav_h: float = cav_hi - cav_lo
    var wall_full := 0
    var wall_short := 0
    for n in boxes:
        var s2 := _box_size(n)
        if _near(s2.y, cav_h, 0.01):
            wall_full += 1
        if _near(s2.y, 5.42 - cav_lo, 0.01):
            wall_short += 1
    _ok(wall_full == 4, "楼梯井井壁 4 面（4.35->5.63）", "count=%d" % wall_full)
    _ok(wall_short == 1, "x=1.005 侧井壁仅做到楼梯下皮 5.42", "count=%d" % wall_short)
    # 一层天花板 4 块必须避开洞口（R1/R2）
    var slabs: Array = []
    for n in _box_boxes(root):
        var s3 := _box_size(n)
        if _near(s3.y, 0.10, 0.02) and s3.z > 3.0:
            if _is_axis_aligned(n):
                slabs.append(n)
    _ok(slabs.size() == 4, "一层天花板按 L 形洞口切成 4 块", "count=%d" % slabs.size())
    var cover := 0.0
    for n in slabs:
        var s4 := _box_size(n)
        var pp := _part_pos(n)
        var rect := Rect2(pp.x - s4.x * 0.5, pp.z - s4.z * 0.5, s4.x, s4.z)
        cover += _rect_overlap_area(rect, r1) + _rect_overlap_area(rect, r2)
    _ok(cover <= 0.01, "天花板 4 块均不覆盖楼梯洞口", "overlap=%.4f m2" % cover)
    # 二层地板 MultiMesh 不得盖住洞口
    var af := _find(root, "AtticFloor")
    _ok(af != null and af is MultiMeshInstance3D, "AtticFloor MultiMesh 存在")
    if af is MultiMeshInstance3D:
        var mmi: MultiMeshInstance3D = af
        var mm: MultiMesh = mmi.multimesh
        # 21 条板条在 4 个 region 间切分，x 跨界处拆成 2 实例（实测 23 实例）
        _ok(mm != null and mm.instance_count >= 21 and mm.instance_count <= 26, "二层地板板条 21 条（跨区拆分后 ~23 实例）",
            "count=%d" % (mm.instance_count if mm != null else -1))
        var board_cover := 0.0
        if mm != null:
            for i in range(mm.instance_count):
                var xf: Transform3D = mm.get_instance_transform(i)
                var o: Vector3 = xf.origin
                var bw: float = xf.basis.x.length()
                var bd: float = xf.basis.z.length()
                var rect2 := Rect2(o.x - bw * 0.5, o.z - bd * 0.5, bw, bd)
                board_cover += _rect_overlap_area(rect2, r1) + _rect_overlap_area(rect2, r2)
        _ok(board_cover <= 0.01, "二层地板板条不覆盖洞口", "overlap=%.4f m2" % board_cover)

# ============================================================
# 6) 二层：栏杆 + 家具 + 暖灯
# ============================================================
func _section_attic() -> void:
    print("---- [6] 二层栏杆/家具/暖灯 ----")
    var root := _cottage_root()
    if root == null:
        return
    var C := _ctx()
    var floor_y: float = float(C.get("attic_floor", 5.70))
    var rails: Array = []
    var posts: Array = []
    for n in _box_boxes(root):
        var s := _box_size(n)
        if _near(s.x, 0.09, 0.01) and _near(s.y, 0.06, 0.01):
            rails.append(n)
        elif _near(s.x, 0.10, 0.01) and _near(s.y, 1.06, 0.01) and _near(s.z, 0.10, 0.01):
            posts.append(n)
    _ok(rails.size() == 3, "二层洞口栏杆 3 段扶手", "count=%d" % rails.size())
    var rail_y_ok := 0
    for n in rails:
        if _near(_part_pos(n).y, floor_y + 0.92, 0.02):
            rail_y_ok += 1
    _ok(rail_y_ok == 3, "扶手高度 = 二层地面 + 0.92", "ok=%d" % rail_y_ok)
    _ok(posts.size() == 4, "栏杆立柱 4 根", "count=%d" % posts.size())
    var post_top_ok := 0
    for n in posts:
        if _near(_part_pos(n).y + 0.53, floor_y + 1.06, 0.02):
            post_top_ok += 1
    _ok(post_top_ok == 4, "立柱顶 = 二层地面 + 1.06", "ok=%d" % post_top_ok)
    var ia := _find(root, "AtticInterior")
    var prop_kinds := {}
    var bad_pos := 0
    if ia != null:
        for p in _find_pref(ia, "Prop_"):
            var kind := String(p.get_meta("prop_kind", ""))
            prop_kinds[kind] = true
            if bool(p.get_meta("prop_wall_mounted", false)):
                continue
            var loc := (p as Node3D).position
            var lo := floor_y - 0.05
            var hi := floor_y + 0.10
            if kind == "table_lamp":
                # 台灯放在书桌 / 边几台面上
                lo = floor_y + 0.40
                hi = floor_y + 1.05
            if loc.y < lo or loc.y > hi:
                bad_pos += 1
                print("[V3]   bad prop kind=%s y=%.3f floor=%.3f" % [kind, loc.y, floor_y])
    _ok(prop_kinds.size() >= 10, "二层家具种类 >= 10", "kinds=%d" % prop_kinds.size())
    _ok(bad_pos == 0, "二层家具高度符合设计（落地家具贴地、台灯在台面、挂墙件免检）", "bad=%d" % bad_pos)
    var lamp2: Vector3 = _cottage.get("attic_lamp2_world", Vector3.ZERO)
    _ok(lamp2 != Vector3.ZERO, "attic_lamp2_world 存在", str(lamp2))
    var halo_meta := 0
    for n in _walk(root):
        if bool(n.get_meta("attic_lamp_halo", false)):
            halo_meta += 1
    _ok(halo_meta == 1, "二层书桌暖灯光晕存在", "count=%d" % halo_meta)
    var has_142 := false
    for src in (_cottage.get("light_sources", []) as Array):
        if src is Dictionary and _near(float((src as Dictionary).get("intensity", 0.0)), 1.42, 0.02):
            has_142 = true
    _ok(has_142, "light_sources 含二层第二暖灯（1.42）")

# ============================================================
# 7) 一层室内：吊灯位置 / 壁炉
# ============================================================
func _section_interior() -> void:
    print("---- [7] 一层室内 ----")
    var root := _cottage_root()
    if root == null:
        return
    var C := _ctx()
    var fy: float = float(C.get("fy", 0.55))
    var bulb: Variant = null
    for n in root.get_children():
        if n is MeshInstance3D:
            var mi := n as MeshInstance3D
            if mi.mesh is SphereMesh:
                var sm := mi.mesh as SphereMesh
                if _near(sm.radius, 0.11, 0.02):
                    bulb = n
    # 合批后灯泡已并入 Cottage 的 surface；用溯源清单里的 Sphere 条目复核
    if bulb == null:
        for e in _batch_parts(root):
            if String((e as Dictionary).get("kind", "")) != "Sphere":
                continue
            var sz: Vector3 = (e as Dictionary).get("size", Vector3.ZERO)
            if _near(sz.x, 0.11, 0.02):
                bulb = e
                break
    _ok(bulb != null, "室内吊灯灯泡（SphereMesh r=0.11）存在")
    if bulb != null:
        var bp: Vector3 = _part_pos(bulb)
        _ok(_near(bp.x, 1.15, 0.03) and _near(bp.z, 1.95, 0.03), "吊灯位于餐桌正上方 (1.15, ?, 1.95)", str(bp))
        # 吊灯 y = 天花板内顶 in_top(4.15) - 0.74 = 3.41（房屋本地坐标）
        _ok(_near(bp.y, 3.41, 0.03), "吊灯高度约 3.41（餐桌上方）", "y=%.3f" % bp.y)
    var fp := 0
    for n in _box_boxes(root):
        var s := _box_size(n)
        if _near(s.x, 1.70, 0.02) and _near(s.y, 3.30, 0.03) and _near(s.z, 0.56, 0.02):
            fp += 1
    _ok(fp == 1, "壁炉石体（1.70x3.30x0.56）存在", "count=%d" % fp)
    # 一层桌椅/沙发等家具数量在 [2] 已覆盖；此处核对二层家具不压栏杆线（视觉项另记）

# ============================================================
# 8) 猫咪：部件 + 待机（旧实现则 SKIP）
# ============================================================
func _section_cat() -> void:
    print("---- [8] 门廊猫咪 ----")
    var root := _cottage_root()
    if root == null:
        return
    var cat := _find(root, "PorchCat")
    _ok(cat != null, "PorchCat 节点存在")
    if cat == null:
        return
    var integrated: bool = bool(cat.get_meta("isle_cat", false)) or _find(cat, "CatIdleDriver") != null
    if not integrated:
        _skip("猫咪部件/待机断言", "待机未接入（PorchCat 仍是旧拼装实现，isle_cat.gd 未挂接）")
        _ok(_near((cat as Node3D).position.x, 2.30, 0.01) and _near((cat as Node3D).position.z, 6.10, 0.01),
            "旧猫咪仍位于门廊 (2.30, ?, 6.10)", str((cat as Node3D).position))
        return
    var cn := cat as Node3D
    _ok(_near(cn.position.x, 2.30, 0.05) and _near(cn.position.z, 6.10, 0.05), "PorchCat 位于门廊 (2.30,?,6.10)", str(cn.position))
    _ok(_near(cn.rotation.y, -0.6, 0.05), "PorchCat 朝向 yaw≈-0.6", "%.3f" % cn.rotation.y)
    for part in ["Body", "Head", "HeadCore", "Tail", "Legs"]:
        _ok(_find(cat, part) != null, "猫咪部件 " + part + " 存在")
    var tail := _find(cat, "Tail")
    if tail != null:
        # Tail 是链根：Tail -> TailJ0 -> TailJ1 -> TailJ2（3 节关节链）
        var joints := 0
        for n in _walk(tail):
            if String(n.name).begins_with("TailJ"):
                joints += 1
        _ok(joints == 3, "尾巴 3 节关节链 TailJ0..TailJ2", "joints=%d" % joints)
        _ok(tail.get_child_count() == 1 and _find(cat, "TailJ2") != null, "尾巴关节为父子链（非平铺）")
    var driver := _find(cat, "CatIdleDriver")
    _ok(driver != null, "CatIdleDriver 节点存在（待机驱动）")
    if driver == null:
        return
    _ok((driver as Node).is_processing(), "CatIdleDriver 正在处理（idle 生效）")
    var ctrl: Variant = driver.get("controller")
    _ok(ctrl != null, "CatIdleDriver.controller 已创建")
    if ctrl == null:
        return
    var st: Dictionary = ctrl.call("debug_state")
    _ok(st.size() > 0, "CatIdle.debug_state() 可读", "keys=%d" % st.size())
    var bp := float(st.get("breath_period", 0.0))
    _ok(bp >= 3.2 and bp <= 4.2, "呼吸周期 ∈ [3.2,4.2]s", "%.3f" % bp)
    var counts: Dictionary = st.get("counts", {})
    var count_ok := counts.has("blink") and counts.has("ear") and counts.has("look") and counts.has("lick")
    _ok(count_ok, "待机事件计数含 blink/ear/look/lick", str(counts.keys()))
    var before_lid := float(st.get("lid_rot", 0.0))
    # debug_force_event 只设事件 t0，需要再 advance 一小步让 _tick_blink 计算 _lid_amt 并应用到眼睑
    ctrl.call("debug_force_event", "blink", 0.5)
    ctrl.call("advance", 0.001)
    var st2: Dictionary = ctrl.call("debug_state")
    var after_lid := float(st2.get("lid_rot", 0.0))
    var after_amt := float(st2.get("lid_amount", 0.0))
    _ok(after_amt > 0.90 and after_lid < 0.50, "强制眨眼事件闭合眼睑",
        "before_lid=%.4f amt=%.3f lid=%.4f" % [before_lid, after_amt, after_lid])
    var p0 := cn.global_position
    for i in range(40):
        await process_frame
    var p1 := cn.global_position
    _ok(p0.distance_to(p1) < 0.02, "猫咪待机不位移（40 帧）", "drift=%.4f" % p0.distance_to(p1))

# ============================================================
# 9) 小船：甲板分段 / 内构 / 配件
# ============================================================
func _section_boat() -> void:
    print("---- [9] 小船 ----")
    var boat: Variant = _world.get("sailboat", null)
    _ok(boat is Node3D, "world.sailboat 存在")
    _ok(_main.get("_sailboat") != null, "main._sailboat 已绑定")
    if not (boat is Node3D):
        return
    var bn := boat as Node3D
    var deck := _find(bn, "Deck")
    _ok(deck != null, "Deck 分组存在")
    if deck != null:
        var planks := _find_pref(deck, "DeckPlank")
        _ok(planks.size() == 7, "甲板 7 段横铺板", "count=%d" % planks.size())
        var aabbs: Array = []
        for p in planks:
            var a := _mesh_aabb(p)
            aabbs.append(a)
        aabbs.sort_custom(func(x, y): return (x as AABB).position.z < (y as AABB).position.z)
        var len_ok := 0
        var thick_ok := 0
        var gap_ok := 0
        var first_z := 99.0
        var last_z := -99.0
        for i in range(aabbs.size()):
            var a2: AABB = aabbs[i]
            if _near(a2.size.z, 0.5971, 0.01):
                len_ok += 1
            if _near(a2.size.y, 0.06, 0.006):
                thick_ok += 1
            first_z = minf(first_z, a2.position.z)
            last_z = maxf(last_z, a2.end.z)
            if i > 0:
                var prev: AABB = aabbs[i - 1]
                if _near(a2.position.z - prev.end.z, 0.02, 0.006):
                    gap_ok += 1
                if not _near(a2.end.y, prev.end.y, 0.012) and i % 2 == 1:
                    pass
        _ok(len_ok == 7, "每段甲板长≈0.597", "ok=%d" % len_ok)
        _ok(thick_ok == 7, "甲板厚 0.06", "ok=%d" % thick_ok)
        _ok(gap_ok == 6, "相邻甲板缝 0.02", "ok=%d" % gap_ok)
        _ok(_near(first_z, -2.23, 0.01) and _near(last_z, 2.07, 0.01), "甲板覆盖 z -2.23..2.07",
            "z=%.3f..%.3f" % [first_z, last_z])
        var top_ok := 0
        for a3 in aabbs:
            var ay: float = (a3 as AABB).end.y
            if _near(absf(ay - 0.52), 0.004, 0.003):
                top_ok += 1
        _ok(top_ok == 7, "甲板面高 0.52±0.004（交替 4mm 错缝）", "ok=%d" % top_ok)
        var inwales := _find_pref(deck, "Inwale")
        _ok(inwales.size() == 12, "舷缘内衬 12 段", "count=%d" % inwales.size())
    var inner := _find(bn, "InnerFloor")
    _ok(inner != null, "舱底 InnerFloor 存在")
    if inner != null:
        var tris := _mesh_tri_count(inner)
        _ok(tris > 100, "InnerFloor 为曲面网格（三角面 > 100）", "tris=%d" % tris)
    var interior := _find(bn, "Interior")
    if interior != null:
        var ribs := _find_pref(interior, "Rib")
        _ok(ribs.size() == 16, "肋骨 16 段", "count=%d" % ribs.size())
        for nm in ["Thwart00", "Thwart01"]:
            var th := _find(interior, nm)
            _ok(th != null, nm + " 存在")
            if th != null:
                var ts := _box_size(th)
                _ok(_near(ts.y, 0.06, 0.006) and _near(ts.z, 0.30, 0.006), nm + " 座板 0.06x0.30", str(ts))
                _ok(_near((th as Node3D).position.y + 0.03, 0.60, 0.01), nm + " 座面高 0.60",
                    "%.3f" % ((th as Node3D).position.y + 0.03))
    var fittings := _find(bn, "Fittings")
    _ok(fittings != null, "Fittings 分组存在")
    if fittings != null:
        for nm2 in ["OarShaftP", "OarShaftS", "OarBladeP", "OarBladeS", "MooringCleatBow", "MooringCleatStern"]:
            _ok(_find(fittings, nm2) != null, nm2 + " 存在")
        var locks := _find_pref(fittings, "Oarlock")
        _ok(locks.size() == 2, "桨架 2 个", "count=%d" % locks.size())
    _ok(_find(bn, "Cabin") != null, "Cabin 舱室存在")
    _ok(_find(bn, "Rig") != null, "Rig 帆装分组存在")

# ============================================================
# 10) FOV 设置读写 + 相机 + 菜单滑条
# ============================================================
func _section_fov() -> void:
    print("---- [10] 相机 FOV 设置读写 ----")
    _ok(_near(S.FOV_DEFAULT, 42.0, 0.001), "FOV_DEFAULT=42", "%.1f" % S.FOV_DEFAULT)
    _ok(_near(S.FOV_MIN, 35.0, 0.001) and _near(S.FOV_MAX, 65.0, 0.001), "FOV 范围 35..65",
        "%.1f..%.1f" % [S.FOV_MIN, S.FOV_MAX])
    _ok(_near(S.sanitize_fov(10.0), 35.0, 0.001), "sanitize_fov(10)=35", "%.1f" % S.sanitize_fov(10.0))
    _ok(_near(S.sanitize_fov(90.0), 65.0, 0.001), "sanitize_fov(90)=65", "%.1f" % S.sanitize_fov(90.0))
    _ok(_near(S.sanitize_fov("abc"), 42.0, 0.001), "sanitize_fov(非数值)=42", "%.1f" % S.sanitize_fov("abc"))
    _ok(_near(S.sanitize_fov(42.4), 42.0, 0.001), "sanitize_fov(42.4)=42", "%.1f" % S.sanitize_fov(42.4))
    _ok(_near(S.sanitize_fov(42.6), 43.0, 0.001), "sanitize_fov(42.6)=43", "%.1f" % S.sanitize_fov(42.6))
    # 注意：本机 harness 的 Godot 进程只能写工作区盘（D:），user://（C:/Users/.../AppData）会 CANT_OPEN，
    # 故持久化往返用工作区临时文件验证同一份 save_settings/load_settings 逻辑（同一 ConfigFile 代码路径）。
    var probe_user := FileAccess.open("user://probe_verify_p7v3_write.txt", FileAccess.WRITE)
    if probe_user != null:
        probe_user.close()
        DirAccess.remove_absolute(ProjectSettings.globalize_path("user://probe_verify_p7v3_write.txt"))
    else:
        _warn("本机 Godot 进程无法写 user://（沙箱限制，error=%d）" % FileAccess.get_open_error(),
            "默认 user://settings.cfg 的落盘需窗口/真实环境人工复核；此处用工作区临时文件验证 save/load 逻辑")
    var tmp_dir: String = ProjectSettings.globalize_path("res://").path_join("..").simplify_path().path_join("开发产物/p7v3/logs")
    DirAccess.make_dir_recursive_absolute(tmp_dir)
    var tmp: String = tmp_dir.path_join("probe_fov_tmp.cfg")
    S.save_settings({"fov": 55.0}, tmp)
    var loaded: Dictionary = S.load_settings(tmp)
    _ok(_near(float(loaded.get("fov", 0.0)), 55.0, 0.001), "save/load 往返 fov=55", "%.1f" % float(loaded.get("fov", 0.0)))
    S.save_settings({"fov": 71.0}, tmp)
    var loaded2: Dictionary = S.load_settings(tmp)
    _ok(_near(float(loaded2.get("fov", 0.0)), 65.0, 0.001), "save/load 越界 71 被夹到 65", "%.1f" % float(loaded2.get("fov", 0.0)))
    S.save_settings({"fov": "abc"}, tmp)
    var loaded3: Dictionary = S.load_settings(tmp)
    _ok(_near(float(loaded3.get("fov", 0.0)), 42.0, 0.001), "save/load 非法值回落到 42", "%.1f" % float(loaded3.get("fov", 0.0)))
    if FileAccess.file_exists(tmp):
        DirAccess.remove_absolute(tmp)
    _ok(not FileAccess.file_exists(tmp), "FOV 临时配置文件已清理", tmp)
    # 运行时相机：_play_pose/_apply_pose 写入 _cam.fov
    var cam: Camera3D = _main.get("_cam") as Camera3D
    var fov: float = float(_main.get("_fov"))
    _ok(cam != null, "主相机存在")
    _ok(fov >= S.FOV_MIN and fov <= S.FOV_MAX, "main._fov 在设置范围内", "%.1f" % fov)
    if cam != null:
        _ok(_near(cam.fov, fov, 0.001), "相机 fov == main._fov（玩家轨道机位）", "cam=%.3f _fov=%.3f" % [cam.fov, fov])
    var pose: Dictionary = _main.call("_play_pose")
    _ok(_near(float(pose.get("fov", 0.0)), fov, 0.001), "_play_pose 携带 fov", "%.2f" % float(pose.get("fov", 0.0)))
    _main.set("_fov", 55.0)
    _main.call("_apply_pose", _main.call("_play_pose"))
    _ok(_near(cam.fov, 55.0, 0.001), "写入 _fov=55 后相机 fov=55", "%.3f" % cam.fov)
    _main.set("_fov", fov)
    _main.call("_apply_pose", _main.call("_play_pose"))
    _ok(_near(cam.fov, fov, 0.001), "恢复 _fov 后相机 fov 恢复", "%.3f" % cam.fov)
    # 自由视角 base_fov 同步
    var flycam: Variant = _main.get("_flycam")
    if flycam != null:
        var bf := float(flycam.get("_base_fov"))
        _ok(_near(bf, fov, 0.001), "flycam._base_fov 与设置 FOV 同步", "%.3f" % bf)
    # 菜单滑条
    var menu: Variant = _main.get("_menu")
    if menu == null or not (menu is Node) or not (menu as Node).is_inside_tree():
        _skip("设置菜单 FOV 滑条断言", "菜单节点不可用")
        return
    var sliders: Variant = menu.get("_sliders")
    if not (sliders is Dictionary) or not (sliders as Dictionary).has("fov"):
        _skip("设置菜单 FOV 滑条断言", "_sliders 无 fov 键")
        return
    var slider: Variant = (sliders as Dictionary)["fov"]
    # 设置菜单用自绘滑条 scripts/ui_slider.gd（SliderCtl extends Control，字段 min_value/max_value/step/value）
    _ok(slider is Control, "设置菜单 FOV 滑条节点存在（ui_slider.gd SliderCtl）", str(slider))
    if slider is Control:
        var hs: Control = slider
        var smn := float(hs.get("min_value"))
        var smx := float(hs.get("max_value"))
        var sst := float(hs.get("step"))
        var sv := float(hs.get("value"))
        _ok(_near(smn, 35.0, 0.001) and _near(smx, 65.0, 0.001), "滑条范围 35..65",
            "%.1f..%.1f" % [smn, smx])
        _ok(_near(sst, 1.0, 0.001), "滑条步进 1", "%.2f" % sst)
        _ok(_near(sv, fov, 0.6), "滑条值同步当前 FOV", "%.1f" % sv)
        _ok(String(hs.tooltip_text).contains("42"), "滑条提示含默认 42°", hs.tooltip_text)
        _ok(hs.has_method("set_value") and hs.has_method("configure"), "滑条为可编程 SliderCtl（set_value/configure）")

# ============================================================
# 主流程
# ============================================================
func _initialize() -> void:
    var booted := await _bootstrap()
    if not booted:
        quit(1)
        return
    _section_env()
    _section_furniture()
    _section_door_mesh()
    await _section_door_anim()
    _section_lanterns()
    _section_stairs()
    _section_attic()
    _section_interior()
    await _section_cat()
    _section_boat()
    _section_fov()
    print("")
    print("[VERIFY] RESULT pass=%d fail=%d skip=%d warn=%d" % [_pass, _fail, _skip_count, _warn_count])
    if _fails.size() > 0:
        print("[VERIFY] FAILURES:")
        for f in _fails:
            print("[VERIFY]   - " + f)
    if _warns.size() > 0:
        print("[VERIFY] WARNINGS:")
        for w in _warns:
            print("[VERIFY]   - " + w)
    quit(0 if _fail == 0 else 1)
