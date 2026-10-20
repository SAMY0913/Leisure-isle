extends SceneTree
## T6 天文精度验证 probe。
## 运行：Godot_v4.7.2-stable_win64_console.exe --headless --path D:/休闲小岛幻境/游戏工程 --script res://tools/probe_astro6.gd
## 覆盖：10 日期误差表（NOAA 太阳 / astronomy-engine 月球 / MET Norway 第三方）、无 NaN、
##       方位 0-360、日出日落合理性、24h 连续性（相邻秒 alt 变化 <0.1°）、世界坐标映射、day_events 性能。
## 退出码：0 = 全部通过；1 = 有失败。

const DETAIL_DATES := ["2026-01-01", "2026-03-20", "2026-06-21", "2026-09-23", "2026-12-21"]
const DETAIL_MINUTES := [360, 480, 720, 1080, 1260]

const COMPUTE_KEYS := ["sun_alt", "sun_az", "sun_ha", "sun_dec", "moon_alt", "moon_az",
	"moon_illum", "moon_waxing", "moon_dist", "jd"]
const EVENT_KEYS := ["sunrise", "sunset", "noon_alt", "day_length", "moonrise", "moonset", "noon_illum"]

const REF := [
	{"date": "2026-01-01", "sun_rise": 428.086, "sun_rise_az": 114.776, "sun_set": 1072.713, "sun_set_az": 245.264, "sun_noon": 750.127, "sun_noon_alt": 43.8686, "moon_rise": 929.605, "moon_rise_az": 60.321, "moon_set": 278.678, "moon_set_az": 298.396, "moon_illum_noon": 0.9249, "met_sun_rise": 428.0, "met_sun_rise_az": 114.78, "met_sun_set": 1072.0, "met_sun_set_az": 245.26, "met_sun_noon": 750.0, "met_sun_noon_alt": 43.87, "met_moon_rise": 929.0, "met_moon_rise_az": 60.33, "met_moon_set": 278.0, "met_moon_set_az": 298.39, "met_high_moon_alt": 85.34, "met_high_moon": 1358.0},
	{"date": "2026-02-15", "sun_rise": 419.563, "sun_rise_az": 103.534, "sun_set": 1102.878, "sun_set_az": 256.644, "sun_noon": 761.098, "sun_noon_alt": 54.1907, "moon_rise": 325.268, "moon_rise_az": 117.002, "moon_set": 979.302, "moon_set_az": 244.721, "moon_illum_noon": 0.0583, "met_sun_rise": 419.0, "met_sun_rise_az": 103.54, "met_sun_set": 1102.0, "met_sun_set_az": 256.64, "met_sun_noon": 761.0, "met_sun_noon_alt": 54.19, "met_moon_rise": 325.0, "met_moon_rise_az": 117.0, "met_moon_set": 979.0, "met_moon_set_az": 244.73, "met_high_moon_alt": 42.3, "met_high_moon": 650.0},
	{"date": "2026-03-20", "sun_rise": 391.371, "sun_rise_az": 89.933, "sun_set": 1117.903, "sun_set_az": 270.284, "sun_noon": 754.614, "sun_noon_alt": 66.7051, "moon_rise": 422.202, "moon_rise_az": 82.457, "moon_set": 1196.571, "moon_set_az": 281.353, "moon_illum_noon": 0.0168, "met_sun_rise": 391.0, "met_sun_rise_az": 89.94, "met_sun_set": 1117.0, "met_sun_set_az": 270.28, "met_sun_noon": 754.0, "met_sun_noon_alt": 66.7, "met_moon_rise": 422.0, "met_moon_rise_az": 82.46, "met_moon_set": 1196.0, "met_moon_set_az": 281.35, "met_high_moon_alt": 75.36, "met_high_moon": 806.0},
	{"date": "2026-05-05", "sun_rise": 351.43, "sun_rise_az": 71.995, "sun_set": 1136.213, "sun_set_az": 288.176, "sun_noon": 743.717, "sun_noon_alt": 83.1203, "moon_rise": 1335.447, "moon_rise_az": 120.855, "moon_set": 479.896, "moon_set_az": 239.298, "moon_illum_noon": 0.8939, "met_sun_rise": 351.0, "met_sun_rise_az": 72.0, "met_sun_set": 1136.0, "met_sun_set_az": 288.17, "met_sun_noon": 743.0, "met_sun_noon_alt": 83.12, "met_moon_rise": 1335.0, "met_moon_rise_az": 120.85, "met_moon_set": 480.0, "met_moon_set_az": 239.31, "met_high_moon_alt": 38.37, "met_high_moon": 161.0},
	{"date": "2026-06-21", "sun_rise": 341.928, "sun_rise_az": 63.975, "sun_set": 1155.471, "sun_set_az": 296.026, "sun_noon": 748.59, "sun_noon_alt": 89.6834, "moon_rise": 709.935, "moon_rise_az": 87.732, "moon_set": -1, "moon_set_az": -1, "moon_illum_noon": 0.4235, "met_sun_rise": 341.0, "met_sun_rise_az": 63.98, "met_sun_set": 1155.0, "met_sun_set_az": 296.03, "met_sun_noon": 748.0, "met_sun_noon_alt": 89.69, "met_moon_rise": 709.0, "met_moon_rise_az": 87.73, "met_moon_set": -1.0, "met_moon_set_az": -1.0, "met_high_moon_alt": 67.04, "met_high_moon": 1084.0},
	{"date": "2026-07-15", "sun_rise": 350.063, "sun_rise_az": 66.05, "sun_set": 1155.61, "sun_set_az": 293.852, "sun_noon": 752.875, "sun_noon_alt": 88.3922, "moon_rise": 386.051, "moon_rise_az": 65.234, "moon_set": 1214.025, "moon_set_az": 291.781, "moon_illum_noon": 0.009, "met_sun_rise": 350.0, "met_sun_rise_az": 66.05, "met_sun_set": 1155.0, "met_sun_set_az": 293.85, "met_sun_noon": 752.0, "met_sun_noon_alt": 88.39, "met_moon_rise": 386.0, "met_moon_rise_az": 65.24, "met_moon_set": 1213.0, "met_moon_set_az": 291.78, "met_high_moon_alt": 88.26, "met_high_moon": 803.0},
	{"date": "2026-09-23", "sun_rise": 375.855, "sun_rise_az": 89.611, "sun_set": 1102.693, "sun_set_az": 270.176, "sun_noon": 739.618, "sun_noon_alt": 66.8033, "moon_rise": 976.782, "moon_rise_az": 107.109, "moon_set": 171.068, "moon_set_az": 249.952, "moon_illum_noon": 0.8697, "met_sun_rise": 375.0, "met_sun_rise_az": 89.61, "met_sun_set": 1102.0, "met_sun_set_az": 270.18, "met_sun_noon": 739.0, "met_sun_noon_alt": 66.8, "met_moon_rise": 976.0, "met_moon_rise_az": 107.1, "met_moon_set": 171.0, "met_moon_set_az": 249.96, "met_high_moon_alt": 51.86, "met_high_moon": 1319.0},
	{"date": "2026-10-10", "sun_rise": 381.661, "sun_rise_az": 96.757, "sun_set": 1086.054, "sun_set_az": 263.042, "sun_noon": 734.153, "sun_noon_alt": 60.2381, "moon_rise": 346.005, "moon_rise_az": 96.48, "moon_set": 1060.983, "moon_set_az": 260.296, "moon_illum_noon": 0.0036, "met_sun_rise": 381.0, "met_sun_rise_az": 96.76, "met_sun_set": 1086.0, "met_sun_set_az": 263.04, "met_sun_noon": 734.0, "met_sun_noon_alt": 60.24, "met_moon_rise": 345.0, "met_moon_rise_az": 96.48, "met_moon_set": 1061.0, "met_moon_set_az": 260.3, "met_high_moon_alt": 58.97, "met_high_moon": 706.0},
	{"date": "2026-11-11", "sun_rise": 397.696, "sun_rise_az": 108.542, "sun_set": 1063.83, "sun_set_az": 251.318, "sun_noon": 730.828, "sun_noon_alt": 49.4622, "moon_rise": 497.044, "moon_rise_az": 119.016, "moon_set": 1138.562, "moon_set_az": 240.235, "moon_illum_noon": 0.0352, "met_sun_rise": 397.0, "met_sun_rise_az": 108.55, "met_sun_set": 1063.0, "met_sun_set_az": 251.32, "met_sun_noon": 730.0, "met_sun_noon_alt": 49.46, "met_moon_rise": 496.0, "met_moon_rise_az": 119.01, "met_moon_set": 1138.0, "met_moon_set_az": 240.25, "met_high_moon_alt": 39.35, "met_high_moon": 818.0},
	{"date": "2026-12-21", "sun_rise": 423.419, "sun_rise_az": 115.233, "sun_set": 1066.302, "sun_set_az": 244.765, "sun_noon": 744.615, "sun_noon_alt": 43.4349, "moon_rise": 893.031, "moon_rise_az": 65.18, "moon_set": 224.406, "moon_set_az": 292.612, "moon_illum_noon": 0.8786, "met_sun_rise": 423.0, "met_sun_rise_az": 115.24, "met_sun_set": 1066.0, "met_sun_set_az": 244.77, "met_sun_noon": 744.0, "met_sun_noon_alt": 43.43, "met_moon_rise": 893.0, "met_moon_rise_az": 65.19, "met_moon_set": 224.0, "met_moon_set_az": 292.61, "met_high_moon_alt": 89.23, "met_high_moon": 1310.0},
]

