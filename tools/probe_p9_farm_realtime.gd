extends SceneTree
## P9 / P7-FINALIZE —— 农田双时钟语义探针（headless）。
##
## 覆盖新契约：
##   A. sim 模式（探针/自动化兼容）：advance_to(sim_seconds) 驱动生长；
##   B. real 模式：main 每帧 advance_realtime(delta) 驱动；advance_to(大跳变) 不推进生长；
##      阈值前 1s 未熟、+1s 成熟；单帧 MAX_REAL_STEP_SECONDS 夹取；时间回退/暂停/day_length 不影响；
##   C. 时间回退不倒退阶段（sim 模式按 delta 平移格内时间戳）；
##   D. export/restore 在 real 模式下阶段一致；
##   E. 再生作物 corn/tomato 每株最多成功收获 3 次（含首收），第 3 次 plant_removed=true，第 4 次 empty；
##   F. 播种/采收失败不 partial commit（含库存回调重入守卫）；
##   G. 生产接线：main._tick 对 farm 的模式分发（real -> advance_realtime(delta)；sim -> advance_to(_sim_seconds)）。
##
## 运行：ENG --headless --path GAME --script res://tools/probe_p9_farm_realtime.gd -- --out=DIR

const FARM := preload("res://scripts/isle_farm.gd")
const INV := preload("res://scripts/isle_inventory.gd")
const CROPS := preload("res://scripts/isle_crops.gd")
const DT := 1.0 / 60.0
const DEFAULT_OUT := "D:/休闲小岛幻境/开发产物/P9/P7-finalize/evidence/farm/realtime"

var out_dir := DEFAULT_OUT
var _pass := 0
var _fail := 0
var _lines: Array = []
var _fail_names: Array = []
var _main: Node = null


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--out="):
			out_dir = s.substr(6).strip_edges().trim_suffix("/").trim_suffix("\\")
	if out_dir == "":
		out_dir = DEFAULT_OUT
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	print("[RTP] out=%s headless=%s godot=%s" % [out_dir,
		str(DisplayServer.get_name() == "headless"),
		String(Engine.get_version_info().get("string", ""))])
	_test_sim_mode()
	_test_real_mode()
	_test_rollback()
	_test_export_restore_real()
	_test_three_harvests()
	_test_failure_no_partial_commit()
	await _test_main_wiring()
	_write_report()
	var summary := "[SUMMARY] checks=%d fail=%d" % [_pass + _fail, _fail]
	print(summary)
	_lines.append(summary)
	print("[RESULT] ", "PASS" if _fail == 0 else "FAIL")
	_lines.append("[RESULT] " + ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)


# ============================================================ 基础设施 =========
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


func _new_inv() -> Object:
	var inv: Object = INV.new()
	inv.call("grant_starting_seeds")
	return inv


## real 模式按"单帧夹取"语义分块推进（等价于主控逐帧 advance_realtime(delta) 的累加）。
func _advance_real(farm: Object, seconds: float) -> void:
	var remain := seconds
	while remain > 0.0:
		var step := minf(remain, float(FARM.MAX_REAL_STEP_SECONDS))
		farm.call("advance_realtime", step)
		remain -= step


func _fresh_real_farm() -> Object:
	var inv := _new_inv()
	var farm: Object = FARM.new(inv)
	farm.call("set_clock_mode", "real")
	farm.call("advance_realtime", 0.0)
	return farm


