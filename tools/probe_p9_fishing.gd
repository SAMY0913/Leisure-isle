extends SceneTree

const INV := preload("res://scripts/isle_inventory.gd")
const FISH := preload("res://scripts/isle_fish.gd")
const CAL := preload("res://scripts/isle_calendar.gd")
const SPOTS := preload("res://scripts/isle_villager_spots.gd")

const DEFAULT_OUT := "D:/休闲小岛幻境/开发产物/P9/P6/r2_fishing"
const DT := 0.05
const MAX_WALK_TICKS := 1600

var _out_dir: Variant = DEFAULT_OUT
var _lines: Array = []
var _checks: Variant = 0
var _fail: Variant = 0
var _fail_names: Array = []

var _main: Node = null
var _hud: Node = null
var _villager: Node = null
var _inv: Object = null

var _prev_fish: Dictionary = {}
var _committed: Dictionary = {}
var _commit_events: Array = []
var _last_total: Variant = 0
var _burst: Variant = 0
var _decrease: Variant = 0

var _spot: Dictionary = {}
var _saved_sand: Variant = PackedStringArray()
var _saved_stand: Variant = PackedStringArray()
var _timing: Dictionary = {}


func _initialize() -> void:
    _parse_args()
    DirAccess.make_dir_recursive_absolute(_out_dir)
    _run.call_deferred()


func _parse_args() -> void:
    for raw in OS.get_cmdline_user_args():
        var s: Variant = String(raw)
        if s.begins_with("--out="):
            var v: Variant = s.substr(6).strip_edges()
            while v.ends_with("/") or v.ends_with(String.chr(92)):
                v = v.substr(0, v.length() - 1)
            if v != "":
                _out_dir = v


func _run() -> void:
    print("=== P6 fishing probe ===")
    print("[PROBE] out=%s" % _out_dir)
    await _boot()
    _section_a()
    _section_b0()
    _section_b1()
    _section_b2()
    _section_b3()
    _section_b4()
    _section_b5()
    _section_b6()
    _section_b7()
    _section_b8()
    _section_c()
    _section_d()
    _section_e()
    _write_report()
    print("[SUMMARY] checks=%d fail=%d" % [_checks, _fail])
    print("[RESULT] %s" % ("PASS" if _fail == 0 else "FAIL"))
    quit(0 if _fail == 0 else 1)


# ---------------------------------------------------------------- boot / core

func _boot() -> void:
    var ps: Variant = load("res://isle.tscn") as PackedScene
    var inst: Variant = ps.instantiate()
    root.add_child(inst)
    _main = inst
    _main.set_process(false)
    _main.set("_mode", 1)
    await process_frame
    await process_frame
    await process_frame
    await process_frame
    _hud = _main.get("_hud") as Node
    _villager = _main.get("_villager") as Node
    _inv = _main.call("inventory") as Object
    _check_eq("boot.hud", _hud != null, true)
    _check_eq("boot.villager", _villager != null, true)
    _check_eq("boot.inventory", _inv != null, true)
    _check_eq("boot.grant_once", int(_main.get("_inventory_grant_count")), 1)
    _main.set("_time_source", "sim")
    _main.set("_realtime", false)
    _main.set("_day_length", 86400.0)
    _main.set("_paused", false)
    _main.call("_on_time_set", 43200.0)
    _hold_patrol()
    _main.call("_tick", DT)
    _hold_patrol()
    _init_watch()
    var cal: Dictionary = CAL.parts(_sim())
    _check_eq("boot.noon_hour", int(cal.get("hour", -1)), 12)
    _check_eq("boot.awake", _sleeping(), false)
    print("[PROBE] time_source=%s day_length=%.0f sim_rate=%.3f" % [String(_main.get("_time_source")), float(_main.get("_day_length")), float(_main.get("_sim_rate"))])
    print("[PROBE] boot sim=%.1f season=%s weather_key=%s" % [_sim(), String(cal.get("season_id", "")), String(FISH.weather_key(String((_main.call("_weather_eco") as Dictionary).get("type", "clear")), String((_main.call("_weather_eco") as Dictionary).get("precip_type", "none")), float((_main.call("_weather_eco") as Dictionary).get("cloud", 0.0))))])


func _sim() -> float:
    return float(_main.get("_sim_seconds"))


func _hold_patrol() -> void:
    _main.set("_patrol_handled_day", int(floor(_sim() / 86400.0)))


func _sleeping() -> bool:
    var dbg: Variant = _dbg_state()
    var st: Variant = dbg.get("state", "")
    return String(st) == "SLEEP" or String(st) == "BED_IN" or String(st) == "LIE_IN"


func _dbg_state() -> Dictionary:
    return _villager.call("debug_state") as Dictionary


func _pos_now() -> Vector3:
    return _dbg_state().get("pos", Vector3.ZERO) as Vector3


func _yaw_now() -> float:
    return float(_dbg_state().get("yaw", 0.0))


func _fs() -> Dictionary:
    return _villager.call("fishing_state") as Dictionary


func _phase() -> String:
    return String(_fs().get("phase", ""))


func _active() -> bool:
    return bool(_villager.call("fishing_active"))


func _fish_dict() -> Dictionary:
    return _villager.get("_fish") as Dictionary


func _rig() -> Node:
    return _villager.get("_fish_rig") as Node


func _rig_info() -> Dictionary:
    var r: Variant = _rig()
    if r == null or not r.has_method("debug_info"):
        return {}
    return r.call("debug_info") as Dictionary


func _spot_point() -> Vector3:
    return _spot.get("point", Vector3.ZERO) as Vector3


func _spot_cast() -> Vector3:
    return _spot.get("cast_point", Vector3.ZERO) as Vector3


func _total_fish() -> int:
    var total: Variant = 0
    for fid in FISH.all_ids():
        total += int(_inv.call("get_count", fid))
    return total


func _init_watch() -> void:
    _prev_fish.clear()
    _committed.clear()
    _commit_events.clear()
    var total: Variant = 0
    for fid in FISH.all_ids():
        var c: Variant = int(_inv.call("get_count", fid))
        _prev_fish[fid] = c
        _committed[fid] = 0
        total += c
    _last_total = total


func _watch() -> void:
    var sim: Variant = _sim()
    var total: Variant = 0
    for fid in FISH.all_ids():
        var c: Variant = int(_inv.call("get_count", fid))
        var prev: Variant = int(_prev_fish.get(fid, 0))
        if c < prev:
            _decrease += 1
        if c > prev:
            var d: Variant = c - prev
            if d != 1:
                _burst += 1
            for k in range(d):
                _commit_events.append({"fish_id": fid, "sim": sim})
            _committed[fid] = int(_committed.get(fid, 0)) + d
        _prev_fish[fid] = c
        total += c
    if total - _last_total > 1:
        _burst += 1
    if total < _last_total:
        _decrease += 1
    _last_total = total


func _step() -> void:
    _main.call("_tick", DT)
    _watch()


func _tick(n: int) -> void:
    for i in range(n):
        _step()


func _step_until(cond: Callable, maxn: int) -> bool:
    for i in range(maxn):
        if bool(cond.call()):
            return true
        _step()
    return bool(cond.call())


