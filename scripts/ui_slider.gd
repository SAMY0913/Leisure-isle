class_name IsleSlider
extends Control
## 可拖动的横向滑条：圆形滑块 + 轨道 + 刻度。
## 数值在拖动过程中按 step 线性量化并实时发出 value_changed，供设置面板即时预览。

signal value_changed(value: float)
signal drag_started
signal drag_finished

const PAD := 14.0
const TRACK_H := 6.0
const KNOB_R := 8.5

var min_value: float = 0.0
var max_value: float = 1.0
var step: float = 0.01
var value: float = 0.0
var accent: Color = Color("d99a6c")
var cream: Color = Color("f4ead8")
var track_color: Color = Color(1.0, 0.92, 0.80, 0.16)
var tick_count: int = 4

var _dragging: bool = false
var _hover: bool = false

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(170.0, 34.0)
	mouse_entered.connect(func() -> void:
		_hover = true
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hover = false
		queue_redraw())

## 设置范围与初值；step 同时决定拖动时的量化精度。
func configure(mn: float, mx: float, st: float, val: float) -> void:
	min_value = mn
	max_value = maxf(mx, mn + maxf(st, 0.0001))
	step = maxf(st, 0.0001)
	set_value(val, false)

## 刻度数量：五档画质 = 5、十档时间流速 = 10、分辨率 = 预设数。
func set_tick_count(n: int) -> void:
	tick_count = maxi(1, n)
	queue_redraw()

func get_tick_count() -> int:
	return tick_count

func set_value(v: float, emit_now: bool = false) -> void:
	var snapped_v: float = min_value + round((clampf(v, min_value, max_value) - min_value) / step) * step
	snapped_v = clampf(snapped_v, min_value, max_value)
	var changed: bool = absf(snapped_v - value) > step * 0.001
	value = snapped_v
	queue_redraw()
	if changed and emit_now:
		value_changed.emit(value)

func get_ratio() -> float:
	if is_equal_approx(max_value, min_value):
		return 0.0
	return (value - min_value) / (max_value - min_value)

func is_dragging() -> bool:
	return _dragging

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			_dragging = true
			drag_started.emit()
			_set_from_x(mb.position.x, true)
			accept_event()
		elif _dragging:
			_dragging = false
			drag_finished.emit()
			queue_redraw()
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_set_from_x((event as InputEventMouseMotion).position.x, true)
		accept_event()

func _set_from_x(x: float, emit_now: bool) -> void:
	var span: float = maxf(1.0, size.x - PAD * 2.0)
	var ratio: float = clampf((x - PAD) / span, 0.0, 1.0)
	set_value(lerpf(min_value, max_value, ratio), emit_now)

func _draw() -> void:
	var cy: float = size.y * 0.5
	var x0: float = PAD
	var x1: float = maxf(x0 + 1.0, size.x - PAD)
	draw_line(Vector2(x0, cy), Vector2(x1, cy), track_color, TRACK_H, true)
	var kx: float = lerpf(x0, x1, get_ratio())
	if kx > x0 + 0.5:
		draw_line(Vector2(x0, cy), Vector2(kx, cy), accent.darkened(0.06), TRACK_H, true)
	for i in range(tick_count + 1):
		var tx: float = lerpf(x0, x1, float(i) / float(maxi(tick_count, 1)))
		draw_line(Vector2(tx, cy + TRACK_H * 0.5 + 2.0), Vector2(tx, cy + TRACK_H * 0.5 + 5.0),
			Color(1.0, 0.96, 0.88, 0.20), 1.0, true)
	if _hover or _dragging:
		draw_circle(Vector2(kx, cy), KNOB_R + 3.5, Color(accent.r, accent.g, accent.b, 0.22))
	draw_circle(Vector2(kx, cy), KNOB_R, cream)
	draw_circle(Vector2(kx, cy), KNOB_R - 3.6, accent.darkened(0.12))
	draw_arc(Vector2(kx, cy), KNOB_R, 0.0, TAU, 24, Color(0.1, 0.08, 0.06, 0.45), 1.0, true)
