extends SceneTree
## P7-V3 任务D FOV 设置探针（headless）
## 运行：
##   "$ENG" --headless --path "D:/休闲小岛幻境/游戏工程" --script res://tools/probe_settings_fov.gd
## 判据：exit 0 且 [FOVPROBE] RESULT fail=0。
## 覆盖：
##  1 isle_settings 常量/DEFAULTS/sanitize_fov（默认 42、clamp 35..65、取整、非法值回落）
##  2 保存/读取往返与旧配置迁移（缺 fov → 42；坏值/越界 → clamp 35/65）
##  3 user://settings.cfg 实际路径可持久化并读回（探针结束恢复原文件）
##  4 主场景菜单：FOV 滑块存在、范围 35–65/步进 1、数值标签 %d°、get/set_settings 全链路
##  5 分辨率/窗口模式/画质不被 FOV 覆盖
##  6 main._apply_user_settings → _fov 生效；设置面板打开时相机 FOV 实时预览（MENU 观景机位）

const S := preload("res://scripts/isle_settings.gd")

const TMP_CFG := "D:/休闲小岛幻境/开发产物/logs/probe_settings_fov.cfg"

var _pass := 0
var _fail := 0
var _user_cfg_abs := ""
var _user_cfg_backup := PackedByteArray()
var _user_cfg_existed := false


func _ok(tag: String, cond: bool, detail: String = "") -> void:
	print(("[FOVPROBE][PASS] " if cond else "[FOVPROBE][FAIL] ") + tag + (" | " + detail if detail != "" else ""))
	if cond:
		_pass += 1
	else:
		_fail += 1


