class_name IsleFlyCam
extends RefCounted
## P7-V2 自由飞行观景相机（纯逻辑件：不创建、不拥有 Camera3D 节点）。
##
## 与 main.gd 的轨道相机完全解耦：main 只在“进入 / 每帧 / 退出”三个点调用本类，
## 本类不做场景节点操作（apply_to 除外：把最终变换与 FOV 写给传入的 Camera3D）。
##
## API（main.gd 接线契约，名称固定，不得改名）：
##   var active: bool                         是否仍由本类控制相机（含退出回位混合期）
##   func configure(cfg: Dictionary) -> void  可选；部分键覆盖，缺省用本文件校准默认值
##   func enter(from_xf: Transform3D, fov: float, home_xf: Transform3D = Transform3D.IDENTITY) -> void
##   func request_exit() -> void              立即释放鼠标，进入 smoothstep 回位混合
##   func handle_event(e: InputEvent) -> bool 仅消费鼠标移动；其余返回 false
##   func update(delta: float, terrain_height: Callable) -> bool  返回是否仍控制相机
##   func apply_to(cam: Camera3D) -> void
##   func help_text() -> String
##   func debug_state() -> Dictionary
##   func saved_home() -> Dictionary          {transform, fov, yaw, pitch}
##
## 运动语义：
##   * WASD 只按 yaw 做水平前/右（不含 pitch，向下看不自动下降）；
##   * Space 上升 / Shift 下降（独立垂直轴，世界单位/秒）；
##   * Ctrl 临时加速：倍率 BOOST_MULT_DEFAULT≈2.09×（=speed_boost/speed_regular=21.7/10.4），
##     加速端平滑（τ≈1/8s），松开立即回落 1×；
##   * 所有速度均为“每秒世界单位”；速度阻尼按指数时间常数解析积分，和帧率无关；
##   * 边界：水平距 center 超过 radius → 切向滑动 + clamp（不瞬移）；y 夹在
##     [max(min_y, terrain_height(x,z)+0.8), max_y]，绝不低于海平面；
##   * FOV：加速时平滑 +boost_fov_add，松开/退出平滑恢复；退出混合期间不做飞行输入响应。
##
## 本文件内不读取/改写 main.gd 的轨道参数（_theta/_elev/_radius/_cam_target/_fov），
## 进入时快照、退出时按快照回位，由 main 决定何时恢复轨道运镜。

# ---------------- 校准基准（实测数据见 tools/probe_flycam_p7v2.gd 的 [FLYCAM] 输出） ----------------
# 观察范围直径 D：任务书 §7.2 口径 = 自由视角水平观察范围直径 = 2 × 边界半径 R(130) = 260 m。
# 实测海岸线：公式 coast_radius 半径最大值 ≈32.0 m → 直径 ≈63.6 m（4096 采样 max=30.07≈60.1 m）；
# 地形网格外缘 ≈40 m 半径。R=130 m ≈ 2.0× 岛最大直径（任务书要求 2–3 倍），覆盖全岛 + 周边海域。
# （旧口径 164 = 2×轨道相机半径 CAM_START_R，与"自由视角观察范围"不同，已按 §7.2 更正。）
const REF_RANGE_D := 260.0
# 普通速度 = D/25 = 260/25 = 10.4 m/s（完整穿越 D 约 25 s，落在 20–30 s 验收区间）。
const DEFAULT_SPEED_REGULAR := 10.4
# 加速 = D/12 = 260/12 ≈ 21.7 m/s（完整穿越约 12 s，落在 10–15 s 验收区间）。
const DEFAULT_SPEED_BOOST := 21.7
# 加速倍率由两档速度派生（21.7/10.4≈2.0865×），不硬编码，改速度后自动一致。
const BOOST_MULT_DEFAULT := DEFAULT_SPEED_BOOST / DEFAULT_SPEED_REGULAR
# 垂直速度：普通 5.5 m/s；加速时同倍率放大（×≈2.09 ≈ 11.5 m/s）。
const DEFAULT_VERTICAL_SPEED := 5.5
# 鼠标视角灵敏度：rad/像素（0.0022 rad/px ≈ 全屏宽 1440px 转身 181°），main 可乘用户灵敏度。
const DEFAULT_LOOK_SENSITIVITY := 0.0022
# 加速 FOV 增量：FOV 42 → 46.5（+10.7%，参考 Minecraft 加速 +10% FOV）。
const DEFAULT_BOOST_FOV_ADD := 4.5
# 退出回位混合时长（smoothstep），比菜单 2.4s 转场短，交互更利落。
const DEFAULT_EXIT_BLEND_DUR := 0.6
# 水平活动半径 R=130 m：≈2.0× 岛岸线最大直径（≈63.6 m），也大于轨道半径 82 m，留足海上观景范围。
const DEFAULT_RADIUS := 130.0
# 最低绝对高度：海平面以上 1.2 m（任意位置都不低于海平面）。
const DEFAULT_MIN_Y := 1.2
# 最高高度 130 m：≈2.0× 岛岸线最大直径，可俯瞰全岛与远海。
const DEFAULT_MAX_Y := 130.0

