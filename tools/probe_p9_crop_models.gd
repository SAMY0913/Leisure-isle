extends SceneTree
## P3 —— 五种作物三阶段模型 + 九格农田接入 探针。
##
## 用法：
##   1) 数据/接入检查（headless 可跑）：
##      Godot_v4.7.2-stable_win64_console.exe --headless --path <proj> \
##          --script res://tools/probe_p9_crop_models.gd -- --out=D:/休闲小岛幻境/开发产物/P9/P3
##   2) 追加正式农田渲染截图（必须开窗口，不能 --headless）：
##      Godot_v4.7.2-stable_win64_console.exe --path <proj> \
##          --script res://tools/probe_p9_crop_models.gd -- --out=... --p3shots
##
## 覆盖范围：
##   A 三阶段数据契约（CROPS.stage_at/stage_index_at/stage_progress/边界）
##   B 15 个模型覆盖与几何基准（模型根=苗床土面中心、体量与三角面预算）
##   C 显示规则 display_stage（再生周期不缩回幼苗）
##   D 农田权威驱动（播种→时间推进→成熟→采收→一次性清除 / 再生保留）
##   E 正式场景接线的只读检查（main.farm()/main.farm_view() 与 facts 锚点）
##   F 时间推进由 main._tick 驱动视觉更新（不依赖探针手动 sync）
##   G export_state/restore_state 后按恢复状态重建显示
##   SHOT 正式九格农田实况截图（--p3shots）

const CROPS := preload("res://scripts/isle_crops.gd")
const FARM := preload("res://scripts/isle_farm.gd")
const MODELS := preload("res://scripts/isle_crop_models.gd")
const VIEW := preload("res://scripts/isle_farm_view.gd")
const M := preload("res://scripts/isle_math.gd")
const CAL := preload("res://scripts/isle_calendar.gd")

const SHOT_W := 1600
const SHOT_H := 1000
const OUT_DEFAULT := "D:/休闲小岛幻境/开发产物/P9/P3"
const SEED_COUNT := 20

var out_dir := OUT_DEFAULT
var do_shots := false
var _headless := false
var _main: Node = null
var _world: Dictionary = {}
var _fy: Dictionary = {}
var _cam: Camera3D = null
var _sv: SubViewport = null
var _shot_cam: Camera3D = null
var _shot_dir := ""
var _checks: Array = []
var _notes: Array = []
var _shots: Array = []
var _log_lines: Array = []
var _t0 := 0
## 统一基准模拟时刻（P2 真实 _sim_seconds 是 1e9 量级 Unix，这里同样用大数避免 0 附近退化）。
## 注意：绝对时刻会决定日历季节，进而决定 main 的季节视觉（冬季会把草地/树冠漂白）。
## 这里在 _run() 里取 5 月中旬（春季）作为基准，保证截图看到的是正常季节配色；
## 各断言只依赖相对增量，改这个值不影响它们。
var BASE_T := 1778415600.0


class MockInv extends RefCounted:
	## 与 P1 探针同口径的鸭子类型库存：get_count/remove_item/add_items。
	var items: Dictionary = {}

	func get_count(item_id: String) -> int:
		return int(items.get(item_id, 0))

	func remove_item(item_id: String, amount: int) -> bool:
		var have := get_count(item_id)
		if amount <= 0 or have < amount:
			return false
		var left := have - amount
		if left <= 0:
			items.erase(item_id)
		else:
			items[item_id] = left
		return true

	func add_items(item_deltas: Dictionary) -> bool:
		for k in item_deltas.keys():
			var n := int(item_deltas[k])
			if n > 0:
				items[str(k)] = get_count(str(k)) + n
		return true


func _initialize() -> void:
	_headless = DisplayServer.get_name() == "headless"
	_t0 = Time.get_ticks_msec()
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--out="):
			out_dir = s.substr(6)
		elif s == "--p3shots":
			do_shots = true
	_run.call_deferred()


func _log(line: String) -> void:
	print(line)
	_log_lines.append(line)


func _check(id: String, group: String, ok: bool, expect: String, actual: String) -> void:
	_checks.append({"id": id, "group": group, "ok": ok, "expect": expect, "actual": actual})
	_log("[P3] %s %s | expect: %s | actual: %s" % ["PASS" if ok else "FAIL", id, expect, actual])


func _note(id: String, detail: String) -> void:
	_notes.append({"id": id, "detail": detail})
	_log("[P3] NOTE %s: %s" % [id, detail])


func _new_inv(seeds: int = SEED_COUNT) -> Object:
	var inv := MockInv.new()
	for cid in CROPS.CROP_IDS:
		inv.items["seed_" + String(cid)] = seeds
	return inv


func _run() -> void:
	# 基准时刻＝2026-05-10 12:20（春季）：绝对时刻决定季节视觉，必须落在非冬季。
	BASE_T = CAL.to_local_seconds(2026, 5, 10, 12, 20)
	_log("[P3] start %s headless=%s out=%s base_t=%.0f" % [Time.get_datetime_string_from_system(), str(_headless), out_dir, BASE_T])
	_run_stage_data_checks()
	_run_model_checks()
	_run_display_rule_checks()
	_run_farm_authority_checks()
	await _boot_main_scene()
	_run_scene_wiring_checks()
	await _run_tick_driven_checks()
	_run_restore_checks()
	if do_shots:
		await _run_shots()
	else:
		_note("no_shots", "未传 --p3shots：未生成正式农田截图")
	await _finish()


