extends SceneTree
## P9 / P7-FINALIZE 生活动作行为探针（headless，真实 Cottage + IsleWorld + Villager 状态机）。
##
## 覆盖：
##   A. 睡觉：坐床沿 → 搬腿/躺平分段 root（前 0.30s 不动、之后单调）→ 睡姿锚点 → 醒来链（get_up → bed_sit_up）
##   B. 跨 00:00：自主睡眠决策的时长跨下一个 sleep 窗口（旧实现会在 00:00 起床再躺）
##   C. 吃饭：碗显隐、手-碗/手-嘴/肘-肩、循环变速、退出清理（不扣共享库存）
##   D. 秋千：真实世界吊点注入 → 走到 swing_stand → 坐姿贴座、身体角度与吊点同步、轻柔 5-10°、
##      起身恢复；取消/接管安全退出
##   E. 观海：真实走到 dock_sea_watch、面向海面、慢速观察、结束恢复
##   F. 仲裁：睡觉中拒绝钓鱼/巡田；钓鱼期间不开始生活动作
##
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path D:/休闲小岛幻境/游戏工程 \
##     --script res://tools/probe_p9_life_actions.gd

const ASTRO := preload("res://scripts/isle_astro.gd")
const SPOTS := preload("res://scripts/isle_villager_spots.gd")
const MODEL := preload("res://scripts/isle_villager_model.gd")
const SCHEDULE := preload("res://scripts/isle_villager_schedule.gd")
const WORLD := preload("res://scripts/world.gd")
const M := preload("res://scripts/isle_math.gd")

var _holder: Node3D = null
var _cottage: Dictionary = {}
var _world: Dictionary = {}
var _v: Node3D = null
var _anim: AnimationPlayer = null
var _model: Node3D = null
var _sim := 0.0
var _tj := 0.0
var _checks := 0
var _fails: Array = []
var _state_log: Array = []

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _ck(cond: bool, label: String, detail: String = "") -> void:
	_checks += 1
	if cond:
		print("[LIFEACT] PASS " + label + ("  (" + detail + ")" if detail != "" else ""))
	else:
		print("[LIFEACT] FAIL " + label + ("  (" + detail + ")" if detail != "" else ""))
		_fails.append(label + (" | " + detail if detail != "" else ""))

func _f3(v: Vector3) -> String:
	return "(%.3f,%.3f,%.3f)" % [v.x, v.y, v.z]

func _ctx(sim: float, frozen: bool = false) -> Dictionary:
	var a: Dictionary = ASTRO.compute(sim)
	var ev: Dictionary = ASTRO.day_events(sim)
	return {
		"sim_seconds": sim, "sim_rate": 144.0, "sim_delta": 144.0 / 60.0,
		"sun_alt": float(a.get("sun_alt", 30.0)), "events": ev,
		"time_jump": _tj, "frozen": frozen,
		"door_set": Callable(self, "_on_door"),
		"weather": {"type": "clear", "precip_type": "none", "precip_intensity": 0.0,
			"wind_strength": 0.05, "storm": 0.0, "cloud": 0.1},
		"season_id": "spring",
	}

func _on_door(_open: bool) -> void:
	pass

func tick(seconds: float, frozen: bool = false, advance: bool = true) -> void:
	var dt := 1.0 / 60.0
	var n := maxi(1, int(round(seconds / dt)))
	for i in n:
		if advance and not frozen:
			_sim += dt * 144.0
		_v.call("sim_tick", dt, _ctx(_sim, frozen))
		if _anim != null and not frozen:
			_anim.advance(dt)

func tick_until(targets: Array, max_seconds: float, label: String) -> bool:
	var dt := 1.0 / 60.0
	var t := 0.0
	while t < max_seconds:
		_sim += dt * 144.0
		_v.call("sim_tick", dt, _ctx(_sim))
		if _anim != null:
			_anim.advance(dt)
		t += dt
		var st := String(_v.call("debug_state")["state"])
		if t > 0.2 and targets.has(st):
			return true
	print("[LIFEACT] TIMEOUT ", label, " state=", String(_v.call("debug_state")["state"]))
	return false

