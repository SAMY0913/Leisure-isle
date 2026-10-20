extends SceneTree

## T1 设置面板 / HUD 窗口截图（GUI 渲染，非 headless）。
## 运行：Godot_v4.7.2-stable_win64_console.exe --path 项目 --script res://tools/probe_menu6_shots.gd
## 输出：D:/休闲小岛幻境/开发产物/shots6/t1/*.png

const OUT_DIR := "D:/休闲小岛幻境/开发产物/shots6/t1"
const LOG_PATH := "D:/休闲小岛幻境/开发产物/logs/probe_menu6_shots.log"

var _logs: Array = []
var _menu = null
var _hud = null

func _log(s: String) -> void:
    print(s)
    _logs.append(s)

func _save(name: String) -> void:
    await RenderingServer.frame_post_draw
    var img: Image = root.get_texture().get_image()
    var path := OUT_DIR + "/" + name + ".png"
    if img == null:
        _log("SAVE_FAIL " + name)
        return
    var err := img.save_png(path)
    _log("SAVED %s err=%d size=%dx%d" % [path, err, img.get_width(), img.get_height()])

func _wait(sec: float) -> void:
    await create_timer(sec).timeout

func _hud_data() -> Dictionary:
    return {
        "clock": "16:42", "date": "10月20日", "weekday": "周二", "phase": "黄昏", "phase_short": "黄昏",
        "sun_alt": 8.0, "sun_az": 250.0, "sunrise": "06:12", "sunset": "17:48", "day_length": "11:36",
        "moon_name": "盈凸月", "moon_illum": 0.72, "moonrise": "15:20", "moonset": "02:10", "theme_t": 0.62,
        "heading": 128.0, "cam_elev": 12.0, "realtime": false, "time_source": "sim", "timezone_label": "",
        "paused": false, "day_length_sec": 900.0, "quality": "高 · 精致",
    }

func _menu_layout_now() -> void:
    root.size = root.size
    await process_frame
    await process_frame
    _menu.visible = true
    _menu._layout()

func _initialize() -> void:
    DirAccess.make_dir_recursive_absolute(OUT_DIR)
    DirAccess.make_dir_recursive_absolute("D:/休闲小岛幻境/开发产物/logs")
    _log("=== probe_menu6_shots start ===")
    root.size = Vector2i(1440, 900)
    await process_frame
    await process_frame
    var bg := ColorRect.new()
    bg.color = Color("0b0e14")
    bg.position = Vector2.ZERO
    bg.size = Vector2(4000, 3000)
    root.add_child(bg)
    _menu = load("res://scripts/menu.gd").new()
    root.add_child(_menu)
    await process_frame
    await process_frame
    _menu._layout()
    _log("vp=%s" % str(_menu.get_viewport().get_visible_rect().size))
    _menu.open(true)
    await _wait(0.5)
    await _save("01_menu_enter_mid")
    await _wait(0.5)
    await _save("02_menu_idle")
    _menu.open_settings()
    await _wait(0.5)
    await _save("03_settings_top")
    var sc: ScrollContainer = _menu.get("_settings_scroll")
    sc.scroll_vertical = 140
    await process_frame
    await process_frame
    await _save("04_settings_quality")
    sc.scroll_vertical = 100000
    await process_frame
    await process_frame
    await _save("05_settings_audio_bottom")
    sc.scroll_vertical = 0
    await process_frame
    # 分辨率确认层（保持设置面板打开，确认层覆盖其上）
    _menu.set_settings({"resolution": Vector2i(1440, 900), "window_mode": "windowed"})
    var res_slider: Control = (_menu.get("_sliders") as Dictionary)["resolution"]
    _menu._on_res_drag_started()
    res_slider.call("set_value", 4.0, true)
    _menu._on_res_drag_finished()
    await process_frame
    await process_frame
    await _save("06_resolution_confirm")
    _menu._confirm_keep()
    await process_frame
    _menu.close_settings_instant()
    _menu.instant_finish()
    await process_frame
    await process_frame

    # ---- HUD 自动运镜提示（1440x900）----
    _hud = load("res://scripts/hud.gd").new()
    root.add_child(_hud)
    await process_frame
    await process_frame
    _hud.set_hud_visible(true, false)
    _hud.update_all(_hud_data())
    _hud.set_auto_orbit(true, true)
    await _wait(0.40)
    await _save("07_hud_auto_orbit_toast")
    await _wait(2.7)
    _hud.set_auto_orbit(false, false)
    await process_frame
    await _save("08_hud_auto_orbit_indicator_off")
    _hud.set_auto_orbit(true, false)

    # ---- 1280x720 适配 ----
    _hud.set_hud_visible(false, false)
    root.size = Vector2i(1280, 720)
    await process_frame
    await process_frame
    await _menu_layout_now()
    _menu.open(true)
    await _wait(0.9)
    _menu.open_settings()
    await _wait(0.6)
    await _save("10_settings_1280x720")
    _menu.close_settings_instant()
    _menu.instant_finish()
    await process_frame
    _hud.set_hud_visible(true, false)
    _hud.update_all(_hud_data())
    await process_frame
    await _save("11_hud_1280x720")

    # ---- 3440x1440 适配 ----
    _hud.set_hud_visible(false, false)
    root.size = Vector2i(3440, 1440)
    await process_frame
    await process_frame
    await _menu_layout_now()
    _menu.open(true)
    await _wait(1.0)
    _menu.open_settings()
    await _wait(0.6)
    await _save("09_settings_3440x1440")
    _menu.close_settings_instant()
    _menu.instant_finish()
    await process_frame
    _hud.set_hud_visible(true, false)
    _hud.update_all(_hud_data())
    await process_frame
    await _save("12_hud_3440x1440")

    var f := FileAccess.open(LOG_PATH, FileAccess.WRITE)
    if f != null:
        f.store_string("\n".join(_logs) + "\n")
        f.close()
    _log("=== probe_menu6_shots done ===")
    quit(0)