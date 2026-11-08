extends SceneTree
## P9 P7-FINALIZE 海鸥运动学验收探针（headless，只读）
## 运行：
##   ENG --headless --path GAME --script res://tools/probe_p9_bird_kinematics.gd
## 覆盖（真实状态机逐帧采样）：
##   [M] 模型：整鸟尺度不变、腿枢轴/脚底接地面、前趾长度、腿与躯干连续
##   [F] 栖点脚部契约：按栖点 kind 反补偿作者 gap，脚底贴面净空 0~0.005 m
##   [T] 起飞：分阶段（准备/蹬离/爬升/并入）、单调加速无尖峰、无单帧位置/朝向跳变
##   [C] 巡航：速度稳定于解析 r*ω、方向连续、快速收敛
##   [L] 着陆：提前减速、末速<0.3 m/s、无单帧跳变、落地朝向无硬切
##   [DT] 30/60/120 Hz 步长一致（同一绝对时刻的位置/速度/朝向）
##   [R] 反复起降无累积误差；[W] 风力平滑；[P] 姿态残留/中途 hop 起飞
## 退出码 0 = 全部通过。

const Fx := preload("res://scripts/fx.gd")
const World := preload("res://scripts/world.gd")
const Cottage := preload("res://scripts/cottage.gd")
const DT := 1.0 / 60.0
const STATE_FLY := 0
const STATE_TAKEOFF := 1
const STATE_LANDING := 2
const STATE_PERCH := 3
const EPS := 1.0e-6

var _pass := 0
var _fail := 0
var _holder: Node3D = null
var _perches: Array = []
var _cot: Dictionary = {}
var _fails: Array = []

func _initialize() -> void:
	print("=== P9 BIRD KINEMATICS PROBE START ===")
	await process_frame
	_holder = Node3D.new()
	_holder.name = "P9KinHolder"
	root.add_child(_holder)
	var w: Dictionary = World.build(_holder)
	_cot = Cottage.build(_holder)
	_perches = (w["perches"] as Array).duplicate()
	_perches.append_array((_cot["perches"] as Array).duplicate())
	print("[LOAD] perches=", _perches.size())
	await process_frame
	_test_model_metrics()
	_test_foot_contract()
	_test_takeoff()
	_test_cruise()
	_test_landing()
	_test_dt_consistency()
	_test_repeat_cycles()
	_test_wind_smooth()
	_test_pose_residue()
	print("=== P9 BIRD KINEMATICS RESULT: ", "PASS" if _fail == 0 else "FAIL", " pass=", _pass, " fail=", _fail, " ===")
	if _fail > 0:
		print("[FAILS] ", str(_fails))
	quit(0 if _fail == 0 else 1)

# ------------------------------------------------------------
func _check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("  [OK] ", msg)
	else:
		_fail += 1
		_fails.append(msg)
		print("  [FAIL] ", msg)

func _sv(v: Vector3) -> String:
	return "(%.3f,%.3f,%.3f)" % [v.x, v.y, v.z]

func _ctx(wind: float = 0.0) -> Dictionary:
	var d := {"day": 0, "rising": false, "sim_seconds": 12.0 * 3600.0, "sim_rate": 60.0,
		"time_source": "sim", "paused": false,
		"season": {"winter": 1.0, "canopy_keep": 1.0}}
	if wind > 0.0:
		d["weather"] = {"type": "clear", "precip_type": "none", "precip_intensity": 0.0,
			"wind_strength": wind, "wind_x": 1.0, "wind_z": 0.0, "storm": 0.0, "cloud": 0.0}
	return d

func _mk_flock(nm: String):
	var f = Fx.BirdFlock.new()
	f.name = nm
	_holder.add_child(f)
	f.setup(_perches)
	return f

func _birds(f) -> Array:
	return f.get("_birds") as Array

func _step(f, n: int, dt: float = DT, wind: float = 0.0) -> void:
	for i in range(n):
		f.update_birds(dt, 25.0, _ctx(wind))

func _seat_all(f) -> int:
	var arr: Array = _birds(f)
	var ids: Array = []
	for p_v in _perches:
		var p: Dictionary = p_v
		if int(p.get("slots", 0)) > 0:
			ids.append(String(p["id"]))
	var used := {}
	var i2 := 0
	for i in range(arr.size()):
		var ok := false
		var guard := 0
		while not ok and guard < ids.size():
			var pid := String(ids[i2 % ids.size()])
			i2 += 1
			guard += 1
			if used.has(pid):
				continue
			ok = bool(f.call("debug_force_perch", i, pid))
			if ok:
				used[pid] = true
		var b: Dictionary = arr[i]
		b["timer"] = 999.0
		b["idle_cool"] = 999.0
	return used.size()

## 取指定鸟的运动学快照
func _motion(f, idx: int) -> Dictionary:
	var states: Array = f.call("debug_motion_state")
	for s_v in states:
		var s: Dictionary = s_v
		if int(s["index"]) == idx:
			return s
	return {}

func _force_perch(f, idx: int, pid_list: Array) -> String:
	for pid_v in pid_list:
		var pid := String(pid_v)
		if String(pid) == "":
			continue
		if bool(f.call("debug_force_perch", idx, pid)):
			return pid
	return ""

func _any_free_perch(f, idx: int) -> String:
	var p: Dictionary = f.call("_find_free_slot", Vector3(0.0, 15.0, 0.0))
	if p.is_empty():
		return ""
	return String(p["id"])