func _initialize() -> void:
	await process_frame
	_backup_user_cfg()
	_test_schema()
	_test_persistence()
	await _test_scene()
	_restore_user_cfg()
	print("[FOVPROBE] RESULT pass=%d fail=%d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)


# ============================================================
# 0. user://settings.cfg 备份（探针会触发自动保存，结束恢复）
# ============================================================
func _backup_user_cfg() -> void:
	_user_cfg_abs = ProjectSettings.globalize_path(S.PATH)
	_user_cfg_existed = FileAccess.file_exists(_user_cfg_abs)
	if _user_cfg_existed:
		_user_cfg_backup = FileAccess.get_file_as_bytes(_user_cfg_abs)


func _restore_user_cfg() -> void:
	if _user_cfg_abs == "":
		return
	if _user_cfg_existed:
		var f := FileAccess.open(_user_cfg_abs, FileAccess.WRITE)
		if f != null:
			f.store_buffer(_user_cfg_backup)
			f.close()
	else:
		DirAccess.remove_absolute(_user_cfg_abs)


# ============================================================
# 1. schema / sanitize
# ============================================================
func _test_schema() -> void:
	print("[FOVPROBE] --- 1 schema & sanitize ---")
	_ok("const_default_42", is_equal_approx(S.FOV_DEFAULT, 42.0), str(S.FOV_DEFAULT))
	_ok("const_min_35", is_equal_approx(S.FOV_MIN, 35.0), str(S.FOV_MIN))
	_ok("const_max_65", is_equal_approx(S.FOV_MAX, 65.0), str(S.FOV_MAX))
	_ok("defaults_fov_42", is_equal_approx(float(S.DEFAULTS["fov"]), 42.0), str(S.DEFAULTS.get("fov")))
	var d: Dictionary = S.defaults()
	_ok("defaults_dup_fov_42", is_equal_approx(float(d["fov"]), 42.0))
	_ok("sanitize_42", is_equal_approx(S.sanitize_fov(42.0), 42.0))
	_ok("sanitize_clamp_low_35", is_equal_approx(S.sanitize_fov(20.0), 35.0), str(S.sanitize_fov(20.0)))
	_ok("sanitize_clamp_low_34.4", is_equal_approx(S.sanitize_fov(34.4), 35.0), str(S.sanitize_fov(34.4)))
	_ok("sanitize_clamp_high_65", is_equal_approx(S.sanitize_fov(80.0), 65.0), str(S.sanitize_fov(80.0)))
	_ok("sanitize_clamp_999_65", is_equal_approx(S.sanitize_fov(999.0), 65.0), str(S.sanitize_fov(999.0)))
	_ok("sanitize_round_42.4_42", is_equal_approx(S.sanitize_fov(42.4), 42.0), str(S.sanitize_fov(42.4)))
	_ok("sanitize_round_42.6_43", is_equal_approx(S.sanitize_fov(42.6), 43.0), str(S.sanitize_fov(42.6)))
	_ok("sanitize_null_42", is_equal_approx(S.sanitize_fov(null), 42.0), str(S.sanitize_fov(null)))
	_ok("sanitize_string_42", is_equal_approx(S.sanitize_fov("abc"), 42.0), str(S.sanitize_fov("abc")))


# ============================================================
# 2/3. 保存读取往返、旧配置迁移、user:// 实际路径
# ============================================================
func _test_persistence() -> void:
	print("[FOVPROBE] --- 2 persistence & migration ---")
	_remove_tmp()
	var v: Dictionary = S.defaults()
	v["fov"] = 55.0
	v["quality"] = 4
	v["resolution"] = Vector2i(1920, 1200)
	S.save_settings(v, TMP_CFG)
	var back: Dictionary = S.load_settings(TMP_CFG)
	_ok("rt_fov_55", is_equal_approx(float(back["fov"]), 55.0), str(back["fov"]))
	_ok("rt_quality_kept", int(back["quality"]) == 4)
	_ok("rt_resolution_kept", back["resolution"] == Vector2i(1920, 1200))
	_ok("rt_fullscreen_derived", bool(back["fullscreen"]) == false)
	# 旧配置（无 fov 键）→ 迁移到默认 42，其它键保留
	_remove_tmp()
	var cfg := ConfigFile.new()
	cfg.set_value("settings", "sensitivity", 1.5)
	cfg.set_value("settings", "quality", 3)
	cfg.set_value("settings", "resolution", Vector2i(1920, 1200))
	cfg.set_value("settings", "day_length", 1800.0)
	cfg.save(TMP_CFG)
	var mig: Dictionary = S.load_settings(TMP_CFG)
	_ok("legacy_missing_fov_42", is_equal_approx(float(mig["fov"]), 42.0), str(mig["fov"]))
	_ok("legacy_keeps_sensitivity", is_equal_approx(float(mig["sensitivity"]), 1.5))
	_ok("legacy_keeps_quality", int(mig["quality"]) == 3)
	_ok("legacy_keeps_day", is_equal_approx(float(mig["day_length"]), 1800.0))
	# 坏值 999 → clamp 65
	_remove_tmp()
	cfg = ConfigFile.new()
	cfg.set_value("settings", "fov", 999.0)
	cfg.save(TMP_CFG)
	var inv: Dictionary = S.load_settings(TMP_CFG)
	_ok("invalid_999_loaded_65", is_equal_approx(float(inv["fov"]), 65.0), str(inv["fov"]))
	# 保存越界值 10 → clamp 35
	_remove_tmp()
	var v2: Dictionary = S.defaults()
	v2["fov"] = 10.0
	S.save_settings(v2, TMP_CFG)
	_ok("save_clamp_low_35", is_equal_approx(float(S.load_settings(TMP_CFG)["fov"]), 35.0))
	_remove_tmp()
	# user://settings.cfg 实际路径（默认 PATH）持久化。
	# 注意：本机 headless 子进程的用户目录被沙箱 ACL 限制为只读（FileAccess 错误 12），
	# 无法写 user:// 时显式 SKIP 并说明，不把未验证项算通过。
	print("[FOVPROBE] --- 3 user://settings.cfg ---")
	var sentinel := "user://fov_probe_sentinel.txt"
	var sf := FileAccess.open(sentinel, FileAccess.WRITE)
	var user_writable := sf != null and FileAccess.get_open_error() == OK
	if sf != null:
		sf.close()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(sentinel))
	if user_writable:
		var v3: Dictionary = S.defaults()
		v3["fov"] = 55.0
		S.save_settings(v3)
		var u: Dictionary = S.load_settings()
		_ok("user_path_fov_55", is_equal_approx(float(u["fov"]), 55.0), str(u["fov"]))
	else:
		print("[FOVPROBE][SKIP] user_path_fov_55 | 当前沙箱环境禁止写 user://（open_error=%d），user://settings.cfg 落盘无法在此环境验证；已由 2 的显式路径往返覆盖" % FileAccess.get_open_error())
	print("[FOVPROBE] user_cfg=", _user_cfg_abs, " existed=", _user_cfg_existed, " writable=", user_writable)


func _remove_tmp() -> void:
	if FileAccess.file_exists(TMP_CFG):
		DirAccess.remove_absolute(TMP_CFG)


