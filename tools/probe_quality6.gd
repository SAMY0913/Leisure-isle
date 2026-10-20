extends SceneTree
## P6 五档画质探针。
## headless 模式：校验 isle_quality.gd 五档契约（24 键/类型/区间/档间差异/映射/设置桥接）、
##                sea/sky/post_ao 着色器静态接口。
## 窗口模式（-- --window --out=DIR）：实例化 isle.tscn，同机位/同时刻拍 q0..q4 与水面近景，
##                记录每档 MSAA/SSAA/海网格细分/绘制统计/FPS；并挂载 post_ao QuadMesh 做
##                AO 开/关 + depth 约定 A/B 的像素级对比（验证 AO 真实生效）。
## 用法：
##   headless: console.exe --headless --path D:/休闲小岛幻境/游戏工程 --script res://tools/probe_quality6.gd
##   window:   console.exe --path D:/休闲小岛幻境/游戏工程 --script res://tools/probe_quality6.gd -- --window --out=D:/休闲小岛幻境/开发产物/shots6/t3

const IQ_PATH := "res://scripts/isle_quality.gd"
const SETTINGS_PATH := "res://scripts/isle_settings.gd"
const SEA_SHADER := "res://shaders/sea.gdshader"
const SKY_SHADER := "res://shaders/sky.gdshader"
const POST_AO := "res://shaders/post_ao.gdshader"
const MAIN_SCENE := "res://isle.tscn"
const DEFAULT_OUT := "D:/休闲小岛幻境/开发产物/shots6/t3"

const CONTRACT_KEYS := [
	"msaa_3d", "msaa_2d", "screen_space_aa", "taa", "scaling_3d_scale", "scaling_3d_mode",
	"max_fps", "sky_cloud_detail", "sea_wave_detail", "sea_foam", "sea_reflection", "sea_ssr",
	"sea_mesh_scale", "grass_density", "particle_density", "light_budget", "glow_strength",
	"tonemap", "exposure", "posts_ao", "ao_strength", "volumetric_fog", "fog_scale", "lod_bias",
]
const QUALITY_NAMES_EXPECTED := ["低 · 流畅", "中 · 均衡", "高 · 精致", "极高 · 细腻", "极致 · 电影"]
const MONO_UP := [
	"msaa_3d", "msaa_2d", "scaling_3d_scale", "sky_cloud_detail", "sea_wave_detail", "sea_foam",
	"sea_reflection", "sea_ssr", "sea_mesh_scale", "grass_density", "particle_density",
	"light_budget", "glow_strength", "exposure", "ao_strength", "fog_scale", "lod_bias",
]

var checks := 0
var fails := 0
var iq_scr: Script
var presets: Array = []
var start_ms := 0
var out_dir := DEFAULT_OUT

func _check(cond: bool, msg: String) -> void:
	checks += 1
	if cond:
		print("  [PASS] ", msg)
	else:
		fails += 1
		print("  [FAIL] ", msg)

func _iq(method: String, args: Array = []) -> Variant:
	return iq_scr.callv(method, args)

func _initialize() -> void:
	start_ms = Time.get_ticks_msec()
	print("=== probe_quality6: 五档画质契约 + 材质映射 + 自定义 AO ===")
	iq_scr = load(IQ_PATH)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	_static_checks()
	if "--window" in OS.get_cmdline_user_args():
		print("--- 窗口验证（截图 + AO 像素对比）---")
		await _window_checks()
	_report()

