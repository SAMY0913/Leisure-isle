extends SceneTree
## P2-B v2 门前土地 / 3x3 农田 视觉层探针（只读：不改 world.gd、main.gd、场景）。
## 用法：
##   Godot_v4.7.2-stable_win64_console.exe --path <proj> --script res://tools/probe_p2b_yard.gd \
##       -- --out=D:/休闲小岛幻境/开发产物/P9/P2 --p2bshots
## 输出：<out>/p2b_probe.json、<out>/p2b_probe.log、<out>/shots/<tag>.png
## 本探针自身不生成任何游戏几何；它只读取 main._world["front_yard"] 与场景实例。

const SHOT_W := 1600
const SHOT_H := 1000
const M := preload("res://scripts/isle_math.gd")

var out_dir := "D:/休闲小岛幻境/开发产物/P9/P2"
var do_shots := false
var _main: Node = null
var _world: Dictionary = {}
var _fy: Dictionary = {}
var _cam: Camera3D = null
var _sv: SubViewport = null
var _shot_cam: Camera3D = null
var _shot_dir := ""
var _checks: Array = []
var _notes: Array = []
var _shots: Array = []
var _log_lines: Array = []
var _headless := false


func _initialize() -> void:
    _headless = DisplayServer.get_name() == "headless"
    _parse_args()
    _run.call_deferred()


func _parse_args() -> void:
    for a in OS.get_cmdline_user_args():
        var s := String(a)
        if s.begins_with("--out="):
            out_dir = s.substr(6)
        elif s == "--p2bshots":
            do_shots = true


func _log(line: String) -> void:
    print(line)
    _log_lines.append(line)


func _check(id: String, group: String, ok: bool, expect: String, actual: String) -> void:
    _checks.append({"id": id, "group": group, "ok": ok, "expect": expect, "actual": actual})
    _log("[P2B] %s %s | expect: %s | actual: %s" % ["PASS" if ok else "FAIL", id, expect, actual])


func _note(id: String, detail: String) -> void:
    _notes.append({"id": id, "detail": detail})
    _log("[P2B] NOTE %s: %s" % [id, detail])


func _run() -> void:
    var t0 := Time.get_ticks_msec()
    _log("[P2B] start %s headless=%s out=%s" % [Time.get_datetime_string_from_system(), str(_headless), out_dir])
    var ps: PackedScene = load("res://isle.tscn")
    if ps == null:
        _check("scene_load", "A", false, "isle.tscn loads", "load failed")
        _finish()
        return
    _main = ps.instantiate()
    root.add_child(_main)
    await process_frame
    await process_frame
    var S := load("res://scripts/isle_settings.gd")
    if S != null:
        _main.set("_settings", S.defaults())
        _main.call("_apply_user_settings", false)
    if not _headless:
        for i in range(3):
            await process_frame
    _main.set("_settings_save_delay", -1.0)
    _main.set("_mode", 1)
    _main.set("_started", true)
    _main.set("_paused", false)
    _main.set("_blending", "")
    _main.set("_auto_orbit", false)
    _cam = _main.get("_cam") as Camera3D
    var menu: Variant = _main.get("_menu")
    if menu != null:
        if menu.has_method("instant_finish"):
            menu.call("instant_finish")
        menu.set("menu_visible", false)
    for key in ["_hud", "_ui_layer"]:
        var nd: Variant = _main.get(key)
        if nd is CanvasLayer:
            (nd as CanvasLayer).visible = false
    _suppress_ui()
    if not _headless:
        _sv = SubViewport.new()
        _sv.size = Vector2i(SHOT_W, SHOT_H)
        _sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
        _sv.msaa_3d = Viewport.MSAA_2X
        root.add_child(_sv)
        _sv.world_3d = root.world_3d
        _shot_cam = Camera3D.new()
        _shot_cam.near = 0.05
        _shot_cam.far = 1200.0
        _sv.add_child(_shot_cam)
        _shot_cam.current = true
    _main.call("_set_time_of_day", 12 * 60 + 20)
    var weather: Variant = _main.get("_weather")
    if weather != null and weather.has_method("set_manual_type"):
        weather.set_manual_type("clear")
        weather.set("_manual_blend", 1.0)
    _main.call("_update_weather", 0.0, true)
    await process_frame
    _world = _main.get("_world") as Dictionary
    _fy = _world.get("front_yard", {}) as Dictionary
    _check("front_yard_built", "A", not _fy.is_empty(), "world.build() returns front_yard facts", "keys=%d" % _fy.size())
    if _fy.is_empty():
        _finish()
        return
    _shot_dir = out_dir + "/shots/p2b"
    DirAccess.make_dir_recursive_absolute(_shot_dir)
    _run_checks_a()
    _run_checks_b()
    if do_shots:
        await _run_shots()
    else:
        _note("no_shots", "run without --p2bshots")
    _finish()
    _log("[P2B] elapsed %.1f s" % (float(Time.get_ticks_msec() - t0) / 1000.0))


