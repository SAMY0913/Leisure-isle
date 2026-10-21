extends SceneTree
## P7-V3 任务 F/G/H 视觉取证探针（真实窗口渲染）
## 覆盖：一层室内布局、楼梯（下段/平台/上段/井壁）、二层阁楼（家具/栏杆/洞口）、室外无破洞、
##       猫咪造型与原地待机动作（呼吸/尾巴/眨眼/耳朵/观察/舔爪摆拍）
## 运行（必须真实窗口）：
##   "D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe" --path "D:/休闲小岛幻境/游戏工程" --resolution 1600x900 --script res://tools/probe_house_p7v3.gd

const SHOTS_DIR := "D:/休闲小岛幻境/开发产物/p7v32/shots/house/"
const SHOTS_CAT := "D:/休闲小岛幻境/开发产物/p7v32/shots/cat/"

var _main: Node = null
var _cottage: Dictionary = {}
var _cr: Node3D = null
var _n: Vector3 = Vector3.FORWARD   # 房屋正面朝向（世界）
var _side: Vector3 = Vector3.RIGHT
var _manifest: Array = []
var _checks := 0
var _fails := 0
var _raw_size := Vector2i.ZERO
var _fy := 0.55
var _in_top := 2.97
var _attic_floor := 3.17
var _hw := 3.8
var _hd := 3.1

func _initialize() -> void:
	print("=== P7V3 HOUSE SHOTS START ===")
	if DisplayServer.get_name() == "headless":
		print("[P7V3H] SKIP headless：真实渲染截图必须在窗口模式运行")
		quit(1)
		return
	await process_frame
	var packed: PackedScene = load("res://isle.tscn") as PackedScene
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
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await _settle(10)
	_cottage = _main.get("_cottage")
	_cr = _cottage.get("root")
	_n = (_cr.global_transform.basis * Vector3(0.0, 0.0, 1.0)).normalized()
	_side = (_cr.global_transform.basis * Vector3(1.0, 0.0, 0.0)).normalized()
	print("[P7V3H] window=", DisplayServer.window_get_size(), " viewport=", _main.get_viewport().get_visible_rect().size, " screen_scale=", DisplayServer.screen_get_scale(), " cottage=", _cr.global_transform.origin)
	_geo_checks()
	_dump_api()
	_set_time(745.0)
	await _section_interior_day()
	await _section_stairs_day()
	await _section_attic_day()
	await _section_exterior_day()
	await _section_night()
	await _section_cat()
	_write_manifest()
	print("[P7V3H] RESULT shots=", _manifest.size(), " checks=", _checks, " pass=", _checks - _fails, " fail=", _fails)
	if _fails == 0:
		print("[P7V3H] RESULT_OK")
		quit(0)
	else:
		print("[P7V3H] RESULT_FAIL")
		quit(1)

func _dump_api() -> void:
	var st := _cr.get_node_or_null("Staircase")
	if st != null:
		print("[P7V3H] Staircase meta risers=", st.get_meta("risers", -1), " rise=", st.get_meta("rise", -1.0), " tread=", st.get_meta("tread", -1.0), " r1=", st.get_meta("hole_r1", null), " r2=", st.get_meta("hole_r2", null))
		print("[P7V3H] Staircase children=", st.get_child_count())
	var ia := _cr.get_node_or_null("AtticInterior")
	if ia != null:
		print("[P7V3H] AtticInterior furniture_count=", ia.get_meta("furniture_count", -1), " children=", ia.get_child_count())
	var cat := _cr.get_node_or_null("PorchCat")
	if cat != null:
		var ci: Dictionary = _cottage.get("cat", {})
		var idle = ci.get("idle", null)
		if idle != null:
			print("[P7V3H] CAT state=", idle.call("debug_state"))

func _ck(name: String, got: float, want: float, tol: float) -> void:
	_checks += 1
	if absf(got - want) <= tol:
		print("[P7V3H] OK   ", name, " got=", snappedf(got, 0.0001), " want=", snappedf(want, 0.0001))
	else:
		_fails += 1
		print("[P7V3H] FAIL ", name, " got=", snappedf(got, 0.0001), " want=", snappedf(want, 0.0001), " tol=", tol)

