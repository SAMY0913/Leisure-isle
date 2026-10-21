class_name IsleHud
extends CanvasLayer
## Relaxed-view HUD: clock, date, sky phase, compass ribbon, an almanac panel
## and a collapsible 24-hour time console that drives the shared simulation clock.

signal time_adjust(seconds_delta: float)
## 直接设定“当天时刻”（秒），用于可拖动时间轴；与 time_adjust 共用同一个主模拟时钟。
signal time_set(seconds_of_day: float)
## 时间来源切换请求（"real" / "sim"）：HUD 只负责 UI 与信号，状态源与保存由 main / 设置菜单负责。
signal time_mode_requested(mode: String)

const ScrubberCtl := preload("res://scripts/ui_time_scrubber.gd")
## 现实时间模式：时区换算全部走 IANA 真值表（isle_time / isle_tz_data）。
const TimeSvc := preload("res://scripts/isle_time.gd")

## 模拟时间模式下时间面板的说明文案。
const TIME_NOTE_SIM := "24 小时制 · 调时会驱动天空 / 日月 / 月相 / 船只 / 飞鸟 / 炊烟"

const CREAM := Color("f4ead8")
const DIM := Color("c5b9a2")
const ACCENT := Color("d99a6c")
const INK := Color("0b0e14")

var _root: Control
var _font: Font
var _top_left: VBoxContainer
var _title: Label
var _subtitle: Label
var _clock: Label
var _phase: Label
var _date: Label
var _tz_line: Label
var _hint: VBoxContainer
var _hint_lines: Array = []
var _hint_keys: Label
var _hint_keys2: Label
var _compass: Control
var _almanac: PanelContainer
var _almanac_toggle_hint: Label
var _values: Dictionary = {}
var _toast: Label
var _toast_t: float = 0.0
var _heading: float = 0.0
var _almanac_open: bool = false
var _data: Dictionary = {}
var _visible_now: bool = true
var _fade_t: float = 0.0

# ---- F3 performance overlay / hover prompt ----
var _perf_panel: PanelContainer
var _perf_label: Label
var _perf_open: bool = false
var _hover_label: Label
var _hover_text: String = ""

# ---- 24h time console ----
var _time_pill: Button
var _time_panel: PanelContainer
var _time_big: Label
var _time_note: Label
var _time_open: bool = false
var _time_idle: float = 0.0
var _clock_text: String = "--:--"
var _time_scrubber: Control
var _scrub_hint: Label
var _quick_buttons: Array[Button] = []
var _time_tz_line: Label
# 现实时间模式（由主循环在 update_all 里传入 time_source / timezone_label，缺键即模拟时间）。
var _time_source: String = "sim"
var _tz_label: String = ""
## 时间来源行（现实时间 / 模拟时间）：与设置菜单共用同一状态源，仅在本 UI 内展示与发信号。
var _time_mode_row: HBoxContainer
var _time_mode_buttons: Dictionary = {}
## 当前已应用到按钮高亮的来源，用于避免每帧重刷 stylebox。
var _time_mode_ui: String = ""

# ---- Phase 6（T1）：自动运镜常驻指示 + 每游戏日现实耗时 ----
var _auto_label: Label
var _auto_orbit: bool = true
var _auto_orbit_available: bool = true
var _time_daylen: Label

func _ready() -> void:
	layer = 5
	_font = _load_font()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.modulate = Color(1, 1, 1, 0)
	add_child(_root)
	_build()
	_visible_now = false

func _load_font() -> Font:
	var f := FontFile.new()
	var bytes := FileAccess.get_file_as_bytes("res://fonts/simhei.ttf")
	if bytes.size() > 0:
		f.data = bytes
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		f.hinting = TextServer.HINTING_NORMAL
		return f
	return ThemeDB.fallback_font

