extends SceneTree
## P8.2-06 长时间 soak（窗口模式，真实渲染 + 真实周期交互 + 自带 PASS/FAIL）
##
## 目的：长时间真实窗口运行，期间周期性做真实操作（五档画质轮转 / 12 类天气轮转 /
##       季节·跨年·闰年·月末日期跳转 / HUD 面板开关），全程用一个挂在场景树里的采样
##       Node 以 _process(delta) 累计「真实帧间隔」并统计 p50/p95/p99/max，同时记录
##       节点/ObjectDB/draw call/VRAM/静态内存/激活灯光数，最后自带判定并写日志+CSV+JSON。
##
## 为什么不用 Performance.TIME_PROCESS：窗口模式下该监视器在部分驱动/VSync 组合上不可信，
## 无法反映真实帧间隔。本探针只信任 _process(delta) 的累计值。
##
## 用法（必须真窗口；headless 下帧时间无意义）：
##   cd "D:/休闲小岛幻境/游戏工程"
##   bash "D:/休闲小岛幻境/开发产物/p82/run_godot.sh" --path . --resolution 1600x900 \
##     --script res://tools/probe_p82_soak.gd -- --minutes=30 --out=D:/休闲小岛幻境/开发产物/p82/06_soak
##
##   # 短自检（约 2 分钟，压缩操作间隔以覆盖全部操作类型）：
##   ... -- --minutes=2 --op-scale=0.12
##
## 参数：
##   --minutes=30      运行分钟数（默认 30）
##   --out=<dir>       证据目录（默认 开发产物/p82/06_soak/）
##   --sample=5        采样间隔秒（默认 5，任务要求 5-10s）
##   --op-scale=1.0    操作间隔缩放（默认 1.0 = 任务规定的 60/90/150/180s；短跑用 0.1-0.2）
##   --vsync=off|on    默认 off（VSync 会把帧时间量化到 16.7ms，p95 判据失去分辨力）
##   --settle=0.5      每次操作后的稳定等待秒
##
## 输出：soak_<stamp>.csv / soak_<stamp>.log / soak_<stamp>_summary.json / soak_<stamp>_summary.md
## 退出码：0 = PASS，1 = FAIL（判定明细见日志 criteria 段与 summary.json）
##
## 免责声明（写报告时必须照抄口径）：本探针只能给出「本次 soak 未发现明显异常」，
## 不能据此宣称不存在内存泄漏；帧时间趋势本身受画质/天气周期影响。
##
## 判定口径见 _criteria()：C1 帧时间 p95 退化、C2 节点数增长、C3 连续低帧、C4 操作覆盖、
## C5 操作断言零失败、C6 退出期状态健全。短跑（<12min）自动把 C1 标 SKIP。

const ISLE_CALENDAR := preload("res://scripts/isle_calendar.gd")
const ISLE_WEATHER := preload("res://scripts/isle_weather.gd")

const OUT_DEFAULT := "D:/休闲小岛幻境/开发产物/p82/06_soak/"
const RES_W := 1600
const RES_H := 900
const QUALITY_COUNT := 5
const WEATHER_ORDER := [
	"clear", "partly", "overcast", "strong_wind", "light_rain", "mid_rain",
	"heavy_rain", "light_snow", "mid_snow", "heavy_snow", "thunder", "typhoon",
]
## 雪三类只在深冬合法、台风只在夏秋暖季合法（IsleWeather.type_legal）。
## 轮到非法类型时先跳到该类型的既有证据工况日期，再切换，保证 12 类全部真实覆盖。
const WEATHER_FALLBACK_DATE := {
	"light_snow": [2027, 1, 15, 10, 0],
	"mid_snow": [2027, 1, 15, 10, 0],
	"heavy_snow": [2027, 1, 15, 10, 0],
	"typhoon": [2026, 7, 15, 12, 20],
}
## 季节 / 跨年 / 闰年 2/29 / 月末 / 非闰 2 月末 跳转序列（含期望回读值）。
const DATE_STEPS := [
	{"tag": "spring", "y": 2026, "mo": 4, "d": 15, "h": 10, "mi": 0, "season": "spring"},
	{"tag": "summer", "y": 2026, "mo": 7, "d": 15, "h": 10, "mi": 0, "season": "summer"},
	{"tag": "autumn", "y": 2026, "mo": 10, "d": 20, "h": 16, "mi": 30, "season": "autumn"},
	{"tag": "winter", "y": 2027, "mo": 1, "d": 15, "h": 10, "mi": 0, "season": "winter"},
	{"tag": "cross_year_a", "y": 2027, "mo": 12, "d": 31, "h": 23, "mi": 50, "season": "winter"},
	{"tag": "cross_year_b", "y": 2028, "mo": 1, "d": 1, "h": 0, "mi": 10, "season": "winter"},
	{"tag": "leap_day", "y": 2028, "mo": 2, "d": 29, "h": 12, "mi": 0, "season": "winter"},
	{"tag": "month_end_a", "y": 2027, "mo": 1, "d": 31, "h": 23, "mi": 59, "season": "winter"},
	{"tag": "month_end_b", "y": 2027, "mo": 2, "d": 1, "h": 0, "mi": 1, "season": "winter"},
	{"tag": "nonleap_a", "y": 2026, "mo": 2, "d": 28, "h": 23, "mi": 59, "season": "winter"},
	{"tag": "nonleap_b", "y": 2026, "mo": 3, "d": 1, "h": 0, "mi": 1, "season": "spring"},
]
const CSV_HEADER := "t_s,fps,p50_ms,p95_ms,p99_ms,max_ms,frames,engine_fps,nodes,orphan_nodes,objects,draw_calls,vram_mb,mem_static_mb,obj_count,res_count,lights_active,light_budget,weather,season,datetime,quality,max_fps"

