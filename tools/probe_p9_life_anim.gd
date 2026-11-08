extends SceneTree
## P9 / P7-FINALIZE 生活动作 —— 模型关节空间 / 世界几何 headless 探针（测量 + 断言）。
##
## 覆盖：睡觉（头-枕、膝、床垫、被子、坐床沿脚落地）、吃饭（手-碗 / 手-嘴 / 肘-肩、碗可见）、
##       坐姿/秋千坐姿几何、剪辑边界与循环。
##
## 家具几何来源：用与 cottage.gd 完全相同的位置/朝向参数调用 isle_house_props 真实资产构建函数，
## 得到未合批的床/餐桌节点；所有比较统一在 **房屋局部坐标系**（与 C_life 报告同一口径）。
##
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path D:/休闲小岛幻境/游戏工程 \
##     --script res://tools/probe_p9_life_anim.gd

const MODEL := preload("res://scripts/isle_villager_model.gd")
const COTTAGE := preload("res://scripts/cottage.gd")
const SPOTS := preload("res://scripts/isle_villager_spots.gd")
const PROPS := preload("res://scripts/isle_house_props.gd")
const MATH := preload("res://scripts/isle_math.gd")
const WORLD := preload("res://scripts/world.gd")

# 与 villager.gd 契约一致（探针显式复制，若生产常量变更这里会先红）
const BED_EDGE_INSET := 0.02
const BED_EDGE_ROOT_OFFSET := 0.085

var _holder: Node3D = null
var _cottage: Dictionary = {}
var _house: Node3D = null
var _house_inv: Transform3D = Transform3D.IDENTITY
var _graph: Dictionary = {}
var _spots: Dictionary = {}
var _model: Node3D = null
var _anim: AnimationPlayer = null

var _checks := 0
var _fails: Array = []

var _floor_local := 0.0
var _bed: Dictionary = {}
var _bed_root_local := Vector3.ZERO
var _mattress := AABB()
var _quilt_top := 0.0
var _pillows: Array = []
var _table_top := 0.0
var _table_aabb := AABB()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_holder = Node3D.new()
	_holder.name = "Holder"
	get_root().add_child(_holder)
	_cottage = COTTAGE.build(_holder)
	var root: Node3D = _cottage["root"] as Node3D
	await process_frame
	await process_frame
	_house = Node3D.new()
	_house.name = "PropHouse"
	_house.global_transform = root.global_transform
	_holder.add_child(_house)
	_house_inv = _house.global_transform.affine_inverse()

	_graph = SPOTS.build(_cottage)
	_spots = _graph["spots"]
	_bed = _spots["bed_attic"]
	_floor_local = _to_local_pos((_graph["nodes"]["bed_stand"] as Dictionary)["pos"]).y
	_build_bed_prop()
	var built: Dictionary = MODEL.create(0)
	_model = built["root"] as Node3D
	_anim = built["anim"] as AnimationPlayer
	_holder.add_child(_model)
	await process_frame
	await process_frame

	print("[LIFEANIM] ===== 真实家具几何（房屋局部，米） =====")
	print("[LIFEANIM] attic_floor_local_y=%.4f" % _floor_local)
	print("[LIFEANIM] mattress=%s top=%.4f" % [_ab(_mattress), _mattress.position.y + _mattress.size.y])
	print("[LIFEANIM] quilt_top=%.4f" % _quilt_top)
	for i in _pillows.size():
		print("[LIFEANIM] pillow[%d]=%s top=%.4f" % [i, _ab(_pillows[i]), (_pillows[i] as AABB).position.y + (_pillows[i] as AABB).size.y])
	print("[LIFEANIM] bed anchor_local=%s edge_local=%s yaw=%.3f" % [
		_f3(_bed["anchor"]), _f3(_bed["anchor_edge"]), float(_bed["yaw"])])

	_measure_stand()
	_measure_bed_sit()
	_measure_sleep()
	_measure_eat()
	_measure_eat_solver()
	_measure_swing_pose()
	_measure_clip_contract()
	_summary()

# ============================================================ 真实家具资产 =====
func _build_bed_prop() -> void:
	var ctx: Dictionary = (_cottage["root"] as Node3D).get_meta("cottage_ctx", {})
	var attic_floor := float(ctx.get("attic_floor", 3.17))
	var fl := attic_floor + 0.02
	PROPS.build(_house, "bed", Vector3(-2.00, fl, -0.90), -PI * 0.5)
	# 餐桌：cottage.gd:1860 与 spot 表同源（世界坐标约 (1.45,0.57,0.80)，yaw PI*0.5）
	PROPS.build(_house, "dining_table", Vector3(1.45, 0.57, 0.80), PI * 0.5)
	# ---- 床垫 / 被子 / 枕头（从真实资产网格取） ----
	for n in _house.find_children("*", "Node3D", true, false):
		if String(n.get_meta("prop_kind", "")) != "bed":
			continue
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			var role := String(mi.get_meta("prop_role", ""))
			var a := _aabb_local(mi)
			if role == "mattress":
				_mattress = a
			elif role == "pillow":
				_pillows.append(a)
		# 被子顶面 = 资产里 Vector3(0.92,0.060,1.10) @ (0,0.48,0.28) 的 +Y 面（house_props:698）
		var bed_xf: Transform3D = (n as Node3D).global_transform
		var quilt_world: Vector3 = bed_xf * Vector3(0.0, 0.48 + 0.030, 0.28)
		_quilt_top = _to_local_pos(quilt_world).y
	# 按房屋 z 排序：A = 靠南（z 大）/ B = 靠北
	_pillows.sort_custom(func(a, b): return (a as AABB).get_center().z > (b as AABB).get_center().z)
	# 餐桌顶面
	for n in _house.find_children("*", "Node3D", true, false):
		if String(n.get_meta("prop_kind", "")) != "dining_table":
			continue
		var first := true
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			var a2 := _aabb_local(mi)
			_table_top = maxf(_table_top, a2.position.y + a2.size.y)
			if first:
				_table_aabb = a2
				first = false
			else:
				_table_aabb = _table_aabb.merge(a2)