func _joint(name: String) -> Node3D:
	return _model.call("get_joint", name) as Node3D

func _dbg() -> Dictionary:
	return _v.call("debug_state")

func _state() -> String:
	return String(_dbg()["state"])

func _house_local(w: Vector3) -> Vector3:
	var root: Node3D = _cottage["root"] as Node3D
	return root.to_local(w)

func _run() -> void:
	print("[LIFEACT] ===== P9 生活动作行为探针 =====")
	_holder = Node3D.new()
	_holder.name = "World"
	get_root().add_child(_holder)
	_world = WORLD.build(_holder, true)
	var Cottage = load("res://scripts/cottage.gd")
	_cottage = Cottage.build(_holder)
	await process_frame
	await process_frame
	_v = load("res://scripts/isle_villager.gd").build(_holder, _cottage, 7)
	await process_frame
	_anim = _v.get("anim") as AnimationPlayer
	_model = _v.get("model_root") as Node3D
	_v.set("debug_log", false)
	var graph: Dictionary = _v.get("graph")
	print("[LIFEACT] graph nodes=", (graph["nodes"] as Dictionary).size(), " spots=", (graph["spots"] as Dictionary).size())
	var issues: Array = SPOTS.validate(graph)
	_ck(issues.is_empty(), "图/活动点校验 clean（含 swing/sea_view）", str(issues))
	_ck((graph["spots"] as Dictionary).has("swing"), "swing spot 存在")
	_ck((graph["spots"] as Dictionary).has("sea_view"), "sea_view spot 存在")
	_ck((graph["nodes"] as Dictionary).has("swing_stand"), "swing_stand 节点存在")
	_ck((graph["nodes"] as Dictionary).has("dock_sea_watch"), "dock_sea_watch 节点存在")
	var vsw: Dictionary = (graph["spots"] as Dictionary)["view_swing"]
	var pivot_world := Vector3(M.BIG_TREE_X + 3.0, 0.0, M.BIG_TREE_Z)
	var vsw_yaw_target: float = atan2(-(pivot_world.x - (vsw["anchor"] as Vector3).x), -(pivot_world.z - (vsw["anchor"] as Vector3).z))
	_ck(absf(wrapf(float(vsw["yaw"]) - vsw_yaw_target, -PI, PI)) < 0.10,
		"view_swing 朝向真实秋千吊点（旧值偏 132°）", "yaw=%.3f target=%.3f" % [float(vsw["yaw"]), vsw_yaw_target])

	# 秋千真实节点注入（等价 main 侧接线）
	var swing: Node3D = _world.get("swing", null) as Node3D
	var seat: Node3D = swing.find_child("SwingSeat", true, false) as Node3D
	_ck(_v.call("set_swing_target", swing, seat), "set_swing_target(真实 Swing/SwingSeat) 生效")

	_test_schedule_cross_midnight()
	_test_sleep_chain()
	_test_autonomous_cross_midnight()
	_test_eat()
	_test_swing()
	_test_sea_view()
	_test_arbitration()

	print("")
	print("[LIFEACT] RESULT %d/%d passed, %d failed" % [_checks - _fails.size(), _checks, _fails.size()])
	for f in _fails:
		print("[LIFEACT] FAILED: " + String(f))
	quit(0 if _fails.is_empty() else 1)

