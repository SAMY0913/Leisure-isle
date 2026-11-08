extends SceneTree
## P6 / A —— 鱼类目录 + 库存契约 + 背包排序 + 可用规则探针（纯数据，不加载场景）。
##
## 运行方式：
##   ENG --headless --path GAME --script res://tools/probe_p9_fish_items.gd -- --out=D:/休闲小岛幻境/开发产物/P9/P6/r1_items
##
## 覆盖：
##   A 鱼类目录：6 种、id 唯一且 fish_ 前缀、DEFS 字段完整合法、显示名/稀有度/颜色/尺寸/权重、
##     全部登记为库存规范物品、known_item_ids 最后 6 位且紧跟产物之后、总数 16。
##   B 库存契约：鱼入账/查询/导出-恢复往返、非法增量与非法恢复整笔失败（快照逐字节不变）、
##     旧 STATE_VERSION=1 存档（无鱼）仍可恢复且鱼读作 0、未知 id 不部分提交、版本 2 拒绝。
##   C 背包排序：item_category / category_rank / catalog_index 正确且单调（seed < produce < fish）。
##   D 可用规则：兜底鱼 4 季 x 24 小时 x 4 天气全可用、is_available 与 DEFS 逐条一致、
##     weight_for>0 当且仅当可用、注入 rng 的决定论、500 次抽样覆盖全部 6 种。
##
## 纪律：只读消费正式目录/库存脚本，不加载 isle.tscn、不写正式存档、不改项目文件。

const CROPS := preload("res://scripts/isle_crops.gd")
const FISH := preload("res://scripts/isle_fish.gd")
const INVENTORY := preload("res://scripts/isle_inventory.gd")

const DEFAULT_OUT := "D:/休闲小岛幻境/开发产物/P9/P6"
const SEASONS := ["spring", "summer", "autumn", "winter"]
const WEATHERS := ["clear", "cloudy", "rain", "snow"]
const RARITIES := ["common", "uncommon", "rare"]
const REQUIRED_DEF_KEYS := [
	"display_name", "rarity", "color", "weight", "seasons",
	"hour_from", "hour_to", "weather", "min_size", "max_size",
]

var out_dir := DEFAULT_OUT
var _pass := 0
var _fail := 0
var _lines: Array = []
var _fail_names: Array = []


func _initialize() -> void:
	_parse_args()
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--out="):
			out_dir = s.substr(6).strip_edges().trim_suffix("/").trim_suffix("\\")
	if out_dir == "":
		out_dir = DEFAULT_OUT


func _run() -> void:
	var banner := "[P6ITEM] out=%s headless=%s godot=%s" % [
		out_dir, str(DisplayServer.get_name() == "headless"),
		String(Engine.get_version_info().get("string", ""))]
	print(banner)
	_lines.append(banner)
	_catalog_checks()
	_inventory_checks()
	_sort_checks()
	_rule_checks()
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
	var line := "[CHECK] %s | expected=%s actual=%s | %s" % [name, expected, actual, "PASS" if ok else "FAIL"]
	print(line)
	_lines.append(line)


func _check_eq(name: String, expected: Variant, actual: Variant) -> void:
	_check(name, expected == actual, str(expected), str(actual))


func _write_report() -> void:
	var log_path := out_dir + "/probe_p9_fish_items.log"
	var fa := FileAccess.open(log_path, FileAccess.WRITE)
	if fa != null:
		fa.store_string("\n".join(_lines) + "\n")
		fa.close()
		print("[P6ITEM] log=", log_path)
	var species: Array = []
	for raw in FISH.all_ids():
		var fid := String(raw)
		var def: Dictionary = FISH.get_def(fid)
		species.append({
			"id": fid,
			"name": String(def.get("display_name", "")),
			"rarity": String(def.get("rarity", "")),
			"weight": float(def.get("weight", 0.0)),
		})
	var data := {
		"checks": _pass + _fail,
		"fail": _fail,
		"fail_names": _fail_names,
		"headless": DisplayServer.get_name() == "headless",
		"godot": String(Engine.get_version_info().get("string", "")),
		"known_item_count": INVENTORY.catalog_ids().size(),
		"species": species,
	}
	var jf := FileAccess.open(out_dir + "/probe_p9_fish_items.json", FileAccess.WRITE)
	if jf != null:
		jf.store_string(JSON.stringify(data, "  "))
		jf.close()
		print("[P6ITEM] json=", out_dir + "/probe_p9_fish_items.json")


