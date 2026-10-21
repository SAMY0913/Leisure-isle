class_name IsleCat
extends RefCounted
## P7-V3 任务 F：门廊猫 —— 程序化绘本 toon 造型 + 原地随机待机（6 类动作）。
##
## 集成方式（Lead 改 scripts/cottage.gd 的 _cat，其余不变）：
##   const CAT_MODEL := preload("res://scripts/isle_cat.gd")
##   static func _cat(root: Node3D, C: Dictionary, pos: Vector3) -> void:
##       CAT_MODEL.build(root, pos)   # root 名为 PorchCat、position=pos、rotation.y=-0.6
##   （若全局类缓存已扫描，也可直接写 IsleCat.build(root, pos)）
##
## build() 返回字典：
##   root/body/head/head_core/ears/eyes/eyelids/whiskers/tail/legs/front_legs/paws/shadow/driver/idle
##   - ears: Array[Node3D] 耳朵枢轴（可动，抽动动画）
##   - eyes: Array[Node3D] 眼球枢轴（内含扁球眼球+竖瞳+高光）
##   - eyelids: Array[Node3D] 眼睑枢轴（眨眼动画）
##   - tail: Array[Node3D] 3 节尾巴关节链 J0→J1→J2
##   - front_legs: Array[Node3D] 前腿枢轴（舔爪抬爪）
##   - paws: Array[MeshInstance3D] 4 只脚掌
##   - driver: Node（CatIdleDriver，_process 驱动待机）
##   - idle: RefCounted（CatIdle，时间累加器+RNG；可 advance(dt) 手动驱动 / debug_state()）
##
## 约定：
##   - 模型朝 +Z（与旧版一致），脚底 local y≈0；root 放在门廊木板顶面（世界 y≈0.47）。
##   - 根节点位置旋转恒定，动画只动子节点；无永久 Timer、不重建网格。
##   - 驱动节点 PROCESS_MODE_INHERIT：SceneTree.paused 时自动暂停，恢复后继续（时间累加器不跳变）。
##   - 探针可 cat["driver"].set_process(false) 冻结后手动 idle.advance()/debug_force_event() 摆姿势。

const M := preload("res://scripts/isle_math.gd")

# ---------------------------------------------------------------------------
# 造型常量（米；模型 +Z 朝前）
# ---------------------------------------------------------------------------
const BODY_R := 0.23                              # 身体半径（头身比 ≈ 1:2.2）
const HEAD_R := 0.155                             # 头半径
const BODY_CENTER := Vector3(0.0, 0.25, -0.045)   # 坐姿躯干中心（前高后低倾斜）
const BODY_TILT := -0.20                          # 躯干绕 X 倾斜（前胸抬高）
const HEAD_PIVOT := Vector3(0.0, 0.40, 0.13)      # 颈枢轴（头的 yaw/pitch 绕此旋转）
const HEAD_CORE_OFFSET := Vector3(0.0, 0.075, 0.065)  # 头球中心相对颈枢轴
# P7-V3.2 全岛度量衡校准：旧猫按 1.50 m 人物比例过大（坐姿耳尖 0.742 m、鼻尖到尾根 0.732 m）。
# 不改根节点 scale（会污染后续动画/交互坐标与探针契约），而是把全部构造字面量统一乘比例。
# 目标：坐姿耳尖 ≈0.445 m（0.40–0.50）、鼻尖到尾根 ≈0.44 m（≤0.55）、体宽 ≈0.276 m（0.24–0.28）、
#      站立肩高 ≈0.256 m（0.25–0.30）。尾巴/呼吸/行走动画只动 rotation 与相对量，保持不变。
const CAT_MODEL_SCALE := 0.60

const C_FUR := Color("4a4e57")        # 身体深蓝灰（沿用旧猫配色）
const C_FUR_HEAD := Color("555a64")   # 头/耳/爪稍亮
const C_CREAM := Color("d8d2c4")      # 奶油色胸脯/口鼻
const C_EAR_IN := Color("b08a84")     # 内耳
const C_NOSE := Color("2a2321")       # 鼻/嘴
const C_EYE := Color("e8c25a")        # 琥珀眼
const C_PUPIL := Color("1e1a18")
const C_HILITE := Color("fff6e0")
const C_WHISKER := Color("cfc8b8")

# ===========================================================================
# 驱动节点：挂在 PorchCat 下，_process 推进 CatIdle；随场景树暂停/恢复
# ===========================================================================
class CatIdleDriver extends Node:
	var controller = null   # CatIdle（动态调用，避免内嵌类类型依赖）

	func _process(delta: float) -> void:
		if controller != null:
			controller.advance(delta)