func _mk_label(text: String, size: int, color: Color, outline: int = 4) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.025, 0.04, 0.92))
	l.add_theme_constant_override("outline_size", outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _panel_style(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(1.0, 0.9, 0.74, 0.14)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 14.0
	sb.content_margin_bottom = 14.0
	sb.shadow_color = Color(0, 0, 0, 0.25)
	sb.shadow_size = 10
	return sb

func _btn_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = border
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 5.0
	sb.content_margin_bottom = 5.0
	return sb

func _mk_button(text: String, size: int, cb: Callable, square: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", CREAM)
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.97, 0.9))
	b.add_theme_color_override("font_pressed_color", ACCENT)
	b.add_theme_stylebox_override("normal", _btn_style(Color(0.06, 0.075, 0.10, 0.72), Color(1.0, 0.9, 0.74, 0.18)))
	b.add_theme_stylebox_override("hover", _btn_style(Color(0.11, 0.13, 0.17, 0.85), Color(1.0, 0.85, 0.64, 0.42)))
	b.add_theme_stylebox_override("pressed", _btn_style(Color(0.16, 0.13, 0.11, 0.9), Color(1.0, 0.78, 0.52, 0.7)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if square:
		b.custom_minimum_size = Vector2(38, 32)
	b.pressed.connect(cb)
	return b

func _build() -> void:
	# top-left clock block
	_top_left = VBoxContainer.new()
	_top_left.position = Vector2(34, 22)
	_top_left.add_theme_constant_override("separation", 2)
	_root.add_child(_top_left)
	_title = _mk_label("休闲小岛幻境", 30, CREAM, 5)
	_top_left.add_child(_title)
	_subtitle = _mk_label("LEISURE ISLE OF DUSK & DAWN", 11, DIM, 3)
	_top_left.add_child(_subtitle)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	_top_left.add_child(gap)
	_clock = _mk_label("--:--", 36, CREAM, 5)
	_top_left.add_child(_clock)
	_phase = _mk_label("--", 14, ACCENT, 3)
	_top_left.add_child(_phase)
	_date = _mk_label("----", 12, DIM, 3)
	_top_left.add_child(_date)
	# 现实时间模式才显示：现实时间 · Asia/Shanghai · UTC+08:00
	_tz_line = _mk_label("", 12, Color(0.84, 0.78, 0.68, 0.92), 3)
	_tz_line.visible = false
	_top_left.add_child(_tz_line)
	# top-right hints
	_hint = VBoxContainer.new()
	_hint.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_hint.position = Vector2(-356, 24)
	_hint.add_theme_constant_override("separation", 1)
	_root.add_child(_hint)
	var hints: Array = [
		["左键拖动 · 旋转视角", 12, DIM],
		["右键拖动 · 平移观察点", 12, DIM],
		["滚轮 · 推拉镜头", 12, DIM],
		["点击 · 木门 / 烟囱 / 海面", 12, DIM],
	]
	for hspec in hints:
		var l := _mk_label(hspec[0], hspec[1], hspec[2], 3)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.custom_minimum_size = Vector2(320, 0)
		_hint.add_child(l)
		_hint_lines.append(l)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	_hint.add_child(spacer)
	var keys := _mk_label("空格 暂停 · Tab 天文历 · T 时间 · C 自动运镜 · H 隐藏界面", 11, Color(0.72, 0.66, 0.56, 0.85), 2)
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	keys.custom_minimum_size = Vector2(320, 0)
	_hint.add_child(keys)
	_hint_keys = keys
	var keys2 := _mk_label("F2 截图 · F3 性能 · F11 全屏", 11, Color(0.72, 0.66, 0.56, 0.85), 2)
	keys2.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	keys2.custom_minimum_size = Vector2(320, 0)
	_hint.add_child(keys2)
	_hint_keys2 = keys2
	# compass
	_compass = Control.new()
	_compass.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_compass.position = Vector2(-260, 16)
	_compass.size = Vector2(520, 54)
	_compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_compass)
	_compass.draw.connect(_draw_compass)
	# almanac panel
	_almanac = PanelContainer.new()
	_almanac.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_almanac.offset_left = -392.0
	_almanac.offset_top = -400.0
	_almanac.offset_right = -32.0
	_almanac.offset_bottom = -28.0
	_almanac.add_theme_stylebox_override("panel", _panel_style(Color(0.045, 0.055, 0.075, 0.55)))
	_almanac.visible = false
	_root.add_child(_almanac)
	var av := VBoxContainer.new()
	av.add_theme_constant_override("separation", 5)
	_almanac.add_child(av)
	var at = _mk_label("天文历 · ALMANAC", 15, ACCENT, 3)
	av.add_child(at)
	var line := ColorRect.new()
	line.color = Color(1.0, 0.88, 0.71, 0.18)
	line.custom_minimum_size = Vector2(0, 1)
	av.add_child(line)
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 4)
	av.add_child(gap2)
	var rows: Array = [
		["clock", "时刻"], ["sun", "太阳 高度 / 方位"], ["day", "日出 / 日落"],
		["length", "昼长"], ["moon", "月相 / 照亮"], ["moonrise", "月出 / 月落"],
		["view", "视点方位"], ["theme", "主题参数 t"],
	]
	for r in rows:
		var hb := HBoxContainer.new()
		var nl := _mk_label(r[1], 12, DIM, 2)
		nl.custom_minimum_size = Vector2(150, 0)
		hb.add_child(nl)
		var vl := _mk_label("--", 13, CREAM, 2)
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		vl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(vl)
		av.add_child(hb)
		_values[r[0]] = vl
	var gap3 := Control.new()
	gap3.custom_minimum_size = Vector2(0, 4)
	av.add_child(gap3)
	var note := _mk_label("南岭 · 广州 23.13°N 113.26°E", 10, Color(0.65, 0.60, 0.52, 0.8), 2)
	av.add_child(note)
	# toast
	_toast = _mk_label("", 17, CREAM, 4)
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.position = Vector2(-320, -108)
	_toast.size = Vector2(640, 34)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.visible = false
	_root.add_child(_toast)
	# ---- F3 performance overlay ----
	_perf_panel = PanelContainer.new()
	_perf_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_perf_panel.position = Vector2(34, 196)
	_perf_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.03, 0.04, 0.055, 0.72)))
	_perf_panel.visible = false
	_perf_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_perf_panel)
	_perf_label = _mk_label("", 13, Color(0.82, 0.95, 0.88, 0.95), 2)
	_perf_panel.add_child(_perf_label)
	# ---- hover prompt that follows the cursor ----
	_hover_label = _mk_label("", 14, CREAM, 3)
	var hover_sb := _panel_style(Color(0.04, 0.05, 0.07, 0.86))
	hover_sb.content_margin_left = 12.0
	hover_sb.content_margin_right = 12.0
	hover_sb.content_margin_top = 6.0
	hover_sb.content_margin_bottom = 6.0
	_hover_label.add_theme_stylebox_override("normal", hover_sb)
	_hover_label.visible = false
	_root.add_child(_hover_label)
	# ---- Phase 6（T1）：自动运镜常驻指示（右上角小型半透明，不遮挡画面） ----
	_auto_label = _mk_label("", 11, Color(0.86, 0.80, 0.70, 0.58), 3)
	_auto_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_auto_label.offset_left = -356.0
	_auto_label.offset_top = 168.0
	_auto_label.offset_right = -32.0
	_auto_label.offset_bottom = 190.0
	_auto_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_auto_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_auto_label)
	_apply_auto_indicator()
	# ---- collapsible 24h time console ----
	_build_time_console()

