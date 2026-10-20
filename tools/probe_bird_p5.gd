extends SceneTree
## P5 海鸥模型与朝向验收探针（不加载 isle.tscn、不渲染）：
##   <godot_console.exe> --headless --path D:/休闲小岛幻境/游戏工程 --script res://tools/probe_bird_p5.gd
## 断言：
##   [STRUCT] 模型结构（躯干/头/喙/眼/腿/尾 + 双翼内外段 + 每翼 6 根初级飞羽）、共享材质/网格
##   [SPAN]   展开翼展 1.05~1.25m
##   [ORIENT] 真实速度驱动朝向：dot(forward, velocity_norm) > 0.9（无倒飞）、pitch/roll 限幅
##   [POSE]   振翅/滑翔/降落/停栖收翼姿态数值
##   [PERCH]  facing 向量 → 朝向一致、夜间全部栖息
## 退出码：0 = 全部断言通过。

const Fx := preload("res://scripts/fx.gd")
const DT := 1.0 / 60.0
const DAY_SECS := 20.0
const NIGHT_SECS := 25.0
const PITCH_MAX := 0.610865
const ROLL_MAX := 0.55

var _pass := 0
var _fail := 0

func _initialize() -> void:
	print("=== P5 BIRD PROBE START ===")
	await process_frame
	var flock = Fx.BirdFlock.new()
	root.add_child(flock)
	flock.setup(_make_perches())
	await process_frame
	_probe_structure(flock)
	_probe_span(flock)
	_probe_orientation(flock)
	_probe_perch(flock)
	_probe_alloc(flock)
	flock.free()
	print("=== P5 BIRD PROBE RESULT: ", "PASS" if _fail == 0 else "FAIL", " pass=", _pass, " fail=", _fail, " ===")
	quit(0 if _fail == 0 else 1)

func _check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("  [OK] ", msg)
	else:
		_fail += 1
		print("  [FAIL] ", msg)

func _fmt_counts(st: Dictionary) -> String:
	return "birds=%d fly=%d takeoff=%d landing=%d perch=%d airborne=%d waiting=%d night=%s slots=%d used=%d conflicts=%d min_gap=%.2f takeoffs=%d landings=%d night_takeoffs=%d" % [
		int(st["birds"]), int(st["flying"]), int(st["takeoff"]), int(st["landing"]),
		int(st["perched"]), int(st["airborne"]), int(st["waiting"]), str(st["night"]),
		int(st["perch_slots"]), int(st["perch_used"]), int(st["perch_conflicts"]),
		float(st["air_min_dist"]), int(st["takeoffs"]), int(st["landings"]), int(st["takeoffs_night"]),
	]

## 带已知 facing 向量的栖枝（覆盖树/屋脊/码头/灯桩朝向，外加 1 个 float 旧格式）
func _make_perches() -> Array:
	return [
		{"id": "p_north", "pos": Vector3(0.0, 9.0, -8.0), "facing": Vector3(0.0, 0.0, -1.0), "radius": 1.4, "kind": "ridge"},
		{"id": "p_south", "pos": Vector3(0.0, 9.0, 8.0), "facing": Vector3(0.0, 0.0, 1.0), "radius": 1.4, "kind": "ridge"},
		{"id": "p_east", "pos": Vector3(8.0, 6.0, 0.0), "facing": Vector3(1.0, 0.0, 0.0), "radius": 1.4, "kind": "roof"},
		{"id": "p_west", "pos": Vector3(-8.0, 6.0, 0.0), "facing": Vector3(-1.0, 0.0, 0.0), "radius": 1.4, "kind": "roof"},
		{"id": "p_diag1", "pos": Vector3(6.0, 4.0, 6.0), "facing": Vector3(0.6, 0.0, 0.8), "radius": 1.4, "kind": "dock"},
		{"id": "p_diag2", "pos": Vector3(-6.0, 4.0, -6.0), "facing": Vector3(-0.6, 0.0, -0.8), "radius": 1.4, "kind": "dock"},
		{"id": "p_roof", "pos": Vector3(3.0, 5.0, -3.0), "facing": Vector3(-0.3, 0.0, 0.9), "radius": 1.4, "kind": "eave"},
		{"id": "p_legacy_float", "pos": Vector3(-3.0, 3.0, 5.0), "facing": 0.0, "radius": 1.4, "kind": "porch"},
		Vector3(10.0, 3.0, -5.0),
		Vector3(-10.0, 3.0, 5.0),
	]

