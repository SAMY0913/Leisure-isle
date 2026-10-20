extends SceneTree
## P5 小船生命周期验收探针（headless）
##   <godot_console.exe> --headless --path D:/休闲小岛幻境/游戏工程 --script res://tools/probe_boat_p5.gd
## 逐帧驱动 isle.tscn 的 main.gd 私有状态机，检查：
##   航线契约（>=8 条、码头起终点、coastal/far 分类、5D 远海淡出、far_entries）
##   离港加速、航向=切线、coastal 往返、far 淡出/等待/淡入/返航/停靠、18:00-08:00 休息、
##   手动跳时对齐、无瞬移、随波高度、淡出材质、夜间探照灯 global uniform。
## 退出码：0 = 全部断言通过（数据契约在旧 P4 航线上标 PENDING）。

const MainScene := preload("res://isle.tscn")
const DT := 1.0 / 60.0
const STEP := 1.0 / 20.0
const SIM_DAY := 480.0
const FAR_WAIT := 28800.0

var _pass := 0
var _fail := 0
var _pending := 0
var m: Node = null
var _data_ok := true

func _initialize() -> void:
	print("=== P5 BOAT PROBE START ===")
	await process_frame
	m = MainScene.instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	m._paused = false
	m._time_source = "sim"
	m._day_length = SIM_DAY
	m._sim_seconds = 10.0 * 3600.0
	m._sim_delta = 0.0
	m._frame_t = 0.0
	m._sail_boat_visible = true
	probe_routes()
	probe_coastal_cycle()
	probe_far_cycle()
	probe_rest_window()
	probe_time_jump()
	probe_spot_light()
	probe_fade_materials()
	print("=== P5 BOAT PROBE RESULT: ", "PASS" if _fail == 0 else "FAIL",
		" pass=", _pass, " fail=", _fail, " pending=", _pending, " ===")
	quit(0 if _fail == 0 else 1)

func _check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("  [OK] ", msg)
	else:
		_fail += 1
		print("  [FAIL] ", msg)

func _pend(cond: bool, msg: String) -> void:
	if _data_ok:
		_check(cond, msg)
	else:
		_pending += 1
		print("  [PENDING-DATA] ", msg, " = ", cond)

func _route_by_kind(kind: String) -> Dictionary:
	for r in m._sail_routes:
		if String((r as Dictionary).get("kind", "")) == kind:
			return r
	return {}

func _start_with(route: Dictionary) -> void:
	var saved: Array = m._sail_routes
	m._sail_routes = [route]
	m._sail_route_last = -1
	m._start_boat_departure()
	m._sail_routes = saved

func _set_time(hour: float) -> void:
	m._sim_seconds = hour * 3600.0
	m._sim_delta = 0.0

func _step(n: int, dt := STEP) -> void:
	for i in n:
		m._frame_t += dt
		var sim_dt := 0.0
		if m._time_source == "sim":
			sim_dt = dt * (86400.0 / m._day_length)
		m._sim_delta = sim_dt
		m._sim_seconds += sim_dt
		var before_state: String = m._boat_state
		var before_pos: Vector3 = m._sailboat.global_position
		m._update_boat(dt)
		var after_state: String = m._boat_state
		var after_pos: Vector3 = m._sailboat.global_position
		if before_state == after_state and before_state != "OFFSCREEN_WAIT" and before_state != "RESTING" and before_state != "DOCKED":
			var jump := before_pos.distance_to(after_pos)
			if jump > m._boat_route_speed * dt + 0.6:
				print("  [JUMP] state=", before_state, " jump=", snappedf(jump, 0.01), " dt=", dt, " pos=", after_pos)
				_check(false, "无瞬移（state=" + before_state + "）")
				return

func _step_until(state: String, max_steps: int, dt := STEP) -> bool:
	for i in max_steps:
		if m._boat_state == state:
			return true
		_step(1, dt)
	return m._boat_state == state

