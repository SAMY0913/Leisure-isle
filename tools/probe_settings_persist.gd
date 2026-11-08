extends SceneTree
## P7-FINALIZE —— 设置持久化真实跨进程验收（正式 isle.tscn + 真实窗口/真实菜单路径）。
## 运行：ENG --path GAME --script res://tools/probe_settings_persist.gd -- --mode=set|check|restore --out=DIR
## 流程（由 shell 运行器分进程执行）：
##   set     : 启动正式场景 → 打开设置菜单 → 逐项修改（音量/画面/时间/天气）→ 等防抖落盘 → 打印保存路径与值
##   check   : 新进程启动 → 读 main._settings / 菜单 UI / AudioServer 实际 bus dB → 断言与 set 一致
##   restore : 读取 --baseline 指定的原始 cfg → 恢复除 volume_master 外的全部值，并把主音量固定为 30%
var _mode := "check"
var _out_dir := "D:/休闲小岛幻境/开发产物/P9/P7-finalize/evidence/settings"
var _baseline := ""
var _main: Node = null
var _pass := 0
var _fail := 0
var _lines: Array = []
var _fails: Array = []

const S := preload("res://scripts/isle_settings.gd")

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--mode="): _mode = s.substr(7)
		elif s.begins_with("--out="): _out_dir = s.substr(6).strip_edges().trim_suffix("/").trim_suffix("\\")
		elif s.begins_with("--baseline="): _baseline = s.substr(11)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _log(s: String) -> void:
	print(s)
	_lines.append(s)

func _chk(name: String, cond: bool, expected: String, actual: String) -> void:
	if cond:
		_pass += 1
		_log("[CHECK] %s | expected=%s actual=%s | PASS" % [name, expected, actual])
	else:
		_fail += 1
		_fails.append(name)
		_log("[CHECK] %s | expected=%s actual=%s | FAIL" % [name, expected, actual])

func _frames(n: int) -> void:
	for i in range(n):
		await process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null: return
	DirAccess.make_dir_recursive_absolute(_out_dir + "/shots")
	var p := "%s/shots/%s.png" % [_out_dir, name]
	img.save_png(p)
	_log("[SHOT] %s %dx%d %s" % [name, img.get_width(), img.get_height(), p])

func _run() -> void:
	_log("=== settings-persist mode=%s out=%s ===" % [_mode, _out_dir])
	if _mode == "restore":
		_do_restore()
		return
	var ps := load("res://isle.tscn") as PackedScene
	if ps == null:
		_log("[RESULT] FAIL scene"); quit(1); return
	_main = ps.instantiate()
	root.add_child(_main)
	await _frames(12)
	var menu = _main.get("_menu")
	if menu == null:
		_log("[RESULT] FAIL no-menu"); quit(1); return
	if _mode == "set":
		await _do_set(menu)
	elif _mode == "verify30":
		await _do_verify30(menu)
	else:
		await _do_check(menu)
	_log("[SUMMARY] checks=%d fail=%d" % [_pass + _fail, _fail])
	_log("[RESULT] %s" % ("PASS" if _fail == 0 and _pass > 0 else "FAIL"))
	var f := FileAccess.open(_out_dir + "/settings_persist_" + _mode + ".log", FileAccess.WRITE)
	if f != null: f.store_string("\n".join(_lines) + "\n"); f.close()
	quit(0 if _fail == 0 and _pass > 0 else 1)

func _set_slider(menu, key: String, value: float) -> void:
	var sliders: Dictionary = menu.get("_sliders")
	if sliders.has(key):
		(menu.call("_on_slider_changed", key, value))

func _slider_value(menu, key: String) -> float:
	var sliders: Dictionary = menu.get("_sliders")
	if not sliders.has(key): return -999.0
	return float((sliders[key] as Control).get("value"))

func _slider_label(menu, key: String) -> String:
	var labels: Dictionary = menu.get("_slider_value_labels")
	if not labels.has(key): return ""
	var l := labels[key] as Label
	return l.text if l != null else ""