# ============================================================ A 三阶段数据 =========
func _run_stage_data_checks() -> void:
	_check("stage.ids_count", "A", CROPS.STAGE_IDS.size() == 3, "3 个正式阶段", str(CROPS.STAGE_IDS.size()))
	_check("stage.ids_exact", "A", CROPS.STAGE_IDS == ["seedling", "growing", "mature"],
		"seedling,growing,mature（旧 seed/sprout/growing/ripening 不许残留）", str(CROPS.STAGE_IDS))
	_check("stage.thresholds", "A", CROPS.STAGE_THRESHOLDS == [0.0, 0.25, 1.0],
		"[0.0, 0.25, 1.0]", str(CROPS.STAGE_THRESHOLDS))
	_check("stage.labels", "A", CROPS.STAGE_LABELS == ["幼苗", "生长中", "成熟"], "幼苗,生长中,成熟", str(CROPS.STAGE_LABELS))
	var legacy := ["seed", "sprout", "ripening"]
	var leftover := 0
	for i in range(CROPS.STAGE_IDS.size()):
		if legacy.has(String(CROPS.STAGE_IDS[i])):
			leftover += 1
	_check("stage.no_legacy_ids", "A", leftover == 0, "0 个旧阶段 id", str(leftover))

	for cid in CROPS.CROP_IDS:
		var c := String(cid)
		var cyc := CROPS.first_maturity_seconds(c)
		var tag := "stage.%s" % c
		_check(tag + ".at_0_seedling", "A", CROPS.stage_at(c, 0.0, cyc) == "seedling", "seedling", CROPS.stage_at(c, 0.0, cyc))
		_check(tag + ".just_below_25_seedling", "A", CROPS.stage_at(c, cyc * 0.2499, cyc) == "seedling",
			"seedling（p=0.2499）", CROPS.stage_at(c, cyc * 0.2499, cyc))
		_check(tag + ".exactly_25_growing", "A", CROPS.stage_at(c, cyc * 0.25, cyc) == "growing",
			"growing（p=0.25 边界包含）", CROPS.stage_at(c, cyc * 0.25, cyc))
		_check(tag + ".just_below_1_growing", "A", CROPS.stage_at(c, cyc * 0.9999, cyc) == "growing",
			"growing（p=0.9999）", CROPS.stage_at(c, cyc * 0.9999, cyc))
		_check(tag + ".at_1_mature", "A", CROPS.stage_at(c, cyc, cyc) == "mature", "mature", CROPS.stage_at(c, cyc, cyc))
		_check(tag + ".over_1_mature", "A", CROPS.stage_at(c, cyc * 3.7, cyc) == "mature", "mature（超上限仍成熟）", CROPS.stage_at(c, cyc * 3.7, cyc))
		_check(tag + ".negative_seedling", "A", CROPS.stage_at(c, -1234.0, cyc) == "seedling",
			"seedling（负 elapsed 被 clamp 到 0）", CROPS.stage_at(c, -1234.0, cyc))
		_check(tag + ".index_boundary_25", "A", CROPS.stage_index_at(c, cyc * 0.25, cyc) == 1, "1", str(CROPS.stage_index_at(c, cyc * 0.25, cyc)))
		_check(tag + ".index_at_1", "A", CROPS.stage_index_at(c, cyc, cyc) == 2, "2", str(CROPS.stage_index_at(c, cyc, cyc)))
		_check(tag + ".index_in_range", "A", CROPS.stage_index_at(c, cyc * 0.5, cyc) >= 0 and CROPS.stage_index_at(c, cyc * 0.5, cyc) < CROPS.STAGE_IDS.size(),
			"0..2（不越界）", str(CROPS.stage_index_at(c, cyc * 0.5, cyc)))
		_check(tag + ".progress_clamped", "A", is_equal_approx(CROPS.stage_progress(c, -50.0, cyc), 0.0) and is_equal_approx(CROPS.stage_progress(c, cyc * 9.0, cyc), 1.0),
			"0.0 / 1.0", "%.4f / %.4f" % [CROPS.stage_progress(c, -50.0, cyc), CROPS.stage_progress(c, cyc * 9.0, cyc)])
		_check(tag + ".label_mapping", "A", CROPS.stage_label_at(c, 0.0, cyc) == "幼苗" and CROPS.stage_label_at(c, cyc * 0.5, cyc) == "生长中" and CROPS.stage_label_at(c, cyc, cyc) == "成熟",
			"幼苗/生长中/成熟", "%s/%s/%s" % [CROPS.stage_label_at(c, 0.0, cyc), CROPS.stage_label_at(c, cyc * 0.5, cyc), CROPS.stage_label_at(c, cyc, cyc)])

	# 异常输入不得越界/崩溃（cycle<=0 与未知作物）
	var bad_crop := CROPS.stage_at("dragonfruit", 10.0, 100.0) == ""
	_check("stage.unknown_crop_empty", "A", bad_crop, "空串", CROPS.stage_at("dragonfruit", 10.0, 100.0))
	var zero_cycle := CROPS.stage_at("wheat", 10.0, 0.0)
	_check("stage.zero_cycle_seedling", "A", zero_cycle == "seedling", "seedling（除零防御，进度为 0）", zero_cycle)
	var idx_zero := CROPS.stage_index_at("wheat", 10.0, 0.0)
	_check("stage.zero_cycle_index_safe", "A", idx_zero >= 0 and idx_zero < CROPS.STAGE_IDS.size(), "0..2", str(idx_zero))


