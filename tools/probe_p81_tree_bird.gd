extends SceneTree
## P8.1 task-2 验收探针（headless，不加载 isle.tscn、不开窗口）：
##   D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe --headless --path D:/休闲小岛幻境/游戏工程 --script res://tools/probe_p81_tree_bird.gd
## 覆盖：
##   [COUNTS]  world 旧 22 栖点 + 冬季裸枝 5 = 27；+ cottage 14 = 41；旧 id/kind 不变；_build_perches 默认 false 契约保留
##   [GEOM]    5 个裸枝锚点贴真实 CylinderMesh 枝面（距离<=0.03）、法线垂直枝轴、normal.y>=0.35、slope 与法线一致、
##             world y = surface_y(树根) + local.y、避开秋千绳、两两间距>=1.5m
##   [SEASON]  冬季 canopy_keep<=0.001 / leafcard<=0.05；main.gd 无 _winter_plum/WinterPlum 死代码；
##             WinterBloom 茎/头两个 5 实例 MultiMesh、同名同 Transform、初始不可见、节点名不以 Flower 开头
##   [FLOWERS] 5 朵屋前红花：_grass_spot 合法、在门廊排除区外、离路缘>=0.6、离门 3.5-6.0m、间距>=0.6、贴合地表
##   [FXGATE]  41 点 setup 后，冬季 ctx 240 帧 / 夏季 ctx 120 帧：teleports 增量==0、冬季裸枝点开/冠面点关、
##             夏季反向、无鸟持有 winter_branch、预约表 used==perched+landing、conflicts==0、无残留预约
## 退出码：0 = 全部通过；1 = 有失败。

const World := preload("res://scripts/world.gd")
const Cottage := preload("res://scripts/cottage.gd")
const Season := preload("res://scripts/isle_season.gd")
const Fx := preload("res://scripts/fx.gd")
const IM := preload("res://scripts/isle_math.gd")

const DT := 1.0 / 60.0
const BIG_TREE_X := -10.9
const BIG_TREE_Z := 4.2
const SWING_PIVOT_LOCAL := Vector3(3.0, 5.55, 0.0)
const STATE_LANDING := 2
const STATE_PERCH := 3

var _pass := 0
var _fail := 0
var _fails: Array = []
var _world_holder: Node3D = null
var _cottage_holder: Node3D = null
var _island: Dictionary = {}
var _cottage: Dictionary = {}
var _world_root: Node3D = null
var _big: Node3D = null
var _base: Vector3 = Vector3.ZERO
var _winter_perches: Array = []

func _initialize() -> void:
	print("=== P8.1 TREE/BIRD PROBE START ===")
	await process_frame
	_world_holder = Node3D.new()
	_world_holder.name = "P81ProbeWorld"
	get_root().add_child(_world_holder)
	# 与本任务游戏内路径一致：显式开启冬季裸枝栖点（41 点契约）。
	_island = World.build(_world_holder, true)
	_cottage_holder = Node3D.new()
	_cottage_holder.name = "P81ProbeCottage"
	get_root().add_child(_cottage_holder)
	_cottage = Cottage.build(_cottage_holder)
	await process_frame
	_world_root = _island["root"] as Node3D
	_big = _world_root.find_child("BigTree", true, false) as Node3D
	_base = _island["big_tree"] as Vector3
	_probe_counts()
	_probe_geometry()
	_probe_season_params()
	_probe_winter_bloom()
	_probe_source_cleanup()
	await _probe_fx_gating()
	_world_holder.free()
	_cottage_holder.free()
	print("=== P8.1 TREE/BIRD PROBE RESULT: ", "PASS" if _fail == 0 else "FAIL", " pass=", _pass, " fail=", _fail, " ===")
	for m in _fails:
		print("[FAILED] ", m)
	quit(0 if _fail == 0 else 1)

func _check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("  [OK] ", msg)
	else:
		_fail += 1
		_fails.append(msg)
		print("  [FAIL] ", msg)