func _do_set(menu) -> void:
	_log("--- set phase: 通过真实设置菜单回调修改 ---")
	menu.call("open_settings")
	await _frames(3)
	# 音量五组
	_set_slider(menu, "volume_master", 0.30)
	_set_slider(menu, "volume_ambient", 0.42)
	_set_slider(menu, "volume_birds", 0.51)
	_set_slider(menu, "volume_fire", 0.20)
	_set_slider(menu, "volume_sfx", 0.66)
	# 画面
	_set_slider(menu, "sensitivity", 1.50)
	_set_slider(menu, "fov", 55.0)
	_set_slider(menu, "quality", 3.0)
	# 时间流速：滑条 = 预设索引（1200s/日 = index 4）
	_set_slider(menu, "day_length", float(S.day_length_index(1200.0)))
	# 自动运镜开关
	menu.call("_on_setting_pressed", "auto")
	# 天气：切手动（走 main 的真实入口，会同步菜单并写设置）
	_main.call("_on_weather_auto_requested", false)
	await _frames(2)
	# 等待 0.25s 防抖 + 余量
	await create_timer(1.4).timeout
	await _frames(2)
	var sets: Dictionary = _main.get("_settings")
	_chk("set.main.volume_master", absf(float(sets.get("volume_master", -1.0)) - 0.30) < 0.001, "0.30", str(sets.get("volume_master")))
	_chk("set.menu.volume_master", absf(_slider_value(menu, "volume_master") - 0.30) < 0.001, "0.30", str(_slider_value(menu, "volume_master")))
	_chk("set.menu.label_30pct", _slider_label(menu, "volume_master") == "30%", "30%", _slider_label(menu, "volume_master"))
	# 实际 bus dB（真实 AudioServer）
	var bus := AudioServer.get_bus_index("Master")
	var db := AudioServer.get_bus_volume_db(bus)
	_chk("set.bus.db_matches_linear", absf(db - linear_to_db(0.30)) < 0.15, str(linear_to_db(0.30)), str(db))
	# 真正从磁盘读回（Save->Load 同进程回读）
	var disk := S.load_settings()
	_chk("set.disk.volume_master_30", absf(float(disk.get("volume_master", -1.0)) - 0.30) < 0.001, "0.30", str(disk.get("volume_master")))
	_chk("set.disk.volume_ambient", absf(float(disk.get("volume_ambient", -1.0)) - 0.42) < 0.001, "0.42", str(disk.get("volume_ambient")))
	_chk("set.disk.fov", absf(float(disk.get("fov", -1.0)) - 55.0) < 0.01, "55", str(disk.get("fov")))
	_chk("set.disk.quality", int(disk.get("quality", -1)) == 3, "3", str(disk.get("quality")))
	_chk("set.disk.day_length", absf(float(disk.get("day_length", -1.0)) - 1200.0) < 0.5, "1200", str(disk.get("day_length")))
	_chk("set.disk.auto_orbit", bool(disk.get("auto_orbit")) == false, "false", str(disk.get("auto_orbit")))
	_chk("set.disk.weather_auto", bool(disk.get("weather_auto")) == false, "false", str(disk.get("weather_auto")))
	_chk("set.disk.load_path_is_real", String(S.last_load_path) != "", S.last_load_path, String(S.last_load_path))
	_log("[PATH] save_path=%s load_path=%s" % [String(S.last_save_path), String(S.last_load_path)])
	await _shot("01_settings_after_set")
	_log("[RESULT] set-phase checks=%d fail=%d" % [_pass + _fail, _fail])

func _do_check(menu) -> void:
	_log("--- check phase: 新进程重启后读取 ---")
	var sets: Dictionary = _main.get("_settings")
	var s_path := S.load_settings()
	_log("[PATH] load_path=%s" % String(S.last_load_path))
	_chk("check.loaded_from_disk.volume_master", absf(float(sets.get("volume_master", -1.0)) - 0.30) < 0.001, "0.30", str(sets.get("volume_master")))
	_chk("check.menu.volume_master", absf(_slider_value(menu, "volume_master") - 0.30) < 0.001, "0.30", str(_slider_value(menu, "volume_master")))
	_chk("check.menu.label_30pct", _slider_label(menu, "volume_master") == "30%", "30%", _slider_label(menu, "volume_master"))
	var bus := AudioServer.get_bus_index("Master")
	var db := AudioServer.get_bus_volume_db(bus)
	_chk("check.bus.db_matches_30", absf(db - linear_to_db(0.30)) < 0.15, str(linear_to_db(0.30)), str(db))
	_chk("check.other.volume_ambient", absf(float(sets.get("volume_ambient", -1.0)) - 0.42) < 0.001, "0.42", str(sets.get("volume_ambient")))
	_chk("check.other.volume_birds", absf(float(sets.get("volume_birds", -1.0)) - 0.51) < 0.001, "0.51", str(sets.get("volume_birds")))
	_chk("check.other.volume_fire", absf(float(sets.get("volume_fire", -1.0)) - 0.20) < 0.001, "0.20", str(sets.get("volume_fire")))
	_chk("check.other.volume_sfx", absf(float(sets.get("volume_sfx", -1.0)) - 0.66) < 0.001, "0.66", str(sets.get("volume_sfx")))
	_chk("check.other.ambient_bus", absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("IsleAmbient")) - linear_to_db(0.42)) < 0.15, str(linear_to_db(0.42)), str(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("IsleAmbient"))))
	_chk("check.other.sensitivity", absf(float(sets.get("sensitivity", -1.0)) - 1.50) < 0.001, "1.50", str(sets.get("sensitivity")))
	_chk("check.other.fov", absf(float(sets.get("fov", -1.0)) - 55.0) < 0.01, "55", str(sets.get("fov")))
	_chk("check.other.quality", int(sets.get("quality", -1)) == 3, "3", str(sets.get("quality")))
	_chk("check.other.day_length", absf(float(sets.get("day_length", -1.0)) - 1200.0) < 0.5, "1200", str(sets.get("day_length")))
	_chk("check.other.auto_orbit", bool(sets.get("auto_orbit", true)) == false, "false", str(sets.get("auto_orbit")))
	_chk("check.other.weather_auto", bool(sets.get("weather_auto", true)) == false, "false", str(sets.get("weather_auto")))
	_chk("check.menu.fov_slider", absf(_slider_value(menu, "fov") - 55.0) < 0.01, "55", str(_slider_value(menu, "fov")))
	_chk("check.menu.quality_slider", absf(_slider_value(menu, "quality") - 3.0) < 0.01, "3", str(_slider_value(menu, "quality")))
	menu.call("open_settings")
	await _frames(3)
	await _shot("02_settings_after_restart")
	_log("[RESULT] check-phase checks=%d fail=%d" % [_pass + _fail, _fail])

