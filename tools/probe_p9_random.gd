extends SceneTree
## P9 / P7-FINALIZE —— 随机性统计验收探针（headless）。
##
## 覆盖新契约（用户要求"真正随机"）：
##   A. 巡田访问顺序：main._build_farm_patrol_route() 每轮 = 九格随机排列；
##      N=200 轮统计"每格在每位"的频率落在 [N/9*0.55, N/9*1.8]；不存在固定顺序/固定循环；
##      同种子可复现、不同种子顺序不同（>=90% 不同）。
##   B. 自动选种：farm.choose_crop() 在候选集上等概率（卡方 df=K-1，p>0.01 上界 + 反均衡下界）；
##      K=3（summer）/K=4（spring）可构造；K=5 在当前作物数据下不可构造（无任何季节允许 5 种同季新种），
##      作为 NOTE 记录并改用"重田块偏置"与"无 70% 去重"两个反均衡断言覆盖同一规则。
##   C. 播种点位/访问顺序每轮重新生成：每轮内部无重复格，轮与轮之间顺序不同。
##
## 统计窗口理由（不是放宽阈值）：
##   - 巡田 N=200 轮：每格每位期望 22.2 次；二项分布 sd≈4.4，[0.55,1.8]×均值 = [12.2,40.0]
##     约 ±2.3σ/+4σ 带，200 轮足以在 1e-3 级别拒绝固定/周期顺序，同时 81 个单元格仍可控。
##   - choose_crop N=9000/12000 次：每候选期望 3000/2400 次，卡方统计量已收敛到 χ²(df)，
##     p>0.01 上界拒绝偏置；下界取 χ²_{0.001} 拒绝"确定轮转/完美均衡"的假随机。
##
## 运行：ENG --headless --path GAME --script res://tools/probe_p9_random.gd -- --out=DIR

const FARM := preload("res://scripts/isle_farm.gd")
const INV := preload("res://scripts/isle_inventory.gd")
const CROPS := preload("res://scripts/isle_crops.gd")

const DEFAULT_OUT := "D:/休闲小岛幻境/开发产物/P9/P7-finalize/evidence/farm/random"
const PATROL_ROUNDS := 200
const SEED_ROUNDS := 60
const PATROL_SEED := 20261026
const K3_N := 9000
const K4_N := 12000
const IMBALANCE_N := 4000
## 卡方临界值（1-p 分位）：上界=0.99（p>0.01），下界=0.001（反"完美轮转"假随机）。
const CHI2_UPPER := {2: 9.2103, 3: 11.3449, 4: 13.2767}
const CHI2_LOWER := {2: 0.002, 3: 0.0243, 4: 0.0908}

var out_dir := DEFAULT_OUT
var _pass := 0
var _fail := 0
var _notes: Array = []
var _lines: Array = []
var _fail_names: Array = []
var _main: Node = null
var _details: Dictionary = {}


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
	print("[RAND] out=%s headless=%s godot=%s" % [out_dir,
		str(DisplayServer.get_name() == "headless"),
		String(Engine.get_version_info().get("string", ""))])
	await _boot()
	if _main == null:
		print("[RESULT] FAIL")
		_write_report()
		quit(1)
		return
	_test_patrol_randomness()
	_test_seed_variation()
	_test_choose_crop_uniform()
	_test_anti_balance()
	_test_pick_dedupe()
	_write_report()
	var summary := "[SUMMARY] checks=%d fail=%d notes=%d" % [_pass + _fail, _fail, _notes.size()]
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


func _note(text: String) -> void:
	_notes.append(text)
	print("[NOTE] ", text)
	_lines.append("[NOTE] " + text)


func _chi2(counts: Array, expected: float) -> float:
	var chi := 0.0
	for c in counts:
		var d := float(int(c)) - expected
		chi += d * d / expected
	return chi


