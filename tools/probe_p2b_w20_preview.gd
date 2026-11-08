extends SceneTree
# =============================================================================
# W20 小舌候选对比预览（临时探针，非正式游戏实现）
#   tools/probe_p2b_w20_preview.gd
#   目的：在窗口/离屏渲染下对比「无小舌」与「有小舌」两种门前土地近段，
#         供用户对 P2-B 的 W20 决策做视觉确认。
#   约束：不修改 world.gd / main.gd / cottage.gd / project.godot；
#         只在 isle.tscn 实例之上追加一块台面近段预览网格（真实地形高度场取样）。
#   用法：
#     Godot --path <工程> --script res://tools/probe_p2b_w20_preview.gd -- \
#       --out=<输出目录> --tongue   (带小舌)   / 不带 --tongue 为对照
# =============================================================================

const M := preload("res://scripts/isle_math.gd")
const SHOT_W := 1600
const SHOT_H := 1000
const TAN32 := 0.6248693519093274
const OFFSET := 0.02
const FLOOR_TERRACE := 7.53
# 台面多边形（房屋局部，P2-A v9 S4 六点 Γ 形；--tongue 时插入 0.35x0.45 小舌）
const POLY_BASE := [
	Vector2(-7.70, 3.28), Vector2(4.43, 3.28), Vector2(4.43, 5.15),
	Vector2(-1.45, 5.15), Vector2(-1.45, 14.75), Vector2(-7.70, 14.75)]
const POLY_TONGUE := [
	Vector2(-7.70, 3.28), Vector2(4.43, 3.28), Vector2(4.43, 5.15),
	Vector2(-1.10, 5.15), Vector2(-1.10, 5.60), Vector2(-1.45, 5.60),
	Vector2(-1.45, 14.75), Vector2(-7.70, 14.75)]
# 近段关注区（房屋局部）：覆盖三级踏步、左右台面、两路起步带
const RECT_MIN := Vector2(-4.60, 3.02)
const RECT_MAX := Vector2(2.60, 6.80)
const CELL := 0.06

var out_dir := "D:/休闲小岛幻境/开发产物/P9/P2/w20_preview"
var tongue := false
var tag_prefix := ""

var _main: Node = null
var _cam: Camera3D = null
var _sv: SubViewport = null
var _shot_cam: Camera3D = null
var _layout: Node3D = null
var _poly: Array = []
var _shots: Array = []
var _checks: Array = []
var _hide_rect := Rect2()
var _masked := 0

func _initialize() -> void:
	_run.call_deferred()

func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--out="):
			out_dir = s.substr(6)
		elif s == "--tongue":
			tongue = true
		elif s.begins_with("--tag="):
			tag_prefix = s.substr(6)

func _l2w(lx: float, lz: float) -> Vector2:
	var c := cos(M.HOUSE_YAW)
	var s := sin(M.HOUSE_YAW)
	return Vector2(M.HOUSE_X + lx * c + lz * s, M.HOUSE_Z - lx * s + lz * c)

func _w2l(x: float, z: float) -> Vector2:
	var c := cos(M.HOUSE_YAW)
	var s := sin(M.HOUSE_YAW)
	var dx := x - M.HOUSE_X
	var dz := z - M.HOUSE_Z
	return Vector2(dx * c - dz * s, dx * s + dz * c)

func _ground(lp: Vector2) -> float:
	var w := _l2w(lp.x, lp.y)
	return IsleWorld.surface_y(w.x, w.y)

func _pad_y(lp: Vector2) -> float:
	return maxf(_ground(lp) + OFFSET, FLOOR_TERRACE)

func _pt_in_poly(p: Vector2, poly: Array) -> bool:
	var inside := false
	var n := poly.size()
	var j := n - 1
	for i in range(n):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[j]
		if ((a.y > p.y) != (b.y > p.y)) and (p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x):
			inside = not inside
		j = i
	return inside

func _grass_color(w: Vector2) -> Color:
	var m1: float = IsleWorld._fbm(w.x * 0.055 + 3.0, w.y * 0.055 - 7.0)
	var m2: float = IsleWorld._fbm(w.x * 0.21 - 31.7, w.y * 0.21 + 12.3)
	var m3: float = IsleWorld._vnoise(w.x * 0.73 + 5.1, w.y * 0.73 - 8.9)
	var g: Color = M.C_GRASS
	g = g.lerp(M.C_GRASS_LIGHT, clampf(m1 * 1.5 - 0.05, 0.0, 1.0))
	g = g.lerp(M.C_GRASS_DARK, clampf(m2 * 0.42, 0.0, 1.0))
	g = g.lerp(Color(0.71, 0.73, 0.54), smoothstep(0.55, 0.92, m1) * 0.34)
	g = g.lerp(M.C_GRASS_LIGHT, m3 * 0.10)
	return g