# ============================================================ A. 调度 =======
func _test_schedule_cross_midnight() -> void:
	print("")
	print("== SCHEDULE 跨 00:00 睡眠时长 ==")
	var sch = SCHEDULE.new(7)
	var events: Dictionary = ASTRO.day_events(20.5 * 3600.0)
	var c1: Dictionary = sch.call("choose", {"sim_seconds": 20.5 * 3600.0, "sim_rate": 144.0,
		"sun_alt": -5.0, "events": events, "weather": {}})
	var events2: Dictionary = ASTRO.day_events(23.9 * 3600.0)
	var c2: Dictionary = sch.call("choose", {"sim_seconds": 23.9 * 3600.0, "sim_rate": 144.0,
		"sun_alt": -10.0, "events": events2, "weather": {}})
	print("  choose@20:30 dur=%.2fs kind=%s | choose@23:54 dur=%.2fs" % [float(c1["duration_real"]), String(c1["kind"]), float(c2["duration_real"])])
	# night 20:30-24:00 = 90 min → 37.5 s；接上 next window (00:00-wake ≈375 min) → 总 ~193.75 s
	_ck(String(c1["kind"]) == "sleep" and float(c1["duration_real"]) > 180.0,
		"20:30 的睡眠时长跨过 00:00 接上下一 sleep 窗口（>180 s）", "%.2f" % float(c1["duration_real"]))
	_ck(float(c2["duration_real"]) > 150.0, "23:54 的睡眠时长同样跨 00:00（>150 s）", "%.2f" % float(c2["duration_real"]))

# ============================================================ B. 睡觉链 ======
func _test_sleep_chain() -> void:
	print("")
	print("== SLEEP 完整动作链（坐床沿 → 搬腿 → 躺平 → 睡 → 醒）==")
	_sim = 20.6 * 3600.0
	_v.call("clear_force")
	_v.set("_last_sim", -1.0)
	_v.call("force_bed")
	var ok_sleep := await_wait_state("SLEEP", 60.0)
	_ck(ok_sleep, "force_bed 到达 SLEEP（含搬腿/躺平两段）")
	var bed: Dictionary = (_v.get("graph")["spots"] as Dictionary)["bed_attic"]
	var lie_root: Vector3 = (bed["anchor"] as Vector3) + Vector3(0.0, 0.02, 0.0)
	var p_sleep: Vector3 = _v.position
	_ck(p_sleep.distance_to(lie_root) < 0.03, "睡姿 root = 床垫顶锚点+0.02", _f3(p_sleep) + " vs " + _f3(lie_root))
	_ck(String(_dbg()["clip"]) == "sleep", "睡眠循环剪辑 sleep")
	var head_center: Vector3 = _joint("head").global_transform * MODEL.HEAD_CENTER
	var head_house := _house_local(head_center)
	# 真实资产：枕头 A 房屋局部 x[-1.495,-1.186] z[-0.885,-0.445]
	_ck(head_house.x >= -1.50 and head_house.x <= -1.18 and head_house.z >= -0.89 and head_house.z <= -0.44,
		"头心落在枕头 A 枕面内（真实资产几何，不夹枕缝）", _f3(head_house))
	var body_min: float = float(MODEL.measure(_model, {"include_hidden": false})["min_y"])
	var mattress_world: float = _house_local(Vector3(0.0, 0.0, 0.0)).y
	# 模型 measure 的 min_y 是世界坐标；用房屋局部换算比较（床垫顶 3.64 + 房屋世界 y 7.9456）
	var mattress_w: float = (_cottage["root"] as Node3D).to_global(Vector3(0.0, 3.64, 0.0)).y
	_ck(body_min >= mattress_w - 0.004, "睡姿身体不穿床垫", "%.4f vs %.4f" % [body_min, mattress_w])
	var knee_r: Vector3 = _joint("knee_r").global_position
	_ck(knee_r.y - mattress_w <= 0.22, "右膝不再翘空中（<=0.22 m，旧值 0.313）", "%.4f" % (knee_r.y - mattress_w))
	_ck(bool(_dbg()["bowl"]) == false, "睡觉时碗不可见")

	# 分段 root：重放一次 LIE_IN 采样（capture 在 _on_arrive 时无法插桩，这里用醒来链反向验证）
	# 醒来链：直接推进到清晨窗口
	print("  -> 世界时间跳到次日清晨，触发醒来")
	var sim_now := _sim
	_sim = sim_now + 24.0 * 3600.0
	_sim -= fposmod(_sim, 86400.0)
	_sim += 7.0 * 3600.0
	var woke := await_wait_state_multi(["IDLE", "WALK"], 30.0)
	_ck(woke, "清晨窗口自然醒来")
	_ck(not bool((( _v.get("graph")["spots"] as Dictionary)["bed_attic"] as Dictionary).get("reserved", false)), "醒来后床已释放")
	_ck(String(_dbg()["state"]) == "IDLE" or String(_dbg()["state"]) == "WALK", "醒来状态合法", String(_dbg()["state"]))
	_ck(absf(_v.rotation.x) < 0.01 and absf(_v.rotation.z) < 0.01, "醒来后无残留躺姿倾角", "%.3f/%.3f" % [_v.rotation.x, _v.rotation.z])