var _checks: int = 0
var _fails: Array = []
var _max_errors: Dictionary = {}

func _init() -> void:
	var t0: int = Time.get_ticks_msec()
	_run_mapping_check()
	_run_range_checks()
	_run_accuracy()
	_run_continuity()
	_run_perf()
	_run_compat()
	_run_detail_dump()
	print("")
	print("[SUMMARY] checks=%d fail=%d elapsed_ms=%d" % [_checks, _fails.size(), Time.get_ticks_msec() - t0])
	if _fails.is_empty():
		print("PROBE6 RESULT: PASS")
		quit(0)
	else:
		for f in _fails:
			print("[FAIL] ", str(f))
		print("PROBE6 RESULT: FAIL")
		quit(1)

# ---------------------------------------------------------------- 工具

func _base(date: String) -> float:
	var p: PackedStringArray = date.split("-")
	return float(Time.get_unix_time_from_datetime_dict({
		"year": int(p[0]), "month": int(p[1]), "day": int(p[2]),
		"hour": 0, "minute": 0, "second": 0}))

func _check(cond: bool, name: String, detail: String = "") -> bool:
	_checks += 1
	if not cond:
		_fails.append(name + ((" " + detail) if detail != "" else ""))
	return cond

func _finite(v: float) -> bool:
	return not (is_nan(v) or is_inf(v))