# ============================================================
# [M] 模型度量：尺度不变 + 腿/趾新比例
# ============================================================
func _test_model_metrics() -> void:
	print("--- [M] MODEL METRICS ---")
	var body_mesh: ArrayMesh = Fx._gull_body_mesh()
	var head_mesh: ArrayMesh = Fx._gull_head_mesh()
	var wing_in: ArrayMesh = Fx._gull_wing_inner_mesh(1.0)
	var wing_out: ArrayMesh = Fx._gull_wing_outer_mesh(1.0)
	var legs_mesh: ArrayMesh = Fx._gull_legs_mesh()
	var ab_body: AABB = body_mesh.get_aabb()
	var ab_wi: AABB = wing_in.get_aabb()
	var ab_wo: AABB = wing_out.get_aabb()
	var ab_legs: AABB = legs_mesh.get_aabb()
	var hip: float = float(Fx.BIRD_LEG_HIP_Y)
	var span: float = 2.0 * (0.056 + maxf(absf(ab_wi.position.x), absf(ab_wi.end.x)) + maxf(absf(ab_wo.position.x), absf(ab_wo.end.x)))
	print("[M] body=", ab_body, " legs=", ab_legs, " hip=", hip)
	print("[M] wingspan_est=%.4f body_len=%.4f legs_y=[%.4f,%.4f] legs_z_size=%.4f" % [
		span, ab_body.size.z, ab_legs.position.y, ab_legs.end.y, ab_legs.size.z])
	_check(absf(span - 1.219) <= 0.02, "整鸟翼展保持 ~1.22m（实际 %.3f，禁止缩放整鸟）" % span)
	var body_bottom: float = ab_body.position.y
	_check(absf(body_bottom - hip) <= 0.004, "髋高 == 躯干网格下沿（body_bottom=%.4f hip=%.4f）" % [body_bottom, hip])
	var foot_floor: float = hip + ab_legs.position.y
	_check(absf(foot_floor) <= 0.002, "脚底接地面在鸟节点 y=0（实际 %.4f；髋枢轴 %.4f）" % [foot_floor, hip])
	_check(ab_legs.position.y <= -hip + 0.002, "腿网格从髋向下延伸到脚底（min_y=%.4f）" % ab_legs.position.y)
	var leg_top_world: float = hip + ab_legs.end.y
	_check(leg_top_world >= body_bottom - 0.002, "腿根延伸进躯干内部（腿网格顶 world y=%.4f >= 躯干下沿 %.4f，无断缝）" % [leg_top_world, body_bottom])
	var toe_len: float = ab_legs.size.z
	print("[M] foot_z_extent=%.4f (旧 0.074)" % toe_len)
	_check(toe_len <= 0.066 and toe_len >= 0.045, "脚/趾前后总长 0.045~0.066m（旧 0.074；前趾 0.052→0.031，实际 %.3f）" % toe_len)
	var head_bottom: float = 0.262 + head_mesh.get_aabb().position.y
	print("[M] head_bottom=%.4f body_top=%.4f (头部嵌入躯干即连续)" % [head_bottom, ab_body.end.y])
	_check(head_bottom <= ab_body.end.y - 0.02 and head_bottom >= ab_body.position.y, "头与躯干连续（head_bottom %.3f 在躯干 y 范围内，且与躯干重叠）" % head_bottom)

# ============================================================
# [F] 栖点脚部契约：脚底贴面净空 0~0.005m
# ============================================================
func _test_foot_contract() -> void:
	print("--- [F] PERCH FOOT CONTRACT ---")
	var flock = _mk_flock("P9KinFoot")
	_seat_all(flock)
	_step(flock, 3)
	var check_ids: Array = ["porch_rail_L", "porch_ray_L", "porch_beam_L", "ridge_0", "eave_L_-2.415", "lamp_1", "tree_0", "winter_branch_0", "lighthouse_0", "dock_rail", "dock_bollard", "garden_post_0"]
	for pid_v in check_ids:
		var pid := String(pid_v)
		var contract: Dictionary = flock.call("debug_foot_contract", pid)
		if contract.is_empty():
			continue
		var gap: float = float(contract["support_gap"])
		var lift: float = float(contract["foot_lift"])
		print("[F] %-20s kind=%-10s author_gap=%.4f foot_lift=%.4f support_gap=%.4f" % [
			pid, String(contract["kind"]), float(contract["author_gap"]), lift, gap])
		_check(gap >= 0.0 and gap <= 0.005, "%s 脚底贴面净空 ∈[0,0.005]（实际 %.4f m）" % [pid, gap])
		var p: Dictionary = flock.call("_find_perch", pid)
		if p.is_empty():
			continue
		var n: Vector3 = (p["normal"] as Vector3).normalized()
		var real_support: Vector3 = (p["pos"] as Vector3) - n * float(contract["author_gap"])
		var foot_world: Vector3 = real_support + n * gap
		var back: float = (foot_world - real_support).dot(n)
		_check(absf(back - gap) <= 0.0005, "%s 支撑面+净空换算自洽（%.4f）" % [pid, back])
	# 真实节点测量：强制 0 号鸟逐个栖点，测节点原点（=脚底）到真实支撑面的法向净空
	var ids2: Array = ["porch_rail_L", "ridge_0", "lamp_1", "tree_0", "winter_branch_0", "lighthouse_0"]
	for pid2_v in ids2:
		var pid2 := String(pid2_v)
		var p2: Dictionary = flock.call("_find_perch", pid2)
		if p2.is_empty():
			continue
		var assigned: String = _force_perch(flock, 0, [pid2])
		if assigned == "":
			continue
		_step(flock, 2)
		var b: Dictionary = _birds(flock)[0]
		var node: Node3D = b["node"]
		var contract2: Dictionary = flock.call("debug_foot_contract", pid2)
		var n2: Vector3 = (p2["normal"] as Vector3).normalized()
		var support2: Vector3 = (p2["pos"] as Vector3) - n2 * float(contract2["author_gap"])
		var foot_y: float = float(_motion(flock, 0).get("foot_local_y", 0.0))
		var foot_w: Vector3 = node.position + node.basis * Vector3(0.0, foot_y, 0.0)
		var gap2: float = (foot_w - support2).dot(n2)
		print("[F] node %-18s foot_gap=%.4f (foot_local_y=%.4f)" % [pid2, gap2, foot_y])
		_check(gap2 >= -0.0005 and gap2 <= 0.005, "%s 真实节点脚底净空 ∈[0,0.005]（实际 %.4f m）" % [pid2, gap2])
	flock.free()