# ===========================================================================
# 待机控制器：纯 RefCounted，时间累加器 + RandomNumberGenerator
# ===========================================================================
class CatIdle extends RefCounted:
	# 呼吸：胸腹 scale y 1±0.015，周期 3.2~4.2s
	const BREATH_AMP := 0.015
	const BREATH_PERIOD_MIN := 3.2
	const BREATH_PERIOD_MAX := 4.2
	# 尾巴摆动：2 节正弦 + 随机相位，幅度 ±0.18 rad，周期 5~8s
	const TAIL_AMP := 0.18
	const TAIL_PERIOD_MIN := 5.0
	const TAIL_PERIOD_MAX := 8.0
	const TAIL_AMP2 := 0.60      # 第 2 节幅度系数
	const TAIL_AMP3 := 0.35      # 第 3 节被动跟随
	const TAIL_UP_AMP := 0.03    # 尾部轻微上下摆动（≤0.03 rad，保证不触地）
	# 耳朵抽动：随机 6~14s 一次，0.25 rad 快速抖 2 次
	const EAR_AMP := 0.25
	const EAR_FLICK_DUR := 0.13
	const EAR_FLICK_GAP := 0.20
	const EAR_EVENT_DUR := 0.34
	const EAR_NEXT_MIN := 6.0
	const EAR_NEXT_MAX := 14.0
	# 眨眼：随机 4~9s，闭合 0.12s / 停留 0.06s / 恢复 0.12s
	const LID_OPEN := 1.38
	const LID_CLOSED := -0.10
	const BLINK_CLOSE := 0.12
	const BLINK_HOLD := 0.06
	const BLINK_OPEN := 0.12
	const BLINK_TOTAL := 0.30
	const BLINK_NEXT_MIN := 4.0
	const BLINK_NEXT_MAX := 9.0
	# 观察四周：随机 10~20s 一次，头 yaw ±0.35 rad，1.2s 缓动（+保持+回正）
	const LOOK_YAW := 0.35
	const LOOK_TURN := 1.2
	const LOOK_HOLD_MIN := 0.5
	const LOOK_HOLD_MAX := 0.9
	const LOOK_BACK := 1.2
	const LOOK_NEXT_MIN := 10.0
	const LOOK_NEXT_MAX := 20.0
	# 舔爪：随机 20~35s 一次，头低 0.35 rad + 前爪抬起 0.12
	const LICK_PITCH := 0.35
	const LICK_RAISE := 0.072    # 0.12 × CAT_MODEL_SCALE(0.60)：抬爪距离随模型比例缩小
	const LICK_SIDE_YAW := 0.14
	const LICK_LEG_TILT := -0.30
	const LICK_UP := 0.60
	const LICK_HOLD_MIN := 0.60
	const LICK_HOLD_MAX := 1.20
	const LICK_DOWN := 0.60
	const LICK_NEXT_MIN := 20.0
	const LICK_NEXT_MAX := 35.0

	var driver = null    # CatIdleDriver（debug_state 用）
	var _rng := RandomNumberGenerator.new()
	var _seed_used := 0
	var _t := 0.0

	var _body = null
	var _head = null
	var _ears: Array = []
	var _lids: Array = []
	var _eyes: Array = []
	var _tail: Array = []
	var _front_legs: Array = []
	var _base_body_scale := Vector3.ONE
	var _base_head := Vector3.ZERO
	var _base_ears: Array = []
	var _base_tail: Array = []
	var _base_legs: Array = []

	var _breath_period := 3.6
	var _breath_phase := 0.0
	var _tail_period := 6.0
	var _tail_phase: Array = []

	var _blink: Dictionary = {}
	var _ear: Dictionary = {}
	var _look: Dictionary = {}
	var _lick: Dictionary = {}
	var _counts := {"blink": 0, "ear": 0, "look": 0, "lick": 0}
	var _history := {"blink": [], "ear": [], "look": [], "lick": []}
	var _lid_amt := 0.0
	var _ear_off := 0.0
	var _look_yaw := 0.0
	var _lick_env := 0.0
	var _lick_side_yaw := 0.0

	func _init(parts: Dictionary, seed_value: int = -1) -> void:
		_body = parts.get("body")
		_head = parts.get("head")
		_ears = (parts.get("ears", []) as Array).duplicate()
		_lids = (parts.get("eyelids", []) as Array).duplicate()
		_eyes = (parts.get("eyes", []) as Array).duplicate()
		_tail = (parts.get("tail", []) as Array).duplicate()
		_front_legs = (parts.get("front_legs", []) as Array).duplicate()
		_base_body_scale = _body.scale if _body != null else Vector3.ONE
		_base_head = _head.rotation if _head != null else Vector3.ZERO
		for e in _ears:
			_base_ears.append(e.rotation)
		for j in _tail:
			_base_tail.append(j.rotation)
		for l in _front_legs:
			_base_legs.append({"pos": l.position, "rot": l.rotation})
		if seed_value < 0:
			_rng.randomize()
		else:
			_rng.seed = seed_value
		_seed_used = int(_rng.seed)
		# 连续动作参数（呼吸周期/相位、尾巴周期/三相随机相位）
		_breath_period = _rng.randf_range(BREATH_PERIOD_MIN, BREATH_PERIOD_MAX)
		_breath_phase = _rng.randf_range(0.0, TAU)
		_tail_period = _rng.randf_range(TAIL_PERIOD_MIN, TAIL_PERIOD_MAX)
		_tail_phase = [
			_rng.randf_range(0.0, TAU),
			_rng.randf_range(0.0, TAU),
			_rng.randf_range(0.0, TAU),
		]
		# 事件定时器：首次触发时间落在各自随机区间内
		_blink = _new_timer(_rng.randf_range(BLINK_NEXT_MIN, BLINK_NEXT_MAX))
		_ear = _new_timer(_rng.randf_range(EAR_NEXT_MIN, EAR_NEXT_MAX))
		_look = _new_timer(_rng.randf_range(LOOK_NEXT_MIN, LOOK_NEXT_MAX))
		_look["yaw"] = 0.0
		_look["hold"] = 0.0
		_lick = _new_timer(_rng.randf_range(LICK_NEXT_MIN, LICK_NEXT_MAX))
		_lick["side"] = 0
		_lick["hold"] = 0.0
		_ear["side"] = 0
		_reset_pose()

	func _new_timer(first: float) -> Dictionary:
		return {"active": false, "t0": 0.0, "dur": 0.0, "next": first}

	func _ease(x: float) -> float:
		var c := clampf(x, 0.0, 1.0)
		return c * c * (3.0 - 2.0 * c)

	func _reset_pose() -> void:
		_lid_amt = 0.0
		_ear_off = 0.0
		_look_yaw = 0.0
		_lick_env = 0.0
		_lick_side_yaw = 0.0
		if _body != null:
			_body.scale = _base_body_scale
		if _head != null:
			_head.rotation = _base_head
		for i in range(_ears.size()):
			_ears[i].rotation = _base_ears[i]
		for i in range(_tail.size()):
			_tail[i].rotation = _base_tail[i]
		for i in range(_front_legs.size()):
			_front_legs[i].position = _base_legs[i]["pos"]
			_front_legs[i].rotation = _base_legs[i]["rot"]
		var lid_rot := LID_OPEN
		for lid in _lids:
			lid.rotation.x = lid_rot
		for eye in _eyes:
			(eye as Node3D).visible = true

	## 每帧推进（driver 调用；探针可用固定 dt 手动调用）。
	## 只更新已有网格节点的 Transform，绝不重建/新增网格。
	func advance(delta: float) -> void:
		if delta <= 0.0 or not is_finite(delta):
			return
		_t += delta
		# --- 呼吸：胸腹 scale y 1±0.015（周期 3.2~4.2s，随机相位）---
		var breath := 1.0 + BREATH_AMP * sin(TAU * _t / _breath_period + _breath_phase)
		_body.scale = Vector3(_base_body_scale.x, _base_body_scale.y * breath, _base_body_scale.z)
		# --- 尾巴：2 节正弦 + 随机相位 + 第 3 节被动跟随（幅度 ≤ ±0.18 rad）---
		var w0: float = TAU * _t / _tail_period + float(_tail_phase[0])
		var w1: float = TAU * _t / (_tail_period * 1.37) + float(_tail_phase[1])
		var w2: float = TAU * _t / (_tail_period * 1.83) + float(_tail_phase[2])
		var up0: float = TAIL_UP_AMP * sin(TAU * _t / (_tail_period * 1.21) + float(_tail_phase[1]))
		var up1: float = TAIL_UP_AMP * 0.6 * sin(TAU * _t / (_tail_period * 1.59) + float(_tail_phase[2]))
		_tail[0].rotation = Vector3(_base_tail[0].x + up0, _base_tail[0].y + TAIL_AMP * sin(w0), _base_tail[0].z + 0.02 * sin(w2))
		_tail[1].rotation = Vector3(_base_tail[1].x + up1, _base_tail[1].y + TAIL_AMP * TAIL_AMP2 * sin(w1), _base_tail[1].z)
		_tail[2].rotation = Vector3(_base_tail[2].x, _base_tail[2].y + TAIL_AMP * TAIL_AMP3 * sin(w2), _base_tail[2].z)
		# --- 事件：低频随机错峰 ---
		_tick_blink()
		_tick_ear()
		_tick_look()
		_tick_lick()
		_apply_face_and_limbs()

	func _tick_blink() -> void:
		if not bool(_blink["active"]) and _t >= float(_blink["next"]):
			_blink["active"] = true
			_blink["t0"] = _t
			_counts["blink"] = int(_counts["blink"]) + 1
			(_history["blink"] as Array).append(snappedf(_t, 0.001))
		var amt := 0.0
		if bool(_blink["active"]):
			var lt: float = _t - float(_blink["t0"])
			if lt < BLINK_CLOSE:
				amt = _ease(lt / BLINK_CLOSE)
			elif lt < BLINK_CLOSE + BLINK_HOLD:
				amt = 1.0
			elif lt < BLINK_TOTAL:
				amt = 1.0 - _ease((lt - BLINK_CLOSE - BLINK_HOLD) / BLINK_OPEN)
			else:
				_blink["active"] = false
				_blink["next"] = _t + _rng.randf_range(BLINK_NEXT_MIN, BLINK_NEXT_MAX)
		_lid_amt = amt

	func _tick_ear() -> void:
		if not bool(_ear["active"]) and _t >= float(_ear["next"]):
			_ear["active"] = true
			_ear["t0"] = _t
			_ear["side"] = _rng.randi_range(0, 2)   # 0 左耳 / 1 右耳 / 2 双耳
			_counts["ear"] = int(_counts["ear"]) + 1
			(_history["ear"] as Array).append(snappedf(_t, 0.001))
		var off := 0.0
		if bool(_ear["active"]):
			var lt: float = _t - float(_ear["t0"])
			if lt < EAR_FLICK_DUR:
				off = EAR_AMP * sin(PI * clampf(lt / EAR_FLICK_DUR, 0.0, 1.0))
			elif lt >= EAR_FLICK_GAP and lt < EAR_FLICK_GAP + EAR_FLICK_DUR:
				off = EAR_AMP * sin(PI * clampf((lt - EAR_FLICK_GAP) / EAR_FLICK_DUR, 0.0, 1.0))
			if lt >= EAR_EVENT_DUR:
				_ear["active"] = false
				off = 0.0
				_ear["next"] = _t + _rng.randf_range(EAR_NEXT_MIN, EAR_NEXT_MAX)
		_ear_off = off

	func _tick_look() -> void:
		if not bool(_look["active"]) and _t >= float(_look["next"]):
			_look["active"] = true
			_look["t0"] = _t
			_look["yaw"] = (1.0 if _rng.randf() < 0.5 else -1.0) * _rng.randf_range(0.22, LOOK_YAW)
			_look["hold"] = _rng.randf_range(LOOK_HOLD_MIN, LOOK_HOLD_MAX)
			_look["dur"] = LOOK_TURN + float(_look["hold"]) + LOOK_BACK
			_counts["look"] = int(_counts["look"]) + 1
			(_history["look"] as Array).append(snappedf(_t, 0.001))
		var yaw := 0.0
		if bool(_look["active"]):
			var lt: float = _t - float(_look["t0"])
			var hold: float = float(_look["hold"])
			if lt < LOOK_TURN:
				yaw = float(_look["yaw"]) * _ease(lt / LOOK_TURN)
			elif lt < LOOK_TURN + hold:
				yaw = float(_look["yaw"])
			elif lt < float(_look["dur"]):
				yaw = float(_look["yaw"]) * (1.0 - _ease((lt - LOOK_TURN - hold) / LOOK_BACK))
			else:
				_look["active"] = false
				yaw = 0.0
				_look["next"] = _t + _rng.randf_range(LOOK_NEXT_MIN, LOOK_NEXT_MAX)
		_look_yaw = yaw

	func _tick_lick() -> void:
		if not bool(_lick["active"]) and _t >= float(_lick["next"]):
			_lick["active"] = true
			_lick["t0"] = _t
			_lick["side"] = _rng.randi_range(0, maxi(_front_legs.size() - 1, 0))
			_lick["hold"] = _rng.randf_range(LICK_HOLD_MIN, LICK_HOLD_MAX)
			_lick["dur"] = LICK_UP + float(_lick["hold"]) + LICK_DOWN
			_lick_side_yaw = LICK_SIDE_YAW * (1.0 if int(_lick["side"]) == 0 else -1.0)
			_counts["lick"] = int(_counts["lick"]) + 1
			(_history["lick"] as Array).append(snappedf(_t, 0.001))
		var env := 0.0
		if bool(_lick["active"]):
			var lt: float = _t - float(_lick["t0"])
			var hold: float = float(_lick["hold"])
			if lt < LICK_UP:
				env = _ease(lt / LICK_UP)
			elif lt < LICK_UP + hold:
				env = 1.0
			elif lt < float(_lick["dur"]):
				env = 1.0 - _ease((lt - LICK_UP - hold) / LICK_DOWN)
			else:
				_lick["active"] = false
				env = 0.0
				_lick["next"] = _t + _rng.randf_range(LICK_NEXT_MIN, LICK_NEXT_MAX)
		_lick_env = env

	func _apply_face_and_limbs() -> void:
		# 头：yaw（观察）+ pitch（舔爪低头）+ 侧偏
		_head.rotation = Vector3(
			_base_head.x + LICK_PITCH * _lick_env,
			_base_head.y + _look_yaw + _lick_side_yaw * _lick_env,
			_base_head.z)
		# 眼睑：0=张开 1=闭合
		var lid_rot := lerpf(LID_OPEN, LID_CLOSED, _lid_amt)
		for lid in _lids:
			lid.rotation.x = lid_rot
		# 完全闭眼时隐藏眼球，避免高亮虹膜从眼睑边缘透出（高亮件 self_lit+glow 很亮）
		var eye_hidden := _lid_amt > 0.92
		for eye in _eyes:
			(eye as Node3D).visible = not eye_hidden
		# 耳朵：抽动（向后快速压）
		for i in range(_ears.size()):
			var rot: Vector3 = _base_ears[i]
			if int(_ear["side"]) == 2 or int(_ear["side"]) == i:
				rot.x -= _ear_off
			_ears[i].rotation = rot
		# 前爪：舔爪时抬起一侧（抬 0.12 + 微前倾）
		for i in range(_front_legs.size()):
			var base: Dictionary = _base_legs[i]
			var pos: Vector3 = base["pos"]
			var rot: Vector3 = base["rot"]
			if int(_lick["side"]) == i:
				pos.y += LICK_RAISE * _lick_env
				rot.x += LICK_LEG_TILT * _lick_env
			_front_legs[i].position = pos
			_front_legs[i].rotation = rot

	## 动作日志/探针断言用快照（不含网格数据）。
	func debug_state() -> Dictionary:
		var tail_y: Array = []
		var tail_x: Array = []
		for i in range(_tail.size()):
			tail_y.append(snappedf(_tail[i].rotation.y - _base_tail[i].y, 0.0001))
			tail_x.append(snappedf(_tail[i].rotation.x - _base_tail[i].x, 0.0001))
		var hist := {}
		for k in _history.keys():
			hist[k] = (_history[k] as Array).duplicate()
		return {
			"t": snappedf(_t, 0.0001),
			"seed": _seed_used,
			"breath_period": snappedf(_breath_period, 0.001),
			"breath_scale": snappedf(_body.scale.y, 0.0001) if _body != null else 1.0,
			"lid_amount": snappedf(_lid_amt, 0.0001),
			"lid_rot": snappedf(_lids[0].rotation.x, 0.0001) if _lids.size() > 0 else 0.0,
			"ear_flick": snappedf(_ear_off, 0.0001),
			"look_yaw": snappedf(_look_yaw, 0.0001),
			"lick_env": snappedf(_lick_env, 0.0001),
			"head_yaw": snappedf(_head.rotation.y - _base_head.y, 0.0001) if _head != null else 0.0,
			"head_pitch": snappedf(_head.rotation.x - _base_head.x, 0.0001) if _head != null else 0.0,
			"tail_y": tail_y,
			"tail_x": tail_x,
			"counts": _counts.duplicate(true),
			"history": hist,
			"next": {
				"blink": snappedf(float(_blink["next"]), 0.001),
				"ear": snappedf(float(_ear["next"]), 0.001),
				"look": snappedf(float(_look["next"]), 0.001),
				"lick": snappedf(float(_lick["next"]), 0.001),
			},
			"active": {
				"blink": bool(_blink["active"]),
				"ear": bool(_ear["active"]),
				"look": bool(_look["active"]),
				"lick": bool(_lick["active"]),
			},
			"driver_processing": driver.is_processing() if driver != null else false,
			"driver_can_process": driver.can_process() if driver != null else false,
		}

	## 仅截图/调试用：清空所有进行中的动作并回到中性姿态（不影响随机计数）。
	func debug_clear_events() -> void:
		for timer in [_blink, _ear, _look, _lick]:
			timer["active"] = false
		_reset_pose()

	## 仅截图/调试用：把某类动作强行推进到指定相位（0..1），不改其他动作。
	## side_override：仅 ear 用，-1=随机，0 左耳 / 1 右耳 / 2 双耳（截图取证用）。
	func debug_force_event(kind: String, phase: float = 0.5, side_override: int = -1) -> void:
		var p := clampf(phase, 0.0, 0.999)
		match kind:
			"blink":
				_blink["active"] = true
				_blink["t0"] = _t - BLINK_TOTAL * p
			"ear":
				_ear["active"] = true
				_ear["side"] = side_override if side_override >= 0 else _rng.randi_range(0, 2)
				_ear["t0"] = _t - EAR_EVENT_DUR * p
			"look":
				if not bool(_look["active"]):
					_look["yaw"] = LOOK_YAW * (0.9 if _rng.randf() < 0.62 else -0.9)
					_look["hold"] = _rng.randf_range(LOOK_HOLD_MIN, LOOK_HOLD_MAX)
					_look["dur"] = LOOK_TURN + float(_look["hold"]) + LOOK_BACK
				_look["active"] = true
				_look["t0"] = _t - float(_look["dur"]) * p
			"lick":
				if not bool(_lick["active"]):
					_lick["side"] = _rng.randi_range(0, maxi(_front_legs.size() - 1, 0))
					_lick["hold"] = _rng.randf_range(LICK_HOLD_MIN, LICK_HOLD_MAX)
					_lick["dur"] = LICK_UP + float(_lick["hold"]) + LICK_DOWN
				_lick_active_side_setup()
				_lick["active"] = true
				_lick["t0"] = _t - float(_lick["dur"]) * p
		# 立即把姿态应用一次（advance(0) 不推进时间）
		_apply_face_and_limbs()

	func _lick_active_side_setup() -> void:
		_lick_side_yaw = LICK_SIDE_YAW * (1.0 if int(_lick["side"]) == 0 else -1.0)

