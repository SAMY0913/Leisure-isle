class_name IsleDateTimeWheel
extends Control
## P8.1-07：Apple 式五列日期时间滚轮（年 / 月 / 日 / 时 / 分）。
##
## 设计依据：docs/P8_1_REFINEMENT_PLAN.md 第 10 章；开发产物/p81/findings/wind_ui.md B 段。
## 权威时钟仍是 main.gd 的 _sim_seconds：本控件只编辑“草稿”，确认后由 HUD 发
## datetime_jump_requested，main._jump_datetime 统一 clamp + 落地。本文件不持有时钟、
## 不写 _sim_seconds、不依赖任何第三方资源。
##
## 结构：根 Control（本类，负责布局 / 信号 / 跨列日期钳制） + 5 个内部 WheelColumn
## （自绘 5 行、处理滚轮 / 拖动 / 点击 / 键盘）。滚轮一格 = 1 行 = 1 单位。
## 交互数值模型：pos 为浮点行位置，中心行 = round(pos) 对应的值；拖动直接改 pos，
## 松手后 EMA 速度 > 1.2 行/秒进入惯性（摩擦 exp(-6dt)），否则临界阻尼弹簧
## （ω=18, ζ=1）吸附，0.25—0.35 s 稳定。所有输入都 accept_event()，避免冒泡到
## main.gd 的相机滚轮缩放。

signal parts_changed(parts: Dictionary)
## busy=true 表示拖动 / 惯性 / 吸附 / 回弹中；HUD 用它阻止 14 s 空闲收折。
signal editing_changed(busy: bool)

const Cal := preload("res://scripts/isle_calendar.gd")

const FIELDS := ["year", "month", "day", "hour", "minute"]
const UNITS := {"year": "年", "month": "月", "day": "日", "hour": "时", "minute": "分"}

## 布局：5 列宽 68/46/46/46/46 = 252，4 个 6px 列距 = 24，左右各 20px 内边距。
const COL_WIDTHS := [68.0, 46.0, 46.0, 46.0, 46.0]
const COL_GAP := 6.0
const PAD_X := 20.0
const ROW_H := 28.0
const VISIBLE_ROWS := 5
const WHEEL_W := 316.0
const WHEEL_H := 156.0

## 字号：中心 16、相邻 13、最外 10；alpha 对应 1.0 / .62 / .32。
const FONT_CENTER := 16
const FONT_NEAR := 13
const FONT_FAR := 10

const CREAM := Color("f4ead8")
const DIM := Color("c5b9a2")
const ACCENT := Color("d99a6c")

## WheelColumn 模式（与内部类共享字面值，内部类不引用外部常量）。
const MODE_SETTLED := 0
const MODE_DRAGGING := 1
const MODE_MOMENTUM := 2
const MODE_SNAPPING := 3

## 弹簧 / 惯性参数（docs/P8_1_REFINEMENT_PLAN.md §10.3）。
const SPRING_OMEGA := 18.0
const FRICTION := 6.0
const FLICK_THRESHOLD := 1.2
const SNAP_EPS_POS := 0.01
const SNAP_EPS_VEL := 0.05
const RUBBER_LIMIT := 0.25
const DRAG_THRESHOLD := 3.0

var _font: Font
var _cols: Array = []
var _editable := true
var _last_parts: Dictionary = {}
var _last_busy := false

# ============================================================
# 生命周期 / 对外 API
# ============================================================

func _ready() -> void:
	if _cols.is_empty() and _font != null:
		_build_columns()
	_layout()
	queue_redraw()

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	tick(delta)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and not _cols.is_empty():
		_layout()

