extends SceneTree

# P8.1-06 照明探针：解析光槽 12→16 + 室内外双池 + 壁炉/室内家具灯/门廊/窗光/码头灯。
# 用法（headless 只跑断言；窗口跑截图必须不带 --headless）：
#   Godot --headless --path <工程> --script res://tools/probe_p81_lights.gd -- --mode=checks
#   Godot --path <工程> --resolution 1600x900 --script res://tools/probe_p81_lights.gd -- --mode=shots --out=<证据目录>
#
# checks 断言（对应验收门 G6）：
#   Q1 五档 light_budget / IsleQuality.light_split 契约（10/11/12/14/16，室内 3/3/3/4/6）
#   Q2 light_sources 清单（cottage 10 + world 8）与每盏灯的 indoor 位置合法性
#   Q3 每档双池激活清单与预算一致、总数 = 预算（L7）
#   Q4 壁炉 q0..q4 全部在室内池（L1）
#   Q5 一层台灯/落地灯 q3+、吊灯全档（L2）
#   Q6 门廊 q1+、窗光 q2+、码头灯 q3+ 阶梯（L3/L4）
#   Q7 槽位合法性与池隔离（L5/L6：上限、有限值、室内灯不进室外池）
#   Q8 冬季夜间双池仍激活（L8 前提）

# P8.2-02 回归：输出改到 P8.2 证据目录（只改路径，断言未动）。
const OUT_DIR := "D:/休闲小岛幻境/开发产物/p82/02_lighting/probe_p81_lights/"
const EXP_BUDGET := [10, 11, 12, 14, 16]
const EXP_INDOOR := [3, 3, 3, 4, 6]
const OUT_CAP := 10
const IN_CAP := 6

var _mode := "checks"
var _out := OUT_DIR
var _fails: Array[String] = []
var _checks := 0
var _isle: Node = null

func _initialize() -> void:
    for a in OS.get_cmdline_user_args():
        var s := String(a)
        if s.begins_with("--mode="):
            _mode = s.substr(7)
        elif s.begins_with("--out="):
            _out = s.substr(6)
    _run.call_deferred()

func _ok(cond: bool, msg: String, detail: String = "") -> void:
    _checks += 1
    if cond:
        if detail == "":
            print("[P81LPROBE] OK   " + msg)
        else:
            print("[P81LPROBE] OK   " + msg + " | " + detail)
    else:
        _fails.append(msg)
        print("[P81LPROBE] FAIL " + msg + " | " + detail)

func _run() -> void:
    var booted := await _boot()
    if not booted:
        quit(1)
        return
    if _mode == "shots":
        await _shots()
    elif _mode == "fire":
        await _fire_debug()
    else:
        await _run_checks()
    print("[P81LPROBE] done mode=%s checks=%d fails=%d" % [_mode, _checks, _fails.size()])
    for f in _fails:
        print("[P81LPROBE]   FAILED: " + String(f))
    quit(0 if _fails.is_empty() else 1)

func _boot() -> bool:
    var packed: PackedScene = load("res://isle.tscn")
    _ok(packed != null, "isle.tscn 可加载")
    if packed == null:
        return false
    _isle = packed.instantiate()
    root.add_child(_isle)
    for i in range(4):
        await process_frame
    _ok(_isle != null and _isle.has_method("debug_light_state"), "main 提供 debug_light_state")
    _ok(_isle != null and _isle.has_method("_apply_quality"), "main 提供 _apply_quality")
    return _isle != null

# ============================================================ 几何/工具
## 与 shaders/toon.gdshader::indoor_mask 逐行同构（世界→房屋局部，与摄像机无关）。
func _indoor_mask(wp: Vector3, gh: Vector4, gh2: Vector4, gr: Vector4) -> float:
    var c := gh.w
    var s := gh2.x
    var dx := wp.x - gh.x
    var dz := wp.z - gh.z
    var lx := c * dx - s * dz
    var lz := s * dx + c * dz
    var dy := wp.y - gh.y
    if absf(lx) > gh2.y or absf(lz) > gh2.z:
        return 0.0
    if dy < gh2.w:
        return 0.0
    if dy <= gr.w:
        return 1.0
    var roof_under := gr.x - gr.y * absf(lx) - gr.z
    if dy <= roof_under:
        return 1.0
    return 0.0

