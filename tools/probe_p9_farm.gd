extends SceneTree
## P9 / P1 —— 作物定义与九格农田数据层纯 headless 探针。
##
## 不加载 isle.tscn、不构建世界、不生成图形场景、不需要 UI/NPC。
## 只 preload 数据层脚本：scripts/isle_crops.gd、scripts/isle_farm.gd，
## 并用 scripts/isle_calendar.gd 的真实季节投影验证"季节允许新种"。
##
## 运行（推荐）：
##   "$ENG" --path "D:/休闲小岛幻境/游戏工程" --headless --script res://tools/probe_p9_farm.gd -- --out="D:/休闲小岛幻境/开发产物/P9/P1"
## 输出：out/probe_p9_farm.log、out/probe_p9_farm.json；逐项打印 expected/actual/PASS|FAIL；
## 结尾 [SUMMARY] checks=N fail=M 与 [RESULT] PASS|FAIL；退出码 0/1。
##
## 注意：不得用 --shots（main.gd 内置截图流程会改写场景/存档）。

const CROPS := preload("res://scripts/isle_crops.gd")
const FARM := preload("res://scripts/isle_farm.gd")
const CAL := preload("res://scripts/isle_calendar.gd")

const DEFAULT_OUT := "D:/休闲小岛幻境/开发产物/P9/P1"
const EPS := 0.0001

## 库存 Mock 只存在于本探针文件内；正式运行时代码不得包含任何库存实现。
## 鸭子类型接口与未来 IsleInventory 一致：
##   get_count(item_id) -> int
##   remove_item(item_id, amount) -> bool
##   add_items(item_deltas: Dictionary) -> bool（一次采收的成品+返还种子原子提交）
class MockInventory:
	var items: Dictionary = {}
	var fail_next_add := false
	var fail_next_remove := false
	var add_calls := 0
	var remove_calls := 0
	## 可选同步回调：用于验证 IsleFarm 的重入守卫（库存实现可能同步回调农田）。
	var on_remove: Callable = Callable()
	var on_add: Callable = Callable()

	func _init(initial: Dictionary = {}) -> void:
		items = initial.duplicate(true)

	func get_count(item_id: String) -> int:
		return int(items.get(item_id, 0))

	func remove_item(item_id: String, amount: int) -> bool:
		remove_calls += 1
		if on_remove.is_valid():
			var cb := on_remove
			on_remove = Callable()
			cb.call()
		if fail_next_remove:
			fail_next_remove = false
			return false
		if amount <= 0:
			return false
		var have := get_count(item_id)
		if have < amount:
			return false
		items[item_id] = have - amount
		return true

	func add_items(item_deltas: Dictionary) -> bool:
		add_calls += 1
		if on_add.is_valid():
			var cb := on_add
			on_add = Callable()
			cb.call()
		if fail_next_add:
			fail_next_add = false
			return false
		for k in item_deltas:
			if int(item_deltas[k]) < 0:
				return false
		for k in item_deltas:
			items[k] = get_count(String(k)) + int(item_deltas[k])
		return true


var out_dir := DEFAULT_OUT
var rng_seed := 20261023

var _pass := 0
var _fail := 0
var _checks: Array = []
var _lines: Array = []
var _distribution: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_parse_args()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var banner := "[P1FARM] out=%s headless=%s godot=%s" % [out_dir, str(DisplayServer.get_name() == "headless"), String(Engine.get_version_info().get("string", ""))]
	print(banner)
	_lines.append(banner)
	_section("0. 环境：纯 headless 数据层（不加载 isle.tscn）")
	var scene_names: Array = []
	for ch in root.get_children():
		scene_names.append(String(ch.name))
	var scene_loaded := scene_names.has("Isle") or scene_names.has("World") or current_scene != null
	_check("env.no_scene_loaded", not scene_loaded, "无 isle.tscn 场景节点（root 仅 autoload）", "children=%s current_scene=%s" % [str(scene_names), str(current_scene)])
	_check("env.godot_version", Engine.get_version_info().get("major", 0) == 4, "Godot 4.x", str(Engine.get_version_info().get("string", "")))
	# P4 起生产环境有了共享库存并把同一实例注入 IsleFarm；P1 的"未注入即可读"语义仍保留
	# （本探针后面仍以无库存 IsleFarm 验证 no_inventory 分支）。
	var inv_exists := FileAccess.file_exists("res://scripts/isle_inventory.gd")
	var main_src := FileAccess.get_file_as_string("res://scripts/main.gd")
	var inv_wired: bool = inv_exists and main_src.find("res://scripts/isle_inventory.gd") >= 0 \
		and main_src.find("FARM_SCRIPT.new(_inventory)") >= 0
	_check("env.inventory_in_production", inv_wired, "库存脚本存在且 main 把同一实例注入 IsleFarm（P4）", "exists=%s wired=%s" % [str(inv_exists), str(inv_wired)])

	_section("1. 五种作物定义")
	_check_crops()
	_section("2. 九格初始与播种")
	_check_planting()
	_section("3. 非法操作失败且无副作用")
	_check_invalid_ops()
	_section("4. 生长阶段只随模拟时间推进、不回退")
	_check_stages()
	_section("5. 一次性收获：wheat / watermelon / kale")
	_check_one_shot()
	_section("6. 持续再生长与首收返种：corn / tomato")
	_check_regrow()
	_section("7. 库存提交失败时农田状态不变")
	_check_inventory_failure()
	_section("8. 重复提交不产生重复种子/农产品")
	_check_duplicates()
	_section("9. 随机选种的过滤条件")
	_check_choice_filters()
	_section("10. 固定随机种子的长期分布")
	_check_distribution()
	_section("11. 状态导出与恢复")
	_check_export_restore()
	_section("12. 时间快进不自动补发多次错过的采收")
	_check_fast_forward()
	_section("13. 重复清理/中断调用不改变已提交结果")
	_check_idempotent_cleanup()
	_section("14. 重入守卫、选种纯函数与可配置再生规则")
	_check_reentrancy_and_config()
	_section("15. 补充语义：plant_removed、多轮再生、换季保留、多 seed 分布")
	_check_extra_semantics()
	_section("16. 输出与证据链契约（原子写入/失败不产假 PASS）")
	_check_output_contract()

	# 先把"本次应写入的摘要"追加进日志缓冲，再原子写入；写入失败则删掉任何旧产物，
	# 保证磁盘上不会留下"旧 checks=... fail=0 / PASS"造成假通过。
	_lines.append("[SUMMARY] checks=%d fail=%d" % [_checks.size(), _fail])
	_lines.append("[RESULT] %s" % ("PASS" if _fail == 0 else "FAIL"))
	if not _write_outputs_atomic():
		_fail += 1
		var oline := "[CHECK] output.written | expected=log+json 原子写入 | FAIL"
		print(oline)
		_checks.append({"id": "output.written", "pass": false, "expected": "log+json 原子写入", "actual": "write/rename failed"})
		_remove_outputs()
	_finish()


