class_name IsleMenu
extends CanvasLayer
## Cinematic title screen: 2.39:1 letterbox, slowly drifting island backdrop,
## start / settings / quit, and a radial fly-out transition into the game.
##
## Phase 6（T1）：ESC 菜单入场/退场改为「从屏幕外错峰滑入、反向滑出」的动画；
## 设置面板增加五档画质 + 三个高级覆盖开关、十档时间流速、五组音量、
## 三态窗口模式，以及分辨率 / 窗口模式的「保持 / 12 秒自动回退」确认层。

signal start_pressed(returning: bool)
signal quit_pressed
signal settings_changed(settings: Dictionary)

const RATIO := 2.39
const CREAM := Color("f4ead8")
const DIM := Color("c5b9a2")
const ACCENT := Color("d99a6c")
const INK := Color("0b0e14")

const S := preload("res://scripts/isle_settings.gd")
const SliderCtl := preload("res://scripts/ui_slider.gd")
## 时区弹层的真值来源（IANA 表 + 当前 UTC 偏移）。
const TimeSvc := preload("res://scripts/isle_time.gd")

const SENS_MIN := 0.2
const SENS_MAX := 3.0
const SENS_STEP := 0.05

## 画质高级覆盖开关：写入 quality_overrides（空字典 = 完全跟随预设档位）。
const OVERRIDE_ROWS := [
    {"key": "sea_ssr", "title": "海面反射 · SSR"},
    {"key": "post_ao", "title": "环境光遮蔽 · AO"},
    {"key": "volumetric_fog", "title": "体积雾 · FOG"},
]

## 窗口模式中文名（三态：窗口化 / 全屏 / 无边框窗口）。
const WINDOW_MODE_LABELS := {
    "windowed": "窗口化",
    "fullscreen": "全屏",
    "borderless": "无边框窗口",
}

## ESC 菜单入场/退场：单项 0.52s、错峰 0.04s、8 项总长 0.80s（验收 <=0.9s）。
const ANIM_ITEM_TIME := 0.52
const ANIM_STAGGER := 0.04
const ANIM_NONE := 0
const ANIM_ENTER := 1
const ANIM_EXIT := 2

## 分辨率 / 窗口模式切换的确认停留时间（秒），超时自动回退。
const CONFIRM_SECONDS := 12.0

var _font: Font
var _letter_top: ColorRect
var _letter_bottom: ColorRect
var _menu_root: Control
var _fade: ColorRect
var _items: Array = []
var _title: Label
var _subtitle: Label
var _rule: ColorRect
var _start_btn: Button
var _settings_btn: Button
var _quit_btn: Button
var _hint: Label
var _version: Label
var _settings_dim: ColorRect
var _settings_panel: PanelContainer
var _setting_buttons: Dictionary = {}
var _sliders: Dictionary = {}
var _slider_value_labels: Dictionary = {}
var _quality_override_buttons: Dictionary = {}
var _settings_vb: VBoxContainer
var _settings_scroll: ScrollContainer
var _settings_open: bool = false
var _daylen_note: Label
# 时区选择弹层（仅现实时间模式可用）：搜索框 + 可滚动按钮列表。
var _tz_popup: PanelContainer
var _tz_search: LineEdit
var _tz_scroll: ScrollContainer
var _tz_list: VBoxContainer
var _tz_buttons: Array = []
var _tz_row: HBoxContainer
var _tz_popup_open: bool = false
## 第五阶段：分组时区选择器（常用时区 / 特殊时区规则，每组最多 2 个代表）。
var _tz_groups: Array = []
var _tz_group_blocks: Array = []
var _tz_section_headers: Dictionary = {}
var _tz_default_visible: Array = []
var _tz_last_now: float = -1.0
## 最近一次分组列表重建 / 刷新耗时（毫秒），供性能断言/日志。
var _tz_last_build_ms: float = 0.0
var _tz_last_refresh_ms: float = -1.0
var _closing: bool = false
var _returning: bool = false
var _bar_h: float = 0.0
var _values: Dictionary = {
    "day_length": 600.0,
    "sensitivity": 1.0,
    "auto": true,
    "quality": 2,
    "quality_overrides": {},
    "resolution": S.default_resolution(),
    "window_mode": "windowed",
    "time_source": "sim",
    "timezone": S.DEFAULT_TIMEZONE,
}

# ---- ESC 菜单入场/退场动画状态（单一 Tween，反复开关不叠加、不跳变） ----
var _anim_state: int = ANIM_NONE
var _anim_tween: Tween
var _anim_t: float = 0.0
var _anim_total: float = 0.0
var _items_home: Array = []
var _items_dir: Array = []
var _menu_buttons: Array = []
var _bar_tween: Tween
## 标题菜单螺旋飞出（_fly_out）的 Tween 列表：open 时必须 kill，避免旧 tween 继续写 rotation/position。
var _fly_tweens: Array = []

# ---- 分辨率 / 窗口模式确认层 ----
var _res_confirm_dim: ColorRect
var _res_confirm_panel: PanelContainer
var _res_confirm_label: Label
var _res_confirm_open: bool = false
var _res_confirm_t: float = 0.0
var _res_prev: Dictionary = {}
var _res_kind: String = ""

func _ready() -> void:
    layer = 10
    for group_spec in S.audio_groups():
        var key: String = str((group_spec as Dictionary).get("key", ""))
        if not key.is_empty() and not _values.has(key):
            _values[key] = S.audio_default(key)
    _font = _load_font()
    _build_letterbox()
    _build_menu()
    _build_settings()
    _build_res_confirm()
    _build_timezone_picker()
    _build_fade()
    get_viewport().size_changed.connect(_layout)
    _layout()
    _set_settings_visuals()

func _load_font() -> Font:
    var f := FontFile.new()
    var bytes := FileAccess.get_file_as_bytes("res://fonts/simhei.ttf")
    if bytes.size() > 0:
        f.data = bytes
        f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
        return f
    return ThemeDB.fallback_font

func _mk_label(text: String, size: int, color: Color, outline: int = 4) -> Label:
    var l := Label.new()
    l.text = text
    l.add_theme_font_override("font", _font)
    l.add_theme_font_size_override("font_size", size)
    l.add_theme_color_override("font_color", color)
    l.add_theme_color_override("font_outline_color", Color(0.02, 0.025, 0.04, 0.95))
    l.add_theme_constant_override("outline_size", outline)
    l.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return l

func _btn_style(primary: bool, hot: bool) -> StyleBoxFlat:
    var sb := StyleBoxFlat.new()
    if primary:
        sb.bg_color = Color(0.80, 0.53, 0.37, 0.96 if hot else 0.88)
        sb.border_color = Color(1.0, 0.86, 0.7, 0.65 if hot else 0.35)
    else:
        sb.bg_color = Color(0.03, 0.04, 0.055, 0.45 if not hot else 0.62)
        sb.border_color = Color(1.0, 0.88, 0.72, 0.42 if hot else 0.20)
    sb.corner_radius_top_left = 10
    sb.corner_radius_top_right = 10
    sb.corner_radius_bottom_left = 10
    sb.corner_radius_bottom_right = 10
    sb.border_width_left = 1
    sb.border_width_top = 1
    sb.border_width_right = 1
    sb.border_width_bottom = 1
    sb.shadow_color = Color(0, 0, 0, 0.28)
    sb.shadow_size = 12
    return sb

func _mk_button(text: String, primary: bool) -> Button:
    var b := Button.new()
    b.text = text
    b.add_theme_font_override("font", _font)
    b.add_theme_font_size_override("font_size", 21)
    b.add_theme_color_override("font_color", INK if primary else CREAM)
    b.add_theme_color_override("font_hover_color", Color(0.06, 0.05, 0.04) if primary else Color(1, 0.97, 0.92))
    b.add_theme_color_override("font_pressed_color", INK if primary else CREAM)
    b.add_theme_stylebox_override("normal", _btn_style(primary, false))
    b.add_theme_stylebox_override("hover", _btn_style(primary, true))
    b.add_theme_stylebox_override("pressed", _btn_style(primary, true))
    b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
    b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    b.mouse_entered.connect(func() -> void:
        var tw := create_tween()
        tw.tween_property(b, "modulate", Color(1.12, 1.08, 1.02, 1.0), 0.14))
    b.mouse_exited.connect(func() -> void:
        var tw := create_tween()
        tw.tween_property(b, "modulate", Color(1, 1, 1, 1), 0.18))
    return b

