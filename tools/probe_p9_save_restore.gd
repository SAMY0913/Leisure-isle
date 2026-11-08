extends SceneTree
## P9 / P7-FINALIZE —— 世界存档（IsleSave：库存 + 九格农田）探针（headless，完全隔离）。
##
## 纪律：绝不读写玩家 user:// 存档；所有存档文件都写在本探针自建的临时绝对目录
## （<out>/_tmp_save_<usec>/，即证据目录内，D: 盘绝对路径），结束后清理。
## 注：本机 Godot 进程对 C:/Users/.../AppData/Local/Temp 无写权限（FileAccess 失败），
## 故不使用 OS.get_temp_dir()；证据目录是可写的绝对路径，不涉及玩家存档。
## 覆盖：
##   A. 保存 -> 新库存/农田实例读档：九格、收获次数、种子/产物库存一致；
##   B. 离线生长：saved_unix 往前 120s -> 读档后 now 增加 120、成熟判定随之前进；
##   C. 系统时钟回拨（now < saved_unix）不产生负生长/不倒退阶段；
##   D. 损坏/旧版本/缺段/非法库存/非法农田数据整份拒绝，且目标状态不变；
##   E. 主路径不可写时的 fallback 路径：不崩溃、返回明确结果（成功则落在 save_fallback.cfg）；
##   F. 保存后立即读回原子一致（offline=0，时间戳不漂移）。
##
## 运行：ENG --headless --path GAME --script res://tools/probe_p9_save_restore.gd -- --out=DIR

const SAVE := preload("res://scripts/isle_save.gd")
const INV := preload("res://scripts/isle_inventory.gd")
const FARM := preload("res://scripts/isle_farm.gd")
const CROPS := preload("res://scripts/isle_crops.gd")

const DEFAULT_OUT := "D:/休闲小岛幻境/开发产物/P9/P7-finalize/evidence/save"
const SAVED_UNIX := 1_800_000_000.0
const OFFLINE_120 := 120.0
const SLOT_COUNT := 9

var out_dir := DEFAULT_OUT
var _pass := 0
var _fail := 0
var _lines: Array = []
var _fail_names: Array = []
var _tmp_dir := ""
var _tmp_seq := 0


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
	print("[SAVEP] out=%s headless=%s godot=%s" % [out_dir,
		str(DisplayServer.get_name() == "headless"),
		String(Engine.get_version_info().get("string", ""))])
	_tmp_dir = out_dir.path_join("_tmp_save_%d" % Time.get_ticks_usec())
	var mk := DirAccess.make_dir_recursive_absolute(_tmp_dir)
	_check("env.tmp_dir_created", mk == OK and DirAccess.dir_exists_absolute(_tmp_dir),
		"临时目录可创建（不写玩家 user://）", _tmp_dir)
	var fallback_before := _read_fallback_backup()
	_test_roundtrip()
	_test_offline_growth()
	_test_clock_rollback()
	_test_reject_invalid()
	_test_immediate_consistency()
	_test_fallback()
	_restore_fallback(fallback_before)
	_cleanup_tmp()
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


func _next_path(tag: String) -> String:
	_tmp_seq += 1
	return _tmp_dir.path_join("%02d_%s.cfg" % [_tmp_seq, tag])