# ============================================================ 1 作物定义 ===
func _check_crops() -> void:
	var ids: Array = CROPS.all_ids()
	_check("crops.count", ids.size() == 5, "5", str(ids.size()))
	var uniq := {}
	for cid in ids:
		uniq[String(cid)] = true
	_check("crops.ids_unique", uniq.size() == ids.size(), "5 unique", str(uniq.size()))
	var expect := ["wheat", "corn", "watermelon", "tomato", "kale"]
	for cid in expect:
		_check("crops.has.%s" % cid, CROPS.has_crop(cid), "true", str(CROPS.has_crop(cid)))
	var maturity: Array = []
	for cid in ids:
		var c := String(cid)
		var seed := CROPS.seed_item(c)
		var produce := CROPS.produce_item(c)
		_check("crops.%s.seed_item_id" % c, seed == "seed_" + c, "seed_" + c, seed)
		_check("crops.%s.produce_item_id" % c, produce == c, c, produce)
		_check("crops.%s.seed_ne_produce" % c, seed != produce, "不同物品", "%s vs %s" % [seed, produce])
		var m := CROPS.first_maturity_seconds(c)
		maturity.append({"id": c, "seconds": m})
		# P7-FINALIZE 真实时间农作契约：首次成熟 = 参考农学天数 × REAL_SECONDS_PER_CROP_DAY(60s)。
		# 断言 25–110 现实分钟（1500–6600 秒），并要求与 REAL_DAYS_REF 代表值严格一致。
		_check("crops.%s.maturity_minutes_range" % c, m >= 1500.0 and m <= 6600.0, "25..110 min", str(m / 60.0))
		var ref_days := float(CROPS.REAL_DAYS_REF[c]["representative"])
		_check("crops.%s.real_days_mapping" % c, _near(m, ref_days * CROPS.REAL_SECONDS_PER_CROP_DAY), "%.1f s" % (ref_days * CROPS.REAL_SECONDS_PER_CROP_DAY), str(m))
		_check("crops.%s.real_days_range_valid" % c, ref_days >= 45.0 and ref_days <= 130.0, "45..130 d", "%.0f d" % ref_days)
		# P3：正式视觉阶段收敛为三档，进度 0 属于 seedling（旧 5 阶段的 seed/sprout 已合并）。
		_check("crops.%s.first_stage_seedling" % c, CROPS.stage_at(c, 0.0, m) == "seedling", "seedling", CROPS.stage_at(c, 0.0, m))
		_check("crops.%s.stage_mature_at_cycle_end" % c, CROPS.stage_at(c, m, m) == "mature", "mature", CROPS.stage_at(c, m, m))
		_check("crops.%s.harvest_amount_positive" % c, CROPS.harvest_amount(c) >= 1, ">=1", str(CROPS.harvest_amount(c)))
	_check("crops.stage_ids_count", CROPS.STAGE_IDS.size() == 3, "3", str(CROPS.STAGE_IDS.size()))
	_check("crops.stage_ids_order", CROPS.STAGE_IDS == ["seedling", "growing", "mature"], "seedling,growing,mature", str(CROPS.STAGE_IDS))
	_check("crops.stage_thresholds", CROPS.STAGE_THRESHOLDS == [0.0, 0.25, 1.0], "0.0,0.25,1.0", str(CROPS.STAGE_THRESHOLDS))
	# 成熟时间必须有真实差异：五者两两不同、彼此间隔不小于 60 秒（真实农学天数不同）。
	var mat: Array = []
	for row in maturity:
		mat.append(float((row as Dictionary)["seconds"]))
	mat.sort()
	var min_gap := 999999.0
	for i in range(1, mat.size()):
		min_gap = minf(min_gap, float(mat[i]) - float(mat[i - 1]))
	_check("crops.maturity_distinct_gap", min_gap >= 60.0, ">=60s", "min_gap=%.1fs" % min_gap)
	# 真实参考天数顺序：kale(52) < corn(75) < tomato(100) < watermelon(101) < wheat(105)
	_check("crops.maturity_order", CROPS.first_maturity_seconds("kale") < CROPS.first_maturity_seconds("corn") and CROPS.first_maturity_seconds("corn") < CROPS.first_maturity_seconds("tomato") and CROPS.first_maturity_seconds("tomato") < CROPS.first_maturity_seconds("watermelon") and CROPS.first_maturity_seconds("watermelon") < CROPS.first_maturity_seconds("wheat"), "kale<corn<tomato<watermelon<wheat", "kale=%.0f corn=%.0f tomato=%.0f watermelon=%.0f wheat=%.0f" % [CROPS.first_maturity_seconds("kale"), CROPS.first_maturity_seconds("corn"), CROPS.first_maturity_seconds("tomato"), CROPS.first_maturity_seconds("watermelon"), CROPS.first_maturity_seconds("wheat")])
	# 一次性 vs 持续再生长
	for cid in ["wheat", "watermelon", "kale"]:
		_check("crops.%s.one_shot" % cid, not CROPS.is_regrowing(cid) and CROPS.regrow_seconds(cid) < 0.0, "regrow=false, seconds=-1", "regrow=%s seconds=%.1f" % [str(CROPS.is_regrowing(cid)), CROPS.regrow_seconds(cid)])
	for cid in ["corn", "tomato"]:
		_check("crops.%s.regrowing" % cid, CROPS.is_regrowing(cid) and CROPS.regrow_seconds(cid) > 0.0, "regrow=true, seconds>0", "regrow=%s seconds=%.1f" % [str(CROPS.is_regrowing(cid)), CROPS.regrow_seconds(cid)])
	# 季节：kale 冬季可种；暖季作物冬季默认不可种，覆写参数打开后可种（配置文件不保存全局状态）。
	_check("crops.kale.winter_plantable", CROPS.plantable("kale", "winter"), "true", str(CROPS.plantable("kale", "winter")))
	_check("crops.corn.winter_not_plantable", not CROPS.plantable("corn", "winter"), "false", str(CROPS.plantable("corn", "winter")))
	_check("crops.warm_in_winter_override", CROPS.plantable("corn", "winter", true) and CROPS.plantable("watermelon", "winter", true) and CROPS.plantable("tomato", "winter", true), "true when override=true", "corn=%s watermelon=%s tomato=%s" % [str(CROPS.plantable("corn", "winter", true)), str(CROPS.plantable("watermelon", "winter", true)), str(CROPS.plantable("tomato", "winter", true))])
	_check("crops.warm_in_winter_override_isolated", not CROPS.plantable("corn", "winter", false) and not CROPS.plantable("corn", "winter"), "false without override", "false")
	# 复用真实日历季节（纯函数，不需要场景）
	var winter_sim := _sim_for_date(2026, 1, 15, 12)
	var spring_sim := _sim_for_date(2026, 4, 15, 12)
	var summer_sim := _sim_for_date(2026, 7, 15, 12)
	var autumn_sim := _sim_for_date(2026, 10, 15, 12)
	_check("calendar.winter_id", String(CAL.parts(winter_sim).get("season_id", "")) == "winter", "winter", String(CAL.parts(winter_sim).get("season_id", "")))
	_check("calendar.spring_id", String(CAL.parts(spring_sim).get("season_id", "")) == "spring", "spring", String(CAL.parts(spring_sim).get("season_id", "")))
	_check("calendar.summer_id", String(CAL.parts(summer_sim).get("season_id", "")) == "summer", "summer", String(CAL.parts(summer_sim).get("season_id", "")))
	_check("calendar.autumn_id", String(CAL.parts(autumn_sim).get("season_id", "")) == "autumn", "autumn", String(CAL.parts(autumn_sim).get("season_id", "")))
	_check("crops.season_from_calendar", CROPS.plantable("kale", String(CAL.parts(winter_sim).get("season_id", ""))) and not CROPS.plantable("corn", String(CAL.parts(winter_sim).get("season_id", ""))), "kale ok / corn rejected", "calendar season_id=%s" % String(CAL.parts(winter_sim).get("season_id", "")))


# ============================================================ 2 播种 ======
func _check_planting() -> void:
	var inv := _mock_all_seeds(10)
	var farm = FARM.new(inv)
	_check("plant.farm_slots", farm.slot_count() == 9, "9", str(farm.slot_count()))
	var all_empty := true
	for i in range(9):
		if not bool(farm.is_empty(i)):
			all_empty = false
	_check("plant.initial_all_empty", all_empty, "9 empty", str(all_empty))
	_check("plant.slot_index_ij", farm.slot_index(2, 1) == 5 and farm.slot_index(0, 0) == 0 and farm.slot_index(2, 2) == 8, "slot_index(2,1)=5", "%d" % farm.slot_index(2, 1))
	_check("plant.slot_offset_center", farm.slot_offset(4) == Vector2(0, 0), "(0,0)", str(farm.slot_offset(4)))
	_check("plant.slot_offset_corner", farm.slot_offset(0) == Vector2(-1.5, -1.5), "(-1.5,-1.5)", str(farm.slot_offset(0)))
	_check("plant.slot_ij_roundtrip", farm.slot_ij(5) == Vector2i(2, 1), "(2,1)", str(farm.slot_ij(5)))

	farm.advance_to(1000.0)
	var r := farm.plant(0, "wheat", "spring")
	_check("plant.ok", bool(r.get("ok", false)), "true", str(r))
	_check("plant.seed_consumed", inv.get_count("seed_wheat") == 9, "9", str(inv.get_count("seed_wheat")))
	_check("plant.slot_crop", farm.crop_id_at(0) == "wheat", "wheat", farm.crop_id_at(0))
	_check("plant.slot_planted_at", _near(float(farm.get_slot(0).get("planted_at", -1.0)), 1000.0), "1000.0", str(farm.get_slot(0).get("planted_at", -1.0)))
	_check("plant.slot_next_ready", _near(float(farm.get_slot(0).get("next_ready_at", -1.0)), 1000.0 + CROPS.first_maturity_seconds("wheat")), "%.1f" % (1000.0 + CROPS.first_maturity_seconds("wheat")), str(farm.get_slot(0).get("next_ready_at", -1.0)))
	_check("plant.seed_returned_flag_false", not bool(farm.get_slot(0).get("seed_returned", true)), "false", str(farm.get_slot(0).get("seed_returned", true)))
	var r2 := farm.plant(8, "corn", "summer")
	_check("plant.second_ok", bool(r2.get("ok", false)), "true", str(r2))
	_check("plant.second_seed_consumed", inv.get_count("seed_corn") == 9, "9", str(inv.get_count("seed_corn")))
	_check("plant.stage_is_seedling", farm.stage_id(0) == "seedling", "seedling", farm.stage_id(0))


# ============================================================ 3 非法操作 ===
func _check_invalid_ops() -> void:
	var inv := _mock_all_seeds(5)
	inv.items.erase("seed_watermelon")
	var farm = FARM.new(inv)
	farm.advance_to(100.0)
	# 占用地：先合法种一株作为基线，之后所有非法操作都不得改变这份状态
	farm.plant(0, "kale", "winter")
	var before := farm.export_state()
	var seeds_before := inv.get_count("seed_kale")
	var r := farm.plant(0, "kale", "winter")
	_check("invalid.occupied", not bool(r.get("ok", true)) and String(r.get("reason", "")) == "occupied", "ok=false/occupied", str(r))
	_check("invalid.occupied_no_seed_loss", inv.get_count("seed_kale") == seeds_before, str(seeds_before), str(inv.get_count("seed_kale")))
	# 越界索引
	for idx in [-1, 9, 99]:
		var rr := farm.plant(idx, "kale", "winter")
		_check("invalid.index.%d" % idx, not bool(rr.get("ok", true)) and String(rr.get("reason", "")) == "invalid_index", "invalid_index", str(rr.get("reason", "")))
	# 未知作物
	var ru := farm.plant(1, "banana", "spring")
	_check("invalid.unknown_crop", not bool(ru.get("ok", true)) and String(ru.get("reason", "")) == "unknown_crop", "unknown_crop", str(ru.get("reason", "")))
	# 季节不允许
	var rs := farm.plant(1, "wheat", "winter")
	_check("invalid.season", not bool(rs.get("ok", true)) and String(rs.get("reason", "")) == "season_not_allowed", "season_not_allowed", str(rs.get("reason", "")))
	# 缺种子（西瓜种子被移除）
	var rn := farm.plant(1, "watermelon", "summer")
	_check("invalid.no_seed", not bool(rn.get("ok", true)) and String(rn.get("reason", "")) == "no_seed", "no_seed", str(rn.get("reason", "")))
	# 无库存
	var bare = FARM.new()
	var rb := bare.plant(0, "wheat", "spring")
	_check("invalid.no_inventory", not bool(rb.get("ok", true)) and String(rb.get("reason", "")) == "no_inventory", "no_inventory", str(rb.get("reason", "")))
	# 空地与未成熟收获
	# 主时钟未同步（clock_not_ready）时禁止播种，避免首帧快照让作物瞬间成熟
	var uinv := _mock_all_seeds(3)
	var unready2 = FARM.new(uinv)
	var rcu2 := unready2.plant(0, "wheat", "spring")
	_check("invalid.clock_not_ready_no_seed_loss", not bool(rcu2.get("ok", true)) and uinv.get_count("seed_wheat") == 3, "seed stays 3", str(uinv.get_count("seed_wheat")))
	unready2.advance_to(0.0)
	var rcu3 := unready2.plant(0, "wheat", "spring")
	_check("invalid.clock_ready_after_advance", bool(rcu3.get("ok", false)), "ok=true", str(rcu3.get("ok", false)))
	# 空地与未成熟收获
	var re := farm.harvest(4)
	_check("invalid.harvest_empty", not bool(re.get("ok", true)) and String(re.get("reason", "")) == "empty", "empty", str(re.get("reason", "")))
	var rimm := farm.harvest(0)
	_check("invalid.harvest_immature", not bool(rimm.get("ok", true)) and String(rimm.get("reason", "")) == "not_mature", "not_mature", str(rimm.get("reason", "")))
	var after := farm.export_state()
	# 只比较格状态（时间同样是权威状态的一部分；这里时间未变）
	_check("invalid.no_state_change", str(before["slots"]) == str(after["slots"]), "slots unchanged", "changed=%s" % str(before["slots"] != after["slots"]))


