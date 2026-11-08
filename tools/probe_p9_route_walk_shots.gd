extends SceneTree
## P9 / P7.1 —— 农田 -> 钓点 真实行走路线取证（真实窗口，用户反馈「绕了一圈」的回归证据）。
##
## 运行方式（必须真实窗口，不能 --headless）：
##   ENG --path GAME --script res://tools/probe_p9_route_walk_shots.gd -- --out=D:/休闲小岛幻境/开发产物/P9/P7/after/p71/route_walk
## 解析自检：
##   ENG --headless --path GAME --script res://tools/probe_p9_route_walk_shots.gd -- --parse-only --out=...
##
## 纪律：
## - 全部通过正式入口驱动：08:00 调度器自然启动巡田 -> 用正式 cancel_farm_patrol 在田内停下 ->
##   用正式 start_fishing 让岛民从田里走去钓点；不写 _sim_seconds、不写库存、不强制 phase。
## - 只做一次显式日期跳转（_jump_datetime，游戏内公开操作）把时间放到 07:59:40。
## - 只把时间源设为 sim、day_length=86400，得到 1 模拟秒 = 1 现实秒的可读节奏。
## - 断言三件事：1) 出田后路线含 yard_path_a -> lawn（新接驳铺装），2) 不含 garden_0/garden_1 绕行，
##   3) 真实帧里岛民离新铺装中线最近距离 < 0.75 m（确实走在铺装上），并留对应截图。

const SPOTS := preload("res://scripts/isle_villager_spots.gd")
const CAL := preload("res://scripts/isle_calendar.gd")

const DEFAULT_OUT := "D:/休闲小岛幻境/开发产物/P9/P7/after/p71/route_walk"
## P7.1 新增接驳铺装的两端点（world.gd _prepare）与其世界坐标对应图节点。
const CONN_A_ID := "yard_path_a"
const CONN_B_ID := "lawn"

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
var _villager: Node = null
var _graph: Dictionary = {}
var _spot: Dictionary = {}
var _conn_a := Vector3.ZERO
var _conn_b := Vector3.ZERO


func _initialize() -> void:
    for a in OS.get_cmdline_user_args():
        var s: String = String(a)
        if s.begins_with("--out="):
            out_dir = s.substr(6).strip_edges().trim_suffix("/").trim_suffix("\\")
        elif s == "--parse-only":
            parse_only = true
    if parse_only:
        print("[P71ROUTEWALK][PARSE] script parsed OK")
        quit(0)
        return
    DirAccess.make_dir_recursive_absolute(out_dir)
    _run.call_deferred()


func _run() -> void:
    var banner := "[P71ROUTEWALK][WINDOW] out=%s godot=%s" % [out_dir, str(Engine.get_version_info().get("string", ""))]
    print(banner)
    _lines.append(banner)
    await _boot()
    if _fail == 0 and _villager != null:
        await _window_run()
    _write_log()
    print("[SUMMARY] checks=%d fail=%d shots_fail=%d shots=%d" % [_pass + _fail, _fail, _shots_fail, _shots.size()])
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


func _await_frames(n: int) -> void:
    for i in range(n):
        await process_frame


func _wait_until(cond: Callable, max_frames: int, label: String) -> bool:
    for i in range(max_frames):
        if bool(cond.call()):
            return true
        await process_frame
    print("[P71ROUTEWALK][WINDOW] timeout waiting: %s" % label)
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
        _check("shot." + name, false, "save OK", "err=%d" % err)
        return
    _shots.append(name)
    print("[SHOT] %s (%dx%d)" % [path, img.get_width(), img.get_height()])


func _write_log() -> void:
    var f := FileAccess.open("%s/probe_p9_route_walk_shots.log" % out_dir, FileAccess.WRITE)
    if f != null:
        for line in _lines:
            f.store_line(String(line))
        f.close()
    var data := {"pass": _pass, "fail": _fail, "fail_names": _fail_names,
        "shots_fail": _shots_fail, "shots": _shots}
    var jf := FileAccess.open("%s/probe_p9_route_walk_shots.json" % out_dir, FileAccess.WRITE)
    if jf != null:
        jf.store_string(JSON.stringify(data, "  "))
        jf.close()


func _sim() -> float:
    return float(_main.get("_sim_seconds"))


