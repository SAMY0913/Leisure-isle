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
const FishScript := preload("res://scripts/isle_fish.gd")

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
const BED_EDGE_INSET := 0.02       # 坐床沿时骨盆中心离床沿向内 0.02m（P9：旧值 0.12 让坐点内缩 0.27m，腿搁在床面）
const BED_EDGE_ROOT_OFFSET := 0.085 # 坐床沿 root(骨盆中心) = 床垫顶 + 0.085（骨盆网格底 -0.085 → 刚好坐上）
const BED_LIE_ROOT_OFFSET := 0.02  # 躺姿 root = 床垫顶 + 0.02（模型 _lie 约定）
const BED_LIE_FREEZE := 0.30       # 躺下链前 0.30s 冻结 root（先搬腿，再整个人平移上床）
const BED_UP_FREEZE := 0.30        # 起床链前 0.30s 冻结 root（先抬头撑起，再挪回床沿）

# ---- P9：秋千 / 观海（白天生活动作；不加新状态，复用 SIT/IDLE）----
const SWING_AMPLITUDE := 0.11      # 坐秋千时轻柔前后摆 ±6.3°（要求 5–10°，不与环境风叠加）
const SWING_PERIOD := 4.2          # 摆周期（真实秒）
const SWING_CALM_TIME := 0.9       # 走到秋千前把吊点摆角压到 0 的过渡时长
const SWING_RIDE_RAMP := 1.6       # 上座后摆幅从 0 渐入的时长
const SWING_RELEASE_TIME := 0.7    # 起身后把吊点控制权交还 main 的过渡时长
const SWING_SEAT_TOP_FALLBACK := 0.035  # 座椅 BoxMesh 半高（seat mesh AABB 不可读时）
const SEA_WATCH_ANIM_SCALE := 0.62 # 观海用慢速待机（轻缓观察动作）

# ---- 时间/调度 ----
const WINDOW_CHECK_PERIOD := 0.25  # 世界窗口检查间隔（秒，低成本）
const JUMP_GUARD_SIM := 180.0      # 兜底：单帧模拟时间跨度超过它视为跳时
const DECISION_COOLDOWN := 0.35    # 活动结束后到下一次决策的最短间隔

# ---- P4：农田巡田（主控在 08:00 调度时接管；天气中断则返回室内）----
const PATROL_DWELL := 0.6              # 每格处理后的可观察停留（真实帧时间，非世界时钟）
const PATROL_INDOOR_NODES := ["hall", "mid", "room_in"]  # 现有室内安全点（返回室内目标）

# ---- P6：岛民自主钓鱼（与 P4 巡田同一套"唯一活动意图"仲裁，不建第二套移动状态机）----
# 所有阶段时长均为"体感秒" = ctx.sim_delta / ctx.sim_rate；世界暂停时 sim_tick 直接冻结，
# 单帧推进量还有 FISH_FEEL_CAP 上限，所以一次时间跳变不可能瞬间连播多轮。
const FISH_WAIT_MIN := 6.0            # 普通等待咬钩（体感秒）
const FISH_WAIT_MAX := 16.0
const FISH_LONG_CHANCE := 0.18        # 偶发更长等待的比例
const FISH_WAIT_LONG_MIN := 18.0
const FISH_WAIT_LONG_MAX := 24.0
const FISH_NIBBLE_PRE := 1.6          # 咬钩前更清楚的试探提前量
const FISH_BITE_TIME := 0.8           # 咬钩反馈（浮漂下沉/水花）时长
const FISH_REVEAL_TIME := 1.5         # 鱼获展示时长
const FISH_BETWEEN_TIME := 1.0        # 两轮之间停顿
const FISH_FEEL_CAP := 0.25           # 单帧最多推进的体感秒（跳时保护）
const FISH_SPOT_EPS := 0.10           # 到达钓位判定（水平米）

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
# 当前路径段的水平总长：竖直方向按“本段行进比例”插值，避免陡坡路段到达节点时垂直跳变（P6 岸边下坡必需）。
var _seg_horiz := 0.0
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
# P9：弧线入座（椅背后方接近时绕开靠背）
var _tr_curve := false
var _tr_ctrl := Vector3.ZERO

# P9：秋千（由 main 注入真实吊点/座椅节点；未注入时 swing 活动自动回退）
var _swing_pivot: Node3D = null
var _swing_seat: Node3D = null
var _swing_parent_xf := Transform3D.IDENTITY
var _swing_parent_inv := Transform3D.IDENTITY
var _swing_pivot_local := Vector3.ZERO
var _swing_seat_local := Transform3D.IDENTITY
var _swing_seat_top := SWING_SEAT_TOP_FALLBACK
var _swing_ctrl := false
var _swing_phase := ""        # approach / ride / release
var _swing_t := 0.0
var _swing_theta := 0.0
var _swing_hold_theta := 0.0
# P9：进食碗（模型内置 Bowl，仅显示/隐藏，不产生/消耗共享库存）
var _bowl_on := false

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

# P4：巡田任务（空 = 无）。调度、天气与路线由 main 注入，本文件不建第二份时钟/天气状态。
var _patrol: Dictionary = {}
var _patrol_last: Dictionary = {}

