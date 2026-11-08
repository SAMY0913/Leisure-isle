extends SceneTree
## P9 / P5 —— 背包探针：左下角入口 + B 键 + 只读全岛共享库存 + 一键整理。
##
## 运行方式：
##   1) headless 全量断言（默认）：
##      ENG --headless --path GAME --script res://tools/probe_p9_backpack.gd -- --out=D:/休闲小岛幻境/开发产物/P9/P5/r2_headless
##   2) 真实窗口运行 + 截图（需 GPU）：
##      ENG --path GAME --script res://tools/probe_p9_backpack.gd -- --p5shots --out=D:/休闲小岛幻境/开发产物/P9/P5/r2_window
##
## 纪律：
## - 只读正式共享库存与农田数据；UI 只用 HUD 公开开关、真实 Button.pressed 与 Input.parse_input_event 驱动。
## - 不写回库存、不暂停世界、不改时间源；不使用 --shots（main 内置截图流程会改时间/天气/相机）。
## - headless 断言与真实窗口断言用不同前缀（h.* / win.*），报告里可区分两类证据。

const CROPS := preload("res://scripts/isle_crops.gd")
const FISH := preload("res://scripts/isle_fish.gd")

const DEFAULT_OUT := "D:/休闲小岛幻境/开发产物/P9/P5"
const BASE_Y := 2026
const BASE_M := 3
const BASE_D := 20
const SEASON := "spring"
const FORBIDDEN_BAG_WORDS := ["容量", "负重", "上限", "格位", "已满", "背包格"]
## P7-FINALIZE：说明性小字已按用户要求删除；探针断言面板文本中不再出现这些说明。
## 空状态提示（"背包是空的"/"此分类暂无物品"）是唯一保留的必要状态文案。
const BAG_EXPLANATORY_WORDS := ["显示顺序", "共享库存", "B 键", "只显示已获得", "分类叠加", "已整理"]

var out_dir := DEFAULT_OUT
var do_shots := false

var _pass := 0
var _fail := 0
var _lines: Array = []
var _fail_names: Array = []
var _main: Node = null
var _hud: Object = null
var _inv: Object = null
var _farm: Object = null
var _shots_fail := 0
var _seed_ids: Array = []
var _produce_ids: Array = []
var _canonical_order: Array = []
var _default_order: Array = []
var _inv_baseline: Dictionary = {}


func _initialize() -> void:
    _parse_args()
    DirAccess.make_dir_recursive_absolute(out_dir)
    _run.call_deferred()


func _parse_args() -> void:
    for a in OS.get_cmdline_user_args():
        var s := String(a)
        if s.begins_with("--out="):
            out_dir = s.substr(6).strip_edges().trim_suffix("/").trim_suffix("\\")
        elif s == "--p5shots":
            do_shots = true
    if out_dir == "":
        out_dir = DEFAULT_OUT


func _run() -> void:
    var banner := "[P5BAG] out=%s headless=%s godot=%s" % [
        out_dir, str(DisplayServer.get_name() == "headless"),
        String(Engine.get_version_info().get("string", ""))]
    print(banner)
    _lines.append(banner)
    await _boot()
    if _main == null:
        print("[RESULT] FAIL")
        quit(1)
        return
    if do_shots:
        await _window_run()
    else:
        await _layout_checks()
        await _entry_checks()
        await _items_checks()
        await _filter_checks()
        await _sort_checks()
        await _readonly_checks()
        await _sync_checks()
    _write_report()
    var summary := "[SUMMARY] checks=%d fail=%d" % [_pass + _fail, _fail]
    print(summary)
    _lines.append(summary)
    print("[RESULT] ", "PASS" if _fail == 0 else "FAIL")
    _lines.append("[RESULT] " + ("PASS" if _fail == 0 else "FAIL"))
    quit(0 if _fail == 0 else 1)


# =========================================================== 基础设施 =========
func _section(title: String) -> void:
    print("")
    print("== ", title, " ==")
    _lines.append("")
    _lines.append("== " + title + " ==")


func _check(name: String, ok: bool, expected: String, actual: String) -> void:
    if ok:
        _pass += 1
    else:
        _fail += 1
        _fail_names.append(name)
    print("[CHECK] %s | expected=%s actual=%s | %s" % [name, expected, actual, "PASS" if ok else "FAIL"])
    _lines.append("[CHECK] %s | expected=%s actual=%s | %s" % [name, expected, actual, "PASS" if ok else "FAIL"])


func _check_eq(name: String, expected: Variant, actual: Variant) -> void:
    _check(name, expected == actual, str(expected), str(actual))


func _write_report() -> void:
    var log_path := out_dir + "/probe_p9_backpack.log"
    var fa := FileAccess.open(log_path, FileAccess.WRITE)
    if fa != null:
        fa.store_string("\n".join(_lines) + "\n")
        fa.close()
        print("[P5BAG] log=", log_path)
    var data := {
        "checks": _pass + _fail,
        "fail": _fail,
        "fail_names": _fail_names,
        "headless": DisplayServer.get_name() == "headless",
        "shots_fail": _shots_fail,
    }
    var jf := FileAccess.open(out_dir + "/probe_p9_backpack.json", FileAccess.WRITE)
    if jf != null:
        jf.store_string(JSON.stringify(data, "  "))
        jf.close()


func _await_frames(n: int) -> void:
    for i in range(n):
        await process_frame


func _wait_until(cond: Callable, max_frames: int, label: String) -> bool:
    for i in range(max_frames):
        if bool(cond.call()):
            return true
        await process_frame
    print("[P5BAG][WINDOW] timeout waiting: %s" % label)
    return bool(cond.call())


func _shot(name: String) -> void:
    await RenderingServer.frame_post_draw
    var img: Image = root.get_texture().get_image()
    if img == null or img.get_width() <= 0:
        _shots_fail += 1
        _check("shot." + name, false, "非空 PNG", "empty image")
        return
    var dir := "%s/shots" % out_dir
    DirAccess.make_dir_recursive_absolute(dir)
    var path := "%s/%s.png" % [dir, name]
    var err := img.save_png(path)
    if err != OK:
        _shots_fail += 1
        _check("shot." + name, false, "PNG 保存成功", str(err))
        return
    print("[SHOT] %s %dx%d %s" % [name, img.get_width(), img.get_height(), path])


# ================================================================ 启动 ======
# P7-FINALIZE：与 HUD 的 _bag_canonical_ids() 一致 —— 「整理」后顺序 = 作物产物 → 鱼 → 种子。
func _canonical_ids() -> Array:
    var out: Array = []
    for raw in CROPS.CROP_IDS:
        out.append(CROPS.produce_item(String(raw)))
    for raw in FISH.all_ids():
        out.append(String(raw))
    for raw in CROPS.CROP_IDS:
        out.append(CROPS.seed_item(String(raw)))
    return out


## P7-FINALIZE：面板初始显示顺序 = 种子 → 作物 → 鱼（故意与「整理」后不同，整理是真实重排）。
func _default_ids() -> Array:
    var out: Array = []
    for raw in CROPS.CROP_IDS:
        out.append(CROPS.seed_item(String(raw)))
    for raw in CROPS.CROP_IDS:
        out.append(CROPS.produce_item(String(raw)))
    for raw in FISH.all_ids():
        out.append(String(raw))
    return out


