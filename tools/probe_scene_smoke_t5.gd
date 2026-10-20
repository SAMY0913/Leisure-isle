extends SceneTree

## T5 集成诊断：窗口渲染下实例化 isle.tscn，摆 06_smoke_noon / 06_bird_roof 机位并截图，
## 核对炊烟在真实游戏场景中是否可见、海鸥是否停栖在屋顶。
const OUT := "D:/休闲小岛幻境/开发产物/shots6/t5/"

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	await process_frame
	var scene: PackedScene = load("res://isle.tscn")
	if scene == null:
		print("[GAME ISO] isle.tscn 加载失败")
		quit(1)
		return
	var main: Node = scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var menu: Variant = main.get("_menu")
	if menu != null and menu.has_method("instant_finish"):
		menu.call("instant_finish")
	main.set("_mode", 1)  # Mode.PLAYING
	# 设置里的 time_source 可能持久化为 real（之前自测切过现实时间），强制回 sim 才能让 _set_time_of_day 生效
	main.set("_time_source", "sim")
	main.set("_realtime", false)
	main.set("_started", true)
	main.set("_paused", false)
	main.set("_auto_orbit", false)
	main.set("_blending", "")
	var pp: Variant = main.call("_play_pose")
	main.call("_apply_pose", pp)
	main.call("_set_time_of_day", 12.0 * 60.0 + 10.0)
	await process_frame
	main.call("_pose_look", Vector3(-2.69, 14.5, 14.0), Vector3(-2.69, 18.1, -3.76), 34.0)
	await process_frame
	await process_frame
	var fx0: Variant = main.get("_fx")
	var sm0: Variant = fx0.get("smoke") if fx0 is Dictionary else null
	var ctl0: Variant = sm0.get("ctl") if sm0 is Dictionary else null
	if ctl0 != null:
		print("[GAME ISO] early debug=", ctl0.call("smoke_debug"))
	# 给烟雾 1 秒 ramp + 5 秒生命周期的预填充时间（3.5s）
	for i in range(210):
		await process_frame
	var fx: Variant = main.get("_fx")
	var smoke: Variant = fx.get("smoke") if fx is Dictionary else null
	var ctl: Variant = smoke.get("ctl") if smoke is Dictionary else null
	var p: GPUParticles3D = smoke.get("node") if smoke is Dictionary else null
	if ctl != null:
		print("[GAME ISO] debug=", ctl.call("smoke_debug"))
	if p != null:
		print("[GAME ISO] emitting=", p.emitting, " ratio=", p.amount_ratio, " amount=", p.amount, " visible=", p.visible, " gpos=", p.global_position, " aabb=", p.visibility_aabb)
	var cam: Camera3D = main.get("_cam")
	if cam != null:
		print("[GAME ISO] cam gpos=", cam.global_position, " fov=", cam.fov)
	print("[GAME ISO] now_sim=", main.call("_now_sim_seconds"))
	await _grab("game_smoke_probe.png")
	# 近景对准烟囱顶
	main.call("_pose_look", Vector3(-1.0, 19.6, 6.2), Vector3(-0.85, 18.4, -3.0), 30.0)
	for i in range(90):
		await process_frame
	await _grab("game_smoke_probe_close.png")
	# 诊断：同场景内新增标记球 + 新烟发射器，判断是“这个发射器实例”问题还是“场景粒子渲染”问题
	var diag_holder := Node3D.new()
	diag_holder.name = "T5Diag"
	main.add_child(diag_holder)
	var marker := MeshInstance3D.new()
	var sms := SphereMesh.new()
	sms.radius = 0.8
	sms.height = 1.6
	marker.mesh = sms
	var mmat := StandardMaterial3D.new()
	mmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mmat.albedo_color = Color(1, 0, 1)
	mmat.no_depth_test = true
	marker.material_override = mmat
	marker.position = Vector3(-2.69 + 2.0, 18.32 + 1.2, -3.76)
	diag_holder.add_child(marker)
	var fx_script: GDScript = load("res://scripts/fx.gd") as GDScript
	var s2: Dictionary = fx_script.smoke(diag_holder, Vector3(-2.69 + 3.6, 18.32 + 0.4, -3.76))
	var ctl2: Variant = s2.get("ctl", null)
	if ctl2 != null:
		ctl2.call("set_sim_seconds", 12.0 * 3600.0 + 600.0)
	print("[GAME ISO] diag marker visible=", marker.is_visible_in_tree(), " fresh smoke=", s2.get("node", null))
	if p != null:
		print("[GAME ISO] draw_pass_1=", p.draw_pass_1, " mesh_mat=", (p.draw_pass_1 as Mesh).material if p.draw_pass_1 is Mesh else null)
		p.restart()
	# 变体测试：普通球形 draw pass 的 GPU 粒子 / CPU 粒子，判断是否全部粒子都不渲染
	var gp2 := GPUParticles3D.new()
	gp2.amount = 24
	gp2.lifetime = 3.0
	gp2.preprocess = 1.0
	gp2.emitting = true
	gp2.position = Vector3(-2.69, 18.32 + 2.2, -3.76)
	var pm2 := ParticleProcessMaterial.new()
	pm2.direction = Vector3(0, 1, 0)
	pm2.spread = 10.0
	pm2.initial_velocity_min = 0.3
	pm2.initial_velocity_max = 0.6
	gp2.process_material = pm2
	var sm2 := SphereMesh.new()
	sm2.radius = 0.25
	sm2.height = 0.5
	gp2.draw_pass_1 = sm2
	diag_holder.add_child(gp2)
	var cp := CPUParticles3D.new()
	cp.amount = 24
	cp.lifetime = 3.0
	cp.emitting = true
	cp.position = Vector3(-2.69 - 2.2, 18.32 + 2.2, -3.76)
	cp.direction = Vector3(0, 1, 0)
	cp.spread = 10.0
	cp.initial_velocity_min = 0.3
	cp.initial_velocity_max = 0.6
	var sm3 := SphereMesh.new()
	sm3.radius = 0.25
	sm3.height = 0.5
	cp.mesh = sm3
	diag_holder.add_child(cp)
	var ao_mi: Variant = main.get("_post_ao_mi")
	print("[GAME ISO] variant gp2_visible=", gp2.is_visible_in_tree(), " cp_visible=", cp.is_visible_in_tree(), " tree_paused=", paused, " frames=", Engine.get_frames_drawn(), " ao_visible=", (ao_mi.visible if ao_mi is Node3D else "n/a"))
	for i in range(150):
		await process_frame
	print("[GAME ISO] variants after: gp2=", gp2, " cp=", cp, " frames=", Engine.get_frames_drawn())
	if ao_mi is Node3D:
		(ao_mi as Node3D).visible = false
		print("[GAME ISO] AO disabled for test")
	for i in range(60):
		await process_frame
	await _grab("game_smoke_no_ao.png")
	main.call("_apply_quality", 0)
	for i in range(60):
		await process_frame
	await _grab("game_smoke_low.png")
	print("[GAME ISO] quality after low=", (main.get("_settings") as Dictionary).get("quality", -1), " ao_visible=", (ao_mi.visible if ao_mi is Node3D else "n/a"))
	if ctl2 != null:
		print("[GAME ISO] diag2 debug=", ctl2.call("smoke_debug"))
	await _grab("game_smoke_marker.png")
	# 鸟屋顶镜头 10:00
	main.call("_set_time_of_day", 10.0 * 60.0 + 3.0)
	main.call("_pose_look", Vector3(4.5, 20.5, 3.0), Vector3(-0.11, 18.05, -3.54), 26.0)
	for i in range(90):
		await process_frame
	await _grab("game_bird_roof_probe.png")
	quit(0)
func _grab(file_name: String) -> void:
	await process_frame
	await process_frame
	var tex: ViewportTexture = root.get_texture()
	if tex == null:
		print("[GAME ISO] grab FAILED (no viewport texture): ", file_name)
		return
	var img: Image = tex.get_image()
	if img == null:
		print("[GAME ISO] grab FAILED (null image): ", file_name)
		return
	var err: int = img.save_png(OUT + file_name)
	print("[GAME ISO] grab ", file_name, " err=", err, " size=", img.get_width(), "x", img.get_height())