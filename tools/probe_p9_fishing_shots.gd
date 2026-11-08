extends SceneTree
## P9 / P6 —— 钓鱼真实窗口探针：正式主游戏 + 真实 HUD 按钮 + 真实窗口截图。
##
## 运行方式（必须真实窗口，不能 --headless）：
##   ENG --path GAME --script res://tools/probe_p9_fishing_shots.gd -- --out=D:/休闲小岛幻境/开发产物/P9/P6/r3_window
## 解析自检（无 GPU 也可跑，只验证脚本能解析）：
##   ENG --headless --path GAME --script res://tools/probe_p9_fishing_shots.gd -- --parse-only --out=...
##
## 纪律：
## - 驱动正式生产入口：HUD press_fishing_button() → main._on_fishing_toggle → villager.begin_fishing。
## - 不改 _sim_seconds、不直接写库存、不强制 phase/caught，只读状态并截图。
## - 只把时间源设为 sim、day_length=86400 以获得 1 sim 秒 = 1 现实秒的可读时长（与 P4/P5 窗口探针一致）。

const SPOTS := preload("res://scripts/isle_villager_spots.gd")
const FISH := preload("res://scripts/isle_fish.gd")

const DEFAULT_OUT := "D:/休闲小岛幻境/开发产物/P9/P6/r3_window"
const BASE_Y := 2026
const BASE_M := 10
const BASE_D := 24

var out_dir := DEFAULT_OUT
var parse_only := false

var _pass := 0
var _fail := 0
var _lines: Array = []
var _fail_names: Array = []
var _shots_fail := 0

var _main: Node = null
var _hud: Object = null
var _inv: Object = null
var _villager: Node = null
var _spot: Dictionary = {}

var _walk_max_step := 0.0
var _walk_max_speed := 0.0
var _walk_big: Array = []
var _walk_last_ms := 0
var _walk_frames := 0
var _walk_feel := 0.0
var _splash_after_cast := 0
var _round1_feel := 0.0
var _shots: Array = []


func _initialize() -> void:
    _parse_args()
    if parse_only:
        print("[P6FISH][PARSE] script parsed OK")
        quit(0)
        return
    DirAccess.make_dir_recursive_absolute(out_dir)
    _run.call_deferred()


func _parse_args() -> void:
    for a in OS.get_cmdline_user_args():
        var s: String = String(a)
        if s.begins_with("--out="):
            out_dir = s.substr(6).strip_edges().trim_suffix("/").trim_suffix("\\")
        elif s == "--parse-only":
            parse_only = true
    if out_dir == "":
        out_dir = DEFAULT_OUT


func _run() -> void:
    var banner := "[P6FISH][WINDOW] out=%s godot=%s" % [out_dir, str(Engine.get_version_info().get("string", ""))]
    print(banner)
    _lines.append(banner)
    await _boot()
    if _fail == 0 and _villager != null and not _spot.is_empty():
        await _window_run()
    _write_log()
    print("[SUMMARY] checks=%d fail=%d shots_fail=%d" % [_pass + _fail, _fail, _shots_fail])
    print("[RESULT] %s" % ("PASS" if _fail == 0 and _pass > 0 else "FAIL"))
    quit(0 if _fail == 0 and _pass > 0 else 1)


# ---------------------------------------------------------------- helpers ---

func _section(title: String) -> void:
    var line := "=== %s ===" % title
    print(line)
    _lines.append(line)


func _check(name: String, ok: bool, expected: String, actual: String) -> void:
    var line := ""
    if ok:
        _pass += 1
        line = "[CHECK] %s | expected=%s actual=%s | PASS" % [name, expected, actual]
    else:
        _fail += 1
        _fail_names.append(name)
        line = "[CHECK] %s | expected=%s actual=%s | FAIL" % [name, expected, actual]
    print(line)
    _lines.append(line)


func _check_eq(name: String, actual: Variant, expected: Variant) -> void:
    _check(name, actual == expected, str(expected), str(actual))


func _check_range(name: String, value: float, lo: float, hi: float) -> void:
    _check(name, value >= lo and value <= hi, "[%.2f..%.2f]" % [lo, hi], "%.3f" % value)


