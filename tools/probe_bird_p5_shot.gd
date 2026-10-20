extends SceneTree
## 临时截图工具（P5 海鸥视觉验证）：直接打开主场景，固定正午，冻结时间后近距离多机位截图，
## 输出到 shots/p5_detail_*.png 与 shots/p5_wide_flight.png。仅用于验证，不属于游戏运行逻辑。
const SHOTS := "D:/休闲小岛幻境/开发产物/shots/"
var _main: Node
var _flock: Node

func _initialize() -> void:
	_run()

func _log(s: String) -> void:
	print("[DETAIL] ", s)

func _run() -> void:
	await process_frame
	var ps: PackedScene = load("res://isle.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	await process_frame
	_main.set("_auto_orbit", false)
	var menu_node = _main.get("_menu")
	if menu_node != null and menu_node.has_method("instant_finish"):
		menu_node.call("instant_finish")
	_main.set("_mode", 1)
	_main.set("_started", true)
	_main.set("_paused", false)
	_main.set("_blending", "")
	# 用户设置可能是“现实时间”，截图脚本强制切回模拟时间并固定到正午。
	_main.set("_time_source", "sim")
	_main.set("_realtime", false)
	_main.set("_day_length", 480.0)
	_main.call("_apply_pose", _main.call("_play_pose"))
	_main.call("_set_time_of_day", 12.0 * 60.0 + 20.0)
	_log("time_source=" + str(_main.get("_time_source")) + " sim=" + str(_main.get("_sim_seconds")))
	_flock = _main.get("_birds")
	for i in 6:
		await process_frame
	# 先冻结，再选鸟：白天初始约有 6 只在飞
	Engine.time_scale = 0.0
	_log("counts=" + str(_flock.call("get_state_counts")))
	var b := {}
	for b_v in (_flock.get("_birds") as Array):
		var cand: Dictionary = b_v
		if int(cand.get("state", -1)) == 0:
			var n = cand.get("node", null)
			if n is Node3D:
				b = cand
				break
	if b.is_empty():
		_log("no flying bird")
		quit(1)
		return
	var node: Node3D = b["node"]
	_log("bird pos=" + str(node.global_position) + " rot=" + str(node.rotation) + " wing=" + str(node.get_node("wing_l").rotation))
	var target: Vector3 = node.global_position + Vector3(0, 0.19, 0)
	await _aim_and_shot(node, {"fwd": 1.0, "right": 0.0, "r": 1.45, "elev": 0.10, "fov": 50.0}, target, "p5_detail_front")
	await _aim_and_shot(node, {"fwd": 0.0, "right": 1.0, "r": 1.45, "elev": 0.04, "fov": 50.0}, target, "p5_detail_side")
	await _aim_and_shot(node, {"fwd": 0.0, "right": 0.0, "r": 1.45, "elev": 1.35, "fov": 50.0}, target, "p5_detail_top")
	await _aim_and_shot(node, {"fwd": 0.85, "right": 0.55, "r": 1.5, "elev": 0.30, "fov": 50.0}, target, "p5_detail_quarter")
	# 环境全景（验证真实场景里也看不到悬浮板）
	await _aim_and_shot(node, {"fwd": 0.55, "right": 0.85, "r": 3.4, "elev": 0.30, "fov": 58.0}, target, "p5_wide_flight")
	var pb := {}
	for b_v in (_flock.get("_birds") as Array):
		var cand: Dictionary = b_v
		if int(cand.get("state", -1)) == 3:
			var n = cand.get("node", null)
			if n is Node3D:
				pb = cand
				break
	if not pb.is_empty():
		var pn: Node3D = pb["node"]
		_log("perch pos=" + str(pn.global_position) + " yaw=" + str(pn.rotation.y))
		await _perch_shot(pn, 0.62, 1.15, "p5_detail_perch_34")
		await _perch_shot(pn, PI * 0.5, 1.15, "p5_detail_perch_side")
		await _perch_shot(pn, 0.0, 1.15, "p5_detail_perch_front")
	else:
		_log("no perched bird")
	_log("done")
	quit(0)

func _aim_and_shot(node: Node3D, spec: Dictionary, target: Vector3, name: String) -> void:
	var fwd := node.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.001 else Vector3.FORWARD
	var right := node.global_basis.x
	right.y = 0.0
	right = right.normalized() if right.length() > 0.001 else Vector3.RIGHT
	var dir := fwd * float(spec["fwd"]) + right * float(spec["right"])
	if dir.length() < 0.01:
		dir = fwd
	dir = dir.normalized()
	_main.set("_theta", atan2(dir.x, dir.z))
	_main.set("_elev", float(spec["elev"]))
	_main.set("_radius", float(spec["r"]))
	_main.set("_cam_target", target)
	_main.set("_fov", float(spec["fov"]))
	for i in 4:
		await process_frame
	await _capture(name)

func _perch_shot(node: Node3D, yaw_off: float, radius: float, name: String) -> void:
	var d := node.rotation.y + yaw_off
	_main.set("_theta", d)
	_main.set("_elev", 0.12)
	_main.set("_radius", radius)
	_main.set("_cam_target", node.global_position + Vector3(0, 0.13, 0))
	_main.set("_fov", 46.0)
	for i in 4:
		await process_frame
	await _capture(name)

func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = _main.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(SHOTS)
	var path := SHOTS + name + ".png"
	var err := img.save_png(path)
	var cam = _main.get("_cam")
	var ct = _main.get("_cam_target")
	var cdist := -1.0
	if cam is Node3D and ct is Vector3:
		cdist = (cam as Node3D).global_position.distance_to(ct)
	_log("[SHOT] %s err=%d %dx%d dist=%.2f cam=%s target=%s" % [name, err, img.get_width(), img.get_height(), cdist, str((cam as Node3D).global_position) if cam is Node3D else "?", str(ct)])
	await process_frame