func _static_checks() -> void:
	var consts: Dictionary = iq_scr.get_script_constant_map()
	var names: Array = consts["QUALITY_NAMES"]
	_check(names.size() == 5 and String(names[0]) == QUALITY_NAMES_EXPECTED[0] and String(names[4]) == QUALITY_NAMES_EXPECTED[4], "QUALITY_NAMES 五档名称与契约一致")
	_check(int(_iq("count")) == 5, "count() == 5")
	var label_ok := true
	for i in range(5):
		if String(_iq("label", [i])) != QUALITY_NAMES_EXPECTED[i]:
			label_ok = false
	_check(label_ok, "label(0..4) 依次为 %s" % str(QUALITY_NAMES_EXPECTED))

	var ks: Array = _iq("keys")
	var key_set := {}
	for k in ks:
		key_set[String(k)] = true
	var missing: Array = []
	for k in CONTRACT_KEYS:
		if not key_set.has(k):
			missing.append(k)
	var extra: Array = []
	for k in key_set.keys():
		if not CONTRACT_KEYS.has(String(k)):
			extra.append(k)
	_check(ks.size() == CONTRACT_KEYS.size() and missing.is_empty() and extra.is_empty(), "keys() = 契约 24 键（缺 %s / 多 %s）" % [str(missing), str(extra)])

	var specs: Dictionary = consts["KEY_SPECS"]
	presets.clear()
	var type_msg := ""
	var range_msg := ""
	for i in range(5):
		var p: Dictionary = _iq("preset", [i])
		presets.append(p)
		for key in CONTRACT_KEYS:
			if not p.has(key):
				type_msg += "p%d 缺 %s; " % [i, key]
				continue
			var spec: Dictionary = specs[key]
			var t := String(spec["type"])
			var v: Variant = p[key]
			if t == "bool":
				if not (v is bool):
					type_msg += "p%d.%s 应为 bool; " % [i, key]
			elif t == "int":
				if not (v is int or v is float):
					type_msg += "p%d.%s 应为 int; " % [i, key]
				elif int(v) < int(spec["min"]) or int(v) > int(spec["max"]):
					range_msg += "p%d.%s=%s; " % [i, key, str(v)]
			else:
				if not (v is float or v is int):
					type_msg += "p%d.%s 应为 float; " % [i, key]
				elif not is_finite(float(v)) or float(v) < float(spec["min"]) or float(v) > float(spec["max"]):
					range_msg += "p%d.%s=%s; " % [i, key, str(v)]
	_check(type_msg.is_empty(), "五档 24 键类型全部符合 KEY_SPECS（%s）" % (type_msg if not type_msg.is_empty() else "ok"))
	_check(range_msg.is_empty(), "五档数值全部在 KEY_SPECS 合法区间（%s）" % (range_msg if not range_msg.is_empty() else "ok"))

	for key in MONO_UP:
		var prev := -1e9
		var ok := true
		var seq: Array = []
		for i in range(5):
			var raw: Variant = presets[i][key]
			var v := 0.0
			if raw is bool:
				v = 1.0 if bool(raw) else 0.0
			else:
				v = float(raw)
			seq.append(snappedf(v, 0.001))
			if v + 1e-9 < prev:
				ok = false
			prev = v
		_check(ok, "%s 随档位单调不降 %s" % [key, str(seq)])

	var p0: Dictionary = presets[0]
	var p4: Dictionary = presets[4]
	_check(int(p0["msaa_3d"]) == 0 and float(p0["scaling_3d_scale"]) >= 0.8 and int(p0["max_fps"]) > 0, "低档不坏画面：MSAA 关、SSAA>=0.8、限 60fps")
	_check(int(p4["msaa_3d"]) == 3 and float(p4["scaling_3d_scale"]) >= 1.2 and int(p4["sky_cloud_detail"]) == 3 and int(p4["sea_wave_detail"]) == 3, "极致档：MSAA8x + SSAA>=1.2 + 第4层云 + 全部 7 组波")
	_check(float(p4["sea_ssr"]) >= 0.5 and float(p4["ao_strength"]) >= 0.6 and bool(p4["posts_ao"]), "极致档：SSR + 自定义 AO 最强（ssr=%.2f ao=%.2f）" % [float(p4["sea_ssr"]), float(p4["ao_strength"])])
	_check(float(p4["exposure"]) <= 1.1 and float(p4["glow_strength"]) <= 1.2 and float(p4["scaling_3d_scale"]) <= 1.3, "极致档不过曝：exposure=%.2f glow=%.2f SSAA=%.2f" % [float(p4["exposure"]), float(p4["glow_strength"]), float(p4["scaling_3d_scale"])])
	var tonemap_ok := true
	for p in presets:
		if int(p["tonemap"]) != 0:
			tonemap_ok = false
	_check(tonemap_ok, "五档 tonemap 统一 LINEAR（项目按 LINEAR 调色，避免换 tonemap 整体偏灰）")

	var defs: Dictionary = _iq("defaults")
	var p2: Dictionary = presets[2]
	_check(str(defs) == str(p2), "defaults() = 高·精致档 preset(2)")

	# overrides 合并 / 收敛
	var merged: Dictionary = _iq("merge_overrides", [presets[4], {"sea_wave_detail": 99, "sea_foam": -3.0, "exposure": 5.0, "unknown_key": 1}])
	_check(int(merged["sea_wave_detail"]) == 3 and float(merged["sea_foam"]) <= 0.001 and absf(float(merged["exposure"]) - 1.4) < 1e-6 and not merged.has("unknown_key"), "merge_overrides：越界 clamp、非法键丢弃（wave=%d foam=%.2f exposure=%.2f）" % [int(merged["sea_wave_detail"]), float(merged["sea_foam"]), float(merged["exposure"])])
	var eff: Dictionary = _iq("effective", [3, {"grass_density": 0.5}])
	_check(absf(float(eff["grass_density"]) - 0.5) < 1e-6 and int(eff["sea_wave_detail"]) == 3 and absf(float(eff["sea_ssr"]) - 0.58) < 1e-6, "effective(3, override) = 档位参数 + 用户覆盖")

	# 材质映射
	var sea4: Dictionary = _iq("sea_params", [p4])
	_check(int(sea4["wave_detail"]) == 3 and absf(float(sea4["foam_amount"]) - 1.0) < 1e-6 and absf(float(sea4["island_refl"]) - 1.25) < 1e-6 and absf(float(sea4["ssr_strength"]) - 0.62) < 1e-6, "极致档 sea_params: wave=3 foam=1.0 refl=1.25 ssr=0.62")
	_check(absf(float(sea4["sea_normal_detail"]) - 1.35) < 1e-6 and absf(float(sea4["sea_foam_detail"]) - 2.4) < 1e-6 and absf(float(sea4["sea_refl_detail"]) - 2.0) < 1e-6, "极致档海面细节 uniform: normal=1.35 foam=2.4 refl=2.0")
	var sea0: Dictionary = _iq("sea_params", [p0])
	_check(int(sea0["wave_detail"]) == 0 and float(sea0["foam_amount"]) <= 0.001 and float(sea0["ssr_strength"]) <= 0.001 and float(sea0["sea_foam_detail"]) <= 0.001, "低档 sea_params: wave=0 foam=0 ssr=0（仍有 3 组大波，无泡沫/SSR 成本）")
	var sky4: Dictionary = _iq("sky_params", [p4])
	_check(absf(float(sky4["cloud_detail"]) - 3.0) < 1e-6, "极致档 sky_params.cloud_detail = 3")
	var rp4: Dictionary = _iq("render_params", [p4])
	_check(int(rp4["msaa_3d"]) == 3 and float(rp4["scaling_3d_scale"]) >= 1.2 and float(rp4["ao_strength"]) >= 0.6 and bool(rp4["posts_ao"]), "极致档 render_params: MSAA8x + SSAA>=1.2 + AO 0.75")
	var rp0: Dictionary = _iq("render_params", [p0])
	_check((not bool(rp0["posts_ao"])) and float(rp0["ao_strength"]) <= 0.001, "低档 render_params: AO 关闭")

	# isle_settings 桥接
	var s_scr: Script = load(SETTINGS_PATH)
	var s_consts: Dictionary = s_scr.get_script_constant_map()
	_check(int(s_consts.get("QUALITY_COUNT", -1)) == 5, "isle_settings.QUALITY_COUNT = 5")
	var s_labels: Array = s_consts.get("QUALITY_LABELS", [])
	_check(s_labels.size() == 5 and String(s_labels[4]) == QUALITY_NAMES_EXPECTED[4], "isle_settings.QUALITY_LABELS 与 IsleQuality 一致")
	var sp: Variant = s_scr.call("quality_preset", 4)
	var sp_ok: bool = sp is Dictionary
	if sp_ok:
		for key in CONTRACT_KEYS:
			if not (sp as Dictionary).has(key):
				sp_ok = false
				break
	_check(sp_ok, "isle_settings.quality_preset(4) 桥接到 24 键参数表")
	_check(String(s_scr.call("quality_label", 4)) == QUALITY_NAMES_EXPECTED[4], "isle_settings.quality_label(4) = 极致 · 电影")
	var se: Variant = s_scr.call("quality_effective", 3, {"sea_wave_detail": 1})
	_check(se is Dictionary and int((se as Dictionary).get("sea_wave_detail", -1)) == 1, "isle_settings.quality_effective(3, override) 生效")
	var ss: Variant = s_scr.call("quality_summary", {"quality": 4, "quality_overrides": {}})
	_check(ss is String and String(ss).length() > 0, "isle_settings.quality_summary(quality=4) = %s" % str(ss))

	# 着色器静态接口
	var sea_txt := FileAccess.get_file_as_string(SEA_SHADER)
	var sea_req := ["uniform float wave_height", "uniform float wave_detail", "uniform float foam_amount", "uniform float island_refl", "uniform float ssr_strength", "uniform float sea_normal_detail", "uniform float sea_foam_detail", "uniform float sea_refl_detail", "uniform mat4 ssr_cam_vp"]
	var miss: Array = []
	for s in sea_req:
		if not sea_txt.contains(s):
			miss.append(s)
	_check(miss.is_empty(), "sea.gdshader 保留 main 写入的 uniform 名（缺 %s）" % str(miss))
	_check(sea_txt.contains("vec3 reflect_extra(vec3 R)") and not sea_txt.contains(": hint_screen_texture") and not sea_txt.contains(": hint_depth_texture"), "sea.gdshader：屏幕/深度纹理采样已移除，改为解析反射增强 reflect_extra()（不透明 pass 洗白已修）")
	var sky_txt := FileAccess.get_file_as_string(SKY_SHADER)
	_check(sky_txt.contains("uniform float cloud_detail") and sky_txt.contains("cloud_detail > 2.5"), "sky.gdshader cloud_detail 0..3 且有第 4 层云分支")
	_check(sky_txt.contains("star_field(d, y, cloud_detail)"), "sky.gdshader 星空细节随 cloud_detail 提升（含银河细化）")
	var ao_txt := FileAccess.get_file_as_string(POST_AO)
	_check(ao_txt.length() > 500 and ao_txt.contains("hint_depth_texture") and ao_txt.contains("uniform float ao_strength") and ao_txt.contains("uniform float ao_radius") and ao_txt.contains("uniform int ao_samples"), "post_ao.gdshader 存在且暴露 ao_strength/ao_radius/ao_samples + depth texture")
	_check(ao_txt.contains("POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0)"), "post_ao.gdshader 顶点全屏铺满（可直接挂 Camera3D 下）")
	_check(ao_txt.contains("v_proj * vec4(sp") and ao_txt.contains("view_pos_z(INV_PROJECTION_MATRIX"), "post_ao.gdshader 采用视空间半球投影采样（不是屏幕空间圆环）")
	_check(not ao_txt.contains(": hint_screen_texture") and ao_txt.contains("ALPHA = clamp(ao"), "post_ao.gdshader 为透明乘法叠层（不读屏幕纹理）")