# ============================================================ 坐标 / 测量工具 ==
func _to_local_pos(w: Vector3) -> Vector3:
	return _house_inv * w

func _aabb_local(mi: MeshInstance3D) -> AABB:
	if mi == null or mi.mesh == null:
		return AABB()
	var box := mi.mesh.get_aabb()
	var xf: Transform3D = _house_inv * mi.global_transform
	var acc := AABB()
	var first := true
	for i in 8:
		var p: Vector3 = xf * box.get_endpoint(i)
		if first:
			acc = AABB(p, Vector3.ZERO)
			first = false
		else:
			acc = acc.expand(p)
	return acc

func _joint(name: String) -> Node3D:
	return _model.call("get_joint", name) as Node3D

func _joint_local(name: String) -> Vector3:
	var j := _joint(name)
	if j == null:
		return Vector3.ZERO
	return _to_local_pos(j.global_position)

func _mesh_local(mi: MeshInstance3D) -> AABB:
	return _aabb_local(mi)

## 精确顶点最低 y（房屋局部）。AABB 8 角点变换在旋转下会高估尺寸，头/手接触判定用它。
func _exact_min_y(mi: MeshInstance3D) -> float:
	if mi == null or mi.mesh == null or not mi.is_visible_in_tree():
		return INF
	var lo := INF
	var xf: Transform3D = _house_inv * mi.global_transform
	for si in mi.mesh.get_surface_count():
		var arr: Array = mi.mesh.surface_get_arrays(si)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for v in verts:
			lo = minf(lo, (xf * v).y)
	return lo

func _exact_min_y_subtree(j: Node3D) -> float:
	var lo := INF
	var self_mi := j as MeshInstance3D
	if self_mi != null:
		lo = minf(lo, _exact_min_y(self_mi))
	for mi in j.find_children("*", "MeshInstance3D", true, false):
		lo = minf(lo, _exact_min_y(mi))
	return lo

## 关节子树（含自身）所有网格在房屋坐标系的并集 AABB
func _subtree_local(j: Node3D) -> AABB:
	var acc := AABB()
	var first := true
	var list: Array = []
	var self_mi := j as MeshInstance3D
	if self_mi != null:
		list.append(self_mi)
	for mi in j.find_children("*", "MeshInstance3D", true, false):
		list.append(mi)
	for mi in list:
		if not mi.is_visible_in_tree():
			continue
		var a := _aabb_local(mi)
		if first:
			acc = a
			first = false
		else:
			acc = acc.merge(a)
	return acc

func _subtree_min_y(j: Node3D) -> float:
	return _subtree_local(j).position.y

func _model_local_aabb() -> AABB:
	var acc := AABB()
	var first := true
	for n in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.is_visible_in_tree() or mi.name == "Shadow":
			continue
		var a := _aabb_local(mi)
		if first:
			acc = a
			first = false
		else:
			acc = acc.merge(a)
	return acc

## 只统计房屋 x 区间内的身体网格最低 y（判断被子覆盖区内是否穿模）
func _model_min_y_in_x(x0: float, x1: float) -> float:
	var lo := INF
	for n in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.is_visible_in_tree() or mi.name == "Shadow":
			continue
		var a := _aabb_local(mi)
		if a.position.x + a.size.x < x0 or a.position.x > x1:
			continue
		lo = minf(lo, a.position.y)
	return lo

func _head_meshes() -> Array:
	var out: Array = []
	var hj := _joint("head")
	if hj == null:
		return out
	var self_mi := hj as MeshInstance3D
	if self_mi != null:
		out.append(self_mi)
	for mi in hj.find_children("*", "MeshInstance3D", true, false):
		out.append(mi)
	var hair := _joint("hair")
	if hair != null:
		for mi in hair.find_children("*", "MeshInstance3D", true, false):
			out.append(mi)
	return out

func _exact_min_y_world(j: Node3D) -> float:
	var lo := INF
	var list: Array = []
	var self_mi := j as MeshInstance3D
	if self_mi != null:
		list.append(self_mi)
	for mi in j.find_children("*", "MeshInstance3D", true, false):
		list.append(mi)
	for mi in list:
		if mi == null or mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var xf: Transform3D = mi.global_transform
		for si in mi.mesh.get_surface_count():
			var arr: Array = mi.mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for v in verts:
				lo = minf(lo, (xf * v).y)
	return lo

func _palm_r() -> Vector3:
	return _to_local_pos(_joint("hand_r").global_transform * Vector3(0.0, -0.06, 0.0))