## 采样 Node：只做一件事——把每一帧的真实 delta 记下来。
class FrameSampler extends Node:
	var t_ms := PackedFloat32Array()
	var dt_ms := PackedFloat32Array()
	var frames := 0
	var _t0 := 0

	func _ready() -> void:
		_t0 = Time.get_ticks_msec()
		set_process(true)

	func _process(delta: float) -> void:
		frames += 1
		# 单帧 delta 夹到 2s：窗口被系统拖走/最小化时 delta 会爆到几十秒，夹掉但不丢帧
		t_ms.append(float(Time.get_ticks_msec() - _t0))
		dt_ms.append(minf(delta, 2.0) * 1000.0)

var _minutes := 30.0
var _out := OUT_DEFAULT
var _sample_sec := 5.0
var _op_scale := 1.0
var _vsync := "off"
var _settle := 0.5

var _isle: Node = null
var _hud: Node = null
var _sampler: FrameSampler = null
var _t0 := 0
var _rows: Array = []
var _ops: Array = []
var _checks: Array = []
var _fails: Array = []
var _csv: FileAccess = null
var _logf: FileAccess = null
var _csv_path := ""
var _log_path := ""
var _q_step := 0
var _wx_step := 0
var _date_step := 0
var _hud_step := 0
var _last_sample_ms := 0.0
var _win_size := Vector2i.ZERO
var _boot_ok := false

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--minutes="):
			_minutes = maxf(0.5, float(s.substr(10)))
		elif s.begins_with("--out="):
			_out = s.substr(6).strip_edges().trim_suffix("/") + "/"
		elif s.begins_with("--sample="):
			_sample_sec = clampf(float(s.substr(9)), 1.0, 60.0)
		elif s.begins_with("--op-scale="):
			_op_scale = clampf(float(s.substr(11)), 0.02, 5.0)
		elif s.begins_with("--vsync="):
			_vsync = s.substr(8).strip_edges()
		elif s.begins_with("--settle="):
			_settle = clampf(float(s.substr(9)), 0.1, 5.0)
	_run.call_deferred()

# ============================================================
# 日志 / 断言
# ============================================================
func _log(text: String) -> void:
	print(text)
	if _logf != null:
		_logf.store_line(text)
		_logf.flush()

func _elapsed() -> float:
	return float(Time.get_ticks_msec() - _t0) / 1000.0

func _ok(cond: bool, name: String, detail: String = "") -> void:
	_checks.append({"name": name, "ok": cond, "detail": detail})
	if cond:
		_log("[P82SOAK] CHECK ok   %s | %s" % [name, detail])
	else:
		_fails.append(name + (" | " + detail if detail != "" else ""))
		_log("[P82SOAK] CHECK FAIL %s | %s" % [name, detail])

func _record_op(kind: String, ok: bool, tag: String, detail: String) -> void:
	_ops.append({"t": snappedf(_elapsed(), 0.1), "kind": kind, "tag": tag, "ok": ok, "detail": detail})
	if ok:
		_log("[P82SOAK] OPS ok   %-7s %-14s | %s" % [kind, tag, detail])
	else:
		_fails.append("%s/%s | %s" % [kind, tag, detail])
		_log("[P82SOAK] OPS FAIL %-7s %-14s | %s" % [kind, tag, detail])

# ============================================================
# 启动
# ============================================================
func _boot() -> bool:
	_log("[P82SOAK] ===== P8.2-06 soak probe =====")
	_log("[P82SOAK] engine=%s os=%s host=%s" % [
		String(Engine.get_version_info().get("string", "?")), OS.get_version(), OS.get_name()])
	if DisplayServer.get_name() != "headless":
		_log("[P82SOAK] gpu=%s api=%s" % [
			RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_api_version()])
	else:
		_log("[P82SOAK] WARN 当前是 headless，帧时间采样无意义（必须真窗口跑）")
	_log("[P82SOAK] args minutes=%.2f op_scale=%.3f sample=%.1fs vsync=%s settle=%.2f out=%s" % [
		_minutes, _op_scale, _sample_sec, _vsync, _settle, _out])

	var packed: PackedScene = load("res://isle.tscn")
	if packed == null:
		_log("[P82SOAK] BOOT FAIL 无法加载 res://isle.tscn")
		return false
	_isle = packed.instantiate()
	if _isle == null:
		_log("[P82SOAK] BOOT FAIL isle.tscn 实例化失败")
		return false
	root.add_child(_isle)
	for i in range(4):
		await process_frame
	if DisplayServer.get_name() != "headless" and _vsync == "off":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	# 跳过菜单，直接进游玩态（与 tools/probe_soak_p7v31.gd 同一路径）
	var menu = _isle.get("_menu")
	if menu != null and menu.has_method("instant_finish"):
		menu.call("instant_finish")
	_isle.set("_mode", 1)
	_isle.set("_time_source", "sim")
	_isle.set("_realtime", false)
	_isle.set("_started", true)
	_isle.set("_paused", false)
	_isle.set("_auto_orbit", true)
	_isle.set("_blending", "")
	await process_frame
	_isle.call("_jump_datetime", 2026, 7, 15, 12, 0, 0)
	await process_frame
	# main._ready/_enter_playing 会按存档分辨率 _apply_resolution()（延迟调用，可能晚于本次设置），
	# 所以重复钉窗口尺寸直到稳定；不改 _settings，避免污染玩家存档。
	if DisplayServer.get_name() != "headless":
		if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		for attempt in range(8):
			DisplayServer.window_set_size(Vector2i(RES_W, RES_H))
			await process_frame
			await process_frame
			var cur := DisplayServer.window_get_size()
			if cur.x == RES_W and cur.y == RES_H:
				break
		await create_timer(0.4).timeout
		if DisplayServer.window_get_size() != Vector2i(RES_W, RES_H):
			DisplayServer.window_set_size(Vector2i(RES_W, RES_H))
			await create_timer(0.2).timeout
	_win_size = DisplayServer.window_get_size()
	_hud = _isle.get("_hud")
	_sampler = FrameSampler.new()
	_sampler.name = "P82FrameSampler"
	root.add_child(_sampler)

	_ok(_isle.is_inside_tree(), "isle_in_tree", "")
	_ok(_hud != null, "hud_available", "")
	_ok(_sampler != null and _sampler.is_inside_tree(), "sampler_in_tree", "")
	var cal: Dictionary = ISLE_CALENDAR.parts(float(_isle.get("_sim_seconds")))
	_ok(int(cal.get("year", 0)) == 2026 and int(cal.get("month", 0)) == 7, "boot_datetime_2026_07",
		String(cal.get("date_label", "")))
	_log("[P82SOAK] window=%dx%d requested=%dx%d vsync=%s" % [
		_win_size.x, _win_size.y, RES_W, RES_H, _vsync])
	if DisplayServer.get_name() == "headless":
		_ok(true, "window_1600x900", "SKIP headless（无窗口，尺寸无意义）")
	else:
		_ok(_win_size.x == RES_W and _win_size.y == RES_H, "window_1600x900",
			"got=%dx%d" % [_win_size.x, _win_size.y])
	var ls: Dictionary = _isle.call("debug_light_state")
	_ok(int(ls.get("active", -1)) >= 0, "debug_light_state_ok",
		"active=%d budget=%d" % [int(ls.get("active", -1)), int(ls.get("budget", -1))])
	_boot_ok = true
	return true