func _json(value: Variant) -> String:
	return JSON.stringify(value)


func _is_hex_color(s: String) -> bool:
	if s.length() != 7 or not s.begins_with("#"):
		return false
	var digits := "0123456789abcdef"
	var body := s.substr(1).to_lower()
	for i in range(body.length()):
		if digits.find(body[i]) < 0:
			return false
	return true


func _is_number(value: Variant) -> bool:
	var t := typeof(value)
	return t == TYPE_INT or t == TYPE_FLOAT


# =========================================================== A. 目录 ======
func _catalog_checks() -> void:
	_section("A. 鱼类目录（6 种 / 唯一 / 元数据完整 / 库存已登记）")
	var ids: Array = FISH.all_ids()
	_check_eq("a.id_count", 6, ids.size())
	_check_eq("a.FISH_IDS_count", 6, FISH.FISH_IDS.size())
	_check("a.all_ids_matches_const", _json(ids) == _json(FISH.FISH_IDS),
		"all_ids() 与 FISH_IDS 同序", _json(ids))
	var ids_mut: Array = FISH.all_ids()
	ids_mut.clear()
	_check_eq("a.all_ids_is_copy", 6, FISH.all_ids().size())

	var uniq: Dictionary = {}
	var prefix_bad: Array = []
	var meta_bad: Array = []
	var display_names: Array = []
	var rarity_counts: Dictionary = {}
	var defs_ok := 0
	for raw in ids:
		var fid := String(raw)
		if uniq.has(fid):
			meta_bad.append(fid + ":duplicate")
		uniq[fid] = true
		if not fid.begins_with("fish_"):
			prefix_bad.append(fid)
		if not FISH.has_fish(fid):
			meta_bad.append(fid + ":has_fish")
		var def: Dictionary = FISH.get_def(fid)
		if def.is_empty():
			meta_bad.append(fid + ":def_empty")
			continue
		defs_ok += 1
		for key in REQUIRED_DEF_KEYS:
			if not def.has(key):
				meta_bad.append(fid + ":missing_" + String(key))
		var dn := String(def.get("display_name", ""))
		if dn == "" or dn == fid:
			meta_bad.append(fid + ":display_name")
		display_names.append(dn)
		var rar := String(def.get("rarity", ""))
		if not RARITIES.has(rar):
			meta_bad.append(fid + ":rarity")
		rarity_counts[rar] = int(rarity_counts.get(rar, 0)) + 1
		if not _is_hex_color(String(def.get("color", ""))):
			meta_bad.append(fid + ":color")
		if not _is_number(def.get("weight", null)) or float(def.get("weight", 0.0)) <= 0.0:
			meta_bad.append(fid + ":weight")
		var seasons: Variant = def.get("seasons", null)
		if typeof(seasons) != TYPE_ARRAY:
			meta_bad.append(fid + ":seasons_type")
		else:
			for s in seasons:
				if not SEASONS.has(String(s)):
					meta_bad.append(fid + ":season_" + String(s))
		var weather: Variant = def.get("weather", null)
		if typeof(weather) != TYPE_ARRAY:
			meta_bad.append(fid + ":weather_type")
		else:
			for w in weather:
				if not WEATHERS.has(String(w)):
					meta_bad.append(fid + ":weather_" + String(w))
		var hf: Variant = def.get("hour_from", null)
		var ht: Variant = def.get("hour_to", null)
		if typeof(hf) != TYPE_INT or int(hf) < 0 or int(hf) > 23:
			meta_bad.append(fid + ":hour_from")
		if typeof(ht) != TYPE_INT or int(ht) < 0 or int(ht) > 23:
			meta_bad.append(fid + ":hour_to")
		if not _is_number(def.get("min_size", null)) or not _is_number(def.get("max_size", null)):
			meta_bad.append(fid + ":size_type")
		elif float(def.get("min_size", 0.0)) <= 0.0 or float(def.get("max_size", 0.0)) < float(def.get("min_size", 0.0)):
			meta_bad.append(fid + ":size_range")
	_check("a.ids_unique", uniq.size() == 6, "6 个唯一 id", str(uniq.size()))
	_check("a.id_prefix_fish", prefix_bad.is_empty(), "0 个非 fish_ 前缀", str(prefix_bad))
	_check("a.defs_complete", meta_bad.is_empty(), "0 处元数据问题", str(meta_bad))
	_check_eq("a.defs_count", 6, defs_ok)
	var dup_display: Array = []
	var seen_dn: Dictionary = {}
	for dn in display_names:
		if seen_dn.has(dn):
			dup_display.append(String(dn))
		seen_dn[dn] = true
	_check("a.display_names_unique", dup_display.is_empty(), "中文显示名互不相同", str(dup_display))
	_check("a.display_name_nonempty", display_names.size() == 6 and not display_names.has(""),
		"6 个非空中文名", str(display_names))
	_check("a.rarity_domain", rarity_counts.size() >= 2
		and int(rarity_counts.get("common", 0)) >= 1
		and int(rarity_counts.get("uncommon", 0)) >= 1
		and int(rarity_counts.get("rare", 0)) >= 1,
		"同时含 common/uncommon/rare", str(rarity_counts))
	_check_eq("a.fallback_has_fish", true, FISH.has_fish(FISH.fallback_id()))
	var fb: Dictionary = FISH.get_def(FISH.fallback_id())
	_check("a.fallback_always_structural",
		Array(fb.get("seasons", [])).is_empty() and Array(fb.get("weather", [])).is_empty()
		and int(fb.get("hour_from", -1)) == 0 and int(fb.get("hour_to", -1)) == 23,
		"兜底鱼 seasons/weather 为空且 0..23", _json({"seasons": fb.get("seasons", []), "weather": fb.get("weather", []), "hour_from": fb.get("hour_from"), "hour_to": fb.get("hour_to")}))
	# get_def 必须是深拷贝
	var def_a: Dictionary = FISH.get_def("fish_crucian")
	var def_b: Dictionary = FISH.get_def("fish_crucian")
	def_b["display_name"] = "MUTATED"
	var def_c: Dictionary = FISH.get_def("fish_crucian")
	_check("a.get_def_deep_copy",
		String(def_a.get("display_name", "")) == "鲫鱼" and String(def_c.get("display_name", "")) == "鲫鱼"
		and String(def_a.get("display_name", "")) != String(def_b.get("display_name", "")),
		"修改副本不影响 DEFS", String(def_c.get("display_name", "")))
	_check("a.get_def_unknown_empty", FISH.get_def("fish_bogus").is_empty(), "{}", str(FISH.get_def("fish_bogus")))
	_check_eq("a.rarity_unknown", "", FISH.rarity("fish_bogus"))
	_check_eq("a.display_name_unknown", "fish_bogus", FISH.display_name("fish_bogus"))

	# 库存登记：总数 16、最后 6 位恰为鱼、鱼紧跟产物之后。
	var inv = INVENTORY.new()
	var known: Array = inv.known_item_ids()
	_check_eq("a.known_total", 16, known.size())
	_check("a.known_matches_static", _json(known) == _json(INVENTORY.catalog_ids()),
		"known_item_ids 与 catalog_ids 同序", _json(known))
	var expected_known: Array = []
	for crop_id in CROPS.CROP_IDS:
		expected_known.append(CROPS.seed_item(String(crop_id)))
	for crop_id in CROPS.CROP_IDS:
		expected_known.append(CROPS.produce_item(String(crop_id)))
	for raw_fish in FISH.FISH_IDS:
		expected_known.append(String(raw_fish))
	_check("a.known_canonical_order", _json(known) == _json(expected_known),
		"种子 -> 产物 -> 鱼", _json(known))
	var tail: Array = known.slice(known.size() - 6, known.size())
	_check("a.fish_are_last_six", _json(tail) == _json(FISH.all_ids()),
		_json(FISH.all_ids()), _json(tail))
	var fish_after_produce := true
	for i in range(6):
		var idx := 10 + i
		if idx >= known.size() or String(known[idx]) != String(FISH.FISH_IDS[i]):
			fish_after_produce = false
	_check("a.fish_follow_produce", fish_after_produce, "known[10..15] == FISH_IDS", str(known.slice(10, known.size())))
	var unknown_known: Array = []
	for raw_fish in FISH.FISH_IDS:
		if not inv.is_known_item(String(raw_fish)):
			unknown_known.append(String(raw_fish))
	_check("a.fish_is_known_item", unknown_known.is_empty(), "6 种鱼全部 is_known_item", str(unknown_known))
	_check_eq("a.known_rejects_unknown", false, inv.is_known_item("fish_bogus"))