func _boot() -> void:
    _section("0. 正式场景加载与依赖注入")
    _seed_ids = []
    _produce_ids = []
    _canonical_order = _canonical_ids()
    _default_order = _default_ids()
    for raw in CROPS.CROP_IDS:
        _seed_ids.append(CROPS.seed_item(String(raw)))
        _produce_ids.append(CROPS.produce_item(String(raw)))
    var ps := load("res://isle.tscn") as PackedScene
    _check("env.scene_load", ps != null, "isle.tscn 可加载", str(ps != null))
    if ps == null:
        return
    _main = ps.instantiate()
    if _main == null:
        _check("env.scene_instance", false, "实例化成功", "null")
        return
    root.add_child(_main)
    await _await_frames(8)
    _main.set("_mode", 1)
    _inv = _main.call("inventory")
    _farm = _main.call("farm")
    _hud = _main.get("_hud")
    _check("env.inventory_exists", _inv != null, "共享库存实例存在", str(_inv))
    _check("env.farm_exists", _farm != null, "正式九格农田实例存在", str(_farm))
    _check("env.hud_exists", _hud != null and not bool(_main.get("_selftest")),
        "正式 HUD 实例存在", str(_hud))
    if _hud == null:
        return
    _check("env.same_inventory_instance", _farm.get("_inventory") == _inv,
        "农田注入同一个库存实例", str(_farm.get("_inventory") == _inv))
    _check("env.hud_backpack_api", _hud.has_method("toggle_backpack")
        and _hud.has_method("bag_display_state") and _hud.has_method("bag_layout_info")
        and _hud.has_method("sort_backpack"),
        "HUD 暴露背包开关/视图/整理接口", "ok")
    var known: Array = _inv.call("known_item_ids")
    # P7.2：库存白名单的内部顺序（种子在前）不等于背包显示顺序（作物→种子→鱼），
    # 这里按集合比较，再单独证明显示顺序 —— 避免把两种顺序混为一谈。
    var known_sorted: Array = known.duplicate()
    known_sorted.sort()
    var canon_sorted: Array = _canonical_order.duplicate()
    canon_sorted.sort()
    _check("env.known_ids_canonical",
        known_sorted == canon_sorted and known.size() == _canonical_order.size(),
        "16 个规范 ID（5 产物 + 5 种子 + 6 鱼）", str(known))
    _check_eq("env.inventory_grant_count", 1, int(_main.call("inventory_grant_count")))
    # 初始库存：五种种子各 9，产物全 0（isle_inventory.STARTING_SEEDS_PER_CROP）。
    var counts: Dictionary = _inv.call("item_snapshot")
    var seed_ok := true
    for raw in _seed_ids:
        if int(counts.get(raw, 0)) != 9:
            seed_ok = false
    var produce_zero := true
    for raw in _produce_ids:
        if int(counts.get(raw, 0)) != 0:
            produce_zero = false
    _check("env.starting_seed_counts", seed_ok, "五种子各 9", str(counts))
    _check("env.produce_counts_zero", produce_zero, "五产物均 0", str(counts))
    _inv_baseline = _inv.call("export_state") as Dictionary
    if do_shots:
        await _window_prepare()
    else:
        _main.set_process(false)
        _main.set("_day_length", 86400.0)
        _hud.call("set_hud_visible", true, false)
        _await_refresh()
    var feeds: Dictionary = _hud.get("_data")
    _check("env.hud_receives_inventory_items",
        feeds.get("inventory_items", null) == _inv.call("item_snapshot"),
        "update_all 传入只读库存快照", str(feeds.get("inventory_items", null)))
    _check("env.hud_holds_no_inventory", _hud.get("_inventory") == null
        and not _hud.has_method("add_item") and not _hud.has_method("set_count"),
        "HUD 不持有第二套库存/写接口", "none")
    var hud_api: Variant = _hud.call("bag_layout_info")
    _check("env.hud_visible_now", bool(_hud.get("_visible_now")), "true",
        str(_hud.get("_visible_now")))
    _check("env.bag_pill_exists", _bag_pill() != null, "左下角背包入口已创建", str(_bag_pill()))
    _check("env.bag_closed_default", not _bag_open(), "false", str(_bag_open()))
    print("[P5BAG] viewport=%s hud_api_keys=%s" % [
        str((hud_api as Dictionary).get("viewport", Vector2.ZERO)),
        str((hud_api as Dictionary).keys())])


func _await_refresh() -> void:
    _main.call("_update_ui", 0.5)
    await _await_frames(2)


## headless：手动走主控 _update_ui（正式 UI 数据入口），保持断言确定性。
func _refresh_snapshot() -> void:
    _main.call("_update_ui", 0.5)
    await _await_frames(2)


func _hud_state() -> Dictionary:
    return _hud.call("bag_display_state") as Dictionary


func _layout() -> Dictionary:
    return _hud.call("bag_layout_info") as Dictionary


func _bag_open() -> bool:
    return bool(_hud.call("backpack_open"))


func _bag_pill() -> Button:
    return _hud.get("_bag_pill") as Button


func _bag_panel() -> Control:
    return _hud.get("_bag_panel") as Control


func _snapshot() -> Dictionary:
    return _inv.call("export_state") as Dictionary


func _counts() -> Dictionary:
    return _inv.call("item_snapshot") as Dictionary


func _find_button(parent: Node, text: String) -> Button:
    if parent == null:
        return null
    for child in parent.get_children():
        if child is Button and String((child as Button).text) == text:
            return child as Button
        var deep := _find_button(child, text)
        if deep != null:
            return deep
    return null


func _collect_labels(parent: Node, out: Array) -> void:
    if parent == null:
        return
    for child in parent.get_children():
        if child is Label:
            out.append(String((child as Label).text))
        elif child is Button:
            out.append(String((child as Button).text))
        _collect_labels(child, out)


func _click(btn: Button) -> void:
    if btn == null:
        return
    btn.pressed.emit()


func _press_key(code: int) -> void:
    var down := InputEventKey.new()
    down.keycode = code
    down.physical_keycode = code
    down.pressed = true
    Input.parse_input_event(down)
    await process_frame
    var up := InputEventKey.new()
    up.keycode = code
    up.physical_keycode = code
    up.pressed = false
    Input.parse_input_event(up)
    await _await_frames(2)


func _press_b() -> void:
    await _press_key(KEY_B)