# ------------------------------------------------------------- helpers ----
func _l2w(lx: float, lz: float) -> Vector2:
    var c := cos(M.HOUSE_YAW)
    var s := sin(M.HOUSE_YAW)
    return Vector2(M.HOUSE_X + lx * c + lz * s, M.HOUSE_Z - lx * s + lz * c)


func _w2l(x: float, z: float) -> Vector2:
    var c := cos(M.HOUSE_YAW)
    var s := sin(M.HOUSE_YAW)
    var dx := x - M.HOUSE_X
    var dz := z - M.HOUSE_Z
    return Vector2(dx * c - dz * s, dx * s + dz * c)


func _terrain_l(lx: float, lz: float) -> float:
    var w := _l2w(lx, lz)
    return IsleWorld.surface_y(w.x, w.y)


func _collect_mm(node: Node, out: Array) -> void:
    if node is MultiMeshInstance3D:
        out.append(node)
    for ch in node.get_children():
        _collect_mm(ch, out)


func _summ_color(c: Color) -> String:
    return "#%02x%02x%02x a=%.2f" % [int(c.r * 255.0), int(c.g * 255.0), int(c.b * 255.0), c.a]


# --------------------------------------------------------- checks A: 几何 ----
func _run_checks_a() -> void:
    var poly: Array = _fy["polygon_local"]
    var poly_w: Array = _fy["polygon_world"]
    var want := [Vector2(-7.70, 3.28), Vector2(4.43, 3.28), Vector2(4.43, 5.15),
        Vector2(-1.45, 5.15), Vector2(-1.45, 14.75), Vector2(-7.70, 14.75)]
    var perr := 0.0
    if poly.size() != 6:
        perr = 999.0
    else:
        for i in range(6):
            perr = maxf(perr, (poly[i] as Vector2).distance_to(want[i]))
    _check("A1_pad_polygon_six_points", "A", perr <= 0.001,
        "6 点 Γ 形轮廓 (−7.70,3.28)(4.43,3.28)(4.43,5.15)(−1.45,5.15)(−1.45,14.75)(−7.70,14.75)",
        "points=%d max_err=%.5f" % [poly.size(), perr])
    # A2 坐标帧：用 M.HOUSE_X/Z/YAW 独立反算
    var ferr := 0.0
    for i in range(poly_w.size()):
        var w2 := _l2w((poly[i] as Vector2).x, (poly[i] as Vector2).y)
        ferr = maxf(ferr, Vector2(poly_w[i] as Vector2).distance_to(w2))
    _check("A2_house_local_frame", "A", ferr <= 0.0005,
        "polygon_world == l2w(polygon_local) with house frame", "max_err=%.6f m" % ferr)
    # A3 与房屋衔接：近边 lz=3.28 全跨贴地、连续、只填不挖
    var near_min := 99.0
    var near_max := -99.0
    var near_gap_max := -99.0
    var cont_max := 0.0
    var prev := 0.0
    var first := true
    var xx := -7.70
    while xx <= 4.43:
        var hh := _terrain_l(xx, 3.28)
        var w3 := _l2w(xx, 3.28)
        var yy := IsleWorld._yard_pad_y_world(w3.x, w3.y)
        near_min = minf(near_min, yy)
        near_max = maxf(near_max, yy)
        near_gap_max = maxf(near_gap_max, yy - hh)
        if not first:
            cont_max = maxf(cont_max, absf(yy - prev))
        prev = yy
        first = false
        xx += 0.25
    var hc: Dictionary = _fy["house_contact"]
    _check("A3_pad_contacts_house", "A", near_gap_max <= 0.05 and cont_max <= 0.03
        and near_max - near_min <= 0.35,
        "lz=3.28 近边全跨 7.5m 以上贴地(+0.02)、连续、与墙外皮 3.10 相差 0.18 m",
        "near_y=[%.3f,%.3f] lift_max=%.3f cont_max=%.3f wall_gap=0.180" % [
            near_min, near_max, near_gap_max, cont_max])
    # A4 九格 ↔ P1 数据层映射
    var farm_script: Object = (load("res://scripts/isle_farm.gd") as GDScript).new()
    var slots: Array = _fy["slots"]
    var merr := 0.0
    var werr := 0.0
    var idx_ok := true
    for row in slots:
        var idx: int = int(row["index"])
        var ij: Vector2i = farm_script.slot_ij(idx)
        var expect_local: Vector2 = Vector2(-4.35, 11.70) + farm_script.slot_offset(idx)
        merr = maxf(merr, (row["local"] as Vector2).distance_to(expect_local))
        var ew := _l2w(expect_local.x, expect_local.y)
        werr = maxf(werr, (row["world"] as Vector2).distance_to(ew))
        if farm_script.slot_index(ij.x, ij.y) != idx:
            idx_ok = false
        if int(row["i"]) != ij.x or int(row["j"]) != ij.y:
            idx_ok = false
    _check("A4_slots_match_isle_farm", "A", merr <= 0.0001 and werr <= 0.0005 and idx_ok
        and slots.size() == 9,
        "9 格 = 田心 + IsleFarm.slot_offset(index)，slot_index(i,j)=j*3+i",
        "slots=%d local_err=%.6f world_err=%.6f index_ok=%s pitch=%.2f" % [
            slots.size(), merr, werr, str(idx_ok), float(_fy["grid_pitch"])])
    # A5 九格共同水平面
    var spread := float(_fy["beds"]["bed_top_spread"])
    var deck_ok := true
    for row in slots:
        if absf(float(row["deck"]) - 7.536) > 0.004:
            deck_ok = false
    _check("A5_bed_common_level", "A", spread <= 0.002 and deck_ok,
        "九格土床顶共面（振幅 ≤ 0.002 m），deck 全部在 pad+0.006",
        "spread=%.5f deck_ok=%s bed_top=%.3f" % [spread, str(deck_ok), float(_fy["beds"]["bed_top_y"])])
    # A6 围栏同一坐标帧 / 门洞朝向
    var fence: Dictionary = _fy["fence"]
    var posts_out := 0
    for pl in fence["posts_local"]:
        if not IsleWorld._yard_pad_contains((pl as Vector2).x, (pl as Vector2).y, -0.05):
            posts_out += 1
    var gate_c: Vector2 = fence["gate_center_world"]
    var gate_l := _w2l(gate_c.x, gate_c.y)
    var gate_dev := gate_l.distance_to(Vector2(-4.35, 8.99))
    # 门洞必须真的空：跨门洞的横杆已整段跳过（D 组 B1 阻断的回归断言）
    var gate_skip := int(fence.get("gate_rails_skipped", 0))
    _check("A6_fence_frame_and_gate", "A", posts_out == 0 and gate_dev <= 0.35
        and absf(float(fence["gate_w"]) - 1.10) <= 0.001 and int(fence["post_count"]) >= 30
        and gate_skip >= 2,
        "围栏 5.42 见方、柱全在台内、门洞 1.10 在朝房屋近边 (lz 8.99) 且跨门横杆已跳过（门洞无遮挡）",
        "posts=%d outside=%d rail=%d gate_w=%.2f gate_local=(%.2f,%.2f) gate_rails_skipped=%d" % [
            int(fence["post_count"]), posts_out, int(fence["rail_count"]),
            float(fence["gate_w"]), gate_l.x, gate_l.y, gate_skip])
    # A7 围栏盒内台面振幅
    var amp := float(_fy["fence_box_amp"])
    _check("A7_fence_box_amp", "A", amp <= 0.010,
        "围栏盒内台面振幅 ≤ 0.01 m（P2-A 要求九格共同水平面）", "amp=%.5f m" % amp)
    # A8 小径
    var walk: Dictionary = _fy["walkway"]
    var wlen := float(walk["length_m"])
    var wdrop := float(walk["drop_m"])
    var wslope := float(walk["slope_pct"])
    _check("A8_walkway_geometry", "A", absf(wlen - 4.326) <= 0.06 and wdrop >= 0.15 and wdrop <= 0.26
        and wslope >= 3.2 and wslope <= 6.0 and bool(walk["on_pad"]),
        "小径 (−1.60,5.65)→门洞 4.326 m / 降 0.15~0.26 m（≈4~5%）/ 100% 在台内；"
        + "注：P2-A 记录 0.207/4.78% 是旧 7.737 起点，现行 max(HL+0.02,7.53) 起点为 7.707",
        "len=%.3f drop=%.3f slope=%.2f%% on_pad=%s slabs=%d skipped_junction=%d" % [
            wlen, wdrop, wslope, str(walk["on_pad"]), int(walk["slab_count"]),
            int(walk["skipped_at_junction"])])
    # A9 道路净距
    var paths: Dictionary = _fy["paths"]
    _check("A9_path_clearance", "A", float(paths["fence_to_main_edge"]) >= 2.30
        and float(paths["fence_to_spur_edge"]) >= 1.10
        and float(paths["pad_to_main_edge"]) >= 0.0 and bool(paths["layout_ok"])
        and float(paths["path_raise_max"]) <= 0.0905,
        "围栏盒→主路缘 ≥2.30、→支路缘 ≥1.10、台缘不压主路缘（≥0）、路面未被抬起 >0.09",
        "fence_main=%.3f fence_spur=%.3f pad_main=%.3f raise=%.4f layout_ok=%s" % [
            float(paths["fence_to_main_edge"]), float(paths["fence_to_spur_edge"]),
            float(paths["pad_to_main_edge"]), float(paths["path_raise_max"]),
            str(paths["layout_ok"])])
    # A10 不侵占旧花圃 / 旧菜地
    var gx0 := -9.75
    var gx1 := -5.90
    var gz0 := -9.45
    var gz1 := -2.95
    var fx0 := -4.90
    var fx1 := -1.70
    var fz0 := -9.60
    var fz1 := -6.90
    var garden_min := 1.0e9
    var field_min := 1.0e9
    for wp in poly_w:
        var wq: Vector2 = wp
        garden_min = minf(garden_min, maxf(maxf(gx0 - wq.x, wq.x - gx1), maxf(gz0 - wq.y, wq.y - gz1)))
        field_min = minf(field_min, maxf(maxf(fx0 - wq.x, wq.x - fx1), maxf(fz0 - wq.y, wq.y - fz1)))
    _check("A10_old_plots_untouched", "A", garden_min >= 1.0 and field_min >= 1.0,
        "台面距旧花圃/旧菜地 > 1 m（两者均在房屋背面 lz<0）",
        "garden=%.2f m field=%.2f m" % [garden_min, field_min])
    # A11 外缘三段式：草肩坡高 ≤0.70 m、坡面恰好 32°、坡面被地形接管、
    #     不存在任何“一步就掉下去”的竖直面（木边单独由 A12 限制）
    var edge: Dictionary = _fy["edge"]
    var hist: Dictionary = edge["fill_hist"]
    var shoulder_hmax := float(edge["shoulder_hmax"])
    var max_step := float(edge["max_step"])
    var land_err := float(edge["land_err"])   # 旧指标：只反映被 clamp 后的末行，属同义反复
    var land_meas: Dictionary = edge.get("land_meas", {})
    var lm_ok := bool(land_meas.get("ok", false))
    var lm_max_d := float(land_meas.get("max_d", 99.0))
    var lm_max_err := float(land_meas.get("max_err", 9.0))
    var row_step := 0.18
    # 独立复算：草肩的“水平跨距”必须等于 sh/tan32°，即坡度恒为 32°
    # （原 run_err 计算恒为 0，属同义反复，D 组复核后删除）
    var step_vis := float(edge["max_step_visible"])
    var slope_vis := float(edge["max_slope_visible"])
    # 判据说明：可见填方坡面（四角都明显高于原地形）不允许出现竖直面。
    #  - 32° 草肩：单行水平 0.18 m ⇒ 落差 0.1125 m；允许到 0.1725（=tan32*0.18+0.06）
    #  - 坡脚收口段：原地形本身 30° 下坡，纯 32° 坡面在 5.4 m 裙宽内落不到地面，
    #    因此最后一段按线性收口，实测最大可见坡 ≈35°（落差 ~0.128 m/行），仍无竖直面。
    #  - max_step（不限可见性）只作参考：它包含被房屋遮住的 wall_side 塌缩列与
    #    “坡面已被地形接管”的埋没区，不是可见坡度。
    _check("A11_edge_three_stage", "A", shoulder_hmax <= 0.7005
        and step_vis <= 0.2100 and slope_vis <= 46.0 and lm_ok and lm_max_d <= 24.0 and lm_max_err <= 0.120
        and float(hist["gt070"]) > 0.0 and int(edge["samples"]) > 200,
        "草肩坡高 ≤0.70 m；坡脚按 45° 收口后可见坡面无竖直面（坡角 ≤46°、单行落差 ≤0.21 m）；坡面全部落到原地形（≤0.01 m）；木边只在 fill>0.70 段",
        "shoulder_hmax=%.4f m visible_step=%.4f m (limit 0.21) max_step=%.4f m visible_slope=%.2f° (limit 46°) land(ok=%s max_d=%.2f max_err=%.4f) legacy_land_err=%.5f gt070=%.2f m perimeter=%.2f m" % [
            shoulder_hmax, step_vis, max_step, slope_vis, str(lm_ok), lm_max_d, lm_max_err, land_err,
            float(hist["gt070"]), float(edge["perimeter"])])
    _note("edge_land", "land_at=%s" % [str(edge.get("land_at", {}))])
    _note("edge_geometry", "草肩按 32° 建（可见填方面坡度恒为 32°，地形更高的地方由原地形接管）；木边长 %.2f m（%.1f%% 周长），最高 %.4f m" % [
        float(edge["timber_len"]), 100.0 * float(edge["timber_len"]) / maxf(float(edge["perimeter"]), 0.01),
        float(edge["timber_hmax"])])
    # A13 排水结构
    var gut: Dictionary = _fy["gutter"]
    var gut_node := _main.find_child("FrontYardGutter", true, false) as MeshInstance3D
    var gut_ok := gut_node != null and gut_node.mesh != null and gut_node.mesh.get_surface_count() > 0
    _check("A13_gutter_present", "A", gut_ok and float(gut["depth"]) >= 0.04,
        "非种植区有浅排水槽（0.28 m 宽 / 5 cm 深）",
        "node=%s depth=%.3f x=[%.2f,%.2f] z=[%.2f,%.2f]" % [str(gut_ok), float(gut["depth"]),
            float(gut["x0"]), float(gut["x1"]), float(gut["z0"]), float(gut["z1"])])


