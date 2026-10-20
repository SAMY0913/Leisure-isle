extends SceneTree
## 第五阶段 · 时间 UI 探针（headless 单元断言 + 可选 --ui 窗口截图/集成断言）
## 运行：
##   Godot_console.exe --headless --path D:/休闲小岛幻境/游戏工程 --script res://tools/probe_time_p5.gd
##   Godot_console.exe --path D:/休闲小岛幻境/游戏工程 --script res://tools/probe_time_p5.gd -- --ui
## 覆盖：isle_time 新 API（rule_signature / zone_groups / zone_option_label / dst / special）、
##       分组契约（≤2 代表、同组签名一致、上海+香港/东京+首尔同组、特殊规则代表存在）、
##       固定时刻偏移真值、HUD 时间来源行、菜单分组选择器、时间模式往返。
## 结果写入 logs/probe_time_p5.log；FAIL 时退出码 1。

const T := preload("res://scripts/isle_time.gd")
const TZD := preload("res://scripts/isle_tz_data.gd")
const HUD_SCRIPT := preload("res://scripts/hud.gd")
const MENU_SCRIPT := preload("res://scripts/menu.gd")

## 2026-01-15T12:00:00Z / 2026-07-15T12:00:00Z（Python zoneinfo 真值见下）
const I1 := 1768478400
const I2 := 1784116800
const LOG_PATH := "D:/休闲小岛幻境/开发产物/logs/probe_time_p5.log"

var _passes := 0
var _fails: Array[String] = []
var _group := "?"
var _log: FileAccess = null
var _ui_mode := false
var _ui_finished := false
var _hud_sets := 0
var _hud_adjusts := 0
var _hud_modes: Array[String] = []
var _menu_signals := 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if str(arg) == "--ui":
			_ui_mode = true
	DirAccess.make_dir_recursive_absolute("D:/休闲小岛幻境/开发产物/logs")
	# 追加写入：同一次交付里 unit 与 --ui 两次运行都保留在同一日志中，便于复核。
	var had_log := FileAccess.file_exists(LOG_PATH)
	_log = FileAccess.open(LOG_PATH, FileAccess.READ_WRITE) if had_log else FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if _log != null and had_log:
		_log.seek_end()
		_log.store_string("\n")
	_log_line("==== P5 TIME-UI PROBE ====")
	_log_line("mode=" + ("ui" if _ui_mode else "unit") + " argv=" + str(OS.get_cmdline_user_args()))
	await process_frame
	if _ui_mode:
		await _run_ui_mode()
		_check("UI 模式完整跑完", _ui_finished)
	else:
		_run_unit_mode()
	_print_summary()

func _run_unit_mode() -> void:
	_group = "zones_data"
	_test_zones_data()
	_group = "temp_offsets"
	_test_offsets()
	_group = "temp_dst"
	_test_dst()
	_group = "special_rule"
	_test_special()
	_group = "option_label"
	_test_option_label()
	_group = "signature"
	_test_signature()
	_group = "groups"
	_test_groups()
	_group = "regression"
	_test_old_api()

# ---------------------------------------------------------------- 日志 / 断言

func _log_line(line: String) -> void:
	print(line)
	if _log != null:
		_log.store_line(line)

func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_passes += 1
		return
	var msg := "[" + _group + "] " + name
	if not detail.is_empty():
		msg += "  (" + detail + ")"
	_fails.append(msg)
	_log_line("  FAIL  " + msg)

func _check_eq(name: String, got: Variant, want: Variant) -> void:
	var ok: bool = got == want
	_check(name, ok, "" if ok else "got=" + str(got) + " want=" + str(want))

func _check_near(name: String, got: float, want: float) -> void:
	_check(name, absf(got - want) < 0.5, "got=" + str(got) + " want=" + str(want))

func _print_build_ms(build_ms: float, refresh_ms: float) -> void:
	_log_line("  tz list build: %.1f ms, reopen refresh: %.1f ms" % [build_ms, refresh_ms])

func _print_summary() -> void:
	_log_line("")
	_log_line("==== P5 TIME-UI PROBE SUMMARY ====")
	_log_line("PASS: %d   FAIL: %d" % [_passes, _fails.size()])
	for f in _fails:
		_log_line("  FAILED: " + f)
	_log_line("RESULT: " + ("ALL PASS" if _fails.is_empty() else "%d FAILURE(S)" % _fails.size()))
	if _log != null:
		_log.flush()
		_log.close()
		_log = null
	quit(0 if _fails.is_empty() else 1)

# ---------------------------------------------------------------- 数据表

func _test_zones_data() -> void:
	var zones: Array = T.zones()
	var order: Array = TZD.ZONE_ORDER
	_check("zones() 数量 = ZONE_ORDER 数量", zones.size() == order.size(), "zones=%d order=%d" % [zones.size(), order.size()])
	_check("时区数量 >= 134", zones.size() >= 134, "size=" + str(zones.size()))
	_check_eq("ZONE_TRANS 数量 = ZONE_ORDER 数量", TZD.ZONE_TRANS.size(), order.size())
	_check_eq("ZONE_CITIES 数量 = ZONE_ORDER 数量", TZD.ZONE_CITIES.size(), order.size())
	_check_eq("ZONE_CITIES_EN 数量 = ZONE_ORDER 数量", TZD.ZONE_CITIES_EN.size(), order.size())
	var uniq := {}
	var missing := []
	for z in zones:
		var key := str(z)
		if uniq.has(key):
			missing.append("dup:" + key)
		uniq[key] = true
		if not TZD.ZONE_TRANS.has(key):
			missing.append("no_trans:" + key)
		if not TZD.ZONE_CITIES.has(key):
			missing.append("no_cn:" + key)
		if not TZD.ZONE_CITIES_EN.has(key):
			missing.append("no_en:" + key)
	_check("时区 id 唯一且表项齐全", missing.is_empty(), str(missing.slice(0, 6)))
	for z in ["Australia/Eucla", "Pacific/Marquesas", "Pacific/Kiritimati", "America/Nuuk"]:
		_check("新时区存在 " + z, uniq.has(z))
	_check_eq("上海英文名", T.city_en_of("Asia/Shanghai"), "Shanghai")
	_check_eq("纽约英文名", T.city_en_of("America/New_York"), "New York")
	_check_eq("圣约翰斯英文名", T.city_en_of("America/St_Johns"), "St. John's")
	_check_eq("加德满都中英双名", T.city_bilingual("Asia/Kathmandu"), "加德满都 Kathmandu")
	_check_eq("非法时区英文名回落默认", T.city_en_of("Mars/Base"), "Shanghai")

