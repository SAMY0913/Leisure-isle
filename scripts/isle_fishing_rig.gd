class_name IsleFishingRig
extends Node3D

## P6 / B —— 钓鱼视觉装配件（程序化鱼竿 / 世界空间鱼线 / 浮漂 / 水花水环 / 鱼获）。
##
## 设计约定：
## - 本文件只负责“看得见的东西”：不写库存、不做判定、不发游戏事件；
##   一切时机由调用方（IsleVillager 的钓鱼状态机）用 tick + 公开方法驱动。
## - 创建顺序：var rig = RIG_SCRIPT.new() → add_child(rig)（可选）→ rig.setup(villager, model_root, hand)。
##   setup 会把 rig 挂到村民 root 下，因此自动跟随村民移动 / 转向；重复调用 setup 会先拆后建（幂等）。
## - 节点结构（固定命名，便于外部 get_node 定位）：
##     IsleFishingRig / "FishingRig"
##       ├─ "Rod"    (Node3D) → "RodMesh" (MeshInstance3D，程序化低模竿)
##       ├─ "Line"   (MeshInstance3D，ImmediateMesh 每帧重建的细管)
##       ├─ "Bobber" (Node3D) → "BobberMesh" (MeshInstance3D，红白浮漂)
##       ├─ "Splash" (CPUParticles3D，一次性白/蓝水花)
##       ├─ "Ripple" (MeshInstance3D，程序化圆环，扩散渐隐)
##       └─ "Catch"  (Node3D) → "Fish" (MeshInstance3D，程序化鱼获)
## - 鱼竿不直接挂到手骨骼：每帧用“手的 global 变换 × 本地握持偏移”同步。这样 rig 被 free 时
##   所有视觉节点随父子关系一起释放，不会在村民身上留下孤儿节点。
## - 鱼线沿用 scripts/fx.gd 船尾迹的同类做法：同一个 ImmediateMesh 每帧 clear/重建三角面，
##   不新建 Mesh / 材质对象；顶点在 rig 本地空间（线随村民整体移动）。
## - 所有网格代码生成，复用 IsleMath.toon_material 顶点色缓存材质；暖色系（奶油 / 木色 / 红）。
## - tick(dt, true) 冻结全部视觉运动：浮漂、咬钩、水环、鱼获摆动都停，只同步鱼竿跟手。

const M := preload("res://scripts/isle_math.gd")

# ============================================================ 尺寸/调参 =====
# —— 鱼竿（本地 +Y 为竿身方向；握点≈原点；含竿尾总长 1.82 m）——
const ROD_TIP_Y := 1.62
const ROD_BUTT_Y := -0.20
const ROD_SIDES := 6

# —— P9 / P6-VISUAL-FIX：竿在世界里的真实指向 ——
# 旧实现把“握持基准”写成 **hand 空间** 的 (0,0.86,-0.51)，再整体乘 hand_r 的 global 变换；
# 而 hand_r 被整条手臂链（肩 1.12 + 肘 0.42 + 腕 -0.30 + 躯干 -0.05）累计转了约 1.19 rad，
# 于是竿身世界方向变成 (-0.45,0.79,-0.41)·角色朝向 = 朝上且**朝后**，竿尖落在脑后 0.6 m、
# 2.3 m 高处 —— 就是截图里的“肩扛”。手臂在 cast/reel 中还会继续转，同一个 hand 空间常量
# 无法同时满足 hold / cast / reel，因此改为：**位置跟手，朝向由角色前向 + 仰角直接定义**。
const ROD_HOLD_PITCH := 0.30     # 持竿仰角（相对水平面，+ = 竿尖上抬；17°）
const ROD_HOLD_SWAY := 0.0       # 持竿水平偏摆（相对角色正前，0 = 正对抛竿方向）
const ROD_PITCH_MIN := -1.30
const ROD_PITCH_MAX := 1.45

# —— 鱼线（细三棱管，比 1px 线在不同分辨率下更稳，且不出现 z-fighting）——
const LINE_SEGMENTS := 14
const LINE_R0 := 0.009
const LINE_R1 := 0.0045
const LINE_ANCHOR_Y := 0.055      # 鱼线挂在浮漂原点上方的高度
const LINE_DROP_MIN := 0.015
const LINE_DROP_MAX := 0.42

# —— 浮漂 / 水面 ——
const WATER_Y := 0.0              # 海平面世界高度
const BOB_AMP := 0.012            # 水面上下轻浮振幅
const BOB_FREQ := 2.4
const NIBBLE_TIME := 0.30         # 轻啄持续时间
const NIBBLE_AMP := 0.045         # 轻啄最大下沉
const BITE_TIME := 0.80           # 咬钩持续时间（与 isle_villager.gd FISH_BITE_TIME 对齐）
const BITE_SINK := 0.105          # 咬钩最大下沉（≈0.10 m）
const HANG_DROP := 0.50           # 收线/待机时浮漂悬在竿尖下方的距离（短吊线，不悬在半空）
const RIPPLE_TIME := 0.78
const RIPPLE_BASE_R := 0.22
const RIPPLE_Y := 0.008           # 略高于水面，避免与水面共面

# —— 鱼获 ——
const FISH_DEFAULT_COLOR := Color(0.86, 0.60, 0.36)
const FISH_DEFAULT_SIZE := 0.32
const FISH_MIN_VIS := 0.12
const FISH_MAX_VIS := 0.46
const CATCH_FORWARD := 0.34       # 鱼获在胸前的“前方”偏移（村民本地 -Z）
const CATCH_RIGHT := 0.26         # 略偏右肩，避免被躯干完全挡住
const CATCH_UP := 0.22
const CATCH_BOB := 0.012

# —— 状态机（内部）——
const MODE_HANG := 0
const MODE_CAST := 1
const MODE_FLOAT := 2
const MODE_REEL := 3

# —— P7-UX 抛竿 / 收线挥杆 ——
# 抛竿不是“竿尖恒定前指”：先向后上引竿（蓄力），再向前甩出，浮漂在甩出的瞬间才离竿。
# 这些比例都相对 start_cast 传入的 duration（= 村民 fish_cast 动画 1.2 s），不改变任何玩法计时。
const CAST_LAUNCH_FRAC := 0.50   # 甩出（释放浮漂）发生在抛竿时长的 50%（= 模型 fish_cast 释放帧）
const ROD_IDLE_SWAY_PITCH := 0.018
const ROD_IDLE_SWAY_ROLL := 0.012

# —— 暖色板（奶油 / 木色 / 红点缀）——
const C_ROD_WOOD := Color(0.474, 0.318, 0.208)
const C_ROD_WOOD_LIGHT := Color(0.627, 0.463, 0.310)
const C_ROD_GRIP := Color(0.902, 0.804, 0.627)
const C_ROD_ACCENT := Color(0.780, 0.278, 0.220)
const C_REEL := Color(0.341, 0.250, 0.188)
const C_REEL_SPOOL := Color(0.878, 0.780, 0.619)
const C_BOBBER_RED := Color(0.859, 0.243, 0.180)
const C_BOBBER_WHITE := Color(0.961, 0.949, 0.902)
const C_LINE := Color(0.933, 0.921, 0.839)
const C_SPLASH := Color(0.902, 0.961, 1.000)
const C_RIPPLE := Color(0.902, 0.969, 1.000)
const C_FISH_BELLY := Color(0.973, 0.933, 0.824)

# —— 节点名 ——
const NODE_ROD := "Rod"
const NODE_ROD_MESH := "RodMesh"
const NODE_LINE := "Line"
const NODE_BOBBER := "Bobber"
const NODE_BOBBER_MESH := "BobberMesh"
const NODE_SPLASH := "Splash"
const NODE_RIPPLE := "Ripple"
const NODE_CATCH := "Catch"
const NODE_FISH := "Fish"

# ============================================================ 运行时状态 =====
var _built := false

var _villager: Node3D = null
var _model_root: Node3D = null
var _hand: Node3D = null

