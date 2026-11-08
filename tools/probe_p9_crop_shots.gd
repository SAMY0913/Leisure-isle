extends SceneTree
## P9 / P3 —— 作物模型展示台真实渲染截图探针。
##
## 只读：不修改 scripts/ 下任何 .gd、不修改 isle.tscn、不做任何 git 操作。
## 展台（土台 / 背景板 / Label3D 标签）只在本次探针运行时存在，绝不进入正式游戏场景。
##
## 用法（必须开真窗口，不能 --headless，否则 SubViewport 出不了图）：
##   "D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe" \
##     --path "D:/休闲小岛幻境/游戏工程" \
##     --script res://tools/probe_p9_crop_shots.gd \
##     -- --out="D:/休闲小岛幻境/开发产物/P9/P3/shots/p3"
## 注意：不要传 --shots（那会触发 main.gd 内置截图流程）。
##
## 输出：<out>/*.png（1600x1000）、<out>/p3_crop_shots.log、<out>/p3_crop_shots.json
## 每张图打印 "SHOT <name> 1600x1000 err=0"，结尾打印 [RESULT] PASS|FAIL 并 quit(0/1)。

const SHOT_W := 1600
const SHOT_H := 1000
const M := preload("res://scripts/isle_math.gd")
const CM := preload("res://scripts/isle_crop_models.gd")
const FONT_RES := "res://fonts/simhei.ttf"
const DEFAULT_OUT := "D:/休闲小岛幻境/开发产物/P9/P3/shots/p3"

const STAGES := ["seedling", "growing", "mature"]
const STAGE_CN := {"seedling": "幼苗", "growing": "生长中", "mature": "成熟"}
const CROP_CN := {
    "wheat": "小麦", "corn": "玉米", "watermelon": "西瓜",
    "tomato": "番茄", "kale": "羽衣甘蓝",
}

# ---- 展台位置：远离岛的空中，避免与岛屿几何相交；仍在同一 World3D 内以复用正式光照 ----
const OVER_ORIGIN := Vector3(400.0, 150.0, 0.0)
const CLOSE_ORIGIN := Vector3(400.0, 150.0, 60.0)
const REGROW_C_ORIGIN := Vector3(400.0, 150.0, 120.0)
const REGROW_T_ORIGIN := Vector3(400.0, 150.0, 134.0)

const OVER_COL_PITCH := 0.75
const OVER_ROW_PITCH := 1.20
const CLOSE_PITCH := 0.70
const REGROW_PITCH := 0.70
const SIDE_PITCH := 0.80
const WALL_WIDTH := 16.0

# ---- 展台配色（与苗床土面同色系）----
const C_SOIL := Color("6b5340")
const C_SOIL_TOP := Color("7d6349")
const C_BACKDROP := Color("b3bab6")
const C_BACKDROP_LOW := Color("9aa29d")
const C_LABEL := Color("fffaf0")
const C_LABEL_OUTLINE := Color("221c16")

# ---- 光照 / 时间 ----
const TIME_OF_DAY_MIN := 12.0 * 60.0 + 20.0
const STAGE_OPTS := {"bands": 3.0, "soft": 0.45, "rim": 0.02}

var out_dir := DEFAULT_OUT
var _headless := false
var _main: Node = null
var _cam: Camera3D = null
var _sv: SubViewport = null
var _shot_cam: Camera3D = null
var _stage_root: Node3D = null
var _font: Font = null

var _over: Array = []
var _over_labels: Array = []
var _close: Array = []
var _close_labels: Array = []
var _regrow: Dictionary = {}
var _labels: Array = []

var _checks: Array = []
var _notes: Array = []
var _shots: Array = []
var _log_lines: Array = []
var _model_facts: Array = []


func _initialize() -> void:
    _headless = DisplayServer.get_name() == "headless"
    _parse_args()
    _run.call_deferred()


