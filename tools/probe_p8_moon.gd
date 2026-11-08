extends SceneTree
# P8 阶段 3.2 月球验证探针（headless，不依赖现实时间与渲染）。
# 覆盖：
#   A 相位时刻：4 个朔望月 × 8 相（0/45/90/.../315°），日月视黄经距角 Δλ 与照亮比例；
#   B 位置：MET Norway 广州 12 天样本的月出/月落时刻+方位、18:00 高度与照亮比例；
#   C 完整朔望月连续性：29.6 天 × 3h 采样，Δλ 单调推进、照亮比例连续、相位角自洽；
#   D 渲染端月盘模型：按 sky.gdshader 新版公式在 CPU 复算亮面比例与亮侧朝向（朝太阳）；
#   E 可见性契约：真实高度 < −2.3° 必须不可见、> +3.4° 必须可见；固定 18:00 证伪。
# 数据来源：HKO MoonPhases_2026（USNO 派生）+ MET Norway Sunrise API v3。
# 复跑：Godot_v4.7.2-stable_win64_console.exe --headless --path <项目> --script res://tools/probe_p8_moon.gd

const TZ := 28800.0
const MOON_RISE_ALT := -0.8257   # isle_astro: MOON_REFRACTION(0.5667) + 视半径 0.259

var _pass := 0
var _fail := 0
var _fails: Array[String] = []

func _initialize() -> void:
	_test_phase_times()
	_test_met_positions()
	_test_cycle_continuity()
	_test_render_geometry()
	_test_visibility_contract()
	_test_shader_wiring()
	print("[P8MOON] RESULT %d/%d passed, %d failed" % [_pass, _pass + _fail, _fail])
	for f in _fails:
		print("[P8MOON] FAIL ", f)
	quit(0 if _fail == 0 else 1)