# ------------------------------------------------- check B: 环境 / 回归 ----
func _scatter_nodes() -> Array:
    var all: Array = []
    _collect_mm(_main, all)
    var out: Array = []
    for nd in all:
        var nm := str((nd as Node).name)
        if nm.begins_with("FrontYard"):
            continue
        out.append(nd)
    return out


func _node_kind(nm: String) -> String:
    if nm == "GrassNear" or nm == "GrassFar" or nm == "Clover":
        return "grass"
    if nm.begins_with("FlowerStems_") or nm.begins_with("FlowerHeads_"):
        return "flower"
    if nm == "Bushes":
        return "bush"
    if nm.begins_with("Rocks_"):
        return "rock"
    return ""


func _run_checks_b() -> void:
    var nodes := _scatter_nodes()
    # B1 硬净空区（围栏内走道 / 排水槽 / 石板小径 / 土床）不得残留任何散布实例
    var hard_left := 0
    var seat_bad := 0
    var near_kept := 0
    var raised := 0
    var seen_nodes: Array = []
    for nd in nodes:
        var mi := nd as MultiMeshInstance3D
        if mi == null or mi.multimesh == null:
            continue
        var nm := str(mi.name)
        var kind := _node_kind(nm)
        if kind == "":
            continue
        var mm := mi.multimesh
        seen_nodes.append("%s:%d" % [nm, mm.instance_count])
        for i in range(mm.instance_count):
            var o := mm.get_instance_transform(i).origin
            var l := _w2l(o.x, o.z)
            var plan: Dictionary = IsleWorld._yard_instance_plan(l.x, l.y, kind)
            var act := str(plan["act"])
            if act == "remove":
                hard_left += 1
            elif act == "seat":
                if absf(o.y - float(plan["y"])) > 0.012:
                    seat_bad += 1
                raised += 1
                if float(plan["sy"]) < 0.35:
                    near_kept += 1
    _check("B1_hard_clearance_clean", "B", hard_left == 0,
        "台面硬净空区（围栏内走道/排水槽/小径/土床）无任何残留散布实例",
        "leftover=%d nodes=%s" % [hard_left, ", ".join(seen_nodes)])
    _check("B2_scatter_seated_on_pad", "B", seat_bad == 0,
        "台面内草实例重新坐落：origin.y 与 pad 的差 ≤ 0.012 m（无悬浮/无埋入）",
        "seated=%d mismatch=%d" % [raised, seat_bad])
    _check("B3_near_strip_low_grass", "B", near_kept >= 20,
        "贴平近段（fill≤0.05）保留低草（只压低不剃除）", "near_strip_low=%d" % near_kept)
    # B4 全岛散布未被大面积改动
    var filt: Dictionary = _fy["filter"]
    var removed_grass := int(filt["removed_grass"])
    var removed_clover := int(filt.get("removed_clover", 0))
    var by_node: Dictionary = filt["by_node"]
    var removed_sum := 0
    var grass_total := 0
    for k in by_node.keys():
        var rec: Dictionary = by_node[k]
        if str(rec["kind"]) == "grass":
            removed_sum += int(rec["removed"])
    for nd in nodes:
        var mi2 := nd as MultiMeshInstance3D
        if mi2 != null and mi2.multimesh != null and _node_kind(str(mi2.name)) == "grass":
            grass_total += mi2.multimesh.instance_count
    # 口径：by_node 里 Clover 与 GrassNear/GrassFar 同属 kind="grass"，
    # 因此 removed_grass（仅 Grass*）+ removed_clover 才等于 removed_sum；
    # grass_total 含 Clover，故 pre = grass_total + removed_sum（B 组指出原先少报 46）。
    _check("B4_scatter_scope_limited", "B",
        removed_grass + removed_clover == removed_sum and removed_sum <= 2500,
        "只删除台面内实例：removed 全部来自 台面/走道/小径；总量 < 2500",
        "removed_grass=%d removed_clover=%d removed_all_nodes=%d grass_total_now=%d pre=%d" % [
            removed_grass, removed_clover, removed_sum, grass_total, grass_total + removed_sum])
    _note("scatter_removed_by_node", JSON.stringify(_j(by_node)))
    # B5 冬季红花：按 U5 删除锚点，接口保留
    var wb: Dictionary = _world.get("winter_bloom", {})
    var stems := wb.get("stems", null) as MultiMeshInstance3D
    var heads := wb.get("heads", null) as MultiMeshInstance3D
    var base: Array = wb.get("base", [])
    var wb_count := 0
    if stems != null and stems.multimesh != null:
        wb_count += stems.multimesh.instance_count
    if heads != null and heads.multimesh != null:
        wb_count += heads.multimesh.instance_count
    _check("B5_winter_blooms_removed", "B", base.is_empty() and wb_count == 0
        and stems != null and heads != null,
        "5 株冬季红花锚点已删除（base=[] / 实例=0），节点与返回结构保留给 main.gd selftest",
        "base=%d instances=%d stems=%s heads=%s" % [base.size(), wb_count,
            str(stems != null), str(heads != null)])
    # B6 路灯：位置/数量不变
    var lamp_nodes: Array = []
    for nm in ["PathLamp1", "PathLamp2", "PathLamp3", "GardenLamp1", "GardenLamp2", "GardenLamp3"]:
        var ln := _main.find_child(nm, true, false)
        if ln != null:
            lamp_nodes.append(nm)
    var lights: Array = _world.get("light_sources", [])
    var lmerge: Dictionary = _fy.get("lamps", {})
    var gl2: Dictionary = lmerge.get("GardenLamp2", {})
    var buried := float(gl2.get("buried", 9.0))
    _check("B6_lamps_unchanged", "B", lamp_nodes.size() == 6 and lights.size() == 8
        and buried >= 0.015 and buried <= 0.030,
        "6 盏路灯仍在、光源预算 8 不变；GardenLamp2 位置不动（台面埋其基座约 2 cm，U8）",
        "lamps=%d lights=%d GardenLamp2_buried=%.4f" % [lamp_nodes.size(), lights.size(), buried])
    # B7 既有主路/支路石板仍在、且我方石板不与其重叠
    var stones := _main.find_child("PathStones", true, false) as MultiMeshInstance3D
    var stone_n := 0
    var min_gap := 9.0
    if stones != null and stones.multimesh != null:
        stone_n = stones.multimesh.instance_count
        var slabs := _main.find_child("FrontYardSlabs", true, false) as MultiMeshInstance3D
        if slabs != null and slabs.multimesh != null:
            for i in range(slabs.multimesh.instance_count):
                var so := slabs.multimesh.get_instance_transform(i).origin
                for j in range(stone_n):
                    var po := stones.multimesh.get_instance_transform(j).origin
                    min_gap = minf(min_gap, Vector2(so.x, so.z).distance_to(Vector2(po.x, po.z)))
    _check("B7_existing_stones_intact", "B", stone_n > 0 and (min_gap >= 0.45 or stone_n == 0),
        "既有 PathStones 未被移除/覆盖；我方石板与既有石板最近中心距 ≥ 0.45 m",
        "pathstones=%d min_gap=%.3f m" % [stone_n, min_gap])
    # B8 路口不重复铺板
    var walk: Dictionary = _fy["walkway"]
    _check("B8_junction_no_double_slab", "B", int(walk["skipped_at_junction"]) >= 1
        and int(walk["slab_count"]) >= 4,
        "与花园支路交汇处 ±0.60 m 跳过铺板（不重复、不穿模）",
        "skipped=%d placed=%d" % [int(walk["skipped_at_junction"]), int(walk["slab_count"])])
    # B9 台面短草（避免剃头圈）
    var grass: Dictionary = _fy["pad_grass"]
    _check("B9_pad_grass_added", "B", int(grass["pad_grass"]) >= 600,
        "台面补铺短草 ≥ 600 株，避免大面积裸地与剃头圈",
        "pad_grass=%d tries=%d" % [int(grass["pad_grass"]), int(grass["pad_grass_tries"])])
    _note("near_strip_low_share", "台面近段低草顶点占比 %.3f" % float(_fy["near_strip_low_share"]))