var _rod: Node3D = null
var _rod_mi: MeshInstance3D = null
# 竿的世界指向诊断（探针断言用）：持竿方向 = 角色前向绕 +Y 偏摆、再抬仰角。
var _rod_dir_world := Vector3(0.0, 0.0, -1.0)
# P7-UX：竿的姿态偏移（相对持竿基准仰角），由抛竿/咬钩/收线关键帧驱动。
var _rod_pose_pitch := 0.0
var _rod_pose_roll := 0.0
var _rod_anim := ""              # "" | "cast" | "reel" | "bite"
var _rod_anim_t := 0.0
var _rod_anim_dur := 0.0

var _line_mi: MeshInstance3D = null
var _line_im: ImmediateMesh = null
var _line_pts := PackedVector3Array()
var _line_has_points := false
var _line_on := true

var _bobber: Node3D = null
var _bobber_mi: MeshInstance3D = null

var _splash: CPUParticles3D = null

var _ripple: MeshInstance3D = null
var _ripple_mat: StandardMaterial3D = null

var _catch: Node3D = null
var _fish_mi: MeshInstance3D = null
var _catch_base_local := Vector3(0.0, 1.18, -0.36)
var _catch_euler_base := Vector3.ZERO

var _mat_toon: ShaderMaterial = null
var _mat_line: StandardMaterial3D = null
var _mat_splash: StandardMaterial3D = null

# 视觉开关
var _rod_on := false
var _bobber_visible := false
var _catch_visible := false

# 浮漂状态机
var _bobber_mode := MODE_HANG
var _target := Vector3.ZERO
var _bob_pos := Vector3.ZERO
var _bob_phase := 0.0

var _cast_from := Vector3.ZERO
var _cast_to := Vector3.ZERO
var _cast_t := 0.0
var _cast_dur := 1.0
var _cast_active := false
# P7-UX：浮漂在“甩出”帧之前一直停在竿尖，甩出后才开始抛物线飞行。
var _cast_launched := false
var _cast_launch_from := Vector3.ZERO

var _reel_from := Vector3.ZERO
var _reel_t := 0.0
var _reel_dur := 0.8
var _reel_active := false

var _nibble_t := 0.0
var _nibble_amp := 0.0
var _nibble_active := false

var _bite_t := 0.0
var _bite_active := false

var _ripple_t := 0.0
var _ripple_dur := RIPPLE_TIME
var _ripple_r := 0.55
var _ripple_active := false

var _catch_phase := 0.0
var _fish_id := ""
var _fish_length := FISH_DEFAULT_SIZE
var _fish_color := FISH_DEFAULT_COLOR

# 诊断计数（探针 / 联调用，不参与玩法逻辑）
var _splash_events := 0
var _ripple_events := 0

# 鱼类目录脚本防御式加载（isle_fish.gd 可能尚不存在）
var _fish_script_checked := false
var _fish_script_res: Script = null


# ============================================================ 公开 API =====

## 构建全部视觉节点并把 rig 挂到村民 root 下。
## 幂等：重复调用会先释放旧节点再重建；villager / model_root / hand 允许为 null（不崩）。
func setup(villager: Node3D, model_root: Node3D, hand_joint: Node3D) -> void:
	if _built:
		_teardown()
	_villager = villager
	_model_root = model_root
	_hand = hand_joint
	# 挂到村民 root 下（自动跟随）；已挂好则不动
	if _villager != null and is_instance_valid(_villager) and get_parent() != _villager:
		var old := get_parent()
		if old != null:
			old.remove_child(self)
		_villager.add_child(self)
	transform = Transform3D.IDENTITY
	name = "FishingRig"
	_build_nodes()
	_compute_catch_anchor()
	_sync_rod()
	_apply_visibility()
	_built = true
	# 初帧先把线摆好（避免第一帧线在原点闪一下）
	_bob_phase = 0.0
	_bob_pos = rod_tip_world() + Vector3(0.0, -HANG_DROP, 0.0)
	if _bobber != null:
		_bobber.global_position = _bob_pos
	_rebuild_line()


## 竿尖世界坐标（未 setup 时返回 Vector3.ZERO）。
func rod_tip_world() -> Vector3:
	if not _built or _rod == null:
		return Vector3.ZERO
	return _rod.global_transform * Vector3(0.0, ROD_TIP_Y, 0.0)


## 握竿手的世界坐标（没有手时退回竿身原点 / rig 原点）。
func hand_world() -> Vector3:
	if _hand != null and is_instance_valid(_hand):
		return _hand.global_position
	if _built and _rod != null:
		return _rod.global_transform.origin
	return Vector3.ZERO


## 鱼竿显隐（隐藏时鱼线一并隐藏）。
func show_rod(on: bool = true) -> void:
	_rod_on = on
	if _rod != null:
		_rod.visible = on
	if not on and _line_mi != null:
		_line_mi.visible = false
		_line_has_points = false


## 鱼线显隐开关（实际可见还需要竿可见 + 浮漂可见）。
func set_line_visible(on: bool = true) -> void:
	_line_on = on
	if not on and _line_mi != null:
		_line_mi.visible = false
		_line_has_points = false


## 抛竿：浮漂从竿尖沿抛物线飞到 target，duration 秒后落水并溅水花/推水环。
## 纯视觉，不做任何判定。
func start_cast(target: Vector3, duration: float) -> void:
	if not _built:
		return
	_sync_rod()
	_target = Vector3(target.x, WATER_Y, target.z)
	_cast_to = _target
	_cast_from = rod_tip_world()
	if _cast_from.distance_squared_to(_cast_to) < 0.0001:
		_cast_from = _cast_to + Vector3(0.0, 0.6, 0.0)
	_cast_t = 0.0
	_cast_dur = maxf(duration, 0.05)
	_cast_active = true
	_cast_launched = false
	_cast_launch_from = _cast_from
	_reel_active = false
	_bobber_mode = MODE_CAST
	_bob_pos = _cast_from
	_bobber_visible = true
	# P7-UX：先向后上方蓄力，再向前甩出；浮漂在甩出帧才离竿。
	_start_rod_anim("cast", _cast_dur)
	if _bobber != null:
		_bobber.visible = true
		_bobber.global_position = _bob_pos


## 设置浮漂的水面目标点（y 强制为水平面；不在抛/收线中会立即浮到该点）。
func set_bobber_target(pos: Vector3) -> void:
	if not _built:
		return
	_target = Vector3(pos.x, WATER_Y, pos.z)
	if _cast_active or _reel_active:
		return
	_bobber_mode = MODE_FLOAT
	_bob_pos = Vector3(_target.x, WATER_Y, _target.z)
	if _bobber != null:
		_bobber.global_position = _bob_pos


## 浮漂显隐（隐藏时鱼线一并隐藏）。
func set_bobber_visible(on: bool = true) -> void:
	if not _built:
		return
	_bobber_visible = on
	if _bobber != null:
		_bobber.visible = on
	if not on and _line_mi != null:
		_line_mi.visible = false
		_line_has_points = false


## 浮漂当前世界坐标（未 setup 时 Vector3.ZERO）。
func bobber_world() -> Vector3:
	if not _built or _bobber == null:
		return Vector3.ZERO
	return _bobber.global_position


## 轻啄：strength 0..1，播放一次 0.30 s 的小幅下沉（咬钩前的信号）。
func nibble(strength: float) -> void:
	if not _built:
		return
	_nibble_active = true
	_nibble_t = 0.0
	_nibble_amp = clampf(strength, 0.0, 1.0)


## 咬钩：0.105 m 猛沉 + 水面水花 + 扩散水环。
func bite() -> void:
	if not _built:
		return
	_bite_active = true
	_bite_t = 0.0
	# P7-UX：咬钩瞬间竿尖向下急抽一下（与浮漂猛沉同步）。
	_start_rod_anim("bite", BITE_TIME)
	if _bobber_visible:
		_emit_splash(_bob_pos)
		_emit_ripple(_bob_pos, 0.85)