## HUD 构建时调用一次；重复调用只更新字体，不重建列（避免节点泄漏）。
func setup(font: Font, editable: bool = true) -> void:
	_font = font
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(WHEEL_W, WHEEL_H)
	focus_mode = Control.FOCUS_NONE
	if _cols.is_empty():
		_build_columns()
	else:
		for col in _cols:
			col.font = font
	_editable = true   # 先归位，再按参数设置，确保 signal 语义一致
	set_editable(editable)
	_layout()
	if _last_parts.is_empty():
		set_parts({"year": 2026, "month": 1, "day": 1, "hour": 0, "minute": 0})
	queue_redraw()

## 外部灌值（草稿 / 回到当前）。非法输入走 isle_calendar.clamp_parts，不发信号。
func set_parts(p: Dictionary) -> void:
	if _cols.size() != FIELDS.size():
		return
	var c: Dictionary = Cal.clamp_parts(
		int(p.get("year", 2026)), int(p.get("month", 1)), int(p.get("day", 1)),
		int(p.get("hour", 0)), int(p.get("minute", 0)), 0)
	_col("year").set_value_immediate(int(c["year"]))
	_col("month").set_value_immediate(int(c["month"]))
	_sync_day_range()
	_col("day").set_value_immediate(int(c["day"]))
	_col("hour").set_value_immediate(int(c["hour"]))
	_col("minute").set_value_immediate(int(c["minute"]))
	_sync_day_range()
	# 程序化灌值不算用户编辑：同步 _last_parts，避免下一次 tick() 把同一组值当成新值再发 parts_changed
	# （否则 HUD 打开日历 / 点“回到当前”后 _cal_dirty 会被误置 true）。
	if _cols.size() == FIELDS.size():
		_last_parts = get_parts()
	_refresh_busy()
	queue_redraw()

## 读回当前五列（已按公历夹取；不含秒——秒由 main._jump_datetime 固定为 0）。
func get_parts() -> Dictionary:
	if _cols.size() != FIELDS.size():
		return {"year": 2026, "month": 1, "day": 1, "hour": 0, "minute": 0}
	var c: Dictionary = Cal.clamp_parts(
		int(_col("year").get_value()), int(_col("month").get_value()),
		int(_col("day").get_value()), int(_col("hour").get_value()),
		int(_col("minute").get_value()), 0)
	return {
		"year": int(c["year"]), "month": int(c["month"]), "day": int(c["day"]),
		"hour": int(c["hour"]), "minute": int(c["minute"]),
	}

## 真实时间模式只读；切回模拟模式后可编辑。关闭 / 隐藏时由 HUD 调用 cancel_drag()。
func set_editable(b: bool) -> void:
	_editable = b
	for col in _cols:
		col.set_editable(b)
	if not b:
		_cancel_animations()
	_refresh_busy()
	queue_redraw()

## 键盘 / 旧按钮兼容的单步：立即改值并发一次 parts_changed（HUD 草稿同步）。
## 年越界回弹不改变值；月 / 时 / 分循环；日按当月天数钳制。
func step_field(field: String, dir: int) -> void:
	if not _editable or dir == 0:
		return
	var col = _col(field)
	if col == null:
		return
	_cancel_animations()
	_sync_day_range()
	var before := get_parts()
	col.step_immediate(dir)
	_sync_day_range()
	var after := get_parts()
	_refresh_busy()
	if after != before:
		_last_parts = after
		parts_changed.emit(after)
	queue_redraw()

func is_busy() -> bool:
	for col in _cols:
		if col.is_busy():
			return true
	return false

func focus_first() -> void:
	if not _editable or _cols.is_empty():
		return
	_cols[0].grab_focus()

## 焦点在列间左右移动（方向键路径；TAB 顺序由列在树中的先后保证）。
func focus_step(dir: int) -> void:
	if not _editable or _cols.is_empty():
		return
	var idx := 0
	for i in _cols.size():
		if _cols[i].has_focus():
			idx = i
			break
	idx = clampi(idx + dir, 0, _cols.size() - 1)
	_cols[idx].grab_focus()

## 停止拖动 / 惯性并立即吸附到最近行；用于面板收折、隐藏、真实模式切换。
## 不发 parts_changed（调用方会重新灌入权威草稿），只保证 is_busy()==false。
func cancel_drag() -> void:
	_cancel_animations()
	_refresh_busy()

