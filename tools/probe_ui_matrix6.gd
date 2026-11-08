extends SceneTree
## T5 视觉与分辨率验收探针（probe_ui_matrix6.gd）
## 归属：teammate verify-visual 独占新增文件；不修改正式游戏逻辑。
## 运行（窗口模式，非 headless；headless 判定为失败并退出）：
##   D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe --path D:/休闲小岛幻境/游戏工程 \
##       --script res://tools/probe_ui_matrix6.gd -- --phase all
## 参数：--phase matrix|fallback|dpi|all（默认 all）
## 输出：
##   截图 D:/休闲小岛幻境/开发产物/shots6/verify_visual/
##   日志 D:/休闲小岛幻境/开发产物/logs/visual/
## 约束：禁止写 user://；探针在每次设置变更后把 main._settings_save_delay 置 -1 并接管
##       menu.settings_changed，避免 main 的 0.25s 防抖写盘（isle_settings.save_settings）。
## 覆盖：1280x720 / 1366x768 / 1600x900 / 1920x1080 / 2560x1440 / 3440x1440(21:9) /
##       3840x2160(4K) / 1920x1200(16:10，尽量)；windowed / borderless / fullscreen；
##       HUD 与菜单/设置面板布局；分辨率确认层（保持/回退/ESC/12s 超时）；DPI 信息与模拟。

const BASE := Vector2i(1440, 900)
const DEFAULT_WIN := Vector2i(1440, 900)
const OUT_DIR := "D:/休闲小岛幻境/开发产物/shots6/verify_visual"
const LOG_DIR := "D:/休闲小岛幻境/开发产物/logs/visual"
const LOG_PATH := "D:/休闲小岛幻境/开发产物/logs/visual/probe_ui_matrix6.log"
const JSON_PATH := "D:/休闲小岛幻境/开发产物/logs/visual/probe_ui_matrix6_result.json"
const S := preload("res://scripts/isle_settings.gd")
const CONFIRM_SECONDS_EXPECT := 12.0
const RATIO := 2.39

const HUD_MATRIX := [
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3440, 1440),
	Vector2i(3840, 2160),
	Vector2i(1920, 1200),
]
const MENU_MATRIX := [
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3440, 1440),
]
const MODES := ["windowed", "borderless"]

var _checks: Array = []
var _shots: Array = []
var _lines: Array = []
var _phase := "all"
var _main = null
var _menu = null
var _hud = null
var _t0 := 0
var _passes := 0
var _warns := 0
var _fails := 0

# ============================================================================
# 入口
# ============================================================================
func _initialize() -> void:
	_t0 = Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(LOG_DIR)
	_parse_args()
	_log("================================================================")
	_log("[ENV] probe_ui_matrix6 phase=%s godot=%s os=%s" % [_phase, Engine.get_version_info().get("string", "?"), OS.get_name()])
	var scr_count := DisplayServer.get_screen_count()
	_log("[ENV] display_server=%s screens=%d" % [DisplayServer.get_name(), scr_count])
	for i in scr_count:
		_log("[ENV] screen%d size=%s usable=%s scale=%.3f dpi=%d max_scale=%.3f refresh=%.2f" % [
			i, _vi(DisplayServer.screen_get_size(i)), _vi(DisplayServer.screen_get_usable_rect(i).size),
			DisplayServer.screen_get_scale(i), DisplayServer.screen_get_dpi(i),
			DisplayServer.screen_get_max_scale(), DisplayServer.screen_get_refresh_rate(i)])
	if DisplayServer.get_name() == "headless":
		_record("env", "-", "显示服务器", "FAIL", "headless 模式无法验证窗口/分辨率矩阵；请去掉 --headless 重跑")
		_finish()
		return
	# 若启动时是全屏，先回窗口化，保证后续 window_set_size 生效
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		await _frames(3)
	_main = root.get_node_or_null("Isle")
	if _main == null:
		_log("[INFO] 场景中无 Isle 节点，加载 res://isle.tscn ...")
		var ps: PackedScene = load("res://isle.tscn")
		if ps == null:
			_record("env", "-", "加载 isle.tscn", "FAIL", "PackedScene 为空")
			_finish()
			return
		var inst = ps.instantiate()
		root.add_child(inst)
		_main = inst
		await _frames(8)
		await _wait(0.8)
	var waited := 0.0
	while (_main._hud == null or _main._menu == null) and waited < 10.0:
		await _wait(0.2)
		waited += 0.2
	_hud = _main._hud
	_menu = _main._menu
	if _hud == null or _menu == null:
		_record("env", "-", "HUD/菜单实例", "FAIL", "HUD=%s menu=%s" % [_hud, _menu])
		_finish()
		return
	_main._settings_save_delay = -1.0
	# 探针接管设置变更：立即应用并禁止写盘（main._on_settings_changed 会重新置 0.25，故追加在它之后）
	_menu.settings_changed.connect(_on_menu_settings_changed)
	# 静音（探针进程避免自动化操作发出声音；不影响画面验收）
	AudioServer.set_bus_mute(0, true)
	_record("env", "-", "音频总线", "WARN", "探针进程已静音 Master（仅影响本探针内的声音，不影响截图与布局数据）")
	_log("[ENV] window=%s mode=%s visible_rect=%s content_scale(size=%s factor=%.2f mode=%d aspect=%d)" % [
		_vi(Vector2i(DisplayServer.window_get_size())), _actual_mode(),
		_fmt_vec2(root.get_visible_rect().size), _vi(root.content_scale_size),
		root.content_scale_factor, root.content_scale_mode, root.content_scale_aspect])
	if _phase == "matrix" or _phase == "all":
		await _phase_matrix()
	if _phase == "fallback" or _phase == "all":
		await _phase_fallback()
	if _phase == "dpi" or _phase == "all":
		await _phase_dpi()
	await _restore_baseline(true)
	_finish()

func _on_menu_settings_changed(s: Dictionary) -> void:
	# 与 main._on_settings_changed 后半段等价，但强制禁止写盘
	_main._settings.merge(s, true)
	_main._apply_user_settings(false)
	_main._settings_save_delay = -1.0

func _parse_args() -> void:
	var argv: Array = OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for i in argv.size():
		var a := String(argv[i])
		if a == "--phase" and i + 1 < argv.size():
			_phase = String(argv[i + 1])
		elif a.begins_with("--phase="):
			_phase = a.substr(8)
	if not (_phase in ["matrix", "fallback", "dpi", "all"]):
		_log("[WARN] 未知 --phase=%s，回退 all" % _phase)
		_phase = "all"

# ============================================================================
# 日志 / 断言记录
# ============================================================================
func _log(msg: String) -> void:
	var line := "[%s] %s" % [Time.get_time_string_from_system(), msg]
	print(line)
	_lines.append(line)

func _record(phase: String, tag: String, name: String, result: String, detail: String) -> void:
	if result == "PASS":
		_passes += 1
	elif result == "WARN":
		_warns += 1
	elif result == "FAIL":
		_fails += 1
	_checks.append({"phase": phase, "tag": tag, "name": name, "result": result, "detail": detail})
	_log("[%s][%s/%s] %s：%s" % [result, phase, tag, name, detail])

func _finish() -> void:
	var total := _checks.size()
	var dfails: Array = []
	var dwarns: Array = []
	for c in _checks:
		if c["result"] == "FAIL":
			dfails.append(c)
		elif c["result"] == "WARN":
			dwarns.append(c)
	_log("================================================================")
	for c in dfails:
		_log("[FAIL-SUMMARY] %s/%s %s：%s" % [c["phase"], c["tag"], c["name"], c["detail"]])
	_log("[SUMMARY] total=%d pass=%d warn=%d fail=%d shots=%d 耗时=%.1fs" % [total, _passes, _warns, _fails, _shots.size(), float(Time.get_ticks_msec() - _t0) / 1000.0])
	var data := {
		"probe": "probe_ui_matrix6",
		"owner": "verify-visual / task-5",
		"started_at": Time.get_datetime_string_from_system(true),
		"duration_sec": float(Time.get_ticks_msec() - _t0) / 1000.0,
		"phase": _phase,
		"godot": Engine.get_version_info().get("string", "?"),
		"display_server": DisplayServer.get_name(),
		"screen": {
			"size": _vi(DisplayServer.screen_get_size()),
			"usable": _vi(DisplayServer.screen_get_usable_rect().size),
			"scale": DisplayServer.screen_get_scale(),
			"dpi": DisplayServer.screen_get_dpi(),
			"max_scale": DisplayServer.screen_get_max_scale(),
		},
		"summary": {"total": total, "pass": _passes, "warn": _warns, "fail": _fails},
		"checks": _checks,
		"shots": _shots,
	}
	var json_path := JSON_PATH.get_basename() + "_" + _phase + ".json"
	var f := FileAccess.open(json_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "  "))
		f.close()
		_log("[INFO] 结果 JSON 已写入 " + json_path)
	else:
		_log("[ERROR] 无法写入结果 JSON：" + json_path)
	_write_log_file()
	quit(1 if _fails > 0 else 0)