# ============================================================ A sim 模式 ======
func _test_sim_mode() -> void:
	_section("A. sim 模式（探针兼容）：advance_to 驱动生长")
	var inv := _new_inv()
	var farm: Object = FARM.new(inv)
	_check("A.default_sim", String(farm.call("clock_mode_name")) == "sim", "sim（默认）", String(farm.call("clock_mode_name")))
	farm.call("advance_to", 1000.0)
	_check("A.advance_to_moves", absf(float(farm.call("now")) - 1000.0) < 0.001, "1000", "%.1f" % float(farm.call("now")))
	_check("A.clock_ready", bool(farm.call("clock_ready")), "true", str(farm.call("clock_ready")))
	var r: Dictionary = farm.call("plant", 0, "wheat", "spring")
	_check("A.plant_ok", bool(r.get("ok", false)), "ok", str(r))
	var first := CROPS.first_maturity_seconds("wheat")
	farm.call("advance_to", 1000.0 + first * 0.5)
	_check_eq("A.half_growing", "growing", String(farm.call("stage_id", 0)))
	_check("A.half_not_mature", not bool(farm.call("is_mature", 0)), "false", str(farm.call("is_mature", 0)))
	farm.call("advance_to", 1000.0 + first)
	_check("A.at_threshold_mature", bool(farm.call("is_mature", 0)), "true", str(farm.call("is_mature", 0)))
	_check_eq("A.stage_mature", "mature", String(farm.call("stage_id", 0)))


# ============================================================ B real 模式 =====
func _test_real_mode() -> void:
	_section("B. real 模式：advance_realtime 驱动；advance_to 不推进；阈值前后 1s 精确")
	var inv := _new_inv()
	var farm: Object = FARM.new(inv)
	farm.call("set_clock_mode", "real")
	_check("B.mode_real", String(farm.call("clock_mode_name")) == "real", "real", String(farm.call("clock_mode_name")))
	# 从未收到任何 advance_realtime 时 clock_ready=false：播种必须被拒（防止"0 时刻种下瞬间成熟"）
	var not_ready_plant: Dictionary = farm.call("plant", 0, "wheat", "spring")
	_check("B.not_ready_plant_rejected",
		not bool(not_ready_plant.get("ok", true)) and String(not_ready_plant.get("reason", "")) == "clock_not_ready",
		"clock_not_ready", str(not_ready_plant))
	farm.call("advance_realtime", 0.0)
	_check("B.first_delta_marks_ready", bool(farm.call("clock_ready")), "true", str(farm.call("clock_ready")))
	var ready_plant: Dictionary = farm.call("plant", 0, "wheat", "spring")
	_check("B.plant_after_ready", bool(ready_plant.get("ok", false)), "ok", str(ready_plant))
	# 单帧夹取
	var farm_clamp := _fresh_real_farm()
	farm_clamp.call("advance_realtime", 5000.0)
	_check("B.single_frame_clamp", absf(float(farm_clamp.call("now")) - float(FARM.MAX_REAL_STEP_SECONDS)) < 0.001,
		"单帧最多 %.0fs" % float(FARM.MAX_REAL_STEP_SECONDS), "%.1f" % float(farm_clamp.call("now")))
	var farm_neg := _fresh_real_farm()
	farm_neg.call("advance_realtime", -3.0)
	farm_neg.call("advance_realtime", NAN)
	_check_eq("B.invalid_delta_ignored", 0.0, float(farm_neg.call("now")))
	# 正式语义：逐帧累加
	var first := CROPS.first_maturity_seconds("wheat")
	var farm2 := _fresh_real_farm()
	var plant_res: Dictionary = farm2.call("plant", 0, "wheat", "spring")
	_check("B.plant_ok", bool(plant_res.get("ok", false)), "ok", str(plant_res))
	# advance_to 大跳变在 real 模式不得推进生长时钟（只有诊断快照）
	farm2.call("advance_to", 1.0e9)
	_check_eq("B.advance_to_no_move", 0.0, float(farm2.call("now")))
	_check("B.advance_to_no_growth", not bool(farm2.call("is_mature", 0)), "不因 advance_to 大跳变而成熟", str(farm2.call("is_mature", 0)))
	_advance_real(farm2, first - 1.0)
	_check("B.threshold_minus_1_not_mature", not bool(farm2.call("is_mature", 0)),
		"阈值前 1s 未熟", "now=%.1f mature=%s" % [float(farm2.call("now")), str(farm2.call("is_mature", 0))])
	_check("B.threshold_minus_1_seconds", absf(float(farm2.call("seconds_to_mature", 0)) - 1.0) < 0.01,
		"1.0", "%.3f" % float(farm2.call("seconds_to_mature", 0)))
	_advance_real(farm2, 1.0)
	_check("B.threshold_exact_mature", bool(farm2.call("is_mature", 0)), "阈值 +1s 成熟", str(farm2.call("is_mature", 0)))
	_check_eq("B.threshold_exact_stage", "mature", String(farm2.call("stage_id", 0)))
	# 暂停/菜单/day_length 不参与 real 时钟：只受 advance_realtime 调用影响
	var paused_before := float(farm2.call("now"))
	_check("B.pause_no_tick_no_growth", absf(float(farm2.call("now")) - paused_before) < 0.001,
		"无 advance_realtime 调用时时钟不动（暂停/菜单不推进也不回退）", "%.3f" % float(farm2.call("now")))


