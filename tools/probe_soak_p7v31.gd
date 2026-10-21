extends SceneTree
## P7-V3.1 长时间运行（soak）探针（窗口模式）
##
## 目的：连续运行 12 分钟，期间周期性做真实交互（自由视角进出、菜单开关、画质上下档、
##       FOV 调整、自动运镜、时间推进），观察是否存在：
##         * FPS / 帧时间持续恶化
##         * objects / draw_calls 异常增长
##         * 节点/资源/ObjectDB 计数持续增长（泄漏迹象）
##         * 猫咪待机动画卡死
##         * 退出期 ObjectDB / RID 告警
##
## 结论口径（写报告时必须照抄）：本探针只能给出「本次 soak 未发现明显异常」，
## **不能**据此宣称不存在内存泄漏。
##
## 运行：
##   ENG --path <PROJ> --resolution 1600x900 --script res://tools/probe_soak_p7v31.gd -- --minutes=12

var _minutes := 12.0
var _samples: Array = []

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--minutes="):
			_minutes = maxf(1.0, float(s.substr(10)))

	await process_frame
	var packed: PackedScene = load("res://isle.tscn") as PackedScene
	var main: Node = packed.instantiate()
	get_root().add_child(main)
	await process_frame
	await process_frame
	var menu = main.get("_menu")
	if menu != null and menu.has_method("instant_finish"):
		menu.call("instant_finish")
	# 直接进入游玩态（不等过场）
	main.set("_mode", 1)
	main.set("_time_source", "sim")
	main.set("_realtime", false)
	main.set("_started", true)
	main.set("_paused", false)
	main.set("_auto_orbit", true)
	main.set("_blending", "")
	main.set("_sim_seconds", 0.0)
	await process_frame
	main.call("_set_time_of_day", 780.0)
	main.call("_update_lighting")
	await process_frame

	var cat: Node = _find_named(get_root(), "PorchCat")
	var drv: Node = cat.get_node_or_null("CatIdleDriver") if cat != null else null
	var ctl = drv.get("controller") if drv != null else null

	print("[SOAK] begin minutes=%.1f  quality=%s" % [_minutes, str(main.get("_quality"))])
	var total := int(_minutes * 60.0)
	var tick := 0
	var t0 := Time.get_ticks_msec()
	var fps_hist: Array = []
	var cycle := 0
	while tick < total:
		await create_timer(10.0).timeout
		tick += 10
		# 每 60 秒做一轮真实交互
		if tick % 60 == 0:
			cycle += 1
			await _cycle(main, cycle)
		# 采样
		var s := {
			"t": tick,
			"fps": Engine.get_frames_per_second(),
			"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			"orphan": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
			"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
			"dc": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			"vram": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
			"objcount": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
			"rescount": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
			"mem_static": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
			"cat_t": -1.0,
		}
		if ctl != null:
			var st: Dictionary = ctl.call("debug_state") if ctl.has_method("debug_state") else {}
			s["cat_t"] = float(st.get("t", -1.0))
		_samples.append(s)
		fps_hist.append(int(s["fps"]))
		print("[SOAK] t=%3ds fps=%3d dc=%4d objects=%4d nodes=%4d orphan=%2d vram=%.1f res=%d mem=%.1f cat_t=%.2f" % [
			tick, int(s["fps"]), int(s["dc"]), int(s["objects"]), int(s["nodes"]),
			int(s["orphan"]), float(s["vram"]), int(s["rescount"]), float(s["mem_static"]),
			float(s["cat_t"])])

	var secs := float(Time.get_ticks_msec() - t0) / 1000.0
	_report(secs)
	await process_frame
	quit(0)

