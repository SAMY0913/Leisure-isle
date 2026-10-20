extends SceneTree

## T5 窗口截图探针：真实渲染下拍
##  A) 06_smoke_noon 同机位 12:10 炊烟柱（shot A/B 两种取景）
##  B) 22:10 夜间屋顶海鸥近景，选一只在 cottage 屋顶瓦面上的鸟，镜头对准脚-瓦接触处
const OUT := "D:/休闲小岛幻境/开发产物/shots6/t5/"

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	await process_frame
	var scene: PackedScene = load("res://isle.tscn")
	if scene == null:
		print("[SHOT] isle.tscn 加载失败")
		quit(1)
		return
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
	main.call("_apply_pose", main.call("_play_pose"))

	# ---------- A) 06 机位 12:10 炊烟 ----------
	main.call("_set_time_of_day", 12.0 * 60.0 + 10.0)
	main.call("_pose_look", Vector3(-2.69, 14.5, 14.0), Vector3(-2.69, 18.1, -3.76), 34.0)
	for i in range(420):
		await process_frame
	_dump_smoke(main)
	await _grab("06_smoke_noon_t5.png")
	# 稍近的烟柱取景（同轴拉近）
	main.call("_pose_look", Vector3(-2.69, 15.4, 9.0), Vector3(-2.69, 18.6, -3.76), 30.0)
	for i in range(120):
		await process_frame
	_dump_smoke(main)
	await _grab("06_smoke_noon_close_t5.png")

	# ---------- B) 黄昏 + 夜间 瓦面海鸥近景（只选 ridge/eave/chimney，排除门廊梁） ----------
	main.call("_set_time_of_day", 19.0 * 60.0 + 20.0)
	for i in range(300):
		await process_frame
	var roof := _roof_bird(main)
	if roof.is_empty():
		print("[SHOT] 19:20 无瓦面停栖鸟，改拍屋顶广角")
		main.call("_pose_look", Vector3(4.5, 21.0, 6.0), Vector3(-0.5, 17.9, -2.0), 34.0)
		for i in range(60):
			await process_frame
		await _grab("dusk_bird_roof_wide_t5.png")
	else:
		var bp: Vector3 = roof["pos"]
		print("[SHOT] roof bird=", roof["desc"])
		var out_dir: Vector3 = roof.get("out", Vector3(1, 0.5, 1)).normalized()
		main.call("_pose_look", bp + out_dir * 2.2 + Vector3(0, 1.0, 0), bp + Vector3(0, 0.10, 0), 30.0)
		for i in range(45):
			await process_frame
		await _grab("dusk_bird_roof_close_t5.png")
		main.call("_pose_look", bp + out_dir * 3.8 + Vector3(0, 1.6, 0), bp + Vector3(0, 0.20, 0), 34.0)
		for i in range(45):
			await process_frame
		await _grab("dusk_bird_roof_mid_t5.png")
	# 22:10 深夜：同一只瓦面鸟（脚-瓦接触近景）
	main.call("_set_time_of_day", 22.0 * 60.0 + 10.0)
	for i in range(180):
		await process_frame
	var roof2 := _roof_bird(main)
	if not roof2.is_empty():
		var bp2: Vector3 = roof2["pos"]
		var out2: Vector3 = roof2.get("out", Vector3(1, 0.5, 1)).normalized()
		print("[SHOT] 22:10 roof bird=", roof2["desc"])
		main.call("_pose_look", bp2 + out2 * 2.0 + Vector3(0, 0.95, 0), bp2 + Vector3(0, 0.10, 0), 30.0)
		for i in range(45):
			await process_frame
		await _grab("night_bird_roof_close_t5.png")
		main.call("_pose_look", bp2 + out2 * 3.6 + Vector3(0, 1.5, 0), bp2 + Vector3(0, 0.18, 0), 34.0)
		for i in range(45):
			await process_frame
		await _grab("night_bird_roof_mid_t5.png")
	else:
		main.call("_pose_look", Vector3(4.5, 21.0, 6.0), Vector3(-0.5, 17.9, -2.0), 34.0)
		for i in range(60):
			await process_frame
		await _grab("night_bird_roof_wide_t5.png")

	# ---------- C) 10:00 官方 06_bird_roof 机位：白天屋脊海鸥 ----------
	main.call("_set_time_of_day", 10.0 * 60.0)
	main.call("_pose_look", Vector3(4.5, 20.5, 3.0), Vector3(-0.11, 18.05, -3.54), 26.0)
	for i in range(180):
		await process_frame
	var ridge: Array = _ridge_birds(main)
	await _grab("06_bird_roof_t5.png")
	if not ridge.is_empty():
		var rp: Vector3 = ridge[0]["pos"]
		main.call("_pose_look", rp + Vector3(2.0, 0.75, 1.7), rp + Vector3(0.0, 0.05, 0.0), 30.0)
		for i in range(60):
			await process_frame
		await _grab("day_bird_ridge_close_t5.png")
	quit(0)

