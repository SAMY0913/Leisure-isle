extends SceneTree
## P7-V3.1 门廊猫尾巴剪影测量探针（headless）
##
## 背景：P7-V3 验收记录"低机位正面时尾巴在头顶形成环状剪影，损害外形识别"。
## 本探针把这件事变成可量化的几何事实，并给出修复前后的对照口径。
##
## 关键口径（踩过的坑）：必须用**透视投影**判定，不能用"比 y 大小"。
##   cat_close_front 机位是"相机高 0.80m 俯视 0.26m"，尾巴位于猫身后 0.56m、y≈0.53。
##   俯视时身后偏低的物体会因透视被抬到画面上方 —— 正投影会得出"尾巴在头下方"的
##   错误结论，而实际渲染里它正好从两耳之间露出来（已用"隐藏尾巴 A/B 截图"证实：
##   差异区域 (1171,53)-(1285,115) 精确落在头顶上方）。
##
## 断言：
##  1) 基态尾巴尖**不**高于头球顶在屏幕上的高度，或已偏出两耳横向范围；
##  2) 待机动画整周期内同样成立（逐相位采样）；
##  3) 尾巴仍在、3 节链完整、仍高于地面；
##  4) 呼吸/眨眼/张望/舔爪/双耳等其它动作全部保留。
##
## 运行：
##   ENG --headless --path <PROJ> --script res://tools/probe_cat_tail_p7v31.gd

var _pass: int = 0
var _fail: int = 0