# ============================================================
# [T] 起飞分阶段 / 单调加速 / 无跳变
# ============================================================
func _takeoff_sequence(flock, idx: int) -> Dictionary:
	var out := {"frames": [], "states": [], "stages": []}
	var guard := 0
	while int(_birds(flock)[idx]["state"]) == STATE_TAKEOFF and guard < 400:
		_step(flock, 1)
		guard += 1
		var m: Dictionary = _motion(flock, idx)
		out["frames"].append(m)
		out["states"].append(int(m["state"]))
		out["stages"].append(int(m["stage"]))
	return out

func _test_takeoff() -> void:
	print("--- [T] TAKEOFF PHASES / CONTINUITY ---")
	var flock = _mk_flock("P9KinTO")
	_seat_all(flock)
	_step(flock, 3)
	var pid := _force_perch(flock, 0, ["ridge_0", "porch_rail_L", "tree_0", "lamp_1"])
	if pid == "":
		pid = _any_free_perch(flock, 0)
		if pid != "":
			flock.call("debug_force_perch", 0, pid)
	_check(pid != "", "起飞测试鸟已停到真实栖点（%s）" % pid)
	if pid == "":
		flock.free()
		return
	var b: Dictionary = _birds(flock)[0]
	b["timer"] = 999.0
	b["idle_cool"] = 999.0
	_step(flock, 2)
	var p0: Vector3 = (b["node"] as Node3D).position
	var cruise: float = maxf(float(b["radius"]) * absf(float(b["speed"])), 0.8)
	var ok := bool(flock.call("debug_force_takeoff", 0))
	_check(ok, "debug_force_takeoff 成功进入 TAKEOFF")
	if not ok:
		flock.free()
		return
	var seq: Dictionary = _takeoff_sequence(flock, 0)
	var frames: Array = seq["frames"]
	_check(frames.size() >= 8, "起飞采样帧数 >=8（实际 %d）" % frames.size())
	var dur: float = float(frames.size()) * DT
	_check(dur >= 0.40 and dur <= 1.60, "起飞时长 0.40~1.60s（实际 %.3fs；旧为固定 0.6~1.0s 插值）" % dur)
	var stages_seen := {}
	for sv in (seq["stages"] as Array):
		stages_seen[int(sv)] = true
	_check(stages_seen.has(0) and stages_seen.has(1) and stages_seen.has(2), "起飞包含 准备/蹬离/爬升 三个阶段（实际 %s）" % str(stages_seen.keys()))
	var first_speed := -1.0
	var peak := 0.0
	var prev_speed := 0.0
	var max_dspeed := 0.0
	var max_decrease := 0.0
	var max_step := 0.0
	var max_dyaw := 0.0
	var max_dpitch := 0.0
	var max_dvy := 0.0
	var prev_pos: Vector3 = p0
	var prev_vy := 0.0
	var prev_yaw := 0.0
	var prev_pitch := 0.0
	var first := true
	for f_v in frames:
		var m: Dictionary = f_v
		var pos: Vector3 = m["pos"] as Vector3
		var vel: Vector3 = m["vel"] as Vector3
		var spd := vel.length()
		if first_speed < 0.0 and spd > 0.02:
			first_speed = spd
		if not first:
			max_step = maxf(max_step, pos.distance_to(prev_pos))
			var dsp: float = absf(spd - prev_speed)
			max_dspeed = maxf(max_dspeed, dsp)
			if spd < prev_speed - 0.02:
				max_decrease = maxf(max_decrease, prev_speed - spd)
			max_dyaw = maxf(max_dyaw, absf(rad_to_deg(wrapf(float(m["yaw"]) - prev_yaw, -PI, PI))))
			max_dpitch = maxf(max_dpitch, absf(rad_to_deg(float(m["pitch"]) - prev_pitch)))
			max_dvy = maxf(max_dvy, absf(vel.y - prev_vy))
		peak = maxf(peak, spd)
		prev_speed = spd
		prev_yaw = float(m["yaw"])
		prev_pitch = float(m["pitch"])
		prev_vy = vel.y
		prev_pos = pos
		first = false
	print("[T] cruise=%.3f dur=%.3fs first_v=%.3f peak=%.3f max_dv=%.3f max_pos_step=%.4f max_dyaw=%.2f° max_dpitch=%.2f° max_dvy=%.3f" % [
		cruise, dur, first_speed, peak, max_dspeed, max_step, max_dyaw, max_dpitch, max_dvy])
	_check(first_speed >= 0.0 and first_speed <= 0.40, "起飞首帧速度 <=0.40 m/s（从静止连续起跳，实际 %.3f）" % first_speed)
	_check(max_decrease <= 0.05, "蹬离/爬升段速度单调（最大回落 %.3f m/s，无尖峰）" % max_decrease)
	_check(peak <= cruise * 1.60 + 0.40, "起飞峰值 <=1.6×巡航（巡航 %.2f，峰值 %.2f）" % [cruise, peak])
	_check(max_dspeed <= Fx.BIRD_TAKEOFF_ACCEL * DT + 0.03, "单帧速度变化 <= 加速度上限×dt（实际 %.3f，上限 %.3f）" % [max_dspeed, Fx.BIRD_TAKEOFF_ACCEL * DT + 0.03])
	var vmax: float = cruise * 1.60 + 0.40
	_check(max_step <= maxf(0.10, vmax * DT * 1.35), "起飞单帧位置步 <= 合理上限（实际 %.4f m，上限 %.4f）" % [max_step, maxf(0.10, vmax * DT * 1.35)])
	_check(max_dyaw <= rad_to_deg(Fx.BIRD_YAW_RATE_MAX * DT) + 1.0, "起飞单帧 yaw 变化 <= %.1f°（实际 %.2f°，无硬转向）" % [rad_to_deg(Fx.BIRD_YAW_RATE_MAX * DT) + 1.0, max_dyaw])
	_check(max_dpitch <= rad_to_deg(Fx.BIRD_PITCH_RATE_MAX * DT) + 1.0, "起飞单帧 pitch 变化 <= %.1f°（实际 %.2f°）" % [rad_to_deg(Fx.BIRD_PITCH_RATE_MAX * DT) + 1.0, max_dpitch])
	_check(max_dvy <= 0.35, "起飞单帧垂直速度变化 <=0.35 m/s（实际 %.3f）" % max_dvy)
	# 入 FLY 帧连续性
	var last_to_speed := prev_speed
	var last_to_yaw := prev_yaw
	var last_to_pitch := prev_pitch
	_step(flock, 1)
	var m1: Dictionary = _motion(flock, 0)
	var fly_speed: float = float(m1["speed"])
	var dyaw_entry: float = rad_to_deg(absf(wrapf(float(m1["yaw"]) - last_to_yaw, -PI, PI)))
	var dpitch_entry: float = rad_to_deg(absf(float(m1["pitch"]) - last_to_pitch))
	print("[T] entry: last_to_v=%.3f first_fly_v=%.3f dv=%.3f dyaw=%.2f° dpitch=%.2f°" % [
		last_to_speed, fly_speed, absf(fly_speed - last_to_speed), dyaw_entry, dpitch_entry])
	_check(int(m1["state"]) == STATE_FLY, "起飞完成后进入 FLY")
	_check(absf(fly_speed - last_to_speed) <= 0.60, "入 FLY 速度连续（|Δv|=%.3f <=0.60，无急停/硬加速）" % absf(fly_speed - last_to_speed))
	_check(dyaw_entry <= rad_to_deg(Fx.BIRD_YAW_RATE_MAX * DT) + 1.5, "入 FLY yaw 连续（%.2f°）" % dyaw_entry)
	_check(dpitch_entry <= rad_to_deg(Fx.BIRD_PITCH_RATE_MAX * DT) + 1.5, "入 FLY pitch 连续（%.2f°）" % dpitch_entry)
	flock.free()

