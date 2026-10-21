class_name IsleWeather
extends RefCounted
## P8：天气状态机（确定性调度 + 少量可积状态）。
##
## 权威时钟仍是 main.gd 的 _sim_seconds（唯一权威时间源）。本模块不持有自己的时钟，
## 只把"模拟秒数 + 固定种子"投影成天气状态：
##   - 天气槽 = 30 模拟分钟一块；每个槽起点以确定性哈希决定是否开启一个"天气轮次"，
##     轮次长 2..10 块（1..5 游戏小时），因此任意时刻可以 O(1)-O(14) 直接算出天气，
##     不需要从开服补演、也不依赖帧率。
##   - 同一 seed + 同一时刻 → 同一状态（自动天气可复跑、可固定）。
##   - 季节权重来自 IsleCalendar.parts()；雪只在深冬自动出现，台风只在夏秋；
##     跨季跳转时非法天气立即换成合法天气（不补演、不硬切）。
##   - 模拟暂停时 main 传 advancing=false，调度与过渡都冻结。

const BLOCK_SECONDS := 1800.0        # 一个天气槽 = 30 模拟分钟
const RUN_MIN_BLOCKS := 2            # 一轮天气最短 2 槽 = 1 游戏小时
const RUN_MAX_BLOCKS := 10           # 最长 10 槽 = 5 游戏小时
const TRANSITION_SECONDS := 1200.0   # 天气过渡 20 模拟分钟
const SUPER_BLOCKS := 10             # 每个"超级块"= 10 槽 = 5 游戏小时；内部再确定性切分
const SEED_DEFAULT := 20261022
const CalendarCtl := preload("res://scripts/isle_calendar.gd")

const TYPE_ORDER := [
	"clear", "partly", "overcast", "windy", "strong_wind",
	"light_rain", "mid_rain", "heavy_rain",
	"light_snow", "mid_snow", "heavy_snow", "thunder", "typhoon",
]

const TYPE_LABELS := {
	"clear": "晴", "partly": "多云", "overcast": "阴",
	"windy": "有风", "strong_wind": "强风",
	"light_rain": "小雨", "mid_rain": "中雨", "heavy_rain": "大雨",
	"light_snow": "小雪", "mid_snow": "中雪", "heavy_snow": "大雪",
	"thunder": "雷暴", "typhoon": "台风",
}

## 每种天气的基础目标参数；强度 intensity 会把云量/风力/降水在类型带内再缩放。
const TYPE_PARAMS := {
	"clear": {"cloud": 0.06, "wind": 0.18, "rain": 0.0, "snow": 0.0, "storm": 0.0},
	"partly": {"cloud": 0.38, "wind": 0.26, "rain": 0.0, "snow": 0.0, "storm": 0.0},
	"overcast": {"cloud": 0.82, "wind": 0.32, "rain": 0.0, "snow": 0.0, "storm": 0.0},
	"windy": {"cloud": 0.30, "wind": 0.62, "rain": 0.0, "snow": 0.0, "storm": 0.0},
	"strong_wind": {"cloud": 0.48, "wind": 0.88, "rain": 0.0, "snow": 0.0, "storm": 0.08},
	"light_rain": {"cloud": 0.68, "wind": 0.36, "rain": 0.30, "snow": 0.0, "storm": 0.0},
	"mid_rain": {"cloud": 0.84, "wind": 0.46, "rain": 0.62, "snow": 0.0, "storm": 0.12},
	"heavy_rain": {"cloud": 0.94, "wind": 0.58, "rain": 0.92, "snow": 0.0, "storm": 0.30},
	"light_snow": {"cloud": 0.78, "wind": 0.30, "rain": 0.0, "snow": 0.32, "storm": 0.0},
	"mid_snow": {"cloud": 0.90, "wind": 0.40, "rain": 0.0, "snow": 0.64, "storm": 0.0},
	"heavy_snow": {"cloud": 0.97, "wind": 0.50, "rain": 0.0, "snow": 0.95, "storm": 0.10},
	"thunder": {"cloud": 0.96, "wind": 0.64, "rain": 0.86, "snow": 0.0, "storm": 0.85},
	"typhoon": {"cloud": 1.0, "wind": 1.0, "rain": 0.95, "snow": 0.0, "storm": 1.0},
}

