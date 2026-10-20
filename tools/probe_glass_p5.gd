extends SceneTree
## P5 玻璃模块探针（glass 模块自测，不依赖 godot-ai MCP / 编辑器会话）。
## headless（静态校验，契约要求的常规跑法）：
##   <console exe> --headless --path D:/休闲小岛幻境/游戏工程 --script res://tools/probe_glass_p5.gd
## 窗口（额外渲染一帧，证明 shader 在真实 Forward+ 管线下编译并可透射）：
##   <console exe> --path D:/休闲小岛幻境/游戏工程 --resolution 960x600 --script res://tools/probe_glass_p5.gd --render-check
## 输出：[GLASS] PASS/FAIL ...，最后 [GLASS] RESULT=PASS failures=0；渲染图 logs/probe_glass_p5_render.png

const M := preload("res://scripts/isle_math.gd")
const SHADER_PATH := "res://shaders/glass.gdshader"
const RENDER_OUT := "D:/休闲小岛幻境/开发产物/logs/probe_glass_p5_render.png"

var _checks := 0
var _fails := 0
var _lines: Array = []

func _initialize() -> void:
	Run()

func Run() -> void:
	_check_shader_source()
	_check_shader_uniforms()
	_check_material()
	_check_globals_registered_in_main()
	_check_consumers()
	var want_render := OS.get_cmdline_user_args().has("--render-check") or OS.get_cmdline_args().has("--render-check")
	if DisplayServer.get_name() != "headless" and want_render:
		await _check_render()
	_finish()

func _ok(cond: bool, name: String, detail: String = "") -> void:
	_checks += 1
	if cond:
		_lines.append("[GLASS] PASS " + name + (" " + detail if detail != "" else ""))
	else:
		_fails += 1
		_lines.append("[GLASS] FAIL " + name + (" " + detail if detail != "" else ""))
	print(_lines[-1])

func _shader_text() -> String:
	var sh: Shader = load(SHADER_PATH)
	if sh == null:
		return ""
	return sh.code

# ---- 1. shader 源码契约：透明排序 / 单面 / 屏幕折射 / 淡出 ----
func _check_shader_source() -> void:
	var src := _shader_text()
	_ok(src != "", "shader_loads", SHADER_PATH)
	_ok(src.contains("depth_draw_never"), "render_mode_depth_draw_never")
	_ok(src.contains("cull_back"), "render_mode_cull_back")
	_ok(not src.contains("cull_disabled"), "no_cull_disabled")
	_ok(src.contains("hint_screen_texture"), "screen_texture_hint")
	_ok(src.contains("INV_VIEW_MATRIX"), "world_normal_via_inv_view")
	_ok(src.contains("g_sun_dir_view"), "sun_dir_global_used")
	_ok(src.contains("fade_alpha"), "fade_alpha_declared")
	_ok(src.contains("screen_dither(FRAGCOORD.xy) > fade_alpha"), "fade_alpha_dither_discard")

# ---- 2. shader uniform 表：命名与参数范围 ----
func _check_shader_uniforms() -> void:
	var sh: Shader = load(SHADER_PATH)
	_ok(sh != null, "shader_resource")
	var names: Array = []
	for u in sh.get_shader_uniform_list():
		names.append(String(u["name"]))
	# 注：hint_screen_texture 的 sampler 由引擎作为内置纹理提供，不出现在 get_shader_uniform_list()，
	# 因此 screen_tex 只查源码声明（见 _check_shader_source 的 screen_texture_hint）。
	var required := ["tint", "opacity", "glow", "glow_col", "surface_rough", "tint_strength",
		"fresnel_f0", "fresnel_power", "reflection_gain", "sun_spec_gain", "sun_shininess",
		"refract_strength", "refract_weight", "front_sheen", "glow_gain", "fade_alpha"]
	for n in required:
		_ok(names.has(n), "uniform_" + n)
	# 参数范围（从 shader 源码的 hint_range 与默认值取证）
	var src := _shader_text()
	_ok(src.contains("uniform float refract_strength : hint_range(0.0, 0.01)"), "refract_strength_max_0.01")
	_ok(src.contains("uniform float fresnel_f0 : hint_range(0.0, 0.25)"), "fresnel_f0_range_ok")
	_ok(src.contains("uniform float fade_alpha = 1.0"), "fade_alpha_default_1")

# ---- 3. 材质工厂：isle_math.glass_material 参数与渲染优先级 ----
func _check_material() -> void:
	var m: ShaderMaterial = M.glass_material(0.30)
	_ok(m != null, "material_created")
	_ok(m.shader != null and m.shader.resource_path == SHADER_PATH, "material_shader_path")
	var op := float(m.get_shader_parameter("opacity"))
	_ok(op <= 0.20, "material_opacity_le_0.20", "opacity=%.3f" % op)
	var rs := float(m.get_shader_parameter("refract_strength"))
	_ok(rs >= 0.0 and rs <= 0.01, "material_refract_within_0.01", "refract_strength=%.4f" % rs)
	var f0 := float(m.get_shader_parameter("fresnel_f0"))
	_ok(f0 >= 0.0 and f0 <= 0.10, "material_fresnel_f0_le_0.10", "fresnel_f0=%.3f" % f0)
	_ok(m.render_priority >= 1, "material_render_priority", "priority=%d" % m.render_priority)
	var glow := float(m.get_shader_parameter("glow"))
	_ok(abs(glow - 0.30) < 0.001, "material_glow_param_compat", "glow=%.3f" % glow)
	_ok(m.get_shader_parameter("front_sheen") != null, "material_front_sheen_set")
	_ok(m.get_shader_parameter("glow_gain") != null, "material_glow_gain_set")
	# 两处复用点（灯室/船窗）都通过同一工厂：签名保持
	var m2: ShaderMaterial = M.glass_material()
	_ok(float(m2.get_shader_parameter("glow")) == 0.0, "material_default_glow_zero")

