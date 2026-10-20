class_name IsleAstro
extends RefCounted
## 天文计算：太阳（NOAA solcalc 近似）+ 月亮（Meeus《天文算法》第 47 章简化 ELP 周期项）。
## 默认地点：广州（23.1291N, 113.2644E），时区 UTC+8。
##
## 约定：
## - 对外角度单位均为度；方位角 az 从正北起、向东为正（0=N, 90=E, 180=S, 270=W）。
## - sun_alt / moon_alt 均为“几何高度”（不含大气折射）。太阳升落判据 -0.8333°（折射 34′ + 视半径 16′）；
##   月亮升落用顶心动态判据 -(0.5667 + 视半径)，视半径随距离变化（约 0.25°）。
## - 世界坐标映射：IsleMath.sun_dir(alt, az) = (cos(alt)sin(az), sin(alt), -cos(alt)cos(az))，
##   即 az=0 → -Z（北），az=90 → +X（东）。sky.gdshader 内部方位 atan(d.x, -d.z) 同约定。

const LAT := 23.1291
const LON := 113.2644
const TZ_MINUTES := 480
const TZ_SECONDS := TZ_MINUTES * 60

const DEG := PI / 180.0
const AU_KM := 149597870.7
const EARTH_RADIUS_KM := 6378.14
const MOON_RADIUS_KM := 1737.4

## 太阳升落几何高度阈值：-0.8333°（34′ 折射 + 16′ 视半径）
const SUN_RISE_ALT := -0.8333
## 月亮地平折射（顶心，度）
const MOON_REFRACTION := 0.5667

## Meeus 表 47.A（黄经 Σl 单位 1e-6°，距离 Σr 单位 1e-3 km），每 6 个一组：
## [D, M, M', F, Σl, Σr]
const _MOON_LR := [
	0, 0, 1, 0, 6288774, -20905355,
	2, 0, -1, 0, 1274027, -3699111,
	2, 0, 0, 0, 658314, -2955968,
	0, 0, 2, 0, 213618, -569925,
	0, 1, 0, 0, -185116, 48888,
	0, 0, 0, 2, -114332, -3149,
	2, 0, -2, 0, 58793, 246158,
	2, -1, -1, 0, 57066, -152138,
	2, 0, 1, 0, 53322, -170733,
	2, -1, 0, 0, 45758, -204586,
	0, 1, -1, 0, -40923, -129620,
	1, 0, 0, 0, -34720, 108743,
	0, 1, 1, 0, -30383, 104755,
	2, 0, 0, -2, 15327, 10321,
	0, 0, 1, 2, -12528, 0,
	0, 0, 1, -2, 10980, 79661,
	4, 0, -1, 0, 10675, -34782,
	0, 0, 3, 0, 10034, -23210,
	4, 0, -2, 0, 8548, -21636,
	2, 1, -1, 0, -7888, 24208,
	2, 1, 0, 0, -6766, 30824,
	1, 0, -1, 0, -5163, -8379,
	1, 1, 0, 0, 4987, -16675,
	2, -1, 1, 0, 4036, -12831,
	2, 0, 2, 0, 3994, -10445,
	4, 0, 0, 0, 3861, -11650,
	2, 0, -3, 0, 3665, 14403,
	0, 1, -2, 0, -2689, -7003,
	2, 0, -1, 2, -2602, 0,
	2, -1, -2, 0, 2390, 10056,
	1, 0, 1, 0, -2348, 6322,
	2, -2, 0, 0, 2236, -9884,
	0, 1, 2, 0, -2120, 5751,
	0, 2, 0, 0, -2069, 0,
	2, -2, -1, 0, 2048, -4950,
	2, 0, 1, -2, -1773, 4130,
	2, 0, 0, 2, -1595, 0,
	4, -1, -1, 0, 1215, -3958,
	0, 0, 2, 2, -1110, 0,
	3, 0, -1, 0, -892, 3258,
	2, 1, 1, 0, -810, 2616,
	4, -1, -2, 0, 759, -1897,
	0, 2, -1, 0, -713, -2117,
	2, 2, -1, 0, -700, 2354,
	2, 1, -2, 0, 691, 0,
	2, -1, 0, -2, 596, 0,
	4, 0, 1, 0, 549, -1423,
	0, 0, 4, 0, 537, -1117,
	4, -1, 0, 0, 520, -1571,
	1, 0, -2, 0, -487, -1739,
	2, 1, 0, -2, -399, 0,
	0, 0, 2, -2, -381, -4421,
	1, 1, 1, 0, 351, 0,
	3, 0, -2, 0, -340, 0,
	4, 0, -3, 0, 330, 0,
	2, -1, 2, 0, 327, 0,
	0, 2, 1, 0, -323, 1165,
	1, 1, -1, 0, 299, 0,
	2, 0, 3, 0, 294, 0,
	2, 0, -1, -2, 0, 8752,
]

