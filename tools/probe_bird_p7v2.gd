
extends SceneTree
## P7-V2 海鸥专项验收探针（headless，脚本 Shell 用 SceneTree）
## 运行：
##   D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe --headless --path D:/休闲小岛幻境/游戏工程 --script res://tools/probe_bird_p7v2.gd
## 覆盖：
##   [A] 停栖待机动作 ≥4 类、错峰、白天无 rest、动作结束姿态/位置归位、轻跳回原槽位不穿面/不侧移、取消（起飞）归位
##   [A-NIGHT] 夜间安静：仅 rest/look_around/preen，rest 占比高、零位移；黄昏归栖 ROOST_ACTIVE 不做位移动作
##   [B] 白天多轮起降分布：屋顶区 ≤2、同排屋脊 ≤2、≥8 个不同栖枝 / ≥4 kind / ≥4 区域、porch_rail 参与、落地后 idle_cool 重置
##   [C] 烟囱禁停：11-13/17-19 双窗口边界、提前量=(TRANSITION_MAX+缓冲)*sim_rate、窗口前正常起飞不触发 hold
##   [C] 时间跳入窗口 → 同帧驱逐 + smoke_hold 安全回退（ChimneySmoke.set_sim_seconds(sim, hold) / BirdFlock.smoke_hold_remaining()）
##   [C] 夜间烟囱禁停与安全改停、debug_perch_availability reason
##   [D] debug_snapshot 扩展 / debug_idle_state / debug_perch_availability / debug_perch_stats / debug_force_perch
##   [BASE] 夜间 10 只全部停栖、槽位无冲突、脚点=槽点（P7-V1 行为保留）
## 退出码：0 全部通过。

const Fx := preload("res://scripts/fx.gd")
const World := preload("res://scripts/world.gd")
const DT := 1.0 / 60.0
const BIRD_COUNT := 10
const STATE_FLY := 0
const STATE_TAKEOFF := 1
const STATE_LANDING := 2
const STATE_PERCH := 3

var _pass := 0
var _fail := 0
var _holder: Node3D = null
var _cot_perches: Array = []
var _all_perches: Array = []
var _cottage_loaded := false

func _initialize() -> void:
	print("=== P7V2 BIRD PROBE START ===")
	await process_frame
	_holder = Node3D.new()
	_holder.name = "P7V2ProbeHolder"
	root.add_child(_holder)
	_build_perches()
	await process_frame
	_test_debug_interfaces()
	_test_idle_day_actions()
	_test_idle_cancel_and_snap()
	_test_hop_returns_to_slot()
	_test_night_quiet_and_still()
	_test_roost_active_no_displacement()
	_test_distribution_stats()
	_test_chimney_window_boundaries()
	_test_chimney_lead_eviction()
	_test_time_jump_hold()
	_test_smoke_hold_clock()
	_test_night_chimney_eviction()
	_test_force_perch_and_layout()
	_test_kind_zones()
	print("=== P7V2 BIRD PROBE RESULT: ", "PASS" if _fail == 0 else "FAIL", " pass=", _pass, " fail=", _fail, " ===")
	quit(0 if _fail == 0 else 1)

# ------------------------------------------------------------
# 基础设施
# ------------------------------------------------------------
func _check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("  [OK] ", msg)
	else:
		_fail += 1
		print("  [FAIL] ", msg)

func _ctx(sim_seconds: float, sim_rate: float, rising: bool = true) -> Dictionary:
	return {
		"day": int(floor(sim_seconds / 86400.0)),
		"rising": rising,
		"sim_seconds": sim_seconds,
		"sim_rate": sim_rate,
		"time_source": "sim",
		"paused": false,
	}

func _build_perches() -> void:
	var big := {"pos": Vector3(0.0, 0.0, 0.0), "perches": [
		Vector3(3.2, 6.1, 0.4), Vector3(-3.0, 6.4, -0.6), Vector3(0.5, 7.0, 3.1),
		Vector3(-0.7, 6.7, -3.2), Vector3(4.0, 5.8, 4.2), Vector3(-3.8, 5.9, -4.0)]}
	var dock := {"perch": Vector3(10.0, 2.0, 4.0), "bollard": Vector3(11.0, 1.6, 2.5)}
	var lh := {"perches": [Vector3(-20.0, 15.0, 9.0), Vector3(-14.0, 15.0, 9.0), Vector3(-17.0, 16.0, 13.0), Vector3(-17.0, 16.0, 5.0)]}
	# 旧三参调用（probe 桩）必须仍返回 16 点（world.gd 兼容契约）
	var world_base: Array = World._build_perches(big, dock, lh)
	_check(world_base.size() == 16, "world 旧三参 _build_perches 仍返回 16 点（兼容，实际 %d）" % world_base.size())
	# P7-V2：传入 6 个真实路灯数据（base/facing 与 _street_lamps 同格式），验证 lamp 栖点接入
	var lamps: Array = []
	for i in range(6):
		var lbase := Vector3(cos(float(i) * 1.05) * 12.0, 0.0, sin(float(i) * 1.05) * 12.0)
		var lf := Vector3(-lbase.x, 0.0, -lbase.z)
		if lf.length_squared() < 0.000001:
			lf = Vector3(1.0, 0.0, 0.0)
		lamps.append([null, null, null, {"base": lbase, "facing": lf.normalized()}])
	var world_perches: Array = World._build_perches(big, dock, lh, lamps)
	var lamp_kinds: Array = []
	for p_v in world_perches:
		var p0: Dictionary = p_v
		if String(p0["kind"]) == "lamp":
			lamp_kinds.append(String(p0["id"]))
	_check(world_perches.size() == 22 and lamp_kinds.size() == 6, "world 接入 6 个真实路灯栖点（总 %d，lamp=%s）" % [world_perches.size(), str(lamp_kinds)])
	_all_perches = world_perches.duplicate()
	var cottage_script: GDScript = load("res://scripts/cottage.gd") as GDScript
	if cottage_script != null and cottage_script.can_instantiate():
		var cot: Dictionary = cottage_script.build(_holder)
		_cot_perches = (cot["perches"] as Array).duplicate()
		_cottage_loaded = true
		for p_v in _cot_perches:
			_all_perches.append(p_v)
	print("[PERCH] world=", world_perches.size(), " cottage=", _cot_perches.size(), " all=", _all_perches.size())
	_check(world_perches.size() == 22, "world 栖枝数 16+6 lamp=22（实际 %d）" % world_perches.size())
	_check(_cottage_loaded and _cot_perches.size() >= 10, "cottage 栖枝可用（实际 %d）" % _cot_perches.size())