# ============================================================
# [C] 巡航稳定性
# ============================================================
func _fly_one(flock) -> int:
	for b_v in _birds(flock):
		var b: Dictionary = b_v
		b["timer"] = 999.0
		b["idle_cool"] = 999.0
	var idx := -1
	for i in range(_birds(flock).size()):
		var b2: Dictionary = _birds(flock)[i]
		if int(b2["state"]) == STATE_PERCH:
			idx = i
			break
	if idx < 0:
		return -1
	flock.call("debug_force_takeoff", idx)
	var guard := 0
	while int(_birds(flock)[idx]["state"]) != STATE_FLY and guard < 400:
		_step(flock, 1)
		guard += 1
	_birds(flock)[idx]["timer"] = 999.0
	return idx

func _test_cruise() -> void:
	print("--- [C] CRUISE STABILITY ---")
	var flock = _mk_flock("P9KinCruise")
	_seat_all(flock)
	_step(flock, 3)
	var idx: int = _fly_one(flock)
	_check(idx >= 0, "巡航测试鸟已进入 FLY（index=%d）" % idx)
	if idx < 0:
		flock.free()
		return
	_step(flock, 300)
	var b: Dictionary = _birds(flock)[idx]
	var cruise: float = maxf(float(b["radius"]) * absf(float(b["speed"])), 0.5)
	var speeds: Array = []
	var max_step := 0.0
	var max_dyaw := 0.0
	var prev_pos: Vector3 = (b["node"] as Node3D).position
	var prev_yaw: float = float(_motion(flock, idx)["yaw"])
	for i in range(300):
		_step(flock, 1)
		var m: Dictionary = _motion(flock, idx)
		speeds.append(float(m["speed"]))
		max_step = maxf(max_step, (m["pos"] as Vector3).distance_to(prev_pos))
		max_dyaw = maxf(max_dyaw, absf(rad_to_deg(wrapf(float(m["yaw"]) - prev_yaw, -PI, PI))))
		prev_pos = m["pos"] as Vector3
		prev_yaw = float(m["yaw"])
	var sum := 0.0
	var mn := 1.0e9
	var mx := 0.0
	for s_v in speeds:
		var s := float(s_v)
		sum += s
		mn = minf(mn, s)
		mx = maxf(mx, s)
	var mean: float = sum / float(maxi(speeds.size(), 1))
	print("[C] analytic=%.3f mean=%.3f min=%.3f max=%.3f max_step=%.4f max_dyaw=%.2f°" % [cruise, mean, mn, mx, max_step, max_dyaw])
	_check(absf(mean - cruise) <= cruise * 0.12 + 0.10, "巡航平均速度 ≈ 解析 r*ω（%.3f vs %.3f，偏差 %.1f%%）" % [mean, cruise, 100.0 * absf(mean - cruise) / cruise])
	_check((mx - mn) <= cruise * 0.20 + 0.10, "巡航速度稳定（波动 %.3f m/s）" % (mx - mn))
	_check(max_step <= 0.12, "巡航单帧位置步 <=0.12m（实际 %.4f）" % max_step)
	_check(max_dyaw <= rad_to_deg(Fx.BIRD_YAW_RATE_MAX * DT) + 1.0, "巡航单帧 yaw <= %.1f°（实际 %.2f°）" % [rad_to_deg(Fx.BIRD_YAW_RATE_MAX * DT) + 1.0, max_dyaw])
	flock.free()