func _house_volume() -> Array:
    var hr: Node3D = _isle._cottage["root"]
    var xf: Transform3D = hr.global_transform
    var yaw: float = hr.global_rotation.y
    var gh := Vector4(xf.origin.x, xf.origin.y, xf.origin.z, cos(yaw))
    var gh2 := Vector4(sin(yaw),
        IsleMath.HOUSE_W * 0.5 - IsleMath.HOUSE_WALL_T + 0.05,
        IsleMath.HOUSE_D * 0.5 - IsleMath.HOUSE_WALL_T + 0.15,
        IsleMath.HOUSE_FY - 0.05)
    var gr := Vector4(IsleMath.HOUSE_ROOF_BASE + IsleMath.HOUSE_ROOF_H,
        IsleMath.HOUSE_ROOF_H / (IsleMath.HOUSE_W * 0.5),
        0.10,
        IsleMath.HOUSE_FY + IsleMath.HOUSE_ROOM_CLEAR_H)
    return [gh, gh2, gr]

func _kinds(pool: Array) -> Array:
    var out: Array = []
    for e in pool:
        if e is Dictionary:
            out.append(String((e as Dictionary).get("kind", "?")))
    return out

func _finite_vec3(v: Variant) -> bool:
    if not (v is Vector3):
        return false
    var p: Vector3 = v
    return is_finite(p.x) and is_finite(p.y) and is_finite(p.z)

