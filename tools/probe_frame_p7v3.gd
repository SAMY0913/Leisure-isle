extends SceneTree
## P7-V3 通用窗口截图 harness（QA / task-5 第二阶段）
##
## 用途：给 Lead 与各负责人快速拍验收图。所有截图落 开发产物/p7v3/shots/frame/，并写 MANIFEST.md。
## 运行（真实窗口；GPU 必须串行，见 docs/P7_V3_QA_NOTES.md 的锁约定）：
##   ENG --path PROJ --resolution 1600x900 --script res://tools/probe_frame_p7v3.gd -- --stage=all
##
## 参数（-- 之后的用户参数，支持 --key=value 与 --key value 两种写法）：
##   --stage=all|door|porch|interior|stairs|boat|cat   逗号可组合，如 --stage=door,porch
##   --out=<目录>      覆盖输出目录（默认 D:/休闲小岛幻境/开发产物/p7v3/shots/frame/）
##   --fov=<度>        覆盖门/室内等机位的默认 FOV（默认 42）
##
## 输出标记：[P7V3F] STAGE/SHOT/SKIP 行，结尾 [P7V3F] RESULT shots=N skipped=K dir=...
## headless 下会直接 quit(1)（截图必须真实渲染）。

const DEFAULT_OUT := "D:/休闲小岛幻境/开发产物/p7v3/shots/frame/"
const SHOT_W := 1600
const SHOT_H := 900
const T_DAY := 745.0
const T_DUSK := 1050.0
const T_NIGHT := 1305.0

var _main: Node = null
var _cottage: Dictionary = {}
var _cr: Node3D = null
var _n := Vector3.FORWARD      # 房屋正面朝向（世界坐标）
var _side := Vector3.RIGHT     # 房屋 +X（世界坐标）
var _out := DEFAULT_OUT
var _stages: Array = []
var _manifest: Array = []
var _skipped: Array = []
var _fov := 42.0
var _stair_nodes: Array = []
var _stair_ok := false
var _cat_ok := false
var _cat_script_ok := false

func _initialize() -> void:
	_parse_args()
	print("=== P7V3 FRAME HARNESS START ===")
	if DisplayServer.get_name() == "headless":
		print("[P7V3F] SKIP headless：截图 harness 必须在真实窗口运行")
		quit(1)
		return
	var ok: bool = await _setup_scene()
	if not ok:
		print("[P7V3F] FAIL 场景初始化失败")
		quit(1)
		return
	print("[P7V3F] setup window=", DisplayServer.window_get_size(), " out=", _out, " stages=", _stages)
	_set_time(T_DAY)
	await _settle(2)
	for st in _stages:
		match String(st):
			"door": await _stage_door()
			"porch", "lamp": await _stage_porch()
			"interior": await _stage_interior()
			"stairs": await _stage_stairs()
			"boat": await _stage_boat()
			"cat": await _stage_cat()
			_: print("[P7V3F] SKIP 未知 stage=", st)
	_write_manifest()
	print("[P7V3F] RESULT shots=", _manifest.size(), " skipped=", _skipped.size(), " dir=", _out)
	if _manifest.is_empty():
		quit(1)
	else:
		quit(0)

# ============================================================
# 参数 / 初始化
# ============================================================
func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var stage_arg := "all"
	var i := 0
	while i < args.size():
		var a: String = args[i]
		var key := a
		var val := ""
		if a.begins_with("--") and a.contains("="):
			var eq := a.find("=")
			key = a.substr(0, eq)
			val = a.substr(eq + 1)
		elif a.begins_with("--") and i + 1 < args.size() and not String(args[i + 1]).begins_with("--"):
			key = a
			val = String(args[i + 1])
			i += 1
		match key:
			"--stage": stage_arg = val
			"--out": _out = val
			"--fov": _fov = clampf(float(val), 20.0, 90.0)
		i += 1
	if _out.length() > 0 and not _out.ends_with("/"):
		_out += "/"
	for s in stage_arg.split(",", false):
		var t := String(s).strip_edges()
		if t.length() > 0:
			_stages.append(t)
	if _stages.has("all"):
		_stages = ["door", "porch", "interior", "stairs", "boat", "cat"]