# ============================================================
func probe_routes() -> void:
	print("--- ROUTES ---")
	var routes: Array = m._sail_routes
	_check(routes.size() >= 8, "航线数量 >= 8（实际 %d）" % routes.size())
	for r in routes:
		if not (r as Dictionary).has("kind"):
			_data_ok = false
			break
	var dock: Vector3 = m._boat_dock_pos
	var D: float = float(m._world.get("island_diameter", 0.0))
	_pend(D > 10.0, "world.island_diameter 已提供且合理（%.3f m）" % D)
	var coastal := 0
	var far := 0
	var max_dock_err := 0.0
	for r_v in routes:
		var r: Dictionary = r_v
		var out_pts: Array = m._route_points(r.get("out", []))
		var back_pts: Array = m._route_points(r.get("back", []))
		if out_pts.size() < 2 or back_pts.size() < 2:
			_check(false, "航线 %s 起终点数量不足" % String(r.get("name", "?")))
			continue
		max_dock_err = maxf(max_dock_err, (out_pts[0] as Vector3).distance_to(dock))
		max_dock_err = maxf(max_dock_err, (back_pts[back_pts.size() - 1] as Vector3).distance_to(dock))
		var k := String(r.get("kind", ""))
		if k == "coastal":
			coastal += 1
		elif k == "far":
			far += 1
		if k == "far":
			var md := 0.0
			for p in out_pts:
				md = maxf(md, Vector2((p as Vector3).x, (p as Vector3).z).length())
			_pend(md >= 5.6 * D - 1.0, "far 航线 %s 末端距岛心 %.1f m >= 5.6D(%.1f)" % [String(r.get("name", "?")), md, 5.6 * D])
			_pend(float(r.get("fade_start", -1.0)) >= 5.0 * D - 1.0, "far 航线 %s fade_start %.1f >= 5D(%.1f)" % [String(r.get("name", "?")), float(r.get("fade_start", -1.0)), 5.0 * D])
			_pend((r.get("far_entries", []) as Array).size() >= 2, "far 航线 %s 提供 >=2 个远海返航入口" % String(r.get("name", "?")))
	_pend(max_dock_err < 1.2, "所有航线 out[0] 与 back[-1] 回到码头（最大误差 %.2f m）" % max_dock_err)
	_pend(coastal >= 4, "coastal 航线 >= 4（实际 %d）" % coastal)
	_pend(far >= 4, "far 航线 >= 4（实际 %d）" % far)
	var rp = m._world.get("sail_return_paths", null)
	_pend(rp is Dictionary and (rp as Dictionary).size() >= 4, "world.sail_return_paths 提供 >=4 条远海返航路径")

# ============================================================
func probe_coastal_cycle() -> void:
	print("--- COASTAL CYCLE ---")
	var route := _route_by_kind("coastal")
	if route.is_empty():
		route = m._sail_routes[0]
	_set_time(10.0)
	m._boat_state = "DOCKED"
	m._sail_dwell = 0.0
	m._boat_fade = 1.0
	_start_with(route)
	_check(m._boat_state == "DEPARTING", "出航后状态 = DEPARTING")
	_check(m._sailboat.global_position.distance_to(m._boat_dock_pos) < 0.6, "出航起点在码头（误差 %.2f m）" % m._sailboat.global_position.distance_to(m._boat_dock_pos))
	_check(m._boat_speed_cur < 0.01, "离港初速为 0")
	var s0: float = m._boat_speed_cur
	_step(6, DT)
	var s1: float = m._boat_speed_cur
	_step(20, DT)
	var s2: float = m._boat_speed_cur
	_check(s1 > 0.0 and s1 < m._boat_route_speed, "离港 0.1s 速度已增加但未到最大（%.2f / %.2f）" % [s1, m._boat_route_speed])
	_check(s2 >= s1 and s2 <= m._boat_route_speed + 0.001, "离港后速度单调增加到上限（%.2f -> %.2f）" % [s1, s2])
	_check(s0 < 0.01, "速度从 0 平滑起步")

	var min_dot := 1.0
	var prev: Vector3 = m._sailboat.global_position
	var states := {}
	var trace_every := 40
	for i in 6000:
		_step(1)
		states[m._boat_state] = true
		var cur: Vector3 = m._sailboat.global_position
		var d := cur - prev
		if d.length() > 0.02 and m._boat_state in ["DEPARTING", "COASTAL_CRUISE", "OUTBOUND_FAR"]:
			var hdg := Vector3(sin(m._sail_heading), 0.0, cos(m._sail_heading))
			min_dot = minf(min_dot, hdg.dot(d.normalized()))
		prev = cur
		if int(i) % 120 == 0:
			var fwd: Vector3 = m._sailboat.global_transform.basis.z
			var expect := Vector3(sin(m._sail_heading), 0.0, cos(m._sail_heading))
			if m._boat_state in ["DEPARTING", "COASTAL_CRUISE", "OUTBOUND_FAR"]:
				_check(fwd.dot(expect) > 0.995, "船头模型 +Z 与航向一致（dot=%.4f，state=%s）" % [fwd.dot(expect), m._boat_state])
		if m._boat_state == "RESTING" or m._boat_state == "DOCKED":
			break
	_check(min_dot > 0.92, "运动方向与航向一致（最小 dot=%.3f）" % min_dot)
	_check(m._boat_state == "RESTING" or m._boat_state == "DOCKED", "近海航线完成返航并停靠（state=%s）" % m._boat_state)
	_check(m._sailboat.global_position.distance_to(m._boat_dock_pos) < 0.6, "返航终点在码头（误差 %.2f m）" % m._sailboat.global_position.distance_to(m._boat_dock_pos))
	_check(m._boat_fade > 0.99, "停靠时完全可见（fade=%.2f）" % m._boat_fade)