## 自动天气分季权重（艺术化概率，不求真实气候；雪在广州只是罕见，台风主要夏秋）。
const SEASON_WEIGHTS := {
	"spring": [26.0, 18.0, 16.0, 12.0, 5.0, 8.0, 5.0, 2.0, 0.0, 0.0, 0.0, 3.0, 0.0],
	"summer": [18.0, 16.0, 8.0, 7.0, 6.0, 8.0, 7.0, 4.0, 0.0, 0.0, 0.0, 9.0, 3.0],
	"autumn": [22.0, 18.0, 13.0, 11.0, 6.0, 8.0, 6.0, 2.0, 0.0, 0.0, 0.0, 4.0, 3.0],
	"winter": [18.0, 19.0, 17.0, 8.0, 6.0, 7.0, 4.0, 2.0, 1.2, 0.6, 0.2, 0.5, 0.0],
}
const SEASON_IDS := ["spring", "summer", "autumn", "winter"]

# ---- 运行期 ----
var seed := SEED_DEFAULT
var mode := "auto"              # "auto" | "manual"
var manual_type := "clear"
var _wetness := 0.0
var _snow_depth := 0.0
var _last_t := -1.0
var _manual_prev: Dictionary = {}
var _manual_target: Dictionary = {}
var _manual_blend := 1.0
var _state: Dictionary = {}

# ============================================================ 确定性哈希 ====

static func _rand01(seed_value: int, index: int, salt: int) -> float:
	var x := (seed_value ^ (index * 0x9E3779B1) ^ (salt * 0x85EBCA6B)) & 0xFFFFFFFF
	x ^= (x << 13) & 0xFFFFFFFF
	x ^= x >> 17
	x ^= (x << 5) & 0xFFFFFFFF
	x &= 0xFFFFFFFF
	return float(x & 0xFFFFFF) / 16777215.0

static func _smoothstep01(x: float) -> float:
	var v := clampf(x, 0.0, 1.0)
	return v * v * (3.0 - 2.0 * v)

static func _blend_angle(a: float, b: float, u: float) -> float:
	var d := fposmod(b - a + 540.0, 360.0) - 180.0
	return fposmod(a + d * u, 360.0)

# ============================================================ 天气轮次 ====

## 超级块内的确定性切分，长度和为 SUPER_BLOCKS；每段 2..8 槽，即每轮天气 1..4 游戏小时。
## 切分只依赖超级块索引 → 任意时刻直接算出轮次边界，轮次链天然连续、不重叠。
static func _super_split(m: int, seed_value: int) -> Array:
	var r := _rand01(seed_value, m, 301)
	if r < 0.28:
		return [10]
	if r < 0.52:
		return [5, 5]
	if r < 0.68:
		return [3, 7]
	if r < 0.82:
		return [7, 3]
	if r < 0.92:
		return [2, 8]
	if r < 0.98:
		return [4, 3, 3]
	return [2, 2, 6]

static func _run_bounds(block: int, seed_value: int) -> Dictionary:
	var m := int(floor(float(block) / float(SUPER_BLOCKS)))
	var offset := block - m * SUPER_BLOCKS
	var split := _super_split(m, seed_value)
	var cum := 0
	var idx := 0
	for i in range(split.size()):
		var ln := int(split[i])
		if offset < cum + ln:
			idx = i
			break
		cum += ln
	var start_block := m * SUPER_BLOCKS + cum
	return {"start_block": start_block, "len": int(split[idx])}

## 季节权重混合后的天气类型概率（按 TYPE_ORDER 索引）。
static func season_type_weights(season_weights: Array) -> Array:
	var total := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	for si in range(4):
		var w := float(season_weights[si]) if season_weights.size() > si else 0.0
		if w <= 0.0:
			continue
		var row: Array = SEASON_WEIGHTS[SEASON_IDS[si]]
		for ti in range(TYPE_ORDER.size()):
			total[ti] = float(total[ti]) + float(row[ti]) * w
	return total

## 天气类型在给定季节权重下是否属于"正常自动选项"。
static func type_legal(type_id: String, season_weights: Array) -> bool:
	var winter_w := float(season_weights[3]) if season_weights.size() > 3 else 0.0
	var warm_w := 0.0
	if season_weights.size() >= 3:
		warm_w = float(season_weights[1]) + float(season_weights[2])
	if type_id == "light_snow" or type_id == "mid_snow" or type_id == "heavy_snow":
		return winter_w >= 0.60
	if type_id == "typhoon":
		return warm_w >= 0.60
	return true