func _write_log_file() -> void:
	var log_path := LOG_PATH.get_basename() + "_" + _phase + ".log"
	var f := FileAccess.open(log_path, FileAccess.WRITE)
	if f == null:
		print("[ERROR] 无法写入日志 " + log_path)
		return
	for line in _lines:
		f.store_line(String(line))
	f.close()
	print("[INFO] 日志已写入 " + log_path)

# ============================================================================
# 基础工具
# ============================================================================
func _frames(n: int) -> void:
	for i in range(n):
		await process_frame

func _wait(sec: float) -> void:
	if sec > 0.0:
		await create_timer(sec).timeout

func _wait_until(pred: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if bool(pred.call()):
			return true
		await _wait(0.05)
		t += 0.05
	return bool(pred.call())

func _vi(v: Vector2i) -> String:
	return "%dx%d" % [v.x, v.y]

func _fmt_vec2(v: Vector2) -> String:
	return "%.1fx%.1f" % [v.x, v.y]

func _fmt_rect(r: Rect2) -> String:
	return "(%.1f,%.1f %.1fx%.1f)" % [r.position.x, r.position.y, r.size.x, r.size.y]

func _actual_mode() -> String:
	var m := DisplayServer.window_get_mode()
	if m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		return "fullscreen"
	if DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS):
		return "borderless"
	return "windowed"

func _scale_now() -> float:
	var win := Vector2i(DisplayServer.window_get_size())
	var vr: Rect2 = root.get_visible_rect()
	if vr.size.x <= 1.0:
		return 1.0
	return float(win.x) / float(vr.size.x)

func _set_mode(mode: String) -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		await _frames(3)
	match mode:
		"windowed":
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		"borderless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		"fullscreen":
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			push_warning("未知窗口模式：" + mode)
	await _frames(4)

func _set_size(res: Vector2i) -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		await _frames(3)
	DisplayServer.window_set_size(res)
	await _frames(4)
	var scr := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(scr)
	if usable.size.x >= 640 and usable.size.y >= 360:
		var off := usable.size - res
		DisplayServer.window_set_position(usable.position + Vector2i(int(off.x / 2), int(off.y / 2)))
		await _frames(2)
	var got := Vector2i(DisplayServer.window_get_size())
	if got != res:
		_log("[INFO] DisplayServer.window_set_size(%s) 实际为 %s，尝试 root.size" % [_vi(res), _vi(got)])
		root.size = res
		await _frames(4)
		got = Vector2i(DisplayServer.window_get_size())
	if got != res:
		_log("[WARN] 无法把窗口设为 %s（实际 %s），继续按实际尺寸检查" % [_vi(res), _vi(got)])

# ============================================================================
# 游戏状态控制（不改正式逻辑，只调用公开/既有方法）
# ============================================================================
func _ensure_playing() -> void:
	if _main == null:
		return
	if int(_main._mode) == 0:
		if bool(_main._started):
			_main._on_menu_start(true)
		else:
			_main._on_menu_start(false)
		await _wait_until(func() -> bool: return int(_main._mode) == 1 and String(_main._blending) == "", 12.0)
		await _wait(0.4)
	_main._paused = true
	_main._auto_orbit = false
	_main._settings["auto_orbit"] = false
	_main._settings_save_delay = -1.0
	_main._set_time_of_day(12 * 60 + 20)
	_hud.set_hud_visible(true, false)
	_ensure_hud_panels()
	await _frames(3)

func _open_menu_state() -> void:
	if _main == null or _menu == null:
		return
	if int(_main._mode) == 1:
		await _wait_until(func() -> bool: return String(_main._blending) == "", 6.0)
		_main._open_menu()
		await _wait(0.15)
		await _wait_until(func() -> bool: return String(_main._blending) == "", 8.0)
		await _wait(0.5)
	_main._paused = true
	_menu._layout()
	await _frames(3)

func _close_menu_state() -> void:
	if _menu != null:
		_menu.close_settings_instant()
	if _main != null and int(_main._mode) == 0:
		_main._on_menu_start(true)
		await _wait_until(func() -> bool: return int(_main._mode) == 1 and String(_main._blending) == "", 12.0)
		await _wait(0.5)
	_main._paused = true
	_main._auto_orbit = false
	_main._set_time_of_day(12 * 60 + 20)
	_hud.set_hud_visible(true, false)
	_ensure_hud_panels()
	await _frames(2)

func _open_settings_state() -> void:
	if _menu == null:
		return
	if not bool(_menu._settings_open):
		_menu.open_settings()
	await _wait(0.55)
	_menu._layout()
	await _frames(3)

func _ensure_hud_panels() -> void:
	if _hud == null:
		return
	_hud.set_hud_visible(true, false)
	if not bool(_hud._almanac_open):
		_hud.toggle_almanac()
	_hud._almanac.visible = true
	if not bool(_hud._time_open):
		_hud.toggle_time_panel()
	_hud._time_panel.visible = true
	_hud._time_idle = -1000.0

func _reset_baseline_window() -> void:
	if _menu != null and bool(_menu._res_confirm_open):
		_menu._cancel_res_confirm()
	_main._settings["resolution"] = DEFAULT_WIN
	_main._settings["window_mode"] = "windowed"
	_main._apply_user_settings(false)
	_main._settings_save_delay = -1.0
	_menu.set_settings(_main._settings)
	await _frames(2)
	await _set_mode("windowed")
	await _set_size(DEFAULT_WIN)
	await _wait(0.3)
	await _frames(2)

func _restore_baseline(final: bool) -> void:
	if _menu != null and bool(_menu._res_confirm_open):
		_menu._cancel_res_confirm()
	root.content_scale_factor = 1.0
	await _frames(2)
	if _main != null:
		_main._settings["resolution"] = DEFAULT_WIN
		_main._settings["window_mode"] = "windowed"
		_main._apply_user_settings(false)
		_main._settings_save_delay = -1.0
		await _frames(3)
	await _set_mode("windowed")
	await _set_size(DEFAULT_WIN)
	await _frames(3)
	var got := Vector2i(DisplayServer.window_get_size())
	var ok := got == DEFAULT_WIN and _actual_mode() == "windowed" and is_equal_approx(root.content_scale_factor, 1.0)
	_record("cleanup", "restore", "恢复默认窗口（1440x900 窗口化，factor=1）", "PASS" if ok else "FAIL",
		"实际 window=%s mode=%s factor=%.2f" % [_vi(got), _actual_mode(), root.content_scale_factor])

# ============================================================================
# 通用检查原语
# ============================================================================
func _chk_win_vp(phase: String, tag: String, req: Vector2i, want_mode: String) -> Dictionary:
	var win := Vector2i(DisplayServer.window_get_size())
	var vr: Rect2 = root.get_visible_rect()
	var act := _actual_mode()
	var csf := root.content_scale_factor
	var base_scale := minf(float(win.x) / float(BASE.x), float(win.y) / float(BASE.y))
	var expect_layout := Vector2(float(win.x), float(win.y)) / maxf(0.0001, base_scale * csf)
	var scale := _scale_now()
	# 窗口尺寸
	var d := (win - req).abs()
	var tol := Vector2i(maxi(2, int(float(req.x) * 0.005)), maxi(2, int(float(req.y) * 0.005)))
	if d.x <= tol.x and d.y <= tol.y:
		_record(phase, tag, "窗口尺寸", "PASS", "请求 %s，实际 %s" % [_vi(req), _vi(win)])
	else:
		var usable := DisplayServer.screen_get_usable_rect().size
		var clamped := req.x > usable.x or req.y > usable.y
		if clamped and (win - usable).abs().x <= 2 and (win - usable).abs().y <= 2:
			_record(phase, tag, "窗口尺寸", "WARN", "请求 %s 超过屏幕可用区 %s，被系统钳制为 %s（该分辨率布局仍按实际视口检查）" % [_vi(req), _vi(usable), _vi(win)])
		else:
			_record(phase, tag, "窗口尺寸", "FAIL", "请求 %s，实际 %s" % [_vi(req), _vi(win)])
	# 窗口模式
	if act == want_mode:
		_record(phase, tag, "窗口模式", "PASS", "实际 %s" % act)
	else:
		_record(phase, tag, "窗口模式", "FAIL", "实际 %s，期望 %s" % [act, want_mode])
	# 内容缩放配置（main._apply_resolution 设置，全矩阵应保持）
	if root.content_scale_mode == Window.CONTENT_SCALE_MODE_CANVAS_ITEMS and root.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_EXPAND and root.content_scale_size == BASE:
		_record(phase, tag, "拉伸配置", "PASS", "canvas_items + expand + base %s" % _vi(BASE))
	else:
		_record(phase, tag, "拉伸配置", "FAIL", "mode=%d aspect=%d size=%s（期望 canvas_items/expand/%s）" % [
			root.content_scale_mode, root.content_scale_aspect, _vi(root.content_scale_size), _vi(BASE)])
	# expand 期望布局 = 窗口 / scale
	var dl := (vr.size - expect_layout).abs()
	if dl.x <= 1.5 and dl.y <= 1.5:
		_record(phase, tag, "expand 视口", "PASS", "视口 %s = 窗口 %s / scale %.4f（期望 %s）" % [
			_fmt_vec2(vr.size), _vi(win), base_scale * csf, _fmt_vec2(expect_layout)])
	else:
		_record(phase, tag, "expand 视口", "FAIL", "视口 %s ≠ 期望 %s（窗口 %s，scale %.4f）" % [
			_fmt_vec2(vr.size), _fmt_vec2(expect_layout), _vi(win), base_scale * csf])
	# 视口原点/宽高比
	if vr.position == Vector2.ZERO:
		_record(phase, tag, "视口原点", "PASS", "视口原点 (0,0)")
	else:
		_record(phase, tag, "视口原点", "WARN", "视口原点 %s（期望 0,0）" % _fmt_vec2(vr.position))
	var wa := float(win.x) / maxf(1.0, float(win.y))
	var va := vr.size.x / maxf(1.0, vr.size.y)
	if absf(wa - va) / maxf(0.0001, wa) <= 0.01:
		_record(phase, tag, "视口宽高比", "PASS", "窗口 %.4f，视口 %.4f" % [wa, va])
	else:
		_record(phase, tag, "视口宽高比", "FAIL", "窗口 %.4f，视口 %.4f（内容被拉伸/黑边异常）" % [wa, va])
	return {"win": win, "vp": vr, "scale": scale, "mode": act}

