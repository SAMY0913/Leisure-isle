extends SceneTree
# P7-V1 生态节奏探针（headless）：黄昏归栖 / 船鸟联动 / 近海航段几何 / main 集成。
# 判据：exit 0 且 [ECO7] RESULT fail=0。固定 dt、固定上下文（day/rising/paused），不用真实时钟。

const Fx = preload("res://scripts/fx.gd")
const WorldScript = preload("res://scripts/world.gd")
const MathX = preload("res://scripts/isle_math.gd")
const MainScene = preload("res://isle.tscn")

const DT := 1.0 / 60.0
const ROOST_NONE := 0
const ROOST_ACTIVE := 1
const ROOST_NIGHT := 2
const ST_FLY := 0
const ST_TAKEOFF := 1
const ST_LANDING := 2
const ST_PERCH := 3

var _pass := 0
var _fail := 0
var _fails: Array = []

func _initialize() -> void:
	print("[ECO7] P7-V1 ecological rhythm probe start")
	await process_frame
	_probe_world_routes()
	_probe_dusk_roost()
	_probe_rising_no_trigger()
	_probe_threshold_jitter()
	_probe_paused()
	_probe_no_perch()
	_probe_perch_a6()
	_probe_night_settle_a7()
	_probe_night_jump_a8()
	_probe_boat_pass_b1()
	_probe_boat_guards_b2()
	_probe_boat_no_interrupt_b3()
	await _probe_main_integration()
	print("[ECO7] RESULT pass=%d fail=%d" % [_pass, _fail])
	for m in _fails:
		print("[ECO7] FAIL: ", m)
	quit(0 if _fail == 0 else 1)

# ---------------- helpers ----------------
func _check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		_fails.append(msg)
		print("[ECO7] FAIL ", msg)

func _perches(n: int, slots: int) -> Array:
	var out: Array = []
	for i in range(n):
		var a := TAU * float(i) / float(n)
		var p := Vector3(cos(a) * 18.0, 4.0, sin(a) * 18.0)
		var facing := Vector3(-cos(a), 0.0, -sin(a))
		var kind := "tree_branch"
		if i % 5 == 4:
			kind = "ridge"
		out.append({
			"id": "probe_perch_%d" % i,
			"pos": p,
			"facing": facing,
			"radius": 2.0,
			"kind": kind,
			"slots": slots,
			"normal": Vector3.UP,
		})
	return out

func _spawn(perches: Array):
	var flock = Fx.BirdFlock.new()
	root.add_child(flock)
	flock.setup(perches)
	return flock

func _ctx(day: int, rising: bool, paused: bool = false, src: String = "sim") -> Dictionary:
	return {
		"day": day,
		"rising": rising,
		"sim_seconds": 86400.0 * float(day) + 43200.0,
		"time_source": src,
		"paused": paused,
	}

func _ctx_dir(day: int, paused: bool = false) -> Dictionary:
	return {
		"day": day,
		"sim_seconds": 86400.0 * float(day) + 43200.0,
		"time_source": "sim",
		"paused": paused,
	}

func _run(flock, frames: int, alt: float, ctx: Dictionary) -> void:
	for i in range(frames):
		flock.update_birds(DT, alt, ctx)

func _positions(flock) -> Array:
	var out: Array = []
	for s in flock.debug_snapshot():
		out.append(s["pos"])
	return out

func _max_step(flock, prev: Array) -> float:
	var snap: Array = flock.debug_snapshot()
	var best := 0.0
	for i in range(snap.size()):
		var p: Vector3 = snap[i]["pos"]
		best = maxf(best, p.distance_to(prev[i]))
		prev[i] = p
	return best

func _all_finite(flock) -> bool:
	for s in flock.debug_snapshot():
		var p: Vector3 = s["pos"]
		if not is_finite(p.x) or not is_finite(p.y) or not is_finite(p.z):
			return false
	return true

func _perch_layout_ok(flock, label: String) -> void:
	var snap: Array = flock.debug_snapshot()
	var bad_pos := 0
	var bad_slot := 0
	var seen: Dictionary = {}
	var counts: Dictionary = flock.get_state_counts()
	for s in snap:
		if int(s["state"]) != ST_PERCH:
			continue
		var perch: Dictionary = flock.call("_find_perch", String(s["perch_id"]))
		if perch.is_empty():
			bad_slot += 1
			continue
		var slot := int(s["perch_slot"])
		var key := String(s["perch_id"]) + "#" + str(slot)
		if seen.has(key):
			bad_slot += 1
		seen[key] = true
		var sp: Vector3 = flock.call("_slot_position", perch, slot)
		var p: Vector3 = s["pos"]
		if p.distance_to(sp) > 0.02:
			bad_pos += 1
	_check(bad_pos == 0, label + "：停栖位置贴合落点槽（超限 %d）" % bad_pos)
	_check(bad_slot == 0, label + "：落点 id/槽位唯一有效（异常 %d）" % bad_slot)
	_check(int(counts["perch_conflicts"]) == 0, label + "：无落点占用冲突")
	_check(_all_finite(flock), label + "：坐标有限无 NaN")

