extends SceneTree
## P8 阶段 7：生态联动（岛民天气偏好 / 海鸥风场 / 船只停航 / 炊烟 / 萤火）静态 + 纯函数 probe。
## 运行：Godot_v4.7.2-stable_win64_console.exe --headless --path D:/休闲小岛幻境/游戏工程 --script res://tools/probe_p8_ecology.gd
## 覆盖：日程 choose() 在雷暴/台风/雨/雪/强风/晴天下的 kind 与 region_pref；
##       小雪赏雪例外、午餐/夜间窗口不受天气影响；无 weather 键时行为不变；
##       各接入文件确实消费同一份天气快照（源码契约，防止后续改回独立天气源）。
## 退出码：0 = 全部通过；1 = 有失败。

const Cal := preload("res://scripts/isle_calendar.gd")
const Astro := preload("res://scripts/isle_astro.gd")
const Sch := preload("res://scripts/isle_villager_schedule.gd")

var _checks: int = 0
var _fails: Array = []

func _init() -> void:
	var t0: int = Time.get_ticks_msec()
	_run_schedule_weather()
	_run_schedule_unchanged()
	_run_source_contracts()
	print("")
	print("[SUMMARY] checks=%d fail=%d elapsed_ms=%d" % [_checks, _fails.size(), Time.get_ticks_msec() - t0])
	if _fails.is_empty():
		print("PROBE_P8_ECOLOGY RESULT: PASS")
		quit(0)
	else:
		for f in _fails:
			print("[FAIL] ", str(f))
		print("PROBE_P8_ECOLOGY RESULT: FAIL")
		quit(1)

# ---------------------------------------------------------------- 工具

func _check(cond: bool, name: String, detail: String = "") -> bool:
	_checks += 1
	if not cond:
		_fails.append(name + (("  " + detail) if detail != "" else ""))
	return cond

func _ls(y: int, mo: int, d: int, h: int = 12, mi: int = 0) -> float:
	return Cal.to_local_seconds(y, mo, d, h, mi, 0)

func _choose_at(y: int, mo: int, d: int, h: int, mi: int, weather: Dictionary) -> Dictionary:
	var ls := _ls(y, mo, d, h, mi)
	var events: Dictionary = Astro.day_events(ls)
	var sun_alt := float((Astro.compute(ls) as Dictionary).get("sun_alt", 30.0))
	var s := Sch.new()
	s.seed = 7
	var ctx := {
		"sim_seconds": ls,
		"sim_rate": 144.0,
		"sun_alt": sun_alt,
		"events": events,
	}
	if not weather.is_empty():
		ctx["weather"] = weather
	return s.choose(ctx)

func _wx(type_id: String, precip: String, pint: float, wind: float, storm: float) -> Dictionary:
	return {
		"type": type_id,
		"precip_type": precip,
		"precip_intensity": pint,
		"wind_strength": wind,
		"wind_x": 0.0,
		"wind_z": -1.0,
		"storm": storm,
		"cloud": 0.5,
	}

func _file_text(path: String) -> String:
	return FileAccess.get_file_as_string(path)

# ---------------------------------------------------------------- 日程天气过滤

