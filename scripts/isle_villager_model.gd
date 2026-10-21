class_name IsleVillagerModel
extends Node3D

## P7-V4 岛民角色模型：程序化 1.50 m 低模人形（白内衬衣 + 绿色农夫连体防水背带裤 + 两种发型）。
##
## 设计约定：
## - 只用 Godot 原生节点 + 代码生成的 ArrayMesh；不导入任何外部模型/贴图/动画。
## - 全部颜色走同一个顶点色 toon 材质（IsleMath.toon_material 缓存共享），静态细节
##   （五官、口袋、扣件、靴筒…）在构建时合并进所属关节的同一个 surface。
## - 每个可动关节 = 1 个 MeshInstance3D = 1 个 surface，运行时只旋转/平移关节，不重建网格。
## - 站立时脚底 y = 0，含发型总高 1.500 m，模型局部 -Z 为正面（脸朝 -Z）。
## - root 带 no_batch meta：静态合批会吞掉独立枢轴，动态角色必须跳过。

const M := preload("res://scripts/isle_math.gd")

const FIG_HEIGHT := 1.500
const HAIR_STYLES := ["short", "medium"]

# —— 比例常量（站立，脚底 y = 0；世界坐标只在注释里出现，代码里用局部坐标）——
const HIP_Y := 0.760          # 骨盆中心（= body_pos 站立高度）
const TORSO_Y := 0.140        # 躯干关节相对骨盆
const NECK_Y := 0.240         # 脖子关节相对躯干
const HEAD_Y := 0.020         # 头关节相对脖子
const HEAD_CENTER := Vector3(0.0, 0.162, -0.004)
const HEAD_RADIUS := Vector3(0.132, 0.146, 0.132)  # 头略收窄（宽高比≈0.90），仍保 1.500 总高与头身比
const HAIR_Y := 0.150         # 发型枢轴相对头关节
const HAIR_CENTER := Vector3(0.0, 0.012, -0.004)  # 头骨中心在 hair 局部坐标中（HEAD_CENTER - (0, HAIR_Y, 0)）
const HAIR_RADIUS := HEAD_RADIUS                  # 发帽贴着同一颗头骨长（不再是独立大椭球）
const HAIR_THICK_RIM := 0.010                     # 发缘处发帽厚度
const HAIR_THICK_TOP := 0.032                     # 发顶厚度：发顶 = 头骨顶 + 0.032 = 世界 1.500
const SHOULDER_X := 0.165
const SHOULDER_Y := 0.230
const ELBOW_LEN := 0.200
const WRIST_LEN := 0.170
const HIP_X := 0.070
const THIGH_LEN := 0.360
const SHIN_LEN := 0.300

# —— 色板（与岛屿低饱和手绘风一致；两种发型共用 C_HAIR 系列）——
const C_SKIN := Color(0.949, 0.788, 0.659)          # f2c9a8
const C_SKIN_SHADOW := Color(0.878, 0.690, 0.565)   # e0b090
const C_BLUSH := Color(0.906, 0.604, 0.525)         # e79a86
const C_BLUSH_SOFT := Color(0.930, 0.705, 0.599)    # edb499：低饱和腮红（贴合脸颊、不凸出）
const C_SHIRT := Color(0.949, 0.937, 0.902)         # f2efe6
const C_SHIRT_SHADOW := Color(0.871, 0.855, 0.816)  # dedad0
const C_OVERALL := Color(0.290, 0.478, 0.239)       # 4a7a3d
const C_OVERALL_LIGHT := Color(0.373, 0.569, 0.314) # 5f9150
const C_OVERALL_DARK := Color(0.200, 0.341, 0.169)  # 33572b
const C_OVERALL_PALE := Color(0.467, 0.659, 0.408)  # 77a868
const C_BOOT := Color(0.184, 0.290, 0.173)          # 2f4a2c
const C_SOLE := Color(0.231, 0.200, 0.173)          # 3b332c
const C_BRASS := Color(0.847, 0.663, 0.290)         # d8a94a
const C_WOOD := Color(0.612, 0.455, 0.341)          # 9c7457
const C_METAL := Color(0.604, 0.643, 0.659)         # 9aa4a8
const C_HAIR := Color(0.294, 0.204, 0.149)          # 4b3426
const C_HAIR_LIGHT := Color(0.416, 0.290, 0.200)    # 6a4a33
const C_HAIR_DARK := Color(0.200, 0.137, 0.094)     # 332318
const C_EYE_WHITE := Color(0.973, 0.953, 0.918)     # f8f3ea
const C_EYE_DARK := Color(0.165, 0.137, 0.125)      # 2a2320
const C_MOUTH := Color(0.541, 0.290, 0.259)         # 8a4a42
const C_BOWL := Color(0.86, 0.80, 0.68)  # 进食小碗：粗陶米白
const C_BOWL_IN := Color(0.62, 0.42, 0.24)  # 碗内汤汁

const JOINT_NAMES := [
	"pelvis", "torso", "neck", "head", "hair",
	"shoulder_l", "shoulder_r", "elbow_l", "elbow_r", "hand_l", "hand_r",
	"hip_l", "hip_r", "knee_l", "knee_r", "foot_l", "foot_r",
	"eyelid_l", "eyelid_r",
]


# =============================================================================
# 几何装配工具：把 PrimitiveMesh 的顶点/法线烘进一个带顶点色的 SurfaceTool。
# 所有 primitive 用 xform 变换（含非均匀缩放，法线走逆转置），避免使用节点 scale。
# =============================================================================
class _Kit extends RefCounted:
	var _st := SurfaceTool.new()
	var _tris := 0

	func _init() -> void:
		_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	func _add(p: Vector3, n: Vector3, c: Color) -> void:
		_st.set_color(c)
		_st.set_normal(n)
		_st.add_vertex(p)

	## 自定义三角：Godot 4 以顺时针为正面（cull_back 剔除逆时针），
	## 用「交叉积 vs 外侧法线」判定，若反向则交换 b/c。
	func tri(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color,
			na: Vector3, nb: Vector3, nc: Vector3) -> void:
		if (b - a).cross(c - a).dot(na + nb + nc) > 0.0:
			var tb := b
			b = c
			c = tb
			var tn := nb
			nb = nc
			nc = tn
			var tc := cb
			cb = cc
			cc = tc
		_add(a, na, ca)
		_add(b, nb, cb)
		_add(c, nc, cc)
		_tris += 1

	func add_arrays(arr: Array, xf: Transform3D, col: Color) -> void:
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var nb := xf.basis.inverse().transposed()
		var idx = arr[Mesh.ARRAY_INDEX]
		if idx == null:
			for i in verts.size():
				_add(xf * verts[i], (nb * norms[i]).normalized(), col)
			_tris += verts.size() / 3
		else:
			var ii: PackedInt32Array = idx
			for i in ii.size():
				var vi := ii[i]
				_add(xf * verts[vi], (nb * norms[vi]).normalized(), col)
			_tris += ii.size() / 3

	func box(size: Vector3, pos: Vector3, col: Color, rot := Vector3.ZERO) -> void:
		var m := BoxMesh.new()
		m.size = Vector3.ONE
		var basis := Basis.from_euler(rot) * Basis.from_scale(size)
		add_arrays(m.get_mesh_arrays(), Transform3D(basis, pos), col)

	func ellipsoid(center: Vector3, radii: Vector3, col: Color, segs := 10, rings := 6) -> void:
		var m := SphereMesh.new()
		m.radius = 1.0
		m.height = 2.0
		m.radial_segments = segs
		m.rings = rings
		add_arrays(m.get_mesh_arrays(), Transform3D(Basis.from_scale(radii), center), col)

	func cylinder(top_r: float, bot_r: float, h: float, center: Vector3, col: Color,
			rot := Vector3.ZERO, segs := 10) -> void:
		var m := CylinderMesh.new()
		m.top_radius = maxf(top_r, 0.0001)
		m.bottom_radius = maxf(bot_r, 0.0001)
		m.height = h
		m.radial_segments = segs
		m.rings = 2
		add_arrays(m.get_mesh_arrays(), Transform3D(Basis.from_euler(rot), center), col)

	func ellipsoid_rot(center: Vector3, radii: Vector3, col: Color,
			rot := Vector3.ZERO, segs := 8, rings := 4) -> void:
		var m := SphereMesh.new()
		m.radius = 1.0
		m.height = 2.0
		m.radial_segments = segs
		m.rings = rings
		add_arrays(m.get_mesh_arrays(), Transform3D(Basis.from_euler(rot) * Basis.from_scale(radii), center), col)

	func prism(size: Vector3, pos: Vector3, col: Color, rot := Vector3.ZERO) -> void:
		var m := PrismMesh.new()
		m.size = Vector3.ONE
		var basis := Basis.from_euler(rot) * Basis.from_scale(size)
		add_arrays(m.get_mesh_arrays(), Transform3D(basis, pos), col)

	func commit() -> ArrayMesh:
		_st.index()
		return _st.commit()



# =============================================================================
# 对外 API（villager 控制脚本只依赖这里；网格/材质/动画一次性构建，运行期不再创建或销毁部件）
# =============================================================================

const HAIR_STYLE := 0  # 0=短（偏男性），1=中长（偏女性）

const ANIMATIONS := {
	&"idle": {"length": 5.0, "loop": true},
	&"idle_alt": {"length": 5.2, "loop": true},
	&"walk": {"length": 0.88, "loop": true},
	&"sit_down": {"length": 0.80, "loop": false},
	&"sit_idle": {"length": 4.0, "loop": true},
	&"sit_up": {"length": 0.70, "loop": false},
	&"bed_sit_down": {"length": 0.80, "loop": false},
	&"bed_sit_up": {"length": 0.70, "loop": false},
	&"eat": {"length": 3.0, "loop": true},
	&"lie_down": {"length": 1.0, "loop": false},
	&"sleep": {"length": 6.0, "loop": true},
	&"get_up": {"length": 1.0, "loop": false},
}

const WALK_STRIDE := 1.0  # 每循环（左右各一步）步幅，单位 m；控制器按 WALK_STRIDE/length 换算≈1.13 m/s

const EYELID_OPEN := Vector3(-1.55, 0.0, 0.0)
const EYELID_CLOSED := Vector3(0.0, 0.0, 0.0)

static var _toon_mat: ShaderMaterial = null
static var _bowl_mat: ShaderMaterial = null

var _anim: AnimationPlayer = null
var _joints := {}
var _hair_short: MeshInstance3D = null
var _hair_medium: MeshInstance3D = null
var _bowl: MeshInstance3D = null
var _shadow: MeshInstance3D = null
var _hair_style := 0


## 一次性构建岛民角色（网格 + 共享材质 + 动画库）。返回 {"root","anim","height","hair_style"}
static func create(hair_style: int = 0) -> Dictionary:
	# 用 load 自引用而不是 IsleVillagerModel.new()：headless 无编辑器扫描时全局类缓存可能还没登记本脚本
	var villager: Node3D = (load("res://scripts/isle_villager_model.gd") as GDScript).new()
	villager.name = "Villager"
	villager.set_meta("isle_villager", true)
	villager.set_meta("no_batch", true)
	villager._build(hair_style)
	return {"root": villager, "anim": villager._anim, "height": FIG_HEIGHT, "hair_style": villager._hair_style}


## 切换发型：0=短（偏男性）/1=中长（偏女性）。只切两份预建发型的显隐，不重建角色。
func set_hair_style(style: int) -> void:
	_hair_style = 1 if style >= 1 else 0
	if _hair_short != null:
		_hair_short.visible = _hair_style == 0
	if _hair_medium != null:
		_hair_medium.visible = _hair_style == 1


## 进食小碗开关（默认隐藏）。碗挂在 root 下，坐姿 root 位于骨盆中心时碗底≈餐桌高度。
func set_bowl_visible(v: bool) -> void:
	if _bowl != null:
		_bowl.visible = v


func get_animation_names() -> PackedStringArray:
	var out := PackedStringArray()
	if _anim != null:
		for n in _anim.get_animation_list():
			out.append(String(n))
	return out


func get_joint(joint_name: String) -> Node3D:
	return _joints.get(StringName(joint_name)) as Node3D


## 网格 / 材质 / 三角面 / 包围盒 / 绘制调用估算（按 visible 链过滤）
func stats() -> Dictionary:
	var m := measure(self)
	return {
		"mesh_count": m["meshes"],
		"material_count": m["materials"],
		"triangles": m["tris"],
		"aabb": m["aabb"],
		"dc_estimate": m["dc_est"],
		"surfaces": m["surfaces"],
		"height": m["height"],
	}


# =============================================================================
# 构建
# =============================================================================

