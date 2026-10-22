extends SceneTree
## ============================================================================
## P8.2-02 交付：五档画质性能 A/B 可信测量探针（窗口模式，真实渲染，墙钟帧间隔）
##
## 目的：给"五档画质 + 7 个代表场景"的帧时间/渲染计数/灯光状态留下可复核数据，
##       用于 base（P8.1 冻结 ddcde3a）vs new（当前分支）交替 A/B。
##
## 用法（必须走全局串行器 run_godot.sh v2，一次只跑一个）：
##   cd "D:/休闲小岛幻境/游戏工程"
##   bash "D:/休闲小岛幻境/开发产物/p82/run_godot.sh" --path . --resolution 1600x900 \
##     --script res://tools/probe_p82_perf_ab.gd -- \
##     --out=D:/休闲小岛幻境/开发产物/p82/evidence/02_perf --label=baseA
##
## 可选参数：
##   --out=DIR        输出目录（默认 开发产物/p82/evidence/02_perf）
##   --label=TAG      本 run 的标签（写进 CSV，用于 A/A 与 A/B 配对分析）
##   --scene=K1,K2    只测指定场景
##   --quality=0,4    只测指定画质档
##   --frames=120     每个 (场景,画质) 采样的帧数
##   --warmup=30      采样前的预热帧数（剔除 shader 编译/首次绘制抖动）
##   --settle=0.20    切场景/画质后的等待秒数
##   --sweeps=2       同一 run 内的往返扫描次数（偶数轮升序、奇数轮降序，抵消热漂移）
##   --soak=0         boot 后先固定画质连续渲染 N 秒（热稳态：GPU 时钟/风扇到位）再开始采样，
##                    用于消除"每个 run 起始热状态不同"这一跨 run 漂移源。A/A/A-B 交替轮必须给同一 soak。
##
## 口径（重要，写进 PERF_MEASURE 文档）：
##   - VSync 关；窗口钉 1600x900；采样期间 Engine.max_fps = 0（**不受画质预设的 60 FPS 上限约束**，
##     这与 P8.1 历史 q0 门"FPS≥170"的口径一致：预设 max_fps=60 是玩家侧上限，不是测量口径）。
##     实际预设值记录在 preset_max_fps 列，便于报告说明。
##   - 帧时间 = 相邻 process_frame 恢复点的 Time.get_ticks_usec 差（墙钟，含 GPU 等待）。
##   - Performance.TIME_PROCESS 不记录：P8.2-03 已证明它在窗口模式只返回 15–18µs，是伪影。
##   - 每个 (场景,画质) 采样前后的顺序索引写入 CSV（order_in_sweep），用于漂移诊断。
##
## 输出：
##   perf_<label>_<stamp>.csv     每 (sweep,场景,画质) 一行：p50/p95/p99/mean/min/max、fps、draw/objects/vram、灯光状态
##   frames_<label>_<stamp>.csv   每帧一行：run 标签、sweep、场景、画质、frame_idx、frame_us、draw/objects/vram
##   log 由 run_godot.sh 重定向，探针自身打印 [P82PERF] 汇总行
## ============================================================================

const ISLE_SCENE := "res://isle.tscn"
const OUT_DEFAULT := "D:/休闲小岛幻境/开发产物/p82/evidence/02_perf"
const RES_W := 1600
const RES_H := 900
const QUALITY_COUNT := 5
const ISLE_CALENDAR := preload("res://scripts/isle_calendar.gd")

