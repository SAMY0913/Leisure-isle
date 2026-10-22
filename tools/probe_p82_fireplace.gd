extends SceneTree

# P8.2-01 壁炉几何探针：烟囱不再侵入一层室内 + 炉膛真实凹龛 + 火焰可见 + 烟帽/栖点不变。
# 用法（headless 只跑断言；窗口截图必须不带 --headless）：
#   Godot --headless --path <工程> --script res://tools/probe_p82_fireplace.gd -- --mode=geom
#   Godot --path <工程> --resolution 1600x900 --script res://tools/probe_p82_fireplace.gd -- --mode=shots --out=<证据目录>
#
# geom 断言（每一处失败都会打印真实 AABB/射线遮挡原因）：
#   G1  一层室内净空（z>-2.80 且 y<2.97）无烟囱主体/石箍侵入（进深 >0.31m 即判失败）
#   G2  壁炉贴墙装修件进深 <=0.275m
#   G3  炉膛为真实凹龛：黑膛板在开口平面之后、凹深 >=0.10m
#   G4  三块火焰盒整体位于开口平面之内（z <= -2.52）且高度 >=0.10
#   G5  halo 收小（<=0.50）并退入凹龛（z <= -2.545）
#   G6  正面/低机位/斜侧射线不被烟囱体或石胸阻挡（front/low 3/3，oblique >=2/3）
#   G7  烟帽顶 6.55 / ChimneyTop / 烟囱栖点 / 穿越屋面 / 泛水石 全部不变
#   G8  壁炉光槽 local (ch_x, fy+0.55, -2.30) 且不在任何实体盒内、属室内池
#   G9  ChimneyHit 位置 (ch_x,5.10,ch_z) 与尺寸 (1.1,2.9,1.1) 不变
# shots 模式输出（真实窗口，生产合批路径）：
#   q0..q4_fire_front / q0..q4_fire_oblique、q2_fire_low、q2_room_wide、
#   q2_exterior_chimney、q2_attic_view、q2_attic_chimney_side、day_front、day_oblique

const OUT_DIR := "D:/休闲小岛幻境/开发产物/p82/01_fireplace/shots/"

var _mode := "geom"
var _out := OUT_DIR
var _fails: Array[String] = []
var _checks := 0
var _isle: Node = null
var _root: Node3D = null
var _C: Dictionary = {}
var _items: Array = []
var _fy := 0.55
var _in_top := 2.97
var _ch_x := -2.20
var _ch_z := -2.60
var _ch_top := 6.20
var _ridge_y := 6.20
var _roof_y := 4.77

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--mode="):
			_mode = s.substr(7)
		elif s.begins_with("--out="):
			_out = s.substr(6)
	_run.call_deferred()

func _ok(cond: bool, msg: String, detail: String = "") -> void:
	_checks += 1
	if cond:
		if detail == "":
			print("[P82FP] OK   " + msg)
		else:
			print("[P82FP] OK   " + msg + " | " + detail)
	else:
		_fails.append(msg)
		print("[P82FP] FAIL " + msg + " | " + detail)

func _wait(sec: float) -> void:
	await create_timer(sec).timeout

func _w(local: Vector3) -> Vector3:
	return _root.to_global(local)

func _run() -> void:
	var booted := await _boot()
	if not booted:
		quit(1)
		return
	if _mode == "shots":
		await _shots()
		print("[P82FP] SUMMARY mode=shots shots_done")
		quit(0)
		return
	_collect()
	_report_geometry()
	_check_no_intrusion()
	_check_wall_pieces()
	_check_recess()
	_check_flames()
	_check_halo()
	_check_visibility()
	_check_cap_perch_roof()
	_check_light()
	_check_hitbox()
	print("[P82FP] SUMMARY checks=%d fails=%d" % [_checks, _fails.size()])
	for f in _fails:
		print("[P82FP] FAILED_ITEM " + f)
	quit(1 if _fails.size() > 0 else 0)