# ---------------------------------------------------------------- assertions

func _section(title: String) -> void:
    _lines.append("")
    _lines.append("=== %s ===" % title)
    print("")
    print("=== %s ===" % title)


func _check(name: String, ok: bool, expected: String, actual: String) -> void:
    _checks += 1
    if not ok:
        _fail += 1
        _fail_names.append(name)
    var tag: Variant = "PASS" if ok else "FAIL"
    var line: Variant = "[CHECK] %s | expected=%s actual=%s | %s" % [name, expected, actual, tag]
    _lines.append(line)
    print(line)


func _check_eq(name: String, actual: Variant, expected: Variant) -> void:
    _check(name, actual == expected, str(expected), str(actual))


func _check_range(name: String, value: float, lo: float, hi: float) -> void:
    _check(name, value >= lo and value <= hi, "[%.2f..%.2f]" % [lo, hi], "%.3f" % value)


# ---------------------------------------------------------------- A 物品契约

func _section_a() -> void:
    _section("A item contract: fish catalog + inventory")
    var ids: Array = FISH.all_ids()
    _check("a.fish_count", ids.size() >= 5 and ids.size() <= 7, "5..7", str(ids.size()))
    var unique_ids: Dictionary = {}
    var unique_names: Dictionary = {}
    var bad_id: Variant = 0
    var bad_name: Variant = 0
    var bad_rarity: Variant = 0
    var bad_color: Variant = 0
    var bad_size: Variant = 0
    var bad_weight: Variant = 0
    var bad_seasons: Variant = 0
    var bad_weather: Variant = 0
    var unreachable: Variant = 0
    for raw_id in ids:
        var fid: Variant = String(raw_id)
        unique_ids[fid] = int(unique_ids.get(fid, 0)) + 1
        if not fid.begins_with("fish_"):
            bad_id += 1
        var def: Dictionary = FISH.get_def(fid)
        var dn: Variant = String(def.get("display_name", ""))
        if dn == "":
            bad_name += 1
        else:
            unique_names[dn] = int(unique_names.get(dn, 0)) + 1
        var rar: Variant = String(def.get("rarity", ""))
        if not (rar == "common" or rar == "uncommon" or rar == "rare"):
            bad_rarity += 1
        var col: Variant = String(def.get("color", ""))
        if not (col.length() == 7 and col.begins_with("#")):
            bad_color += 1
        var mn: Variant = float(def.get("min_size", -1.0))
        var mx: Variant = float(def.get("max_size", -1.0))
        if mn <= 0.0 or mx < mn:
            bad_size += 1
        if float(def.get("weight", 0.0)) <= 0.0:
            bad_weight += 1
        for s in (def.get("seasons", []) as Array):
            if not (String(s) in FISH.SEASON_IDS):
                bad_seasons += 1
        for w in (def.get("weather", []) as Array):
            if not (String(w) in FISH.WEATHER_KEYS):
                bad_weather += 1
        var avail: Variant = false
        for season in FISH.SEASON_IDS:
            for hour in range(24):
                for wk in FISH.WEATHER_KEYS:
                    if FISH.is_available(fid, String(season), hour, String(wk)):
                        avail = true
        if not avail:
            unreachable += 1
    var dup_ids: Variant = 0
    for k in unique_ids.keys():
        if int(unique_ids[k]) != 1:
            dup_ids += 1
    var dup_names: Variant = 0
    for k in unique_names.keys():
        if int(unique_names[k]) != 1:
            dup_names += 1
    _check_eq("a.unique_ids", dup_ids, 0)
    _check_eq("a.id_prefix", bad_id, 0)
    _check_eq("a.display_names", bad_name, 0)
    _check_eq("a.unique_display_names", dup_names, 0)
    _check_eq("a.rarity", bad_rarity, 0)
    _check_eq("a.color_hex", bad_color, 0)
    _check_eq("a.sizes", bad_size, 0)
    _check_eq("a.weight", bad_weight, 0)
    _check_eq("a.seasons", bad_seasons, 0)
    _check_eq("a.weather", bad_weather, 0)
    _check_eq("a.each_fish_reachable", unreachable, 0)

    var known: Array = _inv.call("known_item_ids") as Array
    var cat: Array = INV.catalog_ids()
    _check_eq("a.catalog_size", cat.size(), 16)
    _check_eq("a.known_equals_catalog", known, cat)
    _check_eq("a.fish_are_last", cat.slice(cat.size() - ids.size(), cat.size()), ids)
    var cat_bad: Variant = 0
    for i in range(ids.size()):
        var fid2: Variant = String(ids[i])
        if not bool(_inv.call("is_known_item", fid2)):
            cat_bad += 1
        if String(INV.item_category(fid2)) != "fish":
            cat_bad += 1
        if int(INV.category_rank(fid2)) != 2:
            cat_bad += 1
        if int(INV.catalog_index(fid2)) != cat.size() - ids.size() + i:
            cat_bad += 1
    _check_eq("a.fish_catalog_metadata", cat_bad, 0)
    _check_eq("a.unknown_fish_rejected", bool(_inv.call("is_known_item", "fish_dragon")), false)
    _check_eq("a.unknown_fish_add_rejected", bool(_inv.call("add_items", {"fish_dragon": 1})), false)
    _check_eq("a.STATE_VERSION", int(INV.STATE_VERSION), 1)

    var inv2: Object = INV.new()
    _check_eq("a.inv2.seed_grant", bool(inv2.call("grant_starting_seeds")), true)
    _check_eq("a.inv2.seed_once", bool(inv2.call("grant_starting_seeds")), false)
    _check_eq("a.inv2.add_fish", bool(inv2.call("add_items", {String(ids[0]): 2})), true)
    _check_eq("a.inv2.count", int(inv2.call("get_count", String(ids[0]))), 2)
    var snap: Dictionary = inv2.call("item_snapshot") as Dictionary
    _check_eq("a.inv2.snapshot", int(snap.get(String(ids[0]), 0)), 2)
    var ex: Dictionary = inv2.call("export_state") as Dictionary
    var ex_items: Dictionary = ex.get("items", {}) as Dictionary
    _check_eq("a.inv2.export_version", int(ex.get("version", -1)), 1)
    _check_eq("a.inv2.export_fish", int(ex_items.get(String(ids[0]), 0)), 2)

    var ex_before: Dictionary = inv2.call("export_state") as Dictionary
    var mixed: Variant = {String(ids[0]): 1, "fish_dragon": 1}
    _check_eq("a.inv2.atomic_mixed", bool(inv2.call("add_items", mixed)), false)
    _check_eq("a.inv2.atomic_unknown", bool(inv2.call("add_items", {"fish_dragon": 1})), false)
    _check_eq("a.inv2.atomic_zero", bool(inv2.call("add_items", {String(ids[0]): 0})), false)
    _check_eq("a.inv2.atomic_negative", bool(inv2.call("add_items", {String(ids[0]): -1})), false)
    _check_eq("a.inv2.atomic_fraction", bool(inv2.call("add_items", {String(ids[0]): 1.5})), false)
    _check_eq("a.inv2.atomic_too_large", bool(inv2.call("add_items", {String(ids[0]): int(INV.MAX_COUNT) + 1})), false)
    _check_eq("a.inv2.state_unchanged", inv2.call("export_state"), ex_before)

    var old_state: Variant = {"version": 1, "items": {"seed_wheat": 3, "wheat": 2}}
    _check_eq("a.old_state_restore", bool(inv2.call("restore_state", old_state)), true)
    _check_eq("a.old_state_seed", int(inv2.call("get_count", "seed_wheat")), 3)
    _check_eq("a.old_state_produce", int(inv2.call("get_count", "wheat")), 2)
    _check_eq("a.old_state_fish_zero", int(inv2.call("get_count", String(ids[0]))), 0)
    var ex_old: Dictionary = inv2.call("export_state") as Dictionary
    _check_eq("a.old_state_reexport", ex_old, old_state)

    _check_eq("a.zero_fish_restore", bool(inv2.call("restore_state", {"version": 1, "items": {String(ids[0]): 0}})), true)
    var ex_zero: Dictionary = inv2.call("export_state") as Dictionary
    _check_eq("a.zero_fish_dropped", (ex_zero.get("items", {}) as Dictionary).is_empty(), true)

    _check_eq("a.fish_state_restore", bool(inv2.call("restore_state", {"version": 1, "items": {String(ids[ids.size() - 1]): 4}})), true)
    _check_eq("a.fish_state_count", int(inv2.call("get_count", String(ids[ids.size() - 1]))), 4)

    var keep: Dictionary = inv2.call("export_state") as Dictionary
    _check_eq("a.unknown_restore_rejected", bool(inv2.call("restore_state", {"version": 1, "items": {"fish_dragon": 1}})), false)
    _check_eq("a.unknown_restore_atomic", inv2.call("export_state"), keep)
    _check_eq("a.bad_version_rejected", bool(inv2.call("restore_state", {"version": 99, "items": {}})), false)


