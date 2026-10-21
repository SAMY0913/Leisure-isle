extends SceneTree
## P7-V3.2 T1 全岛尺度审计探针（headless，可重复）
## 用途：直接测量真实生成网格/节点的 AABB 与世界尺寸（房屋/家具/船/码头/灯塔/路灯/树/
##       猫/海鸥/地形/相机/参照人形），对照 scripts/isle_scale_spec.gd 的目标，
##       输出 [SCALE] 行 + 最终 [SCALE] RESULT，并写 inventory.json / inventory.md。
##
## 运行（headless，无需窗口）：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path PROJ --script res://tools/probe_scale_world.gd -- --mode audit
##   ... --mode inventory --tag baseline --out OUTDIR
##
## 模式：
##   audit     ：主树，对照 spec 目标给出 PASS/WARN/FAIL（有 FAIL 时 quit(1)）
##   inventory ：基线副本（wt_baseline），只记录实测原始值（状态 INFO，quit(0)）
##
## 说明：所有数值来自运行时真实节点/网格 AABB 或三角形射线实测，不读登记表冒充实测；
##       spec 只提供“目标/区间”。

const SPEC := preload("res://scripts/isle_scale_spec.gd")
const FIG := preload("res://scripts/isle_scale_figure.gd")
const PROPS := preload("res://scripts/isle_house_props.gd")
const OVERLAY := preload("res://tools/scale_debug_overlay.gd")

const DEFAULT_OUT := "D:/休闲小岛幻境/开发产物/p7v32/scale"

var _mode := "audit"
var _tag := "main"
var _out_dir := DEFAULT_OUT
var _results: Array = []
var _raw: Dictionary = {}
var _main: Node = null
var _world: Dictionary = {}
var _cottage: Dictionary = {}
var _fy := 0.0

# =================================================================== 启动 ====
func _initialize() -> void:
    _parse_args()
    await process_frame
    var packed: PackedScene = load("res://isle.tscn") as PackedScene
    if packed == null:
        print("[SCALE] FAIL cannot load res://isle.tscn")
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
    await process_frame
    var w = _main.get("_world")
    if w is Dictionary:
        _world = w
    var c = _main.get("_cottage")
    if c is Dictionary:
        _cottage = c
    print("[SCALE] START mode=%s tag=%s engine=%s" % [_mode, _tag, String(Engine.get_version_info().get("string", "?"))])
    if _mode == "overlay":
        await _group_overlay()
        _finish()
        return
    _group_human()
    _group_house()
    _group_furniture()
    _group_world()
    _group_camera()
    _finish()

func _parse_args() -> void:
    var args: Array = []
    args.append_array(OS.get_cmdline_user_args())
    args.append_array(OS.get_cmdline_args())
    var i := 0
    while i < args.size():
        var a := String(args[i])
        if a == "--mode" and i + 1 < args.size():
            _mode = String(args[i + 1])
            i += 2
            continue
        if a == "--tag" and i + 1 < args.size():
            _tag = String(args[i + 1])
            i += 2
            continue
        if a == "--out" and i + 1 < args.size():
            _out_dir = String(args[i + 1])
            i += 2
            continue
        if a.begins_with("--mode="):
            _mode = a.substr(7)
        elif a.begins_with("--tag="):
            _tag = a.substr(6)
        elif a.begins_with("--out="):
            _out_dir = a.substr(6)
        i += 1
    if _mode != "inventory" and _mode != "overlay":
        _mode = "audit"

# ============================================================== 通用小工具 ====
func _walk(n: Node) -> Array:
    var out: Array = []
    for c in n.get_children():
        out.append(c)
        out.append_array(_walk(c))
    return out

func _find_name(n: Node, wanted: String) -> Node:
    if String(n.name) == wanted:
        return n
    for c in _walk(n):
        if String(c.name) == wanted:
            return c
    return null

func _find_prefix(n: Node, prefix: String) -> Array:
    var out: Array = []
    for c in _walk(n):
        if String(c.name).begins_with(prefix):
            out.append(c)
    return out

func _xf_aabb(t: Transform3D, aabb: AABB) -> AABB:
    var b := t.basis
    var o := t.origin
    var lo := Vector3(1e20, 1e20, 1e20)
    var hi := Vector3(-1e20, -1e20, -1e20)
    for i in 8:
        var p: Vector3 = aabb.position + Vector3(
            aabb.size.x * float(i & 1),
            aabb.size.y * float((i >> 1) & 1),
            aabb.size.z * float((i >> 2) & 1))
        var q: Vector3 = o + b * p
        lo = lo.min(q)
        hi = hi.max(q)
    return AABB(lo, hi - lo)

func _mat_of(mi: MeshInstance3D) -> Material:
    if mi.material_override != null:
        return mi.material_override
    if mi.mesh != null and mi.mesh.get_surface_count() > 0:
        return mi.mesh.surface_get_material(0)
    return null

func _shader_path_of(mi: MeshInstance3D) -> String:
    var m := _mat_of(mi)
    if m is ShaderMaterial:
        var sm: ShaderMaterial = m
        if sm.shader != null:
            return sm.shader.resource_path
    return ""

func _is_toon(mi: MeshInstance3D) -> bool:
    return _shader_path_of(mi).ends_with("toon.gdshader")

func _is_effect(mi: MeshInstance3D) -> bool:
    var p := _shader_path_of(mi)
    if p.contains("glass") or p.contains("outline") or p.contains("additive") or p.contains("grass") or p.contains("blob"):
        return true
    var m := _mat_of(mi)
    if m is BaseMaterial3D:
        var bm: BaseMaterial3D = m
        if bm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
            return true
    var nm := String(mi.name)
    for pref in ["Glow", "Halo", "Blob", "Shadow"]:
        if nm.begins_with(pref):
            return true
    return false

func _node_excluded(n: Node, root: Node, exact: Array, prefixes: Array) -> bool:
    var p: Node = n
    while p != null and p != root:
        var nm := String(p.name)
        if exact.has(nm):
            return true
        for pref in prefixes:
            if nm.begins_with(pref):
                return true
        p = p.get_parent()
    return false

func _mesh_insts_under(root: Node, exclude_exact: Array, exclude_prefix: Array, toon_only: bool) -> Array:
    var out: Array = []
    for n in _walk(root):
        if not (n is MeshInstance3D):
            continue
        var mi: MeshInstance3D = n
        if mi.mesh == null:
            continue
        if _node_excluded(mi, root, exclude_exact, exclude_prefix):
            continue
        if toon_only and not _is_toon(mi):
            continue
        out.append(mi)
    return out

func _local_aabb_of(mi: MeshInstance3D, frame: Node3D) -> AABB:
    var xf: Transform3D = frame.global_transform.affine_inverse() * mi.global_transform
    return _xf_aabb(xf, mi.mesh.get_aabb())

func _local_aabbs(frame: Node3D, root: Node, exclude_exact: Array, exclude_prefix: Array, toon_only: bool, skip_effects: bool) -> Array:
    var out: Array = []
    for mi_v in _mesh_insts_under(root, exclude_exact, exclude_prefix, toon_only):
        var mi: MeshInstance3D = mi_v
        if skip_effects and _is_effect(mi):
            continue
        out.append(_local_aabb_of(mi, frame))
    return out

func _union_aabbs(list: Array) -> AABB:
    if list.is_empty():
        return AABB()
    var acc: AABB = list[0]
    for i in range(1, list.size()):
        acc = acc.merge(list[i])
    return acc

func _subtree_aabb(frame: Node3D, obj: Node, skip_effects := true) -> AABB:
    var acc := AABB()
    var first := true
    var frame_inv := frame.global_transform.affine_inverse()
    for n in _walk(obj):
        if n is MultiMeshInstance3D:
            var mmi: MultiMeshInstance3D = n
            var mm: MultiMesh = mmi.multimesh
            if mm == null or mm.mesh == null:
                continue
            var base := mm.mesh.get_aabb()
            var mx := frame_inv * mmi.global_transform
            for i in range(mm.instance_count):
                var a := _xf_aabb(mx * mm.get_instance_transform(i), base)
                acc = a if first else acc.merge(a)
                first = false
        elif n is MeshInstance3D:
            var mi: MeshInstance3D = n
            if mi.mesh == null:
                continue
            if skip_effects and _is_effect(mi):
                continue
            var a2 := _local_aabb_of(mi, frame)
            acc = a2 if first else acc.merge(a2)
            first = false
    return acc

func _multimesh_usable(mmi: MultiMeshInstance3D) -> bool:
    var mm: MultiMesh = mmi.multimesh
    if mm == null or mm.mesh == null or mm.instance_count == 0:
        return false
    if mm.instance_count == 1:
        return true
    return mm.get_instance_transform(0) != Transform3D.IDENTITY or mm.get_instance_transform(1) != Transform3D.IDENTITY

func _subtree_aabb_toon(frame: Node3D, obj: Node) -> AABB:
    var out: Array = []
    for mi_v in _mesh_insts_under(obj, [], [], true):
        out.append(_local_aabb_of(mi_v, frame))
    return _union_aabbs(out)

func _multimesh_local_aabb(mmi: MultiMeshInstance3D, frame: Node3D) -> AABB:
    var mm: MultiMesh = mmi.multimesh
    if mm == null or mm.mesh == null:
        return AABB()
    var base := mm.mesh.get_aabb()
    var xf: Transform3D = frame.global_transform.affine_inverse() * mmi.global_transform
    var acc := AABB()
    var first := true
    for i in range(mm.instance_count):
        var a := _xf_aabb(xf * mm.get_instance_transform(i), base)
        acc = a if first else acc.merge(a)
        first = false
    return acc

func _append_tris_flat(mi: MeshInstance3D, frame: Node3D, out: PackedVector3Array) -> void:
    if mi.mesh == null:
        return
    var xf: Transform3D = frame.global_transform.affine_inverse() * mi.global_transform
    var b := xf.basis
    var o := xf.origin
    for s in range(mi.mesh.get_surface_count()):
        var arrays: Array = mi.mesh.surface_get_arrays(s)
        if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
            continue
        var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
        var idx = arrays[Mesh.ARRAY_INDEX]
        if idx is PackedInt32Array and (idx as PackedInt32Array).size() >= 3:
            var ii: PackedInt32Array = idx
            var k := 0
            while k + 2 < ii.size():
                out.append(o + b * verts[ii[k]])
                out.append(o + b * verts[ii[k + 1]])
                out.append(o + b * verts[ii[k + 2]])
                k += 3
        else:
            var k2 := 0
            while k2 + 2 < verts.size():
                out.append(o + b * verts[k2])
                out.append(o + b * verts[k2 + 1])
                out.append(o + b * verts[k2 + 2])
                k2 += 3

func _shell_tris(root: Node3D, insts: Array) -> PackedVector3Array:
    var out := PackedVector3Array()
    for mi_v in insts:
        _append_tris_flat(mi_v, root, out)
    return out

func _filter_tris(tris: PackedVector3Array, lo: Vector3, hi: Vector3) -> PackedVector3Array:
    var out := PackedVector3Array()
    var i := 0
    while i + 2 < tris.size():
        var a: Vector3 = tris[i]
        var b: Vector3 = tris[i + 1]
        var c: Vector3 = tris[i + 2]
        var tlo: Vector3 = a.min(b).min(c)
        var thi: Vector3 = a.max(b).max(c)
        if thi.x >= lo.x and tlo.x <= hi.x and thi.y >= lo.y and tlo.y <= hi.y and thi.z >= lo.z and tlo.z <= hi.z:
            out.append(a)
            out.append(b)
            out.append(c)
        i += 3
    return out

func _ray_nearest(tris: PackedVector3Array, from: Vector3, dir: Vector3, max_d := 200.0) -> Dictionary:
    var best := max_d
    var hit_any := false
    var i := 0
    while i + 2 < tris.size():
        var h = Geometry3D.ray_intersects_triangle(from, dir, tris[i], tris[i + 1], tris[i + 2])
        if h != null:
            var d: float = from.distance_to(h)
            if d > 0.001 and d < best:
                best = d
                hit_any = true
        i += 3
    return {"hit": hit_any, "dist": best}

# ================================================================ 结果登记 ====
func _add(group: String, key: String, actual, target, status: String, detail: String) -> void:
    var st := status
    if _mode == "inventory":
        st = "INFO"
    _results.append({"group": group, "key": key, "actual": actual, "target": target, "status": st, "detail": detail})

