extends SceneTree

## P7 联合探针：农田巡田 × 岛民自主钓鱼 的活动交界、库存对账与状态/节点泄漏。
## 只读断言 + 正式入口调用（HUD 按钮 / main.start_fishing / main._tick），不修改生产代码。
## 与既有探针互补：P4 探针覆盖巡田内部，P6 探针覆盖钓鱼内部，本探针覆盖两者交替。

const FISH := preload("res://scripts/isle_fish.gd")
const CAL := preload("res://scripts/isle_calendar.gd")

const DEFAULT_OUT := "D:/休闲小岛幻境/开发产物/P9/P7/after/joint"
const DT := 0.05
const MAX_WALK := 2200

var _out_dir: Variant = DEFAULT_OUT
var _lines: Array = []
var _checks: int = 0
var _fail: int = 0
var _fail_names: Array = []

var _main: Node = null
var _hud: Node = null
var _villager: Node = null
var _farm: Object = null
var _inv: Object = null

var _today: int = 0
var _nodes_cycle1: int = -1
var _rig_nodes: int = -1
var _prev: Dictionary = {}
var _committed: Dictionary = {}
var _commit_events: Array = []
var _decrease: int = 0
var _burst: int = 0
var _last_total: int = 0


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
	print("=== P7 joint farm x fishing probe ===")
	print("[PROBE] out=%s" % _out_dir)
	await _boot()
	_section_j0()
	_section_j15()
	_section_j1()
	_section_j2()
	_section_j3()
	_section_j4()
	_section_j5()
	_section_j6()
	_section_j7()
	_section_j8()
	_section_j9()
	_section_j10()
	_section_j11()
	_section_j12()
	_section_j13()
	_section_j14()
	_section_j16()
	_write_report()
	print("[SUMMARY] checks=%d fail=%d" % [_checks, _fail])
	if _fail > 0:
		print("[FAIL_NAMES] %s" % ", ".join(_fail_names))
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
	_farm = _main.call("farm") as Object
	_main.set("_time_source", "sim")
	_main.set("_realtime", false)
	_main.set("_day_length", 86400.0)
	_main.set("_paused", false)
	# _on_time_set 只接受"当天秒数"（0..86399），不接受绝对时间戳。
	_main.call("_on_time_set", 12.0 * 3600.0)
	_today = int(floor(_sim() / 86400.0))
	_hold_patrol()
	_step()
	_force_weather("clear")
	_init_watch()
	print("[PROBE] hud=%s villager=%s farm=%s inv=%s" % [str(_hud != null), str(_villager != null), str(_farm != null), str(_inv != null)])
	print("[PROBE] boot sim=%.0f today=%d rate=%.3f" % [_sim(), _today, float(_main.get("_sim_rate"))])


func _sim() -> float:
	return float(_main.get("_sim_seconds"))


## 以启动日为锚点的第 day_offset 天 00:00（绝对模拟时间）；只用于探针注入。
func _day_base(day_offset: int) -> float:
	return float((_today + day_offset) * 86400)


func _hold_patrol() -> void:
	_main.set("_patrol_handled_day", int(floor(_sim() / 86400.0)))
	_main.set("_patrol_rewind_day", -2147483647)


func _set_sim(t: float) -> void:
	_main.set("_sim_seconds", t)
	if _farm != null:
		_farm.call("advance_to", t)
	_main.call("_update_lighting")
	if _villager != null:
		_villager.set("_sim_now", t)
		_villager.set("_last_sim", t)
	_main.set("_sim_delta", 0.0)


func _force_weather(type_id: String) -> void:
	var wx: Object = _main.get("_weather") as Object
	if wx == null:
		return
	var real: String = String({"rain": "mid_rain", "snow": "heavy_snow"}.get(type_id, type_id))
	wx.call("set_manual_type", real)
	wx.call("reset", float(_main.get("_sim_seconds")))
	_main.call("_update_weather", 0.0, true)


# ---------------------------------------------------------------- fishing

func _fs() -> Dictionary:
	return _villager.call("fishing_state") as Dictionary


func _phase() -> String:
	return str(_fs().get("phase", ""))


func _fishing_active() -> bool:
	return bool(_villager.call("fishing_active"))


func _press() -> void:
	_hud.call("press_fishing_button")


func _fish_start() -> Dictionary:
	var res: Dictionary = _main.call("start_fishing") as Dictionary
	_step()
	return res


func _fish_stop(reason: String = "player_stop") -> void:
	if _fishing_active():
		_main.call("stop_fishing", reason)
		_step()


func _rig() -> Node:
	return _villager.get("_fish_rig") as Node


func _rig_info() -> Dictionary:
	var r: Variant = _rig()
	if r == null or not r.has_method("debug_info"):
		return {}
	return r.call("debug_info") as Dictionary


# ---------------------------------------------------------------- patrol

func _patrol_state() -> Dictionary:
	return _main.call("farm_patrol_state") as Dictionary


func _patrol_active() -> bool:
	return bool(_villager.call("farm_patrol_active"))


func _patrol_last() -> Dictionary:
	return _villager.call("farm_patrol_last") as Dictionary


func _scheduler_clear() -> void:
	if _patrol_active():
		_villager.call("cancel_farm_patrol", "probe_reset")
	_main.set("_patrol_handled_day", -2147483647)
	_main.set("_patrol_rewind_day", -2147483647)
	_main.set("_patrol_phase", "idle")
	_main.set("_patrol_last", {})
	_main.set("_patrol_start_count", 0)
	_main.set("_patrol_deadline_day", -2147483647)
	_main.set("_patrol_deadline", 0.0)
	_main.set("_patrol_retry_timer", 0.0)


## 把调度器重置到某个游戏日 08:00 之后的第一帧，交给正式 _tick 启动。
func _sched_arm(day_offset: int, secs: float) -> void:
	_force_weather("clear")
	_scheduler_clear()
	_set_sim(_day_base(day_offset) + secs)


