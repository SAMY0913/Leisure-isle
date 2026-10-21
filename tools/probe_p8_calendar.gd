extends SceneTree
## P8 阶段 3：公历日历与季节投影验证 probe。
## 运行：Godot_v4.7.2-stable_win64_console.exe --headless --path D:/休闲小岛幻境/游戏工程 --script res://tools/probe_p8_calendar.gd
## 覆盖：闰年/月长/年内天数、秒数↔日历往返、跨日/跨月/跨年/闰日步进、季节边界与连续权重、
##       权重和恒 1 且非负、年内相位单调、星期/中文标签、非法输入夹取、确定性、性能。
## 退出码：0 = 全部通过；1 = 有失败。

const Cal := preload("res://scripts/isle_calendar.gd")

var _checks: int = 0
var _fails: Array = []

func _init() -> void:
	var t0: int = Time.get_ticks_msec()
	_run_leap_and_month()
	_run_round_trip()
	_run_day_steps()
	_run_season_boundaries()
	_run_season_continuity()
	_run_labels_and_clamp()
	_run_determinism_and_perf()
	print("")
	print("[SUMMARY] checks=%d fail=%d elapsed_ms=%d" % [_checks, _fails.size(), Time.get_ticks_msec() - t0])
	if _fails.is_empty():
		print("PROBE_P8_CALENDAR RESULT: PASS")
		quit(0)
	else:
		for f in _fails:
			print("[FAIL] ", str(f))
		print("PROBE_P8_CALENDAR RESULT: FAIL")
		quit(1)

# ---------------------------------------------------------------- 工具

func _check(cond: bool, name: String, detail: String = "") -> bool:
	_checks += 1
	if not cond:
		_fails.append(name + (("  " + detail) if detail != "" else ""))
	return cond

func _dt(y: int, mo: int, d: int, h: int = 0, mi: int = 0, s: int = 0) -> float:
	return Cal.to_local_seconds(y, mo, d, h, mi, s)

func _near(a: float, b: float, eps: float = 0.000001) -> bool:
	return absf(a - b) <= eps

func _fmt_parts(p: Dictionary) -> String:
	return "%04d-%02d-%02d %02d:%02d:%02d wk%d %s %s w=%s" % [
		p["year"], p["month"], p["day"], p["hour"], p["minute"], p["second"],
		p["weekday"], p["season_label"], p["clock_label"], str(p["season_weights"])]

# ---------------------------------------------------------------- 闰年 / 月长 / 年内天数

func _run_leap_and_month() -> void:
	_check(Cal.is_leap(2024), "leap 2024")
	_check(Cal.is_leap(2000), "leap 2000")
	_check(not Cal.is_leap(1900), "not leap 1900")
	_check(not Cal.is_leap(2100), "not leap 2100")
	_check(not Cal.is_leap(2026), "not leap 2026")
	_check(Cal.days_in_year(2024) == 366, "days_in_year 2024")
	_check(Cal.days_in_year(2026) == 365, "days_in_year 2026")
	_check(Cal.days_in_month(2026, 2) == 28, "feb 2026 = 28")
	_check(Cal.days_in_month(2024, 2) == 29, "feb 2024 = 29")
	for m in range(1, 13):
		_check(Cal.days_in_month(2026, m) == int(Cal.MONTH_DAYS[m - 1]), "month len %d" % m)
	_check(Cal.day_of_year(2026, 1, 1) == 0, "doy jan1 = 0")
	_check(Cal.day_of_year(2026, 3, 1) == 59, "doy 2026-03-01 = 59")
	_check(Cal.day_of_year(2024, 3, 1) == 60, "doy 2024-03-01 = 60")
	_check(Cal.day_of_year(2026, 12, 31) == 364, "doy 2026-12-31 = 364")
	_check(Cal.day_of_year(2024, 12, 31) == 365, "doy 2024-12-31 = 365")

# ---------------------------------------------------------------- 秒数 ↔ 日历往返

