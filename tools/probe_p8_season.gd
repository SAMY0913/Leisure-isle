extends SceneTree
## P8 阶段 4：四季视觉参数（IsleSeason）与日历季节权重（IsleCalendar）联动的纯函数 probe。
## 运行：Godot_v4.7.2-stable_win64_console.exe --headless --path D:/休闲小岛幻境/游戏工程 --script res://tools/probe_p8_season.gd
## 覆盖：权重归一/非负/和恒 1、四季中点 one-hot、边界连续（无硬切）、视觉参数连续性与极值、
##       花按物种保留顺序、冬季红花（P8.1 屋前 WinterBloom，树顶红梅已移除）、确定性、weight_delta 对称、跨年/闰年边界。
## 退出码：0 = 全部通过；1 = 有失败。

const Cal := preload("res://scripts/isle_calendar.gd")
const Season := preload("res://scripts/isle_season.gd")

var _checks: int = 0
var _fails: Array = []

func _init() -> void:
	var t0: int = Time.get_ticks_msec()
	_run_weight_sanity()
	_run_one_hot_midpoints()
	_run_boundary_continuity()
	_run_visual_ranges()
	_run_flower_species()
	_run_determinism_and_delta()
	print("")
	print("[SUMMARY] checks=%d fail=%d elapsed_ms=%d" % [_checks, _fails.size(), Time.get_ticks_msec() - t0])
	if _fails.is_empty():
		print("PROBE_P8_SEASON RESULT: PASS")
		quit(0)
	else:
		for f in _fails:
			print("[FAIL] ", str(f))
		print("PROBE_P8_SEASON RESULT: FAIL")
		quit(1)

# ---------------------------------------------------------------- 工具

func _check(cond: bool, name: String, detail: String = "") -> bool:
	_checks += 1
	if not cond:
		_fails.append(name + (("  " + detail) if detail != "" else ""))
	return cond

func _weights_at(y: int, mo: int, d: int, h: int = 12) -> Array:
	var p: Dictionary = Cal.season_at(y, mo, d, float(h) * 3600.0)
	return p.get("season_weights", [0.25, 0.25, 0.25, 0.25]) as Array

func _sum(w: Array) -> float:
	var s := 0.0
	for v in w:
		s += float(v)
	return s

func _near(a: float, b: float, eps: float = 0.000001) -> bool:
	return absf(a - b) <= eps

# ---------------------------------------------------------------- 权重基本性质

func _run_weight_sanity() -> void:
	var samples: Array = [
		[2026, 1, 1], [2026, 2, 15], [2026, 3, 1], [2026, 4, 15], [2026, 6, 1],
		[2026, 7, 15], [2026, 9, 1], [2026, 10, 20], [2026, 12, 1], [2026, 12, 21],
		[2027, 1, 15], [2024, 2, 29], [2028, 2, 29], [2026, 3, 11], [2026, 5, 21],
	]
	for s in samples:
		var w := _weights_at(int(s[0]), int(s[1]), int(s[2]))
		_check(w.size() == 4, "weights size 4", str(s))
		_check(_near(_sum(w), 1.0, 0.0001), "weights sum=1", str(s) + " sum=" + str(_sum(w)))
		var neg := false
		for v in w:
			if float(v) < -0.0000001:
				neg = true
		_check(not neg, "weights non-negative", str(s))
	for w in [[0.0, 0.0, 0.0, 0.0], [-1.0, 2.0, 0.0, 0.0], [9.0, 0.0, 0.0, 0.0]]:
		var v: Dictionary = Season.visuals(w)
		_check(v.has("grass_tint") and v.has("canopy_keep") and v.has("flower_keep"), "visuals keys", str(w))
		var fk: Array = v["flower_keep"]
		_check(fk.size() == 4, "flower_keep size 4", str(w))
	_check(Season.visuals([]).size() > 0, "visuals empty weights tolerated")

# ---------------------------------------------------------------- 季节中点 one-hot

