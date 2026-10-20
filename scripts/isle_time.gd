class_name IsleTime
extends RefCounted
## 现实时间 / 时区服务。
##
## 把 unix 秒换算成任意 IANA 时区的“墙上时间”，并给出 UTC 偏移标签。
## 偏移转换表由 tools/gen_tz_data.py 用 IANA tzdata（Python zoneinfo）真值生成、
## 写入 scripts/isle_tz_data.gd（2016-01 ~ 2041-01），因此夏令时、半小时时区、
## 跨日/跨年换算都不需要在游戏侧维护任何规则；表外的历史/未来时刻按最近一档偏移延用。
##
## 第五阶段新增“规则分组”能力：按“近 10 年历史 + 未来 3 年”的转换序列签名把
## 时区归入同一规则组（用于时区选择器：普通组 / 特殊组各最多 2 个代表城市）。
##
## 默认时区为 Asia/Shanghai；全部接口都是无状态静态函数，可被菜单、HUD 与主循环共享。

const TZ := preload("res://scripts/isle_tz_data.gd")

const DEFAULT_ZONE := "Asia/Shanghai"
const SOURCE_SIM := "sim"
const SOURCE_REAL := "real"

# ============================================================
# 时区枚举 / 元信息
# ============================================================

## 全部可选时区 id（按大洲分组的展示顺序，共 134 个）。
static func zones() -> Array[String]:
	var out: Array[String] = []
	for z in TZ.ZONE_ORDER:
		out.append(String(z))
	return out

static func default_zone() -> String:
	return DEFAULT_ZONE

## 该 id 是否在偏移表内（大小写不敏感）。
static func has_zone(id: String) -> bool:
	var key := id.strip_edges()
	if TZ.ZONE_TRANS.has(key):
		return true
	for z in TZ.ZONE_ORDER:
		if String(z).to_lower() == key.to_lower():
			return true
	return false

## 归一化时区 id：非法 / 空串 / 大小写偏差都回落到默认时区。
static func resolve_zone(id: String) -> String:
	var key := id.strip_edges()
	if TZ.ZONE_TRANS.has(key):
		return key
	for z in TZ.ZONE_ORDER:
		if String(z).to_lower() == key.to_lower():
			return String(z)
	return DEFAULT_ZONE

## 城市中文名（表内缺省时回落为 id 本身）。
static func city_of(id: String) -> String:
	var key := resolve_zone(id)
	return String(TZ.ZONE_CITIES.get(key, key))

## 城市英文名（表内缺省时回落为 IANA id 末段）。
static func city_en_of(id: String) -> String:
	var key := resolve_zone(id)
	if TZ.ZONE_CITIES_EN.has(key):
		return String(TZ.ZONE_CITIES_EN[key])
	return key.get_slice("/", maxi(0, key.get_slice_count("/") - 1)).replace("_", " ")

## 中英双名：“上海 Shanghai”，用于时区选项标签。
static func city_bilingual(id: String) -> String:
	var key := resolve_zone(id)
	var cn := city_of(key)
	var en := city_en_of(key)
	if en.is_empty() or en == cn:
		return cn
	return "%s %s" % [cn, en]

## 单个时区的展示信息；unix < 0 时取当前时刻。
## 返回 {id, city, offset_now(秒), label}，label 形如 “上海 · Asia/Shanghai · UTC+08:00”。
static func info(id: String, unix: float = -1.0) -> Dictionary:
	var key := resolve_zone(id)
	var ts := unix
	if ts < 0.0:
		ts = now_unix()
	var off := offset_at(key, ts)
	var city := city_of(key)
	return {
		"id": key,
		"city": city,
		"offset_now": off,
		"label": "%s · %s · %s" % [city, key, format_offset(off)],
	}

# ============================================================
# 偏移换算
# ============================================================

## unix 秒 → 该时区的 UTC 偏移秒（含夏令时）。
## 表结构：[基线偏移, 转换时刻1, 新偏移1, 转换时刻2, 新偏移2, ...]，在转换时刻上二分。
static func offset_at(id: String, unix: float) -> int:
	var data: Array = TZ.ZONE_TRANS.get(resolve_zone(id), [])
	var n := data.size()
	if n <= 1:
		return int(data[0]) if n == 1 else 0
	var lo := 1
	var hi := (n - 1) >> 1
	var idx := 0
	while lo <= hi:
		var mid := (lo + hi) >> 1
		if float(data[2 * mid - 1]) <= unix:
			idx = mid
			lo = mid + 1
		else:
			hi = mid - 1
	return int(data[2 * idx])

