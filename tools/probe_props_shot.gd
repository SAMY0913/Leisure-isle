extends SceneTree
## P7-V3 家具库窗口截图探针（task-4 / G 阶段）
## 木质展台 + 后墙 + 昼光（toon 全局 uniform）+ 透视/正交/分排/细节机位，
## 把 isle_house_props.gd 的 25 类家具摆成 3 排，截图到 开发产物/p7v3/shots/。
## 运行（必须窗口，串行 GPU 锁；不要 --headless）：
##   "D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe" --path "D:/休闲小岛幻境/游戏工程" ##     --resolution 1600x900 --script res://tools/probe_props_shot.gd -- --out=D:/休闲小岛幻境/开发产物/p7v3/shots

const M := preload("res://scripts/isle_math.gd")
const PROPS := preload("res://scripts/isle_house_props.gd")

const OUT_DEFAULT := "D:/休闲小岛幻境/开发产物/p7v3/shots"
const WALL_FACE_Z := -4.43   # 后墙前表面（家具库墙挂件原点贴近此平面）

var out_dir := OUT_DEFAULT
var fails := 0
var shots := 0
var stage: Node3D = null
var labels: Node3D = null
var cam: Camera3D = null
var bg := Color(0.62, 0.80, 0.88)
var sun_dir_world := Vector3(0.42, 0.80, 0.34).normalized()
var placed: Array = []          # [{kind,pos,footprint,height}]
var built_kinds: Dictionary = {}

func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("[PROPS-SHOT] SKIP: 窗口截图探针需要真实窗口（不要 --headless）")
		quit(1)
		return
	print("=== probe_props_shot: P7-V3 家具库展台截图 ===")
	_parse_args()
	DirAccess.make_dir_recursive_absolute(out_dir)
	await process_frame
	DisplayServer.window_set_size(Vector2i(1600, 900))
	get_root().size = Vector2i(1600, 900)
	_setup_globals()
	_build_world()
	await process_frame
	cam = Camera3D.new()
	cam.name = "ShotCam"
	cam.near = 0.1
	cam.far = 250.0
	get_root().add_child(cam)
	cam.current = true
	await process_frame
	await process_frame
	await _shots()
	print("[PROPS-SHOT] 摆放 %d 件 / 覆盖 kind %d/%d" % [placed.size(), built_kinds.size(), PROPS.kinds().size()])
	print("[PROPS-SHOT] RESULT fail=%d shots=%d out=%s" % [fails, shots, out_dir])
	quit(0 if fails == 0 else 1)

func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--out="):
			out_dir = s.substr(6)

# ============================================================
# 全局 toon uniform（与 scripts/main.gd:327-371 注册名/类型一致）
# ============================================================
func _setup_globals() -> void:
	var color_names := ["g_sun_color", "g_moon_color", "g_ambient_sky", "g_ambient_ground",
		"g_fog_color", "g_outline_color", "g_beam_color", "g_spot_color"]
	for n in color_names:
		RenderingServer.global_shader_parameter_add(String(n), RenderingServer.GLOBAL_VAR_TYPE_COLOR, Color.WHITE)
	for n in ["g_sun_dir_view", "g_moon_dir_view", "g_beam_origin", "g_beam_dir", "g_spot_origin", "g_spot_dir"]:
		RenderingServer.global_shader_parameter_add(String(n), RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3.ZERO)
	for n in ["g_beam_params", "g_spot_params"]:
		RenderingServer.global_shader_parameter_add(String(n), RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4.ZERO)
	for n in ["g_fog_near", "g_fog_far", "g_wind_time", "g_light_count", "g_occ_count"]:
		RenderingServer.global_shader_parameter_add(String(n), RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)
	for i in range(12):
		RenderingServer.global_shader_parameter_add("g_l%d_pos" % i, RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4(0.0, -999.0, 0.0, 1.0))
		RenderingServer.global_shader_parameter_add("g_l%d_col" % i, RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4.ZERO)
	for i in range(4):
		RenderingServer.global_shader_parameter_add("g_occ_c%d" % i, RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3.ZERO)
		RenderingServer.global_shader_parameter_add("g_occ_h%d" % i, RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3.ZERO)
		RenderingServer.global_shader_parameter_add("g_occ_y%d" % i, RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)

	var lin := func(c: Color) -> Color: return c.srgb_to_linear()
	RenderingServer.global_shader_parameter_set("g_sun_color", lin.call(Color(1.0, 0.91, 0.78)) * 0.92)
	RenderingServer.global_shader_parameter_set("g_moon_color", lin.call(Color(0.56, 0.68, 0.91)) * 0.08)
	RenderingServer.global_shader_parameter_set("g_ambient_sky", lin.call(Color(0.65, 0.82, 0.90)) * 0.88)
	RenderingServer.global_shader_parameter_set("g_ambient_ground", lin.call(Color(0.40, 0.45, 0.31)) * 0.88)
	RenderingServer.global_shader_parameter_set("g_fog_color", lin.call(bg))
	RenderingServer.global_shader_parameter_set("g_fog_near", 90.0)
	RenderingServer.global_shader_parameter_set("g_fog_far", 400.0)
	RenderingServer.global_shader_parameter_set("g_wind_time", 0.0)
	RenderingServer.global_shader_parameter_set("g_outline_color", lin.call(Color(0.10, 0.13, 0.19)))
	RenderingServer.global_shader_parameter_set("g_light_count", 0.0)
	RenderingServer.global_shader_parameter_set("g_occ_count", 0.0)
	RenderingServer.global_shader_parameter_set("g_moon_dir_view", Vector3(0.0, 0.0, -1.0))
	_update_sun_view()

