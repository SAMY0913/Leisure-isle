from pathlib import Path
p = Path(r"D:/休闲小岛幻境/游戏工程/tools/probe_menu6.gd")
t = p.read_text(encoding="utf-8")
old_rapid = '''    var before_emit := int(start_emit["n"])
    menu.open(true)
    await process_frame
    menu.close(Callable())
    await create_timer(0.03).timeout
    menu.open(true)
    await create_timer(0.03).timeout
    menu.close(Callable())
    await create_timer(0.03).timeout
    menu.open(true)
    await create_timer(0.03).timeout
    menu.close(Callable())
    await create_timer(0.6).timeout
    _check("rapid_final_closed", not bool(menu.get("menu_visible")))
    _check("rapid_state_idle", int(menu.get("_anim_state")) == 0, "state=%d" % int(menu.get("_anim_state")))
    _check("rapid_no_extra_emit", int(start_emit["n"]) == before_emit)
    _check("rapid_home_restored", _items_at_home(menu))'''
new_rapid = '''    var before_emit := int(start_emit["n"])
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
    _check("rapid_state_idle", int(menu.get("_anim_state")) == 0, "state=%d" % int(menu.get("_anim_state")))'''
assert old_rapid in t
t = t.replace(old_rapid, new_rapid)
old_title = '''    menu.close(func() -> void: done["called"] = true)
    await create_timer(0.2).timeout
    var rotated := false
    for item in (menu.get("_items") as Array):
        if absf((item as Control).rotation) > 0.01:
            rotated = true
            break
    _check("title_close_spiral_rotating", rotated)'''
new_title = '''    menu.close(func() -> void: done["called"] = true)
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
    _check("title_close_spiral_moved", moved >= 4, "moved=%d" % moved)'''
assert old_title in t
t = t.replace(old_title, new_title)
p.write_text(t, encoding="utf-8")
print("patched, lines=%d" % (t.count(chr(10))+1))