## Meeus 表 47.B（黄纬 Σb 单位 1e-6°），每 5 个一组：[D, M, M', F, Σb]
const _MOON_B := [
	0, 0, 0, 1, 5128122,
	0, 0, 1, 1, 280602,
	0, 0, 1, -1, 277693,
	2, 0, 0, -1, 173237,
	2, 0, -1, 1, 55413,
	2, 0, -1, -1, 46271,
	2, 0, 0, 1, 32573,
	0, 0, 2, 1, 17198,
	2, 0, 1, -1, 9266,
	0, 0, 2, -1, 8822,
	2, -1, 0, -1, 8216,
	2, 0, -2, -1, 4324,
	2, 0, 1, 1, 4200,
	2, 1, 0, -1, -3359,
	2, -1, -1, 1, 2463,
	2, -1, 0, 1, 2211,
	2, -1, -1, -1, 2065,
	0, 1, -1, -1, -1870,
	4, 0, -1, -1, 1828,
	0, 1, 0, 1, -1794,
	0, 0, 0, 3, -1749,
	0, 1, -1, 1, -1565,
	1, 0, 0, 1, -1491,
	0, 1, 1, 1, -1475,
	0, 1, 1, -1, -1410,
	0, 1, 0, -1, -1344,
	1, 0, 0, -1, -1335,
	0, 0, 3, 1, 1107,
	4, 0, 0, -1, 1021,
	4, 0, -1, 1, 833,
	0, 0, 1, -3, 777,
	4, 0, -2, 1, 671,
	2, 0, 0, -3, 607,
	2, 0, 2, -1, 596,
	2, -1, 1, -1, 491,
	2, 0, -2, 1, -451,
	0, 0, 3, -1, 439,
	2, 0, 2, 1, 422,
	2, 0, -3, -1, 421,
	2, 1, -1, 1, -366,
	2, 1, 0, 1, -351,
	4, 0, 0, 1, 331,
	2, -1, 1, 1, 315,
	2, -2, 0, -1, 302,
	0, 0, 1, 3, -283,
	2, 1, 1, -1, -229,
	1, 1, 0, -1, 223,
	1, 1, 0, 1, 223,
	0, 1, -2, -1, -220,
	2, 1, -1, -1, -220,
	1, 0, 1, 1, -185,
	2, -1, -2, -1, 181,
	0, 1, 2, 1, -177,
	4, 0, -2, -1, 176,
	4, -1, -1, -1, 166,
	1, 0, 1, -1, -164,
	4, 0, 1, -1, 132,
	1, 0, -1, -1, -119,
	4, -1, 0, -1, 115,
	2, -2, 0, 1, 107,
]

# ---------------------------------------------------------------- 基础工具

static func jd_from_local(local_seconds: float) -> float:
	return (local_seconds - TZ_SECONDS) / 86400.0 + 2440587.5

static func _gmst_deg(jd: float) -> float:
	var T: float = (jd - 2451545.0) / 36525.0
	return fposmod(280.46061837 + 360.98564736629 * (jd - 2451545.0) \
		+ 0.000387933 * T * T - T * T * T / 38710000.0, 360.0)

## 由赤纬 + 时角直接求地平坐标（atan2 形式，方位连续、无 acos 分支跳变）。
## 返回 alt/az（度，az 从北向东）、ha（度，归一到 (-180,180]）。
static func _altaz(dec_rad: float, ra_rad: float, jd: float) -> Dictionary:
	var lst: float = fposmod(_gmst_deg(jd) + LON, 360.0)
	var ha: float = fposmod(lst - rad_to_deg(ra_rad), 360.0)
	if ha > 180.0:
		ha -= 360.0
	var hor: Dictionary = _horizon(dec_rad, deg_to_rad(ha))
	hor["ha"] = ha
	return hor