func _build_time_console() -> void:
	# 折叠态：左下角一枚小胶囊，随时可展开，不长期遮挡画面
	_time_pill = _mk_button("◷ 时间  --:--", 14, _toggle_time_panel)
	_time_pill.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_time_pill.offset_left = 34.0
	_time_pill.offset_right = 196.0
	_time_pill.offset_top = -66.0
	_time_pill.offset_bottom = -32.0
	_time_pill.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_root.add_child(_time_pill)

	# 展开态：时间控制台（同一模拟时钟，调时立即驱动全部系统）
	_time_panel = PanelContainer.new()
	_time_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_time_panel.offset_left = 34.0
	_time_panel.offset_right = 386.0
	# 第五阶段：header 下新增“现实时间 / 模拟时间”切换行，面板相应加高。
	_time_panel.offset_top = -444.0
	_time_panel.offset_bottom = -84.0
	_time_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.045, 0.055, 0.075, 0.72)))
	_time_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_time_panel.visible = false
	_root.add_child(_time_panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_time_panel.add_child(v)

	var header := HBoxContainer.new()
	v.add_child(header)
	var ttl := _mk_label("时间 · TIME", 15, ACCENT, 3)
	ttl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(ttl)
	var collapse := _mk_button("收折 ▾", 12, _toggle_time_panel)
	collapse.custom_minimum_size = Vector2(70, 28)
	header.add_child(collapse)

	# 时间来源切换：现实时间 / 模拟时间；高亮跟随主循环传入的 data.time_source。
	_time_mode_row = HBoxContainer.new()
	_time_mode_row.add_theme_constant_override("separation", 8)
	v.add_child(_time_mode_row)
	var src_lbl := _mk_label("来源", 11, DIM, 2)
	src_lbl.custom_minimum_size = Vector2(32, 0)
	_time_mode_row.add_child(src_lbl)
	for spec in [["real", "现实时间"], ["sim", "模拟时间"]]:
		var mode_key := str(spec[0])
		var mode_btn := _mk_button(str(spec[1]), 12, Callable(self, "_on_time_mode_pressed").bind(mode_key))
		mode_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mode_btn.custom_minimum_size = Vector2(0, 30)
		mode_btn.tooltip_text = "跟随系统真实时钟（只读预览，切换后保存）" if mode_key == "real" else "游戏内模拟时钟，可自由调时"
		_time_mode_row.add_child(mode_btn)
		_time_mode_buttons[mode_key] = mode_btn

	_time_big = _mk_label("--:--", 40, CREAM, 5)
	_time_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_time_big)

	# 现实时间模式：面板内显示 “现实时间 · 时区 · UTC 偏移 · 只读预览”
	_time_tz_line = _mk_label("", 11, Color(0.84, 0.78, 0.68, 0.92), 3)
	_time_tz_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_tz_line.visible = false
	v.add_child(_time_tz_line)

	# 每游戏日对应的现实耗时（main 通过 day_length_sec 传入；缺键时隐藏该行）
	_time_daylen = _mk_label("", 11, Color(0.86, 0.78, 0.66, 0.92), 3)
	_time_daylen.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_daylen.visible = false
	v.add_child(_time_daylen)

	var line := ColorRect.new()
	line.color = Color(1.0, 0.88, 0.71, 0.16)
	line.custom_minimum_size = Vector2(0, 1)
	v.add_child(line)

	# 可拖动 24 小时时间轴：拖动即线性改变当天时刻，比按钮更直观
	var scrub_row := VBoxContainer.new()
	scrub_row.add_theme_constant_override("separation", 0)
	v.add_child(scrub_row)
	_time_scrubber = ScrubberCtl.new()
	scrub_row.add_child(_time_scrubber)
	(_time_scrubber as Control).call("setup", _font)
	_time_scrubber.custom_minimum_size = Vector2(320.0, 46.0)
	_time_scrubber.connect("scrubbed", Callable(self, "_on_time_scrubbed"))
	_scrub_hint = _mk_label("拖动时间轴 · 线性调整当天时刻 · 日月 / 月相 / 船只 / 飞鸟同步", 10, Color(0.68, 0.62, 0.53, 0.9), 2)
	_scrub_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scrub_row.add_child(_scrub_hint)

	var quick := HBoxContainer.new()
	quick.add_theme_constant_override("separation", 8)
	v.add_child(quick)
	for qspec in [["黎明 05:40", 5, 40], ["正午 12:20", 12, 20], ["黄昏 17:40", 17, 40], ["深夜 22:40", 22, 40]]:
		var qb := _mk_button(str(qspec[0]), 11, Callable(self, "_set_clock_target").bind(int(qspec[1]), int(qspec[2])))
		quick.add_child(qb)
		_quick_buttons.append(qb)

	_time_note = _mk_label(TIME_NOTE_SIM, 10, Color(0.68, 0.62, 0.53, 0.9), 2)
	_time_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_time_note.custom_minimum_size = Vector2(320, 0)
	v.add_child(_time_note)

