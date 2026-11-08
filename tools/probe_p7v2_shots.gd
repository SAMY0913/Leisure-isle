extends SceneTree
## P7-V2 窗口真实渲染截图套件（task-4 / test-verify）
##
## 覆盖：
##   1) 道路+路灯：同机位 昼/黄昏/夜 × 画质 q0..q4（15 张，真实渲染，验证低/中档夜间道路可辨识、
##      六盏路灯局部光、无过曝光斑）
##   2) 海鸥待机动作近景（昼）：自然发生的 look_around / preen / shake / hop 各 1 张（2.5m 近景）
##   3) 海鸥夜间休息姿态近景（rest，头收拢；灯帽栖点）
##   4) 栖点视觉验收（perch-dev）：门廊栏杆 4 只、路灯灯帽 3 只
##   5) 烟囱禁停视觉证据：10:58:30（窗口前）→ 跳时入 11:00 烟窗瞬间（鸟被驱逐、烟雾 hold 无穿鸟）
##      → 11:00:32 后（鸟已离开、炊烟正常）
##   6) 自由视角：126m 全岛俯瞰（昼/夜）、海岸低空看周边海域、退出后轨道机位恢复
##   最后写 开发产物/p7v2/shots/suite/MANIFEST.md 清单（文件名→内容→尺寸→平均亮度）。
##
## 只做截图，不改正式运行规则；唯一"摆位"手段是 flock.debug_force_perch() 把鸟放到指定真实栖点
## （栖点数据来自 world/cottage build 的真实结果），用于构图与栖点视觉验收。
##
## 运行（必须真实窗口，headless 会直接退出 1）：
##   "D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe" --path "D:/休闲小岛幻境/游戏工程" --resolution 1600x900 --script res://tools/probe_p7v2_shots.gd

const SHOTS_DIR := "D:/休闲小岛幻境/开发产物/p7v2/shots/suite/"

var _main: Node = null
var _flock: Node = null
var _manifest: Array = []
var _idle_holder: Node3D = null

# ============================================================
# 启动 / 场景稳定态
# ============================================================
func _initialize() -> void:
	print("=== P7-V2 SHOTS START ===")
	if DisplayServer.get_name() == "headless":
		print("[P7V2S] SKIP headless：真实渲染截图必须在窗口模式运行")
		quit(1)
		return
	await process_frame
	var packed: PackedScene = load("res://isle.tscn") as PackedScene
	_main = packed.instantiate()
	get_root().add_child(_main)
	await process_frame
	await process_frame
	var menu = _main.get("_menu")
	if menu != null and menu.has_method("instant_finish"):
		menu.call("instant_finish")
	_main.set("_mode", 1)          # Mode.PLAYING
	_main.set("_time_source", "sim")
	_main.set("_realtime", false)
	_main.set("_started", true)
	_main.set("_paused", true)     # 冻结模拟时间；海鸥由 main._update_lighting 每帧实时驱动
	_main.set("_auto_orbit", false)
	_main.set("_blending", "")
	await process_frame
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await _settle(8)
	print("[P7V2S] window=", DisplayServer.window_get_size(), " root=", get_root().size)
	_flock = _main.get("_birds")
	_print_api()
	await _section_road()
	await _section_bird_idle()
	await _section_bird_night()
	await _section_perch_visual()
	await _section_chimney()
	await _section_flycam()
	_write_manifest()
	print("[P7V2S] RESULT shots=", _manifest.size(), " dir=", SHOTS_DIR)
	quit(0)

func _print_api() -> void:
	var need_main := ["_set_time_of_day", "_apply_quality", "_pose_look", "_update_lighting", "_enter_flycam", "_exit_flycam", "debug_light_state", "debug_flycam", "_p7_time_for_alt"]
	var miss: Array = []
	for m in need_main:
		if not _main.has_method(m):
			miss.append(m)
	print("[P7V2S] main API missing=", miss)
	if _flock == null:
		print("[P7V2S] WARN main._birds == null")
		return
	var need_flock := ["debug_snapshot", "debug_idle_state", "debug_perch_stats", "debug_force_perch", "debug_perch_availability"]
	var miss2: Array = []
	for m in need_flock:
		if not _flock.has_method(m):
			miss2.append(m)
	print("[P7V2S] flock API missing=", miss2)