# ============================================================ 4 阶段 ======
func _check_stages() -> void:
	var inv := _mock_all_seeds(5)
	var farm = FARM.new(inv)
	farm.set_rng_seed(7)
	# 使用接近真实 Unix 量级的绝对模拟秒（P2 实际 _sim_seconds 在 1e9 量级），
	# 这样"回退平移"不会因为贴近 0 而被 clamp 干扰。
	var base := 1800000000.0
	farm.advance_to(base)
	farm.plant(0, "kale", "spring")
	var cycle := CROPS.first_maturity_seconds("kale")
	_check("stage.at_0_seedling", farm.stage_id(0) == "seedling", "seedling", farm.stage_id(0))
	farm.advance_to(base + cycle * 0.25)
	_check("stage.at_25pct_growing", farm.stage_id(0) == "growing", "growing", farm.stage_id(0))
	farm.advance_to(base + cycle * 0.60)
	_check("stage.at_60pct_growing", farm.stage_id(0) == "growing", "growing", farm.stage_id(0))
	farm.advance_to(base + cycle * 0.90)
	_check("stage.at_90pct_growing", farm.stage_id(0) == "growing", "growing", farm.stage_id(0))
	farm.advance_to(base + cycle)
	_check("stage.at_100pct_mature", farm.stage_id(0) == "mature", "mature", farm.stage_id(0))
	_check("stage.mature_flag", farm.is_mature(0), "true", str(farm.is_mature(0)))
	# 时间回退（切时间源/拨时间）：时间戳整体平移，作物年龄不变，不退回幼苗也不冻结
	var started_before := float(farm.get_slot(0).get("cycle_started_at", 0.0))
	var target_back := base + cycle * 0.10
	farm.advance_to(target_back)
	_check("stage.backward_clock_shifted", _near(farm.now(), target_back), "%.3f" % target_back, "%.3f" % farm.now())
	_check("stage.backward_stage_kept", farm.stage_id(0) == "mature", "mature", farm.stage_id(0))
	var expected_started := started_before + (target_back - (base + cycle))
	_check("stage.backward_timestamp_shifted", _near(float(farm.get_slot(0).get("cycle_started_at", 0.0)), expected_started), "%.3f" % expected_started, "%.3f" % float(farm.get_slot(0).get("cycle_started_at", 0.0)))
	_check("stage.backward_attempt_counted", farm.backward_attempts() >= 1, ">=1", str(farm.backward_attempts()))
	# 回退后继续前进：作物不会因旧死区而冻结（立即可以继续累计）
	farm.advance_to(target_back + cycle * 0.5)
	_check("stage.after_backward_continues", farm.now() > target_back, "advances", "%.3f" % farm.now())
	farm.advance_to(base + cycle * 10.0)
	_check("stage.no_regress_after_more_time", farm.stage_id(0) == "mature", "mature", farm.stage_id(0))


# ============================================================ 5 一次性收获 =
func _check_one_shot() -> void:
	var cases := [["wheat", "spring"], ["watermelon", "summer"], ["kale", "winter"]]
	for row in cases:
		var crop := String((row as Array)[0])
		var season := String((row as Array)[1])
		var inv := _mock_all_seeds(3)
		var farm = FARM.new(inv)
		farm.advance_to(500.0)
		farm.plant(0, crop, season)
		farm.advance_to(500.0 + CROPS.first_maturity_seconds(crop))
		var produce_before := inv.get_count(crop)
		var seed_before := inv.get_count(CROPS.seed_item(crop))
		var r := farm.harvest(0)
		_check("oneshot.%s.harvest_ok" % crop, bool(r.get("ok", false)), "true", str(r))
		_check("oneshot.%s.produce_plus_1" % crop, inv.get_count(crop) == produce_before + 1, str(produce_before + 1), str(inv.get_count(crop)))
		_check("oneshot.%s.seed_returned_once" % crop, inv.get_count(CROPS.seed_item(crop)) == seed_before + 1, str(seed_before + 1), str(inv.get_count(CROPS.seed_item(crop))))
		_check("oneshot.%s.slot_cleared" % crop, farm.is_empty(0), "true", str(farm.is_empty(0)))
		var r2 := farm.harvest(0)
		_check("oneshot.%s.second_harvest_fails" % crop, not bool(r2.get("ok", true)) and String(r2.get("reason", "")) == "empty", "empty", str(r2.get("reason", "")))
		_check("oneshot.%s.no_double_produce" % crop, inv.get_count(crop) == produce_before + 1, str(produce_before + 1), str(inv.get_count(crop)))


# ============================================================ 6 再生长 ======
func _check_regrow() -> void:
	for crop in ["corn", "tomato"]:
		var season := "summer"
		var inv := _mock_all_seeds(3)
		var farm = FARM.new(inv)
		var first := CROPS.first_maturity_seconds(crop)
		var regrow := CROPS.regrow_seconds(crop)
		farm.advance_to(100.0)
		farm.plant(0, String(crop), season)
		farm.advance_to(100.0 + first)
		var seed_before := inv.get_count(CROPS.seed_item(crop))
		var produce_before := inv.get_count(crop)
		var r1 := farm.harvest(0)
		_check("regrow.%s.first_harvest_ok" % crop, bool(r1.get("ok", false)), "true", str(r1))
		_check("regrow.%s.first_seed_returned" % crop, inv.get_count(CROPS.seed_item(crop)) == seed_before + 1, str(seed_before + 1), str(inv.get_count(CROPS.seed_item(crop))))
		_check("regrow.%s.slot_not_cleared" % crop, not farm.is_empty(0), "still planted", "empty=%s" % str(farm.is_empty(0)))
		_check("regrow.%s.harvest_count_1" % crop, farm.harvest_count(0) == 1, "1", str(farm.harvest_count(0)))
		_check("regrow.%s.seed_flag_true" % crop, farm.seed_returned(0), "true", str(farm.seed_returned(0)))
		_check("regrow.%s.next_ready" % crop, _near(float(farm.get_slot(0).get("next_ready_at", -1.0)), 100.0 + first + regrow), "%.1f" % (100.0 + first + regrow), str(farm.get_slot(0).get("next_ready_at", -1.0)))
		var rimm := farm.harvest(0)
		_check("regrow.%s.early_harvest_fails" % crop, not bool(rimm.get("ok", true)) and String(rimm.get("reason", "")) == "not_mature", "not_mature", str(rimm.get("reason", "")))
		farm.advance_to(100.0 + first + regrow)
		var seed_mid := inv.get_count(CROPS.seed_item(crop))
		var r2 := farm.harvest(0)
		_check("regrow.%s.second_harvest_ok" % crop, bool(r2.get("ok", false)), "true", str(r2))
		_check("regrow.%s.second_no_seed_return" % crop, inv.get_count(CROPS.seed_item(crop)) == seed_mid, str(seed_mid), str(inv.get_count(CROPS.seed_item(crop))))
		_check("regrow.%s.produce_plus_2" % crop, inv.get_count(crop) == produce_before + 2, str(produce_before + 2), str(inv.get_count(crop)))
		_check("regrow.%s.harvest_count_2" % crop, farm.harvest_count(0) == 2, "2", str(farm.harvest_count(0)))
		_check("regrow.%s.slot_stays" % crop, not farm.is_empty(0), "still planted", "empty=%s" % str(farm.is_empty(0)))
		_check("regrow.%s.next_ready_advances" % crop, _near(float(farm.get_slot(0).get("next_ready_at", -1.0)), 100.0 + first + regrow * 2.0), "%.1f" % (100.0 + first + regrow * 2.0), str(farm.get_slot(0).get("next_ready_at", -1.0)))
		# P7-FINALIZE（用户规则）：每株最多成功收获 3 次（含首收），第 3 次后植株结束、格子回空地。
		_check("regrow.%s.cycle_limit_three" % crop, CROPS.harvest_cycle_limit(String(crop)) == 3, "3", str(CROPS.harvest_cycle_limit(String(crop))))
		farm.advance_to(100.0 + first + regrow * 2.0)
		var seed_before3 := inv.get_count(CROPS.seed_item(crop))
		var r3 := farm.harvest(0)
		_check("regrow.%s.third_harvest_ok" % crop, bool(r3.get("ok", false)), "true", str(r3))
		_check("regrow.%s.third_plant_removed" % crop, bool(r3.get("plant_removed", false)) and farm.is_empty(0), "plant_removed=true + empty", "removed=%s empty=%s" % [str(r3.get("plant_removed", null)), str(farm.is_empty(0))])
		_check("regrow.%s.third_no_seed_return" % crop, inv.get_count(CROPS.seed_item(crop)) == seed_before3, str(seed_before3), str(inv.get_count(CROPS.seed_item(crop))))
		_check("regrow.%s.produce_plus_3" % crop, inv.get_count(String(crop)) == produce_before + 3, str(produce_before + 3), str(inv.get_count(String(crop))))
		_check("regrow.%s.harvest_count_reset" % crop, farm.harvest_count(0) == 0, "0", str(farm.harvest_count(0)))
		var r4 := farm.harvest(0)
		_check("regrow.%s.fourth_harvest_empty" % crop, not bool(r4.get("ok", true)) and String(r4.get("reason", "")) == "empty", "empty", str(r4.get("reason", "")))
		# 第 3 次收获后可以被重新自动播种（正常种植流程；不会自动复活旧株）。
		var replant := farm.plant_auto(0, "summer")
		_check("regrow.%s.replant_after_end" % crop, bool(replant.get("ok", false)) and not farm.is_empty(0), "plant ok + not empty", str(replant))