# ============================================================ B 模型覆盖与几何 =========
func _run_model_checks() -> void:
	var all := MODELS.all_models()
	_check("model.all_count", "B", all.size() == 15, "5 作物 × 3 阶段 = 15", str(all.size()))
	var seen := {}
	var mesh_rids := {}
	var tri_total := 0
	for entry in all:
		var c := String((entry as Dictionary)["crop_id"])
		var st := String((entry as Dictionary)["stage_id"])
		var tag := "model.%s.%s" % [c, st]
		_check(tag + ".exists", "B", MODELS.has_model(c, st), "true", str(MODELS.has_model(c, st)))
		var mesh: ArrayMesh = MODELS.mesh_for(c, st)
		_check(tag + ".mesh", "B", mesh != null and mesh.get_surface_count() >= 1, "ArrayMesh 且至少 1 个 surface",
			"null" if mesh == null else "surfaces=%d" % mesh.get_surface_count())
		if mesh == null:
			continue
		mesh_rids[mesh.get_rid()] = str(entry)
		var tri: int = MODELS.triangle_count(c, st)
		tri_total += tri
		_check(tag + ".tri_budget", "B", tri >= 8 and tri <= 1600, "8..1600 三角面（低多边形）", str(tri))
		var bb: AABB = MODELS.bounds_of(c, st)
		_check(tag + ".root_on_ground", "B", bb.position.y >= -0.02 and bb.position.y <= 0.02,
			"模型最低点 = 苗床土面 y≈0", "aabb.position.y=%.4f" % bb.position.y)
		_check(tag + ".height_sane", "B", bb.size.y >= 0.03 and bb.size.y <= 1.30,
			"0.03..1.30 m（单株高度）", "h=%.3f" % bb.size.y)
		var hx := maxf(absf(bb.position.x), absf(bb.position.x + bb.size.x))
		var hz := maxf(absf(bb.position.z), absf(bb.position.z + bb.size.z))
		_check(tag + ".footprint_inside_slot", "B", hx <= 0.56 and hz <= 0.56,
			"XZ 半幅 ≤0.56 m（1×1 苗床，不侵入邻格）", "x=%.3f z=%.3f" % [hx, hz])
		seen[tag] = true
	_check("model.all_unique_keys", "B", seen.size() == 15, "15 个唯一 (crop,stage)", str(seen.size()))
	_check("model.mesh_instances_unique", "B", mesh_rids.size() == 15, "15 个不同 Mesh（无占位复用）", str(mesh_rids.size()))
	_check("model.tri_total", "B", tri_total <= 9000, "≤9000 三角面（15 模型合计）", str(tri_total))

	# 每个作物三个阶段的网格必须真的不同（不能只换材质/换阶段名）
	for cid in CROPS.CROP_IDS:
		var c := String(cid)
		var rids := []
		var tris := []
		for st in MODELS.STAGE_IDS:
			var m: ArrayMesh = MODELS.mesh_for(c, String(st))
			rids.append("" if m == null else str(m.get_rid()))
			tris.append(MODELS.triangle_count(c, String(st)))
		var same_rid: bool = rids[0] == rids[1] or rids[1] == rids[2] or rids[0] == rids[2]
		_check("model.%s.stages_distinct_mesh" % c, "B", not same_rid, "三阶段 Mesh 互不相同", str(rids))
		var diff_pairs := 0
		if tris[0] != tris[1]:
			diff_pairs += 1
		if tris[1] != tris[2]:
			diff_pairs += 1
		if tris[0] != tris[2]:
			diff_pairs += 1
		_check("model.%s.stages_distinct_geometry" % c, "B", diff_pairs >= 2, "至少两对阶段几何面数不同", "tris=%s" % str(tris))

	# 五种作物成熟形态必须可区分（高度/横向体量/面数签名互不相同）
	var sig := {}
	for cid in CROPS.CROP_IDS:
		var c := String(cid)
		var bb: AABB = MODELS.bounds_of(c, "mature")
		var s := "%.3f|%.3f|%.3f|%d" % [bb.size.y, bb.size.x, bb.size.z, MODELS.triangle_count(c, "mature")]
		sig[c] = s
	var uniq := {}
	for k in sig.keys():
		uniq[sig[k]] = k
	_check("model.crops_distinct_silhouette", "B", uniq.size() == 5, "5 个不同形态签名", str(sig))

	# 材质：顶点色必须真的打开（否则顶点色不显示，模型会变成一片白/单色）
	var mat: ShaderMaterial = MODELS.material()
	_check("model.material_shader", "B", mat != null and mat.shader != null, "ShaderMaterial + shader", "null" if mat == null else "ok")
	var vc := 0.0
	if mat != null:
		vc = float(mat.get_shader_parameter("use_vertex_color"))
	_check("model.material_vertex_color", "B", is_equal_approx(vc, 1.0), "use_vertex_color=1.0（顶点色可见）", str(vc))
	_check("model.material_shared", "B", MODELS.material() == mat, "同一材质实例（共享）", "true" if MODELS.material() == mat else "false")
	var mesh_sample: ArrayMesh = MODELS.mesh_for("wheat", "mature")
	var colors_present := false
	var arrays: Array = mesh_sample.surface_get_arrays(0)
	if arrays.size() > Mesh.ARRAY_COLOR:
		var col: Variant = arrays[Mesh.ARRAY_COLOR]
		colors_present = col is PackedColorArray and (col as PackedColorArray).size() > 0
	_check("model.mesh_has_vertex_colors", "B", colors_present, "ARRAY_COLOR 非空", str(colors_present))


# ============================================================ C 显示规则 =========
func _run_display_rule_checks() -> void:
	for cid in CROPS.CROP_IDS:
		var c := String(cid)
		for st in MODELS.STAGE_IDS:
			var s := String(st)
			_check("display.%s.%s.normal" % [c, s], "C", MODELS.display_stage(s, false) == s, s, MODELS.display_stage(s, false))
		_check("display.%s.regrow_seedling_not_shrunk" % c, "C", MODELS.display_stage("seedling", true) == "growing",
			"growing（再生期不缩回幼苗）", MODELS.display_stage("seedling", true))
		_check("display.%s.regrow_growing" % c, "C", MODELS.display_stage("growing", true) == "growing", "growing", MODELS.display_stage("growing", true))
		_check("display.%s.regrow_mature" % c, "C", MODELS.display_stage("mature", true) == "mature", "mature", MODELS.display_stage("mature", true))
	# 再生期显示阶段必须落在正式三阶段内
	var in_ids := true
	for v in [MODELS.display_stage("seedling", true), MODELS.display_stage("growing", true), MODELS.display_stage("mature", true)]:
		if not MODELS.STAGE_IDS.has(v):
			in_ids = false
	_check("display.regrow_uses_official_stage", "C", in_ids, "再生期显示仍是 seedling/growing/mature", "ok" if in_ids else "bad")


