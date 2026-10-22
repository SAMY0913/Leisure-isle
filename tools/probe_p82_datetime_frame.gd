extends SceneTree
## 休闲小岛幻境 · P8.2-05 帧时间/几何采样（v1 等价最小复现版）
##
## 【为什么有这个文件】P8.2-05 第一版采样脚本（原名即 probe_p82_datetime_frame.gd）在后续重构中
## 被删除且从未入库，导致 开发产物/p82/05_wheel/probe_p82_datetime_frame_result.json 与 9 张截图
## 在 tools/ 下没有对应的可复跑脚本（winter 的 §10 审计发现）。本文件按**同一口径**重写为最小复现版：
##   A. P-5：windowed 下 Performance.TIME_PROCESS 的取值被量化（唯一值极少），不能作帧开销判据；
##   B. 朴素 ABBA 长段 A/B（每段 240 帧、vsync 关闭）的"段间漂移 > 信号"噪声底，
##      这是后来改用"逐对交错 + A/A + 95%CI"（见 tools/probe_p81_datetime_wheel_ui.gd 的 _ui10）的原因；
##   C. 四档窗口尺寸下的画布可见区与面板几何（expand 语义：1639x900 -> 窗口宽/1600 的物理缩放）。
## 注意：本脚本**不产生新的性能结论**，性能结论一律以 UI10（逐对交错）为准；本文件只用于复现方法学证据。
##
## 运行（必须窗口模式，勿加 --headless）：
##   cd "D:/休闲小岛幻境/游戏工程"
##   bash "D:/休闲小岛幻境/开发产物/p82/run_godot.sh" --path . --script res://tools/probe_p82_datetime_frame.gd
## 输出：D:/休闲小岛幻境/开发产物/p82/05_wheel/probe_p82_datetime_frame_repro.log / _repro.json

const OUT_DIR := "D:/休闲小岛幻境/开发产物/p82/05_wheel"
const TAG := "probe_p82_datetime_frame_repro"
const SIZES: Array = [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]
const AB_FRAMES := 240

var _main: Node = null
var _hud: Node = null
var _lines: PackedStringArray = PackedStringArray()
var _json: Dictionary = {}

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_log("[ENV] godot=%s screen=%s usable=%s scale=%.3f dpi=%d count=%d" % [
		Engine.get_version_info().string, str(DisplayServer.screen_get_size()),
		str(DisplayServer.screen_get_usable_rect().size), DisplayServer.screen_get_scale(),
		DisplayServer.screen_get_dpi(), DisplayServer.get_screen_count()])
	if DisplayServer.get_name() == "headless":
		_log("[SKIP] 本探针只在窗口模式有意义（帧时间/尺寸），headless 退出")
		_write_out()
		quit(0)
		return
	await _run()
	_write_out()
	quit(0)

func _run() -> void:
	if not await _load_main():
		_log("[FAIL] 世界加载失败")
		return
	await _ensure_playing()
	await _frames(30)
	await _p5_study()
	await _abba_study()
	await _size_matrix()

func _p5_study() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	Engine.max_fps = 0
	await _frames(10)
	var procs: Array = []
	var fpss: Array = []
	for i in range(120):
		await process_frame
		procs.append(Performance.get_monitor(Performance.TIME_PROCESS))
		fpss.append(Performance.get_monitor(Performance.TIME_FPS))
	var uniq: Dictionary = {}
	for v in procs:
		uniq[str(snappedf(float(v), 0.001))] = true
	_log("[P5] TIME_PROCESS(ms) uniq=%d min=%.4f p50=%.4f max=%.4f | TIME_FPS p50=%.1f" % [
		uniq.size(), _minf(procs), _medianf(procs), _maxf(procs), _medianf(fpss)])
	_json["p5"] = {
		"proc_unique": uniq.size(), "proc_min": _minf(procs), "proc_p50": _medianf(procs),
		"proc_max": _maxf(procs), "fps_p50": _medianf(fpss),
		"conclusion": "windowed 下 TIME_PROCESS 被量化（唯一值极少）→ 不可作帧开销判据；改用逐帧墙钟差值（UI10）",
	}

func _abba_study() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var seg: Dictionary = {}
	var order: Array = ["A1", "B1", "B2", "A2", "A3"]
	for seg_name in order:
		if str(seg_name).begins_with("B"):
			await _open_calendar()
		else:
			await _close_all_panels()
		await _frames(10)
		var m: Dictionary = await _measure(AB_FRAMES)
		seg[seg_name] = m
		_log("[ABBA] %s p50=%.3f avg=%.3f draw=%d objs=%d" % [
			str(seg_name), float(m["p50"]), float(m["avg"]), int(m["draw"]), int(m["objs"])])
	var d_p50: Array = []
	var d_avg: Array = []
	var pairs: Array = [["A1", "B1"], ["A2", "B2"]]
	for p in pairs:
		d_p50.append(float(seg[p[1]]["p50"]) - float(seg[p[0]]["p50"]))
		d_avg.append(float(seg[p[1]]["avg"]) - float(seg[p[0]]["avg"]))
	var noise_p50: float = float(seg["A3"]["p50"]) - float(seg["A1"]["p50"])
	_log("[ABBA] Δp50=%s 中位=%.3f | Δavg 中位=%.3f | A/A 噪声 Δp50=%.3f" % [
		str(d_p50), _medianf(d_p50), _medianf(d_avg), noise_p50])
	_json["abba"] = {"d_p50": d_p50, "d_avg": d_avg, "d_p50_med": _medianf(d_p50),
		"d_avg_med": _medianf(d_avg), "noise_p50": noise_p50, "frames": AB_FRAMES,
		"conclusion": "朴素长段 ABBA 的 |Δ| 与 A/A 噪声同阶（噪声 > 信号）→ 不可分辨，改用逐对交错 + A/A + 95%CI（UI10）"}
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)

