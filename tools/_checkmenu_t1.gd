extends SceneTree
func _initialize() -> void:
    var s = load("res://scripts/menu.gd")
    if s == null:
        print("MENU_LOAD_FAIL")
        quit(1)
        return
    print("MENU_LOAD_OK class=", s.get_global_name() if s.has_method("new") else "?")
    var inst = s.new()
    print("INSTANCE_OK=", inst != null, " has_open=", inst.has_method("open"), " has_set_tick=", inst.has_method("get_anim_state"))
    inst.free()
    quit(0)