# ------------------------------------------------------------------
# 窗口验证
# ------------------------------------------------------------------
func _window_checks() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var scene: PackedScene = load(MAIN_SCENE)
	var m: Variant = scene.instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	await process_frame
	_check(m != null and m.has_method("_apply_quality") and m.has_method("_set_time_of_day"), "isle.tscn 实例化成功且 main 暴露 _apply_quality/_set_time_of_day")
	if m == null:
		return
	# 隐藏菜单/HUD，只留场景
	var menu: Variant = m.get("_menu")
	if menu is CanvasItem:
		menu.visible = false
	elif menu is CanvasLayer:
		menu.visible = false
	var hud: Variant = m.get("_hud")
	if hud != null and hud.has_method("set_hud_visible"):
		hud.call("set_hud_visible", false, false)
	# 关键：main 默认停在 MENU 模式，_process 每帧用 _movie_pose() 覆盖机位，
	# 探针摆的 _play_pose 会被立刻冲掉（此前截图其实是 menu 电影机位）。
	# 切到 PLAYING 模式并关掉自动运镜，机位才稳定生效。
	m.set("_mode", 1)
	m.set("_auto_orbit", false)
	# 时间冻结：菜单模式下 _tick 不推进时间，切 PLAYING 后必须锁时间源与暂停推进，
	# 否则若持久化设置 time_source=real 会立刻跳到系统真实时间（夜间），各档也不同时刻。
	m.set("_time_source", "sim")
	m.set("_realtime", false)
	m.set("_paused", true)
	if menu is CanvasLayer:
		(menu as CanvasLayer).visible = false
	DisplayServer.window_set_size(Vector2i(1280, 800))
	await process_frame
	var cam: Camera3D = null
	var cv: Variant = m.get("_cam")
	if cv is Camera3D:
		cam = cv
	if cam == null:
		cam = _find_camera(m)
	_check(cam != null, "找到 Camera3D（_cam）")
	if cam == null:
		return
	# 同机位/同时刻：与 main.gd --shots 的 05_quality 段一致
	m.call("_set_time_of_day", 12.0 * 60.0 + 20.0)
	var isle_math: Script = load("res://scripts/isle_math.gd")
	var cart: Variant = isle_math.get_script_constant_map().get("CAM_TARGET", Vector3.ZERO)
	m.set("_theta", 0.74)
	m.set("_elev", 0.28)
	m.set("_radius", 82.0)
	m.set("_cam_target", cart)
	m.set("_fov", 42.0)
	m.call("_apply_pose", m.call("_play_pose"))
	await process_frame
	await process_frame
	await process_frame
	# 机位稳定性：5 帧内不应漂移（验证 PLAYING 模式下 _update_camera 不会覆盖探针机位）
	var p0: Vector3 = cam.global_position
	for _k in range(5):
		await process_frame
	var p1: Vector3 = cam.global_position
	_check(p0.distance_to(p1) < 0.5, "同机位稳定保持（5 帧漂移 %.3f m）" % p0.distance_to(p1))
	var tier_imgs: Array = []
	var tier_stats: Array = []
	var sea_mesh := _find_sea(m)
	var vp: Viewport = m.get_viewport()
	var sim_min := fposmod(float(m.get("_sim_seconds")), 86400.0) / 60.0
	print("  viewport size = %s | sea MeshInstance3D = %s | time_source=%s day_length=%.0fs sim=%02d:%02d paused=%s" % [str(vp.get_visible_rect().size), str(sea_mesh != null), str(m.get("_time_source")), float(m.get("_day_length")), int(sim_min) / 60, int(sim_min) % 60, str(m.get("_paused"))])

	for i in range(5):
		if Time.get_ticks_msec() - start_ms > 75000:
			print("  [WARN] 窗口阶段超时预算，提前结束（已拍 %d 档）" % i)
			break
		var settings: Variant = m.get("_settings")
		if settings is Dictionary:
			(settings as Dictionary)["quality"] = i
			(settings as Dictionary)["quality_overrides"] = {}
		m.call("_apply_quality", i)
		await process_frame
		await process_frame
		await process_frame
		var fps := await _measure_fps(6)
		var prim := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		var calls := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		var subdiv := -1
		var verts := -1
		if sea_mesh != null and sea_mesh.mesh is PlaneMesh:
			var pm: PlaneMesh = sea_mesh.mesh
			subdiv = pm.subdivide_width
			verts = (pm.subdivide_width + 1) * (pm.subdivide_depth + 1)
		var img: Image = await _capture(out_dir + "/quality_fixed_q%d.png" % i)
		tier_imgs.append(img)
		var st := _img_stats(img)
		tier_stats.append(st)
		print("  [STATS] q%d mean=(%.3f,%.3f,%.3f) lum=%.4f sat=%.4f sky_lum=%.4f sea_lum=%.4f island_lum=%.4f" % [i, float(st["r"]), float(st["g"]), float(st["b"]), float(st["lum"]), float(st["sat"]), float(st["sky"]), float(st["sea"]), float(st["island"])])
		print("  [METRIC] q%d: msaa_3d=%d scaling_3d=%.2f taa=%s sea_subdiv=%d sea_verts=%d prim=%d calls=%d fps=%.1f shot=%dx%d" % [
			i, int(vp.msaa_3d), float(vp.scaling_3d_scale), str(vp.use_taa), subdiv, verts, prim, calls, fps,
			img.get_width() if img != null else 0, img.get_height() if img != null else 0])
		_check(subdiv < 0 or subdiv > 0, "q%d 海网格细分已由 main._apply_sea_mesh 设置（subdiv=%d）" % [i, subdiv])

	# 档间可见差异 + 「高档不洗白」检查（同机位像素对比）
	if tier_imgs.size() == 5:
		var d02 := _img_diff(tier_imgs[0], tier_imgs[2])
		var d24 := _img_diff(tier_imgs[2], tier_imgs[4])
		var d04 := _img_diff(tier_imgs[0], tier_imgs[4])
		print("  [DIFF] q0->q2 mean=%.5f changed=%.2f%% | q2->q4 mean=%.5f changed=%.2f%% | q0->q4 mean=%.5f changed=%.2f%%" % [d02["mean"], d02["pct"], d24["mean"], d24["pct"], d04["mean"], d04["pct"]])
		_check(float(d04["pct"]) > 3.0, "低档 vs 极致档同机位画面差异可见（%.2f%% 像素改变）" % float(d04["pct"]))
		_check(float(d24["pct"]) > 0.3 or float(d24["mean"]) > 0.0008, "高 vs 极致档仍有可见提升（%.2f%% 像素，mean=%.5f）" % [float(d24["pct"]), float(d24["mean"])])
		var lum2 := float(tier_stats[2]["lum"])
		var lum3 := float(tier_stats[3]["lum"])
		var lum4 := float(tier_stats[4]["lum"])
		var sat2 := float(tier_stats[2]["sat"])
		var sat3 := float(tier_stats[3]["sat"])
		var sat4 := float(tier_stats[4]["sat"])
		print("  [WASH] dLum q3-q2=%+.4f q4-q2=%+.4f | sat 比 q3=%.3f q4=%.3f" % [lum3 - lum2, lum4 - lum2, sat3 / maxf(sat2, 1e-6), sat4 / maxf(sat2, 1e-6)])
		_check(lum3 - lum2 < 0.025 and lum4 - lum2 < 0.035, "q2 之后没有整屏提亮/蒙层（Δlum q3=%+.4f q4=%+.4f）" % [lum3 - lum2, lum4 - lum2])
		_check(sat3 / maxf(sat2, 1e-6) > 0.85 and sat4 / maxf(sat2, 1e-6) > 0.85, "q2 之后色彩没有被洗淡（sat 比 q3=%.3f q4=%.3f）" % [sat3 / maxf(sat2, 1e-6), sat4 / maxf(sat2, 1e-6)])

	# 水面近景：极致 / 低 两档对比
	m.call("_pose_look", Vector3(-42.0, 6.0, 30.0), Vector3(-96.0, -0.4, 78.0), 58.0)
	await process_frame
	await process_frame
	_apply_q(m, 4)
	await process_frame
	await process_frame
	await process_frame
	await _capture(out_dir + "/t3_water_ultra.png")
	_apply_q(m, 0)
	await process_frame
	await process_frame
	await process_frame
	await _capture(out_dir + "/t3_water_low.png")

	# ---- 回到岛屿机位：q4 解析反射增强（sea ssr_strength）与自定义 AO 的定量验证 ----
	_restore_isle_pose(m)
	_apply_q(m, 4)
	await process_frame
	await process_frame
	await process_frame
	var sea_mat: ShaderMaterial = null
	if sea_mesh != null and sea_mesh.material_override is ShaderMaterial:
		sea_mat = sea_mesh.material_override
	var ssr_on := 0.62
	var img_tier4: Image = tier_imgs[4] if tier_imgs.size() == 5 else null
	if sea_mat != null:
		ssr_on = float(sea_mat.get_shader_parameter("ssr_strength"))
		sea_mat.set_shader_parameter("ssr_strength", 0.0)
		await process_frame
		await process_frame
	var img_ssr0: Image = await _capture(out_dir + "/quality_fixed_q4_ssr0.png")
	if sea_mat != null:
		sea_mat.set_shader_parameter("ssr_strength", ssr_on)
	var dssr := _img_diff(img_tier4, img_ssr0)
	var lum_ssr_on := _img_lum(img_tier4)
	var lum_ssr0 := _img_lum(img_ssr0)
	print("  [SSR-BOOST] q4 ssr=%.2f vs 0: mean=%.5f changed=%.2f%% full_lum %.4f -> %.4f" % [ssr_on, dssr["mean"], dssr["pct"], lum_ssr_on, lum_ssr0])
	_check(float(dssr["pct"]) > 0.1, "q4 解析反射增强（ssr_strength）有可见海面变化（%.2f%% 像素）" % float(dssr["pct"]))
	_check(absf(lum_ssr_on - lum_ssr0) < 0.02, "反射增强不会整屏提亮/洗白（Δlum=%.4f）" % absf(lum_ssr_on - lum_ssr0))

	# 自定义 AO：用 main 已挂载的 PostAO（透明 pass 乘法叠层，priority=127）
	var post_mat: ShaderMaterial = null
	var post_mi: MeshInstance3D = null
	var pmv: Variant = m.get("_post_ao_mat")
	if pmv is ShaderMaterial:
		post_mat = pmv
	var pmiv: Variant = m.get("_post_ao_mi")
	if pmiv is MeshInstance3D:
		post_mi = pmiv
	_check(post_mat != null and post_mi != null, "main 场景内已挂载 PostAO QuadMesh（_post_ao_mat/_post_ao_mi）")
	if post_mat == null or post_mi == null:
		return
	post_mi.visible = false
	post_mat.set_shader_parameter("ao_strength", 0.0)
	await process_frame
	await process_frame
	var img_ao_off: Image = await _capture(out_dir + "/quality_fixed_ao_off.png")
	post_mi.visible = true
	post_mat.set_shader_parameter("ao_strength", 0.75)
	post_mat.set_shader_parameter("ao_radius", 1.0)
	post_mat.set_shader_parameter("ao_samples", 16)
	post_mat.set_shader_parameter("ao_bias", 0.02)
	post_mat.set_shader_parameter("ao_max_dist", 140.0)
	post_mat.set_shader_parameter("ao_contrast", 1.4)
	post_mat.set_shader_parameter("depth_convention", 0)
	post_mat.set_shader_parameter("ao_debug", 0)
	await process_frame
	await process_frame
	var img_ao_on: Image = await _capture(out_dir + "/quality_fixed_ao_on.png")
	var dao := _img_diff(img_ao_off, img_ao_on)
	var lum_off := _img_lum(img_ao_off)
	var lum_on := _img_lum(img_ao_on)
	var ratio := lum_on / maxf(lum_off, 1e-6)
	print("  [AO] 开/关: mean=%.5f changed=%.2f%% full_lum %.4f -> %.4f ratio=%.4f" % [dao["mean"], dao["pct"], lum_off, lum_on, ratio])
	_check(float(dao["pct"]) > 1.0 and ratio > 0.85, "自定义 AO 在真实场景产生可测的局部接触阴影（%.2f%% 像素、亮度比 %.3f，不是整屏蒙层）" % [float(dao["pct"]), ratio])
	post_mat.set_shader_parameter("ao_debug", 1)
	await process_frame
	await process_frame
	var img_ao_dbg: Image = await _capture(out_dir + "/quality_fixed_ao_debug.png")
	post_mat.set_shader_parameter("ao_debug", 0)
	var aq := _img_quantiles(img_ao_dbg, 0.28, 0.15, 0.44, 0.65, 0)
	print("  [AO-DBG] 岛区 ao: p50=%.3f p90=%.3f p99=%.3f max=%.3f frac>0.05=%.2f%%" % [aq["p50"], aq["p90"], aq["p99"], aq["max"], aq["frac"]])
	_check(float(aq["p90"]) > 0.05 and float(aq["frac"]) > 2.0, "AO 调试图在岛屿区域确有遮蔽值（p90=%.3f、>0.05 占比=%.1f%%）" % [float(aq["p90"]), float(aq["frac"])])
	# 恢复 main 的画质参数与 AO 开关，避免影响后续统一 --shots
	_apply_q(m, 4)