func _build_letterbox() -> void:
    _letter_top = ColorRect.new()
    _letter_top.color = Color("040405")
    _letter_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
    _letter_top.offset_bottom = 0.0
    _letter_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_letter_top)
    _letter_bottom = ColorRect.new()
    _letter_bottom.color = Color("040405")
    _letter_bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
    _letter_bottom.offset_top = 0.0
    _letter_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_letter_bottom)

func _build_menu() -> void:
    _menu_root = Control.new()
    _menu_root.set_anchors_preset(Control.PRESET_FULL_RECT)
    _menu_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_menu_root)
    _title = _mk_label("休闲小岛幻境", 68, CREAM, 10)
    _title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _menu_root.add_child(_title)
    _subtitle = _mk_label("LEISURE ISLE OF DUSK & DAWN", 15, Color(0.86, 0.78, 0.66, 0.92), 5)
    _subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _menu_root.add_child(_subtitle)
    _rule = ColorRect.new()
    _rule.color = Color(0.85, 0.55, 0.38, 0.85)
    _rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _menu_root.add_child(_rule)
    _start_btn = _mk_button("开始游戏", true)
    _start_btn.pressed.connect(_on_start_pressed)
    _menu_root.add_child(_start_btn)
    _settings_btn = _mk_button("设置", false)
    _settings_btn.pressed.connect(_on_settings_pressed)
    _menu_root.add_child(_settings_btn)
    _quit_btn = _mk_button("离开", false)
    _quit_btn.pressed.connect(_on_quit_pressed)
    _menu_root.add_child(_quit_btn)
    _hint = _mk_label("一次缓慢的黄昏 · 无需目标，只需看着", 12, Color(0.82, 0.75, 0.64, 0.85), 3)
    _hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _menu_root.add_child(_hint)
    _version = _mk_label("GODOT 4.7 · 程序化绘本 · 致敬《休闲小岛幻境》", 10, Color(0.7, 0.65, 0.57, 0.75), 2)
    _version.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    _menu_root.add_child(_version)
    _items = [_title, _subtitle, _rule, _start_btn, _settings_btn, _quit_btn, _hint, _version]
    _menu_buttons = [_start_btn, _settings_btn, _quit_btn]

func _build_settings() -> void:
    _settings_dim = ColorRect.new()
    _settings_dim.color = Color(0.0, 0.0, 0.0, 0.0)
    _settings_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
    _settings_dim.mouse_filter = Control.MOUSE_FILTER_STOP
    _settings_dim.visible = false
    _menu_root.add_child(_settings_dim)
    _settings_panel = PanelContainer.new()
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color(0.045, 0.052, 0.068, 0.94)
    sb.corner_radius_top_left = 16
    sb.corner_radius_top_right = 16
    sb.corner_radius_bottom_left = 16
    sb.corner_radius_bottom_right = 16
    sb.border_width_left = 1
    sb.border_width_top = 1
    sb.border_width_right = 1
    sb.border_width_bottom = 1
    sb.border_color = Color(1.0, 0.87, 0.70, 0.22)
    sb.content_margin_left = 34.0
    sb.content_margin_right = 34.0
    sb.content_margin_top = 26.0
    sb.content_margin_bottom = 26.0
    sb.shadow_color = Color(0, 0, 0, 0.45)
    sb.shadow_size = 24
    _settings_panel.add_theme_stylebox_override("panel", sb)
    _settings_panel.visible = false
    _menu_root.add_child(_settings_panel)
    _settings_scroll = ScrollContainer.new()
    _settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    _settings_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
    _settings_panel.add_child(_settings_scroll)
    var vb := VBoxContainer.new()
    vb.add_theme_constant_override("separation", 14)
    vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _settings_scroll.add_child(vb)
    _settings_vb = vb
    var head := _mk_label("设置 · SETTINGS", 24, CREAM, 4)
    vb.add_child(head)
    var line := ColorRect.new()
    line.color = Color(1.0, 0.88, 0.71, 0.18)
    line.custom_minimum_size = Vector2(0, 1)
    vb.add_child(line)
    # ---- 时间 ----
    _add_section(vb, "时间 · TIME")
    _add_day_length_row(vb)
    _add_setting_row(vb, "time_source", "时间来源", "模拟时间")
    _tz_row = _add_setting_row(vb, "timezone", "时区", "上海 · Asia/Shanghai")
    # ---- 画面 ----
    _add_section(vb, "画面 · DISPLAY")
    _add_slider_row(vb, "sensitivity", "相机灵敏度", SENS_MIN, SENS_MAX, SENS_STEP)
    _add_setting_row(vb, "auto", "自动运镜", "开")
    _add_setting_row(vb, "window_mode", "窗口模式", "窗口化")
    _add_resolution_slider_row(vb)
    _add_slider_row(vb, "quality", "画质", 0.0, float(S.QUALITY_COUNT - 1), 1.0)
    if _sliders.has("quality"):
        (_sliders["quality"] as Control).call("set_tick_count", S.QUALITY_COUNT)
    for spec in OVERRIDE_ROWS:
        _add_override_row(vb, str(spec["key"]), str(spec["title"]))
    # ---- 音量 ----
    _add_section(vb, "音量 · AUDIO")
    for group_spec in S.audio_groups():
        var group: Dictionary = group_spec as Dictionary
        var key: String = str(group.get("key", ""))
        if key.is_empty():
            continue
        _add_slider_row(vb, key, str(group.get("label", key)), 0.0, 1.0, 0.01)
        if _sliders.has(key):
            (_sliders[key] as Control).tooltip_text = str(group.get("hint", ""))
    # 兼容旧截图流程与旧测试：_sliders["volume"] 指向主音量滑条。
    if _sliders.has("volume_master"):
        _sliders["volume"] = _sliders["volume_master"]
        _slider_value_labels["volume"] = _slider_value_labels["volume_master"]
    var note := _mk_label("设置会保存到本地，下次启动继续沿用。切换分辨率 / 全屏 / 无边框后需在 12 秒内确认，否则自动回退。", 11, Color(0.68, 0.62, 0.53, 0.9), 2)
    note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    vb.add_child(note)
    var back := _mk_button("返回", false)
    back.custom_minimum_size = Vector2(0, 46)
    back.pressed.connect(close_settings)
    vb.add_child(back)
    _settings_panel.custom_minimum_size = Vector2(660, 0)

func _add_section(vb: VBoxContainer, title: String) -> void:
    var l := _mk_label(title, 13, ACCENT, 3)
    vb.add_child(l)

func _add_setting_row(vb: VBoxContainer, key: String, title: String, value_text: String) -> HBoxContainer:
    var hb := HBoxContainer.new()
    hb.add_theme_constant_override("separation", 16)
    vb.add_child(hb)
    var nl := _mk_label(title, 16, CREAM, 3)
    nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    nl.custom_minimum_size = Vector2(200, 0)
    hb.add_child(nl)
    var vb2 := _mk_button(value_text, false)
    vb2.custom_minimum_size = Vector2(230, 44)
    vb2.add_theme_font_size_override("font_size", 15)
    vb2.pressed.connect(func() -> void: _on_setting_pressed(key))
    hb.add_child(vb2)
    _setting_buttons[key] = vb2
    return hb

## 定量设置行：标题 + 可拖动滑条 + 当前值。拖动实时生效，数值文字同步刷新。
func _add_slider_row(vb: VBoxContainer, key: String, title: String, mn: float, mx: float, st: float) -> void:
    var hb := HBoxContainer.new()
    hb.add_theme_constant_override("separation", 14)
    vb.add_child(hb)
    var nl := _mk_label(title, 16, CREAM, 3)
    nl.custom_minimum_size = Vector2(180, 0)
    nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    hb.add_child(nl)
    var slider := SliderCtl.new()
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    slider.custom_minimum_size = Vector2(220, 34)
    hb.add_child(slider)
    var val_l := _mk_label("", 14, Color(0.92, 0.85, 0.74, 0.95), 2)
    val_l.custom_minimum_size = Vector2(150, 0)
    val_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    val_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    hb.add_child(val_l)
    slider.configure(mn, mx, st, float(_values.get(key, mn)))
    slider.value_changed.connect(func(v: float) -> void: _on_slider_changed(key, v))
    _sliders[key] = slider
    _slider_value_labels[key] = val_l
    _refresh_slider_label(key)