func _birds(flock) -> Array:
	return flock.get("_birds")

func _find(node: Node, nm: String) -> Node:
	if String(node.name) == nm:
		return node
	for c in node.get_children():
		var r: Node = _find(c, nm)
		if r != null:
			return r
	return null

## 网格 AABB 变换到 bird 局部空间并合并
func _local_aabb(mi: MeshInstance3D, bird: Node3D) -> AABB:
	var xf: Transform3D = bird.global_transform.affine_inverse() * mi.global_transform
	var ab: AABB = mi.get_aabb()
	var mn := Vector3(1.0e9, 1.0e9, 1.0e9)
	var mx := Vector3(-1.0e9, -1.0e9, -1.0e9)
	for i in range(8):
		var c: Vector3 = ab.position + Vector3(
			ab.size.x if (i & 1) != 0 else 0.0,
			ab.size.y if (i & 2) != 0 else 0.0,
			ab.size.z if (i & 4) != 0 else 0.0)
		var p: Vector3 = xf * c
		mn = mn.min(p)
		mx = mx.max(p)
	return AABB(mn, mx - mn)

## 两个 AABB 的最近距离（相交时为 0），用于“零件飘走”检查
func _aabb_gap(a: AABB, b: AABB) -> float:
	var dx: float = maxf(0.0, maxf(a.position.x - (b.position.x + b.size.x), b.position.x - (a.position.x + a.size.x)))
	var dy: float = maxf(0.0, maxf(a.position.y - (b.position.y + b.size.y), b.position.y - (a.position.y + a.size.y)))
	var dz: float = maxf(0.0, maxf(a.position.z - (b.position.z + b.size.z), b.position.z - (a.position.z + a.size.z)))
	return sqrt(dx * dx + dy * dy + dz * dz)

func _collect_meshes(node: Node, out: Array) -> void:
	for c in node.get_children():
		if c is MeshInstance3D:
			out.append(c)
		_collect_meshes(c, out)

func _unwrap_mats(m: Material) -> Array:
	var out: Array = []
	if m == null:
		return out
	out.append(m)
	if m is ShaderMaterial:
		var sh: ShaderMaterial = m
		if sh.next_pass != null:
			out.append(sh.next_pass)
	return out

