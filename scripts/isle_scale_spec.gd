class_name IsleScaleSpec
extends RefCounted
## P7-V3.2 全岛度量衡规范：单位、1.50 m 人体基准、建筑/家具目标尺寸与容差。
##
## 全局约定（唯一来源，其它脚本不要各自另立单位或比例）：
##   1 Godot 世界单位 = 1 米；1 米 = 100 厘米；Y 轴向上（沿用项目既有坐标约定）。
##   尺寸语义：Vector3(x = 宽 / 左右, y = 高, z = 深 / 前后)，单位米。
##   位置、速度、灯光范围、相机距离等仍使用同一坐标体系（1 单位 = 1 米）。
##
## 使用方式：
##   const SPEC := preload("res://scripts/isle_scale_spec.gd")
##   var tgt: Vector3 = SPEC.size_of("dining_table")
##   var st: Dictionary = SPEC.check("dining_table", actual_aabb.size)  # {"status":"PASS|WARN|FAIL", ...}
##
## 说明：本文件只放“跨资产共享的尺度常量与目标区间”，不把每个模型的全部程序化几何
## 参数搬进来；复杂结构在各自脚本内用局部常量构造，并由 tools/probe_scale_world.gd
## 直接测量真实网格 AABB 与这些目标比较（规范不能与真实几何脱节）。

# ---------------- 基础单位 ----------------
const UNIT_NAME := "meter"
const UNITS_PER_METER := 1.0
const CM := 0.01

# ---------------- 1.50 m 人体基准（脚底站立面 = 0） ----------------
const HUMAN_HEIGHT := 1.50          # 脚底到头发最高点的总包围高度（含发型/鞋）
const HUMAN_HEIGHT_TOL := 0.010     # 参照模型高度容差 ±1 cm
const HUMAN_HEAD_TOP_H := 1.50
const HUMAN_EYE_H := 1.38
const HUMAN_CHIN_H := 1.32
const HUMAN_SHOULDER_H := 1.24
const HUMAN_SHOULDER_W := 0.36
const HUMAN_BODY_DEPTH := 0.24
const HUMAN_HAND_H := 0.95          # 自然站立时手掌/门把手高度
const HUMAN_REACH_UP_H := 1.95      # 指尖上举可达（柜门/搁板/门梁余量）
const HUMAN_WAIST_H := 0.92
const HUMAN_HIP_H := 0.78
const HUMAN_KNEE_H := 0.42
const HUMAN_ANKLE_H := 0.06
const HUMAN_STEP_H := 0.16          # 舒适抬脚高度参考

# ---------------- 建筑尺度目标 ----------------
const DOOR_CLEAR_W := 1.14          # 门洞净宽
const DOOR_CLEAR_H := 1.94          # 门洞净高（自室内地面 fy 起算）
const DOOR_HANDLE_H := 0.95         # 门把手中心高度（自室内地面）
const ROOM_CLEAR_H := 2.42          # 一层室内净高（地板面到阁楼楼板底）
const SLAB_T := 0.20                # 阁楼楼板厚度
const ATTIC_KNEE_H := 0.56          # 阁楼可站立区边缘的膝墙（楼板面到屋面）
const STAIR_COUNT := 16
const STAIR_RISE := 0.16375         # 2.62 m 总升高 / 16 级
const STAIR_TREAD := 0.26
const STAIR_WIDTH := 0.85
const STAIR_HANDRAIL_H := 0.85
const STAIR_HEADROOM := 1.95        # 楼梯上方最小净空
const WINDOW_SILL_H := 0.90         # 一层窗台高（自室内地面）

# ---------------- 容差 ----------------
const TOL := 0.05                   # 目标尺寸 ±5% 内 PASS
const WARN_TOL := 0.10              # ±10% 内 WARN，超出 FAIL
const TOL_ABS := 0.010              # 小尺寸（<0.2 m）额外允许 ±1 cm