## 时间流速行：十档「每游戏日现实秒数」，滑条走档位索引（0..9，step 1）。
func _add_day_length_row(vb: VBoxContainer) -> void:
    var hb := HBoxContainer.new()
    hb.add_theme_constant_override("separation", 14)
    vb.add_child(hb)
    var nl := _mk_label("时间流速", 16, CREAM, 3)
    nl.custom_minimum_size = Vector2(180, 0)
    nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    hb.add_child(nl)
    var slider := SliderCtl.new()
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    slider.custom_minimum_size = Vector2(220, 34)
    hb.add_child(slider)
    var val_l := _mk_label("", 14, Color(0.92, 0.85, 0.74, 0.95), 2)
    val_l.custom_minimum_size = Vector2(150, 0)
    val_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    val_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    hb.add_child(val_l)
    var idx: int = S.day_length_index(float(_values["day_length"]))
    slider.configure(0.0, float(S.DAY_LENGTH_PRESETS.size() - 1), 1.0, float(idx))
    slider.set_tick_count(S.DAY_LENGTH_PRESETS.size())
    slider.value_changed.connect(func(v: float) -> void: _on_slider_changed("day_length", v))
    _sliders["day_length"] = slider
    _slider_value_labels["day_length"] = val_l
    _refresh_slider_label("day_length")
    _daylen_note = _mk_label(S.DAY_LENGTH_HINT, 11, Color(0.68, 0.62, 0.53, 0.9), 2)
    _daylen_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    vb.add_child(_daylen_note)

## 画质高级覆盖行：三态（跟随预设 → 与预设相反 → 与预设相同 → 跟随预设）。
func _add_override_row(vb: VBoxContainer, key: String, title: String) -> void:
    var hb := HBoxContainer.new()
    hb.add_theme_constant_override("separation", 16)
    vb.add_child(hb)
    var nl := _mk_label(title, 16, CREAM, 3)
    nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    nl.custom_minimum_size = Vector2(200, 0)
    hb.add_child(nl)
    var btn := _mk_button("跟随预设", false)
    btn.custom_minimum_size = Vector2(230, 44)
    btn.add_theme_font_size_override("font_size", 15)
    btn.pressed.connect(func() -> void: _cycle_override(key))
    hb.add_child(btn)
    _quality_override_buttons[key] = btn

## 分辨率行：滑条按预设列表索引；拖动只更新文字，松手后进入确认层。
func _add_resolution_slider_row(vb: VBoxContainer) -> void:
    var hb := HBoxContainer.new()
    hb.add_theme_constant_override("separation", 14)
    vb.add_child(hb)
    var nl := _mk_label("分辨率", 16, CREAM, 3)
    nl.custom_minimum_size = Vector2(180, 0)
    nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    hb.add_child(nl)
    var presets: Array = S.resolution_presets()
    var idx: int = S.resolution_index(presets, S.sanitize_resolution(_values.get("resolution", S.default_resolution())))
    var slider := SliderCtl.new()
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    slider.custom_minimum_size = Vector2(220, 34)
    hb.add_child(slider)
    var val_l := _mk_label("", 14, Color(0.92, 0.85, 0.74, 0.95), 2)
    val_l.custom_minimum_size = Vector2(150, 0)
    val_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    val_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    hb.add_child(val_l)
    slider.configure(0.0, float(maxi(0, presets.size() - 1)), 1.0, float(idx))
    slider.set_tick_count(maxi(1, presets.size()))
    slider.drag_started.connect(_on_res_drag_started)
    slider.value_changed.connect(func(v: float) -> void:
        var ps: Array = S.resolution_presets()
        var i: int = clampi(int(round(v)), 0, maxi(0, ps.size() - 1))
        _values["resolution"] = ps[i]
        _refresh_slider_label("resolution"))
    slider.drag_finished.connect(_on_res_drag_finished)
    _sliders["resolution"] = slider
    _slider_value_labels["resolution"] = val_l
    _refresh_slider_label("resolution")

## 分辨率 / 窗口模式确认层：「保持此分辨率？12s 后自动回退」+ 保持 / 回退。
func _build_res_confirm() -> void:
    _res_confirm_dim = ColorRect.new()
    _res_confirm_dim.color = Color(0, 0, 0, 0.35)
    _res_confirm_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
    _res_confirm_dim.mouse_filter = Control.MOUSE_FILTER_STOP
    _res_confirm_dim.visible = false
    _menu_root.add_child(_res_confirm_dim)
    _res_confirm_panel = PanelContainer.new()
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color(0.055, 0.062, 0.08, 0.97)
    sb.corner_radius_top_left = 14
    sb.corner_radius_top_right = 14
    sb.corner_radius_bottom_left = 14
    sb.corner_radius_bottom_right = 14
    sb.border_width_left = 1
    sb.border_width_top = 1
    sb.border_width_right = 1
    sb.border_width_bottom = 1
    sb.border_color = Color(1.0, 0.87, 0.70, 0.34)
    sb.content_margin_left = 24.0
    sb.content_margin_right = 24.0
    sb.content_margin_top = 18.0
    sb.content_margin_bottom = 18.0
    sb.shadow_color = Color(0, 0, 0, 0.5)
    sb.shadow_size = 22
    _res_confirm_panel.add_theme_stylebox_override("panel", sb)
    _res_confirm_panel.visible = false
    _menu_root.add_child(_res_confirm_panel)
    var vb := VBoxContainer.new()
    vb.add_theme_constant_override("separation", 12)
    _res_confirm_panel.add_child(vb)
    var head := _mk_label("显示设置确认", 17, CREAM, 4)
    head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    vb.add_child(head)
    _res_confirm_label = _mk_label("保持此分辨率？（12 秒后自动回退）", 14, Color(0.92, 0.84, 0.72, 0.96), 3)
    _res_confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    vb.add_child(_res_confirm_label)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 14)
    row.alignment = BoxContainer.ALIGNMENT_CENTER
    vb.add_child(row)
    var keep := _mk_button("保持", true)
    keep.custom_minimum_size = Vector2(140, 42)
    keep.add_theme_font_size_override("font_size", 16)
    keep.pressed.connect(_confirm_keep)
    row.add_child(keep)
    var revert := _mk_button("回退", false)
    revert.custom_minimum_size = Vector2(140, 42)
    revert.add_theme_font_size_override("font_size", 16)
    revert.pressed.connect(_confirm_revert)
    row.add_child(revert)

## 时区选择弹层：可搜索（城市 / IANA id），列表显示“城市 · IANA id · 当前 UTC 偏移”，
## 点击即保存并通知主循环，Esc 或“关闭”只收起弹层（不影响设置面板）。
func _build_timezone_picker() -> void:
    _tz_popup = PanelContainer.new()
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color(0.045, 0.052, 0.068, 0.97)
    sb.corner_radius_top_left = 16
    sb.corner_radius_top_right = 16
    sb.corner_radius_bottom_left = 16
    sb.corner_radius_bottom_right = 16
    sb.border_width_left = 1
    sb.border_width_top = 1
    sb.border_width_right = 1
    sb.border_width_bottom = 1
    sb.border_color = Color(1.0, 0.87, 0.70, 0.3)
    sb.content_margin_left = 26.0
    sb.content_margin_right = 26.0
    sb.content_margin_top = 20.0
    sb.content_margin_bottom = 20.0
    sb.shadow_color = Color(0, 0, 0, 0.5)
    sb.shadow_size = 26
    _tz_popup.add_theme_stylebox_override("panel", sb)
    _tz_popup.visible = false
    _menu_root.add_child(_tz_popup)
    var vb := VBoxContainer.new()
    vb.add_theme_constant_override("separation", 12)
    _tz_popup.add_child(vb)
    var head_row := HBoxContainer.new()
    head_row.add_theme_constant_override("separation", 12)
    vb.add_child(head_row)
    var head := _mk_label("时区 · TIMEZONE", 22, CREAM, 4)
    head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    head.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    head_row.add_child(head)
    var close_btn := _mk_button("关闭", false)
    close_btn.custom_minimum_size = Vector2(96, 38)
    close_btn.add_theme_font_size_override("font_size", 14)
    close_btn.pressed.connect(close_timezone_picker)
    head_row.add_child(close_btn)
    var hint := _mk_label("仅现实时间模式生效；选择后立即保存。搜索城市或时区名，Esc 关闭。", 11, Color(0.70, 0.64, 0.55, 0.92), 2)
    vb.add_child(hint)
    _tz_search = LineEdit.new()
    _tz_search.placeholder_text = "搜索城市或 IANA 时区，如 上海 / Tokyo / Europe"
    _tz_search.add_theme_font_override("font", _font)
    _tz_search.add_theme_font_size_override("font_size", 15)
    _tz_search.add_theme_color_override("font_color", CREAM)
    _tz_search.add_theme_color_override("font_placeholder_color", Color(0.62, 0.57, 0.50, 0.8))
    _tz_search.add_theme_color_override("caret_color", ACCENT)
    _tz_search.custom_minimum_size = Vector2(0, 40)
    _tz_search.text_changed.connect(_on_tz_search_changed)
    vb.add_child(_tz_search)
    _tz_scroll = ScrollContainer.new()
    _tz_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    _tz_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
    _tz_scroll.custom_minimum_size = Vector2(0, 300)
    _tz_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    vb.add_child(_tz_scroll)
    _tz_list = VBoxContainer.new()
    _tz_list.add_theme_constant_override("separation", 4)
    _tz_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _tz_scroll.add_child(_tz_list)
    # 第五阶段：按规则分组构建（常用 / 特殊），每规则最多 2 个代表城市。
    _populate_timezone_list(TimeSvc.now_unix())