func _az_err(a: float, b: float) -> float:
	return absf(fposmod(a - b + 540.0, 360.0) - 180.0)

func _upd(key: String, v: float) -> void:
	if not _max_errors.has(key) or absf(v) > absf(float(_max_errors[key])):
		_max_errors[key] = v

# ---------------------------------------------------------------- 坐标映射

func _run_mapping_check() -> void:
	# IsleMath.sun_dir：az=0 → -Z（北），az=90 → +X（东）；sky.gdshader 内部 az=atan2(x,-z) 同约定。
	var v_n: Vector3 = IsleMath.sun_dir(0.0, 0.0)
	var v_e: Vector3 = IsleMath.sun_dir(0.0, 90.0)
	_check(v_n.distance_to(Vector3(0.0, 0.0, -1.0)) < 1e-5, "map-north-is-minusZ", str(v_n))
	_check(v_e.distance_to(Vector3(1.0, 0.0, 0.0)) < 1e-5, "map-east-is-plusX", str(v_e))
	for az in [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0, 359.0]:
		var v: Vector3 = IsleMath.sun_dir(12.0, float(az))
		var back: float = fposmod(rad_to_deg(atan2(v.x, -v.z)), 360.0)
		_check(_az_err(back, float(az)) < 0.01, "map-roundtrip", "az=%.1f back=%.2f" % [float(az), back])
	print("[MAP] sun_dir: az=0 → (0,0,-1) 北, az=90 → (1,0,0) 东; shader 反解 az=atan2(x,-z) 一致")
	# HUD 罗盘 heading：相机轨道 theta 与视线真方位对拍（只记录，main.gd 修复由 Lead 执行）
	for theta_deg in [0.0, 45.0, 90.0, 180.0, 270.0]:
		var th: float = deg_to_rad(theta_deg)
		var target: Vector3 = IsleMath.CAM_TARGET
		var r: float = IsleMath.CAM_START_R
		var elev: float = 0.35
		var pos: Vector3 = target + Vector3(r * cos(elev) * sin(th), r * sin(elev), r * cos(elev) * cos(th))
		var dir: Vector3 = (target - pos).normalized()
		var true_bearing: float = fposmod(rad_to_deg(atan2(dir.x, -dir.z)), 360.0)
		var old_formula: float = fposmod(rad_to_deg(atan2(dir.x, dir.z)) + 180.0, 360.0)
		print("[MAP] theta=%5.1f° 视线真方位=%6.1f° main.gd旧heading=%6.1f° 应为=%6.1f°" % [theta_deg, true_bearing, old_formula, true_bearing])

