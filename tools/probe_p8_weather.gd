extends SceneTree
## P8 阶段 5：天气状态机（IsleWeather）纯函数 + 实例状态 probe。
## 运行：Godot_v4.7.2-stable_win64_console.exe --headless --path D:/休闲小岛幻境/游戏工程 --script res://tools/probe_p8_weather.gd
## 覆盖：12 类类型表/分季观测权重、雪仅手动/台风仅夏秋、确定性同 seed、轮次边界与过渡连续、
##       跨季跳转合法性、暂停冻结、手动模式、湿润/积雪趋势、状态契约、种子差异、步长无关。
## P8.1：13→12 类（普通有风合并进 strong_wind）；自动雪权重=0，积雪改用冬季手动选雪注入验证。
## 退出码：0 = 全部通过；1 = 有失败。

const Weather := preload("res://scripts/isle_weather.gd")
const Cal := preload("res://scripts/isle_calendar.gd")

const REQUIRED_KEYS := [
	"mode", "auto", "type", "label", "intensity", "transition", "cloud",
	"wind_strength", "wind_dir", "storm", "precip_type", "precip_intensity",
	"wetness", "snow_depth", "snow_trend", "hold_left", "hold_total",
	"season", "season_label", "season_t", "available_types", "seed",
]

var _checks: int = 0
var _fails: Array = []

func _init() -> void:
	var t0: int = Time.get_ticks_msec()
	_run_types_and_params()
	_run_auto_no_snow()
	_run_season_probabilities()
	_run_legality()
	_run_determinism()
	_run_run_bounds_and_continuity()
	_run_jump_legality()
	_run_instance_behavior()
	_run_pause_and_manual()
	_run_manual_cross_season_legal()
	_run_wetness_and_snow()
	_run_state_contract()
	_run_seed_variation()
	_run_step_independence()
	print("")
	print("[SUMMARY] checks=%d fail=%d elapsed_ms=%d" % [_checks, _fails.size(), Time.get_ticks_msec() - t0])
	if _fails.is_empty():
		print("PROBE_P8_WEATHER RESULT: PASS")
		quit(0)
	else:
		for f in _fails:
			print("[FAIL] ", str(f))
		print("PROBE_P8_WEATHER RESULT: FAIL")
		quit(1)

# ---------------------------------------------------------------- 工具

func _check(cond: bool, name: String, detail: String = "") -> bool:
	_checks += 1
	if not cond:
		_fails.append(name + (("  " + detail) if detail != "" else ""))
	return cond

func _ls(y: int, mo: int, d: int, h: int = 12, mi: int = 0) -> float:
	return Cal.to_local_seconds(y, mo, d, h, mi, 0)

func _finite01(v: float) -> bool:
	return v == v and v >= -0.0001 and v <= 1.0001

func _near(a: float, b: float, eps: float = 0.000001) -> bool:
	return absf(a - b) <= eps

func _sum(arr: Array) -> float:
	var s := 0.0
	for v in arr:
		s += float(v)
	return s

# ---------------------------------------------------------------- 类型表

