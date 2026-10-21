extends SceneTree
## P7-V3 任务 A/B 视觉取证探针（真实窗口渲染）
## 覆盖：门扇半圆单体网格（正面/近景/斜侧/门内背面/开关门动画中途）、门廊对称灯具（白天/黄昏/夜间）
## 运行（必须真实窗口）：
##   "D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe" --path "D:/休闲小岛幻境/游戏工程" --resolution 1600x900 --script res://tools/probe_door_p7v3.gd

const SHOTS_DIR := "D:/休闲小岛幻境/开发产物/p7v3/shots/door/"
const COTTAGE_X := 0.8
const COTTAGE_Z := -0.6
const HOUSE_YAW := 0.30

var _main: Node = null
var _cottage: Dictionary = {}
var _cr: Node3D = null
var _n: Vector3 = Vector3.FORWARD   # 房屋正面朝向（世界）
var _side: Vector3 = Vector3.RIGHT
var _manifest: Array = []

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
	print("[P7V3D] window=", DisplayServer.window_get_size(), " door_pivot=", _cottage.get("door_pivot"))
	_dump_door_api()
	_set_time(745.0)
	await _section_day()
	_set_time(1050.0)
	await _section_dusk()
	_set_time(1305.0)
	await _section_night()
	await _section_interaction()
	_write_manifest()
	print("[P7V3D] RESULT shots=", _manifest.size(), " dir=", SHOTS_DIR)
	quit(0)

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
	var t := _local(Vector3(0.0, 1.75, 4.2))
	_pose(t + _n * 6.2 + Vector3(0.0, 0.30, 0.0), t, 46.0)
	await _settle(3)
	await _shot("door_front_day", "门正面：半圆气窗与拱券门框整体（正午）")
	var ta := _local(Vector3(0.0, 2.95, 4.2))
	_pose(ta + _n * 3.8 + Vector3(0.0, 0.25, 0.0), ta, 44.0)
	await _settle(3)
	await _shot("door_arch_close_day", "门上方半圆气窗 + 拱券近景（正午）")
	var tq := _local(Vector3(0.0, 2.0, 4.2))
	_pose(tq + _n * 4.6 + _side * 3.2 + Vector3(0.0, 1.0, 0.0), tq, 48.0)
	await _settle(3)
	await _shot("door_angle_day", "门体斜侧面：检查半圆厚度、侧壁与门板衔接（正午）")
	# 门内背面（从室内看门扇背面与气窗背面）
	var from_in := _local(Vector3(1.05, 1.95, 1.15))
	var to_in := _local(Vector3(1.05, 2.55, 4.15))
	_pose(from_in, to_in, 52.0)
	await _settle(3)
	await _shot("door_back_inside_day", "室内看门扇背面：半圆背面完整、无漏光（正午）")

func _section_dusk() -> void:
	await _settle(6)
	var t := _local(Vector3(0.0, 2.4, 5.6))
	_pose(t + _n * 9.5 + Vector3(0.0, 1.10, 0.0), t, 46.0)
	await _settle(3)
	await _shot("porch_wide_dusk", "门廊正面：左右对称灯具（黄昏）")

func _section_night() -> void:
	await _settle(6)
	var t := _local(Vector3(0.0, 2.4, 5.6))
	_pose(t + _n * 9.5 + Vector3(0.0, 1.10, 0.0), t, 46.0)
	await _settle(3)
	await _shot("porch_wide_night", "门廊正面：左右对称灯具亮度（深夜 21:45）")
	var ta := _local(Vector3(0.0, 2.95, 4.2))
	_pose(ta + _n * 3.8 + Vector3(0.0, 0.25, 0.0), ta, 44.0)
	await _settle(3)
	await _shot("door_arch_close_night", "门上方半圆气窗 + 拱券近景（深夜，灯光）")
	# 灯的近景左右各一张
	var lamp_l := _local(Vector3(-2.8, 3.2, 6.55))
	_pose(lamp_l + _n * 2.4 + _side * -1.0 + Vector3(0.0, 0.1, 0.0), lamp_l, 40.0)
	await _settle(3)
	await _shot("lamp_left_night", "门廊左吊灯近景（深夜）")
	var lamp_r := _local(Vector3(2.8, 3.2, 6.55))
	_pose(lamp_r + _n * 2.4 + _side * 1.0 + Vector3(0.0, 0.1, 0.0), lamp_r, 40.0)
	await _settle(3)
	await _shot("lamp_right_night", "门廊右吊灯近景（深夜，本次新增对称灯）")

func _section_interaction() -> void:
	# 1) 门关闭时点击门体（屏幕中心拾取由 _click_at 完成），验证仍然可开关
	_set_time(745.0)
	var t := _local(Vector3(0.0, 1.75, 4.2))
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

func _write_manifest() -> void:
	DirAccess.make_dir_recursive_absolute(SHOTS_DIR)
	var text := "# P7-V3 门/门廊灯视觉取证清单\n\n| 文件 | 内容 | 平均亮度 | 保存 |\n|---|---|---|---|\n"
	for it in _manifest:
		text += "| %s | %s | %.3f | %s |\n" % [it["name"], it["desc"], it["luma"], it["err"]]
	var f := FileAccess.open(SHOTS_DIR + "MANIFEST.md", FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()