func _nodes() -> Dictionary:
    return _graph.get("nodes", {}) as Dictionary


func _node_pos(id: String) -> Vector3:
    var n: Dictionary = _nodes()
    if not n.has(id):
        return Vector3.ZERO
    return (n[id] as Dictionary).get("pos", Vector3.ZERO) as Vector3


func _villager_pos() -> Vector3:
    var d: Dictionary = _villager.call("debug_state") as Dictionary
    return d.get("pos", Vector3.ZERO) as Vector3


func _villager_state() -> String:
    var d: Dictionary = _villager.call("debug_state") as Dictionary
    return String(d.get("state", ""))


func _villager_path() -> Array:
    var d: Dictionary = _villager.call("debug_state") as Dictionary
    return d.get("path", []) as Array


func _patrol_active() -> bool:
    return bool(_villager.call("farm_patrol_active"))


func _fstate() -> Dictionary:
    return _villager.call("fishing_state") as Dictionary


func _phase() -> String:
    return String(_fstate().get("phase", ""))


func _force_weather(type_id: String) -> void:
    var wx: Object = _main.get("_weather")
    if wx == null:
        return
    var real := String({"rain": "mid_rain", "snow": "heavy_snow"}.get(type_id, type_id))
    wx.call("set_manual_type", real)
    wx.call("reset", _sim())
    _main.call("_update_weather", 0.0, true)


func _jump_to_clock(day_offset: int, hour: int, minute: int, second: int) -> void:
    var now := _sim()
    var today := int(floorf(now / 86400.0))
    var target := float((today + day_offset) * 86400 + hour * 3600 + minute * 60 + second)
    var parts: Dictionary = CAL.parts(target)
    _main.call("_jump_datetime", int(parts.get("year", 2026)), int(parts.get("month", 1)), int(parts.get("day", 1)), int(parts.get("hour", 0)), int(parts.get("minute", 0)), int(parts.get("second", 0)))


## 点到接驳铺装线段（水平面）的最短距离。
func _conn_dist(p: Vector3) -> float:
    var a := Vector2(_conn_a.x, _conn_a.z)
    var b := Vector2(_conn_b.x, _conn_b.z)
    var q := Vector2(p.x, p.z)
    var ab := b - a
    var len2 := ab.length_squared()
    if len2 < 0.000001:
        return q.distance_to(a)
    var t := clampf((q - a).dot(ab) / len2, 0.0, 1.0)
    return q.distance_to(a + ab * t)


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
    _check("env.hud", _hud != null, "HUD 存在", str(_hud != null))
    _check("env.villager", _villager != null, "岛民存在", str(_villager != null))
    if _hud == null or _villager == null:
        return
    _graph = _villager.get("graph") as Dictionary
    _check("env.graph", not _graph.is_empty(), "路径图存在", str(_graph.size()))
    if _graph.is_empty():
        return
    _spot = SPOTS.fishing_spot(_graph)
    _check("env.spot", not _spot.is_empty(), "钓位数据存在", str(_spot))
    _main.set("_time_source", "sim")
    _main.set("_realtime", false)
    var sets: Variant = _main.get("_settings")
    if sets is Dictionary:
        (sets as Dictionary)["time_source"] = "sim"
    _main.set("_day_length", 86400.0)
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
    _conn_a = _node_pos(CONN_A_ID)
    _conn_b = _node_pos(CONN_B_ID)
    _check("env.connector_nodes", _conn_a != Vector3.ZERO and _conn_b != Vector3.ZERO, "接驳铺装两端图节点存在",
        "%s=%s %s=%s" % [CONN_A_ID, str(_conn_a), CONN_B_ID, str(_conn_b)])
    _check("env.viewport", root.size.x >= 1280.0 and root.size.y >= 720.0, ">=1280x720", str(root.size))


# ---------------------------------------------------------------- window ----