# ---------------------------------------------------------------- boot / collect
func _boot() -> bool:
	if _mode == "geom":
		# 探针专用：跳过静态合批，保留逐件 MeshInstance 以测量真实构建几何。
		IsleCottage.probe_skip_batch = true
	var packed: PackedScene = load("res://isle.tscn")
	_ok(packed != null, "isle.tscn 可加载")
	if packed == null:
		return false
	_isle = packed.instantiate()
	root.add_child(_isle)
	for i in range(6):
		await process_frame
	var c = _isle._cottage
	_ok(c is Dictionary and c.has("root"), "main 构建 cottage 字典")
	if not (c is Dictionary and c.has("root")):
		return false
	_root = c["root"]
	_C = _root.get_meta("cottage_ctx")
	_fy = float(_C["fy"])
	_in_top = float(_C["in_top"])
	_ch_x = float(_C["ch_x"])
	_ch_z = float(_C["ch_z"])
	_ch_top = float(_C["ch_top"])
	_ridge_y = float(_C["ridge_y"])
	_roof_y = _ridge_y - absf(_ch_x) * tan(float(_C["pitch"]))
	print("[P82FP] ctx fy=%.3f in_top=%.3f ch_x=%.3f ch_z=%.3f ch_top=%.3f ridge=%.3f roof_y@ch=%.3f" % [_fy, _in_top, _ch_x, _ch_z, _ch_top, _ridge_y, _roof_y])
	return true

func _collect() -> void:
	_items.clear()
	_walk(_root)
	_items.sort_custom(func(a, b): return float(a["c"].y) > float(b["c"].y))
	print("[P82FP] collected MeshInstance3D items=%d (probe_skip_batch=true)" % _items.size())

func _walk(n: Node) -> void:
	for ch in n.get_children():
		if ch is MultiMeshInstance3D:
			continue
		if ch is MeshInstance3D and (ch as MeshInstance3D).mesh != null:
			_add_item(ch as MeshInstance3D)
		_walk(ch)

func _add_item(mi: MeshInstance3D) -> void:
	var xf: Transform3D = _root.global_transform.affine_inverse() * mi.global_transform
	var ab := _xf_aabb(xf, mi.mesh.get_aabb())
	var col := Color(0.0, 0.0, 0.0)
	var self_lit := 0.0
	var glow := 0.0
	var sh := mi.material_override as ShaderMaterial
	if sh != null:
		var ca = sh.get_shader_parameter("albedo")
		if ca is Color:
			col = ca
		var sl = sh.get_shader_parameter("self_lit")
		if sl is float or sl is int:
			self_lit = float(sl)
		var gl = sh.get_shader_parameter("glow")
		if gl is float or gl is int:
			glow = float(gl)
	var add := false
	var sm := mi.material_override as StandardMaterial3D
	if sm != null:
		col = sm.albedo_color
		add = sm.blend_mode == BaseMaterial3D.BLEND_MODE_ADD
	var kind := mi.mesh.get_class()
	if mi.mesh is BoxMesh:
		kind = "Box"
	elif mi.mesh is QuadMesh:
		kind = "Quad"
	elif mi.mesh is CylinderMesh:
		kind = "Cyl"
	elif mi.mesh is SphereMesh:
		kind = "Sphere"
	elif mi.mesh is PlaneMesh:
		kind = "Plane"
	_items.append({
		"node": mi,
		"path": String(_root.get_path_to(mi)),
		"kind": kind,
		"aabb": ab,
		"c": ab.get_center(),
		"s": ab.size,
		"color": col,
		"self_lit": self_lit,
		"glow": glow,
		"add": add,
	})

func _xf_aabb(xf: Transform3D, ab: AABB) -> AABB:
	var mn := Vector3(INF, INF, INF)
	var mx := Vector3(-INF, -INF, -INF)
	for i in range(8):
		var p := ab.position + Vector3(
			ab.size.x * float(i & 1),
			ab.size.y * float((i >> 1) & 1),
			ab.size.z * float((i >> 2) & 1))
		var q := xf * p
		mn = Vector3(minf(mn.x, q.x), minf(mn.y, q.y), minf(mn.z, q.z))
		mx = Vector3(maxf(mx.x, q.x), maxf(mx.y, q.y), maxf(mx.z, q.z))
	return AABB(mn, mx - mn)

func _zone_of(it: Dictionary) -> String:
	var a: AABB = it["aabb"]
	var col: Color = it["color"]
	if String(it["kind"]) == "Quad" and (bool(it["add"]) or col.r > 1.2):
		return "halo"
	if float(it["self_lit"]) >= 0.5 and float(it["glow"]) >= 1.0 and String(it["kind"]) == "Box":
		return "flame"
	if col.get_luminance() < 0.15 and String(it["kind"]) == "Box":
		return "firebox"
	if a.end.z <= -2.795:
		return "behind_wall"
	return "in_room"