func _update_sun_view() -> void:
	if cam == null:
		return
	RenderingServer.global_shader_parameter_set("g_sun_dir_view", (cam.global_transform.basis.inverse() * sun_dir_world).normalized())

# ============================================================
# 展台世界
# ============================================================
func _build_world() -> void:
	stage = Node3D.new()
	stage.name = "PropsStage"
	get_root().add_child(stage)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = bg
	e.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.environment = e
	stage.add_child(env)

	# 草地与木展台（展台面 y=0，草地在 -0.02）
	M.box(stage, Vector3(64, 0.40, 64), Vector3(0, -0.22, 0), M.C_GRASS, 0.0, {})
	M.box(stage, Vector3(16.4, 0.40, 9.0), Vector3(0, -0.20, -0.6), M.C_WOOD_LIGHT, 0.0, {"outline": 0.02})
	# 台面压边 + 板缝（细深色条，增强木地板观感）
	M.box(stage, Vector3(16.5, 0.06, 0.10), Vector3(0, -0.01, 3.92), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
	M.box(stage, Vector3(16.5, 0.06, 0.10), Vector3(0, -0.01, -5.02), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
	# 展台前裙板（正交前视时遮住地平线以下，画面底部不露背景色）
	M.box(stage, Vector3(16.5, 4.0, 0.14), Vector3(0, -2.0, 3.94), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
	for i in range(11):
		var z := -4.6 + float(i) * 0.78
		M.box(stage, Vector3(15.9, 0.006, 0.018), Vector3(0, 0.004, z), M.C_WOOD_DARK, 0.0, {})
	# 后墙 + 踢脚线 + 顶线
	M.box(stage, Vector3(16.4, 3.7, 0.22), Vector3(0, 1.85, -4.55), M.C_WALL, 0.0, {"outline": 0.02})
	M.box(stage, Vector3(16.4, 0.14, 0.07), Vector3(0, 0.07, -4.41), M.C_WOOD, 0.0, {"outline": 0.02})
	M.box(stage, Vector3(16.4, 0.12, 0.09), Vector3(0, 3.62, -4.40), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
	# 后墙装饰（窗帘后面的一扇“窗”，深蓝自发光玻璃 + 木框）
	M.box(stage, Vector3(1.18, 1.52, 0.02), Vector3(5.6, 1.62, -4.42), Color("7fb6d4"), 0.0, {"outline": 0.02, "self_lit": true, "glow": 0.45})
	M.box(stage, Vector3(1.30, 0.07, 0.06), Vector3(5.6, 2.42, -4.40), M.C_WOOD, 0.0, {"outline": 0.02})
	M.box(stage, Vector3(1.30, 0.07, 0.06), Vector3(5.6, 0.82, -4.40), M.C_WOOD, 0.0, {"outline": 0.02})
	M.box(stage, Vector3(0.07, 1.67, 0.06), Vector3(4.96, 1.62, -4.40), M.C_WOOD, 0.0, {"outline": 0.02})
	M.box(stage, Vector3(0.07, 1.67, 0.06), Vector3(6.24, 1.62, -4.40), M.C_WOOD, 0.0, {"outline": 0.02})
	M.box(stage, Vector3(0.05, 1.52, 0.05), Vector3(5.6, 1.62, -4.39), M.C_WOOD, 0.0, {"outline": 0.02})

	labels = Node3D.new()
	labels.name = "Labels"
	stage.add_child(labels)
	_place_props()

func _add(kind: String, x: float, z: float, yaw: float = 0.0, y: float = 0.0, label: bool = true) -> void:
	var r: Dictionary = PROPS.build(stage, kind, Vector3(x, y, z), yaw)
	if r.is_empty():
		fails += 1
		print("[FAIL] build ", kind)
		return
	placed.append({"kind": kind, "pos": Vector3(x, y, z), "footprint": r["footprint"], "height": r["height"]})
	built_kinds[kind] = true
	if label and labels != null:
		var lab := Label3D.new()
		lab.text = kind
		lab.font_size = 40
		lab.pixel_size = 0.0028
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.modulate = Color(0.10, 0.12, 0.16)
		lab.outline_size = 0
		lab.no_depth_test = false
		var ly: float = y + float(r["height"]) + 0.10
		if PROPS.is_wall_mounted(kind):
			ly = y + float(r["height"]) * 0.5 + 0.34
		lab.position = Vector3(x, ly, z)
		labels.add_child(lab)

func _place_props() -> void:
	# ---- 第一排（前端，z≈+1.5）：客厅组 / 餐组 / 玄关组 ----
	_add("rug", -3.7, 1.6)
	_add("sofa", -5.7, 1.6, 0.0)
	_add("floor_lamp", -7.05, 2.65)
	_add("coffee_table", -3.7, 1.6, 0.0, 0.026)
	_add("armchair", -1.7, 1.7, 0.40)
	_add("dining_table", 1.0, 1.5)
	_add("chair", 1.0, 0.745, 0.0, 0.0, false)          # 餐桌远侧（面向 +Z 桌子）
	_add("chair", 1.0, 2.255, PI, 0.0, false)            # 近侧
	_add("chair", -0.08, 1.5, PI * 0.5, 0.0, false)      # 西侧
	_add("chair", 2.08, 1.5, -PI * 0.5, 0.0, false)      # 东侧
	_add("sideboard", 4.7, 1.6)
	_add("shoe_bench", 6.15, 2.55, 0.20)
	_add("doormat", 7.35, 1.05)
	# ---- 第二排（中，z≈-1.1）：柜类 / 床 / 书桌 ----
	_add("bookshelf", -7.10, -1.10)
	_add("tall_cupboard", -5.75, -1.10)
	_add("wardrobe", -4.15, -1.10)
	_add("bed", -2.00, -2.00)
	_add("nightstand", -0.85, -2.70)
	_add("desk", 1.10, -1.70)
	_add("chair", 1.10, -0.45, PI, 0.0, false)
	_add("reading_chair", 3.35, -1.95, -0.60)
	_add("side_table", 4.45, -1.95)
	_add("table_lamp", 4.45, -1.95, 0.0, 0.55)
	_add("plant_pot", 5.55, -2.00)
	_add("firewood_basket", 6.65, -2.00)
	_add("chair", 7.45, -1.00, 0.35)
	# ---- 第三排（后，z≈-3.4）与后墙墙挂件 ----
	_add("curtain", 5.60, WALL_FACE_Z + 0.11, 0.0, 2.35)
	_add("picture_frame", 3.80, WALL_FACE_Z + 0.01, 0.0, 1.62)
	_add("wall_clock", 2.55, WALL_FACE_Z + 0.01, 0.0, 2.10)
	_add("coat_rack", 1.15, WALL_FACE_Z + 0.01, 0.0, 1.45)

# ============================================================
# 机位与截图
# ============================================================
func _shots() -> void:
	var total := PROPS.kinds().size()
	var missing: Array = []
	for k in PROPS.kinds():
		if not built_kinds.has(String(k)):
			missing.append(String(k))
	if missing.is_empty():
		print("[PASS] 25 类全部上展台（摆放 %d 件）" % placed.size())
	else:
		fails += 1
		print("[FAIL] 未上展台 kind：", str(missing))
	var list_names: Array = []
	for p in placed:
		list_names.append("%s@(%.2f,%.2f)" % [p["kind"], p["pos"].x, p["pos"].z])
	print("[INFO] 摆放：", ", ".join(list_names))

	# 总览 / 正交前视带品名标签
	labels.visible = true
	await _shot("props_overview", Vector3(0.4, 7.0, 12.8), Vector3(0.2, 0.85, -1.4), 50.0, false, 11.5)
	await _shot("props_front", Vector3(0.0, 2.6, 14.0), Vector3(0.0, 1.35, -1.4), 45.0, true, 9.3)
	# 分排近景 / 细节（隐藏标签看造型）
	labels.visible = false
	await _shot("props_row1", Vector3(0.6, 5.6, 10.0), Vector3(0.1, 0.20, 1.6), 52.0, false, 0.0)
	await _shot("props_row2", Vector3(0.4, 5.6, 6.2), Vector3(0.2, 0.20, -1.4), 52.0, false, 0.0)
	await _shot("props_row3", Vector3(2.4, 2.6, 3.6), Vector3(3.6, 1.20, -3.4), 50.0, false, 0.0)
	await _shot("props_detail_sofa", Vector3(-4.0, 1.7, 5.2), Vector3(-3.9, 0.50, 1.5), 38.0, false, 0.0)
	await _shot("props_detail_dining", Vector3(3.7, 1.9, 5.4), Vector3(1.4, 0.55, 1.5), 38.0, false, 0.0)
	await _shot("props_detail_bed", Vector3(-2.2, 1.8, 2.7), Vector3(-2.0, 0.55, -2.0), 40.0, false, 0.0)
	await _shot("props_detail_cabinets", Vector3(-5.4, 1.8, 2.9), Vector3(-5.9, 0.90, -1.1), 40.0, false, 0.0)
	await _shot("props_detail_wall", Vector3(-1.0, 2.2, 2.0), Vector3(4.2, 1.60, -4.4), 45.0, false, 0.0)

func _shot(shot_name: String, pos: Vector3, target: Vector3, fov: float, ortho: bool, ortho_size: float) -> void:
	cam.global_position = pos
	cam.look_at(target, Vector3.UP)
	cam.fov = fov
	if ortho:
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = ortho_size
	else:
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_update_sun_view()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_root().get_texture().get_image()
	var path := out_dir.path_join(shot_name + ".png")
	var err := img.save_png(path)
	shots += 1
	if err != OK:
		fails += 1
		print("[FAIL] 保存失败 ", path, " err=", err)
		return
	var st := _stats(img)
	var ok: bool = st["mean"] > 0.18 and st["ratio"] > 0.08 and img.get_width() >= 1200
	if not ok:
		fails += 1
	print("[SHOT] %-22s %dx%d mean=%.3f 非背景=%.1f%% %s" % [shot_name, img.get_width(), img.get_height(), st["mean"], float(st["ratio"]) * 100.0, ("OK" if ok else "FAIL")])

## 亮度均值 + 非背景像素占比（以左上角像素为背景基准）。
func _stats(img: Image) -> Dictionary:
	var w := img.get_width()
	var h := img.get_height()
	var bg_px := img.get_pixel(4, 4)
	var step := 8
	var n := 0
	var lum := 0.0
	var diff := 0
	for y in range(0, h, step):
		for x in range(0, w, step):
			var c := img.get_pixel(x, y)
			lum += c.get_luminance()
			n += 1
			if absf(c.r - bg_px.r) + absf(c.g - bg_px.g) + absf(c.b - bg_px.b) > 0.06:
				diff += 1
	return {"mean": lum / float(maxi(n, 1)), "ratio": float(diff) / float(maxi(n, 1))}