# =========================================================== B. 库存 ======
func _fresh_inv():
	return INVENTORY.new()


func _inventory_checks() -> void:
	_section("B. 库存契约（鱼入账 / 导出恢复 / 原子性 / 老存档兼容）")
	_check_eq("b.state_version", 1, int(INVENTORY.STATE_VERSION))
	var inv = _fresh_inv()
	_check("b.empty_snapshot", inv.item_snapshot().is_empty(), "{}", str(inv.item_snapshot()))
	_check_eq("b.empty_total", 0, int(inv.total_count()))

	# 鱼入账 + 查询 + 导出/恢复往返。
	_check_eq("b.add_fish", true, inv.add_items({"fish_crucian": 1}))
	_check_eq("b.get_count_fish", 1, inv.get_count("fish_crucian"))
	_check_eq("b.snapshot_has_fish", 1, int(inv.item_snapshot().get("fish_crucian", 0)))
	_check_eq("b.has_items_fish", true, inv.has_items({"fish_crucian": 1}))
	_check_eq("b.has_items_more", false, inv.has_items({"fish_crucian": 2}))
	var exported: Dictionary = inv.export_state()
	_check_eq("b.export_version", 1, int(exported.get("version", -1)))
	_check("b.export_has_fish", _json(exported.get("items", {})) == _json({"fish_crucian": 1}),
		_json({"fish_crucian": 1}), _json(exported.get("items", {})))
	var inv2 = _fresh_inv()
	_check_eq("b.restore_roundtrip_ok", true, inv2.restore_state(exported))
	_check("b.restore_roundtrip_snapshot", _json(inv2.item_snapshot()) == _json(inv.item_snapshot()),
		_json(inv.item_snapshot()), _json(inv2.item_snapshot()))
	_check("b.restore_roundtrip_export", _json(inv2.export_state()) == _json(inv.export_state()),
		_json(inv.export_state()), _json(inv2.export_state()))

	# 非法增量：整笔失败且快照逐字节不变。
	var atomic_cases: Array = [
		["unknown_id", {"fish_bogus": 1}],
		["zero", {"fish_crucian": 0}],
		["negative", {"fish_crucian": -1}],
		["float", {"fish_crucian": 1.5}],
		["mixed_valid_invalid", {"fish_crucian": 1, "fish_bogus": 1}],
		["seed_zero", {"seed_wheat": 0}],
	]
	for entry in atomic_cases:
		var case_name := String(entry[0])
		var before := _json(inv.export_state())
		var deltas: Dictionary = entry[1]
		var ok: bool = inv.add_items(deltas)
		var after := _json(inv.export_state())
		_check("b.add_atomic_" + case_name, (not ok) and before == after,
			"false + 快照不变", "ok=%s same=%s" % [str(ok), str(before == after)])
	_check_eq("b.add_empty_noop", true, inv.add_items({}))

	# 扣减 / 消费：鱼与作物同语义。
	_check_eq("b.add_sardine", true, inv.add_items({"fish_sardine": 2}))
	_check_eq("b.get_sardine", 2, inv.get_count("fish_sardine"))
	_check_eq("b.remove_fish_ok", true, inv.remove_item("fish_sardine", 1))
	_check_eq("b.remove_fish_count", 1, inv.get_count("fish_sardine"))
	var before_remove := _json(inv.export_state())
	_check_eq("b.remove_fish_too_much", false, inv.remove_item("fish_sardine", 2))
	_check_eq("b.remove_fish_zero", false, inv.remove_item("fish_sardine", 0))
	_check_eq("b.remove_unknown", false, inv.remove_item("fish_bogus", 1))
	_check("b.remove_failed_unchanged", _json(inv.export_state()) == before_remove,
		"快照不变", before_remove)
	_check_eq("b.consume_fish_ok", true, inv.try_consume_items({"fish_sardine": 1}))
	_check_eq("b.consume_sardine_zero", 0, inv.get_count("fish_sardine"))
	_check_eq("b.consume_fish_too_much", false, inv.try_consume_items({"fish_sardine": 1}))

	# 旧存档兼容：没有鱼条目的 STATE_VERSION=1 数据必须能恢复，鱼读作 0。
	var inv_old = _fresh_inv()
	var old_state := {"version": 1, "items": {"seed_wheat": 3, "wheat": 2}}
	_check_eq("b.old_state_restore", true, inv_old.restore_state(old_state))
	_check("b.old_state_snapshot", _json(inv_old.item_snapshot()) == _json({"seed_wheat": 3, "wheat": 2}),
		_json({"seed_wheat": 3, "wheat": 2}), _json(inv_old.item_snapshot()))
	_check("b.old_state_export_stable", _json(inv_old.export_state()) == _json(old_state),
		_json(old_state), _json(inv_old.export_state()))
	var old_fish_zero: Array = []
	for raw_fish in FISH.FISH_IDS:
		if int(inv_old.get_count(String(raw_fish))) != 0:
			old_fish_zero.append(String(raw_fish))
	_check("b.old_state_fish_zero", old_fish_zero.is_empty(), "6 种鱼均读作 0", str(old_fish_zero))

	# 非法恢复：不部分提交（已有库存保持原样）。
	var before_bad_restore := _json(inv_old.export_state())
	_check_eq("b.restore_unknown_id", false,
		inv_old.restore_state({"version": 1, "items": {"seed_wheat": 1, "fish_bogus": 2}}))
	_check_eq("b.restore_unknown_no_partial", before_bad_restore, _json(inv_old.export_state()))
	_check_eq("b.restore_version2", false,
		inv_old.restore_state({"version": 2, "items": {"fish_crucian": 1}}))
	_check_eq("b.restore_version_string", false,
		inv_old.restore_state({"version": "1", "items": {}}))
	_check_eq("b.restore_float_count", false,
		inv_old.restore_state({"version": 1, "items": {"fish_crucian": 1.5}}))
	_check_eq("b.restore_no_partial_after_all", before_bad_restore, _json(inv_old.export_state()))

	# 合法鱼存档恢复 + 初始种子表不含鱼。
	var inv_fish = _fresh_inv()
	_check_eq("b.restore_fish_state", true, inv_fish.restore_state({"version": 1, "items": {"fish_koi": 5}}))
	_check_eq("b.restore_fish_count", 5, inv_fish.get_count("fish_koi"))
	var seeds: Dictionary = inv_fish.starting_seeds()
	_check_eq("b.starting_seeds_count", 5, seeds.size())
	var seed_has_fish: Array = []
	for key in seeds.keys():
		if FISH.has_fish(String(key)):
			seed_has_fish.append(String(key))
	_check("b.starting_seeds_no_fish", seed_has_fish.is_empty(), "初始种子表不含鱼", str(seed_has_fish))
	# 版本 1.0（整值 float）仍接受（沿用既有 _is_integral 语义）。
	_check_eq("b.restore_version_float_ok", true, inv_old.restore_state({"version": 1.0, "items": {}}))


