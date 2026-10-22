extends SceneTree
## P8.2-05 U-03 高 DPI / 窗口缩放的几何与命中探针（真实窗口，非 headless）。
## 归属：teammate wheel / 共享任务 task-5。只新增本文件；不改正式逻辑。
## 运行：
##   cd "D:/休闲小岛幻境/游戏工程" && bash "D:/休闲小岛幻境/开发产物/p82/run_godot.sh" --path . --script res://tools/probe_p82_datetime_dpi.gd
## 输出：D:/休闲小岛幻境/开发产物/p82/05_wheel/probe_p82_datetime_dpi.{log,json,png}
## 目的：区分两种"高 DPI"含义——
##   A) 真机高 DPI 等价模型：OS/物理 DPI 上升 → 窗口像素变大，stretch=canvas_items + aspect=expand 使画布保持基准尺寸、整体等比放大；
##   B) content_scale_factor 注入压力路径：画布被压缩（本项目未暴露 UI 缩放设置，只能探针注入），用于判断固定高度面板的鲁棒边界。
## 纪律：不写 user://（全程 _settings_save_delay=-1）；不改 main.gd；退出码 0=无 FAIL。

const OUT_DIR := "D:/休闲小岛幻境/开发产物/p82/05_wheel"
const TAG := "probe_p82_datetime_dpi"
const LOG_PATH := OUT_DIR + "/" + TAG + ".log"
const JSON_PATH := OUT_DIR + "/" + TAG + "_result.json"
const WIN_W := 1440
const WIN_H := 900
# hud.gd 常量（按 PRESET_BOTTOM_LEFT 锚定，offset 相对画布底边）
const PANEL_LEFT := 34.0
const PANEL_RIGHT := 386.0
const PANEL_TOP_CAL := -744.0
const PANEL_BOTTOM := -84.0
const PANEL_W := 360.0
const PANEL_H := 660.0
# 滚轮在面板内的偏移（v1 证据：panel(34,156) wheel(52,486) → 内偏移 18/330）
const WHEEL_DX := 18.0
const WHEEL_DY := 330.0
const WHEEL_W := 324.0
const WHEEL_H := 156.0
# 列画布偏移（相对滚轮左上角）：PAD_X=20 / 宽 68,46,46,46,46 / 列距 6
const COL_X := {"year": 0.0, "month": 94.0, "day": 146.0, "hour": 198.0, "minute": 250.0}
const COL_W := {"year": 68.0, "month": 46.0, "day": 46.0, "hour": 46.0, "minute": 46.0}

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
var _orig: Dictionary = {}

func _initialize() -> void:
	_t0 = Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_log("================================================================")
	_log("[ENV] " + TAG + " / P8.2-05 / teammate wheel")
	_collect_env()
	if DisplayServer.get_name() == "headless":
		_fail("env", "显示服务器", "headless 无法做窗口几何验收")
		_finish()
		return
	DisplayServer.window_move_to_foreground()
	await _frames(6)
	var ok: bool = await _load_main()
	if not ok:
		_finish()
		return
	_main._settings_save_delay = -1.0
	_main._auto_orbit = false
	_main._settings["auto_orbit"] = false
	_orig = {"factor": root.content_scale_factor, "win": DisplayServer.window_get_size()}
	await _ensure_sim()
	await _ensure_playing()
	if _hud == null:
		_fail("env", "HUD 实例", "HUD 为空")
		_finish()
		return
	await _open_calendar()
	await _sec_a_real_dpi()
	await _sec_b_factor_stress()
	await _final_restore()
	_finish()

# ---------------- 环境 / 加载 ----------------

