class_name IsleScaleFigure
extends RefCounted
## P7-V3.2 1.50 m 人体参照（低模、无动画、无脚本生命周期）。
##
## 契约（供 tools/probe_scale_world.gd 与 scripts/scale_debug_overlay.gd 共用）：
##   * 脚底局部 y = 0.000，头顶局部 y = 1.500（世界 AABB 高度 1.500 ± 0.010 m）
##   * 全部部件只用 IsleMath.toon_material（无自发光、无灯光、无 MultiMesh）
##   * MeshInstance3D 数量 ≤ 12（当前 12 个：2 脚 + 2 腿 + 1 髋 + 1 躯干 + 1 颈 + 1 头 + 2 臂 + 2 手）
##   * 关键关节点写成 Node3D 子节点 LM_<关节>（foot/ankle/knee/hip/waist/hand/shoulder/chin/eye/head_top），
##     供 measure() 直接读；marker 本身不参与 AABB。
##   * 父节点即使被 scale，measure() 仍返回真实世界 AABB（会如实暴露异常比例）。
##
## 用法：
##   const Figure := preload("res://scripts/isle_scale_figure.gd")
##   var fig: Node3D = Figure.build(parent, Vector3(0, 0, 0), 0.0)
##   var m: Dictionary = Figure.measure(fig)   # height / foot_y_world / world_aabb / landmarks ...

const Spec := preload("res://scripts/isle_scale_spec.gd")

const FIG_NAME := "ScaleFigure"
const FIG_HEIGHT := Spec.HUMAN_HEIGHT           # 1.50
const HEAD_TOP := Spec.HUMAN_HEAD_TOP_H         # 1.50
const EYE_H := Spec.HUMAN_EYE_H                 # 1.38
const CHIN_H := Spec.HUMAN_CHIN_H               # 1.32
const SHOULDER_H := Spec.HUMAN_SHOULDER_H       # 1.24
const HAND_H := Spec.HUMAN_HAND_H               # 0.95
const WAIST_H := Spec.HUMAN_WAIST_H             # 0.92
const HIP_H := Spec.HUMAN_HIP_H                 # 0.78
const KNEE_H := Spec.HUMAN_KNEE_H               # 0.42
const ANKLE_H := Spec.HUMAN_ANKLE_H             # 0.06
const SHOULDER_W := Spec.HUMAN_SHOULDER_W       # 0.36 肩宽
const HIP_HALF_W := 0.10                        # 两腿中心到中轴
const ARM_OUT := 0.19                           # 手臂中心 |x|（臂外缘 0.235，总宽 0.47）
const FOOT_H := 0.07
const FOOT_LEN := 0.22
const FOOT_FWD := 0.02                          # 脚掌前伸（角色面向 -Z）；脚掌-躯干合并后总深 0.24

# 醒目对照色（与岛屿暖色系区分开，画面上一眼可辨）
const C_TORSO := Color("ff7a45")
const C_ARM := Color("ff9a5a")
const C_LEG := Color("3a6fd8")
const C_FOOT := Color("202a3c")
const C_HEAD := Color("ffd88a")
const C_NECK := Color("e8b46a")
const C_MARK := Color("36e0ff")

const _OPTS := {"outline": 0.015, "rim": 0.25}