# ---------------------------------------------------------------- B0 refusals

func _section_b0() -> void:
    _section("B0 start refusals (forced / not_playing / path_failed / no_spot)")
    _hold_patrol()
    _villager.set("_force", "probe_force")
    var r1: Dictionary = _main.call("start_fishing") as Dictionary
    _check_eq("b0.forced_mode", String(r1.get("reason", "")), "forced_mode")
    _villager.set("_force", "")
    _check_eq("b0.forced_inactive", _active(), false)

    _main.set("_mode", 0)
    var r2: Dictionary = _main.call("start_fishing") as Dictionary
    _check_eq("b0.not_playing", String(r2.get("reason", "")), "not_playing")
    _main.set("_mode", 1)

    var graph: Dictionary = _villager.get("graph") as Dictionary
    # P9 / P6-VISUAL-FIX：钓位已从沙滩 shore_stand 迁到码头木板 dock_fishing_stand，
    # 这里不再写死节点名：一律从 fishing_spot() 的权威数据取，换站位后仍能正确断边/删点。
    var spot_node := String((SPOTS.fishing_spot(graph) as Dictionary).get("node", ""))
    _check("b0.spot_node_present", spot_node != "", "非空", spot_node)

    _cut_spot_edges(true)
    var r3: Dictionary = _main.call("start_fishing") as Dictionary
    _check_eq("b0.path_failed", String(r3.get("reason", "")), "path_failed")
    _check_eq("b0.path_failed_inactive", _active(), false)
    _cut_spot_edges(false)
    _check_eq("b0.graph_valid_after_restore", (SPOTS.validate(graph) as Array).size(), 0)

    var nodes: Dictionary = graph.get("nodes", {}) as Dictionary
    var saved: Dictionary = (nodes.get(spot_node, {}) as Dictionary).duplicate(true)
    nodes.erase(spot_node)
    var r4: Dictionary = _main.call("start_fishing") as Dictionary
    _check_eq("b0.no_spot", String(r4.get("reason", "")), "no_spot")
    _check_eq("b0.no_spot_inactive", _active(), false)
    nodes[spot_node] = saved
    _check_eq("b0.graph_valid_after_spot_restore", (SPOTS.validate(graph) as Array).size(), 0)

    _spot = SPOTS.fishing_spot(graph) as Dictionary
    _check_eq("b0.spot_node", String(_spot.get("node", "")), spot_node)
    _check_eq("b0.spot_has_cast_point", _spot.has("cast_point"), true)
    _check("b0.spot_cast_on_water", absf(_spot_cast().y) <= 0.01, "y=0", "%.3f" % _spot_cast().y)
    print("[PROBE] spot point=%s cast=%s yaw=%.4f" % [str(_spot_point()), str(_spot_cast()), float(_spot.get("face_yaw", 0.0))])


## 断掉钓位节点的**所有**边（= 真的走不到钓位），再原样恢复。
## 不写死邻接节点名，因此钓位从沙滩迁到码头后仍然有效。
func _cut_spot_edges(on: bool) -> void:
    var graph: Dictionary = _villager.get("graph") as Dictionary
    var adj: Dictionary = graph.get("adj", {}) as Dictionary
    var spot_node := String((SPOTS.fishing_spot(graph) as Dictionary).get("node", ""))
    if spot_node == "":
        return
    if on:
        _saved_stand = (adj.get(spot_node, PackedStringArray()) as PackedStringArray).duplicate()
        _saved_sand = PackedStringArray()
        for nb in _saved_stand:
            var nb_id := String(nb)
            var arr := (adj.get(nb_id, PackedStringArray()) as PackedStringArray).duplicate()
            _saved_sand.append(nb_id)
            adj[nb_id] = _without_node(arr, spot_node)
        adj[spot_node] = PackedStringArray()
    else:
        for i in range(_saved_sand.size()):
            var nb_id := String(_saved_sand[i])
            var arr := (adj.get(nb_id, PackedStringArray()) as PackedStringArray).duplicate()
            if not arr.has(spot_node):
                arr.append(spot_node)
            adj[nb_id] = arr
        adj[spot_node] = _saved_stand.duplicate()


func _without_node(arr: PackedStringArray, node_id: String) -> PackedStringArray:
    var out: Variant = PackedStringArray()
    for v in arr:
        if String(v) != node_id:
            out.append(String(v))
    return out


# ---------------------------------------------------------------- B1 walk

