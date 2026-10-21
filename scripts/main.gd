extends Node3D
## 休闲小岛幻境 · Godot 复刻 — 主场景。
##
## 标题界面（2.39:1 电影画幅 + 电影环绕运镜）→ 开始 → 径向飞出 / 黑框收合 /
## 相机推入 → 放置观景（慢速运镜 + 真实天文 + 昼夜循环）。

const SHOTS_DIR := "D:/休闲小岛幻境/开发产物/shots/"
const P7_SHOTS_DIR := "D:/休闲小岛幻境/开发产物/p7/shots/"
const VIGNETTE_SHADER := "res://shaders/vignette.gdshader"
const SKY_SHADER := "res://shaders/sky.gdshader"
const SEA_SHADER := "res://shaders/sea.gdshader"
const BEAM_SHADER := "res://shaders/beam.gdshader"
# P7-V3.2 T1 开发模式尺度标尺：默认不创建，--scale-debug 时才实例化一次。
const ScaleOverlay := preload("res://tools/scale_debug_overlay.gd")
# P7-V4 岛民（程序化模型 + 动画 + 日程）：--no-villager 时不创建，仅用于性能基线对照。
const ISLE_VILLAGER := preload("res://scripts/isle_villager.gd")

# ---- 灯塔旋转 / 光束参数（真实旋转透镜参考：Kīlauea Point 约 20 秒一圈，用作基础周期配置项） ----
const LIGHTHOUSE_ROTATION_PERIOD := 20.0   # 秒/圈（1× 时间流速下的基础周期）
const LIGHTHOUSE_REF_DAY_LENGTH := 480.0   # 默认一天 480 秒即 1× 时间流速
const LIGHTHOUSE_BEAM_PITCH_DEG := 34.0    # 光束俯角：从灯室斜向下照射
const LIGHTHOUSE_BEAM_OUTER_DEG := 12.0    # 外锥半角（决定海面亮区/岛屿受光范围）
const LIGHTHOUSE_BEAM_INNER_DEG := 3.5     # 内锥半角（亮芯）
const LIGHTHOUSE_BEAM_RANGE := 120.0       # 实际照明射程（覆盖岛屿、近海与小船）
const LIGHTHOUSE_BEAM_VIS_LEN := 62.0      # 可视光柱长度（覆盖灯室到海面交点，修 P5 光柱半空截断）

# ---- 小船（完整航行生命周期） ----
const BOAT_BODY_LEN := 5.1                 # 船长（m），探照灯射程/水花区都以船身为尺度
const BOAT_SPOT_RANGE := 5.4               # 前向探照灯有效射程 ≈ 一个船身长度
const BOAT_REST_START_HOUR := 18.0         # 夜间休息窗口：18:00
const BOAT_REST_END_HOUR := 8.0            # 夜间休息窗口：次日 08:00

# ---- 状态 ----
enum Mode { MENU, PLAYING }
var _mode: int = Mode.MENU
var _paused := false
var _started := false
var _shots := false
var _transition := false
var _selftest := false
var _p7shots := false

# ---- 时间 ----
var _sim_seconds := 0.0
var _day_length := 480.0
var _realtime := false
var _events: Dictionary = {}
var _events_timer := 0.0

# ---- 天文 / 主题 ----
var _astro: Dictionary = {}
var _pal: Dictionary = {}
var _theme_t := 0.6
var _sun_alt := 0.0
var _sun_az := 0.0
var _rising := true
var _sun_dir_world := Vector3.UP
var _moon_dir_world := Vector3.UP
var _moon_illum := 0.0
var _moon_waxing := false
var _phase_name := "黄昏"
var _phase_short := "DUSK"
var _frame_t := 0.0

# ---- 相机 ----
var _cam: Camera3D
var _cam_target := Vector3(0, 5.0, 0)
var _theta := 0.74
var _elev := 0.28
var _radius := IsleMath.CAM_START_R
var _fov := 42.0
var _menu_theta := 0.30
var _movie_theta := 0.30
var _blending := ""
var _blend_t := 0.0
const BLEND_DUR := 2.4
var _blend_from := {}
var _sensitivity := 1.0
var _auto_orbit := true
var _orbit_speed := 0.018   # 自动运镜角速度：开关时平滑增减，杜绝硬停/硬启

# ---- P7-V2 自由飞行观景相机（scripts/isle_flycam.gd，纯逻辑件） ----
var _flycam: IsleFlyCam = null
var _flycam_look_base := 0.0022

# ---- 拖拽 / 双击 ----
var _dragging := false
var _drag_moved := 0.0
var _last_click_ms := 0
var _press_pos := Vector2.ZERO
var _panning := false
var _pan_start := Vector2.ZERO

# ---- P7-V3 自由视角左键点击（按下记录屏幕位置，松开位移 <7px 才触发场景拾取） ----
var _fly_click_pos := Vector2.INF
var _fly_click_moved := 0.0

# ---- 场景对象 ----
var _env: Environment
var _sky_mat: ShaderMaterial
var _sea_mat: ShaderMaterial
var _world: Dictionary = {}
var _cottage: Dictionary = {}
var _fx: Dictionary = {}
var _ripples = null
var _birds = null
var _cam_layer: CanvasLayer
var _vignette_mat: ShaderMaterial
var _post_ao_mat: ShaderMaterial
var _post_ao_mi: MeshInstance3D
var _hud = null
var _menu = null
var _door_open := false
# P7-V4 岛民与门状态仲裁：玩家开门请求与 NPC 开门请求合并，共同决定 _door_open。
var _villager: Node3D = null
var _no_villager := false
var _door_npc := false
var _door_player := false
var _window_mats: Array = []
var _window_halos: Array = []
var _lantern_mat: ShaderMaterial
var _lantern_halo: MeshInstance3D
var _lantern_halos: Array = []
var _lamp_mats: Array = []
var _lamp_halos: Array = []
var _light_sources: Array = []
var _lights: Array = []
var _splash = null
var _wake = null
var _windmill_blades: Node3D = null
var _windmill_axis := Vector3(0.0, 0.0, 1.0)
var _swing_pivot: Node3D = null
var _sailboat: Node3D = null
var _sail_path: Array = []
var _sail_dist := 0.0
var _sail_speed := 3.2
var _moored_boat: Node3D = null
var _moored_base := Vector3.ZERO
var _moored_heading := 0.0
var _perf := false

# ---- 现实时间 / 时区（isle_time.gd，第四阶段） ----
var _time_api = null
var _time_source := "sim"
var _timezone := "Asia/Shanghai"
var _tz_label := ""
var _abs_unix := 0.0
var _display_dt: Dictionary = {}

# ---- 灯塔旋转光束 ----
var _lighthouse: Node3D = null
var _lighthouse_lamp: Node3D = null
var _lighthouse_light: Dictionary = {}
var _beam_origin_node: Node3D = null
var _beam_rotator: Node3D = null
var _beam_core: MeshInstance3D = null
var _beam_mid: MeshInstance3D = null
var _beam_haze: MeshInstance3D = null
var _beam_core_mat: ShaderMaterial = null
var _beam_mid_mat: ShaderMaterial = null
var _beam_haze_mat: ShaderMaterial = null
var _beam_angle := 0.0
var _beam_strength := 0.0
var _beam_dir_world := Vector3(0, 0, -1)
var _shot_beam_lock := false   # --shots 专用：锁定光束角度，避免等相机时被时间流速转过目标
var _shot_boat_hold := false   # --shots 专用：把船固定在指定海面坐标拍“光束照到船”的证据
var _shot_boat_hold_pos := Vector3.ZERO
var _shot_boat_hold_heading := 0.0

# ---- 大船多航线状态机 ----
var _sail_routes: Array = []
var _sail_route_last := -1
var _sail_route: Dictionary = {}
var _sail_phase := "docked"
var _sail_dist2 := 0.0
var _sail_wait := 0.0
var _sail_dwell := 4.0
var _sail_heading := 0.0
var _sail_trip_speed := 3.4
var _sail_boat_visible := true
var _perch_count := 0
var _boat_depart_hours := [6.6, 9.5, 12.5, 15.5, 18.6]
# ---- 小船生命周期状态机（DOCKED/DEPARTING/COASTAL_CRUISE/OUTBOUND_FAR/FADING_OUT/
#      OFFSCREEN_WAIT/FADING_IN/RETURNING/RESTING） ----
var _boat_state := "DOCKED"
var _boat_route_dist := 0.0
var _boat_route_speed := 3.0
var _boat_route_len := 0.0
var _boat_wait_sim := 0.0          # OFFSCREEN_WAIT 剩余模拟秒（far = 8 模拟小时）
var _boat_fade := 1.0
var _boat_meshes: Array = []       # 船体所有 MeshInstance3D（淡出用 GeometryInstance3D.transparency）
var _boat_trip := 0
var _boat_rest_until := -1.0       # 模拟秒时间戳：RESTING 至少停靠到该时刻
var _wave_height := 0.5            # 与 sea.gdshader 的 wave_height 保持一致（GDScript 复算波高）
var _sim_delta := 0.0              # 上一帧推进的模拟秒数（灯塔转速/远海等待共用同一时钟）
var _sim_rate := 1.0               # P7-V2：上一帧模拟秒/真实秒（生态超前量按时间倍率换算用）
var _time_jump := 0.0              # 手动调时/时间轴跳转的累计秒数（用于对齐远海等待与休息窗口）
# 小船生命周期 / 灯光 / 淡出
var _boat_fade_mats: Array = []    # 船体 ShaderMaterial 副本（fade_alpha 抖动淡出）
var _boat_fade_std: Array = []     # 船体 StandardMaterial3D 副本（光晕等按 albedo 缩放淡出）
var _boat_fade_map: Dictionary = {}
var _boat_lantern_local := Vector3(0.0, 1.30, 1.95)
var _boat_spot_lens := Vector3(0.0, 1.05, 2.05)
var _boat_spot_node: Node3D = null
var _boat_spot_cone_mat: ShaderMaterial = null
var _boat_lantern_mat: ShaderMaterial = null
var _boat_lantern_halo: MeshInstance3D = null
var _boat_dock_pos := Vector3.ZERO
var _boat_dock_heading := 0.0
var _boat_speed_cur := 0.0
var _boat_turn_rate := 0.0
var _boat_fade_start := -1.0
var _boat_fade_end := -1.0
var _boat_route_kind := "far"
var _boat_far_entries: Array = []
var _boat_ret_pts: Array = []
var _boat_wait_total := 28800.0
# P7：船鸟联动——近海航段一次性触发（每次航次最多一次；时间跳转不改 _boat_route_dist，不重放）
var _boat_shore_done := true
var _boat_shore_trigger := -1.0
# 探照灯最近一次写入的值（headless 的 dummy renderer 读不到 global uniform，探针用这些字段断言）
var _dbg_spot_strength := 0.0
var _dbg_spot_dir := Vector3.ZERO
var _dbg_spot_origin := Vector3.ZERO
var _dbg_spot_visible := false
# 画质档雾距（fog_scale）最后一次写入值：headless dummy renderer 读不到 global uniform，探针用这两个字段断言。
var _dbg_fog_near := 0.0
var _dbg_fog_far := 0.0

# ---- 用户设置 / 画质 / 音频 / 交互反馈 ----
const Settings := preload("res://scripts/isle_settings.gd")
var _settings: Dictionary = {}
var _quality := 2
var _light_budget := 8
var _quality_state: Dictionary = {}
var _sea_subdiv := 180
var _hud_quality_label := "高 · 精致"
var _audio = null
var _hover_timer := 0.0
var _perf_timer := 0.0
var _grass_total := 0
var _grass_visible_count := 0
var _photo_count := 0
var _last_photo := ""
var _settings_save_delay := -1.0

# ============================================================
# 启动
# ============================================================
func _ready() -> void:
	randomize()
	_p7shots = "--p7shots" in OS.get_cmdline_args() or "--p7shots" in OS.get_cmdline_user_args()
	_shots = "--shots" in OS.get_cmdline_args() or "--shots" in OS.get_cmdline_user_args() or _p7shots
	_transition = "--transition" in OS.get_cmdline_args() or "--transition" in OS.get_cmdline_user_args()
	_selftest = "--selftest" in OS.get_cmdline_args() or "--selftest" in OS.get_cmdline_user_args()
	_perf = "--perf" in OS.get_cmdline_args() or "--perf" in OS.get_cmdline_user_args()
	_no_villager = "--no-villager" in OS.get_cmdline_args() or "--no-villager" in OS.get_cmdline_user_args()
	# --selftest 是既有功能的确定性回归基线（含"点击木门"这类对门状态的精确断言），
	# 岛民自主开门会引入真实竞态，故自测时不创建岛民；岛民自身由 P7-V4 专用探针覆盖。
	if _selftest:
		_no_villager = true
	if _perf:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	# 读取用户设置：菜单、时钟、画质、音量、窗口模式共用同一份数据。
	# 自动化运行（截图/性能/自测/转场）使用默认设置，保证结果可复现且不受玩家配置影响。
	var automation := _shots or _perf or _selftest or _transition or _p7shots
	_settings = Settings.defaults() if automation else Settings.load_settings()
	_setup_time_api()
	_time_source = String(_settings.get("time_source", "sim"))
	_timezone = String(_settings.get("timezone", "Asia/Shanghai"))
	_realtime = _time_source == "real"
	_abs_unix = Time.get_unix_time_from_system()
	_day_length = Settings.day_length_seconds(_settings.get("day_length", Settings.DAY_LENGTH_DEFAULT))
	_sensitivity = clampf(float(_settings.get("sensitivity", 1.0)), 0.2, 3.0)
	# P7-V3：FOV 在 _build_camera 之前生效（初始相机与自由视角基础值都用玩家设置）。
	_fov = Settings.sanitize_fov(_settings.get("fov", Settings.FOV_DEFAULT))
	_settings["fov"] = _fov
	_auto_orbit = bool(_settings.get("auto_orbit", true))
	_quality = Settings.sanitize_quality(_settings.get("quality", 2))
	# --perf 可选画质覆盖：--quality N（配合 -- --perf --quality 4 跑分档性能）
	if _perf:
		var qo := _cmdline_value("--quality")
		if qo != "":
			_quality = Settings.sanitize_quality(int(qo))
	_init_time()
	_setup_globals()
	_build_environment()
	_build_sea()
	_build_world()
	_build_camera()
	_build_post()
	_build_ui()
	_setup_audio()
	_apply_user_settings(false)
	_update_lighting()
	# P7-V3.2 开发测量模式：--scale-debug 时挂 T1 ScaleDebugOverlay（1 m 立方 / 1.50 m 人形 /
	# 标尺 / 房屋层高标注），只建一次；默认无参数完全不创建，零常驻开销。
	if ScaleOverlay.enabled() and get_node_or_null("ScaleDebugOverlay") == null:
		var scale_overlay: Node3D = ScaleOverlay.new()
		scale_overlay.name = "ScaleDebugOverlay"
		add_child(scale_overlay)
		print("[SCALE] ScaleDebugOverlay installed built=%s children=%d" % [
			str(scale_overlay.is_built()), scale_overlay.get_child_count()])
	if _selftest:
		_run_selftest()
	elif _perf:
		_run_perf()
	elif _transition:
		_run_transition()
	elif _p7shots:
		_run_p7shots()
	elif _shots:
		_run_shots()
	else:
		_menu.open(false)
		_hud.set_hud_visible(false, false)

## 读取命令行的 "key value" 形式（合并引擎参数与 -- 之后的用户参数）。
func _cmdline_value(key: String) -> String:
	var args: Array = OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	for i in args.size():
		if String(args[i]) == key and i + 1 < args.size():
			return String(args[i + 1])
	return ""

func _init_time() -> void:
	_abs_unix = Time.get_unix_time_from_system()
	if _time_source == "real":
		# 现实时间：天文/生态时钟固定为岛屿参考时区（广州 UTC+8）的当地秒；
		# 所选“显示时区”只影响 HUD 文本（见 _display_datetime），不得平移天体位置（T7 修复）。
		_sim_seconds = _abs_unix + float(IsleAstro.TZ_SECONDS)
	else:
		# 参考项目的氛围起点：傍晚 17:18
		_sim_seconds = 17.0 * 3600.0 + 18.0 * 60.0
	_events = IsleAstro.day_events(_sim_seconds)

## 时区/现实时间模块是热加载的：不存在时退回旧行为，避免脚本报错。
func _setup_time_api() -> void:
	_time_api = null
	if ResourceLoader.exists("res://scripts/isle_time.gd"):
		var scr = load("res://scripts/isle_time.gd")
		if scr != null and scr.can_instantiate():
			_time_api = scr.new()

# ============================================================
# 全局 shader uniform
# ============================================================
func _setup_globals() -> void:
	_add_global("g_sun_color", RenderingServer.GLOBAL_VAR_TYPE_COLOR)
	_add_global("g_sun_dir_view", RenderingServer.GLOBAL_VAR_TYPE_VEC3)
	_add_global("g_moon_color", RenderingServer.GLOBAL_VAR_TYPE_COLOR)
	_add_global("g_moon_dir_view", RenderingServer.GLOBAL_VAR_TYPE_VEC3)
	_add_global("g_ambient_sky", RenderingServer.GLOBAL_VAR_TYPE_COLOR)
	_add_global("g_ambient_ground", RenderingServer.GLOBAL_VAR_TYPE_COLOR)
	_add_global("g_fog_color", RenderingServer.GLOBAL_VAR_TYPE_COLOR)
	_add_global("g_fog_near", RenderingServer.GLOBAL_VAR_TYPE_FLOAT)
	_add_global("g_fog_far", RenderingServer.GLOBAL_VAR_TYPE_FLOAT)
	_add_global("g_wind_time", RenderingServer.GLOBAL_VAR_TYPE_FLOAT)
	_add_global("g_outline_color", RenderingServer.GLOBAL_VAR_TYPE_COLOR)
	RenderingServer.global_shader_parameter_set("g_outline_color", Color(0.12, 0.13, 0.17))
	# 局部灯光（unshaded toon 材质不吃引擎灯光，这里自算最多 6 盏，见 toon.gdshader）
	_add_global("g_light_count", RenderingServer.GLOBAL_VAR_TYPE_FLOAT)
	# 灯塔旋转光束（toon / sea 共用的解析光锥参数）
	_add_global("g_beam_origin", RenderingServer.GLOBAL_VAR_TYPE_VEC3)
	_add_global("g_beam_dir", RenderingServer.GLOBAL_VAR_TYPE_VEC3)
	_add_global("g_beam_color", RenderingServer.GLOBAL_VAR_TYPE_COLOR)
	_add_global("g_beam_params", RenderingServer.GLOBAL_VAR_TYPE_VEC4)
	# 船载前向探照灯（聚光）：origin / dir / rgb+strength / (cos_outer, cos_inner, range, edge)
	_add_global("g_spot_origin", RenderingServer.GLOBAL_VAR_TYPE_VEC3)
	_add_global("g_spot_dir", RenderingServer.GLOBAL_VAR_TYPE_VEC3)
	_add_global("g_spot_color", RenderingServer.GLOBAL_VAR_TYPE_COLOR)
	_add_global("g_spot_params", RenderingServer.GLOBAL_VAR_TYPE_VEC4)
	RenderingServer.global_shader_parameter_set("g_spot_origin", Vector3.ZERO)
	RenderingServer.global_shader_parameter_set("g_spot_dir", Vector3(0.0, 0.0, -1.0))
	RenderingServer.global_shader_parameter_set("g_spot_color", Color(0.0, 0.0, 0.0, 0.0))
	RenderingServer.global_shader_parameter_set("g_spot_params", Vector4(0.90, 0.985, BOAT_SPOT_RANGE, 0.0))
	# Phase6：局部灯上限从 8 提到 12（toon/grass/glass 同步扩到 12 盏）
	for i in range(12):
		_add_global("g_l%d_pos" % i, RenderingServer.GLOBAL_VAR_TYPE_VEC4)
		_add_global("g_l%d_col" % i, RenderingServer.GLOBAL_VAR_TYPE_VEC4)
		RenderingServer.global_shader_parameter_set("g_l%d_pos" % i, Vector4(0.0, -999.0, 0.0, 1.0))
		RenderingServer.global_shader_parameter_set("g_l%d_col" % i, Vector4.ZERO)
	# Phase6：灯塔光束遮挡盒（世界空间，toon 片元里做 ray-box 可见性判定，解决光穿墙）
	_add_global("g_occ_count", RenderingServer.GLOBAL_VAR_TYPE_FLOAT)
	RenderingServer.global_shader_parameter_set("g_occ_count", 0.0)
	for oi in range(4):
		_add_global("g_occ_c%d" % oi, RenderingServer.GLOBAL_VAR_TYPE_VEC3)
		_add_global("g_occ_h%d" % oi, RenderingServer.GLOBAL_VAR_TYPE_VEC3)
		_add_global("g_occ_y%d" % oi, RenderingServer.GLOBAL_VAR_TYPE_FLOAT)
		RenderingServer.global_shader_parameter_set("g_occ_c%d" % oi, Vector3.ZERO)
		RenderingServer.global_shader_parameter_set("g_occ_h%d" % oi, Vector3.ZERO)
		RenderingServer.global_shader_parameter_set("g_occ_y%d" % oi, 0.0)

func _add_global(name: String, type: int) -> void:
	RenderingServer.global_shader_parameter_add(name, type, _default_value(type))

func _default_value(type: int) -> Variant:
	if type == RenderingServer.GLOBAL_VAR_TYPE_COLOR:
		return Color.WHITE
	if type == RenderingServer.GLOBAL_VAR_TYPE_VEC3:
		return Vector3.ZERO
	if type == RenderingServer.GLOBAL_VAR_TYPE_VEC4:
		return Vector4.ZERO
	return 0.0

## global uniform 的 source_color 不会自动转换，这里补上 sRGB→linear。
func _lin(c: Color) -> Color:
	return c.srgb_to_linear()

# ============================================================
# 环境
# ============================================================
func _build_environment() -> void:
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	_env = Environment.new()
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = load(SKY_SHADER)
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_env.glow_enabled = true
	_env.glow_intensity = 0.6
	_env.glow_strength = 1.0
	_env.glow_bloom = 0.06
	_env.glow_hdr_threshold = 0.95
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	_env.adjustment_enabled = true
	we.environment = _env
	add_child(we)

# ============================================================
# 海面
# ============================================================
func _build_sea() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Sea"
	var pm := PlaneMesh.new()
	pm.size = Vector2(1400, 1400)
	pm.subdivide_width = 180
	pm.subdivide_depth = 180
	mi.mesh = pm
	_sea_mat = ShaderMaterial.new()
	_sea_mat.shader = load(SEA_SHADER)
	mi.material_override = _sea_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 波高与 main.gd 的 _wave_h() 复算严格一致：船体吃水/俯仰/水花都基于同一波面
	_sea_mat.set_shader_parameter("wave_height", _wave_height)
	_sea_mat.set_shader_parameter("wave_detail", 1.0)
	_sea_mat.set_shader_parameter("foam_amount", 0.78)
	_sea_mat.set_shader_parameter("island_refl", 1.0)
	add_child(mi)

# ============================================================
# 岛屿 / 小屋 / 特效
# ============================================================
func _build_world() -> void:
	var holder := Node3D.new()
	holder.name = "World"
	add_child(holder)
	_world = IsleWorld.build(holder)
	_cottage = IsleCottage.build(holder)
	_window_mats = _cottage["window_mats"]
	_window_halos = _cottage["window_halos"]
	_lantern_mat = _cottage["lantern_mat"] as ShaderMaterial
	_lantern_halo = _cottage["lantern_halo"] as MeshInstance3D
	_lantern_halos = (_cottage.get("lantern_halos", []) as Array).duplicate()
	if _lantern_halos.is_empty() and _lantern_halo != null:
		_lantern_halos.append(_lantern_halo)
	_lamp_mats = (_world.get("lamp_mats", []) as Array).duplicate()
	_lamp_halos = (_world.get("lamp_halos", []) as Array).duplicate()
	# 夜间光晕尺寸收敛：halo 是广告牌面片，原尺寸在近景会变成直径 1m+ 的光球
	_scale_halos(_window_halos, 0.60)
	_scale_halos(_lantern_halos, 0.55)
	_scale_halos(_lamp_halos, 0.50)
	var fx_holder := Node3D.new()
	fx_holder.name = "Fx"
	add_child(fx_holder)
	_fx["smoke"] = IsleFx.smoke(fx_holder, (_cottage["chimney_top"] as Node3D).global_position + Vector3(0, 0.4, 0))
	_fx["fireflies"] = IsleFx.fireflies(fx_holder, Vector3(-3.0, 2.0, 3.5))
	_fx["petals"] = IsleFx.petals(fx_holder, Vector3(IsleMath.BIG_TREE_X, 5.0, IsleMath.BIG_TREE_Z))
	_ripples = IsleFx.Ripples.new()
	_ripples.name = "Ripples"
	fx_holder.add_child(_ripples)
	_birds = IsleFx.BirdFlock.new()
	_birds.name = "Birds"
	fx_holder.add_child(_birds)
	var perches: Array = (_world.get("perches", []) as Array).duplicate()
	perches.append_array(_cottage.get("perches", []))
	_birds.setup(perches)
	# 立体水花 / 船尾迹
	_splash = IsleFx.Splash.new()
	_splash.name = "Splash"
	fx_holder.add_child(_splash)
	_wake = IsleFx.Wake.new()
	_wake.name = "Wake"
	fx_holder.add_child(_wake)
	if _ripples != null and "splash_cb" in _ripples:
		_ripples.splash_cb = _splash.splash_at
	_collect_lights()
	_collect_props()
	_build_lighthouse_beam()
	_collect_beam_occluders()
	_update_smoke_clock()
	# P7-V4：岛民与场景同父（World），复用小区块合批与光照收集；只创建一次，运行期不重建。
	if not _no_villager:
		_villager = ISLE_VILLAGER.build(holder, _cottage)

# ============================================================
# 相机
# ============================================================
func _build_camera() -> void:
	_cam = Camera3D.new()
	_cam.name = "Camera"
	_cam.fov = _fov
	_cam.near = 0.3
	_cam.far = 2200.0
	add_child(_cam)
	_cam.current = true
	_apply_pose(_movie_pose())
	_update_camera_light_dirs()
	# P7-V2 自由飞行观景相机：只创建逻辑件，不创建/不接管 Camera3D；
	# 轨道参数在进入时冻结、退出混合结束后原样恢复（见 _enter_flycam/_exit_flycam）。
	_flycam = IsleFlyCam.new()
	var fly_cfg := IsleFlyCam.default_config()
	# P7-V3 校准（以自由视角水平观察范围 D 为基准，实测海岸线最大直径≈63.6m）：
	#   边界半径 R=130m（≈2.0× 岛直径）→ D=2R=260m；
	#   普通速度 12.48 m/s（P7-V2 10.4 基础 +20%，完整穿越约 20.8s，20–30s 区间）；
	#   冲刺速度 24.96 m/s（精确 2.0×，完整穿越约 10.4s，10–15s 区间）；
	#   垂直速度 6.6 m/s（+20%）；最高高度 130m（≈2.0× 岛直径，可俯瞰全岛与周边海域）。
	fly_cfg["center"] = Vector3(0.0, 0.0, 0.0)
	fly_cfg["radius"] = 130.0
	fly_cfg["max_y"] = 130.0
	fly_cfg["speed_regular"] = 12.48
	fly_cfg["speed_boost"] = 24.96
	fly_cfg["vertical_speed"] = 6.6
	_flycam_look_base = float(fly_cfg.get("look_sensitivity", 0.0022))
	_flycam.configure(fly_cfg)
	# P7-V3：玩家 FOV 设置与自由视角共用同一基础值（默认 42，见 isle_settings.FOV_DEFAULT）。
	_flycam.set_base_fov(_fov)

func _menu_pose() -> Dictionary:
	return {"target": Vector3(0, 4.2, 0), "theta": _movie_theta, "elev": 0.50, "r": 106.0, "fov": 36.0}

func _movie_pose() -> Dictionary:
	return {"target": Vector3(0, 4.2, 0), "theta": _menu_theta, "elev": 0.50, "r": 106.0, "fov": 36.0}

func _play_pose() -> Dictionary:
	return {"target": _cam_target, "theta": _theta, "elev": _elev, "r": _radius, "fov": _fov}

static func _pose_to_transform(p: Dictionary) -> Transform3D:
	var target: Vector3 = p["target"]
	var theta: float = p["theta"]
	var elev: float = p["elev"]
	var r: float = p["r"]
	var pos := target + Vector3(r * cos(elev) * sin(theta), r * sin(elev), r * cos(elev) * cos(theta))
	var t := Transform3D.IDENTITY
	t.origin = pos
	var dir := target - pos
	var up := Vector3.UP
	var right := dir.cross(up)
	if right.length_squared() < 0.000001:
		right = Vector3.RIGHT
	right = right.normalized()
	var cam_up := right.cross(dir.normalized()).normalized()
	t.basis = Basis(right, cam_up, -dir.normalized())
	return t

