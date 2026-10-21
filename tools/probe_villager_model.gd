extends SceneTree
# =============================================================================
# P7-V4 岛民模型/动画自检探针（headless）
# 运行：
#   godot --headless --path D:/休闲小岛幻境/游戏工程 --script res://tools/probe_villager_model.gd
# 说明：不依赖全局类缓存，统一用 preload 拿到脚本；只读模型，不修改工程其他文件。
# =============================================================================

const MODEL := preload("res://scripts/isle_villager_model.gd")
const MATH := preload("res://scripts/isle_math.gd")
const STUDIO_DIR := "D:/休闲小岛幻境/开发产物/p7v4/model_shots/"

const EXPECTED_CLIPS := {
	"idle": [5.0, true],
	"idle_alt": [5.2, true],
	"walk": [0.88, true],
	"sit_down": [0.80, false],
	"sit_idle": [4.0, true],
	"sit_up": [0.70, false],
	"eat": [3.0, true],
	"lie_down": [1.0, false],
	"sleep": [6.0, true],
	"get_up": [1.0, false],
	"bed_sit_down": [0.80, false],
	"bed_sit_up": [0.70, false],
}

const JOINT_KEYS := [
	"body_pos", "body_roll", "body_tilt", "pelvis", "torso", "neck", "head", "hair",
	"shoulder_l", "shoulder_r", "elbow_l", "elbow_r", "hand_l", "hand_r",
	"hip_l", "hip_r", "knee_l", "knee_r", "foot_l", "foot_r", "eyelid_l", "eyelid_r",
]

const BODY_ROOTS := ["Pelvis", "Torso", "Neck", "Head"]

var _fails: Array = []
var _checks := 0


func _initialize() -> void:
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	if DisplayServer.get_name() != "headless" and user_args.has("--studio"):
		await _run_studio(user_args)
		return
	await process_frame
	var holder := Node3D.new()
	holder.name = "Holder"
	get_root().add_child(holder)

	var built: Dictionary = MODEL.create(0)
	var root: Node3D = built["root"]
	holder.add_child(root)
	await process_frame
	await process_frame

	_check_api(built, root)
	_check_tree_and_joints(root)
	_check_stand_metrics(root)
	_check_scale_and_materials(root)
	_check_tweens(root)
	_check_clips(built, root)
	_check_stats(root)
	_check_bowl(root)
	_check_hair_switch(root)
	_check_sit_pose(built, root)
	_check_lie_pose(built, root)
	_check_walk(built, root)
	_check_bed_sit(built, root)
	_check_boundaries(built, root)
	_check_runtime(built, root)

	print("")
	if _fails.is_empty():
		print("[V4] RESULT PASS (%d checks)" % _checks)
	else:
		print("[V4] RESULT FAIL (%d checks, %d failed)" % [_checks, _fails.size()])
		for f in _fails:
			print("[V4] FAILED: " + String(f))
	quit(0 if _fails.is_empty() else 1)


# =============================================================================
# 检查项
# =============================================================================

func _check_api(built: Dictionary, root: Node3D) -> void:
	for key in ["root", "anim", "height", "hair_style"]:
		_ok(built.has(key), "create() 返回键 %s" % key)
	_ok(is_equal_approx(float(built["height"]), 1.5), "create() height==1.50", str(built["height"]))
	_ok(built["root"] == root and root.name == "Villager", "root 名称为 Villager")
	_ok(root.get_meta("isle_villager", false) == true, "root 带 isle_villager 标记")
	_ok(root.get_meta("no_batch", false) == true, "root 带 no_batch 标记")
	var anim := built["anim"] as AnimationPlayer
	_ok(anim != null and anim.name == "Anim", "AnimationPlayer 节点名 'Anim'")
	_ok(anim != null and anim.get_parent() == root, "Anim 挂在 root 下")
	_ok(anim != null and anim.root_node == NodePath(".."), "Anim root_node == '..'")
	_ok(anim != null and anim.get_animation_library_list().size() == 1, "仅一个 AnimationLibrary（默认库）")


func _check_tree_and_joints(root: Node3D) -> void:
	var missing: Array = []
	for key in JOINT_KEYS:
		if root.get_joint(key) == null:
			missing.append(key)
	_ok(missing.is_empty(), "22 个关节齐全", str(missing))
	_ok(root.get_joint("pelvis") is Node3D, "get_joint('pelvis') 返回 Node3D")
	_ok(root.get_joint("nope") == null, "get_joint(未知) 返回 null")
	# 关节层级
	var pelvis : Node3D = root.get_joint("pelvis")
	var torso : Node3D = root.get_joint("torso")
	var head : Node3D = root.get_joint("head")
	var knee_l : Node3D = root.get_joint("knee_l")
	var foot_l : Node3D = root.get_joint("foot_l")
	_ok(torso.get_parent() == pelvis, "Pelvis→Torso 层级")
	_ok(head.get_parent().name == "Neck", "Head 父节点是 Neck")
	_ok(knee_l.get_parent().name == "HipL", "KneeL 父节点是 HipL")
	_ok(foot_l.get_parent() == knee_l, "FootL 父节点是 KneeL")
	var hand_l : Node3D = root.get_joint("hand_l")
	_ok(hand_l.get_parent().name == "ElbowL", "HandL 父节点是 ElbowL")
	# 节点树名称快照（供 Lead 核对）
	var names: Array = []
	for n in _walk(root):
		if n is Node3D and n != root:
			names.append(String(n.name))
	print("[V4] NODES(" + str(names.size()) + "): " + ", ".join(names))