# ---------------- 目标尺寸登记表 ----------------
# 每项：size=目标包围盒 (x 宽, y 高, z 深)，tol=相对容差，category=类别，note=采用依据。
static var _REGISTRY: Dictionary = {
	# ---- 1.50 m 人体参照（临时，仅测量用）----
	"human_ref": {"size": Vector3(0.36, 1.50, 0.24), "tol": 0.01, "category": "human",
		"note": "岛民规定总高 1.50 m（脚底到头发最高点），临时人形仅用于比例测量"},

	# ---- 门窗 ----
	"door_opening": {"size": Vector3(1.14, 1.94, 0.30), "tol": 0.05, "category": "architecture",
		"note": "净宽 1.14 / 净高 1.94；相对 1.50 m 人物留头部余量并保留半圆拱+气窗风格"},
	"window_front": {"size": Vector3(1.00, 1.15, 0.10), "tol": 0.05, "category": "architecture",
		"note": "一层前窗；窗台 0.90，上沿约 2.05，低于檐口"},
	"window_side": {"size": Vector3(1.00, 0.95, 0.10), "tol": 0.05, "category": "architecture",
		"note": "一层侧窗；与 1.50 m 人物视线高度匹配"},
	"window_back": {"size": Vector3(0.90, 0.90, 0.10), "tol": 0.05, "category": "architecture",
		"note": "一层后窗；采光/通风用"},
	"window_attic": {"size": Vector3(1.50, 1.50, 0.10), "tol": 0.06, "category": "architecture",
		"note": "阁楼前山墙窗洞；坐在阁楼地板上可看到外部天空"},

	# ---- 家具（X=宽 Y=高 Z=深）----
	"doormat": {"size": Vector3(1.00, 0.02, 0.60), "tol": 0.08, "category": "furniture",
		"note": "门洞净宽 1.14 内可置"},
	"coat_rack": {"size": Vector3(0.80, 1.20, 0.14), "tol": 0.06, "category": "furniture",
		"note": "挂衣钩高度 1.20，低于 1.50 m 人物抬手可达"},
	"shoe_bench": {"size": Vector3(0.80, 0.42, 0.32), "tol": 0.05, "category": "furniture",
		"note": "鞋凳面 0.42，等于椅面高附近，便于坐着换鞋"},
	"dining_table": {"size": Vector3(1.30, 0.65, 0.80), "tol": 0.05, "category": "furniture",
		"note": "桌面 0.65；按 1.50/1.70 折算并保留腿部空间"},
	"chair": {"size": Vector3(0.42, 0.85, 0.44), "tol": 0.05, "category": "furniture",
		"note": "座面 0.40，靠背顶 0.85；与桌高 0.65 配套"},
	"sofa": {"size": Vector3(1.50, 0.78, 0.80), "tol": 0.05, "category": "furniture",
		"note": "坐面 0.40，靠背顶 0.78，与坐姿匹配"},
	"armchair": {"size": Vector3(0.72, 0.78, 0.76), "tol": 0.05, "category": "furniture",
		"note": "单人扶手椅；坐面 0.40 与沙发一致"},
	"coffee_table": {"size": Vector3(0.95, 0.38, 0.50), "tol": 0.05, "category": "furniture",
		"note": "茶几面 0.38，低于坐面，便于取放"},
	"rug": {"size": Vector3(2.20, 0.02, 1.60), "tol": 0.10, "category": "furniture",
		"note": "客厅地毯覆盖沙发/茶几组合"},
	"bookshelf": {"size": Vector3(0.85, 1.75, 0.30), "tol": 0.05, "category": "furniture",
		"note": "高 1.75，高于人物 0.25，最上层略低于抬手可达 1.95"},
	"sideboard": {"size": Vector3(1.00, 0.80, 0.40), "tol": 0.05, "category": "furniture",
		"note": "柜面 0.80，可作备餐台/摆放台"},
	"tall_cupboard": {"size": Vector3(0.80, 1.70, 0.40), "tol": 0.05, "category": "furniture",
		"note": "高 1.70，顶层 1.70 在抬手可达边缘以内"},
	"bed": {"size": Vector3(1.00, 0.85, 1.90), "tol": 0.05, "category": "furniture",
		"note": "床长 1.90 容 1.50 m 人体 + 头脚余量；床面(床垫顶) 0.45；宽 1.00"},
	"nightstand": {"size": Vector3(0.40, 0.50, 0.38), "tol": 0.06, "category": "furniture",
		"note": "床头柜面 0.50，略高于床面 0.45"},
	"wardrobe": {"size": Vector3(1.00, 1.75, 0.55), "tol": 0.05, "category": "furniture",
		"note": "高 1.75；挂杆与抽屉位于 0.4–1.7 可操作区间"},
	"desk": {"size": Vector3(1.20, 0.65, 0.60), "tol": 0.05, "category": "furniture",
		"note": "书桌 0.65，与椅面 0.40 配合"},
	"reading_chair": {"size": Vector3(0.70, 1.05, 0.72), "tol": 0.06, "category": "furniture",
		"note": "阅读椅带高靠背 1.05，坐面 0.40"},
	"side_table": {"size": Vector3(0.40, 0.50, 0.40), "tol": 0.06, "category": "furniture",
		"note": "边桌 0.50，与扶手椅/沙发配套"},
	"table_lamp": {"size": Vector3(0.24, 0.50, 0.24), "tol": 0.10, "category": "furniture",
		"note": "台灯总高 0.50，放在 0.50–0.80 台面上"},
	"floor_lamp": {"size": Vector3(0.36, 1.45, 0.36), "tol": 0.06, "category": "furniture",
		"note": "落地灯总高 1.45，灯罩位于视线 1.0–1.5"},
	"wall_clock": {"size": Vector3(0.40, 0.40, 0.10), "tol": 0.10, "category": "furniture",
		"note": "挂钟中心约 1.60，高于 1.50 m 人物头顶"},
	"picture_frame": {"size": Vector3(0.55, 0.42, 0.04), "tol": 0.10, "category": "furniture",
		"note": "挂画中心约 1.40，处于视线高度"},
	"curtain": {"size": Vector3(0.70, 1.35, 0.08), "tol": 0.10, "category": "furniture",
		"note": "窗帘高度与窗高 1.15 + 上下余量匹配"},
	"firewood_basket": {"size": Vector3(0.52, 0.44, 0.38), "tol": 0.08, "category": "furniture",
		"note": "柴篮高度 0.44，靠近壁炉/炉边"},
	"plant_pot": {"size": Vector3(0.42, 0.70, 0.42), "tol": 0.08, "category": "furniture",
		"note": "室内盆栽总高 0.70，放地面或矮柜"},
}

