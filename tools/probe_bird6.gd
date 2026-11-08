extends SceneTree
## Phase6 T5 海鸥栖枝验收探针（headless，不加载 isle.tscn、不渲染）：
##   D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe --headless --path D:/休闲小岛幻境/游戏工程 --script res://tools/probe_bird6.gd
## 断言：
##   [WORLD]   world.gd 栖枝 = 16（大树6/灯塔4/码头2/花园4），不再有 roof_*/eave_* 重复屋面点
##   [NORMAL]  fx 解析 normal/slope：radius<=0 / normal.y<0.35 / slope>60° / 坏 normal 一律跳过；缺省法线=UP
##   [FOOT]    脚点 = perch.pos + normal*0.02（PERCH_FOOT_LIFT）；脚点落在屋面/脊瓦上，距离 ∈ [0,0.12]，不穿瓦/不悬空
##   [ALIGN]   身体 up 对齐停栖面法线（倾角 <=35°），正交基；斜瓦上身体随瓦面倾斜
##   [CLAMP]   法线倾角超过 35° 时身体倾角被夹到 35°（不翻倒）
##   [MUTEX]   夜间 10 只全部栖息、无重复槽位、perch_conflicts=0；同一栖枝多鸟间距 >= 0.9m
##   [ANIM]    夜间停栖 / 日间起飞降落状态机保留（takeoffs/landings 增长）
##   [ROOF]    P7-V2 口径：屋顶区（ridge/eave/chimney）同时占用 <=2、同一屋顶栖点 <=2（无三只同排）、
##             多轮分布覆盖多种 kind、屋顶脚点距瓦面 ∈[0,0.12]；旧的「初始 3 只固定屋脊且白天不飞」因
##             P7-V2 移除 index<3 屋脊硬编码 + 屋顶分区上限而作废（口径变更见 开发产物/p7v2/REGRESSION_P7V2.md）。
## 退出码：0 = 全部断言通过。

const Fx := preload("res://scripts/fx.gd")
const World := preload("res://scripts/world.gd")
# cottage.gd 归 T4 所有，编辑窗口内可能短暂无法解析：用运行时 load 而不是 preload，
# 这样 T4 中间态下探针仍能跑 world/normal/spacing 段并给出明确提示。
var _cottage_script: GDScript = null
const DT := 1.0 / 60.0
const BIRD_COUNT := 10
const STATE_PERCH := 3
const BODY_TILT_MAX := 0.610865

var _pass := 0
var _fail := 0

func _initialize() -> void:
	print("=== T5 BIRD PROBE START ===")
	await process_frame
	_probe_world_perches()
	_probe_normalize()
	var holder := Node3D.new()
	holder.name = "ProbeHolder"
	root.add_child(holder)
	_cottage_script = load("res://scripts/cottage.gd") as GDScript
	if _cottage_script == null or not _cottage_script.can_instantiate():
		print("[SKIP] cottage.gd 当前无法加载（T4 编辑中间态），跳过屋顶/姿态/动画断言，等地板完成后重跑")
		_check(false, "cottage.gd 可加载（T4 中间态导致 parse error，需 T4 完成）")
		_probe_spacing()
		holder.free()
		print("=== T5 BIRD PROBE RESULT: FAIL pass=", _pass, " fail=", _fail, " ===")
		quit(1)
		return
	var cot: Dictionary = _cottage_script.build(holder)
	await process_frame
	var cot_root: Node3D = cot["root"]
	var cot_perches: Array = (cot["perches"] as Array).duplicate()
	print("[COTTAGE] perches=", cot_perches.size(), " ids=", _ids(cot_perches))
	_collect_roof_geometry(cot_root)
	_probe_roof_contact(cot_perches)
	_probe_perch_pose(cot_perches)
	_probe_spacing()
	_probe_day_anim(cot_perches)
	_probe_day_roof_rest(cot_perches)
	_probe_nan(cot_perches)
	holder.free()
	print("=== T5 BIRD PROBE RESULT: ", "PASS" if _fail == 0 else "FAIL", " pass=", _pass, " fail=", _fail, " ===")
	quit(0 if _fail == 0 else 1)

func _check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("  [OK] ", msg)
	else:
		_fail += 1
		print("  [FAIL] ", msg)

func _ids(perches: Array) -> Array:
	var out: Array = []
	for p_v in perches:
		out.append(String((p_v as Dictionary).get("id", "?")))
	return out

func _find(node: Node, nm: String) -> Node:
	if node == null:
		return null
	if String(node.name) == nm:
		return node
	for c in node.get_children():
		var r: Node = _find(c, nm)
		if r != null:
			return r
	return null