func _section_b1() -> void:
    _section("B1 HUD press -> walk to real shore spot (no teleport)")
    _hold_patrol()
    var before_total: Variant = _total_fish()
    _hud.call("press_fishing_button")
    var fs: Variant = _fs()
    _check_eq("b1.active", bool(fs.get("active", false)), true)
    _check_eq("b1.phase_walking", String(fs.get("phase", "")), "walking")
    _check_eq("b1.spot", String(fs.get("spot", "")), String(_spot.get("node", "")))
    _check_eq("b1.rounds_zero", int(fs.get("rounds", -1)), 0)
    _check_eq("b1.fishing_seen", bool(_main.get("_fishing_seen")), true)
    _check_eq("b1.no_reward_yet", _total_fish(), before_total)
    var info: Variant = _rig_info()
    _check_eq("b1.rig_built", bool(info.get("built", false)), true)
    _check_eq("b1.rod_hidden_while_walking", bool(info.get("rod_visible", true)), false)
    _tick(4)
    var ui: Variant = _hud.call("fishing_ui_state") as Dictionary
    _check_eq("b1.hud_text_active", String(ui.get("text", "")), "停止钓鱼")
    _check_eq("b1.hud_active", bool(ui.get("active", false)), true)
    _check_eq("b1.hud_phase_walking", String(ui.get("phase", "")), "walking")
    _check("b1.hud_status_dock", String(ui.get("status_text", "")).contains("码头"), "contains 码头", String(ui.get("status_text", "")))
    _check_eq("b1.no_overlap_time", bool(ui.get("overlaps_time", true)), false)
    _check_eq("b1.no_overlap_weather", bool(ui.get("overlaps_weather", true)), false)

    var walk_start: Variant = _sim()
    var prev: Variant = _pos_now()
    var max_step: Variant = 0.0
    var teleports: Variant = 0
    var rod_seen: Variant = false
    var reward_seen: Variant = false
    var steps: Variant = 0
    for i in range(MAX_WALK_TICKS):
        if not _active():
            break
        if _phase() != "walking":
            break
        _step()
        steps += 1
        if not _active():
            break
        if _phase() != "walking":
            break
        var p: Variant = _pos_now()
        var d: Variant = Vector2(p.x - prev.x, p.z - prev.z).length()
        max_step = maxf(max_step, d)
        if d > 0.15:
            teleports += 1
        prev = p
        if int(_fs().get("rounds", 0)) != 0:
            reward_seen = true
        if bool(_rig_info().get("rod_visible", false)):
            rod_seen = true
    var walk_feel: Variant = _sim() - walk_start
    _timing["walk_feel"] = walk_feel
    _check_eq("b1.walk_teleports", teleports, 0)
    _check("b1.walk_step_max", max_step <= 0.15, "<=0.15", "%.4f" % max_step)
    _check_eq("b1.walk_no_reward", reward_seen, false)
    _check_eq("b1.walk_no_rod", rod_seen, false)
    fs = _fs()
    _check_eq("b1.arrived_active", bool(fs.get("active", false)), true)
    _check("b1.arrived_phase", String(fs.get("phase", "")) in ["casting", "waiting"], "casting|waiting", String(fs.get("phase", "")))
    var d_spot: Variant = Vector2(_pos_now().x - _spot_point().x, _pos_now().z - _spot_point().z).length()
    _check("b1.arrive_dist", d_spot <= 0.10, "<=0.10", "%.4f" % d_spot)
    var yaw_err: Variant = absf(wrapf(_yaw_now() - float(_spot.get("face_yaw", 0.0)), -PI, PI))
    _check("b1.arrive_yaw", yaw_err < 0.05, "<0.05", "%.4f" % yaw_err)
    _check_range("b1.walk_feel", walk_feel, 10.0, 60.0)
    print("[PROBE] walk steps=%d feel=%.2fs %s->%s" % [steps, walk_feel, str(prev), str(_pos_now())])


# ---------------------------------------------------------------- B2 cast/wait

func _section_b2() -> void:
    _section("B2 cast / bobber on water / wait / nibble / bite")
    var commits0: Variant = _commit_events.size()
    var cast_start: Variant = _sim()
    var reached: Variant = _step_until(func(): return _phase() == "waiting" or not _active(), 300)
    var cast_feel: Variant = _sim() - cast_start
    _check_eq("b2.reached_waiting", reached and _phase() == "waiting", true)
    if _phase() != "waiting":
        _check("b2.abort", false, "waiting", _phase())
        return
    var wait_start: Variant = _sim()
    var wd: Variant = float(_fs().get("wait_dur", 0.0))
    _check("b2.wait_range", (wd >= 5.99 and wd <= 16.01) or (wd >= 17.99 and wd <= 24.01), "6-16|18-24", "%.2f" % wd)
    _check_range("b2.cast_feel", cast_feel, 1.10, 1.45)
    _timing["cast_feel"] = cast_feel
    _timing["wait_dur"] = wd
    var info: Variant = _rig_info()
    _check_eq("b2.rod_visible", bool(info.get("rod_visible", false)), true)
    _check_eq("b2.line_visible", bool(info.get("line_visible", false)), true)
    _check_eq("b2.line_points", bool(info.get("line_has_points", false)), true)
    _check_eq("b2.bobber_visible", bool(info.get("bobber_visible", false)), true)
    var bob: Variant = info.get("bobber_world", Vector3.ZERO) as Vector3
    var cp: Variant = _spot_cast()
    _check("b2.bobber_on_water", absf(bob.y) <= 0.20, "|y|<=0.20", "%.3f" % bob.y)
    var bob_off: Variant = Vector2(bob.x - cp.x, bob.z - cp.z).length()
    _check("b2.bobber_at_cast_point", bob_off <= 0.25, "<=0.25", "%.3f" % bob_off)
    _check_eq("b2.no_catch_during_wait", _commit_events.size(), commits0)

    var nib: Variant = _step_until(func(): return bool(_fish_dict().get("nibble_early", false)) or _phase() != "waiting", 420)
    _check_eq("b2.nibble_early_seen", nib and bool(_fish_dict().get("nibble_early", false)), true)
    var nib_info: Variant = _rig_info()
    _check_eq("b2.nibble_early_active", bool(nib_info.get("nibble_active", false)), true)
    _check("b2.nibble_early_strength", absf(float(nib_info.get("nibble_amp", 0.0)) - 0.32) <= 0.011, "~0.32", "%.3f" % float(nib_info.get("nibble_amp", 0.0)))
    var base_y: Variant = (_rig_info().get("bobber_world", Vector3.ZERO) as Vector3).y
    var min_y: Variant = base_y
    for i in range(8):
        _step()
        var y: Variant = (_rig_info().get("bobber_world", Vector3.ZERO) as Vector3).y
        min_y = minf(min_y, y)
    _check("b2.nibble_dip", min_y <= -0.002, "bobber below surface", "%.4f" % min_y)
    var pre: Variant = _step_until(func(): return bool(_fish_dict().get("nibble_pre", false)) or _phase() != "waiting", 600)
    _check_eq("b2.nibble_pre_seen", pre and bool(_fish_dict().get("nibble_pre", false)), true)
    var pre_info: Variant = _rig_info()
    _check("b2.nibble_pre_strength", absf(float(pre_info.get("nibble_amp", 0.0)) - 0.62) <= 0.011, "~0.62", "%.3f" % float(pre_info.get("nibble_amp", 0.0)))

    var pre_splash: Variant = int(_rig_info().get("splash_events", 0))
    var bite_ok: Variant = _step_until(func(): return _phase() != "waiting" or not _active(), 700)
    _check_eq("b2.bite_phase", bite_ok and _phase() == "bite", true)
    var wait_feel: Variant = _sim() - wait_start
    _check_range("b2.wait_feel_matches_dur", wait_feel, wd - 0.30, wd + 0.35)
    var info2: Variant = _rig_info()
    var splash2: Variant = int(info2.get("splash_events", 0))
    _check("b2.bite_splash", splash2 > pre_splash, ">%d" % pre_splash, str(splash2))
    _check_eq("b2.bite_ripple", bool(info2.get("ripple_visible", false)), true)
    _tick(6)
    var by: Variant = (_rig_info().get("bobber_world", Vector3.ZERO) as Vector3).y
    _check("b2.bite_sink", by <= -0.03, "<=-0.03", "%.3f" % by)
    _check_eq("b2.no_catch_before_reel", _commit_events.size(), commits0)