## 收线：浮漂在 duration 秒内回到竿尖下方（收尾后悬挂跟随竿尖）。
func start_reel(duration: float) -> void:
	if not _built:
		return
	_reel_from = _bob_pos
	_reel_t = 0.0
	_reel_dur = maxf(duration, 0.05)
	_reel_active = true
	_cast_active = false
	_bobber_mode = MODE_REEL
	# P7-UX：收线时抬竿 / 抽竿两把，竿身不再恒定前指。
	_start_rod_anim("reel", _reel_dur)


## 展示鱼获：程序化低模鱼挂在胸前偏右；fish_id 用 isle_fish.gd 的目录取颜色/体长范围。
## size 为体长（米）；<=0 用默认 0.32 m；有目录定义时夹在 min_size..max_size 内。
func show_catch(fish_id: String, size: float) -> void:
	if not _built or _catch == null or _fish_mi == null:
		return
	_compute_catch_anchor()
	var info := _resolve_fish(fish_id, size)
	_fish_id = fish_id
	_fish_length = float(info.get("length", FISH_DEFAULT_SIZE))
	_fish_color = info.get("color", FISH_DEFAULT_COLOR)
	_fish_mi.mesh = _build_fish_mesh(_fish_color)
	_fish_mi.scale = Vector3.ONE * _fish_length
	_fish_mi.visible = true
	_catch.visible = true
	_catch_visible = true
	_catch_phase = 0.0
	_catch.transform = Transform3D(_catch_basis(), _catch_base_local)


## 隐藏鱼获。
func hide_catch() -> void:
	_catch_visible = false
	if _catch != null:
		_catch.visible = false
	if _fish_mi != null:
		_fish_mi.visible = false


## 收起全部视觉：竿 / 线 / 浮漂 / 鱼获 / 粒子 / 水环全部隐藏并复位。
## 可重复调用，也可在 hide / 未 setup / 半释放状态下安全调用。
func clear_all() -> void:
	if not _built:
		return
	_rod_on = false
	_line_on = true
	_bobber_visible = false
	_catch_visible = false
	_cast_active = false
	_cast_launched = false
	_reel_active = false
	_nibble_active = false
	_bite_active = false
	_ripple_active = false
	_bobber_mode = MODE_HANG
	_rod_anim = ""
	_rod_pose_pitch = 0.0
	_rod_pose_roll = 0.0
	if _splash != null:
		_splash.emitting = false
	if _ripple != null:
		_ripple.visible = false
	if _line_mi != null:
		_line_mi.visible = false
		_line_has_points = false
	_apply_visibility()


## 每帧驱动：paused 时冻结所有视觉运动与计时，只同步鱼竿跟手。
func tick(dt: float, paused: bool) -> void:
	if not _built:
		return
	if paused:
		# 暂停时竿姿态与浮漂都停在上一帧，只保持跟手。
		_sync_rod()
		return
	var step := clampf(dt, 0.0, 0.1)
	_bob_phase += step
	_update_rod_pose(step)
	_sync_rod()
	_update_bobber(step)
	_update_ripple(step)
	_update_catch(step)
	_rebuild_line()


# ============================================================ 竿姿态动画 =====

## 开始一段竿姿态动画：cast = 后引蓄力 → 前甩抛饵；reel = 两把抬竿抽竿；bite = 竿尖急抽。
func _start_rod_anim(kind: String, duration: float) -> void:
	_rod_anim = kind
	_rod_anim_t = 0.0
	_rod_anim_dur = maxf(duration, 0.05)


func _update_rod_pose(step: float) -> void:
	if _rod_anim == "":
		# 待机 / 等待咬钩：保持自然持竿，只做极轻微呼吸摆动（不是死板前指）。
		_rod_pose_pitch = sin(_bob_phase * 1.35) * ROD_IDLE_SWAY_PITCH
		_rod_pose_roll = sin(_bob_phase * 0.82) * ROD_IDLE_SWAY_ROLL
		return
	_rod_anim_t += step
	var u := clampf(_rod_anim_t / _rod_anim_dur, 0.0, 1.0)
	var pr := _rod_pose_keys(_rod_anim, u)
	_rod_pose_pitch = pr.x
	_rod_pose_roll = pr.y
	if u >= 1.0:
		_rod_anim = ""
		_rod_pose_pitch = 0.0
		_rod_pose_roll = 0.0


## 关键帧格式 Vector3(u, pitch, roll)，两者都是**相对持竿基准**的偏移：
##   pitch > 0 = 竿尖上抬（后摆蓄力），pitch < 0 = 竿尖下压前甩（抛投），roll = 水平偏摆。
## 真实仰角 = ROD_HOLD_PITCH + pitch，所以 u=0.30 的 1.05 表示竿尖抬到 77°，u=0.48 的 -0.61
## 表示甩到水平下方 18°（竿尖从身前掠过）。整段弧线在“角色前向的竖直平面”内。
func _rod_pose_keys(kind: String, u: float) -> Vector2:
	match kind:
		"cast":
			return _sample_pose([
				Vector3(0.00, 0.00, 0.00),
				Vector3(0.14, 0.38, 0.06),
				Vector3(0.30, 1.05, 0.14),
				Vector3(0.38, 0.98, 0.12),
				Vector3(0.48, -0.61, -0.06),
				Vector3(0.62, -0.40, -0.03),
				Vector3(0.84, -0.02, 0.00),
				Vector3(1.00, 0.00, 0.00),
			], u)
		"reel":
			# 提竿两把：仰角抬高 → 松一点 → 再提 → 回到持竿（不是把竿甩到身后）。
			return _sample_pose([
				Vector3(0.00, 0.00, 0.00),
				Vector3(0.10, 0.16, 0.02),
				Vector3(0.24, 0.62, 0.08),
				Vector3(0.36, 0.68, 0.09),
				Vector3(0.50, 0.18, 0.02),
				Vector3(0.64, 0.60, 0.07),
				Vector3(0.78, 0.16, 0.01),
				Vector3(1.00, 0.00, 0.00),
			], u)
		"bite":
			return _sample_pose([
				Vector3(0.00, 0.00, 0.00),
				Vector3(0.12, -0.32, -0.06),
				Vector3(0.26, 0.22, 0.05),
				Vector3(0.40, -0.14, -0.03),
				Vector3(0.55, 0.08, 0.02),
				Vector3(1.00, 0.00, 0.00),
			], u)
	return Vector2.ZERO


func _sample_pose(keys: Array, u: float) -> Vector2:
	for i in range(keys.size() - 1):
		var a: Vector3 = keys[i]
		var b: Vector3 = keys[i + 1]
		if u <= b.x:
			var t := 0.0 if b.x <= a.x else smoothstep(0.0, 1.0, (u - a.x) / (b.x - a.x))
			return Vector2(lerpf(a.y, b.y, t), lerpf(a.z, b.z, t))
	var last: Vector3 = keys[keys.size() - 1]
	return Vector2(last.y, last.z)


## 调试 / 探针用诊断信息（不参与玩法）。
func debug_info() -> Dictionary:
	return {
		"built": _built,
		"rod_visible": _rod_on,
		"line_visible": _line_mi != null and _line_mi.visible,
		"line_has_points": _line_has_points,
		"bobber_visible": _bobber_visible,
		"bobber_mode": _bobber_mode,
		"catch_visible": _catch_visible,
		"rod_tip_world": rod_tip_world(),
		"hand_world": hand_world(),
		"bobber_world": bobber_world(),
		"line_points": _line_pts,
		"fish_id": _fish_id,
		"fish_length": _fish_length,
		"fish_color": _fish_color,
		"splash_events": _splash_events,
		"ripple_events": _ripple_events,
		"splash_emitting": _splash != null and _splash.emitting,
		"ripple_visible": _ripple != null and _ripple.visible,
		# P7-UX：挥杆姿态诊断（探针断言用）。
		"rod_pose_pitch": _rod_pose_pitch,
		"rod_pose_roll": _rod_pose_roll,
		"rod_anim": _rod_anim,
		"cast_launched": _cast_launched,
		# P9 / P6-VISUAL-FIX：竿在世界里到底朝哪（真实窗口验收的硬判据）。
		"rod_dir_world": _rod_dir_world,
		"rod_pitch_world": ROD_HOLD_PITCH + _rod_pose_pitch,
		"rod_forward_dot": _rod_forward_dot(),
		"rod_tip_forward_m": _rod_tip_forward_m(),
		"rod_tip_above_water": rod_tip_world().y - WATER_Y,
		"nibble_active": _nibble_active,
		"nibble_amp": _nibble_amp,
		"bob_phase": _bob_phase,
	}


