extends SceneTree

## T5 临时探针：headless 实例化主场景，检查不同时刻海鸥停栖分布（哪些鸟在 cottage 屋顶），
## 用于给窗口截图选时机/机位。输出：bird idx、state、perch_id、kind、脚-面间隙。
const EXE_HINT := "headless"

func _initialize() -> void:
	await process_frame
	var scene: PackedScene = load("res://isle.tscn")
	if scene == null:
		print("[ROOF] isle.tscn 加载失败")
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
	await _report(main, 10.0 * 60.0 + 3.0, 300)
	await _report(main, 22.0 * 60.0 + 10.0, 400)
	await _report(main, 19.0 * 60.0 + 20.0, 400)
	quit(0)

func _report(main: Node, minutes: float, frames: int) -> void:
	main.call("_set_time_of_day", minutes)
	for i in range(frames):
		await process_frame
	var birds: Variant = main.get("_birds")
	var arr: Array = birds.get("_birds") if birds != null else []
	var sm: Variant = main.get("_settings")
	var sun: Variant = main.get("_sun_alt")
	print("=== t=", "%02d:%02d" % [int(minutes) / 60, int(minutes) % 60], " sun_alt=", sun, " birds=", arr.size())
	var cottage: Variant = main.get("_cottage")
	var perches: Array = cottage.get("perches") if cottage is Dictionary else []
	var by_id := {}
	for p in perches:
		by_id[String(p.get("id", ""))] = p
	var roof_birds := 0
	for i in range(arr.size()):
		var b: Dictionary = arr[i]
		var st := int(b.get("state", -1))
		var pid := String(b.get("perch_id", ""))
		var node: Node3D = b.get("node")
		var kind := ""
		var gap := -999.0
		if by_id.has(pid):
			var p: Dictionary = by_id[pid]
			kind = String(p.get("kind", ""))
			var n: Vector3 = p.get("normal", Vector3.UP)
			var foot: Vector3 = (p.get("pos") as Vector3) + n * 0.02
			gap = node.position.distance_to(foot)
			roof_birds += 1
		print("  bird", i, " state=", st, " pos=", node.position, " perch=", pid, " kind=", kind, " foot_gap=", snapped(gap, 0.001))
	print("[ROOF] cottage-roof perched birds=", roof_birds, " / ", arr.size())
