extends SceneTree
## P9 / P6-VISUAL-FIX —— 真实窗口验收探针（码头钓位 + 鱼竿前抛）。
##
## 运行方式（必须真实窗口，不能 --headless）：
##   ENG --path 游戏工程 --script res://tools/probe_p9_fishing_visual_fix.gd -- --out=DIR
## 解析自检（无 GPU 也可跑）：
##   ENG --headless --path 游戏工程 --script res://tools/probe_p9_fishing_visual_fix.gd -- --parse-only
##
## 纪律：
## - 驱动正式入口：HUD press_fishing_button() → main._on_fishing_toggle → villager.begin_fishing。
## - 不改 _sim_seconds、不直接写库存、不强制 phase/caught，只读状态并截图。
## - 只把时间源设为 sim、day_length=86400（与 P4/P5 窗口探针一致），不影响玩法计时规则。
## - 所有判据都在 **世界/村民空间**：竿尖是否在身前、是否在木板上、落点是否在水面。
## - 每个机位都 await 到位再截图（异步函数必须 await，否则多段机位互相抢占）。

const SPOTS := preload("res://scripts/isle_villager_spots.gd")
const FISH := preload("res://scripts/isle_fish.gd")
const WORLD := preload("res://scripts/world.gd")

const DEFAULT_OUT := "D:/休闲小岛幻境/开发产物/P9/P6/visual-fix"
const BASE_Y := 2026
const BASE_M := 10
const BASE_D := 24
const DECK_Y := 0.72          # world.gd DECK_WORLD_Y
const PLANK_X := 1.70         # dock-local |x| 上限
const PLANK_Z_MIN := 1.80     # 首块木板前缘
const PLANK_Z_MAX := 11.225   # 末块木板后缘
const BODY_R := 0.10

var out_dir := DEFAULT_OUT
var parse_only := false

var _pass := 0
var _fail := 0
var _lines: Array = []
var _fail_names: Array = []
var _shots: Array = []
var _shots_fail := 0

var _main: Node = null
var _hud: Object = null
var _inv: Object = null
var _villager: Node = null
var _spot: Dictionary = {}
var _dock: Dictionary = {}
var _graph: Dictionary = {}

var _walk_max_step := 0.0
var _walk_max_dy := 0.0


func _initialize() -> void:
    _parse_args()
    if parse_only:
        print("[P6VF][PARSE] script parsed OK")
        quit(0)
        return
    DirAccess.make_dir_recursive_absolute(out_dir + "/shots")
    DirAccess.make_dir_recursive_absolute(out_dir + "/logs")
    _run.call_deferred()


func _parse_args() -> void:
    for a in OS.get_cmdline_user_args():
        var s: String = String(a)
        if s.begins_with("--out="):
            out_dir = s.substr(6).strip_edges().trim_suffix("/").trim_suffix(String.chr(92))
        elif s == "--parse-only":
            parse_only = true
    if out_dir == "":
        out_dir = DEFAULT_OUT


func _run() -> void:
    var banner := "[P6VF] out=%s headless=%s godot=%s" % [out_dir, str(DisplayServer.get_name() == "headless"), String(Engine.get_version_info().get("string", ""))]
    print(banner)
    _lines.append(banner)
    await _boot()
    if _fail == 0 and _villager != null and not _spot.is_empty():
        await _main_run()
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
    _check(name, value >= lo and value <= hi, "[%.3f..%.3f]" % [lo, hi], "%.4f" % value)


func _await_frames(n: int) -> void:
    for i in range(n):
        await process_frame


func _wait_until(cond: Callable, max_frames: int, label: String) -> bool:
    for i in range(max_frames):
        if bool(cond.call()):
            return true
        await process_frame
    print("[P6VF] timeout waiting: %s" % label)
    return bool(cond.call())


