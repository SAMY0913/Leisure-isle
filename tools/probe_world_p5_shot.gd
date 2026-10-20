extends SceneTree
## P5 windowed shots for the dock / street lamps / sailboat lanterns.
## Run: Godot --path D:/休闲小岛幻境/游戏工程 --resolution 1440x900 --script res://tools/probe_world_p5_shot.gd
## Loads the real main scene (res://isle.tscn) so lighting/sky/sea are the shipped ones,
## then drives main's own camera state (PLAYING pose, --shots style) and saves PNGs into
## D:/休闲小岛幻境/开发产物/shots/. It also prints the MultiMesh deck readback that headless
## dummy rendering cannot provide.

const SHOTS_DIR := "D:/休闲小岛幻境/开发产物/shots/"
const DECK := 0.72

var main: Node3D
var cam: Camera3D
var world: Dictionary = {}
var errors: Array = []

func _init() -> void:
	_run.call_deferred()

func _err(msg: String) -> void:
	errors.append(msg)
	print("[SHOT][ERR] ", msg)

func _frames(n: int) -> void:
	for i in range(n):
		await process_frame

func _shoot(name: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(SHOTS_DIR)
	var img: Image = get_root().get_texture().get_image()
	img.save_png(SHOTS_DIR + name + ".png")
	print("[SHOT] ", name, " ", img.get_width(), "x", img.get_height())
	await process_frame

func _time(minutes: float) -> void:
	main.call("_set_time_of_day", minutes)
	await _frames(3)

func _aim(from: Vector3, target: Vector3, fov: float) -> void:
	var off := from - target
	var flat := Vector2(off.x, off.z).length()
	main.set("_cam_target", target)
	main.set("_theta", atan2(off.x, off.z))
	main.set("_elev", atan2(off.y, flat))
	main.set("_radius", off.length())
	main.set("_fov", fov)
	await _frames(3)

func _run() -> void:
	var packed: PackedScene = load("res://isle.tscn")
	if packed == null:
		_err("isle.tscn failed to load")
		quit(3)
		return
	main = packed.instantiate() as Node3D
	get_root().add_child(main)
	await _frames(2)
	var tries := 0
	while tries < 1200:
		var wd = main.get("_world")
		if wd is Dictionary and not (wd as Dictionary).is_empty():
			world = wd as Dictionary
			break
		await process_frame
		tries += 1
	if world.is_empty():
		_err("world build timeout")
		quit(3)
		return
	print("[SHOT] world ready after ", tries, " frames; keys=", world.size())
	cam = main.get("_cam") as Camera3D
	if cam == null:
		_err("main camera missing")
	# The user settings may store the real-time clock source; force the sim clock so the
	# requested time of day (noon / 22:40) is stable regardless of the host clock.
	main.set("_time_source", "sim")
	main.set("_realtime", false)
	# Drive main into the shipped PLAYING look without the menu UI.
	main.set("_mode", 1)
	main.set("_started", true)
	main.set("_paused", false)
	main.set("_blending", "")
	main.set("_auto_orbit", false)
	var menu: Variant = main.get("_menu")
	if menu is CanvasLayer:
		(menu as CanvasLayer).visible = false
	var hud: Variant = main.get("_hud")
	if hud is CanvasLayer:
		(hud as CanvasLayer).visible = false
	await _frames(5)
	_read_dock_meshes()
	await _dock_shots()
	await _lamp_shots()
	await _boat_shots()
	print("[SHOT] done errors=", errors.size())
	quit(0 if errors.is_empty() else 3)

func _read_dock_meshes() -> void:
	var dock: Dictionary = world.get("dock", {})
	var node: Node3D = dock.get("node")
	var planks: MultiMeshInstance3D = null
	if node != null:
		planks = node.find_child("DockPlanks", true, false) as MultiMeshInstance3D
	if planks == null or planks.multimesh == null:
		_err("DockPlanks missing in windowed run")
		return
	var mm := planks.multimesh
	var n := mm.instance_count
	var sum := 0.0
	var sum2 := 0.0
	var ymin := 1.0e9
	var ymax := -1.0e9
	for i in range(n):
		var xf: Transform3D = planks.global_transform * mm.get_instance_transform(i)
		var up := (xf.basis * Vector3(0.0, 1.0, 0.0)).normalized()
		var top_y := xf.origin.y + up.y * 0.05
		sum += top_y
		sum2 += top_y * top_y
		ymin = minf(ymin, top_y)
		ymax = maxf(ymax, top_y)
	var mean := sum / float(n)
	var variance := sum2 / float(n) - mean * mean
	print("[SHOT][DECK] planks=%d mean_top_y=%.6f variance=%.9f min=%.6f max=%.6f" % [n, mean, variance, ymin, ymax])
	if absf(mean - DECK) > 0.005:
		_err("deck mean top y %.4f != %.2f" % [mean, DECK])
	if variance > 0.00025:
		_err("deck top variance %.8f too high" % variance)
	if ymax - ymin > 0.02:
		_err("deck top spread %.4f m" % (ymax - ymin))

func _dock_frame() -> Dictionary:
	var d := IsleMath.dock_dir()
	var s := IsleMath.dock_start()
	var axis := Vector3(d.x, 0.0, d.z).normalized()
	var side := Vector3(axis.z, 0.0, -axis.x)
	var centre := s + axis * 6.2
	centre.y = DECK
	return {"axis": axis, "side": side, "centre": centre}

func _dock_shots() -> void:
	var f := _dock_frame()
	var centre: Vector3 = f["centre"]
	var side: Vector3 = f["side"]
	var axis: Vector3 = f["axis"]
	await _time(12.0 * 60.0 + 18.0)
	_aim(centre + side * 13.0 + axis * 0.8 + Vector3(0.0, 1.05, 0.0), centre + Vector3(0.0, 0.10, 0.0), 46.0)
	await _shoot("p5_dock_level")
	_aim(centre + side * 8.5 - axis * 6.0 + Vector3(0.0, 6.4, 0.0), centre + Vector3(0.0, 0.15, 0.0), 52.0)
	await _shoot("p5_dock_oblique")
	_aim(centre + Vector3(0.0, 15.0, 2.5), centre + Vector3(0.0, -0.2, 0.0), 58.0)
	await _shoot("p5_dock_top")
	var shore := IsleMath.dock_start()
	_aim(shore + axis * 5.0 + Vector3(0.0, 1.5, 0.0), shore + axis * 1.0 + Vector3(0.0, 0.05, 0.0), 44.0)
	await _shoot("p5_dock_steps")

func _lamp_list() -> Array:
	var out: Array = []
	var lamps: Array = world.get("lamps", [])
	for entry in lamps:
		if entry is Array and (entry as Array).size() >= 4:
			var info: Dictionary = (entry as Array)[3]
			out.append(info)
	return out

func _lamp_shots() -> void:
	var infos := _lamp_list()
	print("[SHOT][LAMPS] count=", infos.size())
	if infos.size() < 5:
		_err("fewer than 5 lamps in windowed world")
	var sum := Vector3.ZERO
	for info in infos:
		var base: Vector3 = info["base"]
		sum += base
	var centre := sum / float(maxi(infos.size(), 1))
	centre.y = 2.0
	await _time(12.0 * 60.0 + 20.0)
	_aim(centre + Vector3(2.0, 30.0, 9.0), centre + Vector3(0.0, 0.0, 0.0), 60.0)
	await _shoot("p5_lamps_day_top")
	var mid := Vector3.ZERO
	var sidev := Vector3.ZERO
	if infos.size() >= 2:
		var a: Vector3 = infos[0]["base"]
		var b: Vector3 = infos[1]["base"]
		mid = (a + b) * 0.5
		var along := (b - a).normalized()
		sidev = Vector3(along.z, 0.0, -along.x)
		_aim(mid + sidev * 7.0 + Vector3(0.0, 2.3, 0.0), mid + Vector3(0.0, 2.4, 0.0), 55.0)
		await _shoot("p5_lamps_day_close")
	await _time(22.0 * 60.0 + 40.0)
	_aim(centre + Vector3(2.0, 30.0, 9.0), centre + Vector3(0.0, 0.0, 0.0), 60.0)
	await _shoot("p5_lamps_night_top")
	if infos.size() >= 2:
		_aim(mid + sidev * 7.0 + Vector3(0.0, 2.3, 0.0), mid + Vector3(0.0, 2.4, 0.0), 55.0)
		await _shoot("p5_lamps_night_close")
		# Arm direction evidence: 45 degrees off the road shoulder so the arm and its
		# lantern visibly point back at the road centre (the shoulder stands grass-side).
		await _time(10.0 * 60.0 + 20.0)
		var arm_info: Dictionary = infos[1]
		var arm_base: Vector3 = arm_info["base"]
		var arm_facing: Vector3 = arm_info["facing"]
		var arm_side := Vector3(arm_facing.z, 0.0, -arm_facing.x).normalized()
		_aim(arm_base + arm_facing * 4.0 - arm_side * 3.2 + Vector3(0.0, 2.1, 0.0), arm_base + Vector3(0.0, 2.35, 0.0), 48.0)
		await _shoot("p5_lamp_arm_day")

func _boat_shots() -> void:
	var boat: Node3D = world.get("sailboat")
	if boat == null:
		_err("sailboat missing")
		return
	# Pin the boat at its berth for the night beauty shots (same state main uses for --shots).
	main.set("_boat_state", "DOCKED")
	main.set("_sail_dwell", 9999.0)
	if main.has_method("_boat_dock_pose"):
		main.call("_boat_dock_pose", 1.0 / 60.0)
	if main.has_method("_apply_boat_fade"):
		main.call("_apply_boat_fade")
	await _frames(3)
	await _time(22.0 * 60.0 + 40.0)
	var lantern_local: Vector3 = world.get("sailboat_lantern_local_pos", Vector3.ZERO)
	var lantern_w := boat.to_global(lantern_local)
	var fwd := boat.global_transform.basis.z.normalized()
	var side := Vector3(fwd.z, 0.0, -fwd.x)
	var bp := boat.global_position
	print("[SHOT][BOAT] pos=(%.2f,%.2f,%.2f) lantern_world=(%.2f,%.2f,%.2f)" % [bp.x, bp.y, bp.z, lantern_w.x, lantern_w.y, lantern_w.z])
	var left := -boat.global_transform.basis.x.normalized()
	_aim(lantern_w + left * 2.6 - fwd * 1.2 + Vector3(0.0, 0.55, 0.0), lantern_w, 40.0)
	await _shoot("p5_boat_lantern_night")
	_aim(bp - fwd * 5.2 + left * 3.2 + Vector3(0.0, 1.7, 0.0), bp + Vector3(0.0, 1.2, 0.0), 46.0)
	await _shoot("p5_boat_night_side")
	# Force the bow search light on for a cone-shape verification image (runtime only).
	var spot: Node3D = world.get("sailboat_spot_node")
	if spot != null:
		spot.visible = true
		var lens_local: Vector3 = world.get("sailboat_spot_lens_pos", Vector3.ZERO)
		var lens_w := boat.to_global(lens_local)
		_aim(bp + side * 8.0 + fwd * 4.0 + Vector3(0.0, 2.6, 0.0), lens_w + fwd * 4.0 + Vector3(0.0, -0.6, 0.0), 55.0)
		await _shoot("p5_boat_spot_cone")
		spot.visible = false
	else:
		_err("sailboat_spot_node missing")
	var spot2: Node3D = world.get("sailboat_spot_node")
	print("[SHOT][BOAT] spot_visible_after=", str(spot2 != null and spot2.visible))
