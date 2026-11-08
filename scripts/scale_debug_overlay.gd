extends Node3D
## P7-V3.2 开发模式尺度标尺（T1 交付 D）——默认不创建、不显示、零常驻开销。
##
## 安装（main.gd，由 T4 挂钩；3–5 行）：
##   const ScaleOverlay := preload("res://scripts/scale_debug_overlay.gd")
##   if ScaleOverlay.enabled():
##       var ov := ScaleOverlay.new()
##       ov.name = "ScaleDebugOverlay"
##       add_child(ov)
##
## 命令行（用户参数，放在 -- 之后）：
##   --scale-debug                       启用标尺（1 m 参照立方 + 1.50 m 人形 + 垂直/水平标尺 + 标注）
##   --scale-debug-x <float> --scale-debug-z <float>   标尺落点（世界 XZ，默认小屋门前）
##
## 关闭：ov.set_debug_visible(false) 只切 visible；ov.rebuild() 手动重建；不新增材质（复用 IsleMath 缓存）。
## 开销：只在 _ready 构建一次；无 _process/_physics_process；网格最后交给 IsleBatch 合批一次。

const Spec := preload("res://scripts/isle_scale_spec.gd")
const Figure := preload("res://scripts/isle_scale_figure.gd")
const M := preload("res://scripts/isle_math.gd")
const Batch := preload("res://scripts/isle_batch.gd")

const C_CUBE := Color("22e0ff")
const C_RULER := Color("ffd23f")
const C_AXIS_X := Color("ff4d4d")
const C_AXIS_Y := Color("4dff88")
const C_AXIS_Z := Color("4d9bff")
const C_LABEL := Color("e8f6ff")
const C_LABEL_WARN := Color("ffcf7a")

const _OPTS := {"outline": 0.010, "rim": 0.15}

var _anchor := Vector3.ZERO
var _figure: Node3D = null
var _labels: Array = []
var _built := false

func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	_anchor = _resolve_anchor()
	_build()
	_built = true

## 是否由 CLI 打开（main.gd 挂钩用；两个命令行入口都查）。
static func enabled() -> bool:
	for a in OS.get_cmdline_user_args():
		if String(a) == "--scale-debug":
			return true
	for b in OS.get_cmdline_args():
		if String(b) == "--scale-debug":
			return true
	return false

func set_debug_visible(v: bool) -> void:
	visible = v

func is_built() -> bool:
	return _built

func rebuild() -> void:
	for c in get_children():
		c.free()
	_labels.clear()
	_figure = null
	_anchor = _resolve_anchor()
	_build()

func _build() -> void:
	_anchor.y = _ground_y(_anchor.x, _anchor.z)
	# 1 m 参照立方（棱线）
	_cube_edges(_anchor + Vector3(1.05, 0.5, 0.0), 1.0)
	# 1.50 m 人形参照
	_figure = Figure.build(self, _anchor, deg_to_rad(18.0))
	# 垂直标尺：0–3 m，每 0.1 m 小刻度、0.5 m 中刻度、1 m 长刻度 + 数字
	_vertical_ruler(_anchor + Vector3(-1.15, 0.0, 0.0), 3.2)
	# 水平标尺：0–2 m 沿 +X
	_horizontal_ruler(_anchor + Vector3(0.0, 0.02, 1.35), 2.0)
	# 原点/轴向
	_axes(Vector3(0.0, _ground_y(0.0, 0.0) + 0.02, 0.0))
	_label("1.50 m 人体参照", _anchor + Vector3(0.0, 1.66, 0.0), C_LABEL)
	_label("1 m 立方", _anchor + Vector3(1.05, 1.10, 0.0), C_CUBE)
	# 场景关键对象尺寸标注 + 房屋层高/门洞/地面标注
	_annotate_house()
	_annotate_world()
	# 一次合批，避免 ~80 个小 Mesh 的 draw call（开发模式仍守现有合批策略）
	Batch.merge_static(self, {"min_instances": 2})

func _ground_y(x: float, z: float) -> float:
	return M.terrain_height(x, z)

func _resolve_anchor() -> Vector3:
	var base := Vector3(M.HOUSE_X, 0.0, M.HOUSE_Z)
	var cottage := _find_named(get_tree().root, "Cottage")
	if cottage is Node3D:
		var c3: Node3D = cottage
		base = c3.global_transform * Vector3(0.0, 0.0, M.HOUSE_D * 0.5 + 1.9)
	var x := base.x
	var z := base.z
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i in range(args.size()):
		var a := String(args[i])
		if a == "--scale-debug-x" and i + 1 < args.size():
			x = float(args[i + 1])
		elif a == "--scale-debug-z" and i + 1 < args.size():
			z = float(args[i + 1])
	return Vector3(x, 0.0, z)

func _find_named(n: Node, wanted: String) -> Node:
	if String(n.name) == wanted:
		return n
	for c in n.get_children():
		var r := _find_named(c, wanted)
		if r != null:
			return r
	return null

