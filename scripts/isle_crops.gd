class_name IsleCrops
extends RefCounted
## P9 / P1 —— 五种作物的统一静态定义（纯数据，无副作用）。
##
## 本文件只描述"作物是什么"，不持有任何状态、不读取时钟、不依赖场景/UI/NPC。
## 所有时间单位都是"农田成长时钟秒"：生产环境由 main.gd 注入**现实经过时间**
## （IsleFarm.clock_mode == "real"，由单调时钟累加，见 isle_farm.gd / main.gd:_advance_farm_clock），
## 探针可用 sim 模式注入可控测试时钟。时间跳转/时间加速/day_length 都不会改变成长时钟。
##
## P7-FINALIZE 真实时间农作（2026-10-25）：
##   参考真实成熟天数（农业推广资料见 REAL_DAYS_REF）→ 统一压缩映射
##   REAL_SECONDS_PER_CROP_DAY = 60 秒：1 个"作物日" = 1 现实分钟（压缩 1440×）。
##   取种→首次成熟：kale 52 天→52 分钟 / corn 75 天→75 分钟 / wheat 105 天→105 分钟 /
##   watermelon 101 天→101 分钟 / tomato 100 天→100 分钟。
##   该映射是**公开、可调**的设计参数，不是偷偷把成熟改回分钟级游戏模拟时间：
##   成熟时间与 _sim_seconds / day_length 无关，重启后按现实时间继续生长。
## 一次性收获：wheat / watermelon / kale（收获后清空）。
## 持续再生长：corn / tomato，每株**最多成功收获 3 次（含首收）**，第 3 次后植株结束。
## 每株作物在"首次成功收获"时返还 1 颗对应种子，之后不再返还（每株最多一次）。
##
## 种子与成品是不同物品：seed_<crop_id> 与 <crop_id>。

## 稳定作物 id（顺序即默认展示顺序，不表示优先级）。
const CROP_IDS := ["wheat", "corn", "watermelon", "tomato", "kale"]

## 生长阶段标识（视觉系统只读消费；农业权威状态是时间与采收次数，不是阶段文本）。
## P3 起正式视觉阶段收敛为三档（阶段本身不改变成熟时间/季节/采收规则）：
##   阈值是"当前生长周期的进度比例"：[0.0, 0.25) seedling 幼苗、
##   [0.25, 1.0) growing 生长中、>=1.0 mature 成熟。
## 旧五阶段（seed/sprout/growing/ripening/mature）已废弃：seed+sprout 合并为 seedling，
## growing+ripening 合并为 growing，mature 保持不变。生产代码不得再依赖旧 id。
const STAGE_IDS := ["seedling", "growing", "mature"]
const STAGE_LABELS := ["幼苗", "生长中", "成熟"]
const STAGE_THRESHOLDS := [0.0, 0.25, 1.0]

## P7-FINALIZE：每株再生作物最多成功收获 3 次（含首次收获）。第 3 次成功后植株结束、格子回到空地。
## 计数权威是 IsleFarm.slot.harvest_count（每次成功收获 +1），不是布尔 regrow 标志；
## 上限由 cycle_limit_from_def()/harvest_cycle_limit() 统一解释，DEFS 里的 regrow_cycles 优先。
const MAX_REGROW_HARVESTS := 3
## 保留旧全局开关：仅当某作物 regrow_cycles<=0 时才使用。
## P7-FINALIZE 起 corn/tomato 的 DEFS 已显式写 regrow_cycles=3，不再依赖该全局值。
const REGROW_INFINITE := false
## 旧语义兜底：关闭 REGROW_INFINITE 时，无显式 regrow_cycles 的再生作物 = 首收 + 1 次再生。
## 当前五种作物均有显式配置，该值只用于防御未来新增作物漏配。
const REGROW_CYCLES_DEFAULT := 2

## 真实时间农作的统一时间映射：1 个"作物日"对应的现实秒数。
## 推导：参考农业推广资料的真实播种→首次成熟天数（REAL_DAYS_REF）÷ 压缩系数。
## 1 现实日 = 60 秒 → 压缩 1440×；阈值 = 真实天数 × 60 秒。
## 该参数是唯一时间映射入口，调整它即可整体缩放成熟时间（不改变作物之间的相对顺序）。
const REAL_SECONDS_PER_CROP_DAY := 60.0

