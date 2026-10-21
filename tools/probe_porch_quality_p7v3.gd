extends SceneTree
## P7-V3 门廊亮度质量对比探针（QA / task-5 冻结后窗口期）
## 目的：同一门廊机位，在默认画质 q2 与最高画质 q4（预算 9 vs 12 盏）下拍白天/黄昏/夜景，
##       量化门廊平均亮度，回答「最高画质夜间门廊是否比 V2/默认画质暗」的验收问题。
## 运行（真实窗口，持 GPU 锁）：
##   ENG --path PROJ --resolution 1600x900 --script res://tools/probe_porch_quality_p7v3.gd
## 输出：开发产物/p7v3/shots/porchq/ + MANIFEST.md（含平均亮度/ROI 亮度/灯光预算）
## 标记：[P7V3Q] 行；结尾 [P7V3Q] RESULT shots=N

const SHOTS_DIR := "D:/休闲小岛幻境/开发产物/p7v3/shots/porchq/"

var _main: Node = null
var _cottage: Dictionary = {}
var _cr: Node3D = null
var _n: Vector3 = Vector3.FORWARD
var _side: Vector3 = Vector3.RIGHT
var _manifest: Array = []

func _initialize() -> void:
	print("=== P7V3 PORCH QUALITY START ===")
	if DisplayServer.get_name() == "headless":
		print("[P7V3Q] SKIP headless：真实渲染截图必须在窗口模式运行")
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
	var tgt := _local(Vector3(0.0, 2.4, 5.6))
	for q in [2, 4]:
		_main.call("_apply_quality", q)
		await _settle(8)
		var lights: Array = _main.get("_lights")
		print("[P7V3Q] quality=", q, " light_budget=", _main.get("_light_budget"), " active_lights=", lights.size())
		for item in [["day", 745.0], ["dusk", 1050.0], ["night", 1305.0]]:
			_set_time(float(item[1]))
			_main.call("_collect_lights")
			await _settle(8)
			_pose(tgt + _n * 9.5 + Vector3(0.0, 1.10, 0.0), tgt, 46.0)
			await _settle(4)
			await _shot("porch_q%d_%s" % [q, item[0]], "门廊正面 q%d %s（左/右吊灯亮度与对称性）" % [q, item[0]])
	# 夜间门廊灯近景（q2/q4）便于逐灯对比
	for q in [2, 4]:
		_main.call("_apply_quality", q)
		_set_time(1305.0)
		_main.call("_collect_lights")
		await _settle(8)
		var lamp_l := _local(Vector3(-2.8, 3.2, 6.55))
		_pose(lamp_l + _n * 2.4 + _side * -1.0 + Vector3(0.0, 0.1, 0.0), lamp_l, 40.0)
		await _settle(4)
		await _shot("lamp_left_night_q%d" % q, "门廊左吊灯近景 q%d（夜间）" % q)
		var lamp_r := _local(Vector3(2.8, 3.2, 6.55))
		_pose(lamp_r + _n * 2.4 + _side * 1.0 + Vector3(0.0, 0.1, 0.0), lamp_r, 40.0)
		await _settle(4)
		await _shot("lamp_right_night_q%d" % q, "门廊右吊灯近景 q%d（夜间）" % q)
	_write_manifest()
	print("[P7V3Q] RESULT shots=", _manifest.size(), " dir=", SHOTS_DIR)
	quit(0)

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
	var roi := _mean_luma_roi(img, 0.2, 0.15, 0.8, 0.75)
	_manifest.append({"name": shot_name + ".png", "desc": desc, "luma": snappedf(lum, 0.001), "roi_luma": snappedf(roi, 0.001), "err": err})
	print("[P7V3Q] SHOT ", shot_name, " luma=", snappedf(lum, 0.001), " roi=", snappedf(roi, 0.001), " err=", err)
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

func _mean_luma_roi(img: Image, x0: float, y0: float, x1: float, y1: float) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var xa := int(float(w) * x0)
	var xb := int(float(w) * x1)
	var ya := int(float(h) * y0)
	var yb := int(float(h) * y1)
	var step := 12
	var acc := 0.0
	var cnt := 0
	for y in range(ya, yb, step):
		for x in range(xa, xb, step):
			var c := img.get_pixel(x, y)
			acc += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			cnt += 1
	return acc / float(maxi(cnt, 1))

func _write_manifest() -> void:
	DirAccess.make_dir_recursive_absolute(SHOTS_DIR)
	var text := "# P7-V3 门廊亮度 q2/q4 对比清单\n\n| 文件 | 内容 | 全图亮度 | 门廊 ROI 亮度 | 保存 |\n|---|---|---|---|---|\n"
	for it in _manifest:
		text += "| %s | %s | %.3f | %.3f | %s |\n" % [it["name"], it["desc"], it["luma"], it["roi_luma"], it["err"]]
	var f := FileAccess.open(SHOTS_DIR + "MANIFEST.md", FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()