# ============================================================ 构建 =========

func _build_nodes() -> void:
	_mat_toon = M.toon_material(Color.WHITE, {"vertex_color": true, "rim": 0.12})
	# —— 鱼竿 ——
	_rod = Node3D.new()
	_rod.name = NODE_ROD
	add_child(_rod)
	_rod_mi = MeshInstance3D.new()
	_rod_mi.name = NODE_ROD_MESH
	_rod_mi.mesh = _build_rod_mesh()
	_rod_mi.material_override = _mat_toon
	_rod_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rod.add_child(_rod_mi)
	# P9 / P6-VISUAL-FIX：竿的朝向不再预烘到 hand 空间里。_sync_rod() 每帧用
	# “角色前向 + 仰角/偏摆”直接构造世界基（见 ROD_HOLD_PITCH 注释），这里只留状态初始化。
	_rod_dir_world = Vector3(0.0, 0.0, -1.0)
	_rod_pose_pitch = 0.0
	_rod_pose_roll = 0.0
	_rod_anim = ""
	_rod.visible = false

	# —— 鱼线 ——
	_line_im = ImmediateMesh.new()
	_line_mi = MeshInstance3D.new()
	_line_mi.name = NODE_LINE
	_line_mi.mesh = _line_im
	_line_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_line_mi.extra_cull_margin = 8.0
	_line_mi.visible = false
	_mat_line = StandardMaterial3D.new()
	_mat_line.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_line.albedo_color = C_LINE
	_mat_line.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_line.disable_receive_shadows = true
	_line_mi.material_override = _mat_line
	add_child(_line_mi)
	_line_pts.resize(LINE_SEGMENTS + 1)

	# —— 浮漂 ——
	_bobber = Node3D.new()
	_bobber.name = NODE_BOBBER
	add_child(_bobber)
	_bobber_mi = MeshInstance3D.new()
	_bobber_mi.name = NODE_BOBBER_MESH
	_bobber_mi.mesh = _build_bobber_mesh()
	_bobber_mi.material_override = _mat_toon
	_bobber_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bobber.add_child(_bobber_mi)
	_bobber.visible = false

	# —— 水花粒子（一次性，白→蓝）——
	_splash = CPUParticles3D.new()
	_splash.name = NODE_SPLASH
	_splash.amount = 22
	_splash.lifetime = 0.55
	_splash.one_shot = true
	_splash.emitting = false
	_splash.explosiveness = 0.92
	_splash.randomness = 0.45
	_splash.direction = Vector3(0.0, 1.0, 0.0)
	_splash.spread = 52.0
	_splash.initial_velocity_min = 0.9
	_splash.initial_velocity_max = 2.4
	_splash.gravity = Vector3(0.0, -7.5, 0.0)
	_splash.scale_amount_min = 0.035
	_splash.scale_amount_max = 0.10
	_splash.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_splash.emission_sphere_radius = 0.07
	_splash.local_coords = false
	_splash.visibility_aabb = AABB(Vector3(-3.0, -2.0, -3.0), Vector3(6.0, 5.0, 6.0))
	_splash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat_splash = StandardMaterial3D.new()
	_mat_splash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_splash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_splash.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat_splash.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_mat_splash.albedo_texture = M.soft_dot_texture(64)
	_mat_splash.albedo_color = C_SPLASH
	_mat_splash.vertex_color_use_as_albedo = true
	_mat_splash.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_mat_splash.disable_receive_shadows = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.material = _mat_splash
	_splash.mesh = quad
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.95),
		Color(0.80, 0.92, 1.0, 0.62),
		Color(0.55, 0.78, 0.95, 0.0),
	])
	_splash.color_ramp = grad
	add_child(_splash)

	# —— 水面扩散圆环 ——
	_ripple = MeshInstance3D.new()
	_ripple.name = NODE_RIPPLE
	_ripple.mesh = _build_ripple_mesh()
	_ripple.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ripple.extra_cull_margin = 2.0
	_ripple_mat = StandardMaterial3D.new()
	_ripple_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ripple_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ripple_mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	_ripple_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ripple_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_ripple_mat.disable_receive_shadows = true
	_ripple_mat.albedo_color = Color(C_RIPPLE.r, C_RIPPLE.g, C_RIPPLE.b, 0.0)
	_ripple.material_override = _ripple_mat
	_ripple.visible = false
	add_child(_ripple)

	# —— 鱼获 ——
	_catch = Node3D.new()
	_catch.name = NODE_CATCH
	_catch.visible = false
	add_child(_catch)
	_fish_mi = MeshInstance3D.new()
	_fish_mi.name = NODE_FISH
	_fish_mi.material_override = _mat_toon
	_fish_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fish_mi.visible = false
	_catch.add_child(_fish_mi)


## 拆掉本 rig 自建的所有节点（不碰外部节点）。
func _teardown() -> void:
	_free_child(_rod)
	_free_child(_line_mi)
	_free_child(_bobber)
	_free_child(_splash)
	_free_child(_ripple)
	_free_child(_catch)
	_rod = null
	_rod_mi = null
	_line_mi = null
	_line_im = null
	_bobber = null
	_bobber_mi = null
	_splash = null
	_ripple = null
	_ripple_mat = null
	_catch = null
	_fish_mi = null
	_mat_toon = null
	_mat_line = null
	_mat_splash = null
	_line_pts = PackedVector3Array()
	_line_has_points = false
	_built = false


func _free_child(n: Node) -> void:
	if n == null or not is_instance_valid(n):
		return
	if n.get_parent() == self:
		remove_child(n)
	n.free()


# ============================================================ 每帧更新 =====

## 角色当前朝向（纯偏航）。村民根节点只由 isle_villager._apply_pose() 设 rotation.y，
## 这里取 global 基的偏航分量，竿的指向因此与 face_yaw 严格同一坐标系。
func _facing_yaw() -> float:
	if _villager != null and is_instance_valid(_villager):
		return _villager.global_transform.basis.get_euler().y
	if _hand != null and is_instance_valid(_hand) and _hand.is_inside_tree():
		return _hand.global_transform.basis.get_euler().y
	return global_transform.basis.get_euler().y


## 竿在世界里的指向：角色前向 → 绕 +Y 偏摆 sway → 抬仰角 pitch。
## pitch = 0 时竿身水平指向角色正前方；pitch > 0 竿尖上抬；pitch < 0 竿尖向下。
func _rod_dir(pitch: float, sway: float) -> Vector3:
	var b := Basis(Vector3.UP, _facing_yaw())
	var fwd := b * Vector3(0.0, 0.0, -1.0)
	var right := b * Vector3(1.0, 0.0, 0.0)
	var flat := (fwd * cos(sway) + right * sin(sway)).normalized()
	var pp := clampf(pitch, ROD_PITCH_MIN, ROD_PITCH_MAX)
	return (flat * cos(pp) + Vector3.UP * sin(pp)).normalized()


