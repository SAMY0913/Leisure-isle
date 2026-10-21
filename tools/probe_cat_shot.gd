extends SceneTree
## P7-V3 任务 F：门廊猫窗口真实渲染截图（headless 会直接退出 1）
##
## 用途：把 scripts/isle_cat.gd 的 IsleCat.build() 放进真实主场景（isle.tscn → Cottage 门廊），
## 替换旧 PorchCat 后拍 正面 / 侧面 / 待机动作 近景，验证 toon 材质/描边/比例/部件衔接/贴地。
## 只摆镜头与姿势，不改正式场景/规则；cat 的 idle driver 在截图时冻结，用 debug_force_event 摆待机姿势。
##
## 运行（必须真实窗口）：
##   "D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe" --path "D:/休闲小岛幻境/游戏工程" \
##     --resolution 1600x900 --script res://tools/probe_cat_shot.gd

const CAT := preload("res://scripts/isle_cat.gd")
const SHOTS_DIR := "D:/休闲小岛幻境/开发产物/p7v3/shots/"
const LOG_DIR := "D:/休闲小岛幻境/开发产物/p7v3/logs/"
const CAT_LOCAL := Vector3(2.30, 0.47, 6.10)   # 与 cottage.gd 中 _cat 的世界/局部约定一致
const CAT_YAW := -0.6

var _main: Node = null
var _cat: Dictionary = {}
var _manifest: Array = []

func _initialize() -> void:
	print("=== P7-V3 CAT SHOTS START ===")
	if DisplayServer.get_name() == "headless":
		print("[CATSHOT] SKIP headless：真实渲染截图必须在窗口模式运行")
		quit(1)
		return
	await process_frame
	var packed: PackedScene = load("res://isle.tscn") as PackedScene
	if packed == null:
		print("[CATSHOT] FAIL 无法加载 res://isle.tscn")
		quit(1)
		return
	_main = packed.instantiate()
	get_root().add_child(_main)
	await process_frame
	await process_frame
	var menu = _main.get("_menu")
	if menu != null and menu.has_method("instant_finish"):
		menu.call("instant_finish")
	_main.set("_mode", 1)          # Mode.PLAYING
	_main.set("_time_source", "sim")
	_main.set("_realtime", false)
	_main.set("_started", true)
	_main.set("_paused", true)     # 冻结主场景模拟；镜头由 _pose_look 固定
	_main.set("_auto_orbit", false)
	_main.set("_blending", "")
	await process_frame
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await _settle(10)
	_set_time(16.6)                # 午后暖光，深灰猫毛/描边更清楚
	await _settle(3)

	# ---- 找 Cottage 根节点 ----
	var cottage_root: Node3D = null
	var cottage = _main.get("_cottage")
	if cottage is Dictionary and (cottage as Dictionary).has("root"):
		cottage_root = (cottage as Dictionary)["root"] as Node3D
	if cottage_root == null:
		cottage_root = get_root().find_child("Cottage", true, false) as Node3D
	if cottage_root == null:
		print("[CATSHOT] FAIL 未找到 Cottage 根节点（_cottage 与场景树都没有）")
		quit(1)
		return
	# ---- 替换旧 PorchCat（兼容 Lead 已集成 IsleCat 的情况：先移除再重建，保证用最新脚本）----
	var old := cottage_root.find_child("PorchCat", false, false) as Node3D
	if old != null:
		cottage_root.remove_child(old)
		old.queue_free()
		print("[CATSHOT] 移除已存在的 PorchCat（旧几何或旧版本）")
	# ---- 集成路径：与 Lead 将要写入 cottage.gd 的 _cat 完全一致 ----
	_cat = CAT.build(cottage_root, CAT_LOCAL, CAT_YAW)
	await process_frame
	var root: Node3D = _cat["root"] as Node3D
	var idle = _cat["idle"]
	if root == null or idle == null:
		print("[CATSHOT] FAIL IsleCat.build 返回空")
		quit(1)
		return
	(_cat["driver"] as Node).set_process(false)   # 截图期间冻结待机驱动，姿势手动摆
	idle.advance(0.05)
	await process_frame

	var cat_pos: Vector3 = root.global_position
	var fwd: Vector3 = root.global_transform.basis.z.normalized()
	var right: Vector3 = root.global_transform.basis.x.normalized()
	var up := Vector3.UP
	print("[CATSHOT] cat world=", cat_pos, " fwd=", fwd, " right=", right, " global_yaw=", rad_to_deg(root.global_rotation.y))
	var cam: Camera3D = _main.get("_cam")
	print("[CATSHOT] cam=", cam, " paused=", _main.get("_paused"))

	# 1) 正面近景（越过门廊中央台阶缺口拍摄，不挡栏杆）
	_pose(cat_pos + fwd * 2.15 - right * 0.80 + up * 0.86, cat_pos + up * 0.38, 40.0)
	await _shot("cat_front", cam, cat_pos,
		"正面近景：头身比 ≈1:2.2、三角耳+内耳、眼睛高光/竖瞳、口鼻胡须、前腿与爪贴地")
	# 2) 侧面近景（从门廊中央向右侧看轮廓）
	_pose(cat_pos - right * 1.50 + up * 0.60, cat_pos + up * 0.38, 40.0)
	await _shot("cat_side", cam, cat_pos,
		"侧面近景：坐姿轮廓、后腿收拢、3 节尾巴从身体根部自然弯曲")
	# 3) 待机动作近景：舔爪（头低 0.35rad + 前爪抬高 0.12）
	idle.debug_force_event("lick", 0.5)
	idle.advance(1.0 / 60.0)
	await process_frame
	print("[CATSHOT] lick state=", idle.debug_state())
	_pose(cat_pos + fwd * 1.70 - right * 0.45 + up * 0.82, cat_pos + up * 0.36, 40.0)
	await _shot("cat_idle", cam, cat_pos,
		"待机动作近景：舔爪（头低 0.35rad、单侧前爪抬起 0.12、头部侧偏）")
	# 4) 眨眼瞬间近景（验证眼睑动画几何）：先清掉舔爪姿势回到中性站姿
	idle.debug_clear_events()
	idle.debug_force_event("blink", 0.5)
	idle.advance(1.0 / 60.0)
	await process_frame
	print("[CATSHOT] blink state=", idle.debug_state())
	_pose(cat_pos + fwd * 1.22 + up * 0.72, cat_pos + up * 0.44, 38.0)
	await _shot("cat_blink", cam, cat_pos,
		"眨眼瞬间近景：眼睑闭合（验证眼睑枢轴/眼睑网格）", ["head", "eyes"])

	_write_manifest()
	print("[CATSHOT] RESULT shots=%d dir=%s" % [_manifest.size(), SHOTS_DIR])
	quit(0)

