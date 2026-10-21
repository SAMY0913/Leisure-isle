class_name IsleVillager
extends Node3D
## P7-V4: 岛民自主生活控制器（状态机 + 路径行走 + 家具使用 + 日程选择）。
##
## 职责边界：
##   * 本文件只负责"角色运行时"：状态机、移动、动画播放/过渡、活动点预订与释放。
##   * 活动点/路径数据由 isle_villager_spots.gd 提供（无物理碰撞，图是唯一行走真值）。
##   * 世界时间/日程意图由 isle_villager_schedule.gd 决定（本文件不建任何时钟）。
##   * 时间来源、门、暂停、模式由 main.gd 每帧通过 sim_tick(delta, ctx) 注入。
##
## root 语义（与 isle_villager_model.gd 保持一致）：
##   站立：root=脚底；坐姿：root=座面+0.02；坐床沿：root=骨盆中心；躺姿：root=床垫顶+0.02。
##
## 时间约定：所有动画/过渡/移动使用真实帧时间；活动选择只读权威世界时间（_sim_seconds）。

const ModelScript := preload("res://scripts/isle_villager_model.gd")
const SpotScript := preload("res://scripts/isle_villager_spots.gd")
const ScheduleScript := preload("res://scripts/isle_villager_schedule.gd")

# ---- 移动参数（1.5m 风格化身高；步幅 1.0m/0.88s≈1.136 m/s）----
const WALK_SPEED := 1.05
const WALK_ACCEL := 1.7
const WALK_DECEL := 2.8
const ARRIVE_EPS := 0.03           # 节点到达判定（水平；小值减少到点吸附造成的台阶 y 突跳）
const DECEL_DIST := 0.9            # 到终点前减速距离
const TURN_RATE := 5.2             # rad/s 朝向最大角速度
const BLEND_TURN_SPEED := 0.30     # 转向时允许的最低速度系数
const MIN_WALK_SPEED := 0.22

# ---- 交互参数 ----
const DOOR_OPEN_DIST := 1.85
const DOOR_CLOSE_DIST := 2.60
const SIT_ROOT_OFFSET := 0.02      # 座位 root = 座面 + 0.02（模型 _sit 约定）
const BED_EDGE_INSET := 0.12       # 坐床沿时骨盆中心离床沿向内 0.12m
const BED_EDGE_ROOT_OFFSET := 0.085 # 坐床沿 root(骨盆中心) = 床垫顶 + 0.085（骨盆网格底 -0.085 → 刚好坐上）
const BED_LIE_ROOT_OFFSET := 0.02  # 躺姿 root = 床垫顶 + 0.02（模型 _lie 约定）

# ---- 时间/调度 ----
const WINDOW_CHECK_PERIOD := 0.25  # 世界窗口检查间隔（秒，低成本）
const JUMP_GUARD_SIM := 180.0      # 兜底：单帧模拟时间跨度超过它视为跳时
const DECISION_COOLDOWN := 0.35    # 活动结束后到下一次决策的最短间隔

# ---- 调试/报告 ----
var debug_log := false

enum State {
	IDLE, WALK, SIT_IN, SIT, EAT, SIT_OUT,
	BED_IN, LIE_IN, SLEEP, LIE_OUT, BED_OUT,
}

# ---- 公共数据（探针/报告读取）----
var graph: Dictionary = {}
var schedule: RefCounted = null
var model: Dictionary = {}
var anim: AnimationPlayer = null
var model_root: Node3D = null
var hair_style := 0
var stats: Dictionary = {}

# ---- 运行时 ----
var _pos := Vector3.ZERO
var _yaw := 0.0
var _speed := 0.0
var _state: int = State.IDLE
var _state_t := 0.0
var _anim_scale := 1.0
var _frozen := false

# 导航
var _wp: Array = []
var _wp_i := 0
var _seg_y := 0.0
var _at_node := ""
var _arrived := false

# 当前活动
var _act: Dictionary = {}
var _hold_t := 0.0
var _idle_mode := ""
var _idle_dur := 0.0
var _replan := false
var _wake_request := false
var _door_npc := false

# 过渡
var _tr_from := Vector3.ZERO
var _tr_from_yaw := 0.0
var _tr_to := Vector3.ZERO
var _tr_to_yaw := 0.0
var _tr_dur := 0.0

# 时间
var _sim_now := 0.0
var _last_sim := -1.0
var _last_time_jump := 0.0
var _win_check_t := 0.0
var _window_id := ""
var _window_kind := ""
var _rng := RandomNumberGenerator.new()

# 外部注入
var _door_set := Callable()
var _ctx: Dictionary = {}


# =============================================================================
# 构建
# =============================================================================
static func build(parent: Node3D, cottage: Dictionary, vseed: int = 7) -> Node3D:
	var script := load("res://scripts/isle_villager.gd") as GDScript
	var v: Node3D = script.new()
	v.name = "Islander"
	v.set_meta("island_villager", true)
	v.set_meta("no_batch", true)
	parent.add_child(v)
	v.call("setup", cottage, vseed)
	return v