# ===========================================================================
# 构建：静态几何 + 可动部件分组（只为可动部件建枢轴节点，网格只建一次）
# ===========================================================================
## 在 parent（Cottage root）下创建名为 "PorchCat" 的猫根节点：
##   pos = 门廊木板顶面局部坐标（世界 0.47），yaw = 朝向（模型 +Z 朝前）。
## opts: seed(int，-1=随机)、idle(bool，默认 true)、shadow(bool，默认 true)。
static func build(parent: Node3D, pos: Vector3, yaw: float = -0.6, opts: Dictionary = {}) -> Dictionary:
	var root := Node3D.new()
	root.name = "PorchCat"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)
	root.set_meta("isle_cat", true)
	# 猫是逐帧待机动画主体（呼吸/眨眼/张望/舔爪/尾巴链），任何一个部件都不能被
	# 静态合批吞掉，否则动画会失去独立的枢轴节点。这里用 no_batch 契约显式声明。
	root.set_meta("no_batch", true)

	# ---------------- 身体（呼吸组：只 scale y，不影响腿/尾/头） ----------------
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	_build_body(body)

	# ---------------- 头（颈枢轴：yaw/pitch 动画都绕此） ----------------
	var head := Node3D.new()
	head.name = "Head"
	head.position = HEAD_PIVOT * CAT_MODEL_SCALE
	head.rotation.x = -0.04
	root.add_child(head)
	var head_core := Node3D.new()
	head_core.name = "HeadCore"
	head_core.position = HEAD_CORE_OFFSET * CAT_MODEL_SCALE
	head.add_child(head_core)
	var head_parts := _build_head(head_core)

	# ---------------- 尾巴（3 节链，根连身体后侧） ----------------
	var tail := Node3D.new()
	tail.name = "Tail"
	tail.position = Vector3(0.02, 0.17, -0.33) * CAT_MODEL_SCALE
	root.add_child(tail)
	var tail_joints := _build_tail(tail)

	# ---------------- 腿/爪（静态，前腿枢轴可抬；后腿收拢） ----------------
	var legs := Node3D.new()
	legs.name = "Legs"
	root.add_child(legs)
	var leg_parts := _build_legs(legs)

	# ---------------- 脚下软阴影（吸附地面，避免悬空感） ----------------
	var shadow: MeshInstance3D = null
	if bool(opts.get("shadow", true)):
		shadow = M.shadow_blob(root, Vector3(0.0, 0.0, 0.02) * CAT_MODEL_SCALE, 0.42 * CAT_MODEL_SCALE, 0.30 * CAT_MODEL_SCALE)

	# ---------------- 待机驱动 ----------------
	var idle = null
	var driver = null
	if bool(opts.get("idle", true)):
		driver = CatIdleDriver.new()
		driver.name = "CatIdleDriver"
		root.add_child(driver)
		var parts := {
			"body": body,
			"head": head,
			"ears": head_parts["ears"],
			"eyelids": head_parts["eyelids"],
			"tail": tail_joints,
			"front_legs": leg_parts["front_legs"],
		}
		idle = CatIdle.new(parts, int(opts.get("seed", -1)))
		idle.driver = driver
		driver.controller = idle

	return {
		"root": root,
		"body": body,
		"head": head,
		"head_core": head_core,
		"ears": head_parts["ears"],
		"eyes": head_parts["eyes"],
		"eyelids": head_parts["eyelids"],
		"whiskers": head_parts["whiskers"],
		"tail": tail_joints,
		"legs": legs,
		"front_legs": leg_parts["front_legs"],
		"paws": leg_parts["paws"],
		"shadow": shadow,
		"driver": driver,
		"idle": idle,
	}