func _pts(v) -> Array:
	var out: Array = []
	if v is Curve3D:
		var curve: Curve3D = v
		var bl := curve.get_baked_length()
		for i in range(65):
			out.append(curve.sample_baked(bl * float(i) / 64.0))
	elif v is PackedVector3Array:
		for p in (v as PackedVector3Array):
			out.append(p)
	elif v is Array:
		for p in (v as Array):
			if p is Vector3:
				out.append(p)
	return out

func _poly_len(pts: Array) -> float:
	var total := 0.0
	for i in range(pts.size() - 1):
		total += (pts[i] as Vector3).distance_to(pts[i + 1] as Vector3)
	return total

func _sample_pts(pts: Array, dist: float) -> Vector3:
	var acc := 0.0
	for i in range(pts.size() - 1):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var seg := a.distance_to(b)
		if acc + seg >= dist and seg > 0.0001:
			return a.lerp(b, (dist - acc) / seg)
		acc += seg
	return pts[pts.size() - 1]

# ---------------- world 航线几何 ----------------
func _probe_world_routes() -> void:
	print("[ECO7] --- world routes ---")
	var data: Dictionary = WorldScript._sail_routes()
	var routes: Array = data.get("routes", [])
	_check(routes.size() >= 9, "航线数量符合既有设计（%d）" % routes.size())
	var coastal_count := 0
	var far_count := 0
	var bad_meta := 0
	var bad_geom := 0
	for r_v in routes:
		var r: Dictionary = r_v
		var kind := String(r.get("kind", ""))
		if kind == "coastal":
			coastal_count += 1
			if not (r.has("shore_a0") and r.has("shore_a1")):
				bad_meta += 1
				continue
			var pts := _pts(r.get("out", null))
			var a0 := float(r["shore_a0"])
			var a1 := float(r["shore_a1"])
			var total := _poly_len(pts)
			var d: float = WorldScript.shore_trigger_dist(pts, a0, a1)
			if d <= 0.0 or d >= total * 0.95:
				bad_geom += 1
				continue
			var p: Vector3 = _sample_pts(pts, d)
			var az := fposmod(atan2(p.z, p.x), TAU)
			if az < a0 - 0.001 or az > a1 + 0.001:
				bad_geom += 1
			var radius := sqrt(p.x * p.x + p.z * p.z)
			var coast := MathX.coast_radius(az)
			if radius < coast + 3.0 or radius > coast + 18.0:
				bad_geom += 1
		elif kind == "far":
			far_count += 1
			if r.has("shore_a0") or r.has("shore_a1"):
				bad_meta += 1
	_check(coastal_count == 4, "近海航线数量为 4（%d）" % coastal_count)
	_check(far_count >= 5, "远海航线数量 >=5（%d）" % far_count)
	_check(bad_meta == 0, "近海有 shore 元数据、远海无（异常 %d）" % bad_meta)
	_check(bad_geom == 0, "触发点落在真实近海弧段且半径合理（异常 %d）" % bad_geom)

# ---------------- A1 连续下降触发黄昏归栖 ----------------
func _probe_dusk_roost() -> void:
	print("[ECO7] --- A1 dusk roost ---")
	var flock = _spawn(_perches(8, 3))
	_run(flock, 240, 12.0, _ctx(100, true))
	var st0: Dictionary = flock.get_state_counts()
	_check(int(st0["roost_state"]) == ROOST_NONE, "白天未误触发归栖（state=%d）" % int(st0["roost_state"]))
	_check(int(st0["airborne"]) >= 4, "白天空中有足够海鸥（airborne=%d）" % int(st0["airborne"]))
	var starts0 := int(st0["roost_starts"])
	var land0 := int(st0["landings"])
	var ctxd := _ctx(100, false)
	var alt := 12.0
	var prev := _positions(flock)
	var max_jump := 0.0
	var landing_frames: Array = []
	var start_frame := -1
	var start_alt := -999.0
	var last_land := land0
	var run_frames := 0
	while alt > 1.0 and run_frames < 20000:
		alt = maxf(1.0, alt - 0.004)
		flock.update_birds(DT, alt, ctxd)
		run_frames += 1
		var st: Dictionary = flock.get_state_counts()
		if start_frame < 0 and int(st["roost_state"]) == ROOST_ACTIVE:
			start_frame = run_frames
			start_alt = alt
		var li := int(st["landings"])
		if li > last_land:
			for k in range(li - last_land):
				landing_frames.append(run_frames)
			last_land = li
		max_jump = maxf(max_jump, _max_step(flock, prev))
	var st1: Dictionary = flock.get_state_counts()
	print("[ECO7] A1 start_frame=%d start_alt=%.3f landings=%d max_jump=%.3f airborne=%d" % [start_frame, start_alt, landing_frames.size(), max_jump, int(st1["airborne"])])
	_check(start_frame >= 0, "太阳下穿 +4° 后启动归栖")
	_check(start_alt > 3.2 and start_alt <= 4.0, "启动高度在 +4° 附近（%.3f°）" % start_alt)
	_check(int(st1["roost_starts"]) - starts0 == 1, "连续下降只启动一次（starts %d -> %d）" % [starts0, int(st1["roost_starts"])])
	_check(landing_frames.size() >= 2, "归栖分批发生（降落 %d 次）" % landing_frames.size())
	_check(max_jump < 3.0, "归栖过程无瞬移（单帧最大位移 %.3f m）" % max_jump)
	_check(int(st1["airborne"]) <= 3, "归栖推进后空中数量下降（airborne=%d）" % int(st1["airborne"]))
	_check(int(st1["perch_conflicts"]) == 0, "归栖期间落点无互斥冲突")
	_run(flock, 900, -4.0, ctxd)
	var stn: Dictionary = flock.get_state_counts()
	print("[ECO7] A1 night perched=%d airborne=%d state=%d" % [int(stn["perched"]), int(stn["airborne"]), int(stn["roost_state"])])
	_check(int(stn["roost_state"]) == ROOST_NIGHT, "进入夜间后归栖转为 ROOST_NIGHT")
	_check(int(stn["perched"]) == 10 and int(stn["airborne"]) == 0, "夜间全部停栖（perched=%d airborne=%d）" % [int(stn["perched"]), int(stn["airborne"])])
	_check(int(stn["roost_starts"]) - starts0 == 1, "夜间不再重复启动归栖")
	_perch_layout_ok(flock, "A1 夜间")
	var take_night0 := int(stn["takeoffs"])
	_run(flock, 600, -5.0, ctxd)
	var stn2: Dictionary = flock.get_state_counts()
	_check(int(stn2["takeoffs"]) == take_night0, "夜间稳定后不重复起飞")
	flock.free()

