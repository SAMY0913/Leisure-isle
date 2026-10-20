extends SceneTree

## T7 画质真实接线探针（headless）：
## 1) 五档 24 个参数键是否真的被渲染/环境/视口消费（而不是只改 UI 状态）；
## 2) 菜单高级覆盖 post_ao 三态与实际渲染是否一致（别名修复回归）；
## 3) 覆盖经菜单 -> main 的完整往返。
## 运行：console exe --headless --path 项目 --script res://tools/probe_quality_override_t7.gd
## 输出：D:/休闲小岛幻境/开发产物/logs/probe_quality_override_t7.log；退出码非 0 表示有 FAIL。

const MenuScript := preload("res://scripts/menu.gd")
const S := preload("res://scripts/isle_settings.gd")
const Q := preload("res://scripts/isle_quality.gd")

const LOG_PATH := "D:/休闲小岛幻境/开发产物/logs/probe_quality_override_t7.log"

var _pass := 0
var _fail := 0
var _fail_names: Array = []
var _logs: Array = []

func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		_fail_names.append(name)
	_log(("PASS  " if cond else "FAIL  ") + name + ("" if detail.is_empty() else "  [" + detail + "]"))

func _log(s: String) -> void:
	print(s)
	_logs.append(s)

func _eq(a: Variant, b: Variant, eps: float = 1e-5) -> bool:
	if a is float or b is float or a is int or b is int:
		return absf(float(a) - float(b)) <= eps
	return a == b

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("D:/休闲小岛幻境/开发产物/logs")
	_log("=== probe_quality_override_t7 start ===")

	await _test_menu_alias()
	await _test_main_wiring()

	_log("RESULT %d/%d pass, %d fail" % [_pass, _pass + _fail, _fail])
	if _fail > 0:
		_log("FAILS: " + ", ".join(_fail_names))
	var f := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_logs) + "\n")
		f.close()
	quit(1 if _fail > 0 else 0)

# ---------------------------------------------------------------- menu 三态 --
func _test_menu_alias() -> void:
	_log("--- menu post_ao tri-state ---")
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 800)
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(vp)
	await process_frame
	var menu = MenuScript.new()
	vp.add_child(menu)
	await process_frame
	await process_frame
	menu._layout()
	await process_frame
	var btn: Button = (menu.get("_quality_override_buttons") as Dictionary).get("post_ao", null)
	_check("menu_ao_button_exists", btn != null)

	# q0 预设 posts_ao=false：跟随态应显示“关”，循环应 true -> false -> 跟随
	menu.set_settings({"quality": 0, "quality_overrides": {}})
	await process_frame
	if btn != null:
		_check("menu_q0_follow_shows_off", btn.text.contains("关"), btn.text)
	menu._cycle_override("post_ao")
	await process_frame
	var ov1: Dictionary = menu.get_settings()["quality_overrides"]
	_check("menu_q0_cycle1_negate", ov1.has("post_ao") and bool(ov1["post_ao"]) == true, str(ov1))
	if btn != null:
		_check("menu_q0_cycle1_shows_on", btn.text == "开", btn.text)
	menu._cycle_override("post_ao")
	await process_frame
	var ov2: Dictionary = menu.get_settings()["quality_overrides"]
	_check("menu_q0_cycle2_preset", ov2.has("post_ao") and bool(ov2["post_ao"]) == false, str(ov2))
	menu._cycle_override("post_ao")
	await process_frame
	var ov3: Dictionary = menu.get_settings()["quality_overrides"]
	_check("menu_q0_cycle3_follow", ov3.is_empty(), str(ov3))

	# q2 预设 posts_ao=true：循环应 false -> true -> 跟随
	menu.set_settings({"quality": 2, "quality_overrides": {}})
	await process_frame
	if btn != null:
		_check("menu_q2_follow_shows_on", btn.text.contains("开"), btn.text)
	menu._cycle_override("post_ao")
	await process_frame
	var ov4: Dictionary = menu.get_settings()["quality_overrides"]
	_check("menu_q2_cycle1_negate", ov4.has("post_ao") and bool(ov4["post_ao"]) == false, str(ov4))
	menu._cycle_override("post_ao")
	await process_frame
	var ov5: Dictionary = menu.get_settings()["quality_overrides"]
	_check("menu_q2_cycle2_preset", ov5.has("post_ao") and bool(ov5["post_ao"]) == true, str(ov5))
	menu._cycle_override("post_ao")
	await process_frame
	_check("menu_q2_cycle3_follow", (menu.get_settings()["quality_overrides"] as Dictionary).is_empty())

	# 存档键契约：外部仍存 UI 键 post_ao，不出现 posts_ao
	menu.set_settings({"quality_overrides": {"posts_ao": false}})
	await process_frame
	var ov_alias: Dictionary = menu.get_settings()["quality_overrides"]
	_check("menu_alias_kept_external_post_ao", ov_alias.has("post_ao") and not ov_alias.has("posts_ao"), str(ov_alias))
	menu.set_settings({"quality_overrides": {}})
	vp.queue_free()
	await process_frame