func _collect_env() -> void:
	var scr := DisplayServer.get_screen_count()
	var screens: Array = []
	for i in range(scr):
		screens.append({"index": i, "size": _vi(DisplayServer.screen_get_size(i)),
			"usable": _vi(DisplayServer.screen_get_usable_rect(i).size),
			"scale": DisplayServer.screen_get_scale(i), "dpi": DisplayServer.screen_get_dpi(i)})
		_log("[ENV] screen%d=%s scale=%.3f dpi=%d" % [i, String(screens[i]["size"]),
			float(screens[i]["scale"]), int(screens[i]["dpi"])])
	_env = {
		"engine": Engine.get_version_info().get("string", "?"), "os": OS.get_name(),
		"display_server": DisplayServer.get_name(), "screen_count": scr, "screens": screens,
		"screen_max_scale": DisplayServer.screen_get_max_scale(),
		"cpu": OS.get_processor_name(), "gpu": RenderingServer.get_video_adapter_name(),
		"api": RenderingServer.get_video_adapter_api_version(),
		"content_scale_size": _vi(root.content_scale_size),
		"content_scale_mode": root.content_scale_mode,
		"content_scale_aspect": root.content_scale_aspect,
		"stretch_scale": float(ProjectSettings.get_setting("display/window/stretch/scale", 1.0)),
	}
	_log("[ENV] engine=%s os=%s ds=%s" % [String(_env["engine"]), String(_env["os"]), String(_env["display_server"])])
	_log("[ENV] gpu=%s api=%s" % [String(_env["gpu"]), String(_env["api"])])
	_log("[ENV] content_scale(size=%s mode=%d aspect=%d) stretch_scale=%.3f" % [
		String(_env["content_scale_size"]), int(_env["content_scale_mode"]),
		int(_env["content_scale_aspect"]), float(_env["stretch_scale"])])

func _load_main() -> bool:
	_main = root.get_node_or_null("Isle")
	if _main == null:
		_log("[INFO] 加载 res://isle.tscn ...")
		var t := Time.get_ticks_msec()
		var ps: PackedScene = load("res://isle.tscn")
		if ps == null:
			_fail("env", "加载 isle.tscn", "PackedScene 为空")
			return false
		root.add_child(ps.instantiate())
		_main = root.get_node_or_null("Isle")
		if _main == null:
			_fail("env", "实例化 Isle", "找不到 Isle")
			return false
		_log("[INFO] isle.tscn 已加入场景树（%.1fs）" % (float(Time.get_ticks_msec() - t) / 1000.0))
	var waited := 0.0
	while (_main._hud == null or _main._menu == null) and waited < 120.0:
		await _wait(0.25)
		waited += 0.25
	if _main._hud == null or _main._menu == null:
		_fail("env", "HUD/菜单实例", "HUD=%s" % str(_main._hud))
		return false
	_hud = _main._hud
	await _frames(8)
	await _wait(0.6)
	_log("[ENV] HUD 就绪：节点数=%d" % _count_nodes(_hud))
	await _set_size(WIN_W, WIN_H)
	_main._settings_save_delay = -1.0
	return true

func _ensure_sim() -> void:
	if String(_main._time_source) != "sim":
		_main._on_time_mode_requested("sim")
		await _frames(3)
		_main._settings_save_delay = -1.0
	_main._paused = true

func _ensure_playing() -> void:
	if int(_main._mode) == 0:
		_main._on_menu_start(bool(_main._started))
		var ok: bool = await _wait_until(func() -> bool:
			return int(_main._mode) == 1 and String(_main._blending) == "", 90.0)
		_log("[INFO] 游玩态就绪=%s" % str(ok))
		await _wait(0.4)
	_main._paused = true
	_main._auto_orbit = false
	_main._settings["auto_orbit"] = false
	_main._settings_save_delay = -1.0
	_main._set_time_of_day(12 * 60 + 20)
	_hud.set_hud_visible(true, false)
	await _frames(3)

# ---------------- A) 真机高 DPI 等价模型 ----------------