func _draw_compass() -> void:
	if _compass == null or _font == null:
		return
	var w: float = _compass.size.x
	var h: float = _compass.size.y
	var cx: float = w * 0.5
	var y: float = h * 0.62
	var span: float = w * 0.5 - 44.0
	var heading: float = _heading
	_compass.draw_line(Vector2(14, y), Vector2(w - 14, y), Color(0.96, 0.88, 0.72, 0.16), 1.0)
	for i in range(-12, 13):
		var x: float = cx + float(i) / 12.0 * span
		var major: bool = (i % 3) == 0
		var th: float = 8.0 if major else 4.0
		var c: Color = Color(0.96, 0.90, 0.78, 0.5) if major else Color(0.96, 0.88, 0.72, 0.26)
		_compass.draw_line(Vector2(x, y - th), Vector2(x, y), c, 1.0)
	var cards: Array = [["N", 0.0], ["E", 90.0], ["S", 180.0], ["W", 270.0]]
	for cd in cards:
		var rel: float = fposmod(float(cd[1]) - heading + 540.0, 360.0) - 180.0
		if absf(rel) > 88.0:
			continue
		var x2: float = cx + rel / 88.0 * span
		var letter: String = cd[0]
		var tw: float = _font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		_compass.draw_string(_font, Vector2(x2 - tw * 0.5, y - 13), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.98, 0.92, 0.82, 0.92))
	var tri := PackedVector2Array([Vector2(cx - 6.0, y + 7.0), Vector2(cx + 6.0, y + 7.0), Vector2(cx, y + 1.0)])
	_compass.draw_colored_polygon(tri, Color(0.85, 0.55, 0.38, 0.95))
	var deg: int = int(round(fposmod(heading, 360.0)))
	var hs: String = "%03d°" % deg
	_compass.draw_string(_font, Vector2(cx - 22.0, y + 25.0), hs, HORIZONTAL_ALIGNMENT_CENTER, 44.0, 12, Color(0.93, 0.86, 0.72, 0.85))