func _parse_args() -> void:
    for a in OS.get_cmdline_user_args():
        var s := String(a)
        if s.begins_with("--out="):
            out_dir = s.substr(6)
    out_dir = out_dir.replace("\\", "/")
    if out_dir.ends_with("/"):
        out_dir = out_dir.substr(0, out_dir.length() - 1)


# ---------------------------------------------------------------- 日志 / 检查

func _log(line: String) -> void:
    _log_lines.append(line)
    print(line)


func _check(key: String, group: String, ok: bool, expect: String, actual: String) -> bool:
    _checks.append({"key": key, "group": group, "ok": ok, "expect": expect, "actual": actual})
    if not ok:
        _log("[P3SHOTS] CHECK-FAIL %s [%s] expect=%s actual=%s" % [key, group, expect, actual])
    return ok


func _note(key: String, text: String) -> void:
    _notes.append({"key": key, "text": text})
    _log("[P3SHOTS] NOTE %s: %s" % [key, text])


# ---------------------------------------------------------------- 字体

func _load_font() -> Font:
    var f := FontFile.new()
    var bytes := FileAccess.get_file_as_bytes(FONT_RES)
    if bytes.size() > 0:
        f.data = bytes
        f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
        f.hinting = TextServer.HINTING_NORMAL
        _log("[P3SHOTS] font loaded %s (%d bytes)" % [FONT_RES, bytes.size()])
        return f
    _log("[P3SHOTS] font load FAILED %s, fallback ThemeDB" % FONT_RES)
    return ThemeDB.fallback_font


# ---------------------------------------------------------------- 主流程

func _run() -> void:
    _log("[P3SHOTS] start %s headless=%s out=%s" % [
        Time.get_datetime_string_from_system(), str(_headless), out_dir])
    if _headless:
        _log("[P3SHOTS] WARNING headless 模式无法从 SubViewport 取图；本次运行必然 FAIL。")

    var ps: PackedScene = load("res://isle.tscn")
    if ps == null:
        _check("scene_load", "B", false, "isle.tscn 可加载", "load 返回 null")
        _finish()
        return
    _main = ps.instantiate()
    root.add_child(_main)
    await process_frame
    await process_frame

    var S := load("res://scripts/isle_settings.gd")
    if S != null:
        _main.set("_settings", S.defaults())
        _main.call("_apply_user_settings", false)
    if not _headless:
        for i in range(3):
            await process_frame

    _main.set("_settings_save_delay", -1.0)
    _main.set("_mode", 1)          # Mode.PLAYING
    _main.set("_started", true)
    _main.set("_paused", false)
    _main.set("_blending", "")
    _main.set("_auto_orbit", false)
    _cam = _main.get("_cam") as Camera3D
    _check("camera_exists", "B", _cam != null, "main._cam 是 Camera3D", str(_cam))

    _suppress_ui()

    _main.call("_set_time_of_day", TIME_OF_DAY_MIN)
    var weather: Variant = _main.get("_weather")
    if weather != null and weather.has_method("set_manual_type"):
        weather.set_manual_type("clear")
        weather.set("_manual_blend", 1.0)
    _main.call("_update_weather", 0.0, true)
    for i in range(2):
        await process_frame

    _setup_viewport()
    for i in range(2):
        await process_frame

    _font = _load_font()
    _stage_root = Node3D.new()
    _stage_root.name = "P3CropShotsStage"
    root.add_child(_stage_root)
    _build_display()
    for i in range(3):
        await process_frame

    _run_model_checks()
    await _run_shots()
    _finish()


func _suppress_ui() -> void:
    if _main == null:
        return
    var menu: Variant = _main.get("_menu")
    if menu != null and menu.has_method("instant_finish"):
        menu.call("instant_finish")
    if menu != null:
        menu.set("menu_visible", false)
    _hide_layers(_main)
    _hide_layers(root)


func _hide_layers(nd: Node) -> void:
    if nd == null:
        return
    for ch in nd.get_children():
        if ch is CanvasLayer:
            (ch as CanvasLayer).visible = false
        elif ch is CanvasItem:
            (ch as CanvasItem).visible = false
        _hide_layers(ch)