func _check_stand_metrics(root: Node3D) -> void:
	var m: Dictionary = MODEL.measure(root)
	print("[V4] STAND aabb=%s min_y=%.4f height=%.4f meshes=%d surfaces=%d tris=%d materials=%d dc=%d" % [
		str(m["aabb"]), float(m["min_y"]), float(m["height"]), int(m["meshes"]),
		int(m["surfaces"]), int(m["tris"]), int(m["materials"]), int(m["dc_est"]),
	])
	_ok(absf(float(m["height"]) - 1.5) <= 0.01, "站立总高 1.500±0.01", "%.4f" % m["height"])
	_ok(absf(float(m["min_y"])) <= 0.005, "鞋底 y≈0（脚底贴地）", "%.4f" % m["min_y"])
	# 头身比 = 总高(含发顶) / 头部高度(下巴→发顶，与 4.2–5 头身契约一致)
	var head_aabb := _mesh_world_aabb(root.get_joint("head") as MeshInstance3D)
	var hair_aabb := _mesh_world_aabb(root.get_joint("hair").get_child(0) as MeshInstance3D)
	var head_h := (hair_aabb.position.y + hair_aabb.size.y) - head_aabb.position.y
	var ratio := 1.5 / head_h
	print("[V4] HEAD 下巴y=%.4f 发顶y=%.4f 头高=%.4f ratio=%.2f" % [
		head_aabb.position.y, hair_aabb.position.y + hair_aabb.size.y, head_h, ratio,
	])
	_ok(ratio >= 4.2 and ratio <= 5.0, "头身比 4.2–5.0", "%.2f" % ratio)
	_ok(head_h >= 0.30 and head_h <= 0.36, "头部高度 0.30–0.36 m", "%.3f" % head_h)
	# 朝向：局部 -Z 为正面（眼睑/鼻/嘴在 head 的 -Z 侧）
	var eyelid : Node3D = root.get_joint("eyelid_l")
	_ok(eyelid.position.z < -0.05, "面部特征在 -Z 侧（局部朝向）", "%.3f" % eyelid.position.z)
	var pelvis_y := (root.get_joint("pelvis") as Node3D).global_position.y
	_ok(absf(pelvis_y - 0.760) <= 0.01, "站立骨盆中心 y≈0.760", "%.3f" % pelvis_y)
	var hair_top := hair_aabb.position.y + hair_aabb.size.y
	_ok(absf(hair_top - 1.5) <= 0.01, "发型轮廓顶点=总高 1.500（两发型共享发帽顶）", "%.4f" % hair_top)

func _check_scale_and_materials(root: Node3D) -> void:
	var bad_scale: Array = []
	var mats := {}
	var body_meshes := 0
	for n in _walk(root):
		var n3 := n as Node3D
		if n3 != null and not n3.scale.is_equal_approx(Vector3.ONE):
			bad_scale.append(String(n.name))
		var mi := n as MeshInstance3D
		if mi == null or not mi.is_visible_in_tree() or mi.name == "Shadow":
			continue
		body_meshes += 1
		var mat := mi.material_override
		if mat != null:
			mats[mat] = true
	var pelvis_mi : Node3D = root.get_joint("pelvis") as MeshInstance3D
	var toon := pelvis_mi.material_override as ShaderMaterial
	var uv = null
	if toon != null:
		uv = toon.get_shader_parameter("use_vertex_color")
	_ok(bad_scale.is_empty(), "无节点 scale≠1（禁整节点缩放）", str(bad_scale))
	_ok(mats.size() == 1, "16 个可见身体网格共享同一 toon 材质实例", str(mats.size()))
	_ok(uv != null and float(uv) >= 0.5, "toon 材质 use_vertex_color=1（顶点色承载多层色）")
	_ok(body_meshes == 16, "可见角色本体网格 16（14 关节网格 + 2 个可动眼睑；手/脖已并入前臂/躯干）", str(body_meshes))
	_ok(int(root.stats()["material_count"]) == 2, "stats 材质实例 2（toon+阴影）", str(root.stats()["material_count"]))
func _check_tweens(root: Node3D) -> void:
	_ok(get_processed_tweens().is_empty(), "无常驻 Tween")
	var anim := root.get_node_or_null("Anim") as AnimationPlayer
	var track_sum := 0
	if anim != null:
		for name in anim.get_animation_list():
			track_sum += anim.get_animation(name).get_track_count()
	_ok(track_sum == 276, "12 条剪辑共 276 条轨道（23×12，全轨道覆盖避免姿态泄漏）", str(track_sum))


func _check_clips(built: Dictionary, root: Node3D) -> void:
	var anim := built["anim"] as AnimationPlayer
	var names: PackedStringArray = root.get_animation_names()
	print("[V4] CLIPS: " + ", ".join(names))
	_ok(names.size() == EXPECTED_CLIPS.size(), "剪辑数量 == %d" % EXPECTED_CLIPS.size(), str(names.size()))
	for clip in EXPECTED_CLIPS:
		var want: Array = EXPECTED_CLIPS[clip]
		_ok(names.has(clip), "剪辑存在: " + clip)
		var a := anim.get_animation(clip)
		_ok(a != null, "取到 Animation: " + clip)
		if a == null:
			continue
		var loop_expected: bool = want[1]
		_ok(absf(a.length - float(want[0])) <= 0.001, "时长 %s == %.2fs" % [clip, want[0]], "%.3f" % a.length)
		_ok((a.loop_mode == Animation.LOOP_LINEAR) == loop_expected, "循环模式 %s == %s" % [clip, str(loop_expected)], str(a.loop_mode))
		print("[V4] CLIP %-9s len=%.2f loop=%s tracks=%d" % [clip, a.length, str(a.loop_mode == Animation.LOOP_LINEAR), a.get_track_count()])


