extends SceneTree
## task-7 视觉验证（1600x900 窗口，真实 main + isle.tscn）：
## 标题菜单点「开始游戏」走螺旋关闭 → 游玩中按 ESC 打开菜单，
## 截「进入动画中 / 稳定态」两张，并记录 8 个 item 的 rotation / scale / home 误差。
## 用法（GUI，非 headless）：console.exe --path <proj> --script res://tools/probe_task7_shots_t1.gd

const SHOTS := "D:/休闲小岛幻境/开发产物/shots6/t1/"
const LOG_PATH := "D:/休闲小岛幻境/开发产物/logs/probe_task7_shots.log"

var _lines: Array[String] = []
var _main: Node
var _menu: CanvasLayer

func _initialize() -> void:
	await process_frame
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_position(Vector2i(80, 40))
	for i in 3:
		await process_frame
	_log("window viewport=%s" % str(root.get_visible_rect().size))

	change_scene_to_file("res://isle.tscn")
	for i in 900:
		await process_frame
		_main = current_scene
		if _main != null and _main.has_method("_open_menu") and _main.get("_menu") != null:
			break
	if _main == null:
		_log("FATAL main not loaded")
		quit(1)
		return
	_menu = _main.get("_menu")
	# main._ready 会按已保存设置应用分辨率（可能改写窗口为 2560x1440），这里再强制 1600x900。
	await create_timer(1.8).timeout
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_position(Vector2i(80, 40))
	await create_timer(0.35).timeout
	for i in 3:
		await process_frame
	_menu.call("_layout")
	_log("window resized: visible=%s framebuffer=%s" % [str(root.get_visible_rect().size), str(root.get_texture().get_size())])
	_log("loaded; menu_visible=%s" % str(_menu.get("menu_visible")))
	await _snap("title", "title menu (start state)")
	# 标题菜单对照图（稳定态，1600x900）
	await _save_shot("title_menu_1600x900")

	# 真实玩家路径：点「开始游戏」→ 标题菜单螺旋飞出 → 摄像头过渡进游玩
	_menu.start_pressed.emit(false)
	_log("start pressed; waiting blend to_game ...")
	for i in 200:
		await create_timer(0.05).timeout
		if str(_main.get("_blending")) == "" and bool(_main.get("_started")):
			break
	await create_timer(0.4).timeout
	_log("playing; mode=%s blend=%s" % [str(_main.get("_mode")), str(_main.get("_blending"))])
	await _snap("after_flyout_hidden", "after title spiral close (menu hidden)")
	# 游戏内 HUD：右上操作提示含「C 自动运镜」、常驻指示含「按 C 切换」
	await _save_shot("15_hud_c_hint_1600x900")

	# 游玩中按 ESC：打开菜单（入场动画）。先把窗口稳定在 1600x900 再开菜单，
	# 避免"动画中途改窗口尺寸导致截到 resize 后的空帧"（13 号上次偏弱的根因假设）。
	await _force_window()
	await create_timer(0.35).timeout
	_log("before open: window=%s visible=%s" % [str(DisplayServer.window_get_size()), str(root.get_visible_rect().size)])
	_main.call("_open_menu")
	await create_timer(0.42).timeout
	var items0: Array = _menu.get("_items")
	var homes0: Array = _menu.get("_items_home")
	var dirs0: Array = _menu.get("_items_dir")
	var i0: Control = items0[0]
	_log("mid A t=%.3f onscreen_items=%d/%d" % [float(_menu.get("_anim_t")), _onscreen_items(), items0.size()])
	_log("diag item0 pos=%s size=%s home=%s dir=%s grect=%s alpha=%.2f vis=%s root_vis=%s layer_vis=%s vp=%s" % [str(i0.position), str(i0.size), str(homes0[0]), str(dirs0[0]), str(i0.get_global_rect()), i0.modulate.a, str(i0.visible), str((_menu.get("_menu_root") as Control).visible), str(_menu.visible), str(root.get_visible_rect().size)])
	await _save_shot_noresize("13a_esc_menu_enter_early_1600x900")
	await _snap("enter_early", "ESC menu enter t~0.45")
	await create_timer(0.13).timeout
	var mid_t := float(_menu.get("_anim_t"))
	_log("mid B t=%.3f onscreen_items=%d" % [mid_t, _onscreen_items()])
	await _save_shot_noresize("13_esc_menu_enter_mid_1600x900")
	await _snap("enter_mid", "ESC menu enter mid t=%.3f" % mid_t)
	await create_timer(0.16).timeout
	await _save_shot_noresize("13b_esc_menu_enter_late_1600x900")

	await create_timer(0.8).timeout
	await _snap("enter_done", "ESC menu settled")
	await _save_shot("14_esc_menu_stable_1600x900")

	# 稳定态数值校验（真实 main 流程）
	var homes: Array = _menu.get("_items_home")
	var items: Array = _menu.get("_items")
	var max_rot: float = 0.0
	var max_scale_err: float = 0.0
	var max_home_err: float = 0.0
	for i in items.size():
		var ctl: Control = items[i]
		max_rot = maxf(max_rot, absf(ctl.rotation))
		max_scale_err = maxf(max_scale_err, maxf(absf(ctl.scale.x - 1.0), absf(ctl.scale.y - 1.0)))
		if i < homes.size():
			max_home_err = maxf(max_home_err, ctl.position.distance_to(homes[i]))
	var verdict := "max_rot=%.5f max_scale_err=%.5f max_home_err=%.2fpx" % [max_rot, max_scale_err, max_home_err]
	_log("VERDICT " + verdict)
	_log("SUMMARY PASS=1 FAIL=0 | " + verdict if max_rot < 0.001 and max_scale_err < 0.001 and max_home_err < 0.5 else "SUMMARY PASS=0 FAIL=1 | " + verdict)
	_log("=== probe_task7_shots done ===")
	quit(0)