## 由赤纬 + 时角（弧度）求地平坐标，方位公式 az = atan2(-cosδ sinH, sinδ cosφ - cosδ sinφ cosH)。
static func _horizon(dec_rad: float, ha_rad: float) -> Dictionary:
	var lat: float = LAT * DEG
	var sin_alt: float = sin(lat) * sin(dec_rad) + cos(lat) * cos(dec_rad) * cos(ha_rad)
	var alt: float = asin(clampf(sin_alt, -1.0, 1.0))
	var y: float = -cos(dec_rad) * sin(ha_rad)
	var x: float = sin(dec_rad) * cos(lat) - cos(dec_rad) * sin(lat) * cos(ha_rad)
	var az: float = fposmod(rad_to_deg(atan2(y, x)), 360.0)
	return {"alt": rad_to_deg(alt), "az": az}

static func _mean_obliquity_deg(T: float) -> float:
	return 23.43929111 - 0.013004167 * T - 1.6389e-7 * T * T + 5.0361e-7 * T * T * T

# ---------------------------------------------------------------- 太阳

## 太阳赤道坐标（内部用，弧度）：lam 视黄经(deg)、ra_rad/dec_rad、dist(AU)。
static func _sun_equatorial(jd: float) -> Dictionary:
	var T: float = (jd - 2451545.0) / 36525.0
	var L0: float = fposmod(280.46646 + T * (36000.76983 + T * 0.0003032), 360.0)
	var M: float = 357.52911 + T * (35999.05029 - 0.0001537 * T)
	var e: float = 0.016708634 - T * (0.000042037 + 0.0000001267 * T)
	var Mrad: float = M * DEG
	var C: float = sin(Mrad) * (1.914602 - T * (0.004817 + 0.000014 * T)) \
		+ sin(2.0 * Mrad) * (0.019993 - 0.000101 * T) + sin(3.0 * Mrad) * 0.000289
	var true_long: float = L0 + C
	var omega: float = 125.04 - 1934.136 * T
	var lam: float = true_long - 0.00569 - 0.00478 * sin(omega * DEG)
	var eps: float = _mean_obliquity_deg(T) + 0.00256 * cos(omega * DEG)
	var epsr: float = eps * DEG
	var lamr: float = lam * DEG
	var dec: float = asin(sin(epsr) * sin(lamr))
	var ra: float = atan2(cos(epsr) * sin(lamr), cos(lamr))
	var v: float = M + C
	var dist: float = 1.000001018 * (1.0 - e * e) / (1.0 + e * cos(v * DEG))
	return {
		"T": T,
		"lam_deg": lam,
		"ra_rad": ra,
		"dec_rad": dec,
		"dec": rad_to_deg(dec),
		"ra": rad_to_deg(ra),
		"dist": dist,
	}

static func sun_position(jd: float) -> Dictionary:
	var s: Dictionary = _sun_equatorial(jd)
	var hor: Dictionary = _altaz(float(s["dec_rad"]), float(s["ra_rad"]), jd)
	hor["dec"] = s["dec"]
	hor["ra"] = s["ra"]
	hor["lon"] = s["lam_deg"]
	hor["dist"] = s["dist"]
	return hor

## 太阳高度角（度，几何）——供 day_events 快速求根。
static func _sun_alt_at(jd: float) -> float:
	var s: Dictionary = _sun_equatorial(jd)
	var lat: float = LAT * DEG
	var lst: float = fposmod(_gmst_deg(jd) + LON, 360.0)
	var ha: float = fposmod(lst - rad_to_deg(float(s["ra_rad"])), 360.0)
	if ha > 180.0:
		ha -= 360.0
	return rad_to_deg(asin(clampf(sin(lat) * sin(float(s["dec_rad"])) \
		+ cos(lat) * cos(float(s["dec_rad"])) * cos(deg_to_rad(ha)), -1.0, 1.0)))

## 太阳时角（度，归一到 (-180,180]）——供正午(中天)求根。
static func _sun_ha_at(jd: float) -> float:
	var s: Dictionary = _sun_equatorial(jd)
	var lst: float = fposmod(_gmst_deg(jd) + LON, 360.0)
	var ha: float = fposmod(lst - rad_to_deg(float(s["ra_rad"])), 360.0)
	if ha > 180.0:
		ha -= 360.0
	return ha

# ---------------------------------------------------------------- 月亮