# ============================================================ D 农田权威驱动 =========
func _run_farm_authority_checks() -> void:
	var inv := _new_inv()
	var farm: Object = FARM.new(inv)
	farm.advance_to(BASE_T)
	# 一次性作物：小麦
	var pw: Dictionary = farm.plant(0, "wheat", "spring")
	_check("farm.plant_wheat", "D", bool(pw.get("ok", false)), "ok", str(pw))
	_check("farm.wheat_stage_seedling", "D", farm.stage_id(0) == "seedling", "seedling", farm.stage_id(0))
	_check("farm.wheat_regrow_false", "D", not bool(farm.is_regrow_cycle(0)), "false", str(farm.is_regrow_cycle(0)))
	farm.advance_to(BASE_T + CROPS.first_maturity_seconds("wheat") * 0.5)
	_check("farm.wheat_stage_growing", "D", farm.stage_id(0) == "growing", "growing", farm.stage_id(0))
	farm.advance_to(BASE_T + CROPS.first_maturity_seconds("wheat"))
	_check("farm.wheat_stage_mature", "D", farm.stage_id(0) == "mature", "mature", farm.stage_id(0))
	_check("farm.wheat_is_mature", "D", bool(farm.is_mature(0)), "true", str(farm.is_mature(0)))
	var hw: Dictionary = farm.harvest(0)
	_check("farm.wheat_harvest_removed", "D", bool(hw.get("plant_removed", false)) and bool(farm.is_empty(0)),
		"一次性作物采收后清格", "removed=%s empty=%s" % [str(hw.get("plant_removed", false)), str(farm.is_empty(0))])
	_check("farm.wheat_harvest_yield", "D", int(hw.get("produce_amount", 0)) == 1 and int(hw.get("seed_returned", 0)) == 1,
		"成品 1 + 首收返种 1", "produce=%s seed=%s" % [str(hw.get("produce_amount", 0)), str(hw.get("seed_returned", 0))])

	# 再生作物：玉米（两轮）
	var pc: Dictionary = farm.plant(1, "corn", "spring")
	_check("farm.plant_corn", "D", bool(pc.get("ok", false)), "ok", str(pc))
	var corn_cycle := CROPS.first_maturity_seconds("corn")
	var corn_regrow := CROPS.regrow_seconds("corn")
	# 注意：此刻 farm 的权威时间已被小麦那一段推进（CROPS.first_maturity_seconds("wheat")），播种时刻必须从 farm.now() 取。
	var t_corn := float(farm.now())
	farm.advance_to(t_corn + corn_cycle * 0.3)
	_check("farm.corn_stage_growing_cycle0", "D", farm.stage_id(1) == "growing" and not bool(farm.is_regrow_cycle(1)),
		"growing + is_regrow_cycle=false（首轮）", "%s / %s" % [farm.stage_id(1), str(farm.is_regrow_cycle(1))])
	farm.advance_to(t_corn + corn_cycle)
	_check("farm.corn_stage_mature", "D", farm.stage_id(1) == "mature", "mature", farm.stage_id(1))
	var hc: Dictionary = farm.harvest(1)
	_check("farm.corn_harvest_kept", "D", not bool(hc.get("plant_removed", true)) and not bool(farm.is_empty(1)),
		"再生作物采收后保留植株", "removed=%s empty=%s" % [str(hc.get("plant_removed", true)), str(farm.is_empty(1))])
	_check("farm.corn_regrow_cycle_true", "D", bool(farm.is_regrow_cycle(1)), "true（已进入再生周期）", str(farm.is_regrow_cycle(1)))
	_check("farm.corn_stage_raw_seedling", "D", farm.stage_id(1) == "seedling", "seedling（当前周期进度 0）", farm.stage_id(1))
	_check("farm.corn_display_growing", "D", MODELS.display_stage(farm.stage_id(1), bool(farm.is_regrow_cycle(1))) == "growing",
		"growing（成株体量，不缩回幼苗）", MODELS.display_stage(farm.stage_id(1), bool(farm.is_regrow_cycle(1))))
	_check("farm.corn_not_mature_right_after_harvest", "D", not bool(farm.is_mature(1)), "false（必须等下一轮成熟）", str(farm.is_mature(1)))
	farm.advance_to(t_corn + corn_cycle + corn_regrow * 0.5)
	_check("farm.corn_regrow_mid_growing", "D", MODELS.display_stage(farm.stage_id(1), bool(farm.is_regrow_cycle(1))) == "growing",
		"growing", MODELS.display_stage(farm.stage_id(1), bool(farm.is_regrow_cycle(1))))
	farm.advance_to(t_corn + corn_cycle + corn_regrow)
	_check("farm.corn_regrow_mature_again", "D", farm.stage_id(1) == "mature" and bool(farm.is_mature(1)),
		"mature（再生完成再成熟）", "%s / %s" % [farm.stage_id(1), str(farm.is_mature(1))])
	var hc2: Dictionary = farm.harvest(1)
	_check("farm.corn_second_harvest_no_seed", "D", int(hc2.get("seed_returned", -1)) == 0 and int(farm.harvest_count(1)) == 2,
		"第二收不返种 + harvest_count=2", "seed=%s count=%s" % [str(hc2.get("seed_returned", -1)), str(farm.harvest_count(1))])

	# 番茄再生同理（不同再生时间，验证走的是同一权威路径）
	var pt: Dictionary = farm.plant(2, "tomato", "spring")
	var t_tom := float(farm.now())
	farm.advance_to(t_tom + CROPS.first_maturity_seconds("tomato"))
	_check("farm.tomato_mature", "D", farm.stage_id(2) == "mature", "mature", farm.stage_id(2))
	farm.harvest(2)
	_check("farm.tomato_regrow_kept", "D", not bool(farm.is_empty(2)) and bool(farm.is_regrow_cycle(2)), "保留 + 再生周期",
		"empty=%s regrow=%s" % [str(farm.is_empty(2)), str(farm.is_regrow_cycle(2))])
	var td := MODELS.display_stage(farm.stage_id(2), bool(farm.is_regrow_cycle(2)))
	_check("farm.tomato_display_growing", "D", td == "growing", "growing", td)


# ============================================================ E 正式场景接线 =========
func _boot_main_scene() -> void:
	var ps: PackedScene = load("res://isle.tscn")
	if ps == null:
		_check("scene.load", "E", false, "isle.tscn loads", "load failed")
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
	_main.set("_paused", true)     # 冻结权威时间，让探针显式推进
	_main.set("_blending", "")
	_main.set("_auto_orbit", false)
	_cam = _main.get("_cam") as Camera3D
	var menu: Variant = _main.get("_menu")
	if menu != null:
		if menu.has_method("instant_finish"):
			menu.call("instant_finish")
		menu.set("menu_visible", false)
	_hide_ui_layers()
	if not _headless:
		_sv = SubViewport.new()
		_sv.size = Vector2i(SHOT_W, SHOT_H)
		_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_sv.msaa_3d = Viewport.MSAA_2X
		root.add_child(_sv)
		_sv.world_3d = root.world_3d
		_shot_cam = Camera3D.new()
		_shot_cam.near = 0.05
		_shot_cam.far = 1200.0
		_sv.add_child(_shot_cam)
		_shot_cam.current = true
	_main.call("_set_time_of_day", 12 * 60 + 20)
	var weather: Variant = _main.get("_weather")
	if weather != null and weather.has_method("set_manual_type"):
		weather.set_manual_type("clear")
		weather.set("_manual_blend", 1.0)
	_main.call("_update_weather", 0.0, true)
	await process_frame
	_world = _main.get("_world") as Dictionary
	_fy = _world.get("front_yard", {}) as Dictionary
	_check("scene.front_yard", "E", not _fy.is_empty(), "world facts 含 front_yard", "keys=%d" % _fy.size())
	_shot_dir = out_dir + "/shots/p3farm"
	if not _fy.is_empty():
		DirAccess.make_dir_recursive_absolute(_shot_dir)