func _run_round_trip() -> void:
	var samples := [
		[2026, 10, 22, 17, 18, 0],
		[2024, 2, 29, 0, 0, 0],
		[2025, 12, 31, 23, 59, 59],
		[2026, 3, 1, 0, 0, 0],
		[2026, 12, 31, 23, 59, 59],
		[1970, 1, 1, 0, 0, 0],
		[2099, 12, 31, 12, 0, 0],
		[2000, 2, 29, 6, 30, 15],
	]
	for s in samples:
		var ls: float = _dt(s[0], s[1], s[2], s[3], s[4], s[5])
		var p: Dictionary = Cal.parts(ls)
		var ok: bool = (int(p["year"]) == s[0] and int(p["month"]) == s[1] and int(p["day"]) == s[2]
			and int(p["hour"]) == s[3] and int(p["minute"]) == s[4] and int(p["second"]) == s[5])
		_check(ok, "round trip %04d-%02d-%02d %02d:%02d:%02d" % [s[0], s[1], s[2], s[3], s[4], s[5]], _fmt_parts(p))
		_check(_near(Cal.to_local_seconds(p["year"], p["month"], p["day"], p["hour"], p["minute"], p["second"]), ls),
			"seconds round trip same", _fmt_parts(p))
		_check(_near(float(p["sod"]), float(s[3] * 3600 + s[4] * 60 + s[5])), "sod", _fmt_parts(p))
	# 权威秒数轴与 Time 墙钟一致：parts 的时钟字段应等于直接 unix→dict 的结果。
	var ls2: float = _dt(2026, 10, 22, 17, 18, 0)
	var tdt: Dictionary = Time.get_datetime_dict_from_unix_time(int(ls2))
	var p2: Dictionary = Cal.parts(ls2)
	_check(int(p2["year"]) == int(tdt["year"]) and int(p2["month"]) == int(tdt["month"]) and int(p2["day"]) == int(tdt["day"])
		and int(p2["hour"]) == int(tdt["hour"]) and int(p2["minute"]) == int(tdt["minute"]), "parts vs Time dict", _fmt_parts(p2))

# ---------------------------------------------------------------- 跨日 / 跨月 / 跨年 / 闰日

func _run_day_steps() -> void:
	var cases := [
		[2026, 10, 21, 23, 59, 59, 2026, 10, 22, 0, 0, 0],
		[2025, 12, 31, 23, 59, 59, 2026, 1, 1, 0, 0, 0],
		[2026, 1, 31, 23, 59, 59, 2026, 2, 1, 0, 0, 0],
		[2026, 4, 30, 23, 59, 59, 2026, 5, 1, 0, 0, 0],
		[2024, 2, 28, 23, 59, 59, 2024, 2, 29, 0, 0, 0],
		[2024, 2, 29, 23, 59, 59, 2024, 3, 1, 0, 0, 0],
		[2026, 2, 28, 23, 59, 59, 2026, 3, 1, 0, 0, 0],
		[2026, 12, 31, 23, 59, 59, 2027, 1, 1, 0, 0, 0],
	]
	for c in cases:
		var a: float = _dt(c[0], c[1], c[2], c[3], c[4], c[5])
		var b: Dictionary = Cal.parts(a + 1.0)
		var ok: bool = (int(b["year"]) == c[6] and int(b["month"]) == c[7] and int(b["day"]) == c[8]
			and int(b["hour"]) == c[9] and int(b["minute"]) == c[10] and int(b["second"]) == c[11])
		_check(ok, "step %04d-%02d-%02d %02d:%02d:%02d +1s" % [c[0], c[1], c[2], c[3], c[4], c[5]], _fmt_parts(b))
	# 模拟推进跨月：一天一天加，3 月 31 天，4 月 30 天
	var ls: float = _dt(2026, 3, 1)
	var days := 0
	while int(Cal.parts(ls)["month"]) == 3 and days < 40:
		ls += 86400.0
		days += 1
	_check(days == 31, "march has 31 days when stepping", "days=%d" % days)
	var p_apr: Dictionary = Cal.parts(ls)
	_check(int(p_apr["month"]) == 4 and int(p_apr["day"]) == 1 and int(p_apr["hour"]) == 0, "stepped into april", _fmt_parts(p_apr))
	# 日索引连续：同一时刻相邻两天 day_index 差 1
	var p1: Dictionary = Cal.parts(_dt(2026, 12, 31, 23, 0, 0))
	var p2: Dictionary = Cal.parts(_dt(2027, 1, 1, 1, 0, 0))
	_check(int(p2["day_index"]) - int(p1["day_index"]) == 1, "day_index continuous")

