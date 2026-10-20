extends SceneTree

## T5 临时诊断：窗口渲染下截图炊烟粒子，隔离验证“发射状态正确但画面不可见”的疑点。
const Fx := preload("res://scripts/fx.gd")
const OUT_DIR := "D:/休闲小岛幻境/开发产物/shots6/t5/"

var _holder: Node3D
var _ctl: Variant
var _cam: Camera3D

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	await process_frame
	var world := Node3D.new()
	world.name = "DiagWorld"
	root.add_child(world)
	# 深色背景，白色烟雾对比明显
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.08, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.55, 0.7)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	# 一个深色盒子当作烟囱，烟从盒顶上方 0.4m 起
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.2, 2.0, 1.2)
	box.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.32, 0.3)
	box.material_override = mat
	box.position = Vector3(0, 1.0, 0)
	world.add_child(box)
	_holder = Node3D.new()
	world.add_child(_holder)
	var smoke: Dictionary = Fx.smoke(_holder, Vector3(0, 2.4, 0))
	_ctl = smoke.get("ctl", null)
	var p: GPUParticles3D = smoke.get("node", null)
	print("[ISO] ctl=", _ctl, " particles=", p)
	_cam = Camera3D.new()
	world.add_child(_cam)
	_cam.fov = 40.0
	world.add_child(Camera3D.new())
	# 近景机位：3.5m 外看向烟囱顶
	_cam.position = Vector3(0.0, 3.4, 4.2)
	_cam.look_at(Vector3(0, 3.6, 0))
	_cam.current = true
	if _ctl != null:
		_ctl.set_sim_seconds(12.0 * 3600.0 + 600.0)
	for i in range(180):
		await process_frame
	# 强制一帧渲染后抓取
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(OUT_DIR + "diag_smoke_iso_close.png")
	print("[ISO] close shot saved, particles emitting=", p.emitting, " ratio=", p.amount_ratio, " debug=", _ctl.smoke_debug() if _ctl != null else "null")
	# 远景机位：18m（接近游戏 06_smoke_noon 的距离与 FOV）
	_cam.position = Vector3(-2.69, 14.5, 14.0)
	_cam.look_at(Vector3(-2.69, 18.1, -3.76))
	_cam.fov = 34.0
	for i in range(40):
		await process_frame
	await RenderingServer.frame_post_draw
	var img2: Image = root.get_texture().get_image()
	img2.save_png(OUT_DIR + "diag_smoke_iso_far.png")
	print("[ISO] far shot saved")
	for i in range(120):
		await process_frame
	await RenderingServer.frame_post_draw
	var img3: Image = root.get_texture().get_image()
	img3.save_png(OUT_DIR + "diag_smoke_iso_far2.png")
	print("[ISO] far2 shot saved")
	quit(0)