func _mk_flock(perches: Array):
	var flock = Fx.BirdFlock.new()
	root.add_child(flock)
	flock.setup(perches)
	return flock

func _birds(flock) -> Array:
	return flock.get("_birds")

func _freeze_timers(flock, value: float) -> void:
	for b_v in _birds(flock):
		var b: Dictionary = b_v
		if int(b["state"]) == STATE_PERCH:
			b["timer"] = value

## 让停栖鸟按递增的短计时器先后起飞，制造足够多的起降样本（分布统计用）。
func _stir_timers(flock, base: float) -> void:
	var i := 0
	for b_v in _birds(flock):
		var b: Dictionary = b_v
		if int(b["state"]) == STATE_PERCH:
			b["timer"] = base + float(i) * 0.27
		i += 1

func _seat_all(flock) -> int:
	var birds: Array = _birds(flock)
	flock.call("_clear_allocations")
	for b_v in birds:
		var b: Dictionary = b_v
		b["state"] = STATE_FLY
		b["perch_id"] = ""
		b["perch_slot"] = -1
		b["perch_pos"] = Vector3.ZERO
		b["timer"] = 0.0
		b["waiting"] = false
		b["fold"] = 0.0
		b["idle_action"] = "none"
		b["idle_active"] = false
		b["idle_off"] = Vector3.ZERO
	var seated := 0
	for b_v in birds:
		var b: Dictionary = b_v
		var slot: Dictionary = flock.call("_find_free_slot", (b["node"] as Node3D).position)
		if slot.is_empty():
			continue
		flock.call("_reserve_slot", String(slot["id"]), int(slot["slot"]))
		b["perch_id"] = slot["id"]
		b["perch_slot"] = slot["slot"]
		b["perch_pos"] = slot["pos"]
		b["state"] = STATE_PERCH
		b["timer"] = 999.0
		b["fold"] = 1.0
		b["prev_pos"] = slot["pos"]
		b["teleport"] = true
		(b["node"] as Node3D).position = slot["pos"]
		var perch: Dictionary = flock.call("_find_perch", String(slot["id"]))
		if not perch.is_empty():
			flock.call("_apply_perch_pose", b, perch)
		seated += 1
	return seated

func _snap_pos(flock, b: Dictionary) -> Vector3:
	var perch: Dictionary = flock.call("_find_perch", String(b["perch_id"]))
	if perch.is_empty():
		return Vector3.ZERO
	return flock.call("_slot_position", perch, int(b["perch_slot"]))

func _chimney_perches() -> Array:
	var arr: Array = []
	for i in range(12):
		arr.append({
			"id": "mini_tree_%d" % i,
			"pos": Vector3(cos(float(i) * 0.52) * 8.0, 6.0, sin(float(i) * 0.52) * 8.0),
			"facing": Vector3(0.0, 0.0, 1.0),
			"radius": 0.80,
			"kind": "tree_branch",
		})
	arr.append({
		"id": "chimney_0",
		"pos": Vector3(0.0, 9.0, 0.0),
		"facing": Vector3(0.0, 0.0, 1.0),
		"radius": 0.26,
		"kind": "chimney",
		"normal": Vector3(0.0, 1.0, 0.0),
		"slope": 0.0,
	})
	return arr

# ------------------------------------------------------------
# [D] 调试接口
# ------------------------------------------------------------
func _test_debug_interfaces() -> void:
	print("--- [D] DEBUG INTERFACES ---")
	var flock = _mk_flock(_all_perches)
	var snap: Array = flock.call("debug_snapshot")
	_check(snap.size() == BIRD_COUNT, "debug_snapshot 返回 %d 只鸟" % snap.size())
	var first: Dictionary = snap[0]
	_check(first.has("idle_action") and first.has("idle_active") and first.has("perch_zone"), "debug_snapshot 含 idle_action/idle_active/perch_zone")
	_check(first.has("state") and first.has("perch_id") and first.has("perch_slot") and first.has("pos"), "debug_snapshot 保留 P7-V1 字段")
	var idle_states: Array = flock.call("debug_idle_state")
	_check(idle_states.size() == BIRD_COUNT, "debug_idle_state 返回 %d 条" % idle_states.size())
	var st0: Dictionary = idle_states[0]
	var need := ["index", "state", "action", "active", "t", "dur", "cool", "night", "hop_safe", "perch_id", "perch_zone"]
	var missing: Array = []
	for k in need:
		if not st0.has(k):
			missing.append(k)
	_check(missing.is_empty(), "debug_idle_state 字段完整（缺失 %s）" % str(missing))
	var stats: Dictionary = flock.call("debug_perch_stats")
	_check(int(stats["perch_count"]) == _all_perches.size() and int(stats["total_slots"]) == _all_perches.size(), "36 个真实栖点全部被接受（perch_count=%d total_slots=%d）" % [int(stats["perch_count"]), int(stats["total_slots"])])
	var z0: Dictionary = stats["zones"]
	_check(int(z0.get("lamp", 0)) == 6 and int(z0.get("porch", 0)) == 6 and int(z0.get("roof", 0)) == 8, "区域统计 lamp=6/porch=6/roof=8（实际 %s）" % str(z0))
	var need2 := ["perch_count", "total_slots", "used_slots", "roof_count", "ridge_count", "zones", "perched", "idle_active", "idle_counts", "chimney_evictions", "cap_fallbacks", "no_slot_skips", "night", "sim_seconds", "sim_rate", "smoke_hold", "smoke_hold_count", "hold_reason", "perches"]
	var missing2: Array = []
	for k in need2:
		if not stats.has(k):
			missing2.append(k)
	_check(missing2.is_empty(), "debug_perch_stats 字段完整（缺失 %s）" % str(missing2))
	if _cottage_loaded:
		var noon_av: Array = flock.call("debug_perch_availability", 14.0 * 3600.0, 30.0, false, 60.0)
		var chimney_ok := false
		for e_v in noon_av:
			var e: Dictionary = e_v
			if String(e["id"]) == "chimney_0":
				chimney_ok = bool(e["eligible"]) and String(e["reason"]) == "ok"
		_check(noon_av.size() == _all_perches.size() and chimney_ok, "debug_perch_availability 正午烟囱可用（%d 条）" % noon_av.size())
	flock.free()