# ============================================================
# 每帧积分 / 跨列依赖（日列上限随年月变化）
# ============================================================

func tick(delta: float) -> void:
	if _cols.is_empty():
		return
	var dt := clampf(delta, 0.0, 0.1)
	for col in _cols:
		col.tick(dt)
	_sync_day_range()
	_refresh_busy()
	if is_busy():
		return
	var p := get_parts()
	if p != _last_parts:
		_last_parts = p
		parts_changed.emit(p)

func _refresh_busy() -> void:
	var busy := is_busy()
	if busy != _last_busy:
		_last_busy = busy
		editing_changed.emit(busy)

func _sync_day_range() -> void:
	if _cols.size() != FIELDS.size():
		return
	var y := int(_col("year").get_value())
	var mo := int(_col("month").get_value())
	var maxd: int = Cal.days_in_month(y, mo)
	_col("day").set_range(1, maxd, false)

## 日列在年月变化后非法时由 clamp_parts 兜底；这里只需保证列自身的范围正确。
func _cancel_animations() -> void:
	for col in _cols:
		col.settle_now()
	_sync_day_range()
	if _cols.size() == FIELDS.size():
		_last_parts = get_parts()
	queue_redraw()

# ============================================================
# 内部构建 / 布局
# ============================================================

func _range_for(field: String) -> Array:
	match field:
		"year":
			return [int(Cal.MIN_YEAR), int(Cal.MAX_YEAR), false]
		"month":
			return [1, 12, true]
		"day":
			return [1, 31, false]
		"hour":
			return [0, 23, true]
		_:
			return [0, 59, true]

func _build_columns() -> void:
	_cols.clear()
	for i in FIELDS.size():
		var field := String(FIELDS[i])
		var spec := _range_for(field)
		var col := WheelColumn.new()
		col.name = "Wheel_" + field
		col.configure(self, field, _font, ROW_H, FONT_CENTER, FONT_NEAR, FONT_FAR,
			float(COL_WIDTHS[i]), int(spec[0]), int(spec[1]), bool(spec[2]))
		col.unit_text = String(UNITS[field])
		add_child(col)
		_cols.append(col)

func _layout() -> void:
	if _cols.is_empty():
		return
	var x := PAD_X
	var top := maxf(0.0, (size.y - ROW_H * float(VISIBLE_ROWS)) * 0.5)
	for i in _cols.size():
		var col = _cols[i]
		col.position = Vector2(x, top)
		col.size = Vector2(float(COL_WIDTHS[i]), ROW_H * float(VISIBLE_ROWS))
		x += float(COL_WIDTHS[i]) + COL_GAP

func _col(field: String):
	for col in _cols:
		if String(col.field) == field:
			return col
	return null

func _column_index_at(x: float) -> int:
	var best := 0
	var best_d := 1e20
	for i in _cols.size():
		var col = _cols[i]
		var rect := Rect2(col.position, col.size)
		if x >= rect.position.x and x <= rect.end.x:
			return i
		var d: float = absf(x - (rect.position.x + rect.size.x * 0.5))
		if d < best_d:
			best_d = d
			best = i
	return best

# ============================================================
# 绘制（根：中心条 / 列分隔；列自行绘制 5 行文字）
# ============================================================

func _draw() -> void:
	var cy := size.y * 0.5
	var band := Rect2(0.0, cy - ROW_H * 0.5, size.x, ROW_H)
	var band_a := 0.075 if _editable else 0.035
	draw_rect(band, Color(1.0, 0.94, 0.86, band_a), true)
	draw_line(Vector2(0.0, band.position.y), Vector2(size.x, band.position.y),
		Color(1.0, 0.90, 0.74, 0.20), 1.0, true)
	draw_line(Vector2(0.0, band.end.y), Vector2(size.x, band.end.y),
		Color(1.0, 0.90, 0.74, 0.20), 1.0, true)
	# 列分隔线（列间 6px 空隙中点）
	var x := PAD_X
	for i in range(_cols.size() - 1):
		x += float(COL_WIDTHS[i]) + COL_GAP * 0.5
		draw_line(Vector2(x, cy - ROW_H * 2.0), Vector2(x, cy + ROW_H * 2.0),
			Color(1.0, 0.92, 0.80, 0.08), 1.0, true)
		x += COL_GAP * 0.5