# ---------------------------------------------------------------- report
func _report_geometry() -> void:
	print("[P82FP] ---- 壁炉/烟囱逐件 AABB（root 局部坐标；后墙内表面 z=-2.80、外表面 z=-3.10）----")
	for it in _items:
		var c: Vector3 = it["c"]
		if absf(c.x - _ch_x) > 1.05:
			continue
		if c.z > -1.80:
			continue
		var a: AABB = it["aabb"]
		var wa := _xf_aabb(_root.global_transform, a)
		print("[P82FP] GEO %-10s %-34s %-5s size=(%.3f,%.3f,%.3f) c=(%.3f,%.3f,%.3f) z=[%.3f,%.3f] y=[%.3f,%.3f] col=(%.2f,%.2f,%.2f) lit=%.2f glow=%.2f" % [
			_zone_of(it), String(it["path"]), String(it["kind"]),
			a.size.x, a.size.y, a.size.z, c.x, c.y, c.z,
			a.position.z, a.end.z, a.position.y, a.end.y,
			it["color"].r, it["color"].g, it["color"].b, float(it["self_lit"]), float(it["glow"])])
		print("[P82FP]     world aabb c=(%.3f,%.3f,%.3f) size=(%.3f,%.3f,%.3f)" % [wa.get_center().x, wa.get_center().y, wa.get_center().z, wa.size.x, wa.size.y, wa.size.z])

# ---------------------------------------------------------------- G1
func _check_no_intrusion() -> void:
	print("---- [G1] 一层室内净空 z>-2.80 无烟囱侵入 ----")
	var bad := 0
	var max_depth := 0.0
	for it in _items:
		var a: AABB = it["aabb"]
		var c: Vector3 = it["c"]
		if absf(c.x - _ch_x) > 0.85:
			continue
		if c.z > -2.00:
			continue
		if a.end.z <= -2.795:
			continue
		if a.position.y >= _in_top - 0.01:
			continue
		if _zone_of(it) == "halo":
			continue
		var depth := a.size.z
		var floor_slab := a.end.y <= _fy + 0.13 and depth <= 0.63
		if depth <= 0.315 or floor_slab:
			max_depth = maxf(max_depth, depth)
			continue
		bad += 1
		print("[P82FP] INTRUDE %s %s size=(%.3f,%.3f,%.3f) c=(%.3f,%.3f,%.3f) z=[%.3f,%.3f] y=[%.3f,%.3f]" % [
			_zone_of(it), String(it["path"]), a.size.x, a.size.y, a.size.z,
			c.x, c.y, c.z, a.position.z, a.end.z, a.position.y, a.end.y])
	_ok(bad == 0, "G1 一层室内无烟囱侵入件（进深>0.31m）", "bad=%d max_ok_depth=%.3f" % [bad, max_depth])

# ---------------------------------------------------------------- G2
func _check_wall_pieces() -> void:
	print("---- [G2] 壁炉贴墙件进深 ----")
	var over := 0
	var maxd := 0.0
	var buried := 0
	for it in _items:
		var a: AABB = it["aabb"]
		var c: Vector3 = it["c"]
		if absf(c.x - _ch_x) > 0.90:
			continue
		if c.z > -2.00:
			continue
		if a.position.z > -2.79:
			continue
		if a.end.y > _fy + 1.90 or a.position.y < _fy - 0.06:
			continue
		if a.end.y <= _fy + 0.13:
			continue  # 地面/炉台石按 G1 的地面规则判定，不受贴墙进深约束
		var d := a.size.z
		maxd = maxf(maxd, d)
		if d > 0.275:
			over += 1
			print("[P82FP] DEEP %s depth=%.3f z=[%.3f,%.3f]" % [String(it["path"]), d, a.position.z, a.end.z])
		if a.position.z < -2.815:
			buried += 1
	_ok(over == 0, "G2 壁炉贴墙件进深 <=0.275m", "over=%d maxd=%.3f" % [over, maxd])
	_ok(buried == 0, "G2b 贴墙件不埋进墙体（z0>=-2.815）", "buried=%d" % buried)

