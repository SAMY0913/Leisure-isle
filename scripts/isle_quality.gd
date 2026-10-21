class_name IsleQuality
extends RefCounted
## P6 五档画质参数表（唯一数据源）。
##
## 消费方：
##   - isle_settings.gd: quality_preset(i) -> load(...).call("preset", i)
##   - main.gd: _apply_quality(q) 读取本表，按 KEY_SPECS 的类型写入 Viewport/Environment/材质。
##   - menu.gd / hud.gd: label(i) / count() 显示档位名称。
##
## 设计约束（为什么这样分档）：
##   1. 本项目的 toon / sea / sky / glass 全是自定义 unshaded 着色器，引擎的
##      SSAO / SSR / 阴影贴图 / 实时灯光基本不作用于它们（见 docs/P6_RESEARCH_VISUAL.md）。
##      所以"高档更好看"的预算必须落在自定义管线里：
##      MSAA/SSAA、天空云层数、海浪位移波数/法线细节/泡沫/反射、草与粒子密度、
##      灯预算（toon 自算灯光上限）、glow/exposure、自定义屏幕空间 AO。
##   2. 低档不能坏观感：3D 缩放不低于 0.85，保留 FXAA，海浪仍有 3 组大波。
##   3. 高档不能过曝/噪：tonemap 五档统一 LINEAR（项目调色按 LINEAR 精调过，
##      换 ACES/AGX 会整体偏灰偏色）；高档的"电影感"来自 SSAA + AO + 曝光微调。

const QUALITY_NAMES := ["低 · 流畅", "中 · 均衡", "高 · 精致", "极高 · 细腻", "极致 · 电影"]
## 兼容旧命名（T1 菜单/测试可能读 QUALITY_LABELS）。
const QUALITY_LABELS := QUALITY_NAMES
const QUALITY_COUNT := 5

## 键的权威定义：类型 / 合法区间 / 默认（默认 = 高档，保持现有观感）。
## main.gd 只需按这里的 type 取值；越界值用 sanitize_preset() 收敛。
const KEY_SPECS := {
	"msaa_3d": {"type": "int", "min": 0, "max": 3, "def": 2},
	"msaa_2d": {"type": "int", "min": 0, "max": 3, "def": 1},
	"screen_space_aa": {"type": "int", "min": 0, "max": 1, "def": 0},
	"taa": {"type": "bool", "def": false},
	"scaling_3d_scale": {"type": "float", "min": 0.75, "max": 1.30, "def": 1.0},
	"scaling_3d_mode": {"type": "int", "min": 0, "max": 2, "def": 0},
	"max_fps": {"type": "int", "min": 0, "max": 360, "def": 0},
	"sky_cloud_detail": {"type": "int", "min": 0, "max": 3, "def": 2},
	"sea_wave_detail": {"type": "int", "min": 0, "max": 3, "def": 2},
	"sea_foam": {"type": "float", "min": 0.0, "max": 1.0, "def": 0.86},
	"sea_reflection": {"type": "float", "min": 0.0, "max": 1.4, "def": 1.0},
	"sea_ssr": {"type": "float", "min": 0.0, "max": 0.7, "def": 0.0},
	"sea_mesh_scale": {"type": "float", "min": 0.4, "max": 1.6, "def": 1.0},
	"grass_density": {"type": "float", "min": 0.3, "max": 1.6, "def": 1.0},
	"particle_density": {"type": "float", "min": 0.3, "max": 1.6, "def": 1.0},
	"light_budget": {"type": "int", "min": 4, "max": 12, "def": 8},
	"glow_strength": {"type": "float", "min": 0.0, "max": 1.5, "def": 1.0},
	"tonemap": {"type": "int", "min": 0, "max": 4, "def": 0},
	"exposure": {"type": "float", "min": 0.7, "max": 1.4, "def": 1.0},
	"posts_ao": {"type": "bool", "def": true},
	"ao_strength": {"type": "float", "min": 0.0, "max": 1.0, "def": 0.35},
	"volumetric_fog": {"type": "bool", "def": false},
	"fog_scale": {"type": "float", "min": 0.6, "max": 1.4, "def": 1.0},
	"lod_bias": {"type": "float", "min": 0.6, "max": 1.6, "def": 1.0},
}

