extends SceneTree
## T7 天文交叉校验与时间系统回归探针（P6 收尾 / task-6 / teammate astro）
## 运行（headless）：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path "D:/休闲小岛幻境/游戏工程" --script res://tools/probe_astro_xcheck_t7.gd
## 输出：RAW <date> EVENTS <json> / RAW <date> <minute> <json> / RAWT / RAWN / RAWP + [OK]/[FAIL]/[MEASURE]
## 参考数据比对在 node 侧 开发产物/logs/astro/compare_t7.js 完成（本探针不读外部文件）。
## 只读探针：不修改 isle_astro.gd / main.gd；发现 BUG 以 [KNOWN-BUG] 单独计数，退出码仍可为 0。
## 退出码：0 = 无未预期失败；1 = 有 [FAIL]。已知缺陷单独计数并写入报告。

const DAY := 86400.0
const SUN_RISE_ALT := -0.8333
const MOON_REFRACTION := 0.5667
const SAMPLE_MINUTES := [360, 480, 540, 660, 720, 780, 900, 1020, 1080, 1140, 1260]
const DAY_LENGTHS := [60, 300, 600, 900, 1200, 1500, 1800, 2400, 2700, 3600]
const QUARTER_KINDS := {"new": 0, "first_quarter": 1, "full": 2, "last_quarter": 3}
const QUARTERS := [
	[1767434606, 2],
	[1768060143, 3],
	[1768765959, 0],
	[1769402876, 1],
	[1769983790, 2],
	[1770641026, 3],
	[1771329707, 0],
	[1771936089, 1],
	[1772537912, 2],
	[1773221948, 3],
	[1773883446, 0],
	[1774466296, 1],
	[1775095957, 2],
	[1775796738, 3],
	[1776426742, 0],
	[1776997938, 1],
	[1777656228, 2],
	[1778361063, 3],
	[1778961692, 0],
	[1779534689, 1],
	[1780217148, 2],
	[1780912860, 3],
	[1781492079, 0],
	[1782078958, 1],
	[1782777438, 2],
	[1783452569, 3],
	[1784022244, 0],
	[1784631971, 1],
	[1785335779, 2],
	[1785982919, 3],
	[1786556231, 0],
	[1787194018, 1],
	[1787890746, 2],
	[1788508302, 3],
	[1789097248, 0],
	[1789764265, 1],
	[1790441372, 2],
	[1791033934, 3],
	[1791647437, 0],
	[1792339999, 1],
	[1792987936, 2],
	[1793564939, 3],
	[1794207762, 0],
	[1794916107, 1],
	[1795532044, 2],
	[1796105355, 3],
	[1796777551, 0],
	[1797486195, 1],
	[1798075725, 2],
	[1798657207, 3],
]

var _pass := 0
var _fail := 0
var _skips := 0
var _known := 0
var _meas := {}
var _raw_lines := 0
var _m: Node = null

func _initialize() -> void:
	print("=== T7 ASTRO XCHECK PROBE START ===")
	_print_conventions()
	var t_start: int = Time.get_ticks_msec()
	if OS.get_environment("PROBE_PHASE") == "B":
		print("[PHASE-A] SKIPPED via PROBE_PHASE=B")
	else:
		_run_phase_a()
		var elapsed_a: int = Time.get_ticks_msec() - t_start
		print("[PHASE-A] elapsed_ms=%d pass=%d fail=%d skip=%d known=%d" % [elapsed_a, _pass, _fail, _skips, _known])
	await _run_phase_b()
	var elapsed: int = Time.get_ticks_msec() - t_start
	_print_summary(elapsed)
	quit(0 if _fail == 0 else 1)

func _print_conventions() -> void:
	print("[CONV] 角度单位：对外全部为度（deg）。")
	print("[CONV] 方位角：从正北起、向东为正（0=N,90=E,180=S,270=W）；isle_astro._horizon 用 az=fposmod(atan2(-cos(dec)sin(H), sin(dec)cos(lat)-cos(dec)sin(lat)cos(H)),360)。")
	print("[CONV] 太阳高度=几何高度（不含大气折射）；月亮高度=经 Meeus 40.2/40.3 站心视差修正后的几何高度（不含折射）。")
	print("[CONV] 日出/日落阈值 sun_alt=-0.8333°；月出/月落阈值 moon_alt=-(0.5667+sd)，sd=asin(1737.4/dist_km)。")
	print("[CONV] 晨昏阈值：民用 -6°、航海 -12°、天文 -18°。")
	print("[CONV] 时间输入 local_seconds = Asia/Shanghai 当地秒（Unix 秒 + 28800）；jd=(local_seconds-28800)/86400+2440587.5。模型固定广州 LAT=23.1291,LON=113.2644。")
	print("[CONV] 世界映射：IsleMath.sun_dir(alt,az)=(cos alt sin az, sin alt, -cos alt cos az)。")

# ------------------------------------------------------------------ 基础工具
func _check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("  [OK] ", msg)
	else:
		_fail += 1
		print("  [FAIL] ", msg)

