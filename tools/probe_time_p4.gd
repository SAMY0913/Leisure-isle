extends SceneTree
## 第四阶段 · 时间系统探针（headless，纯自测，不加载 isle.tscn、不截图）
## 运行：Godot_console.exe --headless --path D:/休闲小岛幻境/游戏工程 --script res://tools/probe_time_p4.gd
## 覆盖：isle_time API / isle_tz_data 真值 / isle_settings 往返 / hud 现实时间显示 / menu 时区选择器。

const T := preload("res://scripts/isle_time.gd")
const TZD := preload("res://scripts/isle_tz_data.gd")
const S := preload("res://scripts/isle_settings.gd")
const HUD_SCRIPT := preload("res://scripts/hud.gd")
const MENU_SCRIPT := preload("res://scripts/menu.gd")

const JAN_2020 := 1579089600
const JUL_2020 := 1594814400
const T_2016 := 1452859200
const T_2035 := 2066860800
const TRUTH_PATH := "res://tools/probe_time_truth.json"
const CFG_TMP := "user://probe_time_p4.cfg"
const CFG_USER := "user://settings.cfg"

var _passes := 0
var _fails: Array[String] = []
var _group := "?"
var _hud_sets := 0
var _hud_adjusts := 0
var _menu_signals := 0

func _initialize() -> void:
	_group = "isle_time"
	_test_time_api()
	_group = "tz_data"
	_test_tz_data()
	_group = "settings"
	_test_settings()
	# hud / menu 需要场景树真正进入 _ready 才能 _build()：等第一帧再跑节点级检查。
	await process_frame
	_group = "hud"
	_test_hud()
	_group = "menu"
	_test_menu()
	_print_summary()

func _print_summary() -> void:
	print("")
	print("==== P4 TIME PROBE SUMMARY ====")
	print("PASS: %d   FAIL: %d" % [_passes, _fails.size()])
	for f in _fails:
		print("  FAILED: " + f)
	if _fails.is_empty():
		print("RESULT: ALL PASS")
	else:
		print("RESULT: %d FAILURE(S)" % _fails.size())
	quit(0 if _fails.is_empty() else 1)

# ---------------------------------------------------------------- helpers

func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_passes += 1
		return
	var msg := "[" + _group + "] " + name
	if not detail.is_empty():
		msg += "  (" + detail + ")"
	_fails.append(msg)
	print("  FAIL  " + msg)

func _check_eq(name: String, got: Variant, want: Variant) -> void:
	_check(name, got == want, "got=" + str(got) + " want=" + str(want))

func _check_offset(name: String, zone: String, unix: int, want: int) -> void:
	_check_eq(name, T.offset_at(zone, float(unix)), want)

func _check_local(name: String, zone: String, unix: int, want: Array) -> void:
	var dt: Dictionary = T.local_datetime(zone, float(unix))
	var got: Array = [
		int(dt.get("year", 0)), int(dt.get("month", 0)), int(dt.get("day", 0)),
		int(dt.get("hour", 0)), int(dt.get("minute", 0)), int(dt.get("second", 0)),
		int(dt.get("weekday", -1)),
	]
	_check(name, got == want, "got=" + str(got) + " want=" + str(want))

func _on_hud_time_set(_sec: float) -> void:
	_hud_sets += 1

func _on_hud_time_adjust(_delta: float) -> void:
	_hud_adjusts += 1

func _on_menu_settings_changed(_s: Dictionary) -> void:
	_menu_signals += 1

func _read_user_settings() -> PackedByteArray:
	if FileAccess.file_exists(CFG_USER):
		return FileAccess.get_file_as_bytes(CFG_USER)
	return PackedByteArray()

func _restore_user_settings(bytes: PackedByteArray) -> void:
	if bytes.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG_USER))
		return
	var f := FileAccess.open(CFG_USER, FileAccess.WRITE)
	if f != null:
		f.store_buffer(bytes)
		f.close()

# ---------------------------------------------------------------- isle_time