# ---------------------------------------------------------------- 固定时刻偏移真值

func _test_offsets() -> void:
	var cases := [
		["Asia/Shanghai", 28800, 28800],
		["Asia/Hong_Kong", 28800, 28800],
		["Asia/Tokyo", 32400, 32400],
		["Asia/Seoul", 32400, 32400],
		["Asia/Kolkata", 19800, 19800],
		["Asia/Kathmandu", 20700, 20700],
		["Australia/Eucla", 31500, 31500],
		["Pacific/Marquesas", -34200, -34200],
		["Pacific/Kiritimati", 50400, 50400],
		["America/Nuuk", -7200, -3600],
		["America/New_York", -18000, -14400],
		["Europe/London", 0, 3600],
		["Europe/Paris", 3600, 7200],
		["Australia/Sydney", 39600, 36000],
		["America/Santiago", -10800, -14400],
		["Africa/Casablanca", 3600, 3600],
		["Asia/Tehran", 12600, 12600],
		["Asia/Almaty", 18000, 18000],
		["Asia/Istanbul", 10800, 10800],
		["America/Sao_Paulo", -10800, -10800],
		["America/Mexico_City", -21600, -21600],
		["America/Vancouver", -28800, -25200],
		["Africa/Cairo", 7200, 10800],
		["Africa/Windhoek", 7200, 7200],
		["America/Havana", -18000, -14400],
		["America/Asuncion", -10800, -10800],
		["Europe/Dublin", 0, 3600],
		["Atlantic/Reykjavik", 0, 0],
		["Asia/Colombo", 19800, 19800],
		["Pacific/Auckland", 46800, 43200],
		["Pacific/Chatham", 49500, 45900],
	]
	for c in cases:
		var zone := str(c[0])
		_check_eq("偏移 %s @2026-01-15" % zone, T.offset_at(zone, float(I1)), int(c[1]))
		_check_eq("偏移 %s @2026-07-15" % zone, T.offset_at(zone, float(I2)), int(c[2]))
		_check_eq("effective_offset %s" % zone, T.effective_offset(zone, float(I1)), int(c[1]))
	# 24 小时制墙上时间（12:00Z → 上海 20 点 / 东京 21 点 / 纽约 07 点 / 伦敦 12 点）
	_check_eq("上海墙上时间 24h", int(T.local_datetime("Asia/Shanghai", float(I1)).get("hour", -1)), 20)
	_check_eq("东京墙上时间 24h", int(T.local_datetime("Asia/Tokyo", float(I1)).get("hour", -1)), 21)
	_check_eq("纽约墙上时间 24h", int(T.local_datetime("America/New_York", float(I1)).get("hour", -1)), 7)
	_check_eq("伦敦墙上时间 24h", int(T.local_datetime("Europe/London", float(I1)).get("hour", -1)), 12)
	for zone in ["Asia/Kolkata", "Asia/Kathmandu", "Australia/Eucla", "Pacific/Marquesas"]:
		var h := int(T.local_datetime(zone, float(I1)).get("hour", -1))
		_check("非整时区 %s 的 24h 小时合法" % zone, h >= 0 and h < 24, "hour=" + str(h))

# ---------------------------------------------------------------- DST 状态

func _test_dst() -> void:
	var cases := [
		["America/New_York", false, true],
		["Europe/London", false, true],
		["Australia/Sydney", true, false],
		["America/Santiago", true, false],
		["America/Nuuk", false, true],
		["America/Havana", false, true],
		["Asia/Shanghai", false, false],
		["Asia/Tokyo", false, false],
		["Asia/Kolkata", false, false],
		["Asia/Kathmandu", false, false],
		["Australia/Eucla", false, false],
		["Pacific/Marquesas", false, false],
		["Pacific/Kiritimati", false, false],
		["Africa/Casablanca", false, false],
		["America/Sao_Paulo", false, false],
	]
	for c in cases:
		var zone := str(c[0])
		_check_eq("DST %s @2026-01-15" % zone, T.dst_active(zone, float(I1)), bool(c[1]))
		_check_eq("DST %s @2026-07-15" % zone, T.dst_active(zone, float(I2)), bool(c[2]))
	# 默认参数（当前时刻）与显式 now 一致
	_check_eq("dst_active 默认参数 = 当前时刻", T.dst_active("Asia/Shanghai"), T.dst_active("Asia/Shanghai", T.now_unix()))

# ---------------------------------------------------------------- 特殊规则判定