## 7 个代表性场景（lead P8.2-02 指定）：清晰白天 / 冬季白化 / 室内夜间 / 壁炉近景 /
## 码头夜间 / 强降雨 / 大雪近景。date=[y,m,d,h,min]，wx=IsleWeather type_id，accum=雨雪累积秒。
const SCENES := [
	{
		"key": "clear_day_outdoor",
		"label": "清晰白天室外（主岛全景）",
		"date": [2026, 7, 15, 10, 0],
		"wx": "clear",
		"accum": 0.0,
		"cam": "island",
		"night": false,
	},
	{
		"key": "winter_white_outdoor",
		"label": "冬季白化室外（积雪主岛）",
		"date": [2027, 1, 15, 11, 0],
		"wx": "heavy_snow",
		"accum": 30000.0,
		"cam": "island",
		"night": false,
	},
	{
		"key": "indoor_night",
		"label": "室内夜间（屋内机位）",
		"date": [2027, 1, 15, 20, 30],
		"wx": "clear",
		"accum": 0.0,
		"cam": "inside",
		"night": true,
	},
	{
		"key": "fireplace_close",
		"label": "壁炉近景（室内夜间）",
		"date": [2027, 1, 15, 20, 30],
		"wx": "clear",
		"accum": 0.0,
		"cam": "fireplace",
		"night": true,
	},
	{
		"key": "dock_night",
		"label": "码头夜间（灯光倒影）",
		"date": [2027, 1, 15, 20, 30],
		"wx": "clear",
		"accum": 0.0,
		"cam": "dock",
		"night": true,
	},
	{
		"key": "heavy_rain",
		"label": "强降雨（主岛全景）",
		"date": [2026, 7, 15, 14, 0],
		"wx": "heavy_rain",
		"accum": 600.0,
		"cam": "island",
		"night": false,
	},
	{
		"key": "heavy_snow_close",
		"label": "大雪近景（树下）",
		"date": [2027, 1, 15, 11, 0],
		"wx": "heavy_snow",
		"accum": 30000.0,
		"cam": "tree",
		"night": false,
	},
]

const AGG_HEADER := "run,label,sweep,order_in_sweep,scene,quality,frames,fps_mean,frame_us_p50,frame_us_p95,frame_us_p99,frame_us_mean,frame_us_min,frame_us_max,stability_p99_over_p50,draw_calls,objects,vram_mb,lights_active,light_budget,outdoor_count,indoor_count,outdoor_budget,indoor_budget,lamp_count,msaa_3d,preset_max_fps,scaling_3d_scale,date_label,weather,season_id,cell_unix"
const FRAME_HEADER := "run,label,sweep,scene,quality,frame_idx,frame_us,draw_calls,objects,vram_mb"

var _out := OUT_DEFAULT
var _label := "run"
var _scene_filter: PackedStringArray = PackedStringArray()
var _quality_filter: PackedInt32Array = PackedInt32Array()
var _frames := 120
var _warmup := 30
var _settle := 0.20
var _sweeps := 2
var _soak := 0.0
var _run_unix := 0

var _isle: Node = null
var _hud: Node = null
var _win_size := Vector2i.ZERO
var _agg_path := ""
var _frame_path := ""
var _stamp := ""
var _boot_ok := false
var _err_note := ""
var _t0 := 0
var _agg_rows: Array[Dictionary] = []
var _frame_lines: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--out="):
			_out = s.substr(6)
		elif s.begins_with("--label="):
			_label = s.substr(8)
		elif s.begins_with("--scene="):
			_scene_filter = _split_str(s.substr(8))
		elif s.begins_with("--quality="):
			for q in _split_str(s.substr(10)):
				_quality_filter.append(int(q))
		elif s.begins_with("--frames="):
			_frames = int(s.substr(9))
		elif s.begins_with("--warmup="):
			_warmup = int(s.substr(9))
		elif s.begins_with("--settle="):
			_settle = float(s.substr(9))
		elif s.begins_with("--sweeps="):
			_sweeps = int(s.substr(9))
		elif s.begins_with("--soak="):
			_soak = float(s.substr(7))
	_run.call_deferred()

func _split_str(s: String) -> PackedStringArray:
	var out := PackedStringArray()
	for part in s.split(",", false):
		var t := String(part).strip_edges()
		if not t.is_empty():
			out.append(t)
	return out

func _log(text: String) -> void:
	print("[P82PERF] ", text)

