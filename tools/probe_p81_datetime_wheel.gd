extends SceneTree
## P8.1-07 第一阶段验收探针（headless；不加载 isle.tscn、不开窗口、不写任何 P8 冻结目录）。
## 运行：
##   D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe --headless --path D:/休闲小岛幻境/游戏工程 --script res://tools/probe_p81_datetime_wheel.gd
## 覆盖 W01-W12 + 关键边界 C05/C06/C07/C09/C15/C16/C19/C23/C24/C25：
##   A 段：滚轮纯逻辑（初始值、一格吸附、慢拖、惯性、月末/闰年、跨年、只读、年边界回弹、日期钳制、基线公式）
##   B 段：HUD 集成（开合 10 次无泄漏、busy 不 14s 收折、确认只发一次、回到当前、dirty 不被回灌、
##         面板高度、现实时间只读、_cal_step 同步草稿、打开日历从权威时钟灌值）
## 退出码：0 = 全部通过；1 = 有失败。

const WheelCtl := preload("res://scripts/ui_datetime_wheel.gd")
const HudCtl := preload("res://scripts/hud.gd")
const Cal := preload("res://scripts/isle_calendar.gd")

const FIVE := ["year", "month", "day", "hour", "minute"]

var _pass := 0
var _fail := 0
var _fails: Array = []
var _font: Font
var _wheel = null
var _hud = null

var _parts_sig := 0
var _busy_sig := 0
var _jump_count := 0
var _jump_args: Array = []

func _initialize() -> void:
	print("=== P8.1-07 DATETIME WHEEL PROBE START ===")
	await process_frame
	_font = _load_font()
	_wheel = WheelCtl.new()
	_wheel.name = "ProbeWheel"
	get_root().add_child(_wheel)
	_wheel.call("setup", _font, true)
	await process_frame
	_probe_w01_init()
	_probe_w02_notch()
	_probe_w03_drag()
	_probe_w03b_flick()
	_probe_w04_month_clamp()
	_probe_w05_leap()
	_probe_w06_cross_year()
	_probe_w07_readonly()
	_probe_c06_wrap_no_carry()
	_probe_c07_year_edge()
	_probe_c23_year_unix()
	_probe_c24_c25_input()
	_probe_w12_baseline()
	await _probe_hud()
	print("=== P8.1-07 DATETIME WHEEL PROBE RESULT: ", "PASS" if _fail == 0 else "FAIL",
		" pass=", _pass, " fail=", _fail, " ===")
	for m in _fails:
		print("[FAILED] ", m)
	quit(0 if _fail == 0 else 1)

# ------------------------------------------------------------
# 基础设施
# ------------------------------------------------------------

func _load_font() -> Font:
	var f := FontFile.new()
	var bytes := FileAccess.get_file_as_bytes("res://fonts/simhei.ttf")
	if bytes.size() > 0:
		f.data = bytes
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		f.hinting = TextServer.HINTING_NORMAL
		return f
	return ThemeDB.fallback_font

func _check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("  [OK] ", msg)
	else:
		_fail += 1
		_fails.append(msg)
		print("  [FAIL] ", msg)

func _check_int(actual: int, expect: int, msg: String) -> void:
	_check(actual == expect, "%s（实际 %d，期望 %d）" % [msg, actual, expect])

func _parts(y: int, mo: int, d: int, h: int, mi: int) -> Dictionary:
	return {"year": y, "month": mo, "day": d, "hour": h, "minute": mi}

func _eq_parts(a: Dictionary, b: Dictionary) -> bool:
	for k in FIVE:
		if int(a.get(k, -1)) != int(b.get(k, -2)):
			return false
	return true

func _cur() -> Dictionary:
	return _wheel.call("get_parts")

func _setp(y: int, mo: int, d: int, h: int, mi: int) -> void:
	_wheel.call("set_parts", _parts(y, mo, d, h, mi))

func _settle() -> int:
	return int(_wheel.call("debug_settle", 1.0 / 120.0, 1200))

func _sig_parts(_p: Dictionary) -> void:
	_parts_sig += 1