# ---------------------------------------------------------------- inventory watch

func _init_watch() -> void:
	_prev.clear()
	_committed.clear()
	_commit_events.clear()
	var total: int = 0
	for fid in FISH.all_ids():
		var c: int = int(_inv.call("get_count", fid))
		_prev[fid] = c
		_committed[fid] = 0
		total += c
	_last_total = total


func _watch() -> void:
	var sim: float = _sim()
	var total: int = 0
	for fid in FISH.all_ids():
		var c: int = int(_inv.call("get_count", fid))
		var prev: int = int(_prev.get(fid, 0))
		if c < prev:
			_decrease += 1
		if c > prev:
			var d: int = c - prev
			if d != 1:
				_burst += 1
			for k in range(d):
				_commit_events.append({"fish_id": str(fid), "sim": sim})
			_committed[fid] = int(_committed.get(fid, 0)) + d
		_prev[fid] = c
		total += c
	if total - _last_total > 1:
		_burst += 1
	if total < _last_total:
		_decrease += 1
	_last_total = total


func _fish_total() -> int:
	var total: int = 0
	for fid in FISH.all_ids():
		total += int(_inv.call("get_count", fid))
	return total


func _snap() -> Dictionary:
	return _inv.call("item_snapshot") as Dictionary


## 全部物品（含种子/作物/鱼）的总数量：用于"巡田事务没有重复发放/消耗"的对账。
func _inventory_total() -> int:
	return int(_inv.call("total_count"))


# ---------------------------------------------------------------- stepping

func _step() -> void:
	_main.call("_tick", DT)
	_watch()


func _tick_n(n: int) -> void:
	for i in range(n):
		_step()


func _drive(cond: Callable, maxn: int) -> bool:
	for i in range(maxn):
		if bool(cond.call()):
			return true
		_step()
	return bool(cond.call())


func _drive_phase(want: String, maxn: int) -> bool:
	return _drive(func() -> bool: return _phase() == want, maxn)


func _drive_patrol_idle(maxn: int) -> int:
	for i in range(maxn):
		if not _patrol_active():
			return i
		_step()
	return maxn


# ---------------------------------------------------------------- node counting

func _count_nodes(n: Node) -> int:
	var c: int = 1
	for ch in n.get_children():
		c += _count_nodes(ch)
	return c


func _count_named(n: Node, names: Array) -> int:
	var c: int = 0
	if String(n.name) in names:
		c += 1
	for ch in n.get_children():
		c += _count_named(ch, names)
	return c


const RIG_NAMES := ["Rod", "RodMesh", "Line", "Bobber", "BobberMesh", "Splash", "Ripple", "Catch", "Fish"]


func _rig_named_total() -> int:
	var v: Variant = _rig()
	if v == null or not is_instance_valid(v):
		return 0
	return _count_named(v as Node, RIG_NAMES)


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
	var tag: String = "PASS" if ok else "FAIL"
	var line: String = "[CHECK] %s | expected=%s actual=%s | %s" % [name, expected, actual, tag]
	_lines.append(line)
	print(line)


func _check_eq(name: String, actual: Variant, expected: Variant) -> void:
	_check(name, actual == expected, str(expected), str(actual))


func _check_true(name: String, ok: bool, expected: String = "true", actual: String = "false") -> void:
	_check(name, ok, expected, expected if ok else actual)


# ---------------------------------------------------------------- J0

func _section_j0() -> void:
	_section("J0 boot invariants")
	_check_eq("j0.hud", _hud != null, true)
	_check_eq("j0.villager", _villager != null, true)
	_check_eq("j0.farm", _farm != null, true)
	_check_eq("j0.inventory", _inv != null, true)
	var slots: Array = (_farm.call("export_state") as Dictionary).get("slots", [])
	_check_eq("j0.farm_slots", slots.size(), 9)
	_check_eq("j0.fishing_idle", _fishing_active(), false)
	_check_eq("j0.patrol_idle", _patrol_active(), false)
	_check_eq("j0.rig_lazy", _rig(), null)
	var ids: Array = FISH.all_ids()
	_check("j0.fish_catalog", ids.size() >= 5, ">=5", str(ids.size()))
	var known: bool = true
	for fid in ids:
		if not bool(_inv.call("is_known_item", str(fid))):
			known = false
	_check_eq("j0.fish_known_items", known, true)
	_check_eq("j0.inventory_grant_once", int(_main.get("_inventory_grant_count")), 1)
	print("[PROBE] fish_total=%d items=%d" % [_fish_total(), (_snap() as Dictionary).size()])


# ---------------------------------------------------------------- J1

func _section_j1() -> void:
	_section("J1 patrol active -> fishing refused (single activity authority)")
	_sched_arm(1, 8 * 3600.0 + 5.0)
	_drive(func() -> bool: return _patrol_active(), 40)
	_check_true("j1.patrol_started", _patrol_active())
	_check_eq("j1.patrol_phase", str(_patrol_state().get("phase", "")), "running")
	var res: Dictionary = _main.call("start_fishing") as Dictionary
	_check_eq("j1.start_refused", bool(res.get("ok", true)), false)
	_check_eq("j1.refuse_reason", str(res.get("reason", "")), "patrol_running")
	_press()
	_step()
	_check_eq("j1.hud_press_no_state", _fishing_active(), false)
	# 鱼竿装置是懒加载单例：J15 已经真实抛过竿，这里只要求"拒绝后没有任何可见渔具"。
	var ri: Dictionary = _rig_info()
	_check_eq("j1.rig_hidden_on_refuse", bool(ri.get("line_visible", false)) or bool(ri.get("bobber_visible", false)), false)
	_check_eq("j1.inventory_unchanged", _fish_total(), 0)
	_check_true("j1.patrol_still_active", _patrol_active())
	_villager.call("cancel_farm_patrol", "probe_cleanup")
	_step()
	_check_eq("j1.patrol_cancelled", _patrol_active(), false)
	_hold_patrol()