# P6：钓鱼任务（空 = 无）。阶段计时用体感秒；鱼获入账由 main 注入的 Callable 完成。
var _fish: Dictionary = {}
var _fish_last: Dictionary = {}
var _fish_rig: Node3D = null
var _fish_commit := Callable()
var _fish_sfx := Callable()


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
		_fish_rig_tick(0.0)
		# P9：main 的秋千在暂停时仍由 _update_props 推进；坐在秋千上必须保持“贴座”，
		# 否则暂停期间吊点转动会把角色留在原地。这里只重投影 root，不推进状态机。
		_swing_hold_frozen()
		return
	_detect_jump(sim_now)
	_sim_now = sim_now
	anim.speed_scale = _anim_scale
	var dt := minf(delta, 0.10)
	_update_window(dt, ctx)
	_dispatch(dt)
	_swing_tick(dt)
	_update_door()
	_fish_rig_tick(dt)


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
	# P4：巡田不跨时间跳变继续；安全结束（不回滚已提交事务），交还普通调度。
	if not _patrol.is_empty():
		_patrol_finish("cancelled", "time_jump")
	# P6：钓鱼同理——跳时可能是大幅前进（例如跳到明天），不能让状态机瞬间补完多轮，
	# 因此直接结束本次钓鱼；已经提交的鱼获保留在共享库存里，不撤销、不重复。
	if not _fish.is_empty():
		_fish_finish("cancelled", "time_jump")
	if schedule != null:
		(schedule as RefCounted).call("note_jump", backward)
	_log("time jump backward=%s state=%s" % [str(backward), state_name()])
	_replan = true
	match _state:
		State.WALK:
			_abort_walk()
		State.SIT, State.EAT:
			_hold_t = maxf(_hold_t, activity_dur())
			_set_bowl(false)
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
	# P4：巡田期间接管移动/停留；普通活动使用计数不参与。
	if not _patrol.is_empty():
		_patrol_dispatch(dt)
		return
	# P6：钓鱼期间同样由钓鱼状态机接管移动/停留（与巡田互斥，二者不会同时非空）。
	if not _fish.is_empty():
		_fish_dispatch(dt)
		return
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
	if _seg_horiz <= 0.0001 and horiz > 0.0001:
		_seg_horiz = horiz
	if horiz <= ARRIVE_EPS:
		_pos = Vector3(target.x, target.y, target.z)
		var node_id := String((_wp[_wp_i] as Dictionary).get("node", ""))
		if node_id != "":
			_at_node = node_id
		_wp_i += 1
		_seg_y = target.y
		_seg_horiz = 0.0
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
		_seg_horiz = horiz
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
	# 竖直方向按本段已行进比例插值（楼梯 tread 顶面之间为坡面）；
	# 分母用本段总长而不是当前剩余距离，否则陡坡会长时间悬空、到点瞬间垂直跳变。
	var frac := clampf((horiz - step) / maxf(_seg_horiz, 0.0001), 0.0, 1.0)
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
	# P4：巡田到点后由巡田状态机处理（先确认到达，再读权威农田状态）。
	if not _patrol.is_empty():
		_on_patrol_arrive()
		return
	# P6：钓鱼到点后由钓鱼状态机确认钓位，再开始抛竿。
	if not _fish.is_empty():
		_fish_arrive()
		return
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
		"swing":
			# P9：坐秋千复用坐姿状态机；未注入秋千节点时降级为普通观景待机
			if swing_ready():
				_begin_sit_in(false)
			else:
				_face_activity_yaw()
				_play_idle()
				_set_state(State.IDLE)
				_idle_mode = "activity"
				_idle_dur = maxf(0.2, activity_dur())
		"sea_view":
			# P9：码头观海 —— 真实到达、面向海面，用慢速 idle_alt 做“轻缓观察”（呼吸/点头/眨眼）
			_face_activity_yaw()
			_play(&"idle_alt", 0.15)
			_set_state(State.IDLE)
			_idle_mode = "activity"
			_idle_dur = maxf(0.2, activity_dur())
			_anim_scale = SEA_WATCH_ANIM_SCALE
			anim.speed_scale = 0.0 if _frozen else SEA_WATCH_ANIM_SCALE
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
	_tr_curve = false
	_tr_from = _pos
	_tr_from_yaw = _yaw
	_tr_to = anchor + Vector3(0.0, SIT_ROOT_OFFSET, 0.0)
	_tr_to_yaw = float(spot["yaw"])
	_tr_dur = float((ModelScript.ANIMATIONS as Dictionary)[&"sit_down"]["length"])
	# P9 / P7-FINALIZE：从椅背后方接近的椅子（餐椅/扶手椅/书桌椅）不再直线穿过靠背，
	# 改走一条侧向弧线：先绕到椅子侧面，再落座（入座方向由两侧障碍物最少的一侧决定）。
	if String(spot.get("approach_side", "front")) == "back":
		var facing := Vector3(-sin(_tr_to_yaw), 0.0, -cos(_tr_to_yaw))
		var right := facing.cross(Vector3.UP)
		var sgn := _pick_sit_side(spot, _tr_to, facing, right)
		_tr_ctrl = _tr_to - facing * 0.42 + right * (0.50 * sgn) + Vector3(0.0, 0.10, 0.0)
		_tr_curve = true
	_play(&"sit_down", 0.12)
	_set_state(State.SIT_IN)
	_act["eat_after"] = do_eat
	if do_eat:
		_set_bowl(true)   # 就位即显示桌上碗（退出/接管统一隐藏，不扣共享库存）
	if String(_act.get("kind", "")) == "swing":
		_swing_begin_approach()


## 两侧入座弧线各自的障碍采样（排除目标座椅自身footprint），返回碰撞样本数。
func _sit_arc_hits(spot: Dictionary, p0: Vector3, p1: Vector3, ctrl: Vector3) -> int:
	var root := _graph_house()
	if root == null:
		return 0
	var level := int(spot.get("level", 0))
	var seat_local := root.to_local(p1)
	var hits := 0
	for i in range(3, 9):
		var t := float(i) / 9.0
		var p := _quad_bezier(p0, ctrl, p1, t)
		var lp := root.to_local(p)
		for o in (graph.get("obstacles", []) as Array):
			if int(o[5]) != level:
				continue
			var ox := float(o[1])
			var oz := float(o[2])
			# 跳过目标座椅自身（座椅中心附近 0.55 m 内的 footprint）
			if Vector2(ox - seat_local.x, oz - seat_local.z).length() < 0.55:
				continue
			if absf(lp.x - ox) < float(o[3]) + 0.10 and absf(lp.z - oz) < float(o[4]) + 0.10:
				hits += 1
				break
	return hits


func _pick_sit_side(spot: Dictionary, seat: Vector3, facing: Vector3, right: Vector3) -> float:
	var ctrl_a := seat - facing * 0.42 + right * 0.50 + Vector3(0.0, 0.10, 0.0)
	var ctrl_b := seat - facing * 0.42 - right * 0.50 + Vector3(0.0, 0.10, 0.0)
	var hits_a := _sit_arc_hits(spot, _pos, seat, ctrl_a)
	var hits_b := _sit_arc_hits(spot, _pos, seat, ctrl_b)
	if hits_a != hits_b:
		return 1.0 if hits_a < hits_b else -1.0
	return 1.0


func _quad_bezier(p0: Vector3, p1: Vector3, p2: Vector3, t: float) -> Vector3:
	var u := 1.0 - t
	return p0 * (u * u) + p1 * (2.0 * u * t) + p2 * (t * t)


func _tick_sit_in(_dt: float) -> void:
	var p := clampf(_state_t / maxf(_tr_dur, 0.001), 0.0, 1.0)
	var e := smoothstep(0.0, 1.0, p)
	if String(_act.get("kind", "")) == "swing":
		_tick_swing_in(p, e)
		return
	if _tr_curve:
		_pos = _quad_bezier(_tr_from, _tr_ctrl, _tr_to, e)
	else:
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


func _tick_swing_in(p: float, e: float) -> void:
	var spot: Dictionary = _act.get("spot", {})
	var target := _swing_root_pos()
	_pos = _tr_from.lerp(target, e)
	_yaw = lerp_angle(_tr_from_yaw, float(spot.get("sit_yaw", spot.get("yaw", 0.0))), e)
	var tilt := _swing_theta * e
	position = _pos
	rotation = Vector3(tilt, _yaw, 0.0)
	if p >= 1.0:
		_pos = target
		_yaw = float(spot.get("sit_yaw", spot.get("yaw", 0.0)))
		_swing_theta = 0.0
		_swing_phase = "ride"
		_swing_t = 0.0
		_apply_swing_ride(0.0)
		_play(&"sit_idle", 0.12)
		_set_state(State.SIT)
		_hold_t = 0.0