func setup(cottage: Dictionary, vseed: int = 7) -> void:
	_rng.seed = vseed
	graph = SpotScript.build(cottage)
	schedule = ScheduleScript.new(vseed)
	model = ModelScript.create(0)
	model_root = model["root"] as Node3D
	add_child(model_root)
	anim = model["anim"] as AnimationPlayer
	hair_style = int(model.get("hair_style", 0))
	var spawn_node := "deck"
	if not (graph.get("nodes", {}) as Dictionary).has(spawn_node):
		var keys := (graph.get("nodes", {}) as Dictionary).keys()
		spawn_node = String(keys[0]) if not keys.is_empty() else ""
	if spawn_node != "":
		var sn: Dictionary = (graph["nodes"] as Dictionary)[spawn_node]
		_pos = sn["pos"] as Vector3
		_at_node = spawn_node
		_yaw = _yaw_face(Vector3(0.0, 0.0, -1.0))
	# 初始面朝岛内/海景：站在门廊上朝外
	_yaw = _yaw_face(Vector3(0.0, 0.0, 1.0))
	apply_pose()
	stats = ModelScript.measure(model_root, {"include_hidden": false})
	_play(&"idle", 0.0)
	_set_state(State.IDLE)
	_idle_mode = "cooldown"
	_idle_dur = 0.6
	_log("built: spawn=%s pos=%s nodes=%d spots=%d" % [spawn_node, str(_pos), (graph["nodes"] as Dictionary).size(), (graph["spots"] as Dictionary).size()])


# =============================================================================
# 每帧（由 main.gd 在 _update_lighting() 之后调用；frozen 时冻结动画与逻辑）
# =============================================================================
func sim_tick(delta: float, ctx: Dictionary) -> void:
	_ctx = ctx
	door_callable(ctx)
	var sim_now := float(ctx.get("sim_seconds", _sim_now))
	var frozen := bool(ctx.get("frozen", false))
	_frozen = frozen
	if frozen:
		# 暂停/菜单：冻结动画与逻辑；仍记录权威时间，恢复时不会误判成时间跳转。
		anim.speed_scale = 0.0
		_last_sim = sim_now
		_last_time_jump = float(ctx.get("time_jump", _last_time_jump))
		_sim_now = sim_now
		return
	_detect_jump(sim_now)
	_sim_now = sim_now
	anim.speed_scale = _anim_scale
	var dt := minf(delta, 0.10)
	_update_window(dt, ctx)
	_dispatch(dt)
	_update_door()


func door_callable(ctx: Dictionary) -> void:
	var cb: Variant = ctx.get("door_set", null)
	if cb is Callable:
		_door_set = cb as Callable


## 跳时检测只看"权威世界时间相对上一帧的推进"与 main 注入的 sim_delta 期望值之差：
## 船/灯塔会消费并把 _time_jump 清零，若直接用其变化会产生误判，因此这里不依赖 _time_jump。
func _detect_jump(sim_now: float) -> void:
	var jump := false
	var backward := false
	if _last_sim >= 0.0:
		var rate := maxf(float(_ctx.get("sim_rate", 144.0)), 0.001)
		var sd := float(_ctx.get("sim_delta", 0.0))
		var guard := maxf(60.0, rate * 0.10)
		var expected := _last_sim + sd
		if absf(sim_now - expected) > guard:
			jump = true
			backward = sim_now < _last_sim
	_last_time_jump = float(_ctx.get("time_jump", _last_time_jump))
	if jump:
		_on_time_jump(backward)
	_last_sim = sim_now


func _on_time_jump(backward: bool) -> void:
	if schedule != null:
		(schedule as RefCounted).call("note_jump", backward)
	_log("time jump backward=%s state=%s" % [str(backward), state_name()])
	_replan = true
	match _state:
		State.WALK:
			_abort_walk()
		State.SIT, State.EAT:
			_hold_t = maxf(_hold_t, activity_dur())
		State.SLEEP:
			_wake_request = true
		State.IDLE:
			_state_t = maxf(_state_t, _idle_dur)
		_:
			pass


func _update_window(dt: float, ctx: Dictionary) -> void:
	_win_check_t += dt
	if _win_check_t < WINDOW_CHECK_PERIOD:
		return
	_win_check_t = 0.0
	var events: Dictionary = ctx.get("events", {})
	var w: Dictionary = ScheduleScript.window_for(_sim_now, events)
	var wid := String(w.get("id", ""))
	var wkind := String(w.get("kind", ""))
	if wid == _window_id:
		return
	_window_id = wid
	_window_kind = wkind
	# 稳定优先：只有睡眠在窗口结束时自然醒来；普通活动不因窗口切换而中断（避免闪烁）。
	if _state == State.SLEEP and wkind != "sleep":
		_wake_request = true
		_log("dawn wake: window=%s" % wid)


# =============================================================================
# 状态分派
# =============================================================================
func _dispatch(dt: float) -> void:
	_state_t += dt
	# 活动真实时间预算（散步/观景的超时判定依赖它；不参与世界时间选择）
	if not _act.is_empty() and not _forced_mode():
		_act["used"] = float(_act.get("used", 0.0)) + dt
		if _state == State.WALK:
			_act["walk_time"] = float(_act.get("walk_time", 0.0)) + dt
	if _state == State.WALK:
		_walk_step(dt)
		return
	if _state == State.IDLE:
		_hold_t += dt
		_tick_idle(dt)
		return
	if _state == State.SIT_IN:
		_tick_sit_in(dt)
		return
	if _state == State.SIT or _state == State.EAT:
		_hold_t += dt
		_tick_seated(dt)
		return
	if _state == State.SIT_OUT:
		_tick_sit_out(dt)
		return
	if _state == State.BED_IN:
		_tick_bed_in(dt)
		return
	if _state == State.LIE_IN:
		_tick_lie_in(dt)
		return
	if _state == State.SLEEP:
		_hold_t += dt
		_tick_sleep(dt)
		return
	if _state == State.LIE_OUT:
		_tick_lie_out(dt)
		return
	if _state == State.BED_OUT:
		_tick_bed_out(dt)
		return


