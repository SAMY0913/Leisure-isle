extends SceneTree
## T1 生命周期诊断探针：
##   <godot_console.exe> --headless --path D:/休闲小岛幻境/游戏工程 --script res://tools/probe_exit_diag_t7.gd
##   <godot_console.exe> --headless --path D:/休闲小岛幻境/游戏工程 --script res://tools/probe_exit_diag_t7.gd -- --audio-probe [--audio-cleanup]
## 模式 A（默认）：用真实的 Splash / Ripples 池验证"游离复用单元"退出泄漏；
## 模式 B（--audio-probe）：用真实 WAV + 4 条命名总线复现音频退出泄漏（AudioStreamWAV / AudioStreamPlaybackWAV /
##   Orphan StringName IsleAmbient…），并可用 --audio-cleanup 验证"停播放器 + 清 stream + 删总线"能否消除。
## 输出 [DIAG] 行；退出码 0 = 探针跑完（观察日志而非断言）。本探针只读运行，不改工程状态、不改玩法、不删断言。

const Fx := preload("res://scripts/fx.gd")
const DT := 1.0 / 60.0
const RETIRE_FRAMES := 200   # > 涟漪 2.6s 寿命，确保退役

const AUDIO_BUSES: Array[String] = ["IsleAmbient", "IsleBirds", "IsleFire", "IsleSFX"]
const AUDIO_FILES: Array[String] = ["ocean_loop.wav", "wind_loop.wav", "night_loop.wav", "fire_crackle.wav"]
const AUDIO_FRAMES := 90

var _splash: Node3D
var _ripples: Node3D
var _orphan_base := 0
var _node_base := 0

func _initialize() -> void:
	print("=== T1 EXIT DIAG PROBE START ===")
	var args := OS.get_cmdline_user_args()
	if args.has("--audio-probe"):
		await _run_audio_probe(args)
		return
	await _run_fx_probe()

func _run_audio_probe(args: Array) -> void:
	var cleanup := args.has("--audio-cleanup")
	var players: Array[AudioStreamPlayer] = []
	# 1) 与 isle_audio._ensure_bus/_ensure_buses 相同的 4 条命名总线 + 简单效果链
	var created: Array[int] = []
	for bus_name in AUDIO_BUSES:
		var idx := AudioServer.get_bus_index(bus_name)
		if idx < 0:
			AudioServer.add_bus()
			idx = AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			created.append(idx)
		AudioServer.set_bus_send(idx, "Master")
		var eq := AudioEffectEQ6.new()
		eq.set_band_gain_db(0, -1.0)
		AudioServer.add_bus_effect(idx, eq)
	print("[DIAG][audio] buses=", AUDIO_BUSES, " created=", created, " cleanup=", cleanup)
	# 2) 4 个播放器，真实 WAV 复制后循环播放（与 isle_audio 相同：stream=duplicate(true)）
	var parent := Node.new()
	parent.name = "DiagAudioParent"
	root.add_child(parent)
	for i in range(AUDIO_FILES.size()):
		var st := load("res://audio/" + AUDIO_FILES[i]) as AudioStream
		if st == null:
			print("[DIAG][audio] MISSING res://audio/", AUDIO_FILES[i])
			continue
		var dup: AudioStream = st.duplicate(true) as AudioStream
		if dup is AudioStreamWAV:
			(dup as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		var p := AudioStreamPlayer.new()
		p.name = "DiagPlayer%d" % i
		p.bus = AUDIO_BUSES[i] if i < AUDIO_BUSES.size() else "IsleAmbient"
		p.stream = dup
		parent.add_child(p)
		p.play()
		players.append(p)
	await process_frame
	print("[DIAG][audio] playing=", players.size(), " bus_names=", _bus_name_list())
	for i in AUDIO_FRAMES:
		await process_frame
	var playing := 0
	for p in players:
		if p.playing:
			playing += 1
	print("[DIAG][audio] after_frames playing=", playing, " orphan=", _orphan_now())
	if cleanup:
		for p in players:
			if is_instance_valid(p):
				p.stop()
				p.stream = null
		await process_frame
		for idx in range(AudioServer.bus_count - 1, -1, -1):
			var nm := AudioServer.get_bus_name(idx)
			if AUDIO_BUSES.has(nm):
				for e in range(AudioServer.get_bus_effect_count(idx) - 1, -1, -1):
					AudioServer.remove_bus_effect(idx, e)
				AudioServer.remove_bus(idx)
		await process_frame
		print("[DIAG][audio] after_cleanup bus_names=", _bus_name_list(), " playing=", _playing_count(players))
	else:
		print("[DIAG][audio] no_cleanup (leave players playing + buses alive, engine shutdown is the test)")
	print("[DIAG][audio] DONE")
	quit(0)

func _playing_count(players: Array[AudioStreamPlayer]) -> int:
	var n := 0
	for p in players:
		if is_instance_valid(p) and p.playing:
			n += 1
	return n

func _bus_name_list() -> Array[String]:
	var out: Array[String] = []
	for i in range(AudioServer.bus_count):
		if not out.has(AudioServer.get_bus_name(i)):
			out.append(AudioServer.get_bus_name(i))
	return out

func _run_fx_probe() -> void:
	await process_frame
	_orphan_base = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_node_base = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	print("[DIAG] baseline orphan=", _orphan_base, " nodes=", _node_base)

	_splash = Fx.Splash.new()
	_splash.name = "DiagSplash"
	root.add_child(_splash)
	_ripples = Fx.Ripples.new()
	_ripples.name = "DiagRipples"
	root.add_child(_ripples)
	await process_frame
	print("[DIAG] pools ready orphan=", _orphan_now(), " splash_state=", _splash.get_state_counts(), " ripples_state=", _ripples.get_state_counts())

	_splash.splash_at(Vector3(0.0, 0.0, 0.0), 1.2)
	_ripples.ripple_at(Vector3(1.0, 0.0, 1.0), 1.0)
	await process_frame
	print("[DIAG] spawned orphan=", _orphan_now(), " splash_children=", _splash.get_child_count(), " ripples_children=", _ripples.get_child_count(), " splash_state=", _splash.get_state_counts(), " ripples_state=", _ripples.get_state_counts())

	for i in RETIRE_FRAMES:
		await process_frame
		_splash.update(DT)
		_ripples.update(DT, 12.0)
	var orphan_retired := _orphan_now()
	print("[DIAG] after_retire orphan=", orphan_retired, " delta=", orphan_retired - _orphan_base,
		" splash_children=", _splash.get_child_count(), " ripples_children=", _ripples.get_child_count(),
		" splash_state=", _splash.get_state_counts(), " ripples_state=", _ripples.get_state_counts())
	var free_splash: Array = _splash.get("_free")
	var free_ripples: Array = _ripples.get("_free")
	print("[DIAG] detached_pool_free_units splash=", free_splash.size(), " ripples=", free_ripples.size())

	# 模拟场景树退出：池节点被销毁（其游离单元若未被钩子释放，将残留为 ObjectDB 泄漏）
	_splash.free()
	_ripples.free()
	await process_frame
	var orphan_after_free := _orphan_now()
	print("[DIAG] after_pool_free orphan=", orphan_after_free, " delta_vs_baseline=", orphan_after_free - _orphan_base)

	print("[DIAG] DONE (quit: engine exit 诊断将打印在下方)")
	quit(0)

func _orphan_now() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