func _tick_seated(_dt: float) -> void:
	if _replan:
		_replan = false
		_begin_sit_out()
		return
	# P9：进食循环不再每次逐字重复 3 s —— 每轮循环轻微变速（1.0 / 0.92 / 1.06），
	# 配合剪辑内部两口不同节奏，长时段读起来不是机械轮播。
	if _state == State.EAT:
		var eat_len := float((ModelScript.ANIMATIONS as Dictionary)[&"eat"]["length"])
		var loop_i := int(_hold_t / maxf(eat_len, 0.1))
		var speed_tab := [1.0, 0.92, 1.06]
		var sc := float(speed_tab[loop_i % speed_tab.size()])
		_anim_scale = sc
		anim.speed_scale = 0.0 if _frozen else sc
	if _hold_t >= activity_dur():
		_begin_sit_out()


func _begin_sit_out() -> void:
	_set_bowl(false)   # 起身/接管立即收起桌上碗
	var spot: Dictionary = _act.get("spot", {})
	var approach: Vector3 = _act.get("approach", _pos)
	_tr_from = _pos
	_tr_from_yaw = _yaw
	_tr_to = approach
	_tr_to_yaw = float(_act.get("approach_yaw", _yaw))
	_tr_dur = float((ModelScript.ANIMATIONS as Dictionary)[&"sit_up"]["length"])
	if String(_act.get("kind", "")) == "swing":
		_swing_begin_release()
		_play(&"sit_up", 0.10)
		_set_state(State.SIT_OUT)
		return
	_play(&"sit_up", 0.10)
	_set_state(State.SIT_OUT)


func _tick_sit_out(_dt: float) -> void:
	var p := clampf(_state_t / maxf(_tr_dur, 0.001), 0.0, 1.0)
	var e := smoothstep(0.0, 1.0, p)
	_pos = _tr_from.lerp(_tr_to, e)
	_yaw = lerp_angle(_tr_from_yaw, _tr_to_yaw, e)
	if String(_act.get("kind", "")) == "swing":
		# 起身时身体随秋千角一起回正（lerp 到 0），root 从座面滑向站位
		_swing_theta = lerpf(_swing_hold_theta, 0.0, e)
		position = _pos
		rotation = Vector3(_swing_theta, _yaw, 0.0)
	else:
		apply_pose()
	if p >= 1.0:
		_pos = _tr_to
		_yaw = _tr_to_yaw
		rotation = Vector3(0.0, _yaw, 0.0)
		apply_pose()
		_swing_end_control()
		release_spot()
		_play_idle()
		_set_state(State.IDLE)
		_idle_mode = "cooldown"
		_idle_dur = DECISION_COOLDOWN
		_hold_t = 0.0


# =============================================================================
# 床：坐床沿 → 躺下 → 睡眠 → 起身
# =============================================================================
func _bed_inward(spot: Dictionary) -> Vector3:
	# 床的“由床沿指向床心”方向由 spots 提供（躺姿锚点已不在法线上，不能再用 anchor-edge 求）
	var inw: Variant = spot.get("inward", null)
	if inw is Vector3:
		var w: Vector3 = inw
		w.y = 0.0
		if w.length() > 0.001:
			return w.normalized()
	if _graph_house() != null:
		return Vector3(0.0, 0.0, -1.0)
	return Vector3(0.0, 0.0, -1.0)


func _graph_house() -> Node3D:
	if graph.is_empty():
		return null
	return graph.get("root", null) as Node3D


func _bed_edge_root(spot: Dictionary) -> Vector3:
	var edge: Vector3 = spot["anchor_edge"]
	return edge + _bed_inward(spot) * BED_EDGE_INSET + Vector3(0.0, BED_EDGE_ROOT_OFFSET, 0.0)


func _begin_bed_in() -> void:
	var spot: Dictionary = _act.get("spot", {})
	if spot.is_empty():
		_finish_activity("missing bed")
		return
	var edge : Vector3 = spot["anchor_edge"]
	var anchor: Vector3 = spot["anchor"]
	var inward := _bed_inward(spot)
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


## P9 / P7-FINALIZE 睡觉重做（C 报告 D5）：躺下不再是“整个人飘上床”，
## 1.0 s 的 lie_down 剪辑分三段，控制器 root 同步分段：
##   0.00–0.30 坐床沿不动（剪辑里先把腿搬上床）
##   0.30–1.00 按 smoothstep 把 root 从床沿横移到躺姿锚点（躯干同时后仰躺平）
## 剪辑最后一帧 == sleep 首帧（含头落枕 settle），所以停下即无缝进入睡眠循环。
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
	_hold_t = 0.0


func _tick_lie_in(_dt: float) -> void:
	var p := clampf(_state_t / maxf(_tr_dur, 0.001), 0.0, 1.0)
	var freeze_p := clampf(BED_LIE_FREEZE / maxf(_tr_dur, 0.001), 0.0, 0.9)
	if p <= freeze_p:
		_pos = _tr_from                 # 搬腿相位：root 不动
	else:
		var q := clampf((p - freeze_p) / (1.0 - freeze_p), 0.0, 1.0)
		var e := smoothstep(0.0, 1.0, q)
		_pos = _tr_from.lerp(_tr_to, e)
	# 朝向：前 10% 不转（还坐着），10%–90% 平滑躺正
	var ey := smoothstep(0.10, 0.90, p)
	_yaw = lerp_angle(_tr_from_yaw, _tr_to_yaw, ey)
	apply_pose()
	if p >= 1.0:
		_pos = _tr_to
		_yaw = _tr_to_yaw
		apply_pose()
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


## P9 / P7-FINALIZE 起床重做（C 报告 D6）：启用重写后的 get_up（睡姿 → 撑起 → 坐起 → 坐回床沿），
## 1.0 s 内 root 前 0.30 s 不动（先抬头/撑床），之后从躺姿锚点平滑挪回床沿，再由 bed_sit_up 站起。
func _begin_lie_out() -> void:
	var spot: Dictionary = _act.get("spot", {})
	if spot.is_empty():
		# 稳健性：_act 被外部清空时不崩（旧实现直接取 spot["anchor_edge"] 会 Key 错）
		_safe_ground_exit()
		_finish_activity("bed spot missing")
		return
	var edge_root := _bed_edge_root(spot)
	_tr_from = _pos
	_tr_from_yaw = _yaw
	_tr_to = edge_root
	_tr_to_yaw = float(spot.get("sit_yaw", _yaw))
	_tr_dur = float((ModelScript.ANIMATIONS as Dictionary)[&"get_up"]["length"])
	_play(&"get_up", 0.10)
	_set_state(State.LIE_OUT)
	_hold_t = 0.0


