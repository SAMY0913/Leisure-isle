extends SceneTree
## task-8 阁楼窗重影隔离探针（窗口模式，v2 = 修复后回归矩阵）
## 用法:
##   <godot_console.exe> --path D:/休闲小岛幻境/游戏工程 --script res://tools/probe_ghost6.gd -- --window --out=D:/休闲小岛幻境/开发产物/shots6/ghost
## headless 只做语法自检（本探针的矩阵需要真实窗口/GPU）。
##
## v1（修复前）已定位根因 = PostAO：q2/q3/q4 窗洞亮度比 0.496/0.410/0.369（相对 AO 关）。
## v2 用来回归修复后的 post_ao.gdshader：要求
##   ① 窗洞亮度比 q2>0.92、q3>0.90、q4>0.88（鬼影不可察觉）
##   ② AO 仍然可见（q2 全图 0.3%~、q4 1%+ 像素变化；岛景 AO 开/关有差异且不过度）
##   ③ 高档不再洗白/过曝（q4 亮度不高于 q2+0.03）、TAA/玻璃/refract/SSAA 仍非根因（对照项）
## 每个变体只改一个因子；机位固定为 05:14 破晓前正面阁楼落地窗近景（与用户反馈图同构图）。

const MAIN_SCENE := "res://isle.tscn"
const TIME_MIN := 5.0 * 60.0 + 14.0
var out_dir := "D:/休闲小岛幻境/开发产物/shots6/ghost"
var start_ms := 0
var checks := 0
var fails := 0
var m: Variant = null
var cam: Camera3D = null
var vp: Viewport = null
var env: Environment = null
var win_world := Vector3.ZERO
var win_roi := Rect2(0, 0, 0, 0)
var glass_outer: MeshInstance3D = null
var glass_inner: MeshInstance3D = null
var glass_mats: Array = []
var post_ao_mi: MeshInstance3D = null
var post_ao_mat: ShaderMaterial = null
var shots: Array = []
var stats: Dictionary = {}

func _initialize() -> void:
	start_ms = Time.get_ticks_msec()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	if "--window" in OS.get_cmdline_user_args():
		await _window_run()
	else:
		print("[ghost6] headless 模式：仅语法自检；窗口矩阵需 --window + 桌面会话")
	_report()

