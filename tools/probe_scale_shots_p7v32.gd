extends SceneTree
## P7-V3.2 T5 验收截图探针（accept shots）——16 张 1600x900 真实窗口渲染
##
## 用途：把 scripts/isle_scale_figure.gd 的 1.50 m 参照人形真实放进场景，按任务书第十三节
## 的验收机位拍照，覆盖 房屋/室内家具/楼梯/小船码头/灯塔/猫鸥/俯瞰/灯塔门/标尺 共 16 张。
## 每张图都带可比较参照物（1.50 m 人形或规范表已知尺寸物），并输出相机位置/朝向/fov 日志。
##
## 运行（必须真实窗口 + 1600x900；headless 会直接 quit(1)）：
##   & "D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64.exe" --path "D:/休闲小岛幻境/游戏工程" ^
##       --resolution 1600x900 --script res://tools/probe_scale_shots_p7v32.gd ^
##       -- --scale-debug --out="D:/休闲小岛幻境/开发产物/p7v32/shots/"
## 参数：--out=<dir> --only=s01,s03 --stage=house|interior|world|all --time=740 --quality=2 --list
## 产物：<out>/s01_house_front.png … s16_overlay_ruler.png、<out>/manifest.md、<out>/scale_shots_manifest.json
## 清单含 commit/生成时间/引擎/GPU/画质/seed 与人形回读（_git_commit 动态读取，失败记 unknown）。
## 日志：stdout（由调用方重定向到 开发产物/p7v32/logs/accept_shots.log）

const Figure := preload("res://scripts/isle_scale_figure.gd")
const M := preload("res://scripts/isle_math.gd")
const Spec := preload("res://scripts/isle_scale_spec.gd")

const OUT_DEFAULT := "D:/休闲小岛幻境/开发产物/p7v32/shots/"
const SHOT_W := 1600
const SHOT_H := 900
const T_DAY := 740.0      # 12:20 固定太阳时间（与 --shots 正午档一致）
const QUALITY := 2        # 高·精致（默认档）
const SEED_VAL := 20251021
const FIG_H := 1.50

var _main: Node = null
var _cam: Camera3D = null
var _cottage: Dictionary = {}
var _cr: Node3D = null
var _holder: Node3D = null
var _overlay: Node3D = null
var _world: Dictionary = {}
var _n := Vector3(0.0, 0.0, 1.0)
var _side := Vector3(1.0, 0.0, 0.0)

var _out := OUT_DEFAULT
var _only: Array = []
var _stage := "all"
var _time_used := T_DAY
var _quality_used := QUALITY
var _list_only := false

var _manifest: Array = []
var _figures: Array = []
var _fig_nodes: Dictionary = {}
var _fail := 0

func _initialize() -> void:
	_parse_args()
	if _list_only:
		_print_shot_table()
		quit(0)
		return
	if DisplayServer.get_name() == "headless":
		print("[P7V32S] SKIP headless：验收截图必须在真实窗口渲染（窗口版 Godot .exe）")
		quit(1)
		return
	_run()

func _parse_args() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a := String(args[i])
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a == "--out" and i + 1 < args.size():
			_out = String(args[i + 1])
			i += 1
		elif a.begins_with("--only="):
			for s in a.substr(7).split(","):
				var t := String(s).strip_edges()
				if t != "":
					_only.append(t)
		elif a.begins_with("--stage="):
			_stage = a.substr(8)
		elif a.begins_with("--time="):
			_time_used = float(a.substr(7))
		elif a.begins_with("--quality="):
			_quality_used = int(a.substr(10))
		elif a == "--list":
			_list_only = true
		i += 1
	if not _out.ends_with("/"):
		_out += "/"