# ============================================================ 7 库存失败 ===
func _check_inventory_failure() -> void:
	var inv := _mock_all_seeds(5)
	var farm = FARM.new(inv)
	farm.advance_to(100.0)
	farm.plant(0, "kale", "spring")
	farm.advance_to(100.0 + CROPS.first_maturity_seconds("kale"))
	var before := farm.export_state()
	var produce_before := inv.get_count("kale")
	var seed_before := inv.get_count("seed_kale")
	inv.fail_next_add = true
	var r := farm.harvest(0)
	_check("invfail.add_rejected", not bool(r.get("ok", true)) and String(r.get("reason", "")) == "inventory_add_failed", "inventory_add_failed", str(r))
	_check("invfail.state_unchanged", before["slots"] == farm.export_state()["slots"], "slots unchanged", "changed=%s" % str(before["slots"] != farm.export_state()["slots"]))
	_check("invfail.produce_unchanged", inv.get_count("kale") == produce_before, str(produce_before), str(inv.get_count("kale")))
	_check("invfail.seed_unchanged", inv.get_count("seed_kale") == seed_before, str(seed_before), str(inv.get_count("seed_kale")))
	var retry := farm.harvest(0)
	_check("invfail.retry_ok", bool(retry.get("ok", false)), "true after retry", str(retry))
	_check("invfail.retry_single_produce", inv.get_count("kale") == produce_before + 1, str(produce_before + 1), str(inv.get_count("kale")))
	# 扣种子失败
	var farm2 = FARM.new(inv)
	farm2.advance_to(200.0)
	var seeds2 := inv.get_count("seed_wheat")
	inv.fail_next_remove = true
	var rp := farm2.plant(0, "wheat", "spring")
	_check("invfail.remove_rejected", not bool(rp.get("ok", true)) and String(rp.get("reason", "")) == "inventory_remove_failed", "inventory_remove_failed", str(rp))
	_check("invfail.remove_state_unchanged", farm2.is_empty(0), "empty", "empty=%s" % str(farm2.is_empty(0)))
	_check("invfail.remove_seed_unchanged", inv.get_count("seed_wheat") == seeds2, str(seeds2), str(inv.get_count("seed_wheat")))


# ============================================================ 8 重复提交 ===
func _check_duplicates() -> void:
	var inv := _mock_all_seeds(2)
	var farm = FARM.new(inv)
	farm.advance_to(0.0)
	farm.plant(0, "kale", "winter")
	var seeds_after_plant := inv.get_count("seed_kale")
	# 同一槽重复播种（模拟中断后重试）
	for i in range(3):
		var rr := farm.plant(0, "kale", "winter")
		_check("dup.plant_%d.fails" % i, not bool(rr.get("ok", true)) and String(rr.get("reason", "")) == "occupied", "occupied", str(rr.get("reason", "")))
	_check("dup.plant_no_extra_seed", inv.get_count("seed_kale") == seeds_after_plant, str(seeds_after_plant), str(inv.get_count("seed_kale")))
	farm.advance_to(CROPS.first_maturity_seconds("kale"))
	var produce_before := inv.get_count("kale")
	var first := farm.harvest(0)
	_check("dup.harvest_first_ok", bool(first.get("ok", false)), "true", str(first))
	# 同一成熟事件重复提交（一次性：空槽；三次都应失败）
	for i in range(3):
		var rr := farm.harvest(0)
		_check("dup.one_shot_harvest_%d.fails" % i, not bool(rr.get("ok", true)), "false", str(rr))
	_check("dup.produce_single", inv.get_count("kale") == produce_before + 1, str(produce_before + 1), str(inv.get_count("kale")))
	# 再生长作物：同一成熟事件重复提交也不重复发
	var farm2 = FARM.new(inv)
	farm2.advance_to(500.0)
	farm2.plant(0, "corn", "summer")
	farm2.advance_to(500.0 + CROPS.first_maturity_seconds("corn"))
	var corn_before := inv.get_count("corn")
	var seed_before := inv.get_count("seed_corn")
	var h1 := farm2.harvest(0)
	var h2 := farm2.harvest(0)
	_check("dup.regrow_first_ok", bool(h1.get("ok", false)), "true", str(h1))
	_check("dup.regrow_second_fails", not bool(h2.get("ok", true)) and String(h2.get("reason", "")) == "not_mature", "not_mature", str(h2.get("reason", "")))
	_check("dup.regrow_single_produce", inv.get_count("corn") == corn_before + 1, str(corn_before + 1), str(inv.get_count("corn")))
	_check("dup.regrow_single_seed", inv.get_count("seed_corn") == seed_before + 1, str(seed_before + 1), str(inv.get_count("seed_corn")))


# ============================================================ 9 选种过滤 ===
func _check_choice_filters() -> void:
	# 无种子 => 空串，且不生成种子
	var empty_inv := MockInventory.new()
	var farm0 = FARM.new(empty_inv)
	farm0.advance_to(0.0)
	_check("choice.no_seeds_returns_empty", farm0.choose_crop("spring") == "", "\"\"", farm0.choose_crop("spring"))
	var pa := farm0.plant_auto(0, "spring")
	_check("choice.no_target_no_seed_created", not bool(pa.get("ok", true)) and String(pa.get("reason", "")) == "no_candidate", "no_candidate", str(pa))
	_check("choice.no_seed_generated", empty_inv.items.is_empty(), "{}", str(empty_inv.items))
	# 季节过滤：冬季只允许 kale（玉米冬季不允许）
	var inv := _mock_all_seeds(5)
	var farm = FARM.new(inv)
	farm.advance_to(0.0)
	_check("choice.winter_only_kale", farm.choose_crop("winter") == "kale", "kale", farm.choose_crop("winter"))
	var wr := farm.plant_auto(0, "winter")
	_check("choice.winter_plant_kale_ok", bool(wr.get("ok", false)) and String(wr.get("crop_id", "")) == "kale", "kale planted", str(wr))
	# 夏季候选不含 wheat/kale
	var farm2 = FARM.new(_mock_all_seeds(5))
	var summer_ok := true
	for i in range(20):
		var c := farm2.choose_crop("summer")
		if not ["corn", "watermelon", "tomato"].has(c):
			summer_ok = false
	_check("choice.summer_candidates", summer_ok, "corn/watermelon/tomato", "ok=%s" % str(summer_ok))
	# 缺种子跳过：只有 seed_wheat 时，春季必须选 wheat
	var inv3 := MockInventory.new({"seed_wheat": 3})
	var farm3 = FARM.new(inv3)
	_check("choice.missing_seed_skipped", farm3.choose_crop("spring") == "wheat", "wheat", farm3.choose_crop("spring"))
	# 数量优先：田里已种 2 株 wheat，即使有种子也不能再选 wheat
	# P7-FINALIZE：旧规则"在田株数最少优先"已删除，改为候选集等概率抽样。
	# 即使田里已有 2 株 wheat，wheat 仍是合法候选，出现频率应接近 1/4（4 个春季候选），
	# 既不能完全被排除（旧行为），也不能被固定排到首位/末位。
	var inv4 := _mock_all_seeds(9)
	var farm4 = FARM.new(inv4)
	farm4.set_rng_seed(4242)
	farm4.advance_to(0.0)
	farm4.plant(0, "wheat", "spring")
	farm4.plant(1, "wheat", "spring")
	var draws := 400
	var wheat_hits := 0
	var seen := {}
	for _i in range(draws):
		var pick := farm4.choose_crop("spring")
		seen[pick] = true
		if pick == "wheat":
			wheat_hits += 1
	var wheat_share := float(wheat_hits) / float(draws)
	_check("choice.no_count_priority_but_candidate", wheat_share >= 0.15 and wheat_share <= 0.36,
		"wheat 仍为候选，份额 15%..36%（4 候选期望 25%）", "wheat_share=%.1f%% seen=%s" % [100.0 * wheat_share, str(seen.keys())])
	_check("choice.all_season_candidates_reachable", seen.size() == 4, "4 个春季候选都出现", str(seen.keys()))
	# 记录本次分布测试的固定种子
	_check("choice.rng_seed_set", true, "seed=%d" % rng_seed, "seed=%d" % rng_seed)