func _test_special() -> void:
	var normal_cases := ["Asia/Shanghai", "Asia/Hong_Kong", "Asia/Tokyo", "Asia/Seoul", "Australia/Perth", "Pacific/Kiritimati", "Asia/Istanbul", "Atlantic/Reykjavik", "UTC"]
	for zone in normal_cases:
		_check("普通规则 " + zone, not T.is_special_rule(zone, float(I2)))
	var special_cases := ["America/New_York", "Europe/London", "Australia/Sydney", "America/Santiago", "Asia/Kolkata", "Asia/Kathmandu", "Australia/Eucla", "Pacific/Marquesas", "America/Nuuk", "Africa/Casablanca", "Asia/Tehran", "Asia/Almaty", "America/Sao_Paulo", "America/Vancouver"]
	for zone in special_cases:
		_check("特殊规则 " + zone, T.is_special_rule(zone, float(I2)))
	# 特殊原因可读：非整时区 / 法规变更 / DST
	var groups: Array = T.zone_groups(float(I2))
	var reason_of := {}
	for g in groups:
		for e in g.get("entries", []):
			reason_of[str(e.get("id", ""))] = str(g.get("reason", ""))
	_check("Eucla 特殊原因含非整时", str(reason_of.get("Australia/Eucla", "")).contains("非整时偏移"), str(reason_of.get("Australia/Eucla", "")))
	_check("加德满都特殊原因含非整时", str(reason_of.get("Asia/Kathmandu", "")).contains("非整时偏移"), str(reason_of.get("Asia/Kathmandu", "")))
	_check("纽约特殊原因含夏令时", str(reason_of.get("America/New_York", "")).contains("夏令时"), str(reason_of.get("America/New_York", "")))
	_check("努克特殊原因含法规变更", str(reason_of.get("America/Nuuk", "")).contains("规则变更"), str(reason_of.get("America/Nuuk", "")))
	_check("德黑兰特殊原因含法规变更", str(reason_of.get("Asia/Tehran", "")).contains("规则变更"), str(reason_of.get("Asia/Tehran", "")))

# ---------------------------------------------------------------- 选项标签 / 偏移文本

func _test_option_label() -> void:
	_check_eq("format_offset +8h", T.format_offset(28800), "UTC+08:00")
	_check_eq("format_offset -4h", T.format_offset(-14400), "UTC-04:00")
	_check_eq("format_offset +5:30", T.format_offset(19800), "UTC+05:30")
	_check_eq("format_offset +5:45", T.format_offset(20700), "UTC+05:45")
	_check_eq("format_offset +8:45", T.format_offset(31500), "UTC+08:45")
	_check_eq("format_offset -9:30", T.format_offset(-34200), "UTC-09:30")
	_check_eq("format_offset +14h", T.format_offset(50400), "UTC+14:00")
	_check_eq("format_offset 0", T.format_offset(0), "UTC+00:00")
	_check_eq("上海选项标签(冬)", T.zone_option_label("Asia/Shanghai", float(I1)), "上海 Shanghai · UTC+08:00")
	_check_eq("纽约选项标签(冬)", T.zone_option_label("America/New_York", float(I1)), "纽约 New York · UTC-05:00")
	_check_eq("纽约选项标签(夏,带 DST)", T.zone_option_label("America/New_York", float(I2)), "纽约 New York · UTC-04:00 · 夏令时")
	_check_eq("伦敦选项标签(夏,带 DST)", T.zone_option_label("Europe/London", float(I2)), "伦敦 London · UTC+01:00 · 夏令时")
	_check_eq("加德满都选项标签", T.zone_option_label("Asia/Kathmandu", float(I2)), "加德满都 Kathmandu · UTC+05:45")
	_check_eq("尤克拉选项标签", T.zone_option_label("Australia/Eucla", float(I2)), "尤克拉 Eucla · UTC+08:45")
	_check_eq("马克萨斯选项标签", T.zone_option_label("Pacific/Marquesas", float(I2)), "马克萨斯群岛 Marquesas · UTC-09:30")
	_check_eq("基里蒂马蒂选项标签", T.zone_option_label("Pacific/Kiritimati", float(I2)), "基里蒂马蒂 Kiritimati · UTC+14:00")
	_check_eq("悉尼选项标签(夏,南半球)", T.zone_option_label("Australia/Sydney", float(I1)), "悉尼 Sydney · UTC+11:00 · 夏令时")
	_check_eq("悉尼选项标签(冬)", T.zone_option_label("Australia/Sydney", float(I2)), "悉尼 Sydney · UTC+10:00")

# ---------------------------------------------------------------- 规则签名

func _test_signature() -> void:
	var s1 := T.rule_signature("Asia/Shanghai", float(I2), 3.0)
	var s2 := T.rule_signature("Asia/Shanghai", float(I2), 3.0)
	_check("签名确定性", s1 == s2, s1 + " vs " + s2)
	_check("签名非空且为 sha256", s1.length() == 64, "len=" + str(s1.length()))
	_check_eq("上海 1 年签名 = 5 年签名（无规则变化）", T.rule_signature("Asia/Shanghai", float(I2), 1.0), T.rule_signature("Asia/Shanghai", float(I2), 5.0))
	_check("纽约 1 年签名 != 3 年签名（DST 转换次数不同）", T.rule_signature("America/New_York", float(I2), 1.0) != T.rule_signature("America/New_York", float(I2), 3.0))
	_check_eq("东京/首尔签名一致", T.rule_signature("Asia/Tokyo", float(I2), 3.0), T.rule_signature("Asia/Seoul", float(I2), 3.0))
	_check_eq("上海/香港签名一致", T.rule_signature("Asia/Shanghai", float(I2), 3.0), T.rule_signature("Asia/Hong_Kong", float(I2), 3.0))
	_check_eq("zone_group_key = 近10年+未来3年签名", T.zone_group_key("America/New_York", float(I2)),
		T.rule_signature("America/New_York", float(I2) - 10.0 * T.AVG_YEAR, 13.0))
	_check("纽约/圣地亚哥规则键不同（DST 起止不同）",
		T.zone_group_key("America/New_York", float(I2)) != T.zone_group_key("America/Santiago", float(I2)))