# ---------------------------------------------------------------
func _settle(n: int) -> void:
	for i in range(maxi(n, 0)):
		await process_frame

func _set_time(minutes: float) -> void:
	_main.call("_set_time_of_day", minutes)
	_main.call("_update_lighting")

func _pose(from: Vector3, target: Vector3, fov: float) -> void:
	_main.call("_pose_look", from, target, fov)

func _shot(shot_name: String, cam: Camera3D, cat_pos: Vector3, desc: String, keys: Array = []) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(SHOTS_DIR)
	var viewport: Viewport = _main.get_viewport()
	var img: Image = viewport.get_texture().get_image()
	var path := SHOTS_DIR + shot_name + ".png"
	var err := img.save_png(path)
	var lum := _mean_luma(img)
	var screen := ""
	if cam != null:
		screen = _screen_check(cam, cat_pos, keys)
	_manifest.append({
		"name": shot_name + ".png",
		"desc": desc,
		"size": "%dx%d" % [img.get_width(), img.get_height()],
		"mean_luma": snappedf(lum, 0.001),
		"screen": screen,
		"err": err,
	})
	print("[CATSHOT] SHOT %s %dx%d luma=%.3f err=%d screen=%s" % [shot_name, img.get_width(), img.get_height(), lum, err, screen])

func _mean_luma(img: Image) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var step := 16
	var sum := 0.0
	var n := 0
	for y in range(0, h, step):
		for x in range(0, w, step):
			var c := img.get_pixel(x, y)
			sum += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
	return sum / float(maxi(n, 1))

## 把猫的关键点投影到屏幕，确认 3 张近景里猫完整入画（head top / 身体中心 / 爪底）。
func _screen_check(cam: Camera3D, cat_pos: Vector3, keys: Array = []) -> String:
	var pts := {
		"head": cat_pos + Vector3(0.0, 0.70, 0.0),
		"eyes": cat_pos + Vector3(0.0, 0.55, 0.0),
		"body": cat_pos + Vector3(0.0, 0.38, 0.0),
		"paws": cat_pos + Vector3(0.0, 0.02, 0.0),
		"tail": cat_pos + Vector3(0.0, 0.50, 0.0),
	}
	var vp_size := Vector2(cam.get_viewport().get_visible_rect().size)
	var ok := true
	var parts: Array = []
	for key in (pts.keys() if keys.is_empty() else keys):
		var p: Vector3 = pts[key]
		var behind := cam.is_position_behind(p)
		var sp := cam.unproject_position(p)
		var inside := (not behind) and sp.x >= 0.0 and sp.y >= 0.0 and sp.x <= vp_size.x and sp.y <= vp_size.y
		if not inside:
			ok = false
		parts.append("%s=%d,%d%s" % [String(key), int(sp.x), int(sp.y), "!" if not inside else ""])
	return ("IN" if ok else "OUT") + "[" + ", ".join(parts) + "]"

func _write_manifest() -> void:
	DirAccess.make_dir_recursive_absolute(SHOTS_DIR)
	var path := SHOTS_DIR + "MANIFEST_cat.md"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("[CATSHOT] ERROR 无法写清单 ", path)
		return
	f.store_line("# P7-V3 猫咪窗口截图清单（真实渲染，1600×900）")
	f.store_line("")
	f.store_line("- 生成时间：%s" % Time.get_datetime_string_from_system())
	f.store_line("- 运行命令：\"D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe\" --path \"D:/休闲小岛幻境/游戏工程\" --resolution 1600x900 --script res://tools/probe_cat_shot.gd")
	f.store_line("- 场景：真实 isle.tscn → Cottage 门廊；旧 PorchCat 先移除，再由 IsleCat.build(cottage_root, Vector3(2.30,0.47,6.10), -0.6) 重建（与 Lead 集成路径一致）")
	f.store_line("- 姿势：idle driver 冻结，debug_force_event(lick/blink) 摆动作；仅截图用，不改正式运行规则。")
	f.store_line("- 时间：16:36（午后暖光），便于观察 toon 描边/明暗带。")
	f.store_line("")
	f.store_line("| 文件 | 内容 | 尺寸 | 平均亮度 | 猫关键点投影 |")
	f.store_line("| --- | --- | --- | --- | --- |")
	for m_v in _manifest:
		var m: Dictionary = m_v
		f.store_line("| %s | %s | %s | %.3f | %s |" % [String(m["name"]), String(m["desc"]), String(m["size"]), float(m["mean_luma"]), String(m["screen"])])
	f.close()
	print("[CATSHOT] MANIFEST ", path, " entries=", _manifest.size())