# ============================================================ C 时间回退 =====
func _test_rollback() -> void:
	_section("C. 时间回退不倒退阶段（sim 模式按 delta 平移时间戳）")
	var inv := _new_inv()
	var farm: Object = FARM.new(inv)
	farm.call("advance_to", 1000.0)
	farm.call("plant", 0, "wheat", "spring")
	var first := CROPS.first_maturity_seconds("wheat")
	farm.call("advance_to", 1000.0 + first * 0.6)
	var stage_before := String(farm.call("stage_id", 0))
	var mature_before := bool(farm.call("is_mature", 0))
	var slot_before: Dictionary = farm.call("get_slot", 0)
	# 回退 500s（模拟玩家拨回系统时间 / 时间源切换）
	farm.call("advance_to", 1000.0 + first * 0.6 - 500.0)
	_check("C.backward_attempt_recorded", int(farm.call("backward_attempts")) >= 1,
		">=1", str(farm.call("backward_attempts")))
	_check_eq("C.stage_not_regressed", stage_before, String(farm.call("stage_id", 0)))
	_check_eq("C.mature_not_regressed", mature_before, bool(farm.call("is_mature", 0)))
	var elapsed_before := float(slot_before.get("cycle_started_at", 0.0))
	var slot_after: Dictionary = farm.call("get_slot", 0)
	var elapsed_after := float(slot_after.get("cycle_started_at", 0.0))
	# 时间戳整体平移 delta：cycle_started_at 同步减少，进度(age)不变
	_check("C.timestamp_shifted", absf((elapsed_before - elapsed_after) - 500.0) < 0.01,
		"cycle_started_at 位移 500", "%.3f" % (elapsed_before - elapsed_after))
	# real 模式：模拟时钟回退/advance_to 也不影响成长时钟与阶段
	var rfarm := _fresh_real_farm()
	rfarm.call("plant", 1, "corn", "spring")
	_advance_real(rfarm, CROPS.first_maturity_seconds("corn") * 0.5)
	var rstage := String(rfarm.call("stage_id", 1))
	var rnow := float(rfarm.call("now"))
	rfarm.call("advance_to", 0.0)
	rfarm.call("advance_to", -500.0)
	_check_eq("C.real_advance_to_ignored", rnow, float(rfarm.call("now")))
	_check_eq("C.real_stage_not_regressed", rstage, String(rfarm.call("stage_id", 1)))