## unix 秒 → 该时区的“当地秒数”（unix + UTC 偏移），可直接当本地时间轴使用。
static func local_seconds(id: String, unix: float) -> float:
	return unix + float(offset_at(id, unix))

## unix 秒 → 该时区的墙上时间。
## 返回 {year, month, day, hour, minute, second, weekday, offset, unix, local_unix, id}；
## weekday 沿用 Godot 约定：0 = 周日 … 6 = 周六。
static func local_datetime(id: String, unix: float) -> Dictionary:
	var key := resolve_zone(id)
	var off := offset_at(key, unix)
	var local_unix := unix + float(off)
	var clock := Time.get_datetime_dict_from_unix_time(int(floor(local_unix)))
	clock["offset"] = off
	clock["unix"] = unix
	clock["local_unix"] = local_unix
	clock["id"] = key
	return clock

## 偏移秒 → “UTC+08:00” / “UTC-05:00” / “UTC+05:30”（含秒时附第三段）。
static func format_offset(sec: int) -> String:
	var sign := "-" if sec < 0 else "+"
	var a := absi(sec)
	var h := int(a / 3600)
	var m := int((a % 3600) / 60)
	var s := a % 60
	if s != 0:
		return "UTC%s%02d:%02d:%02d" % [sign, h, m, s]
	return "UTC%s%02d:%02d" % [sign, h, m]

## 当前时刻（unix 秒，含小数）。
static func now_unix() -> float:
	return Time.get_unix_time_from_system()

## “Asia/Shanghai · UTC+08:00”，供 HUD / 菜单直接展示。
static func zone_label(id: String, unix: float = -1.0) -> String:
	var key := resolve_zone(id)
	var ts := unix
	if ts < 0.0:
		ts = now_unix()
	return "%s · %s" % [key, format_offset(offset_at(key, ts))]

## 现实时间模式下的完整标签：“Asia/Shanghai · UTC+08:00”。
static func offset_label(id: String, unix: float = -1.0) -> String:
	return format_offset(offset_at(id, unix)) if unix >= 0.0 else format_offset(offset_at(id, now_unix()))

# ============================================================
# 规则分组 / 时区选项标签（第五阶段新增）
# ============================================================

## 平均回归年秒数：把“N 年”窗口换算成 unix 秒。
const AVG_YEAR := 31556952.0
## 规则分组窗口：近 10 年历史 + 未来 3 年，覆盖 DST 规则和“近 10 年法规变更”。
const GROUP_PAST_YEARS := 10.0
const GROUP_FUTURE_YEARS := 3.0
## rule_signature 的默认跨度（契约：3 年）。
const SIG_SPAN_YEARS := 3.0
## 每个规则组最多展示的代表城市数。
const MAX_REPS := 2

## 代表城市优先级：越靠前越优先成为所在规则组的代表（每组最多 2 个）。
## 只影响“选谁代表”，不影响分组；契约硬要求的代表城市都在这里列全。
const REP_PRIORITY := [
	"Asia/Shanghai", "Asia/Hong_Kong", "Asia/Tokyo", "Asia/Seoul",
	"Asia/Kolkata", "Asia/Kathmandu", "Asia/Colombo", "Asia/Dhaka", "Asia/Yangon",
	"Asia/Dubai", "Asia/Riyadh", "Asia/Tehran", "Asia/Istanbul", "Asia/Almaty",
	"Europe/London", "Europe/Dublin", "Europe/Lisbon", "Europe/Paris", "Europe/Berlin",
	"Europe/Madrid", "Europe/Rome", "Europe/Moscow", "Europe/Kyiv",
	"America/New_York", "America/Chicago", "America/Denver", "America/Los_Angeles",
	"America/Phoenix", "America/Anchorage", "America/Toronto", "America/Vancouver",
	"America/Mexico_City", "America/Santiago", "America/Sao_Paulo", "America/Havana",
	"America/Asuncion", "America/St_Johns",
	"Australia/Sydney", "Australia/Melbourne", "Australia/Perth", "Australia/Eucla",
	"Australia/Adelaide", "Australia/Darwin", "Australia/Brisbane",
	"Pacific/Auckland", "Pacific/Chatham", "Pacific/Marquesas", "Pacific/Kiritimati",
	"Pacific/Honolulu", "Pacific/Fiji", "Pacific/Noumea",
	"Africa/Cairo", "Africa/Casablanca", "Africa/Johannesburg", "Africa/Windhoek",
	"Africa/Lagos", "Africa/Nairobi",
	"Indian/Maldives", "Indian/Mauritius", "Atlantic/Reykjavik", "UTC",
]

