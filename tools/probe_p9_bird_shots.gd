extends SceneTree
## P9 P7-FINALIZE 海鸥真实窗口取证探针（必须真实窗口，不能 --headless）
## 运行：ENG --path GAME --script res://tools/probe_p9_bird_shots.gd -- --out=DIR
## 覆盖：正式 isle.tscn 中停栖脚部近景、起飞序列、巡航、着陆序列、触地脚部近景。
## 只摆位/截图，不改玩法与生态规则。

const DEFAULT_OUT := "D:/休闲小岛幻境/开发产物/P9/P7-finalize/evidence/bird/window"
var out_dir := DEFAULT_OUT
var _main: Node = null
var _pass := 0
var _fail := 0
var _lines: Array = []
var _shots: Array = []
var _birds: Array = []

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var s: String = String(a)
		if s.begins_with("--out="):
			out_dir = s.substr(6).strip_edges().trim_suffix("/").trim_suffix("\\")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()

func _run() -> void:
	print("=== P9 bird window shots ===")
	await _boot()
	await _shots_run()
	_write_log()
	print("[SUMMARY] checks=%d fail=%d shots=%d" % [_pass + _fail, _fail, _shots.size()])
	print("[RESULT] %s" % ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)

func _check(name: String, ok: bool, expected: String, actual: String) -> void:
	var line := "[CHECK] %s | expected=%s actual=%s | %s" % [name, expected, actual, "PASS" if ok else "FAIL"]
	print(line)
	_lines.append(line)
	if ok:
		_pass += 1
	else:
		_fail += 1

func _frames(n: int) -> void:
	for i in range(n):
		await process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null or img.get_width() <= 0:
		_check("shot." + name, false, "non-empty PNG", "empty")
		return
	DirAccess.make_dir_recursive_absolute("%s/shots" % out_dir)
	var p := "%s/shots/%s.png" % [out_dir, name]
	var err := img.save_png(p)
	_check("shot." + name, err == OK, "save OK", str(err))
	if err == OK:
		_shots.append(p)
		print("[SHOT] %s %dx%d %s" % [name, img.get_width(), img.get_height(), p])

func _boot() -> void:
	var ps := load("res://isle.tscn") as PackedScene
	_main = ps.instantiate()
	root.add_child(_main)
	await _frames(8)
	var hud = _main.get("_hud")
	_main.set("_time_source", "sim")
	_main.set("_realtime", false)
	_main.set("_day_length", 86400.0)
	_main.call("_jump_datetime", 2026, 10, 24, 12, 0, 0)
	await _frames(2)
	_main.set("_paused", false)
	_main.set("_started", true)
	if _main.has_method("_enter_playing"):
		_main.call("_enter_playing")
	_main.set("_patrol_handled_day", int(floorf(float(_main.get("_sim_seconds")) / 86400.0)))
	_main.set("_mode", 1)
	_main.set_process(true)
	await _frames(30)
	var menu = _main.get("_menu")
	if menu != null and bool((menu as Node).get("visible")):
		(menu as Node).call("close")
		await _frames(60)
	if hud != null:
		hud.call("set_hud_visible", false, false)
	await _frames(6)
	var flock = _main.get("_birds")
	_birds = flock.get("_birds") as Array
	_check("boot.bird_count", _birds.size() == 10, "10", str(_birds.size()))
	# 冻结所有鸟的计时器，避免拍摄期间自然起降打断取景
	for b_v in _birds:
		var b: Dictionary = b_v
		b["timer"] = 9999.0
		b["idle_cool"] = 9999.0
	await _frames(3)

func _flock() -> Object:
	return _main.get("_birds")

func _bird_pos(idx: int) -> Vector3:
	var b: Dictionary = _birds[idx]
	return (b["node"] as Node3D).position

func _bird_state(idx: int) -> int:
	var b: Dictionary = _birds[idx]
	return int(b["state"])