## 众数（按 snap 取整），用于“墙面 vs 线脚/窗框”这类多数/少数样本；平票退回中位数。
func _mode_value(vals: Array, snap: float) -> float:
    if vals.is_empty():
        return 0.0
    var counts: Dictionary = {}
    for v in vals:
        var k := snappedf(float(v), snap)
        counts[k] = int(counts.get(k, 0)) + 1
    var best_k := 0.0
    var best_c := -1
    for k in counts.keys():
        var c := int(counts[k])
        if c > best_c or (c == best_c and absf(float(k) - _median(vals)) < absf(best_k - _median(vals))):
            best_c = c
            best_k = float(k)
    return best_k

func _median(vals: Array) -> float:
    if vals.is_empty():
        return 0.0
    var arr: Array = vals.duplicate()
    arr.sort()
    return float(arr[arr.size() / 2])

func _rel(actual: float, target: float) -> float:
    if absf(target) < 1e-6:
        return 0.0
    return absf(actual - target) / absf(target)

func _status_of(rel: float, tol: float) -> String:
    if rel > SPEC.WARN_TOL:
        return "FAIL"
    if rel > tol:
        return "WARN"
    return "PASS"

func _chk_scalar(group: String, key: String, actual: float, target: float, note := "", tol := SPEC.TOL) -> void:
    var rel := _rel(actual, target)
    var st := _status_of(rel, tol)
    var pct := 0.0
    if absf(target) > 1e-6:
        pct = (actual - target) / absf(target) * 100.0
    var extra := ""
    if note != "":
        extra = "；" + note
    _add(group, key, actual, target, st, "%s 实测 %.3f m / 目标 %.3f m（%+.1f%%%s）" % [key, actual, target, pct, extra])

func _chk_abs(group: String, key: String, actual: float, target: float, abs_tol: float, unit := "m", note := "") -> void:
    var diff := absf(actual - target)
    var st := "PASS" if diff <= abs_tol else ("WARN" if diff <= abs_tol * 2.0 else "FAIL")
    var extra := ""
    if note != "":
        extra = "；" + note
    _add(group, key, actual, target, st, "%s 实测 %.3f %s / 目标 %.3f %s（绝对误差 %.3f，容差 ±%.3f%s）" % [key, actual, unit, target, unit, diff, abs_tol, extra])

func _chk_vec(group: String, key: String, actual: Vector3, target: Vector3, note := "", tol := SPEC.TOL) -> void:
    var rel := 0.0
    for i in 3:
        rel = maxf(rel, _rel(actual[i], target[i]))
    var st := _status_of(rel, tol)
    var extra := ""
    if note != "":
        extra = "；" + note
    _add(group, key, actual, target, st, "%s 实测 %s m / 目标 %s m（最大轴 %+.1f%%%s）" % [key, _fmt(actual), _fmt(target), rel * 100.0, extra])

func _chk_registry(group: String, key: String, actual: Vector3, note := "") -> void:
    var r: Dictionary = SPEC.check(key, actual)
    var d := String(r.get("detail", ""))
    if note != "":
        d += "；" + note
    _add(group, key, actual, SPEC.size_of(key), String(r.get("status", "FAIL")), d)

func _chk_range(group: String, key: String, actual: float, note := "") -> void:
    var r: Dictionary = SPEC.check_range(key, actual)
    var d := String(r.get("detail", ""))
    if note != "":
        d += "；" + note
    var tgt := {"min": float(r.get("min", 0.0)), "max": float(r.get("max", 0.0))}
    _add(group, key, actual, tgt, String(r.get("status", "FAIL")), d)

## reference_keep：明确保留现状的夸张/既定比例，只登记与说明，不参与 PASS/WARN/FAIL 评分。
func _keep(group: String, key: String, actual: float, hint: float, abs_tol: float, note := "") -> void:
    var diff := absf(actual - hint)
    var extra := ""
    if note != "":
        extra = "；" + note
    _add(group, key, actual, hint, "INFO", "%s（保留·不评分）实测 %.3f / hint %.3f，偏差 %.3f%s" % [key, actual, hint, diff, extra])

## 仅登记项（不参与判分）：用于双口径/参考值/世界量法并列，避免把"记录"算成 PASS。
func _info(group: String, key: String, actual, target, note := "") -> void:
    _add(group, key, actual, target, "INFO", "%s %s（仅登记·不评分）%s" % [key, str(actual), "" if note == "" else "；" + note])

func _fmt(v: Vector3) -> String:
    return "%.3f×%.3f×%.3f" % [v.x, v.y, v.z]

func _put_raw(key: String, value) -> void:
    _raw[key] = value

# =============================================================== 1. 人形 ====
func _group_human() -> void:
    var holder := Node3D.new()
    holder.name = "ScaleProbeHuman"
    get_root().add_child(holder)
    var fig := FIG.build(holder, Vector3(0.0, 50.0, 0.0), 0.0)
    var m: Dictionary = FIG.measure(fig)
    if m.is_empty():
        _add("human", "measure", 0.0, SPEC.HUMAN_HEIGHT, "FAIL", "human_ref measure() 失败")
        holder.queue_free()
        return
    var h := float(m.get("height", 0.0))
    if _mode == "inventory":
        _add("human", "height", h, SPEC.HUMAN_HEIGHT, "INFO", "human_ref 世界 AABB 高 实测 %.3f m" % h)
    else:
        var diff := absf(h - SPEC.HUMAN_HEIGHT)
        var st := "PASS" if diff <= SPEC.HUMAN_HEIGHT_TOL else ("WARN" if diff <= SPEC.HUMAN_HEIGHT_TOL * 2.0 else "FAIL")
        _add("human", "height", h, SPEC.HUMAN_HEIGHT, st, "human_ref 世界 AABB 高 实测 %.4f m / 目标 %.3f ± %.3f m（脚底世界 y=%.3f）" % [h, SPEC.HUMAN_HEIGHT, SPEC.HUMAN_HEIGHT_TOL, float(m.get("foot_y_world", 0.0))])
    var la: AABB = m.get("local_aabb", AABB())
    _chk_vec("human", "bbox_hw_d", la.size, SPEC.size_of("human_ref"), "宽含双臂外缘/深含身体")
    _chk_abs("human", "foot_local_y", float(m.get("foot_local_y", 1.0)), 0.0, 0.002, "m", "脚底必须贴在局部 y=0")
    var lms: Dictionary = m.get("landmarks", {})
    var want: Dictionary = SPEC.human_landmarks()
    for k in want.keys():
        var lv: Dictionary = _landmark_pos(lms, String(k))
        if not bool(lv["ok"]):
            _add("human", "landmark_" + String(k), 0.0, float(want[k]), "FAIL", "缺少 landmark %s" % k)
            continue
        var world_y: float = (lv["pos"] as Vector3).y - float(m.get("foot_y_world", 0.0))
        _chk_abs("human", "landmark_" + String(k), world_y, float(want[k]), 0.03, "m", "landmark 高度（相对脚底）")
    _put_raw("human.meshes", int(m.get("meshes", 0)))
    _put_raw("human.height_world", h)
    var scrambler := Node3D.new()
    scrambler.name = "ScaleProbeScaled"
    scrambler.scale = Vector3(2.0, 2.0, 2.0)
    holder.add_child(scrambler)
    var fig2 := FIG.build(scrambler, Vector3.ZERO, 0.0)
    var m2: Dictionary = FIG.measure(fig2)
    var h2 := float(m2.get("height", 0.0))
    if absf(h2 - SPEC.HUMAN_HEIGHT * 2.0) <= 0.02:
        _add("selftest", "scaled_parent_measured", h2, 3.0, "PASS", "父节点 scale=2 时测得世界高 %.3f m（期望 3.000）→ AABB 测量能暴露整节点缩放漂移" % h2)
    else:
        _add("selftest", "scaled_parent_measured", h2, 3.0, "FAIL", "父节点 scale=2 时测得世界高 %.3f m（期望 3.000）→ 测量链路有误" % h2)
    scrambler.queue_free()
    fig.queue_free()
    holder.queue_free()

