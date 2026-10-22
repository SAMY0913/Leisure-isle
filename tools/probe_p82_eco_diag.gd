extends SceneTree
# P8.2-04 冬季生态诊断：为什么海鸥自然使用 5 个冬季裸枝点的次数偏低？
# 用法：bash run_godot.sh --headless --path . --fixed-fps 60 --script res://tools/probe_p82_eco_diag.gd
# 输出：标准输出（重定向到 开发产物/p82/04_winter/eco_diag_*.log）
# 只读观察：不改 fx.gd，不强制栖点，只调用既有 debug_* 接口。

const FRAMES := 2400
const REPORT_EVERY := 120

var _main: Node = null
var _fx: Object = null
var _prev_state: Dictionary = {}
var _prev_pid: Dictionary = {}
var _usage: Dictionary = {}
var _transitions := 0
var _landings := 0
var _state_hist: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	print("[DIAG] boot")
	await process_frame
	var ps: PackedScene = load("res://isle.tscn") as PackedScene
	_main = ps.instantiate()
	root.add_child(_main)
	var frames := 0
	while frames < 2400:
		await process_frame
		frames += 1
		if _main.get("_birds") != null and not (_main.get("_world") as Dictionary).is_empty():
			break
	_fx = _main.get("_birds")
	print("[DIAG] ready frames=%d" % frames)
	_main.set("_mode", 1)
	_main.set("_time_source", "sim")
	_main.set("_paused", false)
	_main.set("_started", true)
	var menu = _main.get("_menu")
	if menu != null and menu.has_method("instant_finish"):
		menu.instant_finish()
	await _frames(5)
	_main.call("_jump_datetime", 2027, 1, 15, 10, 0, 0)
	await _frames(60)
	print("[DIAG] after jump stats=", str(_fx.call("debug_perch_stats")).substr(0, 700))
	print("[DIAG] sun_alt=", str(_main.get("_sun_alt")), " eco_ctx=", str(_main.get("_eco_ctx")))
	# 选点权重分析：对一只飞行鸟当前位置，统计可用槽位的区域权重份额
	var snap0: Array = _fx.call("debug_snapshot")
	var from_pos := Vector3.ZERO
	for s_v in snap0:
		var s: Dictionary = s_v
		if int(s["state"]) == 1:
			from_pos = s["pos"]
			break
	print("[DIAG] weight_from_pos=", str(from_pos))
	_weight_report(from_pos)
	# 逐帧观察
	var prev_states := {}
	for i in range(FRAMES):
		await process_frame
		var snap: Array = _fx.call("debug_snapshot")
		var hist := {}
		for s_v in snap:
			var s: Dictionary = s_v
			var idx := int(s["index"])
			var st := int(s["state"])
			var pid := String(s["perch_id"])
			hist[st] = int(hist.get(st, 0)) + 1
			_state_hist[st] = int(_state_hist.get(st, 0)) + 1
			var prev_st := int(_prev_state.get(idx, -1))
			if prev_st != st:
				if st == 3:
					_landings += 1
					_usage[pid] = int(_usage.get(pid, 0)) + 1
					print("[DIAG] LAND f=%d bird=%d pid=%s slot=%d from_state=%d" % [i, idx, pid, int(s["perch_slot"]), prev_st])
				if st == 1 and prev_st == 2:
					pass
				_prev_state[idx] = st
				_transitions += 1
			if st == 3 and prev_st == 3 and pid != String(_prev_pid.get(idx, "")):
				print("[DIAG] PERCH-ID-CHANGE f=%d bird=%d pid=%s" % [i, idx, pid])
			_prev_pid[idx] = pid
		if i % REPORT_EVERY == 0:
			var st0: Dictionary = _fx.call("debug_perch_stats")
			var wx: Dictionary = (_main.call("_eco_ctx") as Dictionary).get("weather", {})
			print("[DIAG] f=%d night=%s roost=%s wxbad=%s wx=%s hist=%s perched=%d used=%d" % [
				i, str(st0.get("night")), str(st0.get("roost_state")), str(_fx.get("_wx_bad")),
				str(wx).substr(0, 160), str(hist), int(st0.get("perched", 0)), int(st0.get("used_slots", 0))])
	# 鸟位置/地形检查明细
	_check_positions()
	print("[DIAG] transitions=%d landings=%d usage=%s" % [_transitions, _landings, JSON.stringify(_usage)])
	print("[DIAG] state_hist(frame-weighted)=%s" % JSON.stringify(_state_hist))
	print("[DIAG] final stats=", str(_fx.call("debug_perch_stats")).substr(0, 900))
	quit(0)

func _frames(n: int) -> void:
	for i in range(n):
		await process_frame

func _weight_report(from_pos: Vector3) -> void:
	var cands: Array = _fx.call("_collect_free_slots", from_pos, "", false)
	var by_zone := {}
	var total := 0.0
	var winter_list: Array = []
	for c_v in cands:
		var c: Dictionary = c_v
		var zone := String(c.get("zone", ""))
		by_zone[zone] = float(by_zone.get(zone, 0.0)) + float(c["weight"])
		total += float(c["weight"])
		if zone == "winter_branch":
			var p: Dictionary = {}
			for pv in _fx.call("get_perches"):
				if String((pv as Dictionary)["id"]) == String(c["id"]):
					p = pv
			winter_list.append({"id": c["id"], "slot": c["slot"], "w": float(c["weight"]),
				"pos": c["pos"], "normal": p.get("normal", Vector3.UP), "dist": from_pos.distance_to(c["pos"])})
	print("[DIAG] weight_slots=%d total=%.3f by_zone=%s" % [cands.size(), total, JSON.stringify(by_zone)])
	var winter_w := float(by_zone.get("winter_branch", 0.0))
	print("[DIAG] winter_branch_share=%.3f%% (%d slots)" % [100.0 * winter_w / maxf(total, 0.000001), winter_list.size()])
	for w_v in winter_list:
		print("[DIAG]   winter_cand ", JSON.stringify(w_v))

func _check_positions() -> void:
	var snap: Array = _fx.call("debug_snapshot")
	for s_v in snap:
		var s: Dictionary = s_v
		var idx := int(s["index"])
		var st := int(s["state"])
		var p: Vector3 = s["pos"]
		var sy := IsleWorld.surface_y(p.x, p.z)
		var d := p.y - sy
		if d < 0.25 or d > 60.0:
			print("[DIAG] POS-BAD bird=%d state=%d pid=%s pos=%s terrain=%.3f delta=%.3f" % [
				idx, st, String(s["perch_id"]), str(p), sy, d])
		elif st == 3:
			var pid := String(s["perch_id"])
			var perch: Dictionary = {}
			for pv in _fx.call("get_perches"):
				if String((pv as Dictionary)["id"]) == pid:
					perch = pv
			if not perch.is_empty():
				var sp: Vector3 = _fx.call("_slot_position", perch, int(s["perch_slot"]))
				print("[DIAG] POS-PERCH bird=%d pid=%s slot=%d pos=%s slot_pos=%s d=%.4f terrain_gap=%.2f" % [
					idx, pid, int(s["perch_slot"]), str(p), str(sp), p.distance_to(sp), d])