func _set_state(s: int) -> void:
	_state = s
	_state_t = 0.0
	_speed = 0.0
	if s == State.WALK:
		_arrived = false
	_anim_scale = 1.0
	anim.speed_scale = _anim_scale


# =============================================================================
# IDLE
# =============================================================================
func _tick_idle(_dt: float) -> void:
	if _replan:
		_replan = false
		_finish_to_decision()
		return
	if _state_t < _idle_dur:
		return
	match _idle_mode:
		"watch":
			_stroll_next_step()
		"cooldown":
			_finish_to_decision()
		_:
			_finish_activity("idle done")


func _play_idle() -> void:
	var clip := &"idle"
	if _rng.randf() < 0.5:
		clip = &"idle_alt"
	_play(clip, 0.22)


# =============================================================================
# WALK
# =============================================================================
func _abort_walk() -> void:
	_wp.clear()
	_wp_i = 0
	_speed = 0.0
	_play_idle()
	_set_state(State.IDLE)
	_idle_mode = "cooldown"
	_idle_dur = DECISION_COOLDOWN
	_replan = false


func _walk_step(dt: float) -> void:
	if _wp.is_empty() or _wp_i >= _wp.size():
		_on_arrive()
		return
	var target: Vector3 = (_wp[_wp_i] as Dictionary)["pos"]
	var dx := target.x - _pos.x
	var dz := target.z - _pos.z
	var horiz := sqrt(dx * dx + dz * dz)
	if horiz <= ARRIVE_EPS:
		_pos = Vector3(target.x, target.y, target.z)
		var node_id := String((_wp[_wp_i] as Dictionary).get("node", ""))
		if node_id != "":
			_at_node = node_id
		_wp_i += 1
		_seg_y = target.y
		apply_pose()
		if _wp_i >= _wp.size():
			_on_arrive()
			return
		# 重新计算下一段
		var nt: Vector3 = (_wp[_wp_i] as Dictionary)["pos"]
		dx = nt.x - _pos.x
		dz = nt.z - _pos.z
		horiz = sqrt(dx * dx + dz * dz)
		if horiz <= 0.0001:
			return
	var dir := Vector3(dx / horiz, 0.0, dz / horiz)
	var want_yaw := _yaw_face(dir)
	_yaw = _turn_towards(_yaw, want_yaw, dt)
	var forward := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var align := maxf(BLEND_TURN_SPEED, forward.dot(dir))
	var remaining := _remaining_dist()
	var want_speed := WALK_SPEED * align
	if remaining < DECEL_DIST:
		want_speed = maxf(MIN_WALK_SPEED, WALK_SPEED * (remaining / DECEL_DIST))
	_speed = move_toward(_speed, want_speed, (WALK_ACCEL if want_speed > _speed else WALK_DECEL) * dt)
	var step := minf(_speed * dt, horiz)
	_pos.x += dir.x * step
	_pos.z += dir.z * step
	# 竖直方向按段内剩余比例插值（楼梯 tread 顶面之间为坡面）
	var frac := clampf((horiz - step) / maxf(horiz, 0.0001), 0.0, 1.0)
	_pos.y = lerpf(target.y, _seg_y, frac)
	apply_pose()
	var clip_len := float((ModelScript.ANIMATIONS as Dictionary)[&"walk"]["length"])
	var stride := float(ModelScript.WALK_STRIDE)
	_anim_scale = clampf(_speed * clip_len / stride, 0.35, 1.8)
	_play(&"walk", 0.16)


func _remaining_dist() -> float:
	if _wp.is_empty() or _wp_i >= _wp.size():
		return 0.0
	var t: Vector3 = (_wp[_wp_i] as Dictionary)["pos"]
	var d := Vector2(t.x - _pos.x, t.z - _pos.z).length()
	for i in range(_wp_i + 1, _wp.size()):
		var a: Vector3 = (_wp[i - 1] as Dictionary)["pos"]
		var b: Vector3 = (_wp[i] as Dictionary)["pos"]
		d += Vector2(b.x - a.x, b.z - a.z).length()
	return d


func _on_arrive() -> void:
	if _wp_i < _wp.size():
		var node_id := String((_wp[_wp_i] as Dictionary).get("node", ""))
		if node_id != "":
			_at_node = node_id
	_wp.clear()
	_wp_i = 0
	_speed = 0.0
	var kind := String(_act.get("kind", "idle"))
	match kind:
		"sleep":
			_begin_bed_in()
		"eat":
			_begin_sit_in(true)
		"sit":
			_begin_sit_in(false)
		"forced_walk":
			_face_activity_yaw()
			_play_idle()
			_set_state(State.IDLE)
			_idle_mode = "hold"
			_idle_dur = 1.0e9
		"stroll":
			_begin_watch()
		_:
			_face_activity_yaw()
			_play_idle()
			_set_state(State.IDLE)
			_idle_mode = "activity"
			_idle_dur = maxf(0.2, activity_dur())


func _face_activity_yaw() -> void:
	var wy := float(_act.get("yaw", _yaw))
	_yaw = wy
	apply_pose()


# =============================================================================
# 坐下 / 进食
# =============================================================================
func _begin_sit_in(do_eat: bool) -> void:
	var spot: Dictionary = _act.get("spot", {})
	if spot.is_empty():
		_finish_activity("missing spot")
		return
	var anchor: Vector3 = spot["anchor"]
	_tr_from = _pos
	_tr_from_yaw = _yaw
	_tr_to = anchor + Vector3(0.0, SIT_ROOT_OFFSET, 0.0)
	_tr_to_yaw = float(spot["yaw"])
	_tr_dur = float((ModelScript.ANIMATIONS as Dictionary)[&"sit_down"]["length"])
	_play(&"sit_down", 0.12)
	_set_state(State.SIT_IN)
	_act["eat_after"] = do_eat