# ---------------- A2 日出上升不误触发 ----------------
func _probe_rising_no_trigger() -> void:
	print("[ECO7] --- A2 rising no trigger ---")
	var flock = _spawn(_perches(8, 3))
	var ctxn := _ctx(200, false)
	_run(flock, 400, -4.0, ctxn)
	var stn: Dictionary = flock.get_state_counts()
	_check(bool(stn["night"]), "先进入夜间")
	var alt := -4.0
	var ctxr := _ctx(200, true)
	var dawning_frame := -1
	var start_frame := -1
	var first_takeoff_frame := -1
	var takeoff_frame_count := 0
	var last_take := int(stn["takeoffs"])
	var run_frames := 0
	while alt < 10.0 and run_frames < 8000:
		alt = minf(10.0, alt + 0.004)
		flock.update_birds(DT, alt, ctxr)
		run_frames += 1
		var st: Dictionary = flock.get_state_counts()
		if dawning_frame < 0 and not bool(st["night"]):
			dawning_frame = run_frames
		if start_frame < 0 and int(st["roost_state"]) != ROOST_NONE:
			start_frame = run_frames
		var ti := int(st["takeoffs"])
		if ti > last_take:
			if first_takeoff_frame < 0:
				first_takeoff_frame = run_frames
			takeoff_frame_count += 1
			last_take = ti
	var st1: Dictionary = flock.get_state_counts()
	print("[ECO7] A2 dawning=%d first_takeoff=%d takeoff_frames=%d starts=%d" % [dawning_frame, first_takeoff_frame, takeoff_frame_count, int(st1["roost_starts"])])
	_check(start_frame < 0, "太阳从地平线下上升时不触发黄昏归栖")
	_check(int(st1["roost_starts"]) == 0, "上升过程 roost_starts 保持 0")
	_check(dawning_frame >= 0, "升过 +2° 后进入白天")
	_check(first_takeoff_frame >= 0, "清晨恢复起飞活动")
	_check(first_takeoff_frame - dawning_frame >= 90, "清晨起飞错峰（首个起飞在入昼 %.2fs 后）" % (float(first_takeoff_frame - dawning_frame) * DT))
	_check(takeoff_frame_count >= 2, "清晨起飞分布于多个帧（%d 帧）" % takeoff_frame_count)
	_run(flock, 1200, 10.0, ctxr)
	var st2: Dictionary = flock.get_state_counts()
	_check(int(st2["airborne"]) >= 4, "清晨恢复后空中数量恢复（airborne=%d）" % int(st2["airborne"]))
	flock.free()