# ============================================================ 场景 / 工具 ====
func _run() -> void:
	print("=== P7-V3.2 T5 ACCEPT SHOTS START ===")
	print("[P7V32S] out=", _out, " size=", SHOT_W, "x", SHOT_H, " seed=", SEED_VAL,
		" time=", _time_used, " quality=", _quality_used, " stage=", _stage,
		" only=", str(_only))
	seed(SEED_VAL)
	var packed: PackedScene = load("res://isle.tscn") as PackedScene
	if packed == null:
		print("[P7V32S] FAIL 无法加载 res://isle.tscn")
		quit(1)
		return
	_main = packed.instantiate()
	get_root().add_child(_main)
	await process_frame
	await process_frame
	var menu: Node = _main.get("_menu") as Node
	if menu != null and menu.has_method("instant_finish"):
		menu.call("instant_finish")
	_main.set("_mode", 1)            # Mode.PLAYING
	_main.set("_time_source", "sim")
	_main.set("_realtime", false)
	_main.set("_started", true)
	_main.set("_paused", true)       # 冻结模拟：时间/船/鸟/猫/风车全部定住，保证可复现
	_main.set("_auto_orbit", false)
	_main.set("_blending", "")
	_force_windowed()
	await _settle(12)
	_force_windowed()
	await _settle(4)
	_main.call("_apply_quality", _quality_used)
	_set_time(_time_used)
	await _settle(4)
	var hud: Node = _main.get("_hud") as Node
	if hud != null and hud.has_method("set_hud_visible"):
		hud.call("set_hud_visible", false, false)
	var got := DisplayServer.window_get_size()
	if got.x != SHOT_W or got.y != SHOT_H:
		print("[P7V32S] WARN 首次窗口尺寸 ", got.x, "x", got.y, "，强制 windowed+1600x900 后重试")
		_force_windowed()
		await _settle(6)
		got = DisplayServer.window_get_size()
	var vp := _main.get_viewport()
	print("[P7V32S] window=", got.x, "x", got.y, " viewport=", vp.get_visible_rect().size,
		" quality_after=", _main.get("_quality"), " paused=", _main.get("_paused"))
	if got.x != SHOT_W or got.y != SHOT_H:
		print("[P7V32S] WARN 窗口尺寸不是 1600x900（实际 ", got.x, "x", got.y, "）")
		quit(1)
		return

	_cam = _main.get("_cam") as Camera3D
	_cottage = _main.get("_cottage") as Dictionary
	_world = _main.get("_world") as Dictionary
	_cr = _cottage.get("root") as Node3D
	if _cam == null or _cr == null:
		print("[P7V32S] FAIL 场景引用缺失 cam=", _cam, " cottage_root=", _cr)
		quit(1)
		return
	_cr.global_transform = _cr.global_transform  # no-op，仅确保世界变换已刷新
	_n = (_cr.global_transform.basis * Vector3(0.0, 0.0, 1.0)).normalized()
	_side = (_cr.global_transform.basis * Vector3(1.0, 0.0, 0.0)).normalized()
	_holder = Node3D.new()
	_holder.name = "P7V32ScaleFigures"
	_main.add_child(_holder)
	print("[P7V32S] HOUSE world=", _f3(_cr.global_position), " yaw_deg=", "%.1f" % rad_to_deg(_cr.global_rotation.y),
		" n=", _f3(_n), " side=", _f3(_side))

	# 开发者标尺：--scale-debug 时 main 已挂 ScaleDebugOverlay；这里先隐藏，s16 再打开
	_overlay = _main.get_node_or_null("ScaleDebugOverlay") as Node3D
	if _overlay == null:
		var OV := load("res://scripts/scale_debug_overlay.gd")
		if OV != null:
			_overlay = OV.new()
			_overlay.name = "ScaleDebugOverlay"
			_main.add_child(_overlay)
			await _settle(2)
	if _overlay != null:
		if _overlay.has_method("set_debug_visible"):
			_overlay.call("set_debug_visible", false)
		print("[P7V32S] ScaleDebugOverlay 已挂载并在 s01–s15 隐藏（s16 打开）")
	else:
		print("[P7V32S] WARN ScaleDebugOverlay 不可用，s16 将缺失标尺")

	# ---- 参照人形（真实放置，每个都回读 1.500 m 世界高度）----
	# 1) 房屋正面：地面右前侧（避开台阶与门廊）
	var lf := Vector3(-2.90, 0.0, 6.20)
	var wf := _ground(lf)
	_fig(wf, _face_yaw(wf, _local(Vector3(0.0, 1.4, 9.0))), "fig_front")
	# 2) 门口：门廊台面（台面高 0.42）上，面向相机
	var wd := _local(Vector3(0.60, Spec.PORCH_DECK_Y, 3.72))
	_fig(wd, _face_yaw(wd, _local(Vector3(0.20, 1.95, 8.00))), "fig_door")
	# 3) 一层室内：房间中部，面向室内全景机位
	var wi := _local(Vector3(-0.20, Spec.HOUSE_FY, 1.85))
	_fig(wi, _face_yaw(wi, _local(Vector3(3.15, 2.20, 2.30))), "fig_interior")
	# 4) 楼梯上：Flight A 第 4 级踏面（顶面 fy+4*rise），面向相机
	var riser := Spec.STAIR_RISE
	var wt := _local(Vector3(3.065, Spec.HOUSE_FY + 4.0 * riser, -1.01))
	_fig(wt, _face_yaw(wt, _local(Vector3(3.06, 2.30, 1.10))), "fig_stairs")

	await _shot_house()
	await _shot_interior()
	await _shot_world()
	await _shot_light_and_overlay()

	_write_manifest()
	print("[P7V32S] RESULT shots=%d figures=%d fail=%d out=%s" % [_manifest.size(), _figures.size(), _fail, _out])
	if _fail == 0:
		print("[P7V32S] PASS 全部 16 张验收图已生成（1600x900，参照人形 1.500 m）")
		quit(0)
	else:
		print("[P7V32S] FAIL fail=", _fail)
		quit(1)