## 构建参照人形。parent 必须是已在场景树中的 Node3D；pos 为脚底世界位置，yaw 绕 Y。
static func build(parent: Node3D, pos: Vector3, yaw: float = 0.0) -> Node3D:
	if parent == null:
		push_error("IsleScaleFigure.build: parent 为空")
		return null
	var fig := Node3D.new()
	fig.name = FIG_NAME
	fig.position = pos
	fig.rotation.y = yaw
	fig.set_meta("scale_figure", true)
	fig.set_meta("figure_height", FIG_HEIGHT)
	parent.add_child(fig)

	# ---- 脚（2）----
	for sx in [-1.0, 1.0]:
		var foot: MeshInstance3D = IsleMath.box(fig, Vector3(0.10, FOOT_H, FOOT_LEN),
			Vector3(sx * HIP_HALF_W, FOOT_H * 0.5, -FOOT_FWD), C_FOOT, 0.0, _OPTS)
		foot.name = "Ref_Foot_%s" % ("R" if sx > 0.0 else "L")
	# ---- 腿（2）：踝 0.06 → 髋 0.78 ----
	var leg_h: float = HIP_H - ANKLE_H
	for sx in [-1.0, 1.0]:
		var leg: MeshInstance3D = IsleMath.box(fig, Vector3(0.11, leg_h, 0.12),
			Vector3(sx * HIP_HALF_W, ANKLE_H + leg_h * 0.5, 0.0), C_LEG, 0.0, _OPTS)
		leg.name = "Ref_Leg_%s" % ("R" if sx > 0.0 else "L")
	# ---- 髋（1）：0.78 → 0.94 ----
	var pelvis: MeshInstance3D = IsleMath.box(fig, Vector3(0.30, 0.16, 0.20),
		Vector3(0.0, HIP_H + 0.08, 0.0), C_LEG, 0.0, _OPTS)
	pelvis.name = "Ref_Pelvis"
	# ---- 躯干（1）：0.94 → 1.28 ----
	var torso: MeshInstance3D = IsleMath.box(fig, Vector3(SHOULDER_W, SHOULDER_H - 0.94, 0.22),
		Vector3(0.0, (0.94 + SHOULDER_H) * 0.5, 0.0), C_TORSO, 0.0, _OPTS)
	torso.name = "Ref_Torso"
	# ---- 颈（1）：1.28 → 1.34 ----
	var neck: MeshInstance3D = IsleMath.box(fig, Vector3(0.09, CHIN_H - SHOULDER_H, 0.09),
		Vector3(0.0, (SHOULDER_H + CHIN_H) * 0.5, 0.0), C_NECK, 0.0, _OPTS)
	neck.name = "Ref_Neck"
	# ---- 头（1）：下巴 1.32 → 头顶 1.50（球心 1.41，半径 0.09）----
	var head: MeshInstance3D = IsleMath.sphere(fig, (HEAD_TOP - CHIN_H) * 0.5,
		Vector3(0.0, (CHIN_H + HEAD_TOP) * 0.5, 0.0), C_HEAD, Vector3(0.85, 1.0, 0.90), _OPTS)
	head.name = "Ref_Head"
	# ---- 臂（2）：手 0.95 → 肩 1.24 ----
	var arm_h: float = SHOULDER_H - HAND_H
	for sx in [-1.0, 1.0]:
		var arm: MeshInstance3D = IsleMath.box(fig, Vector3(0.09, arm_h, 0.11),
			Vector3(sx * ARM_OUT, HAND_H + arm_h * 0.5, 0.0), C_ARM, 0.0, _OPTS)
		arm.name = "Ref_Arm_%s" % ("R" if sx > 0.0 else "L")
	# ---- 手（2）：0.83 → 0.95 ----
	for sx in [-1.0, 1.0]:
		var hand: MeshInstance3D = IsleMath.box(fig, Vector3(0.09, 0.12, 0.09),
			Vector3(sx * ARM_OUT, HAND_H - 0.06, 0.0), C_HEAD, 0.0, _OPTS)
		hand.name = "Ref_Hand_%s" % ("R" if sx > 0.0 else "L")

	# ---- 关节点 marker（Node3D，不参与 AABB）----
	var marks: Dictionary = {
		"foot": [Vector3(-HIP_HALF_W, 0.0, -FOOT_FWD), Vector3(HIP_HALF_W, 0.0, -FOOT_FWD)],
		"ankle": [Vector3(-HIP_HALF_W, ANKLE_H, 0.0), Vector3(HIP_HALF_W, ANKLE_H, 0.0)],
		"knee": [Vector3(-HIP_HALF_W, KNEE_H, 0.0), Vector3(HIP_HALF_W, KNEE_H, 0.0)],
		"hip": [Vector3(-HIP_HALF_W, HIP_H, 0.0), Vector3(HIP_HALF_W, HIP_H, 0.0)],
		"waist": [Vector3(0.0, WAIST_H, 0.0)],
		"hand": [Vector3(-ARM_OUT, HAND_H, 0.0), Vector3(ARM_OUT, HAND_H, 0.0)],
		"shoulder": [Vector3(-SHOULDER_W * 0.5, SHOULDER_H, 0.0), Vector3(SHOULDER_W * 0.5, SHOULDER_H, 0.0)],
		"chin": [Vector3(0.0, CHIN_H, 0.0)],
		"eye": [Vector3(0.0, EYE_H, -0.06)],
		"head_top": [Vector3(0.0, HEAD_TOP, 0.0)],
	}
	for key in marks.keys():
		var pts: Array = marks[key]
		for i in pts.size():
			var marker := Node3D.new()
			marker.name = "LM_%s%s" % [String(key), "" if pts.size() == 1 else ("_R" if i == 1 else "_L")]
			marker.position = pts[i]
			marker.set_meta("landmark", String(key))
			fig.add_child(marker)
	return fig