func _sig_busy(_b: bool) -> void:
	_busy_sig += 1

func _on_jump(y: int, mo: int, d: int, h: int, mi: int) -> void:
	_jump_count += 1
	_jump_args = [y, mo, d, h, mi]

# ------------------------------------------------------------
# A 段：滚轮纯逻辑
# ------------------------------------------------------------

func _probe_w01_init() -> void:
	print("-- W01 初始值 / set_parts 回读 / 非法输入夹取 --")
	_setp(2026, 3, 15, 14, 30)
	_check(_eq_parts(_cur(), _parts(2026, 3, 15, 14, 30)), "W01 set_parts→get_parts 回读一致")
	_setp(2026, 13, 40, 25, 61)
	_check(_eq_parts(_cur(), _parts(2026, 12, 31, 23, 59)), "W01 非法 month/day/hour/minute 按公历夹取")

func _probe_w02_notch() -> void:
	print("-- W02 滚轮一格 / 临界阻尼吸附 / 信号只发一次 --")
	_setp(2026, 6, 15, 12, 10)
	if not _wheel.parts_changed.is_connected(Callable(self, "_sig_parts")):
		_wheel.connect("parts_changed", Callable(self, "_sig_parts"))
	_parts_sig = 0
	_wheel.call("debug_notch", "minute", 1)
	var steps := _settle()
	_check_int(int(_cur().get("minute", -1)), 11, "W02 分钟一格 +1")
	_check_int(_parts_sig, 1, "W02 吸附结束只发一次 parts_changed")
	_check(steps >= 20 and steps <= 80, "W02 吸附时长 0.17—0.67s（steps=%d @120Hz）" % steps)
	var again := _settle()
	_check(again <= 1, "W02 稳定后 tick 不再产生动画（steps=%d）" % again)
	_check_int(_parts_sig, 1, "W02 稳定后不重复发信号")

func _probe_w03_drag() -> void:
	print("-- W03 慢速拖动一格 --")
	_setp(2026, 6, 15, 12, 0)
	_parts_sig = 0
	_wheel.call("debug_begin_drag", "minute", 78.0)
	for i in range(1, 29):
		_wheel.call("debug_drag_to", "minute", 78.0 - float(i), 0.1)
	_wheel.call("debug_end_drag", "minute", 0.1)
	_settle()
	_check_int(int(_cur().get("minute", -1)), 1, "W03 慢拖 28px 后吸附到最小值 +1")
	_check_int(_parts_sig, 1, "W03 慢拖只发一次 parts_changed")

func _probe_w03b_flick() -> void:
	print("-- W03b 快速 flick 惯性滑行 --")
	_setp(2026, 6, 15, 12, 0)
	_part_sig_reset()
	_wheel.call("debug_begin_drag", "minute", 78.0)
	_wheel.call("debug_drag_to", "minute", 74.0, 0.02)
	_wheel.call("debug_drag_to", "minute", 44.0, 0.02)
	_wheel.call("debug_end_drag", "minute", 0.02)
	_check(bool(_wheel.call("is_busy")), "W03b 快速 flick 进入惯性（is_busy=true）")
	_settle()
	var mi := int(_cur().get("minute", -1))
	_check(mi >= 2, "W03b 惯性滑过 >=2 行（实际 minute=%d）" % mi)
	_check(not bool(_wheel.call("is_busy")), "W03b 惯性最终停稳")

func _part_sig_reset() -> void:
	_parts_sig = 0
	_busy_sig = 0

func _probe_w04_month_clamp() -> void:
	print("-- W04 月末钳制：1/31 → 2 月 --")
	_setp(2026, 1, 31, 0, 0)
	_wheel.call("debug_notch", "month", 1)
	_settle()
	var p := _cur()
	_check_int(int(p.get("month", -1)), 2, "W04 月份到 2 月")
	_check_int(int(p.get("day", -1)), 28, "W04 日 31 自动钳制到 2 月 28（不回弹）")
	# C04 再切回 3 月：日保持 28，不自动恢复 31（明确的产品语义）
	_wheel.call("debug_notch", "month", 1)
	_settle()
	p = _cur()
	_check_int(int(p.get("month", -1)), 3, "C04 月份切回 3 月")
	_check_int(int(p.get("day", -1)), 28, "C04 日保持 28（不自动恢复 31）")