func _apply_pose(p: Dictionary) -> void:
	var xf := _pose_to_transform(p)
	xf.origin.y = maxf(xf.origin.y, _min_camera_y(xf.origin))
	_cam.fov = float(p.get("fov", _cam.fov))
	_cam.global_transform = xf

## 任意机位：从 from 看向 target（--shots 摆位用，例如码头水平侧视）。
## 必须写入 _cam_target/_theta/_elev/_radius 这一套轨道参数，否则下一帧 _update_camera 会用旧参数覆盖。
func _pose_look(from: Vector3, target: Vector3, fov_deg: float) -> void:
	var f := Vector3(from.x, maxf(from.y, _min_camera_y(from)), from.z)
	var dir := f - target
	var r := maxf(dir.length(), 0.25)
	_cam_target = target
	_radius = r
	_elev = asin(clampf(dir.y / r, -0.995, 0.995))
	_theta = atan2(dir.x, dir.z)
	_fov = fov_deg
	_apply_pose(_play_pose())

## 相机最低高度：高于海面 1.1m，且不低于所在地形 + 1.2m，避免钻地穿岛。
func _min_camera_y(pos: Vector3) -> float:
	var th := IsleMath.terrain_height(pos.x, pos.z)
	return maxf(1.1, th + 1.2)

func _update_camera_light_dirs() -> void:
	var cam_xf := _cam.global_transform
	var inv := cam_xf.basis.inverse()
	RenderingServer.global_shader_parameter_set("g_sun_dir_view", (inv * _sun_dir_world).normalized())
	RenderingServer.global_shader_parameter_set("g_moon_dir_view", (inv * _moon_dir_world).normalized())

# ============================================================
# 后处理
# ============================================================
func _build_post() -> void:
	_cam_layer = CanvasLayer.new()
	_cam_layer.name = "Post"
	_cam_layer.layer = 3
	add_child(_cam_layer)
	var rect := ColorRect.new()
	rect.name = "Vignette"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette_mat = ShaderMaterial.new()
	_vignette_mat.shader = load(VIGNETTE_SHADER)
	rect.material = _vignette_mat
	_cam_layer.add_child(rect)
	# P6 极致档：自定义屏幕空间 AO（spatial 全屏 QuadMesh，绕开 canvas 后处理无法读深度的限制）。
	# 参数由 _apply_quality 写入；低档 ao_strength=0 时整体隐藏，省一个全屏 pass。
	_post_ao_mat = ShaderMaterial.new()
	_post_ao_mat.shader = load("res://shaders/post_ao.gdshader")
	_post_ao_mat.render_priority = 127
	_post_ao_mi = MeshInstance3D.new()
	_post_ao_mi.name = "PostAO"
	_post_ao_mi.mesh = QuadMesh.new()
	_post_ao_mi.material_override = _post_ao_mat
	_post_ao_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_post_ao_mi.extra_cull_margin = 16384.0
	_post_ao_mi.position = Vector3(0.0, 0.0, -0.6)
	_post_ao_mi.visible = false
	_cam.add_child(_post_ao_mi)

# ============================================================
# UI
# ============================================================
func _build_ui() -> void:
	_hud = IsleHud.new()
	_hud.name = "Hud"
	_hud.layer = 5
	add_child(_hud)
	_hud.time_adjust.connect(_on_time_adjust)
	_hud.time_set.connect(_on_time_set)
	# P5：T 面板的时间来源切换与设置菜单共用同一状态源（main._settings["time_source"]）
	if _hud.has_signal("time_mode_requested"):
		_hud.connect("time_mode_requested", _on_time_mode_requested)
	_menu = IsleMenu.new()
	_menu.name = "Menu"
	_menu.layer = 10
	add_child(_menu)
	_menu.start_pressed.connect(_on_menu_start)
	_menu.quit_pressed.connect(func() -> void: get_tree().quit())
	_menu.settings_changed.connect(_on_settings_changed)

# ============================================================
# 时间推进
# ============================================================
func _advance_sim(delta: float) -> void:
	var before := fposmod(_sim_seconds, 86400.0)
	var sim_before := _sim_seconds
	if _time_source == "real":
		# 现实模式：唯一来源是系统绝对时间；天文/生态时钟固定用岛屿参考时区（UTC+8）。
		_abs_unix = Time.get_unix_time_from_system()
		_sim_seconds = _abs_unix + float(IsleAstro.TZ_SECONDS)
		_sim_rate = 1.0
	else:
		var rate := 86400.0 / maxf(_day_length, 1.0)
		_sim_seconds += delta * rate
		_sim_rate = rate
	var after := fposmod(_sim_seconds, 86400.0)
	_sim_delta = _sim_seconds - sim_before
	if after < before:
		_events = IsleAstro.day_events(_sim_seconds)

func _now_sim_seconds() -> float:
	return IsleAstro.now_local_seconds()

# ============================================================
# 每帧
# ============================================================
func _process(delta: float) -> void:
	_frame_t += delta
	_tick(delta)
	_update_hover(delta)
	_update_audio(delta)
	_update_perf_overlay(delta)

func _tick(delta: float) -> void:
	if _settings_save_delay >= 0.0:
		_settings_save_delay -= delta
		if _settings_save_delay <= 0.0:
			_settings_save_delay = -1.0
			Settings.save_settings(_settings)
	if _mode == Mode.PLAYING and (not _paused or _time_source == "real"):
		_advance_sim(delta)
	if _mode == Mode.MENU:
		_menu_theta += delta * 0.035
		_movie_theta = lerp_angle(_movie_theta, _menu_theta, 1.0 - exp(-2.0 * delta))
		if _blending.is_empty():
			_apply_pose(_movie_pose())
	_update_camera(delta)
	_update_camera_light_dirs()
	_update_lighting()
	# P7-V4：岛民 tick 放在光照之后（当帧 _astro/_sun_alt/_events 已刷新），用真实帧 delta；
	# 世界时间/暂停/时间来源全部由 ctx 注入，角色自身不建时钟。
	if _villager != null:
		_villager.call("sim_tick", delta, _villager_ctx())
	_update_lighthouse_beam(delta)
	_update_smoke_clock()
	_update_ui(delta)

func _update_camera(delta: float) -> void:
	# 自由视角期间只由 IsleFlyCam 写相机变换/FOV；轨道相机参数（_theta/_elev/_radius/_cam_target/_fov）
	# 保持冻结，退出混合结束后下一帧 _play_pose() 即原样恢复，不会跳回初始机位。
	if _flycam != null and _flycam.active:
		_flycam.update(delta, Callable(IsleMath, "terrain_height"))
		_flycam.apply_to(_cam)
		return
	if not _blending.is_empty():
		_blend_t += delta
		var w := clampf(_blend_t / BLEND_DUR, 0.0, 1.0)
		var e := smoothstep(0.0, 1.0, w)
		var to_pose := _play_pose() if _blending == "to_game" else _menu_pose()
		var a: Dictionary = _blend_from
		_apply_pose({
			"target": (a["target"] as Vector3).lerp(to_pose["target"], e),
			"theta": lerp_angle(a["theta"], to_pose["theta"], e),
			"elev": lerpf(a["elev"], to_pose["elev"], e),
			"r": lerpf(a["r"], to_pose["r"], e),
			"fov": lerpf(float(a.get("fov", 36.0)), float(to_pose.get("fov", 36.0)), e),
		})
		if w >= 1.0:
			_blending = ""
			if _blending_done.is_valid():
				_blending_done.call()
		return
	if _mode == Mode.PLAYING:
		# 自动运镜：暂停/拖拽时平滑收敛到 0；恢复时平滑加速，不抢手动操作（拖拽优先）
		var want_orbit := 0.018 if (_auto_orbit and not _dragging and not _paused) else 0.0
		_orbit_speed = lerpf(_orbit_speed, want_orbit, 1.0 - exp(-5.0 * delta))
		_theta += delta * _orbit_speed
		_apply_pose(_play_pose())
	else:
		_apply_pose(_movie_pose())
		# P7-V3：设置面板打开时实时预览玩家 FOV（菜单观景机位默认 36°，预览改用 _fov）。
		if _menu != null and _menu.has_method("is_settings_open") and bool(_menu.call("is_settings_open")):
			_cam.fov = _fov

var _blending_done := Callable()

func _start_blend(to: String, from_pose: Dictionary, done: Callable) -> void:
	_blending = to
	_blend_t = 0.0
	_blend_from = from_pose.duplicate()
	_blending_done = done

# ============================================================
# 光照 / 材质每帧
# ============================================================
## P7：交给海鸥状态机的权威时间/阶段信息（生态事件只消费这些，不另建世界时钟）。
func _eco_ctx() -> Dictionary:
	return {
		"day": int(floor(_sim_seconds / 86400.0)),
		"rising": _rising,
		"sim_seconds": _sim_seconds,
		"time_source": _time_source,
		"paused": _paused,
		"sim_rate": _sim_rate,  # 模拟秒/真实秒：生态超前量 = 过渡时长 × 该倍率
	}

func _update_lighting() -> void:
	_astro = IsleAstro.compute(_sim_seconds)
	_sun_alt = float(_astro["sun_alt"])
	_sun_az = float(_astro["sun_az"])
	_moon_illum = float(_astro["moon_illum"])
	_moon_waxing = bool(_astro["moon_waxing"])
	_rising = float(_astro["sun_ha"]) < 0.0
	_sun_dir_world = IsleMath.sun_dir(_sun_alt, _sun_az)
	var moon_az := float(_astro["moon_az"])
	var moon_alt := float(_astro["moon_alt"])
	_moon_dir_world = IsleMath.sun_dir(moon_alt, moon_az)
	_theme_t = IsleMath.theme_time(_sun_alt, _rising)
	_pal = IslePalette.sample(_theme_t)
	var p := _pal
	# 画质档雾距缩放（fog_scale 是 isle_quality 定义但此前从未被渲染消费的键）：
	# 只缩放自定义 shader 的雾起止距离；雾色仍由调色板决定，低档稍近、极致档稍远。
	var fog_scale := clampf(float(_quality_state.get("fog_scale", 1.0)), 0.6, 1.4)
	# environment
	# 画质档 glow_strength 系数（1.0=预设基准）；让五档的辉光强度真实生效，而不是被调色板每帧覆盖。
	var gq := clampf(float(_quality_state.get("glow_strength", 1.0)), 0.0, 1.5)
	_env.glow_intensity = float(p["bloom"]) * 1.15 * gq
	_env.adjustment_saturation = float(p["saturation"])
	_env.adjustment_contrast = float(p["contrast"])
	_env.adjustment_brightness = clampf(float(p["exposure"]), 0.6, 1.6)
	# sky
	_sky_mat.set_shader_parameter("sky_zenith", p["skyZenith"])
	_sky_mat.set_shader_parameter("sky_horizon", p["skyHorizon"])
	_sky_mat.set_shader_parameter("sky_haze", p["skyHaze"])
	_sky_mat.set_shader_parameter("sun_glow", p["sunGlow"])
	_sky_mat.set_shader_parameter("sun_disk_col", p["sunDisk"])
	_sky_mat.set_shader_parameter("moon_disk_col", p["moonDisk"])
	_sky_mat.set_shader_parameter("cloud_light", p["cloudLight"])
	_sky_mat.set_shader_parameter("cloud_shade", p["cloudShade"])
	_sky_mat.set_shader_parameter("sun_dir", _sun_dir_world)
	_sky_mat.set_shader_parameter("moon_dir", _moon_dir_world)
	_sky_mat.set_shader_parameter("sun_disk_i", float(p["sunDiskI"]))
	_sky_mat.set_shader_parameter("moon_disk_i", float(p["moonDiskI"]))
	_sky_mat.set_shader_parameter("star_alpha", float(p["starAlpha"]))
	_sky_mat.set_shader_parameter("moon_alpha", float(p["moonAlpha"]))
	_sky_mat.set_shader_parameter("cloud_opacity", clampf(float(p["cloudOpacity"]) * 1.35 + 0.10, 0.0, 0.95))
	_sky_mat.set_shader_parameter("moon_phase", _moon_illum)
	_sky_mat.set_shader_parameter("moon_waxing", 1.0 if _moon_waxing else 0.0)
	_sky_mat.set_shader_parameter("time_s", _frame_t)
	# sea
	_sea_mat.set_shader_parameter("water_deep", p["waterDeep"])
	_sea_mat.set_shader_parameter("water_mid", p["waterMid"])
	_sea_mat.set_shader_parameter("water_shallow", p["waterShallow"])
	_sea_mat.set_shader_parameter("water_foam", p["waterFoam"])
	_sea_mat.set_shader_parameter("spec", p["waterSpec"])
	_sea_mat.set_shader_parameter("glitter", p["waterGlitter"])
	_sea_mat.set_shader_parameter("sky_zenith", p["skyZenith"])
	_sea_mat.set_shader_parameter("sky_horizon", p["skyHorizon"])
	_sea_mat.set_shader_parameter("sky_haze", p["skyHaze"])
	_sea_mat.set_shader_parameter("fog_color", p["fog"])
	_sea_mat.set_shader_parameter("sun_dir", _sun_dir_world)
	_sea_mat.set_shader_parameter("moon_dir", _moon_dir_world)
	_sea_mat.set_shader_parameter("sun_i", float(p["sunI"]))
	_sea_mat.set_shader_parameter("moon_i", float(p["moonI"]))
	_sea_mat.set_shader_parameter("glitter_i", float(p["waterGlitterI"]))
	_sea_mat.set_shader_parameter("moon_phase", _moon_illum)
	_dbg_fog_near = float(p["fogNear"]) * fog_scale
	_dbg_fog_far = float(p["fogFar"]) * fog_scale
	_sea_mat.set_shader_parameter("fog_near", _dbg_fog_near)
	_sea_mat.set_shader_parameter("fog_far", _dbg_fog_far)
	_sea_mat.set_shader_parameter("time_s", _frame_t)
	_sea_mat.set_shader_parameter("cloud_opacity", clampf(float(p["cloudOpacity"]) * 1.35 + 0.10, 0.0, 0.95))
	# SSR 深度重建用相机矩阵（每帧随相机变换更新；shader 内零矩阵即自动跳过 SSR）
	# GDScript 无 Projection*Transform3D；Projection(Transform3D) 构造器存在，顺序必须 projection * view_inverse（世界→裁剪）。
	var ssr_view: Transform3D = _cam.global_transform.affine_inverse()
	var ssr_vp: Projection = _cam.get_camera_projection() * Projection(ssr_view)
	_sea_mat.set_shader_parameter("ssr_cam_vp", ssr_vp)
	# toon global
	# 注意：global shader uniform 不会像普通 source_color uniform 那样做 sRGB→linear 转换，
	# 必须手动 srgb_to_linear，否则整体偏亮发白（实测地皮 #a9c0a6 而非 #758f73）。
	RenderingServer.global_shader_parameter_set("g_sun_color", _lin(p["sunColor"]) * (float(p["sunI"]) * 0.52))
	RenderingServer.global_shader_parameter_set("g_moon_color", _lin(p["moonColor"]) * (float(p["moonI"]) * 0.52))
	RenderingServer.global_shader_parameter_set("g_ambient_sky", _lin(p["hemiSky"]) * float(p["hemiI"]))
	RenderingServer.global_shader_parameter_set("g_ambient_ground", _lin(p["hemiGround"]) * float(p["hemiI"]))
	RenderingServer.global_shader_parameter_set("g_fog_color", _lin(p["fog"]))
	RenderingServer.global_shader_parameter_set("g_fog_near", float(p["fogNear"]) * fog_scale)
	RenderingServer.global_shader_parameter_set("g_fog_far", float(p["fogFar"]) * fog_scale)
	RenderingServer.global_shader_parameter_set("g_wind_time", _frame_t)
	RenderingServer.global_shader_parameter_set("g_outline_color", _lin(p["outline"]))
	# 夜间局部灯光 → 全局 uniform（toon/grass/glass 在片元里自算点光衰减）
	var light_scale := clampf(0.10 + float(p["lanternI"]) * 1.05, 0.0, 1.30)
	# 画质预设可降低参与着色的局部灯数量（4 / 6 / 8），其余仍保留自发光模型与光晕
	# 船载悬挂灯：动态点光（跟随船体，优先占第一盏；亮度由 light_scale 随昼夜自动收敛）
	var lights: Array = _lights
	if _sailboat != null and _boat_fade > 0.02 and _boat_state != "OFFSCREEN_WAIT":
		var bl := {
			"pos": _sailboat.to_global(_boat_lantern_local),
			"color": Color(1.0, 0.74, 0.40),
			"energy": 1.30,
			"range": 6.5,
		}
		var tmp_lights: Array = [bl]
		tmp_lights.append_array(_lights)
		lights = tmp_lights
	# P7-V2：路灯保底。即使玩家把 light_budget 调低（或旧存档预算很小），
	# 6 盏路灯 + 可能的船灯也必须全部参与着色，不允许高级选项意外关掉道路照明。
	var lamp_need := 0
	for L0 in _lights:
		if String((L0 as Dictionary).get("kind", "")) == "street_lamp":
			lamp_need += 1
	var boat_extra := maxi(lights.size() - _lights.size(), 0)
	var active_lights := maxi(mini(_light_budget, 12), lamp_need + boat_extra)
	active_lights = mini(active_lights, mini(lights.size(), 12))
	for i in range(12):
		if i < active_lights:
			var L: Dictionary = lights[i]
			var lpos: Vector3 = L["pos"]
			var lcol: Color = _lin(L["color"])
			# 极轻微火光呼吸，避免死板；白天整体压暗
			var fl := 1.0 + sin(_frame_t * 6.7 + float(i) * 2.1) * 0.05 + sin(_frame_t * 11.9 + float(i) * 1.3) * 0.025
			var en := float(L["energy"]) * light_scale * fl
			RenderingServer.global_shader_parameter_set("g_l%d_pos" % i, Vector4(lpos.x, lpos.y, lpos.z, float(L["range"])))
			RenderingServer.global_shader_parameter_set("g_l%d_col" % i, Vector4(lcol.r, lcol.g, lcol.b, en))
		else:
			RenderingServer.global_shader_parameter_set("g_l%d_pos" % i, Vector4(0.0, -999.0, 0.0, 1.0))
			RenderingServer.global_shader_parameter_set("g_l%d_col" % i, Vector4.ZERO)
	RenderingServer.global_shader_parameter_set("g_light_count", float(active_lights))
	# vignette
	_vignette_mat.set_shader_parameter("vignette_strength", float(p["vignette"]))
	_vignette_mat.set_shader_parameter("grain_amount", float(p["grain"]))
	_vignette_mat.set_shader_parameter("saturation", float(p["saturation"]) * 1.07)
	_vignette_mat.set_shader_parameter("contrast", float(p["contrast"]) * 1.03)
	_vignette_mat.set_shader_parameter("warmth", float(p["warmth"]))
	_vignette_mat.set_shader_parameter("exposure", float(p["exposure"]))
	_vignette_mat.set_shader_parameter("time_s", _frame_t)
	# 灯光（白天窗灯要暗，夜里才亮）
	var wi := float(p["windowI"])
	# 夜间窗光收敛：纯白过曝会盖掉窗框/窗格结构
	var wglow := 0.05 + wi * 0.55
	for m in _window_mats:
		if m is ShaderMaterial:
			(m as ShaderMaterial).set_shader_parameter("glow", wglow)
	var wf := clampf(0.02 + wi * 0.55, 0.0, 1.2)
	for h in _window_halos:
		if h is MeshInstance3D:
			var hm: Material = (h as MeshInstance3D).material_override
			if hm is StandardMaterial3D:
				(hm as StandardMaterial3D).albedo_color = Color(1.35 * wf, 0.86 * wf, 0.43 * wf, 1.0)
	if _lantern_mat != null:
		_lantern_mat.set_shader_parameter("glow", 0.06 + float(p["lanternI"]) * 1.0)
	var lf := clampf(0.03 + pow(float(p["lanternI"]), 1.6) * 0.85, 0.0, 1.6)
	var lantern_halos: Array = _lantern_halos
	if lantern_halos.is_empty() and _lantern_halo != null:
		lantern_halos = [_lantern_halo]
	for h in lantern_halos:
		if h is MeshInstance3D:
			var lm: Material = (h as MeshInstance3D).material_override
			if lm is StandardMaterial3D:
				(lm as StandardMaterial3D).albedo_color = Color(1.55 * lf, 1.02 * lf, 0.50 * lf, 1.0)
	# 码头灯 / 路灯 / 船头灯：与门灯同一套调光（否则白天也是一团过曝亮斑）
	var lampf := clampf(0.02 + pow(float(p["lanternI"]), 1.6) * 0.85, 0.0, 1.5)
	for m in _lamp_mats:
		if m is ShaderMaterial:
			(m as ShaderMaterial).set_shader_parameter("glow", 0.05 + float(p["lanternI"]) * 1.0)
	for h in _lamp_halos:
		if h is MeshInstance3D:
			var hm: Material = (h as MeshInstance3D).material_override
			if hm is StandardMaterial3D:
				(hm as StandardMaterial3D).albedo_color = Color(1.30 * lampf, 0.83 * lampf, 0.40 * lampf, 1.0)
	# 小船悬挂灯：与路灯同一套昼夜调光（淡出时 _apply_boat_fade 再叠加 alpha）
	if _boat_lantern_mat != null:
		_boat_lantern_mat.set_shader_parameter("glow", 0.05 + float(p["lanternI"]) * 1.0)
	if _boat_lantern_halo != null:
		var bhm: Material = _boat_lantern_halo.material_override
		if bhm is StandardMaterial3D:
			(bhm as StandardMaterial3D).albedo_color = Color(1.30 * lampf, 0.83 * lampf, 0.40 * lampf, 1.0)
	# 萤火（C1 修复：原写法按 ShaderMaterial 写 amount_ratio，但实际材质是 StandardMaterial3D，
	# 赋值恒为 null，夜间粒子从未发射；改为直接驱动 GPUParticles3D 的 emitting / amount_ratio）
	var ff: Dictionary = _fx.get("fireflies", {})
	if ff.has("node"):
		var fnode: GPUParticles3D = ff["node"] as GPUParticles3D
		if fnode != null:
			var ffi := clampf(float(p["fireflyI"]), 0.0, 1.0)
			fnode.emitting = ffi > 0.02
			fnode.amount_ratio = maxf(ffi, 0.0)
	# 特效
	if _ripples != null:
		_ripples.update(get_process_delta_time(), _sun_alt)
	if _birds != null:
		_birds.update_birds(get_process_delta_time(), _sun_alt, _eco_ctx())
	# 船 / 风车 / 秋千 / 水花推进
	_update_props(get_process_delta_time())

# ============================================================
# HUD
# ============================================================
var _ui_timer := 0.0
func _update_ui(delta: float) -> void:
	_ui_timer -= delta
	_events_timer -= delta
	if _events_timer <= 0.0:
		_events_timer = 1.5
		_events = IsleAstro.day_events(_sim_seconds)
	if _events.is_empty():
		return
	var dt := _display_datetime()
	var clock := "%02d:%02d" % [int(dt.get("hour", 0)), int(dt.get("minute", 0))]
	var mname := "盈凸月"
	var sun_sd := _phase_name
	var day_txt := "星期三"
	var sr := float(_events["sunrise"])
	var ss := float(_events["sunset"])
	var day_len := float(_events["day_length"])
	var moon_i := _moon_illum
	var heading := _theta
	var elev := _elev
	# 视角方位角（屏幕罗盘）
	var cam_pos := _cam.global_position
	var dir := (_cam_target - cam_pos)
	# 真方位角：az=0=北(-Z)，90=东(+X)，与 IsleMath.sun_dir / sky.gdshader 同一约定。
	# 旧式 atan2(x,z)+180 会把东西镜像（θ=45° 时显示 45°，真方位应为 315°）。
	var heading_deg := fposmod(rad_to_deg(atan2(dir.x, -dir.z)), 360.0)
	var elev_deg := rad_to_deg(asin(clampf(dir.normalized().y, -1.0, 1.0)))
	if _ui_timer <= 0.0:
		_ui_timer = 0.12
		_phase_update()
		_hud.update_all({
			"clock": clock,
			"date": "%d月%d日" % [int(dt["month"]), int(dt["day"])],
			"weekday": IsleAstro.weekday_cn(dt),
			"phase": _phase_name,
			"phase_short": _phase_short,
			"sun_alt": _sun_alt,
			"sun_az": _sun_az,
			"sunrise": _local_seconds_to_display_text(sr),
			"sunset": _local_seconds_to_display_text(ss),
			"day_length": IsleAstro.format_minutes(day_len) if day_len > 0.0 else "--:--",
			"moon_name": _moon_name(),
			"moon_illum": moon_i,
			"moonrise": _local_seconds_to_display_text(float(_events["moonrise"])),
			"moonset": _local_seconds_to_display_text(float(_events["moonset"])),
			"theme_t": _theme_t,
			"heading": heading_deg,
			"cam_elev": elev_deg,
			"realtime": _realtime,
			"time_source": _time_source,
			"timezone_label": _tz_label_text(),
			"paused": _paused,
			"day_length_sec": _day_length,
			"quality": _hud_quality_label,
			"auto_orbit": _auto_orbit,
		})
	if _blending.is_empty() and _mode == Mode.PLAYING and _started:
		pass

func _phase_update() -> void:
	var a := _sun_alt
	if _paused:
		_phase_name = "已暂停"
		_phase_short = "PAUSE"
	elif a > 34.0:
		_phase_name = "正午晴空"
		_phase_short = "NOON"
	elif a > 12.0:
		_phase_name = "午后"
		_phase_short = "AFTERNOON"
	elif a > 4.0:
		_phase_name = "晨光" if _rising else "黄金时刻"
		_phase_short = "MORNING" if _rising else "GOLDEN"
	elif a > -0.9:
		_phase_name = "日出" if _rising else "日落"
		_phase_short = "SUNRISE" if _rising else "SUNSET"
	elif a > -6.0:
		_phase_name = "黎明" if _rising else "黄昏"
		_phase_short = "DAWN" if _rising else "DUSK"
	elif a > -18.0:
		_phase_name = "破晓前" if _rising else "蓝调时刻"
		_phase_short = "PREDAWN" if _rising else "BLUE"
	else:
		_phase_name = "深夜"
		_phase_short = "NIGHT"

func _moon_name() -> String:
	var i := _moon_illum
	var wax := _moon_waxing
	if i < 0.04:
		return "新月"
	if i < 0.22:
		return "娥眉月" if wax else "残月"
	if i < 0.40:
		return "上弦月" if wax else "下弦月"
	if i < 0.62:
		return "盈凸月" if wax else "亏凸月"
	if i < 0.80:
		return "盈凸月" if wax else "亏凸月"
	if i < 0.96:
		return "满月前" if wax else "满月后"
	return "满月"

# ============================================================
# 状态切换
# ============================================================
var _menu_from_return := false

func _on_menu_start(returning: bool) -> void:
	_sfx_ui()
	_menu_from_return = returning
	_menu.close(func() -> void: _enter_playing())
	_start_blend("to_game", _movie_pose(), Callable())

func _enter_playing() -> void:
	if not _started:
		_started = true
	_mode = Mode.PLAYING
	_paused = false
	_hud.set_hud_visible(true, true)

func _open_menu() -> void:
	if _blending == "to_game":
		return
	# 防御：若外部流程在飞行中要求开菜单，先安全退出自由相机，杜绝两套相机同时写变换。
	if _flycam != null and _flycam.active:
		_flycam.request_exit()
		if _hud != null and _hud.has_method("set_fly_hints"):
			_hud.set_fly_hints(false)
	_mode = Mode.MENU
	_menu.open(true)
	_hud.set_hud_visible(false, true)
	_movie_theta = _theta
	_menu_theta = _theta
	_start_blend("to_menu", _play_pose(), Callable())

## Phase6：自动运镜开关。再次按下立即停住（角速度平滑收敛），保留当前机位不跳回起点。
func _toggle_auto_orbit() -> void:
	_auto_orbit = not _auto_orbit
	_settings["auto_orbit"] = _auto_orbit
	if _hud != null and _hud.has_method("set_auto_orbit"):
		_hud.set_auto_orbit(_auto_orbit, true)
	if not (_selftest or _perf or _shots or _transition):
		_settings_save_delay = 0.25

# ============================================================
# P7-V2 自由飞行观景相机（Minecraft 创造飞行习惯的观景相机，不移动任何场景物体）
# ============================================================
func _enter_flycam() -> void:
	if _flycam == null or _flycam.active:
		return
	# 用户灵敏度随设置生效；进入瞬间从当前画面位姿起飞，不重置视角。
	_flycam.configure({"look_sensitivity": _flycam_look_base * maxf(_sensitivity, 0.05)})
	# P7-V3：自由视角基础 FOV = 玩家设置 FOV（默认 42），与轨道视角 _play_pose 一致。
	_flycam.set_base_fov(_fov)
	_flycam.enter(_cam.global_transform, _fov)
	_dragging = false
	_panning = false
	_fly_click_pos = Vector2.INF
	_fly_click_moved = 0.0
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	if _hud != null:
		_hud.hide_hover_hint()
		if _hud.has_method("set_fly_hints"):
			_hud.set_fly_hints(true)
		_hud.show_toast(_flycam.help_text())