func _mouth() -> Vector3:
	return _to_local_pos(_joint("head").global_transform * Vector3(0.0, 0.074, -0.105))

func _bowl_local() -> AABB:
	var bowl := _model.get_node_or_null("Bowl") as MeshInstance3D
	_model.call("set_bowl_visible", true)
	var a := _aabb_local(bowl)
	_model.call("set_bowl_visible", false)
	return a

func _place_root(local_pos: Vector3, local_yaw: float) -> void:
	var xf: Transform3D = _house.global_transform
	var basis := Basis(Vector3.UP, local_yaw)
	_model.global_transform = Transform3D(xf.basis * basis, xf.origin + xf.basis * local_pos)

func _seek(clip: String, t: float) -> void:
	_anim.play(clip)
	_anim.seek(t, true)

# ============================================================ 各姿势测量 =======
func _measure_stand() -> void:
	print("")
	print("== STAND / CLIP 契约 ==")
	_place_root(Vector3.ZERO, 0.0)
	_seek("idle", 0.0)
	var names: PackedStringArray = _model.call("get_animation_names")
	var track_sum := 0
	for n in _anim.get_animation_list():
		track_sum += _anim.get_animation(n).get_track_count()
	print("  clips(%d)=" % names.size(), ", ".join(names))
	print("  track_sum=", track_sum)
	var st: Dictionary = _model.call("stats")
	print("  stats meshes=%d dc=%d tris=%d height=%.3f" % [int(st["mesh_count"]), int(st["dc_estimate"]), int(st["triangles"]), float(st["height"])])
	_ok(names.size() == 15, "剪辑数 == 15（12 生活 + 3 钓鱼，P6 契约不变）", str(names.size()))
	_ok(track_sum == 345, "轨道总数 == 345（23×15）", str(track_sum))
	_ok(int(st["mesh_count"]) == 16 and int(st["dc_estimate"]) <= 40, "网格/DC 预算不变", "%d/%d" % [int(st["mesh_count"]), int(st["dc_estimate"])])
	for pair in [["eat", 3.0, true], ["lie_down", 1.0, false], ["get_up", 1.0, false], ["sleep", 6.0, true]]:
		var a := _anim.get_animation(String(pair[0]))
		_ok(a != null and absf(a.length - float(pair[1])) <= 0.001 and (a.loop_mode == Animation.LOOP_LINEAR) == bool(pair[2]),
			"剪辑契约 %s len=%.2f" % [String(pair[0]), float(pair[1])], "%.3f/%s" % [a.length if a != null else -1.0, str(a.loop_mode == Animation.LOOP_LINEAR) if a != null else "?"])

func _measure_bed_sit() -> void:
	print("")
	print("== BED_SIT（坐床沿，脚落地） ==")
	var edge: Vector3 = _to_local_pos(_bed["anchor_edge"])
	var inward := Vector3(0.0, 0.0, -1.0)  # 床宽方向：从南沿指向床心（房屋局部）
	var edge_root := edge + inward * BED_EDGE_INSET + Vector3(0.0, BED_EDGE_ROOT_OFFSET, 0.0)
	_place_root(edge_root, float(_bed["sit_yaw"]))
	_seek("bed_sit_down", _anim.get_animation("bed_sit_down").length - 0.0001)
	var sole := minf(_exact_min_y(_joint("foot_l") as MeshInstance3D), _exact_min_y(_joint("foot_r") as MeshInstance3D))
	var pel := _mesh_local(_joint("pelvis") as MeshInstance3D)
	var edge_z := _mattress.position.z + _mattress.size.z
	print("  edge_root_local=%s floor_local=%.4f" % [_f3(edge_root), _floor_local])
	print("  sole_local_y=%.4f  sole-floor=%.4f m" % [sole, sole - _floor_local])
	print("  pelvis_bottom_local=%.4f mattress_top=%.4f" % [pel.position.y, _mattress.position.y + _mattress.size.y])
	print("  pelvis_center_local=%s mattress_edge_z=%.4f inset=%.4f" % [_f3(edge_root), edge_z, edge_z - edge_root.z])
	for jn in ["hip_l", "knee_l", "foot_l"]:
		print("  rel/root %-8s = %s" % [jn, _f3(_model.global_transform.affine_inverse() * _joint(jn).global_position)])
	# 床架侧梁（house_props bed：Vector3(0.05,0.16,d-0.10) @ (±(w/2-0.025),0.27,0)）顶面 ≈ 3.19+0.35
	print("  thigh/knee 是否越过床架侧梁（顶 %.3f）：knee_z=%.3f，侧梁 z≈%.3f" % [
		_floor_local + 0.35, _to_local_pos(_joint("knee_l").global_position).z, -0.425])
	_ok(absf(sole - _floor_local) <= 0.03, "坐床沿 shoes 落地（|sole-floor|<=0.03）", "%.4f" % (sole - _floor_local))
	_ok(edge_z - edge_root.z <= 0.05, "坐点贴床沿（内缩<=0.05）", "%.4f" % (edge_z - edge_root.z))
	_ok(pel.position.y >= (_mattress.position.y + _mattress.size.y) - 0.02, "坐床沿骨盆底不陷进床垫", "%.4f" % pel.position.y)

func _bed_lie_root_local() -> Vector3:
	return _to_local_pos((_bed["anchor"] as Vector3) + Vector3(0.0, 0.02, 0.0))