# ---------------- 运动参数（时间常数，单位 1/s） ----------------
const PITCH_LIMIT := 1.45          # 俯仰上限（rad，≈83°），防翻转
const TERRAIN_CLEARANCE := 0.8     # 相机离地最小净高（m）
const MOVE_RESPONSE := 14.0        # 水平/垂直速度趋近目标的时间常数倒数（τ≈0.071s）
const BOOST_RESPONSE := 8.0        # 加速倍率上升的平滑（τ≈0.125s，松开立即回落）
const FOV_RESPONSE := 8.0          # FOV 平滑（τ≈0.125s）
const MAX_STEP := 0.1              # 单帧最大积分步长（防卡顿帧穿透地形）

# ---------------- InputMap 动作名（project.godot [input] 段，键位固定） ----------------
const ACT_TOGGLE := "fly_toggle"     # F=70（由 main 消费进入/退出）
const ACT_FORWARD := "fly_forward"   # W=87
const ACT_BACK := "fly_back"         # S=83
const ACT_LEFT := "fly_left"         # A=65
const ACT_RIGHT := "fly_right"       # D=68
const ACT_UP := "fly_up"             # Space=32
const ACT_DOWN := "fly_down"         # Shift=4194325
const ACT_BOOST := "fly_boost"       # Ctrl=4194326

# ---------------- 公共状态 ----------------
## 是否仍由本类控制相机。退出混合期间保持 true，混合结束后置 false（任务契约）。
var active := false

# ---------------- 配置（configure 写入；默认值已按实测校准） ----------------
var center := Vector3.ZERO
var radius := DEFAULT_RADIUS
var min_y := DEFAULT_MIN_Y
var max_y := DEFAULT_MAX_Y
var speed_regular := DEFAULT_SPEED_REGULAR
var speed_boost := DEFAULT_SPEED_BOOST
var vertical_speed := DEFAULT_VERTICAL_SPEED
var look_sensitivity := DEFAULT_LOOK_SENSITIVITY
var boost_fov_add := DEFAULT_BOOST_FOV_ADD
var exit_blend_dur := DEFAULT_EXIT_BLEND_DUR

# ---------------- 内部状态 ----------------
var _exiting := false
var _pos := Vector3.ZERO
var _yaw := 0.0
var _pitch := 0.0
var _vel := Vector3.ZERO
var _boost_mult := BOOST_MULT_DEFAULT
var _boost_scale := 1.0
var _base_fov := 42.0
var _fov := 42.0
var _hit_bound := false

# 退出/回位快照
var _blend_t := 0.0
var _exit_from_pos := Vector3.ZERO
var _exit_from_yaw := 0.0
var _exit_from_pitch := 0.0
var _exit_from_fov := 42.0
var _home_xf := Transform3D.IDENTITY
var _home_pos := Vector3.ZERO
var _home_yaw := 0.0
var _home_pitch := 0.0
var _home_fov := 42.0

# apply_to 缓存相机（弱引用，避免 RefCounted 与节点生命周期纠缠）
var _cam_ref: WeakRef = null