func _run_one_hot_midpoints() -> void:
	var cases: Array = [
		[2026, 4, 15, 0, "spring"],
		[2026, 7, 15, 1, "summer"],
		[2026, 10, 15, 2, "autumn"],
		[2027, 1, 15, 3, "winter"],
	]
	for cs in cases:
		var w := _weights_at(int(cs[0]), int(cs[1]), int(cs[2]))
		var idx := int(cs[3])
		var other := 0.0
		for i in range(4):
			if i != idx:
				other = maxf(other, float(w[i]))
		_check(float(w[idx]) > 0.999, "midpoint dominant", "%s %s" % [str(cs[4]), str(w)])
		_check(other < 0.0001, "midpoint one-hot", "%s other=%s" % [str(cs[4]), str(w)])
		_check(Season.dominant(w) == idx, "dominant index", "%s %s" % [str(cs[4]), str(w)])
		_check(String(Cal.season_name(idx)) == String(Cal.SEASON_NAMES[idx]), "season name", str(cs[4]))

# ---------------------------------------------------------------- 边界连续（不硬切）

func _run_boundary_continuity() -> void:
	# 边界日 0 点：相邻两季各 0.5，且逐小时变化远小于 0.03（无硬切）。
	var boundaries: Array = [
		[2026, 3, 1, 3, 0],   # 冬→春
		[2026, 6, 1, 0, 1],   # 春→夏
		[2026, 9, 1, 1, 2],   # 夏→秋
		[2026, 12, 1, 2, 3],  # 秋→冬
	]
	for b in boundaries:
		var y := int(b[0]); var mo := int(b[1]); var d := int(b[2])
		var prev := int(b[3]); var cur := int(b[4])
		var w0 := _weights_at(y, mo, d, 0)
		_check(absf(float(w0[prev]) - 0.5) < 0.02, "boundary 50/50 prev", "%02d-%02d w=%s" % [mo, d, str(w0)])
		_check(absf(float(w0[cur]) - 0.5) < 0.02, "boundary 50/50 cur", "%02d-%02d w=%s" % [mo, d, str(w0)])
		var prev_w := w0
		var max_step := 0.0
		var base: float = Cal.to_local_seconds(y, mo, d, 0) - 12.0 * 3600.0
		for h in range(48):
			var t := base + float(h) * 3600.0
			var wn: Array = Cal.parts(t).get("season_weights", [0.25, 0.25, 0.25, 0.25]) as Array
			max_step = maxf(max_step, Season.weight_delta(prev_w, wn))
			prev_w = wn
		_check(max_step < 0.03, "boundary hourly smooth", "%02d-%02d max_step=%.4f" % [mo, d, max_step])
	# 边界前 10 天权重应几乎为上一季；后 10 天几乎为下一季。
	var pre := _weights_at(2026, 2, 20)
	var post := _weights_at(2026, 3, 11, 0)
	_check(float(pre[3]) > 0.95, "10d before boundary prev", str(pre))
	_check(float(post[0]) > 0.95, "10d after boundary cur", str(post))
	# 跨年：12-31 23:00 与 01-01 00:00 权重连续，且 1 月仍属冬季。
	var w_dec: Array = Cal.parts(Cal.to_local_seconds(2026, 12, 31, 23)).get("season_weights", [])
	var w_jan: Array = Cal.parts(Cal.to_local_seconds(2027, 1, 1, 0)).get("season_weights", [])
	_check(Season.weight_delta(w_dec, w_jan) < 0.01, "year boundary continuous")
	_check(float(w_jan[3]) > 0.99, "Jan is winter", str(w_jan))

# ---------------------------------------------------------------- 视觉参数范围与极值