# ============================================================
# 1) 模型结构 / 共享材质共享网格
# ============================================================
func _probe_structure(flock) -> void:
	print("--- STRUCT ---")
	var birds: Array = _birds(flock)
	_check(birds.size() == Fx.BIRD_COUNT, "鸟数 = %d" % Fx.BIRD_COUNT)
	var need := ["body", "head", "beak", "tail", "legs", "eyes", "wing_l", "wing_r", "elbow_l", "elbow_r", "wing_l_inner", "wing_l_outer", "wing_r_inner", "wing_r_outer"]
	var missing: Array = []
	var meshes_per_bird := 0
	for b_v in birds:
		var b: Dictionary = b_v
		var node: Node3D = b["node"]
		for nm in need:
			if _find(node, nm) == null:
				missing.append("%s/%s" % [node.name, nm])
	var b0: Node3D = (birds[0] as Dictionary)["node"]
	var m0: Array = []
	_collect_meshes(b0, m0)
	meshes_per_bird = m0.size()
	print("[STRUCT] bird0 mesh_instances=", meshes_per_bird, " total_nodes=", _count_nodes(b0))
	_check(missing.is_empty(), "结构节点齐全（缺 %d：%s）" % [missing.size(), str(missing.slice(0, 6))])
	_check(meshes_per_bird >= 9, "每只鸟 >= 9 个网格（实际 %d）" % meshes_per_bird)
	var inner_ok := true
	var outer_ok := true
	var prim := 0
	var prim_ok := true
	for b_v2 in birds:
		var node2: Node3D = (b_v2 as Dictionary)["node"]
		for side in ["l", "r"]:
			var inner: Node = _find(node2, "wing_%s_inner" % side)
			var outer: Node = _find(node2, "wing_%s_outer" % side)
			if not (inner is MeshInstance3D):
				inner_ok = false
			if not (outer is MeshInstance3D):
				outer_ok = false
			elif outer.has_meta("primary_count"):
				prim = int(outer.get_meta("primary_count"))
				if prim < 5 or prim > 7:
					prim_ok = false
			else:
				prim_ok = false
	_check(inner_ok, "双翼内段 wing_{l,r}_inner 存在")
	_check(outer_ok, "双翼外段 wing_{l,r}_outer 存在")
	_check(prim_ok and prim > 0, "每翼初级飞羽数 meta.primary_count = %d（要求 5~7）" % prim)
	# 内外段顶点数：外段应含飞羽，顶点数更多
	if inner_ok and outer_ok:
		var inner_m: Mesh = (_find(b0, "wing_l_inner") as MeshInstance3D).mesh
		var outer_m: Mesh = (_find(b0, "wing_l_outer") as MeshInstance3D).mesh
		var sv := [inner_m.get_surface_count(), outer_m.get_surface_count()]
		var av := [inner_m.get_aabb().size, outer_m.get_aabb().size]
		print("[STRUCT] inner surfaces=", sv[0], " aabb=", av[0], " | outer surfaces=", sv[1], " aabb=", av[1])
		_check(av[1].x > av[0].x, "外翼段沿展向比内翼段更长（%.3f > %.3f）" % [av[1].x, av[0].x])
	# 零件附着检查（Lead 要求）：任何翼/羽/尾/肢网格的 AABB 必须与躯干 AABB 相交或距离 < 0.35m，
	# 防止再出现“头顶/背部悬浮一块薄板”的父子变换/局部坐标错误。
	var attach_ok := true
	var attach_worst := 0.0
	var attach_worst_name := ""
	var tail_y_ok := true
	var tail_back_ok := true
	for b_v4 in birds:
		var node4: Node3D = (b_v4 as Dictionary)["node"]
		var body_mi: MeshInstance3D = _find(node4, "body") as MeshInstance3D
		var body_ab: AABB = _local_aabb(body_mi, node4)
		var body_center: Vector3 = body_ab.get_center()
		var parts: Array = []
		_collect_meshes(node4, parts)
		for mi_v2 in parts:
			var mi2: MeshInstance3D = mi_v2
			if mi2 == body_mi:
				continue
			var pab: AABB = _local_aabb(mi2, node4)
			var gap: float = _aabb_gap(body_ab, pab)
			if gap > attach_worst:
				attach_worst = gap
				attach_worst_name = "%s/%s" % [node4.name, mi2.name]
			if not body_ab.grow(0.35).intersects(pab):
				attach_ok = false
			if String(mi2.name) == "tail":
				var tc: Vector3 = pab.get_center()
				if absf(tc.y - body_center.y) > 0.15:
					tail_y_ok = false
				if tc.z > body_center.z + 0.05:
					tail_back_ok = false
	print("[STRUCT] attach: worst_gap=%.3fm (%s) tail_y_ok=%s tail_back_ok=%s" % [attach_worst, attach_worst_name, str(tail_y_ok), str(tail_back_ok)])
	_check(attach_worst < 0.35, "所有翼/羽/尾/肢网格贴着躯干（最大间隙 %.3fm < 0.35m，worst=%s）" % [attach_worst, attach_worst_name])
	_check(tail_y_ok, "尾羽高度与躯干重叠（不再悬浮在头顶/背部上方）")
	_check(tail_back_ok, "尾羽位于躯干后方")
	# 共享材质 / 网格
	var uniq_mats: Dictionary = {}
	var uniq_meshes: Dictionary = {}
	var meshes_total := 0
	for b_v3 in birds:
		var node3: Node3D = (b_v3 as Dictionary)["node"]
		var lst: Array = []
		_collect_meshes(node3, lst)
		for mi_v in lst:
			var mi: MeshInstance3D = mi_v
			meshes_total += 1
			if mi.material_override != null:
				uniq_mats[mi.material_override.get_instance_id()] = true
			if mi.mesh != null:
				uniq_meshes[mi.mesh.get_instance_id()] = true
	print("[STRUCT] mesh_instances_total=", meshes_total, " unique_materials=", uniq_mats.size(), " unique_meshes=", uniq_meshes.size())
	_check(uniq_mats.size() <= 3, "共享材质数 <= 3（实际 %d）" % uniq_mats.size())
	_check(uniq_meshes.size() <= 12, "共享网格数 <= 12（实际 %d）" % uniq_meshes.size())
	var vc_found := false
	for mid in uniq_mats.keys():
		var m := instance_from_id(mid)
		var arr: Array = _unwrap_mats(m)
		for mm in arr:
			if mm is ShaderMaterial and float((mm as ShaderMaterial).get_shader_parameter("use_vertex_color")) > 0.5:
				vc_found = true
	_check(vc_found, "存在 vertex_color 材质（多色合并网格）")

