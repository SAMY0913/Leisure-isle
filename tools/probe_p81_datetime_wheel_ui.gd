extends SceneTree
## P8.1-07 第二阶段端到端 UI 验收探针（真实窗口，非 headless）。
## 归属：teammate wind-ui / 共享任务 task-12。只新增本文件；不修改正式游戏逻辑。
## 运行：
##   D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe \
##       --path D:/休闲小岛幻境/游戏工程 --script res://tools/probe_p81_datetime_wheel_ui.gd
## 覆盖：计划 §10 UI1-UI10 + 第一阶段未验证 U01-U11。
## 输出：开发产物/p82/05_wheel/p81_ui_regression/（P8.2 起改到 p82 证据目录，避免覆盖 P8.1 历史证据）
## 纪律：不写 user://（_settings_save_delay 固定 -1 并逐次重置）；不改 main.gd；
##       不改 开发产物/p8 与 开发产物/p81 冻结证据；退出码 0=全 PASS（WARN 不算失败），1=有 FAIL。

const Cal := preload("res://scripts/isle_calendar.gd")
const OUT_DIR := "D:/休闲小岛幻境/开发产物/p82/05_wheel/p81_ui_regression"
const LOG_PATH := OUT_DIR + "/probe_p81_datetime_wheel_ui.log"
const JSON_PATH := OUT_DIR + "/probe_p81_datetime_wheel_ui_result.json"
const RES_A := Vector2i(1440, 900)
const RES_B := Vector2i(1600, 900)
const FIVE := ["year", "month", "day", "hour", "minute"]
const FIELDS := ["year", "month", "day", "hour", "minute"]
const COL_WIDTHS := [68, 46, 46, 46, 46]
const ROW_H := 28.0
const IDLE_LIMIT := 14.0

var _main = null
var _hud = null
var _wheel = null
var _checks: Array = []
var _shots: Array = []
var _lines: Array = []
var _passes := 0
var _warns := 0
var _fails := 0
var _jump_count := 0
var _jump_args: Array = []
var _t0 := 0
var _env: Dictionary = {}
var _cfg_mtime := -1
var _diag := false

# ============================================================
# 入口
# ============================================================

func _initialize() -> void:
	_t0 = Time.get_ticks_msec()
	for a in OS.get_cmdline_user_args():
		if String(a).contains("diag"):
			_diag = true
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_log("================================================================")
	_log("[ENV] probe_p81_datetime_wheel_ui / task-12 / wind-ui")
	_log("[ENV] godot=%s os=%s display_server=%s" % [
		Engine.get_version_info().get("string", "?"), OS.get_name(), DisplayServer.get_name()])
	if DisplayServer.get_name() == "headless":
		_record("env", "-", "显示服务器", "FAIL", "headless 模式无法做真实窗口 UI 验收；请去掉 --headless 重跑")
		_finish()
		return
	await _collect_env()
	# 启动若全屏先转窗口化，保证 window_set_size 生效
	if DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		await _frames(3)
	await _load_main()
	if _main == null:
		_finish()
		return
	_main._settings_save_delay = -1.0
	await _force_baseline()
	await _ensure_playing()
	if _hud == null:
		_record("env", "-", "HUD 实例", "FAIL", "HUD 为空，无法继续")
		_finish()
		return
	_hud.datetime_jump_requested.connect(_on_jump_sig)
	await _wait(0.4)
	if _diag:
		await _diag_controls()
		_finish()
		return
	await _ui1()
	await _ui2()
	await _ui3()
	await _ui4()
	await _ui5()
	await _ui6()
	await _ui7()
	await _ui8()
	await _ui9()
	await _ui10()
	await _u01()
	await _u03()
	await _u04()
	await _phase_b()
	await _cleanup()
	_finish()

# ============================================================
# 环境 / 加载 / 基线
# ============================================================

func _collect_env() -> void:
	var scr := DisplayServer.get_screen_count()
	for i in scr:
		_log("[ENV] screen%d size=%s usable=%s scale=%.3f dpi=%d max_scale=%.3f" % [
			i, _vi(DisplayServer.screen_get_size(i)), _vi(DisplayServer.screen_get_usable_rect(i).size),
			DisplayServer.screen_get_scale(i), DisplayServer.screen_get_dpi(i),
			DisplayServer.screen_get_max_scale()])
	_log("[ENV] window=%s mode=%s visible_rect=%s content_scale(size=%s factor=%.3f mode=%d aspect=%d)" % [
		_vi(Vector2i(DisplayServer.window_get_size())), _actual_mode(),
		_fmt_vec2(root.get_visible_rect().size), _vi(root.content_scale_size),
		root.content_scale_factor, root.content_scale_mode, root.content_scale_aspect])
	_env = {
		"godot": Engine.get_version_info().get("string", "?"),
		"os": OS.get_name(),
		"display_server": DisplayServer.get_name(),
		"screen_size": _vi(DisplayServer.screen_get_size()),
		"screen_usable": _vi(DisplayServer.screen_get_usable_rect().size),
		"screen_scale": DisplayServer.screen_get_scale(),
		"screen_dpi": DisplayServer.screen_get_dpi(),
		"screen_max_scale": DisplayServer.screen_get_max_scale(),
	}
	_cfg_mtime = int(FileAccess.get_modified_time("user://settings.cfg"))
	await _frames(1)

func _load_main() -> void:
	_main = root.get_node_or_null("Isle")
	if _main == null:
		_log("[INFO] 场景无 Isle 节点，加载 res://isle.tscn ...（程序化生成可能耗时）")
		var t0 := Time.get_ticks_msec()
		var ps: PackedScene = load("res://isle.tscn")
		if ps == null:
			_record("env", "-", "加载 isle.tscn", "FAIL", "PackedScene 为空")
			return
		root.add_child(ps.instantiate())
		_main = root.get_node_or_null("Isle")
		if _main == null:
			_record("env", "-", "加载 isle.tscn", "FAIL", "实例化后找不到 Isle 根节点")
			return
		_log("[INFO] isle.tscn 已加入场景树（%.1fs）" % (float(Time.get_ticks_msec() - t0) / 1000.0))
	var waited := 0.0
	var last_report := 0
	while (_main._hud == null or _main._menu == null) and waited < 120.0:
		await _wait(0.25)
		waited += 0.25
		var r := int(waited * 4.0)
		if r - last_report >= 20:
			last_report = r
			_log("[INFO] 等待 HUD/菜单... %.0fs" % waited)
	if _main._hud == null or _main._menu == null:
		_record("env", "-", "HUD/菜单实例", "FAIL", "HUD=%s menu=%s" % [str(_main._hud), str(_main._menu)])
		return
	_hud = _main._hud
	await _frames(8)
	await _wait(0.8)
	_log("[ENV] HUD 就绪：hud=%s 节点数=%d" % [str(_hud.name), _count_nodes(_hud)])

func _count_nodes(n) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count_nodes(ch)
	return c

func _force_baseline() -> void:
	if _main == null:
		return
	_main._settings["time_source"] = "sim"
	_main._settings["window_mode"] = "windowed"
	_main._settings["resolution"] = RES_A
	_main._settings["auto_orbit"] = false
	_main._settings_save_delay = -1.0
	_main._apply_user_settings(false)
	_main._settings_save_delay = -1.0
	_main._auto_orbit = false
	await _frames(4)
	await _set_mode("windowed")
	await _set_size(RES_A)
	await _wait(0.3)
	_main._settings_save_delay = -1.0
	_log("[ENV] 基线：window=%s mode=%s visible_rect=%s scale_now=%.3f" % [
		_vi(Vector2i(DisplayServer.window_get_size())), _actual_mode(),
		_fmt_vec2(root.get_visible_rect().size), _scale_now()])

func _ensure_playing() -> void:
	if _main == null:
		return
	if int(_main._mode) == 0:
		_log("[INFO] 进入游玩状态（_on_menu_start）...")
		_main._on_menu_start(bool(_main._started))
		var ok: bool = await _wait_until(func() -> bool:
			return int(_main._mode) == 1 and String(_main._blending) == "", 90.0)
		_log("[INFO] 游玩状态就绪=%s（_mode=%d _blending=%s）" % [str(ok), int(_main._mode), String(_main._blending)])
		await _wait(0.4)
	_main._paused = true
	_main._auto_orbit = false
	_main._settings["auto_orbit"] = false
	_main._settings_save_delay = -1.0
	_main._set_time_of_day(12 * 60 + 20)
	_hud.set_hud_visible(true, false)
	await _frames(3)

# ============================================================
# 日志 / 记录 / 收尾
# ============================================================

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

func _pass(phase: String, name: String, detail: String) -> void:
	_record(phase, "check", name, "PASS", detail)

func _warn(phase: String, name: String, detail: String) -> void:
	_record(phase, "check", name, "WARN", detail)

func _fail(phase: String, name: String, detail: String) -> void:
	_record(phase, "check", name, "FAIL", detail)

func _check(phase: String, name: String, cond: bool, detail: String) -> void:
	if cond:
		_pass(phase, name, detail)
	else:
		_fail(phase, name, detail)

