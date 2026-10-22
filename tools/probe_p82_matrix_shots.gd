extends SceneTree
## ============================================================================
## P8.2-06 / 交付 2：五档画质 x 六个代表性场景 截图矩阵探针（窗口模式，真实渲染）
##
## 目的：给"五档画质矩阵"留下可复核的视觉证据 + 像素/渲染统计，而不是靠肉眼记忆。
##
## 用法（必须走全局串行器）：
##   cd "D:/休闲小岛幻境/游戏工程"
##   bash "D:/休闲小岛幻境/开发产物/p82/run_godot.sh" --path . --resolution 1600x900 \
##     --script res://tools/probe_p82_matrix_shots.gd -- \
##     --out=D:/休闲小岛幻境/开发产物/p82/06_matrix
##
## 可选参数：
##   --out=DIR            输出目录（默认 D:/休闲小岛幻境/开发产物/p82/06_matrix）
##   --scene=KEY[,KEY]    只拍指定场景（逗号分隔，默认全部 6 个）
##   --quality=0,1,2      只拍指定画质档（默认 0,1,2,3,4）
##   --max-white=0.02     白点占比上限（亮度 >=250 的像素比例，默认 2%，可按场景调）
##   --min-mean=12.0      夜间场景最低平均亮度（0-255，默认 12，防全黑）
##   --min-lum-diff=1.0   q0 与 q4 同场景平均亮度可测差异下限
##   --min-dc-diff=10     q0 与 q4 同场景 draw calls 可测差异下限
##   --min-white-diff=0.002  q0 与 q4 白点占比可测差异下限
##   --settle=0.9         每档切完等待秒数
##   --contact=0          是否生成 contact_sheet.png（默认 1）
##   --no-window-pin=0    是否跳过窗口尺寸钉死（默认 0=钉 1600x900）
##
## 输出：
##   shots/<quality>_<scene>.png     每张 1600x900 PNG（q 档 + 场景名写在文件名里）
##   matrix.csv                       每张一行的统计（像素 + 渲染计数 + 断言结果）
##   MANIFEST.md                      人读清单：矩阵表 + 判定 + 复现命令 + 阈值
##   matrix_summary.json              机器读汇总（含全部判定与原始行）
##   contact_sheet.png                5 列(画质) x 6 行(场景) 缩略图总览
##   退出码：0 = 全部硬判定 PASS；1 = 有 FAIL 或运行错误
##
## 判定口径（先给数据，再给结论；阈值全部可用命令行覆盖并写进 MANIFEST）：
##   H1 覆盖率     ：需要的 (画质, 场景) 组合全部产出非空 PNG，且尺寸 = 窗口尺寸
##   H2 档位可测差异：同一场景 q0 与 q4 的图像样本至少一项超过可测差异下限
##                    （平均亮度 / draw calls / 白点占比），否则说明"档位没有实际视觉差异"
##   H3 夜间非全黑 ：indoor_night_fireplace 平均亮度 >= --min-mean
##   H4 夜间不过曝 ：indoor_night_fireplace 白点占比 <= --max-white
##   H5 无运行错误 ：运行期间未捕获脚本错误/资源缺失（探针侧能观测到的部分）
##   注意：像素阈值是"证据门槛"而非审美结论；哪一档更好看仍需人工看图。
## ============================================================================

const ISLE_SCENE := "res://isle.tscn"
const OUT_DEFAULT := "D:/休闲小岛幻境/开发产物/p82/06_matrix"
const RES_W := 1600
const RES_H := 900
const QUALITY_COUNT := 5

## 场景矩阵：6 个代表性场景（覆盖白天/冬季白化/室内夜间/码头夜间/强降雨/大雪近景）
## date = [year, month, day, hour, minute]；wx = IsleWeather type_id；accum = 雨雪累积秒数
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
		"key": "indoor_night_fireplace",
		"label": "室内夜间（壁炉近景）",
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

const CSV_HEADER := "file,quality,scene,label,date,weather,accum_s,camera,width,height,mean_lum,max_lum,p95_lum,dark_ratio,white_ratio,draw_calls,objects,lights_active,light_budget,msaa_3d,max_fps,capture_ok"