func _probe_w05_leap() -> void:
	print("-- W05 闰年 / 世纪闰年 / 非闰年 --")
	_setp(2024, 2, 29, 0, 0)
	_check_int(int(_cur().get("day", -1)), 29, "W05 2024-02-29 合法保留")
	_wheel.call("debug_notch", "year", 1)
	_settle()
	var p := _cur()
	_check_int(int(p.get("year", -1)), 2025, "W05 年 +1 到 2025")
	_check_int(int(p.get("day", -1)), 28, "W05 2025-02-29 不存在 → 日钳制到 28")
	_setp(2100, 2, 29, 0, 0)
	_check_int(int(_cur().get("day", -1)), 28, "W05 2100 非闰年 → 28")
	_setp(2000, 2, 29, 0, 0)
	_check_int(int(_cur().get("day", -1)), 29, "W05 2000 世纪闰年 → 29")

func _probe_w06_cross_year() -> void:
	print("-- W06 12-31 23:59 跨年（各列独立，无进位）--")
	_setp(2026, 12, 31, 23, 59)
	_wheel.call("debug_notch", "year", 1)
	_settle()
	_wheel.call("debug_notch", "month", 1)
	_settle()
	_wheel.call("debug_notch", "hour", 1)
	_settle()
	_wheel.call("debug_notch", "minute", 1)
	_settle()
	var p := _cur()
	_check_int(int(p.get("year", -1)), 2027, "W06 年跨到 2027")
	_check_int(int(p.get("month", -1)), 1, "W06 月循环 12→1")
	_check_int(int(p.get("day", -1)), 31, "W06 日保持 31（1 月合法，不自动进位）")
	_check_int(int(p.get("hour", -1)), 0, "W06 时循环 23→0")
	_check_int(int(p.get("minute", -1)), 0, "W06 分循环 59→0")
	_wheel.call("step_field", "day", -30)
	var q := _cur()
	_check(_eq_parts(q, _parts(2027, 1, 1, 0, 0)), "W06 步进 30 天后到 2027-01-01 00:00")
	var target := Cal.to_local_seconds(2027, 1, 1, 0, 0, 0)
	var actual := Cal.to_local_seconds(int(q["year"]), int(q["month"]), int(q["day"]),
		int(q["hour"]), int(q["minute"]), 0)
	_check(is_equal_approx(target, actual), "W06 与 isle_calendar.to_local_seconds 往返一致")

func _probe_w07_readonly() -> void:
	print("-- W07 只读：notch / step / 拖动全部无效 --")
	_setp(2026, 6, 15, 12, 0)
	_wheel.call("set_editable", false)
	_wheel.call("debug_notch", "minute", 1)
	_wheel.call("step_field", "year", 1)
	_wheel.call("debug_begin_drag", "minute", 78.0)
	_wheel.call("debug_drag_to", "minute", 30.0, 0.02)
	_wheel.call("debug_end_drag", "minute", 0.02)
	_settle()
	_check(_eq_parts(_cur(), _parts(2026, 6, 15, 12, 0)), "W07 只读态所有输入不改变值")
	_check(not bool(_wheel.call("is_busy")), "W07 只读态 is_busy=false")
	_wheel.call("set_editable", true)
	_wheel.call("debug_notch", "minute", 1)
	_settle()
	_check_int(int(_cur().get("minute", -1)), 1, "W07 恢复可编辑后 notch 生效")

func _probe_c06_wrap_no_carry() -> void:
	print("-- C06 时 / 分循环不进位 --")
	_setp(2026, 6, 15, 23, 59)
	_wheel.call("debug_notch", "hour", 1)
	_settle()
	_check(_eq_parts(_cur(), _parts(2026, 6, 15, 0, 59)), "C06 23→0 且日期不变")
	_wheel.call("debug_notch", "minute", 1)
	_settle()
	_check(_eq_parts(_cur(), _parts(2026, 6, 15, 0, 0)), "C06 59→0 且时不进位")

