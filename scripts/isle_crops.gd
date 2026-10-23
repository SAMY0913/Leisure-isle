class_name IsleCrops
extends RefCounted
## P9 / P1 —— 五种作物的统一静态定义（纯数据，无副作用）。
##
## 本文件只描述"作物是什么"，不持有任何状态、不读取时钟、不依赖场景/UI/NPC。
## 所有时间单位都是"模拟秒"（main.gd 的 _sim_seconds 轴），由 IsleFarm 注入。
##
## 首批五种作物与成熟时间（第一版可调的游戏平衡参数，不是最终规则）：
##   kale 羽衣甘蓝 900 / tomato 番茄 1650 / corn 玉米 1950 / watermelon 西瓜 2250 / wheat 小麦 3000
## 一次性收获：wheat / watermelon / kale（收获后清空）。
## 持续再生长：corn / tomato（首次收获后继续生长，可重复收获；不设固定采收次数上限）。
## 每株作物在"首次成功收获"时返还 1 颗对应种子，之后不再返还。
##
## 种子与成品是不同物品：seed_<crop_id> 与 <crop_id>。

## 稳定作物 id（顺序即默认展示顺序，不表示优先级）。
const CROP_IDS := ["wheat", "corn", "watermelon", "tomato", "kale"]

## 生长阶段标识（视觉系统只读消费；农业权威状态是时间与采收次数，不是阶段文本）。
## 阈值是"当前生长周期的进度比例"：[0.0, 0.25) 播种、[0.25, 0.55) 幼苗、
## [0.55, 0.85) 生长、[0.85, 1.0) 成熟前、>=1.0 成熟。
const STAGE_IDS := ["seed", "sprout", "growing", "ripening", "mature"]
const STAGE_LABELS := ["播种", "幼苗", "生长", "成熟前", "成熟"]
const STAGE_THRESHOLDS := [0.0, 0.25, 0.55, 0.85, 1.0]

## 持续再生长作物的可调开关：true = 无限再生长（第一版默认），false = 每株仅再生长一次。
## 用户尚未确定玉米/番茄的最终生命周期长度，因此本版不写死"采收 N 次后死亡"，
## 只保留可配置规则；若后续确认上限，改这里或 DEFS 中的 regrow_cycles 即可。
const REGROW_INFINITE := true
## 第一版若关闭 REGROW_INFINITE，则每株最多再生长一次（首收 + 一次再生）。
const REGROW_CYCLES_DEFAULT := 1

## 暖季作物在冬季是否允许新种植由调用方（IsleFarm 实例配置）传入，见 plantable()；
## 本文件不保存任何全局可变状态，避免跨存档/跨探针泄漏。