func _setup_viewport() -> void:
    if _headless:
        return
    _sv = SubViewport.new()
    _sv.name = "P3ShotViewport"
    _sv.size = Vector2i(SHOT_W, SHOT_H)
    _sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    _sv.msaa_3d = Viewport.MSAA_2X
    root.add_child(_sv)
    _sv.world_3d = root.world_3d
    _shot_cam = Camera3D.new()
    _shot_cam.name = "P3ShotCamera"
    _shot_cam.near = 0.05
    _shot_cam.far = 1500.0
    _sv.add_child(_shot_cam)
    _shot_cam.current = true
    _check("viewport_ready", "B", _sv != null and _shot_cam != null,
        "SubViewport(1600x1000) + 独立 Camera3D 就绪", "size=%s" % str(_sv.size))


# ---------------------------------------------------------------- 展台搭建

func _build_bench(origin: Vector3, width: float, depth: float, tag: String) -> void:
    var plinth := M.box(_stage_root, Vector3(width, 1.70, depth),
        origin + Vector3(0.0, -1.22, 0.0), C_SOIL, 0.0, STAGE_OPTS)
    plinth.name = tag + "Plinth"
    var base := M.box(_stage_root, Vector3(width, 0.30, depth),
        origin + Vector3(0.0, -0.21, 0.0), C_SOIL, 0.0, STAGE_OPTS)
    base.name = tag + "Base"
    var deck := M.box(_stage_root, Vector3(width + 0.10, 0.06, depth + 0.10),
        origin + Vector3(0.0, -0.03, 0.0), C_SOIL_TOP, 0.0, STAGE_OPTS)
    deck.name = tag + "Deck"
    var wall_z: float = -(depth * 0.5 + 1.10)
    var wall := M.box(_stage_root, Vector3(WALL_WIDTH, 20.0, 0.20),
        origin + Vector3(0.0, 5.00, wall_z), C_BACKDROP, 0.0, STAGE_OPTS)
    wall.name = tag + "Backdrop"
    var skirt := M.box(_stage_root, Vector3(WALL_WIDTH, 6.0, 0.20),
        origin + Vector3(0.0, -2.90, wall_z), C_BACKDROP_LOW, 0.0, STAGE_OPTS)
    skirt.name = tag + "Skirt"


func _build_display() -> void:
    var crops: Array = CM.crop_ids()
    _build_bench(OVER_ORIGIN, 5.0, 3.9, "Overview")
    for i in range(crops.size()):
        var col: Array = []
        var colb: Array = []
        for j in range(STAGES.size()):
            var crop := String(crops[i])
            var stage := String(STAGES[j])
            var mi := _add_plant(crop, stage, _over_pos(i, j), "Over_%s_%s" % [crop, stage])
            col.append(mi)
            var lb := _add_label("", "over", 0.0011)
            var extra: float = [0.14, 0.14, 0.24][j]
            _set_plant_label(lb, mi, "%s\n%s" % [CROP_CN[crop], STAGE_CN[stage]], extra)
            colb.append(lb)
        _over.append(col)
        _over_labels.append(colb)

    _build_bench(CLOSE_ORIGIN, 4.8, 1.9, "Closeup")
    for i in range(crops.size()):
        var trio: Array = []
        var triob: Array = []
        for j in range(STAGES.size()):
            var crop := String(crops[i])
            var stage := String(STAGES[j])
            var mi := _add_plant(crop, stage, Vector3(0.0, -999.0, 0.0),
                "Close_%s_%s" % [crop, stage])
            mi.visible = false
            trio.append(mi)
            var lb := _add_label("", "close", 0.0017)
            lb.position = Vector3(0.0, -999.0, 0.0)
            lb.visible = false
            triob.append(lb)
        _close.append(trio)
        _close_labels.append(triob)

    _build_regrow_bench(REGROW_C_ORIGIN, "RegrowCorn", "corn")
    _build_regrow_bench(REGROW_T_ORIGIN, "RegrowTomato", "tomato")
    _log("[P3SHOTS] display built: benches at %s / %s / %s / %s" % [
        str(OVER_ORIGIN), str(CLOSE_ORIGIN), str(REGROW_C_ORIGIN), str(REGROW_T_ORIGIN)])