func _exact_model_min_y() -> float:
	var lo := INF
	for n in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.name == "Shadow":
			continue
		lo = minf(lo, _exact_min_y(mi))
	return lo

func _joint_mesh_min_y(jn: String) -> float:
	var j := _joint(jn) as MeshInstance3D
	return _exact_min_y(j)

func _measure_sleep() -> void:
	print("")
	print("== SLEEP pose（头-枕 / 膝 / 床垫 / 被子） ==")
	_place_root(_bed_lie_root_local(), float(_bed["yaw"]))
	_seek("sleep", 0.0)
	var body_min := _exact_model_min_y()
	var head := _subtree_local(_joint("head"))
	var hj := _joint("head")
	var hc: Vector3 = _to_local_pos(hj.global_transform * MODEL.HEAD_CENTER)
	var back_pt: Vector3 = _to_local_pos(hj.global_transform * (MODEL.HEAD_CENTER + Vector3(0.0, 0.0, MODEL.HEAD_RADIUS.z)))
	var head_min := _exact_min_y_subtree(hj)
	var pillow_a: AABB = _pillows[0]
	var pillow_b: AABB = _pillows[1]
	var pa_top := pillow_a.position.y + pillow_a.size.y
	print("  root_local=%s" % _f3(_bed_lie_root_local()))
	print("  body_exact_min=%.4f mattress_top=%.4f quilt_top=%.4f" % [body_min, _mattress.position.y + _mattress.size.y, _quilt_top])
	print("  head_center=%s back_of_head=%s head_exact_min=%.4f pillowA_top=%.4f" % [_f3(hc), _f3(back_pt), head_min, pa_top])
	for i in _pillows.size():
		var p: AABB = _pillows[i]
		var dx := maxf(0.0, maxf(p.position.x - hc.x, hc.x - (p.position.x + p.size.x)))
		var dz := maxf(0.0, maxf(p.position.z - hc.z, hc.z - (p.position.z + p.size.z)))
		print("  head-vs-pillow[%d]: center_dx=%.4f dz=%.4f top=%.4f" % [i, dx, dz, p.position.y + p.size.y])
	var knee_l_y := _joint_local("knee_l").y
	var knee_r_y := _joint_local("knee_r").y
	var mt := _mattress.position.y + _mattress.size.y
	var legs_min := INF
	for jn in ["hip_l", "hip_r", "knee_l", "knee_r", "foot_l", "foot_r"]:
		legs_min = minf(legs_min, _joint_mesh_min_y(jn))
	print("  knee_l_joint_y=%.4f knee_r_joint_y=%.4f (dy_mattress: %.4f / %.4f)" % [knee_l_y, knee_r_y, knee_l_y - mt, knee_r_y - mt])
	print("  legs_exact_min=%.4f quilt_top=%.4f" % [legs_min, _quilt_top])
	print("  hip_r.rot.x=%.3f knee_r.rot.x=%.3f foot_r.rot.x=%.3f  neck=%s head=%s" % [
		(_joint("hip_r") as Node3D).rotation.x, (_joint("knee_r") as Node3D).rotation.x,
		(_joint("foot_r") as Node3D).rotation.x, str((_joint("neck") as Node3D).rotation), str((_joint("head") as Node3D).rotation)])
	print("  body_pos=", str(_joint("body_pos").position))
	var bp := _joint("body_pos")
	var ys: Array = []
	for t in [0.0, 1.5, 3.0, 4.5, 6.0]:
		_seek("sleep", t)
		ys.append(bp.position.y)
	var lo: float = 1e9
	var hi := -1e9
	for v in ys:
		lo = minf(lo, float(v))
		hi = maxf(hi, float(v))
	print("  sleep body_pos.y samples=", str(ys), " breath_span=%.4f" % (hi - lo))
	_seek("sleep", 0.0)

	# ---- 断言（C 报告 A3/A4/A2 + 新睡觉链目标）----
	var dxa := maxf(0.0, maxf(pillow_a.position.x - hc.x, hc.x - (pillow_a.position.x + pillow_a.size.x)))
	var dza := maxf(0.0, maxf(pillow_a.position.z - hc.z, hc.z - (pillow_a.position.z + pillow_a.size.z)))
	_ok(dxa <= 0.03 and dza <= 0.03, "头心落在枕头 A 枕面内（不夹两枕缝）", "dx=%.3f dz=%.3f" % [dxa, dza])
	_ok(back_pt.y >= pa_top - 0.02 and back_pt.y <= pa_top + 0.05, "后脑接触枕面（枕顶-0.02..+0.05）", "%.4f vs %.4f" % [back_pt.y, pa_top])
	_ok(pa_top - head_min <= 0.06, "头部不穿透枕头（最低点不低于枕顶 6 cm）", "%.4f" % (pa_top - head_min))
	_ok(body_min >= mt - 0.004, "身体不穿床垫（exact_min >= 床垫顶）", "%.4f vs %.4f" % [body_min, mt])
	_ok(body_min <= mt + 0.04, "背部贴床垫（离床垫顶 <= 4 cm）", "%.4f" % (body_min - mt))
	_ok(knee_r_y - mt <= 0.22, "右膝不再翘空中（膝关节离床垫 <= 0.22 m，旧值 0.313）", "%.4f" % (knee_r_y - mt))
	_ok(knee_r_y - knee_l_y <= 0.07, "右膝只比左膝微高（<= 7 cm）", "%.4f" % (knee_r_y - knee_l_y))
	_ok(legs_min >= _quilt_top - 0.02, "双腿搭在被面上不穿被子（>= 被面-2 cm）", "%.4f vs %.4f" % [legs_min, _quilt_top])
	_ok(absf((_joint("hip_r") as Node3D).rotation.x) <= 0.25 and (_joint("knee_r") as Node3D).rotation.x >= -0.40, "睡姿右腿配置已压平（hip<=0.25, knee>=-0.40）",
		"%.2f/%.2f" % [(_joint("hip_r") as Node3D).rotation.x, (_joint("knee_r") as Node3D).rotation.x])
	_ok((_joint("eyelid_l") as Node3D).rotation.x > -0.30 and (_joint("eyelid_r") as Node3D).rotation.x > -0.30, "睡姿闭眼")
	_ok(hi - lo >= 0.006, "睡姿呼吸循环（body_pos 起伏 >= 6 mm）", "%.4f" % (hi - lo))
	# 被子覆盖区内身体最低点：不得低于被面 2 cm（腿已在上面断言；躯干在无被区）
	_ok(_pillows.size() == 2, "真实资产：床有 2 颗枕头（探针识别）", str(_pillows.size()))

