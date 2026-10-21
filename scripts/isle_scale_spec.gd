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
	"human_ref": {"size": Vector3(0.47, 1.50, 0.24), "tol": 0.01, "category": "human",
		"note": "岛民规定总高 1.50 m（脚底到头发最高点）；AABB 宽 0.47（手臂自然下垂）/深 0.24；由 scripts/isle_scale_figure.gd 生成并用 tools/probe_scale_world.gd 实测"},


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

# ================= P7-V3.2 Task A 增补：资产/环境/相机目标与实测登记 =================
# 说明：本节目标是“验收目标”，几何来源仍在各自脚本（IsleMath / IsleHouseProps / IsleWorld /
# IsleCottage / main.gd）。改几何后必须同步本表，并用 tools/probe_scale_world.gd 实测登记。

# ---- 房屋结构验收目标（来源 lead_scale_plan_v1.md；局部坐标 y=0 为 cottage 原点，地面 fy=0.55）----
const HOUSE_W := 7.60               # 外墙外皮宽
const HOUSE_D := 6.20               # 外墙外皮深
const HOUSE_WALL_H := 3.18          # 外墙高（fy → roof_base）
const HOUSE_ROOF_H := 2.47          # roof_base → ridge（坡高）
const HOUSE_RIDGE_Y := 6.20         # 屋脊标高（局部，自 cottage 原点）
const HOUSE_FY := 0.55              # 一层室内地面标高（局部）
const HOUSE_WALL_T := 0.30          # 外墙厚
const HOUSE_EAVE_OV := 0.60         # 檐口挑出（沿坡向）
const HOUSE_PITCH_DEG := 33.0       # 屋顶坡度
const HOUSE_ATTIC_FLOOR_Y := 3.17   # 阁楼楼板顶标高
const HOUSE_ATTIC_KNEE_H := 0.56    # 阁楼膝墙
const HOUSE_CHIMNEY_ABOVE_RIDGE := 0.35
const PORCH_DECK_Y := 0.42          # 门廊台面
const PORCH_STEP_RISE := 0.14       # 门廊台阶踏高
const PORCH_STEP_RUN := 0.30        # 门廊台阶踏面深
const ATTIC_WINDOW_BOTTOM_ABOVE_FLOOR := 0.10