# ========================================================== 1. 布局 =======
func _layout_checks() -> void:
    _section("1. 左下角布局（入口在时间胶囊上方、面板不越界）")
    var lay := _layout()
    var pill: Rect2 = lay.get("pill_rect", Rect2())
    var time_rect: Rect2 = lay.get("time_pill_rect", Rect2())
    var vp: Vector2 = lay.get("viewport", Vector2.ZERO)
    _check("h.layout.viewport_nonzero", vp.x > 200.0 and vp.y > 200.0,
        "有效视口", str(vp))
    _check("h.layout.time_pill_exists", time_rect.size.y > 20.0,
        "落位时间胶囊存在", str(time_rect))
    _check("h.layout.pill_visible", _bag_pill() != null and _bag_pill().visible,
        "入口按钮可见", str(_bag_pill()))
    _check("h.layout.pill_height", absf(pill.size.y - 34.0) <= 0.6,
        "34px 胶囊", str(pill.size))
    _check("h.layout.pill_left_aligned", absf(pill.position.x - 34.0) <= 0.6,
        "x=34", str(pill.position))
    _check("h.layout.pill_above_time", bool(lay.get("pill_above_time", false)),
        "入口整体位于时间胶囊上方", "%s vs %s" % [str(pill), str(time_rect)])
    _check("h.layout.pill_gap", time_rect.position.y - pill.end.y >= 4.0,
        ">=4px 间距", "%.1f" % (time_rect.position.y - pill.end.y))
    _check("h.layout.panel_closed_default",
        _bag_panel() != null and not _bag_panel().visible,
        "面板默认隐藏", str(_bag_panel().visible) if _bag_panel() != null else "null")
    _hud.call("open_backpack")
    await _await_frames(4)
    _check("h.layout.panel_opens", _bag_open() and _bag_panel().visible,
        "面板随开关显示", "open=%s visible=%s" % [_bag_open(), _bag_panel().visible])
    lay = _layout()
    var panel: Rect2 = lay.get("panel_rect", Rect2())
    _check("h.layout.panel_no_overlap_time", panel.end.y <= time_rect.position.y + 0.5,
        "面板底边不压时间胶囊",
        "panel_bottom=%.1f time_top=%.1f" % [panel.end.y, time_rect.position.y])
    _check("h.layout.panel_below_pill", panel.end.y <= pill.position.y + 0.5,
        "面板底边在入口上方", "panel_bottom=%.1f pill_top=%.1f" % [panel.end.y, pill.position.y])
    _check("h.layout.panel_on_screen", bool(lay.get("panel_on_screen", false)),
        "面板完整落在可视区", str(panel))
    _check("h.layout.panel_width", panel.size.x >= 380.0 and panel.size.x <= 640.0,
        "380..640 宽", str(panel.size))
    # P7.2：扁平列表 + 只显示已获得物品，高度随可见条目增减（不再固定 16 格三组）。
    _check("h.layout.panel_height", panel.size.y >= 240.0 and panel.size.y <= 640.0,
        "240..640 高（扁平列表按可见条目收缩）", str(panel.size))
    _hud.call("close_backpack")
    await _await_frames(3)


# ==================================================== 2. 入口与 B 键 ======
func _entry_checks() -> void:
    _section("2. 入口按钮与 B 键（同一开关、无冲突、无输入穿透）")
    var paused0: bool = bool(_main.get("_paused"))
    var mode0: int = int(_main.get("_mode"))
    var sim0 := float(_main.get("_sim_seconds"))
    var tree_paused0 := bool(root.get_tree().paused)
    _check("h.entry.closed_initial", not _bag_open(), "false", str(_bag_open()))
    _click(_bag_pill())
    await _await_frames(3)
    _check("h.entry.button_opens", _bag_open(), "点击入口打开", str(_bag_open()))
    _click(_bag_pill())
    await _await_frames(3)
    _check("h.entry.button_closes", not _bag_open(), "再次点击关闭", str(_bag_open()))
    await _press_b()
    _check("h.entry.b_opens", _bag_open(), "B 打开", str(_bag_open()))
    await _press_b()
    _check("h.entry.b_closes", not _bag_open(), "B 关闭", str(_bag_open()))
    # 单一按键只切换一次：打开后按一次 B 必须关闭，不能"按一次跳两步"。
    await _press_b()
    var opened_once := _bag_open()
    await _press_b()
    _check("h.entry.single_press_single_toggle",
        opened_once and not _bag_open(), "一次按键一次切换",
        "open_after_first=%s open_after_second=%s" % [opened_once, _bag_open()])
    # 交叉入口：按钮开 → B 关；B 开 → 按钮关。
    _click(_bag_pill())
    await _await_frames(2)
    await _press_b()
    _check("h.entry.cross_button_then_b", not _bag_open(), "按钮开→B 关", str(_bag_open()))
    await _press_b()
    await _await_frames(2)
    _click(_bag_pill())
    await _await_frames(2)
    _check("h.entry.cross_b_then_button", not _bag_open(), "B 开→按钮关", str(_bag_open()))
    # 打开背包不暂停世界、不切模式、不动时间、不隐藏 HUD。
    await _press_b()
    await _await_frames(3)
    _check("h.entry.no_pause", bool(_main.get("_paused")) == paused0
        and bool(root.get_tree().paused) == tree_paused0, "暂停状态不变",
        "paused=%s tree=%s" % [str(_main.get("_paused")), str(root.get_tree().paused)])
    _check("h.entry.mode_unchanged", int(_main.get("_mode")) == mode0,
        str(mode0), str(_main.get("_mode")))
    _check("h.entry.sim_seconds_unchanged", float(_main.get("_sim_seconds")) == sim0,
        str(sim0), str(_main.get("_sim_seconds")))
    _check("h.entry.hud_stays_visible", bool(_hud.get("_visible_now")), "true",
        str(_hud.get("_visible_now")))
    _check("h.entry.other_panels_closed", not bool(_hud.get("_time_open"))
        and not bool(_hud.get("_weather_open")), "t/false w/false",
        "t=%s w=%s" % [str(_hud.get("_time_open")), str(_hud.get("_weather_open"))])
    # 面板上有明确的关闭控件（标题行 + 底部各一个）。
    var close_btns := 0
    var labels: Array = []
    _collect_labels(_bag_panel(), labels)
    for t in labels:
        if String(t).begins_with("关闭"):
            close_btns += 1
    _check("h.entry.close_control", close_btns >= 2, "标题行与底部各一个关闭控件",
        str(close_btns))
    _check("h.entry.sort_button_present", _find_button(_bag_panel(), "整理") != null,
        "整理按钮存在", str(_find_button(_bag_panel(), "整理")))
    # 与时间/天气面板互斥：同一左下角列不能两块面板叠在一起。
    _hud.call("close_backpack")
    await _await_frames(2)
    _hud.call("toggle_time_panel")
    await _await_frames(3)
    var time_open := bool(_hud.get("_time_open"))
    await _press_b()
    _check("h.entry.bag_collapses_time_panel",
        time_open and _bag_open() and not bool(_hud.get("_time_open")),
        "打开背包时收起时间面板",
        "time_before=%s bag=%s time_after=%s" % [time_open, _bag_open(), _hud.get("_time_open")])
    _hud.call("toggle_time_panel")
    await _await_frames(3)
    _check("h.entry.time_panel_collapses_bag",
        bool(_hud.get("_time_open")) and not _bag_open(),
        "打开时间面板时收起背包",
        "time=%s bag=%s" % [_hud.get("_time_open"), _bag_open()])
    _hud.call("toggle_time_panel")
    await _await_frames(2)
    # HUD 被 H 隐藏时 B 仍可使用：先恢复 HUD 再打开背包。
    await _press_key(KEY_H)
    await _await_frames(3)
    await _press_b()
    _check("h.entry.b_recovers_hidden_hud",
        bool(_hud.get("_visible_now")) and _bag_open(),
        "恢复 HUD 并打开背包",
        "visible=%s open=%s" % [_hud.get("_visible_now"), _bag_open()])
    _hud.call("close_backpack")
    await _await_frames(2)


# ============================================== 3. 十种物品与显示值 ========
func _expected_name(item_id: String) -> String:
    if FISH.has_fish(item_id):
        return FISH.display_name(item_id)
    var crop_id := item_id.trim_prefix("seed_")
    if not CROPS.has_crop(crop_id):
        return item_id
    if item_id.begins_with("seed_"):
        return CROPS.display_name(crop_id) + "种子"
    return CROPS.display_name(crop_id)