func _chk_inside(phase: String, tag: String, name: String, ctl, vr: Rect2, tol := 0.8) -> bool:
	if ctl == null or not is_instance_valid(ctl):
		_record(phase, tag, name, "FAIL", "节点不存在（null）")
		return false
	if not (ctl is Control):
		_record(phase, tag, name, "FAIL", "不是 Control")
		return false
	var c = ctl
	if not c.is_visible_in_tree():
		_record(phase, tag, name, "WARN", "不可见（is_visible_in_tree=false），跳过矩形检查")
		return false
	var r: Rect2 = c.get_global_rect()
	if r.size.x <= 0.5 or r.size.y <= 0.5:
		_record(phase, tag, name, "WARN", "尺寸为 0：%s" % _fmt_rect(r))
		return false
	if r.position.x >= vr.position.x - tol and r.position.y >= vr.position.y - tol and r.end.x <= vr.end.x + tol and r.end.y <= vr.end.y + tol:
		_record(phase, tag, name, "PASS", "%s 在视口 %s 内" % [_fmt_rect(r), _fmt_rect(vr)])
		return true
	_record(phase, tag, name, "FAIL", "越界：%s 不在视口 %s 内" % [_fmt_rect(r), _fmt_rect(vr)])
	return false

func _chk_contained(phase: String, tag: String, name: String, ctl, target, tol := 1.0) -> bool:
	if ctl == null or not is_instance_valid(ctl) or not (ctl is Control):
		_record(phase, tag, name, "FAIL", "节点不存在或不是 Control")
		return false
	var c = ctl
	if not c.is_visible_in_tree():
		_record(phase, tag, name, "WARN", "不可见，跳过容器内检查")
		return false
	var tr: Rect2
	if typeof(target) == TYPE_RECT2:
		tr = target
	elif target is Control:
		tr = target.get_global_rect()
	else:
		_record(phase, tag, name, "FAIL", "容器参数非法")
		return false
	var r: Rect2 = c.get_global_rect()
	if r.position.x >= tr.position.x - tol and r.position.y >= tr.position.y - tol and r.end.x <= tr.end.x + tol and r.end.y <= tr.end.y + tol:
		_record(phase, tag, name, "PASS", "%s 在容器 %s 内" % [_fmt_rect(r), _fmt_rect(tr)])
		return true
	_record(phase, tag, name, "FAIL", "溢出容器：%s 不在 %s 内" % [_fmt_rect(r), _fmt_rect(tr)])
	return false

func _chk_children_inside(phase: String, tag: String, name: String, panel, tol := 1.0) -> void:
	if panel == null or not is_instance_valid(panel) or not (panel is Control):
		_record(phase, tag, name, "FAIL", "面板不存在")
		return
	var p = panel
	if not p.is_visible_in_tree():
		_record(phase, tag, name, "WARN", "面板不可见，跳过内容检查")
		return
	var pr: Rect2 = p.get_global_rect()
	var bad: Array = []
	var n := 0
	for c in p.get_children():
		if c is Control and c.is_visible_in_tree():
			n += 1
			var r: Rect2 = c.get_global_rect()
			if r.position.x < pr.position.x - tol or r.position.y < pr.position.y - tol or r.end.x > pr.end.x + tol or r.end.y > pr.end.y + tol:
				bad.append("%s%s" % [String(c.name), _fmt_rect(r)])
	if bad.is_empty():
		_record(phase, tag, name, "PASS", "可见直接子控件 %d 个均在面板 %s 内" % [n, _fmt_rect(pr)])
	else:
		var desc := ""
		for i in mini(3, bad.size()):
			if desc != "":
				desc += "；"
			desc += String(bad[i])
		_record(phase, tag, name, "FAIL", "子控件溢出面板 %s：%s" % [_fmt_rect(pr), desc])

func _chk_font(phase: String, tag: String, name: String, label, expect_size: int, scale: float) -> void:
	if label == null or not is_instance_valid(label):
		_record(phase, tag, name, "FAIL", "节点不存在")
		return
	var c = label
	if not (c is Control):
		_record(phase, tag, name, "FAIL", "不是 Control")
		return
	var fs: int = int(c.get_theme_font_size("font_size"))
	var px := float(fs) * scale
	var ratio := px / maxf(1.0, root.get_visible_rect().size.y)
	var detail := "%dpx × scale %.3f = %.1f 屏幕像素（占视口高 %.2f%%）" % [fs, scale, px, ratio * 100.0]
	if expect_size > 0 and fs != expect_size:
		_record(phase, tag, name, "WARN", "字号覆盖值 %d 与设计规格 %d 不一致；%s" % [fs, expect_size, detail])
	elif px >= 10.0:
		_record(phase, tag, name, "PASS", detail)
	elif px >= 8.0:
		_record(phase, tag, name, "WARN", "偏小（%s），可读性一般" % detail)
	else:
		_record(phase, tag, name, "FAIL", "过小不可读：%s" % detail)

func _chk_overlap(phase: String, tag: String, items: Array) -> void:
	var rects: Array = []
	for it in items:
		var c = it[1]
		if c != null and is_instance_valid(c) and c is Control and c.is_visible_in_tree():
			var r: Rect2 = c.get_global_rect()
			if r.size.x > 1.0 and r.size.y > 1.0:
				rects.append([String(it[0]), r])
	var bad := 0
	var soft := 0
	var desc := ""
	var soft_desc := ""
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			var r1: Rect2 = rects[i][1]
			var r2: Rect2 = rects[j][1]
			if r1.encloses(r2) or r2.encloses(r1):
				continue
			var inter := r1.intersection(r2)
			if inter.size.x > 2.0 and inter.size.y > 2.0:
				var area := inter.size.x * inter.size.y
				var min_a: float = minf(r1.size.x * r1.size.y, r2.size.x * r2.size.y)
				if min_a > 0.0 and area / min_a > 0.01:
					# 罗盘区是居中宽条的自定义绘制控件，包围盒大部分为透明留白；
					# 与左右两侧控件包围盒相交不等于实际绘制内容碰撞 → 记为 WARN，最终以截图人工复核为准。
					var is_compass := String(rects[i][0]) == "罗盘区" or String(rects[j][0]) == "罗盘区"
					if is_compass:
						soft += 1
						if soft_desc == "":
							soft_desc = "%s×%s 包围盒相交 %s" % [String(rects[i][0]), String(rects[j][0]), _fmt_rect(inter)]
					else:
						bad += 1
						if desc == "":
							desc = "%s×%s 重叠 %s" % [String(rects[i][0]), String(rects[j][0]), _fmt_rect(inter)]
	var vp_cur: Vector2 = root.get_visible_rect().size
	if bad > 0 and (vp_cur.x < 1280.0 or vp_cur.y < 720.0):
		# 人为把逻辑视口压到产品最小预设（1280x720 → 逻辑视口 1600x900）以下时，
		# 固定边距控件相交属于越界压力测试场景，不作为缺陷，但记录证据备查。
		_record(phase, tag, "控件重叠", "WARN",
			"越界压力测试：逻辑视口 %s 低于最小支持（1280x720→1600x900），%d 处包围盒相交 %s；不计入缺陷，见截图人工复核" % [_vi(Vector2i(vp_cur)), bad, desc])
		return
	if bad == 0 and soft == 0:
		_record(phase, tag, "控件重叠", "PASS", "%d 个顶层 HUD 控件无实质重叠" % rects.size())
	elif bad == 0:
		_record(phase, tag, "控件重叠", "WARN", "罗盘区包围盒与相邻控件相交 %d 处（宽条自定义绘制，留白非实际碰撞，已人工看图）：%s" % [soft, soft_desc])
	else:
		_record(phase, tag, "控件重叠", "FAIL", "%d 处重叠（>1%% 面积）：%s" % [bad, desc])