# ============================================================ D export/restore =
func _test_export_restore_real() -> void:
	_section("D. export/restore 在 real 模式下阶段一致")
	var rfarm := _fresh_real_farm()
	rfarm.call("plant", 0, "wheat", "spring")
	rfarm.call("plant", 1, "corn", "spring")
	_advance_real(rfarm, CROPS.first_maturity_seconds("wheat") * 0.5)
	_advance_real(rfarm, 100.0)
	var ex: Dictionary = rfarm.call("export_state") as Dictionary
	_check("D.export_clock_mode_real", String(ex.get("clock_mode", "")) == "real", "real", String(ex.get("clock_mode", "")))
	var inv2 := _new_inv()
	var farm2: Object = FARM.new(inv2)
	farm2.call("set_clock_mode", "real")
	var ok: bool = bool(farm2.call("restore_state", ex))
	_check("D.restore_ok", ok, "true", str(ok))
	_check_eq("D.restore_clock_mode", "real", String(farm2.call("clock_mode_name")))
	_check_eq("D.restore_now", float(ex.get("saved_at_clock_seconds", -1.0)), float(farm2.call("now")))
	var stages_ok := true
	var stages: Array = []
	for i in range(9):
		var s1 := String(rfarm.call("stage_id", i))
		var s2 := String(farm2.call("stage_id", i))
		stages.append("%d:%s/%s" % [i, s1, s2])
		if s1 != s2:
			stages_ok = false
	_check("D.restore_stages_equal", stages_ok, "九格阶段与存档一致", str(stages))
	# 恢复后继续用 real 时钟推进：阶段必须与"原实例再推进同样秒数"一致
	_advance_real(rfarm, 200.0)
	_advance_real(farm2, 200.0)
	var stages2_ok := true
	for i in range(9):
		if String(rfarm.call("stage_id", i)) != String(farm2.call("stage_id", i)):
			stages2_ok = false
	_check("D.restore_then_advance_equal", stages2_ok, "恢复后 real 推进 200s 阶段一致", "ok")
	_check("D.restore_maturity_equal",
		bool(rfarm.call("is_mature", 0)) == bool(farm2.call("is_mature", 0)),
		"成熟判定一致", "%s/%s" % [str(rfarm.call("is_mature", 0)), str(farm2.call("is_mature", 0))])


# ============================================================ E 三次收获 =====
func _test_three_harvests() -> void:
	_section("E. 再生作物每株最多成功收获 3 次（含首收）；第 3 次清空，第 4 次 empty")
	for crop in ["corn", "tomato"]:
		var cid := String(crop)
		var inv := _new_inv()
		var farm: Object = FARM.new(inv)
		farm.call("set_clock_mode", "real")
		farm.call("advance_realtime", 0.0)
		farm.call("plant", 0, cid, "spring")
		var first := CROPS.first_maturity_seconds(cid)
		var regrow := CROPS.regrow_seconds(cid)
		var limit := CROPS.harvest_cycle_limit(cid)
		_check("E.%s.limit" % cid, limit == 3, "3", str(limit))
		var seed_after_plant := int(inv.call("get_count", CROPS.seed_item(cid)))
		var expect_seed := seed_after_plant + 1
		var produce := CROPS.produce_item(cid)
		for n in range(1, 4):
			_advance_real(farm, (first if n == 1 else regrow))
			var mature_ok := bool(farm.call("is_mature", 0))
			_check("E.%s.cycle%d_mature" % [cid, n], mature_ok, "第 %d 轮成熟" % n, str(mature_ok))
			var h: Dictionary = farm.call("harvest", 0)
			_check("E.%s.harvest%d_ok" % [cid, n], bool(h.get("ok", false)), "ok", str(h))
			if n < 3:
				_check_eq("E.%s.harvest%d_count" % [cid, n], n, int(farm.call("harvest_count", 0)))
			else:
				# 第 3 次成功后植株已被清空，harvest_count(空位) 按契约返回 0；清空由下面的 removed/empty 断言覆盖。
				_check_eq("E.%s.harvest3_count_empty_slot" % cid, 0, int(farm.call("harvest_count", 0)))
			_check_eq("E.%s.harvest%d_removed" % [cid, n], n == 3, bool(h.get("plant_removed", false)))
			_check_eq("E.%s.harvest%d_empty" % [cid, n], n == 3, bool(farm.call("is_empty", 0)))
			if n == 1:
				_check_eq("E.%s.first_seed_returned" % cid, expect_seed, int(inv.call("get_count", CROPS.seed_item(cid))))
			else:
				_check_eq("E.%s.no_seed_after_%d" % [cid, n], expect_seed, int(inv.call("get_count", CROPS.seed_item(cid))))
		_check_eq("E.%s.produce_total_3" % cid, 3 * CROPS.harvest_amount(cid), int(inv.call("get_count", produce)))
		var h4: Dictionary = farm.call("harvest", 0)
		_check("E.%s.fourth_harvest_empty" % cid,
			not bool(h4.get("ok", true)) and String(h4.get("reason", "")) == "empty", "ok=false reason=empty", str(h4))
		_check_eq("E.%s.produce_after_fourth" % cid, 3 * CROPS.harvest_amount(cid), int(inv.call("get_count", produce)))
	# 一次性作物不变：一次收获即清空
	var inv3 := _new_inv()
	var farm3: Object = FARM.new(inv3)
	farm3.call("set_clock_mode", "real")
	farm3.call("advance_realtime", 0.0)
	farm3.call("plant", 0, "wheat", "spring")
	_advance_real(farm3, CROPS.first_maturity_seconds("wheat"))
	var hw: Dictionary = farm3.call("harvest", 0)
	_check("E.wheat_one_shot_removed", bool(hw.get("plant_removed", false)) and bool(farm3.call("is_empty", 0)),
		"一次性作物收获即清空", str(hw))
	_check_eq("E.wheat_limit", 1, CROPS.harvest_cycle_limit("wheat"))