func _hide_ui_layers() -> void:
	for key in ["_hud", "_ui_layer"]:
		var nd: Variant = _main.get(key)
		if nd is CanvasLayer:
			(nd as CanvasLayer).visible = false
	_hide_layers(_main)
	_hide_layers(root)


func _hide_layers(nd: Node) -> void:
	for c in nd.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
		_hide_layers(c)


func _run_scene_wiring_checks() -> void:
	if _fy.is_empty():
		return
	var farm: Variant = _main.call("farm")
	var view: Variant = _main.call("farm_view")
	_check("wire.farm_exists", "E", farm != null, "main 已创建 IsleFarm", "null" if farm == null else "ok")
	_check("wire.view_exists", "E", view != null, "main 已创建 IsleFarmView", "null" if view == null else "ok")
	if farm == null or view == null:
		return
	_check("wire.view_ready", "E", bool(view.call("is_ready")), "view.setup 成功", str(view.call("is_ready")))
	_check("wire.view_under_front_yard", "E", (view as Node).get_parent() == (_fy.get("node", null) as Node),
		"作物视图挂在 FrontYard 节点下（不重建场地）", str((view as Node).get_parent().name if (view as Node).get_parent() != null else "null"))
	# 九格锚点与 facts 完全对齐（土面高度 + 世界 XZ）
	var bed_y := float(_fy["beds"]["bed_top_y"])
	var rows: Array = _fy.get("slots", [])
	var max_d := 0.0
	for k in range(9):
		var w: Vector2 = (rows[k] as Dictionary)["world"]
		var want := Vector3(w.x, bed_y, w.y)
		var got: Vector3 = view.call("anchor_world_position", k)
		max_d = maxf(max_d, (got - want).length())
	_check("wire.anchor_positions", "E", max_d <= 0.001, "9 个锚点 = facts 格心 + bed_top_y", "max_err=%.5f m" % max_d)
	_check("wire.anchor_bed_y", "E", is_equal_approx(float(view.call("bed_top_y")), bed_y), "%.4f" % bed_y, "%.4f" % float(view.call("bed_top_y")))
	# 正式起点：没有作物 => 不显示任何模型（不得自动塞假作物）
	_check("wire.start_empty", "E", bool(farm.is_empty(0)) and int(view.call("visible_count")) == 0,
		"正式启动九格为空且无作物网格", "empty=%s visible=%d" % [str(farm.is_empty(0)), int(view.call("visible_count"))])
	# 注入库存后按真实农田状态填充（仅测试用；不改游戏启动行为）
	var inv := _new_inv()
	farm.set_inventory(inv)
	farm.advance_to(BASE_T)
	_main.set("_sim_seconds", BASE_T)
	var planted := 0
	for i in range(9):
		var c := String(CROPS.CROP_IDS[i % 5])
		var season := "summer" if c == "watermelon" else "spring"
		if bool((farm.plant(i, c, season) as Dictionary).get("ok", false)):
			planted += 1
	_check("wire.plant_9", "E", planted == 9, "9 格全部播种成功", str(planted))
	view.call("sync")
	var shown := 0
	for i in range(9):
		if not String(view.call("shown_key", i)).is_empty():
			shown += 1
	_check("wire.slot_models", "E", shown == 9, "9 格都显示模型", str(shown))
	# 同作物同阶段共享 Mesh（不重复生成几何）
	var m0: Mesh = view.call("mesh_at", 0)
	var m5: Mesh = view.call("mesh_at", 5)   # slot0 wheat / slot5 wheat，同阶段 => 必须同一资源
	var same_mesh := m0 != null and m5 != null and m0 == m5
	_check("wire.mesh_shared", "E", same_mesh, "同作物同阶段共享同一 Mesh 资源",
		"slot0=%s slot5=%s" % [str(m0.get_rid()) if m0 != null else "null", str(m5.get_rid()) if m5 != null else "null"])
	# 阶段变化只换 mesh；锚点/根节点位置不变
	var anchor_before: Array = []
	for k in range(9):
		anchor_before.append(view.call("anchor_world_position", k))
	farm.advance_to(BASE_T + 600.0)
	_main.set("_sim_seconds", BASE_T + 600.0)
	view.call("sync")
	var moved := 0.0
	for k in range(9):
		moved = maxf(moved, ((view.call("anchor_world_position", k) as Vector3) - (anchor_before[k] as Vector3)).length())
	_check("wire.anchor_stable_across_stage", "E", moved <= 0.000001, "阶段切换后锚点不动", "max_move=%.7f" % moved)
	_check("wire.stage_follows_farm", "E", String(view.call("shown_stage", 0)) == MODELS.display_stage(String(farm.stage_id(0)), bool(farm.is_regrow_cycle(0))),
		"显示阶段 = 权威阶段（经 display_stage）", "%s vs %s" % [String(view.call("shown_stage", 0)), MODELS.display_stage(String(farm.stage_id(0)), bool(farm.is_regrow_cycle(0)))])
	# 幂等：状态没变时 sync 不产生任何变更
	var changes := int(view.call("sync"))
	_check("wire.sync_idempotent", "E", changes == 0, "0 变更（不每帧重建）", str(changes))
	# 空格不占网格
	farm.advance_to(BASE_T + 600.0)
	var before_vis := int(view.call("visible_count"))
	view.call("sync")
	_check("wire.no_extra_mesh", "E", int(view.call("visible_count")) == before_vis, "可见模型数不无故增加", str(before_vis))