## 构造一份有"已收获/再生中/生长中/空"四种状态的农田 + 非空库存。
## 返回 {inv, farm, saved_clock}；saved_clock 为存档时刻的成长时钟秒。
func _prepare_state() -> Dictionary:
	var inv: Object = INV.new()
	inv.call("grant_starting_seeds")
	var farm: Object = FARM.new(inv)
	farm.call("advance_to", 5000.0)
	# 九格中播 5 格（spring 季节允许的四种 + 用 watermelon 走 summer 校验）
	var plant_ok := true
	plant_ok = plant_ok and bool((farm.call("plant", 0, "wheat", "spring") as Dictionary).get("ok", false))
	plant_ok = plant_ok and bool((farm.call("plant", 1, "corn", "spring") as Dictionary).get("ok", false))
	plant_ok = plant_ok and bool((farm.call("plant", 2, "tomato", "spring") as Dictionary).get("ok", false))
	plant_ok = plant_ok and bool((farm.call("plant", 3, "watermelon", "summer") as Dictionary).get("ok", false))
	plant_ok = plant_ok and bool((farm.call("plant", 4, "kale", "spring") as Dictionary).get("ok", false))
	# wheat 首收（一次性清格，返种 1）——覆盖"空位 + 已返种"状态
	farm.call("advance_to", 5000.0 + CROPS.first_maturity_seconds("wheat"))
	farm.call("harvest", 0)
	# corn 首收 + 第二收（harvest_count=2 < 3，仍保留植株且处于再生周期）
	var t_corn := float(farm.now())
	farm.call("advance_to", t_corn + CROPS.regrow_seconds("corn"))
	farm.call("harvest", 1)
	# tomato 首收（harvest_count=1）
	farm.call("advance_to", float(farm.now()) + CROPS.regrow_seconds("tomato"))
	farm.call("harvest", 2)
	# 让 corn 的下一轮成熟恰好落在 +120s：先前进到"距离成熟还有 120s"的时刻再存档
	var corn_next := float((farm.call("get_slot", 1) as Dictionary).get("next_ready_at", 0.0))
	var target_now := corn_next - OFFLINE_120
	if float(farm.now()) < target_now:
		farm.call("advance_to", target_now)
	return {"inv": inv, "farm": farm, "saved_clock": float(farm.now()), "plant_ok": plant_ok}


func _slot_summary(farm: Object) -> Array:
	var out: Array = []
	for i in range(SLOT_COUNT):
		var s: Dictionary = farm.call("get_slot", i)
		out.append({
			"crop_id": String(s.get("crop_id", "")),
			"harvest_count": int(s.get("harvest_count", 0)),
			"seed_returned": bool(s.get("seed_returned", false)),
		})
	return out


func _ts_shifted_ok(src: Object, dst: Object, shift: float) -> Dictionary:
	var bad: Array = []
	for i in range(SLOT_COUNT):
		var a: Dictionary = src.call("get_slot", i)
		var b: Dictionary = dst.call("get_slot", i)
		for key in ["planted_at", "cycle_started_at", "next_ready_at"]:
			var av := float(a.get(key, 0.0))
			var bv := float(b.get(key, 0.0))
			if String(a.get("crop_id", "")).is_empty() and String(b.get("crop_id", "")).is_empty():
				continue
			if absf((bv - av) - shift) > 0.01:
				bad.append("slot%d.%s %.3f -> %.3f (shift want %.1f)" % [i, key, av, bv, shift])
	return {"ok": bad.is_empty(), "bad": bad}


# ============================================================ A 保存 -> 读档 =====
func _test_roundtrip() -> void:
	_section("A. 保存 -> 新实例读档：九格/收获次数/库存一致 + 离线补涨")
	var st := _prepare_state()
	_check("A.setup_plant_ok", bool(st.get("plant_ok", false)), "9 格中 5 格播种成功", "ok")
	var inv: Object = st["inv"]
	var farm: Object = st["farm"]
	var saved_clock := float(st["saved_clock"])
	var path := _next_path("roundtrip")
	var save_res: Dictionary = SAVE.save_state(inv, farm, SAVED_UNIX, path)
	_check("A.save_ok", bool(save_res.get("ok", false)), "ok=true path=临时绝对路径", str(save_res))
	_check("A.save_path_isolated", String(save_res.get("path", "")) == path,
		"未写入玩家 user://（落在临时绝对路径）", String(save_res.get("path", "")))
	_check("A.save_clock", absf(float(save_res.get("farm_clock", -1.0)) - saved_clock) < 0.01,
		"%.1f" % saved_clock, "%.1f" % float(save_res.get("farm_clock", -1.0)))
	# 新实例读档：离线 120s
	var inv2: Object = INV.new()
	var farm2: Object = FARM.new(inv2)
	var load_res: Dictionary = SAVE.load_into(inv2, farm2, SAVED_UNIX + OFFLINE_120, path)
	_check("A.load_ok", bool(load_res.get("ok", false)), "ok=true", str(load_res))
	_check("A.load_offline", absf(float(load_res.get("offline_seconds", -1.0)) - OFFLINE_120) < 0.01,
		"%.1f" % OFFLINE_120, "%.1f" % float(load_res.get("offline_seconds", -1.0)))
	_check_eq("A.inventory_restored", inv.call("item_snapshot"), inv2.call("item_snapshot"))
	_check_eq("A.slots_restored", _slot_summary(farm), _slot_summary(farm2))
	_check("A.clock_mode_real", String(farm2.call("clock_mode_name")) == "real",
		"real（正式游戏按现实时间生长）", String(farm2.call("clock_mode_name")))
	_check("A.clock_advanced_120", absf(float(farm2.call("now")) - (saved_clock + OFFLINE_120)) < 0.01,
		"%.1f" % (saved_clock + OFFLINE_120), "%.1f" % float(farm2.call("now")))
	# 时间戳不漂移：读档 delta=0，再 advance_realtime 只推进 now，不移动格内时间戳
	var ts := _ts_shifted_ok(farm, farm2, 0.0)
	_check("A.timestamps_stable", bool(ts.get("ok", false)), "格内时间戳与存档一致", str(ts.get("bad", [])))
	# 再保存一次：结构仍合法（证明读档后的状态可再次持久化）
	var path2 := _next_path("roundtrip_again")
	var save2: Dictionary = SAVE.save_state(inv2, farm2, SAVED_UNIX + OFFLINE_120, path2)
	_check("A.resave_ok", bool(save2.get("ok", false)), "ok=true", str(save2))