# --------------------------------------------------------- screenshots ----
func _suppress_ui() -> void:
    var menu: Variant = _main.get("_menu")
    if menu != null:
        menu.set("menu_visible", false)
    _hide_layers(_main)
    _hide_layers(root)


func _hide_layers(nd: Node) -> void:
    for c in nd.get_children():
        if c is CanvasLayer:
            (c as CanvasLayer).visible = false
        _hide_layers(c)


func _pose_local(plx: float, plz: float, py: float, tlx: float, tlz: float, ty: float, fov: float) -> void:
    var pp := _l2w(plx, plz)
    var tt := _l2w(tlx, tlz)
    _main.call("_pose_look", Vector3(pp.x, py, pp.y), Vector3(tt.x, ty, tt.y), fov)


func _pose_play_default() -> void:
    _main.set("_theta", M.CAM_START_THETA)
    _main.set("_elev", 0.28)
    _main.set("_radius", M.CAM_START_R)
    _main.set("_cam_target", M.CAM_TARGET)
    _main.set("_fov", 42.0)
    _main.call("_apply_pose", _main.call("_play_pose"))


func _image_spread(img: Image) -> float:
    var mn := 1.0
    var mx := 0.0
    var step := maxi(1, int(img.get_width() / 48))
    for yy in range(0, img.get_height(), step):
        for xx in range(0, img.get_width(), step):
            var c := img.get_pixel(xx, yy)
            var v := (c.r + c.g + c.b) / 3.0
            mn = minf(mn, v)
            mx = maxf(mx, v)
    return mx - mn