# ============================================================ F 时间推进驱动视觉 =========
func _run_tick_driven_checks() -> void:
	if _fy.is_empty():
		return
	var farm: Variant = _main.call("farm")
	var view: Variant = _main.call("farm_view")
	if farm == null or view == null:
		return
	# 关键路径：只改 main._sim_seconds（游戏唯一权威时间），让 main._tick 自己推进 farm 与视觉。
	_main.set("_paused", false)
	var t_before := BASE_T + 600.0
	_main.set("_sim_seconds", t_before)
	await create_timer(0.05).timeout
	var key_before := String(view.call("shown_key", 0))
	# P7-FINALIZE：小麦首次成熟阈值来自 isle_crops（现实时间映射：105 作物日 × 60s = 6300s），
	# 不得再硬编码旧的 3000；跳到成熟之后（模拟"时间跳跃"），不再手动 sync。
	var wheat_mature := CROPS.first_maturity_seconds("wheat")
	_main.set("_sim_seconds", BASE_T + wheat_mature + 1.0)
	await create_timer(0.35).timeout
	var key_after := String(view.call("shown_key", 0))
	_check("tick.time_drives_view", "F", key_before != key_after and key_after.ends_with("|mature"),
		"_sim_seconds 前进后由 main._tick 自动切到 mature", "%s -> %s" % [key_before, key_after])
	_check("tick.farm_consumed_time", "F", farm.stage_id(0) == "mature", "mature（farm 已消费权威时间）", farm.stage_id(0))
	# 一次性作物采收后由视觉同步清除（不在渲染层自行判断）
	var hw: Dictionary = farm.harvest(0)
	await create_timer(0.35).timeout
	_check("tick.one_shot_cleared", "F", bool(hw.get("plant_removed", false)) and int(view.call("visible_count")) == 8,
		"采收取走后该格模型消失（9->8）", "removed=%s visible=%d" % [str(hw.get("plant_removed", false)), int(view.call("visible_count"))])
	# 再生作物采收后仍显示植株，且是 growing（成株体量）
	var corn_idx := 1
	var before_key := String(view.call("shown_key", corn_idx))
	var enough := float(farm.get_slot(corn_idx).get("next_ready_at", 0.0))
	_main.set("_sim_seconds", enough + 1.0)
	await create_timer(0.35).timeout
	var mature_key := String(view.call("shown_key", corn_idx))
	var hc: Dictionary = farm.harvest(corn_idx)
	await create_timer(0.35).timeout
	var regrow_key := String(view.call("shown_key", corn_idx))
	_check("tick.regrow_kept_visible", "F", not bool(farm.is_empty(corn_idx)) and regrow_key != "",
		"玉米采收后植株仍在且可见", "empty=%s key=%s" % [str(farm.is_empty(corn_idx)), regrow_key])
	_check("tick.regrow_shows_growing", "F", regrow_key.ends_with("|growing"), "growing（不缩回幼苗）", "%s -> %s -> %s" % [before_key, mature_key, regrow_key])
	# 快进到下一轮成熟 => 重新显示成熟
	_main.set("_sim_seconds", float(farm.get_slot(corn_idx).get("next_ready_at", 0.0)) + 1.0)
	await create_timer(0.35).timeout
	var again := String(view.call("shown_key", corn_idx))
	_check("tick.regrow_matures_again", "F", again.ends_with("|mature"), "下一轮成熟显示 mature", again)


# ============================================================ G 存档恢复重建 =========
func _run_restore_checks() -> void:
	if _fy.is_empty():
		return
	var farm: Variant = _main.call("farm")
	if farm == null:
		return
	# 准备一个已知状态（含再生周期中的玉米）
	var st: Dictionary = farm.export_state()
	var inv2 := _new_inv()
	var farm2: Object = FARM.new(inv2)
	# 主时钟权威：恢复时传入当前权威时刻（IsleFarm.restore_state 的第二个参数），
	# 格内时间戳按同一 delta 平移，阶段/年龄完全保留。
	var t_now := float(farm.now())
	farm2.advance_to(t_now)
	var rr: bool = bool(farm2.restore_state(st, t_now))
	_check("restore.ok", "G", rr, "restore_state 成功（以当前主时钟恢复）", str(rr))
	# 全新视图节点（旧视图仍然存在，不能依赖它）
	var holder := Node3D.new()
	holder.name = "P3RestoreProbeView"
	_main.add_child(holder)
	var view2: Node3D = VIEW.new()
	holder.add_child(view2)
	var setup_ok := bool(view2.call("setup", farm2, _fy))
	_check("restore.view_setup", "G", setup_ok, "恢复后视图可独立重建", str(setup_ok))
	var view1: Variant = _main.call("farm_view")
	var mismatch := 0
	var empty_ok := true
	var first_bad := ""
	for k in range(9):
		var want := String(view1.call("shown_key", k))
		var got := String(view2.call("shown_key", k))
		if want != got:
			mismatch += 1
			if first_bad.is_empty():
				first_bad = "slot%d want=%s got=%s farm=%s farm2=%s" % [k, want, got, farm.stage_id(k), farm2.stage_id(k)]
		if bool(farm2.is_empty(k)) and not got.is_empty():
			empty_ok = false
	_check("restore.keys_match", "G", mismatch == 0, "9 格显示键与恢复前完全一致", "mismatch=%d %s" % [mismatch, first_bad])
	_check("restore.empty_stays_empty", "G", empty_ok, "空格恢复后不显示模型", str(empty_ok))
	var has_models := int(view2.call("visible_count")) > 0
	_check("restore.models_rebuilt", "G", has_models, "模型按恢复状态重建（不依赖旧节点）", str(int(view2.call("visible_count"))))
	holder.queue_free()


# ============================================================ SHOT 正式农田截图 =========
func _l2w(lx: float, lz: float) -> Vector2:
	var c := cos(M.HOUSE_YAW)
	var s := sin(M.HOUSE_YAW)
	return Vector2(M.HOUSE_X + lx * c + lz * s, M.HOUSE_Z - lx * s + lz * c)


func _terrain_l(lx: float, lz: float) -> float:
	var w := _l2w(lx, lz)
	return IsleWorld.surface_y(w.x, w.y)


func _pose_local(plx: float, plz: float, py: float, tlx: float, tlz: float, ty: float, fov: float) -> void:
	var pp := _l2w(plx, plz)
	var tt := _l2w(tlx, tlz)
	_main.call("_pose_look", Vector3(pp.x, py, pp.y), Vector3(tt.x, ty, tt.y), fov)


