class_name IsleSettings
extends RefCounted
## Persisted user preferences (user://settings.cfg).
## Single source of truth for the menu values, quality preset, audio groups,
## window mode / resolution and the ten "minutes per game day" time presets.
##
## Phase 6 layout:
##   quality         0..4  five presets (参数由 isle_quality.gd 提供)
##   quality_overrides     advanced-parameter overrides -> "自定义" 档
##   day_length      60..3600  十档：每游戏日对应的现实秒数
##   volume_master / volume_ambient / volume_birds / volume_fire / volume_sfx
##   window_mode     windowed | fullscreen | borderless
##   resolution      Vector2i 窗口/渲染尺寸
##   time_source     sim | real
##   timezone        IANA id
##   fov             35..65 (垂直视野角度，默认 42°；P7-V3)

const PATH := "user://settings.cfg"

## 五档画质名称（isle_quality.gd 的参数与之一一对应）。
const QUALITY_COUNT := 5
const QUALITY_LABELS := [
	"低 · 流畅",
	"中 · 均衡",
	"高 · 精致",
	"极高 · 细腻",
	"极致 · 电影",
]
## 极致档的参数来源（由 T3 提供；缺失时回落到仅档位号，保证脚本可独立加载）。
const QUALITY_SCRIPT := "res://scripts/isle_quality.gd"

## 十档每日时间流速：一个游戏日（24 模拟小时 = 1440 模拟分钟）消耗的现实秒数。
const DAY_LENGTH_PRESETS := [60.0, 300.0, 600.0, 900.0, 1200.0, 1500.0, 1800.0, 2400.0, 2700.0, 3600.0]
const DAY_LENGTH_DEFAULT := 600.0
## 界面说明：这里的"每游戏日"指游戏内 00:00 走到次日 00:00 所需的现实时间。
const DAY_LENGTH_HINT := "每游戏日 = 游戏内 00:00 → 次日 00:00 的现实耗时"

## 时区校验依赖 isle_tz_data 的 IANA 表（isle_time 只做纯函数换算，不反向依赖本文件）。
const IsleTime := preload("res://scripts/isle_time.gd")

## 可选窗口分辨率（按当前显示器可用区域过滤；宽度 >= 640 才收录）。
const RESOLUTIONS := [
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1440, 900),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3440, 1440),
	Vector2i(3840, 2160),
]
const RESOLUTION_DEFAULT := Vector2i(1440, 900)

## 窗口模式：windowed（窗口化）/ fullscreen（独占全屏）/ borderless（无边框窗口）。
const WINDOW_MODES := ["windowed", "fullscreen", "borderless"]

## 时间来源：sim = 游戏内模拟时间（默认），real = 跟随系统现实时间。
const TIME_SOURCES := ["sim", "real"]
const DEFAULT_TIME_SOURCE := "sim"
const DEFAULT_TIMEZONE := "Asia/Shanghai"

## 视野范围（FOV，垂直视角，单位度）：默认 42°；可在 35–65° 之间按 1° 步进调整。
## P7-V3：与鼠标灵敏度无关，只改 Camera3D.fov（轨道视角与自由视角共用）。
const FOV_DEFAULT := 42.0
const FOV_MIN := 35.0
const FOV_MAX := 65.0

## P8 天气：自动天气种子（同一 seed + 同一模拟时刻 = 同一天气，可复跑）、
## 自动/手动模式与手动天气类型。天气面板会实时改这三项，因此一并持久化。
const WEATHER_SEED_DEFAULT := 20261022
const WEATHER_DEFAULT_TYPE := "clear"
## P8.1：12 类（windy 已合并进 strong_wind 并删除）。
const WEATHER_TYPES := [
	"clear", "partly", "overcast", "strong_wind",
	"light_rain", "mid_rain", "heavy_rain",
	"light_snow", "mid_snow", "heavy_snow", "thunder", "typhoon",
]
## P8.1：历史类型别名（旧存档/旧配置迁移用，幂等）。windy 是 P8 的"普通有风"，
## 合并后语义归属唯一具名大风状态 strong_wind。
const WEATHER_TYPE_ALIASES := {"windy": "strong_wind"}

## 音频分组：每组一条 AudioBus，界面滑块只改总线音量。
const AUDIO_GROUPS := [
	{"key": "volume_master", "bus": "Master", "label": "主音量", "hint": "全部游戏声音的最终音量"},
	{"key": "volume_ambient", "bus": "IsleAmbient", "label": "环境音", "hint": "海浪、风声与夜间环境循环"},
	{"key": "volume_birds", "bus": "IsleBirds", "label": "鸟鸣", "hint": "海鸥与其他鸟类的叫声"},
	{"key": "volume_fire", "bus": "IsleFire", "label": "火焰", "hint": "壁炉与篝火音效"},
	{"key": "volume_sfx", "bus": "IsleSFX", "label": "音效", "hint": "交互、船只、水花与按钮"},
]

