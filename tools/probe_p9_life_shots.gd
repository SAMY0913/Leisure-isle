extends SceneTree
## P9 / P7-FINALIZE 生活动作真实窗口连续帧证据（正式 isle.tscn，1600x900，真实渲染）。
##
## 覆盖：睡觉连续帧 ≥6、吃饭连续帧 ≥6、坐秋千 ≥3、码头观海 ≥3；
## 每帧记录状态/剪辑/角色坐标/屏幕投影/平均亮度，图片+日志写 evidence/life/window/。
##
## 运行（真实窗口，不能 headless）：
##   "D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe" --path "D:/休闲小岛幻境/游戏工程" \
##     --resolution 1600x900 --script res://tools/probe_p9_life_shots.gd

const OUT_DIR := "D:/休闲小岛幻境/开发产物/P9/P7-finalize/evidence/life/window/"
const W := 1600
const H := 900
const T_DAY := 660.0      # 11:00，室内外都亮
const T_EVENING := 1290.0 # 21:30，睡眠段夜景
var _main: Node = null
var _v: Node3D = null
var _model: Node3D = null
var _cam: Camera3D = null
var _cottage: Dictionary = {}
var _cr: Node3D = null
var _fails: Array = []
var _shots: Array = []

func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("[LIFESHOT] SKIP headless：真实窗口截图证据必须在窗口模式运行")
		quit(1)
		return
	_run()

func _run() -> void:
	var packed: PackedScene = load("res://isle.tscn") as PackedScene
	_main = packed.instantiate()
	get_root().add_child(_main)
	await process_frame
	await process_frame
	var menu: Node = _main.get("_menu") as Node
	if menu != null and menu.has_method("instant_finish"):
		menu.call("instant_finish")
	_main.set("_mode", 1)
	_main.set("_time_source", "sim")
	_main.set("_realtime", false)
	_main.set("_started", true)
	_main.set("_paused", false)
	_main.set("_auto_orbit", false)
	_main.set("_blending", "")
	_main.set("_day_length", 86400.0)
	_force_windowed()
	await _settle(14)
	_force_windowed()
	await _settle(4)
	var hud: Node = _main.get("_hud") as Node
	if hud != null and hud.has_method("set_hud_visible"):
		hud.call("set_hud_visible", false, false)
	_cam = _main.get("_cam") as Camera3D
	_v = _main.get("_villager") as Node3D
	_cottage = _main.get("_cottage") as Dictionary
	_cr = _cottage.get("root") as Node3D
	if _cam == null or _v == null or _cr == null:
		print("[LIFESHOT] FAIL 场景引用缺失")
		quit(1)
		return
	_model = _v.get("model_root") as Node3D
	_v.set("debug_log", false)
	_v.set("_last_sim", -1.0)
	print("[LIFESHOT] window=", DisplayServer.window_get_size(), " villager_spawn=", _f3(_v.global_position))
	var world: Dictionary = _main.get("_world")
	var swing: Node3D = world.get("swing", null) as Node3D
	var seat: Node3D = null
	if swing != null:
		seat = swing.find_child("SwingSeat", true, false) as Node3D
	var injected := false
	if swing != null and seat != null:
		injected = bool(_v.call("set_swing_target", swing, seat))
	print("[LIFESHOT] swing_target injected=", injected)
	_main.set("_paused", false)
	_set_time(T_DAY)

	await _stage_sleep()
	await _stage_eat()
	await _stage_swing()
	await _stage_sea_view()

	_write_manifest()
	print("[LIFESHOT] FAILS=", str(_fails))
	print("[LIFESHOT] RESULT shots=", _shots.size(), " fail=", _fails.size(), " out=", OUT_DIR)
	quit(0 if _fails.is_empty() else 1)

# ============================================================ 基础设施 =======
func _settle(n: int) -> void:
	for i in maxi(n, 0):
		await process_frame

func _force_windowed() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	DisplayServer.window_set_size(Vector2i(W, H))

func _set_time(minutes: float) -> void:
	_main.call("_set_time_of_day", minutes)
	_main.call("_update_lighting")

