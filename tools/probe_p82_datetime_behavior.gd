extends SceneTree
## P8.2-05 日期时间滚轮：窗口端到端行为探针（真实窗口，非 headless）。
## 归属：teammate wheel / 共享任务 task-5。只新增本文件；不改正式逻辑。
## 运行：
##   cd "D:/休闲小岛幻境/游戏工程" && bash "D:/休闲小岛幻境/开发产物/p82/run_godot.sh" --path . --script res://tools/probe_p82_datetime_behavior.gd
## 输出：D:/休闲小岛幻境/开发产物/p82/05_wheel/probe_p82_datetime_behavior.{log,json}
## 覆盖：P-2 假 dirty、U-05 手感/惯性/阈值/橡皮筋/真实鼠标、U-12 键重复、
##       U-06 TAB/焦点、U-07 并发面板、U-08 跨午夜（sim 自然跨越 + real 注入）、
##       U-10 极端年份/闰年/月末、U-11 失焦/多屏/最小化、U-09 反复开合节点/连接增长。
## 纪律：不写 user://（全程 _settings_save_delay=-1）；不改 main.gd；退出码 0=无 FAIL（WARN/SKIP 不算失败）。

const Cal := preload("res://scripts/isle_calendar.gd")
const OUT_DIR := "D:/休闲小岛幻境/开发产物/p82/05_wheel"
const TAG := "probe_p82_datetime_behavior"
const LOG_PATH := OUT_DIR + "/" + TAG + ".log"
const JSON_PATH := OUT_DIR + "/" + TAG + "_result.json"
const ROW_H := 28.0
const FIELDS := ["year", "month", "day", "hour", "minute"]
const WIN_W := 1440
const WIN_H := 900

var _main = null
var _hud = null
var _wheel = null
var _checks: Array = []
var _shots: Array = []
var _lines: Array = []
var _passes := 0
var _warns := 0
var _fails := 0
var _skips := 0
var _t0 := 0
var _env: Dictionary = {}
var _jump_count := 0
var _jump_args: Array = []
var _last_mouse := Vector2.ZERO
var _orig: Dictionary = {}

# ============================================================
# 入口
# ============================================================

func _initialize() -> void:
	_t0 = Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_log("================================================================")
	_log("[ENV] " + TAG + " / P8.2-05 / teammate wheel")
	_collect_env()
	if DisplayServer.get_name() == "headless":
		_fail("env", "显示服务器", "headless 模式无法做真实窗口验收；请去掉 --headless 重跑")
		_finish()
		return
	DisplayServer.window_move_to_foreground()
	await _frames(6)
	_log("[ENV] window_is_focused=%s" % str(DisplayServer.window_is_focused()))
	var loaded: bool = await _load_main()
	if not loaded:
		_finish()
		return
	_main._settings_save_delay = -1.0
	_main._auto_orbit = false
	_main._settings["auto_orbit"] = false
	await _ensure_sim()
	await _ensure_playing()
	if _hud == null:
		_fail("env", "HUD 实例", "HUD 为空，无法继续")
		_finish()
		return
	_hud.datetime_jump_requested.connect(_on_jump_sig)
	_orig = {"sim": float(_main._sim_seconds), "paused": bool(_main._paused),
		"day_length": float(_main._day_length), "time_source": String(_main._time_source),
		"realtime": bool(_main._realtime)}
	await _wait(0.4)
	await _sec_p2_dirty()
	await _sec_u05()
	await _sec_u12()
	await _sec_u06()
	await _sec_u07()
	await _sec_u08()
	await _sec_u10()
	await _sec_u11()
	await _sec_u04_touch()
	await _sec_u09()
	await _final_restore()
	_finish()

# ============================================================
# 环境 / 加载 / 基线
# ============================================================

func _collect_env() -> void:
	var scr := DisplayServer.get_screen_count()
	var screens: Array = []
	for i in range(scr):
		var s := {"index": i, "size": _vi(DisplayServer.screen_get_size(i)),
			"usable": _vi(DisplayServer.screen_get_usable_rect(i).size),
			"scale": DisplayServer.screen_get_scale(i), "dpi": DisplayServer.screen_get_dpi(i)}
		screens.append(s)
		_log("[ENV] screen%d size=%s usable=%s scale=%.3f dpi=%d" % [
			i, String(s["size"]), String(s["usable"]), float(s["scale"]), int(s["dpi"])])
	_env = {
		"engine": Engine.get_version_info().get("string", "?"),
		"os": OS.get_name(),
		"display_server": DisplayServer.get_name(),
		"screen_count": scr,
		"screens": screens,
		"screen_max_scale": DisplayServer.screen_get_max_scale(),
		"cpu": OS.get_processor_name(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"api": RenderingServer.get_video_adapter_api_version(),
		"window": _vi(DisplayServer.window_get_size()),
		"visible_rect": _fmt_vec2(root.get_visible_rect().size),
		"content_scale_size": _vi(root.content_scale_size),
		"content_scale_factor": root.content_scale_factor,
		"content_scale_mode": root.content_scale_mode,
		"content_scale_aspect": root.content_scale_aspect,
	}
	_log("[ENV] engine=%s os=%s ds=%s cpu=%s" % [String(_env["engine"]), String(_env["os"]),
		String(_env["display_server"]), String(_env["cpu"])])
	_log("[ENV] gpu=%s api=%s" % [String(_env["gpu"]), String(_env["api"])])
	_log("[ENV] window=%s visible_rect=%s content_scale(size=%s factor=%.3f mode=%d aspect=%d)" % [
		String(_env["window"]), String(_env["visible_rect"]), String(_env["content_scale_size"]),
		float(_env["content_scale_factor"]), int(_env["content_scale_mode"]), int(_env["content_scale_aspect"])])
	_log("[ENV] vsync=%d max_fps=%d stretch=%.3f" % [
		int(ProjectSettings.get_setting("display/window/vsync/vsync_mode", -1)),
		int(ProjectSettings.get_setting("application/run/max_fps", 0)),
		float(ProjectSettings.get_setting("display/window/stretch/scale", 1.0))])

func _load_main() -> bool:
	_main = root.get_node_or_null("Isle")
	if _main == null:
		_log("[INFO] 场景无 Isle 节点，加载 res://isle.tscn ...")
		var t_load := Time.get_ticks_msec()
		var ps: PackedScene = load("res://isle.tscn")
		if ps == null:
			_fail("env", "加载 isle.tscn", "PackedScene 为空")
			return false
		root.add_child(ps.instantiate())
		_main = root.get_node_or_null("Isle")
		if _main == null:
			_fail("env", "实例化 Isle 根节点", "找不到 Isle")
			return false
		_log("[INFO] isle.tscn 已加入场景树（%.1fs）" % (float(Time.get_ticks_msec() - t_load) / 1000.0))
	var waited := 0.0
	while (_main._hud == null or _main._menu == null) and waited < 120.0:
		await _wait(0.25)
		waited += 0.25
		if int(waited) % 5 == 0:
			_log("[INFO] 等待 HUD/菜单... %.0fs" % waited)
	if _main._hud == null or _main._menu == null:
		_fail("env", "HUD/菜单实例", "HUD=%s menu=%s" % [str(_main._hud), str(_main._menu)])
		return false
	_hud = _main._hud
	await _frames(8)
	await _wait(0.8)
	_log("[ENV] HUD 就绪：节点数=%d" % _count_nodes(_hud))
	await _set_size(WIN_W, WIN_H)
	await _wait(0.4)
	_main._settings_save_delay = -1.0
	_log("[ENV] 基线窗口 window=%s mode=%s visible_rect=%s scale_now=%.3f" % [
		_vi(DisplayServer.window_get_size()), _actual_mode(),
		_fmt_vec2(root.get_visible_rect().size), _scale_now()])
	return true

func _ensure_sim() -> void:
	if _main == null:
		return
	if String(_main._time_source) != "sim":
		_log("[INFO] 切到模拟时间模式")
		_main._on_time_mode_requested("sim")
		await _frames(3)
		_main._settings_save_delay = -1.0
	_main._paused = true

func _ensure_playing() -> void:
	if _main == null:
		return
	if int(_main._mode) == 0:
		_log("[INFO] 进入游玩状态（_on_menu_start）...")
		_main._on_menu_start(bool(_main._started))
		var ok: bool = await _wait_until(func() -> bool:
			return int(_main._mode) == 1 and String(_main._blending) == "", 90.0)
		_log("[INFO] 游玩态就绪=%s（_mode=%d _blending=%s）" % [str(ok), int(_main._mode), String(_main._blending)])
		await _wait(0.5)
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

func _record(phase: String, name: String, result: String, detail: String) -> void:
	if result == "PASS":
		_passes += 1
	elif result == "WARN":
		_warns += 1
	elif result == "FAIL":
		_fails += 1
	elif result == "SKIP":
		_skips += 1
	_checks.append({"phase": phase, "name": name, "result": result, "detail": detail})
	_log("[%s][%s] %s：%s" % [result, phase, name, detail])

func _pass(phase: String, name: String, detail: String) -> void:
	_record(phase, name, "PASS", detail)

func _warn(phase: String, name: String, detail: String) -> void:
	_record(phase, name, "WARN", detail)

func _fail(phase: String, name: String, detail: String) -> void:
	_record(phase, name, "FAIL", detail)

func _skip(phase: String, name: String, detail: String) -> void:
	_record(phase, name, "SKIP", detail)

func _check(phase: String, name: String, cond: bool, detail: String) -> void:
	if cond:
		_pass(phase, name, detail)
	else:
		_fail(phase, name, detail)

func _finish() -> void:
	var dur := float(Time.get_ticks_msec() - _t0) / 1000.0
	_log("================================================================")
	for c in _checks:
		if String(c["result"]) == "FAIL":
			_log("[FAIL-SUMMARY] %s %s：%s" % [String(c["phase"]), String(c["name"]), String(c["detail"])])
	_log("[SUMMARY] total=%d pass=%d warn=%d fail=%d skip=%d shots=%d 耗时=%.1fs" % [
		_checks.size(), _passes, _warns, _fails, _skips, _shots.size(), dur])
	var data := {
		"probe": TAG, "owner": "wheel / task-5",
		"started_at": Time.get_datetime_string_from_system(true),
		"duration_sec": dur, "env": _env,
		"summary": {"total": _checks.size(), "pass": _passes, "warn": _warns, "fail": _fails, "skip": _skips},
		"checks": _checks, "shots": _shots,
	}
	var f := FileAccess.open(JSON_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "  "))
		f.close()
		_log("[INFO] 结果 JSON 写入 " + JSON_PATH)
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