func _boot() -> void:
	_section("0. 正式场景加载（巡田随机性的唯一入口在 main）")
	var ps := load("res://isle.tscn") as PackedScene
	_check("env.scene_load", ps != null, "isle.tscn 可加载", str(ps != null))
	if ps == null:
		return
	_main = ps.instantiate()
	root.add_child(_main)
	await process_frame
	await process_frame
	_main.set_process(false)
	_main.set("_mode", 1)
	_check("env.main_ready", _main.has_method("_build_farm_patrol_route")
		and _main.has_method("set_farm_patrol_rng_seed"),
		"main 暴露巡田路线构建 + RNG 注入钩子", "ok")
	_check("env.farm_ready", _main.call("farm") != null, "main 已创建 IsleFarm", "ok")


func _route_slot_order() -> Array:
	var route: Array = _main.call("_build_farm_patrol_route")
	var out: Array = []
	for e in route:
		out.append(int((e as Dictionary).get("slot", -1)))
	return out


# ============================================================ A 巡田随机性 ====
func _test_patrol_randomness() -> void:
	_section("A. 巡田顺序随机（N=%d 轮）：九格排列 + 每格每位均匀 + 无固定循环" % PATROL_ROUNDS)
	_main.call("set_farm_patrol_rng_seed", PATROL_SEED)
	var orders: Array = []
	var permutation_bad := 0
	var pos_matrix: Array = []
	for p in range(9):
		var row: Array = []
		row.resize(9)
		row.fill(0)
		pos_matrix.append(row)
	for r in range(PATROL_ROUNDS):
		var order := _route_slot_order()
		orders.append(order)
		if order.size() != 9:
			permutation_bad += 1
			continue
		var seen := {}
		for pos in range(9):
			var slot := int(order[pos])
			seen[slot] = int(seen.get(slot, 0)) + 1
			if slot >= 0 and slot < 9:
				var row: Array = pos_matrix[pos]
				row[slot] = int(row[slot]) + 1
		if seen.size() != 9:
			permutation_bad += 1
	_check("random.patrol_permutation", permutation_bad == 0,
		"每轮九格各出现一次（0 次重复/缺格）", "bad_rounds=%d/%d" % [permutation_bad, PATROL_ROUNDS])
	# 每格在每位的频率：[N/9*0.55, N/9*1.8]
	var exp_cell := float(PATROL_ROUNDS) / 9.0
	var lo := exp_cell * 0.55
	var hi := exp_cell * 1.8
	var cell_bad: Array = []
	var cell_min := 1.0e9
	var cell_max := -1.0e9
	for pos in range(9):
		for slot in range(9):
			var c := int((pos_matrix[pos] as Array)[slot])
			cell_min = minf(cell_min, float(c))
			cell_max = maxf(cell_max, float(c))
			if float(c) < lo or float(c) > hi:
				cell_bad.append("pos%d/slot%d=%d ∉[%.1f,%.1f]" % [pos, slot, c, lo, hi])
	_check("random.patrol_uniform_cells", cell_bad.is_empty(),
		"81 个(位,格)频数 ∈ [%.1f,%.1f]（期望 %.1f）" % [lo, hi, exp_cell],
		"min=%d max=%d bad=%s" % [int(cell_min), int(cell_max), str(cell_bad.slice(0, 6))])
	# 每个格子总的被访问次数必须 = N（排列的直接推论）
	var totals_ok := true
	var totals: Array = []
	for slot in range(9):
		var t := 0
		for pos in range(9):
			t += int((pos_matrix[pos] as Array)[slot])
		totals.append(t)
		if t != PATROL_ROUNDS:
			totals_ok = false
	_check("random.patrol_slot_totals", totals_ok, "每格总访问 = %d" % PATROL_ROUNDS, str(totals))
	# 不存在固定循环：200 轮顺序几乎全不同；相邻轮不同；不存在 period<=4 的重复顺序
	var uniq := {}
	for o in orders:
		uniq[str(o)] = true
	_check("random.patrol_no_fixed_order", uniq.size() >= int(float(PATROL_ROUNDS) * 0.95),
		"不同顺序 >= 95%%（无固定顺序）", "unique=%d/%d" % [uniq.size(), PATROL_ROUNDS])
	var adjacent_diff := 0
	for r in range(1, orders.size()):
		if orders[r] != orders[r - 1]:
			adjacent_diff += 1
	_check("random.patrol_adjacent_diff", adjacent_diff == orders.size() - 1,
		"相邻两轮顺序全都不同", "%d/%d" % [adjacent_diff, orders.size() - 1])
	var cycle_hits := 0
	for r in range(orders.size()):
		for period in [1, 2, 3, 4]:
			if r + period < orders.size() and orders[r] == orders[r + period]:
				cycle_hits += 1
	_check("random.patrol_no_fixed_cycle", cycle_hits == 0,
		"不存在周期 <=4 的固定重复顺序", "hits=%d" % cycle_hits)
	# 相邻顺序（transition）分布：不应总是同一对
	var trans := {}
	for o in orders:
		for pos in range(8):
			var key := "%d>%d" % [int(o[pos]), int(o[pos + 1])]
			trans[key] = int(trans.get(key, 0)) + 1
	var trans_max := 0
	for k in trans.keys():
		trans_max = maxi(trans_max, int(trans[k]))
	_check("random.patrol_transitions_diverse", trans.size() >= 40 and trans_max <= int(float(PATROL_ROUNDS) * 0.2),
		"相邻格转移覆盖 >=40 种且单一转移 <=20%", "distinct=%d max=%d" % [trans.size(), trans_max])
	# 首格分布：200 轮内九个格子都应至少当过一次首格（期望几乎必然）
	var first_hits := {}
	for o in orders:
		first_hits[int(o[0])] = int(first_hits.get(int(o[0]), 0)) + 1
	_check("random.patrol_first_slot_spread", first_hits.size() == 9,
		"9 个格子都当过首格", "%d 种: %s" % [first_hits.size(), str(first_hits)])
	_details["patrol"] = {
		"rounds": PATROL_ROUNDS, "seed": PATROL_SEED,
		"cell_expected": exp_cell, "cell_bounds": [lo, hi],
		"cell_min": int(cell_min), "cell_max": int(cell_max),
		"unique_orders": uniq.size(), "transition_distinct": trans.size(),
		"first_slot_hits": first_hits,
	}