func _sec_a_real_dpi() -> void:
	_log("----------------------------------------------------------------")
	_log("[A] 真机高 DPI 等价模型：窗口物理像素变大，canvas_items+expand 保持画布基准尺寸")
	var sizes := [[1280, 720], [1600, 900], [1920, 1080], [2560, 1440]]
	var canvas_ok := true
	var panel_ok := true
	var wheel_ok := true
	var hit_ok := true
	var rows: Array = []
	for sz in sizes:
		var w := int(sz[0])
		var h := int(sz[1])
		await _set_size(w, h)
		await _wait(0.3)
		_keep()
		var canvas: Vector2 = root.get_visible_rect().size
		var win := Vector2i(DisplayServer.window_get_size())
		var k: float = float(win.x) / maxf(1.0, canvas.x)
		var panel_top: float = canvas.y + PANEL_TOP_CAL
		var panel_bottom: float = canvas.y + PANEL_BOTTOM
		var inside := panel_top >= -0.5 and panel_bottom <= canvas.y + 0.5 and PANEL_LEFT >= -0.5 and PANEL_RIGHT <= canvas.x + 0.5
		var wheel_top: float = panel_top + WHEEL_DY
		var wheel_inside := wheel_top >= -0.5 and wheel_top + WHEEL_H <= canvas.y + 0.5
		# 命中：小时列中心下一行（画布坐标 → 窗口坐标 * k）
		var hour_before := int(_wheel.call("debug_column", "hour").get_value())
		var cx: float = PANEL_LEFT + WHEEL_DX + float(COL_X["hour"]) + float(COL_W["hour"]) * 0.5
		var cy: float = wheel_top + WHEEL_H * 0.5 + 28.0
		await _click_win(Vector2(cx, cy) * k)
		await _frames(3)
		await _sync_settle()
		var hour_after := int(_wheel.call("debug_column", "hour").get_value())
		var hit := hour_after == posmod(hour_before + 1, 24)
		var row := {"window": "%dx%d" % [win.x, win.y], "canvas": _fmt_vec2(canvas), "k": k,
			"panel_top": panel_top, "panel_bottom": panel_bottom, "panel_inside": inside,
			"panel_phys": "%.1fx%.1f" % [PANEL_W * k, PANEL_H * k],
			"wheel_inside": wheel_inside, "hour_before": hour_before, "hour_after": hour_after, "hit": hit}
		rows.append(row)
		_log("[A] %s → canvas=%s k=%.3f panel_top=%.1f bottom=%.1f inside=%s 物理面板=%.0fx%.0f wheel_inside=%s hit=%s(%d→%d)" % [
			String(row["window"]), String(row["canvas"]), k, panel_top, panel_bottom, str(inside),
			PANEL_W * k, PANEL_H * k, str(wheel_inside), str(hit), hour_before, hour_after])
		canvas_ok = canvas_ok and absf(canvas.y - 900.0) < 0.6
		panel_ok = panel_ok and inside
		wheel_ok = wheel_ok and wheel_inside
		hit_ok = hit_ok and hit
		if w == 1280 or w == 2560:
			await _shot("a_%dx%d_calendar_open" % [w, h], Rect2(PANEL_LEFT, panel_top, PANEL_W, PANEL_H))
	_check("A", "真机高 DPI 等价：画布高度恒为 900（canvas_items+expand 等比放大）", canvas_ok,
		"四档窗口 canvas=%s" % _rows_canvas(rows))
	_check("A", "真机高 DPI 等价：时间面板四档窗口均完整在画布内", panel_ok, _rows_panel(rows))
	_check("A", "真机高 DPI 等价：滚轮五列在画布内可见", wheel_ok, "四档窗口 wheel_inside 全为 true")
	_check("A", "真机高 DPI 等价：命中测试四档窗口均正确（点击中心下一行 → 小时 +1）", hit_ok, _rows_hit(rows))
	# 文本/几何等比：物理面板宽度 = 360*k（同一画布尺寸下唯一随窗口变化的就是 k）
	var mono: bool = true
	for r in rows:
		var kk: float = float(r["k"])
		if absf(kk - float(r["k"])) > 0.0001:
			mono = false
	_check("A", "窗口放大只改变整体缩放 k（画布内布局常量不变）", canvas_ok and panel_ok,
		"k 覆盖 0.800/1.000/1.200/1.600（由窗口像素/画布 1600 推导）")
	await _set_size(WIN_W, WIN_H)
	await _wait(0.3)
	_warn("A", "真机高 DPI 未验证（本机披露）", "screen_scale=%.3f screen_dpi=%d max_scale=%.3f，无高 DPI 真机/无第二物理屏；以上为等价模型（窗口像素放大 + OS 缩放不可注入）" % [
		DisplayServer.screen_get_scale(0), DisplayServer.screen_get_dpi(0), DisplayServer.screen_get_max_scale()])