func _set_size(w: int, h: int) -> void:
	if DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		await _frames(3)
	DisplayServer.window_set_size(Vector2i(w, h))
	await _frames(4)
	await _wait(0.2)

func _count_nodes(n) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count_nodes(ch)
	return c

## 整树节点路径集合（用于泄漏定位：Δ 为 0 才算不增长）。
func _node_path_set() -> Dictionary:
	var d := {}
	var stack: Array = [root]
	while not stack.is_empty():
		var n = stack.pop_back()
		var p := str(n.get_path())
		if p.begins_with("/root/Isle/Fx"):
			continue
		d[p] = true
		for ch in n.get_children():
			stack.append(ch)
	return d

func _diff_paths(a: Dictionary, b: Dictionary) -> Array:
	var out: Array = []
	for k in b.keys():
		if not a.has(k):
			out.append(String(k))
	out.sort()
	return out

func _shot(name: String, crop_canvas: Rect2 = Rect2()) -> void:
	await RenderingServer.frame_post_draw
	var tex := root.get_texture()
	var img: Image = tex.get_image() if tex != null else null
	if img == null:
		_fail("shot", name, "取不到 viewport 纹理")
		return
	var path := OUT_DIR + "/" + TAG + "_" + name + ".png"
	var sz := img.get_size()
	var err := img.save_png(path)
	if err == OK:
		_shots.append(path)
	else:
		_fail("shot", name, "save_png err=%d %s" % [err, path])
	if crop_canvas.size.x >= 2.0 and crop_canvas.size.y >= 2.0:
		var vr: Vector2 = root.get_visible_rect().size
		var k: float = float(sz.x) / maxf(1.0, vr.x)
		var r := Rect2i(int(round(crop_canvas.position.x * k)), int(round(crop_canvas.position.y * k)),
			int(round(crop_canvas.size.x * k)), int(round(crop_canvas.size.y * k)))
		r = r.intersection(Rect2i(0, 0, sz.x, sz.y))
		if r.size.x > 2 and r.size.y > 2:
			var cpath := path.get_basename() + "_wheel.png"
			var e2 := img.get_region(r).save_png(cpath)
			if e2 == OK:
				_shots.append(cpath)
	_log("[SHOT] " + path + "（纹理 %s）" % _vi(sz))

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
		await _frames(2)
	if bool(_hud._time_open):
		_hud.toggle_time_panel()
		await _frames(2)
	_hud._time_idle = -1000.0

func _parts() -> Dictionary:
	if _wheel == null:
		return {}
	return _wheel.call("get_parts")

func _parts_str(p: Dictionary) -> String:
	if p == null or p.is_empty():
		return "(空)"
	return "%04d-%02d-%02d %02d:%02d" % [int(p.get("year", 0)), int(p.get("month", 0)),
		int(p.get("day", 0)), int(p.get("hour", 0)), int(p.get("minute", 0))]

func _auth_parts() -> Dictionary:
	var d: Dictionary = _main._display_datetime()
	return {"year": int(d.get("year", 0)), "month": int(d.get("month", 0)),
		"day": int(d.get("day", 0)), "hour": int(d.get("hour", 0)), "minute": int(d.get("minute", 0))}

func _eq_parts(a: Dictionary, b: Dictionary) -> bool:
	for k in ["year", "month", "day", "hour", "minute"]:
		if int(a.get(k, -99999)) != int(b.get(k, -99999)):
			return false
	return true

func _col(field: String):
	if _wheel == null:
		return null
	return _wheel.call("debug_column", field)

func _set_test_parts(d: Dictionary) -> void:
	_hud._cal_dirty = true
	_wheel.call("set_parts", d)
	_hud._cal_draft = _parts()

func _sync_settle(max_steps: int = 1200) -> int:
	return int(_wheel.call("debug_settle", 1.0 / 120.0, max_steps))

func _col_state(field: String) -> String:
	var c = _col(field)
	if c == null:
		return "(空)"
	return "%s pos=%.4f vel=%.4f mode=%d val=%d range=%d..%d wrap=%s" % [
		field, float(c.pos), float(c.vel), int(c.mode), int(c.get_value()),
		int(c.min_value), int(c.max_value), str(bool(c.wrap))]

func _on_jump_sig(y: int, mo: int, d: int, h: int, mi: int) -> void:
	_jump_count += 1
	_jump_args = [y, mo, d, h, mi]

func _focus_name() -> String:
	var o = root.gui_get_focus_owner()
	if o == null or not is_instance_valid(o):
		return "(无)"
	var pname := "?"
	if o.get_parent() != null:
		pname = str(o.get_parent().name)
	return "%s/%s" % [pname, str(o.name)]

# ============================================================
# 输入注入（真实窗口坐标；先 warp 光标，与 P-1 一致）
# ============================================================

func _to_win(p: Vector2) -> Vector2:
	return p * _scale_now()

func _push(ev: InputEvent) -> void:
	root.push_input(ev)

func _press_mouse(pos_win: Vector2) -> void:
	Input.warp_mouse(pos_win)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos_win
	ev.global_position = pos_win
	_push(ev)
	_last_mouse = pos_win