func _items_checks() -> void:
    _section("3. 十种规范物品：名称、数量、零数量、无容量概念")
    await _refresh_snapshot()
    _hud.call("open_backpack")
    await _await_frames(4)
    var st := _hud_state()
    var order: Array = st.get("order", [])
    var counts: Dictionary = st.get("counts", {})
    var names: Dictionary = st.get("names", {})
    _check_eq("h.items.slot_count", _canonical_order.size(), order.size())
    var uniq: Dictionary = {}
    for raw in order:
        uniq[String(raw)] = true
    _check("h.items.unique_ids", uniq.size() == _canonical_order.size(), "每种物品各一格", str(uniq.size()))
    var ids_ok := true
    for raw in _canonical_order:
        if not uniq.has(String(raw)):
            ids_ok = false
    _check("h.items.canonical_set", ids_ok, "规范十 ID 全部出现", str(order))
    var name_ok := true
    var name_bad := ""
    for raw in _canonical_order:
        var item_id := String(raw)
        if String(names.get(item_id, "")) != _expected_name(item_id):
            name_ok = false
            name_bad = "%s→%s(期望 %s)" % [item_id, str(names.get(item_id, "")), _expected_name(item_id)]
    _check("h.items.names_from_crops", name_ok, "名称来自 isle_crops.display_name", name_bad)
    var snap := _counts()
    var count_ok := true
    var count_bad := ""
    for raw in _canonical_order:
        var item_id := String(raw)
        if int(counts.get(item_id, -1)) != int(snap.get(item_id, 0)):
            count_ok = false
            count_bad = "%s: ui=%d inv=%d" % [item_id, int(counts.get(item_id, -1)),
                int(snap.get(item_id, 0))]
    _check("h.items.counts_match_inventory", count_ok, "UI 数量=库存数量", count_bad)
    # P7-UX：只显示已获得（数量 > 0）的物品，未获得物品整格隐藏。
    var want_visible: Array = []
    for raw in order:
        var iid := String(raw)
        if int(snap.get(iid, 0)) > 0:
            want_visible.append(iid)
    _check_eq("h.items.visible_order", want_visible, st.get("visible_order", []))
    _check_eq("h.items.visible_count", want_visible.size(), int(st.get("visible_count", -1)))
    var cells: Dictionary = _hud.get("_bag_cells") as Dictionary
    var hide_ok := true
    var hide_bad := ""
    for raw in _canonical_order:
        var iid2 := String(raw)
        var cell := cells.get(iid2) as Control
        var want := int(snap.get(iid2, 0)) > 0
        if cell == null or cell.visible != want:
            hide_ok = false
            hide_bad = "%s visible=%s want=%s" % [iid2, str(cell.visible if cell != null else "null"), str(want)]
    _check("h.items.zero_hidden", hide_ok, "数量 0 的格子不可见（不再显示 ×0）", hide_bad)
    # P7.2：单一扁平列表 —— 不再有三组小标题，分类改由次级菜单负责。
    _check("h.items.flat_list", bool(st.get("flat", false)) and int(st.get("section_count", -1)) == 0,
        "flat=true section_count=0", "flat=%s section=%s" % [st.get("flat"), st.get("section_count")])
    var all_labels: Array = []
    _collect_labels(_bag_panel(), all_labels)
    var group_title_hit := ""
    for raw_t in all_labels:
        for gtitle in ["种子 · SEEDS", "作物 · CROPS", "鱼 · FISH"]:
            if String(raw_t).contains(String(gtitle)):
                group_title_hit = String(raw_t)
    _check("h.items.no_group_titles", group_title_hit == "", "面板内无分组小标题", group_title_hit)
    # P7-FINALIZE：说明性小字已删除，只保留标题/名称/数量/整理/分类/关闭/空状态提示。
    var explain_hit := ""
    for raw_t2 in all_labels:
        for ew in BAG_EXPLANATORY_WORDS:
            if String(raw_t2).contains(String(ew)):
                explain_hit = "%s ← %s" % [String(ew), String(raw_t2)]
    _check("h.items.no_explanatory_text", explain_hit == "",
        "面板无说明性小字（显示顺序/共享库存/B 键开关/只显示已获得/分类叠加）", explain_hit)
    _check("h.items.filter_default",
        String(st.get("filter", "")) == "all" and not bool(st.get("filter_menu_open", true))
            and (st.get("filter_options", []) as Array) == ["all", "produce", "fish", "seed"]
            and String(st.get("filter_button_text", "")) == "分类：全部",
        "默认全部·菜单收起·四个筛选项", "%s / %s / %s" % [st.get("filter"), st.get("filter_menu_open"), st.get("filter_button_text")])
    _check("h.items.empty_note_hidden", not bool(st.get("empty_visible", true)), "有物品时不显示空背包提示", str(st.get("empty_visible")))
    _check("h.items.filter_contract", bool(st.get("filtered", false))
        and String(st.get("filter_rule", "")) == "count>0", "过滤契约 count>0", str(st.get("filter_rule")))
    var total_ui := 0
    for raw in _canonical_order:
        total_ui += int(counts.get(String(raw), 0))
    _check("h.items.total_matches_inventory", total_ui == int(_inv.call("total_count")),
        str(_inv.call("total_count")), str(total_ui))
    # 不展示负重/格位/容量/堆叠上限等概念。
    var labels: Array = []
    _collect_labels(_bag_panel(), labels)
    var forbidden := ""
    for t in labels:
        for w in FORBIDDEN_BAG_WORDS:
            if String(t).contains(String(w)):
                forbidden = "%s ← %s" % [String(w), String(t)]
    _check("h.items.no_capacity_concepts", forbidden == "", "无容量/负重/格位文案", forbidden)
    # 空背包：只向 HUD 视图注入全 0 快照（不改正式库存），验证空提示与整组隐藏。
    var data: Dictionary = _hud.get("_data") as Dictionary
    var fake: Dictionary = data.duplicate(true)
    var zero_items: Dictionary = {}
    for raw in _canonical_order:
        zero_items[String(raw)] = 0
    fake["inventory_items"] = zero_items
    _hud.call("update_all", fake)
    await _await_frames(2)
    var st_empty := _hud_state()
    _check_eq("h.items.empty_visible", true, bool(st_empty.get("empty_visible", false)))
    _check_eq("h.items.empty_visible_count", 0, int(st_empty.get("visible_count", -1)))
    # P7-FINALIZE：说明性小字删除后，空状态提示仍必须保留（唯一允许的解释性状态文案）。
    var empty_note := _hud.get("_bag_empty_note") as Label
    _check("h.items.empty_note_kept",
        empty_note != null and empty_note.visible and String(empty_note.text) != "",
        "空状态提示保留", "<null>" if empty_note == null else String(empty_note.text))
    _check("h.items.empty_flat_hidden",
        int(st_empty.get("visible_count", -1)) == 0 and bool(st_empty.get("flat", false)),
        "空背包时没有任何可见条目", "visible=%s flat=%s" % [st_empty.get("visible_count"), st_empty.get("flat")])
    await _refresh_snapshot()
    _check_eq("h.items.restored_visible_count", int(st.get("visible_count", -1)),
        int(_hud_state().get("visible_count", -2)))
    # 图标位置干净留空：格子仍为 34x34 空 Panel，无贴图/文字/Eemoji；隐藏格不渲染。
    var icon_acc: Array = [0, 0]
    _count_icons(_bag_panel(), icon_acc)
    var icons := int(icon_acc[0])
    var icon_dirty := int(icon_acc[1])
    _check("h.items.blank_icon_slots", icons == _canonical_order.size() and icon_dirty == 0,
        "每个物品一个空白图标占位且无内容", "icons=%d dirty=%d" % [icons, icon_dirty])
    var vis_acc: Array = [0, 0]
    _count_icons(_bag_panel(), vis_acc, true)
    _check_eq("h.items.visible_icon_slots", int(st.get("visible_count", 0)), int(vis_acc[0]))
    _check("h.items.no_emoji_or_temp_art", icon_dirty == 0, "无临时图标", str(icon_dirty))
    _hud.call("close_backpack")
    await _await_frames(2)