func _shot(name: String) -> void:
    await RenderingServer.frame_post_draw
    var img: Image = root.get_texture().get_image()
    if img == null or img.get_width() <= 0:
        _shots_fail += 1
        _check("shot." + name, false, "非空 PNG", "empty image")
        return
    var path := "%s/shots/%s.png" % [out_dir, name]
    var err := img.save_png(path)
    if err != OK:
        _shots_fail += 1
        _check("shot." + name, false, "PNG 保存成功", str(err))
        return
    _shots.append(path)
    print("[SHOT] %s %dx%d %s" % [name, img.get_width(), img.get_height(), path])


func _write_log() -> void:
    var f := FileAccess.open("%s/logs/probe_p9_fishing_visual_fix.log" % out_dir, FileAccess.WRITE)
    if f != null:
        for line in _lines:
            f.store_line(String(line))
        f.close()
    var data := {
        "pass": _pass,
        "fail": _fail,
        "fail_names": _fail_names,
        "shots": _shots,
        "shots_fail": _shots_fail,
        "spot": _spot,
        "walk_max_step": _walk_max_step,
        "walk_max_dy": _walk_max_dy,
    }
    var jf := FileAccess.open("%s/logs/probe_p9_fishing_visual_fix.json" % out_dir, FileAccess.WRITE)
    if jf != null:
        jf.store_string(JSON.stringify(data, "  "))
        jf.close()


func _sim() -> float:
    return float(_main.get("_sim_seconds"))


func _vstate() -> Dictionary:
    return _villager.call("debug_state") as Dictionary


func _vpos() -> Vector3:
    return _vstate().get("pos", Vector3.ZERO) as Vector3


func _vyaw() -> float:
    return float(_vstate().get("yaw", 0.0))


func _phase() -> String:
    return String(_villager.call("fishing_phase"))


func _active() -> bool:
    return bool(_villager.call("fishing_active"))


func _fstate() -> Dictionary:
    return _villager.call("fishing_state") as Dictionary


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


## 世界坐标 → 码头局部 (x, z)（码头原点是 isle_math.dock_start()，+Z 沿向海轴线）
func _dock_local(p: Vector3) -> Vector2:
    var o: Vector3 = _dock["origin"]
    var b := Basis(Vector3.UP, float(_dock["yaw"]))
    var rel := p - o
    return Vector2(rel.dot(b.x), rel.dot(b.z))


## 世界点是否落在木板可站立矩形内（内缩 shrink）
func _on_planks(p: Vector3, shrink: float = 0.0) -> bool:
    var l := _dock_local(p)
    return absf(l.x) <= PLANK_X - shrink and l.y >= PLANK_Z_MIN + shrink and l.y <= PLANK_Z_MAX - shrink


func _focus(eye: Vector3, target: Vector3, fov: float) -> void:
    _main.call("_pose_look", eye, target, fov)


func _dirs() -> Array:
    var d: Vector3 = _spot.get("cast_dir", Vector3(0, 0, -1)) as Vector3
    return [d, Vector3(-d.z, 0.0, d.x)]


# ---- 机位（全部 await 到位再截）----

func _cam_dock_wide() -> void:
    var p := _vpos()
    var dd := _dirs()
    var d: Vector3 = dd[0]
    var r: Vector3 = dd[1]
    _focus(p - d * 5.6 + r * 3.2 + Vector3(0.0, 2.5, 0.0), p + d * 1.2 + Vector3(0.0, 0.75, 0.0), 52.0)
    await _await_frames(6)


func _cam_feet() -> void:
    var p := _vpos()
    var dd := _dirs()
    var d: Vector3 = dd[0]
    var r: Vector3 = dd[1]
    _focus(p + r * 2.6 - d * 1.4 + Vector3(0.0, 0.75, 0.0), p + Vector3(0.0, 0.30, 0.0), 42.0)
    await _await_frames(6)


func _cam_hold_side() -> void:
    var p := _vpos()
    var dd := _dirs()
    var d: Vector3 = dd[0]
    var r: Vector3 = dd[1]
    _focus(p + r * 3.8 + Vector3(0.0, 1.25, 0.0), p + d * 1.2 + Vector3(0.0, 1.10, 0.0), 46.0)
    await _await_frames(6)