func _await_frames(n: int) -> void:
    for i in range(n):
        await process_frame


func _wait_until(cond: Callable, max_frames: int, label: String) -> bool:
    for i in range(max_frames):
        if bool(cond.call()):
            return true
        await process_frame
    print("[P6FISH][WINDOW] timeout waiting: %s" % label)
    return bool(cond.call())


func _shot(name: String) -> void:
    await RenderingServer.frame_post_draw
    var img: Image = root.get_texture().get_image()
    if img == null or img.get_width() <= 0:
        _shots_fail += 1
        _check("shot." + name, false, "非空 PNG", "empty image")
        return
    var dir := "%s/shots" % out_dir
    DirAccess.make_dir_recursive_absolute(dir)
    var path := "%s/%s.png" % [dir, name]
    var err := img.save_png(path)
    if err != OK:
        _shots_fail += 1
        _check("shot." + name, false, "PNG 保存成功", str(err))
        return
    _shots.append(path)
    print("[SHOT] %s %dx%d %s" % [name, img.get_width(), img.get_height(), path])


func _write_log() -> void:
    var f := FileAccess.open("%s/probe_p9_fishing_shots.log" % out_dir, FileAccess.WRITE)
    if f != null:
        for line in _lines:
            f.store_line(String(line))
        f.close()
    var data := {
        "pass": _pass,
        "fail": _fail,
        "fail_names": _fail_names,
        "shots_fail": _shots_fail,
        "shots": _shots,
    }
    var jf := FileAccess.open("%s/probe_p9_fishing_shots.json" % out_dir, FileAccess.WRITE)
    if jf != null:
        jf.store_string(JSON.stringify(data, "  "))
        jf.close()


func _sim() -> float:
    return float(_main.get("_sim_seconds"))


func _villager_pos() -> Vector3:
    var d: Dictionary = _villager.call("debug_state") as Dictionary
    return d.get("pos", Vector3.ZERO) as Vector3


func _villager_yaw() -> float:
    var d: Dictionary = _villager.call("debug_state") as Dictionary
    return float(d.get("yaw", 0.0))


func _phase() -> String:
    if _villager == null:
        return ""
    return String(_villager.call("fishing_phase"))


func _fstate() -> Dictionary:
    if _villager == null:
        return {}
    return _villager.call("fishing_state") as Dictionary


func _active() -> bool:
    return bool(_villager.call("fishing_active"))


func _rig_info() -> Dictionary:
    var rig: Variant = _villager.get("_fish_rig")
    if rig == null:
        return {}
    return (rig as Node).call("debug_info") as Dictionary


func _line_point_count(info: Dictionary) -> int:
    var points: Variant = info.get("line_points", null)
    if points is PackedVector3Array:
        return (points as PackedVector3Array).size()
    if points is Array:
        return (points as Array).size()
    return 0


func _bag_state() -> Dictionary:
    return _hud.call("bag_display_state") as Dictionary


func _bag_panel() -> Control:
    return _hud.get("_bag_panel") as Control


# P7.2：递归收集面板内所有 Label 文本，用于证明扁平列表里没有分组小标题。
func _collect_all_labels(node: Node, out: Array) -> void:
    if node == null:
        return
    if node is Label:
        out.append(String((node as Label).text))
    for child in node.get_children():
        _collect_all_labels(child, out)


func _count_fish(counts: Dictionary) -> int:
    var n := 0
    for raw in FISH.all_ids():
        n += int(counts.get(String(raw), 0))
    return n


func _fish_total() -> int:
    var total := 0
    for raw in FISH.all_ids():
        total += int(_inv.call("get_count", String(raw)))
    return total


func _hud_fishing() -> Dictionary:
    return _hud.call("fishing_ui_state") as Dictionary


func _force_weather(type_id: String) -> void:
    var wx: Object = _main.get("_weather")
    if wx == null:
        return
    var real := String({"rain": "mid_rain", "snow": "heavy_snow"}.get(type_id, type_id))
    wx.call("set_manual_type", real)
    wx.call("reset", _sim())
    _main.call("_update_weather", 0.0, true)


func _focus_villager() -> void:
    var p := _villager_pos()
    _main.call("_pose_look", p + Vector3(4.2, 2.2, 4.0), p + Vector3(0.0, 0.75, 0.0), 50.0)