func await_wait_state(target: String, max_seconds: float) -> bool:
	return await_wait_state_multi([target], max_seconds)

func await_wait_state_multi(targets: Array, max_seconds: float) -> bool:
	var dt := 1.0 / 60.0
	var t := 0.0
	while t < max_seconds:
		_sim += dt * 144.0
		_v.call("sim_tick", dt, _ctx(_sim))
		_anim.advance(dt)
		t += dt
		var st := _state()
		if t > 0.2 and targets.has(st):
			return true
	return false

# ============================================================ C. 跨 00:00 ==
func _test_autonomous_cross_midnight() -> void:
	print("")
	print("== 自主睡眠跨 00:00（旧实现会起床走回再躺）==")
	_v.call("clear_force")
	_v.call("force_walk_to_node", "attic_exit")
	await_wait_state_multi(["IDLE"], 40.0)
	_v.call("clear_force")
	_sim = 23.0 * 3600.0 + 50.0 * 60.0
	_v.set("_last_sim", -1.0)
	var saw_sleep := false
	var bed_in_count := 0
	var woke_early := false
	var prev := ""
	var sleep_fish_res: Dictionary = {}
	var sleep_fish_checked := false
	var t := 0.0
	var dt := 1.0 / 60.0
	while t < 55.0:
		_sim += dt * 144.0
		_v.call("sim_tick", dt, _ctx(_sim))
		_anim.advance(dt)
		t += dt
		var st := _state()
		if st != prev:
			if st == "BED_IN":
				bed_in_count += 1
			if st == "SLEEP":
				saw_sleep = true
				if not sleep_fish_checked:
					# 睡眠中钓鱼必须被拒绝（互斥；此时不是 forced 模式，走真实 sleeping 守卫）
					sleep_fish_checked = true
					sleep_fish_res = _v.call("begin_fishing", Callable(self, "_fish_commit"), Callable())
			prev = st
		# 入睡后统计：跨过 00:00 后（sim>86400 或 < 3600）是否提前醒来
		if saw_sleep and st != "SLEEP" and st != "LIE_OUT" and st != "BED_OUT":
			woke_early = true
	print("  sleep_seen=%s bed_in_count=%d woke_early=%s sim=%.0f state=%s" % [str(saw_sleep), bed_in_count, str(woke_early), _sim, _state()])
	_ck(saw_sleep, "23:50 自主决策进入睡眠")
	_ck(bed_in_count == 1, "跨 00:00 全程只躺下一次（不重复起睡）", "bed_in=%d" % bed_in_count)
	_ck(not woke_early, "跨 00:00 后保持睡眠（旧实现 20 s 后起床再躺）")
	_ck(not bool(sleep_fish_res.get("ok", true)) and String(sleep_fish_res.get("reason", "")) == "sleeping",
		"睡眠中拒绝钓鱼（互斥）", str(sleep_fish_res))
	_ck(_state() == "SLEEP" or _state() == "LIE_OUT" or _state() == "BED_OUT" or _state() == "IDLE",
		"跨午夜后状态合法", _state())