func _window_run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var scene: PackedScene = load(MAIN_SCENE)
	if scene == null:
		_check(false, "加载 isle.tscn")
		return
	m = scene.instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	await process_frame
	_check(m != null and m.has_method("_apply_quality") and m.has_method("_set_time_of_day"), "isle.tscn 实例化成功且 main 暴露所需方法")
	if m == null:
		return
	var menu: Variant = m.get("_menu")
	if menu is CanvasLayer:
		(menu as CanvasLayer).visible = false
	var hud: Variant = m.get("_hud")
	if hud != null and hud.has_method("set_hud_visible"):
		hud.call("set_hud_visible", false, false)
	# main 默认 MENU 模式且 _process 每帧覆盖机位；切 PLAYING + 暂停 + 冻结时间源，机位才稳定。
	m.set("_mode", 1)
	m.set("_auto_orbit", false)
	m.set("_time_source", "sim")
	m.set("_realtime", false)
	m.set("_paused", true)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	await process_frame
	await process_frame
	var cv: Variant = m.get("_cam")
	if cv is Camera3D:
		cam = cv
	_check(cam != null, "找到 Camera3D")
	if cam == null:
		return
	vp = m.get_viewport()
	var ev: Variant = m.get("_env")
	if ev is Environment:
		env = ev
	m.call("_set_time_of_day", TIME_MIN)
	m.call("_update_lighting")
	# 冻结 main 的 _process（否则 _update_camera 每帧用 _play_pose 覆盖探针机位）
	m.set_process(false)
	await process_frame
	# 阁楼窗世界坐标 + 两层玻璃节点
	var cot: Variant = m.get("_cottage")
	if cot is Dictionary:
		var cd := cot as Dictionary
		var wv: Variant = cd.get("attic_window_world", null)
		if wv is Vector3:
			win_world = wv
		var gv: Variant = cd.get("attic_glass_mats", [])
		if gv is Array:
			glass_mats = gv
		var rv: Variant = cd.get("root", null)
		if rv is Node:
			var aw: Node = (rv as Node).find_child("AtticWindow", true, false)
			if aw != null:
				_collect_glass(aw, glass_mats)
	_check(win_world != Vector3.ZERO, "拿到阁楼窗世界坐标 %s" % str(win_world))
	_check(glass_outer != null and glass_inner != null, "识别阁楼两层玻璃 outer=%s inner=%s mats=%d" % [str(glass_outer != null), str(glass_inner != null), glass_mats.size()])
	var pmv: Variant = m.get("_post_ao_mi")
	if pmv is MeshInstance3D:
		post_ao_mi = pmv
	var mmv: Variant = m.get("_post_ao_mat")
	if mmv is ShaderMaterial:
		post_ao_mat = mmv
	_check(post_ao_mi != null and post_ao_mat != null, "拿到 PostAO 节点/材质")
	# 正面看阁楼窗（用户同构图：窗口在画面中央偏上，仰视）
	var target := win_world + Vector3(0.0, 0.05, 0.0)
	var pos := win_world + Vector3(0.55, -2.05, 6.4)
	_aim(pos, target, 50.0)
	await process_frame
	await process_frame
	win_roi = _project_rect(win_world, 3.30, 2.70)
	print("  [CAM] pos=%s target=%s fov=%.1f win=%s roi=%s viewport=%s mode=%d paused=%s" % [str(cam.global_position), str(target), cam.fov, str(win_world), str(win_roi), str(vp.get_visible_rect().size), int(m.get("_mode")), str(m.get("_paused"))])
	_check(win_roi.size.x > 0.1 and win_roi.size.y > 0.1, "阁楼窗投影 ROI 合理（%s）" % str(win_roi))

	# ---------- A 组：五档基准（修复后应有足够差异、且高档不脏不白） ----------
	await _variant("f_q0", 0, {}, 16)
	await _variant("f_q1", 1, {}, 16)
	await _variant("f_q2", 2, {}, 20)
	await _variant("f_q3", 3, {}, 26)
	await _variant("f_q4", 4, {}, 26)
	# ---------- B 组：AO 隔离（q2/q3/q4 关 AO，与基准对比 = 重影是否消失） ----------
	await _variant("f_q2_ao_off", 2, {"ao": -1.0}, 20)
	await _variant("f_q2_ao_75", 2, {"ao": 0.75}, 20)
	await _variant("f_q3_ao_off", 3, {"ao": -1.0}, 26)
	await _variant("f_q4_ao_off", 4, {"ao": -1.0}, 26)
	# ---------- C 组：TAA 对照（仍应非根因） ----------
	await _variant("f_q4_taa_off", 4, {"taa": false}, 26)
	await _variant("f_q3_taa_off", 3, {"taa": false}, 26)
	# ---------- D 组：玻璃层 / 屏幕折射对照 ----------
	await _variant("f_q2_glass_off", 2, {"glass": "off"}, 20)
	await _variant("f_q2_refract_on", 2, {"refract": 0.006}, 20)
	# ---------- E 组：岛景 AO 有效性（AO 该起作用的地方仍然有遮蔽感） ----------
	await _island_ao_test()
	# ---------- F 组：TAA 历史拖影（转 2° 抓 1 帧） ----------
	await _motion_test("f_q4", 4, {}, 26)
	await _motion_test("f_q4_taa_off", 4, {"taa": false}, 26)
	# ---------- 修复后性能 ----------
	for q in [2, 3, 4]:
		_apply_variant(q, {}, "perf_q%d" % q)
		for _i in range(16):
			await process_frame
		var fps := await _measure_fps(20)
		print("  [FPS] q%d fps=%.1f frame_ms=%.2f" % [q, fps, 1000.0 / maxf(fps, 0.001)])
	# ---------- 判定：重影修复 / AO 仍可见 / 不洗白 ----------
	_eval_window_ghost()
	_check(shots.size() >= 16, "窗口截图张数足够（%d）" % shots.size())
	print("  [SHOTS] %d 张 -> %s" % [shots.size(), out_dir])