func _focus_shore() -> void:
    var p: Vector3 = _spot.get("point", Vector3.ZERO) as Vector3
    var cp: Vector3 = _spot.get("cast_point", Vector3.ZERO) as Vector3
    var dir: Vector3 = _spot.get("cast_dir", Vector3(0, 0, -1)) as Vector3
    var tang := Vector3(-dir.z, 0.0, dir.x)
    var target := (p + cp) * 0.5 + Vector3(0.0, 0.55, 0.0)
    var eye := target + tang * 4.4 + Vector3(0.0, 1.5, 0.0) - dir * 1.0
    _main.call("_pose_look", eye, target, 52.0)


func _wide_shot() -> void:
    var p := _villager_pos()
    _main.call("_pose_look", p + Vector3(10.0, 8.0, 10.0), p + Vector3(0.0, 1.0, 0.0), 46.0)


# ---------------------------------------------------------------- boot ------

func _boot() -> void:
    _section("0. 正式场景启动（真实窗口）")
    var ps := load("res://isle.tscn") as PackedScene
    _check("env.scene_load", ps != null, "isle.tscn 可加载", str(ps != null))
    if ps == null:
        return
    _main = ps.instantiate()
    root.add_child(_main)
    await _await_frames(8)
    _hud = _main.get("_hud")
    _villager = _main.get("_villager") as Node
    _inv = _main.call("inventory")
    _check("env.hud", _hud != null, "HUD 存在", str(_hud))
    _check("env.villager", _villager != null, "岛民存在", str(_villager != null))
    _check("env.inventory", _inv != null, "共享库存存在", str(_inv != null))
    if _hud == null or _villager == null or _inv == null:
        return
    # 可读时长：1 模拟秒 = 1 现实秒（P4/P5 窗口探针同一做法）。
    _main.set("_time_source", "sim")
    _main.set("_realtime", false)
    var sets: Variant = _main.get("_settings")
    if sets is Dictionary:
        (sets as Dictionary)["time_source"] = "sim"
    _main.set("_day_length", 86400.0)
    _main.call("_jump_datetime", BASE_Y, BASE_M, BASE_D, 12, 0, 0)
    await _await_frames(2)
    _force_weather("clear")
    _main.set("_paused", false)
    _main.set("_started", true)
    if _main.has_method("_enter_playing"):
        _main.call("_enter_playing")
    # 先声明“当天巡田已处理”，避免进入 PLAYING 的第一帧自动启动 08:00 巡田，
    # 否则玩家点击钓鱼会被活动仲裁以 patrol_running 正确拒绝，窗口探针测不到钓鱼。
    _main.set("_patrol_handled_day", int(floorf(_sim() / 86400.0)))
    _main.set("_mode", 1)
    _main.set_process(true)
    await _await_frames(30)
    var menu: Variant = _main.get("_menu")
    if menu != null and bool((menu as Node).get("visible")):
        (menu as Node).call("close")
        await _wait_until(func() -> bool: return not bool((menu as Node).get("visible")), 600, "menu close")
    _hud.call("set_hud_visible", true, false)
    _main.set("_patrol_handled_day", int(floorf(_sim() / 86400.0)))
    if bool(_villager.call("farm_patrol_active")):
        _villager.call("cancel_farm_patrol", "probe_setup")
    await _await_frames(4)
    _check("env.no_farm_patrol", not bool(_villager.call("farm_patrol_active")), "岛民空闲", str(bool(_villager.call("farm_patrol_active"))))
    var g: Dictionary = _villager.get("graph") as Dictionary
    _spot = SPOTS.fishing_spot(g)
    _check("env.spot_ready", not _spot.is_empty(), "钓位数据存在", str(_spot))
    var vp: Vector2 = Vector2(root.size)
    _check("env.viewport", vp.x >= 1280.0 and vp.y >= 720.0, ">=1280x720", str(vp))
    _check_eq("env.fish_total_zero", _fish_total(), 0)


# ---------------------------------------------------------------- window ----