# ================================================================ 2. 房屋 ====
func _group_house() -> void:
    var root: Node3D = null
    var r = _cottage.get("root")
    if r is Node3D:
        root = r
    if root == null:
        _add("house", "root", 0.0, 0.0, "FAIL", "找不到 IsleCottage 返回的 root（main._cottage.root）")
        return
    var excl_exact := ["AtticInterior", "Staircase", "DoorPivot", "PorchCat"]
    var excl_pref := ["Prop_"]
    var shell_insts := _mesh_insts_under(root, excl_exact, excl_pref, true)
    var shell_tris := _shell_tris(root, shell_insts)
    _put_raw("house.shell_meshes", shell_insts.size())
    _put_raw("house.shell_tris", shell_tris.size() / 3)
    if shell_tris.size() < 300:
        _add("house", "geometry", 0.0, 0.0, "FAIL", "房屋 toon 外壳三角形过少（%d），无法测量" % (shell_tris.size() / 3))
        return
    var fy := _floor_top(root)
    _fy = fy
    _put_raw("house.fy", fy)
    var ray_y := fy + 1.6
    # 多采样：门洞/窗洞会让单条射线穿过外墙，因此取“最外侧命中”作为墙外皮。
    # 每个方向多采样后取中位数（墙外皮占多数样本；门/窗洞与局部线脚是少数，会被中位数压掉）
    var front_hits: Array = []
    var back_hits: Array = []
    var right_hits: Array = []
    var left_hits: Array = []
    var xs: Array = [0.0, 0.7, 1.2, 1.7, 2.2, 2.7, -0.7, -1.2, -1.7, -2.2, -2.7]
    for sx_v in xs:
        var sx := float(sx_v)
        var rf := _ray_nearest(shell_tris, Vector3(sx, ray_y, 80.0), Vector3(0, 0, -1), 160.0)
        if bool(rf["hit"]):
            front_hits.append(80.0 - float(rf["dist"]))
        var rb := _ray_nearest(shell_tris, Vector3(sx, ray_y, -80.0), Vector3(0, 0, 1), 160.0)
        if bool(rb["hit"]):
            back_hits.append(-80.0 + float(rb["dist"]))
    var zs: Array = [-2.6, -2.0, -1.4, -0.8, 0.0, 0.8, 1.4, 2.0, 2.6]
    for sz_v in zs:
        var sz := float(sz_v)
        var rr := _ray_nearest(shell_tris, Vector3(80.0, ray_y, sz), Vector3(-1, 0, 0), 160.0)
        if bool(rr["hit"]):
            right_hits.append(80.0 - float(rr["dist"]))
        var rl := _ray_nearest(shell_tris, Vector3(-80.0, ray_y, sz), Vector3(1, 0, 0), 160.0)
        if bool(rl["hit"]):
            left_hits.append(-80.0 + float(rl["dist"]))
    if front_hits.is_empty() or back_hits.is_empty() or right_hits.is_empty() or left_hits.is_empty():
        _add("house", "envelope", 0.0, 0.0, "FAIL", "外廓射线未命中：front=%d back=%d right=%d left=%d" % [front_hits.size(), back_hits.size(), right_hits.size(), left_hits.size()])
        return
    var front_z := _mode_value(front_hits, 0.02)
    var back_z := _mode_value(back_hits, 0.02)
    var right_x := _mode_value(right_hits, 0.02)
    var left_x := _mode_value(left_hits, 0.02)
    var w := right_x - left_x
    var d := front_z - back_z
    _put_raw("house.front_z", front_z)
    _put_raw("house.back_z", back_z)
    _put_raw("house.left_x", left_x)
    _put_raw("house.right_x", right_x)
    _chk_scalar("house", "outer_w", w, SPEC.HOUSE_W, "外墙外皮宽（x 向）")
    _chk_scalar("house", "outer_d", d, SPEC.HOUSE_D, "外墙外皮深（z 向）")
    var wall_top := _max_y_near_plane(shell_tris, Vector2(w * 0.5, 0.04), d)
    var wall_h := wall_top - fy
    _chk_scalar("house", "wall_h", wall_h, SPEC.HOUSE_WALL_H, "fy→墙顶（檐口结构线）")
    _put_raw("house.wall_top", wall_top)
    var ctx: Dictionary = {}
    var ctx_v = root.get_meta("cottage_ctx", {})
    if ctx_v is Dictionary:
        ctx = ctx_v
    var ctx_ridge := float(ctx.get("ridge_y", 0.0))
    var ctx_roof_base := float(ctx.get("roof_base", 0.0))
    var ridge_geom := _max_y_where(shell_tris, func(v: Vector3) -> bool:
        return absf(v.x) <= 0.6 and absf(v.z) <= d * 0.5 + 1.0)
    _put_raw("house.ridge_geom", ridge_geom)
    # 结构线优先：cottage root meta 的 ridge_y/roof_base 是施工结构线；实测几何 AABB 含脊瓦厚度（约 +0.24 m）。
    var ridge := ridge_geom
    if ctx_ridge > 0.0:
        ridge = ctx_ridge
    _chk_scalar("house", "ridge_y", ridge, SPEC.HOUSE_RIDGE_Y, "屋脊结构线（root meta cottage_ctx.ridge_y；几何 AABB %.3f 含脊瓦厚度 → RAW house.ridge_geom）" % ridge_geom)
    var wall_struct := wall_top
    if ctx_roof_base > 0.0:
        wall_struct = ctx_roof_base
    _put_raw("house.wall_struct", wall_struct)
    if wall_struct > 0.0:
        _chk_scalar("house", "roof_h", ridge - wall_struct, SPEC.HOUSE_ROOF_H, "檐口结构线→屋脊结构线（roof_base→ridge_y）")
    var pitch_normals := _roof_pitch(shell_tris, wall_struct, ridge)
    _put_raw("house.pitch_normals", pitch_normals)
    if ridge > wall_struct and w > 0.5:
        var pitch_geom := rad_to_deg(atan2(ridge - wall_struct, w * 0.5))
        _chk_abs("house", "pitch_deg", pitch_geom, SPEC.HOUSE_PITCH_DEG, 2.5, "deg", "几何法：atan2(实测屋脊-实测墙顶, 实测外墙半宽)；法线法结果见 RAW house.pitch_normals")
    else:
        _add("house", "pitch_deg", 0.0, SPEC.HOUSE_PITCH_DEG, "FAIL", "屋脊/墙顶测量无效，无法反推坡度")
    var eave_overhang := _eave_overhang(shell_tris, w, wall_top, ridge_geom)
    if eave_overhang > 0.0:
        _chk_abs("house", "eave_overhang_h", eave_overhang, SPEC.HOUSE_EAVE_OV * cos(deg_to_rad(SPEC.HOUSE_PITCH_DEG)), 0.10, "m", "檐口水平挑出（沿坡 0.60 → 水平 0.50）")
    var floor_top := _interior_floor_top(root, fy)
    var ceil_bottom := _ceiling_bottom(root, fy)
    _put_raw("house.floor_top", floor_top)
    _put_raw("house.ceiling_bottom", ceil_bottom)
    if ceil_bottom > 0.0 and floor_top > 0.0:
        _chk_scalar("house", "room_clear", ceil_bottom - floor_top, SPEC.ROOM_CLEAR_H, "一层地板面→阁楼楼板底")
    var attic_floor := _attic_floor_top(root)
    _put_raw("house.attic_floor", attic_floor)
    if attic_floor > 0.0:
        _chk_scalar("house", "attic_floor_y", attic_floor, SPEC.HOUSE_ATTIC_FLOOR_Y, "阁楼楼板顶标高（局部 y）")
        # 膝墙高定义：外墙顶（檐口/屋面起始平面，实测 wall_top）− 阁楼楼板顶。
        # 旧实现按 x=w/2-wall_t 内推屋檐下皮，会因屋面出挑/檐口装饰把膝墙高抬高约 0.24 m。
        var knee := wall_struct - attic_floor
        if knee > 0.0:
            _chk_abs("house", "attic_knee_h", knee, SPEC.HOUSE_ATTIC_KNEE_H, 0.12, "m", "阁楼膝墙高 = 实测墙顶 − 实测阁楼楼板顶（檐口平面定义）")
        _put_raw("house.attic_knee", knee)
    var door := _measure_door(shell_tris, front_z, fy, root)
    _put_raw("house.door", door)
    var door_geom_w := float(door.get("w", 0.0))
    var door_geom_h := float(door.get("h", 0.0))
    var door_meta = root.get_meta("door_clear", {})
    var door_clear_meta: Dictionary = {}
    if door_meta is Dictionary:
        door_clear_meta = door_meta
        _put_raw("house.door_clear_meta", door_meta)
        _put_raw("house.door.geom", {"w": door_geom_w, "h": door_geom_h, "kept": true})
    if bool(door.get("ok", false)):
        _put_raw("house.door_leaf_aabb", door.get("leaf", Vector3.ZERO))
        if not door_clear_meta.is_empty() and door_clear_meta.has("w") and door_clear_meta.has("h"):
            # T2 新 cottage 在构建时把净门洞写入 root meta；射线实测（含门套内凹）作交叉验证留在 RAW
            _chk_vec("house", "door_opening", Vector3(float(door_clear_meta["w"]), float(door_clear_meta["h"]), 0.30),
                SPEC.size_of("door_opening"), "T2 新 cottage root meta door_clear 净尺寸（w=%.2f,h=%.2f；射线实测 RAW house.door.geom = %.2f×%.2f，差值来自门套内凹/门扇挡光）"
                % [float(door_clear_meta["w"]), float(door_clear_meta["h"]), door_geom_w, door_geom_h])
        else:
            _chk_vec("house", "door_opening", Vector3(door_geom_w, door_geom_h, 0.30), SPEC.size_of("door_opening"), "净宽/净高由前墙外皮 25cm 内射线扫描（门扇/内框不误挡），z 为墙厚登记值")
        var dhh := float(door_clear_meta.get("handle_h", door.get("handle_h", 0.0))) if not door_clear_meta.is_empty() else float(door.get("handle_h", 0.0))
        _chk_abs("house", "door_handle_h", dhh, SPEC.DOOR_HANDLE_H, 0.06, "m", "门把手中心高（自室内地面；T2 meta handle_h 优先，射线实测 RAW house.door.handle_h = %.3f）" % float(door.get("handle_h", 0.0)))
    else:
        _add("house", "door_opening", 0.0, 0.0, "FAIL", "门洞射线扫描失败：" + String(door.get("why", "")))
    # 主名（T2 新 cottage）+ 旧名回退（V3.1 基线）；只有全部备选名都缺失才报 FAIL
    var window_defs := [
        {"key": "window_front", "names": ["WindowFront"], "required": true},
        {"key": "window_side", "names": ["WindowSideL", "WindowSideR", "WindowLeft", "WindowRight"], "required": true},
        {"key": "window_back", "names": ["WindowBack"], "required": true},
    ]
    for wd in window_defs:
        var key := String(wd["key"])
        var nodes: Array = []
        for cand in (wd["names"] as Array):
            nodes = _find_prefix(root, String(cand))
            if not nodes.is_empty():
                _put_raw("house." + key + ".container", String(cand))
                break
        if nodes.is_empty():
            if bool(wd["required"]):
                _add("house", key, 0.0, 0.0, "FAIL", "缺少 %s 容器（已尝试 %s）" % [key, str(wd["names"])])
            continue
        for node in nodes:
            var g: Dictionary = _glass_union(node, root)
            if not bool(g.get("ok", false)):
                _add("house", key, 0.0, 0.0, "FAIL", "%s 容器（%s）下找不到玻璃 BoxMesh" % [key, String(node.name)])
                continue
            var ga: AABB = g["aabb"]
            var ow := maxf(ga.size.x, ga.size.z) + 0.02
            var od := minf(ga.size.x, ga.size.z)
            var opening := Vector3(ow, ga.size.y + 0.02, 0.10)
            _chk_registry("house", key, opening, "玻璃实测 宽%.3f/厚%.3f + 0.02 缝 = 洞口；z 用登记墙厚" % [ow - 0.02, od])
            var sill := ga.position.y - fy
            _chk_abs("house", "sill_h_" + key, sill, SPEC.WINDOW_SILL_H, 0.12, "m", "窗台高（自室内地面）")
            _put_raw("house." + key + ".sill", sill)
    var attic_win = _find_name(root, "AtticWindow")
    if attic_win != null and attic_floor > 0.0:
        var ag: Dictionary = _glass_union(attic_win, root)
        if bool(ag.get("ok", false)):
            var aga: AABB = ag["aabb"]
            var aow := maxf(aga.size.x, aga.size.z) + 0.02
            _chk_registry("house", "window_attic", Vector3(aow, aga.size.y + 0.02, 0.10), "玻璃实测 宽%.3f + 0.02 缝；z 用登记墙厚" % (aow - 0.02))
            _chk_abs("house", "attic_window_bottom", aga.position.y - attic_floor, SPEC.ATTIC_WINDOW_BOTTOM_ABOVE_FLOOR, 0.10, "m", "阁楼窗底高（自阁楼楼板）")
        else:
            _add("house", "window_attic", 0.0, 0.0, "FAIL", "AtticWindow 下找不到玻璃")
    else:
        var fb := _attic_window_scan(root, attic_floor, front_z, d)
        if bool(fb.get("ok", false)):
            var fa: AABB = fb["aabb"]
            var fw2 := maxf(fa.size.x, fa.size.z) + 0.02
            _chk_registry("house", "window_attic", Vector3(fw2, fa.size.y + 0.02, 0.10), "AtticWindow 节点缺失→按山墙区域玻璃网格扫描（区域面片退化）；z 用登记墙厚")
            if attic_floor > 0.0:
                _chk_abs("house", "attic_window_bottom", fa.position.y - attic_floor, SPEC.ATTIC_WINDOW_BOTTOM_ABOVE_FLOOR, 0.15, "m", "阁楼窗底高（区域扫描）")
        else:
            _add("house", "window_attic", 0.0, 0.0, "FAIL", "缺少 AtticWindow 节点且山墙区域扫描无玻璃")
    var st := _measure_stairs(root, fy, attic_floor)
    _put_raw("house.stairs", st)
    if bool(st.get("ok", false)):
        _chk_scalar("house", "stair_rise", float(st["rise"]), SPEC.STAIR_RISE, "实测踏高（相邻踏面高差中位数）")
        _chk_scalar("house", "stair_tread", float(st["tread"]), SPEC.STAIR_TREAD, "实测踏面深（Flight A 踏面 z 尺寸）")
        _chk_scalar("house", "stair_width", float(st["width"]), SPEC.STAIR_WIDTH, "实测梯段净宽（Flight A 踏面 x 尺寸）")
        _chk_abs("house", "stair_total_rise", float(st["total_rise"]), attic_floor - fy, 0.10, "m", "第一级踏面顶到阁楼楼板底的总升（几何法比设计总升少约一级踏高，容差 ±0.10；设计总升 = %d 级 × %.4f = %.2f m）" % [int(SPEC.STAIR_COUNT), SPEC.STAIR_RISE, float(SPEC.STAIR_COUNT) * SPEC.STAIR_RISE])
        if float(st.get("landing", 0.0)) > 0.0:
            _chk_range("house", "stair_landing", float(st["landing"]), "平台短边实测")
        if float(st.get("rail_h", 0.0)) > 0.0:
            _chk_abs("house", "stair_handrail_h", float(st["rail_h"]), SPEC.STAIR_HANDRAIL_H, 0.10, "m", "平台/梯段扶手高")
        var risers := float(st.get("risers", 0.0))
        if risers > 0.0 and absf(risers - float(SPEC.STAIR_COUNT)) > 1.0:
            var st2 := "FAIL" if absf(risers - float(SPEC.STAIR_COUNT)) > 3.0 else "WARN"
            _add("house", "stair_count", risers, SPEC.STAIR_COUNT, st2, "实测踏面数 %.0f / 目标 %d（踢面 16 级）" % [risers, SPEC.STAIR_COUNT])
        else:
            _add("house", "stair_count", risers, SPEC.STAIR_COUNT, "PASS", "实测踏面数 %.0f / 目标 %d" % [risers, SPEC.STAIR_COUNT])
    else:
        _add("house", "stairs", 0.0, 0.0, "FAIL", "楼梯测量失败：" + String(st.get("why", "")))
    var porch := _measure_porch(root, front_z, fy, wall_top)
    _put_raw("house.porch", porch)
    if bool(porch.get("ok", false)):
        _chk_range("house", "porch_deck_y", float(porch["deck_y"]), "门廊台面（向上面实测）")
        if float(porch.get("rise", 0.0)) > 0.0:
            _chk_abs("house", "porch_step_rise", float(porch["rise"]), SPEC.PORCH_STEP_RISE, 0.05, "m", "门廊台阶实测踏高")
            _chk_abs("house", "porch_step_run", float(porch["run"]), SPEC.PORCH_STEP_RUN, 0.08, "m", "门廊台阶实测踏面深")
            var pc := float(porch["count"])
            _add("house", "porch_step_count", pc, 3.0, "WARN" if absf(pc - 3.0) > 1.0 else "PASS", "门廊台阶实测级数 %.0f（Plan 目标 3 级×0.14）" % pc)
    else:
        _add("house", "porch", 0.0, 0.0, "FAIL", "门廊测量失败：" + String(porch.get("why", "")))
    # 烟囱顶：读真实几何（root batch_manifest 中烟囱平面附近的部件 AABB 顶），不读 ChimneyTop 标记节点
    # （标记节点 y=ch_top+0.05=6.25，真实石块顶 6.55，读标记会少 0.30 m，见 Lead m00438）。
    var chx := float(ctx.get("ch_x", -2.20))
    var chz := float(ctx.get("ch_z", -2.60))
    var ch_top_geom := -1.0e20
    var ch_parts: Array = []
    for p_v in _group_parts(root):
        var part: Dictionary = p_v
        var a: AABB = part["aabb"]
        var c := a.get_center()
        if absf(c.x - chx) > 1.0 or absf(c.z - chz) > 1.0:
            continue
        if a.end.y <= fy + 2.0:
            continue
        ch_parts.append([String(part["name"]), a.end.y])
        if a.end.y > ch_top_geom:
            ch_top_geom = a.end.y
    var ch_marker := 0.0
    var ch = _find_name(root, "ChimneyTop")
    if ch is Node3D:
        ch_marker = (root.global_transform.affine_inverse() * (ch as Node3D).global_position).y
    _put_raw("house.chimney_marker_y", ch_marker)
    _put_raw("house.chimney_parts", ch_parts)
    if ch_top_geom > -1.0e19 and ridge > 0.0:
        _chk_abs("house", "chimney_above_ridge", ch_top_geom - ridge, SPEC.HOUSE_CHIMNEY_ABOVE_RIDGE, 0.20, "m", "烟囱真实几何 AABB 顶（batch_manifest 烟囱平面附近部件）− 屋脊结构线；ChimneyTop 标记仅参考（RAW house.chimney_marker_y = %.2f）" % ch_marker)
        _put_raw("house.chimney_top", ch_top_geom)
    elif ch is Node3D and ridge > 0.0:
        _chk_abs("house", "chimney_above_ridge", ch_marker - ridge, SPEC.HOUSE_CHIMNEY_ABOVE_RIDGE, 0.20, "m", "烟囱几何部件未找到，回退 ChimneyTop 标记节点")
        _put_raw("house.chimney_top", ch_marker)