var _out := OUT_DEFAULT
var _scene_filter: PackedStringArray = PackedStringArray()
var _quality_filter: PackedInt32Array = PackedInt32Array()
var _max_white := 0.02
var _min_mean := 12.0
var _min_lum_diff := 1.0
var _min_dc_diff := 10
var _min_white_diff := 0.002
var _settle := 0.9
var _contact := true
var _pin_window := true
var _isle: Node = null
var _hud: Node = null
var _win_size := Vector2i.ZERO
var _rows: Array[Dictionary] = []
var _checks: Array[Dictionary] = []
var _fails: PackedStringArray = PackedStringArray()
var _csv: FileAccess = null
var _csv_path := ""
var _manifest_path := ""
var _json_path := ""
var _sheet_path := ""
var _t0 := 0
var _boot_ok := false
var _err_note := ""

const ISLE_CALENDAR := preload("res://scripts/isle_calendar.gd")

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--out="):
			_out = s.substr(6)
		elif s.begins_with("--scene="):
			_scene_filter = _split_str(s.substr(8))
		elif s.begins_with("--quality="):
			for q in _split_str(s.substr(10)):
				_quality_filter.append(int(q))
		elif s.begins_with("--max-white="):
			_max_white = float(s.substr(12))
		elif s.begins_with("--min-mean="):
			_min_mean = float(s.substr(11))
		elif s.begins_with("--min-lum-diff="):
			_min_lum_diff = float(s.substr(15))
		elif s.begins_with("--min-dc-diff="):
			_min_dc_diff = int(s.substr(14))
		elif s.begins_with("--min-white-diff="):
			_min_white_diff = float(s.substr(17))
		elif s.begins_with("--settle="):
			_settle = float(s.substr(9))
		elif s.begins_with("--contact="):
			_contact = int(s.substr(10)) != 0
		elif s.begins_with("--no-window-pin="):
			_pin_window = int(s.substr(16)) == 0
	_run.call_deferred()

func _split_str(s: String) -> PackedStringArray:
	var out := PackedStringArray()
	for part in s.split(",", false):
		var t := String(part).strip_edges()
		if not t.is_empty():
			out.append(t)
	return out

func _log(text: String) -> void:
	print("[P82MATRIX] ", text)

func _ok(cond: bool, check_name: String, detail: String) -> void:
	_checks.append({"name": check_name, "ok": cond, "detail": detail})
	if cond:
		_log("CHECK ok   " + check_name + " | " + detail)
	else:
		_fails.append(check_name + " | " + detail)
		_log("CHECK FAIL " + check_name + " | " + detail)

# ---------------------------------------------------------------------------
# 运行主体
# ---------------------------------------------------------------------------
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	DirAccess.make_dir_recursive_absolute(_out + "/shots")
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	_csv_path = _out + "/matrix.csv"
	_manifest_path = _out + "/MANIFEST.md"
	_json_path = _out + "/matrix_summary_" + stamp + ".json"
	_sheet_path = _out + "/contact_sheet.png"
	_t0 = Time.get_ticks_msec()
	_log("start: out=" + _out)
	_boot_ok = await _boot()
	if not _boot_ok:
		_log("BOOT FAILED: " + _err_note)
		quit(1)
		return
	_csv = FileAccess.open(_csv_path, FileAccess.WRITE)
	if _csv == null:
		_log("cannot open " + _csv_path)
		quit(1)
		return
	_csv.store_line(CSV_HEADER)
	var scenes: Array = []
	for sc in SCENES:
		if _scene_filter.is_empty() or _scene_filter.has(String(sc["key"])):
			scenes.append(sc)
	var quals := PackedInt32Array()
	for q in range(QUALITY_COUNT):
		if _quality_filter.is_empty() or _quality_filter.has(q):
			quals.append(q)
	if scenes.is_empty() or quals.is_empty():
		_log("matrix: nothing selected after filter")
		quit(1)
		return
	_log("matrix plan: scenes=%d qualities=%d total=%d" % [scenes.size(), quals.size(), scenes.size() * quals.size()])
	for sc in scenes:
		await _apply_scene(sc)
		for q in quals:
			await _shoot(sc, q)
	await _build_contact_sheet(scenes, quals)
	_finish(scenes, quals)

