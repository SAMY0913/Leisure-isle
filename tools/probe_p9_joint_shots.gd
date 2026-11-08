extends SceneTree
## P9 / P7 —— 农田巡田 × 岛民钓鱼 联合真实窗口探针（跨玩法交界，真实帧 + 真实 HUD 入口）。
##
## 运行方式（必须真实窗口，不能 --headless）：
##   ENG --path GAME --script res://tools/probe_p9_joint_shots.gd -- --out=D:/休闲小岛幻境/开发产物/P9/P7/after/joint_window
## 解析自检（无 GPU 也可跑，只验证脚本能解析）：
##   ENG --headless --path GAME --script res://tools/probe_p9_joint_shots.gd -- --parse-only --out=...
##
## 纪律：
## - 全部通过正式入口驱动：main._update_farm_patrol 自然 08:00 启动巡田；HUD press_fishing_button() 触发钓鱼；真实帧推进。
## - 不直接写 _sim_seconds / 不直接写库存 / 不强制 phase；只做一次显式日期跳转（_jump_datetime，游戏内公开时间操作）以缩短等待。
## - 只把时间源设为 sim、day_length=86400，得到 1 模拟秒 = 1 现实秒的可读节奏（与 P4/P6 窗口探针一致）。

const SPOTS := preload("res://scripts/isle_villager_spots.gd")
const FISH := preload("res://scripts/isle_fish.gd")
const CAL := preload("res://scripts/isle_calendar.gd")

const DEFAULT_OUT := "D:/休闲小岛幻境/开发产物/P9/P7/after/joint_window"
const RIG_NAMES := ["Rod", "RodMesh", "Line", "Bobber", "BobberMesh", "Splash", "Ripple", "Catch", "Fish"]

var out_dir := DEFAULT_OUT
var parse_only := false

var _pass := 0
var _fail := 0
var _lines: Array = []
var _fail_names: Array = []
var _shots_fail := 0
var _shots: Array = []

var _main: Node = null
var _hud: Object = null
var _inv: Object = null
var _villager: Node = null
var _spot: Dictionary = {}

var _prev_rounds := 0
var _max_round_jump := 0


func _initialize() -> void:
    for a in OS.get_cmdline_user_args():
        var s: String = String(a)
        if s.begins_with("--out="):
            out_dir = s.substr(6).strip_edges().trim_suffix("/").trim_suffix("\\")
        elif s == "--parse-only":
            parse_only = true
    if parse_only:
        print("[P7JOINT][PARSE] script parsed OK")
        quit(0)
        return
    DirAccess.make_dir_recursive_absolute(out_dir)
    _run.call_deferred()


func _run() -> void:
    var banner := "[P7JOINT][WINDOW] out=%s godot=%s" % [out_dir, str(Engine.get_version_info().get("string", ""))]
    print(banner)
    _lines.append(banner)
    await _boot()
    if _fail == 0 and _villager != null:
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


func _await_frames(n: int) -> void:
    for i in range(n):
        await process_frame


func _wait_until(cond: Callable, max_frames: int, label: String) -> bool:
    for i in range(max_frames):
        if bool(cond.call()):
            return true
        await process_frame
    print("[P7JOINT][WINDOW] timeout waiting: %s" % label)
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
    var f := FileAccess.open("%s/probe_p9_joint_shots.log" % out_dir, FileAccess.WRITE)
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
        "max_round_jump": _max_round_jump,
    }
    var jf := FileAccess.open("%s/probe_p9_joint_shots.json" % out_dir, FileAccess.WRITE)
    if jf != null:
        jf.store_string(JSON.stringify(data, "  "))
        jf.close()


func _sim() -> float:
    return float(_main.get("_sim_seconds"))


func _villager_pos() -> Vector3:
    var d: Dictionary = _villager.call("debug_state") as Dictionary
    return d.get("pos", Vector3.ZERO) as Vector3


func _villager_state() -> String:
    var d: Dictionary = _villager.call("debug_state") as Dictionary
    return String(d.get("state", ""))