func _local(lp: Vector3) -> Vector3:
	return _cr.global_transform * lp

func _state() -> String:
	return String(_v.call("debug_state")["state"])

func _dbg() -> Dictionary:
	return _v.call("debug_state")

func _f3(v: Vector3) -> String:
	return "(%.2f,%.2f,%.2f)" % [v.x, v.y, v.z]

func _wait_state_multi(targets: Array, timeout_s: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(timeout_s * 1000.0):
		await process_frame
		if targets.has(_state()):
			return true
	return false

func _model_aabb() -> AABB:
	var out := AABB()
	var first := true
	for n in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.is_visible_in_tree() or mi.name == "Shadow":
			continue
		var bb := mi.mesh.get_aabb()
		var xf := mi.global_transform
		for ci in 8:
			var c := bb.position + Vector3(bb.size.x * float(ci & 1), bb.size.y * float((ci >> 1) & 1), bb.size.z * float((ci >> 2) & 1))
			var wp: Vector3 = xf * c
			if first:
				out = AABB(wp, Vector3.ZERO)
				first = false
			else:
				out = out.expand(wp)
	return out

func _joint(name: String) -> Vector3:
	var j: Variant = _model.call("get_joint", name)
	if j is Node3D:
		return (j as Node3D).global_position
	return _model_aabb().get_center()

func _mean_luma(img: Image) -> float:
	if img == null:
		return -1.0
	var acc := 0.0
	var n := 0
	for y in range(0, img.get_height(), 16):
		for x in range(0, img.get_width(), 16):
			var c := img.get_pixel(x, y)
			acc += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
	return acc / float(maxi(n, 1))

func _screen_uv(p: Vector3) -> Vector2i:
	var uv := _cam.unproject_position(p)
	return Vector2i(int(uv.x), int(uv.y))

## 连续帧抓拍：每 gap_frames 渲染帧抓一张，共 count 张。
func _series(prefix: String, desc: String, count: int, gap_frames: int,
		cam_fn: Callable, target_fn: Callable, fov: float) -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	for i in count:
		var cam: Vector3 = cam_fn.call()
		var tgt: Vector3 = target_fn.call()
		_main.call("_pose_look", cam, tgt, fov)
		await _settle(2)
		await RenderingServer.frame_post_draw
		var img: Image = _main.get_viewport().get_texture().get_image()
		var id := "%s_%02d" % [prefix, i]
		var path := OUT_DIR + id + ".png"
		var err := ERR_CANT_CREATE
		var iw := 0
		var ih := 0
		if img != null:
			err = img.save_png(path)
			iw = img.get_width()
			ih = img.get_height()
		var ds := _dbg()
		var uv := _screen_uv(tgt)
		var luma := _mean_luma(img)
		print("[LIFESHOT] SHOT ", id, " state=", String(ds["state"]), " clip=", String(ds["clip"]),
			" cp=%.2f" % float(ds["clip_pos"]), " pos=", _f3(_v.global_position),
			" bowl=", str(ds["bowl"]), " swing=", str(ds["swing"]["ride"]),
			" uv=", str(uv), " lum=", "%.3f" % luma, " err=", err, " size=", iw, "x", ih, " desc=", desc)
		if err != OK or iw != W or ih != H:
			_fails.append("save:" + id)
		if luma < 0.02:
			_fails.append("dark:" + id)
		_shots.append({
			"id": id, "file": id + ".png", "desc": desc,
			"state": String(ds["state"]), "clip": String(ds["clip"]),
			"clip_pos": float(ds["clip_pos"]), "villager_pos": [ _v.global_position.x, _v.global_position.y, _v.global_position.z ],
			"bowl": bool(ds["bowl"]), "swing_ride": bool(ds["swing"]["ride"]),
			"screen_uv": [uv.x, uv.y], "luma": luma, "err": err, "size": [iw, ih],
		})
		await _settle(gap_frames)

# ============================================================ A. 睡觉 ======
func _stage_sleep() -> void:
	print("[LIFESHOT] --- stage SLEEP ---")
	_v.call("clear_force")
	_set_time(T_EVENING)
	await _settle(6)
	var ok := bool(_v.call("force_bed"))
	print("[LIFESHOT] force_bed=", ok)
	if not ok:
		_fails.append("bed_plan")
		return
	# 机位：宽景从床尾侧上方看全身；近景从枕头上方俯视（避开床头板遮挡头/枕）
	var bed_cam := _local(Vector3(-0.30, 4.35, -1.90))
	var bed_close := _local(Vector3(-1.30, 4.55, -2.30))
	# 躺下过渡连续帧（搬腿 → 躺平）
	for i in 4:
		if _state() != "LIE_IN":
			await _wait_state_multi(["LIE_IN"], 40.0)
		await _settle(10)
		var bc := _model_aabb().get_center()
		_main.call("_pose_look", bed_cam, bc, 50.0)
		await _settle(2)
		await RenderingServer.frame_post_draw
		var img: Image = _main.get_viewport().get_texture().get_image()
		var id := "sleep_transition_%02d" % i
		img.save_png(OUT_DIR + id + ".png")
		print("[LIFESHOT] SHOT ", id, " state=", _state(), " clip=", String(_dbg()["clip"]), " cp=%.2f" % float(_dbg()["clip_pos"]))
		_shots.append({"id": id, "file": id + ".png", "desc": "躺下过渡（搬腿→躺平）", "state": _state(),
			"clip": String(_dbg()["clip"]), "clip_pos": float(_dbg()["clip_pos"]),
			"villager_pos": [_v.global_position.x, _v.global_position.y, _v.global_position.z],
			"bowl": bool(_dbg()["bowl"]), "swing_ride": false, "screen_uv": [0, 0], "luma": _mean_luma(img), "err": OK, "size": [img.get_width(), img.get_height()]})
	if not await _wait_state_multi(["SLEEP"], 60.0):
		_fails.append("sleep_state")
		return
	# 睡眠连续帧 ≥6（近景：头-枕 / 膝 / 床垫）
	await _series("sleep", "睡眠连续帧：头在枕上、双腿放平、呼吸循环", 6, 8,
		func() -> Vector3: return bed_close,
		func() -> Vector3: return _joint("head") + Vector3(0.0, -0.05, 0.0), 40.0)
	# 醒来过渡 2 帧
	_v.set("_hold_t", 999.0)
	await _wait_state_multi(["LIE_OUT", "BED_OUT"], 10.0)
	for i in 2:
		await _settle(8)
		var bc2 := _model_aabb().get_center()
		_main.call("_pose_look", bed_cam, bc2, 50.0)
		await _settle(2)
		await RenderingServer.frame_post_draw
		var img2: Image = _main.get_viewport().get_texture().get_image()
		var id2 := "wake_transition_%02d" % i
		img2.save_png(OUT_DIR + id2 + ".png")
		print("[LIFESHOT] SHOT ", id2, " state=", _state(), " clip=", String(_dbg()["clip"]))
		_shots.append({"id": id2, "file": id2 + ".png", "desc": "醒来（get_up → bed_sit_up）", "state": _state(),
			"clip": String(_dbg()["clip"]), "clip_pos": float(_dbg()["clip_pos"]),
			"villager_pos": [_v.global_position.x, _v.global_position.y, _v.global_position.z],
			"bowl": false, "swing_ride": false, "screen_uv": [0, 0], "luma": _mean_luma(img2), "err": OK, "size": [img2.get_width(), img2.get_height()]})
	await _wait_state_multi(["IDLE", "WALK"], 20.0)
	_set_time(T_DAY)
	await _settle(6)
	print("[LIFESHOT] SLEEP done state=", _state())

# ============================================================ B. 吃饭 ======
func _stage_eat() -> void:
	print("[LIFESHOT] --- stage EAT ---")
	_v.call("clear_force")
	_set_time(T_DAY)
	await _settle(6)
	var ok := bool(_v.call("force_eat", "eat_s"))
	print("[LIFESHOT] force_eat=", ok)
	if not ok:
		_fails.append("eat_plan")
		return
	if not await _wait_state_multi(["EAT"], 90.0):
		_fails.append("eat_state")
		return
	await _settle(6)
	# 机位：餐桌对面偏上方（越过对面椅背）看角色正面：脸/右手/碗/桌面关系
	var cam_fn := func() -> Vector3:
		return _local(Vector3(1.52, 1.92, 2.30))
	var tgt_fn := func() -> Vector3:
		return _joint("torso") + Vector3(0.0, 0.10, 0.0)
	await _series("eat", "进食连续帧：右手取食→送嘴→咀嚼（碗在桌上）", 7, 6, cam_fn, tgt_fn, 42.0)
	_v.call("clear_force")
	await _settle(4)
	print("[LIFESHOT] EAT done state=", _state())

# ============================================================ C. 秋千 ======
func _stage_swing() -> void:
	print("[LIFESHOT] --- stage SWING ---")
	_v.call("clear_force")
	_set_time(T_DAY)
	await _settle(6)
	var ok := bool(_v.call("force_swing"))
	print("[LIFESHOT] force_swing=", ok)
	if not ok:
		_fails.append("swing_plan")
		return
	if not await _wait_state_multi(["SIT"], 120.0):
		_fails.append("swing_state")
		return
	await _settle(20)
	var world: Dictionary = _main.get("_world")
	var pivot: Node3D = world.get("swing", null) as Node3D
	var cam_fn := func() -> Vector3:
		var seat := _v.global_position
		return seat + Vector3(2.6, 0.45, -2.2)
	var tgt_fn := func() -> Vector3:
		return _v.global_position + Vector3(0.0, 0.35, 0.0)
	await _series("swing", "坐秋千连续帧：真实吊点/座椅、身体随摆角同步、轻柔前后摆", 4, 20, cam_fn, tgt_fn, 40.0)
	print("[LIFESHOT] swing pivot_rot=", str(pivot.rotation) if pivot != null else "null",
		" villager_rot=", str(_v.rotation))
	_v.call("clear_force")
	await _settle(4)
	print("[LIFESHOT] SWING done state=", _state())

# ============================================================ D. 观海 ======
func _stage_sea_view() -> void:
	print("[LIFESHOT] --- stage SEA_VIEW ---")
	_v.call("clear_force")
	_set_time(T_DAY)
	await _settle(6)
	var ok := bool(_v.call("force_sea_view"))
	print("[LIFESHOT] force_sea_view=", ok)
	if not ok:
		_fails.append("sea_plan")
		return
	if not await _wait_state_multi(["IDLE"], 150.0):
		_fails.append("sea_state")
		return
	await _settle(12)
	var cam_fn := func() -> Vector3:
		var p := _v.global_position
		return p + Vector3(-2.4, 0.55, -1.6)
	var tgt_fn := func() -> Vector3:
		return _v.global_position + Vector3(0.0, 0.55, 0.0)
	await _series("sea_view", "码头观海连续帧：真实到达、面向海面、轻缓观察", 4, 15, cam_fn, tgt_fn, 40.0)
	var ds := _dbg()
	print("[LIFESHOT] sea state=", _state(), " clip=", String(ds["clip"]), " anim_scale=", "%.2f" % float(ds["anim_scale"]),
		" at=", String(ds["at_node"]), " yaw=%.3f" % float(ds["yaw"]))
	_v.call("clear_force")
	await _settle(4)
	print("[LIFESHOT] SEA_VIEW done state=", _state())

# ============================================================ 清单 =========
func _write_manifest() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var meta := {
		"probe": "tools/probe_p9_life_shots.gd",
		"generated_at": Time.get_datetime_string_from_system(false, true),
		"engine": String(Engine.get_version_info().get("string", "?")),
		"renderer": DisplayServer.get_name(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"resolution": [W, H],
		"scene": "res://isle.tscn",
		"shots": _shots,
		"fails": _fails,
	}
	var f := FileAccess.open(OUT_DIR + "manifest.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(meta, "  "))
		f.close()
	var log := FileAccess.open(OUT_DIR + "probe_p9_life_shots.log", FileAccess.WRITE)
	if log != null:
		log.store_string(JSON.stringify(meta, "  "))
		log.close()
	print("[LIFESHOT] manifest -> ", OUT_DIR + "manifest.json")