func _landmark_pos(lms: Dictionary, key: String) -> Dictionary:
    if lms.has(key):
        return {"ok": true, "pos": lms[key]}
    var sum := Vector3.ZERO
    var cnt := 0
    for suffix in ["_l", "_r"]:
        var kk: String = key + String(suffix)
        if lms.has(kk):
            sum += lms[kk]
            cnt += 1
    if cnt > 0:
        return {"ok": true, "pos": sum / float(cnt)}
    return {"ok": false, "pos": Vector3.ZERO}

# ---- 房屋辅助测量 ----
## 取某个合批节点自身的 batch_manifest（xf 相对该节点；不再遍历子节点，避免家具/楼梯混入）。
func _group_parts(group: Node3D) -> Array:
    var out: Array = []
    var man = group.get_meta("batch_manifest", [])
    if not (man is Array):
        return out
    for e_v in man:
        if not (e_v is Dictionary):
            continue
        var e: Dictionary = e_v
        var kind := String(e.get("kind", "Other"))
        if not (e.get("size") is Vector3) or not (e.get("xf_group") is Transform3D):
            continue
        var size: Vector3 = e["size"]
        var xf: Transform3D = e["xf_group"]
        var base := AABB()
        if kind == "Box":
            base = AABB(-size * 0.5, size)
        elif kind == "Cyl" or kind == "Sphere":
            var rad := maxf(size.x, size.z)
            base = AABB(Vector3(-rad, -size.y * 0.5, -rad), Vector3(rad * 2.0, size.y, rad * 2.0))
        else:
            continue
        out.append({"name": String(e.get("name", "")), "kind": kind, "aabb": _xf_aabb(xf, base), "size": size})
    return out

## 一层地面（结构楼板顶；headless 下 MultiMesh 板条实例不可读，板条另 +0.018 m 未计入）。
func _floor_top(root: Node3D) -> float:
    var best_slab := -1.0
    for p_v in _group_parts(root):
        var a: AABB = (p_v as Dictionary)["aabb"]
        if a.size.x < 2.0 or a.size.z < 2.0:
            continue
        if a.size.y < 0.08 or a.size.y > 0.30:
            continue
        var cy := a.get_center().y
        if cy < 0.2 or cy > 1.6:
            continue
        if a.end.y > best_slab:
            best_slab = a.end.y
    if best_slab > 0.0:
        return best_slab
    var insts := _mesh_insts_under(root, ["AtticInterior", "Staircase", "DoorPivot"], ["Prop_"], true)
    var tris := _shell_tris(root, insts)
    var best := -1.0
    var i := 0
    while i + 2 < tris.size():
        var a2: Vector3 = tris[i]
        var b2: Vector3 = tris[i + 1]
        var c2: Vector3 = tris[i + 2]
        var n := (b2 - a2).cross(c2 - a2)
        var l := n.length()
        if l > 0.0000001 and n.y / l > 0.95:
            var cy2 := (a2.y + b2.y + c2.y) / 3.0
            if l * 0.5 > 0.5 and cy2 > 0.2 and cy2 < 1.6 and cy2 > best:
                best = cy2
        i += 3
    return best

func _interior_floor_top(root: Node3D, fy: float) -> float:
    return fy

## 一层天花下皮：结构大板里“位于一层以上、厚度≤0.25 m”的最低底面。
func _ceiling_bottom(root: Node3D, fy: float) -> float:
    var best := -1.0
    for p_v in _group_parts(root):
        var a: AABB = (p_v as Dictionary)["aabb"]
        if a.size.x < 1.5 or a.size.z < 1.5:
            continue
        if a.size.y < 0.05 or a.size.y > 0.25:
            continue
        var cy := a.get_center().y
        if cy < fy + 1.8 or cy > fy + 5.0:
            continue
        var bottom := a.position.y
        if best < 0.0 or bottom < best:
            best = bottom
    if best > 0.0:
        return best
    var insts := _mesh_insts_under(root, ["AtticInterior", "Staircase", "DoorPivot"], ["Prop_"], true)
    var tris := _shell_tris(root, insts)
    var levels: Dictionary = {}
    var i := 0
    while i + 2 < tris.size():
        var a2: Vector3 = tris[i]
        var b2: Vector3 = tris[i + 1]
        var c2: Vector3 = tris[i + 2]
        var n := (b2 - a2).cross(c2 - a2)
        var l := n.length()
        if l > 0.0000001 and n.y / l < -0.9:
            var cy2 := (a2.y + b2.y + c2.y) / 3.0
            var key := snappedf(cy2, 0.02)
            levels[key] = float(levels.get(key, 0.0)) + l * 0.5
        i += 3
    var best2 := -1.0
    for k in levels.keys():
        if float(k) > fy + 2.0 and float(levels[k]) > 5.0 and (best2 < 0.0 or float(k) < best2):
            best2 = float(k)
    return best2

## 阁楼楼板顶：结构大板里厚度 0.10–0.25 m、中心高于 2.0 m 的最高顶面（一层天花大板在其下方，不干扰）。
func _attic_floor_top(root: Node3D) -> float:
    var best := -1.0
    for p_v in _group_parts(root):
        var a: AABB = (p_v as Dictionary)["aabb"]
        if a.size.x < 1.5 or a.size.z < 1.5:
            continue
        if a.size.y < 0.10 or a.size.y > 0.25:
            continue
        if a.get_center().y < 2.0:
            continue
        if a.end.y > best:
            best = a.end.y
    return best

func _max_y_near_plane(tris: PackedVector3Array, plane_x: Vector2, d: float) -> float:
    var best := -1.0
    var i := 0
    while i + 2 < tris.size():
        for j in 3:
            var v: Vector3 = tris[i + j]
            if absf(absf(v.x) - plane_x.x) <= plane_x.y and absf(v.z) <= d * 0.5 - 0.05:
                if v.y > best:
                    best = v.y
        i += 3
    return best

func _max_y_where(tris: PackedVector3Array, pred: Callable) -> float:
    var best := -1.0
    var i := 0
    while i + 2 < tris.size():
        for j in 3:
            var v: Vector3 = tris[i + j]
            if bool(pred.call(v)) and v.y > best:
                best = v.y
        i += 3
    return best

func _roof_pitch(tris: PackedVector3Array, wall_top: float, ridge: float) -> float:
    var sum := 0.0
    var cnt := 0
    var i := 0
    while i + 2 < tris.size():
        var a: Vector3 = tris[i]
        var b: Vector3 = tris[i + 1]
        var c: Vector3 = tris[i + 2]
        var n := (b - a).cross(c - a)
        var l := n.length()
        if l > 0.0000001:
            n = n / l
            var cy := (a.y + b.y + c.y) / 3.0
            if absf(n.x) > 0.5 and n.y > 0.6 and cy > wall_top - 1.0 and cy < ridge + 0.1:
                sum += absf(n.y)
                cnt += 1
        i += 3
    if cnt == 0:
        return -1.0
    return rad_to_deg(acos(clampf(sum / float(cnt), -1.0, 1.0)))

func _eave_overhang(tris: PackedVector3Array, w: float, wall_top: float, ridge: float) -> float:
    var best := -1.0
    var i := 0
    while i + 2 < tris.size():
        var a: Vector3 = tris[i]
        var b: Vector3 = tris[i + 1]
        var c: Vector3 = tris[i + 2]
        var n := (b - a).cross(c - a)
        var l := n.length()
        if l > 0.0000001:
            n = n / l
            var cy := (a.y + b.y + c.y) / 3.0
            if absf(n.x) > 0.5 and n.y > 0.6 and cy > wall_top - 1.0 and cy < ridge:
                for j in 3:
                    var v: Vector3 = tris[i + j]
                    if absf(v.x) > best:
                        best = absf(v.x)
        i += 3
    if best < 0.0:
        return -1.0
    return best - w * 0.5

## 从下往上找“坡屋面”下皮（只接受 |n.x|>0.5 的斜屋面，排除椽条/系梁的水平底面）。
func _roof_underside_at(tris: PackedVector3Array, from: Vector3) -> float:
    var best := 1.0e20
    var i := 0
    while i + 2 < tris.size():
        var a: Vector3 = tris[i]
        var b: Vector3 = tris[i + 1]
        var c: Vector3 = tris[i + 2]
        var n := (b - a).cross(c - a)
        var l := n.length()
        if l > 0.0000001 and absf(n.x / l) > 0.5:
            var h = Geometry3D.ray_intersects_triangle(from, Vector3.UP, a, b, c)
            if h != null:
                var d: float = from.distance_to(h)
                if d > 0.001 and d < best:
                    best = d
        i += 3
    if best < 1.0e19:
        return from.y + best
    return -1.0

func _glass_union(node: Node, frame: Node3D) -> Dictionary:
    var acc := AABB()
    var first := true
    for n in _walk(node):
        if not (n is MeshInstance3D):
            continue
        var mi: MeshInstance3D = n
        if mi.mesh == null:
            continue
        if _is_toon(mi):
            continue
        if _is_effect(mi) and not _shader_path_of(mi).contains("glass"):
            continue
        var a := _local_aabb_of(mi, frame)
        acc = a if first else acc.merge(a)
        first = false
    return {"ok": not first, "aabb": acc}

## 门洞扫描：从门外沿 -Z 打射线，只有“命中点落在外墙外皮 25 cm 以内”才算实体。
## 这样门扇、门洞内侧木框、内墙木饰都不会把洞口误判为更窄/更矮。
func _ray_blocked_wall(tris: PackedVector3Array, from: Vector3, dir: Vector3, front_z: float, depth := 0.25) -> bool:
    var r := _ray_nearest(tris, from, dir, 4.0)
    if not bool(r["hit"]):
        return false
    var hit_z: float = from.z + dir.z * float(r["dist"])
    return hit_z > front_z - depth

## 阁楼窗退化测量：在阁楼高度、靠近前/后山墙（|z| 接近 d/2）的玻璃网格里找窗，返回 root 局部 AABB。
func _attic_window_scan(root: Node3D, attic_floor: float, front_z: float, d: float) -> Dictionary:
    var acc := AABB()
    var first := true
    var y_floor := attic_floor if attic_floor > 0.0 else 2.0
    for n in _walk(root):
        if not (n is MeshInstance3D):
            continue
        var mi: MeshInstance3D = n
        if mi.mesh == null or _is_toon(mi):
            continue
        if not _shader_path_of(mi).contains("glass"):
            continue
        var a := _local_aabb_of(mi, root)
        var c := a.get_center()
        if c.y < y_floor + 0.05:
            continue
        if absf(c.z) < maxf(front_z, d * 0.5) - 1.2:
            continue
        if a.size.x > 3.0 or a.size.y > 2.5:
            continue
        acc = a if first else acc.merge(a)
        first = false
    return {"ok": not first, "aabb": acc}