# ============================================================ B 种子差异 =======
func _test_seed_variation() -> void:
	_section("B. 不同种子产生不同首格/顺序（>=90%% 不同）")
	# 同种子可复现
	_main.call("set_farm_patrol_rng_seed", 424242)
	var a := _route_slot_order()
	_main.call("set_farm_patrol_rng_seed", 424242)
	var a2 := _route_slot_order()
	_check("random.same_seed_reproducible", a == a2, "同种子同顺序", "%s vs %s" % [str(a), str(a2)])
	var seqs: Array = []
	for i in range(SEED_ROUNDS):
		_main.call("set_farm_patrol_rng_seed", 100000 + i * 7919)
		seqs.append(_route_slot_order())
	var diff := 0
	for i in range(1, seqs.size()):
		if seqs[i] != seqs[i - 1]:
			diff += 1
	var diff_ratio := float(diff) / float(seqs.size() - 1)
	_check("random.different_seed_orders_differ", diff_ratio >= 0.90,
		">=90%% 相邻种子顺序不同", "%.1f%% (%d/%d)" % [diff_ratio * 100.0, diff, seqs.size() - 1])
	var firsts := {}
	for s in seqs:
		firsts[int((s as Array)[0])] = true
	_check("random.different_seed_first_slots", firsts.size() >= 6,
		">=6 个不同首格（60 个种子）", "distinct=%d %s" % [firsts.size(), str(firsts.keys())])
	var uniq_seqs := {}
	for s in seqs:
		uniq_seqs[str(s)] = true
	_check("random.different_seed_unique_orders", uniq_seqs.size() >= int(float(SEED_ROUNDS) * 0.95),
		">=95%% 种子产生不同完整顺序", "unique=%d/%d" % [uniq_seqs.size(), SEED_ROUNDS])
	_details["seed_variation"] = {"rounds": SEED_ROUNDS, "diff_ratio": diff_ratio,
		"first_slots": firsts.keys(), "unique_orders": uniq_seqs.size()}


