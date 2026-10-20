extends SceneTree
## task-8 附：PostAO 后处理开销 A/B（窗口模式）
## 用法: <godot_console.exe> --path 游戏工程 --script res://tools/probe_ao_perf.gd -- --window
## 同一机位/画质档下只切 PostAO 节点 visible，测 fps/frame_ms 差 = 自定义 AO 的 GPU 开销。

const MAIN_SCENE := "res://isle.tscn"

func _initialize() -> void:
	if not ("--window" in OS.get_cmdline_user_args()):
		print("[ao_perf] headless: 仅语法自检")
		quit(0)
		return
	var scene: PackedScene = load(MAIN_SCENE)
	var m: Variant = scene.instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	await process_frame
	var menu: Variant = m.get("_menu")
	if menu is CanvasLayer:
		(menu as CanvasLayer).visible = false
	var hud: Variant = m.get("_hud")
	if hud != null and hud.has_method("set_hud_visible"):
		hud.call("set_hud_visible", false, false)
	m.set("_mode", 1)
	m.set("_auto_orbit", false)
	m.set("_time_source", "sim")
	m.set("_realtime", false)
	m.set("_paused", true)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	m.set_process(false)
	await process_frame
	var cam: Camera3D = m.get("_cam")
	var vp: Viewport = m.get_viewport()
	var mi: MeshInstance3D = m.get("_post_ao_mi")
	var mat: ShaderMaterial = m.get("_post_ao_mat")
	var env: Environment = m.get("_env")
	m.call("_set_time_of_day", 12.0 * 60.0 + 20.0)
	m.set("_theta", 0.74)
	m.set("_elev", 0.28)
	m.set("_radius", 82.0)
	m.set("_fov", 42.0)
	m.call("_apply_pose", m.call("_play_pose"))
	print("  [AO-PERF] viewport=%s render_scale=%.2f msaa=%d ao_samples=%s ao_radius=%s" % [str(vp.get_visible_rect().size), float(vp.scaling_3d_scale), int(vp.msaa_3d), str(mat.get_shader_parameter("ao_samples")), str(mat.get_shader_parameter("ao_radius"))])
	for q in [2, 3, 4]:
		var st: Variant = m.get("_settings")
		if st is Dictionary:
			(st as Dictionary)["quality"] = q
			(st as Dictionary)["quality_overrides"] = {}
		m.call("_apply_quality", q)
		m.call("_update_lighting")
		if env != null:
			env.glow_enabled = true
		m.call("_apply_pose", m.call("_play_pose"))
		# AO 关
		mi.visible = false
		for _i in range(24):
			await process_frame
		var off := await _measure(30)
		# AO 开（档位真实参数）
		mi.visible = true
		for _i in range(24):
			await process_frame
		var on := await _measure(30)
		print("  [AO-PERF] q%d ao_off=%.1ffps/%.2fms  ao_on=%.1ffps/%.2fms  开销=%.2fms (%.1f%%)" % [q, off, 1000.0 / maxf(off, 0.001), on, 1000.0 / maxf(on, 0.001), 1000.0 / maxf(on, 0.001) - 1000.0 / maxf(off, 0.001), 100.0 * (1000.0 / maxf(on, 0.001)) / maxf(1000.0 / maxf(off, 0.001), 0.001) - 100.0])
	print("  [AO-PERF] done")
	quit(0)

func _measure(frames: int) -> float:
	var t0 := Time.get_ticks_usec()
	for _i in range(frames):
		await process_frame
	var dt := float(Time.get_ticks_usec() - t0) / 1000000.0
	return float(frames) / maxf(dt, 1e-6)