# ---- 标量目标区间：min ≤ 实测 ≤ max 为 PASS；超出区间 ≤10% 为 WARN；再外为 FAIL ----
static var _RANGES: Dictionary = {
	"porch_deck_y": {"min": 0.42, "max": 0.44, "unit": "m", "category": "architecture",
		"note": "门廊台面高：1.50 m 人物上一步 0.42–0.44 舒适", "measured_by": "PorchSteps meta top_y + 台面顶点实测"},
	"stair_landing": {"min": 0.80, "max": 1.00, "unit": "m", "category": "architecture",
		"note": "L 形楼梯平台边长 0.85–0.95；两侧转身余量", "measured_by": "Staircase batch_manifest 平台板"},
	"cat_shoulder_h": {"min": 0.25, "max": 0.35, "unit": "m", "category": "creature",
		"note": "家猫肩高真实值 0.23–0.35 m（参考 1.50 m 人物约 1/5 身高）", "measured_by": "PorchCat 躯干段 AABB 高"},
	"cat_body_len": {"min": 0.40, "max": 0.60, "unit": "m", "category": "creature",
		"note": "家猫体长（不含尾）0.40–0.60 m", "measured_by": "PorchCat 头部到臀部 AABB 深"},
	"gull_body_len": {"min": 0.40, "max": 0.70, "unit": "m", "category": "creature",
		"note": "海鸥 body-only 体长 0.40–0.70：实测 0.671，T4 判保留（远景可读性 + 绘本夸张），不缩",
		"measured_by": "fx Bird0 躯干+头+喙+尾网格合并 AABB 深（不含翼/腿）；翼展单列 gull_wingspan"},
	"gull_wingspan": {"min": 1.10, "max": 1.50, "unit": "m", "category": "creature",
		"note": "海鸥翼展 1.10–1.50 m", "measured_by": "海鸥节点 AABB 宽"},
	"boat_hull_len": {"min": 3.00, "max": 6.00, "unit": "m", "category": "asset",
		"note": "小船是载 2–4 人的小帆船/划艇：3–6 m；实测后决定保留夸张或按真实区间微调", "measured_by": "Sailboat 船体 Gunwale/Hull 部件 AABB 长"},
	"boat_hull_beam": {"min": 1.20, "max": 2.00, "unit": "m", "category": "asset",
		"note": "船长/船宽比 2.5–3.2 的小船；干舷 0.25–0.60", "measured_by": "Sailboat 船体 AABB 宽"},
	"boat_freeboard": {"min": 0.25, "max": 0.70, "unit": "m", "category": "asset",
		"note": "干舷（水面到舷缘）0.25–0.70（T4 实测舷缘顶 0.660；5 m 小帆船合理偏高，保留船体不缩）",
		"measured_by": "两种量法并列：①世界量法=舷缘 Gunwale 顶世界 Y − 海面世界 Y(0)；②局部设计水线=船节点局部舷缘顶 Y（船局部 y=0 为设计水线）。probe_scale_world 同时输出 boat_freeboard_world / boat_freeboard_local"},
	"street_lamp_h": {"min": 2.70, "max": 3.05, "unit": "m", "category": "asset",
		"note": "地面→灯帽顶/杆顶总高 2.70–3.05（T4 实测帽顶 2.75、灯中心 2.55；旧 2.8–3.8 作废）",
		"measured_by": "路灯节点子树 AABB 高（基座底面→灯帽/杆顶，实测世界高度）"},
	"street_lamp_center": {"min": 2.45, "max": 2.65, "unit": "m", "category": "asset",
		"note": "灯具/光心离地高 2.45–2.65（T4 已按灯中心 2.55 执行）；决定夜间光斑位置与人物抬头视角",
		"measured_by": "world._lamp 返回的 lantern 世界坐标 Y − 灯基座世界 Y；并与灯箱网格 AABB 中心互校"},
	"lighthouse_steps_count": {"min": 6.9, "max": 7.1, "unit": "step", "category": "asset",
		"note": "灯塔入口环绕石阶 7 级（T4 已修：每级内半径 = 该高度基座半径 + 0.02、径向外露 0.38、台地 0.16 → 门槛 1.20）",
		"measured_by": "Lighthouse 下 DoorStep0..6 节点数量"},
	"lighthouse_step_rise": {"min": 0.15, "max": 0.17, "unit": "m", "category": "asset",
		"note": "灯塔石阶踏高 0.16 m（7 级 × 0.16 = 1.12，再加 0.08 到门槛 1.20）",
		"measured_by": "DoorStep 节点顶面局部 y 升序相邻差中位数"},
	"lighthouse_step_depth": {"min": 0.34, "max": 0.42, "unit": "m", "category": "asset",
		"note": "灯塔石阶径向踏面深 0.38 m（BoxMesh 局部 z 向）",
		"measured_by": "DoorStep 各节点 BoxMesh.size.z 中位数"},
	"lighthouse_step_top": {"min": 1.10, "max": 1.14, "unit": "m", "category": "asset",
		"note": "最高一级石阶顶 1.12 m（门槛顶 1.20，gap 0.08；1.50 m 访客一步跨上）",
		"measured_by": "DoorStep0 顶面局部 y（相对 Lighthouse 节点原点）"},
	"camera_orbit_r": {"min": 70.0, "max": 95.0, "unit": "m", "category": "camera",
		"note": "初始轨道相机距离 82 m：保证直径约 63.6 m 的岛全部入画", "measured_by": "main._build_camera IsleFlyCam radius / CAM_START_R"},
	"camera_fly_radius": {"min": 110.0, "max": 150.0, "unit": "m", "category": "camera",
		"note": "自由视角可移动半径 130 m：不飞出远景岛群", "measured_by": "IsleFlyCam.radius"},
	"camera_fov": {"min": 45.0, "max": 75.0, "unit": "deg", "category": "camera",
		"note": "≥45° 保证小岛全景，≤75° 控制透视变形", "measured_by": "Camera3D.fov"},
	"camera_near": {"min": 0.10, "max": 0.50, "unit": "m", "category": "camera",
		"note": "near 0.3：1 m 级近景不穿模、远处海面仍稳定", "measured_by": "Camera3D.near"},
	"island_diameter": {"min": 55.0, "max": 75.0, "unit": "m", "category": "environment",
		"note": "岛屿直径约 63.6 m；保留现状（reference_keep），仅审计", "measured_by": "Terrain AABB / coast_radius"},
}