# ============================================================ 10 分布 =====
func _check_distribution() -> void:
	var inv := _mock_all_seeds(100000)
	var farm = FARM.new(inv)
	farm.set_rng_seed(rng_seed)
	farm.advance_to(0.0)
	var rounds := 400
	var counts := {"corn": 0, "watermelon": 0, "tomato": 0}
	var prev := ""
	var repeats := 0
	for i in range(rounds):
		var slot := -1
		for k in range(9):
			if farm.is_empty(k):
				slot = k
				break
		if slot < 0:
			farm.reset()
			slot = 0
		var pr := farm.plant_auto(slot, "summer")
		if not bool(pr.get("ok", false)):
			_check("dist.round_%d.plant_ok" % i, false, "ok", str(pr))
			continue
		var chosen := String(pr.get("crop_id", ""))
		if chosen == "":
			_check("dist.round_%d.has_candidate" % i, false, "non-empty crop", "\"\"")
			continue
		if chosen == prev:
			repeats += 1
		prev = chosen
		counts[chosen] = int(counts.get(chosen, 0)) + 1
	_distribution = counts.duplicate(true)
	var total := 0
	var min_c := 999999
	var max_c := 0
	for k in counts:
		var c := int(counts[k])
		total += c
		min_c = mini(min_c, c)
		max_c = maxi(max_c, c)
	_check("dist.total_rounds", total == rounds, str(rounds), str(total))
	_check("dist.all_candidates_used", min_c > 0, ">0 each", "min=%d max=%d counts=%s" % [min_c, max_c, str(counts)])
	# P7-FINALIZE：选种改为"候选集上等概率均匀抽样"（无均衡优先/无重复抑制）。
	# 3 个候选的均匀分布：单种期望份额 33.3%，400 次抽样 99% 区间约 [22%, 45%]。
	_check("dist.min_share", float(min_c) / float(rounds) >= 0.22, ">=22% (uniform lower band)", "%.1f%%" % (100.0 * float(min_c) / float(rounds)))
	_check("dist.max_share", float(max_c) / float(rounds) <= 0.45, "<=45% (uniform upper band)", "%.1f%%" % (100.0 * float(max_c) / float(rounds)))
	_check("dist.max_min_ratio", float(max_c) / maxf(1.0, float(min_c)) <= 1.8, "<=1.8", "%.2f" % (float(max_c) / maxf(1.0, float(min_c))))
	# 连续同种率：均匀独立抽样的理论值 = 1/3。旧的"最少在田优先+70%去重"会把该值压到 <10%，
	# 固定轮换会是 0%；因此用双边区间 [24%, 43%] 同时排除"去重"和"轮换"，比旧的单边 <=20% 更严格。
	_check("dist.consecutive_repeat_rate_random", float(repeats) / float(rounds) >= 0.24 and float(repeats) / float(rounds) <= 0.43, "24%..43% (uniform 1/3)", "%.1f%%" % (100.0 * float(repeats) / float(rounds)))
	# 卡方拟合度（df=2）：均匀随机应落在 [0.02, 13.0]（99% 区间附近）；
	# 刻意均衡会得到接近 0 的卡方，固定轮换会更小 —— 同样用双边区间排除。
	var exp_share := float(rounds) / 3.0
	var chi2 := 0.0
	for key in counts:
		var obs := float(counts[key])
		chi2 += (obs - exp_share) * (obs - exp_share) / exp_share
	_check("dist.chi_square_uniform_not_balanced", chi2 >= 0.02 and chi2 <= 13.0, "0.02..13.0 (df=2)", "chi2=%.3f" % chi2)
	var dline := "[P1FARM] distribution rounds=%d counts=%s consecutive_repeats=%d repeats_rate=%.1f%%" % [rounds, str(counts), repeats, 100.0 * float(repeats) / float(rounds)]
	print(dline)
	_lines.append(dline)


# ============================================================ 11 导出/恢复 =
func _check_export_restore() -> void:
	var inv := _mock_all_seeds(9)
	var farm = FARM.new(inv)
	farm.set_rng_seed(99)
	farm.advance_to(1000.0)
	farm.plant(0, "corn", "summer")
	farm.plant(1, "kale", "winter")
	farm.advance_to(1000.0 + CROPS.first_maturity_seconds("corn"))
	farm.harvest(0)  # corn 进入第一次再生长，seed_returned=true, harvest_count=1
	# P7-FINALIZE：成长阈值变大，改为"在收获时刻之后继续前进 1000s"，避免回拨主时钟触发
	# 旧的 _shift_slots 独立 clamp（restore 校验会拒绝该不一致状态）。这是测试时钟构造修正，
	# 不是放宽校验：restore 的完整校验逻辑未改。
	farm.advance_to(farm.now() + 100.0)  # 仍在再生成熟之前（regrow=480），用于断言 not_mature
	var snap := farm.export_state()
	_check("export.version", int(snap.get("version", -1)) == 1, "1", str(snap.get("version", -1)))
	_check("export.slots_count", (snap.get("slots") as Array).size() == 9, "9", str((snap.get("slots") as Array).size()))
	var farm2 = FARM.new(inv)
	var restored := farm2.restore_state(snap)
	_check("restore.ok", restored, "true", str(restored))
	_check("restore.sim_seconds", _near(farm2.now(), farm.now()), "%.4f" % farm.now(), "%.4f" % farm2.now())
	var same := true
	for i in range(9):
		var a: Dictionary = farm.get_slot(i)
		var b: Dictionary = farm2.get_slot(i)
		if String(a.get("crop_id", "")) != String(b.get("crop_id", "")):
			same = false
		if int(a.get("harvest_count", 0)) != int(b.get("harvest_count", 0)):
			same = false
		if bool(a.get("seed_returned", false)) != bool(b.get("seed_returned", false)):
			same = false
		if not _near(float(a.get("planted_at", 0.0)), float(b.get("planted_at", 0.0))):
			same = false
		if not _near(float(a.get("cycle_started_at", 0.0)), float(b.get("cycle_started_at", 0.0))):
			same = false
		if not _near(float(a.get("next_ready_at", 0.0)), float(b.get("next_ready_at", 0.0))):
			same = false
	_check("restore.slots_equal", same, "all 9 equal", "same=%s" % str(same))
	_check("restore.stage_equal", farm.stage_id(0) == farm2.stage_id(0) and farm.stage_id(1) == farm2.stage_id(1), "same stages", "%s/%s vs %s/%s" % [farm.stage_id(0), farm.stage_id(1), farm2.stage_id(0), farm2.stage_id(1)])
	var early := farm2.harvest(0)
	_check("restore.not_mature_before_regrow", not bool(early.get("ok", true)) and String(early.get("reason", "")) == "not_mature", "not_mature", str(early.get("reason", "")))
	farm2.advance_to(float(farm2.get_slot(0).get("next_ready_at", 0.0)))
	var later := farm2.harvest(0)
	_check("restore.harvest_works_after", bool(later.get("ok", false)), "true after reaching next_ready", str(later))
	# 读档时主时钟 ≠ 存档时刻（real 模式换天 / 切时间源）：按 delta 平移，阶段保持
	var farm_clock = FARM.new(inv)
	var clock_now := 5000.0
	var ok_clock := farm_clock.restore_state(snap, clock_now)
	_check("restore.with_current_clock_ok", ok_clock, "true", str(ok_clock))
	_check("restore.with_current_clock_now", _near(farm_clock.now(), clock_now), "%.1f" % clock_now, "%.1f" % farm_clock.now())
	_check("restore.with_current_clock_stage_kept", farm_clock.stage_id(0) == farm.stage_id(0) and farm_clock.stage_id(1) == farm.stage_id(1), "same stages", "%s/%s vs %s/%s" % [farm_clock.stage_id(0), farm_clock.stage_id(1), farm.stage_id(0), farm.stage_id(1)])
	var saved_next := float((snap["slots"] as Array)[0].get("next_ready_at", 0.0))
	var exp_next := saved_next + (clock_now - float(snap.get("saved_at_sim_seconds", 0.0)))
	_check("restore.with_current_clock_shifted", _near(float(farm_clock.get_slot(0).get("next_ready_at", 0.0)), exp_next), "%.1f" % exp_next, "%.1f" % float(farm_clock.get_slot(0).get("next_ready_at", 0.0)))
	# 非法数据防御：失败时状态不变
	var bad_cases: Array = []
	var bad := snap.duplicate(true)
	bad["version"] = 99
	bad_cases.append(bad)
	bad = snap.duplicate(true)
	bad["slots"] = (snap["slots"] as Array).slice(0, 8)
	bad_cases.append(bad)
	bad = snap.duplicate(true)
	(bad["slots"] as Array)[2] = {"crop_id": "banana", "planted_at": 0.0, "cycle_started_at": 0.0, "next_ready_at": 0.0, "harvest_count": 0, "seed_returned": false}
	bad_cases.append(bad)
	bad = snap.duplicate(true)
	(bad["slots"] as Array)[2] = {"crop_id": "wheat", "planted_at": -5.0, "cycle_started_at": 0.0, "next_ready_at": 0.0, "harvest_count": 0, "seed_returned": false}
	bad_cases.append(bad)
	bad = snap.duplicate(true)
	(bad["slots"] as Array)[2] = {"crop_id": "wheat", "planted_at": 0.0, "cycle_started_at": 0.0, "next_ready_at": 3000.0, "harvest_count": 2, "seed_returned": true}
	bad_cases.append(bad)
	bad = snap.duplicate(true)
	# 导出同时含旧别名 saved_at_sim_seconds 与权威 saved_at_clock_seconds；
	# 伪造"存档时刻"必须两个键一起改，否则权威键仍合法（读取优先用权威键）。
	bad["saved_at_sim_seconds"] = -1.0
	bad["saved_at_clock_seconds"] = -1.0
	bad_cases.append(bad)
	# 种子返还状态与采收次数矛盾：持续作物已收 1 次却把 returned 置 false
	bad = snap.duplicate(true)
	(bad["slots"] as Array)[3] = {"crop_id": "corn", "planted_at": 0.0, "cycle_started_at": 1000.0, "next_ready_at": 2000.0, "harvest_count": 1, "seed_returned": false}
	bad_cases.append(bad)
	# 未采收却声称已返还种子
	bad = snap.duplicate(true)
	(bad["slots"] as Array)[4] = {"crop_id": "corn", "planted_at": 0.0, "cycle_started_at": 1000.0, "next_ready_at": 2000.0, "harvest_count": 0, "seed_returned": true}
	bad_cases.append(bad)
	# 下一次成熟时刻与本轮周期不一致
	var other_crop := "tomato"
	var good_cycle := CROPS.cycle_seconds(other_crop, 0)
	bad = snap.duplicate(true)
	(bad["slots"] as Array)[5] = {"crop_id": other_crop, "planted_at": 0.0, "cycle_started_at": 1000.0, "next_ready_at": 1000.0 + good_cycle + 500.0, "harvest_count": 0, "seed_returned": false}
	bad_cases.append(bad)
	# 本轮起点在存档时刻之后（未来时间戳）
	bad = snap.duplicate(true)
	(bad["slots"] as Array)[6] = {"crop_id": other_crop, "planted_at": 0.0, "cycle_started_at": float(snap.get("saved_at_sim_seconds", 0.0)) + 10000.0, "next_ready_at": float(snap.get("saved_at_sim_seconds", 0.0)) + 10000.0 + good_cycle, "harvest_count": 0, "seed_returned": false}
	bad_cases.append(bad)
	var state_before := farm2.export_state()
	var all_rejected := true
	for i in range(bad_cases.size()):
		var ok := farm2.restore_state(bad_cases[i] as Dictionary)
		if ok:
			all_rejected = false
	_check("restore.invalid_rejected", all_rejected, "all rejected", "all_rejected=%s" % str(all_rejected))
	_check("restore.invalid_no_state_change", state_before["slots"] == farm2.export_state()["slots"], "slots unchanged", "changed=%s" % str(state_before["slots"] != farm2.export_state()["slots"]))