func _setup_scene() -> bool:
	await process_frame
	var packed: PackedScene = load("res://isle.tscn") as PackedScene
	if packed == null:
		print("[P7V3F] FAIL isle.tscn 加载失败")
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
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))
	await _settle(10)
	_cottage = _main.get("_cottage")
	_cr = _cottage.get("root") as Node3D
	if _cr == null:
		print("[P7V3F] FAIL 找不到 cottage root")
		return false
	_n = (_cr.global_transform.basis * Vector3(0.0, 0.0, 1.0)).normalized()
	_side = (_cr.global_transform.basis * Vector3(1.0, 0.0, 0.0)).normalized()
	_stair_nodes = _find_named(_cr, ["stair", "flight", "landing", "tread", "railing", "banister"])
	_stair_ok = not _stair_nodes.is_empty()
	var cat := _find_first_named(_cr, ["porchcat"])
	if cat == null:
		cat = _find_first_named(_cr, ["cat"])
	_cat_ok = cat != null
	if _cat_ok:
		_cat_script_ok = cat.get_script() != null or cat.has_meta("isle_cat") or cat.get_node_or_null("CatIdleDriver") != null
	print("[P7V3F] stair_nodes=", _stair_nodes.size(), " cat=", _cat_ok, " cat_new_impl=", _cat_script_ok)
	for sn in _stair_nodes:
		print("[P7V3F]   stair node: ", (sn as Node).get_path())
	return true

# ============================================================
# 通用工具
# ============================================================
func _settle(n: int) -> void:
	for i in range(maxi(n, 0)):
		await process_frame

func _set_time(minutes: float) -> void:
	_main.call("_set_time_of_day", minutes)
	_main.call("_update_lighting")

func _pose(from: Vector3, target: Vector3, fov: float) -> void:
	_main.call("_pose_look", from, target, fov)

## 房屋局部坐标 -> 世界坐标
func _local(p: Vector3) -> Vector3:
	return _cr.global_transform * p