# ---------------- A3 阈值抖动 / 幂等 / 回拖 / 跨日 / 模式切换 ----------------
func _probe_threshold_jitter() -> void:
	print("[ECO7] --- A3 jitter/idempotent ---")
	var flock = _spawn(_perches(8, 3))
	_run(flock, 240, 12.0, _ctx(300, true))
	var st0: Dictionary = flock.get_state_counts()
	var starts0 := int(st0["roost_starts"])
	flock.update_birds(DT, 4.0, _ctx_dir(300))
	var st1: Dictionary = flock.get_state_counts()
	print("[ECO7] A3 jump4 state=%d starts=%d alt_dir_from_sun_prev" % [int(st1["roost_state"]), int(st1["roost_starts"])])
	_check(int(st1["roost_state"]) == ROOST_ACTIVE, "单帧跳入黄昏（方向由历史太阳高度判定）也能启动")
	_check(int(st1["roost_starts"]) - starts0 == 1, "跳入黄昏启动一次")
	var i := 0
	var jitter_starts := int(st1["roost_starts"])
	var jitter_active_all := true
	while i < 300:
		var alt := 3.95 + 0.25 * sin(float(i) * 0.15)
		flock.update_birds(DT, alt, _ctx_dir(300))
		var st: Dictionary = flock.get_state_counts()
		if int(st["roost_state"]) != ROOST_ACTIVE:
			jitter_active_all = false
		i += 1
	var st2: Dictionary = flock.get_state_counts()
	_check(int(st2["roost_starts"]) == jitter_starts, "阈值附近抖动不重复启动归栖")
	_check(jitter_active_all, "抖动期间归栖保持进行中（未被意外取消）")
	flock.update_birds(DT, 8.0, _ctx_dir(300))
	var st3: Dictionary = flock.get_state_counts()
	var eco3: Dictionary = flock.debug_eco_state()
	_check(int(st3["roost_state"]) == ROOST_NONE, "时间回拖到白天取消未完成归栖")
	_check(String(eco3["roost_skip_reason"]) == "cancel_return_day", "取消原因记录为 cancel_return_day（%s）" % String(eco3["roost_skip_reason"]))
	var starts_after_cancel := int(st3["roost_starts"])
	flock.update_birds(DT, 3.5, _ctx_dir(300))
	_run(flock, 120, 3.5, _ctx_dir(300))
	var st4: Dictionary = flock.get_state_counts()
	_check(int(st4["roost_state"]) == ROOST_NONE, "同一模拟日回拖后不重演已消费的归栖")
	_check(int(st4["roost_starts"]) == starts_after_cancel, "同一模拟日回拖不新增启动")
	flock.update_birds(DT, 3.4, _ctx_dir(301))
	var st5: Dictionary = flock.get_state_counts()
	_check(int(st5["roost_state"]) == ROOST_ACTIVE, "新模拟日可重新启动归栖")
	_check(int(st5["roost_starts"]) == starts_after_cancel + 1, "新模拟日启动计数 +1")
	var starts_day_new := int(st5["roost_starts"])
	flock.update_birds(DT, 3.3, _ctx(301, false, false, "real"))
	var st6: Dictionary = flock.get_state_counts()
	_check(int(st6["roost_starts"]) == starts_day_new, "同日切换时间来源不重复启动归栖")
	_check(int(st6["roost_state"]) == ROOST_ACTIVE, "模拟/现实时间切换后归栖状态保持")
	flock.free()

# ---------------- A4 暂停不推进归栖 ----------------
func _probe_paused() -> void:
	print("[ECO7] --- A4 paused ---")
	var flock = _spawn(_perches(8, 3))
	_run(flock, 240, 12.0, _ctx(400, true))
	flock.update_birds(DT, 4.0, _ctx(400, false))
	var st0: Dictionary = flock.get_state_counts()
	_check(int(st0["roost_state"]) == ROOST_ACTIVE, "先启动归栖")
	var land0 := int(st0["roost_landings"])
	var starts0 := int(st0["roost_starts"])
	for i in range(90):
		flock.update_birds(DT, 4.0, _ctx(400, false, true))
	var eco1: Dictionary = flock.debug_eco_state()
	var st1: Dictionary = flock.get_state_counts()
	_check(bool(eco1["paused"]), "暂停标记传入海鸥状态机")
	_check(int(st1["roost_landings"]) == land0, "暂停期间不推进归栖（landings 不变）")
	_check(int(st1["roost_starts"]) == starts0, "暂停期间不重复启动归栖")
	_check(int(st1["roost_state"]) == ROOST_ACTIVE, "暂停期间归栖状态保持")
	_run(flock, 1800, 2.2, _ctx(400, false, false))
	var st2: Dictionary = flock.get_state_counts()
	_check(int(st2["roost_landings"]) > land0, "解除暂停后归栖继续推进")
	flock.free()

# ---------------- A5 无可用栖点安全跳过 ----------------
func _probe_no_perch() -> void:
	print("[ECO7] --- A5 no perch ---")
	var flock = _spawn(_perches(8, 3))
	_run(flock, 240, 12.0, _ctx(500, true))
	flock.update_birds(DT, 4.0, _ctx(500, false))
	var st0: Dictionary = flock.get_state_counts()
	var land0 := int(st0["roost_landings"])
	flock.set_perches([])
	var alt := 4.0
	for i in range(600):
		alt = maxf(3.0, alt - 0.002)
		flock.update_birds(DT, alt, _ctx(500, false))
	var st1: Dictionary = flock.get_state_counts()
	var eco1: Dictionary = flock.debug_eco_state()
	_check(int(st1["roost_skips"]) > 0, "无可用栖点时会跳过归栖（skips=%d）" % int(st1["roost_skips"]))
	var skip_reason := String(eco1["roost_skip_reason"])
	_check(skip_reason == "no_free_slot" or skip_reason == "no_eligible_bird", "跳过原因为无可用栖点/无候选鸟（%s）" % skip_reason)
	_check(int(st1["roost_landings"]) == land0, "无栖点期间不执行归栖降落")
	_check(_all_finite(flock), "无栖点期间无 NaN 崩溃")
	flock.set_perches(_perches(10, 3))
	_run(flock, 1500, 2.0, _ctx(500, false))
	var st2: Dictionary = flock.get_state_counts()
	_check(int(st2["roost_landings"]) >= land0 + 1, "恢复栖点后归栖可继续（landings %d -> %d）" % [land0, int(st2["roost_landings"])])
	_check(int(st2["perch_conflicts"]) == 0, "恢复栖点后无占用冲突")
	flock.free()