func _tick_sit_in(_dt: float) -> void:
	var p := clampf(_state_t / maxf(_tr_dur, 0.001), 0.0, 1.0)
	var e := smoothstep(0.0, 1.0, p)
	_pos = _tr_from.lerp(_tr_to, e)
	_yaw = lerp_angle(_tr_from_yaw, _tr_to_yaw, e)
	apply_pose()
	if p >= 1.0:
		_pos = _tr_to
		_yaw = _tr_to_yaw
		apply_pose()
		if bool(_act.get("eat_after", false)):
			_play(&"eat", 0.10)
			_set_state(State.EAT)
		else:
			_play(&"sit_idle", 0.10)
			_set_state(State.SIT)
		_hold_t = 0.0


func _tick_seated(_dt: float) -> void:
	if _replan:
		_replan = false
		_begin_sit_out()
		return
	if _hold_t >= activity_dur():
		_begin_sit_out()


func _begin_sit_out() -> void:
	var spot: Dictionary = _act.get("spot", {})
	var approach: Vector3 = _act.get("approach", _pos)
	_tr_from = _pos
	_tr_from_yaw = _yaw
	_tr_to = approach
	_tr_to_yaw = float(_act.get("approach_yaw", _yaw))
	_tr_dur = float((ModelScript.ANIMATIONS as Dictionary)[&"sit_up"]["length"])
	_play(&"sit_up", 0.10)
	_set_state(State.SIT_OUT)


func _tick_sit_out(_dt: float) -> void:
	var p := clampf(_state_t / maxf(_tr_dur, 0.001), 0.0, 1.0)
	var e := smoothstep(0.0, 1.0, p)
	_pos = _tr_from.lerp(_tr_to, e)
	_yaw = lerp_angle(_tr_from_yaw, _tr_to_yaw, e)
	apply_pose()
	if p >= 1.0:
		_pos = _tr_to
		release_spot()
		_play_idle()
		_set_state(State.IDLE)
		_idle_mode = "cooldown"
		_idle_dur = DECISION_COOLDOWN
		_hold_t = 0.0


# =============================================================================
# 床：坐床沿 → 躺下 → 睡眠 → 起身
# =============================================================================
func _begin_bed_in() -> void:
	var spot: Dictionary = _act.get("spot", {})
	if spot.is_empty():
		_finish_activity("missing bed")
		return
	var edge : Vector3 = spot["anchor_edge"]
	var anchor: Vector3 = spot["anchor"]
	var inward := anchor - edge
	inward.y = 0.0
	if inward.length() > 0.001:
		inward = inward.normalized()
	var edge_root := edge + inward * BED_EDGE_INSET + Vector3(0.0, BED_EDGE_ROOT_OFFSET, 0.0)
	_tr_from = _pos
	_tr_from_yaw = _yaw
	_tr_to = edge_root
	_tr_to_yaw = float(spot.get("sit_yaw", _yaw))
	_tr_dur = float((ModelScript.ANIMATIONS as Dictionary)[&"bed_sit_down"]["length"])
	_play(&"bed_sit_down", 0.10)
	_set_state(State.BED_IN)


func _tick_bed_in(_dt: float) -> void:
	var p := clampf(_state_t / maxf(_tr_dur, 0.001), 0.0, 1.0)
	var e := smoothstep(0.0, 1.0, p)
	_pos = _tr_from.lerp(_tr_to, e)
	_yaw = lerp_angle(_tr_from_yaw, _tr_to_yaw, e)
	apply_pose()
	if p >= 1.0:
		_pos = _tr_to
		_yaw = _tr_to_yaw
		_begin_lie_in()


func _begin_lie_in() -> void:
	var spot: Dictionary = _act.get("spot", {})
	var anchor: Vector3 = spot["anchor"]
	_tr_from = _pos
	_tr_from_yaw = _yaw
	_tr_to = anchor + Vector3(0.0, BED_LIE_ROOT_OFFSET, 0.0)
	_tr_to_yaw = float(spot["yaw"])
	_tr_dur = float((ModelScript.ANIMATIONS as Dictionary)[&"lie_down"]["length"])
	_play(&"lie_down", 0.10)
	_set_state(State.LIE_IN)


func _tick_lie_in(_dt: float) -> void:
	var p := clampf(_state_t / maxf(_tr_dur, 0.001), 0.0, 1.0)
	var e := smoothstep(0.0, 1.0, p)
	_pos = _tr_from.lerp(_tr_to, e)
	_yaw = lerp_angle(_tr_from_yaw, _tr_to_yaw, e)
	apply_pose()
	if p >= 1.0:
		_pos = _tr_to
		_yaw = _tr_to_yaw
		_play(&"sleep", 0.15)
		_set_state(State.SLEEP)
		_hold_t = 0.0
		_wake_request = false
		_log("sleeping at bed")


func _tick_sleep(_dt: float) -> void:
	if _replan:
		_replan = false
		_begin_lie_out()
		return
	if _wake_request or _hold_t >= activity_dur():
		_wake_request = false
		_begin_lie_out()