## 作物定义。字段说明：
##   display_name      中文显示名
##   seed_item_id      种子物品 id（seed_ + crop_id）
##   produce_item_id   收获成品物品 id（crop_id）
##   harvest_amount    每次成功收获的成品数量（默认 1，测试/流程打通用，未做经济平衡）
##   first_maturity_seconds  首次成熟所需模拟秒（从播种时刻起算）
##   regrow_seconds    持续再生长作物后续每轮所需模拟秒；一次性作物为 -1
##   regrow            是否持续再生长
##   seasons           允许"新种植"的季节 id 数组（isle_calendar.gd 的 season_id：spring/summer/autumn/winter）
##   winter_ok         冬季是否允许新种（kale=true，其余=false）
##   warm_season       是否暖季作物（allow_warm_in_winter=true 时冬季可新种）
##   returns_seed_on_first_harvest  首次成功收获是否返还 1 颗种子（每株最多一次）
##   regrow_cycles     持续再生长作物"最多可成功收获次数（含首收）"；0=用全局默认
##                     （REGROW_INFINITE ? 无限 : 首收+REGROW_CYCLES_DEFAULT 次再生）
const DEFS := {
	"wheat": {
		"display_name": "小麦",
		"seed_item_id": "seed_wheat",
		"produce_item_id": "wheat",
		"harvest_amount": 1,
		"first_maturity_seconds": 3000.0,
		"regrow_seconds": -1.0,
		"regrow": false,
		"seasons": ["spring", "autumn"],
		"winter_ok": false,
		"warm_season": false,
		"returns_seed_on_first_harvest": true,
		"regrow_cycles": 0,
	},
	"corn": {
		"display_name": "玉米",
		"seed_item_id": "seed_corn",
		"produce_item_id": "corn",
		"harvest_amount": 1,
		"first_maturity_seconds": 1950.0,
		## 玉米/番茄的再生成熟时间同样只是第一版可调参数（用户尚未定生命周期）。
		"regrow_seconds": 900.0,
		"regrow": true,
		"seasons": ["spring", "summer"],
		"winter_ok": false,
		"warm_season": true,
		"returns_seed_on_first_harvest": true,
		"regrow_cycles": 0,
	},
	"watermelon": {
		"display_name": "西瓜",
		"seed_item_id": "seed_watermelon",
		"produce_item_id": "watermelon",
		"harvest_amount": 1,
		"first_maturity_seconds": 2250.0,
		"regrow_seconds": -1.0,
		"regrow": false,
		"seasons": ["summer"],
		"winter_ok": false,
		"warm_season": true,
		"returns_seed_on_first_harvest": true,
		"regrow_cycles": 0,
	},
	"tomato": {
		"display_name": "番茄",
		"seed_item_id": "seed_tomato",
		"produce_item_id": "tomato",
		"harvest_amount": 1,
		"first_maturity_seconds": 1650.0,
		"regrow_seconds": 700.0,
		"regrow": true,
		"seasons": ["spring", "summer", "autumn"],
		"winter_ok": false,
		"warm_season": true,
		"returns_seed_on_first_harvest": true,
		"regrow_cycles": 0,
	},
	"kale": {
		"display_name": "羽衣甘蓝",
		"seed_item_id": "seed_kale",
		"produce_item_id": "kale",
		"harvest_amount": 1,
		"first_maturity_seconds": 900.0,
		"regrow_seconds": -1.0,
		"regrow": false,
		"seasons": ["spring", "autumn", "winter"],
		"winter_ok": true,
		"warm_season": false,
		"returns_seed_on_first_harvest": true,
		"regrow_cycles": 0,
	},
}


# ============================================================ 查询 ===
## 是否为已定义作物。
static func has_crop(crop_id: String) -> bool:
	return DEFS.has(crop_id)


## 返回作物定义副本（无效 id 返回空字典）。调用方可以自由读取，不可依赖引用相等。
static func get_def(crop_id: String) -> Dictionary:
	if not DEFS.has(crop_id):
		return {}
	return (DEFS[crop_id] as Dictionary).duplicate(true)


## 全部作物 id（复制，按 CROP_IDS 顺序）。
static func all_ids() -> Array:
	return CROP_IDS.duplicate()


static func seed_item(crop_id: String) -> String:
	return String(get_def(crop_id).get("seed_item_id", ""))


static func produce_item(crop_id: String) -> String:
	return String(get_def(crop_id).get("produce_item_id", ""))


static func display_name(crop_id: String) -> String:
	return String(get_def(crop_id).get("display_name", crop_id))


static func first_maturity_seconds(crop_id: String) -> float:
	return float(get_def(crop_id).get("first_maturity_seconds", 0.0))


## 再生成熟秒数；一次性作物返回 -1。
static func regrow_seconds(crop_id: String) -> float:
	return float(get_def(crop_id).get("regrow_seconds", -1.0))


static func is_regrowing(crop_id: String) -> bool:
	return bool(get_def(crop_id).get("regrow", false))


static func harvest_amount(crop_id: String) -> int:
	return int(get_def(crop_id).get("harvest_amount", 1))