func _build_regrow_bench(origin: Vector3, tag: String, crop: String) -> void:
    _build_bench(origin, 3.4, 1.7, tag)
    var models: Array = []
    var labels: Array = []
    var mid_stage: String = String(CM.display_stage("growing", true))
    var stage_ids := ["mature", mid_stage, "mature"]
    var texts := ["成熟\n(本轮)", "再生期\n(growing)", "成熟\n(下一轮)"]
    var group := "regrow_" + crop
    for k in range(3):
        var mi := _add_plant(crop, String(stage_ids[k]),
            origin + Vector3((float(k) - 1.0) * REGROW_PITCH, 0.002, 0.0),
            "%s_%s_%d" % [tag, crop, k])
        models.append(mi)
        var lb := _add_label("", group, 0.0015)
        _set_plant_label(lb, mi, String(texts[k]), 0.10)
        labels.append(lb)
    _regrow[crop] = {"origin": origin, "models": models, "labels": labels,
        "mid_stage": mid_stage, "stage_ids": stage_ids, "group": group}


func _add_plant(crop: String, stage: String, pos: Vector3, nm: String) -> MeshInstance3D:
    var mi: MeshInstance3D = CM.make_instance(crop, stage)
    mi.name = nm
    mi.position = pos
    _stage_root.add_child(mi)
    return mi


func _add_label(text: String, group: String, pixel_size: float) -> Label3D:
    var lb := Label3D.new()
    lb.name = "CropLabel"
    lb.font = _font
    lb.font_size = 64
    lb.pixel_size = pixel_size
    lb.text = text
    lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    lb.no_depth_test = true
    lb.modulate = C_LABEL
    lb.outline_modulate = C_LABEL_OUTLINE
    lb.outline_size = 1
    lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    lb.render_priority = 10
    lb.alpha_cut = Label3D.ALPHA_CUT_DISCARD
    lb.set_meta("label_group", group)
    _labels.append(lb)
    _stage_root.add_child(lb)
    return lb


func _set_plant_label(lb: Label3D, mi: MeshInstance3D, text: String, extra: float) -> void:
    lb.text = text
    var crop := str(mi.get_meta("crop_id"))
    var stage := str(mi.get_meta("stage_id"))
    var b: AABB = CM.bounds_of(crop, stage)
    var top: float = maxf(b.end.y, 0.08)
    lb.position = mi.position + Vector3(0.0, top + extra, 0.0)
    lb.visible = mi.visible


# ---------------------------------------------------------------- 布局 / 机位

func _over_pos(i: int, j: int) -> Vector3:
    return OVER_ORIGIN + Vector3((float(i) - 2.0) * OVER_COL_PITCH, 0.002,
        (1.0 - float(j)) * OVER_ROW_PITCH)


func _close_cam(crop: String) -> Dictionary:
    match crop:
        "wheat":
            return {"pitch": 0.70, "from": Vector3(0.0, 0.96, 2.05),
                "target": Vector3(0.0, 0.42, 0.0), "fov": 43.0}
        "corn":
            return {"pitch": 0.70, "from": Vector3(0.0, 1.28, 2.35),
                "target": Vector3(0.0, 0.58, 0.0), "fov": 43.0}
        "watermelon":
            return {"pitch": 0.90, "from": Vector3(0.0, 0.72, 2.90),
                "target": Vector3(0.0, 0.16, 0.0), "fov": 40.0}
        "tomato":
            return {"pitch": 0.70, "from": Vector3(0.0, 1.00, 1.75),
                "target": Vector3(0.0, 0.42, 0.0), "fov": 43.0}
        "kale":
            return {"pitch": 0.62, "from": Vector3(0.0, 1.30, 1.95),
                "target": Vector3(0.0, 0.06, 0.0), "fov": 40.0}
    return {"pitch": 0.70, "from": Vector3(0.0, 1.00, 2.05),
        "target": Vector3(0.0, 0.45, 0.0), "fov": 43.0}