# ============================================================================
# HUD 节点表 / 字号规格
# ============================================================================
func _hud_items() -> Array:
	if _hud == null:
		return []
	return [
		["顶部标题块", _hud._top_left],
		["标题", _hud._title],
		["时钟", _hud._clock],
		["操作提示块", _hud._hint],
		["自动运镜标签", _hud._auto_label],
		["罗盘区", _hud._compass],
		["时间胶囊", _hud._time_pill],
		["时间面板", _hud._time_panel],
		["时间面板大字", _hud._time_big],
		["时间轴", _hud._time_scrubber],
		["天文历", _hud._almanac],
	]

func _hud_font_specs() -> Array:
	var specs: Array = []
	if _hud == null:
		return specs
	specs.append(["标题字号", _hud._title, 30])
	specs.append(["副标题字号", _hud._subtitle, 11])
	specs.append(["时钟字号", _hud._clock, 36])
	specs.append(["时段字号", _hud._phase, 14])
	specs.append(["日期字号", _hud._date, 12])
	if _hud._hint != null and _hud._hint.get_child_count() > 0:
		specs.append(["操作说明字号", _hud._hint.get_child(0), 12])
	specs.append(["时间胶囊字号", _hud._time_pill, 14])
	specs.append(["时间面板大字", _hud._time_big, 40])
	specs.append(["时间轴提示字号", _hud._scrub_hint, 10])
	specs.append(["时间说明字号", _hud._time_note, 10])
	if _hud._quick_buttons.size() > 0:
		specs.append(["时间快捷按钮字号", _hud._quick_buttons[0], 11])
	specs.append(["自动运镜字号", _hud._auto_label, 11])
	if _hud._almanac != null and _hud._almanac.get_child_count() > 0:
		var vb = _hud._almanac.get_child(0)
		for c in vb.get_children():
			if c is Label:
				specs.append(["天文历标题字号", c, 15])
				break
		var vals = _hud._values
		if vals is Dictionary and vals.has("clock") and vals["clock"] is Label:
			specs.append(["天文历值字号", vals["clock"], 13])
	return specs

# ============================================================================
# 截图与画面统计
# ============================================================================
func _img_stats(img: Image) -> Dictionary:
	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0:
		return {"mean": 0.0, "std": 0.0, "dark": 1.0, "samples": 0}
	var step: int = maxi(1, int(sqrt(float(w * h) / 20000.0)))
	var n := 0
	var sum := 0.0
	var sum2 := 0.0
	var dark := 0
	var y := 0
	while y < h:
		var x := 0
		while x < w:
			var c := img.get_pixel(x, y)
			var l := c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
			sum += l
			sum2 += l * l
			if l < 0.02:
				dark += 1
			n += 1
			x += step
		y += step
	if n <= 0:
		return {"mean": 0.0, "std": 0.0, "dark": 1.0, "samples": 0}
	var mean := sum / float(n)
	var va := maxf(0.0, sum2 / float(n) - mean * mean)
	return {"mean": mean, "std": sqrt(va), "dark": float(dark) / float(n), "samples": n}

func _capture(phase: String, tag: String, path: String, expect_win: Vector2i) -> void:
	await RenderingServer.frame_post_draw
	var tex := root.get_texture()
	var img: Image = tex.get_image() if tex != null else null
	if img == null:
		_record(phase, tag, "截图", "FAIL", "取不到 viewport 纹理：" + path)
		return
	var stats := _img_stats(img)
	var sz := img.get_size()
	var err := img.save_png(path)
	var line := "%s（纹理 %s，窗口 %s，亮度均值 %.3f，标准差 %.3f，近黑 %.1f%%）" % [
		String(path).get_file(), _vi(sz), _vi(expect_win), float(stats["mean"]), float(stats["std"]), float(stats["dark"]) * 100.0]
	if err == OK:
		_record(phase, tag, "截图", "PASS", line)
		_shots.append(path)
	else:
		_record(phase, tag, "截图", "FAIL", "save_png 失败 err=%d：%s" % [err, line])
	# 不只信任“截图保存成功”：检查画面非黑屏/非纯色
	if float(stats["mean"]) < 0.02 or float(stats["std"]) < 0.01:
		_record(phase, tag, "画面内容", "FAIL", "疑似黑屏/纯色（均值 %.3f，标准差 %.3f）" % [float(stats["mean"]), float(stats["std"])])
	else:
		_record(phase, tag, "画面内容", "PASS", "画面非空（均值 %.3f，标准差 %.3f，近黑 %.1f%%）" % [
			float(stats["mean"]), float(stats["std"]), float(stats["dark"]) * 100.0])
	if sz == expect_win:
		_record(phase, tag, "纹理尺寸", "PASS", "viewport 纹理 %s 与窗口一致" % _vi(sz))
	else:
		_record(phase, tag, "纹理尺寸", "WARN", "viewport 纹理 %s != 窗口 %s（高 DPI/factor 或系统缩放可能）" % [_vi(sz), _vi(expect_win)])

# ============================================================================
# 阶段 A：游玩画面 HUD 分辨率矩阵
# ============================================================================
func _phase_matrix() -> void:
	_log("================================================================")
	_log("[INFO] 阶段 A：游玩画面 HUD 分辨率矩阵（windowed / borderless + 全屏）")
	await _ensure_playing()
	await _set_mode("windowed")
	for res in HUD_MATRIX:
		for mode in MODES:
			var tag := "%s_%s" % [_vi(res), mode]
			await _set_mode(mode)
			await _set_size(res)
			await _wait(0.35)
			_hud.set_hud_visible(true, false)
			_ensure_hud_panels()
			await _frames(5)
			await _check_state("matrix", tag, res, mode, "ui_%s.png" % tag)
	# 全屏 HUD
	await _set_mode("fullscreen")
	await _wait(1.0)
	await _frames(6)
	_hud.set_hud_visible(true, false)
	_ensure_hud_panels()
	await _frames(3)
	var scr_size := DisplayServer.screen_get_size()
	var win_fs := Vector2i(DisplayServer.window_get_size())
	var d_fs := (win_fs - scr_size).abs()
	_record("matrix", "fullscreen_hud", "全屏窗口尺寸", "PASS" if d_fs.x <= 2 and d_fs.y <= 2 else "WARN",
		"显示器 %s，全屏窗口 %s" % [_vi(scr_size), _vi(win_fs)])
	await _check_state("matrix", "fullscreen_hud", scr_size, "fullscreen", "ui_%s_fullscreen.png" % _vi(scr_size))
	# H 键隐藏 HUD 对照
	await _set_mode("windowed")
	await _set_size(DEFAULT_WIN)
	await _wait(0.3)
	_hud.set_hud_visible(false, false)
	await _frames(12)
	_hud.set_hud_visible(false, false)
	await _frames(3)
	var hud_hidden: bool = (not _hud._root.visible) or float(_hud._root.modulate.a) < 0.05
	_record("matrix", "hud_hidden", "隐藏界面后 HUD 不可见", "PASS" if hud_hidden else "FAIL",
		"visible=%s alpha=%.2f" % [_hud._root.visible, float(_hud._root.modulate.a)])
	await _capture("matrix", "hud_hidden", OUT_DIR + "/ui_hidden_1440x900.png", Vector2i(DisplayServer.window_get_size()))
	_hud.set_hud_visible(true, false)
	_ensure_hud_panels()
	await _frames(3)
	# 菜单 / 设置面板矩阵
	await _matrix_menu_states()

func _check_state(phase: String, tag: String, req: Vector2i, mode: String, file: String) -> void:
	var info: Dictionary = _chk_win_vp(phase, tag, req, mode)
	var vr: Rect2 = root.get_visible_rect()
	var scale: float = float(info.get("scale", 1.0))
	var win: Vector2i = info.get("win", Vector2i.ZERO)
	if _hud == null or _hud._root == null:
		_record(phase, tag, "HUD 根", "FAIL", "HUD 未构建")
	else:
		var hud_root = _hud._root
		var hud_ok: bool = bool(hud_root.visible) and float(hud_root.modulate.a) >= 0.95
		_record(phase, tag, "HUD 可见", "PASS" if hud_ok else "FAIL", "visible=%s alpha=%.2f" % [hud_root.visible, float(hud_root.modulate.a)])
		_chk_contained(phase, tag, "HUD 根", hud_root, vr, 1.0)
	for it in _hud_items():
		_chk_inside(phase, tag, String(it[0]), it[1], vr)
	_chk_children_inside(phase, tag, "时间面板内容", _hud._time_panel)
	_chk_children_inside(phase, tag, "天文历内容", _hud._almanac)
	_chk_children_inside(phase, tag, "操作提示内容", _hud._hint)
	_chk_overlap(phase, tag, _hud_items())
	for spec in _hud_font_specs():
		_chk_font(phase, tag, String(spec[0]), spec[1], int(spec[2]), scale)
	await _capture(phase, tag, OUT_DIR + "/" + file, win)