# ---------------------------------------------------------------------------
# 身体：坐姿前高后低的倾斜椭球 + 后臀 + 奶油胸脯
# ---------------------------------------------------------------------------
static func _build_body(body: Node3D) -> void:
	var s := CAT_MODEL_SCALE
	var torso := _ellipsoid(body, BODY_R * s, BODY_CENTER * s, C_FUR, Vector3(1.0, 0.80, 1.45), {"outline": 0.02, "rim": 0.10, "bands": 4.0})
	torso.name = "TorsoEllipsoid"
	torso.rotation.x = BODY_TILT
	# 后臀补形（坐姿重心，底部与躯干后缘共同贴地）
	_ellipsoid(body, 0.155 * s, Vector3(0.0, 0.185, -0.295) * s, C_FUR, Vector3(1.18, 0.82, 1.02), {"outline": 0.02, "rim": 0.10})
	# 奶油色胸脯/围兜（头下方）
	_ellipsoid(body, 0.105 * s, Vector3(0.0, 0.305, 0.160) * s, C_CREAM, Vector3(1.02, 1.05, 0.72), {"outline": 0.0, "rim": 0.05})
	_ellipsoid(body, 0.075 * s, Vector3(0.0, 0.160, 0.175) * s, C_CREAM, Vector3(0.92, 0.85, 0.55), {"outline": 0.0, "rim": 0.04})