func _layout_close(i: int) -> void:
    var crops: Array = CM.crop_ids()
    var cfg := _close_cam(String(crops[i]))
    var pitch: float = float(cfg["pitch"])
    for k in range(_close.size()):
        for j in range(STAGES.size()):
            var mi: MeshInstance3D = _close[k][j]
            var lb: Label3D = _close_labels[k][j]
            if k == i:
                mi.visible = true
                mi.position = CLOSE_ORIGIN + Vector3((float(j) - 1.0) * pitch, 0.002, 0.0)
                _set_plant_label(lb, mi, String(STAGE_CN[String(STAGES[j])]), 0.16)
                lb.visible = true
            else:
                mi.visible = false
                lb.visible = false


func _layout_side() -> void:
    var crops: Array = CM.crop_ids()
    for i in range(crops.size()):
        for j in range(STAGES.size()):
            var mi: MeshInstance3D = _close[i][j]
            var lb: Label3D = _close_labels[i][j]
            if j == 2:
                mi.visible = true
                mi.position = CLOSE_ORIGIN + Vector3((float(i) - 2.0) * SIDE_PITCH, 0.002, -0.15)
                lb.text = String(CROP_CN[String(crops[i])])
                var b: AABB = CM.bounds_of(String(crops[i]), "mature")
                lb.position = mi.position + Vector3(0.0, maxf(b.end.y, 0.10) + 0.10, 0.0)
                lb.visible = true
            else:
                mi.visible = false
                lb.visible = false


# ---------------------------------------------------------------- 模型合同检查

func _run_model_checks() -> void:
    var crops: Array = CM.crop_ids()
    _check("crop_ids", "A", crops.size() == 5 and String(crops[0]) == "wheat"
        and String(crops[4]) == "kale", "crop_ids = [wheat,corn,watermelon,tomato,kale]", str(crops))

    var m1: ShaderMaterial = CM.material()
    var m2: ShaderMaterial = CM.material()
    _check("material_shared", "A", m1 != null and m1 == m2,
        "material() 全局唯一共享", "same=%s" % str(m1 == m2))

    var dm := String(CM.display_stage("mature", true))
    var dg := String(CM.display_stage("growing", true))
    var ds := String(CM.display_stage("seedling", true))
    var ds0 := String(CM.display_stage("seedling", false))
    _check("regrow_mapping", "A", dm == "mature" and dg == "growing" and ds == "growing"
        and ds0 == "seedling",
        "display_stage 再生期: mature->mature, growing->growing, seedling->growing（不缩回幼苗）",
        "mature=%s growing=%s seedling_regrow=%s seedling_norm=%s" % [dm, dg, ds, ds0])

    var all_ok := true
    for crop in crops:
        for stage in STAGES:
            var b: AABB = CM.bounds_of(String(crop), String(stage))
            var tris: int = CM.triangle_count(String(crop), String(stage))
            var h: float = b.end.y - b.position.y
            var ok: bool = tris > 0 and b.size.x > 0.02 and b.size.z > 0.02 and h > 0.02
            if not ok:
                all_ok = false
            _model_facts.append({
                "crop": String(crop), "stage": String(stage), "tris": tris,
                "height": snappedf(h, 0.001), "width": snappedf(b.size.x, 0.001),
                "depth": snappedf(b.size.z, 0.001), "aabb_y0": snappedf(b.position.y, 0.001),
            })
            _log("[P3SHOTS] MODEL %s/%s tris=%d h=%.3f w=%.3f d=%.3f y0=%.3f" % [
                String(crop), String(stage), tris, h, b.size.x, b.size.z, b.position.y])
    _check("models_non_degenerate", "A", all_ok,
        "15 个模型包围盒有效（tris>0 且 w/d/h>0.02）", "facts=%d" % _model_facts.size())

    for crop in ["corn", "tomato"]:
        var bs: AABB = CM.bounds_of(String(crop), "seedling")
        var bg: AABB = CM.bounds_of(String(crop), "growing")
        var bm: AABB = CM.bounds_of(String(crop), "mature")
        _note("regrow_heights_%s" % String(crop),
            "seedling=%.3fm growing=%.3fm mature=%.3fm -> 再生期显示 growing 体量 %.3fm" % [
                bs.end.y - bs.position.y, bg.end.y - bg.position.y,
                bm.end.y - bm.position.y, bg.end.y - bg.position.y])
    _note("model_module_sha256", String(FileAccess.get_sha256("res://scripts/isle_crop_models.gd")))
    var hparts: Array = []
    for f in _model_facts:
        if String(f["stage"]) == "mature":
            hparts.append("%s=%.3f" % [String(f["crop"]), float(f["height"])])
    _note("height_table", "mature 高度表(m): " + ", ".join(hparts))