# ---------------------------------------------------------------- 参照几何 ----
func _cube_edges(center_bottom: Vector3, size: float) -> void:
	var h := size * 0.5
	var c := center_bottom
	var ex := Vector3(size, 0.018, 0.018)
	var ey := Vector3(0.018, size, 0.018)
	var ez := Vector3(0.018, 0.018, size)
	for sy in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			M.box(self, ex, c + Vector3(0.0, h + sy * h, sz * h), C_CUBE, 0.0, _OPTS)
			M.box(self, ey, c + Vector3(sy * h, h, sz * h), C_CUBE, 0.0, _OPTS)
		for sx in [-1.0, 1.0]:
			M.box(self, ez, c + Vector3(sx * h, h + sy * h, 0.0), C_CUBE, 0.0, _OPTS)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			M.box(self, ey, c + Vector3(sx * h, h, sz * h), C_CUBE, 0.0, _OPTS)

func _vertical_ruler(base: Vector3, total_h: float) -> void:
	M.cyl(self, 0.012, 0.012, total_h, base + Vector3(0.0, total_h * 0.5, 0.0), C_RULER, 0, _OPTS)
	var n := int(round(total_h / 0.1))
	for i in range(0, n + 1):
		var y := float(i) * 0.1
		var is_m := i % 10 == 0
		var is_h := i % 5 == 0
		var w := 0.30 if is_m else (0.20 if is_h else 0.10)
		M.box(self, Vector3(w, 0.012, 0.012), base + Vector3(w * 0.5, y, 0.0), C_RULER, 0.0, _OPTS)
		if is_m:
			_label("%.1f m" % y, base + Vector3(0.42, y, 0.0), C_LABEL)
		elif is_h:
			_label("%.2f" % y, base + Vector3(0.30, y, 0.0), C_LABEL_WARN)

func _horizontal_ruler(origin: Vector3, total_len: float) -> void:
	M.box(self, Vector3(total_len, 0.012, 0.012), origin + Vector3(total_len * 0.5, 0.0, 0.0), C_RULER, 0.0, _OPTS)
	var n := int(round(total_len / 0.1))
	for i in range(0, n + 1):
		var x := float(i) * 0.1
		var is_m := i % 10 == 0
		var is_h := i % 5 == 0
		var hgt := 0.30 if is_m else (0.20 if is_h else 0.10)
		M.box(self, Vector3(0.012, hgt, 0.012), origin + Vector3(x, hgt * 0.5, 0.0), C_RULER, 0.0, _OPTS)
		if is_m:
			_label("%.1f m" % x, origin + Vector3(x, 0.42, 0.0), C_LABEL)

func _axes(origin: Vector3) -> void:
	M.box(self, Vector3(1.0, 0.02, 0.02), origin + Vector3(0.5, 0.0, 0.0), C_AXIS_X, 0.0, _OPTS)
	M.box(self, Vector3(0.02, 1.0, 0.02), origin + Vector3(0.0, 0.5, 0.0), C_AXIS_Y, 0.0, _OPTS)
	M.box(self, Vector3(0.02, 0.02, 1.0), origin + Vector3(0.0, 0.0, 0.5), C_AXIS_Z, 0.0, _OPTS)
	M.sphere(self, 0.035, origin, Color("ffffff"), Vector3.ONE, _OPTS)
	_label("X +1 m", origin + Vector3(1.10, 0.10, 0.0), C_AXIS_X)
	_label("Y +1 m", origin + Vector3(0.0, 1.12, 0.0), C_AXIS_Y)
	_label("Z +1 m", origin + Vector3(0.0, 0.10, 1.10), C_AXIS_Z)
	_label("原点 (0,0,0)", origin + Vector3(0.0, -0.16, 0.0), C_LABEL)