# ============================================================
# 主循环
# ============================================================
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
	_csv_path = _out + "soak_" + stamp + ".csv"
	_log_path = _out + "soak_" + stamp + ".log"
	_csv = FileAccess.open(_csv_path, FileAccess.WRITE)
	_logf = FileAccess.open(_log_path, FileAccess.WRITE)
	if _csv == null or _logf == null:
		print("[P82SOAK] BOOT FAIL 无法打开输出文件: ", _csv_path, " / ", _log_path)
		quit(2)
		return
	var booted: bool = await _boot()
	if not booted:
		_log("[P82SOAK] RESULT FAIL (boot 未完成)")
		_finish(0.0)
		return
	_csv.store_line(CSV_HEADER)
	_csv.flush()

	var dur := _minutes * 60.0
	_t0 = Time.get_ticks_msec()
	_last_sample_ms = 0.0
	var next_sample := _sample_sec
	var next_q := 60.0 * _op_scale
	var next_wx := 90.0 * _op_scale
	var next_date := 150.0 * _op_scale
	var next_hud := 180.0 * _op_scale
	_log("[P82SOAK] loop start dur=%.1fs sample=%.1fs ops: quality=%.1fs weather=%.1fs date=%.1fs hud=%.1fs" % [
		dur, _sample_sec, next_q, next_wx, next_date, next_hud])
	_sample(0.0)
	while true:
		var now := _elapsed()
		if now >= dur:
			break
		var nxt: float = minf(next_sample, minf(next_q, minf(next_wx, minf(next_date, next_hud))))
		await create_timer(clampf(nxt - now, 0.02, 5.0)).timeout
		now = _elapsed()
		if now >= dur:
			break
		if now >= next_sample:
			_sample(now)
			next_sample = maxf(next_sample + _sample_sec, now + 0.5)
		if now >= next_q:
			await _op_quality()
			next_q = maxf(next_q + 60.0 * _op_scale, _elapsed() + 0.5)
		if now >= next_wx:
			await _op_weather()
			next_wx = maxf(next_wx + 90.0 * _op_scale, _elapsed() + 0.5)
		if now >= next_date:
			await _op_date()
			next_date = maxf(next_date + 150.0 * _op_scale, _elapsed() + 0.5)
		if now >= next_hud:
			await _op_hud()
			next_hud = maxf(next_hud + 180.0 * _op_scale, _elapsed() + 0.5)

	var elapsed := _elapsed()
	# 收尾：把画质/HUD 还原成中间档与可见，避免影响后续人工观察
	if _isle != null and is_instance_valid(_isle) and _isle.has_method("_apply_quality"):
		_isle.call("_apply_quality", 2)
	if _hud != null and is_instance_valid(_hud) and _hud.has_method("set_hud_visible"):
		_hud.call("set_hud_visible", true, false)
	await create_timer(0.3).timeout
	_finish(elapsed)

# ============================================================
# 采样
# ============================================================
func _frame_now_ms() -> float:
	if _sampler == null or _sampler.t_ms.is_empty():
		return 0.0
	return float(_sampler.t_ms[_sampler.t_ms.size() - 1])

func _pct(sorted_vals: Array, frac: float) -> float:
	var n := sorted_vals.size()
	if n == 0:
		return 0.0
	var idx := clampi(int(round(float(n - 1) * frac)), 0, n - 1)
	return float(sorted_vals[idx])