# ---------------- A6 关键态安全 + 栖点约束 ----------------
func _probe_perch_a6() -> void:
	print("[ECO7] --- A6 pick safety/perch constraints ---")
	var flock = _spawn(_perches(8, 3))
	_run(flock, 240, 12.0, _ctx(600, true))
	flock.update_birds(DT, 4.0, _ctx(600, false))
	var st0: Dictionary = flock.get_state_counts()
	_check(int(st0["roost_state"]) == ROOST_ACTIVE, "A6 归栖已启动")
	var alt := 4.0
	var pick_safe := true
	var pick_checked := 0
	for i in range(600):
		alt = maxf(3.0, alt - 0.002)
		flock.update_birds(DT, alt, _ctx(600, false))
		if i % 6 == 0:
			var pick = flock.call("_pick_roost_bird")
			if pick is Dictionary and not (pick as Dictionary).is_empty():
				pick_checked += 1
				if int((pick as Dictionary)["state"]) != ST_FLY:
					pick_safe = false
	print("[ECO7] A6 picks=%d" % pick_checked)
	_check(pick_checked > 0, "归栖期间存在可安全选择的巡航鸟")
	_check(pick_safe, "归栖只选择巡航态个体，不打断起飞/降落")
	_perch_layout_ok(flock, "A6 归栖中")
	var start_count := int(flock.get_state_counts()["roost_starts"])
	_run(flock, 240, 3.0, _ctx(600, false))
	var st1: Dictionary = flock.get_state_counts()
	_check(int(st1["roost_starts"]) == start_count, "归栖进行中不重复启动")
	flock.free()

# ---------------- A7 夜间停栖槽位约束 ----------------
func _probe_night_settle_a7() -> void:
	print("[ECO7] --- A7 night perch constraints ---")
	var flock = _spawn(_perches(8, 3))
	_run(flock, 240, 12.0, _ctx(700, true))
	flock.update_birds(DT, 4.0, _ctx(700, false))
	_run(flock, 1200, -4.0, _ctx(700, false))
	var st: Dictionary = flock.get_state_counts()
	print("[ECO7] A7 perched=%d airborne=%d state=%d conflicts=%d" % [int(st["perched"]), int(st["airborne"]), int(st["roost_state"]), int(st["perch_conflicts"])])
	_check(int(st["perched"]) == 10 and int(st["airborne"]) == 0, "夜间全部停栖（perched=%d）" % int(st["perched"]))
	_check(int(st["roost_state"]) == ROOST_NIGHT, "夜间归栖状态为 ROOST_NIGHT")
	_perch_layout_ok(flock, "A7 夜间")
	flock.free()

# ---------------- A8 直接跳深夜不补演 / 回日 / 再入黄昏 ----------------
func _probe_night_jump_a8() -> void:
	print("[ECO7] --- A8 jump deep night ---")
	var flock = _spawn(_perches(8, 3))
	_run(flock, 240, 12.0, _ctx(800, true))
	var st0: Dictionary = flock.get_state_counts()
	var starts0 := int(st0["roost_starts"])
	flock.update_birds(DT, -8.0, _ctx(800, false))
	var st1: Dictionary = flock.get_state_counts()
	_check(bool(st1["night"]), "单帧跳入深夜后进入夜间")
	_check(int(st1["roost_starts"]) == starts0, "直接跳深夜不补演已错过的归栖启动")
	_check(int(st1["roost_state"]) == ROOST_NONE, "跳深夜时未消费的归栖不被标记为已执行")
	_run(flock, 900, -8.0, _ctx(800, false))
	var st2: Dictionary = flock.get_state_counts()
	_check(int(st2["perched"]) == 10 and int(st2["airborne"]) == 0, "夜间状态与当前世界阶段重新协调（全部停栖）")
	flock.update_birds(DT, 12.0, _ctx(800, true))
	var st3: Dictionary = flock.get_state_counts()
	_check(not bool(st3["night"]), "跳回白天后退出夜间")
	_check(int(st3["roost_state"]) == ROOST_NONE, "清晨清除夜间归栖状态")
	_check(int(st3["takeoffs"]) == int(st2["takeoffs"]), "清晨首帧不立即全体起飞")
	_run(flock, 240, 12.0, _ctx(800, true))
	var st4: Dictionary = flock.get_state_counts()
	_check(int(st4["takeoffs"]) > int(st2["takeoffs"]), "清晨随后逐渐恢复起飞")
	flock.update_birds(DT, 3.9, _ctx(800, false))
	var st5: Dictionary = flock.get_state_counts()
	_check(int(st5["roost_state"]) == ROOST_ACTIVE, "本日从未消费归栖时，跳入黄昏可正常启动")
	_check(int(st5["roost_starts"]) == starts0 + 1, "启动计数 +1")
	flock.free()