func _snap(tag: String, label: String) -> void:
	await process_frame
	var items: Array = _menu.get("_items")
	var homes: Array = _menu.get("_items_home")
	var max_rot: float = 0.0
	var max_scale_err: float = 0.0
	var max_home_err: float = 0.0
	for i in items.size():
		var ctl: Control = items[i]
		max_rot = maxf(max_rot, absf(ctl.rotation))
		max_scale_err = maxf(max_scale_err, maxf(absf(ctl.scale.x - 1.0), absf(ctl.scale.y - 1.0)))
		if i < homes.size():
			max_home_err = maxf(max_home_err, ctl.position.distance_to(homes[i]))
	_log("%s [%s] anim_state=%d t=%.3f rot=%.5f scale_err=%.5f home_err=%.2f visible=%s" % [tag, label, int(_menu.get("_anim_state")), float(_menu.get("_anim_t")), max_rot, max_scale_err, max_home_err, str(_menu.get("menu_visible"))])

func _force_window() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_position(Vector2i(80, 40))
	await create_timer(0.2).timeout
	for i in 3:
		await process_frame

## 统计当前有几个菜单项的可视矩形与视口相交（证明入场中途控件确实进入画面）。
func _onscreen_items() -> int:
	var items: Array = _menu.get("_items")
	var rect := root.get_visible_rect()
	var n := 0
	for ctl in items:
		var c := ctl as Control
		if c == null or not c.visible:
			continue
		var r := c.get_global_rect()
		if r.intersects(rect):
			n += 1
	return n

## 不改窗口尺寸的截图：动画中途使用，避免 resize 导致的空帧。
func _save_shot_noresize(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null:
		_log("SHOT FAIL " + name)
		return
	var raw_w: int = img.get_width()
	var raw_h: int = img.get_height()
	if raw_w != 1600 or raw_h != 900:
		img.resize(1600, 900, Image.INTERPOLATE_LANCZOS)
	var path := SHOTS + name + ".png"
	var err: int = img.save_png(path)
	_log("SHOT %s window=%s saved=%dx%d (raw %dx%d) err=%d onscreen=%d" % [path, str(DisplayServer.window_get_size()), img.get_width(), img.get_height(), raw_w, raw_h, err, _onscreen_items()])

func _save_shot(name: String) -> void:
	# 强制回到 1600x900 窗口化再截图（main 可能在启动后期按保存设置改写窗口尺寸）。
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await create_timer(0.2).timeout
	for i in 3:
		await process_frame
	_log("shot_now window=%s" % str(DisplayServer.window_get_size()))
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null:
		_log("SHOT FAIL " + name)
		return
	var raw_w: int = img.get_width()
	var raw_h: int = img.get_height()
	# 项目 canvas_items 拉伸下窗口 1600x900 的内部分辨率为设计分辨率 2560x1440，
	# 按窗口等比降采样后保存为 1600x900（同一画面内容，窗口实际显示比例）。
	if raw_w != 1600 or raw_h != 900:
		img.resize(1600, 900, Image.INTERPOLATE_LANCZOS)
	var path := SHOTS + name + ".png"
	var err: int = img.save_png(path)
	_log("SHOT %s window=%s saved=%dx%d (raw %dx%d) err=%d" % [path, str(DisplayServer.window_get_size()), img.get_width(), img.get_height(), raw_w, raw_h, err])

func _log(line: String) -> void:
	_lines.append(line)
	print("[t1-task7] " + line)
	var f := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")
		f.close()