# ---------------- 查询 / 判定 ----------------
static func targets() -> Dictionary:
	return _REGISTRY

static func dimension(key: String) -> Dictionary:
	if not _REGISTRY.has(key):
		push_warning("IsleScaleSpec: 未登记尺寸目标 '%s'" % key)
		return {}
	return _REGISTRY[key]

static func size_of(key: String) -> Vector3:
	if not _REGISTRY.has(key):
		return Vector3.ZERO
	return (_REGISTRY[key] as Dictionary)["size"]

static func category_of(key: String) -> String:
	if not _REGISTRY.has(key):
		return ""
	return String((_REGISTRY[key] as Dictionary)["category"])

## 把一个实测尺寸（AABB 尺寸，米）与目标登记项比较。
## 返回 {key,target,actual,rel_err(Vector3,各轴相对误差),max_rel_err,status,note,detail}
static func check(key: String, actual: Vector3) -> Dictionary:
	var d: Dictionary = dimension(key)
	if d.is_empty():
		return {"key": key, "actual": actual, "status": "FAIL", "detail": "未登记目标尺寸"}
	var target: Vector3 = d["size"]
	var tol: float = float(d.get("tol", TOL))
	var rel := Vector3.ZERO
	for i in 3:
		var t: float = target[i]
		rel[i] = 0.0 if absf(t) < 1e-6 else absf(actual[i] - t) / t
	var max_rel: float = maxf(rel.x, maxf(rel.y, rel.z))
	var status := "PASS"
	if max_rel > WARN_TOL:
		status = "FAIL"
	elif max_rel > tol:
		status = "WARN"
	return {
		"key": key, "target": target, "actual": actual,
		"rel_err": rel, "max_rel_err": max_rel, "status": status,
		"note": String(d.get("note", "")),
		"detail": "%s 实测 %.3f×%.3f×%.3f m / 目标 %.3f×%.3f×%.3f m (误差 %.1f%%)" % [
			key, actual.x, actual.y, actual.z, target.x, target.y, target.z, max_rel * 100.0],
	}

## 单个标量高度/长度检查（如层高、门把手高度）。tol 为相对容差。
static func check_scalar(label: String, actual: float, target: float, tol: float = TOL) -> Dictionary:
	var rel: float = 0.0 if absf(target) < 1e-6 else absf(actual - target) / target
	var status := "PASS"
	if rel > WARN_TOL:
		status = "FAIL"
	elif rel > tol:
		status = "WARN"
	return {"key": label, "target": target, "actual": actual, "max_rel_err": rel, "status": status,
		"detail": "%s 实测 %.3f m / 目标 %.3f m (误差 %.1f%%)" % [label, actual, target, rel * 100.0]}

## 格式化米制尺寸文本（用于叠加层/审计输出）。
static func fmt_m(v: Vector3) -> String:
	return "%.2f×%.2f×%.2f m" % [v.x, v.y, v.z]

## 人体参考关节点高度（构建临时参照人形用）。
static func human_landmarks() -> Dictionary:
	return {
		"foot": 0.0, "ankle": HUMAN_ANKLE_H, "knee": HUMAN_KNEE_H,
		"hip": HUMAN_HIP_H, "waist": HUMAN_WAIST_H, "hand": HUMAN_HAND_H,
		"shoulder": HUMAN_SHOULDER_H, "chin": HUMAN_CHIN_H, "eye": HUMAN_EYE_H,
		"head_top": HUMAN_HEAD_TOP_H,
	}