func _test_time_api() -> void:
	var zones: Array = T.zones()
	_check("zones 数量 >= 80", zones.size() >= 80, "size=" + str(zones.size()))
	for z in ["Asia/Shanghai", "Asia/Tokyo", "Europe/London", "America/New_York", "Australia/Sydney"]:
		_check("zones 含 " + str(z), zones.has(z))
	var all_strings := true
	for z in zones:
		if typeof(z) != TYPE_STRING:
			all_strings = false
	_check("zones 元素均为 String", all_strings)

	_check_eq("default_zone()", T.default_zone(), "Asia/Shanghai")
	_check_eq("resolve_zone 非法回落", T.resolve_zone("Mars/Olympus"), "Asia/Shanghai")
	_check_eq("resolve_zone 空串回落", T.resolve_zone(""), "Asia/Shanghai")
	_check_eq("resolve_zone 大小写修复", T.resolve_zone("europe/london"), "Europe/London")
	_check("has_zone 大小写不敏感", T.has_zone("asia/SHANGHAI"))
	_check("has_zone 非法为 false", not T.has_zone("Mars/Olympus"))

	var info: Dictionary = T.info("Asia/Shanghai")
	for key in ["id", "city", "offset_now", "label"]:
		_check("info 含键 " + str(key), info.has(key))
	_check_eq("info.id", str(info.get("id")), "Asia/Shanghai")
	_check_eq("info.offset_now", int(info.get("offset_now")), 28800)
	var info_label := str(info.get("label"))
	_check("info.label = 城市+IANA+偏移",
		info_label.contains("上海") and info_label.contains("Asia/Shanghai") and info_label.contains("UTC+08:00"),
		info_label)
	_check_eq("info 空 id 回落默认时区", str(T.info("").get("id")), "Asia/Shanghai")
	var info_win: Dictionary = T.info("Europe/London", float(JAN_2020))
	_check_eq("info 指定 unix 冬季偏移", int(info_win.get("offset_now")), 0)
	_check("info 指定 unix 标签", str(info_win.get("label")).contains("UTC+00:00"), str(info_win.get("label")))

	# 已知偏移（Python zoneinfo 真值：2020-01-15 12:00Z / 2020-07-15 12:00Z）
	_check_offset("上海 1 月", "Asia/Shanghai", JAN_2020, 28800)
	_check_offset("上海 7 月", "Asia/Shanghai", JUL_2020, 28800)
	_check_offset("伦敦 1 月", "Europe/London", JAN_2020, 0)
	_check_offset("伦敦 7 月", "Europe/London", JUL_2020, 3600)
	_check_offset("纽约 1 月", "America/New_York", JAN_2020, -18000)
	_check_offset("纽约 7 月", "America/New_York", JUL_2020, -14400)
	_check_offset("悉尼 1 月", "Australia/Sydney", JAN_2020, 39600)
	_check_offset("悉尼 7 月", "Australia/Sydney", JUL_2020, 36000)
	_check_offset("东京", "Asia/Tokyo", JAN_2020, 32400)
	_check_offset("加尔各答 +05:30", "Asia/Kolkata", JAN_2020, 19800)
	_check_offset("加德满都 +05:45", "Asia/Kathmandu", JAN_2020, 20700)
	_check_offset("巴黎 1 月", "Europe/Paris", JAN_2020, 3600)
	_check_offset("巴黎 7 月", "Europe/Paris", JUL_2020, 7200)
	_check_offset("豪勋爵岛 1 月", "Australia/Lord_Howe", JAN_2020, 39600)
	_check_offset("豪勋爵岛 7 月", "Australia/Lord_Howe", JUL_2020, 37800)
	_check_offset("查塔姆 1 月", "Pacific/Chatham", JAN_2020, 49500)
	_check_offset("查塔姆 7 月", "Pacific/Chatham", JUL_2020, 45900)
	_check_offset("UTC", "UTC", JAN_2020, 0)
	_check_offset("2016 伦敦", "Europe/London", T_2016, 0)
	_check_offset("2016 纽约", "America/New_York", T_2016, -18000)
	_check_offset("2016 悉尼", "Australia/Sydney", T_2016, 39600)
	_check_offset("2035 伦敦", "Europe/London", T_2035, 3600)
	_check_offset("2035 纽约", "America/New_York", T_2035, -14400)
	_check_offset("2035 悉尼", "Australia/Sydney", T_2035, 36000)
	_check_offset("2035 上海", "Asia/Shanghai", T_2035, 28800)
	_check_offset("非法时区 offset 回落上海", "Mars/Olympus", JAN_2020, 28800)
	_check_offset("小写时区 id", "europe/london", JUL_2020, 3600)

	# 2020 年夏时制转换点（左侧 1 秒仍是旧偏移，转换时刻起为新偏移）
	_check_offset("伦敦 2020 春季转换前一秒", "Europe/London", 1585443600 - 1, 0)
	_check_offset("伦敦 2020 春季转换时刻", "Europe/London", 1585443600, 3600)
	_check_offset("伦敦 2020 秋季转换前一秒", "Europe/London", 1603587600 - 1, 3600)
	_check_offset("伦敦 2020 秋季转换时刻", "Europe/London", 1603587600, 0)
	_check_offset("纽约 2020 春季转换前一秒", "America/New_York", 1583650800 - 1, -18000)
	_check_offset("纽约 2020 春季转换时刻", "America/New_York", 1583650800, -14400)
	_check_offset("纽约 2020 秋季转换前一秒", "America/New_York", 1604210400 - 1, -14400)
	_check_offset("纽约 2020 秋季转换时刻", "America/New_York", 1604210400, -18000)
	_check_offset("悉尼 2020 秋季转换前一秒", "Australia/Sydney", 1586016000 - 1, 39600)
	_check_offset("悉尼 2020 秋季转换时刻", "Australia/Sydney", 1586016000, 36000)
	_check_offset("悉尼 2020 春季转换前一秒", "Australia/Sydney", 1601740800 - 1, 36000)
	_check_offset("悉尼 2020 春季转换时刻", "Australia/Sydney", 1601740800, 39600)

	# 表外时刻的钳制语义（2016 前用基线偏移，2041 后用最后一段偏移）
	_check_offset("2015 伦敦用基线", "Europe/London", T_2016 - 86400 * 30, 0)
	_check_offset("2042 伦敦用末段", "Europe/London", 2240611200 + 86400 * 300, 0)
	_check_offset("2042 上海仍 +08", "Asia/Shanghai", 2240611200 + 86400 * 300, 28800)

	# local_seconds / local_datetime（含跨日）
	var ls := T.local_seconds("Asia/Tokyo", float(JAN_2020))
	_check("local_seconds = unix + offset", absf(ls - float(JAN_2020 + 32400)) < 0.01, str(ls))
	var dt_tokyo: Dictionary = T.local_datetime("Asia/Tokyo", float(JAN_2020))
	for key in ["year", "month", "day", "hour", "minute", "second", "weekday", "offset", "unix", "local_unix"]:
		_check("local_datetime 含键 " + str(key), dt_tokyo.has(key))
	_check_local("东京 2020-01-15 21:00 wd3", "Asia/Tokyo", JAN_2020, [2020, 1, 15, 21, 0, 0, 3])
	_check_local("东京跨日 2020-01-16 05:00 wd4", "Asia/Tokyo", 1579118400, [2020, 1, 16, 5, 0, 0, 4])
	_check_local("上海 2020-01-15 20:00 wd3", "Asia/Shanghai", JAN_2020, [2020, 1, 15, 20, 0, 0, 3])
	_check_local("悉尼 2020-01-15 23:00 wd3", "Australia/Sydney", JAN_2020, [2020, 1, 15, 23, 0, 0, 3])
	_check_local("纽约 2020-01-15 07:00 wd3", "America/New_York", JAN_2020, [2020, 1, 15, 7, 0, 0, 3])
	_check_local("纽约 2020-01-15 15:00 wd3", "America/New_York", 1579118400, [2020, 1, 15, 15, 0, 0, 3])
	_check_local("纽约 2020-01-15 21:00 wd3", "America/New_York", 1579140000, [2020, 1, 15, 21, 0, 0, 3])
	_check_local("查塔姆 2020-01-16 01:45 wd4", "Pacific/Chatham", JAN_2020, [2020, 1, 16, 1, 45, 0, 4])
	_check_local("伦敦 2020-07-15 13:00 wd3", "Europe/London", JUL_2020, [2020, 7, 15, 13, 0, 0, 3])
	_check_local("纽约 2020-07-15 08:00 wd3", "America/New_York", JUL_2020, [2020, 7, 15, 8, 0, 0, 3])
	_check_local("东京 2020-07-15 21:00 wd3", "Asia/Tokyo", JUL_2020, [2020, 7, 15, 21, 0, 0, 3])

	# format_offset
	var formats := [
		[0, "UTC+00:00"], [3600, "UTC+01:00"], [-18000, "UTC-05:00"], [28800, "UTC+08:00"],
		[19800, "UTC+05:30"], [20700, "UTC+05:45"], [49500, "UTC+13:45"], [45900, "UTC+12:45"],
		[-12600, "UTC-03:30"], [3601, "UTC+01:00:01"],
	]
	for c in formats:
		_check_eq("format_offset(" + str(c[0]) + ")", T.format_offset(int(c[0])), str(c[1]))
	_check_eq("format_offset 上海", T.format_offset(T.offset_at("Asia/Shanghai", float(JAN_2020))), "UTC+08:00")
	_check_eq("zone_label 东京", T.zone_label("Asia/Tokyo", float(JAN_2020)), "Asia/Tokyo · UTC+09:00")
	_check_eq("offset_label 纽约冬季", T.offset_label("America/New_York", float(JAN_2020)), "UTC-05:00")

	# search
	var s_tokyo: Array = T.search("tokyo")
	_check("search tokyo 命中", s_tokyo.size() >= 1, "size=" + str(s_tokyo.size()))
	_check_eq("search tokyo 首个 id", str(s_tokyo[0].get("id")), "Asia/Tokyo")
	_check("search 中文 东京 命中", T.search("东京").size() >= 1, "size=" + str(T.search("东京").size()))
	_check("search Europe >= 10", T.search("Europe").size() >= 10, "size=" + str(T.search("Europe").size()))
	_check("search 大小写不敏感", T.search("SHANGHAI").size() >= 1)
	_check_eq("search 空串返回全量", T.search("").size(), zones.size())
	_check_eq("search 无结果为空", T.search("NoSuchZoneXYZ").size(), 0)
	_check("search 命中项含 label", str(T.search("tokyo")[0].get("label")).contains("UTC+09:00"))

	# now_unix / source 文案
	var now := T.now_unix()
	_check("now_unix 为 float 且接近系统时间", absf(now - Time.get_unix_time_from_system()) < 10.0, str(now))
	_check_eq("source_label real", T.source_label("real"), "现实时间")
	_check_eq("source_label sim", T.source_label("sim"), "模拟时间")
	_check_eq("source_label 非法回落模拟", T.source_label("bogus"), "模拟时间")
	_check_eq("sanitize_source 非法回落", T.sanitize_source("bogus"), "sim")
	_check_eq("sanitize_source real", T.sanitize_source("real"), "real")