func _check_stats(root: Node3D) -> void:
	var s: Dictionary = root.stats()
	print("[V4] STATS " + str(s))
	for key in ["mesh_count", "material_count", "triangles", "aabb", "dc_estimate"]:
		_ok(s.has(key), "stats() 键 %s" % key)
	_ok(int(s["triangles"]) <= 6500, "三角面 ≤6500", str(s["triangles"]))
	_ok(int(s["dc_estimate"]) <= 40, "Draw Call 估算 ≤40（含描边）", str(s["dc_estimate"]))
	_ok(int(s["material_count"]) <= 8, "材质实例 ≤8", str(s["material_count"]))
	_ok(int(s["mesh_count"]) <= 16, "stats.mesh_count ≤16（角色本体网格，阴影贴片不计）", str(s["mesh_count"]))
	_ok(float((s["aabb"] as Vector3).y) > 1.49, "stats aabb 高度 1.50")
	_tris_by_mesh(root)


## 逐网格三角面（调优预算用；不计入断言）
func _tris_by_mesh(root: Node) -> void:
	for n in _walk(root):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var t := 0
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			var idx = arr[Mesh.ARRAY_INDEX]
			if idx != null and (idx as PackedInt32Array).size() > 0:
				t += (idx as PackedInt32Array).size() / 3
			else:
				t += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		print("[V4] MESH %-10s tris=%d" % [String(mi.name), t])



func _check_bowl(root: Node3D) -> void:
	var bowl := root.get_node_or_null("Bowl") as MeshInstance3D
	_ok(bowl != null, "Bowl 节点存在")
	if bowl == null:
		return
	_ok(not bowl.visible, "Bowl 默认隐藏")
	var before: Dictionary = root.stats()
	root.set_bowl_visible(true)
	var after: Dictionary = root.stats()
	_ok(bowl.visible, "set_bowl_visible(true) 生效")
	_ok(int(after["dc_estimate"]) == int(before["dc_estimate"]) + 1, "碗显示后 DC +1（碗不带描边）", "%d→%d" % [before["dc_estimate"], after["dc_estimate"]])
	_ok(int(after["mesh_count"]) == int(before["mesh_count"]) + 1, "碗显示后 mesh +1")
	root.set_bowl_visible(false)
	# 坐姿对齐：另建一份实例，root 放到座面(0.40)+0.02，检查碗底世界高度≈餐桌 0.65
	var sit_built: Dictionary = MODEL.create(0)
	var sr: Node3D = sit_built["root"]
	get_root().add_child(sr)
	var anim := sit_built["anim"] as AnimationPlayer
	anim.play("sit_idle")
	anim.seek(0.0, true)
	sr.position = Vector3(0.0, 0.42, 0.0)
	sr.set_bowl_visible(true)
	var rb := _mesh_world_aabb(sr.get_node("Bowl") as MeshInstance3D)
	print("[V4] BOWL sit 世界 y=%.3f..%.3f" % [rb.position.y, rb.position.y + rb.size.y])
	_ok(absf(rb.position.y - 0.65) <= 0.06, "碗底≈餐桌高 0.65（坐姿，root=座面+0.02）", "%.3f" % rb.position.y)
	_ok(rb.position.y + rb.size.y <= 0.72, "碗口不高于 0.72", "%.3f" % (rb.position.y + rb.size.y))
	get_root().remove_child(sr)
	sr.free()
func _check_hair_switch(root: Node3D) -> void:
	var m0: Dictionary = MODEL.measure(root)
	var body0: Dictionary = MODEL.measure(root, {"skip_hair": true})
	var short_hair := root.get_node_or_null("BodyPos/BodyRoll/BodyTilt/Pelvis/Torso/Neck/Head/Hair/HairShort")
	var medium_hair := root.get_node_or_null("BodyPos/BodyRoll/BodyTilt/Pelvis/Torso/Neck/Head/Hair/HairMedium")
	_ok(short_hair != null and medium_hair != null, "两种发型都是预建节点")
	_ok(short_hair.visible and not medium_hair.visible, "style0：短发型可见")
	root.set_hair_style(1)
	_ok(not short_hair.visible and medium_hair.visible, "style1：中长发可见")
	print("[V4] STATS_HAIR1 " + str(root.stats()))
	var m1: Dictionary = MODEL.measure(root)
	var body1: Dictionary = MODEL.measure(root, {"skip_hair": true})
	_ok(is_equal_approx(float(m0["height"]), float(m1["height"])), "切发型总高不变", "%.4f/%.4f" % [m0["height"], m1["height"]])
	_ok(body0["aabb"].is_equal_approx(body1["aabb"]), "切发型身体 AABB 不变", str(body1["aabb"]))
	_ok(int(m0["materials"]) == int(m1["materials"]), "切发型材质数不增长")
	_ok(int(m0["meshes"]) == int(m1["meshes"]), "切发型网格数不增长", "%d/%d" % [m0["meshes"], m1["meshes"]])
	_ok(int(m0["dc_est"]) == int(m1["dc_est"]), "切发型 DC 不变", "%d/%d" % [m0["dc_est"], m1["dc_est"]])
	# 关节世界坐标不变
	var j0: Array = []
	for key in JOINT_KEYS:
		var j : Node3D = root.get_joint(key)
		if j != null:
			j0.append([key, j.global_transform])
	root.set_hair_style(0)
	var same := true
	var idx := 0
	for key in JOINT_KEYS:
		var j : Node3D = root.get_joint(key)
		if j == null:
			continue
		var t0: Transform3D = j0[idx][1]
		if not t0.is_equal_approx(j.global_transform):
			same = false
		idx += 1
	_ok(same, "切发型关节世界变换完全一致")
	print("[V4] HAIR  0: h=%.4f meshes=%d dc=%d | 1: h=%.4f meshes=%d dc=%d" % [
		m0["height"], m0["meshes"], m0["dc_est"], m1["height"], m1["meshes"], m1["dc_est"],
	])