# ---------------------------------------------------------------- J2

func _section_j2() -> void:
	_section("J2 08:00 crosses while fishing -> patrol does not start, runs after stop")
	_init_watch()
	_force_weather("clear")
	_set_sim(_day_base(1) + 7 * 3600.0 + 59.0 * 60.0 + 55.0)
	_main.set("_patrol_handled_day", _today)
	_main.set("_patrol_phase", "idle")
	_main.set("_patrol_last", {})
	_main.set("_patrol_start_count", 0)
	_main.set("_patrol_deadline_day", -2147483647)
	_main.set("_patrol_deadline", 0.0)
	_main.set("_patrol_retry_timer", 0.0)
	var res: Dictionary = _fish_start()
	_check_true("j2.fishing_started", bool(res.get("ok", false)), "true", str(res))
	_check_eq("j2.start_phase", _phase(), "walking")
	var start_count_before: int = int(_patrol_state().get("start_count", 0))
	var crossed: bool = false
	for i in range(600):
		_step()
		if fposmod(_sim(), 86400.0) > 8.0 * 3600.0 + 2.0:
			crossed = true
			break
	_check_true("j2.crossed_0800_while_fishing", crossed)
	_check_true("j2.fishing_still_active", _fishing_active())
	_tick_n(40)
	var st: Dictionary = _patrol_state()
	_check_eq("j2.patrol_not_started", int(st.get("start_count", 0)), start_count_before)
	_check_eq("j2.no_villager_patrol", _patrol_active(), false)
	_check_true("j2.day_not_handled", int(st.get("handled_day", 0)) != int(floor(_sim() / 86400.0)))
	_fish_stop()
	_drive(func() -> bool: return not _fishing_active(), 80)
	_check_eq("j2.fishing_stopped", _fishing_active(), false)
	_drive(func() -> bool: return _patrol_active(), 120)
	_check_true("j2.patrol_after_stop", _patrol_active())
	_check_eq("j2.patrol_phase_after", str(_patrol_state().get("phase", "")), "running")
	_villager.call("cancel_farm_patrol", "probe_cleanup")
	_step()
	_hold_patrol()
	print("[PROBE] j2 patrol start_count=%d" % int(_patrol_state().get("start_count", 0)))


# ---------------------------------------------------------------- J3

func _section_j3() -> void:
	_section("J3 stop during waiting -> no catch, no inventory, clean recovery")
	_init_watch()
	_set_sim(_day_base(3) + 12 * 3600.0)
	_hold_patrol()
	_force_weather("clear")
	var start: Dictionary = _fish_start()
	_check_true("j3.start", bool(start.get("ok", false)), "true", str(start))
	_check_true("j3.reach_waiting", _drive_phase("waiting", MAX_WALK + 800))
	var before_total: int = _fish_total()
	var before_rounds: int = int(_fs().get("rounds", 0))
	_check_eq("j3.rounds_before_stop", before_rounds, 0)
	_fish_stop()
	_drive(func() -> bool: return not _fishing_active(), 120)
	_check_eq("j3.inactive", _fishing_active(), false)
	_check_eq("j3.no_catch_on_waiting_stop", _fish_total(), before_total)
	_check_eq("j3.no_commit_events", _commit_events.size(), 0)
	var last: Dictionary = _fs().get("last", {})
	_check_eq("j3.last_outcome", str(last.get("outcome", "")), "cancelled")
	_check_eq("j3.last_reason", str(last.get("reason", "")), "player_stop")
	_check_eq("j3.last_rounds", int(last.get("rounds", -1)), 0)
	_check_eq("j3.rig_line_hidden", bool(_rig_info().get("line_visible", true)), false)
	_check_eq("j3.rig_bobber_hidden", bool(_rig_info().get("bobber_visible", true)), false)
	var d: Dictionary = _villager.call("debug_state") as Dictionary
	var st_name: String = str(d.get("state", ""))
	var st_path: Array = d.get("path", []) as Array
	_check_true("j3.recovered_state", st_name != "WALK" or st_path.is_empty())
	var res: Dictionary = _fish_start()
	_check_true("j3.restart_ok", bool(res.get("ok", false)), "true", str(res))
	_check("j3.restart_phase", _phase() in ["walking", "casting", "waiting"], "walking|casting|waiting", _phase())
	_fish_stop()
	_drive(func() -> bool: return not _fishing_active(), 120)
	_check_eq("j3.final_inactive", _fishing_active(), false)
	print("[PROBE] j3 fish_total=%d commits=%d" % [_fish_total(), _commit_events.size()])


# ---------------------------------------------------------------- J4

func _section_j4() -> void:
	_section("J4 commit exactly once, stop right after commit -> catch retained")
	_init_watch()
	_set_sim(_day_base(4) + 12 * 3600.0)
	_hold_patrol()
	var start: Dictionary = _fish_start()
	_check_true("j4.start", bool(start.get("ok", false)), "true", str(start))
	_check_true("j4.first_catch", _drive(func() -> bool: return int(_fs().get("rounds", 0)) >= 1, MAX_WALK + 1200))
	var rounds1: int = int(_fs().get("rounds", 0))
	_check_eq("j4.rounds_at_commit", rounds1, 1)
	_check_eq("j4.commits_at_commit", _commit_events.size(), 1)
	var total1: int = _fish_total()
	_check_eq("j4.inventory_plus_one", total1, 1)
	var catches: Array = _fs().get("catches", [])
	_check_eq("j4.catch_records", catches.size(), 1)
	var fid: String = ""
	if not catches.is_empty():
		fid = str((catches[0] as Dictionary).get("fish_id", ""))
	_check_true("j4.catch_id_known", bool(_inv.call("is_known_item", fid)))
	_check_eq("j4.catch_count_in_inventory", int(_inv.call("get_count", fid)), 1)
	_fish_stop()
	_drive(func() -> bool: return not _fishing_active(), 120)
	_check_eq("j4.stopped", _fishing_active(), false)
	_tick_n(220)
	_check_eq("j4.total_after_stop", _fish_total(), total1)
	_check_eq("j4.commits_after_stop", _commit_events.size(), 1)
	var last: Dictionary = _fs().get("last", {})
	_check_eq("j4.last_rounds", int(last.get("rounds", -1)), 1)
	_check_eq("j4.last_catches", (last.get("catches", []) as Array).size(), 1)
	print("[PROBE] j4 fish=%s total=%d" % [fid, _fish_total()])