func _step_until_state(idx: int, want: int, max_frames: int) -> int:
	var f := 0
	while _bird_state(idx) != want and f < max_frames:
		await process_frame
		f += 1
	return f

func _shots_run() -> void:
	var flock := _flock()
	# ---- 0) 栖点脚部契约数值（日志） ----
	for pid in ["porch_rail_L", "ridge_0", "lamp_1"]:
		var c: Dictionary = flock.call("debug_foot_contract", pid)
		if c.is_empty():
			continue
		print("[FOOT] %s kind=%s author_gap=%.4f foot_lift=%.4f support_gap=%.4f" % [
			pid, String(c["kind"]), float(c["author_gap"]), float(c["foot_lift"]), float(c["support_gap"])])
		_check("foot_contract." + pid, float(c["support_gap"]) >= 0.0 and float(c["support_gap"]) <= 0.005,
			"support_gap 0~0.005", "%.4f" % float(c["support_gap"]))

	# ---- 1) 停栖脚部近景（porch_rail_L） ----
	var placed := bool(flock.call("debug_force_perch", 0, "porch_rail_L"))
	if not placed:
		for pid_v in ["ridge_0", "lamp_1", "eave_L_-2.415"]:
			if bool(flock.call("debug_force_perch", 0, String(pid_v))):
				placed = true
				break
	_check("perch.stage", placed, "true", str(placed))
	await _frames(6)
	var ppos := _bird_pos(0)
	_main.call("_pose_look", ppos + Vector3(0.52, 0.22, 0.42), ppos + Vector3(0.0, 0.02, 0.0), 38.0)
	await _frames(8)
	await _shot("01_perch_feet_closeup_side")
	_main.call("_pose_look", ppos + Vector3(0.62, 0.30, 0.52), ppos + Vector3(0.0, 0.06, 0.0), 42.0)
	await _frames(6)
	await _shot("02_perch_feet_closeup_front")
	_main.call("_pose_look", ppos + Vector3(0.95, 0.38, 0.95), ppos + Vector3(0.0, 0.10, 0.0), 44.0)
	await _frames(6)
	await _shot("03_perch_full_body")

	# ---- 2) 起飞序列（同一机位连拍 >=4 帧） ----
	var pid_to := ""
	for pid_v2 in ["ridge_0", "porch_rail_L", "lamp_1", "eave_L_-2.415"]:
		if bool(flock.call("debug_force_perch", 1, String(pid_v2))):
			pid_to = String(pid_v2)
			break
	if pid_to == "":
		_check("takeoff.stage", false, "perch for takeoff", "none")
	else:
		await _frames(4)
		var tp := _bird_pos(1)
		_main.call("_pose_look", tp + Vector3(2.1, 0.75, 1.1), tp + Vector3(0.0, 0.55, 0.0), 52.0)
		await _frames(6)
		var ok_to := bool(flock.call("debug_force_takeoff", 1))
		_check("takeoff.force", ok_to, "true", str(ok_to))
		var frames_to: Array = [0, 4, 9, 15, 22, 32]
		var last_f := 0
		for fi in frames_to:
			await _frames(maxi(int(fi) - last_f, 1))
			last_f = int(fi)
			var st: int = _bird_state(1)
			print("[TO] frame=%d state=%d pos=%s" % [fi, st, str(_bird_pos(1))])
			await _shot("04_takeoff_%02d_f%02d" % [frames_to.find(fi), fi])

	# ---- 3) 巡航（跟拍） ----
	var fly_idx := -1
	for i in range(_birds.size()):
		if _bird_state(i) == 0:
			fly_idx = i
			break
	if fly_idx < 0:
		# 让 2 号鸟起飞并等待入 FLY
		var pid_fly := ""
		for pid_v3 in ["tree_0", "ridge_1", "lamp_2", "eave_R_2.415"]:
			if bool(flock.call("debug_force_perch", 2, String(pid_v3))):
				pid_fly = String(pid_v3)
				break
		if pid_fly != "":
			_check("cruise.stage", bool(flock.call("debug_force_takeoff", 2)), "takeoff started", "failed")
			fly_idx = 2
			await _step_until_state(2, 0, 300)
	if fly_idx >= 0:
		await _frames(20)
		var cp := _bird_pos(fly_idx)
		_main.call("_pose_look", cp + Vector3(2.6, 0.35, 1.4), cp, 48.0)
		await _frames(8)
		await _shot("05_cruise_side")
		var cp2 := _bird_pos(fly_idx)
		_main.call("_pose_look", cp2 + Vector3(1.4, 0.9, 2.4), cp2, 46.0)
		await _frames(6)
		await _shot("06_cruise_rear3q")
		_check("cruise.flying", _bird_state(fly_idx) == 0, "state FLY", str(_bird_state(fly_idx)))

	# ---- 4) 着陆序列（固定机位，>=4 帧） ----
	var land_idx := -1
	for i in range(_birds.size()):
		if _bird_state(i) == 0:
			land_idx = i
			break
	if land_idx < 0:
		# 从停栖状态直接强制降落（速度从 0 起，仍能拍到近地点展开/触地）
		land_idx = 3
	var target_pid := ""
	for pid_v4 in ["porch_rail_L", "ridge_0", "lamp_1", "eave_L_-2.415", "tree_0"]:
		var tp2: Dictionary = flock.call("debug_foot_contract", String(pid_v4))
		if tp2.is_empty():
			continue
		if bool(flock.call("debug_force_landing", land_idx, String(pid_v4))):
			target_pid = String(pid_v4)
			break
	_check("landing.force", target_pid != "", "free perch target", target_pid)
	if target_pid != "":
		var slot: Vector3 = (_birds[land_idx] as Dictionary)["to_p"]
		_main.call("_pose_look", slot + Vector3(1.6, 0.55, 1.0), slot + Vector3(0.0, 0.30, 0.0), 50.0)
		await _frames(6)
		var shots := 0
		var guard := 0
		var take_next := 0
		while shots < 6 and guard < 500:
			await process_frame
			guard += 1
			var st2: int = _bird_state(land_idx)
			if guard >= take_next:
				var m: Dictionary = {}
				var ms: Array = flock.call("debug_motion_state")
				for m_v in ms:
					var mm: Dictionary = m_v
					if int(mm["index"]) == land_idx:
						m = mm
						break
				print("[LAND] shot=%d frame=%d state=%d dist_hint=%.2f speed=%.2f flare=%.2f" % [
					shots, guard, st2, (_bird_pos(land_idx)).distance_to(slot), float(m.get("speed", 0.0)), float(m.get("flare", 0.0))])
				await _shot("07_landing_%02d_state%d" % [shots, st2])
				shots += 1
				take_next = guard + 6
			if st2 == 3 and shots >= 4:
				break
		_check("landing.shots", shots >= 4, ">=4", str(shots))
		# ---- 5) 触地脚部近景 ----
		await _frames(10)
		var bpos := _bird_pos(land_idx)
		_main.call("_pose_look", bpos + Vector3(0.72, 0.26, 0.56), bpos + Vector3(0.0, 0.01, 0.0), 40.0)
		await _frames(8)
		await _shot("08_touchdown_feet_closeup")
		_main.call("_pose_look", bpos + Vector3(1.05, 0.42, 1.05), bpos + Vector3(0.0, 0.10, 0.0), 46.0)
		await _frames(6)
		await _shot("09_touchdown_perch")

	# ---- 6) 整岛群飞环境对照 ----
	_main.call("_pose_look", Vector3(14.0, 22.0, 14.0), Vector3(0.0, 12.0, 0.0), 55.0)
	await _frames(10)
	await _shot("10_flock_context")

func _write_log() -> void:
	var f := FileAccess.open("%s/probe_p9_bird_shots.log" % out_dir, FileAccess.WRITE)
	if f != null:
		for line in _lines:
			f.store_line(String(line))
		f.close()