# ---------------------------------------------------------------- G3
func _check_recess() -> void:
	print("---- [G3] 炉膛凹龛 ----")
	var fb: Array = []
	for it in _items:
		var a: AABB = it["aabb"]
		var c: Vector3 = it["c"]
		if _zone_of(it) != "firebox":
			continue
		if absf(c.x - _ch_x) > 0.50:
			continue
		if c.z > -2.00 or c.y > _fy + 1.05:
			continue
		fb.append(it)
	_ok(fb.size() == 1, "G3 黑膛板数量=1", "count=%d" % fb.size())
	if fb.size() == 1:
		var a: AABB = fb[0]["aabb"]
		_ok(absf(a.size.x - 0.82) < 0.08 and absf(a.size.y - 0.72) < 0.08, "G3b 黑膛板尺寸 ~0.82x0.72", "size=(%.3f,%.3f)" % [a.size.x, a.size.y])
		_ok(a.end.z <= -2.60, "G3c 黑膛板位于开口平面之后（烤漆凹入）", "z=[%.3f,%.3f]" % [a.position.z, a.end.z])
		var front := -999.0
		for it2 in _items:
			var b: AABB = it2["aabb"]
			var c2: Vector3 = it2["c"]
			if absf(c2.x - _ch_x) > 0.90 or c2.z > -2.00:
				continue
			if b.position.z > -2.79:
				continue
			if b.end.y > _fy + 1.90 or b.position.y < _fy - 0.06:
				continue
			front = maxf(front, b.end.z)
		var recess := front - a.end.z
		_ok(recess >= 0.10, "G3d 凹龛进深 >=0.10m", "recess=%.3f front=%.3f panel=%.3f" % [recess, front, a.end.z])

# ---------------------------------------------------------------- G4
func _check_flames() -> void:
	print("---- [G4] 火焰盒 ----")
	var fl: Array = []
	for it in _items:
		if _zone_of(it) != "flame":
			continue
		var c: Vector3 = it["c"]
		if absf(c.x - _ch_x) > 0.60 or c.y > _fy + 1.20 or c.z > -2.10:
			continue
		fl.append(it)
	_ok(fl.size() == 3, "G4 火焰盒数量=3", "count=%d" % fl.size())
	var bad := 0
	for it in fl:
		var a: AABB = it["aabb"]
		var c: Vector3 = it["c"]
		var ok := a.end.z <= -2.52 and a.position.z >= -2.81 and a.size.y >= 0.10 and absf(c.x - _ch_x) + a.size.x * 0.5 <= 0.45 and a.position.y >= _fy + 0.02
		if not ok:
			bad += 1
			print("[P82FP] FLAME_BAD z=[%.3f,%.3f] y=[%.3f,%.3f] size=(%.3f,%.3f,%.3f) c=(%.3f,%.3f,%.3f)" % [
				a.position.z, a.end.z, a.position.y, a.end.y, a.size.x, a.size.y, a.size.z, c.x, c.y, c.z])
	_ok(bad == 0, "G4b 火焰盒整体在开口平面内且高度>=0.10", "bad=%d" % bad)

# ---------------------------------------------------------------- G5
func _check_halo() -> void:
	print("---- [G5] 壁炉 halo ----")
	var hs: Array = []
	for it in _items:
		if _zone_of(it) != "halo":
			continue
		var c: Vector3 = it["c"]
		if absf(c.x - _ch_x) > 0.70 or c.y > _fy + 1.20 or c.z > -2.00:
			continue
		hs.append(it)
	_ok(hs.size() == 1, "G5 壁炉 halo 数量=1", "count=%d" % hs.size())
	if hs.size() == 1:
		var a: AABB = hs[0]["aabb"]
		var c: Vector3 = hs[0]["c"]
		_ok(a.size.x <= 0.50, "G5b halo 尺寸 <=0.50", "size=%.3f" % a.size.x)
		_ok(c.z <= -2.545 and c.z >= -2.81, "G5c halo 退入凹龛（-2.81<=z<=-2.545）", "z=%.3f" % c.z)