# ---------------------------------------------------------------------------
# 运行主体
# ---------------------------------------------------------------------------
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	_stamp = Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
	_t0 = Time.get_ticks_msec()
	_run_unix = int(Time.get_unix_time_from_system())
	_log("start label=%s unix=%d out=%s frames=%d warmup=%d settle=%.2f sweeps=%d soak=%.1f" % [_label, _run_unix, _out, _frames, _warmup, _settle, _sweeps, _soak])
	_boot_ok = await _boot()
	if not _boot_ok:
		_log("BOOT FAILED: " + _err_note)
		quit(1)
		return
	_agg_path = _out + "/perf_" + _label + "_" + _stamp + ".csv"
	_frame_path = _out + "/frames_" + _label + "_" + _stamp + ".csv"
	var scenes: Array = []
	for sc in SCENES:
		if _scene_filter.is_empty() or _scene_filter.has(String(sc["key"])):
			scenes.append(sc)
	var quals := PackedInt32Array()
	for q in range(QUALITY_COUNT):
		if _quality_filter.is_empty() or _quality_filter.has(q):
			quals.append(q)
	if scenes.is_empty() or quals.is_empty():
		_log("nothing selected after filter")
		quit(1)
		return
	_log("plan: scenes=%d qualities=%d sweeps=%d cells=%d" % [scenes.size(), quals.size(), _sweeps, scenes.size() * quals.size() * _sweeps])
	if _soak > 0.0:
		# 热稳态：固定画质连续渲染 _soak 秒，让 GPU 时钟/风扇/驱动队列进入与 run 无关的稳定状态。
		# 不加这一步时，每个 run 的起始热状态不同，会造成跨 run 10% 量级的系统性漂移（实测过）。
		await _apply_scene(scenes[0])
		_apply_quality(2 if quals.has(2) else quals[quals.size() - 1])
		Engine.max_fps = 0
		var soak_ms := int(_soak * 1000.0)
		var t_soak := Time.get_ticks_msec()
		_log("soak start %.1fs unix=%d" % [_soak, int(Time.get_unix_time_from_system())])
		while Time.get_ticks_msec() - t_soak < soak_ms:
			await process_frame
		_log("soak done elapsed=%.1fs unix=%d" % [float(Time.get_ticks_msec() - t_soak) / 1000.0, int(Time.get_unix_time_from_system())])
	for sweep in range(_sweeps):
		var sc_order: Array = scenes if sweep % 2 == 0 else scenes.duplicate()
		if sweep % 2 == 1:
			sc_order.reverse()
		for sc in sc_order:
			await _apply_scene(sc)
			var q_list: Array = []
			for q in quals:
				q_list.append(q)
			if sweep % 2 == 1:
				q_list.reverse()
			var order_i := 0
			for q in q_list:
				await _sample_cell(sc, int(q), sweep, order_i)
				order_i += 1
		_log("sweep %d done elapsed=%.1fs" % [sweep, float(Time.get_ticks_msec() - _t0) / 1000.0])
	_write_csv()
	_print_summary()
	_log("done elapsed=%.1fs agg=%s frames=%s" % [float(Time.get_ticks_msec() - _t0) / 1000.0, _agg_path, _frame_path])
	quit(0)

func _boot() -> bool:
	var ev := Engine.get_version_info()
	_log("boot engine=%s.%s.%s os=%s gpu=%s api=%s ds=%s" % [
		str(ev.get("major", "?")), str(ev.get("minor", "?")), str(ev.get("patch", "?")),
		OS.get_name(), RenderingServer.get_video_adapter_name(),
		RenderingServer.get_video_adapter_api_version(), DisplayServer.get_name()])
	var packed: Variant = load(ISLE_SCENE)
	if packed == null or not (packed is PackedScene):
		_err_note = "cannot load " + ISLE_SCENE
		return false
	_isle = (packed as PackedScene).instantiate()
	root.add_child(_isle)
	for i in range(4):
		await process_frame
	var menu: Variant = _isle.get("_menu")
	if menu != null and (menu as Object).has_method("instant_finish"):
		(menu as Object).call("instant_finish")
	if _isle.has_method("_enter_playing"):
		_isle.call("_enter_playing")
	_isle.set("_mode", 1)
	_isle.set("_time_source", "sim")
	_isle.set("_realtime", false)
	_isle.set("_started", true)
	_isle.set("_paused", true)
	_isle.set("_auto_orbit", false)
	_isle.set("_blending", "")
	_isle.set("_sim_seconds", 0.0)
	for i in range(6):
		await process_frame
	await _pin_window_size()
	_win_size = DisplayServer.window_get_size()
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_log("window=%dx%d vsync=disabled" % [_win_size.x, _win_size.y])
	_hud = _isle.get("_hud")
	if _hud != null:
		_hud.call("set_hud_visible", false, false)
		_hud.set("visible", false)
	var ls: Dictionary = _isle.call("debug_light_state") as Dictionary
	_log("lights: budget=%d active=%d out=%d/%d in=%d/%d lamps=%d" % [
		int(ls.get("budget", -1)), int(ls.get("active", -1)),
		int(ls.get("outdoor_count", -1)), int(ls.get("outdoor_budget", -1)),
		int(ls.get("indoor_count", -1)), int(ls.get("indoor_budget", -1)),
		int(ls.get("lamp_count", -1))])
	if _win_size != Vector2i(RES_W, RES_H):
		_log("WARN window size %dx%d != %dx%d" % [_win_size.x, _win_size.y, RES_W, RES_H])
	return true