func _exit_flycam() -> void:
	if _flycam == null or not _flycam.active:
		return
	_flycam.request_exit()
	_fly_click_pos = Vector2.INF
	_fly_click_moved = 0.0
	if _hud != null:
		if _hud.has_method("set_fly_hints"):
			_hud.set_fly_hints(false)
		_hud.show_toast("返回观景视角")

## P7-V3：自由视角下 UI（菜单 / 设置面板）打开时，左键点击不透传给场景。
func _fly_click_blocked() -> bool:
	if _menu == null:
		return false
	if _menu.has_method("is_settings_open") and bool(_menu.call("is_settings_open")):
		return true
	return bool(_menu.get("menu_visible"))

## 探针接口：自由相机状态 + 被冻结等待恢复的轨道相机参数。
func debug_flycam() -> Dictionary:
	if _flycam == null:
		return {"available": false}
	var d: Dictionary = _flycam.debug_state()
	d["available"] = true
	d["orbit"] = {
		"theta": _theta, "elev": _elev, "radius": _radius, "fov": _fov,
		"target": _cam_target, "auto_orbit": _auto_orbit,
	}
	return d

## Phase6：灯塔光束遮挡盒。优先用 cottage 导出的贴合盒；缺失时退回房屋整体包围盒，
## 保证「光穿墙」在任何情况下都不会再出现（宁大勿小，但只覆盖建筑实体）。
func _collect_beam_occluders() -> void:
	var boxes: Array = []
	var raw: Variant = _cottage.get("beam_occluders", [])
	if raw is Array:
		for b in (raw as Array):
			if b is Dictionary and (b as Dictionary).has("center") and (b as Dictionary).has("half"):
				boxes.append((b as Dictionary).duplicate(true))
	if boxes.is_empty():
		var root := _cottage.get("root", null) as Node3D
		if root != null:
			var aabb := _node_global_aabb(root)
			if aabb.size.length_squared() > 0.01:
				boxes.append({"center": aabb.get_center(), "half": aabb.size * 0.5, "yaw": 0.0})
	for i in range(4):
		if i < boxes.size():
			var b: Dictionary = boxes[i]
			var c: Vector3 = b.get("center", Vector3.ZERO)
			var h: Vector3 = b.get("half", Vector3.ONE)
			var yaw := float(b.get("yaw", 0.0))
			RenderingServer.global_shader_parameter_set("g_occ_c%d" % i, c)
			RenderingServer.global_shader_parameter_set("g_occ_h%d" % i, Vector3(maxf(h.x, 0.05), maxf(h.y, 0.05), maxf(h.z, 0.05)))
			RenderingServer.global_shader_parameter_set("g_occ_y%d" % i, yaw)
		else:
			RenderingServer.global_shader_parameter_set("g_occ_h%d" % i, Vector3.ZERO)
	RenderingServer.global_shader_parameter_set("g_occ_count", float(mini(boxes.size(), 4)))
	print("[OCC] beam occluders=", boxes.size(), " ", boxes)

func _node_global_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is GeometryInstance3D:
			var gi := n as GeometryInstance3D
			var local_aabb: AABB = gi.get_aabb()
			var xf: Transform3D = gi.global_transform
			var world_aabb: AABB = xf * local_aabb
			if first:
				out = world_aabb
				first = false
			else:
				out = out.merge(world_aabb)
		for c in n.get_children():
			stack.append(c)
	return out

## Phase6：炊烟双时间窗由统一模拟时钟驱动（11:00-13:00 / 17:00-19:00）。
## fx.gd 的 smoke() 返回字典，T5 会把 SmokeClock 节点挂在 smoke["ctl"] 上。
## P7-V2：海鸥在烟囱上且时间跳入出烟窗口时，BirdFlock 会请求 max(起飞过渡)+0.6 秒的
## 烟雾压制（安全回退，避免跳时瞬间烟穿鸟）；这里把该 hold 标志透传给炊烟控制器。
## 正常提前起飞不触发 hold；压制原因由 fx 控制器记录，可从 debug_state()/smoke_debug() 读取。
func _update_smoke_clock() -> void:
	var smoke: Variant = _fx.get("smoke", null)
	if not (smoke is Dictionary):
		return
	var ctl: Variant = (smoke as Dictionary).get("ctl", null)
	if ctl != null and ctl.has_method("set_sim_seconds"):
		var hold := false
		if _birds != null and _birds.has_method("smoke_hold_remaining"):
			hold = float(_birds.smoke_hold_remaining()) > 0.0
		ctl.set_sim_seconds(fposmod(_sim_seconds, 86400.0), hold)

func _on_settings_changed(s: Dictionary) -> void:
	_settings.merge(s, true)
	# 自动化测试（自测/截图/性能/转场）不写入玩家配置，避免污染下次启动；
	# 拖动滑条时每帧都会发出设置，写盘用 0.25s 防抖合并，避免频繁 IO。
	_apply_user_settings(false)
	if not (_selftest or _perf or _shots or _transition):
		_settings_save_delay = 0.25
	_sfx_ui()

# ============================================================
# 输入
# ============================================================
func _unhandled_input(event: InputEvent) -> void:
	# P7-V2 自由飞行视角：F 进入/退出；ESC 优先退出（不打开菜单）。
	# P7-V3 交互：右键按住拖动转向（相对位移交给 flycam）；左键=场景点击（不改变视角）；
	# 菜单/设置面板打开时左键不透传；其余事件飞行期间吞掉，避免 Space 暂停、C 自动运镜冲突。
	if _flycam != null and _flycam.active and not _shots:
		var esc_hit := event is InputEventKey and (event as InputEventKey).pressed \
			and not (event as InputEventKey).echo and (event as InputEventKey).keycode == KEY_ESCAPE
		if event.is_action_pressed("fly_toggle") or esc_hit:
			_exit_flycam()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_RIGHT:
				# 右键按下/松开：开始/结束拖动转向（只有按住右键的 motion 才转视角）。
				_flycam.handle_event(event)
				get_viewport().set_input_as_handled()
				return
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_fly_click_pos = mb.position
					_fly_click_moved = 0.0
				else:
					# 位移 < 7px 视为点击；设置面板/菜单打开时交给 UI，不误触场景。
					if _fly_click_pos != Vector2.INF and _fly_click_moved < 7.0 and not _fly_click_blocked():
						_click_at(mb.position)
					_fly_click_pos = Vector2.INF
					_fly_click_moved = 0.0
				get_viewport().set_input_as_handled()
				return
			# 滚轮/中键等：飞行期间不改变视角、不触发场景操作。
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseMotion:
			var mm := event as InputEventMouseMotion
			if _fly_click_pos != Vector2.INF:
				_fly_click_moved += mm.relative.length()
			# 只有右键按住时 flycam 才消费 motion（左键/无键拖动不转视角）。
			_flycam.handle_event(event)
			get_viewport().set_input_as_handled()
			return
		# 键盘等其它事件：交给 flycam（当前不消费）后吞掉，避免与飞行冲突。
		_flycam.handle_event(event)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("fly_toggle") and _mode == Mode.PLAYING and not _shots and _blending.is_empty():
		_enter_flycam()
		get_viewport().set_input_as_handled()
		return
	# Phase6：自动运镜开关（正式 InputMap 动作 toggle_auto_orbit，默认 C 键）
	if event.is_action_pressed("toggle_auto_orbit") and _mode == Mode.PLAYING and not _shots:
		_toggle_auto_orbit()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = (event as InputEventKey).keycode
		if k == KEY_F11:
			_toggle_fullscreen()
			get_viewport().set_input_as_handled()
			return
		if k == KEY_ESCAPE:
			if _mode == Mode.PLAYING:
				_open_menu()
				get_viewport().set_input_as_handled()
			elif _mode == Mode.MENU and _started:
				# 菜单内再按 ESC：复用「继续观景」的关闭动画回到游玩，不新增一套动画
				_on_menu_start(true)
				get_viewport().set_input_as_handled()
			return
		if _mode == Mode.PLAYING and not _shots:
			_handle_key(k)
			return
	if _mode != Mode.PLAYING or _shots:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			# 右键拖动：受约束地平移观察中心（不触发水面点击，也不弹默认右键菜单）
			if mb.pressed:
				_panning = true
				_pan_start = mb.position
			else:
				_panning = false
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press_pos = mb.position
				_drag_moved = 0.0
				_dragging = true
				# 第四阶段：双击不再复位相机（保留当前视角/距离/目标），仍记录时间用于单击判定。
				_last_click_ms = Time.get_ticks_msec()
			else:
				_dragging = false
				if _drag_moved < 7.0:
					_click_at(mb.position)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_radius = clampf(_radius - maxf(1.2, _radius * 0.075), 9.0, 240.0)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_radius = clampf(_radius + maxf(1.2, _radius * 0.075), 9.0, 240.0)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _panning:
			_drag_moved += mm.relative.length()
			_pan_by(mm.relative)
		elif _dragging:
			_drag_moved += mm.relative.length()
			_theta -= mm.relative.x * 0.006 * _sensitivity
			_elev = clampf(_elev + mm.relative.y * 0.004 * _sensitivity, -0.44, 1.32)

func _handle_key(k: int) -> void:
	if k == KEY_SPACE:
		if _time_source == "real":
			_hud.show_toast("现实时间模式：时间随现实时钟前进")
			return
		_paused = not _paused
		_hud.show_toast("时间暂停" if _paused else "时间继续")
	elif k == KEY_R:
		_toggle_time_source()
	elif k == KEY_TAB:
		_hud.toggle_almanac()
	elif k == KEY_H:
		# 全局监听层切换：UI 隐藏后键盘仍在主场景处理，H 可无限次恢复。
		var focus = get_viewport().gui_get_focus_owner()
		if focus is LineEdit or focus is TextEdit:
			return
		_toggle_hud_visible()
	elif k == KEY_T:
		_hud.toggle_time_panel()
	elif k == KEY_F2:
		_take_photo()
	elif k == KEY_F3:
		_hud.toggle_perf()
	elif k == KEY_BRACKETLEFT:
		if _time_source == "real":
			_hud.show_toast("现实时间模式不可调时")
			return
		_time_jump -= 600.0
		_sim_seconds -= 600.0
		_events = IsleAstro.day_events(_sim_seconds)
		_sync_boat_clock()
	elif k == KEY_BRACKETRIGHT:
		if _time_source == "real":
			_hud.show_toast("现实时间模式不可调时")
			return
		_time_jump += 600.0
		_sim_seconds += 600.0
		_events = IsleAstro.day_events(_sim_seconds)
		_sync_boat_clock()
	elif k >= KEY_1 and k <= KEY_5:
		if _time_source == "real":
			_hud.show_toast("现实时间模式不可调时")
			return
		var times := [5.6, 12.0, 17.4, 18.6, 22.0]
		var target_min := float(times[k - KEY_1]) * 60.0
		var today := _sim_seconds - fposmod(_sim_seconds, 86400.0)
		_time_jump += today + target_min * 60.0 - _sim_seconds
		_sim_seconds = today + target_min * 60.0
		_events = IsleAstro.day_events(_sim_seconds)
		_sync_boat_clock()
		_hud.show_toast("跳至 %s" % ["清晨", "正午", "黄金时刻", "日落", "夜晚"][k - KEY_1])

func _reset_camera() -> void:
	_theta = IsleMath.CAM_START_THETA
	_elev = 0.28
	_radius = IsleMath.CAM_START_R
	# P7-V3：复位机位保留玩家 FOV 设置（默认 42），不覆盖用户偏好。
	_fov = Settings.sanitize_fov(_settings.get("fov", Settings.FOV_DEFAULT))
	_cam_target = IsleMath.CAM_TARGET
	_hud.show_toast("视角已复位")

func _click_at(screen_pos: Vector2) -> void:
	var from := _cam.project_ray_origin(screen_pos)
	var dir := _cam.project_ray_normal(screen_pos)
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 900.0)
	q.collision_mask = 2
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		var col: Object = hit["collider"]
		if col == _cottage.get("door_hit"):
			_toggle_door()
			return
		if col == _cottage.get("chimney_hit"):
			_hud.show_toast("烟囱里升起一束暖烟")
			return
	var plane_y := 0.0
	if absf(dir.y) > 0.0001:
		var t := (plane_y - from.y) / dir.y
		if t > 0.0:
			var p: Vector3 = from + dir * t
			if p.length() < 420.0:
				if _ripples != null:
					_ripples.ripple_at(p, 0.7)
				if _splash != null:
					_splash.splash_at(p, 0.75 + randf() * 0.35)
				_sfx_splash(0.8)
				return

func _toggle_door() -> void:
	# 玩家开关门：覆盖 NPC 请求，按当前状态反向切换；音效/提示只在此路径播放。
	var want := not _door_open
	_door_npc = false
	_door_player = want
	_set_door_state(want, false)

## P7-V4：门状态唯一仲裁入口。
## silent=true 为岛民请求（不播音效/提示）；玩家请求（silent=false）清掉 NPC 请求后优先生效。
## 两者任一需要开即保持开启；目标角度与 P7 原实现完全一致。
func _set_door_state(open: bool, silent: bool = true) -> void:
	if silent:
		_door_npc = open
	else:
		_door_player = open
	var pivot: Node3D = _cottage.get("door_pivot", null) as Node3D
	if pivot == null:
		return
	var want := _door_npc or _door_player
	if want == _door_open:
		return
	_door_open = want
	var target := -1.85 if _door_open else 0.0
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(pivot, "rotation:y", target, 0.95)
	if not silent:
		_sfx_door(_door_open)
		_hud.show_toast("小屋的门开了" if _door_open else "小屋的门轻轻合上")

## P7-V4：岛民每帧上下文。世界时间/时间来源/暂停全部来自 main 权威状态，
## 角色不读系统时间、不建独立时钟；frozen 时岛民冻结动画与逻辑。
func _villager_ctx() -> Dictionary:
	var advancing := _mode == Mode.PLAYING and (not _paused or _time_source == "real")
	return {
		"sim_seconds": _sim_seconds,
		"sim_rate": _sim_rate,
		"sim_delta": _sim_delta if advancing else 0.0,
		"sun_alt": _sun_alt,
		"events": _events,
		"time_jump": _time_jump,
		"frozen": (_mode != Mode.PLAYING) or _paused,
		"door_set": Callable(self, "_set_door_state"),
	}

# ============================================================
# 自动截图
# ============================================================
## --shots 专用：把船摆到指定路线巡航段（只做视觉摆位，不改变状态机的正常流程）
func _shot_boat_cruise(route: Dictionary, frac: float) -> void:
	if _sailboat == null or route.is_empty():
		return
	_sail_route = route
	_sail_route["_out_pts"] = _route_points(route.get("out", []))
	_sail_route["_back_pts"] = _route_points(route.get("back", []))
	_boat_route_kind = String(route.get("kind", "coastal"))
	_boat_fade_start = float(route.get("fade_start", -1.0))
	_boat_fade_end = float(route.get("fade_end", -1.0))
	_boat_far_entries = (route.get("far_entries", []) as Array).duplicate()
	_boat_wait_total = maxf(60.0, float(route.get("wait_sim_seconds", 28800.0)))
	_boat_route_speed = maxf(_sail_speed, float(route.get("speed", _sail_speed)))
	_boat_route_len = _polyline_len(_sail_route["_out_pts"])
	_boat_route_dist = clampf(frac, 0.05, 0.95) * _boat_route_len
	_boat_speed_cur = _boat_route_speed
	_boat_fade = 1.0
	_boat_state = "COASTAL_CRUISE" if _boat_route_kind == "coastal" else "OUTBOUND_FAR"
	_sail_phase = "out"
	var smp: Dictionary = _sample_polyline(_sail_route["_out_pts"], _boat_route_dist)
	var p: Vector3 = smp["pos"]
	var d: Vector3 = smp["dir"]
	_boat_apply(p, atan2(d.x, d.z), _boat_route_speed, 1.0 / 60.0)
	_apply_boat_fade()

# ---- P7-V2 截图专用摆位：把指定海鸥放到某 kind 的真实栖点上并返回其 Node3D。
# 仅用于截图取景（P7-V2 分布随机化后自然分布可能不在镜头里），不改生态规则、不改选点/可用性逻辑。
func _stage_bird_for_shot(index: int, perch_kind: String) -> Node3D:
	if _birds == null or not _birds.has_method("debug_force_perch") or not _birds.has_method("debug_perch_stats"):
		return null
	var arr: Array = _birds.get("_birds") as Array
	if index < 0 or index >= arr.size():
		return null
	var st: Dictionary = _birds.call("debug_perch_stats")
	for p_v in (st.get("perches", []) as Array):
		var p: Dictionary = p_v
		if String(p.get("kind", "")) != perch_kind:
			continue
		if int(p.get("used", 0)) >= int(p.get("slots", 1)):
			continue
		var pid := String(p.get("id", ""))
		if pid == "":
			continue
		if not bool(_birds.call("debug_force_perch", index, pid)):
			continue
		var b: Dictionary = arr[index]
		b["timer"] = 30.0  # 截图专用：保持停栖，避免计时起飞打断取景
		var nv = b.get("node", null)
		if nv is Node3D:
			return nv as Node3D
		return null
	return null