func _count_icons(parent: Node, acc: Array, visible_only: bool = false) -> void:
    if parent == null:
        return
    for child in parent.get_children():
        if child is PanelContainer:
            var pc := child as PanelContainer
            if pc.custom_minimum_size == Vector2(34, 34):
                if visible_only and not pc.is_visible_in_tree():
                    continue
                acc[0] = int(acc[0]) + 1
                if pc.get_child_count() > 0:
                    acc[1] = int(acc[1]) + 1
        _count_icons(child, acc, visible_only)


# ==================================================== 3.5 分类筛选菜单 =====
# P7.2：分类改为次级菜单（全部 / 作物 / 种子 / 鱼），与「只显示已获得」叠加，只改显示不改库存。
func _only_in(vis: Array, allowed: Array) -> bool:
    for raw in vis:
        if not allowed.has(String(raw)):
            return false
    return true


func _visible_after_counts(ids: Array) -> Array:
    var out: Array = []
    var snap: Dictionary = _counts()
    for raw in ids:
        if int(snap.get(String(raw), 0)) > 0:
            out.append(String(raw))
    return out


func _filter_checks() -> void:
    _section("3.5 次级分类菜单：全部/作物/种子/鱼（只改显示，不改库存）")
    await _refresh_snapshot()
    _hud.call("open_backpack")
    await _await_frames(4)
    var exp0: Dictionary = _snapshot()
    _hud.call("toggle_bag_filter_menu")
    await _await_frames(2)
    var st_menu := _hud_state()
    _check("h.filter.menu_opens", bool(st_menu.get("filter_menu_open", false)),
        "分类菜单展开", str(st_menu.get("filter_menu_open")))
    # 作物：此时库存只有种子 → 分类内无物品，应显示「此分类下还没有物品」提示。
    var ok_prod := bool(_hud.call("set_bag_filter", "produce"))
    await _await_frames(2)
    var st_prod := _hud_state()
    _check("h.filter.select_produce",
        ok_prod and String(st_prod.get("filter", "")) == "produce"
            and _only_in(st_prod.get("visible_order", []), _produce_ids),
        "作物筛选只显示作物", "%s / %s" % [st_prod.get("filter"), st_prod.get("visible_order", [])])
    _check("h.filter.produce_empty_hint",
        int(st_prod.get("visible_count", -1)) == _visible_after_counts(_produce_ids).size()
            and (int(st_prod.get("visible_count", -1)) > 0 or bool(st_prod.get("empty_visible", false))),
        "分类为空时显示空提示", "visible=%s empty=%s" % [st_prod.get("visible_count"), st_prod.get("empty_visible")])
    # 种子：只显示种子，且仍叠加「数量 > 0」。
    _hud.call("set_bag_filter", "seed")
    await _await_frames(2)
    var st_seed := _hud_state()
    _check_eq("h.filter.select_seed", _visible_after_counts(_seed_ids), st_seed.get("visible_order", []))
    _check("h.filter.seed_not_empty", not bool(st_seed.get("empty_visible", true)),
        "有种子时不显示空提示", str(st_seed.get("empty_visible")))
    _check("h.filter.button_text", String(st_seed.get("filter_button_text", "")) == "分类：种子",
        "按钮文案随分类变化", str(st_seed.get("filter_button_text")))
    # 鱼：未钓到过 → 空。
    _hud.call("set_bag_filter", "fish")
    await _await_frames(2)
    var st_fish := _hud_state()
    var fish_ids: Array = []
    for raw in FISH.all_ids():
        fish_ids.append(String(raw))
    _check("h.filter.select_fish",
        String(st_fish.get("filter", "")) == "fish"
            and _only_in(st_fish.get("visible_order", []), fish_ids)
            and int(st_fish.get("visible_count", -1)) == _visible_after_counts(fish_ids).size(),
        "鱼筛选只显示鱼", str(st_fish.get("visible_order", [])))
    # 切回全部：恢复「数量 > 0」的全量视图。
    _hud.call("set_bag_filter", "all")
    await _await_frames(2)
    var st_all := _hud_state()
    _check_eq("h.filter.back_to_all", _visible_after_counts(st_all.get("order", [])), st_all.get("visible_order", []))
    # 非法分类被拒绝且不改变当前状态。
    var bad := bool(_hud.call("set_bag_filter", "no_such_filter"))
    await _await_frames(1)
    _check("h.filter.invalid_rejected",
        not bad and String(_hud_state().get("filter", "")) == "all",
        "非法分类返回 false 且状态不变", "%s / %s" % [bad, _hud_state().get("filter")])
    _check_eq("h.filter.counts_unchanged", exp0, _snapshot())
    _hud.call("toggle_bag_filter_menu")
    await _await_frames(2)
    _check("h.filter.menu_closes", not bool(_hud_state().get("filter_menu_open", true)),
        "分类菜单可收起", str(_hud_state().get("filter_menu_open")))
    _hud.call("close_backpack")
    await _await_frames(2)


# ============================================================ 4. 整理 =====
func _sort_checks() -> void:
    _section("4. 一键整理：默认 种子→作物→鱼，整理后 作物→鱼→种子，数量不变")
    await _refresh_snapshot()
    _hud.call("open_backpack")
    await _await_frames(4)
    var before := _hud_state()
    var order0: Array = before.get("order", [])
    # P7-FINALIZE：面板初始顺序 = 种子 → 作物 → 鱼（与整理后不同，整理必须产生真实可见重排）。
    _check("h.sort.default_order", order0 == _default_order and _default_order != _canonical_order,
        "默认顺序=种子→作物→鱼（且与整理后不同）", str(order0))
    var exp_before: Dictionary = _snapshot()
    var counts_before: Dictionary = before.get("counts", {})
    var sort_btn := _find_button(_bag_panel(), "整理")
    _check("h.sort.button_found", sort_btn != null, "找到并点击整理按钮", str(sort_btn))
    if sort_btn != null:
        _click(sort_btn)
    await _await_frames(3)
    var after := _hud_state()
    _check("h.sort.applied", bool(after.get("sorted", false))
        and int(after.get("sort_count", 0)) == 1, "sorted=true sort_count=1",
        "sorted=%s count=%s" % [after.get("sorted"), after.get("sort_count")])
    var after_order: Array = after.get("order", [])
    _check("h.sort.order_canonical", after_order == _canonical_order,
        str(_canonical_order), str(after_order))
    var fish_ids: Array = []
    for raw in FISH.all_ids():
        fish_ids.append(String(raw))
    var produce_part: Array = after_order.slice(0, 5)
    var fish_part: Array = after_order.slice(5, 11)
    var seed_part: Array = after_order.slice(11, 16)
    _check("h.sort.produce_first", produce_part == _produce_ids,
        "整理后先作物产物（按 isle_crops 目录）", str(produce_part))
    _check("h.sort.fish_second", fish_part == fish_ids,
        "整理后其次鱼（按 isle_fish 目录）", str(fish_part))
    _check("h.sort.seeds_last", seed_part == _seed_ids,
        "整理后种子最后（按 isle_crops 目录）", str(seed_part))
    var vis_sorted: Array = after.get("visible_order", [])
    var want_sorted: Array = []
    for raw in _canonical_order:
        if int((after.get("counts", {}) as Dictionary).get(String(raw), 0)) > 0:
            want_sorted.append(String(raw))
    _check_eq("h.sort.visible_order", want_sorted, vis_sorted)
    _check_eq("h.sort.counts_unchanged", counts_before, after.get("counts", {}))
    _check_eq("h.sort.export_unchanged", exp_before, _snapshot())
    # P7-FINALIZE：说明性小字已删除——整理后也不得出现"显示顺序…/已整理…"之类说明。
    var note_ok := true
    var note_hit := ""
    var labels: Array = []
    _collect_labels(_bag_panel(), labels)
    for t in labels:
        for w in BAG_EXPLANATORY_WORDS:
            if String(t).contains(String(w)):
                note_ok = false
                note_hit = "%s ← %s" % [String(w), String(t)]
    _check("h.sort.no_explanatory_note", note_ok,
        "整理后仍无说明性小字（顺序变化本身就是反馈）", note_hit)
    # 重复点击幂等：顺序与数量不变，计数递增。
    if sort_btn != null:
        _click(sort_btn)
    await _await_frames(2)
    var again := _hud_state()
    _check("h.sort.idempotent", again.get("order", []) == _canonical_order
        and int(again.get("sort_count", 0)) == 2, "再次整理顺序不变",
        "order_ok=%s count=%s" % [str(again.get("order", []) == _canonical_order),
            str(again.get("sort_count"))])
    _check_eq("h.sort.counts_unchanged_twice", counts_before, again.get("counts", {}))
    # 关闭再打开：显示顺序保持（UI 状态，不涉及存档）。
    _hud.call("close_backpack")
    await _await_frames(2)
    _hud.call("open_backpack")
    await _await_frames(3)
    _check("h.sort.persists_after_reopen", _hud_state().get("order", []) == _canonical_order,
        "关闭再打开保持整理顺序", str(_hud_state().get("order", [])))
    _hud.call("close_backpack")
    await _await_frames(2)