## 五档参数。顺序 = QUALITY_NAMES 下标。全部差异都在"自定义 unshaded 管线"里真实可见。
## P7-V2：light_budget 最低档从 4 提到 7 —— 6 盏路灯固定占位、不能被画质截断，
## 低档至少保留 6 路灯 + 灯塔（夜路照明与高画质同源）；其余档位相应顺延给小屋灯。
const QUALITY_PRESETS := [
	# 0 低 · 流畅：能跑就行，但海/天/草仍有基本层次（不掉到"坏画面"）
	{
		"msaa_3d": 0, "msaa_2d": 0, "screen_space_aa": 1, "taa": false,
		"scaling_3d_scale": 0.85, "scaling_3d_mode": 1, "max_fps": 60,
		"sky_cloud_detail": 0, "sea_wave_detail": 0, "sea_foam": 0.0, "sea_reflection": 0.0,
		"sea_ssr": 0.0, "sea_mesh_scale": 0.6,
		"grass_density": 0.45, "particle_density": 0.5, "light_budget": 7,
		"glow_strength": 0.55, "tonemap": 0, "exposure": 1.0,
		"posts_ao": false, "ao_strength": 0.0, "volumetric_fog": false,
		"fog_scale": 0.85, "lod_bias": 0.8,
	},
	# 1 中 · 均衡
	{
		"msaa_3d": 1, "msaa_2d": 0, "screen_space_aa": 1, "taa": false,
		"scaling_3d_scale": 0.92, "scaling_3d_mode": 0, "max_fps": 60,
		"sky_cloud_detail": 1, "sea_wave_detail": 1, "sea_foam": 0.62, "sea_reflection": 1.0,
		"sea_ssr": 0.0, "sea_mesh_scale": 0.8,
		"grass_density": 0.7, "particle_density": 0.75, "light_budget": 8,
		"glow_strength": 0.75, "tonemap": 0, "exposure": 1.0,
		"posts_ao": false, "ao_strength": 0.0, "volumetric_fog": false,
		"fog_scale": 0.92, "lod_bias": 0.9,
	},
	# 2 高 · 精致（默认档，保持现有 P5 观感：4x MSAA + 分层云 + 5 组波）
	{
		"msaa_3d": 2, "msaa_2d": 1, "screen_space_aa": 0, "taa": false,
		"scaling_3d_scale": 1.0, "scaling_3d_mode": 0, "max_fps": 0,
		"sky_cloud_detail": 2, "sea_wave_detail": 2, "sea_foam": 0.86, "sea_reflection": 1.0,
		"sea_ssr": 0.0, "sea_mesh_scale": 1.0,
		"grass_density": 1.0, "particle_density": 1.0, "light_budget": 9,
		"glow_strength": 1.0, "tonemap": 0, "exposure": 1.0,
		"posts_ao": true, "ao_strength": 0.35, "volumetric_fog": false,
		"fog_scale": 1.0, "lod_bias": 1.0,
	},
	# 3 极高 · 细腻：8x MSAA + SSAA 1.15 + 第 3 层云 + 7 组波 + SSR + AO 加强
	{
		"msaa_3d": 3, "msaa_2d": 2, "screen_space_aa": 0, "taa": true,
		"scaling_3d_scale": 1.15, "scaling_3d_mode": 0, "max_fps": 0,
		"sky_cloud_detail": 2, "sea_wave_detail": 3, "sea_foam": 0.92, "sea_reflection": 1.15,
		"sea_ssr": 0.58, "sea_mesh_scale": 1.2,
		"grass_density": 1.2, "particle_density": 1.2, "light_budget": 11,
		"glow_strength": 1.08, "tonemap": 0, "exposure": 1.02,
		"posts_ao": true, "ao_strength": 0.55, "volumetric_fog": false,
		"fog_scale": 1.06, "lod_bias": 1.15,
	},
	# 4 极致 · 电影：8x MSAA + SSAA 1.25 + 4 层云 + 全部波 + 泡沫细节 + SSR 强 + AO 最强
	{
		"msaa_3d": 3, "msaa_2d": 2, "screen_space_aa": 0, "taa": true,
		"scaling_3d_scale": 1.25, "scaling_3d_mode": 0, "max_fps": 0,
		"sky_cloud_detail": 3, "sea_wave_detail": 3, "sea_foam": 1.0, "sea_reflection": 1.25,
		"sea_ssr": 0.62, "sea_mesh_scale": 1.4,
		"grass_density": 1.4, "particle_density": 1.35, "light_budget": 12,
		"glow_strength": 1.12, "tonemap": 0, "exposure": 1.04,
		"posts_ao": true, "ao_strength": 0.75, "volumetric_fog": false,
		"fog_scale": 1.1, "lod_bias": 1.3,
	},
]