static func _utc_year(ts: float) -> int:
	return int(Time.get_datetime_dict_from_unix_time(int(floor(ts))).get("year", 1970))

static func _year_start(year: int) -> float:
	return float(Time.get_unix_time_from_datetime_dict({"year": year, "month": 1, "day": 1, "hour": 0, "minute": 0, "second": 0}))

## 某 UTC 年份的 1 月 1 日 / 7 月 1 日偏移（用于判断该年是否行夏令时、基准规则是否变化）。
static func _year_offsets(key: String, year: int) -> Array[int]:
	var jan := _year_start(year)
	var jul := float(Time.get_unix_time_from_datetime_dict({"year": year, "month": 7, "day": 1, "hour": 0, "minute": 0, "second": 0}))
	var out: Array[int] = []
	out.append(offset_at(key, jan))
	out.append(offset_at(key, jul))
	return out

## 分组窗口起点：近 10 年历史的起点（unix 秒）。
static func _window_from(ts: float) -> float:
	return ts - GROUP_PAST_YEARS * AVG_YEAR

## 窗口内是否发生过偏移转换（DST 或法规变更都会命中）。
static func _has_window_change(key: String, from_ts: float, to_ts: float) -> bool:
	var flat: Array = TZ.ZONE_TRANS.get(key, [])
	var i := 1
	while i < flat.size():
		var t := float(flat[i])
		if t >= to_ts:
			return false
		if t > from_ts:
			return true
		i += 2
	return false

## 窗口内全部转换 [(转换时刻, 新偏移), ...]。
static func _transitions_in(key: String, from_ts: float, to_ts: float) -> Array:
	var flat: Array = TZ.ZONE_TRANS.get(key, [])
	var out: Array = []
	var i := 1
	while i < flat.size():
		var t := float(flat[i])
		if t >= to_ts:
			break
		if t > from_ts:
			out.append([t, int(flat[i + 1])])
		i += 2
	return out

## 窗口内出现过的偏移集合（升序去重）。
static func _window_offsets(key: String, from_ts: float, to_ts: float) -> Array[int]:
	var offsets: Array[int] = []
	offsets.append(offset_at(key, from_ts))
	for pair in _transitions_in(key, from_ts, to_ts):
		var off := int((pair as Array)[1])
		if not offsets.has(off):
			offsets.append(off)
	offsets.sort()
	return offsets

## 规则签名：窗口内“基线偏移 + (相对转换秒, 新偏移) 序列”的规范化哈希。
## 同一签名的时区在当前窗口内规则完全一致（含 DST 起止与历史法规变更）。
static func rule_signature(id: String, unix_from: float, span_years: float) -> String:
	var key := resolve_zone(id)
	var from_ts := unix_from
	if from_ts < 0.0:
		from_ts = now_unix()
	var span := span_years
	if span <= 0.0:
		span = SIG_SPAN_YEARS
	var to_ts := from_ts + span * AVG_YEAR
	var parts := PackedStringArray()
	parts.append(str(offset_at(key, from_ts)))
	var flat: Array = TZ.ZONE_TRANS.get(key, [])
	var i := 1
	while i < flat.size():
		var t := float(flat[i])
		if t <= from_ts:
			i += 2
			continue
		if t >= to_ts:
			break
		parts.append("%d:%d" % [int(round(t - from_ts)), int(flat[i + 1])])
		i += 2
	return ",".join(parts).sha256_text()

## 分组键：近 10 年 + 未来 3 年窗口的规则签名（zone_groups 的 rule_key 同源）。
static func zone_group_key(id: String, unix_now: float = -1.0) -> String:
	var ts := unix_now
	if ts < 0.0:
		ts = now_unix()
	return rule_signature(id, _window_from(ts), GROUP_PAST_YEARS + GROUP_FUTURE_YEARS)

## 当前生效偏移秒（= offset_at，语义化命名，供 UI 读取）。
static func effective_offset(id: String, unix: float = -1.0) -> int:
	var ts := unix
	if ts < 0.0:
		ts = now_unix()
	return offset_at(id, ts)

## 当前是否处于夏令时：与同年 1 月 / 7 月偏移相比，当前偏移较大者为 DST。
static func dst_active(id: String, unix: float = -1.0) -> bool:
	var key := resolve_zone(id)
	var ts := unix
	if ts < 0.0:
		ts = now_unix()
	var pair := _year_offsets(key, _utc_year(ts))
	if pair[0] == pair[1]:
		return false
	return offset_at(key, ts) == maxi(pair[0], pair[1])