func _apply_q(m: Variant, q: int) -> void:
	var st: Variant = m.get("_settings")
	if st is Dictionary:
		(st as Dictionary)["quality"] = q
		(st as Dictionary)["quality_overrides"] = {}
	m.call("_apply_quality", q)

func _restore_isle_pose(m: Variant) -> void:
	var isle_math: Script = load("res://scripts/isle_math.gd")
	var cart: Variant = isle_math.get_script_constant_map().get("CAM_TARGET", Vector3.ZERO)
	m.call("_set_time_of_day", 12.0 * 60.0 + 20.0)
	m.set("_theta", 0.74)
	m.set("_elev", 0.28)
	m.set("_radius", 82.0)
	m.set("_cam_target", cart)
	m.set("_fov", 42.0)
	m.call("_apply_pose", m.call("_play_pose"))

func _find_camera(node: Node) -> Camera3D:
	if node is Camera3D:
		return node
	for c in node.get_children():
		var r := _find_camera(c)
		if r != null:
			return r
	return null

func _find_sea(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh is PlaneMesh and (mi.mesh as PlaneMesh).size.x >= 1000.0:
			return mi
	for c in node.get_children():
		var r := _find_sea(c)
		if r != null:
			return r
	return null

func _capture(path: String) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null:
		print("  [WARN] 截图失败：%s" % path)
		return null
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := img.save_png(path)
	print("  [SHOT] %s %dx%d err=%d" % [path, img.get_width(), img.get_height(), err])
	return img

func _measure_fps(frames: int) -> float:
	var t0 := Time.get_ticks_usec()
	for i in range(frames):
		await process_frame
	var dt := float(Time.get_ticks_usec() - t0) / 1000000.0
	return float(frames) / maxf(dt, 1e-6)

func _img_diff(a: Image, b: Image) -> Dictionary:
	if a == null or b == null:
		return {"mean": 0.0, "pct": 0.0}
	var w := mini(a.get_width(), b.get_width())
	var h := mini(a.get_height(), b.get_height())
	var sum := 0.0
	var n := 0
	var changed := 0
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var la := 0.2126 * ca.r + 0.7152 * ca.g + 0.0722 * ca.b
			var lb := 0.2126 * cb.r + 0.7152 * cb.g + 0.0722 * cb.b
			var d := absf(la - lb)
			sum += d
			n += 1
			if d > 0.004:
				changed += 1
	return {"mean": sum / float(maxi(n, 1)), "pct": 100.0 * float(changed) / float(maxi(n, 1))}

func _img_lum_region(img: Image, rx: float, ry: float, rw: float, rh: float) -> float:
	if img == null:
		return 0.0
	var w := img.get_width()
	var h := img.get_height()
	var x0 := clampi(int(rx * float(w)), 0, w - 1)
	var y0 := clampi(int(ry * float(h)), 0, h - 1)
	var x1 := clampi(int((rx + rw) * float(w)), x0 + 1, w)
	var y1 := clampi(int((ry + rh) * float(h)), y0 + 1, h)
	var sum := 0.0
	var n := 0
	for y in range(y0, y1, 8):
		for x in range(x0, x1, 8):
			var c := img.get_pixel(x, y)
			sum += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
	return sum / float(maxi(n, 1))

func _img_stats(img: Image) -> Dictionary:
	if img == null:
		return {"r": 0.0, "g": 0.0, "b": 0.0, "lum": 0.0, "sat": 0.0, "sky": 0.0, "sea": 0.0, "island": 0.0}
	var w := img.get_width()
	var h := img.get_height()
	var sr := 0.0
	var sg := 0.0
	var sb := 0.0
	var ssat := 0.0
	var n := 0
	for y in range(0, h, 12):
		for x in range(0, w, 12):
			var c := img.get_pixel(x, y)
			sr += c.r
			sg += c.g
			sb += c.b
			ssat += maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))
			n += 1
	var fn := float(maxi(n, 1))
	return {
		"r": sr / fn, "g": sg / fn, "b": sb / fn,
		"lum": (0.2126 * sr + 0.7152 * sg + 0.0722 * sb) / fn,
		"sat": ssat / fn,
		"sky": _img_lum_region(img, 0.0, 0.0, 1.0, 0.22),
		"sea": _img_lum_region(img, 0.0, 0.88, 1.0, 0.12),
		"island": _img_lum_region(img, 0.30, 0.25, 0.42, 0.55),
	}