# ---------------------------------------------------------------- J5

func _section_j5() -> void:
	_section("J5 repeated start/stop cycles -> no node or state accumulation")
	_init_watch()
	_set_sim(_day_base(5) + 12 * 3600.0)
	_hold_patrol()
	var base_nodes: int = _count_nodes(_villager)
	var base_rig_named: int = _rig_named_total()
	var base_total: int = _fish_total()
	var walks: int = 0
	var waits: int = 0
	for i in range(6):
		var res: Dictionary = _fish_start()
		if not bool(res.get("ok", false)):
			_check("j5.cycle_start_%d" % i, false, "ok", str(res))
			continue
		walks += 1
		if i % 2 == 0:
			_tick_n(5)
			_check_true("j5.cycle_walking_%d" % i, _fishing_active())
		else:
			if _drive_phase("waiting", MAX_WALK + 800):
				waits += 1
			_check_true("j5.cycle_waiting_%d" % i, _fishing_active())
		_fish_stop()
		_drive(func() -> bool: return not _fishing_active(), 200)
		_check_eq("j5.cycle_inactive_%d" % i, _fishing_active(), false)
		_check_eq("j5.cycle_no_catch_%d" % i, _fish_total(), base_total)
	_check_eq("j5.walks", walks, 6)
	_check_eq("j5.waits", waits, 3)
	var nodes_after: int = _count_nodes(_villager)
	var rig_named_after: int = _rig_named_total()
	_check_eq("j5.no_node_growth", nodes_after, base_nodes)
	_check_eq("j5.no_rig_node_growth", rig_named_after, base_rig_named)
	_check_eq("j5.single_rig", _count_named(_villager, ["IsleFishingRig", "FishingRig"]), 1)
	_check_eq("j5.no_commit", _commit_events.size(), 0)
	_check_eq("j5.no_inventory_change", _fish_total(), base_total)
	_check_eq("j5.villager_no_fish_dict", (_villager.get("_fish") as Dictionary).size(), 0)
	var last: Dictionary = _fs().get("last", {})
	_check_true("j5.last_present", not last.is_empty())
	_nodes_cycle1 = nodes_after
	_rig_nodes = _count_named(_villager, RIG_NAMES)
	print("[PROBE] j5 villager_nodes=%d rig_named=%d rig_total=%d" % [nodes_after, rig_named_after, _rig_nodes])


# ---------------------------------------------------------------- J6

func _section_j6() -> void:
	_section("J6 fishing ends -> patrol runs next day, all 9 slots still visited once")
	_init_watch()
	_set_sim(_day_base(5) + 7 * 3600.0)
	_hold_patrol()
	_force_weather("clear")
	var res: Dictionary = _fish_start()
	_check_true("j6.pre_fishing_start", bool(res.get("ok", false)), "true", str(res))
	_drive(func() -> bool: return int(_fs().get("rounds", 0)) >= 1, MAX_WALK + 1200)
	var commits_before: int = _commit_events.size()
	_fish_stop()
	_drive(func() -> bool: return not _fishing_active(), 200)
	_check_eq("j6.fishing_stopped", _fishing_active(), false)
	_sched_arm(5, 8 * 3600.0 + 5.0)
	_drive(func() -> bool: return _patrol_active(), 120)
	_check_true("j6.patrol_started", _patrol_active())
	_check_eq("j6.patrol_phase", str(_patrol_state().get("phase", "")), "running")
	var ticks: int = _drive_patrol_idle(20000)
	_check_eq("j6.patrol_finished", _patrol_active(), false)
	var last: Dictionary = _patrol_last()
	_check_eq("j6.outcome", str(last.get("outcome", "")), "done")
	var results: Array = last.get("results", [])
	_check_eq("j6.results_size", results.size(), 9)
	var seen: Dictionary = {}
	var unreachable: Array = []
	for rec in results:
		var r: Dictionary = rec
		var slot: int = int(r.get("slot", -1))
		seen[slot] = int(seen.get(slot, 0)) + 1
		if str(r.get("action", "")) == "unreachable":
			unreachable.append(slot)
	_check_eq("j6.unique_slots", seen.size(), 9)
	var dup: Array = []
	for k in seen.keys():
		if int(seen[k]) != 1:
			dup.append(k)
	_check_eq("j6.no_duplicate_slot", dup.size(), 0)
	_check_eq("j6.no_unreachable", unreachable.size(), 0)
	_check_true("j6.slot4_reached", seen.has(4), "slot4 visited", "missing")
	_check_eq("j6.patrol_nodes_stable", _count_nodes(_villager), _nodes_cycle1)
	_check_eq("j6.fish_commits_preserved", _commit_events.size(), commits_before)
	_check_true("j6.ticks_used", ticks < 20000, "<20000", str(ticks))
	print("[PROBE] j6 ticks=%d results=%s" % [ticks, str(results)])
	_hold_patrol()


# ---------------------------------------------------------------- J7