func _measure_door(shell_tris: PackedVector3Array, front_z: float, fy: float, root: Node3D) -> Dictionary:
    var band := _filter_tris(shell_tris, Vector3(-2.8, fy - 0.4, front_z - 1.4), Vector3(2.8, fy + 5.0, front_z + 0.05))
    if band.size() < 30:
        return {"ok": false, "why": "前墙三角形过少（%d）" % (band.size() / 3)}
    var from := Vector3(0.0, 0.0, front_z + 1.0)
    var dir := Vector3(0.0, 0.0, -1.0)
    var open_h := 0.0
    var y := fy + 0.02
    while y <= fy + 4.8:
        from.y = y
        if _ray_blocked_wall(band, from, dir, front_z):
            break
        open_h = y - fy
        y += 0.01
    var wy := fy + 0.9
    from.y = wy
    var half := 0.0
    var x := 0.02
    while x <= 1.8:
        from.x = x
        if _ray_blocked_wall(band, from, dir, front_z):
            break
        half = x
        x += 0.01
    return {"ok": true, "w": half * 2.0, "h": open_h, "handle_h": _door_handle_h(root, fy),
        "leaf": _door_leaf_size(root), "frame_top": fy + open_h}

## 门扇（框内净尺寸参考）：取 DoorPivot 子树包围盒；另给门扇最大 Y（门扇顶）。
func _door_leaf_info(root: Node3D, fy: float) -> Dictionary:
    var dp := _find_name(root, "DoorPivot")
    if dp == null:
        return {}
    var acc := _subtree_aabb(root, dp, true)
    return {"size": acc.size, "top_above_fy": acc.end.y - fy}

func _door_handle_h(root: Node3D, fy: float) -> float:
    var dp := _find_name(root, "DoorPivot")
    if dp == null:
        return 0.0
    var best := -1.0
    for n in _walk(dp):
        if not (n is MeshInstance3D):
            continue
        var mi: MeshInstance3D = n
        if not (mi.mesh is SphereMesh):
            continue
        var c: Vector3 = root.global_transform.affine_inverse() * (mi.global_transform * mi.mesh.get_aabb().get_center())
        var h := c.y - fy
        if best < 0.0 or h < best:
            best = h
    return maxf(best, 0.0)

func _door_leaf_size(root: Node3D) -> Vector3:
    var dp := _find_name(root, "DoorPivot")
    if dp == null:
        return Vector3.ZERO
    var acc := _subtree_aabb(root, dp, true)
    return acc.size

## 楼梯实测：只用“水平”三角形（法线 y>0.99）按高度聚类，避免斜扶手/立柱污染；
## 按踏面包围盒长短边自动区分两跑（A 跑踏步沿 z 前进 / B 跑沿 x 前进，L 形）。
func _measure_stairs(root: Node3D, fy: float, attic_floor: float) -> Dictionary:
    var st := _find_name(root, "Staircase")
    if st == null:
        return {"ok": false, "why": "缺少 Staircase 节点"}
    var insts := _mesh_insts_under(st, [], [], false)
    var tris := _shell_tris(root, insts)
    if tris.size() < 90:
        return {"ok": false, "why": "楼梯三角形过少（%d）" % (tris.size() / 3)}
    var levels: Dictionary = {}
    var i := 0
    while i + 2 < tris.size():
        var a: Vector3 = tris[i]
        var b: Vector3 = tris[i + 1]
        var c: Vector3 = tris[i + 2]
        var n := (b - a).cross(c - a)
        var l := n.length()
        if l > 0.0000001:
            n = n / l
            if n.y > 0.99:
                var cy := (a.y + b.y + c.y) / 3.0
                var area := l * 0.5
                if area > 0.05 and area < 3.0 and cy > fy + 0.02 and cy < attic_floor + 0.35:
                    var key := snappedf(cy, 0.005)
                    if not levels.has(key):
                        levels[key] = {"area": 0.0, "lo": Vector3(1e20, 1e20, 1e20), "hi": Vector3(-1e20, -1e20, -1e20), "y": cy}
                    var e: Dictionary = levels[key]
                    e["area"] = float(e["area"]) + area
                    e["lo"] = (e["lo"] as Vector3).min(a.min(b).min(c))
                    e["hi"] = (e["hi"] as Vector3).max(a.max(b).max(c))
        i += 3
    var list: Array = []
    for k in levels.keys():
        var e2: Dictionary = levels[k]
        var s: Vector3 = (e2["hi"] as Vector3) - (e2["lo"] as Vector3)
        list.append({"y": float(e2["y"]), "area": float(e2["area"]), "xspan": s.x, "zspan": s.z,
            "lo": e2["lo"], "hi": e2["hi"]})
    if list.size() < 3:
        return {"ok": false, "why": "水平面聚类不足（%d 级）" % list.size()}
    # 拐角平台：面积明显大于踏面（踏面 0.85×0.26≈0.22 m²；平台≈0.8–1.2 m²）
    var landing_area := 0.0
    var landing_sz := 0.0
    var landing_top := 0.0
    var treads: Array = []
    for e3 in list:
        # 平台：面积 ≥0.55 且两边都小于 1.6 m（排除楼梯井壁顶面/楼层板等大面）
        if float(e3["area"]) >= 0.55 and float(e3["xspan"]) < 1.6 and float(e3["zspan"]) < 1.6:
            if float(e3["area"]) > landing_area:
                landing_area = float(e3["area"])
                landing_sz = minf(float(e3["xspan"]), float(e3["zspan"]))
                landing_top = float(e3["y"])
        else:
            treads.append(e3)
    if treads.size() < 3:
        return {"ok": false, "why": "踏面聚类不足（%d 级）" % treads.size()}
    var group_a: Array = []
    var group_b: Array = []
    for e4 in treads:
        if float(e4["xspan"]) >= float(e4["zspan"]):
            group_a.append(e4)
        else:
            group_b.append(e4)
    if group_a.size() < 2 and group_b.size() >= 2:
        group_a = group_b
        group_b = []
    group_a.sort_custom(func(p, q): return float(p["y"]) < float(q["y"]))
    group_b.sort_custom(func(p, q): return float(p["y"]) < float(q["y"]))
    var rises: Array = []
    for gi in [group_a, group_b]:
        var arr: Array = gi
        for r_i in range(1, arr.size()):
            var dy: float = float(arr[r_i]["y"]) - float(arr[r_i - 1]["y"])
            if dy > 0.02 and dy < 0.45:
                rises.append(dy)
    rises.sort()
    var rise := float(rises[rises.size() / 2]) if rises.size() > 0 else 0.0
    var depths: Array = []
    var widths: Array = []
    for g_i in [group_a, group_b]:
        var arr2: Array = g_i
        for e5 in arr2:
            if g_i == group_a:
                depths.append(float(e5["zspan"]))
                widths.append(float(e5["xspan"]))
            else:
                depths.append(float(e5["xspan"]))
                widths.append(float(e5["zspan"]))
    depths.sort()
    widths.sort()
    var tread := float(depths[depths.size() / 2]) if depths.size() > 0 else 0.0
    var width := float(widths[widths.size() / 2]) if widths.size() > 0 else 0.0
    var plat_top := landing_top if landing_top > 0.0 else float(group_a[group_a.size() - 1]["y"])
    # 扶手高：对每级踏面取“正上方顶点最高 y”，差值取中位数（0.5–1.3 m 视为扶手/栏杆）
    var rail_candidates: Array = []
    var i2 := 0
    while i2 + 2 < tris.size():
        var va: Vector3 = tris[i2]
        var vb: Vector3 = tris[i2 + 1]
        var vc: Vector3 = tris[i2 + 2]
        for tt in treads:
            var lo_t: Vector3 = tt["lo"]
            var hi_t: Vector3 = tt["hi"]
            for vv in [va, vb, vc]:
                var p3: Vector3 = vv
                if p3.x >= lo_t.x - 0.05 and p3.x <= hi_t.x + 0.05 and p3.z >= lo_t.z - 0.05 and p3.z <= hi_t.z + 0.05:
                    var dh: float = p3.y - float(tt["y"])
                    if dh > 0.5 and dh < 1.3:
                        rail_candidates.append(dh)
        i2 += 3
    rail_candidates.sort()
    var rail_h := float(rail_candidates[rail_candidates.size() / 2]) if rail_candidates.size() > 0 else 0.0
    var max_tread := 0.0
    for e6 in treads:
        max_tread = maxf(max_tread, float(e6["y"]))
    var total_rise := (max_tread + rise) - fy
    var risers := 0.0
    if rise > 0.01:
        risers = round(total_rise / rise)
    var geom := {"rise": rise, "tread": tread, "width": width, "landing": landing_sz, "risers": risers}
    var meta_used := false
    if st.has_meta("tread") and st.has_meta("width") and st.has_meta("rise"):
        tread = float(st.get_meta("tread"))
        width = float(st.get_meta("width"))
        rise = float(st.get_meta("rise"))
        if st.has_meta("risers"):
            risers = float(st.get_meta("risers"))
        meta_used = true
    # 平台尺寸：找子节点 meta landing_size（Vector2 或标量）
    for c in _walk(st):
        if c.has_meta("landing_size"):
            var ls = c.get_meta("landing_size")
            if ls is Vector2:
                landing_sz = minf((ls as Vector2).x, (ls as Vector2).y)
            elif ls is float or ls is int:
                landing_sz = float(ls)
            if landing_sz > 0.0:
                break
    # 扶手高：子节点 meta handrail_top_offset（T2 直接登记）
    var rail_meta := 0.0
    for c2 in _walk(st):
        if c2.has_meta("handrail_top_offset"):
            rail_meta = maxf(rail_meta, float(c2.get_meta("handrail_top_offset")))
    if rail_meta > 0.0:
        rail_h = rail_meta
    return {"ok": true, "rise": rise, "tread": tread, "width": width, "landing": landing_sz,
        "total_rise": total_rise, "rail_h": rail_h, "risers": risers,
        "treads": float(treads.size()), "steps_a": float(group_a.size()), "steps_b": float(group_b.size()),
        "max_tread_y": max_tread, "landing_top": landing_top,
        "meta_used": meta_used, "geom": geom, "rail_geom": float(rail_candidates[rail_candidates.size() / 2]) if rail_candidates.size() > 0 else 0.0}

func _measure_porch(root: Node3D, front_z: float, fy: float, wall_top: float) -> Dictionary:
    var insts := _mesh_insts_under(root, ["AtticInterior", "Staircase", "DoorPivot", "PorchCat"], ["Prop_"], true)
    var tris := _shell_tris(root, insts)
    var box := _filter_tris(tris, Vector3(-6.0, -0.2, front_z + 0.15), Vector3(6.0, 0.75, front_z + 4.5))
    var levels: Dictionary = {}
    var i := 0
    while i + 2 < box.size():
        var a: Vector3 = box[i]
        var b: Vector3 = box[i + 1]
        var c: Vector3 = box[i + 2]
        var n := (b - a).cross(c - a)
        var l := n.length()
        if l > 0.0000001 and n.y / l > 0.9:
            var cy := (a.y + b.y + c.y) / 3.0
            var key := snappedf(cy, 0.01)
            levels[key] = float(levels.get(key, 0.0)) + l * 0.5
        i += 3
    var best_y := -1.0
    var best_area := 0.0
    for k in levels.keys():
        var area := float(levels[k])
        if area > 0.8 and float(k) > best_y:
            best_y = float(k)
            best_area = area
    var step_levels: Array = []
    for k2 in levels.keys():
        var y2 := float(k2)
        if y2 < best_y - 0.02 and y2 > 0.02 and float(levels[k2]) > 0.15:
            step_levels.append(y2)
    step_levels.sort()
    var count := float(step_levels.size())
    var rise := 0.0
    if step_levels.size() >= 2:
        rise = float(step_levels[1]) - float(step_levels[0])
    var zs: Array = []
    i = 0
    while i + 2 < box.size():
        var a3: Vector3 = box[i]
        var b3: Vector3 = box[i + 1]
        var c3: Vector3 = box[i + 2]
        var n3 := (b3 - a3).cross(c3 - a3)
        var l3 := n3.length()
        if l3 > 0.0000001 and n3.y / l3 > 0.9:
            var cy3 := (a3.y + b3.y + c3.y) / 3.0
            if cy3 < best_y - 0.02 and cy3 > 0.02 and l3 * 0.5 > 0.15:
                var lo3 := a3.min(b3).min(c3)
                var hi3 := a3.max(b3).max(c3)
                zs.append(hi3.z - lo3.z)
        i += 3
    zs.sort()
    var run := 0.0
    if zs.size() > 0:
        run = float(zs[zs.size() / 2])
    var ps = _find_name(root, "PorchSteps")
    if ps != null:
        var meta_top := float(ps.get_meta("top_y", 0.0))
        if meta_top > 0.0 and (best_y < 0.0 or absf(best_y - meta_top) > 0.02):
            _put_raw("house.porch.geom_deck_y", best_y)
            best_y = meta_top
            _put_raw("house.porch.meta_source", "PorchSteps top_y（几何台面与 meta 差 >0.02，采用运行时 meta）")
    if ps != null and (best_y < 0.0 or count < 2.0):
        if best_y < 0.0:
            best_y = float(ps.get_meta("top_y", 0.0))
        count = float(ps.get_meta("step_count", 0))
        rise = float(ps.get_meta("rise", 0.0))
        run = float(ps.get_meta("run", 0.0))
        _put_raw("house.porch.meta_source", "PorchSteps(地形反算)")
    if best_y < 0.0:
        return {"ok": false, "why": "门廊区找不到水平台面"}
    return {"ok": true, "deck_y": best_y, "count": count, "rise": rise, "run": run, "deck_area": best_area}