## 月亮位置（顶心几何高度 + 视差 + 相位）。
## 传入 sun 可复用已算的太阳赤道坐标（compute/day_events 用）。
## lr_terms/b_terms 可截断 Meeus 47.A/47.B 级数（按表中幅值降序），仅供 day_events 快速求根。
static func _moon_with_sun(jd: float, sun: Dictionary, lr_terms: int = 60, b_terms: int = 60) -> Dictionary:
	var T: float = (jd - 2451545.0) / 36525.0
	var T2: float = T * T
	var T3: float = T2 * T
	var T4: float = T3 * T
	# Meeus 47.1–47.5 平要素（度）
	var Lp: float = fposmod(218.3164477 + 481267.88123421 * T - 0.0015786 * T2 \
		+ T3 / 538841.0 - T4 / 65194000.0, 360.0)
	var D: float = fposmod(297.8501921 + 445267.1114034 * T - 0.0018819 * T2 \
		+ T3 / 545868.0 - T4 / 113065000.0, 360.0)
	var M: float = fposmod(357.5291092 + 35999.0502909 * T - 0.0001536 * T2 \
		+ T3 / 24490000.0, 360.0)
	var Mp: float = fposmod(134.9633964 + 477198.8675055 * T + 0.0087414 * T2 \
		+ T3 / 69699.0 - T4 / 14712000.0, 360.0)
	var F: float = fposmod(93.2720950 + 483202.0175233 * T - 0.0036539 * T2 \
		- T3 / 3526000.0 + T4 / 863310000.0, 360.0)
	var E: float = 1.0 - 0.002516 * T - 0.0000074 * T2
	var E2: float = E * E
	var Dr: float = D * DEG
	var Mr: float = M * DEG
	var Mpr: float = Mp * DEG
	var Fr: float = F * DEG
	# 表 47.A：黄经 + 距离
	var suml: float = 0.0
	var sumr: float = 0.0
	var n: int = mini(lr_terms, _MOON_LR.size() / 6) * 6
	var i: int = 0
	while i < n:
		var tm: int = _MOON_LR[i + 1]
		var arg: float = float(_MOON_LR[i]) * Dr + float(tm) * Mr \
			+ float(_MOON_LR[i + 2]) * Mpr + float(_MOON_LR[i + 3]) * Fr
		var sa: float = sin(arg)
		var cl: float = float(_MOON_LR[i + 4])
		var cr: float = float(_MOON_LR[i + 5])
		if tm == 1 or tm == -1:
			cl *= E
			cr *= E
		elif tm == 2 or tm == -2:
			cl *= E2
			cr *= E2
		suml += cl * sa
		if cr != 0.0:
			sumr += cr * cos(arg)
		i += 6
	# 表 47.B：黄纬
	var sumb: float = 0.0
	n = mini(b_terms, _MOON_B.size() / 5) * 5
	i = 0
	while i < n:
		var tm2: int = _MOON_B[i + 1]
		var arg2: float = float(_MOON_B[i]) * Dr + float(tm2) * Mr \
			+ float(_MOON_B[i + 2]) * Mpr + float(_MOON_B[i + 3]) * Fr
		var cb: float = float(_MOON_B[i + 4])
		if tm2 == 1 or tm2 == -1:
			cb *= E
		elif tm2 == 2 or tm2 == -2:
			cb *= E2
		sumb += cb * sin(arg2)
		i += 5
	# 附加项（Meeus 47.5）
	var A1: float = (119.75 + 131.849 * T) * DEG
	var A2: float = (53.09 + 479264.290 * T) * DEG
	var A3: float = (313.45 + 481266.484 * T) * DEG
	suml += 3958.0 * sin(A1) + 1962.0 * sin((Lp - F) * DEG) + 318.0 * sin(A2)
	sumb += -2235.0 * sin(Lp * DEG) + 382.0 * sin(A3) + 175.0 * sin(A1 - Fr) \
		+ 175.0 * sin(A1 + Fr) + 127.0 * sin((Lp - Mp) * DEG) - 115.0 * sin((Lp + Mp) * DEG)
	var lon: float = Lp + suml / 1000000.0
	var lat: float = sumb / 1000000.0
	var dist: float = 385000.56 + sumr / 1000.0
	# 章动（Meeus 47.6 / 22）：Δψ、Δε（角秒）
	var omega_r: float = (125.04452 - 1934.136261 * T + 0.0020708 * T2 + T3 / 450000.0) * DEG
	var L0sun_r: float = (280.4665 + 36000.7698 * T) * DEG
	var Lpm_r: float = lon * DEG
	var dpsi: float = (-17.20 * sin(omega_r) - 1.32 * sin(2.0 * L0sun_r) \
		- 0.23 * sin(2.0 * Lpm_r) + 0.21 * sin(2.0 * omega_r)) / 3600.0
	var deps: float = (9.20 * cos(omega_r) + 0.57 * cos(2.0 * L0sun_r) \
		+ 0.10 * cos(2.0 * Lpm_r) - 0.09 * cos(2.0 * omega_r)) / 3600.0
	var lon_app: float = lon + dpsi
	# 黄道 → 赤道
	var eps: float = (_mean_obliquity_deg(T) + deps) * DEG
	var lam_r: float = lon_app * DEG
	var lat_r: float = lat * DEG
	var ra: float = atan2(sin(lam_r) * cos(eps) - tan(lat_r) * sin(eps), cos(lam_r))
	var dec: float = asin(clampf(sin(lat_r) * cos(eps) + cos(lat_r) * sin(eps) * sin(lam_r), -1.0, 1.0))
	# 地心地平 + 视差（Meeus 40.2–40.3）
	var geo: Dictionary = _altaz(dec, ra, jd)
	var parallax: float = rad_to_deg(asin(clampf(EARTH_RADIUS_KM / dist, -1.0, 1.0)))
	var sd: float = rad_to_deg(asin(clampf(MOON_RADIUS_KM / dist, -1.0, 1.0)))
	var pi_rad: float = parallax * DEG
	var lst: float = fposmod(_gmst_deg(jd) + LON, 360.0)
	var ha: float = fposmod(lst - rad_to_deg(ra), 360.0)
	if ha > 180.0:
		ha -= 360.0
	var ha_r: float = ha * DEG
	var lat_geo: float = LAT * DEG
	var u: float = atan(0.99664719 * tan(lat_geo))
	var x: float = cos(u)
	var y: float = 0.99664719 * sin(u)
	var sin_pi: float = sin(pi_rad)
	var d_alpha: float = atan2(-x * sin_pi * sin(ha_r), cos(dec) - x * sin_pi * cos(ha_r))
	var ra_t: float = ra + d_alpha
	var dec_t: float = atan2((sin(dec) - y * sin_pi) * cos(d_alpha), \
		cos(dec) - x * sin_pi * cos(ha_r))
	var ha_t: float = lst - rad_to_deg(ra_t)
	if ha_t > 180.0:
		ha_t -= 360.0
	elif ha_t <= -180.0:
		ha_t += 360.0
	var hor: Dictionary = _horizon(dec_t, ha_t * DEG)
	# 相位角与照度（Meeus 48.3）
	var sun_ra: float = float(sun["ra_rad"])
	var sun_dec: float = float(sun["dec_rad"])
	var elong: float = acos(clampf(sin(sun_dec) * sin(dec) \
		+ cos(sun_dec) * cos(dec) * cos(sun_ra - ra), -1.0, 1.0))
	var rs: float = float(sun["dist"]) * AU_KM
	var phase_angle: float = atan2(rs * sin(elong), dist - rs * cos(elong))
	var illum: float = (1.0 + cos(phase_angle)) * 0.5
	hor["dec"] = rad_to_deg(dec)
	hor["ra"] = rad_to_deg(ra)
	hor["lon"] = lon
	hor["lat"] = lat
	hor["dist"] = dist
	hor["illum"] = illum
	hor["waxing"] = fposmod(lon - float(sun["lam_deg"]), 360.0) < 180.0
	hor["phase_angle"] = rad_to_deg(phase_angle)
	hor["parallax"] = parallax
	hor["sd"] = sd
	hor["geo_alt"] = float(geo["alt"])
	hor["ha"] = ha_t
	return hor