func _vkey(v: Vector3) -> String:
	return "%.3f,%.3f,%.3f" % [v.x, v.y, v.z]

# ============================================================
# 1) world.gd 栖枝：16 个且无重复屋面点
# ============================================================
func _probe_world_perches() -> void:
	print("--- WORLD PERCHES ---")
	var big := {"pos": Vector3(0.0, 0.0, 0.0), "perches": [
		Vector3(3.2, 6.1, 0.4), Vector3(-3.0, 6.4, -0.6), Vector3(0.5, 7.0, 3.1),
		Vector3(-0.7, 6.7, -3.2), Vector3(4.0, 5.8, 4.2), Vector3(-3.8, 5.9, -4.0)]}
	var dock := {"perch": Vector3(10.0, 2.0, 4.0), "bollard": Vector3(11.0, 1.6, 2.5)}
	var lh := {"perches": [Vector3(-20.0, 15.0, 9.0), Vector3(-14.0, 15.0, 9.0), Vector3(-17.0, 16.0, 13.0), Vector3(-17.0, 16.0, 5.0)]}
	var perches: Array = World._build_perches(big, dock, lh)
	print("[WORLD] count=", perches.size(), " ids=", _ids(perches))
	_check(perches.size() == 16, "world 栖枝数 == 16（大树6+灯塔4+码头2+花园4，实际 %d）" % perches.size())
	var bad_ids: Array = []
	var kinds: Dictionary = {}
	for p_v in perches:
		var p: Dictionary = p_v
		var pid: String = String(p["id"])
		kinds[String(p["kind"])] = true
		if pid.begins_with("roof_") or pid.begins_with("eave_") or pid.begins_with("roof_chimney"):
			bad_ids.append(pid)
	_check(bad_ids.is_empty(), "world 不再含重复屋面栖枝 roof_*/eave_*（残留 %s）" % str(bad_ids))
	_check(not kinds.has("roof") and not kinds.has("eave") and not kinds.has("ridge"), "world 栖枝 kind 不含屋顶类（实际 %s）" % str(kinds.keys()))
	_check(kinds.has("tree_branch") and kinds.has("lighthouse_platform") and kinds.has("dock") and kinds.has("garden_post"), "保留大树/灯塔/码头/花园四类栖枝（实际 %s）" % str(kinds.keys()))

# ============================================================
# 2) normalize：normal/slope 解析与过滤
# ============================================================
func _probe_normalize() -> void:
	print("--- NORMALIZE (normal/slope) ---")
	var flat := {"id": "flat", "pos": Vector3(0.0, 5.0, 0.0), "facing": Vector3(0.0, 0.0, 1.0), "radius": 1.6, "kind": "flat"}
	var pitch := acos(0.827)  # 34.19° 屋顶坡
	var roof_n := Vector3(sin(pitch), cos(pitch), 0.0).normalized()
	var tilt20 := deg_to_rad(20.0)
	var valid_roof := {"id": "roof_ok", "pos": Vector3(2.0, 9.0, 0.0), "facing": Vector3(0.0, 0.0, 1.0), "radius": 0.4, "kind": "eave", "normal": roof_n, "slope": pitch}
	var valid_tilt := {"id": "tilt20", "pos": Vector3(-2.0, 8.0, 0.0), "facing": Vector3(0.0, 0.0, 1.0), "radius": 0.4, "kind": "roof", "normal": Vector3(sin(tilt20), cos(tilt20), 0.0), "slope": tilt20}
	var valid_steep := {"id": "steep60", "pos": Vector3(0.0, 7.0, 3.0), "facing": Vector3(0.0, 0.0, 1.0), "radius": 0.4, "kind": "roof", "normal": Vector3(sin(deg_to_rad(60.0)), cos(deg_to_rad(60.0)), 0.0)}
	var raw: Array = [
		flat, valid_roof, valid_tilt, valid_steep,
		{"id": "zero_r", "pos": Vector3(4.0, 9.0, 0.0), "radius": 0.0, "normal": Vector3.UP},
		{"id": "neg_r", "pos": Vector3(5.0, 9.0, 0.0), "radius": -1.0, "normal": Vector3.UP},
		{"id": "down", "pos": Vector3(6.0, 9.0, 0.0), "radius": 0.4, "normal": Vector3(0.0, -1.0, 0.0)},
		{"id": "low_y", "pos": Vector3(7.0, 9.0, 0.0), "radius": 0.4, "normal": Vector3(0.0, 0.2, 0.98).normalized()},
		{"id": "steep", "pos": Vector3(8.0, 9.0, 0.0), "radius": 0.4, "normal": Vector3(sin(deg_to_rad(70.0)), cos(deg_to_rad(70.0)), 0.0)},
		{"id": "bad_n", "pos": Vector3(9.0, 9.0, 0.0), "radius": 0.4, "normal": "up"},
		{"id": "deg_slope", "pos": Vector3(0.0, 6.0, 0.0), "facing": Vector3(0.0, 0.0, 1.0), "radius": 0.4, "normal": Vector3(sin(deg_to_rad(20.0)), cos(deg_to_rad(20.0)), 0.0), "slope": 20.0},
		]
	var flock = Fx.BirdFlock.new()
	root.add_child(flock)
	flock.setup(raw)
	var kept: Array = flock.get_perches()
	print("[NORMAL] kept=", kept.size(), " ids=", _ids(kept))
	_check(kept.size() == 5, "过滤后保留 5 个可停栖点：flat/roof_ok/tilt20/steep60/deg_slope（实际 %d）" % kept.size())
	var by_id: Dictionary = {}
	for p_v in kept:
		by_id[String((p_v as Dictionary)["id"])] = p_v
	_check(by_id.has("flat") and by_id.has("roof_ok") and by_id.has("tilt20") and by_id.has("steep60") and by_id.has("deg_slope"), "保留集合 id 正确")
	for bad in ["zero_r", "neg_r", "down", "low_y", "steep", "bad_n"]:
		_check(not by_id.has(bad), "%s 被跳过" % bad)
	var flat_p: Dictionary = by_id["flat"]
	_check((flat_p["normal"] as Vector3).is_equal_approx(Vector3.UP) and absf(float(flat_p["slope"])) < 0.0001, "缺省 normal=UP / slope=0")
	var roof_p: Dictionary = by_id["roof_ok"]
	_check(absf((roof_p["normal"] as Vector3).length() - 1.0) < 0.001 and absf(float(roof_p["slope"]) - pitch) < 0.002, "normal 归一化、slope 由 normal 推得（%.3f rad）" % float(roof_p["slope"]))
	var deg_p: Dictionary = by_id["deg_slope"]
	_check(absf(float(deg_p["slope"]) - deg_to_rad(20.0)) < 0.002, "slope=20(度) 被识别为 %.3f rad" % float(deg_p["slope"]))
	flock.free()