func update_all(d: Dictionary) -> void:
	_data = d
	var clock_text: String = str(d.get("clock", "--:--"))
	_clock_text = clock_text
	if bool(d.get("paused", false)):
		clock_text += "  ❚❚"
	_clock.text = clock_text
	_phase.text = str(d.get("phase", "--"))
	var date_text: String = str(d.get("date", "")) + "  " + str(d.get("weekday", ""))
	if bool(d.get("realtime", false)):
		date_text += "  · 真实时间"
	_date.text = date_text
	_update_time_mode(d)
	_heading = float(d.get("heading", 0.0))
	_compass.queue_redraw()
	_refresh_time_display()
	_refresh_day_length_note(d)
	if _almanac_open:
		_refresh_almanac()

## 现实时间 / 模拟时间模式：只读取主循环传入的键；缺键时保持模拟时间显示且不报错。
func _update_time_mode(d: Dictionary) -> void:
	var legacy_real: bool = bool(d.get("realtime", false))
	var source: String = str(d.get("time_source", "real" if legacy_real else "sim")).strip_edges()
	_time_source = "real" if source == "real" else "sim"
	var tz_label: String = str(d.get("timezone_label", "")).strip_edges()
	if tz_label.is_empty():
		var tz_id: String = str(d.get("timezone", "")).strip_edges()
		if not tz_id.is_empty():
			tz_label = _normalize_tz_label(tz_id)
	_tz_label = tz_label
	_apply_time_mode_labels()

## 刷新左上“现实时间 · 时区 · UTC 偏移”行与时间面板注释；文本不变时不触发重排。
func _apply_time_mode_labels() -> void:
	var real: bool = _time_source == "real"
	# 左上时钟块：现实时间模式追加 “现实时间 · 时区 · UTC 偏移”
	if _tz_line != null:
		if real:
			var line := "现实时间"
			if not _tz_label.is_empty():
				line += " · " + _tz_label
			if _tz_line.text != line:
				_tz_line.text = line
			_tz_line.visible = true
		else:
			_tz_line.visible = false
	# 时间面板标题行：现实时间模式显示时区与只读标记
	if _time_tz_line != null:
		if real:
			var tz_line := "现实时间"
			if not _tz_label.is_empty():
				tz_line += " · " + _tz_label
			tz_line += " · 只读预览"
			if _time_tz_line.text != tz_line:
				_time_tz_line.text = tz_line
			_time_tz_line.visible = true
		else:
			_time_tz_line.visible = false
	# 时间轴提示：现实时间模式改为只读说明
	if _scrub_hint != null:
		var hint := "拖动时间轴 · 线性调整当天时刻 · 日月 / 月相 / 船只 / 飞鸟同步"
		if real:
			hint = "现实时间模式 · 时间轴只读；切回模拟时间后可调时"
		if _scrub_hint.text != hint:
			_scrub_hint.text = hint
	# 时间轴：现实时间模式禁用拖动（mouse_filter=IGNORE）并调暗
	if _time_scrubber != null:
		var scrubber := _time_scrubber as Control
		scrubber.mouse_filter = Control.MOUSE_FILTER_IGNORE if real else Control.MOUSE_FILTER_STOP
		scrubber.mouse_default_cursor_shape = Control.CURSOR_ARROW if real else Control.CURSOR_POINTING_HAND
		scrubber.modulate = Color(1.0, 1.0, 1.0, 0.45) if real else Color(1.0, 1.0, 1.0, 1.0)
	# 快捷按钮：现实时间模式禁用并调暗
	for entry in _quick_buttons:
		var qb := entry as Button
		if qb != null:
			qb.disabled = real
			qb.modulate = Color(1.0, 1.0, 1.0, 0.45) if real else Color(1.0, 1.0, 1.0, 1.0)
	if _time_note != null:
		var note := TIME_NOTE_SIM
		if real:
			var tz := _tz_label if not _tz_label.is_empty() else "系统时区"
			note = "现实时间模式 · 时钟跟随系统真实时间（%s）；时间轴 / 快捷按钮已只读，仅预览当日时刻，不修改系统时间。" % tz
		if _time_note.text != note:
			_time_note.text = note
	_apply_time_mode_buttons()