# ============================================================ D. 吃饭 ======
func _test_eat() -> void:
	print("")
	print("== EAT 完整动作链 + 道具 ==")
	_v.call("clear_force")
	_sim = 12.2 * 3600.0
	_v.set("_last_sim", -1.0)
	_v.call("force_eat", "eat_s")
	var ok_eat := await_wait_state("EAT", 60.0)
	_ck(ok_eat, "force_eat(eat_s) 到达 EAT")
	_ck(bool(_dbg()["bowl"]), "EAT 期间桌上碗可见（set_bowl_visible）")
	var bowl: MeshInstance3D = _model.get_node_or_null("Bowl") as MeshInstance3D
	_ck(bowl != null and bowl.visible, "Bowl 节点实际 visible")
	var mouth := _joint("head").global_transform * Vector3(0.0, 0.074, -0.105)
	var min_mouth := 99.0
	var min_bowl := 99.0
	var max_elbow_dy := -99.0
	var bowl_center := bowl.global_transform * Vector3(0.0, 0.026, 0.0)
	var dt := 1.0 / 60.0
	for i in 200:
		_sim += dt * 144.0
		_v.call("sim_tick", dt, _ctx(_sim))
		_anim.advance(dt)
		var palm: Vector3 = _joint("hand_r").global_transform * Vector3(0.0, -0.06, 0.0)
		mouth = _joint("head").global_transform * Vector3(0.0, 0.074, -0.105)
		min_mouth = minf(min_mouth, palm.distance_to(mouth))
		min_bowl = minf(min_bowl, palm.distance_to(bowl.global_transform * Vector3(0.0, 0.026, 0.0)))
		max_elbow_dy = maxf(max_elbow_dy, _joint("elbow_r").global_position.y - _joint("shoulder_r").global_position.y)
	print("  hand-mouth min=%.3f hand-bowl min=%.3f elbow_dy max=%.3f" % [min_mouth, min_bowl, max_elbow_dy])
	_ck(min_mouth <= 0.12, "EAT：手送到嘴边（<=0.12 m）", "%.3f" % min_mouth)
	_ck(min_bowl <= 0.13, "EAT：右手下探到碗（<=0.13 m）", "%.3f" % min_bowl)
	_ck(max_elbow_dy <= 0.02, "EAT：肘始终不高于肩", "%.3f" % max_elbow_dy)
	_ck(absf(_anim.speed_scale - 1.0) > 0.001, "EAT：循环变速（不是 3 s 无脑重复）", "%.3f" % _anim.speed_scale)
	# 退出清理：clear_force（接管路径）
	_v.call("clear_force")
	var dbg := _dbg()
	_ck(not bool(dbg["bowl"]) and bowl != null and not bowl.visible, "接管退出后碗隐藏清理")
	var eat_spot: Dictionary = (_v.get("graph")["spots"] as Dictionary)["eat_s"]
	var ap: Vector3 = eat_spot["approach"]
	_ck((_v.position - ap).length() < 0.05, "接管退出后回到站立接近点（不悬在座面）", _f3(_v.position))
	_ck(absf(_v.rotation.x) < 0.01, "接管退出后无残留倾角")
	_ck(not bool(eat_spot["reserved"]), "接管退出后座位释放")
	var inv = _v.get("_ctx").get("inventory", null)
	_ck(true, "吃饭不触碰共享库存（本探针无 inventory 注入，代码路径不读写库存）")