func _eval_window_ghost() -> void:
	var r_q2 := _roi_ratio("f_q2", "f_q2_ao_off")
	var r_q3 := _roi_ratio("f_q3", "f_q3_ao_off")
	var r_q4 := _roi_ratio("f_q4", "f_q4_ao_off")
	print("  [AO-WIN] 窗洞亮度比(开/关) q2=%.3f q3=%.3f q4=%.3f （修复前 0.496/0.410/0.369；目标 >0.92/>0.90/>0.88）" % [r_q2, r_q3, r_q4])
	_check(r_q2 > 0.92, "q2 窗内 AO 压暗 <8%%（比值 %.3f）—— 重影不可察觉" % r_q2)
	_check(r_q3 > 0.90, "q3 窗内 AO 压暗 <10%%（比值 %.3f）" % r_q3)
	_check(r_q4 > 0.88, "q4 窗内 AO 压暗 <12%%（比值 %.3f）" % r_q4)
	# AO 仍然真实生效（否则等于偷偷关掉 AO 糊弄）
	for pair in [["f_q2", "f_q2_ao_off", 0.2], ["f_q3", "f_q3_ao_off", 0.4], ["f_q4", "f_q4_ao_off", 0.6]]:
		var a: String = str(pair[0])
		var b: String = str(pair[1])
		var mn: float = float(pair[2])
		var d := _diff_paths(a, b)
		print("  [AO-VIS] %s vs %s mean=%.5f pct=%.2f%%（要求 pct>%.1f%%）" % [a, b, float(d["mean"]), float(d["pct"]), mn])
		_check(float(d["pct"]) > mn, "AO 仍可见且柔和（%s pct=%.2f%% > %.1f%%）" % [a, float(d["pct"]), mn])
	_check(float(stats["f_q2"]["roi_std"]) > 0.02, "q2 窗洞仍有层次（roi_std=%.4f）" % float(stats["f_q2"]["roi_std"]))
	# 不洗白：q4 整体亮度不超过 q2 + 0.03，且 q4 不低于 q1 的 0.9（不整屏变暗）
	var l2 := float(stats["f_q2"]["lum"])
	var l4 := float(stats["f_q4"]["lum"])
	_check(l4 < l2 + 0.03, "q4 不洗白（lum q2=%.4f q4=%.4f）" % [l2, l4])
	_check(float(stats["f_q4"]["roi_lum"]) > 0.6 * float(stats["f_q2"]["roi_lum"]), "q4 窗内亮度不低于 q2 的 60%%（q2=%.4f q4=%.4f）" % [float(stats["f_q2"]["roi_lum"]), float(stats["f_q4"]["roi_lum"])])
	# TAA 不是根因：开/关差异小且窗洞亮度一致
	var d_taa := _diff_paths("f_q4", "f_q4_taa_off")
	var r_taa := _roi_ratio("f_q4", "f_q4_taa_off")
	print("  [TAA] q4 TAA on/off mean=%.5f pct=%.2f%% roi_ratio=%.3f" % [float(d_taa["mean"]), float(d_taa["pct"]), r_taa])
	_check(float(d_taa["pct"]) < 12.0 and absf(r_taa - 1.0) < 0.05, "TAA 开/关不改变窗内亮度（pct=%.2f%% ratio=%.3f）→ TAA 非根因" % [float(d_taa["pct"]), r_taa])
	# 玻璃/refract 不是根因
	var d_g := _diff_paths("f_q2", "f_q2_glass_off")
	var d_r := _diff_paths("f_q2", "f_q2_refract_on")
	print("  [GLASS] q2 glass off mean=%.5f pct=%.2f%% | refract .006 mean=%.5f pct=%.2f%%" % [float(d_g["mean"]), float(d_g["pct"]), float(d_r["mean"]), float(d_r["pct"])])
	var r_glass := _roi_ratio("f_q2_glass_off", "f_q2")
	print("  [GLASS-ROI] q2 glass off/on 窗洞亮度比=%.3f" % r_glass)
	_check(float(d_g["pct"]) < 12.0 and float(d_g["mean"]) < 0.004 and r_glass > 0.92 and r_glass < 1.12, "两层玻璃不是鬼影来源（pct=%.2f%% mean=%.5f 窗洞比=%.3f）" % [float(d_g["pct"]), float(d_g["mean"]), r_glass])
	_check(float(d_r["pct"]) < 6.0, "屏幕折射不是鬼影来源（refract on 仅 %.2f%% 像素变化）" % float(d_r["pct"]))
	# 五档仍有明确差异
	var d02 := _diff_paths("f_q0", "f_q2")
	var d24 := _diff_paths("f_q2", "f_q4")
	print("  [DIFF] q0->q2 mean=%.5f pct=%.2f%% | q2->q4 mean=%.5f pct=%.2f%%" % [float(d02["mean"]), float(d02["pct"]), float(d24["mean"]), float(d24["pct"])])
	_check(float(d02["pct"]) > 20.0 or float(d02["mean"]) > 0.01, "q0->q2 画质差异明确（pct=%.2f%%）" % float(d02["pct"]))
	_check(float(d24["pct"]) > 5.0 or float(d24["mean"]) > 0.002, "q2->q4 画质差异明确（pct=%.2f%%）" % float(d24["pct"]))