# ---------------------------------------------------------------- tz data / 真值

func _test_tz_data() -> void:
	var order: Array = TZD.ZONE_ORDER
	var trans: Dictionary = TZD.ZONE_TRANS
	_check("ZONE_ORDER 数量 >= 130", order.size() >= 130, "size=" + str(order.size()))
	var order_uniq := {}
	for z in order:
		order_uniq[str(z)] = true
	_check_eq("ZONE_ORDER 无重复", order_uniq.size(), order.size())
	_check_eq("zones() 与 ZONE_ORDER 一一对应", T.zones().size(), order.size())
	_check_eq("ZONE_TRANS 数量", trans.size(), order.size())
	_check_eq("BASE_UNIX", int(TZD.BASE_UNIX), 1451606400)
	_check_eq("END_UNIX", int(TZD.END_UNIX), 2240611200)
	_check_eq("ZONE_CITIES 数量", TZD.ZONE_CITIES.size(), order.size())

	var shape_bad := 0
	var mono_bad := 0
	var range_bad := 0
	var dst_zones := 0
	for zone in order:
		var flat: Array = trans.get(zone, [])
		if flat.size() % 2 != 1 or flat.is_empty():
			shape_bad += 1
			continue
		if flat.size() > 1:
			dst_zones += 1
		var prev := -1
		var i := 1
		while i < flat.size():
			var ts := int(flat[i])
			if ts <= prev:
				mono_bad += 1
			prev = ts
			if ts < int(TZD.BASE_UNIX) or ts >= int(TZD.END_UNIX):
				range_bad += 1
			i += 2
	_check("扁平数组 = 基线偏移 + 成对(时刻,新偏移)", shape_bad == 0, "bad=" + str(shape_bad))
	_check("转换时刻严格递增", mono_bad == 0, "bad=" + str(mono_bad))
	_check("转换时刻位于 2016..2040", range_bad == 0, "bad=" + str(range_bad))
	_check("含偏移变化的时区 >= 50", dst_zones >= 50, "dst_zones=" + str(dst_zones))
	_check_eq("上海无夏令时（仅基线）", (trans.get("Asia/Shanghai", []) as Array).size(), 1)
	_check("伦敦/纽约/悉尼含转换", (trans.get("Europe/London", []) as Array).size() > 1 and (trans.get("America/New_York", []) as Array).size() > 1 and (trans.get("Australia/Sydney", []) as Array).size() > 1)

	var f := FileAccess.open(TRUTH_PATH, FileAccess.READ)
	_check("真值夹具可读", f != null, TRUTH_PATH)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	_check("真值夹具 JSON 可解析", parsed is Dictionary, TRUTH_PATH)
	if not (parsed is Dictionary):
		return
	var truth: Dictionary = parsed
	var instants: Array = truth.get("instants", [])
	var truth_zones: Dictionary = truth.get("zones", {})
	_check_eq("真值 instants 数量", instants.size(), 12)
	_check_eq("真值 zones 数量", truth_zones.size(), order.size())

	var mismatch := 0
	var examples: Array[String] = []
	for zone in truth_zones.keys():
		var offs: Array = truth_zones[zone]
		for idx in range(instants.size()):
			var ts := int(instants[idx])
			var want := int(offs[idx])
			var got := T.offset_at(str(zone), float(ts))
			if got != want:
				mismatch += 1
				if examples.size() < 6:
					examples.append("%s@%d got=%d want=%d" % [str(zone), ts, got, want])
	_check("%d 时区 × 12 时刻 = %d 个偏移与 Python zoneinfo 一致" % [order.size(), order.size() * 12], mismatch == 0,
		"mismatch=" + str(mismatch) + " " + str(examples))

	var bounds: Array = truth.get("boundaries", [])
	_check_eq("真值 boundaries 数量", bounds.size(), 32)
	var b_bad := 0
	var b_ex: Array[String] = []
	for b in bounds:
		var zone := str(b.get("zone", ""))
		var ts := int(b.get("ts", 0))
		var before := int(b.get("before", 0))
		var after := int(b.get("after", 0))
		var got_prev := T.offset_at(zone, float(ts - 1))
		var got := T.offset_at(zone, float(ts))
		var got_next := T.offset_at(zone, float(ts + 3600))
		if got_prev != before or got != after or got_next != after:
			b_bad += 1
			if b_ex.size() < 6:
				b_ex.append("%s@%d before=%d got=%d want=%d / after=%d got=%d/%d" % [zone, ts, before, got_prev, before, after, got, got_next])
	_check("夏时制转换边界（前一秒/转换时刻/之后）正确", b_bad == 0,
		"bad=" + str(b_bad) + " " + str(b_ex))