func _size_matrix() -> void:
	await _open_calendar()
	var rows: Array = []
	for s in SIZES:
		DisplayServer.window_set_size(s)
		await _frames(12)
		var vis: Vector2 = root.get_visible_rect().size
		var panel: Control = _hud._time_panel
		var pr: Rect2 = panel.get_global_rect()
		var wheel: Control = _hud._cal_wheel
		var wr: Rect2 = wheel.get_global_rect()
		var inside: bool = pr.position.x >= 0.0 and pr.position.y >= 0.0 and pr.end.x <= vis.x and pr.end.y <= vis.y
		var cols_ok := true
		for i in range(5):
			var cr: Rect2 = _hud._cal_wheel.get_child(i).get_global_rect()
			if cr.position.x < wr.position.x - 0.5 or cr.end.x > wr.end.x + 0.5:
				cols_ok = false
		var k: float = float(s.x) / max(vis.x, 1.0)
		var row: Dictionary = {"win": [s.x, s.y], "visible_rect": [vis.x, vis.y], "k": k,
			"panel": [pr.position.x, pr.position.y, pr.size.x, pr.size.y],
			"wheel": [wr.position.x, wr.position.y, wr.size.x, wr.size.y],
			"panel_inside": inside, "cols_inside": cols_ok}
		rows.append(row)
		_log("[SIZE] win=%dx%d visible=%.0fx%.0f k=%.3f panel=(%.0f,%.0f %.0fx%.0f) inside=%s cols_ok=%s" % [
			s.x, s.y, vis.x, vis.y, k, pr.position.x, pr.position.y, pr.size.x, pr.size.y, str(inside), str(cols_ok)])
	_json["size_matrix"] = rows
	await _close_all_panels()
	DisplayServer.window_set_size(Vector2i(1440, 900))
	await _frames(6)

func _measure(frames: int) -> Dictionary:
	var t: Array = []
	var draw: int = 0
	var objs: int = 0
	var last: int = Time.get_ticks_usec()
	for i in range(frames):
		await process_frame
		var now: int = Time.get_ticks_usec()
		t.append(float(now - last) / 1000.0)
		last = now
		draw = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		objs = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var sum: float = 0.0
	for v in t:
		sum += float(v)
	return {"p50": _medianf(t), "avg": sum / float(max(t.size(), 1)), "draw": draw, "objs": objs}

# ---------- 世界/HUD ----------
func _load_main() -> bool:
	var isle: Node = root.get_node_or_null("Isle")
	if isle == null:
		var ps: PackedScene = load("res://isle.tscn")
		if ps == null:
			return false
		isle = ps.instantiate()
		root.add_child(isle)
	_main = isle
	var waited: float = 0.0
	while waited < 180.0:
		await process_frame
		waited += 0.05
		_hud = _main.get("_hud")
		if _hud != null and _main.get("_menu") != null:
			break
	_log("[HUD] ready waited=%.1fs nodes=%d" % [waited, _main.find_children("*", "", true, false).size()])
	return _hud != null

func _ensure_playing() -> void:
	if int(_main._mode) == 0:
		_main._on_menu_start(bool(_main._started))
	var waited: float = 0.0
	while waited < 60.0:
		await process_frame
		waited += 0.05
		if int(_main._mode) == 1 and str(_main._blending) == "":
			return
	await _frames(10)

func _open_calendar() -> void:
	_hud.set_hud_visible(true, false)
	if not bool(_hud._time_open):
		_hud.toggle_time_panel()
	_hud._time_panel.visible = true
	_hud._time_idle = -100000.0
	await _frames(4)
	if not bool(_hud._cal_open):
		_hud._toggle_calendar()
	await _frames(8)
	_hud._time_idle = -100000.0
	_main._settings_save_delay = -1.0

func _close_all_panels() -> void:
	_hud._time_idle = -100000.0
	if bool(_hud._cal_open):
		_hud._toggle_calendar()
	if bool(_hud._time_open):
		_hud.toggle_time_panel()
	if bool(_hud._weather_open):
		_hud.toggle_weather_panel()
	if bool(_hud._almanac_open):
		_hud.toggle_almanac()
	if bool(_hud._perf_open):
		_hud.toggle_perf()
	await _frames(6)

func _frames(n: int) -> void:
	for i in range(n):
		await process_frame

# ---------- 数学/输出 ----------
func _medianf(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var b: Array = a.duplicate()
	b.sort()
	return float(b[b.size() / 2])

func _minf(a: Array) -> float:
	var m: float = 1e9
	for v in a:
		m = minf(m, float(v))
	return m

func _maxf(a: Array) -> float:
	var m: float = -1e9
	for v in a:
		m = maxf(m, float(v))
	return m

func _log(s: String) -> void:
	print(s)
	_lines.append(s)

func _write_out() -> void:
	var f: FileAccess = FileAccess.open(OUT_DIR + "/" + TAG + ".log", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")
		f.close()
	var j: FileAccess = FileAccess.open(OUT_DIR + "/" + TAG + ".json", FileAccess.WRITE)
	if j != null:
		j.store_string(JSON.stringify(_json, "  "))
		j.close()
	_log("[DONE] %s.log / %s.json" % [TAG, TAG])