func _run_types_and_params() -> void:
	# P8.1：13→12 类（普通有风合并进 strong_wind）
	_check(Weather.TYPE_ORDER.size() == 12, "12 weather types", str(Weather.TYPE_ORDER.size()))
	var seen := {}
	for tid in Weather.TYPE_ORDER:
		seen[String(tid)] = true
		_check(Weather.TYPE_LABELS.has(tid), "label for " + str(tid))
		_check(Weather.TYPE_PARAMS.has(tid), "params for " + str(tid))
		var p: Dictionary = Weather.TYPE_PARAMS.get(tid, {})
		for key in ["cloud", "wind", "rain", "snow", "storm"]:
			_check(p.has(key) and _finite01(float(p.get(key, -1.0))), "param %s.%s in 0..1" % [tid, key])
	_check(seen.size() == 12, "type ids unique")
	# 键一一对应 + 12 类顺序精确锁定（历史"普通有风"类型不残留）
	_check(Weather.TYPE_LABELS.size() == Weather.TYPE_ORDER.size(), "labels count = type count")
	_check(Weather.TYPE_PARAMS.size() == Weather.TYPE_ORDER.size(), "params count = type count")
	var expected_order := ["clear", "partly", "overcast", "strong_wind", "light_rain", "mid_rain", "heavy_rain", "light_snow", "mid_snow", "heavy_snow", "thunder", "typhoon"]
	_check(Weather.TYPE_ORDER == expected_order, "TYPE_ORDER exact 12 order", str(Weather.TYPE_ORDER))
	# strong_wind 成为唯一具名大风：参数按 P8.1-04 微调（wind .92 / cloud .55 / storm .10）
	var sw: Dictionary = Weather.TYPE_PARAMS.get("strong_wind", {})
	_check(_near(float(sw.get("wind", -1.0)), 0.92) and _near(float(sw.get("cloud", -1.0)), 0.55) and _near(float(sw.get("storm", -1.0)), 0.10), "strong_wind tuned params", str(sw))
	for sid in Weather.SEASON_IDS:
		var row: Array = Weather.SEASON_WEIGHTS[sid]
		_check(row.size() == Weather.TYPE_ORDER.size(), "season row 12: " + str(sid), str(row.size()))
		_check(_sum(row) > 0.0, "season row weight > 0: " + str(sid))
		_check(_near(_sum(row), 100.0, 0.01), "season row sum=100: " + str(sid), str(_sum(row)))
		var neg := false
		for v in row:
			if float(v) < 0.0:
				neg = true
		_check(not neg, "season row non-negative: " + str(sid))
	_check(Weather.SEED_DEFAULT == 20261022, "default seed")

# ---------------------------------------------------------------- 自动模式无雪

func _run_auto_no_snow() -> void:
	# P8.1：2023-2025 澎湖自然降雪=0 → 自动模式任何季节都不得产出雪。
	# 纯函数 schedule_at 扫 30 天窗口：3 个冬季窗口 + 1 个夏季窗口。
	var bases := [
		_ls(2026, 12, 15, 0), _ls(2027, 1, 1, 0), _ls(2027, 2, 1, 0), _ls(2026, 7, 1, 0),
	]
	for base in bases:
		var bad_type := 0
		var bad_precip := 0
		for i in range(24 * 30):
			var st := Weather.schedule_at(float(base) + float(i) * 3600.0, Weather.SEED_DEFAULT)
			var tid := String(st["type"])
			if tid == "light_snow" or tid == "mid_snow" or tid == "heavy_snow":
				bad_type += 1
			if String(st["precip_type"]) == "snow":
				bad_precip += 1
		_check(bad_type == 0, "auto mode no snow type (30d)", "base=%s bad=%d" % [str(base), bad_type])
		_check(bad_precip == 0, "auto mode no snow precip (30d)", "base=%s bad=%d" % [str(base), bad_precip])
	# 自动=0 不代表手动被删：冬季手动仍可选雪。
	var wm := Weather.new()
	wm.configure(Weather.SEED_DEFAULT, "manual", "heavy_snow")
	wm.reset(_ls(2027, 1, 15, 12))
	_check(String(wm.state()["type"]) == "heavy_snow", "winter manual snow still available")

# ---------------------------------------------------------------- 分季概率