# ============================================================ C choose_crop 均匀 =
func _new_inv_all_seeds() -> Object:
	var inv: Object = INV.new()
	inv.call("add_items", {"seed_wheat": 100000, "seed_corn": 100000, "seed_watermelon": 100000,
		"seed_tomato": 100000, "seed_kale": 100000})
	return inv


func _season_candidates(season: String, allow_warm: bool = false) -> Array:
	var out: Array = []
	for cid in CROPS.all_ids():
		if CROPS.plantable(String(cid), season, allow_warm):
			out.append(String(cid))
	return out


func _sample_choose(farm: Object, season: String, n: int) -> Dictionary:
	var counts := {}
	for c in CROPS.all_ids():
		counts[String(c)] = 0
	for i in range(n):
		var pick := String(farm.call("choose_crop", season))
		counts[pick] = int(counts.get(pick, 0)) + 1
	return counts


func _test_choose_crop_uniform() -> void:
	_section("C. choose_crop 等概率（卡方 df=K-1）：K=3 / K=4")
	# 先证明当前作物数据下的同季最大候选数（K=5 不可构造的客观依据）
	var sizes := {}
	for season in ["spring", "summer", "autumn", "winter"]:
		sizes[season] = _season_candidates(season, false).size()
		sizes[season + "+warm"] = _season_candidates(season, true).size()
	_details["season_candidate_sizes"] = sizes
	_check_eq("random.crop_count", 5, CROPS.all_ids().size())
	_check("random.max_candidates_leq4", int(sizes["spring"]) <= 4 and int(sizes["summer"]) <= 4
		and int(sizes["autumn"]) <= 4 and int(sizes["winter+warm"]) <= 4,
		"任意季节最多 4 种同季可种（K=5 路径不可构造）", str(sizes))
	_note("choose_crop K=5 无法从当前生产数据构造：五种作物没有任何季节能同时新种（spring=4, summer=3, autumn=3, winter+warm=4）。已用 K=3/K=4 卡方 + '重田块偏置' + '无 70%% 去重' 覆盖同一等概率规则；若未来作物 seasons 变化使 K=5 可构造，本探针会在 K=3/4 之外自然覆盖不到，需补充。")

	# K=3：summer -> corn / watermelon / tomato
	var inv3 := _new_inv_all_seeds()
	var farm3: Object = FARM.new(inv3)
	farm3.call("advance_to", 1000.0)
	farm3.call("set_rng_seed", 2026102601)
	var cand3 := _season_candidates("summer")
	_check_eq("random.k3_candidates", ["corn", "watermelon", "tomato"], cand3)
	var counts3 := _sample_choose(farm3, "summer", K3_N)
	var arr3: Array = []
	for c in cand3:
		arr3.append(int(counts3.get(String(c), 0)))
	_check_eq("random.k3_no_extra_pick", K3_N, int(arr3[0]) + int(arr3[1]) + int(arr3[2]))
	var chi3 := _chi2(arr3, float(K3_N) / 3.0)
	_check("random.k3_chi2_upper", chi3 <= float(CHI2_UPPER[2]),
		"chi2 <= %.4f（p>0.01，df=2）" % float(CHI2_UPPER[2]), "chi2=%.3f counts=%s" % [chi3, str(arr3)])
	_check("random.k3_chi2_lower", chi3 >= float(CHI2_LOWER[2]),
		"chi2 >= %.4f（拒绝完美轮转假随机）" % float(CHI2_LOWER[2]), "chi2=%.3f" % chi3)
	var shares3: Array = []
	var max_dev3 := 0.0
	for c in arr3:
		var share := float(c) / float(K3_N)
		shares3.append(snappedf(share, 0.001))
		max_dev3 = maxf(max_dev3, absf(share - 1.0 / 3.0))
	_check("random.k3_shares", max_dev3 <= 0.02,
		"三份份额≈1/3（各偏离 <=2%%）", "shares=%s max_dev=%.2f%%" % [str(shares3), max_dev3 * 100.0])
	_details["k3"] = {"n": K3_N, "candidates": cand3, "counts": counts3, "chi2": chi3, "upper": CHI2_UPPER[2], "lower": CHI2_LOWER[2]}

	# K=4：spring -> wheat / corn / tomato / kale
	var inv4 := _new_inv_all_seeds()
	var farm4: Object = FARM.new(inv4)
	farm4.call("advance_to", 1000.0)
	farm4.call("set_rng_seed", 2026102602)
	var cand4 := _season_candidates("spring")
	_check_eq("random.k4_candidates", ["wheat", "corn", "tomato", "kale"], cand4)
	var counts4 := _sample_choose(farm4, "spring", K4_N)
	var arr4: Array = []
	var sum4 := 0
	for c in cand4:
		arr4.append(int(counts4.get(String(c), 0)))
		sum4 += int(counts4.get(String(c), 0))
	_check_eq("random.k4_no_extra_pick", K4_N, sum4)
	var chi4 := _chi2(arr4, float(K4_N) / 4.0)
	_check("random.k4_chi2_upper", chi4 <= float(CHI2_UPPER[3]),
		"chi2 <= %.4f（p>0.01，df=3）" % float(CHI2_UPPER[3]), "chi2=%.3f counts=%s" % [chi4, str(arr4)])
	_check("random.k4_chi2_lower", chi4 >= float(CHI2_LOWER[3]),
		"chi2 >= %.4f（拒绝完美轮转假随机）" % float(CHI2_LOWER[3]), "chi2=%.3f" % chi4)
	var exp4 := float(K4_N) / 4.0
	var max_dev4 := 0.0
	for c in arr4:
		max_dev4 = maxf(max_dev4, absf(float(c) - exp4) / exp4)
	_check("random.k4_shares", max_dev4 <= 0.10, "各份额偏离 1/4 <= 10%%", "max_dev=%.2f%%" % (max_dev4 * 100.0))
	_details["k4"] = {"n": K4_N, "candidates": cand4, "counts": counts4, "chi2": chi4, "upper": CHI2_UPPER[3], "lower": CHI2_LOWER[3]}

	# 单一候选必然选中；无候选返回空
	var only := INV.new({"seed_kale": 2})
	var f_only: Object = FARM.new(only)
	f_only.call("advance_to", 1000.0)
	var single_ok := true
	for i in range(50):
		if String(f_only.call("choose_crop", "winter")) != "kale":
			single_ok = false
	_check("random.single_candidate", single_ok, "唯一候选 50 次都返回 kale", str(single_ok))
	var none := INV.new({"seed_watermelon": 3})
	var f_none: Object = FARM.new(none)
	f_none.call("advance_to", 1000.0)
	_check_eq("random.no_candidate", "", String(f_none.call("choose_crop", "spring")))