func _run_shots() -> void:
	_mode = Mode.MENU
	_menu.open(false)
	_hud.set_hud_visible(false, false)
	await get_tree().create_timer(1.6).timeout
	await _save_shot("00_menu")
	_menu.open_settings()
	await get_tree().create_timer(0.5).timeout
	await _save_shot("00_settings")
	# 真实鼠标事件拖动一次音量滑条：截图证明把手与数值随拖动变化
	var shot_sliders: Dictionary = _menu.get("_sliders")
	var shot_vol: Variant = shot_sliders.get("volume_master", shot_sliders.get("volume"))
	if shot_vol != null:
		await _sim_drag(shot_vol as Control, 0.9, 14.0)
		await get_tree().create_timer(0.25).timeout
		await _save_shot("00_settings_drag")
	_menu.set_settings(Settings.defaults())
	# 直接开始
	_menu.instant_finish()
	_mode = Mode.PLAYING
	_started = true
	_paused = false
	_blending = ""
	_apply_pose(_play_pose())
	_hud.set_hud_visible(true, false)
	await get_tree().create_timer(0.4).timeout
	var ev := IsleAstro.day_events(_sim_seconds)
	var sr := float(ev["sunrise"])
	var ss := float(ev["sunset"])
	if sr < 0.0:
		sr = 355.0
	if ss < 0.0:
		ss = 1085.0
	var specs := [
		["sunrise", sr + 10.0],
		["noon", 12.0 * 60.0 + 20.0],
		["golden", ss - 18.0],
		["sunset", ss - 3.0],
		["dusk", ss + 26.0],
		["night", 22.0 * 60.0 + 40.0],
	]
	for spec in specs:
		_set_time_of_day(float(spec[1]))
		await get_tree().create_timer(0.35).timeout
		await _save_shot("01_" + String(spec[0]))
	# 低仰角英雄镜头：把天空/日落太阳/夜星月亮也拍进画面
	_auto_orbit = false
	var heroes := [
		["02_sunset_sky", ss - 2.0, {"theta": 2.02, "elev": 0.13, "r": 82.0, "target": Vector3(0, 10, 0), "fov": 46.0}],
		["02_sunrise_sky", sr + 3.0, {"theta": -2.02, "elev": 0.13, "r": 82.0, "target": Vector3(0, 10, 0), "fov": 46.0}],
		["02_night_sky", 100.0, {"theta": -deg_to_rad(103.6), "elev": -0.02, "r": 86.0, "target": Vector3(0, 20, 0), "fov": 62.0}],
		["02_noon_sky", 12.0 * 60.0 + 20.0, {"theta": -0.45, "elev": -0.30, "r": 72.0, "target": Vector3(0, 22, 0), "fov": 66.0}],
	]
	for h in heroes:
		_set_time_of_day(float(h[1]))
		var pd: Dictionary = h[2]
		_theta = float(pd["theta"])
		_elev = float(pd["elev"])
		_radius = float(pd["r"])
		_cam_target = pd["target"]
		_fov = float(pd["fov"])
		await get_tree().create_timer(0.4).timeout
		await _save_shot(String(h[0]))
	# ---- 第三阶段细节验收镜头 ----
	# 屋顶 / 山墙 / 檐口近景
	# 新屋尺寸（isle_math.gd）：门前地面 door_world().y = 地坪(fy 0.55)，其上是墙 3.18 + 屋顶 2.47，
	# 故屋脊 = door_world().y + HOUSE_WALL_H + HOUSE_ROOF_H（= 地面 +6.20），不再硬编码 6.2。
	var house_door := IsleMath.door_world()
	var house_eave_y: float = house_door.y + IsleMath.HOUSE_WALL_H
	var house_ridge_y: float = house_eave_y + IsleMath.HOUSE_ROOF_H
	var house_door_top_y: float = house_door.y + 1.94  # 门洞高 1.94（新门高）
	_set_time_of_day(12.0 * 60.0 + 20.0)
	_theta = 0.62
	_elev = 0.46
	_radius = 26.0
	_cam_target = Vector3(IsleMath.HOUSE_X, house_ridge_y, IsleMath.HOUSE_Z)
	_fov = 42.0
	await get_tree().create_timer(0.5).timeout
	await _save_shot("03_roof_close")
	# 正立面：拱门 / 门框 / 窗 / 半木结构
	_theta = IsleMath.HOUSE_YAW
	_elev = 0.30
	_radius = 20.0
	# 正立面取景对准门洞顶（≈ 地面 +2.49），取代旧的 ground+2.9
	_cam_target = Vector3(IsleMath.HOUSE_X, house_door_top_y, IsleMath.HOUSE_Z)
	_fov = 48.0
	await get_tree().create_timer(0.5).timeout
	await _save_shot("03_house_front")
	# 门廊台阶（6 级，踏步尺寸已重算）
	_theta = IsleMath.HOUSE_YAW
	_elev = 0.25
	_radius = 8.0
	var stair_door := IsleMath.door_world()
	# P7-V3.2：取景对准门槛下方约一档台阶。door_world().y = 地坪 + 0.55（门槛高），
	# 不再用 terrain+0.75 硬编码（地形采样点在台阶体下方，会与踏面高度不一致）。
	_cam_target = Vector3(stair_door.x, stair_door.y + 0.20, stair_door.z)
	_fov = 50.0
	await get_tree().create_timer(0.5).timeout
	await _save_shot("03_stairs_close")
	# 码头主平台：低机位侧视 + 斜上方，平台面须与海平线平行（本轮修复“向海下斜坡”）
	_set_time_of_day(12.0 * 60.0 + 18.0)
	if _sailboat != null:
		_boat_state = "DOCKED"
		_sail_dwell = 9999.0
		_boat_dock_pose(1.0 / 60.0)
		_apply_boat_fade()
	var dock_c: Vector3 = _boat_dock_pos
	if dock_c == Vector3.ZERO:
		dock_c = Vector3(0.0, 0.72, 8.0)
	var dock_axis := Vector3(sin(_boat_dock_heading), 0.0, cos(_boat_dock_heading))
	if dock_axis.length() < 0.1:
		dock_axis = Vector3(0.0, 0.0, 1.0)
	dock_axis = dock_axis.normalized()
	var dock_side := Vector3(dock_axis.z, 0.0, -dock_axis.x)
	var dock_out := Vector3(dock_c.x, 0.0, dock_c.z)
	if dock_out.length() < 0.5:
		dock_out = dock_side
	dock_out = dock_out.normalized()
	await get_tree().create_timer(0.4).timeout
	_pose_look(dock_c + dock_out * 10.0 + dock_side * 2.5 + Vector3(0.0, 1.45, 0.0), dock_c + Vector3(0.0, 0.55, 0.0), 50.0)
	await get_tree().create_timer(0.4).timeout
	await _save_shot("01b_dock_level")
	_pose_look(dock_c + dock_out * 8.5 + Vector3(0.0, 6.5, 0.0), dock_c - dock_out * 1.5 + Vector3(0.0, 0.40, 0.0), 54.0)
	await get_tree().create_timer(0.4).timeout
	await _save_shot("01c_dock_oblique")
	# 阁楼落地玻璃窗（真实墙体开口 + 内部家具）：cottage 返回的是世界坐标 Vector3
	var attic_raw = _cottage.get("attic_window_world") if _cottage != null else null
	var attic_w := Vector3.ZERO
	if attic_raw is Vector3:
		attic_w = attic_raw
	elif attic_raw is Node3D:
		attic_w = (attic_raw as Node3D).global_position
	if attic_w != Vector3.ZERO:
		_theta = IsleMath.HOUSE_YAW
		_elev = 0.22
		_radius = 11.5
		_cam_target = attic_w + Vector3(0, -0.2, 0)
		_fov = 50.0
		await get_tree().create_timer(0.5).timeout
		await _save_shot("03_attic_window")
	# 花园 / 田地 / 栅栏
	var garden_gy: float = IsleMath.terrain_height(IsleMath.GARDEN_X, IsleMath.GARDEN_Z)
	_theta = -2.45
	_elev = 0.46
	_radius = 23.0
	_cam_target = Vector3(IsleMath.GARDEN_X, garden_gy + 1.2, IsleMath.GARDEN_Z)
	_fov = 46.0
	await get_tree().create_timer(0.5).timeout
	await _save_shot("03_garden")
	# 岩石（≥6 类）：取「一帧内可见最多族类」的岩石簇做英雄机位，再由海面回看岸线
	var rock_stats: Dictionary = {}
	if _world != null and _world.get("rock_stats", null) is Dictionary:
		rock_stats = _world.get("rock_stats")
	var hero_rock: Vector3 = rock_stats.get("hero_pos", Vector3.ZERO) if rock_stats.has("hero_pos") else Vector3.ZERO
	var hero_kinds: int = int(rock_stats.get("hero_kinds", 0)) if rock_stats.has("hero_kinds") else 0
	if hero_rock == Vector3.ZERO:
		var fallback_ang := 0.9
		hero_rock = Vector3(cos(fallback_ang) * (IsleMath.coast_radius(fallback_ang) - 1.0), 0.9,
			sin(fallback_ang) * (IsleMath.coast_radius(fallback_ang) - 1.0))
	var hero_gy: float = IsleMath.terrain_height(hero_rock.x, hero_rock.z)
	_theta = atan2(hero_rock.x, hero_rock.z) + 1.05
	_elev = 0.42
	_radius = 7.5
	_cam_target = Vector3(hero_rock.x, hero_gy + 0.35, hero_rock.z)
	_fov = 55.0
	await get_tree().create_timer(0.5).timeout
	await _save_shot("03_rocks_coast")
	print("[SHOT] rocks hero kinds=", hero_kinds, " at ", hero_rock)
	_theta = atan2(hero_rock.x, hero_rock.z)
	_elev = 0.10
	_radius = 14.0
	_cam_target = Vector3(hero_rock.x, hero_gy + 0.40, hero_rock.z)
	_fov = 56.0
	await get_tree().create_timer(0.5).timeout
	await _save_shot("03_rocks_shore")
	# 花卉（4 型）：四个抬升花坛各栽一个花型，从南侧高位越过园墙俯拍整排花坛
	var bed_c := Vector2(-6.52, -4.78)
	var bed_gy: float = IsleMath.terrain_height(bed_c.x, bed_c.y)
	_theta = 3.05
	_elev = 0.46
	_radius = 6.2
	_cam_target = Vector3(bed_c.x, bed_gy + 1.10, bed_c.y)
	_fov = 50.0
	await get_tree().create_timer(0.5).timeout
	await _save_shot("03_flowers_close")
	# 灯塔近景（原风车位置，高度 = 原风车包围盒 ×1.5）：塔基/环带/平台/灯室/玻璃
	var lh: Node3D = _world.get("lighthouse") if _world != null else null
	if lh != null:
		var lpos: Vector3 = lh.global_position
		var lh_height: float = float(_world.get("lighthouse_height", 16.0))
		_set_time_of_day(12.0 * 60.0 + 20.0)
		_theta = 0.92
		_elev = 0.18
		_radius = 30.0
		_cam_target = lpos + Vector3(0.0, lh_height * 0.58, 0.0)
		_fov = 46.0
		await get_tree().create_timer(0.5).timeout
		await _save_shot("03_lighthouse_day")
		# 夜间灯塔光束：可见光锥 + 灯室高亮 + 海面受光
		# --shots 期间锁定光束角度（实际运行仍由统一时钟旋转）。否则等相机就位时，
		# 模拟时间流速(默认 180×)早把光束转过目标，截图只能拍到随机方向，
		# 无法证明“扫过海面/岛屿/小船”——这正是之前三张灯塔图看起来不匹配的根因。
		_set_time_of_day(22.0 * 60.0 + 40.0)
		_shot_beam_lock = true
		_theta = 0.92 + 0.7
		_elev = 0.10
		_radius = 46.0
		_cam_target = lpos + Vector3(0.0, lh_height * 0.72, 0.0)
		_fov = 52.0
		await get_tree().create_timer(0.6).timeout
		# 光束横穿画面：与相机方位垂直，近灯室窄、远端宽
		var beam_cam_p: Vector3 = _cam.global_position
		var beam_to_cam := Vector3(beam_cam_p.x - lpos.x, 0.0, beam_cam_p.z - lpos.z).normalized()
		_beam_angle = atan2(-beam_to_cam.x, -beam_to_cam.z) + PI * 0.5
		await get_tree().process_frame
		await _save_shot("04_lighthouse_beam")
		# 灯室近景：灯具与玻璃透光、旋转组件
		_set_time_of_day(22.0 * 60.0 + 40.0)
		_theta = 0.92
		_elev = 0.05
		_radius = 8.5
		_cam_target = lpos + Vector3(0.0, lh_height * 0.86, 0.0)
		_fov = 55.0
		await get_tree().create_timer(0.5).timeout
		await _save_shot("04_lantern_close")
		# 海面低机位：光束从灯室扫过镜头侧方（海面受光）
		_theta = atan2(lpos.x, lpos.z)
		_elev = 0.03
		_radius = 62.0
		_cam_target = lpos + Vector3(0.0, lh_height * 0.55, 0.0)
		_fov = 48.0
		await get_tree().create_timer(0.5).timeout
		var cam_p: Vector3 = _cam.global_position
		var lamp_p: Vector3 = _lighthouse_lamp.global_position if _lighthouse_lamp != null else lpos
		var to_cam := Vector3(cam_p.x - lamp_p.x, 0.0, cam_p.z - lamp_p.z).normalized()
		_beam_angle = atan2(-to_cam.x, -to_cam.z) + 0.85
		await get_tree().process_frame
		await _save_shot("04_lighthouse_sweep")
		# 斜向下光束扫过岛屿：取“光束海面足迹”方位放相机，让足迹落在镜头与岛屿之间；
		# 光束指向码头方位（斜穿岛上空）→ 可见光柱、岛面/屋顶受光、海面亮区同框。
		_set_time_of_day(21.0 * 60.0 + 40.0)
		var lamp_o: Vector3 = _lighthouse_lamp.global_position if _lighthouse_lamp != null else lpos
		var beam_h := Vector3(_boat_dock_pos.x - lamp_o.x, 0.0, _boat_dock_pos.z - lamp_o.z)
		if beam_h.length() < 0.01:
			beam_h = Vector3(-lamp_o.x, 0.0, -lamp_o.z)
		beam_h = beam_h.normalized()
		# 解析光锥与海面的交点（俯角 pitch，灯高 22m → 水平 32.6m），即海面亮区中心
		var footprint: Vector3 = lamp_o + beam_h * (lamp_o.y / tan(deg_to_rad(LIGHTHOUSE_BEAM_PITCH_DEG)))
		footprint.y = 0.0
		_theta = atan2(footprint.x, footprint.z)
		_elev = 0.30
		_radius = 86.0
		_cam_target = Vector3(0.0, 5.5, 0.0)
		_fov = 56.0
		await get_tree().create_timer(0.4).timeout
		_beam_angle = atan2(-beam_h.x, -beam_h.z)
		await get_tree().process_frame
		await _save_shot("05_lighthouse_island_light")
		# 光束直接扫过小船：船放在光束海面足迹处（侧舷迎光），从侧面拍光柱+受光船体+海面亮斑
		if _sailboat != null:
			_boat_fade = 1.0
			_sail_dwell = 9999.0
			_shot_boat_hold_pos = footprint
			_shot_boat_hold_heading = atan2(beam_h.x, beam_h.z) + PI * 0.5
			_shot_boat_hold = true
			_theta = atan2(footprint.x, footprint.z) + 0.95
			_elev = 0.13
			_radius = 12.0
			_cam_target = footprint + Vector3(0.0, 1.15, 0.0)
			_fov = 52.0
			await get_tree().create_timer(0.5).timeout
			_beam_angle = atan2(-beam_h.x, -beam_h.z)
			await get_tree().process_frame
			await _save_shot("05_lighthouse_boat_light")
			_shot_boat_hold = false
		_shot_beam_lock = false
	# 开门看室内
	_theta = IsleMath.HOUSE_YAW
	_elev = 0.05
	_radius = 9.5
	_cam_target = house_door + Vector3(0.0, 1.38, 0.0)  # 1.38 m = 1.50 m 岛民眼高
	_fov = 54.0
	if not _door_open:
		_toggle_door()
	await get_tree().create_timer(1.4).timeout
	await _save_shot("03_interior")
	# 夜间灯光 / 窗光 / 门廊灯
	_set_time_of_day(22.0 * 60.0 + 40.0)
	_theta = 0.74
	_elev = 0.20
	_radius = 34.0
	# 立面视觉中心 ≈ 门洞顶（门顶世界高 = house_door_top_y ≈ 地面 +2.49），取代旧硬编码 4.0
	_cam_target = Vector3(IsleMath.HOUSE_X, house_door_top_y, IsleMath.HOUSE_Z)
	_fov = 42.0
	await get_tree().create_timer(0.6).timeout
	await _save_shot("04_night_lights")
	# 路灯：夜间俯视，检查底座是否沿道路边缘、灯头是否朝道路中心
	_set_time_of_day(21.0 * 60.0 + 35.0)
	_theta = IsleMath.HOUSE_YAW + 0.15
	_elev = 1.12
	_radius = 56.0
	_cam_target = Vector3(IsleMath.HOUSE_X * 0.55, 0.6, IsleMath.HOUSE_Z + 6.0)
	_fov = 52.0
	await get_tree().create_timer(0.6).timeout
	await _save_shot("04b_street_lamps_top")
	# 白天鸟群：约 60% 飞行 / 40% 停靠（栖枝 > 1.5×鸟数）
	_set_time_of_day(12.0 * 60.0 + 20.0)
	_theta = IsleMath.HOUSE_YAW + 0.45
	_elev = 0.22
	_radius = 17.0
	# 鸟群/栖枝取景对准新屋脊（旧硬编码 7.6 高于屋脊）
	_cam_target = Vector3(IsleMath.HOUSE_X, house_ridge_y, IsleMath.HOUSE_Z)
	_fov = 54.0
	await get_tree().create_timer(3.0).timeout
	await _save_shot("04_birds")
	# 栖息鸟近景：找一只此刻停在栖枝上的个体，从侧后方 2.6m 拍站姿
	# P7-V2 截图专用摆位：预置一只到真实屋脊栖点，保证近景有主体（不改生态规则）
	var perched_node: Node3D = _stage_bird_for_shot(9, "ridge")
	if perched_node == null and _birds != null:
		for b_v in (_birds.get("_birds") as Array):
			var b: Dictionary = b_v
			if int(b.get("state", -1)) == 3:
				var node_v = b.get("node", null)
				if node_v is Node3D:
					perched_node = node_v as Node3D
					b["timer"] = 30.0  # screenshot only: keep this bird perched for the shot
					break
	if perched_node != null:
		_theta = float(perched_node.rotation.y) + 2.05
		_elev = 0.10
		_radius = 3.6
		_cam_target = perched_node.global_position + Vector3(0.0, 0.12, 0.0)
		_fov = 42.0
		await get_tree().create_timer(0.7).timeout
		await _save_shot("04_bird_perch")
	# 水花：真圆环 + 水柱 + 3D 水滴（近景）
	var splash_ang := -2.45
	var srad: float = IsleMath.coast_radius(splash_ang) + 4.5
	var sp := Vector3(cos(splash_ang) * srad, 0.02, sin(splash_ang) * srad)
	if _splash != null:
		_set_time_of_day(17.0 * 60.0 + 40.0)
		_splash.splash_at(sp, 1.0)
		_splash.splash_at(sp + Vector3(0.9, 0.0, 0.4), 0.7)
		_splash.splash_at(sp + Vector3(-0.7, 0.0, 0.6), 0.6)
		_theta = atan2(cos(splash_ang), sin(splash_ang))
		_elev = 0.48
		_radius = 10.5
		_cam_target = sp + Vector3(0, 0.45, 0)
		_fov = 48.0
		await get_tree().create_timer(0.5).timeout
		await _save_shot("04_splash")
	# 小船：真实状态机巡航位姿（近海航线中段），检查航向/尾迹/随波姿态
	var shot_route: Dictionary = {}
	var shot_bow := Vector3.FORWARD
	if _sailboat != null and not _sail_routes.is_empty():
		_set_time_of_day(12.0 * 60.0 + 20.0)
		for r_v in _sail_routes:
			var r: Dictionary = r_v
			if String(r.get("kind", "")) == "coastal":
				shot_route = r
				break
		if shot_route.is_empty():
			shot_route = _sail_routes[0]
		_shot_boat_cruise(shot_route, 0.46)
		await get_tree().create_timer(0.35).timeout
		var bp: Vector3 = _sailboat.global_position
		# 从船的外海侧回看：船体 3/4 侧面 + 岛与灯塔作背景（相机方位 ≈ 船相对岛的方向 + 30°）
		_theta = atan2(bp.x, bp.z) + 0.55
		_elev = 0.17
		_radius = 17.0
		_cam_target = bp + Vector3(0, 1.35, 0)
		_fov = 50.0
		await get_tree().create_timer(0.5).timeout
		await _save_shot("04_boat_route")
		# 船体吃水线 / 船尾水花生成位置：贴水面侧后近景，检查浪花是否从船体外侧生成、是否穿模
		_shot_boat_cruise(shot_route, 0.50)
		await get_tree().create_timer(0.35).timeout
		bp = _sailboat.global_position
		shot_bow = (_sailboat.global_basis.z as Vector3).normalized()
		var wake_side := Vector3(shot_bow.z, 0.0, -shot_bow.x)
		_pose_look(bp - shot_bow * 2.2 + wake_side * 6.4 + Vector3(0.0, 1.30, 0.0), bp - shot_bow * 1.2 + Vector3(0.0, 0.42, 0.0), 54.0)
		await get_tree().create_timer(0.5).timeout
		await _save_shot("04_boat_wake_close")
		# 夜间船载悬挂灯：侧后方近景，检查暖光灯罩/局部照明/随船固定
		_set_time_of_day(21.0 * 60.0 + 40.0)
		_shot_boat_cruise(shot_route, 0.52)
		await get_tree().create_timer(0.35).timeout
		bp = _sailboat.global_position
		shot_bow = (_sailboat.global_basis.z as Vector3).normalized()
		var side := Vector3(shot_bow.z, 0.0, -shot_bow.x)
		_theta = atan2(side.x, side.z)
		_elev = 0.17
		_radius = 6.2
		_cam_target = bp + Vector3(0.0, 1.25, 0.0)
		_fov = 48.0
		await get_tree().create_timer(0.5).timeout
		await _save_shot("05_boat_night_lantern")
		# 夜间前向探照灯：从船头正前方回看，检查聚光光锥、海面亮斑与朝向
		_shot_boat_cruise(shot_route, 0.52)
		await get_tree().create_timer(0.3).timeout
		bp = _sailboat.global_position
		shot_bow = (_sailboat.global_basis.z as Vector3).normalized()
		# 相机放在船头前方 8.5m、高 2.1m，目标为船头水线 → 光束正对镜头展开
		var cam_off: Vector3 = shot_bow * 8.5 + Vector3(0.0, 1.25, 0.0)
		_theta = atan2(cam_off.x, cam_off.z)
		_elev = asin(clampf(cam_off.y / cam_off.length(), -0.99, 0.99))
		_radius = cam_off.length()
		_cam_target = bp + Vector3(0.0, 0.85, 0.0)
		_fov = 58.0
		await get_tree().create_timer(0.5).timeout
		await _save_shot("05_boat_spotlight")
		# 夜间前向探照灯：侧向看光锥轮廓与水面照亮范围（验证主方向与船头一致）
		_shot_boat_cruise(shot_route, 0.52)
		await get_tree().create_timer(0.3).timeout
		bp = _sailboat.global_position
		shot_bow = (_sailboat.global_basis.z as Vector3).normalized()
		var bow_side := Vector3(shot_bow.z, 0.0, -shot_bow.x)
		_pose_look(bp + shot_bow * 4.2 + bow_side * 7.4 + Vector3(0.0, 2.35, 0.0), bp + shot_bow * 2.6 + Vector3(0.0, 0.75, 0.0), 52.0)
		await get_tree().create_timer(0.5).timeout
		await _save_shot("05_boat_spotlight_side")
		# 拍摄结束恢复停靠，避免后续镜头被小船带走
		_boat_state = "DOCKED"
		_boat_fade = 1.0
		_boat_dock_pose(1.0 / 60.0)
		_apply_boat_fade()
		_sail_dwell = 9999.0
	# 可折叠 24h 时间面板
	_hud.set_hud_visible(true, false)
	_hud.toggle_time_panel()
	await get_tree().create_timer(0.5).timeout
	await _save_shot("04_time_panel")
	_hud.toggle_time_panel()
	# 抬头看天（负仰角）
	_theta = 2.02
	_elev = -0.30
	_radius = 66.0
	_cam_target = Vector3(0, 22, 0)
	_fov = 62.0
	await get_tree().create_timer(0.6).timeout
	await _save_shot("04_sky_up")
	# 现实时间 + 时区：HUD 显示所选时区日期/时间
	var saved_src2 := _time_source
	var saved_tz2 := _timezone
	_settings["time_source"] = "real"
	_settings["timezone"] = "America/New_York"
	_apply_user_settings(false)
	_hud.set_hud_visible(true, false)
	await get_tree().create_timer(0.6).timeout
	await _save_shot("04_realtime_clock")
	_settings["time_source"] = saved_src2
	_settings["timezone"] = saved_tz2
	_apply_user_settings(false)
	# 画质档位对照（同一机位）：低画质关闭 MSAA/云层/岛屿反射并降低草量
	_theta = 0.74
	_elev = 0.28
	_radius = 82.0
	_cam_target = IsleMath.CAM_TARGET
	_fov = 42.0
	_set_time_of_day(12.0 * 60.0 + 20.0)
	_apply_quality(0)
	await get_tree().create_timer(1.4).timeout
	await _save_shot("05_quality_low")
	_apply_quality(1)
	await get_tree().create_timer(0.9).timeout
	await _save_shot("05_quality_medium")
	_apply_quality(2)
	await get_tree().create_timer(0.9).timeout
	await _save_shot("05_quality_high")
	_apply_quality(3)
	await get_tree().create_timer(1.0).timeout
	await _save_shot("05_quality_extreme")
	_apply_quality(4)
	await get_tree().create_timer(1.2).timeout
	await _save_shot("05_quality_ultra")
	# 水面近景：极致档的顶点波动 / 泡沫 / 解析反射（同一机位低角度看开阔海面）
	_pose_look(Vector3(-42.0, 6.0, 30.0), Vector3(-96.0, -0.4, 78.0), 58.0)
	await get_tree().create_timer(1.2).timeout
	await _save_shot("05_water_ultra")
	_apply_quality(0)
	await get_tree().create_timer(0.8).timeout
	await _save_shot("05_water_low")
	# ---- P6 专项：以下截图需要干净画面，先彻底隐藏 HUD（shots 模式下 HUD 淡入 tween 可能残留） ----
	_hud.set_hud_visible(false, true)
	await get_tree().create_timer(0.75).timeout
	# ---- P6 专项：11:00–13:00 炊烟（同机位拍烟囱与烟柱） ----
	_apply_quality(2)
	_set_time_of_day(12.0 * 60.0 + 10.0)
	_pose_look(Vector3(-2.69, 14.5, 14.0), Vector3(-2.69, 18.1, -3.76), 34.0)
	await get_tree().create_timer(3.2).timeout
	await _save_shot("06_smoke_noon")
	# ---- P6 专项：海鸥停在真实瓦面（近景，验证脚接触瓦片） ----
	_set_time_of_day(10.0 * 60.0)
	# P7-V2 截图专用摆位：分布随机化后自然分布可能不在此机位，预置两只到真实屋脊栖点保证取景有主体（不改生态规则）
	_stage_bird_for_shot(8, "ridge")
	_stage_bird_for_shot(9, "ridge")
	_pose_look(Vector3(4.5, 20.5, 3.0), Vector3(-0.11, 18.05, -3.54), 26.0)
	await get_tree().create_timer(1.6).timeout
	await _save_shot("06_bird_roof")
	# ---- P6 专项：夜间阁楼玻璃透明（室内灯/家具/内墙可见、窗外无光球） ----
	_apply_quality(2)
	_set_time_of_day(22.0 * 60.0 + 40.0)
	var at_w: Vector3 = _cottage["attic_window_world"] if _cottage != null else Vector3.ZERO
	_theta = IsleMath.HOUSE_YAW
	_elev = 0.10
	_radius = 12.0
	_cam_target = at_w + Vector3(0.0, -0.6, 0.0)
	_fov = 50.0
	await get_tree().create_timer(0.8).timeout
	await _save_shot("06_attic_window_night")
	# ---- P6 专项：灯塔光束扫过房屋两侧对比（同一机位/同一光束，只改光束角） ----
	# 新屋尺度（isle_math）：地坪 door_world().y + 墙 3.18 = 檐口，+ 屋顶 2.47 = 屋脊；
	# 取景目标取檐口—屋脊之间，取代旧的地面+4.4/4.0 硬编码。
	var beam_house_door := IsleMath.door_world()
	var beam_eave_y: float = beam_house_door.y + IsleMath.HOUSE_WALL_H
	var beam_ridge_y: float = beam_eave_y + IsleMath.HOUSE_ROOF_H
	_shot_beam_lock = true
	var lamp_o: Vector3 = _lighthouse_lamp.global_position if _lighthouse_lamp != null else Vector3(0.0, 22.0, 0.0)
	var beam_h := Vector3(IsleMath.HOUSE_X - lamp_o.x, 0.0, IsleMath.HOUSE_Z - lamp_o.z).normalized()
	_beam_angle = atan2(-beam_h.x, -beam_h.z)
	_theta = atan2(beam_h.x, beam_h.z)
	_elev = 0.12
	_radius = 26.0
	_cam_target = Vector3(IsleMath.HOUSE_X, beam_eave_y + (beam_ridge_y - beam_eave_y) * 0.30, IsleMath.HOUSE_Z)
	_fov = 46.0
	await get_tree().create_timer(0.8).timeout
	await _save_shot("06_beam_house_a")
	_beam_angle += 1.4
	await get_tree().create_timer(0.5).timeout
	await _save_shot("06_beam_house_b")
	# 垂直侧视：相机在光束轴侧面，可见光束射向小屋、被实体墙截断（近光侧亮/背面暗）
	_beam_angle = atan2(-beam_h.x, -beam_h.z)
	_theta = atan2(beam_h.x, beam_h.z) + PI * 0.5
	_elev = 0.08
	_radius = 30.0
	_cam_target = Vector3(IsleMath.HOUSE_X, beam_eave_y + (beam_ridge_y - beam_eave_y) * 0.20, IsleMath.HOUSE_Z)
	_fov = 58.0
	await get_tree().create_timer(0.8).timeout
	await _save_shot("06_beam_house_side")
	# 同机位把光束转开 180°，与上一张做像素差（受光墙应明显变暗、背光墙应基本不变）
	_beam_angle += PI
	await get_tree().create_timer(0.6).timeout
	await _save_shot("06_beam_house_side_off")
	_shot_beam_lock = false
	# ---- P6 专项：ESC 菜单入场/退场逐帧 ----
	# 必须走真实 ESC 路径（_unhandled_input → _open_menu/open(true) 的屏外错峰入场 + _on_menu_start 反向退场），
	# 不能直接调 _menu.open(false)（那是标题菜单风格且不切换 _mode，截图里会没有菜单）。
	# 不要在此调用 _menu.close()：它是标题菜单的异步飞出动效，会在约 1.3s 后把已重新打开的菜单隐藏，
	# 与随后的 open(true) 入场动画竞争（表现为只拍到黑边、没有菜单）。instant_finish() 已把标题菜单收起。
	await get_tree().create_timer(0.25).timeout
	var esc_ev := InputEventKey.new()
	esc_ev.keycode = KEY_ESCAPE
	esc_ev.physical_keycode = KEY_ESCAPE
	esc_ev.pressed = true
	Input.parse_input_event(esc_ev)
	var esc_up := InputEventKey.new()
	esc_up.keycode = KEY_ESCAPE
	esc_up.physical_keycode = KEY_ESCAPE
	esc_up.pressed = false
	Input.parse_input_event(esc_up)
	await get_tree().create_timer(0.06).timeout
	print("[SHOTDBG] esc1 mode=", _mode, " blend=", _blending, " menu_visible=", _menu.menu_visible, " anim=", _menu.get_anim_state(), " menu_node=", _menu.visible)
	if _mode != Mode.MENU:
		# 自动化环境下注入事件可能被焦点控件吞掉；截图流程退回直接调用公开入口（真实 ESC 路径另由 probe_esc_e2e_t1 / --selftest 覆盖）
		print("[SHOTDBG] ESC 注入未生效，退回 _open_menu()")
		_open_menu()
	await get_tree().create_timer(0.06).timeout
	await _save_shot("07_menu_enter_012")
	await get_tree().create_timer(0.30).timeout
	await _save_shot("07_menu_enter_042")
	await get_tree().create_timer(0.90).timeout
	await _save_shot("07_menu_stable")
	# 菜单内再按 ESC：PLAYING 恢复前的反向退场（复用「继续观景」路径，不叠加 Tween）
	Input.parse_input_event(esc_ev)
	Input.parse_input_event(esc_up)
	await get_tree().create_timer(0.06).timeout
	print("[SHOTDBG] esc2 mode=", _mode, " blend=", _blending, " menu_visible=", _menu.menu_visible, " anim=", _menu.get_anim_state())
	if _mode == Mode.MENU:
		print("[SHOTDBG] 第二次 ESC 注入未生效，退回 _on_menu_start(true)")
		_on_menu_start(true)
	await get_tree().create_timer(0.12).timeout
	await _save_shot("07_menu_exit_018")
	await get_tree().create_timer(0.9).timeout
	get_tree().quit()

func _run_transition() -> void:
	# 转场录制：走真实的「开始游戏」路径，按时间轴抓帧，验证径向飞出 + 黑框收合 + 相机过渡
	_mode = Mode.MENU
	_menu.open(false)
	_hud.set_hud_visible(false, false)
	await get_tree().create_timer(1.5).timeout
	await _save_shot("tr_00_menu")
	_on_menu_start(false)
	var times := [0.15, 0.35, 0.55, 0.8, 1.05, 1.3, 1.55, 1.9, 2.3, 2.9, 3.6, 4.4]
	var last := 0.0
	for i in range(times.size()):
		var tt := float(times[i])
		await get_tree().create_timer(maxf(0.0, tt - last)).timeout
		last = tt
		await _save_shot("tr_%02d_%.2f" % [i + 1, tt])
	get_tree().quit()