func _build(style: int) -> void:
	var mat := _toon()
	_shadow = M.shadow_blob(self, Vector3.ZERO, 0.26)
	_shadow.name = "Shadow"
	var body_pos := _pivot(self, "BodyPos", Vector3(0.0, HIP_Y, 0.0))
	var body_roll := _pivot(body_pos, "BodyRoll", Vector3.ZERO)
	var body_tilt := _pivot(body_roll, "BodyTilt", Vector3.ZERO)
	var pelvis := _joint(body_tilt, "Pelvis", Vector3.ZERO, _pelvis_kit(), mat)
	var torso := _joint(pelvis, "Torso", Vector3(0.0, TORSO_Y, 0.0), _torso_kit(), mat)
	# 脖子圆柱并进 torso 的同一 surface，Neck 只留空枢轴（Head 仍随 Neck 旋转）
	var neck := _pivot(torso, "Neck", Vector3(0.0, NECK_Y, 0.0))
	var head := _joint(neck, "Head", Vector3(0.0, HEAD_Y, 0.0), _head_kit(), mat)
	var hair := _pivot(head, "Hair", Vector3(0.0, HAIR_Y, 0.0))
	_hair_short = _hair_mesh(hair, "HairShort", _hair_short_kit(), mat, style == 0)
	_hair_medium = _hair_mesh(hair, "HairMedium", _hair_medium_kit(), mat, style == 1)

	_joints = {
		&"body_pos": body_pos,
		&"body_roll": body_roll,
		&"body_tilt": body_tilt,
		&"pelvis": pelvis,
		&"torso": torso,
		&"neck": neck,
		&"head": head,
		&"hair": hair,
	}
	for s in [-1.0, 1.0]:
		var suffix := "L" if s < 0.0 else "R"
		var eyelid := _joint(head, "Eyelid" + suffix, Vector3(s * 0.056, 0.196, -0.112), _eyelid_kit(), mat)
		eyelid.rotation = EYELID_OPEN
		var shoulder := _joint(torso, "Shoulder" + suffix, Vector3(s * SHOULDER_X, SHOULDER_Y, 0.0), _shoulder_kit(s), mat)
		# 手掌并进前臂的同一 surface，Hand 只留空枢轴（保留 hand_l/r 轨道，不额外占绘制）
		var elbow := _joint(shoulder, "Elbow" + suffix, Vector3(0.0, -ELBOW_LEN, 0.0), _elbow_kit(s), mat)
		var hand := _pivot(elbow, "Hand" + suffix, Vector3(0.0, -WRIST_LEN, 0.0))
		var hip := _joint(pelvis, "Hip" + suffix, Vector3(s * HIP_X, 0.0, 0.0), _hip_kit(s), mat)
		var knee := _joint(hip, "Knee" + suffix, Vector3(0.0, -THIGH_LEN, 0.0), _knee_kit(s), mat)
		var foot := _joint(knee, "Foot" + suffix, Vector3(0.0, -SHIN_LEN, 0.0), _foot_kit(s), mat)
		_joints[StringName("eyelid_" + suffix.to_lower())] = eyelid
		_joints[StringName("shoulder_" + suffix.to_lower())] = shoulder
		_joints[StringName("elbow_" + suffix.to_lower())] = elbow
		_joints[StringName("hand_" + suffix.to_lower())] = hand
		_joints[StringName("hip_" + suffix.to_lower())] = hip
		_joints[StringName("knee_" + suffix.to_lower())] = knee
		_joints[StringName("foot_" + suffix.to_lower())] = foot

	_bowl = _build_bowl(mat)
	_anim = _build_animations()
	set_hair_style(style)


func _hair_mesh(parent: Node3D, node_name: String, kit: _Kit, mat: ShaderMaterial, shown: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = kit.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = shown
	parent.add_child(mi)
	return mi


func _build_bowl(mat: ShaderMaterial) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Bowl"
	mi.mesh = _bowl_kit().commit()
	mi.material_override = _bowl_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0.0, 0.230, -0.330)
	mi.visible = false
	add_child(mi)
	return mi


## 碗不带描边（省 1 次绘制，保证“含碗”DC 也 ≤40），仍走 IsleMath 缓存
static func _bowl_material() -> ShaderMaterial:
	if _bowl_mat == null:
		_bowl_mat = M.toon_material(Color.WHITE, {"vertex_color": true, "rim": 0.12})
	return _bowl_mat


static func _bowl_kit() -> _Kit:
	var k := _Kit.new()
	k.cylinder(0.072, 0.050, 0.052, Vector3(0.0, 0.026, 0.0), C_BOWL, Vector3.ZERO, 12)
	k.cylinder(0.064, 0.046, 0.008, Vector3(0.0, 0.054, 0.0), C_BOWL_IN, Vector3.ZERO, 12)
	k.ellipsoid(Vector3(0.0, 0.050, 0.0), Vector3(0.064, 0.010, 0.064), C_BOWL_IN, 12, 3)
	return k


# =============================================================================
# 动画：剪辑构建（全部轨道由 joints 世界层级反算，一次性生成 AnimationLibrary）
# =============================================================================

func _build_animations() -> AnimationPlayer:
	var ap := AnimationPlayer.new()
	ap.name = "Anim"
	ap.root_node = NodePath("..")
	add_child(ap)
	var specs := _track_specs()
	var lib := AnimationLibrary.new()
	for clip_name in ANIMATIONS:
		var info: Dictionary = ANIMATIONS[clip_name]
		lib.add_animation(clip_name, _make_clip(specs, clip_name, _clip_frames(clip_name), _clip_base(clip_name), bool(info["loop"])))
	ap.add_animation_library(&"", lib)
	ap.play(&"idle")
	return ap


## 23 条 VALUE 轨道：躯干三大控制器 + 各关节 rotation + 阴影 visible。
func _track_specs() -> Array:
	var out: Array = []
	var rot_keys := [
		&"body_roll", &"body_tilt", &"pelvis", &"torso", &"neck", &"head", &"hair",
		&"shoulder_l", &"shoulder_r", &"elbow_l", &"elbow_r", &"hand_l", &"hand_r",
		&"hip_l", &"hip_r", &"knee_l", &"knee_r", &"foot_l", &"foot_r",
		&"eyelid_l", &"eyelid_r",
	]
	var pos_node := _resolve_node(&"body_pos")
	if pos_node != null:
		out.append({
			"key": &"body_pos",
			"path": get_path_to(pos_node),
			"prop": &"position",
			"kind": 0,
			"interp": Animation.INTERPOLATION_CUBIC,
		})
	for key in rot_keys:
		var node := _resolve_node(key)
		if node == null:
			continue
		out.append({
			"key": key,
			"path": get_path_to(node),
			"prop": &"rotation",
			"kind": 0,
			"interp": Animation.INTERPOLATION_CUBIC,
		})
	if _shadow != null:
		out.append({
			"key": &"shadow",
			"path": get_path_to(_shadow),
			"prop": &"visible",
			"kind": 1,
			"interp": Animation.INTERPOLATION_LINEAR,
		})
	return out


func _resolve_node(key: StringName) -> Node3D:
	if key == &"shadow":
		return _shadow
	return _joints.get(key) as Node3D


static func _make_clip(specs: Array, clip_name: StringName, frames: Array, base: Dictionary, loop: bool) -> Animation:
	var anim := Animation.new()
	anim.length = float(ANIMATIONS[clip_name]["length"])
	if bool(ANIMATIONS[clip_name]["loop"]):
		anim.loop_mode = Animation.LOOP_LINEAR
	var tracks := {}
	for f in frames:
		var t := float(f["t"])
		var pose: Dictionary = f["pose"]
		for spec in specs:
			var key: StringName = spec["key"]
			if not pose.has(key):
				continue
			var track: int = tracks.get(spec["path"], -1)
			if track < 0:
				track = anim.add_track(Animation.TYPE_VALUE)
				# Godot 4 的 VALUE 轨道把属性名写在路径里（NodePath("节点:属性")），缺了 ":prop" 轨道不会生效
				anim.track_set_path(track, NodePath(String(spec["path"]) + ":" + String(spec["prop"])))
				anim.track_set_interpolation_type(track, spec["interp"])
				anim.value_track_set_update_mode(track, Animation.UPDATE_CONTINUOUS)
				if loop:
					anim.track_set_interpolation_loop_wrap(track, true)
				tracks[spec["path"]] = track
			if int(spec["kind"]) == 1:
				anim.track_insert_key(track, t, bool(pose[key]))
			else:
				anim.track_insert_key(track, t, pose[key])
	# 兜底：若某条轨道没有任何 key（理论上不会），用基准姿态补首尾
	for spec in specs:
		var track: int = tracks.get(spec["path"], -1)
		if track < 0:
			continue
		if anim.track_get_key_count(track) > 0:
			continue
		var value = base.get(spec["key"])
		if value == null:
			continue
		if int(spec["kind"]) == 1:
			anim.track_insert_key(track, 0.0, bool(value))
			anim.track_insert_key(track, anim.length, bool(value))
		else:
			anim.track_insert_key(track, 0.0, value)
			anim.track_insert_key(track, anim.length, value)
	return anim


# =============================================================================
# 姿势基准（root 原点语义见各函数注释）
# =============================================================================

## 站立：root 原点=脚底，鞋底 y=0，头顶 1.500。
static func _stand() -> Dictionary:
	return {
		&"body_pos": Vector3(0.0, HIP_Y, 0.0),
		&"body_roll": Vector3.ZERO,
		&"body_tilt": Vector3.ZERO,
		&"pelvis": Vector3.ZERO,
		&"torso": Vector3.ZERO,
		&"neck": Vector3.ZERO,
		&"head": Vector3.ZERO,
		&"hair": Vector3.ZERO,
		&"shoulder_l": Vector3(0.0, 0.0, -0.05),
		&"shoulder_r": Vector3(0.0, 0.0, 0.05),
		&"elbow_l": Vector3(0.10, 0.0, 0.0),
		&"elbow_r": Vector3(0.10, 0.0, 0.0),
		&"hand_l": Vector3.ZERO,
		&"hand_r": Vector3.ZERO,
		&"hip_l": Vector3.ZERO,
		&"hip_r": Vector3.ZERO,
		&"knee_l": Vector3.ZERO,
		&"knee_r": Vector3.ZERO,
		&"foot_l": Vector3.ZERO,
		&"foot_r": Vector3.ZERO,
		&"eyelid_l": EYELID_OPEN,
		&"eyelid_r": EYELID_OPEN,
		&"shadow": true,
	}


## 坐姿：root 原点=座面(0.40)+0.02=0.42 处的接触平面（控制器把 root 放在这里）。
## body_pos 抬到 0.075：骨盆网格底 -0.114 → 臀底世界 0.381，只压进软坐垫约 2cm，不穿座板。
## 大腿绝对角 1.30、小腿绝对 0.093 → 踝 y=-0.320、鞋底 y=-0.420（脚踩地）；膝朝 -Z z≈-0.347。
static func _sit() -> Dictionary:
	return {
		&"body_pos": Vector3(0.0, 0.075, 0.0),
		&"body_roll": Vector3.ZERO,
		&"body_tilt": Vector3.ZERO,
		&"pelvis": Vector3(0.04, 0.0, 0.0),
		&"torso": Vector3(-0.02, 0.0, 0.0),
		&"neck": Vector3.ZERO,
		&"head": Vector3(-0.02, 0.0, 0.0),
		&"hair": Vector3.ZERO,
		&"shoulder_l": Vector3(0.30, 0.0, -0.14),
		&"shoulder_r": Vector3(0.30, 0.0, 0.14),
		&"elbow_l": Vector3(0.50, 0.0, 0.0),
		&"elbow_r": Vector3(0.50, 0.0, 0.0),
		&"hand_l": Vector3(0.12, 0.0, 0.0),
		&"hand_r": Vector3(0.12, 0.0, 0.0),
		&"hip_l": Vector3(1.26, 0.0, 0.0),
		&"hip_r": Vector3(1.26, 0.0, 0.0),
		&"knee_l": Vector3(-1.207, 0.0, 0.0),
		&"knee_r": Vector3(-1.207, 0.0, 0.0),
		&"foot_l": Vector3(-0.093, 0.0, 0.0),
		&"foot_r": Vector3(-0.093, 0.0, 0.0),
		&"eyelid_l": EYELID_OPEN,
		&"eyelid_r": EYELID_OPEN,
		&"shadow": false,
	}


