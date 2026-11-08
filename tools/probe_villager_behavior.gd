extends SceneTree
## P7-V4 岛民控制器 headless 行为探针（不启动主场景，直接构造 Cottage+Villager）。

var fails: Array = []
var passes: int = 0
var holder: Node3D
var cottage: Dictionary
var V
var v: Node3D
var Astro
var Spot
var Model
var door_log: Array = []

func ok(cond: bool, label: String, detail: String = "") -> void:
	if cond:
		passes += 1
		print("  PASS ", label, ("  " + detail) if detail != "" else "")
	else:
		fails.append(label + (("  [" + detail + "]") if detail != "" else ""))
		print("  FAIL ", label, ("  " + detail) if detail != "" else "")

func ctx_for(sim: float, frozen: bool = false) -> Dictionary:
	var a: Dictionary = Astro.compute(sim)
	var ev: Dictionary = Astro.day_events(sim)
	return {
		"sim_seconds": sim,
		"sim_rate": 144.0,
		"sun_alt": float(a.get("sun_alt", 30.0)),
		"events": ev,
		"time_jump": _tj,
		"frozen": frozen,
		"door_set": Callable(self, "_on_door"),
	}

var _tj := 0.0
func _on_door(open: bool) -> void:
	door_log.append(open)

var _sim := 0.0
func tick(seconds: float, frozen: bool = false, sim_advance: bool = true) -> void:
	var dt := 1.0 / 60.0
	var n := maxi(1, int(round(seconds / dt)))
	for i in n:
		if sim_advance and not frozen:
			_sim += dt * 144.0
		v.call("sim_tick", dt, ctx_for(_sim, frozen))
		var an: AnimationPlayer = v.get("anim")
		if an != null and not frozen:
			an.advance(dt)

## 每次状态/剪辑变化打印一行；到达目标状态集合或超时返回
func tick_until_done(max_seconds: float, label: String, targets: Array = ["SIT", "EAT", "SLEEP"]) -> void:
	var dt := 1.0 / 60.0
	var t := 0.0
	var last := ""
	while t < max_seconds:
		_sim += dt * 144.0
		v.call("sim_tick", dt, ctx_for(_sim))
		var an2: AnimationPlayer = v.get("anim")
		if an2 != null:
			an2.advance(dt)
		t += dt
		var st: Dictionary = v.call("debug_state")
		var sig := "%s/%s/%s" % [st["state"], st["clip"], st["kind"]]
		if sig != last:
			print("    ", "%.2fs" % t, " ", sig, " pos=", _fmt(st["pos"]), " node=", st["at_node"], " y=", "%.3f" % (st["pos"] as Vector3).y)
			last = sig
		if t > 0.25 and targets.has(String(st["state"])):
			print("    -> reached %s at %.2fs" % [String(st["state"]), t])
			return
	print("    -> TIMEOUT ", label)
	fails.append("timeout: " + label)

