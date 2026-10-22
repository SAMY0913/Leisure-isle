class_name IsleHud
extends CanvasLayer
## Relaxed-view HUD: clock, date, sky phase, compass ribbon, an almanac panel
## and a collapsible 24-hour time console that drives the shared simulation clock.

signal time_adjust(seconds_delta: float)
## 直接设定“当天时刻”（秒），用于可拖动时间轴；与 time_adjust 共用同一个主模拟时钟。
signal time_set(seconds_of_day: float)
## 时间来源切换请求（"real" / "sim"）：HUD 只负责 UI 与信号，状态源与保存由 main / 设置菜单负责。
signal time_mode_requested(mode: String)
## P8：面板内可见的暂停按钮；与空格键共用同一个 main._paused 权威状态，HUD 只发请求。
signal pause_toggle_requested
## P8：日历弹层请求跳到完整公历日期时间；合法性夹取与落地由 main._jump_datetime 统一负责。
signal datetime_jump_requested(year: int, month: int, day: int, hour: int, minute: int)

# P8 阶段 5：天气面板只发请求，天气状态唯一源在主循环的 IsleWeather 实例。
signal weather_auto_requested(enabled: bool)
signal weather_type_requested(type_id: String)

const ScrubberCtl := preload("res://scripts/ui_time_scrubber.gd")
## P8 日历：把“年月日时分”离散编辑量换算成主时钟秒数（isle_calendar 为纯函数模块，不持有时钟）。
const CalendarCtl := preload("res://scripts/isle_calendar.gd")
## 时间面板高度：普通态 / 日历展开态（只改布局，不改任何时间状态）。
const TIME_PANEL_TOP := -524.0
const TIME_PANEL_TOP_CAL := -744.0
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

# ---- P8 日历 / 可见暂停（完整公历编辑，主时钟仍是 main._sim_seconds）----
const CAL_FIELDS := ["year", "month", "day", "hour", "minute"]
var _pause_btn: Button
var _time_date: Label
var _cal_toggle: Button
var _cal_section: VBoxContainer
var _cal_open: bool = false
var _cal_draft: Dictionary = {}
var _cal_value_labels: Dictionary = {}
## 用户已修改草稿但尚未跳转：此时不要用权威时钟回灌，避免把编辑内容冲掉。
var _cal_dirty: bool = false
var _cal_preview: Label