## 坐床沿：root 原点=骨盆中心，双腿朝 +Z 垂下（床在角色 +Z 方向）。
static func _bed_sit() -> Dictionary:
	return {
		&"body_pos": Vector3(0.0, 0.030, 0.0),
		&"body_roll": Vector3.ZERO,
		&"body_tilt": Vector3.ZERO,
		&"pelvis": Vector3(-0.06, 0.0, 0.0),
		&"torso": Vector3(-0.02, 0.0, 0.0),
		&"neck": Vector3(0.02, 0.0, 0.0),
		&"head": Vector3(-0.04, 0.0, 0.0),
		&"hair": Vector3.ZERO,
		&"shoulder_l": Vector3(-0.22, 0.0, -0.12),
		&"shoulder_r": Vector3(-0.22, 0.0, 0.12),
		&"elbow_l": Vector3(0.28, 0.0, 0.0),
		&"elbow_r": Vector3(0.28, 0.0, 0.0),
		&"hand_l": Vector3(0.05, 0.0, 0.0),
		&"hand_r": Vector3(0.05, 0.0, 0.0),
		&"hip_l": Vector3(-1.34, 0.0, 0.0),
		&"hip_r": Vector3(-1.34, 0.0, 0.0),
		&"knee_l": Vector3(0.94, 0.0, 0.0),
		&"knee_r": Vector3(0.94, 0.0, 0.0),
		&"foot_l": Vector3(0.46, 0.0, 0.0),
		&"foot_r": Vector3(0.46, 0.0, 0.0),
		&"eyelid_l": EYELID_OPEN,
		&"eyelid_r": EYELID_OPEN,
		&"shadow": false,
	}


## 躺姿：root 原点=床面接触平面（控制器把 root 放在床垫顶+0.02）。
## body_pos.y=0.095 是骨盆中心相对 root 的竖直抬高量：躯干背部 ≈ root-0.02 贴床垫；
## 颈前屈 -0.82 rad 把头部整体抬到床垫面上方（头枢轴在头底：给头再加正俯仰反而会把后脑压向床垫，故头只做 0.05 微调）。
## body_roll z=π + body_tilt x=-π/2 → 局部 (x,y,z) → 世界 (-x,-z,-y)：头朝 -Z、脸朝 +Y、脚朝 +Z。
static func _lie() -> Dictionary:
	return {
		&"body_pos": Vector3(0.0, 0.105, 0.0),
		&"body_roll": Vector3(0.0, 0.0, PI),
		&"body_tilt": Vector3(-PI / 2.0, 0.0, 0.0),
		&"pelvis": Vector3.ZERO,
		&"torso": Vector3.ZERO,
		&"neck": Vector3(-0.82, 0.05, 0.10),
		&"head": Vector3(0.05, 0.05, 0.10),
		&"hair": Vector3.ZERO,
		&"shoulder_l": Vector3(-0.12, 0.0, -0.22),
		&"shoulder_r": Vector3(-0.12, 0.0, 0.22),
		&"elbow_l": Vector3(0.12, 0.0, 0.0),
		&"elbow_r": Vector3(0.12, 0.0, 0.0),
		&"hand_l": Vector3.ZERO,
		&"hand_r": Vector3.ZERO,
		&"hip_l": Vector3(0.02, 0.0, 0.0),
		&"hip_r": Vector3(0.06, 0.0, 0.0),
		&"knee_l": Vector3(-0.04, 0.0, 0.0),
		&"knee_r": Vector3(-0.10, 0.0, 0.0),
		&"foot_l": Vector3(0.40, 0.0, 0.0),
		&"foot_r": Vector3(0.45, 0.0, 0.0),
		&"eyelid_l": EYELID_OPEN,
		&"eyelid_r": EYELID_OPEN,
		&"shadow": false,
	}


## 睡姿：躺姿 + 闭眼 + 侧头 + 右腿屈起、右手搭在胸前（明显不是“直立旋转 90°”）。
static func _sleep_pose() -> Dictionary:
	return _merge(_lie(), {
		&"neck": Vector3(-0.78, 0.04, 0.30),
		&"head": Vector3(0.10, 0.04, 0.18),
		&"shoulder_l": Vector3(-0.08, 0.0, -0.30),
		&"shoulder_r": Vector3(-0.02, 0.0, 0.16),
		&"elbow_l": Vector3(0.20, 0.0, 0.0),
		&"elbow_r": Vector3(0.55, 0.0, 0.0),
		&"hand_r": Vector3(0.10, 0.0, 0.0),
		&"hip_r": Vector3(0.55, 0.0, 0.0),
		&"knee_r": Vector3(-1.00, 0.0, 0.0),
		&"foot_r": Vector3(0.20, 0.0, 0.0),
		&"eyelid_l": EYELID_CLOSED,
		&"eyelid_r": EYELID_CLOSED,
	})


static func _merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var out := base.duplicate()
	for k in over:
		out[k] = over[k]
	return out


static func _clip_base(clip_name: StringName) -> Dictionary:
	match clip_name:
		&"sleep", &"get_up":
			return _sleep_pose()
		&"lie_down", &"sit_down", &"sit_idle", &"sit_up", &"eat":
			return _sit()
		&"bed_sit_down", &"bed_sit_up":
			return _stand()
		_:
			return _stand()


# =============================================================================
# 各剪辑关键帧（t 秒；full 帧=完整姿势，partial 帧只写眨眼）
# =============================================================================

