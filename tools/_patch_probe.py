from pathlib import Path
p = Path(r"D:/休闲小岛幻境/游戏工程/tools/probe_menu6.gd")
t = p.read_text(encoding="utf-8")
old_init = '''func _initialize() -> void:
    root.size = Vector2i(1280, 800)
    await process_frame
    await process_frame
    DirAccess.make_dir_recursive_absolute("D:/休闲小岛幻境/开发产物/logs")
    _log("=== probe_menu6 start ===")
    _log("viewport " + str(root.get_visible_rect().size))
    var menu = MenuScript.new()
    root.add_child(menu)
    await process_frame
    await process_frame
    menu._layout()
    await process_frame'''
new_init = '''var _menu_vp: SubViewport

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
    _log("viewport " + str(menu.get_viewport().get_visible_rect().size))'''
assert old_init in t
t = t.replace(old_init, new_init)
old_lay = '''    var sizes: Array = [Vector2i(1280, 720), Vector2i(1440, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3440, 1440)]
    menu.set_settings({"window_mode": "windowed", "time_source": "sim"})
    for size in sizes:
        root.size = size
        await process_frame
        await process_frame
        menu._layout()
        await process_frame
        var vp: Vector2 = menu.get_viewport().get_visible_rect().size'''
new_lay = '''    var sizes: Array = [Vector2i(1280, 720), Vector2i(1440, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3440, 1440)]
    menu.set_settings({"window_mode": "windowed", "time_source": "sim"})
    for size in sizes:
        _menu_vp.size = size
        await process_frame
        await process_frame
        menu._layout()
        await process_frame
        var vp: Vector2 = menu.get_viewport().get_visible_rect().size'''
assert old_lay in t
t = t.replace(old_lay, new_lay)
old_end = '''    root.size = Vector2i(1280, 800)
    await process_frame
    await process_frame
    menu._layout()'''
new_end = '''    _menu_vp.size = Vector2i(1280, 800)
    await process_frame
    await process_frame
    menu._layout()'''
assert old_end in t
t = t.replace(old_end, new_end)
p.write_text(t, encoding="utf-8")
print("patched probe, lines=%d" % (t.count(chr(10))+1))