func _run_visual_ranges() -> void:
	var spring := Season.visuals(_weights_at(2026, 4, 15))
	var summer := Season.visuals(_weights_at(2026, 7, 15))
	var autumn := Season.visuals(_weights_at(2026, 10, 15))
	var winter := Season.visuals(_weights_at(2027, 1, 15))
	_check(float(spring["canopy_keep"]) > 0.9, "spring canopy full")
	_check(float(summer["canopy_keep"]) >= 0.99, "summer canopy full")
	_check(float(autumn["leaf_fall"]) > 0.95, "autumn leaf fall")
	_check(float(winter["leaf_fall"]) < 0.05, "winter no leaf fall")
	# P8.1：冬季完全落叶（0.0），不再保留随机残冠（残冠子集会悬空）。
	_check(float(winter["canopy_keep"]) <= 0.001, "winter canopy removed", str(winter["canopy_keep"]))
	_check(float(winter["leafcard_keep"]) <= 0.05, "winter leaf cards gone", str(winter["leafcard_keep"]))
	_check(float(spring["leafcard_keep"]) > 0.8, "spring leaf cards")
	var gs: Color = spring["grass_tint"]
	var ga: Color = autumn["grass_tint"]
	var gw: Color = winter["grass_tint"]
	_check(gs.g > 1.0, "spring grass greener", str(gs))
	_check(ga.r > 1.15 and ga.b < 0.7, "autumn grass yellow", str(ga))
	_check(gw.r < 0.98 and gw.g < 0.95, "winter grass muted", str(gw))
	var fs: Color = autumn["foliage_tint"]
	_check(fs.r > 1.3 and fs.b < 0.5, "autumn foliage warm", str(fs))
	# 连续：相邻两天视觉参数变化小（每天最多约 10% 权重 → 颜色不硬切）。
	var a1 := Season.visuals(_weights_at(2026, 3, 5))
	var a2 := Season.visuals(_weights_at(2026, 3, 6))
	var dc: float = absf((a1["grass_tint"] as Color).r - (a2["grass_tint"] as Color).r)
	_check(dc < 0.1, "daily grass tint smooth", "%.4f" % dc)
	_check(Season.weight_delta(_weights_at(2026, 3, 5), _weights_at(2026, 3, 6)) < 0.1, "daily weight smooth")

# ---------------------------------------------------------------- 花按物种保留

func _run_flower_species() -> void:
	var spring := Season.visuals(_weights_at(2026, 4, 15))
	var winter := Season.visuals(_weights_at(2027, 1, 15))
	_check(str(Season.FLOWER_SPECIES) == '["Tulip", "Daisy", "Bluebell", "Poppy"]', "flower species order", str(Season.FLOWER_SPECIES))
	for sp in Season.FLOWER_SPECIES:
		var k: float = Season.flower_keep_for(spring, String(sp))
		_check(k > 0.85, "spring flower keeps " + String(sp), "%.2f" % k)
	_check(Season.flower_keep_for(winter, "Tulip") <= 0.0001, "winter no tulip")
	_check(Season.flower_keep_for(winter, "Daisy") <= 0.0001, "winter no daisy")
	_check(Season.flower_keep_for(winter, "Bluebell") <= 0.0001, "winter no bluebell")
	_check(Season.flower_keep_for(winter, "Poppy") <= 0.0001, "winter no garden poppy (P8.1 冬季红花改由屋前 WinterBloom 承担)")
	_check(Season.flower_keep_for(winter, "Unknown") == 1.0, "unknown species keep 1")
	_check(Season.flower_keep_for(spring, "") == 1.0, "empty species keep 1")

# ---------------------------------------------------------------- 确定性与 delta

func _run_determinism_and_delta() -> void:
	var w := _weights_at(2026, 10, 20)
	var v1 := Season.visuals(w)
	var v2 := Season.visuals(w)
	_check((v1["grass_tint"] as Color).is_equal_approx(v2["grass_tint"] as Color), "visuals deterministic")
	_check(Season.weight_delta(w, w) == 0.0, "delta identical zero")
	var a := [1.0, 0.0, 0.0, 0.0]
	var b := [0.0, 0.0, 1.0, 0.0]
	_check(_near(Season.weight_delta(a, b), 1.0), "delta max component")
	_check(_near(Season.weight_delta(b, a), 1.0), "delta symmetric")
	_check(Season.weight_delta([], [0.25, 0.25, 0.25, 0.25]) == 0.25, "delta empty tolerated")
	# 同一个日历秒多次投影结果一致（纯函数、无缓存漂移）。
	var ls: float = Cal.to_local_seconds(2026, 12, 21, 12, 0, 0)
	var p1: Dictionary = Cal.parts(ls)
	var p2: Dictionary = Cal.parts(ls)
	_check(str(p1["season_weights"]) == str(p2["season_weights"]), "calendar projection deterministic")
