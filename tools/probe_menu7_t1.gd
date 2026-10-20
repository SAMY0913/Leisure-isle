extends SceneTree
## T1 / task-7 回归探针：
## 1) 标题菜单螺旋关闭（_fly_out 写入 rotation/scale）后 open(true)，ESC 菜单入场全程
##    rotation=0 / scale=ONE / position 回到 home；反复开关、动画中反转均不漂移。
## 2) HUD 右上操作提示与自动运镜常驻指示包含 C 键提示，H 隐藏界面时一起隐藏。
## 用法：console.exe --headless --path <proj> --script res://tools/probe_menu7_t1.gd

const MenuScript := preload("res://scripts/menu.gd")
const HudScript := preload("res://scripts/hud.gd")

const LOG_PATH := "D:/休闲小岛幻境/开发产物/logs/probe_menu7_t1.log"

var _pass: int = 0
var _fail: int = 0
var _lines: Array[String] = []
var _vp: SubViewport
var _menu: CanvasLayer

func _initialize() -> void:
	await process_frame
	_write_log("=== probe_menu7_t1 (rotation residue + HUD C hint) ===")
	await _test_menu_rotation()
	await _test_hud_c_hint()
	var summary := "SUMMARY PASS=%d FAIL=%d" % [_pass, _fail]
	print(summary)
	_write_log(summary)
	quit(0 if _fail == 0 else 1)

func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		_write_log("PASS " + name + ("" if detail.is_empty() else " | " + detail))
	else:
		_fail += 1
		_write_log("FAIL " + name + ("" if detail.is_empty() else " | " + detail))

func _write_log(line: String) -> void:
	_lines.append(line)
	var f := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")
		f.close()

func _wait(sec: float) -> void:
	await create_timer(sec).timeout

func _snapshot() -> Array:
	var out: Array = []
	for item in _menu.get("_items"):
		var ctl: Control = item
		out.append({"rot": ctl.rotation, "scale": ctl.scale, "pos": ctl.position, "a": ctl.modulate.a, "vis": ctl.visible})
	return out

func _max_rot(snap: Array) -> float:
	var m: float = 0.0
	for s in snap:
		m = maxf(m, absf(float(s["rot"])))
	return m

func _max_scale_err(snap: Array) -> float:
	var m: float = 0.0
	for s in snap:
		var sc: Vector2 = s["scale"]
		m = maxf(m, maxf(absf(sc.x - 1.0), absf(sc.y - 1.0)))
	return m

func _max_home_err(snap: Array) -> float:
	var homes: Array = _menu.get("_items_home")
	var m: float = 0.0
	for i in snap.size():
		if i >= homes.size():
			continue
		var p: Vector2 = snap[i]["pos"]
		var h: Vector2 = homes[i]
		m = maxf(m, p.distance_to(h))
	return m