func _finish() -> void:
	var dur := float(Time.get_ticks_msec() - _t0) / 1000.0
	_log("================================================================")
	for c in _checks:
		if c["result"] == "FAIL":
			_log("[FAIL-SUMMARY] %s/%s %s：%s" % [c["phase"], c["tag"], c["name"], c["detail"]])
	_log("[SUMMARY] total=%d pass=%d warn=%d fail=%d shots=%d 耗时=%.1fs" % [
		_checks.size(), _passes, _warns, _fails, _shots.size(), dur])
	var data := {
		"probe": "probe_p81_datetime_wheel_ui",
		"owner": "wind-ui / task-12",
		"started_at": Time.get_datetime_string_from_system(true),
		"duration_sec": dur,
		"env": _env,
		"summary": {"total": _checks.size(), "pass": _passes, "warn": _warns, "fail": _fails},
		"checks": _checks,
		"shots": _shots,
	}
	var f := FileAccess.open(JSON_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "  "))
		f.close()
		_log("[INFO] 结果 JSON 写入 " + JSON_PATH)
	else:
		_log("[ERROR] 无法写入结果 JSON：" + JSON_PATH)
	var lf := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if lf != null:
		for line in _lines:
			lf.store_line(String(line))
		lf.close()
		print("[INFO] 日志写入 " + LOG_PATH)
	quit(1 if _fails > 0 else 0)

# ============================================================
# 基础工具
# ============================================================

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
	if DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]:
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
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	await _frames(4)

func _set_size(res: Vector2i) -> void:
	if DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		await _frames(3)
	DisplayServer.window_set_size(res)
	await _frames(4)
	var scr := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(scr)
	if usable.size.x >= 640 and usable.size.y >= 360:
		var off := usable.size - res
		DisplayServer.window_set_position(usable.position + Vector2i(int(off.x / 2.0), int(off.y / 2.0)))
		await _frames(2)
	var got := Vector2i(DisplayServer.window_get_size())
	if got != res:
		_log("[INFO] window_set_size(%s) 实际 %s，尝试 root.size" % [_vi(res), _vi(got)])
		root.size = res
		await _frames(4)
		got = Vector2i(DisplayServer.window_get_size())
	if got != res:
		_log("[WARN] 无法把窗口设为 %s（实际 %s），按实际尺寸继续" % [_vi(res), _vi(got)])

# ============================================================
# 截图 / 图像统计
# ============================================================

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

func _band_mean(img: Image, y0: int, y1: int, x0: int, x1: int) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var ya := clampi(y0, 0, h - 1)
	var yb := clampi(y1, ya + 1, h)
	var xa := clampi(x0, 0, w - 1)
	var xb := clampi(x1, xa + 1, w)
	var n := 0
	var sum := 0.0
	for y in range(ya, yb):
		for x in range(xa, xb):
			var c := img.get_pixel(x, y)
			sum += c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
			n += 1
	if n <= 0:
		return 0.0
	return sum / float(n)

## 截取整个窗口；若 crop_canvas 非空，同时保存滚轮区域的裁剪图。
## 返回完整窗口 Image（失败返回 null）。坐标换算：canvas 坐标 * (纹理宽/可见矩形宽)。
func _shot(phase: String, tag: String, path: String, crop_canvas: Rect2 = Rect2()) -> Image:
	await RenderingServer.frame_post_draw
	var tex := root.get_texture()
	var img: Image = tex.get_image() if tex != null else null
	if img == null:
		_record(phase, tag, "截图", "FAIL", "取不到 viewport 纹理：" + path)
		return null
	var stats := _img_stats(img)
	var sz := img.get_size()
	var win := Vector2i(DisplayServer.window_get_size())
	var err := img.save_png(path)
	var line := "%s（纹理 %s，窗口 %s，均值 %.3f，标准差 %.3f，近黑 %.1f%%）" % [
		String(path).get_file(), _vi(sz), _vi(win), float(stats["mean"]), float(stats["std"]), float(stats["dark"]) * 100.0]
	if err == OK:
		_record(phase, tag, "截图", "PASS", line)
		_shots.append(path)
	else:
		_record(phase, tag, "截图", "FAIL", "save_png 失败 err=%d：%s" % [err, line])
		return img
	if float(stats["mean"]) < 0.02 or float(stats["std"]) < 0.01:
		_record(phase, tag, "画面内容", "FAIL", "疑似黑屏/纯色（均值 %.3f，标准差 %.3f）" % [
			float(stats["mean"]), float(stats["std"])])
	elif sz == win:
		_record(phase, tag, "画面内容", "PASS", "非黑屏且纹理==窗口 %s（均值 %.3f，标准差 %.3f）" % [
			_vi(sz), float(stats["mean"]), float(stats["std"])])
	else:
		_record(phase, tag, "画面内容", "WARN", "非黑屏但纹理 %s != 窗口 %s（高 DPI/缩放）" % [_vi(sz), _vi(win)])
	if crop_canvas.size.x >= 2.0 and crop_canvas.size.y >= 2.0:
		var vr: Vector2 = root.get_visible_rect().size
		var k: float = float(sz.x) / maxf(1.0, vr.x)
		var r := Rect2i(
			int(round(crop_canvas.position.x * k)), int(round(crop_canvas.position.y * k)),
			int(round(crop_canvas.size.x * k)), int(round(crop_canvas.size.y * k)))
		r = r.intersection(Rect2i(0, 0, sz.x, sz.y))
		if r.size.x > 2 and r.size.y > 2:
			var crop := img.get_region(r)
			var cpath := String(path).get_basename() + "_wheel.png"
			var e2 := crop.save_png(cpath)
			if e2 == OK:
				_record(phase, tag, "滚轮裁剪截图", "PASS", "%s（%s，缩放 k=%.3f）" % [
					String(cpath).get_file(), _vi(crop.get_size()), k])
				_shots.append(cpath)
			else:
				_record(phase, tag, "滚轮裁剪截图", "FAIL", "裁剪 save_png err=%d：%s" % [e2, cpath])
	return img

# ============================================================
# 状态 / 输入注入辅助
# ============================================================

func _sim() -> float:
	return float(_main._sim_seconds)

func _on_jump_sig(y: int, mo: int, d: int, h: int, mi: int) -> void:
	_jump_count += 1
	_jump_args = [y, mo, d, h, mi]

func _auth_parts() -> Dictionary:
	var d: Dictionary = _main._display_datetime()
	return {
		"year": int(d.get("year", 0)), "month": int(d.get("month", 0)),
		"day": int(d.get("day", 0)), "hour": int(d.get("hour", 0)),
		"minute": int(d.get("minute", 0)),
	}

func _cal_parts() -> Dictionary:
	var p: Dictionary = Cal.parts(_sim())
	return {
		"year": int(p.get("year", 0)), "month": int(p.get("month", 0)),
		"day": int(p.get("day", 0)), "hour": int(p.get("hour", 0)),
		"minute": int(p.get("minute", 0)),
	}

func _wheel_parts() -> Dictionary:
	if _wheel == null:
		return {}
	var p: Dictionary = _wheel.call("get_parts")
	return p

func _eq_parts(a: Dictionary, b: Dictionary) -> bool:
	for k in FIVE:
		if int(a.get(k, -1)) != int(b.get(k, -2)):
			return false
	return true

func _parts_str(p: Dictionary) -> String:
	if p == null or p.is_empty():
		return "(空)"
	return "%04d-%02d-%02d %02d:%02d" % [
		int(p.get("year", 0)), int(p.get("month", 0)), int(p.get("day", 0)),
		int(p.get("hour", 0)), int(p.get("minute", 0))]

func _wheel_col(field: String):
	if _wheel == null:
		return null
	return _wheel.get_node_or_null("Wheel_" + field)

func _col_rect_canvas(field: String) -> Rect2:
	var c = _wheel_col(field)
	if c == null:
		return Rect2()
	return c.get_global_rect()

func _to_win(p: Vector2) -> Vector2:
	return p * _scale_now()