func _checkq(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  [FAIL] ", msg)

func _skip(msg: String) -> void:
	_skips += 1
	print("  [SKIP] ", msg)

func _upd(key: String, err: float, at: String) -> void:
	var cur = _meas.get(key, null)
	if cur == null or err > float(cur["max"]):
		_meas[key] = {"max": err, "at": at}

func _adiff(a: float, b: float) -> float:
	return fposmod(a - b + 180.0, 360.0) - 180.0

func _angle_delta(a: float, b: float) -> float:
	return fposmod(a - b + PI, TAU) - PI

func _base(date: String) -> float:
	var p := date.split("-")
	return float(Time.get_unix_time_from_datetime_dict({"year": int(p[0]), "month": int(p[1]), "day": int(p[2]), "hour": 0, "minute": 0, "second": 0}))

func _date_str(local_seconds: float) -> String:
	var dt := Time.get_datetime_dict_from_unix_time(int(local_seconds))
	return "%04d-%02d-%02d" % [int(dt["year"]), int(dt["month"]), int(dt["day"])]

func _probe_dates() -> Array:
	var arr: Array = []
	var t0 := _base("2026-01-01")
	for i in 53:
		arr.append(t0 + float(i) * 7.0 * DAY)
	for s in ["2026-03-20", "2026-06-21", "2026-09-23", "2026-12-21"]:
		var tt := _base(s)
		if not arr.has(tt):
			arr.append(tt)
	return arr

func _ev_same(a: Dictionary, b: Dictionary) -> bool:
	for k in a.keys():
		if not b.has(k):
			return false
		if absf(float(a[k]) - float(b[k])) > 1e-9:
			return false
	return true

func _emit_events(d: String, ev: Dictionary) -> void:
	var j := {}
	for key in ["sunrise", "sunset", "noon_time", "sunrise_az", "sunset_az", "noon_alt", "noon_az", "moonrise", "moonset", "moonrise_az", "moonset_az", "noon_illum", "day_length", "civil_dawn", "civil_dusk", "nautical_dawn", "nautical_dusk", "astronomical_dawn", "astronomical_dusk"]:
		j[key] = float(ev[key])
	print("RAW %s EVENTS %s" % [d, JSON.stringify(j)])
	_raw_lines += 1

func _emit_sample(d: String, minute: int, c: Dictionary) -> void:
	var j := {
		"sun_alt": float(c["sun_alt"]),
		"sun_az": float(c["sun_az"]),
		"moon_alt": float(c["moon_alt"]),
		"moon_az": float(c["moon_az"]),
		"moon_illum": float(c["moon_illum"]),
		"moon_phase_angle": float(c["moon_phase_angle"]),
		"moon_dist": float(c["moon_dist"]),
		"moon_sd": float(c["moon_sd"]),
		"moon_waxing": bool(c["moon_waxing"]),
	}
	print("RAW %s %d %s" % [d, minute, JSON.stringify(j)])
	_raw_lines += 1

func _emit_rawt(d: String, key: String, alt: float, thr: float, err: float) -> void:
	print("RAWT %s %s %s" % [d, key, JSON.stringify({"alt": alt, "thr": thr, "err": err})])

# ------------------------------------------------------------------ Phase A
func _run_phase_a() -> void:
	print("--- PHASE A: 天文模型参考输出 + 内部一致性 ---")
	_phase_a_units_and_azimuth()
	_phase_a_events_and_samples()
	_phase_a_cache_and_rollover()
	_phase_a_continuity()
	_phase_a_phase_and_quarters()
	_phase_a_perf_and_determinism()

func _phase_a_units_and_azimuth() -> void:
	print("  [A1] 输入输出约定 / 单位 / 方位方向 / 正午几何")
	var t0 := _base("2026-03-20")
	var jd := IsleAstro.jd_from_local(t0)
	var jd_expect := (t0 - 28800.0) / 86400.0 + 2440587.5
	_check(absf(jd - jd_expect) <= 1e-9, "jd_from_local 与约定一致（固定 UTC+8）：jd=%.9f" % jd)
	var g0 := IsleAstro._gmst_deg(jd)
	var dg := fposmod(IsleAstro._gmst_deg(jd + 1.0) - g0 + 360.0, 360.0)
	_check(absf(dg - 0.98564736629) <= 1e-4, "GMST 每太阳日推进 %.6f°（恒星日超出 360° 部分）" % dg)
	var c0 := IsleAstro.compute(t0)
	var c1 := IsleAstro.compute(t0 + 43200.0)
	var finite_ok := true
	for name in ["sun_alt", "sun_az", "sun_ha", "sun_dec", "sun_dist", "moon_alt", "moon_az", "moon_illum", "moon_dist", "moon_parallax", "moon_sd", "moon_phase_angle"]:
		if not is_finite(float(c0[name])):
			finite_ok = false
			print("  [FAIL] compute 字段非有限：%s" % name)
	_check(finite_ok, "compute 全部字段有限（无 NaN/Inf）")
	_check(float(c1["sun_alt"]) >= -90.0 and float(c1["sun_alt"]) <= 90.0 and float(c1["sun_az"]) >= 0.0 and float(c1["sun_az"]) < 360.0, "太阳高度在 [-90,90]、方位在 [0,360)（度）")
	_check(float(c0["moon_illum"]) >= 0.0 and float(c0["moon_illum"]) <= 1.0, "moon_illum 在 0..1")
	var dec_r := deg_to_rad(float(c1["sun_dec"]))
	var ha_r := deg_to_rad(float(c1["sun_ha"]))
	var lat := deg_to_rad(23.1291)
	var alt_re := rad_to_deg(asin(clampf(sin(lat) * sin(dec_r) + cos(lat) * cos(dec_r) * cos(ha_r), -1.0, 1.0)))
	var y := -cos(dec_r) * sin(ha_r)
	var x := sin(dec_r) * cos(lat) - cos(dec_r) * sin(lat) * cos(ha_r)
	var az_re := fposmod(rad_to_deg(atan2(y, x)), 360.0)
	var e_alt := absf(alt_re - float(c1["sun_alt"]))
	var e_az := absf(_adiff(az_re, float(c1["sun_az"])))
	_upd("reconstruct_alt", e_alt, "2026-03-20 12:00")
	_upd("reconstruct_az", e_az, "2026-03-20 12:00")
	_check(e_alt <= 1e-6 and e_az <= 1e-6, "由 sun_dec/sun_ha 重建高度方位：dalt=%.6f° daz=%.6f°（单位/公式自洽）" % [e_alt, e_az])
	var ev := IsleAstro.day_events(t0 + 43200.0)
	_check(float(ev["sunrise_az"]) >= 80.0 and float(ev["sunrise_az"]) <= 100.0, "春分广州日出方位偏东 sunrise_az=%.3f°" % float(ev["sunrise_az"]))
	_check(absf(_adiff(float(ev["sunset_az"]), 270.0)) <= 10.0, "春分广州日落方位偏西 sunset_az=%.3f°" % float(ev["sunset_az"]))
	_check(absf(_adiff(float(ev["noon_az"]), 180.0)) <= 2.0, "春分正午太阳偏南 noon_az=%.3f°（方位=从北顺时针）" % float(ev["noon_az"]))
	var ev_s := IsleAstro.day_events(_base("2026-06-21") + 43200.0)
	var ev_w := IsleAstro.day_events(_base("2026-12-21") + 43200.0)
	_check(absf(_adiff(float(ev_s["noon_az"]), 0.0)) <= 5.0, "夏至正午太阳偏北 noon_az=%.3f°" % float(ev_s["noon_az"]))
	_check(float(ev_s["noon_alt"]) > 89.0, "夏至正午接近天顶 noon_alt=%.3f°" % float(ev_s["noon_alt"]))
	_check(absf(_adiff(float(ev_w["noon_az"]), 180.0)) <= 5.0, "冬至正午太阳偏南 noon_az=%.3f°" % float(ev_w["noon_az"]))
	_check(float(ev_w["noon_alt"]) >= 40.0 and float(ev_w["noon_alt"]) <= 45.0, "冬至正午高度 noon_alt=%.3f°" % float(ev_w["noon_alt"]))
	var v := IsleMath.sun_dir(37.5, 123.4)
	var alt2 := rad_to_deg(asin(clampf(v.y, -1.0, 1.0)))
	var az2 := fposmod(rad_to_deg(atan2(v.x, -v.z)), 360.0)
	_check(absf(alt2 - 37.5) <= 1e-4 and absf(_adiff(az2, 123.4)) <= 1e-4, "IsleMath.sun_dir 与 (alt,az) 往返一致（世界坐标映射约定）")

func _phase_a_events_and_samples() -> void:
	print("  [A2] 57 日期事件/采样输出（供 NOAA + astronomy-engine 比对）")
	var dates := _probe_dates()
	var absent_rise := 0
	var absent_set := 0
	var prev_rise := -1.0
	var prev_date := ""
	for t0 in dates:
		var d := _date_str(t0)
		var ev := IsleAstro.day_events(t0 + 43200.0)
		_emit_events(d, ev)
		for mnt in SAMPLE_MINUTES:
			var c := IsleAstro.compute(t0 + float(mnt) * 60.0)
			_emit_sample(d, mnt, c)
			for k in ["sun_alt", "sun_az", "moon_alt", "moon_az", "moon_illum", "moon_phase_angle", "moon_dist", "moon_sd"]:
				if not is_finite(float(c[k])):
					_checkq(false, "%s %d %s 非有限" % [d, mnt, k])
			var illum := float(c["moon_illum"])
			var pa := float(c["moon_phase_angle"])
			var exp_illum := (1.0 + cos(deg_to_rad(pa))) * 0.5
			var ie := absf(illum - exp_illum)
			_upd("illum_formula", ie, "%s %d" % [d, mnt])
			_checkq(ie <= 1e-6, "%s %d illum=(1+cos pa)/2 残差=%.6f" % [d, mnt, ie])
		var thr_map := {"sunrise": SUN_RISE_ALT, "sunset": SUN_RISE_ALT, "civil_dawn": -6.0, "civil_dusk": -6.0, "nautical_dawn": -12.0, "nautical_dusk": -12.0, "astronomical_dawn": -18.0, "astronomical_dusk": -18.0}
		for key in thr_map.keys():
			var mm := float(ev[key])
			if mm < 0.0:
				_checkq(false, "%s %s 意外缺席（广州全年应有）" % [d, key])
				continue
			var thr := float(thr_map[key])
			var c2 := IsleAstro.compute(t0 + mm * 60.0)
			var err := absf(float(c2["sun_alt"]) - thr)
			_upd("threshold_" + key, err, d)
			_checkq(err <= 0.02, "%s %s 阈值残差=%.4f° (<=0.02)" % [d, key, err])
			_emit_rawt(d, key, float(c2["sun_alt"]), thr, err)
		for key in ["moonrise", "moonset"]:
			var mm2 := float(ev[key])
			if mm2 < 0.0:
				if key == "moonrise":
					absent_rise += 1
				else:
					absent_set += 1
				continue
			var c3 := IsleAstro.compute(t0 + mm2 * 60.0)
			var sd := float(c3["moon_sd"])
			var thr2 := -(MOON_REFRACTION + sd)
			var err2 := absf(float(c3["moon_alt"]) - thr2)
			_upd("threshold_" + key, err2, d)
			_checkq(err2 <= 0.05, "%s %s 月亮阈值残差=%.4f° (<=0.05)" % [d, key, err2])
			_emit_rawt(d, key, float(c3["moon_alt"]), thr2, err2)
			var azk := "moonrise_az" if key == "moonrise" else "moonset_az"
			var ae := absf(_adiff(float(ev[azk]), float(c3["moon_az"])))
			_upd(azk + "_consistency", ae, d)
			_checkq(ae <= 0.02, "%s %s 方位复算残差=%.4f° (<=0.02)" % [d, azk, ae])
		var nt := float(ev["noon_time"])
		if nt < 0.0:
			_checkq(false, "%s 正午意外缺席" % d)
		else:
			var cn := IsleAstro.compute(t0 + nt * 60.0)
			var na := absf(float(cn["sun_alt"]) - float(ev["noon_alt"]))
			var nz := absf(_adiff(float(cn["sun_az"]), float(ev["noon_az"])))
			var nh := absf(float(cn["sun_ha"]))
			_upd("noon_alt_consistency", na, d)
			_upd("noon_az_consistency", nz, d)
			_upd("noon_ha", nh, d)
			_checkq(na <= 0.01 and nz <= 0.01 and nh <= 0.05, "%s 正午一致性 dalt=%.4f daz=%.4f ha=%.4f°" % [d, na, nz, nh])
			print("RAWN %s %s" % [d, JSON.stringify({"noon_ha": float(cn["sun_ha"]), "noon_alt": float(cn["sun_alt"]), "noon_az": float(cn["sun_az"]), "noon_time": nt})])
		var sunrise := float(ev["sunrise"])
		var sunset := float(ev["sunset"])
		if sunrise >= 0.0 and sunset >= 0.0:
			_checkq(sunrise < float(ev["noon_time"]) and float(ev["noon_time"]) < sunset, "%s 日出<正午<日落" % d)
			_checkq(float(ev["civil_dawn"]) <= sunrise and sunset <= float(ev["civil_dusk"]), "%s 民用晨昏包住日出日落" % d)
			_checkq(float(ev["astronomical_dawn"]) <= float(ev["nautical_dawn"]) and float(ev["nautical_dawn"]) <= float(ev["civil_dawn"]), "%s 晨昏次序 天文<=航海<=民用" % d)
			_checkq(float(ev["astronomical_dusk"]) >= float(ev["nautical_dusk"]) and float(ev["nautical_dusk"]) >= float(ev["civil_dusk"]), "%s 昏影次序 民用<=航海<=天文" % d)
			var dl := absf(float(ev["day_length"]) - (sunset - sunrise))
			_upd("day_length_formula", dl, d)
			_checkq(dl <= 1e-6, "%s day_length=sunset-sunrise 残差=%.6f min" % [d, dl])
			for key2 in ["sunrise", "sunset", "noon_time", "civil_dawn", "civil_dusk", "nautical_dawn", "nautical_dusk", "astronomical_dawn", "astronomical_dusk"]:
				var mv := float(ev[key2])
				_checkq(mv >= 0.0 and mv <= 1440.0, "%s %s 在本地日内 [0,1440)" % [d, key2])
			if prev_rise >= 0.0:
				_upd("sunrise_day_drift", absf(sunrise - prev_rise), d)
				_checkq(absf(sunrise - prev_rise) <= 180.0, "%s 相邻日日出漂移=%.3fs (<=180s)" % [d, absf(sunrise - prev_rise)])
			prev_rise = sunrise
			prev_date = d
	print("  [MEASURE] 日期数=%d 无月出日=%d 无月落日=%d 末日期=%s" % [dates.size(), absent_rise, absent_set, prev_date])

func _phase_a_cache_and_rollover() -> void:
	print("  [A3] 日事件缓存 / 跨日切换 / 确定性")
	var t0 := _base("2026-03-20")
	var a := IsleAstro.day_events(t0)
	var b := IsleAstro.day_events(t0 + 86399.0)
	_check(_ev_same(a, b), "同日 00:00 与 23:59:59 取到同一份 day_events（缓存/日界划分一致）")
	var c := IsleAstro.day_events(t0 + 86400.0)
	_check(not _ev_same(a, c), "次日 day_events 与当日不同")
	_check(float(c["sunrise"]) >= 0.0 and absf(float(c["sunrise"]) - float(a["sunrise"])) <= 180.0, "相邻日日出时刻漂移合理（<180s）")
	var d2 := IsleAstro.day_events(t0)
	_check(_ev_same(a, d2), "缓存被次日替换后回到原日期重算结果一致（无隐藏状态泄漏）")
	var t_s := Time.get_ticks_usec()
	for i in 200:
		IsleAstro.day_events(t0 + float(i % 12) * 1800.0)
	var warm := float(Time.get_ticks_usec() - t_s) / 200.0 / 1000.0
	_upd("day_events_warm_ms", warm, "2026-03-20")
	_check(warm <= 0.5, "day_events 缓存命中平均 %.3f ms (<=0.5)" % warm)

func _phase_a_continuity() -> void:
	print("  [A4] 连续性（日月 1s 步长 / 60s 步长 / 跨日边界）")
	var max_alt := 0.0
	var max_az := 0.0
	var max_sep := 0.0
	for ds in ["2026-03-20", "2026-06-21", "2026-09-23", "2026-12-21"]:
		var t0 := _base(ds)
		var ev := IsleAstro.day_events(t0 + 43200.0)
		for am in [float(ev["sunrise"]), float(ev["noon_time"]), float(ev["sunset"])]:
			if am < 0.0:
				continue
			var ta: float = t0 + float(am) * 60.0
			var prev := IsleAstro.compute(ta - 30.0)
			for i in 61:
				var cur := IsleAstro.compute(ta - 30.0 + float(i))
				var da := absf(float(cur["sun_alt"]) - float(prev["sun_alt"]))
				max_alt = maxf(max_alt, da)
				var vp: Vector3 = IsleMath.sun_dir(float(prev["sun_alt"]), float(prev["sun_az"]))
				var vc: Vector3 = IsleMath.sun_dir(float(cur["sun_alt"]), float(cur["sun_az"]))
				max_sep = maxf(max_sep, rad_to_deg(vp.angle_to(vc)))
				# 天顶附近方位角变化率可合法地极大（cos(alt)→0），方位角阈值只统计 alt<80° 段；
				# 全天方向连续性另用单位向量夹角 max_sep 衡量（与坐标系/方位奇点无关）。
				var a_use: float = minf(float(prev["sun_alt"]), float(cur["sun_alt"]))
				if a_use < 80.0:
					var dz := absf(_adiff(float(cur["sun_az"]), float(prev["sun_az"])))
					max_az = maxf(max_az, dz)
				prev = cur
	_upd("sun_1s_alt_jump", max_alt, "四季事件附近")
	_upd("sun_1s_az_jump", max_az, "四季事件附近 alt<80°")
	_upd("sun_1s_sep_jump", max_sep, "四季事件附近")
	_check(max_alt <= 0.01 and max_az <= 0.02 and max_sep <= 0.01, "太阳 1s 连续性 max|dalt|=%.6f° max|daz|=%.6f°(alt<80°) max|dsep|=%.6f° (<=0.01/0.02/0.01)" % [max_alt, max_az, max_sep])
	var moon_alt := 0.0
	var moon_az := 0.0
	for ds in ["2026-03-20", "2026-06-21", "2026-09-23", "2026-12-21"]:
		var t0 := _base(ds)
		var ev := IsleAstro.day_events(t0 + 43200.0)
		for key in ["moonrise", "moonset"]:
			var mm := float(ev[key])
			if mm < 0.0:
				continue
			var ta := t0 + mm * 60.0
			var prev := IsleAstro.compute(ta - 20.0)
			for i in 41:
				var cur := IsleAstro.compute(ta - 20.0 + float(i))
				var da := absf(float(cur["moon_alt"]) - float(prev["moon_alt"]))
				var dz := absf(_adiff(float(cur["moon_az"]), float(prev["moon_az"])))
				moon_alt = maxf(moon_alt, da)
				moon_az = maxf(moon_az, dz)
				prev = cur
	_upd("moon_1s_alt_jump", moon_alt, "四季月出月落附近")
	_upd("moon_1s_az_jump", moon_az, "四季月出月落附近")
	_check(moon_alt <= 0.01 and moon_az <= 0.02, "月亮 1s 连续性 max|dalt|=%.6f° max|daz|=%.6f° (<=0.01/0.02)" % [moon_alt, moon_az])
	var day_max := 0.0
	var t60 := _base("2026-03-20")
	var prev60 := IsleAstro.compute(t60)
	for i in 1440:
		var cur60 := IsleAstro.compute(t60 + float(i) * 60.0)
		day_max = maxf(day_max, absf(float(cur60["sun_alt"]) - float(prev60["sun_alt"])))
		prev60 = cur60
	_upd("sun_60s_alt_jump", day_max, "2026-03-20 全天")
	_check(day_max <= 0.35, "太阳 60s 步长全天最大 |dalt|=%.4f° (<=0.35)" % day_max)
	var boundary := _base("2026-03-21")
	var before := IsleAstro.compute(boundary - 1.0)
	var after := IsleAstro.compute(boundary)
	var bda := absf(float(after["sun_alt"]) - float(before["sun_alt"]))
	var bdz := absf(_adiff(float(after["sun_az"]), float(before["sun_az"])))
	var bmda := absf(float(after["moon_alt"]) - float(before["moon_alt"]))
	_check(bda <= 0.01 and bdz <= 0.02 and bmda <= 0.01, "跨日边界 1s 连续 dsun_alt=%.6f dsun_az=%.6f dmoon_alt=%.6f" % [bda, bdz, bmda])

func _phase_a_phase_and_quarters() -> void:
	print("  [A5] 月相/四相（2026 全年 50 次朔弦望）与相位-位置解耦")
	var counts := {"new": 0, "first": 0, "full": 0, "last": 0}
	for q in QUARTERS:
		var unix := float(q[0])
		var kind := int(q[1])
		var local := unix + 28800.0
		var c := IsleAstro.compute(local)
		var illum := float(c["moon_illum"])
		var pa := float(c["moon_phase_angle"])
		var wax := bool(c["moon_waxing"])
		if kind == 0:
			counts["new"] += 1
			# 朔/望判据须按真实几何：月球黄纬可达 5.3°，故“朔”瞬间月-日-地夹角最大约 5.3°，
			# 相位角最小约 174.7°、illum 最低约 0.0005，不能要求 pa≈180（那等于假设月球始终在黄道面）。
			_checkq(illum <= 0.003 and pa >= 173.5, "新月 illum=%.5f pa=%.3f°" % [illum, pa])
		elif kind == 2:
			counts["full"] += 1
			# 同理“望”瞬间相位角可达约 5.3°，illum 最低约 0.9979。
			_checkq(illum >= 0.995 and pa <= 6.5, "满月 illum=%.5f pa=%.3f°" % [illum, pa])
		elif kind == 1:
			counts["first"] += 1
			_checkq(absf(illum - 0.5) <= 0.02 and wax, "上弦 illum=%.5f waxing=%s pa=%.3f°" % [illum, str(wax), pa])
		else:
			counts["last"] += 1
			_checkq(absf(illum - 0.5) <= 0.02 and not wax, "下弦 illum=%.5f waxing=%s pa=%.3f°" % [illum, str(wax), pa])
		var exp_illum := (1.0 + cos(deg_to_rad(pa))) * 0.5
		_upd("illum_quarter_formula", absf(illum - exp_illum), "unix=%d" % int(unix))
		_checkq(absf(illum - exp_illum) <= 1e-6, "四相 illum 公式残差=%.6f (unix=%d)" % [absf(illum - exp_illum), int(unix)])
		for off in [0.0, 6.0, 24.0]:
			var cl := IsleAstro.compute(local + off * 3600.0)
			print("RAWP %d %d %s %s" % [int(unix), kind, str(off), JSON.stringify({
				"sun_alt": float(cl["sun_alt"]), "sun_az": float(cl["sun_az"]), "sun_dec": float(cl["sun_dec"]),
				"moon_alt": float(cl["moon_alt"]), "moon_az": float(cl["moon_az"]), "moon_illum": float(cl["moon_illum"]),
				"moon_phase_angle": float(cl["moon_phase_angle"]), "moon_dist": float(cl["moon_dist"]), "moon_sd": float(cl["moon_sd"]),
			})])
	print("  [MEASURE] 四相计数 %s" % JSON.stringify(counts))
	# 朔望瞬间的 waxing 标记数值上无定义（几何黄经差在 0/360 附近抖动，符号随机），
	# 物理可判据是“朔前 6h 为亏、朔后 6h 为盈”，故瞬间标记不判、改判两侧。
	var new_unix_w := -1.0
	for q in QUARTERS:
		if int(q[1]) == 0:
			new_unix_w = float(q[0])
			break
	if new_unix_w > 0.0:
		var w_pre := bool(IsleAstro.compute(new_unix_w + 28800.0 - 6.0 * 3600.0)["moon_waxing"])
		var w_post := bool(IsleAstro.compute(new_unix_w + 28800.0 + 6.0 * 3600.0)["moon_waxing"])
		_check(not w_pre and w_post, "朔前 6h waxing=false、朔后 6h waxing=true（相位方向正确；瞬间标记无定义故不判）")
	var full_unix := -1.0
	var new_unix := -1.0
	for q in QUARTERS:
		if int(q[1]) == 2 and full_unix < 0.0:
			full_unix = float(q[0])
		if int(q[1]) == 0 and new_unix < 0.0:
			new_unix = float(q[0])
	_check(full_unix > 0.0 and new_unix > 0.0, "找到满月与新月时刻样本")
	if full_unix > 0.0:
		var cf := IsleAstro.compute(full_unix + 28800.0)
		var cb := IsleAstro.compute(full_unix + 28800.0 - 12.0 * 3600.0)
		var ca := IsleAstro.compute(full_unix + 28800.0 + 12.0 * 3600.0)
		var il := absf(float(cb["moon_illum"]) - float(cf["moon_illum"]))
		var il2 := absf(float(ca["moon_illum"]) - float(cf["moon_illum"]))
		var dalt := absf(float(cb["moon_alt"]) - float(ca["moon_alt"]))
		_upd("full_moon_illum_12h_drift", maxf(il, il2), "unix=%d" % int(full_unix))
		_check(il <= 0.02 and il2 <= 0.02 and dalt >= 5.0, "满月±12h：照度漂移 %.4f/%.4f（<=0.02）而高度差 %.2f°（>=5）→ 相位与位置解耦" % [il, il2, dalt])
	if new_unix > 0.0:
		var cn := IsleAstro.compute(new_unix + 28800.0)
		var cnb := IsleAstro.compute(new_unix + 28800.0 - 12.0 * 3600.0)
		_check(absf(float(cnb["moon_illum"]) - float(cn["moon_illum"])) <= 0.02, "新月±12h：照度保持 <2% 漂移")
	var prev_illum := -1.0
	var jump := 0.0
	for q in QUARTERS:
		var cq := IsleAstro.compute(float(q[0]) + 28800.0 + 60.0)
		var cq2 := IsleAstro.compute(float(q[0]) + 28800.0 - 60.0)
		jump = maxf(jump, absf(float(cq["moon_illum"]) - float(cq2["moon_illum"])))
		jump = maxf(jump, absf(_adiff(float(cq["moon_az"]), float(cq2["moon_az"]))) / 100.0)
	_check(jump <= 0.02, "四相时刻 ±60s 无错误隐藏/突跳（illum<=0.02）实测 %.5f" % jump)

func _phase_a_perf_and_determinism() -> void:
	print("  [A6] 性能与确定性（未缓存日期 / compute / 重复调用）")
	var t0 := _base("2027-01-01")
	var times: Array = []
	for i in 14:
		var d := t0 + float(i) * 13.0 * DAY + 5.0 * 3600.0
		var s := Time.get_ticks_usec()
		IsleAstro.day_events(d)
		times.append(float(Time.get_ticks_usec() - s) / 1000.0)
	var sum := 0.0
	var mx := 0.0
	for v in times:
		sum += float(v)
		mx = maxf(mx, float(v))
	var avg := sum / float(times.size())
	_upd("day_events_cold_avg_ms", avg, "2027 14 未缓存日期")
	_upd("day_events_cold_max_ms", mx, "2027 14 未缓存日期")
	_check(avg <= 50.0 and mx <= 80.0, "day_events 冷启动 avg=%.2fms max=%.2fms (<=50/80)" % [avg, mx])
	print("  [MEASURE] day_events 冷启动 avg=%.2f ms max=%.2f ms" % [avg, mx])
	var t1 := Time.get_ticks_usec()
	for i in 500:
		IsleAstro.compute(_base("2026-05-05") + float(i) * 600.0)
	var cavg := float(Time.get_ticks_usec() - t1) / 500.0 / 1000.0
	_upd("compute_avg_ms", cavg, "500 次")
	_check(cavg <= 5.0, "compute 平均 %.3f ms (<=5)" % cavg)
	var ta := IsleAstro.compute(_base("2026-08-08") + 12345.0)
	var tb := IsleAstro.compute(_base("2026-08-08") + 12345.0)
	_check(JSON.stringify(ta) == JSON.stringify(tb), "compute 同输入重复调用结果逐位一致")
	var e1 := IsleAstro.day_events(_base("2026-02-02") + 3600.0)
	var e2 := IsleAstro.day_events(_base("2026-02-02") + 7200.0)
	_check(_ev_same(e1, e2), "day_events 同一天不同时刻取到一致结果")

# ------------------------------------------------------------------ Phase B
func _run_phase_b() -> void:
	print("--- PHASE B: 时间系统回归（动态 isle.tscn，headless） ---")
	await process_frame
	var ps = load("res://isle.tscn")
	if ps == null:
		_fail += 1
		print("  [FAIL] isle.tscn 加载失败")
		return
	_m = ps.instantiate()
	if _m == null:
		_fail += 1
		print("  [FAIL] isle.tscn 实例化失败")
		return
	root.add_child(_m)
	await process_frame
	await process_frame
	if not _m.has_method("_update_lighting"):
		_fail += 1
		print("  [FAIL] 主场景缺少 _update_lighting，Phase B 跳过")
		return
	_m._mode = 1
	_m._paused = false
	_m._frame_t = 0.0
	_phase_b_speed_scales()
	_phase_b_lighthouse_real()
	_phase_b_lighting()
	_phase_b_smoke()
	_phase_b_boat()
	_phase_b_birds()
	_phase_b_audio()
	_phase_b_timezone()
	_phase_b_clock_coherence()
	_m.queue_free()
	await process_frame

func _phase_b_speed_scales() -> void:
	print("  [B1] 模拟时间十档流速 → _advance_sim / _time_flow_scale / 灯塔转速")
	if not _m.has_method("_advance_sim") or not _m.has_method("_update_lighthouse_beam"):
		_skip("缺少 _advance_sim/_update_lighthouse_beam")
		return
	var base := _base("2026-03-20")
	var sim_rate_max := 0.0
	var beam_err_max := 0.0
	for dl_v in DAY_LENGTHS:
		var dl := float(dl_v)
		_m._time_source = "sim"
		_m._day_length = dl
		_m._sim_seconds = base + 12.0 * 3600.0
		_m._sim_delta = 0.0
		var before: float = float(_m._sim_seconds)
		_m._advance_sim(1.0)
		var dsim: float = float(_m._sim_seconds) - before
		var expect: float = 86400.0 / dl
		var rate_err := absf(dsim - expect)
		sim_rate_max = maxf(sim_rate_max, rate_err)
		_upd("sim_rate_err", rate_err, "day_length=%d" % dl_v)
		_checkq(rate_err <= maxf(1e-6, expect * 1e-9), "dl=%d 1 现实秒推进 %.4f 模拟秒（期望 %.4f）" % [dl_v, dsim, expect])
		var flow: float = float(_m._time_flow_scale())
		var flow_err := absf(flow - 480.0 / dl)
		_upd("time_flow_scale_err", flow_err, "day_length=%d" % dl_v)
		_checkq(flow_err <= 1e-9, "dl=%d _time_flow_scale=%.6f（期望 %.6f）" % [dl_v, flow, 480.0 / dl])
		_m._sim_delta = dsim
		_m._beam_angle = 0.0
		_m._update_lighthouse_beam(1.0)
		var expect_ang := dsim * TAU / 3600.0
		var beam_err := absf(_angle_delta(float(_m._beam_angle), expect_ang))
		beam_err_max = maxf(beam_err_max, beam_err)
		_upd("beam_inc_err", beam_err, "day_length=%d" % dl_v)
		_checkq(beam_err <= 1e-6, "dl=%d 1 现实秒光束转角 %.6f rad（期望 %.6f）" % [dl_v, float(_m._beam_angle), expect_ang])
	print("  [MEASURE] 十档流速：sim_rate_max_err=%.6f beam_inc_max_err=%.6f" % [sim_rate_max, beam_err_max])

func _phase_b_lighthouse_real() -> void:
	print("  [B2] 灯塔：现实模式 20s/圈、模拟暂停停转、角度连续")
	if _m.get("_beam_rotator") == null:
		_skip("_beam_rotator 为空")
		return
	_m._mode = 1
	_m._time_source = "real"
	_m._beam_angle = 0.0
	_m._update_lighthouse_beam(2.0)
	var expect_real := 2.0 * TAU / 20.0
	_check(absf(_angle_delta(float(_m._beam_angle), expect_real)) <= 1e-6, "现实模式 2 真实秒光束转 %.6f rad（20s/圈）" % float(_m._beam_angle))
	_m._time_source = "sim"
	_m._day_length = 480.0
	_m._sim_delta = 0.0
	var a0: float = float(_m._beam_angle)
	_m._update_lighthouse_beam(1.0)
	_check(absf(_angle_delta(float(_m._beam_angle), a0)) <= 1e-9, "模拟暂停（_sim_delta=0）光束停转")
	_m._sim_delta = 86400.0 / 480.0
	var a1: float = float(_m._beam_angle)
	_m._update_lighthouse_beam(1.0)
	var inc_sim: float = float(_m._beam_angle) - a1
	var expect_sim: float = (86400.0 / 480.0) * TAU / 3600.0
	_check(absf(_angle_delta(inc_sim, expect_sim)) <= 1e-6, "模拟恢复后 1 真实秒=180 模拟秒 → 转角 %.6f rad（期望 %.6f = 1/20 圈，连续不重置）" % [inc_sim, expect_sim])

func _phase_b_lighting() -> void:
	print("  [B3] 天空/主题调色/世界方向与天文层一致")
	_m._time_source = "sim"
	_m._day_length = 480.0
	for h in [6.0, 10.0, 12.0, 18.0, 20.0, 23.5]:
		_m._sim_seconds = _base("2026-03-20") + h * 3600.0
		_m._update_lighting()
		var c := IsleAstro.compute(float(_m._sim_seconds))
		var e1 := absf(float(_m._sun_alt) - float(c["sun_alt"]))
		var e2 := absf(_adiff(float(_m._sun_az), float(c["sun_az"])))
		_upd("scene_sun_alt_err", e1, "h=%.1f" % h)
		_upd("scene_sun_az_err", e2, "h=%.1f" % h)
		_checkq(e1 <= 1e-6 and e2 <= 1e-6, "h=%.1f _sun_alt/_sun_az 与 IsleAstro.compute 一致 dalt=%.6f daz=%.6f" % [h, e1, e2])
		var rising: bool = float(c["sun_ha"]) < 0.0
		_checkq(bool(_m._rising) == rising, "h=%.1f _rising=sun_ha<0 一致" % h)
		var theme: float = IsleMath.theme_time(float(_m._sun_alt), bool(_m._rising))
		_checkq(absf(float(_m._theme_t) - theme) <= 1e-9, "h=%.1f _theme_t 与 theme_time 一致" % h)
		var sd: Vector3 = IsleMath.sun_dir(float(_m._sun_alt), float(_m._sun_az))
		_checkq((_m._sun_dir_world as Vector3).distance_to(sd) <= 1e-6, "h=%.1f _sun_dir_world 与 sun_dir 一致" % h)
		_checkq(_m._pal is Dictionary and (_m._pal as Dictionary).size() > 0, "h=%.1f 调色板非空" % h)

func _phase_b_smoke() -> void:
	print("  [B4] 炊烟双窗口 11:00-13:00 / 17:00-19:00（左闭右开 + 1.5s 渐变）")
	var fx = _m.get("_fx")
	if fx == null or not (fx is Dictionary) or not (fx as Dictionary).has("smoke"):
		_skip("场景无 _fx.smoke")
		return
	var sm = (fx as Dictionary)["smoke"]
	var ctl = sm.get("ctl", null)
	if ctl == null:
		_skip("炊烟控制器为空")
		return
	_check(IsleFx.is_smoke_window(10.0 * 3600.0 + 59.0 * 60.0 + 59.0) == false, "10:59:59 非窗口")
	_check(IsleFx.is_smoke_window(11.0 * 3600.0) == true, "11:00:00 是窗口（左闭）")
	_check(IsleFx.is_smoke_window(11.0 * 3600.0 + 59.0 * 60.0 + 59.999) == true, "11:59:59.999 是窗口")
	_check(IsleFx.is_smoke_window(13.0 * 3600.0) == false, "13:00:00 非窗口（右开）")
	_check(IsleFx.is_smoke_window(12.0 * 3600.0 + 59.0 * 60.0 + 59.999) == true, "12:59:59.999 仍是窗口")
	_check(IsleFx.is_smoke_window(17.0 * 3600.0) == true, "17:00:00 是窗口")
	_check(IsleFx.is_smoke_window(18.0 * 3600.0 + 59.0 * 60.0 + 59.999) == true, "18:59:59.999 是窗口")
	_check(IsleFx.is_smoke_window(19.0 * 3600.0) == false, "19:00:00 非窗口")
	_check(IsleFx.is_smoke_window(86400.0 + 11.0 * 3600.0) == true, "次日 11:00 仍是窗口（按 86400 取模）")
	var t := _base("2026-03-20") + 11.0 * 3600.0 + 30.0 * 60.0
	_m._sim_seconds = t
	_m._update_smoke_clock()
	if ctl.has_method("smoke_debug"):
		var dbg: Dictionary = ctl.smoke_debug()
		var want := fposmod(t, 86400.0)
		_check(absf(float(dbg.get("sim_seconds", -1.0)) - want) <= 1e-6, "main._sim_seconds → 炊烟时钟同步（%s）" % String(dbg.get("time_label", "")))
		_check(bool(dbg.get("active_window", false)), "11:30 经 main 驱动为窗口内")
	ctl.set_sim_seconds(10.0 * 3600.0 + 59.0 * 60.0 + 59.5)
	ctl.set_sim_seconds(11.0 * 3600.0)
	var r1 := float(ctl.smoke_debug()["ratio"])
	_upd("smoke_ramp_err", absf(r1 - 0.5 / 1.5), "进入窗口 0.5s")
	_check(absf(r1 - 0.5 / 1.5) <= 0.02, "进入窗口 0.5s 后 ratio=%.3f（期望 0.333，渐变）" % r1)
	ctl.set_sim_seconds(11.0 * 3600.0 + 0.5)
	var r2 := float(ctl.smoke_debug()["ratio"])
	_check(absf(r2 - 1.0 / 1.5) <= 0.02, "再 0.5s ratio=%.3f（期望 0.667）" % r2)
	ctl.set_sim_seconds(11.0 * 3600.0 + 1.0)
	var r3 := float(ctl.smoke_debug()["ratio"])
	_check(absf(r3 - 1.0) <= 0.02, "再 0.5s ratio=%.3f（期望 1.0，满 1.5s 渐变）" % r3)
	ctl.set_sim_seconds(13.0 * 3600.0 - 0.5)
	ctl.set_sim_seconds(13.0 * 3600.0)
	var d_out: Dictionary = ctl.smoke_debug()
	_check(absf(float(d_out.get("ratio", -1.0))) <= 1e-6 and not bool(d_out.get("emitting", true)), "13:00:00 出窗 ratio=0 且停止发射")
	ctl.set_sim_seconds(13.5 * 3600.0)
	ctl.set_sim_seconds(17.0 * 3600.0)
	var d_jump: Dictionary = ctl.smoke_debug()
	_check(absf(float(d_jump.get("ratio", -1.0)) - 1.0) <= 0.02, "跨窗大跳（dt>30s）17:00 直接满强度 ratio=%.3f" % float(d_jump.get("ratio", -1.0)))
	ctl.set_sim_seconds(23.0 * 3600.0)
	ctl.set_sim_seconds(0.5 * 3600.0)
	var d_mid: Dictionary = ctl.smoke_debug()
	_check(not bool(d_mid.get("active_window", true)) and String(d_mid.get("time_label", "")).length() > 0, "跨午夜后 00:30 仍非窗口（时间标签 %s）" % String(d_mid.get("time_label", "")))

func _phase_b_boat() -> void:
	print("  [B5] 小船夜间休息窗口 18:00-次日08:00 与统一时钟")
	if not _m.has_method("_is_boat_rest_hour"):
		_skip("缺少 _is_boat_rest_hour")
		return
	_m._time_source = "sim"
	_m._day_length = 600.0
	var t0 := _base("2026-03-20")
	for cs in [[10.0, false], [18.0, true], [19.0, true], [23.0, true], [0.0, true], [7.0 + 59.0 / 60.0, true], [8.0, false], [12.0, false]]:
		_m._sim_seconds = t0 + float(cs[0]) * 3600.0
		_checkq(bool(_m._is_boat_rest_hour()) == bool(cs[1]), "%.2f 时休息时段=%s" % [float(cs[0]), str(cs[1])])
	if _m.has_method("_next_rest_end_sim"):
		_m._sim_seconds = t0 + 19.0 * 3600.0
		var end_at: float = float(_m._next_rest_end_sim())
		_check(absf(end_at - (t0 + DAY + 8.0 * 3600.0)) <= 1e-6, "19:00 下一次休息结束=次日 08:00")
		_m._sim_seconds = t0 + 7.0 * 3600.0
		var end2: float = float(_m._next_rest_end_sim())
		_check(absf(end2 - (t0 + 8.0 * 3600.0)) <= 1e-6, "07:00 下一次休息结束=当日 08:00")
	if _m.get("_sailboat") != null and _m.has_method("_enter_resting"):
		_m._day_length = 600.0
		_m._sim_seconds = t0 + 19.0 * 3600.0
		_m._enter_resting()
		_check(String(_m._boat_state) == "RESTING", "19:00 靠岸进入 RESTING")
		_check(float(_m._boat_rest_until) >= t0 + DAY + 8.0 * 3600.0 - 1e-6, "19:00 休息至少延续到次日 08:00")
		_m._sim_seconds = t0 + 10.0 * 3600.0
		_m._enter_resting()
		var dur: float = float(_m._boat_rest_until) - float(_m._sim_seconds)
		var scale: float = 86400.0 / 600.0
		_check(dur >= 18.0 * scale - 1e-3 and dur <= 40.0 * scale + 1e-3, "10:00 休息时长 %.1f 模拟秒（18..40 分钟×%.0f 倍率）" % [dur, scale])
		if _m.has_method("_sync_boat_clock"):
			_m._boat_state = "OFFSCREEN_WAIT"
			_m._boat_wait_sim = 10000.0
			_m._time_jump = -600.0
			_m._sync_boat_clock()
			_check(absf(float(_m._boat_wait_sim) - 9400.0) <= 1e-6 and absf(float(_m._time_jump)) <= 1e-6, "跳时 -600s 扣减远海等待：wait=%.1f jump=%.1f" % [float(_m._boat_wait_sim), float(_m._time_jump)])
			_m._time_jump = 0.0
			_m._boat_state = "DOCKED"
			_m._sim_seconds = t0 + 19.0 * 3600.0
			_m._sync_boat_clock()
			_check(String(_m._boat_state) == "RESTING", "DOCKED 状态在 19:00 经 _sync_boat_clock 转 RESTING")

func _phase_b_birds() -> void:
	print("  [B6] 海鸥昼夜迟滞（-2/+2 阈值，统一太阳高度）")
	var birds = _m.get("_birds")
	if birds == null:
		_skip("场景无 _birds")
		return
	birds.update_birds(0.016, -5.0)
	var st: Dictionary = birds.get_state_counts()
	_check(bool(st.get("night", false)) == true, "sun_alt=-5 → 判夜")
	birds.update_birds(0.016, 1.0)
	st = birds.get_state_counts()
	_check(bool(st.get("night", false)) == true, "sun_alt=+1 → 仍为夜（迟滞下界 -2）")
	birds.update_birds(0.016, 2.5)
	st = birds.get_state_counts()
	_check(bool(st.get("night", false)) == false, "sun_alt=+2.5 → 回日（迟滞上界 +2）")
	birds.update_birds(0.016, -1.5)
	st = birds.get_state_counts()
	_check(bool(st.get("night", false)) == false, "sun_alt=-1.5 → 仍为日（迟滞）")
	birds.update_birds(0.016, -3.0)
	st = birds.get_state_counts()
	_check(bool(st.get("night", false)) == true, "sun_alt=-3 → 判夜")
	for i in 240:
		birds.update_birds(0.05, -8.0)
	st = birds.get_state_counts()
	_upd("birds_night_perched", -float(st.get("perched", 0)), "夜间 12s 后")
	_check(int(st.get("perched", 0)) + int(st.get("landing", 0)) + int(st.get("takeoff", 0)) > 0, "夜间 12s 后海鸥处于栖息/降落过程（perched=%d landing=%d）" % [int(st.get("perched", 0)), int(st.get("landing", 0))])
	_check(int(st.get("flying", 0)) + int(st.get("airborne", 0)) >= 0, "海鸥计数无 NaN/负值异常")

func _phase_b_audio() -> void:
	print("  [B7] 环境音交叉淡化（target/env/phase/炉火开关）")
	var audio = _m.get("_audio")
	if audio == null or not audio.has_method("get_debug_info"):
		_skip("声音系统未就绪")
		return
	var info0: Dictionary = audio.get_debug_info()
	print("  [MEASURE] audio ready=%s loops_loaded=%s phase=%s fire_loaded=%s" % [str(info0.get("ready", false)), str(info0.get("loops_loaded", -1)), String(info0.get("phase", "")), str(info0.get("fire_loaded", false))])
	audio.update_audio(0.5, {"sun_alt": 20.0, "night": 0.0, "wind": 0.5, "fireplace_on": false})
	var info: Dictionary = audio.get_debug_info()
	_check(String(info.get("phase", "")) == "day", "sun_alt=20 → 相位 day（实测 %s）" % String(info.get("phase", "")))
	var loops: Array = info.get("loops", [])
	if loops.size() >= 3 and loops[0] is Dictionary and (loops[0] as Dictionary).has("target"):
		var t0v := float((loops[0] as Dictionary).get("target", -1.0))
		var t1v := float((loops[1] as Dictionary).get("target", -1.0))
		var t2v := float((loops[2] as Dictionary).get("target", -1.0))
		_upd("audio_target0_err", absf(t0v - 1.0), "day")
		_upd("audio_target1_err", absf(t1v - 0.65), "wind=0.5")
		_check(absf(t0v - 1.0) <= 0.02 and absf(t1v - 0.65) <= 0.02 and absf(t2v) <= 1e-6, "白天 target 公式：surf=%.3f wind=%.3f night=%.3f" % [t0v, t1v, t2v])
	else:
		_skip("音频 loops target 不可读（wav 缺失导致未加载）")
	for i in 24:
		audio.update_audio(0.25, {"sun_alt": -8.0, "night": 1.0, "wind": 0.2, "fireplace_on": true})
	var info_n: Dictionary = audio.get_debug_info()
	_check(String(info_n.get("phase", "")) == "night", "sun_alt=-8 → 相位 night（实测 %s）" % String(info_n.get("phase", "")))
	var loops_n: Array = info_n.get("loops", [])
	if loops_n.size() >= 3 and loops_n[2] is Dictionary and (loops_n[2] as Dictionary).has("env"):
		var env2 := float((loops_n[2] as Dictionary).get("env", -1.0))
		_upd("audio_night_env_err", absf(env2 - 1.0), "night 6s 后")
		_check(env2 >= 0.5, "夜间层 6 模拟帧后 env=%.3f 明显上升（交叉淡化生效）" % env2)
	else:
		_skip("夜层 env 不可读（wav 缺失）")
	_check(bool(audio.get("_fire_loop_on")) == true, "fireplace_on(sun_alt<2) → _fire_loop_on=true")
	audio.update_audio(0.25, {"sun_alt": 2.1, "night": 0.8, "wind": 0.2, "fireplace_on": false})
	_check(bool(audio.get("_fire_loop_on")) == false, "sun_alt>=2 → _fire_loop_on=false")

func _phase_b_timezone() -> void:
	print("  [B8] 现实时间 + 时区：天体地理位置不得随显示时区漂移（用户硬性要求）")
	if _m.get("_time_api") == null or not _m.has_method("_offset_for"):
		_skip("时间 API 未初始化")
		return
	var unix := 1773968400.0
	var utc := Time.get_datetime_dict_from_unix_time(int(unix))
	_check(int(utc.get("hour", -1)) == 1 and int(utc.get("day", -1)) == 20, "基准时刻 2026-03-20T01:00:00Z（UTC 时钟校验）")
	# T7（a43ca8c 后）：real 模式的生产语义是「天文/生态时钟固定参考时区 IsleAstro.TZ_SECONDS，
	# 所选显示时区只改 HUD/事件文本」。旧版本此处自行用 unix+所选偏移 构造 _sim_seconds（旧映射），
	# 只能复现修复前的反事实 bug，无法验证当前代码；现改为走 main 生产路径 _advance_sim/_update_lighting。
	# 旧映射保留在文末 [INFO] 反事实对照，只作 pre-fix 证据，不计入 known_bug。
	_m._time_source = "real"
	var tzs := ["Asia/Shanghai", "Asia/Tokyo", "America/New_York"]
	var res := {}
	# 段① 廉价时钟段：只走 _advance_sim（real 模式生产时钟入口）+ 显示换算，不调 _update_lighting；
	# 重渲染开销约 50ms/次，会放大跨时区系统时钟读数漂移，掩盖真正的时区语义。
	for tz in tzs:
		_m._timezone = tz
		_m._advance_sim(0.0)   # real 生产入口：_abs_unix=系统时间，_sim_seconds=_abs_unix+TZ_SECONDS
		var c := IsleAstro.compute(float(_m._sim_seconds))
		var dt: Dictionary = _m._display_datetime()
		var off: int = _m._offset_for(float(_m._abs_unix))
		var simerr: float = absf(float(_m._sim_seconds) - (float(_m._abs_unix) + float(IsleAstro.TZ_SECONDS)))
		res[tz] = {
			"off": off, "abs": float(_m._abs_unix), "sim": float(_m._sim_seconds), "simerr": simerr,
			"compute_alt": float(c["sun_alt"]), "compute_az": float(c["sun_az"]),
			"wall": "%02d:%02d" % [int(dt.get("hour", 0)), int(dt.get("minute", 0))],
			"wall_min": int(dt.get("hour", 0)) * 60 + int(dt.get("minute", 0)),
		}
		print("  [MEASURE] real tz=%s offset=%+.0fs 显示=%s sim=%.3f(abs+TZ 误差 %.4fs) compute sun_alt=%.4f° sun_az=%.4f°" % [tz, off, String(res[tz]["wall"]), float(_m._sim_seconds), simerr, float(c["sun_alt"]), float(c["sun_az"])])
	_check(absf(float(res["Asia/Shanghai"]["off"]) - 28800.0) <= 1e-6, "Asia/Shanghai 偏移 +28800s")
	_check(absf(float(res["Asia/Tokyo"]["off"]) - 32400.0) <= 1e-6, "Asia/Tokyo 偏移 +32400s")
	var ref: Dictionary = res["Asia/Shanghai"]
	var max_shift := 0.0
	var max_az := 0.0
	var max_sim_drift := 0.0
	var max_simerr := 0.0
	for tz in tzs:
		max_sim_drift = maxf(max_sim_drift, absf(float(res[tz]["sim"]) - float(ref["sim"])))
		max_simerr = maxf(max_simerr, float(res[tz]["simerr"]))
		max_shift = maxf(max_shift, absf(float(res[tz]["compute_alt"]) - float(ref["compute_alt"])))
		max_az = maxf(max_az, absf(_adiff(float(res[tz]["compute_az"]), float(ref["compute_az"]))))
	_upd("tz_sun_alt_shift", max_shift, "real 廉价时钟段（系统时间）")
	_upd("tz_sun_az_shift", max_az, "real 廉价时钟段（系统时间）")
	_upd("tz_sim_seconds_drift", max_sim_drift, "real 廉价时钟段（跨时区）")
	_upd("tz_sim_seconds_semantics_err", max_simerr, "|sim-(abs+TZ_SECONDS)|")
	print("  [MEASURE] real 廉价时钟段：max|dsim|=%.4fs max|sim-(abs+TZ)|=%.5fs max|dalt|=%.6f° max|daz|=%.6f°" % [max_sim_drift, max_simerr, max_shift, max_az])
	_checkq(max_simerr <= 0.01, "real 模式天文时钟固定参考时区：|_sim_seconds-(_abs_unix+TZ_SECONDS)|max=%.5fs≤0.01s" % max_simerr)
	_checkq(max_sim_drift <= 0.1, "切换显示时区不改变天文时钟：跨时区 |dsim|max=%.4fs≤0.1s（廉价段，系统时间毫秒漂移）" % max_sim_drift)
	_checkq(max_shift <= 0.05 and max_az <= 0.05, "切换显示时区后太阳天文位置不变（real 廉价段 max dalt=%.6f° daz=%.6f°≤0.05°）" % [max_shift, max_az])
	# 段② 生产路径段：走 main._advance_sim + main._update_lighting（真实每帧链路），校验 _update_lighting
	# 写出的 _sun_alt/_sun_az 与同一 _sim_seconds 的 IsleAstro.compute 完全一致，且跨时区场景太阳位置稳定。
	var max_scene_mismatch := 0.0
	var scene_ref_alt := 0.0
	var scene_ref_az := 0.0
	var max_scene_alt := 0.0
	var max_scene_az := 0.0
	var scene_first := true
	for tz in tzs:
		_m._timezone = tz
		_m._advance_sim(0.0)
		_m._update_lighting()
		var c2 := IsleAstro.compute(float(_m._sim_seconds))
		var mism := maxf(absf(float(_m._sun_alt) - float(c2["sun_alt"])), absf(_adiff(float(_m._sun_az), float(c2["sun_az"]))))
		max_scene_mismatch = maxf(max_scene_mismatch, mism)
		res[tz]["scene_alt"] = float(_m._sun_alt)
		res[tz]["scene_az"] = float(_m._sun_az)
		if scene_first:
			scene_ref_alt = float(_m._sun_alt)
			scene_ref_az = float(_m._sun_az)
			scene_first = false
		else:
			max_scene_alt = maxf(max_scene_alt, absf(float(_m._sun_alt) - scene_ref_alt))
			max_scene_az = maxf(max_scene_az, absf(_adiff(float(_m._sun_az), scene_ref_az)))
		print("  [MEASURE] real 生产路径 tz=%s sim=%.3f _sun_alt=%.4f° _sun_az=%.4f°（vs compute 差 %.9f°）" % [tz, float(_m._sim_seconds), float(_m._sun_alt), float(_m._sun_az), mism])
	_upd("tz_scene_sun_alt_shift", max_scene_alt, "real 生产路径 _update_lighting（跨时区）")
	_upd("tz_scene_sun_az_shift", max_scene_az, "real 生产路径 _update_lighting（跨时区）")
	_upd("tz_scene_compute_mismatch", max_scene_mismatch, "_update_lighting vs 同 _sim_seconds compute")
	print("  [MEASURE] real 生产路径：max|dalt|=%.6f° max|daz|=%.6f° max|scene-compute|=%.9f°" % [max_scene_alt, max_scene_az, max_scene_mismatch])
	_checkq(max_scene_mismatch <= 1.0e-9, "real 生产路径 _update_lighting 与同一 _sim_seconds 的 IsleAstro.compute 一致（max=%.9f°）" % max_scene_mismatch)
	_checkq(max_scene_alt <= 0.05 and max_scene_az <= 0.05, "切换显示时区后 _update_lighting 太阳位置不变（生产路径 max dalt=%.6f° daz=%.6f°≤0.05°）" % [max_scene_alt, max_scene_az])
	# 显示层：墙钟必须按所选时区偏移换算（显示调整允许，天体不随之移动，模 24h 比较）
	var max_wall_err := 0.0
	var off_ref: int = int(ref["off"])
	var off_ref_min: int = int(float(off_ref) / 60.0)
	for tz in tzs:
		var off_tz_min: int = int(float(int(res[tz]["off"])) / 60.0)
		var want_min: int = int(fposmod(float(int(ref["wall_min"]) - off_ref_min + off_tz_min), 1440.0))
		var got_min: int = int(res[tz]["wall_min"])
		var e: float = absf(fposmod(float(got_min - want_min) + 720.0, 1440.0) - 720.0)
		max_wall_err = maxf(max_wall_err, e)
		print("  [MEASURE] real tz=%s 墙钟=%s（按 offset 换算期望 %02d:%02d，误差 %.2fmin）" % [tz, String(res[tz]["wall"]), want_min / 60, want_min % 60, e])
	_upd("tz_display_wall_err_min", max_wall_err, "real 生产路径（模 24h）")
	_checkq(max_wall_err <= 1.0, "显示墙钟按所选时区偏移换算（模 24h 最大误差 %.2fmin≤1min）" % max_wall_err)
	# 切换动作本身：同一绝对时刻连续切换显示时区，天体不得移动（仿 main 自测第 24 组并加严）
	_m._timezone = "Asia/Shanghai"
	_m._advance_sim(0.0)
	_m._update_lighting()
	var alt_a := float(_m._sun_alt)
	var az_a := float(_m._sun_az)
	var wall_a := _hhmm_min(String(_m._display_clock_text()))
	_m._timezone = "America/New_York"
	_m._advance_sim(0.0)
	_m._update_lighting()
	var d_switch_alt := absf(float(_m._sun_alt) - alt_a)
	var d_switch_az := absf(_adiff(float(_m._sun_az), az_a))
	var wall_b := _hhmm_min(String(_m._display_clock_text()))
	var wall_diff := fposmod(float(wall_b - wall_a), 1440.0)
	var want_switch := fposmod(float(int(res["America/New_York"]["off"]) - int(res["Asia/Shanghai"]["off"])) / 60.0, 1440.0)
	var switch_wall_err: float = absf(fposmod(wall_diff - want_switch + 720.0, 1440.0) - 720.0)
	_upd("tz_switch_sun_alt_shift", d_switch_alt, "上海→纽约 连续切换")
	_upd("tz_switch_sun_az_shift", d_switch_az, "上海→纽约 连续切换")
	_checkq(d_switch_alt <= 0.05 and d_switch_az <= 0.05, "同一绝对时刻连续切换显示时区（上海→纽约）：天体位置差 max dalt=%.6f° daz=%.6f°≤0.05°" % [d_switch_alt, d_switch_az])
	_checkq(switch_wall_err <= 1.0, "切换后墙钟差与 offset 差一致（误差 %.2fmin≤1min）" % switch_wall_err)
	# [INFO] 反事实对照：旧映射（unix+所选偏移 灌入天文层）的漂移量，修复前正是 KNOWN-BUG 来源；
	# 修复后生产路径不再使用该映射，仅作证据保留，不计入 known_bug。
	var old_ref := IsleAstro.compute(unix + float(ref["off"]))
	var old_max_alt := 0.0
	var old_max_az := 0.0
	for tz in tzs:
		var old_c := IsleAstro.compute(unix + float(res[tz]["off"]))
		old_max_alt = maxf(old_max_alt, absf(float(old_c["sun_alt"]) - float(old_ref["sun_alt"])))
		old_max_az = maxf(old_max_az, absf(_adiff(float(old_c["sun_az"]), float(old_ref["sun_az"]))))
	print("  [INFO] 反事实旧映射 unix+显示偏移（pre-fix 语义）：max|dalt|=%.4f° max|daz|=%.4f° —— 修复后生产路径已不使用，仅证据保留" % [old_max_alt, old_max_az])
	_m._time_source = "sim"
	var fixed := _base("2026-03-20") + 9.0 * 3600.0
	_m._sim_seconds = fixed
	_m._timezone = "Asia/Shanghai"
	var c_sh := IsleAstro.compute(fixed)
	_m._timezone = "Asia/Tokyo"
	var c_tk := IsleAstro.compute(fixed)
	_check(absf(float(c_sh["sun_alt"]) - float(c_tk["sun_alt"])) <= 1e-12 and absf(_adiff(float(c_sh["sun_az"]), float(c_tk["sun_az"]))) <= 1e-12, "模拟模式：仅切换显示时区时天体位置严格不变（正确语义）")
	var ev := IsleAstro.day_events(fixed)
	var lsec: float = fixed + float(ev["sunrise"]) * 60.0
	print("  [DBG] fixed=%.1f sunrise_min=%.3f lsec=%.1f time_source=%s realtime=%s tz=%s off=%d" % [fixed, float(ev["sunrise"]), lsec, String(_m._time_source), str(_m.get("_realtime")), String(_m._timezone), int(_m._offset_for(lsec - 28800.0))])
	_m._timezone = "Asia/Shanghai"
	var text_sh := String(_m._local_seconds_to_display_text(lsec))
	_m._timezone = "Asia/Tokyo"
	var text_tk := String(_m._local_seconds_to_display_text(lsec))
	print("  [DBG] text_sh=%s text_tk=%s tz_now=%s off_now=%d" % [text_sh, text_tk, String(_m._timezone), int(_m._offset_for(lsec - 28800.0))])
	var m_sh := _hhmm_min(text_sh)
	var m_tk := _hhmm_min(text_tk)
	_check(m_sh >= 0 and m_tk >= 0 and absf(float(m_tk - m_sh) - 60.0) <= 1.0, "显示时刻随所选时区平移 1h（允许的显示调整）：Shanghai=%s Tokyo=%s" % [text_sh, text_tk])

func _hhmm_min(text: String) -> int:
	var parts := text.split(":")
	if parts.size() < 2:
		return -1
	return int(parts[0]) * 60 + int(parts[1])

func _phase_b_clock_coherence() -> void:
	print("  [B9] 同一 _sim_seconds 下天空/灯塔/炊烟/船/鸟/音频协调一致")
	_m._time_source = "sim"
	_m._day_length = 480.0
	var t0 := _base("2026-03-20")
	for h in [12.0, 18.0, 20.0]:
		_m._sim_seconds = t0 + h * 3600.0
		_m._sim_delta = 86400.0 / 480.0
		_m._update_lighting()
		_m._update_smoke_clock()
		_m._update_lighthouse_beam(1.0)
		var alt := float(_m._sun_alt)
		var night := 1.0 - smoothstep(-7.0, 3.0, alt)
		var lit := clampf(night * (0.22 + float((_m._pal as Dictionary).get("lanternI", 0.0)) * 1.05), 0.0, 1.0)
		var bs := float(_m.get("_beam_strength"))
		_upd("beam_strength_formula", absf(bs - lit), "h=%.1f" % h)
		_checkq(absf(bs - lit) <= 1e-6, "h=%.1f 灯塔强度=夜间系数公式（%.4f）" % [h, bs])
		var c := IsleAstro.compute(float(_m._sim_seconds))
		_checkq(absf(alt - float(c["sun_alt"])) <= 1e-6, "h=%.1f 天空太阳高度与同一 _sim_seconds 一致" % h)
		if _m.has_method("_is_boat_rest_hour"):
			var want_rest: bool = h >= 18.0 or h < 8.0
			_checkq(bool(_m._is_boat_rest_hour()) == want_rest, "h=%.1f 船只休息窗与同一时钟一致（want=%s）" % [h, str(want_rest)])
		_checkq(IsleFx.is_smoke_window(float(_m._sim_seconds)) == (h >= 11.0 and h < 13.0 or h >= 17.0 and h < 19.0), "h=%.1f 炊烟窗口与同一时钟一致" % h)
		var birds = _m.get("_birds")
		if birds != null:
			birds.update_birds(0.016, alt)
			var st: Dictionary = birds.get_state_counts()
			_checkq(bool(st.get("night", false)) == (alt < -2.0 or (bool(st.get("night", false)) and alt < 2.0)), "h=%.1f 海鸥昼夜与太阳高度协调（night=%s alt=%.2f）" % [h, str(st.get("night", false)), alt])
		var audio = _m.get("_audio")
		if audio != null and audio.has_method("get_debug_info"):
			audio.update_audio(0.2, {"sun_alt": alt, "night": clampf(-alt / 10.0, 0.0, 1.0), "wind": 0.5, "fireplace_on": alt < 2.0})
			var info: Dictionary = audio.get_debug_info()
			var phase := String(info.get("phase", ""))
			var want_phase := "day" if alt > 2.0 else ("night" if alt < -6.0 else "dusk")
			if alt > 2.0:
				_checkq(phase == "day", "h=%.1f 音频相位 day（实测 %s）" % [h, phase])
			elif alt < -6.0:
				_checkq(phase == "night", "h=%.1f 音频相位 night（实测 %s）" % [h, phase])
			else:
				_checkq(phase == "dusk" or phase == "dawn", "h=%.1f 音频相位 dusk/dawn（实测 %s）" % [h, phase])

# ------------------------------------------------------------------ 汇总
func _print_summary(elapsed_ms: int) -> void:
	print("--- SUMMARY ---")
	print("[SUMMARY] pass=%d fail=%d skip=%d known_bug=%d raw_lines=%d elapsed_ms=%d" % [_pass, _fail, _skips, _known, _raw_lines, elapsed_ms])
	var keys := _meas.keys()
	keys.sort()
	for k in keys:
		var v: Dictionary = _meas[k]
		print("[MEASURE] max %-28s = %.6f @ %s" % [String(k), float(v["max"]), String(v["at"])])
	print("=== T7 ASTRO XCHECK PROBE RESULT: %s ===" % ("PASS" if _fail == 0 else "FAIL"))
