extends SceneTree
## P7-V4 只读侦察探针（headless）：导出房屋/家具世界坐标、物理体清单、楼梯 meta、
## 地形采样高度、码头/门廊/路径高差、阁楼净空、猫待机状态、时间域状态。
## 不修改任何产品文件。运行：
##   ENG --headless --path <PROJ> --script res://tools/probe_recon_p7v4.gd
## 输出统一前缀 [RECON]，末尾 [RECON] END。

const M := preload("res://scripts/isle_math.gd")

var _main: Node = null
var _cot: Dictionary = {}
var _wd: Dictionary = {}

func _initialize() -> void:
	var ok: bool = await _bootstrap()
	if ok:
		_report()
	else:
		print("[RECON] FAIL bootstrap")
	print("[RECON] END")
	quit(0 if ok else 1)

func _bootstrap() -> bool:
	var packed: PackedScene = load("res://isle.tscn") as PackedScene
	if packed == null:
		return false
	_main = packed.instantiate()
	get_root().add_child(_main)
	await process_frame
	await process_frame
	var menu = _main.get("_menu")
	if menu != null and menu.has_method("instant_finish"):
		menu.call("instant_finish")
	_main.set("_mode", 1)
	_main.set("_time_source", "sim")
	_main.set("_realtime", false)
	_main.set("_started", true)
	_main.set("_paused", true)
	_main.set("_auto_orbit", false)
	_main.set("_blending", "")
	await process_frame
	await process_frame
	_cot = _main.get("_cottage") as Dictionary
	_wd = _main.get("_world") as Dictionary
	return _cot != null and _cot.size() > 0

func _walk_all(parent: Node, out: Array) -> void:
	var stack: Array = [parent]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		out.append(n)
		for c in n.get_children():
			stack.append(c)

