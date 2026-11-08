class_name IsleCalendar
extends RefCounted
## P8：公历日历与季节派生（纯函数）。
##
## 唯一权威时间仍是 main.gd 的 _sim_seconds（UTC+8 本地秒数轴）。本模块不持有任何
## 时钟、不缓存"当前日期"，只把权威秒数投影成日历/季节，供 UI、视觉、天气与生态
## 只读消费。所有函数无副作用，可在 --headless 探针里逐条断言。

const SEC_PER_DAY := 86400.0
## 与 IsleAstro.TZ_SECONDS 一致：模拟秒数轴按 UTC+8 墙钟表示（local = unix + 28800）。
const TZ_SECONDS := 28800.0

const WEEKDAY_CN := ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
const SEASON_NAMES := ["春", "夏", "秋", "冬"]
const SEASON_LABELS := ["春季", "夏季", "秋季", "冬季"]
const SEASON_IDS := ["spring", "summer", "autumn", "winter"]
const MONTH_DAYS := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

## 季节边界（北半球公历季）：春 3-5、夏 6-8、秋 9-11、冬 12-2。
const TRANSITION_DAYS := 10.0
const MIN_YEAR := 1
const MAX_YEAR := 9999

static func is_leap(year: int) -> bool:
	return (year % 4 == 0) and ((year % 100 != 0) or (year % 400 == 0))

static func days_in_month(year: int, month: int) -> int:
	var m := clampi(month, 1, 12)
	if m == 2 and is_leap(year):
		return 29
	return int(MONTH_DAYS[m - 1])

static func days_in_year(year: int) -> int:
	return 366 if is_leap(year) else 365

## 0 基的年内天数（1 月 1 日 = 0）。
static func day_of_year(year: int, month: int, day: int) -> int:
	var m := clampi(month, 1, 12)
	var total := clampi(day, 1, days_in_month(year, m)) - 1
	for i in range(1, m):
		total += days_in_month(year, i)
	return total

## 权威模拟秒数 → 日历/季节投影。
##   year/month/day/hour/minute/second/weekday/weekday_cn
##   sod          当天内秒数 [0, 86400)
##   day_index    floor(local_seconds / 86400)，天气槽等做确定性派生的稳定索引
##   date_label   "2026年10月22日"
##   clock_label  "17:18"
##   season       主季节索引 0春 1夏 2秋 3冬
##   season_id    "spring"/"summer"/"autumn"/"winter"
##   season_label "春季"
##   season_t     年内季节相位 [0,1)，3 月 1 日 0 点 = 0，12 月 1 日 = 0.75
##   season_frac  主季节内的进度 [0,1)
##   season_weights [春, 夏, 秋, 冬] 连续权重（边界 ±10 天平滑混合，和恒为 1）
static func parts(local_seconds: float) -> Dictionary:
	var ls: float = floorf(local_seconds)
	var day_index := int(floorf(ls / SEC_PER_DAY))
	var sod: float = fposmod(local_seconds, SEC_PER_DAY)
	var dt := Time.get_datetime_dict_from_unix_time(int(ls))
	var year := int(dt.get("year", 1970))
	var month := int(dt.get("month", 1))
	var day := int(dt.get("day", 1))
	if year < MIN_YEAR or year > MAX_YEAR:
		# Time 对越界秒数可能给出异常年份：夹回合法范围，避免 UI/视觉崩溃。
		year = clampi(year, MIN_YEAR, MAX_YEAR)
	var hour := int(dt.get("hour", 0))
	var minute := int(dt.get("minute", 0))
	var second := int(dt.get("second", 0))
	var weekday := int(dt.get("weekday", 0))
	var season: Dictionary = season_at(year, month, day, sod)
	var result := {
		"year": year,
		"month": month,
		"day": day,
		"hour": hour,
		"minute": minute,
		"second": second,
		"weekday": weekday,
		"weekday_cn": WEEKDAY_CN[clampi(weekday, 0, 6)],
		"sod": sod,
		"day_index": day_index,
		"date_label": "%04d年%d月%d日" % [year, month, day],
		"clock_label": "%02d:%02d" % [hour, minute],
	}
	result.merge(season, true)
	return result

## 日历部件 → 权威模拟秒数。非法输入先夹到合法范围（不抛错、不产生 NaN）。
static func to_local_seconds(year: int, month: int, day: int, hour: int = 0, minute: int = 0, second: int = 0) -> float:
	var c := clamp_parts(year, month, day, hour, minute, second)
	var unix := Time.get_unix_time_from_datetime_dict({
		"year": int(c["year"]),
		"month": int(c["month"]),
		"day": int(c["day"]),
		"hour": int(c["hour"]),
		"minute": int(c["minute"]),
		"second": int(c["second"]),
	})
	return float(unix)