# ---------------------------------------------------------------- B3 reel

func _section_b3() -> void:
    _section("B3 reel / catch reveal / exactly-once inventory commit")
    var commits_before: Variant = _commit_events.size()
    var bite_start: Variant = _sim()
    var reel_ok: Variant = _step_until(func(): return _phase() == "reeling" or not _active(), 60)
    var bite_feel: Variant = _sim() - bite_start + 6.0 * DT
    _check_eq("b3.reeling", reel_ok and _phase() == "reeling", true)
    _check_range("b3.bite_feel", bite_feel, 0.70, 0.95)
    _timing["bite_feel"] = bite_feel
    _step()
    _check_eq("b3.no_catch_while_reeling", bool(_rig_info().get("catch_visible", false)), false)
    var reel_start: Variant = _sim()
    var reveal_ok: Variant = _step_until(func(): return _phase() == "reveal" or not _active(), 120)
    var reel_feel: Variant = _sim() - reel_start
    _check_eq("b3.reveal", reveal_ok and _phase() == "reveal", true)
    _check_range("b3.reel_feel", reel_feel, 1.30, 1.55)
    _timing["reel_feel"] = reel_feel
    var fs: Variant = _fs()
    _check_eq("b3.rounds_one", int(fs.get("rounds", 0)), 1)
    var catches: Array = fs.get("catches", [])
    _check_eq("b3.catches_size", catches.size(), 1)
    _check_eq("b3.commit_exactly_one", _commit_events.size(), commits_before + 1)
    if catches.is_empty():
        _check("b3.abort", false, "1 catch", "0")
        return
    var catch: Variant = catches.back() as Dictionary
    var fid: Variant = String(catch.get("fish_id", ""))
    _check_eq("b3.catch_known", FISH.has_fish(fid), true)
    _check_eq("b3.catch_name", String(catch.get("display_name", "")), FISH.display_name(fid))
    var def: Dictionary = FISH.get_def(fid)
    var size: Variant = float(catch.get("size", -1.0))
    _check("b3.catch_size", size >= float(def.get("min_size", 0.0)) and size <= float(def.get("max_size", 0.0)), "within def", "%.2f" % size)
    var csim: Variant = float(catch.get("sim_seconds", -1.0))
    _check("b3.catch_sim", absf(csim - _sim()) <= 0.11, "%.2f" % _sim(), "%.2f" % csim)
    var cpos: Variant = catch.get("pos", Vector3.ZERO) as Vector3
    var pos_err: Variant = Vector2(cpos.x - _spot_point().x, cpos.z - _spot_point().z).length()
    _check("b3.catch_pos", pos_err <= 0.10, "<=0.10", "%.3f" % pos_err)
    _check_eq("b3.catch_season", String(catch.get("season", "")), String(CAL.parts(csim).get("season_id", "")))
    _check_eq("b3.catch_hour", int(catch.get("hour", -1)), int(fposmod(csim, 86400.0) / 3600.0))
    _check("b3.catch_weather", String(catch.get("weather_key", "")) in FISH.WEATHER_KEYS, "in WEATHER_KEYS", String(catch.get("weather_key", "")))
    var info: Variant = _rig_info()
    _check_eq("b3.catch_visible", bool(info.get("catch_visible", false)), true)
    _check_eq("b3.rig_fish_id", String(info.get("fish_id", "")), fid)
    _check_eq("b3.catch_committed_count", int(_committed.get(fid, 0)), 1)
    _check_eq("b3.inventory_count", int(_inv.call("get_count", fid)), 1)

    _tick(4)
    var ui: Variant = _hud.call("fishing_ui_state") as Dictionary
    _check_eq("b3.hud_rounds_one", int(ui.get("rounds", 0)), 1)
    _check("b3.hud_status_caught", String(ui.get("status_text", "")).contains("已钓 1 条"), "contains 已钓 1 条", String(ui.get("status_text", "")))

    var rv_start: Variant = _sim()
    var between_ok: Variant = _step_until(func(): return _phase() == "between" or not _active(), 60)
    var reveal_feel: Variant = _sim() - rv_start + 4.0 * DT
    _check_eq("b3.between", between_ok and _phase() == "between", true)
    _check_range("b3.reveal_feel", reveal_feel, 1.40, 1.60)
    _timing["reveal_feel"] = reveal_feel
    _check_eq("b3.catch_hidden_after_reveal", bool(_rig_info().get("catch_visible", true)), false)
    var bt_start: Variant = _sim()
    var cast_ok: Variant = _step_until(func(): return _phase() == "casting" or not _active(), 60)
    var between_feel: Variant = _sim() - bt_start
    _check_eq("b3.auto_next_cast", cast_ok and _phase() == "casting", true)
    _check_range("b3.between_feel", between_feel, 0.90, 1.15)
    _timing["between_feel"] = between_feel
    _check_eq("b3.rounds_still_one", int(_fs().get("rounds", 0)), 1)
    _check_eq("b3.no_extra_commit", _commit_events.size(), commits_before + 1)


# ---------------------------------------------------------------- B4 round 2

func _section_b4() -> void:
    _section("B4 round 2 auto + activity exclusion")
    var commits_before: Variant = _commit_events.size()
    var to_wait: Variant = _step_until(func(): return _phase() == "waiting" or not _active(), 400)
    _check_eq("b4.round2_waiting", to_wait and _phase() == "waiting", true)
    var route: Array = _main.call("_build_farm_patrol_route") as Array
    _check_eq("b4.route_size", route.size(), 9)
    var patrol_ok: Variant = bool(_villager.call("begin_farm_patrol", route, _main.call("farm"), "spring"))
    _check_eq("b4.patrol_refused", patrol_ok, false)
    var again: Dictionary = _villager.call("begin_fishing", Callable(self, "_reject_commit_true"), Callable()) as Dictionary
    _check_eq("b4.begin_again_refused", String(again.get("reason", "")), "already_fishing")
    var phase_before: Variant = _phase()
    _main.call("_update_farm_patrol", DT)
    _check_eq("b4.main_patrol_inactive", bool(_villager.call("farm_patrol_active")), false)
    _check_eq("b4.phase_stable", _phase(), phase_before)
    var r2: Variant = _step_until(func(): return int(_fs().get("rounds", 0)) >= 2 or not _active(), 1400)
    _check_eq("b4.round2_done", r2 and int(_fs().get("rounds", 0)) >= 2, true)
    _check_eq("b4.one_more_commit", _commit_events.size(), commits_before + 1)
    if _commit_events.size() >= 2:
        var d: Variant = float((_commit_events[-1] as Dictionary).get("sim", 0.0)) - float((_commit_events[-2] as Dictionary).get("sim", 0.0))
        _check("b4.inter_commit_gap", d >= 8.0, ">=8.0", "%.2f" % d)
    _tick(4)
    var ui: Variant = _hud.call("fishing_ui_state") as Dictionary
    _check_eq("b4.hud_rounds_two", int(ui.get("rounds", 0)), 2)
    _check("b4.hud_status_two", String(ui.get("status_text", "")).contains("已钓 2 条"), "contains 已钓 2 条", String(ui.get("status_text", "")))