func _gui_input(event: InputEvent) -> void:
	# 列空隙 / 只读态也要吃掉滚轮与左键，避免继续传给 main.gd 的相机缩放 / 水面点击。
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and _editable and not _cols.is_empty():
			_cols[_column_index_at(mb.position.x)].grab_focus()
		if is_inside_tree():
			accept_event()
	elif event is InputEventMouseMotion:
		if is_inside_tree():
			accept_event()

# ============================================================
# 测试 / 调试钩子（--headless probe 用；不参与正常 UI 路径）
# ============================================================

func debug_column(field: String):
	return _col(field)

func debug_notch(field: String, dir: int) -> void:
	var col = _col(field)
	if col != null:
		col.notch(dir)

func debug_begin_drag(field: String, y: float) -> void:
	var col = _col(field)
	if col != null:
		col.begin_drag(y)

func debug_drag_to(field: String, y: float, dt: float) -> void:
	var col = _col(field)
	if col != null:
		col.drag_to(y, dt)

func debug_end_drag(field: String, dt: float) -> void:
	var col = _col(field)
	if col != null:
		col.end_drag(dt)

func debug_click(field: String, y: float) -> void:
	var col = _col(field)
	if col != null:
		col.click_at(y)

func debug_tick(dt: float) -> void:
	tick(dt)

## 推进到稳定（默认 120Hz 最多 10 s）；返回实际步数，便于断言“吸附在 0.25—0.35 s”。
func debug_settle(dt: float = 1.0 / 120.0, max_steps: int = 1200) -> int:
	var steps := 0
	while steps < max_steps:
		tick(dt)
		steps += 1
		if not is_busy():
			break
	return steps

## 字体基线：让文字视觉盒中心落在 center_y（W12 高 DPI 对齐断言用）。
static func center_baseline(font: Font, font_size: int, center_y: float) -> float:
	if font == null:
		return center_y
	return center_y + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5

# ============================================================
# WheelColumn：单列自绘滚轮
# ============================================================