func _test_menu_rotation() -> void:
	_write_log("-- menu rotation residue --")
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 800)
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(_vp)
	_menu = MenuScript.new()
	_vp.add_child(_menu)
	for i in 4:
		await process_frame
	_check("menu_ready", _menu.get("_items").size() == 8, "items=%d" % _menu.get("_items").size())

	# 0) 标题菜单稳定态：干净
	_menu.call("open", false)
	await _wait(0.95)
	var snap := _snapshot()
	_check("title_idle_rot_zero", _max_rot(snap) < 0.0001, "max_rot=%.5f" % _max_rot(snap))
	_check("title_idle_scale_one", _max_scale_err(snap) < 0.0001, "max_err=%.5f" % _max_scale_err(snap))
	_check("title_idle_pos_home", _max_home_err(snap) < 0.5, "max_err=%.2fpx" % _max_home_err(snap))

	# 1) 真实 bug 触发路径：标题菜单「开始游戏」螺旋飞出 close(returning=false)
	_menu.call("close", Callable())
	await _wait(1.9)
	var fly_snap := _snapshot()
	# 修复后：_fly_out 收尾自己会还原 rotation/scale（旧实现残留 ±0.68rad / 0.9 缩放）。
	_check("flyout_self_cleans_rot", _max_rot(fly_snap) < 0.0001, "max_rot=%.5f" % _max_rot(fly_snap))
	_check("flyout_self_cleans_scale", _max_scale_err(fly_snap) < 0.0001, "max_err=%.5f" % _max_scale_err(fly_snap))
	_check("flyout_hidden", not bool(fly_snap[0]["vis"]) and float(fly_snap[0]["a"]) <= 0.001, "vis=%s a=%.3f" % [str(fly_snap[0]["vis"]), float(fly_snap[0]["a"])])
	_check("flyout_tweens_done", (_menu.get("_fly_tweens") as Array).is_empty(), "n=%d" % (_menu.get("_fly_tweens") as Array).size())

	# 1b) 复现旧 bug 的残留状态（手工写入螺旋姿态），验证 open(true) 能完全复位
	var items: Array = _menu.get("_items")
	for i in items.size():
		var ctl: Control = items[i]
		ctl.rotation = 0.62 if i % 2 == 0 else -0.62
		ctl.scale = Vector2(0.9, 0.9)
		ctl.position += Vector2(260.0 * (1.0 if i % 2 == 0 else -1.0), -180.0)
	var injected := _snapshot()
	_check("injected_old_residue_present", _max_rot(injected) > 0.5 and _max_scale_err(injected) > 0.05, "rot=%.3f scale_err=%.3f" % [_max_rot(injected), _max_scale_err(injected)])

	# 2) 游玩中按 ESC：open(true) 入场，采样 0.12s / 稳定态
	_menu.call("open", true)
	await _wait(0.12)
	var mid := _snapshot()
	_check("enter_mid_animating", int(_menu.get("_anim_state")) == 1, "state=%d" % _menu.get("_anim_state"))
	_check("enter_mid_rot_zero", _max_rot(mid) < 0.0001, "max_rot=%.5f" % _max_rot(mid))
	_check("enter_mid_scale_one", _max_scale_err(mid) < 0.0001, "max_err=%.5f" % _max_scale_err(mid))
	_check("enter_mid_offscreen", _max_home_err(mid) > 5.0, "moving=%.2fpx" % _max_home_err(mid))
	# 回归：标题菜单螺旋飞出收尾会把 item.visible 置 false；ESC 入场动画期间必须重新可见，
	# 否则控件"隐形滑入"、到动画结束才突然出现（13 号窗口截图曾因此拍不到东西）。
	var mid_vis := 0
	for it in mid:
		if bool(it["vis"]):
			mid_vis += 1
	_check("enter_mid_all_visible", mid_vis == mid.size(), "visible=%d/%d" % [mid_vis, mid.size()])
	await _wait(1.05)
	var done := _snapshot()
	_check("enter_done_rot_zero", _max_rot(done) < 0.0001, "max_rot=%.5f" % _max_rot(done))
	_check("enter_done_scale_one", _max_scale_err(done) < 0.0001, "max_err=%.5f" % _max_scale_err(done))
	_check("enter_done_pos_home", _max_home_err(done) < 0.5, "max_err=%.2fpx" % _max_home_err(done))
	_check("enter_done_alpha_one", absf(float(done[0]["a"]) - 1.0) < 0.0001, "a=%.3f" % float(done[0]["a"]))
	_check("enter_done_visible", bool(done[0]["vis"]), "")
	_check("no_stale_fly_tweens", (_menu.get("_fly_tweens") as Array).is_empty(), "")

	# 2b) 打开时仍在跑的 _fly_out tween 必须被 kill（不能继续写 rotation/position）
	for it2 in _menu.get("_items"):
		var c2: Control = it2
		_menu.call("_fly_out", c2, _menu.get("_menu_root").size * 0.5, 40.0, 0.0, 0.62, 0.0)
	_check("stale_fly_tweens_tracked", (_menu.get("_fly_tweens") as Array).size() == 8, "n=%d" % (_menu.get("_fly_tweens") as Array).size())
	_menu.call("open", true)
	await _wait(0.55)
	_check("stale_fly_tweens_killed", (_menu.get("_fly_tweens") as Array).is_empty(), "n=%d" % (_menu.get("_fly_tweens") as Array).size())
	var stale_snap := _snapshot()
	_check("stale_tween_cannot_rotate", _max_rot(stale_snap) < 0.0001, "max_rot=%.5f" % _max_rot(stale_snap))
	await _wait(0.65)

	# 3) ESC 反复开关 3 轮：无漂移（close returning 反向滑出 → open(true) 滑入）
	for r in 3:
		_menu.call("close", Callable())
		await _wait(1.2)
		_menu.call("open", true)
		await _wait(1.05)
		var rep := _snapshot()
		_check("repeat_%d_rot_zero" % r, _max_rot(rep) < 0.0001, "max_rot=%.5f" % _max_rot(rep))
		_check("repeat_%d_scale_one" % r, _max_scale_err(rep) < 0.0001, "max_err=%.5f" % _max_scale_err(rep))
		_check("repeat_%d_pos_home" % r, _max_home_err(rep) < 0.5, "max_err=%.2fpx" % _max_home_err(rep))

	# 4) 入场动画中途 ESC 反转（enter -> exit）再打开：不漂移、无残留 tween
	_menu.call("close", Callable())
	await _wait(1.2)
	_menu.call("open", true)
	await _wait(0.2)
	_menu.call("close", Callable())
	await _wait(1.2)
	_check("reverse_closed_hidden", not bool(_menu.get("menu_visible")), "menu_visible=%s" % str(_menu.get("menu_visible")))
	_menu.call("open", true)
	await _wait(1.05)
	var rev := _snapshot()
	_check("reverse_rot_zero", _max_rot(rev) < 0.0001, "max_rot=%.5f" % _max_rot(rev))
	_check("reverse_scale_one", _max_scale_err(rev) < 0.0001, "max_err=%.5f" % _max_scale_err(rev))
	_check("reverse_pos_home", _max_home_err(rev) < 0.5, "max_err=%.2fpx" % _max_home_err(rev))

	# 5) 快速开关风暴 6 次后最终稳定态干净
	for i in 6:
		_menu.call("close", Callable())
		if i % 2 == 0:
			await _wait(0.12)
			_menu.call("open", true)
			await _wait(0.15)
		_menu.call("open", true)
		await _wait(0.05)
	await _wait(1.2)
	var storm := _snapshot()
	_check("storm_rot_zero", _max_rot(storm) < 0.0001, "max_rot=%.5f" % _max_rot(storm))
	_check("storm_scale_one", _max_scale_err(storm) < 0.0001, "max_err=%.5f" % _max_scale_err(storm))
	_check("storm_pos_home", _max_home_err(storm) < 0.5, "max_err=%.2fpx" % _max_home_err(storm))
	_check("storm_tween_single", _menu.get("_anim_tween") == null or not (_menu.get("_anim_tween") as Tween).is_running(), "anim_tween=%s" % str(_menu.get("_anim_tween")))

	# 6) 关闭后重新以标题菜单（open(false)）打开也干净
	_menu.call("close", Callable())
	await _wait(1.2)
	_menu.call("open", false)
	await _wait(0.95)
	var title2 := _snapshot()
	_check("title_reopen_clean", _max_rot(title2) < 0.0001 and _max_scale_err(title2) < 0.0001, "rot=%.5f scale_err=%.5f" % [_max_rot(title2), _max_scale_err(title2)])