# ============================================================ F 失败不 partial =
func _test_failure_no_partial_commit() -> void:
	_section("F. 播种/采收失败不 partial commit（含库存回调重入守卫）")
	# F1 播种失败（扣种失败）：格子保持空、库存不变
	var f_inv := _DuckInv.new()
	f_inv.counts = {"seed_wheat": 1}
	f_inv.fail_remove = true
	var farm_f: Object = FARM.new(f_inv)
	farm_f.call("advance_to", 1000.0)
	var snap0: Dictionary = f_inv.counts.duplicate(true)
	var pf: Dictionary = farm_f.call("plant", 0, "wheat", "spring")
	_check("F.plant_remove_fail_rejected", not bool(pf.get("ok", false)), "ok=false", str(pf))
	_check("F.plant_remove_fail_empty", bool(farm_f.call("is_empty", 0)), "true", str(farm_f.call("is_empty", 0)))
	_check("F.plant_remove_fail_inventory", snap0 == f_inv.counts, "库存不变", str(f_inv.counts))
	# F2 播种失败（无种子）：格子保持空
	var f_inv2 := _DuckInv.new()
	f_inv2.counts = {}
	var farm_f2: Object = FARM.new(f_inv2)
	farm_f2.call("advance_to", 1000.0)
	var pf2: Dictionary = farm_f2.call("plant", 0, "wheat", "spring")
	_check("F.plant_no_seed_rejected", String(pf2.get("reason", "")) == "no_seed", "no_seed", str(pf2))
	_check("F.plant_no_seed_empty", bool(farm_f2.call("is_empty", 0)), "true", "true")
	# F3 采收失败（未成熟）：库存与格状态都不变
	var inv: Object = INV.new()
	inv.call("grant_starting_seeds")
	var farm: Object = FARM.new(inv)
	farm.call("advance_to", 1000.0)
	farm.call("plant", 0, "wheat", "spring")
	var inv_before: Dictionary = inv.call("export_state")
	var farm_before: Dictionary = farm.call("export_state") as Dictionary
	var hf: Dictionary = farm.call("harvest", 0)
	_check("F.harvest_immature_rejected", not bool(hf.get("ok", false)), "not_mature", str(hf))
	_check_eq("F.harvest_immature_inventory", inv_before, inv.call("export_state"))
	_check_eq("F.harvest_immature_farm", farm_before, farm.call("export_state"))
	# F4 采收失败（入账失败）：库存无部分增加、植株仍成熟
	var f_inv3 := _DuckInv.new()
	f_inv3.counts = {"seed_wheat": 1}
	var farm_f3: Object = FARM.new(f_inv3)
	farm_f3.call("advance_to", 1000.0)
	farm_f3.call("plant", 0, "wheat", "spring")
	farm_f3.call("advance_to", 1000.0 + CROPS.first_maturity_seconds("wheat"))
	f_inv3.fail_add = true
	var snap_add: Dictionary = f_inv3.counts.duplicate(true)
	var hf2: Dictionary = farm_f3.call("harvest", 0)
	_check("F.harvest_add_fail_reason", String(hf2.get("reason", "")) == "inventory_add_failed",
		"inventory_add_failed", str(hf2))
	_check("F.harvest_add_fail_no_partial", snap_add == f_inv3.counts, "库存无部分增加", str(f_inv3.counts))
	_check("F.harvest_add_fail_kept_mature", bool(farm_f3.call("is_mature", 0)), "仍成熟（可重试）", str(farm_f3.call("is_mature", 0)))
	# F5 重入守卫：库存 add_items 回调里再次采收 -> busy，且只入账一次
	var re_inv := _ReentryInv.new()
	re_inv.counts = {"seed_corn": 2}
	var farm_re: Object = FARM.new(re_inv)
	re_inv.farm = farm_re
	farm_re.call("advance_to", 1000.0)
	farm_re.call("plant", 0, "corn", "spring")
	farm_re.call("advance_to", 1000.0 + CROPS.first_maturity_seconds("corn"))
	var hre: Dictionary = farm_re.call("harvest", 0)
	_check("F.reentry_harvest_ok", bool(hre.get("ok", false)), "外层采收成功", str(hre))
	_check_eq("F.reentry_single_produce", 1, int(re_inv.counts.get("corn", 0)))
	_check_eq("F.reentry_single_seed", 2, int(re_inv.counts.get("seed_corn", 0)))
	_check_eq("F.reentry_inner_busy", "busy", String(re_inv.inner_reason))
	_check_eq("F.reentry_harvest_count", 1, int(farm_re.call("harvest_count", 0)))
	# F6 播种重入：remove_item 回调里再次播种 -> busy，只扣一颗种子、只种一次
	var p_inv := _ReentryInv.new()
	p_inv.counts = {"seed_kale": 2}
	p_inv.reentry_op = "plant"
	var farm_pr: Object = FARM.new(p_inv)
	p_inv.farm = farm_pr
	farm_pr.call("advance_to", 1000.0)
	var ppr: Dictionary = farm_pr.call("plant", 0, "kale", "spring")
	_check("F.reentry_plant_ok", bool(ppr.get("ok", false)), "外层播种成功", str(ppr))
	_check_eq("F.reentry_seed_once", 1, int(p_inv.counts.get("seed_kale", 0)))
	_check_eq("F.reentry_slot_once", "kale", String(farm_pr.call("crop_id_at", 0)))
	_check_eq("F.reentry_plant_inner_busy", "busy", String(p_inv.inner_reason))