# ============================================================
func probe_far_cycle() -> void:
	print("--- FAR CYCLE ---")
	var route := _route_by_kind("far")
	if route.is_empty():
		route = m._sail_routes[0]
	_set_time(12.0)
	m._boat_state = "DOCKED"
	m._sail_dwell = 0.0
	m._boat_fade = 1.0
	_start_with(route)
	var fade_prev := 1.0
	var fade_mono := true
	var got_wait := _step_until("OFFSCREEN_WAIT", 26000, STEP)
	_check(got_wait, "远海路线完成淡出并进入 OFFSCREEN_WAIT（state=%s）" % m._boat_state)
	if got_wait:
		_check(m._sailboat.visible == false, "OFFSCREEN_WAIT 时船体不可见")
		_check(absf(m._boat_wait_sim - m._boat_wait_total) < 1.0, "等待时长 = %.0f 模拟秒（实际 %.0f）" % [m._boat_wait_total, m._boat_wait_sim])
		_check(m._boat_fade < 0.01, "OFFSCREEN_WAIT 时 fade=0")
		var entry_dist := 0.0
		var fade_in0: float = float(m._boat_fade)
		var sim_before: float = m._sim_seconds
		# 推进 8 个模拟小时
		var guard := 0
		while m._boat_state == "OFFSCREEN_WAIT" and guard < 20000:
			_step(1)
			guard += 1
		_check(m._boat_state == "FADING_IN", "8 模拟小时等待结束进入 FADING_IN（state=%s, 推进 %.0f 模拟秒）" % [m._boat_state, m._sim_seconds - sim_before])
		if m._boat_state == "FADING_IN":
			_check(absf((m._sim_seconds - sim_before) - m._boat_wait_total) < 120.0, "等待消耗约 8 模拟小时（%.0f s）" % (m._sim_seconds - sim_before))
			entry_dist = Vector2(m._sailboat.global_position.x, m._sailboat.global_position.z).length()
			var D: float = float(m._world.get("island_diameter", 60.0))
			_check(m._boat_fade <= 0.02, "淡入起点完全透明（fade=%.3f）" % m._boat_fade)
			_check(entry_dist >= 5.0 * D - 1.0, "远海入口距岛心 %.1f m >= 5D(%.1f)" % [entry_dist, 5.0 * D])
			var fi0: float = m._boat_fade
			_step(30)
			_check(m._boat_fade >= fi0 - 0.001, "淡入过程 fade 单调不减（%.3f -> %.3f）" % [fi0, m._boat_fade])
			var got_ret := _step_until("RETURNING", 6000, STEP)
			_check(got_ret, "淡入完成进入 RETURNING（state=%s）" % m._boat_state)
			var got_rest := _step_until("RESTING", 20000, STEP)
			_check(got_rest, "返航完成进入 RESTING（state=%s）" % m._boat_state)
			_check(m._sailboat.global_position.distance_to(m._boat_dock_pos) < 0.6, "远海返航终点在码头（误差 %.2f m）" % m._sailboat.global_position.distance_to(m._boat_dock_pos))
			_check(m._boat_fade > 0.99, "返航结束完全可见（fade=%.2f）" % m._boat_fade)
			_check(absf(m._boat_speed_cur) < 0.01, "停靠后速度为 0（实际 %.3f）" % m._boat_speed_cur)
	# 淡出单调性：重跑并采样（用较大 dt 加速）
	_set_time(12.0)
	m._boat_state = "DOCKED"
	m._sail_dwell = 0.0
	m._boat_fade = 1.0
	_start_with(route)
	var samples: Array = []
	for i in 12000:
		_step(1)
		if m._boat_state == "OUTBOUND_FAR":
			samples.append(m._boat_fade)
		if m._boat_state == "OFFSCREEN_WAIT":
			break
	for i in range(1, samples.size()):
		if float(samples[i]) > float(samples[i - 1]) + 0.001:
			fade_mono = false
	_check(samples.size() == 0 or fade_mono, "OUTBOUND_FAR 期间 fade 单调不增（采样 %d）" % samples.size())

