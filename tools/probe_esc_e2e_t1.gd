extends SceneTree
## T1 端到端：真实 main + menu 的 ESC 开关菜单（含动画中再次 ESC 反向）验证。
## headless 运行：console exe --headless --path 项目 --script res://tools/probe_esc_e2e_t1.gd

var _fails := 0
var _passes := 0
var main: Node = null
var menu: Node = null

func _initialize() -> void:
    print("=== probe_esc_e2e_t1 start ===")
    change_scene_to_file("res://isle.tscn")
    await process_frame
    for i in 300:
        main = current_scene
        if main != null and main.get("_menu") != null and main.get("_hud") != null:
            break
        await process_frame
    if main == null:
        print("FATAL no main")
        quit(1)
        return
    menu = main.get("_menu")
    await create_timer(1.2).timeout
    _check("boot Mode.MENU", _mode() == 0, "mode=%d" % _mode())
    _check("boot menu visible", bool(menu.get("menu_visible")))
    # 1) 从标题菜单进入游玩
    menu.start_pressed.emit(false)
    var ok: bool = await _poll(func() -> bool: return _mode() == 1 and not bool(menu.get("menu_visible")) and str(main.get("_blending")) == "", 9000)
    _check("enter playing", ok, "mode=%d blend=%s" % [_mode(), str(main.get("_blending"))])
    _check("started flag", bool(main.get("_started")))
    # 2) 游玩中 ESC → 打开菜单动画；动画中再 ESC → 反向
    for cycle in 3:
        var esc := _esc_event()
        main.call("_unhandled_input", esc)
        await create_timer(0.25).timeout
        var st: int = int(menu.get("_anim_state"))
        _check("cycle%d ESC opens menu (anim ENTER)" % cycle, _mode() == 0 and bool(menu.get("menu_visible")) and st == 1, "mode=%d anim=%d" % [_mode(), st])
        var esc2 := _esc_event()
        menu.call("_input", esc2)
        await create_timer(0.06).timeout
        var st2: int = int(menu.get("_anim_state"))
        _check("cycle%d ESC mid-anim reverses (anim EXIT)" % cycle, st2 == 2, "anim=%d" % st2)
        var ok2: bool = await _poll(func() -> bool: return _mode() == 1 and not bool(menu.get("menu_visible")) and str(main.get("_blending")) == "", 4000)
        _check("cycle%d back to playing" % cycle, ok2, "mode=%d vis=%s" % [_mode(), str(menu.get("menu_visible"))])
        _check("cycle%d anim finished clean" % cycle, int(menu.get("_anim_state")) == 0 and menu.get("_anim_tween") == null)
    # 3) 动画完成后再次 ESC 关闭（不反向，走正常退出动画）
    await _poll(func() -> bool: return str(main.get("_blending")) == "", 4000)
    main.call("_unhandled_input", _esc_event())
    await create_timer(0.15).timeout
    _check("idle ESC opens again", _mode() == 0 and bool(menu.get("menu_visible")))
    menu.call("_input", _esc_event())
    await create_timer(0.06).timeout
    _check("idle ESC reversed too (same path)", int(menu.get("_anim_state")) == 2)
    var ok3: bool = await _poll(func() -> bool: return _mode() == 1 and str(main.get("_blending")) == "", 4000)
    _check("back to playing after idle reverse", ok3, "mode=%d" % _mode())
    print("=== SUMMARY PASS=%d FAIL=%d ===" % [_passes, _fails])
    quit(1 if _fails > 0 else 0)

func _esc_event() -> InputEventKey:
    var ev := InputEventKey.new()
    ev.keycode = KEY_ESCAPE
    ev.physical_keycode = KEY_ESCAPE
    ev.pressed = true
    ev.echo = false
    return ev

func _mode() -> int:
    return int(main.get("_mode"))

func _poll(cond: Callable, timeout_ms: int) -> bool:
    var t0 := Time.get_ticks_msec()
    while Time.get_ticks_msec() - t0 < timeout_ms:
        if bool(cond.call()):
            return true
        await process_frame
    return bool(cond.call())

func _check(name: String, cond: bool, detail: String = "") -> void:
    if cond:
        _passes += 1
        print("PASS " + name + ("" if detail == "" else " | " + detail))
    else:
        _fails += 1
        print("FAIL " + name + ("" if detail == "" else " | " + detail))