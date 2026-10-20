extends SceneTree

## T1 设置面板 / ESC 动画 / HUD 自动运镜 自动验收。
## headless 运行：console exe --headless --path 项目 --script res://tools/probe_menu6.gd
## 输出：D:/休闲小岛幻境/开发产物/logs/probe_menu6.log；退出码非 0 表示有 FAIL。

const MenuScript := preload("res://scripts/menu.gd")
const HudScript := preload("res://scripts/hud.gd")
const S := preload("res://scripts/isle_settings.gd")

const LOG_PATH := "D:/休闲小岛幻境/开发产物/logs/probe_menu6.log"

var _pass := 0
var _fail := 0
var _logs: Array = []

func _check(name: String, cond: bool, detail: String = "") -> void:
    if cond:
        _pass += 1
        _log("PASS  " + name + ("" if detail.is_empty() else "  [" + detail + "]"))
    else:
        _fail += 1
        _fail_names.append(name)
        _log("FAIL  " + name + ("" if detail.is_empty() else "  [" + detail + "]"))

var _fail_names: Array = []

func _log(s: String) -> void:
    print(s)
    _logs.append(s)

var _menu_vp: SubViewport
var _hud_vp: SubViewport

func _initialize() -> void:
    DirAccess.make_dir_recursive_absolute("D:/休闲小岛幻境/开发产物/logs")
    _log("=== probe_menu6 start ===")
    _menu_vp = SubViewport.new()
    _menu_vp.size = Vector2i(1280, 800)
    _menu_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
    root.add_child(_menu_vp)
    await process_frame
    var menu = MenuScript.new()
    _menu_vp.add_child(menu)
    await process_frame
    await process_frame
    menu._layout()
    await process_frame
    _log("viewport " + str(menu.get_viewport().get_visible_rect().size))
    _log("menu built items=%d sliders=%d setting_buttons=%d menu_buttons=%d" % [
        (menu.get("_items") as Array).size(),
        (menu.get("_sliders") as Dictionary).size(),
        (menu.get("_setting_buttons") as Dictionary).size(),
        (menu.get("_menu_buttons") as Array).size()])

    var start_emit := {"n": 0, "ret": false}
    menu.start_pressed.connect(func(r: bool) -> void:
        start_emit["n"] = int(start_emit["n"]) + 1
        start_emit["ret"] = r)

    await _test_anim(menu, start_emit)
    await _test_quality(menu)
    await _test_day_length(menu)
    await _test_volumes(menu)
    await _test_display_confirm(menu)
    await _test_layout(menu)
    await _test_hud_layout()
    await _test_title_close(menu)
    await _test_hud()

    _log("=====================================")
    _log("SUMMARY PASS=%d FAIL=%d" % [_pass, _fail])
    if _fail > 0:
        _log("FAILED: " + str(_fail_names))
    var f := FileAccess.open(LOG_PATH, FileAccess.WRITE)
    if f != null:
        f.store_string("\n".join(_logs) + "\n")
        f.close()
    print("PROBE_MENU6 PASS=%d FAIL=%d" % [_pass, _fail])
    quit(1 if _fail > 0 else 0)

func _items_at_home(menu) -> bool:
    var items: Array = menu.get("_items")
    var home: Array = menu.get("_items_home")
    if items.size() == 0 or home.size() != items.size():
        return false
    for i in items.size():
        if (items[i] as Control).position.distance_to(home[i]) > 0.5:
            return false
    return true

func _buttons_disabled(menu) -> bool:
    var btns: Array = menu.get("_menu_buttons")
    if btns.is_empty():
        return false
    for b in btns:
        if b is Button and not (b as Button).disabled:
            return false
    return true

func _buttons_enabled(menu) -> bool:
    for b in (menu.get("_menu_buttons") as Array):
        if b is Button and (b as Button).disabled:
            return false
    return true