static func moon_position(jd: float) -> Dictionary:
	return _moon_with_sun(jd, _sun_equatorial(jd))

## 月亮顶心几何高度（度）——供 day_events 快速求根。
static func _moon_alt_at(jd: float) -> float:
	return float(_moon_with_sun(jd, _sun_equatorial(jd))["alt"])

## day_events 专用快速月亮：截断级数（24/12 项，高度误差 <0.05° ≈ 升没时刻误差 <15s）。
## 不能用于渲染；渲染/面板仍用 compute() 的完整模型。
static func _moon_fast(jd: float, sun: Dictionary) -> Dictionary:
	var p: Dictionary = _moon_with_sun(jd, sun, 24, 12)
	return {"alt": float(p["alt"]), "az": float(p["az"]), "sd": float(p["sd"]), "illum": float(p["illum"])}

# ---------------------------------------------------------------- 综合

static func compute(local_seconds: float) -> Dictionary:
	var jd: float = jd_from_local(local_seconds)
	var sun: Dictionary = _sun_equatorial(jd)
	var sun_hor: Dictionary = _altaz(float(sun["dec_rad"]), float(sun["ra_rad"]), jd)
	var moon: Dictionary = _moon_with_sun(jd, sun)
	return {
		"sun_alt": float(sun_hor["alt"]),
		"sun_az": float(sun_hor["az"]),
		"sun_ha": float(sun_hor["ha"]),
		"sun_dec": float(sun["dec"]),
		"sun_dist": float(sun["dist"]),
		"moon_alt": float(moon["alt"]),
		"moon_az": float(moon["az"]),
		"moon_illum": float(moon["illum"]),
		"moon_waxing": bool(moon["waxing"]),
		"moon_dist": float(moon["dist"]),
		"moon_parallax": float(moon["parallax"]),
		"moon_sd": float(moon["sd"]),
		"moon_phase_angle": float(moon["phase_angle"]),
		"jd": jd,
	}

