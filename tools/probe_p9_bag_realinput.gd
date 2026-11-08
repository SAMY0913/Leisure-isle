extends SceneTree
## P9 / P7.2 —— 背包 B 键「真实系统键盘」复现探针（真实窗口 + 外部 SendKeys 注入）。
##
## 背景：用户反馈「按 B 打不开背包」。合成事件（Input.parse_input_event）路径在旧探针里是通过的，
## 因此这里不再合成按键，而是把游戏窗口跑起来，由外部 PowerShell 通过 Windows 消息队列发送真实按键，
## 游戏内只做观测：每帧记录 hud.backpack_open() / _bag_panel.visible / 面板矩形，并定时截图。
##
## 运行（必须真实窗口，不能 --headless）：
##   ENG --path GAME --script res://tools/probe_p9_bag_realinput.gd -- --out=<dir> --frames=2700
##
## 外部注入示例（PowerShell）：
##   $p = Get-Process Godot_v4.7.2-stable_win64_console | Where-Object {$_.MainWindowHandle -ne 0} | Select-Object -First 1
##   [Win32]::SetForegroundWindow($p.MainWindowHandle); [System.Windows.Forms.SendKeys]::SendWait("b")

var out_dir := "D:/休闲小岛幻境/开发产物/P9/P7/after/p72/bag_realinput"
var total_frames := 2700
var parse_only := false

var _pass := 0
var _fail := 0
var _lines: Array = []
var _fail_names: Array = []

var _main: Node = null
var _hud: Object = null
var _bag_open := false
var _transitions: Array = []
var _frame := 0


func _initialize() -> void:
    for a in OS.get_cmdline_user_args():
        var s: String = String(a)
        if s.begins_with("--out="):
            out_dir = s.substr(6).strip_edges().trim_suffix("/").trim_suffix("\\")
        elif s.begins_with("--frames="):
            total_frames = int(s.substr(9))
        elif s == "--parse-only":
            parse_only = true
    if parse_only:
        print("[P7BAGKEY][PARSE] script parsed OK")
        quit(0)
        return
    DirAccess.make_dir_recursive_absolute(out_dir)
    _run.call_deferred()


func _log(line: String) -> void:
    print(line)
    _lines.append(line)


func _check(name: String, ok: bool, expected: String, actual: String) -> void:
    if ok:
        _pass += 1
        _log("[CHECK] %s | expected=%s actual=%s | PASS" % [name, expected, actual])
    else:
        _fail += 1
        _fail_names.append(name)
        _log("[CHECK] %s | expected=%s actual=%s | FAIL" % [name, expected, actual])


func _await_frames(n: int) -> void:
    for i in range(n):
        await process_frame


func _shot(name: String) -> void:
    await RenderingServer.frame_post_draw
    var img: Image = root.get_texture().get_image()
    if img == null or img.get_width() <= 0:
        _log("[SHOT-FAIL] %s empty" % name)
        return
    var dir := "%s/shots" % out_dir
    DirAccess.make_dir_recursive_absolute(dir)
    var path := "%s/%s.png" % [dir, name]
    img.save_png(path)
    _log("[SHOT] %s %dx%d %s" % [name, img.get_width(), img.get_height(), path])


func _bag_state() -> Dictionary:
    if _hud == null:
        return {}
    var st: Dictionary = _hud.call("bag_display_state") as Dictionary
    var lay: Dictionary = _hud.call("bag_layout_info") as Dictionary
    return {"open": bool(st.get("open", false)), "visible_count": int(st.get("visible_count", 0)),
        "order": st.get("order", []), "panel_on_screen": bool(lay.get("panel_on_screen", false)),
        "panel_rect": lay.get("panel_rect", Rect2()), "hud_visible": bool(_hud.get("_visible_now"))}


func _run() -> void:
    var banner := "[P7BAGKEY][WINDOW] out=%s godot=%s frames=%d" % [out_dir, str(Engine.get_version_info().get("string", "")), total_frames]
    _log(banner)
    await _boot()
    if _main != null and _hud != null:
        await _observe()
    _write_log()
    _log("[SUMMARY] checks=%d fail=%d" % [_pass + _fail, _fail])
    _log("[RESULT] %s" % ("PASS" if _fail == 0 and _pass > 0 else "FAIL"))
    quit(0 if _fail == 0 and _pass > 0 else 1)