# ------------------------------------------------------------
# [A] 白天待机动作：≥4 类、错峰、无 rest、非 hop 帧零位移
# ------------------------------------------------------------
func _test_idle_day_actions() -> void:
	print("--- [A] DAY IDLE ACTIONS ---")
	if not _cottage_loaded:
		_check(false, "cottage 栖枝不可用，无法测试白天待机")
		return
	var flock = _mk_flock(_cot_perches)
	var seated := _seat_all(flock)
	_check(seated == BIRD_COUNT, "白天待机：10 只全部落座（seated=%d）" % seated)
	_freeze_timers(flock, 999.0)
	var sim := 12.0 * 3600.0
	var action_samples := {}
	var hop_seen := false
	var rest_seen := false
	var look_seen := false
	var preen_seen := false
	var shake_seen := false
	var adjust_seen := false
	var max_active := 0
	var bad_disp := 0
	var bad_action := 0
	var first_start := {}
	for i in range(1800):
		sim += 60.0 * DT
		flock.update_birds(DT, 25.0, _ctx(sim, 60.0))
		var states: Array = flock.call("debug_idle_state")
		var active := 0
		for s_v in states:
			var s: Dictionary = s_v
			if not bool(s["active"]):
				continue
			active += 1
			var act := String(s["action"])
			action_samples[act] = int(action_samples.get(act, 0)) + 1
			if act == "hop":
				hop_seen = true
			elif act == "look_around":
				look_seen = true
			elif act == "preen":
				preen_seen = true
			elif act == "shake":
				shake_seen = true
			elif act == "adjust_stance":
				adjust_seen = true
			elif act == "rest":
				rest_seen = true
			else:
				bad_action += 1
			var idx := int(s["index"])
			if not first_start.has(idx):
				first_start[idx] = i
			if int(s["state"]) == STATE_PERCH and act != "hop":
				var b: Dictionary = _birds(flock)[idx]
				var delta: Vector3 = (b["node"] as Node3D).position - _snap_pos(flock, b)
				if delta.length() > 0.001:
					bad_disp += 1
		max_active = maxi(max_active, active)
	_check(action_samples.size() >= 4, "白天出现 >=4 类待机动作（实际 %d：%s）" % [action_samples.size(), str(action_samples.keys())])
	_check(look_seen and preen_seen and shake_seen and adjust_seen, "观察四周/理羽/抖羽/调整站姿均出现")
	_check(hop_seen, "轻跳 hop 出现")
	_check(not rest_seen, "白天不出现休息 rest 动作")
	_check(bad_action == 0, "动作名均在允许集合内（异常 %d）" % bad_action)
	_check(max_active >= 4, "多鸟同时待机（峰值活跃 %d）" % max_active)
	var start_values := {}
	for k in first_start.keys():
		start_values[int(first_start[k])] = true
	_check(start_values.size() >= 4, "动作起始帧错峰（不同起始帧 %d 个）" % start_values.size())
	_check(bad_disp == 0, "非 hop 待机动作不改动脚点（位移样本 %d）" % bad_disp)
	flock.free()

# ------------------------------------------------------------
# [A] 动作可被状态机取消并归位
# ------------------------------------------------------------
func _test_idle_cancel_and_snap() -> void:
	print("--- [A] IDLE CANCEL / SNAP ---")
	if not _cottage_loaded:
		_check(false, "cottage 栖枝不可用，无法测试动作取消")
		return
	var flock = _mk_flock(_cot_perches)
	_seat_all(flock)
	_freeze_timers(flock, 999.0)
	var sim := 12.0 * 3600.0
	var idx := -1
	var snap_pos := Vector3.ZERO
	for i in range(600):
		sim += 60.0 * DT
		flock.update_birds(DT, 25.0, _ctx(sim, 60.0))
		var states: Array = flock.call("debug_idle_state")
		for s_v in states:
			var s: Dictionary = s_v
			if bool(s["active"]) and int(s["state"]) == STATE_PERCH:
				idx = int(s["index"])
				break
		if idx >= 0:
			break
	_check(idx >= 0, "在 10s 内观察到进行中的待机动作")
	if idx < 0:
		flock.free()
		return
	var birds: Array = _birds(flock)
	var b: Dictionary = birds[idx]
	snap_pos = _snap_pos(flock, b)
	var node: Node3D = b["node"]
	var head: Node3D = b["head"]
	var wl: Node3D = b["wing_l"]
	var h_before := head.rotation
	var w_before := wl.rotation
	flock.call("_begin_takeoff", b)
	_check(int(b["state"]) == STATE_TAKEOFF, "起飞中断待机动作（state=TAKEOFF）")
	_check(not bool(b["idle_active"]) and String(b["idle_action"]) == "none", "中断后 idle_active=false / action=none")
	_check((b["idle_off"] as Vector3).length() <= 0.000001, "中断后待机位移清零")
	_check(node.position.distance_to(snap_pos) <= 0.0001, "中断后脚点回到原槽位（err=%.6f）" % node.position.distance_to(snap_pos))
	flock.update_birds(DT, 25.0, _ctx(sim, 60.0))
	_check(int(b["state"]) == STATE_TAKEOFF and not bool(b["idle_active"]), "起飞后下一帧仍保持取消状态")
	# 头部/翼根姿态由 _pose_flying 接管并收敛（不应残留待机动作的异常值）
	_check(is_finite(head.rotation.x) and is_finite(head.rotation.y) and is_finite(wl.rotation.z), "中断后姿态数值有限（head.rot=%s，曾 %s）" % [str(head.rotation), str(h_before)])
	_check(absf(wl.rotation.z) < 3.2, "中断后翼面姿态未爆（wl.z=%.3f，取消前 %s）" % [wl.rotation.z, str(w_before)])
	flock.free()