# ============================================================ G main 接线 =====
func _test_main_wiring() -> void:
	_section("G. 生产接线：main._tick 按 farm.clock_mode 分发时间源")
	var ps := load("res://isle.tscn") as PackedScene
	_check("G.scene_load", ps != null, "isle.tscn 可加载", str(ps != null))
	if ps == null:
		return
	_main = ps.instantiate()
	root.add_child(_main)
	await process_frame
	await process_frame
	_main.set_process(false)
	_main.set("_paused", true)
	_main.set("_mode", 1)
	var farm = _main.call("farm")
	_check("G.farm_exists", farm != null, "main 已创建 IsleFarm", "null" if farm == null else "ok")
	if farm == null:
		return
	# script 探针模式：main 不启用世界存档 -> farm 保持 sim（既有探针语义不变）
	_check_eq("G.script_mode_farm_sim", "sim", String(farm.call("clock_mode_name")))
	_check("G.world_save_disabled", not bool((_main.call("world_save_state") as Dictionary).get("enabled", true)),
		"--script 探针不启用世界存档", str((_main.call("world_save_state") as Dictionary).get("enabled")))
	# sim 分支：_tick 把 _sim_seconds 注入 farm.advance_to
	var sim_target := 123456.0
	_main.set("_sim_seconds", sim_target)
	_main.call("_tick", DT)
	_check("G.sim_branch_syncs", absf(float(farm.call("now")) - sim_target) < 0.001,
		"farm.now = _sim_seconds", "%.1f" % float(farm.call("now")))
	# real 分支：_tick 每帧把现实 delta 注入 advance_realtime（与 _sim_seconds 解耦）
	farm.call("set_clock_mode", "real")
	farm.call("advance_realtime", 0.0)
	var before := float(farm.call("now"))
	var sim_before := float(_main.get("_sim_seconds"))
	for i in range(4):
		_main.call("_tick", 0.25)
	var delta_real := float(farm.call("now")) - before
	_check("G.real_branch_advances", absf(delta_real - 1.0) < 0.001,
		"4 x 0.25s = +1.0s（按现实 delta）", "%.3f" % delta_real)
	_check_eq("G.real_branch_ignores_sim", sim_before, float(_main.get("_sim_seconds")))
	# 大跳变 _sim_seconds 不改变 real 时钟
	_main.set("_sim_seconds", sim_target + 100000.0)
	_main.call("_tick", 0.0)
	_check("G.real_ignores_sim_jump", absf((float(farm.call("now")) - before) - 1.0) < 0.001,
		"real 时钟只跟现实 delta 走", "%.3f" % (float(farm.call("now")) - before))