# ============================================================
# 3) 屋顶：脚点-瓦面距离（与渲染共用 cottage 的瓦片/脊瓦几何数据）
# ============================================================
# Godot 4.7 headless（dummy 渲染器）下 MultiMesh 实例变换无法读回（手工 MultiMesh 也一样，
# get_instance_transform 恒 identity），所以不读渲染实例；改为调用 cottage.gd 暴露的
# static _roof_cap_data(C) / _roof_tile_data(C)（_roof 渲染用的同一份 xforms + mesh），
# 在 cottage 局部空间做“点到圆柱瓦片表面的有符号距离”，<0 表示脚落进瓦里（穿模）。
var _roof_root: Node3D = null
var _roof_C: Dictionary = {}
var _roof_cyls: Array = []

func _collect_roof_geometry(cot_root: Node3D) -> void:
	_roof_root = cot_root
	_roof_C.clear()
	_roof_cyls.clear()
	var cv = cot_root.get_meta("cottage_ctx", null)
	if typeof(cv) == TYPE_DICTIONARY:
		_roof_C = cv
	if _roof_C.is_empty():
		print("[ROOF] cottage_ctx MISSING")
		return
	for part in ["cap", "tile"]:
		var fn: String = "_roof_cap_data" if part == "cap" else "_roof_tile_data"
		var data = _cottage_script.call(fn, _roof_C)
		if typeof(data) != TYPE_DICTIONARY:
			print("[ROOF] cottage.", fn, " 不可用")
			continue
		var cd: Dictionary = data
		var mesh := cd.get("mesh", null) as CylinderMesh
		var xfs_v = cd.get("xforms", null)
		if mesh == null or typeof(xfs_v) != TYPE_ARRAY:
			print("[ROOF] cottage.", fn, " 返回缺 mesh/xforms")
			continue
		for i in range((xfs_v as Array).size()):
			_roof_cyls.append({"xf": (xfs_v as Array)[i], "top": mesh.top_radius, "bot": mesh.bottom_radius, "h": mesh.height, "part": part})
	print("[ROOF] cottage cylinders=", _roof_cyls.size(), " (cap/tile 均为渲染同源数据)")
	_check(_roof_cyls.size() > 0, "cottage 暴露可解析的瓦片/脊瓦几何（%d 个圆柱实例）" % _roof_cyls.size())