static func _legal_fallback(type_id: String, season_weights: Array) -> String:
	if type_id == "light_snow" or type_id == "mid_snow" or type_id == "heavy_snow":
		return "light_rain" if type_id == "light_snow" else "mid_rain"
	if type_id == "typhoon":
		var warm := 0.0
		if season_weights.size() >= 3:
			warm = float(season_weights[1]) + float(season_weights[2])
		return "thunder" if warm > 0.30 else "strong_wind"
	return type_id

static func _pick_type(season_weights: Array, r: float) -> String:
	var weights := season_type_weights(season_weights)
	var total := 0.0
	for v in weights:
		total += float(v)
	if total <= 0.0001:
		return "clear"
	var target := r * total
	var acc := 0.0
	for i in range(TYPE_ORDER.size()):
		acc += float(weights[i])
		if target <= acc:
			return String(TYPE_ORDER[i])
	return "partly"

static func _run_weather(start_block: int, seed_value: int) -> Dictionary:
	var local_seconds := float(start_block) * BLOCK_SECONDS
	var cal := CalendarCtl.parts(local_seconds)
	var season_weights: Array = cal.get("season_weights", [0.25, 0.25, 0.25, 0.25])
	var type_id := _pick_type(season_weights, _rand01(seed_value, start_block, 201))
	if not type_legal(type_id, season_weights):
		type_id = _legal_fallback(type_id, season_weights)
	var params: Dictionary = TYPE_PARAMS[type_id]
	var out := {
		"type": type_id,
		"label": String(TYPE_LABELS[type_id]),
		"intensity": 0.25 + 0.65 * _rand01(seed_value, start_block, 202),
		"wind_dir": fposmod(90.0 + 160.0 * _rand01(seed_value, start_block, 203), 360.0),
		"start_block": start_block,
		"local_seconds": local_seconds,
		"season_weights": season_weights.duplicate(),
	}
	for key in params.keys():
		out[key] = float(params[key])
	return out

## 把一轮天气按强度缩放成目标参数（云量/风/雨/雪/风暴）。
static func _scaled_run(run: Dictionary) -> Dictionary:
	var intensity := float(run.get("intensity", 0.5))
	var k := 0.72 + 0.56 * intensity
	return {
		"type": String(run["type"]),
		"label": String(run["label"]),
		"intensity": intensity,
		"cloud": clampf(float(run["cloud"]) * k, 0.0, 1.0),
		"wind": clampf(float(run["wind"]) * k, 0.0, 1.0),
		"rain": clampf(float(run["rain"]) * k, 0.0, 1.0),
		"snow": clampf(float(run["snow"]) * k, 0.0, 1.0),
		"storm": clampf(float(run["storm"]) * k, 0.0, 1.0),
		"wind_dir": float(run["wind_dir"]),
	}

