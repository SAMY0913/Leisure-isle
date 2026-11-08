extends SceneTree

# P8.2-04 生态 soak：真实 isle.tscn（main.gd 完整运行） + 固定 60fps 步进。
# 覆盖：多轮 秋→冬→春、冬→春转换自然性、快速跳季节、跨年、暂停/恢复；
# 断言：树冠/叶卡 kept、冬季裸枝 5 点开放与真实使用率、预约表一致性、
#       鸟类位置合法性、冬花可见性、瞬移计数不增。
# 随机性：fx.gd 内固定种子（_rng.seed=55021 / _vis_rng=77123 / _perch_rng=90210），不需要额外 seed 参数。
# 用法：bash run_godot.sh --headless --path . --fixed-fps 60 --script res://tools/probe_p82_eco_soak.gd

const W := preload("res://scripts/world.gd")

const DT := 1.0 / 60.0
const ROUNDS := 8
const F_AUTUMN := 180
const F_WINTER := 2400      # 40 s/轮（鸟 timer 8~20 s；1800 帧 30s 样本仍偏少）
const F_SPRING := 480
const F_SETTLE := 90

const WINTER_IDS := ["winter_branch_0", "winter_branch_1", "winter_branch_2", "winter_branch_3", "winter_branch_4"]
const ST_PERCH := 3
const ST_LANDING := 2

var _pass := 0
var _fail := 0
var _fails: Array = []
var _main: Node = null
var _fx: Node = null
var _usage: Dictionary = {}
var _prev_pid: Dictionary = {}
var _prev_st: Dictionary = {}
var _conflicts_prev := 0
var _boot_conflicts := 0
var _teleports_snapshot := 0
var _conflict_max := 0
var _round_rows: Array = []
var _winter_evictions_total := 0
var _usage_step_events := 0

func _initialize() -> void:
	print("[SOAK] start rounds=", ROUNDS, " autumn=", F_AUTUMN, " winter=", F_WINTER, " spring=", F_SPRING)
	await process_frame
	var ps: PackedScene = load("res://isle.tscn") as PackedScene
	if ps == null:
		_expect(false, "isle.tscn 可加载", "")
		quit(1)
		return
	_main = ps.instantiate()
	if _main == null:
		_expect(false, "isle.tscn 可实例化", "")
		quit(1)
		return
	root.add_child(_main)
	var frames := 0
	while frames < 2400:
		await process_frame
		frames += 1
		if _main.has_method("_jump_datetime") and _main.get("_birds") != null:
			var wd: Dictionary = _main.get("_world")
			if not wd.is_empty() and (wd.get("perches", null) != null):
				break
	_expect(_main.get("_birds") != null, "main 完成 _ready（世界+鸟群已建）", "waited=%d frames" % frames)
	if _main.get("_birds") == null:
		quit(1)
		return
	_fx = _main.get("_birds")
	_main.set("_mode", 1)            # Mode.PLAYING（头部菜单期不推进模拟）
	_main.set("_time_source", "sim")
	_main.set("_paused", false)
	for i in range(WINTER_IDS.size()):
		_usage[WINTER_IDS[i]] = 0
	_teleports_snapshot = int(_stats().get("teleports", 0))
	_boot_conflicts = int(_stats().get("conflicts", 0))
	print("[SOAK] boot conflicts=%d teleports=%d" % [_boot_conflicts, _teleports_snapshot])
	# 首帧让季节视觉/夜间标记稳定
	await _frames(5)
	_expect(int(_stats().get("perch_count", 0)) > 0, "栖点已注册", "perch_count=%d" % int(_stats().get("perch_count", 0)))
	_expect(_main.get("_winter_bloom").has("heads"), "冬季红花资源已就绪", "")

	for r in range(ROUNDS):
		await _run_round(r, 2026 + r)
	await _test_fast_jumps(2034)
	await _test_cross_year(2035)
	await _test_pause_resume(2038)
	_final_report()
	quit(0 if _fail == 0 else 1)