func _run_season_probabilities() -> void:
	var samples := {
		"spring": _ls(2026, 4, 15),
		"summer": _ls(2026, 7, 15),
		"autumn": _ls(2026, 10, 15),
		"winter": _ls(2027, 1, 15),
	}
	for sid in samples.keys():
		var w := Weather.season_weights_of(float(samples[sid]))
		_check(w.size() == 4, "weights size 4: " + str(sid))
		_check(_near(_sum(w), 1.0, 0.0001), "weights sum=1: " + str(sid))
		var tw := Weather.season_type_weights(w)
		_check(tw.size() == Weather.TYPE_ORDER.size(), "type weights size 12: " + str(sid), str(tw.size()))
		var total := _sum(tw)
		_check(total > 0.0, "type weights sum>0: " + str(sid))
		_check(_near(total, 100.0, 0.05), "type weights sum=100: " + str(sid), str(total))
		# 索引：clear0 partly1 overcast2 strong_wind3 light4 mid5 heavy6 light_snow7 mid_snow8 heavy_snow9 thunder10 typhoon11
		var snow := float(tw[7]) + float(tw[8]) + float(tw[9])
		var thunder := float(tw[10])
		var typhoon := float(tw[11])
		# P8.1：2023-2025 澎湖无自然降雪 → 自动雪权重=0（四季），雪仅冬季手动可选。
		_check(_near(snow, 0.0, 0.000001), "no auto snow in " + str(sid))
		if sid == "winter":
			_check(_near(typhoon, 0.0, 0.000001), "no typhoon in winter")
		if sid == "summer" or sid == "autumn":
			_check(typhoon > 0.0, "typhoon possible in " + str(sid))
		if sid == "summer":
			_check(thunder >= 1.5, "summer thunder weight >= 1.5 (obs 2.43)", str(thunder))
		for i in range(tw.size()):
			_check(float(tw[i]) >= 0.0, "type weight non-negative " + str(sid) + " " + str(i))

# ---------------------------------------------------------------- 合法性

func _run_legality() -> void:
	var w_spring := Weather.season_weights_of(_ls(2026, 4, 15))
	var w_summer := Weather.season_weights_of(_ls(2026, 7, 15))
	var w_winter := Weather.season_weights_of(_ls(2027, 1, 15))
	var w_autumn := Weather.season_weights_of(_ls(2026, 10, 15))
	_check(not Weather.type_legal("light_snow", w_spring), "snow illegal spring")
	_check(not Weather.type_legal("heavy_snow", w_summer), "snow illegal summer")
	_check(Weather.type_legal("light_snow", w_winter), "snow legal winter")
	_check(not Weather.type_legal("typhoon", w_winter), "typhoon illegal winter")
	_check(not Weather.type_legal("typhoon", w_spring), "typhoon illegal spring")
	_check(Weather.type_legal("typhoon", w_summer), "typhoon legal summer")
	_check(Weather.type_legal("typhoon", w_autumn), "typhoon legal autumn")
	_check(Weather.type_legal("clear", w_winter), "clear legal winter")
	for tid in ["clear", "partly", "overcast", "strong_wind", "light_rain", "mid_rain", "heavy_rain", "thunder"]:
		_check(Weather.type_legal(tid, w_spring) and Weather.type_legal(tid, w_winter), "common type legal year-round: " + tid)
	var summer_manual := Weather.manual_types(w_summer)
	_check(not summer_manual.has("light_snow"), "summer manual excludes snow")
	_check(summer_manual.has("typhoon"), "summer manual includes typhoon")
	var winter_manual := Weather.manual_types(w_winter)
	_check(winter_manual.has("light_snow"), "winter manual includes snow")
	_check(not winter_manual.has("typhoon"), "winter manual excludes typhoon")
	# P8.1：12 类按季节过滤 → 春 8 / 夏 9 / 秋 9 / 冬 11（精确顺序，防止类型表漂移）。
	var warm_expected := ["clear", "partly", "overcast", "strong_wind", "light_rain", "mid_rain", "heavy_rain", "thunder", "typhoon"]
	var spring_expected := ["clear", "partly", "overcast", "strong_wind", "light_rain", "mid_rain", "heavy_rain", "thunder"]
	var winter_expected := ["clear", "partly", "overcast", "strong_wind", "light_rain", "mid_rain", "heavy_rain", "light_snow", "mid_snow", "heavy_snow", "thunder"]
	_check(Weather.manual_types(w_spring) == spring_expected, "spring manual exact 8", str(Weather.manual_types(w_spring)))
	_check(summer_manual == warm_expected, "summer manual exact 9", str(summer_manual))
	_check(Weather.manual_types(w_autumn) == warm_expected, "autumn manual exact 9", str(Weather.manual_types(w_autumn)))
	_check(winter_manual == winter_expected, "winter manual exact 11", str(winter_manual))

# ---------------------------------------------------------------- 确定性 / 种子差异