# ---------------------------------------------------------------- B5 cancel

func _section_b5() -> void:
    _section("B5 player stop while fishing")
    var commits_before: Variant = _commit_events.size()
    _hold_patrol()
    _hud.call("press_fishing_button")
    _step()
    _check_eq("b5.inactive", _active(), false)
    var last: Dictionary = _villager.call("fishing_last") as Dictionary
    _check_eq("b5.outcome", String(last.get("outcome", "")), "cancelled")
    _check_eq("b5.reason", String(last.get("reason", "")), "player_stop")
    _check_eq("b5.rounds", int(last.get("rounds", -1)), 2)
    _check_eq("b5.catches_kept", (last.get("catches", []) as Array).size(), 2)
    _tick(400)
    _check_eq("b5.no_reward_after_stop", _commit_events.size(), commits_before)
    var info: Variant = _rig_info()
    _check_eq("b5.rig_rod_cleared", bool(info.get("rod_visible", true)), false)
    _check_eq("b5.rig_bobber_cleared", bool(info.get("bobber_visible", true)), false)
    _check_eq("b5.rig_catch_cleared", bool(info.get("catch_visible", true)), false)
    _tick(4)
    var ui: Variant = _hud.call("fishing_ui_state") as Dictionary
    _check_eq("b5.hud_text_idle", String(ui.get("text", "")), "钓鱼")
    _check_eq("b5.hud_status_empty", String(ui.get("status_text", "")), "")
    _check_eq("b5.fishing_seen_false", bool(_main.get("_fishing_seen")), false)
    _check_eq("b5.inventory_kept", _total_fish(), 2)


# ---------------------------------------------------------------- B6 pause

func _section_b6() -> void:
    _section("B6 pause freezes fishing (no rewards while paused)")
    _hold_patrol()
    _hud.call("press_fishing_button")
    var to_wait: Variant = _step_until(func(): return _phase() == "waiting" or not _active(), 1400)
    _check_eq("b6.waiting", to_wait and _phase() == "waiting", true)
    if _phase() != "waiting":
        return
    var sim_before: Variant = _sim()
    var feel_before: Variant = float(_fish_dict().get("feel", -1.0))
    var bob_before: Variant = _rig_info().get("bobber_world", Vector3.ZERO) as Vector3
    var commits_before: Variant = _commit_events.size()
    _main.set("_paused", true)
    _tick(200)
    _check_eq("b6.paused_sim_frozen", _sim(), sim_before)
    _check_eq("b6.paused_phase", _phase(), "waiting")
    _check_eq("b6.paused_feel_frozen", float(_fish_dict().get("feel", -1.0)), feel_before)
    _check_eq("b6.paused_no_commit", _commit_events.size(), commits_before)
    var bob_after: Variant = _rig_info().get("bobber_world", Vector3.ZERO) as Vector3
    _check("b6.paused_bobber_frozen", bob_after.distance_to(bob_before) <= 0.0001, str(bob_before), str(bob_after))
    _main.set("_paused", false)
    _hold_patrol()
    var rounds_before: Variant = int(_fs().get("rounds", 0))
    var resumed: Variant = _step_until(func(): return int(_fs().get("rounds", 0)) > rounds_before or not _active(), 1400)
    _check_eq("b6.resume_works", resumed and int(_fs().get("rounds", 0)) > rounds_before, true)
    var last: Dictionary = _villager.call("fishing_last") as Dictionary
    _main.call("stop_fishing", "probe_pause_done")
    _tick(4)
    _check_eq("b6.finished", _active(), false)


# ---------------------------------------------------------------- B7 jumps

func _section_b7() -> void:
    _section("B7 time jumps: safe cancel, no burst credit, restartable")
    _jump_case("time_set", "time_set")
    _jump_case("forward_2d", "forward")
    _jump_case("rewind_1h", "rewind")


func _begin_waiting(tag: String) -> bool:
    _hold_patrol()
    if _active():
        _main.call("stop_fishing", "probe_reset")
        _tick(4)
    _hud.call("press_fishing_button")
    var ok: Variant = _step_until(func(): return _phase() == "waiting" or not _active(), 1600)
    _check_eq("b7." + tag + ".reach_waiting", ok and _phase() == "waiting", true)
    return ok and _phase() == "waiting"


func _jump_case(tag: String, mode: String) -> void:
    if not _begin_waiting(tag):
        return
    var commits_before: Variant = _commit_events.size()
    if mode == "time_set":
        var p: Dictionary = CAL.parts(_sim())
        _main.call("_on_time_set", fposmod(float(p.get("sod", 43200.0)) + 900.0, 86400.0))
    else:
        var target: Variant = _sim() + (172800.0 if mode == "forward" else -3600.0)
        var q: Dictionary = CAL.parts(target)
        _main.call("_jump_datetime", int(q.get("year", 2026)), int(q.get("month", 1)), int(q.get("day", 1)), int(q.get("hour", 12)), int(q.get("minute", 0)), 0)
    _hold_patrol()
    _tick(6)
    _check_eq("b7." + tag + ".cancelled", _active(), false)
    var last: Dictionary = _villager.call("fishing_last") as Dictionary
    _check_eq("b7." + tag + ".outcome", String(last.get("outcome", "")), "cancelled")
    _check_eq("b7." + tag + ".reason", String(last.get("reason", "")), "time_jump")
    _tick(300)
    _check_eq("b7." + tag + ".no_burst", _commit_events.size(), commits_before)
    var info: Variant = _rig_info()
    _check_eq("b7." + tag + ".rig_cleared", bool(info.get("rod_visible", true)) or bool(info.get("bobber_visible", true)) or bool(info.get("catch_visible", true)), false)
    _tick(4)
    var ui: Variant = _hud.call("fishing_ui_state") as Dictionary
    _check_eq("b7." + tag + ".hud_restored", String(ui.get("text", "")), "钓鱼")
    _check_eq("b7." + tag + ".phase_stable", _phase(), "")
    _main.call("_on_time_set", 43200.0)
    _hold_patrol()
    _tick(4)
    _check_eq("b7." + tag + ".awake_again", _sleeping(), false)
    var restart: Dictionary = _main.call("start_fishing") as Dictionary
    _check_eq("b7." + tag + ".restart_ok", bool(restart.get("ok", false)), true)
    _check_eq("b7." + tag + ".restart_active", _active(), true)
    _main.call("stop_fishing", "probe_after_jump")
    _tick(4)
    _check_eq("b7." + tag + ".inactive_again", _active(), false)


