extends Node3D
const M := preload("res://scripts/isle_math.gd")
func _ready() -> void:
	var names := ["g_sun_color","g_sun_dir_view","g_moon_color","g_moon_dir_view","g_ambient_sky","g_ambient_ground","g_fog_color","g_fog_near","g_fog_far","g_wind_time","g_outline_color"]
	for n in names:
		RenderingServer.global_shader_parameter_add(n, RenderingServer.GLOBAL_VAR_TYPE_VEC4 if n.ends_with("color") else (RenderingServer.GLOBAL_VAR_TYPE_FLOAT if n in ["g_fog_near","g_fog_far","g_wind_time"] else RenderingServer.GLOBAL_VAR_TYPE_VEC3), null)
	RenderingServer.global_shader_parameter_set("g_sun_color", Color("fff3d8"))
	RenderingServer.global_shader_parameter_set("g_sun_dir_view", Vector3(0.2, 0.7, 0.4).normalized())
	RenderingServer.global_shader_parameter_set("g_moon_color", Color("8faeff"))
	RenderingServer.global_shader_parameter_set("g_moon_dir_view", Vector3(-0.5,-0.5,0.2).normalized())
	RenderingServer.global_shader_parameter_set("g_ambient_sky", Color("8fd0ec"))
	RenderingServer.global_shader_parameter_set("g_ambient_ground", Color("65724f"))
	RenderingServer.global_shader_parameter_set("g_fog_color", Color("b2e0ea"))
	RenderingServer.global_shader_parameter_set("g_fog_near", 5000.0)
	RenderingServer.global_shader_parameter_set("g_fog_far", 9000.0)
	RenderingServer.global_shader_parameter_set("g_wind_time", 0.0)
	RenderingServer.global_shader_parameter_set("g_outline_color", Color(0.12, 0.13, 0.17))
	var we := WorldEnvironment.new(); var env := Environment.new()
	env.background_mode = Environment.BG_COLOR; env.background_color = Color(0.02,0.03,0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env; add_child(we)
	var cam := Camera3D.new(); cam.fov = 40.0
	cam.look_at_from_position(Vector3(0,4.0,16.0), Vector3(0,1.6,0), Vector3.UP); add_child(cam)
	# row A: prisms. row B: boxes
	var xs := [-3.6, 0.0, 3.6]
	var opts_list := [{}, {"outline": 0.06}]
	for i in range(3):
		var outline: float = 0.06 if i >= 1 else 0.0
		M.prism(self, 2.4, 1.5, 2.4, Vector3(xs[i], 0.0, 0.0), M.C_TERRACOTTA, 0.0, {"outline": outline})
		M.box(self, Vector3(2.4, 1.5, 2.4), Vector3(xs[i], 1.9, 0.0), M.C_TERRACOTTA, 0.0, {"outline": outline})
	_frames = 0
var _frames := 0
func _process(_d: float) -> void:
	_frames += 1
	if _frames == 10:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("D:/休闲小岛幻境/开发产物/shots/probe_outline.png")
		print("[PROBE] saved")
		get_tree().quit()