func _pin_window_size() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	for attempt in range(8):
		DisplayServer.window_set_size(Vector2i(RES_W, RES_H))
		await process_frame
		await process_frame
		if DisplayServer.window_get_size() == Vector2i(RES_W, RES_H):
			break
	await create_timer(0.35).timeout
	if DisplayServer.window_get_size() != Vector2i(RES_W, RES_H):
		DisplayServer.window_set_size(Vector2i(RES_W, RES_H))
		await create_timer(0.2).timeout

# ---------------------------------------------------------------------------
# 场景 / 机位 / 画质
# ---------------------------------------------------------------------------
func _apply_scene(sc: Dictionary) -> void:
	var d: Array = sc["date"]
	_isle.set("_paused", false)
	_isle.call("_p8_wfx_apply", int(d[0]), int(d[1]), int(d[2]), int(d[3]), int(d[4]), String(sc["wx"]), float(sc["accum"]))
	await create_timer(0.35).timeout
	_apply_camera(String(sc["cam"]))
	await create_timer(0.25).timeout
	_isle.set("_paused", true)
	await create_timer(0.10).timeout
	var ws: Dictionary = _isle.get("_weather_state") as Dictionary
	var got_wx := String(ws.get("type", ""))
	if got_wx != String(sc["wx"]):
		_log("WARN scene %s weather want=%s got=%s" % [String(sc["key"]), String(sc["wx"]), got_wx])
	var cal := _read_calendar()
	_log("SCENE %-22s weather=%s date=%s season=%s cam=%s" % [
		String(sc["key"]), got_wx, String(cal.get("date_label", "?")), String(cal.get("season_id", "?")), String(sc["cam"])])

func _read_calendar() -> Dictionary:
	var secs := 0.0
	var v: Variant = _isle.get("_sim_seconds")
	if v != null:
		secs = float(v)
	return ISLE_CALENDAR.parts(secs)

func _apply_quality(q: int) -> void:
	var sv: Variant = _isle.get("_settings")
	if sv is Dictionary:
		var sd := sv as Dictionary
		sd["quality"] = q
		sd["quality_overrides"] = {}
		_isle.set("_settings", sd)
	_isle.call("_apply_quality", q)

func _quality_value(field: String) -> int:
	var qv: Variant = _isle.get("_quality_state")
	if qv is Dictionary:
		var qd := qv as Dictionary
		if qd.has(field):
			return int(qd[field])
	return -999

func _quality_value_f(field: String) -> float:
	var qv: Variant = _isle.get("_quality_state")
	if qv is Dictionary:
		var qd := qv as Dictionary
		if qd.has(field):
			return float(qd[field])
	return -1.0

func _apply_camera(spec: String) -> void:
	match spec:
		"island":
			_isle.call("_p8_camera_island")
		"tree":
			_isle.call("_p8_camera_tree")
		"inside":
			_isle.call("_p8_camera_inside")
		"fireplace":
			var cv: Variant = _isle.get("_cottage")
			if cv is Dictionary:
				var c := cv as Dictionary
				var hr: Node3D = c["root"]
				var yaw: float = hr.global_rotation.y
				var front := Vector3(sin(yaw), 0.0, cos(yaw))
				var right := Vector3(cos(yaw), 0.0, -sin(yaw))
				var fire: Vector3 = c["fireplace_world"]
				_isle.call("_pose_look", fire + front * 2.55 + right * 0.55 + Vector3(0.0, 0.10, 0.0), fire + Vector3(0.0, -0.42, 0.0), 48.0)
		"dock":
			var dock_c := Vector3(0.0, 0.72, 8.0)
			var dv: Variant = _isle.get("_boat_dock_pos")
			if dv is Vector3:
				var cand: Vector3 = dv
				if cand != Vector3.ZERO:
					dock_c = cand
			var heading := 0.0
			var hv: Variant = _isle.get("_boat_dock_heading")
			if hv != null:
				heading = float(hv)
			var dock_axis := Vector3(sin(heading), 0.0, cos(heading))
			if dock_axis.length() < 0.1:
				dock_axis = Vector3(0.0, 0.0, 1.0)
			dock_axis = dock_axis.normalized()
			var dock_out := Vector3(dock_c.x, 0.0, dock_c.z)
			if dock_out.length() < 0.5:
				dock_out = dock_axis
			dock_out = dock_out.normalized()
			_isle.call("_pose_look", dock_c + dock_out * 8.5 + Vector3(0.0, 5.2, 0.0), dock_c - dock_out * 1.5 + Vector3(0.0, 0.40, 0.0), 54.0)
		_:
			_isle.call("_p8_camera_island")