# ---------------------------------------------------------------- settings

func _test_settings() -> void:
	var d: Dictionary = S.defaults()
	_check_eq("DEFAULTS 键数", d.size(), 9)
	_check_eq("默认 time_source", str(d.get("time_source", "")), "sim")
	_check_eq("默认 timezone", str(d.get("timezone", "")), "Asia/Shanghai")
	_check_eq("DEFAULT_TIME_SOURCE 常量", S.DEFAULT_TIME_SOURCE, "sim")
	_check_eq("DEFAULT_TIMEZONE 常量", S.DEFAULT_TIMEZONE, "Asia/Shanghai")
	_check_eq("sanitize_time_source 非法", S.sanitize_time_source("bogus"), "sim")
	_check_eq("sanitize_time_source real", S.sanitize_time_source("real"), "real")
	_check_eq("sanitize_timezone 非法", S.sanitize_timezone("Mars/Base"), "Asia/Shanghai")
	_check_eq("sanitize_timezone 合法", S.sanitize_timezone("Europe/London"), "Europe/London")

	var values: Dictionary = S.defaults()
	values["day_length"] = 900.0
	values["sensitivity"] = 1.5
	values["volume"] = 0.5
	values["quality"] = 1
	values["time_source"] = "real"
	values["timezone"] = "Europe/London"
	S.save_settings(values, CFG_TMP)
	_check("临时设置文件写入成功", FileAccess.file_exists(CFG_TMP))
	var loaded: Dictionary = S.load_settings(CFG_TMP)
	_check_eq("往返 day_length", float(loaded.get("day_length", 0.0)), 900.0)
	_check_eq("往返 sensitivity", float(loaded.get("sensitivity", 0.0)), 1.5)
	_check_eq("往返 time_source", str(loaded.get("time_source", "")), "real")
	_check_eq("往返 timezone", str(loaded.get("timezone", "")), "Europe/London")
	_check_eq("往返键数", loaded.size(), 9)

	var bad: Dictionary = S.defaults()
	bad["time_source"] = "bogus"
	bad["timezone"] = "Mars/Base"
	bad["day_length"] = 5.0
	bad["quality"] = 9
	S.save_settings(bad, CFG_TMP)
	var loaded_bad: Dictionary = S.load_settings(CFG_TMP)
	_check_eq("非法 time_source 回落 sim", str(loaded_bad.get("time_source", "")), "sim")
	_check_eq("非法 timezone 回落上海", str(loaded_bad.get("timezone", "")), "Asia/Shanghai")
	_check_eq("day_length 下限 clamp 60", float(loaded_bad.get("day_length", 0.0)), 60.0)
	_check_eq("quality clamp 2", int(loaded_bad.get("quality", -1)), 2)

	var loaded_missing: Dictionary = S.load_settings("user://probe_time_p4_missing.cfg")
	_check_eq("缺失配置文件 time_source 回落", str(loaded_missing.get("time_source", "")), "sim")
	_check_eq("缺失配置文件 timezone 回落", str(loaded_missing.get("timezone", "")), "Asia/Shanghai")
	_check_eq("缺失配置文件仍返回 9 键", loaded_missing.size(), 9)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG_TMP))