func _press_mouse(pos_win: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos_win
	ev.global_position = pos_win
	Input.parse_input_event(ev)
	_last_mouse = pos_win

var _last_mouse := Vector2.ZERO

func _release_mouse(pos_win: Vector2 = Vector2.INF) -> void:
	var p := _last_mouse if pos_win == Vector2.INF else pos_win
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = p
	ev.global_position = p
	Input.parse_input_event(ev)
	_last_mouse = p

func _motion_mouse(pos_win: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos_win
	ev.global_position = pos_win
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(ev)
	_last_mouse = pos_win

func _inject_click_ctl(ctl) -> bool:
	if ctl == null or not is_instance_valid(ctl) or not (ctl is Control):
		return false
	var c: Control = ctl
	if not c.is_visible_in_tree():
		return false
	var r: Rect2 = c.get_global_rect()
	if r.size.x < 2.0 or r.size.y < 2.0:
		return false
	var pos := _to_win(r.position + r.size * 0.5)
	# 注入前先把真实光标移到目标点：后台/非聚焦窗口下，合成点击的命中测试偶发使用旧 OS 光标位置。
	Input.warp_mouse(pos)
	await _frames(2)
	_press_mouse(pos)
	await _frames(2)
	_release_mouse(pos)
	await _frames(3)
	return true

func _inject_wheel(ctl, up: bool) -> bool:
	if ctl == null or not is_instance_valid(ctl) or not (ctl is Control):
		return false
	var c: Control = ctl
	if not c.is_visible_in_tree():
		return false
	var pos := _to_win(c.get_global_rect().position + c.get_global_rect().size * 0.5)
	Input.warp_mouse(pos)
	await _frames(2)
	var btn := MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	var ev := InputEventMouseButton.new()
	ev.button_index = btn
	ev.pressed = true
	ev.position = pos
	ev.global_position = pos
	Input.parse_input_event(ev)
	await _frames(2)
	var ev2 := InputEventMouseButton.new()
	ev2.button_index = btn
	ev2.pressed = false
	ev2.position = pos
	ev2.global_position = pos
	Input.parse_input_event(ev2)
	await _frames(2)
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

## 在指定列上慢速拖动 rows 行（正=向下拖=值减小；负=向上拖=值增大）。
## 每步 3 帧，速度约 0.66 行/秒，低于 FLICK_THRESHOLD=1.2 → 释放后走弹簧吸附。
func _inject_drag_col(field: String, rows: float, release: bool = true) -> bool:
	var c = _wheel_col(field)
	if c == null or not is_instance_valid(c):
		return false
	var r: Rect2 = c.get_global_rect()
	var start := _to_win(r.position + r.size * 0.5)
	Input.warp_mouse(start)
	await _frames(2)
	_press_mouse(start)
	await _frames(2)
	# 步长按“墙钟时间”拉长：滚轮列用事件间真实 Δt 估算速度，若帧率较高（合成 3 帧≈25ms）
	# 旧 30 步会超过 FLICK_THRESHOLD=1.2 行/秒，释放后惯性滑行导致拖 1 行却跑很多行。
	# 60 步 × 25ms，速度≈0.67 行/秒，稳定落在慢拖区间。
	var steps := 60
	var dy := (rows * ROW_H) / float(steps)
	var p := start
	for i in range(steps):
		p.y += dy * _scale_now()
		_motion_mouse(p)
		await _wait(0.025)
	if release:
		_release_mouse(p)
		await _frames(3)
	return true

func _settle_wheel(timeout: float = 3.0) -> void:
	if _wheel == null:
		return
	await _wait_until(func() -> bool: return not bool(_wheel.call("is_busy")), timeout)

func _keep() -> void:
	if _main != null:
		_main._settings_save_delay = -1.0
	if _hud != null:
		_hud._time_idle = -1000.0

func _open_time_panel() -> void:
	if _hud == null:
		return
	_hud.set_hud_visible(true, false)
	if not bool(_hud._time_open):
		_hud.toggle_time_panel()
	_hud._time_panel.visible = true
	_hud._time_idle = -1000.0
	await _frames(3)

func _open_calendar() -> void:
	await _open_time_panel()
	if _hud == null:
		return
	if not bool(_hud._cal_open):
		_hud._toggle_calendar()
	await _frames(4)
	_hud._time_idle = -1000.0
	if _wheel == null:
		_wheel = _hud._cal_wheel
	await _frames(2)

func _close_all_panels() -> void:
	if _hud == null:
		return
	if bool(_hud._cal_open):
		_hud._toggle_calendar()
		await _frames(3)
	if bool(_hud._time_open):
		_hud.toggle_time_panel()
		await _frames(3)
	_hud._time_idle = -1000.0

func _ensure_sim_mode() -> void:
	if _main == null:
		return
	if String(_main._time_source) != "sim":
		_main._on_time_mode_requested("sim")
		await _frames(2)
		_main._paused = true
		_main._settings_save_delay = -1.0
		await _wait(0.3)

## 中心行高亮带与相邻带亮度差（滚轮视觉证据；裁剪图坐标）
## 返回 {center, above, below, k}
func _wheel_band_diff(full: Image, wheel_rect_canvas: Rect2) -> Dictionary:
	if full == null:
		return {"center": 0.0, "above": 0.0, "below": 0.0, "k": 0.0}
	var vr: Vector2 = root.get_visible_rect().size
	var k: float = float(full.get_width()) / maxf(1.0, vr.x)
	var cy_full: float = wheel_rect_canvas.position.y * k + wheel_rect_canvas.size.y * k * 0.5
	var cx0: int = int(round(wheel_rect_canvas.position.x * k)) + int(round(4.0 * k))
	var cx1: int = int(round(wheel_rect_canvas.position.x * k)) + int(round(16.0 * k))
	var half: int = int(round(14.0 * k))
	var rh: int = int(round(ROW_H * k))
	var center := _band_mean(full, int(cy_full) - half, int(cy_full) + half, cx0, cx1)
	var above := _band_mean(full, int(cy_full) - half - rh, int(cy_full) - half, cx0, cx1)
	var below := _band_mean(full, int(cy_full) + half, int(cy_full) + half + rh, cx0, cx1)
	return {"center": center, "above": above, "below": below, "k": k}

# ============================================================
# UI1：打开日历时滚轮显示权威时间 / 布局 / 中心高亮
# ============================================================

func _ui1() -> void:
	_log("----------------------------------------------------------------")
	_log("[UI1] 打开日历：权威时间、5 列布局、offset_top、中心行高亮")
	await _close_all_panels()
	_main._paused = true
	await _wait(0.25)
	var auth := _auth_parts()
	var calp := _cal_parts()
	_keep()
	await _open_calendar()
	if _wheel == null:
		_fail("UI1", "滚轮实例", "_hud._cal_wheel 为空")
		return
	var opened: bool = bool(_hud._cal_open) and bool(_hud._cal_section.visible) and _wheel.is_visible_in_tree()
	_check("UI1", "日历打开可见", opened,
		"_cal_open=%s _cal_section.visible=%s wheel.visible_in_tree=%s" % [
			str(_hud._cal_open), str(_hud._cal_section.visible), str(_wheel.is_visible_in_tree())])
	var off_top := float(_hud._time_panel.offset_top)
	_check("UI1", "面板展开高度 offset_top=-744", absf(off_top - (-744.0)) < 0.5,
		"offset_top=%.2f（TIMEPANEL_TOP_CAL=-744）" % off_top)
	var pr: Rect2 = _hud._time_panel.get_global_rect()
	var wr: Rect2 = _wheel.get_global_rect()
	var win: Vector2 = root.get_visible_rect().size
	var panel_inside: bool = pr.size.x > 100.0 and pr.size.y > 100.0 and pr.position.x >= -0.5 and pr.position.y >= -0.5 and pr.end.x <= win.x + 0.5 and pr.end.y <= win.y + 0.5
	_check("UI1", "面板在可视区内", panel_inside,
		"panel=%s 可视区=%s" % [_fmt_rect(pr), _fmt_vec2(win)])
	var wp := _wheel_parts()
	_check("UI1", "滚轮=权威时钟(5 值)", _eq_parts(wp, auth),
		"wheel=%s auth=%s" % [_parts_str(wp), _parts_str(auth)])
	_check("UI1", "滚轮=历法投影(_sim_seconds)", _eq_parts(auth, calp),
		"auth=%s Cal.parts(_sim_seconds)=%s" % [_parts_str(auth), _parts_str(calp)])
	var ncol := 0
	var aligns: Array = []
	var widths: Array = []
	for f in FIELDS:
		var c = _wheel_col(f)
		if c == null:
			continue
		ncol += 1
		var r: Rect2 = c.get_global_rect()
		widths.append("%s=%.1f" % [f, r.size.x])
		aligns.append("%s=%.2f" % [f, r.position.y + r.size.y * 0.5 - (wr.position.y + wr.size.y * 0.5)])
	var wsum := ""
	for w in widths:
		wsum += String(w) + " "
	_check("UI1", "5 列都存在且高度 140", ncol == 5 and absf(float(_wheel_col("year").get_global_rect().size.y) - 140.0) < 1.0,
		"列数=%d 列宽=%s列高=%.1f" % [ncol, wsum, float(_wheel_col("year").get_global_rect().size.y)])
	var acenter := 0.0
	for a in aligns:
		var s := String(a)
		var v := float(s.split("=")[1])
		if absf(v) <= absf(acenter):
			acenter = v
	var maxdev := 0.0
	for a in aligns:
		maxdev = maxf(maxdev, absf(float(String(a).split("=")[1]) - acenter))
	_check("UI1", "列中心与滚轮中心对齐", absf(acenter) < 0.5 and maxdev < 0.5,
		"各列中心偏差=%s（最大互差 %.3f）" % [str(aligns), maxdev])
	# 设计宽 316 是 custom_minimum_size；HUD 里给了 SIZE_EXPAND_FILL，父容器内宽 324 时会撑到 324。
	_check("UI1", "滚轮 rect 高度=156 且宽度≥316（expand 填满）", wr.size.x >= 316.0 and wr.size.x <= 340.0 and absf(wr.size.y - 156.0) < 2.0,
		"wheel rect=%s（custom_min=316x156，expand 后宽=%.1f）" % [_fmt_rect(wr), wr.size.x])
	var img: Image = await _shot("UI1", "1440x900", OUT_DIR + "/1440x900_ui1_calendar_open.png", wr)
	var bands := _wheel_band_diff(img, wr)
	var d_above: float = float(bands["center"]) - float(bands["above"])
	var d_below: float = float(bands["center"]) - float(bands["below"])
	if d_above > 0.002 and d_below > 0.002:
		_pass("UI1", "中心行高亮带亮度", "中心 %.4f > 上邻 %.4f（+%.4f）且 > 下邻 %.4f（+%.4f），k=%.3f" % [
			float(bands["center"]), float(bands["above"]), d_above, float(bands["below"]), d_below, float(bands["k"])])
	elif d_above > 0.0003 and d_below > 0.0003:
		_warn("UI1", "中心行高亮带亮度", "方向正确但差值偏小：中心 %.4f 上邻 %.4f 下邻 %.4f" % [
			float(bands["center"]), float(bands["above"]), float(bands["below"])])
	else:
		_fail("UI1", "中心行高亮带亮度", "中心带未更亮：中心 %.4f 上邻 %.4f 下邻 %.4f" % [
			float(bands["center"]), float(bands["above"]), float(bands["below"])])
	_log("[UI1] wheel parts=%s off_top=%.1f wheel_rect=%s" % [_parts_str(wp), off_top, _fmt_rect(wr)])

# ============================================================
# UI2：滚轮/拖动/键盘后相机半径不变（不被 main 相机缩放吃掉）
# ============================================================

func _ui2() -> void:
	_log("----------------------------------------------------------------")
	_log("[UI2] 输入不分发给相机：滚轮/拖动/键盘后 _radius 不变")
	await _open_calendar()
	_keep()
	var r0 := float(_main._radius)
	_check("UI2", "起始相机半径记录", true, "_radius=%.4f（CAM 缩放范围 9..240）" % r0)
	# (a) 真实滚轮事件
	var b := _wheel_parts()
	var okw: bool = await _inject_wheel(_wheel_col("minute"), true)
	await _settle_wheel(2.5)
	var a := _wheel_parts()
	var r1 := float(_main._radius)
	var expect_minute := posmod(int(b.get("minute", 0)) - 1, 60)  # 滚轮上=notch(-1)=值-1（分钟循环）
	_check("UI2", "滚轮事件命中控件（一格=一行）", okw and int(a.get("minute", -1)) == expect_minute,
		"minute %d → %d（期望 %d，%s）" % [int(b.get("minute", 0)), int(a.get("minute", 0)), expect_minute, _parts_str(a)])
	_check("UI2", "滚轮后相机半径不变", is_equal_approx(r0, r1),
		"_radius %.4f → %.4f（Δ=%.6f，期望完全不缩放）" % [r0, r1, r1 - r0])
	# (b) 慢速拖动 1 行
	await _open_calendar()
	_keep()
	var before := _wheel_parts()
	var dim := int(Cal.days_in_month(int(before.get("year", 2026)), int(before.get("month", 1))))
	var drag_up := int(before.get("day", 1)) < dim
	var rows := -1.0 if drag_up else 1.0
	var expect_day := int(before.get("day", 1)) + (1 if drag_up else -1)
	var started: bool = await _inject_drag_col("day", rows, true)
	await _settle_wheel(3.0)
	var after := _wheel_parts()
	var r2 := float(_main._radius)
	_check("UI2", "拖动事件命中计日列", started and int(after.get("day", -99)) == expect_day,
		"day %d → %d（期望 %d，%s）" % [int(before.get("day", 0)), int(after.get("day", 0)), expect_day, _parts_str(after)])
	_check("UI2", "拖动后相机半径不变", is_equal_approx(r0, r2),
		"_radius %.4f → %.4f（Δ=%.6f）" % [r0, r2, r2 - r0])
	# (c) 点击聚焦 + 键盘 DOWN
	var c = _wheel_col("hour")
	if c != null:
		var cr: Rect2 = c.get_global_rect()
		await _inject_click_ctl(c)
		await _frames(2)
		var h0 := int(_wheel_parts().get("hour", -1))
		await _inject_key(KEY_DOWN)
		await _settle_wheel(2.5)
		var h1 := int(_wheel_parts().get("hour", -1))
		var r3 := float(_main._radius)
		_check("UI2", "键盘 DOWN 命中聚焦列", h0 != h1, "hour %d → %d（焦点 owner=%s）" % [
			h0, h1, str(root.gui_get_focus_owner())])
		_check("UI2", "键盘后相机半径不变", is_equal_approx(r0, r3),
			"_radius %.4f → %.4f（Δ=%.6f；也验证方向键未被 main 快捷键消费）" % [r0, r3, r3 - r0])
	else:
		_fail("UI2", "小时列存在", "找不到 Wheel_hour")
	var wr: Rect2 = _wheel.get_global_rect()
	var img: Image = await _shot("UI2", "1440x900", OUT_DIR + "/1440x900_ui2_after_input.png", wr)
	if img != null:
		_log("[UI2] 输入后 wheel=%s radius=%.4f" % [_parts_str(_wheel_parts()), float(_main._radius)])

# ============================================================
# UI3：关闭再打开草稿重置 + 0.12s 刷新不覆盖编辑
# ============================================================

func _ui3() -> void:
	_log("----------------------------------------------------------------")
	_log("[UI3] 未确认草稿：0.12s 刷新不覆盖、关闭重开重置为权威时间")
	await _open_calendar()
	_keep()
	_hud._seed_cal_draft(true)
	await _frames(3)
	var auth := _auth_parts()
	var w0 := _wheel_parts()
	_check("UI3", "打开时草稿=权威时间", _eq_parts(w0, auth), "wheel=%s auth=%s" % [_parts_str(w0), _parts_str(auth)])
	var dim := int(Cal.days_in_month(int(auth.get("year", 2026)), int(auth.get("month", 1))))
	var up := int(auth.get("day", 1)) < dim
	await _inject_wheel(_wheel_col("day"), up)
	await _settle_wheel(2.5)
	var edited := _wheel_parts()
	var dirty1 := bool(_hud._cal_dirty)
	_check("UI3", "编辑后 dirty=true 且值已改", dirty1 and not _eq_parts(edited, auth),
		"dirty=%s wheel=%s" % [str(dirty1), _parts_str(edited)])
	await _wait(0.45)
	var still := _wheel_parts()
	var dirty2 := bool(_hud._cal_dirty)
	_check("UI3", "0.45s（>3×0.12s 刷新）后编辑不被回灌", _eq_parts(still, edited) and dirty2,
		"wheel=%s dirty=%s（update_all 的 _seed_cal_draft 受 _cal_dirty 门控）" % [_parts_str(still), str(dirty2)])
	var toggle = _hud._cal_toggle
	var clicked: bool = await _inject_click_ctl(toggle)
	await _wait(0.2)
	_check("UI3", "点「收起」关闭日历", clicked and not bool(_hud._cal_open) and not bool(_hud._cal_section.visible),
		"_cal_open=%s visible=%s offset_top=%.1f" % [str(_hud._cal_open), str(_hud._cal_section.visible),
		float(_hud._time_panel.offset_top)])
	_check("UI3", "关闭后滚轮 busy 归零", not bool(_wheel.call("is_busy")), "is_busy=%s" % str(_wheel.call("is_busy")))
	var clicked2: bool = await _inject_click_ctl(toggle)
	await _wait(0.25)
	var w2 := _wheel_parts()
	_check("UI3", "重开后草稿重置为权威时间", clicked2 and bool(_hud._cal_open) and _eq_parts(w2, _auth_parts()) and
		not bool(_hud._cal_dirty), "wheel=%s auth=%s dirty=%s" % [_parts_str(w2), _parts_str(_auth_parts()), str(_hud._cal_dirty)])

# ============================================================
# UI4：暂停中仍可编辑；重置按钮只复位草稿不发跳转
# ============================================================

func _ui4() -> void:
	_log("----------------------------------------------------------------")
	_log("[UI4] 暂停中仍可编辑（_sim_seconds 冻结），重置按钮不发跳转")
	_main._paused = true
	await _open_calendar()
	_keep()
	_hud._seed_cal_draft(true)
	await _frames(3)
	var s0 := _sim()
	var j0 := _jump_count
	var h0 := int(_wheel_parts().get("hour", -1))
	await _inject_wheel(_wheel_col("hour"), false)
	await _settle_wheel(2.5)
	var h1 := int(_wheel_parts().get("hour", -1))
	var s1 := _sim()
	_check("UI4", "暂停中滚轮可编辑", h0 != h1, "hour %d → %d，paused=%s" % [h0, h1, str(_main._paused)])
	_check("UI4", "编辑不推进权威时钟", is_equal_approx(s0, s1) and bool(_main._paused),
		"_sim_seconds %.3f → %.3f（Δ=%.6f），paused=%s" % [s0, s1, s1 - s0, str(_main._paused)])
	var reset_ok: bool = await _inject_click_ctl(_hud._cal_reset_btn)
	await _wait(0.2)
	var w := _wheel_parts()
	_check("UI4", "「回到当前」复位草稿且不发跳转", reset_ok and _eq_parts(w, _auth_parts()) and _jump_count == j0,
		"wheel=%s auth=%s jump_count=%d→%d" % [_parts_str(w), _parts_str(_auth_parts()), j0, _jump_count])

# ============================================================
# UI5：真实时间模式整轮只读 + 自动收起（U11）
# ============================================================

func _ui5() -> void:
	_log("----------------------------------------------------------------")
	_log("[UI5+U11] 切到现实时间：日历自动收起、整轮只读、暂停按钮禁用；切回 sim 恢复")
	await _ensure_sim_mode()
	await _open_calendar()
	_keep()
	var real_btn = _hud._time_mode_buttons.get("real", null)
	if real_btn == null:
		_fail("UI5", "现实时间按钮存在", "_time_mode_buttons 无 real 键：%s" % str(_hud._time_mode_buttons.keys()))
		return
	await _inject_click_ctl(real_btn)
	_main._settings_save_delay = -1.0
	await _wait(0.6)
	_main._settings_save_delay = -1.0
	var src_main := String(_main._time_source)
	var src_hud := String(_hud._time_source)
	_check("UI5", "main 已切到 real", src_main == "real" and bool(_main._realtime),
		"_time_source=%s _realtime=%s" % [src_main, str(_main._realtime)])
	_check("UI5", "HUD 收到 real", src_hud == "real", "_hud._time_source=%s" % src_hud)
	_check("U11", "real 切换后日历自动收起", not bool(_hud._cal_open),
		"_cal_open=%s（_apply_time_mode_labels 内 _close_calendar）" % str(_hud._cal_open))
	_check("UI5", "real 下日历入口禁用", bool(_hud._cal_toggle.disabled),
		"_cal_toggle.disabled=%s" % str(_hud._cal_toggle.disabled))
	var editable: bool = bool(_wheel.get("_editable"))
	_check("UI5", "real 下滚轮只读", not editable, "wheel._editable=%s" % str(editable))
	_check("UI5", "real 下暂停按钮禁用", bool(_hud._pause_btn.disabled),
		"_pause_btn.disabled=%s" % str(_hud._pause_btn.disabled))
	# real 模式下日历入口禁用且 0.12s 刷新会强制收起面板：真实鼠标路径已在 UI3/UI4 覆盖，
	# 这里直接调用内部入口验证只读守卫（不强行改 UI 状态来绕过产品语义）。
	var before := _wheel_parts()
	var j0 := _jump_count
	_hud._cal_step("day", 1)
	_hud._on_cal_jump()
	await _frames(3)
	var after := _wheel_parts()
	_check("UI5", "real 下 _cal_step/_on_cal_jump 守卫不生效", _eq_parts(before, after) and _jump_count == j0,
		"_cal_step/_on_cal_jump 后 before=%s after=%s jump_count=%d→%d" % [
			_parts_str(before), _parts_str(after), j0, _jump_count])
	# 组件层也直接验证：set_editable(false) 后 step_field 提前 return。
	_wheel.call("step_field", "minute", 1)
	await _frames(2)
	_check("UI5", "real 下滚轮 step_field 直接调用不改值", _eq_parts(_wheel_parts(), before),
		"step_field(minute,+1) 后 wheel=%s" % _parts_str(_wheel_parts()))
	_check("UI5", "real 下跳转按钮 disabled", bool(_hud._cal_jump_btn.disabled),
		"_cal_jump_btn.disabled=%s（busy 或 real 均禁用）" % str(_hud._cal_jump_btn.disabled))
	var abs_unix := float(_main._abs_unix)
	var sys_unix := Time.get_unix_time_from_system()
	_check("UI5", "real 模式时钟跟随系统时间", absf(abs_unix - sys_unix) < 3.0,
		"_abs_unix=%.1f system=%.1f Δ=%.2fs" % [abs_unix, sys_unix, abs_unix - sys_unix])
	# 切回 sim
	var sim_btn = _hud._time_mode_buttons.get("sim", null)
	await _inject_click_ctl(sim_btn)
	_main._paused = true
	_main._settings_save_delay = -1.0
	await _wait(0.5)
	_main._settings_save_delay = -1.0
	await _ensure_sim_mode()
	await _wait(0.2)
	_check("UI5", "切回 sim 恢复可编辑", String(_main._time_source) == "sim" and not bool(_main._realtime) and
		not bool(_hud._pause_btn.disabled),
		"_time_source=%s realtime=%s pause.disabled=%s" % [String(_main._time_source), str(_main._realtime),
		str(_hud._pause_btn.disabled)])
	await _close_all_panels()

# ============================================================
# UI6：跨年确认 → _sim_seconds 秒=0 且日期正确
# ============================================================

func _ui6() -> void:
	_log("----------------------------------------------------------------")
	_log("[UI6] 跨年确认跳转：_sim_seconds 秒=0、日期正确、仍暂停")
	await _ensure_sim_mode()
	_main._paused = true
	await _open_calendar()
	_keep()
	_hud._seed_cal_draft(true)
	await _frames(3)
	var auth := _auth_parts()
	var ty := int(auth.get("year", 2026)) + 1
	if ty > 9999:
		ty = 9999
	var target := {"year": ty, "month": 1, "day": 1, "hour": 0, "minute": 0}
	_wheel.call("set_parts", target)
	_hud._cal_step("year", 0)
	await _frames(3)
	var draft_ok := _eq_parts(_wheel_parts(), target) and bool(_hud._cal_dirty)
	_check("UI6", "构造跨年草稿（set_parts + 固化 dirty）", draft_ok,
		"wheel=%s dirty=%s" % [_parts_str(_wheel_parts()), str(_hud._cal_dirty)])
	var j0 := _jump_count
	var s0 := _sim()
	var clicked: bool = await _inject_click_ctl(_hud._cal_jump_btn)
	await _wait(0.5)
	_keep()
	var s1 := _sim()
	var cp := _cal_parts()
	var j1 := _jump_count
	_check("UI6", "确认按钮发出一次跳转信号", clicked and j1 == j0 + 1,
		"jump_count %d→%d args=%s" % [j0, j1, str(_jump_args)])
	_check("UI6", "跳转后日期=目标（跨年 1/1 00:00）", _eq_parts(cp, target),
		"Cal.parts(_sim_seconds)=%s 目标=%s" % [_parts_str(cp), _parts_str(target)])
	var sec := fposmod(s1, 60.0)
	var sec_ok := absf(sec) < 0.01 or absf(sec - 60.0) < 0.01
	_check("UI6", "跳转后秒数=0", sec_ok,
		"_sim_seconds=%.3f sec_of_minute=%.6f" % [s1, sec])
	_check("UI6", "跳转未解除暂停", bool(_main._paused),
		"paused=%s s0=%.3f s1=%.3f" % [str(_main._paused), s0, s1])
	_check("UI6", "跳转后滚轮同步目标值", _eq_parts(_wheel_parts(), target) and not bool(_hud._cal_dirty),
		"wheel=%s dirty=%s" % [_parts_str(_wheel_parts()), str(_hud._cal_dirty)])
	var wr: Rect2 = _wheel.get_global_rect()
	await _shot("UI6", "1440x900", OUT_DIR + "/1440x900_ui6_after_jump.png", wr)
	_log("[UI6] auth_before=%s target=%s after=%s sim=%.3f→%.3f" % [
		_parts_str(auth), _parts_str(target), _parts_str(cp), s0, s1])

# ============================================================
# UI7：连续两次确认幂等（HUD 发两次信号，main 第二次早退）
# ============================================================

func _ui7() -> void:
	_log("----------------------------------------------------------------")
	_log("[UI7] 连续两次确认：HUD 每次发信号一次，main 第二次幂等早退（_sim_seconds 不变）")
	_main._paused = true
	var s_before := _sim()
	var j0 := _jump_count
	var target := _cal_parts()
	var clicked: bool = await _inject_click_ctl(_hud._cal_jump_btn)
	await _wait(0.4)
	_keep()
	var s_after := _sim()
	var j1 := _jump_count
	_check("UI7", "第二次点击仍只发一次信号", clicked and j1 == j0 + 1,
		"jump_count %d→%d args=%s" % [j0, j1, str(_jump_args)])
	_check("UI7", "第二次跳转 _sim_seconds 不变（幂等早退）", absf(s_after - s_before) < 0.001,
		"_sim_seconds %.4f → %.4f（Δ=%.6f，main._jump_datetime 的 |target-sim|<0.001 早退）" % [
			s_before, s_after, s_after - s_before])
	_check("UI7", "第二次确认后日期不变", _eq_parts(_cal_parts(), target),
		"Cal.parts=%s 目标=%s" % [_parts_str(_cal_parts()), _parts_str(target)])
	_check("UI7", "第二次确认后滚轮仍为目标值", _eq_parts(_wheel_parts(), target),
		"wheel=%s" % _parts_str(_wheel_parts()))

# ============================================================
# UI8：收起面板/隐藏 HUD 时中止拖拽（busy 归零）
# ============================================================

func _ui8() -> void:
	_log("----------------------------------------------------------------")
	_log("[UI8] 隐藏 HUD（H）/收起面板时中止拖拽，wheel.is_busy 归零")
	await _ensure_sim_mode()
	_main._paused = true
	var hidden0 := bool(_main._hud_hidden)
	# (a) 拖拽中按 H
	await _open_calendar()
	_keep()
	await _inject_drag_col("minute", -3.0, false)
	await _frames(2)
	var busy1 := bool(_wheel.call("is_busy"))
	_check("UI8a", "拖拽进入 busy", busy1, "wheel.is_busy=%s mode=%d" % [
		str(busy1), int(_wheel.debug_column("minute").get("mode")) if _wheel.has_method("debug_column") else -1])
	await _inject_key(KEY_H)
	await _wait(0.4)
	var hidden1 := bool(_main._hud_hidden)
	var busy2 := bool(_wheel.call("is_busy"))
	_check("UI8a", "H 隐藏 HUD", hidden1 != hidden0, "_hud_hidden %s→%s _visible_now=%s" % [
		str(hidden0), str(hidden1), str(_hud._visible_now)])
	_check("UI8a", "隐藏后面板与日历关闭", not bool(_hud._time_open) and not bool(_hud._cal_open),
		"_time_open=%s _cal_open=%s" % [str(_hud._time_open), str(_hud._cal_open)])
	_check("UI8a", "隐藏后拖拽中止（busy=false）", not busy2, "wheel.is_busy=%s" % str(busy2))
	_release_mouse()
	await _frames(3)
	# 恢复 HUD
	if bool(_main._hud_hidden):
		_main._toggle_hud_visible()
	await _frames(3)
	_hud.set_hud_visible(true, false)
	await _frames(3)
	_check("UI8a", "HUD 已恢复", not bool(_main._hud_hidden) and bool(_hud._visible_now),
		"_hud_hidden=%s _visible_now=%s" % [str(_main._hud_hidden), str(_hud._visible_now)])
	# (b) 拖拽中直接收折时间面板
	await _open_calendar()
	_keep()
	await _inject_drag_col("hour", -3.0, false)
	await _frames(2)
	var busy3 := bool(_wheel.call("is_busy"))
	_hud._collapse_time_panel()
	await _wait(0.25)
	_check("UI8b", "收起面板后拖拽中止", busy3 and not bool(_hud._time_open) and not bool(_hud._cal_open) and
		not bool(_wheel.call("is_busy")),
		"drag_busy=%s _time_open=%s _cal_open=%s busy_after=%s" % [
			str(busy3), str(_hud._time_open), str(_hud._cal_open), str(_wheel.call("is_busy"))])
	_release_mouse()
	await _frames(3)

# ============================================================
# UI9：busy 时 14s 自动收折不触发；空闲时阈值真实生效
# ============================================================

func _ui9() -> void:
	_log("----------------------------------------------------------------")
	_log("[UI9] 14s 自动收折：busy 门有效；空闲时阈值生效")
	await _ensure_sim_mode()
	_main._paused = true
	await _open_calendar()
	_keep()
	var win := Vector2i(DisplayServer.window_get_size())
	Input.warp_mouse(Vector2(win.x - 60, 80))
	await _wait(0.2)
	var mp: Vector2 = _hud.get_viewport().get_mouse_position()
	var pr: Rect2 = _hud._time_panel.get_global_rect()
	var over := pr.has_point(mp)
	if over:
		_warn("UI9", "光标移出面板", "warp 后光标仍在面板内：mp=%s panel=%s（窗口可能未获得焦点）" % [
			_fmt_vec2(mp), _fmt_rect(pr)])
	else:
		_pass("UI9", "光标移出面板", "mp=%s panel=%s over=%s" % [_fmt_vec2(mp), _fmt_rect(pr), str(over)])
	# A：拖拽 busy 时把 idle 推过阈值，不应收折
	await _inject_drag_col("minute", -3.0, false)
	await _frames(2)
	var busy := bool(_wheel.call("is_busy"))
	_hud._time_idle = 20.0
	await _wait(0.35)
	var open_a := bool(_hud._time_open)
	var idle_a := float(_hud._time_idle)
	if busy and not over:
		_check("UI9", "busy 时 14s 自动收折不触发", open_a,
			"busy=%s idle 设为 20 后 0.35s：_time_open=%s（busy 每帧清零 idle，实测 idle=%.2f）" % [
				str(busy), str(open_a), idle_a])
	elif busy:
		_warn("UI9", "busy 时 14s 自动收折不触发", "busy=%s 但光标在面板内（over=true），无法区分 busy 门与 over 门；_time_open=%s idle=%.2f" % [
			str(busy), str(open_a), idle_a])
	else:
		_fail("UI9", "拖拽进入 busy", "wheel.is_busy=false")
	_release_mouse()
	# 释放后弹簧仍在吸附：先等待彻底空闲并把光标移出面板，否则 busy/over 会每帧清零 idle。
	await _settle_wheel(3.0)
	Input.warp_mouse(Vector2(win.x - 60, 80))
	await _wait(0.2)
	if not over:
		# B：空闲时 idle 超过 14s 应当收折
		_hud._time_idle = 20.0
		await _wait(0.35)
		var open_b := bool(_hud._time_open)
		_check("UI9", "空闲时 14s 阈值真实生效（idle>14 收折）", not open_b,
			"idle 置 20 后 0.35s：_time_open=%s _cal_open=%s（阈值常量 14.0s）" % [
				str(open_b), str(_hud._cal_open)])
	else:
		_warn("UI9", "空闲时 14s 阈值", "光标在面板内（over=true），不会触发收折，无法验证阈值路径")
		await _close_all_panels()

# ============================================================
# UI10：面板帧开销（P8.2 重写：vsync 关闭 + 逐对交错 + A/A 噪声底 + 95% CI）
# ============================================================

## 帧间隔采样（ms）：Time.get_ticks_usec() 跨 process_frame 的差值。
## P-5：windowed 下 Performance.TIME_PROCESS 恒为少数几个量化值（v1 采样唯一值=2），不可作判据；
## 此处仅统计其唯一值个数作为 P-5 证据，并用 Performance.TIME_FPS 与墙钟 fps 交叉校验。
func _measure_frame_wall(frames: int = 40) -> Dictionary:
	await _frames(6)
	var raw: Array = []
	var proc: Array = []
	var prev := Time.get_ticks_usec()
	for i in range(frames):
		await process_frame
		var now := Time.get_ticks_usec()
		raw.append(float(now - prev) / 1000.0)
		prev = now
		proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	var sorted := raw.duplicate()
	sorted.sort()
	proc.sort()
	var n := sorted.size()
	var sum := 0.0
	for v in raw:
		sum += float(v)
	var uniq := {}
	for v in proc:
		uniq[str(v)] = true
	return {"avg": sum / maxf(1.0, float(n)),
		"p50": float(sorted[int(clampf(float(n) * 0.5, 0.0, float(n - 1)))]),
		"p95": float(sorted[int(clampf(float(n) * 0.95, 0.0, float(n - 1)))]),
		"max": float(sorted[n - 1]),
		"proc": float(proc[int(clampf(float(n) * 0.5, 0.0, float(n - 1)))]),
		"proc_unique": uniq.size(),
		"fps_engine": float(Engine.get_frames_per_second()),
		"fps_wall": 1000.0 / maxf(0.001, sum / maxf(1.0, float(n))),
		"draw": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objs": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"n": n}

static func _meanf(a: Array) -> float:
	var s := 0.0
	for v in a:
		s += float(v)
	return s / maxf(1.0, float(a.size()))

static func _medianf(a: Array) -> float:
	var b := a.duplicate()
	b.sort()
	if b.is_empty():
		return 0.0
	var n := b.size()
	if n % 2 == 1:
		return float(b[int(n / 2)])
	return 0.5 * (float(b[n / 2 - 1]) + float(b[n / 2]))

static func _percentilef(a: Array, q: float) -> float:
	var b := a.duplicate()
	b.sort()
	if b.is_empty():
		return 0.0
	return float(b[int(clampf((float(b.size()) - 1.0) * q, 0.0, float(b.size() - 1)))])

static func _stddevf(a: Array) -> float:
	if a.size() < 2:
		return 0.0
	var m := _meanf(a)
	var s := 0.0
	for v in a:
		var d := float(v) - m
		s += d * d
	return sqrt(s / float(a.size() - 1))

func _ui10() -> void:
	_log("----------------------------------------------------------------")
	_log("[UI10] 面板帧开销：P8.2 重写 = vsync 关闭 + 逐对交错 12 对 + A/A 噪声底 8 对（每段 40 帧）")
	var prev_vsync := DisplayServer.window_get_vsync_mode()
	var prev_max_fps := Engine.max_fps
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await _close_all_panels()
	var win := Vector2i(DisplayServer.window_get_size())
	Input.warp_mouse(Vector2(win.x - 60, 80))
	await _wait(0.3)

	var d_p50: Array = []
	var d_avg: Array = []
	var closed_p50: Array = []
	var open_p50: Array = []
	var planes: Array = []
	var draw_closed := 0
	var draw_open := 0
	var objs_closed := 0
	var objs_open := 0
	var proc_unique := 0
	var fps_engine := 0.0
	var fps_wall := 0.0
	for i in range(12):
		var a: Dictionary = await _measure_frame_wall(40)
		_keep()
		await _open_calendar()
		_keep()
		var b: Dictionary = await _measure_frame_wall(40)
		await _close_all_panels()
		_keep()
		Input.warp_mouse(Vector2(win.x - 60, 80))
		await _wait(0.05)
		d_p50.append(float(b["p50"]) - float(a["p50"]))
		d_avg.append(float(b["avg"]) - float(a["avg"]))
		closed_p50.append(float(a["p50"]))
		open_p50.append(float(b["p50"]))
		planes.append("A%.3f/B%.3f" % [float(a["p50"]), float(b["p50"])])
		proc_unique = maxi(proc_unique, int(a["proc_unique"]))
		fps_engine = float(a["fps_engine"])
		fps_wall = float(a["fps_wall"])
		if i == 0:
			draw_closed = int(a["draw"])
			draw_open = int(b["draw"])
			objs_closed = int(a["objs"])
			objs_open = int(b["objs"])
		_log("[UI10] 对%02d %s（Δp50=%+.3fms）" % [i + 1, planes[i], float(d_p50[i])])

	# A/A 对照：同一"面板全关"状态连续两段，量化段间漂移/噪声底
	var aa_p50: Array = []
	var aa_avg: Array = []
	for i in range(8):
		var a: Dictionary = await _measure_frame_wall(40)
		var b: Dictionary = await _measure_frame_wall(40)
		await _close_all_panels()
		_keep()
		Input.warp_mouse(Vector2(win.x - 60, 80))
		await _wait(0.05)
		aa_p50.append(absf(float(b["p50"]) - float(a["p50"])))
		aa_avg.append(absf(float(b["avg"]) - float(a["avg"])))
	DisplayServer.window_set_vsync_mode(prev_vsync)
	Engine.max_fps = prev_max_fps

	var positive := 0
	for v in d_p50:
		if float(v) > 0.0:
			positive += 1
	var dmed := _medianf(d_p50)
	var dmean := _meanf(d_p50)
	var sd := _stddevf(d_p50)
	var se := sd / sqrt(float(maxi(1, d_p50.size())))
	var ci_hi := dmean + 1.96 * se
	var noise_med := _medianf(aa_p50)
	var noise_p95 := _percentilef(aa_p50, 0.95)
	var dd := draw_open - draw_closed
	var detail := "Δp50 中位=%+.3fms（均值 %+.3f±%.3f，95%%CI 上限 %+.3fms，正号 %d/12）；A/A |Δp50| 中位=%.3fms p95=%.3fms；关闭/打开 p50 中位=%.3f/%.3fms；Δdraw=%+d（%d→%d）；Δobjs=%+d；TIME_FPS 引擎=%.1f 墙钟≈%.1f；TIME_PROCESS 唯一值=%d（P-5 量化，仅记录）" % [
		dmed, dmean, se, ci_hi, positive, noise_med, noise_p95,
		_medianf(closed_p50), _medianf(open_p50), dd, draw_closed, draw_open, objs_open - objs_closed,
		fps_engine, fps_wall, proc_unique]
	_log("[UI10] " + detail)
	_log("[UI10] 逐对=%s；A/A=|Δp50|%s" % [str(planes), str(aa_p50)])
	# 判据：vsync 关闭 + 逐对交错消除段间漂移；以配对差均值 95% 置信上限 < 0.3ms 作为"证明通过"。
	# dmed<0.3 但 CI 上限 ≥0.3 时只记 WARN（数据不足以证明门限，不冒充通过）；≥1.5ms 或无 draw 增量记 FAIL。
	if dd > 0 and ci_hi < 0.3 and dmed < 0.3:
		_pass("UI10", "面板帧开销 Δp50 中位<0.3ms（95% CI 上限<0.3ms，逐对交错）", detail)
	elif dd > 0 and dmed < 0.3:
		_warn("UI10", "面板 Δp50 中位<0.3ms 但 95% CI 上限≥0.3ms（A/A 噪声底 %.3fms，数据不足）" % noise_med, detail)
	elif dd > 0 and dmed < 1.5:
		_warn("UI10", "面板帧时间 Δp50 中位=%.3fms（0.3–1.5ms 区间）" % dmed, detail)
	else:
		_fail("UI10", "面板帧开销异常（Δp50 中位≥1.5ms 或 draw 无增量）", detail)

# ============================================================
# U01：高 DPI / 纹理-窗口一致性
# ============================================================

func _u01() -> void:
	_log("----------------------------------------------------------------")
	_log("[U01] 高 DPI / 纹理-窗口一致性")
	var win := Vector2i(DisplayServer.window_get_size())
	var vr: Rect2 = root.get_visible_rect()
	var factor := root.content_scale_factor
	var same := absf(vr.size.x - float(win.x)) < 0.5 and absf(vr.size.y - float(win.y)) < 0.5
	var detail := "screen_scale=%.3f dpi=%d max_scale=%.3f；window=%s visible_rect=%s content_scale_factor=%.3f scale_now=%.3f" % [
		DisplayServer.screen_get_scale(), DisplayServer.screen_get_dpi(), DisplayServer.screen_get_max_scale(),
		_vi(win), _fmt_vec2(vr.size), factor, _scale_now()]
	if same and is_equal_approx(factor, 1.0):
		_pass("U01", "1:1 像素映射（纹理=窗口）", detail)
	else:
		_warn("U01", "非 1:1 映射（高 DPI/系统缩放）", detail + "；所有注入坐标已乘 scale_now")
	# 用一张 1440 截图核对纹理尺寸
	await _open_calendar()
	var wr: Rect2 = _wheel.get_global_rect()
	await RenderingServer.frame_post_draw
	var tex := root.get_texture()
	var img: Image = tex.get_image() if tex != null else null
	if img != null:
		var sz := img.get_size()
		if sz == win:
			_pass("U01", "截图纹理尺寸=窗口尺寸", "%s（滚轮 rect=%s）" % [_vi(sz), _fmt_rect(wr)])
		else:
			_warn("U01", "截图纹理尺寸≠窗口", "纹理 %s vs 窗口 %s（缩放补偿 k=%.3f）" % [
				_vi(sz), _vi(win), _scale_now()])

# ============================================================
# U03：TAB 焦点遍历观察
# ============================================================

func _u03() -> void:
	_log("----------------------------------------------------------------")
	_log("[U03] 滚轮聚焦时按 TAB 的焦点遍历观察")
	await _open_calendar()
	var hour_col = _wheel_col("hour")
	await _inject_click_ctl(hour_col)
	await _frames(3)
	var f0: String = _focus_name()
	var alm0 := bool(_hud._almanac_open)
	await _inject_key(KEY_TAB)
	await _frames(3)
	var f1: String = _focus_name()
	var alm1 := bool(_hud._almanac_open)
	var detail := "TAB 前焦点=%s，TAB 后焦点=%s；_almanac_open %s→%s" % [f0, f1, str(alm0), str(alm1)]
	if alm0 != alm1:
		_warn("U03", "TAB 被 main 消费（almanac 切换）", detail + "；计划 U03 标为未验证，记录实测行为")
	elif f0 != f1:
		_pass("U03", "TAB 在滚轮内做焦点遍历", detail)
	else:
		_warn("U03", "TAB 未改变焦点（观察）", detail)

func _focus_name() -> String:
	var o = root.gui_get_focus_owner()
	if o == null or not is_instance_valid(o):
		return "(无)"
	return "%s(%s)" % [str(o.name), o.get_class()]

# ============================================================
# U04：触摸注入观察
# ============================================================

func _u04() -> void:
	_log("----------------------------------------------------------------")
	_log("[U04] 触摸事件注入观察（桌面端是否等价点击）")
	await _open_calendar()
	_keep()
	var col = _wheel_col("day")
	var r: Rect2 = col.get_global_rect()
	var p_win := _to_win(Vector2(r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.5 + ROW_H * 0.5))
	var before := _wheel_parts()
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.pressed = true
	ev.position = p_win
	Input.parse_input_event(ev)
	await _frames(3)
	var ev2 := InputEventScreenTouch.new()
	ev2.index = 0
	ev2.pressed = false
	ev2.position = p_win
	Input.parse_input_event(ev2)
	await _frames(3)
	var after := _wheel_parts()
	if _eq_parts(before, after):
		_warn("U04", "触摸注入不改变滚轮值", "桌面触控未通过 GUI 路由（%s→%s；计划 U04 未验证，桌面鼠标路径已由 UI2 覆盖）" % [
			_parts_str(before), _parts_str(after)])
	else:
		_pass("U04", "触摸注入等价点击", "%s→%s" % [_parts_str(before), _parts_str(after)])

# ============================================================
# 1600x900 真实窗口视觉回归
# ============================================================

func _phase_b() -> void:
	_log("----------------------------------------------------------------")
	_log("[LAYOUT1600] 切到 1600x900 真实窗口复检布局与截图")
	await _ensure_sim_mode()
	_main._paused = true
	await _close_all_panels()
	await _set_size(RES_B)
	await _wait(0.5)
	_main._settings_save_delay = -1.0
	_hud.set_hud_visible(true, false)
	await _frames(3)
	var win := Vector2i(DisplayServer.window_get_size())
	var vr: Rect2 = root.get_visible_rect()
	_record("LAYOUT1600", "check", "窗口=1600x900", "PASS" if win == RES_B else "WARN",
		"window=%s visible_rect=%s scale_now=%.3f content_scale_factor=%.3f" % [
			_vi(win), _fmt_vec2(vr.size), _scale_now(), root.content_scale_factor])
	await _open_calendar()
	_keep()
	var wr: Rect2 = _wheel.get_global_rect()
	var pr: Rect2 = _hud._time_panel.get_global_rect()
	_check("LAYOUT1600", "1600x900 下面板完整在可视区",
		pr.position.x >= 0.0 and pr.position.y >= 0.0 and pr.end.x <= vr.size.x + 0.5 and pr.end.y <= vr.size.y + 0.5,
		"panel=%s wheel=%s 可视区=%s" % [_fmt_rect(pr), _fmt_rect(wr), _fmt_vec2(vr.size)])
	var inside := true
	for f in FIELDS:
		var c = _wheel_col(f)
		if c == null:
			inside = false
			continue
		var cr: Rect2 = c.get_global_rect()
		if not wr.grow(1.0).encloses(cr):
			inside = false
	_check("LAYOUT1600", "5 列都在滚轮 rect 内", inside, "wheel=%s" % _fmt_rect(wr))
	var wp := _wheel_parts()
	_check("LAYOUT1600", "1600x900 下滚轮仍=权威时间", _eq_parts(wp, _auth_parts()),
		"wheel=%s auth=%s" % [_parts_str(wp), _parts_str(_auth_parts())])
	var img: Image = await _shot("LAYOUT1600", "1600x900", OUT_DIR + "/1600x900_ui1_calendar_open.png", wr)
	var bands := _wheel_band_diff(img, wr)
	var d_above: float = float(bands["center"]) - float(bands["above"])
	var d_below: float = float(bands["center"]) - float(bands["below"])
	_check("LAYOUT1600", "1600x900 中心行高亮带", d_above > 0.0005 and d_below > 0.0005,
		"中心 %.4f 上邻 %.4f（+%.4f）下邻 %.4f（+%.4f）k=%.3f" % [
			float(bands["center"]), float(bands["above"]), d_above,
			float(bands["below"]), d_below, float(bands["k"])])
	await _wait(0.2)
	await _shot("LAYOUT1600", "1600x900", OUT_DIR + "/1600x900_ui1_full_hud.png")
	await _close_all_panels()

# ============================================================
# 收尾：恢复窗口、确认未写 user:// 设置
# ============================================================

func _cleanup() -> void:
	_log("----------------------------------------------------------------")
	_log("[CLEANUP] 恢复窗口与面板状态，确认未写 user://settings.cfg")
	await _close_all_panels()
	if _main != null:
		_main._settings_save_delay = -1.0
	await _set_mode("windowed")
	await _set_size(RES_A)
	await _frames(3)
	var win := Vector2i(DisplayServer.window_get_size())
	var ok := win == RES_A and _actual_mode() == "windowed"
	_record("cleanup", "check", "恢复 1440x900 窗口化", "PASS" if ok else "WARN",
		"window=%s mode=%s factor=%.3f" % [_vi(win), _actual_mode(), root.content_scale_factor])
	var mtime_now := FileAccess.get_modified_time("user://settings.cfg")
	if int(_cfg_mtime) >= 0 and mtime_now == int(_cfg_mtime):
		_pass("cleanup", "未写 user://settings.cfg", "mtime 保持 %d" % mtime_now)
	else:
		_warn("cleanup", "user://settings.cfg mtime 有变化",
			"probe 启动时=%s 结束=%s（可能由并行进程/其他实例写入；本探针全程 _settings_save_delay=-1）" % [
				str(_cfg_mtime), str(mtime_now)])
	if _main != null:
		_check("cleanup", "结束时 _settings_save_delay<0", float(_main._settings_save_delay) < 0.0,
			"_settings_save_delay=%.2f" % float(_main._settings_save_delay))



# ============================================================
# 诊断模式：控件 rect / hovered / 点击分发定位（仅调试，不参与正式验收）
# ============================================================

func _diag_hover(tag: String, ctl) -> void:
	if ctl == null or not is_instance_valid(ctl):
		_log("[DIAG] %s: 控件为空" % tag)
		return
	var c: Control = ctl
	var r: Rect2 = c.get_global_rect()
	Input.warp_mouse(Vector2(0, 0))
	await _frames(2)
	var pos := r.position + r.size * 0.5
	Input.warp_mouse(pos)
	await _frames(3)
	var hov = root.gui_get_hovered_control()
	var hov_name := "(null)"
	if hov != null and is_instance_valid(hov):
		hov_name = "%s(%s)/%s" % [str(hov.name), hov.get_class(), str(hov.get_parent().name if hov.get_parent() != null else "?")]
	var extra := ""
	if c is Button:
		var b := c as Button
		extra = "disabled=%s" % str(b.disabled)
	_log("[DIAG] %s: name=%s type=%s rect=%s visible_in_tree=%s mouse_filter=%d %s pos=%s hovered=%s" % [
		tag, str(c.name), c.get_class(), _fmt_rect(r), str(c.is_visible_in_tree()),
		c.mouse_filter, extra, _fmt_vec2(pos), hov_name])

func _diag_click(tag: String, ctl, warp: bool) -> void:
	if ctl == null or not is_instance_valid(ctl):
		_log("[DIAG] %s: 控件为空" % tag)
		return
	var c: Control = ctl
	var r: Rect2 = c.get_global_rect()
	var pos := r.position + r.size * 0.5
	if warp:
		Input.warp_mouse(pos)
		await _frames(3)
	_press_mouse(pos)
	await _frames(2)
	_release_mouse(pos)
	await _frames(4)
	_log("[DIAG] %s click(warp=%s) pos=%s → hovered=%s" % [tag, str(warp), _fmt_vec2(pos),
		str(root.gui_get_hovered_control().name if root.gui_get_hovered_control() != null else "(null)")])

func _diag_controls() -> void:
	_log("================================================================")
	_log("[DIAG] 控件 rect / hovered 命中 / 点击分发诊断")
	_main._paused = true
	await _open_calendar()
	if _wheel == null:
		_log("[DIAG] 滚轮为空")
		return
	_keep()
	await _frames(3)
	var panel: Rect2 = _hud._time_panel.get_global_rect()
	_log("[DIAG] panel=%s visible=%s wheel=%s" % [
		_fmt_rect(panel), str(_hud._time_panel.visible), _fmt_rect(_wheel.get_global_rect())])
	var ctrls := [
		["cal_toggle", _hud._cal_toggle],
		["cal_jump_btn", _hud._cal_jump_btn],
		["cal_reset_btn", _hud._cal_reset_btn],
		["mode_sim", _hud._time_mode_buttons.get("sim", null)],
		["mode_real", _hud._time_mode_buttons.get("real", null)],
		["col_day", _wheel_col("day")],
		["col_hour", _wheel_col("hour")],
		["col_minute", _wheel_col("minute")],
	]
	for item in ctrls:
		await _diag_hover(str(item[0]), item[1])
	# 点击分发：toggle（含 warp / 不 warp 两种）
	await _diag_click("toggle_nowarp", _hud._cal_toggle, false)
	_log("[DIAG] toggle_nowarp 后 _cal_open=%s" % str(_hud._cal_open))
	await _diag_click("toggle_warp", _hud._cal_toggle, true)
	_log("[DIAG] toggle_warp 后 _cal_open=%s" % str(_hud._cal_open))
	if not bool(_hud._cal_open):
		await _open_calendar()
	# reset：先弄脏草稿再点
	_hud._cal_step("day", 1)
	await _frames(2)
	var dirty_before := bool(_hud._cal_dirty)
	await _diag_click("reset_warp", _hud._cal_reset_btn, true)
	_log("[DIAG] reset_warp 前 dirty=%s wheel=%s，后 dirty=%s wheel=%s auth=%s" % [
		str(dirty_before), _parts_str(_wheel_parts()), str(_hud._cal_dirty),
		_parts_str(_wheel_parts()), _parts_str(_auth_parts())])
	# real 按钮
	var before_src := String(_main._time_source)
	await _diag_click("real_warp", _hud._time_mode_buttons.get("real", null), true)
	await _wait(0.4)
	_main._settings_save_delay = -1.0
	_log("[DIAG] real_warp 后 _main._time_source=%s（前=%s）_hud._time_source=%s realtime=%s cal_open=%s editable=%s" % [
		String(_main._time_source), before_src, String(_hud._time_source), str(bool(_main._realtime)),
		str(bool(_hud._cal_open)), str(bool(_wheel.get("_editable")))])
	await _ensure_sim_mode()
	await _wait(0.2)
	_main._settings_save_delay = -1.0
	if not bool(_hud._cal_open):
		await _open_calendar()
	# 列拖动诊断
	await _diag_drag()
	# 列点击聚焦诊断
	var hc = _wheel_col("hour")
	var hr: Rect2 = hc.get_global_rect()
	Input.warp_mouse(hr.position + hr.size * 0.5)
	await _frames(3)
	_press_mouse(hr.position + hr.size * 0.5)
	await _frames(2)
	_release_mouse(hr.position + hr.size * 0.5)
	await _frames(3)
	_log("[DIAG] 点击 hour 列后 focus_owner=%s press_down_hour=%s" % [
		_focus_name(), str(hc.get("_press_down"))])

func _diag_drag() -> void:
	var w = _wheel_col("day")
	if w == null:
		_log("[DIAG] day 列为空")
		return
	var r: Rect2 = w.get_global_rect()
	var start := r.position + r.size * 0.5
	Input.warp_mouse(start)
	await _frames(3)
	_press_mouse(start)
	await _frames(2)
	_log("[DIAG] drag press: press_down=%s drag_started=%s mode=%d pos=%.2f" % [
		str(w.get("_press_down")), str(w.get("_drag_started")), int(w.get("mode")), float(w.get("pos"))])
	var p := start
	var total := -28.0
	for i in range(10):
		p.y += total / 10.0
		_motion_mouse(p)
		await _frames(3)
		if i == 0 or i == 2 or i == 9:
			_log("[DIAG] drag motion %d: dy=%.2f press_down=%s drag_started=%s mode=%d pos=%.2f" % [
				i, p.y - start.y, str(w.get("_press_down")), str(w.get("_drag_started")),
				int(w.get("mode")), float(w.get("pos"))])
	_release_mouse(p)
	await _frames(2)
	_log("[DIAG] drag release: mode=%d pos=%.2f parts=%s" % [
		int(w.get("mode")), float(w.get("pos")), _parts_str(_wheel_parts())])
	await _settle_wheel(3.0)
	_log("[DIAG] drag settled: mode=%d pos=%.2f parts=%s" % [
		int(w.get("mode")), float(w.get("pos")), _parts_str(_wheel_parts())])