func _sync_rod() -> void:
	if _rod == null:
		return
	var pitch := ROD_HOLD_PITCH + _rod_pose_pitch
	var sway := ROD_HOLD_SWAY + _rod_pose_roll
	var dir := _rod_dir(pitch, sway)
	_rod_dir_world = dir
	# 正交基：Y = 竿身方向，X = 横轴，Z = X×Y（行列式 +1，右手系）
	var x_axis := dir.cross(Vector3.UP)
	if x_axis.length_squared() < 0.000001:
		x_axis = (Basis(Vector3.UP, _facing_yaw()) * Vector3.RIGHT)
	x_axis = x_axis.normalized()
	var z_axis := x_axis.cross(dir).normalized()
	var grip := Vector3(0.0, 1.15, 0.0)
	if _hand != null and is_instance_valid(_hand) and _hand.is_inside_tree():
		# 只取手的 **位置**：握点仍贴着手，朝向不再被手腕旋转带偏。
		grip = _hand.global_position
	elif _villager != null and is_instance_valid(_villager):
		grip = _villager.global_position + Vector3(0.0, 1.15, 0.0) 			+ (Basis(Vector3.UP, _facing_yaw()) * Vector3(0.0, 0.0, -0.30))
	_rod.global_transform = Transform3D(Basis(x_axis, dir, z_axis), grip)
	_rod.visible = _rod_on


## 竿身方向与角色前向的夹角余弦（1 = 正前方，<0 = 朝后）。
func _rod_forward_dot() -> float:
	if not _built or _rod == null:
		return 0.0
	var b := Basis(Vector3.UP, _facing_yaw())
	var fwd := (b * Vector3(0.0, 0.0, -1.0)).normalized()
	return _rod_dir_world.dot(fwd)


## 竿尖在角色前方多少米（水平投影，负值 = 落在身后）。
func _rod_tip_forward_m() -> float:
	if not _built or _rod == null or _villager == null or not is_instance_valid(_villager):
		return 0.0
	var b := Basis(Vector3.UP, _facing_yaw())
	var fwd := (b * Vector3(0.0, 0.0, -1.0)).normalized()
	var rel := rod_tip_world() - _villager.global_position
	return Vector2(rel.x, rel.z).dot(Vector2(fwd.x, fwd.z))


func _update_bobber(step: float) -> void:
	var tip := rod_tip_world()
	if _cast_active:
		_cast_t += step
		if not _cast_launched:
			# 甩出之前，浮漂/饵跟着竿尖走：玩家能看清“后引蓄力 → 前甩”的整段挥杆。
			_bob_pos = rod_tip_world() + Vector3(0.0, 0.03, 0.0)
			_cast_launch_from = _bob_pos
			if _cast_t >= _cast_dur * CAST_LAUNCH_FRAC:
				_cast_launched = true
				_cast_launch_from = _bob_pos
		if _cast_launched:
			var flight_dur := maxf(_cast_dur * (1.0 - CAST_LAUNCH_FRAC), 0.05)
			var u := clampf((_cast_t - _cast_dur * CAST_LAUNCH_FRAC) / flight_dur, 0.0, 1.0)
			var arc := 0.35 + _cast_launch_from.distance_to(_cast_to) * 0.30
			var p := _cast_launch_from.lerp(_cast_to, u)
			p.y += sin(PI * u) * arc
			_bob_pos = p
			if u >= 1.0:
				_cast_active = false
				_bobber_mode = MODE_FLOAT
				_bob_pos = Vector3(_cast_to.x, WATER_Y, _cast_to.z)
				_emit_splash(_bob_pos)
				_emit_ripple(_bob_pos, 0.55)
	elif _reel_active:
		_reel_t += step
		var u := clampf(_reel_t / _reel_dur, 0.0, 1.0)
		var hang := tip + Vector3(0.0, -HANG_DROP, 0.0)
		var p := _reel_from.lerp(hang, u)
		p.y += sin(PI * u) * 0.12
		_bob_pos = p
		if u >= 1.0:
			_reel_active = false
			_bobber_mode = MODE_HANG
	elif _bobber_mode == MODE_FLOAT:
		var y := WATER_Y + sin(_bob_phase * BOB_FREQ) * BOB_AMP
		var x := _target.x
		var z := _target.z
		if _nibble_active:
			_nibble_t += step
			var un := _nibble_t / NIBBLE_TIME
			if un >= 1.0:
				_nibble_active = false
			else:
				y -= NIBBLE_AMP * _nibble_amp * sin(PI * un)
		if _bite_active:
			_bite_t += step
			var ub := _bite_t / BITE_TIME
			if ub >= 1.0:
				_bite_active = false
			else:
				var sink := sin(PI * clampf(ub * 1.55, 0.0, 1.0))
				y -= BITE_SINK * sink
				x += sin(_bite_t * 26.0) * 0.012
				z += cos(_bite_t * 23.0) * 0.010
		_bob_pos = Vector3(x, y, z)
	else:
		# 收线完成 / 待机：浮漂悬在竿尖下方轻晃
		_bob_pos = tip + Vector3(0.0, -HANG_DROP, 0.0)
		_bob_pos.x += sin(_bob_phase * 1.7) * 0.02
		_bob_pos.z += cos(_bob_phase * 1.3) * 0.02
	if _bobber != null:
		_bobber.global_position = _bob_pos
		_bobber.rotation = Vector3(0.0, sin(_bob_phase * 0.9) * 0.25, sin(_bob_phase * 1.5) * 0.06)


func _update_ripple(step: float) -> void:
	if not _ripple_active or _ripple == null or _ripple_mat == null:
		return
	_ripple_t += step
	var u := _ripple_t / _ripple_dur
	if u >= 1.0:
		_ripple_active = false
		_ripple.visible = false
		_ripple_mat.albedo_color = Color(C_RIPPLE.r, C_RIPPLE.g, C_RIPPLE.b, 0.0)
		return
	var grow := 1.0 - pow(1.0 - u, 2.0)
	var r := lerpf(RIPPLE_BASE_R, _ripple_r, grow)
	_ripple.scale = Vector3(r, 1.0, r)
	_ripple_mat.albedo_color = Color(C_RIPPLE.r, C_RIPPLE.g, C_RIPPLE.b, (1.0 - u) * 0.55)


func _update_catch(step: float) -> void:
	if not _catch_visible or _catch == null:
		return
	_catch_phase += step
	_catch.position = _catch_base_local + Vector3(0.0, sin(_catch_phase * 2.1) * CATCH_BOB, 0.0)
	_catch.rotation = _catch_euler_base + Vector3(
		sin(_catch_phase * 1.3) * 0.05,
		sin(_catch_phase * 0.9) * 0.10,
		sin(_catch_phase * 1.7) * 0.14)


func _rebuild_line() -> void:
	if _line_mi == null or _line_im == null:
		return
	if not (_rod_on and _line_on and _bobber_visible):
		_line_mi.visible = false
		_line_has_points = false
		return
	var tip := rod_tip_world()
	var anchor := _bob_pos + Vector3(0.0, LINE_ANCHOR_Y, 0.0)
	var dist := tip.distance_to(anchor)
	var sag := clampf(dist * 0.055, LINE_DROP_MIN, LINE_DROP_MAX)
	if _reel_active or _bite_active:
		sag *= 0.45
	# 采样点：抛物线近似悬链线下垂（两端精确落在竿尖 / 浮漂挂点）
	var inv := global_transform.affine_inverse()
	var n := LINE_SEGMENTS
	for i in range(n + 1):
		var u := float(i) / float(n)
		var p := tip.lerp(anchor, u)
		p.y -= sag * 4.0 * u * (1.0 - u)
		_line_pts[i] = inv * p
	_line_pts[0] = inv * tip
	_line_pts[n] = inv * anchor
	# 三条棱的细管（cull_disabled，绕序不重要）
	var im := _line_im
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(n):
		var p0: Vector3 = _line_pts[i]
		var p1: Vector3 = _line_pts[i + 1]
		var t0 := _line_tangent(i)
		var t1 := _line_tangent(i + 1)
		var r0 := lerpf(LINE_R0, LINE_R1, float(i) / float(n))
		var r1v := lerpf(LINE_R0, LINE_R1, float(i + 1) / float(n))
		var ref0 := Vector3.UP
		if absf(t0.dot(ref0)) > 0.98:
			ref0 = Vector3.RIGHT
		var n10 := t0.cross(ref0).normalized()
		var n20 := n10.cross(t0).normalized()
		var ref1 := Vector3.UP
		if absf(t1.dot(ref1)) > 0.98:
			ref1 = Vector3.RIGHT
		var n11 := t1.cross(ref1).normalized()
		var n21 := n11.cross(t1).normalized()
		var a0 := p0 + n10 * r0
		var a1 := p0 + n20 * r0
		var a2 := p0 - (n10 + n20) * r0
		var b0 := p1 + n11 * r1v
		var b1 := p1 + n21 * r1v
		var b2 := p1 - (n11 + n21) * r1v
		_add_line_tri(im, a0, a1, b1)
		_add_line_tri(im, a0, b1, b0)
		_add_line_tri(im, a1, a2, b2)
		_add_line_tri(im, a1, b2, b1)
		_add_line_tri(im, a2, a0, b0)
		_add_line_tri(im, a2, b0, b2)
	im.surface_end()
	_line_mi.visible = true
	_line_has_points = true


