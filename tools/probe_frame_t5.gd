extends SceneTree

## T5 headless 取景验证（不渲染、不占窗口）：官方 06_bird_roof / 06_smoke_noon 机位下，
## 屋脊海鸥与炊烟发射器是否真的落在画面内，并估算烟柱屏幕高度。
## 运行：console.exe --headless --path 游戏工程 --script res://tools/probe_frame_t5.gd

var _pass := 0
var _fail := 0

func _initialize() -> void:
	await process_frame
	var scene: PackedScene = load("res://isle.tscn")
	if scene == null:
		print("[FRAME] isle.tscn 加载失败"); quit(1); return
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
	var vp_size: Vector2 = root.get_visible_rect().size
	print("[FRAME] viewport=", vp_size)

	# ---------- 10:00 官方 06_bird_roof 机位 ----------
	main.call("_set_time_of_day", 10.0 * 60.0)
	main.call("_pose_look", Vector3(4.5, 20.5, 3.0), Vector3(-0.11, 18.05, -3.54), 26.0)
	for i in range(150):
		await process_frame
	var cam: Camera3D = main.get("_cam")
	print("[FRAME] cam pos=", cam.global_position, " fov=", cam.fov)
	var birds: Variant = main.get("_birds")
	var arr: Array = birds.get("_birds") if birds != null else []
	var cottage: Variant = main.get("_cottage")
	var perches: Array = cottage.get("perches") if cottage is Dictionary else []
	var ridge_ids := {}
	for p in perches:
		if String(p.get("kind", "")) == "ridge":
			ridge_ids[String(p.get("id", ""))] = true
	var in_frame := 0
	var ridge_seen := 0
	for i in range(arr.size()):
		var b: Dictionary = arr[i]
		if int(b.get("state", -1)) != 3:
			continue
		var pid := String(b.get("perch_id", ""))
		if not ridge_ids.has(pid):
			continue
		ridge_seen += 1
		var node: Node3D = b.get("node")
		var center: Vector3 = node.position + node.basis.y * 0.22
		var behind: bool = cam.is_position_behind(center)
		var sp: Vector2 = cam.unproject_position(center)
		var inside: bool = (not behind) and sp.x >= 0.0 and sp.y >= 0.0 and sp.x <= vp_size.x and sp.y <= vp_size.y
		if inside:
			in_frame += 1
		print("  ridge bird %d perch=%s screen=(%.0f,%.0f) behind=%s inside=%s" % [i, pid, sp.x, sp.y, str(behind), str(inside)])
	_check(ridge_seen >= 3, "10:00 时屋脊停栖海鸥 %d 只（应 >=3）" % ridge_seen)
	_check(in_frame >= 2, "官方 06_bird_roof 画面内可见屋脊海鸥 %d 只（应 >=2）" % in_frame)

	# ---------- 12:10 官方 06_smoke_noon 机位 ----------
	main.call("_set_time_of_day", 12.0 * 60.0 + 10.0)
	main.call("_pose_look", Vector3(-2.69, 14.5, 14.0), Vector3(-2.69, 18.1, -3.76), 34.0)
	for i in range(200):
		await process_frame
	var fx: Variant = main.get("_fx")
	var smoke: Variant = fx.get("smoke") if fx is Dictionary else null
	var ctl: Variant = smoke.get("ctl") if smoke is Dictionary else null
	var p: GPUParticles3D = smoke.get("node") if smoke is Dictionary else null
	var ctl_pos: Vector3 = (ctl as Node3D).global_position if ctl is Node3D else Vector3.ZERO
	var behind2: bool = cam.is_position_behind(ctl_pos)
	var sp2: Vector2 = cam.unproject_position(ctl_pos)
	var dist: float = (ctl_pos - cam.global_position).length()
	var px_per_m: float = float(vp_size.y) / (2.0 * tan(deg_to_rad(cam.fov) * 0.5) * maxf(dist, 0.001))
	var plume_h_m: float = 5.5
	var plume_px: float = plume_h_m * px_per_m
	print("[FRAME] smoke emitter=", ctl_pos, " screen=", sp2, " behind=", behind2, " dist=", snappedf(dist, 0.01), " m")
	print("[FRAME] smoke px_per_m=", snappedf(px_per_m, 0.01), " estimate plume height=", snappedf(plume_px, 1.0), " px (world ", plume_h_m, " m)")
	if ctl != null:
		print("[FRAME] smoke_debug=", ctl.call("smoke_debug"))
	_check(not behind2 and sp2.x >= 0.0 and sp2.y >= 0.0 and sp2.x <= vp_size.x and sp2.y <= vp_size.y, "12:10 烟囱发射器在 06_smoke_noon 画面内 screen=(%.0f,%.0f)" % [sp2.x, sp2.y])
	_check(ctl != null and bool(ctl.call("smoke_debug")["emitting"]), "12:10 炊烟正在发射")
	_check(plume_px >= 80.0, "烟柱屏幕高度估算 %.0f px（应 >=80px，18m 外可见）" % plume_px)

	main.queue_free()
	print("=== T5 FRAME PROBE RESULT: ", "PASS" if _fail == 0 else "FAIL", " pass=", _pass, " fail=", _fail, " ===")
	quit(0 if _fail == 0 else 1)

func _check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("  [OK] ", msg)
	else:
		_fail += 1
		print("  [FAIL] ", msg)