## 统计 [_sampler 时间基] (from_ms, to_ms] 区间内的真实帧间隔。
## 只信任 _process(delta) 累计值：Performance.TIME_PROCESS 在窗口模式下不可信。
func _window_stats(from_ms: float, to_ms: float) -> Dictionary:
	var span := maxf(0.001, (to_ms - from_ms) / 1000.0)
	var dts: Array = []
	var ts: PackedFloat32Array = _sampler.t_ms
	var ds: PackedFloat32Array = _sampler.dt_ms
	for i in range(ts.size()):
		var t := float(ts[i])
		if t > from_ms and t <= to_ms:
			dts.append(float(ds[i]))
	var n := dts.size()
	if n == 0:
		return {"frames": 0, "span": span, "fps": 0.0, "p50": 0.0, "p95": 0.0, "p99": 0.0, "max": 0.0}
	dts.sort()
	return {
		"frames": n,
		"span": span,
		"fps": float(n) / span,
		"p50": _pct(dts, 0.50),
		"p95": _pct(dts, 0.95),
		"p99": _pct(dts, 0.99),
		"max": float(dts[n - 1]),
	}

func _perf() -> Dictionary:
	return {
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphan": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"dc": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"vram": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"mem_static": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
		"obj_count": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"res_count": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
	}

func _state_probe() -> Dictionary:
	var cal: Dictionary = ISLE_CALENDAR.parts(float(_isle.get("_sim_seconds")))
	var ls: Dictionary = _isle.call("debug_light_state")
	var ws: Dictionary = _isle.get("_weather_state")
	return {
		"lights_active": int(ls.get("active", 0)),
		"light_budget": int(ls.get("budget", 0)),
		"weather": String(ws.get("type", "?")),
		"season": String(cal.get("season_id", "?")),
		"datetime": String(cal.get("date_label", "?")) + " " + String(cal.get("clock_label", "?")),
		"quality": int(_isle.get("_quality")),
		"max_fps": Engine.max_fps,
	}

func _sample(now: float) -> void:
	var to_ms := _frame_now_ms()
	var st: Dictionary = _window_stats(_last_sample_ms, to_ms)
	_last_sample_ms = to_ms
	var pf: Dictionary = _perf()
	var sp: Dictionary = _state_probe()
	var row := {
		"t": snappedf(now, 0.1),
		"fps": snappedf(float(st["fps"]), 0.1),
		"p50": snappedf(float(st["p50"]), 0.01),
		"p95": snappedf(float(st["p95"]), 0.01),
		"p99": snappedf(float(st["p99"]), 0.01),
		"max": snappedf(float(st["max"]), 0.01),
		"frames": int(st["frames"]),
		"engine_fps": snappedf(Engine.get_frames_per_second(), 0.1),
		"nodes": int(pf["nodes"]),
		"orphan": int(pf["orphan"]),
		"objects": int(pf["objects"]),
		"dc": int(pf["dc"]),
		"vram": float(pf["vram"]),
		"mem_static": float(pf["mem_static"]),
		"obj_count": int(pf["obj_count"]),
		"res_count": int(pf["res_count"]),
		"lights_active": int(sp["lights_active"]),
		"light_budget": int(sp["light_budget"]),
		"weather": String(sp["weather"]),
		"season": String(sp["season"]),
		"datetime": String(sp["datetime"]),
		"quality": int(sp["quality"]),
		"max_fps": int(sp["max_fps"]),
	}
	_rows.append(row)
	var line := "%7.1f,%6.1f,%7.2f,%7.2f,%7.2f,%7.2f,%5d,%6.1f,%6d,%5d,%6d,%5d,%8.1f,%8.1f,%6d,%6d,%3d,%3d,%s,%s,%s,%d,%d" % [
		float(row["t"]), float(row["fps"]), float(row["p50"]), float(row["p95"]), float(row["p99"]),
		float(row["max"]), int(row["frames"]), float(row["engine_fps"]), int(row["nodes"]),
		int(row["orphan"]), int(row["objects"]), int(row["dc"]), float(row["vram"]),
		float(row["mem_static"]), int(row["obj_count"]), int(row["res_count"]),
		int(row["lights_active"]), int(row["light_budget"]), String(row["weather"]),
		String(row["season"]), String(row["datetime"]), int(row["quality"]), int(row["max_fps"]),
	]
	if _csv != null:
		_csv.store_line(line)
		_csv.flush()
	_log("[P82SOAK] t=%6.1fs fps=%6.1f p50=%6.2f p95=%7.2f p99=%7.2f max=%7.2f n=%4d dc=%4d nodes=%5d orphan=%3d vram=%.1fMB mem=%.1fMB lights=%d/%d q=%d wx=%s %s %s %s" % [
		float(row["t"]), float(row["fps"]), float(row["p50"]), float(row["p95"]), float(row["p99"]),
		float(row["max"]), int(row["frames"]), int(row["dc"]), int(row["nodes"]), int(row["orphan"]),
		float(row["vram"]), float(row["mem_static"]), int(row["lights_active"]), int(row["light_budget"]),
		int(row["quality"]), String(row["weather"]), String(row["season"]), String(row["datetime"]),
		("max_fps=" + str(int(row["max_fps"])))])