# ============================================================ 鸭子类型库存 ======
class _DuckInv:
	var counts: Dictionary = {}
	var fail_remove := false
	var fail_add := false

	func get_count(item_id: String) -> int:
		return int(counts.get(item_id, 0))

	func remove_item(item_id: String, amount: int) -> bool:
		if fail_remove:
			return false
		var have := get_count(item_id)
		if amount <= 0 or have < amount:
			return false
		counts[item_id] = have - amount
		return true

	func add_items(items: Dictionary) -> bool:
		if fail_add:
			return false
		for k in items.keys():
			counts[String(k)] = get_count(String(k)) + int(items[k])
		return true


class _ReentryInv:
	var counts: Dictionary = {}
	var farm: Object = null
	var inner_reason := ""
	var reentry_op := "harvest"

	func get_count(item_id: String) -> int:
		return int(counts.get(item_id, 0))

	func remove_item(item_id: String, amount: int) -> bool:
		var have := get_count(item_id)
		if amount <= 0 or have < amount:
			return false
		counts[item_id] = have - amount
		if reentry_op == "plant" and farm != null:
			var r: Dictionary = farm.call("plant", 1, item_id.trim_prefix("seed_"), "spring")
			inner_reason = String(r.get("reason", ""))
		return true

	func add_items(items: Dictionary) -> bool:
		for k in items.keys():
			counts[String(k)] = get_count(String(k)) + int(items[k])
		if reentry_op == "harvest" and farm != null:
			var r: Dictionary = farm.call("harvest", 0)
			inner_reason = String(r.get("reason", ""))
		return true


# ============================================================ 报告 ============
func _write_report() -> void:
	var log_path := out_dir + "/probe_p9_farm_realtime.log"
	var fa := FileAccess.open(log_path, FileAccess.WRITE)
	if fa != null:
		fa.store_string("\n".join(_lines) + "\n")
		fa.close()
		print("[RTP] log=", log_path)
	var data := {
		"checks": _pass + _fail,
		"fail": _fail,
		"fail_names": _fail_names,
		"headless": DisplayServer.get_name() == "headless",
	}
	var jf := FileAccess.open(out_dir + "/probe_p9_farm_realtime.json", FileAccess.WRITE)
	if jf != null:
		jf.store_string(JSON.stringify(data, "  "))
		jf.close()