static func clamp_parts(year: int, month: int, day: int, hour: int = 0, minute: int = 0, second: int = 0) -> Dictionary:
	var y := clampi(year, MIN_YEAR, MAX_YEAR)
	var mo := clampi(month, 1, 12)
	var d := clampi(day, 1, days_in_month(y, mo))
	return {
		"year": y,
		"month": mo,
		"day": d,
		"hour": clampi(hour, 0, 23),
		"minute": clampi(minute, 0, 59),
		"second": clampi(second, 0, 59),
	}

## 某天某时刻（当天内秒）的季节投影；month/day 非法时自动夹取。
static func season_at(year: int, month: int, day: int, sod: float = 0.0) -> Dictionary:
	var y := clampi(year, MIN_YEAR, MAX_YEAR)
	var mo := clampi(month, 1, 12)
	var d := clampi(day, 1, days_in_month(y, mo))
	var phase := season_phase(y, mo, d, clampf(sod, 0.0, SEC_PER_DAY - 0.001))
	var s: float = fposmod(phase, 1.0)
	s *= 4.0
	if s >= 3.999999:
		s = 3.999999
	var base := int(floorf(s)) % 4
	var frac: float = s - floorf(s)
	var weights: Array = [0.0, 0.0, 0.0, 0.0]
	var w := TRANSITION_DAYS / (float(days_in_year(y)) * 0.25)
	if frac < w:
		var prev := (base + 3) % 4
		var alpha := 0.5 + 0.5 * smoothstep(0.0, 1.0, frac / w)
		weights[base] = alpha
		weights[prev] = 1.0 - alpha
	elif frac > 1.0 - w:
		var nxt := (base + 1) % 4
		# 季末过渡：权重从 1.0 平滑降到 0.5（与下一季起始的 0.5 对齐），不要从 0.5 起步。
		var beta := 1.0 - 0.5 * smoothstep(0.0, 1.0, (frac - (1.0 - w)) / w)
		weights[base] = beta
		weights[nxt] = 1.0 - beta
	else:
		weights[base] = 1.0
	return {
		"season": base,
		"season_id": String(SEASON_IDS[base]),
		"season_label": String(SEASON_LABELS[base]),
		"season_t": phase,
		"season_frac": frac,
		"season_weights": weights,
	}

## 年内季节相位：3 月 1 日 0 点 = 0.0，6 月 1 日 = 0.25，9 月 1 日 = 0.5，12 月 1 日 = 0.75。
## 季长按真实公历天数分段线性；12 月→次年 2 月按 12 月 1 日到次年 3 月 1 日归一。
static func season_phase(year: int, month: int, day: int, sod: float = 0.0) -> float:
	var yd := float(day_of_year(year, month, day)) + clampf(sod, 0.0, SEC_PER_DAY - 0.001) / SEC_PER_DAY
	var ylen := float(days_in_year(year))
	var b1 := float(days_in_month(year, 1) + days_in_month(year, 2))          # 3 月 1 日
	var b2 := b1 + float(days_in_month(year, 3) + days_in_month(year, 4) + days_in_month(year, 5))
	var b3 := b2 + float(days_in_month(year, 6) + days_in_month(year, 7) + days_in_month(year, 8))
	var b4 := b3 + float(days_in_month(year, 9) + days_in_month(year, 10) + days_in_month(year, 11))
	if yd < b1:
		# 1-2 月：属于上一年的冬季尾段
		var winter_len := b1 + ylen - b4
		return 0.75 + 0.25 * ((yd + ylen) - b4) / winter_len
	if yd < b2:
		return 0.25 * (yd - b1) / (b2 - b1)
	if yd < b3:
		return 0.25 + 0.25 * (yd - b2) / (b3 - b2)
	if yd < b4:
		return 0.5 + 0.25 * (yd - b3) / (b4 - b3)
	var winter_len2 := b1 + ylen - b4
	return 0.75 + 0.25 * (yd - b4) / winter_len2

## 季节索引（0春 1夏 2秋 3冬）→ 中文名；非法索引回退为春。
static func season_label(index: int) -> String:
	return String(SEASON_LABELS[clampi(index, 0, 3)])

static func season_name(index: int) -> String:
	return String(SEASON_NAMES[clampi(index, 0, 3)])

## "2026年10月22日 周四 17:18" —— 仅用于日志/探针，HUD 自己组合。
static func full_label(local_seconds: float) -> String:
	var p := parts(local_seconds)
	return "%s %s %s" % [str(p["date_label"]), str(p["weekday_cn"]), str(p["clock_label"])]