func _probe_c07_year_edge() -> void:
	print("-- C07 年 1 / 9999 边界回弹 --")
	_setp(9999, 6, 15, 0, 0)
	_wheel.call("debug_notch", "year", 1)
	_settle()
	var col = _wheel.call("debug_column", "year")
	var pos := float(col.get("pos"))
	_check_int(int(_cur().get("year", -1)), 9999, "C07 年 9999 +1 不越界")
	_check(pos <= 9999.25 + 0.001, "C07 年 9999 橡皮筋不超过 9999.25（pos=%.3f）" % pos)
	_setp(1, 6, 15, 0, 0)
	_wheel.call("debug_notch", "year", -1)
	_settle()
	col = _wheel.call("debug_column", "year")
	pos = float(col.get("pos"))
	_check_int(int(_cur().get("year", -1)), 1, "C07 年 1 -1 不越界")
	_check(pos >= 0.749, "C07 年 1 橡皮筋不低于 0.75（pos=%.3f）" % pos)

func _probe_c23_year_unix() -> void:
	print("-- C23 年 1 / 9999 的 to_local_seconds 实测 --")
	var s1 := Cal.to_local_seconds(1, 1, 1, 0, 0, 0)
	var s2 := Cal.to_local_seconds(9999, 12, 31, 23, 59, 0)
	print("  [INFO] year1=%.1f year9999=%.1f" % [s1, s2])
	_check(is_finite(s1) and is_finite(s2), "C23 年 1 / 9999 秒值有限（不溢出 NaN/INF）")
	_check(s1 < s2, "C23 年 1 秒值 < 年 9999 秒值")

func _probe_c24_c25_input() -> void:
	print("-- C24 键盘 echo 不重复 / C25 拖动越界钳制 --")
	_setp(2026, 6, 15, 12, 10)
	var col = _wheel.call("debug_column", "minute")
	var echo := InputEventKey.new()
	echo.pressed = true
	echo.echo = true
	echo.keycode = KEY_UP
	col._gui_input(echo)
	_settle()
	_check_int(int(_cur().get("minute", -1)), 10, "C24 echo 键盘事件不重复步进")
	var wheel_up := InputEventMouseButton.new()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_up.pressed = true
	wheel_up.position = Vector2(10, 78)
	col._gui_input(wheel_up)
	_settle()
	_check_int(int(_cur().get("minute", -1)), 9, "C24 滚轮事件使分钟 -1（并 accept_event）")
	# C19 方向键在列内步进（事件被 accept，不冒泡到 main 的快捷键；窗口分发另测）
	var up := InputEventKey.new()
	up.pressed = true
	up.echo = false
	up.keycode = KEY_UP
	col._gui_input(up)
	_settle()
	_check_int(int(_cur().get("minute", -1)), 8, "C19 方向键 ↑ 在分钟列 -1")
	# 日列硬钳制
	_setp(2026, 1, 1, 0, 0)
	_wheel.call("debug_begin_drag", "day", 78.0)
	_wheel.call("debug_drag_to", "day", 278.0, 0.1)
	_wheel.call("debug_end_drag", "day", 0.1)
	_settle()
	var day_col = _wheel.call("debug_column", "day")
	_check_int(int(_cur().get("day", -1)), 1, "C25 日列越界下拉钳制到 1")
	_check(float(day_col.get("pos")) >= 1.0, "C25 日列 pos 不低于 1")
	# 年列橡皮筋
	_setp(9999, 1, 1, 0, 0)
	_wheel.call("debug_begin_drag", "year", 78.0)
	_wheel.call("debug_drag_to", "year", -422.0, 0.2)
	_wheel.call("debug_end_drag", "year", 0.2)
	_settle()
	var year_col = _wheel.call("debug_column", "year")
	_check_int(int(_cur().get("year", -1)), 9999, "C25 年列上拉越界钳制到 9999")
	_check(float(year_col.get("pos")) <= 9999.25 + 0.001, "C25 年列 pos 不超过 9999.25")