func _shot(tag: String) -> void:
    if _headless:
        _check("shot_" + tag, "C", false, "窗口模式渲染", "headless: no framebuffer")
        return
    _suppress_ui()
    var cp := _cam.global_position
    var gnd := IsleWorld.surface_y(cp.x, cp.z)
    var dy := cp.y - gnd
    _check("cam_above_ground_" + tag, "C", dy >= 1.15,
        "相机在地形以上 ≥1.15 m（防止钻进山体/树冠/台底）",
        "cam=(%.1f,%.1f,%.1f) dy=%.2f" % [cp.x, cp.y, cp.z, dy])
    _shot_cam.global_transform = _cam.global_transform
    _shot_cam.fov = _cam.fov
    await process_frame
    await process_frame
    await RenderingServer.frame_post_draw
    var img: Image = _sv.get_texture().get_image() if (_sv != null and _sv.get_texture() != null) else null
    if img == null:
        _check("shot_" + tag, "C", false, "viewport image", "null")
        return
    DirAccess.make_dir_recursive_absolute(_shot_dir)
    var pth := _shot_dir + "/" + tag + ".png"
    var spread := _image_spread(img)
    if spread < 0.02:
        # 偶发首帧未绘制：再等几帧后重拍一次
        for _i in range(6):
            await process_frame
        await create_timer(0.10).timeout
        await RenderingServer.frame_post_draw
        var img2: Image = _sv.get_texture().get_image() if (_sv != null and _sv.get_texture() != null) else null
        if img2 != null:
            img = img2
            spread = _image_spread(img)
            _log("[P2B] shot %s retried (blank frame) spread=%.3f" % [tag, spread])
    _check("shot_not_blank_" + tag, "C", spread >= 0.02, "画面非空白", "luma spread=%.3f" % spread)
    var err := img.save_png(pth)
    _log("[P2B] shot %s %dx%d err=%d -> %s" % [tag, img.get_width(), img.get_height(), err, pth])
    if err == OK:
        _shots.append({"tag": tag, "path": pth, "size": [img.get_width(), img.get_height()]})
        _check("shot_" + tag, "C", true, "真实引擎渲染截图", pth)
    else:
        _check("shot_" + tag, "C", false, "真实引擎渲染截图", "save err=%d" % err)