func _begin_lie_out() -> void:
	var spot: Dictionary = _act.get("spot", {})
	var edge: Vector3 = spot["anchor_edge"]
	var anchor: Vector3 = spot["anchor"]
	var inward := anchor - edge
	inward.y = 0.0
	if inward.length() > 0.001:
		inward = inward.normalized()
	var edge_root := edge + inward * BED_EDGE_INSET + Vector3(0.0, BED_EDGE_ROOT_OFFSET, 0.0)
	_tr_from = _pos
	_tr_from_yaw = _yaw
	_tr_to = edge_root
	_tr_to_yaw = float(spot.get("sit_yaw", _yaw))
	_tr_dur = float((ModelScript.ANIMATIONS as Dictionary)[&"lie_down"]["length"])
	anim.play_backwards(&"lie_down", 0.12)
	_anim_scale = 1.0
	_set_state(State.LIE_OUT)


func _tick_lie_out(_dt: float) -> void:
	var p := clampf(_state_t / maxf(_tr_dur, 0.001), 0.0, 1.0)
	var e := smoothstep(0.0, 1.0, p)
	_pos = _tr_from.lerp(_tr_to, e)
	_yaw = lerp_angle(_tr_from_yaw, _tr_to_yaw, e)
	apply_pose()
	if p >= 1.0:
		_pos = _tr_to
		_yaw = _tr_to_yaw
		_begin_bed_out()


func _begin_bed_out() -> void:
	var approach: Vector3 = _act.get("approach", _pos)
	_tr_from = _pos
	_tr_from_yaw = _yaw
	_tr_to = approach
	_tr_to_yaw = float(_act.get("approach_yaw", _yaw))
	_tr_dur = float((ModelScript.ANIMATIONS as Dictionary)[&"bed_sit_up"]["length"])
	_play(&"bed_sit_up", 0.10)
	_set_state(State.BED_OUT)


func _tick_bed_out(_dt: float) -> void:
	var p := clampf(_state_t / maxf(_tr_dur, 0.001), 0.0, 1.0)
	var e := smoothstep(0.0, 1.0, p)
	_pos = _tr_from.lerp(_tr_to, e)
	_yaw = lerp_angle(_tr_from_yaw, _tr_to_yaw, e)
	apply_pose()
	if p >= 1.0:
		_pos = _tr_to
		release_spot()
		_play_idle()
		_set_state(State.IDLE)
		_idle_mode = "cooldown"
		_idle_dur = DECISION_COOLDOWN
		_log("woke up at bed")


# =============================================================================
# 散步 / 观景
# =============================================================================
func _begin_watch() -> void:
	var node_id := String(_act.get("node_id", ""))
	var yaw := float(_act.get("yaw", _yaw))
	# 若目标节点同时是观景点，面向观景方向
	for sid in (graph["spots"] as Dictionary).keys():
		var sp: Dictionary = (graph["spots"] as Dictionary)[sid]
		if String(sp.get("kind", "")) != "view":
			continue
		if String(sp.get("approach_node", "")) == node_id:
			yaw = float(sp["yaw"])
			break
	_yaw = yaw
	apply_pose()
	_play_idle()
	_set_state(State.IDLE)
	_idle_mode = "watch"
	_idle_dur = _rng.randf_range(2.4, 4.6)


func _stroll_next_step() -> void:
	var budget := float(_act.get("dur", 10.0))
	if _state_t_budget_used() >= budget:
		_finish_activity("stroll done")
		return
	if _rt_walk_time() >= budget:
		_finish_activity("stroll done")
		return
	_target_stroll(true)


func _state_t_budget_used() -> float:
	return float(_act.get("used", 0.0))


func _rt_walk_time() -> float:
	return float(_act.get("walk_time", 0.0))


# =============================================================================
# 活动决策
# =============================================================================
func _finish_to_decision() -> void:
	if String(_act.get("kind", "")) == "" or _forced_mode():
		_choose_activity()
		return
	_finish_activity("done")


func _finish_activity(reason: String) -> void:
	var kind := String(_act.get("kind", ""))
	var spot_id := String(_act.get("spot_id", ""))
	if spot_id != "":
		release_spot()
	if kind != "" and schedule != null and spot_id != "":
		(schedule as RefCounted).call("note_finished", kind, spot_id, _sim_now)
	_log("finish %s (%s) at sim=%.0f" % [kind, reason, _sim_now])
	_act = {}
	_hold_t = 0.0
	if _forced_mode():
		_play_idle()
		_set_state(State.IDLE)
		_idle_mode = "hold"
		_idle_dur = 1.0e9
		return
	_set_state(State.IDLE)
	_idle_mode = "cooldown"
	_idle_dur = DECISION_COOLDOWN
	_play_idle()


func _choose_activity() -> void:
	if _forced_mode():
		return
	if schedule == null:
		return
	if spot_reserved():
		release_spot()
	var sim_now := _sim_now
	var events: Dictionary = _ctx.get("events", {})
	var c: Dictionary = (schedule as RefCounted).call("choose", {
		"sim_seconds": sim_now,
		"sim_rate": float(_ctx.get("sim_rate", 144.0)),
		"sun_alt": float(_ctx.get("sun_alt", 30.0)),
		"events": events,
		# P8 阶段 7：天气只作为额外过滤条件传给日程，不建立第二份天气状态。
		"weather": _ctx.get("weather", {}),
	})
	var kind := String(c.get("kind", "idle"))
	_act = {
		"kind": kind,
		"dur": float(c.get("duration_real", 8.0)),
		"window_id": String(c.get("window_id", "")),
		"region_pref": String(c.get("region_pref", "any")),
		"reason": String(c.get("reason", "")),
		"used": 0.0,
		"walk_time": 0.0,
	}
	_log("decide %s dur=%.1f pref=%s reason=%s" % [kind, float(_act["dur"]), String(_act["region_pref"]), String(_act["reason"])])
	match kind:
		"sleep":
			_target_bed()
		"eat":
			var sp := _pick_spot("eat")
			if sp.is_empty():
				sp = _pick_spot("sit")
				if not sp.is_empty():
					_act["kind"] = "sit"
			if not sp.is_empty():
				_target_spot(sp)
			else:
				_in_place_idle()
		"sit":
			var sp2 := _pick_spot("sit")
			if not sp2.is_empty():
				_target_spot(sp2)
			else:
				_in_place_idle()
		"stroll":
			_target_stroll(false)
		_:
			var vsp := _pick_spot("view")
			if not vsp.is_empty():
				_act["kind"] = "idle"
				_target_spot(vsp)
			else:
				_in_place_idle()