# ============================================================
# 基础工具
# ============================================================
func _settle(n: int) -> void:
	for i in range(maxi(n, 0)):
		await process_frame

func _set_time(minutes: float) -> void:
	_main.call("_set_time_of_day", minutes)
	_main.call("_update_lighting")

func _pose(from: Vector3, target: Vector3, fov: float) -> void:
	_main.call("_pose_look", from, target, fov)

func _shot(shot_name: String, desc: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(SHOTS_DIR)
	var img: Image = _main.get_viewport().get_texture().get_image()
	var path := SHOTS_DIR + shot_name + ".png"
	var err := img.save_png(path)
	var lum := _mean_luma(img)
	_manifest.append({
		"name": shot_name + ".png",
		"desc": desc,
		"size": "%dx%d" % [img.get_width(), img.get_height()],
		"mean_luma": snappedf(lum, 0.001),
		"err": err,
	})
	print("[P7V2S] SHOT ", shot_name, " ", img.get_width(), "x", img.get_height(), " luma=", snappedf(lum, 0.001), " err=", err)
	await process_frame

func _mean_luma(img: Image) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var step := 16
	var sum := 0.0
	var n := 0
	for y in range(0, h, step):
		for x in range(0, w, step):
			var c := img.get_pixel(x, y)
			sum += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
	return sum / float(maxi(n, 1))

func _write_manifest() -> void:
	var path := SHOTS_DIR + "MANIFEST.md"
	DirAccess.make_dir_recursive_absolute(SHOTS_DIR)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("[P7V2S] ERROR 无法写清单 ", path)
		return
	f.store_line("# P7-V2 窗口截图清单（真实渲染，1600×900）")
	f.store_line("")
	f.store_line("- 生成时间：%s" % Time.get_datetime_string_from_system())
	f.store_line("- 运行命令：\"D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe\" --path \"D:/休闲小岛幻境/游戏工程\" --resolution 1600x900 --script res://tools/probe_p7v2_shots.gd")
	f.store_line("- 说明：镜头摆位只用于截图构图；鸟的栖点用 flock.debug_force_perch() 放到 world/cottage 真实栖点数据上，不改生态规则。")
	f.store_line("")
	f.store_line("| 文件 | 内容 | 尺寸 | 平均亮度 |")
	f.store_line("| --- | --- | --- | --- |")
	for m_v in _manifest:
		var m: Dictionary = m_v
		f.store_line("| %s | %s | %s | %.3f |" % [String(m["name"]), String(m["desc"]), String(m["size"]), float(m["mean_luma"])])
	f.close()
	print("[P7V2S] MANIFEST ", path, " entries=", _manifest.size())

# ============================================================
# flock 辅助
# ============================================================
func _perch_ids_by_kind(kind: String) -> Array:
	var out: Array = []
	var st: Dictionary = _flock.call("debug_perch_stats")
	for p_v in st.get("perches", []):
		var p: Dictionary = p_v
		if String(p["kind"]) == kind:
			out.append(String(p["id"]))
	return out

func _find_perch_id_by_kind(kind: String) -> String:
	var ids := _perch_ids_by_kind(kind)
	return String(ids[0]) if ids.size() > 0 else ""

func _find_free_perch_id(exclude: String = "") -> String:
	var st: Dictionary = _flock.call("debug_perch_stats")
	for p_v in st.get("perches", []):
		var p: Dictionary = p_v
		var pid := String(p["id"])
		if pid == exclude:
			continue
		if String(p["kind"]) == "chimney":
			continue
		if int(p["slots_free"]) > 0:
			return pid
	return ""

## 把 idx 鸟放到 pid 栖点；若被别的鸟占用，先把占用者挪到其他空闲真实栖点。
func _force_bird(idx: int, pid: String) -> bool:
	if _flock == null or pid == "":
		return false
	var snap: Array = _flock.call("debug_snapshot")
	for s_v in snap:
		var s: Dictionary = s_v
		if int(s["index"]) == idx:
			continue
		if String(s.get("perch_id", "")) != pid:
			continue
		var fb := _find_free_perch_id(pid)
		if fb == "":
			return false
		if not bool(_flock.call("debug_force_perch", int(s["index"]), fb)):
			return false
	return bool(_flock.call("debug_force_perch", idx, pid))

func _snap() -> Array:
	return _flock.call("debug_snapshot") if _flock != null else []

# ============================================================
# 1) 道路 + 路灯：昼/黄昏/夜 × 五档画质
# ============================================================
func _section_road() -> void:
	print("--- [ROAD] 道路/路灯 昼/黄昏/夜 × q0..q4 同机位 ---")
	var st: Dictionary = _main.call("debug_light_state")
	var lamps: Array = (st.get("lamp_positions", []) as Array).duplicate()
	if lamps.size() < 6:
		print("[P7V2S] WARN lamp_positions=", lamps.size(), " 跳过道路组")
		return
	var mid: Vector3 = (((lamps[0] as Vector3) + (lamps[1] as Vector3) + (lamps[2] as Vector3)) / 3.0)
	var ground := mid - Vector3(0.0, 1.98, 0.0)
	var from := ground + Vector3(7.2, 5.6, 10.0)
	var target := ground + Vector3(0.4, 0.9, 0.2)
	var dusk_sec := float(_main.call("_p7_time_for_alt", 3.5, true))
	var dusk_min := fposmod(dusk_sec, 86400.0) / 60.0
	print("[P7V2S] road camera ground=", ground, " dusk_minutes=", snappedf(dusk_min, 0.1))
	var phases: Array = [["day", 740.0], ["dusk", dusk_min], ["night", 1340.0]]
	for ph_v in phases:
		var ph: Array = ph_v
		for q in range(5):
			_main.call("_apply_quality", q)
			_set_time(float(ph[1]))
			_pose(from, target, 50.0)
			await _settle(14)
			await _shot("road_%s_q%d" % [String(ph[0]), q], "道路与六盏路灯 %s（画质 q%d，同机位）" % [String(ph[0]), q])

# ============================================================
# 2) 海鸥待机动作近景（昼，自然发生）
# ============================================================
func _section_bird_idle() -> void:
	print("--- [BIRD DAY] 待机动作近景（自然发生）---")
	if _flock == null:
		return
	_main.call("_apply_quality", 2)
	_set_time(740.0)
	await _settle(40)
	var wanted: Array = ["look_around", "preen", "shake", "hop"]
	var captured: Dictionary = {}
	var preferred: Array = ["lamp", "porch", "dock", "lighthouse", "garden"]
	for frame in range(3600):
		await process_frame
		var idle: Array = _flock.call("debug_idle_state")
		var snap: Array = _snap()
		var relaxed := frame > 1800
		for st_v in idle:
			var st: Dictionary = st_v
			var act := String(st["action"])
			if not wanted.has(act) or captured.has(act) or not bool(st["active"]):
				continue
			var dur := float(st["dur"])
			var t := float(st["t"])
			if dur <= 0.0 or t < dur * 0.18 or t > dur * 0.82:
				continue
			var idx := int(st["index"])
			var s: Dictionary = snap[idx]
			if int(s["state"]) != 3:
				continue
			var zone := String(s.get("perch_zone", ""))
			if zone == "roof":
				continue
			if not relaxed and not preferred.has(zone):
				continue
			var pos: Vector3 = s["pos"]
			var out := Vector3(pos.x, 0.0, pos.z)
			if out.length() < 0.1:
				out = Vector3(1.0, 0.0, 0.0)
			out = out.normalized()
			var from := pos + out * 2.5 + Vector3(0.0, 0.85, 0.0)
			_pose(from, pos + Vector3(0.0, 0.06, 0.0), 38.0)
			await _shot("bird_day_%s" % act, "白天自然发生的待机动作 %s 近景（2.5m，%s 区栖点）" % [act, zone])
			captured[act] = true
			break
		if captured.size() == wanted.size():
			break
	print("[P7V2S] day idle captured=", captured.keys())

# ============================================================
# 3) 夜间休息姿态近景
# ============================================================
func _section_bird_night() -> void:
	print("--- [BIRD NIGHT] 夜间休息姿态近景 ---")
	if _flock == null:
		return
	_set_time(1340.0)
	await _settle(90)
	# 把一只鸟安放到路灯灯帽，保证夜景近景清晰可辨识（真实 lamp 栖点）
	var lamp_pid := _find_perch_id_by_kind("lamp")
	var subject := -1
	if lamp_pid != "" and _force_bird(2, lamp_pid):
		subject = 2
	await _settle(12)
	var shots := 0
	for frame in range(1800):
		await process_frame
		var idle: Array = _flock.call("debug_idle_state")
		var snap: Array = _snap()
		for st_v in idle:
			var st: Dictionary = st_v
			if String(st["action"]) != "rest" or not bool(st["active"]):
				continue
			var dur := float(st["dur"])
			var t := float(st["t"])
			if dur <= 0.0 or t < dur * 0.25:
				continue
			var idx := int(st["index"])
			if subject >= 0 and idx != subject:
				continue
			var s: Dictionary = snap[idx]
			if int(s["state"]) != 3:
				continue
			var zone := String(s.get("perch_zone", ""))
			if zone == "roof":
				continue
			var pos: Vector3 = s["pos"]
			var out := Vector3(pos.x, 0.0, pos.z)
			if out.length() < 0.1:
				out = Vector3(1.0, 0.0, 0.0)
			out = out.normalized()
			var from := pos + out * 2.3 + Vector3(0.0, 0.75, 0.0)
			_pose(from, pos + Vector3(0.0, 0.05, 0.0), 38.0)
			await _shot("bird_night_rest_%d" % (shots + 1), "夜间海鸥休息姿态（头收拢）近景，%s 区栖点" % zone)
			shots += 1
			if shots >= 2:
				break
		if shots >= 2:
			break
	print("[P7V2S] night rest shots=", shots)

# ============================================================
# 4) 栖点视觉验收：门廊栏杆 / 路灯灯帽
# ============================================================
func _section_perch_visual() -> void:
	print("--- [PERCH] 门廊栏杆 / 路灯灯帽 栖点视觉验收 ---")
	if _flock == null:
		return
	_main.call("_apply_quality", 2)
	_set_time(740.0)
	await _settle(30)
	var porch_ids := _perch_ids_by_kind("porch_rail")
	if porch_ids.size() >= 4:
		var okc := 0
		for i in range(4):
			if _force_bird(i, String(porch_ids[i])):
				okc += 1
		await _settle(30)
		var positions: Array = []
		for s_v in _snap():
			var s: Dictionary = s_v
			if String(s.get("perch_zone", "")) == "porch":
				positions.append(s["pos"] as Vector3)
		if positions.size() >= 2:
			var mid := Vector3.ZERO
			for p_v in positions:
				mid += p_v as Vector3
			mid /= float(positions.size())
			# 前栏外法线：由门廊矩形走向推导（前栏沿 (0.955,0,-0.296)，外法线 = (0.296,0,0.955)）
			var a := Vector3(0.296, 0.0, 0.955).normalized()
			var from := mid + a * 6.6 + Vector3(0.0, 2.7, 0.0)
			_pose(from, mid + Vector3(0.0, 0.15, 0.0), 44.0)
			await _settle(22)
			await _shot("perch_porch_rail_group", "门廊栏杆 4 只海鸥（真实扶手顶面栖点，沿栏杆朝向；forced=%d/4）" % okc)
	# 三盏路灯灯帽栖点
	var lamp_ids := _perch_ids_by_kind("lamp")
	if lamp_ids.size() >= 3:
		var ok2 := 0
		for i in range(3):
			if _force_bird(5 + i, String(lamp_ids[i])):
				ok2 += 1
		await _settle(30)
		var lp: Array = []
		for s_v in _snap():
			var s: Dictionary = s_v
			if String(s.get("perch_zone", "")) == "lamp":
				lp.append(s["pos"] as Vector3)
		if lp.size() >= 1:
			var mid2 := Vector3.ZERO
			for p_v in lp:
				mid2 += p_v as Vector3
			mid2 /= float(lp.size())
			var from2 := mid2 + Vector3(6.0, 3.4, 8.5)
			_pose(from2, mid2 - Vector3(0.0, 0.4, 0.0), 48.0)
			await _settle(22)
			await _shot("perch_lamp_group", "路灯灯帽栖点上的海鸥（真实 lamp 栖点；forced=%d/3）" % ok2)

# ============================================================
# 5) 烟囱禁停前后视觉证据
# ============================================================
func _section_chimney() -> void:
	print("--- [CHIMNEY] 烟囱禁停前后（跳时进入烟窗瞬间 hold）---")
	if _flock == null:
		return
	var cid := _find_perch_id_by_kind("chimney")
	if cid == "":
		print("[P7V2S] WARN 未找到 chimney 栖点")
		return
	_main.call("_apply_quality", 2)
	_set_time(10.0 * 60.0 + 58.5)  # 10:58:30，窗口前
	await _settle(24)
	var forced := _force_bird(9, cid)
	await _settle(30)
	var snap: Array = _snap()
	var cpos := Vector3.ZERO
	for s_v in snap:
		var s: Dictionary = s_v
		if String(s.get("perch_id", "")) == cid and int(s["state"]) == 3:
			cpos = s["pos"] as Vector3
	if cpos == Vector3.ZERO:
		print("[P7V2S] WARN 未能把鸟放到烟囱（forced=", forced, "）")
		return
	var out := Vector3(cpos.x, 0.0, cpos.z)
	if out.length() < 0.1:
		out = Vector3(1.0, 0.0, 0.0)
	out = out.normalized()
	var from := cpos + out * 5.4 + Vector3(0.0, 2.5, 0.0)
	var target := cpos + Vector3(0.0, 0.35, 0.0)
	_pose(from, target, 38.0)
	await _settle(18)
	await _shot("chimney_1058_before", "10:58:30 鸟正常停栖烟囱、无烟（烟窗开始前）")
	var st_before: Dictionary = _flock.call("debug_perch_stats")
	# 直接跳时进入 11:00 烟窗
	_set_time(11.0 * 60.0 + 0.5)
	await process_frame
	var st_jump: Dictionary = _flock.call("debug_perch_stats")
	var smoke_emitting: Variant = _smoke_emitting()
	await _shot("chimney_1100_jump_early", "跳时进入 11:00 烟窗瞬间：鸟被驱逐起飞、烟雾被 hold 压下，无粒子穿鸟")
	print("[P7V2S] chimney jump hold=", snappedf(float(st_jump.get("smoke_hold", 0.0)), 0.01), " hold_count=", st_jump.get("smoke_hold_count", 0), " reason=", st_jump.get("hold_reason", ""), " evictions=", st_jump.get("chimney_evictions", 0), " (before=", st_before.get("chimney_evictions", 0), ") smoke_emitting=", smoke_emitting)
	# 烟雾 _ramp 依赖 set_sim_seconds 的 sim dt；_paused=true 时 sim 冻结→dt=0→ramp 停在 0。
	# 因此保持暂停，手工逐帧推进模拟时间（每帧 +0.1 游戏秒，仍在 11:00-13:00 烟窗内），
	# 读取 SmokeClock.debug_state() 的 emitting/ratio，达阈值后再截图（Lead 复核要求的证据口径）。
	var smoke_after: Variant = _smoke_emitting()
	var smoke_ratio := 0.0
	var smoke_frames := 0
	for i in range(240):
		_set_time(11.0 * 60.0 + 0.5 + float(i) * 0.1 / 60.0)
		await process_frame
		var st: Dictionary = _smoke_state()
		smoke_after = str(st.get("emitting", false))
		smoke_ratio = float(st.get("ratio", 0.0))
		smoke_frames = i + 1
		if smoke_after == "true" and smoke_ratio > 0.5:
			break
	var smoke_after_ok: bool = (smoke_after == "true" and smoke_ratio > 0.5)
	print("[P7V2S] chimney smoke after emitting=", smoke_after, " ratio=", snappedf(smoke_ratio, 0.001), " frames=", smoke_frames, " result=", "PASS" if smoke_after_ok else "FAIL")
	await _shot("chimney_1102_after", "烟窗内 11:0x 之后：鸟已离开烟囱、炊烟恢复冒出（同机位；sim 逐帧推进 %d 帧后截图）" % smoke_frames)
	print("[P7V2S] chimney after evictions=", (_flock.call("debug_perch_stats")).get("chimney_evictions", 0), " smoke_after_ok=", smoke_after_ok)

func _smoke_emitting() -> Variant:
	var st: Dictionary = _smoke_state()
	return st.get("emitting", "n/a")

func _smoke_state() -> Dictionary:
	var fx = _main.get("_fx")
	if not (fx is Dictionary):
		return {}
	var smoke = (fx as Dictionary).get("smoke", null)
	if not (smoke is Dictionary):
		return {}
	var ctl = (smoke as Dictionary).get("ctl", null)
	if ctl == null or not ctl.has_method("debug_state"):
		return {}
	var st = ctl.call("debug_state")
	return st as Dictionary

# ============================================================
# 6) 自由视角：全岛俯瞰 / 周边海域 / 退出恢复
# ============================================================
func _fly_pose(fc, cam: Camera3D, pos: Vector3, target: Vector3) -> void:
	var fwd := (target - pos).normalized()
	var pitch := asin(clampf(fwd.y, -1.0, 1.0))
	var yaw := atan2(-fwd.x, -fwd.z)
	fc.set("_pos", pos)
	fc.set("_yaw", yaw)
	fc.set("_pitch", pitch)
	fc.set("_vel", Vector3.ZERO)
	fc.call("apply_to", cam)

func _fly_shot(fc, cam: Camera3D, shot_name: String, desc: String, pos: Vector3, target: Vector3) -> void:
	_fly_pose(fc, cam, pos, target)
	await _settle(10)
	await _shot(shot_name, desc)

func _section_flycam() -> void:
	print("--- [FLYCAM] 自由视角全岛 / 海域 / 退出恢复 ---")
	if not _main.has_method("_enter_flycam") or not _main.has_method("debug_flycam"):
		print("[P7V2S] WARN main 未接入自由视角，跳过")
		return
	_set_time(740.0)
	_main.call("_apply_quality", 2)
	await _settle(12)
	var before: Dictionary = _main.call("debug_flycam")
	_main.call("_enter_flycam")
	var fc = _main.get("_flycam")
	var cam: Camera3D = _main.get("_cam")
	await _settle(3)
	await _fly_shot(fc, cam, "flycam_day_overview", "自由视角 126m 高空全岛俯瞰（含周边海域）", Vector3(0.0, 126.0, 110.0), Vector3(0.0, 5.0, 0.0))
	await _fly_shot(fc, cam, "flycam_day_coast", "自由视角海岸低空：全岛周边海域", Vector3(58.0, 42.0, 62.0), Vector3(10.0, 6.0, 10.0))
	_set_time(1340.0)
	await _settle(34)
	_fly_pose(fc, cam, Vector3(0.0, 126.0, 110.0), Vector3(0.0, 5.0, 0.0))
	await _settle(12)
	await _shot("flycam_night_overview", "自由视角夜景全岛俯瞰（含周边海域）")
	_main.call("_exit_flycam")
	var n := 0
	while bool(fc.get("active")) and n < 400:
		await process_frame
		n += 1
	await _settle(42)
	await _shot("flycam_exit_restored", "退出自由视角后自动运镜/轨道机位恢复（与进入前同机位）")
	var after: Dictionary = _main.call("debug_flycam")
	print("[P7V2S] flycam exit frames=", n)
	print("[P7V2S] flycam orbit before=", before.get("orbit", {}), " after=", after.get("orbit", {}))
