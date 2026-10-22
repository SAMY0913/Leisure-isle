extends SceneTree

# P8.1-03 白化/室内豁免 静态+运行期断言探针（headless，无窗口、无截图）。
# 校验对象：
#   1) g_house/g_house2/g_roof 已由 main 按 Cottage 变换写入，数值与几何常量一致；
#   2) GLSL indoor_mask 的 GDScript 镜像样本（一层室内/阁楼/内外墙面/屋面外表面/门廊）；
#   3) g_winter 季节曲线：smoothstep(0.30,0.90,winter_weight)，与 P8.1 计划书 6.1 一致；
#   4) 材质接收系数 winter_recv 按类别落位（地形/草/树冠/灌木/屋顶/自发光/动态对象/花）。
# 任一断言失败 → 退出码 1。

var _fails: Array[String] = []
var _checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _ok(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("[P81WPROBE] OK   ", msg)
	else:
		_fails.append(msg)
		print("[P81WPROBE] FAIL ", msg)

func _near(a: float, b: float, eps: float = 0.0015) -> bool:
	return absf(a - b) <= eps

## 与 shaders/toon.gdshader::indoor_mask 逐行同构（同一组 uniform 常量、同一判定顺序）。
func _indoor_mask(wp: Vector3, gh: Vector4, gh2: Vector4, gr: Vector4) -> float:
	var c := gh.w
	var s := gh2.x
	var dx := wp.x - gh.x
	var dz := wp.z - gh.z
	var lx := c * dx - s * dz
	var lz := s * dx + c * dz
	var dy := wp.y - gh.y
	if absf(lx) > gh2.y or absf(lz) > gh2.z:
		return 0.0
	if dy < gh2.w:
		return 0.0
	if dy <= gr.w:
		return 1.0
	var roof_under := gr.x - gr.y * absf(lx) - gr.z
	if dy <= roof_under:
		return 1.0
	return 0.0

func _shader_path(m: ShaderMaterial) -> String:
	if m == null or m.shader == null:
		return ""
	return String((m.shader as Shader).resource_path)

## 读 winter_recv；未设置返回 (-1,-1,-1,-1) 便于断言失败可读。
func _recv(m: ShaderMaterial) -> Vector4:
	var v = m.get_shader_parameter("winter_recv")
	if v == null:
		return Vector4(-1.0, -1.0, -1.0, -1.0)
	return Vector4(float(v.x), float(v.y), float(v.z), float(v.w))

func _self_lit(m: ShaderMaterial) -> float:
	var v = m.get_shader_parameter("self_lit")
	if v == null:
		return 0.0
	return float(v)

## 收集子树内全部 ShaderMaterial（override + mesh surface + multimesh surface），与 main 标记口径一致。
func _collect(root: Node) -> Array:
	var out: Array = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is GeometryInstance3D):
			continue
		var gi := n as GeometryInstance3D
		var rel := String(root.get_path_to(n))
		var mo := gi.material_override
		if mo is ShaderMaterial:
			out.append({"node": n, "rel": rel, "mat": mo})
		if gi is MeshInstance3D:
			var mi := gi as MeshInstance3D
			if mi.mesh != null:
				for si in range(mi.mesh.get_surface_count()):
					var sm := mi.get_surface_override_material(si)
					if not (sm is ShaderMaterial):
						sm = mi.mesh.surface_get_material(si)
					if sm is ShaderMaterial:
						out.append({"node": n, "rel": rel, "mat": sm})
		elif gi is MultiMeshInstance3D:
			var mmi := gi as MultiMeshInstance3D
			if mmi.multimesh != null and mmi.multimesh.mesh != null:
				for si in range(mmi.multimesh.mesh.get_surface_count()):
					var sm2 := mmi.multimesh.mesh.surface_get_material(si)
					if sm2 is ShaderMaterial:
						out.append({"node": n, "rel": rel, "mat": sm2})
	return out