func _release_mouse(pos_win: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = pos_win
	ev.global_position = pos_win
	_push(ev)
	_last_mouse = pos_win

func _motion_mouse(pos_win: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos_win
	ev.global_position = pos_win
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	_push(ev)
	_last_mouse = pos_win

func _inject_key(keycode: int, echo: bool = false, pressed: bool = true) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = pressed
	ev.echo = echo
	_push(ev)

func _col_center_win(field: String) -> Vector2:
	var c = _col(field)
	if c == null:
		return Vector2.ZERO
	var r: Rect2 = c.get_global_rect()
	return _to_win(r.position + r.size * 0.5)

## 在指定列上慢速拖动 rows 行（正=向下拖=值减小；负=向上拖=值增大）。
func _inject_drag_col(field: String, rows: float, steps: int = 60, step_wait: float = 0.025, trace: bool = false) -> void:
	var c = _col(field)
	if c == null:
		return
	var r: Rect2 = c.get_global_rect()
	var start := _to_win(r.position + r.size * 0.5)
	_log("[DRAG] field=%s rows=%.2f steps=%d scale=%.3f win=%s visible_rect=%s col_rect=%s start=%s panel_top=%.1f" % [
		field, rows, steps, _scale_now(), str(DisplayServer.window_get_size()), _fmt_vec2(root.get_visible_rect().size), _fmt_rect(r), str(start),
		float(_hud._time_panel.offset_top)])
	Input.warp_mouse(start)
	await _frames(2)
	_press_mouse(start)
	await _frames(2)
	_log("[DRAG] press后 press_down=%s drag_started=%s press_y=%.2f last_y=%.2f pos=%.4f mode=%d" % [
		str(bool(c._press_down)), str(bool(c._drag_started)), float(c._press_y), float(c._last_y), float(c.pos), int(c.mode)])
	var dy := (rows * ROW_H) / float(steps)
	var p := start
	# 拖动步进只移动 OS 光标（warp），由引擎产生真实 MouseMotion；不再叠发合成 motion 事件。
	# 原因（本轮实测）：合成事件不移动 OS 光标，真实位置刷新会把 event.position 报回按下点 →
	# last_y/pos 被重置（表现为真实拖 1 行结果 +2/+5 小时）；而"每步 warp + 每步合成 push"会让同帧内
	# 产生两个位置相同的 motion，_dt_since_last 极小 → inst/EMA 尖峰（实测 2.5~3.2 行/s）→ 误判惯性 → 多滑 1 行。
	# 只 warp：位置一致、dt 为真实帧间隔，等价于人手匀速拖动。见 docs/P8_2_05_NOTES.md §6.2。
	for i in range(steps):
		p.y += dy * _scale_now()
		Input.warp_mouse(p)
		await _wait(step_wait)
		if trace and (i < 3 or i % 10 == 0 or i >= steps - 2):
			_log("[DRAG] step %d p.y=%.2f drag_started=%s last_y=%.2f ema=%.3f pos=%.4f mode=%d panel_top=%.1f" % [
				i, p.y, str(bool(c._drag_started)), float(c._last_y), float(c._ema_vel), float(c.pos),
				int(c.mode), float(_hud._time_panel.offset_top)])
	_release_mouse(p)
	await _frames(3)
	var waited := 0.0
	while (int(c.mode) != 0 or absf(float(c.vel)) > 0.001) and waited < 2.0:
		await _wait(0.02)
		waited += 0.02
	_log("[DRAG] release后 pos=%.4f mode=%d vel=%.3f ema=%.3f value=%d" % [
		float(c.pos), int(c.mode), float(c.vel), float(c._ema_vel), int(c.get_value())])

func _inject_wheel_event(up: bool, pressed: bool) -> void:
	var pos := _col_center_win("minute")
	Input.warp_mouse(pos)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	_push(ev)

# ============================================================
# U-05 物理工具：拖拽 + 释放 + 轨迹采样（同步 debug_tick，避免真实帧干扰）
# ============================================================

func _drag_release(field: String, rows: float, speed: float, dt: float = 1.0 / 60.0) -> Dictionary:
	var y0 := 70.0
	var step_px := speed * ROW_H * dt
	if step_px < 0.05:
		step_px = 0.05
	var n := int(maxf(12.0, ceil(absf(rows) * ROW_H / step_px)))
	n = mini(n, 400)
	var dir := 1.0 if rows >= 0.0 else -1.0
	_wheel.call("debug_begin_drag", field, y0)
	var y := y0
	for i in range(n):
		y += dir * step_px
		_wheel.call("debug_drag_to", field, y, dt)
	var col = _col(field)
	var ema := float(col._ema_vel)
	var pos_before := float(col.pos)
	_wheel.call("debug_end_drag", field, dt)
	var mode_after := int(col.mode)
	var vel_after := float(col.vel)
	var steps := 0
	var prev := float(col.pos)
	var max_step := 0.0
	var traj: Array = [prev]
	var last_mode := mode_after
	var transition_step := -1
	var vel_monotone := true
	var last_abs_vel := absf(float(col.vel))
	while steps < 1500 and int(col.mode) != 0:
		_wheel.call("debug_tick", dt)
		steps += 1
		var p := float(col.pos)
		max_step = maxf(max_step, absf(p - prev))
		prev = p
		traj.append(p)
		var m := int(col.mode)
		if m != last_mode:
			if last_mode == 2 and m == 3:
				transition_step = steps
			last_mode = m
		if m == 2:
			var av := absf(float(col.vel))
			if av > last_abs_vel + 1e-9:
				vel_monotone = false
			last_abs_vel = av
	return {"n": n, "ema": ema, "pos_before": pos_before, "mode_after": mode_after,
		"vel_after": vel_after, "steps": steps, "time": float(steps) * dt,
		"pos_after": float(col.pos), "value_after": int(col.get_value()),
		"max_step": max_step, "traj": traj, "transition_step": transition_step,
		"vel_monotone": vel_monotone}

## 临界阻尼解析解（与产品 mode=3 同公式）到 |x|<0.01 且 |vel|<0.05 所需时间。
func _settle_time_expect(x0: float, dt: float) -> float:
	var x := absf(x0)
	var vel := 0.0
	var t := 0.0
	while t < 5.0:
		var e := exp(-18.0 * dt)
		var b := vel + 18.0 * x
		var nx := (x + b * dt) * e
		var nv := (b - 18.0 * (x + b * dt)) * e
		x = nx
		vel = nv
		t += dt
		if absf(x) < 0.01 and absf(vel) < 0.05:
			return t
	return -1.0

func _traj_overshoot(traj: Array, target: float, start: float) -> float:
	var ov := 0.0
	if start < target:
		for p in traj:
			ov = maxf(ov, float(p) - target)
	else:
		for p in traj:
			ov = maxf(ov, target - float(p))
	return maxf(0.0, ov)

# ============================================================
# P-2 假 dirty / 草稿回灌
# ============================================================

func _sec_p2_dirty() -> void:
	_log("----------------------------------------------------------------")
	_log("[P2] 假 dirty / 草稿回灌语义（窗口实测）")
	_main._paused = true
	await _close_all_panels()
	await _open_calendar()
	_keep()
	_hud._cal_dirty = false
	await _frames(3)
	var d0 := bool(_hud._cal_dirty)
	await _wait(0.4)
	var d1 := bool(_hud._cal_dirty)
	var auth := _auth_parts()
	var wp := _parts()
	_check("P2", "打开日历 0.4s 内无假 dirty", (not d0) and (not d1),
		"t0=%s t+0.4s=%s 权威=%s 滚轮=%s" % [str(d0), str(d1), _parts_str(auth), _parts_str(wp)])
	_check("P2", "打开后滚轮草稿=权威时间", _eq_parts(auth, wp),
		"权威=%s 滚轮=%s" % [_parts_str(auth), _parts_str(wp)])
	# 一次滚轮 notch → dirty=true 且数值改变
	_wheel.call("debug_notch", "minute", -1)
	_sync_settle()
	await _frames(2)
	var d2 := bool(_hud._cal_dirty)
	var wp2 := _parts()
	_check("P2", "一次 notch 后 _cal_dirty=true 且数值改变", d2 and (not _eq_parts(auth, wp2)),
		"dirty=%s 权威=%s 滚轮=%s" % [str(d2), _parts_str(auth), _parts_str(wp2)])
	# 跳转 → dirty=false，滚轮=新权威
	var draft_before := _parts()
	_hud._on_cal_jump()
	await _frames(3)
	var d3 := bool(_hud._cal_dirty)
	var auth2 := _auth_parts()
	_check("P2", "跳转后 _cal_dirty=false 且滚轮=权威", (not d3) and _eq_parts(auth2, _parts()),
		"跳转草稿=%s 权威=%s dirty=%s" % [_parts_str(draft_before), _parts_str(auth2), str(d3)])
	# 关闭面板丢弃未确认编辑
	_wheel.call("debug_notch", "minute", 3)
	_sync_settle()
	await _frames(2)
	var dirty_edit := bool(_hud._cal_dirty)
	await _close_all_panels()
	await _open_calendar()
	_keep()
	var auth3 := _auth_parts()
	_check("P2", "关闭面板丢弃未确认编辑（重开=权威）",
		dirty_edit and _eq_parts(auth3, _parts()),
		"关闭前 dirty=%s 权威=%s 重开草稿=%s" % [str(dirty_edit), _parts_str(auth3), _parts_str(_parts())])

# ============================================================
# U-05 滚轮吸附手感 / 惯性 / 阈值 / 橡皮筋 / 真实鼠标滚轮与拖动
# ============================================================

func _sec_u05() -> void:
	_log("----------------------------------------------------------------")
	_log("[U05] 滚轮吸附手感 / 惯性 / 阈值 / 橡皮筋 / 真实鼠标")
	_main._paused = true
	await _open_calendar()
	_keep()
	var base := {"year": 2026, "month": 10, "day": 22, "hour": 10, "minute": 0}

	# --- 1) 慢拖 0.6 行 → 释放走弹簧吸附 ---
	_set_test_parts(base)
	var snap := _drag_release("hour", 0.6, 0.6, 1.0 / 120.0)
	var snap_target := float(round(float(snap["pos_after"])))
	var ov := _traj_overshoot(snap["traj"], snap_target, float(snap["pos_before"]))
	_check("U05", "慢拖释放走弹簧吸附（mode=3）", int(snap["mode_after"]) == 3,
		"EMA=%.3f 行/s pos %.3f→%.3f mode_after=%d" % [float(snap["ema"]),
			float(snap["pos_before"]), float(snap["pos_after"]), int(snap["mode_after"])])
	var snap_x0 := absf(float(snap["pos_before"]) - snap_target)
	var snap_expect := _settle_time_expect(snap_x0, 1.0 / 120.0)
	var snap_ratio := float(snap["time"]) / snap_expect if snap_expect > 1e-6 else -1.0
	_check("U05", "吸附收敛时间≈临界阻尼解析解（ω=18 ζ=1，dt=1/120）",
		snap_expect > 0.0 and snap_ratio >= 0.6 and snap_ratio <= 1.6,
		"steps=%d time=%.3fs 起始偏移=%.3f 行 解析期望=%.3fs 比值=%.2f" % [
			int(snap["steps"]), float(snap["time"]), snap_x0, snap_expect, snap_ratio])
	_check("U05", "吸附无超调（|过冲|≤0.01 行）", ov <= 0.01,
		"过冲=%.4f 行（起始 pos=%.3f 目标=%.1f）" % [ov, float(snap["pos_before"]), snap_target])
	_check("U05", "吸附后落在整数行且 vel=0", absf(float(snap["pos_after"]) - snap_target) < 1e-6,
		"pos_after=%.4f 值=%d" % [float(snap["pos_after"]), int(snap["value_after"])])

	# --- 2) 惯性甩动（慢速 2.2 行/s 与快速 6 行/s） ---
	for sp in [2.2, 6.0]:
		_set_test_parts(base)
		var fl := _drag_release("hour", 1.2, float(sp))
		var glide := float(fl["pos_after"]) - float(fl["pos_before"])
		var mglide := glide
		var tr := int(fl["transition_step"])
		var traj: Array = fl["traj"]
		if tr > 0 and tr <= traj.size():
			mglide = float(traj[tr - 1]) - float(fl["pos_before"])
		var expect := absf(float(fl["vel_after"])) / 6.0
		var ratio := absf(mglide) / expect if expect > 1e-6 else -1.0
		_check("U05", "甩动 %.1f 行/s 进入惯性（mode=2）" % sp, int(fl["mode_after"]) == 2,
			"EMA=%.2f vel_after=%.2f 行/s" % [float(fl["ema"]), float(fl["vel_after"])])
		_check("U05", "甩动 %.1f 行/s 速度单调衰减并收敛" % sp,
			bool(fl["vel_monotone"]) and int(fl["steps"]) < 1500 and absf(float(fl["pos_after"]) - round(float(fl["pos_after"]))) < 1e-6,
			"steps=%d time=%.3fs max_step=%.3f 行（无跳变）" % [int(fl["steps"]), float(fl["time"]), float(fl["max_step"])])
		_check("U05", "甩动 %.1f 行/s 惯性滑行距离≈v/6" % sp, ratio >= 0.6 and ratio <= 1.4,
			"惯性段滑行=%.3f 行（含吸附总位移=%.3f）期望≈%.3f 比值=%.2f（v=%.2f 行/s）" % [
				mglide, glide, expect, ratio, float(fl["vel_after"])])

	# --- 3) 惯性阈值扫描（end_drag 用 FLICK_THRESHOLD 常量=1.2 行/s；P8.2-05 已去掉重复字面量，数值未改）---
	var sweep: Array = []
	for sv in [0.3, 0.7, 1.0, 1.3, 2.0, 5.0]:
		_set_test_parts(base)
		var r := _drag_release("hour", 1.0, float(sv))
		sweep.append({"speed": float(sv), "ema": float(r["ema"]), "mode": int(r["mode_after"])})
		_log("[U05] 阈值扫描 speed=%.1f 行/s EMA=%.3f → mode=%d（2=惯性 3=吸附）" % [
			float(sv), float(r["ema"]), int(r["mode_after"])])
	var boundary := -1.0
	var mono := true
	var seen_momentum := false
	for s in sweep:
		var is_m := int(s["mode"]) == 2
		if is_m and boundary < 0.0:
			boundary = float(s["speed"])
		if seen_momentum and not is_m:
			mono = false
		if is_m:
			seen_momentum = true
	var ft_const := -1.0
	var cmap = _wheel.get_script().get_script_constant_map()
	if cmap != null and cmap.has("FLICK_THRESHOLD"):
		ft_const = float(cmap["FLICK_THRESHOLD"])
	_check("U05", "惯性阈值边界在 1.0—1.4 行/s", boundary > 1.0 and boundary <= 1.4,
		"实测边界=%.1f 行/s（EMA 滞后）；常量 FLICK_THRESHOLD=%.2f，end_drag 引用该常量（P8.2-05 去重，数值未改）" % [boundary, ft_const])
	_check("U05", "阈值扫描单调（低→吸附 高→惯性）", mono,
		"扫描=%s" % JSON.stringify(sweep))

	# --- 4) 年列橡皮筋（±0.25 行）与越界 notch 回弹 ---
	_set_test_parts({"year": 1, "month": 1, "day": 1, "hour": 0, "minute": 0})
	var yc = _col("year")
	_wheel.call("debug_begin_drag", "year", 70.0)
	_wheel.call("debug_drag_to", "year", 70.0 + 3.0 * ROW_H, 1.0 / 60.0)
	var pos_drag := float(yc.pos)
	_wheel.call("debug_end_drag", "year", 1.0 / 60.0)
	var min_pos := pos_drag
	var steps := 0
	while steps < 1500 and int(yc.mode) != 0:
		_wheel.call("debug_tick", 1.0 / 60.0)
		steps += 1
		min_pos = minf(min_pos, float(yc.pos))
	_check("U05", "1 年下界橡皮筋限位 0.25 行",
		absf(pos_drag - (1.0 - 0.25)) < 1e-4,
		"拖 3 行后 pos=%.4f（期望 0.7500）" % pos_drag)
	_check("U05", "下界橡皮筋回弹到 1 且越界不塌陷", min_pos >= 0.75 - 1e-4 and int(yc.get_value()) == 1,
		"过程中 min_pos=%.4f 终值=%d 终 pos=%.4f steps=%d" % [min_pos, int(yc.get_value()), float(yc.pos), steps])
	_set_test_parts({"year": 9999, "month": 12, "day": 31, "hour": 23, "minute": 59})
	var yc2 = _col("year")
	_wheel.call("debug_begin_drag", "year", 70.0)
	_wheel.call("debug_drag_to", "year", 70.0 - 3.0 * ROW_H, 1.0 / 60.0)
	var pos_drag2 := float(yc2.pos)
	_wheel.call("debug_end_drag", "year", 1.0 / 60.0)
	var max_pos := pos_drag2
	steps = 0
	while steps < 1500 and int(yc2.mode) != 0:
		_wheel.call("debug_tick", 1.0 / 60.0)
		steps += 1
		max_pos = maxf(max_pos, float(yc2.pos))
	_check("U05", "9999 年上界橡皮筋限位 0.25 行",
		absf(pos_drag2 - (9999.0 + 0.25)) < 1e-3,
		"拖 3 行后 pos=%.4f（期望 9999.2500）" % pos_drag2)
	_check("U05", "上界橡皮筋回弹到 9999", max_pos <= 9999.25 + 1e-3 and int(yc2.get_value()) == 9999,
		"过程中 max_pos=%.4f 终值=%d 终 pos=%.4f steps=%d" % [max_pos, int(yc2.get_value()), float(yc2.pos), steps])
	# 越界 notch 回弹（不改变值）
	_wheel.call("debug_notch", "year", 1)
	var pos_notch := float(yc2.pos)
	_sync_settle()
	_check("U05", "9999 年 notch 越界回弹不改值", absf(pos_notch - 9999.25) < 1e-3 and int(yc2.get_value()) == 9999,
		"notch 后 pos=%.4f 终值=%d 终 pos=%.4f" % [pos_notch, int(yc2.get_value()), float(yc2.pos)])

	# --- 5) 循环列 / 日列钳制 ---
	_set_test_parts({"year": 2026, "month": 12, "day": 1, "hour": 23, "minute": 59})
	_wheel.call("debug_notch", "hour", 1)
	_sync_settle()
	_wheel.call("debug_notch", "minute", 1)
	_sync_settle()
	_wheel.call("debug_notch", "month", 1)
	_sync_settle()
	var wrap_parts := _parts()
	_check("U05", "时/分/月循环进 1", int(wrap_parts["hour"]) == 0 and int(wrap_parts["minute"]) == 0 and int(wrap_parts["month"]) == 1,
		"23:59 月 12 → %s" % _parts_str(wrap_parts))
	# 1/31 → 2/1：日列上限随月收敛到 28
	_set_test_parts({"year": 2026, "month": 1, "day": 31, "hour": 12, "minute": 0})
	_wheel.call("debug_notch", "month", 1)
	_sync_settle()
	var feb := _parts()
	var dc = _col("day")
	_check("U05", "1/31 改月后日列钳制到 2 月上限", int(feb["month"]) == 2 and int(feb["day"]) == 28 and int(dc.max_value) == 28,
		"改月后=%s 日列 range=1..%d" % [_parts_str(feb), int(dc.max_value)])
	# 日列下界不循环
	_set_test_parts({"year": 2026, "month": 1, "day": 1, "hour": 12, "minute": 0})
	_wheel.call("debug_notch", "day", -1)
	var day_pos := float(_col("day").pos)
	_sync_settle()
	_check("U05", "日列下界不循环（1 保持 1，0.25 行回弹）",
		int(_parts()["day"]) == 1 and absf(day_pos - 0.75) < 1e-3,
		"notch 后 pos=%.4f 终值=%d" % [day_pos, int(_parts()["day"])])

	# --- 6) 真实鼠标拖动（push_input，窗口坐标） ---
	_set_test_parts({"year": 2026, "month": 10, "day": 22, "hour": 10, "minute": 0})
	await _frames(2)
	var before_drag := _parts()
	await _inject_drag_col("hour", -1.0, 60, 0.025, true)
	await _wait_until(func() -> bool: return not bool(_wheel.call("is_busy")), 3.0)
	var after_drag := _parts()
	_check("U05", "真实鼠标向上拖 1 行 → 小时 +1", int(after_drag["hour"]) == int(before_drag["hour"]) + 1,
		"%s → %s" % [_parts_str(before_drag), _parts_str(after_drag)])
	var hour_col = _col("hour")
	_check("U05", "真实拖动释放后无残留漂移（mode=0 vel=0 pos 整数）",
		int(hour_col.mode) == 0 and absf(float(hour_col.vel)) < 1e-6 and absf(float(hour_col.pos) - round(float(hour_col.pos))) < 1e-6,
		_col_state("hour"))
	await _shot("u05_after_real_drag", _wheel.get_global_rect())

	# --- 7) 真实鼠标滚轮 notch（P-3 双 notch 验证） ---
	var w_before := _parts()
	_inject_wheel_event(true, true)
	await _frames(2)
	_inject_wheel_event(true, false)
	await _frames(2)
	await _wait_until(func() -> bool: return not bool(_wheel.call("is_busy")), 3.0)
	var w_after1 := _parts()
	_check("U05", "真实滚轮 1 次(WHEEL_UP pressed+released) = 1 notch（P-3 无双 notch）",
		int(w_after1["minute"]) == _wrap_dec(int(w_before["minute"]), -1),
		"%s → %s" % [_parts_str(w_before), _parts_str(w_after1)])
	var w_mid := _parts()
	_inject_wheel_event(true, false)
	await _frames(2)
	await _wait_until(func() -> bool: return not bool(_wheel.call("is_busy")), 3.0)
	_check("U05", "只有 released 的滚轮事件被忽略（不重复滚格）", _eq_parts(w_mid, _parts()),
		"%s → %s" % [_parts_str(w_mid), _parts_str(_parts())])
	var w_before2 := _parts()
	_inject_wheel_event(false, true)
	await _frames(2)
	_inject_wheel_event(false, false)
	await _frames(2)
	await _wait_until(func() -> bool: return not bool(_wheel.call("is_busy")), 3.0)
	_check("U05", "真实滚轮 WHEEL_DOWN = +1 notch",
		int(_parts()["minute"]) == _wrap_dec(int(w_before2["minute"]), 1),
		"%s → %s" % [_parts_str(w_before2), _parts_str(_parts())])
	# 合成点击命中（无 warp 观测，P-1 复现记录；本探针所有真实路径注入均先 warp）
	Input.warp_mouse(Vector2.ZERO)
	await _frames(2)
	var hover0 := root.gui_get_hovered_control()
	_warn("U05", "P-1 合成输入需 warp（环境复现记录）",
		"warp(0,0) 后 hovered=%s；本探针真实路径均先 warp 再注入（与 P8.1 P-1 结论一致，属探针环境限制非产品缺陷）" % str(hover0.name if hover0 != null else "(null)"))

	# --- 8) 全部交互后无残留漂移 ---
	_hud._cal_dirty = true
	_wheel.call("set_parts", base)
	_sync_settle()
	for i in range(240):
		_wheel.call("debug_tick", 1.0 / 120.0)
	var drift := ""
	var all_ok := true
	for f in FIELDS:
		var c = _col(f)
		if absf(float(c.pos) - round(float(c.pos))) > 1e-6 or absf(float(c.vel)) > 1e-6 or int(c.mode) != 0:
			all_ok = false
			drift += " [" + _col_state(f) + "]"
	_check("U05", "空闲 2s 后五列无残留漂移", all_ok, "状态=" + (drift if not all_ok else "五列全部 mode=0 vel=0 pos 整数"))

func spin(v: float) -> String:
	return "%.1f" % v

func _wrap_dec(v: int, d: int) -> int:
	return posmod(v + d, 60)

# ============================================================
# U-12 键重复率（key echo）
# ============================================================

func _sec_u12() -> void:
	_log("----------------------------------------------------------------")
	_log("[U12] 键盘重复率（key echo）/ 方向键单步")
	_main._paused = true
	await _open_calendar()
	_keep()
	_set_test_parts({"year": 2026, "month": 10, "day": 22, "hour": 18, "minute": 10})
	await _frames(2)
	var mc = _col("minute")
	mc.grab_focus()
	await _frames(2)
	var f0 := _focus_name()
	var v0 := int(_parts()["minute"])
	# 直达焦点控件的 10 次 echo 事件
	for i in range(10):
		var ev := InputEventKey.new()
		ev.keycode = KEY_DOWN
		ev.physical_keycode = KEY_DOWN
		ev.pressed = true
		ev.echo = true
		mc.call("_gui_input", ev)
	await _frames(2)
	var v1 := int(_parts()["minute"])
	_check("U12", "10 次 echo=true 按键不改变数值（handler 路径）", v1 == v0,
		"focus=%s %d → %d" % [f0, v0, v1])
	# 经视口输入管线（焦点路由）的 10 次 echo
	for i in range(10):
		_inject_key(KEY_DOWN, true, true)
	await _frames(2)
	var v2 := int(_parts()["minute"])
	_check("U12", "10 次 echo=true 经 GUI 焦点路由不改变数值", v2 == v0,
		"焦点=%s %d → %d" % [_focus_name(), v0, v2])
	# 10 次真实按下（echo=false）
	for i in range(10):
		_inject_key(KEY_DOWN, false, true)
		await _frames(1)
	_inject_key(KEY_DOWN, false, false)
	await _wait_until(func() -> bool: return not bool(_wheel.call("is_busy")), 3.0)
	var v3 := int(_parts()["minute"])
	_check("U12", "10 次真实 KEY_DOWN → 分钟 +10（10→20）", v3 == 20,
		"%d → %d（焦点=%s）" % [v0, v3, _focus_name()])
	# 直达 handler 的 3 次真实按下
	for i in range(3):
		var ev2 := InputEventKey.new()
		ev2.keycode = KEY_DOWN
		ev2.physical_keycode = KEY_DOWN
		ev2.pressed = true
		mc.call("_gui_input", ev2)
	await _frames(2)
	await _wait_until(func() -> bool: return not bool(_wheel.call("is_busy")), 3.0)
	var v4 := int(_parts()["minute"])
	_check("U12", "handler 路径 3 次真实按下 → 分钟 +3", v4 == 23, "%d → %d" % [v3, v4])
	_warn("U12", "真机 OS 自动重复率无法在自动化中测量（披露）",
		"本探针用合成 echo 标记模拟 OS key-repeat；产品在 ui_datetime_wheel.gd:736 对 echo 直接 return，任何 OS 重复率都不会重复计步；真机重复率建议人工长按观察")

# ============================================================
# U-06 TAB / 焦点遍历
# ============================================================

func _sec_u06() -> void:
	_log("----------------------------------------------------------------")
	_log("[U06] TAB / 方向键焦点遍历（真实按键注入）")
	_main._paused = true
	await _open_calendar()
	_keep()
	_set_test_parts({"year": 2026, "month": 10, "day": 22, "hour": 18, "minute": 47})
	_wheel.call("focus_first")
	await _frames(2)
	var seq: Array = [_focus_name()]
	for i in range(6):
		_inject_key(KEY_TAB, false, true)
		await _frames(2)
		_inject_key(KEY_TAB, false, false)
		await _frames(2)
		seq.append(_focus_name())
	_log("[U06] TAB 焦点序列=" + JSON.stringify(seq))
	var expect := ["DateTimeWheel/Wheel_month", "DateTimeWheel/Wheel_day", "DateTimeWheel/Wheel_hour", "DateTimeWheel/Wheel_minute"]
	var tab_ok := true
	for i in range(4):
		if seq[i + 1] != expect[i]:
			tab_ok = false
	_check("U06", "TAB 依次遍历 5 列（year→month→day→hour→minute）", tab_ok,
		"序列=%s" % JSON.stringify(seq))
	var almanac_after := bool(_hud._almanac_open)
	_check("U06", "TAB 遍历滚轮时不误触发天文历面板", not almanac_after,
		"_almanac_open=%s（TAB 第 5 次后焦点=%s）" % [str(almanac_after), String(seq[5])])
	_warn("U06", "TAB 到 minute 后离开滚轮（记录行为，非缺陷）",
		"第 5 次 TAB 后焦点=%s；滚轮列在 HUD 控件树的 TAB 顺序内，但不会在 5 列间循环" % String(seq[5]))
	# 方向键：RIGHT 到末列夹取，LEFT 回到首列
	_wheel.call("focus_first")
	await _frames(2)
	var right_seq: Array = [_focus_name()]
	for i in range(6):
		_inject_key(KEY_RIGHT, false, true)
		await _frames(2)
		_inject_key(KEY_RIGHT, false, false)
		await _frames(2)
		right_seq.append(_focus_name())
	var right_ok: bool = right_seq[0] == "DateTimeWheel/Wheel_year" \
		and right_seq[1] == "DateTimeWheel/Wheel_month" \
		and right_seq[2] == "DateTimeWheel/Wheel_day" \
		and right_seq[3] == "DateTimeWheel/Wheel_hour" \
		and right_seq[4] == "DateTimeWheel/Wheel_minute" \
		and right_seq[5] == "DateTimeWheel/Wheel_minute" \
		and right_seq[6] == "DateTimeWheel/Wheel_minute"
	_check("U06", "右方向键逐列右移并在 minute 夹取", right_ok, "序列=" + JSON.stringify(right_seq))
	_wheel.call("focus_first")
	await _frames(2)
	var left_seq: Array = [_focus_name()]
	for i in range(6):
		_inject_key(KEY_LEFT, false, true)
		await _frames(2)
		_inject_key(KEY_LEFT, false, false)
		await _frames(2)
		left_seq.append(_focus_name())
	var left_ok: bool = left_seq[0] == "DateTimeWheel/Wheel_year" and left_seq[1] == "DateTimeWheel/Wheel_year" \
		and left_seq[2] == "DateTimeWheel/Wheel_year"
	_check("U06", "左方向键在 year 夹取（不循环）", left_ok, "序列=" + JSON.stringify(left_seq))
	# 焦点可见下划线截图
	var mc = _col("minute")
	mc.grab_focus()
	await _frames(3)
	await _shot("u06_focus_minute", _wheel.get_global_rect())

# ============================================================
# U-07 并发面板 / 焦点切换
# ============================================================

func _sec_u07() -> void:
	_log("----------------------------------------------------------------")
	_log("[U07] 多面板并发（时间+日历+天文历+天气+性能）")
	_main._paused = true
	await _close_all_panels()
	await _open_calendar()
	_keep()
	var opened: Array = []
	if not bool(_hud._almanac_open):
		_hud.toggle_almanac()
		opened.append("almanac")
	if not bool(_hud._weather_open):
		_hud.toggle_weather_panel()
		opened.append("weather")
	if not bool(_hud._perf_open):
		_hud.toggle_perf()
		opened.append("perf")
	await _frames(4)
	_hud._time_idle = -1000.0
	_hud._weather_idle = -1000.0
	var all_open := bool(_hud._time_open) and bool(_hud._cal_open) and bool(_hud._almanac_open) \
		and bool(_hud._weather_open) and bool(_hud._perf_open)
	_check("U07", "5 个面板可同时打开且不崩溃", all_open,
		"time=%s cal=%s almanac=%s weather=%s perf=%s（新开=%s）" % [
			str(bool(_hud._time_open)), str(bool(_hud._cal_open)), str(bool(_hud._almanac_open)),
			str(bool(_hud._weather_open)), str(bool(_hud._perf_open)), str(opened)])
	await _shot("u07_concurrent_panels")
	# 并发下面板仍响应：滚轮 notch + 焦点
	_set_test_parts({"year": 2026, "month": 10, "day": 22, "hour": 18, "minute": 30})
	await _frames(2)
	var mc = _col("minute")
	mc.grab_focus()
	await _frames(2)
	var before := int(_parts()["minute"])
	_wheel.call("debug_notch", "minute", -1)
	_sync_settle()
	var after := int(_parts()["minute"])
	_check("U07", "并发面板下滚轮仍响应（notch 生效）且保持焦点",
		after == _wrap_dec(before, -1) and mc.has_focus(),
		"%d → %d 焦点=%s" % [before, after, _focus_name()])
	# 关闭所有面板后滚轮不可见、状态复位
	_hud.toggle_perf()
	_hud.toggle_weather_panel()
	_hud.toggle_almanac()
	await _frames(2)
	await _close_all_panels()
	await _frames(2)
	_check("U07", "关闭全部面板后滚轮隐藏且 busy=false",
		(not _wheel.is_visible_in_tree()) and (not bool(_wheel.call("is_busy"))),
		"visible_in_tree=%s busy=%s time_open=%s cal_open=%s" % [
			str(_wheel.is_visible_in_tree()), str(bool(_wheel.call("is_busy"))),
			str(bool(_hud._time_open)), str(bool(_hud._cal_open))])

# ============================================================
# U-08 跨午夜 / 跨月 / 跨年（sim 自然跨越 + real 显示函数注入）
# ============================================================

func _sec_u08() -> void:
	_log("----------------------------------------------------------------")
	_log("[U08] 跨午夜 / 跨月 / 跨闰年（模拟时间自然跨越 + 现实时间显示注入）")
	_main._paused = true
	await _close_all_panels()
	await _open_calendar()
	_keep()
	var saved_paused := bool(_main._paused)
	var saved_len := float(_main._day_length)
	var saved_sim := float(_main._sim_seconds)
	_main._day_length = 14400.0
	var cases := [
		{"name": "跨年 2026-12-31→2027-01-01", "y": 2026, "mo": 12, "d": 31, "h": 23, "mi": 59, "s": 58,
			"ey": 2027, "emo": 1, "ed": 1, "edmax": 31},
		{"name": "跨月 2026-01-31→2026-02-01", "y": 2026, "mo": 1, "d": 31, "h": 23, "mi": 59, "s": 58,
			"ey": 2026, "emo": 2, "ed": 1, "edmax": 28},
		{"name": "闰日 2028-02-28→2028-02-29", "y": 2028, "mo": 2, "d": 28, "h": 23, "mi": 59, "s": 58,
			"ey": 2028, "emo": 2, "ed": 29, "edmax": 29},
	]
	for c in cases:
		var before_local := Cal.to_local_seconds(int(c["y"]), int(c["mo"]), int(c["d"]), int(c["h"]), int(c["mi"]), int(c["s"]))
		_main._sim_seconds = before_local
		_main._events_timer = 0.0
		_main._paused = false
		await _frames(2)
		var dt_before: Dictionary = _main._display_datetime()
		var crossed := false
		var t_wait := 0.0
		while t_wait < 4.0:
			await _wait(0.05)
			t_wait += 0.05
			var dd: Dictionary = _main._display_datetime()
			if int(dd.get("day", 0)) != int(dt_before.get("day", 0)) or int(dd.get("month", 0)) != int(dt_before.get("month", 0)):
				crossed = true
				break
		_main._paused = true
		await _wait(0.3)  # 等 HUD 0.12s 刷新 cadence + 滚轮草稿跟随权威时间
		var dt_after: Dictionary = _main._display_datetime()
		var clock_text := String(_hud._clock_text)
		var date_text := String(_hud._date.text)
		var parts_ok := int(dt_after.get("year", 0)) == int(c["ey"]) \
			and int(dt_after.get("month", 0)) == int(c["emo"]) \
			and int(dt_after.get("day", 0)) == int(c["ed"])
		_check("U08", String(c["name"]) + " 自然跨越成功",
			crossed and parts_ok,
			"前=%04d-%02d-%02d %02d:%02d 后=%04d-%02d-%02d %02d:%02d（等待 %.2fs 门限=%.2f 秒/秒）" % [
				int(dt_before.get("year", 0)), int(dt_before.get("month", 0)), int(dt_before.get("day", 0)),
				int(dt_before.get("hour", 0)), int(dt_before.get("minute", 0)),
				int(dt_after.get("year", 0)), int(dt_after.get("month", 0)), int(dt_after.get("day", 0)),
				int(dt_after.get("hour", 0)), int(dt_after.get("minute", 0)), t_wait, float(_main._sim_rate)])
		_check("U08", String(c["name"]) + " HUD 时钟/日期文本同步",
			clock_text.begins_with("00:0") and date_text.contains("%04d年%d月%d日" % [int(c["ey"]), int(c["emo"]), int(c["ed"])]),
			"clock='%s' date='%s'" % [clock_text, date_text])
		var day_col = _col("day")
		var wp := _parts()
		_check("U08", String(c["name"]) + " 日列上限/草稿跟随权威时间",
			int(day_col.max_value) == int(c["edmax"]) and _eq_parts(_auth_parts(), wp),
			"日列 range=1..%d 权威=%s 草稿=%s" % [int(day_col.max_value), _parts_str(_auth_parts()), _parts_str(wp)])
	_main._day_length = saved_len
	_main._paused = saved_paused
	_main._sim_seconds = saved_sim
	_main._events_timer = 0.0
	_main._settings_save_delay = -1.0
	await _frames(3)

	# --- 现实时间显示路径注入（不改 main.gd：同步设 _abs_unix 后立即读，避免下一帧被系统时间覆盖）---
	var saved_src := String(_main._time_source)
	var saved_real := bool(_main._realtime)
	var saved_abs := float(_main._abs_unix)
	var off_now := float(_main._offset_for(_main._abs_unix))
	var local_a := Cal.to_local_seconds(2026, 12, 31, 23, 59, 59)
	# 显示路径为 Time.get_datetime_dict_from_unix_time(int(_abs_unix + _offset_for(_abs_unix)))：
	# 必须用「目标时刻」的偏移反解 unix，否则在 epoch 附近 _offset_for 返回 0 会整体 +8h（探针 v1 失败原因）。
	var off_target := float(_main._offset_for(local_a - off_now))
	_main._time_source = "real"
	_main._realtime = true
	_main._abs_unix = local_a - off_target
	var d1: Dictionary = _main._display_datetime()
	var c1 := String(_main._display_clock_text())
	var off_after := float(_main._offset_for(local_a + 6.0 - off_target))
	_main._abs_unix = (local_a + 6.0) - off_after
	var d2: Dictionary = _main._display_datetime()
	var c2 := String(_main._display_clock_text())
	_main._time_source = saved_src
	_main._realtime = saved_real
	_main._abs_unix = saved_abs
	_main._settings_save_delay = -1.0
	_check("U08", "现实时间 23:59:59 显示正确", int(d1.get("year", 0)) == 2026 and int(d1.get("month", 0)) == 12 \
		and int(d1.get("day", 0)) == 31 and int(d1.get("hour", 0)) == 23 and int(d1.get("minute", 0)) == 59 and c1 == "23:59",
		"%04d-%02d-%02d %02d:%02d:%02d clock=%s 偏移=%d" % [
			int(d1.get("year", 0)), int(d1.get("month", 0)), int(d1.get("day", 0)),
			int(d1.get("hour", 0)), int(d1.get("minute", 0)), int(d1.get("second", 0)), c1, int(off_target)])
	_check("U08", "现实时间 +6s 跨到 2027-01-01 00:00:05（日期进位）",
		int(d2.get("year", 0)) == 2027 and int(d2.get("month", 0)) == 1 and int(d2.get("day", 0)) == 1 \
		and int(d2.get("hour", 0)) == 0 and int(d2.get("minute", 0)) == 0 and int(d2.get("second", 0)) == 5 and c2 == "00:00",
		"%04d-%02d-%02d %02d:%02d:%02d clock=%s 星期=%s" % [
			int(d2.get("year", 0)), int(d2.get("month", 0)), int(d2.get("day", 0)),
			int(d2.get("hour", 0)), int(d2.get("minute", 0)), int(d2.get("second", 0)), c2,
			String(Cal.parts(local_a + 6.0).get("weekday_cn", ""))])
	_check("U08", "现实时间注入后现场已恢复（_time_source/_abs_unix）",
		String(_main._time_source) == saved_src and absf(float(_main._abs_unix) - saved_abs) < 1.0,
		"_time_source=%s _abs_unix=%.1f（原 %.1f）" % [String(_main._time_source), float(_main._abs_unix), saved_abs])
	_warn("U08", "现实时间 23:59:59→00:00:05 为同步注入而非真实等待（披露）",
		"main.gd:_advance_sim 现实模式每帧重取系统时间，无法在不改 main.gd 的前提下注入；本项验证 _display_datetime/_display_clock_text 显示路径的日期进位，模拟模式已由自然跨越覆盖")

# ============================================================
# U-10 极端年份 / 闰年 / 月末 / 边界夹取
# ============================================================

func _sec_u10() -> void:
	_log("----------------------------------------------------------------")
	_log("[U10] 极端年份 / 闰年 / 月末 / 边界")
	_main._paused = true
	await _close_all_panels()
	await _open_calendar()
	_keep()
	var saved_sim := float(_main._sim_seconds)
	var saved_paused := bool(_main._paused)
	_main._paused = true
	var targets := [
		{"y": 1999, "mo": 12, "d": 31, "h": 23, "mi": 59},
		{"y": 2000, "mo": 2, "d": 29, "h": 12, "mi": 0},
		{"y": 2001, "mo": 1, "d": 31, "h": 12, "mi": 0},
		{"y": 1, "mo": 1, "d": 1, "h": 0, "mi": 0},
		{"y": 9999, "mo": 12, "d": 31, "h": 23, "mi": 59},
	]
	for t in targets:
		_set_test_parts({"year": int(t["y"]), "month": int(t["mo"]), "day": int(t["d"]), "hour": int(t["h"]), "minute": int(t["mi"])})
		await _frames(2)
		var j0 := _jump_count
		_hud._on_cal_jump()
		await _frames(3)
		_main._paused = true
		var d: Dictionary = _main._display_datetime()
		var ok := int(d.get("year", 0)) == int(t["y"]) and int(d.get("month", 0)) == int(t["mo"]) \
			and int(d.get("day", 0)) == int(t["d"]) and int(d.get("hour", 0)) == int(t["h"]) \
			and int(d.get("minute", 0)) == int(t["mi"])
		_check("U10", "跳转到 %04d-%02d-%02d %02d:%02d" % [int(t["y"]), int(t["mo"]), int(t["d"]), int(t["h"]), int(t["mi"])],
			ok and (_jump_count == j0 + 1),
			"权威=%s 跳转信号=%d 次" % [_parts_str(_auth_parts()), _jump_count - j0])
	# 2100 非闰年：2/29 被钳制到 2/28
	var c2100: Dictionary = Cal.clamp_parts(2100, 2, 29, 12, 0, 0)
	var d2100: int = Cal.days_in_month(2100, 2)
	var d2000: int = Cal.days_in_month(2000, 2)
	_check("U10", "2100-02-29 非法日期钳制到 02-28", int(c2100["day"]) == 28 and d2100 == 28 and d2000 == 29,
		"clamp_parts(2100,2,29)=%s；days_in_month(2100,2)=%d days_in_month(2000,2)=%d" % [
			_parts_str(c2100), d2100, d2000])
	_set_test_parts({"year": 2100, "month": 2, "day": 28, "hour": 12, "minute": 0})
	await _frames(2)
	_hud._on_cal_jump()
	await _frames(3)
	_main._paused = true
	var d2: Dictionary = _main._display_datetime()
	_check("U10", "跳转 2100-02-28 生效", int(d2.get("year", 0)) == 2100 and int(d2.get("month", 0)) == 2 and int(d2.get("day", 0)) == 28,
		"权威=%s" % _parts_str(_auth_parts()))
	# 1/31 改月 → 2/28（草稿与权威一致）
	_set_test_parts({"year": 2001, "month": 1, "day": 31, "hour": 12, "minute": 0})
	await _frames(2)
	_hud._cal_step("month", 1)
	await _frames(2)
	var draft := _parts()
	var day_col = _col("day")
	_check("U10", "2001-01-31 月 +1 → 草稿 02-28（日列钳制）",
		int(draft["month"]) == 2 and int(draft["day"]) == 28 and int(day_col.max_value) == 28,
		"草稿=%s 日列 range=1..%d" % [_parts_str(draft), int(day_col.max_value)])
	_set_test_parts({"year": 2001, "month": 2, "day": 28, "hour": 12, "minute": 0})
	await _frames(2)
	_hud._on_cal_jump()
	await _frames(3)
	_main._paused = true
	var d3: Dictionary = _main._display_datetime()
	_check("U10", "跳转 2001-02-28 生效", int(d3.get("month", 0)) == 2 and int(d3.get("day", 0)) == 28,
		"权威=%s" % _parts_str(_auth_parts()))
	# 年列边界 notch 不越界
	_set_test_parts({"year": 9999, "month": 12, "day": 31, "hour": 23, "minute": 59})
	_hud._on_cal_jump()
	await _frames(2)
	_main._paused = true
	var yc = _col("year")
	_wheel.call("debug_notch", "year", 1)
	_sync_settle()
	var ymax := int(yc.get_value())
	_set_test_parts({"year": 1, "month": 1, "day": 1, "hour": 0, "minute": 0})
	_hud._on_cal_jump()
	await _frames(2)
	_main._paused = true
	_wheel.call("debug_notch", "year", -1)
	_sync_settle()
	var ymin := int(yc.get_value())
	_check("U10", "年列 1/9999 边界 notch 不越界", ymax == 9999 and ymin == 1,
		"9999 notch(+1) → %d；1 notch(-1) → %d（pos=%.4f）" % [ymax, ymin, float(yc.pos)])
	# 恢复原始时间
	_main._sim_seconds = saved_sim
	_main._paused = saved_paused
	_main._events_timer = 0.0
	_main._settings_save_delay = -1.0
	await _frames(3)

# ============================================================
# U-11 失焦 / 多显示器 / 最小化恢复
# ============================================================

func _sec_u11() -> void:
	_log("----------------------------------------------------------------")
	_log("[U11] 焦点切换 / 失焦 / 多显示器 / 最小化恢复")
	_main._paused = true
	await _open_calendar()
	_keep()
	var scr := DisplayServer.get_screen_count()
	if scr > 1:
		var cur := DisplayServer.window_get_current_screen()
		DisplayServer.window_set_current_screen(1)
		await _frames(4)
		var on1 := DisplayServer.window_get_current_screen()
		DisplayServer.window_set_current_screen(cur)
		await _frames(4)
		_check("U11", "多显示器：窗口可移到第 2 屏", on1 == 1, "screen_count=%d current=%d" % [scr, on1])
	else:
		_skip("U11", "多显示器真机验证", "本机 DisplayServer.screen_count=1（RTX 2060 + Oray 虚拟显示未作为第二屏暴露），无法验证多屏；如实披露")
	var focused := DisplayServer.window_is_focused()
	_log("[U11] window_is_focused=%s" % str(focused))
	# 失焦 / 恢复
	var flag_before := bool(_hud._time_open)
	root.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _frames(4)
	var hidden_ok: bool = bool(_hud._time_open) == flag_before and _wheel.is_visible_in_tree()
	root.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await _frames(4)
	_set_test_parts({"year": 2026, "month": 10, "day": 22, "hour": 18, "minute": 40})
	var mc = _col("minute")
	mc.grab_focus()
	await _frames(2)
	var b1 := int(_parts()["minute"])
	_wheel.call("debug_notch", "minute", -1)
	_sync_settle()
	var a1 := int(_parts()["minute"])
	_check("U11", "失焦/回到前台后面板与滚轮仍可用",
		hidden_ok and a1 == _wrap_dec(b1, -1),
		"失焦期间面板保持=%s；恢复后 notch %d→%d 焦点=%s" % [str(hidden_ok), b1, a1, _focus_name()])
	# 最小化 → 恢复
	var size_before := DisplayServer.window_get_size()
	var panel_before: Rect2 = _hud._time_panel.get_global_rect()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	await _wait(0.5)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	await _wait(0.5)
	if DisplayServer.window_get_size() != Vector2i(WIN_W, WIN_H):
		DisplayServer.window_set_size(Vector2i(WIN_W, WIN_H))
		await _wait(0.3)
	await _frames(4)
	_hud._time_idle = -1000.0
	var size_after := DisplayServer.window_get_size()
	var panel_after: Rect2 = _hud._time_panel.get_global_rect()
	var vr: Rect2 = root.get_visible_rect()
	var inside: bool = panel_after.position.y >= 0.0 and panel_after.end.y <= vr.size.y + 0.5 \
		and panel_after.position.x >= 0.0 and panel_after.end.x <= vr.size.x + 0.5
	_check("U11", "最小化→恢复后窗口与面板布局正确", size_after == Vector2i(WIN_W, WIN_H) and inside and _wheel.is_visible_in_tree(),
		"window %s→%s（原 %s）panel %s→%s visible_rect=%s" % [_vi(size_before), _vi(size_after), _vi(Vector2i(WIN_W, WIN_H)),
			_fmt_rect(panel_before), _fmt_rect(panel_after), _fmt_vec2(vr.size)])
	# 恢复后仍可交互
	_set_test_parts({"year": 2026, "month": 10, "day": 22, "hour": 18, "minute": 40})
	await _frames(2)
	var b2 := int(_parts()["minute"])
	_wheel.call("debug_notch", "minute", 1)
	_sync_settle()
	_check("U11", "最小化恢复后滚轮交互正常", int(_parts()["minute"]) == _wrap_dec(b2, 1),
		"%d → %d" % [b2, int(_parts()["minute"])])
	await _shot("u11_after_restore", _wheel.get_global_rect())
	_warn("U11", "多显示器/高 DPI 真机（披露）",
		"本机 screen_count=%d、screen_scale=%.3f、screen_dpi=%d、max_scale=%.3f；无第二物理屏、无高 DPI 真机，高 DPI 仅能用 content_scale_factor 模拟（见 probe_p82_datetime_frame/perf 证据）" % [
			scr, DisplayServer.screen_get_scale(), DisplayServer.screen_get_dpi(), DisplayServer.screen_get_max_scale()])

# ============================================================
# U-09 长时运行 / 反复开合节点与连接增长
# ============================================================

func _perf_count() -> int:
	return int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))