# ---------------------------------------------------------------- B8 inventory

func _section_b8() -> void:
    _section("B8 inventory commit failure")
    _hold_patrol()
    if _active():
        _main.call("stop_fishing", "probe_reset_b8")
        _tick(4)
    var commits_before: Variant = _commit_events.size()
    var start: Dictionary = _villager.call("begin_fishing", Callable(self, "_reject_commit"), Callable()) as Dictionary
    _check_eq("b8.started", bool(start.get("ok", false)), true)
    var done: Variant = _step_until(func(): return not _active(), 2000)
    _check_eq("b8.ended", done and not _active(), true)
    var last: Dictionary = _villager.call("fishing_last") as Dictionary
    _check_eq("b8.outcome", String(last.get("outcome", "")), "inventory_failed")
    _check_eq("b8.reason", String(last.get("reason", "")), "commit_failed")
    _check_eq("b8.error_field", String(last.get("error", "")), "inventory_failed")
    _check_eq("b8.catches_zero", (last.get("catches", []) as Array).size(), 0)
    _check_eq("b8.rounds_zero", int(last.get("rounds", -1)), 0)
    _check_eq("b8.no_credit", _commit_events.size(), commits_before)
    var info: Variant = _rig_info()
    _check_eq("b8.rig_cleared", bool(info.get("rod_visible", true)) or bool(info.get("catch_visible", true)), false)
    _main.call("start_fishing")
    _tick(4)
    _check_eq("b8.recovered", _active(), true)
    _main.call("stop_fishing", "probe_recover")
    _tick(4)
    _check_eq("b8.recovered_inactive", _active(), false)


func _reject_commit(_fish_id: String, _size: float) -> bool:
    return false


func _reject_commit_true(_fish_id: String, _size: float) -> bool:
    return true


# ---------------------------------------------------------------- C conditions

func _section_c() -> void:
    _section("C fish conditions / deterministic seeded pick")
    _check_eq("c.weather_precip_rain", FISH.weather_key("clear", "rain", 0.0), "rain")
    _check_eq("c.weather_precip_snow", FISH.weather_key("clear", "snow", 0.0), "snow")
    _check_eq("c.weather_type_rain", FISH.weather_key("rain", "none", 0.0), "rain")
    _check_eq("c.weather_cloudy", FISH.weather_key("clear", "none", 0.6), "cloudy")
    _check_eq("c.weather_clear", FISH.weather_key("clear", "none", 0.0), "clear")
    _check_eq("c.weather_cloudy_edge", FISH.weather_key("partly", "none", 0.45), "cloudy")

    var rng_a: Variant = RandomNumberGenerator.new()
    rng_a.seed = 20261024
    var rng_b: Variant = RandomNumberGenerator.new()
    rng_b.seed = 20261024
    var picks_a: Array = []
    var picks_b: Array = []
    for i in range(50):
        var season: Variant = String(FISH.SEASON_IDS[i % FISH.SEASON_IDS.size()])
        var hour: Variant = i % 24
        var wk: Variant = String(FISH.WEATHER_KEYS[(i * 3) % FISH.WEATHER_KEYS.size()])
        picks_a.append(String(FISH.pick(season, hour, wk, rng_a)))
        picks_b.append(String(FISH.pick(season, hour, wk, rng_b)))
    _check_eq("c.seeded_determinism", picks_a, picks_b)

    var combo_total: Variant = 0
    var fallback_missing: Variant = 0
    var pick_bad: Variant = 0
    var rng2: Variant = RandomNumberGenerator.new()
    rng2.seed = 424242
    for season in FISH.SEASON_IDS:
        for hour in range(24):
            for wk in FISH.WEATHER_KEYS:
                combo_total += 1
                if FISH.weight_for(String(FISH.fallback_id()), String(season), hour, String(wk)) <= 0.0:
                    fallback_missing += 1
                var picked: Variant = String(FISH.pick(String(season), hour, String(wk), rng2))
                if not FISH.has_fish(picked) or not FISH.is_available(picked, String(season), hour, String(wk)):
                    pick_bad += 1
    _check_eq("c.exhaustive_combos", combo_total, 384)
    _check_eq("c.fallback_always_available", fallback_missing, 0)
    _check_eq("c.pick_always_valid", pick_bad, 0)

    _check_eq("c.koi_winter", FISH.is_available("fish_koi", "winter", 8, "clear"), false)
    _check_eq("c.koi_rain", FISH.is_available("fish_koi", "summer", 8, "rain"), false)
    _check_eq("c.koi_ok", FISH.is_available("fish_koi", "summer", 8, "clear"), true)
    _check_eq("c.salmon_autumn", FISH.is_available("fish_salmon", "autumn", 6, "rain"), true)
    _check_eq("c.salmon_summer", FISH.is_available("fish_salmon", "summer", 6, "clear"), false)
    _check_eq("c.puffer_spring", FISH.is_available("fish_puffer", "spring", 10, "clear"), false)
    _check_eq("c.puffer_rain", FISH.is_available("fish_puffer", "summer", 10, "rain"), false)
    _check_eq("c.puffer_ok", FISH.is_available("fish_puffer", "summer", 10, "clear"), true)


# ---------------------------------------------------------------- D HUD/backpack

