extends SceneTree
## P7-FINALIZE —— 真实时间农作 + 最小世界存档的跨进程 e2e（正式 isle.tscn / 正式 main 代码路径）。
## 运行（隔离 APPDATA 的独立 user://，两次独立进程）：
##   ENG --path GAME --script res://tools/probe_p9_worldsave_e2e.gd -- --mode=write --p7worldsave --out=DIR
##   ENG --path GAME --script res://tools/probe_p9_worldsave_e2e.gd -- --mode=check --p7worldsave --out=DIR
var _mode := "check"
var _out_dir := ""
var _main: Node = null
var _pass := 0
var _fail := 0
var _lines: Array = []
var _fails: Array = []

const CROPS := preload("res://scripts/isle_crops.gd")

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--mode="): _mode = s.substr(7)
		elif s.begins_with("--out="): _out_dir = s.substr(6).strip_edges().trim_suffix("/").trim_suffix("\\")
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _log(s: String) -> void:
	print(s)
	_lines.append(s)

func _chk(name: String, cond: bool, expected: String, actual: String) -> void:
	if cond:
		_pass += 1
		_log("[CHECK] %s | expected=%s actual=%s | PASS" % [name, expected, actual])
	else:
		_fail += 1
		_fails.append(name)
		_log("[CHECK] %s | expected=%s actual=%s | FAIL" % [name, expected, actual])

func _frames(n: int) -> void:
	for i in range(n):
		await process_frame

func _run() -> void:
	_log("=== worldsave-e2e mode=%s out=%s ===" % [_mode, _out_dir])
	_log("[PATH] user_dir=%s" % OS.get_user_data_dir())
	var ps := load("res://isle.tscn") as PackedScene
	if ps == null:
		_log("[RESULT] FAIL scene"); quit(1); return
	_main = ps.instantiate()
	root.add_child(_main)
	await _frames(10)
	var farm = _main.call("farm")
	var inv = _main.call("inventory")
	if farm == null or inv == null:
		_log("[RESULT] FAIL no-farm"); quit(1); return
	if _mode == "write":
		await _do_write(farm, inv)
	else:
		await _do_check(farm, inv)
	_log("[SUMMARY] checks=%d fail=%d" % [_pass + _fail, _fail])
	_log("[RESULT] %s" % ("PASS" if _fail == 0 and _pass > 0 else "FAIL"))
	var f := FileAccess.open("%s/worldsave_%s.log" % [_out_dir, _mode], FileAccess.WRITE)
	if f != null: f.store_string("\n".join(_lines) + "\n"); f.close()
	quit(0 if _fail == 0 and _pass > 0 else 1)

func _season() -> String:
	return String(_main.call("_farm_season_id"))

## 生产时钟按帧推进，单帧夹取 MAX_REAL_STEP_SECONDS=300s；测试用分块推进模拟多帧，
## 避免一次注入大 dt 被单帧夹取（这不是放宽生产限制，而是模拟真实多帧经过）。
func _advance_clock(sec: float) -> void:
	var left := sec
	while left > 0.001:
		var step := minf(left, 250.0)
		_farm_call("advance_realtime", step)
		left -= step

func _farm_call(method: String, arg: Variant) -> Variant:
	return _main.call("farm").call(method, arg)

func _slot(i: int) -> Dictionary:
	return _main.call("farm").call("get_slot", i)