## 点到单个圆柱（瓦/脊瓦）表面的有符号距离：<0 = 在圆柱内部（穿模），>0 = 外侧距离
func _cyl_signed_distance(xf: Transform3D, lp: Vector3, top_r: float, bot_r: float, h: float) -> float:
	var q: Vector3 = xf.affine_inverse() * lp
	var half: float = h * 0.5
	var t: float = clampf((q.y + half) / maxf(h, 0.0001), 0.0, 1.0)
	var r: float = lerpf(bot_r, top_r, t)
	var rho: float = sqrt(q.x * q.x + q.z * q.z)
	var dy: float = absf(q.y) - half
	if dy <= 0.0:
		return rho - r
	return sqrt(dy * dy + pow(maxf(rho - r, 0.0), 2.0))

## 局部点到指定类别（ridge/eave）瓦片表面的最近有符号距离
func _roof_signed_distance_local(lp: Vector3, kind: String) -> float:
	var want: String = "cap" if kind == "ridge" or kind == "ridge_cap" else "tile"
	var best := 1.0e30
	for c_v in _roof_cyls:
		var c: Dictionary = c_v
		if String(c["part"]) != want:
			continue
		var d: float = _cyl_signed_distance(c["xf"], lp, float(c["top"]), float(c["bot"]), float(c["h"]))
		best = minf(best, d)
	return best

## 世界坐标脚点 -> 最近瓦面/脊瓦/烟囱压顶的有符号距离
func _roof_signed_distance(world_foot: Vector3, kind: String) -> float:
	if _roof_C.is_empty() or _roof_root == null:
		return 1.0e30
	var lp: Vector3 = _roof_root.to_local(world_foot)
	if kind == "chimney":
		return lp.y - (float(_roof_C["ch_top"]) + 0.35)
	if kind == "ridge" or kind == "ridge_cap" or kind == "eave" or kind == "roof" or kind == "tile":
		return _roof_signed_distance_local(lp, kind)
	return 1.0e30

func _is_roof_kind(kind: String) -> bool:
	return kind == "ridge" or kind == "eave" or kind == "roof" or kind == "tile" or kind == "ridge_cap"

func _probe_roof_contact(cot_perches: Array) -> void:
	print("--- ROOF CONTACT (cottage perches, shared tile geometry) ---")
	_check(not _roof_C.is_empty(), "cottage root 暴露 cottage_ctx 屋顶参数")
	var roof: Array = []
	var with_normal := 0
	var sloped_normals := 0
	var skipped := 0
	for p_v in cot_perches:
		var p: Dictionary = p_v
		var kind: String = String(p["kind"])
		if typeof(p.get("normal", null)) == TYPE_VECTOR3:
			with_normal += 1
			var n0: Vector3 = (p["normal"] as Vector3).normalized()
			if rad_to_deg(acos(clampf(n0.y, -1.0, 1.0))) > 5.0:
				sloped_normals += 1
		if (_is_roof_kind(kind) or kind == "chimney") and float(p["radius"]) > 0.0:
			roof.append(p)
		if float(p["radius"]) <= 0.0:
			skipped += 1
	print("[ROOF] cottage perches=", cot_perches.size(), " roof_perches=", roof.size(), " with_normal=", with_normal, " sloped_normals=", sloped_normals, " radius<=0=", skipped)
	_check(with_normal > 0, "cottage 屋顶栖枝提供 normal（实际 %d 个）" % with_normal)
	_check(sloped_normals > 0, "存在倾斜瓦面法线（坡度>5° 的 normal %d 个，用于验证身体随瓦面倾斜）" % sloped_normals)
	if roof.is_empty():
		_check(false, "cottage 至少提供 1 个可停栖屋顶栖枝")
		return
	var bad_dist := 0
	var inside := 0
	var min_d := 1.0e30
	var max_d := -1.0e30
	for p_v in roof:
		var p: Dictionary = p_v
		var n: Vector3 = (p["normal"] as Vector3).normalized()
		var pos: Vector3 = p["pos"]
		var foot: Vector3 = pos + n * Fx.PERCH_FOOT_LIFT
		var d: float = _roof_signed_distance(foot, String(p["kind"]))
		min_d = minf(min_d, d)
		max_d = maxf(max_d, d)
		if d < -0.001:
			inside += 1
		if d < -0.001 or d > 0.12:
			bad_dist += 1
		var slant: float = rad_to_deg(acos(clampf(n.y, -1.0, 1.0)))
		var flag: String = "" if d >= -0.001 and d <= 0.12 else "<-- OUT OF [0,0.12]"
		print("  perch %-12s kind=%-9s pos=(%.2f,%.2f,%.2f) normal=(%.2f,%.2f,%.2f) slant=%.1f° foot->surface=%.3f m %s" % [String(p["id"]), String(p["kind"]), pos.x, pos.y, pos.z, n.x, n.y, n.z, slant, d, flag])
	print("[ROOF] foot->surface signed distance min=%.3f max=%.3f inside=%d bad=%d" % [min_d, max_d, inside, bad_dist])
	_check(bad_dist == 0, "所有屋顶栖枝脚点-瓦面/脊瓦/烟囱压顶距离 ∈ [0,0.12] 且不穿模（越界 %d/%d）" % [bad_dist, roof.size()])
	_check(inside == 0, "无脚点落入瓦/脊瓦内部（穿模 %d 个）" % inside)