# -------- 房屋组：s01/s02 --------
func _shot_house() -> void:
	var t1 := _local(Vector3(0.0, 2.90, 4.50))
	await _shot("s01", "s01_house_front", "人形与房屋正面：1.50m 人形 vs 外廓 7.6x6.2 / 墙高3.18 / 屋脊6.20",
		t1 + _n * 15.0 + _side * 1.2 + Vector3(0.0, 3.0, 0.0), t1, 50.0,
		"参照人形 fig_front(1.500m) + 房屋外廓 7.6x6.2 / 屋脊 6.20m", false, ["fig_front"])
	var t2 := _local(Vector3(0.10, 1.60, 3.05))
	await _shot("s02", "s02_door", "人形站在门口（门洞对比）：人形 1.50m vs 门洞净高 1.94 / 净宽 1.14",
		_local(Vector3(0.20, 1.95, 8.00)), t2, 50.0,
		"参照人形 fig_door(1.500m，脚底=门廊台面 0.42m) + 门洞净高 1.94m / 净宽 1.14m", false, ["fig_door"])

# -------- 室内组：s03..s10 --------
func _shot_interior() -> void:
	await _shot("s03", "s03_interior_overview", "一层室内+家具全景：人形 vs 沙发1.50/餐桌1.30/净高2.42",
		_local(Vector3(3.15, 2.20, 2.30)), _local(Vector3(-1.30, 1.15, -1.20)), 68.0,
		"参照人形 fig_interior(1.500m) + 家具规范表（沙发1.50x0.78、餐桌1.30x0.65、净高2.42）", false, ["fig_interior"])
	await _shot("s04", "s04_dining", "餐桌椅组合：餐桌 1.30x0.65x0.80 + 4 把椅 0.42x0.85x0.44",
		_local(Vector3(-0.75, 1.90, 2.45)), _local(Vector3(1.85, 0.95, 1.50)), 56.0,
		"已知尺寸物：dining_table 1.30x0.65x0.80 / chair 0.42x0.85x0.44")
	await _shot("s05", "s05_sofa", "沙发/扶手椅/茶几：沙发1.50x0.78x0.80、扶手椅0.72、茶几0.95",
		_local(Vector3(0.85, 2.00, 2.05)), _local(Vector3(-2.05, 0.90, 1.30)), 58.0,
		"已知尺寸物：sofa 1.50x0.78x0.80 / armchair 0.72x0.78x0.76 / coffee_table 0.95x0.38x0.50")
	await _shot("s06", "s06_bed", "阁楼床+床头柜：床 1.00x0.85x1.90、床头柜 0.40x0.50x0.38",
		_local(Vector3(1.30, 4.15, 1.85)), _local(Vector3(-2.00, 3.65, -0.90)), 58.0,
		"已知尺寸物：bed 1.00x0.85x1.90 / nightstand 0.40x0.50x0.38 / 阁楼地板面 3.17m")
	await _shot("s07", "s07_stairs_bottom", "楼梯下部：16 级、rise 0.16375 / tread 0.26 / 宽 0.85 / 扶手 0.85",
		_local(Vector3(1.45, 2.05, 1.55)), _local(Vector3(3.06, 1.30, -1.00)), 60.0,
		"已知尺寸物：楼梯 rise 0.16375 / tread 0.26 / 宽 0.85 / 首级踏面标高 0.55")
	await _shot("s08", "s08_stairs_landing", "楼梯转角平台：平台 0.85x0.85，顶面 1.86",
		_local(Vector3(1.25, 2.60, 0.10)), _local(Vector3(3.00, 1.95, -2.45)), 55.0,
		"已知尺寸物：平台 0.85x0.85 / 平台顶面 1.86m / 第 8 级")
	await _shot("s09", "s09_attic_entry", "二层入口：阁楼地板面 3.17、洞口护栏、Flight B 顶部",
		_local(Vector3(0.10, 4.45, 1.60)), _local(Vector3(0.95, 3.35, -1.95)), 58.0,
		"已知尺寸物：阁楼地板面 3.17m / 净高 2.42 / 洞口尺寸 1.82x0.85")
	await _shot("s10", "s10_figure_on_stairs", "人形站在楼梯上（Flight A 第 4 级）：1.50m 人形 vs 0.26 踏面",
		_local(Vector3(3.06, 2.30, 1.10)), _local(Vector3(3.06, 1.85, -1.02)), 58.0,
		"参照人形 fig_stairs(1.500m，脚底 = 第4级踏面 1.205m)", false, ["fig_stairs"])