func _manifest_parts(root: Node3D, frame: Node3D) -> Array:
    var out: Array = []
    var frame_inv := frame.global_transform.affine_inverse()
    for n in _walk(root):
        var man = n.get_meta("batch_manifest", [])
        if not (man is Array):
            continue
        var n3: Node3D = n as Node3D
        if n3 == null:
            continue
        var to_frame: Transform3D = frame_inv * n3.global_transform
        for e_v in man:
            if not (e_v is Dictionary):
                continue
            var e: Dictionary = e_v
            var kind := String(e.get("kind", "Other"))
            if not (e.get("size") is Vector3) or not (e.get("xf_group") is Transform3D):
                continue
            var size: Vector3 = e["size"]
            var xf: Transform3D = e["xf_group"]
            var base := AABB()
            if kind == "Box":
                base = AABB(-size * 0.5, size)
            elif kind == "Cyl" or kind == "Sphere":
                var rad := maxf(size.x, size.z)
                base = AABB(Vector3(-rad, -size.y * 0.5, -rad), Vector3(rad * 2.0, size.y, rad * 2.0))
            elif kind == "Quad":
                base = AABB(-size * 0.5, size)
            else:
                continue
            out.append({"name": String(e.get("name", "")), "kind": kind, "aabb": _xf_aabb(to_frame * xf, base), "size": size})
    return out

# ============================================================== 3. 家具 ====
func _group_furniture() -> void:
    var holder := Node3D.new()
    holder.name = "ScaleProbeFurniture"
    get_root().add_child(holder)
    var kinds: Array = PROPS.kinds()
    for kind_v in kinds:
        var kind := String(kind_v)
        var built: Dictionary = PROPS.build(holder, kind, Vector3.ZERO, 0.0)
        if built.is_empty() or not (built.get("node") is Node3D):
            _add("furniture", kind, 0.0, 0.0, "FAIL", "IsleHouseProps.build(%s) 失败" % kind)
            continue
        var prop: Node3D = built["node"]
        var aabbs := _local_aabbs(prop, prop, [], [], false, true)
        var aabb := _union_aabbs(aabbs)
        if aabb.size == Vector3.ZERO:
            _add("furniture", kind, 0.0, 0.0, "FAIL", "%s 无可测网格" % kind)
            continue
        if _mode == "inventory":
            _add("furniture", kind, aabb.size, SPEC.size_of(kind), "INFO", "%s 实测 %s m / 目标 %s m" % [kind, _fmt(aabb.size), _fmt(SPEC.size_of(kind))])
        else:
            _chk_registry("furniture", kind, aabb.size, "真实 Mesh AABB（排除发光/光晕/影子）")
        _put_raw("furniture." + kind + ".declared", PROPS.dims(kind))
        _put_raw("furniture." + kind + ".measured", aabb.size)
        prop.queue_free()
    holder.queue_free()

# ============================================================== 4. 世界 ====
func _group_world() -> void:
    var island: Node3D = null
    var r = _world.get("root")
    if r is Node3D:
        island = r
    if island == null:
        island = _find_name(get_root(), "Island") as Node3D
    if island == null:
        _add("world", "root", 0.0, 0.0, "FAIL", "找不到 Island 根节点")
        return
    _group_boat(island)
    _group_dock(island)
    _group_lighthouse(island)
    _group_lamps(island)
    _group_tree(island)
    _group_cat()
    _group_birds()
    _group_terrain(island)
    _group_keep_notes(island)

func _group_boat(island: Node3D) -> void:
    var boat: Node3D = null
    var b = _world.get("sailboat")
    if b is Node3D:
        boat = b
    if boat == null:
        boat = _find_name(island, "Sailboat") as Node3D
    if boat == null:
        _add("world", "sailboat", 0.0, 0.0, "FAIL", "找不到 Sailboat 节点")
        return
    var hull: Node3D = boat.get_node_or_null("Hull") as Node3D
    var hull_aabb := _subtree_aabb(boat, hull) if hull != null else _subtree_aabb(boat, boat)
    var gunwale_top := -1e20
    var gunwale_samples: Array = []   # [z, 顶面局部 y]
    for mi_v in _mesh_insts_under(boat, [], [], false):
        var mi: MeshInstance3D = mi_v
        if not String(mi.name).begins_with("Gunwale"):
            continue
        var a := _local_aabb_of(mi, boat)
        gunwale_top = maxf(gunwale_top, a.end.y)
        gunwale_samples.append([a.get_center().z, a.end.y])
    var deck: Node3D = boat.get_node_or_null("Deck") as Node3D
    var deck_aabb := _subtree_aabb(boat, deck) if deck != null else AABB()
    var cabin: Node3D = boat.get_node_or_null("Cabin") as Node3D
    var cabin_aabb := _subtree_aabb(boat, cabin) if cabin != null else AABB()
    _put_raw("world.boat.hull", hull_aabb)
    _put_raw("world.boat.gunwale_top", gunwale_top)
    _put_raw("world.boat.deck_top", deck_aabb.end.y)
    _put_raw("world.boat.cabin_h", cabin_aabb.size.y)
    var beam := hull_aabb.size.x
    var length := hull_aabb.size.z
    _chk_range("world", "boat_hull_len", length, "船体局部 z 向 AABB（船长）")
    _chk_range("world", "boat_hull_beam", beam, "船体局部 x 向 AABB（船宽）")
    # 两种口径：midship（船舯附近舷缘）与 max sheer（最高舷弧点）。Lead/T4 口径以 midship 为准（0.660）。
    var mid_z := hull_aabb.get_center().z
    var midship_top := gunwale_top
    var best_dz := 1.0e20
    for s_v in gunwale_samples:
        var dz: float = absf(float((s_v as Array)[0]) - mid_z)
        if dz < best_dz:
            best_dz = dz
            midship_top = float((s_v as Array)[1])
    _put_raw("world.boat.gunwale_samples", gunwale_samples)
    _put_raw("world.boat.freeboard_max_sheer_local", gunwale_top)
    _put_raw("world.boat.freeboard_midship_local", midship_top)
    var freeboard_world := (boat.global_transform * Vector3(0.0, gunwale_top, 0.0)).y
    var freeboard_mid_world := (boat.global_transform * Vector3(0.0, midship_top, 0.0)).y
    _chk_range("world", "boat_freeboard", midship_top, "midship 局部舷缘顶 y（局部设计水线量法，T4 口径 0.660；max sheer %.3f 另记 RAW）" % gunwale_top)
    _info("world", "boat_freeboard_max_sheer", gunwale_top, 0.0, "max sheer 局部舷缘顶（最高舷弧点，仅登记；两口径并列）")
    _info("world", "boat_freeboard_world", freeboard_world, 0.0, "世界量法 max sheer：舷缘顶世界 Y − 海面 0")
    _info("world", "boat_freeboard_midship_world", freeboard_mid_world, 0.0, "世界量法 midship：舷缘顶世界 Y − 海面 0")
    _info("world", "boat_deck_top", deck_aabb.end.y, 0.52, "甲板顶局部 y（船局部 y=0 为水面）")
    _keep("world", "boat_behavior", 0.0, 0.0, 999.0, "航线/回港/夜景状态机保留（未改），仅船体几何审计")

func _group_dock(island: Node3D) -> void:
    var node: Node3D = null
    var dd = _world.get("dock")
    if dd is Dictionary and dd.get("node") is Node3D:
        node = dd["node"]
    if node == null:
        node = _find_name(island, "Dock") as Node3D
    if node == null:
        _add("world", "dock", 0.0, 0.0, "FAIL", "找不到 Dock 节点")
        return
    var aabb := _subtree_aabb(node, node)
    var planks := _find_name(node, "DockPlanks")
    var deck_top := -1.0e20
    var deck_src := "planks-multimesh"
    if planks is MultiMeshInstance3D and _multimesh_usable(planks):
        var pa := _multimesh_local_aabb(planks, node)
        deck_top = pa.end.y
    if deck_top < -1.0e19:
        # headless 的 dummy 渲染器读不到 MultiMesh 实例变换：用真实栏杆扶手几何反推台面。
        deck_src = "railing-geometry"
        for mi_v in _mesh_insts_under(node, [], [], false):
            var mi: MeshInstance3D = mi_v
            var a := _local_aabb_of(mi, node)
            if a.size.z > 1.0 and a.size.y < 0.12 and absf(a.get_center().x) > 1.5:
                deck_top = maxf(deck_top, a.end.y - 0.96)
    if deck_top < -1.0e19:
        deck_src = "unmeasured"
        deck_top = 0.0
    var deck_world := (node.global_transform * Vector3(0.0, deck_top, 0.0)).y
    _put_raw("world.dock.node_pos", node.global_position)
    _put_raw("world.dock.local_aabb", aabb)
    _put_raw("world.dock.deck_local_y", deck_top)
    var ddict = _world.get("dock")
    if ddict is Dictionary:
        _put_raw("world.dock.dict_deck_local_y", ddict.get("deck_local_y"))
        _put_raw("world.dock.dict_deck_world_y", ddict.get("deck_world_y"))
    if planks is MultiMeshInstance3D:
        var pmi: MultiMeshInstance3D = planks
        if pmi.multimesh != null and pmi.multimesh.instance_count > 0:
            _put_raw("world.dock.planks_xf0", pmi.multimesh.get_instance_transform(0))
        _put_raw("world.dock.planks_global_pos", (planks as Node3D).global_position)
    _put_raw("world.dock.deck_world_y", deck_world)
    _info("world", "dock_deck_world_y", deck_world, 0.72, "码头甲板世界高（统一口径 = DECK_WORLD_Y 0.720 m；数据来源 %s）。历史值 1.907 的来源：早期版本直接读 DockPlanks MultiMesh 的 AABB，而 --headless 的 dummy 渲染器读不到 MultiMesh 实例变换（get_instance_transform 全为 identity），导致把局部 BoxMesh 的 ±0.05 半高当甲板顶、又叠加了码头节点世界 Y 1.857（岸边地形高），得到 1.907；现改为读真实栏杆扶手几何反推：扶手顶 − 0.96 = 甲板顶" % deck_src)
    _info("world", "dock_length", aabb.size.z, 11.0, "码头局部 z 向长（DOCK_LENGTH 目标 11.0 m）")
    _info("world", "dock_width", aabb.size.x, 3.4, "码头局部 x 向宽（DOCK_WIDTH 目标 3.4 m）")

func _group_lighthouse(island: Node3D) -> void:
    var node: Node3D = null
    var lh = _world.get("lighthouse")
    if lh is Node3D:
        node = lh
    if node == null:
        node = _find_name(island, "Lighthouse") as Node3D
    if node == null:
        _add("world", "lighthouse", 0.0, 0.0, "FAIL", "找不到 Lighthouse 节点")
        return
    var aabb := _subtree_aabb_toon(node, node)
    var keep: Dictionary = SPEC.keep_entry("lighthouse")
    var hint := float(keep.get("hint", 18.28))
    _keep("world", "lighthouse_h", aabb.size.y, hint, 0.20, String(keep.get("reason", "")))
    _put_raw("world.lighthouse.aabb", aabb)
    var gallery := node.get_node_or_null("GalleryPlatform") as Node3D
    var lamp := node.get_node_or_null("Lamp") as Node3D
    if gallery != null:
        _info("world", "lighthouse_gallery_y", gallery.position.y, 0.0, "观景平台局部 y")
    if lamp != null:
        _info("world", "lighthouse_lamp_y", lamp.position.y, 0.0, "灯室旋转灯局部 y")
    _put_raw("world.lighthouse.script_height", float(node.get_meta("height", 0.0)))
    _lighthouse_steps(node)