# ============================================================
# 4) 停栖姿态：脚点位置、up 对齐法线、限倾
# ============================================================
func _probe_perch_pose(cot_perches: Array) -> void:
	print("--- PERCH POSE ---")
	var flock = Fx.BirdFlock.new()
	root.add_child(flock)
	flock.setup(cot_perches)
	_seat_all(flock)
	for i in range(120):
		flock.update_birds(DT, -10.0)
	var st: Dictionary = flock.get_state_counts()
	print("[POSE] ", _counts(st))
	_check(int(st["perched"]) == BIRD_COUNT, "夜间 10 只全部停栖（实际 %d）" % int(st["perched"]))
	_check(int(st["perch_conflicts"]) == 0, "perch_conflicts == 0（实际 %d）" % int(st["perch_conflicts"]))
	var flock_perches: Array = flock.get_perches()
	var used: Dictionary = {}
	var dup := 0
	var bad_foot := 0
	var bad_align := 0
	var bad_tilt := 0
	var bad_ortho := 0
	var max_tilt_deg := 0.0
	var roof_dist_bad := 0
	var birds: Array = flock.get("_birds")
	for b_v in birds:
		var b: Dictionary = b_v
		if int(b["state"]) != STATE_PERCH:
			continue
		var pid: String = String(b["perch_id"])
		var slot: int = int(b["perch_slot"])
		var key: String = "%s#%d" % [pid, slot]
		if used.has(key):
			dup += 1
		used[key] = true
		var perch: Dictionary = {}
		for p_v in flock_perches:
			if String((p_v as Dictionary)["id"]) == pid:
				perch = p_v
				break
		if perch.is_empty():
			bad_foot += 1
			continue
		var n: Vector3 = (perch["normal"] as Vector3).normalized()
		var want: Vector3 = (perch["pos"] as Vector3) + n * Fx.PERCH_FOOT_LIFT
		var node: Node3D = b["node"]
		var foot_err: float = node.position.distance_to(want)
		var up: Vector3 = node.basis.y.normalized()
		# align_err：身体 up 与法线的偏差，应≈0；tilt：身体相对竖直的倾角，应≈min(slant,35°)
		var align_err: float = rad_to_deg(acos(clampf(up.dot(n), -1.0, 1.0)))
		var tilt: float = rad_to_deg(acos(clampf(up.y, -1.0, 1.0)))
		var slant: float = rad_to_deg(acos(clampf(n.y, -1.0, 1.0)))
		var expect_tilt: float = minf(slant, rad_to_deg(BODY_TILT_MAX))
		max_tilt_deg = maxf(max_tilt_deg, tilt)
		var dot_xy: float = node.basis.x.normalized().dot(up)
		var dot_yz: float = up.dot(node.basis.z.normalized())
		var len_err: float = absf(node.basis.x.length() - 1.0) + absf(node.basis.y.length() - 1.0) + absf(node.basis.z.length() - 1.0)
		print("  bird %-6s perch=%-12s slot=%d foot_err=%.4f align_err=%.2f° tilt=%.2f° expect_tilt=%.2f° (slant %.2f°)" % [
			String(node.name), pid, slot, foot_err, align_err, tilt, expect_tilt, slant])
		if foot_err > 0.01:
			bad_foot += 1
		if align_err > 0.6:
			bad_align += 1
		if absf(tilt - expect_tilt) > 0.6:
			bad_tilt += 1
			print("    [warn] tilt %.2f° != expect %.2f°" % [tilt, expect_tilt])
		if absf(dot_xy) > 0.01 or absf(dot_yz) > 0.01 or len_err > 0.01:
			bad_ortho += 1
		if _is_roof_kind(String(perch["kind"])) and not _roof_C.is_empty():
			var d: float = _roof_signed_distance(node.position, String(perch["kind"]))
			if d < -0.001 or d > 0.12:
				roof_dist_bad += 1
				print("    [warn] roof foot distance=%.3f out of [0,0.12]" % d)
	_check(dup == 0, "无重复 (perch,slot) 占用（重复 %d）" % dup)
	_check(bad_foot == 0, "鸟脚点 = perch.pos + normal*0.02（误差>1cm 的 %d 只）" % bad_foot)
	_check(bad_align == 0, "身体 up 与停栖面法线对齐（偏差>0.6° 的 %d 只）" % bad_align)
	_check(bad_tilt == 0, "身体倾角=min(瓦面坡度,35°)（不符 %d 只，max_tilt=%.2f°）" % [bad_tilt, max_tilt_deg])
	_check(bad_ortho == 0, "停栖基正交（非正交 %d 只）" % bad_ortho)
	_check(roof_dist_bad == 0, "实际停栖鸟脚点距瓦面 ∈ [0,0.12]（越界 %d 只）" % roof_dist_bad)
	# 斜瓦上身体应随瓦面倾斜，而不是被摆平：只统计法线确实倾斜（>5°）的屋顶栖枝
	var sloped_total := 0
	var sloped_aligned := 0
	for b_v in birds:
		var b: Dictionary = b_v
		if int(b["state"]) != STATE_PERCH:
			continue
		var perch2: Dictionary = flock.call("_find_perch", String(b["perch_id"]))
		if perch2.is_empty() or not _is_roof_kind(String(perch2["kind"])):
			continue
		var n2: Vector3 = (perch2["normal"] as Vector3).normalized()
		var slant2: float = rad_to_deg(acos(clampf(n2.y, -1.0, 1.0)))
		if slant2 < 5.0:
			continue
		sloped_total += 1
		var up2: Vector3 = (b["node"] as Node3D).basis.y.normalized()
		var tilt2: float = rad_to_deg(acos(clampf(up2.y, -1.0, 1.0)))
		if absf(tilt2 - minf(slant2, rad_to_deg(BODY_TILT_MAX))) <= 0.6:
			sloped_aligned += 1
	if sloped_total == 0:
		print("[POSE] [warn] 屋顶栖枝 normal 均接近 UP（无倾斜 >5° 的法线），斜瓦随动检查无样本（T4 应提供瓦面法线）")
		_check(false, "屋顶栖枝提供真实瓦面法线（存在倾角 >5° 的 normal）")
	else:
		_check(sloped_aligned == sloped_total, "斜瓦上的身体 up 与瓦面法线一致（%d/%d 只）" % [sloped_aligned, sloped_total])
	flock.free()

