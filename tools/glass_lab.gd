extends Node3D
## 玻璃独立测试场景（glass 模块 P5）：不加载 isle.tscn，只验证 glass.gdshader 的
## 正面/斜视/掠射反射、屏幕空间折射、透见室内、昼夜发光与透明排序。
## 运行（窗口渲染，脚本自己截图后退出）：
##   console.exe --path D:/休闲小岛幻境/游戏工程 --resolution 1440x900 res://tools/glass_lab.tscn > logs/glass_lab.log 2>&1
## 截图输出：shots/glass_lab_<preset>_<pose>.png
## 注意：独立场景没有 main.gd 注册的 global uniform，这里按 main 的同名/同类型自行注册。

const M := preload("res://scripts/isle_math.gd")
const OUT_DIR := "D:/休闲小岛幻境/开发产物/shots/"

var _cam: Camera3D
var _env: Environment
var _sky_mat: ProceduralSkyMaterial
var _sun: DirectionalLight3D
var _glass_mats: Array = []
var _win_glass: ShaderMaterial = null
var _lantern_glass: ShaderMaterial = null
var _lamp_mats: Array = []
var _sun_world := Vector3(0.4, 0.7, 0.55).normalized()

const POSES := [
	{"name": "win_front", "pos": Vector3(0.0, 1.86, 5.30), "target": Vector3(0.0, 1.78, 0.0), "fov": 40.0},
	{"name": "win_oblique", "pos": Vector3(3.25, 2.05, 4.35), "target": Vector3(0.05, 1.74, 0.0), "fov": 44.0},
	{"name": "win_grazing", "pos": Vector3(5.55, 2.15, 1.25), "target": Vector3(0.10, 1.80, 0.0), "fov": 46.0},
	{"name": "lantern_front", "pos": Vector3(6.55, 1.90, 1.05), "target": Vector3(6.55, 1.45, -3.00), "fov": 40.0},
]

const PRESETS := [
	{
		"name": "day",
		"sun": Vector3(0.42, 0.74, 0.52),
		"sun_col": Color(1.0, 0.96, 0.88),
		"sun_energy": 1.4,
		"sky_top": Color(0.22, 0.40, 0.72),
		"sky_horizon": Color(0.62, 0.74, 0.86),
		"ground_horizon": Color(0.50, 0.56, 0.50),
		"ground_bottom": Color(0.20, 0.24, 0.18),
		"g_sky": Color(0.34, 0.50, 0.78),
		"g_ground": Color(0.17, 0.18, 0.15),
		"g_sun": Color(1.85, 1.70, 1.45),
		"g_fog": Color(0.62, 0.74, 0.86),
		"g_fog_near": 90.0,
		"g_fog_far": 420.0,
		"win_glow": 0.06,
		"lamp_boost": 0.55,
		"bg_energy": 1.0,
	},
	{
		"name": "night",
		"sun": Vector3(-0.35, 0.55, -0.62),
		"sun_col": Color(0.55, 0.66, 0.95),
		"sun_energy": 0.05,
		"sky_top": Color(0.012, 0.022, 0.050),
		"sky_horizon": Color(0.030, 0.048, 0.085),
		"ground_horizon": Color(0.020, 0.030, 0.045),
		"ground_bottom": Color(0.006, 0.010, 0.016),
		"g_sky": Color(0.020, 0.035, 0.075),
		"g_ground": Color(0.006, 0.008, 0.012),
		"g_sun": Color(0.10, 0.13, 0.20),
		"g_fog": Color(0.020, 0.032, 0.060),
		"g_fog_near": 90.0,
		"g_fog_far": 420.0,
		"win_glow": 0.52,
		"lamp_boost": 1.0,
		"bg_energy": 1.0,
	},
]