# ---------------------------------------------------------------------------
# 头：头球 + 口鼻/鼻/嘴/颊/须 + 眼（扁球+竖瞳+高光）+ 眼睑 + 三角耳
# ---------------------------------------------------------------------------
static func _build_head(core: Node3D) -> Dictionary:
	var s := CAT_MODEL_SCALE
	var head_sphere := _ellipsoid(core, HEAD_R * s, Vector3.ZERO, C_FUR_HEAD, Vector3(1.03, 0.97, 1.0), {"outline": 0.02, "rim": 0.10, "bands": 4.0})
	head_sphere.name = "HeadEllipsoid"
	# 口鼻（奶油色宽吻）+ 两侧颊
	_ellipsoid(core, 0.062 * s, Vector3(0.0, -0.055, 0.128) * s, C_CREAM, Vector3(1.35, 0.80, 0.95), {"outline": 0.0, "rim": 0.05})
	for sx in [-1.0, 1.0]:
		_ellipsoid(core, 0.045 * s, Vector3(sx * 0.055, -0.050, 0.128) * s, C_CREAM, Vector3(1.0, 0.88, 0.85), {"outline": 0.0, "rim": 0.04})
	# 鼻 + 嘴（两条短线组成 V 形）
	_ellipsoid(core, 0.018 * s, Vector3(0.0, -0.026, 0.196) * s, C_NOSE, Vector3(1.25, 0.85, 0.72), {"outline": 0.0, "rim": 0.0})
	for sx in [-1.0, 1.0]:
		M.box_rot(core, Vector3(0.030, 0.007, 0.007) * s, Vector3(sx * 0.016, -0.063, 0.192) * s, Color("3a3330"), Vector3(0.0, 0.0, sx * 0.42), {"outline": 0.0, "rim": 0.0})
	# 下巴
	_ellipsoid(core, 0.030 * s, Vector3(0.0, -0.092, 0.145) * s, C_CREAM, Vector3(1.10, 0.70, 0.80), {"outline": 0.0, "rim": 0.02})

	# ---- 眼睛（扁球 + 竖瞳 + 高光点），眼睑枢轴在眼睛上方 ----
	# 注：toon.gdshader 中 self_lit=1 时 col = base * glow，glow 缺省 0 → 纯黑，
	# 所以自发光部件必须显式给 glow（瞳孔故意 glow=0 保持纯黑）。
	var eyes := Node3D.new()
	eyes.name = "Eyes"
	core.add_child(eyes)
	var eye_nodes: Array = []
	var lid_nodes: Array = []
	for sx in [-1.0, 1.0]:
		var eye := Node3D.new()
		eye.name = "EyeL" if sx < 0.0 else "EyeR"
		eye.position = Vector3(sx * 0.060, 0.045, 0.120) * s
		eyes.add_child(eye)
		_ellipsoid(eye, 0.048 * s, Vector3.ZERO, C_EYE, Vector3(0.82, 1.12, 0.50), {"outline": 0.0, "rim": 0.18, "glow": 1.05, "self_lit": true})
		_ellipsoid(eye, 0.023 * s, Vector3(0.0, 0.002, 0.028) * s, C_PUPIL, Vector3(0.58, 1.15, 0.34), {"outline": 0.0, "rim": 0.0, "self_lit": true})
		_ellipsoid(eye, 0.010 * s, Vector3(-0.014, 0.021, 0.041) * s, C_HILITE, Vector3(1.0, 1.0, 0.60), {"outline": 0.0, "rim": 0.0, "self_lit": true, "glow": 2.2})
		eye_nodes.append(eye)
		# 眼睑：毛色扁球，枢轴在眼睛上缘；张开时收进头内（rotation.x≈1.38），闭合时盖住眼睛
		var lid := Node3D.new()
		lid.name = "EyeLidL" if sx < 0.0 else "EyeLidR"
		lid.position = Vector3(sx * 0.060, 0.090, 0.110) * s
		lid.rotation.x = 1.38
		eyes.add_child(lid)
		_ellipsoid(lid, 0.054 * s, Vector3(0.0, -0.048, 0.030) * s, C_FUR_HEAD, Vector3(0.92, 1.06, 0.72), {"outline": 0.010, "rim": 0.08})
		lid_nodes.append(lid)

	# ---- 耳朵：3 棱锥（三角锥）外耳 + 浅色内耳 ----
	# 注：Godot 4.7.2 的 CylinderMesh 会把 radial_segments 钳到最小 4，故用 ArrayMesh
	#     精确构造 3 个侧面的三角锥（等价于 radial=3 的圆锥），满足造型要求。
	var ears: Array = []
	for sx in [-1.0, 1.0]:
		var ear := Node3D.new()
		ear.name = "EarL" if sx < 0.0 else "EarR"
		ear.position = Vector3(sx * 0.082, 0.104, 0.006) * s
		ear.rotation = Vector3(-0.10, sx * 0.16, -sx * 0.30)
		core.add_child(ear)
		_ear_mesh(ear, 0.085 * s, 0.140 * s, C_FUR_HEAD, {"outline": 0.015, "rim": 0.10})
		# 内耳比例直接烘进网格（0.95/0.95/0.70），不再用节点 scale（P7-V3.2 禁节点缩放）
		var inner := _ear_mesh(ear, 0.060 * s, 0.110 * s, C_EAR_IN, {"outline": 0.0, "rim": 0.02, "self_lit": true, "glow": 0.85}, Vector3(0.95, 0.95, 0.70))
		inner.position = Vector3(0.0, 0.028, 0.014) * s
		ears.append(ear)

	# ---- 胡须：每侧 3 根细圆柱 ----
	var whiskers: Array = []
	for sx in [-1.0, 1.0]:
		for i in range(3):
			var origin := Vector3(sx * 0.070, -0.048 + float(i) * 0.014, 0.145) * s
			var dir := Vector3(sx * 1.0, 0.28 - float(i) * 0.30, 0.35).normalized()
			var w := M.cyl(core, 0.0015 * s, 0.0022 * s, 0.115 * s, origin + dir * 0.058 * s, C_WHISKER, 0.0, {"outline": 0.0, "rim": 0.0})
			w.transform = Transform3D(_basis_y_to(dir), origin + dir * 0.058 * s)
			whiskers.append(w)

	return {"ears": ears, "eyes": eye_nodes, "eyelids": lid_nodes, "whiskers": whiskers}

