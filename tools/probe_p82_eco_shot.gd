extends SceneTree
# ============================================================
# P8.2-04 冬季裸枝/栖点近景截图探针（同机位 before/after）
# 用法（窗口模式，不要 --headless）：
#   bash run_godot.sh --path <工程> --resolution 1600x900 \
#     --script res://tools/probe_p82_eco_shot.gd -- --tag=before|after
# before 用冻结基线副本（ddcde3a）的拷贝，after 用当前工作树；
# 两 build 的固定机位常量完全相同（PERCH4_W/PERCH4_N），便于并排比对。
# 鸟必须是自然停栖（最多等 WAIT_PERCH_FRAMES 帧），禁止 debug_force_perch。
# 输出：D:/休闲小岛幻境/开发产物/p82/04_winter/shots/
# ============================================================

const OUT_DIR := "D:/休闲小岛幻境/开发产物/p82/04_winter/shots"
# 修复后的 winter_branch_4 世界坐标/法线（两 build 固定机位共用，不随 build 变化）
const PERCH4_W := Vector3(-11.807, 15.583, 6.735)
const PERCH4_N := Vector3(0.164, 0.926, -0.339)
# 侧视方向：与 facing 水平投影 (-0.436,0,0.900) 垂直的水平向量
const SIDE := Vector3(0.900, 0.0, 0.436)
const WAIT_PERCH_FRAMES := 12000   # 200s @60fps：冬季 5 个裸枝点权重占比 41.5%，单点约 8%/次降落
const WAIT_ANY_WINTER_FRAMES := 6000
const CAM_SIDE_DIST := 4.0
const CAM_UP := 1.4
const CAM_FOV := 38.0

var _main: Node = null
var _fx: Object = null
var _tag := "after"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--tag="):
			_tag = String(a).substr(6)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	print("[SHOT] begin tag=%s out=%s viewport=%s" % [_tag, OUT_DIR, str(root.get_viewport().get_visible_rect().size)])
	var ps: PackedScene = load("res://isle.tscn") as PackedScene
	if ps == null:
		print("[SHOT] FAIL cannot load isle.tscn")
		quit(1)
		return
	_main = ps.instantiate()
	root.add_child(_main)
	if not await _wait_nodes():
		print("[SHOT] FAIL main not ready")
		quit(1)
		return
	# 与 P8.1 截图例程一致的初始化（进 PLAYING、暂停模拟时钟、隐藏 HUD/菜单）
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
	if _fx == null:
		print("[SHOT] FAIL _birds null")
		quit(1)
		return
	print("[SHOT] perch_stats=", str(_fx.call("debug_perch_stats")))
	var perches: Array = _fx.get("_perches")
	var actual_w := Vector3.ZERO
	var actual_n := Vector3.UP
	for p_v in perches:
		var p: Dictionary = p_v
		if String(p["id"]) == "winter_branch_4":
			actual_w = p["pos"]
			actual_n = p["normal"]
	print("[SHOT] PERCH4 actual_world=%s actual_normal=%s fixed_const=%s" % [str(actual_w), str(actual_n), str(PERCH4_W)])
	# ---- 等海鸥自然停到 winter_branch_4（禁止强制） ----
	var landed := false
	var frames := 0
	while frames < WAIT_PERCH_FRAMES:
		await process_frame
		frames += 1
		var snap: Array = _fx.call("debug_snapshot")
		for s_v in snap:
			var s: Dictionary = s_v
			if int(s["state"]) == 3 and String(s["perch_id"]) == "winter_branch_4":
				landed = true
				print("[SHOT] landed bird=%d slot=%d pos=%s after_frames=%d" % [
					int(s["index"]), int(s["perch_slot"]), str(s["pos"]), frames])
				break
		if landed:
			break
	print("[SHOT] wait_landing landed=%s frames=%d (%.1fs @60fps)" % [str(landed), frames, float(frames) / 60.0])
	if landed:
		print("[SHOT] snapshot_after_landing=", str(_fx.call("debug_snapshot")))
	# A) 固定机位（两 build 完全同一 from/target/fov）
	await _cam_shot("p82_04_perch4_fixed_" + _tag,
		PERCH4_W + SIDE * CAM_SIDE_DIST + Vector3(0.0, CAM_UP, 0.0),
		PERCH4_W + PERCH4_N * 0.14, CAM_FOV)
	# B) 实际栖点机位（以当前 build 内真实 winter_branch_4 为准）
	await _cam_shot("p82_04_perch4_actual_" + _tag,
		actual_w + SIDE * CAM_SIDE_DIST + Vector3(0.0, CAM_UP, 0.0),
		actual_w + actual_n * 0.14, CAM_FOV)
	# B2) 若 200s 内没有自然停到 winter_branch_4：退而在任意冬季裸枝点拍到“鸟脚站在裸枝上”，
	#     用于“裸枝直径 / 脚掌跨度”比例判定（仍然禁止 debug_force_perch）。
	if not landed:
		var got_any := await _wait_any_winter(WAIT_ANY_WINTER_FRAMES)
		if not got_any.is_empty():
			var aw: Vector3 = got_any["pos"]
			var an: Vector3 = got_any["normal"]
			print("[SHOT] fallback_any_winter pid=%s pos=%s radius=%.3f ratio=%.2f" % [
				String(got_any["id"]), str(aw), float(got_any["radius"]), float(got_any["radius"]) * 2.0 / 0.114])
			await _cam_shot("p82_04_perch_any_" + _tag,
				aw + SIDE * 2.6 + Vector3(0.0, 1.0, 0.0),
				aw + an * 0.10, 36.0)
	# C) 冬季裸枝整体近景（等同 P8.1 _p8_camera_tree_close 机位）
	_main.call("_p8_camera_tree_close")
	await _frames(8)
	await _save("p82_04_winter_bare_close_" + _tag)
	# D) 冬季裸枝广角（等同 P8.1 _p8_camera_tree 机位）
	_main.call("_p8_camera_tree")
	await _frames(8)
	await _save("p82_04_winter_bare_wide_" + _tag)
	print("[SHOT] done tag=%s" % _tag)
	quit(0)

## 等待任意冬季裸枝点出现自然停栖；返回 {id,pos,normal,radius} 或空字典。
func _wait_any_winter(max_frames: int) -> Dictionary:
	var frames := 0
	while frames < max_frames:
		await process_frame
		frames += 1
		for s_v in _fx.call("debug_snapshot"):
			var s: Dictionary = s_v
			var pid := String(s["perch_id"])
			if int(s["state"]) == 3 and pid.begins_with("winter_branch"):
				var p: Dictionary = {}
				for p_v in _fx.call("get_perches"):
					var pp: Dictionary = p_v
					if String(pp["id"]) == pid:
						p = pp
				if not p.is_empty():
					print("[SHOT] any_winter pid=%s frames=%d" % [pid, frames])
					return {"id": pid, "pos": p["pos"], "normal": p["normal"], "radius": float(p["radius"])}
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

func _cam_shot(name: String, from: Vector3, target: Vector3, fov: float) -> void:
	_main.call("_pose_look", from, target, fov)
	await _frames(6)
	var cam: Camera3D = _main.get("_cam")
	if cam != null:
		print("[SHOT] cam %s want=%s got=%s target=%s fov=%.1f" % [
			name, str(from), str(cam.global_position), str(target), fov])
	await _save(name)

func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png(OUT_DIR + "/" + name + ".png")
	print("[SHOT] saved %s %dx%d" % [name, img.get_width(), img.get_height()])