## 五档参数（深拷贝，调用方可安全修改）。
static func preset(i: int) -> Dictionary:
	return (QUALITY_PRESETS[clampi(i, 0, QUALITY_COUNT - 1)] as Dictionary).duplicate(true)


## 档位名称。
static func label(i: int) -> String:
	return QUALITY_NAMES[clampi(i, 0, QUALITY_COUNT - 1)]


static func count() -> int:
	return QUALITY_COUNT


## 参数键（固定顺序，供 UI/探针遍历）。
static func keys() -> Array:
	return KEY_SPECS.keys()


## 默认参数（= 高 · 精致档），菜单初始化用。
static func defaults() -> Dictionary:
	return (QUALITY_PRESETS[2] as Dictionary).duplicate(true)


## 兼容入口：isle_settings.preset_defaults_for_ui() 的命名。
static func preset_defaults_for_ui() -> Dictionary:
	return defaults()


## 把任意值收敛为合法档位下标。
static func sanitize_quality(value: Variant) -> int:
	var v := int(value) if value is int or value is float else 2
	return clampi(v, 0, QUALITY_COUNT - 1)


## 按 KEY_SPECS 收敛一个参数表：缺键补默认、类型纠正、越界 clamp。
static func sanitize_preset(values: Dictionary) -> Dictionary:
	var base := defaults()
	var out: Dictionary = {}
	for key in base.keys():
		out[key] = base[key]
	for key in values.keys():
		if not base.has(key):
			continue
		var spec: Dictionary = KEY_SPECS[key]
		var raw: Variant = values[key]
		match String(spec["type"]):
			"bool":
				out[key] = bool(raw)
			"int":
				out[key] = clampi(int(raw), int(spec["min"]), int(spec["max"]))
			_:
				var f := float(raw)
				if not is_finite(f):
					f = float(base[key])
				out[key] = clampf(f, float(spec["min"]), float(spec["max"]))
	return out


## 预设 + 用户高级覆盖（高级设置面板写 quality_overrides）。
## overrides 里非法/未知的键会被丢弃，其余按 KEY_SPECS 收敛。
static func merge_overrides(preset_dict: Dictionary, overrides_dict: Dictionary) -> Dictionary:
	var merged: Dictionary = preset_dict.duplicate(true)
	for key in overrides_dict.keys():
		if merged.has(key):
			merged[key] = overrides_dict[key]
	return sanitize_preset(merged)


## 兼容入口：isle_settings.quality_effective() 也可以直接用它。
static func effective(i: int, overrides_dict: Dictionary = {}) -> Dictionary:
	return merge_overrides(preset(i), overrides_dict)