func _fmt(p: Vector3) -> String:
	return "(%.2f,%.2f,%.2f)" % [p.x, p.y, p.z]

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	print("[TEST] P7-V4 villager behavior probe")
	Astro = load("res://scripts/isle_astro.gd")
	Spot = load("res://scripts/isle_villager_spots.gd")
	Model = load("res://scripts/isle_villager_model.gd")
	holder = Node3D.new()
	holder.name = "World"
	get_root().add_child(holder)
	var Cottage = load("res://scripts/cottage.gd")
	cottage = Cottage.build(holder)
	var World = load("res://scripts/world.gd")
	# 只用于确保 world 静态函数可用（surface_y 是纯函数，无需 build）

	# ---------- 模型剪辑 ----------
	print("\n== model clips ==")
	var mroot: Node3D = Model.create(0)["root"]
	holder.add_child(mroot)
	var anim_names: PackedStringArray = mroot.call("get_animation_names")
	var need := ["idle", "idle_alt", "walk", "sit_down", "sit_idle", "sit_up", "bed_sit_down", "bed_sit_up", "eat", "lie_down", "sleep", "get_up"]
	for n in need:
		ok(anim_names.has(n), "clip " + n)
	var ms: Dictionary = Model.measure(mroot, {"include_hidden": false})
	print("  stats: ", ms)
	ok(int(ms["meshes"]) <= 16, "meshes<=16", str(ms["meshes"]))
	ok(int(ms["dc_est"]) <= 40, "dc_est<=40", str(ms["dc_est"]))
	mroot.queue_free()

	# ---------- 构建 ----------
	print("\n== villager build ==")
	var G = load("res://scripts/isle_villager_spots.gd")
	var t0 := Time.get_ticks_msec()
	v = load("res://scripts/isle_villager.gd").build(holder, cottage, 7)
	var build_ms := Time.get_ticks_msec() - t0
	print("  build %.1f ms" % float(build_ms))
	var dbg: Dictionary = v.call("debug_state")
	print("  spawn state=", dbg["state"], " pos=", _fmt(dbg["pos"]), " node=", dbg["at_node"], " window=", dbg["window"])
	print("  stats: ", dbg["stats"])
	ok(dbg["state"] == "IDLE", "spawn IDLE")
	var graph: Dictionary = v.get("graph")
	var issues: Array = G.validate(graph)
	print("  graph: nodes=", (graph["nodes"] as Dictionary).size(), " spots=", (graph["spots"] as Dictionary).size(), " issues=", issues.size())
	for it in issues:
		print("    issue: ", it)
	ok(issues.is_empty(), "graph validate clean", str(issues))

	# ---------- idle 3s（强制待机，排除日程立即行动）----------
	print("\n== idle ==")
	_sim = 12.0 * 3600.0  # 12:00
	v.call("force_idle", 3.0)
	tick(2.0)
	dbg = v.call("debug_state")
	ok(dbg["state"] == "IDLE", "still IDLE after 2s", String(dbg["state"]))
	ok(String(dbg["clip"]).begins_with("idle"), "idle clip", String(dbg["clip"]))
	v.call("clear_force")
	tick(0.3)

	# ---------- 行走：门廊 -> 客厅 ----------
	print("\n== walk: deck -> hall ==")
	ok(bool(v.call("force_walk_to_node", "hall")), "force_walk_to_node(hall) accepted")
	tick_until_done(60.0, "walk hall", ["IDLE"])
	dbg = v.call("debug_state")
	ok(String(dbg["at_node"]) == "hall", "arrived hall", String(dbg["at_node"]))
	var hp: Vector3 = (graph["nodes"]["hall"] as Dictionary)["pos"]
	ok((dbg["pos"] as Vector3).distance_to(hp) < 0.12, "pos at hall", _fmt(dbg["pos"]))
	print("  door log: ", door_log)

	# ---------- 行走：上楼 ----------
	print("\n== walk: hall -> attic_exit (stairs) ==")
	door_log.clear()
	ok(bool(v.call("force_walk_to_node", "attic_exit")), "force_walk_to_node(attic_exit) accepted")
	var stair_ys: Array = []
	var dt := 1.0 / 60.0
	var walked := 0.0
	var last_clip := ""
	while walked < 90.0:
		_sim += dt * 144.0
		v.call("sim_tick", dt, ctx_for(_sim))
		var an3: AnimationPlayer = v.get("anim")
		if an3 != null:
			an3.advance(dt)
		walked += dt
		dbg = v.call("debug_state")
		stair_ys.append((dbg["pos"] as Vector3).y)
		if dbg["state"] != "WALK" and walked > 0.5:
			break
	dbg = v.call("debug_state")
	var apex: float = (graph["nodes"]["attic_exit"] as Dictionary)["pos"].y
	print("    end state=", dbg["state"], " pos=", _fmt(dbg["pos"]), " apex_y=%.3f" % apex, " walk_t=%.1fs" % walked)
	ok(absf(float((dbg["pos"] as Vector3).y) - apex) < 0.15, "reached attic height", "%.3f vs %.3f" % [(dbg["pos"] as Vector3).y, apex])
	var mono := true
	var bad_ys := 0
	for i in range(2, stair_ys.size()):
		if float(stair_ys[i]) < float(stair_ys[i - 1]) - 0.001:
			bad_ys += 1
	ok(bad_ys == 0, "stair y monotonic non-decreasing", "bad=" + str(bad_ys))
	ok(bool(dbg["at_node"] == "attic_exit"), "at attic_exit", String(dbg["at_node"]))

	# ---------- 坐下（沙发，front 侧） ----------
	print("\n== sit: sofa ==")
	ok(bool(v.call("force_sit", "sofa")), "force_sit(sofa) accepted")
	tick_until_done(60.0, "sit sofa", ["SIT"])
	dbg = v.call("debug_state")
	var sp: Dictionary = (graph["spots"]["sofa"] as Dictionary)
	print("    state=", dbg["state"], " clip=", dbg["clip"], " pos=", _fmt(dbg["pos"]), " seat=", _fmt(sp["anchor"]))
	ok(dbg["state"] == "SIT", "SIT state", String(dbg["state"]))
	ok(String(dbg["clip"]) == "sit_idle", "sit_idle clip", String(dbg["clip"]))
	var sitp: Vector3 = sp["anchor"] + Vector3(0, 0.02, 0)
	ok((dbg["pos"] as Vector3).distance_to(sitp) < 0.05, "root at seat+0.02", _fmt(dbg["pos"]))
	var seated := absf(wrapf(float(dbg["yaw"]) - float(sp["yaw"]), -PI, PI)) < 0.05
	ok(seated, "yaw matches spot", "%.2f vs %.2f" % [float(dbg["yaw"]), float(sp["yaw"])])
	ok(bool(v.call("spot_reserved")), "spot reserved while sitting")
	# 起身：clear_force 应立即释放并回到 IDLE（随后自主日程可合法开始新活动）
	v.call("clear_force")
	dbg = v.call("debug_state")
	ok(not bool((graph["spots"]["sofa"] as Dictionary)["reserved"]), "sofa released after clear_force")
	ok(dbg["state"] == "IDLE", "back to IDLE after clear_force", String(dbg["state"]))
	tick(2.0)

	# ---------- 吃饭（餐桌） ----------
	print("\n== eat at dining table ==")
	ok(bool(v.call("force_eat", "eat_s")), "force_eat(eat_s) accepted")
	tick_until_done(60.0, "eat eat_s", ["EAT"])
	dbg = v.call("debug_state")
	print("    state=", dbg["state"], " clip=", dbg["clip"], " pos=", _fmt(dbg["pos"]))
	ok(dbg["state"] == "EAT", "EAT state", String(dbg["state"]))
	ok(String(dbg["clip"]) == "eat", "eat clip", String(dbg["clip"]))
	ok(bool(v.call("spot_reserved")), "eat spot reserved")
	v.call("clear_force")
	ok(not bool((graph["spots"]["eat_s"] as Dictionary)["reserved"]), "eat_s released after clear_force")
	tick(1.0)

	# ---------- 上床 ----------
	print("\n== bed ==")
	ok(bool(v.call("force_bed")), "force_bed accepted")
	tick_until_done(120.0, "bed", ["SLEEP"])
	dbg = v.call("debug_state")
	print("    state=", dbg["state"], " clip=", dbg["clip"], " pos=", _fmt(dbg["pos"]), " yaw=%.2f" % float(dbg["yaw"]))
	var bed: Dictionary = graph["spots"]["bed_attic"]
	var lie_root: Vector3 = (bed["anchor"] as Vector3) + Vector3(0, 0.02, 0)
	ok(dbg["state"] == "SLEEP", "SLEEP state", String(dbg["state"]))
	ok(String(dbg["clip"]) == "sleep", "sleep clip", String(dbg["clip"]))
	ok((dbg["pos"] as Vector3).distance_to(lie_root) < 0.06, "lie root = mattress+0.02", _fmt(dbg["pos"]))
	var bed_yaw := absf(wrapf(float(dbg["yaw"]) - float(bed["yaw"]), -PI, PI))
	ok(bed_yaw < 0.08, "bed yaw", "%.2f vs %.2f diff %.2f" % [float(dbg["yaw"]), float(bed["yaw"]), bed_yaw])
	ok(bool(v.call("spot_reserved")), "bed reserved while sleeping")
	# 唤醒：时间到清晨窗口（世界时间前进到 08:00）
	print("    -> advance world time to 08:00 next morning")
	var cur: float = v.get("_sim_now")
	_sim = cur + 24.0 * 3600.0
	tick_until_done(60.0, "wake", ["IDLE", "WALK"])
	dbg = v.call("debug_state")
	print("    state=", dbg["state"], " clip=", dbg["clip"], " pos=", _fmt(dbg["pos"]))
	ok(dbg["state"] == "IDLE" or dbg["state"] == "WALK", "woke up to IDLE/WALK", String(dbg["state"]))
	ok(not bool(v.call("spot_reserved")), "bed released after wake")
	v.call("clear_force")
	tick(0.5)

	# ---------- 自主日程（12:00 应倾向 eat） ----------
	print("\n== autonomous schedule ==")
	# 重新放到客厅，时间设为 12:00
	v.call("clear_force")
	_sim = 12.0 * 3600.0
	var st2: Dictionary = v.call("debug_state")
	print("    start sim=%.0f pos=%s" % [_sim, _fmt(st2["pos"])])
	var kinds: Array = []
	var states: Array = []
	var last_kind := ""
	var last_state := ""
	var dt2 := 1.0 / 60.0
	var total := 0.0
	while total < 120.0:
		_sim += dt2 * 144.0
		v.call("sim_tick", dt2, ctx_for(_sim))
		var an4: AnimationPlayer = v.get("anim")
		if an4 != null:
			an4.advance(dt2)
		total += dt2
		var d: Dictionary = v.call("debug_state")
		if String(d["kind"]) != last_kind:
			last_kind = String(d["kind"])
			kinds.append(last_kind)
			print("    %.1fs decide kind=%s" % [total, last_kind])
		if String(d["state"]) != last_state:
			last_state = String(d["state"])
			states.append(last_state)
			print("    %.1fs state=%s clip=%s spot=%s" % [total, last_state, d["clip"], d["spot_id"]])
	print("    kinds=", kinds)
	print("    states=", states)
	ok(kinds.size() >= 2, "autonomous activity changed at least once", str(kinds))
	ok(states.size() >= 4, "multiple states", str(states))
	var invalid_state := false
	for s in states:
		if not ["IDLE", "WALK", "SIT_IN", "SIT", "EAT", "SIT_OUT", "BED_IN", "LIE_IN", "SLEEP", "LIE_OUT", "BED_OUT"].has(String(s)):
			invalid_state = true
	ok(not invalid_state, "no invalid state")

	# ---------- 时间跳转 ----------
	print("\n== time jump ==")
	var before: Dictionary = v.call("debug_state")
	_tj += 600.0
	_sim += 600.0
	tick(1.0)
	var after: Dictionary = v.call("debug_state")
	ok(true, "jump handled (no crash)", "%s -> %s" % [before["state"], after["state"]])

	# ---------- 冻结/暂停 ----------
	print("\n== frozen ==")
	var p0: Vector3 = (v.call("debug_state")["pos"] as Vector3)
	tick(2.0, true)
	var d2: Dictionary = v.call("debug_state")
	print("    frozen state=", d2["state"], " anim_scale=", d2["anim_scale"], " pos=", _fmt(d2["pos"]))
	ok(is_equal_approx(float(d2["anim_scale"]), 0.0), "anim speed_scale=0 while frozen", str(d2["anim_scale"]))
	ok((d2["pos"] as Vector3).distance_to(p0) < 0.001, "position frozen")
	tick(1.0, false)
	var d3: Dictionary = v.call("debug_state")
	ok(not is_equal_approx(float(d3["anim_scale"]), 0.0), "resumed after unfreeze", str(d3["anim_scale"]))

	# ---------- 汇总 ----------
	print("\n[TEST] RESULT %d/%d passed, %d failed" % [passes, passes + fails.size(), fails.size()])
	for f in fails:
		print("[TEST] FAILED: ", f)
	quit(0 if fails.is_empty() else 1)