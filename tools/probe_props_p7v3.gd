extends SceneTree
## P7-V3 家具库 headless 自检（task-4 / G 阶段）
## 覆盖：25 类家具 build 契约、footprint/height 声明一致性、几何非方块堆（部件数/尺寸/包围盒）、
##       NaN/节点命名冲突/材质共享（不泄漏）、描边覆盖、无 Light3D、重复 build 与释放回收。
## 运行：
##   "D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe" --headless ##     --path "D:/休闲小岛幻境/游戏工程" --script res://tools/probe_props_p7v3.gd

const PROPS := preload("res://scripts/isle_house_props.gd")

# 任务要求的 24 类（floor_lamp 为本库额外补充，服务 lead 的落地灯机位）
const REQUIRED := [
	"doormat", "coat_rack", "shoe_bench", "dining_table", "chair", "sofa", "armchair",
	"coffee_table", "rug", "bookshelf", "sideboard", "tall_cupboard", "bed", "nightstand",
	"wardrobe", "desk", "reading_chair", "side_table", "wall_clock", "picture_frame",
	"table_lamp", "curtain", "firewood_basket", "plant_pot",
]
const WALL_KINDS := ["coat_rack", "wall_clock", "picture_frame", "curtain"]

var checks := 0
var fails := 0
var stage: Node3D = null
var round1: Dictionary = {}     # kind -> {node, footprint, height, parts, meshes}
var round1_mats: Dictionary = {} # instance_id -> true
var round1_mesh_count := 0

func _initialize() -> void:
	print("=== probe_props_p7v3: 家具库契约/几何/材质 headless 自检 ===")
	await process_frame
	_check_kind_registry()
	_build_round1()
	await _second_round()
	await _free_round()
	_extra_contract_checks()
	_report()

# ------------------------------------------------------------
func _check(cond: bool, msg: String) -> void:
	checks += 1
	if cond:
		print("  [PASS] ", msg)
	else:
		fails += 1
		print("  [FAIL] ", msg)

func _report() -> void:
	print("[PROPS] RESULT fail=%d checks=%d round1_meshes=%d materials=%d" % [fails, checks, round1_mesh_count, round1_mats.size()])
	quit(0 if fails == 0 else 1)

func _check_kind_registry() -> void:
	print("--- 1) kind 清单与尺寸契约 ---")
	var ks: Array = PROPS.kinds()
	_check(ks.size() >= 18, "kind 数量 >= 18（实际 %d）" % ks.size())
	var missing: Array = []
	for k in REQUIRED:
		if not PROPS.has_kind(k):
			missing.append(k)
	_check(missing.is_empty(), "任务要求 24 类全部实现（缺：%s）" % str(missing))
	_check(PROPS.has_kind("floor_lamp"), "额外提供 floor_lamp（落地灯）")
	var wall_ok := true
	for k in ks:
		var w: bool = PROPS.is_wall_mounted(k)
		if w != WALL_KINDS.has(String(k)):
			wall_ok = false
	_check(wall_ok, "墙挂 kind 标记正确（%s）" % str(WALL_KINDS))
	var dim_ok := true
	var dim_msg := ""
	for k in ks:
		var d: Vector3 = PROPS.dims(k)
		if not (d.x > 0.0 and d.y > 0.0 and d.z > 0.0) or not d.is_finite():
			dim_ok = false
			dim_msg += "%s=%s; " % [k, str(d)]
	_check(dim_ok, "每个 kind 的 DIMS 均为有限正值（%s）" % dim_msg)
	# 与计划 §12 尺寸表对照（允许 ±0.02）
	var plan := {
		"dining_table": Vector2(1.60, 0.95), "chair": Vector2(0.46, 0.46),
		"sofa": Vector2(1.80, 0.85), "coffee_table": Vector2(1.10, 0.55),
		"rug": Vector2(2.60, 1.90), "bookshelf": Vector2(0.95, 0.32),
		"sideboard": Vector2(1.20, 0.42), "tall_cupboard": Vector2(0.90, 0.44),
		"bed": Vector2(1.40, 2.05), "nightstand": Vector2(0.45, 0.40),
		"wardrobe": Vector2(1.25, 0.60), "desk": Vector2(1.70, 0.90),
		"side_table": Vector2(0.45, 0.45),
	}
	var plan_msg := ""
	for k in plan.keys():
		var fp: Vector2 = PROPS.footprint_of(k)
		var want: Vector2 = plan[k]
		if absf(fp.x - want.x) > 0.02 or absf(fp.y - want.y) > 0.02:
			plan_msg += "%s=%s(want %s); " % [k, str(fp), str(want)]
	_check(plan_msg.is_empty(), "计划 §12 关键占地尺寸一致（%s）" % plan_msg)
	print("  kinds=%s" % str(ks))