# ---------------------------------------------------------------------------
# 尾巴：3 节关节链（根部连身体后侧），自然 S 形弯曲、抬起离地
# ---------------------------------------------------------------------------
# P7-V3.1 姿态微调（针对"低机位正面时尾巴从两耳之间露出、形成环状剪影"）：
#   原 j0.x=-0.55 / j1.x=-0.28 让尾巴整体上翘过高；配合 cat_close_front 机位
#   （相机高 0.80m 俯视 0.26m）的透视关系，尾巴虽在世界坐标里比头球顶低 9.8cm，
#   投影后仍高于头顶 0.042 NDC，正好卡在两耳中间 —— 已用"隐藏尾巴 A/B 截图"证实
#   （差异区域 (1171,53)-(1285,115) 即那个拱形）。
#   把 j0.x/-0.55→-0.74、j1.x/-0.28→-0.44（尾巴更向后展开、整体降低约 8cm），
#   投影后 dy=-0.077 NDC（低于头顶 7.7% 半屏），整周期 36/36 帧不再越界。
#   **j2 的前卷姿态与全部动画幅度一律不变**（猫咪尾巴仍然向前卷、仍在摆动）。
static func _build_tail(tail: Node3D) -> Array:
	var s := CAT_MODEL_SCALE
	var j0 := Node3D.new()
	j0.name = "TailJ0"
	j0.rotation = Vector3(-0.74, 0.12, 0.05)
	tail.add_child(j0)
	M.cyl(j0, 0.040 * s, 0.047 * s, 0.16 * s, Vector3(0.0, 0.080, 0.0) * s, C_FUR, 0.0, {"outline": 0.02, "rim": 0.10})
	_ellipsoid(j0, 0.043 * s, Vector3(0.0, 0.160, 0.0) * s, C_FUR, Vector3.ONE, {"outline": 0.015, "rim": 0.10})
	var j1 := Node3D.new()
	j1.name = "TailJ1"
	j1.position = Vector3(0.0, 0.160, 0.0) * s
	j1.rotation = Vector3(-0.44, -0.16, -0.05)
	j0.add_child(j1)
	M.cyl(j1, 0.034 * s, 0.040 * s, 0.15 * s, Vector3(0.0, 0.075, 0.0) * s, C_FUR, 0.0, {"outline": 0.02, "rim": 0.10})
	_ellipsoid(j1, 0.036 * s, Vector3(0.0, 0.150, 0.0) * s, C_FUR, Vector3.ONE, {"outline": 0.015, "rim": 0.10})
	var j2 := Node3D.new()
	j2.name = "TailJ2"
	j2.position = Vector3(0.0, 0.150, 0.0) * s
	j2.rotation = Vector3(0.55, -0.18, 0.10)
	j1.add_child(j2)
	M.cyl(j2, 0.024 * s, 0.033 * s, 0.13 * s, Vector3(0.0, 0.065, 0.0) * s, C_FUR_HEAD, 0.0, {"outline": 0.015, "rim": 0.10})
	_ellipsoid(j2, 0.030 * s, Vector3(0.0, 0.132, 0.0) * s, C_FUR_HEAD, Vector3.ONE, {"outline": 0.015, "rim": 0.10})
	return [j0, j1, j2]