func _p(v: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [v.x, v.y, v.z]

func _slope_deg(x: float, z: float) -> float:
	var e := 0.25
	var dx := (M.terrain_height(x + e, z) - M.terrain_height(x - e, z)) / (2.0 * e)
	var dz := (M.terrain_height(x, z + e) - M.terrain_height(x, z - e)) / (2.0 * e)
	return rad_to_deg(atan(sqrt(dx * dx + dz * dz)))

func _report() -> void:
	var root: Node3D = _cot.get("root")
	var xf: Transform3D = root.global_transform
	var g0 := M.house_ground_y()
	print("[RECON] house_root_origin=", _p(xf.origin), " yaw_rad=%.4f yaw_deg=%.2f house_ground_y=%.4f" % [
		xf.basis.get_euler().y, rad_to_deg(xf.basis.get_euler().y), g0])
	print("[RECON] LEVELS world: plinth_bottom=%.4f deck_top=%.4f interior_floor=%.4f door_head=%.4f attic_floor=%.4f ridge=%.4f" % [
		g0 - 0.75, g0 + 0.42, g0 + 0.55, g0 + 0.55 + 1.94, g0 + 3.17, g0 + 6.20])
	print("[RECON] door_world=", _p(xf * Vector3(0.0, 0.55 + 0.97, 3.10)), " approach=", _p(M.door_approach()))
	var st: Node3D = root.find_child("Staircase", true, false)
	if st != null and st.has_meta("stair_data"):
		var sd: Dictionary = st.get_meta("stair_data")
		var line := ""
		for k in sd.keys():
			if String(k) == "treads":
				continue
			line += "%s=%s " % [String(k), str(sd[k])]
		print("[RECON] stairs_meta ", line)
		var tr: Array = sd.get("treads", [])
		for i in [0, 7, 14, 15]:
			if i < tr.size():
				print("[RECON] tread[", i, "] ", str(tr[i]))
	for mk in ["door_clear", "door_opening"]:
		if root.has_meta(mk):
			print("[RECON] root_meta ", mk, " = ", str(root.get_meta(mk)))
	var ps: Node3D = root.find_child("PorchSteps", true, false)
	if ps != null:
		var d := {}
		for k in ["step_count", "rise", "run", "top_y", "bottom_y", "z_top"]:
			if ps.has_meta(k):
				d[k] = ps.get_meta(k)
		print("[RECON] porch_steps ", str(d))
	# ---- 门廊台阶 / 门槛 / 地形高差 ----
	for i in range(3):
		var ty := 0.42 - 0.14 * float(i + 1)
		var zc := 4.70 + 0.30 * (float(i) + 0.5)
		var wp: Vector3 = xf * Vector3(0.0, ty, zc)
		var th := M.terrain_height(wp.x, wp.z)
		print("[RECON] PORCH step%d local_y=%.3f world_y=%.3f ground=%.3f step_above_ground=%.3f z_local=%.2f" % [
			i + 1, ty, wp.y, th, wp.y - th, zc])
	if ps != null:
		print("[RECON] PORCH bottom_local=%.3f" % float(ps.get_meta("bottom_y", 0.0)))
	# ---- 码头：甲板面(世界 0.72)与地形沿轴高差 ----
	var dock: Dictionary = _wd.get("dock", {})
	var dn = dock.get("node")
	if dn != null:
		var dxf: Transform3D = (dn as Node3D).global_transform
		print("[RECON] DOCK deck_world_y=%.3f dock_origin=%s rot_y=%.4f" % [float(dock.get("deck_world_y", -1.0)), _p(dxf.origin), dxf.basis.get_euler().y])
		for i in range(25):
			var z := 0.5 * float(i)
			var wp: Vector3 = dxf * Vector3(0.0, 0.0, z)
			var th := M.terrain_height(wp.x, wp.z)
			print("[RECON] DOCK z=%.2f world=(%.3f, %.3f) ground_y=%.3f deck_minus_ground=%.3f" % [
				z, wp.x, wp.z, th, 0.72 - th])
	# ---- 主路 door_approach -> dock_start 地形剖面 ----
	var a: Vector3 = M.door_approach()
	var b: Vector3 = M.dock_start()
	for i in range(13):
		var t := float(i) / 12.0
		var q := a.lerp(b, t)
		print("[RECON] ROUTE t=%.2f xz=(%.2f, %.2f) ground=%.3f slope_deg=%.2f" % [
			t, q.x, q.z, M.terrain_height(q.x, q.z), _slope_deg(q.x, q.z)])
	# ---- 基座与地形（四角） ----
	for lxv in [-4.30, 4.30]:
		for lzv in [-3.15, 3.15]:
			var lx := float(lxv)
			var lz := float(lzv)
			var wp: Vector3 = xf * Vector3(lx, 0.0, lz)
			var th := M.terrain_height(wp.x, wp.z)
			print("[RECON] PLINTH corner_local=(%.2f,%.2f) world_y=%.3f ground=%.3f plinth_bottom_local=-0.75 相对地形=%+.3f" % [
				lx, lz, wp.y, th, (th - g0) - (-0.75)])
	# ---- 阁楼净空（屋面下皮公式）与床 ----
	for axv in [0.0, 1.0, 2.0, 2.31, 2.95]:
		var ax := float(axv)
		var roof_under: float = 6.20 - 0.6494 * ax - 0.167
		print("[RECON] ATTIC |x|=%.2f roof_under=%.3f headroom=%.3f" % [ax, roof_under, roof_under - 3.17])
	print("[RECON] ATTIC bed_top=%.3f clearance_at_x2.0=%.3f" % [3.19 + 0.85, (6.20 - 0.6494 * 2.0 - 0.167) - (3.19 + 0.85)])
	# ---- 门扇开启终点（局部，旋转 -1.85 rad 绕 pivot(-0.50,0.55,3.04)） ----
	var piv := Vector3(-0.50, 0.55, 3.04)
	var th_off := -1.85
	var tip := piv + Vector3(cos(th_off), 0.0, -sin(th_off)) * 1.0
	print("[RECON] DOOR open_tip_local=", _p(tip), " world=", _p(xf * tip), " closed_tip_local=", _p(Vector3(0.50, 0.55, 3.04)))
	# ---- 主路折线（world.gd:160-187 节点）坡度 ----
	var poly: Array = [M.door_approach(), Vector3(5.6, 0.0, 8.6), Vector3(9.6, 0.0, 10.2), Vector3(14.2, 0.0, 11.8), M.dock_start()]
	var prev: Vector3 = poly[0]
	for i in range(1, poly.size()):
		var cur: Vector3 = poly[i]
		var worst: float = 0.0
		for k in range(8):
			var t: float = (float(k) + 0.5) / 8.0
			var q: Vector3 = prev.lerp(cur, t)
			worst = maxf(worst, _slope_deg(q.x, q.z))
		print("[RECON] PATH seg%d len=%.2f ground_prev=%.3f ground_cur=%.3f max_slope=%.2f deg" % [
			i, prev.distance_to(cur), M.terrain_height(prev.x, prev.z), M.terrain_height(cur.x, cur.z), worst])
		prev = cur
	# ---- 室内楼板四角与地形（穿透检查） ----
	for lxv in [-3.49, 3.49]:
		for lzv in [-2.79, 2.79]:
			var wp2: Vector3 = xf * Vector3(float(lxv), 0.0, float(lzv))
			var th2 := M.terrain_height(wp2.x, wp2.z)
			print("[RECON] SLAB corner_local=(%.2f,%.2f) ground=%.3f slab_bottom=%.3f terrain_minus_slab=%.3f" % [
				float(lxv), float(lzv), th2, g0 + 0.55 - 0.14, th2 - (g0 + 0.55 - 0.14)])
	# ---- 家具 ----
	var all: Array = []
	_walk_all(_main, all)
	var props: Array = []
	for n in all:
		if n is Node3D and String(n.name).begins_with("Prop_"):
			props.append(n)
	print("[RECON] prop_count=", props.size())
	for p in props:
		var n3 := p as Node3D
		var par := "?"
		if n3.get_parent() != null:
			par = String(n3.get_parent().name)
		print("[RECON] PROP ", String(p.get_meta("prop_kind", "?")), " name=", String(n3.name),
			" parent=", par, " local=", _p(n3.position), " world=", _p(n3.global_position),
			" yaw_deg=%.1f" % rad_to_deg(n3.global_rotation.y), " wall=", str(p.get_meta("prop_wall_mounted", false)))
	# ---- 物理 / 导航清单 ----
	var counts := {"StaticBody3D": 0, "CharacterBody3D": 0, "RigidBody3D": 0, "Area3D": 0,
		"CollisionShape3D": 0, "CollisionPolygon3D": 0, "NavigationRegion3D": 0,
		"NavigationAgent3D": 0, "NavigationObstacle3D": 0, "MeshInstance3D": 0, "MultiMeshInstance3D": 0}
	for n in all:
		if n is StaticBody3D:
			counts["StaticBody3D"] += 1
			var sb := n as StaticBody3D
			print("[RECON] STATICBODY name=", sb.name, " pos=", _p(sb.global_position),
				" layer=", sb.collision_layer, " mask=", sb.collision_mask)
		elif n is CharacterBody3D:
			counts["CharacterBody3D"] += 1
		elif n is RigidBody3D:
			counts["RigidBody3D"] += 1
		elif n is Area3D:
			counts["Area3D"] += 1
		elif n is CollisionShape3D:
			counts["CollisionShape3D"] += 1
			var cs := n as CollisionShape3D
			var sz := String(cs.shape.get_class()) if cs.shape != null else "null"
			if cs.shape is BoxShape3D:
				sz = "Box %s" % str((cs.shape as BoxShape3D).size)
			print("[RECON] COLLISIONSHAPE parent=", cs.get_parent().name, " shape=", sz)
		elif n is CollisionPolygon3D:
			counts["CollisionPolygon3D"] += 1
		elif n is NavigationRegion3D:
			counts["NavigationRegion3D"] += 1
		elif n is NavigationAgent3D:
			counts["NavigationAgent3D"] += 1
		elif n is NavigationObstacle3D:
			counts["NavigationObstacle3D"] += 1
		elif n is MeshInstance3D:
			counts["MeshInstance3D"] += 1
		elif n is MultiMeshInstance3D:
			counts["MultiMeshInstance3D"] += 1
	print("[RECON] node_total=", all.size(), " physics=", str(counts))
	# ---- 地形采样 ----
	var samples := {
		"house_ground": Vector2(M.HOUSE_X, M.HOUSE_Z),
		"door_approach": Vector2(M.door_approach().x, M.door_approach().z),
		"dock_start": Vector2(M.dock_start().x, M.dock_start().z),
		"dock_end": Vector2(M.dock_end().x, M.dock_end().z),
		"garden_center": Vector2(-7.0, -5.8),
		"field_center": Vector2(-3.3, -8.25),
		"lighthouse_base": Vector2(-17.0, 9.0),
		"swing": Vector2(-7.9, 4.2),
		"big_tree": Vector2(-10.9, 4.2),
		"origin": Vector2(0.0, 0.0),
	}
	for k in samples.keys():
		var q: Vector2 = samples[k]
		print("[RECON] TERRAIN ", k, " xz=", str(q), " y=%.4f slope_deg=%.2f" % [
			M.terrain_height(q.x, q.y), _slope_deg(q.x, q.y)])
	var terr = _wd.get("terrain")
	if terr != null:
		print("[RECON] terrain_aabb=", str((terr as MeshInstance3D).get_aabb()), " world=", _p((terr as Node3D).global_position))
	print("[RECON] island_diameter=%.3f dock_end=" % float(_wd.get("island_diameter", -1.0)), _p(M.dock_end()))
	print("[RECON] perches cottage=", (_cot.get("perches", []) as Array).size(), " world=", (_wd.get("perches", []) as Array).size())
	# ---- 猫 ----
	var cat: Dictionary = _cot.get("cat", {})
	var cat_root = cat.get("root")
	if cat_root != null:
		var cr := cat_root as Node3D
		print("[RECON] CAT world=", _p(cr.global_position), " yaw_deg=%.1f" % rad_to_deg(cr.global_rotation.y),
			" meta_no_batch=", str(cr.get_meta("no_batch", false)))
		var drv = cat.get("driver")
		print("[RECON] CAT driver=", (drv != null), " processing=", (drv.is_processing() if drv != null else false))
		var idle = cat.get("idle")
		if idle != null and idle.has_method("debug_state"):
			var ds: Dictionary = idle.debug_state()
			print("[RECON] CAT state breath_period=%.3f breath_scale=%.4f counts=%s" % [
				float(ds.get("breath_period", -1.0)), float(ds.get("breath_scale", -1.0)), str(ds.get("counts", {}))])
	# ---- 时间域 ----
	print("[RECON] TIME sim_seconds=%.3f day_length=%.1f rate=%.4f delta=%.4f source=%s paused=%s tree_paused=%s" % [
		float(_main.get("_sim_seconds")), float(_main.get("_day_length")), float(_main.get("_sim_rate")),
		float(_main.get("_sim_delta")), str(_main.get("_time_source")), str(_main.get("_paused")), str(paused)])
	var lc = _cot.get("light_sources")
	print("[RECON] light_sources_cottage=", (lc as Array).size() if lc != null else -1,
		" light_sources_world=", (_wd.get("light_sources", []) as Array).size())
