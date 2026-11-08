extends SceneTree

## T7 AO 真实效果 / 引擎体积雾可见性 / AO 帧成本（v2 机位修正版）。
## 运行（窗口，非 headless）：
##   console.exe --path 游戏工程 --resolution 1600x900 --script res://tools/probe_ao_visual_t7.gd
## 产物：开发产物/shots6/ao/*.png、开发产物/logs/probe_ao_visual_t7.log

const S := preload("res://scripts/isle_settings.gd")
const M := preload("res://scripts/isle_math.gd")
const Astro := preload("res://scripts/isle_astro.gd")

const OUT_DIR := "D:/休闲小岛幻境/开发产物/shots6/ao/"
const LOG_PATH := "D:/休闲小岛幻境/开发产物/logs/probe_ao_visual_t7.log"

var _logs: Array = []
var _pass := 0
var _fail := 0

func _log(s: String) -> void:
	print(s)
	_logs.append(s)

func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
	_log(("PASS  " if cond else "FAIL  ") + name + ("" if detail.is_empty() else "  [" + detail + "]"))

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DirAccess.make_dir_recursive_absolute("D:/休闲小岛幻境/开发产物/logs")
	_log("=== probe_ao_visual_t7 v2 start ===")
	if DisplayServer.get_name() == "headless":
		_log("SKIP: headless 无渲染，AO 视觉/体积雾必须窗口运行")
		_flush()
		quit(0)
		return
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	var main = load("res://isle.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	main.set("_settings", S.defaults())
	main.set("_quality", 3)
	main.set("_time_source", "sim")
	main.set("_realtime", false)
	main.call("_apply_user_settings", false)
	main.set("_mode", 1)
	main.set("_started", true)
	main.set("_paused", true)
	main.set("_auto_orbit", false)
	main.set("_blending", "")
	var hud = main.get("_hud")
	if hud != null:
		hud.call("set_hud_visible", false, false)
	var menu = main.get("_menu")
	if menu != null:
		menu.visible = false
	for i in range(2):
		await process_frame

	var aomi: MeshInstance3D = main.get("_post_ao_mi")
	var aom: ShaderMaterial = main.get("_post_ao_mat")
	_check("ao_mesh_exists", aomi != null and aom != null)
	_log("quality=%d ao_strength_uniform=%.3f" % [int(main.get("_quality")), float(aom.get_shader_parameter("ao_strength"))])

	# ============ A. AO：正午三机位 off/on/debug ============
	main.call("_set_time_of_day", 12.0 * 60.0 + 20.0)
	for i in range(20):
		await process_frame
	main.set_process(false)
	var poses := {
		"house_front": [M.HOUSE_YAW, 0.30, 20.0, Vector3(M.HOUSE_X, M.house_ground_y() + 2.9, M.HOUSE_Z), 48.0],
		"stairs_close": [M.HOUSE_YAW, 0.25, 8.0, Vector3(M.door_world().x, M.terrain_height(M.door_world().x, M.door_world().z) + 0.75, M.door_world().z), 50.0],
		"roof_close": [0.62, 0.46, 26.0, Vector3(M.HOUSE_X, M.house_ground_y() + 6.2, M.HOUSE_Z), 42.0],
	}
	var attic_raw = main.get("_cottage").get("attic_window_world") if main.get("_cottage") != null else null
	if attic_raw is Vector3:
		poses["attic_window"] = [M.HOUSE_YAW, 0.22, 11.5, attic_raw + Vector3(0, -0.2, 0), 50.0]
	for pname in poses.keys():
		var pd: Array = poses[pname]
		_apply_orbit(main, float(pd[0]), float(pd[1]), float(pd[2]), pd[3], float(pd[4]))
		await process_frame
		await process_frame
		aomi.visible = false
		await _shot("noon_%s_ao_off" % pname)
		aomi.visible = true
		await _shot("noon_%s_ao_on" % pname)
	# debug 视图只看两个机位
	for pname in ["house_front", "attic_window"]:
		var pd: Array = poses[pname]
		_apply_orbit(main, float(pd[0]), float(pd[1]), float(pd[2]), pd[3], float(pd[4]))
		aom.set_shader_parameter("ao_debug", 1.0)
		await _shot("noon_%s_ao_debug" % pname)
		aom.set_shader_parameter("ao_debug", 0.0)
	# 强度档位：q2(.35) / q4(.75) 在 house_front + attic_window
	for q in [2, 4]:
		main.set("_quality", q)
		main.call("_apply_quality", q)
		await process_frame
		for pname in ["house_front", "attic_window"]:
			var pd2: Array = poses[pname]
			_apply_orbit(main, float(pd2[0]), float(pd2[1]), float(pd2[2]), pd2[3], float(pd2[4]))
			await _shot("noon_%s_q%d_ao_on" % [pname, q])
	main.set("_quality", 3)
	main.call("_apply_quality", 3)
	aomi.visible = true

	# ============ B. 引擎体积雾：真实黎明 / 正午，A/B ============
	var ev: Dictionary = Astro.day_events(float(main.get("_sim_seconds")))
	var sr := float(ev["sunrise"])       # 单位：分钟（_run_shots 直接使用）
	var ss := float(ev["sunset"])
	if sr < 0.0:
		sr = 355.0
	if ss < 0.0:
		ss = 1085.0
	_log("sunrise=%.1fmin sunset=%.1fmin" % [sr, ss])
	var env: Environment = main.get("_env")
	var fog_poses := {
		"dawn_house": [M.HOUSE_YAW, 0.20, 26.0, Vector3(M.HOUSE_X, M.house_ground_y() + 4.2, M.HOUSE_Z), 46.0],
	}
	for fp in fog_poses.keys():
		var fd: Array = fog_poses[fp]
		main.call("_set_time_of_day", sr + 8.0)
		main.call("_update_lighting")
		_apply_orbit(main, float(fd[0]), float(fd[1]), float(fd[2]), fd[3], float(fd[4]))
		for i in range(8):
			await process_frame
		await _shot("dawn_house_enginefog_off")
		_set_engine_fog(env, true)
		for i in range(10):
			await process_frame
		await _shot("dawn_house_enginefog_on")
		_set_engine_fog(env, false)
		for i in range(6):
			await process_frame
		await _shot("dawn_house_enginefog_off2")

	# 低机位望海：正午与黄昏，看雾对远景/海面的影响
	main.set_process(true)
	for spec in [["noon_sea", 12.0 * 60.0 + 20.0], ["dusk_sea", ss - 25.0]]:
		main.call("_set_time_of_day", float(spec[1]))
		main.call("_update_lighting")
		main.call("_pose_look", Vector3(0.0, 14.0, 8.0), Vector3(0.0, 3.0, -80.0), 56.0)
		for i in range(20):
			await process_frame
		await _shot("%s_enginefog_off" % spec[0])
		_set_engine_fog(env, true)
		for i in range(10):
			await process_frame
		await _shot("%s_enginefog_on" % spec[0])
		_set_engine_fog(env, false)
		for i in range(6):
			await process_frame

	# ============ C. AO 帧成本（初步，GPU 非独占）============
	main.call("_set_time_of_day", 12.0 * 60.0 + 20.0)
	main.call("_pose_look", Vector3(9.0, 4.6, 7.6), Vector3(0.8, 2.2, -0.6), 44.0)
	for i in range(30):
		await process_frame
	var off_ms: Array = []
	var on_ms: Array = []
	for round_i in range(3):
		aomi.visible = false
		off_ms.append(await _measure_frames(90))
		aomi.visible = true
		on_ms.append(await _measure_frames(90))
	var off_avg := _avg(off_ms)
	var on_avg := _avg(on_ms)
	_log("AO cost: off=%s avg=%.3fms  on=%s avg=%.3fms  delta=%.3fms" % [str(off_ms), off_avg, str(on_ms), on_avg, on_avg - off_avg])
	_log("RESULT %d/%d pass" % [_pass, _pass + _fail])
	_flush()
	quit(0)

func _set_engine_fog(env: Environment, on: bool) -> void:
	env.volumetric_fog_enabled = on
	if on:
		env.volumetric_fog_density = 0.045
		env.volumetric_fog_albedo = Color(1.0, 0.94, 0.86)
		env.volumetric_fog_emission_energy = 0.0
		env.volumetric_fog_anisotropy = 0.30
		env.volumetric_fog_length = 160.0
		env.volumetric_fog_detail_spread = 1.5
		env.volumetric_fog_sky_affect = 0.0

func _apply_orbit(main, theta: float, elev: float, radius: float, target: Vector3, fov: float) -> void:
	main.set("_theta", theta)
	main.set("_elev", elev)
	main.set("_radius", radius)
	main.set("_cam_target", target)
	main.set("_fov", fov)
	main.call("_apply_pose", main.call("_play_pose"))

func _measure_frames(n: int) -> float:
	var t0 := Time.get_ticks_usec()
	for i in range(n):
		await process_frame
	var t1 := Time.get_ticks_usec()
	return float(t1 - t0) / 1000.0 / float(n)

func _avg(a: Array) -> float:
	var s := 0.0
	for v in a:
		s += float(v)
	return s / maxf(1.0, float(a.size()))

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(OUT_DIR + name + ".png")
	_log("[SHOT] %s %dx%d" % [name, img.get_width(), img.get_height()])
	await process_frame

func _flush() -> void:
	var f := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_logs) + "\n")
		f.close()