# ---------------------------------------------------------------- 分组契约

func _group_with_entry(groups: Array, zone: String) -> Dictionary:
	for g in groups:
		for e in g.get("entries", []):
			if str(e.get("id", "")) == zone:
				return g
	return {}

func _entry_ids(g: Dictionary) -> Array:
	var ids := []
	for e in g.get("entries", []):
		ids.append(str(e.get("id", "")))
	return ids

func _test_groups() -> void:
	var ts := float(I2)
	var groups: Array = T.zone_groups(ts)
	_check("分组数量 >= 55", groups.size() >= 55, "n=" + str(groups.size()))
	var normal_groups := 0
	var special_groups := 0
	var keys := {}
	var zone_hits := {}
	var rep_hits := {}
	var bad := []
	for g in groups:
		var kind := str(g.get("kind", ""))
		_check("组 kind 合法", kind == "normal" or kind == "special", kind)
		if kind == "normal":
			normal_groups += 1
		else:
			special_groups += 1
		var sig := str(g.get("rule_key", ""))
		_check("rule_key 非空", not sig.is_empty())
		if keys.has(sig):
			bad.append("dup rule_key " + sig)
		keys[sig] = true
		for f in ["kind", "rule_key", "title", "dst", "entries", "members"]:
			_check("组含字段 " + f, g.has(f), sig)
		var entries: Array = g.get("entries", [])
		var members: Array = g.get("members", [])
		_check("每组代表 1..2 个", entries.size() >= 1 and entries.size() <= T.MAX_REPS, "n=%d %s" % [entries.size(), sig])
		_check("members 非空", members.size() > 0, sig)
		if kind == "normal":
			_check("普通组标题含 标准时区", str(g.get("title", "")).contains("标准时区"), str(g.get("title", "")))
		else:
			_check("特殊组 reason 非空", not str(g.get("reason", "")).is_empty(), str(g.get("title", "")))
			_check("特殊组标题含原因", str(g.get("title", "")).contains(str(g.get("reason", ""))), str(g.get("title", "")))
		for e in entries:
			var eid := str(e.get("id", ""))
			_check("代表在 members 内 " + eid, members.has(eid))
			_check("代表不跨组重复 " + eid, not rep_hits.has(eid), eid)
			rep_hits[eid] = true
			_check_eq("代表 label " + eid, str(e.get("label", "")), T.zone_option_label(eid, ts))
			_check_eq("代表 offset_text " + eid, str(e.get("offset_text", "")), T.format_offset(int(e.get("offset_sec", 0))))
			_check_eq("代表 offset_sec " + eid, int(e.get("offset_sec", 0)), T.effective_offset(eid, ts))
			_check_eq("代表 dst_now " + eid, bool(e.get("dst_now", false)), T.dst_active(eid, ts))
			_check_eq("代表 is_dst " + eid, bool(e.get("is_dst", false)), bool(e.get("dst_now", false)))
			_check_eq("同组签名一致(10y) " + eid, T.rule_signature(eid, ts - 10.0 * T.AVG_YEAR, 13.0), sig)
			var first_id := str(entries[0].get("id", ""))
			_check_eq("同组签名一致(3y) " + eid, T.rule_signature(eid, ts, 3.0), T.rule_signature(first_id, ts, 3.0))
			_check_eq("special 判定与组 kind 一致 " + eid, T.is_special_rule(eid, ts), kind == "special")
			if kind == "normal":
				var off := T.offset_at(eid, ts)
				_check("普通组偏移整小时 " + eid, off % 3600 == 0, str(off))
				var constant := true
				for k in range(-3, 4):
					if T.offset_at(eid, ts + float(k) * 0.5 * T.AVG_YEAR) != off:
						constant = false
				_check("普通组 3 年内偏移不变 " + eid, constant, str(off))
		for m in members:
			var mkey := str(m)
			zone_hits[mkey] = int(zone_hits.get(mkey, 0)) + 1
	_check("rule_key 唯一", bad.is_empty(), str(bad.slice(0, 4)))
	_check("normal 组 >= 10", normal_groups >= 10, "n=" + str(normal_groups))
	_check("special 组 >= 20", special_groups >= 20, "n=" + str(special_groups))
	var missing := []
	var dup := []
	for z in T.zones():
		var hit := int(zone_hits.get(str(z), 0))
		if hit == 0:
			missing.append(str(z))
		elif hit > 1:
			dup.append(str(z))
	_check("全部时区归入且仅归入一组", missing.is_empty() and dup.is_empty(), "missing=%s dup=%s" % [str(missing.slice(0, 5)), str(dup.slice(0, 5))])
	# 契约硬要求：UTC+08:00 普通组只有上海+香港代表
	var g8 := _group_with_entry(groups, "Asia/Shanghai")
	_check("上海组存在", not g8.is_empty())
	_check_eq("上海组 kind", str(g8.get("kind", "")), "normal")
	var ids8 := _entry_ids(g8)
	_check_eq("UTC+8 组代表 = 上海+香港", str(ids8), str(["Asia/Shanghai", "Asia/Hong_Kong"]))
	_check("UTC+8 组代表不含台北", not ids8.has("Asia/Taipei"), str(ids8))
	# 东京 / 首尔同组（UTC+9 普通组）
	var g9 := _group_with_entry(groups, "Asia/Tokyo")
	_check("东京组存在", not g9.is_empty())
	var ids9 := _entry_ids(g9)
	_check("东京/首尔同组", ids9.has("Asia/Tokyo") and ids9.has("Asia/Seoul"), str(ids9))
	_check_eq("东京组 kind", str(g9.get("kind", "")), "normal")
	# 特殊规则代表必须存在且位于 special 组
	for zone in ["America/New_York", "Europe/London", "Australia/Sydney", "America/Santiago", "Asia/Kolkata", "Asia/Kathmandu", "Australia/Eucla", "Pacific/Marquesas", "America/Nuuk"]:
		var g := _group_with_entry(groups, zone)
		_check("特殊代表存在 " + zone, not g.is_empty())
		_check_eq("特殊代表所在组 kind " + zone, str(g.get("kind", "")), "special")
	# Kiritimati（UTC+14 无 DST）应在普通组且可见
	var gk := _group_with_entry(groups, "Pacific/Kiritimati")
	_check("基里蒂马蒂组存在", not gk.is_empty())
	_check_eq("基里蒂马蒂组 kind", str(gk.get("kind", "")), "normal")
	_check_eq("基里蒂马蒂组 label", str(gk.get("entries", [{}])[0].get("label", "")), "基里蒂马蒂 Kiritimati · UTC+14:00")
	# 纽约 / 圣地亚哥：DST 起止不同 → 不同规则组
	var gny := _group_with_entry(groups, "America/New_York")
	var gsc := _group_with_entry(groups, "America/Santiago")
	_check("纽约 与 圣地亚哥 规则键不同", str(gny.get("rule_key", "")) != str(gsc.get("rule_key", "")), "same=" + str(gny.get("rule_key", "")))
	# 特殊组里必须能看出“为何特殊”
	var reasons := {}
	for g in groups:
		if str(g.get("kind", "")) == "special":
			reasons[str(g.get("reason", ""))] = true
	_check("特殊原因含非整时偏移", reasons.has("非整时偏移"), str(reasons.keys()))
	var has_dst_reason := false
	var has_law_reason := false
	for r in reasons.keys():
		if str(r).contains("夏令时"):
			has_dst_reason = true
		if str(r).contains("规则变更"):
			has_law_reason = true
	_check("特殊原因含夏令时", has_dst_reason, str(reasons.keys()))
	_check("特殊原因含法规变更", has_law_reason, str(reasons.keys()))
	_log_line("  groups total=%d normal=%d special=%d" % [groups.size(), normal_groups, special_groups])

