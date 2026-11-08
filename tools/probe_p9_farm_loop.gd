extends SceneTree
## P9 / P4 —— 共享库存 + 每日巡田闭环探针。
##
## 三种运行方式：
##   1) headless 全量断言（默认）：
##      ENG --headless --path GAME --script res://tools/probe_p9_farm_loop.gd -- --out=D:/休闲小岛幻境/开发产物/P9/P4
##   2) 真实窗口运行 + 截图（需 GPU）：
##      ENG --path GAME --script res://tools/probe_p9_farm_loop.gd -- --p4shots --out=...
##   3) 只跑窗口模式（--p4shots）时同样输出 [SUMMARY]/[RESULT]，PNG 落在 <out>/shots/。
##
## 纪律：
## - 不修改正式场景/存档；测试只通过运行时注入模拟时间/天气/自建库存与农田实例。
## - 不得用 --shots：main.gd 会把 --shots 当成项目内置截图流程，改写时间/天气/相机。
## - 正式默认行为（08:00 巡田、雨雪否决）不被测试改写；测试注入的状态在日志里单独标注。

const INV := preload("res://scripts/isle_inventory.gd")
const FARM := preload("res://scripts/isle_farm.gd")
const CROPS := preload("res://scripts/isle_crops.gd")
const CAL := preload("res://scripts/isle_calendar.gd")
const FISH := preload("res://scripts/isle_fish.gd")

const DEFAULT_OUT := "D:/休闲小岛幻境/开发产物/P9/P4"
const DT := 1.0 / 60.0
const BASE_Y := 2026
const BASE_M := 3
const BASE_D := 20
const PATROL_SEASON := "spring"
## P7-FINALIZE：巡田访问顺序已改为每轮 Fisher–Yates 随机（main._shuffled_patrol_order），
## 因此不再有固定顺序常量；这里只保留"九格全集"，用于断言每轮覆盖且不重复。
const PATROL_SLOT_SET := [0, 1, 2, 3, 4, 5, 6, 7, 8]
const SLOT_NODES := {0: "yard_slot_0", 1: "yard_gate_in", 2: "yard_slot_2",
	3: "yard_slot_3", 4: "yard_slot_4", 5: "yard_slot_5", 6: "yard_slot_6",
	7: "yard_slot_7", 8: "yard_slot_8"}
## P4-CLOSE：中心格不再"不可达"——岛民走上北排中间苗床顶面（yard_slot_4）后再操作中心格。
## 槽位节点高度：走道台面 7.536；中心格站位在北排中间苗床顶面 7.736。
const WALK_Y := 7.536
const BED_Y := 7.736
const SLOT_NODE_Y := {4: 7.736}
const BED_ACCESS_NODES := ["yard_bed_step", "yard_bed_up", "yard_slot_4"]
const INDOOR_NODES := ["hall", "mid", "room_in"]

var out_dir := DEFAULT_OUT
var do_shots := false

var _pass := 0
var _fail := 0
var _lines: Array = []
var _fail_names: Array = []
var _main: Node = null
var _farm: Object = null
var _inv: Object = null
var _villager: Node = null
var _t8 := 0.0
var _day0 := 0
var _shots_fail := 0


func _initialize() -> void:
	_parse_args()
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--out="):
			out_dir = s.substr(6).strip_edges().trim_suffix("/").trim_suffix("\\")
		elif s == "--p4shots":
			do_shots = true
	if out_dir == "":
		out_dir = DEFAULT_OUT