func _tick_lie_out(_dt: float) -> void:
	var p := clampf(_state_t / maxf(_tr_dur, 0.001), 0.0, 1.0)
	var freeze_p := clampf(BED_UP_FREEZE / maxf(_tr_dur, 0.001), 0.0, 0.9)
	if p <= freeze_p:
		_pos = _tr_from
	else:
		var q := clampf((p - freeze_p) / (1.0 - freeze_p), 0.0, 1.0)
		var e := smoothstep(0.0, 1.0, q)
		_pos = _tr_from.lerp(_tr_to, e)
	var ey := smoothstep(0.10, 0.90, p)
	_yaw = lerp_angle(_tr_from_yaw, _tr_to_yaw, ey)
	apply_pose()
	if p >= 1.0:
		_pos = _tr_to
		_yaw = _tr_to_yaw
		apply_pose()
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
# P9：秋千坐姿（由 main 注入真实吊点/座椅；不加新状态，复用 SIT_IN/SIT/SIT_OUT）
# =============================================================================
## main 侧接线：在 _collect_props() 拿到 _swing_pivot 后调用
##   _villager.call("set_swing_target", _swing_pivot, _swing_pivot.find_child("SwingSeat", true, false))
## 未注入时 swing 活动会安全回退为普通 sit/view，不会报错。
func set_swing_target(pivot: Node3D, seat: Node3D) -> bool:
	if pivot == null or seat == null:
		return false
	_swing_pivot = pivot
	_swing_seat = seat
	var par := pivot.get_parent() as Node3D
	_swing_parent_xf = par.global_transform if par != null else Transform3D.IDENTITY
	var self_par := get_parent() as Node3D
	_swing_parent_inv = (self_par.global_transform.affine_inverse() if self_par != null else Transform3D.IDENTITY)
	_swing_pivot_local = pivot.position
	_swing_seat_local = seat.transform
	_swing_seat_top = SWING_SEAT_TOP_FALLBACK
	var mi := seat as MeshInstance3D
	if mi != null and mi.mesh != null:
		var a := mi.mesh.get_aabb()
		_swing_seat_top = a.position.y + a.size.y
	_log("swing target injected seat_top=%.3f" % _swing_seat_top)
	return true


func swing_ready() -> bool:
	return _swing_pivot != null and _swing_seat != null


func swing_ride_active() -> bool:
	return _swing_ctrl and _state == State.SIT


## 座椅在给定吊点俯仰角下的世界变换（绕 pivot 局部 X 轴；roll 在骑行时归零）。
func _swing_seat_xf(theta: float) -> Transform3D:
	var pivot_xf := _swing_parent_xf * Transform3D(Basis(Vector3.RIGHT, theta), _swing_pivot_local)
	return pivot_xf * _swing_seat_local


## 角色 root 目标：座面上表面 + 0.02（与椅子坐姿同一约定），整身随座椅俯仰。
func _swing_root_pos() -> Vector3:
	if not swing_ready():
		return _pos
	var xf := _swing_seat_xf(_swing_theta)
	return _swing_parent_inv * (xf.origin + xf.basis * Vector3(0.0, _swing_seat_top + 0.02, 0.0))


func _apply_swing_ride(theta: float) -> void:
	if not swing_ready():
		return
	var xf := _swing_seat_xf(theta)
	var world_pos := xf.origin + xf.basis * Vector3(0.0, _swing_seat_top + 0.02, 0.0)
	position = _swing_parent_inv * world_pos
	transform.basis = _swing_parent_inv.basis * xf.basis
	_pos = position


func _swing_begin_approach() -> void:
	if not swing_ready():
		return
	_swing_ctrl = true
	_swing_phase = "approach"
	_swing_t = 0.0
	_swing_theta = 0.0


func _swing_begin_release() -> void:
	if not _swing_ctrl:
		return
	_swing_phase = "release"
	_swing_t = 0.0
	_swing_hold_theta = _swing_theta


func _swing_end_control() -> void:
	# 交还控制权：main 的 _update_props 下一帧就会写回自己的风致/待机摆角。
	_swing_ctrl = false
	_swing_phase = ""
	_swing_theta = 0.0
	rotation = Vector3(0.0, _yaw, 0.0)


func _swing_abort() -> void:
	_swing_end_control()


func _swing_tick(dt: float) -> void:
	if not swing_ready() or not _swing_ctrl:
		return
	var main_theta := _swing_pivot.rotation.x
	var main_roll := _swing_pivot.rotation.z
	_swing_t += dt
	match _swing_phase:
		"approach":
			var e := smoothstep(0.0, 1.0, clampf(_swing_t / SWING_CALM_TIME, 0.0, 1.0))
			_swing_theta = lerpf(main_theta, 0.0, e)
			_swing_pivot.rotation = Vector3(_swing_theta, 0.0, lerpf(main_roll, 0.0, e))
		"ride":
			# 轻柔 5–10° 前后摆：从 0 渐入到 ±7.4°，完全由角色自己驱动（不再叠加环境风的大幅 idle）。
			var amp := SWING_AMPLITUDE * clampf(_swing_t / SWING_RIDE_RAMP, 0.0, 1.0)
			_swing_theta = amp * sin(TAU * _swing_t / SWING_PERIOD)
			_swing_pivot.rotation = Vector3(_swing_theta, 0.0, 0.0)
			if _state == State.SIT:
				_apply_swing_ride(_swing_theta)
		"release":
			var e2 := smoothstep(0.0, 1.0, clampf(_swing_t / SWING_RELEASE_TIME, 0.0, 1.0))
			_swing_theta = lerpf(_swing_hold_theta, main_theta, e2)
			_swing_pivot.rotation = Vector3(_swing_theta, 0.0, lerpf(0.0, main_roll, e2))
			if e2 >= 1.0:
				_swing_end_control()


## 冻结（暂停/菜单）时 main 的秋千仍在推进：只把 root 重新贴回座椅，不推进状态机。
func _swing_hold_frozen() -> void:
	if not swing_ready() or not _swing_ctrl:
		return
	if _swing_phase == "ride" and _state == State.SIT:
		_apply_swing_ride(_swing_pivot.rotation.x)


# =============================================================================
# P9：进食碗（模型内置 Bowl 显隐；不扣/不加共享库存）
# =============================================================================
func _set_bowl(on: bool) -> void:
	if _bowl_on == on:
		return
	_bowl_on = on
	if model_root != null and model_root.has_method("set_bowl_visible"):
		model_root.call("set_bowl_visible", on)