func _seat_all(flock) -> void:
	var birds: Array = flock.get("_birds")
	# setup() 默认已让前 4 只就位；这里先彻底清空占位/状态，保证 10 只都能各自分到槽位
	flock.call("_clear_allocations")
	for b0_v in birds:
		var b0: Dictionary = b0_v
		b0["state"] = 0
		b0["perch_id"] = ""
		b0["perch_slot"] = -1
		b0["perch_pos"] = Vector3.ZERO
		b0["timer"] = 0.0
		b0["waiting"] = false
		b0["fold"] = 0.0
	var seated := 0
	for b_v in birds:
		var b: Dictionary = b_v
		var node: Node3D = b["node"]
		var slot: Dictionary = flock.call("_find_free_slot", node.position)
		if slot.is_empty():
			continue
		flock.call("_reserve_slot", String(slot["id"]), int(slot["slot"]))
		b["perch_id"] = slot["id"]
		b["perch_slot"] = slot["slot"]
		b["perch_pos"] = slot["pos"]
		b["state"] = STATE_PERCH
		b["timer"] = 999.0
		b["fold"] = 1.0
		b["prev_pos"] = slot["pos"]
		b["teleport"] = true
		node.position = slot["pos"]
		var perch: Dictionary = flock.call("_find_perch", String(slot["id"]))
		if not perch.is_empty():
			flock.call("_apply_perch_pose", b, perch)
		seated += 1
	print("[SEAT] seated=", seated)

func _counts(st: Dictionary) -> String:
	return "birds=%d fly=%d takeoff=%d landing=%d perch=%d airborne=%d slots=%d used=%d conflicts=%d takeoffs=%d landings=%d night=%s" % [
		int(st["birds"]), int(st["flying"]), int(st["takeoff"]), int(st["landing"]), int(st["perched"]), int(st["airborne"]),
		int(st["perch_slots"]), int(st["perch_used"]), int(st["perch_conflicts"]), int(st["takeoffs"]), int(st["landings"]), str(st["night"])]