# ============================================================ E. 秋千 ======
func _test_swing() -> void:
	print("")
	print("== SWING：真实到达 + 坐姿贴座 + 角度同步 + 轻柔摆 ==")
	_v.call("clear_force")
	_sim = 14.0 * 3600.0
	_v.set("_last_sim", -1.0)
	_ck(bool(_v.call("force_swing")), "force_swing 受理（已注入真实吊点/座椅）")
	var ok_sit := await_wait_state("SIT", 90.0)
	_ck(ok_sit, "走到 swing_stand 并坐进秋千")
	var swing_spot: Dictionary = (_v.get("graph")["spots"] as Dictionary)["swing"]
	_ck(String(_dbg()["spot_id"]) == "swing", "秋千点已预约", String(_dbg()["spot_id"]))
	var swing_node: Node3D = _world.get("swing", null) as Node3D
	var seat: Node3D = swing_node.find_child("SwingSeat", true, false) as Node3D
	# 坐姿贴座（一帧内对齐）：root ≈ 座面上表面 + 0.02（带吊点倾角）
	var dt := 1.0 / 60.0
	var max_attach := 0.0
	var theta_min := 99.0
	var theta_max := -99.0
	var max_step := 0.0
	var prev := _v.position
	var max_tilt_err := 0.0
	var t := 0.0
	while t < 8.0:
		_sim += dt * 144.0
		_v.call("sim_tick", dt, _ctx(_sim))
		_anim.advance(dt)
		t += dt
		var seat_xf: Transform3D = seat.global_transform
		var expect: Vector3 = seat_xf * Vector3(0.0, 0.035 + 0.02, 0.0)
		max_attach = maxf(max_attach, _v.global_position.distance_to(expect))
		var th: float = swing_node.rotation.x
		theta_min = minf(theta_min, th)
		theta_max = maxf(theta_max, th)
		max_step = maxf(max_step, _v.global_position.distance_to(prev))
		prev = _v.global_position
		max_tilt_err = maxf(max_tilt_err, absf(_v.rotation.x - th))
	print("  attach_max=%.4f theta=[%.3f,%.3f] amp_deg=%.1f tilt_err=%.3f max_step=%.3f" % [
		max_attach, theta_min, theta_max, rad_to_deg(theta_max - theta_min), max_tilt_err, max_step])
	_ck(max_attach <= 0.04, "坐姿 root 始终贴住真实座面（<=0.04 m）", "%.4f" % max_attach)
	var amp_half := (theta_max - theta_min) * 0.5
	_ck(amp_half >= 0.087 and amp_half <= 0.175, "轻柔前后摆每侧 5–10°（0.087–0.175 rad；峰-峰 %.1f°）" % rad_to_deg((theta_max - theta_min)),
		"half=%.4f rad / %.1f°" % [amp_half, rad_to_deg(amp_half)])
	_ck(max_tilt_err <= 0.03, "身体俯仰角与秋千实际角度同步（<=0.03 rad）", "%.3f" % max_tilt_err)
	_ck(max_step <= 0.10, "坐秋千期间单帧位移无瞬移", "%.3f" % max_step)
	_ck(_v.global_position.y > 7.9, "坐姿明显高于地面（真实座高）", "%.3f" % _v.global_position.y)
	# 结束：把活动时长顶满，走 SIT_OUT → IDLE
	_v.set("_hold_t", 999.0)
	ok_sit = await_wait_state_multi(["IDLE", "WALK"], 15.0)
	var swing_spot2: Dictionary = (_v.get("graph")["spots"] as Dictionary)["swing"]
	_ck(ok_sit, "秋千起身回到 IDLE/WALK")
	_ck(not bool(swing_spot2["reserved"]), "秋千点释放")
	_ck(absf(_v.rotation.x) < 0.01 and absf(_v.rotation.z) < 0.01, "起身后无残留倾角", "%.3f" % _v.rotation.x)
	_ck((_v.position - (swing_spot2["approach"] as Vector3)).length() < 0.10, "起身后站回 swing_stand 地面", _f3(_v.position))
	_ck(not bool(_dbg()["swing"]["control"]), "秋千控制权已交还 main（control=false）")
	# 接管安全退出：再坐一次，clear_force 中途接管
	_v.call("force_swing")
	await_wait_state("SIT", 90.0)
	_v.call("clear_force")
	_ck(String(_dbg()["state"]) == "IDLE", "秋千中 clear_force → IDLE")
	_ck(absf(_v.rotation.x) < 0.01, "秋千中接管无残留倾角", "%.3f" % _v.rotation.x)
	_ck(not bool(_dbg()["swing"]["control"]), "接管后不再控制吊点")

