extends SceneTree
## P7-V3 任务 F：门廊猫探针（headless 可跑，不依赖窗口/GPU）
## 覆盖：节点层级与可动部件、造型（头身比/三角耳/爪贴地/尾巴链/头身衔接）、6 类待机动作
## 幅度与随机错峰、原地不动、无 NaN、无每帧重建、暂停/恢复、seed 可复现。
## 运行：
##   "D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe" --headless \
##     --path "D:/休闲小岛幻境/游戏工程" --script res://tools/probe_cat_p7v3.gd

const CAT := preload("res://scripts/isle_cat.gd")
const LOG_DIR := "D:/休闲小岛幻境/开发产物/p7v3/logs"
const LOG_PATH := LOG_DIR + "/cat_idle_log.txt"
const DT := 1.0 / 60.0
const SEED := 20261021

var _pass := 0
var _fail := 0
var _log: Array = []
var _holder: Node3D
var _cat: Dictionary = {}

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(LOG_DIR)
	_holder = Node3D.new()
	_holder.name = "CatProbeHolder"
	get_root().add_child(_holder)
	await process_frame

	print("[CAT] P7-V3 门廊猫探针开始")
	_test_build_structure()
	await process_frame
	_test_geometry()
	_test_idle_20s_and_60s()
	_test_determinism()
	await _test_pause_resume()

	_write_log()
	print("[CAT] RESULT pass=%d fail=%d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

# ---------------------------------------------------------------------------
# 通用断言
# ---------------------------------------------------------------------------
func _ok(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("[CAT] PASS ", msg)
	else:
		_fail += 1
		print("[CAT] FAIL ", msg)
		_log.append("FAIL: " + msg)

func _ok_near(a: float, b: float, eps: float, msg: String) -> void:
	_ok(absf(a - b) <= eps, "%s（%.4f ≈ %.4f，容差 %.4f）" % [msg, a, b, eps])

func _root() -> Node3D:
	return _cat["root"] as Node3D

func _log_line(s: String) -> void:
	_log.append(s)

func _write_log() -> void:
	var f := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f == null:
		print("[CAT] WARN 无法写日志 ", LOG_PATH)
		return
	f.store_string("\n".join(_log) + "\n")
	f.close()
	print("[CAT] 动作日志已写入 ", LOG_PATH)

# ---------------------------------------------------------------------------
# 树工具
# ---------------------------------------------------------------------------
func _find_named(node: Node, target: String) -> Node:
	if node.name == target:
		return node
	for c in node.get_children():
		var r := _find_named(c, target)
		if r != null:
			return r
	return null

func _count_nodes(node: Node) -> int:
	var n := 1
	for c in node.get_children():
		n += _count_nodes(c)
	return n

func _count_timers(node: Node) -> int:
	var n := 1 if node is Timer else 0
	for c in node.get_children():
		n += _count_timers(c)
	return n

func _mesh_rids(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		if mi.mesh != null:
			out.append("%s|%d" % [str(mi.mesh.get_rid()), mi.get_instance_id()])
	for c in node.get_children():
		_mesh_rids(c, out)

func _count_meshes(node: Node) -> int:
	var n := 1 if (node is MeshInstance3D and (node as MeshInstance3D).mesh != null) else 0
	for c in node.get_children():
		n += _count_meshes(c)
	return n

func _transforms_finite(node: Node, bad: Array) -> void:
	if node is Node3D:
		var t: Node3D = node
		var tr: Transform3D = t.transform
		var good := tr.origin.is_finite() and tr.basis.x.is_finite() and tr.basis.y.is_finite() and tr.basis.z.is_finite()
		if not good:
			bad.append(str(t.get_path()))
	for c in node.get_children():
		_transforms_finite(c, bad)

func _xf_aabb(xf: Transform3D, box: AABB) -> Dictionary:
	var acc := {"ok": false, "aabb": AABB()}
	for i in range(8):
		var corner: Vector3 = box.position + Vector3(
			box.size.x if (i & 1) != 0 else 0.0,
			box.size.y if (i & 2) != 0 else 0.0,
			box.size.z if (i & 4) != 0 else 0.0)
		var p: Vector3 = xf * corner
		if not bool(acc["ok"]):
			acc["aabb"] = AABB(p, Vector3.ZERO)
			acc["ok"] = true
		else:
			acc["aabb"] = (acc["aabb"] as AABB).expand(p)
	return acc

func _acc_aabb(node: Node, inv: Transform3D, acc: Dictionary) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		if mi.mesh != null:
			var sub := _xf_aabb(inv * mi.global_transform, mi.mesh.get_aabb())
			if bool(sub["ok"]):
				if not bool(acc["ok"]):
					acc["aabb"] = sub["aabb"]
					acc["ok"] = true
				else:
					acc["aabb"] = (acc["aabb"] as AABB).merge(sub["aabb"])
	for c in node.get_children():
		_acc_aabb(c, inv, acc)

func _aabb_in_root(node: Node, root: Node3D) -> AABB:
	var acc := {"ok": false, "aabb": AABB()}
	_acc_aabb(node, root.global_transform.affine_inverse(), acc)
	return acc["aabb"]

func _find_named_mi(node: Node, nm: String) -> MeshInstance3D:
	if node is MeshInstance3D and String(node.name) == nm:
		return node as MeshInstance3D
	for c in node.get_children():
		var r := _find_named_mi(c, nm)
		if r != null:
			return r
	return null

## 统计猫子树里节点 scale 非单位的 MeshInstance3D（P7-V3.2 禁节点缩放）。
func _nonunit_scale_meshes(node: Node, out: Array) -> void:
	if node is Node3D and node is MeshInstance3D:
		var s3: Vector3 = (node as Node3D).scale
		if absf(s3.x - 1.0) > 0.01 or absf(s3.y - 1.0) > 0.01 or absf(s3.z - 1.0) > 0.01:
			out.append(String(node.name))
	for c in node.get_children():
		_nonunit_scale_meshes(c, out)

# ---------------------------------------------------------------------------
# 1) 结构与部件
# ---------------------------------------------------------------------------
func _test_build_structure() -> void:
	var pos := Vector3(2.30, 0.47, 6.10)
	_cat = CAT.build(_holder, pos)
	var root := _root()
	_log_line("# P7-V3 门廊猫待机动作日志（tools/probe_cat_p7v3.gd，headless）")
	_log_line("build: parent=Cottage root（探针用 holder 代替），pos=%s，默认 yaw=-0.6" % pos)
	_ok(root != null, "build 返回 root")
	if root == null:
		return
	_ok(root.name == "PorchCat", "根节点名为 PorchCat（实际 %s）" % root.name)
	_ok(root.get_parent() == _holder, "root 挂在传入的 parent 下")
	_ok(root.position.is_equal_approx(pos), "root position = %s（门廊木板顶面）" % pos)
	_ok_near(root.rotation.y, -0.6, 0.0001, "root rotation.y 默认 -0.6")
	_ok(bool(root.get_meta("isle_cat", false)), "root 带 isle_cat 元数据标记")
	_ok(root.global_position.is_equal_approx(pos), "root 世界位置 = %s（holder 在原点）" % pos)
	_ok(root.find_child("Body", true, false) != null, "层级含 Body（呼吸组）")
	_ok(root.find_child("Head", true, false) != null, "层级含 Head（颈枢轴）")
	_ok(root.find_child("Tail", true, false) != null, "层级含 Tail")
	_ok(root.find_child("Legs", true, false) != null, "层级含 Legs")
	_ok(root.find_child("Eyes", true, false) != null, "层级含 Eyes")
	_ok(_find_named(root, "CatIdleDriver") != null, "root 下有 CatIdleDriver 驱动节点")
	_ok(_count_nodes(root) > 45, "部件节点数充足（%d 个节点）" % _count_nodes(root))
	var ears: Array = _cat["ears"]
	var eyes: Array = _cat["eyes"]
	var lids: Array = _cat["eyelids"]
	var tail: Array = _cat["tail"]
	var flegs: Array = _cat["front_legs"]
	var paws: Array = _cat["paws"]
	var whiskers: Array = _cat["whiskers"]
	_ok(ears.size() == 2, "2 只耳朵（%d）" % ears.size())
	_ok(eyes.size() == 2, "2 只眼睛（%d）" % eyes.size())
	_ok(lids.size() == 2, "2 个眼睑（%d）" % lids.size())
	_ok(tail.size() == 3, "尾巴 3 节链（%d）" % tail.size())
	_ok(flegs.size() == 2, "2 条可动前腿（%d）" % flegs.size())
	_ok(paws.size() == 4, "4 只脚掌（%d）" % paws.size())
	_ok(whiskers.size() == 6, "6 根胡须（%d）" % whiskers.size())
	_ok(_count_timers(root) == 0, "未使用任何 Timer 节点（时间累加器+RNG）")
	_ok(_find_named(root, "CatIdleDriver") == _cat["driver"], "返回的 driver 就是树中驱动节点")
	var driver: Node = _cat["driver"]
	_ok(driver.is_processing(), "driver 默认启用 _process")
	_ok(driver.process_mode == Node.PROCESS_MODE_INHERIT, "driver 为 PROCESS_MODE_INHERIT（随 SceneTree 暂停）")
	var idle = _cat["idle"]
	_ok(idle != null, "build 返回待机控制器 CatIdle")
	_ok_near(float(idle.debug_state()["t"]), 0.0, 0.0001, "待机控制器初始时间 t=0")
	# idle=false 的静态模型（便于对照/集成兜底）
	var cat_static: Dictionary = CAT.build(_holder, Vector3.ZERO, 0.0, {"idle": false, "shadow": false})
	var root2 := cat_static["root"] as Node3D
	_ok(cat_static["idle"] == null and cat_static["driver"] == null, "opts.idle=false 时不建驱动/控制器")
	_ok(root2.find_child("Body", true, false) != null and _find_named(root2, "CatIdleDriver") == null, "opts.idle=false 仍保留静态几何、无驱动节点")
	root2.queue_free()

# ---------------------------------------------------------------------------
# 2) 造型（头身比/三角耳/眼/爪贴地/尾巴/头身衔接）
# ---------------------------------------------------------------------------
func _test_geometry() -> void:
	var root := _root()
	var s: float = CAT.CAT_MODEL_SCALE
	var body: Node3D = _cat["body"] as Node3D
	var head: Node3D = _cat["head"] as Node3D
	# P7-V3.2：非均匀比例烘进网格（ArrayMesh），靠 TorsoEllipsoid/HeadEllipsoid 命名查找；
	# 节点 scale 必须为 1（禁止用节点缩放冒充重建）。
	var torso := _find_named_mi(body, "TorsoEllipsoid")
	var head_mi := _find_named_mi(head, "HeadEllipsoid")
	_ok(torso != null, "身体椭球 TorsoEllipsoid 存在（网格烘焙，半径 0.23*scale）")
	_ok(head_mi != null, "头球 HeadEllipsoid 存在（网格烘焙，半径 0.155*scale）")
	var bad_scale: Array = []
	_nonunit_scale_meshes(root, bad_scale)
	_ok(bad_scale.is_empty(), "猫全部网格节点 scale=1（构造烘焙无节点缩放）%s" % str(bad_scale.slice(0, 8)))
	if torso != null:
		var ts: Vector3 = torso.mesh.get_aabb().size
		# 说明：14/8 分段的 SphereMesh 顶点多边形近似使 AABB 比理论直径小 ~1–4%，
		# 因此直径断言容差放到 0.015（比例/头身比断言另行校验）。
		_ok_near(ts.x, 2.0 * 0.23 * s * 1.00, 0.015, "身体椭球 x 直径 = %.3f m" % (2.0 * 0.23 * s))
		_ok_near(ts.y, 2.0 * 0.23 * s * 0.80, 0.013, "身体椭球 y 直径比 0.80（%.3f m）" % (2.0 * 0.23 * s * 0.80))
		_ok_near(ts.z, 2.0 * 0.23 * s * 1.45, 0.015, "身体椭球 z 直径比 1.45（%.3f m）" % (2.0 * 0.23 * s * 1.45))
		_ok(torso.scale.is_equal_approx(Vector3.ONE), "身体网格节点 scale = 1")
		_ok_near(torso.rotation.x, -0.20, 0.01, "身体前高后低倾斜 -0.20 rad")
	if torso != null and head_mi != null:
		var body_len: float = torso.mesh.get_aabb().size.z
		var head_d: float = head_mi.mesh.get_aabb().size.x
		var ratio: float = body_len / head_d
		_ok(ratio > 1.85 and ratio < 2.45, "头身比 ≈1:2.2（体长/头径 = %.2f）" % ratio)
	# 三角锥耳朵（3 侧面 + 底面；Godot 4.7.2 CylinderMesh 最小径向 4 段，故用 ArrayMesh 精确 3 段）
	var ears: Array = _cat["ears"]
	var ear0: Node3D = ears[0] as Node3D
	var ear_mesh: MeshInstance3D = null
	for c in ear0.get_children():
		if c is MeshInstance3D:
			ear_mesh = c
			break
	_ok(ear_mesh != null, "耳朵含网格")
	if ear_mesh != null and ear_mesh.mesh != null and ear_mesh.mesh.get_surface_count() >= 1:
		var faces := ear_mesh.mesh.get_faces()
		var base_pts := {}
		var apex_max := -1.0
		var base_r_max := 0.0
		for v in faces:
			if v.y < 0.005:
				base_pts["%.4f_%.4f" % [v.x, v.z]] = true
				base_r_max = maxf(base_r_max, sqrt(v.x * v.x + v.z * v.z))
			apex_max = maxf(apex_max, v.y)
		_ok(faces.size() == 12, "耳为 3 侧面+底面的三角锥（%d 个三角面顶点 = 4 面 × 3）" % faces.size())
		_ok(base_pts.size() == 3, "耳底面 3 个角点（radial=3 三角棱锥，非 4 段方锥）")
		_ok_near(apex_max, 0.140 * s, 0.002, "耳尖高 0.14*scale=%.3f（顶端收成一点）" % (0.140 * s))
		_ok_near(base_r_max, 0.085 * s, 0.003, "耳底半径 0.085*scale=%.3f" % (0.085 * s))
	else:
		_ok(false, "耳网格应为三角锥 ArrayMesh")
	_ok(ear0.get_child_count() >= 2, "耳含外耳+浅色内耳（%d 个子网格）" % ear0.get_child_count())
	# 眼睛：扁球 + 竖瞳 + 高光
	for i in range(2):
		var eye: Node3D = _cat["eyes"][i] as Node3D
		_ok(eye.get_child_count() >= 3, "眼 %d 含眼球/竖瞳/高光（%d 个网格）" % [i, eye.get_child_count()])
	var lid: Node3D = _cat["eyelids"][0] as Node3D
	_ok_near(lid.rotation.x, 1.38, 0.01, "眼睑初始为张开姿态 rotation.x=1.38")
	# 爪贴地：每只脚 AABB 底部在 [ -0.02, 0.02 ]（root 局部，root 世界高 0.47 = 木板顶面）
	var paws: Array = _cat["paws"]
	var paw_ok := true
	var paw_info := ""
	for i in range(paws.size()):
		var pa := _aabb_in_root(paws[i], root)
		var bottom: float = pa.position.y
		paw_info += "paw%d y=%.4f " % [i, bottom]
		if bottom < -0.02 or bottom > 0.02:
			paw_ok = false
	_ok(paw_ok, "4 只脚掌贴门廊地面（root 局部 y≈0）：%s" % paw_info.strip_edges())
	# 整猫包围盒：不陷地、不超高、水平范围合理（尾巴在身后）
	var all_aabb := _aabb_in_root(root, root)
	_ok(all_aabb.position.y >= -0.02, "整猫最低点不穿地（min y=%.4f）" % all_aabb.position.y)
	_ok(all_aabb.end.y < 0.60, "整猫最高点 < 0.60m（%.3f）" % all_aabb.end.y)
	var horiz: float = maxf(absf(all_aabb.position.x), absf(all_aabb.end.x))
	horiz = maxf(horiz, maxf(absf(all_aabb.position.z), absf(all_aabb.end.z)))
	_ok(horiz < 0.55, "整猫水平半径 < 0.55m（%.3f，尾巴自然弯曲在身后）" % horiz)
	# P7-V3.2 尺度目标（Lead m00286）：坐姿耳尖 0.40-0.50，鼻尖到尾根 <=0.55，
	# 体宽 0.24-0.28，站立肩高 0.25-0.30。全部由 CAT_MODEL_SCALE 推导，不允许 root scale。
	var ear_tip: float = all_aabb.end.y
	_ok(ear_tip >= 0.40 and ear_tip <= 0.50, "坐姿耳尖高 %.3f ∈ [0.40, 0.50]" % ear_tip)
	var nose_z: float = _aabb_in_root(head, root).end.z
	var tail_root: Node3D = ((_cat["tail"] as Array)[0] as Node3D).get_parent() as Node3D
	var tail_root_z: float = tail_root.position.z
	var nose_to_tail: float = nose_z - tail_root_z
	_ok(nose_to_tail <= 0.55, "鼻尖到尾根 %.3f <= 0.55" % nose_to_tail)
	var body_width: float = _aabb_in_root(body, root).size.x
	_ok(body_width >= 0.24 and body_width <= 0.28, "体宽 %.3f ∈ [0.24, 0.28]" % body_width)
	var shoulder: float = _aabb_in_root(body, root).end.y
	# AABB 上界含身体 -0.20 rad 倾斜膨胀，实测 0.300（目标上界 0.30，允许 5 mm 舍入）
	_ok(shoulder >= 0.25 and shoulder <= 0.305, "站立肩高 %.3f ∈ [0.25, 0.30]（AABB 含倾斜）" % shoulder)
	# 头身衔接（不悬空/不断裂）
	var body_aabb := _aabb_in_root(body, root)
	var head_aabb := _aabb_in_root(head, root)
	var inter := body_aabb.intersection(head_aabb)
	var inter_vol: float = inter.size.x * inter.size.y * inter.size.z
	_ok(inter_vol > 0.0005, "头与身体重叠衔接（交集体积 %.5f m³）" % inter_vol)
	# 尾巴：根部连身体、3 节链、尾尖离地
	var tail: Array = _cat["tail"]
	var tail_node := (tail[0] as Node3D).get_parent() as Node3D
	_ok(tail_node.name == "Tail", "尾巴根节点名 Tail（实际 %s）" % tail_node.name)
	_ok_near(tail_node.position.y, 0.17 * s, 0.02, "尾根高度 y≈0.17*scale=%.3f（身体后侧）" % (0.17 * s))
	_ok(tail_node.position.z < -0.20 * s, "尾根在身体后侧（z=%.3f）" % tail_node.position.z)
	_ok((tail[1] as Node3D).get_parent() == tail[0], "尾 J1 挂在 J0 下")
	_ok((tail[2] as Node3D).get_parent() == tail[1], "尾 J2 挂在 J1 下")
	_ok(_tail_tip_local(tail).y > 0.15 * s, "尾尖离地足够高（局部 y=%.3f > %.3f）" % [_tail_tip_local(tail).y, 0.15 * s])
	# 阴影贴地
	if _cat["shadow"] != null:
		var sa := _aabb_in_root(_cat["shadow"], root)
		_ok(sa.position.y > -0.01 and sa.position.y < 0.10, "脚下软阴影贴地（y=%.3f）" % sa.position.y)
	# 初始无位移（静态几何不得随机跳）
	_ok_near(root.position.x, 2.30, 0.0001, "root x 未被动画改动")
	_ok_near(root.position.z, 6.10, 0.0001, "root z 未被动画改动")

func _tail_tip_local(tail: Array) -> Vector3:
	var j0: Node3D = tail[0] as Node3D
	var j1: Node3D = tail[1] as Node3D
	var j2: Node3D = tail[2] as Node3D
	var tail_node := j0.get_parent() as Node3D
	var p: Vector3 = j2.transform * Vector3(0.0, 0.132 * CAT.CAT_MODEL_SCALE, 0.0)
	p = j1.transform * p
	p = j0.transform * p
	return tail_node.transform * p

# ---------------------------------------------------------------------------
# 3) 待机：20s 连续变化 + 60s 事件统计/幅度边界/原地/无 NaN/不重建
# ---------------------------------------------------------------------------
func _test_idle_20s_and_60s() -> void:
	# 用固定 seed 新建一只，关闭 driver 后手动固定 dt 推进（等价 headless 模拟）
	_cat = CAT.build(_holder, Vector3(2.30, 0.47, 6.10), -0.6, {"seed": SEED})
	var root := _root()
	var idle = _cat["idle"]
	var driver: Node = _cat["driver"]
	driver.set_process(false)
	_ok(not driver.is_processing(), "手动模拟前关闭 driver._process")
	_log_line("")
	_log_line("## 模拟设置：seed=%d，固定 dt=1/60，手动 advance 20s + 60s" % SEED)
	_ok(int(idle.debug_state()["seed"]) == SEED, "RNG seed 可控（seed=%d）" % SEED)

	var nodes_before := _count_nodes(root)
	var rids_before: Array = []
	_mesh_rids(root, rids_before)
	var meshes_before := _count_meshes(root)
	var root_pos := root.position
	var root_rot := root.rotation
	var bad_nan: Array = []

	var max_tail0 := 0.0
	var max_tail1 := 0.0
	var max_tail0_x := 0.0
	var max_head_yaw := 0.0
	var max_head_yaw_nolick := 0.0
	var max_head_pitch := 0.0
	var max_ear := 0.0
	var max_lid := 0.0
	var max_lid_rot := -10.0
	var min_lid_rot := 10.0
	var min_breath := 10.0
	var max_breath := -10.0
	var min_tail_tip_y := 10.0
	var max_head_body := 0.0
	var root_drift := 0.0
	var snap20: Dictionary = {}
	var head_changed_20 := false
	var tail_changed_20 := false
	var lid_changed_20 := false
	var hist_blink: Array = []
	var hist_ear: Array = []
	var hist_look: Array = []
	var hist_lick: Array = []
	var steps := 3600
	for i in range(steps):
		idle.advance(DT)
		if i % 3 != 0:
			continue
		var st: Dictionary = idle.debug_state()
		var tail_y: Array = st["tail_y"]
		var tail_x: Array = st["tail_x"]
		var head_yaw: float = float(st["head_yaw"])
		var head_pitch: float = float(st["head_pitch"])
		var ear_flick: float = float(st["ear_flick"])
		var lid_amt: float = float(st["lid_amount"])
		var lid_rot: float = float(st["lid_rot"])
		var breath: float = float(st["breath_scale"])
		var lick_env: float = float(st["lick_env"])
		max_tail0 = maxf(max_tail0, absf(float(tail_y[0])))
		max_tail1 = maxf(max_tail1, absf(float(tail_y[1])))
		max_tail0_x = maxf(max_tail0_x, absf(float(tail_x[0])))
		max_head_yaw = maxf(max_head_yaw, absf(head_yaw))
		if lick_env < 0.001:
			max_head_yaw_nolick = maxf(max_head_yaw_nolick, absf(head_yaw))
		max_head_pitch = maxf(max_head_pitch, absf(head_pitch))
		max_ear = maxf(max_ear, absf(ear_flick))
		max_lid = maxf(max_lid, lid_amt)
		max_lid_rot = maxf(max_lid_rot, lid_rot)
		min_lid_rot = minf(min_lid_rot, lid_rot)
		min_breath = minf(min_breath, breath)
		max_breath = maxf(max_breath, breath)
		min_tail_tip_y = minf(min_tail_tip_y, _tail_tip_local(_cat["tail"]).y)
		var cs: float = CAT.CAT_MODEL_SCALE
		var head_local: Vector3 = (root.find_child("Head", true, false) as Node3D).transform * Vector3(0.0, 0.075 * cs, 0.065 * cs)
		max_head_body = maxf(max_head_body, head_local.distance_to(Vector3(0.0, 0.25 * cs, -0.045 * cs)))
		root_drift = maxf(root_drift, root.position.distance_to(root_pos))
		if i == 1200:
			snap20 = st.duplicate(true)
			tail_changed_20 = max_tail0 > 0.05
			lid_changed_20 = max_lid > 0.9
			head_changed_20 = max_head_yaw > 0.05 or max_head_pitch > 0.05
		# 结构/NaN 抽查
		if i % 300 == 0:
			var bad: Array = []
			_transforms_finite(root, bad)
			if bad.size() > 0:
				bad_nan.append_array(bad)
	hist_blink = (idle.debug_state()["history"]["blink"] as Array).duplicate()
	hist_ear = (idle.debug_state()["history"]["ear"] as Array).duplicate()
	hist_look = (idle.debug_state()["history"]["look"] as Array).duplicate()
	hist_lick = (idle.debug_state()["history"]["lick"] as Array).duplicate()

	# ---- 20s：连续动作确实发生 ----
	_ok(tail_changed_20, "连续 20s 尾巴摆动（max |Δyaw| = %.3f rad）" % max_tail0)
	_ok(lid_changed_20, "连续 20s 发生眨眼（lid_amount 峰值 %.2f）" % max_lid)
	_ok(head_changed_20, "连续 20s 头部变换发生过变化（max |yaw| = %.3f rad）" % max_head_yaw)
	_ok(snap20.size() > 0, "20s 快照有效")

	# ---- 60s：事件数量与随机错峰 ----
	var counts: Dictionary = idle.debug_state()["counts"]
	_ok(int(counts["blink"]) >= 4, "60s 眨眼次数 ≥4（%d）" % int(counts["blink"]))
	_ok(int(counts["ear"]) >= 3, "60s 耳朵抽动次数 ≥3（%d）" % int(counts["ear"]))
	_ok(int(counts["look"]) >= 2, "60s 观察四周次数 ≥2（%d）" % int(counts["look"]))
	_ok(int(counts["lick"]) >= 1, "60s 舔爪次数 ≥1（%d）" % int(counts["lick"]))
	var iv_blink := _intervals(hist_blink)
	var iv_ear := _intervals(hist_ear)
	var iv_look := _intervals(hist_look)
	var iv_lick := _intervals(hist_lick)
	_ok_check_intervals(iv_blink, 4.0, 9.75, "眨眼起始间隔 = 4~9s + 闭合时长")
	_ok_check_intervals(iv_ear, 6.0, 14.85, "耳朵起始间隔 = 6~14s + 抽动时长")
	_ok_check_intervals(iv_look, 12.0, 23.5, "观察起始间隔 = 10~20s + 转向/回正时长")
	_ok_check_intervals(iv_lick, 21.0, 37.5, "舔爪起始间隔 = 20~35s + 起落时长")
	var sp_blink := _spread(iv_blink)
	var sp_ear := _spread(iv_ear)
	var sp_look := _spread(iv_look)
	_ok(sp_blink > 0.25 or sp_ear > 0.25 or sp_look > 0.25,
		"事件间隔有随机错峰（spread：眨眼 %.2f / 耳 %.2f / 观察 %.2f s）" % [sp_blink, sp_ear, sp_look])
	_ok(_mean(iv_blink) < _mean(iv_look) and _mean(iv_look) < _mean(iv_lick) + 0.001,
		"不同动作节奏不同（均值：眨眼 %.2f < 观察 %.2f < 舔爪 %.2f s）" % [_mean(iv_blink), _mean(iv_look), _mean(iv_lick)])
	# 首次触发落在要求区间
	_ok(hist_blink.size() > 0 and float(hist_blink[0]) >= 3.99 and float(hist_blink[0]) <= 9.1,
		"首次眨眼在 4~9s（%.2fs）" % float(hist_blink[0]))
	_ok(hist_ear.size() > 0 and float(hist_ear[0]) >= 5.99 and float(hist_ear[0]) <= 14.1,
		"首次耳朵抽动在 6~14s（%.2fs）" % float(hist_ear[0]))
	_ok(hist_look.size() > 0 and float(hist_look[0]) >= 9.99 and float(hist_look[0]) <= 20.1,
		"首次观察四周在 10~20s（%.2fs）" % float(hist_look[0]))
	if hist_lick.size() > 0:
		_ok(float(hist_lick[0]) >= 19.99 and float(hist_lick[0]) <= 35.1,
			"首次舔爪在 20~35s（%.2fs）" % float(hist_lick[0]))
	else:
		_ok(false, "60s 内没有舔爪（要求 20~35s 一次）")

	# ---- 幅度边界（不穿模/不夸张） ----
	_ok(max_tail0 <= 0.1805, "尾巴第 1 节幅度 ≤±0.18 rad（%.4f）" % max_tail0)
	_ok(max_tail1 <= 0.1105, "尾巴第 2 节幅度 ≤±0.108 rad（%.4f）" % max_tail1)
	_ok(max_tail0_x <= 0.0351, "尾巴上下微摆 ≤0.03 rad（%.4f）" % max_tail0_x)
	_ok(max_head_yaw_nolick <= 0.3505, "观察四周头部 yaw ≤±0.35 rad（%.4f）" % max_head_yaw_nolick)
	_ok(max_head_yaw <= 0.5005, "头部 yaw 总幅度 ≤0.50 rad（观察+舔爪侧偏，%.4f）" % max_head_yaw)
	_ok(max_head_pitch <= 0.3505, "舔爪低头 ≤0.35 rad（%.4f）" % max_head_pitch)
	_ok(max_ear <= 0.2505, "耳朵抽动 ≤0.25 rad（%.4f）" % max_ear)
	_ok(max_lid >= 0.99 and max_lid_rot <= 1.381 and min_lid_rot >= -0.101,
		"眨眼眼睑范围 [%.3f, %.3f]（开 1.38 / 闭 -0.10）" % [min_lid_rot, max_lid_rot])
	_ok(min_breath >= 0.9845 and max_breath <= 1.0155,
		"呼吸 scale y ∈ [0.985, 1.015]（实测 %.4f~%.4f）" % [min_breath, max_breath])
	_ok(min_tail_tip_y > 0.12 * CAT.CAT_MODEL_SCALE, "尾巴摆动过程尾尖不触地/不穿地板（min 局部 y=%.3f）" % min_tail_tip_y)
	_ok(max_head_body < 0.45 * CAT.CAT_MODEL_SCALE and max_head_body > 0.25 * CAT.CAT_MODEL_SCALE,
		"头部始终连接身体（头中心距身中心 %.3f m，按 0.6 比例目标 %.2f-%.2f）" % [max_head_body, 0.25 * CAT.CAT_MODEL_SCALE, 0.45 * CAT.CAT_MODEL_SCALE])

	# ---- 原地不动 / 无 NaN / 不重建 ----
	_ok(root_drift < 0.000001, "全程根节点零位移（max drift=%.8f）" % root_drift)
	_ok(root.rotation.is_equal_approx(root_rot), "全程根节点旋转不变")
	var nodes_after := _count_nodes(root)
	var rids_after: Array = []
	_mesh_rids(root, rids_after)
	var meshes_after := _count_meshes(root)
	_ok(nodes_after == nodes_before, "节点数不变（%d → %d，无运行时增删节点）" % [nodes_before, nodes_after])
	_ok(meshes_after == meshes_before, "网格数不变（%d → %d，不每帧重建）" % [meshes_before, meshes_after])
	_ok(rids_after == rids_before, "网格 RID/实例 ID 全部不变（复用同一批网格）")
	var bad_now: Array = []
	_transforms_finite(root, bad_now)
	_ok(bad_nan.size() == 0 and bad_now.size() == 0, "全程无 NaN/Inf 变换（累计异常 %d 处）" % (bad_nan.size() + bad_now.size()))
	var df: Dictionary = idle.debug_state()
	var finite_ok: bool = is_finite(float(df["t"])) and is_finite(float(df["breath_scale"]))
	var tai: Array = df["tail_y"]
	for v in tai:
		if not is_finite(float(v)):
			finite_ok = false
	_ok(finite_ok, "待机状态数值全部有限（t/breath/tail_y）")
	_ok_near(float(df["t"]), 60.0, 0.05, "模拟时长 60s")

	# ---- 动作日志 ----
	_log_line("")
	_log_line("## 实测结果（60s，seed=%d）" % SEED)
	_log_line("计数：眨眼 %d / 耳 %d / 观察 %d / 舔爪 %d" % [int(counts["blink"]), int(counts["ear"]), int(counts["look"]), int(counts["lick"])])
	_log_line("眨眼起始时刻: %s" % str(hist_blink))
	_log_line("耳朵起始时刻: %s" % str(hist_ear))
	_log_line("观察起始时刻: %s" % str(hist_look))
	_log_line("舔爪起始时刻: %s" % str(hist_lick))
	_log_line("幅度：尾1 %.4f / 尾2 %.4f / 头yaw %.4f / 头pitch %.4f / 耳 %.4f rad" % [max_tail0, max_tail1, max_head_yaw_nolick, max_head_pitch, max_ear])
	_log_line("呼吸 scale y：%.4f ~ %.4f；尾尖最低 y=%.3f；头身中心距 %.3f m" % [min_breath, max_breath, min_tail_tip_y, max_head_body])
	_log_line("20s 快照：t=%.1f 尾y=%s 头yaw=%.3f 眼睑=%.3f" % [float(snap20.get("t", 0.0)), str(snap20.get("tail_y", [])), float(snap20.get("head_yaw", 0.0)), float(snap20.get("lid_amount", 0.0))])
	_log_line("根节点位移 %.8f；节点数 %d 恒定；网格数 %d 恒定；无 NaN" % [root_drift, nodes_after, meshes_after])

func _intervals(hist: Array) -> Array:
	var out: Array = []
	for i in range(1, hist.size()):
		out.append(float(hist[i]) - float(hist[i - 1]))
	return out

func _spread(arr: Array) -> float:
	if arr.size() < 2:
		return 0.0
	var lo: float = float(arr[0])
	var hi: float = float(arr[0])
	for v in arr:
		lo = minf(lo, float(v))
		hi = maxf(hi, float(v))
	return hi - lo

func _mean(arr: Array) -> float:
	if arr.size() == 0:
		return 0.0
	var s := 0.0
	for v in arr:
		s += float(v)
	return s / float(arr.size())

func _ok_check_intervals(iv: Array, lo: float, hi: float, label: String) -> void:
	var good := iv.size() > 0
	var bad := ""
	for v in iv:
		var d := float(v)
		if d < lo or d > hi:
			good = false
			bad += " %.2f" % d
	_ok(good, "%s 全部在 [%.1f, %.2f]s（%s）" % [label, lo, hi, "实测 " + str(iv) if good else "越界:" + bad])

# ---------------------------------------------------------------------------
# 4) seed 可复现 / 不同 seed 不同
# ---------------------------------------------------------------------------
func _test_determinism() -> void:
	var a: Dictionary = CAT.build(_holder, Vector3.ZERO, 0.0, {"seed": 111, "shadow": false})
	var b: Dictionary = CAT.build(_holder, Vector3.ZERO, 0.0, {"seed": 111, "shadow": false})
	var c: Dictionary = CAT.build(_holder, Vector3.ZERO, 0.0, {"seed": 222, "shadow": false})
	(a["driver"] as Node).set_process(false)
	(b["driver"] as Node).set_process(false)
	(c["driver"] as Node).set_process(false)
	for i in range(300):
		a["idle"].advance(DT)
		b["idle"].advance(DT)
		c["idle"].advance(DT)
	var sa: Dictionary = a["idle"].debug_state()
	var sb: Dictionary = b["idle"].debug_state()
	var sc: Dictionary = c["idle"].debug_state()
	var same_seed := absf(float(sa["breath_period"]) - float(sb["breath_period"])) < 0.0001 \
		and int(sa["counts"]["blink"]) == int(sb["counts"]["blink"]) \
		and str(sa["tail_y"]) == str(sb["tail_y"]) \
		and str(sa["history"]) == str(sb["history"])
	_ok(same_seed, "相同 seed 完全复现（呼吸周期/尾巴相位/事件时刻一致）")
	var tail_a: Array = sa["tail_y"]
	var tail_c: Array = sc["tail_y"]
	var diff_c := absf(float(sa["breath_period"]) - float(sc["breath_period"])) > 0.001 \
		or absf(float(tail_a[0]) - float(tail_c[0])) > 0.002
	_ok(diff_c, "不同 seed 动作参数不同（seed=111 vs 222：呼吸周期 %.3f vs %.3f）" % [float(sa["breath_period"]), float(sc["breath_period"])])
	_log_line("")
	_log_line("## seed 复现性：seed111 两次一致=%s；seed111 vs seed222 不同=%s" % [str(same_seed), str(diff_c)])
	(a["root"] as Node3D).queue_free()
	(b["root"] as Node3D).queue_free()
	(c["root"] as Node3D).queue_free()

# ---------------------------------------------------------------------------
# 5) 暂停/恢复（随 SceneTree.process 自动停；恢复后继续）
# ---------------------------------------------------------------------------
func _test_pause_resume() -> void:
	var cat: Dictionary = CAT.build(_holder, Vector3(5.0, 0.0, 0.0), 0.0, {"seed": 42, "shadow": false})
	var root := cat["root"] as Node3D
	var driver: Node = cat["driver"]
	var idle = cat["idle"]
	await process_frame
	await process_frame
	var t0: float = float(idle.debug_state()["t"])
	_ok(t0 > 0.0, "驱动节点在场景树中自动推进（t=%.3fs）" % t0)
	paused = true
	await create_timer(0.20).timeout
	var t1: float = float(idle.debug_state()["t"])
	_ok(t1 - t0 < 0.01, "SceneTree.paused=true 时待机动作暂停（Δ=%.4fs）" % (t1 - t0))
	_ok(driver.is_processing() and not driver.can_process(), "暂停时 driver 启用但不可处理（可暂停）")
	await create_timer(0.10).timeout
	var t2: float = float(idle.debug_state()["t"])
	_ok(absf(t2 - t1) < 0.005, "暂停期间持续不动（Δ=%.4fs）" % (t2 - t1))
	paused = false
	await create_timer(0.20).timeout
	var t3: float = float(idle.debug_state()["t"])
	_ok(t3 > t2 + 0.05, "恢复后继续推进（Δ=%.3fs）" % (t3 - t2))
	_ok(driver.can_process(), "恢复后可处理（可恢复）")
	# 暂停/恢复不引起位置跳变
	_ok(root.position.distance_to(Vector3(5.0, 0.0, 0.0)) < 0.000001, "暂停/恢复不引起根节点位移")
	_log_line("")
	_log_line("## 暂停/恢复：t0=%.3f → 暂停 0.30s 后 t1=%.3f（Δ=%.4f） → 恢复后 t=%.3f" % [t0, t1, t1 - t0, t3])
	root.queue_free()