# ---------------------------------------------------------------- 季节边界

func _run_season_boundaries() -> void:
	var bounds := [
		[2026, 3, 1, 0, [0.5, 0.0, 0.0, 0.5]],
		[2026, 6, 1, 1, [0.5, 0.5, 0.0, 0.0]],
		[2026, 9, 1, 2, [0.0, 0.5, 0.5, 0.0]],
		[2026, 12, 1, 3, [0.0, 0.0, 0.5, 0.5]],
	]
	for b in bounds:
		var s: Dictionary = Cal.season_at(b[0], b[1], b[2], 0.0)
		_check(int(s["season"]) == b[3], "season idx %d-%02d-%02d" % [b[0], b[1], b[2]], str(s))
		var w: Array = s["season_weights"]
		for i in range(4):
			_check(_near(float(w[i]), float(b[4][i]), 0.0001), "weight[%d] at %d-%02d-%02d" % [i, b[0], b[1], b[2]], str(w))
	# 季中：权重应几乎单季
	var mids := [
		[2026, 4, 15, 0], [2026, 7, 15, 1], [2026, 10, 15, 2], [2026, 1, 15, 3], [2026, 2, 15, 3],
	]
	for m in mids:
		var s: Dictionary = Cal.season_at(m[0], m[1], m[2], 0.0)
		_check(int(s["season"]) == m[3], "mid season %d-%02d-%02d" % [m[0], m[1], m[2]], str(s))
		_check(float(s["season_weights"][m[3]]) > 0.999, "mid weight ~1", str(s))
	# 季节相位基准
	_check(_near(Cal.season_phase(2026, 3, 1, 0.0), 0.0), "phase mar1 = 0")
	_check(_near(Cal.season_phase(2026, 6, 1, 0.0), 0.25), "phase jun1 = 0.25")
	_check(_near(Cal.season_phase(2026, 9, 1, 0.0), 0.5), "phase sep1 = 0.5")
	_check(_near(Cal.season_phase(2026, 12, 1, 0.0), 0.75), "phase dec1 = 0.75")
	# 3 月 1 日 0 点前后相位连续（2/28 23:59:59 → 3/1 0 点，应在 1.0 附近接 0.0）
	var eps := 1.0 / 86400.0
	var before: float = Cal.season_phase(2026, 2, 28, 86399.0)
	var after: float = Cal.season_phase(2026, 3, 1, 0.0)
	_check(_near(fposmod(after - before, 1.0), eps, 0.0001), "phase continuity at mar1", "before=%.6f after=%.6f" % [before, after])

# ---------------------------------------------------------------- 权重连续性 / 单调性

func _run_season_continuity() -> void:
	var ls: float = _dt(2026, 1, 1)
	var prev_phase: float = -1.0
	var prev_w: Array = []
	var total := 365
	for i in range(total):
		var p: Dictionary = Cal.parts(ls)
		var w: Array = p["season_weights"]
		var wsum := 0.0
		for v in w:
			wsum += float(v)
			_check(float(v) >= -0.000001 and float(v) <= 1.000001, "weight range", "%s w=%s" % [str(p["date_label"]), str(w)])
		_check(_near(wsum, 1.0, 0.0001), "weight sum", "%s w=%s" % [str(p["date_label"]), str(w)])
		if not prev_w.is_empty():
			var jump := 0.0
			for k in range(4):
				jump = maxf(jump, absf(float(w[k]) - float(prev_w[k])))
			# 24h 内权重最多变化约 0.5*24/10 = 1.2 → 但仍应平滑；限制单日突变 < 0.15
			_check(jump < 0.15, "weight daily jump", "%s jump=%.4f" % [str(p["date_label"]), jump])
		var phase: float = float(p["season_t"])
		if prev_phase >= 0.0:
			var d: float = fposmod(phase - prev_phase, 1.0)
			_check(d > 0.0 and d < 0.01, "phase monotonic", "%s d=%.6f" % [str(p["date_label"]), d])
		prev_phase = phase
		prev_w = w
		ls += 86400.0
	# 一整年后相位回到 0
	var endp: Dictionary = Cal.parts(ls)
	_check(int(endp["year"]) == 2027 and int(endp["day"]) == 1, "year walk end", str(endp["date_label"]))