func _make_stage() -> void:
	var root3d := Node3D.new()
	root3d.name = "PropsStage"
	get_root().add_child(root3d)
	stage = Node3D.new()
	stage.name = "Stage"
	root3d.add_child(stage)

func _build_round1() -> void:
	print("--- 2) 首轮 build：返回契约 / 部件数 / 包围盒 / 描边 / 灯 ---")
	_make_stage()
	var ks: Array = PROPS.kinds()
	for k in ks:
		var kind := String(k)
		var base: Vector3 = PROPS.dims(kind)
		var pos := Vector3(1.0, 0.55, -2.0)
		var yaw := 0.37
		var res: Dictionary = PROPS.build(stage, kind, pos, yaw)
		var ok := res.has("node") and res.has("footprint") and res.has("height") and res.has("kind")
		var node: Node3D = res.get("node", null)
		if not ok or node == null:
			_check(false, "%s: 返回字典含 node/footprint/height/kind" % kind)
			continue
		var fp: Vector2 = res["footprint"]
		var h: float = float(res["height"])
		var parts := node.get_child_count()
		var meshes := _count_meshes(node)
		var aabb := _aabb_of(node)
		var mats: Dictionary = {}
		var outline_bad: Array = []
		var glow_count := 0
		var lit_count := 0
		for c in node.get_children():
			if not (c is MeshInstance3D):
				continue
			var mi := c as MeshInstance3D
			if String(mi.name).begins_with("Glow"):
				glow_count += 1
				continue
			if mi.mesh == null:
				outline_bad.append("nullmesh")
			var mat: Material = mi.material_override
			if mat == null:
				outline_bad.append(String(mi.name) + ":nomat")
				continue
			mats[mat.get_instance_id()] = true
			if mat is ShaderMaterial:
				if (mat as ShaderMaterial).next_pass == null:
					outline_bad.append(String(mi.name) + ":no_outline")
				var self_lit: Variant = (mat as ShaderMaterial).get_shader_parameter("self_lit")
				if self_lit is float and float(self_lit) > 0.5:
					lit_count += 1
			round1_mats[mat.get_instance_id()] = true
		round1_mesh_count += meshes

		var msg := "%s: parts=%d meshes=%d fp=(%.2f,%.2f) h=%.3f" % [kind, parts, meshes, fp.x, fp.y, h]
		var cond_ret: bool = res["kind"] == kind and fp.is_finite() and h > 0.0 and h < 3.0
		_check(cond_ret, msg + " 返回数值有效")
		_check(parts >= 3, "%s: 部件数 >= 3（实际 %d，不是单一方块）" % [kind, parts])
		_check(meshes >= 4, "%s: 网格数 >= 4（实际 %d）" % [kind, meshes])
		_check((node.position - pos).length() < 1e-5, "%s: 原点=pos" % kind)
		_check(absf(node.rotation.y - yaw) < 1e-5, "%s: 朝向 yaw=%.3f" % [kind, yaw])
		_check(String(node.name).begins_with("Prop_%s_" % kind), "%s: 节点命名 Prop_<kind>_<seq>（%s）" % [kind, node.name])
		_check(node.get_meta("prop_kind", "") == kind, "%s: 元数据 prop_kind 正确" % kind)
		_check(fp.is_equal_approx(Vector2(base.x, base.y)), "%s: footprint 与 DIMS 一致" % kind)
		_check(absf(h - base.z) < 1e-4, "%s: height 与 DIMS 一致（%.3f vs %.3f）" % [kind, h, base.z])
		_check(outline_bad.is_empty(), "%s: 所有实体部件带 0.02 描边（异常：%s）" % [kind, str(outline_bad.slice(0, 4))])
		_check(_has_light3d(node) == false, "%s: 不含 Light3D（光源由 main.gd 注册）" % kind)
		var wall := PROPS.is_wall_mounted(kind)
		var ab_chk := _check_aabb(kind, wall, fp, h, aabb)
		_check(ab_chk["ok"], "%s: 包围盒不超声明占地/高度（%s）" % [kind, ab_chk["msg"]])
		if kind == "table_lamp" or kind == "floor_lamp":
			_check(lit_count >= 1, "%s: 含自发光灯罩（self_lit 部件 %d）" % [kind, lit_count])
		round1[kind] = {"node": node, "footprint": fp, "height": h, "parts": parts, "meshes": meshes, "mats": mats, "glow": glow_count}
	print("  首轮完成：kinds=%d meshes=%d materials=%d" % [round1.size(), round1_mesh_count, round1_mats.size()])