func _clip_frames(clip_name: StringName) -> Array:
	match clip_name:
		&"idle":
			var b := _stand()
			return [
				{"t": 0.0, "pose": b},
				{"t": 1.25, "pose": _merge(b, {
					&"body_pos": Vector3(0.0, 0.7628, 0.0),
					&"torso": Vector3(0.016, 0.0, 0.0),
					&"neck": Vector3(-0.012, 0.05, 0.0),
					&"head": Vector3(0.004, 0.09, 0.0),
					&"hair": Vector3(0.0, 0.02, 0.0),
					&"shoulder_l": Vector3(0.03, 0.0, -0.062),
					&"shoulder_r": Vector3(0.03, 0.0, 0.062),
				})},
				{"t": 2.15, "pose": {&"eyelid_l": EYELID_OPEN, &"eyelid_r": EYELID_OPEN}},
				{"t": 2.27, "pose": {&"eyelid_l": EYELID_CLOSED, &"eyelid_r": EYELID_CLOSED}},
				{"t": 2.40, "pose": {&"eyelid_l": EYELID_OPEN, &"eyelid_r": EYELID_OPEN}},
				{"t": 3.10, "pose": _merge(b, {
					&"body_pos": Vector3(0.006, 0.7608, 0.0),
					&"pelvis": Vector3(0.0, 0.0, 0.018),
					&"neck": Vector3(0.0, -0.10, 0.0),
					&"head": Vector3(0.0, -0.16, 0.0),
					&"hair": Vector3(0.0, -0.04, 0.0),
				})},
				{"t": 4.10, "pose": _merge(b, {
					&"body_pos": Vector3(0.002, 0.7615, 0.0),
					&"torso": Vector3(0.010, 0.0, 0.0),
					&"neck": Vector3(-0.006, 0.02, 0.0),
				})},
				{"t": 5.0, "pose": b},
			]
		&"idle_alt":
			var b2 := _stand()
			return [
				{"t": 0.0, "pose": b2},
				{"t": 1.05, "pose": _merge(b2, {
					&"body_pos": Vector3(-0.008, 0.7602, 0.0),
					&"torso": Vector3(0.0, -0.05, 0.0),
					&"neck": Vector3(-0.02, -0.18, 0.0),
					&"head": Vector3(-0.03, -0.24, 0.0),
					&"hair": Vector3(0.0, -0.05, 0.0),
					&"shoulder_l": Vector3(0.05, 0.0, -0.07),
				})},
				{"t": 2.10, "pose": _merge(b2, {
					&"body_pos": Vector3(-0.006, 0.7612, 0.0),
					&"torso": Vector3(0.02, 0.0, 0.0),
					&"neck": Vector3(-0.10, 0.0, 0.0),
					&"head": Vector3(-0.14, 0.02, 0.0),
				})},
				{"t": 2.95, "pose": _merge(b2, {
					&"body_pos": Vector3(0.004, 0.7608, 0.0),
					&"torso": Vector3(0.0, 0.04, 0.0),
					&"neck": Vector3(0.0, 0.16, 0.0),
					&"head": Vector3(0.02, 0.22, 0.0),
					&"hair": Vector3(0.0, 0.04, 0.0),
					&"shoulder_r": Vector3(0.04, 0.0, 0.075),
				})},
				{"t": 3.95, "pose": {&"eyelid_l": EYELID_OPEN, &"eyelid_r": EYELID_OPEN}},
				{"t": 4.07, "pose": {&"eyelid_l": EYELID_CLOSED, &"eyelid_r": EYELID_CLOSED}},
				{"t": 4.20, "pose": {&"eyelid_l": EYELID_OPEN, &"eyelid_r": EYELID_OPEN}},
				{"t": 4.60, "pose": _merge(b2, {
					&"body_pos": Vector3(0.0, 0.7606, 0.0),
					&"pelvis": Vector3(0.0, 0.0, -0.014),
					&"torso": Vector3(0.008, 0.0, 0.0),
					&"neck": Vector3(-0.01, 0.0, 0.0),
				})},
				{"t": 5.2, "pose": b2},
			]
		&"walk":
			return [
				{"t": 0.0, "pose": _walk_contact(1.0)},
				{"t": 0.22, "pose": _walk_passing(1.0)},
				{"t": 0.44, "pose": _walk_contact(-1.0)},
				{"t": 0.66, "pose": _walk_passing(-1.0)},
				{"t": 0.88, "pose": _walk_contact(1.0)},
			]
		&"sit_down":
			var st := _stand()
			var sit := _sit()
			return [
				{"t": 0.0, "pose": st},
				{"t": 0.30, "pose": _merge(st, {
					&"body_pos": Vector3(0.0, 0.500, 0.0),
					&"pelvis": Vector3(0.10, 0.0, 0.0),
					&"torso": Vector3(0.16, 0.0, 0.0),
					&"neck": Vector3(-0.06, 0.0, 0.0),
					&"head": Vector3(-0.05, 0.0, 0.0),
					&"hip_l": Vector3(0.85, 0.0, 0.0),
					&"hip_r": Vector3(0.85, 0.0, 0.0),
					&"knee_l": Vector3(-1.15, 0.0, 0.0),
					&"knee_r": Vector3(-1.15, 0.0, 0.0),
					&"foot_l": Vector3(-0.30, 0.0, 0.0),
					&"foot_r": Vector3(-0.30, 0.0, 0.0),
					&"shoulder_l": Vector3(0.30, 0.0, -0.10),
					&"shoulder_r": Vector3(0.30, 0.0, 0.10),
					&"elbow_l": Vector3(0.40, 0.0, 0.0),
					&"elbow_r": Vector3(0.40, 0.0, 0.0),
				})},
				{"t": 0.55, "pose": _merge(st, {
					&"body_pos": Vector3(0.0, 0.220, 0.0),
					&"pelvis": Vector3(0.07, 0.0, 0.0),
					&"torso": Vector3(0.10, 0.0, 0.0),
					&"neck": Vector3(-0.03, 0.0, 0.0),
					&"head": Vector3(-0.03, 0.0, 0.0),
					&"hip_l": Vector3(1.20, 0.0, 0.0),
					&"hip_r": Vector3(1.20, 0.0, 0.0),
					&"knee_l": Vector3(-1.02, 0.0, 0.0),
					&"knee_r": Vector3(-1.02, 0.0, 0.0),
					&"foot_l": Vector3(-0.42, 0.0, 0.0),
					&"foot_r": Vector3(-0.42, 0.0, 0.0),
					&"shoulder_l": Vector3(0.30, 0.0, -0.13),
					&"shoulder_r": Vector3(0.30, 0.0, 0.13),
					&"elbow_l": Vector3(0.48, 0.0, 0.0),
					&"elbow_r": Vector3(0.48, 0.0, 0.0),
				})},
				{"t": 0.80, "pose": sit},
			]
		&"sit_idle":
			var sit2 := _sit()
			return [
				{"t": 0.0, "pose": sit2},
				{"t": 1.20, "pose": _merge(sit2, {
					&"body_pos": Vector3(0.0, 0.078, 0.0),
					&"torso": Vector3(-0.010, 0.0, 0.0),
					&"neck": Vector3(-0.01, 0.04, 0.0),
					&"head": Vector3(0.0, 0.06, 0.0),
					&"shoulder_l": Vector3(0.315, 0.0, -0.145),
					&"shoulder_r": Vector3(0.315, 0.0, 0.145),
				})},
				{"t": 1.90, "pose": {&"eyelid_l": EYELID_OPEN, &"eyelid_r": EYELID_OPEN}},
				{"t": 2.02, "pose": {&"eyelid_l": EYELID_CLOSED, &"eyelid_r": EYELID_CLOSED}},
				{"t": 2.15, "pose": {&"eyelid_l": EYELID_OPEN, &"eyelid_r": EYELID_OPEN}},
				{"t": 2.60, "pose": _merge(sit2, {
					&"body_pos": Vector3(0.004, 0.0735, 0.0),
					&"neck": Vector3(0.0, -0.10, 0.0),
					&"head": Vector3(-0.02, -0.14, 0.0),
					&"hair": Vector3(0.0, -0.04, 0.0),
					&"hand_l": Vector3(0.18, 0.0, 0.0),
				})},
				{"t": 3.30, "pose": _merge(sit2, {
					&"body_pos": Vector3(-0.003, 0.0755, 0.0),
					&"pelvis": Vector3(0.04, 0.0, 0.010),
					&"neck": Vector3(-0.02, 0.05, 0.0),
					&"head": Vector3(0.01, 0.08, 0.0),
				})},
				{"t": 4.0, "pose": sit2},
			]
		&"sit_up":
			var sit3 := _sit()
			var stand := _stand()
			return [
				{"t": 0.0, "pose": sit3},
				{"t": 0.25, "pose": _merge(sit3, {
					&"body_pos": Vector3(0.0, 0.160, 0.0),
					&"torso": Vector3(0.22, 0.0, 0.0),
					&"neck": Vector3(-0.10, 0.0, 0.0),
					&"head": Vector3(-0.08, 0.0, 0.0),
					&"shoulder_l": Vector3(0.55, 0.0, -0.10),
					&"shoulder_r": Vector3(0.55, 0.0, 0.10),
					&"elbow_l": Vector3(0.35, 0.0, 0.0),
					&"elbow_r": Vector3(0.35, 0.0, 0.0),
					&"hip_l": Vector3(1.10, 0.0, 0.0),
					&"hip_r": Vector3(1.10, 0.0, 0.0),
					&"knee_l": Vector3(-1.28, 0.0, 0.0),
					&"knee_r": Vector3(-1.28, 0.0, 0.0),
					&"foot_l": Vector3(-0.20, 0.0, 0.0),
					&"foot_r": Vector3(-0.20, 0.0, 0.0),
				})},
				{"t": 0.50, "pose": _merge(sit3, {
					&"body_pos": Vector3(0.0, 0.420, 0.0),
					&"torso": Vector3(0.20, 0.0, 0.0),
					&"neck": Vector3(-0.06, 0.0, 0.0),
					&"head": Vector3(-0.05, 0.0, 0.0),
					&"pelvis": Vector3(0.02, 0.0, 0.0),
					&"shoulder_l": Vector3(0.30, 0.0, -0.08),
					&"shoulder_r": Vector3(0.30, 0.0, 0.08),
					&"elbow_l": Vector3(0.22, 0.0, 0.0),
					&"elbow_r": Vector3(0.22, 0.0, 0.0),
					&"hand_l": Vector3.ZERO,
					&"hand_r": Vector3.ZERO,
					&"hip_l": Vector3(0.70, 0.0, 0.0),
					&"hip_r": Vector3(0.70, 0.0, 0.0),
					&"knee_l": Vector3(-0.90, 0.0, 0.0),
					&"knee_r": Vector3(-0.90, 0.0, 0.0),
					&"foot_l": Vector3(-0.20, 0.0, 0.0),
					&"foot_r": Vector3(-0.20, 0.0, 0.0),
				})},
				{"t": 0.70, "pose": stand},
			]
		&"eat":
			var sit4 := _sit()
			return [
				{"t": 0.0, "pose": sit4},
				{"t": 0.70, "pose": _merge(sit4, {
					&"shoulder_r": Vector3(1.35, 0.0, 0.10),
					&"elbow_r": Vector3(1.60, 0.0, 0.0),
					&"hand_r": Vector3(0.25, 0.0, 0.0),
					&"neck": Vector3(-0.06, 0.0, 0.0),
					&"head": Vector3(-0.08, 0.0, 0.0),
					&"torso": Vector3(0.0, 0.0, 0.0),
				})},
				{"t": 1.30, "pose": _merge(sit4, {
					&"shoulder_r": Vector3(2.02, 0.0, 0.12),
					&"elbow_r": Vector3(1.50, 0.0, 0.0),
					&"hand_r": Vector3(0.20, 0.0, 0.0),
					&"neck": Vector3(-0.10, 0.0, 0.0),
					&"head": Vector3(-0.14, 0.05, 0.0),
				})},
				{"t": 1.70, "pose": _merge(sit4, {
					&"shoulder_r": Vector3(2.04, 0.0, 0.12),
					&"elbow_r": Vector3(1.58, 0.0, 0.0),
					&"hand_r": Vector3(0.22, 0.0, 0.0),
					&"neck": Vector3(-0.09, 0.0, 0.0),
					&"head": Vector3(-0.12, 0.05, 0.0),
				})},
				{"t": 2.00, "pose": _merge(sit4, {
					&"shoulder_r": Vector3(2.00, 0.0, 0.12),
					&"elbow_r": Vector3(1.44, 0.0, 0.0),
					&"hand_r": Vector3(0.18, 0.0, 0.0),
					&"neck": Vector3(-0.08, 0.0, 0.0),
					&"head": Vector3(-0.11, 0.05, 0.0),
				})},
				{"t": 2.30, "pose": _merge(sit4, {
					&"shoulder_r": Vector3(2.03, 0.0, 0.12),
					&"elbow_r": Vector3(1.56, 0.0, 0.0),
					&"hand_r": Vector3(0.21, 0.0, 0.0),
					&"neck": Vector3(-0.09, 0.0, 0.0),
					&"head": Vector3(-0.13, 0.05, 0.0),
				})},
				{"t": 2.70, "pose": _merge(sit4, {
					&"shoulder_r": Vector3(1.00, 0.0, 0.10),
					&"elbow_r": Vector3(0.90, 0.0, 0.0),
					&"hand_r": Vector3(0.20, 0.0, 0.0),
					&"neck": Vector3(-0.03, 0.0, 0.0),
					&"head": Vector3(-0.04, 0.0, 0.0),
				})},
				{"t": 3.0, "pose": sit4},
			]
		&"bed_sit_down":
			# 站立（脚底地面）→ 坐床沿（骨盆中心）。控制器同时把 root 从脚底点插到坐床点。
			var bsd_stand := _stand()
			var bsd_sit := _bed_sit()
			return [
				{"t": 0.0, "pose": bsd_stand},
				{"t": 0.28, "pose": _merge(bsd_stand, {
					&"body_pos": Vector3(0.0, 0.600, 0.0),
					&"pelvis": Vector3(0.16, 0.0, 0.0),
					&"torso": Vector3(0.20, 0.0, 0.0),
					&"neck": Vector3(-0.08, 0.0, 0.0),
					&"head": Vector3(-0.08, 0.0, 0.0),
					&"shoulder_l": Vector3(-0.22, 0.0, -0.16),
					&"shoulder_r": Vector3(-0.22, 0.0, 0.16),
					&"elbow_l": Vector3(0.36, 0.0, 0.0),
					&"elbow_r": Vector3(0.36, 0.0, 0.0),
					&"hip_l": Vector3(-0.42, 0.0, 0.0),
					&"hip_r": Vector3(-0.42, 0.0, 0.0),
					&"knee_l": Vector3(0.55, 0.0, 0.0),
					&"knee_r": Vector3(0.55, 0.0, 0.0),
					&"foot_l": Vector3(0.20, 0.0, 0.0),
					&"foot_r": Vector3(0.20, 0.0, 0.0),
					&"shadow": false,
				})},
				{"t": 0.56, "pose": _merge(bsd_stand, {
					&"body_pos": Vector3(0.0, 0.200, 0.0),
					&"pelvis": Vector3(0.02, 0.0, 0.0),
					&"torso": Vector3(0.08, 0.0, 0.0),
					&"neck": Vector3(-0.02, 0.0, 0.0),
					&"head": Vector3(-0.04, 0.0, 0.0),
					&"shoulder_l": Vector3(-0.38, 0.0, -0.13),
					&"shoulder_r": Vector3(-0.38, 0.0, 0.13),
					&"elbow_l": Vector3(0.42, 0.0, 0.0),
					&"elbow_r": Vector3(0.42, 0.0, 0.0),
					&"hand_l": Vector3(0.10, 0.0, 0.0),
					&"hand_r": Vector3(0.10, 0.0, 0.0),
					&"hip_l": Vector3(-1.02, 0.0, 0.0),
					&"hip_r": Vector3(-1.02, 0.0, 0.0),
					&"knee_l": Vector3(0.92, 0.0, 0.0),
					&"knee_r": Vector3(0.92, 0.0, 0.0),
					&"foot_l": Vector3(0.42, 0.0, 0.0),
					&"foot_r": Vector3(0.42, 0.0, 0.0),
					&"shadow": false,
				})},
				{"t": 0.80, "pose": bsd_sit},
			]
		&"bed_sit_up":
			# 坐床沿（骨盆中心）→ 站立（脚底地面）：先手撑床沿、收腿，再撑起离开床。
			var bsu_sit := _bed_sit()
			var bsu_stand := _stand()
			return [
				{"t": 0.0, "pose": bsu_sit},
				{"t": 0.22, "pose": _merge(bsu_sit, {
					&"body_pos": Vector3(0.0, 0.100, 0.0),
					&"pelvis": Vector3(0.10, 0.0, 0.0),
					&"torso": Vector3(0.26, 0.0, 0.0),
					&"neck": Vector3(-0.08, 0.0, 0.0),
					&"head": Vector3(-0.10, 0.0, 0.0),
					&"shoulder_l": Vector3(-0.34, 0.0, -0.10),
					&"shoulder_r": Vector3(-0.34, 0.0, 0.10),
					&"elbow_l": Vector3(0.55, 0.0, 0.0),
					&"elbow_r": Vector3(0.55, 0.0, 0.0),
					&"hand_l": Vector3(0.15, 0.0, 0.0),
					&"hand_r": Vector3(0.15, 0.0, 0.0),
					&"hip_l": Vector3(-1.05, 0.0, 0.0),
					&"hip_r": Vector3(-1.05, 0.0, 0.0),
					&"knee_l": Vector3(1.10, 0.0, 0.0),
					&"knee_r": Vector3(1.10, 0.0, 0.0),
					&"foot_l": Vector3(0.30, 0.0, 0.0),
					&"foot_r": Vector3(0.30, 0.0, 0.0),
				})},
				{"t": 0.46, "pose": _merge(bsu_sit, {
					&"body_pos": Vector3(0.0, 0.460, 0.0),
					&"pelvis": Vector3(0.06, 0.0, 0.0),
					&"torso": Vector3(0.18, 0.0, 0.0),
					&"neck": Vector3(-0.04, 0.0, 0.0),
					&"head": Vector3(-0.04, 0.0, 0.0),
					&"shoulder_l": Vector3(-0.15, 0.0, -0.09),
					&"shoulder_r": Vector3(-0.15, 0.0, 0.09),
					&"elbow_l": Vector3(0.30, 0.0, 0.0),
					&"elbow_r": Vector3(0.30, 0.0, 0.0),
					&"hand_l": Vector3.ZERO,
					&"hand_r": Vector3.ZERO,
					&"hip_l": Vector3(-0.45, 0.0, 0.0),
					&"hip_r": Vector3(-0.45, 0.0, 0.0),
					&"knee_l": Vector3(0.72, 0.0, 0.0),
					&"knee_r": Vector3(0.72, 0.0, 0.0),
					&"foot_l": Vector3(0.10, 0.0, 0.0),
					&"foot_r": Vector3(0.10, 0.0, 0.0),
					&"shadow": true,
				})},
				{"t": 0.70, "pose": bsu_stand},
			]
		&"lie_down":
			var bed := _bed_sit()
			var lie := _sleep_pose()
			return [
				{"t": 0.0, "pose": bed},
				{"t": 0.30, "pose": _merge(bed, {
					&"body_pos": Vector3(0.0, 0.060, 0.0),
					&"body_tilt": Vector3(-0.45, 0.0, 0.0),
					&"torso": Vector3(0.06, 0.0, 0.0),
					&"neck": Vector3(-0.12, 0.0, 0.0),
					&"head": Vector3(-0.06, 0.0, 0.0),
					&"shoulder_l": Vector3(-0.10, 0.0, -0.16),
					&"shoulder_r": Vector3(-0.05, 0.0, 0.16),
					&"elbow_l": Vector3(0.30, 0.0, 0.0),
					&"elbow_r": Vector3(0.40, 0.0, 0.0),
					&"hip_l": Vector3(-1.00, 0.0, 0.0),
					&"hip_r": Vector3(-0.95, 0.0, 0.0),
					&"knee_l": Vector3(0.75, 0.0, 0.0),
					&"knee_r": Vector3(0.70, 0.0, 0.0),
					&"foot_l": Vector3(0.30, 0.0, 0.0),
					&"foot_r": Vector3(0.30, 0.0, 0.0),
				})},
				{"t": 0.60, "pose": _merge(bed, {
					&"body_pos": Vector3(0.0, 0.120, 0.0),
					&"body_roll": Vector3(0.0, 0.0, 2.0),
					&"body_tilt": Vector3(-1.15, 0.0, 0.0),
					&"neck": Vector3(-0.20, 0.05, 0.0),
					&"head": Vector3(0.0, 0.05, 0.0),
					&"shoulder_l": Vector3(0.0, 0.0, -0.24),
					&"shoulder_r": Vector3(0.05, 0.0, 0.20),
					&"elbow_l": Vector3(0.20, 0.0, 0.0),
					&"elbow_r": Vector3(0.30, 0.0, 0.0),
					&"hip_l": Vector3(-0.40, 0.0, 0.0),
					&"hip_r": Vector3(-0.30, 0.0, 0.0),
					&"knee_l": Vector3(0.30, 0.0, 0.0),
					&"knee_r": Vector3(0.20, 0.0, 0.0),
					&"foot_l": Vector3(0.35, 0.0, 0.0),
					&"foot_r": Vector3(0.35, 0.0, 0.0),
				})},
				{"t": 0.85, "pose": _merge(bed, {
					&"body_pos": Vector3(0.0, 0.106, 0.0),
					&"body_roll": Vector3(0.0, 0.0, 3.05),
					&"body_tilt": Vector3(-1.52, 0.0, 0.0),
					&"neck": Vector3(-0.78, 0.05, 0.22),
					&"head": Vector3(0.10, 0.04, 0.14),
					&"shoulder_l": Vector3(0.05, 0.0, -0.30),
					&"shoulder_r": Vector3(0.10, 0.0, 0.16),
					&"elbow_l": Vector3(0.20, 0.0, 0.0),
					&"elbow_r": Vector3(0.50, 0.0, 0.0),
					&"hand_r": Vector3(0.10, 0.0, 0.0),
					&"hip_l": Vector3(0.0, 0.0, 0.0),
					&"hip_r": Vector3(0.40, 0.0, 0.0),
					&"knee_l": Vector3(-0.04, 0.0, 0.0),
					&"knee_r": Vector3(-0.80, 0.0, 0.0),
					&"foot_l": Vector3(0.40, 0.0, 0.0),
					&"foot_r": Vector3(0.20, 0.0, 0.0),
				})},
				{"t": 1.0, "pose": lie},
			]
		&"sleep":
			var slp := _sleep_pose()
			return [
				{"t": 0.0, "pose": slp},
				{"t": 1.5, "pose": _merge(slp, {
					&"body_pos": Vector3(0.0, 0.099, 0.0),
					&"torso": Vector3(0.012, 0.0, 0.0),
					&"head": Vector3(0.12, 0.03, 0.14),
				})},
				{"t": 3.0, "pose": _merge(slp, {
					&"body_pos": Vector3(0.0, 0.102, 0.0),
					&"torso": Vector3(0.004, 0.0, 0.0),
					&"head": Vector3(0.14, 0.05, 0.20),
				})},
				{"t": 4.5, "pose": _merge(slp, {
					&"body_pos": Vector3(0.0, 0.099, 0.0),
					&"torso": Vector3(0.010, 0.0, 0.0),
					&"head": Vector3(0.12, 0.04, 0.16),
				})},
				{"t": 6.0, "pose": slp},
			]
		&"get_up":
			var slp2 := _sleep_pose()
			var stand2 := _stand()
			return [
				{"t": 0.0, "pose": slp2},
				{"t": 0.35, "pose": _merge(slp2, {
					&"body_pos": Vector3(0.0, 0.118, 0.0),
					&"body_roll": Vector3(0.0, 0.0, 2.40),
					&"body_tilt": Vector3(-1.20, 0.0, 0.0),
					&"neck": Vector3(-0.72, 0.04, 0.18),
					&"head": Vector3(0.10, 0.03, 0.12),
					&"hip_l": Vector3(0.10, 0.0, 0.0),
					&"hip_r": Vector3(0.20, 0.0, 0.0),
					&"knee_l": Vector3(-0.30, 0.0, 0.0),
					&"knee_r": Vector3(-0.40, 0.0, 0.0),
					&"eyelid_l": EYELID_OPEN,
					&"eyelid_r": EYELID_OPEN,
				})},
				{"t": 0.65, "pose": _merge(slp2, {
					&"body_pos": Vector3(0.0, 0.100, 0.0),
					&"body_roll": Vector3(0.0, 0.0, 1.20),
					&"body_tilt": Vector3(-0.80, 0.0, 0.0),
					&"neck": Vector3(-0.10, 0.0, 0.0),
					&"head": Vector3(-0.05, 0.0, 0.0),
					&"shoulder_l": Vector3(-0.10, 0.0, -0.14),
					&"shoulder_r": Vector3(-0.05, 0.0, 0.14),
					&"elbow_l": Vector3(0.30, 0.0, 0.0),
					&"elbow_r": Vector3(0.35, 0.0, 0.0),
					&"hip_l": Vector3(-0.60, 0.0, 0.0),
					&"hip_r": Vector3(-0.55, 0.0, 0.0),
					&"knee_l": Vector3(0.50, 0.0, 0.0),
					&"knee_r": Vector3(0.45, 0.0, 0.0),
					&"foot_l": Vector3(0.30, 0.0, 0.0),
					&"foot_r": Vector3(0.30, 0.0, 0.0),
					&"eyelid_l": EYELID_OPEN,
					&"eyelid_r": EYELID_OPEN,
				})},
				{"t": 0.85, "pose": _merge(slp2, {
					&"body_pos": Vector3(0.0, 0.060, 0.0),
					&"body_roll": Vector3(0.0, 0.0, 0.20),
					&"body_tilt": Vector3(-0.15, 0.0, 0.0),
					&"pelvis": Vector3(0.10, 0.0, 0.0),
					&"torso": Vector3(0.12, 0.0, 0.0),
					&"neck": Vector3(-0.04, 0.0, 0.0),
					&"head": Vector3(-0.04, 0.0, 0.0),
					&"shoulder_l": Vector3(0.20, 0.0, -0.08),
					&"shoulder_r": Vector3(0.20, 0.0, 0.08),
					&"elbow_l": Vector3(0.20, 0.0, 0.0),
					&"elbow_r": Vector3(0.20, 0.0, 0.0),
					&"hand_l": Vector3.ZERO,
					&"hand_r": Vector3.ZERO,
					&"hip_l": Vector3(1.10, 0.0, 0.0),
					&"hip_r": Vector3(1.05, 0.0, 0.0),
					&"knee_l": Vector3(-1.00, 0.0, 0.0),
					&"knee_r": Vector3(-0.95, 0.0, 0.0),
					&"foot_l": Vector3(-0.20, 0.0, 0.0),
					&"foot_r": Vector3(-0.20, 0.0, 0.0),
					&"eyelid_l": EYELID_OPEN,
					&"eyelid_r": EYELID_OPEN,
				})},
				{"t": 1.0, "pose": stand2},
			]
		_:
			return [{"t": 0.0, "pose": _stand()}]