# ---------------------------------------------------------------- 旧 API 回归

func _test_old_api() -> void:
	var ts := float(I2)
	var info: Dictionary = T.info("Asia/Shanghai", ts)
	_check_eq("info.id", str(info.get("id", "")), "Asia/Shanghai")
	_check_eq("info.city", str(info.get("city", "")), "上海")
	_check_eq("info.offset_now", int(info.get("offset_now", 0)), 28800)
	_check_eq("info.label 旧格式", str(info.get("label", "")), "上海 · Asia/Shanghai · UTC+08:00")
	_check_eq("zone_label", T.zone_label("Europe/London", ts), "Europe/London · UTC+01:00")
	_check_eq("offset_label", T.offset_label("Asia/Kathmandu", ts), "UTC+05:45")
	_check_eq("city_of", T.city_of("America/New_York"), "纽约")
	_check_eq("default_zone", T.default_zone(), "Asia/Shanghai")
	_check("has_zone 上海", T.has_zone("Asia/Shanghai"))
	_check("has_zone 不存在", not T.has_zone("Mars/Base"))
	_check_eq("resolve_zone 空白/大小写", T.resolve_zone("  asia/shanghai "), "Asia/Shanghai")
	_check_eq("resolve_zone 大小写", T.resolve_zone("ASIA/TOKYO"), "Asia/Tokyo")
	_check_eq("resolve_zone 非法回落默认", T.resolve_zone("Mars/Base"), "Asia/Shanghai")
	_check_eq("search tokyo 数量", T.search("tokyo").size(), 1)
	_check_eq("search tokyo id", str(T.search("tokyo")[0].get("id", "")), "Asia/Tokyo")
	_check_eq("search 东京 数量", T.search("东京").size(), 1)
	_check_eq("search new york 数量", T.search("new york").size(), 1)
	_check_eq("search new york id", str(T.search("new york")[0].get("id", "")), "America/New_York")
	_check_eq("search 空 = 全部", T.search("").size(), T.zones().size())
	_check_eq("search 无结果", T.search("zzz-not-a-zone").size(), 0)
	_check_eq("sanitize_source real", T.sanitize_source("real"), "real")
	_check_eq("sanitize_source 空串", T.sanitize_source(""), "sim")
	_check_eq("sanitize_source 非法", T.sanitize_source("xxx"), "sim")
	_check_eq("source_label real", T.source_label("real"), "现实时间")
	_check_eq("source_label sim", T.source_label("sim"), "模拟时间")
	var dt: Dictionary = T.local_datetime("Asia/Tokyo", ts)
	for k in ["year", "month", "day", "hour", "minute", "second", "weekday", "offset", "unix", "local_unix", "id"]:
		_check("local_datetime 含字段 " + k, dt.has(k))
	_check_eq("local_datetime 东京小时", int(dt.get("hour", -1)), 21)
	_check("now_unix 合理", T.now_unix() > 1700000000.0, str(T.now_unix()))

# ---------------------------------------------------------------- UI 模式（窗口运行）

const UI_SHOT_DIR := "res://shots"

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := "%s/p5_ui_%s.png" % [UI_SHOT_DIR, name]
	var err := img.save_png(path)
	_log_line("  shot " + path + " err=" + str(err))

func _visible_zone_buttons(menu: Node) -> Array:
	var out := []
	for b in menu.get("_tz_buttons"):
		if (b as Button).visible:
			out.append(b)
	return out

func _zone_of_button(b: Button) -> String:
	return str(b.get_meta("zone", ""))

