class_name IsleWaves
extends RefCounted
## CPU 侧海浪高度：与 shaders/sea.gdshader 的 wave_h() / wave_grad() 严格同源。
##
## 唯一数据源是本文件的 WAVES 表。sea.gdshader 里的 wave_h()/wave_grad() 是用同一组
## 系数逐行展开的（工具 tools/probe_water6.gd 会解析 shader 文本、逐系数比对并数值复算，
## 见测试输出）。main.gd 的 _wave_h() 应改为：
##     return IsleWaves.height(x, z, _frame_t, float(_sea_wave_detail), _wave_height)
## 这样船体吃水/俯仰/横滚与 GPU 顶点位移完全一致（同一帧、同一 detail、同一 wave_height）。
##
## detail 语义（0..3，与 sea_wave_detail 画质档一一对应）：
##   0 -> 3 组波（140m / 78m / 41m）        —— 低档：仍有可读的大浪，网格粗也不闪
##   1 -> 4 组波（+24m）                    —— 中档
##   2 -> 6 组波（+16m / +34.7m 交叉涌浪）  —— 高档（默认，接近 P5 观感）
##   3 -> 7 组波（+20m 细碎涌浪）           —— 极高/极致
## 波高 = (Σ A_i * sin(k_i·p + ω_i*t + φ_i)) * height_scale
##
## 为什么不用 Gerstner 水平位移：水平位移会让"世界坐标 (x,z) 处的水面高度"需要反解
## （CPU 端 Newton 迭代），船体吃水就会有厘米级抖动；解析高度 + 分析法线修正能在
## 不牺牲 CPU/GPU 同源性的前提下达到同样的浪形可读性（见 docs/P6_RESEARCH_VISUAL.md）。

## 每组波：amp 振幅(m) / kx,kz 波矢 / omega 角速度 / phase 相位 / need 启用所需 detail 门槛。
## 前 5 组 = P5 sea.gdshader 原参数（保证观感连续），后 2 组是 P6 新增交叉涌浪。
const WAVES := [
	{"amp": 0.420, "kx": 0.035, "kz": 0.028, "omega": 0.420, "phase": 0.000, "need": 0.0},
	{"amp": 0.260, "kx": -0.061, "kz": 0.052, "omega": 0.580, "phase": 1.700, "need": 0.0},
	{"amp": 0.150, "kx": 0.124, "kz": -0.087, "omega": 0.860, "phase": 3.100, "need": 0.0},
	{"amp": 0.085, "kx": -0.201, "kz": -0.168, "omega": 1.220, "phase": 5.000, "need": 0.5},
	{"amp": 0.050, "kx": 0.317, "kz": 0.244, "omega": 1.630, "phase": 0.600, "need": 1.5},
	{"amp": 0.072, "kx": 0.148, "kz": 0.212, "omega": 1.020, "phase": 2.350, "need": 1.5},
	{"amp": 0.038, "kx": -0.256, "kz": 0.183, "omega": 1.380, "phase": 4.450, "need": 2.5},
]

const DETAIL_MAX := 3
const WAVE_COUNT_MAX := 7


## 指定 detail 下实际参与位移的波数（与 shader 里的 if (wave_detail >= x) 门槛一一对应）。
static func wave_count(detail: float) -> int:
	var n := 0
	for w in WAVES:
		if detail + 0.0001 >= float(w["need"]):
			n += 1
	return n


## 水面高度（米）。x/z 世界坐标，t 秒，detail 0..3，height_scale 对应 shader 的 wave_height。
static func height(x: float, z: float, t: float, detail: float = float(DETAIL_MAX), height_scale: float = 1.0) -> float:
	var h := 0.0
	for i in range(wave_count(detail)):
		var w: Dictionary = WAVES[i]
		h += float(w["amp"]) * sin(float(w["kx"]) * x + float(w["kz"]) * z + float(w["omega"]) * t + float(w["phase"]))
	return h * height_scale


## 最高细节（detail=3）下的水面高度：用于与 GPU 满档位移对照的"真值"。
static func height_at_detail_max(x: float, z: float, t: float, height_scale: float = 1.0) -> float:
	return height(x, z, t, float(DETAIL_MAX), height_scale)


## 解析梯度 dH/dx, dH/dz（与 shader wave_grad() 同源，可用来算法线/坡度）。
static func grad(x: float, z: float, t: float, detail: float = float(DETAIL_MAX), height_scale: float = 1.0) -> Vector2:
	var g := Vector2.ZERO
	for i in range(wave_count(detail)):
		var w: Dictionary = WAVES[i]
		var c := cos(float(w["kx"]) * x + float(w["kz"]) * z + float(w["omega"]) * t + float(w["phase"]))
		g += Vector2(float(w["kx"]), float(w["kz"])) * float(w["amp"]) * c
	return g * height_scale


## 水面法线（Y 向上，右手系；与 sea.gdshader fragment 里 normalize(vec3(-gx, 1, -gz)) 一致）。
static func normal(x: float, z: float, t: float, detail: float = float(DETAIL_MAX), height_scale: float = 1.0) -> Vector3:
	var g := grad(x, z, t, detail, height_scale)
	return Vector3(-g.x, 1.0, -g.y).normalized()


## 理论最大振幅（Σ|A_i| * height_scale），探针用于检查波高范围。
static func amp_sum(detail: float, height_scale: float = 1.0) -> float:
	var s := 0.0
	for i in range(wave_count(detail)):
		s += absf(float(WAVES[i]["amp"]))
	return s * height_scale


## 采样一段波面的极值/均值（探针与调试用）。
static func sample_stats(detail: float, t: float, height_scale: float, count: int = 64, spacing: float = 3.7) -> Dictionary:
	var lo := 1e9
	var hi := -1e9
	var sum := 0.0
	var prev := 0.0
	var max_step := 0.0
	for i in range(count):
		var x := float(i % 8) * spacing * 0.9 + 0.37
		var z := float(i / 8) * spacing + 0.61
		var h := height(x, z, t, detail, height_scale)
		lo = minf(lo, h)
		hi = maxf(hi, h)
		sum += h
		if i > 0:
			max_step = maxf(max_step, absf(h - prev))
		prev = h
	return {"min": lo, "max": hi, "mean": sum / float(count), "max_step": max_step}