# =========================================================== C. 排序 ======
func _category_of(item_id: String) -> String:
	if item_id.begins_with("seed_"):
		return "seed"
	if item_id.begins_with("fish_"):
		return "fish"
	for crop_id in CROPS.CROP_IDS:
		if String(crop_id) == item_id:
			return "produce"
	return ""


func _rank_of(category: String) -> int:
	match category:
		"seed":
			return 0
		"produce":
			return 1
		"fish":
			return 2
		_:
			return 3


func _sort_checks() -> void:
	_section("C. 背包分类/排序辅助（seed < produce < fish）")
	var known: Array = INVENTORY.catalog_ids()
	var cat_bad: Array = []
	var rank_bad: Array = []
	var idx_bad: Array = []
	var seed_ids: Array = []
	var produce_ids: Array = []
	var fish_ids: Array = []
	for i in range(known.size()):
		var item_id := String(known[i])
		var exp_cat := _category_of(item_id)
		if INVENTORY.item_category(item_id) != exp_cat:
			cat_bad.append(item_id)
		if INVENTORY.category_rank(item_id) != _rank_of(exp_cat):
			rank_bad.append(item_id)
		if INVENTORY.catalog_index(item_id) != i:
			idx_bad.append(item_id)
		match exp_cat:
			"seed":
				seed_ids.append(item_id)
			"produce":
				produce_ids.append(item_id)
			"fish":
				fish_ids.append(item_id)
	_check("c.item_category_all", cat_bad.is_empty(), "0 处不符", str(cat_bad))
	_check("c.category_rank_all", rank_bad.is_empty(), "0 处不符", str(rank_bad))
	_check("c.catalog_index_all", idx_bad.is_empty(), "0 处不符", str(idx_bad))
	_check_eq("c.item_category_unknown", "", INVENTORY.item_category("fish_bogus"))
	_check_eq("c.category_rank_unknown", 3, INVENTORY.category_rank("fish_bogus"))
	_check_eq("c.catalog_index_unknown", -1, INVENTORY.catalog_index("fish_bogus"))
	_check_eq("c.seed_class_count", 5, seed_ids.size())
	_check_eq("c.produce_class_count", 5, produce_ids.size())
	_check_eq("c.fish_class_count", 6, fish_ids.size())

	var class_ok := true
	for group in [seed_ids, produce_ids, fish_ids]:
		var last := -1
		for raw in group:
			var idx: int = INVENTORY.catalog_index(String(raw))
			if idx <= last:
				class_ok = false
			last = idx
	_check("c.class_index_strictly_increasing", class_ok, "每个大类内下标严格递增", "ok=%s" % str(class_ok))

	var cross_ok := true
	for raw_seed in seed_ids:
		for raw_produce in produce_ids:
			if INVENTORY.category_rank(String(raw_seed)) > INVENTORY.category_rank(String(raw_produce)):
				cross_ok = false
	for raw_produce2 in produce_ids:
		for raw_fish2 in fish_ids:
			if INVENTORY.category_rank(String(raw_produce2)) > INVENTORY.category_rank(String(raw_fish2)):
				cross_ok = false
	_check("c.rank_cross_class_monotonic", cross_ok,
		"所有 seed rank <= 所有 produce rank <= 所有 fish rank", "ok=%s" % str(cross_ok))
	var fish_after_produce := int(INVENTORY.catalog_index(String(fish_ids[0]))) > int(INVENTORY.catalog_index(String(produce_ids[produce_ids.size() - 1])))
	_check("c.fish_catalog_after_produce", fish_after_produce,
		"第一条鱼的下标 > 最后一条产物下标",
		"%d > %d" % [INVENTORY.catalog_index(String(fish_ids[0])), INVENTORY.catalog_index(String(produce_ids[produce_ids.size() - 1]))])