func _counts() -> Dictionary:
	var hud_nodes := _count_nodes(_hud)
	var tree_nodes := _count_nodes(root)
	# 世界动效（/root/Isle/Fx：涟漪/水花等）在运行时持续生成并释放，属动态池不是 UI 泄漏；
	# 泄漏判据只统计 Fx 子树以外的节点（另报 fx_nodes 供核对）。
	var fx := root.get_node_or_null("Isle/Fx")
	var fx_nodes := _count_nodes(fx) if fx != null else 0
	return {"hud_nodes": hud_nodes, "tree_nodes": tree_nodes, "static_nodes": tree_nodes - fx_nodes,
		"fx_nodes": fx_nodes,
		"objects": _perf_count(),
		"node_count": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"hud_jump_conn": _hud.get_signal_connection_list("datetime_jump_requested").size(),
		"wheel_parts_conn": _wheel.get_signal_connection_list("parts_changed").size(),
		"wheel_edit_conn": _wheel.get_signal_connection_list("editing_changed").size(),
		"mem_static": int(Performance.get_monitor(Performance.MEMORY_STATIC))}

func _counts_str(c: Dictionary) -> String:
	return "hud_nodes=%d tree_nodes=%d static_nodes=%d fx_nodes=%d objects=%d object_nodes=%d jump_conn=%d parts_conn=%d edit_conn=%d mem=%.1fMB" % [
		int(c["hud_nodes"]), int(c["tree_nodes"]), int(c["static_nodes"]), int(c["fx_nodes"]),
		int(c["objects"]), int(c["node_count"]),
		int(c["hud_jump_conn"]), int(c["wheel_parts_conn"]), int(c["wheel_edit_conn"]),
		float(c["mem_static"]) / 1048576.0]