func _count_nodes(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count_nodes(ch)
	return c

# ============================================================
# 2) 展开翼展
# ============================================================
func _probe_span(flock) -> void:
	print("--- SPAN ---")
	var b: Dictionary = _birds(flock)[0]
	var bird: Node3D = b["node"]
	var wing_nodes: Array = []
	for nm in ["wing_l", "wing_r", "elbow_l", "elbow_r"]:
		var n := _find(bird, nm)
		if n is Node3D:
			wing_nodes.append({"node": n, "rot": (n as Node3D).rotation})
	for item in wing_nodes:
		(item["node"] as Node3D).rotation = Vector3.ZERO
	var meshes: Array = []
	_collect_meshes(bird, meshes)
	var box := AABB()
	var first := true
	for mi_v in meshes:
		var mi: MeshInstance3D = mi_v
		var ab: AABB = _local_aabb(mi, bird)
		if first:
			box = ab
			first = false
		else:
			box = box.merge(ab)
	for item2 in wing_nodes:
		(item2["node"] as Node3D).rotation = item2["rot"]
	print("[SPAN] local aabb size=", box.size, " span_x=%.3f" % box.size.x, " body_len_z=%.3f" % box.size.z)
	_check(box.size.x >= 1.05 and box.size.x <= 1.25, "展开翼展 %.3f m 在 1.05~1.25 范围" % box.size.x)
	_check(box.size.z >= 0.5 and box.size.z <= 0.95, "体长（喙到尾尖）%.3f m 在 0.5~0.95 范围" % box.size.z)

# ============================================================
# 3) 朝向：真实速度驱动、无倒飞、pitch/roll 限幅、姿态
# ============================================================
func _probe_orientation(flock) -> void:
	print("--- ORIENT ---")
	var birds: Array = _birds(flock)
	var prev: Array = []
	var prev_state: Array = []
	for b_v in birds:
		prev.append(((b_v as Dictionary)["node"] as Node3D).global_position)
		prev_state.append(-1)
	var frames := int(DAY_SECS / DT)
	var samples := 0
	var viol := 0
	var min_dot := 9.0
	var min_dot_h := 9.0
	var pitch_lo := 9.0
	var pitch_hi := -9.0
	var roll_lo := 9.0
	var roll_hi := -9.0
	var max_speed := 0.0
	var glide_frames := 0
	var flap_frames := 0
	var landing_frames := 0
	var landing_flare := 9.0
	var wing_lo := 9.0
	var wing_hi := -9.0
	var elbow_lo := 9.0
	var elbow_hi := -9.0
	# 内外翼相位差证据：记录“翼根峰值帧的肘部值”和“肘部峰值帧的翼根值”
	var wing_peak := -9.0
	var elbow_at_wing_peak := 9.0
	var elbow_peak := -9.0
	var wing_at_elbow_peak := 9.0
	var flight_leg_tuck := -9.0
	var seen_states: Dictionary = {}
	var bad_nan := 0
	var last_takeoffs := 0
	var last_landings := 0
	for i in range(frames):
		flock.update_birds(DT, 22.0)
		var st_c: Dictionary = flock.get_state_counts()
		if int(st_c["takeoffs"]) > last_takeoffs:
			last_takeoffs = int(st_c["takeoffs"])
		if int(st_c["landings"]) > last_landings:
			last_landings = int(st_c["landings"])
		for bi in range(birds.size()):
			var b: Dictionary = birds[bi]
			var node: Node3D = b["node"]
			var st: int = int(b["state"])
			seen_states[st] = true
			var pos: Vector3 = node.global_position
			if pos.is_finite() == false:
				bad_nan += 1
			var vel: Vector3 = (pos - (prev[bi] as Vector3)) / DT
			var speed: float = vel.length()
			max_speed = maxf(max_speed, speed)
			var rot: Vector3 = node.rotation
			pitch_lo = minf(pitch_lo, rot.x)
			pitch_hi = maxf(pitch_hi, rot.x)
			roll_lo = minf(roll_lo, rot.z)
			roll_hi = maxf(roll_hi, rot.z)
			var wl: Node3D = _find(node, "wing_l")
			var el: Node3D = _find(node, "elbow_l")
			var legs: Node3D = _find(node, "legs")
			if st == 0:
				flap_frames += 1
				if wl != null:
					wing_lo = minf(wing_lo, wl.rotation.z)
					wing_hi = maxf(wing_hi, wl.rotation.z)
				if el != null:
					elbow_lo = minf(elbow_lo, el.rotation.z)
					elbow_hi = maxf(elbow_hi, el.rotation.z)
				if wl != null and el != null:
					if wl.rotation.z > wing_peak:
						wing_peak = wl.rotation.z
						elbow_at_wing_peak = el.rotation.z
					if el.rotation.z > elbow_peak:
						elbow_peak = el.rotation.z
						wing_at_elbow_peak = wl.rotation.z
				if legs != null:
					flight_leg_tuck = maxf(flight_leg_tuck, legs.rotation.x)
				if float(b.get("flap_env", 1.0)) < 0.25:
					glide_frames += 1
				if speed > 0.2 and speed < 30.0 and int(prev_state[bi]) == 0:
					var fwd: Vector3 = node.global_basis.z.normalized()
					var vn: Vector3 = vel.normalized()
					var d: float = fwd.dot(vn)
					var fh := Vector3(fwd.x, 0.0, fwd.z)
					var vh := Vector3(vn.x, 0.0, vn.z)
					var dh: float = 1.0
					if fh.length_squared() > 0.0001 and vh.length_squared() > 0.0001:
						dh = fh.normalized().dot(vh.normalized())
					min_dot = minf(min_dot, d)
					min_dot_h = minf(min_dot_h, dh)
					samples += 1
					if d <= 0.9:
						viol += 1
			elif st == 2:
				landing_frames += 1
				if wl != null:
					landing_flare = minf(landing_flare, wl.rotation.z)
			prev[bi] = pos
			prev_state[bi] = st
	print("[ORIENT] fly_frames=%d samples=%d min_dot=%.4f min_dot_h=%.4f violations=%d max_speed=%.2f m/s" % [flap_frames, samples, min_dot, min_dot_h, viol, max_speed])
	print("[ORIENT] pitch=[%.3f, %.3f] roll=[%.3f, %.3f] clamp=±%.3f/±%.3f" % [pitch_lo, pitch_hi, roll_lo, roll_hi, PITCH_MAX, ROLL_MAX])
	print("[ORIENT] wing_root_z=[%.3f, %.3f] elbow_z=[%.3f, %.3f] glide_frames=%d/%d landing_frames=%d landing_flare_min=%.3f leg_tuck_max=%.3f" % [wing_lo, wing_hi, elbow_lo, elbow_hi, glide_frames, maxi(flap_frames, 1), landing_frames, landing_flare, flight_leg_tuck])
	print("[ORIENT] phase_lag: wing_peak=%.3f elbow@wing_peak=%.3f (diff=%.3f) elbow_peak=%.3f wing@elbow_peak=%.3f (diff=%.3f)" % [wing_peak, elbow_at_wing_peak, absf(elbow_peak - elbow_at_wing_peak), elbow_peak, wing_at_elbow_peak, absf(wing_peak - wing_at_elbow_peak)])
	print("[ORIENT] seen_states=", seen_states.keys(), " takeoffs=", last_takeoffs, " landings=", last_landings)
	_check(samples > 400, "飞行朝向采样帧数 %d > 400" % samples)
	_check(min_dot > 0.9, "dot(forward, velocity) 最小值 %.4f > 0.9（无倒飞）" % min_dot)
	_check(viol == 0, "倒飞帧数 = %d（要求 0）" % viol)
	_check(pitch_lo >= -PITCH_MAX - 0.03 and pitch_hi <= PITCH_MAX + 0.03, "pitch 限幅 ±35°（%.3f ~ %.3f）" % [pitch_lo, pitch_hi])
	_check(roll_lo >= -ROLL_MAX - 0.03 and roll_hi <= ROLL_MAX + 0.03, "roll 限幅 ±0.55（%.3f ~ %.3f）" % [roll_lo, roll_hi])
	_check(pitch_hi - pitch_lo > 0.02, "pitch 随速度变化（范围 %.3f）" % (pitch_hi - pitch_lo))
	_check(roll_hi - roll_lo > 0.02, "roll 随转向变化（范围 %.3f）" % (roll_hi - roll_lo))
	_check(wing_hi - wing_lo > 0.9, "振翅幅度（wing root z 范围 %.3f > 0.9）" % (wing_hi - wing_lo))
	# 相位差证据：翼根到峰值那一帧，肘部并不在自己的峰值（差 0.72rad）；反之肘部到峰值时翼根也不在峰值（差 0.95rad）
	_check(absf(elbow_peak - elbow_at_wing_peak) > 0.25 and absf(wing_peak - wing_at_elbow_peak) > 0.25 and elbow_hi - elbow_lo > 0.25, "内外翼相位差：翼根峰值帧肘部距其峰值 %.3f、肘部峰值帧翼根距其峰值 %.3f、肘部幅度 %.3f（>0.25 即外翼滞后于内翼）" % [absf(elbow_peak - elbow_at_wing_peak), absf(wing_peak - wing_at_elbow_peak), elbow_hi - elbow_lo])
	_check(glide_frames > 30, "滑翔帧数 %d > 30（有滑翔段）" % glide_frames)
	_check(landing_frames > 5, "降落帧数 %d > 5（有降落姿态）" % landing_frames)
	_check(landing_flare < -0.5, "降落时翅膀上举收刹（wing_l.rotation.z min %.3f < -0.5）" % landing_flare)
	_check(flight_leg_tuck > 0.8, "飞行时双腿后收（legs.rotation.x max %.3f > 0.8）" % flight_leg_tuck)
	_check(bad_nan == 0, "无 NaN 位置")
	_check(seen_states.has(0) and seen_states.has(2), "白天出现 FLY 与 LANDING 状态")

# ============================================================
# 4) 停栖朝向：facing 向量 → yaw 一致；夜间全栖息
# ============================================================
func _probe_perch(flock) -> void:
	print("--- PERCH ---")
	var perches: Array = flock.get_perches()
	# float 旧格式数量应从原始输入统计（归一化后 facing 一律是 yaw float）
	var raw_float := 0
	for raw in _make_perches():
		if raw is Dictionary and typeof((raw as Dictionary)["facing"]) == TYPE_FLOAT:
			raw_float += 1
	print("[PERCH] perches=", perches.size(), " slots=", _total_slots(perches), " raw_float_facing=", raw_float)
	_check(perches.size() == 10, "10 个栖枝归一化")
	_check(_total_slots(perches) >= Fx.BIRD_COUNT, "槽位 >= 鸟数")
	_check(raw_float == 1, "float facing 旧格式仍被接受（原始输入 1 个）")
	# 原始输入 facing（世界方向向量）作为预期朝向；与归一化后的 yaw 无关
	var expect := _expected_facing_by_pos()
	# 夜间：全部降落且朝向与 facing 向量一致
	var all_perched := -1
	var frames := int(NIGHT_SECS / DT)
	for i in range(frames):
		flock.update_birds(DT, -8.0)
		var st: Dictionary = flock.get_state_counts()
		if all_perched < 0 and int(st["perched"]) == Fx.BIRD_COUNT:
			all_perched = i
	var stn: Dictionary = flock.get_state_counts()
	print("[PERCH] night: all_perched_frame=", all_perched, " ", _fmt_counts(stn))
	print("[PERCH] night perch facing check:")
	var bad := 0
	var min_facing_dot := 9.0
	var folded_ok := 0
	for b_v in _birds(flock):
		var b: Dictionary = b_v
		var node: Node3D = b["node"]
		if int(b["state"]) != 3:
			continue
		var perch: Dictionary = {}
		for p_v2 in perches:
			var p2: Dictionary = p_v2
			if String(p2["id"]) == String(b["perch_id"]):
				perch = p2
				break
		if perch.is_empty():
			bad += 1
			continue
		var yaw: float = float(perch["facing"])
		var fwd: Vector3 = node.global_basis.z
		var want: Vector3 = expect.get(_vkey(perch["pos"]), Vector3(0.0, 0.0, 1.0))
		var got := Vector3(fwd.x, 0.0, fwd.z)
		var d := 9.0
		if got.length_squared() > 0.0001:
			d = got.normalized().dot(want)
		min_facing_dot = minf(min_facing_dot, d)
		var wl: Node3D = _find(node, "wing_l")
		var el: Node3D = _find(node, "elbow_l")
		var ok := wl != null and absf(wl.rotation.y) > 1.0
		if el != null and absf(el.rotation.y) > 0.3:
			ok = ok and true
		if ok:
			folded_ok += 1
		print("  %s state=%d perch=%s yaw=%.3f facing_dot=%.4f wing_l.y=%.3f elbow_l.y=%.3f" % [
			node.name, int(b["state"]), String(b["perch_id"]), yaw, d,
			wl.rotation.y if wl != null else 0.0,
			el.rotation.y if el != null else 0.0])
	print("[PERCH] min_facing_dot=%.4f folded_ok=%d/%d" % [min_facing_dot, folded_ok, Fx.BIRD_COUNT])
	_check(all_perched >= 0, "夜间在 %.1fs 内全部栖息" % NIGHT_SECS)
	_check(int(stn["perched"]) == Fx.BIRD_COUNT, "夜间 perched = 10（实际 %d）" % int(stn["perched"]))
	_check(int(stn["takeoffs_night"]) == 0, "夜间无起飞（实际 %d）" % int(stn["takeoffs_night"]))
	_check(int(stn["perch_conflicts"]) == 0, "夜间无栖枝冲突")
	_check(min_facing_dot > 0.999, "停栖朝向与 facing 向量一致（min dot %.4f > 0.999）" % min_facing_dot)
	_check(folded_ok == Fx.BIRD_COUNT, "停栖收翼（wing_l.rotation.y > 1.0）%d/10" % folded_ok)

func _vkey(v: Vector3) -> String:
	return "%.4f,%.4f,%.4f" % [v.x, v.y, v.z]

## 原始输入（_make_perches）→ 世界朝向单位向量；raw Vector3 栖枝按“朝向岛心”兜底
func _expected_facing_by_pos() -> Dictionary:
	var out: Dictionary = {}
	for raw in _make_perches():
		if raw is Dictionary:
			var p: Dictionary = raw
			var pos: Vector3 = p["pos"]
			if typeof(p["facing"]) == TYPE_FLOAT:
				var f := float(p["facing"])
				out[_vkey(pos)] = Vector3(sin(f), 0.0, cos(f))
			else:
				var fv: Vector3 = p["facing"]
				var flat := Vector3(fv.x, 0.0, fv.z)
				out[_vkey(pos)] = flat.normalized() if flat.length_squared() > 1.0e-9 else Vector3(0.0, 0.0, 1.0)
		elif raw is Vector3:
			var pos2: Vector3 = raw
			var to_center := Vector3(-pos2.x, 0.0, -pos2.z)
			out[_vkey(pos2)] = to_center.normalized() if to_center.length_squared() > 1.0e-9 else Vector3(0.0, 0.0, 1.0)
	return out

func _total_slots(perches: Array) -> int:
	var n := 0
	for p_v in perches:
		n += int((p_v as Dictionary)["slots"])
	return n

# ============================================================
# 5) 每帧零分配：节点数不随帧增长
# ============================================================
func _probe_alloc(flock) -> void:
	print("--- ALLOC ---")
	flock.update_birds(DT, 22.0)
	var before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	for i in range(180):
		flock.update_birds(DT, 22.0)
	var after := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	print("[ALLOC] node_count before=", before, " after=", after, " delta=", after - before)
	_check(after - before <= 10, "180 帧节点数不增长（delta=%d <= 10）" % (after - before))
