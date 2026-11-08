extends SceneTree
## P9 / P6 —— 钓鱼视觉装配件探针（headless 结构 / 行为断言）。
##
## 运行方式：
##   ENG --headless --path GAME --script res://tools/probe_p9_fishing_rig.gd -- --out=D:/休闲小岛幻境/开发产物/P9/P6/r1_rig
##
## 纪律：
## - 只实例化真实的村民模型（isle_villager_model.create(0)），不改村民脚本、不启动主场景、不写库存。
## - 全部断言走 IsleFishingRig 的公开 API + 场景树结构，不读私有字段（debug_info 是公开诊断口）。
## - 检查不弱化：距离/尺寸/可见性都按任务书阈值，宁可真 FAIL 也不放宽。

const RIG := preload("res://scripts/isle_fishing_rig.gd")
const MODEL_PATH := "res://scripts/isle_villager_model.gd"
const DEFAULT_OUT := "D:/休闲小岛幻境/开发产物/P9/P6/r1_rig"

# 任务书给的钓鱼点 / 抛竿落点
const CAST_TARGET := Vector3(23.1 + 2.8, 0.0, 12.57)
const HANG_DROP_MAX := 0.60

var out_dir := DEFAULT_OUT

var _pass := 0
var _fail := 0
var _lines: Array = []
var _fail_names: Array = []

var _holder: Node3D = null
var _model_root: Node3D = null
var _hand: Node3D = null
var _rig = null


func _initialize() -> void:
	_parse_args()
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--out="):
			out_dir = s.substr(6).strip_edges().trim_suffix("/").trim_suffix("\\")
	if out_dir == "":
		out_dir = DEFAULT_OUT


func _run() -> void:
	var banner := "[P9RIG] out=%s headless=%s godot=%s" % [
		out_dir, str(DisplayServer.get_name() == "headless"),
		String(Engine.get_version_info().get("string", ""))]
	print(banner)
	_lines.append(banner)

	var ok := await _boot()
	if ok:
		await _pre_setup_checks()
		await _structure_checks()
		await _cast_checks()
		await _nibble_bite_checks()
		await _reel_checks()
		await _catch_checks()
		await _clear_checks()
		await _pause_checks()
		await _lifecycle_checks()
	_write_report()
	var summary := "[SUMMARY] checks=%d fail=%d" % [_pass + _fail, _fail]
	print(summary)
	_lines.append(summary)
	print("[RESULT] ", "PASS" if _fail == 0 else "FAIL")
	_lines.append("[RESULT] " + ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)


# =========================================================== 基础设施 =========

func _section(title: String) -> void:
	print("")
	print("== ", title, " ==")
	_lines.append("")
	_lines.append("== " + title + " ==")