# -------- 野外组：s11..s14 --------
func _shot_world() -> void:
	# ---- s11 小船 + 码头（真实航线状态机：coastal 航线 5% 处，紧邻码头）----
	var routes: Array = _main.get("_sail_routes") as Array
	var route: Dictionary = {}
	if routes != null:
		for r_v in routes:
			var rd: Dictionary = r_v
			if String(rd.get("kind", "")) == "coastal":
				route = rd
				break
		if route.is_empty() and routes.size() > 0:
			route = routes[0] as Dictionary
	var boat: Node3D = _main.get("_sailboat") as Node3D
	var s11_from := Vector3.ZERO
	var s11_tgt := Vector3.ZERO
	var s11_ok := false
	if boat != null and not route.is_empty():
		_main.call("_shot_boat_cruise", route, 0.05)
		await _settle(4)
		var bp: Vector3 = boat.global_position
		var dock_pos: Vector3 = _main.get("_boat_dock_pos") as Vector3
		var away := Vector3(bp.x - dock_pos.x, 0.0, bp.z - dock_pos.z)
		if away.length() < 0.5:
			away = Vector3(0.0, 0.0, 1.0)
		away = away.normalized()
		var sidew := Vector3(-away.z, 0.0, away.x)
		s11_tgt = (bp + dock_pos) * 0.5 + Vector3(0.0, 0.95, 0.0)
		s11_from = bp + away * 9.0 + sidew * 5.0 + Vector3(0.0, 2.8, 0.0)
		s11_ok = true
		print("[P7V32S] boat staged: pos=", _f3(bp), " dock=", _f3(dock_pos), " route=", String(route.get("name", "?")))
	await _shot("s11", "s11_boat_dock", "小船+码头：船体几何 3–6m / 干舷 0.25–0.70、码头甲板",
		s11_from, s11_tgt, 56.0,
		"已知尺寸物：boat_hull_len 3.00–6.00 / beam 1.20–2.00 / dock 甲板")
	if not s11_ok:
		_fail += 1

	# ---- s12 灯塔与树/房 ----
	var lh: Node3D = _main.get("_lighthouse") as Node3D
	var island: Node3D = _world.get("root") as Node3D
	var tree: Node3D = null
	if island != null:
		tree = island.find_child("BigTree", true, false) as Node3D
	var house_w: Vector3 = _cr.global_position
	var s12_tgt := house_w + Vector3(0.0, 5.0, 0.0)
	var s12_from := house_w + Vector3(30.0, 12.0, 30.0)
	var s12_ok := false
	if lh != null and tree != null:
		var lp: Vector3 = lh.global_position
		var tp: Vector3 = tree.global_position
		var c := (lp + house_w + tp) / 3.0
		var d := Vector3(lp.x - house_w.x, 0.0, lp.z - house_w.z)
		if d.length() < 0.5:
			d = Vector3(0.0, 0.0, 1.0)
		d = d.normalized()
		var perp := Vector3(-d.z, 0.0, d.x)
		var rad := maxf(maxf(lp.distance_to(c), tp.distance_to(c)), house_w.distance_to(c))
		s12_tgt = c + Vector3(0.0, 6.0, 0.0)
		s12_from = c + perp * (rad * 2.0) + Vector3(0.0, rad * 0.95 + 2.0, 0.0)
		s12_ok = true
		print("[P7V32S] s12 center=", _f3(c), " radius=", "%.2f" % rad, " lh=", _f3(lp), " tree=", _f3(tp))
	await _shot("s12", "s12_lighthouse", "灯塔与树/房：灯塔 18.28m vs 屋脊 6.20 / 大树 12.0",
		s12_from, s12_tgt, 58.0,
		"已知尺寸物：灯塔总高 18.28m（reference_keep ±0.20）/ 屋脊 6.20 / 大树 12.0")
	if not s12_ok:
		_fail += 1

	# ---- s13 猫与海鸥同框（真实栖点；猫在门廊地面，海鸥按真实栖点位置强制停栖）----
	var cat: Node3D = _cr.find_child("PorchCat", false, false) as Node3D
	var cat_pos := cat.global_position if cat != null else _local(Vector3(1.70, 0.44, 3.80))
	var gull_pos := _local(Vector3(2.135, 1.29, 4.60))
	var birds = _main.get("_birds")
	var staged := false
	if birds != null and birds.has_method("debug_force_perch"):
		staged = bool(birds.call("debug_force_perch", 0, "porch_rail_FR"))
		if staged:
			var arr: Array = birds.get("_birds") as Array
			if arr.size() > 0:
				var bd: Dictionary = arr[0]
				var bn = bd.get("node", null)
				if bn is Node3D:
					gull_pos = (bn as Node3D).global_position
	await _settle(3)
	var s13_tgt := (cat_pos + gull_pos) * 0.5 + Vector3(0.0, 0.32, 0.0)
	var s13_from := _local(Vector3(2.80, 1.80, 5.85))
	await _shot("s13", "s13_cat_gull", "猫与海鸥相对尺寸（同框）：猫肩高 0.25–0.35 / 海鸥体长 0.40–0.70",
		s13_from, s13_tgt, 46.0,
		"已知尺寸物：猫 cat_shoulder_h 0.25–0.35 / 海鸥 gull_body_len 0.40–0.70、翼展 1.10–1.50")
	print("[P7V32S] s13 cat=", _f3(cat_pos), " gull=", _f3(gull_pos), " forced_perch=", staged)
	if not staged:
		print("[P7V32S] WARN s13 海鸥未能强制停栖到 porch_rail_FR（仍按默认栖点取景）")

	# ---- s14 自由视角俯瞰岛与近海 ----
	await _shot("s14", "s14_overview", "自由视角俯瞰：岛地形直径≈63.6m、近海、村落/灯塔/码头同框",
		Vector3(26.0, 44.0, 66.0), Vector3(0.0, 1.2, 0.0), 56.0,
		"已知尺寸物：岛屿地形直径≈63.6m / 房屋 7.6x6.2 / 灯塔 18.28m")

