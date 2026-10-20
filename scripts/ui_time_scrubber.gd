class_name IsleTimeScrubber
extends Control
## 24 小时时间轴：拖动圆形把手即可线性改变当天时刻（0..86400 秒）。
## 只负责交互与绘制，真实时间仍由主模拟时钟持有。

signal scrubbed(seconds_of_day: float)

const PAD := 16.0
const TRACK_H := 8.0
const KNOB_R := 9.0
const LABELS := [0, 3, 6, 9, 12, 15, 18, 21, 24]

var seconds_of_day: float = 0.0
var accent: Color = Color("d99a6c")
var cream: Color = Color("f4ead8")
var dim: Color = Color(0.98, 0.92, 0.82, 0.55)
var track_color: Color = Color(1.0, 0.92, 0.80, 0.16)

var _font: Font
var _dragging: bool = false
var _hover: bool = false

func setup(font: Font) -> void:
	_font = font
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(300.0, 48.0)
	mouse_entered.connect(func() -> void:
		_hover = true
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hover = false
		queue_redraw())
	queue_redraw()

func set_seconds(v: float, emit_now: bool = false) -> void:
	if _dragging and not emit_now:
		return
	var snapped_v: float = clampf(snapped(v, 60.0), 0.0, 86400.0)
	var changed: bool = absf(snapped_v - seconds_of_day) > 0.5
	seconds_of_day = snapped_v
	queue_redraw()
	if changed and emit_now:
		scrubbed.emit(seconds_of_day)

func is_dragging() -> bool:
	return _dragging

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			_dragging = true
			_set_from_x(mb.position.x, true)
			accept_event()
		elif _dragging:
			_dragging = false
			queue_redraw()
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_set_from_x((event as InputEventMouseMotion).position.x, true)
		accept_event()

func _set_from_x(x: float, emit_now: bool) -> void:
	var span: float = maxf(1.0, size.x - PAD * 2.0)
	var ratio: float = clampf((x - PAD) / span, 0.0, 1.0)
	set_seconds(ratio * 86400.0, emit_now)

func _draw() -> void:
	var track_y: float = 18.0
	var x0: float = PAD
	var x1: float = maxf(x0 + 1.0, size.x - PAD)
	draw_line(Vector2(x0, track_y), Vector2(x1, track_y), track_color, TRACK_H, true)
	var kx: float = lerpf(x0, x1, clampf(seconds_of_day / 86400.0, 0.0, 1.0))
	if kx > x0 + 0.5:
		draw_line(Vector2(x0, track_y), Vector2(kx, track_y), accent.darkened(0.10), TRACK_H, true)
	# 每 3 小时一个刻度，并在下方标注整点；12:00 与 00:00 加粗
	for h in LABELS:
		var tx: float = lerpf(x0, x1, float(h) / 24.0)
		var major: bool = (int(h) % 6) == 0
		draw_line(Vector2(tx, track_y - (7.0 if major else 4.0)), Vector2(tx, track_y + (7.0 if major else 4.0)),
			Color(1.0, 0.95, 0.86, 0.45 if major else 0.22), 1.0, true)
		if _font != null:
			var label: String = "%02d" % int(h)
			var tw: float = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			draw_string(_font, Vector2(tx - tw * 0.5, track_y + 22.0), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, dim)
	if _hover or _dragging:
		draw_circle(Vector2(kx, track_y), KNOB_R + 4.0, Color(accent.r, accent.g, accent.b, 0.22))
	draw_circle(Vector2(kx, track_y), KNOB_R, cream)
	draw_circle(Vector2(kx, track_y), KNOB_R - 3.8, accent.darkened(0.12))