func _ready() -> void:
	_register_globals()
	_build_environment()
	_build_window_wall()
	_build_interior()
	_build_outside()
	_build_lantern()
	_cam = Camera3D.new()
	_cam.name = "LabCam"
	_cam.near = 0.05
	_cam.far = 600.0
	add_child(_cam)
	_cam.current = true
	await get_tree().process_frame
	await get_tree().process_frame
	print("[LAB] adapter=", RenderingServer.get_video_adapter_name(), " api=", RenderingServer.get_video_adapter_api_version())
	print("[LAB] glass_shader=", _shader_path())
	for pr in PRESETS:
		_apply_preset(pr)
		for pose in POSES:
			await _shoot(pr, pose)
	# 额外：夜晚的掠射角度最容易暴露透明排序/黑边问题
	_apply_preset(PRESETS[1])
	_cam_pose(POSES[2])
	await get_tree().process_frame
	await get_tree().process_frame
	await _save("glass_lab_night_grazing2")
	# fade_alpha 抖动剔除自检（main.gd 船窗远海淡出会写这个参数）
	_apply_preset(PRESETS[0])
	_win_glass.set_shader_parameter("fade_alpha", 0.45)
	_cam_pose(POSES[0])
	await get_tree().process_frame
	await get_tree().process_frame
	await _save("glass_lab_day_win_fade45")
	_win_glass.set_shader_parameter("fade_alpha", 1.0)
	# 折射开关对照：同一斜视机位下 refract_weight=0 vs 0.55，用于像素级验证
	# 屏幕空间折射确实生效、位移 <= 0.01，且差异只出现在玻璃区域。
	_apply_preset(PRESETS[0])
	_cam_pose(POSES[1])
	_win_glass.set_shader_parameter("refract_weight", 0.0)
	await get_tree().process_frame
	await get_tree().process_frame
	await _save("glass_lab_refract_ab_off")
	_win_glass.set_shader_parameter("refract_weight", 0.55)
	await get_tree().process_frame
	await get_tree().process_frame
	await _save("glass_lab_refract_ab_on")
	# 参数快照（探针会再复核一次）
	for m in _glass_mats:
		_material_dump(m)
	print("[LAB] done")
	get_tree().quit()

func _shader_path() -> String:
	var sh: Shader = _win_glass.shader
	return sh.resource_path if sh != null else "<none>"

# ---------------------------------------------------------------
# global uniforms：与 scripts/main.gd _setup_globals 同名同类型
# ---------------------------------------------------------------
func _register_globals() -> void:
	var have: Array = RenderingServer.global_shader_parameter_get_list()
	var defs := [
		["g_sun_color", RenderingServer.GLOBAL_VAR_TYPE_COLOR],
		["g_sun_dir_view", RenderingServer.GLOBAL_VAR_TYPE_VEC3],
		["g_ambient_sky", RenderingServer.GLOBAL_VAR_TYPE_COLOR],
		["g_ambient_ground", RenderingServer.GLOBAL_VAR_TYPE_COLOR],
		["g_fog_color", RenderingServer.GLOBAL_VAR_TYPE_COLOR],
		["g_fog_near", RenderingServer.GLOBAL_VAR_TYPE_FLOAT],
		["g_fog_far", RenderingServer.GLOBAL_VAR_TYPE_FLOAT],
	]
	for d in defs:
		if not have.has(StringName(d[0])):
			RenderingServer.global_shader_parameter_add(d[0], int(d[1]), _global_default(int(d[1])))

func _global_default(t: int) -> Variant:
	if t == RenderingServer.GLOBAL_VAR_TYPE_COLOR:
		return Color.WHITE
	if t == RenderingServer.GLOBAL_VAR_TYPE_VEC3:
		return Vector3.ZERO
	return 0.0