# =================================================== 5. 只读与一致性 ======
func _readonly_checks() -> void:
    _section("5. 只读性：开关/整理不改变库存、农田与时间")
    await _refresh_snapshot()
    var inv0: Dictionary = _snapshot()
    var farm0: Dictionary = _farm.call("export_state") as Dictionary
    var sim0 := float(_main.get("_sim_seconds"))
    var total0 := int(_inv.call("total_count"))
    for i in range(20):
        _hud.call("toggle_backpack")
        await process_frame
    _hud.call("close_backpack")
    await _await_frames(3)
    _check_eq("h.ro.export_after_20_toggles", inv0, _snapshot())
    _check_eq("h.ro.farm_state_after_toggles", farm0, _farm.call("export_state"))
    _check_eq("h.ro.total_count_after_toggles", total0, int(_inv.call("total_count")))
    _check("h.ro.sim_seconds_after_toggles",
        float(_main.get("_sim_seconds")) == sim0, str(sim0),
        str(_main.get("_sim_seconds")))
    _hud.call("open_backpack")
    await _await_frames(2)
    _click(_find_button(_bag_panel(), "整理"))
    await _await_frames(2)
    _check_eq("h.ro.export_after_sort", inv0, _snapshot())
    _check_eq("h.ro.farm_state_after_sort", farm0, _farm.call("export_state"))
    _check("h.ro.same_inventory_instance", _main.call("inventory") == _inv, "同一实例", "same")
    _check_eq("h.ro.export_has_version", 1, int(inv0.get("version", -1)))


# =============================================== 6. 库存事务与 UI 同步 =====
func _sync_checks() -> void:
    _section("6. 真实农田事务后背包数量同步（只读展示）")
    _farm.call("reset")
    _farm.call("advance_to", float(_main.get("_sim_seconds")))
    var season := String(_main.call("_farm_season_id"))
    await _refresh_snapshot()
    var counts0 := _counts()
    var snap0: Dictionary = _snapshot()
    var plant_res: Dictionary = _farm.call("plant", 0, "wheat", season) as Dictionary
    _check("h.sync.plant_ok", bool(plant_res.get("ok", false)),
        "播种成功", str(plant_res.get("reason", "")))
    await _refresh_snapshot()
    var counts1 := _counts()
    var snap1: Dictionary = _snapshot()
    _check_eq("h.sync.plant_consumes_one_seed",
        int(counts0.get("seed_wheat", 0)) - 1, int(counts1.get("seed_wheat", 0)))
    var st1 := _hud_state()
    _check_eq("h.sync.seed_label_after_plant",
        int(counts1.get("seed_wheat", 0)), int((st1.get("counts", {}) as Dictionary).get("seed_wheat", -1)))
    _check("h.sync.export_after_plant_differs", snap0 != snap1, "库存确有一次事务", "diff")
    # 让植株成熟后真实采收（首收会返还 1 颗种子 + 产物）。
    var now := float(_main.get("_sim_seconds"))
    _farm.call("advance_to", now + 20000.0)
    var can: Dictionary = _farm.call("can_harvest", 0) as Dictionary
    _check("h.sync.mature_ready", bool(can.get("ok", false)), "成熟可收", str(can))
    var harv: Dictionary = _farm.call("harvest", 0) as Dictionary
    _check("h.sync.harvest_ok", bool(harv.get("ok", false)), "采收成功", str(harv))
    var produce_item := String(harv.get("produce_item", ""))
    var produce_amt := int(harv.get("produce_amount", 0))
    var seed_back := int(harv.get("seed_returned", 0))
    await _refresh_snapshot()
    var counts2 := _counts()
    var st2 := _hud_state()
    _check_eq("h.sync.produce_inventory_delta",
        int(counts1.get(produce_item, 0)) + produce_amt, int(counts2.get(produce_item, 0)))
    _check_eq("h.sync.produce_label_after_harvest", int(counts2.get(produce_item, 0)),
        int((st2.get("counts", {}) as Dictionary).get(produce_item, -1)))
    _check_eq("h.sync.first_harvest_seed_returned",
        int(counts1.get("seed_wheat", 0)) + seed_back, int(counts2.get("seed_wheat", 0)))
    _check("h.sync.ui_total_matches", _sum_states(st2) == int(_inv.call("total_count")),
        str(_inv.call("total_count")), str(_sum_states(st2)))
    # P7.2：扁平列表里采收后产物格直接出现在可见集合中（没有分组标题可断言）。
    _check("h.sync.produce_visible_after_harvest",
        (st2.get("visible_order", []) as Array).has(produce_item) and bool(st2.get("flat", false)),
        "采收后产物格在扁平列表中可见", str(st2.get("visible_order", [])))
    # 重复刷新不会重复计数（HUD 只读，不会扣加库存）。
    var total_before := int(_inv.call("total_count"))
    for i in range(5):
        await _refresh_snapshot()
    _check_eq("h.sync.no_double_count_on_refresh", total_before, int(_inv.call("total_count")))
    _hud.call("close_backpack")
    await _await_frames(2)
    var st3 := _hud_state()
    _check("h.sync.closed_panel_counts_still_readonly",
        _sum_states(st3) == int(_inv.call("total_count")), "关闭后一致",
        str(_sum_states(st3)))


func _sum_states(st: Dictionary) -> int:
    var counts: Dictionary = st.get("counts", {})
    var total := 0
    for k in counts.keys():
        total += int(counts[k])
    return total


# ======================================================== 7. 真实窗口 =====
func _window_force_sim_time() -> void:
    _main.set("_time_source", "sim")
    _main.set("_realtime", false)
    var sets: Variant = _main.get("_settings")
    if sets is Dictionary:
        (sets as Dictionary)["time_source"] = "sim"


