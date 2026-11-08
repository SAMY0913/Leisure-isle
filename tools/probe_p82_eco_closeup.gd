extends SceneTree
# ============================================================
# P8.2-04 冬季裸枝「鸟脚 / 裸枝比例」近视特写探针 v2（同机位多方位）
# 用法（窗口模式，不要 --headless）：
#   cd <工程> && bash run_godot.sh --path <工程> --script res://tools/probe_p82_eco_closeup.gd -- --tag=before|after
# v2 改动（相对 v1）：优先等鸟自然停到 winter_branch_4（修复点，最多 18000 帧），
#   并绕鸟拍 4 个方位 + 1 张 3m 上下文，避免单向机位被前向裸枝遮挡（v1 在 wb2 被挡）。
# 鸟必须自然停栖（不调用 debug_force_perch、不瞬移）。
# 输出：D:/休闲小岛幻境/开发产物/p82/04_winter/closeup/<tag>/
# ============================================================

const OUT_DIR := "D:/休闲小岛幻境/开发产物/p82/04_winter/closeup"
const WAIT_WB4_FRAMES := 18000     # ~300s @60fps
const WAIT_ANY_WINTER_FRAMES := 6000
# 与 winter_branch_4 facing 水平投影(-0.436,0,0.900) 垂直的水平向量
const SIDE := Vector3(0.900, 0.0, 0.436)
const AXIS := Vector3(-0.436, 0.0, 0.900)   # 枝轴水平投影

var _main: Node = null
var _fx: Object = null
var _tag := "after"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--tag="):
			_tag = String(a).substr(6)
	DirAccess.make_dir_recursive_absolute(OUT_DIR + "/" + _tag)
	print("[CLOSEUP] begin tag=%s viewport=%s" % [_tag, str(root.get_viewport().get_visible_rect().size)])
	var ps: PackedScene = load("res://isle.tscn") as PackedScene
	_main = ps.instantiate()
	root.add_child(_main)
	if not await _wait_nodes():
		print("[CLOSEUP] FAIL main not ready")
		quit(1)
		return
	_main.set("_mode", 1)
	_main.set("_started", true)
	_main.set("_paused", true)
	var menu = _main.get("_menu")
	if menu != null and menu.has_method("instant_finish"):
		menu.instant_finish()
	_main.set("_blending", "")
	var hud = _main.get("_hud")
	if hud != null and hud.has_method("set_hud_visible"):
		hud.set_hud_visible(false, false)
	_main.set("_auto_orbit", false)
	_main.set("_shot_beam_lock", false)
	_main.set("_time_source", "sim")
	await _frames(20)
	_main.call("_jump_datetime", 2027, 1, 15, 10, 0, 0)
	await _frames(150)
	_fx = _main.get("_birds")
	var want := "winter_branch_4"
	var target := await _wait_natural_perch(want, WAIT_WB4_FRAMES)
	if target.is_empty():
		print("[CLOSEUP] wb4 not used in %d frames, fallback any winter branch" % WAIT_WB4_FRAMES)
		target = await _wait_natural_perch("winter_branch", WAIT_ANY_WINTER_FRAMES)
		want = "any"
	if target.is_empty():
		print("[CLOSEUP] FAIL no natural winter-branch perch")
		quit(2)
		return
	# 停稳：LANDING 结束后先让姿态机过渡完，避免拍到翅膀未收/lerp 中间态
	await _frames(45)
	var bird_pos: Vector3 = target["bird_pos"]
	var n: Vector3 = target["normal"]
	print("[CLOSEUP] CHOSEN pid=%s want=%s bird_pos=%s normal=%s declared_radius=%.3f" % [
		String(target["id"]), want, str(bird_pos), str(n), float(target["radius"])])
	var prefix := "p82_04_feet_" + String(target["id"]) + "_" + _tag
	var dist := 2.4
	var up := 0.55
	await _cam_shot(prefix + "_side1.png", bird_pos + SIDE * dist + Vector3(0.0, up, 0.0), bird_pos + n * 0.06, 30.0)
	await _cam_shot(prefix + "_side2.png", bird_pos - SIDE * dist + Vector3(0.0, up, 0.0), bird_pos + n * 0.06, 30.0)
	await _cam_shot(prefix + "_axis1.png", bird_pos + AXIS * dist + Vector3(0.0, up, 0.0), bird_pos + n * 0.06, 30.0)
	await _cam_shot(prefix + "_axis2.png", bird_pos - AXIS * dist + Vector3(0.0, up, 0.0), bird_pos + n * 0.06, 30.0)
	await _cam_shot(prefix + "_context3m.png", bird_pos + SIDE * 3.0 + Vector3(0.0, 0.90, 0.0), bird_pos + n * 0.06, 36.0)
	print("[CLOSEUP] done tag=%s pid=%s" % [_tag, String(target["id"])])
	quit(0)

## 等待自然停栖；want=="winter_branch" 时匹配任意冬季裸枝点，否则精确匹配 id。
func _wait_natural_perch(want: String, max_frames: int) -> Dictionary:
	var frames := 0
	while frames < max_frames:
		await process_frame
		frames += 1
		for s_v in _fx.call("debug_snapshot"):
			var s: Dictionary = s_v
			var pid := String(s["perch_id"])
			if int(s["state"]) != 3:
				continue
			if want == "winter_branch":
				if not pid.begins_with("winter_branch"):
					continue
			elif pid != want:
				continue
			var p: Dictionary = {}
			for p_v in _fx.call("get_perches"):
				var pp: Dictionary = p_v
				if String(pp["id"]) == pid:
					p = pp
			if p.is_empty():
				continue
			print("[CLOSEUP] natural_perch pid=%s bird_pos=%s frames=%d" % [pid, str(s["pos"]), frames])
			return {"id": pid, "bird_pos": s["pos"], "normal": p["normal"], "radius": float(p["radius"])}
	return {}

func _frames(n: int) -> void:
	for i in range(n):
		await process_frame

func _wait_nodes() -> bool:
	for i in range(1800):
		await process_frame
		var birds = _main.get("_birds")
		var world = _main.get("_world")
		if birds != null and world is Dictionary and not (world as Dictionary).is_empty():
			return true
	return false

func _cam_shot(file_name: String, from: Vector3, target: Vector3, fov: float) -> void:
	_main.call("_pose_look", from, target, fov)
	await _frames(6)
	var cam: Camera3D = _main.get("_cam")
	if cam != null:
		print("[CLOSEUP] cam %s got=%s target=%s fov=%.1f dist=%.2f" % [
			file_name, str(cam.global_position), str(target), fov,
			cam.global_position.distance_to(target)])
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png(OUT_DIR + "/" + _tag + "/" + file_name)
	print("[CLOSEUP] saved %s %dx%d" % [file_name, img.get_width(), img.get_height()])