func _measure_eat() -> void:
	print("")
	print("== EAT pose（手-碗 / 手-嘴 / 肘-肩 / 碗在桌上） ==")
	var sp: Dictionary = _spots["eat_s"]
	_place_root(_to_local_pos((sp["anchor"] as Vector3) + Vector3(0.0, 0.02, 0.0)), float(sp["yaw"]))
	var bowl := _bowl_local()
	var bowl_rim := bowl.position.y + bowl.size.y
	print("  table_aabb=", _ab(_table_aabb), " table_top=%.4f" % _table_top)
	# 四把餐椅：碗必须真实落在桌面上（旧模型碗位在 n/s 椅悬空 4 cm）
	var bowl_chair_bad: Array = []
	for esid in ["eat_n", "eat_s", "eat_w", "eat_e"]:
		var esp: Dictionary = _spots[esid]
		_place_root(_to_local_pos((esp["anchor"] as Vector3) + Vector3(0.0, 0.02, 0.0)), float(esp["yaw"]))
		var b2 := _bowl_local()
		var bc := b2.get_center()
		var inside: bool = bc.x >= _table_aabb.position.x - 0.02 and bc.x <= _table_aabb.position.x + _table_aabb.size.x + 0.02 			and bc.z >= _table_aabb.position.z - 0.02 and bc.z <= _table_aabb.position.z + _table_aabb.size.z + 0.02
		var bottom_ok := absf(b2.position.y - _table_top) <= 0.02
		print("  BOWL@%s center=%s bottom-table=%.4f inside_table=%s" % [esid, _f3(bc), b2.position.y - _table_top, str(inside)])
		if not inside or not bottom_ok:
			bowl_chair_bad.append(esid)
	_ok(bowl_chair_bad.is_empty(), "四把餐椅碗都落在桌面上（不悬空）", str(bowl_chair_bad))
	_place_root(_to_local_pos((sp["anchor"] as Vector3) + Vector3(0.0, 0.02, 0.0)), float(sp["yaw"]))
	_ok(_bowl_visible_default_false(), "碗默认隐藏（由进食状态显式 set_bowl_visible）")

	var t := 0.0
	var min_bowl := 1e9
	var min_mouth := 1e9
	var max_elbow_dy := -1e9
	var at_mouth_elbow_dy := 99.0
	var mouth_episodes := 0
	var in_mouth := false
	var pick_episodes := 0
	var in_pick := false
	var hand_through_table := false
	while t <= 3.0001:
		_seek("eat", t)
		var hand_house := _to_local_pos(_joint("hand_r").global_transform * Vector3(0.0, -0.06, 0.0))
		var mouth_house := _to_local_pos(_joint("head").global_transform * Vector3(0.0, 0.074, -0.105))
		var sh := _to_local_pos(_joint("shoulder_r").global_position)
		var el := _to_local_pos(_joint("elbow_r").global_position)
		var bowl_c := bowl.get_center()
		var db := hand_house.distance_to(bowl_c)
		var dm := hand_house.distance_to(mouth_house)
		min_bowl = minf(min_bowl, db)
		if dm < min_mouth:
			min_mouth = dm
			at_mouth_elbow_dy = el.y - sh.y
		max_elbow_dy = maxf(max_elbow_dy, el.y - sh.y)
		if dm <= 0.10 and not in_mouth:
			mouth_episodes += 1
			in_mouth = true
		elif dm > 0.25:
			in_mouth = false
		if db <= 0.13 and not in_pick:
			pick_episodes += 1
			in_pick = true
		elif db > 0.30:
			in_pick = false
		# 手在桌面上方区域内时不得低于桌面（穿桌）
		# 桌面是 0.035 厚板：只有手掌落在“桌板厚度带”内且水平在桌面投影内才算穿桌；
		# 手放在桌下/腿上（更低）是正常坐姿，不算穿模。
		if hand_house.x >= _table_aabb.position.x and hand_house.x <= _table_aabb.position.x + _table_aabb.size.x 				and hand_house.z >= _table_aabb.position.z and hand_house.z <= _table_aabb.position.z + _table_aabb.size.z:
			if hand_house.y >= _table_top - 0.065 and hand_house.y <= _table_top + 0.005:
				hand_through_table = true
				print("    [HAND-TABLE] t=%.2f hand=%s table_top=%.3f" % [t, _f3(hand_house), _table_top])
		print("  t=%.2f hand=%s mouth_d=%.3f bowl_d=%.3f elbow_y-sho_y=%.3f head_pitch=%.3f eyelid=%.2f" % [
			t, _f3(hand_house), dm, db, el.y - sh.y, (_joint("head") as Node3D).rotation.x,
			(_joint("eyelid_l") as Node3D).rotation.x])
		t += 0.1
	print("  min hand-bowl=%.3f  min hand-mouth=%.3f (elbow-shoulder dy at that frame=%.3f)  elbow_dy_max=%.3f  mouth_episodes=%d pick_episodes=%d hand_through_table=%s" % [
		min_bowl, min_mouth, at_mouth_elbow_dy, max_elbow_dy, mouth_episodes, pick_episodes, str(hand_through_table)])
	_ok(min_bowl <= 0.13, "右手下探到碗（手-碗 <= 0.13 m）", "%.3f" % min_bowl)
	_ok(min_mouth <= 0.12, "手送到嘴边（手-嘴 <= 0.12 m）", "%.3f" % min_mouth)
	_ok(max_elbow_dy <= 0.02, "肘始终不高于肩（max(elbow_y-shoulder_y) <= 0.02）", "%.3f" % max_elbow_dy)
	_ok(mouth_episodes >= 2, "一个循环内至少两次完整送嘴（2-3 口）", str(mouth_episodes))
	_ok(pick_episodes >= 2, "一个循环内至少两次下探取食", str(pick_episodes))
	_ok(min_mouth >= 0.03, "手不穿脸（手-嘴 >= 3 cm）", "%.3f" % min_mouth)
	_ok(not hand_through_table, "手不穿桌面", str(hand_through_table))
	# 咀嚼眨眼（采样两个精确闭眼帧）
	_seek("eat", 0.74)
	var e1 := (_joint("eyelid_l") as Node3D).rotation.x
	_seek("eat", 1.66)
	var e2 := (_joint("eyelid_l") as Node3D).rotation.x
	_ok(e1 > -0.30 and e2 > -0.30, "咀嚼相位有眨眼（0.74s / 1.66s 闭眼）", "%.2f/%.2f" % [e1, e2])
	_seek("eat", 0.0)
	var p0: Dictionary = _snapshot()
	_seek("eat", 2.9999)
	var p1: Dictionary = _snapshot()
	_ok(_pose_diff(p0, p1) <= 0.02, "eat 循环首尾无缝（首尾都 _sit()）", "maxdiff=%.4f" % _pose_diff(p0, p1))