## 参数元数据（高级设置面板可直接生成滑条/勾选）。
static func param_specs() -> Array:
	var out: Array = []
	for key in KEY_SPECS.keys():
		var spec: Dictionary = KEY_SPECS[key]
		out.append({
			"key": String(key),
			"type": String(spec["type"]),
			"min": spec.get("min", 0),
			"max": spec.get("max", 1),
			"def": spec["def"],
		})
	return out


## 海面材质 uniform 映射（main._apply_quality 里直接喂 set_shader_parameter）。
static func sea_params(p: Dictionary) -> Dictionary:
	var wave_detail := float(int(p.get("sea_wave_detail", 2)))
	var foam := clampf(float(p.get("sea_foam", 0.86)), 0.0, 1.0)
	var refl := clampf(float(p.get("sea_reflection", 1.0)), 0.0, 1.4)
	var ssr := clampf(float(p.get("sea_ssr", 0.0)), 0.0, 0.7)
	# 由"最终 uniform 值"反推画质档位（0..4），用于海面细节层数。
	var lv := 0
	if foam > 0.01:
		if ssr > 0.001:
			lv = 4 if foam >= 0.97 else 3
		else:
			lv = 2 if wave_detail >= 2.0 else 1
	return {
		"wave_detail": wave_detail,
		"foam_amount": foam,
		"island_refl": refl,
		"ssr_strength": ssr,
		"sea_normal_detail": [0.45, 0.72, 1.0, 1.2, 1.35][lv],
		"sea_foam_detail": [0.0, 1.0, 1.7, 2.1, 2.4][lv],
		"sea_refl_detail": [0.0, 1.0, 1.0, 1.5, 2.0][lv],
	}


## 天空材质 uniform 映射。
static func sky_params(p: Dictionary) -> Dictionary:
	return {"cloud_detail": float(int(p.get("sky_cloud_detail", 2)))}


## Environment / Viewport 侧的完整参数（main 自己按需取用）。
## tonemap 值对应 Environment.TONE_MAPPER_*（0 linear / 2 filmic / 3 ACES / 4 AGX）。
static func render_params(p: Dictionary) -> Dictionary:
	return {
		"msaa_3d": int(p.get("msaa_3d", 2)),
		"msaa_2d": int(p.get("msaa_2d", 1)),
		"screen_space_aa": int(p.get("screen_space_aa", 0)),
		"taa": bool(p.get("taa", false)),
		"scaling_3d_scale": float(p.get("scaling_3d_scale", 1.0)),
		"scaling_3d_mode": int(p.get("scaling_3d_mode", 0)),
		"max_fps": int(p.get("max_fps", 0)),
		"grass_density": float(p.get("grass_density", 1.0)),
		"particle_density": float(p.get("particle_density", 1.0)),
		"light_budget": int(p.get("light_budget", 8)),
		"glow_strength": float(p.get("glow_strength", 1.0)),
		"tonemap": int(p.get("tonemap", 0)),
		"exposure": float(p.get("exposure", 1.0)),
		"posts_ao": bool(p.get("posts_ao", true)),
		"ao_strength": float(p.get("ao_strength", 0.35)),
		"volumetric_fog": bool(p.get("volumetric_fog", false)),
		"fog_scale": float(p.get("fog_scale", 1.0)),
		"lod_bias": float(p.get("lod_bias", 1.0)),
		"sea_mesh_scale": float(p.get("sea_mesh_scale", 1.0)),
	}


## 一行摘要（日志 / 探针用）。
static func describe(i: int) -> String:
	var p := preset(i)
	return "%s: msaa=%d scale=%.2f cloud=%d wave=%d foam=%.2f refl=%.2f ssr=%.2f ssao=%.2f grass=%.2f lights=%d" % [
		label(i), int(p["msaa_3d"]), float(p["scaling_3d_scale"]), int(p["sky_cloud_detail"]),
		int(p["sea_wave_detail"]), float(p["sea_foam"]), float(p["sea_reflection"]),
		float(p["sea_ssr"]), float(p["ao_strength"]),
		float(p["grass_density"]), int(p["light_budget"]),
	]