func _in_place_idle() -> void:
	_play_idle()
	_set_state(State.IDLE)
	_idle_mode = "activity"
	_idle_dur = maxf(1.0, float(_act.get("dur", 4.0)))
	_hold_t = 0.0


func _pick_spot(kind: String) -> Dictionary:
	var spots: Dictionary = graph.get("spots", {})
	var best: Dictionary = {}
	var best_score := -2.0
	var start := _best_start_node()
	var score_ctx := {
		"sim_seconds": _sim_now,
		"region_pref": String(_act.get("region_pref", "any")),
	}
	for sid in spots.keys():
		var sp: Dictionary = spots[sid]
		if String(sp.get("kind", "")) != kind:
			continue
		if bool(sp.get("reserved", false)):
			continue
		var node_id := String(sp.get("approach_node", ""))
		if node_id == "":
			continue
		var path := SpotScript.find_path(graph, start, node_id)
		if path.is_empty():
			continue
		var sc := float((schedule as RefCounted).call("score_spot", sp, kind, score_ctx))
		if sc > best_score:
			best_score = sc
			best = sp
	return best


func _target_spot(sp: Dictionary) -> void:
	_act["spot"] = sp
	_act["spot_id"] = String(sp.get("id", ""))
	_act["approach"] = sp.get("approach", _pos)
	_act["approach_yaw"] = float(sp.get("approach_yaw", 0.0))
	sp["reserved"] = true
	var node_id := String(sp.get("approach_node", ""))
	var goal: Vector3 = sp.get("approach", _pos)
	if not _plan_path(node_id, goal, _act["approach_yaw"]):
		sp["reserved"] = false
		_act["spot"] = {}
		_act["spot_id"] = ""
		_log("path failed -> spot %s" % String(sp.get("id", "")))
		_in_place_idle()
		return
	_play(&"walk", 0.2)
	_set_state(State.WALK)


func _target_bed() -> void:
	var spots: Dictionary = graph.get("spots", {})
	var bed: Dictionary = {}
	for sid in spots.keys():
		var sp: Dictionary = spots[sid]
		if String(sp.get("kind", "")) == "bed":
			bed = sp
			break
	if bed.is_empty():
		_in_place_idle()
		return
	_act["spot"] = bed
	_act["spot_id"] = String(bed.get("id", ""))
	_act["approach"] = bed.get("approach", _pos)
	_act["approach_yaw"] = float(bed.get("approach_yaw", 0.0))
	bed["reserved"] = true
	if not _plan_path(String(bed.get("approach_node", "")), bed["approach"], _act["approach_yaw"]):
		bed["reserved"] = false
		_act["spot"] = {}
		_act["spot_id"] = ""
		_log("path to bed failed")
		_in_place_idle()
		return
	_play(&"walk", 0.2)
	_set_state(State.WALK)


func _target_stroll(_next: bool) -> void:
	var node_id := _pick_stroll_node()
	if node_id == "":
		_in_place_idle()
		return
	_act["node_id"] = node_id
	if not _plan_path(node_id, (graph["nodes"] as Dictionary)[node_id]["pos"], 0.0):
		_log("stroll path failed -> %s" % node_id)
		_in_place_idle()
		return
	_play(&"walk", 0.2)
	_set_state(State.WALK)


func _pick_stroll_node() -> String:
	var nodes: Dictionary = graph.get("nodes", {})
	var pool: Array = []
	var pref := String(_act.get("region_pref", "any"))
	var cur_region := ""
	if _at_node != "" and nodes.has(_at_node):
		cur_region = String((nodes[_at_node] as Dictionary).get("region", ""))
	match pref:
		"outdoor":
			pool = ["front_path_1", "front_path_2", "garden_0", "garden_2", "garden_4", "garden_6", "garden_8", "garden_cross", "tree_view", "swing_view", "lawn"]
		"porch":
			pool = ["deck_out", "porch_bench_front", "front_path_1", "lawn"]
		"floor1":
			pool = ["hall", "mid", "south_mid", "east_top", "desk_front", "sofa_front"]
		"attic":
			pool = ["attic_1", "attic_2", "attic_3", "reading_front", "attic_exit", "bed_stand"]
		"indoor":
			if cur_region == "attic":
				pool = ["attic_1", "attic_2", "reading_front", "attic_exit"]
			else:
				pool = ["hall", "mid", "south_mid", "east_top", "desk_front", "sofa_front"]
		_:
			pool = ["hall", "mid", "deck_out", "lawn", "front_path_1", "garden_2"]
	var start := _best_start_node()
	var choices: Array = []
	for id in pool:
		var nid := String(id)
		if not nodes.has(nid):
			continue
		if nid == _at_node:
			continue
		if String(_act.get("node_id", "")) == nid:
			continue
		if SpotScript.find_path(graph, start, nid).is_empty():
			continue
		choices.append(nid)
	if choices.is_empty():
		return ""
	return String(choices[_rng.randi() % choices.size()])