# ---------------------------------------------------------------------------
# 腿：前腿直立（0.07 半径柱 + 压扁爪），后腿收拢（大腿球 + 折叠膝 + 后爪）
# ---------------------------------------------------------------------------
static func _build_legs(legs: Node3D) -> Dictionary:
	var s := CAT_MODEL_SCALE
	var front_legs: Array = []
	var paws: Array = []
	for sx in [-1.0, 1.0]:
		# 前腿枢轴在肩部，舔爪时整条腿抬起
		var fl := Node3D.new()
		fl.name = "FrontLegL" if sx < 0.0 else "FrontLegR"
		fl.position = Vector3(sx * 0.105, 0.345, 0.205) * s
		legs.add_child(fl)
		_ellipsoid(fl, 0.082 * s, Vector3(0.0, -0.010, 0.0) * s, C_FUR, Vector3.ONE, {"outline": 0.02, "rim": 0.10})
		M.cyl(fl, 0.070 * s, 0.058 * s, 0.31 * s, Vector3(0.0, -0.155, 0.012) * s, C_FUR, 0.0, {"outline": 0.02, "rim": 0.10})
		var paw := _ellipsoid(fl, 0.060 * s, Vector3(0.0, -0.312, 0.055) * s, C_FUR_HEAD, Vector3(1.05, 0.55, 1.35), {"outline": 0.015, "rim": 0.10})
		front_legs.append(fl)
		paws.append(paw)
		# 后腿收拢（贴在身体后侧，爪尖朝前）
		_ellipsoid(legs, 0.140 * s, Vector3(sx * 0.118, 0.160, -0.200) * s, C_FUR, Vector3(0.95, 0.95, 1.15), {"outline": 0.02, "rim": 0.10})
		_ellipsoid(legs, 0.078 * s, Vector3(sx * 0.138, 0.100, -0.020) * s, C_FUR, Vector3(0.95, 0.90, 1.0), {"outline": 0.02, "rim": 0.10})
		var hp := _ellipsoid(legs, 0.055 * s, Vector3(sx * 0.112, 0.028, 0.060) * s, C_FUR_HEAD, Vector3(1.0, 0.50, 1.45), {"outline": 0.015, "rim": 0.10})
		paws.append(hp)
	return {"front_legs": front_legs, "paws": paws}