# ---------------------------------------------------------------------------
# 单个 (场景, 画质) 单元采样
# ---------------------------------------------------------------------------
func _sample_cell(sc: Dictionary, q: int, sweep: int, order_i: int) -> void:
	_apply_quality(q)
	Engine.max_fps = 0
	var preset_max_fps := _quality_value("max_fps")
	_apply_camera(String(sc["cam"]))
	await create_timer(_settle).timeout
	for i in range(_warmup):
		await process_frame
	var n := _frames
	var dt := PackedInt64Array()
	dt.resize(n)
	var dcs := PackedInt32Array()
	dcs.resize(n)
	var objs := PackedInt32Array()
	objs.resize(n)
	var vrams := PackedFloat32Array()
	vrams.resize(n)
	var prev := Time.get_ticks_usec()
	for i in range(n):
		await process_frame
		var now := Time.get_ticks_usec()
		dt[i] = now - prev
		prev = now
		dcs[i] = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		objs[i] = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
		vrams[i] = float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0
	var lv: Variant = _isle.call("debug_light_state")
	var ls: Dictionary = lv if lv is Dictionary else {}
	var cal := _read_calendar()
	var ws: Dictionary = _isle.get("_weather_state") as Dictionary
	var sorted_dt := dt.duplicate()
	sorted_dt.sort()
	var total := 0
	for v in dt:
		total += int(v)
	var mean_us := float(total) / float(n)
	var p50 := _pct(sorted_dt, 50.0)
	var p95 := _pct(sorted_dt, 95.0)
	var p99 := _pct(sorted_dt, 99.0)
	var dc_med := _median_i(dcs)
	var obj_med := _median_i(objs)
	var vram_med := _median_f(vrams)
	var row := {
		"run": _label,
		"label": _label,
		"sweep": sweep,
		"order_in_sweep": order_i,
		"scene": String(sc["key"]),
		"quality": q,
		"frames": n,
		"fps_mean": 1000000.0 / maxf(mean_us, 1.0),
		"frame_us_p50": p50,
		"frame_us_p95": p95,
		"frame_us_p99": p99,
		"frame_us_mean": mean_us,
		"frame_us_min": int(sorted_dt[0]),
		"frame_us_max": int(sorted_dt[n - 1]),
		"stability_p99_over_p50": float(p99) / maxf(float(p50), 1.0),
		"draw_calls": dc_med,
		"objects": obj_med,
		"vram_mb": vram_med,
		"lights_active": int(ls.get("active", -1)),
		"light_budget": int(ls.get("budget", -1)),
		"outdoor_count": int(ls.get("outdoor_count", -1)),
		"indoor_count": int(ls.get("indoor_count", -1)),
		"outdoor_budget": int(ls.get("outdoor_budget", -1)),
		"indoor_budget": int(ls.get("indoor_budget", -1)),
		"lamp_count": int(ls.get("lamp_count", -1)),
		"msaa_3d": _quality_value("msaa_3d"),
		"preset_max_fps": preset_max_fps,
		"scaling_3d_scale": _quality_value_f("scaling_3d_scale"),
		"date_label": String(cal.get("date_label", "?")),
		"weather": String(ws.get("type", "?")),
		"season_id": String(cal.get("season_id", "?")),
		"cell_unix": int(Time.get_unix_time_from_system()),
	}
	_agg_rows.append(row)
	for i in range(n):
		_frame_lines.append("%s,%s,%d,%s,%d,%d,%d,%d,%d,%.3f" % [
			_label, _label, sweep, String(sc["key"]), q, i, int(dt[i]), int(dcs[i]), int(objs[i]), float(vrams[i])])
	_log("CELL sweep=%d %-22s q%d fps=%7.1f us p50/p95/p99=%6d/%6d/%6d dc=%4d obj=%5d vram=%6.1fMB lights=%2d/%2d out=%2d in=%2d msaa=%d preset_maxfps=%d" % [
		sweep, String(sc["key"]), q, float(row["fps_mean"]), p50, p95, p99, dc_med, obj_med, vram_med,
		int(row["lights_active"]), int(row["light_budget"]), int(row["outdoor_count"]), int(row["indoor_count"]),
		int(row["msaa_3d"]), preset_max_fps])