func _boot() -> bool:
	var ev := Engine.get_version_info()
	_log("boot: engine=%s.%s.%s" % [str(ev.get("major", "?")), str(ev.get("minor", "?")), str(ev.get("patch", "?"))])
	_log("boot: os=%s gpu=%s api=%s ds=%s" % [OS.get_name(), RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_api_version(), DisplayServer.get_name()])
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
	if _pin_window:
		await _pin_window_size()
	_win_size = DisplayServer.window_get_size()
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_log("window=%dx%d pin=%s" % [_win_size.x, _win_size.y, str(_pin_window)])
	_hud = _isle.get("_hud")
	if _hud != null:
		_hud.call("set_hud_visible", false, false)
		_hud.set("visible", false)
	var ls: Dictionary = _isle.call("debug_light_state")
	_log("lights: budget=%d active=%d lamps=%d" % [int(ls.get("budget", -1)), int(ls.get("active", -1)), int(ls.get("lamp_count", -1))])
	_ok(_isle.is_inside_tree(), "boot_isle_in_tree", "in_tree=" + str(_isle.is_inside_tree()))
	_ok(_hud != null, "boot_hud_resolved", "hud=" + str(_hud != null))
	var win_ok := (not _pin_window) or _win_size == Vector2i(RES_W, RES_H)
	_ok(win_ok, "boot_window_size", "window=%dx%d want=%dx%d pin=%s" % [_win_size.x, _win_size.y, RES_W, RES_H, str(_pin_window)])
	_ok(int(ls.get("budget", 0)) > 0, "boot_light_budget", "budget=" + str(int(ls.get("budget", 0))))
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
	var y := int(d[0])
	var mo := int(d[1])
	var dd := int(d[2])
	var hh := int(d[3])
	var mi := int(d[4])
	_isle.set("_paused", false)
	_isle.call("_p8_wfx_apply", y, mo, dd, hh, mi, String(sc["wx"]), float(sc["accum"]))
	await create_timer(0.35).timeout
	_apply_camera(String(sc["cam"]))
	await create_timer(0.35).timeout
	_isle.set("_paused", true)
	await create_timer(0.15).timeout
	var ws: Dictionary = _isle.get("_weather_state")
	var got_wx := String(ws.get("type", ""))
	var want_wx := String(sc["wx"])
	var cal := _read_calendar()
	var date_ok := int(cal["year"]) == y and int(cal["month"]) == mo and int(cal["day"]) == dd
	_ok(got_wx == want_wx, "scene_weather_" + String(sc["key"]), "want=" + want_wx + " got=" + got_wx + " label=" + String(ws.get("label", "")))
	_ok(date_ok, "scene_date_" + String(sc["key"]), "want=%04d-%02d-%02d got=%s" % [y, mo, dd, String(cal.get("date_label", "?"))])
	_log("SCENE " + String(sc["key"]) + " | " + String(sc["label"]) + " | weather=" + got_wx + "(" + String(ws.get("label", "")) + ") | date=" + String(cal.get("date_label", "?")) + " | season=" + String(cal.get("season_id", "?")) + " | cam=" + String(sc["cam"]))

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
			# 复用 main.gd 自带码头机位（_boat_dock_pos + 01c_dock_oblique 的取景参数）：
			# 手算 IsleMath.dock_start/end 容易把相机放进礁石/栈桥内部（实测拍出近景遮挡）。
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
# 单张截图 + 像素统计
# ---------------------------------------------------------------------------
func _shoot(sc: Dictionary, q: int) -> void:
	var key := String(sc["key"])
	_apply_quality(q)
	_apply_camera(String(sc["cam"]))
	await create_timer(_settle).timeout
	await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	var fname := "q%d_%s.png" % [q, key]
	var rel := "shots/" + fname
	var path := _out + "/" + rel
	var err := ERR_UNAVAILABLE
	var m := {"mean": 0.0, "max": 0, "p95": 0, "dark_ratio": 0.0, "white_ratio": 0.0}
	var w := 0
	var h := 0
	if img != null:
		w = img.get_width()
		h = img.get_height()
		err = img.save_png(path)
		m = _analyze(img)
	var lv: Variant = _isle.call("debug_light_state")
	var ls: Dictionary = lv if lv is Dictionary else {}
	var perf := _perf_metrics()
	var d: Array = sc["date"]
	var row := {
		"file": rel,
		"quality": q,
		"scene": key,
		"label": String(sc["label"]),
		"date": "%04d-%02d-%02d %02d:%02d" % [int(d[0]), int(d[1]), int(d[2]), int(d[3]), int(d[4])],
		"weather": String(sc["wx"]),
		"accum_s": float(sc["accum"]),
		"camera": String(sc["cam"]),
		"width": w,
		"height": h,
		"mean_lum": float(m["mean"]),
		"max_lum": int(m["max"]),
		"p95_lum": int(m["p95"]),
		"dark_ratio": float(m["dark_ratio"]),
		"white_ratio": float(m["white_ratio"]),
		"draw_calls": int(perf["draw_calls"]),
		"objects": int(perf["objects"]),
		"lights_active": int(ls.get("active", -1)),
		"light_budget": int(ls.get("budget", -1)),
		"msaa_3d": _quality_value("msaa_3d"),
		"max_fps": _quality_value("max_fps"),
		"capture_ok": (img != null and err == OK and w > 0 and h > 0),
	}
	_rows.append(row)
	if _csv != null:
		_csv.store_line(_row_csv(row))
		_csv.flush()
	var caps_ok: bool = bool(row["capture_ok"]) and w == _win_size.x and h == _win_size.y
	_ok(caps_ok, "capture_" + key + "_q" + str(q), "err=%d size=%dx%d want=%dx%d" % [int(err), w, h, _win_size.x, _win_size.y])
	_log("SHOT q%d %-22s mean=%6.2f max=%3d p95=%3d dark=%.3f white=%.4f dc=%4d obj=%5d lights=%2d/%2d msaa=%d maxfps=%d" % [q, key, float(row["mean_lum"]), int(row["max_lum"]), int(row["p95_lum"]), float(row["dark_ratio"]), float(row["white_ratio"]), int(row["draw_calls"]), int(row["objects"]), int(row["lights_active"]), int(row["light_budget"]), int(row["msaa_3d"]), int(row["max_fps"])])