func _section_j7() -> void:
	_section("J7 backpack open/sort during fishing -> no data or state disturbance")
	_init_watch()
	_set_sim(_day_base(6) + 12 * 3600.0)
	_hold_patrol()
	var start: Dictionary = _fish_start()
	_check_true("j7.start", bool(start.get("ok", false)), "true", str(start))
	_check_true("j7.reach_waiting", _drive_phase("waiting", MAX_WALK + 800))
	var snap_before: Dictionary = _snap()
	_hud.call("open_backpack")
	_tick_n(3)
	_check_true("j7.backpack_open", bool(_hud.call("backpack_open")))
	_check_eq("j7.open_no_data", _snap(), snap_before)
	var sorted: bool = bool(_hud.call("sort_backpack"))
	_check_eq("j7.sort_ok", sorted, true)
	_check_eq("j7.sort_no_data", _snap(), snap_before)
	_check_true("j7.still_fishing", _fishing_active())
	_check_eq("j7.phase_intact", _phase(), "waiting")
	_hud.call("close_backpack")
	_tick_n(3)
	_check_eq("j7.backpack_closed", bool(_hud.call("backpack_open")), false)
	_check_eq("j7.close_no_data", _snap(), snap_before)
	_hud.call("open_backpack")
	_tick_n(2)
	_fish_stop("player_stop")
	_drive(func() -> bool: return not _fishing_active(), 120)
	var res: Dictionary = _fish_start()
	_check_true("j7.restart_ok", bool(res.get("ok", false)), "true", str(res))
	_check_eq("j7.start_closes_backpack", bool(_hud.call("backpack_open")), false)
	_check_eq("j7.no_commit", _commit_events.size(), 0)
	_fish_stop()
	_drive(func() -> bool: return not _fishing_active(), 120)
	_hold_patrol()


# ---------------------------------------------------------------- J8

func _section_j8() -> void:
	_section("J8 time jump during fishing -> cancel, committed catch kept, restartable")
	_init_watch()
	_set_sim(_day_base(7) + 12 * 3600.0)
	_hold_patrol()
	var base8: int = _fish_total()
	var start: Dictionary = _fish_start()
	_check_true("j8.start", bool(start.get("ok", false)), "true", str(start))
	_check_true("j8.reach_commit", _drive(func() -> bool: return int(_fs().get("rounds", 0)) >= 1, MAX_WALK + 1200))
	var total1: int = _fish_total()
	_check_eq("j8.committed_once", total1 - base8, 1)
	var sim_before: float = _sim()
	_main.set("_sim_seconds", sim_before + 600.0)
	_step()
	_step()
	_check_eq("j8.cancelled_by_jump", _fishing_active(), false)
	var l2: Dictionary = _fs().get("last", {})
	_check_eq("j8.outcome", str(l2.get("outcome", "")), "cancelled")
	_check_eq("j8.reason", str(l2.get("reason", "")), "time_jump")
	_check_eq("j8.catch_kept", _fish_total(), total1)
	_check_eq("j8.catch_records_kept", (l2.get("catches", []) as Array).size(), 1)
	_check_eq("j8.no_extra_commit", _commit_events.size(), 1)
	var res: Dictionary = _fish_start()
	_check_true("j8.restart_after_jump", bool(res.get("ok", false)), "true", str(res))
	_tick_n(20)
	_check("j8.restart_phase", _phase() in ["walking", "casting", "waiting"], "walking|casting|waiting", _phase())
	_fish_stop()
	_drive(func() -> bool: return not _fishing_active(), 120)
	_hold_patrol()
	print("[PROBE] j8 sim_before=%.0f after=%.0f total=%d" % [sim_before, _sim(), _fish_total()])


# ---------------------------------------------------------------- J9

func _section_j9() -> void:
	_section("J9 pause during waiting -> no logic/no commit; resume completes once")
	_init_watch()
	_set_sim(_day_base(8) + 12 * 3600.0)
	_hold_patrol()
	var base9: int = _fish_total()
	var start: Dictionary = _fish_start()
	_check_true("j9.start", bool(start.get("ok", false)), "true", str(start))
	_check_true("j9.reach_waiting", _drive_phase("waiting", MAX_WALK + 800))
	var phase_before: String = _phase()
	var sim_before: float = _sim()
	_main.set("_paused", true)
	_tick_n(200)
	_check_eq("j9.sim_frozen", _sim(), sim_before)
	_check_eq("j9.phase_frozen", _phase(), phase_before)
	_check_eq("j9.no_commit_while_paused", _commit_events.size(), 0)
	_check_eq("j9.inventory_flat", _fish_total(), base9)
	_check_true("j9.still_active", _fishing_active())
	_main.set("_paused", false)
	var ok: bool = _drive(func() -> bool: return int(_fs().get("rounds", 0)) >= 1, 1400)
	_check_true("j9.resume_commits", ok)
	_check_eq("j9.commit_once", _commit_events.size(), 1)
	_check_eq("j9.total_one", _fish_total(), base9 + 1)
	_fish_stop()
	_drive(func() -> bool: return not _fishing_active(), 200)
	_hold_patrol()
	print("[PROBE] j9 commits=%d" % _commit_events.size())


# ---------------------------------------------------------------- J10