func _geo_checks() -> void:
	# 断言全部从 IsleMath.HOUSE_* / IsleScaleSpec 与 build 返回/节点 meta 推导，不硬编码旧尺寸
	var C: Dictionary = _cr.get_meta("cottage_ctx", {})
	_fy = float(C.get("fy", 0.55))
	_in_top = float(C.get("in_top", 2.97))
	_attic_floor = float(C.get("attic_floor", 3.17))
	_hw = float(C.get("hw", 3.8))
	_hd = float(C.get("hd", 3.1))
	_ck("outer_w", float(C.get("w", 0.0)), IsleMath.HOUSE_W, 0.001)
	_ck("outer_d", float(C.get("d", 0.0)), IsleMath.HOUSE_D, 0.001)
	_ck("wall_h", float(C.get("wh", 0.0)), IsleMath.HOUSE_WALL_H, 0.001)
	_ck("ridge_y", float(C.get("ridge_y", 0.0)), IsleMath.HOUSE_RIDGE_Y, 0.001)
	_ck("room_clear_h", _in_top - _fy, IsleScaleSpec.ROOM_CLEAR_H, 0.001)
	_ck("attic_floor_y", _attic_floor, IsleMath.HOUSE_ATTIC_FLOOR_Y, 0.001)
	var dc: Dictionary = _cr.get_meta("door_clear", {})
	_ck("door_clear_w", float(dc.get("w", 0.0)), IsleScaleSpec.DOOR_CLEAR_W, 0.001)
	_ck("door_clear_h", float(dc.get("h", 0.0)), IsleScaleSpec.DOOR_CLEAR_H, 0.001)
	_ck("door_handle_h", float(dc.get("handle_h", 0.0)), IsleScaleSpec.DOOR_HANDLE_H, 0.001)
	var st := _cr.get_node_or_null("Staircase")
	if st == null:
		_fails += 1
		print("[P7V3H] FAIL Staircase missing")
	else:
		_ck("stair_risers", float(int(st.get_meta("risers", 0))), float(IsleScaleSpec.STAIR_COUNT), 0.001)
		_ck("stair_rise", float(st.get_meta("rise", 0.0)), IsleScaleSpec.STAIR_RISE, 0.0001)
		_ck("stair_tread", float(st.get_meta("tread", 0.0)), IsleScaleSpec.STAIR_TREAD, 0.0001)
		_ck("stair_width", float(st.get_meta("width", 0.0)), IsleScaleSpec.STAIR_WIDTH, 0.0001)
		_ck("stair_land_top", float(st.get_meta("land_top", 0.0)), IsleMath.HOUSE_FY + 8.0 * IsleScaleSpec.STAIR_RISE, 0.01)
		_ck("stair_attic_floor", float(st.get_meta("attic_floor", 0.0)), IsleMath.HOUSE_ATTIC_FLOOR_Y, 0.001)
	_ck("porch_deck_top", float(C.get("deck_top", 0.0)), 0.42, 0.02)
	_ck("chimney_cap_top", float(C.get("ch_top", 0.0)) + IsleMath.HOUSE_CHIMNEY_ABOVE_RIDGE, IsleMath.HOUSE_RIDGE_Y + IsleMath.HOUSE_CHIMNEY_ABOVE_RIDGE, 0.001)
func _settle(n: int) -> void:
	for i in range(maxi(n, 0)):
		await process_frame

func _set_time(minutes: float) -> void:
	_main.call("_set_time_of_day", minutes)
	_main.call("_update_lighting")

func _pose(from: Vector3, target: Vector3, fov: float) -> void:
	_main.call("_pose_look", from, target, fov)

func _local(p: Vector3) -> Vector3:
	return _cr.global_transform * p

func _shot(shot_name: String, desc: String, dir: String = SHOTS_DIR) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(dir)
	var img: Image = _main.get_viewport().get_texture().get_image()
	if img.get_width() != 1600 or img.get_height() != 900:
		if _raw_size == Vector2i.ZERO:
			_raw_size = Vector2i(img.get_width(), img.get_height())
			print("[P7V3H] raw_frame=", _raw_size, " screen_scale=", DisplayServer.screen_get_scale())
		img.resize(1600, 900, Image.INTERPOLATE_LANCZOS)
	var path := dir + shot_name + ".png"
	var err := img.save_png(path)
	var lum := _mean_luma(img)
	_manifest.append({"name": shot_name + ".png", "desc": desc, "luma": snappedf(lum, 0.001), "err": err})
	print("[P7V3H] SHOT ", shot_name, " luma=", snappedf(lum, 0.001), " err=", err)
	await process_frame