# -------- 灯塔门 / 标尺：s15/s16 --------
func _shot_light_and_overlay() -> void:
	# ---- s15 灯塔门口特写：7 级石阶 + 门槛 + 1.50m 参照人形 ----
	var lh: Node3D = _main.get("_lighthouse") as Node3D
	var s15_from := Vector3(0.0, 0.0, 0.0)
	var s15_tgt := Vector3(0.0, 0.0, 0.0)
	var s15_ok := false
	if lh != null:
		var lh_xf: Transform3D = lh.global_transform
		# world.gd:2156 door_dir := Vector3(-LIGHTHOUSE_X, 0, -LIGHTHOUSE_Z).normalized()，LIGHTHOUSE_X=-17, Z=9
		var door_dir_local := Vector3(17.0, 0.0, -9.0).normalized()
		var door_ang := atan2(door_dir_local.x, door_dir_local.z)
		var door_dir := (lh_xf.basis * door_dir_local).normalized()
		# 7 级石阶（world.gd:2175-2192）：i=0 最上，top_y=0.16*(7-i)，ang=door_ang-(i+0.5)*0.15，
		# r_mid = r_plinth + 0.02 + 0.19，踏面上表面 y = top_y，节点原点 y = 台基地面
		var step_i := 2
		var step_y := 0.16 * float(7 - step_i)
		var r_plinth := 2.00 if step_y > 0.98 else 2.32 - (0.34 / 1.05) * step_y
		var r_mid := r_plinth + 0.02 + 0.19
		var step_ang := door_ang - (float(step_i) + 0.5) * 0.15
		var fig_pos: Vector3 = lh_xf * Vector3(sin(step_ang) * r_mid, step_y, cos(step_ang) * r_mid)
		# 相机站在台阶组外侧（门法线 -1.05 rad），沿石阶向上看门/门槛/人形
		var cam_ang := door_ang - 0.30
		var cam_local := Vector3(sin(cam_ang), 0.0, cos(cam_ang)) * 6.6 + Vector3(0.0, 1.70, 0.0)
		var cam_pos: Vector3 = lh_xf * cam_local
		_fig(fig_pos, _face_yaw(fig_pos, cam_pos), "fig_lighthouse")
		# 门口中心：door_base = 1.66*dir，门槛顶 1.20、门楣底约 3.31
		var door_mid: Vector3 = lh_xf * (door_dir_local * 1.86 + Vector3(0.0, 1.60, 0.0))
		s15_tgt = door_mid
		s15_from = cam_pos
		s15_ok = true
		print("[P7V32S] s15 lighthouse base=", _f3(lh.global_position), " door_dir=", _f3(door_dir),
			" fig_step=", step_i, " step_y=", step_y, " fig=", _f3(fig_pos), " cam=", _f3(cam_pos),
			" door_mid=", _f3(door_mid))
	await _shot("s15", "s15_lighthouse_door", "灯塔门口特写：7 级石阶(rise 0.16/depth 0.38)、门槛、1.50m 人形",
		s15_from, s15_tgt, 58.0,
		"参照人形 fig_lighthouse(1.500m，脚底=第3级石阶踏面 0.80m) + 7 级石阶 rise 0.16 / depth 0.38 / 门槛顶 1.20", false, ["fig_lighthouse"])
	if not s15_ok:
		_fail += 1

	# ---- s16 标尺证据：打开 --scale-debug 的 ScaleDebugOverlay 拍屋前，再关闭 ----
	var anchor := _local(Vector3(0.0, 0.0, Spec.HOUSE_D * 0.5 + 1.9))
	anchor.y = M.terrain_height(anchor.x, anchor.z)
	var s16_from := anchor + _n * 7.2 - _side * 1.0 + Vector3(0.0, 2.4, 0.0)
	await _shot("s16", "s16_overlay_ruler", "开发标尺（--scale-debug）：1m 立方 / 1.50m 人形 / 垂直水平标尺 / 房屋层高标注",
		s16_from, anchor + Vector3(0.0, 1.30, 0.0), 52.0,
		"ScaleDebugOverlay：1m 参照立方 + 1.500m 人形 + 0–3m 垂直标尺 + 2m 水平标尺", true)