func _dump_smoke(main: Node) -> void:
	var fx: Variant = main.get("_fx")
	var smoke: Variant = fx.get("smoke") if fx is Dictionary else null
	var ctl: Variant = smoke.get("ctl") if smoke is Dictionary else null
	var p: GPUParticles3D = smoke.get("node") if smoke is Dictionary else null
	if ctl != null:
		print("[SHOT] smoke_debug=", ctl.call("smoke_debug"))
	if p != null:
		print("[SHOT] smoke emitting=", p.emitting, " ratio=", p.amount_ratio, " amount=", p.amount, " lifetime=", p.lifetime, " visible=", p.is_visible_in_tree())
	var ao: Variant = main.get("_post_ao_mi")
	print("[SHOT] ao_visible=", (ao.visible if ao is Node3D else "n/a"), " now_sim=", main.call("_now_sim_seconds"))

func _roof_bird(main: Node) -> Dictionary:
	var birds: Variant = main.get("_birds")
	var arr: Array = birds.get("_birds") if birds != null else []
	var cottage: Variant = main.get("_cottage")
	var perches: Array = cottage.get("perches") if cottage is Dictionary else []
	var by_id := {}
	for p in perches:
		by_id[String(p.get("id", ""))] = p
	var best: Dictionary = {}
	var best_d := 1e9
	var roof_count := 0
	for i in range(arr.size()):
		var b: Dictionary = arr[i]
		if int(b.get("state", -1)) != 3:
			continue
		var pid := String(b.get("perch_id", ""))
		if not by_id.has(pid):
			continue
		var p: Dictionary = by_id[pid]
		var kind := String(p.get("kind", ""))
		if kind != "ridge" and kind != "eave" and kind != "chimney":
			continue
		var node: Node3D = b.get("node")
		var n: Vector3 = p.get("normal", Vector3.UP)
		var foot: Vector3 = (p.get("pos") as Vector3) + n * 0.02
		var gap: float = node.position.distance_to(foot)
		roof_count += 1
		print("[SHOT] roof-perched bird", i, " perch=", pid, " kind=", kind, " pos=", node.position, " foot_gap=", snapped(gap, 0.0001), " normal=", n)
		# 相机外侧方向：沿法线向外 + 离开屋脊（烟囱/檐口取 x 外）
		var out: Vector3 = n
		out.y = 0.0
		if out.length_squared() < 0.01:
			# 屋脊/烟囱（法线朝上）：沿屋脊水平法线方向取景，避免镜头落在屋脊正上方
			out = Vector3(0.95, 0, -0.30)
		out = out.normalized() + Vector3(0.35, 0, 0.55)
		var d: float = (node.position - main.get("_cam").global_position).length()
		if d < best_d:
			best_d = d
			best = {"pos": node.position, "out": out, "desc": "bird%d %s kind=%s gap=%.4f" % [i, pid, kind, gap]}
	print("[SHOT] cottage roof perched count=", roof_count)
	return best

func _ridge_birds(main: Node) -> Array:
	var birds: Variant = main.get("_birds")
	var arr: Array = birds.get("_birds") if birds != null else []
	var cottage: Variant = main.get("_cottage")
	var perches: Array = cottage.get("perches") if cottage is Dictionary else []
	var ridge_ids := {}
	for p in perches:
		if String(p.get("kind", "")) == "ridge":
			ridge_ids[String(p.get("id", ""))] = true
	var out: Array = []
	for i in range(arr.size()):
		var b: Dictionary = arr[i]
		if int(b.get("state", -1)) != 3:
			continue
		var pid := String(b.get("perch_id", ""))
		var node: Node3D = b.get("node")
		var gap := -1.0
		for p in perches:
			if String(p.get("id", "")) == pid:
				gap = node.position.distance_to((p.get("pos") as Vector3) + (p.get("normal", Vector3.UP) as Vector3) * 0.02)
		print("[SHOT] perched bird", i, " perch=", pid, " kind=", ("ridge" if ridge_ids.has(pid) else "other"), " pos=", node.position, " foot_gap=", snappedf(gap, 0.0001))
		if ridge_ids.has(pid):
			out.append({"pos": node.position, "desc": "bird%d %s gap=%.4f" % [i, pid, gap]})
	print("[SHOT] ridge perched count=", out.size())
	return out

func _grab(file_name: String) -> void:
	await process_frame
	await process_frame
	var tex: ViewportTexture = root.get_texture()
	if tex == null:
		print("[SHOT] grab FAILED (no texture): ", file_name)
		return
	var img: Image = tex.get_image()
	if img == null:
		print("[SHOT] grab FAILED (null image): ", file_name)
		return
	var err: int = img.save_png(OUT + file_name)
	print("[SHOT] saved ", OUT + file_name, " err=", err, " ", img.get_width(), "x", img.get_height())