# ============================================================ D 反均衡 =========
func _test_anti_balance() -> void:
	_section("D. 反均衡：重田块偏置（无「最少在田优先」）与均匀分布")
	var inv := _new_inv_all_seeds()
	var farm: Object = FARM.new(inv)
	farm.call("advance_to", 1000.0)
	# 8 格全种 corn（spring 可种），若存在"在田株数最少优先"规则，choose_crop 会几乎总选非 corn。
	var plant_bad := 0
	for i in range(8):
		if not bool((farm.call("plant", i, "corn", "spring") as Dictionary).get("ok", false)):
			plant_bad += 1
	_check("random.imbalance_setup", plant_bad == 0, "8 格已种 corn", "bad=%d" % plant_bad)
	farm.call("set_rng_seed", 2026102603)
	var counts := _sample_choose(farm, "spring", IMBALANCE_N)
	var cands := _season_candidates("spring")
	var arr: Array = []
	for c in cands:
		arr.append(int(counts.get(String(c), 0)))
	var chi := _chi2(arr, float(IMBALANCE_N) / float(cands.size()))
	_check("random.no_least_in_field_bias", chi <= float(CHI2_UPPER[3]),
		"8 格已种 corn 时选种仍均匀（chi2 <= %.3f，df=3）" % float(CHI2_UPPER[3]),
		"chi2=%.3f counts=%s" % [chi, str(arr)])
	var corn_share := float(counts.get("corn", 0)) / float(IMBALANCE_N)
	_check("random.corn_share_unbiased", absf(corn_share - 0.25) <= 0.05,
		"corn 份额≈25%%（±5%%；旧均衡规则会≈0）", "%.1f%%" % (corn_share * 100.0))
	_details["imbalance"] = {"n": IMBALANCE_N, "planted": 8, "counts": counts, "chi2": chi, "corn_share": corn_share}