func _check(id: String, ok: bool, detail: String) -> void:
	_checks.append({"id": id, "ok": ok, "detail": detail})
	print("[W20] %s %s  %s" % ["PASS" if ok else "FAIL", id, detail])

func _collect_mm(node: Node, out: Array) -> void:
	if node is MultiMeshInstance3D:
		out.append(node)
	for ch in node.get_children():
		_collect_mm(ch, out)

func _hide_ui() -> void:
	var menu: Variant = _main.get("_menu")
	if menu != null:
		if menu.has_method("instant_finish"):
			menu.call("instant_finish")
		menu.set("menu_visible", false)
		if menu is CanvasLayer:
			(menu as CanvasLayer).visible = false
	for key in ["_hud", "_ui_layer"]:
		var nd: Variant = _main.get(key)
		if nd is CanvasLayer:
			(nd as CanvasLayer).visible = false
	_hide_layers(_main)
	_hide_layers(root)

func _hide_layers(nd: Node) -> void:
	for c in nd.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
		_hide_layers(c)

# 近段遮草：真实 P2-B 会在硬质结构区过滤散布实例；此处只对视口关注区做同样的"实例置零"，
# 且不改任何生成函数/随机数（与 world.gd 的接受/拒绝逻辑无关）。
func _mask_scatter() -> void:
	var mm_nodes: Array = []
	_collect_mm(_main, mm_nodes)
	_hide_rect = Rect2(RECT_MIN - Vector2(0.10, 0.10), (RECT_MAX - RECT_MIN) + Vector2(0.20, 0.20))
	for mm in mm_nodes:
		var mi := mm as MultiMeshInstance3D
		if mi == null or mi.multimesh == null:
			continue
		var nm := String(mi.name)
		var is_veg := nm.begins_with("Grass") or nm.begins_with("Clover") or nm.begins_with("Weed") \
			or nm.begins_with("Flower") or nm.begins_with("WinterBloom") or nm.begins_with("Bush") \
			or nm.begins_with("Stems") or nm.begins_with("LeafCards")
		if not is_veg:
			continue
		var mtx := mi.multimesh
		for i in range(mtx.instance_count):
			var xf := mtx.get_instance_transform(i)
			var gp: Vector3 = mi.global_transform * xf.origin
			var lp := _w2l(gp.x, gp.z)
			if not _hide_rect.has_point(lp):
				continue
			xf.basis = Basis().scaled(Vector3.ZERO)
			xf.origin = Vector3(0.0, -200.0, 0.0)
			mtx.set_instance_transform(i, xf)
			_masked += 1
	print("[W20] scatter masked in view rect: %d" % _masked)

func _commit(st: SurfaceTool, nm: String, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_layout.add_child(mi)
	return mi

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ca: Color, cb: Color, cc: Color, cd: Color, wa: Vector2, wb: Vector2, wc: Vector2, wd: Vector2) -> void:
	var n := (b - a).cross(c - a)
	var up := Vector3.UP
	var v := [a, b, c, d]
	var col := [ca, cb, cc, cd]
	var uv := [wa, wb, wc, wd]
	if n.dot(up) < 0.0:
		v = [a, d, c, b]
		col = [ca, cd, cc, cb]
		uv = [wa, wd, wc, wb]
	for k in [0, 1, 2, 0, 2, 3]:
		st.set_color(col[k])
		st.set_uv(uv[k])
		st.add_vertex(v[k])

# 台面近段顶面：按真实地形高度场取样，pad=max(HL+0.02, 7.53)
func _build_pad_skin() -> void:
	var nx := int(ceil((RECT_MAX.x - RECT_MIN.x) / CELL))
	var nz := int(ceil((RECT_MAX.y - RECT_MIN.y) / CELL))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols: Array = []
	var ys: Array = []
	for iz in range(nz + 1):
		for ix in range(nx + 1):
			var lp := Vector2(RECT_MIN.x + float(ix) * CELL, RECT_MIN.y + float(iz) * CELL)
			ys.append(_pad_y(lp))
			var w := _l2w(lp.x, lp.y)
			cols.append(_grass_color(w))
	var tris := 0
	for iz in range(nz):
		for ix in range(nx):
			var p00 := Vector2(RECT_MIN.x + float(ix) * CELL, RECT_MIN.y + float(iz) * CELL)
			var p10 := p00 + Vector2(CELL, 0.0)
			var p11 := p00 + Vector2(CELL, CELL)
			var p01 := p00 + Vector2(0.0, CELL)
			if not (_pt_in_poly(p00, _poly) and _pt_in_poly(p10, _poly) and _pt_in_poly(p11, _poly) and _pt_in_poly(p01, _poly)):
				continue
			var i00 := iz * (nx + 1) + ix
			var i10 := i00 + 1
			var i01 := i00 + (nx + 1)
			var i11 := i01 + 1
			var a := Vector3(p00.x, ys[i00], p00.y)
			var b := Vector3(p10.x, ys[i10], p10.y)
			var c := Vector3(p11.x, ys[i11], p11.y)
			var d := Vector3(p01.x, ys[i01], p01.y)
			_quad(st, a, b, c, d, cols[i00], cols[i10], cols[i11], cols[i01], p00, p10, p11, p01)
			tris += 2
	var mat: Material = M.terrain_material()
	_commit(st, "W20_PadSkin", mat)
	print("[W20] pad skin tris=%d poly_pts=%d" % [tris, _poly.size()])