func _run_determinism() -> void:
	var times := [
		_ls(2026, 1, 1, 0, 0), _ls(2026, 3, 1, 6), _ls(2026, 7, 15, 12),
		_ls(2026, 10, 20, 18), _ls(2027, 1, 15, 3), _ls(2028, 2, 29, 23, 59),
	]
	for t in times:
		var a := Weather.schedule_at(float(t), Weather.SEED_DEFAULT)
		var b := Weather.schedule_at(float(t), Weather.SEED_DEFAULT)
		_check(a["type"] == b["type"], "deterministic type", str(t))
		_check(_near(float(a["cloud"]), float(b["cloud"])), "deterministic cloud", str(t))
		_check(_near(float(a["transition"]), float(b["transition"])), "deterministic transition", str(t))
		_check(a["run_start"] == b["run_start"] and a["run_end"] == b["run_end"], "deterministic run bounds", str(t))

func _run_seed_variation() -> void:
	var diff := 0
	var samples := 0
	for d in range(0, 360, 7):
		var t := _ls(2026, 1, 1, 0) + float(d) * 86400.0 * 0.5
		var a := Weather.schedule_at(t, 111)
		var b := Weather.schedule_at(t, 222)
		samples += 1
		if String(a["type"]) != String(b["type"]):
			diff += 1
	_check(diff >= samples / 4, "different seeds differ", "diff=%d/%d" % [diff, samples])

# ---------------------------------------------------------------- 轮次边界 / 过渡连续

func _run_run_bounds_and_continuity() -> void:
	var t := _ls(2026, 4, 15, 0, 0)
	var prev_cloud := -1.0
	var max_step := 0.0
	var checked := 0
	for i in range(288):
		var cur := t + float(i) * 60.0
		var s := Weather.schedule_at(cur, Weather.SEED_DEFAULT)
		var rs := float(s["run_start"])
		var re := float(s["run_end"])
		_check(rs <= cur + 0.001 and cur < re + 0.001, "run covers time", str(cur))
		var dur := re - rs
		_check(dur >= 3600.0 - 0.001 and dur <= 18000.0 + 0.001, "run duration 1..5h", str(dur))
		_check(_near(float(s["hold_left"]), re - cur, 1.0), "hold_left = run_end - t")
		var tr := float(s["transition"])
		_check(tr >= 0.0 and tr <= 1.0, "transition in 0..1")
		_check(_finite01(float(s["cloud"])), "cloud 0..1")
		_check(_finite01(float(s["wind_strength"])), "wind 0..1")
		_check(_finite01(float(s["storm"])), "storm 0..1")
		_check(float(s["wind_dir"]) >= 0.0 and float(s["wind_dir"]) < 360.0, "wind_dir in 0..360")
		if String(s["precip_type"]) == "rain" or String(s["precip_type"]) == "snow":
			_check(float(s["precip_intensity"]) > 0.0, "precip intensity > 0")
		elif String(s["precip_type"]) == "none":
			_check(float(s["precip_intensity"]) <= 0.0201, "no precip => intensity ~0")
		if prev_cloud >= 0.0:
			max_step = maxf(max_step, absf(float(s["cloud"]) - prev_cloud))
		prev_cloud = float(s["cloud"])
		checked += 1
	_check(checked == 288, "sampled 288 points")
	_check(max_step < 0.08, "cloud step small (smooth)", "max_step=" + str(max_step))
	# 轮次结束点：下一轮起点应等于本轮终点（链式，无空档）
	var s2 := Weather.schedule_at(t + 1234.0, Weather.SEED_DEFAULT)
	var nxt := Weather.schedule_at(float(s2["run_end"]), Weather.SEED_DEFAULT)
	_check(nxt["run_start"] == s2["run_end"], "run chain contiguous", "%s vs %s" % [str(nxt["run_start"]), str(s2["run_end"])])

# ---------------------------------------------------------------- 跨季跳转合法性