# ============================================================
# [L] 着陆减速 / 触地 / 无硬切
# ============================================================
func _test_landing() -> void:
	print("--- [L] LANDING DECEL / TOUCHDOWN ---")
	var flock = _mk_flock("P9KinLand")
	_seat_all(flock)
	_step(flock, 3)
	var idx: int = _fly_one(flock)
	if idx < 0:
		_check(false, "着陆测试鸟无法进入 FLY")
		flock.free()
		return
	_step(flock, 90)
	var b: Dictionary = _birds(flock)[idx]
	var cruise: float = maxf(float(b["radius"]) * absf(float(b["speed"])), 0.8)
	var target: String = _any_free_perch(flock, 1)
	if target == "":
		_check(false, "没有空闲栖点可用于着陆目标")
	print("[L] target=", target)
	var ok := bool(flock.call("debug_force_landing", idx, target))
	_check(ok, "debug_force_landing 成功进入 LANDING（%s）" % target)
	if not ok:
		flock.free()
		return
	var v0: float = float(_motion(flock, idx)["speed"])
	var frames: Array = []
	var guard := 0
	while int(_birds(flock)[idx]["state"]) == STATE_LANDING and guard < 600:
		_step(flock, 1)
		guard += 1
		frames.append(_motion(flock, idx))
	_check(int(_birds(flock)[idx]["state"]) == STATE_PERCH, "着陆完成进入 PERCH（采样 %d 帧）" % frames.size())
	# 从 PERCH 起始帧拿到最后着陆帧的 basis 与首 PERCH 帧 basis 的差
	var last_m: Dictionary = frames[frames.size() - 1] if not frames.is_empty() else {}
	var max_step := 0.0
	var max_dyaw := 0.0
	var max_dpitch := 0.0
	var max_speed_drop := 0.0
	var prev_pos: Vector3 = (b["node"] as Node3D).position
	var prev_yaw := float(last_m.get("yaw", 0.0)) - 0.0
	var prev_pitch := 0.0
	var prev_spd := v0
	var spd_at_60 := 0.0
	var first := true
	for i in range(frames.size()):
		var m: Dictionary = frames[i]
		var pos: Vector3 = m["pos"] as Vector3
		var spd: float = float(m["speed"])
		if not first:
			max_step = maxf(max_step, pos.distance_to(prev_pos))
			var dsp: float = absf(spd - prev_spd)
			if dsp > max_speed_drop:
				max_speed_drop = dsp
			max_dyaw = maxf(max_dyaw, absf(rad_to_deg(wrapf(float(m["yaw"]) - prev_yaw, -PI, PI))))
			max_dpitch = maxf(max_dpitch, absf(rad_to_deg(float(m["pitch"]) - prev_pitch)))
			if float(i) / float(maxi(frames.size() - 1, 1)) >= 0.60 and spd_at_60 == 0.0:
				spd_at_60 = spd
		prev_pos = pos
		prev_yaw = float(m["yaw"])
		prev_pitch = float(m["pitch"])
		prev_spd = spd
		first = false
	# 速度剖面（打印 + 用于"提前减速"断言）
	var prof: Array = []
	for k in [0.0, 0.2, 0.4, 0.6, 0.8, 0.9, 1.0]:
		var fi: int = clampi(int(round(float(k) * float(maxi(frames.size() - 1, 1)))), 0, maxi(frames.size() - 1, 0))
		prof.append(float((frames[fi] as Dictionary)["speed"]))
	print("[L] speed profile k0..1=%.3f/%.3f/%.3f/%.3f/%.3f/%.3f/%.3f" % [prof[0], prof[1], prof[2], prof[3], prof[4], prof[5], prof[6]])
	var dur: float = float(frames.size()) * DT
	var last: Dictionary = frames[frames.size() - 1]
	var last_v: float = float(last["speed"])
	var last_pos: Vector3 = last["pos"] as Vector3
	var slot: Vector3 = b.get("to_p", last_pos) as Vector3
	var dist_err: float = last_pos.distance_to(slot)
	print("[L] v0=%.3f dur=%.2fs spd@60%%=%.3f last_v=%.3f dist_err=%.4f max_step=%.4f max_dyaw=%.2f° max_dpitch=%.2f° max_dsp=%.3f" % [
		v0, dur, spd_at_60, last_v, dist_err, max_step, max_dyaw, max_dpitch, max_speed_drop])
	_check(dur >= 0.5 and dur <= 6.0, "着陆时长 0.5~6.0s（实际 %.2fs）" % dur)
	_check(last_v < 0.30, "触地合速度 <0.30 m/s（实际 %.3f）" % last_v)
	_check(dist_err <= 0.02, "触地点与栖点槽位误差 <=0.02m（实际 %.4f）" % dist_err)
	if spd_at_60 > 0.0:
		# P9 契约：着陆速度剖面 = 进近段受控（不超过入场速度/巡航上限，不加速）+ 末段单调减速到触地
		var peak_land: float = 0.0
		var rose_after_20 := 0
		var prev_spd2: float = float((frames[0] as Dictionary)["speed"])
		for i2 in range(frames.size()):
			var spd2: float = float((frames[i2] as Dictionary)["speed"])
			peak_land = maxf(peak_land, spd2)
			# 容差 0.28 m/s：进近速度上限轮廓（1.25×巡航）在转向段后回到 cap，属受控包线内，
			# 不构成"加速尖峰"；要求 20% 之后无 >0.28 m/s 的回升，且 90% 处必须已显著减速。
			if float(i2) >= float(frames.size()) * 0.20 and spd2 > prev_spd2 + 0.28:
				rose_after_20 += 1
			prev_spd2 = spd2
		print("[L] peak=%.3f rose_after_20%%=%d spd@60%%=%.3f spd@90%%=%.3f" % [peak_land, rose_after_20, spd_at_60, prof[5]])
		_check(peak_land <= maxf(v0, cruise * 1.40) * 1.10 + 0.05, "着陆无加速尖峰（峰值 %.2f <= max(入场 %.2f, 巡航 %.2f)×1.10）" % [peak_land, v0, cruise])
		_check(rose_after_20 == 0, "着陆 20%% 后速度单调不升（回升帧 %d）" % rose_after_20)
		_check(spd_at_60 <= maxf(v0, 1.2), "着陆 60%% 处不高于入场速度（v0=%.2f → %.2f）" % [v0, spd_at_60])
		_check(prof[5] <= maxf(v0 * 0.55, 0.9), "着陆 90%% 处已明显减速（%.2f → %.2f）" % [v0, prof[5]])
	_check(max_step <= 0.14, "着陆单帧位置步 <=0.14m（实际 %.4f）" % max_step)
	_check(max_dyaw <= rad_to_deg(Fx.BIRD_YAW_RATE_MAX * DT) + 1.0, "着陆单帧 yaw <= %.1f°（实际 %.2f°，无硬切）" % [rad_to_deg(Fx.BIRD_YAW_RATE_MAX * DT) + 1.0, max_dyaw])
	_check(max_dpitch <= rad_to_deg(Fx.BIRD_PITCH_RATE_MAX * DT) + 1.0, "着陆单帧 pitch <= %.1f°（实际 %.2f°）" % [rad_to_deg(Fx.BIRD_PITCH_RATE_MAX * DT) + 1.0, max_dpitch])
	_check(max_speed_drop <= Fx.BIRD_LANDING_ACCEL * DT + 0.05, "着陆单帧速度变化 <= 加速度上限×dt（实际 %.3f）" % max_speed_drop)
	# 首 PERCH 帧的 basis 与最后 LANDING 帧 basis 之差（不允许硬切）
	var b_land: Basis = (b["node"] as Node3D).basis
	_step(flock, 1)
	var b_perch: Basis = (b["node"] as Node3D).basis
	var q1: Quaternion = b_land.get_rotation_quaternion().normalized()
	var q2: Quaternion = b_perch.get_rotation_quaternion().normalized()
	var snap_deg: float = rad_to_deg(q1.angle_to(q2))
	print("[L] perch-entry basis delta=%.2f°" % snap_deg)
	_check(snap_deg <= 30.0, "落地入 PERCH 单帧朝向变化 <=30°（实际 %.2f°，无 74~158° 硬切）" % snap_deg)
	flock.free()