# ---------------------------------------------------------------- helpers
func _frames(n: int) -> void:
	for i in range(n):
		await process_frame
		_watch_conflicts("frames")

## conflicts 增量定位：_reserve_slot 重复预约会 +1，输出当时预约表与全部鸟姿态。
func _watch_conflicts(tag: String) -> void:
	var cf := int(_stats().get("conflicts", 0))
	if cf <= _conflicts_prev:
		return
	print("[CONFLICT+] tag=%s conflicts %d->%d table=%s" % [tag, _conflicts_prev, cf, JSON.stringify(_fx.get("_perch_used"))])
	for item in _snap():
		var cb: Dictionary = item
		print("[CONFLICT+]    idx=%d st=%d pid=%s slot=%d pos=%s" % [int(cb.get("index", -1)), int(cb.get("state", -1)), String(cb.get("perch_id", "")), int(cb.get("perch_slot", -1)), str(cb.get("pos"))])
	_conflicts_prev = cf

func _expect(cond: bool, label: String, detail: String = "") -> bool:
	if cond:
		_pass += 1
		print("  [OK] ", label, "  ", detail)
	else:
		_fail += 1
		_fails.append(label)
		print("  [FAIL] ", label, "  ", detail)
	return cond

func _jump(y: int, mo: int, d: int, h: int) -> void:
	_main.call("_jump_datetime", y, mo, d, h, 0)
	# _jump_datetime 内部已 force 更新光照/季节/天气
	await process_frame

func _stats() -> Dictionary:
	return _fx.call("debug_perch_stats")

func _avail() -> Array:
	return _fx.call("debug_perch_availability")

func _snap() -> Array:
	return _fx.call("debug_snapshot")

func _perch_of(id: String) -> Dictionary:
	for p_v in _fx.call("get_perches"):
		var p: Dictionary = p_v
		if String(p["id"]) == id:
			return p
	return {}

func _season_kind_sums() -> Dictionary:
	var out := {"canopy_kept": 0, "canopy_count": 0, "cards_kept": 0, "cards_count": 0}
	var nodes: Array = _main.get("_season_nodes")
	for raw in nodes:
		var e: Dictionary = raw
		var kind := String(e.get("kind", ""))
		var cnt := int(e.get("count", 0))
		var kept := int(e.get("kept", -1))
		if kind == "canopy":
			out["canopy_kept"] = int(out["canopy_kept"]) + kept
			out["canopy_count"] = int(out["canopy_count"]) + cnt
		elif kind == "cards":
			out["cards_kept"] = int(out["cards_kept"]) + kept
			out["cards_count"] = int(out["cards_count"]) + cnt
	return out

func _bloom_state() -> Dictionary:
	var wb: Dictionary = _main.get("_winter_bloom")
	var stems = wb.get("stems", null)
	var heads = wb.get("heads", null)
	var out := {"valid": stems != null and heads != null, "stems_visible": false, "heads_visible": false, "count": 0, "scale0": 0.0, "scale_all_min": 0.0, "scale_all_max": 0.0}
	if stems == null or heads == null:
		return out
	out["stems_visible"] = (stems as Node3D).visible
	out["heads_visible"] = (heads as Node3D).visible
	var mm: MultiMesh = (heads as MultiMeshInstance3D).multimesh
	if mm == null:
		return out
	out["count"] = mm.instance_count
	var smin := 1.0e9
	var smax := -1.0e9
	for i in range(mm.instance_count):
		var sc := mm.get_instance_transform(i).basis.get_scale()
		var s := (sc.x + sc.y + sc.z) / 3.0
		smin = minf(smin, s)
		smax = maxf(smax, s)
		if i == 0:
			out["scale0"] = s
	out["scale_all_min"] = smin
	out["scale_all_max"] = smax
	return out

func _leaves_emitting() -> bool:
	var fx_d: Dictionary = _main.get("_fx")
	var entry: Dictionary = fx_d.get("leaves", {})
	var node = entry.get("node", null)
	if node == null:
		return false
	return (node as GPUParticles3D).emitting