# 台面边界：沿多边形边界做竖直收边（高度=pad−原地形，本关注区仅 0.02m），
# 让台面边缘在近景里可读；不做竖直挡墙、不做阶梯。
func _build_pad_edge() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := _poly.size()
	var made := 0
	var soil := M.C_SOIL
	for i in range(n):
		var a: Vector2 = _poly[i]
		var b: Vector2 = _poly[(i + 1) % n]
		var L := a.distance_to(b)
		var k := maxi(1, int(ceil(L / 0.05)))
		for j in range(k):
			var p := a.lerp(b, float(j) / float(k))
			var q := a.lerp(b, float(j + 1) / float(k))
			if not (_hide_rect.has_point(p) and _hide_rect.has_point(q)):
				continue
			var yp := _pad_y(p)
			var yq := _pad_y(q)
			var gp := _ground(p)
			var gq := _ground(q)
			# 只用竖直面补齐 pad 与地形的高差（0.02 量级），不制造额外构件
			var pa := Vector3(p.x, yp, p.y)
			var pb := Vector3(q.x, yq, q.y)
			var pc := Vector3(q.x, gq, q.y)
			var pd := Vector3(p.x, gp, p.y)
			var c1 := soil.lerp(M.C_GRASS_DARK, 0.35)
			_quad(st, pa, pb, pc, pd, c1, c1, c1, c1, p, q, q, p)
			made += 1
	_commit(st, "W20_PadEdge", M.toon_material(M.C_SOIL, {"bands": 3.0, "soft": 0.5, "rim": 0.06}))
	print("[W20] pad edge quads=%d" % made)

func _setup_shot_viewport() -> void:
	_sv = SubViewport.new()
	_sv.size = Vector2i(SHOT_W, SHOT_H)
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sv.msaa_3d = Viewport.MSAA_2X
	root.add_child(_sv)
	_sv.world_3d = root.world_3d
	_shot_cam = Camera3D.new()
	_shot_cam.near = 0.05
	_shot_cam.far = 1200.0
	_sv.add_child(_shot_cam)
	_shot_cam.current = true

func _pose(plx: float, plz: float, py: float, tlx: float, tlz: float, ty: float, fov: float) -> void:
	var pp := _l2w(plx, plz)
	var tt := _l2w(tlx, tlz)
	_main.call("_pose_look", Vector3(pp.x, py, pp.y), Vector3(tt.x, ty, tt.y), fov)
	await process_frame

func _shot(tag: String) -> void:
	var cp := _cam.global_position
	var gnd := IsleWorld.surface_y(cp.x, cp.z)
	_check("cam_above_ground_" + tag, cp.y - gnd >= 1.19, "cam=(%.2f,%.2f,%.2f) ground=%.2f dy=%.2f (engine clamps to terrain+1.2 via _min_camera_y)" % [cp.x, cp.y, cp.z, gnd, cp.y - gnd])
	_shot_cam.global_transform = _cam.global_transform
	_shot_cam.fov = _cam.fov
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = _sv.get_texture().get_image() if (_sv != null and _sv.get_texture() != null) else null
	if img == null:
		_check("shot_" + tag, false, "viewport image null")
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	var p := out_dir + "/" + tag_prefix + tag + ".png"
	var err := img.save_png(p)
	_check("shot_" + tag, err == OK, "%dx%d err=%d -> %s" % [img.get_width(), img.get_height(), err, p])
	if err == OK:
		_shots.append(p)