func _bowl_visible_default_false() -> bool:
	var bowl := _model.get_node_or_null("Bowl") as MeshInstance3D
	_model.call("set_bowl_visible", false)
	return bowl != null and not bowl.visible

func _measure_eat_solver() -> void:
	print("")
	print("== EAT 右臂目标求解（手-碗 / 手-嘴，含躯干/头前倾） ==")
	var sp: Dictionary = _spots["eat_s"]
	_place_root(_to_local_pos((sp["anchor"] as Vector3) + Vector3(0.0, 0.02, 0.0)), float(sp["yaw"]))
	var scenarios := [
		{"name": "pickup", "torso": Vector3(0.14, 0.0, 0.0), "neck": Vector3(-0.02, 0.0, 0.0), "head": Vector3(0.08, 0.0, 0.0), "mode": "bowl", "off": Vector3(0.050, 0.050, 0.040), "lefthand": true},
		{"name": "tomouth", "torso": Vector3(0.09, 0.0, 0.0), "neck": Vector3(0.12, -0.42, 0.02), "head": Vector3(0.10, -0.22, -0.02), "mode": "mouth", "off": Vector3(0.038, -0.035, -0.022), "lefthand": false},
		{"name": "overedge", "torso": Vector3(0.12, 0.0, 0.0), "neck": Vector3(-0.02, 0.0, 0.0), "head": Vector3(0.06, 0.0, 0.0), "mode": "fixed", "target": Vector3(0.060, 0.300, -0.170), "off": Vector3.ZERO, "lefthand": true},
		{"name": "retractlow", "torso": Vector3(0.03, 0.0, 0.0), "neck": Vector3(0.0, 0.0, 0.0), "head": Vector3(0.02, 0.0, 0.0), "mode": "fixed", "target": Vector3(0.100, 0.140, -0.030), "off": Vector3.ZERO, "lefthand": false},
		{"name": "sit_thigh", "torso": Vector3(-0.02, 0.0, 0.0), "neck": Vector3(0.0, 0.0, 0.0), "head": Vector3(-0.02, 0.0, 0.0), "mode": "fixed", "target": Vector3(0.150, 0.125, -0.080), "off": Vector3.ZERO, "lefthand": false},
		{"name": "lift2", "torso": Vector3(0.06, 0.0, 0.0), "neck": Vector3(0.0, 0.0, 0.0), "head": Vector3(0.03, 0.0, 0.0), "mode": "fixed", "target": Vector3(0.100, 0.310, -0.070), "off": Vector3.ZERO, "lefthand": false},
		{"name": "pause2", "torso": Vector3(0.05, 0.0, 0.0), "neck": Vector3(0.02, -0.20, 0.01), "head": Vector3(0.04, -0.10, 0.0), "mode": "fixed", "target": Vector3(0.100, 0.262, -0.200), "off": Vector3.ZERO, "lefthand": false},
		{"name": "lift", "torso": Vector3(0.06, 0.0, 0.0), "neck": Vector3(0.0, 0.0, 0.0), "head": Vector3(0.03, 0.0, 0.0), "mode": "fixed", "target": Vector3(0.080, 0.300, -0.040), "off": Vector3.ZERO, "lefthand": false},
		{"name": "pause_low", "torso": Vector3(0.05, 0.0, 0.0), "neck": Vector3(0.02, -0.20, 0.01), "head": Vector3(0.04, -0.10, 0.0), "mode": "fixed", "target": Vector3(0.100, 0.230, -0.200), "off": Vector3.ZERO, "lefthand": false},
	]
	for sc in scenarios:
		_seek("eat", 0.0)
		(_joint("torso") as Node3D).rotation = sc["torso"]
		(_joint("neck") as Node3D).rotation = sc["neck"]
		(_joint("head") as Node3D).rotation = sc["head"]
		var inv: Transform3D = _model.global_transform.affine_inverse()
		var bowl := _bowl_local()
		var bowl_root: Vector3 = inv * (_house.global_transform * bowl.get_center())
		var mouth_root: Vector3 = inv * (_joint("head").global_transform * Vector3(0.0, 0.074, -0.105))
		var target: Vector3
		if String(sc["mode"]) == "bowl":
			target = bowl_root + (sc["off"] as Vector3)
		elif String(sc["mode"]) == "fixed":
			target = sc["target"]
		else:
			target = mouth_root + (sc["off"] as Vector3)
		var best_d := 1e9
		var best_sx := 0.0
		var best_sy := 0.0
		var best_sz := 0.0
		var best_ex := 0.0
		var best_hx := 0.0
		var best_elbow_dy := 99.0
		for sx_i in range(0, 12):
			var sx := -0.20 + 0.20 * float(sx_i)         # -0.20..2.00（允许自然垂臂）
			for sy_i in range(0, 5):
				var sy := -0.40 + 0.20 * float(sy_i)
				for sz_i in range(0, 10):
					var sz := -0.80 + 0.133 * float(sz_i)  # -0.80..0.40
					for ex_i in range(0, 12):
						var ex := 0.0 + 0.20 * float(ex_i)    # 0.0..2.20
						for hx_i in range(0, 7):
							var hx := -0.60 + 0.20 * float(hx_i)
							(_joint("shoulder_r") as Node3D).rotation = Vector3(sx, sy, sz)
							(_joint("elbow_r") as Node3D).rotation = Vector3(ex, 0.0, 0.0)
							(_joint("hand_r") as Node3D).rotation = Vector3(hx, 0.0, 0.0)
							var palm: Vector3 = inv * (_joint("hand_r").global_transform * Vector3(0.0, -0.06, 0.0))
							var d := palm.distance_to(target)
							if d < best_d:
								best_d = d
								best_sx = sx
								best_sy = sy
								best_sz = sz
								best_ex = ex
								best_hx = hx
								best_elbow_dy = (_joint("elbow_r").global_position - _joint("shoulder_r").global_position).y
		(_joint("shoulder_r") as Node3D).rotation = Vector3(best_sx, best_sy, best_sz)
		(_joint("elbow_r") as Node3D).rotation = Vector3(best_ex, 0.0, 0.0)
		(_joint("hand_r") as Node3D).rotation = Vector3(best_hx, 0.0, 0.0)
		var got: Vector3 = inv * (_joint("hand_r").global_transform * Vector3(0.0, -0.06, 0.0))
		print("  %-10s target=%s reach=%.3f palm=%s -> shoulder_r=(%.2f,%.2f,%.2f) elbow_r.x=%.2f hand_r.x=%.2f elbow_dy=%.3f" % [
			String(sc["name"]), _f3(target), best_d, _f3(got), best_sx, best_sy, best_sz, best_ex, best_hx, best_elbow_dy])