## 时间来源按钮高亮：现实时间 / 模拟时间，与设置菜单同一状态源（data.time_source）。
## 只在来源变化时重刷 stylebox，避免 0.12s 刷新周期反复分配资源。
func _apply_time_mode_buttons() -> void:
	if _time_mode_buttons.is_empty():
		return
	var mode := "real" if _time_source == "real" else "sim"
	if _time_mode_ui == mode:
		return
	_time_mode_ui = mode
	for key in ["sim", "real"]:
		if not _time_mode_buttons.has(key):
			continue
		var b := _time_mode_buttons[key] as Button
		var active: bool = key == mode
		if active:
			b.add_theme_color_override("font_color", ACCENT)
			b.add_theme_color_override("font_hover_color", Color(1.0, 0.86, 0.66))
			b.add_theme_stylebox_override("normal", _btn_style(Color(0.24, 0.17, 0.12, 0.95), ACCENT))
			b.add_theme_stylebox_override("hover", _btn_style(Color(0.30, 0.21, 0.14, 0.98), Color(0.95, 0.72, 0.50)))
			b.add_theme_stylebox_override("pressed", _btn_style(Color(0.20, 0.14, 0.10, 0.98), ACCENT))
		else:
			b.add_theme_color_override("font_color", CREAM)
			b.add_theme_color_override("font_hover_color", Color(1.0, 0.97, 0.9))
			b.add_theme_stylebox_override("normal", _btn_style(Color(0.06, 0.075, 0.10, 0.72), Color(1.0, 0.9, 0.74, 0.18)))
			b.add_theme_stylebox_override("hover", _btn_style(Color(0.11, 0.13, 0.17, 0.85), Color(1.0, 0.85, 0.64, 0.42)))
			b.add_theme_stylebox_override("pressed", _btn_style(Color(0.16, 0.13, 0.11, 0.9), Color(1.0, 0.78, 0.52, 0.7)))
		b.disabled = false

## 点击“现实时间 / 模拟时间”：只发请求信号，状态切换 / 保存 / 回灌由 main 统一处理。
func _on_time_mode_pressed(mode: String) -> void:
	var src := "real" if str(mode).strip_edges() == "real" else "sim"
	if src == _time_source:
		return
	# 乐观更新本 UI 高亮，main 下一次 update_all 会以状态源为准覆盖。
	_time_source = src
	_time_mode_ui = ""
	time_mode_requested.emit(src)
	_apply_time_mode_buttons()

## timezone_label 允许两种形态：完整标签（含 “UTC”/“·”）原样使用；纯 IANA id 则补上当前偏移。
func _normalize_tz_label(raw: String) -> String:
	var text := raw.strip_edges()
	if text.is_empty():
		return ""
	if text.contains("UTC") or text.contains("·"):
		return text
	if TimeSvc.has_zone(text):
		var zone := TimeSvc.resolve_zone(text)
		return "%s · %s" % [zone, TimeSvc.format_offset(TimeSvc.offset_at(zone, TimeSvc.now_unix()))]
	return text

## 只用主模拟时钟提供的 "clock" 字符串刷新显示，不新建任何时间变量。
func _refresh_time_display() -> void:
	if _time_pill != null:
		_time_pill.text = "◷ 时间  " + _clock_text
	if _time_big != null:
		_time_big.text = _clock_text
	if _time_scrubber != null and not bool((_time_scrubber as Control).call("is_dragging")):
		var parts := _clock_text.split(":")
		if parts.size() >= 2:
			var sec: float = float(int(parts[0])) * 3600.0 + float(int(parts[1])) * 60.0
			(_time_scrubber as Control).call("set_seconds", sec, false)

## 时间轴拖动 → 交给主程序直接设置当天时刻（不新建时间变量）。
func _on_time_scrubbed(sec_of_day: float) -> void:
	# 现实时间模式：时间由系统时钟驱动，交互只读
	if _time_source == "real":
		return
	_time_idle = 0.0
	time_set.emit(clampf(sec_of_day, 0.0, 86399.0))

func _toggle_time_panel() -> void:
	_time_open = not _time_open
	_time_panel.visible = _time_open
	_time_idle = 0.0
	if _time_open:
		_refresh_time_display()