# ------------------------------------------------------------
# [A] 轻跳回原槽位、沿法线、不侧移不穿面
# ------------------------------------------------------------
func _test_hop_returns_to_slot() -> void:
	print("--- [A] HOP RETURNS TO SLOT ---")
	if not _cottage_loaded:
		_check(false, "cottage 栖枝不可用，无法测试轻跳")
		return
	var flock = _mk_flock(_cot_perches)
	_seat_all(flock)
	_freeze_timers(flock, 999.0)
	var sim := 12.0 * 3600.0
	flock.update_birds(DT, 25.0, _ctx(sim, 60.0))
	var birds: Array = _birds(flock)
	var target: Dictionary = {}
	for b_v in birds:
		var b0: Dictionary = b_v
		if int(b0["state"]) != STATE_PERCH:
			continue
		if bool(flock.call("_idle_hop_safe", b0)):
			target = b0
			break
	_check(not target.is_empty(), "存在适合轻跳的平坦栖枝（hop_safe）")
	if target.is_empty():
		flock.free()
		return
	var perch: Dictionary = flock.call("_find_perch", String(target["perch_id"]))
	var slot_pos: Vector3 = flock.call("_slot_position", perch, int(target["perch_slot"]))
	var n: Vector3 = (perch["normal"] as Vector3).normalized()
	target["idle_action"] = "hop"
	target["idle_active"] = true
	target["idle_t"] = 0.0
	target["idle_dur"] = 0.34
	target["idle_hop_h"] = 0.11
	target["idle_off"] = Vector3.ZERO
	var max_rise := -1.0
	var lateral_bad := 0
	var below := 0
	var finished_frame := -1
	for i in range(60):
		sim += 60.0 * DT
		flock.update_birds(DT, 25.0, _ctx(sim, 60.0))
		var node: Node3D = target["node"]
		var d: Vector3 = node.position - slot_pos
		var rise: float = d.dot(n)
		max_rise = maxf(max_rise, rise)
		var lateral: Vector3 = d - n * rise
		if lateral.length() > 0.0001:
			lateral_bad += 1
		if rise < -0.000001:
			below += 1
		if finished_frame < 0 and not bool(target["idle_active"]):
			finished_frame = i
	_check(max_rise >= 0.05 and max_rise <= 0.14, "轻跳沿栖面法线升起 0.05~0.14m（峰值 %.4f）" % max_rise)
	_check(lateral_bad == 0, "轻跳不侧移（偏离法线样本 %d）" % lateral_bad)
	_check(below == 0, "轻跳不穿入栖面（低于槽点样本 %d）" % below)
	_check(finished_frame >= 0, "轻跳在 60 帧内结束")
	_check(((target["node"] as Node3D).position - slot_pos).length() <= 0.0001, "轻跳结束脚点精确回原槽位（err=%.6f）" % ((target["node"] as Node3D).position - slot_pos).length())
	_check((target["idle_off"] as Vector3).length() <= 0.000001, "轻跳结束 idle_off 清零")
	flock.free()

# ------------------------------------------------------------
# [A-NIGHT] 夜间安静 + 零位移
# ------------------------------------------------------------
func _test_night_quiet_and_still() -> void:
	print("--- [A-NIGHT] NIGHT QUIET ---")
	if not _cottage_loaded:
		_check(false, "cottage 栖枝不可用，无法测试夜间待机")
		return
	var flock = _mk_flock(_cot_perches)
	_seat_all(flock)
	_freeze_timers(flock, 999.0)
	var sim := 23.0 * 3600.0
	var action_samples := {}
	var rest_samples := 0
	var other_samples := 0
	var bad_disp := 0
	var bad_action := 0
	for i in range(1200):
		sim += 60.0 * DT
		flock.update_birds(DT, -10.0, _ctx(sim, 60.0, false))
		var states: Array = flock.call("debug_idle_state")
		for s_v in states:
			var s: Dictionary = s_v
			if int(s["state"]) != STATE_PERCH:
				continue
			var b: Dictionary = _birds(flock)[int(s["index"])]
			if ((b["node"] as Node3D).position - _snap_pos(flock, b)).length() > 0.001:
				bad_disp += 1
			if not bool(s["active"]):
				continue
			var act := String(s["action"])
			action_samples[act] = int(action_samples.get(act, 0)) + 1
			if act == "rest":
				rest_samples += 1
			elif act == "look_around" or act == "preen":
				other_samples += 1
			else:
				bad_action += 1
	var st: Dictionary = flock.call("debug_perch_stats")
	_check(int(st["night"]) == 1, "夜间状态 night=true")
	_check(not action_samples.has("hop") and not action_samples.has("shake") and not action_samples.has("adjust_stance"), "夜间不做位移/剧烈动作（实际 %s）" % str(action_samples.keys()))
	_check(bad_action == 0, "夜间动作均在 rest/look_around/preen 内（异常 %d）" % bad_action)
	_check(rest_samples > other_samples * 2, "夜间安静权重高：rest 样本 %d 远多于其它 %d" % [rest_samples, other_samples])
	_check(bad_disp == 0, "夜间待机零位移（异常样本 %d）" % bad_disp)
	var counts: Dictionary = flock.get_state_counts()
	_check(int(counts["perched"]) == BIRD_COUNT, "夜间 10 只全部停栖（实际 %d）" % int(counts["perched"]))
	flock.free()