# ============================================================ B 离线生长 ======
func _test_offline_growth() -> void:
	_section("B. 离线生长：saved_unix 往前 120s -> now +120、成熟判定随之前进")
	var st := _prepare_state()
	var inv: Object = st["inv"]
	var farm: Object = st["farm"]
	var saved_clock := float(st["saved_clock"])
	var path := _next_path("offline")
	var save_res: Dictionary = SAVE.save_state(inv, farm, SAVED_UNIX, path)
	_check("B.save_ok", bool(save_res.get("ok", false)), "ok=true", str(save_res))
	# 存档时 corn 正处在"还差 120s 成熟"的生长中状态
	var corn_before: Dictionary = farm.call("get_slot", 1)
	var remain_before := float(farm.call("seconds_to_mature", 1))
	_check("B.before_growing", String(corn_before.get("crop_id", "")) == "corn" and remain_before > 0.0,
		"corn 存档时未成熟（remain>0）", "remain=%.3f" % remain_before)
	_check("B.before_remain_120", absf(remain_before - OFFLINE_120) < 0.01,
		"remain=%.1f" % OFFLINE_120, "remain=%.3f" % remain_before)
	var inv2: Object = INV.new()
	var farm2: Object = FARM.new(inv2)
	var load_res: Dictionary = SAVE.load_into(inv2, farm2, SAVED_UNIX + OFFLINE_120, path)
	_check("B.load_ok", bool(load_res.get("ok", false)), "ok=true", str(load_res))
	_check("B.now_advanced", absf(float(farm2.call("now")) - (saved_clock + OFFLINE_120)) < 0.01,
		"%.1f" % (saved_clock + OFFLINE_120), "%.1f" % float(farm2.call("now")))
	_check("B.mature_advanced", bool(farm2.call("is_mature", 1)),
		"离线 120s 后 corn 恰好成熟（mature=true）", str(farm2.call("is_mature", 1)))
	_check_eq("B.seconds_to_mature_zero", 0.0, float(farm2.call("seconds_to_mature", 1)))
	# 所有格子：读档后的成熟判定必须等于"存档时刻 + 离线秒数"的判定（逐格一致）
	var mismatch: Array = []
	for i in range(SLOT_COUNT):
		var s: Dictionary = farm.call("get_slot", i)
		var expect_mature := false
		if not String(s.get("crop_id", "")).is_empty():
			expect_mature = (saved_clock + OFFLINE_120) + 0.000001 >= float(s.get("next_ready_at", 0.0))
		if bool(farm2.call("is_mature", i)) != expect_mature:
			mismatch.append("slot%d expect=%s actual=%s" % [i, str(expect_mature), str(farm2.call("is_mature", i))])
	_check("B.maturity_consistent_all_slots", mismatch.is_empty(),
		"九格成熟判定 = 存档时刻+离线秒数", str(mismatch))
	# 另一个生长中（非成熟）格子仍在生长（不能全部瞬熟）
	var still_growing := -1
	for i in range(SLOT_COUNT):
		if String((farm.call("get_slot", i) as Dictionary).get("crop_id", "")) != "" and not bool(farm2.call("is_mature", i)):
			still_growing = i
			break
	_check("B.some_slot_still_growing", still_growing >= 0, "至少一格仍在生长（不是无脑瞬熟）",
		"slot=%d" % still_growing)
	# B2 离线时长 > IsleFarm.MAX_REAL_STEP_SECONDS(300s)：isle_save.gd:205 注释明确写
	# "离线生长不经过 MAX_REAL_STEP 的单帧夹取"，因此 1 小时离线必须补涨 3600s。
	# 若实际只补 300s，说明离线生长被单帧夹取截断（真实玩家离线数小时只长 5 分钟）=> 生产 bug。
	var st2 := _prepare_state()
	var path_far := _next_path("offline_far")
	var save_far: Dictionary = SAVE.save_state(st2["inv"], st2["farm"], SAVED_UNIX, path_far)
	_check("B2.save_ok", bool(save_far.get("ok", false)), "ok=true", str(save_far))
	var saved_clock_far := float(st2["saved_clock"])
	var offline_far := 3600.0
	var inv_far: Object = INV.new()
	var farm_far: Object = FARM.new(inv_far)
	var load_far: Dictionary = SAVE.load_into(inv_far, farm_far, SAVED_UNIX + offline_far, path_far)
	_check("B2.load_ok", bool(load_far.get("ok", false)), "ok=true", str(load_far))
	_check("B2.offline_seconds_reported", absf(float(load_far.get("offline_seconds", -1.0)) - offline_far) < 0.01,
		"%.1f" % offline_far, "%.1f" % float(load_far.get("offline_seconds", -1.0)))
	var expected_clock_far := saved_clock_far + offline_far
	_check("B2.offline_growth_full", absf(float(farm_far.call("now")) - expected_clock_far) < 0.01,
		"farm.now = saved_clock + %.0f = %.1f（离线完整补涨）" % [offline_far, expected_clock_far],
		"actual=%.1f (delta=+%.1f；MAX_REAL_STEP_SECONDS=%.0f)" % [
			float(farm_far.call("now")), float(farm_far.call("now")) - saved_clock_far,
			float(FARM.MAX_REAL_STEP_SECONDS)])


