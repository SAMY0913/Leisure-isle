extends Node3D

const M := preload("res://scripts/isle_math.gd")

func _ready() -> void:
	var names := ["g_sun_color","g_sun_dir_view","g_moon_color","g_moon_dir_view","g_ambient_sky","g_ambient_ground","g_fog_color","g_fog_near","g_fog_far","g_wind_time","g_outline_color"]
	for n in names:
		RenderingServer.global_shader_parameter_add(n, RenderingServer.GLOBAL_VAR_TYPE_VEC4 if n.ends_with("color") else (RenderingServer.GLOBAL_VAR_TYPE_FLOAT if n in ["g_fog_near","g_fog_far","g_wind_time"] else RenderingServer.GLOBAL_VAR_TYPE_VEC3), null)
	RenderingServer.global_shader_parameter_set("g_sun_color", Color("fff3d8"))
	RenderingServer.global_shader_parameter_set("g_moon_color", Color("8faeff"))
	RenderingServer.global_shader_parameter_set("g_ambient_sky", Color("8fd0ec"))
	RenderingServer.global_shader_parameter_set("g_ambient_ground", Color("65724f"))
	RenderingServer.global_shader_parameter_set("g_fog_color", Color("b2e0ea"))
	RenderingServer.global_shader_parameter_set("g_fog_near", 5000.0)
	RenderingServer.global_shader_parameter_set("g_fog_far", 9000.0)
	RenderingServer.global_shader_parameter_set("g_wind_time", 0.0)
	RenderingServer.global_shader_parameter_set("g_outline_color", Color(0.12, 0.13, 0.17))

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.03, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	add_child(we)

	var cam := Camera3D.new()
	cam.fov = 36.0
	var target := Vector3(0.0, 5.8, 0.0)
	var pose := Vector3(43.4, 49.8, 47.6)
	cam.look_at_from_position(pose, target, Vector3.UP)
	add_child(cam)
	# sun dir in view space
	var sun_world := Vector3(0.0, sin(deg_to_rad(44.0)), cos(deg_to_rad(44.0))).normalized()
	var inv := cam.global_transform.basis.inverse()
	RenderingServer.global_shader_parameter_set("g_sun_dir_view", (inv * sun_world).normalized())
	RenderingServer.global_shader_parameter_set("g_moon_dir_view", (inv * Vector3(0.4, -0.7, -0.4)).normalized())

	# roof-like prism, yaw 0.3
	var n := Node3D.new()
	n.position = Vector3(0.8, 6.15, -0.6)
	n.rotation.y = 0.30
	add_child(n)
	M.prism(n, 12.4, 3.6, 10.0, Vector3.ZERO, M.C_TERRACOTTA, 0.0, {"outline": 0.06})
	var door := Node3D.new()
	door.position = Vector3(0.8, 2.0, -0.6)
	door.rotation.y = 0.3
	add_child(door)
	M.box(door, Vector3(6.0, 6.0, 6.0), Vector3.ZERO, M.C_WALL, 0.0, {"outline": 0.05})
	_frames = 0

var _frames := 0
func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 10:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("D:/休闲小岛幻境/开发产物/shots/probe_roof.png")
		print("[PROBE] saved ", img.get_width(), "x", img.get_height())
		get_tree().quit()