## 真实成熟天数参考（农业推广资料）：min/max/representative/说明/来源。
## representative 用于游戏阈值；出处见各条 note 与 docs 报告 §B。
const REAL_DAYS_REF := {
	"wheat": {
		"min": 95.0, "max": 115.0, "representative": 105.0,
		"basis": "spring wheat, direct seeded, grain maturity",
		"note": "春小麦直播至成熟通行范围 95–115 天；主源（UMN 春小麦生育期指南）本机 403，按通行农学范围取值，报告已标注待补一手引文。",
	},
	"corn": {
		"min": 60.0, "max": 90.0, "representative": 75.0,
		"basis": "sweet corn, direct seeded; USU Extension",
		"note": "USU Extension《Sweet Corn in the Garden》：maturity range 60–90 days from planting depending on variety（65/70/75/80 天熟期分级）。",
	},
	"watermelon": {
		"min": 99.0, "max": 104.0, "representative": 101.0,
		"basis": "seeded watermelon = Clemson 85–90 d from transplant + USU 移栽比直播早约 2 周",
		"note": "Clemson HGIC：85–90 days from transplant to first ripe fruit；USU：transplants mature about 2 weeks before seeded melons → 直播取 99–104 天。",
	},
	"tomato": {
		"min": 93.0, "max": 108.0, "representative": 100.0,
		"basis": "tomato from seed = Cornell 65–80 d from transplant（早/中熟）+ USU 移栽比直播早约 4 周",
		"note": "Cornell Garden Guidance：first ripe fruit 65 days or less / 65–80 / 80+ after transplanting；USU：transplants mature about 4 weeks before seeded tomatoes → 直播约 93–108 天。",
	},
	"kale": {
		"min": 50.0, "max": 55.0, "representative": 52.0,
		"basis": "kale, direct seeded; USU Extension",
		"note": "USU Extension《Kale in the Garden》：Starbor 55 days、Red Russian 50 days、Scarlet 55 days（秋季提前 50–75 天）。",
	},
}

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
		"real_days_to_first": 105.0,
		"first_maturity_seconds": 6300.0,
		"regrow_seconds": -1.0,
		"regrow": false,
		"seasons": ["spring", "autumn"],
		"winter_ok": false,
		"warm_season": false,
		"returns_seed_on_first_harvest": true,
		"regrow_cycles": 1,
	},
	"corn": {
		"display_name": "玉米",
		"seed_item_id": "seed_corn",
		"produce_item_id": "corn",
		"harvest_amount": 1,
		"real_days_to_first": 75.0,
		## 现实甜玉米一株一穗、无再生；游戏为"可重复收获"保留再生，并限制每株总收获 3 次。
		"real_days_regrow": 8.0,
		"first_maturity_seconds": 4500.0,
		"regrow_seconds": 480.0,
		"regrow": true,
		"seasons": ["spring", "summer"],
		"winter_ok": false,
		"warm_season": true,
		"returns_seed_on_first_harvest": true,
		"regrow_cycles": 3,
	},
	"watermelon": {
		"display_name": "西瓜",
		"seed_item_id": "seed_watermelon",
		"produce_item_id": "watermelon",
		"harvest_amount": 1,
		"real_days_to_first": 101.0,
		"first_maturity_seconds": 6060.0,
		"regrow_seconds": -1.0,
		"regrow": false,
		"seasons": ["summer"],
		"winter_ok": false,
		"warm_season": true,
		"returns_seed_on_first_harvest": true,
		"regrow_cycles": 1,
	},
	"tomato": {
		"display_name": "番茄",
		"seed_item_id": "seed_tomato",
		"produce_item_id": "tomato",
		"harvest_amount": 1,
		"real_days_to_first": 100.0,
		## 现实 indeterminate 番茄连续结果约 3–7 天一批；游戏取 6 个作物日，总收获上限 3 次。
		"real_days_regrow": 6.0,
		"first_maturity_seconds": 6000.0,
		"regrow_seconds": 360.0,
		"regrow": true,
		"seasons": ["spring", "summer", "autumn"],
		"winter_ok": false,
		"warm_season": true,
		"returns_seed_on_first_harvest": true,
		"regrow_cycles": 3,
	},
	"kale": {
		"display_name": "羽衣甘蓝",
		"seed_item_id": "seed_kale",
		"produce_item_id": "kale",
		"harvest_amount": 1,
		"real_days_to_first": 52.0,
		"first_maturity_seconds": 3120.0,
		"regrow_seconds": -1.0,
		"regrow": false,
		"seasons": ["spring", "autumn", "winter"],
		"winter_ok": true,
		"warm_season": false,
		"returns_seed_on_first_harvest": true,
		"regrow_cycles": 1,
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


## 其他文档/报告使用的时间映射：把"真实作物天数"换算成权威成长时钟秒。
static func real_seconds_for_days(days: float) -> float:
	return maxf(0.0, days) * REAL_SECONDS_PER_CROP_DAY


## 首次成熟所需的权威成长时钟秒（生产环境 = 现实秒）。
static func first_maturity_seconds(crop_id: String) -> float:
	return float(get_def(crop_id).get("first_maturity_seconds", 0.0))


## 该作物参考的真实"播种→首次成熟"天数（农学资料代表值；见 REAL_DAYS_REF）。
static func real_days_to_first(crop_id: String) -> float:
	return float(get_def(crop_id).get("real_days_to_first", 0.0))


## 真实的再生间隔天数（一次性作物返回 -1）。
static func real_days_regrow(crop_id: String) -> float:
	return float(get_def(crop_id).get("real_days_regrow", -1.0))


## 仅供 UI/报告：按当前映射折算的首次成熟现实分钟数（= 秒/60）。
static func first_maturity_real_minutes(crop_id: String) -> float:
	return first_maturity_seconds(crop_id) / 60.0


## 每株可成功收获的总次数上限（含首收；-1=无限）。一次性作物恒为 1。
static func max_harvests(crop_id: String) -> int:
	return harvest_cycle_limit(crop_id)


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


## 阶段索引 0..2（STAGE_IDS 下标）。进度 >=1 为 mature。
static func stage_index_at(crop_id: String, elapsed: float, cycle: float) -> int:
	var p := stage_progress(crop_id, elapsed, cycle)
	var idx := 0
	for i in range(STAGE_THRESHOLDS.size()):
		if p + 0.0000001 >= float(STAGE_THRESHOLDS[i]):
			idx = i
	return idx


## 阶段 id（"seedling"/"growing"/"mature"）；无效作物返回空串。
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