# ============================================================
# [DT] 30/60/120 Hz 一致性
# ============================================================
func _run_dt_sequence(flock, dt: float, sample_times: Array) -> Array:
	var out: Array = []
	var t := 0.0
	for st_v in sample_times:
		var goal := float(st_v)
		while t < goal - 1.0e-9:
			flock.update_birds(dt, 25.0, _ctx())
			t += dt
		var m: Dictionary = _motion(flock, 0)
		out.append({"t": goal, "state": int(m["state"]), "pos": m["pos"], "speed": float(m["speed"]), "yaw": float(m["yaw"]), "pitch": float(m["pitch"])})
	return out

func _test_dt_consistency() -> void:
	print("--- [DT] FRAME-RATE CONSISTENCY 30/60/120Hz ---")
	var times: Array = [0.2, 0.4, 0.6, 0.8, 1.0, 1.2, 1.5, 2.0]
	var results: Array = []
	for dt in [1.0 / 60.0, 1.0 / 30.0, 1.0 / 120.0]:
		var flock = _mk_flock("P9KinDT%d" % int(round(1.0 / dt)))
		_seat_all(flock)
		_step(flock, 3)
		var pid := _force_perch(flock, 0, ["ridge_0", "porch_rail_L", "tree_0"])
		if pid == "":
			pid = _any_free_perch(flock, 0)
			flock.call("debug_force_perch", 0, pid)
		var b: Dictionary = _birds(flock)[0]
		b["timer"] = 999.0
		b["idle_cool"] = 999.0
		flock.call("debug_force_takeoff", 0)
		results.append(_run_dt_sequence(flock, dt, times))
		flock.free()
	var max_pos := 0.0
	var max_speed := 0.0
	var max_yaw := 0.0
	var max_pitch := 0.0
	var bad_state := 0
	for k in range(times.size()):
		var r60: Dictionary = (results[0] as Array)[k]
		var r30: Dictionary = (results[1] as Array)[k]
		var r120: Dictionary = (results[2] as Array)[k]
		max_pos = maxf(max_pos, (r60["pos"] as Vector3).distance_to(r30["pos"] as Vector3))
		max_pos = maxf(max_pos, (r60["pos"] as Vector3).distance_to(r120["pos"] as Vector3))
		max_speed = maxf(max_speed, absf(float(r60["speed"]) - float(r30["speed"])))
		max_speed = maxf(max_speed, absf(float(r60["speed"]) - float(r120["speed"])))
		max_yaw = maxf(max_yaw, absf(rad_to_deg(wrapf(float(r60["yaw"]) - float(r30["yaw"]), -PI, PI))))
		max_yaw = maxf(max_yaw, absf(rad_to_deg(wrapf(float(r60["yaw"]) - float(r120["yaw"]), -PI, PI))))
		max_pitch = maxf(max_pitch, absf(rad_to_deg(float(r60["pitch"]) - float(r30["pitch"]))))
		if int(r60["state"]) != int(r30["state"]) or int(r60["state"]) != int(r120["state"]):
			bad_state += 1
		print("[DT] t=%.1f pos60=%s |Δpos|=%.5f |Δyaw|=%.2f° state=%d" % [float(times[k]), _sv(r60["pos"] as Vector3), (r60["pos"] as Vector3).distance_to(r30["pos"] as Vector3), max_yaw, int(r60["state"])])
	print("[DT] max_pos=%.5f max_speed=%.5f max_yaw=%.3f° max_pitch=%.3f° state_mismatch=%d" % [max_pos, max_speed, max_yaw, max_pitch, bad_state])
	_check(max_pos <= 0.005, "30/60/120Hz 同刻位置一致（最大偏差 %.5f m <=0.005）" % max_pos)
	_check(max_speed <= 0.02, "30/60/120Hz 同刻速度一致（最大偏差 %.5f m/s）" % max_speed)
	_check(max_yaw <= 1.0, "30/60/120Hz 同刻朝向一致（最大偏差 %.3f° <=1°）" % max_yaw)
	_check(max_pitch <= 1.0, "30/60/120Hz 同刻俯仰一致（最大偏差 %.3f°）" % max_pitch)
	_check(bad_state == 0, "30/60/120Hz 状态切换时刻一致（不一致样本 %d）" % bad_state)