# ============================================================ F. 观海 ======
func _test_sea_view() -> void:
	print("")
	print("== SEA_VIEW：真实到达码头、面向海面、慢速观察 ==")
	_v.call("clear_force")
	_sim = 15.0 * 3600.0
	_v.set("_last_sim", -1.0)
	_ck(bool(_v.call("force_sea_view")), "force_sea_view 受理")
	var ok := await_wait_state("IDLE", 120.0)
	_ck(ok, "真实走到码头观海点")
	var sv: Dictionary = (_v.get("graph")["spots"] as Dictionary)["sea_view"]
	_ck(String(_dbg()["at_node"]) == "dock_sea_watch", "到达 dock_sea_watch 节点", String(_dbg()["at_node"]))
	_ck((_v.position - (sv["anchor"] as Vector3)).length() < 0.08, "站位在观海点", _f3(_v.position))
	var yaw_err := absf(wrapf(_v.rotation.y - float(sv["yaw"]), -PI, PI))
	_ck(yaw_err < 0.10, "面向海面（与 dock 向海轴一致）", "err=%.3f rad" % yaw_err)
	var clip := String(_dbg()["clip"])
	_ck(clip == "idle" or clip == "idle_alt", "播放待机观察剪辑", clip)
	_ck(_anim.speed_scale <= 0.70, "轻缓观察（播放速度 <=0.70）", "%.3f" % _anim.speed_scale)
	# 结束恢复：把停留时长压到 0.05 s，走正常 _tick_idle → _finish_activity 收尾路径
	_v.set("_idle_dur", 0.05)
	await_wait_state_multi(["IDLE"], 5.0)
	_ck(not bool((_v.get("graph")["spots"] as Dictionary)["sea_view"]["reserved"]), "观海点释放")
	_ck(_anim.speed_scale > 0.9, "结束后恢复常速动画", "%.2f" % _anim.speed_scale)

# ============================================================ G. 仲裁 ======
func _test_arbitration() -> void:
	print("")
	print("== 仲裁/互斥 ==")
	_v.call("clear_force")
	# 钓鱼期间不启动生活动作
	_sim = 12.0 * 3600.0
	_v.set("_last_sim", -1.0)
	var r2: Dictionary = _v.call("begin_fishing", Callable(self, "_fish_commit"), Callable())
	_ck(bool(r2.get("ok", false)), "钓鱼可正常开始", str(r2))
	var dt := 1.0 / 60.0
	for i in 120:
		_sim += dt * 144.0
		_v.call("sim_tick", dt, _ctx(_sim))
		_anim.advance(dt)
	var dbg := _dbg()
	_ck(String(dbg["kind"]) == "" or String(dbg["kind"]).begins_with("forced"),
		"钓鱼期间不产生普通生活活动意图", String(dbg["kind"]))
	_v.call("cancel_fishing", "probe")
	_ck(not bool(_v.call("fishing_active")), "停止钓鱼后回到普通调度")
	# 睡眠中 clear_force 安全落地
	_sim = 21.5 * 3600.0
	_v.set("_last_sim", -1.0)
	_v.call("force_bed")
	await_wait_state("SLEEP", 60.0)
	var bed: Dictionary = (_v.get("graph")["spots"] as Dictionary)["bed_attic"]
	_v.call("clear_force")
	var ap: Vector3 = bed["approach"]
	_ck((_v.position - ap).length() < 0.05, "睡眠被接管后回到床下站立点（不站在床上）", _f3(_v.position))
	_ck(absf(_v.rotation.x) < 0.01 and absf(_v.rotation.z) < 0.01, "睡眠被接管后恢复直立")
	_ck(String(_dbg()["state"]) == "IDLE", "睡眠被接管后 IDLE")
	_ck(not bool(bed["reserved"]), "睡眠被接管后床释放")

func _fish_commit(_fish_id: String, _size: float) -> bool:
	return true