# ------------------------------------------------------------
# [A-ROOST] 黄昏归栖 ROOST_ACTIVE：无位移动作
# ------------------------------------------------------------
func _test_roost_active_no_displacement() -> void:
	print("--- [A-ROOST] ROOST ACTIVE ---")
	if not _cottage_loaded:
		_check(false, "cottage 栖枝不可用，无法测试归栖待机")
		return
	var flock = _mk_flock(_cot_perches)
	_seat_all(flock)
	_freeze_timers(flock, 999.0)
	flock.set("_roost_state", 1)
	var sim := 17.5 * 3600.0
	var bad_disp := 0
	var hop_seen := false
	for i in range(600):
		sim += 60.0 * DT
		flock.update_birds(DT, 3.0, _ctx(sim, 60.0, false))
		for b_v in _birds(flock):
			var b: Dictionary = b_v
			if int(b["state"]) != STATE_PERCH:
				continue
			if ((b["node"] as Node3D).position - _snap_pos(flock, b)).length() > 0.001:
				bad_disp += 1
			if bool(b.get("idle_active", false)) and String(b.get("idle_action", "")) == "hop":
				hop_seen = true
	_check(not hop_seen, "归栖进行中不做轻跳位移动作")
	_check(bad_disp == 0, "归栖进行中停栖鸟零位移（异常样本 %d）" % bad_disp)
	var counts: Dictionary = flock.get_state_counts()
	_check(int(counts["perched"]) == BIRD_COUNT, "归栖期间 10 只保持停栖（实际 %d）" % int(counts["perched"]))
	flock.free()

# ------------------------------------------------------------
# [B] 白天多轮起降分布统计
# ------------------------------------------------------------
func _test_distribution_stats() -> void:
	print("--- [B] DAY DISTRIBUTION ---")
	var flock = _mk_flock(_all_perches)
	var seated := _seat_all(flock)
	_check(seated == BIRD_COUNT, "分布测试开始 10 只全部落座（seated=%d）" % seated)
	_stir_timers(flock, 0.35)
	var kind_of := {}
	var zone_of := {}
	for p_v in _all_perches:
		var p: Dictionary = p_v
		kind_of[String(p["id"])] = String(p["kind"])
		zone_of[String(p["id"])] = String(flock.call("_perch_zone", String(p["kind"])))
	var sim := 12.0 * 3600.0
	var max_roof := 0
	var max_ridge := 0
	var used_ids := {}
	var used_kinds := {}
	var used_zones := {}
	var bad_landing_cool := 0
	var prev_states := {}
	var landings := 0
	for b_v in _birds(flock):
		prev_states[int(b_v["index"])] = int(b_v["state"])
	for i in range(3600):
		sim += 60.0 * DT
		flock.update_birds(DT, 25.0, _ctx(sim, 60.0))
		var roof := 0
		var ridge := 0
		for b_v in _birds(flock):
			var b: Dictionary = b_v
			var idx := int(b["index"])
			var st := int(b["state"])
			if st == STATE_PERCH and int(prev_states[idx]) == STATE_LANDING:
				landings += 1
				var cool := float(b.get("idle_cool", 0.0))
				if cool < 0.7 or cool > 2.5:
					bad_landing_cool += 1
			prev_states[idx] = st
			if st != STATE_PERCH and st != STATE_LANDING:
				continue
			var pid := String(b["perch_id"])
			if pid == "":
				continue
			var zone: String = String(zone_of.get(pid, "other"))
			var kind: String = String(kind_of.get(pid, ""))
			used_ids[pid] = true
			used_kinds[kind] = true
			used_zones[zone] = true
			if zone == "roof":
				roof += 1
			if kind == "ridge":
				ridge += 1
		max_roof = maxi(max_roof, roof)
		max_ridge = maxi(max_ridge, ridge)
	var st2: Dictionary = flock.get_state_counts()
	_check(max_roof <= int(Fx.PERCH_ROOF_ZONE_MAX), "屋顶区同时占用 ≤%d（峰值 %d）" % [int(Fx.PERCH_ROOF_ZONE_MAX), max_roof])
	_check(max_ridge <= int(Fx.PERCH_RIDGE_ROW_MAX), "同一排屋脊同时占用 ≤%d（峰值 %d）" % [int(Fx.PERCH_RIDGE_ROW_MAX), max_ridge])
	_check(used_ids.size() >= 8, "多轮起降使用 ≥8 个不同栖枝（实际 %d：%s）" % [used_ids.size(), str(used_ids.size())])
	_check(used_kinds.size() >= 4, "使用 ≥4 种栖枝 kind（实际 %s）" % str(used_kinds.keys()))
	_check(used_zones.size() >= 4, "使用 ≥4 个区域（实际 %s）" % str(used_zones.keys()))
	_check(used_zones.has("porch"), "门廊区 porch_rail 参与白天分布")
	_check(used_zones.has("lamp"), "路灯区 lamp 参与白天分布（实际区域 %s）" % str(used_zones.keys()))
	_check(used_zones.has("roof"), "屋顶区在白天被使用且不超上限")
	_check(int(st2["takeoffs"]) > 5 and int(st2["landings"]) > 5, "白天起降样本充足（takeoffs=%d landings=%d）" % [int(st2["takeoffs"]), int(st2["landings"])])
	_check(bad_landing_cool == 0, "落地后 idle_cool 重置为 0.8~2.4（异常 %d，过渡样本 %d）" % [bad_landing_cool, landings])
	flock.free()

