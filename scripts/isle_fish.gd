class_name IsleFish
extends RefCounted
## P6 / A —— 近岸鱼类静态目录（纯数据 + 纯函数，无场景/时钟/库存依赖）。
##
## 本文件只回答三件事："有哪些鱼"、"在什么条件下出现"、"权重多少"。
## 钓鱼流程（钓鱼装配件 / main / HUD / 背包）只读消费这里的判定，本文件不写库存、不建节点。
##
## 条件维度与权威来源：
##   season_id   —— isle_calendar.gd 的季节 id：spring / summer / autumn / winter。
##   hour        —— 0..23 的整点（含两端）；hour_from > hour_to 表示跨午夜（例如 18..6）。
##   weather_key —— 四档粗粒度天气：clear / cloudy / rain / snow。
##                 由 weather_key() 从 isle_weather.gd 的权威状态投影：
##                 降水以 precip_type（"rain"/"snow"）为准；无降水时按云量阈值分 clear/cloudy。
##   seasons / weather 字段为空数组 = 不限（全年 / 全天候）。
##
## 平衡：权重只是第一版可调参数（不是最终经济平衡）。目录里恒有一条兜底鱼（鲫鱼），
## 在任何季节/时段/天气都可用，保证 pick() 在任意合法条件下权重和 > 0、永远返回合法 id。
##
## 决定论：pick() 只使用调用方注入的 RandomNumberGenerator，本文件不创建 rng、
## 不消费全局随机数；同一 seed + 同一条件序列可完整复跑。

## 规范鱼类 id（顺序即默认图鉴/背包展示顺序，fish_ 前缀便于库存分类）。
const FISH_IDS: Array[String] = [
	"fish_crucian",  # 鲫鱼（全年全天候兜底）
	"fish_sardine",  # 沙丁鱼
	"fish_seabass",  # 鲈鱼
	"fish_puffer",   # 河豚
	"fish_salmon",   # 鲑鱼
	"fish_koi",      # 彩鲤
]

## 兜底鱼：DEFS 中必须保证它全年/全天候/全天气可用（探针逐组合校验）。
const FALLBACK_ID := "fish_crucian"

## 合法季节 id（与 isle_calendar.gd 一致；本文件只做数据校验，不推导季节）。
const SEASON_IDS := ["spring", "summer", "autumn", "winter"]

## 天气粗档（weather_key() 的输出域；与 isle_weather.gd 的细档 type 是投影关系）。
const WEATHER_KEYS := ["clear", "cloudy", "rain", "snow"]

## 云量阈值：无降水时 cloud >= 0.45 记为 cloudy，否则 clear。
## isle_weather.gd 的典型云量：clear≈0.06 / partly≈0.35 / overcast≈0.8，
## 因此 clear→clear、overcast→cloudy；partly（多云）按云量落在两侧，不单独占一档。
const CLOUDY_THRESHOLD := 0.45

## 鱼类定义。字段说明：
##   display_name  中文显示名
##   rarity        稀有度：common / uncommon / rare
##   color         鱼获 3D 网格使用的十六进制颜色 "#rrggbb"
##   weight        基础刷新权重（float，> 0；第一版可调）
##   seasons       允许季节 id 数组（[] = 不限）
##   hour_from     允许时段起点（0..23，含）
##   hour_to       允许时段终点（0..23，含；< hour_from 表示跨午夜）
##   weather       允许天气粗档数组（[] = 不限；键只能是 clear/cloudy/rain/snow）
##   min_size      最小体长（米）
##   max_size      最大体长（米，>= min_size）
const DEFS := {
	"fish_crucian": {
		"display_name": "鲫鱼",
		"rarity": "common",
		"color": "#8a8f63",
		"weight": 100.0,
		"seasons": [],
		"hour_from": 0,
		"hour_to": 23,
		"weather": [],
		"min_size": 0.12,
		"max_size": 0.38,
	},
	"fish_sardine": {
		"display_name": "沙丁鱼",
		"rarity": "common",
		"color": "#a9c3d6",
		"weight": 70.0,
		"seasons": [],
		"hour_from": 6,
		"hour_to": 18,
		"weather": [],
		"min_size": 0.08,
		"max_size": 0.22,
	},
	"fish_seabass": {
		"display_name": "鲈鱼",
		"rarity": "uncommon",
		"color": "#7f98a6",
		"weight": 30.0,
		"seasons": [],
		"hour_from": 17,
		"hour_to": 21,
		"weather": [],
		"min_size": 0.30,
		"max_size": 0.85,
	},
	"fish_puffer": {
		"display_name": "河豚",
		"rarity": "uncommon",
		"color": "#d8b466",
		"weight": 20.0,
		"seasons": ["summer", "autumn"],
		"hour_from": 9,
		"hour_to": 17,
		"weather": ["clear", "cloudy"],
		"min_size": 0.20,
		"max_size": 0.55,
	},
	"fish_salmon": {
		"display_name": "鲑鱼",
		"rarity": "rare",
		"color": "#e08a6c",
		"weight": 8.0,
		"seasons": ["autumn"],
		"hour_from": 5,
		"hour_to": 9,
		"weather": [],
		"min_size": 0.45,
		"max_size": 1.10,
	},
	"fish_koi": {
		"display_name": "彩鲤",
		"rarity": "rare",
		"color": "#e2543f",
		"weight": 5.0,
		"seasons": ["spring", "summer"],
		"hour_from": 6,
		"hour_to": 10,
		"weather": ["clear"],
		"min_size": 0.30,
		"max_size": 0.75,
	},
}