func _ok(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		_fails.append(msg)

func _near(v: float, target: float, tol: float, msg: String) -> void:
	_ok(absf(v - target) <= tol, "%s: got %.4f want %.4f ±%.4f" % [msg, v, target, tol])

## 本地钟面字段 → 权威模拟秒（isle_astro 的 local_seconds 语义：unix + 28800）。
func _ls(y: int, mo: int, d: int, h: int, mi: int) -> float:
	# Godot 把 datetime_dict 当 UTC 解析：钟面 18:00 解析出的 unix 已比北京 18:00 的 unix 快 8h，
	# 而 local_seconds = unix + 8h，两者刚好抵消——所以直接返回 u，不能再加 TZ（否则整体偏 8h）。
	var u: float = Time.get_unix_time_from_datetime_dict({"year": y, "month": mo, "day": d, "hour": h, "minute": mi, "second": 0})
	return u

## UTC 日期时间字符串 → 权威模拟秒（+08:00 无夏令时）。
func _ls_utc(s: String) -> float:
	return float(Time.get_unix_time_from_datetime_string(s)) + TZ

func _dlambda(ls: float) -> float:
	var jd: float = IsleAstro.jd_from_local(ls)
	var sun: Dictionary = IsleAstro.sun_position(jd)
	var moon: Dictionary = IsleAstro.moon_position(jd)
	return fposmod(float(moon["lon"]) - float(sun["lon"]), 360.0)

# ---------------------------------------------------------------- A 相位时刻
func _test_phase_times() -> void:
	# 2026-10 至 2027-01 连续四个朔望月 × 八相（UTC），HKO 0/90/180/270 + 模型 45/135/225/315。
	var samples := [
		["2026-10-10T15:50:00", 0.0], ["2026-10-14T13:13:00", 45.0],
		["2026-10-18T16:13:00", 90.0], ["2026-10-22T15:19:00", 135.0],
		["2026-10-26T04:12:00", 180.0], ["2026-10-29T11:23:00", 225.0],
		["2026-11-01T20:28:00", 270.0], ["2026-11-05T11:02:00", 315.0],
		["2026-11-09T07:02:00", 0.0], ["2026-11-13T08:33:00", 45.0],
		["2026-11-17T11:48:00", 90.0], ["2026-11-21T06:42:00", 135.0],
		["2026-11-24T14:54:00", 180.0], ["2026-11-27T19:55:00", 225.0],
		["2026-12-01T06:09:00", 270.0], ["2026-12-05T00:29:00", 315.0],
		["2026-12-09T00:52:00", 0.0], ["2026-12-13T04:38:00", 45.0],
		["2026-12-17T05:43:00", 90.0], ["2026-12-20T20:08:00", 135.0],
		["2026-12-24T01:28:00", 180.0], ["2026-12-27T06:23:00", 225.0],
		["2026-12-30T19:00:00", 270.0], ["2027-01-03T17:08:00", 315.0],
		["2027-01-07T20:24:00", 0.0], ["2027-01-11T23:31:00", 45.0],
		["2027-01-15T20:35:00", 90.0], ["2027-01-19T07:34:00", 135.0],
		["2027-01-22T12:17:00", 180.0], ["2027-01-25T18:59:00", 225.0],
		["2027-01-29T10:55:00", 270.0], ["2027-02-02T12:20:00", 315.0],
	]
	for s in samples:
		var ls: float = _ls_utc(str(s[0]))
		var want: float = float(s[1])
		var d: float = _dlambda(ls)
		var delta: float = absf(d - want)
		if delta > 180.0:
			delta = absf(delta - 360.0)
		_ok(delta <= 2.0, "A 相位时刻 Δλ %s: got %.2f° want %.1f°" % [str(s[0]), d, want])
		var c: Dictionary = IsleAstro.compute(ls)
		var k: float = float(c["moon_illum"])
		var expect_k: float = (1.0 - cos(deg_to_rad(want))) * 0.5
		_near(k, expect_k, 0.02, "A 照亮比例 %s" % str(s[0]))
		var pa: float = float(c["moon_phase_angle"])
		_near(k, (1.0 + cos(deg_to_rad(pa))) * 0.5, 0.001, "A 相位角自洽 %s" % str(s[0]))
		_near(float(c["moon_phase_deg"]), d, 0.001, "A compute.moon_phase_deg %s" % str(s[0]))

# ---------------------------------------------------------------- B 位置
func _test_met_positions() -> void:
	# [rise y,mo,d,h,mi,az, set y,mo,d,h,mi,az, 18:00 高度, k]
	var days := [
		[2026, 10, 26, 17, 45, 70.0, 2026, 10, 26, 6, 18, 287.0, 2.3, 1.00],
		[2026, 11, 24, 17, 10, 63.0, 2026, 11, 24, 6, 8, 295.0, 9.2, 1.00],
		[2026, 12, 24, 18, 0, 61.0, 2026, 12, 24, 7, 10, 300.0, -1.0, 1.00],
		[2027, 1, 22, 17, 55, 66.0, 2027, 1, 22, 6, 49, 296.0, -0.0, 1.00],
		[2026, 10, 19, 13, 35, 114.0, 2026, 10, 20, 0, 39, 248.0, 42.4, 0.57],
		[2026, 11, 17, 12, 44, 106.0, 2026, 11, 18, 0, 16, 257.0, 52.2, 0.49],
		[2026, 12, 17, 12, 19, 90.0, 2026, 12, 18, 0, 46, 274.0, 67.1, 0.52],
		[2027, 1, 16, 12, 0, 73.0, 2027, 1, 16, 0, 28, 284.0, 78.7, 0.56],
		[2026, 11, 1, 23, 45, 69.0, 2026, 11, 2, 13, 20, 289.0, -48.4, 0.44],
		[2026, 11, 30, 23, 41, 80.0, 2026, 12, 1, 12, 36, 278.0, -60.2, 0.48],
		[2026, 12, 31, 0, 24, 97.0, 2026, 12, 31, 12, 17, 260.0, -74.0, 0.44],
		[2027, 1, 29, 0, 6, 107.0, 2027, 1, 29, 11, 26, 250.0, -85.4, 0.51],
	]
	for di in range(days.size()):
		var d: Array = days[di]
		var rise_ls: float = _ls(int(d[0]), int(d[1]), int(d[2]), int(d[3]), int(d[4]))
		var set_ls: float = _ls(int(d[6]), int(d[7]), int(d[8]), int(d[9]), int(d[10]))
		var cr: Dictionary = IsleAstro.compute(rise_ls)
		var cs: Dictionary = IsleAstro.compute(set_ls)
		_near(float(cr["moon_alt"]), MOON_RISE_ALT, 0.8, "B 月出高度 %d-%02d-%02d" % [int(d[0]), int(d[1]), int(d[2])])
		_near(float(cr["moon_az"]), float(d[5]), 2.0, "B 月出方位 %d-%02d-%02d" % [int(d[0]), int(d[1]), int(d[2])])
		_near(float(cs["moon_alt"]), MOON_RISE_ALT, 0.8, "B 月落高度 %d-%02d-%02d" % [int(d[6]), int(d[7]), int(d[8])])
		_near(float(cs["moon_az"]), float(d[11]), 2.0, "B 月落方位 %d-%02d-%02d" % [int(d[6]), int(d[7]), int(d[8])])
		# 18:00 样本属于“该行标注的那一天”：月出在 23:xx 的样本，18:00 已在次日（月出前约 6h）。
		var at18_ls: float = _ls(int(d[0]), int(d[1]), int(d[2]), 18, 0)
		if int(d[3]) > 18:
			at18_ls += 86400.0
		var at18: Dictionary = IsleAstro.compute(at18_ls)
		_near(float(at18["moon_alt"]), float(d[12]), 1.5, "B 18:00 高度 %d-%02d-%02d" % [int(d[0]), int(d[1]), int(d[2])])
		_near(float(at18["moon_illum"]), float(d[13]), 0.03, "B 18:00 照亮 %d-%02d-%02d" % [int(d[0]), int(d[1]), int(d[2])])
	# day_events 月出/月没时刻（同一天升落的事件才比对）
	var ev_days := [
		[2026, 10, 26, 1065.0, 378.0], [2026, 11, 24, 1030.0, 368.0],
		[2026, 12, 24, 1080.0, 430.0], [2027, 1, 22, 1075.0, 409.0],
		[2027, 1, 16, 720.0, 28.0], [2026, 12, 31, 24.0, 737.0], [2027, 1, 29, 6.0, 686.0],
	]
	for e in ev_days:
		var ev: Dictionary = IsleAstro.day_events(_ls(int(e[0]), int(e[1]), int(e[2]), 12, 0))
		_near(float(ev["moonrise"]), float(e[3]), 3.0, "B day_events 月出 %d-%02d-%02d" % [int(e[0]), int(e[1]), int(e[2])])
		_near(float(ev["moonset"]), float(e[4]), 3.0, "B day_events 月没 %d-%02d-%02d" % [int(e[0]), int(e[1]), int(e[2])])
	# 时区字段：本地钟面字段喂进去必须原样回来（防 UTC/本地混用）
	var dt: Dictionary = IsleAstro.local_datetime(_ls(2026, 10, 26, 18, 0))
	_ok(int(dt["year"]) == 2026 and int(dt["month"]) == 10 and int(dt["day"]) == 26 and int(dt["hour"]) == 18 and int(dt["minute"]) == 0, "B 本地时区字段自洽 %s" % str(dt))

# ---------------------------------------------------------------- C 完整周期
func _test_cycle_continuity() -> void:
	# 从新月前 16h（本地 10-10 08:00）起采样 238×3h=29.6 天，确保完整覆盖一次 Δλ 回绕。
	var start: float = _ls_utc("2026-10-10T00:00:00")
	var prev_d: float = -1.0
	var wraps := 0
	var min_k := 2.0
	var max_k := -1.0
	var bad_illum := 0
	var bad_step := 0
	var bad_vis := 0
	var samples := 0
	for i in range(0, 238):
		var ls: float = start + float(i) * 10800.0
		var jd: float = IsleAstro.jd_from_local(ls)
		var sun: Dictionary = IsleAstro.sun_position(jd)
		var moon: Dictionary = IsleAstro.moon_position(jd)
		var d: float = fposmod(float(moon["lon"]) - float(sun["lon"]), 360.0)
		var k: float = float(moon["illum"])
		var c: Dictionary = IsleAstro.compute(ls)
		min_k = minf(min_k, k)
		max_k = maxf(max_k, k)
		if absf(k - float(c["moon_illum"])) > 0.001:
			bad_illum += 1
		if absf(k - (1.0 - cos(deg_to_rad(d))) * 0.5) > 0.01:
			bad_illum += 1
		if prev_d >= 0.0:
			var step: float = d - prev_d
			if step < -300.0:
				wraps += 1
			elif step < 0.8 or step > 2.5:
				bad_step += 1
		prev_d = d
		# 可见性契约（与 main._moon_visibility 同一公式）
		var vis: float = smoothstep(-0.02, 0.06, sin(deg_to_rad(float(c["moon_alt"]))))
		if float(c["moon_alt"]) < -2.5 and vis > 0.0001:
			bad_vis += 1
		if float(c["moon_alt"]) > 5.0 and vis < 0.9999:
			bad_vis += 1
		samples += 1
	_ok(bad_illum == 0, "C 照亮比例/相位角自洽（%d 个样本坏值 %d）" % [samples, bad_illum])
	_ok(bad_step == 0, "C Δλ 连续推进（坏步长 %d）" % bad_step)
	_ok(wraps == 1, "C Δλ 在 29.6 天内只回绕一次（wraps=%d）" % wraps)
	_ok(min_k < 0.01 and max_k > 0.99, "C 完整周期覆盖新月到满月（min=%.3f max=%.3f）" % [min_k, max_k])
	_ok(bad_vis == 0, "C 可见性契约（坏样本 %d）" % bad_vis)

# ---------------------------------------------------------------- D 渲染端月盘模型
## 与新版 sky.gdshader 月盘公式逐行对应：mx=太阳方向投影（亮侧轴），
## n·L = px*sinα + pz*cosα，cosα=2k−1；返回亮面比例与亮/暗像素质心。
func _disk_stats(sun_dir: Vector3, moon_dir: Vector3, illum: float, n: int = 40) -> Dictionary:
	var md: Vector3 = moon_dir.normalized()
	var sp: Vector3 = sun_dir - md * sun_dir.dot(md)
	var mx: Vector3 = sp.normalized() if sp.length() > 0.0001 else Vector3.RIGHT
	var my: Vector3 = md.cross(mx).normalized()
	var cosa: float = clampf(2.0 * illum - 1.0, -1.0, 1.0)
	var sina: float = sqrt(maxf(1.0 - cosa * cosa, 0.0))
	var lit := 0
	var total := 0
	var lit_sum := Vector2.ZERO
	var dark_sum := Vector2.ZERO
	for iy in range(-n, n + 1):
		for ix in range(-n, n + 1):
			var px: float = float(ix) / float(n)
			var py: float = float(iy) / float(n)
			if px * px + py * py > 1.0:
				continue
			total += 1
			var pz: float = sqrt(maxf(1.0 - px * px - py * py, 0.0))
			var nl: float
			if sina < 0.02:
				nl = pz * cosa
			else:
				nl = px * sina + pz * cosa
			if nl > 0.0:
				lit += 1
				lit_sum += Vector2(px, py)
			else:
				dark_sum += Vector2(px, py)
	var lit_n := float(lit)
	var dark_n := float(total - lit)
	return {
		"frac": lit_n / float(total),
		"lit_c": (lit_sum / lit_n) if lit_n > 0.0 else Vector2.ZERO,
		"dark_c": (dark_sum / dark_n) if dark_n > 0.0 else Vector2.ZERO,
		"sina": sina,
	}

func _test_render_geometry() -> void:
	var phases := [
		["2026-10-10T15:50:00", 0.0], ["2026-10-14T13:13:00", 45.0],
		["2026-10-18T16:13:00", 90.0], ["2026-10-22T15:19:00", 135.0],
		["2026-10-26T04:12:00", 180.0], ["2026-10-29T11:23:00", 225.0],
		["2026-11-01T20:28:00", 270.0], ["2026-11-05T11:02:00", 315.0],
	]
	var bad_frac := 0
	var bad_orient := 0
	var checked := 0
	for p in phases:
		# 每个相取相位时刻 ±6h 三个样本（不固定在 18:00）
		for off in [-21600.0, 0.0, 21600.0]:
			var ls: float = _ls_utc(str(p[0])) + off
			var c: Dictionary = IsleAstro.compute(ls)
			var sd: Vector3 = IsleMath.sun_dir(float(c["sun_alt"]), float(c["sun_az"]))
			var md: Vector3 = IsleMath.sun_dir(float(c["moon_alt"]), float(c["moon_az"]))
			var st: Dictionary = _disk_stats(sd, md, float(c["moon_illum"]))
			if absf(float(st["frac"]) - float(c["moon_illum"])) > 0.03:
				bad_frac += 1
			var sina: float = float(st["sina"])
			var k: float = float(c["moon_illum"])
			if sina > 0.15:
				checked += 1
				if k < 0.45:
					if (st["lit_c"] as Vector2).x < 0.55:
						bad_orient += 1
				elif k > 0.55:
					if (st["dark_c"] as Vector2).x > -0.55:
						bad_orient += 1
	_ok(bad_frac == 0, "D 月盘亮面比例与 astro 照亮比例一致（坏样本 %d/24）" % bad_frac)
	_ok(checked >= 12 and bad_orient == 0, "D 亮侧朝太阳（检查 %d，坏 %d；旧固定基实现会在高空月相反向）" % [checked, bad_orient])

# ---------------------------------------------------------------- E 可见性
func _moon_vis(alt_deg: float) -> float:
	return smoothstep(-0.02, 0.06, sin(deg_to_rad(alt_deg)))

func _test_visibility_contract() -> void:
	var cases := [
		[2026, 12, 9, 18, 0, false],   # 新月日 18:00 高度 −4.0°：必须不可见
		[2026, 11, 2, 18, 0, false],   # 下弦日 18:00 高度 −48.4°
		[2027, 1, 29, 18, 0, false],
		[2026, 10, 26, 18, 0, true],   # 满月刚升起 +2.3°：可见（淡入）
		[2026, 10, 19, 18, 0, true],   # 上弦 18:00 高度 +42.4°
		[2026, 11, 17, 18, 0, true],
	]
	for c in cases:
		var a: float = float(IsleAstro.compute(_ls(int(c[0]), int(c[1]), int(c[2]), int(c[3]), int(c[4])))["moon_alt"])
		var vis: float = _moon_vis(a)
		if bool(c[5]):
			_ok(vis > 0.5, "E 可见 %d-%02d-%02d %02d:%02d alt=%.1f vis=%.2f" % [int(c[0]), int(c[1]), int(c[2]), int(c[3]), int(c[4]), a, vis])
		else:
			_ok(vis <= 0.0001, "E 不可见 %d-%02d-%02d %02d:%02d alt=%.1f vis=%.2f" % [int(c[0]), int(c[1]), int(c[2]), int(c[3]), int(c[4]), a, vis])
	_near(_moon_vis(-90.0), 0.0, 0.0001, "E 地平线下 90°")
	_near(_moon_vis(3.44), 1.0, 0.0001, "E 高度超过 +3.44° 全可见")
	# 固定 18:00 证伪：同一天不同时刻高度差异巨大（旧“固定 18:00 见月”假设不成立）
	var h02: float = float(IsleAstro.compute(_ls(2026, 10, 26, 2, 0))["moon_alt"])
	var h10: float = float(IsleAstro.compute(_ls(2026, 10, 26, 10, 0))["moon_alt"])
	var h18: float = float(IsleAstro.compute(_ls(2026, 10, 26, 18, 0))["moon_alt"])
	var h22: float = float(IsleAstro.compute(_ls(2026, 10, 26, 22, 0))["moon_alt"])
	print("[P8MOON] 2026-10-26 高度 02:00=%.1f 10:00=%.1f 18:00=%.1f 22:00=%.1f" % [h02, h10, h18, h22])
	_ok(h02 > 40.0 and h10 < -20.0 and h22 > 40.0, "E 固定 18:00 假设被证伪（02/10/18/22 高度 %.1f/%.1f/%.1f/%.1f）" % [h02, h10, h18, h22])

# ---------------------------------------------------------------- 接线检查
func _test_shader_wiring() -> void:
	var f := FileAccess.open("res://shaders/sky.gdshader", FileAccess.READ)
	if f == null:
		_ok(false, "接线 sky.gdshader 可读")
		return
	var src := f.get_as_text()
	f.close()
	_ok(src.contains("sun_proj") and src.contains("px * sina + pz * cosa"), "接线 sky.gdshader 使用“朝太阳投影”的月盘明暗模型")
	var fm := FileAccess.open("res://scripts/main.gd", FileAccess.READ)
	if fm == null:
		_ok(false, "接线 main.gd 可读")
		return
	var msrc := fm.get_as_text()
	fm.close()
	_ok(msrc.contains("_moon_visibility") and msrc.contains("moon_phase_deg"), "接线 main.gd 使用真实高度可见性与八相距角命名")