# =============================================================================
# 路径
# =============================================================================
func _best_start_node() -> String:
	var nodes: Dictionary = graph.get("nodes", {})
	if _at_node != "" and nodes.has(_at_node):
		return _at_node
	var nid := String(SpotScript.nearest_node(graph, _pos, ""))
	return nid


## 规划到目标节点（末尾可附带一个精确点）。返回 false = 不可达。
func _plan_path(target_node: String, goal_point: Variant = null, _goal_yaw: float = 0.0) -> bool:
	var nodes: Dictionary = graph.get("nodes", {})
	if target_node == "" or not nodes.has(target_node):
		return false
	var start := _best_start_node()
	var ids: PackedStringArray = SpotScript.find_path(graph, start, target_node)
	if ids.is_empty():
		return false
	_wp.clear()
	_wp_i = 0
	for id in ids:
		var nid := String(id)
		if not nodes.has(nid):
			continue
		_wp.append({"pos": (nodes[nid] as Dictionary)["pos"], "node": nid})
	if _wp.is_empty():
		return false
	if goal_point != null:
		var gp: Vector3 = goal_point
		var last: Vector3 = (_wp[_wp.size() - 1] as Dictionary)["pos"]
		if Vector2(gp.x - last.x, gp.z - last.z).length() > 0.02:
			_wp.append({"pos": gp, "node": ""})
	_seg_y = _pos.y
	return true


# =============================================================================
# 动画工具
# =============================================================================
func _play(clip: StringName, blend: float = 0.15) -> void:
	if anim.current_animation == clip and anim.is_playing():
		return
	anim.play(clip, blend)
	_anim_scale = 1.0
	anim.speed_scale = 0.0 if _frozen else 1.0


func _apply_pose() -> void:
	position = _pos
	rotation.y = _yaw


func apply_pose() -> void:
	_apply_pose()