class WheelColumn:
	extends Control

	var wheel = null
	var field := ""
	var font: Font = null
	var row_h := 28.0
	var font_center := 16
	var font_near := 13
	var font_far := 10
	var min_value := 1
	var max_value := 1
	var wrap := false

	## 浮点行位置：中心行显示 round(pos) 对应的值。
	var pos := 1.0
	var vel := 0.0
	var mode := 0            ## 与 IsleDateTimeWheel.MODE_* 相同的字面值
	var target_index := 0
	var use_target := false

	var _editable := true
	var _press_down := false
	var _drag_started := false
	var _press_y := 0.0
	var _anchor_pos := 1.0
	var _last_y := 0.0
	var _last_ms := 0
	var _ema_vel := 0.0
	var _hover := false
	var unit_text := ""

	func configure(wheel_ref, p_field: String, p_font: Font, p_row_h: float,
			p_center: int, p_near: int, p_far: int, p_width: float,
			p_min: int, p_max: int, p_wrap: bool) -> void:
		wheel = wheel_ref
		field = p_field
		font = p_font
		row_h = p_row_h
		font_center = p_center
		font_near = p_near
		font_far = p_far
		min_value = p_min
		max_value = p_max
		wrap = p_wrap
		pos = float(min_value)
		custom_minimum_size = Vector2(p_width, p_row_h * 5.0)
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_ALL
		clip_contents = true
		set_process(false)
		mouse_entered.connect(_on_mouse_entered)
		mouse_exited.connect(_on_mouse_exited)
		focus_entered.connect(_on_focus_changed)
		focus_exited.connect(_on_focus_changed)
		queue_redraw()

	func _on_mouse_entered() -> void:
		_hover = true
		queue_redraw()

	func _on_mouse_exited() -> void:
		_hover = false
		queue_redraw()

	func _on_focus_changed() -> void:
		queue_redraw()

	# ---------------- 范围 / 值 ----------------

	func set_range(p_min: int, p_max: int, p_wrap: bool) -> void:
		min_value = p_min
		max_value = p_max
		wrap = p_wrap
		if not wrap:
			pos = clampf(pos, float(min_value), float(max_value))
			if use_target:
				target_index = clampi(target_index, min_value, max_value)
			if mode == 0:
				pos = float(clampi(int(round(pos)), min_value, max_value))
		queue_redraw()

	func _canonical_index(v: int) -> int:
		if wrap:
			return v
		return clampi(v, min_value, max_value)

	func value_at_index(r: int) -> int:
		if wrap:
			var count := max_value - min_value + 1
			return posmod(r - min_value, count) + min_value
		return clampi(r, min_value, max_value)

	func _valid_index(r: int) -> bool:
		if wrap:
			return true
		return r >= min_value and r <= max_value

	func nearest_index() -> int:
		return int(round(pos))

	func get_value() -> int:
		if wrap:
			return value_at_index(nearest_index())
		return clampi(nearest_index(), min_value, max_value)

	func set_value_immediate(v: int) -> void:
		pos = float(_canonical_index(value_at_index(v) if wrap else v))
		vel = 0.0
		use_target = false
		mode = 0
		queue_redraw()

	func _clamp_pos(np: float) -> float:
		if wrap:
			return np
		if field == "year":
			return clampf(np, float(min_value) - 0.25, float(max_value) + 0.25)
		return clampf(np, float(min_value), float(max_value))

	# ---------------- 状态 ----------------

	func is_busy() -> bool:
		return mode != 0

	func set_editable(b: bool) -> void:
		_editable = b
		mouse_filter = Control.MOUSE_FILTER_STOP if b else Control.MOUSE_FILTER_IGNORE
		focus_mode = Control.FOCUS_ALL if b else Control.FOCUS_NONE
		if not b:
			release_focus()
			settle_now()
		queue_redraw()

	func settle_now() -> void:
		_press_down = false
		_drag_started = false
		var idx := target_index if use_target else nearest_index()
		if not wrap:
			idx = clampi(idx, min_value, max_value)
		var v := value_at_index(idx)
		pos = float(_canonical_index(v))
		vel = 0.0
		use_target = false
		mode = 0
		queue_redraw()

	# ---------------- 离散步进 / 滚轮 / 点击 ----------------

	## 立即步进（HUD 旧按钮 / step_field）；返回是否真的改变。
	func step_immediate(dir: int) -> bool:
		var old := get_value()
		var v := old
		if wrap:
			var count := max_value - min_value + 1
			v = posmod(old - min_value + dir, count) + min_value
		else:
			v = old + dir
			if v < min_value or v > max_value:
				_bump(dir)
				return false
		set_value_immediate(v)
		return v != old

	## 滚轮一格：动画走到相邻行；年越界回弹（0.25 行）。
	func notch(dir: int) -> void:
		if not _editable or dir == 0:
			return
		if mode == 2:
			mode = 3
			vel = 0.0
		var base := target_index if (mode == 3 and use_target) else nearest_index()
		var t := base + dir
		if not wrap and (t < min_value or t > max_value):
			_bump(dir)
			return
		target_index = t
		use_target = true
		mode = 3
		vel = 0.0
		queue_redraw()

	func _bump(dir: int) -> void:
		pos += float(dir) * 0.25
		target_index = nearest_index()
		if not wrap:
			target_index = clampi(target_index, min_value, max_value)
		use_target = true
		mode = 3
		vel = 0.0
		queue_redraw()

	## 点击某一行直接选中：y 为列内坐标，中心行 = 当前值。
	func click_at(y: float) -> void:
		if not _editable:
			return
		var rel := (y - size.y * 0.5) / row_h
		var off := int(round(rel))
		if off == 0 or absi(off) > 2:
			return
		var t := nearest_index() + off
		if not _valid_index(t):
			return
		target_index = t
		use_target = true
		mode = 3
		vel = 0.0
		queue_redraw()

	# ---------------- 拖动 / 惯性 / 吸附 ----------------

	func begin_drag(y: float) -> void:
		if not _editable:
			return
		settle_now()
		_press_down = true
		_drag_started = false
		_press_y = y
		_last_y = y
		_anchor_pos = pos
		_ema_vel = 0.0
		_last_ms = Time.get_ticks_msec()

	func drag_to(y: float, dt: float) -> void:
		if not _editable or not _press_down:
			return
		var dy := y - _press_y
		if not _drag_started:
			if absf(dy) < 3.0:
				return
			_drag_started = true
			mode = 1
			use_target = false
			_ema_vel = 0.0
			_last_y = y
		var step_dt := dt
		if step_dt <= 0.0:
			step_dt = 0.016
		var inst := -((y - _last_y) / row_h) / step_dt
		_ema_vel = lerpf(_ema_vel, inst, 0.35)
		_last_y = y
		pos = _clamp_pos(_anchor_pos - dy / row_h)
		queue_redraw()

	func end_drag(dt: float) -> void:
		if not _press_down:
			return
		_press_down = false
		_last_ms = Time.get_ticks_msec()
		if not _drag_started:
			mode = 0
			return
		_drag_started = false
		if absf(_ema_vel) > 1.2:
			mode = 2
			vel = _ema_vel
		else:
			mode = 3
			vel = 0.0
			use_target = false
		queue_redraw()

	func _dt_since_last() -> float:
		var now := Time.get_ticks_msec()
		var dt := float(now - _last_ms) / 1000.0
		_last_ms = now
		return clampf(dt, 0.001, 0.1)

	func _snap_target_float() -> float:
		if use_target:
			return float(target_index)
		if wrap:
			return float(nearest_index())
		return float(clampi(nearest_index(), min_value, max_value))

	func tick(dt: float) -> void:
		if mode == 0 or mode == 1:
			return
		if mode == 2:
			pos = _clamp_pos(pos + vel * dt)
			vel *= exp(-6.0 * dt)
			if absf(vel) < 0.2:
				mode = 3
				vel = 0.0
				use_target = false
			queue_redraw()
			return
		# 临界阻尼弹簧（解析解，任意 dt 稳定）：
		# x(t) = (x0 + (v0 + w*x0) t) e^(-w t)
		var t := _snap_target_float()
		var x := pos - t
		var w := 18.0
		var e := exp(-w * dt)
		var b := vel + w * x
		pos = t + (x + b * dt) * e
		vel = (b - w * (x + b * dt)) * e
		if absf(pos - t) < 0.01 and absf(vel) < 0.05:
			pos = t
			vel = 0.0
			mode = 0
			use_target = false
			_normalize_after_settle()
		queue_redraw()

	func _normalize_after_settle() -> void:
		var v := value_at_index(int(round(pos)))
		pos = float(_canonical_index(v))

	# ---------------- 输入 ----------------

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				# 只认按下事件：部分平台/合成事件会给滚轮补一个 released，若不判断会滚动两格。
				if mb.pressed and _editable:
					grab_focus()
					notch(-1)
				if is_inside_tree():
					accept_event()
				return
			if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed and _editable:
					grab_focus()
					notch(1)
				if is_inside_tree():
					accept_event()
				return
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed:
					if _editable:
						grab_focus()
						begin_drag(mb.position.y)
					if is_inside_tree():
						accept_event()
				else:
					if _editable:
						var was_drag := _drag_started
						end_drag(_dt_since_last())
						if not was_drag:
							click_at(mb.position.y)
					if is_inside_tree():
						accept_event()
		elif event is InputEventMouseMotion:
			if _editable and _press_down:
				drag_to((event as InputEventMouseMotion).position.y, _dt_since_last())
			if is_inside_tree():
				accept_event()
		elif event is InputEventKey:
			var key := event as InputEventKey
			if not key.pressed or key.echo or not _editable:
				return
			match key.keycode:
				KEY_UP:
					notch(-1)
					accept_event()
				KEY_DOWN:
					notch(1)
					accept_event()
				KEY_PAGEUP:
					_page_step(-5)
					accept_event()
				KEY_PAGEDOWN:
					_page_step(5)
					accept_event()
				KEY_HOME:
					_jump_to_value(min_value)
					accept_event()
				KEY_END:
					_jump_to_value(max_value)
					accept_event()
				KEY_LEFT:
					wheel.focus_step(-1)
					accept_event()
				KEY_RIGHT:
					wheel.focus_step(1)
					accept_event()
				KEY_ENTER, KEY_KP_ENTER:
					accept_event()

	func _page_step(delta_rows: int) -> void:
		var base := target_index if (mode == 3 and use_target) else nearest_index()
		var t := base + delta_rows
		if wrap:
			target_index = t
		else:
			target_index = clampi(t, min_value, max_value)
		use_target = true
		mode = 3
		vel = 0.0
		queue_redraw()

	func _jump_to_value(v: int) -> void:
		target_index = _canonical_index(v)
		use_target = true
		mode = 3
		vel = 0.0
		queue_redraw()

	# ---------------- 绘制 ----------------

	func _draw() -> void:
		if font == null:
			return
		var cy := size.y * 0.5
		if _editable and (_hover or has_focus()):
			draw_rect(Rect2(0.0, cy - row_h * 0.5, size.x, row_h),
				Color(1.0, 0.90, 0.74, 0.05), true)
		var base := nearest_index()
		var frac := pos - float(base)
		var dim_mul := 1.0 if _editable else 0.45
		for i in range(-2, 3):
			var r := base + i
			if not _valid_index(r):
				continue
			var dist := absf(float(i) - frac)
			var fs := font_far
			var alpha := 0.32
			if dist < 0.5:
				fs = font_center
				alpha = 0.98
			elif dist < 1.5:
				fs = font_near
				alpha = 0.62
			var value := value_at_index(r)
			var text := _format_value(value)
			var color := Color(0.957, 0.918, 0.847, alpha * dim_mul)
			var dy := (float(i) - frac) * row_h
			var baseline := cy + dy + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5
			if dist < 0.5:
				var unit := unit_text
				var nw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				var uw := 0.0
				if not unit.is_empty():
					uw = font.get_string_size(unit, HORIZONTAL_ALIGNMENT_LEFT, -1, font_far).x
				var total := nw + (4.0 + uw if uw > 0.0 else 0.0)
				var x0 := (size.x - total) * 0.5
				draw_string(font, Vector2(x0, baseline), text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
				if uw > 0.0:
					draw_string(font, Vector2(x0 + nw + 4.0, baseline), unit,
						HORIZONTAL_ALIGNMENT_LEFT, -1, font_far,
						Color(0.957, 0.918, 0.847, alpha * 0.55 * dim_mul))
			else:
				var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				draw_string(font, Vector2((size.x - tw) * 0.5, baseline), text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
		if has_focus() and _editable:
			var fy := cy + row_h * 0.5 - 1.0
			draw_line(Vector2(4.0, fy), Vector2(size.x - 4.0, fy),
				Color(0.85, 0.60, 0.42, 0.85), 1.0, true)

	func _format_value(v: int) -> String:
		if field == "year":
			return "%04d" % v
		return "%02d" % v