const DEFAULTS := {
	"day_length": 600.0,
	"sensitivity": 1.0,
	"fov": FOV_DEFAULT,
	"auto_orbit": true,
	"quality": 2,
	"quality_overrides": {},
	"window_mode": "windowed",
	"fullscreen": false,
	"resolution": RESOLUTION_DEFAULT,
	"time_source": DEFAULT_TIME_SOURCE,
	"timezone": DEFAULT_TIMEZONE,
	"weather_seed": WEATHER_SEED_DEFAULT,
	"weather_auto": true,
	"weather_type": WEATHER_DEFAULT_TYPE,
	"volume_master": 0.8,
	"volume_ambient": 0.7,
	"volume_birds": 0.8,
	"volume_fire": 0.7,
	"volume_sfx": 0.8,
}

const VOLUME_KEYS := ["volume_master", "volume_ambient", "volume_birds", "volume_fire", "volume_sfx"]


static func defaults() -> Dictionary:
	return DEFAULTS.duplicate(true)

## 当前显示器可用区域（headless 下返回 0，调用方据此走兜底逻辑）。
static func _screen_usable_size() -> Vector2i:
	if DisplayServer.get_name() == "headless":
		return Vector2i.ZERO
	var r: Rect2i = DisplayServer.screen_get_usable_rect()
	if r.size.x < 640 or r.size.y < 360:
		return Vector2i.ZERO
	return r.size

## 依据当前显示器筛选出可用分辨率列表（附带"满屏"当前桌面尺寸）。
static func resolution_presets() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var scr := _screen_usable_size()
	for r in RESOLUTIONS:
		if scr == Vector2i.ZERO or (r.x <= scr.x and r.y <= scr.y):
			out.append(r)
	if scr != Vector2i.ZERO and not out.has(scr):
		out.append(scr)
	if out.is_empty():
		out.append(Vector2i(1280, 720))
	return out

## 默认分辨率：优先 1440x900，其次 1280x720，最后列表首项。
static func default_resolution() -> Vector2i:
	var presets := resolution_presets()
	if presets.has(RESOLUTION_DEFAULT):
		return RESOLUTION_DEFAULT
	if presets.has(Vector2i(1280, 720)):
		return Vector2i(1280, 720)
	return presets[0]

static func resolution_label(v: Vector2i) -> String:
	var scr := _screen_usable_size()
	var suffix := ""
	if scr != Vector2i.ZERO and v == scr:
		suffix = " · 满屏"
	return "%d × %d%s" % [v.x, v.y, suffix]

## 找到当前分辨率在预设列表中的索引（找不到则回落到默认项）。
static func resolution_index(presets: Array, current: Vector2i) -> int:
	for i in presets.size():
		if presets[i] == current:
			return i
	var def := default_resolution()
	for i in presets.size():
		if presets[i] == def:
			return i
	return 0

## 过滤异常/越界的历史配置值。
static func sanitize_resolution(value: Variant) -> Vector2i:
	var v := Vector2i.ZERO
	if value is Vector2i:
		v = value
	elif value is Vector2:
		v = Vector2i(int(value.x), int(value.y))
	else:
		return default_resolution()
	v.x = clampi(v.x, 640, 3840)
	v.y = clampi(v.y, 360, 2160)
	return v

static func sanitize_window_mode(value: Variant, legacy_fullscreen: Variant = false) -> String:
	var text := str(value).strip_edges()
	if WINDOW_MODES.has(text):
		return text
	if bool(legacy_fullscreen):
		return "fullscreen"
	return "windowed"


## 时间来源校验：只认 "sim" / "real"，其余（含旧版本缺失值）回落默认模拟时间。
static func sanitize_time_source(value: Variant) -> String:
	var text := str(value).strip_edges()
	if TIME_SOURCES.has(text):
		return text
	return DEFAULT_TIME_SOURCE


## 时区校验：必须是 isle_tz_data 表内的 IANA id，非法值回落 Asia/Shanghai。
static func sanitize_timezone(value: Variant) -> String:
	var text := str(value).strip_edges()
	if text.is_empty():
		return DEFAULT_TIMEZONE
	return IsleTime.resolve_zone(text)