func _img_quantiles(img: Image, rx: float, ry: float, rw: float, rh: float, ch: int) -> Dictionary:
	if img == null:
		return {"p50": 0.0, "p90": 0.0, "p99": 0.0, "max": 0.0, "frac": 0.0}
	var w := img.get_width()
	var h := img.get_height()
	var x0 := clampi(int(rx * float(w)), 0, w - 1)
	var y0 := clampi(int(ry * float(h)), 0, h - 1)
	var x1 := clampi(int((rx + rw) * float(w)), x0 + 1, w)
	var y1 := clampi(int((ry + rh) * float(h)), y0 + 1, h)
	var vals: Array = []
	for y in range(y0, y1, 3):
		for x in range(x0, x1, 3):
			var c := img.get_pixel(x, y)
			var v := c.r
			if ch == 1:
				v = c.g
			elif ch == 2:
				v = c.b
			vals.append(v)
	vals.sort()
	var cnt := maxi(vals.size(), 1)
	var cnt_gt := 0
	for v in vals:
		if float(v) > 0.05:
			cnt_gt += 1
	return {
		"p50": float(vals[mini(int(0.50 * float(cnt)), cnt - 1)]) if vals.size() > 0 else 0.0,
		"p90": float(vals[mini(int(0.90 * float(cnt)), cnt - 1)]) if vals.size() > 0 else 0.0,
		"p99": float(vals[mini(int(0.99 * float(cnt)), cnt - 1)]) if vals.size() > 0 else 0.0,
		"max": float(vals[cnt - 1]) if vals.size() > 0 else 0.0,
		"frac": 100.0 * float(cnt_gt) / float(cnt),
	}

func _img_lum(img: Image) -> float:
	if img == null:
		return 0.0
	var w := img.get_width()
	var h := img.get_height()
	var sum := 0.0
	var n := 0
	for y in range(0, h, 8):
		for x in range(0, w, 8):
			var c := img.get_pixel(x, y)
			sum += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
	return sum / float(maxi(n, 1))

func _report() -> void:
	var elapsed := float(Time.get_ticks_msec() - start_ms) / 1000.0
	print("=== probe_quality6 结果: checks=%d fails=%d 用时=%.1fs ===" % [checks, fails, elapsed])
	if "--window" in OS.get_cmdline_user_args():
		print("截图目录: ", out_dir)
	quit(0 if fails == 0 else 1)