func _petals_emitting() -> bool:
	var fx_d: Dictionary = _main.get("_fx")
	var entry: Dictionary = fx_d.get("petals", {})
	var node = entry.get("node", null)
	if node == null:
		return false
	return (node as GPUParticles3D).emitting

## 停栖使用率统计：按“进入 PERCH 状态”的跳变计数（perch_id 在 LANDING 阶段就已写入，
## 用 pid 变化会漏掉全部真实降落；P8.2-04 首版 soak 因此误报 0/5）。
func _collect_usage(snap: Array) -> void:
	for item in snap:
		var b: Dictionary = item
		var idx := int(b.get("index", -1))
		var st: int = int(b.get("state", -1))
		var pid := String(b.get("perch_id", ""))
		var prev_st := int(_prev_st.get(idx, -1))
		if st == ST_PERCH and pid != "" and prev_st != ST_PERCH:
			_usage[pid] = int(_usage.get(pid, 0)) + 1
			_usage_step_events += 1
			var pu: Dictionary = _prev_pid.get("__round_usage", {})
			pu[pid] = int(pu.get(pid, 0)) + 1
			_prev_pid["__round_usage"] = pu
			print("[LAND] f pid=%s bird=%d from_state=%d" % [pid, idx, prev_st])
		_prev_pid[idx] = pid
		_prev_st[idx] = st

func _reset_round_usage() -> void:
	var pu: Dictionary = {}
	for i in range(WINTER_IDS.size()):
		pu[WINTER_IDS[i]] = 0
	_prev_pid["__round_usage"] = pu
	# 同步当前状态，避免把“本轮开始前就已停栖”的鸟算成本轮降落
	_prev_st.clear()
	for item in _snap():
		var b: Dictionary = item
		_prev_st[int(b.get("index", -1))] = int(b.get("state", -1))
		_prev_pid[int(b.get("index", -1))] = String(b.get("perch_id", ""))

func _round_usage() -> Dictionary:
	return _prev_pid.get("__round_usage", {})

func _reservation_check(label: String) -> void:
	var used := {}
	var conflicts := 0
	var mismatch := 0
	for item in _snap():
		var b: Dictionary = item
		var st: int = int(b.get("state", -1))
		if st != ST_PERCH and st != ST_LANDING:
			continue
		var pid := String(b.get("perch_id", ""))
		if pid == "":
			continue
		var key := "%s#%d" % [pid, int(b.get("perch_slot", -1))]
		if used.has(key):
			conflicts += 1
		used[key] = true
	var fx_used := 0
	var raw_used: Dictionary = _fx.get("_perch_used")
	for k_v in raw_used.keys():
		var arr: Array = raw_used[k_v]
		fx_used += arr.size()
	for key_v in used.keys():
		var parts := String(key_v).split("#")
		var pid := parts[0]
		var slot := int(parts[1])
		var arr2: Array = raw_used.get(pid, [])
		if not arr2.has(slot):
			mismatch += 1
	var st2 := _stats()
	_conflict_max = maxi(_conflict_max, conflicts)
	_expect(conflicts == 0, label + " 预约无重复槽位", "conflicts=%d" % conflicts)
	_expect(mismatch == 0, label + " 每只停栖鸟的预约都在预约表内", "mismatch=%d" % mismatch)
	_expect(fx_used == used.size(), label + " 预约表槽位数 == 停栖/降落鸟数", "table=%d birds=%d stats=%d" % [fx_used, used.size(), int(st2.get("used_slots", -1))])

func _check_no_bad_reservations(label: String) -> void:
	var bad := []
	var raw_used: Dictionary = _fx.get("_perch_used")
	for pid_v in raw_used.keys():
		var pid := String(pid_v)
		var p := _perch_of(pid)
		if p.is_empty():
			bad.append(pid + ":missing")
			continue
		var ev: Dictionary = _fx.call("_perch_eligible", p, -1.0, 0.0, false, false)
		if not bool(ev.get("eligible", true)):
			bad.append(pid + ":" + String(ev.get("reason", "?")))
	_expect(bad.is_empty(), label + " 预约表只含当前可用栖点", "" if bad.is_empty() else "bad=" + str(bad))