func _test_anim(menu, start_emit: Dictionary) -> void:
    _log("--- ESC 菜单动画 ---")
    menu.set_settings({"time_source": "sim", "window_mode": "windowed"})
    await process_frame
    menu.open(true)
    await process_frame
    var total: float = float(menu.get("_anim_total"))
    _check("enter_state_enter", int(menu.get("_anim_state")) == 1, "state=%d" % int(menu.get("_anim_state")))
    _check("enter_total_le_0.9", total <= 0.9 and total >= 0.5, "total=%.3f" % total)
    _check("enter_buttons_blocked", _buttons_disabled(menu))
    var home: Array = menu.get("_items_home")
    var items: Array = menu.get("_items")
    _check("enter_items_8", items.size() == 8, "items=%d" % items.size())
    await create_timer(0.08).timeout
    var displaced := 0
    var max_disp := 0.0
    for i in items.size():
        var d: float = (items[i] as Control).position.distance_to(home[i]) if i < home.size() else 0.0
        max_disp = maxf(max_disp, d)
        if d > 40.0:
            displaced += 1
    _check("enter_starts_offscreen", displaced >= 3, "displaced=%d max=%.1f" % [displaced, max_disp])
    await create_timer(0.95).timeout
    _check("enter_done_idle", int(menu.get("_anim_state")) == 0)
    _check("enter_home_restored", _items_at_home(menu))
    _check("enter_buttons_enabled", _buttons_enabled(menu))
    _check("enter_menu_visible", bool(menu.get("menu_visible")))
    _check("enter_no_duplicate_emit", int(start_emit["n"]) == 0, "emit=%d" % int(start_emit["n"]))

    # 入场中途 ESC → 反向退出，结束后通知 main 恢复游玩（start_pressed(true)）。
    menu.open(true)
    await create_timer(0.20).timeout
    var t0: float = float(menu.get("_anim_t"))
    var ev := InputEventKey.new()
    ev.pressed = true
    ev.keycode = KEY_ESCAPE
    menu._input(ev)
    _check("reverse_state_exit", int(menu.get("_anim_state")) == 2, "state=%d" % int(menu.get("_anim_state")))
    var t1: float = float(menu.get("_anim_t"))
    await create_timer(0.05).timeout
    var t2: float = float(menu.get("_anim_t"))
    _check("reverse_monotonic", t2 <= t1 + 0.001 and t2 < t0 - 0.001, "t0=%.3f t1=%.3f t2=%.3f" % [t0, t1, t2])
    await create_timer(0.5).timeout
    _check("reverse_closed", not bool(menu.get("menu_visible")))
    _check("reverse_emit_resume", int(start_emit["n"]) == 1 and bool(start_emit["ret"]), "n=%d ret=%s" % [int(start_emit["n"]), str(start_emit["ret"])])

    # 反复快速开关不叠加、不重复回调。
    var before_emit := int(start_emit["n"])
    for k in 3:
        menu.open(true)
        await create_timer(0.03).timeout
        menu.close(Callable())
        await create_timer(0.03).timeout
    _check("rapid_no_extra_emit", int(start_emit["n"]) == before_emit, "emit=%d" % int(start_emit["n"]))
    menu.open(true)
    await create_timer(1.0).timeout
    _check("rapid_reopen_after_storm", bool(menu.get("menu_visible")) and int(menu.get("_anim_state")) == 0, "state=%d" % int(menu.get("_anim_state")))
    _check("rapid_home_restored", _items_at_home(menu))
    _check("rapid_buttons_enabled", _buttons_enabled(menu))
    menu.close(Callable())
    await create_timer(0.9).timeout
    _check("rapid_final_closed", not bool(menu.get("menu_visible")))
    _check("rapid_state_idle", int(menu.get("_anim_state")) == 0, "state=%d" % int(menu.get("_anim_state")))