func _run_schedule_weather() -> void:
	# 夏季 10:00 = morning_out（08:30-11:30，户外散步窗口）
	var clear := _choose_at(2026, 7, 15, 10, 0, _wx("clear", "none", 0.0, 0.18, 0.0))
	# P7-FINALIZE：life-fix 在白天户外窗口新增 weighted random 休闲候选（stroll/swing/sea_view/idle）。
	# 本探针意图是"晴天允许户外活动"，不是固定动作名，因此接受新户外候选集合。
	var outdoor_ok := ["stroll", "swing", "sea_view", "idle"].has(String(clear["kind"]))
	_check(outdoor_ok, "clear morning_out kind∈{stroll,swing,sea_view,idle}", String(clear["kind"]))
	_check(String(clear["region_pref"]) == "outdoor", "clear morning_out pref=outdoor", String(clear["region_pref"]))
	# 大雨：户外 → 门廊，散步 → 坐
	var rain := _choose_at(2026, 7, 15, 10, 0, _wx("heavy_rain", "rain", 0.92, 0.58, 0.30))
	_check(String(rain["region_pref"]) == "porch", "heavy rain pref=porch", String(rain["region_pref"]))
	_check(String(rain["kind"]) == "sit", "heavy rain stroll->sit", String(rain["kind"]))
	# 雷暴 / 台风：一律室内
	var thunder := _choose_at(2026, 7, 15, 10, 0, _wx("thunder", "rain", 0.86, 0.64, 0.85))
	_check(String(thunder["region_pref"]) == "indoor", "thunder pref=indoor", String(thunder["region_pref"]))
	_check(String(thunder["kind"]) == "idle", "thunder stroll->idle", String(thunder["kind"]))
	var typhoon := _choose_at(2026, 9, 20, 10, 0, _wx("typhoon", "rain", 0.95, 1.0, 1.0))
	_check(String(typhoon["region_pref"]) == "indoor", "typhoon pref=indoor", String(typhoon["region_pref"]))
	# 中雨（强度 > 0.25）同样避雨
	var mid := _choose_at(2026, 7, 15, 10, 0, _wx("mid_rain", "rain", 0.55, 0.45, 0.1))
	_check(String(mid["region_pref"]) == "porch", "mid rain pref=porch", String(mid["region_pref"]))
	# 小雪且风弱：保留少量户外赏雪
	var snow_calm := _choose_at(2027, 1, 15, 10, 0, _wx("light_snow", "snow", 0.25, 0.25, 0.10))
	_check(String(snow_calm["region_pref"]) == "outdoor", "light calm snow keeps outdoor", String(snow_calm["region_pref"]))
	_check(["stroll", "swing", "sea_view", "idle"].has(String(snow_calm["kind"])), "light calm snow kind∈户外候选", String(snow_calm["kind"]))
	# 大雪（强度 > 0.62）：避雪回门廊
	var snow_heavy := _choose_at(2027, 1, 15, 10, 0, _wx("heavy_snow", "snow", 0.90, 0.40, 0.20))
	_check(String(snow_heavy["region_pref"]) == "porch", "heavy snow pref=porch", String(snow_heavy["region_pref"]))
	# 强风（无降水）：户外停留改门廊，散步改坐
	var gust := _choose_at(2026, 10, 20, 10, 0, _wx("strong_wind", "none", 0.0, 0.85, 0.35))
	_check(String(gust["region_pref"]) == "porch", "strong wind pref=porch", String(gust["region_pref"]))
	_check(String(gust["kind"]) == "sit", "strong wind stroll->sit", String(gust["kind"]))
	# 午餐窗口：室内桌边不受天气影响（仍是 eat / floor1）
	var lunch := _choose_at(2026, 7, 15, 12, 0, _wx("thunder", "rain", 0.86, 0.64, 0.85))
	_check(String(lunch["region_pref"]) == "floor1", "lunch weather-safe pref=floor1", String(lunch["region_pref"]))
	_check(String(lunch["kind"]) == "eat", "lunch kind=eat", String(lunch["kind"]))
	# 夜间：睡眠窗口优先，天气不改变睡眠与阁楼
	var night := _choose_at(2026, 7, 15, 23, 0, _wx("typhoon", "rain", 0.95, 1.0, 1.0))
	_check(String(night["kind"]) == "sleep", "night kind=sleep", String(night["kind"]))
	_check(String(night["region_pref"]) == "attic", "night pref=attic", String(night["region_pref"]))
	# 返回契约字段完整
	for key in ["kind", "duration_real", "window_id", "window_kind", "reason", "region_pref"]:
		_check(clear.has(key), "schedule result key: " + str(key))
	_check(float(clear["duration_real"]) > 0.0, "duration_real positive")

# ---------------------------------------------------------------- 无天气时行为不变

func _run_schedule_unchanged() -> void:
	# 不传 weather 键：夏天上午仍是户外散步（保持 P7 原有行为）
	var plain := _choose_at(2026, 7, 15, 10, 0, {})
	_check(String(plain["region_pref"]) == "outdoor", "no-weather pref=outdoor", String(plain["region_pref"]))
	_check(["stroll", "swing", "sea_view", "idle"].has(String(plain["kind"])), "no-weather kind∈户外候选", String(plain["kind"]))
	# 空字典与不传等价
	var empty := _choose_at(2026, 7, 15, 10, 0, {})
	_check(String(empty["region_pref"]) == String(plain["region_pref"]), "empty weather same pref")

# ---------------------------------------------------------------- 接入源码契约

func _run_source_contracts() -> void:
	var main_src := _file_text("res://scripts/main.gd")
	_check(main_src.contains('"weather": _weather_eco()'), "main: eco/villager ctx share weather snapshot")
	_check(main_src.contains("func _weather_eco()"), "main: _weather_eco helper")
	_check(main_src.contains("func _boat_weather_hold()"), "main: boat weather hold")
	_check(main_src.contains("_boat_weather_hold()"), "main: boat gate call")
	_check(main_src.contains("wx_fire"), "main: firefly weather factor")
	_check(main_src.contains("ctl.set_weather("), "main: smoke weather wiring")
	var fx_src := _file_text("res://scripts/fx.gd")
	_check(fx_src.contains("func set_weather(wind: float, rain: float, snow: float, storm: float)"), "fx: smoke set_weather")
	_check(fx_src.contains("func _update_weather_eco(ctx: Dictionary)"), "fx: bird weather eco")
	_check(fx_src.contains("_wx_bad"), "fx: bird weather gate")
	var vil_src := _file_text("res://scripts/isle_villager.gd")
	_check(vil_src.contains('"weather": _ctx.get("weather", {})'), "villager: passes weather to schedule")
	var sch_src := _file_text("res://scripts/isle_villager_schedule.gd")
	_check(sch_src.contains("wx_severe"), "schedule: severe weather filter")
	_check(sch_src.contains("wx_snow_calm"), "schedule: calm snow exception")
	# 不得另建时钟：生态接入文件里不出现新的系统时间读取
	for path in ["res://scripts/isle_villager_schedule.gd", "res://scripts/isle_villager.gd"]:
		var src := _file_text(path)
		_check(not src.contains("Time.get_unix_time_from_system"), "no second clock: " + path)