# ---------------------------------------------------------------- 区间/合理性

func _run_range_checks() -> void:
	for d in DETAIL_DATES:
		var base: float = _base(d)
		var c: Dictionary = IsleAstro.compute(base + 43200.0)
		for k in COMPUTE_KEYS:
			_check(c.has(k), "compute-key " + d, k)
		_check(_finite(float(c["sun_alt"])) and absf(float(c["sun_alt"])) <= 90.0, "sun_alt-range " + d, str(c["sun_alt"]))
		_check(_finite(float(c["moon_alt"])) and absf(float(c["moon_alt"])) <= 90.0, "moon_alt-range " + d, str(c["moon_alt"]))
		_check(float(c["sun_az"]) >= 0.0 and float(c["sun_az"]) < 360.0, "sun_az-0-360 " + d, str(c["sun_az"]))
		_check(float(c["moon_az"]) >= 0.0 and float(c["moon_az"]) < 360.0, "moon_az-0-360 " + d, str(c["moon_az"]))
		_check(float(c["moon_illum"]) >= 0.0 and float(c["moon_illum"]) <= 1.0, "illum-0-1 " + d, str(c["moon_illum"]))
		var ev: Dictionary = IsleAstro.day_events(base + 43200.0)
		for k in EVENT_KEYS + ["sunrise_az", "sunset_az", "noon_az", "noon_time", "civil_dawn", "civil_dusk",
				"nautical_dawn", "nautical_dusk", "astronomical_dawn", "astronomical_dusk",
				"moonrise_az", "moonset_az"]:
			_check(ev.has(k), "events-key " + d, k)
		var sr: float = float(ev["sunrise"])
		var ss: float = float(ev["sunset"])
		var noon: float = float(ev["noon_time"])
		_check(sr > 0.0 and sr < 1440.0, "sunrise-sane " + d, str(sr))
		_check(ss > 0.0 and ss < 1440.0, "sunset-sane " + d, str(ss))
		_check(sr > 0.0 and ss > sr and ss - sr > 600.0 and ss - sr < 900.0, "day-length-sane " + d, str(ss - sr))
		_check(absf(float(ev["day_length"]) - (ss - sr)) < 1e-6, "day_length-consistency " + d)
		_check(noon > sr and noon < ss, "noon-between " + d)
		var order: Array = [float(ev["astronomical_dawn"]), float(ev["nautical_dawn"]), float(ev["civil_dawn"]),
			sr, noon, ss, float(ev["civil_dusk"]), float(ev["nautical_dusk"]), float(ev["astronomical_dusk"])]
		var ordered: bool = true
		for i in range(1, order.size()):
			if float(order[i]) <= float(order[i - 1]):
				ordered = false
		_check(ordered, "twilight-order " + d, str(order))
		var mr: float = float(ev["moonrise"])
		var ms: float = float(ev["moonset"])
		_check((mr < 0.0) or (mr >= 0.0 and mr <= 1440.0), "moonrise-sane " + d, str(mr))
		_check((ms < 0.0) or (ms >= 0.0 and ms <= 1440.0), "moonset-sane " + d, str(ms))
		# 事件处的实际高度必须等于判据
		if sr > 0.0:
			var cs: Dictionary = IsleAstro.compute(base + sr * 60.0)
			_check(absf(float(cs["sun_alt"]) - IsleAstro.SUN_RISE_ALT) < 0.01, "sunrise-threshold " + d, str(cs["sun_alt"]))
		if mr > 0.0:
			var cm: Dictionary = IsleAstro.compute(base + mr * 60.0)
			var want: float = -(IsleAstro.MOON_REFRACTION + float(cm["moon_sd"]))
			# day_events 用截断级数求根（升没时刻误差 <15s），与完整模型高度差可达 ~0.05°
			_check(absf(float(cm["moon_alt"]) - want) < 0.1, "moonrise-threshold " + d, "alt=%.4f want=%.4f" % [float(cm["moon_alt"]), want])