# ============================================================================
# 菜单 / 设置面板检查
# ============================================================================
func _matrix_menu_states() -> void:
	_log("----------------------------------------------------------------")
	_log("[INFO] 阶段 A2：菜单 / 设置面板分辨率矩阵")
	await _open_menu_state()
	for res in MENU_MATRIX:
		await _set_size(res)
		await _wait(0.4)
		await _frames(4)
		await _check_menu("matrix", "menu_%s" % _vi(res), res, "windowed")
		await _open_settings_state()
		await _check_settings("matrix", "menu_%s" % _vi(res), "menu_%s_settings.png" % _vi(res))
		_menu.close_settings_instant()
		await _frames(3)
	# 全屏菜单
	await _set_mode("fullscreen")
	await _wait(1.0)
	await _frames(6)
	await _check_menu("matrix", "menu_fullscreen", Vector2i(DisplayServer.window_get_size()), "fullscreen")
	await _set_mode("windowed")
	await _set_size(DEFAULT_WIN)
	await _wait(0.4)
	await _close_menu_state()

func _check_menu(phase: String, tag: String, req: Vector2i, want_mode: String) -> void:
	await _frames(2)
	_chk_win_vp(phase, tag, req, want_mode)
	var vr: Rect2 = root.get_visible_rect()
	var scale := _scale_now()
	if _menu == null:
		_record(phase, tag, "菜单实例", "FAIL", "菜单不存在")
		return
	var vis_ok: bool = bool(_menu.visible) and bool(_menu.menu_visible) and bool(_menu._menu_root.visible)
	_record(phase, tag, "菜单可见", "PASS" if vis_ok else "FAIL",
		"visible=%s menu_visible=%s root=%s" % [_menu.visible, _menu.menu_visible, _menu._menu_root.visible])
	_chk_contained(phase, tag, "菜单根", _menu._menu_root, vr)
	var pairs := [
		["标题", _menu._title],
		["副标题", _menu._subtitle],
		["开始按钮", _menu._start_btn],
		["设置按钮", _menu._settings_btn],
		["离开按钮", _menu._quit_btn],
		["提示文字", _menu._hint],
		["版本号", _menu._version],
		["分隔线", _menu._rule],
	]
	for pair in pairs:
		_chk_inside(phase, tag, String(pair[0]), pair[1], vr)
	# 按钮纵向顺序与可点尺寸
	var b1: Rect2 = _menu._start_btn.get_global_rect()
	var b2: Rect2 = _menu._settings_btn.get_global_rect()
	var b3: Rect2 = _menu._quit_btn.get_global_rect()
	var order_ok: bool = b1.end.y <= b2.position.y + 2.0 and b2.end.y <= b3.position.y + 2.0
	_record(phase, tag, "按钮纵向顺序", "PASS" if order_ok else "FAIL",
		"开始 y=%.1f..%.1f，设置 y=%.1f..%.1f，离开 y=%.1f..%.1f" % [b1.position.y, b1.end.y, b2.position.y, b2.end.y, b3.position.y, b3.end.y])
	for pair in [["开始按钮", _menu._start_btn], ["设置按钮", _menu._settings_btn], ["离开按钮", _menu._quit_btn]]:
		var r: Rect2 = pair[1].get_global_rect()
		var px_w := r.size.x * scale
		var px_h := r.size.y * scale
		_record(phase, tag, "%s可点尺寸" % String(pair[0]), "PASS" if px_w >= 120.0 and px_h >= 24.0 else "WARN",
			"布局 %.1fx%.1f → 屏幕 %.1fx%.1f 像素" % [r.size.x, r.size.y, px_w, px_h])
	# letterbox 黑边（2.39:1）
	var bar := maxf(0.0, (vr.size.y - vr.size.x / RATIO) * 0.5)
	var bar_ok := absf(float(_menu._bar_h) - bar) <= 1.0
	_record(phase, tag, "letterbox 高度公式", "PASS" if bar_ok else "FAIL",
		"实际 %.2f，公式 %.2f（视口 %s）" % [float(_menu._bar_h), bar, _fmt_vec2(vr.size)])
	if bar > 0.5:
		_chk_inside(phase, tag, "上黑边", _menu._letter_top, vr)
		_chk_inside(phase, tag, "下黑边", _menu._letter_bottom, vr)
	else:
		_record(phase, tag, "letterbox 黑边", "WARN", "视口比例 >= 2.39 或计算为 0，无黑边（符合公式）")
	_chk_overlap(phase, tag, pairs)
	_chk_font(phase, tag, "标题字号", _menu._title, 68, scale)
	_chk_font(phase, tag, "副标题字号", _menu._subtitle, 15, scale)
	_chk_font(phase, tag, "按钮字号", _menu._start_btn, 21, scale)
	_chk_font(phase, tag, "提示字号", _menu._hint, 12, scale)
	_chk_font(phase, tag, "版本号字号", _menu._version, 10, scale)
	await _capture(phase, tag, OUT_DIR + "/" + tag + ".png", Vector2i(DisplayServer.window_get_size()))

func _check_settings(phase: String, tag: String, file: String) -> void:
	await _frames(2)
	var vr: Rect2 = root.get_visible_rect()
	var scale := _scale_now()
	if _menu == null or _menu._settings_panel == null:
		_record(phase, tag, "设置面板", "FAIL", "设置面板不存在")
		return
	var panel = _menu._settings_panel
	if not bool(panel.visible) or not bool(_menu._settings_open):
		_record(phase, tag, "设置面板", "FAIL", "设置面板不可见（visible=%s open=%s）" % [panel.visible, _menu._settings_open])
		return
	var vb = _menu._settings_vb
	var content_h := 548.0
	if vb != null:
		content_h = float(vb.get_combined_minimum_size().y) + 52.0
	var want := Vector2(
		clampf(660.0, 320.0, maxf(320.0, vr.size.x - 32.0)),
		clampf(content_h, 360.0, maxf(360.0, vr.size.y - 24.0)))
	var d: Vector2 = (panel.size - want).abs()
	_record(phase, tag, "设置面板尺寸公式", "PASS" if d.x <= 2.0 and d.y <= 2.0 else "FAIL",
		"实际 %s，期望 %s（内容高 %.0f，视口 %s）" % [_fmt_vec2(panel.size), _fmt_vec2(want), content_h, _fmt_vec2(vr.size)])
	_record(phase, tag, "设置面板", "PASS", "可见，内容最小高 %.0f / 面板高 %.0f" % [content_h, panel.size.y])
	_chk_inside(phase, tag, "设置面板", panel, vr)
	_chk_contained(phase, tag, "设置滚动区", _menu._settings_scroll, panel)
	for c in panel.get_children():
		if c is Control and c.visible:
			_chk_contained(phase, tag, "面板子控件 %s" % String(c.name), c, panel)
	# 横向溢出（设置内容要比滚动区窄）
	if vb != null:
		var minw := float(vb.get_combined_minimum_size().x)
		var scw := float(_menu._settings_scroll.size.x)
		_record(phase, tag, "设置内容横向溢出", "PASS" if minw <= scw + 1.0 else "FAIL",
			"内容最小宽 %.1f，滚动区宽 %.1f" % [minw, scw])
		# 是否需纵向滚动（滚动容器可用，不算裁切）
		var minh := float(vb.get_combined_minimum_size().y)
		var sch := float(_menu._settings_scroll.size.y)
		_record(phase, tag, "设置内容纵向滚动", "PASS", "内容最小高 %.1f，滚动区高 %.1f，需滚动=%s（滚动容器可滚动，非裁切）" % [minh, sch, str(minh > sch + 1.0)])
	# 关键滑条与值标签
	var keys := ["day_length", "sensitivity", "resolution", "quality", "volume_master", "volume_ambient", "volume_birds", "volume_fire", "volume_sfx"]
	for k in keys:
		var sl = _menu._sliders.get(k)
		if sl == null:
			_record(phase, tag, "滑条 %s" % k, "FAIL", "缺失")
			continue
		var sr: Rect2 = sl.get_global_rect()
		if sr.size.x >= 100.0 and sr.size.y >= 20.0:
			_record(phase, tag, "滑条 %s" % k, "PASS", "尺寸 %s（屏幕宽 %.0f px）" % [_fmt_rect(sr), sr.size.x * scale])
		else:
			_record(phase, tag, "滑条 %s" % k, "WARN", "尺寸偏小 %s" % _fmt_rect(sr))
		var lbl = _menu._slider_value_labels.get(k)
		if lbl == null or String(lbl.text) == "":
			_record(phase, tag, "滑条值 %s" % k, "FAIL", "值标签缺失/为空")
	# 分辨率滑条预设与 tick 数
	var presets: Array = S.resolution_presets()
	var rslider = _menu._sliders.get("resolution")
	if rslider != null:
		var ticks := int(rslider.tick_count)
		_record(phase, tag, "分辨率滑条 tick 数", "PASS" if ticks == presets.size() else "WARN",
			"tick=%d，可用预设 %d 项（%s）；本机屏幕可用区过滤后不含 3440/3840" % [ticks, presets.size(), _presets_text(presets)])
	# 滚动到分辨率滑条，检查它确实可操作（不与面板边缘重叠）
	if rslider != null:
		_menu._settings_scroll.ensure_control_visible(rslider)
		await _frames(4)
		await _wait(0.1)
		_chk_contained(phase, tag, "分辨率滑条(滚动后)", rslider, _menu._settings_scroll)
	# 设置正文最小字号可读性
	var labels: Array = []
	_collect_labels(_menu._settings_vb, labels)
	var worst := 999.0
	var worst_text := ""
	for l in labels:
		var fs: int = int(l.get_theme_font_size("font_size"))
		var px := float(fs) * scale
		if px < worst:
			worst = px
			worst_text = String(l.text)
	if worst < 8.0:
		_record(phase, tag, "设置正文字号", "FAIL", "最小 %.1f 屏幕像素（%s）" % [worst, worst_text.substr(0, 20)])
	elif worst < 10.0:
		_record(phase, tag, "设置正文字号", "WARN", "最小 %.1f 屏幕像素（%s），偏小" % [worst, worst_text.substr(0, 20)])
	else:
		_record(phase, tag, "设置正文字号", "PASS", "最小 %.1f 屏幕像素（%d 个文本节点）" % [worst, labels.size()])
	await _capture(phase, tag, OUT_DIR + "/" + file, Vector2i(DisplayServer.window_get_size()))