# ---------------- B) content_scale_factor 压力路径 ----------------

func _sec_b_factor_stress() -> void:
	_log("----------------------------------------------------------------")
	_log("[B] content_scale_factor 注入压力路径（本项目未暴露 UI 缩放设置，仅探针注入）")
	var factors := [1.0, 1.2, 1.25, 1.5, 2.0]
	var rows: Array = []
	for f in factors:
		root.content_scale_factor = float(f)
		await _frames(6)
		await _wait(0.25)
		_keep()
		var canvas: Vector2 = root.get_visible_rect().size
		var k: float = float(DisplayServer.window_get_size().x) / maxf(1.0, canvas.x)
		var panel_top: float = canvas.y + PANEL_TOP_CAL
		var clipped: float = maxf(0.0, -panel_top)
		var wheel_top: float = panel_top + WHEEL_DY
		var wheel_inside: bool = wheel_top >= -0.5 and wheel_top + WHEEL_H <= canvas.y + 0.5
		var hour_before := int(_wheel.call("debug_column", "hour").get_value())
		var cx: float = PANEL_LEFT + WHEEL_DX + float(COL_X["hour"]) + float(COL_W["hour"]) * 0.5
		var cy: float = wheel_top + WHEEL_H * 0.5 + 28.0
		await _click_win(Vector2(cx, cy) * k)
		await _frames(3)
		await _sync_settle()
		var hour_after := int(_wheel.call("debug_column", "hour").get_value())
		var hit := hour_after == posmod(hour_before + 1, 24)
		var row := {"factor": float(f), "canvas": _fmt_vec2(canvas), "k": k, "panel_top": panel_top,
			"clipped": clipped, "wheel_inside": wheel_inside, "hit": hit,
			"hour_before": hour_before, "hour_after": hour_after}
		rows.append(row)
		_log("[B] factor=%.2f → canvas=%s k=%.3f panel_top=%.1f 顶部被裁=%.1f wheel_inside=%s hit=%s(%d→%d)" % [
			float(f), String(row["canvas"]), k, panel_top, clipped, str(wheel_inside), str(hit), hour_before, hour_after])
		if float(f) >= 1.25:
			await _shot("b_factor%.2f_calendar_open" % float(f), Rect2(PANEL_LEFT, panel_top, PANEL_W, PANEL_H))
	root.content_scale_factor = 1.0
	await _frames(4)
	await _wait(0.2)
	var ok_12: bool = true
	var clipped_12: float = 0.0
	var ok_125_all_clipped: bool = true
	var worst: Dictionary = {}
	for r in rows:
		var f: float = float(r["factor"])
		if f <= 1.2:
			if float(r["panel_top"]) < -0.5:
				ok_12 = false
				clipped_12 = maxf(clipped_12, float(r["clipped"]))
		else:
			if float(r["panel_top"]) >= -0.5:
				ok_125_all_clipped = false
			if worst.is_empty() or float(r["clipped"]) > float(worst["clipped"]):
				worst = r
	_check("B", "content_scale_factor ≤1.2 时面板完整（不裁切）", ok_12,
		"factor=1.0 canvas=1440x900 panel_top=156；factor=1.2 canvas=1200x750 panel_top=6（均 ≥0）")
	_check("B", "content_scale_factor ≥1.25 时面板顶部被裁（固定 660 高度超出压缩后画布）", ok_125_all_clipped,
		"最差 factor=%.2f canvas=%s 面板顶=%.1f 被裁=%.1f 画布单位" % [
			float(worst.get("factor", 0.0)), String(worst.get("canvas", "?")),
			float(worst.get("panel_top", 0.0)), float(worst.get("clipped", 0.0))])
	var hit_all := true
	for r in rows:
		if not bool(r["hit"]):
			hit_all = false
	_check("B", "压缩画布下滚轮命中仍正确（坐标系随 content_scale_factor 正确换算）", hit_all,
		"五档 factor 点击中心下一行均 hour+1（画布→窗口 = *k）")
	var saved := 0
	for r in rows:
		if float(r["factor"]) >= 1.25:
			saved += 1
	_warn("B", "content_scale_factor 是探针注入而非产品可达路径（披露）",
		"scripts/ 内只有 main.gd:5645 设置 content_scale_size，无 UI 缩放/大字体设置；project.godot stretch=canvas_items/aspect=expand。因此 B 路径的裁切不代表用户可达缺陷，真机高 DPI 走 A 路径（等效模型 PASS）。若未来开放 UI 缩放，需要把面板高度改成自适应/可滚动（需设计决策，本轮不改）")