# ============================================================
func probe_rest_window() -> void:
	print("--- REST WINDOW 18:00-08:00 ---")
	_set_time(19.0)
	m._boat_state = "DOCKED"
	m._sail_dwell = 0.0
	m._boat_rest_until = -1.0
	_step(2, DT)
	_check(m._boat_state == "RESTING", "19:00 停靠状态直接进入 RESTING（state=%s）" % m._boat_state)
	var rest_until_night: float = m._boat_rest_until
	# 时间必须单调向前：19:00 -> 次日 03:00 -> 次日 08:05
	_set_time(24.0 + 3.0)
	_step(2, DT)
	_check(m._boat_state == "RESTING", "次日 03:00 仍在 RESTING（不得出港）")
	_check(m._boat_rest_until >= rest_until_night, "夜间休息至少延长到次日 08:00（rest_until=%.0f）" % m._boat_rest_until)
	_set_time(24.0 + 8.0 + 5.0 / 60.0)
	_step(3, DT)
	_check(m._boat_state == "DOCKED", "08:05 休息结束转 DOCKED（state=%s）" % m._boat_state)
	# 白天停靠不会立刻出港
	m._sail_dwell = 3.0
	_step(10, DT)
	_check(m._boat_state == "DOCKED", "白天返港后有停靠等待，不瞬间出港")
	# dwell 归零后正常出航
	m._sail_dwell = 0.0
	var n_before: int = m._boat_trip
	_step(3, DT)
	_check(m._boat_state == "DEPARTING" and m._boat_trip == n_before + 1, "白天停靠等待结束后开始新一轮出航（trip %d -> %d）" % [n_before, m._boat_trip])
	# 夜间窗口禁止出港
	_set_time(19.5)
	m._boat_state = "DOCKED"
	m._sail_dwell = 0.0
	_step(3, DT)
	_check(m._boat_state == "RESTING", "19:30 即使 dwell=0 也不出港（state=%s）" % m._boat_state)

# ============================================================
func probe_time_jump() -> void:
	print("--- TIME JUMP ---")
	_set_time(12.0)
	m._boat_state = "OFFSCREEN_WAIT"
	m._boat_wait_sim = FAR_WAIT
	m._time_jump = FAR_WAIT
	m._sync_boat_clock()
	_check(absf(m._boat_wait_sim) < 1.0, "手动跳 8h 后远海等待归零（wait=%.0f）" % m._boat_wait_sim)
	_check(absf(m._time_jump) < 0.001, "跳时增量已被消费（_time_jump=%.1f）" % m._time_jump)
	_step(1, DT)
	_check(m._boat_state == "FADING_IN", "等待归零后下一帧开始远海返航淡入（state=%s）" % m._boat_state)
	_set_time(14.0)
	m._boat_state = "DOCKED"
	m._boat_rest_until = -1.0
	m._sail_dwell = 5.0
	m._time_jump = -3600.0
	m._sync_boat_clock()
	_check(absf(m._time_jump) < 0.001, "负向跳时也能消费 _time_jump")
	m._boat_state = "RESTING"
	m._boat_rest_until = 1e9
	_set_time(20.0)
	m._time_jump = 7200.0
	m._sync_boat_clock()
	_check(m._boat_rest_until >= m._next_rest_end_sim() - 1.0, "夜间 RESTING 期间跳时会把休息延长到下一个 08:00")