# ============================================================ E 无去重 =========
func _test_pick_dedupe() -> void:
	_section("E. 无 70%% 去重：相邻两次选种同种概率≈1/K")
	var inv := _new_inv_all_seeds()
	var farm: Object = FARM.new(inv)
	farm.call("advance_to", 1000.0)
	farm.call("set_rng_seed", 2026102604)
	var n := 6000
	var picks: Array = []
	for i in range(n):
		picks.append(String(farm.call("choose_crop", "spring")))
	var repeats := 0
	var seq_ok := true
	for i in range(1, n):
		if picks[i] == picks[i - 1]:
			repeats += 1
	for i in range(n):
		if not CROPS.plantable(String(picks[i]), "spring"):
			seq_ok = false
	var repeat_ratio := float(repeats) / float(n - 1)
	# K=4 时相邻同种的理论概率=1/4；旧"70% 排除上次"规则会把它压到 ≈0.3*1/3≈0.10。
	_check("random.pick_valid_candidates", seq_ok, "全部命中 spring 候选", str(seq_ok))
	_check("random.adjacent_repeat_no_dedupe", repeat_ratio >= 0.18 and repeat_ratio <= 0.32,
		"相邻同种比例∈[18%%,32%%]（理论 25%%；旧 70%% 去重≈10%%）", "%.1f%% (%d/%d)" % [repeat_ratio * 100.0, repeats, n - 1])
	# 同种子序列可复现；不同种子序列不同
	var inv_b := _new_inv_all_seeds()
	var farm_b: Object = FARM.new(inv_b)
	farm_b.call("advance_to", 1000.0)
	farm_b.call("set_rng_seed", 2026102604)
	var same := true
	for i in range(200):
		if String(farm_b.call("choose_crop", "spring")) != String(picks[i]):
			same = false
	_check("random.choose_same_seed_reproducible", same, "同种子前 200 次选种一致", str(same))
	var farm_c: Object = FARM.new(_new_inv_all_seeds())
	farm_c.call("advance_to", 1000.0)
	farm_c.call("set_rng_seed", 2026102605)
	var differs := false
	for i in range(20):
		if String(farm_c.call("choose_crop", "spring")) != String(picks[i]):
			differs = true
	_check("random.choose_different_seed_differs", differs, "不同种子序列不同", str(differs))
	_details["dedupe"] = {"n": n, "repeat_ratio": repeat_ratio, "repeats": repeats}


# ============================================================ 报告 ============
func _write_report() -> void:
	var log_path := out_dir + "/probe_p9_random.log"
	var fa := FileAccess.open(log_path, FileAccess.WRITE)
	if fa != null:
		fa.store_string("\n".join(_lines) + "\n")
		fa.close()
		print("[RAND] log=", log_path)
	var data := {
		"checks": _pass + _fail,
		"fail": _fail,
		"fail_names": _fail_names,
		"notes": _notes,
		"headless": DisplayServer.get_name() == "headless",
		"details": _details,
	}
	var jf := FileAccess.open(out_dir + "/probe_p9_random.json", FileAccess.WRITE)
	if jf != null:
		jf.store_string(JSON.stringify(data, "  "))
		jf.close()
