extends SceneTree
## P7-V4 岛民 × main.gd 集成探针：在真实主场景里验证创建/tick/ctx/门/暂停/跳时/自主日程。
## 运行：引擎 --headless --path 游戏工程 --script res://tools/probe_villager_integration.gd
## 自动化/无头环境；不写存档、不改用户设置；结束 quit(0/1)。

const Settings := preload("res://scripts/isle_settings.gd")

var _checks := 0
var _fails: Array = []
var _main: Node = null
var _v: Node3D = null
var _anim: AnimationPlayer = null

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _ck(name: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_fails.append(name + (" | " + detail if detail != "" else ""))
	var line := "[V4I] " + ("PASS  " if ok else "FAIL  ") + name
	if detail != "":
		line += " | " + detail
	print(line)

func _run() -> void:
	var ps: PackedScene = load("res://isle.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	await process_frame
	await process_frame

	# --- 确定性时钟/设置：固定 17:18 模拟时间，默认设置 ---
	var t0 := 17.0 * 3600.0 + 18.0 * 60.0
	_main.set("_settings", Settings.defaults())
	_main.set("_time_source", "sim")
	_main.set("_realtime", false)
	_main.set("_day_length", float(Settings.DAY_LENGTH_DEFAULT))
	_main.set("_sim_seconds", t0)
	_main.set("_events", IsleAstro.day_events(t0))
	_main.set("_mode", 1)
	_main.set("_started", true)
	_main.set("_paused", false)
	_main.set("_blending", "")
	_main.call("_apply_pose", _main.call("_play_pose"))
	_main.set_process(false)

	_v = _main.get("_villager") as Node3D
	_ck("main._build_world 创建岛民", _v != null)
	if _v == null:
		await _finish()
		return
	_anim = _v.get("anim") as AnimationPlayer
	# 探针在运行期改写了权威时间（构造时用过另一时刻），让岛民丢弃旧的“上帧时间”，避免误判为时间跳转
	_v.set("_last_sim", -1.0)

	# --- 1. 场景结构与资源 ---
	_ck("岛民挂在 World 节点下", _v.get_parent() != null and String(_v.get_parent().name) == "World")
	_ck("岛民唯一（场景中仅一个 Islander）", root.find_children("Islander", "", true, false).size() == 1)
	_ck("动画剪辑 12 个", _anim != null and _anim.get_animation_list().size() == 12,
		"list=%s" % [str(_anim.get_animation_list() if _anim != null else [])])
	var stats: Dictionary = _v.get("stats")
	_ck("模型网格预算 mesh<=16", int(stats.get("meshes", 99)) <= 16, "meshes=%d" % int(stats.get("meshes", -1)))
	_ck("模型 DC 估算 <=40", int(stats.get("dc_est", 99)) <= 40, "dc=%d" % int(stats.get("dc_est", -1)))
	_ck("模型三角面 <=7000", int(stats.get("tris", 99999)) <= 7000, "tris=%d" % int(stats.get("tris", -1)))
	_ck("身高 1.50m", absf(float(stats.get("height", 0.0)) - 1.5) < 0.01)

	# --- 2. ctx 契约 ---
	var ctx: Dictionary = _main.call("_villager_ctx")
	var need := ["sim_seconds", "sim_rate", "sim_delta", "sun_alt", "events", "time_jump", "frozen", "door_set"]
	var missing: Array = []
	for k in need:
		if not ctx.has(k):
			missing.append(k)
	_ck("ctx 字段齐全", missing.is_empty(), "missing=%s" % [str(missing)])
	_ck("PLAYING 时 frozen=false", bool(ctx.get("frozen", true)) == false)
	_ck("ctx.door_set 是 Callable", ctx.get("door_set") is Callable)
	_ck("ctx.sim_seconds 与 main 一致", absf(float(ctx.get("sim_seconds", 0.0)) - float(_main.get("_sim_seconds"))) < 1e-6)

	# --- 3. tick 驱动：强制走到 hall（真实连续移动，无瞬移） ---
	_ck("force_walk_to_node(hall) 受理", bool(_v.call("force_walk_to_node", "hall")))
	var nodes: Dictionary = _v.get("graph")["nodes"]
	var hall: Vector3 = (nodes["hall"] as Dictionary)["pos"]
	var max_step := 0.0
	var prev: Vector3 = _v.position
	var walked := false
	for i in 400:
		_main.call("_tick", 0.05)
		max_step = maxf(max_step, _v.position.distance_to(prev))
		prev = _v.position
		if String(_v.call("state_name")) != "WALK":
			walked = true
			break
	_ck("行走到 hall 结束", walked and _v.position.distance_to(hall) < 0.15,
		"pos=%s hall=%s" % [str(_v.position), str(hall)])
	_ck("单帧位移无瞬移（<=0.10m/0.05s，含节点吸附）", max_step <= 0.10, "max=%.4f" % max_step)
	_ck("到达节点记录 hall", String(_v.call("debug_state").get("at_node", "")) == "hall")

	# --- 4. 走楼梯上阁楼 ---
	_ck("force_walk_to_node(attic_exit) 受理", bool(_v.call("force_walk_to_node", "attic_exit")))
	var attic: Vector3 = (nodes["attic_exit"] as Dictionary)["pos"]
	var y_prev := _v.position.y
	var y_fall := 0.0
	var up := false
	for i in 900:
		_main.call("_tick", 0.05)
		var dy := _v.position.y - y_prev
		y_fall = minf(y_fall, dy)
		y_prev = _v.position.y
		if String(_v.call("state_name")) != "WALK":
			up = true
			break
	_ck("经楼梯到 attic_exit", up and _v.position.distance_to(attic) < 0.20,
		"pos=%s target=%s" % [str(_v.position), str(attic)])
	_ck("到达阁楼高度 y≈11.1", absf(_v.position.y - attic.y) < 0.3, "y=%.3f target=%.3f" % [_v.position.y, attic.y])
	_ck("楼梯无坠落（单帧最大下降 <=0.10m）", y_fall >= -0.10, "min_dy=%.4f" % y_fall)

	# --- 5. 坐下休息 / 进食 / 预约释放 ---
	_ck("force_sit(sofa) 受理", bool(_v.call("force_sit", "sofa")))
	var sit_ok := false
	for i in 1200:
		_main.call("_tick", 0.05)
		if String(_v.call("state_name")) == "SIT":
			sit_ok = true
			break
	var dbs: Dictionary = _v.call("debug_state")
	var spots: Dictionary = _v.get("graph")["spots"]
	var sofa: Dictionary = spots["sofa"]
	var sofa_expect: Vector3 = (sofa["anchor"] as Vector3) + Vector3(0, 0.02, 0)
	_ck("到达 SIT 且播放 sit_idle", sit_ok and String(dbs.get("clip", "")) == "sit_idle", "clip=%s" % dbs.get("clip", ""))
	_ck("坐姿 root=座面+0.02", sofa_expect.distance_to(_v.position) < 0.03,
		"pos=%s expect=%s" % [str(_v.position), str(sofa_expect)])
	_ck("坐姿朝向=座位 yaw", absf(wrapf(_v.rotation.y - float(sofa["yaw"]), -PI, PI)) < 0.05)
	_ck("座位已被预约", bool(sofa.get("reserved", false)) and ("sofa" in (dbs.get("reserved", []) as Array)))
	var released := false
	for i in 800:
		_main.call("_tick", 0.05)
		if String(_v.call("state_name")) == "IDLE" and (bool(sofa.get("reserved", false)) == false):
			released = true
			break
	_ck("活动结束释放座位（回 IDLE）", released)

	_ck("force_eat(eat_s) 受理", bool(_v.call("force_eat", "eat_s")))
	var eat_ok := false
	for i in 1200:
		_main.call("_tick", 0.05)
		if String(_v.call("state_name")) == "EAT":
			eat_ok = true
			break
	var eat_s: Dictionary = spots["eat_s"]
	var eat_clip := String(_v.call("debug_state").get("clip", ""))
	var eat_expect: Vector3 = (eat_s["anchor"] as Vector3) + Vector3(0, 0.02, 0)
	_ck("到达 EAT 且播放 eat", eat_ok and eat_clip == "eat", "clip=" + eat_clip)
	_ck("进食 root=座面+0.02", eat_expect.distance_to(_v.position) < 0.03)
	_ck("进食位已预约", bool(eat_s.get("reserved", false)))

	# --- 6. 上床睡觉 + 清晨唤醒 ---
	_ck("force_bed 受理", bool(_v.call("force_bed")))
	var sleep_ok := false
	for i in 1800:
		_main.call("_tick", 0.05)
		if String(_v.call("state_name")) == "SLEEP":
			sleep_ok = true
			break
	var bed: Dictionary = spots["bed_attic"]
	var sleep_clip := String(_v.call("debug_state").get("clip", ""))
	var bed_expect: Vector3 = (bed["anchor"] as Vector3) + Vector3(0, 0.02, 0)
	_ck("到达 SLEEP 且播放 sleep", sleep_ok and sleep_clip == "sleep", "clip=" + sleep_clip)
	_ck("躺姿 root=床垫顶+0.02", bed_expect.distance_to(_v.position) < 0.04,
		"pos=%s expect=%s" % [str(_v.position), str(bed_expect)])
	_ck("床已预约", bool(bed.get("reserved", false)))
	var sim_now := float(_main.get("_sim_seconds"))
	var ev_now: Dictionary = IsleAstro.day_events(sim_now)
	var sunrise_s := float(ev_now.get("sunrise", 360.0)) * 60.0
	var day_base: float = floor(sim_now / 86400.0) * 86400.0
	var morning: float = day_base + sunrise_s + 3600.0
	_main.set("_sim_seconds", morning)
	_main.set("_events", IsleAstro.day_events(morning))
	var woke := false
	for i in 1200:
		_main.call("_tick", 0.05)
		if String(_v.call("state_name")) == "IDLE" and (bool(bed.get("reserved", false)) == false):
			woke = true
			break
	_ck("清晨窗口自然醒来并释放床", woke, "state=%s reserved=%s" % [_v.call("state_name"), str(bed.get("reserved", false))])

	# --- 7. 门仲裁 ---
	var cottage: Dictionary = _main.get("_cottage")
	var pivot: Node3D = cottage.get("door_pivot") as Node3D
	_main.call("_set_door_state", true, true)
	await create_timer(1.25).timeout
	_ck("NPC 请求开门（静默）", bool(_main.get("_door_open")) and absf(pivot.rotation.y + 1.85) < 0.06,
		"rot=%.3f open=%s" % [pivot.rotation.y, str(_main.get("_door_open"))])
	_ck("NPC 请求标记 _door_npc", bool(_main.get("_door_npc")) and not bool(_main.get("_door_player")))
	_main.call("_toggle_door")
	await create_timer(1.25).timeout
	_ck("玩家开关门优先于 NPC 请求（关门）", (not bool(_main.get("_door_open"))) and absf(pivot.rotation.y) < 0.06,
		"rot=%.3f" % pivot.rotation.y)
	_ck("玩家操作清空 NPC 请求", not bool(_main.get("_door_npc")) and not bool(_main.get("_door_player")))
	_main.call("_toggle_door")
	await create_timer(1.25).timeout
	_ck("玩家开门生效", bool(_main.get("_door_open")))
	_main.call("_set_door_state", false, true)
	await create_timer(1.25).timeout
	_ck("NPC 关门请求不覆盖玩家开门", bool(_main.get("_door_open")), "open=%s" % str(_main.get("_door_open")))
	_main.call("_set_door_state", false, false)
	await create_timer(1.25).timeout
	_ck("玩家关闭请求生效", not bool(_main.get("_door_open")))

	# --- 8. 暂停 / 菜单冻结 ---
	_main.set("_paused", true)
	var sim_before := float(_main.get("_sim_seconds"))
	var pos_before: Vector3 = _v.position
	for i in 12:
		_main.call("_tick", 0.05)
	_ck("暂停时动画冻结（speed_scale=0）", is_equal_approx(_anim.speed_scale, 0.0), "scale=%.3f" % _anim.speed_scale)
	_ck("暂停时位置冻结", _v.position.distance_to(pos_before) < 1e-5)
	_ck("暂停时模拟时间不推进", absf(float(_main.get("_sim_seconds")) - sim_before) < 1e-6)
	_main.set("_paused", false)
	_main.call("_tick", 0.05)
	_ck("恢复后动画继续", _anim.speed_scale > 0.0, "scale=%.3f" % _anim.speed_scale)
	_main.set("_mode", 0)
	_main.call("_tick", 0.05)
	_ck("标题/转场态冻结岛民", is_equal_approx(_anim.speed_scale, 0.0))
	_main.set("_mode", 1)
	_main.call("_tick", 0.05)

	# --- 9. 时间跳转：检测、后跳、不瞬移 ---
	_v.call("force_idle", 2.0)
	_main.call("_tick", 0.05)
	var sch0: Dictionary = _v.get("schedule").call("debug_state")
	var jumps0 := int(sch0.get("jumps", 0))
	var p_jump: Vector3 = _v.position
	var s_now := float(_main.get("_sim_seconds"))
	_main.set("_sim_seconds", s_now + 3600.0)
	_main.set("_events", IsleAstro.day_events(s_now + 3600.0))
	_main.call("_tick", 0.05)
	var sch1: Dictionary = _v.get("schedule").call("debug_state")
	_ck("前跳 1 小时被检测", int(sch1.get("jumps", 0)) == jumps0 + 1, "jumps=%d->%d" % [jumps0, int(sch1.get("jumps", 0))])
	_ck("跳转不瞬移角色", _v.position.distance_to(p_jump) < 0.30, "d=%.3f" % _v.position.distance_to(p_jump))
	var st_after := String(_v.call("state_name"))
	_ck("跳转后状态合法", st_after in ["IDLE", "WALK", "SIT_IN", "SIT", "EAT", "SIT_OUT", "BED_IN", "LIE_IN", "SLEEP", "LIE_OUT", "BED_OUT"], "state=" + st_after)
	_main.set("_sim_seconds", s_now - 3600.0)
	_main.set("_events", IsleAstro.day_events(s_now - 3600.0))
	_main.call("_tick", 0.05)
	var sch2: Dictionary = _v.get("schedule").call("debug_state")
	_ck("后跳 1 小时被检测", int(sch2.get("jumps", 0)) == jumps0 + 2, "jumps=%d" % int(sch2.get("jumps", 0)))

	# --- 10. 自主日程连续运行（状态/边界/预约；含调试读取，成本另测） ---
	_v.call("clear_force")
	_v.set("_last_sim", -1.0)
	var ctx2: Dictionary = _main.call("_villager_ctx")
	var sim_base := float(ctx2.get("sim_seconds", 0.0))
	var rate := maxf(float(ctx2.get("sim_rate", 144.0)), 0.001)
	var states_seen := {}
	var kinds_seen := {}
	var max_reserved := 0
	var bad_pos := ""
	var bad_nan := ""
	var max_seg := 0.0
	var pos_last: Vector3 = _v.position
	var steps := 7200
	var dt_step := 0.016
	var dbg := "--probe-verbose" in OS.get_cmdline_user_args() or "--probe-verbose" in OS.get_cmdline_args()
	_v.set("debug_log", dbg)
	var last_sig := ""
	var max_info := ""
	for i in steps:
		ctx2["sim_seconds"] = sim_base + float(i) * dt_step * rate
		ctx2["sim_delta"] = dt_step * rate
		_v.call("sim_tick", dt_step, ctx2)
		var d: Dictionary = _v.call("debug_state")
		states_seen[String(d.get("state", ""))] = true
		var k := String(d.get("kind", ""))
		if k != "":
			kinds_seen[k] = true
		max_reserved = maxi(max_reserved, (d.get("reserved", []) as Array).size())
		var p: Vector3 = _v.position
		if is_nan(p.x) or is_nan(p.y) or is_nan(p.z):
			bad_nan = "t=%d" % i
		if p.y < 7.0 or p.y > 12.5:
			bad_pos = "y=%.2f t=%d" % [p.y, i]
		var seg := p.distance_to(pos_last)
		if seg > max_seg:
			max_seg = seg
			max_info = "t=%d seg=%.3f state=%s kind=%s window=%s idle=%s at=%s from=%s to=%s" % [i, seg, String(d.get("state", "")), k, String(d.get("window", "")), String(d.get("idle_mode", "")), String(d.get("at_node", "")), str(pos_last), str(p)]
		if dbg:
			var sig := "%s|%s|%s" % [String(d.get("state", "")), k, String(d.get("idle_mode", ""))]
			if sig != last_sig:
				last_sig = sig
				print("[V4I-D] t=%d sim=%.0f %s pos=%s reserved=%s" % [i, float(d.get("sim_seconds", 0.0)), sig, str(p), str(d.get("reserved", []))])
		pos_last = p
	_ck("自主运行状态覆盖 >=3 种", states_seen.size() >= 3, "states=%s" % [str(states_seen.keys())])
	_ck("自主运行活动种类 >=2 种", kinds_seen.size() >= 2, "kinds=%s" % [str(kinds_seen.keys())])
	_ck("任何时刻预约数 <=1", max_reserved <= 1, "max=%d" % max_reserved)
	_ck("位置无 NaN", bad_nan == "", bad_nan)
	_ck("位置始终在小屋/岛屿高度范围", bad_pos == "", bad_pos)
	_ck("单帧位移无瞬移（<=0.10m）", max_seg <= 0.10, "max=%.4f %s" % [max_seg, max_info])

	# 纯调度成本（不读 debug_state）：1200 次 sim_tick 平均耗时
	var ctx3: Dictionary = _main.call("_villager_ctx")
	var sim_b3 := float(ctx3.get("sim_seconds", 0.0))
	var t_perf := Time.get_ticks_usec()
	for i in 1200:
		ctx3["sim_seconds"] = sim_b3 + float(i) * 0.016 * rate
		ctx3["sim_delta"] = 0.016 * rate
		_v.call("sim_tick", 0.016, ctx3)
	var avg_us := float(Time.get_ticks_usec() - t_perf) / 1200.0
	_ck("岛民每帧调度成本 <0.3ms", avg_us < 300.0, "avg=%.1fus" % avg_us)

	# --- 11. 模型/动画资源运行期不重建 ---
	var mesh_a := int((_v.get("stats") as Dictionary).get("meshes", 0))
	var clips_a := _anim.get_animation_list().size()
	var child_a := _v.get_child_count()
	for i in 30:
		_main.call("_tick", 0.05)
	_ck("运行期网格数不变", int((_v.get("stats") as Dictionary).get("meshes", 0)) == mesh_a)
	_ck("运行期动画剪辑不变", _anim.get_animation_list().size() == clips_a)
	_ck("运行期子节点数不变", _v.get_child_count() == child_a)
	_ck("岛民 sim_seconds 与 main 同步", absf(float(_v.call("debug_state").get("sim_seconds", -1.0)) - float(_main.get("_sim_seconds"))) < 1e-6)

	# --- 12. 时间倍率/时间来源/暂停/菜单转场稳定性（P7-V4 验收项 10-13） ---
	var dl_save := float(_main.get("_day_length"))
	var ts_save := String(_main.get("_time_source"))
	var rt_save := bool(_main.get("_realtime"))
	var paused_save := bool(_main.get("_paused"))
	var mode_save := int(_main.get("_mode"))
	var legal_states := ["IDLE", "WALK", "SIT_IN", "SIT", "EAT", "SIT_OUT", "BED_IN", "LIE_IN", "SLEEP", "LIE_OUT", "BED_OUT"]
	# 12a 最快模拟日长（day_length=60s → 1440x 模拟速率）
	_main.set("_time_source", "sim")
	_main.set("_realtime", false)
	_main.set("_paused", false)
	_main.set("_mode", 1)
	_main.set("_day_length", 60.0)
	_v.call("clear_force")
	_v.set("_last_sim", -1.0)
	var fast_changes := 0
	var fast_states := {}
	var prev_st := String(_v.call("state_name"))
	for i in 900:
		_main.call("_tick", 0.016)
		var st := String(_v.call("state_name"))
		fast_states[st] = true
		if st != prev_st:
			fast_changes += 1
			prev_st = st
	_ck("最快日长(60s)状态合法", fast_states.keys().size() > 0 and not fast_states.has(""), "states=%s" % [str(fast_states.keys())])
	_ck("最快日长 14.4s 内切换不闪烁（<=40）", fast_changes <= 40, "changes=%d" % fast_changes)
	# 12b 最慢模拟日长（day_length=3600s → 24x）
	_main.set("_day_length", 3600.0)
	_v.set("_last_sim", -1.0)
	var slow_changes := 0
	var slow_st := String(_v.call("state_name"))
	for i in 900:
		_main.call("_tick", 0.016)
		var st2 := String(_v.call("state_name"))
		if st2 != slow_st:
			slow_changes += 1
			slow_st = st2
	_ck("最慢日长(3600s)行程稳定（切换 <=8）", slow_changes <= 8, "changes=%d" % slow_changes)
	# 12c 现实时间来源：岛民只消费 main 注入时间，不误判跳时
	_main.set("_day_length", float(dl_save))
	_main.set("_time_source", "real")
	_main.set("_realtime", true)
	_v.set("_last_sim", -1.0)
	_main.call("_tick", 0.016)
	var jumps_r0 := int((_v.get("schedule").call("debug_state") as Dictionary).get("jumps", 0))
	var real_ok := true
	for i in 180:
		_main.call("_tick", 0.016)
		if not (String(_v.call("state_name")) in legal_states):
			real_ok = false
	var jumps_r1 := int((_v.get("schedule").call("debug_state") as Dictionary).get("jumps", 0))
	_ck("现实时间模式状态合法", real_ok, "state=" + String(_v.call("state_name")))
	_ck("现实时间模式不误判跳时", jumps_r1 == jumps_r0, "jumps=%d->%d" % [jumps_r0, jumps_r1])
	# 12d 暂停：位置与动画冻结
	_main.set("_time_source", "sim")
	_main.set("_realtime", false)
	_main.set("_paused", true)
	_v.set("_last_sim", -1.0)
	_main.call("_tick", 0.016)
	var p_pause: Vector3 = _v.position
	var cp_pause := _anim.current_animation_position
	for i in 60:
		_main.call("_tick", 0.016)
	_ck("暂停时位置冻结", _v.position.distance_to(p_pause) < 1e-4, "d=%.5f" % _v.position.distance_to(p_pause))
	_ck("暂停时动画冻结", absf(_anim.current_animation_position - cp_pause) < 1e-4, "cp=%.4f->%.4f" % [cp_pause, _anim.current_animation_position])
	# 12e 恢复后继续推进
	_main.set("_paused", false)
	var resume_ok := false
	for i in 120:
		_main.call("_tick", 0.016)
		if String(_v.call("state_name")) in legal_states:
			resume_ok = true
	_ck("暂停恢复后状态可继续推进", resume_ok, "state=" + String(_v.call("state_name")))
	# 12f 菜单转场：冻结且无重复动画实例/预约泄漏
	var p_menu: Vector3 = _v.position
	var anim_count0 := root.find_children("Anim", "", true, false).size()
	_main.set("_mode", 0)
	_v.set("_last_sim", -1.0)
	for i in 30:
		_main.call("_tick", 0.016)
	_ck("菜单模式位置冻结", _v.position.distance_to(p_menu) < 1e-4)
	_ck("菜单模式无重复动画实例", root.find_children("Anim", "", true, false).size() == anim_count0)
	_main.set("_mode", 1)
	_main.set("_paused", false)
	for i in 60:
		_main.call("_tick", 0.016)
	_ck("菜单返回后状态合法", String(_v.call("state_name")) in legal_states, "state=" + String(_v.call("state_name")))
	_ck("菜单返回后预约数 <=1", (_v.call("debug_state").get("reserved", []) as Array).size() <= 1)
	_main.set("_day_length", float(dl_save))
	_main.set("_time_source", ts_save)
	_main.set("_realtime", rt_save)
	_main.set("_paused", paused_save)
	_main.set("_mode", mode_save)

	await _finish()

func _finish() -> void:
	print("[V4I] RESULT %d/%d passed" % [_checks - _fails.size(), _checks])
	if not _fails.is_empty():
		print("[V4I] FAILED: %s" % [str(_fails)])
	if _main != null:
		_main.queue_free()
		_main = null
	await process_frame
	quit(0 if _fails.is_empty() else 1)