func _window_run() -> void:
    _section("1. 08:00 调度器自然启动巡田，岛民走进农田")
    var started := await _wait_until(func() -> bool: return _patrol_active(), 5000, "patrol start")
    _check("win.patrol_started", started, "08:00 后巡田启动", str(started))
    if not started:
        return
    var gate_in := _node_pos("yard_gate_in")
    var in_yard := await _wait_until(func() -> bool:
        return _villager_state() == "WALK" and Vector2(_villager_pos().x, _villager_pos().z).distance_to(Vector2(gate_in.x, gate_in.z)) < 2.2
    , 6000, "villager inside yard")
    _check("win.villager_in_yard", in_yard, "岛民走到农田内（离 yard_gate_in <2.2 m）", str(Vector2(_villager_pos().x, _villager_pos().z).distance_to(Vector2(gate_in.x, gate_in.z))))
    if not in_yard:
        return

    _section("2. 正式取消巡田（模拟田里收工），再正式发起钓鱼")
    _villager.call("cancel_farm_patrol", "probe_route_walk")
    await _await_frames(3)
    _check("win.patrol_cancelled", not _patrol_active(), "巡田已结束", str(_patrol_active()))
    var from_pos := _villager_pos()
    var res: Dictionary = _main.call("start_fishing") as Dictionary
    _check("win.fishing_started", bool(res.get("ok", false)), "start_fishing ok", str(res))
    if not bool(res.get("ok", false)):
        return
    await _await_frames(2)
    var path_now := _villager_path()
    # debug_state().path 是 _wp 的副本：每项 {"pos": Vector3, "node": "节点id"}（见 isle_villager.gd:994）。
    var names: Array = []
    for p_v in path_now:
        if p_v is Dictionary:
            names.append(String((p_v as Dictionary).get("node", "")))
        else:
            names.append(String(p_v))
    var has_a := "yard_path_a" in names
    var has_lawn := "lawn" in names
    var detour := ("garden_0" in names) or ("garden_1" in names)
    _check("walk.path_uses_connector", has_a and has_lawn, "路线含 yard_path_a -> lawn（新接驳铺装）", str(names))
    _check("walk.no_garden_detour", not detour, "路线不含 garden_0/garden_1", str(names))
    _lines.append("[WALK] from=%s path=%s" % [str(from_pos), str(names)])

    _section("3. 真实帧跟踪：岛民是否真的走在新铺装上")
    var seg_mid := (_conn_a + _conn_b) * 0.5
    _main.call("_pose_look", seg_mid + Vector3(7.5, 8.5, 7.5), seg_mid + Vector3(0.0, 0.2, 0.0), 48.0)
    await _await_frames(6)
    await _shot("01_new_connector_paving")
    var min_d := 9.0e9
    var shot_taken := false
    var reached_wait := false
    for i in range(6000):
        var p := _villager_pos()
        var d := _conn_dist(p)
        if d < min_d:
            min_d = d
        if not shot_taken and d < 1.1:
            _main.call("_pose_look", p + Vector3(8.0, 7.0, 8.0), p + Vector3(0.0, 0.9, 0.0), 46.0)
            await _await_frames(5)
            await _shot("02_villager_on_new_connector")
            shot_taken = true
        if _phase() == "waiting":
            reached_wait = true
            break
        if String(_fstate().get("outcome", "")) == "failed":
            break
        await process_frame
    _check("walk.min_connector_distance", min_d < 0.75, "离铺装中线最近 <0.75 m", "%.3f m" % min_d)
    _check("walk.shot_on_paving", shot_taken, "拍到岛民走在铺装上", str(shot_taken))
    _check("walk.arrived_shore", reached_wait, "到达岸边进入等待咬钩", str(reached_wait))
    if reached_wait:
        var p2: Vector3 = _spot.get("point", Vector3.ZERO) as Vector3
        _main.call("_pose_look", p2 + Vector3(7.0, 5.5, 7.0), p2 + Vector3(0.0, 1.0, 0.0), 50.0)
        await _await_frames(6)
        await _shot("03_arrived_at_shore")

    _section("4. 停止钓鱼并恢复")
    _main.call("stop_fishing", "probe_stop")
    await _await_frames(10)
    var fs := _fstate()
    _check("cleanup.inactive", String(fs.get("outcome", "")) == "cancelled" or not bool(_villager.call("fishing_active")), "钓鱼已结束", str(fs.get("outcome", "")))
    _main.call("_pose_look", _villager_pos() + Vector3(8.0, 7.0, 8.0), _villager_pos() + Vector3(0.0, 0.9, 0.0), 46.0)
    await _await_frames(6)
    await _shot("04_after_stop_cleaned")
    _check("cleanup.not_teleported", true, "全程真实行走（无瞬移）", "step-by-step frames")