func _line_tangent(i: int) -> Vector3:
	var n := LINE_SEGMENTS
	var t: Vector3
	if i <= 0:
		t = _line_pts[1] - _line_pts[0]
	elif i >= n:
		t = _line_pts[n] - _line_pts[n - 1]
	else:
		t = _line_pts[i + 1] - _line_pts[i - 1]
	if t.length_squared() < 0.0000001:
		return Vector3.UP
	return t.normalized()


static func _add_line_tri(im: ImmediateMesh, a: Vector3, b: Vector3, c: Vector3) -> void:
	im.surface_add_vertex(a)
	im.surface_add_vertex(b)
	im.surface_add_vertex(c)


func _apply_visibility() -> void:
	if _rod != null:
		_rod.visible = _rod_on
	if _bobber != null:
		_bobber.visible = _bobber_visible
	if _catch != null:
		_catch.visible = _catch_visible
	if _fish_mi != null:
		_fish_mi.visible = _catch_visible
	if _line_mi != null and not (_rod_on and _line_on and _bobber_visible):
		_line_mi.visible = false


# ============================================================ 触发效果 =====

func _emit_splash(pos: Vector3) -> void:
	if _splash == null:
		return
	_splash.global_position = Vector3(pos.x, WATER_Y + 0.02, pos.z)
	_splash.restart()
	_splash.emitting = true
	_splash_events += 1


func _emit_ripple(pos: Vector3, radius: float) -> void:
	if _ripple == null or _ripple_mat == null:
		return
	_ripple.global_position = Vector3(pos.x, WATER_Y + RIPPLE_Y, pos.z)
	_ripple.scale = Vector3(RIPPLE_BASE_R, 1.0, RIPPLE_BASE_R)
	_ripple.visible = true
	_ripple_t = 0.0
	_ripple_r = maxf(radius, RIPPLE_BASE_R + 0.05)
	_ripple_dur = RIPPLE_TIME
	_ripple_active = true
	_ripple_mat.albedo_color = Color(C_RIPPLE.r, C_RIPPLE.g, C_RIPPLE.b, 0.55)
	_ripple_events += 1


# ============================================================ 鱼获数据 =====

func _compute_catch_anchor() -> void:
	_catch_base_local = Vector3(0.0, 1.18, -0.36)
	_catch_euler_base = Vector3.ZERO
	if _villager == null or not is_instance_valid(_villager):
		return
	var gt := _villager.global_transform
	var up := gt.basis.y.normalized()
	var fwd := -gt.basis.z.normalized()
	var right := gt.basis.x.normalized()
	var chest_y := gt.origin.y + 1.00
	var torso := _joint("torso")
	if torso != null:
		chest_y = torso.global_position.y + 0.10
	var world_pos := Vector3(gt.origin.x, chest_y, gt.origin.z) \
		+ fwd * CATCH_FORWARD + right * CATCH_RIGHT + up * CATCH_UP
	_catch_base_local = to_local(world_pos)
	var fish_basis := Basis(right, up, right.cross(up)) \
		* Basis(Vector3(0.0, 1.0, 0.0), 0.22) \
		* Basis(Vector3(0.0, 0.0, 1.0), -0.16)
	var inv_basis := global_transform.basis.orthonormalized().inverse()
	_catch_euler_base = (inv_basis * fish_basis).get_euler()


func _catch_basis() -> Basis:
	if _villager == null or not is_instance_valid(_villager):
		return Basis.IDENTITY
	return Basis.from_euler(_catch_euler_base)


func _joint(joint_name: String) -> Node3D:
	if _model_root == null or not is_instance_valid(_model_root):
		return null
	if not _model_root.has_method("get_joint"):
		return null
	var j: Variant = _model_root.call("get_joint", joint_name)
	if j is Node3D:
		return j as Node3D
	return null


func _fish_script() -> Script:
	if _fish_script_checked:
		return _fish_script_res
	_fish_script_checked = true
	var path := "res://scripts/isle_fish.gd"
	if ResourceLoader.exists(path):
		var res: Variant = load(path)
		if res is Script:
			_fish_script_res = res as Script
	return _fish_script_res


## 解析鱼获颜色与体长：有 isle_fish.gd 目录就取 color / min_size / max_size，否则安全兜底。
func _resolve_fish(fish_id: String, size: float) -> Dictionary:
	var col := FISH_DEFAULT_COLOR
	var lo := FISH_MIN_VIS
	var hi := FISH_MAX_VIS
	var has_bounds := false
	var script := _fish_script()
	if script != null and script.has_method("get_def"):
		var raw_def: Variant = script.call("get_def", fish_id)
		if typeof(raw_def) == TYPE_DICTIONARY:
			var def: Dictionary = raw_def
			if def.has("color"):
				var raw: Variant = def["color"]
				var parsed := FISH_DEFAULT_COLOR
				if typeof(raw) == TYPE_COLOR:
					parsed = raw as Color
				elif typeof(raw) == TYPE_STRING:
					parsed = Color(String(raw))
					if parsed.r <= 0.0 and parsed.g <= 0.0 and parsed.b <= 0.0:
						parsed = FISH_DEFAULT_COLOR  # 解析失败兜底
				col = parsed
			if def.has("min_size") and def.has("max_size"):
				var l := float(def["min_size"])
				var h := float(def["max_size"])
				if l > 0.0 and h >= l:
					lo = l
					hi = h
					has_bounds = true
	var length := size if size > 0.0 else FISH_DEFAULT_SIZE
	if has_bounds:
		length = clampf(length, lo, hi)
	length = clampf(length, FISH_MIN_VIS, FISH_MAX_VIS)
	return {"color": col, "length": length}


# ============================================================ 程序化网格 ====
# 全部是构建期一次性调用（show_catch 每次重建鱼网格），不在 tick 里分配。

## 三角形工具：SurfaceTool 顶点色 + 法线；Godot 4 以顺时针为正面，按外侧法线自动纠正绕序。
class _Kit extends RefCounted:
	var _st := SurfaceTool.new()

	func _init() -> void:
		_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	func add_v(p: Vector3, n: Vector3, c: Color) -> void:
		_st.set_normal(n)
		_st.set_color(c)
		_st.add_vertex(p)

	func tri(a: Vector3, b: Vector3, c: Vector3,
			na: Vector3, nb: Vector3, nc: Vector3,
			ca: Color, cb: Color, cc: Color) -> void:
		if (b - a).cross(c - a).dot(na + nb + nc) > 0.0:
			var tb := b
			b = c
			c = tb
			var tn := nb
			nb = nc
			nc = tn
			var tc := cb
			cb = cc
			cc = tc
		add_v(a, na, ca)
		add_v(b, nb, cb)
		add_v(c, nc, cc)

	func commit() -> ArrayMesh:
		return _st.commit()