# ---- P8 天气面板（可折叠；与时间面板同样的空闲自动收折 / H 同步收起）----
const WeatherCtl := preload("res://scripts/isle_weather.gd")
const WEATHER_PANEL_TOP := -338.0   # 内容高度约 270px + 内边距（手动按钮最多 11 个，4 列 3 行），不留空白
var _weather_pill: Button
var _weather_panel: PanelContainer
var _weather_open: bool = false
var _weather_idle: float = 0.0
var _weather_big: Label
var _weather_sub: Label
var _weather_hold: Label
var _weather_next: Label
var _weather_auto_btn: Button
var _weather_manual_btn: Button
var _weather_type_grid: GridContainer
var _weather_type_buttons: Dictionary = {}
var _weather_types_sig: String = ""
var _weather_mode_ui: String = ""
var _weather_active_ui: String = ""

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
	_hint.position = Vector2(-436, 24)
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
		l.custom_minimum_size = Vector2(400, 0)
		_hint.add_child(l)
		_hint_lines.append(l)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	_hint.add_child(spacer)
	var keys := _mk_label("空格 暂停 · Tab 天文历 · T 时间 · W 天气 · C 自动运镜 · H 隐藏界面", 11, Color(0.72, 0.66, 0.56, 0.85), 2)
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	keys.custom_minimum_size = Vector2(400, 0)
	_hint.add_child(keys)
	_hint_keys = keys
	var keys2 := _mk_label("F2 截图 · F3 性能 · F11 全屏", 11, Color(0.72, 0.66, 0.56, 0.85), 2)
	keys2.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	keys2.custom_minimum_size = Vector2(400, 0)
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
	# ---- P8 collapsible weather console ----
	_build_weather_console()

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
	# P8：再新增日期行 + 日历编辑区，面板高度由 TIME_PANEL_TOP / TIME_PANEL_TOP_CAL 控制。
	_time_panel.offset_top = TIME_PANEL_TOP
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

	# P8：日期 / 星期 / 季节 + 可见暂停按钮（与空格共享同一权威状态）
	var date_row := HBoxContainer.new()
	date_row.add_theme_constant_override("separation", 8)
	v.add_child(date_row)
	_time_date = _mk_label("", 12, Color(0.90, 0.84, 0.74, 0.95), 3)
	_time_date.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	date_row.add_child(_time_date)
	_pause_btn = _mk_button("暂停", 12, _on_pause_pressed)
	_pause_btn.custom_minimum_size = Vector2(74, 28)
	date_row.add_child(_pause_btn)

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

	# P8：日历编辑入口 + 折叠编辑区（年 / 月 / 日 / 时 / 分，跳转仍走 main 权威时钟）
	_cal_toggle = _mk_button("编辑日期与时间 ▾", 11, _toggle_calendar)
	v.add_child(_cal_toggle)
	_cal_section = VBoxContainer.new()
	_cal_section.add_theme_constant_override("separation", 6)
	_cal_section.visible = false
	v.add_child(_cal_section)
	_cal_row(_cal_section, "year", "年")
	_cal_row(_cal_section, "month", "月")
	_cal_row(_cal_section, "day", "日")
	_cal_row(_cal_section, "hour", "时")
	_cal_row(_cal_section, "minute", "分")
	_cal_preview = _mk_label("", 11, Color(0.82, 0.76, 0.66, 0.92), 2)
	_cal_preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cal_section.add_child(_cal_preview)
	var jump_row := HBoxContainer.new()
	jump_row.add_theme_constant_override("separation", 8)
	_cal_section.add_child(jump_row)
	var jump_btn := _mk_button("跳转到该时刻", 12, _on_cal_jump)
	jump_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	jump_btn.custom_minimum_size = Vector2(0, 30)
	jump_row.add_child(jump_btn)
	var reset_btn := _mk_button("回到当前", 11, _on_cal_reset)
	reset_btn.custom_minimum_size = Vector2(84, 30)
	jump_row.add_child(reset_btn)

	_time_note = _mk_label(TIME_NOTE_SIM, 10, Color(0.68, 0.62, 0.53, 0.9), 2)
	_time_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_time_note.custom_minimum_size = Vector2(320, 0)
	v.add_child(_time_note)

# ---- P8 阶段 5：天气面板（自动 / 手动 + 季节合法选项；只读主循环的天气状态）----

## 折叠态小胶囊放在时间胶囊右侧；展开态是独立的左下角小面板，不遮挡时间面板。
func _build_weather_console() -> void:
	_weather_pill = _mk_button("☁ 天气  --", 14, _toggle_weather_panel)
	_weather_pill.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_weather_pill.offset_left = 204.0
	_weather_pill.offset_right = 372.0
	_weather_pill.offset_top = -66.0
	_weather_pill.offset_bottom = -32.0
	_weather_pill.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_root.add_child(_weather_pill)

	_weather_panel = PanelContainer.new()
	_weather_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_weather_panel.offset_left = 398.0
	_weather_panel.offset_right = 754.0
	_weather_panel.offset_top = WEATHER_PANEL_TOP
	_weather_panel.offset_bottom = -32.0
	_weather_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.045, 0.055, 0.075, 0.72)))
	_weather_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_weather_panel.visible = false
	_root.add_child(_weather_panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_weather_panel.add_child(v)

	var header := HBoxContainer.new()
	v.add_child(header)
	var ttl := _mk_label("天气 · WEATHER", 15, ACCENT, 3)
	ttl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(ttl)
	var collapse := _mk_button("收折 ▾", 12, _toggle_weather_panel)
	collapse.custom_minimum_size = Vector2(70, 28)
	header.add_child(collapse)

	_weather_big = _mk_label("--", 26, CREAM, 4)
	_weather_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_weather_big)

	_weather_sub = _mk_label("", 11, Color(0.90, 0.84, 0.74, 0.95), 2)
	_weather_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_weather_sub)

	_weather_hold = _mk_label("", 10, Color(0.82, 0.76, 0.66, 0.92), 2)
	_weather_hold.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_weather_hold)

	_weather_next = _mk_label("", 10, Color(0.80, 0.74, 0.62, 0.9), 2)
	_weather_next.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_weather_next)

	var line := ColorRect.new()
	line.color = Color(1.0, 0.88, 0.71, 0.16)
	line.custom_minimum_size = Vector2(0, 1)
	v.add_child(line)

	# 自动 / 手动：与时间来源切换同一种双按钮交互，当前模式高亮。
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 8)
	v.add_child(mode_row)
	var mode_lbl := _mk_label("模式", 11, DIM, 2)
	mode_lbl.custom_minimum_size = Vector2(32, 0)
	mode_row.add_child(mode_lbl)
	_weather_auto_btn = _mk_button("自动", 12, _on_weather_auto_pressed)
	_weather_auto_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weather_auto_btn.custom_minimum_size = Vector2(0, 28)
	_weather_auto_btn.tooltip_text = "按季节权重与确定性随机自动推进天气"
	mode_row.add_child(_weather_auto_btn)
	_weather_manual_btn = _mk_button("手动", 12, _on_weather_manual_pressed)
	_weather_manual_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weather_manual_btn.custom_minimum_size = Vector2(0, 28)
	_weather_manual_btn.tooltip_text = "锁定手动选择的天气，直到切回自动"
	mode_row.add_child(_weather_manual_btn)

	var pick_lbl := _mk_label("手动选择 · 仅列本季合法选项", 10, Color(0.68, 0.62, 0.53, 0.9), 2)
	v.add_child(pick_lbl)
	_weather_type_grid = GridContainer.new()
	# P8.1：12 类按季节过滤后为 8/9/9/11 个按钮；4 列 → 最多 3 行。
	# 不要改成 6 列：6×72px + 间距 ≈457px 会超出面板内容宽度（面板 356px）。
	_weather_type_grid.columns = 4
	_weather_type_grid.add_theme_constant_override("h_separation", 5)
	_weather_type_grid.add_theme_constant_override("v_separation", 4)
	v.add_child(_weather_type_grid)

	var note := _mk_label("天气只影响观感，不改变任何进度 · W 收折", 10, Color(0.62, 0.57, 0.49, 0.82), 2)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(320, 0)
	v.add_child(note)

