extends SceneTree

## P7.1 真实窗口取景探针：门前农场地块/砾石路/五盏路灯（P7.1 删门前一盏）的俯视与平视取证。
## 用于设计"农田→钓点"直连路线与确认挡路路灯；只读，不改玩法。
## 运行（必须真实窗口，不能 --headless）：
##   ENG --path GAME --script res://tools/probe_p9_route_shots.gd -- --out=DIR

const DEFAULT_OUT := "D:/休闲小岛幻境/开发产物/P9/P7/after/route_window"
var out_dir := DEFAULT_OUT
var _main: Node = null
var _hud: Object = null
var _pass := 0
var _fail := 0
var _lines: Array = []
var _shots: Array = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var s: String = String(a)
		if s.begins_with("--out="):
			out_dir = s.substr(6).strip_edges().trim_suffix("/").trim_suffix("\\")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	print("=== P7.1 route shots ===")
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


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null or img.get_width() <= 0:
		_check("shot." + name, false, "非空 PNG", "empty")
		return
	DirAccess.make_dir_recursive_absolute("%s/shots" % out_dir)
	var path := "%s/shots/%s.png" % [out_dir, name]
	var err := img.save_png(path)
	_check("shot." + name, err == OK, "save OK", str(err))
	if err == OK:
		_shots.append(path)
		print("[SHOT] %s %dx%d %s" % [name, img.get_width(), img.get_height(), path])


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _boot() -> void:
	var ps := load("res://isle.tscn") as PackedScene
	_main = ps.instantiate()
	root.add_child(_main)
	await _frames(8)
	_hud = _main.get("_hud")
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
	var menu: Variant = _main.get("_menu")
	if menu != null and bool((menu as Node).get("visible")):
		(menu as Node).call("close")
		await _frames(60)
	_hud.call("set_hud_visible", true, false)
	await _frames(6)


func _shots_run() -> void:
	var world: Dictionary = _main.get("_world")
	var lamps: Array = world.get("lamps", [])
	_check("env.lamp_count", lamps.size() == 5, "5 盏路灯（P7.1 删门前 GardenLamp1）", str(lamps.size()))
	for entry in lamps:
		var info: Dictionary = (entry as Array)[3]
		var base: Vector3 = info["base"]
		print("[LAMP] %s base=%.3f,%.3f" % [String(info["name"]), base.x, base.z])
	# 1) 白天俯视：门前台面 + 农场支路 + 花园支路 + 主路起点
	_main.call("_pose_look", Vector3(1.0, 24.0, 14.0), Vector3(0.6, 7.6, 8.2), 52.0)
	await _frames(8)
	await _shot("01_front_yard_top_day")
	# 2) 夜间俯视：路灯亮起，看哪盏压在门前/出田口
	_main.call("_set_time_of_day", 21.0 * 60.0 + 35.0)
	await _frames(10)
	await _shot("02_front_yard_top_night")
	# 3) 平视：从门廊台阶看农场门（玩家实际看到的角度）
	_main.call("_set_time_of_day", 12.0 * 60.0 + 10.0)
	_main.call("_pose_look", Vector3(2.5, 9.25, 4.3), Vector3(-0.9, 7.7, 9.3), 62.0)
	await _frames(8)
	await _shot("03_porch_look_farm_gate")
	# 4) 平视：从农场门看门廊/主路（岛民出田后的朝向）
	_main.call("_pose_look", Vector3(-0.75, 9.20, 9.35), Vector3(2.4, 7.75, 4.8), 62.0)
	await _frames(8)
	await _shot("04_farm_gate_look_porch")
	# 5) 俯视特写：出田支路北端 + 主路起点（1.6 m 缺口）
	_main.call("_pose_look", Vector3(1.0, 13.5, 6.6), Vector3(1.4, 7.6, 5.9), 48.0)
	await _frames(8)
	await _shot("05_exit_junction_closeup")


func _write_log() -> void:
	var f := FileAccess.open("%s/probe_p9_route_shots.log" % out_dir, FileAccess.WRITE)
	if f != null:
		for line in _lines:
			f.store_line(String(line))
		f.close()
