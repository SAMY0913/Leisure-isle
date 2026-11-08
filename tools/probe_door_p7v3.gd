extends SceneTree
## P7-V3 任务 A/B 视觉取证探针（真实窗口渲染）
## 覆盖：门扇半圆单体网格（正面/近景/斜侧/门内背面/开关门动画中途）、门廊对称灯具（白天/黄昏/夜间）
## 运行（必须真实窗口）：
##   "D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe" --path "D:/休闲小岛幻境/游戏工程" --resolution 1600x900 --script res://tools/probe_door_p7v3.gd

const SHOTS_DIR := "D:/休闲小岛幻境/开发产物/p7v32/shots/door/"
const COTTAGE_X := 0.8
const COTTAGE_Z := -0.6
const HOUSE_YAW := 0.30

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
var _hd := 3.1

func _initialize() -> void:
	print("=== P7V3 DOOR SHOTS START ===")
	if DisplayServer.get_name() == "headless":
		print("[P7V3D] SKIP headless：真实渲染截图必须在窗口模式运行")
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
	print("[P7V3D] window=", DisplayServer.window_get_size(), " viewport=", _main.get_viewport().get_visible_rect().size, " screen_scale=", DisplayServer.screen_get_scale(), " door_pivot=", _cottage.get("door_pivot"))
	_door_checks()
	_dump_door_api()
	_set_time(745.0)
	await _section_day()
	_set_time(1050.0)
	await _section_dusk()
	_set_time(1305.0)
	await _section_night()
	await _section_interaction()
	_write_manifest()
	print("[P7V3D] RESULT shots=", _manifest.size(), " checks=", _checks, " pass=", _checks - _fails, " fail=", _fails, " dir=", SHOTS_DIR)
	if _fails == 0:
		print("[P7V3D] RESULT_OK")
		quit(0)
	else:
		print("[P7V3D] RESULT_FAIL")
		quit(1)

func _ck(name: String, got: float, want: float, tol: float) -> void:
	_checks += 1
	if absf(got - want) <= tol:
		print("[P7V3D] OK   ", name, " got=", snappedf(got, 0.0001), " want=", snappedf(want, 0.0001))
	else:
		_fails += 1
		print("[P7V3D] FAIL ", name, " got=", snappedf(got, 0.0001), " want=", snappedf(want, 0.0001), " tol=", tol)

func _door_checks() -> void:
	# 从 IsleMath / IsleScaleSpec / build 返回 door_clear 与节点 meta 推导
	var C: Dictionary = _cr.get_meta("cottage_ctx", {})
	_fy = float(C.get("fy", 0.55))
	_hd = float(C.get("hd", 3.1))
	var dc: Dictionary = _cr.get_meta("door_clear", {})
	_ck("door_clear_w", float(dc.get("w", 0.0)), IsleScaleSpec.DOOR_CLEAR_W, 0.001)
	_ck("door_clear_h", float(dc.get("h", 0.0)), IsleScaleSpec.DOOR_CLEAR_H, 0.001)
	_ck("door_spring_y", float(dc.get("spring_y", 0.0)), _fy + 1.42, 0.001)
	_ck("door_arch_ri", float(dc.get("arch_ri", 0.0)), 0.52, 0.001)
	_ck("door_arch_ro", float(dc.get("arch_ro", 0.0)), 0.66, 0.001)
	_ck("door_fanlight_r", float(dc.get("fanlight_r", 0.0)), 0.50, 0.001)
	_ck("door_handle_h", float(dc.get("handle_h", 0.0)), IsleScaleSpec.DOOR_HANDLE_H, 0.001)
	_ck("door_leaf_w", float(dc.get("leaf_w", 0.0)), 1.00, 0.001)
	_ck("door_leaf_h", float(dc.get("leaf_h", 0.0)), 1.40, 0.001)
	_ck("wall_t", float(C.get("wall_t", 0.0)), IsleMath.HOUSE_WALL_T, 0.001)
	var pivot: Node3D = _cottage.get("door_pivot")
	if pivot == null:
		_fails += 1
		print("[P7V3D] FAIL DoorPivot missing")
	else:
		var pl: Vector3 = dc.get("pivot_local", Vector3.ZERO)
		_ck("pivot_local_x", pivot.position.x, pl.x, 0.001)
		_ck("pivot_local_y", pivot.position.y, pl.y, 0.001)
		_ck("pivot_local_z", pivot.position.z, pl.z, 0.001)
		_ck("pivot_rot_y", pivot.rotation.y, 0.0, 0.001)
	var arch := _cr.get_node_or_null("DoorArch")
	if arch != null and arch is Node3D:
		var ab: AABB = (arch as Node3D).get_aabb()
		_ck("arch_aabb_w", ab.size.x, 2.0 * 0.66, 0.03)
		_ck("arch_aabb_h", ab.size.y, 0.66, 0.03)
	var fan := pivot.get_node_or_null("DoorFanlight") if pivot != null else null
	if fan != null and fan is Node3D:
		var fb: AABB = (fan as Node3D).get_aabb()
		_ck("fanlight_w", fb.size.x, 1.00, 0.03)
		_ck("fanlight_h", fb.size.y, 0.50, 0.03)