func _toggle_weather_panel() -> void:
	_weather_open = not _weather_open
	_weather_panel.visible = _weather_open
	_weather_idle = 0.0
	if _weather_open:
		_refresh_weather(_data)

func toggle_weather_panel() -> void:
	_toggle_weather_panel()

## 收起天气面板的公共路径（收折按钮 / 空闲自动收折 / H 隐藏界面共用）。
func _collapse_weather_panel() -> void:
	_weather_open = false
	_weather_panel.visible = false

## 只读主循环传入的 weather 状态字典：胶囊与面板文字都从这里派生，不保存第二份天气状态。
func _refresh_weather(d: Dictionary) -> void:
	var w: Dictionary = d.get("weather", {})
	if w.is_empty():
		return
	var label := str(w.get("label", "晴"))
	var type_id := str(w.get("type", "clear"))
	var auto_on := bool(w.get("auto", true))
	var season_label := str(w.get("season_label", "春季"))
	var intensity := clampf(float(w.get("intensity", 0.0)), 0.0, 1.0)
	if _weather_pill != null:
		var pill_text := "☁ 天气  " + label
		if _weather_pill.text != pill_text:
			_weather_pill.text = pill_text
	if _weather_panel == null or not _weather_panel.visible:
		return
	if _weather_big.text != label:
		_weather_big.text = label
	var sub := "%s · %s · 强度 %d%%" % [season_label, "自动" if auto_on else "手动", int(round(intensity * 100.0))]
	if _weather_sub.text != sub:
		_weather_sub.text = sub
	var hold_text := ""
	if auto_on:
		var hold_left := maxf(0.0, float(w.get("hold_left", 0.0)))
		var hold_total := maxf(0.0, float(w.get("hold_total", 0.0)))
		hold_text = "预计再持续 %s" % _weather_duration_text(hold_left)
		if hold_total > 0.0:
			hold_text += " · 本轮共 %s" % _weather_duration_text(hold_total)
	else:
		hold_text = "手动锁定中 · 天气不会自行变化"
	if _weather_hold.text != hold_text:
		_weather_hold.text = hold_text
	var next_text := ""
	if auto_on:
		var nxt := str(w.get("next_label", ""))
		var trans := clampf(float(w.get("transition", 0.0)), 0.0, 1.0)
		if not nxt.is_empty() and nxt != label and trans > 0.02:
			next_text = "过渡中 · 即将转为 %s" % nxt
		elif not nxt.is_empty() and nxt != label:
			next_text = "趋势 · 之后转为 %s" % nxt
		else:
			next_text = "趋势 · 持续%s" % label
	else:
		next_text = "切回自动后恢复季节权重随机"
	if _weather_next.text != next_text:
		_weather_next.text = next_text
	_refresh_weather_types(w)
	_apply_weather_mode_ui("auto" if auto_on else "manual", type_id)