## 该年是否行夏令时（1 月 / 7 月偏移不同）。
static func _has_dst_now(key: String, ts: float) -> bool:
	var year := _utc_year(ts)
	for y in range(year, year + 2):
		var pair := _year_offsets(key, y)
		if pair[0] != pair[1]:
			return true
	return false

## 当年 DST 起止日期文本（如 “03-08 → 11-01”；南半球标注“次年”）；无法计算时返回空串。
static func _dst_bounds_text(key: String, ts: float) -> String:
	var year := _utc_year(ts)
	var trans := _transitions_in(key, _year_start(year), _year_start(year + 1))
	if trans.size() != 2:
		return ""
	var a: Array = trans[0]
	var b: Array = trans[1]
	var oa := int(a[1])
	var ob := int(b[1])
	if oa == ob:
		return ""
	var start_ts := float(a[0]) if oa > ob else float(b[0])
	var end_ts := float(b[0]) if oa > ob else float(a[0])
	var sm := _month_day(start_ts)
	var em := _month_day(end_ts)
	if int(Time.get_datetime_dict_from_unix_time(int(start_ts)).get("month", 0)) > int(Time.get_datetime_dict_from_unix_time(int(end_ts)).get("month", 0)):
		return "%s → 次年 %s" % [sm, em]
	return "%s → %s" % [sm, em]

## 特殊规则的“为何特殊”说明：非整时偏移 / 法规变更年份 / 夏令时起止 / 非固定偏移调整。
static func _special_reason(key: String, ts: float) -> String:
	var from_ts := _window_from(ts)
	var to_ts := ts + GROUP_FUTURE_YEARS * AVG_YEAR
	var offsets := _window_offsets(key, from_ts, to_ts)
	var nonwhole := false
	for off in offsets:
		if int(off) % 3600 != 0:
			nonwhole = true
			break
	var y0 := _utc_year(from_ts)
	if _year_start(y0) < from_ts:
		y0 += 1
	var y1 := _utc_year(to_ts)
	var prev: Array[int] = []
	var change_year := 0
	for y in range(y0, y1 + 1):
		var pair := _year_offsets(key, y)
		if prev.is_empty():
			prev = pair
			continue
		if pair != prev:
			change_year = y
			break
		prev = pair
	var has_dst := _has_dst_now(key, ts)
	var future_change := _has_window_change(key, ts, to_ts)
	var hist_change := _has_window_change(key, from_ts, ts)
	var parts := PackedStringArray()
	if nonwhole:
		parts.append("非整时偏移")
	if change_year > 0:
		parts.append("%d 年起规则变更" % change_year)
	if has_dst:
		var bounds := _dst_bounds_text(key, ts)
		parts.append("夏令时" + (" " + bounds if not bounds.is_empty() else ""))
	elif future_change:
		parts.append("非固定偏移调整")
	if change_year == 0 and not has_dst and not future_change and hist_change:
		parts.append("近 10 年规则变更")
	if parts.is_empty():
		parts.append("特殊规则")
	return " · ".join(parts)

## 特殊规则 = 窗口内有转换（DST / 法规变更 / 非固定调整）或当前偏移非整小时。
static func is_special_rule(id: String, unix: float = -1.0) -> bool:
	var key := resolve_zone(id)
	var ts := unix
	if ts < 0.0:
		ts = now_unix()
	if _has_window_change(key, _window_from(ts), ts + GROUP_FUTURE_YEARS * AVG_YEAR):
		return true
	return offset_at(key, ts) % 3600 != 0

## 时区选项标签：“上海 Shanghai · UTC+08:00”，夏令时追加 “ · 夏令时”；unix < 0 取当前。
static func zone_option_label(id: String, unix: float = -1.0) -> String:
	var key := resolve_zone(id)
	var ts := unix
	if ts < 0.0:
		ts = now_unix()
	var label := "%s · %s" % [city_bilingual(key), format_offset(offset_at(key, ts))]
	if dst_active(key, ts):
		label += " · 夏令时"
	return label

## 代表城市：先按 REP_PRIORITY 挑，不足 MAX_REPS 再按表内顺序补齐。
static func _pick_reps(mem: Array) -> Array:
	var out: Array = []
	for cand in REP_PRIORITY:
		if out.size() >= MAX_REPS:
			break
		if mem.has(cand) and not out.has(cand):
			out.append(cand)
	if out.size() < MAX_REPS:
		for z in mem:
			if out.size() >= MAX_REPS:
				break
			if not out.has(z):
				out.append(z)
	return out