# ============================================================ C 时钟回拨 ======
func _test_clock_rollback() -> void:
	_section("C. 系统时钟回拨：now < saved_unix 时不产生负生长/不倒退阶段")
	var st := _prepare_state()
	var inv: Object = st["inv"]
	var farm: Object = st["farm"]
	var path := _next_path("rollback")
	var save_res: Dictionary = SAVE.save_state(inv, farm, SAVED_UNIX, path)
	_check("C.save_ok", bool(save_res.get("ok", false)), "ok=true", str(save_res))
	var stages_before: Array = []
	for i in range(SLOT_COUNT):
		stages_before.append(String(farm.call("stage_id", i)))
	var inv2: Object = INV.new()
	var farm2: Object = FARM.new(inv2)
	var load_res: Dictionary = SAVE.load_into(inv2, farm2, SAVED_UNIX - 100.0, path)
	_check("C.load_ok", bool(load_res.get("ok", false)), "ok=true", str(load_res))
	_check_eq("C.offline_zero", 0.0, float(load_res.get("offline_seconds", -1.0)))
	_check("C.now_not_negative_shift", absf(float(farm2.call("now")) - float(st["saved_clock"])) < 0.01,
		"%.1f（不倒退）" % float(st["saved_clock"]), "%.1f" % float(farm2.call("now")))
	var stages_after: Array = []
	for i in range(SLOT_COUNT):
		stages_after.append(String(farm2.call("stage_id", i)))
	_check_eq("C.stages_not_regressed", stages_before, stages_after)
	_check("C.offline_seconds_pure",
		SAVE.offline_seconds(100.0, 50.0) == 0.0
			and absf(SAVE.offline_seconds(100.0, 100.0 + 90_000.0) - 86400.0) < 0.001
			and SAVE.offline_seconds(NAN, 100.0) == 0.0
			and SAVE.offline_seconds(100.0, INF) == 0.0
			and absf(SAVE.offline_seconds(100.0, 130.0) - 30.0) < 0.001,
		"回拨=0 / 上限 86400 / NaN&Inf=0 / 正常差值", "ok")