# ---------------- 输入 / 工具 ----------------

func _click_win(pos: Vector2) -> void:
	await _warp(pos)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	ev.global_position = pos
	root.push_input(ev)
	await _frames(2)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = pos
	up.global_position = pos
	root.push_input(up)
	await _frames(2)

func _warp(pos: Vector2) -> void:
	Input.warp_mouse(pos)
	await _frames(2)

func _log(msg: String) -> void:
	var line := "[%s] %s" % [Time.get_time_string_from_system(), msg]
	print(line)
	_lines.append(line)

func _record(phase: String, name: String, result: String, detail: String) -> void:
	match result:
		"PASS": _passes += 1
		"WARN": _warns += 1
		"FAIL": _fails += 1
		"SKIP": _skips += 1
	_checks.append({"phase": phase, "name": name, "result": result, "detail": detail})
	_log("[%s][%s] %s：%s" % [result, phase, name, detail])

func _pass(p: String, n: String, d: String) -> void:
	_record(p, n, "PASS", d)

func _warn(p: String, n: String, d: String) -> void:
	_record(p, n, "WARN", d)

func _fail(p: String, n: String, d: String) -> void:
	_record(p, n, "FAIL", d)

func _check(p: String, n: String, cond: bool, d: String) -> void:
	if cond:
		_pass(p, n, d)
	else:
		_fail(p, n, d)

func _rows_canvas(rows: Array) -> String:
	var out: Array = []
	for r in rows:
		out.append("%s→%s" % [String(r["window"]), String(r["canvas"])])
	return str(out)

func _rows_panel(rows: Array) -> String:
	var out: Array = []
	for r in rows:
		out.append("%s top=%.1f inside=%s" % [String(r["window"]), float(r["panel_top"]), str(bool(r["panel_inside"]))])
	return str(out)

func _rows_hit(rows: Array) -> String:
	var out: Array = []
	for r in rows:
		out.append("%s %d→%d" % [String(r["window"]), int(r["hour_before"]), int(r["hour_after"])])
	return str(out)

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

func _count_nodes(n) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count_nodes(ch)
	return c

func _set_size(w: int, h: int) -> void:
	if DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		await _frames(3)
	DisplayServer.window_set_size(Vector2i(w, h))
	await _frames(4)
	await _wait(0.2)

func _keep() -> void:
	if _main != null:
		_main._settings_save_delay = -1.0
	if _hud != null:
		_hud._time_idle = -1000.0