func _probe_w12_baseline() -> void:
	print("-- W12 高 DPI：中心行字体基线公式 --")
	for fs in [10, 13, 16]:
		var size := int(fs)
		var baseline := float(WheelCtl.center_baseline(_font, size, 78.0))
		var center := baseline - (_font.get_ascent(size) - _font.get_descent(size)) * 0.5
		_check(absf(center - 78.0) < 0.01,
			"W12 字号 %d 文字视觉中心=78.0（实际 %.4f）" % [size, center])
	# C20 TAB 焦点顺序 = 年→月→日→时→分
	var names: Array = []
	for i in range(5):
		names.append(String(_wheel.get_child(i).name))
	_check(names == ["Wheel_year", "Wheel_month", "Wheel_day", "Wheel_hour", "Wheel_minute"],
		"C20 列子节点顺序 = 年/月/日/时/分（TAB 顺序）")

# ------------------------------------------------------------
# B 段：HUD 集成
# ------------------------------------------------------------

func _data(y: int, mo: int, d: int, h: int, mi: int, src: String) -> Dictionary:
	return {
		"clock": "%02d:%02d" % [h, mi],
		"date": "%04d-%02d-%02d" % [y, mo, d],
		"weekday": "周一",
		"phase": "白天",
		"year": y, "month": mo, "day": d, "hour": h, "minute": mi,
		"time_source": src, "paused": true, "heading": 0.0,
	}