func _pose_play_default() -> void:
	_main.set("_theta", M.CAM_START_THETA)
	_main.set("_elev", 0.28)
	_main.set("_radius", M.CAM_START_R)
	_main.set("_cam_target", M.CAM_TARGET)
	_main.set("_fov", 42.0)
	_main.call("_apply_pose", _main.call("_play_pose"))


func _image_spread(img: Image) -> float:
	var mn := 1.0
	var mx := 0.0
	var step := maxi(1, int(img.get_width() / 48))
	for yy in range(0, img.get_height(), step):
		for xx in range(0, img.get_width(), step):
			var c := img.get_pixel(xx, yy)
			var v := (c.r + c.g + c.b) / 3.0
			mn = minf(mn, v)
			mx = maxf(mx, v)
	return mx - mn


func _shot(tag: String) -> void:
	if _headless:
		_check("shot_" + tag, "SHOT", false, "窗口模式渲染", "headless: 无帧缓冲")
		return
	_hide_ui_layers()
	var cp := _cam.global_position
	var gnd := IsleWorld.surface_y(cp.x, cp.z)
	var dy := cp.y - gnd
	_check("cam_above_ground_" + tag, "SHOT", dy >= 0.30, "相机在地面上方（不钻进地形）",
		"cam=(%.2f,%.2f,%.2f) dy=%.2f" % [cp.x, cp.y, cp.z, dy])
	_shot_cam.global_transform = _cam.global_transform
	_shot_cam.fov = _cam.fov
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = _sv.get_texture().get_image() if (_sv != null and _sv.get_texture() != null) else null
	if img == null:
		_check("shot_" + tag, "SHOT", false, "viewport image", "null")
		return
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	var pth := _shot_dir + "/" + tag + ".png"
	var spread := _image_spread(img)
	if spread < 0.02:
		for _i in range(6):
			await process_frame
		await create_timer(0.10).timeout
		await RenderingServer.frame_post_draw
		var img2: Image = _sv.get_texture().get_image() if _sv.get_texture() != null else null
		if img2 != null:
			img = img2
			spread = _image_spread(img)
		_log("[P3] shot %s retried (blank frame) spread=%.3f" % [tag, spread])
	_check("shot_not_blank_" + tag, "SHOT", spread >= 0.02, "画面非空白", "luma spread=%.3f" % spread)
	var err := img.save_png(pth)
	_log("[P3] shot %s %dx%d err=%d -> %s" % [tag, img.get_width(), img.get_height(), err, pth])
	if err == OK:
		_shots.append({"tag": tag, "path": pth, "size": [img.get_width(), img.get_height()]})
		_check("shot_" + tag, "SHOT", true, "真实引擎渲染截图", pth)
	else:
		_check("shot_" + tag, "SHOT", false, "真实引擎渲染截图", "save err=%d" % err)