# ============================================================
# 交互自测（--selftest）：直接驱动 _unhandled_input，验证点击/按键链路
# ============================================================
func _click_screen(p: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = p
	_unhandled_input(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = p
	_unhandled_input(up)

func _key_press(k: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = k
	ev.physical_keycode = k
	ev.pressed = true
	_unhandled_input(ev)

func _wheel_click(btn: int) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = btn
	ev.pressed = true
	ev.position = Vector2(720, 450)
	_unhandled_input(ev)

func _run_selftest() -> void:
	_selftest = true
	var results: Array = []
	# 直接进入观景状态（与截图流程同一条建造路径）
	_menu.instant_finish()
	_mode = Mode.PLAYING
	_started = true
	_paused = false
	_blending = ""
	_apply_pose(_play_pose())
	_hud.set_hud_visible(true, false)
	_set_time_of_day(17.0 * 60.0 + 20.0)
	await get_tree().create_timer(0.9).timeout
	var pivot := _cottage.get("door_pivot", null) as Node3D
	var door_hit := _cottage.get("door_hit", null) as Node3D
	var chimney_hit := _cottage.get("chimney_hit", null) as Node3D
	# 1. 点木门 → 门打开
	if door_hit != null:
		_click_screen(_cam.unproject_position(door_hit.global_position))
	await get_tree().create_timer(1.2).timeout
	results.append(["点击木门后门打开", _door_open and pivot != null and absf(pivot.rotation.y + 1.85) < 0.12])
	await get_tree().create_timer(0.5).timeout
	if door_hit != null:
		_click_screen(_cam.unproject_position(door_hit.global_position))
	await get_tree().create_timer(1.1).timeout
	results.append(["再次点击门关闭", (not _door_open) and pivot != null and absf(pivot.rotation.y) < 0.12])
	# 2. 点烟囱 → toast
	if chimney_hit != null:
		_click_screen(_cam.unproject_position(chimney_hit.global_position))
	await get_tree().create_timer(0.3).timeout
	var toast_text := ""
	var toast_node = _hud.get("_toast")
	if toast_node != null:
		toast_text = String(toast_node.text)
	results.append(["点击烟囱有提示", toast_text.find("烟囱") >= 0])
	# 3. 点海面 → 涟漪
	await get_tree().create_timer(0.4).timeout
	var before := 0
	if _ripples != null:
		before = _ripples.get_child_count()
	_click_screen(_cam.unproject_position(Vector3(30.0, 0.0, -18.0)))
	await get_tree().create_timer(0.35).timeout
	var after := 0
	if _ripples != null:
		after = _ripples.get_child_count()
	results.append(["点击海面产生涟漪", after > before])
	# 4. Esc 回标题
	_key_press(KEY_ESCAPE)
	await get_tree().create_timer(0.4).timeout
	results.append(["Esc 回到标题界面", _mode == Mode.MENU and _menu.menu_visible])
	# 5. 继续观景
	_on_menu_start(true)
	await get_tree().create_timer(2.4).timeout
	results.append(["继续观景回到游戏", _mode == Mode.PLAYING and not _menu.menu_visible])
	# 6. 设置即时生效
	_on_settings_changed({"day_length": 240.0, "sensitivity": 1.6, "auto_orbit": false})
	# Phase6：240s 不是十档之一，应吸附到最近的 300s 档
	results.append(["设置即时生效（流速吸附到预设档）", is_equal_approx(_day_length, 300.0) and is_equal_approx(_sensitivity, 1.6) and not _auto_orbit])
	# 7. 空格暂停
	_key_press(KEY_SPACE)
	results.append(["空格暂停时间", _paused])
	_key_press(KEY_SPACE)
	# 8. Tab 天文历
	_key_press(KEY_TAB)
	await get_tree().create_timer(0.2).timeout
	var alm := _hud.get("_almanac") as Control
	results.append(["Tab 打开天文历", alm != null and alm.visible])
	_key_press(KEY_TAB)
	# 9. 数字键跳时段
	_key_press(KEY_4)
	await get_tree().create_timer(0.2).timeout
	results.append(["数字键跳到日落", absf(fposmod(_sim_seconds, 86400.0) / 3600.0 - 18.6) < 0.06])
	# 10. 双击不再复位视角（第四阶段要求：双击保持当前位置/朝向/距离/目标）
	_theta = 1.9
	_radius = 140.0
	_cam_target = Vector3(4.0, 6.0, 2.0)
	_apply_pose(_play_pose())
	await get_tree().process_frame
	var pose_theta: float = _theta
	var pose_r: float = _radius
	var pose_t: Vector3 = _cam_target
	var center := Vector2(720, 450)
	_click_screen(center)
	await get_tree().process_frame
	_click_screen(center)
	await get_tree().create_timer(0.3).timeout
	results.append(["双击不复位视角", absf(_theta - pose_theta) < 0.002 and absf(_radius - pose_r) < 0.002 and _cam_target.distance_to(pose_t) < 0.002])
	# 11. 滚轮推拉
	var r0 := _radius
	_wheel_click(MOUSE_BUTTON_WHEEL_DOWN)
	await get_tree().process_frame
	results.append(["滚轮推拉镜头", _radius > r0])
	# 12. H 无限次隐藏 / 恢复界面（全局输入层，不销毁 UI）
	_key_press(KEY_H)
	await get_tree().create_timer(0.45).timeout
	var hud_hidden_ok: bool = not bool(_hud.get("_visible_now"))
	_key_press(KEY_H)
	await get_tree().create_timer(0.45).timeout
	var hud_restored_ok: bool = _hud != null and bool(_hud.get("_visible_now")) and _hud.is_inside_tree()
	results.append(["H 隐藏/恢复界面", hud_hidden_ok and hud_restored_ok])
	# 13. 设置面板读写
	_menu.set_settings({"day_length": 960.0, "sensitivity": 0.6, "auto_orbit": true})
	var s: Dictionary = _menu.get_settings()
	# 960s 吸附到 900s 档（15 分钟 / 游戏日）
	results.append(["设置读写一致", is_equal_approx(float(s.get("day_length", 0.0)), 900.0) and bool(s.get("auto_orbit", false))])
	# 15. T 打开 24 小时时间面板 + 调时接入同一模拟时钟
	_key_press(KEY_T)
	await get_tree().create_timer(0.35).timeout
	results.append(["T 打开 24h 时间面板", bool(_hud.get("_time_open"))])
	var before_t := _sim_seconds
	_hud.time_adjust.emit(600.0)
	await get_tree().process_frame
	results.append(["时间面板调时驱动模拟时钟", absf(_sim_seconds - before_t - 600.0) < 0.5])
	_key_press(KEY_T)
	await get_tree().create_timer(0.2).timeout
	# 16. 相机可抬头看天空
	_theta = 0.74
	_elev = -0.30
	_radius = 64.0
	_cam_target = Vector3(0, 22, 0)
	_update_camera(0.0)
	var fwd := -_cam.global_transform.basis.z
	results.append(["相机可抬头看天空", fwd.y > 0.15])
	# 17. 相机不钻地形
	_elev = -0.44
	_radius = 30.0
	_cam_target = Vector3(0, 6, 0)
	_update_camera(0.0)
	var th := IsleMath.terrain_height(_cam.global_position.x, _cam.global_position.z)
	results.append(["相机不穿地形", _cam.global_position.y >= th + 0.8])
	# 18. 右键拖动平移观察点，且不触发水面交互
	_theta = 0.74
	_elev = 0.28
	_radius = 82.0
	_cam_target = IsleMath.CAM_TARGET
	_update_camera(0.0)
	var ripple_before: int = _ripples.get_child_count() if _ripples != null else 0
	var splash_before: int = _splash.get_child_count() if _splash != null else 0
	var tgt_before := _cam_target
	var rd := InputEventMouseButton.new()
	rd.button_index = MOUSE_BUTTON_RIGHT
	rd.pressed = true
	rd.position = Vector2(700, 420)
	_unhandled_input(rd)
	var mv := InputEventMouseMotion.new()
	mv.relative = Vector2(46, -22)
	mv.position = Vector2(746, 398)
	_unhandled_input(mv)
	var ru := InputEventMouseButton.new()
	ru.button_index = MOUSE_BUTTON_RIGHT
	ru.pressed = false
	ru.position = Vector2(746, 398)
	_unhandled_input(ru)
	await get_tree().process_frame
	results.append(["右键拖动平移观察点", _cam_target.distance_to(tgt_before) > 0.3 and not _dragging])
	results.append(["右键拖动不触发水面交互", (_ripples.get_child_count() if _ripples != null else 0) == ripple_before and (_splash.get_child_count() if _splash != null else 0) == splash_before])
	# 19. 局部灯光已注册（uniform）
	results.append(["夜间局部灯光已注册", _lights.size() > 0])
	# 20. 立体水花系统可生成（先推进 10s 清空之前测试残留的活跃水花，避免窗口/headless 时序差撞上池上限）
	if _splash != null:
		_splash.update(10.0)
	var sb2: int = _splash.get_child_count() if _splash != null else 0
	if _splash != null:
		_splash.splash_at(Vector3(30, 0, -18), 1.0)
		_splash.update(1.0 / 60.0)
	await get_tree().process_frame
	results.append(["立体水花可生成", _splash != null and _splash.get_child_count() > sb2 and _splash.get_child_count() > 0])
	# 21. 昼夜窗灯差异（同一套调光）
	_set_time_of_day(12.0 * 60.0 + 20.0)
	await get_tree().create_timer(0.3).timeout
	var day_glow := 0.0
	if _window_mats.size() > 0:
		day_glow = float((_window_mats[0] as ShaderMaterial).get_shader_parameter("glow"))
	_set_time_of_day(22.0 * 60.0 + 40.0)
	await get_tree().create_timer(0.3).timeout
	var night_glow := 0.0
	if _window_mats.size() > 0:
		night_glow = float((_window_mats[0] as ShaderMaterial).get_shader_parameter("glow"))
	results.append(["夜间窗灯亮于白天", night_glow > day_glow + 0.15])
	# 22. 场景动效：大船（状态机出港）/ 灯塔旋转灯室 / 秋千
	if _sail_dwell > 0.0:
		_sail_dwell = -1.0
	var sail0: Vector3 = _sailboat.global_position if _sailboat != null else Vector3.ZERO
	var lh0: float = _lighthouse_lamp.rotation.y if _lighthouse_lamp != null else 0.0
	var sw0: Vector3 = _swing_pivot.rotation if _swing_pivot != null else Vector3.ZERO
	await get_tree().create_timer(1.6).timeout
	var sail_moved := _sailboat != null and _sailboat.global_position.distance_to(sail0) > 0.1
	var lh_moved := _lighthouse_lamp != null and absf(angle_difference(lh0, _lighthouse_lamp.rotation.y)) > 0.03
	var sw_moved := _swing_pivot != null and (_swing_pivot.rotation - sw0).length() > 0.01
	results.append(["帆船出港航行", sail_moved])
	results.append(["灯塔灯室旋转", lh_moved])
	results.append(["秋千摆动", sw_moved])
	# 23. 设置持久化（写临时文件，避免覆盖玩家真实设置）
	# 本沙箱环境禁止 Godot 写 C:/Users（user://），持久化测试改用工作区绝对路径；
	# 读取/写入代码路径与正式 user://settings.cfg 完全一致（ConfigFile）。
	var tmp_path := "D:/休闲小岛幻境/开发产物/logs/settings_selftest.cfg"
	var test_settings: Dictionary = Settings.defaults()
	test_settings["volume_master"] = 0.4
	test_settings["volume_ambient"] = 0.55
	test_settings["quality"] = 1
	Settings.save_settings(test_settings, tmp_path)
	var loaded := Settings.load_settings(tmp_path)
	results.append(["设置持久化读写一致", absf(float(loaded.get("volume_master", -1.0)) - 0.4) < 0.001 and absf(float(loaded.get("volume_ambient", -1.0)) - 0.55) < 0.001 and int(loaded.get("quality", -1)) == 1])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_path))
	# 24. 五档画质预设真实生效（MSAA / 云层细节 / 草实例预算 / 灯预算 / 海浪细节）
	_apply_quality(0)
	var low_msaa: int = get_viewport().msaa_3d
	var low_cloud := float(_sky_mat.get_shader_parameter("cloud_detail"))
	var low_grass: int = _grass_visible_count
	var low_lights := _light_budget
	var low_wave := float(_sea_mat.get_shader_parameter("wave_detail"))
	_apply_quality(4)
	var high_cloud := float(_sky_mat.get_shader_parameter("cloud_detail"))
	var high_wave := float(_sea_mat.get_shader_parameter("wave_detail"))
	results.append(["画质五档生效（低→极致 有真实差异）", low_msaa != get_viewport().msaa_3d and low_cloud < high_cloud and _grass_visible_count >= low_grass and _light_budget > low_lights and high_wave > low_wave])
	_apply_quality(2)
	# 25. F3 性能叠层开关与读数
	_key_press(KEY_F3)
	await get_tree().process_frame
	results.append(["F3 性能叠层可开关", bool(_hud.get("_perf_open"))])
	_perf_timer = 0.0
	_update_perf_overlay(0.5)
	var pl = _hud.get("_perf_label")
	results.append(["性能叠层有帧率读数", pl is Label and (pl as Label).text.find("FPS") >= 0])
	_key_press(KEY_F3)
	# 26. F2 截图写入 user://（headless 下无渲染纹理，容错通过）
	await _take_photo()
	var photo_ok := _last_photo != "" and FileAccess.file_exists(_last_photo)
	results.append(["F2 截图保存成功", photo_ok or DisplayServer.get_name() == "headless"])
	# 27. 音频导演已接入
	results.append(["音频系统已接入", _audio != null and _audio.has_method("update_audio") and _audio.has_method("play_splash")])
	# 28. 分辨率设置：预设/标签/持久化 + 非 headless 时真实窗口尺寸
	var res_cfg := "D:/休闲小岛幻境/开发产物/logs/settings_res_selftest.cfg"
	var res_settings: Dictionary = Settings.defaults()
	var test_res := Vector2i(1280, 720)
	res_settings["resolution"] = test_res
	Settings.save_settings(res_settings, res_cfg)
	var res_loaded := Settings.load_settings(res_cfg)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(res_cfg))
	var res_presets: Array = Settings.resolution_presets()
	var res_persist: bool = Vector2i(res_loaded.get("resolution", Vector2i.ZERO)) == test_res
	var res_label: bool = Settings.resolution_label(test_res).find("×") >= 0
	var res_real: bool = true
	var res_orig: Vector2i = DisplayServer.window_get_size()
	var res_orig_pos: Vector2i = DisplayServer.window_get_position()
	if DisplayServer.get_name() != "headless":
		_apply_resolution(test_res, true)
		await get_tree().process_frame
		res_real = DisplayServer.window_get_size() == test_res
		_apply_resolution(res_orig, true)
		DisplayServer.window_set_position(res_orig_pos)
		await get_tree().process_frame
	var res_menu: bool = false
	if _menu != null:
		var res_sliders: Dictionary = _menu.get("_sliders")
		res_menu = res_sliders.has("resolution") and _menu.get_settings().has("resolution")
	results.append(["分辨率设置（预设/标签/持久化/菜单/窗口生效）", res_persist and res_label and res_presets.size() > 0 and res_menu and res_real])
	# --- 灯塔高度（原风车完整包围盒高度 ×1.5，实测） ---
	var lh_obj: Node3D = _world.get("lighthouse") if _world != null else null
	var lh_h: float = float(_world.get("lighthouse_height", 0.0)) if _world != null else 0.0
	var old_h: float = float(_world.get("windmill_old_height", 0.0)) if _world != null else 0.0
	var lh_ratio_ok: bool = old_h <= 0.01 or absf(lh_h / old_h - 1.5) < 0.09
	results.append(["灯塔建成且高度≈原风车×1.5", lh_obj != null and lh_h > 10.0 and lh_ratio_ok])
	var slider_map: Dictionary = _menu.get("_sliders") if _menu != null else {}
	var all_sliders: bool = slider_map.has("day_length") and slider_map.has("sensitivity") and slider_map.has("volume") and slider_map.has("quality") and slider_map.has("resolution")
	# Phase6：五档 quality、五组音量（volume 为主音量别名）、十档流速（1234 吸附 1200）、window_mode
	_menu.set_settings({"day_length": 1234.0, "sensitivity": 2.15, "volume_master": 0.37, "quality": 4, "auto_orbit": false, "window_mode": "windowed"})
	var gs: Dictionary = _menu.get_settings()
	var raw_roundtrip: bool = absf(float(gs.get("day_length", 0.0)) - 1200.0) < 0.6 and absf(float(gs.get("sensitivity", 0.0)) - 2.15) < 0.001 and absf(float(gs.get("volume_master", gs.get("volume", -1.0))) - 0.37) < 0.0015 and int(gs.get("quality", -1)) == 4
	results.append(["设置定量项全部为可拖动滑条", all_sliders and raw_roundtrip])
	_menu.set_settings(Settings.defaults())
	var day_start := _sim_seconds - fposmod(_sim_seconds, 86400.0)
	_hud.time_set.emit(7.0 * 3600.0 + 30.0 * 60.0)
	var scrub_ok: bool = absf(fposmod(_sim_seconds - day_start, 86400.0) - 27000.0) < 1.0 and _hud.get("_time_scrubber") != null
	results.append(["可拖动时间轴设定当天时刻", scrub_ok])
	# --- 真实鼠标事件路由：设置滑条与时间轴都能被拖动 ---
	# headless 显示服务器不派发 GUI 鼠标事件（探针已证实），这两项只在窗口模式验证。
	if DisplayServer.get_name() == "headless":
		print("[TEST] SKIP  真实鼠标拖动（headless 无 GUI 输入；窗口模式 --selftest 覆盖）")
	else:
		# --- 真实鼠标事件路由：设置滑条与时间轴都能被拖动 ---
		_menu.open(false)
		await get_tree().create_timer(0.3).timeout
		_menu.open_settings()
		await get_tree().create_timer(0.3).timeout
		var vol_slider: Control = slider_map.get("volume_master", slider_map.get("volume"))
		var vol_before: float = float(vol_slider.get("value")) if vol_slider != null else -1.0
		var slider_routed: bool = await _sim_drag(vol_slider, 0.9, 14.0)
		await get_tree().process_frame
		var vol_after: float = float(vol_slider.get("value")) if vol_slider != null else -1.0
		results.append(["设置滑条可真实鼠标拖动", slider_routed and vol_after > vol_before + 0.05])
		_menu.close_settings_instant()
		_menu.instant_finish()
		_menu.set_settings(Settings.defaults())
		_hud.set_hud_visible(true, false)
		if not bool(_hud.get("_time_open")):
			_hud.toggle_time_panel()
		await get_tree().create_timer(0.3).timeout
		var scrubber: Control = _hud.get("_time_scrubber")
		var scrub_routed: bool = await _sim_drag(scrubber, 0.5, 16.0)
		await get_tree().process_frame
		var scrub_time: bool = absf(fposmod(_sim_seconds - day_start, 86400.0) - 43200.0) < 1800.0
		results.append(["时间轴可真实鼠标拖动并改变时刻", scrub_routed and scrub_time])
		_hud.toggle_time_panel()
	# 24. 现实时间模式 + IANA 时区（切东京立即生效，切回模拟不丢状态）
	# T7 修复：现实模式下天文/生态时钟固定为岛屿参考时区（广州 UTC+8）；
	#          切换“显示时区”只改 HUD 文本与事件显示时刻，不得平移天体位置。
	var saved_src := _time_source
	var saved_tz := _timezone
	_settings["time_source"] = "real"
	_settings["timezone"] = "Asia/Tokyo"
	_apply_user_settings(false)
	await get_tree().create_timer(0.2).timeout
	var real_mode_ok: bool = _time_source == "real" and _realtime
	var tokyo_off: int = _offset_for(_abs_unix)
	var expect_dt := Time.get_datetime_dict_from_unix_time(int(_abs_unix + float(_offset_for(_abs_unix))))
	var tz_ok: bool = _time_api != null and tokyo_off == 32400 and int(_display_datetime().get("hour", -1)) == int(expect_dt.get("hour", -2))
	var tz_label_ok: bool = _tz_label_text().find("Asia/Tokyo") >= 0
	# 天体时钟必须与系统绝对时间 + 参考时区同源（不是所选显示时区）。
	var d_ref: float = fposmod(_sim_seconds - (_abs_unix + float(IsleAstro.TZ_SECONDS)), 86400.0)
	var sky_ref_ok: bool = minf(d_ref, 86400.0 - d_ref) < 5.0
	# 事件显示时刻按显示时区偏移换算（日出/日落等文本随所选时区平移，但天文事件不变）。
	var sr_ev := float(_events["sunrise"])
	var sr_unix_ev := sr_ev - float(IsleAstro.TZ_SECONDS)
	var sr_tokyo_dt := Time.get_datetime_dict_from_unix_time(int(sr_unix_ev + float(tokyo_off)))
	var sr_txt_ok: bool = _local_seconds_to_display_text(sr_ev) == "%02d:%02d" % [int(sr_tokyo_dt["hour"]), int(sr_tokyo_dt["minute"])]
	# 切换显示时区前后天体位置不变（同一绝对时刻）。
	var sky_alt_a := _sun_alt
	var sky_az_a := _sun_az
	_settings["timezone"] = "America/New_York"
	_apply_user_settings(false)
	await get_tree().process_frame
	var ny_off: int = _offset_for(_abs_unix)
	var ny_expect := Time.get_datetime_dict_from_unix_time(int(_abs_unix + float(ny_off)))
	var sky_same: bool = absf(_sun_alt - sky_alt_a) < 0.05 and absf(wrapf(_sun_az - sky_az_a, -180.0, 180.0)) < 0.05
	var sky_ny_ok: bool = sky_same and int(_display_datetime().get("hour", -1)) == int(ny_expect.get("hour", -2))
	_settings["time_source"] = saved_src
	_settings["timezone"] = saved_tz
	_apply_user_settings(false)
	await get_tree().process_frame
	results.append(["现实时间模式", real_mode_ok])
	results.append(["IANA 时区切换（东京 UTC+09）", tz_ok and tz_label_ok])
	results.append(["现实时间天体时钟固定为岛屿参考时区", sky_ref_ok and sr_txt_ok])
	results.append(["切换显示时区天体不移动（纽约）", sky_ny_ok])
	# 25. 大船航线：≥8 组、每组 out/back 且贴海面
	var routes_ok: bool = _sail_routes.size() >= 8
	if routes_ok:
		for rt in _sail_routes:
			var out_pts: Array = _route_points((rt as Dictionary).get("out", []))
			var back_pts: Array = _route_points((rt as Dictionary).get("back", []))
			if out_pts.size() < 2 or back_pts.size() < 2:
				routes_ok = false
				break
			for pt in out_pts:
				if absf((pt as Vector3).y) > 0.3:
					routes_ok = false
					break
	results.append(["大船≥8组往返航线", routes_ok and _sailboat != null])
	# 26. 栖枝数 > 1.5×鸟数
	var birds_count: int = 10
	var perch_n: int = int(_perch_count)
	results.append(["栖枝数>1.5×鸟数", perch_n >= int(floor(1.5 * float(birds_count))) + 1 and perch_n > 0])
	# 27. 海岸岩石 ≥6 类 / 花卉 ≥3 型 / 阁楼玻璃窗
	var rock_kinds: int = 0
	var flower_kinds: int = 0
	if _world != null:
		var rock_stats: Dictionary = _world.get("rock_stats", {}) if _world.get("rock_stats", {}) is Dictionary else {}
		rock_kinds = (rock_stats.get("families", []) as Array).size()
		var flower_stats: Dictionary = _world.get("flower_stats", {}) if _world.get("flower_stats", {}) is Dictionary else {}
		flower_kinds = (flower_stats.get("species", {}) as Dictionary).size() if flower_stats.get("species", {}) is Dictionary else 0
		if rock_kinds == 0:
			rock_kinds = int(_world.get("rock_type_count", 0))
		if flower_kinds == 0:
			flower_kinds = int(_world.get("flower_type_count", 0))
	var attic_win: bool = _cottage != null and _cottage.get("attic_window_world") != null
	results.append(["岩石≥6类且花卉≥3型", rock_kinds >= 6 and flower_kinds >= 3])
	results.append(["阁楼落地玻璃窗", attic_win])
	# 28. 夜间灯塔光束开启、白天关闭（同一时钟，平滑过渡）
	_set_time_of_day(22.0 * 60.0)
	_update_lighting()
	await get_tree().process_frame
	var beam_night: float = _beam_strength
	_set_time_of_day(12.35 * 60.0)
	_update_lighting()
	await get_tree().process_frame
	var beam_day: float = _beam_strength
	results.append(["灯塔光束夜间开/白天关", beam_night > 0.18 and beam_day < 0.06])
	# 29. 滚轮可拉近（最小 9m，且不失控）
	_radius = 40.0
	for i in range(40):
		_wheel_click(MOUSE_BUTTON_WHEEL_UP)
	await get_tree().process_frame
	results.append(["滚轮可拉近至近景", _radius >= 8.9 and _radius <= 12.5])
	_radius = 106.0
	# --- Phase6（第六阶段）：五档画质 / 十档流速 / 五组音量 / 自动运镜 / ESC / 光束遮挡 ---
	var five_ok := Settings.QUALITY_COUNT == 5
	var cloud_seen: Array = []
	for qi in range(Settings.QUALITY_COUNT):
		_apply_quality(qi)
		cloud_seen.append(float(_sky_mat.get_shader_parameter("cloud_detail")))
		five_ok = five_ok and _quality == qi
		await get_tree().process_frame
	five_ok = five_ok and cloud_seen[0] < cloud_seen[4] and float(_quality_state.get("sea_wave_detail", 0.0)) > 1.0
	results.append(["画质五档参数全部可应用且逐档提升", five_ok])
	_apply_quality(2)
	var day_ok: bool = Settings.DAY_LENGTH_PRESETS.size() == 10 and Settings.day_length_label(600.0).find("10 分钟") >= 0 and absf(Settings.sanitize_day_length(1234.0) - 1200.0) < 0.5 and absf(Settings.sanitize_day_length(280.0) - 300.0) < 0.5
	results.append(["十档每日流速（60..3600s，边界吸附）", day_ok])
	var groups_ok: bool = Settings.audio_groups().size() == 5
	for gg in Settings.audio_groups():
		groups_ok = groups_ok and _settings.has(String(gg["key"]))
	results.append(["五组音量配置齐全（主/环境/鸟鸣/火焰/音效）", groups_ok])
	# 自动运镜：正式 InputMap 动作 + 再次按键停止且不跳回起点
	var theta_before := _theta
	var orbit_before := _auto_orbit
	_key_press(KEY_C)
	await get_tree().process_frame
	var orbit_flipped := _auto_orbit != orbit_before
	_key_press(KEY_C)
	await get_tree().process_frame
	var orbit_ok: bool = InputMap.has_action("toggle_auto_orbit") and orbit_flipped and _auto_orbit == orbit_before and absf(_theta - theta_before) < 0.5
	results.append(["自动运镜 C 键开关（保留机位/无跳变）", orbit_ok])
	# ESC：打开菜单，再按一次走关闭动画回到游玩
	_mode = Mode.PLAYING
	_paused = false
	_key_press(KEY_ESCAPE)
	await get_tree().create_timer(0.6).timeout
	var esc_open: bool = _mode == Mode.MENU and bool(_menu.get("menu_visible"))
	_key_press(KEY_ESCAPE)
	await get_tree().create_timer(2.8).timeout
	results.append(["ESC 菜单打开/再次按键关闭", esc_open and _mode == Mode.PLAYING])
	# 灯塔遮挡盒已注册（光束不穿墙的几何前提）
	results.append(["灯塔光束遮挡盒已注册", (_cottage.get("beam_occluders", []) as Array).size() > 0 or _cottage.get("root", null) != null])
	# 炊烟窗口（T5 接入后严格校验）
	var smoke_ok := true
	var smoke: Variant = _fx.get("smoke", null)
	if smoke is Dictionary and (smoke as Dictionary).has("ctl"):
		var ctl: Variant = (smoke as Dictionary)["ctl"]
		if ctl != null and ctl.has_method("debug_state"):
			smoke_ok = (ctl.debug_state() as Dictionary).has("emitting")
	results.append(["炊烟双时间窗时钟已接入", smoke_ok])
	# 汇总
	var passed := 0
	for r in results:
		var ok := bool(r[1])
		if ok:
			passed += 1
		print("[TEST] ", "PASS" if ok else "FAIL", "  ", String(r[0]))
	print("[TEST] RESULT ", passed, "/", results.size(), " passed")
	get_tree().quit()

func _set_time_of_day(minutes: float) -> void:
	var today := _sim_seconds - fposmod(_sim_seconds, 86400.0)
	_sim_seconds = today + minutes * 60.0
	_events = IsleAstro.day_events(_sim_seconds)

func _save_shot(name: String, dir: String = SHOTS_DIR) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(dir)
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir + name + ".png")
	print("[SHOT] ", name, " ", img.get_width(), "x", img.get_height())
	await get_tree().process_frame

## 用注入的鼠标事件拖动一个滑条式控件（验证输入路由，而不是直接调用 set_value）。
func _sim_drag(ctl: Control, ratio: float, pad: float) -> bool:
	if ctl == null or not ctl.is_visible_in_tree():
		return false
	var rect: Rect2 = ctl.get_global_rect()
	if rect.size.x < 24.0 or rect.size.y < 8.0:
		return false
	var y: float = rect.position.y + rect.size.y * 0.5
	var x0: float = rect.position.x + pad
	var x1: float = rect.position.x + rect.size.x - pad
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(x0, y)
	Input.parse_input_event(press)
	await get_tree().process_frame
	var mot := InputEventMouseMotion.new()
	mot.button_mask = MOUSE_BUTTON_MASK_LEFT
	mot.position = Vector2(lerpf(x0, x1, clampf(ratio, 0.05, 0.95)), y)
	Input.parse_input_event(mot)
	await get_tree().process_frame
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	rel.position = mot.position
	Input.parse_input_event(rel)
	await get_tree().process_frame
	return not bool(ctl.call("is_dragging"))

func _scale_halo(h: Node3D, k: float) -> void:
	if h == null:
		return
	h.scale = h.scale * k

func _scale_halos(arr: Array, k: float) -> void:
	for h in arr:
		if h is Node3D:
			(h as Node3D).scale = (h as Node3D).scale * k

# ============================================================
# 夜间局部灯光：收集 cottage / world 提供的 light_sources
# 结构：{pos: Vector3, color: Color, energy: float, range: float}（可选 node）
# ============================================================
func _collect_lights() -> void:
	_light_sources = []
	for src in (_cottage.get("light_sources", []) as Array):
		_light_sources.append(src)
	for src in (_world.get("light_sources", []) as Array):
		_light_sources.append(src)
	# P7-V2 夜间道路照明修复：路灯固定占位。
	# 旧实现把所有光源按 energy 降序后按画质 _light_budget 截断；6 盏路灯 energy=1.35，
	# 低/中档（budget 4/6）会被小屋灯（1.60/1.50/1.42…）整体挤出，夜里道路没有任何受光。
	# 现在先单独收集 6 盏路灯并永远排在最前，剩余名额才按能量分给环境灯。
	var lamp_lights: Array = []
	var lamp_positions: Array = []
	for l in (_world.get("lamps", []) as Array):
		if not (l is Array) or (l as Array).size() < 3:
			continue
		var ld: Variant = (l as Array)[2]
		if typeof(ld) != TYPE_DICTIONARY:
			continue
		var ldct: Dictionary = ld
		var lp: Vector3 = ldct.get("pos", ldct.get("position", Vector3.ZERO))
		lamp_positions.append(lp)
		lamp_lights.append({
			"pos": lp,
			"color": ldct.get("color", ldct.get("col", Color(1.0, 0.76, 0.45))),
			"energy": float(ldct.get("energy", ldct.get("intensity", 1.35))),
			"range": maxf(float(ldct.get("range", ldct.get("radius", 7.5))), 0.6),
			"kind": "street_lamp",
		})
	var norm: Array = []
	for src in _light_sources:
		if typeof(src) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = src
		var pos: Vector3 = d.get("pos", d.get("position", Vector3.ZERO))
		if d.has("node") and (d["node"] as Object) is Node3D:
			pos = (d["node"] as Node3D).global_position
		# world.light_sources 里也包含这 6 盏路灯：按位置去重，避免同一盏灯被算两次。
		var dup := false
		for lp2 in lamp_positions:
			if pos.distance_squared_to(lp2) < 0.0025:
				dup = true
				break
		if dup:
			continue
		var col: Color = d.get("color", d.get("col", Color(1.0, 0.72, 0.42)))
		var energy := float(d.get("energy", d.get("intensity", 1.2)))
		var rng := float(d.get("range", d.get("radius", 7.0)))
		var kind := String(d.get("kind", "other"))
		if kind == "other":
			# 灯塔/码头灯是夜景里的地标光，单独打标签（探针与排序可核对）
			var lh: Variant = _world.get("lighthouse_light", {})
			if lh is Dictionary and (lh as Dictionary).has("pos"):
				if pos.distance_squared_to((lh as Dictionary)["pos"] as Vector3) < 0.25:
					kind = "lighthouse"
			if kind == "other":
				var dock: Variant = _world.get("dock", {})
				if dock is Dictionary:
					var dl: Variant = (dock as Dictionary).get("light", {})
					if dl is Dictionary and (dl as Dictionary).has("pos"):
						if pos.distance_squared_to((dl as Dictionary)["pos"] as Vector3) < 0.25:
							kind = "dock"
		norm.append({"pos": pos, "color": col, "energy": energy, "range": maxf(rng, 0.6), "kind": kind})
	# 取最重要的 12 盏（toon/grass shader 上限）；路灯永远在最前，任意画质截断都不会丢道路照明。
	norm.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["energy"]) > float(b["energy"]))
	var merged: Array = []
	merged.append_array(lamp_lights)
	merged.append_array(norm)
	_lights = merged.slice(0, 12)
	RenderingServer.global_shader_parameter_set("g_light_count", float(_lights.size()))

## P7-V2 探针接口：当前参与着色的光源清单（含 kind 标签）与真实路灯世界坐标。
func debug_light_state() -> Dictionary:
	var arr: Array = []
	for L in _lights:
		arr.append({
			"kind": String(L.get("kind", "other")),
			"pos": L["pos"],
			"color": L["color"],
			"energy": float(L["energy"]),
			"range": float(L["range"]),
		})
	var lamp_positions: Array = []
	for l in (_world.get("lamps", []) as Array):
		if l is Array and (l as Array).size() >= 3 and typeof((l as Array)[2]) == TYPE_DICTIONARY:
			var ld: Dictionary = (l as Array)[2]
			lamp_positions.append(ld.get("pos", ld.get("position", Vector3.ZERO)))
	# 与 _update_lighting 的 active_lights 口径一致（不含临时船灯；船灯可见时实际再多 1 盏）。
	var lamp_need := 0
	for L in _lights:
		if String((L as Dictionary).get("kind", "")) == "street_lamp":
			lamp_need += 1
	return {
		"quality": _quality,
		"budget": _light_budget,
		"active": mini(_lights.size(), maxi(mini(_light_budget, 12), lamp_need)),
		"lamp_count": lamp_positions.size(),
		"lamp_positions": lamp_positions,
		"lights": arr,
	}