## 时区规则分组（时区选择器数据源）。
## 返回 [{kind: "normal"|"special", rule_key, title, dst, reason, offset_min, offset_max,
##        offset_text, entries: [{id, city, city_en, offset_sec, offset_text, dst_now, is_dst, label}],
##        members: Array[String]}]；entries 每组 ≤ MAX_REPS（2 个代表），members 为全部同规则时区。
## 同一规则只会落在 normal 或 special 之一（rule_key 唯一，窗口内规则含历史，因此分类一致）。
static func zone_groups(unix_now: float = -1.0) -> Array:
	var ts := unix_now
	if ts < 0.0:
		ts = now_unix()
	var from_ts := _window_from(ts)
	var to_ts := ts + GROUP_FUTURE_YEARS * AVG_YEAR
	var span := GROUP_PAST_YEARS + GROUP_FUTURE_YEARS
	var order: Array[String] = []
	var members := {}
	for z in TZ.ZONE_ORDER:
		var key := String(z)
		var sig := rule_signature(key, from_ts, span)
		if not members.has(sig):
			order.append(sig)
			members[sig] = []
		(members[sig] as Array).append(key)
	var out: Array = []
	for sig in order:
		var mem: Array = members[sig]
		var probe_key := String(mem[0])
		var kind := "special" if is_special_rule(probe_key, ts) else "normal"
		var offsets := _window_offsets(probe_key, from_ts, to_ts)
		var off_parts := PackedStringArray()
		for off in offsets:
			off_parts.append(format_offset(int(off)))
		var offsets_text := " / ".join(off_parts)
		var has_dst := _has_dst_now(probe_key, ts)
		var reason := ""
		var title := ""
		if kind == "normal":
			title = "%s · 标准时区 · %d 个时区" % [offsets_text, mem.size()]
		else:
			reason = _special_reason(probe_key, ts)
			title = "%s · %s · %d 个时区" % [offsets_text, reason, mem.size()]
		var entries: Array = []
		for rid in _pick_reps(mem):
			var zid := String(rid)
			var off := offset_at(zid, ts)
			var is_dst := dst_active(zid, ts)
			entries.append({
				"id": zid,
				"city": city_of(zid),
				"city_en": city_en_of(zid),
				"offset_sec": off,
				"offset_text": format_offset(off),
				"dst_now": is_dst,
				"is_dst": is_dst,
				"label": zone_option_label(zid, ts),
			})
		out.append({
			"kind": kind,
			"rule_key": sig,
			"title": title,
			"dst": has_dst,
			"reason": reason,
			"offset_min": int(offsets[0]),
			"offset_max": int(offsets[offsets.size() - 1]),
			"offset_text": offsets_text,
			"entries": entries,
			"members": mem,
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ka := 0 if str(a["kind"]) == "normal" else 1
		var kb := 0 if str(b["kind"]) == "normal" else 1
		if ka != kb:
			return ka < kb
		if int(a["offset_min"]) != int(b["offset_min"]):
			return int(a["offset_min"]) < int(b["offset_min"])
		# 按 ZONE_ORDER 首个成员排序：rule_key 含相对窗口起点的秒数，会随 now 微移，
		# 若用它做次序键，选择器分组顺序会在几十秒内抖动。
		return str((a["members"] as Array)[0]) < str((b["members"] as Array)[0]))
	return out

## 月份-日期文本：“03-08”。
static func _month_day(ts: float) -> String:
	var d := Time.get_datetime_dict_from_unix_time(int(floor(ts)))
	return "%02d-%02d" % [int(d.get("month", 1)), int(d.get("day", 1))]

# ============================================================
# 搜索 / 时间来源
# ============================================================

## 按 city（中文名 / 英文名）或 IANA id 子串搜索；空查询返回全部时区。
## 返回 Array[Dictionary]，元素同 info(id)。
static func search(q: String) -> Array:
	var query := q.strip_edges().to_lower()
	var ts := now_unix()
	var out: Array = []
	for z in TZ.ZONE_ORDER:
		var key := String(z)
		if query.is_empty() or key.to_lower().contains(query) or city_of(key).to_lower().contains(query) or city_en_of(key).to_lower().contains(query):
			out.append(info(key, ts))
	return out

## 时间来源归一化：只认 "real"，其余一律 "sim"。
static func sanitize_source(value: String) -> String:
	return SOURCE_REAL if value.strip_edges() == SOURCE_REAL else SOURCE_SIM

## 时间来源展示名。
static func source_label(value: String) -> String:
	return "现实时间" if sanitize_source(value) == SOURCE_REAL else "模拟时间"