# ---------------------------------------------------------------- 截图

func _flatten(grid: Array) -> Array:
    var out: Array = []
    for row in grid:
        for mi in row:
            out.append(mi)
    return out


func _expect_of(models: Array) -> Array:
    var out: Array = []
    for nd in models:
        if nd == null:
            continue
        out.append({"node": nd, "name": str((nd as Node).name)})
    return out


func _run_shots() -> void:
    if _headless:
        _check("window_mode", "B", false,
            "真实窗口渲染（不能 --headless，否则 SubViewport 无法出图）", "headless")
        return
    if _sv == null or _shot_cam == null:
        _check("viewport_ready", "B", false, "SubViewport 就绪", "_sv/_shot_cam 为 null")
        return

    await _shot("01_models_overview.png",
        OVER_ORIGIN + Vector3(0.0, 1.50, 4.50),
        OVER_ORIGIN + Vector3(0.0, 0.70, 0.0), 38.0,
        _expect_of(_flatten(_over)), "over")

    var crops: Array = CM.crop_ids()
    var close_tags := [
        "02_wheat_closeup.png", "03_corn_closeup.png", "04_watermelon_closeup.png",
        "05_tomato_closeup.png", "06_kale_closeup.png",
    ]
    for i in range(crops.size()):
        _layout_close(i)
        await process_frame
        var cfg := _close_cam(String(crops[i]))
        var trio: Array = [_close[i][0], _close[i][1], _close[i][2]]
        await _shot(String(close_tags[i]),
            CLOSE_ORIGIN + (cfg["from"] as Vector3),
            CLOSE_ORIGIN + (cfg["target"] as Vector3), float(cfg["fov"]),
            _expect_of(trio), "close")

    var regrow_cams := {
        "corn": {"tags": "07_corn_regrow.png", "from": Vector3(0.0, 1.35, 2.55),
            "target": Vector3(0.0, 0.58, 0.0), "fov": 42.0},
        "tomato": {"tags": "08_tomato_regrow.png", "from": Vector3(0.0, 0.98, 2.15),
            "target": Vector3(0.0, 0.36, 0.0), "fov": 42.0},
    }
    for crop in ["corn", "tomato"]:
        var info: Dictionary = _regrow[crop]
        var origin: Vector3 = info["origin"]
        var rc: Dictionary = regrow_cams[crop]
        for lb in info["labels"]:
            (lb as Label3D).visible = true
        await _shot(String(rc["tags"]),
            origin + (rc["from"] as Vector3),
            origin + (rc["target"] as Vector3), float(rc["fov"]),
            _expect_of(info["models"]), String(info["group"]))

    _layout_side()
    await process_frame
    var side: Array = []
    for i in range(crops.size()):
        side.append(_close[i][2])
    await _shot("09_side_profiles.png",
        CLOSE_ORIGIN + Vector3(0.55, 0.40, 3.30),
        CLOSE_ORIGIN + Vector3(0.0, 0.46, -0.10), 45.0,
        _expect_of(side), "close")