func _patrol_active() -> bool:
    return bool(_villager.call("farm_patrol_active"))


func _patrol_state() -> Dictionary:
    return _main.call("farm_patrol_state") as Dictionary


func _patrol_last() -> Dictionary:
    return _villager.call("farm_patrol_last") as Dictionary


func _fstate() -> Dictionary:
    return _villager.call("fishing_state") as Dictionary


func _fishing_active() -> bool:
    return bool(_villager.call("fishing_active"))


func _rounds() -> int:
    return int(_fstate().get("rounds", 0))


func _rig_info() -> Dictionary:
    var rig: Variant = _villager.get("_fish_rig")
    if rig == null:
        return {}
    return (rig as Node).call("debug_info") as Dictionary


func _fish_total() -> int:
    var total := 0
    for raw in FISH.all_ids():
        total += int(_inv.call("get_count", String(raw)))
    return total


func _inventory_total() -> int:
    return int(_inv.call("total_count"))


func _hud_fishing() -> Dictionary:
    return _hud.call("fishing_ui_state") as Dictionary


func _toast_text() -> String:
    var lbl: Variant = _hud.get("_toast")
    if lbl == null:
        return ""
    return String((lbl as Label).text)


func _count_nodes(n: Node) -> int:
    var total := 1
    for c in n.get_children():
        total += _count_nodes(c)
    return total


func _count_named(n: Node, names: Array) -> int:
    var total := 1 if String(n.name) in names else 0
    for c in n.get_children():
        total += _count_named(c, names)
    return total


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
    _main.call("_pose_look", p + Vector3(10.0, 8.0, 10.0), p + Vector3(0.0, 1.0, 0.0), 46.0)


func _focus_shore() -> void:
    if _spot.is_empty():
        _focus_villager()
        return
    var p: Vector3 = _spot.get("point", Vector3.ZERO) as Vector3
    var cp: Vector3 = _spot.get("cast_point", Vector3.ZERO) as Vector3
    var dir: Vector3 = _spot.get("cast_dir", Vector3(0, 0, -1)) as Vector3
    var tang := Vector3(-dir.z, 0.0, dir.x)
    var target := (p + cp) * 0.5 + Vector3(0.0, 0.55, 0.0)
    var eye := target + tang * 4.4 + Vector3(0.0, 1.5, 0.0) - dir * 1.0
    _main.call("_pose_look", eye, target, 52.0)


func _jump_to_clock(day_offset: int, hour: int, minute: int, second: int) -> void:
    var now := _sim()
    var today := int(floorf(now / 86400.0))
    var target := float((today + day_offset) * 86400 + hour * 3600 + minute * 60 + second)
    var parts: Dictionary = CAL.parts(target)
    _main.call("_jump_datetime", int(parts.get("year", 2026)), int(parts.get("month", 1)), int(parts.get("day", 1)), int(parts.get("hour", 0)), int(parts.get("minute", 0)), int(parts.get("second", 0)))


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
    _main.set("_time_source", "sim")
    _main.set("_realtime", false)
    var sets: Variant = _main.get("_settings")
    if sets is Dictionary:
        (sets as Dictionary)["time_source"] = "sim"
    _main.set("_day_length", 86400.0)
    # 07:59:40 -- 等待约 20 秒真实时间即可自然跨过 08:00，由正式调度器启动巡田。
    _jump_to_clock(0, 7, 59, 40)
    await _await_frames(2)
    _force_weather("clear")
    _main.set("_paused", false)
    _main.set("_started", true)
    if _main.has_method("_enter_playing"):
        _main.call("_enter_playing")
    _main.set("_mode", 1)
    _main.set_process(true)
    await _await_frames(30)
    var menu: Variant = _main.get("_menu")
    if menu != null and bool((menu as Node).get("visible")):
        (menu as Node).call("close")
        await _wait_until(func() -> bool: return not bool((menu as Node).get("visible")), 600, "menu close")
    _hud.call("set_hud_visible", true, false)
    await _await_frames(4)
    _check("env.no_patrol_yet", not _patrol_active(), "08:00 前无巡田", str(_patrol_active()))
    var g: Dictionary = _villager.get("graph") as Dictionary
    _spot = SPOTS.fishing_spot(g)
    _check("env.spot_ready", not _spot.is_empty(), "钓位数据存在", str(_spot))
    var vp: Vector2 = Vector2(root.size)
    _check("env.viewport", vp.x >= 1280.0 and vp.y >= 720.0, ">=1280x720", str(vp))
    _check_eq("env.clock_morning", int(floorf(fposmod(_sim(), 86400.0) / 3600.0)), 7)