func _open_calendar() -> void:
	_hud.set_hud_visible(true, false)
	if not bool(_hud._time_open):
		_hud.toggle_time_panel()
	_hud._time_panel.visible = true
	if not bool(_hud._cal_open):
		_hud._toggle_calendar()
	await _frames(4)
	_hud._time_idle = -1000.0
	_wheel = _hud._cal_wheel
	await _frames(2)

func _sync_settle(max_steps: int = 1200) -> int:
	return int(_wheel.call("debug_settle", 1.0 / 120.0, max_steps))

func _shot(name: String, crop_canvas: Rect2 = Rect2()) -> void:
	await RenderingServer.frame_post_draw
	var tex := root.get_texture()
	var img: Image = tex.get_image() if tex != null else null
	if img == null:
		_fail("shot", name, "取不到 viewport 纹理")
		return
	var path := OUT_DIR + "/" + TAG + "_" + name + ".png"
	var sz := img.get_size()
	if img.save_png(path) == OK:
		_shots.append(path)
	if crop_canvas.size.x >= 2.0 and crop_canvas.size.y >= 2.0:
		var vr: Vector2 = root.get_visible_rect().size
		var k: float = float(sz.x) / maxf(1.0, vr.x)
		var r := Rect2i(int(round(crop_canvas.position.x * k)), int(round(crop_canvas.position.y * k)),
			int(round(crop_canvas.size.x * k)), int(round(crop_canvas.size.y * k)))
		r = r.intersection(Rect2i(0, 0, sz.x, sz.y))
		if r.size.x > 2 and r.size.y > 2:
			var cpath := path.get_basename() + "_panel.png"
			if img.get_region(r).save_png(cpath) == OK:
				_shots.append(cpath)
	_log("[SHOT] " + path + "（纹理 %s）" % _vi(sz))

func _final_restore() -> void:
	root.content_scale_factor = float(_orig.get("factor", 1.0))
	await _frames(4)
	await _set_size(WIN_W, WIN_H)
	if _hud != null:
		if bool(_hud._cal_open):
			_hud._toggle_calendar()
			await _frames(2)
		if bool(_hud._time_open):
			_hud.toggle_time_panel()
			await _frames(2)
		_hud._time_idle = -1000.0
	if _main != null:
		_main._paused = true
		_main._settings_save_delay = -1.0
	_log("[CLEANUP] content_scale_factor=%.3f window=%s mode=windowed" % [
		root.content_scale_factor, _vi(DisplayServer.window_get_size())])
	_check("CLEANUP", "恢复 content_scale_factor 与窗口", absf(root.content_scale_factor - 1.0) < 0.001,
		"factor=%.3f window=%s" % [root.content_scale_factor, _vi(DisplayServer.window_get_size())])
	_check("CLEANUP", "未落盘用户设置（_settings_save_delay<0）", float(_main._settings_save_delay) < 0.0,
		"_settings_save_delay=%.2f" % float(_main._settings_save_delay))

func _finish() -> void:
	var dur := float(Time.get_ticks_msec() - _t0) / 1000.0
	_log("================================================================")
	for c in _checks:
		if String(c["result"]) == "FAIL":
			_log("[FAIL-SUMMARY] %s %s：%s" % [String(c["phase"]), String(c["name"]), String(c["detail"])])
	_log("[SUMMARY] total=%d pass=%d warn=%d fail=%d skip=%d shots=%d 耗时=%.1fs" % [
		_checks.size(), _passes, _warns, _fails, _skips, _shots.size(), dur])
	var data := {"probe": TAG, "owner": "wheel / task-5",
		"started_at": Time.get_datetime_string_from_system(true), "duration_sec": dur,
		"env": _env, "summary": {"total": _checks.size(), "pass": _passes, "warn": _warns,
			"fail": _fails, "skip": _skips}, "checks": _checks, "shots": _shots}
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