func toggle_time_panel() -> void:
	_toggle_time_panel()

func _adjust_time(delta_seconds: float) -> void:
	if _time_source == "real":
		return
	_time_idle = 0.0
	time_adjust.emit(delta_seconds)

## 快捷按钮：按“当前日期 + 目标时刻”的差值调时，仍走主时钟的 time_adjust 通道。
func _set_clock_target(hour: int, minute: int) -> void:
	if _time_source == "real":
		return
	_time_idle = 0.0
	var parts := _clock_text.split(":")
	var cur_h: int = int(parts[0]) if parts.size() > 0 else 0
	var cur_m: int = int(parts[1]) if parts.size() > 1 else 0
	var delta_min: int = (hour * 60 + minute) - (cur_h * 60 + cur_m)
	if delta_min <= -720:
		delta_min += 1440
	time_adjust.emit(float(delta_min) * 60.0)

func _refresh_almanac() -> void:
	if _values.is_empty():
		return
	var d := _data
	_values["clock"].text = str(d.get("clock", "--:--"))
	_values["sun"].text = "%+.1f° / %.0f°" % [float(d.get("sun_alt", 0.0)), float(d.get("sun_az", 0.0))]
	_values["day"].text = "%s / %s" % [str(d.get("sunrise", "--")), str(d.get("sunset", "--"))]
	var dl: float = float(d.get("day_length", -1.0))
	if dl > 0.0:
		_values["length"].text = "%d h %02d m" % [int(dl) / 60, int(dl) % 60]
	else:
		_values["length"].text = "--"
	_values["moon"].text = "%s · %d%%" % [str(d.get("moon_name", "--")), int(round(float(d.get("moon_illum", 0.0)) * 100.0))]
	_values["moonrise"].text = "%s / %s" % [str(d.get("moonrise", "--")), str(d.get("moonset", "--"))]
	_values["view"].text = "%03d° · EL %.1f°" % [int(round(fposmod(_heading, 360.0))), float(d.get("cam_elev", 0.0))]
	_values["theme"].text = "%.3f · %s" % [float(d.get("theme_t", 0.0)), str(d.get("phase_short", ""))]

## 每游戏日 = 现实多少秒：main 传入 data.day_length_sec（缺键时该行隐藏）。
func _refresh_day_length_note(d: Dictionary) -> void:
	if _time_daylen == null:
		return
	var sec: float = float(d.get("day_length_sec", -1.0))
	if sec <= 0.0:
		_time_daylen.visible = false
		return
	var text := "%d 分钟/游戏日" % int(round(sec / 60.0))
	if _time_daylen.text != text:
		_time_daylen.text = text
	_time_daylen.visible = true

## 自动运镜状态：announce=true 时弹出 2s 提示（C 键切换说明）。
func set_auto_orbit(enabled: bool, announce: bool = false) -> void:
	_auto_orbit = enabled
	_apply_auto_indicator()
	if announce:
		show_toast("自动运镜 %s · C 键切换" % ("开" if enabled else "关"))

## 自动运镜是否可用（不可用时隐藏常驻指示）。
func set_auto_orbit_available(available: bool) -> void:
	_auto_orbit_available = available
	_apply_auto_indicator()

func _apply_auto_indicator() -> void:
	if _auto_label == null:
		return
	_auto_label.visible = _auto_orbit_available
	if _auto_orbit_available:
		# 常驻指示附带 C 键提示（只展示，按键监听仍在 main）。
		_auto_label.text = ("◉ 自动运镜 · 开 · 按 C 切换" if _auto_orbit else "○ 自动运镜 · 关 · 按 C 切换")

## P7-V3：自由视角下切换右上角操作提示（轨道视角↔飞行视角），避免两套操作说明互相误导演示。
## P7-V3.1：同时收敛"快捷键行"——自由视角下 C（自动运镜）作用于轨道相机，飞行时按下
## 只会切换一个看不见的状态，属于冲突说明，因此从飞行文案里去掉，并在退出时原样恢复。
func set_fly_hints(active: bool) -> void:
	var orbit_lines: Array = [
		"左键拖动 · 旋转视角",
		"右键拖动 · 平移观察点",
		"滚轮 · 推拉镜头",
		"点击 · 木门 / 烟囱 / 海面",
	]
	var fly_lines: Array = [
		"右键按住拖动 · 转向",
		"WASD 水平移动 · Space 上升 · Ctrl 下降",
		"Shift · 冲刺（2× 速度）",
		"左键点击 · 木门 / 烟囱 / 海面",
	]
	var lines: Array = fly_lines if active else orbit_lines
	for i in range(mini(_hint_lines.size(), lines.size())):
		(_hint_lines[i] as Label).text = str(lines[i])
	if _hint_keys != null:
		_hint_keys.text = ("空格 暂停 · Tab 天文历 · T 时间 · H 隐藏界面" if active
			else "空格 暂停 · Tab 天文历 · T 时间 · C 自动运镜 · H 隐藏界面")
	if _hint_keys2 != null:
		_hint_keys2.text = ("F2 截图 · F3 性能 · F11 全屏 · F 退出自由视角" if active
			else "F2 截图 · F3 性能 · F11 全屏")