func _shot(tag: String, cam_from: Vector3, cam_target: Vector3, fov: float,
        expect: Array, label_group: String) -> void:
    _suppress_ui()
    for lb in _labels:
        if str(lb.get_meta("label_group", "")) != label_group:
            lb.visible = false
    _main.call("_pose_look", cam_from, cam_target, fov)
    for i in range(2):
        await process_frame

    _shot_cam.global_transform = _cam.global_transform
    _shot_cam.fov = float(fov)
    for i in range(2):
        await process_frame
    await RenderingServer.frame_post_draw

    var img := _grab()
    if img == null:
        _check("shot_" + tag, "B", false, "SubViewport 取图成功", "get_image() 返回 null")
        _log("SHOT %s FAILED: null image" % tag)
        return

    var spread := _image_spread(img)
    if spread < 0.02:
        _log("[P3SHOTS] blank detected on %s spread=%.4f, retry" % [tag, spread])
        for i in range(8):
            await process_frame
        await create_timer(0.12).timeout
        await RenderingServer.frame_post_draw
        var img2 := _grab()
        if img2 != null:
            img = img2
            spread = _image_spread(img)

    var iw := img.get_width()
    var ih := img.get_height()
    var size_ok: bool = iw == SHOT_W and ih == SHOT_H
    var framed := _check_framing(tag, expect)
    var green := _green_ratio(img)
    var path := out_dir + "/" + tag
    DirAccess.make_dir_recursive_absolute(out_dir)
    var err := img.save_png(path)
    _log("SHOT %s %dx%d err=%d -> %s" % [tag, iw, ih, err, path])

    _check("blank_" + tag, "B", spread >= 0.02,
        "非空白（luma spread >= 0.02）", "spread=%.4f" % spread)
    _check("size_" + tag, "B", size_ok, "1600x1000", "%dx%d" % [iw, ih])
    _check("save_" + tag, "B", err == OK, "save_png err=0", "err=%d" % err)
    _note("stats_" + tag, "luma_spread=%.3f green_ratio=%.3f framed=%s" % [
        spread, green, str(framed)])
    _shots.append({
        "tag": tag, "path": path, "width": iw, "height": ih, "save_err": err,
        "luma_spread": snappedf(spread, 0.0001), "green_ratio": snappedf(green, 0.0001),
        "camera_from": [cam_from.x, cam_from.y, cam_from.z],
        "camera_target": [cam_target.x, cam_target.y, cam_target.z],
        "fov": fov, "framed_ok": framed,
    })


func _check_framing(tag: String, expect: Array) -> bool:
    var bad: Array = []
    for e in expect:
        var mi := e["node"] as MeshInstance3D
        if mi == null or not mi.is_visible_in_tree():
            bad.append("%s:missing" % String(e["name"]))
            continue
        var crop := str(mi.get_meta("crop_id"))
        var stage := str(mi.get_meta("stage_id"))
        var b: AABB = CM.bounds_of(crop, stage)
        var base_w: Vector3 = mi.global_position
        var h: float = maxf(b.end.y, 0.10)
        var pts := [base_w, base_w + Vector3(0.0, h * 0.5, 0.0), base_w + Vector3(0.0, h, 0.0)]
        var inside := false
        for wp in pts:
            var sp := _shot_cam.unproject_position(wp)
            if sp.x >= 10.0 and sp.x <= float(SHOT_W) - 10.0 \
                    and sp.y >= 8.0 and sp.y <= float(SHOT_H) - 8.0:
                inside = true
                break
        if not inside:
            bad.append(String(e["name"]))
    return _check("framed_" + tag, "B", bad.is_empty(),
        "所有主体在画面内", "out=%s" % str(bad))


func _grab() -> Image:
    if _sv == null:
        return null
    var tex := _sv.get_texture()
    if tex == null:
        return null
    return tex.get_image()