func _pct(sorted_arr: PackedInt64Array, p: float) -> int:
	var n := sorted_arr.size()
	if n <= 0:
		return 0
	var idx := int(round(p / 100.0 * float(n - 1)))
	return int(sorted_arr[clampi(idx, 0, n - 1)])

func _median_i(arr: PackedInt32Array) -> int:
	if arr.size() <= 0:
		return 0
	var c := arr.duplicate()
	c.sort()
	return int(c[c.size() / 2])

func _median_f(arr: PackedFloat32Array) -> float:
	if arr.size() <= 0:
		return 0.0
	var c := arr.duplicate()
	c.sort()
	return float(c[c.size() / 2])

# ---------------------------------------------------------------------------
# CSV / 汇总
# ---------------------------------------------------------------------------
func _write_csv() -> void:
	var fa := FileAccess.open(_agg_path, FileAccess.WRITE)
	if fa == null:
		_log("cannot write " + _agg_path)
	else:
		fa.store_line(AGG_HEADER)
		for row in _agg_rows:
			var parts := PackedStringArray()
			for key in AGG_HEADER.split(","):
				parts.append(str(row.get(key, "")))
			fa.store_line(",".join(parts))
		fa.close()
	var ff := FileAccess.open(_frame_path, FileAccess.WRITE)
	if ff == null:
		_log("cannot write " + _frame_path)
	else:
		ff.store_line(FRAME_HEADER)
		for line in _frame_lines:
			ff.store_line(line)
		ff.close()
	_frame_lines.clear()

func _print_summary() -> void:
	_log("SUMMARY label=" + _label)
	for sc in SCENES:
		var key := String(sc["key"])
		var q0 := _find_row(key, 0)
		var q4 := _find_row(key, 4)
		if q0.is_empty() or q4.is_empty():
			_log("  %-22s q0/q4 missing" % key)
			continue
		_log("  %-22s q0 fps=%7.1f p50=%6d p95=%6d dc=%4d lights=%2d/%2d | q4 fps=%7.1f p50=%6d p95=%6d dc=%4d lights=%2d/%2d | dq4-q0 p50=%+6d us fps=%+7.1f" % [
			key,
			float(q0["fps_mean"]), int(q0["frame_us_p50"]), int(q0["frame_us_p95"]), int(q0["draw_calls"]),
			int(q0["lights_active"]), int(q0["light_budget"]),
			float(q4["fps_mean"]), int(q4["frame_us_p50"]), int(q4["frame_us_p95"]), int(q4["draw_calls"]),
			int(q4["lights_active"]), int(q4["light_budget"]),
			int(q4["frame_us_p50"]) - int(q0["frame_us_p50"]),
			float(q4["fps_mean"]) - float(q0["fps_mean"])])
	_log("LIGHTDIFF q0 vs q4（active/pool out/in）:")
	for sc in SCENES:
		var key := String(sc["key"])
		var q0 := _find_row(key, 0)
		var q4 := _find_row(key, 4)
		if q0.is_empty() or q4.is_empty():
			continue
		_log("  %-22s q0 active=%2d out=%2d in=%2d budget=%2d outb=%2d inb=%2d | q4 active=%2d out=%2d in=%2d budget=%2d outb=%2d inb=%2d" % [
			key,
			int(q0["lights_active"]), int(q0["outdoor_count"]), int(q0["indoor_count"]), int(q0["light_budget"]), int(q0["outdoor_budget"]), int(q0["indoor_budget"]),
			int(q4["lights_active"]), int(q4["outdoor_count"]), int(q4["indoor_count"]), int(q4["light_budget"]), int(q4["outdoor_budget"]), int(q4["indoor_budget"])])

## 取该场景某画质档在最后一次 sweep 的行（sweep 已做顺序翻转，最后一轮更接近稳态）
func _find_row(scene_key: String, q: int) -> Dictionary:
	var hit: Dictionary = {}
	for row in _agg_rows:
		if String(row["scene"]) == scene_key and int(row["quality"]) == q:
			hit = row
	return hit