func _test_hud_c_hint() -> void:
	_write_log("-- HUD C hint --")
	var hvp := SubViewport.new()
	hvp.size = Vector2i(1600, 900)
	hvp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(hvp)
	var hud = HudScript.new()
	hvp.add_child(hud)
	for i in 4:
		await process_frame
	hud.call("set_hud_visible", true, false)
	hud.call("set_auto_orbit", true, false)
	await process_frame
	var hint: VBoxContainer = hud.get("_hint")
	var texts: Array[String] = []
	for c in hint.get_children():
		var l := c as Label
		if l != null:
			texts.append(l.text)
	var joined := "\n".join(texts)
	_check("hint_contains_C_auto_orbit", joined.contains("C 自动运镜"), joined.replace("\n", " / "))
	_check("hint_keeps_existing_keys", joined.contains("空格 暂停") and joined.contains("F2 截图"), "")
	var auto_label: Label = hud.get("_auto_label")
	_check("indicator_has_C_on", auto_label.text.contains("自动运镜") and auto_label.text.contains("C"), auto_label.text)
	hud.call("set_auto_orbit", false, false)
	await process_frame
	_check("indicator_has_C_off", auto_label.text.contains("关") and auto_label.text.contains("C"), auto_label.text)
	hud.call("set_auto_orbit_available", false)
	await process_frame
	_check("indicator_hidden_unavailable", not auto_label.visible, "")
	hud.call("set_auto_orbit_available", true)
	hud.call("set_auto_orbit", true, true)
	await _wait(0.3)
	var toast: Label = hud.get("_toast")
	_check("toast_C_hint", toast.text.contains("C 键切换") and toast.visible, toast.text)
	# H 隐藏界面：整棵 HUD（含提示 / 指示）一起隐藏
	hud.call("set_hud_visible", false, false)
	await process_frame
	var root_ctl: Control = hud.get("_root")
	_check("hud_hidden_alpha_zero", absf(root_ctl.modulate.a) < 0.001, "a=%.3f" % root_ctl.modulate.a)
	# 1600x900 与 1280x720 下右上提示不越界 / 不裁切
	for sz in [Vector2i(1600, 900), Vector2i(1280, 720)]:
		hvp.size = sz
		hud.call("set_hud_visible", true, false)
		await process_frame
		await process_frame
		var rect: Rect2 = hint.get_global_rect()
		_check("hint_inside_%dx%d" % [sz.x, sz.y], rect.position.x >= 0.0 and rect.end.x <= float(sz.x) + 0.5 and rect.position.y >= 0.0 and rect.end.y <= float(sz.y) + 0.5, "rect=%s vp=%s" % [str(rect), str(sz)])