func _check_bird_positions(label: String) -> void:
	var bad_ground := 0
	var bad_bounds := 0
	var bad_perch := 0
	var perched := 0
	var max_d := 0.0
	var ground_detail: Array = []
	for item in _snap():
		var b: Dictionary = item
		var pos: Vector3 = b["pos"]
		var st: int = int(b.get("state", -1))
		# 地形高度场在水域是海床（负值）；码头/灯桩栖点在海上 1~2m 是合法的。
		# 判定“钻地”= 低于可站立表面（陆地用地形，水域用海平面 0m）0.25m 以上。
		var terr := W.surface_y(pos.x, pos.z)
		var standable := maxf(terr, 0.0)
		if pos.y < standable + 0.25:
			bad_ground += 1
			if ground_detail.size() < 4:
				ground_detail.append("idx=%d st=%d pid=%s pos=(%.2f,%.2f,%.2f) terrain=%.2f standable=%.2f gap=%.2f" % [int(b.get("index", -1)), st, String(b.get("perch_id", "")), pos.x, pos.y, pos.z, terr, standable, pos.y - standable])
		if absf(pos.x) > 90.0 or absf(pos.z) > 90.0 or pos.y > 80.0:
			bad_bounds += 1
		if st == ST_PERCH:
			perched += 1
			var pid := String(b.get("perch_id", ""))
			if pid == "":
				bad_perch += 1
				continue
			var p := _perch_of(pid)
			if p.is_empty():
				bad_perch += 1
				continue
			var slot := int(b.get("perch_slot", 0))
			var sp: Vector3 = _fx.call("_slot_position", p, slot)
			var idle := bool(b.get("idle_active", false))
			var d := pos.distance_to(sp)
			max_d = maxf(max_d, d)
			var tol := 0.60 if idle else 0.06
			if d > tol:
				bad_perch += 1
	_expect(bad_ground == 0, label + " 无鸟钻地", ("bad=%d " % bad_ground) + str(ground_detail))
	_expect(bad_bounds == 0, label + " 鸟位置在世界范围内", "bad=%d" % bad_bounds)
	_expect(bad_perch == 0, label + " 停栖鸟贴在所属栖点槽位上（idle 轻跳放宽 0.6m）", "perched=%d bad=%d max_d=%.3f" % [perched, bad_perch, max_d])

func _check_teleports(label: String) -> void:
	var tp := int(_stats().get("teleports", 0))
	_expect(tp == _teleports_snapshot, label + " 无瞬移（teleports 增量 0）", "now=%d base=%d" % [tp, _teleports_snapshot])

func _winter_gate_checks(label: String) -> void:
	var st := _stats()
	_expect(bool(st.get("winter_open", false)), label + " 冬季裸枝门控开启", "winter_open=%s" % str(st.get("winter_open")))
	_expect(not bool(st.get("leafy_open", true)), label + " 冠面树栖点门控关闭", "leafy_open=%s" % str(st.get("leafy_open")))
	var avail: Array = _avail()
	var w_ok := 0
	var w_bad := []
	var t_ok := 0
	for a_v in avail:
		var a: Dictionary = a_v
		var pid := String(a.get("id", ""))
		if pid.begins_with("winter_branch"):
			if bool(a.get("eligible", false)):
				w_ok += 1
			else:
				w_bad.append(pid + ":" + String(a.get("reason", "?")))
		elif String(a.get("kind", "")) == "tree_branch":
			if not bool(a.get("eligible", true)) and String(a.get("reason", "")) == "season_off":
				t_ok += 1
	_expect(w_ok == 5, label + " 5 个冬季专用栖点全部可用", "eligible=%d bad=%s" % [w_ok, str(w_bad)])
	_expect(t_ok >= 6, label + " 6 个冠面树栖点全部 season_off", "count=%d" % t_ok)