# ============================================================ 断言模式
func _run_checks() -> void:
    # ---- Q1 五档预算契约 ----
    for q in range(5):
        var p: Dictionary = IsleQuality.QUALITY_PRESETS[q]
        var sp: Dictionary = IsleQuality.light_split(q)
        _ok(int(p.get("light_budget", -1)) == EXP_BUDGET[q],
            "q%d light_budget=%d" % [q, int(p.get("light_budget", -1))], "契约 %d" % EXP_BUDGET[q])
        _ok(int(sp.get("total", -1)) == EXP_BUDGET[q], "q%d light_split.total" % q, str(sp))
        _ok(int(sp.get("indoor", -1)) == EXP_INDOOR[q], "q%d light_split.indoor" % q,
            "%d（契约 %d）" % [int(sp.get("indoor", -1)), EXP_INDOOR[q]])
        _ok(int(sp.get("outdoor", -1)) == EXP_BUDGET[q] - EXP_INDOOR[q], "q%d light_split.outdoor" % q,
            "%d（契约 %d）" % [int(sp.get("outdoor", -1)), EXP_BUDGET[q] - EXP_INDOOR[q]])
        _isle._apply_quality(q)
        await process_frame
        _ok(int(_isle._light_budget) == EXP_BUDGET[q], "q%d 应用后 _light_budget" % q,
            "%d（契约 %d）" % [int(_isle._light_budget), EXP_BUDGET[q]])
        # Lead 复核 2026-10-22：main._fallback_quality_params 的兜底预算必须同源（旧 7/8/9/11/12 会静默把 q3/q4 降到 11/12）。
        var fb: Dictionary = _isle._fallback_quality_params(q)
        _ok(int(fb.get("light_budget", -1)) == EXP_BUDGET[q], "q%d 兜底 light_budget 同源" % q,
            "%d（契约 %d）" % [int(fb.get("light_budget", -1)), EXP_BUDGET[q]])
    _isle._apply_quality(2)
    await process_frame

    # ---- Q2 light_sources 清单 ----
    var csrc: Array = _isle._cottage.get("light_sources", [])
    var wsrc: Array = _isle._world.get("light_sources", [])
    _ok(csrc.size() == 10, "cottage light_sources 条数", "actual=%d expect=10" % csrc.size())
    _ok(wsrc.size() == 8, "world light_sources 条数", "actual=%d expect=8" % wsrc.size())
    var vol := _house_volume()
    var gh: Vector4 = vol[0]
    var gh2: Vector4 = vol[1]
    var gr: Vector4 = vol[2]
    var kinds := {}
    var mask_bad: Array = []
    var num_bad: Array = []
    for src in csrc:
        if not (src is Dictionary):
            continue
        var d: Dictionary = src
        var k := String(d.get("kind", "?"))
        kinds[k] = int(kinds.get(k, 0)) + 1
        _ok(d.has("indoor") and d.has("priority") and d.has("energy") and d.has("range"),
            "cottage[%s] 含 indoor/priority/energy/range" % k)
        var pos: Vector3 = d.get("pos", Vector3.ZERO)
        var mask := _indoor_mask(pos, gh, gh2, gr)
        if bool(d.get("indoor", false)):
            if mask < 0.5:
                mask_bad.append(k)
        else:
            # 门廊灯/窗光是"室外池里照亮室外"的聚合槽，其位置本身就应在屋外
            if mask > 0.5:
                mask_bad.append(k)
        var rng := float(d.get("range", 0.0))
        var en := float(d.get("energy", d.get("intensity", 0.0)))
        if not _finite_vec3(pos) or rng <= 0.0 or rng > 20.0 or en <= 0.0 or en > 3.0:
            num_bad.append("%s(pos=%s,range=%.2f,energy=%.2f)" % [k, str(pos), rng, en])
    _ok(mask_bad.is_empty(), "灯位置与 indoor 标志一致（室内灯在体积内、室外灯在外）", str(mask_bad))
    _ok(num_bad.is_empty(), "灯参数数值合法（range<=20, energy<=3）", str(num_bad))
    for k in ["fireplace", "chandelier", "table_lamp", "floor_lamp", "porch_lantern", "window_glow"]:
        _ok(int(kinds.get(k, 0)) == 1, "cottage 唯一灯种 %s" % k, "count=%d" % int(kinds.get(k, 0)))
    _ok(int(kinds.get("attic_chandelier", 0)) == 2, "阁楼吊灯 2 盏", "count=%d" % int(kinds.get("attic_chandelier", 0)))
    _ok(int(kinds.get("attic_table_lamp", 0)) == 2, "阁楼台灯 2 盏", "count=%d" % int(kinds.get("attic_table_lamp", 0)))

    # ---- Q3 每档双池激活清单（L7）----
    # Lead 复核 2026-10-22：室外 rank 改为 路灯0→灯塔1→码头2→门廊3→窗光4（码头灯 q1+ 生效、默认 q2 有门廊）。
    var L := "street_lamp"
    var exp_out: Array = [
        [L, L, L, L, L, L, "lighthouse"],
        [L, L, L, L, L, L, "lighthouse", "dock"],
        [L, L, L, L, L, L, "lighthouse", "dock", "porch_lantern"],
        [L, L, L, L, L, L, "lighthouse", "dock", "porch_lantern", "window_glow"],
        [L, L, L, L, L, L, "lighthouse", "dock", "porch_lantern", "window_glow"],
    ]
    var base_in := ["fireplace", "chandelier", "table_lamp"]
    var exp_in: Array = [
        base_in,
        base_in,
        base_in,
        ["fireplace", "chandelier", "table_lamp", "floor_lamp"],
        ["fireplace", "chandelier", "table_lamp", "floor_lamp", "attic_chandelier", "attic_chandelier"],
    ]
    for q in range(5):
        _isle._apply_quality(q)
        await process_frame
        await process_frame
        # 断言确定性：船灯可见时会临时替换「窗光聚合槽」，导致五档固定清单抖动。
        # 这里显式压掉船灯（fade/gain 归零）再读池，恢复见循环结束后。
        _isle.set("_boat_fade", 0.0)
        _isle.set("_boat_light_gain", 0.0)
        var st: Dictionary = _isle.debug_light_state()
        var po: Array = st.get("pool_outdoor", [])
        var pi: Array = st.get("pool_indoor", [])
        var so := _kinds(po)
        var si := _kinds(pi)
        _ok(so == exp_out[q], "q%d 室外池激活清单" % q, "actual=%s" % str(so))
        _ok(si == exp_in[q], "q%d 室内池激活清单" % q, "actual=%s" % str(si))
        _ok(int(st.get("outdoor_count", -1)) == exp_out[q].size(), "q%d outdoor_count" % q,
            "%d expect %d" % [int(st.get("outdoor_count", -1)), exp_out[q].size()])
        _ok(int(st.get("indoor_count", -1)) == exp_in[q].size(), "q%d indoor_count" % q,
            "%d expect %d" % [int(st.get("indoor_count", -1)), exp_in[q].size()])
        _ok(int(st.get("outdoor_count", 0)) + int(st.get("indoor_count", 0)) == EXP_BUDGET[q],
            "q%d 双池激活总数=预算" % q, "%d+%d vs %d" % [int(st.get("outdoor_count", 0)), int(st.get("indoor_count", 0)), EXP_BUDGET[q]])
        _ok(int(st.get("outdoor_budget", -1)) == EXP_BUDGET[q] - EXP_INDOOR[q], "q%d outdoor_budget" % q, str(st.get("outdoor_budget", null)))
        _ok(int(st.get("indoor_budget", -1)) == EXP_INDOOR[q], "q%d indoor_budget" % q, str(st.get("indoor_budget", null)))
        # 池隔离：室外池无室内灯种，室内池无室外灯种
        var cross := false
        for k in so:
            if k in ["fireplace", "chandelier", "table_lamp", "floor_lamp", "attic_chandelier", "attic_table_lamp"]:
                cross = true
        for k in si:
            if k in ["street_lamp", "lighthouse", "porch_lantern", "window_glow", "dock"]:
                cross = true
        _ok(not cross, "q%d 室内外池无串池（L5 结构前提）" % q)
        # L1 壁炉全档在列
        _ok(si.has("fireplace"), "q%d 壁炉在室内池（L1）" % q)
        # L2 一层家具灯：吊灯全档、台灯全档、落地灯 q3+
        _ok(si.has("chandelier"), "q%d 一层吊灯在列" % q)
        _ok(si.has("table_lamp"), "q%d 一层台灯在列" % q)
        _ok(si.has("floor_lamp") == (q >= 3), "q%d 一层落地灯在列=%s（契约 q3+）" % [q, str(q >= 3)], str(si.has("floor_lamp")))
        # L3/L4 室外阶梯：门廊 q1+、窗光 q2+、码头 q3+
        _ok(so.has("dock") == (q >= 1), "q%d 码头灯在列=%s（契约 q1+，Lead 复核）" % [q, str(q >= 1)], str(so.has("dock")))
        _ok(so.has("porch_lantern") == (q >= 2), "q%d 门廊灯在列=%s（契约 q2+，Lead 复核）" % [q, str(q >= 2)], str(so.has("porch_lantern")))
        _ok(so.has("window_glow") == (q >= 3), "q%d 窗光在列=%s（契约 q3+，Lead 复核）" % [q, str(q >= 3)], str(so.has("window_glow")))
        # L6 槽位合法：上限、有限值
        _ok(po.size() <= OUT_CAP, "q%d 室外池 <= %d 槽" % [q, OUT_CAP], "size=%d" % po.size())
        _ok(pi.size() <= IN_CAP, "q%d 室内池 <= %d 槽" % [q, IN_CAP], "size=%d" % pi.size())
        var bad := 0
        for pool in [po, pi]:
            for e in pool:
                if not (e is Dictionary):
                    bad += 1
                    continue
                var ed: Dictionary = e
                if not _finite_vec3(ed.get("pos", null)):
                    bad += 1
                if not is_finite(float(ed.get("energy", 0.0))):
                    bad += 1
        _ok(bad == 0, "q%d 槽位数值有限（无 NaN）" % q, "bad=%d" % bad)

    # 恢复船灯正常淡入（Q3 期间被压掉）
    _isle.set("_boat_fade", 1.0)

    # ---- Q8 冬季夜间双池仍激活（L8 前提；像素证据见 shots）----
    _isle._apply_quality(2)
    _isle._jump_datetime(2027, 1, 15, 20, 30, 0)
    await process_frame
    await process_frame
    var stw: Dictionary = _isle.debug_light_state()
    _ok(int(stw.get("outdoor_count", 0)) > 0 and int(stw.get("indoor_count", 0)) > 0,
        "冬季夜间双池仍激活（L8 前提）", "outdoor=%d indoor=%d" % [int(stw.get("outdoor_count", 0)), int(stw.get("indoor_count", 0))])
    var wsrc_ok := true
    for k in _kinds(stw.get("pool_indoor", [])):
        if String(k) == "?":
            wsrc_ok = false
    _ok(wsrc_ok, "debug_light_state 池条目均带 kind")