func bowl_visible() -> bool:
	return _bowl_on


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
	_set_bowl(false)
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
		"swing":
			# P9：秋千是白天户外休闲。未注入真实吊点或秋千点被占/不可达时，安全回退到 view→sit→原地。
			var ssp := _pick_spot("swing")
			if not ssp.is_empty() and swing_ready():
				_target_spot(ssp)
			else:
				var vs := _pick_spot("view")
				if not vs.is_empty():
					_act["kind"] = "idle"
					_target_spot(vs)
				else:
					_in_place_idle()
		"sea_view":
			# P9：码头观海 —— 真实走到 dock_sea_watch 面朝海面；不可达则回退到 view 点。
			var svs := _pick_spot("sea_view")
			if not svs.is_empty():
				_target_spot(svs)
			else:
				var vs2 := _pick_spot("view")
				if not vs2.is_empty():
					_act["kind"] = "idle"
					_target_spot(vs2)
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
	_seg_horiz = 0.0
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
# P9：被接管/取消时的安全退出（不残留躺姿/坐姿/秋千倾角）
# =============================================================================
## 当 force_*/钓鱼/巡田在坐/躺/秋千中途接管时，把角色放回该活动的站立接近点并恢复直立姿态。
## 生产路径的普通活动结束不走这里（各 *_out 相位负责平滑收尾）。
func _safe_ground_exit() -> void:
	var in_pose := _state in [State.SIT_IN, State.SIT, State.EAT, State.SIT_OUT,
		State.BED_IN, State.LIE_IN, State.SLEEP, State.LIE_OUT, State.BED_OUT]
	if not in_pose and not _swing_ctrl:
		rotation = Vector3(0.0, _yaw, 0.0)
		return
	var ap: Variant = _act.get("approach", null)
	var ap_yaw := float(_act.get("approach_yaw", _yaw))
	if ap is Vector3:
		_pos = ap
		_yaw = ap_yaw
	rotation = Vector3(0.0, _yaw, 0.0)
	apply_pose()
	_swing_end_control()
	_set_bowl(false)
	# 状态机自身由调用方负责（force_* / 钓鱼 / 巡田都会紧接着设置新状态）


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
		"patrol": {
			"active": not _patrol.is_empty(),
			"phase": String(_patrol.get("phase", "")),
			"step": int(_patrol.get("step", 0)),
			"weather_abort": bool(_patrol.get("weather_abort", false)),
			"last": _patrol_last.duplicate(true),
		},
		"fishing": {
			"active": not _fish.is_empty(),
			"phase": String(_fish.get("phase", "")),
			"rounds": int(_fish.get("rounds", 0)),
			"catches": (_fish.get("catches", []) as Array).size(),
			"spot": String((_fish.get("spot", {}) as Dictionary).get("node", "")),
			"last": _fish_last.duplicate(true),
		},
		# P9：生活动作调试投影（探针断言用；只读）
		"bowl": _bowl_on,
		"swing": {
			"ready": swing_ready(),
			"control": _swing_ctrl,
			"phase": _swing_phase,
			"theta": _swing_theta,
			"seat_top": _swing_seat_top,
			"ride": swing_ride_active(),
		},
		"at_approach": _act.get("approach", null),
	}

# ---- 强制接口（仅供探针/测试，不进玩家 UI）----
var _force := ""

func _forced_mode() -> bool:
	return _force != ""


## 强制切换前丢弃当前活动（释放预约），避免调试/任务覆盖时永久锁住家具。
## 巡田也属于“当前活动”：任何显式丢弃（force_* 接管、日程切换）都先结束巡田，
## 防止两套移动意图并存；正式运行中巡田由主控正常完成/取消，不走这里。
func _drop_activity() -> void:
	if not _patrol.is_empty():
		_patrol_finish("cancelled", "activity_takeover")
	if not _fish.is_empty():
		_fish_finish("cancelled", "activity_takeover")
	_safe_ground_exit()
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


func force_swing() -> bool:
	var sp := _find_spot("swing", "")
	if sp.is_empty() or not swing_ready():
		return false
	_drop_activity()
	_force = "swing"
	_act = {"kind": "swing", "dur": 12.0, "spot_id": "", "region_pref": "any"}
	_target_spot_for_force(sp, "swing")
	return true


func force_sea_view() -> bool:
	var sp := _find_spot("sea_view", "")
	if sp.is_empty():
		return false
	_drop_activity()
	_force = "sea_view"
	_act = {"kind": "sea_view", "dur": 10.0, "spot_id": "", "region_pref": "any"}
	_target_spot_for_force(sp, "sea_view")
	return true


func clear_force() -> void:
	_force = ""
	_replan = false
	# P9（C 报告 D8）：沉睡/坐姿/秋千被 clear_force 打断时先安全落地，避免“站在床上/悬在座面”
	_safe_ground_exit()
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


# =============================================================================
# P4：农田巡田（主控在 08:00 交付；逐格移动→确认到达→检查天气→读权威状态→执行唯一主操作）
# =============================================================================
## 开始一轮全田巡查。route: [{slot:int, node:String, point:Vector3|null, face:Vector3|null}]。
## 失败返回 false（无农田/空路线/已有巡田/当前天气恶劣）；不瞬移、不伪造到达。
func begin_farm_patrol(route: Array, farm: Object, season_id: String) -> bool:
	if farm == null or route.is_empty() or not _patrol.is_empty():
		return false
	if not (farm.has_method("is_empty") and farm.has_method("is_mature") and farm.has_method("harvest") and farm.has_method("plant_auto")):
		return false
	if _weather_bad():
		return false
	# P6：钓鱼占用期间不抢控制权（一个岛民只能有一个有效活动意图）；
	# 主控按同一游戏日重试，绝不与钓鱼共用移动目标。
	if not _fish.is_empty():
		return false
	# 睡梦中/躺床时不抢控制权：由主控按同一游戏日在启动窗口内重试（不新建任务、不重复）。
	if _state == State.SLEEP or _state == State.BED_IN or _state == State.LIE_IN:
		return false
	# force_* 是调试/探针专用的粘性接管（正式玩法不用）；巡田不与它争控制权，
	# 主控按同一游戏日重试，等接管释放后再启动，避免探针断言被巡田打断。
	if _force != "":
		return false
	_drop_activity()
	_force = ""
	_patrol = {
		"phase": "walking",
		"route": route.duplicate(true),
		"farm": farm,
		"season": season_id,
		"step": 0,
		"results": [],
		"weather_abort": false,
		"started_sim": _sim_now,
		"ended_sim": 0.0,
		"return_node": "",
	}
	_log("farm patrol begin slots=%d sim=%.0f" % [route.size(), _sim_now])
	if not _patrol_plan_current():
		# _patrol_plan_current 在全部格子都不可达时会直接收尾（记录 unreachable 后 done）；
		# 这仍算"今天这一轮已经执行过"，不能用 false 让主控误以为从未启动。
		return _patrol.is_empty()
	return true


func farm_patrol_active() -> bool:
	return not _patrol.is_empty()


func farm_patrol_phase() -> String:
	return String(_patrol.get("phase", ""))


func farm_patrol_last() -> Dictionary:
	return _patrol_last.duplicate(true)


func cancel_farm_patrol(reason: String = "cancelled") -> void:
	_patrol_finish("cancelled", reason)


## 天气是否恶劣：只读 main 每帧注入的权威天气（与农田/日程同源），不看粒子/天空/截图。
func _weather_bad() -> bool:
	var w: Dictionary = _ctx.get("weather", {})
	var precip := String(w.get("precip_type", "none"))
	return precip == "rain" or precip == "snow"


## 按当前 step 规划下一格；路径失败记录 unreachable 后继续下一格（绝不瞬移/不夸大交互距离）。
func _patrol_plan_current() -> bool:
	var route: Array = _patrol.get("route", [])
	while int(_patrol.get("step", 0)) < route.size():
		var step := int(_patrol["step"])
		var entry: Dictionary = route[step]
		var node_id := String(entry.get("node", ""))
		var point: Variant = entry.get("point", null)
		if node_id != "" and _plan_path(node_id, point, 0.0):
			_patrol["phase"] = "walking"
			_play(&"walk", 0.2)
			_set_state(State.WALK)
			return true
		_patrol_record(int(entry.get("slot", -1)), "unreachable", "path_failed", "")
		_patrol["step"] = step + 1
	_patrol_finish("done", "")
	return false