func _apply_preset(pr: Dictionary) -> void:
	_sun_world = (pr["sun"] as Vector3).normalized()
	_sky_mat.sky_top_color = pr["sky_top"]
	_sky_mat.sky_horizon_color = pr["sky_horizon"]
	_sky_mat.ground_horizon_color = pr["ground_horizon"]
	_sky_mat.ground_bottom_color = pr["ground_bottom"]
	_sun.light_color = pr["sun_col"]
	_sun.light_energy = float(pr["sun_energy"])
	_sun.look_at_from_position(_sun_world * 40.0, Vector3.ZERO, Vector3.UP)
	RenderingServer.global_shader_parameter_set("g_sun_color", pr["g_sun"])
	RenderingServer.global_shader_parameter_set("g_ambient_sky", pr["g_sky"])
	RenderingServer.global_shader_parameter_set("g_ambient_ground", pr["g_ground"])
	RenderingServer.global_shader_parameter_set("g_fog_color", pr["g_fog"])
	RenderingServer.global_shader_parameter_set("g_fog_near", float(pr["g_fog_near"]))
	RenderingServer.global_shader_parameter_set("g_fog_far", float(pr["g_fog_far"]))
	if _win_glass != null:
		_win_glass.set_shader_parameter("glow", float(pr["win_glow"]))
	var lb := float(pr["lamp_boost"])
	for m in _lamp_mats:
		m.albedo_color = Color(2.6, 1.65, 0.80) * lb

func _cam_pose(pose: Dictionary) -> void:
	_cam.fov = float(pose["fov"])
	_cam.global_position = pose["pos"]
	var target: Vector3 = pose["target"]
	if (_cam.global_position - target).length_squared() > 0.0001:
		_cam.look_at(target, Vector3.UP)
	var inv := _cam.global_transform.basis.inverse()
	RenderingServer.global_shader_parameter_set("g_sun_dir_view", (inv * _sun_world).normalized())

func _shoot(pr: Dictionary, pose: Dictionary) -> void:
	_cam_pose(pose)
	await get_tree().process_frame
	await get_tree().process_frame
	await _save("glass_lab_" + String(pr["name"]) + "_" + String(pose["name"]))

func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(OUT_DIR + name + ".png")
	print("[LAB] shot=", OUT_DIR + name + ".png", " ", img.get_width(), "x", img.get_height(), " err=", err)
	await get_tree().process_frame

# ---------------------------------------------------------------
# 场景内容
# ---------------------------------------------------------------
func _build_environment() -> void:
	_env = Environment.new()
	_sky_mat = ProceduralSkyMaterial.new()
	_sky_mat.sky_curve = 0.18
	_sky_mat.sky_energy_multiplier = 1.0
	_sky_mat.ground_curve = 0.05
	_sky_mat.sun_angle_max = 7.0
	_sky_mat.sun_curve = 0.12
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
	var we := WorldEnvironment.new()
	we.name = "LabEnv"
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.name = "LabSun"
	add_child(_sun)

func _std_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.disable_receive_shadows = true
	return m

func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

func _glass_box(parent: Node3D, size: Vector3, pos: Vector3, mat: ShaderMaterial) -> MeshInstance3D:
	var mi := _box(parent, size, pos, mat)
	mi.name = "GlassPane"
	return mi