func _test_quality(menu) -> void:
    _log("--- 画质五档 + 高级覆盖 ---")
    menu.set_settings({"quality": 4, "quality_overrides": {}})
    await process_frame
    var sliders: Dictionary = menu.get("_sliders")
    var labels: Dictionary = menu.get("_slider_value_labels")
    _check("quality_slider_exists", sliders.has("quality"))
    if not sliders.has("quality"):
        return
    _check("quality_tick_count_5", int((sliders["quality"] as Control).get("tick_count")) == 5, "ticks=%d" % int((sliders["quality"] as Control).get("tick_count")))
    _check("quality_label_4", str((labels["quality"] as Label).text).contains("极致"), str((labels["quality"] as Label).text))
    menu.set_settings({"quality_overrides": {"sea_ssr": false}})
    await process_frame
    _check("quality_custom_label", str((labels["quality"] as Label).text).contains("自定义"), str((labels["quality"] as Label).text))
    menu._on_slider_changed("quality", 2.0)
    var gs: Dictionary = menu.get_settings()
    _check("quality_reselect_clears_overrides", (gs["quality_overrides"] as Dictionary).is_empty() and int(gs["quality"]) == 2, str(gs["quality_overrides"]))

    var preset_v: bool = bool(S.quality_preset(2).get("sea_ssr", true))
    menu.set_settings({"quality": 2, "quality_overrides": {}})
    menu._cycle_override("sea_ssr")
    var ov1: Dictionary = menu.get_settings()["quality_overrides"]
    _check("override_cycle_1_negate", ov1.has("sea_ssr") and bool(ov1["sea_ssr"]) == (not preset_v), str(ov1))
    menu._cycle_override("sea_ssr")
    var ov2: Dictionary = menu.get_settings()["quality_overrides"]
    _check("override_cycle_2_preset", ov2.has("sea_ssr") and bool(ov2["sea_ssr"]) == preset_v, str(ov2))
    menu._cycle_override("sea_ssr")
    _check("override_cycle_3_none", (menu.get_settings()["quality_overrides"] as Dictionary).is_empty())
    menu.set_settings({"quality_overrides": {"posts_ao": false}})
    var ov_alias: Dictionary = menu.get_settings()["quality_overrides"]
    _check("override_alias_posts_ao", ov_alias.has("post_ao") and not ov_alias.has("posts_ao"), str(ov_alias))
    menu.set_settings({"quality_overrides": {}})

func _test_day_length(menu) -> void:
    _log("--- 时间流速十档 ---")
    menu.set_settings({"day_length": 600.0, "time_source": "sim"})
    await process_frame
    var sliders: Dictionary = menu.get("_sliders")
    var labels: Dictionary = menu.get("_slider_value_labels")
    _check("daylen_slider_exists", sliders.has("day_length"))
    if not sliders.has("day_length"):
        return
    _check("daylen_tick_count_10", int((sliders["day_length"] as Control).get("tick_count")) == 10, "ticks=%d" % int((sliders["day_length"] as Control).get("tick_count")))
    _check("daylen_hint_present", menu.get("_daylen_note") != null and str((menu.get("_daylen_note") as Label).text).contains("每游戏日"))
    var presets: Array = S.DAY_LENGTH_PRESETS
    var all_ok := true
    var bad := ""
    for i in presets.size():
        menu._on_slider_changed("day_length", float(i))
        var got: float = float(menu.get_settings()["day_length"])
        if not is_equal_approx(got, float(presets[i])):
            all_ok = false
            bad = "i=%d got=%.1f want=%.1f" % [i, got, float(presets[i])]
    _check("daylen_all_10_presets", all_ok, bad)
    menu._on_slider_changed("day_length", 5.0)
    _check("daylen_label_1500", str((labels["day_length"] as Label).text).contains("25 分钟"), str((labels["day_length"] as Label).text))
    menu.set_settings({"time_source": "real"})
    await process_frame
    var dl: Control = sliders["day_length"]
    _check("real_disables_daylen", dl.mouse_filter == Control.MOUSE_FILTER_IGNORE and absf(dl.modulate.a - 0.45) < 0.02 and not dl.tooltip_text.is_empty(), "mf=%d a=%.2f" % [dl.mouse_filter, dl.modulate.a])
    _check("real_keeps_saved_daylen", is_equal_approx(float(menu.get_settings()["day_length"]), 1500.0), "dl=%.1f" % float(menu.get_settings()["day_length"]))
    _check("real_shows_tz_row", (menu.get("_tz_row") as Control).visible)
    menu.set_settings({"time_source": "sim"})
    await process_frame
    _check("sim_enables_daylen", dl.mouse_filter == Control.MOUSE_FILTER_STOP and absf(dl.modulate.a - 1.0) < 0.02)
    _check("sim_hides_tz_row", not (menu.get("_tz_row") as Control).visible)