# ============================================================
# 周期操作（每次都必须回读校验「真的生效」）
# ============================================================
func _op_quality() -> void:
	var q := _q_step % QUALITY_COUNT
	_q_step += 1
	_isle.call("_apply_quality", q)
	await create_timer(_settle * 0.6).timeout
	var got := int(_isle.get("_quality"))
	var qs: Dictionary = _isle.get("_quality_state")
	var vp: Viewport = root.get_viewport()
	var msaa_got := int(vp.msaa_3d)
	var msaa_want := int(qs.get("msaa_3d", -1))
	var fps_got := Engine.max_fps
	var fps_want := int(qs.get("max_fps", -1))
	var ls: Dictionary = _isle.call("debug_light_state")
	var budget := int(ls.get("budget", -1))
	var budget_want := clampi(int(qs.get("light_budget", -1)), 10, 16)
	var active := int(ls.get("active", -1))
	var ok: bool = got == q and msaa_got == msaa_want and fps_got == fps_want and budget == budget_want and active >= 0 and active <= budget
	_record_op("quality", ok, "q%d" % q,
		"quality=%d msaa3d=%d(want %d) max_fps=%d(want %d) budget=%d(want %d) active=%d" % [
			got, msaa_got, msaa_want, fps_got, fps_want, budget, budget_want, active])

func _op_weather() -> void:
	var wtype := String(WEATHER_ORDER[_wx_step % WEATHER_ORDER.size()])
	_wx_step += 1
	var forced := "-"
	var avail: Array = _isle.call("_weather_available_types")
	if not avail.has(wtype) and WEATHER_FALLBACK_DATE.has(wtype):
		# 该类型在当前季节不合法：先跳到它的既有证据工况日期，再重取合法集合
		var d: Array = WEATHER_FALLBACK_DATE[wtype]
		_isle.set("_paused", true)
		_isle.call("_jump_datetime", int(d[0]), int(d[1]), int(d[2]), int(d[3]), int(d[4]), 0)
		await create_timer(0.12).timeout
		_isle.set("_paused", false)
		forced = "%04d-%02d-%02d %02d:%02d" % [int(d[0]), int(d[1]), int(d[2]), int(d[3]), int(d[4])]
		avail = _isle.call("_weather_available_types")
	var legal := avail.has(wtype)
	_isle.call("_on_weather_type_requested", wtype)
	await create_timer(_settle * 0.6).timeout
	var ws: Dictionary = _isle.get("_weather_state")
	var got := String(ws.get("type", "?"))
	var label := String(ws.get("label", ""))
	var expect_label := String(ISLE_WEATHER.TYPE_LABELS.get(wtype, ""))
	var label_ok := label == "" or label == expect_label
	var ok: bool = legal and got == wtype and label_ok
	_record_op("weather", ok, wtype,
		"type=%s(want %s) label=%s legal=%s forced=%s cloud=%.2f precip=%s/%.2f storm=%.2f" % [
			got, wtype, label, str(legal), forced,
			float(ws.get("cloud", 0.0)), String(ws.get("precip_type", "-")),
			float(ws.get("precip_intensity", 0.0)), float(ws.get("storm", 0.0))])

func _op_date() -> void:
	if _date_step >= DATE_STEPS.size():
		_date_step = 0
	var d: Dictionary = DATE_STEPS[_date_step]
	_date_step += 1
	_isle.set("_paused", true)
	await create_timer(0.05).timeout
	_isle.call("_jump_datetime", int(d["y"]), int(d["mo"]), int(d["d"]), int(d["h"]), int(d["mi"]), 0)
	await create_timer(0.12).timeout
	var cal: Dictionary = ISLE_CALENDAR.parts(float(_isle.get("_sim_seconds")))
	var got_str := "%04d-%02d-%02d %02d:%02d" % [
		int(cal.get("year", 0)), int(cal.get("month", 0)), int(cal.get("day", 0)),
		int(cal.get("hour", 0)), int(cal.get("minute", 0))]
	var want_str := "%04d-%02d-%02d %02d:%02d" % [
		int(d["y"]), int(d["mo"]), int(d["d"]), int(d["h"]), int(d["mi"])]
	var date_ok := got_str == want_str
	var season_ok := String(cal.get("season_id", "?")) == String(d["season"])
	_isle.set("_paused", false)
	await create_timer(0.05).timeout
	_record_op("date", date_ok and season_ok, String(d["tag"]),
		"got=%s(want %s) season=%s(want %s)" % [
			got_str, want_str, String(cal.get("season_id", "?")), String(d["season"])])

func _flag(name: String) -> bool:
	var v = _hud.get(name)
	if v == null:
		return false
	return bool(v)