# ---------------------------------------------------------------- 标签 / 夹取

func _run_labels_and_clamp() -> void:
	var p: Dictionary = Cal.parts(_dt(2026, 10, 22, 17, 18, 0))
	_check(str(p["date_label"]) == "2026年10月22日", "date label", str(p["date_label"]))
	_check(str(p["clock_label"]) == "17:18", "clock label", str(p["clock_label"]))
	_check(str(p["weekday_cn"]) == "周四", "weekday 2026-10-22 = 周四", str(p["weekday_cn"]))
	_check(int(p["weekday"]) == 4, "weekday index 4", str(p["weekday"]))
	_check(str(p["season_id"]) == "autumn" and str(p["season_label"]) == "秋季", "season autumn", str(p))
	_check(Cal.parts(_dt(2026, 1, 1))["weekday_cn"] == "周四", "2026-01-01 = 周四")
	_check(Cal.parts(_dt(2024, 2, 29))["weekday_cn"] == "周四", "2024-02-29 = 周四")
	_check(Cal.season_label(0) == "春季" and Cal.season_label(3) == "冬季", "season_label()")
	_check(Cal.season_name(1) == "夏", "season_name()")
	# clamp
	var c: Dictionary = Cal.clamp_parts(0, 13, 31, 25, -1, 61)
	_check(int(c["year"]) == 1, "clamp year 0->1", str(c))
	_check(int(c["month"]) == 12, "clamp month 13->12")
	_check(int(c["day"]) == 31, "clamp day 31 ok dec")
	_check(int(c["hour"]) == 23 and int(c["minute"]) == 0 and int(c["second"]) == 59, "clamp h/m/s", str(c))
	var c2: Dictionary = Cal.clamp_parts(2026, 2, 31)
	_check(int(c2["day"]) == 28, "clamp feb 31 -> 28", str(c2))
	var c3: Dictionary = Cal.clamp_parts(2024, 2, 31)
	_check(int(c3["day"]) == 29, "clamp feb 2024 -> 29", str(c3))
	var c4: Dictionary = Cal.clamp_parts(99999, 1, 1)
	_check(int(c4["year"]) == 9999, "clamp year max", str(c4))
	# 非法输入 to_local_seconds 不崩且等于夹取后的值
	var bad: float = Cal.to_local_seconds(2026, 2, 31)
	var good: float = _dt(2026, 2, 28)
	_check(_near(bad, good), "to_local_seconds clamps feb 31", "bad=%.1f good=%.1f" % [bad, good])
	_check(not is_nan(bad) and not is_inf(bad), "to_local_seconds finite")

# ---------------------------------------------------------------- 确定性与性能

func _run_determinism_and_perf() -> void:
	var ls: float = _dt(2026, 10, 22, 17, 18, 33)
	var a: Dictionary = Cal.parts(ls)
	var b: Dictionary = Cal.parts(ls)
	_check(str(a) == str(b), "parts deterministic")
	var t0: int = Time.get_ticks_usec()
	var acc := 0.0
	for i in range(2000):
		var p: Dictionary = Cal.parts(ls + float(i))
		acc += float(p["season_weights"][int(p["season"])])
	var dt_us: int = Time.get_ticks_usec() - t0
	_check(acc > 0.0, "perf loop acc")
	print("[PERF] parts() 2000 calls = %.2f ms (%.2f us/call)" % [dt_us / 1000.0, float(dt_us) / 2000.0])
	_check(float(dt_us) / 2000.0 < 120.0, "parts() under 120us/call", "%.1f us" % (float(dt_us) / 2000.0))