# ---------------------------------------------------------------- 精度误差表

func _run_accuracy() -> void:
	print("[ACC] 参考：NOAA solcalc（太阳时刻/方位/正午高度）、astronomy-engine 2.1.19（月球升落/方位/照度）、MET Norway sunrise 3.0（第三方时刻/方位）")
	print("[ACC] date        sunRise_min sunSet_min sunNoon_min sunRiseAz sunSetAz sunNoonAlt | moonRise_min moonSet_min moonRiseAz moonSetAz moonIllum | MET_sunAzRise MET_sunAzSet MET_moonAzRise MET_moonAzSet")
	for row in REF:
		var d: String = String(row["date"])
		var base: float = _base(d)
		var ev: Dictionary = IsleAstro.day_events(base + 43200.0)
		var noon_c: Dictionary = IsleAstro.compute(base + float(ev["noon_time"]) * 60.0)
		var e_sr: float = float(ev["sunrise"]) - float(row["sun_rise"])
		var e_ss: float = float(ev["sunset"]) - float(row["sun_set"])
		var e_sn: float = float(ev["noon_time"]) - float(row["sun_noon"])
		var e_sraz: float = _az_err(float(ev["sunrise_az"]), float(row["sun_rise_az"]))
		var e_ssaz: float = _az_err(float(ev["sunset_az"]), float(row["sun_set_az"]))
		var e_snalt: float = float(noon_c["sun_alt"]) - float(row["sun_noon_alt"])
		var has_mr: bool = float(row["moon_rise"]) > 0.0
		var has_ms: bool = float(row["moon_set"]) > 0.0
		var e_mr: float = 0.0
		var e_ms: float = 0.0
		var e_mraz: float = 0.0
		var e_msaz: float = 0.0
		if has_mr and float(ev["moonrise"]) > 0.0:
			e_mr = float(ev["moonrise"]) - float(row["moon_rise"])
			e_mraz = _az_err(float(ev["moonrise_az"]), float(row["moon_rise_az"]))
		if has_ms and float(ev["moonset"]) > 0.0:
			e_ms = float(ev["moonset"]) - float(row["moon_set"])
			e_msaz = _az_err(float(ev["moonset_az"]), float(row["moon_set_az"]))
		var e_mil: float = float(ev["noon_illum"]) - float(row["moon_illum_noon"])
		var met_sraz: float = _az_err(float(ev["sunrise_az"]), float(row["met_sun_rise_az"]))
		var met_ssaz: float = _az_err(float(ev["sunset_az"]), float(row["met_sun_set_az"]))
		var met_mraz: float = 0.0
		var met_msaz: float = 0.0
		if float(row["met_moon_rise"]) > 0.0:
			met_mraz = _az_err(float(ev["moonrise_az"]), float(row["met_moon_rise_az"]))
		if float(row["met_moon_set"]) > 0.0:
			met_msaz = _az_err(float(ev["moonset_az"]), float(row["met_moon_set_az"]))
		print("[ACC] %s %10.3f %10.3f %11.3f %9.3f %8.3f %10.3f | %12.3f %11.3f %10.3f %9.3f %9.4f | %13.3f %11.3f %14.3f %13.3f" % [
			d, e_sr, e_ss, e_sn, e_sraz, e_ssaz, e_snalt,
			e_mr, e_ms, e_mraz, e_msaz, e_mil,
			met_sraz, met_ssaz, met_mraz, met_msaz])
		# 判据
		_check(absf(e_sr) <= 2.0, "acc-sunrise<=2min " + d, "%.3f" % e_sr)
		_check(absf(e_ss) <= 2.0, "acc-sunset<=2min " + d, "%.3f" % e_ss)
		_check(absf(e_sn) <= 1.0, "acc-sunnoon<=1min " + d, "%.3f" % e_sn)
		_check(e_sraz <= 0.3 and e_ssaz <= 0.3, "acc-sunaz<=0.3deg " + d, "%.3f/%.3f" % [e_sraz, e_ssaz])
		_check(absf(e_snalt) <= 0.1, "acc-noonalt<=0.1deg " + d, "%.3f" % e_snalt)
		_check(has_mr == (float(ev["moonrise"]) > 0.0), "acc-moonrise-availability " + d)
		_check(has_ms == (float(ev["moonset"]) > 0.0), "acc-moonset-availability " + d)
		if has_mr and float(ev["moonrise"]) > 0.0:
			_check(absf(e_mr) <= 10.0, "acc-moonrise<=10min " + d, "%.3f" % e_mr)
			_check(e_mraz <= 1.0, "acc-moonriseaz<=1deg " + d, "%.3f" % e_mraz)
		if has_ms and float(ev["moonset"]) > 0.0:
			_check(absf(e_ms) <= 10.0, "acc-moonset<=10min " + d, "%.3f" % e_ms)
			_check(e_msaz <= 1.0, "acc-moonsetaz<=1deg " + d, "%.3f" % e_msaz)
		_check(absf(e_mil) <= 0.02, "acc-moonillum<=0.02 " + d, "%.4f" % e_mil)
		_check(met_sraz <= 0.3 and met_ssaz <= 0.3, "acc-met-sunaz<=0.3 " + d, "%.3f/%.3f" % [met_sraz, met_ssaz])
		if float(row["met_moon_rise"]) > 0.0:
			_check(met_mraz <= 1.0, "acc-met-moonriseaz<=1 " + d, "%.3f" % met_mraz)
		if float(row["met_moon_set"]) > 0.0:
			_check(met_msaz <= 1.0, "acc-met-moonsetaz<=1 " + d, "%.3f" % met_msaz)
		_upd("sunrise_min", e_sr)
		_upd("sunset_min", e_ss)
		_upd("sunnoon_min", e_sn)
		_upd("sun_az", maxf(e_sraz, e_ssaz))
		_upd("moonrise_min", e_mr)
		_upd("moonset_min", e_ms)
		_upd("moon_az", maxf(e_mraz, e_msaz))
		_upd("noon_alt", e_snalt)
		_upd("moon_illum", e_mil)
	print("[ACC] 最大误差: sunrise=%.3fmin sunset=%.3fmin sunnoon=%.3fmin sun_az=%.3f° noon_alt=%.3f° moonrise=%.3fmin moonset=%.3fmin moon_az=%.3f° moon_illum=%.4f" % [
		float(_max_errors.get("sunrise_min", 0.0)), float(_max_errors.get("sunset_min", 0.0)),
		float(_max_errors.get("sunnoon_min", 0.0)), float(_max_errors.get("sun_az", 0.0)),
		float(_max_errors.get("noon_alt", 0.0)), float(_max_errors.get("moonrise_min", 0.0)),
		float(_max_errors.get("moonset_min", 0.0)), float(_max_errors.get("moon_az", 0.0)),
		float(_max_errors.get("moon_illum", 0.0))])