func _test_volumes(menu) -> void:
    _log("--- 五组音量 ---")
    var sliders: Dictionary = menu.get("_sliders")
    var labels: Dictionary = menu.get("_slider_value_labels")
    var gs: Dictionary = menu.get_settings()
    for key in S.VOLUME_KEYS:
        _check("volume_key_in_settings_" + key, gs.has(key), str(key))
        _check("volume_slider_" + key, sliders.has(key))
        if sliders.has(key):
            _check("volume_slider_step_" + key, is_equal_approx(float((sliders[key] as Control).get("step")), 0.1) or is_equal_approx(float((sliders[key] as Control).get("step")), 0.01), "step=%.3f" % float((sliders[key] as Control).get("step")))
            _check("volume_slider_range_" + key, is_equal_approx(float((sliders[key] as Control).get("min_value")), 0.0) and is_equal_approx(float((sliders[key] as Control).get("max_value")), 1.0))
    menu.set_settings({"volume_master": 0.33, "volume_ambient": 0.44, "volume_birds": 0.55, "volume_fire": 0.66, "volume_sfx": 0.77})
    gs = menu.get_settings()
    var vals_ok := is_equal_approx(float(gs["volume_master"]), 0.33) and is_equal_approx(float(gs["volume_ambient"]), 0.44) and is_equal_approx(float(gs["volume_birds"]), 0.55) and is_equal_approx(float(gs["volume_fire"]), 0.66) and is_equal_approx(float(gs["volume_sfx"]), 0.77)
    _check("volume_roundtrip", vals_ok, "master=%.2f ambient=%.2f birds=%.2f fire=%.2f sfx=%.2f" % [float(gs["volume_master"]), float(gs["volume_ambient"]), float(gs["volume_birds"]), float(gs["volume_fire"]), float(gs["volume_sfx"])])
    _check("volume_master_label_pct", str((labels["volume_master"] as Label).text) == "33%", str((labels["volume_master"] as Label).text))
    _check("legacy_volume_alias", sliders.has("volume") and sliders["volume"] == sliders["volume_master"] and is_equal_approx(float(gs["volume"]), float(gs["volume_master"])))
    menu._on_slider_changed("volume_sfx", 0.9)
    _check("volume_slider_change_effective", is_equal_approx(float(menu.get_settings()["volume_sfx"]), 0.9), "sfx=%.2f" % float(menu.get_settings()["volume_sfx"]))
    menu.set_settings({"volume_master": 0.8, "volume_ambient": 0.7, "volume_birds": 0.8, "volume_fire": 0.7, "volume_sfx": 0.8})

