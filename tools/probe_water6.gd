extends SceneTree
## P6 水面同源探针。
## 1) 解析 shaders/sea.gdshader 里 wave_h()/wave_grad() 逐行展开的系数（7 组波）；
## 2) 与 scripts/isle_waves.gd 的 WAVES 表逐项比对（容差 1e-6）；
## 3) 用"从 shader 文本解析出的系数"独立复算高度，与 IsleWaves.height() 采样对比（容差 1e-4）；
## 4) 检查波高范围、连续性（1cm 步长）、梯度/法线一致性、detail 门槛波数。
## 用法：console exe --headless --path D:/休闲小岛幻境/游戏工程 --script res://tools/probe_water6.gd

const SEA_SHADER := "res://shaders/sea.gdshader"
const WAVES_SCRIPT := "res://scripts/isle_waves.gd"
const MAIN_SCRIPT := "res://scripts/main.gd"

var checks := 0
var fails := 0
var warns := 0

func _check(cond: bool, msg: String) -> void:
	checks += 1
	if cond:
		print("  [PASS] ", msg)
	else:
		fails += 1
		print("  [FAIL] ", msg)

func _warn(msg: String) -> void:
	warns += 1
	print("  [WARN] ", msg)

func _initialize() -> void:
	print("=== probe_water6: sea.gdshader <-> isle_waves.gd 同源校验 ===")
	var txt := FileAccess.get_file_as_string(SEA_SHADER)
	_check(txt.length() > 4000, "sea.gdshader 可读（%d bytes）" % txt.length())
	var waves_script: Script = load(WAVES_SCRIPT)
	var inst: Object = waves_script.new()
	var waves: Array = waves_script.get_script_constant_map()["WAVES"]
	_check(waves.size() == 7, "isle_waves.WAVES 组数 = 7（实际 %d）" % waves.size())

	var re_h := RegEx.new()
	re_h.compile("h\\s*\\+=\\s*([0-9.]+)\\s*\\*\\s*gate\\(([0-9.]+)\\)\\s*\\*\\s*sin\\(dot\\(p,\\s*vec2\\((-?[0-9.]+),\\s*(-?[0-9.]+)\\)\\)\\s*\\+\\s*t\\s*\\*\\s*([0-9.]+)\\s*\\+\\s*(-?[0-9.]+)\\);")
	var hs := re_h.search_all(txt)
	_check(hs.size() == waves.size(), "shader wave_h() 展开行数 = %d（实际 %d）" % [waves.size(), hs.size()])

	var sw_list: Array = []
	var coeff_ok := true
	for i in range(mini(hs.size(), waves.size())):
		var m: RegExMatch = hs[i]
		var sw := {
			"amp": float(m.get_string(1)), "need": float(m.get_string(2)),
			"kx": float(m.get_string(3)), "kz": float(m.get_string(4)),
			"omega": float(m.get_string(5)), "phase": float(m.get_string(6)),
		}
		sw_list.append(sw)
		var w: Dictionary = waves[i]
		var bad: Array = []
		for key in ["amp", "need", "kx", "kz", "omega", "phase"]:
			if absf(float(sw[key]) - float(w[key])) > 1e-6:
				bad.append("%s(shader=%s, waves=%s)" % [key, sw[key], w[key]])
		if not bad.is_empty():
			coeff_ok = false
			print("    [diff] 第%d组: %s" % [i, ", ".join(PackedStringArray(bad))])
	_check(coeff_ok, "7 组波 amp/kx/kz/omega/phase/need 与 isle_waves.gd 完全一致（容差 1e-6）")

	var re_g := RegEx.new()
	re_g.compile("c\\s*=\\s*gate\\(([0-9.]+)\\)\\s*\\*\\s*cos\\(dot\\(p,\\s*vec2\\((-?[0-9.]+),\\s*(-?[0-9.]+)\\)\\)\\s*\\+\\s*t\\s*\\*\\s*([0-9.]+)\\s*\\+\\s*(-?[0-9.]+)\\);")
	var gs := re_g.search_all(txt)
	_check(gs.size() == waves.size(), "shader wave_grad() 展开行数 = %d（实际 %d）" % [waves.size(), gs.size()])
	var grad_ok := true
	for i in range(mini(gs.size(), sw_list.size())):
		var m: RegExMatch = gs[i]
		var sw: Dictionary = sw_list[i]
		var bad: Array = []
		if absf(float(m.get_string(1)) - float(sw["need"])) > 1e-6:
			bad.append("need")
		if absf(float(m.get_string(2)) - float(sw["kx"])) > 1e-6:
			bad.append("kx")
		if absf(float(m.get_string(3)) - float(sw["kz"])) > 1e-6:
			bad.append("kz")
		if absf(float(m.get_string(4)) - float(sw["omega"])) > 1e-6:
			bad.append("omega")
		if absf(float(m.get_string(5)) - float(sw["phase"])) > 1e-6:
			bad.append("phase")
		if not bad.is_empty():
			grad_ok = false
			print("    [diff] grad 第%d组: %s" % [i, ", ".join(PackedStringArray(bad))])
	_check(grad_ok, "wave_grad() 系数与 wave_h()/WAVES 一致")

	# 从 shader 系数独立复算，与 CPU 实现采样比对
	var max_err := 0.0
	var samples := 0
	for di in range(4):
		var detail := float(di)
		for ti in [0.0, 3.7, 21.3]:
			for hsi in [0.5, 1.0, 1.6]:
				for i in range(120):
					var x := float(i) * 1.37 - 130.0
					var z := float(i) * 0.91 - 70.0
					var ref := 0.0
					for j in range(sw_list.size()):
						var sw: Dictionary = sw_list[j]
						if detail + 0.0001 >= float(sw["need"]):
							ref += float(sw["amp"]) * sin(float(sw["kx"]) * x + float(sw["kz"]) * z + float(sw["omega"]) * ti + float(sw["phase"]))
					ref *= float(hsi)
					var got: float = float(inst.callv("height", [x, z, ti, detail, hsi]))
					max_err = maxf(max_err, absf(got - ref))
					samples += 1
	_check(max_err < 1e-4, "IsleWaves.height 与 shader 公式独立复算 %d 点最大误差 %.6f < 1e-4" % [samples, max_err])

	# 波数门槛
	var counts: Array = []
	for di in range(4):
		counts.append(int(inst.callv("wave_count", [float(di)])))
	_check(counts == [3, 4, 6, 7], "各 detail 波数 = [3,4,6,7]（实际 %s）" % str(counts))

	# 理论振幅上限 / 实际范围
	var amp3: float = float(inst.callv("amp_sum", [3.0, 1.0]))
	_check(absf(amp3 - 1.075) < 1e-6, "detail=3 理论最大振幅 = %.3f m（7 组振幅和）" % amp3)
	var lo := 1e9
	var hi := -1e9
	for i in range(600):
		var x := float(i) * 2.31 - 500.0
		var z := float(i) * 1.77 - 400.0
		var h: float = float(inst.callv("height", [x, z, 7.31, 3.0, 1.6]))
		lo = minf(lo, h)
		hi = maxf(hi, h)
	_check(hi <= 1.075 * 1.6 + 1e-6 and lo >= -1.075 * 1.6 - 1e-6, "波高范围 [%.3f, %.3f] 在 ±%.3f 内" % [lo, hi, 1.075 * 1.6])

	# 连续性：1cm 步长的高度跃变必须落在解析斜率上界内
	var slope := 0.0
	for sw in sw_list:
		slope += float(sw["amp"]) * sqrt(float(sw["kx"]) * float(sw["kx"]) + float(sw["kz"]) * float(sw["kz"]))
	var max_step := 0.0
	var prev: float = float(inst.callv("height", [-80.0, 40.0, 5.0, 3.0, 1.6]))
	for i in range(1, 400):
		var x := -80.0 + float(i) * 0.01
		var h: float = float(inst.callv("height", [x, 40.0, 5.0, 3.0, 1.6]))
		max_step = maxf(max_step, absf(h - prev))
		prev = h
	var step_bound := slope * 1.6 * 0.01 * 1.05
	_check(max_step <= step_bound, "连续性：1cm 步长最大跃变 %.5f m <= 解析上界 %.5f m" % [max_step, step_bound])

	# 梯度一致性（与高度中心差分）
	var grad_err := 0.0
	for i in range(40):
		var x := float(i) * 3.1 - 60.0
		var z := float(i) * 2.3 - 40.0
		var e := 0.02
		var gx: float = (float(inst.callv("height", [x + e, z, 9.0, 3.0, 1.0])) - float(inst.callv("height", [x - e, z, 9.0, 3.0, 1.0]))) / (2.0 * e)
		var gz: float = (float(inst.callv("height", [x, z + e, 9.0, 3.0, 1.0])) - float(inst.callv("height", [x, z - e, 9.0, 3.0, 1.0]))) / (2.0 * e)
		var g: Vector2 = inst.callv("grad", [x, z, 9.0, 3.0, 1.0])
		grad_err = maxf(grad_err, absf(g.x - gx))
		grad_err = maxf(grad_err, absf(g.y - gz))
	_check(grad_err < 1e-3, "grad() 与高度中心差分最大误差 %.6f < 1e-3" % grad_err)

	var n: Vector3 = inst.callv("normal", [12.0, -7.0, 4.0, 3.0, 1.0])
	_check(absf(n.length() - 1.0) < 1e-5 and n.y > 0.9, "normal() 为单位向量且 Y 向上（len=%.6f, y=%.3f）" % [n.length(), n.y])

	# height_scale 线性
	var h1: float = float(inst.callv("height", [5.0, -3.0, 2.0, 3.0, 1.0]))
	var h2: float = float(inst.callv("height", [5.0, -3.0, 2.0, 3.0, 2.0]))
	_check(absf(h2 - h1 * 2.0) < 1e-6, "height_scale 线性：h(scale=2) = 2*h(scale=1)")

	# shader 顶点/法线接入点
	_check(txt.contains("VERTEX.y += wave_h(wp, time_s)") or txt.contains("wave_h(VERTEX.xz, time_s)"), "vertex 使用 wave_h(wp, time_s) 位移（wp = VERTEX.xz）")
	_check(txt.contains("wave_height"), "shader 保留 wave_height uniform 并参与位移缩放")
	_check(txt.contains("wave_scale"), "shader 保留 wave_scale uniform（main 设定）")

	# main.gd 集成状态（Lead 负责替换 _wave_h；未完成只告警）
	var main_txt := FileAccess.get_file_as_string(MAIN_SCRIPT)
	if main_txt.contains("IsleWaves.height") or main_txt.contains("IsleWaves.height_at_detail_max"):
		print("  [PASS] main.gd 已改为调用 IsleWaves.height（CPU/GPU 同源）")
	else:
		_warn("main.gd 尚未调用 IsleWaves.height（Lead 待替换 _wave_h；船体 CPU 波高仍用旧 5 波公式）")

	print("=== probe_water6 结果: checks=%d fails=%d warns=%d ===" % [checks, fails, warns])
	quit(0 if fails == 0 else 1)