func _spring_gate_checks(label: String) -> void:
	var st := _stats()
	_expect(not bool(st.get("winter_open", true)), label + " 冬季裸枝门控关闭", "")
	_expect(bool(st.get("leafy_open", false)), label + " 冠面树栖点门控开启", "")
	var avail: Array = _avail()
	var w_off := 0
	var t_open := 0
	for a_v in avail:
		var a: Dictionary = a_v
		var pid := String(a.get("id", ""))
		if pid.begins_with("winter_branch"):
			if not bool(a.get("eligible", true)) and String(a.get("reason", "")) == "season_off":
				w_off += 1
		elif String(a.get("kind", "")) == "tree_branch":
			if bool(a.get("eligible", false)):
				t_open += 1
	_expect(w_off == 5, label + " 5 个冬季裸枝点全部 season_off", "off=%d" % w_off)
	_expect(t_open >= 6, label + " 6 个冠面树栖点恢复可用", "open=%d" % t_open)

func _no_winter_residue(label: String) -> void:
	var raw_used: Dictionary = _fx.get("_perch_used")
	var residue := []
	for pid_v in raw_used.keys():
		if String(pid_v).begins_with("winter_branch"):
			residue.append(String(pid_v))
	for item in _snap():
		var b: Dictionary = item
		if int(b.get("state", -1)) == ST_PERCH and String(b.get("perch_id", "")).begins_with("winter_branch"):
			residue.append("bird:" + String(b.get("perch_id")))
	_expect(residue.is_empty(), label + " 冬季预约与停栖无残留", "" if residue.is_empty() else str(residue))

func _no_tree_residue(label: String) -> void:
	var raw_used: Dictionary = _fx.get("_perch_used")
	var residue := []
	for pid_v in raw_used.keys():
		var p := _perch_of(String(pid_v))
		if String(p.get("kind", "")) == "tree_branch":
			residue.append(String(pid_v))
	for item in _snap():
		var b: Dictionary = item
		var pid := String(b.get("perch_id", ""))
		var p2 := _perch_of(pid)
		if int(b.get("state", -1)) == ST_PERCH and String(p2.get("kind", "")) == "tree_branch":
			residue.append("bird:" + pid)
	_expect(residue.is_empty(), label + " 落叶后无鸟停在冠面栖点", "" if residue.is_empty() else str(residue))

