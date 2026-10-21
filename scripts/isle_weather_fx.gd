extends RefCounted
## P8 阶段 6：天气视觉粒子工厂。
##
## 只负责创建降水粒子节点（雨/雪），不持有权威时钟、不推进天气状态。
## 每帧由 main.gd 写入 amount_ratio / emitting / visible / 风向等参数：
##   - 局部降水（岛屿与近海），节点水平跟随相机并夹紧在岛屿附近，不铺满全世界；
##   - 每类降水只有一个 GPUParticles3D（每个 draw pass 一次实例化），不建逐滴节点；
##   - 粒子数由画质 particle_density 缩放（main._apply_quality），室内由 main 隐藏；
##   - 雪的地面/屋顶/枝干积雪不在这里做，统一由 toon.gdshader 的 g_weather.w 完成。

const RAIN_BASE_AMOUNT := 2600
const SNOW_BASE_AMOUNT := 1100
const PRECIP_SHADER := preload("res://shaders/precip.gdshader")
const SPLASH_SHADER := preload("res://shaders/splash.gdshader")

const SPLASH_COUNT := 220
const SPLASH_RADIUS := 23.0


static func build(parent: Node3D) -> Dictionary:
	var out := {}
	out["rain"] = _build_rain(parent)
	out["snow"] = _build_snow(parent)
	out["drip"] = _build_drip(parent)
	out["splash"] = _build_splash(parent)
	return out