func _section_d() -> void:
    _section("D HUD button + backpack regression")
    var ui: Variant = _hud.call("fishing_ui_state") as Dictionary
    _check_eq("d.pill_exists", bool(ui.get("exists", false)), true)
    _check_eq("d.pill_text_idle", String(ui.get("text", "")), "钓鱼")
    _check_eq("d.pill_active_idle", bool(ui.get("active", true)), false)
    _check_eq("d.no_overlap_time", bool(ui.get("overlaps_time", true)), false)
    _check_eq("d.no_overlap_weather", bool(ui.get("overlaps_weather", true)), false)
    var rect: Variant = ui.get("rect", Rect2()) as Rect2
    var srect: Variant = ui.get("status_rect", Rect2()) as Rect2
    _check("d.status_right_of_pill", srect.position.x >= rect.end.x - 0.5, ">=%.1f" % rect.end.x, "%.1f" % srect.position.x)
    _check_eq("d.no_fishing_shortcut", InputMap.has_action("fishing"), false)

    var open_before: Variant = bool(_hud.call("backpack_open"))
    _main.call("_handle_key", KEY_B)
    var open_after: Variant = bool(_hud.call("backpack_open"))
    _check_eq("d.b_key_toggles_backpack", open_after != open_before, true)
    if not open_after:
        _main.call("_handle_key", KEY_B)
    _check_eq("d.bag_open", bool(_hud.call("backpack_open")), true)
    _tick(4)

    var bag: Variant = _hud.call("bag_display_state") as Dictionary
    var order: Array = bag.get("order", [])
    var counts: Dictionary = bag.get("counts", {})
    var names: Dictionary = bag.get("names", {})
    var cat: Array = INV.catalog_ids()
    _check_eq("d.bag_order_size", order.size(), cat.size())
    var counts_ok: Variant = true
    for item_id in cat:
        if int(counts.get(item_id, -1)) != int(_inv.call("get_count", item_id)):
            counts_ok = false
    _check_eq("d.bag_counts_match", counts_ok, true)
    var fish_names_ok: Variant = true
    for fid in FISH.all_ids():
        if String(names.get(fid, "")) != String(FISH.display_name(fid)):
            fish_names_ok = false
    _check_eq("d.bag_fish_names", fish_names_ok, true)
    var zero_present: Variant = false
    for fid2 in FISH.all_ids():
        if int(_inv.call("get_count", fid2)) == 0 and int(counts.get(fid2, -1)) == 0:
            zero_present = true
    _check_eq("d.bag_zero_count_fish", zero_present, true)

    var sort_count_before: Variant = int(bag.get("sort_count", 0))
    var sorted_ok: Variant = bool(_hud.call("sort_backpack"))
    _tick(2)
    var bag2: Variant = _hud.call("bag_display_state") as Dictionary
    var order2: Array = bag2.get("order", [])
    var counts2: Dictionary = bag2.get("counts", {})
    _check_eq("d.sort_returns_true", sorted_ok, true)
    # P7-FINALIZE：用户要求「整理」后的规范顺序改为「作物 5 → 鱼 6 → 种子 5」，
    # 同类别内部按作物/鱼类目录顺序。这里按分组断言 + 集合断言，两者都不放宽要求。
    var grp_ok: Variant = true
    for x in order2.slice(0, 5):
        if String(x).begins_with("seed_") or String(x).begins_with("fish_"):
            grp_ok = false
    for x2 in order2.slice(5, 11):
        if not String(x2).begins_with("fish_"):
            grp_ok = false
    for x3 in order2.slice(11, 16):
        if not String(x3).begins_with("seed_"):
            grp_ok = false
    _check("d.sort_order_catalog", grp_ok and order2.slice(5, 11) == FISH.all_ids(),
        "作物 5 → 鱼 6 → 种子 5", str(order2))
    var set_a: Array = order2.duplicate()
    set_a.sort()
    var set_b: Array = cat.duplicate()
    set_b.sort()
    _check_eq("d.sort_order_set", set_a, set_b)
    _check_eq("d.sort_flag", bool(bag2.get("sorted", false)), true)
    _check("d.sort_count_up", int(bag2.get("sort_count", 0)) > sort_count_before, ">%d" % sort_count_before, str(int(bag2.get("sort_count", 0))))
    var same_counts: Variant = true
    for item_id2 in cat:
        if int(counts2.get(item_id2, -1)) != int(counts.get(item_id2, -1)):
            same_counts = false
    _check_eq("d.sort_counts_unchanged", same_counts, true)
    var layout: Variant = _hud.call("bag_layout_info") as Dictionary
    _check_eq("d.bag_panel_on_screen", bool(layout.get("panel_on_screen", false)), true)
    _hud.call("close_backpack")
    _check_eq("d.bag_closed", bool(_hud.call("backpack_open")), false)
    _check_eq("d.time_pill_intact", String((_hud.call("fishing_ui_state") as Dictionary).get("text", "")), "钓鱼")


# ---------------------------------------------------------------- E sim contract

func _section_e() -> void:
    _section("E sim-time contract + inventory reconciliation")
    _check_eq("e.commit_events", _commit_events.size(), 3)
    var prev: Variant = -1.0
    var increasing: Variant = true
    for ev in _commit_events:
        var s: Variant = float((ev as Dictionary).get("sim", 0.0))
        if s <= prev:
            increasing = false
        prev = s
    _check_eq("e.commit_sim_increasing", increasing, true)
    var min_delta: Variant = 999999.0
    for i in range(1, _commit_events.size()):
        var d: Variant = float((_commit_events[i] as Dictionary).get("sim", 0.0)) - float((_commit_events[i - 1] as Dictionary).get("sim", 0.0))
        min_delta = minf(min_delta, d)
    _check("e.round_gap", min_delta >= 8.0, ">=8.0", "%.2f" % min_delta)
    _check_eq("e.no_burst", _burst, 0)
    _check_eq("e.no_decrease", _decrease, 0)

    var round1: Variant = float(_timing.get("cast_feel", 0.0)) + float(_timing.get("wait_dur", 0.0)) + float(_timing.get("bite_feel", 0.0)) + float(_timing.get("reel_feel", 0.0)) + float(_timing.get("reveal_feel", 0.0)) + float(_timing.get("between_feel", 0.0))
    _timing["round1_feel"] = round1
    _check_range("e.round1_feel", round1, 11.0, 26.0)

    var mismatch: Variant = 0
    var total: Variant = 0
    for fid in FISH.all_ids():
        var want: Variant = int(_committed.get(fid, 0))
        var got: Variant = int(_inv.call("get_count", fid))
        total += got
        if want != got:
            mismatch += 1
    _check_eq("e.reconcile_per_fish", mismatch, 0)
    _check_eq("e.reconcile_total", total, _commit_events.size())
    var snap: Dictionary = _inv.call("item_snapshot") as Dictionary
    var snap_total: Variant = 0
    for fid3 in FISH.all_ids():
        snap_total += int(snap.get(fid3, 0))
    _check_eq("e.snapshot_matches", snap_total, total)
    var ex: Dictionary = _inv.call("export_state") as Dictionary
    var ex_items: Dictionary = ex.get("items", {}) as Dictionary
    var ex_fish: Variant = 0
    for fid4 in FISH.all_ids():
        ex_fish += int(ex_items.get(fid4, 0))
    _check_eq("e.export_matches", ex_fish, total)
    _check_eq("e.version_unchanged", int(ex.get("version", -1)), 1)
    var exp_log: Array = []
    for ev2 in _commit_events:
        exp_log.append("%s@%.1f" % [String((ev2 as Dictionary).get("fish_id", "")), float((ev2 as Dictionary).get("sim", 0.0))])
    print("[PROBE] commits=%s" % str(exp_log))
    print("[PROBE] timing=%s" % str(_timing))


# ---------------------------------------------------------------- report

func _write_report() -> void:
    _lines.append("")
    _lines.append("[SUMMARY] checks=%d fail=%d" % [_checks, _fail])
    _lines.append("[RESULT] %s" % ("PASS" if _fail == 0 else "FAIL"))
    var log_path: Variant = _out_dir + "/probe_p9_fishing.log"
    var f: Variant = FileAccess.open(log_path, FileAccess.WRITE)
    if f != null:
        f.store_string(String.chr(10).join(_lines) + String.chr(10))
        f.close()
    var data: Variant = {
        "checks": _checks,
        "fail": _fail,
        "fail_names": _fail_names,
        "headless": DisplayServer.get_name() == "headless",
        "timing": _timing,
        "commit_events": _commit_events,
        "committed": _committed,
        "spot": _spot,
        "burst": _burst,
        "decrease": _decrease,
        "sim_seconds": _sim(),
    }
    var jp: Variant = _out_dir + "/probe_p9_fishing.json"
    var jf: Variant = FileAccess.open(jp, FileAccess.WRITE)
    if jf != null:
        jf.store_string(JSON.stringify(data, "  "))
        jf.close()