func _check_sit_pose(built: Dictionary, root: Node3D) -> void:
	var anim := built["anim"] as AnimationPlayer
	anim.play("sit_idle")
	anim.seek(2.0, true)
	var pelvis : Node3D = root.get_joint("pelvis")
	var knee : Node3D = root.get_joint("knee_l") as Node3D
	var mesh: Dictionary = MODEL.measure(root)
	var pb := _mesh_world_aabb(pelvis as MeshInstance3D)
	print("[V4] SIT pelvis_y=%.3f body_min_y=%.3f knee.z=%.3f aabb=%s pelvis_bottom=%.3f" % [
		pelvis.global_position.y, mesh["min_y"], knee.global_position.z, str(mesh["aabb"]), pb.position.y,
	])
	_ok(absf(pelvis.global_position.y - 0.075) <= 0.01, "坐姿骨盆在 root 上方 0.075（臀底压进软坐垫 2cm）", "%.3f" % pelvis.global_position.y)
	_ok(absf(float(mesh["min_y"]) + 0.42) <= 0.03, "坐姿双脚相对 root y≈-0.42（root 放 0.42 时踩地）", "%.3f" % mesh["min_y"])
	_ok(knee.global_position.z < -0.25, "坐姿膝盖朝 -Z 前伸", "%.3f" % knee.global_position.z)
	_ok(root.get_joint("head").global_position.y > pelvis.global_position.y + 0.35, "坐姿头明显高于骨盆", "%.3f" % root.get_joint("head").global_position.y)
	_ok(pb.position.y >= -0.05, "坐姿臀部不穿到座面以下", "%.3f" % pb.position.y)
	var shadow := root.get_node_or_null("Shadow") as MeshInstance3D
	_ok(shadow != null and not shadow.visible, "坐姿隐藏地面阴影 blob")
	# 眨眼覆盖：idle 中段闭眼
	anim.play("idle")
	anim.seek(2.27, true)
	var eyelid : Node3D = root.get_joint("eyelid_l")
	_ok(eyelid.rotation.x > -0.3, "idle 内嵌眨眼（2.27s 闭眼）", "%.3f" % eyelid.rotation.x)
	anim.seek(2.90, true)
	_ok(eyelid.rotation.x < -1.0, "idle 眨眼后睁开", "%.3f" % eyelid.rotation.x)
func _check_lie_pose(built: Dictionary, root: Node3D) -> void:
	var anim := built["anim"] as AnimationPlayer
	anim.play("sleep")
	anim.seek(0.0, true)
	var pelvis : Node3D = root.get_joint("pelvis")
	var head : Node3D = root.get_joint("head")
	var foot : Node3D = root.get_joint("foot_l")
	var mesh: Dictionary = MODEL.measure(root)
	var up := pelvis.global_basis.y.dot(Vector3.UP)
	print("[V4] LIE pelvis=(%.3f,%.3f,%.3f) pelvis.up·UP=%.3f head.z=%.3f foot.z=%.3f body_min_y=%.3f" % [
		pelvis.global_position.x, pelvis.global_position.y, pelvis.global_position.z,
		up, head.global_position.z, foot.global_position.z, float(mesh["min_y"]),
	])
	_ok(absf(pelvis.global_position.y - 0.095) <= 0.02, "卧姿骨盆在 root 上方 0.095（背部贴床垫面）", "%.3f" % pelvis.global_position.y)
	_ok(up < 0.15, "卧姿身体水平（骨盆上轴不再朝 UP）", "%.3f" % up)
	_ok(head.global_position.z < -0.35, "卧姿头朝模型 -Z", "%.3f" % head.global_position.z)
	_ok(foot.global_position.z > 0.45, "卧姿脚朝 +Z", "%.3f" % foot.global_position.z)
	_ok(absf(float(mesh["min_y"]) + 0.02) <= 0.03, "卧姿全身贴床垫面且不穿模（root 放在床垫顶+0.02，min_y≈-0.02）", "%.3f" % mesh["min_y"])
	# 睡姿 ≠ 直立旋转 90°：右膝屈起 + 头侧转 + 闭眼
	var knee_r : Node3D = root.get_joint("knee_r")
	_ok(absf(knee_r.rotation.x) > 0.5, "睡姿右膝屈起（非整体旋转躺平）", "%.2f" % knee_r.rotation.x)
	_ok(absf(head.rotation.z) > 0.08 or absf((root.get_joint("neck") as Node3D).rotation.z) > 0.08, "睡姿头部侧转", "head.z=%.2f neck.z=%.2f" % [head.rotation.z, (root.get_joint("neck") as Node3D).rotation.z])
	var eyelid : Node3D = root.get_joint("eyelid_l")
	_ok(absf(eyelid.rotation.x) < 0.3, "睡姿闭眼", "%.2f" % eyelid.rotation.x)
	# 循环呼吸：body_pos.y 在 sleep 中有约 6mm 起伏（root 空间 y 就是世界竖直方向）
	var body_pos : Node3D = root.get_joint("body_pos")
	var samples: Array = []
	anim.seek(0.0, true)
	samples.append(body_pos.position.y)
	anim.seek(1.5, true)
	samples.append(body_pos.position.y)
	anim.seek(3.0, true)
	samples.append(body_pos.position.y)
	var dz: float = float(samples[1]) - float(samples[0])
	print("[V4] SLEEP breath dy=%.4f samples=%s" % [dz, str(samples)])
	_ok(absf(dz) >= 0.004, "睡姿呼吸有起伏（body_pos.y 极轻呼吸）", "%.4f" % dz)