## 每日时间流速：仅接受十档预设值，其他值取最近档（旧版 480 秒会迁移到 600 秒档）。
static func sanitize_day_length(value: Variant) -> float:
	var v := float(value)
	if not is_finite(v) or v <= 0.0:
		return DAY_LENGTH_DEFAULT
	var best: float = DAY_LENGTH_PRESETS[0]
	var best_d := absf(v - best)
	for p in DAY_LENGTH_PRESETS:
		var d := absf(v - float(p))
		if d < best_d:
			best_d = d
			best = float(p)
	return best


## 找到档位索引（找不到返回默认档索引）。
static func day_length_index(value: float) -> int:
	var v := sanitize_day_length(value)
	for i in DAY_LENGTH_PRESETS.size():
		if absf(DAY_LENGTH_PRESETS[i] - v) < 0.5:
			return i
	return DAY_LENGTH_PRESETS.size() - 1


## 界面文案：例如 "10 分钟 / 游戏日"。
static func day_length_label(value: float) -> String:
	var sec := sanitize_day_length(value)
	var minutes := int(round(sec / 60.0))
	return "%d 分钟 / 游戏日" % minutes


## 一个游戏日对应的现实秒数（= day_length，直接供 main.gd 的统一时钟使用）。
static func day_length_seconds(value: float) -> float:
	return sanitize_day_length(value)


## FOV 校验：clamp 到 35–65 度、取整到 1°；缺失/非法值回落默认 42°（旧配置迁移用）。
static func sanitize_fov(value: Variant) -> float:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return FOV_DEFAULT
	var v := float(value)
	if not is_finite(v):
		return FOV_DEFAULT
	return roundf(clampf(v, FOV_MIN, FOV_MAX))


## P8 天气种子：正整数；非法/越界回落默认（保证同一配置可复跑）。
static func sanitize_weather_seed(value: Variant) -> int:
	var v := int(value)
	if v <= 0 or v > 2147483647:
		return WEATHER_SEED_DEFAULT
	return v


static func sanitize_weather_auto(value: Variant) -> bool:
	return bool(value)


## 手动天气类型：只认 12 种已知 id（雪/台风是否可选由面板按季节过滤）。
## 先把历史别名迁移成新 id（windy → strong_wind），**再**做合法性校验；
## 顺序不能反，否则旧存档里的 "windy" 会被当成非法值回退成 "clear"。
static func sanitize_weather_type(value: Variant) -> String:
	var text := str(value).strip_edges()
	if WEATHER_TYPE_ALIASES.has(text):
		text = String(WEATHER_TYPE_ALIASES[text])
	if WEATHER_TYPES.has(text):
		return text
	return WEATHER_DEFAULT_TYPE


static func sanitize_volume(value: Variant) -> float:
	var v := float(value)
	if not is_finite(v):
		return 0.8
	return clampf(v, 0.0, 1.0)


static func sanitize_quality(value: Variant) -> int:
	return clampi(int(value), 0, QUALITY_COUNT - 1)


## 五档画质参数（由 isle_quality.gd 提供）。脚本尚不存在时返回最小字典。
static func _quality_script() -> Variant:
	if not ResourceLoader.exists(QUALITY_SCRIPT):
		return null
	return load(QUALITY_SCRIPT)


## 返回指定档位的完整参数表（不含用户覆盖）。
static func quality_preset(quality_index: int) -> Dictionary:
	var q := sanitize_quality(quality_index)
	var script: Variant = _quality_script()
	if script != null:
		# 脚本可能正在编辑/解析失败：先确认存在 preset 再 call，避免运行期报错。
		var names: Array = []
		for m in (script as Script).get_script_method_list():
			names.append(String(m.get("name", "")))
		if names.has("preset"):
			var merged: Variant = (script as Script).call("preset", q)
			if merged is Dictionary:
				return (merged as Dictionary).duplicate(true)
	return {"quality": q}


## 合并用户高级参数覆盖后的生效参数表。
static func quality_effective(quality_index: int, overrides: Dictionary = {}) -> Dictionary:
	var out := quality_preset(quality_index)
	for key in overrides.keys():
		out[key] = overrides[key]
	return out


## 是否处于"自定义"画质（存在覆盖时界面显示自定义而不再冒充某个预设）。
static func quality_custom(values: Dictionary) -> bool:
	var overrides: Variant = values.get("quality_overrides", {})
	return overrides is Dictionary and not (overrides as Dictionary).is_empty()


## 画质界面文案：自定义时显示 "自定义"，否则显示五档名称。
static func quality_summary(values: Dictionary) -> String:
	if quality_custom(values):
		return "自定义"
	return quality_label(int(values.get("quality", DEFAULTS["quality"])))


static func quality_label(quality: int) -> String:
	return QUALITY_LABELS[clampi(quality, 0, QUALITY_LABELS.size() - 1)]