func _cam_hold_3q() -> void:
    var p := _vpos()
    var dd := _dirs()
    var d: Vector3 = dd[0]
    var r: Vector3 = dd[1]
    _focus(p - d * 3.0 + r * 3.2 + Vector3(0.0, 1.55, 0.0), p + d * 0.7 + Vector3(0.0, 1.05, 0.0), 46.0)
    await _await_frames(6)


func _cam_cast_side() -> void:
    var p := _vpos()
    var dd := _dirs()
    var d: Vector3 = dd[0]
    var r: Vector3 = dd[1]
    _focus(p + r * 4.4 + Vector3(0.0, 1.55, 0.0) - d * 0.6, p + d * 0.9 + Vector3(0.0, 1.30, 0.0), 48.0)
    await _await_frames(3)


func _cam_line() -> void:
    var p := _vpos()
    var cp: Vector3 = _spot.get("cast_point", Vector3.ZERO) as Vector3
    var dd := _dirs()
    var d: Vector3 = dd[0]
    var r: Vector3 = dd[1]
    var mid := (p + cp) * 0.5 + Vector3(0.0, 0.75, 0.0)
    _focus(mid + r * 5.2 + Vector3(0.0, 1.35, 0.0) - d * 1.4, mid, 54.0)
    await _await_frames(6)


func _force_weather(type_id: String) -> void:
    var wx: Object = _main.get("_weather")
    if wx == null:
        return
    var real := String({"rain": "mid_rain", "snow": "heavy_snow"}.get(type_id, type_id))
    wx.call("set_manual_type", real)
    wx.call("reset", _sim())
    _main.call("_update_weather", 0.0, true)


# ---------------------------------------------------------------- boot ------

func _boot() -> void:
    _section("0. 正式主场景 isle.tscn（真实窗口）")
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
    _check("env.real_window", DisplayServer.get_name() != "headless", "真实窗口", DisplayServer.get_name())
    _check("env.hud", _hud != null, "HUD 存在", str(_hud != null))
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
    _main.call("_jump_datetime", BASE_Y, BASE_M, BASE_D, 12, 0, 0)
    await _await_frames(2)
    _force_weather("clear")
    _main.set("_paused", false)
    _main.set("_started", true)
    if _main.has_method("_enter_playing"):
        _main.call("_enter_playing")
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
    _graph = _villager.get("graph") as Dictionary
    _dock = _graph.get("dock", {}) as Dictionary
    _spot = SPOTS.fishing_spot(_graph)
    _check("env.spot_ready", not _spot.is_empty(), "钓位数据存在", str(not _spot.is_empty()))
    _check("env.dock_frame", _dock.has("origin") and _dock.has("dir"), "码头空间框架存在", str(_dock.keys()))
    var vp: Vector2 = Vector2(root.size)
    _check("env.viewport", vp.x >= 1280.0 and vp.y >= 720.0, ">=1280x720", str(vp))
    _check_eq("env.fish_total_zero", _fish_total(), 0)


# ---------------------------------------------------------------- window ----