func _test_display_confirm(menu) -> void:
    _log("--- 分辨率 / 窗口模式确认层 ---")
    menu.set_settings({"resolution": Vector2i(1440, 900), "window_mode": "windowed"})
    await process_frame
    var sliders: Dictionary = menu.get("_sliders")
    var presets: Array = S.resolution_presets()
    _check("res_slider_exists", sliders.has("resolution"))
    if not sliders.has("resolution"):
        return
    var res_slider: Control = sliders["resolution"]
    _check("res_tick_count_presets", int(res_slider.get("tick_count")) == presets.size(), "%d vs %d" % [int(res_slider.get("tick_count")), presets.size()])
    _check("res_presets_contain_3440", presets.has(Vector2i(3440, 1440)), str(presets))
    var emitted: Array = []
    menu.settings_changed.connect(func(s: Dictionary) -> void: emitted.append(s))

    menu._on_res_drag_started()
    var cur: Vector2i = menu.get_settings()["resolution"]
    var cur_idx: int = S.resolution_index(presets, cur)
    var target_idx: int = 4 if cur_idx != 4 else 5
    target_idx = clampi(target_idx, 0, presets.size() - 1)
    res_slider.call("set_value", float(target_idx), true)
    menu._on_res_drag_finished()
    _check("res_confirm_open", bool(menu.get("_res_confirm_open")))
    _check("res_confirm_label_12", str((menu.get("_res_confirm_label") as Label).text).contains("12") and str((menu.get("_res_confirm_label") as Label).text).contains("分辨率"), str((menu.get("_res_confirm_label") as Label).text))
    var applied: Vector2i = menu.get_settings()["resolution"]
    _check("res_confirm_applied", applied == presets[target_idx], "%s want %s" % [str(applied), str(presets[target_idx])])
    _check("res_confirm_emitted_new", emitted.size() >= 1 and (emitted[emitted.size() - 1] as Dictionary)["resolution"] == applied)
    menu._confirm_revert()
    _check("res_revert_closed", not bool(menu.get("_res_confirm_open")))
    _check("res_revert_value", menu.get_settings()["resolution"] == cur, str(menu.get_settings()["resolution"]))
    _check("res_revert_emitted_old", emitted.size() >= 2 and (emitted[emitted.size() - 1] as Dictionary)["resolution"] == cur)
    _check("res_keep_clears", true)

    # 保持按钮：确认层消失且不回退。
    menu._on_res_drag_started()
    var other_idx: int = (target_idx + 2) % presets.size()
    res_slider.call("set_value", float(other_idx), true)
    menu._on_res_drag_finished()
    var kept: Vector2i = menu.get_settings()["resolution"]
    var n_before_keep: int = emitted.size()
    menu._confirm_keep()
    _check("res_keep_closed", not bool(menu.get("_res_confirm_open")))
    _check("res_keep_value", menu.get_settings()["resolution"] == kept)
    await create_timer(0.1).timeout
    _check("res_keep_no_revert_emit", emitted.size() == n_before_keep or (emitted[emitted.size() - 1] as Dictionary)["resolution"] == kept)
    menu.set_settings({"resolution": cur})

    # 窗口模式三态：切换进入确认层，回退恢复。
    var wm_before: String = str(menu.get_settings()["window_mode"])
    menu._on_setting_pressed("window_mode")
    _check("wm_confirm_open", bool(menu.get("_res_confirm_open")))
    _check("wm_confirm_label", str((menu.get("_res_confirm_label") as Label).text).contains("窗口模式"), str((menu.get("_res_confirm_label") as Label).text))
    var wm_new: String = str(menu.get_settings()["window_mode"])
    _check("wm_changed_cycle", wm_new != wm_before, "%s -> %s" % [wm_before, wm_new])
    menu._confirm_revert()
    _check("wm_reverted", str(menu.get_settings()["window_mode"]) == wm_before, str(menu.get_settings()["window_mode"]))

    # 全屏时分辨率滑条禁用 + 说明。
    menu.set_settings({"window_mode": "fullscreen"})
    await process_frame
    _check("fs_disables_res_slider", res_slider.mouse_filter == Control.MOUSE_FILTER_IGNORE and absf(res_slider.modulate.a - 0.45) < 0.02 and res_slider.tooltip_text.contains("全屏"), "mf=%d a=%.2f tip=%s" % [res_slider.mouse_filter, res_slider.modulate.a, res_slider.tooltip_text])
    menu.set_settings({"window_mode": "windowed"})
    await process_frame
    _check("win_enables_res_slider", res_slider.mouse_filter == Control.MOUSE_FILTER_STOP and absf(res_slider.modulate.a - 1.0) < 0.02)

    # 12s 倒计时自动回退：把剩余时间压到 0 再手动 tick 一次 _process。
    menu._on_res_drag_started()
    res_slider.call("set_value", float(target_idx), true)
    menu._on_res_drag_finished()
    menu.set("_res_confirm_t", 0.02)
    menu._process(0.05)
    _check("res_timeout_autorevert", not bool(menu.get("_res_confirm_open")) and menu.get_settings()["resolution"] == cur, str(menu.get_settings()["resolution"]))