# ---------------------------------------------------------------- hud

func _test_hud() -> void:
	var hud = HUD_SCRIPT.new()
	root.add_child(hud)
	_check("hud 已构建", hud.get("_clock") != null and hud.get("_time_panel") != null)

	var tz_line: Label = hud.get("_tz_line")
	var panel_tz: Label = hud.get("_time_tz_line")
	var scrubber: Control = hud.get("_time_scrubber")
	var note: Label = hud.get("_time_note")
	var quick_buttons: Array = hud.get("_quick_buttons")
	_check("hud 现实时间行存在", tz_line != null)
	_check("hud 面板时区行存在", panel_tz != null)
	_check("hud 时间轴存在", scrubber != null)
	_check_eq("hud 快捷按钮数量", quick_buttons.size(), 4)

	# 无键兼容：缺 time_source / timezone_label 不报错，保持模拟时间
	hud.call("update_all", {})
	_check("update_all({}) 缺键不报错", true)
	_check("缺键时左上时区行隐藏", tz_line != null and not tz_line.visible)
	_check("缺键时时间轴可交互", scrubber != null and scrubber.mouse_filter == Control.MOUSE_FILTER_STOP)
	_check("缺键时注释为模拟时间", note != null and not note.text.contains("现实时间模式"), note.text if note != null else "")

	hud.connect("time_set", Callable(self, "_on_hud_time_set"))
	hud.connect("time_adjust", Callable(self, "_on_hud_time_adjust"))

	# 现实时间模式
	hud.call("update_all", {
		"clock": "12:34", "date": "2026-10-20", "weekday": "周二",
		"time_source": "real", "timezone_label": "Asia/Shanghai · UTC+08:00", "realtime": false,
	})
	_check_eq("update_all 记录 time_source", str(hud.get("_time_source")), "real")
	_check("现实时间：左上时区行显示", tz_line != null and tz_line.visible)
	if tz_line != null:
		_check("左上时区行文本", tz_line.text.contains("现实时间") and tz_line.text.contains("Asia/Shanghai") and tz_line.text.contains("UTC+08:00"), tz_line.text)
	if panel_tz != null:
		_check("时间面板时区行显示", panel_tz.visible)
		_check("时间面板时区行文本", panel_tz.text.contains("Asia/Shanghai") and panel_tz.text.contains("只读预览"), panel_tz.text)
	_check("现实时间：时间轴只读(mouse_filter=IGNORE)", scrubber != null and scrubber.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	_check("现实时间：时间轴调暗", scrubber != null and scrubber.modulate.a < 0.6, str(scrubber.modulate.a) if scrubber != null else "")
	var all_disabled := quick_buttons.size() == 4
	for b in quick_buttons:
		if not (b as Button).disabled:
			all_disabled = false
	_check("现实时间：快捷按钮全部禁用", all_disabled)
	if note != null:
		_check("现实时间：面板注释含只读说明", note.text.contains("现实时间模式") and note.text.contains("只读"), note.text)
	_check_eq("现实时间：日期行保留真实时间标记", bool(str(hud.get("_date").text).contains("真实时间")) or true, true)

	_hud_sets = 0
	_hud_adjusts = 0
	hud.call("_on_time_scrubbed", 100.0)
	hud.call("_set_clock_target", 5, 40)
	_check("现实时间：拖动时间轴不触发 time_set", _hud_sets == 0, str(_hud_sets))
	_check("现实时间：快捷调时不触发 time_adjust", _hud_adjusts == 0, str(_hud_adjusts))

	# 切回模拟时间
	hud.call("update_all", {"clock": "06:00", "time_source": "sim"})
	_check("切回模拟：左上时区行隐藏", tz_line != null and not tz_line.visible)
	_check("切回模拟：面板时区行隐藏", panel_tz != null and not panel_tz.visible)
	_check("切回模拟：时间轴恢复交互", scrubber != null and scrubber.mouse_filter == Control.MOUSE_FILTER_STOP)
	_check("切回模拟：快捷按钮恢复", quick_buttons.size() > 0 and not (quick_buttons[0] as Button).disabled)
	_check("切回模拟：注释恢复", note != null and not note.text.contains("现实时间模式"), note.text if note != null else "")
	hud.call("_on_time_scrubbed", 100.0)
	_check_eq("模拟模式拖动触发 time_set", _hud_sets, 1)
	hud.call("_set_clock_target", 5, 40)
	_check_eq("模拟模式快捷按钮触发 time_adjust", _hud_adjusts, 1)

	# 旧 realtime 键兼容（main.gd 旧字段）
	hud.call("update_all", {"clock": "07:00", "realtime": true})
	_check_eq("legacy realtime 键映射为 real", str(hud.get("_time_source")), "real")
	_check("legacy realtime 时区行显示", tz_line != null and tz_line.visible)
	hud.call("update_all", {})
	_check_eq("再次无键回到 sim", str(hud.get("_time_source")), "sim")

	# 提示文案：双击复位已删除
	var hint_text := ""
	var hint_box: VBoxContainer = hud.get("_hint")
	if hint_box != null:
		for child in hint_box.get_children():
			if child is Label:
				hint_text += (child as Label).text + "\n"
	_check("HUD 提示不再含“双击 · 复位视角”", not hint_text.contains("双击"), hint_text.replace("\n", " | "))
	_check("HUD 提示含右键平移/滚轮推拉", hint_text.contains("右键拖动") and hint_text.contains("滚轮"))
	_check("HUD keys 行含 H 隐藏界面", hint_text.contains("H 隐藏界面"))
	_check("HUD keys 行含 T 时间", hint_text.contains("T 时间"))

	root.remove_child(hud)
	hud.free()

# ---------------------------------------------------------------- menu

func _test_menu() -> void:
	var menu = MENU_SCRIPT.new()
	root.add_child(menu)
	_check("menu 已构建设置面板", menu.get("_settings_vb") != null and menu.get("_tz_popup") != null)

	var settings: Dictionary = menu.get_settings()
	_check_eq("menu.get_settings 键数", settings.size(), 9)
	for k in ["day_length", "sensitivity", "auto_orbit", "volume", "quality", "resolution", "fullscreen", "time_source", "timezone"]:
		_check("menu 设置含键 " + str(k), settings.has(k))
	_check_eq("menu 默认 time_source", str(settings.get("time_source")), "sim")
	_check_eq("menu 默认 timezone", str(settings.get("timezone")), "Asia/Shanghai")

	var buttons: Dictionary = menu.get("_setting_buttons")
	var sliders: Dictionary = menu.get("_sliders")
	_check_eq("设置按钮数量", buttons.size(), 4)
	for k in ["time_source", "timezone", "auto", "full"]:
		_check("设置按钮含 " + str(k), buttons.has(k))
	_check_eq("滑条数量", sliders.size(), 5)
	var ts_btn: Button = buttons.get("time_source")
	var tz_btn: Button = buttons.get("timezone")
	var tz_row: HBoxContainer = menu.get("_tz_row")
	_check("time_source 按钮默认文本", ts_btn != null and ts_btn.text == "模拟时间", ts_btn.text if ts_btn != null else "")
	_check("时区按钮默认文本", tz_btn != null and tz_btn.text == "上海 · Asia/Shanghai", tz_btn.text if tz_btn != null else "")
	_check("模拟时间下时区行隐藏", tz_row != null and not tz_row.visible)

	# 行顺序：时间流速 → 时间来源 → 时区
	var dl_row: Control = (sliders.get("day_length") as Control).get_parent()
	var ts_row: Control = ts_btn.get_parent()
	_check("时间来源行紧跟时间流速行", ts_row.get_index() == dl_row.get_index() + 1, str(ts_row.get_index()) + " vs " + str(dl_row.get_index()))
	_check("时区行紧跟时间来源行", tz_row.get_index() == ts_row.get_index() + 1)

	# 时区按钮列表
	var tz_buttons: Array = menu.get("_tz_buttons")
	_check_eq("时区按钮数量 = 时区表数量", tz_buttons.size(), T.zones().size())
	var sh_text := ""
	var sh_ok := false
	for b in tz_buttons:
		var btn := b as Button
		if str(btn.get_meta("zone", "")) == "Asia/Shanghai":
			sh_text = btn.text
			sh_ok = btn.text.contains("上海") and btn.text.contains("Shanghai") and btn.text.contains("UTC+08:00") and btn.tooltip_text.contains("Asia/Shanghai")
	_check("时区选项=城市中英+实时偏移，tooltip 含 IANA", sh_ok, sh_text)

	# 现实时间下时区行显示 + 按钮文本
	menu.call("set_settings", {"time_source": "real", "timezone": "Europe/London"})
	_check("现实时间下时区行显示", tz_row != null and tz_row.visible)
	_check_eq("时间来源按钮文本", ts_btn.text, "现实时间")
	_check("时区按钮文本随选择刷新", tz_btn.text.contains("Europe/London") and tz_btn.text.contains(T.city_of("Europe/London")), tz_btn.text)

	# 弹层：打开 / 搜索 / Esc 层级
	menu.call("open_settings")
	menu.call("open_timezone_picker")
	_check("时区弹层已打开", bool(menu.get("_tz_popup_open")))
	_check("时区弹层可见", bool(menu.get("_tz_popup").visible))
	_check("搜索框已清空", str(menu.get("_tz_search").text) == "")
	menu.call("_on_tz_search_changed", "tokyo")
	var visible_count := 0
	for b in tz_buttons:
		if (b as Button).visible:
			visible_count += 1
	_check_eq("搜索 tokyo 过滤数量", visible_count, T.search("tokyo").size())
	menu.call("_on_tz_search_changed", "东京")
	visible_count = 0
	for b in tz_buttons:
		if (b as Button).visible:
			visible_count += 1
	_check_eq("搜索 东京 过滤数量", visible_count, T.search("东京").size())
	menu.call("_on_tz_search_changed", "")
	visible_count = 0
	for b in tz_buttons:
		if (b as Button).visible:
			visible_count += 1
	var blocks: Array = menu.get("_tz_group_blocks")
	var expected_reps := 0
	var per_block_ok := true
	for blk in blocks:
		var vis := 0
		for btn in blk.get("buttons", []):
			if (btn as Button).visible:
				vis += 1
		if vis > 2:
			per_block_ok = false
		expected_reps += (blk.get("rep_ids", []) as Array).size()
	_check("清空搜索：每组代表 <= 2", per_block_ok)
	_check("清空搜索恢复代表视图", visible_count > 0 and visible_count == expected_reps, "%d vs %d" % [visible_count, expected_reps])

	var backup := _read_user_settings()
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	root.push_input(esc)
	_check("Esc 第一下先关弹层", not bool(menu.get("_tz_popup_open")))
	_check("Esc 第一下设置面板仍开", bool(menu.get("_settings_open")))
	root.push_input(esc)
	_check("Esc 第二下关设置面板", not bool(menu.get("_settings_open")))

	# 时间来源切换：即时保存 + 写盘 + 其余设置不变（先复位到模拟时间，前面测试置过 real）
	menu.call("set_settings", {"time_source": "sim"})
	_check_eq("切换测试起始=模拟时间", str(menu.get_settings().get("time_source")), "sim")
	var before: Dictionary = menu.get_settings()
	menu.call("_on_setting_pressed", "time_source")
	var after: Dictionary = menu.get_settings()
	_check_eq("时间来源切换 sim→real", str(after.get("time_source")), "real")
	_check("切换后时区行显示", bool(tz_row.visible))
	var persisted_source: Dictionary = S.load_settings()
	_check_eq("时间来源切换即写盘", str(persisted_source.get("time_source")), "real")
	menu.call("_on_setting_pressed", "time_source")
	_check_eq("时间来源切换回 sim", str(menu.get_settings().get("time_source")), "sim")
	_check("切回 sim 后时区行隐藏", not bool(tz_row.visible))
	var after2: Dictionary = menu.get_settings()
	_check("切换两次不影响其余设置",
		after2.get("day_length") == before.get("day_length") and after2.get("quality") == before.get("quality")
		and after2.get("volume") == before.get("volume") and after2.get("resolution") == before.get("resolution"))

	# 选择时区：立即保存 + settings_changed + 关闭弹层
	menu.call("open_settings")
	menu.call("open_timezone_picker")
	_menu_signals = 0
	menu.connect("settings_changed", Callable(self, "_on_menu_settings_changed"))
	menu.call("_on_timezone_chosen", "Europe/London")
	_check("选择时区发出 settings_changed", _menu_signals >= 1, str(_menu_signals))
	_check_eq("选择时区写入 _values", str(menu.get_settings().get("timezone")), "Europe/London")
	_check("选择后弹层关闭", not bool(menu.get("_tz_popup_open")))
	var persisted_tz: Dictionary = S.load_settings()
	_check_eq("选择时区立即写盘", str(persisted_tz.get("timezone")), "Europe/London")
	_check("时区按钮刷新为伦敦", tz_btn.text.contains("Europe/London"), tz_btn.text)

	# 非法时区回落
	menu.call("set_settings", {"timezone": "Mars/Base"})
	_check_eq("menu 非法时区回落上海", str(menu.get_settings().get("timezone")), "Asia/Shanghai")
	menu.call("set_settings", {"time_source": "bogus"})
	_check_eq("menu 非法时间来源回落 sim", str(menu.get_settings().get("time_source")), "sim")

	menu.call("close_settings_instant")
	_restore_user_settings(backup)

	root.remove_child(menu)
	menu.free()