func _section_j10() -> void:
	_section("J10 alternation stress: fishing <-> patrol, 3 rounds, no accumulation")
	_init_watch()
	var nodes_start: int = _count_nodes(_villager)
	var base_total: int = _fish_total()
	_check_eq("j10.nodes_baseline", nodes_start, _nodes_cycle1)
	var fishing_rounds: int = 0
	var patrol_starts: int = 0
	for i in range(3):
		_force_weather("clear")
		_set_sim(_day_base(10 + i) + 7 * 3600.0)
		_hold_patrol()
		var res: Dictionary = _fish_start()
		_check_true("j10.fishing_%d" % i, bool(res.get("ok", false)), "true", str(res))
		fishing_rounds += 1
		_drive_phase("waiting", MAX_WALK + 800)
		_fish_stop()
		_drive(func() -> bool: return not _fishing_active(), 200)
		_check_eq("j10.fishing_stop_%d" % i, _fishing_active(), false)
		_force_weather("clear")
		_scheduler_clear()
		_set_sim(_day_base(10 + i) + 8 * 3600.0 + 5.0)
		_drive(func() -> bool: return _patrol_active(), 120)
		if _patrol_active():
			patrol_starts += 1
			_check_eq("j10.patrol_phase_%d" % i, str(_patrol_state().get("phase", "")), "running")
			_villager.call("cancel_farm_patrol", "probe_stress")
			_drive(func() -> bool: return not _patrol_active(), 120)
		_check_eq("j10.patrol_clean_%d" % i, _patrol_active(), false)
		_check_eq("j10.no_inventory_delta_%d" % i, _fish_total(), base_total)
		_hold_patrol()
		_tick_n(20)
	_check_eq("j10.fishing_cycles", fishing_rounds, 3)
	_check_eq("j10.patrol_cycles", patrol_starts, 3)
	_check_eq("j10.no_node_growth", _count_nodes(_villager), _nodes_cycle1)
	_check_eq("j10.no_fish_commit", _commit_events.size(), 0)
	_check_eq("j10.no_fish_decrease", _decrease, 0)
	_check_eq("j10.no_burst", _burst, 0)
	_check_eq("j10.no_leftover_fish", (_villager.get("_fish") as Dictionary).size(), 0)
	_check_eq("j10.no_leftover_patrol", (_villager.get("_patrol") as Dictionary).size(), 0)
	print("[PROBE] j10 nodes=%d rig=%d" % [_count_nodes(_villager), _rig_named_total()])


# ---------------------------------------------------------------- J11

func _section_j11() -> void:
	_section("J11 final reconciliation (inventory vs commits, rig singleton, farm intact)")
	_init_watch()
	_set_sim(_day_base(13) + 12 * 3600.0)
	_force_weather("clear")
	_hold_patrol()
	var baseline_total: int = _fish_total()
	var start: Dictionary = _fish_start()
	_check_true("j11.fishing_start", bool(start.get("ok", false)), "true", str(start))
	_drive(func() -> bool: return int(_fs().get("rounds", 0)) >= 1, MAX_WALK + 1200)
	_fish_stop()
	_drive(func() -> bool: return not _fishing_active(), 200)
	var delta: int = _fish_total() - baseline_total
	_check_eq("j11.delta_matches_events", delta, _commit_events.size())
	_check_eq("j11.no_decrease", _decrease, 0)
	_check_eq("j11.no_burst", _burst, 0)
	_check_eq("j11.rig_singleton", _count_named(_villager, ["IsleFishingRig", "FishingRig"]), 1)
	_check_true("j11.rig_built", bool(_rig_info().get("built", false)))
	_check_eq("j11.rig_line_hidden", bool(_rig_info().get("line_visible", true)), false)
	_check_eq("j11.fishing_inactive", _fishing_active(), false)
	_check_eq("j11.patrol_inactive", _patrol_active(), false)
	var slots: Array = (_farm.call("export_state") as Dictionary).get("slots", [])
	_check_eq("j11.farm_slots", slots.size(), 9)
	var bad_counts: int = 0
	var snap: Dictionary = _snap()
	for item_id in snap.keys():
		if int(snap[item_id]) < 0:
			bad_counts += 1
	_check_eq("j11.no_negative_items", bad_counts, 0)
	_check_eq("j11.nodes_final", _count_nodes(_villager), _nodes_cycle1)
	print("[PROBE] j11 baseline=%d delta=%d events=%d total=%d" % [baseline_total, delta, _commit_events.size(), _fish_total()])


# ---------------------------------------------------------------- J12

func _section_j12() -> void:
	_section("J12 patrol running across midnight -> report cancelled (not stale running), next day recovers")
	_init_watch()
	_force_weather("clear")
	# 用"自然跨日"（等价于正式设置里 60s/日 的最快档，巡田会跨过 00:00），
	# 而不是 [ ] 时间跳变：跨日时 main 的新游戏日分支必须取消当天巡田，并把
	# _patrol_phase/_patrol_last 如实投影为 cancelled/new_day；若停留在 running，
	# 巡田快照就与岛民真实状态（已无巡田）不一致。
	var day11: int = _today + 11
	_sched_arm(11, 8 * 3600.0 + 5.0)
	_drive(func() -> bool: return _patrol_active(), 60)
	_check_true("j12.patrol_started", _patrol_active())
	_check_eq("j12.phase_running", str(_patrol_state().get("phase", "")), "running")
	# 跳到当天 23:59:55（岛民时钟同步，不会被判定为时间跳变），再让真实 tick 自然越过 00:00。
	_set_sim(float(day11 * 86400 + 86395))
	var crossed: bool = false
	for i in range(300):
		_step()
		if int(floor(_sim() / 86400.0)) > day11:
			crossed = true
			break
	_check_true("j12.crossed_midnight", crossed)
	_check_eq("j12.villager_patrol_cancelled", _patrol_active(), false)
	var st: Dictionary = _patrol_state()
	_check_eq("j12.phase_cancelled", str(st.get("phase", "")), "cancelled")
	var last: Dictionary = st.get("last", {}) as Dictionary
	_check_eq("j12.last_outcome", str(last.get("outcome", "")), "cancelled")
	_check_eq("j12.last_reason", str(last.get("reason", "")), "new_day")
	_check_eq("j12.handled_day_not_new", int(st.get("handled_day", 0)), day11)
	# 次日 08:00 仍能正常启动（跨日取消不破坏"每日一轮"的幂等语义）。
	_set_sim(_day_base(12) + 7 * 3600.0 + 59.0 * 60.0 + 58.0)
	var sc0: int = int(_patrol_state().get("start_count", 0))
	_drive(func() -> bool: return _patrol_active(), 400)
	_check_true("j12.next_day_patrol_started", _patrol_active())
	_check_eq("j12.next_day_start_count", int(_patrol_state().get("start_count", 0)), sc0 + 1)
	_check_eq("j12.next_day_phase", str(_patrol_state().get("phase", "")), "running")
	_villager.call("cancel_farm_patrol", "probe_cleanup")
	_step()
	_hold_patrol()
	print("[PROBE] j12 start_count=%d phase=%s last=%s" % [int(_patrol_state().get("start_count", 0)), str(_patrol_state().get("phase", "")), str(last)])