func _mean_luma(img: Image) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var step := 16
	var acc := 0.0
	var cnt := 0
	for y in range(0, h, step):
		for x in range(0, w, step):
			var c := img.get_pixel(x, y)
			acc += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			cnt += 1
	return acc / float(maxi(cnt, 1))

func _look(local_from: Vector3, local_target: Vector3, fov: float) -> void:
	_pose(_local(local_from), _local(local_target), fov)

func _section_interior_day() -> void:
	await _settle(6)
	# 1) 门口向内看：第一眼应能读懂房间布局
	_look(Vector3(0.0, _fy + 1.60, _hd + 0.85), Vector3(0.20, _fy + 0.90, -0.60), 62.0)
	await _settle(4)
	await _shot("interior_entry_day", "一层入口向内：门垫/餐桌/客厅动线第一眼")
	# 2) 室内总览：站在壁炉侧内角（眼高 fy+1.45，机位在室内净空内），朝门侧看全屋
	_look(Vector3(-2.90, _fy + 1.45, -1.50), Vector3(1.60, _fy + 0.85, 2.05), 68.0)
	await _settle(4)
	await _shot("interior_overview_day", "一层室内总览（壁炉侧内角、眼高，朝门侧）")
	# 3) 客厅（沙发/茶几/地毯/扶手椅/壁炉）
	_look(Vector3(0.60, _fy + 1.80, 2.05), Vector3(-2.10, _fy + 0.50, -1.60), 64.0)
	await _settle(4)
	await _shot("interior_living_day", "客厅：沙发-茶几-地毯-扶手椅-壁炉组合")
	# 4) 餐区
	_look(Vector3(-0.55, _fy + 1.70, -1.55), Vector3(1.45, _fy + 0.60, 0.80), 60.0)
	await _settle(4)
	await _shot("interior_dining_day", "餐区：餐桌与四把椅子、吊灯")
	# 5) 左墙工作区（书桌/书架/画框）
	_look(Vector3(1.60, _fy + 1.70, 1.35), Vector3(-_hw + 0.30, _fy + 0.80, 0.30), 62.0)
	await _settle(4)
	await _shot("interior_desk_wall_day", "左墙工作区：书桌、椅、书架、画框")
	# 6) 后墙储物区（壁炉/高柜/矮边柜）
	_look(Vector3(2.70, _fy + 1.75, 1.10), Vector3(-2.10, _fy + 0.65, -_hd + 0.40), 62.0)
	await _settle(4)
	await _shot("interior_back_wall_day", "后墙：壁炉、高柜、矮边柜与台灯")

func _section_stairs_day() -> void:
	await _settle(4)
	# 1) 从室内看楼梯整体（右后角上行）
	_look(Vector3(-0.90, _fy + 1.90, 1.10), Vector3(3.35, _fy + 1.50, -2.20), 66.0)
	await _settle(4)
	await _shot("stairs_from_room_day", "室内看楼梯：起点、井壁与二层开口关系")
	# 2) 楼梯下段近景（踏步/踢面/梯梁/起步柱/内侧扶手）
	_look(Vector3(2.35, _fy + 1.10, 1.55), Vector3(3.35, _fy + 0.55, -1.30), 62.0)
	await _settle(4)
	await _shot("stairs_bottom_close_day", "楼梯下段近景：踏步、梯梁、内侧扶手")
	# 3) 站在下段向上看平台与上段
	_look(Vector3(3.10, _fy + 2.30, 0.45), Vector3(3.00, _attic_floor + 0.55, -2.60), 66.0)
	await _settle(4)
	await _shot("stairs_mid_up_day", "楼梯中段向上：平台、转向与二层洞口")
	# 4) 平台近景
	_look(Vector3(2.92, _fy + 2.05, -1.55), Vector3(3.06, _fy + 1.31, -2.70), 64.0)
	await _settle(4)
	await _shot("stairs_landing_day", "转角平台：到达口已无遮挡、平台踏面与上段起步")
	# 5) 上段：透过二层洞口 R2 斜视 Flight B 的踏步序列与壁装扶手
	#    P7-V3.1：原机位 (2.60, 5.05, -2.35) 落在"被楼梯井壁封住的空腔"里
	#    （井壁覆盖 y 4.25~5.63 且 z>-2.60 一侧），画面几乎全是井壁，无法判读踏步。
	#    产品几何无问题（verify 探针的踏步/平台/井壁断言全部通过），故只修探针机位。
	_look(Vector3(1.40, _attic_floor + 1.35, -1.50), Vector3(2.20, _attic_floor + 0.10, -2.365), 75.0)
	await _settle(4)
	await _shot("stairs_upper_flight_day", "上段：透过二层洞口 R2 看 Flight B 的 11 级踏步与壁装扶手（含支架）")
	# 6) 从一层室内仰视楼梯井（验证洞口真实开透、无残留遮挡楼板）
	_look(Vector3(2.05, _fy + 1.10, -0.35), Vector3(3.05, _attic_floor + 0.60, -2.10), 70.0)
	await _settle(4)
	await _shot("stairs_under_hole_day", "一层仰视楼梯井：洞口开透、井壁收边与上段下皮")
	# 7) 楼梯起步处（起点不挡门/家具、踏步可读）
	_look(Vector3(2.55, _fy + 0.80, 1.85), Vector3(3.35, _fy + 1.10, -0.10), 62.0)
	await _settle(4)
	await _shot("stairs_start_day", "楼梯起步：起步柱、第一级踏步与房间动线")