# ============================================================
# 配置
# ============================================================
## 由 main 在建立自由视角前调用；所有键都可选。允许在 active 期间调用（例如换灵敏度）。
func configure(cfg: Dictionary) -> void:
	if cfg.has("center"):
		center = _as_v3(cfg["center"], center)
	if cfg.has("radius"):
		radius = maxf(_as_float(cfg["radius"], radius), 1.0)
	if cfg.has("min_y"):
		min_y = _as_float(cfg["min_y"], min_y)
	if cfg.has("max_y"):
		max_y = _as_float(cfg["max_y"], max_y)
	if max_y < min_y + 1.0:
		max_y = min_y + 1.0
	if cfg.has("speed_regular"):
		speed_regular = maxf(_as_float(cfg["speed_regular"], speed_regular), 0.05)
	if cfg.has("speed_boost"):
		speed_boost = _as_float(cfg["speed_boost"], speed_boost)
	if cfg.has("vertical_speed"):
		vertical_speed = maxf(_as_float(cfg["vertical_speed"], vertical_speed), 0.05)
	if cfg.has("look_sensitivity"):
		look_sensitivity = maxf(_as_float(cfg["look_sensitivity"], look_sensitivity), 0.00001)
	if cfg.has("boost_fov_add"):
		boost_fov_add = maxf(_as_float(cfg["boost_fov_add"], boost_fov_add), 0.0)
	if cfg.has("exit_blend_dur"):
		exit_blend_dur = maxf(_as_float(cfg["exit_blend_dur"], exit_blend_dur), 0.05)
	_boost_mult = maxf(speed_boost / maxf(speed_regular, 0.001), 1.0)


## 校准默认配置（main 可原样传给 configure，或只覆盖少数键）。
static func default_config() -> Dictionary:
	return {
		"center": Vector3.ZERO,
		"radius": DEFAULT_RADIUS,
		"min_y": DEFAULT_MIN_Y,
		"max_y": DEFAULT_MAX_Y,
		"speed_regular": DEFAULT_SPEED_REGULAR,
		"speed_boost": DEFAULT_SPEED_BOOST,
		"vertical_speed": DEFAULT_VERTICAL_SPEED,
		"look_sensitivity": DEFAULT_LOOK_SENSITIVITY,
		"boost_fov_add": DEFAULT_BOOST_FOV_ADD,
		"exit_blend_dur": DEFAULT_EXIT_BLEND_DUR,
	}


# ============================================================
# 进入 / 退出
# ============================================================
## 进入自由视角：记录起点位姿、FOV 与回位目标（home_xf 省略时 = from_xf），并捕获鼠标。
func enter(from_xf: Transform3D, fov: float, home_xf: Transform3D = Transform3D.IDENTITY) -> void:
	if active and not _exiting:
		return
	var home := home_xf
	if home == Transform3D.IDENTITY:
		home = from_xf
	_active_setup(from_xf.origin, from_xf.basis, fov)
	_home_xf = home
	_home_pos = home.origin
	var hf := -home.basis.z
	_home_pitch = clampf(asin(clampf(hf.y, -1.0, 1.0)), -PITCH_LIMIT, PITCH_LIMIT)
	_home_yaw = atan2(-hf.x, -hf.z)
	_home_fov = fov
	active = true
	_exiting = false
	_blend_t = 0.0
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


## 请求退出：立即释放鼠标，记录当前位姿并开始 smoothstep 回位混合。
## active 保持 true 直到混合结束（update 返回 false 的那一帧）。
func request_exit() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if not active or _exiting:
		return
	_exiting = true
	_blend_t = 0.0
	_exit_from_pos = _pos
	_exit_from_yaw = _yaw
	_exit_from_pitch = _pitch
	_exit_from_fov = _fov
	_hit_bound = false
	_vel = Vector3.ZERO


# ============================================================
# 每帧
# ============================================================
## 返回本帧是否仍由本类控制相机（active 或退出混合期）。
## terrain_height(x, z) -> float：传入 IsleMath.terrain_height 即可（Callable）。
func update(delta: float, terrain_height: Callable) -> bool:
	if not active:
		return false
	var dt := clampf(delta, 0.0, MAX_STEP)
	if _exiting:
		return _update_exit(dt, terrain_height)
	_update_movement(dt, terrain_height)
	return true


func handle_event(e: InputEvent) -> bool:
	if not active or _exiting:
		return false
	if e is InputEventMouseMotion:
		var mm := e as InputEventMouseMotion
		# 鼠标右移 → yaw 减小（向右转）；鼠标下移 → pitch 减小（向下看）
		_yaw = wrapf(_yaw - mm.relative.x * look_sensitivity, -PI, PI)
		_pitch = clampf(_pitch - mm.relative.y * look_sensitivity, -PITCH_LIMIT, PITCH_LIMIT)
		return true
	return false


func apply_to(cam: Camera3D) -> void:
	if cam == null:
		return
	_cam_ref = weakref(cam)
	cam.global_transform = _current_transform()
	cam.fov = _fov