# ---- reference_keep：明确“保留现有夸张/既定比例”的对象与理由（不做等比缩放的依据）----
static var _REFERENCE_KEEP: Dictionary = {
	"lighthouse": {"hint": 18.28, "unit": "m", "node": "Island/Lighthouse",
		"reason": "灯塔是岛屿地标与夜间导航视觉焦点：18.28 m 保证 60 m 外仍可读，灯室/平台/perch/光束已按此高度设计，缩小后与远岛群比例失衡",
		"keep_conditions": "保留总高 18.28±0.20；只允许局部可读性修整（灯室/平台/梯段），不整体缩放"},
	"island_terrain": {"hint": 63.6, "unit": "m", "node": "Island/Terrain",
		"reason": "岛屿直径≈63.6 m、地形由 coast_radius/terrain_height 程序化生成；重定比例会破坏房屋/花园/秋千/码头/小路既有摆位与远景海平线",
		"keep_conditions": "保留地形与岸线；仅审计地形起伏是否压得过 1.5 m 人物尺度（如台阶/坡道可读性）"},
	"sea_surface": {"hint": 0.0, "unit": "m", "node": "Island/Sea",
		"reason": "海面高度 y=0 是干舷、码头台面（0.72 m）、船体吃水的共同基准；改变会使三者同时失准",
		"keep_conditions": "海面 y=0 固定；船只/码头据此审计"},
	"big_tree": {"hint": 12.0, "unit": "m", "node": "Island/BigTree",
		"reason": "大树是主要取景框与秋千挂点（SWING_LIMB_Y 5.55）；按真实树高重算会牵动秋千绳长/摆幅、相机取景与树冠遮蔽",
		"keep_conditions": "保留树高与秋千挂点；秋千座面/绳长按 1.5 m 人物舒适度审计"},
	"day_night_cycle": {"hint": 0.0, "unit": "-", "node": "main/日月球",
		"reason": "日月球与光照按现有世界比例调过，不属于尺度对象；本轮只做相机/灯光距离审计",
		"keep_conditions": "不重定比例"},
	"windmill_old": {"hint": 12.19, "unit": "m", "node": "（已替换）",
		"reason": "旧风车 12.1839 m 已由灯塔替换，仅作为历史记录保留在 IsleWorld 返回值中，不重建",
		"keep_conditions": "仅记录，不再生成"},
	"boat_behavior": {"hint": 0.0, "unit": "-", "node": "Island/Sailboat",
		"reason": "小船航线/回港/夜景状态机与码头/航道摆位绑定；尺度调整只允许改船体几何，状态机与路径保留",
		"keep_conditions": "保留 boat 状态机/航线/回港路径；只改船体比例"},
}