# ============================================================ D 整份拒绝 ======
func _test_reject_invalid() -> void:
	_section("D. 损坏/旧版本/缺段/非法数据：整份拒绝且目标状态不变")
	var st := _prepare_state()
	var inv: Object = st["inv"]
	var farm: Object = st["farm"]
	var good_path := _next_path("good")
	var save_res: Dictionary = SAVE.save_state(inv, farm, SAVED_UNIX, good_path)
	_check("D.baseline_save_ok", bool(save_res.get("ok", false)), "ok=true", str(save_res))

	# D1 损坏文件（非 ConfigFile）
	var corrupt := _next_path("corrupt")
	var f := FileAccess.open(corrupt, FileAccess.WRITE)
	if f != null:
		f.store_string("[meta\nbroken line without a valid section header =")
		f.close()
	# D2 旧版本
	var old_ver := _next_path("old_version")
	var c2 := ConfigFile.new()
	c2.set_value("meta", "version", 0)
	c2.set_value("meta", "saved_unix", SAVED_UNIX)
	c2.set_value("inventory", "state", inv.call("export_state"))
	c2.set_value("farm", "state", farm.call("export_state"))
	c2.save(old_ver)
	# D3 缺段（只有 meta + inventory，没有 farm）
	var missing := _next_path("missing_section")
	var c3 := ConfigFile.new()
	c3.set_value("meta", "version", 1)
	c3.set_value("meta", "saved_unix", SAVED_UNIX)
	c3.set_value("inventory", "state", inv.call("export_state"))
	c3.save(missing)
	# D4 非法库存（未知物品 ID）
	var bad_inv := _next_path("bad_inventory")
	var cfg_bad_inv := ConfigFile.new()
	cfg_bad_inv.set_value("meta", "version", 1)
	cfg_bad_inv.set_value("meta", "saved_unix", SAVED_UNIX)
	cfg_bad_inv.set_value("inventory", "state", {"version": 1, "items": {"banana": 3}})
	cfg_bad_inv.set_value("farm", "state", farm.call("export_state"))
	cfg_bad_inv.save(bad_inv)
	# D5 非法农田（version=2）
	var bad_farm := _next_path("bad_farm")
	var cfg_bad_farm := ConfigFile.new()
	cfg_bad_farm.set_value("meta", "version", 1)
	cfg_bad_farm.set_value("meta", "saved_unix", SAVED_UNIX)
	cfg_bad_farm.set_value("inventory", "state", inv.call("export_state"))
	var fs: Dictionary = (farm.call("export_state") as Dictionary).duplicate(true)
	fs["version"] = 2
	cfg_bad_farm.set_value("farm", "state", fs)
	cfg_bad_farm.save(bad_farm)
	# D6 非法 saved_unix（0）
	var bad_stamp := _next_path("bad_stamp")
	var cfg_stamp := ConfigFile.new()
	cfg_stamp.set_value("meta", "version", 1)
	cfg_stamp.set_value("meta", "saved_unix", 0)
	cfg_stamp.set_value("inventory", "state", inv.call("export_state"))
	cfg_stamp.set_value("farm", "state", farm.call("export_state"))
	cfg_stamp.save(bad_stamp)

	var cases := [
		{"name": "D.corrupt_load_failed", "path": corrupt, "reason": "load_failed"},
		{"name": "D.old_version_rejected", "path": old_ver, "reason": "version_mismatch"},
		{"name": "D.missing_section_rejected", "path": missing, "reason": "missing_sections"},
		{"name": "D.bad_inventory_rejected", "path": bad_inv, "reason": "bad_inventory"},
		{"name": "D.bad_farm_rejected", "path": bad_farm, "reason": "bad_farm"},
		{"name": "D.bad_saved_unix_rejected", "path": bad_stamp, "reason": "bad_saved_unix"},
	]
	for case in cases:
		var c: Dictionary = case
		var inv_t: Object = INV.new()
		inv_t.call("grant_starting_seeds")
		var farm_t: Object = FARM.new(inv_t)
		farm_t.call("advance_to", 1000.0)
		farm_t.call("plant", 6, "kale", "spring")
		var inv_before: Dictionary = inv_t.call("export_state")
		var farm_before: Dictionary = farm_t.call("export_state") as Dictionary
		var res: Dictionary = SAVE.load_into(inv_t, farm_t, SAVED_UNIX + 10.0, String(c["path"]))
		_check(String(c["name"]), not bool(res.get("ok", false))
			and String(res.get("reason", "")) == String(c["reason"]),
			"ok=false reason=%s" % String(c["reason"]), "ok=%s reason=%s" % [str(res.get("ok")), String(res.get("reason", ""))])
		_check(String(c["name"]) + ".target_unchanged",
			inv_t.call("export_state") == inv_before and farm_t.call("export_state") == farm_before,
			"目标库存/农田状态不变", "changed")
	# 不存在的文件
	var inv_x: Object = INV.new()
	var farm_x: Object = FARM.new(inv_x)
	var nf: Dictionary = SAVE.load_into(inv_x, farm_x, SAVED_UNIX, _tmp_dir.path_join("no_such_save.cfg"))
	_check("D.no_save_rejected", not bool(nf.get("ok", false)) and String(nf.get("reason", "")) == "no_save",
		"ok=false reason=no_save", str(nf))