# ---------------------------------------------------------------- 24h 连续性

func _run_continuity() -> void:
	var worst_sun: float = 0.0
	var worst_sun_at: String = ""
	for d in DETAIL_DATES:
		var base: float = _base(d)
		var prev: float = IsleAstro._sun_alt_at(IsleAstro.jd_from_local(base))
		for s in range(1, 86401):
			var alt: float = IsleAstro._sun_alt_at(IsleAstro.jd_from_local(base + float(s)))
			var dv: float = absf(alt - prev)
			if dv > worst_sun:
				worst_sun = dv
				worst_sun_at = "%s+%ds" % [d, s]
			prev = alt
	print("[CONT] 太阳 1 秒步长 24h 最大相邻高度变化 = %.6f° (%s)" % [worst_sun, worst_sun_at])
	_check(worst_sun < 0.1, "continuity-sun-1s<0.1deg", "%.6f" % worst_sun)
	# 月亮计算较贵：单日 1 秒步长验证（另 4 天 10 秒步长）
	var worst_moon: float = 0.0
	var moon_base: float = _base("2026-06-21")
	var pm: float = IsleAstro._moon_alt_at(IsleAstro.jd_from_local(moon_base))
	for s in range(1, 86401):
		var alt2: float = IsleAstro._moon_alt_at(IsleAstro.jd_from_local(moon_base + float(s)))
		var dv2: float = absf(alt2 - pm)
		if dv2 > worst_moon:
			worst_moon = dv2
		pm = alt2
	print("[CONT] 月亮 1 秒步长 24h 最大相邻高度变化 = %.6f°" % worst_moon)
	_check(worst_moon < 0.1, "continuity-moon-1s<0.1deg", "%.6f" % worst_moon)
	var worst_moon10: float = 0.0
	for d in ["2026-01-01", "2026-03-20", "2026-09-23", "2026-12-21"]:
		var b: float = _base(d)
		var p10: float = IsleAstro._moon_alt_at(IsleAstro.jd_from_local(b))
		for s in range(10, 86401, 10):
			var a10: float = IsleAstro._moon_alt_at(IsleAstro.jd_from_local(b + float(s)))
			worst_moon10 = maxf(worst_moon10, absf(a10 - p10))
			p10 = a10
	print("[CONT] 月亮 10 秒步长 其余 4 日最大相邻高度变化 = %.6f° (按比例折算 1 秒约 %.6f°)" % [worst_moon10, worst_moon10 / 10.0])
	_check(worst_moon10 < 0.1, "continuity-moon-10s<0.1deg", "%.6f" % worst_moon10)