func _button_for_zone(menu: Node, zone: String) -> Button:
	for b in menu.get("_tz_buttons"):
		if _zone_of_button(b as Button) == zone:
			return b as Button
	return null

# 把包含指定时区的分组滚到滚动视口顶部（top_margin 为组头距视口顶的留白）
func _scroll_zone_into_view(menu: Node, zone: String, top_margin: int = 44) -> bool:
	var scroll: ScrollContainer = menu.get("_tz_scroll")
	var blocks: Array = menu.get("_tz_group_blocks")
	if scroll == null:
		return false
	var header: Control = null
	for b in blocks:
		for btn in b.get("buttons", []):
			if _zone_of_button(btn as Button) == zone:
				header = b.get("header") as Control
				break
		if header != null:
			break
	if header == null:
		return false
	var rel := header.get_global_rect().position.y - scroll.get_global_rect().position.y + float(scroll.scroll_vertical) - float(top_margin)
	scroll.scroll_vertical = int(maxf(0.0, rel))
	return true

func _find_block_containing(blocks: Array, zone: String) -> Dictionary:
	for b in blocks:
		for btn in b.get("buttons", []):
			if str((btn as Button).get_meta("zone", "")) == zone:
				return b
	return {}

func _run_ui_mode() -> void:
	_group = "ui"
	DirAccess.make_dir_recursive_absolute(UI_SHOT_DIR)
	_log_line("  display=" + DisplayServer.get_name())
	root.size = Vector2i(1280, 800)
	change_scene_to_file("res://isle.tscn")
	for i in range(12):
		await process_frame
	var main: Node = current_scene
	_check("主场景 isle.tscn 已加载", main != null and main.scene_file_path.ends_with("isle.tscn"), "" if main == null else str(main.scene_file_path))
	if main == null:
		return
	var hud: Node = main.get("_hud")
	var menu: Node = main.get("_menu")
	_check("main._hud 存在", hud != null)
	_check("main._menu 存在", menu != null)
	if hud == null or menu == null:
		return
	await create_timer(0.6).timeout
	await _shot("menu_title")

	# 进入游戏，让 HUD 可见
	menu.start_pressed.emit(false)
	await create_timer(2.4).timeout
	_check("进入游戏后 HUD 可见", bool(hud.get("_visible_now")), str(hud.get("_visible_now")))
	if not bool(hud.get("_visible_now")):
		hud.call("set_hud_visible", true, false)
		await create_timer(0.3).timeout

	# --- HUD 时间来源行 ---
	_check("HUD 有 time_mode_requested 信号", hud.has_signal("time_mode_requested"))
	var mb: Dictionary = hud.get("_time_mode_buttons")
	_check("HUD 两枚来源按钮", mb.size() == 2, str(mb.keys()))
	_check("HUD 按钮 real/sim 齐全", mb.has("real") and mb.has("sim"))
	if not (mb.has("real") and mb.has("sim")):
		return
	hud.call("toggle_time_panel")
	await create_timer(0.5).timeout
	_check("HUD 时间面板已打开", bool(hud.get("_time_open")))
	# 切到现实时间
	(mb["real"] as Button).pressed.emit()
	await create_timer(0.5).timeout
	_check_eq("HUD 按现实时间后 main._time_source", str(main.get("_time_source")), "real")
	_check_eq("HUD 按现实时间后 menu 设置同步", str(menu.get_settings().get("time_source", "")), "real")
	_check_eq("HUD 高亮源 real", str(hud.get("_time_mode_ui")), "real")
	_check_eq("HUD real 按钮高亮色 = ACCENT", (mb["real"] as Button).get_theme_color("font_color"), HUD_SCRIPT.ACCENT)
	_check_eq("HUD sim 按钮非高亮色", (mb["sim"] as Button).get_theme_color("font_color"), HUD_SCRIPT.CREAM)
	_check_eq("菜单 time_source 文本=现实时间", (menu.get("_setting_buttons")["time_source"] as Button).text, "现实时间")
	await _shot("time_panel_real")
	# 现实时间下：设置菜单同步（时间来源 + 时区行可见）
	menu.call("open", false)
	await create_timer(0.7).timeout
	menu.call("open_settings")
	await create_timer(0.7).timeout
	var tz_row_real := menu.get("_tz_row") as HBoxContainer
	_check("现实时间下设置菜单时区行可见", tz_row_real != null and tz_row_real.visible)
	_check_eq("设置菜单时间来源=现实时间", (menu.get("_setting_buttons")["time_source"] as Button).text, "现实时间")
	await _shot("settings_real_timezone_row")
	menu.call("close_settings")
	await create_timer(0.3).timeout
	menu.call("close")
	# close() 内部 await 约 1.5s 才把 CanvasLayer 隐藏；必须等它完成，否则会晚于下面的 open() 把菜单重新隐藏。
	await create_timer(2.0).timeout
	# 切回模拟时间
	(mb["sim"] as Button).pressed.emit()
	await create_timer(0.5).timeout
	_check_eq("HUD 按模拟时间后 main._time_source", str(main.get("_time_source")), "sim")
	_check_eq("HUD 按模拟时间后 menu 设置同步", str(menu.get_settings().get("time_source", "")), "sim")
	_check_eq("HUD 高亮源 sim", str(hud.get("_time_mode_ui")), "sim")
	_check_eq("HUD sim 按钮高亮色 = ACCENT", (mb["sim"] as Button).get_theme_color("font_color"), HUD_SCRIPT.ACCENT)
	_check_eq("菜单 time_source 文本=模拟时间", (menu.get("_setting_buttons")["time_source"] as Button).text, "模拟时间")
	await _shot("time_panel_sim")
	hud.call("toggle_time_panel")
	await create_timer(0.3).timeout

	# --- 菜单时区选择器：分组 / 默认代表 / 搜索 ---
	menu.call("open", false)
	await create_timer(0.7).timeout
	menu.call("open_settings")
	await create_timer(0.7).timeout
	var mr := menu.get("_menu_root") as Control
	var sp := menu.get("_settings_panel") as Control
	_check("设置菜单 CanvasLayer 实际可见", bool(menu.visible) and mr != null and mr.visible and sp != null and sp.visible, "menu=%s root=%s panel=%s" % [str(menu.visible), str(mr.visible if mr != null else false), str(sp.visible if sp != null else false)])
	await _shot("settings_open")
	menu.call("open_timezone_picker")
	await create_timer(0.7).timeout
	_check("时区弹层已打开", bool(menu.get("_tz_popup_open")))
	var blocks: Array = menu.get("_tz_group_blocks")
	_check("分组块已构建", blocks.size() > 0, "n=" + str(blocks.size()))
	var ts_now := T.now_unix()
	var groups: Array = T.zone_groups(ts_now)
	var expected_reps := 0
	for g in groups:
		expected_reps += g.get("entries", []).size()
	_check_eq("全表按钮 134 个", menu.get("_tz_buttons").size(), T.zones().size())
	var build_ms := float(menu.get("_tz_last_build_ms"))
	var refresh_ms := float(menu.get("_tz_last_refresh_ms"))
	_check("初次分组列表构建 < 500ms", build_ms < 500.0, "%.1fms" % build_ms)
	_check("再次打开只刷新文本 < 50ms", refresh_ms >= 0.0 and refresh_ms < 50.0, "%.1fms" % refresh_ms)
	_print_build_ms(build_ms, refresh_ms)
	var per_block_ok := true
	var visible_blocks := 0
	var block_normal := 0
	var block_special := 0
	for b in blocks:
		var btns: Array = b.get("buttons", [])
		var vis := 0
		for btn in btns:
			if (btn as Button).visible:
				vis += 1
		if vis > T.MAX_REPS:
			per_block_ok = false
		if vis > 0:
			visible_blocks += 1
		if str(b.get("kind", "")) == "normal":
			block_normal += 1
		else:
			block_special += 1
		var header: Label = b.get("header")
		if header != null:
			_check("组头含 UTC " + header.text, header.text.contains("UTC"), header.text)
	_check("每组默认可见代表 <=2", per_block_ok)
	_check("默认可见代表数 = 各组代表数之和", _visible_zone_buttons(menu).size() == expected_reps, "%d vs %d" % [_visible_zone_buttons(menu).size(), expected_reps])
	_check("分组块数 = 组数", blocks.size() == groups.size(), "%d vs %d" % [blocks.size(), groups.size()])
	_check("normal/special 块都存在", block_normal >= 10 and block_special >= 20, "normal=%d special=%d" % [block_normal, block_special])
	var g8 := _group_with_entry(groups, "Asia/Shanghai")
	var b8 := _find_block_containing(blocks, "Asia/Shanghai")
	_check("上海分组块存在", not b8.is_empty())
	if not b8.is_empty():
		var vis8 := []
		for btn in b8.get("buttons", []):
			if (btn as Button).visible:
				vis8.append(_zone_of_button(btn))
		_check_eq("上海组默认可见 = 上海+香港", str(vis8), str(["Asia/Shanghai", "Asia/Hong_Kong"]))
		var h8: Label = b8.get("header")
		_check("上海组头含 UTC+08:00", h8 != null and h8.text.contains("UTC+08:00"), "" if h8 == null else h8.text)
		_check("上海组头含 标准时区", h8 != null and h8.text.contains("标准时区"), "" if h8 == null else h8.text)
		_check("上海组头含时区数量", h8 != null and h8.text.contains(str(g8.get("members", []).size())), "" if h8 == null else h8.text)
	# 弹层截图（默认代表视图）
	var tp := menu.get("_tz_popup") as Control
	_check("时区弹层实际可见渲染", tp != null and tp.visible and tp.is_visible_in_tree() and tp.modulate.a > 0.9, "vis=%s a=%.2f" % [str(tp.visible if tp != null else false), (tp.modulate.a if tp != null else -1.0)])
	await _shot("timezone_normal")
	# 搜索 tokyo
	menu.call("_on_tz_search_changed", "tokyo")
	await create_timer(0.3).timeout
	var vt := _visible_zone_buttons(menu)
	_check_eq("搜索 tokyo 可见数", vt.size(), 1)
	if vt.size() == 1:
		_check_eq("搜索 tokyo 命中 Asia/Tokyo", _zone_of_button(vt[0]), "Asia/Tokyo")
		_check("搜索 tokyo 按钮文字含实时偏移", (vt[0] as Button).text.contains("UTC+09:00"), (vt[0] as Button).text)
	await _shot("timezone_search_tokyo")
	# 搜索英文城市名 new york
	menu.call("_on_tz_search_changed", "new york")
	await create_timer(0.2).timeout
	var vny := _visible_zone_buttons(menu)
	_check_eq("搜索 new york 可见数", vny.size(), 1)
	if vny.size() == 1:
		_check_eq("搜索 new york 命中 America/New_York", _zone_of_button(vny[0]), "America/New_York")
	# 恢复默认
	menu.call("_on_tz_search_changed", "")
	await create_timer(0.3).timeout
	_check_eq("清空搜索恢复默认代表", _visible_zone_buttons(menu).size(), expected_reps)
	# 特殊组截图（滚动到特殊区域）
	var scroll: ScrollContainer = menu.get("_tz_scroll")
	var special_header: Label = null
	var special_section: Label = null
	for b in blocks:
		if str(b.get("kind", "")) == "special":
			special_header = b.get("header")
			break
	var sections: Dictionary = menu.get("_tz_section_headers")
	if sections.has("special"):
		special_section = sections["special"]
	_check("存在特殊区段标题", special_section != null)
	if special_section != null:
		_check("特殊区段标题文字", special_section.text.contains("特殊"), special_section.text)
	if special_header != null:
		_check("特殊组头含原因关键词", special_header.text.contains("夏令时") or special_header.text.contains("非整时") or special_header.text.contains("规则变更") or special_header.text.contains("偏移"), special_header.text)
	if scroll != null:
		scroll.scroll_vertical = int(maxf(0.0, (special_header as Control).get_global_rect().position.y - (scroll.get_global_rect().position.y) + scroll.scroll_vertical)) if special_header != null else 0
		await create_timer(0.3).timeout
	await _shot("timezone_special")
	# 搜索一个特殊时区
	menu.call("_on_tz_search_changed", "santiago")
	await create_timer(0.3).timeout
	var vs := _visible_zone_buttons(menu)
	_check_eq("搜索 santiago 可见数", vs.size(), 1)
	if vs.size() == 1:
		_check_eq("搜索 santiago 命中 America/Santiago", _zone_of_button(vs[0]), "America/Santiago")
	await _shot("timezone_search_santiago")
	# --- 特写1：UTC+08:00 组（上海 + 香港；无台北/新加坡等重复项）---
	menu.call("_on_tz_search_changed", "")
	await create_timer(0.35).timeout
	_check("滚动到 UTC+8 组", _scroll_zone_into_view(menu, "Asia/Shanghai", 46))
	await create_timer(0.45).timeout
	var b8c := _find_block_containing(menu.get("_tz_group_blocks"), "Asia/Shanghai")
	var vis8c := []
	for btn in b8c.get("buttons", []):
		if (btn as Button).visible:
			vis8c.append(_zone_of_button(btn as Button))
	_check_eq("UTC+8 特写: 同屏代表 = 上海+香港", str(vis8c), str(["Asia/Shanghai", "Asia/Hong_Kong"]))
	var h8c: Label = b8c.get("header")
	_check("UTC+8 特写: 组头含 UTC+08:00", h8c != null and h8c.text.contains("UTC+08:00"), "" if h8c == null else h8c.text)
	_check("UTC+8 特写: 组头含时区数量", h8c != null and h8c.text.contains("个时区"), "" if h8c == null else h8c.text)
	for z in ["Asia/Taipei", "Asia/Singapore", "Asia/Chongqing", "Asia/Macau"]:
		var zb := _button_for_zone(menu, z)
		_check("UTC+8 特写: 不显示重复项 " + z, zb == null or not zb.visible, "exists=%s visible=%s" % [str(zb != null), str(zb != null and zb.visible)])
	await _shot("timezone_utc8_group")
	# --- 特写2：Australia/Eucla（UTC+08:45 非整时）---
	_check("滚动到 Eucla 组", _scroll_zone_into_view(menu, "Australia/Eucla", 46))
	await create_timer(0.45).timeout
	var be := _find_block_containing(menu.get("_tz_group_blocks"), "Australia/Eucla")
	var hbe: Label = be.get("header")
	_check("Eucla 组头含 UTC+08:45", hbe != null and hbe.text.contains("UTC+08:45"), "" if hbe == null else hbe.text)
	_check("Eucla 组头含 非整时", hbe != null and hbe.text.contains("非整时"), "" if hbe == null else hbe.text)
	var ebtn := _button_for_zone(menu, "Australia/Eucla")
	_check("Eucla 按钮文字含 尤克拉/Eucla/UTC+08:45", ebtn != null and ebtn.text.contains("尤克拉") and ebtn.text.contains("Eucla") and ebtn.text.contains("UTC+08:45"), "" if ebtn == null else ebtn.text)
	await _shot("timezone_eucla_nuuk")
	# --- 特写2 相邻屏：America/Nuuk（2024 年起规则变更）---
	_check("滚动到 Nuuk 组", _scroll_zone_into_view(menu, "America/Nuuk", 46))
	await create_timer(0.45).timeout
	var bn := _find_block_containing(menu.get("_tz_group_blocks"), "America/Nuuk")
	var hbn: Label = bn.get("header")
	_check("Nuuk 组头含 2024 年起规则变更", hbn != null and hbn.text.contains("2024") and hbn.text.contains("规则变更"), "" if hbn == null else hbn.text)
	var nbtn := _button_for_zone(menu, "America/Nuuk")
	_check("Nuuk 按钮文字含 努克/Nuuk", nbtn != null and nbtn.text.contains("努克") and nbtn.text.contains("Nuuk"), "" if nbtn == null else nbtn.text)
	await _shot("timezone_eucla_nuuk_b")
	# 菜单 -> main -> HUD 往返：点设置里的 time_source 行
	menu.call("_on_tz_search_changed", "")
	var src_before := str(main.get("_time_source"))
	(menu.get("_setting_buttons")["time_source"] as Button).pressed.emit()
	await create_timer(0.5).timeout
	var src_after := str(main.get("_time_source"))
	_check("设置菜单切换 time_source 生效", src_after != src_before, src_before + " -> " + src_after)
	_check_eq("设置菜单切换后 HUD 状态源同步", str(hud.get("_time_mode_ui")), src_after)
	_check_eq("设置菜单切换后 get_settings 同步", str(menu.get_settings().get("time_source", "")), src_after)
	menu.call("close_timezone_picker")
	await create_timer(0.3).timeout
	menu.call("close_settings")
	await create_timer(0.5).timeout
	await _shot("after_roundtrip")
	_ui_finished = true