## 当前生长周期需要的模拟秒数：harvest_count=0 为首次成熟，>0 为再生成熟。
## 一次性作物 harvest_count>0 不会出现（收获即清空），这里仍返回 -1 作为防御。
static func cycle_seconds(crop_id: String, harvest_count: int) -> float:
	var def := get_def(crop_id)
	if def.is_empty():
		return -1.0
	if harvest_count <= 0:
		return float(def.get("first_maturity_seconds", 0.0))
	if not bool(def.get("regrow", false)):
		return -1.0
	return float(def.get("regrow_seconds", -1.0))


## 该作物在给定季节是否允许"新种植"。
## 规则复用现有日历季节 id（不新建季节系统）：
##   - DEFS["seasons"] 包含该季节 => 可种；
##   - winter 额外允许 winter_ok 作物（kale）；
##   - allow_warm_in_winter=true 时，冬季也允许暖季作物新种（简单可调配置）。
static func plantable(crop_id: String, season_id: String, allow_warm_in_winter: bool = false) -> bool:
	var def := get_def(crop_id)
	if def.is_empty():
		return false
	var seasons: Array = def.get("seasons", [])
	if seasons.has(season_id):
		return true
	if season_id == "winter":
		if bool(def.get("winter_ok", false)):
			return true
		if allow_warm_in_winter and bool(def.get("warm_season", false)):
			return true
	return false


## 生长进度 [0, 1]。elapsed=当前周期已过模拟秒，cycle=当前周期总秒数。
static func stage_progress(crop_id: String, elapsed: float, cycle: float) -> float:
	if not has_crop(crop_id) or cycle <= 0.0:
		return 0.0
	return clampf(elapsed / cycle, 0.0, 1.0)


## 阶段索引 0..4（STAGE_IDS 下标）。进度 >=1 为 mature。
static func stage_index_at(crop_id: String, elapsed: float, cycle: float) -> int:
	var p := stage_progress(crop_id, elapsed, cycle)
	var idx := 0
	for i in range(STAGE_THRESHOLDS.size()):
		if p + 0.0000001 >= float(STAGE_THRESHOLDS[i]):
			idx = i
	return idx


## 阶段 id（"seed"/"sprout"/"growing"/"ripening"/"mature"）；无效作物返回空串。
static func stage_at(crop_id: String, elapsed: float, cycle: float) -> String:
	if not has_crop(crop_id):
		return ""
	return String(STAGE_IDS[stage_index_at(crop_id, elapsed, cycle)])


## 阶段中文标签；无效作物返回空串。
static func stage_label_at(crop_id: String, elapsed: float, cycle: float) -> String:
	if not has_crop(crop_id):
		return ""
	return String(STAGE_LABELS[stage_index_at(crop_id, elapsed, cycle)])


## 由作物定义字典判定"首次成功收获是否返还种子"（纯函数，便于配置边界测试）。
static func returns_seed_from_def(def: Dictionary) -> bool:
	return bool(def.get("returns_seed_on_first_harvest", true))


## 该作物首次成功收获是否会返还种子（每株只返还一次，由 IsleFarm 的 seed_returned 决定是否已使用）。
static func returns_seed_on_first_harvest(crop_id: String) -> bool:
	return returns_seed_from_def(get_def(crop_id))


## 由作物定义字典判定"持续再生长可收获总次数上限（含首收）"；-1 表示无限。
## regrow_cycles>0 直接用；==0 用全局默认（REGROW_INFINITE ? -1 : 1 + REGROW_CYCLES_DEFAULT）。
## 纯函数：配置边界可直接测试，不需要修改静态定义表。
static func cycle_limit_from_def(def: Dictionary) -> int:
	if def.is_empty() or not bool(def.get("regrow", false)):
		return 1
	var per := int(def.get("regrow_cycles", 0))
	if per > 0:
		return per
	if REGROW_INFINITE:
		return -1
	return 1 + REGROW_CYCLES_DEFAULT


## 持续再生长作物的可收获总次数上限（含首收）；-1 表示无限。
static func harvest_cycle_limit(crop_id: String) -> int:
	return cycle_limit_from_def(get_def(crop_id))