# ---------------------------------------------------------------- J15

## B 报告 F2 声称"真实长帧会被误判为时间跳变"。主控核算：_advance_sim 里
## _sim_delta = _sim_seconds - sim_before，岛民 _detect_jump 用同一个增量做期望值，
## 因此帧长不改变差值；这里用一次 2.0 s 的真实长帧在正式状态机上复核。
func _section_j15() -> void:
	_section("J15 oversized real frame is not a time jump (fishing keeps running)")
	_init_watch()
	_force_weather("clear")
	_set_sim(_day_base(0) + 12.0 * 3600.0)
	_hold_patrol()
	var start: Dictionary = _fish_start()
	_check_true("j15.fishing_start", bool(start.get("ok", false)), "true", str(start))
	_drive(func() -> bool: return _phase() == "walking", 1200)
	_check_eq("j15.walking", _phase(), "walking")
	var pos0: Vector3 = _villager.get("_pos") as Vector3
	var total0: int = _fish_total()
	var rounds0: int = int(_fs().get("rounds", 0))
	# 一次 2.0 s 的"卡顿长帧"：等价于窗口最小化后恢复的一帧。
	_main.call("_tick", 2.0)
	_watch()
	_check_eq("j15.still_fishing", _fishing_active(), true)
	_check_eq("j15.no_commit", _fish_total(), total0)
	_check_eq("j15.rounds_unchanged", int(_fs().get("rounds", 0)), rounds0)
	_check_eq("j15.no_error", str(_fs().get("error", "")), "")
	var pos1: Vector3 = _villager.get("_pos") as Vector3
	var step_h: float = Vector2(pos0.x, pos0.z).distance_to(Vector2(pos1.x, pos1.z))
	_check("j15.step_bounded", step_h <= 0.12, "<=0.12m", "%.4fm" % step_h)
	var last: Dictionary = _villager.call("fishing_last") as Dictionary
	_check_eq("j15.no_finish_record", last.is_empty(), true)
	_fish_stop()
	_drive(func() -> bool: return not _fishing_active(), 200)
	_check_eq("j15.cleaned", _fishing_active(), false)
	print("[PROBE] j15 phase=%s step=%.4f total=%d" % [_phase(), step_h, _fish_total()])


# ---------------------------------------------------------------- J13

## A-FARM-01 回归：巡田完成当天（D）后把时间倒回 D-1 跨过 00:00，再前进到 D 的 08:00，
## 旧实现下调了 _patrol_handled_day，会认为 D 还没巡过而第二次启动巡田（重复播种/重复发种）。
func _section_j13() -> void:
	_section("J13 rewind across midnight then replay to D 08:00 -> no second patrol")
	_init_watch()
	_force_weather("clear")
	var day_d: int = _today + 14
	_sched_arm(14, 8 * 3600.0 + 5.0)
	_drive(func() -> bool: return _patrol_active(), 60)
	_check_true("j13.patrol_started", _patrol_active())
	_drive_patrol_idle(6000)
	_check_eq("j13.patrol_finished", _patrol_active(), false)
	# phase 投影在岛民 tick 之后的下一帧同步（主控先跑调度再跑岛民），补两帧再读。
	_tick_n(2)
	var st_done: Dictionary = _patrol_state()
	_check_eq("j13.phase_completed", str(st_done.get("phase", "")), "completed")
	var sc0: int = int(st_done.get("start_count", 0))
	var total0: int = _inventory_total()
	# 倒带：D-1 00:05（等价于玩家跨过 00:00 回拨时间）
	_set_sim(_day_base(13) + 5.0 * 60.0)
	_step()
	_check_eq("j13.rewind_phase", str(_patrol_state().get("phase", "")), "day_rewound")
	_check_eq("j13.handled_kept", int(_patrol_state().get("handled_day", 0)), day_d)
	# 重播回到已巡过的 D 日 08:00：只允许状态同步，绝不允许第二轮
	_set_sim(_day_base(14) + 7 * 3600.0 + 59.0 * 60.0 + 58.0)
	_drive(func() -> bool: return _patrol_active(), 400)
	_check_eq("j13.no_second_patrol", _patrol_active(), false)
	_check_eq("j13.start_count_unchanged", int(_patrol_state().get("start_count", 0)), sc0)
	_check_eq("j13.inventory_flat", _inventory_total(), total0)
	_check_eq("j13.handled_still_d", int(_patrol_state().get("handled_day", 0)), day_d)
	# 次日（D+1）仍能正常启动：修复不能破坏"每天一轮"
	_set_sim(_day_base(15) + 7 * 3600.0 + 59.0 * 60.0 + 58.0)
	_drive(func() -> bool: return _patrol_active(), 400)
	_check_true("j13.next_day_started", _patrol_active())
	_check_eq("j13.next_day_start_count", int(_patrol_state().get("start_count", 0)), sc0 + 1)
	_villager.call("cancel_farm_patrol", "probe_cleanup")
	_step()
	# 触发条件回归证明：把高水位按旧实现下调，同一游戏日确实会二次巡田（说明该断言有效）。
	_set_sim(_day_base(14) + 7 * 3600.0 + 59.0 * 60.0 + 58.0)
	_main.set("_patrol_handled_day", day_d - 1)
	_main.set("_patrol_rewind_day", -2147483647)
	_drive(func() -> bool: return _patrol_active(), 400)
	_check_true("j13.old_bug_would_repeat", _patrol_active())
	_villager.call("cancel_farm_patrol", "probe_demo")
	_step()
	_hold_patrol()
	print("[PROBE] j13 start_count=%d day_d=%d" % [sc0, day_d])