## 音频分组表（深拷贝，避免调用方改动常量）。
static func audio_groups() -> Array:
	return AUDIO_GROUPS.duplicate(true)


static func audio_default(key: String) -> float:
	return float(DEFAULTS.get(key, 0.8))


static func load_settings(path: String = PATH) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate(true)
	var cfg := ConfigFile.new()
	var loaded: int = cfg.load(path)
	if loaded != OK:
		out["resolution"] = default_resolution()
		return out
	# 旧版单音量 -> 主音量迁移。
	var legacy_volume: Variant = null
	if cfg.has_section_key("settings", "volume"):
		legacy_volume = cfg.get_value("settings", "volume")
	for key in DEFAULTS.keys():
		var value: Variant = cfg.get_value("settings", key, DEFAULTS[key])
		match key:
			"day_length":
				out[key] = sanitize_day_length(value)
			"sensitivity":
				out[key] = clampf(float(value), 0.2, 3.0)
			"fov":
				out[key] = sanitize_fov(value)
			"quality":
				out[key] = sanitize_quality(value)
			"quality_overrides":
				out[key] = (value as Dictionary).duplicate(true) if value is Dictionary else {}
			"auto_orbit", "fullscreen":
				out[key] = bool(value)
			"window_mode":
				if cfg.has_section_key("settings", "window_mode"):
					out[key] = sanitize_window_mode(value, false)
				else:
					out[key] = sanitize_window_mode("", cfg.get_value("settings", "fullscreen", false))
			"resolution":
				out[key] = sanitize_resolution(value)
			"time_source":
				out[key] = sanitize_time_source(value)
			"timezone":
				out[key] = sanitize_timezone(value)
			"weather_seed":
				out[key] = sanitize_weather_seed(value)
			"weather_auto":
				out[key] = sanitize_weather_auto(value)
			"weather_type":
				out[key] = sanitize_weather_type(value)
			_:
				if VOLUME_KEYS.has(key):
					out[key] = sanitize_volume(value)
	if legacy_volume != null and not cfg.has_section_key("settings", "volume_master"):
		out["volume_master"] = sanitize_volume(legacy_volume)
	# 兼容派生字段：旧菜单仍读 fullscreen。
	out["fullscreen"] = (out["window_mode"] as String) == "fullscreen"
	out["resolution"] = sanitize_resolution(out["resolution"])
	return out


static func save_settings(values: Dictionary, path: String = PATH) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)
	var snapshot: Dictionary = values.duplicate(true)
	snapshot["resolution"] = sanitize_resolution(snapshot.get("resolution", RESOLUTION_DEFAULT))
	snapshot["window_mode"] = sanitize_window_mode(snapshot.get("window_mode", "windowed"), snapshot.get("fullscreen", false))
	snapshot["fullscreen"] = (snapshot["window_mode"] as String) == "fullscreen"
	snapshot["time_source"] = sanitize_time_source(snapshot.get("time_source", DEFAULT_TIME_SOURCE))
	snapshot["timezone"] = sanitize_timezone(snapshot.get("timezone", DEFAULT_TIMEZONE))
	snapshot["day_length"] = sanitize_day_length(snapshot.get("day_length", DAY_LENGTH_DEFAULT))
	snapshot["fov"] = sanitize_fov(snapshot.get("fov", FOV_DEFAULT))
	snapshot["quality"] = sanitize_quality(snapshot.get("quality", DEFAULTS["quality"]))
	snapshot["weather_seed"] = sanitize_weather_seed(snapshot.get("weather_seed", WEATHER_SEED_DEFAULT))
	snapshot["weather_auto"] = sanitize_weather_auto(snapshot.get("weather_auto", true))
	snapshot["weather_type"] = sanitize_weather_type(snapshot.get("weather_type", WEATHER_DEFAULT_TYPE))
	var overrides: Variant = snapshot.get("quality_overrides", {})
	snapshot["quality_overrides"] = (overrides as Dictionary).duplicate(true) if overrides is Dictionary else {}
	for key in VOLUME_KEYS:
		snapshot[key] = sanitize_volume(snapshot.get(key, DEFAULTS[key]))
	# 旧版单音量字段写出去便于旧版本回退读取，同时不再是读取源。
	snapshot["volume"] = snapshot["volume_master"]
	for key in DEFAULTS.keys():
		cfg.set_value("settings", key, snapshot.get(key, DEFAULTS[key]))
	# DEFAULTS 不含旧版 volume 键，需显式写出镜像值（P5 及更早版本回退读取用）。
	cfg.set_value("settings", "volume", snapshot["volume"])
	var err: int = cfg.save(path)
	if err != OK:
		push_warning("[settings] failed to save %s (error %d)" % [path, err])