# ============================================================
# 5) 同一栖枝多鸟间距（宽栖枝 -> 多槽位）
# ============================================================
func _probe_spacing() -> void:
	print("--- SPACING (multi-bird same perch) ---")
	var broad: Array = []
	for i in range(3):
		broad.append({"id": "broad_%d" % i, "pos": Vector3(float(i) * 8.0 - 8.0, 6.0, 0.0), "facing": Vector3(0.0, 0.0, 1.0), "radius": 2.4, "kind": "tree_branch"})
	var flock = Fx.BirdFlock.new()
	root.add_child(flock)
	flock.setup(broad)
	var st0: Dictionary = flock.get_state_counts()
	print("[SPACING] slots=", int(st0["perch_slots"]), " (expansion >= 10)")
	for i in range(1500):
		flock.update_birds(DT, -10.0)
	var st: Dictionary = flock.get_state_counts()
	print("[SPACING] ", _counts(st))
	_check(int(st["perched"]) == BIRD_COUNT, "宽栖枝夜间 10 只全部停栖（实际 %d）" % int(st["perched"]))
	var min_same := 1.0e30
	var pairs := 0
	var birds: Array = flock.get("_birds")
	var same_perch: Dictionary = {}
	for b_v in birds:
		var b: Dictionary = b_v
		if int(b["state"]) != STATE_PERCH:
			continue
		var pid: String = String(b["perch_id"])
		if not same_perch.has(pid):
			same_perch[pid] = []
		(same_perch[pid] as Array).append(b)
	for pid in same_perch.keys():
		var arr: Array = same_perch[pid]
		for i in range(arr.size()):
			for j in range(i + 1, arr.size()):
				var p1: Vector3 = (arr[i]["node"] as Node3D).position
				var p2: Vector3 = (arr[j]["node"] as Node3D).position
				min_same = minf(min_same, p1.distance_to(p2))
				pairs += 1
	print("[SPACING] same-perch pairs=", pairs, " min_dist=%.3f" % (min_same if pairs > 0 else -1.0))
	_check(pairs > 0, "存在同栖枝多鸟（pairs=%d）" % pairs)
	_check(pairs == 0 or min_same >= 0.9, "同栖枝鸟间距 >= 0.9m（min=%.3f）" % min_same)
	_check(int(st["perch_conflicts"]) == 0, "宽栖枝 perch_conflicts=0")
	flock.free()

# ============================================================
# 6) 日间起飞/降落状态机保留
# ============================================================
func _probe_day_anim(cot_perches: Array) -> void:
	print("--- DAY ANIMATION ---")
	var flock = Fx.BirdFlock.new()
	root.add_child(flock)
	flock.setup(cot_perches)
	_seat_all(flock)
	# 让停栖鸟的计时器快点到期，否则要等 8~20s 才起飞（40s 内不够）
	_stir_timers(flock, 0.35)
	var st_before: Dictionary = flock.get_state_counts()
	var max_flying := 0
	var took_off := 0
	for i in range(2400):
		flock.update_birds(DT, 20.0)
		var st_i: Dictionary = flock.get_state_counts()
		max_flying = maxi(max_flying, int(st_i["flying"]))
		took_off = maxi(took_off, int(st_i["takeoffs"]))
	var st: Dictionary = flock.get_state_counts()
	print("[ANIM] ", _counts(st))
	print("[ANIM] takeoffs ", int(st_before["takeoffs"]), " -> ", int(st["takeoffs"]), ", landings ", int(st_before["landings"]), " -> ", int(st["landings"]), ", max_flying=", max_flying)
	_check(int(st["takeoffs"]) > int(st_before["takeoffs"]), "日间起飞计数增长（%d -> %d）" % [int(st_before["takeoffs"]), int(st["takeoffs"])])
	_check(int(st["landings"]) > int(st_before["landings"]), "日间降落计数增长（%d -> %d）" % [int(st_before["landings"]), int(st["landings"])])
	_check(max_flying > 0, "日间存在飞行鸟（逐帧 max_flying=%d）" % max_flying)
	flock.free()

## 让所有停栖鸟的起飞计时器尽快到期（base + i*0.27 秒），用于观察起飞/降落动画。
# ============================================================
# 5b) 白天屋脊歇脚：初始 3 只优先落屋脊，白天不主动起飞（官方 06_bird_roof 镜头）
# ============================================================
func _max_used(d: Dictionary) -> int:
	var m := 0
	for k in d.keys():
		m = maxi(m, int(d[k]))
	return m