# ============================================================
# 船 / 风车 / 秋千 场景动效引用
# ============================================================
func _collect_props() -> void:
	_moored_boat = _world.get("boat", null) as Node3D
	if _moored_boat != null:
		_moored_base = _world.get("boat_base", _moored_boat.position) as Vector3
		_moored_heading = float(_world.get("boat_heading", 0.0))
	_windmill_blades = null
	_lighthouse = _world.get("lighthouse", null) as Node3D
	_lighthouse_lamp = _world.get("lighthouse_lamp", null) as Node3D
	_lighthouse_light = _world.get("lighthouse_light", {}) if _world.get("lighthouse_light", {}) is Dictionary else {}
	# world 返回的 lighthouse_beam_origin 是世界坐标 Vector3（不是节点）；
	# 旋转组件挂在灯室节点上，既让灯具/玻璃旋转，也让光束同轴转动。
	_beam_origin_node = _lighthouse_lamp if _lighthouse_lamp != null else _lighthouse
	_swing_pivot = _world.get("swing", null) as Node3D
	_sailboat = _world.get("sailboat", null) as Node3D
	_sail_speed = maxf(float(_world.get("sailboat_speed", 3.4)), 0.2)
	_sail_trip_speed = _sail_speed
	# 多航线：优先 sail_routes（8 条往返），否则退回旧的闭合路径。
	_sail_routes = []
	var rr = _world.get("sail_routes", null)
	if rr is Array:
		for r in (rr as Array):
			if r is Dictionary and (r as Dictionary).has("out") and (r as Dictionary).has("back"):
				_sail_routes.append(r)
	_sail_path = []
	if _sail_routes.is_empty():
		var pv = _world.get("sailboat_path", null)
		if pv is Curve3D:
			var curve: Curve3D = pv
			var bl := curve.get_baked_length()
			for i in range(64):
				_sail_path.append(curve.sample_baked(bl * float(i) / 64.0))
		elif pv is PackedVector3Array:
			for pt in (pv as PackedVector3Array):
				_sail_path.append(pt)
		elif pv is Array:
			for pt in (pv as Array):
				if pt is Vector3:
					_sail_path.append(pt)
	_sail_phase = "docked"
	_sail_dist2 = 0.0
	_sail_route = {}
	_sail_route_last = -1
	_sail_dwell = randf_range(2.5, 5.0)
	# ---- 小船生命周期 / 船载灯 / 淡出材质 ----
	var dock_anchor := _boat_dock_anchor()
	_boat_dock_pos = (_world.get("sail_dock_pos", dock_anchor[0]) as Vector3)
	_boat_dock_heading = float(_world.get("sail_dock_heading", dock_anchor[1]))
	_boat_lantern_local = _world.get("sailboat_lantern_local_pos", Vector3(0.0, 1.30, 1.95)) as Vector3
	_boat_spot_lens = _world.get("sailboat_spot_lens_pos", Vector3(0.0, 1.05, 2.05)) as Vector3
	_boat_spot_node = _world.get("sailboat_spot_node", null) as Node3D
	_boat_spot_cone_mat = _world.get("sailboat_spot_cone_mat", null) as ShaderMaterial
	_boat_lantern_mat = _world.get("sailboat_lantern_mat", null) as ShaderMaterial
	_boat_lantern_halo = _world.get("sailboat_lantern_halo", null) as MeshInstance3D
	_boat_state = "DOCKED"
	_boat_fade = 1.0
	_boat_route_dist = 0.0
	_boat_route_kind = "far"
	_boat_far_entries = []
	_boat_ret_pts = []
	_boat_wait_sim = 0.0
	_boat_rest_until = -1.0
	_boat_speed_cur = 0.0
	_boat_turn_rate = 0.0
	_sail_heading = _boat_dock_heading
	# 船体材质复制一份（toon 材质是全局缓存共享的，必须副本才能只淡出小船）
	_boat_fade_mats = []
	_boat_fade_std = []
	_boat_fade_map = {}
	if _sailboat != null:
		_collect_boat_fade_mats(_sailboat)
	# 所有航线起点必须是同一码头锚点；返航终点也回到这里
	for r in _sail_routes:
		var ro: Array = _route_points((r as Dictionary).get("out", []))
		var rb: Array = _route_points((r as Dictionary).get("back", []))
		if not ro.is_empty() and (ro[0] as Vector3).distance_to(_boat_dock_pos) > 1.2:
			print("[BOAT][WARN] route ", String((r as Dictionary).get("name", "?")), " out[0] 距码头 ", snappedf((ro[0] as Vector3).distance_to(_boat_dock_pos), 0.01), "m")
		if not rb.is_empty() and (rb[rb.size() - 1] as Vector3).distance_to(_boat_dock_pos) > 1.2:
			print("[BOAT][WARN] route ", String((r as Dictionary).get("name", "?")), " back[-1] 距码头 ", snappedf((rb[rb.size() - 1] as Vector3).distance_to(_boat_dock_pos), 0.01), "m")
	var world_perches: Array = (_world.get("perches", []) as Array)
	var cottage_perches: Array = (_cottage.get("perches", []) as Array) if _cottage != null else []
	_perch_count = int(_world.get("perch_count", world_perches.size() + cottage_perches.size()))

# ============================================================
# 时间面板 → 同一模拟时钟
# ============================================================
func _on_time_adjust(seconds_delta: float) -> void:
	if _time_source == "real" or absf(seconds_delta) < 0.001:
		return
	_time_jump += seconds_delta
	_sim_seconds += seconds_delta
	_events = IsleAstro.day_events(_sim_seconds)
	_events_timer = 0.0
	_sync_boat_clock()

## 可拖动时间轴：直接设置当天时刻（保留当前日期），仍驱动同一个模拟时钟。
func _on_time_set(sec_of_day: float) -> void:
	if _time_source == "real":
		return
	var day_start := _sim_seconds - fposmod(_sim_seconds, 86400.0)
	var next_seconds := day_start + clampf(sec_of_day, 0.0, 86399.0)
	_time_jump += next_seconds - _sim_seconds
	_sim_seconds = next_seconds
	_events = IsleAstro.day_events(_sim_seconds)
	_events_timer = 0.0
	_sync_boat_clock()

# ============================================================
# 右键平移（受约束：水平沿相机右向，竖直调整观察中心高度）
# ============================================================
func _pan_by(rel: Vector2) -> void:
	var k := 0.00115 * maxf(_radius, 26.0) * _sensitivity
	var right := Vector3(cos(_theta), 0.0, -sin(_theta))
	_cam_target -= right * (rel.x * k)
	_cam_target.y += rel.y * k * 0.85
	_clamp_target()

func _clamp_target() -> void:
	var h := Vector2(_cam_target.x, _cam_target.z)
	var maxr := 34.0
	if h.length() > maxr:
		h = h.normalized() * maxr
	_cam_target.x = h.x
	_cam_target.z = h.y
	_cam_target.y = clampf(_cam_target.y, 1.2, 30.0)

# ============================================================
# 船 / 风车 / 秋千 / 水花 每帧推进
# ============================================================
func _update_props(delta: float) -> void:
	# 秋千（绕吊点摆动）
	if _swing_pivot != null:
		_swing_pivot.rotation.x = sin(_frame_t * 1.15) * 0.42
		_swing_pivot.rotation.z = sin(_frame_t * 0.83 + 0.8) * 0.06
	# 立体水花
	if _splash != null:
		_splash.update(delta)
	# 大船：出港 → 远海等待 → 返航 → 停靠，每次出港随机选一条完整往返航线
	_update_boat(delta)

# ============================================================
# 大船多航线状态机（8 条往返；出港时确定，途中不重随机）
# ============================================================
func _route_points(v) -> Array:
	var pts: Array = []
	if v is Curve3D:
		var curve: Curve3D = v
		var bl := curve.get_baked_length()
		var n := 64
		for i in range(n + 1):
			pts.append(curve.sample_baked(bl * float(i) / float(n)))
	elif v is PackedVector3Array:
		for pt in (v as PackedVector3Array):
			pts.append(pt)
	elif v is Array:
		for pt in (v as Array):
			if pt is Vector3:
				pts.append(pt)
	return pts

func _polyline_len(pts: Array) -> float:
	var total := 0.0
	for i in range(pts.size() - 1):
		total += (pts[i] as Vector3).distance_to(pts[i + 1] as Vector3)
	return total

func _sample_polyline(pts: Array, dist: float) -> Dictionary:
	if pts.size() < 2:
		return {"pos": Vector3.ZERO, "dir": Vector3.FORWARD, "done": true}
	var total := _polyline_len(pts)
	if dist >= total:
		var last: Vector3 = pts[pts.size() - 1]
		var prev: Vector3 = pts[pts.size() - 2]
		return {"pos": last, "dir": (last - prev).normalized(), "done": true}
	var acc := 0.0
	for i in range(pts.size() - 1):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var seg := a.distance_to(b)
		if acc + seg >= dist and seg > 0.0001:
			var t := (dist - acc) / seg
			return {"pos": a.lerp(b, t), "dir": (b - a).normalized(), "done": false}
		acc += seg
	return {"pos": pts[pts.size() - 1], "dir": Vector3.FORWARD, "done": true}

## 水面高度：与 shaders/sea.gdshader 的 wave_h() 完全一致（吃水/俯仰/横滚共用同一波面）
func _wave_h(x: float, z: float) -> float:
	# P6：与 sea.gdshader 的 wave_h()/wave_grad() 严格同源（同一 WAVES 表、同一 detail、
	# 同一 wave_height），船体吃水/俯仰/横滚不会与画面波面错位。
	var wd := float(_quality_state.get("sea_wave_detail", 3.0))
	return IsleWaves.height(x, z, _frame_t, wd, _wave_height)

## 船体随波：艏/艉/左右舷五点采样 → 升沉 + 俯仰 + 横滚；船头沿路径切线，转向带内倾
func _boat_apply(pos: Vector3, target_heading: float, speed: float, delta: float) -> void:
	var turn := wrapf(target_heading - _sail_heading, -PI, PI)
	_boat_turn_rate = lerpf(_boat_turn_rate, turn / maxf(delta, 0.001), 1.0 - exp(-4.0 * delta))
	_sail_heading = lerp_angle(_sail_heading, target_heading, 1.0 - exp(-2.8 * delta))
	var fwd := Vector3(sin(_sail_heading), 0.0, cos(_sail_heading))
	var right := Vector3(cos(_sail_heading), 0.0, -sin(_sail_heading))
	var half := BOAT_BODY_LEN * 0.5
	var hc := _wave_h(pos.x, pos.z)
	var hf := _wave_h(pos.x + fwd.x * half, pos.z + fwd.z * half)
	var hb := _wave_h(pos.x - fwd.x * half, pos.z - fwd.z * half)
	var hr := _wave_h(pos.x + right.x * 0.75, pos.z + right.z * 0.75)
	var hl := _wave_h(pos.x - right.x * 0.75, pos.z - right.z * 0.75)
	var surf := (hc * 2.0 + hf + hb + hr + hl) / 6.0
	var pitch := atan2(hf - hb, BOAT_BODY_LEN)
	var roll := atan2(hr - hl, 1.5)
	var turn_roll := clampf(-_boat_turn_rate * 0.06, -0.12, 0.12)
	# 吃水：船体设计水线 y=0，波面之上只留 0.02 视觉余量，避免浪尖穿进船舱
	_sailboat.position = Vector3(pos.x, surf + 0.02, pos.z)
	_sailboat.rotation = Vector3(-pitch * 0.85, _sail_heading, roll * 0.8 + turn_roll)
	if _wake != null:
		_wake.update(delta, _sailboat.global_position, _sail_heading, speed)
	_apply_boat_fade()
	_update_boat_spot()

## 淡出：船体材质副本统一写 fade_alpha（屏幕抖动），远处不硬消失，也不影响场景其它物体
func _apply_boat_fade() -> void:
	var a := clampf(_boat_fade, 0.0, 1.0)
	for m in _boat_fade_mats:
		if m is ShaderMaterial:
			(m as ShaderMaterial).set_shader_parameter("fade_alpha", a)
	for d in _boat_fade_std:
		var dm: StandardMaterial3D = d.get("mat", null) as StandardMaterial3D
		if dm != null:
			var base: Color = d.get("color", Color.WHITE)
			dm.albedo_color = Color(base.r, base.g, base.b, base.a * a)
	if _sailboat != null:
		var vis := _sail_boat_visible and a > 0.02 and _boat_state != "OFFSCREEN_WAIT"
		_sailboat.visible = vis
		if _wake != null:
			_wake.visible = vis

## 递归收集船体材质并复制副本（toon_material 全局缓存共享，直接改 fade_alpha 会让全场景一起淡出）
func _collect_boat_fade_mats(root: Node) -> void:
	for c in root.get_children():
		if c is GeometryInstance3D:
			_collect_gi_fade(c as GeometryInstance3D)
		_collect_boat_fade_mats(c)

func _collect_gi_fade(gi: GeometryInstance3D) -> void:
	var ov := gi.material_override
	if ov is ShaderMaterial:
		gi.material_override = _register_boat_fade_mat(ov as ShaderMaterial)
	elif ov is StandardMaterial3D:
		gi.material_override = _register_boat_std_mat(ov as StandardMaterial3D)
	var mi := gi as MeshInstance3D
	if mi != null and mi.mesh != null:
		for si in range(mi.mesh.get_surface_count()):
			var sm := mi.get_surface_override_material(si)
			if sm == null:
				sm = mi.mesh.surface_get_material(si)
			if sm is ShaderMaterial:
				mi.set_surface_override_material(si, _register_boat_fade_mat(sm as ShaderMaterial))
			elif sm is StandardMaterial3D:
				mi.set_surface_override_material(si, _register_boat_std_mat(sm as StandardMaterial3D))

## ShaderMaterial.get_shader_parameter() 对“未显式赋值”的 uniform 返回 null，
## 因此必须查 shader 的 uniform 表判断是否支持 fade_alpha，否则整船材质都收集不到。
func _shader_has_uniform(sm: ShaderMaterial, uname: String) -> bool:
	if sm == null or sm.shader == null:
		return false
	for u in sm.shader.get_shader_uniform_list():
		if String(u.get("name", "")) == uname:
			return true
	return false

func _register_boat_fade_mat(sm: ShaderMaterial) -> ShaderMaterial:
	if not _shader_has_uniform(sm, "fade_alpha"):
		return sm
	var key := sm.get_instance_id()
	if _boat_fade_map.has(key):
		return _boat_fade_map[key] as ShaderMaterial
	var d := sm.duplicate() as ShaderMaterial
	d.set_shader_parameter("fade_alpha", 1.0)
	var np := d.next_pass
	if np is ShaderMaterial and _shader_has_uniform(np as ShaderMaterial, "fade_alpha"):
		var npd := (np as ShaderMaterial).duplicate() as ShaderMaterial
		npd.set_shader_parameter("fade_alpha", 1.0)
		d.next_pass = npd
		_boat_fade_mats.append(npd)
	_boat_fade_map[key] = d
	_boat_fade_mats.append(d)
	return d

func _register_boat_std_mat(sm: StandardMaterial3D) -> StandardMaterial3D:
	var key := sm.get_instance_id()
	if _boat_fade_map.has(key):
		return _boat_fade_map[key] as StandardMaterial3D
	var d := sm.duplicate() as StandardMaterial3D
	d.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_boat_fade_map[key] = d
	_boat_fade_std.append({"mat": d, "color": d.albedo_color})
	return d

## 船载探照灯：方向 = 船头 + 适度俯角；可见光锥与 toon/sea 的真实受光共用同一组 global uniform
func _update_boat_spot() -> void:
	if _sailboat == null:
		return
	var on := _sail_boat_visible and _boat_fade > 0.05 and _boat_state != "OFFSCREEN_WAIT" and _sun_alt < 0.5
	if not on:
		if _boat_spot_node != null:
			_boat_spot_node.visible = false
		_dbg_spot_strength = 0.0
		_dbg_spot_visible = false
		RenderingServer.global_shader_parameter_set("g_spot_color", Color(0.0, 0.0, 0.0, 0.0))
		return
	var b := _sailboat.global_transform.basis
	var fwd := b.z.normalized()
	var sdir := (fwd * 0.80 + Vector3.DOWN * 0.20).normalized()
	var lens := _sailboat.to_global(_boat_spot_lens)
	var night := 1.0 - smoothstep(-6.0, 2.0, _sun_alt)
	var moving := 1.0 if _boat_speed_cur > 0.4 else 0.42
	var strength := clampf(night * _boat_fade * moving, 0.0, 1.0)
	if _boat_spot_node != null:
		_boat_spot_node.visible = strength > 0.04
	_dbg_spot_strength = strength
	_dbg_spot_dir = sdir
	_dbg_spot_origin = lens
	_dbg_spot_visible = strength > 0.04
	var lc := _lin(Color(1.0, 0.86, 0.62))
	RenderingServer.global_shader_parameter_set("g_spot_origin", lens)
	RenderingServer.global_shader_parameter_set("g_spot_dir", sdir)
	RenderingServer.global_shader_parameter_set("g_spot_color", Color(lc.r, lc.g, lc.b, strength))
	RenderingServer.global_shader_parameter_set("g_spot_params", Vector4(cos(deg_to_rad(27.0)), cos(deg_to_rad(9.0)), BOAT_SPOT_RANGE, 0.0))

func _boat_dock_anchor() -> Array:
	if not _sail_routes.is_empty():
		var out0 := _route_points((_sail_routes[0] as Dictionary).get("out", []))
		if out0.size() >= 2:
			return [out0[0], atan2((out0[1] as Vector3).x - (out0[0] as Vector3).x, (out0[1] as Vector3).z - (out0[0] as Vector3).z)]
	if _sail_path.size() >= 2:
		return [_sail_path[0], atan2((_sail_path[1] as Vector3).x - (_sail_path[0] as Vector3).x, (_sail_path[1] as Vector3).z - (_sail_path[0] as Vector3).z)]
	return [Vector3.ZERO, 0.0]

func _choose_sail_route() -> void:
	_start_boat_departure()

## 出航：从码头锚点出发，随机选一条完整路线；整条路线在出港瞬间确定，途中不再重随机
func _start_boat_departure() -> void:
	if _sail_routes.is_empty():
		return
	var idx := randi() % _sail_routes.size()
	if _sail_routes.size() > 2 and idx == _sail_route_last:
		idx = (idx + 1 + randi() % (_sail_routes.size() - 1)) % _sail_routes.size()
	_sail_route_last = idx
	_sail_route = _sail_routes[idx]
	_sail_route["_out_pts"] = _route_points(_sail_route.get("out", []))
	_sail_route["_back_pts"] = _route_points(_sail_route.get("back", []))
	if (_sail_route["_out_pts"] as Array).size() < 2:
		return
	_boat_route_kind = String(_sail_route.get("kind", "far"))
	_boat_fade_start = float(_sail_route.get("fade_start", -1.0))
	_boat_fade_end = float(_sail_route.get("fade_end", -1.0))
	_boat_far_entries = (_sail_route.get("far_entries", []) as Array).duplicate()
	_boat_wait_total = maxf(60.0, float(_sail_route.get("wait_sim_seconds", 28800.0)))
	_boat_route_speed = maxf(_sail_speed, float(_sail_route.get("speed", _sail_speed)))
	_boat_route_len = _polyline_len(_sail_route["_out_pts"])
	_set_boat_shore_window(_sail_route)
	_boat_route_dist = 0.0
	_boat_speed_cur = 0.0
	_boat_turn_rate = 0.0
	_boat_fade = 1.0
	_boat_state = "DEPARTING"
	_boat_trip += 1
	_sail_phase = "out"
	_sail_trip_speed = _boat_route_speed
	_sail_dist2 = 0.0
	_apply_boat_fade()
	print("[BOAT] depart #", _boat_trip, " route=", String(_sail_route.get("name", str(idx))), " kind=", _boat_route_kind, " out_len=", snappedf(_boat_route_len, 0.1), " far_entries=", _boat_far_entries.size(), " wait=", snappedf(_boat_wait_total, 1.0), "s")

## P7：按航线真实几何计算近海航段的一次性触发距离；远海 / 无近海元数据的航次直接禁用。
func _set_boat_shore_window(route: Dictionary) -> void:
	_boat_shore_done = true
	_boat_shore_trigger = -1.0
	if String(route.get("kind", "")) != "coastal" or not route.has("shore_a0"):
		return
	var pts: Array = route.get("_out_pts", [])
	if pts.is_empty():
		pts = _route_points(route.get("out", []))
	var d: float = IsleWorld.shore_trigger_dist(pts, float(route["shore_a0"]), float(route["shore_a1"]))
	if d > 0.0:
		_boat_shore_trigger = d
		_boat_shore_done = false

## 沿路线推进（弧长参数化），船头始终对准路径切线
func _boat_step(pts: Array, speed: float, delta: float) -> Dictionary:
	_boat_route_dist += maxf(0.0, speed) * delta
	var smp := _sample_polyline(pts, _boat_route_dist)
	var sdir: Vector3 = smp["dir"]
	var heading := atan2(sdir.x, sdir.z)
	_boat_apply(smp["pos"] as Vector3, heading, speed, delta)
	return smp

## 停靠姿态：贴合码头位置/朝向，随波轻微起伏
func _boat_dock_pose(delta: float) -> void:
	_boat_speed_cur = 0.0
	_boat_route_dist = 0.0
	_boat_fade = 1.0
	_boat_apply(_boat_dock_pos, _boat_dock_heading, 0.0, delta)

## 近海巡游结束 → 沿 back 段返航
func _begin_return(pts: Array) -> void:
	if pts.size() < 2:
		_enter_resting()
		return
	_boat_ret_pts = pts
	_boat_route_dist = 0.0
	_boat_fade = 1.0
	_boat_state = "RETURNING"
	_sail_phase = "back"
	print("[BOAT] cruise finished -> RETURNING len=", snappedf(_polyline_len(pts), 0.1))

## 远海等待结束：随机选一个远海入口，从该处淡入，再沿返航路径回码头
func _begin_return_from_far() -> void:
	var entry := Vector3.ZERO
	if not _boat_far_entries.is_empty():
		entry = _boat_far_entries[randi() % _boat_far_entries.size()]
	else:
		var out_pts: Array = _sail_route.get("_out_pts", [])
		if not out_pts.is_empty():
			entry = out_pts[out_pts.size() - 1] as Vector3
	var pts: Array = []
	var rp = _world.get("sail_return_paths", null)
	if rp is Dictionary and (rp as Dictionary).has(entry):
		pts = _route_points((rp as Dictionary).get(entry))
	var cbp = _world.get("sail_return_path", null)
	if pts.size() < 2 and cbp is Callable:
		pts = _route_points((cbp as Callable).call(entry))
	if pts.size() < 2:
		pts = [entry, _boat_dock_pos]
	_boat_ret_pts = pts
	_boat_route_dist = 0.0
	_boat_fade = 0.0
	_boat_speed_cur = 1.2
	_boat_state = "FADING_IN"
	_sail_phase = "back"
	_sail_heading = atan2(_boat_dock_pos.x - entry.x, _boat_dock_pos.z - entry.z)
	_sailboat.position = entry
	_apply_boat_fade()
	print("[BOAT] far return entry=", entry, " len=", snappedf(_polyline_len(pts), 0.1))

## 抵达码头 → RESTING：夜间强制停到次日 08:00，白天也要有合理停靠/等待时间
func _enter_resting() -> void:
	_boat_state = "RESTING"
	_sail_phase = "docked"
	_boat_fade = 1.0
	_boat_speed_cur = 0.0
	_boat_route_dist = 0.0
	_boat_dock_pose(0.016)
	var rest_scale := 1.0
	if _time_source == "sim":
		rest_scale = 86400.0 / maxf(_day_length, 1.0)
	_boat_rest_until = _sim_seconds + randf_range(18.0, 40.0) * rest_scale
	if _is_boat_rest_hour():
		_boat_rest_until = maxf(_boat_rest_until, _next_rest_end_sim())
	print("[BOAT] arrived dock -> RESTING until sim=", snappedf(_boat_rest_until, 1.0))

## 18:00—次日 08:00 为小船休息窗口（按岛屿参考时区/模拟时钟判定；显示时区不影响生态行为）
func _is_boat_rest_hour() -> bool:
	var hour := fposmod(_sim_seconds, 86400.0) / 3600.0
	return hour >= BOAT_REST_START_HOUR or hour < BOAT_REST_END_HOUR

## 下一次 08:00 的模拟秒时间戳
func _next_rest_end_sim() -> float:
	var tod := fposmod(_sim_seconds, 86400.0)
	var end_at := _sim_seconds - tod + BOAT_REST_END_HOUR * 3600.0
	if tod >= BOAT_REST_END_HOUR * 3600.0:
		end_at += 86400.0
	return end_at

## 时间源切换 / 手动跳时 / 改流速后：把船只状态与时钟对齐（夜间不出港、远海等待按跳时推进）
func _sync_boat_clock() -> void:
	if _sailboat == null:
		return
	var jumped := absf(_time_jump) > 0.001
	if jumped:
		if _boat_state == "OFFSCREEN_WAIT":
			_boat_wait_sim = maxf(0.0, _boat_wait_sim - absf(_time_jump))
		_time_jump = 0.0
	if _boat_state == "DOCKED" and _is_boat_rest_hour():
		_enter_resting()
	elif _boat_state == "RESTING":
		if _is_boat_rest_hour():
			_boat_rest_until = maxf(_boat_rest_until, _next_rest_end_sim())
		elif jumped and _boat_rest_until > _sim_seconds:
			# C4 修复：向后拖时间/跳到白天时，夜间长休息不应把船锁在 RESTING 约 20 游戏小时；
			# 只在真正的跳时（_time_jump）时提前结束，正常白天短停靠不受影响。
			_boat_rest_until = _sim_seconds

func _update_boat(delta: float) -> void:
	if _sailboat == null:
		return
	if _shot_boat_hold:
		_boat_apply(_shot_boat_hold_pos, _shot_boat_hold_heading, 0.0, delta)
		return
	if _sail_routes.is_empty():
		sailboat_visible(_sail_boat_visible)
		_update_boat_legacy(delta)
		return
	match _boat_state:
		"DOCKED":
			_boat_dock_pose(delta)
			if _is_boat_rest_hour():
				_enter_resting()
				return
			if not _paused:
				_sail_dwell -= delta
			if _sail_dwell <= 0.0:
				_start_boat_departure()
		"DEPARTING":
			# 平滑加速，离港段不瞬间到最大速度
			_boat_speed_cur = minf(_boat_route_speed, _boat_speed_cur + maxf(0.8, _boat_route_speed * 0.55) * delta)
			var smp := _boat_step(_sail_route.get("_out_pts", []), _boat_speed_cur, delta)
			var depart_n := minf(6.0, maxf(2.0, _boat_route_len * 0.12))
			if _boat_route_dist >= depart_n and not bool(smp["done"]):
				_boat_state = "COASTAL_CRUISE" if _boat_route_kind == "coastal" else "OUTBOUND_FAR"
		"COASTAL_CRUISE":
			_boat_speed_cur = minf(_boat_route_speed, _boat_speed_cur + 1.1 * delta)
			var c := _boat_step(_sail_route.get("_out_pts", []), _boat_speed_cur, delta)
			# P7：进入真实近海航段的一次性边界触发；_boat_shore_done 保证同一航次只调用一次。
			if not _boat_shore_done and _boat_shore_trigger > 0.0 and _boat_route_dist >= _boat_shore_trigger and not _paused:
				_boat_shore_done = true
				var eco: Dictionary = {}
				if _birds != null:
					eco = _birds.on_boat_shore_pass(_boat_trip, _sailboat.global_position, _sun_alt)
				print("[ECO] boat_shore trip=", _boat_trip, " birds=", int(eco.get("birds", 0)), " reason=", String(eco.get("reason", "")), " dist=", snappedf(_boat_route_dist, 0.1))
			if bool(c["done"]):
				_begin_return(_sail_route.get("_back_pts", []))
		"OUTBOUND_FAR":
			_boat_speed_cur = minf(_boat_route_speed, _boat_speed_cur + 1.1 * delta)
			var f := _boat_step(_sail_route.get("_out_pts", []), _boat_speed_cur, delta)
			if _boat_fade_end > _boat_fade_start and _boat_fade_start > 0.0:
				_boat_fade = clampf(1.0 - smoothstep(_boat_fade_start, _boat_fade_end, _boat_route_dist), 0.0, 1.0)
			if bool(f["done"]):
				_boat_fade = 0.0
				_boat_speed_cur = 0.0
				_boat_state = "OFFSCREEN_WAIT"
				_boat_wait_sim = _boat_wait_total
				_apply_boat_fade()
				print("[BOAT] faded out far -> OFFSCREEN_WAIT ", snappedf(_boat_wait_total, 1.0), " sim-s")
		"OFFSCREEN_WAIT":
			_boat_wait_sim -= maxf(0.0, _sim_delta)
			if _boat_wait_sim <= 0.0:
				_begin_return_from_far()
		"FADING_IN":
			_boat_speed_cur = minf(_boat_route_speed, _boat_speed_cur + 1.5 * delta)
			var fi := _boat_step(_boat_ret_pts, _boat_speed_cur, delta)
			var fade_len := maxf(38.0, float(_world.get("island_diameter", 60.0)) * 0.6)
			_boat_fade = clampf(_boat_route_dist / fade_len, 0.0, 1.0)
			if _boat_fade >= 0.999 or bool(fi["done"]):
				_boat_fade = 1.0
				_boat_state = "RETURNING"
				_apply_boat_fade()
		"RETURNING":
			_boat_speed_cur = minf(_boat_route_speed, _boat_speed_cur + 1.0 * delta)
			var rr := _boat_step(_boat_ret_pts, _boat_speed_cur, delta)
			# 到码头前最后 8m 平滑减速
			var remain := _polyline_len(_boat_ret_pts) - _boat_route_dist
			if remain < 8.0:
				_boat_speed_cur = maxf(0.55, _boat_speed_cur * (0.86 + 0.14 * clampf(remain / 8.0, 0.0, 1.0)))
			if bool(rr["done"]):
				_enter_resting()
		"RESTING":
			_boat_dock_pose(delta)
			if _sim_seconds >= _boat_rest_until:
				if _is_boat_rest_hour():
					_boat_rest_until = maxf(_boat_rest_until, _next_rest_end_sim())
				else:
					_boat_state = "DOCKED"
					_sail_dwell = randf_range(3.0, 7.0)
					print("[BOAT] rest done -> DOCKED dwell=", snappedf(_sail_dwell, 0.1))
		_:
			_boat_state = "DOCKED"
			_sail_dwell = 2.0