# ---------------------------------------------------------------- 性能

func _run_perf() -> void:
	var cold: Array = []
	for i in range(8):
		var base: float = _base("2027-01-%02d" % (5 + i)) + 43200.0
		var t0: int = Time.get_ticks_usec()
		var ev: Dictionary = IsleAstro.day_events(base)
		var dt: float = float(Time.get_ticks_usec() - t0) / 1000.0
		cold.append(dt)
		_check(not ev.is_empty() and ev.has("sunrise"), "perf-events", str(i))
	var csum: float = 0.0
	var cmax: float = 0.0
	for v in cold:
		csum += float(v)
		cmax = maxf(cmax, float(v))
	var tw0: int = Time.get_ticks_usec()
	var ev2: Dictionary = IsleAstro.day_events(_base("2027-01-12") + 43200.0)
	var warm: float = float(Time.get_ticks_usec() - tw0) / 1000.0
	_check(not ev2.is_empty(), "perf-warm-events")
	print("[PERF] day_events 冷启动 avg=%.3fms max=%.3fms | 缓存命中 warm=%.4fms (目标冷 <5ms)" % [csum / float(cold.size()), cmax, warm])
	_check(cmax < 5.0, "perf-cold<5ms", "max=%.3f" % cmax)
	_check(warm < 0.5, "perf-warm<0.5ms", "%.4f" % warm)

# ---------------------------------------------------------------- 兼容性

func _run_compat() -> void:
	var base: float = _base("2026-06-21") + 43200.0
	var c: Dictionary = IsleAstro.compute(base)
	for k in COMPUTE_KEYS:
		_check(c.has(k), "compat-compute-key", k)
	_check(typeof(c["moon_waxing"]) == TYPE_BOOL, "compat-moon_waxing-bool")
	var ev: Dictionary = IsleAstro.day_events(base)
	for k in EVENT_KEYS:
		_check(ev.has(k), "compat-events-key", k)
	_check(float(ev["day_length"]) > 0.0, "compat-day_length>0")
	# 新增字段（只增不改）
	for k in ["civil_dawn", "civil_dusk", "nautical_dawn", "nautical_dusk",
			"astronomical_dawn", "astronomical_dusk", "noon_time", "sunrise_az", "sunset_az",
			"noon_az", "moonrise_az", "moonset_az"]:
		_check(ev.has(k), "compat-new-key", k)

# ---------------------------------------------------------------- 明细输出

func _run_detail_dump() -> void:
	for d in DETAIL_DATES:
		var base: float = _base(d)
		for m in DETAIL_MINUTES:
			var c: Dictionary = IsleAstro.compute(base + float(m) * 60.0)
			print("[COMPUTE] %s %4d sun(alt=%7.2f az=%6.2f) moon(alt=%7.2f az=%6.2f illum=%.3f waxing=%s)" % [
				d, m, float(c["sun_alt"]), float(c["sun_az"]), float(c["moon_alt"]),
				float(c["moon_az"]), float(c["moon_illum"]), str(c["moon_waxing"])])
		var ev: Dictionary = IsleAstro.day_events(base + 43200.0)
		print("[EVENTS] %s %s" % [d, JSON.stringify(ev)])