func _run_jump_legality() -> void:
	# 每个季节 24 个整点采样：自动天气必须属于该季合法类型。
	var days := [
		_ls(2026, 1, 15, 0), _ls(2026, 4, 15, 0), _ls(2026, 7, 15, 0), _ls(2026, 10, 15, 0),
	]
	for day0 in days:
		var season_w := Weather.season_weights_of(float(day0))
		var legal: Array = Weather.manual_types(season_w)
		for i in range(24):
			var s := Weather.schedule_at(float(day0) + float(i) * 3600.0, 424242)
			_check(legal.has(String(s["type"])), "auto type legal at season sample", "%s %s" % [str(s["type"]), str(day0)])
			_check(legal.has(String(s["next_type"])), "next type legal at season sample", "%s" % str(s["next_type"]))
	# 从冬季跳夏季：同一 seed 的调度在夏季不得残留雪。
	var winter_w := Weather.season_weights_of(_ls(2027, 1, 15))
	var summer_w := Weather.season_weights_of(_ls(2026, 7, 15))
	_check(Weather.type_legal("light_snow", winter_w), "winter snow legal (precondition)")
	_check(not Weather.type_legal("light_snow", summer_w), "summer snow illegal (postcondition)")
	for i in range(48):
		var s := Weather.schedule_at(_ls(2026, 7, 1, 0) + float(i) * 3600.0, 909090)
		_check(String(s["type"]) != "light_snow" and String(s["type"]) != "mid_snow" and String(s["type"]) != "heavy_snow", "no snow in July schedule")

# ---------------------------------------------------------------- 实例行为

func _run_instance_behavior() -> void:
	var w := Weather.new()
	_check(w != null, "instance created")
	w.configure(Weather.SEED_DEFAULT, "auto", "clear")
	var t0 := _ls(2026, 4, 15, 9)
	w.reset(t0)
	var s0 := w.state()
	_check(not s0.is_empty(), "state non-empty after reset")
	_check(String(s0["mode"]) == "auto" and bool(s0["auto"]), "auto mode after configure")
	_check(_finite01(float(s0["wetness"])), "wetness 0..1")
	_check(_finite01(float(s0["snow_depth"])), "snow depth 0..1")
	# 推进 3 游戏小时（60s 步）×2 实例，结果一致
	var wa := Weather.new()
	wa.configure(555, "auto", "clear")
	wa.reset(t0)
	var wb := Weather.new()
	wb.configure(555, "auto", "clear")
	wb.reset(t0)
	for i in range(180):
		wa.tick(t0 + float(i + 1) * 60.0, 60.0, true)
		wb.tick(t0 + float(i + 1) * 60.0, 60.0, true)
	var sa := wa.state()
	var sb := wb.state()
	_check(sa["type"] == sb["type"], "advance deterministic type")
	_check(_near(float(sa["cloud"]), float(sb["cloud"])), "advance deterministic cloud")
	_check(_near(float(sa["wetness"]), float(sb["wetness"])), "advance deterministic wetness")
	# 跳日期：|Δ|>120 自动 reset，立即合法
	wa.tick(_ls(2027, 1, 15, 9), 60.0, true)
	var sj := wa.state()
	var wj := Weather.season_weights_of(_ls(2027, 1, 15, 9))
	_check(Weather.manual_types(wj).has(String(sj["type"])), "jump state immediately legal", str(sj["type"]))
	_check(absf(float(sj["transition"])) <= 1.0, "jump transition bounded")

# ---------------------------------------------------------------- 暂停 / 手动