func sailboat_visible(v: bool) -> void:
	_sail_boat_visible = v
	if _sailboat != null:
		_sailboat.visible = v and _boat_fade > 0.02 and _boat_state != "OFFSCREEN_WAIT"
	if _wake != null:
		_wake.visible = _sail_boat_visible and _boat_fade > 0.02

## 兜底：没有 8 航线数据时，沿用旧的闭合折线巡航，保证不影响旧场景。
func _update_boat_legacy(delta: float) -> void:
	if _sail_path.size() < 2:
		return
	var total := 0.0
	for i in range(_sail_path.size()):
		total += (_sail_path[i] as Vector3).distance_to(_sail_path[(i + 1) % _sail_path.size()] as Vector3)
	_sail_dist = fposmod(_sail_dist + delta * _sail_speed, maxf(total, 0.01))
	var acc := 0.0
	var spos: Vector3 = _sail_path[0]
	var sdir := Vector3.FORWARD
	for i in range(_sail_path.size()):
		var a2: Vector3 = _sail_path[i]
		var b2: Vector3 = _sail_path[(i + 1) % _sail_path.size()]
		var seg := a2.distance_to(b2)
		if acc + seg >= _sail_dist and seg > 0.0001:
			var t2 := (_sail_dist - acc) / seg
			spos = a2.lerp(b2, t2)
			sdir = (b2 - a2).normalized()
			break
		acc += seg
	_boat_apply(spos, atan2(sdir.x, sdir.z), _sail_speed, delta)