## 实测：世界 AABB（含父级变换真实性）、局部 AABB、高度、脚底高度、关节点位置、网格数。
static func measure(node: Node3D) -> Dictionary:
	var out: Dictionary = {
		"ok": false, "height": 0.0, "foot_y_world": 0.0,
		"world_aabb": AABB(), "local_aabb": AABB(),
		"meshes": 0, "landmarks": {}, "landmarks_local": {},
		"ancestor_scale": Vector3.ONE, "height_err": INF, "fine": false,
	}
	if node == null or not is_instance_valid(node):
		return out
	var world_xf: Transform3D = node.global_transform if node.is_inside_tree() else node.transform
	var mn := Vector3(INF, INF, INF)
	var mx := Vector3(-INF, -INF, -INF)
	var found := false
	var meshes := 0
	for n in _walk(node):
		if not (n is MeshInstance3D):
			continue
		var mi: MeshInstance3D = n
		if mi.mesh == null:
			continue
		meshes += 1
		var bb: AABB = mi.mesh.get_aabb()
		var xf: Transform3D = mi.global_transform if mi.is_inside_tree() else (world_xf * mi.transform)
		for i in 8:
			var corner: Vector3 = bb.position + Vector3(
				bb.size.x * (1.0 if (i & 1) != 0 else 0.0),
				bb.size.y * (1.0 if (i & 2) != 0 else 0.0),
				bb.size.z * (1.0 if (i & 4) != 0 else 0.0))
			var p: Vector3 = xf * corner
			mn = mn.min(p)
			mx = mx.max(p)
			found = true
	if not found:
		return out
	var waabb := AABB(mn, mx - mn)
	var inv: Transform3D = world_xf.affine_inverse()
	var lmn := Vector3(INF, INF, INF)
	var lmx := Vector3(-INF, -INF, -INF)
	for i in 8:
		var c: Vector3 = waabb.position + Vector3(
			waabb.size.x * (1.0 if (i & 1) != 0 else 0.0),
			waabb.size.y * (1.0 if (i & 2) != 0 else 0.0),
			waabb.size.z * (1.0 if (i & 4) != 0 else 0.0))
		var lp: Vector3 = inv * c
		lmn = lmn.min(lp)
		lmx = lmx.max(lp)
	var landmarks: Dictionary = {}
	var landmarks_local: Dictionary = {}
	for n in _walk(node):
		if n is Node3D and n.has_meta("landmark"):
			var n3: Node3D = n
			var local_p: Vector3 = n3.transform.origin
			var name_key: String = String(n3.name).trim_prefix("LM_").to_lower()
			landmarks_local[name_key] = local_p
			landmarks[name_key] = world_xf * local_p
	# 双侧关节点再提供聚合键（foot/ankle/knee/hip/hand/shoulder = 左右均值），
	# 方便规范表/叠加层只读一个名字；单侧细节仍保留 foot_l/foot_r 等键。
	for agg in ["foot", "ankle", "knee", "hip", "hand", "shoulder"]:
		var sum := Vector3.ZERO
		var cnt := 0
		for side in ["_l", "_r"]:
			var kk: String = String(agg) + String(side)
			if landmarks.has(kk):
				sum += landmarks[kk]
				cnt += 1
		if cnt > 0:
			landmarks[agg] = sum / float(cnt)
			var sum_l := Vector3.ZERO
			for side2 in ["_l", "_r"]:
				var kk2: String = String(agg) + String(side2)
				if landmarks_local.has(kk2):
					sum_l += landmarks_local[kk2]
			landmarks_local[agg] = sum_l / float(cnt)
	# 父级缩放（角点 max |scale|）：用于暴露“被父节点缩放”的异常
	var sx: Vector3 = world_xf.basis.get_scale()
	var ascale: Vector3 = Vector3(absf(sx.x), absf(sx.y), absf(sx.z))
	var h: float = waabb.size.y
	out["ok"] = true
	out["height"] = h
	out["foot_y_world"] = waabb.position.y
	out["world_aabb"] = waabb
	out["local_aabb"] = AABB(lmn, lmx - lmn)
	out["meshes"] = meshes
	out["landmarks"] = landmarks
	out["landmarks_local"] = landmarks_local
	out["ancestor_scale"] = ascale
	out["height_err"] = h - FIG_HEIGHT
	out["fine"] = absf(out["height_err"]) <= Spec.HUMAN_HEIGHT_TOL
	out["foot_local_y"] = lmn.y
	return out

## 便捷：只取世界高度。
static func world_height(node: Node3D) -> float:
	return float(measure(node)["height"])

static func _walk(parent: Node) -> Array:
	var out: Array = []
	var stack: Array = [parent]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n != parent:
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out