func _perf_metrics() -> Dictionary:
	return {
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
	}

func _analyze(img: Image) -> Dictionary:
	var gray: Image = img.duplicate()
	if gray.get_format() != Image.FORMAT_L8:
		gray.convert(Image.FORMAT_L8)
	var data := gray.get_data()
	var hist := PackedInt64Array()
	hist.resize(256)
	hist.fill(0)
	var n := data.size()
	var sum := 0
	var mx := 0
	for i in range(n):
		var v := int(data[i])
		hist[v] += 1
		sum += v
		if v > mx:
			mx = v
	var mean := 0.0
	if n > 0:
		mean = float(sum) / float(n)
	var dark := 0
	for i in range(0, 25):
		dark += hist[i]
	var white := 0
	for i in range(250, 256):
		white += hist[i]
	return {
		"mean": mean,
		"max": mx,
		"p95": _percentile(hist, n, 0.95),
		"dark_ratio": float(dark) / float(maxi(n, 1)),
		"white_ratio": float(white) / float(maxi(n, 1)),
	}

func _percentile(hist: PackedInt64Array, total: int, p: float) -> int:
	if total <= 0:
		return 0
	var target := int(ceil(float(total) * p))
	var acc := 0
	for i in range(256):
		acc += hist[i]
		if acc >= target:
			return i
	return 255

func _row_csv(row: Dictionary) -> String:
	var parts := PackedStringArray()
	parts.append(String(row["file"]))
	parts.append(str(int(row["quality"])))
	parts.append(String(row["scene"]))
	parts.append(String(row["label"]))
	parts.append(String(row["date"]))
	parts.append(String(row["weather"]))
	parts.append("%.1f" % float(row["accum_s"]))
	parts.append(String(row["camera"]))
	parts.append(str(int(row["width"])))
	parts.append(str(int(row["height"])))
	parts.append("%.3f" % float(row["mean_lum"]))
	parts.append(str(int(row["max_lum"])))
	parts.append(str(int(row["p95_lum"])))
	parts.append("%.5f" % float(row["dark_ratio"]))
	parts.append("%.5f" % float(row["white_ratio"]))
	parts.append(str(int(row["draw_calls"])))
	parts.append(str(int(row["objects"])))
	parts.append(str(int(row["lights_active"])))
	parts.append(str(int(row["light_budget"])))
	parts.append(str(int(row["msaa_3d"])))
	parts.append(str(int(row["max_fps"])))
	parts.append("1" if bool(row["capture_ok"]) else "0")
	return ",".join(parts)