func _op_hud() -> void:
	var n := _hud_step % 6
	_hud_step += 1
	if n == 5:
		_hud.call("set_hud_visible", false, false)
		await create_timer(_settle * 0.8).timeout
		var vv = _hud.get("_visible_now")
		var hidden: bool = (vv != null) and (not bool(vv))
		var collapsed := true
		for k in ["_time_open", "_weather_open", "_perf_open", "_almanac_open"]:
			collapsed = collapsed and (not _flag(k))
		_hud.call("set_hud_visible", true, false)
		await create_timer(_settle * 0.8).timeout
		var shown: bool = (_hud.get("_visible_now") == null) or bool(_hud.get("_visible_now"))
		var ok: bool = hidden and collapsed and shown
		_record_op("hud", ok, "visibility",
			"hidden=%s all_panels_collapsed=%s shown_again=%s" % [str(hidden), str(collapsed), str(shown)])
		return
	var pairs := [
		["_time_open", "toggle_time_panel", "time_panel", "_time_panel"],
		["_cal_open", "_toggle_calendar", "calendar", "_cal_section"],
		["_weather_open", "toggle_weather_panel", "weather_panel", "_weather_panel"],
		["_perf_open", "toggle_perf", "perf_panel", "_perf_panel"],
		["_almanac_open", "toggle_almanac", "almanac", "_almanac"],
	]
	var pr: Array = pairs[n]
	var flag_name := String(pr[0])
	var method := String(pr[1])
	var tag := String(pr[2])
	var panel_name := String(pr[3])
	# 主脚本会在大量运镜/流程里把 HUD 整体隐藏（set_hud_visible(false)），
	# 那样面板 visible 一定为 false。先把 HUD 显式打开（最多重试 3 次），断言才有意义。
	var hud_visible := false
	for attempt in range(3):
		if _hud.has_method("set_hud_visible"):
			_hud.call("set_hud_visible", true, false)
		await create_timer(0.12).timeout
		hud_visible = (_hud.get("_visible_now") == null) or _flag("_visible_now")
		if hud_visible:
			break
	var before := _flag(flag_name)
	_hud.call(method)
	await create_timer(_settle * 0.8).timeout
	var after := _flag(flag_name)
	var panel = _hud.get(panel_name)
	var panel_visible := "n/a"
	var panel_ok := true
	if panel != null and panel is CanvasItem:
		panel_visible = str((panel as CanvasItem).visible)
		panel_ok = ((panel as CanvasItem).visible == after)
	# 再点一次恢复现场，避免影响后续截图/人工观察
	_hud.call(method)
	await create_timer(_settle * 0.5).timeout
	var reverted := _flag(flag_name) == before
	var ok: bool = after != before and panel_ok and reverted and hud_visible
	_record_op("hud", ok, tag,
		"flag %s->%s panel_visible=%s panel_ok=%s reverted=%s hud_visible=%s" % [
			str(before), str(after), panel_visible, str(panel_ok), str(reverted), str(hud_visible)])

# ============================================================
# 判定
# ============================================================
func _median_col(col: String, from_idx: int, count: int) -> float:
	if _rows.is_empty():
		return 0.0
	var i0: int = clampi(from_idx, 0, _rows.size() - 1)
	var i1: int = mini(_rows.size(), i0 + count)
	var vals: Array = []
	for j in range(i0, i1):
		vals.append(float(_rows[j][col]))
	if vals.is_empty():
		return 0.0
	vals.sort()
	return float(vals[vals.size() / 2])

func _count_ops(kind: String) -> int:
	var c := 0
	for o in _ops:
		if String(o["kind"]) == kind:
			c += 1
	return c

func _count_ops_ok(kind: String) -> int:
	var c := 0
	for o in _ops:
		if String(o["kind"]) == kind and bool(o["ok"]):
			c += 1
	return c

func _distinct_weather_types() -> Array:
	var seen: Array = []
	for o in _ops:
		if String(o["kind"]) == "weather" and bool(o["ok"]) and not seen.has(String(o["tag"])):
			seen.append(String(o["tag"]))
	return seen

## 短跑时降低覆盖要求：真实长跑（dur>=600s）才要求 70% 计划次数与 12 类天气全覆盖。
func _need(dur: float, interval_s: float) -> int:
	var planned := int(floor(dur / maxf(0.001, interval_s)))
	if dur >= 600.0:
		return int(floor(float(planned) * 0.7))
	return maxi(1, mini(planned, 2))

func _criteria(elapsed: float, dur: float) -> Array:
	var out: Array = []
	# C1 帧时间 p95 退化：末段 p95 不得高于首段 p95*1.25+2ms（短跑无意义，SKIP）
	var total_ms := _frame_now_ms()
	if elapsed < 720.0:
		out.append({"name": "C1_frame_p95_degrade", "status": "SKIP",
			"detail": "运行 %.0fs < 720s，趋势判定无意义（留给最终 30min soak）" % elapsed})
	else:
		var win_ms: float = minf(300000.0, maxf(20000.0, elapsed * 500.0))
		var first: Dictionary = _window_stats(0.0, win_ms)
		var last: Dictionary = _window_stats(maxf(0.0, total_ms - win_ms), total_ms)
		var limit: float = float(first["p95"]) * 1.25 + 2.0
		var ok: bool = float(last["p95"]) <= limit
		out.append({"name": "C1_frame_p95_degrade", "status": "PASS" if ok else "FAIL",
			"detail": "first p95=%.2fms (%d frames) -> last p95=%.2fms, limit=%.2fms" % [
				float(first["p95"]), int(first["frames"]), float(last["p95"]), limit]})
	# C2 节点数增长：末 3 次采样 nodes 中位数增长 <= n0*2%+50
	var n0 := _median_col("nodes", 0, 3)
	var n1 := _median_col("nodes", maxi(0, _rows.size() - 3), 3)
	var nlimit: float = n0 * 0.02 + 50.0
	var c2: bool = (n0 <= 0.0) or ((n1 - n0) <= nlimit)
	out.append({"name": "C2_node_growth", "status": "PASS" if c2 else "FAIL",
		"detail": "nodes %.0f -> %.0f (delta %+.0f, limit +%.0f)" % [n0, n1, n1 - n0, nlimit]})
	# C3 连续低帧：不得出现连续 3 次采样 fps<20
	var run := 0
	var worst := 0
	var worst_t := 0.0
	for r in _rows:
		if float(r["fps"]) < 20.0:
			run += 1
			if run > worst:
				worst = run
				worst_t = float(r["t"])
		else:
			run = 0
	out.append({"name": "C3_fps_floor", "status": "PASS" if worst < 3 else "FAIL",
		"detail": "最长连续 <20fps 采样 %d 次（阈值 3），出现在 t=%.0fs" % [worst, worst_t]})
	# C4 操作覆盖
	var need_q := _need(dur, 60.0 * _op_scale)
	var need_w := _need(dur, 90.0 * _op_scale)
	var need_d := _need(dur, 150.0 * _op_scale)
	var need_h := _need(dur, 180.0 * _op_scale)
	var cq := _count_ops("quality")
	var cw := _count_ops("weather")
	var cd := _count_ops("date")
	var ch := _count_ops("hud")
	var c4: bool = cq >= need_q and cw >= need_w and cd >= need_d and ch >= need_h
	var wtypes := _distinct_weather_types()
	var wdetail := ""
	if dur >= 600.0:
		c4 = c4 and wtypes.size() >= 12
		wdetail = ", weather_types=%d/12" % wtypes.size()
	out.append({"name": "C4_op_coverage", "status": "PASS" if c4 else "FAIL",
		"detail": "quality %d/%d, weather %d/%d, date %d/%d, hud %d/%d%s" % [
			cq, need_q, cw, need_w, cd, need_d, ch, need_h, wdetail]})
	# C5 操作/启动断言零失败
	out.append({"name": "C5_zero_assert_fail", "status": "PASS" if _fails.is_empty() else "FAIL",
		"detail": "%d 项断言失败" % _fails.size()})
	# C6 退出期状态健全
	var sane: bool = _isle != null and is_instance_valid(_isle) and _isle.is_inside_tree()
	if sane:
		sane = int(_isle.get("_mode")) == 1
	out.append({"name": "C6_state_sane", "status": "PASS" if sane else "FAIL",
		"detail": "isle_valid=%s in_tree=%s mode=%s" % [
			str(_isle != null and is_instance_valid(_isle)),
			str(_isle != null and is_instance_valid(_isle) and _isle.is_inside_tree()),
			str(int(_isle.get("_mode")) if _isle != null and is_instance_valid(_isle) else -1)]})
	return out