func help_text() -> String:
	return "自由视角：WASD 水平移动 · Space 上升 · Shift 下降 · Ctrl 加速 · 鼠标转向 · F 退出 · ESC 返回"


func saved_home() -> Dictionary:
	return {
		"transform": _home_xf,
		"fov": _home_fov,
		"yaw": _home_yaw,
		"pitch": _home_pitch,
	}


func debug_state() -> Dictionary:
	return {
		"active": active,
		"exiting": _exiting,
		"pos": _pos,
		"yaw": _yaw,
		"pitch": _pitch,
		"speed": _vel.length(),
		"velocity": _vel,
		"horizontal_speed": Vector2(_vel.x, _vel.z).length(),
		"vertical_speed_now": _vel.y,
		"boost_scale": _boost_scale,
		"boost_mult": _boost_mult,
		"boost_active": _boost_scale > 1.0001,
		"hit_bound": _hit_bound,
		"bounds": {
			"center": center,
			"radius": radius,
			"min_y": min_y,
			"max_y": max_y,
		},
		"fov": _fov,
		"base_fov": _base_fov,
		"boost_fov_add": boost_fov_add,
		"look_sensitivity": look_sensitivity,
		"blend_t": _blend_t,
		"exit_blend_dur": exit_blend_dur,
		"home_pos": _home_pos,
		"home_fov": _home_fov,
		"speed_regular": speed_regular,
		"speed_boost": speed_boost,
		"vertical_speed": vertical_speed,
	}


# ============================================================
# 内部：进入初始化 / 相机变换
# ============================================================
func _active_setup(pos: Vector3, basis: Basis, fov: float) -> void:
	_pos = pos
	var fwd := -basis.z
	if fwd.length_squared() < 0.000001:
		fwd = Vector3(0.0, 0.0, -1.0)
	fwd = fwd.normalized()
	_pitch = clampf(asin(clampf(fwd.y, -1.0, 1.0)), -PITCH_LIMIT, PITCH_LIMIT)
	_yaw = atan2(-fwd.x, -fwd.z)
	_base_fov = fov
	_fov = fov
	_vel = Vector3.ZERO
	_boost_scale = 1.0
	_hit_bound = false


func _current_transform() -> Transform3D:
	return Transform3D(Basis.from_euler(Vector3(_pitch, _yaw, 0.0)), _pos)


# ============================================================
# 内部：飞行移动（指数阻尼 + 位置解析积分 → 帧率无关）
# ============================================================
func _update_movement(dt: float, terrain_height: Callable) -> void:
	# 加速倍率：按下 Ctrl 由 1 → 2.10 平滑上升；松开立即回落 1（任务契约）。
	var boost_pressed := _act_pressed(ACT_BOOST, KEY_CTRL)
	if boost_pressed:
		_boost_scale = lerpf(_boost_scale, _boost_mult, 1.0 - exp(-BOOST_RESPONSE * dt))
	else:
		_boost_scale = 1.0

	# 水平输入：只按 yaw（不含 pitch），斜向归一化避免斜跑更快。
	var fwd_in := _act_strength(ACT_FORWARD, KEY_W) - _act_strength(ACT_BACK, KEY_S)
	var right_in := _act_strength(ACT_RIGHT, KEY_D) - _act_strength(ACT_LEFT, KEY_A)
	var fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
	var wish := fwd * fwd_in + right * right_in
	if wish.length_squared() > 1.0:
		wish = wish.normalized()

	var up_in := _act_strength(ACT_UP, KEY_SPACE) - _act_strength(ACT_DOWN, KEY_SHIFT)
	var target := wish * (speed_regular * _boost_scale)
	target.y = up_in * vertical_speed * _boost_scale

	# v(t) = target + (v0-target)·e^(-k t) 的解析积分：
	#   Δp = target·dt + (v0-target)·(1-e^(-k dt))/k ；v_end = target + (v0-target)·e^(-k dt)
	# 该积分与步长无关，因此 30fps/120fps 下的位移一致。
	var e := exp(-MOVE_RESPONSE * dt)
	var avg := (1.0 - e) / MOVE_RESPONSE
	_pos += target * dt + (_vel - target) * avg
	_vel = target + (_vel - target) * e

	_apply_bounds(terrain_height)
	_update_fov(dt)