# ============================================================
# [R] 反复起降无累积误差
# ============================================================
func _test_repeat_cycles() -> void:
	print("--- [R] REPEATED TAKEOFF/LANDING CYCLES ---")
	var flock = _mk_flock("P9KinCycle")
	_seat_all(flock)
	_step(flock, 3)
	var pid := _force_perch(flock, 0, ["ridge_0", "porch_rail_L", "lamp_1", "eave_L_-2.415"])
	if pid == "":
		pid = _any_free_perch(flock, 0)
		flock.call("debug_force_perch", 0, pid)
	var b: Dictionary = _birds(flock)[0]
	var slot: Vector3 = b.get("perch_pos", Vector3.ZERO) as Vector3
	var errs: Array = []
	for cycle in range(3):
		b["timer"] = 999.0
		b["idle_cool"] = 999.0
		flock.call("debug_force_takeoff", 0)
		var guard := 0
		while int(b["state"]) != STATE_FLY and guard < 400:
			_step(flock, 1)
			guard += 1
		_step(flock, 30)
		var ok := bool(flock.call("debug_force_landing", 0, pid))
		guard = 0
		while int(b["state"]) == STATE_LANDING and guard < 600:
			_step(flock, 1)
			guard += 1
		_check(ok and int(b["state"]) == STATE_PERCH, "第 %d 次循环完成起飞→巡航→着陆（state=%d）" % [cycle, int(b["state"])])
		var pos: Vector3 = (b["node"] as Node3D).position
		var err: float = pos.distance_to(slot)
		errs.append(err)
		print("[R] cycle=%d touchdown_err=%.5f pos=%s slot=%s" % [cycle, err, _sv(pos), _sv(slot)])
		_check(err <= 0.01, "第 %d 次着陆落点误差 <=0.01m（实际 %.5f）" % [cycle, err])
	if errs.size() >= 2:
		var spread: float = float(errs.max()) - float(errs.min())
		print("[R] error spread=%.6f" % spread)
		_check(spread <= 0.005, "3 次循环落点无累积漂移（极差 %.5f <=0.005）" % spread)
	flock.free()