func _check_walk(built: Dictionary, root: Node3D) -> void:
	var anim := built["anim"] as AnimationPlayer
	var body_pos : Node3D = root.get_joint("body_pos")
	var ys: Array = []
	var phases := [0.0, 0.22, 0.44, 0.66]
	for t in phases:
		anim.play("walk")
		anim.seek(t, true)
		ys.append(body_pos.position.y)
	# 摆臂/摆腿只在 contact 帧采样（0.0 / 0.44），passing 帧手臂回中
	anim.play("walk")
	anim.seek(0.0, true)
	var hip_l := (root.get_joint("hip_l") as Node3D).rotation.x
	var hip_r := (root.get_joint("hip_r") as Node3D).rotation.x
	var sh_l := (root.get_joint("shoulder_l") as Node3D).rotation.x
	var sh_r := (root.get_joint("shoulder_r") as Node3D).rotation.x
	anim.seek(0.44, true)
	var hip_l2 := (root.get_joint("hip_l") as Node3D).rotation.x
	var hip_r2 := (root.get_joint("hip_r") as Node3D).rotation.x
	var sh_l2 := (root.get_joint("shoulder_l") as Node3D).rotation.x
	var sh_r2 := (root.get_joint("shoulder_r") as Node3D).rotation.x
	var bob_span: float = 0.0
	for i in ys.size():
		bob_span = maxf(bob_span, absf(float(ys[i]) - float(ys[0])))
	print("[V4] WALK body_y=%s bob=%.4f hip_l=%.2f hip_r=%.2f sh_l=%.2f sh_r=%.2f root_pos=%s" % [
		str(ys), bob_span, hip_l, hip_r, sh_l, sh_r, str(root.position),
	])
	_ok(hip_l * hip_r < 0.0, "walk 双腿反向摆动", "%.2f/%.2f" % [hip_l, hip_r])
	_ok(sh_l * sh_r < 0.0, "walk 双臂反向摆动", "%.2f/%.2f" % [sh_l, sh_r])
	_ok(hip_l * sh_l < 0.0, "walk 同侧手臂与腿反相", "%.2f/%.2f" % [hip_l, sh_l])
	_ok(hip_l2 * hip_l < 0.0 and sh_l2 * sh_l < 0.0, "walk 后半周期左右反相（0.44s）", "%.2f/%.2f" % [hip_l2, sh_l2])
	_ok(bob_span > 0.01, "walk 躯干有起伏", "%.4f" % bob_span)
	_ok(root.position.is_equal_approx(Vector3.ZERO), "walk 原地（root 不位移）", str(root.position))
	_ok(absf(hip_l) < 0.6 and absf(hip_r) < 0.6, "walk 摆腿幅度自然（<0.6rad）")



## 坐床沿：报告骨盆网格最低点相对 root 的偏移（控制器据此把 root 放到床垫上不陷进去），
## 并确认 lie_down 首帧逐轨道等于 _bed_sit()。
func _check_bed_sit(built: Dictionary, root: Node3D) -> void:
	var anim := built["anim"] as AnimationPlayer
	anim.play("bed_sit_down")
	anim.seek(anim.get_animation("bed_sit_down").length - 0.0001, true)
	var bed_pose: Dictionary = _pose_snapshot(root)
	var pelvis := root.get_joint("pelvis") as MeshInstance3D
	var foot := root.get_joint("foot_l") as Node3D
	var pel_aabb := _mesh_world_aabb(pelvis)
	var root_y := root.global_position.y
	var pelvis_min_rel: float = pel_aabb.position.y - root_y
	var pelvis_max_rel: float = pel_aabb.position.y + pel_aabb.size.y - root_y
	# 脚底相对 root：取鞋底网格最低点
	var sole_min := INF
	for n in _walk(foot):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		sole_min = minf(sole_min, _mesh_world_aabb(mi).position.y - root_y)
	print("[V4] BED_SIT pelvis_bottom_rel_root=%.3f pelvis_top_rel_root=%.3f foot_bottom_rel_root=%.3f" % [pelvis_min_rel, pelvis_max_rel, sole_min])
	_ok(pelvis_min_rel >= -0.09 and pelvis_min_rel <= -0.02, "坐床沿骨盆网格底相对 root 约 -0.04~-0.06（不陷床垫）", "%.3f" % pelvis_min_rel)
	_ok(sole_min < -0.20, "坐床沿双腿自然垂下（鞋底低于 root）", "%.3f" % sole_min)
	# lie_down 首帧必须逐轨道等于 bed_sit（末帧）
	anim.play("lie_down")
	anim.seek(0.0, true)
	var lie_start: Dictionary = _pose_snapshot(root)
	_ok(_pose_diff(lie_start, bed_pose) <= 0.0005, "lie_down 首帧逐轨道 == bed_sit_down 末帧", "maxdiff=%.4f" % _pose_diff(lie_start, bed_pose))