## 重建分组列表：常用时区（无 DST / 整小时 / 3 年规则稳定）+ 特殊时区规则（DST / 非整时 / 法规变更）。
## 每次打开弹层均按“当前时刻”重建，保证 UTC 偏移与 DST 状态实时；代表之外的同规则时区隐藏，搜索时显示。
func _populate_timezone_list(now: float) -> void:
    if _tz_list == null:
        return
    var build_t0 := Time.get_ticks_usec()
    for child in _tz_list.get_children():
        _tz_list.remove_child(child)
        child.queue_free()
    _tz_buttons.clear()
    _tz_group_blocks.clear()
    _tz_section_headers.clear()
    _tz_default_visible.clear()
    _tz_last_now = now
    _tz_groups = TimeSvc.zone_groups(now)
    var sections := [
        ["normal", "常用时区 · 规则稳定 · 无夏令时 · 整小时偏移", DIM],
        ["special", "特殊时区规则 · 夏令时 / 非整时 / 法规变更 · 每组最多 2 个代表", ACCENT],
    ]
    for spec in sections:
        var kind := str(spec[0])
        var sec_lbl := _mk_label(str(spec[1]), 12, spec[2], 2)
        sec_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _tz_list.add_child(sec_lbl)
        _tz_section_headers[kind] = sec_lbl
        for g in _tz_groups:
            if str(g.get("kind", "")) != kind:
                continue
            _add_tz_group(g, now, kind)
    _tz_last_build_ms = float(Time.get_ticks_usec() - build_t0) / 1000.0
    _tz_last_refresh_ms = -1.0
    _update_tz_selection_highlight()

## 打开弹层：分组结构不变时只刷新组头 / 按钮文字（实时偏移与 DST），避免每次重建 134 个按钮造成卡顿。
func _sync_timezone_list(now: float) -> void:
    var groups := TimeSvc.zone_groups(now)
    if _tz_buttons.is_empty() or not _tz_structure_matches(groups):
        _populate_timezone_list(now)
        return
    var refresh_t0 := Time.get_ticks_usec()
    _tz_groups = groups
    _tz_last_now = now
    for i in _tz_group_blocks.size():
        var block: Dictionary = _tz_group_blocks[i]
        var g: Dictionary = groups[i]
        var header := block.get("header") as Label
        if header != null:
            header.text = str(g.get("title", ""))
        for item in block.get("buttons", []):
            var b := item as Button
            var zone := str(b.get_meta("zone", ""))
            b.text = TimeSvc.zone_option_label(zone, now)
            var tip := TimeSvc.zone_label(zone, now)
            if TimeSvc.dst_active(zone, now):
                tip += " · 夏令时"
            b.tooltip_text = tip
            b.set_meta("search_text", (zone + " " + TimeSvc.city_of(zone) + " " + TimeSvc.city_en_of(zone) + " " + b.text).to_lower())
    _tz_last_refresh_ms = float(Time.get_ticks_usec() - refresh_t0) / 1000.0
    _update_tz_selection_highlight()

## 分组结构（kind / rule_key / 代表集合）是否与当前已构建 UI 一致。
func _tz_structure_matches(groups: Array) -> bool:
    if groups.size() != _tz_group_blocks.size():
        return false
    for i in groups.size():
        var g: Dictionary = groups[i]
        var block: Dictionary = _tz_group_blocks[i]
        if str(g.get("kind", "")) != str(block.get("kind", "")):
            return false
        # rule_key 的转换秒相对窗口起点，now 微移几十秒即变；成员集合在此尺度稳定，用它判结构。
        var built: Dictionary = block.get("group", {})
        var cur_members: Array = g.get("members", [])
        var built_members: Array = built.get("members", [])
        if cur_members.size() != built_members.size():
            return false
        for k in cur_members.size():
            if str(cur_members[k]) != str(built_members[k]):
                return false
        var rep_ids: Array = block.get("rep_ids", [])
        var entries: Array = g.get("entries", [])
        if rep_ids.size() != entries.size():
            return false
        for j in entries.size():
            if str(rep_ids[j]) != str((entries[j] as Dictionary).get("id", "")):
                return false
    return true

## 一个规则组：组标题（偏移 / 特殊原因 / 时区数量）+ 全部成员按钮（代表可见，其余隐藏待搜索）。
func _add_tz_group(g: Dictionary, now: float, kind: String) -> void:
    var header_color := Color(0.72, 0.66, 0.57, 0.95) if kind == "normal" else Color(0.88, 0.76, 0.60, 0.95)
    var header := _mk_label(str(g.get("title", "")), 11, header_color, 2)
    header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _tz_list.add_child(header)
    var rep_ids: Array = []
    for e in g.get("entries", []):
        rep_ids.append(str(e.get("id", "")))
    var block := {
        "header": header,
        "buttons": [],
        "kind": kind,
        "group": g,
        "rep_ids": rep_ids,
    }
    var ordered: Array = rep_ids.duplicate()
    for m in g.get("members", []):
        if not ordered.has(str(m)):
            ordered.append(str(m))
    for zone in ordered:
        var zid := str(zone)
        var is_rep: bool = rep_ids.has(zid)
        var b := _make_tz_button(zid, now, kind, is_rep)
        _tz_list.add_child(b)
        _tz_buttons.append(b)
        (block["buttons"] as Array).append(b)
        if is_rep:
            _tz_default_visible.append(b)
    _tz_group_blocks.append(block)

## 单个时区选项：文字 = IANA 城市 + 实时 UTC 偏移 + DST 状态；tooltip 保留 IANA id 供设置行 / 测试复核。
func _make_tz_button(zone: String, now: float, kind: String, is_rep: bool) -> Button:
    var label := TimeSvc.zone_option_label(zone, now)
    var b := _mk_button(label, false)
    b.alignment = HORIZONTAL_ALIGNMENT_LEFT
    b.custom_minimum_size = Vector2(0, 34)
    b.add_theme_font_size_override("font_size", 13)
    b.set_meta("zone", zone)
    b.set_meta("rep", is_rep)
    b.set_meta("kind", kind)
    b.set_meta("search_text", (zone + " " + TimeSvc.city_of(zone) + " " + TimeSvc.city_en_of(zone) + " " + label).to_lower())
    var tip := TimeSvc.zone_label(zone, now)
    if TimeSvc.dst_active(zone, now):
        tip += " · 夏令时"
    b.tooltip_text = tip
    b.pressed.connect(func() -> void: _on_timezone_chosen(str(b.get_meta("zone", ""))))
    b.visible = is_rep
    return b

## 当前已保存时区用 ACCENT 高亮，与设置菜单同一状态源。
func _update_tz_selection_highlight() -> void:
    var current := TimeSvc.resolve_zone(str(_values.get("timezone", "")))
    for item in _tz_buttons:
        var b := item as Button
        var active: bool = str(b.get_meta("zone", "")) == current
        b.add_theme_color_override("font_color", ACCENT if active else CREAM)

func open_timezone_picker() -> void:
    if _tz_popup == null:
        return
    _tz_popup_open = true
    if _tz_search != null:
        _tz_search.text = ""
    # 打开时刷新分组（结构不变只更新偏移 / DST 文本，避免重复重建按钮）。
    _sync_timezone_list(TimeSvc.now_unix())
    _on_tz_search_changed("")
    _tz_popup.visible = true
    _tz_popup.modulate = Color(1, 1, 1, 0)
    var tw := create_tween()
    tw.tween_property(_tz_popup, "modulate:a", 1.0, 0.16)
    _layout()
    if _tz_search != null:
        _tz_search.grab_focus()
    if _tz_scroll != null:
        _tz_scroll.scroll_vertical = 0