# =========================================================== D. 规则 ======
func _expected_available(def: Dictionary, season_id: String, hour: int, weather_id: String) -> bool:
	var seasons: Array = def.get("seasons", [])
	if not seasons.is_empty() and not seasons.has(season_id):
		return false
	var weather: Array = def.get("weather", [])
	if not weather.is_empty() and not weather.has(weather_id):
		return false
	var hf := int(def.get("hour_from", 0))
	var ht := int(def.get("hour_to", 23))
	if hf <= ht:
		return hour >= hf and hour <= ht
	return hour >= hf or hour <= ht


func _rule_checks() -> void:
	_section("D. 可用规则（兜底全覆盖 / DEFS 一致 / 权重 / 决定论 / 抽样覆盖）")
	var fallback: String = FISH.fallback_id()
	var fb_miss: Array = []
	for season_id in SEASONS:
		for hour in range(24):
			for weather_id in WEATHERS:
				if not FISH.is_available(fallback, String(season_id), hour, String(weather_id)):
					fb_miss.append("%s/%d/%s" % [season_id, hour, weather_id])
	_check("d.fallback_all_conditions", fb_miss.is_empty(),
		"4 季 x 24 小时 x 4 天气 全部可用", "%d 处不可用 %s" % [fb_miss.size(), str(fb_miss.slice(0, 5))])
	var fb_weight_bad: Array = []
	for season_id in SEASONS:
		for hour in range(24):
			for weather_id in WEATHERS:
				if FISH.weight_for(fallback, String(season_id), hour, String(weather_id)) <= 0.0:
					fb_weight_bad.append("%s/%d/%s" % [season_id, hour, weather_id])
	_check("d.fallback_weight_positive", fb_weight_bad.is_empty(),
		"所有组合 weight_for > 0", "%d 处 <= 0" % fb_weight_bad.size())

	# is_available 与 DEFS 逐条一致（独立重算），且 weight_for > 0 当且仅当可用。
	var avail_bad_total := 0
	var weight_bad_total := 0
	var per_fish_lines: Array = []
	for raw in FISH.all_ids():
		var fid := String(raw)
		var def: Dictionary = FISH.get_def(fid)
		var fish_mismatch := 0
		var fish_weight_mismatch := 0
		for season_id in SEASONS:
			for hour in range(24):
				for weather_id in WEATHERS:
					var expected: bool = _expected_available(def, String(season_id), hour, String(weather_id))
					var actual: bool = FISH.is_available(fid, String(season_id), hour, String(weather_id))
					if expected != actual:
						avail_bad_total += 1
						fish_mismatch += 1
					var w: float = FISH.weight_for(fid, String(season_id), hour, String(weather_id))
					if (w > 0.0) != expected:
						weight_bad_total += 1
						fish_weight_mismatch += 1
		per_fish_lines.append("%s:%d/%d" % [fid, fish_mismatch, fish_weight_mismatch])
	_check("d.is_available_matches_defs", avail_bad_total == 0,
		"0 处不一致", "%d 处不一致 (%s)" % [avail_bad_total, str(per_fish_lines)])
	_check("d.weight_positive_iff_available", weight_bad_total == 0,
		"0 处不一致", "%d 处不一致 (%s)" % [weight_bad_total, str(per_fish_lines)])
	_check_eq("d.weight_unknown_zero", 0.0, FISH.weight_for("fish_bogus", "spring", 7, "clear"))
	_check_eq("d.available_unknown_false", false, FISH.is_available("fish_bogus", "spring", 7, "clear"))

	# weather_key 投影。
	_check("d.weather_key_clear", "clear" == FISH.weather_key("clear", "none", 0.06),
		"clear", FISH.weather_key("clear", "none", 0.06))
	_check("d.weather_key_cloudy", "cloudy" == FISH.weather_key("overcast", "none", 0.82),
		"cloudy", FISH.weather_key("overcast", "none", 0.82))
	_check("d.weather_key_rain", "rain" == FISH.weather_key("mid_rain", "rain", 0.84),
		"rain", FISH.weather_key("mid_rain", "rain", 0.84))
	_check("d.weather_key_snow", "snow" == FISH.weather_key("mid_snow", "snow", 0.9),
		"snow", FISH.weather_key("mid_snow", "snow", 0.9))
	_check("d.weather_key_threshold_high", "cloudy" == FISH.weather_key("x", "none", 0.45),
		"cloudy", FISH.weather_key("x", "none", 0.45))
	_check("d.weather_key_threshold_low", "clear" == FISH.weather_key("x", "none", 0.4499),
		"clear", FISH.weather_key("x", "none", 0.4499))
	_check("d.weather_key_coarse_type_fallback", "rain" == FISH.weather_key("rain", "none", 0.1),
		"rain", FISH.weather_key("rain", "none", 0.1))

	# 注入 rng 的决定论：同 seed 两次得到完全相同的 id 序列。
	var conditions: Array = [
		["spring", 7, "clear"],
		["summer", 10, "cloudy"],
		["autumn", 6, "clear"],
		["autumn", 12, "cloudy"],
		["summer", 18, "clear"],
		["winter", 3, "rain"],
	]
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 12345
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 12345
	var seq_a: Array = []
	var seq_b: Array = []
	var legality_bad: Array = []
	var availability_bad: Array = []
	for i in range(600):
		var cond: Array = conditions[i % conditions.size()]
		var season_id := String(cond[0])
		var hour := int(cond[1])
		var weather_id := String(cond[2])
		var id_a: String = FISH.pick(season_id, hour, weather_id, rng_a)
		var id_b: String = FISH.pick(season_id, hour, weather_id, rng_b)
		seq_a.append(id_a)
		seq_b.append(id_b)
		if not FISH.has_fish(id_a):
			legality_bad.append(id_a)
		if not FISH.is_available(id_a, season_id, hour, weather_id):
			availability_bad.append("%s@%s/%d/%s" % [id_a, season_id, hour, weather_id])
	_check("d.pick_deterministic_same_seed", _json(seq_a) == _json(seq_b),
		"同 seed 两次序列完全一致", "len=%d eq=%s" % [seq_a.size(), str(_json(seq_a) == _json(seq_b))])
	_check("d.pick_always_legal", legality_bad.is_empty(), "600 次全部返回合法 id", str(legality_bad.slice(0, 5)))
	_check("d.pick_always_available", availability_bad.is_empty(), "600 次全部来自当前条件可钓鱼", str(availability_bad.slice(0, 5)))
	_check_eq("d.pick_null_rng_fallback", fallback, FISH.pick("winter", 3, "rain", null))

	# 仅兜底鱼可用的条件：100 次必须全部是兜底鱼。
	var rng_fb := RandomNumberGenerator.new()
	rng_fb.seed = 4242
	var fb_pick_bad: Array = []
	for i in range(100):
		var got: String = FISH.pick("winter", 3, "rain", rng_fb)
		if got != fallback:
			fb_pick_bad.append(got)
	_check("d.pick_fallback_only_condition", fb_pick_bad.is_empty(),
		"冬季 3 点雨天 100 次全是 " + fallback, str(fb_pick_bad.slice(0, 5)))

	# 500 次抽样（每条件 500 次，条件并集覆盖全部 6 种）：所有鱼都必须出现。
	var coverage_conditions: Array = [
		["spring", 7, "clear"],     # 鲫鱼 / 沙丁鱼 / 彩鲤
		["summer", 10, "cloudy"],   # 鲫鱼 / 沙丁鱼（河豚 9-17 cloudy 也命中）
		["autumn", 6, "clear"],     # 鲫鱼 / 沙丁鱼 / 鲑鱼
		["autumn", 12, "cloudy"],   # 鲫鱼 / 沙丁鱼 / 河豚
		["summer", 18, "clear"],    # 鲫鱼 / 沙丁鱼 / 鲈鱼
		["winter", 3, "rain"],      # 仅鲫鱼
	]
	var rng_cov := RandomNumberGenerator.new()
	rng_cov.seed = 777
	var seen: Dictionary = {}
	var cov_illegal := 0
	var cov_unavailable := 0
	for cond2 in coverage_conditions:
		var season2 := String(cond2[0])
		var hour2 := int(cond2[1])
		var weather2 := String(cond2[2])
		for i in range(500):
			var got2: String = FISH.pick(season2, hour2, weather2, rng_cov)
			seen[got2] = true
			if not FISH.has_fish(got2):
				cov_illegal += 1
			elif not FISH.is_available(got2, season2, hour2, weather2):
				cov_unavailable += 1
	var missing: Array = []
	for raw in FISH.all_ids():
		if not seen.has(String(raw)):
			missing.append(String(raw))
	_check("d.pick_500_covers_all_species", missing.is_empty(),
		"6 种全部出现", "missing=%s seen=%s" % [str(missing), str(seen.keys())])
	_check_eq("d.pick_coverage_illegal", 0, cov_illegal)
	_check_eq("d.pick_coverage_unavailable", 0, cov_unavailable)
	_check("d.pick_500_condition_count", coverage_conditions.size() == 6,
		"6 个条件各 500 次", str(coverage_conditions.size()))