func _update_fov(dt: float) -> void:
	var span := maxf(_boost_mult - 1.0, 0.0001)
	var amount := clampf((_boost_scale - 1.0) / span, 0.0, 1.0)
	var target_fov := _base_fov + boost_fov_add * amount
	_fov = lerpf(_fov, target_fov, 1.0 - exp(-FOV_RESPONSE * dt))


## 边界：水平圆内切向滑动（去掉朝外径向速度 → 不瞬移、不抖），y 上下限 + 地形净高。
func _apply_bounds(terrain_height: Callable) -> void:
	_hit_bound = false
	var dx := _pos.x - center.x
	var dz := _pos.z - center.z
	var dist := sqrt(dx * dx + dz * dz)
	if dist > radius and dist > 0.000001:
		var nx := dx / dist
		var nz := dz / dist
		_pos.x = center.x + nx * radius
		_pos.z = center.z + nz * radius
		_hit_bound = true
		# 沿切向滑动：只消除朝外的径向速度分量，保留切向速度。
		var radial := _vel.x * nx + _vel.z * nz
		if radial > 0.0:
			_vel.x -= nx * radial
			_vel.z -= nz * radial

	var ground := _terrain_at(terrain_height, _pos.x, _pos.z)
	var dyn_min := maxf(min_y, ground + TERRAIN_CLEARANCE)
	if _pos.y < dyn_min:
		_pos.y = dyn_min
		if _vel.y < 0.0:
			_vel.y = 0.0
		_hit_bound = true
	if _pos.y > max_y:
		_pos.y = max_y
		if _vel.y > 0.0:
			_vel.y = 0.0
		_hit_bound = true


# ============================================================
# 内部：退出回位混合（smoothstep）
# ============================================================
func _update_exit(dt: float, terrain_height: Callable) -> bool:
	_blend_t += dt
	var w := clampf(_blend_t / exit_blend_dur, 0.0, 1.0)
	var e := smoothstep(0.0, 1.0, w)
	_pos = _exit_from_pos.lerp(_home_pos, e)
	_yaw = lerp_angle(_exit_from_yaw, _home_yaw, e)
	_pitch = lerpf(_exit_from_pitch, _home_pitch, e)
	_fov = lerpf(_exit_from_fov, _home_fov, e)
	_boost_scale = 1.0
	_vel = Vector3.ZERO
	# 回位直线可能掠过地形：混合期也做净高保护（home 本身在轨道下限之上，不影响最终精确回位）。
	var ground := _terrain_at(terrain_height, _pos.x, _pos.z)
	var dyn_min := maxf(min_y, ground + TERRAIN_CLEARANCE)
	if _pos.y < dyn_min:
		_pos.y = dyn_min
		_hit_bound = true
	if w >= 1.0:
		_pos = _home_pos
		_yaw = _home_yaw
		_pitch = _home_pitch
		_fov = _home_fov
		_hit_bound = false
		active = false
		_exiting = false
		_blend_t = 0.0
		_flush_to_cam()
		return false
	return true


## 混合结束这一帧直接把精确 home 写回相机（main 下一帧起恢复轨道运镜）。
func _flush_to_cam() -> void:
	var cam := _cached_cam()
	if cam != null:
		cam.global_transform = _current_transform()
		cam.fov = _fov


func _cached_cam() -> Camera3D:
	if _cam_ref == null:
		return null
	var obj = _cam_ref.get_ref()
	if obj is Camera3D:
		return obj as Camera3D
	return null


# ============================================================
# 内部：输入读取（InputMap 动作优先；缺动作时用物理键兜底，便于独立运行/测试）
# ============================================================
func _act_pressed(action: String, fallback_key: Key) -> bool:
	if InputMap.has_action(action):
		return Input.is_action_pressed(action)
	return Input.is_physical_key_pressed(fallback_key)


func _act_strength(action: String, fallback_key: Key) -> float:
	if InputMap.has_action(action):
		return Input.get_action_strength(action)
	return 1.0 if Input.is_physical_key_pressed(fallback_key) else 0.0


func _terrain_at(terrain_height: Callable, x: float, z: float) -> float:
	if not terrain_height.is_valid():
		return 0.0
	var v: Variant = terrain_height.call(x, z)
	if v is float or v is int:
		return float(v)
	return 0.0


func _as_float(v: Variant, fallback: float) -> float:
	if v is float or v is int:
		return float(v)
	return fallback


func _as_v3(v: Variant, fallback: Vector3) -> Vector3:
	if v is Vector3:
		return v as Vector3
	return fallback