func _build_window_wall() -> void:
	var wall := _std_mat(Color(0.72, 0.63, 0.47))
	var wood := _std_mat(Color(0.30, 0.20, 0.12))
	var wood_l := _std_mat(Color(0.42, 0.29, 0.17))
	var g := Node3D.new()
	g.name = "WindowWall"
	add_child(g)
	var pivot := Node3D.new()
	pivot.name = "FrontWall"
	g.add_child(pivot)
	# 前墙（真实洞口 x±1.10, y 0.95..2.85, 墙厚 0.18）
	_box(pivot, Vector3(1.90, 3.20, 0.18), Vector3(-2.05, 1.40, 0.0), wall)
	_box(pivot, Vector3(1.90, 3.20, 0.18), Vector3(2.05, 1.40, 0.0), wall)
	_box(pivot, Vector3(2.20, 1.15, 0.18), Vector3(0.0, 0.375, 0.0), wall)
	_box(pivot, Vector3(2.20, 0.15, 0.18), Vector3(0.0, 2.925, 0.0), wall)
	# 窗框 / 窗台 / 窗棂（全部在玻璃前方或错开 z，不与玻璃共面）
	_box(pivot, Vector3(0.14, 2.20, 0.26), Vector3(-1.17, 1.90, 0.02), wood)
	_box(pivot, Vector3(0.14, 2.20, 0.26), Vector3(1.17, 1.90, 0.02), wood)
	_box(pivot, Vector3(2.48, 0.14, 0.26), Vector3(0.0, 2.92, 0.02), wood)
	_box(pivot, Vector3(2.60, 0.12, 0.34), Vector3(0.0, 0.86, 0.06), wood_l)
	_box(pivot, Vector3(0.05, 1.88, 0.07), Vector3(0.0, 1.90, 0.075), wood)
	_box(pivot, Vector3(2.18, 0.05, 0.06), Vector3(0.0, 1.90, 0.070), wood)
	# 玻璃：薄盒（与 cottage 一致的封闭网格），共享 isle_math.glass_material()
	_win_glass = M.glass_material(0.06)
	_glass_mats.append(_win_glass)
	_glass_box(pivot, Vector3(2.20, 1.90, 0.02), Vector3(0.0, 1.90, 0.02), _win_glass)

func _build_interior() -> void:
	var room := Node3D.new()
	room.name = "Interior"
	add_child(room)
	var wall := _std_mat(Color(0.80, 0.72, 0.58))
	var floor_m := _std_mat(Color(0.52, 0.38, 0.24))
	var ceil_m := _std_mat(Color(0.55, 0.50, 0.42))
	var desk_m := _std_mat(Color(0.36, 0.24, 0.14))
	var rug_m := _std_mat(Color(0.42, 0.14, 0.12))
	_box(room, Vector3(6.00, 3.20, 0.18), Vector3(0.0, 1.40, -3.10), wall)
	_box(room, Vector3(0.18, 3.20, 3.10), Vector3(-3.00, 1.40, -1.60), _std_mat(Color(0.70, 0.62, 0.49)))
	_box(room, Vector3(0.18, 3.20, 3.10), Vector3(3.00, 1.40, -1.60), _std_mat(Color(0.66, 0.58, 0.46)))
	_box(room, Vector3(6.00, 0.10, 3.10), Vector3(0.0, -0.05, -1.60), floor_m)
	_box(room, Vector3(6.00, 0.10, 3.10), Vector3(0.0, 2.95, -1.60), ceil_m)
	# 地毯 + 书桌 + 椅子 + 书（“室内家具必须清楚可见”的判据物）
	_box(room, Vector3(2.20, 0.02, 1.50), Vector3(0.0, 0.011, -1.55), rug_m)
	_box(room, Vector3(1.70, 0.07, 0.85), Vector3(0.0, 0.74, -1.55), desk_m)
	for lx in [-0.76, 0.76]:
		for lz in [-1.88, -1.22]:
			_box(room, Vector3(0.07, 0.72, 0.07), Vector3(lx, 0.37, lz), desk_m)
	_box(room, Vector3(0.42, 0.05, 0.32), Vector3(-0.28, 0.80, -1.55), _std_mat(Color(0.75, 0.16, 0.13)))
	_box(room, Vector3(0.36, 0.05, 0.28), Vector3(0.10, 0.80, -1.58), _std_mat(Color(0.18, 0.42, 0.30)))
	_box(room, Vector3(0.26, 0.04, 0.22), Vector3(0.48, 0.79, -1.50), _std_mat(Color(0.20, 0.26, 0.62)))
	# 椅子（正对窗，挡住一部分透视线，便于检查玻璃不遮挡室内）
	_box(room, Vector3(0.46, 0.06, 0.46), Vector3(0.55, 0.46, -0.95), desk_m)
	for cx in [0.34, 0.76]:
		for cz in [-1.16, -0.74]:
			_box(room, Vector3(0.05, 0.44, 0.05), Vector3(cx, 0.23, cz), desk_m)
	_box(room, Vector3(0.46, 0.46, 0.05), Vector3(0.55, 0.68, -1.17), desk_m)
	# 暖光台灯（HDR 自发光 + main 同款 glow 后处理）
	var lamp_stand := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.03
	cm.bottom_radius = 0.06
	cm.height = 0.55
	lamp_stand.mesh = cm
	lamp_stand.material_override = _std_mat(Color(0.30, 0.22, 0.14))
	lamp_stand.position = Vector3(-0.72, 1.02, -1.55)
	room.add_child(lamp_stand)
	var shade := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.10
	sm.bottom_radius = 0.20
	sm.height = 0.16
	shade.mesh = sm
	shade.material_override = _std_mat(Color(0.55, 0.36, 0.18))
	shade.position = Vector3(-0.72, 1.30, -1.55)
	room.add_child(shade)
	var bulb := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.075
	sph.height = 0.15
	bulb.mesh = sph
	var bm := _std_mat(Color(2.6, 1.65, 0.80))
	bulb.material_override = bm
	bulb.position = Vector3(-0.72, 1.26, -1.55)
	room.add_child(bulb)
	_lamp_mats.append(bm)