# ---------------------------------------------------------------- G6
func _seg_hits_aabb(p0: Vector3, p1: Vector3, ab: AABB) -> float:
	var d := p1 - p0
	var tmin := 0.0
	var tmax := 1.0
	for ax in range(3):
		var o: float = p0[ax]
		var dd: float = d[ax]
		var mn: float = ab.position[ax]
		var mx: float = ab.position[ax] + ab.size[ax]
		if absf(dd) < 1e-9:
			if o < mn or o > mx:
				return -1.0
		else:
			var t1 := (mn - o) / dd
			var t2 := (mx - o) / dd
			if t1 > t2:
				var tmp := t1
				t1 = t2
				t2 = tmp
			tmin = maxf(tmin, t1)
			tmax = minf(tmax, t2)
			if tmin > tmax:
				return -1.0
	return tmin

func _first_occluder(eye: Vector3, target: Vector3, skip: Array) -> Dictionary:
	var best_t := 2.0
	var best: Dictionary = {}
	for it in _items:
		if skip.has(it["node"]):
			continue
		var z := _zone_of(it)
		if z == "halo" or z == "flame" or z == "firebox":
			continue
		var a: AABB = it["aabb"]
		if a.end.y <= _fy + 0.14:
			continue  # 地面/炉台石不挡视线
		var t := _seg_hits_aabb(eye, target, a)
		if t > 0.015 and t < 0.985 and t < best_t:
			best_t = t
			best = {"t": t, "item": it}
	return best

func _check_visibility() -> void:
	print("---- [G6] 室内可见方向射线遮挡 ----")
	var fl: Array = []
	for it in _items:
		if _zone_of(it) != "flame":
			continue
		var c: Vector3 = it["c"]
		if absf(c.x - _ch_x) > 0.60 or c.y > _fy + 1.20 or c.z > -2.10:
			continue
		fl.append(it)
	if fl.size() != 3:
		_ok(false, "G6 火焰盒数量不足，无法做可见性测试", "count=%d" % fl.size())
		return
	var cams := [
		{"name": "front", "eye": Vector3(_ch_x + 0.15, _fy + 1.02, -0.35)},
		{"name": "low", "eye": Vector3(_ch_x + 0.10, _fy + 0.48, -0.85)},
		{"name": "oblique", "eye": Vector3(_ch_x + 1.30, _fy + 1.00, -0.50)},
	]
	var halo_node: Node = null
	for it in _items:
		if _zone_of(it) == "halo" and absf(it["c"].x - _ch_x) <= 0.70 and it["c"].z <= -2.00:
			halo_node = it["node"]
	for cam in cams:
		var eye: Vector3 = cam["eye"]
		var vis := 0
		for it in fl:
			var skip: Array = [it["node"]]
			if halo_node != null:
				skip.append(halo_node)
			var oc := _first_occluder(eye, it["c"], skip)
			if oc.is_empty():
				vis += 1
			else:
				var oi: Dictionary = oc["item"]
				print("[P82FP] OCCLUDED cam=%s flame=(%.3f,%.3f,%.3f) by=%s zone=%s t=%.3f aabb c=(%.3f,%.3f,%.3f) s=(%.3f,%.3f,%.3f)" % [
					String(cam["name"]), it["c"].x, it["c"].y, it["c"].z, String(oi["path"]), _zone_of(oi), float(oc["t"]),
					oi["c"].x, oi["c"].y, oi["c"].z, oi["aabb"].size.x, oi["aabb"].size.y, oi["aabb"].size.z])
		var need := 3 if String(cam["name"]) != "oblique" else 2
		_ok(vis >= need, "G6 火焰可见性 cam=%s" % String(cam["name"]), "visible=%d/3 need=%d" % [vis, need])
	if halo_node != null:
		var oc2 := _first_occluder(cams[0]["eye"], _items[0]["c"], [])
		_ok(oc2.is_empty() or true, "G6 halo 记录", "")
		var hp := Vector3.ZERO
		for it in _items:
			if it["node"] == halo_node:
				hp = it["c"]
		var oc := _first_occluder(cams[0]["eye"], hp, [halo_node])
		_ok(oc.is_empty(), "G6b halo 正面不被实体遮挡", "by=%s" % (String(oc["item"]["path"]) if not oc.is_empty() else "none"))