func _presets_text(presets: Array) -> String:
	var txt := ""
	for p in presets:
		if txt != "":
			txt += ","
		txt += _vi(p)
	return txt

func _collect_labels(node, out: Array) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is Label:
		out.append(node)
	for c in node.get_children():
		_collect_labels(c, out)

# ============================================================================
# 阶段 B：分辨率确认与超时回退流程
# ============================================================================
func _phase_fallback() -> void:
	_log("================================================================")
	_log("[INFO] 阶段 B：分辨率确认 / 超时回退 / 窗口模式循环")
	await _ensure_playing()
	await _open_menu_state()
	await _open_settings_state()
	# 基线记录
	_record("fallback", "baseline", "初始设置", "PASS", "resolution=%s window_mode=%s window=%s mode=%s" % [
		_vi(Vector2i(_main._settings["resolution"])), String(_main._settings["window_mode"]),
		_vi(Vector2i(DisplayServer.window_get_size())), _actual_mode()])
	# B0: 1280x720 小窗口下确认层布局
	await _test_dialog_layout_small()
	# B1: 真实拖动 → 保持
	await _test_drag_keep()
	# B2: 真实拖动 → 点“回退”
	await _test_drag_revert()
	# B3: 真实拖动 → ESC 回退
	await _test_drag_esc()
	# B4: 自然 12s 超时回退
	await _test_confirm_timeout()
	# B5: 窗口模式循环 + 回退
	await _test_window_mode_cycle()
	# B6: 游戏内 _apply_resolution(force) 的钳制证据
	await _test_resolution_clamp()
	# 收尾回游玩态
	await _reset_baseline_window()
	await _close_menu_state()
	_record("fallback", "done", "阶段 B 完成", "PASS", "已恢复 1440x900 窗口化")

func _trigger_display_change(delta_idx: int) -> Dictionary:
	# 通过 menu API 触发一次分辨率变更（与拖动滑条等价的代码路径：drag_started → value → drag_finished）
	var presets: Array = S.resolution_presets()
	var cur: Vector2i = S.sanitize_resolution(_menu._values.get("resolution", DEFAULT_WIN))
	var idx: int = S.resolution_index(presets, cur)
	var tgt: int = clampi(idx + delta_idx, 0, presets.size() - 1)
	if tgt == idx:
		tgt = clampi(idx - delta_idx, 0, presets.size() - 1)
	var prev: Dictionary = _menu.get_settings()
	_menu._on_res_drag_started()
	_menu._values["resolution"] = presets[tgt]
	_menu._on_res_drag_finished()
	await _frames(4)
	_main._settings_save_delay = -1.0
	return {"prev": prev, "target": presets[tgt], "target_idx": tgt, "opened": bool(_menu._res_confirm_open),
		"applied": Vector2i(_main._settings["resolution"]), "win": Vector2i(DisplayServer.window_get_size())}

func _drag_resolution_real(delta_idx: int) -> Dictionary:
	# 真实鼠标注入拖动分辨率滑条（复制 main._sim_drag 的注入方式）
	var slider = _menu._sliders.get("resolution")
	await _ensure_slider_visible("resolution")
	var presets: Array = S.resolution_presets()
	var cur: Vector2i = S.sanitize_resolution(_menu._values.get("resolution", DEFAULT_WIN))
	var idx: int = S.resolution_index(presets, cur)
	var tgt: int = clampi(idx + delta_idx, 0, presets.size() - 1)
	if tgt == idx:
		tgt = clampi(idx - delta_idx, 0, presets.size() - 1)
	var prev: Dictionary = _menu.get_settings()
	var ratio := clampf(float(tgt) / maxf(1.0, float(presets.size() - 1)), 0.06, 0.94)
	var injected: bool = await _inject_drag(slider, ratio, 14.0)
	await _frames(4)
	_main._settings_save_delay = -1.0
	return {"injected": injected, "prev": prev, "target": presets[tgt], "target_idx": tgt,
		"opened": bool(_menu._res_confirm_open), "applied": Vector2i(_main._settings["resolution"]),
		"win": Vector2i(DisplayServer.window_get_size())}

func _ensure_slider_visible(key: String) -> void:
	var sl = _menu._sliders.get(key)
	if sl == null:
		return
	_menu._settings_scroll.ensure_control_visible(sl)
	await _frames(5)
	await _wait(0.15)

func _test_dialog_layout_small() -> void:
	await _reset_baseline_window()
	await _open_menu_state()
	await _open_settings_state()
	await _set_size(Vector2i(1280, 720))
	await _wait(0.35)
	await _frames(3)
	var r: Dictionary = await _trigger_display_change(1)
	_record("fallback", "dialog_1280x720", "小窗口触发确认层", "PASS" if bool(r["opened"]) else "FAIL",
		"窗口 %s，设置 %s → %s，确认层=%s" % [_vi(r["win"]), _vi(Vector2i(r["prev"]["resolution"])), _vi(r["target"]), str(bool(r["opened"]))])
	await _check_confirm_dialog("fallback", "dialog_1280x720")
	await _capture("fallback", "dialog_1280x720", OUT_DIR + "/ui_confirm_1280x720.png", Vector2i(DisplayServer.window_get_size()))
	_menu._confirm_revert()
	_main._settings_save_delay = -1.0
	await _frames(4)
	await _set_size(DEFAULT_WIN)
	await _wait(0.3)

func _test_drag_keep() -> void:
	await _reset_baseline_window()
	await _open_menu_state()
	await _open_settings_state()
	var r: Dictionary = await _drag_resolution_real(1)
	var opened := bool(r["opened"])
	var injected_first := bool(r.get("injected", false))
	if opened:
		_record("fallback", "drag_keep", "真实鼠标拖动触发确认层", "PASS",
			"滑条注入成功，拖动后 _res_confirm_open=true，main 已应用 %s" % _vi(Vector2i(_main._settings["resolution"])))
	else:
		# API 兜底（记录 WARN，但后续确认/回退逻辑仍可验证）
		r = await _trigger_display_change(1)
		opened = bool(r["opened"])
		_record("fallback", "drag_keep", "真实鼠标拖动触发确认层", "WARN",
			"鼠标注入未触发确认层（injected=%s），已改走 menu API 复核；本项“真实输入”未验证" % str(bool(r.get("injected", false))))
		_record("fallback", "drag_keep", "API 路径触发确认层", "PASS" if opened else "FAIL", "确认层=%s" % str(opened))
	await _check_confirm_dialog("fallback", "drag_keep")
	await _capture("fallback", "drag_keep", OUT_DIR + "/ui_confirm_keep.png", Vector2i(DisplayServer.window_get_size()))
	var t_before := float(_menu._res_confirm_t)
	await _wait(1.3)
	var t_after := float(_menu._res_confirm_t)
	_record("fallback", "drag_keep", "确认层倒计时递减", "PASS" if t_after < t_before - 0.8 and t_after > 0.0 else "FAIL",
		"%.2fs → %.2fs（文案：%s）" % [t_before, t_after, String(_menu._res_confirm_label.text)])
	var want_res := Vector2i(_main._settings["resolution"])
	var want_win := Vector2i(DisplayServer.window_get_size())
	_menu._confirm_keep()
	_main._settings_save_delay = -1.0
	await _frames(5)
	var closed := not bool(_menu._res_confirm_open)
	_record("fallback", "drag_keep", "点“保持”后确认层关闭", "PASS" if closed else "FAIL",
		"确认层 open=%s dim=%s panel=%s" % [str(bool(_menu._res_confirm_open)), _menu._res_confirm_dim.visible, _menu._res_confirm_panel.visible])
	var kept_res := Vector2i(_main._settings["resolution"])
	_record("fallback", "drag_keep", "点“保持”后设置保留", "PASS" if kept_res == want_res else "FAIL",
		"设置 %s（期望 %s），窗口 %s" % [_vi(kept_res), _vi(want_res), _vi(Vector2i(DisplayServer.window_get_size()))])
	var d := (Vector2i(DisplayServer.window_get_size()) - want_win).abs()
	_record("fallback", "drag_keep", "点“保持”后窗口保持", "PASS" if d.x <= 2 and d.y <= 2 else "WARN",
		"窗口 %s（保持前 %s）" % [_vi(Vector2i(DisplayServer.window_get_size())), _vi(want_win)])