func _run() -> void:
	var packed: PackedScene = load("res://isle.tscn")
	_ok(packed != null, "isle.tscn 可加载")
	if packed == null:
		quit(1)
		return
	var isle = packed.instantiate()
	root.add_child(isle)
	await process_frame
	await process_frame
	await process_frame
	_ok(isle.has_method("_setup_winter_house_uniforms"), "main.gd 已包含 P8.1-03 白化函数")
	var world = isle._world
	var cottage = isle._cottage
	_ok(not world.is_empty() and not cottage.is_empty(), "World/Cottage 已构建")
	if world.is_empty() or cottage.is_empty():
		quit(1)
		return
	var house_root := cottage.get("root", null) as Node3D
	_ok(house_root != null, "Cottage root 存在")

	# ---------- 1) 房屋体积 uniform ----------
	var o := house_root.global_transform.origin
	var yaw := house_root.global_rotation.y
	# headless 的 dummy RenderingServer 不实现 global_shader_parameter_get 回读（返回 null）；
	# 窗口运行由 --p81white 的 [P81WHITE] globals 日志回读，这里在无回读时按 main 同一公式重建期望值，
	# 从而把「几何常量/世界原点/朝向」与「indoor_mask 判定语义」继续钉死。
	var gh = RenderingServer.global_shader_parameter_get("g_house")
	var gh2 = RenderingServer.global_shader_parameter_get("g_house2")
	var gr = RenderingServer.global_shader_parameter_get("g_roof")
	var have_globals: bool = gh != null and gh2 != null and gr != null
	print("[P81WPROBE] global readback available=", have_globals)
	var g_house := Vector4(o.x, o.y, o.z, cos(yaw))
	var g_house2 := Vector4(sin(yaw), 3.55, 2.95, 0.50)
	var g_roof := Vector4(6.20, 2.47 / 3.8, 0.10, 2.97)
	if have_globals:
		g_house = Vector4(float(gh.x), float(gh.y), float(gh.z), float(gh.w))
		g_house2 = Vector4(float(gh2.x), float(gh2.y), float(gh2.z), float(gh2.w))
		g_roof = Vector4(float(gr.x), float(gr.y), float(gr.z), float(gr.w))
	if have_globals:
		_ok(_near(g_house.x, o.x) and _near(g_house.y, o.y) and _near(g_house.z, o.z), "g_house.xyz = Cottage 世界原点（回读）")
		_ok(_near(g_house.w, cos(yaw)), "g_house.w = cos(yaw)（回读）")
		_ok(_near(g_house2.x, sin(yaw)), "g_house2.x = sin(yaw)（回读）")
		_ok(_near(g_house2.y, 3.55), "g_house2.y(half_x) = 3.55（回读）")
		_ok(_near(g_house2.z, 2.95), "g_house2.z(half_z) = 2.95（回读）")
		_ok(_near(g_house2.w, 0.50), "g_house2.w(floor_local) = 0.50（回读）")
		_ok(_near(g_roof.x, 6.20), "g_roof.x(ridge_y) = 6.20（回读）")
		_ok(_near(g_roof.y, 2.47 / 3.8), "g_roof.y(tan_pitch) = 0.65（回读）")
		_ok(_near(g_roof.z, 0.10), "g_roof.z(under_margin) = 0.10（回读）")
		_ok(_near(g_roof.w, 2.97), "g_roof.w(first_floor_top) = 2.97（回读）")
	else:
		_ok(_near(g_house2.y, 3.55) and _near(g_house2.z, 2.95) and _near(g_house2.w, 0.50), "g_house2 常量 = (sin,3.55,2.95,0.50)（无回读，按 main 公式重建）")
		_ok(_near(g_roof.x, 6.20) and _near(g_roof.y, 0.65) and _near(g_roof.z, 0.10) and _near(g_roof.w, 2.97), "g_roof 常量 = (6.20,0.65,0.10,2.97)（无回读，按 main 公式重建）")

	# ---------- 2) indoor_mask 样本（世界点 = Cottage 世界变换 * 房屋局部点） ----------
	var xf := house_root.global_transform
	var winter_w := 1.0
	var ip: Vector3 = cottage.get("interior_pos", xf * Vector3(0.35, 1.75, 0.0))
	var attic_lamp: Vector3 = cottage.get("attic_lamp_world", xf * Vector3(0.0, 6.0, 0.0))
	var samples: Array = [
		["一层室内中心 interior_pos", ip, 1.0],
		["阁楼室内（吊灯位置）", attic_lamp, 1.0],
		["一层前内墙面 (0,1.5,2.79)", xf * Vector3(0.0, 1.5, 2.79), 1.0],
		["前墙厚度中 (0,1.5,3.02)", xf * Vector3(0.0, 1.5, 3.02), 0.0],
		["前墙外 (0,1.5,3.30)", xf * Vector3(0.0, 1.5, 3.30), 0.0],
		["一层侧内墙面 (3.45,1.5,0)", xf * Vector3(3.45, 1.5, 0.0), 1.0],
		["侧墙厚度中 (3.65,1.5,0)", xf * Vector3(3.65, 1.5, 0.0), 0.0],
		["地板以下 (0,0.40,0)", xf * Vector3(0.0, 0.40, 0.0), 0.0],
		["屋面外表面上方 (2.0,5.05,0)", xf * Vector3(2.0, 5.05, 0.0), 0.0],
		["阁楼室内屋面下 (2.0,4.60,0)", xf * Vector3(2.0, 4.60, 0.0), 1.0],
		["门廊室外 (0,1.0,4.20)", xf * Vector3(0.0, 1.0, 4.20), 0.0],
		["岛面室外 (5.0,0.30,0)", xf * Vector3(5.0, 0.30, 0.0), 0.0],
	]
	for s in samples:
		var got := _indoor_mask(s[1], g_house, g_house2, g_roof)
		_ok(_near(got, float(s[2]), 0.0001), "indoor_mask %s -> %.0f" % [String(s[0]), got])

	# ---------- 3) g_winter 季节曲线（_season_weights[3] = winter_weight） ----------
	var saved_weights: Array = isle._season_weights.duplicate(true)
	var cases: Array = [
		[0.0, 0.0],
		[0.30, 0.0],
		[0.514, 0.2905],   # P8.1 计划 6.1：2026-12-01
		[0.830, 0.9623],   # 2026-12-06
		[1.0, 1.0],
	]
	for c in cases:
		isle._season_weights = [0.0, 0.0, 0.0, float(c[0])]
		isle._set_winter_season_uniforms()
		var wv := float(isle._p81_winter_whiteness())
		_ok(_near(wv, float(c[1]), 0.004), "_p81_winter_whiteness(w=%.3f) = %.4f（期望 %.4f）" % [float(c[0]), wv, float(c[1])])
		var gw = RenderingServer.global_shader_parameter_get("g_winter")
		if gw != null:
			_ok(_near(float(gw.x), wv, 0.004), "g_winter.x 回读 = whiteness（w=%.3f）" % float(c[0]))
			_ok(_near(float(gw.y), wv * 0.65, 0.004), "g_winter.y 回读 = whiteness*0.65（w=%.3f）" % float(c[0]))
	isle._season_weights = saved_weights
	isle._set_winter_season_uniforms()

	# ---------- 4) 材质接收系数 winter_recv ----------
	# main.gd:594-600：holder=New Node3D 名 "World"，IsleWorld.build(holder) 的 root 与 IsleCottage.build(holder)
	# 是 holder 的两个兄弟子树；屋顶/室内材质在 Cottage 下，必须从 main 的 "World" holder 往下遍历。
	var holder: Node = isle.get_node_or_null("World")
	_ok(holder != null, "main 的 World holder 存在")
	var mats: Array = _collect(holder)
	print("[P81WPROBE] materials=", mats.size())
	var n_toon := 0
	var n_grass := 0
	var n_selflit := 0
	var bad_selflit := 0
	var n_dyn := 0
	var bad_dyn := 0
	var n_flower := 0
	var bad_flower := 0
	var terrain_ok := false
	var grass_ok := 0
	var canopy_ok := 0
	var bush_ok := 0
	var roof_ok := 0
	for e in mats:
		var m = e["mat"] as ShaderMaterial
		var rel: String = e["rel"]
		var node = e["node"] as Node
		var nm := String(node.name)
		var sp := _shader_path(m)
		if sp.ends_with("grass.gdshader"):
			n_grass += 1
			var rg := _recv(m)
			if _near(rg.x, 0.90) and _near(rg.w, 0.85):
				grass_ok += 1
			continue
		if not sp.ends_with("toon.gdshader"):
			continue
		n_toon += 1
		var r := _recv(m)
		if nm == "Terrain":
			terrain_ok = _near(r.x, 0.90) and _near(r.z, 1.00) and _near(r.y, 0.55)
		if nm == "Canopy" or nm == "LeafCards" or nm == "BgTreeCanopy":
			if _near(r.w, 0.85):
				canopy_ok += 1
		if nm == "Bushes":
			if _near(r.w, 0.85):
				bush_ok += 1
		if nm.begins_with("Roof"):
			if r.x >= 0.85:
				roof_ok += 1
		if _self_lit(m) > 0.5:
			n_selflit += 1
			if r != Vector4.ZERO:
				bad_selflit += 1
		if rel.contains("Sailboat") or nm == "Sailboat" or rel.contains("Islander") or nm == "Islander" or rel.contains("PorchCat") or nm == "PorchCat":
			n_dyn += 1
			if r != Vector4.ZERO:
				bad_dyn += 1
		if nm.begins_with("Flower") or nm.begins_with("WinterBloom"):
			n_flower += 1
			if r != Vector4.ZERO:
				bad_flower += 1
	# ---------- 4b) 室外覆盖清单抽查：码头木构 / 灯塔（按 holder 相对路径；world 子树不合批，cottage 才合批） ----------
	# 注意：码头/灯塔子节点大量是未命名 MeshInstance3D（@MeshInstance3D@NN），只能按 rel 路径判定；
	# Sailboat/Deck/DeckPlank* 是船甲板，属于动态对象（winter_recv=0），不得误判进码头统计。
	var n_dock := 0
	var dock_ok := 0
	var n_lh := 0
	var lh_ok := 0
	var sample_default: Array[String] = []
	for e in mats:
		var rel2 := String(e["rel"])
		var m2 := e["mat"] as ShaderMaterial
		if not _shader_path(m2).ends_with("toon.gdshader"):
			continue
		if _self_lit(m2) > 0.5:
			continue
		if rel2.begins_with("Island/Dock/"):
			n_dock += 1
			var rv := _recv(m2)
			if rv.x >= 0.70:
				dock_ok += 1
			elif sample_default.size() < 12:
				sample_default.append(rel2 + " -> " + str(rv))
		elif rel2.begins_with("Island/Lighthouse/"):
			n_lh += 1
			var rv2 := _recv(m2)
			if rv2.x >= 0.70:
				lh_ok += 1
			elif sample_default.size() < 22:
				sample_default.append(rel2 + " -> " + str(rv2))
	print("[P81WPROBE] dock mats=", n_dock, " ok=", dock_ok, " lighthouse mats=", n_lh, " ok=", lh_ok)
	for s in sample_default:
		print("[P81WPROBE]   non-white sample: ", s)
	_ok(n_dock > 0 and dock_ok == n_dock, "码头木构/石阶材质 %d 个 winter_recv.x>=0.70（雪覆盖）" % n_dock)
	_ok(n_lh > 0 and lh_ok == n_lh, "灯塔本体/石阶材质 %d 个 winter_recv.x>=0.70" % n_lh)
	_ok(terrain_ok, "Terrain winter_recv=(0.90,0.55,1.00,0.0)")
	_ok(n_grass > 0 and grass_ok == n_grass, "草材质 %d 个全部 winter_recv=(0.90,0,0.55,0.85)" % n_grass)
	_ok(canopy_ok > 0, "树冠/叶卡/背景冠材质 %d 个 winter_recv.w=0.85" % canopy_ok)
	_ok(bush_ok > 0, "灌木材质 %d 个 winter_recv.w=0.85" % bush_ok)
	_ok(roof_ok > 0, "屋顶瓦/脊瓦/椽尾材质 %d 个 winter_recv.x>=0.85" % roof_ok)
	_ok(n_selflit >= 5 and bad_selflit == 0, "自发光材质 %d 个全部 winter_recv=0（灯罩/炉火/窗暖光不刷白）" % n_selflit)
	_ok(n_dyn > 0 and bad_dyn == 0, "动态对象/动物材质 %d 个全部 winter_recv=0" % n_dyn)
	_ok(n_flower > 0 and bad_flower == 0, "花/冬季红花材质 %d 个全部 winter_recv=0" % n_flower)
	print("[P81WPROBE] toon=", n_toon, " grass=", n_grass, " selflit=", n_selflit,
		" dyn=", n_dyn, " flower=", n_flower, " canopy_ok=", canopy_ok, " roof_ok=", roof_ok)
	# 冬季真实激活时 shader 不会把室内片元刷白：由上面的 indoor_mask 样本 + 材质系数共同保证。
	print("[P81WPROBE] summary checks=", _checks, " fails=", _fails.size())
	if _fails.is_empty():
		print("[P81WPROBE] PASS")
		quit(0)
	else:
		print("[P81WPROBE] FAILED: ", str(_fails))
		quit(1)