# ---------------------------------------------------------------- 屋檐滴水
## 沿小屋正面屋檐的一条短水线（位置/朝向由 main 按房屋实体盒摆放，见 _setup_weather_fx）。
static func _build_drip(parent: Node3D) -> Dictionary:
	var node := GPUParticles3D.new()
	node.name = "WeatherDrip"
	node.amount = 80
	node.lifetime = 1.05
	node.preprocess = 0.0
	node.fixed_fps = 30
	node.interpolate = true
	node.local_coords = false
	node.emitting = false
	node.visible = false
	node.visibility_aabb = AABB(Vector3(-16.0, -8.0, -16.0), Vector3(32.0, 12.0, 32.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(3.0, 0.04, 0.16)
	pm.direction = Vector3(0.0, -1.0, 0.0)
	pm.spread = 2.0
	pm.initial_velocity_min = 0.10
	pm.initial_velocity_max = 0.55
	pm.gravity = Vector3(0.0, -9.8, 0.0)
	pm.scale_min = 0.6
	pm.scale_max = 1.1
	pm.lifetime_randomness = 0.2
	pm.color = Color(0.80, 0.87, 0.97, 0.65)
	node.process_material = pm
	var mat := ShaderMaterial.new()
	mat.shader = PRECIP_SHADER
	mat.set_shader_parameter("albedo_tex", _streak_texture())
	mat.set_shader_parameter("albedo_color", Color(0.80, 0.86, 0.96, 0.9))
	mat.set_shader_parameter("near_fade_start", 0.5)
	mat.set_shader_parameter("near_fade_end", 2.2)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.030, 0.34)
	quad.material = mat
	node.draw_pass_1 = quad
	parent.add_child(node)
	return {"node": node, "mat": mat, "pm": pm, "base_amount": 80}


# ---------------------------------------------------------------- 地面水花
## 岛上地面锚点 + 一个 MultiMesh：每个实例一个横放小圆环，shader 用 TIME/相位循环。
## 锚点位置固定（种子确定性），只在地形高度足够（非沙滩/海面）的地方生成。
static func _build_splash(parent: Node3D) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261022
	var xforms: Array = []
	var customs: Array = []
	var tries := 0
	while xforms.size() < SPLASH_COUNT and tries < 600:
		tries += 1
		var ang := rng.randf_range(0.0, TAU)
		var rad := sqrt(rng.randf()) * SPLASH_RADIUS
		var x := cos(ang) * rad
		var z := sin(ang) * rad
		var h := IsleMath.terrain_height(x, z)
		if h < 1.35:
			continue
		var y := h + 0.035
		xforms.append(Transform3D(Basis.IDENTITY, Vector3(x, y, z)))
		customs.append(Color(rng.randf(), 0.0, 0.0, 0.0))
	var mesh := PlaneMesh.new()
	mesh.size = Vector2.ONE
	var mat := ShaderMaterial.new()
	mat.shader = SPLASH_SHADER
	mat.set_shader_parameter("albedo_color", Color(0.90, 0.95, 1.0, 0.66))
	mat.set_shader_parameter("strength", 0.0)
	mesh.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in range(xforms.size()):
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_custom_data(i, customs[i])
	var node := MultiMeshInstance3D.new()
	node.name = "WeatherSplash"
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visible = false
	parent.add_child(node)
	return {"node": node, "mat": mat, "mm": mm, "base_amount": xforms.size()}


# ---------------------------------------------------------------- 雨
static func _build_rain(parent: Node3D) -> Dictionary:
	var node := GPUParticles3D.new()
	node.name = "WeatherRain"
	node.amount = RAIN_BASE_AMOUNT
	node.lifetime = 1.45
	node.preprocess = 1.0
	node.fixed_fps = 30
	node.interpolate = true
	node.local_coords = false
	node.emitting = false
	node.visible = false
	node.visibility_aabb = AABB(Vector3(-80.0, -12.0, -80.0), Vector3(160.0, 96.0, 160.0))
	node.position = Vector3(0.0, 33.0, 0.0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(62.0, 19.0, 62.0)
	pm.direction = Vector3(0.0, -1.0, 0.0)
	pm.spread = 3.0
	pm.initial_velocity_min = 26.0
	pm.initial_velocity_max = 32.0
	pm.gravity = Vector3(0.0, -4.0, 0.0)
	pm.scale_min = 0.75
	pm.scale_max = 1.35
	pm.lifetime_randomness = 0.25
	pm.color = Color(0.72, 0.80, 0.94, 0.55)
	node.process_material = pm
	# 自定义降水 shader：绕 Y 公告板 + 室内盒剔除（StandardMaterial3D 做不到）
	var mat := ShaderMaterial.new()
	mat.shader = PRECIP_SHADER
	mat.set_shader_parameter("albedo_tex", _streak_texture())
	mat.set_shader_parameter("albedo_color", Color(0.80, 0.86, 0.96, 1.0))
	mat.set_shader_parameter("near_fade_start", 0.8)
	mat.set_shader_parameter("near_fade_end", 3.4)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.045, 1.55)
	quad.material = mat
	node.draw_pass_1 = quad
	parent.add_child(node)
	return {"node": node, "mat": mat, "pm": pm, "base_amount": RAIN_BASE_AMOUNT}


# ---------------------------------------------------------------- 雪
static func _build_snow(parent: Node3D) -> Dictionary:
	var node := GPUParticles3D.new()
	node.name = "WeatherSnow"
	node.amount = SNOW_BASE_AMOUNT
	node.lifetime = 9.5
	node.preprocess = 3.5
	node.fixed_fps = 30
	node.interpolate = true
	node.local_coords = false
	node.emitting = false
	node.visible = false
	node.visibility_aabb = AABB(Vector3(-80.0, -12.0, -80.0), Vector3(160.0, 96.0, 160.0))
	node.position = Vector3(0.0, 27.0, 0.0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(58.0, 13.0, 58.0)
	pm.direction = Vector3(0.0, -1.0, 0.0)
	pm.spread = 18.0
	pm.initial_velocity_min = 0.55
	pm.initial_velocity_max = 1.35
	pm.gravity = Vector3(0.0, -0.28, 0.0)
	pm.scale_min = 0.55
	pm.scale_max = 1.25
	pm.lifetime_randomness = 0.35
	pm.color = Color(0.96, 0.98, 1.0, 0.92)
	node.process_material = pm
	var mat := ShaderMaterial.new()
	mat.shader = PRECIP_SHADER
	mat.set_shader_parameter("albedo_tex", _flake_texture())
	mat.set_shader_parameter("albedo_color", Color(1.0, 1.0, 1.0, 0.92))
	mat.set_shader_parameter("near_fade_start", 0.9)
	mat.set_shader_parameter("near_fade_end", 4.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.16)
	quad.material = mat
	node.draw_pass_1 = quad
	parent.add_child(node)
	return {"node": node, "mat": mat, "pm": pm, "base_amount": SNOW_BASE_AMOUNT}


# ---------------------------------------------------------------- 程序化贴图
## 竖直雨丝：中段亮、上下端淡出，横向略收窄；8x64，小到不需要外部资源。
static func _streak_texture() -> ImageTexture:
	var w := 8
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		var t := float(y) / float(h - 1)
		var a := pow(sin(PI * t), 0.65)
		for x in range(w):
			var cx := (float(x) + 0.5) / float(w) - 0.5
			var edge := 1.0 - smoothstep(0.16, 0.5, absf(cx))
			var aa := clampf(a * edge, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, aa))
	return ImageTexture.create_from_image(img)


## 雪花：柔和圆点（中心亮、边缘淡），32x32。
static func _flake_texture() -> ImageTexture:
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in range(n):
		for x in range(n):
			var uv := Vector2((float(x) + 0.5) / float(n), (float(y) + 0.5) / float(n)) * 2.0 - Vector2.ONE
			var r := uv.length()
			var a := 1.0 - smoothstep(0.55, 1.0, r)
			# 中心稍亮一点，避免纯灰圆点
			a *= 0.80 + 0.20 * (1.0 - r)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(a, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)