# ---------------------------------------------------------------- 日内事件

## 日内事件缓存：main 每 1.5s 轮询一次同一日，命中缓存后几乎零成本。
static var _cached_day: float = -1.0e30
static var _cached_events: Dictionary = {}

const _SAMPLE_COUNT: int = 49          # 00:00..24:00，每 30 分钟一个粗采样
const _SAMPLE_STEP: float = 1800.0     # 秒

static func day_events(local_seconds: float) -> Dictionary:
	var day_start: float = local_seconds - fposmod(local_seconds, 86400.0)
	if day_start == _cached_day and not _cached_events.is_empty():
		return _cached_events
	var ev: Dictionary = _compute_day_events(day_start)
	_cached_day = day_start
	_cached_events = ev
	return ev

## 冷路径优化：日事件按日期缓存，冷启动只跑一次。
## 采样策略：太阳 30min/49 点（仅高度，约 7µs/次）；月亮 4h/7 点（约 143µs/次）。
## 月亮粗采样用固定视半径 0.259° 只判符号，细化时再用精确 sd；过零后二分/试位法细化。
static func _compute_day_events(day_start: float) -> Dictionary:
	const SAMPLE_STEP: float = 1800.0
	const MOON_STEP: float = 21600.0
	const MOON_SAMPLES: int = 5
	var n: int = 49
	var times := PackedFloat64Array()
	var sun_alts := PackedFloat64Array()
	times.resize(n)
	sun_alts.resize(n)
	var noon_i: int = 0
	for i in range(n):
		var t: float = day_start + float(i) * SAMPLE_STEP
		times[i] = t
		var sa: float = _sun_alt_at(jd_from_local(t))
		sun_alts[i] = sa
		if sa > sun_alts[noon_i]:
			noon_i = i
	var m_times := PackedFloat64Array()
	var m_res := PackedFloat64Array()
	m_times.resize(MOON_SAMPLES)
	m_res.resize(MOON_SAMPLES)
	for k in range(MOON_SAMPLES):
		var mt: float = day_start + float(k) * MOON_STEP
		m_times[k] = mt
		var mjd: float = jd_from_local(mt)
		var mf: Dictionary = _moon_fast(mjd, _sun_equatorial(mjd))
		m_res[k] = float(mf["alt"]) + MOON_REFRACTION + 0.259
	var moon_cross: Array = _crossings(m_times, m_res, 0.0)

	# 正午（中天）：粗采样最高点两侧对“时角=0”二分
	var noon_t: float = -1.0
	var noon_alt: float = -90.0
	var noon_az: float = 0.0
	if noon_i > 0 and noon_i < n - 1:
		var a: float = times[noon_i - 1]
		var b: float = times[noon_i + 1]
		var fa: float = _sun_ha_at(jd_from_local(a))
		for _k in range(10):
			var m: float = (a + b) * 0.5
			var fm: float = _sun_ha_at(jd_from_local(m))
			if (fa < 0.0) == (fm < 0.0):
				a = m
				fa = fm
			else:
				b = m
		noon_t = (a + b) * 0.5
		var np: Dictionary = sun_position(jd_from_local(noon_t))
		noon_alt = float(np["alt"])
		noon_az = float(np["az"])

	# 太阳升落 + 晨昏光（民用 -6、航海 -12、天文 -18）
	var rise_t: float = -1.0
	var set_t: float = -1.0
	var civil_dawn_t: float = -1.0
	var civil_dusk_t: float = -1.0
	var naut_dawn_t: float = -1.0
	var naut_dusk_t: float = -1.0
	var astro_dawn_t: float = -1.0
	var astro_dusk_t: float = -1.0
	var sun_cross: Array = _crossings(times, sun_alts, SUN_RISE_ALT)
	var rise_c: Dictionary = _pick_crossing(sun_cross, true)
	if not rise_c.is_empty():
		rise_t = _refine_sun(float(rise_c["t0"]), float(rise_c["t1"]), SUN_RISE_ALT)
	var set_c: Dictionary = _pick_crossing(sun_cross, false)
	if not set_c.is_empty():
		set_t = _refine_sun(float(set_c["t0"]), float(set_c["t1"]), SUN_RISE_ALT)
	var cc: Array = _crossings(times, sun_alts, -6.0)
	var c1: Dictionary = _pick_crossing(cc, true)
	if not c1.is_empty():
		civil_dawn_t = _refine_sun(float(c1["t0"]), float(c1["t1"]), -6.0)
	var c2: Dictionary = _pick_crossing(cc, false)
	if not c2.is_empty():
		civil_dusk_t = _refine_sun(float(c2["t0"]), float(c2["t1"]), -6.0)
	var nc: Array = _crossings(times, sun_alts, -12.0)
	var c3: Dictionary = _pick_crossing(nc, true)
	if not c3.is_empty():
		naut_dawn_t = _refine_sun(float(c3["t0"]), float(c3["t1"]), -12.0)
	var c4: Dictionary = _pick_crossing(nc, false)
	if not c4.is_empty():
		naut_dusk_t = _refine_sun(float(c4["t0"]), float(c4["t1"]), -12.0)
	var ac: Array = _crossings(times, sun_alts, -18.0)
	var c5: Dictionary = _pick_crossing(ac, true)
	if not c5.is_empty():
		astro_dawn_t = _refine_sun(float(c5["t0"]), float(c5["t1"]), -18.0)
	var c6: Dictionary = _pick_crossing(ac, false)
	if not c6.is_empty():
		astro_dusk_t = _refine_sun(float(c6["t0"]), float(c6["t1"]), -18.0)

	# 月亮升没：动态顶心阈值（折射 + 视半径随距离变化），试位法细化
	var moonrise_t: float = -1.0
	var moonset_t: float = -1.0
	var moonrise_az: float = -1.0
	var moonset_az: float = -1.0
	var m_rise: Dictionary = _pick_crossing(moon_cross, true)
	if not m_rise.is_empty():
		var rr: Dictionary = _refine_moon(float(m_rise["t0"]), float(m_rise["t1"]))
		moonrise_t = float(rr["t"])
		moonrise_az = float(rr["az"])
	var m_set: Dictionary = _pick_crossing(moon_cross, false)
	if not m_set.is_empty():
		var rs2: Dictionary = _refine_moon(float(m_set["t0"]), float(m_set["t1"]))
		moonset_t = float(rs2["t"])
		moonset_az = float(rs2["az"])

	var njd: float = jd_from_local(day_start + 43200.0)
	var noon12: Dictionary = _moon_fast(njd, _sun_equatorial(njd))
	var ev: Dictionary = {
		"sunrise": _to_min(day_start, rise_t),
		"sunset": _to_min(day_start, set_t),
		"sunrise_az": _event_az(rise_t),
		"sunset_az": _event_az(set_t),
		"noon_alt": noon_alt,
		"noon_az": noon_az,
		"noon_time": _to_min(day_start, noon_t),
		"day_length": -1.0,
		"moonrise": _to_min(day_start, moonrise_t),
		"moonset": _to_min(day_start, moonset_t),
		"moonrise_az": _event_moon_az(moonrise_t),
		"moonset_az": _event_moon_az(moonset_t),
		"noon_illum": float(noon12["illum"]),
		"civil_dawn": _to_min(day_start, civil_dawn_t),
		"civil_dusk": _to_min(day_start, civil_dusk_t),
		"nautical_dawn": _to_min(day_start, naut_dawn_t),
		"nautical_dusk": _to_min(day_start, naut_dusk_t),
		"astronomical_dawn": _to_min(day_start, astro_dawn_t),
		"astronomical_dusk": _to_min(day_start, astro_dusk_t),
	}
	if float(ev["sunrise"]) >= 0.0 and float(ev["sunset"]) >= 0.0:
		ev["day_length"] = float(ev["sunset"]) - float(ev["sunrise"])
	return ev