func _image_spread(img: Image) -> float:
    var w := img.get_width()
    var h := img.get_height()
    if w <= 2 or h <= 2:
        return 0.0
    var step: int = maxi(1, w / 48)
    var lo := 9.0
    var hi := -9.0
    var y := 0
    while y < h:
        var x := 0
        while x < w:
            var c := img.get_pixel(x, y)
            var luma := 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
            lo = minf(lo, luma)
            hi = maxf(hi, luma)
            x += step
        y += step
    return hi - lo


func _green_ratio(img: Image) -> float:
    var w := img.get_width()
    var h := img.get_height()
    if w <= 4 or h <= 4:
        return 0.0
    var step: int = maxi(2, w / 200)
    var total := 0
    var green := 0
    var y := 0
    while y < h:
        var x := 0
        while x < w:
            var c := img.get_pixel(x, y)
            total += 1
            if c.g > c.r + 0.02 and c.g > c.b + 0.02:
                green += 1
            x += step
        y += step
    if total == 0:
        return 0.0
    return float(green) / float(total)


# ---------------------------------------------------------------- 收尾

func _finish() -> void:
    var fail := 0
    for c in _checks:
        if not bool(c["ok"]):
            fail += 1
    var pass_n: int = _checks.size() - fail
    var result := "PASS" if fail == 0 else "FAIL"
    _log("[P3SHOTS] SUMMARY checks=%d pass=%d fail=%d shots=%d notes=%d" % [
        _checks.size(), pass_n, fail, _shots.size(), _notes.size()])
    for c in _checks:
        if not bool(c["ok"]):
            _log("[P3SHOTS] FAILED-CHECK %s [%s] expect=%s actual=%s" % [
                String(c["key"]), String(c["group"]), String(c["expect"]), String(c["actual"])])
    for s in _shots:
        _log("[P3SHOTS] SHOT-SUMMARY %s %dx%d err=%d spread=%.3f -> %s" % [
            String(s["tag"]), int(s["width"]), int(s["height"]), int(s["save_err"]),
            float(s["luma_spread"]), String(s["path"])])

    DirAccess.make_dir_recursive_absolute(out_dir)
    var doc := {
        "probe": "tools/probe_p9_crop_shots.gd",
        "generated_at": Time.get_datetime_string_from_system(),
        "engine": Engine.get_version_info(),
        "headless": _headless,
        "shot_size": [SHOT_W, SHOT_H],
        "out_dir": out_dir,
        "result": result,
        "checks": _checks,
        "notes": _notes,
        "shots": _shots,
        "models": _model_facts,
        "layout": {
            "over_origin": [OVER_ORIGIN.x, OVER_ORIGIN.y, OVER_ORIGIN.z],
            "close_origin": [CLOSE_ORIGIN.x, CLOSE_ORIGIN.y, CLOSE_ORIGIN.z],
            "regrow_corn_origin": [REGROW_C_ORIGIN.x, REGROW_C_ORIGIN.y, REGROW_C_ORIGIN.z],
            "regrow_tomato_origin": [REGROW_T_ORIGIN.x, REGROW_T_ORIGIN.y, REGROW_T_ORIGIN.z],
            "over_col_pitch": OVER_COL_PITCH, "over_row_pitch": OVER_ROW_PITCH,
            "close_pitch": CLOSE_PITCH, "regrow_pitch": REGROW_PITCH,
            "side_pitch": SIDE_PITCH,
        },
    }
    var jf := FileAccess.open(out_dir + "/p3_crop_shots.json", FileAccess.WRITE)
    if jf != null:
        jf.store_string(JSON.stringify(doc, "\t"))
        jf.close()
    var lf := FileAccess.open(out_dir + "/p3_crop_shots.log", FileAccess.WRITE)
    if lf != null:
        for line in _log_lines:
            lf.store_line(String(line))
        lf.close()

    print("[P3SHOTS] SUMMARY checks=%d pass=%d fail=%d shots=%d" % [
        _checks.size(), pass_n, fail, _shots.size()])
    print("[RESULT] %s" % result)
    quit(0 if fail == 0 else 1)