# ---------------------------------------------------------------- J14

## C-01 回归：暂停时 _advance_sim 不跑，但 _sim_delta 只有 _advance_sim 会写；
## 旧实现保留上一帧的陈旧增量 -> 灯塔光束继续转、远海等待继续倒数（世界没有真正冻结）。
func _section_j14() -> void:
	_section("J14 pause freezes sim-time consumers (lighthouse beam / far-sea wait)")
	_force_weather("clear")
	_init_watch()
	_scheduler_clear()
	_set_sim(_day_base(16) + 12.0 * 3600.0)
	_hold_patrol()
	_main.set("_paused", false)
	_step()
	var beam0: float = float(_main.get("_beam_angle"))
	var boat_state0: String = str(_main.get("_boat_state"))
	var wait0: float = float(_main.get("_boat_wait_sim"))
	_main.set("_boat_state", "OFFSCREEN_WAIT")
	_main.set("_boat_wait_sim", 123.0)
	_main.call("_toggle_pause")
	_check_eq("j14.paused", bool(_main.get("_paused")), true)
	var sim_p: float = _sim()
	for i in range(20):
		_step()
	_check_eq("j14.sim_frozen", _sim(), sim_p)
	_check_eq("j14.sim_delta_zero", float(_main.get("_sim_delta")), 0.0)
	# 船/灯塔由 _process 侧的推进函数消费（探针手动调用同一函数）
	for i in range(5):
		_main.call("_update_props", DT)
	var wait_p: float = float(_main.get("_boat_wait_sim"))
	_check_eq("j14.boat_wait_frozen", wait_p, 123.0)
	var beam_p: float = float(_main.get("_beam_angle"))
	_check("j14.beam_frozen", absf(beam_p - beam0) < 0.0001, "unchanged", "%.6f" % (beam_p - beam0))
	_main.call("_toggle_pause")
	_check_eq("j14.resumed", bool(_main.get("_paused")), false)
	_step()
	_check_true("j14.sim_delta_resumed", float(_main.get("_sim_delta")) > 0.0)
	for i in range(5):
		_main.call("_update_props", DT)
	_check("j14.boat_wait_resumes", float(_main.get("_boat_wait_sim")) < 123.0, "<123.0", "%.2f" % float(_main.get("_boat_wait_sim")))
	_main.set("_boat_state", boat_state0)
	_main.set("_boat_wait_sim", wait0)
	print("[PROBE] j14 beam_delta=%.6f wait=%.2f" % [beam_p - beam0, float(_main.get("_boat_wait_sim"))])


# ---------------------------------------------------------------- J16

## C-02 回归：暂停是"世界冻结"，期间不接受新活动、也不接受交互式调时。
## 旧实现：_update_farm_patrol 无 _paused 门、start_fishing 无 _paused 门、三处调时入口无 _paused 门。
func _section_j16() -> void:
	_section("J16 paused: no fishing start / no patrol start / interactive time refused")
	_force_weather("clear")
	_init_watch()
	_scheduler_clear()
	_set_sim(_day_base(17) + 12.0 * 3600.0)
	_hold_patrol()
	_main.set("_paused", false)
	_step()
	_main.call("_toggle_pause")
	_check_eq("j16.paused", bool(_main.get("_paused")), true)
	var sim0: float = _sim()
	var res: Dictionary = _main.call("start_fishing") as Dictionary
	_check_eq("j16.fishing_refused", bool(res.get("ok", true)), false)
	_check_eq("j16.fishing_reason", str(res.get("reason", "")), "paused")
	_check_eq("j16.not_fishing", _fishing_active(), false)
	# 三条交互式调时入口（HUD 时间轴、快捷调时、日历跳转）在暂停中都必须拒绝
	_main.call("_on_time_adjust", 600.0)
	_main.call("_on_time_set", 15.0 * 3600.0)
	_hud.emit_signal("time_adjust", 3600.0)
	var parts: Dictionary = CAL.parts(_sim())
	_main.call("_on_datetime_jump_requested", int(parts["year"]), int(parts["month"]), int(parts["day"]), 13, 0)
	_step()
	_check_eq("j16.time_unchanged", _sim(), sim0)
	# 即使时钟被直接推到当天 08:00:05，暂停中也不产生巡田活动
	_set_sim(_day_base(17) + 8 * 3600.0 + 5.0)
	var sc: int = int(_patrol_state().get("start_count", 0))
	_tick_n(40)
	_check_eq("j16.no_patrol_while_paused", _patrol_active(), false)
	_check_eq("j16.patrol_count_unchanged", int(_patrol_state().get("start_count", 0)), sc)
	_main.call("_toggle_pause")
	_check_eq("j16.resumed", bool(_main.get("_paused")), false)
	_sched_arm(17, 8 * 3600.0 + 5.0)
	_drive(func() -> bool: return _patrol_active(), 60)
	_check_true("j16.patrol_after_resume", _patrol_active())
	_villager.call("cancel_farm_patrol", "probe_cleanup")
	_step()
	_hold_patrol()
	print("[PROBE] j16 refused=%s" % str(res))


# ---------------------------------------------------------------- report

func _write_report() -> void:
	var path: String = "%s/probe_p9_joint.log" % str(_out_dir)
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("[PROBE] cannot write %s" % path)
		return
	f.store_line("P7 joint farm x fishing probe")
	f.store_line("checks=%d fail=%d" % [_checks, _fail])
	f.store_line("commit_events=%d fish_total=%d" % [_commit_events.size(), _fish_total()])
	f.store_line("villager_nodes_after_cycle1=%d rig_nodes=%d" % [_nodes_cycle1, _count_nodes(_villager)])
	f.store_line("")
	for line in _lines:
		f.store_line(str(line))
	f.close()
	print("[PROBE] report=%s" % path)