func close_timezone_picker() -> void:
    if _tz_popup == null or not _tz_popup_open:
        return
    _tz_popup_open = false
    _tz_popup.visible = false
    if _tz_search != null and _tz_search.has_focus():
        _tz_search.release_focus()

func _on_tz_search_changed(text: String) -> void:
    var q := text.strip_edges().to_lower()
    var matched := {}
    for item in _tz_buttons:
        var b: Button = item
        var hit: bool
        if q.is_empty():
            hit = bool(b.get_meta("rep", false))
        else:
            hit = str(b.get_meta("search_text", "")).contains(q)
        b.visible = hit
    for block in _tz_group_blocks:
        var any_visible := false
        for btn in block.get("buttons", []):
            if (btn as Button).visible:
                any_visible = true
                break
        var header := block.get("header") as Label
        if header != null:
            header.visible = any_visible
        if any_visible:
            matched[str(block.get("kind", ""))] = true
    for kind in _tz_section_headers.keys():
        var sec := _tz_section_headers[kind] as Label
        if sec != null:
            sec.visible = matched.has(str(kind))
    _update_tz_selection_highlight()
    if q.is_empty() and _tz_scroll != null:
        _tz_scroll.scroll_vertical = 0

func _on_timezone_chosen(zone: String) -> void:
    if zone.is_empty():
        return
    _values["timezone"] = TimeSvc.resolve_zone(zone)
    S.save_settings(get_settings())
    _set_settings_visuals()
    _update_tz_selection_highlight()
    settings_changed.emit(get_settings())
    close_timezone_picker()

func _build_fade() -> void:
    _fade = ColorRect.new()
    _fade.color = Color(0.02, 0.02, 0.025, 1.0)
    _fade.set_anchors_preset(Control.PRESET_FULL_RECT)
    _fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_fade)
    var tw := create_tween()
    tw.tween_property(_fade, "modulate:a", 0.0, 1.2)
    tw.tween_callback(func() -> void: _fade.visible = false)