# ---- 实测登记表：key -> 探针如何得到这个数（防止“只读登记表不看真实几何”）----
static var _MEASURE: Dictionary = {
	"human_ref": {"probe": "figure.build+measure", "path": "scripts/isle_scale_figure.gd", "method": "构建参照人形后取重建世界 AABB（父级缩放会暴露）"},
	"door_opening": {"probe": "house.door", "path": "Island/Cottage", "method": "前墙平面射线-三角形扫描：无命中列高/行宽"},
	"window_front": {"probe": "house.windows", "path": "Cottage/WindowFront*", "method": "窗玻璃真实 Mesh AABB + 0.02 玻璃缝隙"},
	"window_side": {"probe": "house.windows", "path": "Cottage/WindowLeft/Right", "method": "同上"},
	"window_back": {"probe": "house.windows", "path": "Cottage/WindowBack", "method": "同上"},
	"window_attic": {"probe": "house.attic_window", "path": "Cottage/AtticWindow", "method": "阁楼窗玻璃 Mesh AABB"},
}
# 家具统一实测方式
const FURNITURE_MEASURE := "tools/probe_scale_world.gd：IsleHouseProps.build(kind) 后逐 MeshInstance 真实 AABB（排除 Glow/Halo/Blob），再与目标比较"

# ---- 区间 / 保留 / 登记 查询 ----
static func ranges() -> Dictionary:
	return _RANGES

static func range_of(key: String) -> Dictionary:
	return _RANGES.get(key, {})

static func reference_keeps() -> Dictionary:
	return _REFERENCE_KEEP

static func is_reference_keep(key: String) -> bool:
	return _REFERENCE_KEEP.has(key)

static func keep_entry(key: String) -> Dictionary:
	return _REFERENCE_KEEP.get(key, {})

static func measurement_of(key: String) -> Dictionary:
	if _MEASURE.has(key):
		return _MEASURE[key]
	var cat := category_of(key)
	if cat == "furniture":
		return {"probe": "furniture.build+measure", "path": "scripts/isle_house_props.gd", "method": FURNITURE_MEASURE}
	return {}

## 区间检查：min ≤ actual ≤ max 为 PASS；超出 ≤10% 区间宽度为 WARN；再外为 FAIL。
static func check_range(key: String, actual: float) -> Dictionary:
	var r: Dictionary = range_of(key)
	if r.is_empty():
		return {"key": key, "actual": actual, "status": "FAIL", "detail": "未登记目标区间"}
	var lo: float = float(r["min"])
	var hi: float = float(r["max"])
	var span: float = maxf(hi - lo, 1e-6)
	var status := "PASS"
	var margin: float = 0.0
	if actual < lo:
		margin = lo - actual
		status = "WARN" if margin <= span * 0.10 else "FAIL"
	elif actual > hi:
		margin = actual - hi
		status = "WARN" if margin <= span * 0.10 else "FAIL"
	var rel: float = 0.0
	var mid: float = (lo + hi) * 0.5
	if absf(mid) > 1e-6:
		rel = absf(actual - mid) / mid
	return {"key": key, "actual": actual, "min": lo, "max": hi, "max_rel_err": rel,
		"status": status, "note": String(r.get("note", "")),
		"detail": "%s 实测 %.3f %s / 区间 [%.3f, %.3f] %s → %s" % [
			key, actual, String(r.get("unit", "")), lo, hi, "PASS" if status == "PASS" else ("WARN" if status == "WARN" else "FAIL"), status]}

## 与任意显式目标比较（非登记表项，例如结构标量）。
static func check_custom(label: String, actual: Vector3, target: Vector3, tol: float = TOL) -> Dictionary:
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
	return {"key": label, "target": target, "actual": actual, "rel_err": rel,
		"max_rel_err": max_rel, "status": status,
		"detail": "%s 实测 %.3f×%.3f×%.3f m / 目标 %.3f×%.3f×%.3f m (误差 %.1f%%)" % [
			label, actual.x, actual.y, actual.z, target.x, target.y, target.z, max_rel * 100.0]}

## 状态排序：PASS=0 WARN=1 FAIL=2（汇总统计用）。
static func status_rank(s: String) -> int:
	if s == "PASS":
		return 0
	if s == "WARN":
		return 1
	return 2