func _force_weather(type_id: String) -> void:
    var wx: Object = _main.get("_weather")
    if wx == null:
        return
    var real := String({"rain": "mid_rain", "snow": "heavy_snow"}.get(type_id, type_id))
    wx.call("set_manual_type", real)
    wx.call("reset", float(_main.get("_sim_seconds")))
    _main.call("_update_weather", 0.0, true)


func _yard_center() -> Vector3:
    var world: Dictionary = _main.get("_world") as Dictionary
    var fy: Dictionary = world.get("front_yard", {}) as Dictionary
    var rows: Array = fy.get("slots", [])
    var sum := Vector3.ZERO
    for r in rows:
        var w: Vector2 = (r as Dictionary).get("world", Vector2.ZERO)
        sum += Vector3(w.x, 7.6, w.y)
    if rows.is_empty():
        return Vector3(0, 7.6, 0)
    return sum / float(rows.size())


func _window_aim(target: Vector3, dist: float, height: float = 0.55) -> void:
    var eye := target + Vector3(dist * 0.62, dist * height, dist * 0.62)
    _main.call("_pose_look", eye, target + Vector3(0, 0.5, 0), 55.0)


func _window_prepare() -> void:
    _window_force_sim_time()
    _main.set("_day_length", 86400.0)
    _main.call("_jump_datetime", BASE_Y, BASE_M, BASE_D, 6, 0, 0)
    await _await_frames(2)
    _force_weather("clear")
    _main.set("_paused", false)
    _main.set("_started", true)
    if _main.has_method("_enter_playing"):
        _main.call("_enter_playing")
    _main.set("_mode", 1)
    _main.set_process(true)
    await _await_frames(30)
    var menu: Variant = _main.get("_menu")
    if menu != null and bool((menu as Node).get("visible")):
        (menu as Node).call("close")
        await _wait_until(func() -> bool: return not bool((menu as Node).get("visible")), 900, "menu close")
    _hud.call("set_hud_visible", true, false)
    _window_aim(_yard_center(), 10.0, 0.5)
    await _await_frames(10)