# ============================================================ E 保存后读回 =====
func _test_immediate_consistency() -> void:
	_section("E. 保存后立即读回：offline=0 时原子一致、时间戳不漂移")
	var st := _prepare_state()
	var inv: Object = st["inv"]
	var farm: Object = st["farm"]
	var saved_clock := float(st["saved_clock"])
	var path := _next_path("atomic")
	var save_res: Dictionary = SAVE.save_state(inv, farm, SAVED_UNIX, path)
	_check("E.save_ok", bool(save_res.get("ok", false)), "ok=true", str(save_res))
	var inv2: Object = INV.new()
	var farm2: Object = FARM.new(inv2)
	var load_res: Dictionary = SAVE.load_into(inv2, farm2, SAVED_UNIX, path)
	_check("E.load_ok", bool(load_res.get("ok", false)), "ok=true", str(load_res))
	_check_eq("E.inventory_equal", inv.call("item_snapshot"), inv2.call("item_snapshot"))
	_check_eq("E.slots_equal", _slot_summary(farm), _slot_summary(farm2))
	_check("E.now_equal", absf(float(farm2.call("now")) - saved_clock) < 0.01,
		"%.1f" % saved_clock, "%.1f" % float(farm2.call("now")))
	var ts := _ts_shifted_ok(farm, farm2, 0.0)
	_check("E.timestamps_equal", bool(ts.get("ok", false)), "格内时间戳逐字段一致", str(ts.get("bad", [])))
	# 读档后再次 export，与首次存档的 farm state 逐字段一致（除 clock_mode）
	var ex1: Dictionary = farm.call("export_state") as Dictionary
	var ex2: Dictionary = farm2.call("export_state") as Dictionary
	var slots_equal: bool = (ex1.get("slots", []) as Array) == (ex2.get("slots", []) as Array)
	_check("E.export_slots_equal", slots_equal, "slot 完整导出（含时间戳）一致", "slots_equal=%s" % str(slots_equal))


# ============================================================ F fallback ======
func _read_fallback_backup() -> Dictionary:
	var fb := SAVE.fallback_path()
	if fb == "" or not FileAccess.file_exists(fb):
		return {"path": fb, "exists": false, "bytes": PackedByteArray()}
	return {"path": fb, "exists": true, "bytes": FileAccess.get_file_as_bytes(fb)}


func _restore_fallback(backup: Dictionary) -> void:
	var fb := String(backup.get("path", ""))
	if fb == "":
		return
	var existed := bool(backup.get("exists", false))
	if existed:
		var bytes: PackedByteArray = backup.get("bytes", PackedByteArray())
		var f := FileAccess.open(fb, FileAccess.WRITE)
		if f != null:
			f.store_buffer(bytes)
			f.close()
	elif FileAccess.file_exists(fb):
		# 探针自己产生的文件；恢复测试前状态（原本不存在则删除自己创建的）。
		DirAccess.remove_absolute(fb)