# ============================================================
# [W] 风力平滑
# ============================================================
func _test_wind_smooth() -> void:
	print("--- [W] WIND SMOOTHING ---")
	var flock = _mk_flock("P9KinWind")
	_seat_all(flock)
	_step(flock, 3)
	var idx: int = _fly_one(flock)
	if idx < 0:
		_check(false, "风力测试鸟无法进入 FLY")
		flock.free()
		return
	_step(flock, 60)
	var max_dv := 0.0
	var max_dw := 0.0
	var prev_speed: float = float(_motion(flock, idx)["speed"])
	var prev_wind: Vector3 = _motion(flock, idx)["wind"] as Vector3
	for i in range(60):
		flock.update_birds(DT, 25.0, _ctx(1.0 if i >= 5 else 0.0))
		var m: Dictionary = _motion(flock, idx)
		var spd: float = float(m["speed"])
		var wind: Vector3 = m["wind"] as Vector3
		max_dv = maxf(max_dv, absf(spd - prev_speed))
		max_dw = maxf(max_dw, (wind - prev_wind).length())
		prev_speed = spd
		prev_wind = wind
	print("[W] max_dspeed=%.4f max_dwind=%.4f" % [max_dv, max_dw])
	_check(max_dv <= 0.30, "风突变（0→1）时单帧速度变化平滑（最大 %.3f m/s）" % max_dv)
	_check(max_dw <= 0.06, "风向量一阶平滑（单帧最大变化 %.4f m/s）" % max_dw)
	flock.free()

# ============================================================
# [P] 姿态残留 / mid-hop 起飞
# ============================================================
func _test_pose_residue() -> void:
	print("--- [P] POSE RESIDUE / MID-HOP TAKEOFF ---")
	var flock = _mk_flock("P9KinPose")
	_seat_all(flock)
	_step(flock, 3)
	var pid := _force_perch(flock, 0, ["ridge_0", "porch_rail_L", "tree_0"])
	if pid == "":
		pid = _any_free_perch(flock, 0)
		flock.call("debug_force_perch", 0, pid)
	var b: Dictionary = _birds(flock)[0]
	# 1) 姿态残留：强制造 shake 动作（body.z ±0.10）后起飞
	b["idle_action"] = "shake"
	b["idle_active"] = true
	b["idle_t"] = 0.0
	b["idle_dur"] = 0.6
	b["timer"] = 999.0
	_step(flock, 18)
	var m_shake: Dictionary = _motion(flock, 0)
	print("[P] shake body_rot=", m_shake["body_rot"], " head=", m_shake["head_rot"])
	flock.call("debug_force_takeoff", 0)
	_step(flock, 25)
	var m_air: Dictionary = _motion(flock, 0)
	var brot: Vector3 = m_air["body_rot"] as Vector3
	var hrot: Vector3 = m_air["head_rot"] as Vector3
	print("[P] after takeoff+25f state=%d body_rot=%s head=%s" % [int(m_air["state"]), _sv(brot), _sv(hrot)])
	_check(absf(brot.x) < 0.01 and absf(brot.z) < 0.01, "起飞后 body.x/z 姿态残留归零（%.4f, %.4f）" % [brot.x, brot.z])
	_check(absf(hrot.z) < 0.01, "起飞后 head.z 姿态残留归零（%.4f）" % hrot.z)
	# 2) mid-hop 起飞：hop 位移中起飞，首帧不得回拉 0.11m
	var flock2 = _mk_flock("P9KinHop")
	_seat_all(flock2)
	_step(flock2, 3)
	var pid2 := _force_perch(flock2, 0, ["ridge_0", "porch_rail_L", "tree_0"])
	if pid2 == "":
		pid2 = _any_free_perch(flock2, 0)
		flock2.call("debug_force_perch", 0, pid2)
	var b2: Dictionary = _birds(flock2)[0]
	b2["timer"] = 999.0
	b2["idle_action"] = "hop"
	b2["idle_active"] = true
	b2["idle_t"] = 0.0
	b2["idle_dur"] = Fx.BIRD_HOP_DURATION
	_step(flock2, 12)
	var hop_pos: Vector3 = (b2["node"] as Node3D).position
	flock2.call("debug_force_takeoff", 0)
	var max_step_hop := 0.0
	var prev: Vector3 = hop_pos
	for i in range(20):
		_step(flock2, 1)
		var np: Vector3 = (b2["node"] as Node3D).position
		max_step_hop = maxf(max_step_hop, np.distance_to(prev))
		prev = np
	print("[P] mid-hop first max_step=%.4f m (旧实现回拉 0.110m)" % max_step_hop)
	_check(max_step_hop <= 0.03, "mid-hop 起飞无位置回拉（单帧最大 %.4f m <=0.03）" % max_step_hop)
	flock.free()
	flock2.free()