# ============================================================ 截图核心 ======
func _show_figs(tags: Array) -> void:
	for tag_v in _fig_nodes.keys():
		var tag := String(tag_v)
		var n: Node3D = _fig_nodes[tag] as Node3D
		if is_instance_valid(n):
			n.visible = tags.has(tag)

func _shot(sid: String, name: String, desc: String, from: Vector3, target: Vector3, fov: float, refs: String, overlay_on := false, figs: Array = []) -> void:
	if not _want(sid):
		return
	_show_figs(figs)
	if _overlay != null and _overlay.has_method("set_debug_visible"):
		_overlay.call("set_debug_visible", overlay_on)
	_main.call("_pose_look", from, target, fov)
	await _settle(10)
	await RenderingServer.frame_post_draw
	var img: Image = _main.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(_out)
	var path: String = _out + name + ".png"
	var err := ERR_CANT_CREATE
	if img != null:
		err = img.save_png(path)
	var lum := _mean_luma(img)
	var xf: Transform3D = _cam.global_transform
	var cp := xf.origin
	var fwd := -xf.basis.z
	var yaw := rad_to_deg(atan2(fwd.x, fwd.z))
	var pitch := rad_to_deg(asin(clampf(fwd.y, -1.0, 1.0)))
	var iw := 0
	var ih := 0
	if img != null:
		iw = img.get_width()
		ih = img.get_height()
	print("[P7V32S] SHOT ", sid, " ", name,
		" cam=(", _f3(cp), ") target=(", _f3(target), ") fov=", "%.1f" % fov,
		" yaw=", "%.1f" % yaw, " pitch=", "%.1f" % pitch,
		" lum=", "%.3f" % lum, " size=", iw, "x", ih, " err=", err, " desc=", desc)
	if err != OK or iw != SHOT_W or ih != SHOT_H:
		_fail += 1
		print("[P7V32S] FAIL 保存/尺寸异常 ", name, " err=", err, " size=", iw, "x", ih)
	_manifest.append({
		"id": sid, "file": name + ".png", "desc": desc,
		"cam": [cp.x, cp.y, cp.z], "target": [target.x, target.y, target.z],
		"yaw_deg": yaw, "pitch_deg": pitch, "fov": fov,
		"time_min": _time_used, "quality": _quality_used,
		"luma": lum, "size": [iw, ih], "err": err, "refs": refs,
		"figs_shown": figs,
	})
	if overlay_on and _overlay != null and _overlay.has_method("set_debug_visible"):
		_overlay.call("set_debug_visible", false)