func open_settings() -> void:
    close_timezone_picker()
    _settings_open = true
    _settings_dim.visible = true
    _settings_panel.visible = true
    _settings_dim.modulate = Color(1, 1, 1, 0)
    _settings_panel.modulate = Color(1, 1, 1, 0)
    _settings_panel.scale = Vector2(0.96, 0.96)
    if _settings_scroll != null:
        _settings_scroll.scroll_vertical = 0
    var tw := create_tween().set_parallel(true)
    tw.tween_property(_settings_dim, "modulate:a", 1.0, 0.22)
    tw.tween_property(_settings_panel, "modulate:a", 1.0, 0.24)
    tw.tween_property(_settings_panel, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func close_settings() -> void:
    if not _settings_open:
        return
    _settings_open = false
    close_timezone_picker()
    var tw := create_tween().set_parallel(true)
    tw.tween_property(_settings_dim, "modulate:a", 0.0, 0.18)
    tw.tween_property(_settings_panel, "modulate:a", 0.0, 0.16)
    tw.tween_callback(func() -> void:
        _settings_dim.visible = false
        _settings_panel.visible = false).set_delay(0.2)

func close_settings_instant() -> void:
    close_timezone_picker()
    _settings_open = false
    _settings_dim.visible = false
    _settings_panel.visible = false

# ============================================================
# ESC 菜单动画：从屏幕外左 / 右 / 下错峰滑入，关闭时反向滑出。
# 单一 Tween 驱动全部控件，反复开关 / 半途反转都不叠加、不跳变。
# ============================================================
func _capture_items_home() -> void:
    _items_home.clear()
    for item in _items:
        var ctl: Control = item
        _items_home.append(ctl.position)

func _build_item_dirs() -> void:
    _items_dir.clear()
    var vp: Vector2 = get_viewport().get_visible_rect().size
    if vp.x < 10.0 or vp.y < 10.0:
        vp = Vector2(1280.0, 720.0)
    for i in _items.size():
        var ctl: Control = _items[i]
        match i % 3:
            0:
                _items_dir.append(Vector2(-(vp.x + ctl.size.x * 2.0), 0.0))
            1:
                _items_dir.append(Vector2(vp.x + ctl.size.x * 2.0, 0.0))
            _:
                _items_dir.append(Vector2(0.0, vp.y + ctl.size.y * 2.0))

func _ease_out_back(p: float) -> float:
    var c1 := 1.05
    var c3 := c1 + 1.0
    var q := p - 1.0
    return 1.0 + c3 * q * q * q + c1 * q * q

func _apply_anim(t: float) -> void:
    _anim_t = t
    for i in _items.size():
        if i >= _items_home.size() or i >= _items_dir.size():
            continue
        var ctl: Control = _items[i]
        var delay: float = float(i) * ANIM_STAGGER
        var p: float = clampf((t - delay) / ANIM_ITEM_TIME, 0.0, 1.0)
        var e: float = _ease_out_back(p)
        var home: Vector2 = _items_home[i]
        var dir: Vector2 = _items_dir[i]
        ctl.position = home + dir * (1.0 - e)
        # 入场/退场只做平面滑入滑出：rotation / scale 必须复位。
        # 否则标题菜单螺旋飞出（_fly_out）写入的旋转 / 缩放会残留到 ESC 菜单。
        ctl.rotation = 0.0
        ctl.scale = Vector2.ONE
        ctl.modulate.a = clampf(p * 1.6, 0.0, 1.0)

func _kill_anim() -> void:
    if _anim_tween != null and _anim_tween.is_valid():
        _anim_tween.kill()
    _anim_tween = null

## 终止标题菜单螺旋飞出的全部 Tween（打开 ESC 菜单前必须清残留）。
func _kill_fly_tweens() -> void:
    for tw in _fly_tweens:
        if tw != null and tw.is_valid():
            tw.kill()
    _fly_tweens.clear()

## 复位每个菜单项的变换：rotation=0、scale=1（pivot 由 _layout 统一设置）。
func _reset_items_transform() -> void:
    for item in _items:
        var ctl: Control = item
        ctl.rotation = 0.0
        ctl.scale = Vector2.ONE

func _set_menu_interactive(on: bool) -> void:
    for item in _menu_buttons:
        var b := item as Button
        if b != null:
            b.disabled = not on

func _start_enter_anim(from_t: float = 0.0) -> void:
    _kill_anim()
    _kill_fly_tweens()
    _reset_items_transform()
    # 标题菜单螺旋飞出（_fly_out）收尾会把每个 item 置 visible=false；
    # ESC 菜单入场必须重新显示，否则整个进入动画期间控件不可见、到结束才突然出现。
    for item in _items:
        var item_ctl: Control = item
        item_ctl.visible = true
    if _items_home.size() != _items.size():
        _capture_items_home()
    _build_item_dirs()
    _anim_total = float(maxi(1, _items.size() - 1)) * ANIM_STAGGER + ANIM_ITEM_TIME
    _anim_state = ANIM_ENTER
    _closing = false
    _set_menu_interactive(false)
    var start: float = clampf(from_t, 0.0, _anim_total)
    var dur: float = maxf(0.12, _anim_total - start)
    _anim_tween = create_tween()
    _anim_tween.tween_method(_apply_anim, start, _anim_total, dur).set_trans(Tween.TRANS_LINEAR)
    _anim_tween.tween_callback(_on_enter_done)

func _on_enter_done() -> void:
    for i in _items.size():
        var ctl: Control = _items[i]
        if i < _items_home.size():
            ctl.position = _items_home[i]
        ctl.rotation = 0.0
        ctl.scale = Vector2.ONE
        ctl.visible = true
        ctl.modulate = Color(1, 1, 1, 1)
    _anim_state = ANIM_NONE
    _anim_tween = null
    _anim_t = _anim_total
    _set_menu_interactive(true)

func _start_exit_anim(on_done: Callable, from_t: float = -1.0) -> void:
    var start: float = _anim_t if from_t < 0.0 else from_t
    _kill_anim()
    if _items_home.size() != _items.size() or _items_dir.size() != _items.size():
        _capture_items_home()
        _build_item_dirs()
    if _anim_total <= 0.0:
        _anim_total = float(maxi(1, _items.size() - 1)) * ANIM_STAGGER + ANIM_ITEM_TIME
    if _anim_state == ANIM_NONE and start <= 0.001:
        start = _anim_total
    start = clampf(start, 0.0, _anim_total)
    _anim_state = ANIM_EXIT
    _closing = true
    _set_menu_interactive(false)
    var dur: float = maxf(0.14, start * 0.85)
    _anim_tween = create_tween()
    _anim_tween.tween_method(_apply_anim, start, 0.0, dur).set_trans(Tween.TRANS_LINEAR)
    _anim_tween.tween_callback(func() -> void: _on_exit_done(on_done))

func _on_exit_done(on_done: Callable) -> void:
    _menu_root.visible = false
    menu_visible = false
    visible = false
    _closing = false
    _anim_state = ANIM_NONE
    _anim_tween = null
    _anim_t = 0.0
    for item in _items:
        var ctl: Control = item
        ctl.rotation = 0.0
        ctl.scale = Vector2.ONE
        ctl.modulate = Color(1, 1, 1, 1)
    if on_done.is_valid():
        on_done.call()

## 动画中再次 ESC：入场 → 反向退出（完全关闭后通知主循环恢复游玩）；退场 → 反向回到打开。
func _reverse_anim() -> void:
    if _anim_state == ANIM_ENTER:
        _start_exit_anim(Callable(self, "_emit_resume_after_cancel"))
    elif _anim_state == ANIM_EXIT:
        _start_enter_anim(_anim_t)

func _emit_resume_after_cancel() -> void:
    start_pressed.emit(_returning)

## 供测试/自动化读取当前动画状态（0 空闲 / 1 入场 / 2 退场）。
func get_anim_state() -> int:
    return _anim_state

func is_animating() -> bool:
    return _anim_state != ANIM_NONE

func open(returning: bool = false) -> void:
    _returning = returning
    _closing = false
    visible = true
    _menu_root.visible = true
    menu_visible = true
    _start_btn.text = "继续观景" if returning else "开始游戏"
    _cancel_res_confirm()
    close_settings_instant()
    _layout()
    _capture_items_home()
    # 打开菜单前清掉标题菜单螺旋飞出留下的 tween / rotation / scale 残留。
    _kill_fly_tweens()
    _reset_items_transform()
    if _returning:
        _anim_t = 0.0
        _start_enter_anim(0.0)
    else:
        _kill_anim()
        _anim_state = ANIM_NONE
        _anim_t = 0.0
        _set_menu_interactive(true)
        for i in range(_items.size()):
            var ctl: Control = _items[i]
            ctl.visible = true
            ctl.modulate = Color(1, 1, 1, 0)
            ctl.rotation = 0.0
            ctl.scale = Vector2.ONE
            var tw := create_tween().set_parallel(true)
            tw.tween_property(ctl, "modulate:a", 1.0, 0.5).set_delay(0.05 + float(i) * 0.05)
    _set_bar(_bar_h, true)

func get_returning() -> bool:
    return _returning

func close(on_done: Callable = Callable()) -> void:
    if _returning:
        if _anim_state == ANIM_EXIT:
            return
        if not menu_visible:
            _closing = false
            if on_done.is_valid():
                on_done.call()
            return
        _cancel_res_confirm()
        close_settings_instant()
        _start_exit_anim(on_done)
        return
    if _closing:
        return
    _closing = true
    _kill_anim()
    _kill_fly_tweens()
    close_settings_instant()
    var center: Vector2 = _menu_root.size * 0.5
    var total: float = 0.0
    # 径向 + 切向的螺旋飞出：控件沿自身方位角加速离场，同时带一点圆周旋转与错峰。
    for i in range(_items.size()):
        var ctl: Control = _items[i]
        var off: Vector2 = ctl.position + ctl.size * 0.5 - center
        if off.length() < 10.0:
            off = Vector2(cos(float(i) * 1.7), sin(float(i) * 1.7)) * 40.0
        var r0: float = maxf(12.0, off.length())
        var a0: float = off.angle()
        var spin: float = 0.62 if i % 2 == 0 else -0.62
        var delay: float = float(i) * 0.035
        _fly_out(ctl, center, r0, a0, spin, delay)
        total = maxf(total, delay + 1.18)
    var tw2 := create_tween().set_parallel(true)
    tw2.tween_property(_letter_top, "offset_bottom", 0.0, 0.9).set_delay(0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
    tw2.tween_property(_letter_bottom, "offset_top", 0.0, 0.9).set_delay(0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
    await get_tree().create_timer(total + 0.1).timeout
    _menu_root.visible = false
    menu_visible = false
    visible = false
    _closing = false
    if on_done.is_valid():
        on_done.call()

## 单个控件的螺旋飞出：半径加速拉开 + 角度扫过 spin + 缩放旋转淡出。
func _fly_out(ctl: Control, center: Vector2, r0: float, a0: float, spin: float, delay: float) -> void:
    var c := ctl
    var tw: Tween = create_tween()
    tw.tween_method(func(t: float) -> void:
        var p: float = t * t * t
        var rr: float = lerpf(r0, 1780.0, p)
        var aa: float = a0 + spin * p
        c.position = center + Vector2(cos(aa), sin(aa)) * rr - c.size * 0.5
        c.rotation = spin * p * 1.1
        c.modulate.a = clampf(1.0 - maxf(0.0, p - 0.10) * 1.7, 0.0, 1.0)
        c.scale = Vector2.ONE * (1.0 - 0.10 * p)
    , 0.0, 1.0, 1.15).set_delay(delay)
    tw.tween_callback(func() -> void:
        # 收尾必须还原旋转 / 缩放：下一次 open() 的入场动画不能继承螺旋姿态。
        c.rotation = 0.0
        c.scale = Vector2.ONE
        c.visible = false
        _fly_tweens.erase(tw))
    _fly_tweens.append(tw)

## 无动画直接结束标题界面（自动截图流程使用）。
func instant_finish() -> void:
    _closing = false
    _cancel_res_confirm()
    close_settings_instant()
    _kill_anim()
    _kill_fly_tweens()
    _reset_items_transform()
    _anim_state = ANIM_NONE
    _set_bar(0.0, false)
    if _fade != null:
        _fade.visible = false
    _menu_root.visible = false
    menu_visible = false
    visible = false

var menu_visible: bool = false

func _on_start_pressed() -> void:
    if _closing or _anim_state == ANIM_ENTER:
        return
    start_pressed.emit(_returning)

func _on_settings_pressed() -> void:
    if _closing or _anim_state != ANIM_NONE:
        return
    open_settings()

func _on_quit_pressed() -> void:
    if _closing or _anim_state == ANIM_ENTER:
        return
    quit_pressed.emit()

func _input(event: InputEvent) -> void:
    if not (event is InputEventKey):
        return
    var ke := event as InputEventKey
    if not ke.pressed or ke.echo or ke.keycode != KEY_ESCAPE:
        return
    # Esc 先关确认层 / 时区弹层，再关设置面板；随后交给 main 处理菜单开关。
    if _res_confirm_open:
        _confirm_revert()
        get_viewport().set_input_as_handled()
        return
    if _tz_popup_open:
        close_timezone_picker()
        get_viewport().set_input_as_handled()
        return
    if _settings_open:
        close_settings()
        get_viewport().set_input_as_handled()
        return
    # ESC 菜单动画中：反向播放（不叠加 Tween、不跳变）。
    if _returning and menu_visible and _anim_state != ANIM_NONE:
        _reverse_anim()
        get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
    if not _res_confirm_open:
        return
    _res_confirm_t = maxf(0.0, _res_confirm_t - delta)
    var what := "分辨率" if _res_kind == "resolution" else "窗口模式"
    _res_confirm_label.text = "保持此%s？（%d 秒后自动回退）" % [what, int(ceil(_res_confirm_t))]
    if _res_confirm_t <= 0.0:
        _confirm_revert()

func _on_slider_changed(key: String, value: float) -> void:
    match key:
        "day_length":
            var presets: Array = S.DAY_LENGTH_PRESETS
            var idx: int = clampi(int(round(value)), 0, presets.size() - 1)
            _values["day_length"] = float(presets[idx])
        "sensitivity":
            _values["sensitivity"] = clampf(value, SENS_MIN, SENS_MAX)
        "quality":
            if not (_values["quality_overrides"] as Dictionary).is_empty():
                # 重选预设档位 = 放弃一切高级覆盖，回到预设参数。
                _values["quality_overrides"] = {}
                _refresh_override_buttons()
            _values["quality"] = clampi(int(round(value)), 0, S.QUALITY_COUNT - 1)
        "volume":
            _values["volume_master"] = clampf(value, 0.0, 1.0)
        _:
            if S.VOLUME_KEYS.has(key):
                _values[key] = clampf(value, 0.0, 1.0)
    _refresh_slider_label(key)
    settings_changed.emit(get_settings())

func _on_setting_pressed(key: String) -> void:
    if key == "timezone":
        open_timezone_picker()
        return
    if key == "time_source":
        _values["time_source"] = "real" if str(_values.get("time_source", "sim")) == "sim" else "sim"
        # 时间来源影响 HUD 显示与是否启用现实时间，选择即写盘。
        _set_settings_visuals()
        S.save_settings(get_settings())
        settings_changed.emit(get_settings())
        _layout()
        return
    if key == "auto":
        _values["auto"] = not bool(_values["auto"])
    elif key == "window_mode":
        _cycle_window_mode()
        return
    _set_settings_visuals()
    settings_changed.emit(get_settings())

## 窗口模式三态：窗口化 → 全屏 → 无边框窗口；危险切换同样进入确认层。
func _cycle_window_mode() -> void:
    var prev: Dictionary = get_settings()
    var modes: Array = S.WINDOW_MODES
    var cur: String = S.sanitize_window_mode(str(_values.get("window_mode", "windowed")))
    var idx: int = maxi(0, modes.find(cur))
    var next: String = str(modes[(idx + 1) % modes.size()])
    _values["window_mode"] = next
    _set_settings_visuals()
    _apply_display_change("window_mode", prev)

func _is_fullscreen() -> bool:
    return S.sanitize_window_mode(str(_values.get("window_mode", "windowed"))) == "fullscreen"

func _on_res_drag_started() -> void:
    _res_prev = get_settings()

func _on_res_drag_finished() -> void:
    if _res_prev.is_empty():
        _res_prev = get_settings()
    var prev: Dictionary = _res_prev.duplicate(true)
    _res_prev = {}
    var new_res: Vector2i = S.sanitize_resolution(_values.get("resolution", S.default_resolution()))
    var old_res: Vector2i = S.sanitize_resolution(prev.get("resolution", new_res))
    if new_res == old_res:
        _set_settings_visuals()
        return
    _values["resolution"] = new_res
    _apply_display_change("resolution", prev)

func _apply_display_change(kind: String, prev: Dictionary) -> void:
    _res_kind = kind
    _res_prev = prev.duplicate(true)
    _res_confirm_t = CONFIRM_SECONDS
    _res_confirm_open = true
    _res_confirm_dim.visible = true
    _res_confirm_panel.visible = true
    var what := "分辨率" if kind == "resolution" else "窗口模式"
    _res_confirm_label.text = "保持此%s？（%d 秒后自动回退）" % [what, int(CONFIRM_SECONDS)]
    _layout()
    # 立即应用新设置；用户点「回退」或 12s 超时会 emit 旧 settings。
    settings_changed.emit(get_settings())

func _confirm_keep() -> void:
    _res_confirm_open = false
    _res_confirm_dim.visible = false
    _res_confirm_panel.visible = false
    _res_prev = {}
    _res_kind = ""

func _confirm_revert() -> void:
    if not _res_confirm_open and _res_prev.is_empty():
        return
    var old: Dictionary = _res_prev.duplicate(true)
    _res_confirm_open = false
    _res_confirm_dim.visible = false
    _res_confirm_panel.visible = false
    _res_prev = {}
    _res_kind = ""
    if old.is_empty():
        return
    set_settings(old)
    _set_settings_visuals()
    settings_changed.emit(old)

## 取消未确认的显示变更：回退到变更前（open/close 时调用，保证状态一致）。
func _cancel_res_confirm() -> void:
    if _res_confirm_open or not _res_prev.is_empty():
        _confirm_revert()
    _res_confirm_open = false
    _res_confirm_dim.visible = false
    _res_confirm_panel.visible = false
    _res_prev = {}
    _res_kind = ""

## 三态高级覆盖：跟随预设 → 与预设相反 → 与预设相同 → 跟随预设。
func _cycle_override(key: String) -> void:
    var ov: Dictionary = (_values["quality_overrides"] as Dictionary).duplicate(true)
    var preset: Dictionary = S.quality_preset(int(_values["quality"]))
    var preset_v: bool = bool(preset.get(key, true))
    if not ov.has(key):
        ov[key] = not preset_v
    elif bool(ov[key]) == preset_v:
        ov.erase(key)
    else:
        ov[key] = preset_v
    _values["quality_overrides"] = ov
    _refresh_override_buttons()
    _refresh_slider_label("quality")
    settings_changed.emit(get_settings())

func _refresh_override_buttons() -> void:
    var ov: Dictionary = _values.get("quality_overrides", {})
    var eff: Dictionary = S.quality_effective(int(_values["quality"]), ov)
    for spec in OVERRIDE_ROWS:
        var key: String = str(spec["key"])
        if not _quality_override_buttons.has(key):
            continue
        var b: Button = _quality_override_buttons[key]
        var v: bool = bool(eff.get(key, true))
        if ov.has(key):
            b.text = "开" if v else "关"
            b.tooltip_text = "已覆盖预设：%s（再次点击可切回跟随预设）" % ("开" if v else "关")
        else:
            b.text = "跟随预设 · %s" % ("开" if v else "关")
            b.tooltip_text = "跟随当前画质档位：%s" % ("开" if v else "关")

func _refresh_slider_label(key: String) -> void:
    if not _slider_value_labels.has(key):
        return
    var l: Label = _slider_value_labels[key]
    match key:
        "day_length":
            l.text = S.day_length_label(float(_values["day_length"]))
        "sensitivity":
            l.text = "%.2f×" % float(_values["sensitivity"])
        "quality":
            l.text = S.quality_summary(_values)
        "resolution":
            l.text = S.resolution_label(S.sanitize_resolution(_values["resolution"]))
        "volume":
            l.text = "%d%%" % int(round(float(_values.get("volume_master", 0.0)) * 100.0))
        _:
            if S.VOLUME_KEYS.has(key):
                l.text = "%d%%" % int(round(float(_values.get(key, 0.0)) * 100.0))

func get_settings() -> Dictionary:
    var out := {
        "day_length": S.sanitize_day_length(float(_values["day_length"])),
        "sensitivity": clampf(float(_values["sensitivity"]), SENS_MIN, SENS_MAX),
        "auto_orbit": bool(_values["auto"]),
        "quality": clampi(int(_values["quality"]), 0, S.QUALITY_COUNT - 1),
        "quality_overrides": (_values.get("quality_overrides", {}) as Dictionary).duplicate(true),
        "window_mode": S.sanitize_window_mode(str(_values.get("window_mode", "windowed"))),
        "resolution": S.sanitize_resolution(_values["resolution"]),
        "time_source": TimeSvc.sanitize_source(str(_values.get("time_source", "sim"))),
        "timezone": TimeSvc.resolve_zone(str(_values.get("timezone", ""))),
    }
    for key in S.VOLUME_KEYS:
        out[key] = clampf(float(_values.get(key, S.audio_default(key))), 0.0, 1.0)
    # fullscreen 为派生值（旧 main / 旧测试仍读它）；volume 为旧单音量别名。
    out["fullscreen"] = str(out["window_mode"]) == "fullscreen"
    out["volume"] = out["volume_master"]
    return out

func set_settings(s: Dictionary) -> void:
    if s.has("day_length"):
        _values["day_length"] = S.sanitize_day_length(float(s["day_length"]))
    if s.has("sensitivity"):
        _values["sensitivity"] = clampf(float(s["sensitivity"]), SENS_MIN, SENS_MAX)
    if s.has("auto_orbit"):
        _values["auto"] = bool(s["auto_orbit"])
    if s.has("quality"):
        _values["quality"] = clampi(int(s["quality"]), 0, S.QUALITY_COUNT - 1)
    if s.has("quality_overrides") and s["quality_overrides"] is Dictionary:
        var ov: Dictionary = (s["quality_overrides"] as Dictionary).duplicate(true)
        # main 侧 canonical 键是 posts_ao；界面 / 设置统一用 post_ao，这里归一到界面键。
        if ov.has("posts_ao") and not ov.has("post_ao"):
            ov["post_ao"] = ov["posts_ao"]
            ov.erase("posts_ao")
        _values["quality_overrides"] = ov
    if s.has("window_mode"):
        _values["window_mode"] = S.sanitize_window_mode(str(s["window_mode"]), bool(s.get("fullscreen", false)))
    elif s.has("fullscreen"):
        _values["window_mode"] = "fullscreen" if bool(s["fullscreen"]) else "windowed"
    if s.has("resolution"):
        _values["resolution"] = S.sanitize_resolution(s["resolution"])
    if s.has("time_source"):
        _values["time_source"] = TimeSvc.sanitize_source(str(s["time_source"]))
    if s.has("timezone"):
        _values["timezone"] = TimeSvc.resolve_zone(str(s["timezone"]))
    if s.has("volume"):
        _values["volume_master"] = clampf(float(s["volume"]), 0.0, 1.0)
    for key in S.VOLUME_KEYS:
        if s.has(key):
            _values[key] = clampf(float(s[key]), 0.0, 1.0)
    _set_settings_visuals()

func _set_settings_visuals() -> void:
    if _setting_buttons.is_empty() and _sliders.is_empty():
        return
    if _values.get("quality_overrides") == null or not (_values["quality_overrides"] is Dictionary):
        _values["quality_overrides"] = {}
    var is_real: bool = str(_values.get("time_source", "sim")) == "real"
    # 时间流速：滑条 = 十档索引
    if _sliders.has("day_length"):
        var idx: int = S.day_length_index(float(_values["day_length"]))
        (_sliders["day_length"] as Control).call("set_value", float(idx), false)
        _refresh_slider_label("day_length")
    if _sliders.has("sensitivity"):
        (_sliders["sensitivity"] as Control).call("set_value", float(_values["sensitivity"]), false)
        _refresh_slider_label("sensitivity")
    if _sliders.has("quality"):
        (_sliders["quality"] as Control).call("set_value", float(int(_values["quality"])), false)
        _refresh_slider_label("quality")
    for key in S.VOLUME_KEYS:
        if _sliders.has(key):
            (_sliders[key] as Control).call("set_value", float(_values.get(key, S.audio_default(key))), false)
            _refresh_slider_label(key)
    if _sliders.has("volume"):
        _refresh_slider_label("volume")
    if _sliders.has("resolution"):
        var presets: Array = S.resolution_presets()
        var ridx: int = S.resolution_index(presets, S.sanitize_resolution(_values["resolution"]))
        (_sliders["resolution"] as Control).call("set_value", float(ridx), false)
        (_sliders["resolution"] as Control).call("set_tick_count", maxi(1, presets.size()))
        _refresh_slider_label("resolution")
    # 全屏模式分辨率由系统决定：滑条禁用并说明原因。
    var fs: bool = _is_fullscreen()
    if _sliders.has("resolution"):
        var rs := _sliders["resolution"] as Control
        rs.mouse_filter = Control.MOUSE_FILTER_IGNORE if fs else Control.MOUSE_FILTER_STOP
        rs.modulate = Color(1, 1, 1, 0.45) if fs else Color(1, 1, 1, 1)
        rs.tooltip_text = "全屏模式下来分辨率由显示器决定；切回窗口化后可调" if fs else ""
    if _setting_buttons.has("auto"):
        _setting_buttons["auto"].text = "开" if bool(_values["auto"]) else "关"
    if _setting_buttons.has("window_mode"):
        var mode: String = S.sanitize_window_mode(str(_values.get("window_mode", "windowed")))
        _setting_buttons["window_mode"].text = str(WINDOW_MODE_LABELS.get(mode, mode))
        var tips := {
            "windowed": "窗口化：可拖动窗口，分辨率可自由选择",
            "fullscreen": "全屏：独占显示器，分辨率由显示器决定",
            "borderless": "无边框窗口：铺满屏幕但保留窗口渲染，切换后需确认",
        }
        _setting_buttons["window_mode"].tooltip_text = str(tips.get(mode, ""))
    _refresh_override_buttons()
    # 时间来源：现实时间下显示时区行、禁用时间流速滑条。
    if _setting_buttons.has("time_source"):
        var source: String = TimeSvc.sanitize_source(str(_values.get("time_source", "sim")))
        _values["time_source"] = source
        _setting_buttons["time_source"].text = TimeSvc.source_label(source)
    if _setting_buttons.has("timezone"):
        var zone: String = TimeSvc.resolve_zone(str(_values.get("timezone", "")))
        _values["timezone"] = zone
        _setting_buttons["timezone"].text = "%s · %s" % [TimeSvc.city_of(zone), zone]
        _setting_buttons["timezone"].tooltip_text = TimeSvc.zone_label(zone)
    if _tz_row != null:
        _tz_row.visible = is_real
    if _sliders.has("day_length"):
        var dl := _sliders["day_length"] as Control
        dl.mouse_filter = Control.MOUSE_FILTER_IGNORE if is_real else Control.MOUSE_FILTER_STOP
        dl.modulate = Color(1, 1, 1, 0.45) if is_real else Color(1, 1, 1, 1)
        dl.tooltip_text = "现实时间模式下每游戏日固定跟随真实 24 小时；切回模拟时间后可调" if is_real else ""
    if _daylen_note != null:
        _daylen_note.visible = true

func _layout() -> void:
    var vp: Vector2 = get_viewport().get_visible_rect().size
    if vp.x < 10.0 or vp.y < 10.0:
        return
    _bar_h = maxf(0.0, (vp.y - vp.x / RATIO) * 0.5)
    _letter_top.offset_left = 0.0
    _letter_top.offset_right = 0.0
    _letter_top.offset_top = 0.0
    _letter_top.offset_bottom = _bar_h
    _letter_bottom.offset_left = 0.0
    _letter_bottom.offset_right = 0.0
    _letter_bottom.offset_top = -_bar_h
    _letter_bottom.offset_bottom = 0.0
    var c: Vector2 = vp * 0.5
    var side: float = minf(920.0, vp.x - 24.0)
    var btn_w: float = minf(340.0, vp.x - 40.0)
    _place(_title, Vector2(c.x - side * 0.5, c.y - 246.0), Vector2(side, 100.0))
    _place(_subtitle, Vector2(c.x - side * 0.5, c.y - 286.0), Vector2(side, 30.0))
    _place(_rule, Vector2(c.x - 60.0, c.y - 100.0), Vector2(120.0, 2.0))
    _place(_start_btn, Vector2(c.x - btn_w * 0.5, c.y - 62.0), Vector2(btn_w, 60.0))
    _place(_settings_btn, Vector2(c.x - btn_w * 0.5, c.y + 14.0), Vector2(btn_w, 52.0))
    _place(_quit_btn, Vector2(c.x - btn_w * 0.5, c.y + 82.0), Vector2(btn_w, 52.0))
    _place(_hint, Vector2(c.x - side * 0.5, c.y + 168.0), Vector2(side, 26.0))
    _place(_version, Vector2(34.0, vp.y - _bar_h - 30.0), Vector2(700.0, 20.0))
    # 设置面板：高度跟随内容；屏幕矮时内部滚动（720p 下返回键可滚动到达）。
    var psize := Vector2(660.0, 548.0)
    if _settings_vb != null:
        var content_h: float = _settings_vb.get_combined_minimum_size().y + 52.0
        psize.y = clampf(content_h, 360.0, maxf(360.0, vp.y - 24.0))
        psize.x = clampf(660.0, 320.0, maxf(320.0, vp.x - 32.0))
    _settings_panel.position = c - psize * 0.5
    _settings_panel.size = psize
    if _res_confirm_panel != null:
        var csize := Vector2(minf(480.0, vp.x - 40.0), 168.0)
        _res_confirm_panel.position = c - csize * 0.5
        _res_confirm_panel.size = csize
    if _tz_popup != null:
        var tsize := Vector2(clampf(620.0, 320.0, maxf(320.0, vp.x - 32.0)), clampf(vp.y - 40.0, 300.0, 640.0))
        _tz_popup.position = c - tsize * 0.5
        _tz_popup.size = tsize
    for item in _items:
        var ctl: Control = item
        ctl.pivot_offset = ctl.size * 0.5
    if _anim_state == ANIM_NONE:
        var home: Array = []
        for item in _items:
            var ctl: Control = item
            home.append(ctl.position)
        if home.size() == _items.size():
            _items_home = home

func _place(ctl: Control, pos: Vector2, size: Vector2) -> void:
    ctl.position = pos
    ctl.size = size

func _set_bar(h: float, animate: bool) -> void:
    if _bar_tween != null and _bar_tween.is_valid():
        _bar_tween.kill()
    _bar_tween = null
    if animate:
        _bar_tween = create_tween().set_parallel(true)
        _bar_tween.tween_property(_letter_top, "offset_bottom", h, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
        _bar_tween.tween_property(_letter_bottom, "offset_top", -h, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
    else:
        _letter_top.offset_bottom = h
        _letter_bottom.offset_top = -h