func _window_run() -> void:
    _section("1. 初始画面 + 钓鱼入口")
    _wide_shot()
    await _await_frames(6)
    await _shot("01_main_with_fishing_entry")
    var ui0 := _hud_fishing()
    _check_eq("win.pill_exists", bool(ui0.get("exists", false)), true)
    _check_eq("win.pill_idle_text", String(ui0.get("text", "")), "钓鱼")
    _check_eq("win.pill_idle_active", bool(ui0.get("active", false)), false)
    _check_eq("win.pill_no_overlap_time", bool(ui0.get("overlaps_time", true)), false)
    _check_eq("win.pill_no_overlap_weather", bool(ui0.get("overlaps_weather", true)), false)

    _section("1b. 背包只显示已获得物品（初始只有种子）")
    _hud.call("open_backpack")
    await _await_frames(6)
    var bag0 := _bag_state()
    var vis0: Array = bag0.get("visible_order", [])
    var cnt0: Dictionary = bag0.get("counts", {})
    var want0: Array = []
    for raw in bag0.get("order", []):
        if int(cnt0.get(String(raw), 0)) > 0:
            want0.append(String(raw))
    _check_eq("win.bag0.visible_order", want0, vis0)
    _check_eq("win.bag0.visible_count", want0.size(), int(bag0.get("visible_count", -1)))
    _check("win.bag0.no_zero_items", int(bag0.get("visible_count", -1)) == 5 and want0.size() == 5,
        "初始背包只显示 5 种种子（数量 0 不显示）", str(vis0))
    # P7.2：背包改为单一扁平列表（无分组标题），分类由次级菜单负责。
    var bag0_labels: Array = []
    _collect_all_labels(_bag_panel(), bag0_labels)
    var group_hit := ""
    for raw_l in bag0_labels:
        for gtitle in ["种子 · SEEDS", "作物 · CROPS", "鱼 · FISH"]:
            if String(raw_l).contains(String(gtitle)):
                group_hit = String(raw_l)
    _check("win.bag0.flat_no_groups",
        bool(bag0.get("flat", false)) and int(bag0.get("section_count", -1)) == 0 and group_hit == "",
        "扁平列表·无分组标题", "flat=%s group=%s" % [bag0.get("flat"), group_hit])
    await _shot("01b_bag_only_acquired_items")
    _hud.call("close_backpack")
    await _await_frames(4)

    _section("2. 点击按钮：岛民真实走向岸边")
    _hud.call("press_fishing_button")
    await _await_frames(3)
    _check_eq("win.start_active", _active(), true)
    if not _active():
        print("[P6FISH][WINDOW] start failed, fishing_state=%s patrol=%s last=%s"
            % [str(_villager.call("fishing_state")), str(_villager.call("farm_patrol_active")), str(_villager.call("fishing_last"))])
    _check_eq("win.start_phase_walking", _phase(), "walking")
    _check_eq("win.start_villager_walk_state", String((_villager.call("debug_state") as Dictionary).get("state", "")), "WALK")
    var ui1 := _hud_fishing()
    _check_eq("win.pill_active_text", String(ui1.get("text", "")), "停止钓鱼")
    _check_eq("win.fish_total_before", _fish_total(), 0)
    var walk_start := _villager_pos()
    var prev := walk_start
    var frames := 0
    var walk_shot := false
    var sim0 := _sim()
    _walk_last_ms = Time.get_ticks_msec()
    while _phase() == "walking" and frames < 6000:
        await process_frame
        frames += 1
        var pos := _villager_pos()
        var now_ms := Time.get_ticks_msec()
        var step_ms := maxi(now_ms - _walk_last_ms, 1)
        _walk_last_ms = now_ms
        var step := (pos - prev).length()
        var step_speed := step / (float(step_ms) / 1000.0)
        _walk_max_step = maxf(_walk_max_step, step)
        _walk_max_speed = maxf(_walk_max_speed, step_speed)
        if step > 0.20:
            _walk_big.append({"frame": frames, "step": step, "ms": step_ms,
                "speed": step_speed, "phase": _phase(), "pos": pos, "prev": prev})
        prev = pos
        if not walk_shot and (pos - walk_start).length() > 8.0:
            walk_shot = true
            _focus_villager()
            await _await_frames(2)
            await _shot("02_walk_to_shore")
            # 截图/对焦会跨多帧，不能把这些帧的位移当成"单帧瞬移"，重置采样基准。
            prev = _villager_pos()
            _walk_last_ms = Time.get_ticks_msec()
    _walk_frames = frames
    _walk_feel = _sim() - sim0
    _check("win.walk_finished", _phase() != "walking" and _active(), "arrived", _phase())
    # 连续性判据：岛民每帧位移上限 = min(dt,0.10)*WALK_SPEED ≈ 0.105 m；
    # 瞬移会在单帧产生远大于该值的位移。速率(max_speed)受帧率抖动影响，仅作参考打印。
    _check("win.walk_no_teleport", _walk_max_step <= 0.15, "<=0.15 m/帧", "%.4f" % _walk_max_step)
    _check_range("win.walk_feel", _walk_feel, 10.0, 60.0)
    print("[P6FISH][WINDOW] walk frames=%d feel=%.2fs max_step=%.4f max_speed=%.3f big_steps=%d"
        % [frames, _walk_feel, _walk_max_step, _walk_max_speed, _walk_big.size()])

    _section("3. 抵达岸边并面向水域")
    var p_now := _villager_pos()
    var p_spot: Vector3 = _spot.get("point", Vector3.ZERO) as Vector3
    var arrive_err := (p_now - p_spot).length()
    _check("win.arrive_pos", arrive_err <= 0.12, "<=0.12", "%.3f" % arrive_err)
    var face_yaw := float(_spot.get("face_yaw", 0.0))
    var yaw_err := absf(angle_difference(_villager_yaw(), face_yaw))
    _check("win.arrive_yaw", yaw_err <= 0.05, "<=0.05", "%.4f" % yaw_err)
    _check_eq("win.arrive_phase_casting", _phase(), "casting")
    _focus_shore()
    await _await_frames(3)
    await _shot("03_arrived_facing_water")

    _section("4. 抛竿：真实挥杆（后摆→前甩）+ 鱼线/浮漂落水")
    var cast_back_shot := false
    var cast_whip_shot := false
    var pitch_back_max := -9.0
    var pitch_whip_min := 9.0
    var cast_frames := 0
    while _phase() == "casting" and _active() and cast_frames < 300:
        await process_frame
        cast_frames += 1
        var ri_c := _rig_info()
        var pp := float(ri_c.get("rod_pose_pitch", 0.0))
        pitch_back_max = maxf(pitch_back_max, pp)
        pitch_whip_min = minf(pitch_whip_min, pp)
        if not cast_back_shot and pp > 0.45:
            cast_back_shot = true
            _main.set("_paused", true)
            await _await_frames(3)
            await _shot("04a_cast_backswing")
            _main.set("_paused", false)
        elif not cast_whip_shot and pp < -0.30:
            cast_whip_shot = true
            _main.set("_paused", true)
            await _await_frames(3)
            await _shot("04b_cast_whip")
            _main.set("_paused", false)
        if cast_back_shot and cast_whip_shot:
            break
    _check("win.cast_backswing_pose", pitch_back_max > 0.45, ">0.45", "%.3f" % pitch_back_max)
    _check("win.cast_whip_pose", pitch_whip_min < -0.30, "<-0.30", "%.3f" % pitch_whip_min)
    await _shot("04_casting")
    var reaching := await _wait_until(func() -> bool: return _phase() == "waiting" or not _active(), 300, "cast->waiting")
    _check("win.cast_done", reaching and _phase() == "waiting", "waiting", _phase())
    await _await_frames(2)
    # 抛竿弧线在 1.2 s 内落水；等落水水花事件出现（而不是只看高度，弧线末端会先低于水面阈值）。
    var landed := await _wait_until(func() -> bool:
        var ri: Dictionary = _rig_info()
        if not bool(ri.get("bobber_visible", false)):
            return not _active()
        return int(ri.get("splash_events", 0)) >= 1, 240, "bobber landing splash")
    _check("win.bobber_landed", landed and _active() and _phase() == "waiting", "落水且仍在等待", str(landed))
    for big in _walk_big:
        print("[P6FISH][WINDOW] big_step %s" % str(big))
    var info_cast := _rig_info()
    _splash_after_cast = int(info_cast.get("splash_events", 0))
    _check("win.cast_splash", _splash_after_cast >= 1, ">=1 水花", str(_splash_after_cast))
    _check_eq("win.rod_visible", bool(info_cast.get("rod_visible", false)), true)
    _check_eq("win.line_visible", bool(info_cast.get("line_visible", false)), true)
    var lp_count := _line_point_count(info_cast)
    _check("win.line_points", lp_count >= 2, ">=2", str(lp_count))
    _check_eq("win.bobber_visible", bool(info_cast.get("bobber_visible", false)), true)
    var bob := info_cast.get("bobber_world", Vector3.ZERO) as Vector3
    var cp := _spot.get("cast_point", Vector3.ZERO) as Vector3
    _check("win.bobber_on_water", bool(info_cast.get("bobber_visible", false)) and absf(bob.y) <= 0.06,
        "可见且 |y|<=0.06", "visible=%s y=%.3f" % [str(info_cast.get("bobber_visible", false)), bob.y])
    var off := Vector2(bob.x - cp.x, bob.z - cp.z).length()
    _check("win.bobber_at_cast", off <= 0.25, "<=0.25", "%.3f" % off)
    print("[P6FISH][WINDOW] cast bobber=%s cast_point=%s line_points=%d" % [str(bob), str(cp), lp_count])
    await _shot("05_line_and_bobber")

    _section("5. 等待咬钩：自然持竿姿态")
    await _await_frames(30)
    var wd := float(_fstate().get("wait_dur", 0.0))
    _check("win.wait_dur_range", (wd >= 5.99 and wd <= 16.01) or (wd >= 17.99 and wd <= 24.01), "6-16|18-24", "%.2f" % wd)
    _check_eq("win.wait_phase", _phase(), "waiting")
    var clip_name := String((_villager.call("debug_state") as Dictionary).get("clip", ""))
    _check_eq("win.wait_clip", clip_name, "fish_hold")
    var ui2 := _hud_fishing()
    _check_eq("win.hud_waiting_status", String(ui2.get("status_text", "")).begins_with("等待咬钩"), true)
    await _shot("06_waiting_pose")

    _section("6. 浮漂试探 / 下沉 / 水花")
    var nib_seen := false
    for i in range(1600):
        await process_frame
        if _phase() != "waiting":
            break
        var ri := _rig_info()
        if bool(ri.get("nibble_active", false)):
            nib_seen = true
            var amp := float(ri.get("nibble_amp", 0.0))
            _check("win.nibble_strength", amp >= 0.30 and amp <= 0.65, "0.30..0.65", "%.3f" % amp)
            await _shot("07_bobber_nibble")
            break
    _check("win.nibble_seen", nib_seen, "nibble_active=true", str(nib_seen))
    var bite_ok := await _wait_until(func() -> bool: return _phase() == "bite" or not _active(), 2400, "bite")
    _check("win.bite_phase", bite_ok and _phase() == "bite", "bite", _phase())
    var splash_before := int(_rig_info().get("splash_events", 0))
    await _await_frames(3)
    var ri_bite := _rig_info()
    var splash_bite := int(ri_bite.get("splash_events", 0))
    _check("win.bite_splash", splash_bite >= _splash_after_cast + 1, "落水基础上 +1 水花",
        "%d -> %d (落水=%d)" % [splash_before, splash_bite, _splash_after_cast])
    _check_eq("win.bite_ripple", bool(ri_bite.get("ripple_visible", false)), true)
    var bite_y := (ri_bite.get("bobber_world", Vector3.ZERO) as Vector3).y
    _check("win.bite_sink", bite_y <= -0.03, "<=-0.03", "%.3f" % bite_y)
    await _shot("08_bite_sink_splash")

    _section("7. 自动收线 + 鱼获展示")
    var reel_ok := await _wait_until(func() -> bool: return _phase() == "reeling" or not _active(), 200, "reeling")
    _check("win.reel_phase", reel_ok and _phase() == "reeling", "reeling", _phase())
    var reel_lift_shot := false
    var reel_lift_max := -9.0
    var reel_frames := 0
    while _phase() == "reeling" and _active() and reel_frames < 240:
        await process_frame
        reel_frames += 1
        var pp_r := float((_rig_info()).get("rod_pose_pitch", 0.0))
        reel_lift_max = maxf(reel_lift_max, pp_r)
        if not reel_lift_shot and pp_r > 0.45:
            reel_lift_shot = true
            _main.set("_paused", true)
            await _await_frames(3)
            await _shot("09a_reel_lift")
            _main.set("_paused", false)
    _check("win.reel_lift_pose", reel_lift_max > 0.45, ">0.45", "%.3f" % reel_lift_max)
    await _shot("09_reeling")
    var reveal_ok := await _wait_until(func() -> bool: return _phase() == "reveal" or not _active(), 300, "reveal")
    _check("win.reveal_phase", reveal_ok and _phase() == "reveal", "reveal", _phase())
    await _await_frames(2)
    var ri_rev := _rig_info()
    _check_eq("win.catch_visible", bool(ri_rev.get("catch_visible", false)), true)
    _check_eq("win.catch_fish_known", FISH.has_fish(String(ri_rev.get("fish_id", ""))), true)
    var catches: Array = _fstate().get("catches", []) as Array
    _check_eq("win.catch_event_1", catches.size(), 1)
    _check_eq("win.inventory_after_1", _fish_total(), 1)
    if not catches.is_empty():
        var c0: Dictionary = catches[0] as Dictionary
        _check_eq("win.catch_inventory_match", int(_inv.call("get_count", String(c0.get("fish_id", "")))), 1)
        print("[P6FISH][WINDOW] catch#1 %s size=%.2f" % [String(c0.get("display_name", "")), float(c0.get("size", 0.0))])
    await _shot("10_catch_reveal")
    _round1_feel = _sim() - (sim0 + _walk_feel)

    _section("8. 背包中的真实鱼获")
    await _await_frames(6)
    _hud.call("open_backpack")
    await _await_frames(8)
    # 一键整理后再核对：排序顺序是此处的验收对象，默认网格顺序不代表玩家整理后的顺序。
    _hud.call("sort_backpack")
    await _await_frames(4)
    var bag := _bag_state()
    var order: Array = bag.get("order", [])
    var counts: Dictionary = bag.get("counts", {})
    _check_eq("win.bag_open", bool(bag.get("open", false)), true)
    _check_eq("win.bag_item_count", order.size(), 16)
    _check_eq("win.bag_sorted", bool(bag.get("sorted", false)), true)
    var fish_ids: Array = FISH.all_ids()
    var bag_fish_total := 0
    for raw_fish in fish_ids:
        bag_fish_total += int(counts.get(String(raw_fish), 0))
    _check_eq("win.bag_fish_counts_match", bag_fish_total, _fish_total())
    # P7-UX：真实窗口背包只显示已获得物品（种子 + 已钓鱼种），未获得不显示 ×0。
    var want_vis: Array = []
    for raw_v in order:
        if int(counts.get(String(raw_v), 0)) > 0:
            want_vis.append(String(raw_v))
    _check_eq("win.bag_visible_order", want_vis, bag.get("visible_order", []))
    _check_eq("win.bag_visible_count", want_vis.size(), int(bag.get("visible_count", -1)))
    _check("win.bag_only_acquired", want_vis.size() < 16 and bool(bag.get("flat", false)),
        "只显示已获得（种子+鱼），其余不出现", str(bag.get("visible_order", [])))
    var fish_visible := false
    for raw_fv in (bag.get("visible_order", []) as Array):
        if String(raw_fv).begins_with("fish_"):
            fish_visible = true
    _check("win.bag_fish_visible", fish_visible, "钓到鱼后鱼出现在扁平列表", str(bag.get("visible_order", [])))
    # P7.2：次级分类菜单在真实窗口下可用（只改显示，不改数量）。
    var fish_counts0: Dictionary = bag.get("counts", {})
    _hud.call("toggle_bag_filter_menu")
    await _await_frames(3)
    _check_eq("win.bag_filter_menu_open", bool((_bag_state().get("filter_menu_open", false))), true)
    _hud.call("set_bag_filter", "fish")
    await _await_frames(4)
    var bag_f := _bag_state()
    var only_fish := true
    for raw_of in (bag_f.get("visible_order", []) as Array):
        if not String(raw_of).begins_with("fish_"):
            only_fish = false
    _check("win.bag_filter_fish_only",
        String(bag_f.get("filter", "")) == "fish" and only_fish
            and int(bag_f.get("visible_count", -1)) == _count_fish(bag_f.get("counts", {})),
        "分类=鱼时只显示鱼", str(bag_f.get("visible_order", [])))
    await _shot("11b_bag_filter_fish")
    _hud.call("set_bag_filter", "all")
    _hud.call("toggle_bag_filter_menu")
    await _await_frames(4)
    _check_eq("win.bag_filter_back_to_all", _bag_state().get("filter", ""), "all")
    _check_eq("win.bag_filter_counts_unchanged", fish_counts0, bag.get("counts", {}))
    var fish_last := true
    for i in range(fish_ids.size()):
        var want: String = String(fish_ids[i])
        var got: String = String(order[order.size() - fish_ids.size() + i]) if order.size() >= fish_ids.size() else ""
        if got != want:
            fish_last = false
    _check("win.bag_fish_last", fish_last, "鱼类最后", str(order.slice(maxi(order.size() - 6, 0), order.size())))
    await _shot("11_backpack_with_catch")
    _hud.call("close_backpack")
    await _await_frames(4)

    _section("9. 自动下一轮（持续循环）")
    var loop_ok := await _wait_until(func() -> bool: return (not _active()) or (int(_fstate().get("rounds", 0)) >= 2 and _phase() == "waiting"), 3600, "round2")
    _check("win.round2_waiting", loop_ok and _active() and int(_fstate().get("rounds", 0)) >= 2, "rounds>=2 waiting", str(int(_fstate().get("rounds", 0))) + "/" + _phase())
    if not _active():
        _check("win.round2_abort", false, "still active", "inactive")
    else:
        _focus_shore()
        await _await_frames(4)
        var info2 := _rig_info()
        _check_eq("win.round2_bobber", bool(info2.get("bobber_visible", false)), true)
        await _shot("12_second_round_cast")
        _check_eq("win.rounds_two", int(_fstate().get("rounds", 0)), 2)

    _section("10. 玩家停止：活动结束与视觉清理")
    var fish_before := _fish_total()
    _hud.call("press_fishing_button")
    await _await_frames(4)
    _check_eq("win.stop_inactive", _active(), false)
    var last: Dictionary = _villager.call("fishing_last") as Dictionary
    _check_eq("win.stop_outcome", String(last.get("outcome", "")), "cancelled")
    _check_eq("win.stop_reason", String(last.get("reason", "")), "player_stop")
    await _await_frames(10)
    var ui3 := _hud_fishing()
    _check_eq("win.stop_pill_text", String(ui3.get("text", "")), "钓鱼")
    _check_eq("win.stop_pill_inactive", bool(ui3.get("active", false)), false)
    var ri_stop := _rig_info()
    _check("win.stop_rig_readable", ri_stop.has("rod_visible") and ri_stop.has("bobber_visible") and ri_stop.has("catch_visible"),
        "浮漂/鱼竿仍可读（未建即视为已隐藏）", str(ri_stop.keys()))
    _check_eq("win.stop_rod_hidden", bool(ri_stop.get("rod_visible", false)), false)
    _check_eq("win.stop_bobber_hidden", bool(ri_stop.get("bobber_visible", false)), false)
    _check_eq("win.stop_catch_hidden", bool(ri_stop.get("catch_visible", false)), false)
    var clip_after := String((_villager.call("debug_state") as Dictionary).get("clip", ""))
    _check("win.stop_not_fishing_clip", clip_after != "fish_hold" and clip_after != "fish_cast" and clip_after != "fish_reel", "idle clip", clip_after)
    await _shot("13_after_stop_cleaned")
    await _await_frames(120)
    _check_eq("win.stop_no_more_fish", _fish_total(), fish_before)
    print("[P6FISH][WINDOW] done rounds=%d fish=%d walk_feel=%.2f round1_feel=%.2f" % [int(_fstate().get("rounds", 0)), _fish_total(), _walk_feel, _round1_feel])