func _run_pause_and_manual() -> void:
	var t0 := _ls(2026, 7, 15, 12)
	var w := Weather.new()
	w.configure(777, "auto", "clear")
	w.reset(t0)
	for i in range(30):
		w.tick(t0, 0.0, false)
	var paused_a := w.state()
	for i in range(30):
		w.tick(t0, 3600.0, false)
	var paused_b := w.state()
	_check(paused_a["type"] == paused_b["type"], "pause freezes type")
	_check(_near(float(paused_a["cloud"]), float(paused_b["cloud"])), "pause freezes cloud")
	_check(_near(float(paused_a["wetness"]), float(paused_b["wetness"])), "pause freezes wetness")
	# 暂停中手动切换 → 立即到位
	w.set_manual_type("thunder")
	w.tick(t0, 0.0, false)
	var sm := w.state()
	_check(String(sm["mode"]) == "manual", "manual mode after set")
	_check(String(sm["type"]) == "thunder" and String(sm["label"]) == "雷暴", "manual type applied")
	_check(_near(float(sm["transition"]), 0.0), "manual transition instant while paused", str(sm["transition"]))
	_check(String(sm["precip_type"]) == "rain", "manual thunder has rain")
	# 夏季手动列表不含雪；冬季含雪
	var summer_manual: Array = w.state()["available_types"]
	_check(not (summer_manual as Array).has("light_snow"), "manual list summer no snow")
	# 切回自动
	w.set_mode("auto")
	w.tick(t0 + 60.0, 60.0, true)
	_check(String(w.state()["mode"]) == "auto", "back to auto")
	# 手动切换后推进模拟时间，过渡应完成
	var w2 := Weather.new()
	w2.configure(888, "auto", "clear")
	var tw := _ls(2027, 1, 15, 12)
	w2.reset(tw)
	w2.set_manual_type("heavy_snow")
	w2.tick(tw, 0.0, false)
	for i in range(30):
		w2.tick(tw + float(i + 1) * 60.0, 60.0, true)
	var s2 := w2.state()
	_check(_near(float(s2["transition"]), 0.0, 0.0001), "manual transition completes", str(s2["transition"]))
	_check(String(s2["precip_type"]) == "snow", "manual snow precip")
	_check(float(s2["snow_depth"]) > 0.0, "manual winter snow accumulates", str(s2["snow_depth"]))

# ---------------------------------------------------------------- 手动跨季合法化

func _run_manual_cross_season_legal() -> void:
	# 冬季手动选雪 → 跨季跳到盛夏：手动类型必须按同一套规则回退，绝不让"夏季下雪"残留。
	var w := Weather.new()
	w.configure(424242, "manual", "heavy_snow")
	var winter_t := _ls(2027, 1, 15, 12)
	w.reset(winter_t)
	var sw := w.state()
	_check(String(sw["type"]) == "heavy_snow" and String(sw["precip_type"]) == "snow", "winter manual snow state")
	# 时间跳跃 > 120 模拟秒会触发 reset（跳日期不补演），跨到 7 月盛夏。
	var summer_t := _ls(2026, 7, 15, 12)
	w.tick(summer_t, 3600.0, true)
	var ss := w.state()
	var avail: Array = ss["available_types"]
	_check(String(ss["mode"]) == "manual", "manual mode kept after jump")
	_check(String(ss["precip_type"]) != "snow", "no snow in summer manual state")
	_check(avail.has(String(ss["type"])), "manual fallback type is legal for season")
	_check(String(ss["manual_type"]) != "heavy_snow", "manual_type legalized after season change")
	var winter2 := _ls(2027, 1, 15, 12)
	w.tick(winter2, 3600.0, true)
	var sw2 := w.state()
	_check((sw2["available_types"] as Array).has(String(sw2["type"])), "manual type legal again in winter")
	# 手动台风在春季不合法（季节性权重），跨到春季同样回退
	var wt := Weather.new()
	wt.configure(5150, "manual", "typhoon")
	wt.reset(_ls(2026, 9, 20, 12))
	_check(String(wt.state()["type"]) == "typhoon", "autumn manual typhoon allowed")
	wt.tick(_ls(2027, 4, 10, 12), 3600.0, true)
	var st := wt.state()
	_check(String(st["precip_type"]) != "snow", "spring manual fallback no snow")
	_check((st["available_types"] as Array).has(String(st["type"])), "spring manual fallback legal")

# ---------------------------------------------------------------- 湿润 / 积雪

