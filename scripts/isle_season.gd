class_name IsleSeason
extends RefCounted
## P8 四季视觉参数（纯函数）。
##
## 输入是 IsleCalendar.parts() 给出的连续季节权重（春/夏/秋/冬，和恒为 1），
## 输出是本工程现有材质/实例/粒子能直接消费的参数：草坪 tint、树冠与灌木色、
## 树冠保留比例、花按物种保留比例、落叶强度与颜色。
##
## 约束：不重建任何几何、不逐帧写实例；所有值都是"权重加权平均"得到的连续量，
## 因此跨季、跳日期、拖时间轴都不会出现硬切。真正的写入时机与节流由 main.gd 负责。

const FLOWER_SPECIES := ["Tulip", "Daisy", "Bluebell", "Poppy"]

## 四季目标参数（sRGB 乘色；canopy/cards 是保留比例；flowers 对应 FLOWER_SPECIES）。
## 春：返青、花渐开；夏：浓密；秋：黄橙红、缓慢落叶；冬：稀疏裸枝、几乎无花、只留零星红梅（用 Poppy 代）。
const SEASON_TABLE := [
	{
		"id": "spring",
		"grass": Color(1.04, 1.07, 0.98),
		"foliage": Color(0.98, 1.12, 0.80),
		"bush": Color(1.02, 1.14, 0.82),
		"canopy": 0.96,
		"cards": 0.86,
		"flowers": [1.0, 1.0, 1.0, 0.92],
		"leaf_fall": 0.0,
		"drift": Color(0.98, 0.80, 0.78),
	},
	{
		"id": "summer",
		"grass": Color(0.94, 1.05, 0.82),
		"foliage": Color(0.84, 1.00, 0.78),
		"bush": Color(0.90, 1.03, 0.80),
		"canopy": 1.0,
		"cards": 1.0,
		"flowers": [0.62, 1.0, 0.86, 1.0],
		"leaf_fall": 0.0,
		"drift": Color(1.0, 0.92, 0.72),
	},
	{
		"id": "autumn",
		"grass": Color(1.22, 0.99, 0.55),
		"foliage": Color(1.48, 0.86, 0.34),
		"bush": Color(1.30, 0.92, 0.42),
		"canopy": 0.94,
		"cards": 1.0,
		"flowers": [0.05, 0.28, 0.06, 0.48],
		"leaf_fall": 1.0,
		"drift": Color(0.95, 0.52, 0.18),
	},
	{
		"id": "winter",
		"grass": Color(0.92, 0.87, 0.72),
		"foliage": Color(0.88, 0.78, 0.66),
		"bush": Color(0.90, 0.82, 0.72),
		"canopy": 0.0,           # P8.1：冬季完全落叶，只保留树干/裸枝；不再留残冠（残冠是随机子集，会悬空）
		"cards": 0.0,             # 叶卡是浮在冠层里的碎叶，裸枝后必须全收，否则悬空
		"flowers": [0.0, 0.0, 0.0, 0.0],    # 花床全收；冬季红花改由 dedicated WinterBloom 地栽节点承担
		"leaf_fall": 0.0,
		"drift": Color(0.92, 0.92, 0.94),
	},
]

## 权重数组（4 元素，和恒为 1）→ 连续视觉参数。
static func visuals(weights: Array) -> Dictionary:
	var w := _normalized(weights)
	var grass := Color(0, 0, 0)
	var foliage := Color(0, 0, 0)
	var bush := Color(0, 0, 0)
	var canopy := 0.0
	var cards := 0.0
	var flowers := [0.0, 0.0, 0.0, 0.0]
	var leaf_fall := 0.0
	var drift := Color(0, 0, 0)
	for i in range(4):
		var wi: float = w[i]
		var row: Dictionary = SEASON_TABLE[i]
		grass += (row["grass"] as Color) * wi
		foliage += (row["foliage"] as Color) * wi
		bush += (row["bush"] as Color) * wi
		canopy += float(row["canopy"]) * wi
		cards += float(row["cards"]) * wi
		leaf_fall += float(row["leaf_fall"]) * wi
		drift += (row["drift"] as Color) * wi
		var fl: Array = row["flowers"]
		for k in range(4):
			flowers[k] = float(flowers[k]) + float(fl[k]) * wi
	return {
		"grass_tint": grass,
		"foliage_tint": foliage,
		"bush_tint": bush,
		"canopy_keep": clampf(canopy, 0.0, 1.0),
		"leafcard_keep": clampf(cards, 0.0, 1.0),
		"flower_keep": flowers,
		"leaf_fall": clampf(leaf_fall, 0.0, 1.0),
		"drift_color": drift,
	}

## 主季节索引（权重最大者）；并列时按春→夏→秋→冬稳定取第一个。
static func dominant(weights: Array) -> int:
	var w := _normalized(weights)
	var best := 0
	for i in range(1, 4):
		if w[i] > w[best] + 0.0001:
			best = i
	return best

static func flower_keep_for(visuals_dict: Dictionary, species: String) -> float:
	var idx := FLOWER_SPECIES.find(species)
	if idx < 0:
		return 1.0
	return clampf(float((visuals_dict["flower_keep"] as Array)[idx]), 0.0, 1.0)

## 两个权重数组之间的最大分量差：main 用它判断"季节是否真的变了"，避免每帧写实例。
static func weight_delta(a: Array, b: Array) -> float:
	var d := 0.0
	for i in range(4):
		var av: float = float(a[i]) if i < a.size() else 0.0
		var bv: float = float(b[i]) if i < b.size() else 0.0
		d = maxf(d, absf(av - bv))
	return d

static func _normalized(weights: Array) -> Array:
	var w := [0.0, 0.0, 0.0, 0.0]
	var sum := 0.0
	for i in range(4):
		var v: float = maxf(float(weights[i]), 0.0) if i < weights.size() else 0.0
		w[i] = v
		sum += v
	if sum <= 0.000001:
		return [0.25, 0.25, 0.25, 0.25]
	for i in range(4):
		w[i] = float(w[i]) / sum
	return w