## 沿任意轴的低模圆管（含端盖）。
static func _tube(k: _Kit, a: Vector3, b: Vector3, r0: float, r1: float, sides: int,
		segs: int, c0: Color, c1: Color, cap0: bool, cap1: bool) -> void:
	var axis := b - a
	if axis.length_squared() < 0.0000001:
		return
	axis = axis.normalized()
	var ref := Vector3.UP
	if absf(axis.dot(ref)) > 0.98:
		ref = Vector3.RIGHT
	var n1 := axis.cross(ref).normalized()
	var n2 := n1.cross(axis).normalized()
	var dirs: Array = []
	var cosines: Array = []
	var sines: Array = []
	for s in sides:
		var ang := TAU * float(s) / float(sides)
		cosines.append(cos(ang))
		sines.append(sin(ang))
		dirs.append((n1 * cos(ang) + n2 * sin(ang)).normalized())
	for i in segs:
		var t0 := float(i) / float(segs)
		var t1 := float(i + 1) / float(segs)
		var ca := c0.lerp(c1, t0)
		var cb := c0.lerp(c1, t1)
		var pa := a.lerp(b, t0)
		var pb := a.lerp(b, t1)
		var ra := lerpf(r0, r1, t0)
		var rb := lerpf(r0, r1, t1)
		for s in sides:
			var s2 := (s + 1) % sides
			var d0: Vector3 = dirs[s]
			var d1: Vector3 = dirs[s2]
			var p00 := pa + d0 * ra
			var p01 := pa + d1 * ra
			var p10 := pb + d0 * rb
			var p11 := pb + d1 * rb
			k.tri(p00, p01, p11, d0, d1, d1, ca, ca, cb)
			k.tri(p00, p11, p10, d0, d1, d0, ca, cb, cb)
	if cap0:
		for s in sides:
			var s2 := (s + 1) % sides
			var d0: Vector3 = dirs[s]
			var d1: Vector3 = dirs[s2]
			k.tri(a, a + d0 * r0, a + d1 * r0, -axis, -axis, -axis, c0, c0, c0)
	if cap1:
		for s in sides:
			var s2 := (s + 1) % sides
			var d0: Vector3 = dirs[s]
			var d1: Vector3 = dirs[s2]
			k.tri(b, b + d0 * r1, b + d1 * r1, axis, axis, axis, c1, c1, c1)


## 沿 +X 的鱼身型旋转体：rings 为 [[x, ry, rz], ...]；上背色 / 腹色随环形角度渐变。
static func _lathe_x(k: _Kit, rings: Array, sides: int, c_top: Color, c_belly: Color,
		nose_x: float, tail_x: float) -> void:
	var pts: Array = []
	var norms: Array = []
	var cols: Array = []
	for ring in rings:
		var x := float(ring[0])
		var ry := float(ring[1])
		var rz := float(ring[2])
		var rp: Array = []
		var rn: Array = []
		var rc: Array = []
		for s in sides:
			var ang := TAU * float(s) / float(sides)
			var cy := cos(ang)
			var sz := sin(ang)
			rp.append(Vector3(x, ry * cy, rz * sz))
			var nv := Vector3(0.0, cy / maxf(ry, 0.0001), sz / maxf(rz, 0.0001)).normalized()
			rn.append(nv)
			rc.append(c_top.lerp(c_belly, clampf((1.0 - cy) * 0.5, 0.0, 1.0)))
		pts.append(rp)
		norms.append(rn)
		cols.append(rc)
	var n_rings := rings.size()
	for i in range(n_rings - 1):
		for s in sides:
			var s2 := (s + 1) % sides
			var a0: Vector3 = pts[i][s]
			var a1: Vector3 = pts[i][s2]
			var b0: Vector3 = pts[i + 1][s]
			var b1: Vector3 = pts[i + 1][s2]
			var na0: Vector3 = norms[i][s]
			var na1: Vector3 = norms[i][s2]
			var nb0: Vector3 = norms[i + 1][s]
			var nb1: Vector3 = norms[i + 1][s2]
			var ca0: Color = cols[i][s]
			var ca1: Color = cols[i][s2]
			var cb0: Color = cols[i + 1][s]
			var cb1: Color = cols[i + 1][s2]
			k.tri(a0, a1, b1, na0, na1, nb1, ca0, ca1, cb1)
			k.tri(a0, b1, b0, na0, nb1, nb0, ca0, cb1, cb0)
	# 鼻尖 / 尾柄端盖
	var first: Array = pts[0]
	var last: Array = pts[n_rings - 1]
	var c_first: Color = cols[0][0]
	var c_last: Color = cols[n_rings - 1][0]
	var nose := Vector3(nose_x, 0.0, 0.0)
	var tail := Vector3(tail_x, 0.0, 0.0)
	for s in sides:
		var s2 := (s + 1) % sides
		k.tri(nose, first[s], first[s2], Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT,
			c_first, c_first, c_first)
		k.tri(tail, last[s2], last[s], Vector3.LEFT, Vector3.LEFT, Vector3.LEFT,
			c_last, c_last, c_last)


## 沿 +Y 的旋转体（浮漂）：ys / rs 一一对应，cols 为每环颜色。
static func _lathe_y(k: _Kit, ys: PackedFloat32Array, rs: PackedFloat32Array,
		cols: Array, sides: int, cap_bottom: bool, cap_top: bool) -> void:
	var pts: Array = []
	for i in ys.size():
		var y := ys[i]
		var r := rs[i]
		var rp: Array = []
		for s in sides:
			var ang := TAU * float(s) / float(sides)
			rp.append(Vector3(cos(ang) * r, y, sin(ang) * r))
		pts.append(rp)
	for i in range(ys.size() - 1):
		var ca: Color = cols[i]
		var cb: Color = cols[i + 1]
		for s in sides:
			var s2 := (s + 1) % sides
			var a0: Vector3 = pts[i][s]
			var a1: Vector3 = pts[i][s2]
			var b0: Vector3 = pts[i + 1][s]
			var b1: Vector3 = pts[i + 1][s2]
			var na0 := Vector3(a0.x, 0.0, a0.z)
			var na1 := Vector3(a1.x, 0.0, a1.z)
			var nb0 := Vector3(b0.x, 0.0, b0.z)
			var nb1 := Vector3(b1.x, 0.0, b1.z)
			if na0.length_squared() < 0.0000001:
				na0 = Vector3.UP
			if na1.length_squared() < 0.0000001:
				na1 = Vector3.UP
			if nb0.length_squared() < 0.0000001:
				nb0 = Vector3.UP
			if nb1.length_squared() < 0.0000001:
				nb1 = Vector3.UP
			na0 = na0.normalized()
			na1 = na1.normalized()
			nb0 = nb0.normalized()
			nb1 = nb1.normalized()
			k.tri(a0, a1, b1, na0, na1, nb1, ca, ca, cb)
			k.tri(a0, b1, b0, na0, nb1, nb0, ca, cb, cb)
	if cap_bottom:
		var y0 := ys[0]
		var c0: Color = cols[0]
		for s in sides:
			var s2 := (s + 1) % sides
			k.tri(Vector3(0.0, y0, 0.0), pts[0][s2], pts[0][s], Vector3.DOWN, Vector3.DOWN, Vector3.DOWN,
				c0, c0, c0)
	if cap_top:
		var y1 := ys[ys.size() - 1]
		var c1: Color = cols[cols.size() - 1]
		for s in sides:
			var s2 := (s + 1) % sides
			k.tri(Vector3(0.0, y1, 0.0), pts[pts.size() - 1][s], pts[pts.size() - 1][s2],
				Vector3.UP, Vector3.UP, Vector3.UP, c1, c1, c1)


## 双面薄片（鳍）：法线由前三点决定，正反各铺一遍，避免单面剔除。
static func _flat_double(k: _Kit, pts: Array, col: Color) -> void:
	if pts.size() < 3:
		return
	var n: Vector3 = (pts[1] - pts[0]).cross(pts[2] - pts[0]).normalized()
	for i in range(1, pts.size() - 1):
		k.tri(pts[0], pts[i], pts[i + 1], n, n, n, col, col, col)
	for i in range(1, pts.size() - 1):
		k.tri(pts[0], pts[i + 1], pts[i], -n, -n, -n, col, col, col)