func _do_write(farm, inv) -> void:
	_log("--- write: 生产路径写档 ---")
	var season: String = _season()
	_log("[WRITE] season=%s" % season)
	_chk("w.farm_clock_mode_real", String(farm.call("clock_mode_name")) == "real", "real", String(farm.call("clock_mode_name")))
	_chk("w.fresh_start", not bool((_main.call("world_save_state") as Dictionary).get("loaded_at_start", true)), "false", str((_main.call("world_save_state") as Dictionary).get("loaded_at_start")))
	# 1) 小麦：播种→成熟→采收一次（一次性作物，格子清空）
	var p0: Dictionary = farm.call("plant", 0, "wheat", season)
	_chk("w.plant_wheat", bool(p0.get("ok", false)), "ok", str(p0))
	_advance_clock(CROPS.first_maturity_seconds("wheat") + 5.0)
	_chk("w.wheat_mature_by_real_clock", bool(farm.call("is_mature", 0)), "true", str(farm.call("is_mature", 0)))
	var h0: Dictionary = farm.call("harvest", 0)
	_chk("w.harvest_wheat", bool(h0.get("ok", false)) and bool(h0.get("plant_removed", false)), "ok+removed", str(h0))
	# 2) 番茄：三次成功收获后移除（跨"存档前"完成，验证收获次数持久化边界）
	var p2: Dictionary = farm.call("plant", 2, "tomato", season)
	_chk("w.plant_tomato", bool(p2.get("ok", false)), "ok", str(p2))
	_advance_clock(CROPS.first_maturity_seconds("tomato") + 2.0)
	var t1: Dictionary = farm.call("harvest", 2)
	_advance_clock(CROPS.regrow_seconds("tomato") + 2.0)
	var t2: Dictionary = farm.call("harvest", 2)
	_advance_clock(CROPS.regrow_seconds("tomato") + 2.0)
	var t3: Dictionary = farm.call("harvest", 2)
	_chk("w.tomato_three_harvests", bool(t1.get("ok")) and bool(t2.get("ok")) and bool(t3.get("ok")), "3 ok", str([t1.get("ok"), t2.get("ok"), t3.get("ok")]))
	_chk("w.tomato_removed_after_third", bool(t3.get("plant_removed", false)) and bool(farm.call("is_empty", 2)), "removed+empty", str(t3.get("plant_removed")))
	# 3) 羽衣甘蓝：种下不推进，存档后在新进程验证"剩余成长时间"恢复
	var p1: Dictionary = farm.call("plant", 1, "kale", season)
	_chk("w.plant_kale", bool(p1.get("ok", false)), "ok", str(p1))
	_advance_clock(100.0)  # 让 kale 处于生长中，剩余时间明确
	var snap_slot1: Dictionary = farm.call("get_slot", 1)
	var remain_before := float(snap_slot1.get("next_ready_at", 0.0)) - float(farm.call("now"))
	var expected := {
		"inventory": inv.call("item_snapshot"),
		"farm_clock": float(farm.call("now")),
		"slot0_empty": bool(farm.call("is_empty", 0)),
		"slot1_crop": String(snap_slot1.get("crop_id", "")),
		"slot1_remain": remain_before,
		"slot2_empty": bool(farm.call("is_empty", 2)),
	}
	# 4) 时间跳转不加速：把 _sim_seconds 向前拨 10 天，kale 剩余成长时间不得改变
	var before_remain := remain_before
	_main.set("_sim_seconds", float(_main.get("_sim_seconds")) + 86400.0 * 10.0)
	await _frames(5)
	var after_remain := float(farm.call("get_slot", 1).get("next_ready_at", 0.0)) - float(farm.call("now"))
	_chk("w.sim_jump_does_not_grow", absf(after_remain - before_remain) < 1.0, "%.1f" % before_remain, "%.1f" % after_remain)
	# 5) 显式走 main 的存档函数（与正式退出/防抖同一实现）
	var save_ok: bool = bool(_main.call("_save_game_state", "probe_write"))
	var ws: Dictionary = _main.call("world_save_state")
	var save_last: Dictionary = ws.get("last", {})
	_chk("w.save_ok", save_ok, "true", str(save_last.get("reason", "")))
	_chk("w.save_count", int(ws.get("save_count", 0)) >= 1, ">=1", str(ws.get("save_count", 0)))
	expected["saved_clock"] = float(farm.call("now"))
	expected["save_path"] = String(save_last.get("path", ""))
	expected["saved_unix"] = float(save_last.get("saved_unix", 0.0))
	expected["inventory_after"] = inv.call("item_snapshot")
	# 记录关键槽位完整状态（新进程逐字段对比）
	expected["slot1_full"] = farm.call("get_slot", 1)
	expected["slot0_full"] = farm.call("get_slot", 0)
	expected["slot2_full"] = farm.call("get_slot", 2)
	var f := FileAccess.open("%s/expected.json" % _out_dir, FileAccess.WRITE)
	f.store_string(JSON.stringify(expected, "  ")); f.close()
	_log("[WRITE] inventory=%s farm_clock=%.2f save=%s" % [JSON.stringify(expected["inventory"]), float(farm.call("now")), expected["save_path"]])
	_log("[WRITE] kale_remain=%.2f slot2_empty=%s" % [remain_before, str(expected["slot2_empty"])])