## 把模拟秒换算成游戏内时长文本（权威时钟仍是模拟秒；显示只做单位换算）。
func _weather_duration_text(seconds: float) -> String:
	var total_min := int(round(seconds / 60.0))
	if total_min <= 0:
		return "不足 1 分钟"
	var hours := total_min / 60
	var mins := total_min % 60
	if hours <= 0:
		return "%d 分钟" % mins
	if mins <= 0:
		return "%d 小时" % hours
	return "%d 小时 %d 分" % [hours, mins]

## 手动类型按钮只在季节/合法集合变化时重建，避免 0.12s 刷新周期反复创建控件。
func _refresh_weather_types(w: Dictionary) -> void:
	var avail: Array = w.get("available_types", [])
	if avail.is_empty() or _weather_type_grid == null:
		return
	var sig := str(avail)
	if sig == _weather_types_sig:
		return
	_weather_types_sig = sig
	for child in _weather_type_grid.get_children():
		_weather_type_grid.remove_child(child)
		child.queue_free()
	_weather_type_buttons.clear()
	for raw in avail:
		var type_id := str(raw)
		var label := str(WeatherCtl.TYPE_LABELS.get(type_id, type_id))
		var b := _mk_button(label, 11, Callable(self, "_on_weather_type_pressed").bind(type_id))
		b.custom_minimum_size = Vector2(72, 26)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = "手动设为%s（进入手动模式）" % label
		_weather_type_grid.add_child(b)
		_weather_type_buttons[type_id] = b
	_weather_mode_ui = ""
	_weather_active_ui = ""

func _style_weather_rest(b: Button) -> void:
	b.add_theme_color_override("font_color", CREAM)
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.97, 0.9))
	b.add_theme_stylebox_override("normal", _btn_style(Color(0.06, 0.075, 0.10, 0.72), Color(1.0, 0.9, 0.74, 0.18)))
	b.add_theme_stylebox_override("hover", _btn_style(Color(0.11, 0.13, 0.17, 0.85), Color(1.0, 0.85, 0.64, 0.42)))
	b.add_theme_stylebox_override("pressed", _btn_style(Color(0.16, 0.13, 0.11, 0.9), Color(1.0, 0.78, 0.52, 0.7)))

func _style_weather_active(b: Button) -> void:
	b.add_theme_color_override("font_color", ACCENT)
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.86, 0.66))
	b.add_theme_stylebox_override("normal", _btn_style(Color(0.24, 0.17, 0.12, 0.95), ACCENT))
	b.add_theme_stylebox_override("hover", _btn_style(Color(0.30, 0.21, 0.14, 0.98), Color(0.95, 0.72, 0.50)))
	b.add_theme_stylebox_override("pressed", _btn_style(Color(0.20, 0.14, 0.10, 0.98), ACCENT))

## 模式高亮 + 手动类型高亮；只在变化时重刷 stylebox（避免每帧分配资源）。
func _apply_weather_mode_ui(mode: String, active_type: String) -> void:
	var active_key := active_type if mode == "manual" else ""
	if _weather_mode_ui == mode and _weather_active_ui == active_key:
		return
	_weather_mode_ui = mode
	_weather_active_ui = active_key
	if _weather_auto_btn != null:
		if mode == "auto":
			_style_weather_active(_weather_auto_btn)
		else:
			_style_weather_rest(_weather_auto_btn)
	if _weather_manual_btn != null:
		if mode == "manual":
			_style_weather_active(_weather_manual_btn)
		else:
			_style_weather_rest(_weather_manual_btn)
	for raw in _weather_type_buttons.keys():
		var key := str(raw)
		var b := _weather_type_buttons[raw] as Button
		if b == null:
			continue
		if mode == "manual" and key == active_type:
			_style_weather_active(b)
		else:
			_style_weather_rest(b)

func _on_weather_auto_pressed() -> void:
	_weather_idle = 0.0
	weather_auto_requested.emit(true)

func _on_weather_manual_pressed() -> void:
	_weather_idle = 0.0
	weather_auto_requested.emit(false)