func _probe_hud() -> void:
	print("-- HUD 集成（headless 实例化，不启动主场景）--")
	_hud = HudCtl.new()
	_hud.name = "ProbeHud"
	get_root().add_child(_hud)
	await process_frame
	var base := _data(2026, 3, 15, 14, 30, "sim")
	_hud.call("update_all", base)
	var wheel = _hud.get("_cal_wheel")
	_check(wheel != null, "HUD 构建出日期滚轮")
	if wheel == null:
		return
	var sec: VBoxContainer = _hud.get("_cal_section")
	var base_children := sec.get_child_count()
	var wheel_id: int = int(wheel.get_instance_id())
	var orphans0 := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))

	# ---- W08 开合 10 次无残留 ----
	print("-- W08 打开/关闭 10 次：节点与实例不增长 --")
	for i in range(10):
		_hud.call("_toggle_time_panel")
		_hud.call("_toggle_calendar")
		await process_frame
		_hud.call("_toggle_calendar")
		_hud.call("_toggle_time_panel")
	await process_frame
	var orphans1 := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_check_int(sec.get_child_count(), base_children, "W08 _cal_section 子节点数不变")
	_check(is_instance_valid(wheel) and wheel.get_instance_id() == wheel_id, "W08 滚轮实例未被重建")
	_check(orphans1 - orphans0 <= 2, "W08 orphan 节点无增长（%d→%d）" % [orphans0, orphans1])

	# ---- W09 busy 时不 14s 收折 ----
	print("-- W09 滚轮 busy 时阻止 14s 空闲收折 --")
	_hud.call("_toggle_time_panel")
	_hud.call("_toggle_calendar")
	await process_frame
	wheel.call("set_parts", _parts(2026, 3, 15, 14, 30))
	wheel.call("debug_begin_drag", "minute", 78.0)
	wheel.call("debug_drag_to", "minute", 40.0, 0.02)
	_check(bool(wheel.call("is_busy")), "W09 拖动中 is_busy=true")
	for i in range(3):
		_hud.call("_process", 15.0)
	var panel: PanelContainer = _hud.get("_time_panel")
	_check(panel.visible, "W09 busy 时连续 45s 空闲不收折")
	# 松开鼠标 → 惯性/吸附；停稳（is_busy=false）后才允许 14s 收折。
	wheel.call("debug_end_drag", "minute", 0.02)
	wheel.call("debug_settle", 1.0 / 120.0, 1200)
	_check(not bool(wheel.call("is_busy")), "W09 松手后滚轮停稳（is_busy=false）")
	# headless 视口仅 64x64、鼠标恒在 (0,0)，可能落在面板 rect 内使 over=true；
	# 临时把面板移出视口，隔离出「已停稳且鼠标不在面板上」这一收折条件。
	var keep_pos: Vector2 = panel.global_position
	panel.global_position = Vector2(-6000.0, -6000.0)
	await process_frame
	_hud.call("_process", 15.1)
	_check(not panel.visible, "W09 停稳后 14s 空闲收折正常触发")
	panel.global_position = keep_pos
	await process_frame

	# ---- W10 确认只发一次 + 参数 ----
	print("-- W10 确认只发一次 datetime_jump_requested --")
	_hud.call("_toggle_time_panel")
	_hud.call("_toggle_calendar")
	await process_frame
	wheel.call("set_parts", _parts(2027, 8, 9, 10, 11))
	if not _hud.is_connected("datetime_jump_requested", Callable(self, "_on_jump")):
		_hud.connect("datetime_jump_requested", Callable(self, "_on_jump"))
	_jump_count = 0
	_jump_args = []
	_hud.call("_on_cal_jump")
	_check_int(_jump_count, 1, "W10 点一次确认只发一次信号")
	_check(_jump_args == [2027, 8, 9, 10, 11], "W10 信号参数=滚轮当前值")
	_hud.call("_on_cal_jump")
	_check_int(_jump_count, 2, "W10 再点一次再发一次（幂等由 main 负责）")

	# ---- W11 回到当前 ----
	print("-- W11 回到当前：滚轮与草稿重置为权威时间 --")
	_hud.call("update_all", base)
	wheel.call("set_parts", _parts(2030, 5, 5, 6, 7))
	_hud.call("_on_cal_reset")
	await process_frame
	_check(_eq_parts(wheel.call("get_parts"), _parts(2026, 3, 15, 14, 30)), "W11 滚轮回到权威时间")
	_check(_eq_parts(_hud.get("_cal_draft"), _parts(2026, 3, 15, 14, 30)), "W11 _cal_draft 同步权威时间")
	_check(not bool(_hud.get("_cal_dirty")), "W11 重置后 dirty=false")

	# ---- C15 dirty 时 update_all 不回灌 ----
	print("-- C15 未确认草稿不被 update_all 回灌 --")
	wheel.call("set_parts", _parts(2031, 1, 2, 3, 4))
	_hud.call("_on_cal_parts_changed", _parts(2031, 1, 2, 3, 4))
	_check(bool(_hud.get("_cal_dirty")), "C15 编辑后 dirty=true")
	_hud.call("update_all", _data(2020, 1, 2, 3, 4, "sim"))
	_check(_eq_parts(wheel.call("get_parts"), _parts(2031, 1, 2, 3, 4)), "C15 权威时钟刷新不覆盖滚轮草稿")
	_check(_eq_parts(_hud.get("_cal_draft"), _parts(2031, 1, 2, 3, 4)), "C15 _cal_draft 保持草稿")
	_hud.call("_on_cal_reset")
	await process_frame

	# ---- C12b 收起日历时未确认编辑被丢弃并重置（方案补充语义，计划 C12 为 H 隐藏）----
	print("-- C12b 收起日历时未确认草稿重置为权威时间 --")
	# C15 曾把权威 _data 刷成 2020；先恢复基准时钟（dirty=false 时 update_all 会回灌草稿）。
	_hud.call("update_all", base)
	await process_frame
	wheel.call("set_parts", _parts(2032, 6, 7, 8, 9))
	_hud.call("_on_cal_parts_changed", _parts(2032, 6, 7, 8, 9))
	_check(bool(_hud.get("_cal_dirty")), "C12b 收起前 dirty=true")
	_hud.call("_close_calendar")
	await process_frame
	_check(not bool(_hud.get("_cal_open")), "C12b 日历已收起")
	_check(_eq_parts(wheel.call("get_parts"), _parts(2026, 3, 15, 14, 30)), "C12b 收起后滚轮=权威时间")
	_check(not bool(_hud.get("_cal_dirty")), "C12b 收起后 dirty=false")

	# ---- C12 H 隐藏 HUD 时同步收起时间面板与日历（计划 C12）----
	print("-- C12 H 隐藏 HUD 时收起面板与日历 --")
	if not bool(_hud.get("_time_open")):
		_hud.call("_toggle_time_panel")
	if not bool(_hud.get("_cal_open")):
		_hud.call("_toggle_calendar")
	await process_frame
	wheel.call("set_parts", _parts(2033, 9, 10, 11, 12))
	_hud.call("_on_cal_parts_changed", _parts(2033, 9, 10, 11, 12))
	_hud.call("set_hud_visible", false, false)
	await process_frame
	_check(not bool(_hud.get("_time_open")), "C12 H 隐藏后时间面板收起")
	_check(not bool(_hud.get("_cal_open")), "C12 H 隐藏后日历收起")
	_check(not bool(_hud.get("_cal_dirty")), "C12 H 隐藏后草稿重置 dirty=false")
	_check(_eq_parts(wheel.call("get_parts"), _parts(2026, 3, 15, 14, 30)), "C12 H 隐藏后滚轮=权威时间")
	_hud.call("set_hud_visible", true, false)
	await process_frame

	# ---- C16 面板内容高度 ----
	print("-- C16 日历展开态：内容最小高度不超过面板高度 --")
	if not panel.visible:
		_hud.call("_toggle_time_panel")
	_hud.call("_toggle_calendar")
	await process_frame
	var vbox: Control = panel.get_child(0)
	var need := vbox.get_combined_minimum_size().y
	var have := panel.size.y
	if have <= 0.0:
		have = panel.offset_bottom - panel.offset_top
	print("  [INFO] panel need=%.1f have=%.1f viewport=%s" % [need, have, str(get_root().size)])
	_check(have + 0.5 >= need, "C16 内容最小高度 %.1f <= 面板高度 %.1f" % [need, have])

	# ---- C09 现实时间只读 ----
	print("-- C09 现实时间模式滚轮只读 --")
	_hud.call("update_all", _data(2026, 3, 15, 14, 30, "real"))
	await process_frame
	var minute_col = wheel.call("debug_column", "minute")
	_check(int(minute_col.get("mouse_filter")) == int(Control.MOUSE_FILTER_IGNORE),
		"C09 real 模式滚轮列 mouse_filter=IGNORE")
	var before_real: Dictionary = wheel.call("get_parts")
	wheel.call("step_field", "minute", 1)
	_check(_eq_parts(wheel.call("get_parts"), before_real), "C09 real 模式 step_field 不改变值")
	_hud.call("update_all", base)
	await process_frame

	# ---- 旧 selftest 契约：_cal_step 必须同步 _cal_draft ----
	print("-- selftest 契约：_seed_cal_draft + _cal_step 同步 _cal_draft --")
	_hud.call("_seed_cal_draft", true)
	_hud.call("_cal_step", "day", 1)
	_check_int(int(_hud.get("_cal_draft").get("day", -1)), 16, "_cal_step('day',+1) 同步 _cal_draft=16")
	_check_int(int(wheel.call("get_parts").get("day", -1)), 16, "_cal_step 同步滚轮=16")

	# ---- 打开日历从权威时钟灌值 ----
	print("-- 打开日历：从权威时钟灌入草稿 --")
	if not panel.visible:
		_hud.call("_toggle_time_panel")
	_hud.call("_toggle_calendar")
	await process_frame
	_check(_eq_parts(wheel.call("get_parts"), _parts(2026, 3, 15, 14, 30)),
		"打开日历后滚轮=权威时钟值")
	# C10 暂停中仍允许编辑（base.paused=true；确认后 main 保持暂停，第二阶段端到端）
	_hud.call("_cal_step", "day", 1)
	_check_int(int(wheel.call("get_parts").get("day", -1)), 16, "C10 暂停（paused=true）中仍可编辑")
	_hud.call("_on_cal_reset")
	await process_frame
	# 收尾关闭
	_hud.call("_toggle_calendar")
	_hud.call("_toggle_time_panel")
	await process_frame