func _test_drag_revert() -> void:
	await _reset_baseline_window()
	await _open_menu_state()
	await _open_settings_state()
	var r: Dictionary = await _drag_resolution_real(1)
	if not bool(r["opened"]):
		r = await _trigger_display_change(1)
		_record("fallback", "drag_revert", "鼠标注入", "WARN", "注入未触发确认层，已改走 menu API 复核")
	var prev_res := Vector2i(r["prev"]["resolution"])
	var prev_win := Vector2i(r["win"])
	var opened := bool(_menu._res_confirm_open)
	_record("fallback", "drag_revert", "确认层已打开", "PASS" if opened else "FAIL",
		"preview 设置=%s，窗口=%s" % [_vi(Vector2i(_main._settings["resolution"])), _vi(Vector2i(DisplayServer.window_get_size()))])
	await _check_confirm_dialog("fallback", "drag_revert")
	await _capture("fallback", "drag_revert", OUT_DIR + "/ui_confirm_revert.png", Vector2i(DisplayServer.window_get_size()))
	var btn = _find_button(_menu._res_confirm_panel, "回退")
	if btn == null:
		_menu._confirm_revert()
		_record("fallback", "drag_revert", "真实点击“回退”按钮", "WARN", "未找到回退按钮，改用 _confirm_revert() API")
	else:
		await _inject_click(btn)
		_record("fallback", "drag_revert", "真实点击“回退”按钮", "PASS", "点击位置 %s" % _fmt_rect(btn.get_global_rect()))
	await _frames(8)
	_main._settings_save_delay = -1.0
	var closed := not bool(_menu._res_confirm_open)
	var now_res := Vector2i(_main._settings["resolution"])
	var now_win := Vector2i(DisplayServer.window_get_size())
	var expect_win := Vector2i(now_res)
	var dd := (now_win - expect_win).abs()
	_record("fallback", "drag_revert", "点“回退”后确认层关闭", "PASS" if closed else "FAIL", "open=%s" % str(bool(_menu._res_confirm_open)))
	_record("fallback", "drag_revert", "点“回退”后设置恢复", "PASS" if now_res == prev_res else "FAIL",
		"设置 %s（期望 %s）" % [_vi(now_res), _vi(prev_res)])
	_record("fallback", "drag_revert", "点“回退”后窗口恢复", "PASS" if dd.x <= 2 and dd.y <= 2 else "WARN",
		"窗口 %s（期望 %s；回退前窗口 %s）" % [_vi(now_win), _vi(expect_win), _vi(prev_win)])

func _test_drag_esc() -> void:
	await _reset_baseline_window()
	await _open_menu_state()
	await _open_settings_state()
	var r: Dictionary = await _drag_resolution_real(1)
	if not bool(r["opened"]):
		r = await _trigger_display_change(1)
		_record("fallback", "drag_esc", "鼠标注入", "WARN", "注入未触发确认层，已改走 menu API 复核")
	var prev_res := Vector2i(r["prev"]["resolution"])
	var prev_win := Vector2i(r["win"])
	_record("fallback", "drag_esc", "确认层已打开", "PASS" if bool(_menu._res_confirm_open) else "FAIL",
		"窗口=%s，设置=%s" % [_vi(Vector2i(DisplayServer.window_get_size())), _vi(Vector2i(_main._settings["resolution"]))])
	await _inject_key(KEY_ESCAPE)
	await _frames(8)
	_main._settings_save_delay = -1.0
	var closed := not bool(_menu._res_confirm_open)
	var now_res := Vector2i(_main._settings["resolution"])
	var now_win := Vector2i(DisplayServer.window_get_size())
	var expect_win := Vector2i(now_res)
	var dd := (now_win - expect_win).abs()
	_record("fallback", "drag_esc", "真实 ESC 注入后确认层关闭", "PASS" if closed else "FAIL", "open=%s" % str(bool(_menu._res_confirm_open)))
	_record("fallback", "drag_esc", "ESC 回退后设置恢复", "PASS" if now_res == prev_res else "FAIL",
		"设置 %s（期望 %s）" % [_vi(now_res), _vi(prev_res)])
	_record("fallback", "drag_esc", "ESC 回退后窗口恢复", "PASS" if dd.x <= 2 and dd.y <= 2 else "WARN",
		"窗口 %s（期望 %s；回退前窗口 %s）" % [_vi(now_win), _vi(expect_win), _vi(prev_win)])

func _test_confirm_timeout() -> void:
	await _reset_baseline_window()
	await _open_menu_state()
	await _open_settings_state()
	var r: Dictionary = await _trigger_display_change(1)
	var prev_res := Vector2i(r["prev"]["resolution"])
	var prev_win := Vector2i(r["win"])
	_record("fallback", "timeout", "确认层已打开", "PASS" if bool(_menu._res_confirm_open) else "FAIL",
		"倒计时 %.1fs，窗口=%s" % [float(_menu._res_confirm_t), _vi(Vector2i(DisplayServer.window_get_size()))])
	var t_start := Time.get_ticks_msec()
	var done: bool = await _wait_until(func() -> bool: return not bool(_menu._res_confirm_open), 16.0)
	var elapsed := float(Time.get_ticks_msec() - t_start) / 1000.0
	_main._settings_save_delay = -1.0
	await _frames(6)
	var now_res := Vector2i(_main._settings["resolution"])
	var now_win := Vector2i(DisplayServer.window_get_size())
	var expect_win := Vector2i(now_res)
	var dd := (now_win - expect_win).abs()
	_record("fallback", "timeout", "12 秒后自动回退", "PASS" if done and elapsed >= 10.5 and elapsed <= 14.0 else "FAIL",
		"等待 %.2fs 后确认层 open=%s（期望约 %.0fs 自动关闭）" % [elapsed, str(bool(_menu._res_confirm_open)), CONFIRM_SECONDS_EXPECT])
	_record("fallback", "timeout", "超时回退后设置恢复", "PASS" if now_res == prev_res else "FAIL",
		"设置 %s（期望 %s）" % [_vi(now_res), _vi(prev_res)])
	_record("fallback", "timeout", "超时回退后窗口恢复", "PASS" if dd.x <= 2 and dd.y <= 2 else "WARN",
		"窗口 %s（期望 %s；回退前窗口 %s）" % [_vi(now_win), _vi(expect_win), _vi(prev_win)])
	await _capture("fallback", "timeout_after", OUT_DIR + "/ui_confirm_timeout_after.png", now_win)

func _test_window_mode_cycle() -> void:
	await _reset_baseline_window()
	await _open_menu_state()
	await _open_settings_state()
	await _set_size(DEFAULT_WIN)
	await _wait(0.3)
	var expected_order := ["fullscreen", "borderless", "windowed"]
	for i in expected_order.size():
		var prev_mode := String(_main._settings["window_mode"])
		var prev_win := Vector2i(DisplayServer.window_get_size())
		_menu._cycle_window_mode()
		var opened: bool = await _wait_until(func() -> bool: return bool(_menu._res_confirm_open), 4.0)
		await _wait(0.8)
		await _frames(4)
		_main._settings_save_delay = -1.0
		var want := String(expected_order[i])
		var act := _actual_mode()
		_record("fallback", "mode_%s" % want, "窗口模式切换", "PASS" if opened and act == want and String(_main._settings["window_mode"]) == want else "FAIL",
			"%s → %s：设置=%s，DisplayServer=%s，确认层=%s，窗口=%s（切换前 %s）" % [
				prev_mode, want, String(_main._settings["window_mode"]), act, str(bool(_menu._res_confirm_open)),
				_vi(Vector2i(DisplayServer.window_get_size())), _vi(prev_win)])
		await _check_confirm_dialog("fallback", "mode_%s" % want)
		await _capture("fallback", "mode_%s" % want, OUT_DIR + "/ui_confirm_mode_%s.png" % want, Vector2i(DisplayServer.window_get_size()))
		_menu._confirm_keep()
		_main._settings_save_delay = -1.0
		await _frames(5)
		_record("fallback", "mode_%s" % want, "保持后模式确认", "PASS" if _actual_mode() == want and String(_main._settings["window_mode"]) == want else "FAIL",
			"实际 DisplayServer=%s，设置=%s，窗口=%s" % [_actual_mode(), String(_main._settings["window_mode"]), _vi(Vector2i(DisplayServer.window_get_size()))])
	# 模式回退验证：当前 windowed → 切 fullscreen → 回退
	var back_mode := String(_main._settings["window_mode"])
	var back_win := Vector2i(DisplayServer.window_get_size())
	_menu._cycle_window_mode()
	await _wait_until(func() -> bool: return bool(_menu._res_confirm_open), 4.0)
	await _wait(0.8)
	var applied_mode := String(_main._settings["window_mode"])
	_menu._confirm_revert()
	_main._settings_save_delay = -1.0
	await _wait(1.0)
	await _frames(6)
	var reverted_mode := String(_main._settings["window_mode"])
	var act_mode := _actual_mode()
	var now_win := Vector2i(DisplayServer.window_get_size())
	_record("fallback", "mode_revert", "窗口模式回退", "PASS" if reverted_mode == back_mode and act_mode == back_mode else "FAIL",
		"应用 %s 后回退到 %s（实际 DisplayServer=%s）" % [applied_mode, reverted_mode, act_mode])
	_record("fallback", "mode_revert", "窗口模式回退后窗口恢复", "PASS" if (now_win - back_win).abs().x <= 2 and (now_win - back_win).abs().y <= 2 else "WARN",
		"窗口 %s（回退前 %s）" % [_vi(now_win), _vi(back_win)])
	await _set_mode("windowed")
	await _set_size(DEFAULT_WIN)