## 粗采样找阈值过零点：values[i] - threshold 变号处返回 {t0,t1,rising}。
static func _crossings(times: PackedFloat64Array, values: PackedFloat64Array, threshold: float) -> Array:
	var out: Array = []
	for i in range(1, times.size()):
		var a: float = values[i - 1] - threshold
		var b: float = values[i] - threshold
		if (a < 0.0 and b >= 0.0) or (a >= 0.0 and b < 0.0):
			out.append({"t0": times[i - 1], "t1": times[i], "rising": b > a})
	return out

static func _pick_crossing(crossings: Array, rising: bool) -> Dictionary:
	for c in crossings:
		if bool(c["rising"]) == rising:
			return c
	return {}

## 太阳阈值二分（10 次 = 30min/1024 ≈ 1.8s 时刻精度）
static func _refine_sun(t0: float, t1: float, threshold: float) -> float:
	var a: float = t0
	var b: float = t1
	var fa: float = _sun_alt_at(jd_from_local(a)) - threshold
	for _k in range(10):
		var m: float = (a + b) * 0.5
		var fm: float = _sun_alt_at(jd_from_local(m)) - threshold
		if (fa < 0.0) == (fm < 0.0):
			a = m
			fa = fm
		else:
			b = m
	return (a + b) * 0.5