func _check_boundaries(built: Dictionary, root: Node3D) -> void:
	var anim := built["anim"] as AnimationPlayer
	var pairs := [
		["sit_down", "sit_idle", true],
		["sit_up", "sit_idle", false],
		["sit_up", "idle", true],
		["lie_down", "sleep", true],
		["get_up", "sleep", false],
		["get_up", "idle", true],
		["bed_sit_down", "lie_down", true],
		["bed_sit_down", "idle", false],
		["bed_sit_up", "lie_down", false],
		["bed_sit_up", "idle", true],
	]
	for p in pairs:
		var a_name: String = p[0]
		var b_name: String = p[1]
		var ends_at_b: bool = p[2]
		var anim_self := anim
		anim_self.play(b_name)
		anim_self.seek(0.0, true)
		var pose_b: Dictionary = _pose_snapshot(root)
		anim_self.play(a_name)
		var len_a: float = anim_self.get_animation(a_name).length
		anim_self.seek(len_a - 0.0001 if ends_at_b else 0.0, true)
		var pose_a: Dictionary = _pose_snapshot(root)
		var diff := _pose_diff(pose_a, pose_b)
		var label: String
		if ends_at_b:
			label = "%s 末帧 == %s 首帧" % [a_name, b_name]
		else:
			label = "%s 首帧 == %s 首帧" % [a_name, b_name]
		_ok(diff <= 0.02, label, "maxdiff=%.4f" % diff)
	# loop 剪辑首尾同帧（walk 除外，walk 由 _check_walk 覆盖）
	for clip in ["idle", "idle_alt", "sit_idle", "eat", "sleep"]:
		anim.play(clip)
		anim.seek(0.0, true)
		var first: Dictionary = _pose_snapshot(root)
		anim.seek(anim.get_animation(clip).length - 0.0001, true)
		var last: Dictionary = _pose_snapshot(root)
		var d := _pose_diff(first, last)
		_ok(d <= 0.02, "loop 剪辑首尾无缝: " + clip, "maxdiff=%.4f" % d)
func _check_runtime(built: Dictionary, root: Node3D) -> void:
	var anim := built["anim"] as AnimationPlayer
	var mesh_ids: Array = []
	var mesh_nodes := 0
	for n in _walk(root):
		var mi := n as MeshInstance3D
		if mi != null and mi.mesh != null:
			mesh_nodes += 1
			mesh_ids.append(mi.mesh.get_instance_id())
	# 连续 walk 20 圈 + idle 10 秒，步进 1/60
	anim.play("walk")
	var step := 1.0 / 60.0
	var frames := int(ceil(20.0 * 0.88 / step)) + int(ceil(10.0 / step))
	anim.play("idle")
	anim.seek(0.0, true)
	anim.play("walk")
	var nan := false
	var switched := false
	for i in frames:
		anim.advance(step)
		if i % 90 == 0:
			for key in JOINT_KEYS:
				var j : Node3D = root.get_joint(key)
				if j != null and (not j.position.is_finite() or not j.rotation.is_finite() or not j.scale.is_finite()):
					nan = true
		if i == int(ceil(20.0 * 0.88 / step)):
			anim.play("idle")
			switched = true
	var cur := String(anim.current_animation)
	_ok(anim.is_playing() or cur == "idle", "长时间步进后仍在播放", cur)
	_ok(not nan, "长时间播放无 NaN/Inf 变换")
	var mesh_nodes2 := 0
	var ids2: Array = []
	for n in _walk(root):
		var mi := n as MeshInstance3D
		if mi != null and mi.mesh != null:
			mesh_nodes2 += 1
			ids2.append(mi.mesh.get_instance_id())
	_ok(mesh_nodes == mesh_nodes2, "长时间播放不增删网格节点", "%d/%d" % [mesh_nodes, mesh_nodes2])
	_ok(ids2 == mesh_ids, "网格资源未被重建（instance id 不变）")
	_ok(switched and cur == "idle", "walk→idle 可正常切换", cur)
	var m: Dictionary = MODEL.measure(root)
	_ok(float(m["tris"]) <= 6500, "长时间播放后三角面数不变（无每帧生成）", str(m["tris"]))


# =============================================================================
# 工具
# =============================================================================

func _ok(cond: bool, label: String, detail: String = "") -> void:
	_checks += 1
	if cond:
		print("[V4] PASS " + label + ("" if detail.is_empty() else "  (" + detail + ")"))
	else:
		print("[V4] FAIL " + label + ("" if detail.is_empty() else "  (" + detail + ")"))
		_fails.append(label + ("" if detail.is_empty() else " (" + detail + ")"))


func _min_arr(arr: Array) -> float:
	var m: float = INF
	for v in arr:
		m = minf(m, float(v))
	return m


func _walk(n: Node) -> Array:
	var out: Array = []
	var stack: Array = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		out.append(cur)
		for c in cur.get_children():
			stack.append(c)
	return out


func _mesh_world_aabb(mi: MeshInstance3D) -> AABB:
	if mi == null or mi.mesh == null:
		return AABB()
	var box := mi.mesh.get_aabb()
	var xf := mi.global_transform
	var acc := AABB()
	var has := false
	for i in 8:
		var p := xf * box.get_endpoint(i)
		if has:
			acc = acc.expand(p)
		else:
			acc = AABB(p, Vector3.ZERO)
			has = true
	return acc


func _pose_snapshot(root: Node3D) -> Dictionary:
	var out := {}
	for key in JOINT_KEYS:
		var j : Node3D = root.get_joint(key)
		if j == null:
			continue
		out[key] = j.transform
	return out


func _pose_diff(a: Dictionary, b: Dictionary) -> float:
	var worst := 0.0
	for key in a:
		if not b.has(key):
			continue
		var ta: Transform3D = a[key]
		var tb: Transform3D = b[key]
		var dp := ta.origin.distance_to(tb.origin)
		var dq := 0.0
		for axis in 3:
			dq = maxf(dq, absf(ta.basis[axis].angle_to(tb.basis[axis])))
		worst = maxf(worst, maxf(dp, dq))
	return worst