func _check_aabb(kind: String, wall: bool, fp: Vector2, h: float, aabb: AABB) -> Dictionary:
	if aabb.size == Vector3.ZERO:
		return {"ok": false, "msg": "空包围盒"}
	var tol := 0.03
	var parts: Array = []
	var ok := true
	var hw := fp.x * 0.5
	var hd := fp.y * 0.5
	if absf(aabb.position.x) > hw + tol or absf(aabb.end.x) > hw + tol:
		ok = false
		parts.append("x[%.3f,%.3f] 超 ±%.3f" % [aabb.position.x, aabb.end.x, hw])
	if wall:
		if aabb.position.z < -tol or aabb.end.z > fp.y + tol:
			ok = false
			parts.append("z[%.3f,%.3f] 超 [0,%.3f]" % [aabb.position.z, aabb.end.z, fp.y])
		if kind == "curtain":
			if aabb.position.y < -h - tol or aabb.end.y > 0.06:
				ok = false
				parts.append("y[%.3f,%.3f] 超 [-%.3f,0.06]" % [aabb.position.y, aabb.end.y, h])
		else:
			if aabb.position.y < -h * 0.5 - tol or aabb.end.y > h * 0.5 + tol:
				ok = false
				parts.append("y[%.3f,%.3f] 超 ±%.3f" % [aabb.position.y, aabb.end.y, h * 0.5])
	else:
		if aabb.position.y < -tol:
			ok = false
			parts.append("min_y=%.3f < 0" % aabb.position.y)
		if aabb.end.y > h + tol:
			ok = false
			parts.append("max_y=%.3f > %.3f" % [aabb.end.y, h])
	if absf(aabb.position.z) > hd + tol or absf(aabb.end.z) > hd + tol:
		if not wall:
			ok = false
			parts.append("z[%.3f,%.3f] 超 ±%.3f" % [aabb.position.z, aabb.end.z, hd])
	if ok:
		return {"ok": true, "msg": "ok"}
	var jmsg := ""
	for p in parts:
		if jmsg != "":
			jmsg += "；"
		jmsg += String(p)
	return {"ok": false, "msg": jmsg}

func _second_round() -> void:
	print("--- 3) 重复 build：命名不冲突 / 材质不泄漏 / 网格数线性 ---")
	var before_nodes := stage.get_child_count()
	var before_meshes := _count_meshes(stage)
	var before_mats: Dictionary = {}
	for id in round1_mats.keys():
		before_mats[id] = true
	var ks: Array = PROPS.kinds()
	for k in ks:
		PROPS.build(stage, String(k), Vector3(2.0, 0.55, -3.0), -0.21)
	await process_frame
	var after_nodes := stage.get_child_count()
	var after_meshes := _count_meshes(stage)
	_check(after_nodes == before_nodes * 2, "第二次 build 后节点数翻倍（%d -> %d）" % [before_nodes, after_nodes])
	_check(after_meshes == before_meshes * 2, "第二次 build 后网格数翻倍（%d -> %d）" % [before_meshes, after_meshes])
	# 名字唯一
	var names: Dictionary = {}
	var dup: Array = []
	for c in stage.get_children():
		var nm := String(c.name)
		if names.has(nm):
			dup.append(nm)
		names[nm] = true
	_check(dup.is_empty(), "所有家具节点名唯一（重复：%s）" % str(dup))
	# 材质集合不新增（共享 isle_math 材质缓存）
	var after_mats: Dictionary = {}
	for c in stage.get_children():
		if not (c is Node3D):
			continue
		for g in (c as Node3D).get_children():
			if not (g is MeshInstance3D):
				continue
			var gm := g as MeshInstance3D
			if String(gm.name).begins_with("Glow") or gm.material_override == null:
				continue
			after_mats[gm.material_override.get_instance_id()] = true
	var new_mats: Array = []
	for id in after_mats.keys():
		if not before_mats.has(id):
			new_mats.append(id)
	_check(new_mats.is_empty(), "重复 build 未新增材质实例（新增 %d）" % new_mats.size())
	# NaN 检查（第二次全量遍历）
	var nan_bad: Array = []
	for c in stage.get_children():
		_collect_nan(c, nan_bad)
	_check(nan_bad.is_empty(), "全舞台无 NaN/Inf 变换（异常 %d 个）" % nan_bad.size())
	if not nan_bad.is_empty():
		print("    NaN 节点：", str(nan_bad.slice(0, 8)))