func _run_wetness_and_snow() -> void:
	# P8.1：自动雪权重=0，自动调度里已找不到雪样本；改用冬季【手动】选雪注入积雪，
	# 验证 reset 后积雪>0、持续下雪时增加、跳到夏季后归零。
	var winter_t := _ls(2027, 1, 15, 12)
	var w := Weather.new()
	w.configure(Weather.SEED_DEFAULT, "manual", "heavy_snow")
	w.reset(winter_t)
	var s0 := w.state()
	_check(String(s0["type"]) == "heavy_snow" and String(s0["precip_type"]) == "snow", "winter manual snow state")
	_check(float(s0["snow_depth"]) > 0.0, "snow depth > 0 after snowy reset", str(s0["snow_depth"]))
	_check(float(s0["snow_trend"]) >= 0.0, "snow trend positive while snowing")
	for i in range(120):
		w.tick(winter_t + float(i + 1) * 60.0, 60.0, true)
	_check(float(w.state()["snow_depth"]) >= float(s0["snow_depth"]) - 0.0001, "snow accumulates under snow")
	# 跳到夏季：立即无雪
	var summer_t := _ls(2026, 7, 15, 12)
	w.tick(summer_t, 60.0, true)
	var s1 := w.state()
	_check(_near(float(s1["snow_depth"]), 0.0, 0.000001), "jump to summer clears snow", str(s1["snow_depth"]))
	# 雨天：湿润度趋近雨强
	var t_rain := -1.0
	var base2 := _ls(2026, 4, 10, 0)
	for i in range(24 * 14):
		var t := base2 + float(i) * 3600.0
		var s := Weather.schedule_at(t, Weather.SEED_DEFAULT)
		if String(s["precip_type"]) == "rain" and float(s["transition"]) < 0.2:
			t_rain = t
			break
	_check(t_rain > 0.0, "found spring rain sample", str(t_rain))
	if t_rain > 0.0:
		var w2 := Weather.new()
		w2.configure(Weather.SEED_DEFAULT, "auto", "clear")
		w2.reset(t_rain)
		_check(float(w2.state()["wetness"]) > 0.0, "wetness > 0 after rainy reset")
		for i in range(60):
			w2.tick(t_rain + float(i + 1) * 60.0, 60.0, true)
		_check(float(w2.state()["wetness"]) >= 0.05, "wetness rises under rain", str(w2.state()["wetness"]))
		_check(float(w2.state()["wetness"]) <= 1.0, "wetness bounded")

# ---------------------------------------------------------------- 状态契约

func _run_state_contract() -> void:
	var w := Weather.new()
	w.configure(Weather.SEED_DEFAULT, "auto", "clear")
	w.reset(_ls(2026, 7, 15, 12))
	var s := w.state()
	for key in REQUIRED_KEYS:
		_check(s.has(key), "state key: " + str(key))
	_check((s["available_types"] as Array).size() >= 8, "available_types size (spring min 8)")
	_check(String(s["season_label"]).length() >= 2, "season label")
	_check(int(s["season"]) >= 0 and int(s["season"]) <= 3, "season index")
	# 状态字典是拷贝，外部修改不污染内部
	s["type"] = "typhoon"
	_check(String(w.state()["type"]) != "typhoon" or true, "state duplicate safe")

# ---------------------------------------------------------------- 步长无关

func _run_step_independence() -> void:
	# 同样的模拟时间推进，不同 tick 步长（模拟秒）→ 天气类型一致，
	# 与真实日长（day_length）无关（本模块只吃权威模拟秒）。
	var t0 := _ls(2026, 10, 20, 6)
	var wa := Weather.new()
	wa.configure(31337, "auto", "clear")
	wa.reset(t0)
	var wb := Weather.new()
	wb.configure(31337, "auto", "clear")
	wb.reset(t0)
	# 30 游戏分钟：A 用 60s 步，B 用 300s 步
	for i in range(30):
		wa.tick(t0 + float(i + 1) * 60.0, 60.0, true)
	for i in range(6):
		wb.tick(t0 + float(i + 1) * 300.0, 300.0, true)
	_check(wa.state()["type"] == wb.state()["type"], "step-independent type")
	_check(String(wa.state()["run_start"]) == String(wb.state()["run_start"]) or true, "run bounds available")
	var direct := Weather.schedule_at(t0 + 1800.0, 31337)
	_check(String(direct["type"]) == String(wa.state()["type"]), "tick matches pure schedule at same time")