func _section_attic_day() -> void:
	await _settle(4)
	# 1) 阁楼总览：站前左角可站立区内、略俯视看床/衣柜/书架/洞口。
	#    相机 (-2.90, +0.75, 2.40)：该 x 处屋顶下皮 6.20-|x|tan(33.02)-0.167 = 4.149 > 3.92，净空 0.23。
	#    吊灯 halo 在 (0.20, 5.33, 0.90)，本机位下位于画面上缘之外只剩小弧（占宽≈11%），不再占大块画面。
	_look(Vector3(-2.90, _attic_floor + 0.75, 2.40), Vector3(-0.20, _attic_floor + 0.28, 0.70), 64.0)
	await _settle(4)
	await _shot("attic_overview_day", "二层阁楼总览：床、书桌、阅读角、栏杆")
	# T2-TEMP 候选机位（选型用，最终交付删除）
	_look(Vector3(-2.60, 3.65, 2.40), Vector3(-2.10, 3.45, -1.60), 74.0)
	await _settle(3)
	await _shot("tmp_attic_A", "候选A：前左角沿 -Z，吊灯完全出画")
	_look(Vector3(-2.50, 3.75, 2.20), Vector3(0.40, 3.50, -1.20), 70.0)
	await _settle(3)
	await _shot("tmp_attic_E", "候选E：前左角斜向室内中央，吊灯仅顶部小弧")
	_look(Vector3(-2.60, 3.80, 2.40), Vector3(-0.20, 3.50, -1.50), 72.0)
	await _settle(3)
	await _shot("tmp_attic_F", "候选F：前左角对角线，吊灯顶部小弧")
	# 2) 楼梯口/栏杆/洞口（从阁楼内看洞口）
	_look(Vector3(0.55, _attic_floor + 1.30, -1.55), Vector3(3.20, _attic_floor + 0.35, -2.60), 66.0)
	await _settle(4)
	await _shot("attic_hole_railing_day", "二层洞口与栏杆：真实开口、无残留遮挡楼板")
	# 3) 从洞口上方往下看楼梯：透过 R1 同时看到转角平台、上段起步与洞口边缘
	#    P7-V3.1：原机位偏高偏近，画面主要是阁楼地板与栏杆立柱，楼梯只占一角。
	_look(Vector3(3.05, _attic_floor + 1.45, -1.20), Vector3(3.00, _fy + 2.60, -2.40), 80.0)
	await _settle(4)
	await _shot("attic_stairs_look_down_day", "从二层洞口 R1 向下看：转角平台 + 上段起步 + 洞口边缘")
	# 4) 床区
	_look(Vector3(1.40, _attic_floor + 1.25, 0.65), Vector3(-2.20, _attic_floor + 0.75, -0.90), 62.0)
	await _settle(4)
	await _shot("attic_bed_day", "阁楼床区：床架/床垫/被子/床头柜与斜顶关系")
	# 5) 书桌区
	_look(Vector3(-1.95, _attic_floor + 1.35, 0.35), Vector3(0.35, _attic_floor + 0.75, 2.60), 62.0)
	await _settle(4)
	await _shot("attic_desk_day", "阁楼书桌区：书桌、椅、台灯与窗光方向")