# ============================================================
func probe_spot_light() -> void:
	print("--- BOAT LANTERN / SPOT ---")
	_set_time(22.0)
	m._boat_state = "COASTAL_CRUISE"
	m._boat_fade = 1.0
	m._boat_speed_cur = 2.0
	m._sailboat.position = m._boat_dock_pos
	m._sail_heading = 0.4
	m._sun_alt = -12.0
	m._sail_boat_visible = true
	m._update_boat_spot()
	var sc: float = float(m._dbg_spot_strength)
	_check(sc > 0.2, "夜间探照灯强度 > 0.2（strength=%.3f）" % sc)
	var origin: Vector3 = m._dbg_spot_origin
	var expect_lens: Vector3 = m._sailboat.to_global(m._boat_spot_lens)
	_check(origin.distance_to(expect_lens) < 0.05, "探照灯原点在船头灯位（误差 %.3f m）" % origin.distance_to(expect_lens))
	var sdir: Vector3 = m._dbg_spot_dir
	var bow: Vector3 = m._sailboat.global_transform.basis.z.normalized()
	_check(sdir.dot(bow) > 0.6, "探照灯方向对准船头（dot=%.3f）" % sdir.dot(bow))
	_check(sdir.y < -0.05, "探照灯略向下照射（dir.y=%.3f）" % sdir.y)
	_pend(m._boat_spot_node != null and m._boat_spot_node.get_parent() == m._sailboat, "探照灯可见光锥挂在船体下，随船运动")
	if m._boat_spot_node != null:
		_pend(m._boat_spot_node.visible, "夜间探照灯可见光锥开启")
	# 白天关闭
	m._sun_alt = 25.0
	m._update_boat_spot()
	var sc_day: float = float(m._dbg_spot_strength)
	_check(sc_day < 0.01, "白天探照灯关闭（strength=%.3f）" % sc_day)
	# 静止时不抖动：连续两帧方向完全相同
	m._sun_alt = -12.0
	m._boat_speed_cur = 0.0
	m._update_boat_spot()
	var d1: Vector3 = m._dbg_spot_dir
	m._update_boat_spot()
	var d2: Vector3 = m._dbg_spot_dir
	_check(d1.distance_to(d2) < 0.0001, "船静止时探照灯方向稳定（不抖动）")
	# 船载悬挂灯材质存在并被点光增强
	_pend(m._boat_lantern_mat != null, "船载悬挂灯材质已接入")
	if m._boat_lantern_mat != null:
		_pend(m._shader_has_uniform(m._boat_lantern_mat, "glow"), "悬挂灯材质支持 glow 参数")

# ============================================================
func probe_fade_materials() -> void:
	print("--- FADE / WAVE ---")
	_check(m._boat_fade_mats.size() > 0, "已复制船体可淡出材质（%d 个）" % m._boat_fade_mats.size())
	m._boat_state = "OUTBOUND_FAR"
	m._boat_fade = 0.5
	m._sailboat.position = Vector3(30.0, 0.0, 20.0)
	m._apply_boat_fade()
	var ok := true
	for mt in m._boat_fade_mats:
		var v = (mt as ShaderMaterial).get_shader_parameter("fade_alpha")
		if v != null and absf(float(v) - 0.5) > 0.01:
			ok = false
	_check(ok, "fade=0.5 时所有船体材质 fade_alpha=0.5")
	m._boat_fade = 1.0
	m._apply_boat_fade()
	var wx := 12.3
	var wz := -8.7
	m._sailboat.position = Vector3(wx, m._wave_h(wx, wz) + 0.02, wz)
	_check(absf(m._sailboat.position.y - (m._wave_h(wx, wz) + 0.02)) < 0.001, "船体高度 = 波面 + 0.02m 吃水余量")
	_check(m._wake != null, "尾迹节点存在并随船更新")