func _test_layout(menu) -> void:
    _log("--- 多分辨率适配 ---")
    var sizes: Array = [Vector2i(1280, 720), Vector2i(1440, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3440, 1440)]
    menu.set_settings({"window_mode": "windowed", "time_source": "sim"})
    for size in sizes:
        _menu_vp.size = size
        await process_frame
        await process_frame
        menu._layout()
        await process_frame
        var vp: Vector2 = menu.get_viewport().get_visible_rect().size
        var panel: Control = menu.get("_settings_panel")
        var pr := Rect2(panel.position, panel.size)
        var tag := "%dx%d" % [size.x, size.y]
        var inside := pr.position.x >= -0.5 and pr.position.y >= -0.5 and pr.end.x <= vp.x + 0.5 and pr.end.y <= vp.y + 0.5
        _check("layout_panel_inside_" + tag, inside, "vp=%s panel=%s" % [str(vp), str(pr)])
        _check("layout_panel_scroll_" + tag, (menu.get("_settings_scroll") as ScrollContainer).vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO)
        var vb: Control = menu.get("_settings_vb")
        var need_scroll: bool = vb.get_combined_minimum_size().y + 52.0 > vp.y - 24.0
        if need_scroll:
            var sc: ScrollContainer = menu.get("_settings_scroll")
            sc.scroll_vertical = 100000
            await process_frame
            _check("layout_scroll_reaches_back_" + tag, sc.scroll_vertical > 0)
            sc.scroll_vertical = 0
            await process_frame
        var start_btn: Control = menu.get("_start_btn")
        _check("layout_start_btn_inside_" + tag, start_btn.position.x >= -0.5 and start_btn.position.x + start_btn.size.x <= vp.x + 0.5, str(start_btn.position))
        _check("layout_menu_width_fits_" + tag, vp.x >= 1024.0 or (menu.get("_settings_panel") as Control).size.x <= vp.x)
    _menu_vp.size = Vector2i(1280, 800)
    await process_frame
    await process_frame
    menu._layout()

func _test_hud_layout() -> void:
    _log("--- HUD 多分辨率适配 ---")
    _hud_vp = SubViewport.new()
    _hud_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
    root.add_child(_hud_vp)
    var hud = HudScript.new()
    _hud_vp.add_child(hud)
    await process_frame
    hud.set_hud_visible(true, false)
    hud.set_auto_orbit(true, false)
    hud.update_all({
        "clock": "12:00", "date": "1月1日", "weekday": "周一", "phase": "正午", "phase_short": "正午",
        "sun_alt": 60.0, "sun_az": 180.0, "sunrise": "06:00", "sunset": "18:00", "day_length": "12:00",
        "moon_name": "满月", "moon_illum": 1.0, "moonrise": "18:00", "moonset": "06:00", "theme_t": 0.0,
        "heading": 0.0, "cam_elev": 10.0, "realtime": false, "time_source": "sim", "timezone_label": "",
        "paused": false, "day_length_sec": 900.0,
    })
    await process_frame
    var sizes: Array = [Vector2i(1280, 720), Vector2i(1440, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3440, 1440)]
    var node_names: Array = ["_top_left", "_hint", "_compass", "_time_pill", "_auto_label"]
    for size in sizes:
        _hud_vp.size = size
        await process_frame
        await process_frame
        var vp: Vector2 = hud.get_viewport().get_visible_rect().size
        var tag := "%dx%d" % [size.x, size.y]
        for key in node_names:
            var c: Control = hud.get(key)
            var ok := false
            var rect := Rect2()
            if c != null:
                rect = Rect2(c.position, c.size)
                ok = rect.position.x >= -0.5 and rect.position.y >= -0.5 and rect.end.x <= vp.x + 0.5 and rect.end.y <= vp.y + 0.5
            _check("hud_layout_" + str(key).substr(1) + "_" + tag, ok, "vp=%s rect=%s" % [str(vp), str(rect)])
    _hud_vp.queue_free()
    await process_frame

