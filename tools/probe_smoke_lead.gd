extends SceneTree
## Lead 诊断：在真实 isle.tscn 场景中检查炊烟的时钟/粒子状态（headless，仅逻辑与状态，不评估像素）

func _initialize() -> void:
	await process_frame
	var scene: PackedScene = load("res://isle.tscn")
	if scene == null:
		print("[SMOKE] load fail"); quit(1); return
	var main: Node = scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var menu: Variant = main.get("_menu")
	if menu != null and menu.has_method("instant_finish"):
		menu.call("instant_finish")
	main.set("_mode", 1)
	main.set("_time_source", "sim")
	main.set("_realtime", false)
	main.set("_started", true)
	main.set("_paused", false)
	main.set("_auto_orbit", false)
	main.set("_blending", "")
	main.set("_settings", main.call("get_settings"))
	var st: Dictionary = main.get("_settings")
	st["time_source"] = "sim"
	main.call("_apply_user_settings", false)
	main.call("_set_time_of_day", 12.0 * 60.0 + 10.0)
	for i in range(60):
		await process_frame
	var fx: Variant = main.get("_fx")
	var smoke: Variant = fx.get("smoke") if fx is Dictionary else null
	print("[SMOKE] is_dict=", smoke is Dictionary)
	if smoke is Dictionary:
		var ctl: Variant = smoke.get("ctl")
		var p: GPUParticles3D = smoke.get("node")
		var mat: StandardMaterial3D = smoke.get("mat")
		if ctl != null:
			print("[SMOKE] debug=", ctl.call("smoke_debug"))
		if p != null:
			print("[SMOKE] emitting=", p.emitting, " ratio=", p.amount_ratio, " amount=", p.amount, " visible=", p.visible, " gpos=", p.global_position, " lifetime=", p.lifetime, " preprocess=", p.preprocess, " draw=", p.draw_pass_1)
			print("[SMOKE] ctrl gpos=", p.get_parent().global_position, " parent=", p.get_parent().name, " parent_parent=", p.get_parent().get_parent().name if p.get_parent().get_parent()!=null else "null")
		if mat != null:
			print("[SMOKE] mat unshaded=", mat.shading_mode, " transp=", mat.transparency, " billboard=", mat.billboard_mode, " albedo=", mat.albedo_color, " tex=", mat.albedo_texture, " vcol=", mat.vertex_color_use_as_albedo)
	var cam: Camera3D = main.get("_cam")
	print("[SMOKE] cam=", cam.global_position if cam != null else "null", " sim=", main.get("_sim_seconds"))
	# 边界测试：state 直接由统一 sim 时钟驱动
	var boundaries := [10.0*60+59, 11.0*60+0, 11.0*60+2, 12.0*60+59, 13.0*60+0, 16.0*60+59, 17.0*60+0, 17.0*60+2, 18.0*60+59, 19.0*60+0, 23.0*60+0, 0.0]
	if smoke is Dictionary and smoke.get("ctl") != null:
		var ctl2: Variant = smoke.get("ctl")
		for m in boundaries:
			main.call("_set_time_of_day", float(m))
			await process_frame
			await process_frame
			var dbg: Dictionary = ctl2.call("smoke_debug")
			print("[EDGE] ", IsleFx.smoke_time_label(float(m)*60.0), " in_win=", dbg["active_window"], " emitting=", dbg["emitting"], " ratio=", snappedf(float(dbg["ratio"]),0.01), " created=", dbg["created_count"])
	quit(0)