## 一轮真实交互：自由视角进/出、菜单开/关、画质上下档、FOV、自动运镜、时间推进
func _cycle(main: Node, n: int) -> void:
	var step := n % 4
	match step:
		0:
			main.call("_enter_flycam")
			await create_timer(2.0).timeout
			main.call("_exit_flycam")
			await create_timer(1.5).timeout
		1:
			main.call("_open_menu")
			await create_timer(2.0).timeout
			var menu = main.get("_menu")
			var done := [false]
			if menu != null and menu.has_method("close"):
				menu.call("close", func(): done[0] = true)
			await create_timer(2.0).timeout
			if menu != null and menu.has_method("instant_finish"):
				menu.call("instant_finish")
			main.call("_enter_playing")
			await create_timer(1.0).timeout
		2:
			# 画质上下档（会重建大量材质/参数）
			for q in [3, 1, 2]:
				main.call("_apply_quality", q)
				await create_timer(1.2).timeout
		3:
			# FOV 变化 + 自动运镜切换 + 时间推进
			main.set("_fov", 65.0)
			await create_timer(1.0).timeout
			main.set("_fov", 42.0)
			main.call("_toggle_auto_orbit")
			await create_timer(0.8).timeout
			main.call("_toggle_auto_orbit")
			var t: float = float(main.get("_sim_seconds")) + 3600.0
			main.set("_sim_seconds", t)
			main.call("_set_time_of_day", 1250.0)
			await create_timer(1.2).timeout
	print("[SOAK] cycle=%d done (step=%d)" % [n, step])

func _report(secs: float) -> void:
	if _samples.is_empty():
		print("[SOAK] RESULT no_samples")
		return
	var first: Dictionary = _samples[0]
	var last: Dictionary = _samples[_samples.size() - 1]
	var mid: Dictionary = _samples[int(_samples.size() / 2)]
	var fps_all: Array = []
	var fps_tail: Array = []
	for i in range(_samples.size()):
		fps_all.append(int((_samples[i] as Dictionary)["fps"]))
		if i >= _samples.size() - 6:
			fps_tail.append(int((_samples[i] as Dictionary)["fps"]))
	fps_all.sort()
	fps_tail.sort()
	var med_all: float = float(fps_all[int(fps_all.size() / 2)])
	var med_tail: float = float(fps_tail[int(fps_tail.size() / 2)]) if fps_tail.size() > 0 else med_all

	print("[SOAK] ---- summary ----")
	print("[SOAK] wall_seconds=%.0f samples=%d" % [secs, _samples.size()])
	print("[SOAK] fps median(all)=%.0f median(last6)=%.0f" % [med_all, med_tail])
	print("[SOAK] fps first=%d mid=%d last=%d" % [int(first["fps"]), int(mid["fps"]), int(last["fps"])])
	print("[SOAK] nodes %d -> %d (%+d)" % [int(first["nodes"]), int(last["nodes"]), int(last["nodes"]) - int(first["nodes"])])
	print("[SOAK] orphan %d -> %d (%+d)" % [int(first["orphan"]), int(last["orphan"]), int(last["orphan"]) - int(first["orphan"])])
	print("[SOAK] objects %d -> %d (%+d)" % [int(first["objects"]), int(last["objects"]), int(last["objects"]) - int(first["objects"])])
	print("[SOAK] draw_calls %d -> %d (%+d)" % [int(first["dc"]), int(last["dc"]), int(last["dc"]) - int(first["dc"])])
	print("[SOAK] vram_mb %.1f -> %.1f (%+.1f)" % [float(first["vram"]), float(last["vram"]), float(last["vram"]) - float(first["vram"])])
	print("[SOAK] resource_count %d -> %d (%+d)" % [int(first["rescount"]), int(last["rescount"]), int(last["rescount"]) - int(first["rescount"])])
	print("[SOAK] memory_static_mb %.1f -> %.1f (%+.1f)" % [float(first["mem_static"]), float(last["mem_static"]), float(last["mem_static"]) - float(first["mem_static"])])
	# 猫咪待机动画是否仍在推进
	var cat_ok := float(last["cat_t"]) > float(first["cat_t"]) + 1.0
	print("[SOAK] cat_idle_t %.2f -> %.2f (%s)" % [float(first["cat_t"]), float(last["cat_t"]), "advancing" if cat_ok else "STALLED?"])
	print("[SOAK] RESULT done")
	print("[SOAK] NOTE 本探针只能给出「本次 soak 未发现明显异常」，不能据此宣称不存在内存泄漏。")

func _find_named(n: Node, nm: String) -> Node:
	if String(n.name) == nm:
		return n
	for c in n.get_children():
		var r := _find_named(c, nm)
		if r != null:
			return r
	return null