func _patrol_dispatch(dt: float) -> void:
	if _patrol.is_empty():
		return
	var phase := String(_patrol.get("phase", ""))
	if phase == "returning":
		# 返程中不再检查天气：即使转晴也完成返室内意图（不在路线上反复改变目标）。
		if _state == State.WALK:
			_walk_step(dt)
		else:
			_patrol_finish("weather_aborted", "return_interrupted")
		return
	if phase == "walking":
		if _weather_bad():
			_patrol_abort_weather()
			return
		if _state == State.WALK:
			_walk_step(dt)
		else:
			# 异常状态（外部打断）：安全结束本轮，交还普通调度。
			_patrol_finish("failed", "state_lost")
		return
	if phase == "dwell":
		if _state_t >= PATROL_DWELL:
			_patrol_advance()
		return
	_patrol_finish("failed", "unknown_phase")


## 到达一格后：确认到达 → 检查天气 → 读权威状态 → 执行该格唯一主操作 → 短暂停留。
func _on_patrol_arrive() -> void:
	if _patrol.is_empty():
		return
	var phase := String(_patrol.get("phase", ""))
	if phase == "returning":
		_patrol_finish("weather_returned", "returned_indoor")
		return
	var route: Array = _patrol.get("route", [])
	var step := int(_patrol.get("step", 0))
	if step < 0 or step >= route.size():
		_patrol_finish("failed", "bad_step")
		return
	var entry: Dictionary = route[step]
	var slot := int(entry.get("slot", -1))
	# 天气检查必须在执行农田操作之前（同步提交，不在检查后长时间等待）。
	if _weather_bad():
		_patrol_abort_weather()
		return
	var farm: Object = _patrol.get("farm", null)
	var season_id := String(_patrol.get("season", ""))
	var action := "skip"
	var reason := ""
	var crop := ""
	var extra: Dictionary = {}
	if farm == null:
		reason = "no_farm"
	elif bool(farm.call("is_empty", slot)):
		var out: Dictionary = farm.call("plant_auto", slot, season_id)
		if bool(out.get("ok", false)):
			action = "plant"
			crop = String(out.get("crop_id", ""))
			extra = {"stage": "seedling"}
		else:
			reason = String(out.get("reason", "plant_failed"))
	elif bool(farm.call("is_mature", slot)):
		var out2: Dictionary = farm.call("harvest", slot)
		if bool(out2.get("ok", false)):
			action = "harvest"
			crop = String(out2.get("crop_id", ""))
			extra = {
				"produce_item": String(out2.get("produce_item", "")),
				"produce_amount": int(out2.get("produce_amount", 0)),
				"seed_returned": bool(out2.get("seed_returned", false)),
				"plant_removed": bool(out2.get("plant_removed", false)),
			}
		else:
			reason = String(out2.get("reason", "harvest_failed"))
	else:
		reason = "growing"
		crop = String(farm.call("crop_id_at", slot))
	_patrol_record(slot, action, reason, crop, extra)
	# 面向该格中心（可观察，不做劳动动画），停留 PATROL_DWELL 后前往下一格。
	var face: Variant = entry.get("face", null)
	if face != null:
		var fp: Vector3 = face
		var d := fp - _pos
		d.y = 0.0
		if d.length() > 0.01:
			_yaw = _yaw_face(d.normalized())
			apply_pose()
	_play_idle()
	_set_state(State.IDLE)
	_idle_mode = "patrol_dwell"
	_idle_dur = PATROL_DWELL
	_patrol["phase"] = "dwell"


func _patrol_advance() -> void:
	if _patrol.is_empty():
		return
	_patrol["step"] = int(_patrol.get("step", 0)) + 1
	_patrol["phase"] = "walking"
	_patrol_plan_current()


## 巡田途中天气转坏：取消剩余格、保留已提交事务、从现有路径返回室内最近安全点。
func _patrol_abort_weather() -> void:
	if _patrol.is_empty():
		return
	if String(_patrol.get("phase", "")) == "returning":
		return
	_patrol["weather_abort"] = true
	_patrol["phase"] = "returning"
	_patrol["abort_sim"] = _sim_now
	_patrol["step"] = (_patrol.get("route", []) as Array).size()
	_wp.clear()
	_wp_i = 0
	_speed = 0.0
	var best := ""
	var best_len := 1.0e9
	for id in PATROL_INDOOR_NODES:
		if _plan_path(String(id), null, 0.0):
			var ln := _path_length()
			if ln < best_len:
				best_len = ln
				best = String(id)
	if best == "":
		# 无任何可达室内点：不瞬移，安全结束并交还普通调度。
		print("[P4] patrol weather abort but no indoor path")
		_patrol_finish("weather_aborted", "no_indoor_path")
		return
	if not _plan_path(best, null, 0.0):
		_patrol_finish("weather_aborted", "no_indoor_path")
		return
	_patrol["return_node"] = best
	print("[P4] patrol weather abort return=%s sim=%.0f" % [best, _sim_now])
	_play(&"walk", 0.2)
	_set_state(State.WALK)


func _path_length() -> float:
	var total := 0.0
	var prev := _pos
	for w in _wp:
		var p: Vector3 = (w as Dictionary)["pos"]
		total += Vector2(p.x - prev.x, p.z - prev.z).length()
		prev = p
	return total


func _patrol_record(slot: int, action: String, reason: String, crop_id: String, extra: Dictionary = {}) -> void:
	if _patrol.is_empty():
		return
	var rec := {
		"slot": slot,
		"action": action,
		"reason": reason,
		"crop_id": crop_id,
		"sim_seconds": _sim_now,
		"pos": _pos,
	}
	for k in extra.keys():
		rec[k] = extra[k]
	(_patrol["results"] as Array).append(rec)
	print("[P4] patrol slot=%d action=%s reason=%s crop=%s sim=%.0f" % [slot, action, reason, crop_id, _sim_now])


func _patrol_finish(outcome: String, reason: String) -> void:
	if _patrol.is_empty():
		return
	var results: Array = _patrol.get("results", [])
	var summary := {
		"outcome": outcome,
		"reason": reason,
		"results": results.duplicate(true),
		"started_sim": float(_patrol.get("started_sim", _sim_now)),
		"ended_sim": _sim_now,
		"weather_abort": bool(_patrol.get("weather_abort", false)),
		"return_node": String(_patrol.get("return_node", "")),
		"season": String(_patrol.get("season", "")),
		"route_size": (_patrol.get("route", []) as Array).size(),
	}
	_patrol_last = summary
	print("[P4] patrol finish outcome=%s reason=%s visited=%d weather_abort=%s sim=%.0f" % [outcome, reason, results.size(), str(summary["weather_abort"]), _sim_now])
	_patrol = {}
	_wp.clear()
	_wp_i = 0
	_speed = 0.0
	_hold_t = 0.0
	_replan = false
	_play_idle()
	_set_state(State.IDLE)
	_idle_mode = "cooldown"
	_idle_dur = DECISION_COOLDOWN