# ---------------------------------------------------------------- rounds
func _run_round(r: int, year: int) -> void:
	_reset_round_usage()
	_conflicts_prev = int(_stats().get("conflicts", 0))
	_teleports_snapshot = int(_stats().get("teleports", 0))
	var ev0 := int(_stats().get("season_evictions", 0))
	print("[ROUND %d] year=%d" % [r, year])

	# --- 秋 ---
	await _jump(year, 10, 20, 16)
	await _frames(F_AUTUMN)
	_expect(_leaves_emitting(), "R%d 秋：落叶粒子发射" % r, "")
	var autumn_canopy := int(_season_kind_sums()["canopy_kept"])
	_expect(autumn_canopy > 30, "R%d 秋：树冠仍在（kept>30）" % r, "kept=%d" % autumn_canopy)
	var w0 := float((_main.get("_season_weights") as Array)[3])
	_expect(w0 < 0.60, "R%d 秋：冬季权重<0.60（裸枝点应关闭）" % r, "winter_w=%.3f" % w0)
	var avail_a: Array = _avail()
	var autumn_w_off := 0
	for a_v in avail_a:
		var a: Dictionary = a_v
		if String(a.get("id", "")).begins_with("winter_branch") and String(a.get("reason", "")) == "season_off":
			autumn_w_off += 1
	_expect(autumn_w_off == 5, "R%d 秋：5 个冬季裸枝点 season_off" % r, "off=%d" % autumn_w_off)

	# --- 秋 → 冬 ---
	await _jump(year + 1, 1, 15, 10)
	await _frames(F_SETTLE)
	var sums := _season_kind_sums()
	_expect(int(sums["canopy_kept"]) == 0, "R%d 冬：树冠叶片清零" % r, "kept=%d/%d" % [int(sums["canopy_kept"]), int(sums["canopy_count"])])
	_expect(int(sums["cards_kept"]) == 0, "R%d 冬：叶卡清零" % r, "kept=%d/%d" % [int(sums["cards_kept"]), int(sums["cards_count"])])
	_winter_gate_checks("R%d 冬" % r)
	_no_tree_residue("R%d 秋→冬" % r)
	var bl := _bloom_state()
	_expect(bool(bl["valid"]) and bool(bl["stems_visible"]) and bool(bl["heads_visible"]), "R%d 冬：屋前红花可见（茎+头）" % r, "count=%d" % int(bl["count"]))
	_expect(int(bl["count"]) == 5, "R%d 冬：红花 5 朵" % r, "count=%d" % int(bl["count"]))
	_expect(float(bl["scale_all_min"]) > 0.5, "R%d 冬：红花实例缩放生效（>=0.5）" % r, "min=%.3f max=%.3f" % [float(bl["scale_all_min"]), float(bl["scale_all_max"])])
	_expect(not _leaves_emitting(), "R%d 冬：落叶粒子停发" % r, "")
	_reservation_check("R%d 冬" % r)
	_check_no_bad_reservations("R%d 冬" % r)
	_check_bird_positions("R%d 冬" % r)
	_check_teleports("R%d 冬" % r)
	var ev1 := int(_stats().get("season_evictions", 0))
	_expect(ev1 >= ev0, "R%d 秋→冬：季节驱逐计数只增不减" % r, "delta=%d" % (ev1 - ev0))

	# --- 冬季持续观察（统计自然使用率）---
	var remain := F_WINTER - F_SETTLE
	var i := 0
	while i < remain:
		await process_frame
		_collect_usage(_snap())
		# conflicts 增量定位（_reserve_slot 重复预约会计数；P8.2-04 需查清来源）
		_watch_conflicts("R%d winter" % r)
		if i % 120 == 1:
			_check_bird_positions("R%d 冬持续" % r)
			_reservation_check("R%d 冬持续" % r)
		i += 1
	var wstats := _stats()
	print("[ROUND %d] winter perched=%d used_slots=%d winter_open=%s leafy_open=%s" % [r, int(wstats.get("perched", 0)), int(wstats.get("used_slots", 0)), str(wstats.get("winter_open")), str(wstats.get("leafy_open"))])

	# --- 冬 → 春 ---
	await _jump(year + 1, 4, 15, 10)
	await _frames(F_SETTLE)
	var spring_tr := int(_stats().get("season_evictions", 0))
	_expect(spring_tr >= ev1, "R%d 冬→春：季节驱逐计数只增不减" % r, "delta=%d" % (spring_tr - ev1))
	_no_winter_residue("R%d 冬→春" % r)
	_spring_gate_checks("R%d 春" % r)
	var sums2 := _season_kind_sums()
	var v2: Dictionary = _main.get("_season_visuals")
	var exp_canopy := int(round(float(sums2["canopy_count"]) * float(v2.get("canopy_keep", 1.0))))
	var exp_cards := int(round(float(sums2["cards_count"]) * float(v2.get("leafcard_keep", 1.0))))
	_expect(int(sums2["canopy_kept"]) == exp_canopy, "R%d 春：树冠恢复数量=round(count*canopy_keep)" % r, "kept=%d expect=%d count=%d keep=%.3f" % [int(sums2["canopy_kept"]), exp_canopy, int(sums2["canopy_count"]), float(v2.get("canopy_keep", 1.0))])
	_expect(int(sums2["cards_kept"]) == exp_cards, "R%d 春：叶卡恢复数量=round(count*leafcard_keep)" % r, "kept=%d expect=%d count=%d keep=%.3f" % [int(sums2["cards_kept"]), exp_cards, int(sums2["cards_count"]), float(v2.get("leafcard_keep", 1.0))])
	var bl2 := _bloom_state()
	_expect(not bool(bl2["stems_visible"]) and not bool(bl2["heads_visible"]), "R%d 春：红花隐藏" % r, "")
	_expect(_petals_emitting(), "R%d 春：花瓣粒子发射" % r, "")
	_reservation_check("R%d 春" % r)
	_check_no_bad_reservations("R%d 春" % r)
	_check_bird_positions("R%d 春" % r)
	_check_teleports("R%d 春" % r)
	await _frames(F_SPRING - F_SETTLE)
	_no_winter_residue("R%d 春末" % r)

	var ru := _round_usage()
	_round_rows.append({"round": r, "usage": ru})
	print("[USAGE R%d] %s" % [r, JSON.stringify(ru)])