func add_child_root(n: Node) -> void:
	get_root().add_child(n)


# =============================================================================
# 工作室截图模式（真实窗口，仅开发期肉眼验收；headless 自检路径完全不受影响）
# 运行（用户参数前加 --）：
#   Godot...console.exe --path D:/休闲小岛幻境/游戏工程 --resolution 1100x900 \
#     --script res://tools/probe_villager_model.gd -- --studio --only=v_front,v_face_close --hair=0
# 产物：开发产物/p7v4/model_shots/*.png
# =============================================================================

func _run_studio(user_args: PackedStringArray) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1100, 900))
	var only: Array = []
	var hair := 0
	for a in user_args:
		var s := String(a)
		if s.begins_with("--only="):
			for t in s.substr(7).split(","):
				var tt := String(t).strip_edges()
				if tt != "":
					only.append(tt)
		elif s.begins_with("--hair="):
			hair = int(s.substr(7))
	DirAccess.make_dir_recursive_absolute(STUDIO_DIR)
	_setup_studio_globals()

	var stage := Node3D.new()
	stage.name = "Studio"
	get_root().add_child(stage)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.70, 0.78)
	we.environment = env
	stage.add_child(we)

	# 地面 / 椅子 / 床垫代理：只用于判断姿态与比例，不参与角色统计
	_studio_proxy(stage, Vector3(10.0, 0.02, 10.0), Vector3(0.0, -0.01, 0.0), Color(0.58, 0.63, 0.57))
	var chair := _studio_proxy(stage, Vector3(0.34, 0.045, 0.34), Vector3(0.0, 0.3775, 0.02), Color(0.52, 0.33, 0.26))
	var chair_back := _studio_proxy(stage, Vector3(0.34, 0.34, 0.045), Vector3(0.0, 0.56, 0.20), Color(0.52, 0.33, 0.26))
	var bed := _studio_proxy(stage, Vector3(0.95, 0.45, 1.90), Vector3(0.0, 0.225, 0.0), Color(0.74, 0.71, 0.65))
	var pillow := _studio_proxy(stage, Vector3(0.34, 0.11, 0.22), Vector3(0.0, 0.505, -0.55), Color(0.88, 0.86, 0.80))
	chair.visible = false
	chair_back.visible = false
	bed.visible = false
	pillow.visible = false

	var holder := Node3D.new()
	stage.add_child(holder)
	var built: Dictionary = MODEL.create(hair)
	var root: Node3D = built["root"]
	holder.add_child(root)
	var anim: AnimationPlayer = built["anim"]

	var cam := Camera3D.new()
	cam.fov = 36.0
	cam.near = 0.02
	cam.far = 30.0
	get_root().add_child(cam)
	cam.current = true

	await process_frame
	var sun_world := Vector3(0.42, 0.62, -0.66).normalized()
	for shot in _studio_shot_list():
		var nm := String(shot["name"])
		if not only.is_empty() and not only.has(nm):
			continue
		holder.position = shot.get("root_pos", Vector3.ZERO)
		anim.play(String(shot.get("clip", "idle")))
		anim.seek(float(shot.get("t", 0.0)), true)
		anim.speed_scale = 0.0
		root.call("set_hair_style", int(shot.get("hair", hair)))
		root.call("set_bowl_visible", bool(shot.get("bowl", false)))
		var use_chair := bool(shot.get("chair", false))
		chair.visible = use_chair
		chair_back.visible = use_chair
		var use_bed := bool(shot.get("bed", false))
		bed.visible = use_bed
		pillow.visible = use_bed
		cam.position = shot["cam_pos"]
		cam.look_at(shot["cam_look"])
		RenderingServer.global_shader_parameter_set("g_sun_dir_view",
			(cam.global_transform.basis.inverse() * sun_world).normalized())
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var img := get_root().get_texture().get_image()
		var path := STUDIO_DIR + nm + ".png"
		img.save_png(path)
		print("[V4STUDIO] ", nm, " -> ", path, " ", img.get_width(), "x", img.get_height(),
			" stats=", root.call("stats"))
	print("[V4STUDIO] DONE")
	quit(0)