# ---------------------------------------------------------------------------
# 汇总判定 + 产物落盘
# ---------------------------------------------------------------------------
func _yes(b: bool) -> String:
	return "yes" if b else "no"

func _find_row(scene_key: String, q: int) -> Dictionary:
	for row in _rows:
		if String(row["scene"]) == scene_key and int(row["quality"]) == q:
			return row
	return {}

func _scene_def(scene_key: String) -> Dictionary:
	for sc in SCENES:
		if String(sc["key"]) == scene_key:
			return sc
	return {}

func _row_line(row: Dictionary) -> String:
	return "| " + String(row["scene"]) + " | q" + str(int(row["quality"])) + " | " + String(row["file"]) + " | " + String(row["date"]) + " | " + String(row["weather"]) + " | %.2f | %d | %.4f | %d | %d | %d/%d |" % [float(row["mean_lum"]), int(row["p95_lum"]), float(row["white_ratio"]), int(row["draw_calls"]), int(row["objects"]), int(row["lights_active"]), int(row["light_budget"])]

func _build_contact_sheet(scenes: Array, quals: PackedInt32Array) -> void:
	if not _contact or scenes.is_empty() or quals.is_empty():
		return
	var tw := RES_W / maxi(quals.size(), 1)
	var th := int(round(float(tw) * 0.5625))
	var sheet := Image.create_empty(RES_W, th * scenes.size(), false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.04, 0.04, 0.05))
	var placed := 0
	for si in range(scenes.size()):
		var sc: Dictionary = scenes[si]
		for qi in range(quals.size()):
			var q: int = quals[qi]
			var path := _out + "/shots/q%d_%s.png" % [q, String(sc["key"])]
			if not FileAccess.file_exists(path):
				continue
			var im := Image.new()
			if im.load(path) != OK:
				continue
			im.resize(tw, th, Image.INTERPOLATE_BILINEAR)
			im.convert(Image.FORMAT_RGB8)
			sheet.blit_rect(im, Rect2i(0, 0, tw, th), Vector2i(qi * tw, si * th))
			placed += 1
	if sheet.save_png(_sheet_path) != OK:
		_log("contact sheet save failed")
	else:
		_log("contact sheet: " + _sheet_path + " tiles=" + str(placed))