## 手动类型：只发请求；合法性由主循环按权威天气状态的 available_types 判定（非法会给 toast）。
func _on_weather_type_pressed(type_id: String) -> void:
	_weather_idle = 0.0
	weather_type_requested.emit(type_id)

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
	_refresh_date_row(d)
	_refresh_pause_state()
	if _cal_open and not _cal_dirty:
		_seed_cal_draft(false)
	_heading = float(d.get("heading", 0.0))
	_compass.queue_redraw()
	_refresh_time_display()
	_refresh_day_length_note(d)
	_refresh_weather(d)
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
	# P8：现实时间模式下暂停 / 日历编辑只读，避免 UI 承诺做不到的操作
	if _cal_toggle != null:
		_cal_toggle.disabled = real
		_cal_toggle.modulate = Color(1.0, 1.0, 1.0, 0.45) if real else Color(1.0, 1.0, 1.0, 1.0)
		if real and _cal_open:
			_close_calendar()
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
		_seed_cal_draft(false)
	else:
		_close_calendar()

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

# ---- P8：日历编辑区（只读主时钟 _data，编辑草稿本地保存，跳转由 main 落地）----

func _refresh_date_row(d: Dictionary) -> void:
	if _time_date == null:
		return
	var line: String = str(d.get("date", ""))
	var weekday: String = str(d.get("weekday", ""))
	if not weekday.is_empty():
		line += "  " + weekday
	var season_label: String = str(d.get("season_label", ""))
	if not season_label.is_empty():
		line += "  ·  " + season_label
	if _time_date.text != line:
		_time_date.text = line

## 暂停按钮文案 / 可用性：现实时间模式下时钟不可暂停，按钮置灰。
func _refresh_pause_state() -> void:
	if _pause_btn == null:
		return
	var paused := bool(_data.get("paused", false))
	var real: bool = _time_source == "real"
	var text := "继续" if paused else "暂停"
	if _pause_btn.text != text:
		_pause_btn.text = text
	var tip := "暂停模拟时间（空格）"
	if real:
		tip = "现实时间模式：时钟跟随系统，不可暂停"
	elif paused:
		tip = "继续模拟时间（空格）"
	if _pause_btn.tooltip_text != tip:
		_pause_btn.tooltip_text = tip
	_pause_btn.disabled = real
	_pause_btn.modulate = Color(1.0, 1.0, 1.0, 0.45) if real else Color(1.0, 1.0, 1.0, 1.0)

## 暂停按钮：只发请求，_paused 的唯一状态源在 main（与空格键同一函数）。
func _on_pause_pressed() -> void:
	if _time_source == "real":
		show_toast("现实时间模式：时间随现实时钟前进")
		return
	_time_idle = 0.0
	pause_toggle_requested.emit()

## 展开 / 收折日历编辑区：只改布局与本 UI 草稿，不改任何时间状态。
func _toggle_calendar() -> void:
	_cal_open = not _cal_open
	_cal_section.visible = _cal_open
	_cal_toggle.text = "日期与时间 · 收起 ▴" if _cal_open else "编辑日期与时间 ▾"
	_time_panel.offset_top = TIME_PANEL_TOP_CAL if _cal_open else TIME_PANEL_TOP
	_time_idle = 0.0
	if _cal_open:
		_seed_cal_draft(true)

## 折叠日历（收起时间面板 / 隐藏 HUD / 自动收折时调用）：不触发信号、不动时间状态。
func _close_calendar() -> void:
	if not _cal_open:
		return
	_cal_open = false
	_cal_section.visible = false
	_cal_toggle.text = "编辑日期与时间 ▾"
	_time_panel.offset_top = TIME_PANEL_TOP

## 收起时间面板的公共路径：同步收日历并恢复面板高度。
func _collapse_time_panel() -> void:
	_time_open = false
	_time_panel.visible = false
	_close_calendar()