# ---- 4. main.gd 已注册本 shader 依赖的 global uniform（不能依赖 Lead 改接口） ----
func _check_globals_registered_in_main() -> void:
	var f := FileAccess.open("res://scripts/main.gd", FileAccess.READ)
	if f == null:
		_ok(false, "main_gd_readable")
		return
	var txt := f.get_as_text()
	var globals := ["g_sun_color", "g_sun_dir_view", "g_ambient_sky", "g_ambient_ground",
		"g_fog_color", "g_fog_near", "g_fog_far"]
	for gname in globals:
		_ok(txt.contains(gname), "main_registers_" + gname)

# ---- 5. 消费点：world.gd 灯室/船窗、cottage.gd 窗户都使用 M.glass_material ----
func _check_consumers() -> void:
	var world_txt := _read("res://scripts/world.gd")
	var cottage_txt := _read("res://scripts/cottage.gd")
	var math_txt := _read("res://scripts/isle_math.gd")
	_ok(world_txt.contains("M.glass_material("), "world_uses_glass_material")
	_ok(cottage_txt.contains("M.glass_material("), "cottage_uses_glass_material")
	_ok(math_txt.contains("static func glass_material(glow_val: float = 0.0) -> ShaderMaterial:"),
		"glass_material_signature_unchanged")

func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()

# ---- 6. 窗口渲染自检：玻璃板后面放高饱和红块，截图中心应偏红（透射成立），
#         且 shader 若编译失败窗口日志会出现 SHADER ERROR（由运行者 grep 取证）。 ----
func _check_render() -> void:
	var root3d := Node3D.new()
	get_root().add_child(root3d)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.07, 0.10)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	root3d.add_child(we)
	# 背景红板（不透明，位于玻璃之后）
	var bg := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(3.0, 3.0, 0.1)
	bg.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.albedo_color = Color(0.85, 0.10, 0.08)
	bg.material_override = bmat
	bg.position = Vector3(0.0, 0.0, -1.2)
	root3d.add_child(bg)
	# 玻璃板
	var pane := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(2.4, 2.4, 0.02)
	pane.mesh = pm
	var gm: ShaderMaterial = M.glass_material(0.10)
	pane.material_override = gm
	root3d.add_child(pane)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 0.0, 2.2)
	cam.fov = 45.0
	root3d.add_child(cam)
	cam.current = true
	_ensure_globals()
	RenderingServer.global_shader_parameter_set("g_ambient_sky", Color(0.30, 0.42, 0.60))
	RenderingServer.global_shader_parameter_set("g_ambient_ground", Color(0.12, 0.13, 0.10))
	RenderingServer.global_shader_parameter_set("g_sun_color", Color(1.4, 1.3, 1.1))
	RenderingServer.global_shader_parameter_set("g_sun_dir_view", Vector3(0.2, 0.5, 0.8))
	RenderingServer.global_shader_parameter_set("g_fog_color", Color(0.5, 0.6, 0.7))
	RenderingServer.global_shader_parameter_set("g_fog_near", 100.0)
	RenderingServer.global_shader_parameter_set("g_fog_far", 400.0)
	for i in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var err := img.save_png(RENDER_OUT)
	var c := img.get_pixel(img.get_width() / 2, img.get_height() / 2)
	var red_ok := c.r > 0.18 and c.r > c.g * 1.5
	_ok(err == OK, "render_save_png", RENDER_OUT)
	_ok(red_ok, "render_glass_transmits_bg", "center=(%.3f,%.3f,%.3f)" % [c.r, c.g, c.b])

func _ensure_globals() -> void:
	var have: Array = RenderingServer.global_shader_parameter_get_list()
	var defs := [
		["g_sun_color", RenderingServer.GLOBAL_VAR_TYPE_COLOR],
		["g_sun_dir_view", RenderingServer.GLOBAL_VAR_TYPE_VEC3],
		["g_ambient_sky", RenderingServer.GLOBAL_VAR_TYPE_COLOR],
		["g_ambient_ground", RenderingServer.GLOBAL_VAR_TYPE_COLOR],
		["g_fog_color", RenderingServer.GLOBAL_VAR_TYPE_COLOR],
		["g_fog_near", RenderingServer.GLOBAL_VAR_TYPE_FLOAT],
		["g_fog_far", RenderingServer.GLOBAL_VAR_TYPE_FLOAT],
	]
	for d in defs:
		if not have.has(StringName(d[0])):
			var v: Variant = Color.WHITE
			if int(d[1]) == RenderingServer.GLOBAL_VAR_TYPE_FLOAT:
				v = 0.0
			elif int(d[1]) == RenderingServer.GLOBAL_VAR_TYPE_VEC3:
				v = Vector3.ZERO
			RenderingServer.global_shader_parameter_add(d[0], int(d[1]), v)

func _finish() -> void:
	print("[GLASS] checks=%d failures=%d" % [_checks, _fails])
	print("[GLASS] RESULT=" + ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)