func _want(sid: String) -> bool:
	if _only.size() > 0:
		return _only.has(sid)
	match _stage:
		"house":
			return sid == "s01" or sid == "s02"
		"interior":
			return sid in ["s03", "s04", "s05", "s06", "s07", "s08", "s09", "s10"]
		"world":
			return sid in ["s11", "s12", "s13", "s14"]
		_:
			return true

# ============================================================ 小工具 ========
func _force_windowed() -> void:
	# 用户设置可能保存了 fullscreen/borderless（会变成显示器尺寸），截图前强制回 1600x900 窗口。
	if DisplayServer.get_name() == "headless":
		return
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))

func _settle(n: int) -> void:
	for i in n:
		await process_frame

func _set_time(minutes: float) -> void:
	_main.call("_set_time_of_day", minutes)
	_main.call("_update_lighting")

func _local(p: Vector3) -> Vector3:
	return _cr.global_transform * p

func _ground(lp: Vector3) -> Vector3:
	var wp := _local(lp)
	wp.y = M.terrain_height(wp.x, wp.z)
	return wp

func _face_yaw(from_world: Vector3, to_world: Vector3) -> float:
	var d := Vector3(to_world.x - from_world.x, 0.0, to_world.z - from_world.z)
	if d.length_squared() < 1e-8:
		return 0.0
	return atan2(-d.x, -d.z)

func _fig(world_pos: Vector3, world_yaw: float, tag: String) -> Node3D:
	if _holder == null:
		return null
	var fig: Node3D = Figure.build(_holder, world_pos, world_yaw)
	if fig == null:
		_fail += 1
		return null
	var m: Dictionary = Figure.measure(fig)
	var h := float(m.get("height", 0.0))
	var fine := bool(m.get("fine", false))
	print("[P7V32S] FIG ", tag, " pos=(", _f3(world_pos), ") yaw_deg=", "%.1f" % rad_to_deg(world_yaw),
		" h=", "%.4f" % h, " height_err=", "%.4f" % float(m.get("height_err", 0.0)), " fine=", fine,
		" world_aabb_y=", "%.4f" % (m.get("world_aabb", AABB()).position.y))
	_figures.append({"tag": tag, "pos": [world_pos.x, world_pos.y, world_pos.z], "height": h, "fine": fine})
	_fig_nodes[tag] = fig
	if not fine:
		_fail += 1
		print("[P7V32S] FAIL 参照人形高度不在 1.500±0.010：", tag, " h=", h)
	return fig

func _f3(v: Vector3) -> String:
	return "%.2f,%.2f,%.2f" % [v.x, v.y, v.z]

func _mean_luma(img: Image) -> float:
	if img == null:
		return -1.0
	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0:
		return -1.0
	var acc := 0.0
	var n := 0
	var step := 16
	for y in range(0, h, step):
		for x in range(0, w, step):
			var c := img.get_pixel(x, y)
			acc += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
	if n <= 0:
		return -1.0
	return acc / float(n)