func _studio_proxy(parent: Node3D, size: Vector3, pos: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = MATH.toon_material(col, {"rim": 0.0})
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _studio_shot_list() -> Array:
	var front := Vector3(0.0, 0.82, -2.45)
	var look := Vector3(0.0, 0.78, 0.0)
	var sit_root := Vector3(0.0, 0.42, 0.0)
	var bed_root := Vector3(0.0, 0.47, 0.0)
	return [
		{"name": "v_front", "clip": "idle", "t": 0.0, "cam_pos": front, "cam_look": look},
		{"name": "v_side", "clip": "idle", "t": 0.0, "cam_pos": Vector3(-2.45, 0.82, 0.0), "cam_look": look},
		{"name": "v_back", "clip": "idle", "t": 0.0, "cam_pos": Vector3(0.0, 0.82, 2.45), "cam_look": look},
		{"name": "v_34", "clip": "idle", "t": 0.0, "cam_pos": Vector3(-1.55, 1.05, -1.85), "cam_look": Vector3(0.0, 0.82, 0.0)},
		{"name": "v_face_close", "clip": "idle", "t": 0.0, "cam_pos": Vector3(0.0, 1.335, -0.72), "cam_look": Vector3(0.0, 1.315, 0.0)},
		{"name": "v_face_34", "clip": "idle", "t": 0.0, "cam_pos": Vector3(-0.46, 1.36, -0.62), "cam_look": Vector3(0.0, 1.30, 0.0)},
		{"name": "v_hair0", "clip": "idle", "t": 0.0, "hair": 0, "cam_pos": Vector3(0.42, 1.40, -0.62), "cam_look": Vector3(0.0, 1.33, 0.0)},
		{"name": "v_hair1", "clip": "idle", "t": 0.0, "hair": 1, "cam_pos": Vector3(0.42, 1.40, -0.62), "cam_look": Vector3(0.0, 1.33, 0.0)},
		{"name": "v_hair1_front", "clip": "idle", "t": 0.0, "hair": 1, "cam_pos": Vector3(0.0, 1.35, -0.78), "cam_look": Vector3(0.0, 1.30, 0.0)},
		{"name": "v_cloth_detail", "clip": "idle", "t": 0.0, "cam_pos": Vector3(0.0, 0.95, -0.86), "cam_look": Vector3(0.0, 0.95, 0.0)},
		{"name": "v_sit_close", "clip": "sit_idle", "t": 1.0, "root_pos": sit_root, "chair": true, "cam_pos": Vector3(-0.80, 1.02, -1.15), "cam_look": Vector3(0.0, 0.66, 0.0)},
		{"name": "v_eat_close", "clip": "eat", "t": 1.4, "root_pos": sit_root, "chair": true, "bowl": true, "cam_pos": Vector3(-0.72, 1.10, -1.05), "cam_look": Vector3(0.0, 0.72, 0.0)},
		{"name": "v_sleep", "clip": "sleep", "t": 1.5, "root_pos": bed_root, "bed": true, "cam_pos": Vector3(-1.95, 0.82, -0.55), "cam_look": Vector3(0.0, 0.52, -0.20)},
		{"name": "v_walk_a", "clip": "walk", "t": 0.0, "cam_pos": Vector3(-1.85, 0.95, -1.65), "cam_look": Vector3(0.0, 0.80, 0.0)},
		{"name": "v_walk_b", "clip": "walk", "t": 0.22, "cam_pos": Vector3(-1.85, 0.95, -1.65), "cam_look": Vector3(0.0, 0.80, 0.0)},
	]


func _setup_studio_globals() -> void:
	# 窗口模式下 toon/outline shader 的 global uniform 必须先注册（与 main.gd 同口径），否则材质发黑
	var existing := RenderingServer.global_shader_parameter_get_list()
	_add_studio_global(existing, "g_outline_color", RenderingServer.GLOBAL_VAR_TYPE_COLOR, Color(0.09, 0.11, 0.18))
	_add_studio_global(existing, "g_sun_color", RenderingServer.GLOBAL_VAR_TYPE_COLOR, Color(1.08, 1.00, 0.90))
	_add_studio_global(existing, "g_sun_dir_view", RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3(0.3, 0.7, -0.6).normalized())
	_add_studio_global(existing, "g_moon_color", RenderingServer.GLOBAL_VAR_TYPE_COLOR, Color(0.08, 0.10, 0.16))
	_add_studio_global(existing, "g_moon_dir_view", RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3(-0.4, 0.5, 0.7).normalized())
	_add_studio_global(existing, "g_ambient_sky", RenderingServer.GLOBAL_VAR_TYPE_COLOR, Color(0.50, 0.56, 0.62))
	_add_studio_global(existing, "g_ambient_ground", RenderingServer.GLOBAL_VAR_TYPE_COLOR, Color(0.20, 0.20, 0.18))
	_add_studio_global(existing, "g_fog_color", RenderingServer.GLOBAL_VAR_TYPE_COLOR, Color(0.62, 0.70, 0.78))
	_add_studio_global(existing, "g_fog_near", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 120.0)
	_add_studio_global(existing, "g_fog_far", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 300.0)
	_add_studio_global(existing, "g_wind_time", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)
	_add_studio_global(existing, "g_light_count", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)
	_add_studio_global(existing, "g_beam_origin", RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3.ZERO)
	_add_studio_global(existing, "g_beam_dir", RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3(0.0, 0.0, -1.0))
	_add_studio_global(existing, "g_beam_color", RenderingServer.GLOBAL_VAR_TYPE_COLOR, Color(0.0, 0.0, 0.0, 0.0))
	_add_studio_global(existing, "g_beam_params", RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4.ZERO)
	_add_studio_global(existing, "g_spot_origin", RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3.ZERO)
	_add_studio_global(existing, "g_spot_dir", RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3(0.0, 0.0, -1.0))
	_add_studio_global(existing, "g_spot_color", RenderingServer.GLOBAL_VAR_TYPE_COLOR, Color(0.0, 0.0, 0.0, 0.0))
	_add_studio_global(existing, "g_spot_params", RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4(0.9, 0.985, 8.0, 0.0))
	_add_studio_global(existing, "g_occ_count", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)
	for oi in range(4):
		_add_studio_global(existing, "g_occ_c%d" % oi, RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3.ZERO)
		_add_studio_global(existing, "g_occ_h%d" % oi, RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3.ZERO)
		_add_studio_global(existing, "g_occ_y%d" % oi, RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)
	for i in range(12):
		_add_studio_global(existing, "g_l%d_pos" % i, RenderingServer.GLOBAL_VAR_TYPE_VEC4,
			Vector4(0.0, -999.0, 0.0, 1.0))
		_add_studio_global(existing, "g_l%d_col" % i, RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4.ZERO)


func _add_studio_global(existing: Array, nm: String, type: int, value: Variant) -> void:
	if not existing.has(StringName(nm)):
		RenderingServer.global_shader_parameter_add(nm, type, value)
		existing.append(StringName(nm))
	RenderingServer.global_shader_parameter_set(nm, value)