func _run() -> void:
	_parse_args()
	_poly = POLY_TONGUE if tongue else POLY_BASE
	var sid := "with_tongue" if tongue else "no_tongue"
	print("[W20] variant=%s out=%s" % [sid, out_dir])

	var ps: PackedScene = load("res://isle.tscn")
	if ps == null:
		print("[W20] FAIL scene load")
		quit(1)
		return
	_main = ps.instantiate()
	root.add_child(_main)
	await process_frame
	await process_frame
	var S := load("res://scripts/isle_settings.gd")
	if S != null:
		_main.set("_settings", S.defaults())
		_main.call("_apply_user_settings", false)
	for i in range(3):
		await process_frame
	_main.set("_settings_save_delay", -1.0)
	_main.set("_mode", 1)
	_main.set("_started", true)
	_main.set("_paused", false)
	_main.set("_blending", "")
	_main.set("_auto_orbit", false)
	_cam = _main.get("_cam")
	_hide_ui()
	await process_frame
	_setup_shot_viewport()
	_main.call("_set_time_of_day", 12 * 60 + 20)
	var weather: Variant = _main.get("_weather")
	if weather != null and weather.has_method("set_manual_type"):
		weather.set_manual_type("clear")
	_main.call("_update_weather", 0.0, true)

	_layout = Node3D.new()
	_layout.name = "W20_Preview"
	_layout.position = Vector3(M.HOUSE_X, 0.0, M.HOUSE_Z)
	_layout.rotation.y = M.HOUSE_YAW
	_main.add_child(_layout)
	_mask_scatter()
	_build_pad_skin()
	_build_pad_edge()

	# 三个机位：都在最下级踏步左端的近景，低视角、看地面关系
	await _pose(-3.30, 6.55, 8.31, -1.18, 5.35, 7.83, 52.0)
	await create_timer(0.5).timeout
	await _shot("A_wide")
	await _pose(-2.35, 6.30, 8.24, -1.25, 5.42, 7.82, 55.0)
	await create_timer(0.5).timeout
	await _shot("B_close")
	await _pose(-2.10, 6.10, 8.97, -1.28, 5.42, 7.80, 55.0)
	await create_timer(0.5).timeout
	await _shot("C_above")

	# 几何事实输出（供报告引用；引擎内真实取样）
	var tongue_rect := Rect2(Vector2(-1.45, 5.15), Vector2(0.35, 0.45))
	var samples: Array = []
	for lp in [Vector2(-1.30, 5.20), Vector2(-1.30, 5.40), Vector2(-1.30, 5.55), Vector2(-1.60, 5.40), Vector2(-1.05, 5.50), Vector2(-1.30, 5.70)]:
		var ground := _ground(lp)
		var w := _l2w(lp.x, lp.y)
		samples.append({"local": [lp.x, lp.y], "world": [w.x, w.y], "ground": ground,
			"pad": _pad_y(lp), "fill": _pad_y(lp) - ground, "in_poly": _pt_in_poly(lp, _poly)})
	var facts := {
		"variant": sid,
		"tongue": tongue,
		"polygon_local": _poly,
		"tongue_rect_local": [-1.45, 5.15, -1.10, 5.60],
		"tongue_area_m2": 0.1575,
		"step_facts": {"z_top": 4.70, "run": 0.30, "rise": 0.14, "n": 3,
			"treads_local_z": [[4.70, 5.00], [5.00, 5.30], [5.30, 5.60]],
			"tread_widths": [2.60, 2.40, 2.20],
			"tread_top_local": [0.28, 0.14, 0.00],
			"tread_top_world": [8.2256, 8.0856, 7.9456],
			"note": "bottom_y = ground(local 0,5.65)+0.02；末级踏面顶=原地面≈7.9456"},
		"samples": samples,
		"masked_scatter": _masked,
		"cameras": [
			{"tag": "A_wide", "from_local": [-3.30, 6.55], "from_y": 8.06, "target_local": [-1.18, 5.35], "target_y": 7.83, "fov": 52.0},
			{"tag": "B_close", "from_local": [-2.35, 6.30], "from_y": 7.99, "target_local": [-1.25, 5.42], "target_y": 7.82, "fov": 55.0},
			{"tag": "C_above", "from_local": [-2.10, 6.10], "from_y": 8.72, "target_local": [-1.28, 5.42], "target_y": 7.80, "fov": 55.0}],
		"shots": _shots,
		"checks": _checks,
		"disclaimer": "临时预览几何：只构建门前土地近段顶面+2cm 收边；未构建围栏/土床/小径；材质取 world.gd 同一草地着色逻辑但非正式构建产物。"
	}
	var fa := FileAccess.open(out_dir + "/w20_preview_" + sid + ".json", FileAccess.WRITE)
	if fa != null:
		fa.store_string(JSON.stringify(facts, "  "))
		fa.close()
	var failn := 0
	for c in _checks:
		if not bool(c["ok"]):
			failn += 1
	print("[W20] SUMMARY variant=%s checks=%d fail=%d shots=%d masked=%d" % [sid, _checks.size(), failn, _shots.size(), _masked])
	print("[W20] RESULT %s" % ("PASS" if failn == 0 else "FAIL"))
	quit(0 if failn == 0 else 1)