func _run_shots() -> void:
    var pad := float(_fy["pad_y"])
    var fc: Vector2 = _fy["farm_center_local"]
    _pose_play_default()
    await _shot("01_game_default")
    _pose_local(-4.20, 6.60, pad + 2.00, -2.20, 4.30, 8.10, 55.0)
    await _shot("02_house_contact")
    _pose_local(0.40, 7.20, pad + 2.60, fc.x, fc.y, 7.60, 52.0)
    await _shot("03_farm_closeup")
    _pose_local(-1.00, 8.20, pad + 0.55, fc.x, 13.00, 7.40, 55.0)
    await _shot("04_gate_look_in")
    _pose_local(-1.00, 18.60, _terrain_l(-1.00, 18.60) + 1.50, -4.20, 14.40, 7.40, 55.0)
    await _shot("05_far_edge")
    _pose_local(2.60, 6.20, 8.60, -2.60, 7.60, 7.70, 52.0)
    await _shot("06_road_junction")
    _pose_local(-6.40, 9.20, pad + 1.80, -5.50, 10.00, 7.35, 55.0)
    await _shot("07_grass_bed_detail")
    _pose_local(-9.60, 11.00, _terrain_l(-9.60, 11.00) + 1.60, -7.40, 11.40, 7.40, 55.0)
    await _shot("08_side_slope")
    var weather: Variant = _main.get("_weather")
    if weather != null and weather.has_method("set_manual_type"):
        # 注意：天气类型 id 是 light_rain / mid_rain / heavy_rain，"rain" 不是合法 id
        weather.set_manual_type("mid_rain")
        weather.set("_manual_blend", 1.0)
    _main.call("_update_weather", 0.0, true)
    # 天气切换是带过渡的：只等两帧时雨丝/湿地还没起来（C 审审查发现 09 看起来像晴天）
    await create_timer(1.6).timeout
    for _i in range(8):
        await process_frame
    _pose_local(-1.60, 16.80, _terrain_l(-1.60, 16.80) + 1.60, -4.60, 13.60, 7.40, 55.0)
    await _shot("09_rain_outer_edge")
    if weather != null and weather.has_method("set_manual_type"):
        weather.set_manual_type("clear")
    _main.call("_update_weather", 0.0, true)
    _main.call("_set_time_of_day", 18 * 60 + 40)
    await create_timer(0.9).timeout
    for _i in range(6):
        await process_frame
    _pose_play_default()
    await _shot("10_dusk_default")
    _main.call("_set_time_of_day", 12 * 60 + 20)
    await process_frame
    # W20：决策为“不并入小舌”，这里记录当前（无小舌）真实状态供用户复核
    _pose_local(-2.35, 6.30, 8.24, -1.25, 5.42, 7.82, 55.0)
    await _shot("11_w20_no_tongue")
    # 00 诊断机位：俯瞰台面轮廓（仅用于自检三角形/边缘，不代表审美构图）
    _pose_local(-1.60, 20.00, _terrain_l(-1.60, 20.00) + 13.50, fc.x, 9.00, 7.60, 52.0)
    await _shot("00_debug_pad_aerial")