func _shot(shot_name: String, desc: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(_out)
	var img: Image = _main.get_viewport().get_texture().get_image()
	var path := _out + shot_name + ".png"
	var err := img.save_png(path)
	var lum := _mean_luma(img)
	_manifest.append({"name": shot_name + ".png", "desc": desc, "luma": snappedf(lum, 0.001), "err": err})
	print("[P7V3F] SHOT ", shot_name, " luma=", snappedf(lum, 0.001), " err=", err, " desc=", desc)
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

func _find_named(root: Node, needles: Array) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n == root:
			continue
		var low := String(n.name).to_lower()
		for nd in needles:
			if low.contains(String(nd)):
				out.append(n)
				break
	return out

func _find_first_named(root: Node, needles: Array) -> Node:
	var hits := _find_named(root, needles)
	return hits[0] as Node if not hits.is_empty() else null

# ============================================================
# stage: door —— 门正面/斜侧/背面/拱券近景/开关门
# ============================================================
func _stage_door() -> void:
	print("[P7V3F] STAGE door")
	_set_time(T_DAY)
	await _settle(6)
	var pivot: Node3D = _cottage.get("door_pivot") as Node3D
	if pivot != null:
		pivot.rotation.y = 0.0
		_main.set("_door_open", false)
		var fan := pivot.get_node_or_null("DoorFanlight")
		var trim := pivot.get_node_or_null("DoorFanlightTrim")
		print("[P7V3F] door fanlight=", fan, " trim=", trim, " arch=", _cr.get_node_or_null("DoorArch"))
		await _settle(2)
	var t := _local(Vector3(0.0, 1.75, 4.2))
	_pose(t + _n * 6.4 + Vector3(0.0, 0.35, 0.0), t, _fov)
	await _settle(3)
	await _shot("door_front_day", "门正面全貌：半圆气窗 + 拱券门框 + 门廊灯（正午）")
	var ta := _local(Vector3(0.0, 2.95, 4.2))
	_pose(ta + _n * 3.9 + Vector3(0.0, 0.25, 0.0), ta, _fov + 2.0)
	await _settle(3)
	await _shot("door_arch_close_day", "拱券 + 半圆气窗近景（正午）")
	var tq := _local(Vector3(0.0, 2.0, 4.2))
	_pose(tq + _n * 4.6 + _side * 3.2 + Vector3(0.0, 1.0, 0.0), tq, _fov + 6.0)
	await _settle(3)
	await _shot("door_angle_left_day", "门体左斜侧：半圆厚度/侧壁/门板衔接（正午）")
	_pose(tq + _n * 4.6 - _side * 3.2 + Vector3(0.0, 1.0, 0.0), tq, _fov + 6.0)
	await _settle(3)
	await _shot("door_angle_right_day", "门体右斜侧：半圆厚度/侧壁/门板衔接（正午）")
	_pose(_local(Vector3(1.05, 1.95, 1.15)), _local(Vector3(1.05, 2.55, 4.15)), _fov + 10.0)
	await _settle(3)
	await _shot("door_back_inside_day", "室内看门扇背面：半圆背面完整、无漏光（正午）")
	_pose(_local(Vector3(0.0, 2.4, -7.6)), _local(Vector3(0.0, 2.2, -4.2)), _fov + 6.0)
	await _settle(3)
	await _shot("house_back_day", "房屋背面远景（正午）")
	_pose(t + _n * 6.4 + Vector3(0.0, 0.35, 0.0), t, _fov)
	await _settle(4)
	var y0 := pivot.rotation.y if pivot != null else 0.0
	_main.call("_click_at", Vector2(float(SHOT_W) * 0.5, float(SHOT_H) * 0.48))
	await _settle(64)
	var y1 := pivot.rotation.y if pivot != null else 0.0
	await _shot("door_open_day", "点击开门后（正午，正面）")
	print("[P7V3F] door click open rot ", snappedf(y0, 0.001), " -> ", snappedf(y1, 0.001), " door_open=", _main.get("_door_open"))
	_main.call("_click_at", Vector2(float(SHOT_W) * 0.5, float(SHOT_H) * 0.48))
	await _settle(12)
	await _shot("door_anim_mid_day", "关门动画中途：旋转时半圆网格无穿模/枢轴异常（正午）")
	await _settle(72)
	await _shot("door_closed_day", "关门完成后（正午）")
	if pivot != null:
		print("[P7V3F] door final rot_y=", snappedf(pivot.rotation.y, 0.001), " pos=", pivot.position)

# ============================================================
# stage: porch —— 门廊对称灯 白天/黄昏/夜间 + 灯近景
# ============================================================
func _stage_porch() -> void:
	print("[P7V3F] STAGE porch")
	var t := _local(Vector3(0.0, 2.4, 5.6))
	var wide := t + _n * 9.5 + Vector3(0.0, 1.10, 0.0)
	_set_time(T_DAY)
	await _settle(6)
	_pose(wide, t, _fov + 4.0)
	await _settle(3)
	await _shot("porch_wide_day", "门廊正面全景：左右对称吊灯（正午）")
	_set_time(T_DUSK)
	await _settle(6)
	_pose(wide, t, _fov + 4.0)
	await _settle(3)
	await _shot("porch_wide_dusk", "门廊正面全景：左右对称吊灯（黄昏 17:30）")
	_set_time(T_NIGHT)
	await _settle(6)
	_pose(wide, t, _fov + 4.0)
	await _settle(3)
	await _shot("porch_wide_night", "门廊正面全景：左右对称吊灯亮度（深夜 21:45）")
	var lamp_l := _local(Vector3(-2.8, 3.2, 6.55))
	_pose(lamp_l + _n * 2.4 - _side * 1.0 + Vector3(0.0, 0.1, 0.0), lamp_l, _fov - 2.0)
	await _settle(3)
	await _shot("lamp_left_night", "门廊左吊灯近景（深夜）")
	var lamp_r := _local(Vector3(2.8, 3.2, 6.55))
	_pose(lamp_r + _n * 2.4 + _side * 1.0 + Vector3(0.0, 0.1, 0.0), lamp_r, _fov - 2.0)
	await _settle(3)
	await _shot("lamp_right_night", "门廊右吊灯近景（深夜）")
	_pose(_local(Vector3(0.0, 1.8, 8.4)), _local(Vector3(0.0, 2.1, 4.2)), _fov + 8.0)
	await _settle(3)
	await _shot("porch_doorway_night", "夜间门洞近景：检查门口是否过曝/窗灯是否被挤掉")

# ============================================================
# stage: interior —— 一层四角 + 二层（阁楼）+ 阁楼窗
# ============================================================
func _stage_interior() -> void:
	print("[P7V3F] STAGE interior")
	_set_time(T_DAY)
	await _settle(6)
	var corners := [
		{"n": "interior_corner_fl", "from": Vector3(-4.35, 2.05, 3.35), "to": Vector3(2.8, 1.10, -2.6), "d": "一层室内：前左角看全屋（正午）"},
		{"n": "interior_corner_fr", "from": Vector3(4.35, 2.05, 3.35), "to": Vector3(-2.8, 1.10, -2.6), "d": "一层室内：前右角看全屋（正午，楼梯侧）"},
		{"n": "interior_corner_br", "from": Vector3(4.35, 2.05, -3.35), "to": Vector3(-2.8, 1.20, 2.6), "d": "一层室内：后右角看全屋（正午）"},
		{"n": "interior_corner_bl", "from": Vector3(-4.35, 2.05, -3.35), "to": Vector3(2.8, 1.20, 2.6), "d": "一层室内：后左角看全屋（正午）"},
	]
	for c in corners:
		_pose(_local(c["from"]), _local(c["to"]), _fov + 14.0)
		await _settle(3)
		await _shot(c["n"], c["d"])
	_pose(_local(Vector3(-2.2, 1.9, -1.6)), _local(Vector3(0.4, 2.0, 4.2)), _fov + 10.0)
	await _settle(3)
	await _shot("interior_view_door", "一层室内看门口/半圆气窗背光（正午）")
	var attic_win: Vector3 = _cottage.get("attic_window_world", Vector3.ZERO)
	var aw_ok := attic_win.length_squared() > 1.0
	print("[P7V3F] attic_window_world=", attic_win, " ok=", aw_ok)
	_pose(_local(Vector3(-1.2, 6.85, 2.4)), _local(Vector3(1.6, 5.95, -2.2)), _fov + 18.0)
	await _settle(3)
	await _shot("floor2_room_day", "二层（阁楼）室内全景（正午）")
	_pose(_local(Vector3(2.9, 6.85, -0.2)), _local(Vector3(4.35, 5.20, -3.2)), _fov + 20.0)
	await _settle(3)
	await _shot("floor2_stairwell_day", "二层楼梯洞口边缘俯视（楼梯未集成时为空房对比）")
	if aw_ok:
		_pose(attic_win - _n * 2.6 + Vector3(0.0, 0.15, 0.0), attic_win, _fov + 8.0)
		await _settle(3)
		await _shot("attic_window_inside_day", "室内看阁楼窗（正午）")

# ============================================================
# stage: stairs —— 楼梯上下/平台/踏步近景/洞口
# ============================================================
func _stage_stairs() -> void:
	print("[P7V3F] STAGE stairs (stair_nodes=", _stair_nodes.size(), ")")
	var note := "" if _stair_ok else "（楼梯尚未集成：本组为占位对比图，不可作为验收依据）"
	_set_time(T_DAY)
	await _settle(6)
	_pose(_local(Vector3(4.25, 1.85, 2.9)), _local(Vector3(4.25, 3.00, -2.6)), _fov + 20.0)
	await _settle(3)
	await _shot("stairs_up_day", "楼梯第一跑：自一层向上" + note)
	_pose(_local(Vector3(2.95, 4.75, -1.1)), _local(Vector3(4.35, 3.50, -3.1)), _fov + 20.0)
	await _settle(3)
	await _shot("stairs_landing_day", "楼梯平台/转向处" + note)
	_pose(_local(Vector3(2.30, 6.90, -3.2)), _local(Vector3(4.30, 4.60, -3.0)), _fov + 18.0)
	await _settle(3)
	await _shot("stairs_top_day", "楼梯第二跑：自二层俯视" + note)
	_pose(_local(Vector3(3.0, 2.0, 0.3)), _local(Vector3(4.25, 2.2, -0.8)), _fov + 13.0)
	await _settle(3)
	await _shot("stairs_steps_close_day", "楼梯踏步近景：踏面/高差" + note)
	_pose(_local(Vector3(1.2, 6.90, -0.4)), _local(Vector3(4.2, 5.6, -2.4)), _fov + 23.0)
	await _settle(3)
	await _shot("stairs_hole_day", "楼板洞口 + L 形楼梯整体" + note)

# ============================================================
# stage: boat —— 停泊/近岸巡航/甲板近景/夜间
# ============================================================
func _stage_boat() -> void:
	print("[P7V3F] STAGE boat")
	var sailboat: Node3D = _main.get("_sailboat") as Node3D
	if sailboat == null:
		print("[P7V3F] SKIP 找不到 _sailboat")
		_skipped.append("boat:no_sailboat")
		return
	var wd: Dictionary = _main.get("_world")
	print("[P7V3F] boat state=", _main.get("_boat_state"), " world_pos=", sailboat.global_position, " sail_dock_pos=", wd.get("sail_dock_pos", Vector3.ZERO))
	_set_time(T_DAY)
	await _settle(6)
	_boat_shot_pack("boat_dock_day", "小船停泊全景：甲板分段/内舱/属具（正午）")
	var routes: Array = _main.get("_sail_routes")
	var route: Dictionary = {}
	for r in routes:
		if String((r as Dictionary).get("kind", "")) == "coastal":
			route = r
			break
	if route.is_empty() and routes.size() > 0:
		route = routes[0]
	if not route.is_empty():
		_main.call("_shot_boat_cruise", route, 0.28)
		await _settle(2)
		print("[P7V3F] cruise route=", String(route.get("name", "?")), " kind=", String(route.get("kind", "?")), " pos=", sailboat.global_position)
		_boat_shot_pack("boat_cruise_day", "小船近岸巡航：帆/舱/尾灯/水花（正午）")
		_set_time(T_NIGHT)
		await _settle(6)
		_boat_shot_pack("boat_cruise_night", "小船夜间巡航：尾灯/探照灯（深夜）")
	else:
		_skipped.append("boat:no_routes")

## 围绕当前小船位置拍一组（船体侧后 / 甲板近景）
func _boat_shot_pack(prefix: String, desc_main: String) -> void:
	var sailboat: Node3D = _main.get("_sailboat") as Node3D
	if sailboat == null:
		return
	var bp := sailboat.global_position
	var bbasis := sailboat.global_transform.basis
	_pose(bp + bbasis * Vector3(3.4, 2.2, 3.4), bp + Vector3(0.0, 0.55, 0.0), _fov)
	await _settle(3)
	await _shot(prefix, desc_main)
	_pose(bp + bbasis * Vector3(0.9, 1.75, 2.0), bp + bbasis * Vector3(0.0, 0.60, 0.1), _fov - 2.0)
	await _settle(3)
	await _shot(prefix + "_deck_close", desc_main + "（甲板/内舱近景）")

# ============================================================
# stage: cat —— 门廊猫近景/侧景/夜景
# ============================================================
func _stage_cat() -> void:
	print("[P7V3F] STAGE cat")
	var cat: Node3D = _find_first_named(_cr, ["porchcat"]) as Node3D
	if cat == null:
		cat = _find_first_named(_cr, ["cat"]) as Node3D
	if cat == null:
		print("[P7V3F] SKIP 找不到门廊猫")
		_skipped.append("cat:not_found")
		return
	_cat_ok = true
	_cat_script_ok = cat.get_script() != null or cat.has_meta("isle_cat") or cat.get_node_or_null("CatIdleDriver") != null
	print("[P7V3F] cat path=", cat.get_path(), " pos=", cat.global_position, " script=", cat.get_script(), " new_impl=", _cat_script_ok)
	var kids: Array = []
	for k in cat.get_children():
		kids.append(String(k.name))
	print("[P7V3F] cat children=", kids)
	var drv := cat.get_node_or_null("CatIdleDriver")
	if drv != null and drv.get("controller") != null:
		var ctl = drv.get("controller")
		if ctl != null and ctl.has_method("debug_state"):
			print("[P7V3F] cat idle=", ctl.call("debug_state"))
	_set_time(T_DAY)
	await _settle(6)
	var cp := cat.global_position
	var cfwd := (cat.global_transform.basis * Vector3(0.0, 0.0, 1.0)).normalized()
	var cside := (cat.global_transform.basis * Vector3(1.0, 0.0, 0.0)).normalized()
	_pose(cp + cfwd * 1.25 + Vector3(0.0, 0.80, 0.0), cp + Vector3(0.0, 0.26, 0.0), _fov - 7.0)
	await _settle(3)
	await _shot("cat_close_front_day", "门廊猫正面近景：面部/眼睛/耳朵/胸脯（正午）")
	_pose(cp + cfwd * 0.9 + cside * 1.1 + Vector3(0.0, 0.72, 0.0), cp + Vector3(0.0, 0.25, 0.0), _fov - 5.0)
	await _settle(3)
	await _shot("cat_close_side_day", "门廊猫侧前近景：坐姿/尾巴/前爪（正午）")
	_pose(cp - cside * 1.1 + cfwd * 0.4 + Vector3(0.0, 0.55, 0.0), cp + Vector3(0.0, 0.22, 0.0), _fov - 5.0)
	await _settle(3)
	await _shot("cat_back_day", "门廊猫后侧：尾巴节段/后臀（正午）")
	_pose(_local(Vector3(0.0, 2.0, 8.9)), cp + Vector3(0.0, 0.35, 0.0), _fov + 8.0)
	await _settle(3)
	await _shot("cat_porch_wide_day", "门廊全景含猫：猫与长椅/吊灯/门的比例（正午）")
	_set_time(T_NIGHT)
	await _settle(6)
	_pose(cp + cfwd * 1.25 + Vector3(0.0, 0.80, 0.0), cp + Vector3(0.0, 0.26, 0.0), _fov - 7.0)
	await _settle(3)
	await _shot("cat_close_front_night", "门廊猫正面近景（深夜，门廊灯下）")

# ============================================================
# MANIFEST
# ============================================================
func _write_manifest() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	var text := "# P7-V3 通用截图 harness 清单\n\n"
	text += "- 输出目录：" + _out + "\n"
	text += "- stage：" + str(_stages) + "\n"
	text += "- 楼梯节点：%d（%s）\n" % [_stair_nodes.size(), "已集成" if _stair_ok else "未集成/未发现"]
	text += "- 门廊猫：new_impl=%s\n" % str(_cat_script_ok if _cat_ok else false)
	text += "- 跳过：" + str(_skipped) + "\n\n"
	text += "| 文件 | 内容 | 平均亮度 | 保存 |\n|---|---|---|---|\n"
	for it in _manifest:
		text += "| %s | %s | %.3f | %s |\n" % [it["name"], it["desc"], it["luma"], it["err"]]
	var f := FileAccess.open(_out + "MANIFEST.md", FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()