# ---------------------------------------------------------------- 场景标注 ----
func _annotate_house() -> void:
	var cottage := _find_named(get_tree().root, "Cottage")
	if not (cottage is Node3D):
		return
	var c3: Node3D = cottage
	var ctx = c3.get_meta("cottage_ctx", {})
	var fy := 0.55
	var in_top := 4.15
	var attic := 5.70
	var deck := 0.42
	if ctx is Dictionary:
		var cd: Dictionary = ctx
		fy = float(cd.get("fy", fy))
		in_top = float(cd.get("in_top", in_top))
		attic = float(cd.get("attic_floor", attic))
		deck = float(cd.get("deck_top", deck))
	var front := c3.global_transform * Vector3(0.0, 0.0, float(M.HOUSE_D) * 0.5 + 0.75)
	_label("门廊台面 deck_top=%.2f m" % deck, front + Vector3(-2.4, deck + 0.12, 0.0), C_LABEL_WARN)
	_label("1F 地坪 fy=%.2f m" % fy, front + Vector3(2.0, fy + 0.10, 0.0), C_LABEL_WARN)
	_label("一层天花底 in_top=%.2f m" % in_top, front + Vector3(2.0, in_top + 0.10, 0.0), C_LABEL_WARN)
	_label("阁楼楼板 attic_floor=%.2f m" % attic, front + Vector3(2.0, attic + 0.10, 0.0), C_LABEL_WARN)
	var pivot := _find_named(c3, "DoorPivot")
	if pivot is Node3D:
		# 门洞标注口径与 isle_scale_spec / 探针审计一致（Lead m00651）：
		#   T2 在 cottage root 写入 door_clear（净宽/中心净高/拱脚/门扇/气窗），优先读 meta；
		#   meta 缺失时回退到规范常量并标注"规范回退"，绝不用门扇 AABB 高度冒充净高（旧版算成 1.48 的错误来源）。
		var dc: Dictionary = {}
		var meta_dc = c3.get_meta("door_clear", {})
		if meta_dc is Dictionary:
			dc = meta_dc
		var dw: float = float(dc.get("w", Spec.DOOR_CLEAR_W))
		var dh: float = float(dc.get("h", Spec.DOOR_CLEAR_H))
		var leaf_w: float = float(dc.get("leaf_w", 1.00))
		var leaf_h: float = float(dc.get("leaf_h", 1.40))
		var arch_ri: float = float(dc.get("arch_ri", 0.52))
		var arch_foot: float = dh - arch_ri
		if dc.has("spring_y"):
			arch_foot = float(dc.get("spring_y")) - fy
		var suffix := ""
		if dc.is_empty():
			dw = Spec.DOOR_CLEAR_W
			dh = Spec.DOOR_CLEAR_H
			leaf_w = 1.00
			leaf_h = 1.40
			arch_foot = dh - 0.52
			suffix = "（规范回退·缺 door_clear meta）"
		var door_txt := "门洞 净宽 %.2f m / 中心净高 %.2f m（拱脚 %.2f m；门扇 %.2f×%.2f + 气窗）%s" % [dw, dh, arch_foot, leaf_w, leaf_h, suffix]
		_label(door_txt, c3.global_transform * Vector3(0.0, fy + dh + 0.30, float(M.HOUSE_D) * 0.5 + 0.80), C_LABEL)
	var stairs := _find_named(c3, "Staircase")
	if stairs is Node3D:
		var sa := _global_aabb(stairs)
		_label("楼梯 总升≈%.2f m 宽≈%.2f m" % [sa.size.y, sa.size.x], (stairs as Node3D).global_position + Vector3(0.0, 1.0, 0.0), C_LABEL)

func _annotate_world() -> void:
	var specs := [
		["Sailboat", "小船"],
		["Dock", "码头"],
		["Lighthouse", "灯塔"],
		["PathLamp1", "路灯"],
		["BigTree", "大树"],
		["PorchCat", "猫"],
	]
	for s in specs:
		var node := _find_named(get_tree().root, String(s[0]))
		if not (node is Node3D):
			continue
		var a := _global_aabb(node)
		if a.size == Vector3.ZERO:
			continue
		_label("%s %.2f×%.2f×%.2f m（宽×高×深）" % [String(s[1]), a.size.x, a.size.y, a.size.z],
			node.global_position + Vector3(0.0, a.size.y + 0.35, 0.0), C_LABEL)
	var bird := _find_named(get_tree().root, "Bird0")
	if bird is Node3D:
		var ba := _global_aabb(bird)
		_label("海鸥 体长≈%.2f m 翼展≈%.2f m" % [ba.size.z, ba.size.x], bird.global_position + Vector3(0.0, 0.5, 0.0), C_LABEL)

func _global_aabb(root: Node) -> AABB:
	var acc := AABB()
	var first := true
	for n in _walk(root):
		if n is MultiMeshInstance3D:
			continue
		if not (n is MeshInstance3D):
			continue
		var mi: MeshInstance3D = n
		if mi.mesh == null:
			continue
		var nm := String(mi.name)
		if nm.begins_with("Glow") or nm.begins_with("Halo") or nm.begins_with("Blob") or nm.begins_with("Shadow") or nm.begins_with("Bird"):
			continue
		var bb: AABB = mi.mesh.get_aabb()
		var mx := mi.global_transform
		var lo := Vector3(1e20, 1e20, 1e20)
		var hi := Vector3(-1e20, -1e20, -1e20)
		for i in 8:
			var corner: Vector3 = bb.position + Vector3(
				bb.size.x * float(i & 1), bb.size.y * float((i >> 1) & 1), bb.size.z * float((i >> 2) & 1))
			var q: Vector3 = mx * corner
			lo = lo.min(q)
			hi = hi.max(q)
		var a := AABB(lo, hi - lo)
		acc = a if first else acc.merge(a)
		first = false
	return acc

func _walk(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		out.append(c)
		out.append_array(_walk(c))
	return out

# ---------------------------------------------------------------- Label3D ----
func _label(text: String, pos: Vector3, color: Color) -> void:
	var lb := Label3D.new()
	lb.text = text
	lb.font_size = 34
	lb.pixel_size = 0.0042
	lb.modulate = color
	lb.outline_modulate = Color(0.05, 0.07, 0.10, 1.0)
	lb.outline_size = 8
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.no_depth_test = true
	lb.fixed_size = false
	lb.render_priority = 10
	lb.position = pos
	add_child(lb)
	_labels.append(lb)