func _free_round() -> void:
	print("--- 4) 释放回收 ---")
	for c in stage.get_children():
		c.queue_free()
	await process_frame
	await process_frame
	_check(stage.get_child_count() == 0, "释放后舞台子节点归零（%d）" % stage.get_child_count())

func _extra_contract_checks() -> void:
	print("--- 5) 入参与可选覆盖 ---")
	# 未知 kind 返回空字典
	var bad: Dictionary = PROPS.build(stage, "no_such_kind", Vector3.ZERO)
	_check(bad.is_empty(), "未知 kind 返回空字典且不崩")
	# width/depth/height 覆盖
	var base: Vector3 = PROPS.dims("dining_table")
	var r: Dictionary = PROPS.build(stage, "dining_table", Vector3(3.0, 0.55, 3.0), 0.0, {"width": 2.0, "depth": 1.1, "height": 0.8})
	var n: Node3D = r.get("node", null)
	var fp_ov: Vector2 = r.get("footprint", Vector2.ZERO)
	_check(n != null and fp_ov.is_equal_approx(Vector2(2.0, 1.1)) and absf(float(r["height"]) - 0.8) < 1e-4, "width/depth/height 覆盖生效（fp=%s h=%.2f）" % [str(fp_ov), float(r.get("height", 0.0))])
	if n != null:
		_check(n.scale.is_equal_approx(Vector3(2.0 / base.x, 0.8 / base.z, 1.1 / base.y)), "覆盖通过节点缩放实现（scale=%s）" % str(n.scale))
	# color / cushion 覆盖
	var r2: Dictionary = PROPS.build(stage, "sofa", Vector3(-3.0, 0.55, 3.0), 0.0, {"color": Color("331100"), "cushion": Color("336699")})
	_check(r2.get("node", null) != null, "color/cushion 覆盖不报错")
	# rot 覆盖
	var r3: Dictionary = PROPS.build(stage, "picture_frame", Vector3(0.0, 2.0, 0.0), 0.0, {"rot": Vector3(0.0, PI * 0.5, 0.0)})
	var n3: Node3D = r3.get("node", null)
	_check(n3 != null and absf((n3 as Node3D).rotation.y - PI * 0.5) < 1e-4, "rot 覆盖整体欧拉角")
	for c in stage.get_children():
		c.queue_free()
	await process_frame

# ------------------------------------------------------------
func _count_meshes(n: Node) -> int:
	var cnt := 0
	for c in n.get_children():
		if c is MeshInstance3D:
			cnt += 1
		cnt += _count_meshes(c)
	return cnt

func _has_light3d(n: Node) -> bool:
	for c in n.get_children():
		if c is Light3D:
			return true
		if _has_light3d(c):
			return true
	return false

func _collect_nan(n: Node, out: Array) -> void:
	if n is Node3D:
		var n3 := n as Node3D
		var bad := false
		for v in [n3.position, n3.rotation, n3.scale]:
			var vv: Vector3 = v
			if not (is_finite(vv.x) and is_finite(vv.y) and is_finite(vv.z)):
				bad = true
		if bad:
			out.append(String(n.name))
	for c in n.get_children():
		_collect_nan(c, out)

## 把 prop 节点下所有实体网格（排除 Glow 光晕）的局部包围盒合并到 prop 局部坐标。
func _aabb_of(prop: Node3D) -> AABB:
	var mn := Vector3(INF, INF, INF)
	var mx := Vector3(-INF, -INF, -INF)
	var found := false
	for c in prop.get_children():
		if not (c is MeshInstance3D):
			continue
		var mi := c as MeshInstance3D
		if String(mi.name).begins_with("Glow") or mi.mesh == null:
			continue
		var bb: AABB = mi.get_aabb()
		var xf: Transform3D = mi.transform
		for i in range(8):
			var corner := bb.position + Vector3(
				bb.size.x * (1.0 if (i & 1) != 0 else 0.0),
				bb.size.y * (1.0 if (i & 2) != 0 else 0.0),
				bb.size.z * (1.0 if (i & 4) != 0 else 0.0))
			var p := xf * corner
			mn = mn.min(p)
			mx = mx.max(p)
			found = true
	if not found:
		return AABB()
	return AABB(mn, mx - mn)