# ============================================================ 12 快进 =====
func _check_fast_forward() -> void:
	var inv := _mock_all_seeds(3)
	var farm = FARM.new(inv)
	farm.advance_to(0.0)
	farm.plant(0, "corn", "summer")
	var first := CROPS.first_maturity_seconds("corn")
	var regrow := CROPS.regrow_seconds("corn")
	var produce_before := inv.get_count("corn")
	# 一次性跨过 5 个再生长周期 + 半轮
	farm.advance_to(first + regrow * 5.0 + 123.0)
	var r := farm.harvest(0)
	_check("ff.harvest_ok", bool(r.get("ok", false)), "true", str(r))
	_check("ff.single_payout", inv.get_count("corn") == produce_before + 1, str(produce_before + 1), str(inv.get_count("corn")))
	var expected_next := farm.now() + regrow
	_check("ff.next_ready_from_now", _near(float(farm.get_slot(0).get("next_ready_at", -1.0)), expected_next), "%.1f" % expected_next, str(farm.get_slot(0).get("next_ready_at", -1.0)))
	var r2 := farm.harvest(0)
	_check("ff.no_immediate_second", not bool(r2.get("ok", true)) and String(r2.get("reason", "")) == "not_mature", "not_mature", str(r2.get("reason", "")))
	# 一次性作物快进也只收一次
	var farm2 = FARM.new(inv)
	farm2.advance_to(0.0)
	farm2.plant(0, "wheat", "spring")
	var wheat_before := inv.get_count("wheat")
	farm2.advance_to(CROPS.first_maturity_seconds("wheat") * 10.0)
	var w := farm2.harvest(0)
	_check("ff.one_shot_single", bool(w.get("ok", false)) and inv.get_count("wheat") == wheat_before + 1, str(wheat_before + 1), str(inv.get_count("wheat")))


# ============================================================ 13 幂等 =====
func _check_idempotent_cleanup() -> void:
	var inv := _mock_all_seeds(4)
	var farm = FARM.new(inv)
	farm.advance_to(50.0)
	farm.plant(0, "tomato", "spring")
	farm.advance_to(50.0 + CROPS.first_maturity_seconds("tomato"))
	var harvested := farm.harvest(0)
	_check("idem.harvest_ok", bool(harvested.get("ok", false)), "true", str(harvested))
	var snap := farm.export_state()
	var produce := inv.get_count("tomato")
	var seeds := inv.get_count("seed_tomato")
	# 重复"清理/中断"类调用：同一时刻重复 advance、重复查询、重复失败收获
	for i in range(5):
		farm.advance_to(farm.now())
		farm.can_plant(1, "kale", "spring")
		farm.can_harvest(0)
		farm.harvest(0)
	_check("idem.state_unchanged", snap["slots"] == farm.export_state()["slots"], "slots unchanged", "changed=%s" % str(snap["slots"] != farm.export_state()["slots"]))
	_check("idem.produce_unchanged", inv.get_count("tomato") == produce, str(produce), str(inv.get_count("tomato")))
	_check("idem.seed_unchanged", inv.get_count("seed_tomato") == seeds, str(seeds), str(inv.get_count("seed_tomato")))
	# 时间未推进 => 状态不变（暂停语义）
	var before_stage := farm.stage_id(0)
	farm.advance_to(farm.now())
	_check("idem.pause_no_growth", farm.stage_id(0) == before_stage, before_stage, farm.stage_id(0))
	# reset 后重复调用不产生物品
	var produce2 := inv.get_count("tomato")
	farm.reset()
	farm.reset()
	_check("idem.reset_no_items", inv.get_count("tomato") == produce2, str(produce2), str(inv.get_count("tomato")))
	_check("idem.reset_all_empty", farm.is_empty(0) and farm.is_empty(8), "true", "%s/%s" % [str(farm.is_empty(0)), str(farm.is_empty(8))])


# ==================================================== 14 重入/配置 =====
func _check_reentrancy_and_config() -> void:
	# F1：库存 remove_item 同步回调再播一次 => 内层 busy，外层只扣 1 颗种子
	var inv_r := _mock_all_seeds(5)
	var farm_r = FARM.new(inv_r)
	farm_r.advance_to(0.0)
	var inner_r: Dictionary = {}
	inv_r.on_remove = func() -> void:
		inner_r["res"] = farm_r.plant(1, "wheat", "spring")
	var outer_r := farm_r.plant(0, "wheat", "spring")
	_check("reentry.plant_outer_ok", bool(outer_r.get("ok", false)), "true", str(outer_r))
	_check("reentry.plant_inner_busy", String((inner_r.get("res", {}) as Dictionary).get("reason", "")) == "busy", "busy", str(inner_r.get("res", {})))
	_check("reentry.plant_single_seed", inv_r.get_count("seed_wheat") == 4, "4", str(inv_r.get_count("seed_wheat")))
	_check("reentry.plant_inner_no_slot", farm_r.is_empty(1), "true", str(farm_r.is_empty(1)))
	# F1：库存 add_items 同步回调再收一次 => 内层 busy，只发 1 份成品 + 1 颗种子
	var inv_a := _mock_all_seeds(5)
	var farm_a = FARM.new(inv_a)
	farm_a.advance_to(0.0)
	farm_a.plant(0, "corn", "summer")
	farm_a.advance_to(CROPS.first_maturity_seconds("corn"))
	var prod_a := inv_a.get_count("corn")
	var seed_a := inv_a.get_count("seed_corn")
	var inner_a: Dictionary = {}
	inv_a.on_add = func() -> void:
		inner_a["res"] = farm_a.harvest(0)
	var h_outer := farm_a.harvest(0)
	_check("reentry.harvest_outer_ok", bool(h_outer.get("ok", false)), "true", str(h_outer))
	_check("reentry.harvest_inner_busy", String((inner_a.get("res", {}) as Dictionary).get("reason", "")) == "busy", "busy", str(inner_a.get("res", {})))
	_check("reentry.harvest_single_produce", inv_a.get_count("corn") == prod_a + 1, str(prod_a + 1), str(inv_a.get_count("corn")))
	_check("reentry.harvest_single_seed", inv_a.get_count("seed_corn") == seed_a + 1, str(seed_a + 1), str(inv_a.get_count("seed_corn")))
	_check("reentry.harvest_count_once", farm_a.harvest_count(0) == 1, "1", str(farm_a.harvest_count(0)))
	# F7：choose_crop 是纯函数（不改状态/不改 _last_chosen）；plant_auto 失败也不改 last
	var inv_p := _mock_all_seeds(3)
	var farm_p = FARM.new(inv_p)
	farm_p.advance_to(0.0)
	farm_p.plant(0, "wheat", "spring")
	var before_p := farm_p.export_state()
	for _k in range(5):
		farm_p.choose_crop("spring")
	var after_p := farm_p.export_state()
	_check("choice.choose_is_pure", before_p["slots"] == after_p["slots"] and String(before_p.get("last_chosen", "")) == String(after_p.get("last_chosen", "")), "农田状态不变", "last=%s->%s" % [String(before_p.get("last_chosen", "")), String(after_p.get("last_chosen", ""))])
	var last_before := String(farm_p.export_state().get("last_chosen", ""))
	var fail_auto := farm_p.plant_auto(0, "spring")
	_check("choice.plant_auto_fail_keeps_last", not bool(fail_auto.get("ok", true)) and String(farm_p.export_state().get("last_chosen", "")) == last_before, "occupied 且 last 不变", "reason=%s last=%s" % [String(fail_auto.get("reason", "")), String(farm_p.export_state().get("last_chosen", ""))])
	# F6：暖季冬季是否可种是农田实例配置，不是全局 static
	var farm_w = FARM.new(_mock_all_seeds(3))
	farm_w.advance_to(0.0)
	var cp_before := farm_w.can_plant(0, "corn", "winter")
	farm_w.allow_warm_in_winter = true
	var cp_after := farm_w.can_plant(0, "corn", "winter")
	_check("config.allow_warm_instance", String(cp_before.get("reason", "")) == "season_not_allowed" and bool(cp_after.get("ok", false)), "season_not_allowed -> ok", "%s -> %s" % [str(cp_before), str(cp_after)])
	# F5：regrow 上限由纯函数按配置计算（0=默认无限；>0=显式上限），farm 直接调用它
	# P7-FINALIZE：regrow_cycles 显式上限优先；0/缺失时回落到全局默认（当前 REGROW_INFINITE=false
	# → 1+REGROW_CYCLES_DEFAULT=3），与用户"每株最多 3 次成功收获"一致。
	_check("config.regrow_limit_pure", CROPS.cycle_limit_from_def({"regrow": true, "regrow_cycles": 1}) == 1 and CROPS.cycle_limit_from_def({"regrow": true, "regrow_cycles": 0}) == 3 and CROPS.cycle_limit_from_def({"regrow": false}) == 1, "1 / 3 / 1", "%d / %d / %d" % [CROPS.cycle_limit_from_def({"regrow": true, "regrow_cycles": 1}), CROPS.cycle_limit_from_def({"regrow": true, "regrow_cycles": 0}), CROPS.cycle_limit_from_def({"regrow": false})])
	_check("config.regrow_limit_three", CROPS.harvest_cycle_limit("corn") == 3 and CROPS.harvest_cycle_limit("tomato") == 3 and CROPS.harvest_cycle_limit("wheat") == 1, "corn 3 / tomato 3 / wheat 1", "%d / %d / %d" % [CROPS.harvest_cycle_limit("corn"), CROPS.harvest_cycle_limit("tomato"), CROPS.harvest_cycle_limit("wheat")])
	# F5：首收返种由纯函数按配置判定（false 时不返种），farm 直接调用它
	_check("config.seed_return_pure", CROPS.returns_seed_from_def({"returns_seed_on_first_harvest": false}) == false and CROPS.returns_seed_from_def({}) == true and CROPS.returns_seed_on_first_harvest("kale"), "false / true / true", "%s / %s / %s" % [str(CROPS.returns_seed_from_def({"returns_seed_on_first_harvest": false})), str(CROPS.returns_seed_from_def({})), str(CROPS.returns_seed_on_first_harvest("kale"))])
	# F2：非有限时间快照被忽略，不改变时钟
	var farm_n = FARM.new(_mock_all_seeds(1))
	farm_n.advance_to(100.0)
	farm_n.advance_to(NAN)
	farm_n.advance_to(INF)
	_check("clock.nonfinite_ignored", _near(farm_n.now(), 100.0), "100.0", "%.1f" % farm_n.now())


