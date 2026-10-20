extends SceneTree
## T1 五档画质同机位对比截图（GUI 非 headless，窗口锁内运行）。
## 运行：console exe --path 项目 --script res://tools/probe_quality_shots_t1.gd
## 输出：D:/休闲小岛幻境/开发产物/shots6/t1/quality_{0..4}_*.png（画面上叠加档位名）

const OUT_DIR := "D:/休闲小岛幻境/开发产物/shots6/t1"
const NAMES := ["低 · 流畅", "中 · 均衡", "高 · 精致", "极高 · 细腻", "极致 · 电影"]
const FILES := ["quality_0_low.png", "quality_1_medium.png", "quality_2_high.png", "quality_3_ultra.png", "quality_4_cinematic.png"]

var _main: Node = null
var _lbl: Label = null
var _sub: Label = null

func _initialize() -> void:
    DirAccess.make_dir_recursive_absolute(OUT_DIR)
    print("=== probe_quality_shots_t1 start ===")
    change_scene_to_file("res://isle.tscn")
    await process_frame
    for i in 300:
        _main = current_scene
        if _main != null and _main.get("_cam") != null and _main.get("_menu") != null and _main.get("_hud") != null:
            break
        await process_frame
    if _main == null:
        print("FATAL no main scene")
        quit(1)
        return
    print("scene ready, wait settle")
    await create_timer(2.0).timeout
    # 清掉标题菜单 / HUD，进入 PLAYING 态让相机使用 _play_pose
    var menu = _main.get("_menu")
    if menu != null and menu.has_method("instant_finish"):
        menu.instant_finish()
    _main.call("_enter_playing")
    # _enter_playing 会用 0.45s tween 把 HUD 淡入；必须等它结束再隐藏，否则旧的淡入 tween 会把 alpha 拉回 1
    await create_timer(0.7).timeout
    var hud = _main.get("_hud")
    if hud != null:
        hud.set_hud_visible(false, false)
        hud.visible = false
    _main.set("_auto_orbit", false)
    _main.set("_paused", true)  # 冻结模拟时间（sim 源），五档光照完全一致
    # 固定机位（原菜单电影机位）
    var target := Vector3(0.0, 4.2, 0.0)
    var theta := 0.30
    var elev := 0.50
    var r := 106.0
    var from: Vector3 = target + Vector3(r * cos(elev) * sin(theta), r * sin(elev), r * cos(elev) * cos(theta))
    _main.call("_pose_look", from, target, 36.0)
    _build_overlay()
    for q in 5:
        var s: Dictionary = _main.get("_settings")
        s["quality"] = q
        s["quality_overrides"] = {}
        _main.set("_settings", s)
        _main.call("_apply_quality", q)
        _main.call("_pose_look", from, target, 36.0)
        await create_timer(0.9).timeout
        _lbl.text = "画质 %d / 5 · %s" % [q + 1, NAMES[q]]
        _sub.text = "同一机位 · 时间冻结 17:18 · HUD 关闭 · 差异：MSAA/AA、3D 缩放、海面细节、草量、粒子、AO/体积雾/泛光"
        await process_frame
        await RenderingServer.frame_post_draw
        var img: Image = root.get_texture().get_image()
        var path: String = OUT_DIR + "/" + String(FILES[q])
        var err: int = img.save_png(path)
        print("SAVED %s err=%d size=%dx%d" % [path, err, img.get_width(), img.get_height()])
    print("=== probe_quality_shots_t1 done ===")
    quit(0)

func _build_overlay() -> void:
    var layer := CanvasLayer.new()
    layer.layer = 120
    root.add_child(layer)
    _lbl = Label.new()
    _lbl.position = Vector2(64.0, 40.0)
    _apply_font(_lbl, 40)
    _lbl.add_theme_color_override("font_color", Color("f4ead8"))
    _lbl.add_theme_constant_override("outline_size", 10)
    _lbl.add_theme_color_override("font_outline_color", Color("0b0e14"))
    layer.add_child(_lbl)
    _sub = Label.new()
    _sub.position = Vector2(66.0, 96.0)
    _apply_font(_sub, 18)
    _sub.add_theme_color_override("font_color", Color("c5b9a2"))
    _sub.add_theme_constant_override("outline_size", 6)
    _sub.add_theme_color_override("font_outline_color", Color("0b0e14"))
    layer.add_child(_sub)

func _apply_font(l: Label, size_px: int) -> void:
    if ResourceLoader.exists("res://fonts/simhei.ttf"):
        var f = load("res://fonts/simhei.ttf")
        if f != null:
            l.add_theme_font_override("font", f)
    l.add_theme_font_size_override("font_size", size_px)