# ============================================================ 截图模式
func _wait(sec: float) -> void:
    await create_timer(sec).timeout

## 壁炉专项调试：打印自发光材质清单 + 三机位截图（确认三块火焰是否在场景中被渲染）。
func _fire_debug() -> void:
    DirAccess.make_dir_recursive_absolute(_out)
    _isle._mode = 1
    _isle._started = true
    _isle._paused = true
    _isle._blending = ""
    if _isle._menu != null:
        _isle._menu.instant_finish()
    if _isle._hud != null:
        _isle._hud.set_hud_visible(false, false)
    _isle._auto_orbit = false
    _isle._shot_beam_lock = true
    _isle._time_source = "sim"
    _isle._p8_wfx_apply(2027, 1, 15, 20, 30, "clear", 0.0)
    await _wait(1.0)
    var c: Dictionary = _isle._cottage
    var hr: Node3D = c["root"]
    var fire: Vector3 = c["fireplace_world"]
    var yaw: float = hr.global_rotation.y
    var front := Vector3(sin(yaw), 0.0, cos(yaw))
    var right := Vector3(cos(yaw), 0.0, -sin(yaw))
    print("[P81LFIRE] fireplace_world=" + str(fire))
    var seen := {}
    var lit := 0
    var near := 0
    var geoms: Array = _isle.find_children("*", "GeometryInstance3D", true, false)
    for gi in geoms:
        var mats: Array = []
        var mo = gi.get("material_override")
        if mo is ShaderMaterial:
            mats.append(mo)
        if gi is MeshInstance3D and gi.mesh != null:
            for si in range(gi.mesh.get_surface_count()):
                var sm = gi.get_surface_override_material(si)
                if sm == null:
                    sm = gi.mesh.surface_get_material(si)
                if sm is ShaderMaterial:
                    mats.append(sm)
        elif gi is MultiMeshInstance3D and gi.multimesh != null and gi.multimesh.mesh != null:
            for si in range(gi.multimesh.mesh.get_surface_count()):
                var sm2 = gi.multimesh.mesh.surface_get_material(si)
                if sm2 is ShaderMaterial:
                    mats.append(sm2)
        for m in mats:
            var mid: int = m.get_instance_id()
            if seen.has(mid):
                continue
            seen[mid] = true
            var sl = m.get_shader_parameter("self_lit")
            if sl == null or float(sl) <= 0.5:
                continue
            lit += 1
            var wp := Vector3.ZERO
            if gi is Node3D:
                wp = (gi as Node3D).global_position
            var d: float = wp.distance_to(fire)
            var gl = m.get_shader_parameter("glow")
            var glow: float = 0.0 if gl == null else float(gl)
            var alb = m.get_shader_parameter("albedo")
            if d < 3.0:
                near += 1
            if true:
                print("[P81LFIRE] self_lit#%d node=%s pos=%s dist=%.2f glow=%.2f albedo=%s" % [lit, str(gi.get_path()), str(wp), d, glow, str(alb)])
    print("[P81LFIRE] self_lit_materials=%d near_fire=%d" % [lit, near])
    var b5 = _isle.get_node_or_null("World/Cottage/Batch_05")
    if b5 is MeshInstance3D and b5.mesh != null:
        var aabb: AABB = b5.mesh.get_aabb()
        print("[P81LFIRE] Batch_05 aabb=%s .. %s surfaces=%d" % [str(aabb.position), str(aabb.end), b5.mesh.get_surface_count()])
        for si in range(b5.mesh.get_surface_count()):
            var smm: Material = b5.mesh.surface_get_material(si)
            if smm is ShaderMaterial:
                var sl2 = smm.get_shader_parameter("self_lit")
                var av = smm.get_shader_parameter("albedo")
                var uvc = smm.get_shader_parameter("use_vertex_color")
                print("[P81LFIRE] Batch_05 surf%d fmt=%d self_lit=%s albedo=%s uvc=%s" % [si, b5.mesh.surface_get_format(si), str(sl2), str(av), str(uvc)])
    var any_flame := 0
    for ch in _isle.get_node("World/Cottage").get_children():
        if ch is MeshInstance3D and ch.mesh is BoxMesh:
            var bb: BoxMesh = ch.mesh
            if abs(bb.size.x - 0.14) < 0.001 and abs(bb.size.y - 0.07) < 0.001:
                any_flame += 1
                print("[P81LFIRE] flame node=%s pos=%s visible=%s" % [str(ch.get_path()), str(ch.position), str(ch.visible)])
    print("[P81LFIRE] unmerged_flame_nodes=%d" % any_flame)
    # manifest 中查找火焰 BoxMesh 记录
    var cot: Node3D = _isle.get_node("World/Cottage")
    if cot.has_meta("batch_manifest"):
        var mf: Array = cot.get_meta("batch_manifest")
        for e in mf:
            var sz: Vector3 = e.get("size", Vector3.ZERO)
            if absf(sz.x - 0.14) < 0.002 and absf(sz.y - 0.07) < 0.002:
                print("[P81LFIRE] manifest flame size=%s xf=%s xf_group=%s parent=%s mat=%s" % [str(sz), str(e.get("xf", null)), str(e.get("xf_group", null)), str(e.get("parent", "")), str(e.get("mat", ""))])
    # 火源附近的 halo QuadMesh
    var halo_nodes: Array = []
    for qn in _isle.find_children("*", "MeshInstance3D", true, false):
        if qn.mesh is QuadMesh and (qn as Node3D).global_position.distance_to(fire) < 2.5:
            halo_nodes.append(qn)
            print("[P81LFIRE] halo_quad node=%s pos=%s size=%s" % [str(qn.get_path()), str((qn as Node3D).global_position), str((qn.mesh as QuadMesh).size)])
    # 从合批 manifest 反查「正面位于 z≈-2.20、y 跨度大」的部件（嫌疑遮挡体）
    if cot.has_meta("batch_manifest"):
        var mf2: Array = cot.get_meta("batch_manifest")
        for e2 in mf2:
            var sg: Vector3 = e2.get("size", Vector3.ZERO)
            var x2 = e2.get("xf_group", null)
            if x2 is Transform3D:
                var o2: Vector3 = (x2 as Transform3D).origin
                var zfront: float = o2.z + sg.z * 0.5
                if absf(zfront + 2.20) < 0.06 and sg.y > 1.0:
                    print("[P81LFIRE] suspect size=%s origin=%s zfront=%.3f parent=%s mat=%s" % [str(sg), str(o2), zfront, str(e2.get("parent", "")), str(e2.get("mat", ""))])
    _cam(fire + front * 3.4 + right * 0.9 + Vector3(0.0, 0.6, 0.0), fire + Vector3(0.0, -0.15, 0.0), 50.0)
    await _shot("fire_clean_wide")
    # 仅隐藏 Batch_05（含火焰材质），看暗斑是否消失
    var b5a = _isle.get_node_or_null("World/Cottage/Batch_05")
    if b5a != null:
        b5a.visible = false
        await _wait(0.15)
        await _shot("fire_nobatch05")
        b5a.visible = true
        await _wait(0.15)
    # 把壁炉解析光能量置 0，看暗斑是否消失（判断是否为灯光梯度）
    var ls_arr: Array = _isle.get("_lights")
    var saved_en: Array = []
    for e in ls_arr:
        if String(e.get("kind", "")) == "fireplace":
            saved_en.append([e, float(e.get("energy", 0.0))])
            e["energy"] = 0.0
    await _wait(0.2)
    await _shot("fire_nolight")
    # 找出「包含壁炉解析光点」的合批网格（= 烟囱体外盒），隐藏后看壁炉装饰是否恢复
    var cnode: Node3D = hr
    var fire_local: Vector3 = cnode.to_local(fire)
    var hit_node: Node3D = null
    for ch in cnode.get_children():
        if ch is MeshInstance3D and (ch as MeshInstance3D).mesh != null:
            var mi := ch as MeshInstance3D
            var ab: AABB = mi.get_aabb()
            if ab.has_point(fire_local):
                print("[P81LFIRE] batch " + mi.name + " aabb=" + str(ab) + " contains fire_local=" + str(fire_local))
                if hit_node == null:
                    hit_node = mi
    if hit_node != null:
        print("[P81LFIRE] hide chimney body batch=" + str(hit_node.name))
        hit_node.visible = false
        await _wait(0.2)
        _cam(fire + front * 3.4 + right * 0.9 + Vector3(0.0, 0.6, 0.0), fire + Vector3(0.0, -0.15, 0.0), 50.0)
        await _shot("fire_hide_chimney")
        hit_node.visible = true
        await _wait(0.15)
    for pair in saved_en:
        pair[0]["energy"] = pair[1]
    await _wait(0.2)
    # 定位遮挡面：在候选 z 平面放洋红薄板，比较是否与「大面」共面
    var probe_mat: ShaderMaterial = ShaderMaterial.new()
    probe_mat.shader = load("res://shaders/toon.gdshader")
    probe_mat.set_shader_parameter("albedo", Color(1.0, 0.0, 1.0))
    probe_mat.set_shader_parameter("self_lit", 1.0)
    probe_mat.set_shader_parameter("glow", 1.2)
    probe_mat.set_shader_parameter("use_vertex_color", 0.0)
    var zs := [-2.16, -2.18, -2.19, -2.20, -2.21, -2.22, -2.24]
    var tags := ["z216", "z218", "z219", "z220", "z221", "z222", "z224"]
    for zi in range(zs.size()):
        var bm := BoxMesh.new()
        bm.size = Vector3(0.30, 0.30, 0.012)
        var bmi := MeshInstance3D.new()
        bmi.mesh = bm
        bmi.material_override = probe_mat
        bmi.position = Vector3(-2.20, 1.36, float(zs[zi]))
        hr.add_child(bmi)
        await _wait(0.10)
        _cam(fire + front * 3.4 + right * 0.9 + Vector3(0.0, 0.6, 0.0), fire + Vector3(0.0, -0.15, 0.0), 50.0)
        await _shot("fire_plane_" + String(tags[zi]))
        bmi.queue_free()
    await _wait(0.15)
    for hn in halo_nodes:
        hn.visible = false
    await _wait(0.15)
    _cam(fire + front * 2.55 + right * 0.55 + Vector3(0.0, 0.10, 0.0), fire + Vector3(0.0, -0.42, 0.0), 48.0)
    await _shot("fire_nohalo")
    for hn in halo_nodes:
        hn.visible = true
    # 只显示 Batch_05，确认合批网格里火焰几何的实际位置
    var vis_tmp: Array = []
    for n2 in cot.find_children("*", "MeshInstance3D", true, false):
        vis_tmp.append([n2, n2.visible])
        n2.visible = false
    var b5n = cot.get_node_or_null("Batch_05")
    if b5n != null:
        b5n.visible = true
    await _wait(0.15)
    _cam(fire + front * 3.2 + right * 0.6 + Vector3(0.0, 0.5, 0.0), fire + Vector3(0.0, -0.1, 0.0), 55.0)
    await _shot("fire_only_batch05")
    for pair in vis_tmp:
        pair[0].visible = pair[1]
    await _wait(0.15)
    var tsh: Shader = load("res://shaders/toon.gdshader")
    var tmat := ShaderMaterial.new()
    tmat.shader = tsh
    tmat.set_shader_parameter("albedo", Color("ff9a3c"))
    tmat.set_shader_parameter("self_lit", 1.0)
    tmat.set_shader_parameter("glow", 1.35)
    var tbm := BoxMesh.new()
    tbm.size = Vector3(0.5, 0.5, 0.5)
    var tmi := MeshInstance3D.new()
    tmi.name = "P81FireTestCube"
    tmi.mesh = tbm
    tmi.material_override = tmat
    tmi.position = Vector3(-2.20, 1.10, -1.55)
    _isle.get_node("World/Cottage").add_child(tmi)
    await _wait(0.2)
    _cam(fire + front * 0.95 + right * 0.10 + Vector3(0.0, 0.06, 0.0), fire + Vector3(0.0, -0.28, 0.0), 34.0)
    await _shot("fire_macro")
    _cam(fire + front * 2.55 + right * 0.55 + Vector3(0.0, 0.10, 0.0), fire + Vector3(0.0, -0.42, 0.0), 48.0)
    await _shot("fire_testcube")
    _cam(fire + front * 4.6 + right * 1.6 + Vector3(0.0, 0.55, 0.0), fire + Vector3(0.0, -0.1, 0.0), 50.0)
    await _shot("fire_wide")
    _cam(fire + front * 1.90 + right * 0.30 + Vector3(0.0, -0.05, 0.0), fire + Vector3(0.0, -0.30, 0.0), 42.0)
    await _shot("fire_front_low")
    _cam(fire + front * 1.20 + right * 1.60 + Vector3(0.0, 0.25, 0.0), fire + Vector3(0.0, -0.10, 0.0), 45.0)
    await _shot("fire_side")
    print("[P81LFIRE] done")