func show_toast(text: String) -> void:
	_toast.text = text
	_toast.visible = true
	_toast_t = 2.6
	var tw := create_tween()
	_toast.modulate = Color(1, 1, 1, 0)
	tw.tween_property(_toast, "modulate:a", 1.0, 0.25)

func toggle_almanac() -> void:
	_almanac_open = not _almanac_open
	_almanac.visible = _almanac_open
	if _almanac_open:
		_refresh_almanac()

## F3：帧率/绘制开销叠层。数值全部由主循环采样后传入，HUD 不自行计时。
func toggle_perf() -> void:
	_perf_open = not _perf_open
	_perf_panel.visible = _perf_open and _visible_now
	if _perf_open:
		_perf_label.text = "F3 性能 · 采样中…"

func update_perf(d: Dictionary) -> void:
	if not _perf_open:
		return
	_perf_label.text = "%s  %s\nFPS %4.0f · 帧 %5.2f ms\nCPU %5.2f ms\n绘制 %4d · 对象 %5d\n显存 %5.1f MB · 灯 %d / 草 %d\n画质 %s" % [
		str(d.get("clock", "--:--")),
		str(d.get("phase", "")),
		float(d.get("fps", 0.0)),
		float(d.get("frame_ms", 0.0)),
		float(d.get("cpu_ms", 0.0)),
		int(d.get("draw_calls", 0)),
		int(d.get("objects", 0)),
		float(d.get("vram_mb", 0.0)),
		int(d.get("lights", 0)),
		int(d.get("grass", 0)),
		str(d.get("quality", "—")),
	]

## 鼠标悬停在可交互物件上时的提示；位置在 _process 中跟随光标。
func show_hover_hint(text: String) -> void:
	if _hover_label == null:
		return
	if _hover_text == text and _hover_label.visible:
		return
	_hover_text = text
	_hover_label.text = text
	_hover_label.visible = true
	_hover_label.modulate = Color(1, 1, 1, 0)
	create_tween().tween_property(_hover_label, "modulate:a", 1.0, 0.12)

func hide_hover_hint() -> void:
	if _hover_label == null or not _hover_label.visible:
		return
	_hover_text = ""
	_hover_label.visible = false

func set_hud_visible(v: bool, animate: bool = true) -> void:
	_visible_now = v
	if animate:
		var tw := create_tween()
		tw.tween_property(_root, "modulate:a", 1.0 if v else 0.0, 0.45)
	else:
		_root.modulate = Color(1, 1, 1, 1.0 if v else 0.0)
	_root.visible = true
	if not v:
		if _almanac_open:
			_almanac_open = false
			_almanac.visible = false
		if _time_open:
			_time_open = false
			_time_panel.visible = false
		if _perf_panel != null:
			_perf_panel.visible = false
		hide_hover_hint()
	elif _perf_open and _perf_panel != null:
		_perf_panel.visible = true

func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t <= 0.0:
			var tw := create_tween()
			tw.tween_property(_toast, "modulate:a", 0.0, 0.4)
	# 时间面板展开后若长时间无人操作自动收折，避免长期遮挡画面
	if _time_open:
		var mp := get_viewport().get_mouse_position()
		var over: bool = _time_panel.get_global_rect().has_point(mp)
		if over:
			_time_idle = 0.0
		else:
			_time_idle += delta
			if _time_idle > 14.0:
				_time_open = false
				_time_panel.visible = false
	if _hover_label != null and _hover_label.visible:
		var mp := get_viewport().get_mouse_position()
		var vs := get_viewport().get_visible_rect().size
		var sz := _hover_label.get_combined_minimum_size()
		_hover_label.size = sz
		_hover_label.position = (mp + Vector2(18, 16)).clamp(Vector2(8, 8), vs - sz - Vector2(8, 8))