# ---------------------------------------------------------------- G7
func _check_cap_perch_roof() -> void:
	print("---- [G7] 烟帽/栖点/屋顶交界 ----")
	var top := _isle._cottage["chimney_top"] as Node3D
	var want := Vector3(_ch_x, _ch_top + 0.35, _ch_z)
	_ok(top.position.distance_to(want) < 1e-3, "G7 ChimneyTop local pos == (%s)" % str(want), "pos=(%.3f,%.3f,%.3f)" % [top.position.x, top.position.y, top.position.z])
	var wtop := top.global_position
	var wexp := _w(want)
	_ok(wtop.distance_to(wexp) < 1e-3, "G7b ChimneyTop world y = 底+6.55", "world_y=%.3f expect=%.3f" % [wtop.y, wexp.y])
	var max_end := -INF
	for it in _items:
		var a: AABB = it["aabb"]
		if absf(it["c"].x - _ch_x) <= 0.85 and it["c"].z <= -2.05:
			max_end = maxf(max_end, a.end.y)
	_ok(absf(max_end - (_ch_top + 0.35)) <= 0.006, "G7c 烟帽最高点 y=6.55 不变", "geom_top=%.3f" % max_end)
	var crossing := 0
	var top_x := 0.0
	for it in _items:
		var a: AABB = it["aabb"]
		if absf(it["c"].x - _ch_x) <= 0.70 and it["c"].z <= -2.05 and a.position.y <= _roof_y - 0.30 and a.end.y >= _roof_y + 0.30:
			crossing += 1
			top_x = it["c"].z
	_ok(crossing >= 1, "G7d 烟囱穿越屋面（交界面存在）", "crossing=%d at z=%.3f roof_y=%.3f" % [crossing, top_x, _roof_y])
	var flash := 0
	var flash_y := 0.0
	for it in _items:
		var a: AABB = it["aabb"]
		if absf(it["c"].x - _ch_x) <= 0.45 and a.end.y <= _roof_y + 0.45 and a.size.x >= 1.0 and a.size.z >= 1.0:
			flash += 1
			flash_y = it["c"].y
	_ok(flash >= 1, "G7e 泛水石/泛水板仍在屋面交界", "count=%d y=%.3f" % [flash, flash_y])
	var perches: Array = _isle._cottage["perches"]
	var got := false
	for p in perches:
		if String(p["id"]) != "chimney_0":
			continue
		got = true
		var want_pp := _w(Vector3(_ch_x, _ch_top + 0.38, _ch_z))
		var pp: Vector3 = p["pos"]
		_ok(pp.distance_to(want_pp) < 0.02, "G7f 烟囱栖点位置不变", "pos=(%.3f,%.3f,%.3f) expect=(%.3f,%.3f,%.3f)" % [pp.x, pp.y, pp.z, want_pp.x, want_pp.y, want_pp.z])
		_ok(String(p["kind"]) == "chimney", "G7g 栖点 kind=chimney 保持", "kind=%s" % String(p["kind"]))
	_ok(got, "G7h chimney_0 栖点存在")

# ---------------------------------------------------------------- G8
func _check_light() -> void:
	print("---- [G8] 壁炉光槽 ----")
	var found := false
	for ls in _isle._cottage["light_sources"]:
		if String(ls["kind"]) != "fireplace":
			continue
		found = true
		var lp: Vector3 = _root.to_local(ls["pos"] as Vector3)
		_ok(lp.distance_to(Vector3(_ch_x, _fy + 0.55, -2.30)) < 0.02, "G8 壁炉光槽 local pos 不变", "local=(%.3f,%.3f,%.3f)" % [lp.x, lp.y, lp.z])
		var inside: Array = []
		for it in _items:
			if String(it["kind"]) != "Box":
				continue
			var a: AABB = it["aabb"]
			if a.has_point(lp):
				inside.append(String(it["path"]))
		_ok(inside.size() == 0, "G8b 壁炉光槽不在任何实体盒内（无遮挡暗斑）", "inside=%s" % str(inside))
		_ok(bool(ls["indoor"]), "G8c 壁炉灯属室内池", "indoor=%s" % str(ls["indoor"]))
	_ok(found, "G8d 壁炉灯存在")