func _measure_swing_pose() -> void:
	print("")
	print("== SWING 坐姿（座位高度 / 脚离地） ==")
	# 秋千几何与 world.gd::_swing 同源：吊点 = 大树 + (3.0, SWING_LIMB_Y, 0)，绳长 = max(2.6, pivot.y-(ground+0.55))
	var base_y := MATH.terrain_height(MATH.BIG_TREE_X, MATH.BIG_TREE_Z)
	var pivot_y := base_y + WORLD.SWING_LIMB_Y
	var sw_px := MATH.BIG_TREE_X + 3.0
	var sw_pz := MATH.BIG_TREE_Z
	var ground := MATH.terrain_height(sw_px, sw_pz)
	var rope := maxf(2.6, pivot_y - (ground + 0.55))
	var seat_top := pivot_y - rope + 0.035
	print("  pivot=(%.3f,%.3f,%.3f) rope=%.3f ground=%.3f seat_top=%.3f root=%.3f" % [sw_px, pivot_y, sw_pz, rope, ground, seat_top, seat_top + 0.02])
	_place_root(Vector3.ZERO, 0.0)
	_model.global_position = Vector3(sw_px, seat_top + 0.02, sw_pz)
	_model.global_rotation = Vector3(0.0, 0.0, 0.0)
	_seek("sit_idle", 0.0)
	var sole := minf(_exact_min_y_world(_joint("foot_l")), _exact_min_y_world(_joint("foot_r")))
	print("  sole_world_y=%.3f  ground=%.3f  clearance=%.3f" % [sole, ground, sole - ground])
	_ok(sole - ground >= 0.02 and sole - ground <= 0.30, "秋千坐姿双脚离地自然（0.02–0.30 m）", "%.3f" % (sole - ground))
	# 秋千坐姿的“座椅-根”约定：root = 座位上表面 + 0.02（与椅子坐姿同一约定）
	var seat_center := pivot_y - rope
	print("  seat_center=%.3f seat_top=%.3f root=%.3f (root-seat_top=%.3f)" % [seat_center, seat_top, seat_top + 0.02, 0.02])
	_ok(absf((seat_top + 0.02) - (seat_center + 0.035 + 0.02)) < 0.001, "秋千 root 约定 = 座面上表面 + 0.02", "%.3f" % ((seat_top + 0.02) - (seat_center + 0.055)))