func _probe_day_roof_rest(cot_perches: Array) -> void:
	print("--- DAY ROOF REST (白天屋脊歇脚) ---")
	var flock = Fx.BirdFlock.new()
	root.add_child(flock)
	flock.setup(cot_perches)
	var birds: Array = flock.get("_birds")
	var base_pos: Dictionary = {}
	var roof_seated := 0
	var foot_bad := 0
	var kinds_used: Dictionary = {}
	var row_use0: Dictionary = {}
	for b_v in birds:
		var b: Dictionary = b_v
		if int(b["state"]) != STATE_PERCH:
			continue
		var perch: Dictionary = flock.call("_find_perch", String(b["perch_id"]))
		if perch.is_empty():
			continue
		var kind := String(perch.get("kind", ""))
		kinds_used[kind] = true
		var zone := String(flock.call("_perch_zone", kind))
		if zone != "roof":
			continue
		roof_seated += 1
		var pid := String(b["perch_id"])
		row_use0[pid] = int(row_use0.get(pid, 0)) + 1
		var nm := String((b["node"] as Node3D).name)
		base_pos[nm] = (b["node"] as Node3D).position
		if kind == "ridge" or kind == "eave":
			var d: float = _roof_signed_distance((b["node"] as Node3D).position, kind)
			if d < -0.001 or d > 0.12:
				foot_bad += 1
	print("[ROOF REST] initial roof_zone=", roof_seated, " kinds=", str(kinds_used.keys()), " ids=", str(base_pos.keys()))
	_check(roof_seated <= 2, "初始屋顶区（ridge/eave/chimney）停栖 <=2（P7-V2 分区上限；实际 %d）" % roof_seated)
	_check(_max_used(row_use0) <= 2, "初始同一屋顶栖点 <=2 只（无三只同排；实际 %d）" % _max_used(row_use0))
	_check(foot_bad == 0, "屋顶鸟脚点距瓦面 ∈ [0,0.12]（越界 %d）" % foot_bad)
	_check(kinds_used.size() >= 2, "初始停栖分布覆盖多种 kind（实际 %s）" % str(kinds_used.keys()))
	var roof_max := 0
	var row_max := 0
	var kinds_seen: Dictionary = {}
	for i in range(1800):
		flock.update_birds(DT, 20.0)
		var roof_now := 0
		var row_use: Dictionary = {}
		for b_v in birds:
			var b: Dictionary = b_v
			if int(b["state"]) != STATE_PERCH:
				continue
			var perch: Dictionary = flock.call("_find_perch", String(b["perch_id"]))
			if perch.is_empty():
				continue
			var kind := String(perch.get("kind", ""))
			kinds_seen[kind] = true
			if String(flock.call("_perch_zone", kind)) != "roof":
				continue
			roof_now += 1
			var pid2 := String(b["perch_id"])
			row_use[pid2] = int(row_use.get(pid2, 0)) + 1
		roof_max = maxi(roof_max, roof_now)
		row_max = maxi(row_max, _max_used(row_use))
	var st: Dictionary = flock.get_state_counts()
	print("[ROOF REST] ", _counts(st), " roof_max=", roof_max, " row_max=", row_max, " kinds_seen=", str(kinds_seen.keys()))
	_check(roof_max <= 2, "1800 帧内屋顶区同时占用始终 <=2（峰值 %d）" % roof_max)
	_check(row_max <= 2, "1800 帧内同一屋顶栖点从未三只同排（峰值 %d）" % row_max)
	_check(kinds_seen.size() >= 3, "多轮选点覆盖 >=3 种栖枝 kind（实际 %s）" % str(kinds_seen.keys()))
	_check(int(st["perch_conflicts"]) == 0, "白天屋顶歇脚无槽位冲突（conflicts=%d）" % int(st["perch_conflicts"]))
	_check(int(st["airborne"]) >= 1, "其余海鸥白天正常在空中/起飞降落（airborne=%d）" % int(st["airborne"]))
	flock.free()

func _stir_timers(flock, base: float) -> void:
	var i := 0
	for b_v in flock.get("_birds"):
		var b: Dictionary = b_v
		if int(b["state"]) == STATE_PERCH:
			b["timer"] = base + float(i) * 0.27
		i += 1

# ============================================================
# 7) NaN / 位置有效性
# ============================================================
func _probe_nan(cot_perches: Array) -> void:
	print("--- NAN ---")
	var flock = Fx.BirdFlock.new()
	root.add_child(flock)
	flock.setup(cot_perches)
	var bad := 0
	for i in range(600):
		flock.update_birds(DT, 8.0)
		for b_v in flock.get("_birds"):
			var b: Dictionary = b_v
			var p: Vector3 = (b["node"] as Node3D).position
			if is_nan(p.x) or is_nan(p.y) or is_nan(p.z) or p.length() > 1.0e5:
				bad += 1
	_check(bad == 0, "600 帧无 NaN/爆坐标（异常 %d）" % bad)
	flock.free()