# ============================================================
# 4/5/6. 主场景菜单与相机联动
# ============================================================
func _test_scene() -> void:
	print("[FOVPROBE] --- 4 scene menu & camera ---")
	var scene: PackedScene = load("res://isle.tscn")
	_ok("isle_tscn_load", scene != null)
	if scene == null:
		return
	var main: Node = scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var menu: Variant = main.get("_menu")
	var cam: Camera3D = main.get("_cam") as Camera3D
	_ok("main_menu_ready", menu != null)
	_ok("main_cam_ready", cam != null)
	if menu == null or cam == null:
		main.queue_free()
		await process_frame
		return
	if menu.has_method("instant_finish"):
		menu.call("instant_finish")
	_ok("menu_is_settings_open_api", menu.has_method("is_settings_open"))
	_ok("settings_closed_initially", not bool(menu.call("is_settings_open")))
	var sliders: Dictionary = menu.get("_sliders")
	var labels: Dictionary = menu.get("_slider_value_labels")
	_ok("fov_slider_exists", sliders.has("fov"))
	_ok("fov_label_exists", labels.has("fov"))
	_ok("fov_row_title_present", _find_label_with(menu.get("_settings_panel"), "视野范围"))
	if not sliders.has("fov") or not labels.has("fov"):
		main.queue_free()
		await process_frame
		return
	var slider: Object = sliders["fov"]
	var label: Label = labels["fov"] as Label
	_ok("fov_slider_range_35_65", is_equal_approx(float(slider.get("min_value")), 35.0) and is_equal_approx(float(slider.get("max_value")), 65.0), "min=%s max=%s" % [slider.get("min_value"), slider.get("max_value")])
	_ok("fov_slider_step_1", is_equal_approx(float(slider.get("step")), 1.0), str(slider.get("step")))

	# 统一确定性起点：42（真实 user:// 配置可能是任意值）
	var settings: Dictionary = main.get("_settings")
	settings["fov"] = 42.0
	main.call("_apply_user_settings", false)
	await process_frame
	_ok("fov_default_label_42", String(label.text) == "42°", String(label.text))
	_ok("fov_default_settings_42", is_equal_approx(float(menu.get_settings()["fov"]), 42.0), str(menu.get_settings()["fov"]))
	_ok("fov_slider_value_42", is_equal_approx(float(slider.get("value")), 42.0), str(slider.get("value")))

	# 滑块 → 信号 → main 应用（等价设置面板实时预览链路）
	menu.call("_on_slider_changed", "fov", 55.0)
	await process_frame
	_ok("fov_slider_55_settings", is_equal_approx(float(menu.get_settings()["fov"]), 55.0))
	_ok("fov_slider_55_label", String(label.text) == "55°", String(label.text))
	_ok("fov_slider_55_main_applied", is_equal_approx(float(main.get("_fov")), 55.0), str(main.get("_fov")))

	# set_settings → 滑块/标签回写
	menu.set_settings({"fov": 50.0})
	await process_frame
	_ok("fov_set_50_settings", is_equal_approx(float(menu.get_settings()["fov"]), 50.0))
	_ok("fov_set_50_slider", is_equal_approx(float(slider.get("value")), 50.0), str(slider.get("value")))
	_ok("fov_set_50_label", String(label.text) == "50°", String(label.text))

	# 取整与 clamp 全链路
	menu.call("_on_slider_changed", "fov", 42.4)
	_ok("fov_round_42.4", is_equal_approx(float(menu.get_settings()["fov"]), 42.0))
	menu.set_settings({"fov": 999.0})
	await process_frame
	_ok("fov_set_999_clamped_65", is_equal_approx(float(menu.get_settings()["fov"]), 65.0) and String(label.text) == "65°", String(label.text))
	menu.set_settings({"fov": 35.0})
	await process_frame
	_ok("fov_set_35", is_equal_approx(float(menu.get_settings()["fov"]), 35.0) and String(label.text) == "35°", String(label.text))

	# 分辨率 / 窗口模式 / 画质不被 FOV 覆盖
	var before: Dictionary = menu.get_settings()
	menu.set_settings({"fov": 60.0})
	await process_frame
	var after: Dictionary = menu.get_settings()
	_ok("fov_keeps_resolution", after["resolution"] == before["resolution"], "%s vs %s" % [before["resolution"], after["resolution"]])
	_ok("fov_keeps_window_mode", String(after["window_mode"]) == String(before["window_mode"]), "%s vs %s" % [before["window_mode"], after["window_mode"]])
	_ok("fov_keeps_quality", int(after["quality"]) == int(before["quality"]))
	_ok("fov_keeps_auto_orbit", bool(after["auto_orbit"]) == bool(before["auto_orbit"]))

	# 设置面板打开时实时预览：MENU 观景机位下相机 FOV 跟随设置值
	print("[FOVPROBE] --- 5/6 camera preview ---")
	main.set("_mode", 0)
	main.set("_started", false)
	main.set("_blending", "")
	main.set("_auto_orbit", false)
	settings["fov"] = 55.0
	main.call("_apply_user_settings", false)
	menu.call("open_settings")
	await process_frame
	await process_frame
	_ok("settings_panel_open", bool(menu.call("is_settings_open")))
	_ok("preview_cam_fov_55", absf(cam.fov - 55.0) < 0.2, "cam.fov=%.2f _fov=%.2f" % [cam.fov, float(main.get("_fov"))])
	# 面板开着时继续拖滑块到 42，预览实时跟随
	menu.call("_on_slider_changed", "fov", 42.0)
	await process_frame
	await process_frame
	_ok("preview_live_42", absf(cam.fov - 42.0) < 0.2, "cam.fov=%.2f" % cam.fov)
	menu.call("close_settings_instant")
	await process_frame
	await process_frame
	_ok("closed_cam_movie_fov_36", absf(cam.fov - 36.0) < 0.2, "cam.fov=%.2f" % cam.fov)
	main.queue_free()
	await process_frame
	await process_frame


func _find_label_with(node: Variant, needle: String) -> bool:
	if node == null:
		return false
	var n := node as Node
	if n == null:
		return false
	if n is Label and String((n as Label).text).contains(needle):
		return true
	for c in n.get_children():
		if _find_label_with(c, needle):
			return true
	return false