func _window_run() -> void:
    _section("7. 真实窗口运行（左下角入口 / B 键 / 整理 / 事务同步 / resize）")
    # P7-FINALIZE 视觉证据：注入少量作物产物 + 鱼（仅本次探针运行的内存态，不落盘、不影响正式游戏），
    # 让「整理」前后（默认 种子→作物→鱼 vs 整理后 作物→鱼→种子）在真实窗口截图里可辨别。
    # 刻意避开 wheat / fish_koi：窗口断言用它们验证"未获得物品隐藏"。
    # 放在 _window_run 开头而不是 _window_prepare：_boot 的"HUD 收到只读库存快照"断言先跑，避免更新时序竞争。
    _inv.call("add_items", {"corn": 1, "tomato": 1, "fish_crucian": 1, "fish_sardine": 1})
    _main.call("_update_ui", 0.0)
    await _await_frames(3)
    var menu: Variant = _main.get("_menu")
    _check("win.playing", int(_main.get("_mode")) == 1, "1", str(_main.get("_mode")))
    _check("win.menu_hidden", menu == null or not bool((menu as Node).get("visible")),
        "标题菜单已隐藏", "hidden")
    _check("win.hud_visible", bool(_hud.get("_visible_now")), "true",
        str(_hud.get("_visible_now")))
    var lay := _layout()
    var vp: Vector2 = lay.get("viewport", Vector2.ZERO)
    print("[P5BAG][WINDOW] viewport=", vp, " pill=", lay.get("pill_rect"),
        " time=", lay.get("time_pill_rect"))
    _check("win.layout.pill_above_time", bool(lay.get("pill_above_time", false)),
        "入口在时间胶囊上方", str(lay.get("pill_rect")))
    _check("win.layout.viewport_native", vp.x >= 1280.0 and vp.y >= 720.0,
        ">=1280x720", str(vp))
    _check("win.bag_closed_before", not _bag_open(), "false", str(_bag_open()))
    await _shot("01_main_with_entry")
    _click(_bag_pill())
    await _await_frames(6)
    _check("win.click_opens", _bag_open() and _bag_panel().visible, "点击入口打开面板",
        "open=%s" % _bag_open())
    lay = _layout()
    var panel: Rect2 = lay.get("panel_rect", Rect2())
    var time_rect: Rect2 = lay.get("time_pill_rect", Rect2())
    _check("win.layout.panel_on_screen", bool(lay.get("panel_on_screen", false)),
        "面板完整可见", str(panel))
    _check("win.layout.panel_above_time_pill", panel.end.y <= time_rect.position.y + 0.5,
        "不压时间胶囊", "panel_bottom=%.1f time_top=%.1f" % [panel.end.y, time_rect.position.y])
    var st := _hud_state()
    _check_eq("win.items.slot_count", _canonical_order.size(), (st.get("order", []) as Array).size())
    var snap := _counts()
    var counts: Dictionary = st.get("counts", {})
    var sync_ok := true
    for raw in _canonical_order:
        if int(counts.get(String(raw), -1)) != int(snap.get(String(raw), 0)):
            sync_ok = false
    _check("win.items.counts_match_inventory", sync_ok, "UI 数量=库存数量", str(counts))
    # P7-UX：真实窗口里也只显示已获得物品。
    # 面板默认顺序来自 UI 当前 order（整理前不一定等于目录顺序），因此顺序按 UI 顺序核对，
    # 另以排序后的集合证明可见集合恰为库存 >0 的规范子集。
    var want_visible: Array = []
    for raw_o in (st.get("order", []) as Array):
        if int(snap.get(String(raw_o), 0)) > 0:
            want_visible.append(String(raw_o))
    _check_eq("win.items.visible_order", want_visible, st.get("visible_order", []))
    _check_eq("win.items.visible_count", want_visible.size(), int(st.get("visible_count", -1)))
    var want_canon: Array = []
    for raw_c in _canonical_order:
        if int(snap.get(String(raw_c), 0)) > 0:
            want_canon.append(String(raw_c))
    var got_set: Array = (st.get("visible_order", []) as Array).duplicate()
    got_set.sort()
    want_canon.sort()
    _check_eq("win.items.visible_set", want_canon, got_set)
    _check("win.items.zero_hidden",
        bool(st.get("flat", false)) and not (st.get("visible_order", []) as Array).has("wheat")
            and not (st.get("visible_order", []) as Array).has("fish_koi"),
        "未获得物品不出现（不再显示 ×0，扁平列表）", str(st.get("visible_order")))
    await _shot("02_bag_open")
    # P7.2：次级分类菜单真实窗口证据（只改显示顺序/可见性，不改库存数量）。
    _hud.call("toggle_bag_filter_menu")
    await _await_frames(4)
    _check_eq("win.filter.menu_open", bool(_hud_state().get("filter_menu_open", false)), true)
    await _shot("02b_bag_filter_menu")
    _hud.call("set_bag_filter", "seed")
    await _await_frames(4)
    var st_seed_w := _hud_state()
    var only_seed := true
    for raw_s in (st_seed_w.get("visible_order", []) as Array):
        if not String(raw_s).begins_with("seed_"):
            only_seed = false
    _check("win.filter.seed_only", only_seed and int(st_seed_w.get("visible_count", -1)) > 0,
        "分类=种子时只显示种子", str(st_seed_w.get("visible_order", [])))
    await _shot("02c_bag_filter_seed")
    _hud.call("set_bag_filter", "produce")
    await _await_frames(4)
    var st_prod_w := _hud_state()
    var vis_prod: Array = st_prod_w.get("visible_order", [])
    var want_prod: Array = []
    for raw_p in _produce_ids:
        if int(snap.get(String(raw_p), 0)) > 0:
            want_prod.append(String(raw_p))
    _check("win.filter.produce_view",
        _only_in(vis_prod, _produce_ids) and vis_prod == want_prod
            and bool(st_prod_w.get("empty_visible", false)) == (want_prod.is_empty()),
        "分类=作物时只显示已获得作物；无作物时显示空提示（本窗口运行注入了 corn/tomato 产物）",
        "vis=%s want=%s empty=%s" % [str(vis_prod), str(want_prod), str(st_prod_w.get("empty_visible"))])
    await _shot("02d_bag_filter_produce")
    _hud.call("set_bag_filter", "all")
    _hud.call("toggle_bag_filter_menu")
    await _await_frames(4)
    _check_eq("win.filter.back_to_all", _hud_state().get("filter", ""), "all")
    _check_eq("win.filter.counts_unchanged", counts, _hud_state().get("counts", {}))
    # 一键整理（真实点击按钮）
    var sort_btn := _find_button(_bag_panel(), "整理")
    _click(sort_btn)
    await _await_frames(5)
    var st_sorted := _hud_state()
    _check("win.sort.order_canonical", st_sorted.get("order", []) == _canonical_order,
        "作物 5 → 鱼 6 → 种子 5（整理后规范顺序）", str(st_sorted.get("order", [])))
    _check_eq("win.sort.counts_unchanged", counts, st_sorted.get("counts", {}))
    # 整理后可见顺序 = 规范顺序 ∩ 数量>0（截图 03_bag_sorted 应看到 作物→鱼→种子）。
    var want_vis: Array = []
    for raw in _canonical_order:
        if int(snap.get(String(raw), 0)) > 0:
            want_vis.append(String(raw))
    _check_eq("win.sort.visible_order", want_vis, st_sorted.get("visible_order", []))
    # 说明性小字已删除（真实窗口路径也断言）。
    var win_labels: Array = []
    _collect_labels(_bag_panel(), win_labels)
    var win_explain := ""
    for t in win_labels:
        for w in BAG_EXPLANATORY_WORDS:
            if String(t).contains(String(w)):
                win_explain = "%s ← %s" % [String(w), String(t)]
    _check("win.no_explanatory_text", win_explain == "",
        "真实窗口背包面板无说明性小字", win_explain)
    await _shot("03_bag_sorted")
    # 真实农田事务：播种 → 背包种子数量同步
    _farm.call("reset")
    _farm.call("advance_to", float(_main.get("_sim_seconds")))
    await _await_frames(3)
    var c0 := _counts()
    var wseason := String(_main.call("_farm_season_id"))
    var pr: Dictionary = _farm.call("plant", 0, "wheat", wseason) as Dictionary
    _check("win.sync.plant_ok", bool(pr.get("ok", false)), "播种成功", str(pr.get("reason", "")))
    var seed_target := int(c0.get("seed_wheat", 0)) - 1
    var seed_synced := await _wait_until(func() -> bool: return int((_hud_state().get("counts", {}) as Dictionary).get("seed_wheat", -1)) == seed_target, 240, "seed label sync")
    _check("win.sync.seed_label_after_plant", seed_synced,
        str(seed_target), str((_hud_state().get("counts", {}) as Dictionary).get("seed_wheat")))
    await _shot("04_after_plant")
    # 真实采收 → 产物数量同步（采收前先取基准，避免把已入账数量算两遍）
    var counts_before_h := _counts()
    var now := float(_main.get("_sim_seconds"))
    _farm.call("advance_to", now + 20000.0)
    var harv: Dictionary = _farm.call("harvest", 0) as Dictionary
    _check("win.sync.harvest_ok", bool(harv.get("ok", false)), "采收成功", str(harv))
    var produce_item := String(harv.get("produce_item", ""))
    var produce_amt := int(harv.get("produce_amount", 0))
    var produce_target := int(counts_before_h.get(produce_item, 0)) + produce_amt
    var produce_synced := await _wait_until(func() -> bool: return int((_hud_state().get("counts", {}) as Dictionary).get(produce_item, -1)) == produce_target, 240, "produce label sync")
    _check("win.sync.produce_label_after_harvest", produce_synced,
        str(produce_target), str((_hud_state().get("counts", {}) as Dictionary).get(produce_item)))
    var st_h := _hud_state()
    _check("win.sync.produce_visible_after_harvest",
        (st_h.get("visible_order", []) as Array).has(produce_item),
        "采收后产物格可见（扁平列表）", str(st_h.get("visible_order", [])))
    await _shot("05_after_harvest")
    # 背包打开期间世界时间照常推进（不暂停）。
    var sim0 := float(_main.get("_sim_seconds"))
    var total0 := int(_inv.call("total_count"))
    await _await_frames(60)
    var sim1 := float(_main.get("_sim_seconds"))
    _check("win.time_running_while_bag_open", sim1 > sim0 + 0.05,
        "打开背包时模拟时间继续推进", "%.3f → %.3f" % [sim0, sim1])
    _check_eq("win.inventory_realtime_no_drift", total0, int(_inv.call("total_count")))
    _check("win.bag_still_open", _bag_open(), "true", str(_bag_open()))
    # B 键在真实窗口中的开关
    await _press_b()
    _check("win.b_closes", not _bag_open(), "B 关闭", str(_bag_open()))
    await _press_b()
    _check("win.b_opens", _bag_open(), "B 打开", str(_bag_open()))
    await _shot("06_bag_reopened_by_b")
    # 窗口尺寸变化：左下角组合仍然可用（真实改窗口，不用 UI 假缩放）。
    var orig := DisplayServer.window_get_size()
    var orig_mode := DisplayServer.window_get_mode()
    if orig_mode == DisplayServer.WINDOW_MODE_FULLSCREEN or orig_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
        DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
        await _await_frames(15)
    DisplayServer.window_set_size(Vector2i(1280, 720))
    await _await_frames(45)
    var lay2 := _layout()
    # 项目使用 canvas_items 拉伸：视口基准仍按设计分辨率，所以断言"真实窗口"尺寸生效，
    # 同时验证 HUD 布局在该窗口下仍然可用（不依赖固定像素）。
    var wsz := DisplayServer.window_get_size()
    _check("win.resize.window_1280x720", absi(wsz.x - 1280) <= 2 and absi(wsz.y - 720) <= 2,
        "1280x720", str(wsz))
    _check("win.resize.pill_above_time", bool(lay2.get("pill_above_time", false)),
        "入口仍在时间胶囊上方", str(lay2.get("pill_rect")))
    _check("win.resize.panel_on_screen", bool(lay2.get("panel_on_screen", false)),
        "面板仍完整可见", str(lay2.get("panel_rect")))
    _check("win.resize.panel_no_time_overlap",
        (lay2.get("panel_rect", Rect2()) as Rect2).end.y
            <= (lay2.get("time_pill_rect", Rect2()) as Rect2).position.y + 0.5,
        "面板不压时间胶囊", str(lay2.get("panel_rect")))
    await _shot("07_resized_1280x720")
    DisplayServer.window_set_size(orig)
    DisplayServer.window_set_mode(orig_mode)
    await _await_frames(20)
    _check_eq("win.shots_fail", 0, _shots_fail)