# ============================================================ 剪辑边界 =======
func _snapshot() -> Dictionary:
	var out := {}
	for key in ["body_pos", "body_roll", "body_tilt", "pelvis", "torso", "neck", "head", "hair",
			"shoulder_l", "shoulder_r", "elbow_l", "elbow_r", "hand_l", "hand_r",
			"hip_l", "hip_r", "knee_l", "knee_r", "foot_l", "foot_r", "eyelid_l", "eyelid_r"]:
		var j := _joint(key)
		if j != null:
			out[key] = j.transform
	return out

func _pose_diff(a: Dictionary, b: Dictionary) -> float:
	var worst := 0.0
	for key in a:
		if not b.has(key):
			continue
		var ta: Transform3D = a[key]
		var tb: Transform3D = b[key]
		worst = maxf(worst, ta.origin.distance_to(tb.origin))
		for axis in 3:
			worst = maxf(worst, absf(ta.basis[axis].angle_to(tb.basis[axis])))
	return worst

func _measure_clip_contract() -> void:
	print("")
	print("== 剪辑边界（新睡觉链） ==")
	# 坐床沿 → 搬腿上床 → 躺平 → 落枕 → 睡姿：都在 lie_down（1.0s）内表达
	var pairs := [
		["bed_sit_down", "lie_down", true, "坐床沿末帧 == lie_down 首帧"],
		["lie_down", "sleep", true, "lie_down 末帧 == sleep 首帧"],
		["get_up", "sleep", false, "get_up 首帧 == sleep 首帧（醒来从睡姿开始）"],
		["get_up", "bed_sit_up", true, "get_up 末帧 == bed_sit_up 首帧（坐起在床沿）"],
		["bed_sit_down", "idle", false, "坐床沿首帧 == 站立首帧"],
		["bed_sit_up", "idle", true, "床沿起身末帧 == 站立首帧"],
	]
	for p in pairs:
		_anim.play(String(p[0]))
		var lena := _anim.get_animation(String(p[0])).length
		_anim.seek(lena - 0.0001 if bool(p[2]) else 0.0, true)
		var pa: Dictionary = _snapshot()
		_anim.play(String(p[1]))
		_anim.seek(0.0, true)
		var pb: Dictionary = _snapshot()
		var d := _pose_diff(pa, pb)
		_ok(d <= 0.02, String(p[3]), "maxdiff=%.4f" % d)
	for clip in ["idle", "idle_alt", "sit_idle", "eat", "sleep"]:
		_anim.play(clip)
		_anim.seek(0.0, true)
		var p0: Dictionary = _snapshot()
		_anim.seek(_anim.get_animation(clip).length - 0.0001, true)
		var p1: Dictionary = _snapshot()
		_ok(_pose_diff(p0, p1) <= 0.02, "loop 首尾无缝: " + clip, "maxdiff=%.4f" % _pose_diff(p0, p1))

# ============================================================ 输出 ===========
func _f3(v: Vector3) -> String:
	return "(%.3f,%.3f,%.3f)" % [v.x, v.y, v.z]

func _ab(a: AABB) -> String:
	return "pos(%.3f,%.3f,%.3f) size(%.3f,%.3f,%.3f)" % [a.position.x, a.position.y, a.position.z, a.size.x, a.size.y, a.size.z]

func _ok(cond: bool, label: String, detail: String = "") -> void:
	_checks += 1
	if cond:
		print("[LIFEANIM] PASS " + label + ("  (" + detail + ")" if detail != "" else ""))
	else:
		print("[LIFEANIM] FAIL " + label + ("  (" + detail + ")" if detail != "" else ""))
		_fails.append(label + (" | " + detail if detail != "" else ""))

func _summary() -> void:
	print("")
	print("[LIFEANIM] RESULT %d/%d passed, %d failed" % [_checks - _fails.size(), _checks, _fails.size()])
	for f in _fails:
		print("[LIFEANIM] FAILED: " + String(f))
	quit(0 if _fails.is_empty() else 1)