# ============================================================
# U-04 桌面触摸（合成 InputEventScreenTouch/Drag；无真机触屏）
# ============================================================

func _sec_u04_touch() -> void:
	_log("----------------------------------------------------------------")
	_log("[U-04] 桌面触摸合成输入（emulate_mouse_from_touch 路由）")
	var emt := bool(ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch", true))
	var etm := bool(ProjectSettings.get_setting("input_devices/pointing/emulate_touch_from_mouse", false))
	_log("[U-04] emulate_mouse_from_touch=%s emulate_touch_from_mouse=%s touchscreen=%s" % [
		str(emt), str(etm), str(DisplayServer.is_touchscreen_available())])
	await _close_all_panels()
	await _open_calendar()
	_keep()
	var k: float = _scale_now()
	# 1) 触摸点击：日列中心下一行（canvas 坐标 * k = 窗口坐标）
	var day_rect: Rect2 = _col("day").get_global_rect()
	var tap: Vector2 = (day_rect.position + day_rect.size * 0.5 + Vector2(0.0, ROW_H * 0.5)) * k
	var b1 := _parts()
	await _touch_tap(tap)
	await _frames(4)
	await _sync_settle()
	await _wait(0.2)
	var a1 := _parts()
	var tap_changed := not _eq_parts(b1, a1)
	_check("U-04", "合成触摸点击等价鼠标点击（日列下一行 → 日变化）", tap_changed,
		"tap=%s 前=%s 后=%s（emulate_mouse_from_touch=%s）" % [
			_fmt_vec2(tap), _parts_str(b1), _parts_str(a1), str(emt)])
	# 2) 触摸拖动：时列向上拖 1 行
	var hour_rect: Rect2 = _col("hour").get_global_rect()
	var start: Vector2 = (hour_rect.position + hour_rect.size * 0.5) * k
	var b2 := _parts()
	await _touch_drag(start, Vector2(0.0, -ROW_H) * k, 12)
	await _frames(4)
	await _sync_settle()
	await _wait(0.2)
	var a2 := _parts()
	var drag_changed := not _eq_parts(b2, a2)
	var drag_ok: bool = drag_changed and not bool(_wheel.call("is_busy"))
	_check("U-04", "合成触摸拖动等价鼠标拖动（时列上拖 1 行 → 时变化并收敛）", drag_ok,
		"前=%s 后=%s busy=%s" % [_parts_str(b2), _parts_str(a2), str(_wheel.call("is_busy"))])
	await _shot("u04_after_touch")
	_warn("U-04", "无真机触屏，桌面触摸为合成事件（披露）",
		"DisplayServer.is_touchscreen_available()=%s；合成 ScreenTouch/Drag 经 emulate_mouse_from_touch 走 GUI 鼠标路由，能验证等价性但无法覆盖真机触控采样/压力/多点手势" % str(DisplayServer.is_touchscreen_available()))

func _touch_tap(pos: Vector2) -> void:
	Input.warp_mouse(pos)
	await _frames(2)
	var t := InputEventScreenTouch.new()
	t.index = 0
	t.pressed = true
	t.position = pos
	Input.parse_input_event(t)
	await _frames(2)
	var u := InputEventScreenTouch.new()
	u.index = 0
	u.pressed = false
	u.position = pos
	Input.parse_input_event(u)
	await _frames(3)

func _touch_drag(pos: Vector2, delta: Vector2, steps: int) -> void:
	Input.warp_mouse(pos)
	await _frames(2)
	var t := InputEventScreenTouch.new()
	t.index = 0
	t.pressed = true
	t.position = pos
	Input.parse_input_event(t)
	await _frames(2)
	for i in range(steps):
		var d := InputEventScreenDrag.new()
		d.index = 0
		d.position = pos + delta * (float(i + 1) / float(steps))
		d.relative = delta / float(steps)
		Input.parse_input_event(d)
		await _frames(2)
	var u := InputEventScreenTouch.new()
	u.index = 0
	u.pressed = false
	u.position = pos + delta
	Input.parse_input_event(u)
	await _frames(3)

func _sec_u09() -> void:
	_log("----------------------------------------------------------------")
	_log("[U09] 长时运行：60 次开合 + 200 次交互后的节点/连接/对象增长")
	_main._paused = true
	await _close_all_panels()
	await _frames(10)
	_keep()
	var c0 := _counts()
	var paths0 := _node_path_set()
	_log("[U09] 基线 " + _counts_str(c0))
	var c15 := {}
	for i in range(60):
		await _open_time_panel()
		if not bool(_hud._cal_open):
			_hud._toggle_calendar()
		await _frames(2)
		_hud._time_idle = -1000.0
		_wheel.call("debug_notch", "minute", 1)
		_sync_settle()
		if bool(_hud._cal_open):
			_hud._toggle_calendar()
		await _frames(1)
		if bool(_hud._time_open):
			_hud.toggle_time_panel()
		await _frames(1)
		if (i + 1) % 15 == 0:
			_keep()
			var ci := _counts()
			_log("[U09] 第 %d 次开合后 %s" % [i + 1, _counts_str(ci)])
			if i == 14:
				c15 = ci
	# 200 次交互
	await _open_calendar()
	_keep()
	_set_test_parts({"year": 2026, "month": 10, "day": 22, "hour": 18, "minute": 0})
	for i in range(200):
		_wheel.call("step_field", "minute", 1)
	await _frames(4)
	await _close_all_panels()
	await _frames(10)
	var c1 := _counts()
	var added_tree := _diff_paths(paths0, _node_path_set())
	_log("[U09] 结束 " + _counts_str(c1))
	_log("[U09] 开合+交互后新增节点 %d 个（最多列 20）：%s" % [
		added_tree.size(), str(added_tree.slice(0, mini(20, added_tree.size())))])
	var grow_nodes := int(c1["hud_nodes"]) - int(c0["hud_nodes"])
	var grow_tree := int(c1["tree_nodes"]) - int(c0["tree_nodes"])
	var grow_static := int(c1["static_nodes"]) - int(c0["static_nodes"])
	var grow_fx := int(c1["fx_nodes"]) - int(c0["fx_nodes"])
	var grow_obj := int(c1["objects"]) - int(c0["objects"])
	var grow_conn := (int(c1["hud_jump_conn"]) - int(c0["hud_jump_conn"])) \
		+ (int(c1["wheel_parts_conn"]) - int(c0["wheel_parts_conn"])) \
		+ (int(c1["wheel_edit_conn"]) - int(c0["wheel_edit_conn"]))
	var grow_mem := float(c1["mem_static"]) - float(c0["mem_static"])
	_check("U09", "反复开合后 HUD 节点数不增长", grow_nodes == 0, "HUD 节点 %d → %d（Δ=%d）" % [
		int(c0["hud_nodes"]), int(c1["hud_nodes"]), grow_nodes])
	_check("U09", "反复开合后场景节点数不增长（/root/Isle/Fx 动态动效池除外）", grow_static == 0,
		"静态节点 %d → %d（Δ=%d）；Fx 动态池 Δ=%+d（%d→%d）；整树 Δ=%+d；新增非Fx=%s" % [
			int(c0["static_nodes"]), int(c1["static_nodes"]), grow_static, grow_fx,
			int(c0["fx_nodes"]), int(c1["fx_nodes"]), grow_tree,
			str(added_tree.slice(0, mini(20, added_tree.size())))])
	_check("U09", "信号连接数不增长（无重复 connect）", grow_conn == 0, "jump=%d→%d parts=%d→%d edit=%d→%d" % [
		int(c0["hud_jump_conn"]), int(c1["hud_jump_conn"]), int(c0["wheel_parts_conn"]),
		int(c1["wheel_parts_conn"]), int(c0["wheel_edit_conn"]), int(c1["wheel_edit_conn"])])
	# 泄漏 = 持续增长；世界动效/可见性会让对象数上下波动，故判「不增加超过 16」而不是绝对值。
	_check("U09", "渲染对象数无持续增长（不增加超过 16，允许动效波动减少）", grow_obj <= 16,
		"RENDER_TOTAL_OBJECTS %d → %d（Δ=%+d）" % [
			int(c0["objects"]), int(c1["objects"]), grow_obj])
	_check("U09", "静态内存无异常增长（≤4MB）", grow_mem <= 4.0 * 1048576.0,
		"%.1fMB → %.1fMB（Δ=%.2fMB）" % [float(c0["mem_static"]) / 1048576.0,
			float(c1["mem_static"]) / 1048576.0, grow_mem / 1048576.0])
	# 长时运行 1200 帧稳定（世界已 _paused 冻结；先清 dirty 让草稿跟随权威，漂移判定才成立）
	await _open_calendar()
	_keep()
	_hud._cal_dirty = false
	_hud._seed_cal_draft(true)
	await _frames(30)
	var c2a := _counts()
	var paths_a := _node_path_set()
	var draft_start := _parts()
	var intervals: Array = []
	var last_us := Time.get_ticks_usec()
	for i in range(1200):
		await process_frame
		var now := Time.get_ticks_usec()
		intervals.append(float(now - last_us) / 1000.0)
		last_us = now
		if i % 200 == 0:
			_hud._time_idle = -1000.0
	var c2 := _counts()
	var added_run := _diff_paths(paths_a, _node_path_set())
	var sorted := intervals.duplicate()
	sorted.sort()
	var p50 := float(sorted[int(float(sorted.size()) * 0.5)])
	var p95 := float(sorted[mini(int(float(sorted.size()) * 0.95), sorted.size() - 1)])
	var avg := 0.0
	for v in intervals:
		avg += float(v)
	avg /= float(intervals.size())
	var wp := _parts()
	var drift_ok := true
	for f in FIELDS:
		var c = _col(f)
		if int(c.mode) != 0 or absf(float(c.vel)) > 1e-6 or absf(float(c.pos) - round(float(c.pos))) > 1e-6:
			drift_ok = false
	var draft_ok := _eq_parts(draft_start, wp) and _eq_parts(_auth_parts(), wp)
	_check("U09", "1200 帧长时运行后滚轮无漂移/无卡死", drift_ok and draft_ok,
		"起始草稿=%s 结束草稿=%s 权威=%s；帧间隔 p50=%.2fms p95=%.2fms avg=%.2fms（vsync 开启，帧间隔≠CPU 耗时）" % [
			_parts_str(draft_start), _parts_str(wp), _parts_str(_auth_parts()), p50, p95, avg])
	_check("U09", "长时运行后 HUD/静态节点不增长（Fx 动态池除外）",
		_count_nodes(_hud) == int(c2a["hud_nodes"]) and added_run.is_empty(),
		"hud %d→%d 静态 %d→%d（Fx Δ=%+d）新增非Fx节点=%d %s" % [
			int(c2a["hud_nodes"]), _count_nodes(_hud), int(c2a["static_nodes"]), int(c2["static_nodes"]),
			int(c2["fx_nodes"]) - int(c2a["fx_nodes"]), added_run.size(),
			str(added_run.slice(0, mini(12, added_run.size())))])
	_check("U09", "长时运行后渲染对象数稳定（同面板状态前后对比 ±16）",
		absi(int(c2["objects"]) - int(c2a["objects"])) <= 16,
		"objects %d→%d（Δ=%d，均为日历打开状态）" % [
			int(c2a["objects"]), int(c2["objects"]), int(c2["objects"]) - int(c2a["objects"])])
	await _shot("u09_long_run_calendar_open", _wheel.get_global_rect())

# ============================================================
# 收尾
# ============================================================

func _final_restore() -> void:
	_log("----------------------------------------------------------------")
	_log("[CLEANUP] 恢复时间/面板/窗口，确认未写 user:// 设置")
	if _main != null and _hud != null:
		await _close_all_panels()
		_main._settings_save_delay = -1.0
		_main._time_source = String(_orig["time_source"])
		_main._realtime = bool(_orig["realtime"])
		_main._day_length = float(_orig["day_length"])
		_main._paused = bool(_orig["paused"])
		_main._sim_seconds = float(_orig["sim"])
		_main._events_timer = 0.0
		_main._settings_save_delay = -1.0
		var p0: Dictionary = Cal.parts(float(_orig["sim"]))
		var restored := _eq_parts(_auth_parts(), {"year": int(p0["year"]), "month": int(p0["month"]),
			"day": int(p0["day"]), "hour": int(p0["hour"]), "minute": int(p0["minute"])})
		_check("CLEANUP", "模拟时间已恢复到探针起始值", restored,
			"恢复后=%s（起始 sim=%.1f）" % [_parts_str(_auth_parts()), float(_orig["sim"])])
	_main._paused = true
	await _frames(3)
	await _set_size(WIN_W, WIN_H)
	await _frames(3)
	_check("CLEANUP", "结束时窗口=1440x900 窗口化",
		DisplayServer.window_get_size() == Vector2i(WIN_W, WIN_H) and _actual_mode() == "windowed",
		"window=%s mode=%s visible_rect=%s" % [_vi(DisplayServer.window_get_size()), _actual_mode(),
			_fmt_vec2(root.get_visible_rect().size)])
	_check("CLEANUP", "结束时 _settings_save_delay<0（未落盘用户设置）",
		float(_main._settings_save_delay) < 0.0,
		"_settings_save_delay=%.2f" % float(_main._settings_save_delay))
	_hud._time_idle = 0.0