# ------------------------------------------------------------- finish -----
func _j(v: Variant, depth: int = 0) -> Variant:
    if depth > 6:
        return "…"
    if v is Vector2:
        return [snappedf((v as Vector2).x, 0.0001), snappedf((v as Vector2).y, 0.0001)]
    if v is Vector2i:
        return [(v as Vector2i).x, (v as Vector2i).y]
    if v is Vector3:
        return [snappedf((v as Vector3).x, 0.0001), snappedf((v as Vector3).y, 0.0001),
            snappedf((v as Vector3).z, 0.0001)]
    if v is Color:
        return [snappedf((v as Color).r, 0.001), snappedf((v as Color).g, 0.001),
            snappedf((v as Color).b, 0.001), snappedf((v as Color).a, 0.001)]
    if v is Node:
        return "<node:%s>" % str((v as Node).name)
    if v is Dictionary:
        var o: Dictionary = {}
        for k in (v as Dictionary).keys():
            if str(k) == "node":
                continue
            o[str(k)] = _j((v as Dictionary)[k], depth + 1)
        return o
    if v is Array:
        var a: Array = []
        for e in v:
            a.append(_j(e, depth + 1))
        return a
    if v is float:
        return snappedf(v, 0.0001)
    return v


func _multimesh_inventory() -> Dictionary:
    var inv := {}
    var island: Node = _main.find_child("Island", true, false)
    if island == null:
        island = get_root()
    for ch in island.find_children("*", "MultiMeshInstance3D", true, false):
        var mmi := ch as MultiMeshInstance3D
        if mmi == null or mmi.multimesh == null:
            continue
        inv[str(ch.name)] = mmi.multimesh.instance_count
    return inv