# =============================================================================
# P6：岛民自主钓鱼（玩家在 HUD 点击"钓鱼"→ 走到真实钓位 → 抛竿/等待/咬钩/收线/展示 → 自动下一轮）
# =============================================================================
## 玩家正式入口调用。commit_cb(fish_id:String, size:float) -> bool 负责把鱼获写入共享库存；
## sfx_cb(power:float) 可选，用于落水/咬钩水花（main 注入既有 _sfx_splash）。
## 返回 {ok:true, spot:...} 或 {ok:false, reason:...}（reason 用于 HUD 明确提示，绝不静默进入）。
func begin_fishing(commit_cb: Callable, sfx_cb: Callable = Callable()) -> Dictionary:
	if not _fish.is_empty():
		return {"ok": false, "reason": "already_fishing"}
	if not _patrol.is_empty():
		return {"ok": false, "reason": "patrol_running"}
	if _force != "":
		return {"ok": false, "reason": "forced_mode"}
	if _state == State.SLEEP or _state == State.BED_IN or _state == State.LIE_IN:
		return {"ok": false, "reason": "sleeping"}
	var spot: Dictionary = SpotScript.fishing_spot(graph)
	if spot.is_empty():
		return {"ok": false, "reason": "no_spot"}
	if not _plan_path(String(spot["node"]), spot["point"], float(spot["face_yaw"])):
		_log("fishing begin path_failed spot=%s" % String(spot["node"]))
		print("[P6] fishing path_failed spot=%s" % String(spot["node"]))
		return {"ok": false, "reason": "path_failed"}
	_drop_activity()
	_force = ""
	_fish = {
		"phase": "walking",
		"spot": spot,
		"cast_point": spot["cast_point"],
		"face_yaw": float(spot["face_yaw"]),
		"rounds": 0,
		"catches": [],
		"started_sim": _sim_now,
		"ended_sim": 0.0,
		"feel": 0.0,
		"wait_dur": 0.0,
		"nibble_early": false,
		"nibble_pre": false,
		"error": "",
	}
	_fish_commit = commit_cb
	_fish_sfx = sfx_cb
	_setup_fish_rig()
	_play(&"walk", 0.2)
	_set_state(State.WALK)
	_log("fishing begin spot=%s sim=%.0f" % [String(spot["node"]), _sim_now])
	print("[P6] fishing begin spot=%s walk_nodes=%d sim=%.0f" % [String(spot["node"]), _wp.size(), _sim_now])
	return {"ok": true, "spot": spot}


func fishing_active() -> bool:
	return not _fish.is_empty()


func fishing_phase() -> String:
	return String(_fish.get("phase", ""))


## 只读快照（main 每帧投影到 HUD；探针用来断言）。返回深拷贝，外部无法改状态机。
func fishing_state() -> Dictionary:
	if _fish.is_empty():
		return {"active": false, "phase": "", "rounds": 0, "catches": [], "spot": "",
			"last": _fish_last.duplicate(true)}
	return {
		"active": true,
		"phase": String(_fish.get("phase", "")),
		"rounds": int(_fish.get("rounds", 0)),
		"catches": (_fish.get("catches", []) as Array).duplicate(true),
		"spot": String((_fish.get("spot", {}) as Dictionary).get("node", "")),
		"started_sim": float(_fish.get("started_sim", 0.0)),
		"wait_dur": float(_fish.get("wait_dur", 0.0)),
		"error": String(_fish.get("error", "")),
		"last": _fish_last.duplicate(true),
	}


func fishing_last() -> Dictionary:
	return _fish_last.duplicate(true)


## 玩家点"停止钓鱼"：立即结束本轮，不再开下一轮；已提交的鱼获保留，不撤销不重复。
func cancel_fishing(reason: String = "cancelled") -> void:
	_fish_finish("cancelled", reason)


func _fish_dispatch(dt: float) -> void:
	if _fish.is_empty():
		return
	var phase := String(_fish.get("phase", ""))
	if phase == "walking":
		if _state == State.WALK:
			_walk_step(dt)
		else:
			_fish_finish("failed", "walk_state_lost")
		return
	var feel := _fish_feel(dt)
	_fish["feel"] = float(_fish.get("feel", 0.0)) + feel
	var p := float(_fish["feel"])
	if phase == "casting":
		if p >= _fish_clip_len(&"fish_cast"):
			_fish_enter_wait()
		return
	if phase == "waiting":
		var wait_dur := float(_fish.get("wait_dur", FISH_WAIT_MIN))
		if not bool(_fish.get("nibble_early", false)) and p >= wait_dur * 0.55:
			_fish["nibble_early"] = true
			_fish_rig_call(&"nibble", [0.32])
		if not bool(_fish.get("nibble_pre", false)) and p >= wait_dur - FISH_NIBBLE_PRE:
			_fish["nibble_pre"] = true
			_fish_rig_call(&"nibble", [0.62])
		if p >= wait_dur:
			_fish_bite()
		return
	if phase == "bite":
		if p >= FISH_BITE_TIME:
			_fish_begin_reel()
		return
	if phase == "reeling":
		if p >= _fish_clip_len(&"fish_reel"):
			_fish_land()
		return
	if phase == "reveal":
		if p >= FISH_REVEAL_TIME:
			_fish_rig_call(&"hide_catch")
			_fish["phase"] = "between"
			_fish["feel"] = 0.0
		return
	if phase == "between":
		if p >= FISH_BETWEEN_TIME:
			_fish_begin_cast()
		return
	_fish_finish("failed", "unknown_phase")


## 体感秒：世界模拟时间的推进量 ÷ 模拟倍率（等价于真实帧时间，但来源是 _sim_seconds 契约）。
## 单帧上限 FISH_FEEL_CAP：即使注入异常大的 sim_delta 也不会瞬间跳完多个阶段。
func _fish_feel(dt: float) -> float:
	var rate := maxf(float(_ctx.get("sim_rate", 1.0)), 0.001)
	var sd := float(_ctx.get("sim_delta", 0.0))
	if sd <= 0.0:
		sd = dt * rate
	return clampf(sd / rate, 0.0, FISH_FEEL_CAP)


func _fish_clip_len(clip: StringName) -> float:
	var spec: Dictionary = ModelScript.ANIMATIONS.get(clip, {})
	return maxf(float(spec.get("length", 1.2)), 0.2)


func _fish_begin_cast() -> void:
	_fish["phase"] = "casting"
	_fish["feel"] = 0.0
	_fish["nibble_early"] = false
	_fish["nibble_pre"] = false
	_yaw = float(_fish.get("face_yaw", _yaw))
	apply_pose()
	_play(&"fish_cast", 0.12)
	_fish_rig_call(&"show_rod")
	_fish_rig_call(&"set_line_visible", [false])
	_fish_rig_call(&"start_cast", [_fish.get("cast_point", _pos), _fish_clip_len(&"fish_cast")])
	_set_state(State.IDLE)
	_idle_mode = "fishing"
	_idle_dur = 1.0e9