func _fmtv(v: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [v.x, v.y, v.z]

func _perch_by_id(perches: Array, pid: String) -> Dictionary:
	for p_v in perches:
		var p: Dictionary = p_v
		if String(p.get("id", "")) == pid:
			return p
	return {}

func _kind_of(perches: Array, pid: String) -> String:
	var p: Dictionary = _perch_by_id(perches, pid)
	return String(p.get("kind", ""))

# ============================================================
# [COUNTS] 契约：旧 22 点不变，新增 5 个冬季裸枝点
# ============================================================
func _probe_counts() -> void:
	var wperches: Array = (_island.get("perches", []) as Array)
	var cperches: Array = (_cottage.get("perches", []) as Array)
	var all: Array = wperches + cperches
	print("[COUNTS] world=", wperches.size(), " cottage=", cperches.size(), " total=", all.size())
	_check(cperches.size() == 14, "cottage 栖点仍 14")
	_check(wperches.size() == 26, "world 栖点 26（旧 16 + 灯塔/码头/花园 5 灯（P7.1 删一盏）+ 冬季 5）实际=" + str(wperches.size()))
	_check(all.size() == 40, "合并栖点 40（14 cottage + 26 world）")
	_winter_perches = []
	for p_v in wperches:
		var p: Dictionary = p_v
		if String(p.get("kind", "")) == "winter_branch":
			_winter_perches.append(p)
	_check(_winter_perches.size() == 5, "冬季裸枝栖点 5 个")
	var ids: Array = []
	for p_v in _winter_perches:
		var p: Dictionary = p_v
		ids.append(String(p["id"]))
		_check(int(p.get("slots", 0)) == 1, "裸枝 slots=1: " + String(p["id"]))
		_check(absf(float(p.get("radius", 0.0)) - 0.55) < 0.001, "裸枝 radius=0.55: " + String(p["id"]))
	for i in range(5):
		_check(ids.has("winter_branch_%d" % i), "id winter_branch_%d 存在" % i)
	# 旧点 kind 不变（P7 36 点契约的 world 部分 22 点）。
	_check(_kind_of(wperches, "tree_0") == "tree_branch", "tree_0 仍 tree_branch")
	_check(_kind_of(wperches, "lighthouse_0") == "lighthouse_platform", "lighthouse_0 仍 lighthouse_platform")
	_check(_kind_of(wperches, "dock_rail") == "dock", "dock_rail 不变")
	_check(_kind_of(wperches, "garden_post_0") == "garden_post", "garden_post_0 不变")
	_check(_kind_of(wperches, "lamp_0") == "lamp", "lamp_0 不变")
	var src := _read_res("res://scripts/world.gd")
	_check(src.find("include_winter: bool = false") >= 0, "world._build_perches 默认 include_winter=false（旧调用点 36 点契约）")

# ============================================================
# [GEOM] 锚点必须贴真实枝干圆柱面
# ============================================================
func _collect_cylinders(node: Node, out: Array) -> void:
	for c in node.get_children():
		if c is MeshInstance3D:
			var mi: MeshInstance3D = c
			if mi.mesh is CylinderMesh:
				out.append(mi)
		_collect_cylinders(c, out)

func _nearest_branch_surface(sp: Vector3, nrm: Vector3) -> Dictionary:
	var cylinders: Array = []
	_collect_cylinders(_big, cylinders)
	var best: Dictionary = {"score": 1.0e9, "dist": 1.0e9, "axis_dot": 9.0, "within": false, "radius": 0.0, "name": ""}
	for c_v in cylinders:
		var mi: MeshInstance3D = c_v
		var cyl: CylinderMesh = mi.mesh as CylinderMesh
		var xf: Transform3D = mi.global_transform
		var lv: Vector3 = xf.affine_inverse() * sp
		var h: float = cyl.height
		var y: float = clampf(lv.y, -h * 0.5, h * 0.5)
		var t: float = (y + h * 0.5) / maxf(h, 0.0001)
		var r: float = lerpf(cyl.bottom_radius, cyl.top_radius, t)
		var horiz: float = Vector2(lv.x, lv.z).length()
		var dist: float = absf(horiz - r)
		var within: bool = absf(lv.y) <= h * 0.5 + 0.03
		var axis: Vector3 = xf.basis.y.normalized()
		var axis_dot: float = absf(axis.dot(nrm))
		var score: float = dist + 0.05 * axis_dot + (0.0 if within else 0.5)
		if score < float(best["score"]):
			best = {"score": score, "dist": dist, "axis_dot": axis_dot, "within": within, "radius": r, "name": String(mi.name)}
	return best

func _probe_geometry() -> void:
	_check(_big != null, "BigTree 节点存在")
	if _big == null:
		return
	var n := 0
	for p_v in _winter_perches:
		n += 1
		var p: Dictionary = p_v
		var pid := String(p["id"])
		var sp: Vector3 = p["pos"] as Vector3
		var nrm: Vector3 = p.get("normal", Vector3.UP) as Vector3
		var facing: Vector3 = p["facing"] as Vector3
		var local: Vector3 = sp - _base
		var surf := _nearest_branch_surface(sp, nrm)
		_check(bool(surf["within"]) and float(surf["dist"]) <= 0.03, "%s 贴真实枝干圆柱面 dist=%.3f r=%.3f (mesh=%s)" % [pid, float(surf["dist"]), float(surf["radius"]), String(surf["name"])])
		_check(float(surf["axis_dot"]) <= 0.10, "%s 法线垂直枝轴 axis_dot=%.3f" % [pid, float(surf["axis_dot"])])
		_check(absf(nrm.length() - 1.0) < 0.01, "%s 法线单位化" % pid)
		_check(nrm.y >= 0.35, "%s normal.y>=0.35 (%.3f)" % [pid, nrm.y])
		var slope: float = float(p.get("slope", 0.0))
		_check(absf(acos(clampf(nrm.y, -1.0, 1.0)) - slope) < 0.02, "%s slope 与法线一致" % pid)
		_check(absf(Vector2(facing.x, facing.z).length() - 1.0) < 0.02, "%s facing 水平单位化" % pid)
		_check(absf(facing.dot(nrm)) <= 0.45, "%s facing 与法线不冲突 dot=%.3f" % [pid, absf(facing.dot(nrm))])
		var expect_y: float = World.surface_y(BIG_TREE_X, BIG_TREE_Z) + local.y
		_check(absf(sp.y - expect_y) < 0.002, "%s world y 与树根+local.y 一致" % pid)
		var rope_d: float = Vector2(local.x - SWING_PIVOT_LOCAL.x, local.z - SWING_PIVOT_LOCAL.z).length()
		_check(rope_d >= 0.45, "%s 避开秋千绳绳区 (%.2fm)" % [pid, rope_d])
		print("      ", pid, " local=", _fmtv(local), " world=", _fmtv(sp), " n=", _fmtv(nrm), " slope_deg=%.1f" % rad_to_deg(slope))
	for i in range(_winter_perches.size()):
		for j in range(i + 1, _winter_perches.size()):
			var a: Vector3 = (_winter_perches[i] as Dictionary)["pos"] as Vector3
			var b: Vector3 = (_winter_perches[j] as Dictionary)["pos"] as Vector3
			_check(a.distance_to(b) >= 1.5, "裸枝栖点 %d/%d 间距 %.2fm >=1.5" % [i, j, a.distance_to(b)])

# ============================================================
# [SEASON] 冬季完全落叶；红梅删除；WinterBloom 双 MultiMesh
# ============================================================
func _probe_season_params() -> void:
	var vw: Dictionary = Season.visuals([0.0, 0.0, 0.0, 1.0])
	var vs: Dictionary = Season.visuals([0.0, 1.0, 0.0, 0.0])
	var vsp: Dictionary = Season.visuals([1.0, 0.0, 0.0, 0.0])
	_check(float(vw["canopy_keep"]) <= 0.001, "冬季 canopy_keep=0 (%.3f)" % float(vw["canopy_keep"]))
	_check(float(vw["leafcard_keep"]) <= 0.001, "冬季 leafcard_keep=0 (%.3f)" % float(vw["leafcard_keep"]))
	_check(float(vs["canopy_keep"]) >= 0.99, "夏季 canopy_keep=1")
	_check(float(vsp["canopy_keep"]) >= 0.95 and float(vsp["canopy_keep"]) <= 0.98, "春季 canopy_keep 仍 0.96 (%.2f)" % float(vsp["canopy_keep"]))

func _probe_winter_bloom() -> void:
	var wb: Dictionary = _island.get("winter_bloom", {})
	_check(not wb.is_empty(), "world 提供 winter_bloom 数据")
	if wb.is_empty():
		return
	var stems: MultiMeshInstance3D = wb.get("stems", null) as MultiMeshInstance3D
	var heads: MultiMeshInstance3D = wb.get("heads", null) as MultiMeshInstance3D
	var base: Array = wb.get("base", []) as Array
	_check(stems != null and heads != null, "WinterBloom 茎/头节点存在")
	if stems == null or heads == null:
		return
	# P2-B v2 / U5：用户明确要求删掉屋前这五株冬季红花（world.gd:1108-1113 只删锚点、保留结构与节点名）。
	# 旧断言写的是"5 实例"，产品删除后应为 0；这里改为断言删除契约成立（节点仍在但零实例）。
	_check(stems.multimesh.instance_count == 0, "茎 0 实例（冬季红花已按产品要求删除）")
	_check(heads.multimesh.instance_count == 0, "头 0 实例（同上）")
	_check(base.is_empty(), "base 为空（季节循环写 0 次）")
	_check(not stems.visible and not heads.visible, "初始不可见（等季节视觉驱动）")
	_check(not String(stems.name).begins_with("Flower") and not String(heads.name).begins_with("Flower"), "节点名不以 Flower 开头（不被花系统 find_children 误收）")
	var same_xf := true
	for i in range(mini(stems.multimesh.instance_count, heads.multimesh.instance_count)):
		if not stems.multimesh.get_instance_transform(i).is_equal_approx(heads.multimesh.get_instance_transform(i)):
			same_xf = false
	_check(same_xf, "茎/头每实例 Transform 完全一致（花头不会悬空）")
	var door3: Vector3 = IM.door_approach()
	var door := Vector2(door3.x, door3.z)
	var min_sep := 1.0e9
	for i in range(base.size()):
		var e: Dictionary = base[i]
		var pos: Vector3 = e["pos"] as Vector3
		var xz := Vector2(pos.x, pos.z)
		var py: float = World.surface_y(pos.x, pos.z)
		_check(absf(pos.y - (py - 0.01)) < 0.002, "红花 %d 贴合地表" % i)
		_check(World._grass_spot(pos.x, pos.z) > 0.0, "红花 %d 位于合法草地（_grass_spot>0）" % i)
		_check(not World._in_porch(pos.x, pos.z, 0.70), "红花 %d 在门廊排除区外" % i)
		_check(World.trail_clearance(pos.x, pos.z) >= 0.60, "红花 %d 离路缘>=0.60 (%.2f)" % [i, World.trail_clearance(pos.x, pos.z)])
		var dx: float = pos.x - IM.HOUSE_X
		var dz: float = pos.z - IM.HOUSE_Z
		var c: float = cos(IM.HOUSE_YAW)
		var s: float = sin(IM.HOUSE_YAW)
		var lx: float = dx * c - dz * s
		var lz: float = dx * s + dz * c
		_check(absf(lx) < 5.0 and lz > 8.15, "红花 %d 在屋前草坪带（|lx|<5, lz>8.15） lx=%.2f lz=%.2f" % [i, lx, lz])
		var dd: float = xz.distance_to(door)
		_check(dd >= 3.5 and dd <= 6.0, "红花 %d 离门 %.2fm ∈[3.5,6.0]" % [i, dd])
		if i > 0:
			var prev: Vector3 = (base[i - 1] as Dictionary)["pos"] as Vector3
			min_sep = minf(min_sep, pos.distance_to(prev))
	_check(min_sep >= 0.6, "相邻红花间距 %.2fm >=0.6" % min_sep)

# ============================================================
# [SOURCE] 红梅删除干净（无死代码）
# ============================================================
func _read_res(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()

func _probe_source_cleanup() -> void:
	var main_src := _read_res("res://scripts/main.gd")
	var world_src := _read_res("res://scripts/world.gd")
	_check(main_src.find("_winter_plum") < 0, "main.gd 无 _winter_plum 标识符残留")
	_check(main_src.count("WinterPlum") <= 2, "main.gd WinterPlum 仅剩 selftest 回归断言")
	_check(main_src.find("_setup_winter_plum") < 0, "main.gd 无 _setup_winter_plum 残留")
	_check(main_src.find("winter_bloom") >= 0, "main.gd 已接入 winter_bloom")
	_check(world_src.find("winter_branch") >= 0, "world.gd 含 winter_branch 栖点")
	_check(world_src.find("_winter_blooms") >= 0, "world.gd 含冬季红花构建函数")
	_check(world_src.find("WinterBloomStems") >= 0 and world_src.find("WinterBloomHeads") >= 0, "world.gd 冬季红花茎/头双 MultiMesh")
	_check(_world_root.find_child("WinterPlum", true, false) == null, "world 树中无 WinterPlum 节点")

# ============================================================
# [FXGATE] 季节栖点门控 / 不传送 / 预约不残留
# ============================================================
func _ctx_season(sim_seconds: float, winter: float, canopy: float) -> Dictionary:
	return {
		"day": 15 + int(sim_seconds / 86400.0),
		"rising": false,
		"sim_seconds": sim_seconds,
		"time_source": "sim",
		"paused": false,
		"sim_rate": 60.0,
		"weather": {},
		"season": {"winter": winter, "canopy_keep": canopy},
	}

func _step_flock(flock: Node, frames: int, sim_seconds: float, winter: float, canopy: float) -> void:
	var ctx := _ctx_season(sim_seconds, winter, canopy)
	for i in range(frames):
		flock.call("update_birds", DT, 45.0, ctx)

func _probe_fx_gating() -> void:
	var wperches: Array = _island.get("perches", []) as Array
	var cperches: Array = _cottage.get("perches", []) as Array
	var all: Array = wperches + cperches
	var flock: Node = Fx.BirdFlock.new()
	flock.name = "P81ProbeFlock"
	get_root().add_child(flock)
	await process_frame
	flock.call("setup", all)
	await process_frame
	var stats0: Dictionary = flock.call("debug_perch_stats") as Dictionary
	var counts0: Dictionary = flock.call("get_state_counts") as Dictionary
	print("[FXGATE] setup perches=", int(stats0["perch_count"]), " slots=", int(stats0["total_slots"]), " perched=", int(counts0["perched"]), " teleports=", int(stats0["teleports"]))
	_check(int(stats0["perch_count"]) == 40, "fx 归一化保留全部 40 点")
	_check(int(stats0["zones"].get("winter_branch", 0)) == 5, "fx zone 识别 5 个 winter_branch")
	var tp_base := int(stats0["teleports"])

	# 冬季：裸枝点开、冠面点关；驱逐不传送。
	var sim_w: float = 1.0e6
	_step_flock(flock, 240, sim_w, 1.0, 0.0)
	var stats_w: Dictionary = flock.call("debug_perch_stats") as Dictionary
	_check(bool(stats_w["winter_open"]), "冬季 gate: winter_open=true")
	_check(not bool(stats_w["leafy_open"]), "冬季 gate: leafy_open=false")
	var avail_w: Array = flock.call("debug_perch_availability", sim_w, 45.0, false) as Array
	var w_ok := 0
	var w_bad := 0
	var tree_ok := 0
	var tree_bad := 0
	for e_v in avail_w:
		var e: Dictionary = e_v
		var kind := String(e["kind"])
		if kind == "winter_branch":
			if bool(e["eligible"]):
				w_ok += 1
			else:
				w_bad += 1
		elif kind == "tree_branch":
			if bool(e["eligible"]):
				tree_ok += 1
			elif String(e["reason"]) == "season_off":
				tree_bad += 1
	_check(w_ok == 5 and w_bad == 0, "冬季 5 个裸枝点全部 eligible")
	_check(tree_ok == 0 and tree_bad == 6, "冬季 6 个冠面点全部 season_off")
	_check(int(stats_w["teleports"]) == tp_base, "冬季 240 帧无瞬移 (teleports=%d)" % int(stats_w["teleports"]))
	var used_w := int(stats_w["used_slots"])
	var cw: Dictionary = flock.call("get_state_counts") as Dictionary
	_check(used_w == int(cw["perched"]) + int(cw["landing"]), "冬季预约表 used_slots==perched+landing (%d==%d+%d)" % [used_w, int(cw["perched"]), int(cw["landing"])])
	_check(int(cw["perch_conflicts"]) == 0, "冬季无槽位冲突")

	# 夏季：裸枝点关、冠面点开；冬季裸枝上的鸟被正常起飞驱逐、落地失效原地续飞。
	var sim_s: float = sim_w + 400.0
	_step_flock(flock, 120, sim_s, 0.0, 1.0)
	var stats_s: Dictionary = flock.call("debug_perch_stats") as Dictionary
	_check(not bool(stats_s["winter_open"]), "夏季 gate: winter_open=false")
	_check(bool(stats_s["leafy_open"]), "夏季 gate: leafy_open=true")
	_check(int(stats_s["teleports"]) == tp_base, "夏季 120 帧仍无瞬移 (teleports=%d)" % int(stats_s["teleports"]))
	var avail_s: Array = flock.call("debug_perch_availability", sim_s, 45.0, false) as Array
	var s_ok := 0
	var s_bad := 0
	for e_v in avail_s:
		var e: Dictionary = e_v
		if String(e["kind"]) == "winter_branch":
			if not bool(e["eligible"]) and String(e["reason"]) == "season_off":
				s_ok += 1
			else:
				s_bad += 1
	_check(s_ok == 5 and s_bad == 0, "夏季 5 个裸枝点全部 season_off")
	var snap: Array = flock.call("debug_snapshot") as Array
	var holder := 0
	for b_v in snap:
		var b: Dictionary = b_v
		var st := int(b["state"])
		if st != STATE_PERCH and st != STATE_LANDING:
			continue
		if String(b["perch_id"]).begins_with("winter_branch"):
			holder += 1
	_check(holder == 0, "夏季无鸟仍持有 winter_branch 栖点")
	var used_s := int(stats_s["used_slots"])
	var cs: Dictionary = flock.call("get_state_counts") as Dictionary
	_check(used_s == int(cs["perched"]) + int(cs["landing"]), "夏季预约表 used_slots==perched+landing (%d==%d+%d)" % [used_s, int(cs["perched"]), int(cs["landing"])])
	_check(int(cs["perch_conflicts"]) == 0, "夏季无槽位冲突")
	var used_map: Dictionary = flock.get("_perch_used") as Dictionary
	var residual := 0
	for k_v in used_map.keys():
		if String(k_v).begins_with("winter_branch") and (used_map[k_v] as Array).size() > 0:
			residual += 1
	_check(residual == 0, "夏季预约表中无 winter_branch 残留")
	get_root().remove_child(flock)
	flock.free()