# ============================================================ 清单 =========
func _write_manifest() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	# JSON（全量）
	var meta := {
		"probe": "tools/probe_scale_shots_p7v32.gd",
		"commit": _git_commit(),
		"generated_at": Time.get_datetime_string_from_system(false, true),
		"engine": Engine.get_version_info().get("string", "?"),
		"resolution": [SHOT_W, SHOT_H],
		"seed": SEED_VAL,
		"time_min": _time_used,
		"quality": _quality_used,
		"paused": true,
		"renderer": DisplayServer.get_name(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"house_world": [_cr.global_position.x, _cr.global_position.y, _cr.global_position.z],
		"figures": _figures,
		"shots": _manifest,
	}
	var f := FileAccess.open(_out + "scale_shots_manifest.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(meta, "  "))
		f.close()
	# manifest.md（人读）
	var md := "# P7-V3.2 T5 验收截图清单（16 张）\n\n"
	md += "- 生成：tools/probe_scale_shots_p7v32.gd\n"
	md += "- 代码冻结 commit：%s\n" % _git_commit()
	md += "- 生成时间：%s\n" % Time.get_datetime_string_from_system(false, true)
	md += "- 引擎：%s\n" % Engine.get_version_info().get("string", "?")
	md += "- 分辨率：%dx%d（窗口模式 %s）\n" % [SHOT_W, SHOT_H, DisplayServer.get_name()]
	md += "- 固定：seed=%d，时间=%.0f 分钟（12:20），画质档=%d，_paused=true\n" % [SEED_VAL, _time_used, _quality_used]
	md += "- 引擎：%s\n" % OS.get_executable_path()
	md += "- GPU：%s\n" % RenderingServer.get_video_adapter_name()
	md += "- 参照人形：scripts/isle_scale_figure.gd，脚底局部 y=0、头顶 1.500 m（回读见下表 h）\n\n"
	md += "| 文件 | 场景/说明 | 相机位置 | 朝向(yaw/pitch) | fov | 时间 | 画质 | 参照物 | 平均亮度 | 保存 |\n"
	md += "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |\n"
	for s_v in _manifest:
		var s: Dictionary = s_v
		var cp: Array = s.get("cam", [])
		md += "| %s | %s | (%.2f, %.2f, %.2f) | %.1f° / %.1f° | %.1f | %.0f min | %d | %s | %.3f | %s |\n" % [
			String(s.get("file", "")), String(s.get("desc", "")),
			float(cp[0]), float(cp[1]), float(cp[2]),
			float(s.get("yaw_deg", 0.0)), float(s.get("pitch_deg", 0.0)), float(s.get("fov", 0.0)),
			float(s.get("time_min", 0.0)), int(s.get("quality", 0)),
			String(s.get("refs", "")), float(s.get("luma", 0.0)),
			"OK" if int(s.get("err", 1)) == 0 else "ERR"]
	md += "\n## 参照人形回读（Figure.measure）\n\n"
	md += "| tag | 世界位置 | 实测高度(m) | 1.500±0.010 |\n| --- | --- | --- | --- |\n"
	for f_v in _figures:
		var fd: Dictionary = f_v
		var fp: Array = fd.get("pos", [])
		md += "| %s | (%.2f, %.2f, %.2f) | %.4f | %s |\n" % [
			String(fd.get("tag", "")), float(fp[0]), float(fp[1]), float(fp[2]),
			float(fd.get("height", 0.0)), "PASS" if bool(fd.get("fine", false)) else "FAIL"]
	var mf := FileAccess.open(_out + "manifest.md", FileAccess.WRITE)
	if mf != null:
		mf.store_string(md)
		mf.close()
	print("[P7V32S] manifest 写入 ", _out + "manifest.md 与 scale_shots_manifest.json")

func _git_commit() -> String:
	var out: Array = []
	var proj := ProjectSettings.globalize_path("res://")
	var code := OS.execute("git", ["-C", proj, "rev-parse", "--short", "HEAD"], out, true)
	if code == 0 and out.size() > 0:
		var s := String(out[0]).strip_edges()
		if s != "":
			return s
	return "unknown"

func _print_shot_table() -> void:
	print("P7-V3.2 T5 验收截图清单（tools/probe_scale_shots_p7v32.gd）")
	var rows := [
		["s01", "s01_house_front", "人形与房屋正面"],
		["s02", "s02_door", "人形站在门口（门洞对比）"],
		["s03", "s03_interior_overview", "一层室内+家具全景"],
		["s04", "s04_dining", "餐桌椅组合"],
		["s05", "s05_sofa", "沙发/扶手椅/茶几"],
		["s06", "s06_bed", "床+床头柜"],
		["s07", "s07_stairs_bottom", "楼梯下部"],
		["s08", "s08_stairs_landing", "楼梯转角平台"],
		["s09", "s09_attic_entry", "二层入口"],
		["s10", "s10_figure_on_stairs", "人形站在楼梯上"],
		["s11", "s11_boat_dock", "小船+码头"],
		["s12", "s12_lighthouse", "灯塔与树/房"],
		["s13", "s13_cat_gull", "猫与海鸥相对尺寸（同框）"],
		["s14", "s14_overview", "自由视角俯瞰岛与近海"],
		["s15", "s15_lighthouse_door", "灯塔门口特写+人形"],
		["s16", "s16_overlay_ruler", "开发标尺（--scale-debug）"],
	]
	for r in rows:
		print("  %s  %s  %s" % [r[0], r[1], r[2]])
	print("参数：--out=<dir> --only=s01,s03 --stage=house|interior|world|all --time=740 --quality=2")