# ---------------------------------------------------------------- extra tests
func _test_fast_jumps(year: int) -> void:
	print("[TEST] 快速跳多季节")
	_teleports_snapshot = int(_stats().get("teleports", 0))
	await _jump(year, 10, 20, 16)
	await _frames(3)
	var off := 0
	for a_v in _avail():
		var a: Dictionary = a_v
		if String(a.get("id", "")).begins_with("winter_branch") and String(a.get("reason", "")) == "season_off":
			off += 1
	_expect(off == 5, "快跳 秋（3 帧）：冬季裸枝点关闭", "off=%d" % off)
	await _jump(year + 1, 1, 15, 10)
	await _frames(3)
	var sums := _season_kind_sums()
	_expect(int(sums["canopy_kept"]) == 0, "快跳 秋→冬（3 帧）：树冠清零", "kept=%d" % int(sums["canopy_kept"]))
	_winter_gate_checks("快跳 秋→冬")
	await _jump(year + 1, 4, 15, 10)
	await _frames(3)
	_expect(int(_season_kind_sums()["canopy_kept"]) > 30, "快跳 冬→春（3 帧）：树冠恢复", "kept=%d" % int(_season_kind_sums()["canopy_kept"]))
	await _jump(year + 1, 7, 15, 12)
	await _frames(3)
	_spring_gate_checks("快跳 夏")
	await _jump(year + 1, 10, 20, 16)
	await _frames(3)
	await _jump(year + 2, 1, 15, 10)
	await _frames(3)
	_winter_gate_checks("快跳 秋→冬 二次")
	_no_tree_residue("快跳 二次入冬")
	_reservation_check("快跳 二次入冬")
	_check_teleports("快跳 多季节")
	# 跳回春季让后续测试从干净状态开始
	await _jump(year + 2, 4, 15, 10)
	await _frames(60)

func _test_cross_year(year: int) -> void:
	print("[TEST] 跨年 连续三个冬季")
	_teleports_snapshot = int(_stats().get("teleports", 0))
	for k in range(3):
		await _jump(year + k, 1, 15, 10)
		await _frames(120)
		var sums := _season_kind_sums()
		_expect(int(sums["canopy_kept"]) == 0, "跨年 winter %d：树冠清零" % (year + k), "kept=%d" % int(sums["canopy_kept"]))
		_winter_gate_checks("跨年 winter %d" % (year + k))
		_no_tree_residue("跨年 winter %d" % (year + k))
		_reservation_check("跨年 winter %d" % (year + k))
		_check_bird_positions("跨年 winter %d" % (year + k))
		# 冬季中记录使用
		for i in range(120):
			await process_frame
			_collect_usage(_snap())
	_check_teleports("跨年 三冬")
	await _jump(year + 3, 4, 15, 10)
	await _frames(120)
	_spring_gate_checks("跨年 春")
	_no_winter_residue("跨年 春")