func _fish_enter_wait() -> void:
	_fish["phase"] = "waiting"
	_fish["feel"] = 0.0
	var long_wait := _rng.randf() < FISH_LONG_CHANCE
	var lo := FISH_WAIT_LONG_MIN if long_wait else FISH_WAIT_MIN
	var hi := FISH_WAIT_LONG_MAX if long_wait else FISH_WAIT_MAX
	_fish["wait_dur"] = _rng.randf_range(lo, hi)
	_play(&"fish_hold", 0.15)
	_fish_rig_call(&"set_bobber_target", [_fish.get("cast_point", _pos)])
	_fish_rig_call(&"set_bobber_visible", [true])
	_fish_rig_call(&"set_line_visible", [true])
	_fish_sfx_call(0.35)
	print("[P6] fishing cast_done spot=%s wait=%.2fs sim=%.0f" % [String((_fish.get("spot", {}) as Dictionary).get("node", "")), float(_fish["wait_dur"]), _sim_now])


func _fish_bite() -> void:
	_fish["phase"] = "bite"
	_fish["feel"] = 0.0
	_fish_rig_call(&"bite")
	_fish_sfx_call(0.85)
	print("[P6] fishing bite wait=%.2fs sim=%.0f" % [float(_fish.get("wait_dur", 0.0)), _sim_now])


func _fish_begin_reel() -> void:
	_fish["phase"] = "reeling"
	_fish["feel"] = 0.0
	_play(&"fish_reel", 0.12)
	_fish_rig_call(&"start_reel", [_fish_clip_len(&"fish_reel")])


## 收线完成：按当时的权威季节/时刻/天气抽鱼，并通过 main 注入的 Callable 入账一次。
func _fish_land() -> void:
	var cond := _fish_conditions()
	var fish_id := String(FishScript.pick(String(cond["season"]), int(cond["hour"]), String(cond["weather_key"]), _rng))
	var def: Dictionary = FishScript.get_def(fish_id)
	var size := 0.0
	if not def.is_empty():
		size = snappedf(_rng.randf_range(float(def["min_size"]), float(def["max_size"])), 0.01)
	var committed := false
	if _fish_commit.is_valid():
		committed = bool(_fish_commit.call(fish_id, size))
	if not committed:
		_fish["error"] = "inventory_failed"
		print("[P6] fishing inventory_failed fish=%s sim=%.0f" % [fish_id, _sim_now])
		_fish_finish("inventory_failed", "commit_failed")
		return
	var catch_rec := {
		"fish_id": fish_id,
		"display_name": String(FishScript.display_name(fish_id)),
		"size": size,
		"sim_seconds": _sim_now,
		"pos": _pos,
		"season": String(cond["season"]),
		"hour": int(cond["hour"]),
		"weather_key": String(cond["weather_key"]),
	}
	(_fish["catches"] as Array).append(catch_rec)
	_fish["rounds"] = int(_fish.get("rounds", 0)) + 1
	_fish["last_catch"] = catch_rec
	_fish["phase"] = "reveal"
	_fish["feel"] = 0.0
	_play(&"fish_hold", 0.12)
	_fish_rig_call(&"show_catch", [fish_id, size])
	print("[P6] fishing catch fish=%s size=%.2f rounds=%d sim=%.0f season=%s hour=%d weather=%s" % [fish_id, size, int(_fish["rounds"]), _sim_now, String(cond["season"]), int(cond["hour"]), String(cond["weather_key"])])


func _fish_conditions() -> Dictionary:
	var w: Dictionary = _ctx.get("weather", {})
	var season := String(_ctx.get("season_id", "spring"))
	var hour := int(fposmod(_sim_now, 86400.0) / 3600.0)
	var wk := String(FishScript.weather_key(String(w.get("type", "clear")), String(w.get("precip_type", "none")), float(w.get("cloud", 0.0))))
	return {"season": season, "hour": hour, "weather_key": wk}


func _fish_arrive() -> void:
	if _fish.is_empty():
		return
	if String(_fish.get("phase", "")) != "walking":
		_fish_finish("failed", "bad_arrive")
		return
	var spot: Dictionary = _fish.get("spot", {})
	var node_id := String(spot.get("node", ""))
	var point: Vector3 = spot.get("point", _pos)
	var dist := Vector2(_pos.x - point.x, _pos.z - point.z).length()
	if node_id == "" or dist > FISH_SPOT_EPS:
		_fish["error"] = "spot_unreachable"
		print("[P6] fishing spot_unreachable node=%s at=%s dist=%.3f" % [node_id, _at_node, dist])
		_fish_finish("path_failed", "spot_unreachable")
		return
	_pos = point
	_yaw = float(spot.get("face_yaw", _yaw))
	apply_pose()
	print("[P6] fishing arrive spot=%s pos=%s yaw=%.3f sim=%.0f" % [node_id, str(_pos), _yaw, _sim_now])
	_fish_begin_cast()


func _fish_finish(outcome: String, reason: String) -> void:
	if _fish.is_empty():
		return
	var catches: Array = _fish.get("catches", [])
	_fish_last = {
		"outcome": outcome,
		"reason": reason,
		"rounds": int(_fish.get("rounds", 0)),
		"catches": catches.duplicate(true),
		"last_catch": (_fish.get("last_catch", {}) as Dictionary).duplicate(true),
		"started_sim": float(_fish.get("started_sim", _sim_now)),
		"ended_sim": _sim_now,
		"spot": String((_fish.get("spot", {}) as Dictionary).get("node", "")),
		"error": String(_fish.get("error", "")),
	}
	print("[P6] fishing finish outcome=%s reason=%s rounds=%d catches=%d sim=%.0f" % [outcome, reason, int(_fish_last["rounds"]), catches.size(), _sim_now])
	_fish = {}
	_fish_commit = Callable()
	_fish_sfx = Callable()
	_fish_rig_call(&"clear_all")
	_wp.clear()
	_wp_i = 0
	_speed = 0.0
	_hold_t = 0.0
	_replan = false
	_play_idle()
	_set_state(State.IDLE)
	_idle_mode = "cooldown"
	_idle_dur = DECISION_COOLDOWN


# ---- 钓鱼装配件（视觉）：懒加载；脚本缺失时状态机仍可运行（探针/降级），但正式游戏一定有。 ----
func _setup_fish_rig() -> void:
	if _fish_rig == null:
		if not ResourceLoader.exists("res://scripts/isle_fishing_rig.gd"):
			return
		var sc := load("res://scripts/isle_fishing_rig.gd")
		if sc == null:
			return
		_fish_rig = sc.new() as Node3D
		if _fish_rig == null:
			return
		_fish_rig.name = "FishingRig"
		add_child(_fish_rig)
	if _fish_rig.has_method("setup"):
		var hand: Node3D = null
		if model_root != null and model_root.has_method("get_joint"):
			hand = model_root.call("get_joint", "hand_r") as Node3D
		_fish_rig.call("setup", self, model_root, hand)


func _fish_rig_tick(dt: float) -> void:
	if _fish_rig == null or not _fish_rig.has_method("tick"):
		return
	_fish_rig.call("tick", dt, _frozen)


func _fish_rig_call(method: StringName, args: Array = []) -> Variant:
	if _fish_rig == null or not _fish_rig.has_method(method):
		return null
	return _fish_rig.callv(method, args)


func _fish_sfx_call(power: float) -> void:
	if _fish_sfx.is_valid():
		_fish_sfx.call(power)


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