# ============================================================
# 收尾：汇总 + 判定 + 证据落盘
# ============================================================
func _finish(elapsed: float) -> void:
	var dur := _minutes * 60.0
	var crit: Array = _criteria(elapsed, dur)
	var pass_all := true
	for c in crit:
		if String(c["status"]) == "FAIL":
			pass_all = false
	var first_row: Dictionary = {}
	var last_row: Dictionary = {}
	if not _rows.is_empty():
		first_row = _rows[0]
		last_row = _rows[_rows.size() - 1]
	var total_ms := _frame_now_ms()
	var win_ms: float = minf(300000.0, maxf(20000.0, maxf(1.0, elapsed) * 500.0))
	var fw: Dictionary = _window_stats(0.0, win_ms)
	var lw: Dictionary = _window_stats(maxf(0.0, total_ms - win_ms), total_ms)
	var wtypes := _distinct_weather_types()
	var ops_failed := 0
	var ok_by_kind := {"quality": 0, "weather": 0, "date": 0, "hud": 0}
	for o in _ops:
		if not bool(o["ok"]):
			ops_failed += 1
		elif ok_by_kind.has(String(o["kind"])):
			ok_by_kind[String(o["kind"])] = int(ok_by_kind[String(o["kind"])]) + 1
	var node_delta := 0.0
	var orphan_delta := 0
	var vram_delta := 0.0
	var mem_delta := 0.0
	if not _rows.is_empty():
		node_delta = float(last_row["nodes"]) - float(first_row["nodes"])
		orphan_delta = int(last_row["orphan"]) - int(first_row["orphan"])
		vram_delta = float(last_row["vram"]) - float(first_row["vram"])
		mem_delta = float(last_row["mem_static"]) - float(first_row["mem_static"])
	var summary := {
		"verdict": ("PASS" if pass_all else "FAIL"),
		"elapsed_s": snappedf(elapsed, 0.1),
		"planned_s": snappedf(dur, 0.1),
		"samples": _rows.size(),
		"ops_total": _ops.size(),
		"ops_failed": ops_failed,
		"ops_ok_by_kind": ok_by_kind,
		"weather_types_covered": wtypes,
		"weather_types_count": wtypes.size(),
		"first_sample": first_row,
		"last_sample": last_row,
		"node_delta": node_delta,
		"orphan_delta": orphan_delta,
		"vram_delta_mb": snappedf(vram_delta, 0.1),
		"mem_static_delta_mb": snappedf(mem_delta, 0.1),
	}
	var meta := {
		"probe": "tools/probe_p82_soak.gd",
		"milestone": "P8.2-06",
		"project": ProjectSettings.get_setting("application/config/name", "?"),
		"engine": String(Engine.get_version_info().get("string", "?")),
		"gpu": RenderingServer.get_video_adapter_name(),
		"api": RenderingServer.get_video_adapter_api_version(),
		"os": OS.get_version(),
		"host_time": Time.get_datetime_string_from_system(),
		"minutes": _minutes,
		"op_scale": _op_scale,
		"sample_s": _sample_sec,
		"settle_s": _settle,
		"vsync": _vsync,
		"resolution": "%dx%d" % [_win_size.x, _win_size.y],
		"out": _out,
	}
	var doc := {
		"meta": meta,
		"summary": summary,
		"frame_windows": {"first": fw, "last": lw},
		"criteria": crit,
		"checks": _checks,
		"ops": _ops,
		"fails": _fails,
		"samples": _rows,
	}
	var stem := _log_path.get_basename()
	var json_path := stem + "_summary.json"
	var md_path := stem + "_summary.md"
	var jf := FileAccess.open(json_path, FileAccess.WRITE)
	if jf != null:
		jf.store_string(JSON.stringify(doc, "  "))
		jf.close()

	_log("[P82SOAK] ---------- summary ----------")
	_log("[P82SOAK] verdict=%s elapsed=%.1fs samples=%d ops=%d(ok=%d fail=%d)" % [
		summary["verdict"], elapsed, _rows.size(), _ops.size(), _ops.size() - ops_failed, ops_failed])
	_log("[P82SOAK] frame window: first p50=%.2f p95=%.2f max=%.2f | last p50=%.2f p95=%.2f max=%.2f" % [
		float(fw["p50"]), float(fw["p95"]), float(fw["max"]),
		float(lw["p50"]), float(lw["p95"]), float(lw["max"])])
	_log("[P82SOAK] state delta: nodes=%+.0f orphan=%+d vram=%+.1fMB mem_static=%+.1fMB" % [
		node_delta, orphan_delta, vram_delta, mem_delta])
	_log("[P82SOAK] ops coverage: quality=%d weather=%d(%d types) date=%d hud=%d" % [
		int(ok_by_kind["quality"]), int(ok_by_kind["weather"]), wtypes.size(),
		int(ok_by_kind["date"]), int(ok_by_kind["hud"])])
	for c in crit:
		_log("[P82SOAK] CRIT %-4s %-22s %s" % [String(c["status"]), String(c["name"]), String(c["detail"])])
	for f in _fails:
		_log("[P82SOAK] FAILED %s" % String(f))
	_log("[P82SOAK] csv=%s" % _csv_path)
	_log("[P82SOAK] log=%s" % _log_path)
	_log("[P82SOAK] json=%s" % json_path)
	_log("[P82SOAK] md=%s" % md_path)
	_log("[P82SOAK] NOTE 本结论仅代表「本次 %.1f 分钟 soak 未发现明显异常」，不构成内存泄漏/性能无回归的证明。" % (elapsed / 60.0))
	_log("[P82SOAK] RESULT %s" % String(summary["verdict"]))

	# ---- markdown 摘要 ----
	var md: PackedStringArray = []
	md.append("# P8.2-06 Soak 摘要")
	md.append("")
	md.append("- 结论：**%s**" % String(summary["verdict"]))
	md.append("- 运行：%.1f s（请求 %.1f min，op_scale=%.3f，采样 %.1fs）" % [
		elapsed, _minutes, _op_scale, _sample_sec])
	md.append("- 引擎：%s；GPU：%s；OS：%s" % [meta["engine"], meta["gpu"], meta["os"]])
	md.append("- 窗口：%s，VSync=%s，主机时间 %s" % [meta["resolution"], _vsync, meta["host_time"]])
	md.append("- 原始文件：%s（CSV）、%s（日志）" % [_csv_path.get_file(), _log_path.get_file()])
	md.append("")
	md.append("## 判定")
	md.append("")
	md.append("| 状态 | 项 | 明细 |")
	md.append("| --- | --- | --- |")
	for c in crit:
		md.append("| %s | %s | %s |" % [String(c["status"]), String(c["name"]), String(c["detail"])])
	md.append("")
	md.append("## 帧时间窗口")
	md.append("")
	md.append("| 窗口 | frames | fps | p50 | p95 | p99 | max |")
	md.append("| --- | --- | --- | --- | --- | --- | --- |")
	md.append("| 首 | %d | %.1f | %.2f | %.2f | %.2f | %.2f |" % [
		int(fw["frames"]), float(fw["fps"]), float(fw["p50"]), float(fw["p95"]),
		float(fw["p99"]), float(fw["max"])])
	md.append("| 末 | %d | %.1f | %.2f | %.2f | %.2f | %.2f |" % [
		int(lw["frames"]), float(lw["fps"]), float(lw["p50"]), float(lw["p95"]),
		float(lw["p99"]), float(lw["max"])])
	md.append("")
	md.append("## 操作覆盖")
	md.append("")
	md.append("| 类型 | 成功/总数 |")
	md.append("| --- | --- |")
	md.append("| quality | %d/%d |" % [int(ok_by_kind["quality"]), _count_ops("quality")])
	md.append("| weather | %d/%d（%d/12 类） |" % [
		int(ok_by_kind["weather"]), _count_ops("weather"), wtypes.size()])
	md.append("| date | %d/%d |" % [int(ok_by_kind["date"]), _count_ops("date")])
	md.append("| hud | %d/%d |" % [int(ok_by_kind["hud"]), _count_ops("hud")])
	md.append("")
	md.append("## 首末采样")
	md.append("")
	if not _rows.is_empty():
		md.append("| 采样 | t | fps | p95 | nodes | orphan | dc | vram | mem | lights | wx | season | datetime |")
		md.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
		for pair in [["首", first_row], ["末", last_row]]:
			var r: Dictionary = pair[1]
			md.append("| %s | %.0f | %.1f | %.2f | %d | %d | %d | %.1f | %.1f | %d | %s | %s | %s |" % [
				String(pair[0]), float(r["t"]), float(r["fps"]), float(r["p95"]), int(r["nodes"]),
				int(r["orphan"]), int(r["dc"]), float(r["vram"]), float(r["mem_static"]),
				int(r["lights_active"]), String(r["weather"]), String(r["season"]), String(r["datetime"])])
	md.append("")
	md.append("> 免责：本探针只能给出「本次运行未发现明显异常」；帧时间趋势受画质/天气周期影响，")
	md.append("> 不能据此宣称不存在内存泄漏。长跑（30min）结论以最终验收那次为准。")
	var mf := FileAccess.open(md_path, FileAccess.WRITE)
	if mf != null:
		mf.store_string("\n".join(md) + "\n")
		mf.close()

	if _csv != null:
		_csv.close()
		_csv = null
	if _logf != null:
		_logf.close()
		_logf = null
	quit(0 if pass_all else 1)
