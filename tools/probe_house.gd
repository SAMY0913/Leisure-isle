extends Node3D
## Isolated cottage render from the hero camera pose, with roof toggling, to debug roof appearance at low angles.

var _cam: Camera3D
var _out_dir: String = "D:/休闲小岛幻境/开发产物/shots/"

func _setup_globals() -> void:
	var lin := func(c: Color) -> Color: return c.srgb_to_linear()
	RenderingServer.global_shader_parameter_add("g_sun_color", RenderingServer.GLOBAL_VAR_TYPE_COLOR, lin.call(Color(1.0, 0.91, 0.78)) * 0.92)
	RenderingServer.global_shader_parameter_add("g_sun_dir_view", RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3(0, 0, -1))
	RenderingServer.global_shader_parameter_add("g_moon_color", RenderingServer.GLOBAL_VAR_TYPE_COLOR, lin.call(Color(0.56, 0.68, 0.91)) * 0.1)
	RenderingServer.global_shader_parameter_add("g_moon_dir_view", RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3(0, 0, -1))
	RenderingServer.global_shader_parameter_add("g_ambient_sky", RenderingServer.GLOBAL_VAR_TYPE_COLOR, lin.call(Color(0.65, 0.82, 0.90)) * 0.88)
	RenderingServer.global_shader_parameter_add("g_ambient_ground", RenderingServer.GLOBAL_VAR_TYPE_COLOR, lin.call(Color(0.40, 0.45, 0.31)) * 0.88)
	RenderingServer.global_shader_parameter_add("g_fog_color", RenderingServer.GLOBAL_VAR_TYPE_COLOR, lin.call(Color(0.82, 0.90, 0.89)))
	RenderingServer.global_shader_parameter_add("g_fog_near", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 110.0)
	RenderingServer.global_shader_parameter_add("g_fog_far", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 600.0)
	RenderingServer.global_shader_parameter_add("g_wind_time", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)
	RenderingServer.global_shader_parameter_add("g_outline_color", RenderingServer.GLOBAL_VAR_TYPE_COLOR, lin.call(Color(0.10, 0.13, 0.19)))

func _ready() -> void:
	_setup_globals()
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.80, 0.88)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.62, 0.70)
	env.ambient_light_energy = 1.0
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.02, deg_to_rad(245.0), 0.0)
	sun.light_energy = 1.6
	sun.light_color = Color(1.0, 0.93, 0.82)
	add_child(sun)
	IsleCottage.build(self)
	_cam = Camera3D.new()
	_cam.fov = 46.0
	_cam.near = 0.3
	_cam.far = 500.0
	add_child(_cam)
	_cam.current = true
	_pose(2.02, 0.13, 82.0, Vector3(0, 10, 0))
	await _shot("probe_house_a")
	for n in find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh != null and mi.mesh is ArrayMesh:
			mi.visible = false
	await _shot("probe_house_b")
	get_tree().quit()

func _pose(theta: float, elev: float, r: float, target: Vector3) -> void:
	var dir := Vector3(sin(theta) * cos(elev), sin(elev), cos(theta) * cos(elev))
	_cam.global_position = target + dir * r
	var look := (target - _cam.global_position).normalized()
	var right := Vector3.UP.cross(look).normalized()
	var up := look.cross(right).normalized()
	_cam.global_transform = Transform3D(Basis(right, up, -look), _cam.global_position)

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(_out_dir + name + ".png")
	print("[SHOT] ", name, " ", img.get_width(), "x", img.get_height())