func _do_check(farm, inv) -> void:
	_log("--- check: 新进程读档 ---")
	var exp_raw := FileAccess.get_file_as_string("%s/expected.json" % _out_dir)
	if exp_raw.is_empty():
		_log("[RESULT] FAIL no expected.json"); quit(1); return
	var exp: Dictionary = JSON.parse_string(exp_raw)
	_chk("c.loaded_at_start", bool((_main.call("world_save_state") as Dictionary).get("loaded_at_start", false)), "true", str((_main.call("world_save_state") as Dictionary).get("loaded_at_start")))
	_chk("c.farm_clock_mode_real", String(farm.call("clock_mode_name")) == "real", "real", String(farm.call("clock_mode_name")))
	# 库存一致（离线期间无操作，数量应完全一致）
	var got_inv: Dictionary = inv.call("item_snapshot")
	var exp_inv: Dictionary = exp.get("inventory_after", exp.get("inventory", {}))
	var same_inv := true
	var keys := {}
	for k in got_inv.keys(): keys[k] = true
	for k in exp_inv.keys(): keys[k] = true
	for k in keys:
		if int(got_inv.get(k, 0)) != int(exp_inv.get(k, 0)):
			same_inv = false
	_chk("c.inventory_restored", same_inv, JSON.stringify(exp_inv), JSON.stringify(got_inv))
	# 九格：0 空、2 空、1 kale，且剩余成长时间 ≈ 保存时（扣除离线已生长部分）
	_chk("c.slot0_empty", bool(farm.call("is_empty", 0)), "true", str(farm.call("is_empty", 0)))
	_chk("c.slot2_empty", bool(farm.call("is_empty", 2)), "true", str(farm.call("is_empty", 2)))
	_chk("c.slot1_crop", String(farm.call("crop_id_at", 1)) == "kale", "kale", String(farm.call("crop_id_at", 1)))
	var slot1: Dictionary = farm.call("get_slot", 1)
	var remain_now := float(slot1.get("next_ready_at", 0.0)) - float(farm.call("now"))
	var remain_before := float(exp.get("slot1_remain", 0.0))
	var offline := maxf(0.0, float(farm.call("now")) - float(exp.get("saved_clock", 0.0)))
	# 读档后 farm.now = 保存时钟 + 离线补涨；剩余时间 = 保存时剩余 - 离线（不小于 0）
	var expect_remain := maxf(0.0, remain_before - offline)
	_chk("c.offline_not_negative", offline >= 0.0 and offline < 120.0, "0..120s", "%.2f" % offline)
	_chk("c.kale_remaining_restored", absf(remain_now - expect_remain) < 1.5, "%.2f" % expect_remain, "%.2f" % remain_now)
	_chk("c.kale_harvest_count_0", int(slot1.get("harvest_count", -1)) == 0, "0", str(slot1.get("harvest_count")))
	# 真实时钟继续推进：补足剩余时间后 kale 成熟并可收（证明不是只恢复显示）
	if remain_now + 1.0 > 0.0:
		_advance_clock(remain_now + 1.0)
	_chk("c.kale_mature_after_real_advance", bool(farm.call("is_mature", 1)), "true", str(farm.call("is_mature", 1)))
	var hk: Dictionary = farm.call("harvest", 1)
	_chk("c.kale_harvest_after_restore", bool(hk.get("ok", false)), "ok", str(hk))
	# 存档不含实时跳变：把 sim 再拨 30 天，不应改变任何槽位成熟判定
	_advance_clock(0.0)
	_main.set("_sim_seconds", float(_main.get("_sim_seconds")) + 86400.0 * 30.0)
	await _frames(5)
	_chk("c.sim_jump_after_load_no_insta_growth", bool(farm.call("is_empty", 0)) and bool(farm.call("is_empty", 2)), "slots unchanged", "0=%s 2=%s" % [str(farm.call("is_empty", 0)), str(farm.call("is_empty", 2))])
	# 保存/恢复接口幂等：再次显式存档成功
	var save_ok2: bool = bool(_main.call("_save_game_state", "probe_check"))
	var ws2: Dictionary = _main.call("world_save_state")
	_chk("c.resave_ok", save_ok2, "true", str((ws2.get("last", {}) as Dictionary).get("reason", "")))