## 走路 contact：lead=+1 时左脚在前。原地循环，躯干 y 起伏，脚不滑出 root 附近。
static func _walk_contact(lead: float) -> Dictionary:
	var b := _stand()
	return _merge(b, {
		&"body_pos": Vector3(lead * 0.006, 0.748, 0.0),
		&"pelvis": Vector3(0.0, 0.0, lead * 0.02),
		&"torso": Vector3(-0.02, -lead * 0.05, 0.0),
		&"neck": Vector3(0.0, lead * 0.03, 0.0),
		&"head": Vector3(0.0, lead * 0.04, 0.0),
		&"hair": Vector3(0.0, -lead * 0.02, 0.0),
		&"hip_l": Vector3(lead * 0.42, 0.0, 0.0),
		&"hip_r": Vector3(-lead * 0.38, 0.0, 0.0),
		&"knee_l": Vector3(-0.06 if lead > 0.0 else -0.12, 0.0, 0.0),
		&"knee_r": Vector3(-0.12 if lead > 0.0 else -0.06, 0.0, 0.0),
		&"foot_l": Vector3(0.10 if lead > 0.0 else 0.35, 0.0, 0.0),
		&"foot_r": Vector3(0.35 if lead > 0.0 else 0.10, 0.0, 0.0),
		&"shoulder_l": Vector3(-lead * 0.36, 0.0, -0.06),
		&"shoulder_r": Vector3(lead * 0.36, 0.0, 0.06),
		&"elbow_l": Vector3(0.18 + maxf(0.0, lead) * 0.10, 0.0, 0.0),
		&"elbow_r": Vector3(0.18 + maxf(0.0, -lead) * 0.10, 0.0, 0.0),
	})


## 走路 passing：swing=+1 时左腿抬脚通过支撑腿旁。
static func _walk_passing(swing: float) -> Dictionary:
	var b := _stand()
	return _merge(b, {
		&"body_pos": Vector3(0.0, 0.764, 0.0),
		&"pelvis": Vector3(0.0, 0.0, 0.0),
		&"torso": Vector3(0.0, 0.0, 0.0),
		&"neck": Vector3(0.0, 0.0, 0.0),
		&"head": Vector3(0.0, 0.0, 0.0),
		&"hip_l": Vector3(swing * 0.16, 0.0, 0.0),
		&"hip_r": Vector3(-swing * 0.10, 0.0, 0.0),
		&"knee_l": Vector3(-0.50 if swing > 0.0 else -0.06, 0.0, 0.0),
		&"knee_r": Vector3(-0.06 if swing > 0.0 else -0.50, 0.0, 0.0),
		&"foot_l": Vector3(0.12, 0.0, 0.0),
		&"foot_r": Vector3(0.12, 0.0, 0.0),
		&"shoulder_l": Vector3(0.0, 0.0, -0.05),
		&"shoulder_r": Vector3(0.0, 0.0, 0.05),
		&"elbow_l": Vector3(0.20, 0.0, 0.0),
		&"elbow_r": Vector3(0.20, 0.0, 0.0),
	})





# =============================================================================
# 材质 / 枢轴 / 关节
# =============================================================================

## 全角色共用的顶点色 toon 材质（IsleMath 缓存），每个部件一个 surface，静态细节并进同一 surface。
static func _toon() -> ShaderMaterial:
	if _toon_mat == null:
		_toon_mat = M.toon_material(Color.WHITE, {"vertex_color": true, "outline": 0.0025, "rim": 0.18})
	return _toon_mat