# ============================================================ 输出/工具 ===
func _mock_all_seeds(n: int) -> MockInventory:
	var items := {}
	for cid in CROPS.all_ids():
		items[CROPS.seed_item(String(cid))] = n
	return MockInventory.new(items)


func _sim_for_date(year: int, month: int, day: int, hour: int) -> float:
	var dt := {"year": year, "month": month, "day": day, "hour": hour, "minute": 0, "second": 0}
	return float(Time.get_unix_time_from_datetime_dict(dt)) + CAL.TZ_SECONDS


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--out="):
			out_dir = s.substr(6).strip_edges().trim_suffix("/").trim_suffix("\\")
		elif s.begins_with("--seed="):
			rng_seed = int(s.substr(7))
	if out_dir == "":
		out_dir = DEFAULT_OUT


func _section(title: String) -> void:
	var line := "\n== %s ==" % title
	print(line)
	_lines.append(line)


func _check(id: String, ok: bool, expected: String, actual: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	var line := "[CHECK] %s | expected=%s actual=%s | %s" % [id, expected, actual, "PASS" if ok else "FAIL"]
	print(line)
	_lines.append(line)
	_checks.append({"id": id, "pass": ok, "expected": expected, "actual": actual})


func _near(a: float, b: float) -> bool:
	return absf(a - b) <= EPS


## 原子输出：先写 .tmp，成功后再替换正式文件；任一步失败都不把 PASS 内容落到正式路径。
func _write_outputs_atomic() -> bool:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var log_path := out_dir + "/probe_p9_farm.log"
	var json_path := out_dir + "/probe_p9_farm.json"
	var log_tmp := out_dir + "/.probe_p9_farm.log.tmp"
	var json_tmp := out_dir + "/.probe_p9_farm.json.tmp"
	var log_text := "\n".join(_lines) + "\n"
	var data := {
		"generated_at_utc": Time.get_datetime_string_from_system(true),
		"godot_version": String(Engine.get_version_info().get("string", "")),
		"probe_script": "res://tools/probe_p9_farm.gd",
		"probe_sha256": FileAccess.get_sha256("res://tools/probe_p9_farm.gd"),
		"crops_sha256": FileAccess.get_sha256("res://scripts/isle_crops.gd"),
		"farm_sha256": FileAccess.get_sha256("res://scripts/isle_farm.gd"),
		"out_dir": out_dir,
		"rng_seed": rng_seed,
		"checks_total": _checks.size(),
		"checks_pass": _pass,
		"checks_fail": _fail,
		"distribution": _distribution,
		"crops": _crop_table(),
		"checks": _checks,
		"headless": DisplayServer.get_name() == "headless",
	}
	var json_text := JSON.stringify(data, "  ")
	if not _write_text_temp(log_tmp, log_text):
		print("[P1FARM][ERROR] 无法写日志临时文件：%s" % log_tmp)
		return false
	if not _write_text_temp(json_tmp, json_text):
		print("[P1FARM][ERROR] 无法写 JSON 临时文件：%s" % json_tmp)
		_remove_path(log_tmp)
		return false
	if not _replace_file(log_tmp, log_path):
		print("[P1FARM][ERROR] 无法替换日志：%s" % log_path)
		_remove_path(log_tmp)
		_remove_path(json_tmp)
		return false
	if not _replace_file(json_tmp, json_path):
		print("[P1FARM][ERROR] 无法替换 JSON：%s" % json_path)
		_remove_path(json_tmp)
		_remove_path(log_path)
		return false
	return true


func _write_text_temp(path: String, text: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.flush()
	var err := f.get_error()
	f.close()
	return err == OK and FileAccess.file_exists(path)


func _replace_file(src: String, dst: String) -> bool:
	if FileAccess.file_exists(dst):
		DirAccess.remove_absolute(dst)
	return DirAccess.rename_absolute(src, dst) == OK


func _remove_path(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## 失败时清除正式产物，避免残留"上一次成功运行"的 PASS 日志/JSON。
func _remove_outputs() -> void:
	_remove_path(out_dir + "/probe_p9_farm.log")
	_remove_path(out_dir + "/probe_p9_farm.json")
	_remove_path(out_dir + "/.probe_p9_farm.log.tmp")
	_remove_path(out_dir + "/.probe_p9_farm.json.tmp")


# ============================================================ 15 补充语义 ===
func _check_extra_semantics() -> void:
	# plant_removed 字段：一次性作物清空=true；持续作物再生=false；失败路径也带该字段且为 false。
	var inv_h := _mock_all_seeds(5)
	var farm_h = FARM.new(inv_h)
	farm_h.advance_to(1000.0)
	farm_h.plant(0, "wheat", "spring")
	farm_h.advance_to(1000.0 + CROPS.first_maturity_seconds("wheat"))
	var hw := farm_h.harvest(0)
	_check("plant_removed.one_shot_true", bool(hw.get("plant_removed", false)) and farm_h.is_empty(0), "true + 清空", "removed=%s empty=%s" % [str(hw.get("plant_removed", null)), str(farm_h.is_empty(0))])
	farm_h.plant(1, "corn", "summer")
	var hc_fail := farm_h.harvest(1)
	_check("plant_removed.failure_field_false", hc_fail.has("plant_removed") and not bool(hc_fail.get("plant_removed", true)), "false", "has=%s val=%s" % [str(hc_fail.has("plant_removed")), str(hc_fail.get("plant_removed", null))])
	farm_h.advance_to(farm_h.now() + CROPS.first_maturity_seconds("corn"))
	var hc := farm_h.harvest(1)
	_check("plant_removed.regrow_false", not bool(hc.get("plant_removed", true)) and not farm_h.is_empty(1), "false + 保留", "removed=%s empty=%s" % [str(hc.get("plant_removed", null)), str(farm_h.is_empty(1))])

	# P7-FINALIZE：再生作物"每株最多 3 次成功收获（含首收）"，第 3 次后植株结束。
	# 逐轮验证 count/下一轮成熟时刻，并验证第 3 次后清空、第 4 次不能采收、可重新播种。
	var inv_m := _mock_all_seeds(3)
	var farm_m = FARM.new(inv_m)
	var t0 := 5000.0
	farm_m.advance_to(t0)
	farm_m.plant(0, "corn", "summer")
	var ok_multi := true
	var detail_multi := ""
	for k in range(3):
		var need := CROPS.first_maturity_seconds("corn") if k == 0 else CROPS.regrow_seconds("corn")
		farm_m.advance_to(farm_m.now() + need)
		var t_harvest := farm_m.now()
		var h := farm_m.harvest(0)
		if not bool(h.get("ok", false)):
			ok_multi = false
			detail_multi = "round=%d res=%s" % [k + 1, str(h)]
			break
		if k < 2:
			if farm_m.is_empty(0) or farm_m.harvest_count(0) != k + 1:
				ok_multi = false
				detail_multi = "round=%d count=%d empty=%s" % [k + 1, farm_m.harvest_count(0), str(farm_m.is_empty(0))]
				break
			var expect_next := t_harvest + CROPS.regrow_seconds("corn")
			if absf(farm_m.get_slot(0).get("next_ready_at", 0.0) - expect_next) > 0.01:
				ok_multi = false
				detail_multi = "round=%d next_ready mismatch" % (k + 1)
				break
		else:
			if not farm_m.is_empty(0) or not bool(h.get("plant_removed", false)):
				ok_multi = false
				detail_multi = "round3 not removed empty=%s removed=%s" % [str(farm_m.is_empty(0)), str(h.get("plant_removed", null))]
	_check("regrow.exactly_three_harvests", ok_multi, "3 轮全部成功、第 3 轮后清空", detail_multi if detail_multi != "" else "3/3 ok, removed at 3")
	var r_after := farm_m.harvest(0)
	_check("regrow.fourth_rejected", not bool(r_after.get("ok", true)) and String(r_after.get("reason", "")) == "empty", "empty", str(r_after.get("reason", "")))

	# 换季保留：夏季种下番茄，推进到冬季仍存在、已成熟、可采收（换季不销毁作物）。
	var inv_s := _mock_all_seeds(3)
	var farm_s = FARM.new(inv_s)
	var summer_sim := _sim_for_date(2026, 7, 15, 12)
	var winter_sim := _sim_for_date(2027, 1, 15, 12)
	farm_s.advance_to(summer_sim)
	var p_season := farm_s.plant(0, "tomato", "summer")
	farm_s.advance_to(winter_sim)
	var still_there := not farm_s.is_empty(0) and String(farm_s.get_slot(0).get("crop_id", "")) == "tomato"
	var mature_in_winter := farm_s.is_mature(0)
	var h_season := farm_s.harvest(0)
	_check("season.crop_survives_change", bool(p_season.get("ok", false)) and still_there, "冬季仍保留 tomato", "planted=%s still=%s" % [str(p_season), str(still_there)])
	_check("season.mature_and_harvestable_after_change", mature_in_winter and bool(h_season.get("ok", false)), "冬季成熟且可收", "mature=%s harvest=%s" % [str(mature_in_winter), str(h_season)])

	# 多 seed 分布：3 个固定种子各 300 轮自动播种，排除固定种子导致长期偏斜。
	var seed_stats: Array = []
	var ok_seeds := true
	for seed_i in [11, 22, 33]:
		var inv_d := _mock_all_seeds(999)
		var farm_d = FARM.new(inv_d)
		farm_d.set_rng_seed(int(seed_i))
		farm_d.advance_to(1000.0)
		var counts := {}
		var rounds := 0
		var idx := 0
		var prev_c := ""
		var repeats_d := 0
		for _r in range(300):
			var res := farm_d.plant_auto(idx % FARM.SLOT_COUNT, "summer")
			if bool(res.get("ok", false)):
				rounds += 1
				var cid := String(res.get("crop_id", ""))
				counts[cid] = int(counts.get(cid, 0)) + 1
				if cid == prev_c:
					repeats_d += 1
				prev_c = cid
				if rounds > 0 and rounds % FARM.SLOT_COUNT == 0:
					farm_d.reset()
			idx += 1
		var arr: Array = []
		for key in counts:
			arr.append(int(counts[key]))
		arr.sort()
		var lo := int(arr[0]) if arr.size() > 0 else 0
		var hi := int(arr[arr.size() - 1]) if arr.size() > 0 else 0
		var rate := float(repeats_d) / float(maxi(1, rounds))
		# 每个固定种子都应是均匀随机：候选份额 20%..47%，连续同种率 22%..43%（理论 1/3）。
		if counts.size() < 3 or lo < int(round(float(rounds) * 0.20)) or hi > int(round(float(rounds) * 0.47)) 				or rate < 0.22 or rate > 0.43:
			ok_seeds = false
		seed_stats.append({"seed": seed_i, "rounds": rounds, "counts": counts, "min": lo, "max": hi, "repeat_rate": rate})
	_check("dist.multi_seed_random_uniform", ok_seeds, "3 seed × 300 轮：3 候选、份额 20%..47%、连续同种率 22%..43%", JSON.stringify(seed_stats))

	# 自动播种的全部前置失败路径都不消耗 RNG（前置校验先于 choose_crop），成功路径才消耗。
	var inv_rng := _mock_all_seeds(3)
	var farm_rng = FARM.new(inv_rng)
	farm_rng.set_rng_seed(777)
	var st0 := farm_rng.rng_state()
	var r_bad_index := farm_rng.plant_auto(-1, "summer")
	var st_after_index := farm_rng.rng_state()
	var r_no_clock := farm_rng.plant_auto(0, "summer")
	var st_after_clock := farm_rng.rng_state()
	farm_rng.advance_to(1000.0)
	farm_rng.plant(0, "wheat", "spring")
	var st_before_occupied := farm_rng.rng_state()
	var r_occupied := farm_rng.plant_auto(0, "spring")
	var st_after_occupied := farm_rng.rng_state()
	var farm_noinv = FARM.new(null)
	farm_noinv.set_rng_seed(778)
	farm_noinv.advance_to(1000.0)
	var st_before_noinv := farm_noinv.rng_state()
	var r_no_inv := farm_noinv.plant_auto(0, "spring")
	var st_after_noinv := farm_noinv.rng_state()
	var inv_empty := _mock_all_seeds(0)
	var farm_nocand = FARM.new(inv_empty)
	farm_nocand.set_rng_seed(779)
	farm_nocand.advance_to(1000.0)
	var st_before_nocand := farm_nocand.rng_state()
	var r_no_cand := farm_nocand.plant_auto(0, "spring")
	var st_after_nocand := farm_nocand.rng_state()
	var st_before_ok := farm_rng.rng_state()
	var r_ok := farm_rng.plant_auto(1, "spring")
	var st_after_ok := farm_rng.rng_state()
	var fails_ok := String(r_bad_index.get("reason", "")) == "invalid_index" \
		and String(r_no_clock.get("reason", "")) == "clock_not_ready" \
		and String(r_occupied.get("reason", "")) == "occupied" \
		and String(r_no_inv.get("reason", "")) == "no_inventory" \
		and String(r_no_cand.get("reason", "")) == "no_candidate"
	var no_consume := st0 == st_after_index and st_after_index == st_after_clock \
		and st_before_occupied == st_after_occupied \
		and st_before_noinv == st_after_noinv \
		and st_before_nocand == st_after_nocand
	var success_ok := bool(r_ok.get("ok", false)) and st_after_ok != st_before_ok
	_check("choice.auto_fail_no_rng_consume", fails_ok and no_consume and success_ok,
		"5 条失败路径理由正确且 RNG 不变；成功路径 RNG 改变",
		"reasons=[%s,%s,%s,%s,%s] rng=[%d->%d->%d] occ=%d->%d noinv=%d->%d nocand=%d->%d ok=%s rng_ok=%d->%d" % [
			String(r_bad_index.get("reason", "")), String(r_no_clock.get("reason", "")),
			String(r_occupied.get("reason", "")), String(r_no_inv.get("reason", "")),
			String(r_no_cand.get("reason", "")), st0, st_after_index, st_after_clock,
			st_before_occupied, st_after_occupied, st_before_noinv, st_after_noinv,
			st_before_nocand, st_after_nocand, str(r_ok.get("ok", false)), st_before_ok, st_after_ok])

	# 负时钟/非有限时钟被忽略：不改变 now、不置 clock_ready、不产生生长。
	var inv_neg := _mock_all_seeds(2)
	var farm_neg = FARM.new(inv_neg)
	var neg_before := farm_neg.now()
	farm_neg.advance_to(-5.0)
	farm_neg.advance_to(NAN)
	var neg_after := farm_neg.now()
	var neg_plant := farm_neg.plant(0, "wheat", "spring")
	_check("clock.negative_ignored", is_equal_approx(neg_before, neg_after) \
		and String(neg_plant.get("reason", "")) == "clock_not_ready",
		"now 不变且仍未就绪", "before=%s after=%s plant_reason=%s" % [
			str(neg_before), str(neg_after), String(neg_plant.get("reason", ""))])

	# P7-FINALIZE：corn/tomato 变为"有限 3 次再生上限"，restore 的上限防御分支现在可达。
	# 有限上限作物只允许 count < 3，count>=3 的存档格必须被拒绝（正常流程第 3 次后已清空）。
	var finite_crops := 0
	for cid in CROPS.all_ids():
		if CROPS.harvest_cycle_limit(String(cid)) > 1:
			finite_crops += 1
	_check("config.finite_regrow_crop_count", finite_crops == 2,
		"corn/tomato 两个有限上限作物", "finite_crops=%d" % finite_crops)
	# restore 上限分支真实运行验证：构造 count=3 的 corn 存档格，必须整份拒绝、farm 状态不变。
	var inv_lim := _mock_all_seeds(3)
	var farm_lim = FARM.new(inv_lim)
	farm_lim.advance_to(1000.0)
	farm_lim.plant(0, "corn", "summer")
	var snap_lim := farm_lim.export_state()
	var before_lim := farm_lim.export_state()
	(snap_lim["slots"] as Array)[0] = {"crop_id": "corn", "planted_at": 1000.0, "cycle_started_at": 1000.0, "next_ready_at": 1000.0 + CROPS.regrow_seconds("corn"), "harvest_count": 3, "seed_returned": true}
	var ok_lim := farm_lim.restore_state(snap_lim)
	_check("restore.rejects_count_at_limit", not ok_lim and farm_lim.export_state()["slots"] == before_lim["slots"],
		"reject + 状态不变", "ok=%s changed=%s" % [str(ok_lim), str(farm_lim.export_state()["slots"] != before_lim["slots"])])

	# 事务回调里 reset() 被忽略：外层播种仍然完成、只扣 1 颗种子、九格只建一株。
	var inv_g := _mock_all_seeds(3)
	var farm_g = FARM.new(inv_g)
	farm_g.advance_to(1000.0)
	inv_g.on_remove = func() -> void:
		farm_g.reset()
	var outer_g := farm_g.plant(0, "wheat", "spring")
	var only_one := not farm_g.is_empty(0) and farm_g.is_empty(1)
	_check("reentry.reset_ignored_during_tx", bool(outer_g.get("ok", false)) and only_one and inv_g.get_count("seed_wheat") == 2, "ok + 单株 + 种子=2", "res=%s seed=%d" % [str(outer_g), inv_g.get_count("seed_wheat")])


# ============================================================ 16 输出契约 ===
func _check_output_contract() -> void:
	# 父路径是文件的非法输出必须失败且不落文件（证明失败路径可被识别）。
	var bad_path := "res://tools/probe_p9_farm.gd/child.tmp"
	var ok_bad := _write_text_temp(bad_path, "x")
	_check("output.invalid_path_rejected", not ok_bad and not FileAccess.file_exists(bad_path), "false + 无文件", "ok=%s exists=%s" % [str(ok_bad), str(FileAccess.file_exists(bad_path))])
	# 临时文件写入/读回/清理可用于原子替换。
	var tmp_path := out_dir + "/.probe_contract.tmp"
	var ok_write := _write_text_temp(tmp_path, "contract")
	var roundtrip := ok_write and FileAccess.get_file_as_string(tmp_path) == "contract"
	_remove_path(tmp_path)
	_check("output.temp_write_roundtrip", roundtrip and not FileAccess.file_exists(tmp_path), "写入/读回/清理一致", "write=%s roundtrip=%s" % [str(ok_write), str(roundtrip)])


func _crop_table() -> Array:
	var out: Array = []
	for cid in CROPS.all_ids():
		var c := String(cid)
		out.append({
			"id": c,
			"display_name": CROPS.display_name(c),
			"seed_item_id": CROPS.seed_item(c),
			"produce_item_id": CROPS.produce_item(c),
			"first_maturity_seconds": CROPS.first_maturity_seconds(c),
			"regrow_seconds": CROPS.regrow_seconds(c),
			"regrow": CROPS.is_regrowing(c),
			"harvest_amount": CROPS.harvest_amount(c),
			"seasons": CROPS.get_def(c).get("seasons", []),
			"winter_ok": bool(CROPS.get_def(c).get("winter_ok", false)),
			"warm_season": bool(CROPS.get_def(c).get("warm_season", false)),
		})
	return out


func _finish() -> void:
	print("\n[SUMMARY] checks=%d fail=%d" % [_checks.size(), _fail])
	var result := "PASS" if _fail == 0 else "FAIL"
	print("[RESULT] %s" % result)
	quit(0 if _fail == 0 else 1)