## 最终状态：主音量 30% 跨进程保持；其余项恢复为基线（用户原来的偏好）。
func _do_verify30(menu) -> void:
	_log("--- verify30 phase: 重启后最终验收（音量 30） ---")
	var sets: Dictionary = _main.get("_settings")
	var base: Dictionary = S.defaults()
	if _baseline != "" and FileAccess.file_exists(_baseline):
		base = S.load_settings(_baseline)
	_chk("final.volume_master_30", absf(float(sets.get("volume_master", -1.0)) - 0.30) < 0.001, "0.30", str(sets.get("volume_master")))
	_chk("final.menu.label_30pct", _slider_label(menu, "volume_master") == "30%", "30%", _slider_label(menu, "volume_master"))
	var bus := AudioServer.get_bus_index("Master")
	var db := AudioServer.get_bus_volume_db(bus)
	_chk("final.bus.db_matches_30", absf(db - linear_to_db(0.30)) < 0.15, str(linear_to_db(0.30)), str(db))
	_chk("final.fov_restored", absf(float(sets.get("fov", -1.0)) - float(base.get("fov", 42.0))) < 0.01, str(base.get("fov", 42.0)), str(sets.get("fov")))
	_chk("final.quality_restored", int(sets.get("quality", -1)) == int(base.get("quality", 2)), str(base.get("quality", 2)), str(sets.get("quality")))
	_chk("final.day_length_restored", absf(float(sets.get("day_length", -1.0)) - float(base.get("day_length", 600.0))) < 0.5, str(base.get("day_length", 600.0)), str(sets.get("day_length")))
	_chk("final.load_path", String(S.last_load_path) != "", "non-empty", String(S.last_load_path))
	menu.call("open_settings")
	await _frames(3)
	await _shot("03_settings_final_volume30")
	_log("[PATH] load_path=%s" % String(S.last_load_path))
	_log("[RESULT] verify30 checks=%d fail=%d" % [_pass + _fail, _fail])


func _do_restore() -> void:
	_log("--- restore phase: 恢复基线值，主音量固定 30% ---")
	var base: Dictionary = {}
	if _baseline != "" and FileAccess.file_exists(_baseline):
		base = S.load_settings(_baseline)
		_log("[RESTORE] baseline loaded from %s" % _baseline)
	else:
		base = S.defaults()
		_log("[RESTORE] baseline missing, use defaults (%s)" % _baseline)
	# 除主音量外恢复基线；主音量固定 0.30（用户验收要求）。
	base["volume_master"] = 0.30
	var err: int = S.save_settings(base)
	_chk("restore.save_ok", err == OK, "OK", str(err))
	var back := S.load_settings()
	_chk("restore.volume_master_30", absf(float(back.get("volume_master", -1.0)) - 0.30) < 0.001, "0.30", str(back.get("volume_master")))
	_chk("restore.fov_baseline", absf(float(back.get("fov", -1.0)) - float(base.get("fov", 42.0))) < 0.01, str(base.get("fov", 42.0)), str(back.get("fov")))
	_chk("restore.quality_baseline", int(back.get("quality", -1)) == int(base.get("quality", 2)), str(base.get("quality", 2)), str(back.get("quality")))
	_chk("restore.day_length_baseline", absf(float(back.get("day_length", -1.0)) - float(base.get("day_length", 600.0))) < 0.5, str(base.get("day_length", 600.0)), str(back.get("day_length")))
	_log("[PATH] save_path=%s load_path=%s" % [String(S.last_save_path), String(S.last_load_path)])
	_log("[SUMMARY] checks=%d fail=%d" % [_pass + _fail, _fail])
	_log("[RESULT] %s" % ("PASS" if _fail == 0 and _pass > 0 else "FAIL"))
	var f := FileAccess.open(_out_dir + "/settings_persist_restore.log", FileAccess.WRITE)
	if f != null: f.store_string("\n".join(_lines) + "\n"); f.close()
	quit(0 if _fail == 0 and _pass > 0 else 1)