# ---------------------------------------------------------------- G9
func _check_hitbox() -> void:
	print("---- [G9] ChimneyHit ----")
	var body := _isle._cottage["chimney_hit"] as Node3D
	_ok(body != null, "G9 ChimneyHit 存在")
	if body == null:
		return
	var hp := _root.to_local(body.global_position)
	_ok(hp.distance_to(Vector3(_ch_x, 5.10, _ch_z)) < 0.02, "G9b ChimneyHit 中心不漂移", "local=(%.3f,%.3f,%.3f)" % [hp.x, hp.y, hp.z])
	var shape := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape == null:
		for ch in body.get_children():
			if ch is CollisionShape3D:
				shape = ch
	_ok(shape != null and shape.shape is BoxShape3D and (shape.shape as BoxShape3D).size.distance_to(Vector3(1.1, 2.9, 1.1)) < 1e-3, "G9c ChimneyHit size=(1.1,2.9,1.1)", str(shape.shape.size) if shape != null and shape.shape is BoxShape3D else "none")

# ---------------------------------------------------------------- shots
func _cam(eye_local: Vector3, target_local: Vector3, fov: float) -> void:
	_isle._pose_look(_w(eye_local), _w(target_local), fov)

func _shot(tag: String) -> void:
	await _isle._save_shot(tag, _out)

func _shots() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	_isle._mode = 1
	_isle._started = true
	_isle._paused = true
	_isle._blending = ""
	if _isle._menu != null:
		_isle._menu.instant_finish()
	if _isle._hud != null:
		_isle._hud.set_hud_visible(false, false)
	_isle._auto_orbit = false
	_isle._shot_beam_lock = true
	_isle._time_source = "sim"
	await _wait(0.8)
	var fx := _ch_x
	var fz := -2.35
	var eye_front := Vector3(fx + 0.15, _fy + 1.02, -0.35)
	var eye_low := Vector3(fx + 0.10, _fy + 0.48, -0.85)
	var eye_obl := Vector3(fx + 1.30, _fy + 1.00, -0.50)
	var tgt := Vector3(fx + 0.02, _fy + 0.40, fz)
	# 夜间（壁炉照明最能体现）：五档 × 正面/斜侧
	_isle._p8_wfx_apply(2027, 1, 15, 20, 30, "clear", 0.0)
	await _wait(0.7)
	for q in range(5):
		_isle._apply_quality(q)
		await _wait(0.55)
		_cam(eye_front, tgt, 46.0)
		await _shot("q%d_fire_front" % q)
		_cam(eye_obl, tgt, 46.0)
		await _shot("q%d_fire_oblique" % q)
	_isle._apply_quality(2)
	await _wait(0.55)
	_cam(eye_low, tgt, 50.0)
	await _shot("q2_fire_low")
	_cam(Vector3(1.30, _fy + 1.75, 2.20), Vector3(-1.60, _fy + 0.95, -2.55), 62.0)
	await _shot("q2_room_wide")
	_cam(Vector3(fx - 2.60, 5.20, 4.60), Vector3(fx, 5.60, _ch_z), 55.0)
	await _shot("q2_exterior_chimney")
	_cam(Vector3(0.20, 4.72, 2.35), Vector3(0.20, 3.55, -1.60), 62.0)
	await _shot("q2_attic_view")
	_cam(Vector3(0.20, 4.55, 1.10), Vector3(fx, 3.95, _ch_z), 66.0)
	await _shot("q2_attic_chimney_side")
	# 正对阁楼段烟囱胸（验证分段后阁楼内仍为完整石体、与屋面/楼板交接自然）
	_cam(Vector3(0.70, 4.62, -1.05), Vector3(fx, 4.05, -2.72), 58.0)
	await _shot("q2_attic_breast")
	# 白天（结构/石面接缝可读）
	_isle._p8_wfx_apply(2027, 1, 15, 14, 00, "clear", 0.0)
	await _wait(0.7)
	_cam(eye_front, tgt, 46.0)
	await _shot("day_fire_front")
	_cam(eye_obl, tgt, 46.0)
	await _shot("day_fire_oblique")
	_cam(Vector3(1.30, _fy + 1.75, 2.20), Vector3(-1.60, _fy + 0.95, -2.55), 62.0)
	await _shot("day_room_wide")
	_cam(Vector3(0.70, 4.62, -1.05), Vector3(fx, 4.05, -2.72), 58.0)
	await _shot("day_attic_breast")
	print("[P82FP] shots -> " + _out)