func _build_outside() -> void:
	var ground := _std_mat(Color(0.34, 0.44, 0.24))
	_box(self, Vector3(40.0, 0.10, 40.0), Vector3(0.0, -0.06, 0.0), ground)

func _build_lantern() -> void:
	var base := Node3D.new()
	base.name = "LanternRoom"
	base.position = Vector3(6.55, 0.0, -3.00)
	add_child(base)
	var stone := _std_mat(Color(0.62, 0.60, 0.55))
	var wood := _std_mat(Color(0.24, 0.16, 0.10))
	_box(base, Vector3(2.60, 1.10, 2.60), Vector3(0.0, 0.55, 0.0), stone)
	# 灯室玻璃圆筒（封闭网格，与 world.gd 灯室同样复用 glass_material）
	_lantern_glass = M.glass_material(0.30)
	_lantern_glass.set_shader_parameter("opacity", 0.16)
	_glass_mats.append(_lantern_glass)
	var cyl := MeshInstance3D.new()
	var cmm := CylinderMesh.new()
	cmm.top_radius = 0.92
	cmm.bottom_radius = 0.92
	cmm.height = 1.50
	cmm.radial_segments = 24
	cmm.rings = 2
	cyl.mesh = cmm
	cyl.material_override = _lantern_glass
	cyl.position = Vector3(0.0, 1.85, 0.0)
	cyl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	base.add_child(cyl)
	# 室内暖灯（HDR）
	var lamp := MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = 0.10
	lm.bottom_radius = 0.16
	lm.height = 0.85
	lamp.mesh = lm
	var lm_mat := _std_mat(Color(2.6, 1.65, 0.80))
	lamp.material_override = lm_mat
	lamp.position = Vector3(0.0, 1.55, 0.0)
	base.add_child(lamp)
	_lamp_mats.append(lm_mat)
	# 锥顶 + 立柱
	var roof := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.05
	rm.bottom_radius = 1.20
	rm.height = 0.55
	roof.mesh = rm
	roof.material_override = _std_mat(Color(0.52, 0.24, 0.14))
	roof.position = Vector3(0.0, 2.88, 0.0)
	base.add_child(roof)
	_box(base, Vector3(0.10, 0.90, 0.10), Vector3(0.0, 3.60, 0.0), wood)

func _material_dump(m: ShaderMaterial) -> void:
	var keys := ["opacity", "tint_strength", "fresnel_f0", "fresnel_power", "reflection_gain",
		"sun_spec_gain", "sun_shininess", "refract_strength", "refract_weight", "surface_rough",
		"front_sheen", "glow_gain", "glow"]
	var parts: Array = []
	for k in keys:
		parts.append("%s=%s" % [k, str(m.get_shader_parameter(k))])
	print("[LAB] mat priority=", m.render_priority, " ", " ".join(parts))