func _yaw_face(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


func _turn_towards(from_yaw: float, to_yaw: float, dt: float) -> float:
	var diff := wrapf(to_yaw - from_yaw, -PI, PI)
	var max_step := TURN_RATE * dt
	if absf(diff) <= max_step:
		return to_yaw
	return from_yaw + signf(diff) * max_step


# =============================================================================
# 活动点预订 / 释放
# =============================================================================
func release_spot() -> void:
	var sid := String(_act.get("spot_id", ""))
	if sid == "":
		return
	var spots: Dictionary = graph.get("spots", {})
	if spots.has(sid):
		(spots[sid] as Dictionary)["reserved"] = false


func activity_dur() -> float:
	return float(_act.get("dur", 8.0))


# =============================================================================
# 门（NPC 静默开关；玩家自己开关的门由 main 统一管理）
# =============================================================================
func _update_door() -> void:
	if _door_set.is_null():
		return
	var nodes: Dictionary = graph.get("nodes", {})
	if not nodes.has("door_sill"):
		return
	var ds: Vector3 = (nodes["door_sill"] as Dictionary)["pos"]
	var d := Vector2(_pos.x - ds.x, _pos.z - ds.z).length()
	# 只有"正在行走"才主动开门，避免坐着/站着时门被反复开合；走远后无论状态都释放请求。
	if _door_npc and d > DOOR_CLOSE_DIST:
		_door_npc = false
		_door_set.call(false)
	elif _state == State.WALK and not _door_npc and d < DOOR_OPEN_DIST:
		_door_npc = true
		_door_set.call(true)


# =============================================================================
# 调试/测试接口
# =============================================================================
func state_name() -> String:
	return ["IDLE", "WALK", "SIT_IN", "SIT", "EAT", "SIT_OUT", "BED_IN", "LIE_IN", "SLEEP", "LIE_OUT", "BED_OUT"][_state]


func debug_state() -> Dictionary:
	var reserved: Array = []
	var spots: Dictionary = graph.get("spots", {})
	for sid in spots.keys():
		if bool((spots[sid] as Dictionary).get("reserved", false)):
			reserved.append(String(sid))
	if schedule != null:
		_ctx["schedule"] = (schedule as RefCounted).call("debug_state")
	return {
		"state": state_name(),
		"kind": String(_act.get("kind", "")),
		"region": String(_act.get("region_pref", "")),
		"spot_id": String(_act.get("spot_id", "")),
		"act_dur": activity_dur(),
		"hold_t": _hold_t,
		"state_t": _state_t,
		"idle_mode": _idle_mode,
		"pos": _pos,
		"yaw": _yaw,
		"speed": _speed,
		"at_node": _at_node,
		"path": _wp.duplicate(),
		"path_i": _wp_i,
		"reserved": reserved,
		"window": _window_id,
		"sim_seconds": _sim_now,
		"time_jump": _last_time_jump,
		"forced": _forced_mode(),
		"clip": String(anim.current_animation) if anim != null else "",
		"clip_pos": anim.current_animation_position if anim != null else 0.0,
		"anim_scale": anim.speed_scale if anim != null else 0.0,
		"schedule": _ctx.get("schedule", {}),
		"stats": stats,
		"door_npc": _door_npc,
	}

# ---- 强制接口（仅供探针/测试，不进玩家 UI）----
var _force := ""

func _forced_mode() -> bool:
	return _force != ""


## 强制切换前丢弃当前活动（释放预约），避免调试/任务覆盖时永久锁住家具。
func _drop_activity() -> void:
	if spot_reserved():
		release_spot()
	_act = {}
	_hold_t = 0.0


func force_idle(dur: float = 6.0) -> void:
	_drop_activity()
	_force = "idle"
	_act = {"kind": "forced_idle", "dur": dur, "spot_id": ""}
	_play_idle()
	_set_state(State.IDLE)
	_idle_mode = "hold"
	_idle_dur = 1.0e9


func force_walk_to_node(node_id: String) -> bool:
	var nodes: Dictionary = graph.get("nodes", {})
	if not nodes.has(node_id):
		return false
	_drop_activity()
	_force = "walk"
	_act = {"kind": "forced_walk", "node_id": node_id, "dur": 1.0e9, "spot_id": "", "yaw": _yaw}
	if not _plan_path(node_id, (nodes[node_id] as Dictionary)["pos"], _yaw):
		_force = ""
		return false
	_play(&"walk", 0.2)
	_set_state(State.WALK)
	return true


func force_walk_to_point(p: Vector3) -> bool:
	var nid := String(SpotScript.nearest_node(graph, p, ""))
	if nid == "":
		return false
	_drop_activity()
	_force = "walk"
	_act = {"kind": "forced_walk", "node_id": nid, "dur": 1.0e9, "spot_id": "", "yaw": _yaw}
	if not _plan_path(nid, p, _yaw):
		_force = ""
		return false
	_play(&"walk", 0.2)
	_set_state(State.WALK)
	return true


func force_sit(spot_id: String = "") -> bool:
	var sp := _find_spot("sit", spot_id)
	if sp.is_empty():
		return false
	_drop_activity()
	_force = "sit"
	_act = {"kind": "sit", "dur": 12.0, "spot_id": "", "region_pref": "any"}
	_act["kind"] = "sit"
	_target_spot_for_force(sp, "sit")
	return true


func force_eat(spot_id: String = "") -> bool:
	var sp := _find_spot("eat", spot_id)
	if sp.is_empty():
		return false
	_drop_activity()
	_force = "eat"
	_act = {"kind": "eat", "dur": 12.0, "spot_id": "", "region_pref": "any"}
	_target_spot_for_force(sp, "eat")
	return true


func force_bed() -> bool:
	var spots: Dictionary = graph.get("spots", {})
	var bed: Dictionary = {}
	for sid in spots.keys():
		if String((spots[sid] as Dictionary).get("kind", "")) == "bed":
			bed = spots[sid]
			break
	if bed.is_empty():
		return false
	_drop_activity()
	_force = "bed"
	_act = {"kind": "sleep", "dur": 18.0, "spot_id": "", "region_pref": "attic"}
	_act["spot"] = bed
	_act["spot_id"] = String(bed.get("id", ""))
	_act["approach"] = bed.get("approach", _pos)
	_act["approach_yaw"] = float(bed.get("approach_yaw", 0.0))
	bed["reserved"] = true
	if not _plan_path(String(bed.get("approach_node", "")), bed["approach"], _act["approach_yaw"]):
		bed["reserved"] = false
		_force = ""
		_act = {}
		return false
	_play(&"walk", 0.2)
	_set_state(State.WALK)
	return true


func clear_force() -> void:
	_force = ""
	_replan = false
	if spot_reserved():
		release_spot()
	_act = {}
	_play_idle()
	_set_state(State.IDLE)
	_idle_mode = "cooldown"
	_idle_dur = 0.2


func _find_spot(kind: String, spot_id: String) -> Dictionary:
	var spots: Dictionary = graph.get("spots", {})
	if spot_id != "" and spots.has(spot_id):
		return spots[spot_id]
	var start := _best_start_node()
	var fallback: Dictionary = {}
	for sid in spots.keys():
		var sp: Dictionary = spots[sid]
		if String(sp.get("kind", "")) != kind:
			continue
		if bool(sp.get("reserved", false)):
			continue
		if SpotScript.find_path(graph, start, String(sp.get("approach_node", ""))).is_empty():
			continue
		fallback = sp
		break
	return fallback


func _target_spot_for_force(sp: Dictionary, kind: String) -> void:
	_act["kind"] = kind
	_act["spot"] = sp
	_act["spot_id"] = String(sp.get("id", ""))
	_act["approach"] = sp.get("approach", _pos)
	_act["approach_yaw"] = float(sp.get("approach_yaw", 0.0))
	sp["reserved"] = true
	if not _plan_path(String(sp.get("approach_node", "")), sp["approach"], _act["approach_yaw"]):
		sp["reserved"] = false
		_force = ""
		_act = {}
		_play_idle()
		_set_state(State.IDLE)
		_idle_mode = "cooldown"
		_idle_dur = 0.2
		return
	_play(&"walk", 0.2)
	_set_state(State.WALK)


func spot_reserved() -> bool:
	var sid := String(_act.get("spot_id", ""))
	if sid == "":
		return false
	var spots: Dictionary = graph.get("spots", {})
	return bool((spots.get(sid, {}) as Dictionary).get("reserved", false))


# ---- 外观 ----
func set_hair_style(style: int) -> bool:
	if model_root == null:
		return false
	model_root.call("set_hair_style", style)
	hair_style = style
	return true


func get_stats() -> Dictionary:
	if model_root != null:
		stats = ModelScript.measure(model_root, {"include_hidden": false})
	return stats


func _log(msg: String) -> void:
	if debug_log:
		print("[V4] villager: ", msg)