func _shot(tag: String) -> void:
    await _isle._save_shot(tag, _out)

func _cam(eye: Vector3, target: Vector3, fov: float) -> void:
    _isle._pose_look(eye, target, fov)

func _shots() -> void:
    DirAccess.make_dir_recursive_absolute(_out)
    _isle._mode = 1
    _isle._started = true
    _isle._paused = true
    _isle._blending = ""
    if _isle._menu != null:
        _isle._menu.instant_finish()
    if _isle._hud != null:
        _isle._hud.set_hud_visible(false, false)
    _isle._auto_orbit = false
    _isle._shot_beam_lock = true
    _isle._time_source = "sim"
    await _wait(0.8)
    var c: Dictionary = _isle._cottage
    var hr: Node3D = c["root"]
    var yaw: float = hr.global_rotation.y
    var front := Vector3(sin(yaw), 0.0, cos(yaw))
    var right := Vector3(cos(yaw), 0.0, -sin(yaw))
    var win: Vector3 = c["front_window_world"][0]
    var lantern: Vector3 = c["lantern_mid_world"]
    var fire: Vector3 = c["fireplace_world"]
    var tl: Vector3 = c["table_lamp_world"]
    var attic: Vector3 = c["attic_lamp_world"]
    var dock_light: Vector3 = _isle._world["dock"]["light"]["pos"]
    var q_tags: Array = []
    # ---- 夜间：五档 × (门廊+室内立面 / 一层室内 / 壁炉 / 码头 / 白天室内另做) ----
    _isle._p8_wfx_apply(2027, 1, 15, 20, 30, "clear", 0.0)
    await _wait(0.6)
    for q in range(5):
        _isle._apply_quality(q)
        await _wait(0.35)
        # 夜景立面：门廊灯笼 + 窗内暖光（室外看室内，L3/L5）
        _cam(win + front * 6.2 + right * 0.9 + Vector3(0.0, 1.5, 0.0), win + Vector3(0.0, -0.9, 0.0), 52.0)
        await _shot("q%d_night_facade" % q)
        # 一层室内：边柜台灯 + 落地灯 + 吊灯全景（L2）
        _cam(tl + front * 2.9 - right * 2.1 + Vector3(0.0, 0.95, 0.0), tl + Vector3(0.0, -0.35, 0.0), 58.0)
        await _shot("q%d_night_inside" % q)
        # 壁炉近景（L1）
        # 更正面、更低机位：让炉膛三块自发光火焰与炉前地面光池同时入画。
        _cam(fire + front * 2.55 + right * 0.55 + Vector3(0.0, 0.10, 0.0), fire + Vector3(0.0, -0.42, 0.0), 48.0)
        await _shot("q%d_night_fireplace" % q)
        # 码头灯与近水面（L4）
        # 从水道侧面斜看甲板（避免灯罩 halo 贴镜头、同时带入近水面）。
        var dock_s: Vector3 = IsleMath.dock_start()
        var dock_e: Vector3 = IsleMath.dock_end()
        var dock_dir: Vector3 = (dock_e - dock_s).normalized()
        var dock_side := Vector3(-dock_dir.z, 0.0, dock_dir.x)
        var dock_mid: Vector3 = dock_s.lerp(dock_e, 0.80)
        _cam(dock_mid - dock_dir * 6.5 + dock_side * 6.0 + Vector3(0.0, 3.4, 0.0), dock_mid - Vector3(0.0, 1.1, 0.0), 50.0)
        await _shot("q%d_night_dock" % q)
        q_tags.append("q%d" % q)
    _isle._apply_quality(2)
    await _wait(0.35)
    # ---- q2 追加：夜间全岛 / 阁楼 / 门廊仰视 ----
    _isle._p8_camera_island()
    await _shot("q2_night_island")
    # 阁楼从洞口侧沿 -Z 看：两盏阁楼吊灯 + 床/书桌/台灯同框。
    _cam(hr.global_transform * Vector3(0.20, 4.72, 2.35), hr.global_transform * Vector3(0.20, 3.55, -1.60), 62.0)
    await _shot("q2_night_attic")
    _cam(lantern + front * 3.4 + right * 1.5 + Vector3(0.0, 1.15, 0.0), lantern + Vector3(0.0, -1.0, 0.0), 54.0)
    await _shot("q2_night_porch")
    # ---- 白天室内：灯具熄灭/微亮对比（L6 观感）----
    _isle._p8_wfx_apply(2027, 1, 15, 10, 0, "clear", 0.0)
    await _wait(0.6)
    _cam(tl + front * 2.9 - right * 2.1 + Vector3(0.0, 0.95, 0.0), tl + Vector3(0.0, -0.35, 0.0), 58.0)
    await _shot("q2_day_inside")
    _cam(fire + front * 3.0 + right * 1.4 + Vector3(0.0, 0.85, 0.0), fire + Vector3(0.0, 0.15, 0.0), 56.0)
    await _shot("q2_day_fireplace")
    # 冬季白化 + 夜间灯照叠加（L8：白化/积雪不吞灯照）
    _isle._p8_wfx_apply(2027, 1, 15, 20, 30, "heavy_snow", 30000.0)
    await _wait(0.8)
    _cam(win + front * 6.2 + right * 0.9 + Vector3(0.0, 1.5, 0.0), win + Vector3(0.0, -0.9, 0.0), 52.0)
    await _shot("q2_snow_night_facade")
    _cam(tl + front * 2.9 - right * 2.1 + Vector3(0.0, 0.95, 0.0), tl + Vector3(0.0, -0.35, 0.0), 58.0)
    await _shot("q2_snow_night_inside")
    print("[P81LPROBE] shots done qualities=%s out=%s" % [str(q_tags), _out])