## 纯函数：模拟秒数 → 天气调度状态（不考虑已积水的湿润度/积雪深度）。
static func schedule_at(local_seconds: float, seed_value: int) -> Dictionary:
	var t := maxf(local_seconds, 0.0)
	var block := int(floor(t / BLOCK_SECONDS))
	var run := _run_bounds(block, seed_value)
	var cur := _run_weather(int(run["start_block"]), seed_value)
	var run_len := int(run["len"])
	var run_start_t := float(run["start_block"]) * BLOCK_SECONDS
	var run_end_t := run_start_t + float(run_len) * BLOCK_SECONDS
	var next_block := int(run["start_block"]) + run_len
	var next_run := _run_bounds(next_block, seed_value)
	var nxt := _run_weather(int(next_run["start_block"]), seed_value)
	var cal := CalendarCtl.parts(t)
	var season_weights: Array = cal.get("season_weights", [0.25, 0.25, 0.25, 0.25])
	# 跨季跳转：当前/下一轮天气可能已不合法（例如从冬天跳到夏天仍在下雪）→ 立即换合法天气。
	if not type_legal(String(cur["type"]), season_weights):
		_fix_run_type(cur, _legal_fallback(String(cur["type"]), season_weights))
	if not type_legal(String(nxt["type"]), season_weights):
		_fix_run_type(nxt, _legal_fallback(String(nxt["type"]), season_weights))
	var a := _scaled_run(cur)
	var b := _scaled_run(nxt)
	var trans_start := run_end_t - TRANSITION_SECONDS
	var u := 0.0
	if t > trans_start:
		u = _smoothstep01((t - trans_start) / TRANSITION_SECONDS)
	var blended := {
		"cloud": lerpf(float(a["cloud"]), float(b["cloud"]), u),
		"wind": lerpf(float(a["wind"]), float(b["wind"]), u),
		"rain": lerpf(float(a["rain"]), float(b["rain"]), u),
		"snow": lerpf(float(a["snow"]), float(b["snow"]), u),
		"storm": lerpf(float(a["storm"]), float(b["storm"]), u),
		"intensity": lerpf(float(a["intensity"]), float(b["intensity"]), u),
		"wind_dir": _blend_angle(float(a["wind_dir"]), float(b["wind_dir"]), u),
	}
	# 主显示类型：过渡过半后显示下一轮。
	var main_type := String(a["type"])
	var main_label := String(a["label"])
	if u >= 0.5:
		main_type = String(b["type"])
		main_label = String(b["label"])
	var precip_type := "none"
	var precip := 0.0
	if float(blended["snow"]) > 0.02 and float(blended["snow"]) >= float(blended["rain"]):
		precip_type = "snow"
		precip = float(blended["snow"])
	elif float(blended["rain"]) > 0.02:
		precip_type = "rain"
		precip = float(blended["rain"])
	return {
		"type": main_type,
		"label": main_label,
		"next_type": String(b["type"]),
		"next_label": String(b["label"]),
		"intensity": float(blended["intensity"]),
		"transition": u,
		"cloud": float(blended["cloud"]),
		"wind_strength": float(blended["wind"]),
		"wind_dir": float(blended["wind_dir"]),
		"storm": float(blended["storm"]),
		"precip_type": precip_type,
		"precip_intensity": precip,
		"run_start": run_start_t,
		"run_end": run_end_t,
		"hold_left": maxf(run_end_t - t, 0.0),
		"hold_total": float(run_len) * BLOCK_SECONDS,
		"season_weights": season_weights.duplicate(),
		"cal": cal,
		"seed": seed_value,
	}

static func _fix_run_type(run: Dictionary, type_id: String) -> void:
	run["type"] = type_id
	run["label"] = String(TYPE_LABELS[type_id])
	var params: Dictionary = TYPE_PARAMS[type_id]
	for key in params.keys():
		run[key] = float(params[key])

## 手动天气的目标参数（强度取类型中值；与自动共用同一套参数带）。
static func manual_params(type_id: String) -> Dictionary:
	var params: Dictionary = TYPE_PARAMS.get(type_id, TYPE_PARAMS["clear"])
	return {
		"type": type_id,
		"label": String(TYPE_LABELS.get(type_id, "晴")),
		"intensity": 0.65,
		"cloud": float(params["cloud"]),
		"wind": float(params["wind"]),
		"rain": float(params["rain"]),
		"snow": float(params["snow"]),
		"storm": float(params["storm"]),
		"wind_dir": 135.0,
	}

## 当前季节下可手动选择的天气（雪仅冬季、台风仅夏秋；其余全年可选）。
static func manual_types(season_weights: Array) -> Array:
	var out: Array = []
	for tid in TYPE_ORDER:
		if not type_legal(String(tid), season_weights):
			continue
		out.append(String(tid))
	return out

static func season_weights_of(local_seconds: float) -> Array:
	var cal := CalendarCtl.parts(local_seconds)
	return cal.get("season_weights", [0.25, 0.25, 0.25, 0.25])

# ============================================================ 实例状态 ====

func configure(seed_value: int, mode_value: String = "auto", manual: String = "clear") -> void:
	seed = seed_value
	mode = mode_value if mode_value in ["auto", "manual"] else "auto"
	manual_type = manual if TYPE_PARAMS.has(manual) else "clear"
	_last_t = -1.0
	_manual_prev = {}
	_manual_target = manual_params(manual_type)
	_manual_blend = 1.0
	_state = {}