func _run_shots() -> void:
	if _headless:
		_note("shots_headless", "--p3shots 需要窗口模式；本次为 headless，已跳过截图（不伪造）")
		return
	if _fy.is_empty():
		return
	var farm: Variant = _main.call("farm")
	var view: Variant = _main.call("farm_view")
	if farm == null or view == null:
		return
	# 正式九格真实布局（测试用填充）：后两排幼苗/生长中，前排成熟。
	# 严格通过 IsleFarm 权威接口播种 + 推进时间，视觉侧不写任何状态。
	_main.set("_paused", true)
	farm.advance_to(BASE_T)
	_main.set("_sim_seconds", BASE_T)
	var inv := _new_inv()
	farm.set_inventory(inv)
	# 截图用填充前先清空（前面的接线检查已经种过 9 格）；这只发生在探针里，正式游戏不会。
	farm.reset()
	var front := ["wheat", "corn", "watermelon", "tomato", "kale"]
	for i in range(5):
		var c := String(front[i])
		var season := "summer" if c == "watermelon" else "spring"
		farm.plant(i, c, season)
	# P7-FINALIZE：首次成熟阈值来自 isle_crops（现实时间映射），不得再硬编码 3100；
	# 前排全部推进到成熟：取前排 5 种作物的最大 first_maturity_seconds。
	var front_wait := 0.0
	for i in range(5):
		front_wait = maxf(front_wait, CROPS.first_maturity_seconds(String(front[i])))
	var t_mature := BASE_T + front_wait
	farm.advance_to(t_mature)
	_main.set("_sim_seconds", t_mature)
	var back := ["wheat", "corn", "tomato"]
	for i in range(3):
		var c := String(back[i])
		farm.plant(5 + i, c, "spring")
	# 后排推进到"各自首轮进度 50%"（growing 中段，不成熟）；取三种作物的最大 0.5×first_maturity。
	var back_wait := 0.0
	for i in range(3):
		back_wait = maxf(back_wait, CROPS.first_maturity_seconds(String(back[i])) * 0.5)
	var t_grow := t_mature + back_wait
	farm.advance_to(t_grow)
	_main.set("_sim_seconds", t_grow)
	farm.plant(8, "watermelon", "summer")   # 第 9 格保持幼苗（0 进度）
	view.call("sync")
	await create_timer(0.10).timeout
	var keys := []
	for k in range(9):
		keys.append("%d:%s" % [k, String(view.call("shown_key", k))])
	_log("[P3] 正式农田填充后显示：%s" % str(keys))
	_check("shots.filled_9", "SHOT", int(view.call("visible_count")) == 9, "9 格全部有作物", str(int(view.call("visible_count"))))
	_check("shots.front_mature", "SHOT",
		String(view.call("shown_stage", 0)) == "mature" and String(view.call("shown_stage", 1)) == "mature"
		and String(view.call("shown_stage", 2)) == "mature" and String(view.call("shown_stage", 3)) == "mature"
		and String(view.call("shown_stage", 4)) == "mature",
		"前排 5 格 mature", "0=%s 1=%s 2=%s 3=%s 4=%s" % [String(view.call("shown_stage", 0)), String(view.call("shown_stage", 1)), String(view.call("shown_stage", 2)), String(view.call("shown_stage", 3)), String(view.call("shown_stage", 4))])
	_check("shots.back_growing", "SHOT",
		String(view.call("shown_stage", 5)) == "growing" and String(view.call("shown_stage", 6)) == "growing"
		and String(view.call("shown_stage", 7)) == "growing",
		"后排 5..7 growing", "5=%s 6=%s 7=%s" % [String(view.call("shown_stage", 5)), String(view.call("shown_stage", 6)), String(view.call("shown_stage", 7))])
	_check("shots.slot8_seedling", "SHOT", String(view.call("shown_stage", 8)) == "seedling", "8 seedling", String(view.call("shown_stage", 8)))

	var pad := float(_fy["pad_y"])
	var fc: Vector2 = _fy["farm_center_local"]
	# 九格本地坐标（由 facts.slots 的世界坐标反算）：i 列 x=-5.85/-4.35/-2.85，
	# j 行 z=10.20(靠门)/11.70/13.20；farm_center_local=(-4.35,11.70)；苗床土面 y=pad+0.20=7.736。
	_pose_play_default()
	await _shot("10_farm_wide")
	_pose_local(fc.x, 7.55, pad + 3.25, fc.x, fc.y, pad + 0.15, 50.0)
	await _shot("11_farm_overview")
	_pose_local(fc.x, 13.05, pad + 0.62, fc.x, 10.20, pad + 0.40, 56.0)
	await _shot("12_farm_low_angle")
	_pose_local(-5.95, 8.55, pad + 1.45, -3.95, 10.55, pad + 0.42, 50.0)
	await _shot("13_mature_row_closeup")
	_pose_local(-4.60, 9.05, pad + 1.05, -4.90, 10.30, pad + 0.40, 45.0)
	await _shot("16_macro_wheat_corn")
	_pose_local(-6.05, 10.85, pad + 1.15, -4.15, 11.90, pad + 0.45, 50.0)
	await _shot("17_macro_tomato_kale")

	# 再生周期视觉：采收成熟玉米(1)与番茄(3) -> 植株保留，显示 growing
	_main.set("_sim_seconds", t_grow)
	farm.advance_to(t_grow)
	var hc: Dictionary = farm.harvest(1)
	var ht: Dictionary = farm.harvest(3)
	view.call("sync")
	await create_timer(0.10).timeout
	_check("shots.regrow_harvest", "SHOT", not bool(hc.get("plant_removed", true)) and not bool(ht.get("plant_removed", true)),
		"玉米/番茄采收后植株保留", "corn_removed=%s tomato_removed=%s" % [str(hc.get("plant_removed", true)), str(ht.get("plant_removed", true))])
	_check("shots.regrow_display_growing", "SHOT",
		String(view.call("shown_stage", 1)) == "growing" and String(view.call("shown_stage", 3)) == "growing",
		"采收后显示 growing（成株体量）", "1=%s 3=%s" % [String(view.call("shown_stage", 1)), String(view.call("shown_stage", 3))])
	_pose_local(fc.x, 7.55, pad + 3.25, fc.x, fc.y, pad + 0.15, 50.0)
	await _shot("14_regrow_after_harvest")
	_pose_local(-3.55, 8.55, pad + 1.30, -4.35, 10.75, pad + 0.45, 52.0)
	await _shot("15_regrow_closeup")

	# P7-FINALIZE 截图证据（用户要求"收获后空格"）：一次性作物（小麦）采收 -> 该格清空、模型消失。
	var h0: Dictionary = farm.harvest(0)
	view.call("sync")
	await create_timer(0.10).timeout
	_check("shots.one_shot_harvest_ok", "SHOT",
		bool(h0.get("ok", false)) and bool(h0.get("plant_removed", false)),
		"一次性作物(小麦)采收成功且植株移除", str(h0))
	_check("shots.one_shot_cleared_view", "SHOT",
		bool(farm.call("is_empty", 0)) and String(view.call("shown_key", 0)) == ""
			and int(view.call("visible_count")) == 8,
		"收获后该格清空、模型消失（9->8）",
		"empty=%s key=%s visible=%d" % [str(farm.call("is_empty", 0)),
			String(view.call("shown_key", 0)), int(view.call("visible_count"))])
	_pose_local(fc.x, 7.55, pad + 3.25, fc.x, fc.y, pad + 0.15, 50.0)
	await _shot("18_empty_after_harvest")


# ============================================================ finish =========
func _finish() -> void:
	var fail := 0
	for c in _checks:
		if not bool(c["ok"]):
			fail += 1
	var summary := "checks=%d fail=%d shots=%d notes=%d" % [_checks.size(), fail, _shots.size(), _notes.size()]
	_log("[P3] SUMMARY %s" % summary)
	for c in _checks:
		if not bool(c["ok"]):
			_log("[P3] FAIL %s: expect=%s actual=%s" % [String(c["id"]), String(c["expect"]), String(c["actual"])])
	DirAccess.make_dir_recursive_absolute(out_dir)
	var doc := {
		"schema": "p3/crop_models@1",
		"generated_at": Time.get_datetime_string_from_system(true),
		"engine": Engine.get_version_info(),
		"summary": {"checks": _checks.size(), "fail": fail, "shots": _shots.size(), "notes": _notes.size()},
		"result": "PASS" if fail == 0 else "FAIL",
		"checks": _checks,
		"notes": _notes,
		"shots": _shots,
		"stage_contract": {"ids": CROPS.STAGE_IDS, "labels": CROPS.STAGE_LABELS, "thresholds": CROPS.STAGE_THRESHOLDS},
		"models": MODELS.all_models(),
		"elapsed_s": float(Time.get_ticks_msec() - _t0) / 1000.0,
	}
	var jf := FileAccess.open(out_dir + "/probe_p9_crop_models.json", FileAccess.WRITE)
	if jf != null:
		jf.store_string(JSON.stringify(doc, "  "))
		jf.close()
	var lf := FileAccess.open(out_dir + "/probe_p9_crop_models.log", FileAccess.WRITE)
	if lf != null:
		for line in _log_lines:
			lf.store_line(String(line))
		lf.store_line("[P3] SUMMARY %s" % summary)
		lf.close()
	print("[P3] SUMMARY %s" % summary)
	if fail == 0:
		print("[P3] RESULT PASS")
	else:
		print("[P3] RESULT FAIL")
	quit(0 if fail == 0 else 1)