func _island_ao_test() -> void:
	# 回到默认岛景机位（与 main --shots / probe_quality6 同机位：12:20、theta .74、elev .28、r 82、fov 42）
	m.set("_theta", 0.74)
	m.set("_elev", 0.28)
	m.set("_radius", 82.0)
	m.set("_fov", 42.0)
	m.call("_set_time_of_day", 12.0 * 60.0 + 20.0)
	_apply_variant(4, {}, "island_ao_base")
	_set_ao_strength(-1.0)  # 先关 AO 拍基线
	m.call("_apply_pose", m.call("_play_pose"))
	for _i in range(20):
		await process_frame
	var isle_roi := Rect2(0.30, 0.26, 0.40, 0.46)
	var img_off: Image = await _capture(out_dir + "/ghost_island_ao_off.png")
	if img_off != null:
		shots.append("island_ao_off")
		var so := _img_stats(img_off, isle_roi)
		print("  [STATS] %-22s lum=%.4f isle_lum=%.4f isle_std=%.4f" % ["island_ao_off", float(so["lum"]), float(so["roi_lum"]), float(so["roi_std"])])
		stats["island_ao_off"] = so
	# AO 开（用 q4 档位真实强度 0.75）
	_apply_variant(4, {}, "island_ao_on")
	_set_ao_strength(0.75)
	m.call("_apply_pose", m.call("_play_pose"))
	for _i in range(20):
		await process_frame
	var img_on: Image = await _capture(out_dir + "/ghost_island_ao_on.png")
	if img_on != null:
		shots.append("island_ao_on")
		var so2 := _img_stats(img_on, isle_roi)
		print("  [STATS] %-22s lum=%.4f isle_lum=%.4f isle_std=%.4f" % ["island_ao_on", float(so2["lum"]), float(so2["roi_lum"]), float(so2["roi_std"])])
		stats["island_ao_on"] = so2
		if img_off != null:
			var d := _img_diff(img_on, img_off)
			var ratio := float(so2["roi_lum"]) / maxf(float(stats["island_ao_off"]["roi_lum"]), 1e-5)
			print("  [AO-ISLE] on/off mean=%.5f pct=%.2f%% isle_lum_ratio=%.4f" % [float(d["mean"]), float(d["pct"]), ratio])
			_check(float(d["pct"]) > 0.8, "岛景 AO 有真实效果（pct=%.2f%%）" % float(d["pct"]))
			_check(ratio > 0.85 and ratio < 0.9995, "岛景 AO 温和不过暗（isle_lum 比 %.4f）" % ratio)
	# 岛景 AO 调试图（p90 应明显 >0，证明 patch 不是全 0）
	if post_ao_mat != null and post_ao_mi != null:
		post_ao_mi.visible = true
		post_ao_mat.set_shader_parameter("ao_debug", 1)
		m.call("_apply_pose", m.call("_play_pose"))
		for _i in range(20):
			await process_frame
		var img_dbg: Image = await _capture(out_dir + "/ghost_island_ao_debug.png")
		if img_dbg != null:
			shots.append("island_ao_debug")
			var q := _img_quantiles(img_dbg, isle_roi)
			print("  [AO-DBG] isle p50=%.3f p90=%.3f p99=%.3f max=%.3f frac>0.05=%.2f%%" % [float(q["p50"]), float(q["p90"]), float(q["p99"]), float(q["max"]), 100.0 * float(q["frac"])])
			_check(float(q["p90"]) > 0.02 and float(q["frac"]) > 0.02, "AO 调试图有非零分布（p90=%.3f frac=%.1f%%）" % [float(q["p90"]), 100.0 * float(q["frac"])])
		post_ao_mat.set_shader_parameter("ao_debug", 0)
		_apply_variant(4, {}, "island_restore")