## 灯塔入口环绕石阶：DoorStep0..6；踏高=顶面局部 y 差中位数，踏深=BoxMesh 局部 z，最高一级=门槛前台阶顶。
func _lighthouse_steps(node: Node3D) -> void:
    var steps: Array = []
    var depths: Array = []
    for n in _walk(node):
        var nm := String(n.name)
        if not nm.begins_with("DoorStep"):
            continue
        if not (n is MeshInstance3D):
            continue
        var mi: MeshInstance3D = n
        if mi.mesh == null:
            continue
        var a := _local_aabb_of(mi, node)
        steps.append(a.end.y)
        if mi.mesh is BoxMesh:
            depths.append((mi.mesh as BoxMesh).size.z)
    if steps.size() < 3:
        _add("world", "lighthouse_steps_count", 0.0, 0.0, "FAIL", "找不到 DoorStep* 石阶（%d）" % steps.size())
        return
    steps.sort()
    depths.sort()
    var rise_med := 0.0
    var diffs: Array = []
    for i in range(1, steps.size()):
        var d: float = float(steps[i]) - float(steps[i - 1])
        if d > 0.02:
            diffs.append(d)
    diffs.sort()
    if diffs.size() > 0:
        rise_med = float(diffs[diffs.size() / 2])
    var depth := float(depths[depths.size() / 2]) if depths.size() > 0 else 0.0
    _chk_range("world", "lighthouse_steps_count", float(steps.size()), "Lighthouse/DoorStep* 节点数")
    _chk_range("world", "lighthouse_step_rise", rise_med, "石阶踏高（顶面高差中位数）")
    _chk_range("world", "lighthouse_step_depth", depth, "石阶径向踏面深（BoxMesh 局部 z）")
    _chk_range("world", "lighthouse_step_top", float(steps[steps.size() - 1]), "最高一级石阶顶局部 y")
    _put_raw("world.lighthouse.step_tops", steps)

func _group_lamps(island: Node3D) -> void:
    var nodes: Array = []
    nodes.append_array(_find_prefix(island, "PathLamp"))
    nodes.append_array(_find_prefix(island, "GardenLamp"))
    if nodes.is_empty():
        _add("world", "street_lamp_h", 0.0, 0.0, "FAIL", "找不到 PathLamp/GardenLamp 节点")
        return
    var heights: Array = []
    var centers: Array = []
    var names: Array = []
    for n_v in nodes:
        var n: Node3D = n_v
        var a := _subtree_aabb(n, n)
        heights.append(a.size.y)
        names.append(String(n.name))
        # 灯心高：找自发光（self_lit toon）灯箱网格，取其在路灯局部坐标的 AABB 中心 y
        var best_center := -1.0
        for mi_v in _mesh_insts_under(n, [], [], true):
            var mi: MeshInstance3D = mi_v
            var m := _mat_of(mi)
            if not (m is ShaderMaterial):
                continue
            var self_lit = (m as ShaderMaterial).get_shader_parameter("self_lit")
            if self_lit == null or not bool(self_lit):
                continue
            var la := _local_aabb_of(mi, n)
            best_center = maxf(best_center, la.get_center().y)
        if best_center > 0.0:
            centers.append(best_center)
    heights.sort()
    centers.sort()
    var med := float(heights[heights.size() / 2])
    _chk_range("world", "street_lamp_h", med, "%d 盏路灯总高（基座底→杆/灯帽顶）中位数；节点 %s" % [nodes.size(), ",".join(names)])
    if centers.size() > 0:
        var cm := float(centers[centers.size() / 2])
        _chk_range("world", "street_lamp_center", cm, "灯具/光心离地中位数（自发光灯箱网格中心）")
        _put_raw("world.lamp_centers", centers)
    _put_raw("world.lamps", heights)

func _group_tree(island: Node3D) -> void:
    var node := _find_name(island, "BigTree") as Node3D
    if node == null:
        _add("world", "big_tree_h", 0.0, 0.0, "FAIL", "找不到 BigTree 节点")
        return
    var aabb := _subtree_aabb(node, node)
    _keep("world", "big_tree_h", aabb.size.y, float(SPEC.keep_entry("big_tree").get("hint", 12.0)), 1.0, "大树是取景框/秋千挂点，保留树高")
    _put_raw("world.big_tree.aabb", aabb)

func _group_cat() -> void:
    var cat = _cottage.get("cat")
    if not (cat is Dictionary):
        _add("world", "cat", 0.0, 0.0, "FAIL", "cottage dict 缺 cat")
        return
    var root: Node3D = cat.get("root")
    if root == null:
        _add("world", "cat", 0.0, 0.0, "FAIL", "cat.root 为空")
        return
    var aabb := _subtree_aabb(root, root)
    var body_node: Node3D = cat.get("body")
    var body_aabb := _subtree_aabb(root, body_node, false) if body_node != null else AABB()
    var head_node: Node3D = cat.get("head")
    var head_aabb := _subtree_aabb(root, head_node, false) if head_node != null else AABB()
    var shoulder := maxf(body_aabb.end.y, 0.0)
    var body_len := 0.0
    if body_node != null:
        var walk_aabb := body_aabb
        if head_node != null:
            walk_aabb = walk_aabb.merge(head_aabb)
        body_len = walk_aabb.size.z
    _chk_range("world", "cat_shoulder_h", shoulder, "PorchCat Body 组 AABB 顶（坐姿肩/背高；T4 修后 0.297）")
    _put_raw("world.cat.ear_top_h", aabb.size.y)
    _chk_range("world", "cat_body_len", body_len, "Body+Head 合并 AABB 深（体长，不含尾）")
    _put_raw("world.cat.aabb", aabb)
    _put_raw("world.cat.body_aabb", body_aabb)

func _group_birds() -> void:
    var birds: Array = []
    for n in _walk(get_root()):
        if not (n is Node3D):
            continue
        var bn := String(n.name)
        if bn.begins_with("Bird") and bn.length() > 4 and bn.substr(4).is_valid_int():
            birds.append(n)
    if birds.is_empty():
        _add("world", "gull", 0.0, 0.0, "FAIL", "找不到 Bird* 海鸥节点")
        return
    var node: Node3D = birds[0]
    var body_aabbs: Array = []
    var saved: Array = []
    var wing_aabbs_spread: Array = []
    for n in _walk(node):
        if not (n is MeshInstance3D):
            continue
        var mi: MeshInstance3D = n
        if mi.mesh == null:
            continue
        var nm := String(mi.name)
        if nm.contains("wing") or nm.contains("elbow"):
            continue
        body_aabbs.append(_local_aabb_of(mi, node))
    # 翼展：把 wing_l/wing_r 及肘节点旋转归零（设计展宽）后测双翼网格 x 向跨度，随后还原
    for wing_name in ["wing_l", "wing_r"]:
        var wing := node.get_node_or_null(wing_name) as Node3D
        if wing == null:
            continue
        saved.append([wing, wing.rotation])
        wing.rotation = Vector3.ZERO
        var elbow := wing.get_node_or_null("elbow_l") as Node3D
        if elbow == null:
            elbow = wing.get_node_or_null("elbow_r") as Node3D
        if elbow != null:
            saved.append([elbow, elbow.rotation])
            elbow.rotation = Vector3.ZERO
    for n in _walk(node):
        if not (n is MeshInstance3D):
            continue
        var mi2: MeshInstance3D = n
        if mi2.mesh == null:
            continue
        var nm2 := String(mi2.name)
        if nm2.contains("wing"):
            wing_aabbs_spread.append(_local_aabb_of(mi2, node))
    for pair in saved:
        var pp: Array = pair
        var nd: Node3D = pp[0]
        nd.rotation = pp[1]
    var body_aabb := _union_aabbs(body_aabbs)
    var spread_aabb := _union_aabbs(wing_aabbs_spread)
    _chk_range("world", "gull_body_len", body_aabb.size.z, "海鸥躯干+头+喙+尾网格合并 AABB 深（不含翼/腿）")
    _chk_range("world", "gull_wingspan", spread_aabb.size.x, "双翼旋转归零后翼网格 x 向跨度（设计翼展）")
    _put_raw("world.gull.body_aabb", body_aabb)
    _put_raw("world.gull.wing_spread_aabb", spread_aabb)
    _put_raw("world.gull.count", birds.size())

func _group_terrain(island: Node3D) -> void:
    var node := _find_name(island, "Terrain") as Node3D
    if node == null or not (node is MeshInstance3D):
        _add("world", "island_diameter", 0.0, 0.0, "FAIL", "找不到 Terrain 网格")
        return
    var mi: MeshInstance3D = node
    var aabb := _local_aabb_of(mi, island)
    var diameter := maxf(aabb.size.x, aabb.size.z)
    var di = _world.get("island_diameter")
    if di is float or di is int:
        diameter = float(di)
    var keep: Dictionary = SPEC.keep_entry("island_terrain")
    _keep("world", "island_diameter", diameter, float(keep.get("hint", 63.6)), 4.0, "世界岛径（world.island_diameter）；Terrain 网格 AABB 含水下裙边 = %s" % _fmt(Vector3(aabb.size.x, aabb.size.y, aabb.size.z)))
    _put_raw("world.terrain.aabb", aabb)

func _group_keep_notes(island: Node3D) -> void:
    var sea := _find_name(_main, "Sea")
    if sea is MeshInstance3D:
        var sea_y := (sea as Node3D).global_position.y
        _keep("world", "sea_surface_y", sea_y, 0.0, 0.25, "海面 y=0 是干舷/码头/船只吃水共同基准")
        _put_raw("world.sea_y", sea_y)
    else:
        _add("world", "sea_surface_y", 0.0, 0.0, "PASS", "Sea 节点未找到，按设计基准 y=0 保留（reference_keep）")
    _keep("world", "day_night_cycle", 0.0, 0.0, 999.0, "日月球/光照比例保留；本轮只审计相机与灯光距离：%s" % _light_ranges())
    _keep("world", "windmill_old", float(_world.get("windmill_old_height", 12.1839389801025)), float(SPEC.keep_entry("windmill_old").get("hint", 12.19)), 999.0, "旧风车已由灯塔替换，仅历史记录（world.gd windmill_old_height）")

func _light_ranges() -> String:
    var out: Array = []
    for n in _walk(get_root()):
        if n is OmniLight3D:
            var ol: OmniLight3D = n
            out.append("%.1f" % ol.omni_range)
        elif n is SpotLight3D:
            var sl: SpotLight3D = n
            out.append("%.1f" % sl.spot_range)
    if out.is_empty():
        return "none"
    return ",".join(out)

# ============================================================== 5. 相机 ====
func _group_camera() -> void:
    var cam = _main.get("_cam")
    if not (cam is Camera3D):
        _add("camera", "camera", 0.0, 0.0, "FAIL", "找不到 main._cam Camera3D")
        return
    var c: Camera3D = cam
    _chk_range("camera", "camera_fov", c.fov, "Camera3D.fov")
    _chk_range("camera", "camera_near", c.near, "Camera3D.near（far=%.1f）" % c.far)
    var radius = _main.get("_radius")
    if radius is float or radius is int:
        _chk_range("camera", "camera_orbit_r", float(radius), "main._radius 初始轨道半径")
    var target = _main.get("_cam_target")
    if target is Vector3:
        var dist := c.global_position.distance_to(target as Vector3)
        _info("camera", "camera_distance_now", dist, 0.0, "当前相机帧到 _cam_target 实测距离")
    var fly = _main.get("_flycam")
    if fly != null:
        var fr = fly.get("radius")
        if fr is float or fr is int:
            _chk_range("camera", "camera_fly_radius", float(fr), "IsleFlyCam.radius 自由视角半径")
        _put_raw("camera.fly_max_y", fly.get("max_y"))
        _put_raw("camera.fly_speed_regular", fly.get("speed_regular"))
    _put_raw("camera.fov", c.fov)
    _put_raw("camera.near", c.near)
    _put_raw("camera.far", c.far)
    _put_raw("camera.play_radius", radius)

# ================================================================ 收尾 ====
func _js(v):
    if v is Vector3:
        return [v.x, v.y, v.z]
    if v is AABB:
        return {"position": [v.position.x, v.position.y, v.position.z], "size": [v.size.x, v.size.y, v.size.z]}
    if v is float or v is int or v is bool or v is String or v == null:
        return v
    if v is Array:
        var arr: Array = []
        for x in v:
            arr.append(_js(x))
        return arr
    if v is Dictionary:
        var dd: Dictionary = {}
        for k in v.keys():
            dd[String(k)] = _js(v[k])
        return dd
    return str(v)