static func _pivot(parent: Node3D, node_name: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	n.position = pos
	parent.add_child(n)
	return n


static func _joint(parent: Node3D, node_name: String, pos: Vector3, kit: _Kit, mat: ShaderMaterial) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = kit.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	parent.add_child(mi)
	return mi


# =============================================================================
# 测量与统计
# =============================================================================

## 世界空间 AABB 与统计；opts {"skip_hair": true} 可排除发型子树（用于对比两种发型）。
static func measure(root: Node, opts: Dictionary = {}) -> Dictionary:
	var skip_hair := bool(opts.get("skip_hair", false))
	var hair_root := root.get_node_or_null("BodyPos/BodyRoll/BodyTilt/Pelvis/Torso/Neck/Head/Hair")
	var acc := AABB()
	var has := false
	var meshes := 0
	var surfaces := 0
	var tris := 0
	var mats := {}
	var dc := 0
	for n in _all_nodes(root):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if not _shown(mi, root):
			continue
		if skip_hair and hair_root != null and (mi == hair_root or hair_root.is_ancestor_of(mi)):
			continue
		# 网格数只统计角色本体（地面阴影贴片不算角色网格；它仍计入 DC/材质/包围盒过滤）
		if mi.name != "Shadow":
			meshes += 1
		var mat := mi.material_override
		if mat != null:
			mats[mat] = true
		var draws := 1
		var sm := mat as ShaderMaterial
		if sm != null and sm.next_pass != null:
			draws = 2
		dc += draws
		# 地面阴影贴片是 Quad 平面（y=0.035），算进身高/脚底会把 AABB 抬高；身高/脚底只统计身体
		if mi.name != "Shadow":
			var xf := mi.global_transform
			var box := mi.mesh.get_aabb()
			for i in 8:
				var p := xf * box.get_endpoint(i)
				if has:
					acc = acc.expand(p)
				else:
					acc = AABB(p, Vector3.ZERO)
					has = true
		for si in mi.mesh.get_surface_count():
			surfaces += 1
			var arrays := mi.mesh.surface_get_arrays(si)
			var idx = arrays[Mesh.ARRAY_INDEX]
			if idx != null and (idx as PackedInt32Array).size() > 0:
				tris += (idx as PackedInt32Array).size() / 3
			else:
				tris += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return {
		"ok": has,
		"height": acc.size.y,
		"min_y": acc.position.y,
		"max_y": acc.position.y + acc.size.y,
		"aabb": acc.size,
		"aabb_position": acc.position,
		"meshes": meshes,
		"surfaces": surfaces,
		"tris": tris,
		"materials": mats.size(),
		"dc_est": dc,
	}


static func _all_nodes(root: Node) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out


## 节点自身及祖先链上的 visible 都为 true（不依赖 SceneTree，便于构建后立刻测量）。
static func _shown(n: Node, root: Node) -> bool:
	var cur: Node = n
	while cur != null:
		var n3 := cur as Node3D
		if n3 != null and not n3.visible:
			return false
		if cur == root:
			break
		cur = cur.get_parent()
	return true


# =============================================================================
# 各关节几何（坐标都相对各自枢轴；静态细节全部并进同一个 surface）
# =============================================================================

static func _pelvis_kit() -> _Kit:
	var k := _Kit.new()
	# 臀部：扁一点的椭球（避免“绿内裤”鼓包），下方接两条裤口
	k.ellipsoid(Vector3(0.0, -0.016, 0.006), Vector3(0.106, 0.072, 0.094), C_OVERALL, 12, 5)
	for s in [-1.0, 1.0]:
		# 侧兜 + 兜盖
		k.box(Vector3(0.012, 0.052, 0.062), Vector3(s * 0.104, -0.012, 0.004), C_OVERALL_DARK)
		k.box(Vector3(0.014, 0.010, 0.066), Vector3(s * 0.105, 0.018, 0.004), C_OVERALL_LIGHT)
		# 后袋
		k.box(Vector3(0.052, 0.042, 0.010), Vector3(s * 0.046, -0.010, 0.104), C_OVERALL_PALE)
		k.box(Vector3(0.052, 0.008, 0.012), Vector3(s * 0.046, 0.012, 0.104), C_OVERALL_DARK)
	# 腰头接缝
	k.box(Vector3(0.200, 0.008, 0.164), Vector3(0.0, 0.046, 0.004), C_OVERALL_DARK)
	return k

## 胸口（躯干局部坐标）在 (x, y) 处最靠前的表面 z：优先白衬衫椭球，超出范围时退回背带裤腰身
static func _chest_front_z(x: float, y: float) -> float:
	var u := x / 0.146
	var v := (y - 0.138) / 0.104
	var d := 1.0 - u * u - v * v
	if d > 0.02:
		return -0.120 * sqrt(d)
	return -0.105


## 贴合胸/腹曲面的一块“布片”（围兜、口袋共用）：前表面沿躯干曲面偏移、背面深色、四边封口
static func _cloth_patch(k: _Kit, half_w: float, y_bot: float, y_top: float, cols: int, rows: int,
		off: float, thick: float, col: Color, edge_col: Color) -> void:
	var front: Array = []
	var back: Array = []
	var nrm: Array = []
	for j in rows + 1:
		var y := lerpf(y_bot, y_top, float(j) / float(rows))
		var rf: Array = []
		var rb: Array = []
		var rn: Array = []
		for i in cols + 1:
			var x := lerpf(-half_w, half_w, float(i) / float(cols))
			var zf := _chest_front_z(x, y) - off
			rf.append(Vector3(x, y, zf))
			rb.append(Vector3(x, y, zf + thick))
			rn.append(Vector3(x * 6.0, (y - 0.14) * 5.0, -1.0).normalized())
		front.append(rf)
		back.append(rb)
		nrm.append(rn)
	for j in rows:
		for i in cols:
			k.tri(front[j][i], front[j][i + 1], front[j + 1][i + 1], col, col, col,
				nrm[j][i], nrm[j][i + 1], nrm[j + 1][i + 1])
			k.tri(front[j][i], front[j + 1][i + 1], front[j + 1][i], col, col, col,
				nrm[j][i], nrm[j + 1][i + 1], nrm[j + 1][i])
			k.tri(back[j][i], back[j + 1][i + 1], back[j][i + 1], edge_col, edge_col, edge_col,
				-nrm[j][i], -nrm[j + 1][i + 1], -nrm[j][i + 1])
			k.tri(back[j][i], back[j + 1][i], back[j + 1][i + 1], edge_col, edge_col, edge_col,
				-nrm[j][i], -nrm[j + 1][i], -nrm[j + 1][i + 1])
	var down := Vector3.DOWN
	var up := Vector3.UP
	for i in cols:
		k.tri(front[0][i], front[0][i + 1], back[0][i + 1], edge_col, edge_col, edge_col, down, down, down)
		k.tri(front[0][i], back[0][i + 1], back[0][i], edge_col, edge_col, edge_col, down, down, down)
		k.tri(front[rows][i], back[rows][i + 1], front[rows][i + 1], edge_col, edge_col, edge_col, up, up, up)
		k.tri(front[rows][i], back[rows][i], back[rows][i + 1], edge_col, edge_col, edge_col, up, up, up)
	var left := Vector3.LEFT
	var right := Vector3.RIGHT
	for j in rows:
		k.tri(front[j][0], back[j][0], back[j + 1][0], edge_col, edge_col, edge_col, left, left, left)
		k.tri(front[j][0], back[j + 1][0], front[j + 1][0], edge_col, edge_col, edge_col, left, left, left)
		k.tri(front[j][cols], front[j + 1][cols], back[j + 1][cols], edge_col, edge_col, edge_col, right, right, right)
		k.tri(front[j][cols], back[j + 1][cols], back[j][cols], edge_col, edge_col, edge_col, right, right, right)


static func _torso_kit() -> _Kit:
	var k := _Kit.new()
	# 背带裤腰身（圆润的桶形，不再是方盒）+ 浅绿腰线
	k.cylinder(0.098, 0.118, 0.086, Vector3(0.0, -0.014, 0.002), C_OVERALL, Vector3.ZERO, 12)
	# 白衬衫：椭球躯干（侧面也有厚度，不再是薄纸片）+ 圆肩
	k.ellipsoid(Vector3(0.0, 0.138, 0.0), Vector3(0.128, 0.100, 0.108), C_SHIRT, 12, 6)
	for s in [-1.0, 1.0]:
		k.ellipsoid(Vector3(s * 0.112, 0.196, 0.0), Vector3(0.030, 0.030, 0.048), C_SHIRT, 8, 3)
	# 领口（薄环 + 领口内深色，露出 2~3cm 皮肤颈）
	k.cylinder(0.056, 0.062, 0.016, Vector3(0.0, 0.222, 0.0), C_SHIRT_SHADOW, Vector3.ZERO, 12)
	k.cylinder(0.052, 0.054, 0.010, Vector3(0.0, 0.230, 0.0), C_SKIN_SHADOW, Vector3.ZERO, 12)
	# 围兜：贴合胸腹曲面的布片（浅绿）
	_cloth_patch(k, 0.090, 0.024, 0.194, 5, 4, 0.002, 0.005, C_OVERALL_PALE, C_OVERALL_DARK)
	# 围兜前袋：同样贴曲面的小袋布 + 袋口/袋底缝线
	_cloth_patch(k, 0.046, 0.056, 0.108, 3, 2, 0.009, 0.005, C_OVERALL_LIGHT, C_OVERALL_DARK)
	k.box(Vector3(0.096, 0.006, 0.008), Vector3(0.0, 0.106, -0.126), C_OVERALL_DARK)
	k.box(Vector3(0.090, 0.004, 0.008), Vector3(0.0, 0.049, -0.128), C_OVERALL_DARK)
	# 口袋工具：只露一小截木柄（下端藏进袋口）
	k.cylinder(0.006, 0.006, 0.052, Vector3(0.020, 0.130, -0.131), C_WOOD, Vector3(0.0, 0.0, -0.14), 6)
	# 双肩带（中绿，比围兜深一档；前段/过肩段/后段三段贴合身体）
	for s in [-1.0, 1.0]:
		k.box(Vector3(0.034, 0.044, 0.012), Vector3(s * 0.076, 0.201, -0.077), C_OVERALL, Vector3(0.40, 0.0, 0.0))
		k.box(Vector3(0.034, 0.012, 0.120), Vector3(s * 0.076, 0.221, 0.010), C_OVERALL)
		k.box(Vector3(0.034, 0.038, 0.012), Vector3(s * 0.076, 0.198, 0.072), C_OVERALL, Vector3(-0.35, 0.0, 0.0))
		# 简洁圆扣：深绿底环 + 黄铜面
		k.cylinder(0.011, 0.011, 0.006, Vector3(s * 0.076, 0.183, -0.097), C_OVERALL_DARK,
			Vector3(PI * 0.5, 0.0, 0.0), 8)
		k.cylinder(0.0070, 0.0070, 0.008, Vector3(s * 0.076, 0.183, -0.099), C_BRASS,
			Vector3(PI * 0.5, 0.0, 0.0), 6)
	# 后背布片（浅绿，贴在白衬衫背面）
	k.box(Vector3(0.150, 0.110, 0.012), Vector3(0.0, 0.100, 0.108), C_OVERALL_PALE)
	# 脖子：皮肤圆柱，被领口压住一半
	k.cylinder(0.048, 0.053, 0.100, Vector3(0.0, 0.248, 0.002), C_SKIN, Vector3.ZERO, 10)
	return k


static func _head_kit() -> _Kit:
	var k := _Kit.new()
	# 头骨：略窄的蛋形（宽高比 0.90），总高仍由发顶保证 1.500
	k.ellipsoid(HEAD_CENTER, HEAD_RADIUS, C_SKIN, 14, 8)
	# 下颌 + 双颊：收窄的小下巴（更接近儿童的圆脸）
	k.ellipsoid(Vector3(0.0, 0.106, -0.008), Vector3(0.090, 0.072, 0.096), C_SKIN, 10, 4)
	for s in [-1.0, 1.0]:
		k.ellipsoid(Vector3(s * 0.056, 0.118, -0.046), Vector3(0.036, 0.034, 0.036), C_SKIN, 6, 3)
	# 小圆弧耳（贴头侧、略向后张）+ 内耳折
	for s in [-1.0, 1.0]:
		k.ellipsoid_rot(Vector3(s * 0.126, 0.132, -0.004), Vector3(0.013, 0.026, 0.019), C_SKIN,
			Vector3(0.0, s * 0.30, s * -0.10), 6, 3)
		k.ellipsoid_rot(Vector3(s * 0.131, 0.130, -0.007), Vector3(0.005, 0.012, 0.008), C_SKIN_SHADOW,
			Vector3(0.0, s * 0.30, 0.0), 4, 2)
	# 眼：眼白嵌进脸面只露正面 + 深棕虹膜 + 小高光 + 细上眼线（贴着上眼睑，不要浮在眼睛上方）
	for s in [-1.0, 1.0]:
		k.ellipsoid(Vector3(s * 0.052, 0.162, -0.112), Vector3(0.027, 0.031, 0.015), C_EYE_WHITE, 8, 3)
		k.ellipsoid(Vector3(s * 0.052, 0.159, -0.124), Vector3(0.019, 0.022, 0.008), C_HAIR_DARK, 6, 3)
		k.ellipsoid(Vector3(s * 0.056, 0.166, -0.131), Vector3(0.005, 0.006, 0.0035), C_EYE_WHITE, 4, 2)
		k.ellipsoid_rot(Vector3(s * 0.052, 0.180, -0.126), Vector3(0.023, 0.0026, 0.0045), C_EYE_DARK,
			Vector3(0.0, 0.0, s * 0.14), 6, 2)
	# 眉毛：细、外端略挑，位置在刘海下可读
	for s in [-1.0, 1.0]:
		k.ellipsoid_rot(Vector3(s * 0.050, 0.204, -0.122), Vector3(0.018, 0.0032, 0.005), C_HAIR,
			Vector3(0.0, 0.0, s * -0.18), 4, 2)
	# 鼻子：只做很小的鼻尖凸起（同肤色，不要大球）
	k.ellipsoid(Vector3(0.0, 0.113, -0.123), Vector3(0.008, 0.009, 0.008), C_SKIN, 8, 3)
	# 嘴：一条细微笑线（三小段，深棕，不要厚粉唇）
	k.ellipsoid(Vector3(0.0, 0.074, -0.105), Vector3(0.014, 0.0035, 0.004), C_MOUTH, 4, 2)
	for s in [-1.0, 1.0]:
		k.ellipsoid_rot(Vector3(s * 0.013, 0.079, -0.104), Vector3(0.009, 0.0035, 0.004), C_MOUTH,
			Vector3(0.0, 0.0, s * 0.55), 4, 2)
	# 腮红：贴着脸颊曲面、低饱和、小片（不凸出）
	for s in [-1.0, 1.0]:
		k.ellipsoid_rot(Vector3(s * 0.063, 0.126, -0.085), Vector3(0.021, 0.009, 0.0022), C_BLUSH_SOFT,
			Vector3(0.0, s * 0.60, 0.0), 8, 2)
	return k

static func _eyelid_kit() -> _Kit:
	# 眼睑枢轴在眼睛正上方；开态 rotation.x = -1.55（藏进头里），闭态 0 盖住眼睛。
	var k := _Kit.new()
	k.ellipsoid(Vector3(0.0, -0.030, -0.006), Vector3(0.030, 0.030, 0.020), C_SKIN, 8, 3)
	k.ellipsoid_rot(Vector3(0.0, -0.056, -0.010), Vector3(0.028, 0.004, 0.006), C_HAIR_DARK,
		Vector3.ZERO, 6, 2)
	return k


static func _shoulder_kit(_side: float) -> _Kit:
	var k := _Kit.new()
	# 合身短袖：袖山（半径收小、段数够）+ 袖筒到肘弯上方 + 清楚袖口，下面露出小臂皮肤
	k.ellipsoid(Vector3(0.0, -0.006, 0.0), Vector3(0.042, 0.036, 0.044), C_SHIRT, 10, 4)
	k.cylinder(0.042, 0.037, 0.160, Vector3(0.0, -0.084, 0.0), C_SHIRT, Vector3.ZERO, 10)
	k.cylinder(0.038, 0.040, 0.014, Vector3(0.0, -0.160, 0.0), C_SHIRT_SHADOW, Vector3.ZERO, 10)
	return k

## 前臂 + 手掌合并成一个 surface（手掌原在 Hand 枢轴 (0,-WRIST_LEN,0)，这里直接烘进前臂局部坐标）
## 前臂 + 手掌合并成一个 surface（手掌原在 Hand 枢轴 (0,-WRIST_LEN,0)，这里直接烘进前臂局部坐标）
static func _elbow_kit(side: float) -> _Kit:
	var k := _Kit.new()
	# 前臂（皮肤，与脸同色）+ 圆肘
	k.ellipsoid(Vector3.ZERO, Vector3(0.039, 0.041, 0.039), C_SKIN, 8, 4)
	k.cylinder(0.038, 0.032, 0.150, Vector3(0.0, -0.080, 0.0), C_SKIN, Vector3.ZERO, 8)
	# 手掌：简化连指手掌 + 拇指（对称、皮肤色、圆润）
	var hy := -WRIST_LEN
	k.ellipsoid(Vector3(0.0, hy - 0.036, 0.0), Vector3(0.025, 0.046, 0.034), C_SKIN, 8, 4)
	k.ellipsoid(Vector3(0.0, hy - 0.082, -0.006), Vector3(0.024, 0.028, 0.032), C_SKIN, 8, 3)
	k.ellipsoid_rot(Vector3(-side * 0.027, hy - 0.036, -0.020), Vector3(0.012, 0.026, 0.015), C_SKIN,
		Vector3(0.0, 0.0, -side * 0.35), 6, 3)
	return k


static func _hip_kit(side: float) -> _Kit:
	var k := _Kit.new()
	# 髋部平滑过渡（包在骨盆椭球内），大腿上下连续、不再出现单独“膝球”
	k.ellipsoid(Vector3.ZERO, Vector3(0.050, 0.054, 0.058), C_OVERALL, 8, 3)
	k.ellipsoid(Vector3(0.0, -0.090, 0.0), Vector3(0.055, 0.080, 0.058), C_OVERALL, 8, 3)
	k.cylinder(0.058, 0.053, 0.240, Vector3(0.0, -0.230, 0.0), C_OVERALL, Vector3.ZERO, 8)
	# 外侧缝线（深一档绿，贴腿侧）
	k.box(Vector3(0.008, 0.230, 0.020), Vector3(side * 0.056, -0.230, 0.008), C_OVERALL_DARK)
	return k

static func _knee_kit(_side: float) -> _Kit:
	var k := _Kit.new()
	# 膝下裤管（与大腿同径过渡）+ 防水靴筒 + 浅绿翻边（裤腿压住靴口）
	k.cylinder(0.055, 0.052, 0.170, Vector3(0.0, -0.085, 0.0), C_OVERALL, Vector3.ZERO, 8)
	k.cylinder(0.059, 0.063, 0.180, Vector3(0.0, -0.222, 0.0), C_BOOT, Vector3.ZERO, 8)
	k.cylinder(0.064, 0.066, 0.024, Vector3(0.0, -0.140, 0.0), C_OVERALL_LIGHT, Vector3.ZERO, 8)
	# 靴带 + 小铜扣（贴靴面前方）
	k.box(Vector3(0.078, 0.014, 0.012), Vector3(0.0, -0.148, -0.064), C_OVERALL_DARK)
	k.cylinder(0.007, 0.007, 0.010, Vector3(0.0, -0.148, -0.072), C_BRASS, Vector3(PI * 0.5, 0.0, 0.0), 6)
	return k

static func _foot_kit(_side: float) -> _Kit:
	var k := _Kit.new()
	# 鞋底：底面 = 世界 y=0 基准（foot 枢轴世界 0.100）
	k.box(Vector3(0.096, 0.028, 0.236), Vector3(0.0, -0.086, -0.046), C_SOLE)
	# 脚踝 + 脚背 + 圆鞋头（三段椭球拼出圆润靴头）
	k.ellipsoid(Vector3(0.0, -0.012, 0.004), Vector3(0.054, 0.048, 0.060), C_BOOT, 8, 4)
	k.ellipsoid(Vector3(0.0, -0.046, -0.054), Vector3(0.052, 0.042, 0.086), C_BOOT, 8, 3)
	k.ellipsoid(Vector3(0.0, -0.052, -0.120), Vector3(0.046, 0.034, 0.048), C_BOOT, 8, 3)
	# 后跟
	k.box(Vector3(0.078, 0.048, 0.038), Vector3(0.0, -0.042, 0.058), C_BOOT)
	return k


# =============================================================================
# 发型：贴着头骨生长的发帽（外/内双层 + 发缘侧壁）+ 独立发缕（短刘海 / 中分 / 侧发 / 后帘）。
# 两种发型共用 C_HAIR 色系与同一颗头骨，发顶都严格落在世界 y = 1.500。
# φ=0 朝前(-Z)，φ=π 朝后(+Z)；θ 从发顶(0)量到发缘 θ_rim(φ)。
# =============================================================================

static func _hair_color(t: float) -> Color:
	# t=0 发顶偏亮，t=1 发缘/发尾最深
	return C_HAIR_LIGHT.lerp(C_HAIR, clampf(t, 0.0, 1.0))


## 头骨表面上的点（hair 局部坐标）
static func _hair_base(theta: float, phi: float) -> Vector3:
	return HAIR_CENTER + Vector3(
		HAIR_RADIUS.x * sin(theta) * sin(phi),
		HAIR_RADIUS.y * cos(theta),
		-HAIR_RADIUS.z * sin(theta) * cos(phi))


## 头骨椭球在该方向的外法线
static func _hair_normal(theta: float, phi: float) -> Vector3:
	var d := Vector3(sin(theta) * sin(phi), cos(theta), -sin(theta) * cos(phi))
	return Vector3(d.x / HAIR_RADIUS.x, d.y / HAIR_RADIUS.y, d.z / HAIR_RADIUS.z).normalized()


## 发缘角：前额最高、两侧渐低、后脑最低（用幂次让侧面下降更自然）
static func _hair_rim_theta(phi: float, theta_front: float, theta_back: float) -> float:
	var w := pow((1.0 - cos(phi)) * 0.5, 0.62)
	return lerpf(theta_front, theta_back, w)


## 发帽厚度：发顶最厚（保证 1.500），向发缘收薄
static func _hair_thick(s: float) -> float:
	return lerpf(HAIR_THICK_TOP, HAIR_THICK_RIM, pow(clampf(s, 0.0, 1.0), 1.4))


## 发帽：外表面 + 深色内表面 + 发缘侧壁，贴着同一颗头骨，和刘海根部连续
## bangs>0 时前额发缘做连续波浪（替代独立刘海片，避免发帽与刘海之间出现“帽檐”接缝）
static func _hair_shell(k: _Kit, theta_front: float, theta_back: float, seg: int, rings: int,
		bangs: float = 0.0) -> void:
	var outer: Array = []
	var inner: Array = []
	var nrms: Array = []
	for i in seg:
		var phi := TAU * float(i) / float(seg)
		var th_rim := _hair_rim_theta(phi, theta_front, theta_back)
		if bangs > 0.0:
			# 只在正前方 ±1.25 rad 内加波浪，向下延长成 6~7 缕刘海底缘
			var ps := wrapf(phi, -PI, PI)
			var wf := clampf(1.0 - absf(ps) / 1.25, 0.0, 1.0)
			wf = wf * wf * (3.0 - 2.0 * wf)
			th_rim += wf * bangs * (0.5 + 0.5 * cos(ps * 9.0))
		var ring_o := PackedVector3Array()
		var ring_i := PackedVector3Array()
		var ring_n := PackedVector3Array()
		for j in range(1, rings + 1):
			var s := float(j) / float(rings)
			var theta := th_rim * s
			var base := _hair_base(theta, phi)
			var n := _hair_normal(theta, phi)
			var t := _hair_thick(s)
			ring_o.append(base + n * t)
			ring_i.append(base + n * (t - 0.008))
			ring_n.append(n)
		outer.append(ring_o)
		inner.append(ring_i)
		nrms.append(ring_n)
	var pole_o := _hair_base(0.0, 0.0) + Vector3.UP * HAIR_THICK_TOP
	var pole_i := _hair_base(0.0, 0.0) + Vector3.UP * (HAIR_THICK_TOP - 0.008)
	var top_c := _hair_color(0.0)
	# 外表面
	for i in seg:
		var i2 := (i + 1) % seg
		for j in rings - 1:
			var ta := float(j + 1) / float(rings)
			var tb := float(j + 2) / float(rings)
			var ca := _hair_color(ta)
			var cb := _hair_color(tb)
			k.tri(outer[i][j], outer[i2][j], outer[i2][j + 1], ca, ca, cb,
				nrms[i][j], nrms[i2][j], nrms[i2][j + 1])
			k.tri(outer[i][j], outer[i2][j + 1], outer[i][j + 1], ca, cb, cb,
				nrms[i][j], nrms[i2][j + 1], nrms[i][j + 1])
		k.tri(pole_o, outer[i][0], outer[i2][0], top_c, _hair_color(1.0 / float(rings)), _hair_color(1.0 / float(rings)),
			Vector3.UP, nrms[i][0], nrms[i2][0])
	# 内表面（反向法线、深色，发帽内壁不发黑/不漏空）
	var dark := C_HAIR_DARK
	for i in seg:
		var i2 := (i + 1) % seg
		for j in rings - 1:
			k.tri(inner[i][j], inner[i2][j + 1], inner[i2][j], dark, dark, dark,
				-nrms[i][j], -nrms[i2][j + 1], -nrms[i2][j])
			k.tri(inner[i][j], inner[i][j + 1], inner[i2][j + 1], dark, dark, dark,
				-nrms[i][j], -nrms[i][j + 1], -nrms[i2][j + 1])
		k.tri(pole_i, inner[i2][0], inner[i][0], dark, dark, dark,
			Vector3.DOWN, -nrms[i2][0], -nrms[i][0])
	# 发缘侧壁（发帽的厚度）
	for i in seg:
		var i2 := (i + 1) % seg
		var c := C_HAIR
		var last := rings - 1
		k.tri(outer[i][last], outer[i2][last], inner[i2][last], c, c, c,
			nrms[i][last], nrms[i2][last], nrms[i2][last])
		k.tri(outer[i][last], inner[i2][last], inner[i][last], c, c, c,
			nrms[i][last], nrms[i2][last], nrms[i][last])


## 一缕头发：沿 pts 的锥形厚片，宽度沿 right、厚度沿 outward（outward 指向发缕正面）。
## 四角每行，正/背/左/右/发梢五个面，绕序由 tri() 按法线自动修正。
static func _hair_strand(k: _Kit, pts: Array, widths: Array, thicks: Array,
		right: Vector3, outward: Vector3, col_root: Color, col_tip: Color) -> void:
	var rows := pts.size()
	var quads: Array = []
	var cols: Array = []
	for i in rows:
		var c: Vector3 = pts[i]
		var r := right * (float(widths[i]) * 0.5)
		var o := outward * (float(thicks[i]) * 0.5)
		quads.append([c - r - o, c + r - o, c + r + o, c - r + o])
		cols.append(col_root.lerp(col_tip, float(i) / float(maxi(rows - 1, 1))))
	for i in rows - 1:
		var a: Array = quads[i]
		var b: Array = quads[i + 1]
		var ca: Color = cols[i]
		var cb: Color = cols[i + 1]
		# 正面（朝 outward）
		k.tri(a[3], b[3], b[2], ca, cb, cb, outward, outward, outward)
		k.tri(a[3], b[2], a[2], ca, cb, ca, outward, outward, outward)
		# 背面
		k.tri(a[0], a[1], b[1], ca, ca, cb, -outward, -outward, -outward)
		k.tri(a[0], b[1], b[0], ca, cb, cb, -outward, -outward, -outward)
		# 左侧面
		k.tri(a[0], b[0], b[3], ca, cb, cb, -right, -right, -right)
		k.tri(a[0], b[3], a[3], ca, cb, ca, -right, -right, -right)
		# 右侧面
		k.tri(a[1], a[2], b[2], ca, ca, cb, right, right, right)
		k.tri(a[1], b[2], b[1], ca, cb, cb, right, right, right)
	# 发梢封口
	var last: Array = quads[rows - 1]
	var p_last: Vector3 = pts[rows - 1]
	var p_prev: Vector3 = pts[rows - 2]
	var tip_n := (p_last - p_prev).normalized()
	var ct: Color = cols[rows - 1]
	k.tri(last[0], last[1], last[2], ct, ct, ct, tip_n, tip_n, tip_n)
	k.tri(last[0], last[2], last[3], ct, ct, ct, tip_n, tip_n, tip_n)


## 头骨椭球在 (x, y) 处的前表面 z（输入/输出都是 hair 局部坐标；y 会先换算到头关节坐标）
static func _head_surface_z(x: float, y_hair: float) -> float:
	var y := y_hair + HAIR_Y
	var u := clampf(x / HEAD_RADIUS.x, -0.98, 0.98)
	var v := clampf((y - HEAD_CENTER.y) / HEAD_RADIUS.y, -0.98, 0.98)
	return HEAD_CENTER.z - HEAD_RADIUS.z * sqrt(maxf(1.0 - u * u - v * v, 0.0))


## 刘海面的近似外法线：整体朝 -Z，向下(/外)逐渐变陡，两侧随 x 外张
static func _fringe_normal(x: float, t: float) -> Vector3:
	return Vector3(x * 1.6, -0.12 - 0.38 * t, -1.0).normalized()


## 连续刘海片（贴额头曲面）：cols 列 × rows 行；底缘长度用正弦叠加出 5~6 缕波浪，
## 顶部藏在发帽里面（z 更靠后），向下逐渐离开额头 → 与发帽连续、没有锯齿缝。
## medium=true 时中间留分缝、两侧发梢更长。
static func _hair_fringe(k: _Kit, theta_front: float, cols: int, rows: int, medium: bool) -> void:
	var rim_y: float = HAIR_CENTER.y + HAIR_RADIUS.y * cos(theta_front)
	var x_max := 0.112
	var grid_o: Array = []
	var grid_i: Array = []
	var xs: Array = []
	for i in cols + 1:
		var u := float(i) / float(cols) * 2.0 - 1.0
		var x := u * x_max
		var ry := rim_y - 1.7 * x * x
		var plen := 0.048 + 0.011 * sin(x * 24.0 + 0.4) + 0.006 * sin(x * 53.0 + 1.7)
		if medium:
			plen += 0.012 - 0.044 * exp(-pow(x / 0.034, 2.0))
		plen = maxf(plen, 0.012)
		var top := ry + 0.022
		var bottom := ry - plen
		var ring_o := PackedVector3Array()
		var ring_i := PackedVector3Array()
		for j in rows:
			var t := float(j) / float(rows - 1)
			var y := lerpf(top, bottom, t)
			var xx := x * (1.0 - 0.10 * t)
			var z := _head_surface_z(xx, y) - lerpf(0.0045, 0.0085, t) + 0.018 * pow(absf(u), 3.0)
			ring_o.append(Vector3(xx, y, z))
			ring_i.append(Vector3(xx, y, z + 0.012))
		grid_o.append(ring_o)
		grid_i.append(ring_i)
		xs.append(x)
	# 前表面（朝 -Z）：发根偏亮、发梢最深
	for i in cols:
		for j in rows - 1:
			var t0 := float(j) / float(rows - 1)
			var t1 := float(j + 1) / float(rows - 1)
			var ca := _hair_color(0.08 + t0 * 0.85)
			var cb := _hair_color(0.08 + t1 * 0.85)
			var n0 := _fringe_normal(xs[i], t0)
			var n1 := _fringe_normal(xs[i + 1], t0)
			var n2 := _fringe_normal(xs[i + 1], t1)
			var n3 := _fringe_normal(xs[i], t1)
			k.tri(grid_o[i][j], grid_o[i + 1][j], grid_o[i + 1][j + 1], ca, ca, cb, n0, n1, n2)
			k.tri(grid_o[i][j], grid_o[i + 1][j + 1], grid_o[i][j + 1], ca, cb, cb, n0, n2, n3)
			# 内层（深色，朝 +Z 埋进额头）
			k.tri(grid_i[i][j], grid_i[i + 1][j + 1], grid_i[i + 1][j], C_HAIR_DARK, C_HAIR_DARK, C_HAIR_DARK, -n0, -n2, -n1)
			k.tri(grid_i[i][j], grid_i[i][j + 1], grid_i[i + 1][j + 1], C_HAIR_DARK, C_HAIR_DARK, C_HAIR_DARK, -n0, -n3, -n2)
	# 底缘封口
	for i in cols:
		var b := rows - 1
		k.tri(grid_o[i][b], grid_o[i + 1][b], grid_i[i + 1][b], C_HAIR_DARK, C_HAIR_DARK, C_HAIR_DARK, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN)
		k.tri(grid_o[i][b], grid_i[i + 1][b], grid_i[i][b], C_HAIR_DARK, C_HAIR_DARK, C_HAIR_DARK, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN)
	# 两侧封口
	for e in [0, cols]:
		var ns := Vector3(-1.0 if e == 0 else 1.0, 0.0, 0.0)
		for j in rows - 1:
			k.tri(grid_o[e][j], grid_o[e][j + 1], grid_i[e][j + 1], C_HAIR_DARK, C_HAIR_DARK, C_HAIR_DARK, ns, ns, ns)
			k.tri(grid_o[e][j], grid_i[e][j + 1], grid_i[e][j], C_HAIR_DARK, C_HAIR_DARK, C_HAIR_DARK, ns, ns, ns)


## 短发（偏男性）：贴头发帽 + 连续短刘海（底缘 5~6 缕波浪）+ 短鬓角，发顶 1.500
static func _hair_short_kit() -> _Kit:
	var k := _Kit.new()
	_hair_shell(k, 0.82, 1.70, 30, 6, 0.26)
	# 短发不加独立鬓角/侧片：发缘波浪本身收成侧发，避免脸侧出现小方片
	return k


## 中长发（偏女性）：贴头发帽 + 中分连续长刘海（两侧斜下、中间露额头）
## + 两层及颌侧发 + 及肩后帘，发顶同样 1.500
static func _hair_medium_kit() -> _Kit:
	var k := _Kit.new()
	_hair_shell(k, 0.86, 1.60, 30, 6, 0.24)
	for s in [-1.0, 1.0]:
		# 外层长发缕：沿脸侧向下、略外扩再内收，发梢到下颌以下
		var phi: float = s * 1.34
		var th := _hair_rim_theta(phi, 0.86, 1.60)
		var root := _hair_base(th, phi) + _hair_normal(th, phi) * (HAIR_THICK_RIM - 0.004)
		var pts: Array = []
		var widths: Array = []
		var thicks: Array = []
		for j in 7:
			var t := float(j) / 6.0
			pts.append(root + Vector3(s * (0.002 * t + 0.014 * sin(t * PI)), -0.215 * t,
				0.028 * t - 0.008 * t * t))
			widths.append(lerpf(0.058, 0.012, t * t))
			thicks.append(lerpf(0.015, 0.005, t))
		_hair_strand(k, pts, widths, thicks, Vector3(0.0, 0.0, 1.0), Vector3(s, 0.0, 0.0),
			C_HAIR, C_HAIR_DARK)
	_hair_back_curtain(k)
	return k


## 中长发后帘：从后发缘垂到肩胛（世界约 1.04 m），两层带厚度、底缘做波浪、两侧封口
static func _hair_back_curtain(k: _Kit) -> void:
	var cols := 8
	var rows := 5
	var outer: Array = []
	var inner: Array = []
	var nrms: Array = []
	for i in cols + 1:
		var u := float(i) / float(cols) * 2.0 - 1.0
		var phi := PI + u * 1.02
		var th := _hair_rim_theta(phi, 0.90, 1.62)
		var root := _hair_base(th, phi) + _hair_normal(th, phi) * (HAIR_THICK_RIM - 0.004)
		var bottom_y := -0.238 + 0.016 * sin(u * 4.2 + 0.6)
		var ring_o := PackedVector3Array()
		var ring_i := PackedVector3Array()
		var ring_n := PackedVector3Array()
		for j in rows:
			var t := float(j) / float(rows - 1)
			var y := lerpf(root.y, bottom_y, t)
			var f := 1.0 + 0.10 * sin(t * PI)
			var x := root.x * f
			var z := lerpf(root.z, root.z + 0.014, t)
			var p := Vector3(x, y, z)
			var n := Vector3(x, 0.0, z).normalized()
			ring_o.append(p)
			ring_i.append(p - n * 0.010)
			ring_n.append(n)
		outer.append(ring_o)
		inner.append(ring_i)
		nrms.append(ring_n)
	for i in cols:
		for j in rows - 1:
			var ta := float(j) / float(rows - 1)
			var tb := float(j + 1) / float(rows - 1)
			var ca := C_HAIR.lerp(C_HAIR_DARK, ta)
			var cb := C_HAIR.lerp(C_HAIR_DARK, tb)
			k.tri(outer[i][j], outer[i + 1][j], outer[i + 1][j + 1], ca, ca, cb,
				nrms[i][j], nrms[i + 1][j], nrms[i + 1][j + 1])
			k.tri(outer[i][j], outer[i + 1][j + 1], outer[i][j + 1], ca, cb, cb,
				nrms[i][j], nrms[i + 1][j + 1], nrms[i][j + 1])
			k.tri(inner[i][j], inner[i + 1][j + 1], inner[i + 1][j], C_HAIR_DARK, C_HAIR_DARK, C_HAIR_DARK,
				-nrms[i][j], -nrms[i + 1][j + 1], -nrms[i + 1][j])
			k.tri(inner[i][j], inner[i][j + 1], inner[i + 1][j + 1], C_HAIR_DARK, C_HAIR_DARK, C_HAIR_DARK,
				-nrms[i][j], -nrms[i][j + 1], -nrms[i + 1][j + 1])
		var b := rows - 1
		k.tri(outer[i][b], outer[i + 1][b], inner[i + 1][b], C_HAIR_DARK, C_HAIR_DARK, C_HAIR_DARK,
			Vector3.DOWN, Vector3.DOWN, Vector3.DOWN)
		k.tri(outer[i][b], inner[i + 1][b], inner[i][b], C_HAIR_DARK, C_HAIR_DARK, C_HAIR_DARK,
			Vector3.DOWN, Vector3.DOWN, Vector3.DOWN)
	for s in [0, cols]:
		var n_side := Vector3(1.0 if s == 0 else -1.0, 0.0, 0.0)
		for j in rows - 1:
			k.tri(outer[s][j], outer[s][j + 1], inner[s][j + 1],
				C_HAIR_DARK, C_HAIR_DARK, C_HAIR_DARK, n_side, n_side, n_side)
			k.tri(outer[s][j], inner[s][j + 1], inner[s][j],
				C_HAIR_DARK, C_HAIR_DARK, C_HAIR_DARK, n_side, n_side, n_side)