# ---------------- B1 帆船近海经过触发海鸥响应 ----------------
func _probe_boat_pass_b1() -> void:
	print("[ECO7] --- B1 boat shore pass ---")
	var flock = _spawn(_perches(10, 3))
	var ctx := _ctx(1000, true)
	_run(flock, 300, 14.0, ctx)
	var attempts0 := int(flock.debug_eco_state()["boat_pass_attempts"])
	var r1: Dictionary = flock.on_boat_shore_pass(7, Vector3(40.0, 1.0, 12.0), 14.0)
	var st1: Dictionary = flock.get_state_counts()
	print("[ECO7] B1 pass1 ok=%s birds=%d reason=%s handled=%d" % [str(bool(r1["ok"])), int(r1["birds"]), String(r1["reason"]), int(st1["boat_trip_handled"])])
	_check(bool(r1["ok"]), "近海航段经过触发海鸥响应（reason=%s）" % String(r1["reason"]))
	_check(int(r1["birds"]) >= 1 and int(r1["birds"]) <= 2, "单次事件最多 1-2 只海鸥（%d）" % int(r1["birds"]))
	_check(int(st1["boat_trip_handled"]) == 7, "记录已处理航次号（%d）" % int(st1["boat_trip_handled"]))
	var resp_n := 0
	for s in flock.debug_snapshot():
		if float(s["resp_timer"]) > 0.0 or float(s.get("resp_delay", 0.0)) > 0.0:
			resp_n += 1
	_check(resp_n >= 1, "响应鸟进入响应计时/错峰延迟（%d）" % resp_n)
	var r2: Dictionary = flock.on_boat_shore_pass(7, Vector3(40.0, 1.0, 12.0), 14.0)
	var st2: Dictionary = flock.get_state_counts()
	_check(not bool(r2["ok"]) and String(r2["reason"]) == "trip_done", "同一航次不重复触发（reason=%s）" % String(r2["reason"]))
	_check(int(st2["boat_pass_attempts"]) == attempts0 + 2, "每次尝试都进入事件记录（attempts=%d）" % int(st2["boat_pass_attempts"]))
	var all_trip_done := true
	for k in range(5):
		flock.update_birds(DT, 14.0, ctx)
		var rr: Dictionary = flock.on_boat_shore_pass(7, Vector3(40.0 + float(k) * 3.0, 1.0, 12.0), 14.0)
		if String(rr["reason"]) != "trip_done":
			all_trip_done = false
	_check(all_trip_done, "船在检测范围内连续移动时不重复触发")
	var max_w := 0.0
	var bad_state := 0
	for i in range(2400):
		flock.update_birds(DT, 14.0, ctx)
		if i % 10 == 0:
			for s in flock.debug_snapshot():
				max_w = maxf(max_w, float(s["resp_w"]))
				if int(s["state"]) < ST_FLY or int(s["state"]) > ST_PERCH:
					bad_state += 1
	var st3: Dictionary = flock.get_state_counts()
	var eco3: Dictionary = flock.debug_eco_state()
	var leftover := 0
	for s in flock.debug_snapshot():
		if float(s["resp_timer"]) > 0.0 or float(s["resp_w"]) > 0.001 or float(s.get("resp_delay", 0.0)) > 0.0:
			leftover += 1
	print("[ECO7] B1 max_w=%.2f leftover=%d conflicts=%d airborne=%d" % [max_w, leftover, int(st3["perch_conflicts"]), int(st3["airborne"])])
	_check(max_w > 0.2, "响应偏置实际生效（max resp_w=%.2f）" % max_w)
	_check(leftover == 0, "响应结束后偏置状态完全清零（残留 %d）" % leftover)
	_check(bad_state == 0, "响应期间状态值合法")
	_check(int(st3["perch_conflicts"]) == 0, "响应后落点无占用冲突")
	_check(_all_finite(flock), "响应后坐标有限")
	var r3: Dictionary = flock.on_boat_shore_pass(8, Vector3(40.0, 1.0, 12.0), 14.0)
	_check(bool(r3["ok"]), "新航次可再次触发联动（trip=8 reason=%s）" % String(r3["reason"]))
	_check(int(eco3["boat_trip_handled"]) == 7, "旧航次记录保持到新航次触发前")
	flock.free()