func set_mode(value: String) -> void:
	if value == mode:
		return
	if value == "manual":
		_manual_prev = _snapshot_current()
		_manual_target = manual_params(manual_type)
		_manual_blend = 0.0
	mode = value

func set_manual_type(type_id: String) -> void:
	if not TYPE_PARAMS.has(type_id):
		return
	if type_id == manual_type and mode == "manual":
		return
	_manual_prev = _snapshot_current()
	_manual_target = manual_params(type_id)
	_manual_blend = 0.0
	manual_type = type_id
	mode = "manual"

static func _snapshot_fields(src: Dictionary) -> Dictionary:
	var rain := 0.0
	var snow := 0.0
	var ptype := String(src.get("precip_type", "none"))
	if ptype == "rain":
		rain = float(src.get("precip_intensity", 0.0))
	elif ptype == "snow":
		snow = float(src.get("precip_intensity", 0.0))
	return {
		"cloud": float(src.get("cloud", 0.1)),
		"wind": float(src.get("wind_strength", 0.2)),
		"rain": rain,
		"snow": snow,
		"storm": float(src.get("storm", 0.0)),
		"wind_dir": float(src.get("wind_dir", 135.0)),
		"intensity": float(src.get("intensity", 0.5)),
		"type": String(src.get("type", "clear")),
		"label": String(src.get("label", "晴")),
	}

func _snapshot_current() -> Dictionary:
	if _state.is_empty():
		var mp := manual_params(manual_type)
		return {
			"cloud": float(mp["cloud"]), "wind": float(mp["wind"]),
			"rain": float(mp["rain"]), "snow": float(mp["snow"]),
			"storm": float(mp["storm"]), "wind_dir": float(mp["wind_dir"]),
			"intensity": float(mp["intensity"]), "type": String(mp["type"]), "label": String(mp["label"]),
		}
	return _snapshot_fields(_state)

## 用当前权威时间重建状态（跳日期/改变模式/首次启动时调用；不补演历史）。
func reset(local_seconds: float) -> void:
	_last_t = local_seconds
	_manual_prev = {}
	_manual_blend = 1.0
	_state = {}
	var season_weights := season_weights_of(local_seconds)
	var winter_w := float(season_weights[3]) if season_weights.size() > 3 else 0.0
	# 先构建一次状态（sd=0，不推进任何过渡/累积）。
	_refresh(local_seconds, 0.0, true)
	# 跳转后立即进入合法稳态：按当前天气直接给出湿润/积雪估计，不补演过去。
	var rain := 0.0
	var snow := 0.0
	if String(_state.get("precip_type", "none")) == "rain":
		rain = float(_state.get("precip_intensity", 0.0))
	elif String(_state.get("precip_type", "none")) == "snow":
		snow = float(_state.get("precip_intensity", 0.0))
	_wetness = clampf(rain * 0.75, 0.0, 1.0)
	_snow_depth = clampf(snow * 0.55 * winter_w, 0.0, 1.0)
	_state["wetness"] = _wetness
	_state["snow_depth"] = _snow_depth
	_state["snow_trend"] = 1.0 if snow > 0.02 else (-1.0 if _snow_depth > 0.01 else 0.0)

## advancing=false 时（暂停/菜单）冻结调度与过渡；手动切换在暂停时立即到位。
func tick(local_seconds: float, sim_delta: float, advancing: bool) -> void:
	if _last_t < 0.0 or absf(local_seconds - _last_t) > 120.0:
		reset(local_seconds)
		return
	_last_t = local_seconds
	var sd := maxf(sim_delta, 0.0) if advancing else 0.0
	_refresh(local_seconds, sd, advancing)