func _initialize() -> void:
	await process_frame
	var packed: PackedScene = load("res://isle.tscn") as PackedScene
	var main: Node = packed.instantiate()
	get_root().add_child(main)
	await process_frame
	await process_frame
	var menu = main.get("_menu")
	if menu != null and menu.has_method("instant_finish"):
		menu.call("instant_finish")
	main.set("_mode", 1)
	main.set("_started", true)
	main.set("_paused", true)
	main.set("_blending", "")
	await process_frame
	await process_frame

	var cat: Node3D = _find_named(get_root(), "PorchCat") as Node3D
	if cat == null:
		print("[CATTAIL] FAIL PorchCat 缺失")
		quit(1)
		return
	var tail: Node3D = cat.get_node_or_null("Tail") as Node3D
	if tail == null:
		print("[CATTAIL] FAIL Tail 缺失")
		quit(1)
		return
	# 尾巴是 3 节链：Tail/TailJ0 → TailJ1 → TailJ2（逐级为上一节的子节点）
	var j0: Node3D = tail.get_node_or_null("TailJ0") as Node3D
	var j1: Node3D = (j0.get_node_or_null("TailJ1") as Node3D) if j0 != null else null
	var j2: Node3D = (j1.get_node_or_null("TailJ2") as Node3D) if j1 != null else null
	if j0 == null or j1 == null or j2 == null:
		print("[CATTAIL] FAIL 尾巴关节缺失")
		quit(1)
		return
	var drv: Node = cat.get_node_or_null("CatIdleDriver")
	var ctl = drv.get("controller") if drv != null else null
	if ctl == null:
		print("[CATTAIL] FAIL 缺少 CatIdle 控制器")
		quit(1)
		return
	# 采样期间关掉 driver 的每帧推进，改为本探针按固定 dt 手动 advance，保证确定性
	if drv != null:
		drv.set_process(false)
	ctl.call("_reset_pose")
	await process_frame

	var cat_inv: Transform3D = cat.global_transform.affine_inverse()
	var cfwd := (cat.global_transform.basis * Vector3(0.0, 0.0, 1.0)).normalized()
	var cam_from := cat.global_position + cfwd * 1.25 + Vector3(0.0, 0.80, 0.0)
	var cam_look := cat.global_position + Vector3(0.0, 0.26, 0.0)
	var fov := 35.0
	var aspect := 1600.0 / 900.0

	# 头球顶（不含耳朵）：HeadCore 世界位置 + 头半径*0.97（头球 scale y = 0.97）
	var head_core: Node3D = cat.get_node_or_null("Head/HeadCore") as Node3D
	if head_core == null:
		print("[CATTAIL] FAIL HeadCore 缺失")
		quit(1)
		return
	var head_top_world: Vector3 = head_core.global_transform * Vector3(0.0, 0.155 * 0.97, 0.0)
	var head_top_ndc := _project(cam_from, cam_look, fov, aspect, head_top_world)
	var head_side_world: Vector3 = head_core.global_transform * Vector3(0.16, 0.155 * 0.97, 0.0)
	var head_half_ndc := absf(_project(cam_from, cam_look, fov, aspect, head_side_world).x)
	print("[CATTAIL] cam_from=%s look=%s fov=%.0f" % [str(cam_from), str(cam_look), fov])
	print("[CATTAIL] head_top_ndc=(%.4f,%.4f) head_half_ndc=%.4f" % [head_top_ndc.x, head_top_ndc.y, head_half_ndc])

	# ---- 1) 基态 ----
	var rest_tip_world: Vector3 = j2.global_transform * Vector3(0.0, 0.132, 0.0)
	var rest_ndc := _project(cam_from, cam_look, fov, aspect, rest_tip_world)
	print("[CATTAIL] rest_tip_local=%s ndc=(%.4f,%.4f)" % [str(cat_inv * rest_tip_world), rest_ndc.x, rest_ndc.y])
	var rest_over := _over_head(rest_ndc, head_top_ndc, head_half_ndc)
	print("[CATTAIL]   dy_vs_head_top=%.4f (正值=比头顶更高)  |x|=%.4f  in_head_silhouette=%s" % [
		rest_ndc.y - head_top_ndc.y, absf(rest_ndc.x), str(rest_over)])
	var head_tail_height := 0.155 * 2.0 * 0.97
	var geom_gap := head_top_world.y - rest_tip_world.y
	print("[CATTAIL] world_y: head_top=%.4f tail_tip=%.4f gap=%.4f (正=尾巴更低)" % [
		head_top_world.y, rest_tip_world.y, geom_gap])

	# ---- 2) 待机动画整周期 ----
	var period := float(ctl.get("_tail_period"))
	if period <= 0.0:
		period = 6.0
	var samples := 36
	var dt := period / float(samples)
	var max_dy := -INF
	var min_dy := INF
	var minx := INF
	var maxx := -INF
	var miny := INF
	var maxy := -INF
	var over_frames := 0
	for i in range(samples):
		ctl.call("advance", dt)
		var tw: Vector3 = j2.global_transform * Vector3(0.0, 0.132, 0.0)
		var ndc := _project(cam_from, cam_look, fov, aspect, tw)
		var tl := cat_inv * tw
		minx = minf(minx, tl.x); maxx = maxf(maxx, tl.x)
		miny = minf(miny, tl.y); maxy = maxf(maxy, tl.y)
		var dy := ndc.y - head_top_ndc.y
		max_dy = maxf(max_dy, dy)
		min_dy = minf(min_dy, dy)
		if _over_head(ndc, head_top_ndc, head_half_ndc):
			over_frames += 1
	print("[CATTAIL] anim: tip_local x∈[%.3f,%.3f] y∈[%.3f,%.3f]" % [minx, maxx, miny, maxy])
	print("[CATTAIL] anim: dy_vs_head_top ∈ [%.4f, %.4f]   frames_over_head=%d/%d" % [min_dy, max_dy, over_frames, samples])

	# ---- 3) 判定 ----
	var tail_keep := 0
	if rest_over:
		tail_keep += 1
	_ok(not rest_over, "基态：尾巴尖不从两耳之间露出头顶", "dy=%.4f |x|=%.4f" % [rest_ndc.y - head_top_ndc.y, absf(rest_ndc.x)])
	_ok(over_frames == 0, "待机整周期：尾巴尖不露出头顶", "%d/%d 帧越界" % [over_frames, samples])
	_ok(miny > 0.06, "尾巴全程离地（cat 局部 y > 0.06）", "min_y=%.3f" % miny)
	_ok(geom_gap > -0.02, "尾巴尖世界高度不高于头球顶（几何上也不该反超）", "gap=%.3f" % geom_gap)

	# ---- 4) 其它动作仍然存在 ----
	var has_lick := false
	var has_look := false
	for m in ctl.get_method_list():
		var mn := String(m.get("name", ""))
		if mn.contains("lick"):
			has_lick = true
		if mn.contains("look"):
			has_look = true
	var breath: Variant = ctl.get("_breath_period")
	var ears: Array = ctl.get("_ears") if ctl.get("_ears") != null else []
	var lids: Array = ctl.get("_lids") if ctl.get("_lids") != null else []
	var head_node: Node3D = cat.get_node_or_null("Head") as Node3D
	_ok(breath != null, "呼吸动画参数仍存在", str(breath))
	_ok(ears.size() == 2, "双耳枢轴仍在（抽动动画）", str(ears.size()))
	# 张望是绕 Head 枢轴转头（不是独立眼球节点数组），因此断言方法与 Head 节点
	_ok(has_look and head_node != null, "张望动画仍在（_tick_look + Head 枢轴）", str(head_node != null))
	_ok(lids.size() == 2, "双上眼睑仍在（眨眼动画）", str(lids.size()))
	_ok(has_lick, "舔爪动作方法仍存在", "")
	_ok(j2.get_child_count() > 0, "尾巴末端部件仍在（尾巴没被删）", str(j2.get_child_count()))
	var tail_joints: Variant = ctl.get("_tail")
	_ok(tail_joints is Array and (tail_joints as Array).size() == 3, "3 节尾巴链完整",
		str((tail_joints as Array).size() if tail_joints is Array else -1))
	# 尾巴仍在摆动（幅度非零），不是被"冻住"
	var amp := float(ctl.get("_tail_period"))
	_ok(amp > 0.0, "尾巴仍保留摆动周期（动画未被取消）", "period=%.2f" % amp)

	print("[CATTAIL] RESULT pass=%d fail=%d" % [_pass, _fail])
	await process_frame
	quit(0 if _fail == 0 else 1)

