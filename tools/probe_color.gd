extends Node3D

const M := preload("res://scripts/isle_math.gd")

func _ready() -> void:
	var names := ["g_sun_color","g_sun_dir_view","g_moon_color","g_moon_dir_view","g_ambient_sky","g_ambient_ground","g_fog_color","g_fog_near","g_fog_far","g_wind_time","g_outline_color"]
	for n in names:
		RenderingServer.global_shader_parameter_add(n, RenderingServer.GLOBAL_VAR_TYPE_VEC4 if n.ends_with("color") else (RenderingServer.GLOBAL_VAR_TYPE_FLOAT if n in ["g_fog_near","g_fog_far","g_wind_time"] else RenderingServer.GLOBAL_VAR_TYPE_VEC3), null)
	RenderingServer.global_shader_parameter_set("g_sun_color", Color(1.0, 0.95, 0.85))
	RenderingServer.global_shader_parameter_set("g_sun_dir_view", Vector3(0.3, 0.7, 0.65).normalized())
	RenderingServer.global_shader_parameter_set("g_moon_color", Color(0.2, 0.25, 0.4))
	RenderingServer.global_shader_parameter_set("g_moon_dir_view", Vector3(-0.5, -0.5, 0.2).normalized())
	RenderingServer.global_shader_parameter_set("g_ambient_sky", Color("8fd0ec"))
	RenderingServer.global_shader_parameter_set("g_ambient_ground", Color("65724f"))
	RenderingServer.global_shader_parameter_set("g_fog_color", Color("b2e0ea"))
	RenderingServer.global_shader_parameter_set("g_fog_near", 400.0)
	RenderingServer.global_shader_parameter_set("g_fog_far", 900.0)
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
	cam.fov = 45.0
	cam.position = Vector3(0.0, 3.0, 13.0)
	cam.look_at_from_position(Vector3(0.0, 3.0, 13.0), Vector3(0.0, 1.2, 0.0), Vector3.UP)
	add_child(cam)

	var items := [
		{"p": Vector3(-7.5, 0, 0), "kind": "prism", "color": M.C_TERRACOTTA, "outline": 0.0},
		{"p": Vector3(-4.5, 0, 0), "kind": "prism", "color": M.C_TERRACOTTA, "outline": 0.06},
		{"p": Vector3(-1.5, 0, 0), "kind": "box", "color": M.C_TERRACOTTA, "outline": 0.0},
		{"p": Vector3(1.5, 0, 0), "kind": "prism", "color": M.C_GRASS, "outline": 0.0},
		{"p": Vector3(4.5, 0, 0), "kind": "prism", "color": M.C_WALL, "outline": 0.0},
		{"p": Vector3(7.5, 0, 0), "kind": "prism", "color": M.C_ROCK, "outline": 0.0},
	]
	for it in items:
		var opts := {}
		if float(it["outline"]) > 0.0:
			opts["outline"] = float(it["outline"])
		if it["kind"] == "prism":
			M.prism(self, 2.2, 1.4, 2.2, it["p"], it["color"], 0.0, opts)
		else:
			M.box(self, Vector3(2.2, 1.4, 2.2), it["p"] + Vector3(0, 0.7, 0), it["color"], 0.0, opts)
	# self-lit control boxes
	var sl := [
		{"p": Vector3(-7.5, 0, -3.2), "c": M.C_TERRACOTTA},
		{"p": Vector3(-4.5, 0, -3.2), "c": M.C_GRASS},
		{"p": Vector3(-1.5, 0, -3.2), "c": M.C_WALL},
	]
	for it in sl:
		M.box(self, Vector3(2.2, 1.4, 0.2), it["p"] + Vector3(0, 0.7, 0), it["c"], 0.0, {"self_lit": true, "glow": 1.0})
	_frames = 0

var _frames := 0
func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 10:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("D:/休闲小岛幻境/开发产物/shots/probe_color.png")
		print("[PROBE] saved ", img.get_width(), "x", img.get_height())
		get_tree().quit()