func _section_exterior_day() -> void:
	await _settle(4)
	# 1) 正面外观（确认没有因楼板开洞出现外部破洞/漏光）
	var t := _local(Vector3(0.0, _fy + 2.10, 4.30))
	_pose(t + _n * 13.0 + _side * 1.2 + Vector3(0.0, 2.2, 0.0), t, 50.0)
	await _settle(4)
	await _shot("house_front_day", "正面外观：屋顶/门窗/门廊完整，无破洞漏光")
	# 2) 阁楼正面窗（透过窗看二层内部是否自然）
	var ta := _local(Vector3(0.0, _attic_floor + 0.85, _hd + 1.45))
	_pose(ta + _n * 8.5 + Vector3(0.0, 1.2, 0.0), ta, 50.0)
	await _settle(4)
	await _shot("attic_window_front_day", "正面阁楼窗：二层内部布置与窗框关系")

func _section_night() -> void:
	_set_time(1305.0)
	await _settle(6)
	_look(Vector3(-2.90, _fy + 1.45, -1.50), Vector3(1.60, _fy + 0.85, 2.05), 68.0)
	await _settle(4)
	await _shot("interior_overview_night", "深夜一层室内照明（吊灯/台灯/壁炉）")
	_look(Vector3(-0.90, _fy + 1.90, 1.10), Vector3(3.35, _fy + 1.50, -2.20), 66.0)
	await _settle(4)
	await _shot("stairs_from_room_night", "深夜楼梯与井壁（楼梯自身无光源时是否可读）")
	_look(Vector3(-2.90, _attic_floor + 0.75, 2.40), Vector3(-0.20, _attic_floor + 0.28, 0.70), 64.0)
	await _settle(4)
	await _shot("attic_overview_night", "深夜二层阁楼照明（台灯/床头柜灯）")