# ============================================================ 查询 =========
## 全部鱼类 id（复制，按 FISH_IDS 顺序）。
static func all_ids() -> Array:
	return FISH_IDS.duplicate()


## 是否为本目录登记的鱼类。
static func has_fish(fish_id: String) -> bool:
	return DEFS.has(fish_id)


## 返回鱼类定义深拷贝（无效 id 返回空字典）。调用方可自由读取，不可依赖引用相等。
static func get_def(fish_id: String) -> Dictionary:
	if not DEFS.has(fish_id):
		return {}
	return (DEFS[fish_id] as Dictionary).duplicate(true)


## 中文显示名；无效 id 原样返回 id（与 isle_crops.display_name 的兜底风格一致）。
static func display_name(fish_id: String) -> String:
	return String(get_def(fish_id).get("display_name", fish_id))


## 稀有度（common / uncommon / rare）；无效 id 返回空串。
static func rarity(fish_id: String) -> String:
	return String(get_def(fish_id).get("rarity", ""))


## 兜底鱼 id（任意季节/时段/天气可钓；保证 pick() 权重和恒 > 0）。
static func fallback_id() -> String:
	return FALLBACK_ID


# ============================================================ 天气投影 =====
## 把权威天气状态投影成四档粗粒度天气键（clear / cloudy / rain / snow）。
## 规则：
##   1) precip_type 为 "rain" / "snow" 时直接采用（isle_weather.schedule_at 的值）；
##   2) 调用方若直接把粗档 "rain" / "snow" 传给 weather_type，也直接采用（兼容简化调用）；
##   3) 其余情况按云量：cloud >= CLOUDY_THRESHOLD => cloudy，否则 clear。
## 本函数是纯函数：不读 isle_weather 实例，调用方传入当前状态的三个字段即可。
static func weather_key(weather_type: String, precip_type: String, cloud: float) -> String:
	var precip := String(precip_type)
	if precip != "rain" and precip != "snow" and (weather_type == "rain" or weather_type == "snow"):
		precip = weather_type
	if precip == "rain" or precip == "snow":
		return precip
	if float(cloud) >= CLOUDY_THRESHOLD:
		return "cloudy"
	return "clear"


# ============================================================ 可用性 =======
## 时段判定：from <= to 为闭区间；from > to 表示跨午夜（如 18..6 => 18..23 或 0..6）。
static func _hour_matches(hour: int, hour_from: int, hour_to: int) -> bool:
	if hour_from <= hour_to:
		return hour >= hour_from and hour <= hour_to
	return hour >= hour_from or hour <= hour_to


## 该鱼在给定季节/整点/天气下是否可钓。
## 季节、天气字段为空数组表示不限；未知 id 一律 false。
static func is_available(fish_id: String, season_id: String, hour: int, weather_key_id: String) -> bool:
	if not DEFS.has(fish_id):
		return false
	var def: Dictionary = DEFS[fish_id]
	var seasons: Array = def.get("seasons", [])
	if not seasons.is_empty() and not seasons.has(season_id):
		return false
	var weather: Array = def.get("weather", [])
	if not weather.is_empty() and not weather.has(weather_key_id):
		return false
	return _hour_matches(hour, int(def.get("hour_from", 0)), int(def.get("hour_to", 23)))


## 该鱼在给定条件下的刷新权重；不可用时严格返回 0.0（供 pick/UI 预览共用）。
static func weight_for(fish_id: String, season_id: String, hour: int, weather_key_id: String) -> float:
	if not is_available(fish_id, season_id, hour, weather_key_id):
		return 0.0
	return maxf(float(DEFS[fish_id].get("weight", 0.0)), 0.0)


## 按权重随机选一条鱼：只使用注入的 rng（可复跑），永远返回合法 id。
## 任意合法条件组合下都有兜底鱼参与，权重和 > 0；rng 为 null / 异常时退回兜底鱼。
static func pick(season_id: String, hour: int, weather_key_id: String, rng: RandomNumberGenerator) -> String:
	if rng == null:
		return fallback_id()
	var total := 0.0
	for fish_id in FISH_IDS:
		total += weight_for(String(fish_id), season_id, hour, weather_key_id)
	if total <= 0.0:
		return fallback_id()
	var target := rng.randf() * total
	for fish_id in FISH_IDS:
		var w := weight_for(String(fish_id), season_id, hour, weather_key_id)
		if w <= 0.0:
			continue
		target -= w
		if target <= 0.0:
			return String(fish_id)
	# 浮点累加理论上不会走到这里；保底返回兜底鱼，绝不返回非法 id。
	return fallback_id()