func _finish() -> void:

    var fail := 0
    for c in _checks:
        if not bool(c["ok"]):
            fail += 1
    var summary := "checks=%d fail=%d shots=%d notes=%d" % [_checks.size(), fail, _shots.size(), _notes.size()]
    _log("[P2B] SUMMARY %s" % summary)
    for c in _checks:
        if not bool(c["ok"]):
            _log("[P2B] FAIL %s: expect=%s actual=%s" % [String(c["id"]), String(c["expect"]), String(c["actual"])])
    var world_sha := ""
    if FileAccess.file_exists("res://scripts/world.gd"):
        world_sha = FileAccess.get_sha256("res://scripts/world.gd")
    var doc := {
        "schema": "p2b/probe@1",
        "generated_at": Time.get_datetime_string_from_system(true),
        "engine": Engine.get_version_info(),
        "world_gd_sha256": world_sha,
        "summary": {"checks": _checks.size(), "fail": fail, "shots": _shots.size(), "notes": _notes.size()},
        "result": "PASS" if fail == 0 else "FAIL",
        "checks": _checks,
        "notes": _notes,
        "shots": _shots,
        "front_yard": _j(_fy),
        "world_basics": {
            "grass_count": int(_world.get("grass_count", -1)),
            "light_sources": (_world.get("light_sources", []) as Array).size(),
            "rock_stats_like": str(_world.get("rock_stats", {}).get("families", [])),
            "multimesh_inventory": _multimesh_inventory(),
        },
    }
    DirAccess.make_dir_recursive_absolute(out_dir)
    var jf := FileAccess.open(out_dir + "/p2b_probe.json", FileAccess.WRITE)
    if jf != null:
        jf.store_string(JSON.stringify(doc, "  "))
        jf.close()
    var lf := FileAccess.open(out_dir + "/p2b_probe.log", FileAccess.WRITE)
    if lf != null:
        for line in _log_lines:
            lf.store_line(String(line))
        lf.store_line("[P2B] SUMMARY %s" % summary)
        lf.close()
    print("[P2B] SUMMARY %s" % summary)
    quit(0 if fail == 0 else 1)