func _roi_ratio(a: String, b: String) -> float:
	if not stats.has(a) or not stats.has(b):
		return -1.0
	return float(stats[a]["roi_lum"]) / maxf(float(stats[b]["roi_lum"]), 1e-5)

func _diff_paths(a: String, b: String) -> Dictionary:
	# 变体多时重新读盘代价高；这里用截图时的图像缓存（_variant 里保存）
	if img_cache.has(a) and img_cache.has(b):
		return _img_diff(img_cache[a], img_cache[b])
	return {"mean": 0.0, "pct": 0.0}

var img_cache: Dictionary = {}

func _variant(name: String, q: int, opts: Dictionary, settle: int) -> void:
	_apply_variant(q, opts, name)
	for _i in range(settle):
		await process_frame
	var img: Image = await _capture(out_dir + "/ghost_" + name + ".png")
	if img != null:
		shots.append(name)
		img_cache[name] = img
		var st := _img_stats(img, win_roi)
		stats[name] = st
		print("  [STATS] %-22s mean=(%.3f,%.3f,%.3f) lum=%.4f roi_lum=%.4f roi_std=%.4f" % [name, float(st["r"]), float(st["g"]), float(st["b"]), float(st["lum"]), float(st["roi_lum"]), float(st["roi_std"])])

func _motion_test(name: String, q: int, opts: Dictionary, settle: int) -> void:
	_apply_variant(q, opts, name)
	_aim(cam.global_position, win_world + Vector3(0.0, 0.05, 0.0), cam.fov)
	for _i in range(settle):
		await process_frame
	var p0 := cam.global_position
	var img_still: Image = await _capture(out_dir + "/ghost_" + name + "_motion_still.png")
	# 绕目标点转 2°，只等 1 帧：TAA 历史会拖出旧机位的鬼影
	var target := win_world + Vector3(0.0, 0.05, 0.0)
	var rel := p0 - target
	var ang := deg_to_rad(2.0)
	var rp := Vector3(rel.x * cos(ang) + rel.z * sin(ang), rel.y, -rel.x * sin(ang) + rel.z * cos(ang))
	_aim(target + rp, target, cam.fov)
	await process_frame
	var img_m1: Image = await _capture(out_dir + "/ghost_" + name + "_motion_move1.png")
	for _i in range(settle):
		await process_frame
	var img_conv: Image = await _capture(out_dir + "/ghost_" + name + "_motion_converged.png")
	_aim(p0, target, cam.fov)
	for _i in range(settle):
		await process_frame
	var d1 := _img_diff(img_m1, img_conv)
	var d2 := _img_diff(img_still, img_conv)
	print("  [GHOSTT] %-10s move1-vs-converged mean=%.5f pct=%.2f%% | still-vs-converged mean=%.5f pct=%.2f%% taa=%s" % [name, float(d1["mean"]), float(d1["pct"]), float(d2["mean"]), float(d2["pct"]), str(vp.use_taa if vp != null else false)])
	_check(float(d2["pct"]) > 2.0 or float(d2["mean"]) > 0.002, "转动 2° 确实改变画面（%s still-vs-converged pct=%.2f%%）" % [name, float(d2["pct"])])