## 一行 [单位][−][数值][＋]；回调带字段名与增量，全部夹取走 isle_calendar.clamp_parts。
func _cal_row(parent: VBoxContainer, field: String, title: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	var lab := _mk_label(title, 12, DIM, 2)
	lab.custom_minimum_size = Vector2(26, 0)
	row.add_child(lab)
	var minus := _mk_button("−", 15, Callable(self, "_cal_step").bind(field, -1))
	minus.custom_minimum_size = Vector2(36, 28)
	row.add_child(minus)
	var val := _mk_label("--", 16, CREAM, 3)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(val)
	_cal_value_labels[field] = val
	var plus := _mk_button("+", 15, Callable(self, "_cal_step").bind(field, 1))
	plus.custom_minimum_size = Vector2(36, 28)
	row.add_child(plus)

## 从权威时钟回灌草稿（force=true 丢弃用户未跳转的编辑，用于“回到当前”）。
func _seed_cal_draft(force: bool = false) -> void:
	if not force and _cal_dirty:
		return
	_cal_draft = {
		"year": int(_data.get("year", 2026)),
		"month": int(_data.get("month", 1)),
		"day": int(_data.get("day", 1)),
		"hour": int(_data.get("hour", 0)),
		"minute": int(_data.get("minute", 0)),
	}
	_cal_dirty = false
	_refresh_cal_labels()

func _refresh_cal_labels() -> void:
	if _cal_value_labels.is_empty():
		return
	for field in CAL_FIELDS:
		if not _cal_value_labels.has(field):
			continue
		var lab := _cal_value_labels[field] as Label
		if field == "year":
			lab.text = "%04d" % int(_cal_draft.get("year", 2026))
		elif field == "month":
			lab.text = "%02d" % int(_cal_draft.get("month", 1))
		elif field == "day":
			lab.text = "%02d" % int(_cal_draft.get("day", 1))
		elif field == "hour":
			lab.text = "%02d" % int(_cal_draft.get("hour", 0))
		else:
			lab.text = "%02d" % int(_cal_draft.get("minute", 0))
	if _cal_preview != null:
		var cal := CalendarCtl.parts(CalendarCtl.to_local_seconds(
			int(_cal_draft.get("year", 2026)), int(_cal_draft.get("month", 1)),
			int(_cal_draft.get("day", 1)), int(_cal_draft.get("hour", 0)),
			int(_cal_draft.get("minute", 0)), 0))
		_cal_preview.text = "%s  %s" % [str(cal.get("date_label", "")), str(cal.get("weekday_cn", ""))]

## 单步编辑：年夹 1..9999；月 / 时 / 分跨边界回绕；日按当月天数夹取（由 clamp_parts 负责）。
func _cal_step(field: String, delta: int) -> void:
	var y := int(_cal_draft.get("year", 2026))
	var mo := int(_cal_draft.get("month", 1))
	var d := int(_cal_draft.get("day", 1))
	var h := int(_cal_draft.get("hour", 0))
	var mi := int(_cal_draft.get("minute", 0))
	match field:
		"year":
			y = clampi(y + delta, CalendarCtl.MIN_YEAR, CalendarCtl.MAX_YEAR)
		"month":
			mo = wrapi(mo + delta, 1, 13)
		"day":
			d += delta
		"hour":
			h = wrapi(h + delta, 0, 24)
		"minute":
			mi = wrapi(mi + delta, 0, 60)
		_:
			return
	_cal_draft = CalendarCtl.clamp_parts(y, mo, d, h, mi, 0)
	_cal_dirty = true
	_time_idle = 0.0
	_refresh_cal_labels()

func _on_cal_jump() -> void:
	if _time_source == "real":
		show_toast("现实时间模式 · 日期与时间只读")
		return
	_cal_dirty = false
	_time_idle = 0.0
	datetime_jump_requested.emit(
		int(_cal_draft.get("year", 2026)), int(_cal_draft.get("month", 1)),
		int(_cal_draft.get("day", 1)), int(_cal_draft.get("hour", 0)),
		int(_cal_draft.get("minute", 0)))

func _on_cal_reset() -> void:
	_time_idle = 0.0
	_seed_cal_draft(true)

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
			_collapse_time_panel()
		if _weather_open:
			_collapse_weather_panel()
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
				_collapse_time_panel()
	# 天气面板同样空闲自动收折（与时间面板一致的 14s，保持观景画面简洁）
	if _weather_open:
		var wmp := get_viewport().get_mouse_position()
		var wover: bool = _weather_panel.get_global_rect().has_point(wmp)
		if wover:
			_weather_idle = 0.0
		else:
			_weather_idle += delta
			if _weather_idle > 14.0:
				_collapse_weather_panel()
	if _hover_label != null and _hover_label.visible:
		var mp := get_viewport().get_mouse_position()
		var vs := get_viewport().get_visible_rect().size
		var sz := _hover_label.get_combined_minimum_size()
		_hover_label.size = sz
		_hover_label.position = (mp + Vector2(18, 16)).clamp(Vector2(8, 8), vs - sz - Vector2(8, 8))