func _test_fallback() -> void:
	_section("F. 主路径不可写 -> fallback 路径：不崩溃、结果明确（不写玩家 user://）")
	var fb := SAVE.fallback_path()
	_check("F.fallback_path_nonempty", fb != "" and String(fb).ends_with("save_fallback.cfg"),
		".../save_fallback.cfg", fb)
	_check("F.fallback_not_user", not String(fb).begins_with("user://"),
		"fallback 是项目/可执行文件旁的真实路径（不是 user://）", fb)
	var st := _prepare_state()
	var inv: Object = st["inv"]
	var farm: Object = st["farm"]
	# 主路径：临时目录下不存在的子目录 -> ConfigFile.save 必然失败，触发 fallback 分支。
	var bad_primary := _tmp_dir.path_join("no_such_dir_xyz").path_join("save.cfg")
	_check("F.primary_unwritable", not DirAccess.dir_exists_absolute(_tmp_dir.path_join("no_such_dir_xyz")),
		"主路径父目录不存在（写入必失败）", bad_primary)
	var res: Dictionary = SAVE.save_state(inv, farm, SAVED_UNIX, bad_primary)
	var has_ok_key := res.has("ok")
	_check("F.no_crash", has_ok_key, "返回结构化 Dictionary（不崩溃）", str(res))
	var ok := bool(res.get("ok", false))
	if ok:
		var used := String(res.get("path", ""))
		_check("F.used_fallback", used == fb and FileAccess.file_exists(used),
			"ok=true 且落到 fallback 路径", used)
		if used != "" and FileAccess.file_exists(used):
			var cfg := ConfigFile.new()
			var lerr := cfg.load(used)
			_check("F.fallback_readable", lerr == OK
				and (cfg.get_value("inventory", "state", null) is Dictionary)
				and (cfg.get_value("farm", "state", null) is Dictionary),
				"fallback 文件可读且含两段状态", "err=%d" % lerr)
			var inv2: Object = INV.new()
			var farm2: Object = FARM.new(inv2)
			var lres: Dictionary = SAVE.load_into(inv2, farm2, SAVED_UNIX, used)
			_check("F.fallback_load_ok", bool(lres.get("ok", false)),
				"用显式 fallback 路径可读回", str(lres))
			_check_eq("F.fallback_inventory_equal", inv.call("item_snapshot"), inv2.call("item_snapshot"))
	else:
		_check("F.clear_error", String(res.get("reason", "")).begins_with("save_failed:"),
			"ok=false 且 reason=save_failed:<err>（明确错误）", String(res.get("reason", "")))
	# 明确参数错误（不涉及写盘）
	var r_no_inv := SAVE.save_state(null, farm, SAVED_UNIX, _next_path("no_inv"))
	_check("F.no_inventory_reason",
		not bool(r_no_inv.get("ok", true)) and String(r_no_inv.get("reason", "")) == "no_inventory",
		"ok=false reason=no_inventory", str(r_no_inv))
	var r_no_farm := SAVE.save_state(inv, null, SAVED_UNIX, _next_path("no_farm"))
	_check("F.no_farm_reason",
		not bool(r_no_farm.get("ok", true)) and String(r_no_farm.get("reason", "")) == "no_farm",
		"ok=false reason=no_farm", str(r_no_farm))
	var r_no_path := SAVE.save_state(inv, farm, SAVED_UNIX, _tmp_dir.path_join("x").path_join("y").path_join("z.cfg"))
	_check("F.bad_path_structured", r_no_path.has("ok"),
		"不可写路径返回结构化结果（ok 为 true 时已回退）", str(r_no_path))


# ============================================================ 清理/报告 ======
func _cleanup_tmp() -> void:
	if _tmp_dir == "":
		return
	# 只删除本探针自己在临时目录中创建的文件（不触碰任何历史文件/玩家存档）。
	var files := DirAccess.get_files_at(_tmp_dir)
	for f in files:
		DirAccess.remove_absolute(_tmp_dir.path_join(String(f)))
	var dirs := DirAccess.get_directories_at(_tmp_dir)
	for d in dirs:
		var sub := _tmp_dir.path_join(String(d))
		for sf in DirAccess.get_files_at(sub):
			DirAccess.remove_absolute(sub.path_join(String(sf)))
		DirAccess.remove_absolute(sub)
	DirAccess.remove_absolute(_tmp_dir)
	print("[SAVEP] tmp cleaned: %s" % _tmp_dir)


func _write_report() -> void:
	var log_path := out_dir + "/probe_p9_save_restore.log"
	var fa := FileAccess.open(log_path, FileAccess.WRITE)
	if fa != null:
		fa.store_string("\n".join(_lines) + "\n")
		fa.close()
		print("[SAVEP] log=", log_path)
	var data := {
		"checks": _pass + _fail,
		"fail": _fail,
		"fail_names": _fail_names,
		"headless": DisplayServer.get_name() == "headless",
		"tmp_dir": _tmp_dir,
		"user_save_touched": false,
	}
	var jf := FileAccess.open(out_dir + "/probe_p9_save_restore.json", FileAccess.WRITE)
	if jf != null:
		jf.store_string(JSON.stringify(data, "  "))
		jf.close()