## 多边形薄片（眼睛）：按给定中心/半径/平面法线生成，双面。
static func _disc(k: _Kit, center: Vector3, normal: Vector3, radius: float, sides: int, col: Color) -> void:
	var n := normal.normalized()
	var ref := Vector3.UP
	if absf(n.dot(ref)) > 0.98:
		ref = Vector3.RIGHT
	var e1 := n.cross(ref).normalized()
	var e2 := e1.cross(n).normalized()
	var ring: Array = []
	for s in sides:
		var ang := TAU * float(s) / float(sides)
		ring.append(center + (e1 * cos(ang) + e2 * sin(ang)) * radius)
	for s in sides:
		var s2 := (s + 1) % sides
		k.tri(center, ring[s], ring[s2], n, n, n, col, col, col)
		k.tri(center, ring[s2], ring[s], -n, -n, -n, col, col, col)


static func _build_rod_mesh() -> ArrayMesh:
	var k := _Kit.new()
	# 竿尾 → 软木握把 → 红箍 → 竿身（两段收细）→ 红色竿尖
	_tube(k, Vector3(0.0, ROD_BUTT_Y, 0.0), Vector3(0.0, -0.06, 0.0),
		0.012, 0.016, ROD_SIDES, 1, C_ROD_WOOD, C_ROD_WOOD, true, false)
	_tube(k, Vector3(0.0, -0.06, 0.0), Vector3(0.0, 0.20, 0.0),
		0.0185, 0.0185, ROD_SIDES, 2, C_ROD_GRIP, C_ROD_GRIP, false, false)
	_tube(k, Vector3(0.0, 0.20, 0.0), Vector3(0.0, 0.245, 0.0),
		0.019, 0.018, ROD_SIDES, 1, C_ROD_ACCENT, C_ROD_ACCENT, false, false)
	_tube(k, Vector3(0.0, 0.245, 0.0), Vector3(0.0, 0.96, 0.0),
		0.0165, 0.011, ROD_SIDES, 2, C_ROD_WOOD_LIGHT, C_ROD_WOOD_LIGHT, false, false)
	_tube(k, Vector3(0.0, 0.96, 0.0), Vector3(0.0, ROD_TIP_Y, 0.0),
		0.011, 0.0045, ROD_SIDES, 2, C_ROD_WOOD_LIGHT, C_ROD_ACCENT, false, true)
	# 卷线器：短圆柱 + 亮色线杯 + 小摇柄
	_tube(k, Vector3(0.006, 0.115, 0.0), Vector3(0.048, 0.115, 0.0),
		0.042, 0.042, 8, 1, C_REEL, C_REEL, true, true)
	_tube(k, Vector3(0.030, 0.115, 0.0), Vector3(0.056, 0.115, 0.0),
		0.021, 0.021, 6, 1, C_REEL_SPOOL, C_REEL_SPOOL, true, true)
	_tube(k, Vector3(0.010, 0.115, 0.0), Vector3(0.010, 0.128, 0.0),
		0.006, 0.006, 4, 1, C_REEL, C_REEL, false, false)
	return k.commit()


static func _build_bobber_mesh() -> ArrayMesh:
	var k := _Kit.new()
	# 本地原点 = 水面线：下半白、上半红，顶部细天线
	var ys := PackedFloat32Array([-0.058, -0.050, -0.030, 0.000, 0.020, 0.040, 0.052])
	var rs := PackedFloat32Array([0.010, 0.030, 0.048, 0.055, 0.052, 0.036, 0.014])
	var cols: Array = [
		C_BOBBER_WHITE,
		C_BOBBER_WHITE,
		C_BOBBER_WHITE,
		C_BOBBER_WHITE,
		C_BOBBER_RED,
		C_BOBBER_RED,
		C_BOBBER_RED,
	]
	_lathe_y(k, ys, rs, cols, 8, true, true)
	_tube(k, Vector3(0.0, 0.050, 0.0), Vector3(0.0, 0.165, 0.0),
		0.005, 0.0025, 5, 1, C_BOBBER_RED, C_ROD_GRIP, false, true)
	return k.commit()


static func _build_ripple_mesh() -> ArrayMesh:
	var k := _Kit.new()
	var sides := 24
	var inner := 0.74
	var outer := 1.0
	for s in sides:
		var a0 := TAU * float(s) / float(sides)
		var a1 := TAU * float(s + 1) / float(sides)
		var i0 := Vector3(cos(a0) * inner, 0.0, sin(a0) * inner)
		var i1 := Vector3(cos(a1) * inner, 0.0, sin(a1) * inner)
		var o0 := Vector3(cos(a0) * outer, 0.0, sin(a0) * outer)
		var o1 := Vector3(cos(a1) * outer, 0.0, sin(a1) * outer)
		k.tri(i0, o0, o1, Vector3.UP, Vector3.UP, Vector3.UP, Color.WHITE, Color.WHITE, Color.WHITE)
		k.tri(i0, o1, i1, Vector3.UP, Vector3.UP, Vector3.UP, Color.WHITE, Color.WHITE, Color.WHITE)
	return k.commit()


## 单位长度（鼻子 +0.50 → 尾鳍尖 -0.50）的鱼网格；调用方用 scale = 体长。
static func _build_fish_mesh(col: Color) -> ArrayMesh:
	var k := _Kit.new()
	var belly := col.lerp(C_FISH_BELLY, 0.62)
	var fin := col.darkened(0.22)
	var rings: Array = [
		[0.44, 0.030, 0.014],
		[0.38, 0.075, 0.033],
		[0.26, 0.125, 0.055],
		[0.12, 0.155, 0.068],
		[-0.04, 0.165, 0.070],
		[-0.18, 0.150, 0.060],
		[-0.30, 0.115, 0.045],
		[-0.40, 0.070, 0.026],
		[-0.44, 0.038, 0.014],
	]
	_lathe_x(k, rings, 8, col, belly, 0.50, -0.46)
	# 尾鳍（分叉，双面薄片）
	_flat_double(k, [
		Vector3(-0.44, 0.032, 0.0),
		Vector3(-0.50, 0.150, 0.0),
		Vector3(-0.455, 0.0, 0.0),
	], fin)
	_flat_double(k, [
		Vector3(-0.44, -0.032, 0.0),
		Vector3(-0.455, 0.0, 0.0),
		Vector3(-0.50, -0.150, 0.0),
	], fin)
	# 背鳍
	_flat_double(k, [
		Vector3(-0.20, 0.150, 0.0),
		Vector3(-0.06, 0.245, 0.0),
		Vector3(0.06, 0.160, 0.0),
	], fin)
	# 胸鳍（左右各一）
	_flat_double(k, [
		Vector3(0.20, -0.030, 0.075),
		Vector3(0.06, -0.060, 0.085),
		Vector3(-0.02, -0.015, 0.065),
	], fin)
	_flat_double(k, [
		Vector3(0.20, -0.030, -0.075),
		Vector3(-0.02, -0.015, -0.065),
		Vector3(0.06, -0.060, -0.085),
	], fin)
	# 眼睛 + 高光
	var eye_dark := Color(0.137, 0.118, 0.106)
	var eye_light := Color(0.973, 0.953, 0.918)
	_disc(k, Vector3(0.355, 0.055, 0.062), Vector3.BACK, 0.026, 6, eye_dark)
	_disc(k, Vector3(0.355, 0.055, -0.062), Vector3.FORWARD, 0.026, 6, eye_dark)
	_disc(k, Vector3(0.365, 0.065, 0.066), Vector3.BACK, 0.010, 5, eye_light)
	_disc(k, Vector3(0.365, 0.065, -0.066), Vector3.FORWARD, 0.010, 5, eye_light)
	return k.commit()