func _main_run() -> void:
    _section("1. 钓位数据：必须在码头木板上、落点必须在海面")
    var node_name := String(_spot.get("node", ""))
    var p: Vector3 = _spot.get("point", Vector3.ZERO) as Vector3
    var cp: Vector3 = _spot.get("cast_point", Vector3.ZERO) as Vector3
    var cd: Vector3 = _spot.get("cast_dir", Vector3.ZERO) as Vector3
    _check_eq("spot.node", node_name, "dock_fishing_stand")
    _check("spot.deck_y", absf(p.y - DECK_Y) <= 0.001, "站位高度 = 甲板面 0.720", "%.4f" % p.y)
    _check("spot.on_planks", _on_planks(p, 0.0), "站位在木板矩形内", str(_dock_local(p)))
    var l := _dock_local(p)
    _check("spot.rail_clearance", absf(l.x) <= PLANK_X - 1.5, "离两侧栏杆 >= 1.5 m", "%.3f" % (PLANK_X - absf(l.x)))
    _check("spot.cast_on_water", WORLD.surface_y(cp.x, cp.z) < -0.5, "落点下方是海水（地形 < -0.5）", "%.3f" % WORLD.surface_y(cp.x, cp.z))
    _check("spot.cast_ahead", Vector2(cd.x, cd.z).normalized().dot(Vector2(p.x, p.z).normalized()) > 0.0, "抛竿朝向海（远离岛心）", "%.3f" % Vector2(cd.x, cd.z).normalized().dot(Vector2(p.x, p.z).normalized()))
    _check_range("spot.cast_dist", Vector2(cp.x - p.x, cp.z - p.z).length(), 3.0, 3.4)
    var axis: Vector3 = _spot.get("cast_axis", Vector3.ZERO) as Vector3
    _check("spot.cast_dir_derived", absf(cd.normalized().dot(axis.normalized()) - cos(1.0821)) < 0.06, "抛竿方向 = 码头轴线偏 62°", "%.4f" % cd.normalized().dot(axis.normalized()))
    var gp: PackedStringArray = SPOTS.find_path(_graph, "yard_path_a", node_name)
    _check("spot.reachable", gp.size() > 1, "路径图可达", str(gp.size()) + " 节点")
    print("[P6VF] path=%s" % str(gp))

    _section("2. 点击 HUD 按钮：岛民沿真实路径走上码头")
    var before_total := _fish_total()
    _hud.call("press_fishing_button")
    await _await_frames(3)
    _check_eq("walk.active", _active(), true)
    _check_eq("walk.phase", _phase(), "walking")
    _check_eq("walk.spot", String(_fstate().get("spot", "")), node_name)
    _check_eq("walk.rod_hidden", bool(_rig_info().get("rod_visible", true)), false)
    var ui0: Dictionary = _hud.call("fishing_ui_state") as Dictionary
    _check("walk.hud_status", String(ui0.get("status_text", "")).contains("码头"), "contains 码头", String(ui0.get("status_text", "")))
    var prev := _vpos()
    var frames := 0
    var shot_mid := false
    while _phase() == "walking" and frames < 6000:
        await process_frame
        frames += 1
        var pos := _vpos()
        var step := (pos - prev).length()
        var dy := absf(pos.y - prev.y)
        _walk_max_step = maxf(_walk_max_step, step)
        _walk_max_dy = maxf(_walk_max_dy, dy)
        prev = pos
        if not shot_mid and frames == 700:
            shot_mid = true
            await _cam_dock_wide()
            await _shot("walk_on_dock")
            prev = _vpos()
    _check("walk.finished", _phase() != "walking" and _active(), "arrived", _phase())
    _check("walk.no_teleport", _walk_max_step <= 0.15, "<=0.15 m/帧", "%.4f" % _walk_max_step)
    _check("walk.no_vertical_jump", _walk_max_dy <= 0.10, "<=0.10 m/帧（P4 同款竖直插值规则）", "%.4f" % _walk_max_dy)
    print("[P6VF] walk frames=%d max_step=%.4f max_dy=%.4f" % [frames, _walk_max_step, _walk_max_dy])

    _section("3. 站立位置：双脚在码头木板上、不浮空不穿板")
    var pnow := _vpos()
    var arrive_err := (pnow - p).length()
    _check("stand.arrive", arrive_err <= 0.12, "<=0.12", "%.4f" % arrive_err)
    _check("stand.height", absf(pnow.y - DECK_Y) <= 0.01, "脚底 = 0.720", "%.4f" % pnow.y)
    _check("stand.on_planks", _on_planks(pnow, 0.0), "脚底投影在木板矩形内", str(_dock_local(pnow)))
    _check("stand.on_planks_with_radius", _on_planks(pnow, BODY_R), "含 0.10 m 人体半径仍在木板内", str(_dock_local(pnow)))
    var on_terrain := absf(pnow.y - WORLD.surface_y(pnow.x, pnow.z)) < 0.05
    _check("stand.not_on_slope", not on_terrain, "没有站在沙坡上", "terrain_y=%.3f stand_y=%.3f" % [WORLD.surface_y(pnow.x, pnow.z), pnow.y])
    var yaw_err := absf(angle_difference(_vyaw(), float(_spot.get("face_yaw", 0.0))))
    _check("stand.yaw_faces_sea", yaw_err <= 0.05, "<=0.05", "%.4f" % yaw_err)
    await _cam_dock_wide()
    await _shot("dock_fishing_stand")
    await _cam_feet()
    await _shot("feet_on_deck_planks")

    _section("4. fish_cast：明确的后摆蓄力 → 前甩弧线（竿尖真的从身前掠过）")
    var pitch_back := -9.0
    var pitch_whip := 9.0
    var tip_fwd_back := -9.0
    var tip_fwd_whip := 9.0
    var got_back := false
    var got_whip := false
    var cast_frames := 0
    while _phase() == "casting" and _active() and cast_frames < 400:
        await process_frame
        cast_frames += 1
        var ric := _rig_info()
        var pp := float(ric.get("rod_pose_pitch", 0.0))
        var tf := float(ric.get("rod_tip_forward_m", -9.0))
        if pp > pitch_back:
            pitch_back = pp
            tip_fwd_back = tf
        if pp < pitch_whip:
            pitch_whip = pp
            tip_fwd_whip = tf
        if not got_back and pp > 0.75:
            got_back = true
            _main.set("_paused", true)
            await _await_frames(3)
            await _cam_cast_side()
            await _shot("fish_cast_start")
            _main.set("_paused", false)
        elif not got_whip and pp < -0.35:
            got_whip = true
            _main.set("_paused", true)
            await _await_frames(3)
            await _shot("fish_cast_mid")
            _main.set("_paused", false)
    _check("cast.backswing", pitch_back > 0.75, "后摆仰角 >0.75 rad 偏移", "%.3f" % pitch_back)
    _check("cast.whip", pitch_whip < -0.35, "前甩仰角 <-0.35 rad 偏移", "%.3f" % pitch_whip)
    _check("cast.tip_sweeps_forward", tip_fwd_back >= -9.0 and (tip_fwd_whip - tip_fwd_back) > 0.8, "竿尖由后摆位置向前甩出 >0.8 m", "%.3f -> %.3f" % [tip_fwd_back, tip_fwd_whip])
    var launched := await _wait_until(func() -> bool: return bool(_rig_info().get("cast_launched", false)) or _phase() != "casting", 240, "cast launched")
    _check("cast.launched", launched, "浮漂在甩出帧离开竿尖", str(launched))
    var waited := await _wait_until(func() -> bool: return _phase() == "waiting" or not _active(), 300, "cast->waiting")
    _check("cast.done", waited and _phase() == "waiting", "waiting", _phase())
    var landed := await _wait_until(func() -> bool: return int(_rig_info().get("splash_events", 0)) >= 1, 240, "bobber splash")
    _check("cast.splash", landed, "浮漂落水有水花", str(int(_rig_info().get("splash_events", 0))))

    _section("5. fish_hold：竿尖指向身前海面（不再是肩扛）")
    await _await_frames(6)
    var ri := _rig_info()
    var tip: Vector3 = ri.get("rod_tip_world", Vector3.ZERO) as Vector3
    var hand: Vector3 = ri.get("hand_world", Vector3.ZERO) as Vector3
    _check_eq("hold.rod_visible", bool(ri.get("rod_visible", false)), true)
    _check("hold.rod_forward_dot", float(ri.get("rod_forward_dot", -1.0)) > 0.90, ">0.90（竿身与朝向前夹角 <26°）", "%.4f" % float(ri.get("rod_forward_dot", -1.0)))
    _check("hold.tip_front_m", float(ri.get("rod_tip_forward_m", -9.0)) > 1.2, "竿尖在身前 >1.2 m", "%.4f" % float(ri.get("rod_tip_forward_m", -9.0)))
    _check("hold.tip_above_water", float(ri.get("rod_tip_above_water", -9.0)) > 1.2, "竿尖高于海面 >1.2 m", "%.4f" % float(ri.get("rod_tip_above_water", -9.0)))
    _check("hold.grip_at_hand", tip.distance_to(hand) > 1.4 and tip.distance_to(hand) < 2.0, "竿尖离握点 1.4~2.0 m", "%.4f" % tip.distance_to(hand))
    var tl := _dock_local(tip)
    _check("hold.tip_past_deck", tl.y > PLANK_Z_MAX, "竿尖越过木板末端（悬在水面上方）", "local=(%.2f, %.2f)" % [tl.x, tl.y])
    _check_range("hold.tip_height", tip.y - DECK_Y, 1.1, 1.9)
    await _cam_hold_side()
    await _shot("fish_hold_front")
    await _cam_hold_3q()
    await _shot("fish_hold_3q")

    _section("6. 鱼线 / 浮漂：竿尖 → 水面的连续空间关系")
    var ril := _rig_info()
    var bob: Vector3 = ril.get("bobber_world", Vector3.ZERO) as Vector3
    _check("line.visible", bool(ril.get("line_visible", false)), "true", str(bool(ril.get("line_visible", false))))
    _check("bobber.visible", bool(ril.get("bobber_visible", false)), "true", str(bool(ril.get("bobber_visible", false))))
    _check("bobber.on_water", absf(bob.y) <= 0.10, "|y| <= 0.10（海面）", "%.4f" % bob.y)
    var bob_off := Vector2(bob.x - cp.x, bob.z - cp.z).length()
    _check("bobber.at_cast_point", bob_off <= 0.25, "<=0.25 m", "%.4f" % bob_off)
    _check("bobber.over_water", WORLD.surface_y(bob.x, bob.z) < -0.5, "浮漂下方是海水", "%.3f" % WORLD.surface_y(bob.x, bob.z))
    var pts: PackedVector3Array = ril.get("line_points", PackedVector3Array())
    _check_eq("line.point_count", pts.size(), 15)
    if pts.size() == 15:
        var tip2: Vector3 = ril.get("rod_tip_world", Vector3.ZERO) as Vector3
        var rig_node: Node = _villager.get("_fish_rig") as Node
        var p0: Vector3 = (rig_node as Node3D).to_global(pts[0])
        var p14: Vector3 = (rig_node as Node3D).to_global(pts[14])
        _check("line.start_at_tip", p0.distance_to(tip2) < 0.02, "<0.02 m", "%.4f" % p0.distance_to(tip2))
        _check("line.end_at_bobber", p14.distance_to(bob + Vector3(0.0, 0.055, 0.0)) < 0.02, "<0.02 m", "%.4f" % p14.distance_to(bob + Vector3(0.0, 0.055, 0.0)))
        var bad := 0
        for i in range(15):
            var wp: Vector3 = (rig_node as Node3D).to_global(pts[i])
            if _on_planks(wp, 0.0) and wp.y < DECK_Y + 0.02:
                bad += 1
        _check_eq("line.no_deck_crossing", bad, 0)
    await _cam_line()
    await _shot("fish_line_bobber")

    _section("7. 等待咬钩：持竿姿态保持朝前（不闪回肩扛）")
    await _await_frames(10)
    _check_eq("wait.phase", _phase(), "waiting")
    _check_eq("wait.clip", String(_vstate().get("clip", "")), "fish_hold")
    var riw := _rig_info()
    _check("wait.rod_forward_dot", float(riw.get("rod_forward_dot", -1.0)) > 0.90, ">0.90", "%.4f" % float(riw.get("rod_forward_dot", -1.0)))

    _section("8. 咬钩 → 收线 → 鱼获入账")
    var bite_ok := await _wait_until(func() -> bool: return _phase() == "bite" or _phase() == "reeling" or not _active(), 3000, "bite")
    _check("bite.reached", bite_ok and _active(), "进入 bite", _phase())
    var reel_ok := await _wait_until(func() -> bool: return _phase() == "reeling" or not _active(), 400, "reeling")
    _check("reel.phase", reel_ok and _phase() == "reeling", "reeling", _phase())
    var reel_lift := -9.0
    var reel_frames := 0
    var got_reel := false
    while _phase() == "reeling" and _active() and reel_frames < 300:
        await process_frame
        reel_frames += 1
        var pp2 := float(_rig_info().get("rod_pose_pitch", 0.0))
        reel_lift = maxf(reel_lift, pp2)
        if not got_reel and pp2 > 0.45:
            got_reel = true
            _main.set("_paused", true)
            await _await_frames(3)
            await _cam_cast_side()
            await _shot("fish_reel")
            _main.set("_paused", false)
    _check("reel.lift", reel_lift > 0.45, "提竿仰角 >0.45 rad 偏移", "%.3f" % reel_lift)
    var reveal_ok := await _wait_until(func() -> bool: return _phase() == "reveal" or _phase() == "between" or not _active(), 400, "reveal")
    _check("catch.phase", reveal_ok and _active(), "reveal/between", _phase())
    var ris := _rig_info()
    _check_eq("catch.visible", bool(ris.get("catch_visible", false)), true)
    _check_eq("catch.inventory_1", _fish_total(), 1)
    _check_eq("catch.rounds_1", int(_fstate().get("rounds", 0)), 1)
    _check("catch.rod_back_to_hold", float(ris.get("rod_forward_dot", -1.0)) > 0.90, ">0.90（不闪回肩扛）", "%.4f" % float(ris.get("rod_forward_dot", -1.0)))
    await _cam_hold_3q()
    await _shot("fish_catch_reveal")

    _section("9. 第二轮：持竿姿态仍正确（循环不退化）")
    var round2 := await _wait_until(func() -> bool: return (not _active()) or (int(_fstate().get("rounds", 0)) >= 2 and _phase() == "waiting"), 5000, "round2")
    _check("round2.active", _active(), "仍在钓鱼", str(_active()))
    _check("round2.rounds", int(_fstate().get("rounds", 0)) >= 2, ">=2", str(int(_fstate().get("rounds", 0))))
    _check_eq("round2.catches_once", _fish_total(), 2)
    var ri2 := _rig_info()
    _check("round2.rod_forward_dot", float(ri2.get("rod_forward_dot", -1.0)) > 0.90, ">0.90", "%.4f" % float(ri2.get("rod_forward_dot", -1.0)))
    await _cam_hold_3q()
    await _shot("fish_next_cycle")
    await _cam_dock_wide()
    await _shot("fish_next_cycle_wide")

    _section("10. 玩家停止：视觉清理、无新鱼获")
    var fish_before := _fish_total()
    _hud.call("press_fishing_button")
    await _await_frames(4)
    _check_eq("stop.inactive", _active(), false)
    var last: Dictionary = _villager.call("fishing_last") as Dictionary
    _check_eq("stop.outcome", String(last.get("outcome", "")), "cancelled")
    _check_eq("stop.reason", String(last.get("reason", "")), "player_stop")
    await _await_frames(10)
    var riz := _rig_info()
    _check_eq("stop.rod_hidden", bool(riz.get("rod_visible", true)), false)
    _check_eq("stop.bobber_hidden", bool(riz.get("bobber_visible", true)), false)
    _check_eq("stop.catch_hidden", bool(riz.get("catch_visible", true)), false)
    _check_eq("stop.line_hidden", bool(riz.get("line_visible", true)), false)
    var rig_node2: Node = _villager.get("_fish_rig") as Node
    _check_eq("stop.rig_children", rig_node2.get_child_count(), 6)
    var clip_after := String(_vstate().get("clip", ""))
    _check("stop.not_fish_clip", clip_after != "fish_hold" and clip_after != "fish_cast" and clip_after != "fish_reel", "idle clip", clip_after)
    var ui1: Dictionary = _hud.call("fishing_ui_state") as Dictionary
    _check_eq("stop.hud_text", String(ui1.get("text", "")), "钓鱼")
    await _cam_dock_wide()
    await _shot("fish_stop_cleanup")
    await _await_frames(150)
    _check_eq("stop.no_more_fish", _fish_total(), fish_before)
    print("[P6VF] done fish_total=%d shots=%d" % [_fish_total(), _shots.size()])