func _boot() -> void:
    _log("=== 0. 正式场景启动（真实窗口，等待外部真实按键） ===")
    var ps := load("res://isle.tscn") as PackedScene
    if ps == null:
        _check("env.scene_load", false, "isle.tscn", "null")
        return
    _main = ps.instantiate()
    root.add_child(_main)
    await _await_frames(8)
    _hud = _main.get("_hud")
    if _hud == null:
        _check("env.hud", false, "HUD", "null")
        return
    _check("env.hud", true, "HUD", "ok")
    _main.set("_time_source", "sim")
    _main.set("_realtime", false)
    var sets: Variant = _main.get("_settings")
    if sets is Dictionary:
        (sets as Dictionary)["time_source"] = "sim"
    _main.set("_day_length", 86400.0)
    var cal := load("res://scripts/isle_calendar.gd")
    var now := float(_main.get("_sim_seconds"))
    var today := int(floorf(now / 86400.0))
    var target := float(today * 86400 + 12 * 3600)
    var parts: Dictionary = cal.parts(target)
    _main.call("_jump_datetime", int(parts.get("year", 2026)), int(parts.get("month", 1)), int(parts.get("day", 1)), 12, 0, 0)
    await _await_frames(2)
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
        await _await_frames(60)
    _hud.call("set_hud_visible", true, false)
    await _await_frames(4)
    var st := _bag_state()
    _log("[STATE] hud_visible=%s bag_open=%s visible_count=%d t=%.1f" % [str(st.get("hud_visible")), str(st.get("open")), int(st.get("visible_count", 0)), Time.get_unix_time_from_system()])
    _check("boot.bag_closed", not bool(st.get("open", true)), "背包初始关闭", str(st.get("open")))
    _check("boot.hud_visible", bool(st.get("hud_visible", false)), "HUD 可见", str(st.get("hud_visible")))
    _log("[REALKEY] READY t=%.1f 现在可以把窗口切到前台并发送真实 B 键（frames=%d）" % [Time.get_unix_time_from_system(), total_frames])
    await _shot("00_before_real_key")


func _observe() -> void:
    _log("=== 1. 观测真实按键导致的背包开合 ===")
    _bag_open = bool(_bag_state().get("open", false))
    for i in range(total_frames):
        _frame += 1
        var st := _bag_state()
        var now_open := bool(st.get("open", false))
        if now_open != _bag_open:
            _bag_open = now_open
            # P7.2：附墙钟时间戳，便于与外部注入脚本的按键时间对账（证明状态变化确实由真实按键触发）。
            var rec := {"frame": _frame, "t": Time.get_unix_time_from_system(), "open": now_open, "visible_count": int(st.get("visible_count", 0)),
                "panel_on_screen": bool(st.get("panel_on_screen", false)), "hud_visible": bool(st.get("hud_visible", false))}
            _transitions.append(rec)
            _log("[REALKEY] transition %s" % JSON.stringify(rec))
            if now_open:
                _shot_sync("01_real_key_open_frame%d" % _frame)
            else:
                _shot_sync("02_real_key_close_frame%d" % _frame)
        if i % 60 == 0:
            _log("[BEAT] frame=%d t=%.1f bag_open=%s hud=%s vc=%d" % [_frame, Time.get_unix_time_from_system(), str(now_open), str(st.get("hud_visible")), int(st.get("visible_count", 0))])
        await process_frame
    _log("[REALKEY] transitions=%d" % _transitions.size())
    if _transitions.size() >= 1:
        _check("real.open_once", bool((_transitions[0] as Dictionary).get("open", false)), "第一次真实 B 打开背包", str(_transitions[0]))
        _check("real.panel_on_screen", bool((_transitions[0] as Dictionary).get("panel_on_screen", false)), "面板在屏幕内", str(_transitions[0]))
        _check("real.hud_restored", bool((_transitions[0] as Dictionary).get("hud_visible", false)), "HUD 可见", str(_transitions[0]))
        _check("real.has_items", int((_transitions[0] as Dictionary).get("visible_count", 0)) > 0, ">0 可见物品", str((_transitions[0] as Dictionary).get("visible_count", 0)))
    else:
        _check("real.open_once", false, "真实 B 打开背包", "0 次状态变化（真实按键未到达游戏）")
    if _transitions.size() >= 2:
        _check("real.close_once", not bool((_transitions[1] as Dictionary).get("open", true)), "第二次真实 B 关闭背包", str(_transitions[1]))


func _shot_sync(name: String) -> void:
    _shot(name)


func _write_log() -> void:
    var f := FileAccess.open("%s/probe_p9_bag_realinput.log" % out_dir, FileAccess.WRITE)
    if f != null:
        for line in _lines:
            f.store_line(String(line))
        f.close()
    var jf := FileAccess.open("%s/probe_p9_bag_realinput.json" % out_dir, FileAccess.WRITE)
    if jf != null:
        jf.store_string(JSON.stringify({"pass": _pass, "fail": _fail, "fail_names": _fail_names, "transitions": _transitions}, "  "))
        jf.close()