func _refresh(local_seconds: float, sd: float, _advancing: bool) -> void:
	var season_weights := season_weights_of(local_seconds)
	var winter_w := float(season_weights[3]) if season_weights.size() > 3 else 0.0
	if mode == "manual":
		# 季节切换 / 跨季跳转后，手动选中的类型若在新季节不合法，按同一套规则回退
		# （雪 → 雨、台风 → 雷暴/强风），绝不让"夏季下雪"这类状态残留。
		if not type_legal(manual_type, season_weights):
			manual_type = _legal_fallback(manual_type, season_weights)
			_manual_target = manual_params(manual_type)
		if _manual_blend < 1.0:
			_manual_blend = clampf(_manual_blend + sd / TRANSITION_SECONDS, 0.0, 1.0) if sd > 0.0 else 1.0
		if _manual_blend >= 1.0:
			_manual_prev = {}
		var tgt := _manual_target
		var from: Dictionary = _manual_prev if not _manual_prev.is_empty() else tgt
		var u := _smoothstep01(_manual_blend)
		var cloud := lerpf(float(from.get("cloud", 0.1)), float(tgt["cloud"]), u)
		var wind := lerpf(float(from.get("wind", 0.2)), float(tgt["wind"]), u)
		var rain := lerpf(float(from.get("rain", 0.0)), float(tgt["rain"]), u)
		var snow := lerpf(float(from.get("snow", 0.0)), float(tgt["snow"]), u)
		var storm := lerpf(float(from.get("storm", 0.0)), float(tgt["storm"]), u)
		var ptype := "none"
		var precip := 0.0
		if snow > 0.02 and snow >= rain:
			ptype = "snow"
			precip = snow
		elif rain > 0.02:
			ptype = "rain"
			precip = rain
		_state = {
			"type": String(tgt["type"]),
			"label": String(tgt["label"]),
			"next_type": String(tgt["type"]),
			"next_label": String(tgt["label"]),
			"intensity": lerpf(float(from.get("intensity", 0.6)), float(tgt["intensity"]), u),
			"transition": 0.0 if _manual_blend >= 1.0 else _manual_blend,
			"cloud": cloud,
			"wind_strength": wind,
			"wind_dir": _blend_angle(float(from.get("wind_dir", 135.0)), float(tgt["wind_dir"]), u),
			"storm": storm,
			"precip_type": ptype,
			"precip_intensity": precip,
			"run_start": local_seconds,
			"run_end": local_seconds,
			"hold_left": 0.0,
			"hold_total": 0.0,
			"season_weights": season_weights.duplicate(),
			"cal": CalendarCtl.parts(local_seconds),
			"seed": seed,
		}
	else:
		_state = schedule_at(local_seconds, seed)
	# 湿润度：下雨时快速趋近雨强×0.9，雨停后缓慢变干（时间常数按模拟秒）。
	var rain := 0.0
	var snow := 0.0
	if String(_state.get("precip_type", "none")) == "rain":
		rain = float(_state.get("precip_intensity", 0.0))
	elif String(_state.get("precip_type", "none")) == "snow":
		snow = float(_state.get("precip_intensity", 0.0))
	if sd > 0.0:
		var wet_target := clampf(rain * 0.90, 0.0, 1.0)
		var k_wet := clampf(sd / 420.0, 0.0, 1.0) if wet_target > _wetness else clampf(sd / 5400.0, 0.0, 1.0)
		_wetness = clampf(lerpf(_wetness, wet_target, k_wet), 0.0, 1.0)
		var snow_target := clampf(snow * 0.65 * winter_w, 0.0, 1.0)
		var k_snow := clampf(sd / 9000.0, 0.0, 1.0) if snow_target > _snow_depth else clampf(sd / 14000.0, 0.0, 1.0)
		_snow_depth = clampf(lerpf(_snow_depth, snow_target, k_snow), 0.0, 1.0)
	_state["wetness"] = _wetness
	_state["snow_depth"] = _snow_depth
	_state["snow_trend"] = 1.0 if snow > 0.02 else (-1.0 if _snow_depth > 0.01 else 0.0)
	_state["mode"] = mode
	_state["auto"] = mode == "auto"
	_state["manual_type"] = manual_type
	_state["available_types"] = manual_types(season_weights)
	_state["season"] = int(_state.get("cal", {}).get("season", 0))
	_state["season_label"] = String(_state.get("cal", {}).get("season_label", "春季"))
	_state["season_t"] = float(_state.get("cal", {}).get("season_t", 0.0))
	_state["seed"] = seed

func state() -> Dictionary:
	if _state.is_empty():
		reset(0.0)
	return _state.duplicate(true)

## 风向角 → 世界方向向量（az=0 北 = -Z，90 东 = +X）。
func wind_dir_vector() -> Vector3:
	var r := deg_to_rad(float(_state.get("wind_dir", 135.0)))
	return Vector3(sin(r), 0.0, -cos(r))