# ---------------------------------------------------------------------------
# 静态辅助
# ---------------------------------------------------------------------------
## 椭球：把非均匀 scl 烘进 ArrayMesh 顶点/法线，节点 scale 恒为 1。
## P7-V3.2 尺度规范禁止用节点 scale 冒充重建，猫的所有椭球部件因此改为网格级烘焙。
static func _ellipsoid(parent: Node3D, radius: float, pos: Vector3, color: Color,
		scl: Vector3 = Vector3.ONE, opts: Dictionary = {}) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 14
	sm.rings = 8
	var arrays: Array = sm.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i] = Vector3(verts[i].x * scl.x, verts[i].y * scl.y, verts[i].z * scl.z)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in norms.size():
		norms[i] = Vector3(norms[i].x / scl.x, norms[i].y / scl.y, norms[i].z / scl.z).normalized()
	arrays[Mesh.ARRAY_NORMAL] = norms
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mi.mesh = am
	mi.material_override = M.toon_material(color, opts)
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

## 耳朵：3 棱锥（三角锥）。Godot 4.7.2 的 CylinderMesh 会把 radial_segments 钳到最小 4，
## 这里用 ArrayMesh 精确构造 3 个侧面 + 1 个底面（等价 radial=3 圆锥），底面在 y=0。
## scl 直接烘进顶点（内耳用），节点 scale 保持 1。
static func _ear_mesh(parent: Node3D, base_r: float, h: float, color: Color, mat_opts: Dictionary,
		scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _tri_cone_mesh(base_r, h, scl)
	mi.material_override = M.toon_material(color, mat_opts)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

## 3 棱锥网格：底面 3 个角点（y=0，一个角点朝 -Z）+ 顶点（0,h,0），3 侧面 + 1 底面。
## scl 把椭圆化比例烘进顶点（节点 scale 恒 1）。
static func _tri_cone_mesh(base_r: float, h: float, scl: Vector3 = Vector3.ONE) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base: Array = []
	for i in range(3):
		var ang: float = TAU * float(i) / 3.0 - PI * 0.5
		base.append(Vector3(cos(ang) * base_r * scl.x, 0.0, sin(ang) * base_r * scl.z))
	var apex := Vector3(0.0, h * scl.y, 0.0)
	var center := Vector3(0.0, h * 0.25, 0.0)
	for i in range(3):
		var a: Vector3 = base[i]
		var b: Vector3 = base[(i + 1) % 3]
		_add_flat_tri(st, a, b, apex, center)
	var b0: Vector3 = base[0]
	var b1: Vector3 = base[1]
	var b2: Vector3 = base[2]
	_add_flat_tri(st, b0, b1, b2, center)
	return st.commit()

## 加一个平直法线的三角形（按凸体外侧自动纠正绕序）。
static func _add_flat_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, center: Vector3) -> void:
	var n: Vector3 = (b - a).cross(c - a)
	if n.dot((a + b + c) / 3.0 - center) < 0.0:
		var tmp := b
		b = c
		c = tmp
		n = -n
	n = n.normalized()
	st.set_normal(n)
	st.add_vertex(a)
	st.set_normal(n)
	st.add_vertex(b)
	st.set_normal(n)
	st.add_vertex(c)

## 让圆柱的 +Y 轴对齐到 dir 的基（用于胡须摆放）。
static func _basis_y_to(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var ref := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)