# ------------------------------------------------------------
# [C] 烟囱窗口边界（debug_perch_availability）
# ------------------------------------------------------------
func _test_chimney_window_boundaries() -> void:
	print("--- [C] CHIMNEY WINDOW BOUNDARIES ---")
	if not _cottage_loaded:
		_check(false, "cottage 栖枝不可用，无法测试烟囱窗口")
		return
	var flock = _mk_flock(_cot_perches)
	var cases := [
		[10.0 * 3600.0 + 58.0 * 60.0, 60.0, "ok"],
		[10.0 * 3600.0 + 59.0 * 60.0, 60.0, "smoke_lead"],
		[11.0 * 3600.0, 60.0, "smoke"],
		[11.0 * 3600.0 + 30.0 * 60.0, 60.0, "smoke"],
		[13.0 * 3600.0, 60.0, "ok"],
		[16.0 * 3600.0 + 59.0 * 60.0, 60.0, "smoke_lead"],
		[17.0 * 3600.0, 60.0, "smoke"],
		[19.0 * 3600.0, 60.0, "ok"],
		[10.0 * 3600.0 + 30.0 * 60.0, 1440.0, "smoke_lead"],
		[10.0 * 3600.0, 1440.0, "ok"],
	]
	var bad: Array = []
	for case_v in cases:
		var c: Array = case_v
		var sim := float(c[0])
		var rate := float(c[1])
		var want := String(c[2])
		var av: Array = flock.call("debug_perch_availability", sim, 30.0, false, rate)
		var got := ""
		var others_ok := true
		for e_v in av:
			var e: Dictionary = e_v
			if String(e["id"]) == "chimney_0":
				got = String(e["reason"])
				if bool(e["eligible"]) != (want == "ok"):
					others_ok = false
			elif not bool(e["eligible"]):
				others_ok = false
		if got != want or not others_ok:
			bad.append("%.0f@%.0fx want=%s got=%s others_ok=%s" % [sim, rate, want, got, str(others_ok)])
	_check(bad.is_empty(), "烟囱窗口/提前量边界全部符合（异常 %s）" % str(bad))
	var night_av: Array = flock.call("debug_perch_availability", 23.0 * 3600.0, -10.0, true, 60.0)
	var night_reason := ""
	for e_v in night_av:
		var e: Dictionary = e_v
		if String(e["id"]) == "chimney_0":
			night_reason = String(e["reason"])
	_check(night_reason == "night", "夜间烟囱不可用 reason=night（实际 %s）" % night_reason)
	var unknown_av: Array = flock.call("debug_perch_availability", -1.0, 0.0, false, 60.0)
	var unknown_reason := ""
	for e_v in unknown_av:
		var e: Dictionary = e_v
		if String(e["id"]) == "chimney_0":
			unknown_reason = String(e["reason"])
	_check(unknown_reason == "time_unknown", "时间未知时烟囱不可用 reason=time_unknown（实际 %s）" % unknown_reason)
	flock.free()

# ------------------------------------------------------------
# [C] 窗口前提前起飞（正常路径，不触发 hold）
# ------------------------------------------------------------
func _test_chimney_lead_eviction() -> void:
	print("--- [C] CHIMNEY LEAD TAKEOFF ---")
	var flock = _mk_flock(_chimney_perches())
	var seated := _seat_all(flock)
	_check(seated == BIRD_COUNT, "烟囱提前起飞测试落座 10 只（seated=%d）" % seated)
	_freeze_timers(flock, 999.0)
	_check(bool(flock.call("debug_force_perch", 0, "chimney_0")), "强制 0 号鸟停到烟囱")
	var birds: Array = _birds(flock)
	var b: Dictionary = birds[0]
	b["timer"] = 999.0
	var sim := 10.0 * 3600.0 + 57.0 * 60.0
	var evict_sim := -1.0
	var max_step := 0.0
	var prev_pos: Vector3 = (b["node"] as Node3D).position
	for i in range(300):
		sim += 60.0 * DT
		flock.update_birds(DT, 25.0, _ctx(sim, 60.0))
		var pos: Vector3 = (b["node"] as Node3D).position
		max_step = maxf(max_step, pos.distance_to(prev_pos))
		prev_pos = pos
		if evict_sim < 0.0 and int(b["state"]) != STATE_PERCH:
			evict_sim = sim
	var window_start := 11.0 * 3600.0
	var lead_sim: float = (float(Fx.BIRD_TRANSITION_MAX) + float(Fx.PERCH_SMOKE_LEAD_BUFFER)) * 60.0
	_check(evict_sim > 0.0 and evict_sim < window_start, "窗口前提前起飞（evict_sim=%.0f < 11:00）" % evict_sim)
	_check(evict_sim > 0.0 and absf(evict_sim - (window_start - lead_sim)) <= 3.0, "提前量≈(TRANSITION_MAX+缓冲)*sim_rate（偏差 %.1f 模拟秒）" % (evict_sim - (window_start - lead_sim)))
	var stats: Dictionary = flock.call("debug_perch_stats")
	_check(int(stats["chimney_evictions"]) >= 1, "chimney_evictions≥1（实际 %d）" % int(stats["chimney_evictions"]))
	_check(float(stats["smoke_hold"]) <= 0.0001 and int(stats["smoke_hold_count"]) == 0, "正常提前起飞不触发烟雾 hold（回退路径未触发）")
	var chimney_bad := 0
	for i in range(240):
		sim += 60.0 * DT
		flock.update_birds(DT, 25.0, _ctx(sim, 60.0))
		for b_v in _birds(flock):
			var bb: Dictionary = b_v
			if int(bb["state"]) == STATE_PERCH and String(bb["perch_id"]) == "chimney_0":
				chimney_bad += 1
	_check(chimney_bad == 0, "冒烟窗口内无鸟停烟囱（违规帧 %d）" % chimney_bad)
	_check(max_step < 3.0, "提前起飞无瞬移（单帧最大位移 %.3fm）" % max_step)
	flock.free()