func _test_title_close(menu) -> void:
    _log("--- 标题菜单既有螺旋飞出保留 ---")
    menu.set_settings({"time_source": "sim"})
    menu.open(false)
    await create_timer(0.75).timeout
    _check("title_open_visible", bool(menu.get("menu_visible")))
    var done := {"called": false}
    menu.close(func() -> void: done["called"] = true)
    await create_timer(0.3).timeout
    _check("title_close_still_animating", bool(menu.get("menu_visible")))
    await create_timer(0.5).timeout
    var rotated := false
    var max_rot := 0.0
    var moved := 0
    var home_ref: Array = menu.get("_items_home")
    for i in (menu.get("_items") as Array).size():
        var c: Control = (menu.get("_items") as Array)[i]
        max_rot = maxf(max_rot, absf(c.rotation))
        if i < home_ref.size() and c.position.distance_to(home_ref[i]) > 80.0:
            moved += 1
    rotated = max_rot > 0.05
    _check("title_close_spiral_rotating", rotated, "max_rot=%.3f" % max_rot)
    _check("title_close_spiral_moved", moved >= 4, "moved=%d" % moved)
    await create_timer(1.7).timeout
    _check("title_close_done", not bool(menu.get("menu_visible")))
    _check("title_close_callback", bool(done["called"]))
    # close 重复调用安全：不可见时直接回调，不重复播放。
    var done2 := {"n": 0}
    menu.close(func() -> void: done2["n"] = int(done2["n"]) + 1)
    await create_timer(0.1).timeout
    _check("title_close_idempotent", not bool(menu.get("menu_visible")))

func _test_hud() -> void:
    _log("--- HUD 自动运镜提示 + 时间流速注记 ---")
    var hud = HudScript.new()
    root.add_child(hud)
    await process_frame
    await process_frame
    var auto_label: Label = hud.get("_auto_label")
    var daylen: Label = hud.get("_time_daylen")
    var toast: Label = hud.get("_toast")
    _check("hud_auto_label_built", auto_label != null)
    _check("hud_daylen_label_built", daylen != null)
    hud.set_auto_orbit(true, true)
    await process_frame
    _check("hud_auto_on_label", auto_label.visible and auto_label.text.contains("自动运镜") and auto_label.text.contains("开"), str(auto_label.text))
    _check("hud_auto_on_toast", toast.visible and toast.text.contains("自动运镜 开") and toast.text.contains("C 键切换"), str(toast.text))
    hud.set_auto_orbit(false, true)
    await process_frame
    _check("hud_auto_off_label", auto_label.text.contains("关"), str(auto_label.text))
    _check("hud_auto_off_toast", toast.text.contains("自动运镜 关"), str(toast.text))
    hud.set_auto_orbit_available(false)
    await process_frame
    _check("hud_auto_hidden_when_unavailable", not auto_label.visible)
    hud.set_auto_orbit_available(true)
    await process_frame
    _check("hud_auto_shown_when_available", auto_label.visible)
    var d := {
        "clock": "12:00", "date": "1月1日", "weekday": "周一", "phase": "正午", "phase_short": "正午",
        "sun_alt": 60.0, "sun_az": 180.0, "sunrise": "06:00", "sunset": "18:00", "day_length": "12:00",
        "moon_name": "满月", "moon_illum": 1.0, "moonrise": "18:00", "moonset": "06:00", "theme_t": 0.0,
        "heading": 0.0, "cam_elev": 10.0, "realtime": false, "time_source": "sim", "timezone_label": "", "paused": false,
    }
    var d2: Dictionary = d.duplicate(true)
    d2["day_length_sec"] = 900.0
    hud.update_all(d2)
    await process_frame
    _check("hud_daylen_note_visible", daylen.visible and daylen.text.contains("15 分钟") and daylen.text.contains("游戏日"), str(daylen.text))
    var d3: Dictionary = d.duplicate(true)
    d3["day_length_sec"] = 0.0
    hud.update_all(d3)
    await process_frame
    _check("hud_daylen_note_hidden_zero", not daylen.visible)
    var d4: Dictionary = d.duplicate(true)
    d4["day_length_sec"] = 1200.0
    hud.update_all(d4)
    await process_frame
    _check("hud_daylen_note_1200", daylen.visible and daylen.text.contains("20 分钟"), str(daylen.text))
    hud.queue_free()
    await process_frame