# ---------------- B2 跳过守卫 ----------------
func _probe_boat_guards_b2() -> void:
	print("[ECO7] --- B2 boat guards ---")
	var f1 = _spawn(_perches(10, 3))
	_run(f1, 300, 12.0, _ctx(1001, true))
	var r1: Dictionary = f1.on_boat_shore_pass(3, Vector3(40.0, 1.0, 12.0), 5.0)
	_check(not bool(r1["ok"]) and String(r1["reason"]) == "low_sun", "太阳过低时安静跳过（%s）" % String(r1["reason"]))
	f1.free()
	var f2 = _spawn(_perches(10, 3))
	_run(f2, 240, 12.0, _ctx(1002, true))
	f2.update_birds(DT, 4.0, _ctx(1002, false))
	var st2: Dictionary = f2.get_state_counts()
	var r2: Dictionary = f2.on_boat_shore_pass(4, Vector3(40.0, 1.0, 12.0), 14.0)
	_check(int(st2["roost_state"]) == ROOST_ACTIVE, "B2 归栖已启动")
	_check(not bool(r2["ok"]) and String(r2["reason"]) == "dusk_roost", "黄昏归栖期间不触发船鸟联动（%s）" % String(r2["reason"]))
	f2.free()
	var f3 = _spawn(_perches(10, 3))
	_run(f3, 400, -4.0, _ctx(1003, false))
	var r3: Dictionary = f3.on_boat_shore_pass(9, Vector3(40.0, 1.0, 12.0), -4.0)
	_check(not bool(r3["ok"]) and String(r3["reason"]) == "night", "夜间不触发船鸟联动（%s）" % String(r3["reason"]))
	f3.free()
	var f4 = _spawn([])
	_run(f4, 2, 14.0, _ctx(1004, true))
	var r4: Dictionary = f4.on_boat_shore_pass(5, Vector3(40.0, 1.0, 12.0), 14.0)
	_check(not bool(r4["ok"]) and String(r4["reason"]) == "no_candidate", "无合格候选海鸥时安静跳过（%s）" % String(r4["reason"]))
	f4.free()

# ---------------- B3 不打断关键状态转换 ----------------
func _probe_boat_no_interrupt_b3() -> void:
	print("[ECO7] --- B3 no interrupt ---")
	var flock = _spawn(_perches(10, 3))
	var ctx := _ctx(1100, true)
	_run(flock, 300, 14.0, ctx)
	var birds: Array = flock.get("_birds")
	var landing_idx := -1
	var takeoff_idx := -1
	for i in range(birds.size()):
		var b: Dictionary = birds[i]
		if landing_idx < 0 and int(b["state"]) == ST_FLY and not bool(b.get("waiting", false)):
			if bool(flock.call("_begin_landing", b)):
				landing_idx = i
		if takeoff_idx < 0 and int(b["state"]) == ST_PERCH:
			flock.call("_begin_takeoff", b)
			takeoff_idx = i
		if landing_idx >= 0 and takeoff_idx >= 0:
			break
	var snap0: Array = flock.debug_snapshot()
	var land_state0 := -1
	var take_state0 := -1
	if landing_idx >= 0:
		land_state0 = int(snap0[landing_idx]["state"])
	if takeoff_idx >= 0:
		take_state0 = int(snap0[takeoff_idx]["state"])
	var r: Dictionary = flock.on_boat_shore_pass(6, Vector3(40.0, 1.0, 12.0), 14.0)
	flock.update_birds(DT, 14.0, ctx)
	var snap1: Array = flock.debug_snapshot()
	print("[ECO7] B3 landing_idx=%d takeoff_idx=%d ok=%s birds=%d" % [landing_idx, takeoff_idx, str(bool(r["ok"])), int(r["birds"])])
	if landing_idx >= 0:
		_check(int(snap1[landing_idx]["state"]) == land_state0, "正在降落的海鸥不被船鸟联动打断")
		_check(float(snap1[landing_idx]["resp_timer"]) == 0.0, "正在降落的海鸥不被选为响应鸟")
	if takeoff_idx >= 0:
		_check(int(snap1[takeoff_idx]["state"]) == take_state0, "正在起飞的海鸥不被船鸟联动打断")
		_check(float(snap1[takeoff_idx]["resp_timer"]) == 0.0, "正在起飞的海鸥不被选为响应鸟")
	flock.free()