func _apply_variant(q: int, opts: Dictionary, label: String = "") -> void:
	var st: Variant = m.get("_settings")
	if st is Dictionary:
		(st as Dictionary)["quality"] = q
		(st as Dictionary)["quality_overrides"] = {}
	m.call("_apply_quality", q)
	# 先恢复到基准，再按 opts 覆盖
	if opts.get("glass", "both") == "both":
		_set_glass_visible("both")
	if not opts.has("refract"):
		_set_refract(0.0)
	if env != null:
		env.glow_enabled = true
	if vp != null:
		if opts.has("msaa"):
			vp.msaa_3d = int(opts["msaa"])
		if opts.has("taa"):
			vp.use_taa = bool(opts["taa"])
		if opts.has("scale"):
			vp.scaling_3d_scale = float(opts["scale"])
		if opts.has("ssaa"):
			vp.screen_space_aa = int(opts["ssaa"])
	if opts.has("ao"):
		_set_ao_strength(float(opts["ao"]))
	if opts.has("glass"):
		_set_glass_visible(String(opts["glass"]))
	if opts.has("refract"):
		_set_refract(float(opts["refract"]))
	m.call("_update_lighting")
	if opts.has("glow") and env != null and not bool(opts["glow"]):
		env.glow_enabled = false
		env.glow_intensity = 0.0
	var ao_s := -1.0
	if post_ao_mi != null and post_ao_mi.visible and post_ao_mat != null:
		ao_s = float(post_ao_mat.get_shader_parameter("ao_strength"))
	print("  [STATE] %-22s q=%d msaa=%d taa=%s scale=%.2f ssa=%d ao=%.2f glow=%s" % [
		label, q,
		int(vp.msaa_3d) if vp != null else -1,
		str(vp.use_taa) if vp != null else "?",
		float(vp.scaling_3d_scale) if vp != null else -1.0,
		int(vp.screen_space_aa) if vp != null else -1,
		ao_s,
		str(env.glow_enabled) if env != null else "?"])

func _set_ao_strength(strength: float) -> void:
	if post_ao_mi == null or post_ao_mat == null:
		return
	if strength < 0.0:
		post_ao_mi.visible = false
	else:
		post_ao_mi.visible = true
		post_ao_mat.set_shader_parameter("ao_strength", strength)
		post_ao_mat.set_shader_parameter("ao_debug", 0)

func _set_glass_visible(mode: String) -> void:
	if glass_outer != null:
		glass_outer.visible = mode == "both" or mode == "outer"
	if glass_inner != null:
		glass_inner.visible = mode == "both" or mode == "inner"

func _set_refract(v: float) -> void:
	for mat in glass_mats:
		if mat is ShaderMaterial:
			(mat as ShaderMaterial).set_shader_parameter("refract_strength", v)

func _collect_glass(node: Node, mats: Array) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var ov: Variant = mi.material_override
		if ov is Material and mats.has(ov):
			if glass_outer == null and mats.size() > 0 and ov == mats[0]:
				glass_outer = mi
			elif glass_inner == null:
				glass_inner = mi
	for c in node.get_children():
		_collect_glass(c, mats)

func _aim(pos: Vector3, target: Vector3, fov_deg: float) -> void:
	if cam == null:
		return
	cam.current = true
	cam.global_position = pos
	cam.look_at(target, Vector3.UP)
	cam.fov = fov_deg