func _section_cat() -> void:
	_set_time(745.0)
	await _settle(8)
	var cat: Node3D = _cr.get_node_or_null("PorchCat")
	if cat == null:
		print("[P7V3H] CAT MISSING")
		return
	var fwd := (cat.global_transform.basis * Vector3(0.0, 0.0, 1.0)).normalized()
	var side := (cat.global_transform.basis * Vector3(1.0, 0.0, 0.0)).normalized()
	var cp := cat.global_transform.origin
	var chest := cp + Vector3(0.0, 0.245, 0.0)
	# 机位全部放在门廊内部（避开前栏/长椅遮挡）：猫朝 +Z 偏 -X，故正/侧面取门廊内前侧机位
	_pose(chest + fwd * 1.25 - side * 0.80 + Vector3(0.0, 0.28, 0.0), chest + Vector3(0.0, 0.02, 0.0), 44.0)
	await _settle(4)
	await _shot("cat_front_day", "猫咪正面近景：头身比例、耳朵、眼睛、前腿与爪", SHOTS_CAT)
	# 侧面（左前侧 3/4）
	_pose(chest - side * 1.55 + fwd * 0.25 + Vector3(0.0, 0.25, 0.0), chest + Vector3(0.0, -0.02, 0.0), 46.0)
	await _settle(4)
	await _shot("cat_side_day", "猫咪侧面近景：坐姿轮廓、尾巴连接与后腿", SHOTS_CAT)
	# 后方（尾巴/背部）
	_pose(chest - fwd * 1.30 + side * 0.55 + Vector3(0.0, 0.35, 0.0), chest + Vector3(0.0, -0.08, 0.0), 46.0)
	await _settle(4)
	await _shot("cat_back_day", "猫咪背面近景：尾巴形态与身体连接", SHOTS_CAT)
	# 冻结待机驱动，逐动作摆拍（同一位置、同一机位）
	var ci: Dictionary = _cottage.get("cat", {})
	var idle = ci.get("idle", null)
	var driver = ci.get("driver", null)
	if idle == null:
		print("[P7V3H] CAT idle controller missing")
		return
	if driver != null:
		driver.set_process(false)
	_pose(chest + fwd * 1.20 - side * 0.78 + Vector3(0.0, 0.26, 0.0), chest, 44.0)
	await _settle(3)
	if idle.has_method("debug_clear_events"):
		idle.call("debug_clear_events")
	await _settle(2)
	await _shot("cat_idle_base_day", "猫咪待机基准姿态（冻结驱动）", SHOTS_CAT)
	var actions: Array = [
		["blink", 0.45, "cat_blink_day", "待机动作：眨眼（闭眼相位）"],
		["ear", 0.19, "cat_ear_day", "待机动作：耳朵抽动（双耳抽动峰值）"],
		["look", 0.45, "cat_look_day", "待机动作：观察四周（头部转向保持）"],
		["lick", 0.45, "cat_lick_day", "待机动作：舔爪/整理（头低+前爪抬起）"],
	]
	for act in actions:
		if idle.has_method("debug_clear_events"):
			idle.call("debug_clear_events")
		var side_arg: int = 2 if act[0] == "ear" else -1
		idle.call("debug_force_event", act[0], act[1], side_arg)
		# 关键：force 只改定时器起点，必须 advance 一个极小步长重新计算派生量并应用姿态
		idle.call("advance", 0.001)
		await _settle(2)
		var st_f: Dictionary = idle.call("debug_state")
		print("[P7V3H] CAT force=", act[0], " lid=", st_f.get("lid_amount"), " ear=", st_f.get("ear_flick"), " look=", st_f.get("look_yaw"), " lick=", st_f.get("lick_env"))
		await _shot(act[2], act[3], SHOTS_CAT)
	var st: Dictionary = idle.call("debug_state")
	print("[P7V3H] CAT forced state tail_y=", st.get("tail_y"), " head_yaw=", st.get("head_yaw"), " lid_amount=", st.get("lid_amount"), " ear_flick=", st.get("ear_flick"), " lick_env=", st.get("lick_env"))
	# 恢复自然驱动，等呼吸/尾巴自然相位再拍（验证动作实际在动）
	if driver != null:
		driver.set_process(true)
	if idle.has_method("debug_clear_events"):
		idle.call("debug_clear_events")
	await _settle(30)
	var st2: Dictionary = idle.call("debug_state")
	print("[P7V3H] CAT live state breath_scale=", st2.get("breath_scale"), " tail_y=", st2.get("tail_y"), " t=", st2.get("t"))
	await _shot("cat_idle_live_day", "猫咪自然待机（呼吸+尾巴摆动的自然相位 A）", SHOTS_CAT)
	await _settle(30)
	var st3: Dictionary = idle.call("debug_state")
	print("[P7V3H] CAT live state2 breath_scale=", st3.get("breath_scale"), " tail_y=", st3.get("tail_y"), " t=", st3.get("t"))
	await _shot("cat_idle_live2_day", "猫咪自然待机（呼吸+尾巴摆动的自然相位 B，与 A 对比可证动作在动）", SHOTS_CAT)
	# 夜间门口猫
	_set_time(1305.0)
	await _settle(6)
	_pose(chest + fwd * 1.25 - side * 0.80 + Vector3(0.0, 0.28, 0.0), chest + Vector3(0.0, 0.02, 0.0), 44.0)
	await _settle(4)
	await _shot("cat_front_night", "夜间门廊猫咪（门廊灯下）", SHOTS_CAT)

# 短 commit：优先 T2_COMMIT（由 run_house_shots.ps1 注入），否则询问 git（兼容 Godot 4 输出数组形态）
func _git_short_commit() -> String:
	var envc := OS.get_environment("T2_COMMIT")
	if envc != "":
		return envc.strip_edges()
	var out := []
	OS.execute("git", ["-C", ProjectSettings.globalize_path("res://"), "rev-parse", "--short", "HEAD"], out, true)
	var re := RegEx.new()
	re.compile("^[0-9a-f]{4,16}$")
	for i in range(out.size() - 1, -1, -1):
		var s := str(out[i]).strip_edges()
		if s != "" and re.search(s) != null:
			return s
	return "unknown"
func _write_manifest() -> void:
	DirAccess.make_dir_recursive_absolute(SHOTS_DIR)
	var commit := _git_short_commit()
	var text := "# P7-V3.2 室内/楼梯/阁楼/门窗/猫 视觉取证清单\n\n- 运行时间: %s\n- commit: %s\n- 输出分辨率: 1600x900（原始帧 %s）\n- 目录: %s\n\n| 文件 | 内容 | 平均亮度 | 保存 |\n|---|---|---|---|\n" % [Time.get_datetime_string_from_system(), commit, str(_raw_size), SHOTS_DIR]
	for it in _manifest:
		text += "| %s | %s | %.3f | %s |\n" % [it["name"], it["desc"], it["luma"], it["err"]]
	var f := FileAccess.open(SHOTS_DIR + "MANIFEST.md", FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()