func _check(name: String, ok: bool, expected: String, actual: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		_fail_names.append(name)
	print("[CHECK] %s | expected=%s actual=%s | %s" % [name, expected, actual, "PASS" if ok else "FAIL"])
	_lines.append("[CHECK] %s | expected=%s actual=%s | %s" % [name, expected, actual, "PASS" if ok else "FAIL"])


func _check_eq(name: String, expected: Variant, actual: Variant) -> void:
	_check(name, expected == actual, str(expected), str(actual))


func _check_range(name: String, value: float, lo: float, hi: float) -> void:
	_check(name, value >= lo and value <= hi, "[%s, %s]" % [str(lo), str(hi)], str(value))


func _write_report() -> void:
	var log_path := out_dir + "/probe_p9_fishing_rig.log"
	var fa := FileAccess.open(log_path, FileAccess.WRITE)
	if fa != null:
		fa.store_string("\n".join(_lines) + "\n")
		fa.close()
		print("[P9RIG] log=", log_path)
	var data := {
		"checks": _pass + _fail,
		"fail": _fail,
		"fail_names": _fail_names,
		"pass": _pass,
		"script": "tools/probe_p9_fishing_rig.gd",
		"rig_script": "scripts/isle_fishing_rig.gd",
		"cast_target": [CAST_TARGET.x, CAST_TARGET.y, CAST_TARGET.z],
		"godot": String(Engine.get_version_info().get("string", "")),
		"headless": DisplayServer.get_name() == "headless",
	}
	var fj := FileAccess.open(out_dir + "/probe_p9_fishing_rig.json", FileAccess.WRITE)
	if fj != null:
		fj.store_string(JSON.stringify(data, "\t") + "\n")
		fj.close()


func _tick_frames(n: int, dt: float = 1.0 / 60.0) -> void:
	for i in n:
		_rig.tick(dt, false)
		await process_frame


# =========================================================== 启动 =============

func _boot() -> bool:
	_section("boot")
	var model_script: Variant = load(MODEL_PATH)
	_check("boot.model_script", model_script is Script, "Script", str(model_script))
	if not (model_script is Script):
		return false
	var made: Variant = model_script.call("create", 0)
	_check("boot.model_create", typeof(made) == TYPE_DICTIONARY, "Dictionary", str(typeof(made)))
	if typeof(made) != TYPE_DICTIONARY:
		return false
	var md: Dictionary = made
	_model_root = md.get("root") as Node3D
	_check("boot.model_root", _model_root != null, "Node3D", str(_model_root))
	if _model_root == null:
		return false

	_holder = Node3D.new()
	_holder.name = "VillagerHolder"
	# 真实钓鱼点：村民站在沙滩 (23.1, 12.57)，海平面 y=0，抛竿落点在 +X 侧约 2.8 m
	_holder.position = Vector3(23.1, 0.0, 12.57)
	get_root().add_child(_holder)
	_holder.add_child(_model_root)

	var hv: Variant = _model_root.call("get_joint", "hand_r")
	_hand = hv as Node3D
	_check("boot.hand_joint", _hand != null, "Node3D hand_r", str(_hand))
	if _hand == null:
		return false

	_rig = RIG.new()
	_rig.name = "FishingRig"
	_holder.add_child(_rig)
	_rig.setup(_holder, _model_root, _hand)
	await process_frame
	await process_frame

	var info: Dictionary = _rig.debug_info()
	_check("boot.setup_built", bool(info.get("built", false)), "true", str(info.get("built", null)))
	_check("boot.rig_parent", _rig.get_parent() == _holder, "VillagerHolder", str(_rig.get_parent()))
	var tip: Vector3 = _rig.rod_tip_world()
	var hand_pos: Vector3 = _rig.hand_world()
	_check_range("boot.rod_tip_from_hand", tip.distance_to(hand_pos), 1.0, 2.5)
	return true


# =========================================================== 未 setup 安全 =====

func _pre_setup_checks() -> void:
	_section("pre_setup_safety")
	var pre = RIG.new()
	pre.name = "PreSetupRig"
	get_root().add_child(pre)
	var crashed := false
	var detail := ""
	# 每个公开方法在 setup() 之前调用都不能崩（不接 try/catch，直接调用；崩了整个脚本会带栈报错）
	pre.rod_tip_world()
	pre.hand_world()
	pre.show_rod(true)
	pre.set_line_visible(false)
	pre.start_cast(Vector3(25.9, 0.0, 12.57), 1.2)
	pre.set_bobber_target(Vector3(25.0, 0.0, 12.0))
	pre.set_bobber_visible(true)
	pre.bobber_world()
	pre.nibble(0.7)
	pre.bite()
	pre.start_reel(0.5)
	pre.show_catch("fish_koi", 0.32)
	pre.hide_catch()
	pre.clear_all()
	pre.tick(1.0 / 60.0, false)
	pre.tick(1.0 / 60.0, true)
	# setup(null, null, null) 也要安全
	pre.setup(null, null, null)
	pre.tick(1.0 / 60.0, false)
	var tip: Vector3 = pre.rod_tip_world()
	var bob: Vector3 = pre.bobber_world()
	var info2: Dictionary = pre.debug_info()
	crashed = not bool(info2.get("built", false))
	detail = "built=%s" % str(info2.get("built", null))
	_check("pre_setup.no_crash", not crashed, "built=true", detail)
	_check("pre_setup.rod_tip_finite", is_finite(tip.x) and is_finite(tip.y) and is_finite(tip.z), "finite Vector3", str(tip))
	_check("pre_setup.bobber_finite", is_finite(bob.x) and is_finite(bob.y) and is_finite(bob.z), "finite Vector3", str(bob))
	# null 参数下也应有完整节点结构
	_check("pre_setup.null_setup_has_rod", pre.get_node_or_null("Rod") != null, "Rod 节点", str(pre.get_node_or_null("Rod")))
	pre.free()


# =========================================================== 结构 =============

func _structure_checks() -> void:
	_section("structure")
	var rod: Node = _rig.get_node_or_null("Rod")
	var rod_mesh: Node = _rig.get_node_or_null("Rod/RodMesh")
	var line: Node = _rig.get_node_or_null("Line")
	var bobber: Node = _rig.get_node_or_null("Bobber")
	var bobber_mesh: Node = _rig.get_node_or_null("Bobber/BobberMesh")
	var splash: Node = _rig.get_node_or_null("Splash")
	var ripple: Node = _rig.get_node_or_null("Ripple")
	var catch_node: Node = _rig.get_node_or_null("Catch")
	var fish: Node = _rig.get_node_or_null("Catch/Fish")
	_check("structure.rod", rod is Node3D, "Node3D", str(rod))
	_check("structure.rod_mesh", rod_mesh is MeshInstance3D, "MeshInstance3D", str(rod_mesh))
	_check("structure.line", line is MeshInstance3D, "MeshInstance3D", str(line))
	_check("structure.bobber", bobber is Node3D, "Node3D", str(bobber))
	_check("structure.bobber_mesh", bobber_mesh is MeshInstance3D, "MeshInstance3D", str(bobber_mesh))
	_check("structure.splash", splash is CPUParticles3D, "CPUParticles3D", str(splash))
	_check("structure.ripple", ripple is MeshInstance3D, "MeshInstance3D", str(ripple))
	_check("structure.catch", catch_node is Node3D, "Node3D", str(catch_node))
	_check("structure.fish", fish is MeshInstance3D, "MeshInstance3D", str(fish))
	_check("structure.child_count", _rig.get_child_count() == 6, "6", str(_rig.get_child_count()))

	if rod_mesh is MeshInstance3D:
		var mi := rod_mesh as MeshInstance3D
		var aabb := mi.get_aabb()
		_check_range("structure.rod_length", aabb.size.y, 1.7, 1.9)
		var mat := mi.material_override
		_check("structure.rod_material", mat != null, "材质非空", str(mat))
	if line is MeshInstance3D:
		var lm := line as MeshInstance3D
		_check("structure.line_mesh_type", lm.mesh is ImmediateMesh, "ImmediateMesh", str(lm.mesh))
		var lmat := lm.material_override as StandardMaterial3D
		_check("structure.line_unshaded", lmat != null and lmat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "UNSHADED", str(lmat.shading_mode) if lmat != null else "null")
		_check("structure.line_cull_disabled", lmat != null and lmat.cull_mode == BaseMaterial3D.CULL_DISABLED, "CULL_DISABLED", str(lmat.cull_mode) if lmat != null else "null")
	if splash is CPUParticles3D:
		var ps := splash as CPUParticles3D
		_check("structure.splash_one_shot", ps.one_shot, "true", str(ps.one_shot))
		_check("structure.splash_idle", not ps.emitting, "false", str(ps.emitting))
		_check("structure.splash_amount", ps.amount >= 8, ">=8", str(ps.amount))
	# 初始状态：竿/浮漂/鱼获应全部隐藏（由 Lead 显式打开）
	_check("structure.initial_rod_hidden", (rod as Node3D).visible == false, "false", str((rod as Node3D).visible))
	_check("structure.initial_bobber_hidden", (bobber as Node3D).visible == false, "false", str((bobber as Node3D).visible))
	_check("structure.initial_catch_hidden", (catch_node as Node3D).visible == false, "false", str((catch_node as Node3D).visible))
	_check("structure.initial_ripple_hidden", (ripple as Node3D).visible == false, "false", str((ripple as Node3D).visible))

	# P9 / P6-VISUAL-FIX：竿的世界指向必须在 **村民朝向** 空间里判据，而不是 hand 空间。
	# 旧断言只查“hand 空间向上偏前”，恰好把“hand 被手臂链转了 68°”这个错误基准当成正确，
	# 于是鱼竿朝后扛在肩上也能通过 —— 这就是上一版 QA 的盲点。
	var tip_rel: Vector3 = _rig.rod_tip_world() - _holder.global_position
	var fwd := (_holder.global_transform.basis * Vector3(0.0, 0.0, -1.0)).normalized()
	var rightv := (_holder.global_transform.basis * Vector3(1.0, 0.0, 0.0)).normalized()
	var fwd_flat := Vector3(fwd.x, 0.0, fwd.z).normalized()
	var dir_world: Vector3 = (_rig.rod_tip_world() - _rig.hand_world()).normalized()
	var tip_fwd_m := Vector2(tip_rel.x, tip_rel.z).dot(Vector2(fwd_flat.x, fwd_flat.z))
	_check_range("structure.rod_length_world", _rig.rod_tip_world().distance_to(_rig.hand_world()), 1.5, 2.0)
	_check("structure.rod_forward_dot", dir_world.dot(fwd_flat) > 0.80,
		"竿身与角色前向夹角 <37°（dot > 0.80）", str(dir_world.dot(fwd_flat)))
	_check("structure.rod_tip_front", tip_fwd_m > 1.2,
		"竿尖在角色身前 > 1.2 m", str(tip_fwd_m))
	_check("structure.rod_tip_up", _rig.rod_tip_world().y - _holder.global_position.y > 1.2,
		"竿尖高出脚底 > 1.2 m", str(_rig.rod_tip_world().y - _holder.global_position.y))
	_check("structure.rod_not_back", dir_world.dot(fwd_flat) > 0.0,
		"竿不再指向角色身后", str(dir_world.dot(fwd_flat)))

	# setup 幂等：再调一次不产生重复子节点
	var before: int = _rig.get_child_count()
	_rig.setup(_holder, _model_root, _hand)
	await process_frame
	_check_eq("structure.setup_idempotent_children", before, _rig.get_child_count())
	_check("structure.setup_idempotent_rod", _rig.get_node_or_null("Rod") != null, "Rod 存在", str(_rig.get_node_or_null("Rod")))
	_check("structure.setup_single_rod", _holder.get_node_or_null("FishingRig/Rod") != null, "唯一 Rod", str(_holder.get_node_or_null("FishingRig/Rod")))

	# Lead 侧状态机实际以无参 call 驱动（_fish_rig_call(&"show_rod") / set_bobber_visible / set_line_visible）：
	# 这些方法的默认参数必须是可用默认值（show_rod() 等价 show_rod(true)），否则真游戏里竿永远不显示。
	var rod2 := _rig.get_node_or_null("Rod") as Node3D
	var bobber2 := _rig.get_node_or_null("Bobber") as Node3D
	var line2 := _rig.get_node_or_null("Line") as MeshInstance3D
	_rig.call("show_rod")
	_rig.call("set_bobber_visible")
	_rig.call("set_line_visible")
	_rig.tick(1.0 / 60.0, false)
	var rod2_vis := rod2 != null and rod2.visible
	var bobber2_vis := bobber2 != null and bobber2.visible
	var line2_vis := line2 != null and line2.visible
	_check("api.noargs_rod", rod2_vis, "true", str(rod2_vis))
	_check("api.noargs_bobber", bobber2_vis, "true", str(bobber2_vis))
	_check("api.noargs_line", line2_vis, "true", str(line2_vis))
	# 恢复初始隐藏态，避免影响后面的用例
	_rig.show_rod(false)
	_rig.set_bobber_visible(false)
	_rig.tick(1.0 / 60.0, false)


# =========================================================== 抛竿 =============

func _cast_checks() -> void:
	_section("cast")
	_rig.show_rod(true)
	_rig.set_line_visible(true)
	_check("cast.rod_visible_after_show", (_rig.get_node("Rod") as Node3D).visible, "true", str((_rig.get_node("Rod") as Node3D).visible))
	var tip_before: Vector3 = _rig.rod_tip_world()
	_rig.start_cast(CAST_TARGET, 1.2)
	# 0.17 s：后摆蓄力段——竿身后仰、饵/浮漂仍跟着竿尖。
	await _tick_frames(10)
	var info_back: Dictionary = _rig.debug_info()
	var mid: Vector3 = _rig.bobber_world()
	var tip_back: Vector3 = _rig.rod_tip_world()
	_check("cast.backswing_anim", String(info_back.get("rod_anim", "")) == "cast",
		"rod_anim=cast", str(info_back.get("rod_anim")))
	_check("cast.backswing_pitch", float(info_back.get("rod_pose_pitch", 0.0)) > 0.35,
		"后摆 pitch>0.35", str(info_back.get("rod_pose_pitch")))
	_check("cast.bobber_follows_tip", mid.distance_to(tip_back + Vector3(0.0, 0.03, 0.0)) < 0.2,
		"挥杆时饵随竿尖（未提前飞走）", str(mid.distance_to(tip_back)))
	_check("cast.launched_false_before", not bool(info_back.get("cast_launched", true)),
		"甩出前 cast_launched=false", str(info_back.get("cast_launched")))
	_check("cast.tip_swept", tip_back.distance_to(tip_before) > 0.2,
		"竿尖真实挥动 > 0.2 m", str(tip_back.distance_to(tip_before)))
	_check("cast.line_visible_mid", (_rig.get_node("Line") as MeshInstance3D).visible, "true", str((_rig.get_node("Line") as MeshInstance3D).visible))
	# 0.67 s：前甩出手段——竿身前压、饵已离开竿尖飞向落点。
	await _tick_frames(30)
	var info_whip: Dictionary = _rig.debug_info()
	var tip_whip: Vector3 = _rig.rod_tip_world()
	_check("cast.launched_after", bool(info_whip.get("cast_launched", false)),
		"前甩后 cast_launched=true", str(info_whip.get("cast_launched")))
	_check("cast.whip_pitch", float(info_whip.get("rod_pose_pitch", 0.0)) < -0.2,
		"前甩 pitch<-0.2", str(info_whip.get("rod_pose_pitch")))
	await _tick_frames(8)
	var tip_fly: Vector3 = _rig.rod_tip_world()
	_check("cast.bobber_flying", _rig.bobber_world().distance_to(tip_fly) > 0.4,
		"饵在空中远离竿尖 > 0.4 m", str(_rig.bobber_world().distance_to(tip_fly)))
	await _tick_frames(190)
	var info_rest: Dictionary = _rig.debug_info()
	_check("cast.anim_finished", String(info_rest.get("rod_anim", "x")) == "",
		"抛竿动作收势后交回待机", str(info_rest.get("rod_anim")))
	_check("cast.pitch_neutral", absf(float(info_rest.get("rod_pose_pitch", 1.0))) < 0.05,
		"|pitch|<0.05", str(info_rest.get("rod_pose_pitch")))
	var bob: Vector3 = _rig.bobber_world()
	var bob_visible: bool = (_rig.get_node("Bobber") as Node3D).visible
	_check("cast.bobber_visible", bob_visible, "true", str(bob_visible))
	var flat := Vector2(bob.x - CAST_TARGET.x, bob.z - CAST_TARGET.z)
	_check("cast.landed_xz", flat.length() < 0.15, "< 0.15 m", str(flat.length()))
	_check("cast.landed_y", absf(bob.y) < 0.15, "|y| < 0.15", str(bob.y))
	# 落水后应在水面上做小幅正弦轻浮（不沉底也不飞起）
	var ys: Array = []
	for i in 90:
		_rig.tick(1.0 / 60.0, false)
		ys.append(_rig.bobber_world().y)
	var ymin := 999.0
	var ymax := -999.0
	for y in ys:
		ymin = minf(ymin, float(y))
		ymax = maxf(ymax, float(y))
	_check_range("cast.float_band", ymax - ymin, 0.0, 0.06)
	_check("cast.float_on_water", ymin > -0.05 and ymax < 0.05, "|y| < 0.05", "%s..%s" % [str(ymin), str(ymax)])
	# 水花/水环在落点触发过
	var info: Dictionary = _rig.debug_info()
	_check("cast.splash_fired", int(info.get("splash_events", 0)) >= 1, ">= 1", str(info.get("splash_events", null)))
	_check("cast.ripple_fired", int(info.get("ripple_events", 0)) >= 1, ">= 1", str(info.get("ripple_events", null)))
	# 鱼线几何：首点=竿尖、末点=浮漂挂点、中间有下垂
	_check("cast.line_has_points", bool(info.get("line_has_points", false)), "true", str(info.get("line_has_points", null)))
	var pts: PackedVector3Array = info.get("line_points", PackedVector3Array())
	_check("cast.line_point_count", pts.size() == 15, "15", str(pts.size()))
	if pts.size() == 15:
		var p0: Vector3 = _rig.to_global(pts[0])
		var p_last: Vector3 = _rig.to_global(pts[14])
		var tip_now: Vector3 = _rig.rod_tip_world()
		var anchor: Vector3 = _rig.bobber_world() + Vector3(0.0, 0.055, 0.0)
		_check("cast.line_start_at_tip", p0.distance_to(tip_now) < 0.01, "< 0.01", str(p0.distance_to(tip_now)))
		_check("cast.line_end_at_bobber", p_last.distance_to(anchor) < 0.01, "< 0.01", str(p_last.distance_to(anchor)))
		var mid_p: Vector3 = _rig.to_global(pts[7])
		var straight_mid: Vector3 = (p0 + p_last) * 0.5
		_check("cast.line_sag", mid_p.y < straight_mid.y - 0.01, "中点低于直线 > 0.01", str(straight_mid.y - mid_p.y))
		var line_im: ImmediateMesh = (_rig.get_node("Line") as MeshInstance3D).mesh
		_check("cast.line_one_surface", line_im.get_surface_count() == 1, "1", str(line_im.get_surface_count()))
	# 竿身沿手空间“上-前”
	var dir_world: Vector3 = (_rig.rod_tip_world() - _rig.hand_world()).normalized()
	print("[P9RIG] rod_world_dir=", dir_world)


# =========================================================== 轻啄 / 咬钩 ====

func _nibble_bite_checks() -> void:
	_section("nibble_bite")
	var base_y: float = _rig.bobber_world().y
	_rig.nibble(1.0)
	var dip_min := 999.0
	for i in 24:
		_rig.tick(1.0 / 60.0, false)
		dip_min = minf(dip_min, _rig.bobber_world().y)
	_check("nibble.dip", dip_min < base_y - 0.01, "下沉 > 0.01 m", str(base_y - dip_min))
	# 轻啄是瞬态的：播完回到水面
	await _tick_frames(20)
	_check("nibble.transient", absf(_rig.bobber_world().y) < 0.03, "|y| < 0.03", str(_rig.bobber_world().y))
	# 幂等安全：连发两次不崩，也不会一直沉
	_rig.nibble(0.6)
	_rig.nibble(0.6)
	var dip2 := 999.0
	for i in 24:
		_rig.tick(1.0 / 60.0, false)
		dip2 = minf(dip2, _rig.bobber_world().y)
	_check("nibble.repeat_ok", dip2 < base_y - 0.005, "仍会下沉", str(base_y - dip2))
	await _tick_frames(20)

	var info0: Dictionary = _rig.debug_info()
	var splash0 := int(info0.get("splash_events", 0))
	var ripple0 := int(info0.get("ripple_events", 0))
	var info_bite0: Dictionary = _rig.debug_info()
	_rig.bite()
	_check("bite.anim", String(_rig.debug_info().get("rod_anim", "")) == "bite",
		"rod_anim=bite", str(_rig.debug_info().get("rod_anim")))
	var sink_min := 999.0
	var pitch_min := 99.0
	for i in 45:
		_rig.tick(1.0 / 60.0, false)
		sink_min = minf(sink_min, _rig.bobber_world().y)
		pitch_min = minf(pitch_min, float(_rig.debug_info().get("rod_pose_pitch", 0.0)))
	_check("bite.sink", sink_min < -0.05, "下沉 > 0.05 m", str(sink_min))
	_check("bite.rod_jerk", pitch_min < -0.15, "咬钩时竿尖下抽 pitch<-0.15",
		"%s (splash0=%s)" % [str(pitch_min), str(info_bite0.get("splash_events", 0))])
	var info1: Dictionary = _rig.debug_info()
	_check_eq("bite.splash", splash0 + 1, int(info1.get("splash_events", 0)))
	_check_eq("bite.ripple", ripple0 + 1, int(info1.get("ripple_events", 0)))
	_check("bite.ripple_visible", bool(info1.get("ripple_visible", false)), "true", str(info1.get("ripple_visible", null)))
	_check("bite.idempotent", true, "no crash", "ok")
	# 连发 bite 也不崩
	_rig.bite()
	_rig.bite()
	for i in 60:
		_rig.tick(1.0 / 60.0, false)
	_check_range("bite.recover", _rig.bobber_world().y, -0.03, 0.03)
	var info2: Dictionary = _rig.debug_info()
	_check("bite.ripple_expire", not bool(info2.get("ripple_visible", true)), "false", str(info2.get("ripple_visible", null)))


# =========================================================== 收线 =============

func _reel_checks() -> void:
	_section("reel")
	_rig.start_reel(0.8)
	var info_r0: Dictionary = _rig.debug_info()
	_check("reel.anim", String(info_r0.get("rod_anim", "")) == "reel",
		"rod_anim=reel", str(info_r0.get("rod_anim")))
	var max_lift := -9.0
	var lift_at_20 := 0.0
	for i in 90:
		_rig.tick(1.0 / 60.0, false)
		var pp := float(_rig.debug_info().get("rod_pose_pitch", 0.0))
		max_lift = maxf(max_lift, pp)
		if i == 20:
			lift_at_20 = pp
	_check("reel.lift_pitch", max_lift > 0.4, "收线时抬竿 pitch>0.4", str(max_lift))
	_check("reel.lift_at_20", lift_at_20 > 0.3, "第 21 帧已在抬竿", str(lift_at_20))
	_check("reel.anim_finished", String(_rig.debug_info().get("rod_anim", "x")) == "",
		"收线结束动作归位", str(_rig.debug_info().get("rod_anim")))
	var bob: Vector3 = _rig.bobber_world()
	var tip: Vector3 = _rig.rod_tip_world()
	_check("reel.near_tip", bob.distance_to(tip) < HANG_DROP_MAX, "< %.2f m" % HANG_DROP_MAX, str(bob.distance_to(tip)))
	_check("reel.below_tip", bob.y < tip.y, "浮漂在竿尖下方", "bob.y=%s tip.y=%s" % [str(bob.y), str(tip.y)])
	_check("reel.line_visible", (_rig.get_node("Line") as MeshInstance3D).visible, "true", str((_rig.get_node("Line") as MeshInstance3D).visible))
	# 收线后跟随竿尖（移动持竿手 / 旋转村民，浮漂应跟着动）
	var old_bob := bob
	_holder.rotation.y = 0.5
	_rig.tick(1.0 / 60.0, false)
	var new_bob: Vector3 = _rig.bobber_world()
	_check("reel.follows_hand", old_bob.distance_to(new_bob) > 0.05, "> 0.05 m", str(old_bob.distance_to(new_bob)))
	_holder.rotation.y = 0.0
	_rig.tick(1.0 / 60.0, false)


# =========================================================== 鱼获 =============

func _catch_checks() -> void:
	_section("catch")
	_rig.show_catch("fish_koi", 0.32)
	await _tick_frames(30)
	var catch_node: Node3D = _rig.get_node("Catch") as Node3D
	var fish: MeshInstance3D = _rig.get_node("Catch/Fish") as MeshInstance3D
	_check("catch.visible", catch_node.visible, "true", str(catch_node.visible))
	_check("catch.fish_visible", fish.visible, "true", str(fish.visible))
	_check("catch.mesh_set", fish.mesh != null, "非空", str(fish.mesh))
	if fish.mesh != null:
		var waabb: AABB = fish.global_transform * fish.get_aabb()
		var dim := waabb.size
		var max_dim := maxf(dim.x, maxf(dim.y, dim.z))
		var min_dim := minf(dim.x, minf(dim.y, dim.z))
		_check_range("catch.size_max", max_dim, 0.1, 0.8)
		_check_range("catch.size_min", min_dim, 0.02, 0.8)
		var torso: Node3D = _model_root.call("get_joint", "torso") as Node3D
		var chest: Vector3 = torso.global_position if torso != null else _model_root.global_position + Vector3(0.0, 1.2, 0.0)
		_check("catch.near_chest", waabb.get_center().distance_to(chest) < 1.2, "< 1.2 m", str(waabb.get_center().distance_to(chest)))
		_check("catch.above_ground", waabb.get_center().y > 0.3, "> 0.3", str(waabb.get_center().y))
		# 低模预算：几百面以内
		var arrays: Array = fish.mesh.surface_get_arrays(0) if fish.mesh.get_surface_count() > 0 else []
		if not arrays.is_empty():
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			_check_range("catch.tris", verts.size() / 3.0, 1.0, 700.0)
	var info: Dictionary = _rig.debug_info()
	_check_eq("catch.fish_id", "fish_koi", String(info.get("fish_id", "")))
	_check_range("catch.fish_length", float(info.get("fish_length", 0.0)), 0.25, 0.45)
	var col: Color = info.get("fish_color", Color.BLACK)
	_check("catch.fish_color_from_def", col.is_equal_approx(Color("#e2543f")), "#e2543f", str(col))
	# 鱼获轻微摆动（未暂停时应持续变化）
	var p0: Vector3 = catch_node.position
	await _tick_frames(12)
	_check("catch.bobbing", catch_node.position.distance_to(p0) > 0.001, "> 0.001 m", str(catch_node.position.distance_to(p0)))
	# 隐藏
	_rig.hide_catch()
	await process_frame
	_check("catch.hide_node", not catch_node.visible, "false", str(catch_node.visible))
	_check("catch.hide_mesh", not fish.visible, "false", str(fish.visible))
	# 未知鱼种 / size=0：不崩，走兜底
	_rig.show_catch("fish_not_exists", 0.0)
	await _tick_frames(4)
	var info2: Dictionary = _rig.debug_info()
	_check_range("catch.fallback_length", float(info2.get("fish_length", 0.0)), 0.12, 0.8)
	var col2: Color = info2.get("fish_color", Color.BLACK)
	_check("catch.fallback_color", col2.is_equal_approx(Color(0.86, 0.60, 0.36)), str(Color(0.86, 0.60, 0.36)), str(col2))
	# 各鱼种体长夹在目录 min/max 内
	_rig.show_catch("fish_sardine", 2.0)
	await _tick_frames(2)
	var info3: Dictionary = _rig.debug_info()
	_check("catch.clamp_to_def_max", float(info3.get("fish_length", 0.0)) <= 0.22, "<= 0.22", str(float(info3.get("fish_length", 0.0))))
	_rig.hide_catch()


# =========================================================== 清场 =============

func _clear_checks() -> void:
	_section("clear_all")
	_rig.clear_all()
	await process_frame
	var rod: Node3D = _rig.get_node("Rod") as Node3D
	var line: MeshInstance3D = _rig.get_node("Line") as MeshInstance3D
	var bobber: Node3D = _rig.get_node("Bobber") as Node3D
	var catch_node: Node3D = _rig.get_node("Catch") as Node3D
	var ripple: MeshInstance3D = _rig.get_node("Ripple") as MeshInstance3D
	var splash: CPUParticles3D = _rig.get_node("Splash") as CPUParticles3D
	_check("clear.rod_hidden", not rod.visible, "false", str(rod.visible))
	_check("clear.line_hidden", not line.visible, "false", str(line.visible))
	_check("clear.bobber_hidden", not bobber.visible, "false", str(bobber.visible))
	_check("clear.catch_hidden", not catch_node.visible, "false", str(catch_node.visible))
	_check("clear.ripple_hidden", not ripple.visible, "false", str(ripple.visible))
	_check("clear.splash_stopped", not splash.emitting, "false", str(splash.emitting))
	var info: Dictionary = _rig.debug_info()
	_check("clear.splash_not_emitting", not bool(info.get("splash_emitting", true)), "false", str(info.get("splash_emitting", null)))
	# 幂等：连续清场 / 清场后再 tick 都不崩
	_rig.clear_all()
	_rig.clear_all()
	await _tick_frames(10)
	_rig.tick(1.0 / 60.0, true)
	_check("clear.idempotent", true, "no crash", "ok")
	_check("clear.still_cleared", not line.visible and not bobber.visible, "都隐藏", str([line.visible, bobber.visible]))


# =========================================================== 暂停 =============

func _pause_checks() -> void:
	_section("paused")
	_rig.show_rod(true)
	_rig.set_bobber_visible(true)
	_rig.start_cast(CAST_TARGET, 1.2)
	await _tick_frames(20)
	var bob_paused: Vector3 = _rig.bobber_world()
	# P9 / P6-VISUAL-FIX：竿的朝向现在由“角色前向 + 仰角”决定、握点跟手，所以“暂停冻结”的
	# 正确判据是 **竿相对握点的世界向量不变**（朝向冻结、只跟手平移），而不是“竿尖在手空间不变”。
	var rel0: Vector3 = _rig.rod_tip_world() - _rig.hand_world()
	var dir0: Vector3 = rel0.normalized()
	var pitch0: float = float(_rig.debug_info().get("rod_pose_pitch", 0.0))
	for i in 30:
		_rig.tick(1.0 / 60.0, true)
		await process_frame
	_check("paused.bobber_frozen", _rig.bobber_world().distance_to(bob_paused) < 0.0001, "0", str(_rig.bobber_world().distance_to(bob_paused)))
	var rel1: Vector3 = _rig.rod_tip_world() - _rig.hand_world()
	var dir1: Vector3 = rel1.normalized()
	var pitch1: float = float(_rig.debug_info().get("rod_pose_pitch", 0.0))
	_check("paused.rod_attitude_frozen", absf(dir1.dot(dir0) - 1.0) < 0.001 and absf(pitch1 - pitch0) < 0.001,
		"暂停时竿朝向与仰角冻结", "dot=%.5f pitch %.3f->%.3f" % [dir1.dot(dir0), pitch0, pitch1])
	_check("paused.rod_grip_follows_hand", absf(rel1.length() - rel0.length()) < 0.01,
		"竿长不变（握点仍跟手）", "%.4f -> %.4f" % [rel0.length(), rel1.length()])
	# 恢复后抛竿应继续推进并落水
	await _tick_frames(120)
	var bob_after: Vector3 = _rig.bobber_world()
	var flat := Vector2(bob_after.x - CAST_TARGET.x, bob_after.z - CAST_TARGET.z)
	_check("paused.resume_cast", flat.length() < 0.15 and absf(bob_after.y) < 0.15, "落点", str(bob_after))
	# 暂停时鱼获摆动也应冻结
	_rig.show_catch("fish_koi", 0.3)
	await _tick_frames(10)
	var catch_pos: Vector3 = (_rig.get_node("Catch") as Node3D).position
	for i in 20:
		_rig.tick(1.0 / 60.0, true)
		await process_frame
	_check("paused.catch_frozen", (_rig.get_node("Catch") as Node3D).position.distance_to(catch_pos) < 0.0001, "0", str((_rig.get_node("Catch") as Node3D).position.distance_to(catch_pos)))
	_rig.clear_all()


# =========================================================== 生命周期 =========

func _lifecycle_checks() -> void:
	_section("lifecycle")
	# 每帧不新增节点 / 不新增线面（零分配近似：结构稳定）
	var kids0: int = _rig.get_child_count()
	var line: MeshInstance3D = _rig.get_node("Line") as MeshInstance3D
	_rig.show_rod(true)
	_rig.set_bobber_visible(true)
	_rig.set_bobber_target(Vector3(26.0, 0.0, 12.6))
	await _tick_frames(200)
	var kids1: int = _rig.get_child_count()
	var line_im: ImmediateMesh = line.mesh
	_check_eq("lifecycle.child_count_stable", kids0, kids1)
	_check_eq("lifecycle.line_surface_stable", 1, line_im.get_surface_count())
	var kids: Array = _rig.get_children()
	_check("lifecycle.child_count", kids.size() == 6, "6", str(kids.size()))
	_rig.free()
	await process_frame
	var alive := 0
	for k in kids:
		if is_instance_valid(k):
			alive += 1
	_check_eq("lifecycle.children_freed", 0, alive)
	_check("lifecycle.rig_freed", not is_instance_valid(_rig), "invalid", str(is_instance_valid(_rig)))
	# 释放后再调一次 clear_all 类操作（通过一个已释放引用）不应崩：GDScript 对已释放对象调用会报错，
	# 因此这里只验证“释放即全部子节点释放”这一契约，不再对已释放对象发调用。