func _test_pause_resume(year: int) -> void:
	print("[TEST] 暂停/恢复一致性")
	_teleports_snapshot = int(_stats().get("teleports", 0))
	await _jump(year, 1, 15, 10)
	await _frames(180)
	_winter_gate_checks("暂停前")
	_reservation_check("暂停前")
	var w_before := (_main.get("_season_weights") as Array).duplicate()
	var bl_before := _bloom_state()
	_main.set("_paused", true)
	await _frames(180)
	var eco: Dictionary = _fx.call("debug_eco_state")
	_expect(bool(eco.get("paused", false)), "暂停：fx 收到 paused=true", "")
	var w_during: Array = _main.get("_season_weights")
	var same_w := w_before.size() == w_during.size()
	if same_w:
		for i in range(w_before.size()):
			if absf(float(w_before[i]) - float(w_during[i])) > 1e-6:
				same_w = false
				break
	_expect(same_w, "暂停：季节权重不漂移", str(w_during))
	var bl_during := _bloom_state()
	_expect(float(bl_during["scale_all_min"]) == float(bl_before["scale_all_min"]), "暂停：红花缩放不漂移", "%.4f" % float(bl_during["scale_all_min"]))
	_reservation_check("暂停中")
	_check_bird_positions("暂停中")
	_check_teleports("暂停中")
	_main.set("_paused", false)
	await _frames(300)
	var eco2: Dictionary = _fx.call("debug_eco_state")
	_expect(not bool(eco2.get("paused", true)), "恢复：fx paused=false", "")
	_winter_gate_checks("恢复后")
	_reservation_check("恢复后")
	_check_bird_positions("恢复后")
	_check_teleports("恢复后")
	await _jump(year, 4, 15, 10)
	await _frames(120)
	_spring_gate_checks("暂停后回春")
	_no_winter_residue("暂停后回春")

# ---------------------------------------------------------------- report
func _final_report() -> void:
	print("")
	print("================ P8.2-04 ECO SOAK SUMMARY ================")
	print("[USAGE TOTAL] ", JSON.stringify(_usage), "  step_events=", _usage_step_events)
	var used_points := 0
	var max_u := 0
	var min_u := 1 << 30
	for i in range(WINTER_IDS.size()):
		var u := int(_usage.get(WINTER_IDS[i], 0))
		if u > 0:
			used_points += 1
		max_u = maxi(max_u, u)
		min_u = mini(min_u, u)
	print("[USAGE] used_points=%d/5 max=%d min=%d" % [used_points, max_u, min_u])
	_expect(used_points == 5, "5 个冬季裸枝点都被自然使用过", "used=%d/5" % used_points)
	_expect(max_u > 0 and float(min_u) >= float(max_u) * 0.2, "使用分布无极端偏斜（最少点 >= 最多点的 20%）", "min=%d max=%d ratio=%.2f" % [min_u, max_u, float(min_u) / maxf(float(max_u), 1.0)])
	_expect(_conflict_max == 0, "全程预约冲突峰值 0", "conflict_max=%d" % _conflict_max)
	var st := _stats()
	print("[FINAL] teleports=%d season_evictions=%d cap_fallbacks=%d no_slot_skips=%d conflicts=%d used_slots=%d" % [int(st.get("teleports", 0)), int(st.get("season_evictions", 0)), int(st.get("cap_fallbacks", 0)), int(st.get("no_slot_skips", 0)), int(st.get("conflicts", 0)), int(st.get("used_slots", 0))])
	# conflicts 计数器也会在启动时 _reseat_all 的初始强制落座里自增；这里只对“运行期新增”做严格断言。
	var conf_now := int(st.get("conflicts", 0))
	_expect(conf_now == _boot_conflicts, "运行期无新增预约冲突（排除 boot 初始落座）", "boot=%d now=%d" % [_boot_conflicts, conf_now])
	print("=== P8.2-04 ECO SOAK RESULT: %s pass=%d fail=%d ===" % ["PASS" if _fail == 0 else "FAIL", _pass, _fail])
	if _fail > 0:
		print("[FAILED ITEMS] ", str(_fails))