# ------------------------------------------------------------ main 渲染接线 --
func _test_main_wiring() -> void:
	_log("--- main 24-key wiring ---")
	var main = load("res://isle.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	await process_frame
	# 固定为可复现默认设置（探针环境可能已有 user:// 配置）
	main.set("_settings", S.defaults())
	main.set("_quality", 2)
	main.call("_apply_user_settings", false)
	await process_frame
	main.call("_update_lighting")
	await process_frame
	var pal: Dictionary = main.get("_pal")
	_check("main_palette_ready", pal.has("fogNear") and pal.has("bloom"), str(pal.keys().slice(0, 4)))

	var vp: Viewport = main.get_viewport()
	var env: Environment = main.get("_env")
	var sm: ShaderMaterial = main.get("_sea_mat")
	var skm: ShaderMaterial = main.get("_sky_mat")
	var aom: ShaderMaterial = main.get("_post_ao_mat")
	var aomi: MeshInstance3D = main.get("_post_ao_mi")
	var world: Node = main.get_node_or_null("World")
	var sea: MeshInstance3D = main.get_node_or_null("Sea")
	var gl_get := func(k: String, dflt: Variant) -> Variant:
		var v: Variant = sm.get_shader_parameter(k)
		return dflt if v == null else v
	var sk_get := func(k: String, dflt: Variant) -> Variant:
		var v: Variant = skm.get_shader_parameter(k)
		return dflt if v == null else v

	for q in range(5):
		main.call("_apply_quality", q)
		main.call("_update_lighting")
		await process_frame
		await process_frame
		var p: Dictionary = (main.get("_quality_state") as Dictionary).duplicate(true)
		var tag := "q%d" % q
		var pre: Dictionary = Q.preset(q)
		_check(tag + "_quality_state_matches_preset", _eq(float(p.get("msaa_3d", -1)), float(pre["msaa_3d"])), "msaa")
		_check(tag + "_msaa_3d", _eq(vp.msaa_3d, p["msaa_3d"]), "%d vs %d" % [vp.msaa_3d, int(p["msaa_3d"])])
		_check(tag + "_msaa_2d", _eq(vp.msaa_2d, p["msaa_2d"]), "%d vs %d" % [vp.msaa_2d, int(p["msaa_2d"])])
		_check(tag + "_screen_space_aa", _eq(vp.screen_space_aa, p["screen_space_aa"]), "%d" % vp.screen_space_aa)
		_check(tag + "_taa", vp.use_taa == bool(p["taa"]), str(vp.use_taa))
		_check(tag + "_scaling_3d_scale", _eq(vp.scaling_3d_scale, p["scaling_3d_scale"]), "%.3f" % vp.scaling_3d_scale)
		_check(tag + "_scaling_3d_mode", _eq(vp.scaling_3d_mode, p["scaling_3d_mode"]), "%d" % vp.scaling_3d_mode)
		_check(tag + "_max_fps", _eq(Engine.max_fps, p["max_fps"]), "%d" % Engine.max_fps)
		_check(tag + "_tonemap", _eq(env.tonemap_mode, main.call("_tonemap_enum", int(p["tonemap"]))), "%d" % env.tonemap_mode)
		_check(tag + "_exposure", _eq(env.tonemap_exposure, p["exposure"]), "%.3f" % env.tonemap_exposure)
		var exp_glow := float(pal["bloom"]) * 1.15 * clampf(float(p["glow_strength"]), 0.0, 1.5)
		_check(tag + "_glow_strength", _eq(env.glow_intensity, exp_glow, 1e-4), "%.4f vs %.4f" % [env.glow_intensity, exp_glow])
		_check(tag + "_glow_enabled_tier", env.glow_enabled == (q >= 1), str(env.glow_enabled))
		_check(tag + "_sky_cloud_detail", _eq(float(sk_get.call("cloud_detail", -1.0)), float(p["sky_cloud_detail"])), "%.1f" % float(sk_get.call("cloud_detail", -1.0)))
		_check(tag + "_sea_wave_detail", _eq(int(gl_get.call("wave_detail", -1)), int(p["sea_wave_detail"])), "%d" % int(gl_get.call("wave_detail", -1)))
		_check(tag + "_sea_foam", _eq(float(gl_get.call("foam_amount", -1.0)), float(p["sea_foam"])), "%.3f" % float(gl_get.call("foam_amount", -1.0)))
		_check(tag + "_sea_reflection", _eq(float(gl_get.call("island_refl", -1.0)), float(p["sea_reflection"])), "%.3f" % float(gl_get.call("island_refl", -1.0)))
		_check(tag + "_sea_ssr", _eq(float(gl_get.call("ssr_strength", -1.0)), float(p["sea_ssr"])), "%.3f" % float(gl_get.call("ssr_strength", -1.0)))
		var sp: Dictionary = Q.sea_params(p)
		_check(tag + "_sea_normal_detail", _eq(float(gl_get.call("sea_normal_detail", -1.0)), float(sp["sea_normal_detail"])), "%.2f" % float(gl_get.call("sea_normal_detail", -1.0)))
		_check(tag + "_sea_foam_detail", _eq(float(gl_get.call("sea_foam_detail", -1.0)), float(sp["sea_foam_detail"])), "%.2f" % float(gl_get.call("sea_foam_detail", -1.0)))
		_check(tag + "_sea_refl_detail", _eq(float(gl_get.call("sea_refl_detail", -1.0)), float(sp["sea_refl_detail"])), "%.2f" % float(gl_get.call("sea_refl_detail", -1.0)))
		_check(tag + "_light_budget", _eq(main.get("_light_budget"), p["light_budget"]), "%d" % int(main.get("_light_budget")))
		# 海面网格细分
		var want_sub := clampi(int(round(180.0 * clampf(float(p["sea_mesh_scale"]), 0.5, 2.0))), 96, 320)
		var got_sub := -1
		if sea != null and sea.mesh is PlaneMesh:
			got_sub = (sea.mesh as PlaneMesh).subdivide_width
		_check(tag + "_sea_mesh_subdiv", got_sub == want_sub, "%d vs %d" % [got_sub, want_sub])
		# 草密度
		var gr := clampf(float(p["grass_density"]), 0.0, 1.0)
		var exp_grass := int(round(float(main.get("_grass_total")) * gr))
		_check(tag + "_grass_density", int(main.get("_grass_visible_count")) == exp_grass and int(main.get("_grass_total")) > 0, "%d/%d" % [int(main.get("_grass_visible_count")), int(main.get("_grass_total"))])
		# 粒子密度
		var pr := clampf(float(p["particle_density"]), 0.1, 1.5)
		var fx: Dictionary = main.get("_fx")
		var p_ok := true
		var p_dbg := ""
		for key in ["smoke", "petals", "fireflies"]:
			var entry: Dictionary = fx.get(key, {})
			var node = entry.get("node", null)
			if node is GPUParticles3D:
				var gp := node as GPUParticles3D
				var base := int(gp.get_meta("base_amount", gp.amount))
				var exp_amt := maxi(6, int(round(float(base) * pr)))
				p_ok = p_ok and gp.amount == exp_amt
				p_dbg += "%s=%d/%d " % [key, gp.amount, exp_amt]
		_check(tag + "_particle_density", p_ok, p_dbg)
		# AO 开关 + 强度
		var exp_on := bool(p["posts_ao"])
		var exp_s := 0.0
		if exp_on:
			var raw_s := clampf(float(p["ao_strength"]), 0.0, 1.0)
			exp_s = 0.35 if raw_s <= 0.001 else raw_s
		_check(tag + "_ao_visible", aomi != null and aomi.visible == exp_on, "vis=%s exp=%s" % [str(aomi.visible if aomi != null else false), str(exp_on)])
		_check(tag + "_ao_strength_uniform", _eq(float(aom.get_shader_parameter("ao_strength")), exp_s), "%.3f vs %.3f" % [float(aom.get_shader_parameter("ao_strength")), exp_s])
		# fog_scale：真实写入雾距（headless 用 debug 字段断言，值 = 调色板雾距 × 档位系数）
		var fs := clampf(float(p["fog_scale"]), 0.6, 1.4)
		var exp_near := float(pal["fogNear"]) * fs
		var exp_far := float(pal["fogFar"]) * fs
		_check(tag + "_fog_scale_near", _eq(float(main.get("_dbg_fog_near")), exp_near, 1e-4), "%.3f vs %.3f" % [float(main.get("_dbg_fog_near")), exp_near])
		_check(tag + "_fog_scale_far", _eq(float(main.get("_dbg_fog_far")), exp_far, 1e-4), "%.3f vs %.3f" % [float(main.get("_dbg_fog_far")), exp_far])
		# lod_bias：真实缩放岩石近/远 LOD 可见范围
		var lb := clampf(float(p["lod_bias"]), 0.6, 1.6)
		var lod_n := 0
		var lod_ok := true
		if world != null:
			for child in world.find_children("Rocks_*", "", true, false):
				var nm := String(child.name)
				if child is GeometryInstance3D:
					if nm.begins_with("Rocks_") and nm.ends_with("_Near"):
						lod_n += 1
						lod_ok = lod_ok and absf(float((child as GeometryInstance3D).visibility_range_end) - 28.0 * lb) < 1e-4
					elif nm.begins_with("Rocks_") and nm.ends_with("_Far"):
						lod_ok = lod_ok and absf(float((child as GeometryInstance3D).visibility_range_begin) - 24.0 * lb) < 1e-4
		_check(tag + "_lod_bias", lod_n > 0 and lod_ok, "near_nodes=%d bias=%.2f" % [lod_n, lb])
		# volumetric_fog：现阶段所有档都诚实关闭（引擎体积雾对全 unshaded 管线不可见）
		_check(tag + "_volumetric_fog_honest_off", env.volumetric_fog_enabled == false and bool(p["volumetric_fog"]) == false, str(env.volumetric_fog_enabled))

	# ---- 高级覆盖：真实渲染路径 ----
	_log("--- override -> render ---")
	var base_settings: Dictionary = S.defaults()
	main.set("_settings", base_settings.duplicate(true))
	main.call("_apply_user_settings", false)
	await process_frame

	# q2 + 覆盖 post_ao=false：AO 必须真的关掉
	var st: Dictionary = main.get("_settings").duplicate(true)
	st["quality"] = 2
	st["quality_overrides"] = {"post_ao": false}
	main.set("_settings", st)
	main.call("_apply_user_settings", false)
	main.call("_apply_quality", 2)
	await process_frame
	var qs: Dictionary = main.get("_quality_state")
	_check("override_ao_off_state_norm", qs.has("posts_ao") and bool(qs["posts_ao"]) == false and not qs.has("post_ao"), str(qs.get("posts_ao")))
	_check("override_ao_off_render", aomi.visible == false and _eq(float(aom.get_shader_parameter("ao_strength")), 0.0), "vis=%s s=%.3f" % [str(aomi.visible), float(aom.get_shader_parameter("ao_strength"))])
	_check("override_ao_off_summary_custom", String(main.get("_hud_quality_label")) == "自定义", String(main.get("_hud_quality_label")))

	# q0 + 覆盖 post_ao=true：低档手动打开要给可见默认强度 0.35
	st["quality"] = 0
	st["quality_overrides"] = {"post_ao": true}
	main.set("_settings", st)
	main.call("_apply_user_settings", false)
	main.call("_apply_quality", 0)
	await process_frame
	_check("override_ao_on_q0_visible", aomi.visible == true, str(aomi.visible))
	_check("override_ao_on_q0_default_strength", _eq(float(aom.get_shader_parameter("ao_strength")), 0.35), "%.3f" % float(aom.get_shader_parameter("ao_strength")))

	# 覆盖 sea_ssr 也必须进入 shader
	st["quality"] = 0
	st["quality_overrides"] = {"sea_ssr": 0.7}
	main.set("_settings", st)
	main.call("_apply_user_settings", false)
	main.call("_apply_quality", 0)
	await process_frame
	_check("override_ssr_render", _eq(float(gl_get.call("ssr_strength", -1.0)), 0.7), "%.3f" % float(gl_get.call("ssr_strength", -1.0)))

	# 清空覆盖恢复预设
	st["quality_overrides"] = {}
	main.set("_settings", st)
	main.call("_apply_user_settings", false)
	main.call("_apply_quality", 0)
	await process_frame
	var qs2: Dictionary = main.get("_quality_state")
	_check("override_clear_restores_q0_ao", bool(qs2["posts_ao"]) == false and aomi.visible == false, "posts_ao=%s vis=%s" % [str(qs2["posts_ao"]), str(aomi.visible)])
	_check("override_clear_summary_preset", String(main.get("_hud_quality_label")) == Q.label(0), String(main.get("_hud_quality_label")))

	# ---- 菜单存档 -> main 完整往返 ----
	var vp2 := SubViewport.new()
	vp2.size = Vector2i(1280, 800)
	vp2.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(vp2)
	await process_frame
	var menu = MenuScript.new()
	vp2.add_child(menu)
	await process_frame
	await process_frame
	menu._layout()
	await process_frame
	menu.set_settings({"quality": 2, "quality_overrides": {}})
	menu._cycle_override("post_ao")   # q2 预设开 -> 覆盖成关
	await process_frame
	var ms: Dictionary = menu.get_settings()
	_check("menu_roundtrip_saved_override", (ms["quality_overrides"] as Dictionary).has("post_ao") and bool((ms["quality_overrides"] as Dictionary)["post_ao"]) == false, str(ms["quality_overrides"]))
	main.call("_on_settings_changed", ms)
	await process_frame
	await process_frame
	_check("menu_roundtrip_render_off", aomi.visible == false, str(aomi.visible))
	_check("menu_roundtrip_state_norm", bool((main.get("_quality_state") as Dictionary).get("posts_ao", true)) == false)
	vp2.queue_free()
	await process_frame
	main.queue_free()
	await process_frame