func _run() -> void:
	var banner := "[P4LOOP] out=%s headless=%s godot=%s" % [
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
		_data_inventory_checks()
		_data_farm_checks()
		_scene_checks()
		_sched_checks()
		_patrol_checks()
		_abort_checks()
		_view_and_state_checks()
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
	var log_path := out_dir + "/probe_p9_farm_loop.log"
	var fa := FileAccess.open(log_path, FileAccess.WRITE)
	if fa != null:
		fa.store_string("\n".join(_lines) + "\n")
		fa.close()
		print("[P4LOOP] log=", log_path)
	var data := {
		"checks": _pass + _fail,
		"fail": _fail,
		"fail_names": _fail_names,
		"headless": DisplayServer.get_name() == "headless",
		"shots_fail": _shots_fail,
	}
	var jf := FileAccess.open(out_dir + "/probe_p9_farm_loop.json", FileAccess.WRITE)
	if jf != null:
		jf.store_string(JSON.stringify(data, "  "))
		jf.close()


func _boot() -> void:
	_section("0. 正式场景加载与依赖注入")
	var ps := load("res://isle.tscn") as PackedScene
	_check("env.scene_load", ps != null, "isle.tscn 可加载", str(ps != null))
	if ps == null:
		return
	_main = ps.instantiate()
	if _main == null:
		_check("env.scene_instance", false, "实例化成功", "null")
		return
	root.add_child(_main)
	# 停掉主控 _process：headless 断言由探针显式推进模拟时间，避免后台 _tick 与注入互相干扰。
	_main.set_process(false)
	# 主控只在 PLAYING 阶段调度巡田（菜单/标题不启动）；本探针直接调用 _update_farm_patrol，
	# 因此显式进入 PLAYING，但保持 _process 关闭，由探针完全掌控帧推进。
	_main.set("_mode", 1)
	for i in range(4):
		await process_frame
	_check("env.scene_ready", _main.has_method("inventory") and _main.has_method("farm"),
		"main 暴露 inventory()/farm()", str(_main.has_method("inventory")))
	_inv = _main.call("inventory")
	_farm = _main.call("farm")
	_villager = _main.get("_villager")
	_check("env.inventory_exists", _inv != null, "共享库存实例存在", str(_inv))
	_check("env.farm_exists", _farm != null, "正式九格农田实例存在", str(_farm))
	_check("env.villager_exists", _villager != null, "正式岛民实例存在", str(_villager))
	var farm_inv: Variant = _farm.get("_inventory")
	_check("env.same_inventory_instance", farm_inv == _inv, "农田注入的是同一个库存实例",
		str(farm_inv == _inv))
	_check_eq("env.inventory_grant_count", 1, int(_main.call("inventory_grant_count")))
	_check("env.villager_patrol_api", _villager.has_method("begin_farm_patrol")
		and _villager.has_method("farm_patrol_last")
		and _main.has_method("_update_farm_patrol") and _main.has_method("farm_patrol_state"),
		"岛民/主控巡田接口存在", "ok")
	_check("env.slot_count", int(_farm.call("slot_count")) == 9, "9", str(_farm.call("slot_count")))
	_t8 = CAL.to_local_seconds(BASE_Y, BASE_M, BASE_D, 8, 0, 0)
	_day0 = int(floor(_t8 / 86400.0))
	# 探针不进入 PLAYING：主控时间由探针显式注入，避免 _process 与断言互相干扰。
	_main.set("_day_length", 86400.0)


# ======================================================== 1. 库存契约 ========
func _data_inventory_checks() -> void:
	_section("1. 共享库存契约（自建实例，纯数据）")
	var inv: Object = INV.new()
	_check_eq("inv.empty_get_count", 0, int(inv.call("get_count", "seed_wheat")))
	_check_eq("inv.empty_total", 0, int(inv.call("total_count")))
	_check_eq("inv.empty_export", {"version": 1, "items": {}}, inv.call("export_state"))
	var ids: Array = inv.call("known_item_ids")
	_check_eq("inv.known_count", 16, ids.size())
	var expect_ids: Array = []
	for crop_id in CROPS.CROP_IDS:
		expect_ids.append(CROPS.seed_item(String(crop_id)))
	for crop_id in CROPS.CROP_IDS:
		expect_ids.append(CROPS.produce_item(String(crop_id)))
	for fish_id in FISH.all_ids():
		expect_ids.append(String(fish_id))
	_check("inv.known_ids_canonical", ids == expect_ids, "5 种子 + 5 产物 + 6 鱼规范 ID", str(ids))
	_check("inv.grant_once", bool(inv.call("grant_starting_seeds")), "首次发放成功", "true")
	_check("inv.grant_second_false", not bool(inv.call("grant_starting_seeds")), "重复发放返回 false", "false")
	var seeds: Dictionary = INV.starting_seeds()
	var all_nine := true
	for id in seeds.keys():
		if int(inv.call("get_count", String(id))) != 9:
			all_nine = false
	_check("inv.starting_seeds_9_each", all_nine and seeds.size() == 5, "五种作物各 9 颗", str(inv.call("item_snapshot")))
	_check_eq("inv.starting_total", 45, int(inv.call("total_count")))
	_check("inv.starting_granted_flag", bool(inv.call("starting_granted")), "true", str(inv.call("starting_granted")))
	_check("inv.add_items", bool(inv.call("add_items", {"seed_wheat": 2, "seed_corn": 1})), "true", "true")
	_check_eq("inv.add_count_wheat", 11, int(inv.call("get_count", "seed_wheat")))
	_check_eq("inv.add_count_corn", 10, int(inv.call("get_count", "seed_corn")))
	var snap: Variant = inv.call("item_snapshot")
	_check("inv.add_unknown_rejected", not bool(inv.call("add_items", {"banana": 1})), "false", "false")
	_check("inv.add_unknown_unchanged", inv.call("item_snapshot") == snap, "无变化", "changed")
	_check("inv.add_zero_rejected", not bool(inv.call("add_items", {"seed_wheat": 0})), "false", "false")
	_check("inv.add_negative_rejected", not bool(inv.call("add_items", {"seed_wheat": -1})), "false", "false")
	_check("inv.add_mixed_invalid_rejected", not bool(inv.call("add_items", {"seed_wheat": 1, "seed_corn": -2})), "整笔失败", "false")
	_check("inv.add_mixed_invalid_unchanged", inv.call("item_snapshot") == snap, "无变化", "changed")
	_check("inv.add_overflow_delta_rejected", not bool(inv.call("add_items", {"seed_wheat": 1000000001})), "false", "false")
	_check("inv.remove_insufficient", not bool(inv.call("remove_item", "seed_wheat", 100)), "false", "false")
	_check("inv.remove_insufficient_unchanged", int(inv.call("get_count", "seed_wheat")) == 11, "11", str(inv.call("get_count", "seed_wheat")))
	_check("inv.remove_zero_rejected", not bool(inv.call("remove_item", "seed_wheat", 0)), "false", "false")
	_check("inv.remove_negative_rejected", not bool(inv.call("remove_item", "seed_wheat", -3)), "false", "false")
	_check("inv.remove_ok", bool(inv.call("remove_item", "seed_wheat", 1)), "true", "true")
	_check_eq("inv.remove_result", 10, int(inv.call("get_count", "seed_wheat")))
	_check("inv.has_items_true", bool(inv.call("has_items", {"seed_wheat": 1, "seed_corn": 1})), "true", "true")
	_check("inv.has_items_false", not bool(inv.call("has_items", {"seed_wheat": 999})), "false", "false")
	_check("inv.consume_empty_ok", bool(inv.call("try_consume_items", {})), "true", "true")
	var pre_consume: Variant = inv.call("item_snapshot")
	_check("inv.consume_partial_rejected", not bool(inv.call("try_consume_items", {"seed_wheat": 1, "seed_kale": 999})), "false", "false")
	_check("inv.consume_partial_unchanged", inv.call("item_snapshot") == pre_consume, "无部分扣除", "changed")
	_check("inv.consume_ok", bool(inv.call("try_consume_items", {"seed_wheat": 2, "seed_corn": 1})), "true", "true")
	_check_eq("inv.consume_wheat", 8, int(inv.call("get_count", "seed_wheat")))
	_check_eq("inv.consume_corn", 9, int(inv.call("get_count", "seed_corn")))
	# 状态导出/恢复
	var exported: Dictionary = inv.call("export_state")
	var restored: Object = INV.new()
	_check("inv.restore_roundtrip", bool(restored.call("restore_state", exported)), "true", "true")
	_check("inv.restore_counts", restored.call("item_snapshot") == inv.call("item_snapshot"), "一致", "diff")
	_check("inv.restore_bad_version", not bool(restored.call("restore_state", {"version": 2, "items": {}})), "false", "false")
	_check("inv.restore_unknown_id", not bool(restored.call("restore_state", {"version": 1, "items": {"banana": 1}})), "false", "false")
	_check("inv.restore_negative", not bool(restored.call("restore_state", {"version": 1, "items": {"seed_wheat": -1}})), "false", "false")
	_check("inv.restore_float_fraction", not bool(restored.call("restore_state", {"version": 1, "items": {"seed_wheat": 1.5}})), "false", "false")
	_check("inv.restore_wrong_type", not bool(restored.call("restore_state", {"version": 1, "items": []})), "false", "false")
	_check("inv.restore_bad_keeps_state", restored.call("item_snapshot") == inv.call("item_snapshot"), "失败不改状态", "changed")
	_check("inv.restore_float_integral_ok", bool(restored.call("restore_state", {"version": 1, "items": {"seed_kale": 3.0}})), "接受整值 float", "false")
	_check_eq("inv.restore_float_value", 3, int(restored.call("get_count", "seed_kale")))
	_check("inv.restore_zero_dropped", (restored.call("export_state") as Dictionary)["items"].size() == 1, "0 数量不导出", str(restored.call("export_state")))
	_check("inv.ctor_rejects_invalid", int((INV.new({"banana": 1}) as Object).call("total_count")) == 0, "构造注入非法整份丢弃", "ok")
	_check("inv.ctor_accepts_valid", int((INV.new({"seed_wheat": 2}) as Object).call("get_count", "seed_wheat")) == 2, "2", "ok")


# ======================================================= 2. 农田事务 =========
func _new_farm(inv: Object) -> Object:
	var f: Object = FARM.new(inv)
	f.call("advance_to", 1000.0)
	return f


func _data_farm_checks() -> void:
	_section("2. 播种/采收事务完整性与再生规则（自建库存+农田）")
	var inv: Object = INV.new()
	inv.call("grant_starting_seeds")
	var f: Object = _new_farm(inv)
	_check("farm.empty_slot", bool(f.call("is_empty", 0)), "true", str(f.call("is_empty", 0)))
	# 播种成功扣种
	var before := int(inv.call("get_count", "seed_wheat"))
	var r: Dictionary = f.call("plant", 0, "wheat", "spring")
	_check("farm.plant_ok", bool(r.get("ok", false)), "true", str(r))
	_check_eq("farm.plant_seed_removed", before - 1, int(inv.call("get_count", "seed_wheat")))
	_check("farm.plant_slot_filled", not bool(f.call("is_empty", 0)), "false", str(f.call("is_empty", 0)))
	_check_eq("farm.plant_stage", "seedling", String(f.call("stage_id", 0)))
	# 非空格再播种失败且无副作用
	var snap_inv: Variant = inv.call("item_snapshot")
	var r2: Dictionary = f.call("plant", 0, "wheat", "spring")
	_check("farm.plant_occupied_rejected", not bool(r2.get("ok", false)), "false", str(r2.get("reason", "")))
	_check("farm.plant_occupied_no_side_effect", inv.call("item_snapshot") == snap_inv, "无变化", "changed")
	# 季节不允许
	var r3: Dictionary = f.call("plant", 1, "wheat", "summer")
	_check("farm.plant_season_rejected", not bool(r3.get("ok", false)) and String(r3.get("reason", "")) == "season_not_allowed", "season_not_allowed", str(r3.get("reason", "")))
	_check("farm.plant_season_no_seed_removed", int(inv.call("get_count", "seed_wheat")) == before - 1, str(before - 1), str(inv.call("get_count", "seed_wheat")))
	# 未知作物
	var r4: Dictionary = f.call("plant", 1, "banana", "spring")
	_check("farm.plant_unknown_rejected", not bool(r4.get("ok", false)), "false", str(r4.get("reason", "")))
	# 未成熟不能采收
	f.call("advance_to", 1000.0 + CROPS.first_maturity_seconds("wheat") * 0.5)
	var rh0: Dictionary = f.call("harvest", 0)
	_check("farm.harvest_immature_rejected", not bool(rh0.get("ok", false)), "false", str(rh0.get("reason", "")))
	_check_eq("farm.harvest_immature_stage", "growing", String(f.call("stage_id", 0)))
	# 成熟采收：一次性作物返还种子一次
	f.call("advance_to", 1000.0 + CROPS.first_maturity_seconds("wheat"))
	_check("farm.mature", bool(f.call("is_mature", 0)), "true", str(f.call("is_mature", 0)))
	var pre_prod := int(inv.call("get_count", "wheat"))
	var pre_seed := int(inv.call("get_count", "seed_wheat"))
	var rh: Dictionary = f.call("harvest", 0)
	_check("farm.harvest_ok", bool(rh.get("ok", false)), "true", str(rh))
	_check_eq("farm.harvest_produce", pre_prod + int(CROPS.harvest_amount("wheat")), int(inv.call("get_count", "wheat")))
	_check_eq("farm.harvest_seed_returned", pre_seed + 1, int(inv.call("get_count", "seed_wheat")))
	_check("farm.harvest_one_shot_cleared", bool(f.call("is_empty", 0)), "true", str(f.call("is_empty", 0)))
	_check("farm.harvest_plant_removed", bool(rh.get("plant_removed", false)), "true", str(rh.get("plant_removed", false)))
	# 连续重复采收同一格不能重复发奖
	var pre_dup: Variant = inv.call("item_snapshot")
	var rh_dup: Dictionary = f.call("harvest", 0)
	_check("farm.harvest_twice_rejected", not bool(rh_dup.get("ok", false)), "false", str(rh_dup.get("reason", "")))
	_check("farm.harvest_twice_unchanged", inv.call("item_snapshot") == pre_dup, "无变化", "changed")
	# 再生作物：首收返种一次，植株保留，再生成熟可再次采收
	var f2: Object = _new_farm(inv)
	var r5: Dictionary = f2.call("plant", 1, "corn", "summer")
	_check("farm.corn_plant", bool(r5.get("ok", false)), "true", str(r5))
	var corn_pre_seed := int(inv.call("get_count", "seed_corn"))
	f2.call("advance_to", 1000.0 + CROPS.first_maturity_seconds("corn"))
	var h1: Dictionary = f2.call("harvest", 1)
	_check("farm.corn_first_harvest_ok", bool(h1.get("ok", false)), "true", str(h1))
	_check("farm.corn_seed_returned_once", bool(h1.get("seed_returned", false)), "true", str(h1.get("seed_returned", false)))
	_check_eq("farm.corn_seed_count", corn_pre_seed + 1, int(inv.call("get_count", "seed_corn")))
	_check("farm.corn_plant_kept", not bool(f2.call("is_empty", 1)), "false", str(f2.call("is_empty", 1)))
	_check("farm.corn_regrow_cycle", bool(f2.call("is_regrow_cycle", 1)), "true", str(f2.call("is_regrow_cycle", 1)))
	var h_imm: Dictionary = f2.call("harvest", 1)
	_check("farm.corn_not_mature_again", not bool(h_imm.get("ok", false)), "false", str(h_imm.get("reason", "")))
	f2.call("advance_to", 1000.0 + CROPS.first_maturity_seconds("corn") + CROPS.regrow_seconds("corn"))
	var h2: Dictionary = f2.call("harvest", 1)
	_check("farm.corn_regrow_harvest_ok", bool(h2.get("ok", false)), "true", str(h2))
	_check("farm.corn_regrow_no_seed", not bool(h2.get("seed_returned", false)), "false", str(h2.get("seed_returned", false)))
	_check_eq("farm.corn_seed_count_stable", corn_pre_seed + 1, int(inv.call("get_count", "seed_corn")))
	# 库存事务失败：作物保持成熟、无部分奖励
	var inv_fail: Object = INV.new()
	inv_fail.call("grant_starting_seeds")
	var f3: Object = _new_farm(inv_fail)
	f3.call("plant", 2, "kale", "spring")
	f3.call("advance_to", 1000.0 + CROPS.first_maturity_seconds("kale"))
	# 通过把库存换成会失败的鸭子类型实例验证：IsleFarm 只依赖 get_count/remove_item/add_items
	var failing := _FailingInventory.new()
	failing.counts = {"kale": 0, "seed_kale": 1}
	var f4: Object = FARM.new(failing)
	f4.call("advance_to", 500.0)
	f4.call("plant", 0, "kale", "spring")
	f4.call("advance_to", 500.0 + CROPS.first_maturity_seconds("kale"))
	var fail_before: Dictionary = failing.counts.duplicate(true)
	var hf: Dictionary = f4.call("harvest", 0)
	_check("farm.harvest_inv_fail_reported", not bool(hf.get("ok", false)) and String(hf.get("reason", "")) == "inventory_add_failed", "inventory_add_failed", str(hf.get("reason", "")))
	_check("farm.harvest_inv_fail_keeps_mature", bool(f4.call("is_mature", 0)), "true", str(f4.call("is_mature", 0)))
	_check("farm.harvest_inv_fail_no_partial", failing.counts == fail_before and int(failing.counts.get("kale", 0)) == 0,
		"采收事务失败后库存无任何部分增加（播种已合法扣掉的种子不算采收副作用）", str(failing.counts))
	# 播种扣种失败：不写槽位
	var failing2 := _FailingInventory.new()
	failing2.counts = {"seed_wheat": 0}
	var f5: Object = FARM.new(failing2)
	f5.call("advance_to", 500.0)
	var pf: Dictionary = f5.call("plant", 0, "wheat", "spring")
	_check("farm.plant_no_seed_reason", not bool(pf.get("ok", false)) and String(pf.get("reason", "")) == "no_seed", "no_seed", str(pf.get("reason", "")))
	_check("farm.plant_no_seed_empty", bool(f5.call("is_empty", 0)), "true", str(f5.call("is_empty", 0)))
	# 选种策略：季节过滤 + 库存过滤 + 均衡
	var f6: Object = _new_farm(inv)
	var pick := String(f6.call("choose_crop", "spring"))
	_check("farm.choose_spring", CROPS.plantable(pick, "spring"), "可种作物", pick)
	var f7: Object = _new_farm(inv)
	var only_kale: Object = INV.new({"seed_kale": 5})
	var f8: Object = FARM.new(only_kale)
	f8.call("advance_to", 500.0)
	_check_eq("farm.choose_only_available", "kale", String(f8.call("choose_crop", "spring")))
	var none_inv: Object = INV.new({"seed_watermelon": 3})
	var f9: Object = FARM.new(none_inv)
	f9.call("advance_to", 500.0)
	_check_eq("farm.choose_none_available", "", String(f9.call("choose_crop", "spring")))
	_check("farm.plant_auto_no_candidate", String((f9.call("plant_auto", 0, "spring") as Dictionary).get("reason", "")) == "no_candidate", "no_candidate", "ok")
	# 均衡：多次 plant_auto 后各种数量差 <= 1
	var inv_bal: Object = INV.new()
	inv_bal.call("grant_starting_seeds")
	var fb: Object = FARM.new(inv_bal)
	fb.call("set_rng_seed", 20261024)
	fb.call("advance_to", 100.0)
	for i in range(9):
		fb.call("plant_auto", i, "spring")
	var counts := {}
	for i in range(9):
		var cid := String(fb.call("crop_id_at", i))
		counts[cid] = int(counts.get(cid, 0)) + 1
	_check("farm.balance_planted", counts.size() >= 2, "至少两种作物（季节可用）", str(counts))
	# 状态导出/恢复
	var ex: Dictionary = fb.call("export_state")
	var fr: Object = FARM.new(inv_bal)
	var restored_ok := bool(fr.call("restore_state", ex, float(fb.call("now"))))
	_check("farm.restore_ok", restored_ok, "true", str(restored_ok))
	if restored_ok:
		var same := true
		for i in range(9):
			if String(fr.call("crop_id_at", i)) != String(fb.call("crop_id_at", i)):
				same = false
		_check("farm.restore_slots", same, "九格作物一致", str(same))
	_check("farm.restore_bad_rejected", not bool(FARM.new(inv_bal).call("restore_state", {"version": 99})), "false", "false")


class _FailingInventory:
	var counts: Dictionary = {}
	var fail_add := true
	var fail_remove := false
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



	# ===================================================== 3. 正式场景接线 ======
func _scene_checks() -> void:
	_section("3. 正式运行接线：库存单次初始化、九格路线与可达节点")
	var seeds: Dictionary = INV.starting_seeds()
	var seeds_ok := true
	for id in seeds.keys():
		if int(_inv.call("get_count", String(id))) < 9:
			seeds_ok = false
	_check("scene.production_starting_seeds", seeds_ok, "正式库存每作物至少 9 颗种子",
		str(_inv.call("item_snapshot")))
	_check("scene.no_extra_produce", int(_inv.call("total_count")) == 45, "初始只有 45 颗种子、无额外产物",
		str(_inv.call("total_count")))
	_check("scene.single_villager", _main.get("_villagers") == null and _villager != null,
		"当前工程只有一个岛民（无 _villagers 数组）", "single")
	# 路线构建
	var route: Array = _main.call("_build_farm_patrol_route")
	_check_eq("scene.route_size", 9, route.size())
	if route.size() == 9:
		var order: Array = []
		for e in route:
			order.append(int((e as Dictionary).get("slot", -1)))
		# P7-FINALIZE：顺序随机，只断言"九格各出现一次、集合={0..8}"（不再断言固定顺序）。
		var order_sorted: Array = order.duplicate()
		order_sorted.sort()
		_check("scene.route_covers_slots", order_sorted == PATROL_SLOT_SET,
			"九格各出现一次，集合={0..8}（顺序随机）", str(order))
		# 随机性：同一种子可复现、不同种子顺序不同（main.set_farm_patrol_rng_seed 是只读测试钩子）。
		_main.call("set_farm_patrol_rng_seed", 20261026)
		var order_seed_a: Array = _route_slot_order()
		_main.call("set_farm_patrol_rng_seed", 20261026)
		var order_seed_a2: Array = _route_slot_order()
		_main.call("set_farm_patrol_rng_seed", 20261027)
		var order_seed_b: Array = _route_slot_order()
		_check("scene.patrol_order_seed_reproducible", order_seed_a == order_seed_a2,
			"同一种子生成同一顺序（可复现）", "%s vs %s" % [str(order_seed_a), str(order_seed_a2)])
		_check("scene.patrol_order_seed_varies", order_seed_a != order_seed_b,
			"不同种子生成不同顺序（不固定）", "%s vs %s" % [str(order_seed_a), str(order_seed_b)])
		# 恢复随机源：后续巡田断言只看逐格结果，不依赖顺序。
		_main.call("set_farm_patrol_rng_seed", int(Time.get_ticks_usec()))
		var reachable := 0
		var slot4_node := ""
		var slot4_point := Vector3.ZERO
		for e in route:
			var d: Dictionary = e
			var slot := int(d.get("slot", -1))
			var nid := String(d.get("node", ""))
			if nid != "" and d.get("point") != null:
				reachable += 1
			if slot == 4:
				slot4_node = nid
				slot4_point = d.get("point", Vector3.ZERO)
		_check_eq("scene.route_reachable_slots", 9, reachable)
		_check_eq("scene.route_slot4_node", "yard_slot_4", slot4_node)
		# 中心格几何（P4-CLOSE）：九格被 0.5 m 草缝隔开，草缝里不得有图节点；走道节点到中心格
		# 格心仍 >=1.30 m（草缝不提供站立点），但岛民可以走上北排中间苗床顶面 yard_slot_4，
		# 站位到格心 <=1.30 m，草缝本身依然不可通行。
		var facts2: Dictionary = (_main.get("_world") as Dictionary).get("front_yard", {})
		var s4w := Vector2.ZERO
		var s4_found := false
		var spacing := 0.0
		var slot_rows: Array = facts2.get("slots", [])
		for row in slot_rows:
			var r2: Dictionary = row
			if int(r2.get("index", -1)) == 4:
				s4w = r2.get("world", Vector2.ZERO)
				s4_found = true
		var w1s := Vector2.ZERO
		for row in slot_rows:
			if int((row as Dictionary).get("index", -1)) == 1:
				w1s = (row as Dictionary).get("world", Vector2.ZERO)
		if s4_found:
			spacing = w1s.distance_to(s4w)
		var graph0: Dictionary = _villager.get("graph")
		var nodes0: Dictionary = graph0.get("nodes", {})
		var walk_nearest := 1.0e9
		var walk_nearest_id := ""
		var bed_nodes: Array = []
		for k in nodes0.keys():
			var nd0: Dictionary = nodes0[k]
			var np0: Vector3 = nd0["pos"]
			var dd0 := Vector2(np0.x, np0.z).distance_to(s4w)
			if String(nd0.get("mode", "")) == "yard_bed":
				bed_nodes.append(String(k))
			elif dd0 < walk_nearest:
				walk_nearest = dd0
				walk_nearest_id = String(k)
		_check("scene.slot4_found", s4_found, "facts 含中心格 slot4", "found")
		_check("scene.slot4_walkway_out_of_reach", walk_nearest >= 1.30,
			"走道（非床面）节点到中心格格心 >=1.30m：草缝不是站立点", "%s %.3f m" % [walk_nearest_id, walk_nearest])
		var s4_reach := Vector2(slot4_point.x, slot4_point.z).distance_to(s4w)
		_check("scene.slot4_station_in_reach", s4_reach <= 1.30,
			"巡田站位（苗床顶面 yard_slot_4）到中心格格心 <=1.30m", "%.3f m" % s4_reach)
		_check("scene.bed_spacing", absf(spacing - 1.5) <= 0.001, "苗床中心距 1.5m → 净间隔 0.5m",
			"%.3f m" % spacing)
		# 床面节点必须落在某张苗床顶面内（到最近格心 <= 0.48*sqrt(2)=0.679 m），即不可能站在
		# 0.5 m 草缝里；床面节点之间也不允许跨床连边（只能沿同一张床或经走道上下床）。
		var centers_w: Array = []
		for row2 in slot_rows:
			centers_w.append((row2 as Dictionary).get("world", Vector2.ZERO) as Vector2)
		var off_bed: Array = []
		var bed_owner := {}
		for bid in bed_nodes:
			var bnp: Vector3 = (nodes0[String(bid)] as Dictionary)["pos"]
			var bp := Vector2(bnp.x, bnp.z)
			var best := 1.0e9
			var best_i := -1
			for ci in range(centers_w.size()):
				var cd := bp.distance_to(centers_w[ci] as Vector2)
				if cd < best:
					best = cd
					best_i = ci
			bed_owner[String(bid)] = best_i
			if best > 0.679:
				off_bed.append("%s d=%.3f" % [String(bid), best])
		_check("scene.bed_nodes_on_bed_top", bed_nodes.size() >= 2 and off_bed.is_empty(),
			"床面节点都落在苗床顶面内（草缝内无节点）", "%s off=%s" % [str(bed_nodes), str(off_bed)])
		var adj0: Dictionary = graph0.get("adj", {})
		var cross_edges: Array = []
		for ea in bed_owner.keys():
			for eb in (adj0.get(String(ea), []) as Array):
				if bed_owner.has(String(eb)) and int(bed_owner[String(ea)]) != int(bed_owner[String(eb)]):
					cross_edges.append("%s-%s" % [String(ea), String(eb)])
		_check("scene.bed_nodes_no_cross_bed_edge", cross_edges.is_empty(),
			"床面节点之间无跨床连边（不能踩草缝过床）", str(cross_edges))
	# 行走图节点存在性与高度（走道台面 7.536；中心格站位在北排中间苗床顶面 7.736）
	var graph: Dictionary = _villager.get("graph")
	var nodes: Dictionary = graph.get("nodes", {})
	var missing: Array = []
	var bad_y: Array = []
	for slot in SLOT_NODES.keys():
		var nid := String(SLOT_NODES[slot])
		if not nodes.has(nid):
			missing.append(nid)
			continue
		var npos: Vector3 = (nodes[nid] as Dictionary)["pos"]
		var want_y := float(SLOT_NODE_Y.get(int(slot), WALK_Y))
		if absf(npos.y - want_y) > 0.01:
			bad_y.append("%s=%.3f want=%.3f" % [nid, npos.y, want_y])
	_check("scene.slot_nodes_present", missing.is_empty(), "9 个槽位交互节点（含中心格床面节点）", str(missing))
	_check("scene.slot_nodes_height", bad_y.is_empty(), "走道 7.536 / 中心格床面 7.736", str(bad_y))
	# 上台链路：走道边 yard_bed_step(7.536) → 床顶 yard_bed_up(7.736) → 中心格站位(7.736)
	var up_missing: Array = []
	for bid in BED_ACCESS_NODES:
		if not nodes.has(String(bid)):
			up_missing.append(String(bid))
	var up_y_bad: Array = []
	if up_missing.is_empty():
		var y_step: float = ((nodes["yard_bed_step"] as Dictionary)["pos"] as Vector3).y
		var y_up: float = ((nodes["yard_bed_up"] as Dictionary)["pos"] as Vector3).y
		var y_st: float = ((nodes["yard_slot_4"] as Dictionary)["pos"] as Vector3).y
		if absf(y_step - WALK_Y) > 0.01:
			up_y_bad.append("yard_bed_step=%.3f" % y_step)
		if absf(y_up - BED_Y) > 0.01:
			up_y_bad.append("yard_bed_up=%.3f" % y_up)
		if absf(y_st - BED_Y) > 0.01:
			up_y_bad.append("yard_slot_4=%.3f" % y_st)
	_check("scene.bed_access_nodes", up_missing.is_empty() and up_y_bad.is_empty(),
		"走道→床顶→站位 三节点存在且高度正确", "missing=%s bad_y=%s" % [str(up_missing), str(up_y_bad)])
	# 从门前草坪到每个槽位都有 A* 路径（含中心格）
	var no_path: Array = []
	for slot2 in SLOT_NODES.keys():
		var nid2 := String(SLOT_NODES[slot2])
		var pth: Array = IsleVillagerSpots.find_path(graph, "garden_0", nid2)
		if pth.is_empty():
			no_path.append(nid2)
	_check("scene.slot_nodes_pathable", no_path.is_empty(), "garden_0 可达 9 个槽位（含中心格）", str(no_path))
	# 环上角点确实在图中（避免弦穿床）
	var corners := 0
	for nid in ["yard_corner_ne", "yard_corner_se", "yard_corner_sw", "yard_corner_nw"]:
		if nodes.has(nid):
			corners += 1
	_check_eq("scene.ring_corners", 4, corners)


	# ===================================================== 4. 每日调度 ==========
func _patrol_state() -> Dictionary:
	return _main.call("farm_patrol_state") as Dictionary


## 构建一次巡田路线的槽位访问顺序（只读；供随机性/可复现断言）。
func _route_slot_order() -> Array:
	var route: Array = _main.call("_build_farm_patrol_route")
	var out: Array = []
	for e in route:
		out.append(int((e as Dictionary).get("slot", -1)))
	return out


func _sched_tick(times: int = 1) -> void:
	for i in range(times):
		_main.call("_update_farm_patrol", DT)


func _day_base(day_offset: int) -> float:
	return CAL.to_local_seconds(BASE_Y, BASE_M, BASE_D + day_offset, 0, 0, 0)


func _set_sim(t: float) -> void:
	_main.set("_sim_seconds", t)
	var f: Object = _main.call("farm")
	f.call("advance_to", t)
	_main.call("_update_lighting")
	# 探针直接改主时钟后同步岛民缓存时间，避免把"测试注入的时间跳跃"误判成世界跳时。
	if _villager != null:
		_villager.set("_sim_now", t)
		_villager.set("_last_sim", t)


func _force_weather(type_id: String) -> void:
	var wx: Object = _main.get("_weather")
	if wx == null:
		return
	# 只读注入：走 isle_weather 的正式手动接口（set_manual_type + reset 到稳态）。
	# 注意 TYPE_PARAMS 的键是 mid_rain/heavy_snow 等具体类型，不存在 "rain"/"snow"。
	var real := String({"rain": "mid_rain", "snow": "heavy_snow"}.get(type_id, type_id))
	wx.call("set_manual_type", real)
	wx.call("reset", float(_main.get("_sim_seconds")))
	_main.call("_update_weather", 0.0, true)


func _precip() -> String:
	var w: Dictionary = _main.get("_weather_state")
	return String(w.get("precip_type", "none"))


## 探针自建岛民上下文：正式 _villager_ctx() 在 MENU 下 frozen=true，会跳过移动；
## 巡田移动用例需要岛民真实走位，因此只解除 frozen 并保持其余上下文来自正式主控。
## 刷新岛民上下文（天气/时间等）：正式主控每帧 sim_tick 一次，探针直接注入时间后需手动补一次。
func _refresh_ctx() -> void:
	if _villager != null:
		_villager.call("sim_tick", DT, _ctx())


func _ctx() -> Dictionary:
	var c: Dictionary = _main.call("_villager_ctx")
	c["frozen"] = false
	var sim := float(_main.get("_sim_seconds"))
	c["sim_seconds"] = sim
	# 探针按"当前注入时刻"连续推进，不制造世界跳时；确保 _detect_jump 的期望值与实际一致。
	var last := float(_villager.get("_last_sim"))
	c["sim_delta"] = maxf(0.0, sim - last)
	c["time_jump"] = false
	return c


func _scheduler_clear() -> void:
	if bool(_villager.call("farm_patrol_active")):
		_villager.call("cancel_farm_patrol", "probe_reset")
	_main.set("_patrol_handled_day", -2147483647)
	_main.set("_patrol_phase", "idle")
	_main.set("_patrol_last", {})
	_main.set("_patrol_start_count", 0)
	_main.set("_patrol_deadline_day", -2147483647)
	_main.set("_patrol_deadline", 0.0)
	_main.set("_patrol_retry_timer", 0.0)


func _sched_reset(day_offset: int, secs: float) -> void:
	_scheduler_clear()
	_set_sim(_day_base(day_offset) + secs)


func _sched_reset_no_clear(day_offset: int, secs: float) -> void:
	_set_sim(_day_base(day_offset) + secs)


func _sched_checks() -> void:
	_section("4. 08:00 每日巡田调度（权威 _sim_seconds，按游戏日幂等）")
	_ensure_seeds()
	_force_weather("clear")
	# 07:59 不启动；越过 08:00 启动一次
	_sched_reset(0, 7 * 3600 + 59 * 60)
	_sched_tick(5)
	var st: Dictionary = _patrol_state()
	_check("sched.0759_no_start", String(st.get("phase", "")) == "idle" and int(st.get("start_count", 0)) == 0,
		"未启动", str(st))
	_check("sched.0759_day_not_handled", int(st.get("handled_day", 0)) != _day0, "当天未处理", str(st.get("handled_day", 0)))
	_set_sim(_day_base(0) + 8 * 3600)
	_sched_tick(1)
	st = _patrol_state()
	_check("sched.0800_start_once", int(st.get("start_count", 0)) == 1 and String(st.get("phase", "")) == "running",
		"start_count=1 phase=running", str(st))
	_check("sched.0800_day_handled", int(st.get("handled_day", 0)) == _day0, str(_day0), str(st.get("handled_day", 0)))
	_check("sched.villager_active", bool(_villager.call("farm_patrol_active")), "true", str(_villager.call("farm_patrol_active")))
	var route: Array = _main.call("_build_farm_patrol_route")
	var dup := bool(_villager.call("begin_farm_patrol", route, _farm, PATROL_SEASON))
	_check("sched.duplicate_begin_rejected", not dup, "false", str(dup))
	# 同一天数百帧不重复创建
	_sched_tick(300)
	st = _patrol_state()
	_check("sched.300_frames_no_restart", int(st.get("start_count", 0)) == 1 and bool(_villager.call("farm_patrol_active")),
		"start_count=1 仍 active", str(st))
	# 同日取消后不再补做
	_villager.call("cancel_farm_patrol", "probe_cancel")
	_sched_tick(200)
	st = _patrol_state()
	_check("sched.same_day_no_makeup", int(st.get("start_count", 0)) == 1 and not bool(_villager.call("farm_patrol_active")),
		"不再启动", str(st))
	# 新的一天可重新调度
	_sched_reset(1, 7 * 3600 + 59 * 60)
	_sched_tick(3)
	st = _patrol_state()
	_check("sched.next_day_0759_no_start", int(st.get("start_count", 0)) == 0, "0", str(st.get("start_count", 0)))
	_set_sim(_day_base(1) + 8 * 3600)
	_sched_tick(1)
	st = _patrol_state()
	_check("sched.next_day_start", int(st.get("start_count", 0)) == 1 and int(st.get("handled_day", 0)) == _day0 + 1,
		"次日启动", str(st))
	_villager.call("cancel_farm_patrol", "probe_done")
	# 直接快进到 08:10 不漏检查
	_sched_reset(2, 8 * 3600 + 10 * 60)
	_sched_tick(1)
	st = _patrol_state()
	_check("sched.fastforward_0810_start", int(st.get("start_count", 0)) == 1, "08:10 仍触发", str(st))
	_villager.call("cancel_farm_patrol", "probe_done")
	# 08:00 雨天 / 雪天：当天不启动
	_sched_reset(3, 7 * 3600 + 59 * 60)
	_force_weather("rain")
	_check_eq("sched.rain_detected", "rain", _precip())
	_set_sim(_day_base(3) + 8 * 3600)
	_sched_tick(3)
	st = _patrol_state()
	_check("sched.rain_0800_skip", String(st.get("phase", "")) == "weather_skip" and int(st.get("start_count", 0)) == 0,
		"weather_skip", str(st))
	_check("sched.rain_skip_no_villager", not bool(_villager.call("farm_patrol_active")), "false", "true")
	# 当天转晴不补做
	_force_weather("clear")
	_sched_tick(200)
	st = _patrol_state()
	_check("sched.rain_then_clear_no_makeup", String(st.get("phase", "")) == "weather_skip" and int(st.get("start_count", 0)) == 0,
		"仍 weather_skip", str(st))
	# 雪天
	_sched_reset(4, 7 * 3600 + 59 * 60)
	_force_weather("snow")
	_set_sim(_day_base(4) + 8 * 3600)
	_sched_tick(3)
	st = _patrol_state()
	_check("sched.snow_0800_skip", String(st.get("phase", "")) == "weather_skip" and int(st.get("start_count", 0)) == 0,
		"weather_skip", str(st))
	# 次日天气适宜重新调度
	_sched_reset(5, 7 * 3600 + 59 * 60)
	_force_weather("clear")
	_set_sim(_day_base(5) + 8 * 3600)
	_sched_tick(1)
	st = _patrol_state()
	_check("sched.after_weather_next_day_start", int(st.get("start_count", 0)) == 1, "1", str(st.get("start_count", 0)))
	_villager.call("cancel_farm_patrol", "probe_done")
	# 时间回退：倒带当天不得重播
	_sched_reset(6, 7 * 3600 + 59 * 60)
	_set_sim(_day_base(6) + 8 * 3600)
	_sched_tick(1)
	st = _patrol_state()
	_check("sched.rewind_setup_started", int(st.get("start_count", 0)) == 1, "1", str(st.get("start_count", 0)))
	_villager.call("cancel_farm_patrol", "probe_done")
	_sched_reset_no_clear(5, 7 * 3600)
	_sched_tick(3)
	st = _patrol_state()
	_check("sched.rewind_no_start", String(st.get("phase", "")) == "day_rewound", "day_rewound", str(st))
	_check("sched.rewind_not_restarted", int(st.get("start_count", 0)) == 1 and not bool(_villager.call("farm_patrol_active")),
		"未启动新巡田", str(st))
	# 启动窗口耗尽：当天不启动，进入 start_failed
	_sched_reset(7, 9 * 3600)
	# 启动窗口是"当日秒数"语义（main.gd _update_farm_patrol）：截止点压到 07:00，09:00 即窗口耗尽。
	_main.set("_patrol_deadline_day", _day0 + 7)
	_main.set("_patrol_deadline", 7.0 * 3600.0)
	_main.set("_patrol_handled_day", -2147483647)
	_sched_tick(1)
	st = _patrol_state()
	_check("sched.window_expired", String(st.get("phase", "")) == "start_failed", "start_failed", str(st))
	var window_reason := String((st.get("last", {}) as Dictionary).get("reason", ""))
	_check_eq("sched.window_expired_reason", "start_window_expired", window_reason)
	# 恢复干净状态供后续用例
	_scheduler_clear()
	_force_weather("clear")


	# ===================================================== 5. 九格巡田 ==========
func _ensure_seeds() -> void:
	# 仅测试注入：把种子补到固定下限，避免同一探针多场景复用生产库存时因种子耗尽而失真。
	var items: Dictionary = {}
	for crop_id in CROPS.CROP_IDS:
		items[CROPS.seed_item(String(crop_id))] = 30
	_inv.call("restore_state", {"version": 1, "items": items})
	_lines.append("[P4LOOP] TEST-INJECT inventory seeds=30 each (probe only, not production default)")


func _prep_farm_at(t8: float) -> void:
	_farm.call("reset")
	_farm.call("advance_to", t8 - 20000.0)
	_farm.call("plant", 0, "wheat", PATROL_SEASON)
	_farm.call("plant", 1, "corn", PATROL_SEASON)
	_farm.call("plant", 2, "kale", PATROL_SEASON)
	_farm.call("plant", 6, "tomato", PATROL_SEASON)
	_farm.call("advance_to", t8 - 5000.0)
	_farm.call("advance_to", t8 - 100.0)
	_farm.call("plant", 3, "kale", PATROL_SEASON)
	_farm.call("plant", 7, "wheat", PATROL_SEASON)
	_farm.call("advance_to", t8 - 100.0)


func _live_results() -> Array:
	var p: Dictionary = _villager.get("_patrol")
	return (p.get("results", []) as Array).duplicate(true)


func _step_patrol(max_steps: int) -> Dictionary:
	var stats := {
		"steps": 0, "max_jump": 0.0, "premature": 0,
		"arrivals": 0, "arrive_max": 0.0, "arrive_min": 1.0e9,
	}
	var prev: Vector3 = _villager.get("_pos")
	var prev_results := 0
	var prev_slots: Array = (_farm.call("export_state") as Dictionary).get("slots", [])
	var graph: Dictionary = _villager.get("graph")
	var nodes: Dictionary = graph.get("nodes", {})
	for i in range(max_steps):
		_main.call("_update_farm_patrol", DT)
		_villager.call("sim_tick", DT, _ctx())
		stats["steps"] = i + 1
		var pos: Vector3 = _villager.get("_pos")
		stats["max_jump"] = maxf(float(stats["max_jump"]), Vector2(pos.x - prev.x, pos.z - prev.z).length())
		prev = pos
		var active := bool(_villager.call("farm_patrol_active"))
		var results: Array = _live_results() if active else (_villager.call("farm_patrol_last") as Dictionary).get("results", [])
		var results_before := prev_results
		while prev_results < results.size():
			var rec: Dictionary = results[prev_results]
			prev_results += 1
			stats["arrivals"] = int(stats["arrivals"]) + 1
			var slot := int(rec.get("slot", -1))
			if String(rec.get("action", "")) != "unreachable" and SLOT_NODES.has(slot):
				var nid := String(SLOT_NODES[slot])
				if nodes.has(nid):
					var np: Vector3 = (nodes[nid] as Dictionary)["pos"]
					var rp: Vector3 = rec.get("pos", Vector3.ZERO)
					var d := Vector2(rp.x - np.x, rp.z - np.z).length()
					stats["arrive_max"] = maxf(float(stats["arrive_max"]), d)
					stats["arrive_min"] = minf(float(stats["arrive_min"]), d)
		var slots_now: Array = (_farm.call("export_state") as Dictionary).get("slots", [])
		if slots_now != prev_slots:
			if results.size() == results_before:
				stats["premature"] = int(stats["premature"]) + 1
			prev_slots = slots_now
		if not active:
			break
	return stats


func _step_until_results(min_results: int, max_steps: int) -> int:
	for i in range(max_steps):
		if _live_results().size() >= min_results:
			return i
		_main.call("_update_farm_patrol", DT)
		_villager.call("sim_tick", DT, _ctx())
		if not bool(_villager.call("farm_patrol_active")):
			break
	return max_steps


func _slot_node_pos(slot: int) -> Vector3:
	var graph: Dictionary = _villager.get("graph")
	var nodes: Dictionary = graph.get("nodes", {})
	var nid := String(SLOT_NODES.get(slot, ""))
	if nid == "" or not nodes.has(nid):
		return Vector3.ZERO
	return (nodes[nid] as Dictionary)["pos"]


func _patrol_checks() -> void:
	_section("5. 九格逐格巡田（真实移动、逐格到达、唯一主操作）")
	_ensure_seeds()
	_force_weather("clear")
	var t8 := _day_base(10) + 8 * 3600
	_sched_reset(10, 7 * 3600 + 59 * 60)
	_prep_farm_at(t8)
	# 播种前状态快照（成熟/生长/空）
	var before_mature := []
	var before_growing := []
	var before_empty := []
	for i in range(9):
		if bool(_farm.call("is_empty", i)):
			before_empty.append(i)
		elif bool(_farm.call("is_mature", i)):
			before_mature.append(i)
		else:
			before_growing.append(i)
	_check("patrol.prep_mature", before_mature == [0, 1, 2, 6], "[0,1,2,6]", str(before_mature))
	_check("patrol.prep_growing", before_growing == [3, 7], "[3,7]", str(before_growing))
	_check("patrol.prep_empty", before_empty == [4, 5, 8], "[4,5,8]", str(before_empty))
	_sched_tick(1)
	_set_sim(t8)
	_sched_tick(1)
	var st: Dictionary = _patrol_state()
	_check("patrol.started", int(st.get("start_count", 0)) == 1, "1", str(st))
	var inv_before: Dictionary = (_inv.call("export_state") as Dictionary)["items"]
	var stats := _step_patrol(8000)
	_sched_tick(3)
	var last: Dictionary = _villager.call("farm_patrol_last")
	var results: Array = last.get("results", [])
	_check_eq("patrol.results_count", 9, results.size())
	_check_eq("patrol.outcome", "done", String(last.get("outcome", "")))
	_check("patrol.no_weather_abort", not bool(last.get("weather_abort", false)), "false", str(last.get("weather_abort", false)))
	var visited: Array = []
	var action_by_slot := {}
	for rec in results:
		var d: Dictionary = rec
		visited.append(int(d.get("slot", -1)))
		action_by_slot[int(d.get("slot", -1))] = String(d.get("action", ""))
	# P7-FINALIZE：只断言"九格恰好各访问一次"，顺序无关。
	var visited_sorted: Array = visited.duplicate()
	visited_sorted.sort()
	_check("patrol.all_slots_attempted", visited_sorted == PATROL_SLOT_SET,
		"九格各访问一次，集合={0..8}（顺序随机）", str(visited))
	_check_eq("patrol.slot0_harvest", "harvest", String(action_by_slot.get(0, "")))
	_check_eq("patrol.slot1_harvest", "harvest", String(action_by_slot.get(1, "")))
	_check_eq("patrol.slot2_harvest", "harvest", String(action_by_slot.get(2, "")))
	_check_eq("patrol.slot6_harvest", "harvest", String(action_by_slot.get(6, "")))
	_check_eq("patrol.slot3_skip", "skip", String(action_by_slot.get(3, "")))
	_check_eq("patrol.slot7_skip", "skip", String(action_by_slot.get(7, "")))
	_check_eq("patrol.slot5_plant", "plant", String(action_by_slot.get(5, "")))
	_check_eq("patrol.slot8_plant", "plant", String(action_by_slot.get(8, "")))
	# P4-CLOSE：中心格现在真的走到北排中间苗床顶面再操作（不再是 unreachable）
	var slot4_action := String(action_by_slot.get(4, ""))
	_check("patrol.slot4_processed", slot4_action == "plant",
		"中心格真实处理（prep 时为空 → plant）", slot4_action)
	# 真实到达：到达位置与节点水平距离、每步位移（无瞬移）
	_check("patrol.arrivals_9", int(stats["arrivals"]) >= 9, "9 次真实到达（含中心格）", str(stats["arrivals"]))
	_check("patrol.arrive_distance", float(stats["arrive_max"]) <= 0.35, "<=0.35m", "max=%.3f" % float(stats["arrive_max"]))
	_check("patrol.no_teleport", float(stats["max_jump"]) <= 0.25, "单步位移 <=0.25m", "max=%.3f" % float(stats["max_jump"]))
	_check_eq("patrol.no_premature_farm_change", 0, int(stats["premature"]))
	# 库存增量与记录一致（逐笔对账）
	var exp: Dictionary = inv_before.duplicate(true)
	for rec in results:
		var d: Dictionary = rec
		var act := String(d.get("action", ""))
		var crop := String(d.get("crop_id", ""))
		if act == "harvest":
			var prod := String(d.get("produce_item", ""))
			exp[prod] = int(exp.get(prod, 0)) + int(d.get("produce_amount", 0))
			if bool(d.get("seed_returned", false)):
				var sid := CROPS.seed_item(crop)
				exp[sid] = int(exp.get(sid, 0)) + 1
		elif act == "plant":
			var sid2 := CROPS.seed_item(crop)
			exp[sid2] = int(exp.get(sid2, 0)) - 1
	var exp_nonzero := {}
	for k in exp.keys():
		if int(exp[k]) != 0:
			exp_nonzero[String(k)] = int(exp[k])
	var inv_after: Dictionary = (_inv.call("export_state") as Dictionary)["items"]
	_check("patrol.inventory_matches_records", exp_nonzero == inv_after,
		"库存增量与逐格记录一致", "exp=%s actual=%s" % [str(exp_nonzero), str(inv_after)])
	# 农田最终状态
	_check("patrol.slot0_empty_after", bool(_farm.call("is_empty", 0)), "一次性作物清空", str(_farm.call("is_empty", 0)))
	_check("patrol.slot2_empty_after", bool(_farm.call("is_empty", 2)), "一次性作物清空", str(_farm.call("is_empty", 2)))
	_check("patrol.slot1_corn_kept", String(_farm.call("crop_id_at", 1)) == "corn", "corn", String(_farm.call("crop_id_at", 1)))
	_check("patrol.slot6_tomato_kept", String(_farm.call("crop_id_at", 6)) == "tomato", "tomato", String(_farm.call("crop_id_at", 6)))
	_check("patrol.slot1_regrow_cycle", bool(_farm.call("is_regrow_cycle", 1)), "true", str(_farm.call("is_regrow_cycle", 1)))
	_check("patrol.slot3_untouched", String(_farm.call("crop_id_at", 3)) == "kale", "kale", String(_farm.call("crop_id_at", 3)))
	_check("patrol.slot7_untouched", String(_farm.call("crop_id_at", 7)) == "wheat", "wheat", String(_farm.call("crop_id_at", 7)))
	var slot4_rec := {}
	for rec4 in results:
		if int((rec4 as Dictionary).get("slot", -1)) == 4:
			slot4_rec = rec4
	_check("patrol.slot4_processed_state", not bool(_farm.call("is_empty", 4)),
		"中心格被真实播种（不是远程写入）", String(_farm.call("crop_id_at", 4)))
	_check_eq("patrol.slot4_crop_matches", String(slot4_rec.get("crop_id", "")), String(_farm.call("crop_id_at", 4)))
	_check("patrol.slot4_stand_on_bed", absf((slot4_rec.get("pos", Vector3.ZERO) as Vector3).y - BED_Y) <= 0.02,
		"中心格操作站位在苗床顶面 7.736", "y=%.3f" % (slot4_rec.get("pos", Vector3.ZERO) as Vector3).y)
	# 单次到访只做一个主事务：一次性作物采收后同次不补种（保持空）
	_check("patrol.single_transaction_per_slot", bool(_farm.call("is_empty", 0)) and bool(_farm.call("is_empty", 2)),
		"采收后不立即补种", "empty")
	# 当天不再第二轮；下一游戏日可再次调度
	var sc := int((_patrol_state() as Dictionary).get("start_count", 0))
	_sched_tick(300)
	st = _patrol_state()
	_check("patrol.no_second_round_same_day", int(st.get("start_count", 0)) == sc and String(st.get("phase", "")) == "completed",
		"completed 且不再启动", str(st))
	_ensure_seeds()
	var t8b := _day_base(11) + 8 * 3600
	_sched_reset(11, 7 * 3600 + 59 * 60)
	_prep_farm_at(t8b)
	_set_sim(t8b)
	_sched_tick(1)
	st = _patrol_state()
	_check("patrol.next_day_start", int(st.get("start_count", 0)) == 1, "1", str(st.get("start_count", 0)))
	_villager.call("cancel_farm_patrol", "probe_done")



	# ===================================================== 6. 天气中断 ========
func _abort_checks() -> void:
	_section("6. 天气中断：保留已提交、未执行取消、真实返回室内、不补巡田")
	# A) 巡田途中下雨
	_ensure_seeds()
	_force_weather("clear")
	var t8 := _day_base(12) + 8 * 3600
	_sched_reset(12, 7 * 3600 + 59 * 60)
	_prep_farm_at(t8)
	_set_sim(t8)
	_sched_tick(1)
	var st: Dictionary = _patrol_state()
	_check("abort.started", int(st.get("start_count", 0)) == 1, "1", str(st))
	var waited := _step_until_results(2, 6000)
	_check("abort.partial_progress", waited < 6000 and _live_results().size() >= 2, "已处理 >=2 格", "steps=%d" % waited)
	var live_before: Array = _live_results()
	var inv_at_abort: Dictionary = (_inv.call("export_state") as Dictionary)["items"]
	var slots_at_abort: Array = (_farm.call("export_state") as Dictionary)["slots"]
	var committed_slots: Array = []
	for rec in live_before:
		committed_slots.append(int((rec as Dictionary).get("slot", -1)))
	_force_weather("rain")
	_check_eq("abort.rain_detected", "rain", _precip())
	var stats := _step_patrol(9000)
	_sched_tick(3)
	var last: Dictionary = _villager.call("farm_patrol_last")
	_check_eq("abort.outcome", "weather_returned", String(last.get("outcome", "")))
	_check("abort.weather_abort_flag", bool(last.get("weather_abort", false)), "true", str(last.get("weather_abort", false)))
	_check("abort.return_node_indoor", INDOOR_NODES.has(String(last.get("return_node", ""))), "室内节点", String(last.get("return_node", "")))
	var results: Array = last.get("results", [])
	_check_eq("abort.records_preserved", live_before.size(), results.size())
	var slots_after: Array = (_farm.call("export_state") as Dictionary)["slots"]
	_check("abort.unprocessed_untouched", slots_after == slots_at_abort, "与中断瞬间一致", "changed")
	var inv_after: Dictionary = (_inv.call("export_state") as Dictionary)["items"]
	_check("abort.committed_inventory_preserved", inv_after == inv_at_abort, "已提交库存保留且无新增", "diff")
	# 真实走回室内（不是瞬移）
	var pos: Vector3 = _villager.get("_pos")
	var graph: Dictionary = _villager.get("graph")
	var nodes: Dictionary = graph.get("nodes", {})
	var indoor_ok := false
	var indoor_d := 99.0
	for nid in INDOOR_NODES:
		if nodes.has(nid):
			var np: Vector3 = (nodes[nid] as Dictionary)["pos"]
			var d := Vector3(pos.x - np.x, pos.y - np.y, pos.z - np.z).length()
			indoor_d = minf(indoor_d, d)
			if d <= 1.2:
				indoor_ok = true
	_check("abort.returned_indoor", indoor_ok, "距离室内节点 <=1.2m", "min_d=%.2f" % indoor_d)
	_check("abort.no_teleport", float(stats["max_jump"]) <= 0.25, "单步位移 <=0.25m", "max=%.3f" % float(stats["max_jump"]))
	# 当天转晴：不补做、不第二轮
	_force_weather("clear")
	_sched_tick(300)
	st = _patrol_state()
	_check("abort.same_day_no_makeup", String(st.get("phase", "")) == "weather_aborted" and int(st.get("start_count", 0)) == 1,
		"weather_aborted 且不再启动", str(st))
	# 次日可重新调度
	_ensure_seeds()
	var t8b := _day_base(13) + 8 * 3600
	_sched_reset(13, 7 * 3600 + 59 * 60)
	_prep_farm_at(t8b)
	_set_sim(t8b)
	_refresh_ctx()
	_sched_tick(1)
	_check("abort.next_day_restart", int((_patrol_state() as Dictionary).get("start_count", 0)) == 1,
		"1", str((_patrol_state() as Dictionary).get("start_count", 0)))
	_villager.call("cancel_farm_patrol", "probe_done")
	# B) 返程中天气转晴：仍完成返室内，不恢复巡田
	_ensure_seeds()
	_force_weather("clear")
	var t8c := _day_base(14) + 8 * 3600
	_sched_reset(14, 7 * 3600 + 59 * 60)
	_prep_farm_at(t8c)
	_set_sim(t8c)
	_refresh_ctx()
	_sched_tick(1)
	_step_until_results(1, 6000)
	_force_weather("rain")
	var return_seen := false
	for i in range(1200):
		if String(_villager.call("farm_patrol_phase")) == "returning":
			return_seen = true
			break
		if not bool(_villager.call("farm_patrol_active")):
			break
		_villager.call("sim_tick", DT, _ctx())
	_check("abort.return_phase_observed", return_seen, "returning", String(_villager.call("farm_patrol_phase")))
	_force_weather("clear")
	var stats2 := _step_patrol(9000)
	_sched_tick(3)
	var last2: Dictionary = _villager.call("farm_patrol_last")
	_check_eq("abort.return_completed_despite_clear", "weather_returned", String(last2.get("outcome", "")))
	var pos2: Vector3 = _villager.get("_pos")
	var indoor_d2 := 99.0
	for nid2 in INDOOR_NODES:
		if nodes.has(nid2):
			var np2: Vector3 = (nodes[nid2] as Dictionary)["pos"]
			indoor_d2 = minf(indoor_d2, Vector3(pos2.x - np2.x, pos2.y - np2.y, pos2.z - np2.z).length())
	_check("abort.return_indoor_after_clear", indoor_d2 <= 1.2, "<=1.2m", "min_d=%.2f" % indoor_d2)
	_check("abort.return_no_second_round", int((_patrol_state() as Dictionary).get("start_count", 0)) == 1,
		"未重新启动", str((_patrol_state() as Dictionary).get("start_count", 0)))
	_check("abort.no_teleport_return", float(stats2["max_jump"]) <= 0.25, "单步位移 <=0.25m", "max=%.3f" % float(stats2["max_jump"]))
	_scheduler_clear()
	_force_weather("clear")


	# ===================================================== 7. 视觉 / 状态 ======
func _view_and_state_checks() -> void:
	_section("7. 视觉投影随权威状态、库存解耦、P1 状态导出恢复")
	var view: Object = _main.call("farm_view")
	_check("view.exists", view != null, "IsleFarmView", "null")
	if view == null:
		return
	for i in range(6):
		_main.call("_update_farm", 0.25)
	var mismatch: Array = []
	var filled := 0
	for i in range(9):
		var empty := bool(_farm.call("is_empty", i))
		var key := String(view.call("shown_key", i))
		if empty:
			if key != "":
				mismatch.append("slot%d empty but shown=%s" % [i, key])
		else:
			filled += 1
			var crop := String(_farm.call("crop_id_at", i))
			if String(view.call("shown_crop", i)) != crop:
				mismatch.append("slot%d want crop %s got %s" % [i, crop, String(view.call("shown_crop", i))])
			if String(view.call("shown_stage", i)).is_empty():
				mismatch.append("slot%d crop %s stage empty" % [i, crop])
			if not key.begins_with(crop + "|"):
				mismatch.append("slot%d key %s" % [i, key])
	_check("view.matches_farm_state", mismatch.is_empty(), "显示与权威状态一致", str(mismatch))
	_check_eq("view.visible_count_matches", filled, int(view.call("visible_count")))
	# 反复刷新显示不改变库存（库存不依赖节点实例化/模型刷新）
	var inv_before: Dictionary = _inv.call("export_state")
	for i in range(20):
		view.call("invalidate")
		view.call("sync")
		_main.call("_update_farm", 0.25)
	var inv_after: Dictionary = _inv.call("export_state")
	_check("view.sync_does_not_touch_inventory", inv_before == inv_after, "库存不变", "diff")
	# 状态导出 / 恢复到新农田实例
	var ex: Dictionary = _farm.call("export_state")
	var farm2: Object = FARM.new(_inv)
	farm2.call("advance_to", _farm.call("now"))
	var restored := bool(farm2.call("restore_state", ex, _farm.call("now")))
	_check("view.restore_ok", restored, "true", str(restored))
	var ex2: Dictionary = farm2.call("export_state")
	_check("view.restore_slots_equal", ex["slots"] == ex2["slots"], "九格一致", "diff")
	_check("view.restore_inventory_untouched", (_inv.call("export_state") as Dictionary) == inv_after, "恢复不改变库存", "diff")


	# ===================================================== 8. 真实窗口运行 ====
func _await_frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _wait_until(cond: Callable, max_frames: int, label: String) -> bool:
	for i in range(max_frames):
		if bool(cond.call()):
			return true
		await process_frame
	print("[P4LOOP][WINDOW] timeout waiting: %s" % label)
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


func _yard_center() -> Vector3:
	var graph: Dictionary = _villager.get("graph")
	var nodes: Dictionary = graph.get("nodes", {})
	var sum := Vector3.ZERO
	var n := 0
	for slot in SLOT_NODES.keys():
		var nid := String(SLOT_NODES[slot])
		if nodes.has(nid):
			sum += (nodes[nid] as Dictionary)["pos"]
			n += 1
	if n == 0:
		return Vector3.ZERO
	return sum / float(n)


func _window_aim(target: Vector3, dist: float, height: float = 0.55) -> void:
	var eye := target + Vector3(dist * 0.62, dist * height, dist * 0.62)
	_main.call("_pose_look", eye, target + Vector3(0, 0.5, 0), 55.0)


func _window_prep_farm() -> void:
	var now := float(_main.get("_sim_seconds"))
	_farm.call("reset")
	_farm.call("advance_to", now - 20000.0)
	_farm.call("plant", 0, "wheat", PATROL_SEASON)
	_farm.call("plant", 1, "corn", PATROL_SEASON)
	_farm.call("plant", 2, "kale", PATROL_SEASON)
	_farm.call("plant", 6, "tomato", PATROL_SEASON)
	_farm.call("advance_to", now - 5000.0)
	_farm.call("advance_to", now - 130.0)
	_farm.call("plant", 3, "kale", PATROL_SEASON)
	_farm.call("plant", 7, "wheat", PATROL_SEASON)
	_farm.call("advance_to", now - 130.0)


func _window_force_sim_time() -> void:
	# 用户设置可能把正式运行的时钟存成 real；_jump_datetime 在 real 模式下会静默返回，
	# 导致探针以为注入成功、实际仍跟随系统时间。窗口验收必须先落回 sim 主时钟。
	_main.set("_time_source", "sim")
	_main.set("_realtime", false)
	var sets: Variant = _main.get("_settings")
	if sets is Dictionary:
		(sets as Dictionary)["time_source"] = "sim"


func _window_run() -> void:
	_section("8. 真实窗口运行（正式默认行为 + 逐格巡田 + 天气中断 + 次日再巡田）")
	_window_force_sim_time()
	_main.set("_day_length", 3600.0)
	# 顺序很重要：必须先落点再开主循环。若先开 _process，真实时钟的第一帧就会在
	# “今天已过 08:00”下启动一轮巡田；随后跳回 07:58 会被调度器判为 day_rewound
	# 并锁死当天，窗口验收永远等不到 08:00。
	_main.call("_jump_datetime", BASE_Y, BASE_M, BASE_D, 7, 58, 0)
	await _await_frames(2)
	_force_weather("clear")
	_main.set("_paused", false)
	_main.set("_started", true)
	if _main.has_method("_enter_playing"):
		_main.call("_enter_playing")
	_main.set("_mode", 1)
	# 窗口模式必须恢复主控 _process（真实运行由引擎帧驱动）。
	_main.set_process(true)
	await _await_frames(30)
	_check_eq("win.playing", 1, int(_main.get("_mode")))
	# 标题菜单是独立 CanvasLayer（“开始游戏/设置/离开” + 标题字），不关掉会盖住验收截图。
	# 只调用 close() 隐藏菜单，不走 _on_menu_start（避免相机过渡打乱探针机位）。
	var menu: Variant = _main.get("_menu")
	if menu != null and bool((menu as Node).get("visible")):
		(menu as Node).call("close")
		await _wait_until(func() -> bool: return not bool((menu as Node).get("visible")), 900, "menu close")
	_check("win.menu_hidden", menu == null or not bool((menu as Node).get("visible")), "标题菜单已隐藏", "hidden")
	# 按当前模拟时间（2026-03-20 07:58）布置农田：成熟 4 + 生长 2 + 空 3
	_window_prep_farm()
	await _await_frames(3)
	_window_aim(_yard_center(), 16.0, 0.62)
	await _await_frames(5)
	var inv_before: Dictionary = (_inv.call("export_state") as Dictionary)["items"]
	var slots_before: Array = (_farm.call("export_state") as Dictionary)["slots"]
	await _shot("01_before_patrol")
	# 等 08:00 调度启动
	var started := await _wait_until(func() -> bool: return int((_patrol_state() as Dictionary).get("start_count", 0)) >= 1, 2400, "patrol start")
	_check("win.day1_started", started, "08:00 启动巡田", str(_patrol_state()))
	# 等第一次逐格事务，抓巡田中的真实画面
	var first_result := await _wait_until(func() -> bool: return _live_results().size() >= 1, 3600, "first slot result")
	_check("win.day1_first_slot", first_result, "至少处理 1 格", str(_live_results().size()))
	var vpos: Vector3 = _villager.get("_pos")
	_window_aim(vpos, 6.5, 0.55)
	await _await_frames(3)
	# 等岛民真正走上苗床顶面（y 从走道 7.536 升到床顶 7.736）再抓一张路线证据
	var on_bed := await _wait_until(func() -> bool: return float((_villager.get("_pos") as Vector3).y) >= BED_Y - 0.02, 12000, "bed surface walk")
	var bed_pos: Vector3 = _villager.get("_pos")
	_check("win.day1_bed_surface_reached", on_bed, "岛民真实踩上苗床顶面", "y=%.3f" % bed_pos.y)
	if on_bed:
		_window_aim(bed_pos, 4.0, 0.5)
		await _await_frames(3)
		await _shot("02b_on_bed_surface")
	# 等巡田结束并进入 completed（P4-CLOSE：九格全部真实到达，不应再有 unreachable）
	var done := await _wait_until(func() -> bool: return not bool(_villager.call("farm_patrol_active")) and int((_patrol_state() as Dictionary).get("start_count", 0)) >= 1, 12000, "patrol finish")
	_check("win.day1_finished", done, "巡田结束", str(_patrol_state()))
	await _await_frames(10)
	var last_day1: Dictionary = _villager.call("farm_patrol_last")
	var results_day1: Array = last_day1.get("results", [])
	var harvest_count := 0
	var plant_count := 0
	var unreachable_count := 0
	for rec in results_day1:
		var act := String((rec as Dictionary).get("action", ""))
		if act == "harvest":
			harvest_count += 1
		elif act == "plant":
			plant_count += 1
		elif act == "unreachable":
			unreachable_count += 1
	_check("win.day1_outcome", String(last_day1.get("outcome", "")) == "done", "done", String(last_day1.get("outcome", "")))
	_check("win.day1_harvests", harvest_count >= 3, ">=3 次真实采收", str(harvest_count))
	_check("win.day1_plants", plant_count >= 1, ">=1 次真实播种", str(plant_count))
	_check_eq("win.day1_unreachable", 0, unreachable_count)
	_check_eq("win.day1_visited", 9, results_day1.size())
	# 中心格真实到达证据（P4-CLOSE）：slot4 有真实记录、动作不是 unreachable、
	# 操作站位在苗床顶面 7.736 且到中心格格心 <=1.30 m。
	var day1_slot4 := {}
	for rec4 in results_day1:
		if int((rec4 as Dictionary).get("slot", -1)) == 4:
			day1_slot4 = rec4
	var s4_act := String(day1_slot4.get("action", ""))
	_check("win.day1_slot4_recorded", not day1_slot4.is_empty(), "中心格有真实逐格记录", s4_act)
	_check("win.day1_slot4_action", s4_act != "" and s4_act != "unreachable", "中心格执行真实农田操作", s4_act)
	var fy_w: Dictionary = (_main.get("_world") as Dictionary).get("front_yard", {})
	var slot_rows_w: Array = fy_w.get("slots", [])
	var s4w_w := Vector2.ZERO
	for row4 in slot_rows_w:
		if int((row4 as Dictionary).get("index", -1)) == 4:
			s4w_w = (row4 as Dictionary).get("world", Vector2.ZERO)
	var s4_pos: Vector3 = day1_slot4.get("pos", Vector3.ZERO)
	var s4_dist := Vector2(s4_pos.x, s4_pos.z).distance_to(s4w_w)
	_check("win.day1_slot4_in_reach", s4_dist <= 1.30, "中心格站位到格心 <=1.30m", "%.3f m" % s4_dist)
	_check("win.day1_slot4_on_bed", absf(s4_pos.y - BED_Y) <= 0.02, "中心格操作站在苗床顶面 7.736", "y=%.3f" % s4_pos.y)
	var inv_after: Dictionary = (_inv.call("export_state") as Dictionary)["items"]
	var slots_after: Array = (_farm.call("export_state") as Dictionary)["slots"]
	# 库存增量必须与逐格记录精确对应：播种 -1 种子，采收 +产物，首收 +1 种子。
	var inv_delta: Dictionary = {}
	for key in inv_after.keys():
		var d := int(inv_after[key]) - int(inv_before.get(key, 0))
		if d != 0:
			inv_delta[key] = d
	var expected_delta: Dictionary = {}
	for rec in results_day1:
		var r: Dictionary = rec
		var act := String(r.get("action", ""))
		var crop := String(r.get("crop_id", ""))
		if act == "plant" and crop != "":
			var sk := "seed_" + crop
			expected_delta[sk] = int(expected_delta.get(sk, 0)) - 1
		elif act == "harvest":
			var pid := String(r.get("produce_item", crop))
			expected_delta[pid] = int(expected_delta.get(pid, 0)) + int(r.get("produce_amount", 1))
			if bool(r.get("seed_returned", false)):
				var sk2 := "seed_" + crop
				expected_delta[sk2] = int(expected_delta.get(sk2, 0)) + 1
	for key2 in expected_delta.keys():
		if int(expected_delta[key2]) == 0:
			expected_delta.erase(key2)
	print("[P4] inventory day1 before=%s after=%s delta=%s expected=%s" % [JSON.stringify(inv_before), JSON.stringify(inv_after), JSON.stringify(inv_delta), JSON.stringify(expected_delta)])
	_check_eq("win.day1_inventory_delta", JSON.stringify(expected_delta), JSON.stringify(inv_delta))
	_check("win.day1_inventory_changed", inv_after != inv_before, "库存确实变化", JSON.stringify(inv_delta))
	_check("win.day1_slots_changed", slots_after != slots_before, "农田确实变化", "diff")
	_check_eq("win.day1_phase", "completed", String((_patrol_state() as Dictionary).get("phase", "")))
	_window_aim(_yard_center(), 14.0, 0.6)
	await _await_frames(3)
	await _shot("03_after_patrol")
	# 次日 07:58 布置，再等 08:00 触发，途中下雨
	_window_force_sim_time()
	_main.call("_jump_datetime", BASE_Y, BASE_M, BASE_D + 1, 7, 58, 0)
	await _await_frames(5)
	_force_weather("clear")
	_window_prep_farm()
	await _await_frames(3)
	var started2 := await _wait_until(func() -> bool: return int((_patrol_state() as Dictionary).get("start_count", 0)) >= 2, 2400, "day2 patrol start")
	_check("win.day2_started", started2, "次日 08:00 再次启动", str(_patrol_state()))
	var partial2 := await _wait_until(func() -> bool: return _live_results().size() >= 2, 7200, "day2 partial result")
	_check("win.day2_partial", partial2, "已处理 >=2 格", str(_live_results().size()))
	var live2: Array = _live_results()
	var inv_abort: Dictionary = (_inv.call("export_state") as Dictionary)["items"]
	var slots_abort: Array = (_farm.call("export_state") as Dictionary)["slots"]
	_force_weather("rain")
	await _await_frames(6)
	_check_eq("win.day2_rain", "rain", _precip())
	_window_aim(_villager.get("_pos"), 9.0, 0.6)
	await _await_frames(2)
	await _shot("04_rain_interrupt")
	var returning := await _wait_until(func() -> bool: return String(_villager.call("farm_patrol_phase")) == "returning", 1200, "returning")
	_check("win.day2_returning", returning, "returning", String(_villager.call("farm_patrol_phase")))
	_force_weather("clear")
	var finished2 := await _wait_until(func() -> bool: return not bool(_villager.call("farm_patrol_active")), 12000, "day2 return finish")
	_check("win.day2_return_finished", finished2, "返回结束", str(_patrol_state()))
	await _await_frames(10)
	var last2: Dictionary = _villager.call("farm_patrol_last")
	_check_eq("win.day2_outcome", "weather_returned", String(last2.get("outcome", "")))
	_check_eq("win.day2_return_node", true, INDOOR_NODES.has(String(last2.get("return_node", ""))))
	_check_eq("win.day2_committed_records", live2.size(), (last2.get("results", []) as Array).size())
	_check("win.day2_inventory_preserved", (_inv.call("export_state") as Dictionary)["items"] == inv_abort, "已提交库存保留", "diff")
	_check("win.day2_slots_preserved", (_farm.call("export_state") as Dictionary)["slots"] == slots_abort, "未处理格未被改动", "diff")
	var pos2: Vector3 = _villager.get("_pos")
	_window_aim(pos2, 4.5, 0.5)
	await _await_frames(3)
	await _shot("05_returned_indoor")
	# 转晴后不补巡田，但可恢复普通活动；再等一段时间确认没有第二轮
	await _await_frames(240)
	var st_clear: Dictionary = _patrol_state()
	_check("win.day2_no_makeup", String(st_clear.get("phase", "")) == "weather_aborted" and int(st_clear.get("start_count", 0)) == 2,
		"weather_aborted 且无第二轮", str(st_clear))
	_check("win.day2_villager_free", not bool(_villager.call("farm_patrol_active")), "已交还普通活动", "active")
	_window_aim(_yard_center(), 16.0, 0.62)
	await _await_frames(3)
	await _shot("06_clear_resume")
	# 再下一天：仍能正常触发巡田
	_window_force_sim_time()
	_main.call("_jump_datetime", BASE_Y, BASE_M, BASE_D + 2, 7, 58, 0)
	await _await_frames(5)
	var started3 := await _wait_until(func() -> bool: return int((_patrol_state() as Dictionary).get("start_count", 0)) >= 3, 2400, "day3 patrol start")
	_check("win.day3_next_day_start", started3, "第三天 08:00 再次启动", str(_patrol_state()))
	if bool(_villager.call("farm_patrol_active")):
		_villager.call("cancel_farm_patrol", "probe_window_end")
	_check_eq("win.shots_fail", 0, _shots_fail)