func _finish(scenes: Array, quals: PackedInt32Array) -> void:
	var elapsed := float(Time.get_ticks_msec() - _t0) / 1000.0
	var expected := scenes.size() * quals.size()
	var ok_rows := 0
	for row in _rows:
		if bool(row["capture_ok"]):
			ok_rows += 1
	_ok(ok_rows == expected and expected > 0, "H1_coverage", "captured=%d expected=%d" % [ok_rows, expected])
	# H2：同场景 q0 vs q4 必须有可测差异
	var diff_lines := PackedStringArray()
	var h2_bad := 0
	for sc in scenes:
		var key := String(sc["key"])
		var r0 := _find_row(key, 0)
		var r4 := _find_row(key, QUALITY_COUNT - 1)
		if r0.is_empty() or r4.is_empty():
			diff_lines.append("- " + key + ": SKIP（缺 q0 或 q4，可能被 --quality 过滤）")
			continue
		var dl := absf(float(r4["mean_lum"]) - float(r0["mean_lum"]))
		var dd := absf(float(r4["draw_calls"]) - float(r0["draw_calls"]))
		var dw := absf(float(r4["white_ratio"]) - float(r0["white_ratio"]))
		var hit := dl >= _min_lum_diff or dd >= float(_min_dc_diff) or dw >= _min_white_diff
		if not hit:
			h2_bad += 1
		diff_lines.append("- " + key + ": dmean=" + "%.2f" % dl + " (>=%.2f? %s)" % [_min_lum_diff, _yes(dl >= _min_lum_diff)] + " ddc=" + "%.0f" % dd + " (>=%d? %s)" % [_min_dc_diff, _yes(dd >= float(_min_dc_diff))] + " dwhite=" + "%.4f" % dw + " (>=%.4f? %s)" % [_min_white_diff, _yes(dw >= _min_white_diff)] + " => " + ("OK" if hit else "NO-DIFF"))
	_ok(h2_bad == 0, "H2_quality_visual_diff", "q0 vs q4 有可测差异的场景 %d/%d（下限 mean>=%.2f 或 dc>=%d 或 white>=%.4f）" % [scenes.size() - h2_bad, scenes.size(), _min_lum_diff, _min_dc_diff, _min_white_diff])
	# H3/H4：夜间场景非全黑、不过曝
	var h3_ok := true
	var h4_ok := true
	var worst_mean := 100000.0
	var worst_white := -1.0
	var worst_mean_tag := ""
	var worst_white_tag := ""
	for row in _rows:
		var sk := String(row["scene"])
		var sd := _scene_def(sk)
		if sd.is_empty() or not bool(sd.get("night", false)):
			continue
		var mm := float(row["mean_lum"])
		var ww := float(row["white_ratio"])
		var tag := sk + " q" + str(int(row["quality"]))
		if mm < worst_mean:
			worst_mean = mm
			worst_mean_tag = tag
		if ww > worst_white:
			worst_white = ww
			worst_white_tag = tag
		if mm < _min_mean:
			h3_ok = false
		if ww > _max_white:
			h4_ok = false
	if _rows.is_empty():
		h3_ok = false
		h4_ok = false
	_ok(h3_ok, "H3_night_not_black", "夜间最低平均亮度 %.2f（下限 %.2f）@%s" % [worst_mean, _min_mean, worst_mean_tag])
	_ok(h4_ok, "H4_night_not_clipped", "夜间最高白点占比 %.5f（上限 %.5f）@%s" % [worst_white, _max_white, worst_white_tag])
	_ok(_err_note.is_empty(), "H5_no_runtime_error", "探针侧未捕获错误" if _err_note.is_empty() else _err_note)
	var pass_all := _fails.is_empty()
	if _csv != null:
		_csv.flush()
		_csv.close()
		_csv = null
	var ev := Engine.get_version_info()
	var stamp := Time.get_datetime_string_from_system()
	var meta := {
		"probe": "probe_p82_matrix_shots.gd",
		"project": ProjectSettings.get_setting("application/config/name", "?"),
		"engine": "%s.%s.%s" % [str(ev.get("major", "?")), str(ev.get("minor", "?")), str(ev.get("patch", "?"))],
		"gpu": RenderingServer.get_video_adapter_name(),
		"api": RenderingServer.get_video_adapter_api_version(),
		"os": OS.get_name(),
		"host_time": stamp,
		"window": "%dx%d" % [_win_size.x, _win_size.y],
		"elapsed_s": elapsed,
		"scenes": scenes.size(),
		"qualities": quals.size(),
		"shots_expected": expected,
		"shots_captured": ok_rows,
		"pass": pass_all,
	}
	var thresholds := {
		"max_white": _max_white,
		"min_mean": _min_mean,
		"min_lum_diff": _min_lum_diff,
		"min_dc_diff": _min_dc_diff,
		"min_white_diff": _min_white_diff,
		"settle_s": _settle,
	}
	var json := {
		"meta": meta,
		"thresholds": thresholds,
		"pass": pass_all,
		"checks": _checks,
		"fails": _fails,
		"rows": _rows,
	}
	var jf := FileAccess.open(_json_path, FileAccess.WRITE)
	if jf != null:
		jf.store_string(JSON.stringify(json, "  "))
		jf.close()
	# MANIFEST.md
	var md := PackedStringArray()
	md.append("# P8.2-06 五档画质 x 场景 截图矩阵 MANIFEST")
	md.append("")
	md.append("- 探针：tools/probe_p82_matrix_shots.gd（窗口模式真实渲染，非 headless）")
	md.append("- 时间：" + stamp + "；引擎 " + String(meta["engine"]) + "；GPU " + String(meta["gpu"]) + "（" + String(meta["api"]) + "）")
	md.append("- 窗口：" + String(meta["window"]) + "（每张 PNG 的实际尺寸见 CSV 的 width x height）")
	md.append("- 组合：" + str(scenes.size()) + " 场景 x " + str(quals.size()) + " 档 = " + str(expected) + " 张；实际成功 " + str(ok_rows) + " 张；耗时 " + "%.1f" % elapsed + " s")
	md.append("- 结论：**" + ("PASS" if pass_all else "FAIL") + "**")
	md.append("")
	md.append("## 判定")
	md.append("")
	md.append("| 判定 | 结果 | 说明 |")
	md.append("| --- | --- | --- |")
	for ck in _checks:
		md.append("| " + String(ck["name"]) + " | " + ("PASS" if bool(ck["ok"]) else "FAIL") + " | " + String(ck["detail"]).replace("|", "/") + " |")
	md.append("")
	md.append("## 阈值（命令行可覆盖）")
	md.append("")
	md.append("- H3 夜间最低平均亮度 --min-mean = " + "%.2f" % _min_mean + "（0-255 灰度）")
	md.append("- H4 夜间白点占比上限 --max-white = " + "%.4f" % _max_white + "（灰度 >=250 的像素比例）")
	md.append("- H2 可测差异下限 --min-lum-diff " + "%.2f" % _min_lum_diff + " / --min-dc-diff " + str(_min_dc_diff) + " / --min-white-diff " + "%.4f" % _min_white_diff)
	md.append("- 每档切完等待 --settle = " + "%.2f" % _settle + " s")
	md.append("")
	md.append("## q0 vs q4 差异（同场景）")
	md.append("")
	md.append_array(diff_lines)
	md.append("")
	md.append("## 截图清单")
	md.append("")
	md.append("| 场景 | 档位 | 文件 | 日期 | 天气 | 平均亮度 | p95 | 白点占比 | draw calls | objects | 灯光(激活/预算) |")
	md.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
	for row in _rows:
		md.append(_row_line(row))
	md.append("")
	md.append("## 像素口径说明")
	md.append("")
	md.append("- 平均亮度 / p95 / 暗部占比 / 白点占比：先把截图转 8bit 灰度（Image.convert(FORMAT_L8)），再按 0-255 直方图统计。")
	md.append("- 暗部占比 = 灰度 < 25 的像素比例；白点占比 = 灰度 >= 250 的像素比例（可理解为过曝/削顶）。")
	md.append("- draw calls / objects 取 Performance.RENDER_TOTAL_*_IN_FRAME；灯光取 main.debug_light_state() 的 active/budget。")
	md.append("- 这些是证据门槛，不是审美结论：数值过关不代表画面好看，需要人眼看 contact_sheet.png 与单张 PNG。")
	md.append("")
	md.append("## 产物")
	md.append("")
	md.append("- shots/<q>_<scene>.png：每张原始截图（" + "%dx%d" % [_win_size.x, _win_size.y] + "）")
	md.append("- contact_sheet.png：5 列(画质) x " + str(scenes.size()) + " 行(场景) 缩略图总览")
	md.append("- matrix.csv：每张一行的全部统计（机器可读）")
	md.append("- " + _json_path.get_file() + "：同一份数据的 JSON（含 checks/rows）")
	md.append("")
	md.append("## 复现命令")
	md.append("")
	md.append("  cd \"D:/休闲小岛幻境/游戏工程\"")
	md.append("  bash \"D:/休闲小岛幻境/开发产物/p82/run_godot.sh\" --path . --resolution 1600x900 --script res://tools/probe_p82_matrix_shots.gd -- --out=" + _out)
	md.append("")
	md.append("## 已知限制")
	md.append("")
	md.append("- 探针自身无法读取引擎错误日志（那是跑批脚本/外层的职责）：H5 只覆盖探针侧可观测异常；最终验收仍需检查 stdout/日志尾部。")
	md.append("- 窗口尺寸依赖 main.gd 的 _apply_resolution() 时序，探针会重复钉窗口；若被外部改尺寸，boot_window_size 会 FAIL。")
	md.append("- 每档只拍 1 张，不含时间/云量随机性；天气由 _p8_wfx_apply 固定到指定日期+类型。")
	var mf := FileAccess.open(_manifest_path, FileAccess.WRITE)
	if mf != null:
		mf.store_string("\n".join(md) + "\n")
		mf.close()
	_log("---------- summary ----------")
	_log("verdict=" + ("PASS" if pass_all else "FAIL") + " shots=" + str(ok_rows) + "/" + str(expected) + " elapsed=" + "%.1f" % elapsed + "s")
	for ck in _checks:
		_log("CHECK " + ("PASS " if bool(ck["ok"]) else "FAIL ") + String(ck["name"]) + " " + String(ck["detail"]))
	for f in _fails:
		_log("FAILED " + f)
	_log("csv=" + _csv_path)
	_log("manifest=" + _manifest_path)
	_log("json=" + _json_path)
	_log("sheet=" + _sheet_path)
	_log("RESULT " + ("PASS" if pass_all else "FAIL"))
	quit(0 if pass_all else 1)