# ------------------------------------------------------------
# [C] 时间跳入窗口：同帧驱逐 + smoke hold 安全回退
# ------------------------------------------------------------
func _test_time_jump_hold() -> void:
	print("--- [C] TIME JUMP SMOKE HOLD ---")
	var flock = _mk_flock(_chimney_perches())
	_seat_all(flock)
	_freeze_timers(flock, 999.0)
	flock.update_birds(DT, 25.0, _ctx(12.0 * 3600.0, 60.0))
	_check(bool(flock.call("debug_force_perch", 1, "chimney_0")), "跳时前强制 1 号鸟停到烟囱")
	var birds: Array = _birds(flock)
	var b: Dictionary = birds[1]
	b["timer"] = 999.0
	var pos_before: Vector3 = (b["node"] as Node3D).position
	var sim := 11.0 * 3600.0 + 5.0 * 60.0
	flock.update_birds(DT, 25.0, _ctx(sim, 60.0))
	_check(int(b["state"]) != STATE_PERCH, "时间跳入冒烟窗口当帧驱逐烟囱鸟")
	var hold_now := float(flock.call("smoke_hold_remaining"))
	_check(hold_now >= float(Fx.BIRD_TRANSITION_MAX) + 0.6 - 0.001, "当帧启动烟雾 hold（剩余 %.2fs）" % hold_now)
	var stats: Dictionary = flock.call("debug_perch_stats")
	_check(String(stats["hold_reason"]) == "bird_on_chimney", "hold 原因=bird_on_chimney（实际 %s）" % String(stats["hold_reason"]))
	_check(int(stats["smoke_hold_count"]) == 1, "hold 计数=1（实际 %d）" % int(stats["smoke_hold_count"]))
	var moved: float = (b["node"] as Node3D).position.distance_to(pos_before)
	_check(moved < 1.0, "跳时驱逐不瞬移（当帧位移 %.3fm）" % moved)
	var frames := 0
	for i in range(150):
		sim += 60.0 * DT
		flock.update_birds(DT, 25.0, _ctx(sim, 60.0))
		frames += 1
		if float(flock.call("smoke_hold_remaining")) <= 0.0:
			break
	_check(float(flock.call("smoke_hold_remaining")) <= 0.0, "烟雾 hold 在 %.2fs 内释放" % (float(frames) * DT))
	_check(frames >= 60 and frames <= 120, "hold 时长≈TRANSITION_MAX+0.6=1.6s（实际 %.2fs）" % (float(frames) * DT))
	flock.free()

# ------------------------------------------------------------
# [C] ChimneySmoke.set_sim_seconds(sim, hold) 行为
# ------------------------------------------------------------
func _test_smoke_hold_clock() -> void:
	print("--- [C] SMOKE CLOCK HOLD ---")
	var holder := Node3D.new()
	root.add_child(holder)
	var smk: Dictionary = Fx.smoke(holder, Vector3(0.0, 1.0, 0.0))
	var ctl = smk.get("ctl", null)
	_check(ctl != null, "炊烟控制器可创建（smoke() 返回 ctl）")
	if ctl == null:
		holder.free()
		return
	ctl.set_sim_seconds(11.0 * 3600.0 + 5.0 * 60.0, true)
	var s1: Dictionary = ctl.debug_state()
	_check(bool(s1["hold"]) == true, "hold=true 时 debug_state().hold=true")
	_check(bool(s1["emitting"]) == false and float(s1["ratio"]) <= 0.0001, "hold 时强制不冒烟（emitting=false, ratio=0）")
	_check(int(s1["hold_count"]) == 1 and String(s1["hold_reason"]) == "bird_on_chimney", "hold_count=1 / hold_reason=bird_on_chimney")
	_check(String(s1["time_label"]) == "11:05:00", "hold 时仍更新 time_label（%s）" % String(s1["time_label"]))
	_check(bool(s1["active_window"]) == true, "hold 时仍更新窗口判断（active_window=true）")
	_check(int(s1["created_count"]) >= 1 and not (s1["emitters"] as Array).is_empty(), "debug_state 保留 emitters 字段")
	ctl.set_sim_seconds(11.0 * 3600.0 + 6.0 * 60.0, true)
	var s2: Dictionary = ctl.debug_state()
	_check(int(s2["hold_count"]) == 1, "连续 hold 只累计一次 hold_count（实际 %d）" % int(s2["hold_count"]))
	ctl.set_sim_seconds(11.0 * 3600.0 + 7.0 * 60.0, false)
	var s3: Dictionary = ctl.debug_state()
	_check(bool(s3["hold"]) == false, "hold 释放后 hold=false")
	_check(bool(s3["emitting"]) == true and float(s3["ratio"]) > 0.5, "释放后窗口内恢复冒烟（ratio=%.2f）" % float(s3["ratio"]))
	holder.free()