# ---------------------------------------------------------------- window ----

func _window_run() -> void:
    var fish_before := _fish_total()

    _section("1. 08:00 调度器自然启动巡田")
    _focus_villager()
    await _await_frames(4)
    var started := await _wait_until(func() -> bool: return _patrol_active(), 5000, "patrol start")
    _check("win.patrol_started", started, "08:00 后巡田启动", str(started))
    if not started:
        return
    var ps1 := _patrol_state()
    _check("win.phase_running", String(ps1.get("phase", "")) in ["running", "starting", "returning"], "running/starting/returning", str(ps1.get("phase", "")))
    await _wait_until(func() -> bool: return _villager_state() == "WALK", 1200, "patrol walking")
    _focus_villager()
    await _await_frames(4)
    await _shot("01_patrol_walking")

    _section("2. 巡田中点击钓鱼：活动仲裁拒绝，不产生第二套移动")
    var walk_before := _villager_state()
    _hud.call("press_fishing_button")
    await _await_frames(3)
    _check("win.fishing_refused", not _fishing_active(), "仍在巡田", str(_fishing_active()))
    _check("win.refuse_toast", _toast_text().contains("巡田"), "提示岛民正在巡田", _toast_text())
    _check("win.no_rig_on_refuse", (_rig_info().get("line_visible", false) == false), "钓具未出现", str(_rig_info().get("line_visible", null)))
    _check("win.villager_still_patrol", _patrol_active(), "巡田未被接管", str(_patrol_active()))
    await _shot("02_fishing_refused_by_patrol")

    _section("3. 巡田自然完成（九格全处理）")
    var finished := await _wait_until(func() -> bool: return not _patrol_active(), 9000, "patrol finish")
    _check("win.patrol_finished", finished, "巡田结束", str(finished))
    await _await_frames(4)
    var ps2 := _patrol_state()
    _check("win.phase_completed", String(ps2.get("phase", "")) == "completed", "completed", str(ps2.get("phase", "")))
    var last2 := ps2.get("last", {}) as Dictionary
    _check("win.patrol_outcome", String(last2.get("outcome", "")) == "done", "done", str(last2.get("outcome", "")))
    var results2: Variant = last2.get("results", [])
    _check_eq("win.patrol_9_slots", (results2 as Array).size() if results2 is Array else -1, 9)
    _focus_villager()
    await _await_frames(4)
    await _shot("03_patrol_completed")

    _section("4. 巡田结束后由玩家启动钓鱼，真实走到岸边")
    _hud.call("press_fishing_button")
    await _await_frames(2)
    _check("win.fishing_start_ok", _fishing_active(), "钓鱼已启动", str(_fishing_active()))
    var walking := await _wait_until(func() -> bool: return String(_fstate().get("phase", "")) == "walking", 6000, "fishing walking")
    _check("win.fishing_walking", walking, "walking", str(_fstate().get("phase", "")))
    await _shot("04_fishing_walking_from_farm")
    var waiting := await _wait_until(func() -> bool: return String(_fstate().get("phase", "")) == "waiting", 9000, "fishing waiting")
    _check("win.fishing_waiting", waiting, "waiting", str(_fstate().get("phase", "")))
    _focus_shore()
    await _await_frames(4)
    await _shot("05_fishing_waiting_at_shore")

    _section("5. 咬钩收线鱼获展示：每轮恰好入账一次")
    var rounds0 := _rounds()
    _prev_rounds = rounds0
    var caught := await _wait_until(func() -> bool: return _rounds() > rounds0, 6000, "catch commit")
    _check("win.catch_committed", caught, "rounds+1", str(_rounds()))
    await _await_frames(2)
    await _shot("06_fishing_catch_reveal")
    var fish_delta := _fish_total() - fish_before
    _check_eq("win.catch_inventory_delta", fish_delta, 1)
    var rounds_delta := _rounds() - rounds0
    _check_eq("win.rounds_delta_one", rounds_delta, 1)
    var catches: Variant = _fstate().get("catches", [])
    var catch_count := (catches as Array).size() if catches is Array else -1
    _check_eq("win.catch_records_one", catch_count, rounds0 + 1)

    _section("6. 玩家停止钓鱼：已提交鱼获保留、钓具与状态清理")
    await _await_frames(10)
    _hud.call("press_fishing_button")
    var stopped := await _wait_until(func() -> bool: return not _fishing_active(), 1800, "fishing stop")
    _check("win.fishing_stopped", stopped, "停止成功", str(stopped))
    # HUD 在下一帧 _update_ui 才把按钮刷回「钓鱼」，等 3 帧再读只读视图。
    await _await_frames(3)
    var lasts := _villager.call("fishing_last") as Dictionary
    _check_eq("win.stop_reason", String(lasts.get("reason", "")), "player_stop")
    _check_eq("win.catch_kept_after_stop", _fish_total() - fish_before, 1)
    var rig6 := _rig_info()
    _check("win.rig_line_hidden", rig6.get("line_visible", true) == false, "false", str(rig6.get("line_visible", null)))
    _check("win.rig_bobber_hidden", rig6.get("bobber_visible", true) == false, "false", str(rig6.get("bobber_visible", null)))
    _check("win.rig_catch_hidden", rig6.get("catch_visible", true) == false, "false", str(rig6.get("catch_visible", null)))
    var ui6 := _hud_fishing()
    _check_eq("win.pill_back", String(ui6.get("text", "")), "钓鱼")
    _focus_villager()
    await _await_frames(4)
    await _shot("07_after_fishing_stop_cleaned")

    _section("7. 次日 08:00 巡田恢复（钓鱼后不破坏农田调度）")
    var nodes_mid := _count_nodes(_villager)
    var rig_named_mid := _count_named(_villager, RIG_NAMES)
    _check_eq("win.rig_singleton_after_first_fishing", rig_named_mid, 9)
    _jump_to_clock(1, 7, 59, 40)
    await _await_frames(6)
    var sc_before := int(_patrol_state().get("start_count", 0))
    var next_started := await _wait_until(func() -> bool: return _patrol_active(), 5000, "next day patrol start")
    _check("win.next_day_patrol_started", next_started, "次日巡田启动", str(next_started))
    _check_eq("win.start_count_incremented", int(_patrol_state().get("start_count", 0)), sc_before + 1)
    _focus_villager()
    await _await_frames(4)
    await _shot("08_patrol_next_day_after_fishing")
    _villager.call("cancel_farm_patrol", "probe_cleanup")
    await _await_frames(6)

    _section("8. 联合循环后的资源与数据对账")
    _check("win.no_leftover_fishing", not _fishing_active(), "钓鱼已结束", str(_fishing_active()))
    _check("win.no_leftover_patrol", not _patrol_active(), "巡田已结束", str(_patrol_active()))
    _check_eq("win.nodes_stable", _count_nodes(_villager), nodes_mid)
    _check_eq("win.rig_nodes_stable", _count_named(_villager, RIG_NAMES), rig_named_mid)
    var snap_after: Dictionary = _inv.call("item_snapshot") as Dictionary
    var negative := 0
    for k in snap_after.keys():
        if int(snap_after[k]) < 0:
            negative += 1
    _check_eq("win.inventory_non_negative", negative, 0)
    _check_eq("win.fish_total_final", _fish_total() - fish_before, 1)
    _check("win.time_morning_next_day", int(floorf(fposmod(_sim(), 86400.0) / 3600.0)) >= 7, ">=7", str(int(floorf(fposmod(_sim(), 86400.0) / 3600.0))))