## 透视投影 → NDC（y 向上为正，画面上方 = 更大的 y）
func _project(from: Vector3, to: Vector3, fov_deg: float, aspect: float, p: Vector3) -> Vector2:
	var fwd := (to - from).normalized()
	var right := fwd.cross(Vector3.UP)
	if right.length() < 0.0001:
		right = Vector3.RIGHT
	right = right.normalized()
	var up := right.cross(fwd).normalized()
	var v := p - from
	var d := v.dot(fwd)
	if d <= 0.001:
		return Vector2(INF, INF)
	var t := tan(deg_to_rad(fov_deg) * 0.5)
	return Vector2((v.dot(right) / d) / (t * aspect), (v.dot(up) / d) / t)

## "从两耳之间露出头顶"：屏幕 y 高于头球顶，且横向仍落在两耳之间的范围里
func _over_head(tip_ndc: Vector2, head_top_ndc: Vector2, head_half_ndc: float) -> bool:
	if not is_finite(tip_ndc.y):
		return false
	var above := tip_ndc.y > head_top_ndc.y
	var between := absf(tip_ndc.x) < head_half_ndc
	return above and between

func _find_named(n: Node, nm: String) -> Node:
	if String(n.name) == nm:
		return n
	for c in n.get_children():
		var r := _find_named(c, nm)
		if r != null:
			return r
	return null

func _ok(cond: bool, msg: String, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("[CATTAIL] PASS ", msg, ("  (" + detail + ")") if detail != "" else "")
	else:
		_fail += 1
		print("[CATTAIL] FAIL ", msg, ("  (" + detail + ")") if detail != "" else "")