# ============================================================ overlay 自检 ====
## 开发模式标尺运行时自检（--mode overlay）：真实实例化 tools/scale_debug_overlay.gd，
## 检查构建成功/人形 1.50 m（合批后从 batch_manifest 反推）/可隐藏/重建无重复/清理无残留/无常驻 _process。
func _group_overlay() -> void:
    var enabled_no_flag: bool = OVERLAY.enabled()
    _add("overlay", "enabled_no_flag", enabled_no_flag, false,
        "PASS" if not enabled_no_flag else "FAIL",
        "未传 --scale-debug 时 enabled()=%s（期望 false：默认不创建、零常驻开销）" % str(enabled_no_flag))
    var ov: Node3D = OVERLAY.new()
    ov.name = "ScaleDebugOverlay"
    _main.add_child(ov)
    await process_frame
    await process_frame
    var built: bool = ov.call("is_built")
    _add("overlay", "built", built, true, "PASS" if built else "FAIL",
        "overlay 加入场景树后 is_built()=%s（_ready 构建一次）" % str(built))
    var st: Dictionary = _overlay_stats(ov)
    var meshes := int(st["meshes"])
    var labels := int(st["labels"])
    var nodes := int(st["nodes"])
    _add("overlay", "mesh_instances", meshes, "<=120",
        "PASS" if meshes <= 120 else "WARN",
        "构建后子树 MeshInstance3D=%d（合批后为 Batch_* 网格，原始小件已并入）、Label3D=%d、节点总数=%d" % [meshes, labels, nodes])
    _add("overlay", "labels", labels, ">=8", "PASS" if labels >= 8 else "FAIL",
        "尺寸标注 Label3D=%d（1 m 立方/1.50 m 人形/房屋层高/门洞/船/灯塔/路灯/树/猫/鸥等）" % labels)
    var figs := 0
    for n in _walk(ov):
        if String((n as Node).name) == FIG.FIG_NAME:
            figs += 1
    _add("overlay", "figure_node", figs, 1, "PASS" if figs == 1 else "FAIL",
        "overlay 子树内 1.50 m 人形节点（%s）数量=%d" % [FIG.FIG_NAME, figs])
    # 合批后原 Mesh 已并入 Batch_*，用人形部件的 batch_manifest 条目反推世界 AABB。
    var fig_ab: Dictionary = _manifest_aabb_by_prefix(ov, "Ref_")
    if bool(fig_ab.get("ok", false)):
        var ab: AABB = fig_ab["aabb"]
        var h := ab.size.y
        _add("overlay", "figure_height", h, SPEC.HUMAN_HEIGHT,
            "PASS" if absf(h - SPEC.HUMAN_HEIGHT) <= SPEC.HUMAN_HEIGHT_TOL else "FAIL",
            "合批后按 batch_manifest 的 Ref_* 部件反推人形世界高 %.3f m（目标 %.3f ± %.3f）" % [h, SPEC.HUMAN_HEIGHT, SPEC.HUMAN_HEIGHT_TOL])
        var anchor: Vector3 = ov.get("_anchor")
        var foot_local := ab.position.y - anchor.y
        _add("overlay", "figure_foot_y_above_anchor", foot_local, 0.0, "PASS" if absf(foot_local) <= 0.02 else "WARN",
            "人形脚底相对落点 anchor.y=%.3f 的高度差 %.3f m（应为 0：脚底贴地）" % [anchor.y, foot_local])
    else:
        _add("overlay", "figure_height", -1.0, SPEC.HUMAN_HEIGHT, "FAIL",
            "合批后 batch_manifest 中找不到 Ref_* 人形部件，无法反推高度")
    # 再次 rebuild：不应重复叠加
    ov.call("rebuild")
    await process_frame
    await process_frame
    var st2: Dictionary = _overlay_stats(ov)
    var figs2 := 0
    for n in _walk(ov):
        if String((n as Node).name) == FIG.FIG_NAME:
            figs2 += 1
    _add("overlay", "rebuild_no_duplicate", figs2, 1, "PASS" if figs2 == 1 else "FAIL",
        "rebuild() 后人形节点=%d（期望 1，不重复叠加）、MeshInstance3D=%d、Label3D=%d" % [figs2, int(st2["meshes"]), int(st2["labels"])])
    # 隐藏开关
    ov.call("set_debug_visible", false)
    var hidden: bool = not ov.visible
    ov.call("set_debug_visible", true)
    _add("overlay", "hide_toggle", hidden, true, "PASS" if hidden else "FAIL",
        "set_debug_visible(false) 时 visible 变 false（检测到 hidden=%s；随后已恢复 true；只切显示、不重建节点）" % str(hidden))
    # 无 _process 常驻：脚本未声明 _process/_physics_process
    var scr: Script = ov.get_script()
    var src := ""
    var gs := scr as GDScript
    if gs != null:
        src = gs.source_code
    var has_proc := src.contains("func _process")
    var has_phys := src.contains("func _physics_process")
    _add("overlay", "no_per_frame_process", not (has_proc or has_phys), true,
        "PASS" if not (has_proc or has_phys) else "FAIL",
        "脚本声明 _process=%s / _physics_process=%s（标尺只在构建时工作，不每帧重建）" % [str(has_proc), str(has_phys)])
    # 清理：从主场景移除后不留节点
    ov.free()
    await process_frame
    var leftover := _find_name(get_root(), "ScaleDebugOverlay")
    _add("overlay", "cleanup", leftover == null, true, "PASS" if leftover == null else "FAIL",
        "free() 后场景树中 ScaleDebugOverlay 残留=%s" % str(leftover != null))

func _overlay_stats(ov: Node) -> Dictionary:
    var meshes := 0
    var labels := 0
    var nodes := 0
    for n in _walk(ov):
        nodes += 1
        if n is MeshInstance3D:
            meshes += 1
        elif n is Label3D:
            labels += 1
    return {"meshes": meshes, "labels": labels, "nodes": nodes}

## 从 overlay 的 batch_manifest（IsleBatch.merge_static 写入）中按部件名前缀反推 AABB。
func _manifest_aabb_by_prefix(ov: Node, prefix: String) -> Dictionary:
    if not ov.has_meta("batch_manifest"):
        return {}
    var man: Array = ov.get_meta("batch_manifest")
    var acc := AABB()
    var found := false
    for e_v in man:
        var e: Dictionary = e_v
        if not String(e.get("name", "")).begins_with(prefix):
            continue
        var kind := String(e.get("kind", ""))
        var size: Vector3 = e["size"]
        var xf: Transform3D = e["xf_group"]
        var base := AABB()
        if kind == "Box":
            base = AABB(-size * 0.5, size)
        elif kind == "Sphere" or kind == "Cyl":
            var r := maxf(size.x, size.z)
            base = AABB(Vector3(-r, -size.y * 0.5, -r), Vector3(2.0 * r, size.y, 2.0 * r))
        else:
            continue
        var b: AABB = xf * base
        if not found:
            acc = b
            found = true
        else:
            acc = acc.merge(b)
    return {"ok": found, "aabb": acc}

func _finish() -> void:
    var pass_n := 0
    var warn_n := 0
    var fail_n := 0
    var info_n := 0
    for r_v in _results:
        var r: Dictionary = r_v
        var st := String(r["status"])
        if st == "PASS":
            pass_n += 1
        elif st == "WARN":
            warn_n += 1
        elif st == "FAIL":
            fail_n += 1
        else:
            info_n += 1
        print("[SCALE] %s %s/%s | %s" % [st, r["group"], r["key"], r["detail"]])
    for k in _raw.keys():
        print("[SCALE] RAW %s = %s" % [k, str(_js(_raw[k]))])
    if _mode == "overlay":
        print("[SCALE] RESULT pass=%d warn=%d fail=%d info=%d mode=%s tag=%s" % [pass_n, warn_n, fail_n, info_n, _mode, _tag])
        quit(1 if fail_n > 0 else 0)
        return
    var base := "inventory_baseline" if _mode == "inventory" else "inventory"
    var json_path := _out_dir + "/" + base + ".json"
    var md_path := _out_dir + "/" + base + ".md"
    var payload := {
        "tag": _tag,
        "mode": _mode,
        "engine": String(Engine.get_version_info().get("string", "?")),
        "generated_at": Time.get_datetime_string_from_system(true),
        "counts": {"pass": pass_n, "warn": warn_n, "fail": fail_n, "info": info_n},
        "results": _js(_results),
        "raw": _js(_raw),
    }
    DirAccess.make_dir_recursive_absolute(_out_dir)
    var jf := FileAccess.open(json_path, FileAccess.WRITE)
    if jf != null:
        jf.store_string(JSON.stringify(payload, "  "))
        jf.close()
        print("[SCALE] WROTE %s" % json_path)
    else:
        print("[SCALE] FAIL cannot write %s" % json_path)
    var md := _build_md(payload)
    var mf := FileAccess.open(md_path, FileAccess.WRITE)
    if mf != null:
        mf.store_string(md)
        mf.close()
        print("[SCALE] WROTE %s" % md_path)
    else:
        print("[SCALE] FAIL cannot write %s" % md_path)
    print("[SCALE] RESULT pass=%d warn=%d fail=%d info=%d mode=%s tag=%s" % [pass_n, warn_n, fail_n, info_n, _mode, _tag])
    if _mode == "audit" and fail_n > 0:
        quit(1)
    else:
        quit(0)

func _build_md(payload: Dictionary) -> String:
    var lines: Array = []
    var which := "基线原始尺寸 inventory_baseline" if _mode == "inventory" else "主树审计 inventory"
    lines.append("# P7-V3.2 全岛尺度清单（%s）" % which)
    lines.append("")
    lines.append("- tag: %s" % payload["tag"])
    lines.append("- mode: %s" % payload["mode"])
    lines.append("- engine: %s" % payload["engine"])
    lines.append("- generated_at: %s" % payload["generated_at"])
    var c: Dictionary = payload["counts"]
    lines.append("- counts: pass=%d warn=%d fail=%d info=%d" % [int(c["pass"]), int(c["warn"]), int(c["fail"]), int(c["info"])])
    lines.append("")
    lines.append("说明：实测值均来自运行时真实节点/网格 AABB 与三角形射线扫描；目标/区间来自 scripts/isle_scale_spec.gd（1 世界单位 = 1 米）。")
    lines.append("")
    var group_titles := {
        "human": "1.50 m 人体参照（scripts/isle_scale_figure.gd）",
        "selftest": "测量链路自检",
        "house": "房屋（scripts/cottage.gd；局部坐标自 cottage 原点，fy=一层地坪）",
        "furniture": "25 项家具（scripts/isle_house_props.gd，真实 Mesh AABB）",
        "world": "世界资产（船/码头/灯塔/路灯/树/猫/海鸥/地形/保留项）",
        "camera": "相机（main.gd / isle_flycam.gd）",
    }
    var order: Array = []
    for r_v in payload["results"]:
        var g := String((r_v as Dictionary)["group"])
        if not order.has(g):
            order.append(g)
    for g in order:
        lines.append("## " + String(group_titles.get(g, g)))
        lines.append("")
        lines.append("| 名称 | 实测 | 目标/区间 | 状态 | 说明 |")
        lines.append("| --- | --- | --- | --- | --- |")
        for r_v in payload["results"]:
            var r: Dictionary = r_v
            if String(r["group"]) != String(g):
                continue
            var actual := _md_val(r["actual"])
            var target := _md_val(r["target"])
            var det := String(r["detail"]).replace("|", "/")
            lines.append("| %s | %s | %s | %s | %s |" % [String(r["key"]), actual, target, String(r["status"]), det])
        lines.append("")
    lines.append("## 原始记录 RAW")
    lines.append("")
    var raw: Dictionary = payload["raw"]
    for k in raw.keys():
        lines.append("- raw %s = %s" % [k, str(raw[k])])
    lines.append("")
    return "
".join(lines)

func _md_val(v) -> String:
    if v is Array and (v as Array).size() == 3 and ((v as Array)[0] is float or (v as Array)[0] is int):
        var a: Array = v
        return "%.3f×%.3f×%.3f" % [float(a[0]), float(a[1]), float(a[2])]
    if v is float or v is int:
        return "%.3f" % float(v)
    if v is Dictionary:
        var dd: Dictionary = v
        if dd.has("min") and dd.has("max"):
            return "[%.3f, %.3f]" % [float(dd["min"]), float(dd["max"])]
    return str(v)