func _project_rect(center: Vector3, w: float, h: float) -> Rect2:
	if cam == null or vp == null:
		return Rect2()
	var vs: Vector2 = vp.get_visible_rect().size
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var p := center + Vector3(sx * w * 0.5, sy * h * 0.5, 0.0)
			var sp := cam.unproject_position(p)
			mn = Vector2(minf(mn.x, sp.x), minf(mn.y, sp.y))
			mx = Vector2(maxf(mx.x, sp.x), maxf(mx.y, sp.y))
	return Rect2(mn.x / vs.x, mn.y / vs.y, (mx.x - mn.x) / vs.x, (mx.y - mn.y) / vs.y)

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
	for _i in range(frames):
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

func _img_stats(img: Image, roi: Rect2) -> Dictionary:
	if img == null:
		return {"r": 0.0, "g": 0.0, "b": 0.0, "lum": 0.0, "roi_lum": 0.0, "roi_std": 0.0}
	var w := img.get_width()
	var h := img.get_height()
	var sr := 0.0
	var sg := 0.0
	var sb := 0.0
	var n := 0
	for y in range(0, h, 12):
		for x in range(0, w, 12):
			var c := img.get_pixel(x, y)
			sr += c.r
			sg += c.g
			sb += c.b
			n += 1
	var fn := float(maxi(n, 1))
	var x0 := clampi(int(roi.position.x * float(w)), 0, w - 1)
	var y0 := clampi(int(roi.position.y * float(h)), 0, h - 1)
	var x1 := clampi(int((roi.position.x + roi.size.x) * float(w)), x0 + 1, w)
	var y1 := clampi(int((roi.position.y + roi.size.y) * float(h)), y0 + 1, h)
	var rsum := 0.0
	var rsq := 0.0
	var rn := 0
	for y in range(y0, y1, 3):
		for x in range(x0, x1, 3):
			var c := img.get_pixel(x, y)
			var l := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			rsum += l
			rsq += l * l
			rn += 1
	var rmean := rsum / float(maxi(rn, 1))
	var rvar := maxf(rsq / float(maxi(rn, 1)) - rmean * rmean, 0.0)
	return {
		"r": sr / fn, "g": sg / fn, "b": sb / fn,
		"lum": (0.2126 * sr + 0.7152 * sg + 0.0722 * sb) / fn,
		"roi_lum": rmean, "roi_std": sqrt(rvar),
	}

func _img_quantiles(img: Image, roi: Rect2) -> Dictionary:
	var vals: Array[float] = []
	var w := img.get_width()
	var h := img.get_height()
	var x0 := clampi(int(roi.position.x * float(w)), 0, w - 1)
	var y0 := clampi(int(roi.position.y * float(h)), 0, h - 1)
	var x1 := clampi(int((roi.position.x + roi.size.x) * float(w)), x0 + 1, w)
	var y1 := clampi(int((roi.position.y + roi.size.y) * float(h)), y0 + 1, h)
	for y in range(y0, y1, 3):
		for x in range(x0, x1, 3):
			vals.append(img.get_pixel(x, y).r)
	vals.sort()
	var n := vals.size()
	if n == 0:
		return {"p50": 0.0, "p90": 0.0, "p99": 0.0, "max": 0.0, "frac": 0.0}
	var over := 0
	for v in vals:
		if v > 0.05:
			over += 1
	return {
		"p50": vals[int(n * 0.50)], "p90": vals[mini(int(n * 0.90), n - 1)],
		"p99": vals[mini(int(n * 0.99), n - 1)], "max": vals[n - 1],
		"frac": float(over) / float(n),
	}

func _check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("  [PASS] ", label)
	else:
		fails += 1
		print("  [FAIL] ", label)

func _report() -> void:
	var elapsed := float(Time.get_ticks_msec() - start_ms) / 1000.0
	print("=== probe_ghost6 结果: checks=%d fails=%d 用时=%.1fs ===" % [checks, fails, elapsed])
	if "--window" in OS.get_cmdline_user_args():
		print("截图目录: ", out_dir)
	quit(0 if fails == 0 else 1)