# ------------------------------------------------------------
# [C] 夜间烟囱禁停 + 安全改停
# ------------------------------------------------------------
func _test_night_chimney_eviction() -> void:
	print("--- [C] NIGHT CHIMNEY EVICTION ---")
	var flock = _mk_flock(_chimney_perches())
	_seat_all(flock)
	_freeze_timers(flock, 999.0)
	flock.update_birds(DT, -10.0, _ctx(23.0 * 3600.0, 60.0, false))
	_check(bool(flock.call("debug_force_perch", 2, "chimney_0")), "夜间强制 2 号鸟停到烟囱")
	var birds: Array = _birds(flock)
	var b: Dictionary = birds[2]
	b["timer"] = 999.0
	var av: Array = flock.call("debug_perch_availability", 23.0 * 3600.0, -10.0, true, 60.0)
	var reason := ""
	for e_v in av:
		var e: Dictionary = e_v
		if String(e["id"]) == "chimney_0":
			reason = String(e["reason"])
	_check(reason == "night", "夜间 debug_perch_availability 烟囱 reason=night（实际 %s）" % reason)
	var evicted := false
	for i in range(6):
		flock.update_birds(DT, -10.0, _ctx(23.0 * 3600.0 + float(i) * 60.0 * DT, 60.0, false))
		if int(b["state"]) != STATE_PERCH:
			evicted = true
	_check(evicted, "夜间停在烟囱上的鸟被安全驱逐（正常起飞）")
	var chimney_bad := 0
	for i in range(600):
		flock.update_birds(DT, -10.0, _ctx(23.0 * 3600.0 + 300.0 + float(i) * 60.0 * DT, 60.0, false))
		for b_v in _birds(flock):
			var bb: Dictionary = b_v
			if int(bb["state"]) == STATE_PERCH and String(bb["perch_id"]) == "chimney_0":
				chimney_bad += 1
	_check(chimney_bad == 0, "夜间无鸟停烟囱（违规帧 %d）" % chimney_bad)
	var counts: Dictionary = flock.get_state_counts()
	_check(int(counts["perched"]) == BIRD_COUNT, "夜间驱逐后 10 只全部重新停栖（实际 %d）" % int(counts["perched"]))
	flock.free()

# ------------------------------------------------------------
# [D] debug_force_perch + 夜间布局回归
# ------------------------------------------------------------
func _test_force_perch_and_layout() -> void:
	print("--- [D] FORCE PERCH / LAYOUT ---")
	var flock = _mk_flock(_cot_perches)
	_check(bool(flock.call("debug_force_perch", 0, "ridge_0")), "debug_force_perch 合法调用返回 true")
	var b: Dictionary = _birds(flock)[0]
	_check(int(b["state"]) == STATE_PERCH and String(b["perch_id"]) == "ridge_0", "强制落座状态/栖枝正确")
	var perch: Dictionary = flock.call("_find_perch", "ridge_0")
	var want: Vector3 = flock.call("_slot_position", perch, int(b["perch_slot"]))
	_check((b["node"] as Node3D).position.distance_to(want) <= 0.0001, "强制落座脚点=槽点")
	_check(not bool(b["idle_active"]) and (b["idle_off"] as Vector3).length() <= 0.000001, "强制落座清理待机状态")
	_check(not bool(flock.call("debug_force_perch", -1, "ridge_0")), "index 非法返回 false")
	_check(not bool(flock.call("debug_force_perch", 0, "no_such_perch")), "perch_id 不存在返回 false")
	_check(not bool(flock.call("debug_force_perch", 1, "ridge_0")), "单槽栖枝已被占用返回 false")
	flock.free()
	var flock2 = _mk_flock(_cot_perches)
	var seated := _seat_all(flock2)
	_check(seated == BIRD_COUNT, "布局回归：10 只全部落座（seated=%d）" % seated)
	for i in range(600):
		flock2.update_birds(DT, -10.0, _ctx(23.0 * 3600.0 + float(i) * 60.0 * DT, 60.0, false))
	var counts: Dictionary = flock2.get_state_counts()
	_check(int(counts["perched"]) == BIRD_COUNT, "夜间 10 只全部停栖（实际 %d）" % int(counts["perched"]))
	_check(int(counts["perch_conflicts"]) == 0, "perch_conflicts=0")
	var bad_foot := 0
	for b_v in _birds(flock2):
		var bb: Dictionary = b_v
		if int(bb["state"]) != STATE_PERCH:
			continue
		if ((bb["node"] as Node3D).position - _snap_pos(flock2, bb)).length() > 0.01:
			bad_foot += 1
	_check(bad_foot == 0, "夜间停栖脚点=槽点（误差>1cm 的 %d 只）" % bad_foot)
	flock2.free()

# ------------------------------------------------------------
# [B] 新 kind/区域映射
# ------------------------------------------------------------
func _test_kind_zones() -> void:
	print("--- [B] KIND ZONES ---")
	var flock = _mk_flock(_chimney_perches())
	_check(String(flock.call("_perch_zone", "porch_rail")) == "porch", "porch_rail → porch 区")
	_check(String(flock.call("_perch_zone", "porch_beam")) == "porch", "porch_beam → porch 区")
	_check(String(flock.call("_perch_zone", "lamp")) == "lamp", "lamp → lamp 区")
	_check(String(flock.call("_perch_zone", "ridge")) == "roof" and String(flock.call("_perch_zone", "eave")) == "roof", "ridge/eave → roof 区")
	_check(String(flock.call("_perch_zone", "tree_branch")) == "tree" and String(flock.call("_perch_zone", "garden_post")) == "garden", "tree_branch/garden_post 区域映射正确")
	var stats: Dictionary = flock.call("debug_perch_stats")
	_check(int(stats["roof_count"]) == 1 and int(stats["ridge_count"]) == 0, "烟囱测试点集仅 chimney 计入屋顶区（roof_count=%d ridge=%d）" % [int(stats["roof_count"]), int(stats["ridge_count"])])
	flock.free()