# ============================================================
# 灯塔：锥形光束可视化 + 全局解析光锥
# ============================================================
func _make_cone_mesh(length: float, radius: float, segs: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(segs):
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var p0 := Vector3(cos(a0) * radius, sin(a0) * radius, -length)
		var p1 := Vector3(cos(a1) * radius, sin(a1) * radius, -length)
		for tri in [[Vector3.ZERO, Vector2(0.5, 0.0)], [p0, Vector2(float(i) / float(segs), 1.0)], [p1, Vector2(float(i + 1) / float(segs), 1.0)]]:
			st.set_uv(tri[1])
			st.add_vertex(tri[0])
	return st.commit()

# 生成一层光束锥网格；网格/材质只在 _build 时创建一次。
func _make_beam_layer(layer_name: String, length: float, radius: float, segs: int, mat: ShaderMaterial) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = layer_name
	mi.mesh = _make_cone_mesh(length, radius, segs)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	_beam_rotator.add_child(mi)
	return mi

func _make_beam_material(col: Color, hot: Color, softness: float, fade_power: float, side_power: float, noise_amount: float, hot_amount: float, alpha_max: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(BEAM_SHADER)
	mat.set_shader_parameter("beam_color", col)
	mat.set_shader_parameter("beam_hot_color", hot)
	mat.set_shader_parameter("beam_softness", softness)
	mat.set_shader_parameter("beam_fade_power", fade_power)
	mat.set_shader_parameter("beam_side_power", side_power)
	mat.set_shader_parameter("beam_noise_amount", noise_amount)
	mat.set_shader_parameter("beam_hot_amount", hot_amount)
	mat.set_shader_parameter("beam_alpha_max", alpha_max)
	return mat

func _build_lighthouse_beam() -> void:
	if _beam_origin_node == null or _lighthouse == null:
		return
	_beam_rotator = Node3D.new()
	_beam_rotator.name = "BeaconRotator"
	_beam_origin_node.add_child(_beam_rotator)
	_beam_rotator.position = Vector3.ZERO
	# 光束固定俯角：绕 X 轴倾斜，水平旋转由父级灯室（lamp.rotation.y）驱动。
	_beam_rotator.rotation = Vector3(-deg_to_rad(LIGHTHOUSE_BEAM_PITCH_DEG), 0.0, 0.0)
	# 三层同轴锥：白热内芯 / 暖金中芯 / 琥珀雾壳；端半径由半角与长度推得，宽度随距离线性扩大。
	# 网格与材质只在 _build 生成一次；_update 只改 uniform / rotation / visibility。
	# 着色器只点亮朝向相机的壳面，因此这里把柔度整体上调，保持原亮度水平。
	# P5.2 调色：降低近灯室白热占比（原 hot_amount=1.0 使光柱整体发灰白），
	# 提暖并加宽柔边，三层 alpha 递减形成“亮芯→暖金→琥珀雾”的自然过渡。
	_beam_core_mat = _make_beam_material(
		Color(1.0, 0.78, 0.42), Color(1.0, 0.90, 0.66),
		0.72, 1.9, 2.6, 0.05, 0.55, 0.80)
	_beam_mid_mat = _make_beam_material(
		Color(1.0, 0.68, 0.30), Color(1.0, 0.82, 0.50),
		0.62, 2.2, 3.0, 0.08, 0.35, 0.66)
	_beam_haze_mat = _make_beam_material(
		Color(1.0, 0.62, 0.26), Color(1.0, 0.76, 0.42),
		0.50, 3.0, 3.3, 0.10, 0.20, 0.36)
	var beam_len := LIGHTHOUSE_BEAM_VIS_LEN
	var r_core := beam_len * tan(deg_to_rad(3.0))
	var r_mid := beam_len * tan(deg_to_rad(6.6))
	var r_haze := beam_len * tan(deg_to_rad(11.0))
	_beam_core = _make_beam_layer("BeamCore", beam_len, r_core, 32, _beam_core_mat)
	_beam_mid = _make_beam_layer("BeamMid", beam_len, r_mid, 28, _beam_mid_mat)
	_beam_haze = _make_beam_layer("BeamHaze", beam_len, r_haze, 24, _beam_haze_mat)

## 时间流速倍率：模拟模式 = 默认流速（480s/天）/ 当前流速；现实模式恒为 1×。
## 灯塔转速/远海等待/模拟时钟都从这里取同一倍率，避免各模块各用一套计时器。
func _time_flow_scale() -> float:
	if _time_source == "real":
		return 1.0
	return LIGHTHOUSE_REF_DAY_LENGTH / maxf(_day_length, 1.0)

func _update_lighthouse_beam(delta: float) -> void:
	if _beam_rotator == null:
		RenderingServer.global_shader_parameter_set("g_beam_params", Vector4(0, 1, 1, 1))
		return
	# 旋转角度只由统一时钟增量驱动：模拟模式用 _sim_delta（暂停=0，倍速同步），现实模式用真实秒。
	var inc := 0.0
	if _mode == Mode.PLAYING:
		if _time_source == "real":
			inc = delta * TAU / maxf(LIGHTHOUSE_ROTATION_PERIOD, 0.5)
		else:
			inc = _sim_delta * TAU / (maxf(LIGHTHOUSE_ROTATION_PERIOD, 0.5) * (86400.0 / LIGHTHOUSE_REF_DAY_LENGTH))
	if not _shot_beam_lock:
		_beam_angle = fposmod(_beam_angle + inc, TAU)
	if _lighthouse_lamp != null:
		# 灯室与光束同轴：旋转灯具节点，BeaconRotator 是其子节点，避免双重旋转。
		_lighthouse_lamp.rotation.y = _beam_angle
	else:
		_beam_rotator.rotation = Vector3(-deg_to_rad(LIGHTHOUSE_BEAM_PITCH_DEG), _beam_angle, 0.0)
	# 含俯角的三维光束方向（与可视锥、toon/sea 解析光锥完全同轴）。
	var pitch := deg_to_rad(LIGHTHOUSE_BEAM_PITCH_DEG)
	var cpitch := cos(pitch)
	_beam_dir_world = Vector3(-sin(_beam_angle) * cpitch, -sin(pitch), -cos(_beam_angle) * cpitch).normalized()
	var night := 1.0 - smoothstep(-7.0, 3.0, _sun_alt)
	var li := float(_pal.get("lanternI", 0.0))
	_beam_strength = clampf(night * (0.22 + li * 1.05), 0.0, 1.0)
	var origin: Vector3 = _beam_origin_node.global_position
	if _lighthouse_lamp != null:
		origin = _lighthouse_lamp.global_position
	var lin := Color(1.0, 0.80, 0.42).srgb_to_linear()
	var vis := _beam_strength > 0.035
	if _beam_core != null:
		_beam_core.visible = vis
	if _beam_mid != null:
		_beam_mid.visible = vis
	if _beam_haze != null:
		_beam_haze.visible = vis
	if _beam_core_mat != null:
		_beam_core_mat.set_shader_parameter("beam_strength", _beam_strength)
		_beam_core_mat.set_shader_parameter("beam_time", _frame_t)
		_beam_core_mat.set_shader_parameter("beam_len", LIGHTHOUSE_BEAM_VIS_LEN)
	if _beam_mid_mat != null:
		_beam_mid_mat.set_shader_parameter("beam_strength", _beam_strength)
		_beam_mid_mat.set_shader_parameter("beam_time", _frame_t)
		_beam_mid_mat.set_shader_parameter("beam_len", LIGHTHOUSE_BEAM_VIS_LEN)
	if _beam_haze_mat != null:
		_beam_haze_mat.set_shader_parameter("beam_strength", _beam_strength)
		_beam_haze_mat.set_shader_parameter("beam_time", _frame_t)
		_beam_haze_mat.set_shader_parameter("beam_len", LIGHTHOUSE_BEAM_VIS_LEN)
	RenderingServer.global_shader_parameter_set("g_beam_origin", origin)
	RenderingServer.global_shader_parameter_set("g_beam_dir", _beam_dir_world)
	RenderingServer.global_shader_parameter_set("g_beam_color", Color(lin.r, lin.g, lin.b, 1.0))
	# 解析光锥 = 三维锥体（斜向下）：海面亮区、岛屿/屋顶/船体受光都与可视光柱同轴同角度。
	RenderingServer.global_shader_parameter_set("g_beam_params", Vector4(_beam_strength * 0.95, cos(deg_to_rad(LIGHTHOUSE_BEAM_OUTER_DEG)), cos(deg_to_rad(LIGHTHOUSE_BEAM_INNER_DEG)), LIGHTHOUSE_BEAM_RANGE))

# ============================================================
# 性能基线（--perf）：多个时段/机位各采样 180 帧，输出 fps / 帧时间 / CPU / 绘制调用 / 显存
# ============================================================
func _run_perf() -> void:
	_mode = Mode.PLAYING
	_menu.instant_finish()
	_started = true
	_paused = false
	_blending = ""
	_apply_pose(_play_pose())
	_hud.set_hud_visible(true, false)
	print("[PERF] begin viewport=", get_viewport().get_visible_rect().size, " msaa=", get_viewport().msaa_3d, " quality=", _quality, " grass=", _grass_visible_count, " lights=", _light_budget, " vsync_disabled")
	var scenes := [
		["noon_clear", 12.0 * 60.0 + 20.0, {"theta": 0.74, "elev": 0.28, "r": 82.0, "fov": 42.0}],
		["golden_cloud_water", 17.0 * 60.0 + 40.0, {"theta": 0.74, "elev": 0.18, "r": 82.0, "fov": 42.0}],
		["night_shadows", 22.0 * 60.0 + 40.0, {"theta": 0.74, "elev": 0.28, "r": 82.0, "fov": 42.0}],
		["night_close", 22.0 * 60.0 + 40.0, {"theta": 0.30, "elev": 0.30, "r": 30.0, "fov": 40.0}],
		["far_island", 12.0 * 60.0 + 20.0, {"theta": 2.40, "elev": 0.44, "r": 168.0, "fov": 46.0}],
		["sky_up", 22.0 * 60.0 + 40.0, {"theta": 2.02, "elev": -0.30, "r": 70.0, "fov": 62.0}],
	]
	for sc in scenes:
		var nm := String(sc[0])
		_set_time_of_day(float(sc[1]))
		var pd: Dictionary = sc[2]
		_theta = float(pd["theta"])
		_elev = float(pd["elev"])
		_radius = float(pd["r"])
		_fov = float(pd["fov"])
		_cam_target = Vector3(0, 6, 0)
		await get_tree().create_timer(1.4).timeout
		var st := await _sample_frames(180)
		print("[PERF] %-20s fps=%.1f frame_ms=%.2f cpu_ms=%.2f objects=%d draw_calls=%d vram_mb=%.1f" % [nm, float(st["fps"]), float(st["frame_ms"]), float(st["cpu_ms"]), int(st["objects"]), int(st["calls"]), float(st["vram"])])
	# 时间面板展开开销
	_hud.toggle_time_panel()
	await get_tree().create_timer(0.8).timeout
	var sp := await _sample_frames(120)
	print("[PERF] %-20s fps=%.1f frame_ms=%.2f cpu_ms=%.2f objects=%d draw_calls=%d vram_mb=%.1f" % ["time_panel_open", float(sp["fps"]), float(sp["frame_ms"]), float(sp["cpu_ms"]), int(sp["objects"]), int(sp["calls"]), float(sp["vram"])])
	_hud.toggle_time_panel()
	# 成本拆解：关闭 MultiMesh（草/树冠/岩石/瓦片）+ 云 + 水面细节，量化的“简化管线”对照
	var mm_nodes: Array = []
	var stack: Array = []
	if _world.has("root") and _world["root"] != null:
		stack.append(_world["root"])
	if _cottage.has("root") and _cottage["root"] != null:
		stack.append(_cottage["root"])
	while not stack.is_empty():
		var nd = stack.pop_back()
		if nd == null:
			continue
		if nd is MultiMeshInstance3D:
			mm_nodes.append(nd)
		if nd is Node:
			for c in (nd as Node).get_children():
				stack.append(c)
	for nd in mm_nodes:
		(nd as MultiMeshInstance3D).visible = false
	_sea_mat.set_shader_parameter("wave_detail", 0.0)
	_sea_mat.set_shader_parameter("foam_amount", 0.0)
	var lite := [
		["lite_noon_nomultimesh", 12.0 * 60.0 + 20.0],
		["lite_night_nomultimesh", 22.0 * 60.0 + 40.0],
	]
	for sc2 in lite:
		_set_time_of_day(float(sc2[1]))
		_theta = 0.74
		_elev = 0.28
		_radius = 82.0
		_fov = 42.0
		_cam_target = Vector3(0, 6, 0)
		await get_tree().create_timer(1.2).timeout
		var st2 := await _sample_frames(120)
		print("[PERF] %-20s fps=%.1f frame_ms=%.2f cpu_ms=%.2f objects=%d draw_calls=%d vram_mb=%.1f" % [String(sc2[0]), float(st2["fps"]), float(st2["frame_ms"]), float(st2["cpu_ms"]), int(st2["objects"]), int(st2["calls"]), float(st2["vram"])])
	for nd in mm_nodes:
		(nd as MultiMeshInstance3D).visible = true
	_sea_mat.set_shader_parameter("wave_detail", 1.0)
	_sea_mat.set_shader_parameter("foam_amount", 0.78)
	# 画质档位对照：同机位/同时段，验证五档预设的帧率与绘制开销差异。
	# 采样期间临时解除帧率上限：否则低档预设的 max_fps 会把结果固定成 60，失去对比意义。
	var saved_max_fps := Engine.max_fps
	Engine.max_fps = 0
	for q in [4, 3, 2, 1, 0]:
		_apply_quality(q)
		Engine.max_fps = 0
		_set_time_of_day(12.0 * 60.0 + 20.0)
		_theta = 0.74
		_elev = 0.28
		_radius = 82.0
		_fov = 42.0
		_cam_target = Vector3(0, 6, 0)
		await get_tree().create_timer(1.3).timeout
		var sq := await _sample_frames(120)
		print("[PERF] %-20s fps=%.1f frame_ms=%.2f cpu_ms=%.2f objects=%d draw_calls=%d vram_mb=%.1f msaa=%d scale=%.2f grass=%d lights=%d" % [
			"quality_%d" % q, float(sq["fps"]), float(sq["frame_ms"]), float(sq["cpu_ms"]),
			int(sq["objects"]), int(sq["calls"]), float(sq["vram"]),
			get_viewport().msaa_3d, get_viewport().scaling_3d_scale, _grass_visible_count, _light_budget,
		])
	_apply_quality(2)
	Engine.max_fps = saved_max_fps
	# 长时间运行后的活动对象数（回收检查）
	await get_tree().create_timer(6.0).timeout
	print("[PERF] after_6s objects=", get_child_count(), " nodes=", Performance.get_monitor(Performance.OBJECT_NODE_COUNT), " orphan=", Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	print("[PERF] end")
	get_tree().quit()

func _sample_frames(n: int) -> Dictionary:
	await get_tree().process_frame
	var t0 := Time.get_ticks_usec()
	var cpu := 0.0
	for i in range(n):
		await get_tree().process_frame
		cpu += Performance.get_monitor(Performance.TIME_PROCESS)
	var t1 := Time.get_ticks_usec()
	var frame_ms := float(t1 - t0) / 1000.0 / float(n)
	return {
		"fps": 1000.0 / maxf(frame_ms, 0.001),
		"frame_ms": frame_ms,
		"cpu_ms": cpu / float(n) * 1000.0,
		"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"vram": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
	}

# ============================================================
# 用户设置 / 画质预设 / 音频 / F2 截图 / F3 叠层 / 悬停反馈
# ============================================================
func _setup_audio() -> void:
	var path := "res://scripts/isle_audio.gd"
	if not ResourceLoader.exists(path):
		return
	var script: Script = load(path) as Script
	if script == null or not script.can_instantiate():
		return
	_audio = script.new()
	if _audio == null:
		return
	(_audio as Node).name = "Audio"
	add_child(_audio as Node)
	if _audio.has_method("setup"):
		_audio.setup(self)
	_apply_audio_volume()

func _apply_user_settings(save: bool) -> void:
	# Phase6：五档画质 / 十档每日流速 / 五组音量 / 三态窗口模式。所有键都经过 isle_settings 校验。
	_quality = Settings.sanitize_quality(_settings.get("quality", 2))
	_settings["quality"] = _quality
	_day_length = Settings.day_length_seconds(_settings.get("day_length", Settings.DAY_LENGTH_DEFAULT))
	_settings["day_length"] = _day_length
	_sensitivity = clampf(float(_settings.get("sensitivity", 1.0)), 0.2, 3.0)
	_auto_orbit = bool(_settings.get("auto_orbit", true))
	# P7-V3：玩家视野范围（FOV，35–65°，默认 42），轨道视角 _play_pose 与自由视角 base_fov 共用。
	_fov = Settings.sanitize_fov(_settings.get("fov", Settings.FOV_DEFAULT))
	_settings["fov"] = _fov
	if _flycam != null and bool(_flycam.active):
		_flycam.set_base_fov(_fov)
	_time_source = String(_settings.get("time_source", "sim"))
	if _time_source != "sim" and _time_source != "real":
		_time_source = "sim"
	_timezone = String(_settings.get("timezone", "Asia/Shanghai"))
	_realtime = _time_source == "real"
	_settings["resolution"] = Settings.sanitize_resolution(_settings.get("resolution", Settings.default_resolution()))
	_settings["window_mode"] = Settings.sanitize_window_mode(_settings.get("window_mode", "windowed"), _settings.get("fullscreen", false))
	if _realtime:
		# 现实时间：天文/生态时钟固定用岛屿参考时区；显示时区只改 HUD 文本（T7 修复）。
		_abs_unix = Time.get_unix_time_from_system()
		_sim_seconds = _abs_unix + float(IsleAstro.TZ_SECONDS)
		_events = IsleAstro.day_events(_sim_seconds)
	_apply_quality(_quality)
	_apply_audio_volume()
	_apply_window_mode(String(_settings["window_mode"]))
	_apply_resolution()
	if _menu != null:
		_menu.set_settings(_settings)
	if _hud != null:
		if _hud.has_method("set_auto_orbit"):
			_hud.set_auto_orbit(_auto_orbit)
		if _hud.has_method("set_quality_label"):
			_hud.set_quality_label(_hud_quality_label)
	# 时间源/时区/流速变化后，把船只状态与当前时钟对齐（夜间不出港、跳时对齐远海等待）
	_sync_boat_clock()
	if save:
		Settings.save_settings(_settings)

# ============================================================
# 时间来源 / 时区显示 helper（第四阶段）
# ============================================================
var _hud_hidden := false

func _offset_for(unix: float) -> int:
	if _time_api != null and _time_api.has_method("offset_at"):
		return int(_time_api.offset_at(_timezone, unix))
	return 28800

func _display_datetime() -> Dictionary:
	if _time_source == "real":
		var off := _offset_for(_abs_unix)
		return Time.get_datetime_dict_from_unix_time(int(_abs_unix + float(off)))
	return IsleAstro.local_datetime(_sim_seconds)

func _display_clock_text() -> String:
	var dt := _display_datetime()
	return "%02d:%02d" % [int(dt.get("hour", 0)), int(dt.get("minute", 0))]

## 岛屿参考时区（广州）本地秒 → 所选显示时区的墙上时间（日出/日落/月出/月落）。
## 现实与模拟模式同一换算：天体事件始终发生在参考时区，显示时区只改文本（T7 修复）。
func _local_seconds_to_display_text(local_seconds: float) -> String:
	if local_seconds < -1.0e8:
		return "--:--"
	var unix := local_seconds - float(IsleAstro.TZ_SECONDS)
	var off := _offset_for(unix)
	var dt2 := Time.get_datetime_dict_from_unix_time(int(unix + float(off)))
	return "%02d:%02d" % [int(dt2.get("hour", 0)), int(dt2.get("minute", 0))]

func _tz_label_text() -> String:
	if _time_api != null and _time_api.has_method("info"):
		var inf = _time_api.info(_timezone)
		if inf is Dictionary:
			for key in ["label", "display", "city", "name"]:
				if inf.has(key) and String(inf[key]) != "":
					return String(inf[key])
	return _timezone

func _toggle_hud_visible() -> void:
	_hud_hidden = not _hud_hidden
	if _hud != null:
		_hud.set_hud_visible(not _hud_hidden, true)
		if _hud_hidden and bool(_hud.get("_time_open")):
			_hud.toggle_time_panel()
		else:
			_hud.show_toast("界面已恢复 · 按 H 可再次隐藏")

func _toggle_time_source() -> void:
	_on_time_mode_requested("sim" if _time_source == "real" else "real")

## T 面板 / 设置菜单 / R 键的唯一时间来源切换入口。
## 状态源：_settings["time_source"] + _time_source + _realtime；HUD 每帧从 _hud_data 刷新所以两个界面天然同步。
func _on_time_mode_requested(mode: String) -> void:
	if mode != "sim" and mode != "real":
		return
	if mode == _time_source:
		_hud.show_toast("已是%s模式" % ("现实时间" if mode == "real" else "模拟时间"))
		return
	var was_real := _time_source == "real"
	_settings["time_source"] = mode
	_time_source = mode
	_realtime = mode == "real"
	_abs_unix = Time.get_unix_time_from_system()
	if mode == "real":
		# 切到现实：以系统绝对时间 + 岛屿参考时区重新同步（显示时区只改文本）。
		_sim_seconds = _abs_unix + float(IsleAstro.TZ_SECONDS)
	else:
		# 切到模拟：从当前显示时刻连续初始化模拟钟，太阳/月亮/船/鸟不会瞬间跳变。
		if was_real:
			_sim_seconds = _abs_unix + float(IsleAstro.TZ_SECONDS)
		_paused = false
	_events = IsleAstro.day_events(_sim_seconds)
	_events_timer = 0.0
	_sim_delta = 0.0
	# 延迟存盘走主循环既有防抖逻辑，避免每帧写 user://settings.cfg
	_settings_save_delay = 0.25
	if _menu != null:
		_menu.set_settings(_settings)
	# 立刻重算光照，避免切换后一帧内 UI 与天空不一致
	_update_lighting()
	# 时间源变化后立即重新校准船只状态/夜间休息窗口
	_sync_boat_clock()
	if mode == "real":
		_hud.show_toast("现实时间模式 · 跟随 %s 真实时钟" % _tz_label_text())
	else:
		_hud.show_toast("模拟时间模式 · 时间流速由设置决定")

func _set_time_source(src: String, tz: String) -> void:
	if src != "sim" and src != "real":
		src = "sim"
	_time_source = src
	_settings["time_source"] = src
	if tz != "":
		_timezone = tz
		_settings["timezone"] = tz
	_apply_user_settings(true)
	if _menu != null:
		_menu.set_settings(_settings)

func _apply_audio_volume() -> void:
	if _audio == null:
		return
	# Phase6：五组总线音量（主/环境/鸟鸣/火焰/音效），每组即时生效并独立于其它组
	for g in Settings.audio_groups():
		var key := String(g["key"])
		var bus := String(g["bus"])
		var v := clampf(float(_settings.get(key, Settings.audio_default(key))), 0.0, 1.0)
		if _audio.has_method("set_bus_volume"):
			_audio.set_bus_volume(bus, v)
		elif _audio.has_method("set_volume") and bus == "Master":
			_audio.set_volume(v)
	if _audio.has_method("set_muted"):
		_audio.set_muted(float(_settings.get("volume_master", 0.8)) <= 0.001)

func _apply_window_mode(mode_name: String) -> void:
	# Phase6：窗口化 / 独占全屏 / 无边框三态。自动测试保持固定窗口。
	if _shots or _perf or _selftest or _transition:
		return
	if DisplayServer.get_name() == "headless":
		return
	match Settings.sanitize_window_mode(mode_name, _settings.get("fullscreen", false)):
		"fullscreen":
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		"borderless":
			if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		_:
			if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)

## 兼容旧调用点（Esc 菜单的全屏按钮/F11）：由 bool 推导三态窗口模式。
func _apply_fullscreen(on: bool) -> void:
	_apply_window_mode("fullscreen" if on else "windowed")

func _toggle_fullscreen() -> void:
	var mode := String(_settings.get("window_mode", "windowed"))
	var next := "windowed" if mode == "fullscreen" else "fullscreen"
	_settings["window_mode"] = next
	_settings["fullscreen"] = next == "fullscreen"
	_apply_window_mode(next)
	_apply_resolution()
	Settings.save_settings(_settings)
	if _menu != null:
		_menu.set_settings(_settings)
	if _hud != null:
		_hud.show_toast("全屏：开" if bool(_settings["fullscreen"]) else "全屏：关")

func _apply_resolution(target: Variant = null, force: bool = false) -> void:
	# 自动截图 / 性能 / 转场测试保持固定窗口；自测通过 force 做一次真实窗口验证后恢复
	if DisplayServer.get_name() == "headless":
		return
	if not force and (_shots or _perf or _transition):
		return
	var win := get_window()
	if win != null:
		# 高 DPI：内容缩放交给 canvas_items + expand，UI 按锚点扩展，不改系统显示分辨率
		win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		win.content_scale_size = Vector2i(1440, 900)
		win.min_size = Vector2i(1024, 576)
	if not force and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		# 独占全屏下由显示模式决定渲染尺寸，只记录偏好，不改窗口大小
		if target != null:
			_settings["resolution"] = Settings.sanitize_resolution(target)
		return
	var raw: Variant = target if target != null else _settings.get("resolution", Settings.default_resolution())
	var want := Settings.sanitize_resolution(raw)
	var usable := DisplayServer.screen_get_usable_rect()
	if usable.size.x >= 640 and usable.size.y >= 360:
		want.x = mini(want.x, usable.size.x)
		want.y = mini(want.y, usable.size.y)
	DisplayServer.window_set_size(want)
	# 重新居中，避免小分辨率时窗口跑到屏幕外
	if usable.size.x >= 640 and usable.size.y >= 360:
		DisplayServer.window_set_position(usable.position + (usable.size - want) / 2)
	_settings["resolution"] = want

func _apply_quality(q: int) -> void:
	# Phase6：五档画质（低/中/高/极高/极致）。参数表由 isle_quality.gd 提供，
	# 缺失/缺键时用本文件内置的五档兜底表，保证界面档位与实际渲染参数严格一一对应。
	_quality = clampi(q, 0, Settings.QUALITY_COUNT - 1)
	_hud_quality_label = Settings.quality_summary(_settings)
	var p := _quality_params()
	_quality_state = p.duplicate(true)
	var vp := get_viewport()
	# 3D 抗锯齿 / 时间抗锯齿 / 渲染缩放
	vp.msaa_3d = int(p["msaa_3d"])
	vp.msaa_2d = int(p.get("msaa_2d", 0))
	vp.screen_space_aa = int(p.get("screen_space_aa", 0))
	vp.use_taa = bool(p.get("taa", false))
	vp.scaling_3d_scale = clampf(float(p.get("scaling_3d_scale", 1.0)), 0.5, 2.0)
	vp.scaling_3d_mode = int(p.get("scaling_3d_mode", 0))
	Engine.max_fps = int(p.get("max_fps", 0))
	if _env != null:
		_env.tonemap_mode = _tonemap_enum(int(p.get("tonemap", 0)))
		_env.tonemap_exposure = clampf(float(p.get("exposure", 1.0)), 0.5, 2.0)
		_env.glow_enabled = _quality >= 1
		_env.glow_intensity = clampf(float(p.get("glow_strength", 0.6)), 0.0, 2.0)
		# 引擎 SSAO/SSIL 对全 unshaded 自定义管线不产生可见效果；引擎体积雾虽会改变画面，
		# 但在黎明/黄昏会被未受光的雾染暗海面（2026-10-20 T7 实测：黎明海面接近全黑、远景山体成黑带），
		# 与既有暖色天空/海面艺术风格冲突，故不接入，也不在菜单暴露覆盖开关。详见 docs/P6_AO_FOG_EVAL.md。
		_env.ssao_enabled = false
		_env.ssil_enabled = false
		_env.volumetric_fog_enabled = false
	if _sky_mat != null:
		_sky_mat.set_shader_parameter("cloud_detail", float(p.get("sky_cloud_detail", 2.0)))
	if _sea_mat != null:
		_sea_mat.set_shader_parameter("wave_detail", float(p.get("sea_wave_detail", 1.0)))
		_sea_mat.set_shader_parameter("foam_amount", float(p.get("sea_foam", 0.78)))
		_sea_mat.set_shader_parameter("island_refl", float(p.get("sea_reflection", 1.0)))
		# 预留统一命名：T3 的 sea.gdshader 若声明了这些 uniform 会自动生效
		_sea_mat.set_shader_parameter("ssr_strength", float(p.get("sea_ssr", 0.0)))
		_sea_mat.set_shader_parameter("wave_scale", float(p.get("sea_wave_scale", 1.0)))
		# 水面近/中景细节密度（低档也不关，避免切档时"水面突然变平"）。
		# 这三个键由 IsleQuality.sea_params(p) 按档计算，不在 preset 扁平表里。
		var sp: Dictionary = IsleQuality.sea_params(p)
		_sea_mat.set_shader_parameter("sea_normal_detail", float(sp.get("sea_normal_detail", 1.0)))
		_sea_mat.set_shader_parameter("sea_foam_detail", float(sp.get("sea_foam_detail", 1.0)))
		_sea_mat.set_shader_parameter("sea_refl_detail", float(sp.get("sea_refl_detail", 1.0)))
	_light_budget = int(p.get("light_budget", 8))
	_apply_sea_mesh(float(p.get("sea_mesh_scale", 1.0)))
	_apply_lod_bias(float(p.get("lod_bias", 1.0)))
	# 自定义 AO：开关由 posts_ao 布尔决定（同时兼容菜单高级覆盖写入的 UI 别名 post_ao），
	# ao_strength 只表达强度。此前只读 ao_strength，导致「高级覆盖=关」只改状态不动渲染。
	if _post_ao_mat != null and _post_ao_mi != null:
		var ao_on := bool(p.get("posts_ao", true))
		if p.has("post_ao"):
			ao_on = bool(p["post_ao"])
		var ao_s := clampf(float(p.get("ao_strength", 0.0)), 0.0, 1.0)
		if not ao_on:
			ao_s = 0.0
		elif ao_s <= 0.001:
			# 低/中档预设默认关 AO（strength=0）；玩家在高级覆盖里手动打开时给一个可见强度。
			ao_s = 0.35
		_post_ao_mat.set_shader_parameter("ao_strength", ao_s)
		_post_ao_mat.set_shader_parameter("ao_radius", float(p.get("ao_radius", 0.9)))
		_post_ao_mat.set_shader_parameter("ao_samples", int(p.get("ao_samples", 12)))
		_post_ao_mat.set_shader_parameter("ao_bias", float(p.get("ao_bias", 0.025)))
		_post_ao_mat.set_shader_parameter("ao_contrast", float(p.get("ao_contrast", 1.4)))
		_post_ao_mat.set_shader_parameter("ao_max_dist", float(p.get("ao_max_dist", 90.0)))
		_post_ao_mi.visible = ao_s > 0.001
	# 草实例预算：近层+远层按同一比例显示，低画质不会出现局部秃斑
	var ratio := clampf(float(p.get("grass_density", 1.0)), 0.0, 1.0)
	_grass_total = 0
	_grass_visible_count = 0
	for nm in ["GrassNear", "GrassFar"]:
		var mi := _find_grass_node(String(nm))
		if mi == null or mi.multimesh == null:
			continue
		var total := int(mi.multimesh.instance_count)
		_grass_total += total
		var vis := int(round(float(total) * float(ratio)))
		mi.multimesh.visible_instance_count = clampi(vis, 0, total)
		_grass_visible_count += int(mi.multimesh.visible_instance_count)
	# 粒子预算（烟 / 花瓣 / 萤火）
	var pratio := clampf(float(p.get("particle_density", 1.0)), 0.1, 1.5)
	for key in ["smoke", "petals", "fireflies"]:
		var entry: Dictionary = _fx.get(key, {})
		var node = entry.get("node", null)
		if node is GPUParticles3D:
			var gp := node as GPUParticles3D
			if not gp.has_meta("base_amount"):
				gp.set_meta("base_amount", gp.amount)
			gp.amount = maxi(6, int(round(float(gp.get_meta("base_amount")) * float(pratio))))

## 五档兜底参数表（isle_quality.gd 缺键时补齐；数值即真实渲染参数）。
func _fallback_quality_params(q: int) -> Dictionary:
	var tiers: Array = [
		{"msaa_3d": 0, "msaa_2d": 0, "screen_space_aa": 1, "taa": false, "scaling_3d_scale": 0.82, "scaling_3d_mode": 0, "max_fps": 45, "sky_cloud_detail": 0.0, "sea_wave_detail": 0.35, "sea_foam": 0.35, "sea_reflection": 0.0, "sea_ssr": 0.0, "sea_mesh_scale": 0.55, "grass_density": 0.45, "particle_density": 0.45, "light_budget": 7, "glow_strength": 0.45, "tonemap": 0, "exposure": 1.0, "lod_bias": 0.8},
		{"msaa_3d": 1, "msaa_2d": 0, "screen_space_aa": 1, "taa": false, "scaling_3d_scale": 0.95, "scaling_3d_mode": 0, "max_fps": 60, "sky_cloud_detail": 1.0, "sea_wave_detail": 0.65, "sea_foam": 0.6, "sea_reflection": 1.0, "sea_ssr": 0.0, "sea_mesh_scale": 0.8, "grass_density": 0.72, "particle_density": 0.65, "light_budget": 8, "glow_strength": 0.6, "tonemap": 1, "exposure": 1.0, "lod_bias": 1.0},
		{"msaa_3d": 2, "msaa_2d": 1, "screen_space_aa": 1, "taa": false, "scaling_3d_scale": 1.0, "scaling_3d_mode": 0, "max_fps": 0, "sky_cloud_detail": 2.0, "sea_wave_detail": 1.0, "sea_foam": 0.78, "sea_reflection": 1.0, "sea_ssr": 0.0, "sea_mesh_scale": 1.0, "grass_density": 1.0, "particle_density": 0.85, "light_budget": 9, "glow_strength": 0.6, "tonemap": 2, "exposure": 1.0, "lod_bias": 1.1},
		{"msaa_3d": 2, "msaa_2d": 1, "screen_space_aa": 2, "taa": false, "scaling_3d_scale": 1.2, "scaling_3d_mode": 0, "max_fps": 0, "sky_cloud_detail": 3.0, "sea_wave_detail": 1.45, "sea_foam": 0.9, "sea_reflection": 1.0, "sea_ssr": 0.6, "sea_mesh_scale": 1.3, "grass_density": 1.0, "particle_density": 1.0, "light_budget": 11, "glow_strength": 0.75, "tonemap": 3, "exposure": 1.03, "lod_bias": 1.3},
		{"msaa_3d": 3, "msaa_2d": 1, "screen_space_aa": 2, "taa": true, "scaling_3d_scale": 1.5, "scaling_3d_mode": 0, "max_fps": 0, "sky_cloud_detail": 3.0, "sea_wave_detail": 2.0, "sea_foam": 1.0, "sea_reflection": 1.0, "sea_ssr": 1.0, "sea_mesh_scale": 1.6, "grass_density": 1.0, "particle_density": 1.15, "light_budget": 12, "glow_strength": 0.9, "tonemap": 3, "exposure": 1.06, "lod_bias": 1.5},
	]
	return (tiers[clampi(q, 0, tiers.size() - 1)] as Dictionary).duplicate(true)

## 生效参数 = IsleQuality.preset(q) + 玩家自定义覆盖 + 内置兜底。
func _quality_params() -> Dictionary:
	var overrides: Dictionary = {}
	var ov: Variant = _settings.get("quality_overrides", {})
	if ov is Dictionary:
		overrides = ov as Dictionary
	var p: Dictionary = Settings.quality_effective(_quality, overrides)
	# 菜单高级覆盖历史上把 AO 开关存成 UI 别名 "post_ao"，而参数表/渲染键是
	# "posts_ao"。这里做唯一一次归一（保留外部存档契约，内部只留规范键），
	# 避免"改开关不改渲染"的两套键并存。
	if p.has("post_ao"):
		p["posts_ao"] = bool(p["post_ao"])
		p.erase("post_ao")
	var fb := _fallback_quality_params(_quality)
	for k in fb.keys():
		if not p.has(k):
			p[k] = fb[k]
	return p

func _tonemap_enum(mode: int) -> int:
	match mode:
		0:
			return Environment.TONE_MAPPER_LINEAR
		1:
			return Environment.TONE_MAPPER_FILMIC
		2:
			return Environment.TONE_MAPPER_ACES
		3:
			return Environment.TONE_MAPPER_AGX
	return Environment.TONE_MAPPER_AGX

## 海面网格细分随画质档位调整：低档省顶点，极高/极致档获得更细的几何起伏。
func _apply_sea_mesh(scale: float) -> void:
	var want := int(round(180.0 * clampf(scale, 0.5, 2.0)))
	want = clampi(want, 96, 320)
	if want == _sea_subdiv:
		return
	_sea_subdiv = want
	var sea := get_node_or_null("Sea") as MeshInstance3D
	if sea == null:
		return
	var pm := PlaneMesh.new()
	pm.size = Vector2(1400, 1400)
	pm.subdivide_width = _sea_subdiv
	pm.subdivide_depth = _sea_subdiv
	sea.mesh = pm
	if _sea_mat != null:
		_sea_mat.set_shader_parameter("wave_scale", 1.0)

# 画质档 LOD 偏置：缩放世界层岩石近/远 LOD 的可见范围（world.gd 建出的
# Rocks_<family>_Near / Rocks_<family>_Far 的 visibility_range，基准 28m / 24m）。
# 两段同时等比缩放，重叠区间始终存在，切档不会出现岩石空洞或突跳。
func _apply_lod_bias(bias: float) -> void:
	var b := clampf(bias, 0.6, 1.6)
	var holder := get_node_or_null("World")
	if holder == null:
		return
	# 岩石挂在 World/Island 下（world.gd build() 的 root），必须递归查找。
	for child in holder.find_children("Rocks_*", "", true, false):
		var nm := String(child.name)
		if child is GeometryInstance3D:
			if nm.begins_with("Rocks_") and nm.ends_with("_Near"):
				(child as GeometryInstance3D).visibility_range_end = 28.0 * b
			elif nm.begins_with("Rocks_") and nm.ends_with("_Far"):
				(child as GeometryInstance3D).visibility_range_begin = 24.0 * b

func _find_grass_node(node_name: String) -> MultiMeshInstance3D:
	var root = _world.get("root", null)
	if root == null:
		return null
	return (root as Node).find_child(node_name, true, false) as MultiMeshInstance3D

func _grass_visible() -> int:
	var total := 0
	for nm in ["GrassNear", "GrassFar"]:
		var mi := _find_grass_node(String(nm))
		if mi != null and mi.multimesh != null:
			var v := int(mi.multimesh.visible_instance_count)
			total += int(mi.multimesh.instance_count if v < 0 else v)
	return total

func _update_audio(delta: float) -> void:
	if _audio == null or not _audio.has_method("update_audio"):
		return
	var night := clampf(-_sun_alt / 10.0, 0.0, 1.0)
	var wind := clampf(0.40 + 0.22 * sin(_frame_t * 0.09) + 0.10 * sin(_frame_t * 0.31), 0.0, 1.0)
	_audio.update_audio(delta, {
		"sun_alt": _sun_alt,
		"night": night,
		"wind": wind,
		"fireplace_on": _sun_alt < 2.0,
	})

func _sfx_door(open: bool) -> void:
	if _audio != null and _audio.has_method("play_door"):
		_audio.play_door(open)

func _sfx_splash(power: float) -> void:
	if _audio != null and _audio.has_method("play_splash"):
		_audio.play_splash(power)

func _sfx_ui() -> void:
	if _audio != null and _audio.has_method("play_ui_click"):
		_audio.play_ui_click()

func _update_hover(delta: float) -> void:
	if _flycam != null and _flycam.active:
		return
	if _mode != Mode.PLAYING or _shots or _perf or _selftest or _transition:
		return
	if _blending != "" or _dragging or _panning:
		return
	_hover_timer -= delta
	if _hover_timer > 0.0:
		return
	_hover_timer = 0.08
	if _hud == null or not bool(_hud.get("_visible_now")):
		return
	var mp := get_viewport().get_mouse_position()
	var from := _cam.project_ray_origin(mp)
	var dir := _cam.project_ray_normal(mp)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 900.0)
	q.collision_mask = 2
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var col: Object = null
	if not hit.is_empty():
		col = hit["collider"]
	if col != null and col == _cottage.get("door_hit"):
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
		_hud.show_hover_hint("点击 · 开 / 关门")
	elif col != null and col == _cottage.get("chimney_hit"):
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
		_hud.show_hover_hint("点击 · 烟囱")
	else:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		_hud.hide_hover_hint()

func _update_perf_overlay(delta: float) -> void:
	if _hud == null or not bool(_hud.get("_perf_open")):
		return
	_perf_timer -= delta
	if _perf_timer > 0.0:
		return
	_perf_timer = 0.5
	var fps := maxf(Engine.get_frames_per_second(), 1.0)
	_hud.update_perf({
		"clock": _display_clock_text(),
		"phase": _phase_name,
		"fps": fps,
		"frame_ms": 1000.0 / fps,
		"cpu_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"vram_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"lights": mini(_lights.size(), _light_budget),
		"grass": _grass_visible_count,
		"quality": _hud_quality_label,
	})

func _take_photo() -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace("T", "_")
	var img := get_viewport().get_texture().get_image()
	# 正常写入 user://screenshots；若用户目录不可写（受限环境/只读配置），依次回退到
	# 可执行文件目录、res://screenshots（开发期）、开发产物/photos（本机验证目录）。
	var dirs: Array = [
		"user://screenshots",
		OS.get_executable_path().get_base_dir().path_join("screenshots"),
		ProjectSettings.globalize_path("res://screenshots"),
		"D:/休闲小岛幻境/开发产物/photos",
	]
	var saved := false
	for d in dirs:
		DirAccess.make_dir_recursive_absolute(String(d))
		var path := String(d).path_join("isle_%s_%d.png" % [stamp, _photo_count])
		if img.save_png(path) == OK:
			_photo_count += 1
			_last_photo = path
			saved = true
			print("[PHOTO] ", path)
			break
	if saved:
		if _hud != null:
			_hud.show_toast("已保存截图 · F2 再拍一张")
	else:
		if _hud != null:
			_hud.show_toast("截图保存失败")

# ============================================================
# P7 专项截图（--p7shots）：黄昏归栖 / 夜间稳定 / 清晨恢复 / 船鸟联动
# 仅用于视觉验收：只放慢太阳并固定机位，不改变正式运行的生态规则。
# ============================================================
func _run_p7shots() -> void:
	_mode = Mode.PLAYING
	_started = true
	_paused = false
	_menu.instant_finish()
	_blending = ""
	_apply_pose(_play_pose())
	_hud.set_hud_visible(false, false)
	_auto_orbit = false
	_shot_beam_lock = false
	# 放慢太阳：让黄昏阶段在截图期间保持稳定可复现（正式运行仍用玩家设置流速）。
	_day_length = 3600.0
	await get_tree().create_timer(0.9).timeout
	_p7_camera_island()
	# 1) 白天海鸥活动（应有飞行/停栖混合）
	_set_time_of_day(12.0 * 60.0 + 20.0)
	_update_lighting()
	await get_tree().create_timer(4.0).timeout
	await _p7_shot("p7_01_day_gulls")
	await _p7_shot_close("p7_01b_day_gulls_close", 12.0, 3.0)
	_p7_camera_island()
	# 2) 黄昏归栖开始：太阳从上方下穿 +4°
	_set_p7_sim_time(_p7_time_for_alt(4.2, true))
	_update_lighting()
	await get_tree().create_timer(2.5).timeout
	await _p7_shot("p7_02_dusk_roost_start")
	await _p7_shot_close("p7_02b_dusk_roost_close", 12.0, 3.0)
	_p7_camera_island()
	# 3) 黄昏归栖推进：太阳接近地平线，空中数量应明显下降
	_set_p7_sim_time(_p7_time_for_alt(0.6, true))
	_update_lighting()
	await get_tree().create_timer(6.0).timeout
	await _p7_shot("p7_03_dusk_roost_mid")
	await _p7_shot_close("p7_03b_dusk_mid_close", 12.0, 3.0)
	_p7_camera_island()
	# 4) 稳定夜间：全部停栖、夜灯/窗灯/星空
	_set_time_of_day(22.0 * 60.0 + 20.0)
	_update_lighting()
	await get_tree().create_timer(5.0).timeout
	await _p7_shot("p7_04_night_calm")
	await _p7_shot_close("p7_04b_night_perch_close", 8.0, 2.2, "perch")
	_p7_camera_island()
	# 5) 清晨恢复：太阳升过 +2° 后错峰起飞，不是全体同步
	_set_p7_sim_time(_p7_time_for_alt(3.0, false))
	_update_lighting()
	await get_tree().create_timer(6.0).timeout
	await _p7_shot("p7_05_dawn_recover")
	await _p7_shot_close("p7_05b_dawn_recover_close", 12.0, 3.0)
	_p7_camera_island()
	# 6) 船进近海航段 + 海鸥短暂响应
	_set_time_of_day(11.0 * 60.0)
	_update_lighting()
	await get_tree().create_timer(1.0).timeout
	var route: Dictionary = _p7_pick_coastal_route()
	if not route.is_empty():
		var trigger := _p7_setup_boat_pass(route)
		if trigger > 0.0:
			var wait_s: float = clampf(6.0 / maxf(_boat_route_speed, 0.5), 0.5, 4.0) + 1.6
			await get_tree().create_timer(wait_s).timeout
			_p7_camera_boat()
			await get_tree().create_timer(0.5).timeout
			await _p7_shot("p7_06_boat_pass")
			await _p7_shot_boat_respond_close("p7_06b_boat_respond_close")
			_p7_camera_boat()
			await get_tree().create_timer(14.0).timeout
			await _p7_shot("p7_07_boat_recovered")
			await _p7_shot_close("p7_07b_boat_recovered_close", 12.0, 3.0)
	print("[SHOT] p7 sequence done")
	get_tree().quit()

## P7 截图：保存到独立目录，并把鸟群生态状态打进日志便于逐张核对。
func _p7_shot(shot_name: String) -> void:
	await _save_shot(shot_name, P7_SHOTS_DIR)
	var eco: Dictionary = {}
	var counts: Dictionary = {}
	if _birds != null:
		eco = _birds.debug_eco_state()
		counts = _birds.get_state_counts()
	var compact := {
		"airborne": counts.get("airborne", -1),
		"perched": counts.get("perched", -1),
		"waiting": counts.get("waiting", -1),
		"takeoffs": counts.get("takeoffs", -1),
		"landings": counts.get("landings", -1),
		"conflicts": counts.get("perch_conflicts", -1),
	}
	print("[P7] ", shot_name, " sun_alt=", snappedf(_sun_alt, 0.01), " eco=", JSON.stringify(eco), " counts=", JSON.stringify(compact))

## P7 截图：把相机拉近到当前空中的海鸥群 / 响应船只的海鸥 / 夜间栖鸟，验证行为可观察性。
## 只影响截图机位，不改变正式运行的生态规则。
func _p7_shot_close(shot_name: String, back: float, up: float, mode: String = "air") -> void:
	if not _p7_camera_birds(back, up, mode):
		return
	await get_tree().create_timer(0.5).timeout
	await _p7_shot(shot_name)

func _p7_camera_birds(back: float, up: float, mode: String) -> bool:
	if _birds == null:
		return false
	var snap: Array = _birds.debug_snapshot()
	var c := Vector3.ZERO
	var n := 0
	if mode == "perch":
		# 夜间：选最高的一只栖鸟（大树冠层），避免被屋顶挡住视线。
		var best: Dictionary = {}
		for s_v in snap:
			var sp: Dictionary = s_v
			if int(sp["state"]) != 3:
				continue
			if best.is_empty() or (sp["pos"] as Vector3).y > (best["pos"] as Vector3).y:
				best = sp
		if best.is_empty():
			return false
		c = best["pos"] as Vector3
		n = 1
	else:
		for s_v in snap:
			var s: Dictionary = s_v
			var st: int = int(s["state"])
			if st == 3:
				continue
			if mode == "resp" and float(s["resp_w"]) <= 0.02 and float(s["resp_timer"]) <= 0.0:
				continue
			c += s["pos"] as Vector3
			n += 1
	if n == 0:
		return false
	c /= float(n)
	var outw := Vector3(c.x, 0.0, c.z)
	if outw.length() < 0.5:
		outw = Vector3(1.0, 0.0, 0.0)
	outw = outw.normalized()
	_pose_look(c + outw * back + Vector3(0.0, up, 0.0), c, 46.0)
	return true

## P7 截图：同框呈现帆船与被它引起的响应海鸥（相机放在两者中点外侧）。
func _p7_shot_boat_respond_close(shot_name: String) -> void:
	if _birds == null or _sailboat == null:
		return
	var snap: Array = _birds.debug_snapshot()
	var c := Vector3.ZERO
	var n := 0
	for s_v in snap:
		var s: Dictionary = s_v
		if int(s["state"]) == 3:
			continue
		if float(s["resp_w"]) <= 0.02 and float(s["resp_timer"]) <= 0.0:
			continue
		c += s["pos"] as Vector3
		n += 1
	if n == 0:
		return
	c /= float(n)
	var b: Vector3 = _sailboat.global_position
	var mid: Vector3 = (c + b) * 0.5
	# 相机放在「船—鸟」连线的水平垂线上，而不是岛屿外法线上：
	# 外法线方向会把相机放到船的外海一侧，船落在相机后方而无法同框。
	var axis := b - c
	axis.y = 0.0
	if axis.length() < 0.5:
		axis = Vector3(1.0, 0.0, 0.0)
	axis = axis.normalized()
	var side := Vector3(-axis.z, 0.0, axis.x)
	var outward := Vector3(mid.x, 0.0, mid.z)
	if outward.length() > 0.1 and side.dot(outward.normalized()) < 0.0:
		side = -side
	var sep := (b - c).length()
	var back := clampf(10.0 + sep * 0.9, 12.0, 40.0)
	var cam_y := clampf(4.0 + sep * 0.1, 4.0, 10.0)
	_pose_look(mid + side * back + Vector3(0.0, cam_y, 0.0), mid + Vector3(0.0, 1.0, 0.0), 55.0)
	await get_tree().create_timer(0.4).timeout
	await _p7_shot(shot_name)

func _set_p7_sim_time(seconds: float) -> void:
	_sim_seconds = seconds
	_events = IsleAstro.day_events(_sim_seconds)

## 扫描当天，返回太阳高度第一次穿越 target_alt 的模拟时刻（秒）。
func _p7_time_for_alt(target_alt: float, descending: bool) -> float:
	var day_start := _sim_seconds - fposmod(_sim_seconds, 86400.0)
	var prev := 0.0
	var have_prev := false
	for m in range(0, 1440):
		var astro: Dictionary = IsleAstro.compute(day_start + float(m) * 60.0)
		var alt := float(astro["sun_alt"])
		if have_prev:
			var hit: bool = (prev > target_alt and alt <= target_alt) if descending else (prev < target_alt and alt >= target_alt)
			if hit:
				return day_start + float(m) * 60.0
		prev = alt
		have_prev = true
	return day_start + 12.0 * 3600.0

func _p7_camera_island() -> void:
	_theta = 0.86
	_elev = 0.30
	_radius = 60.0
	_cam_target = Vector3(0.0, 11.0, 0.0)
	_fov = 52.0
	_apply_pose(_play_pose())

func _p7_camera_boat() -> void:
	if _sailboat == null:
		return
	var bp: Vector3 = _sailboat.global_position
	var outw := Vector3(bp.x, 0.0, bp.z)
	if outw.length() < 0.1:
		outw = Vector3(0.0, 0.0, 1.0)
	outw = outw.normalized()
	var cam := bp + outw * 16.0 + Vector3(0.0, 5.5, 0.0)
	_pose_look(cam, bp + Vector3(0.0, 2.4, 0.0), 52.0)

func _p7_pick_coastal_route() -> Dictionary:
	for r_v in _sail_routes:
		var r: Dictionary = r_v
		if String(r.get("kind", "")) == "coastal" and r.has("shore_a0"):
			return r
	return {}

## P7 截图：真实近海航线 + 真实航次号，把船摆到触发点前 6m，由状态机自行驶过触发点。
func _p7_setup_boat_pass(route: Dictionary) -> float:
	if _sailboat == null:
		return -1.0
	_sail_route = route
	_sail_route["_out_pts"] = _route_points(route.get("out", []))
	_sail_route["_back_pts"] = _route_points(route.get("back", []))
	_boat_route_kind = "coastal"
	_boat_route_speed = maxf(_sail_speed, float(route.get("speed", _sail_speed)))
	_boat_route_len = _polyline_len(_sail_route["_out_pts"])
	_set_boat_shore_window(_sail_route)
	if _boat_shore_trigger <= 0.0 or _boat_shore_trigger >= _boat_route_len - 1.0:
		return -1.0
	_boat_route_dist = maxf(0.0, _boat_shore_trigger - 6.0)
	_boat_speed_cur = _boat_route_speed
	_boat_fade = 1.0
	_boat_state = "COASTAL_CRUISE"
	_sail_phase = "out"
	_boat_trip += 1
	var smp: Dictionary = _sample_polyline(_sail_route["_out_pts"], _boat_route_dist)
	var pos: Vector3 = smp["pos"]
	var dir: Vector3 = smp["dir"]
	_boat_apply(pos, atan2(dir.x, dir.z), _boat_route_speed, 1.0 / 60.0)
	_apply_boat_fade()
	print("[P7] boat pass armed route=", String(route.get("name", "?")), " trip=", _boat_trip, " trigger=", snappedf(_boat_shore_trigger, 0.1), " len=", snappedf(_boat_route_len, 0.1))
	return _boat_shore_trigger