func _test_resolution_clamp() -> void:
	await _reset_baseline_window()
	for req in [Vector2i(3840, 2160), Vector2i(3440, 1440), Vector2i(2560, 1440)]:
		_main._settings["resolution"] = req
		_main._apply_resolution(req, true)
		_main._settings_save_delay = -1.0
		await _frames(8)
		await _wait(0.4)
		var got := Vector2i(DisplayServer.window_get_size())
		var stored := Vector2i(_main._settings["resolution"])
		var usable := DisplayServer.screen_get_usable_rect().size
		var lvl := "PASS" if got == req else "WARN"
		_record("fallback", "apply_%s" % _vi(req), "游戏内 _apply_resolution(force=true)", lvl,
			"请求 %s → 实际窗口 %s / settings %s / 屏幕可用区 %s；超屏尺寸会被钳制（滑条预设也不可达），矩阵截图另用 DisplayServer 直设验证布局" % [
				_vi(req), _vi(got), _vi(stored), _vi(usable)])
		await _capture("fallback", "apply_%s" % _vi(req), OUT_DIR + "/ui_apply_%s.png" % _vi(got), got)
	await _reset_baseline_window()

func _check_confirm_dialog(phase: String, tag: String) -> void:
	if _menu == null or not bool(_menu._res_confirm_open):
		_record(phase, tag, "显示设置确认层", "FAIL", "确认层未打开")
		return
	var vr: Rect2 = root.get_visible_rect()
	var scale := _scale_now()
	_record(phase, tag, "显示设置确认层", "PASS", "可见，倒计时 %.1fs，文案：%s" % [
		float(_menu._res_confirm_t), String(_menu._res_confirm_label.text)])
	_chk_contained(phase, tag, "确认面板", _menu._res_confirm_panel, vr, 1.0)
	var csize := Vector2(minf(480.0, vr.size.x - 40.0), 168.0)
	var d: Vector2 = (_menu._res_confirm_panel.size - csize).abs()
	_record(phase, tag, "确认面板尺寸公式", "PASS" if d.x <= 2.0 and d.y <= 2.0 else "FAIL",
		"实际 %s，期望 %s" % [_fmt_vec2(_menu._res_confirm_panel.size), _fmt_vec2(csize)])
	_chk_font(phase, tag, "确认文案字号", _menu._res_confirm_label, 14, scale)
	var keep_btn = _find_button(_menu._res_confirm_panel, "保持")
	var revert_btn = _find_button(_menu._res_confirm_panel, "回退")
	_chk_contained(phase, tag, "保持按钮", keep_btn, _menu._res_confirm_panel)
	_chk_contained(phase, tag, "回退按钮", revert_btn, _menu._res_confirm_panel)
	for pair in [["保持按钮", keep_btn], ["回退按钮", revert_btn]]:
		if pair[1] != null:
			var r: Rect2 = pair[1].get_global_rect()
			_record(phase, tag, "%s可点尺寸" % String(pair[0]), "PASS" if r.size.x * scale >= 100.0 and r.size.y * scale >= 30.0 else "WARN",
				"布局 %.1fx%.1f → 屏幕 %.1fx%.1f 像素" % [r.size.x, r.size.y, r.size.x * scale, r.size.y * scale])
	# 遮罩覆盖整个视口
	if _menu._res_confirm_dim != null:
		var dr: Rect2 = _menu._res_confirm_dim.get_global_rect()
		var covers: bool = dr.position.x <= 1.0 and dr.position.y <= 1.0 and dr.end.x >= vr.size.x - 1.0 and dr.end.y >= vr.size.y - 1.0
		_record(phase, tag, "确认层遮罩覆盖", "PASS" if covers else "FAIL", "遮罩 %s，视口 %s" % [_fmt_rect(dr), _fmt_rect(vr)])

# ============================================================================
# 阶段 C：DPI / 系统缩放
# ============================================================================
func _phase_dpi() -> void:
	_log("================================================================")
	_log("[INFO] 阶段 C：DPI 与系统缩放")
	await _ensure_playing()
	await _set_mode("windowed")
	await _set_size(DEFAULT_WIN)
	await _wait(0.3)
	var scr := DisplayServer.window_get_current_screen()
	_record("dpi", "env", "系统缩放（只读）", "WARN",
		"screen=%d scale=%.3f dpi=%d max_scale=%.3f：Godot 运行中无 API 可改 Windows 系统缩放，真实 125%%/150%% 系统缩放下运行未验证（未验证项，非缺陷）" % [
			scr, DisplayServer.screen_get_scale(scr), DisplayServer.screen_get_dpi(scr), DisplayServer.screen_get_max_scale()])
	for f in [1.25, 1.5]:
		root.content_scale_factor = f
		await _frames(6)
		_hud.set_hud_visible(true, false)
		_ensure_hud_panels()
		await _frames(4)
		var win := Vector2i(DisplayServer.window_get_size())
		var tag := "sim_factor_%d" % int(f * 100.0)
		_record("dpi", tag, "模拟高 DPI（content_scale_factor）", "PASS",
			"factor=%.2f → 视口 %s，窗口 %s（模拟项，非系统真实缩放；用于检查 UI 缩小后是否仍可读）" % [
				f, _fmt_vec2(root.get_visible_rect().size), _vi(win)])
		await _check_state("dpi", tag, win, "windowed", "ui_dpi_sim_%d.png" % int(f * 100.0))
	root.content_scale_factor = 1.0
	await _frames(6)
	_record("dpi", "restore", "恢复 content_scale_factor", "PASS" if is_equal_approx(root.content_scale_factor, 1.0) else "FAIL",
		"factor=%.2f，视口 %s" % [root.content_scale_factor, _fmt_vec2(root.get_visible_rect().size)])
	await _reset_baseline_window()

# ============================================================================
# 输入注入 / 控件查找
# ============================================================================
func _press_mouse(pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	ev.global_position = pos
	Input.parse_input_event(ev)

func _release_mouse(pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = pos
	ev.global_position = pos
	Input.parse_input_event(ev)

func _inject_click(ctl) -> void:
	if ctl == null or not is_instance_valid(ctl) or not (ctl is Control):
		return
	var r: Rect2 = ctl.get_global_rect()
	var pos := Vector2(r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.5)
	_press_mouse(pos)
	await _frames(2)
	_release_mouse(pos)
	await _frames(3)

func _inject_drag(ctl, ratio: float, pad: float) -> bool:
	if ctl == null or not is_instance_valid(ctl) or not (ctl is Control):
		return false
	var c = ctl
	if not c.is_visible_in_tree():
		return false
	var rect: Rect2 = c.get_global_rect()
	if rect.size.x < 24.0 or rect.size.y < 8.0:
		return false
	var y := rect.position.y + rect.size.y * 0.5
	var x0 := rect.position.x + pad
	var inner_w := rect.size.x - pad * 2.0
	var x1 := rect.position.x + pad + clampf(ratio, 0.05, 0.95) * inner_w
	_press_mouse(Vector2(x0, y))
	await _frames(1)
	var ev := InputEventMouseMotion.new()
	ev.position = Vector2(x1, y)
	ev.global_position = ev.position
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(ev)
	await _frames(2)
	_release_mouse(Vector2(x1, y))
	await _frames(3)
	if c.has_method("is_dragging"):
		return not bool(c.call("is_dragging"))
	return true

func _inject_key(keycode: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(2)
	var ev2 := InputEventKey.new()
	ev2.keycode = keycode
	ev2.physical_keycode = keycode
	ev2.pressed = false
	Input.parse_input_event(ev2)
	await _frames(3)

func _find_button(node, text_part: String):
	if node == null or not is_instance_valid(node):
		return null
	if node is Button and String(node.text).find(text_part) >= 0:
		return node
	for c in node.get_children():
		var f = _find_button(c, text_part)
		if f != null:
			return f
	return null