# ---------------- main 集成：船只真实生命周期触发一次 ----------------
func _probe_main_integration() -> void:
	print("[ECO7] --- main integration ---")
	var m = MainScene.instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	_check(m._birds != null, "main 已创建海鸥状态机")
	var routes: Array = m._sail_routes
	_check(routes.size() >= 9, "main 已载入全部航线（%d）" % routes.size())
	if m._birds == null or routes.size() < 9:
		print("[ECO7] main integration aborted")
		return
	var coastal: Dictionary = {}
	var far: Dictionary = {}
	var far_name := ""
	for r_v in routes:
		var r: Dictionary = r_v
		if String(r.get("kind", "")) == "coastal" and coastal.is_empty():
			coastal = r
		elif String(r.get("kind", "")) == "far" and far.is_empty():
			far = r
			far_name = String(r.get("name", ""))
	_check(not coastal.is_empty(), "找到真实近海航线")
	_check(not far.is_empty(), "找到远海航线（%s）" % far_name)
	if coastal.is_empty() or far.is_empty():
		return
	m._paused = false
	m._time_source = "sim"
	m._day_length = 480.0
	m._sim_seconds = 10.0 * 3600.0
	m._sim_delta = 0.0
	m._frame_t = 0.0
	m._sun_alt = 12.0
	m._sail_boat_visible = true
	m._boat_state = "DOCKED"
	m._sail_dwell = 0.0
	m._boat_rest_until = 0.0
	m._sail_routes = [coastal]
	var ctx := _ctx(2000, true)
	var trip0 := int(m._boat_trip)
	var attempts0 := int(m._birds.debug_eco_state()["boat_pass_attempts"])
	var departed := false
	var done_at_depart := true
	var crossed := false
	var crossing_frame := -1
	var crossing_state := ""
	var frames := 0
	while frames < 12000 and not crossed:
		m._birds.update_birds(DT, 12.0, ctx)
		m._update_boat(DT)
		frames += 1
		if not departed and String(m._boat_state) == "DEPARTING":
			departed = true
			done_at_depart = bool(m._boat_shore_done)
			print("[ECO7] main depart trip=%d trigger=%.1f done=%s" % [int(m._boat_trip), float(m._boat_shore_trigger), str(bool(m._boat_shore_done))])
		if String(m._boat_state) == "COASTAL_CRUISE" and bool(m._boat_shore_done) and not crossed:
			crossed = true
			crossing_frame = frames
			crossing_state = String(m._boat_state)
	_check(departed, "船只按既有生命周期离港")
	_check(int(m._boat_trip) == trip0 + 1, "航次号递增（%d -> %d）" % [trip0, int(m._boat_trip)])
	_check(not done_at_depart, "近海航段触发窗口在进入航段前处于待触发状态")
	_check(float(m._boat_shore_trigger) > 0.0, "近海航线计算出真实触发弧长（%.1f）" % float(m._boat_shore_trigger))
	_check(crossed, "船只在 COASTAL_CRUISE 中越过近海触发点")
	_check(crossing_state == "COASTAL_CRUISE", "触发发生在近海巡航状态")
	var attempts1 := int(m._birds.debug_eco_state()["boat_pass_attempts"])
	var handled1 := int(m._birds.debug_eco_state()["boat_trip_handled"])
	var r_cross := {"birds": int(m._birds.debug_eco_state()["boat_pass_birds"])}
	print("[ECO7] main cross frame=%d trip=%d attempts=%d->%d handled=%d birds=%d" % [crossing_frame, int(m._boat_trip), attempts0, attempts1, handled1, int(r_cross["birds"])])
	_check(attempts1 == attempts0 + 1, "整段近海航程只调用一次联动（attempts %d -> %d）" % [attempts0, attempts1])
	_check(handled1 == int(m._boat_trip), "已处理航次号与当前航次一致（%d）" % handled1)
	_check(int(r_cross["birds"]) >= 1 and int(r_cross["birds"]) <= 2, "实际选中 1-2 只海鸥（%d）" % int(r_cross["birds"]))
	for i in range(1200):
		m._birds.update_birds(DT, 12.0, ctx)
		m._update_boat(DT)
	var attempts2 := int(m._birds.debug_eco_state()["boat_pass_attempts"])
	_check(attempts2 == attempts1, "继续巡航/返航不重复触发（attempts=%d）" % attempts2)
	# 远海航线：无近海触发窗口
	m._sail_routes = [far]
	m._boat_state = "DOCKED"
	m._sail_dwell = 0.0
	m._boat_rest_until = 0.0
	var far_departed := false
	for i in range(600):
		m._birds.update_birds(DT, 12.0, ctx)
		m._update_boat(DT)
		if String(m._boat_state) == "DEPARTING" or String(m._boat_state) == "OUTBOUND_FAR":
			far_departed = true
			break
	_check(far_departed, "切换到远海航线后正常离港")
	_check(bool(m._boat_shore_done), "远海航线不启用近海触发窗口（done=true）")
	_check(float(m._boat_shore_trigger) <= 0.0, "远海航线触发弧长为 -1（%.1f）" % float(m._boat_shore_trigger))
	var attempts_far := int(m._birds.debug_eco_state()["boat_pass_attempts"])
	for i in range(600):
		m._birds.update_birds(DT, 12.0, ctx)
		m._update_boat(DT)
	_check(int(m._birds.debug_eco_state()["boat_pass_attempts"]) == attempts_far, "远海航行不触发船鸟联动")
	# 再次近海新航次：触发资格恢复
	m._sail_routes = [coastal]
	m._boat_state = "DOCKED"
	m._sail_dwell = 0.0
	m._boat_rest_until = 0.0
	var new_trip := int(m._boat_trip)
	var crossed2 := false
	for i in range(12000):
		m._birds.update_birds(DT, 12.0, ctx)
		m._update_boat(DT)
		if String(m._boat_state) == "COASTAL_CRUISE" and bool(m._boat_shore_done):
			crossed2 = true
			break
	var attempts3 := int(m._birds.debug_eco_state()["boat_pass_attempts"])
	var handled3 := int(m._birds.debug_eco_state()["boat_trip_handled"])
	_check(crossed2, "新近海航次可再次越过触发点")
	_check(int(m._boat_trip) == new_trip + 1, "新航次号递增")
	_check(handled3 == int(m._boat_trip), "新航次触发资格按生命周期更新（handled=%d trip=%d）" % [handled3, int(m._boat_trip)])
	_check(attempts3 == attempts2 + 1, "新航次只新增一次联动尝试（attempts %d -> %d）" % [attempts2, attempts3])
	print("[ECO7] main integration done frames=%d" % frames)