func _dump_door_api() -> void:
	var pivot: Node3D = _cottage.get("door_pivot")
	var fan := pivot.get_node_or_null("DoorFanlight")
	var trim := pivot.get_node_or_null("DoorFanlightTrim")
	var arch := _cr.get_node_or_null("DoorArch")
	for item in [["DoorFanlight", fan], ["DoorFanlightTrim", trim], ["DoorArch", arch]]:
		var node = item[1]
		if node is MeshInstance3D:
			var aabb: AABB = (node as MeshInstance3D).get_aabb()
			print("[P7V3D] ", item[0], " mesh=", (node as MeshInstance3D).mesh, " aabb=", aabb, " surf=", (node as MeshInstance3D).mesh.get_surface_count())
		else:
			print("[P7V3D] MISSING ", item[0])

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

func _shot(shot_name: String, desc: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(SHOTS_DIR)
	var img: Image = _main.get_viewport().get_texture().get_image()
	if img.get_width() != 1600 or img.get_height() != 900:
		if _raw_size == Vector2i.ZERO:
			_raw_size = Vector2i(img.get_width(), img.get_height())
			print("[P7V3D] raw_frame=", _raw_size, " screen_scale=", DisplayServer.screen_get_scale())
		img.resize(1600, 900, Image.INTERPOLATE_LANCZOS)
	var path := SHOTS_DIR + shot_name + ".png"
	var err := img.save_png(path)
	var lum := _mean_luma(img)
	_manifest.append({"name": shot_name + ".png", "desc": desc, "luma": snappedf(lum, 0.001), "err": err})
	print("[P7V3D] SHOT ", shot_name, " luma=", snappedf(lum, 0.001), " err=", err)
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

func _section_day() -> void:
	await _settle(6)
	var t := _local(Vector3(0.0, _fy + 1.20, _hd + 1.10))
	_pose(t + _n * 6.2 + Vector3(0.0, 0.30, 0.0), t, 46.0)
	await _settle(3)
	await _shot("door_front_day", "门正面：半圆气窗与拱券门框整体（正午）")
	var ta := _local(Vector3(0.0, _fy + 1.95, _hd + 1.10))
	_pose(ta + _n * 3.8 + Vector3(0.0, 0.25, 0.0), ta, 44.0)
	await _settle(3)
	await _shot("door_arch_close_day", "门上方半圆气窗 + 拱券近景（正午）")
	var tq := _local(Vector3(0.0, _fy + 1.10, _hd + 1.10))
	_pose(tq + _n * 4.6 + _side * 3.2 + Vector3(0.0, 1.0, 0.0), tq, 48.0)
	await _settle(3)
	await _shot("door_angle_day", "门体斜侧面：检查半圆厚度、侧壁与门板衔接（正午）")
	# 门内背面（从室内看门扇背面与气窗背面）
	var from_in := _local(Vector3(1.05, _fy + 1.35, 1.15))
	var to_in := _local(Vector3(0.20, _fy + 1.50, _hd - 0.30))
	_pose(from_in, to_in, 52.0)
	await _settle(3)
	await _shot("door_back_inside_day", "室内看门扇背面：半圆背面完整、无漏光（正午）")

func _section_dusk() -> void:
	await _settle(6)
	var t := _local(Vector3(0.0, _fy + 1.85, 5.6))
	_pose(t + _n * 9.5 + Vector3(0.0, 1.10, 0.0), t, 46.0)
	await _settle(3)
	await _shot("porch_wide_dusk", "门廊正面：左右对称灯具（黄昏）")

func _section_night() -> void:
	await _settle(6)
	var t := _local(Vector3(0.0, _fy + 1.85, 5.6))
	_pose(t + _n * 9.5 + Vector3(0.0, 1.10, 0.0), t, 46.0)
	await _settle(3)
	await _shot("porch_wide_night", "门廊正面：左右对称灯具亮度（深夜 21:45）")
	var ta := _local(Vector3(0.0, _fy + 1.95, _hd + 1.10))
	_pose(ta + _n * 3.8 + Vector3(0.0, 0.25, 0.0), ta, 44.0)
	await _settle(3)
	await _shot("door_arch_close_night", "门上方半圆气窗 + 拱券近景（深夜，灯光）")
	# 灯的近景左右各一张
	var lamp_l := _local(Vector3(-1.95, 2.05, 4.55))
	_pose(lamp_l + _n * 2.4 + _side * -1.0 + Vector3(0.0, 0.1, 0.0), lamp_l, 40.0)
	await _settle(3)
	await _shot("lamp_left_night", "门廊左吊灯近景（深夜）")
	var lamp_r := _local(Vector3(1.95, 2.05, 4.55))
	_pose(lamp_r + _n * 2.4 + _side * 1.0 + Vector3(0.0, 0.1, 0.0), lamp_r, 40.0)
	await _settle(3)
	await _shot("lamp_right_night", "门廊右吊灯近景（深夜，本次新增对称灯）")

func _section_interaction() -> void:
	# 1) 门关闭时点击门体（屏幕中心拾取由 _click_at 完成），验证仍然可开关
	_set_time(745.0)
	var t := _local(Vector3(0.0, _fy + 1.20, _hd + 1.10))
	_pose(t + _n * 6.2 + Vector3(0.0, 0.30, 0.0), t, 46.0)
	await _settle(4)
	var pivot: Node3D = _cottage.get("door_pivot")
	var y0 := pivot.rotation.y
	_main.call("_click_at", Vector2(800.0, 430.0))
	await _settle(90)
	var y1 := pivot.rotation.y
	await _shot("door_open_day", "点击门后打开状态（正午，正面）")
	print("[P7V3D] CLICK door rot ", snappedf(y0, 0.001), " -> ", snappedf(y1, 0.001), " door_open=", _main.get("_door_open"))
	# 2) 关门动画中途
	_main.call("_click_at", Vector2(800.0, 430.0))
	await _settle(12)
	await _shot("door_anim_mid_day", "关门动画中途：门体旋转时半圆网格无穿模/枢轴异常（正午）")
	await _settle(80)
	# 3) 门轴/枢轴数值
	print("[P7V3D] DOOR final rot_y=", snappedf(pivot.rotation.y, 0.001), " pos=", pivot.position)

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
	var text := "# P7-V3.2 门/门廊灯视觉取证清单\n\n- 运行时间: %s\n- commit: %s\n- 输出分辨率: 1600x900（原始帧 %s）\n- 目录: %s\n\n| 文件 | 内容 | 平均亮度 | 保存 |\n|---|---|---|---|\n" % [Time.get_datetime_string_from_system(), commit, str(_raw_size), SHOTS_DIR]
	for it in _manifest:
		text += "| %s | %s | %.3f | %s |\n" % [it["name"], it["desc"], it["luma"], it["err"]]
	var f := FileAccess.open(SHOTS_DIR + "MANIFEST.md", FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()