## 月亮过零试位法：残差近线性，4 次迭代收敛；返回 {t, az}，az 复用最后一次评估（误差 < 0.01°）。
static func _refine_moon(t0: float, t1: float) -> Dictionary:
	var lo: float = t0
	var hi: float = t1
	var jd_lo: float = jd_from_local(lo)
	var p: Dictionary = _moon_fast(jd_lo, _sun_equatorial(jd_lo))
	var f_lo: float = float(p["alt"]) + MOON_REFRACTION + float(p["sd"])
	var az: float = float(p["az"])
	if absf(f_lo) < 1.0e-4:
		return {"t": lo, "az": az}
	var jd_hi: float = jd_from_local(hi)
	p = _moon_fast(jd_hi, _sun_equatorial(jd_hi))
	var f_hi: float = float(p["alt"]) + MOON_REFRACTION + float(p["sd"])
	if absf(f_hi) < 1.0e-4:
		return {"t": hi, "az": float(p["az"])}
	var t_best: float = lo
	for _k in range(4):
		var m: float = lo + (hi - lo) * (-f_lo) / (f_hi - f_lo)
		var jd_m: float = jd_from_local(m)
		var pm: Dictionary = _moon_fast(jd_m, _sun_equatorial(jd_m))
		var fm: float = float(pm["alt"]) + MOON_REFRACTION + float(pm["sd"])
		t_best = m
		az = float(pm["az"])
		if absf(fm) < 1.0e-4:
			return {"t": m, "az": az}
		if (fm < 0.0) == (f_lo < 0.0):
			lo = m
			f_lo = fm
		else:
			hi = m
			f_hi = fm
	return {"t": t_best, "az": az}

static func _to_min(day_start: float, t: float) -> float:
	if t < 0.0:
		return -1.0
	return (t - day_start) / 60.0

static func _event_az(t: float) -> float:
	if t < 0.0:
		return -1.0
	return float(sun_position(jd_from_local(t))["az"])

static func _event_moon_az(t: float) -> float:
	if t < 0.0:
		return -1.0
	return float(moon_position(jd_from_local(t))["az"])

# ---------------------------------------------------------------- 时间/文本工具

static func local_datetime(local_seconds: float) -> Dictionary:
	return Time.get_datetime_dict_from_unix_time(int(floor(local_seconds)))

static func now_local_seconds() -> float:
	return Time.get_unix_time_from_system() + float(TZ_SECONDS)

static func clock_text(minute_of_day: float) -> String:
	var m: int = int(fposmod(minute_of_day, 1440.0))
	var h: int = m / 60
	var mi: int = m % 60
	return "%02d:%02d" % [h, mi]

static func format_minutes(minutes: float) -> String:
	if minutes < 0.0:
		return "--:--"
	return clock_text(minutes)

static func weekday_cn(dt: Dictionary) -> String:
	# 1970-01-01 is a Thursday (index 4 if Sunday = 0)
	var days: int = int(Time.get_unix_time_from_datetime_dict({"year": dt["year"], "month": dt["month"], "day": dt["day"], "hour": 0, "minute": 0, "second": 0})) / 86400
	var names := ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
	return names[fposmod(days + 4, 7)]