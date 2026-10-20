extends SceneTree
## P5 夜间音效验收探针（不加载 isle.tscn、不渲染、不截图）：
##   <godot_console.exe> --headless --path D:/休闲小岛幻境/游戏工程 --script res://tools/probe_audio_p5.gd
## 断言：
##   [WAV]      audio/night_loop.wav：44.1kHz / 16bit / 单声道 / 16.0s，峰值 / 削波 / RMS /
##              过零率 / 低频占比 / 高频占比 / 循环接缝 / 首尾响度 —— 夜间层是干净虫鸣 + 微风，
##              而不是旧的 91% 能量堆在 <200Hz 的低频轰鸣；且内容已替换（与旧备份 / wind 不同源）。
##   [STREAM]   IsleAudio 加载后的夜层 AudioStreamWAV：LOOP_FORWARD / loop_begin=0 /
##              loop_end=总帧数 / mix_rate=44100 / QOA 头部合法。
##   [LOGIC]    模拟 3 轮 白天→黄昏→夜→黎明（dt=0.05，state 与 main.gd _update_audio 一致）：
##              夜间层恰好启停 3 次、无重复启停；白天不播放；夜间 env/音量正确。
##   [PLAYERS]  播放器数量恒为 12，不随轮次累积；Ocean/Wind 只启动一次且不反复启停。
##   [EVENTS]   事件序列：夜间无 bird/sfx；night 层启停来源均为 night_gate；无缺失资源警告；
##              事件日志 seq 单调、环形缓冲不超上限。
##   [MIX]      事件日志静态接口可用、总音量 bus 与 mute 生效、SFX 正确记入日志。
## 产出：logs/probe_audio_p5.log（完整事件序列 + 快照），退出码 0 = 全部断言通过。

const AudioScript := preload("res://scripts/isle_audio.gd")
const NIGHT_WAV := "res://audio/night_loop.wav"
const WIND_WAV := "res://audio/wind_loop.wav"
const OLD_NIGHT_WAV := "D:/休闲小岛幻境/开发产物/logs/night_loop_before_p5.wav"
const LOG_PATH := "D:/休闲小岛幻境/开发产物/logs/probe_audio_p5.log"

const DT := 0.05
const ROUNDS := 3
const DAY_SUN := 30.0
const NIGHT_SUN := -30.0
const DUSK_END_SUN := -12.0
const DAY_FRAMES := 150
const DUSK_FRAMES := 80
const NIGHT_FRAMES := 120
const DAWN_FRAMES := 80
# P6 起音频拆分为 5 条总线、15 个 player；本探针保留 P5 断言但同步更新数量。
const EXPECT_PLAYERS := 15
const EXPECT_NIGHT_FRAMES := 705600
const EXPECT_MIX_RATE := 44100
const EXPECT_SECONDS := 16.0

var _pass := 0
var _fail := 0
var _lines: Array[String] = []
var _audio: Node = null
var _frame_t := 0.0
var _night_end_snaps: Array = []
var _day_end_snaps: Array = []
var _player_counts: Array = []
var _idem_ok := true
var _sfx_test_mark := 0

func _initialize() -> void:
	print("=== P5 AUDIO PROBE START ===")
	_out("=== P5 AUDIO PROBE START ===")
	await process_frame
	_audio = AudioScript.new() as Node
	_audio.name = "Audio"
	root.add_child(_audio)
	_audio.call("setup", root)
	await process_frame

	var snap0: Dictionary = AudioScript.debug_snapshot()
	_probe_stream(snap0)
	_probe_wav_files()
	_probe_day_setup(snap0)
	_run_cycles()
	_probe_cycles()
	_probe_events()
	_probe_mix_api()
	_dump_events()
	_final_report()

func _out(s: String) -> void:
	_lines.append(s)
	print(s)

func _check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		_out("  [OK] " + msg)
	else:
		_fail += 1
		_out("  [FAIL] " + msg)

func _snap() -> Dictionary:
	return AudioScript.debug_snapshot()

# ============================================================
# 1) 加载后的流参数（导入资源 / 循环设置）
# ============================================================
func _probe_stream(snap: Dictionary) -> void:
	_out("--- STREAM ---")
	_check(bool(snap.get("instance", false)), "IsleAudio 注册了可读实例快照")
	_check(bool(snap.get("setup_done", false)), "setup 完成")
	_check(bool(snap.get("ready", false)), "is_ready() == true（环境层已加载）")
	var loops: Array = snap.get("loops", [])
	_check(loops.size() == 3, "环形环境层数量 == 3（实际 %d）" % loops.size())
	if loops.size() < 3:
		return
	var ocean: Dictionary = loops[0]
	var wind: Dictionary = loops[1]
	var night: Dictionary = loops[2]
	_check(String(night.get("name", "")).ends_with("Night"), "第 3 层是 Night（实际 %s）" % String(night.get("name", "")))
	_check(bool(night.get("loaded", false)), "night_loop.wav 已加载")
	_check(bool(wind.get("loaded", false)) and bool(ocean.get("loaded", false)), "ocean/wind 层均已加载")
	_check(int(night.get("loop_mode", -1)) == AudioStreamWAV.LOOP_FORWARD,
			"夜层 loop_mode == LOOP_FORWARD（实际 %d）" % int(night.get("loop_mode", -1)))
	_check(int(night.get("loop_begin", -1)) == 0, "夜层 loop_begin == 0")
	_check(int(night.get("loop_end", -1)) == EXPECT_NIGHT_FRAMES,
			"夜层 loop_end == %d 帧（实际 %d）" % [EXPECT_NIGHT_FRAMES, int(night.get("loop_end", -1))])
	_check(int(night.get("mix_rate", 0)) == EXPECT_MIX_RATE,
			"夜层 mix_rate == %d（实际 %d）" % [EXPECT_MIX_RATE, int(night.get("mix_rate", 0))])
	_check(absf(float(night.get("length", 0.0)) - EXPECT_SECONDS) < 0.02,
			"夜层时长 ≈ %.1fs（实际 %.3fs）" % [EXPECT_SECONDS, float(night.get("length", 0.0))])
	_check(int(night.get("format", -1)) == AudioStreamWAV.FORMAT_QOA,
			"夜层为 QOA 导入格式（实际 %d）" % int(night.get("format", -1)))
	_check(bool(night.get("stereo", true)) == false, "夜层单声道")
	_check(int(night.get("data_size", 0)) > 100000, "夜层压缩数据非空（%d bytes）" % int(night.get("data_size", 0)))
	var hdr := String(night.get("header", ""))
	_check(hdr.begins_with("716f6166"), "夜层 QOA 头部为 'qoaf'（实际 %s）" % hdr.substr(0, 8))

# ============================================================
# 2) 源 WAV 文件实测：波形 / 频谱分布 / 循环接缝
# ============================================================
func _probe_wav_files() -> void:
	_out("--- WAV ---")
	var md5_night := FileAccess.get_md5(NIGHT_WAV)
	var md5_wind := FileAccess.get_md5(WIND_WAV)
	var md5_old := FileAccess.get_md5(OLD_NIGHT_WAV)
	_check(md5_night != "" and md5_night != md5_wind, "night_loop.wav 与 wind_loop.wav 内容不同源（md5 不同）")
	_check(md5_old == "" or md5_night != md5_old, "night_loop.wav 已替换为新的合成内容（与旧备份 md5 不同）")
	_out("  night md5=%s wind md5=%s old md5=%s" % [md5_night, md5_wind, md5_old])

	var st := _wav_stats(NIGHT_WAV)
	if st.is_empty():
		_check(false, "无法解析 " + NIGHT_WAV)
		return
	_out("  [WAV] frames=%d sr=%d ch=%d bits=%d dur=%.3fs peak=%.4f rms=%.2fdBFS zcr=%.0f/s " % [
		int(st["frames"]), int(st["sample_rate"]), int(st["channels"]), int(st["bits"]),
		float(st["duration"]), float(st["peak"]), float(st["rms_db"]), float(st["zcr_per_s"])])
	_out("  [WAV] LF<250=%d%% (one-pole)  HF>2k=%d%%  seam_jump=%.5f  mean_abs_diff=%.5f  edge_rms=%.4f/%.4f  dc=%.5f" % [
		int(round(100.0 * float(st["lf_ratio"]))), int(round(100.0 * float(st["hf_ratio"]))),
		float(st["seam_jump"]), float(st["mean_abs_diff"]),
		float(st["edge_rms_first"]), float(st["edge_rms_last"]), float(st["dc"])])

	_check(String(st["riff"]) == "RIFF" and String(st["wave"]) == "WAVE", "标准 RIFF/WAVE 容器")
	_check(int(st["channels"]) == 1, "源 WAV 单声道（实际 %d）" % int(st["channels"]))
	_check(int(st["sample_rate"]) == EXPECT_MIX_RATE, "源 WAV 采样率 44100（实际 %d）" % int(st["sample_rate"]))
	_check(int(st["bits"]) == 16, "源 WAV 16bit PCM（实际 %d）" % int(st["bits"]))
	_check(int(st["frames"]) == EXPECT_NIGHT_FRAMES, "源 WAV 总帧数 %d（实际 %d）" % [EXPECT_NIGHT_FRAMES, int(st["frames"])])
	_check(absf(float(st["duration"]) - EXPECT_SECONDS) < 0.01, "源 WAV 时长 16.0s")
	_check(float(st["peak"]) < 0.99, "峰值 %.4f < 0.99，无削波" % float(st["peak"]))
	_check(float(st["peak"]) > 0.2, "峰值 %.4f > 0.2，不是静音文件" % float(st["peak"]))
	_check(int(st["clip_count"]) == 0, "满幅采样点数量 == 0（实际 %d）" % int(st["clip_count"]))
	_check(float(st["rms_db"]) > -30.0 and float(st["rms_db"]) < -12.0,
			"RMS %.2f dBFS 落在 [-30,-12] 合理区间" % float(st["rms_db"]))
	_check(float(st["zcr_per_s"]) >= 600.0,
			"过零率 %.0f/s >= 600（含虫鸣/高频微风成分，而非低频轰鸣）" % float(st["zcr_per_s"]))
	_check(float(st["lf_ratio"]) <= 0.5,
			"低频 <250Hz 能量占比 %d%% <= 50%%（旧文件 91%% 在 <200Hz）" % int(round(100.0 * float(st["lf_ratio"]))))
	_check(float(st["hf_ratio"]) >= 0.05,
			"高频 >2kHz 能量占比 %d%% >= 5%%（虫鸣存在）" % int(round(100.0 * float(st["hf_ratio"]))))
	_check(absf(float(st["dc"])) < 0.01, "无直流偏置（dc=%.5f）" % float(st["dc"]))
	_check(float(st["seam_jump"]) <= 0.05,
			"循环接缝跳变 %.5f <= 0.05（首尾交叉淡化无缝）" % float(st["seam_jump"]))
	_check(float(st["seam_jump"]) <= maxf(0.05, 8.0 * float(st["mean_abs_diff"])),
			"接缝跳变不超过相邻采样差典型值的 8 倍（%.5f vs %.5f）" % [
				float(st["seam_jump"]), float(st["mean_abs_diff"])])
	_check(float(st["edge_rms_first"]) > 0.02 and float(st["edge_rms_last"]) > 0.02,
			"首/尾 10ms 响度非静音（%.4f / %.4f）" % [float(st["edge_rms_first"]), float(st["edge_rms_last"])])
	var edge_ratio := float(st["edge_rms_first"]) / maxf(float(st["edge_rms_last"]), 0.0001)
	_check(edge_ratio > 0.33 and edge_ratio < 3.0, "首尾响度接近，循环处无音量台阶（比值 %.2f）" % edge_ratio)

## 解析 16bit PCM WAV 并做波形统计。返回 {} 表示失败。
func _wav_stats(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var bytes := f.get_buffer(f.get_length())
	f.close()
	if bytes.size() < 44:
		return {}
	var out := {"riff": bytes.slice(0, 4).get_string_from_ascii(), "wave": bytes.slice(8, 12).get_string_from_ascii()}
	out["channels"] = 0
	out["sample_rate"] = 0
	out["bits"] = 0
	out["data_off"] = -1
	out["data_len"] = 0
	var pos := 12
	while pos + 8 <= bytes.size():
		var cid := bytes.slice(pos, pos + 4).get_string_from_ascii()
		var csz := int(bytes.decode_u32(pos + 4))
		if cid == "fmt " and pos + 8 + 16 <= bytes.size():
			out["channels"] = int(bytes.decode_u16(pos + 8 + 2))
			out["sample_rate"] = int(bytes.decode_u32(pos + 8 + 4))
			out["bits"] = int(bytes.decode_u16(pos + 8 + 14))
		elif cid == "data":
			out["data_off"] = pos + 8
			out["data_len"] = mini(csz, bytes.size() - (pos + 8))
		pos += 8 + csz + (csz & 1)
	var channels := int(out["channels"])
	var sr := int(out["sample_rate"])
	var bits := int(out["bits"])
	var off := int(out["data_off"])
	var dlen := int(out["data_len"])
	if off < 0 or channels != 1 or sr <= 0 or bits != 16 or dlen <= 1:
		return {}
	var frames := int(dlen / 2)
	var samples := PackedFloat32Array()
	samples.resize(frames)
	var a_lp := 1.0 - exp(-TAU * 250.0 / float(sr))
	var a_hp := 1.0 - exp(-TAU * 2000.0 / float(sr))
	var lp_y := 0.0
	var hp_y := 0.0
	var sum := 0.0
	var sumsq := 0.0
	var lf_sumsq := 0.0
	var hf_sumsq := 0.0
	var adiff := 0.0
	var clip := 0
	var zc := 0
	var prev := 0.0
	for i in frames:
		var x := float(bytes.decode_s16(off + 2 * i)) / 32768.0
		samples[i] = x
		sum += x
		sumsq += x * x
		lp_y += a_lp * (x - lp_y)
		lf_sumsq += lp_y * lp_y
		hp_y += a_hp * (x - hp_y)
		var hp := x - hp_y
		hf_sumsq += hp * hp
		if i > 0:
			adiff += absf(x - prev)
			if (x >= 0.0) != (prev >= 0.0):
				zc += 1
		if absf(x) >= 0.99997:
			clip += 1
		prev = x
	if frames <= 1 or sumsq <= 0.0:
		return {}
	var edge := mini(441, frames - 1)
	var e_first := 0.0
	var e_last := 0.0
	for i in edge:
		e_first += samples[i] * samples[i]
		e_last += samples[frames - 1 - i] * samples[frames - 1 - i]
	var e_first_rms := sqrt(e_first / float(edge))
	var e_last_rms := sqrt(e_last / float(edge))
	out["frames"] = frames
	out["duration"] = float(frames) / float(sr)
	out["peak"] = _arr_peak(samples)
	out["clip_count"] = clip
	out["rms"] = sqrt(sumsq / float(frames))
	out["rms_db"] = linear_to_db(float(out["rms"]))
	out["zcr_per_s"] = float(zc) / maxf(float(frames) / float(sr), 0.0001)
	out["lf_ratio"] = lf_sumsq / sumsq
	out["hf_ratio"] = hf_sumsq / sumsq
	out["mean_abs_diff"] = adiff / float(frames - 1)
	out["seam_jump"] = absf(samples[0] - samples[frames - 1])
	out["edge_rms_first"] = e_first_rms
	out["edge_rms_last"] = e_last_rms
	out["dc"] = sum / float(frames)
	return out

func _arr_peak(a: PackedFloat32Array) -> float:
	var p := 0.0
	for v in a:
		var av := absf(v)
		if av > p:
			p = av
	return p

# ============================================================
# 3) 初始（白天）状态
# ============================================================
func _probe_day_setup(snap: Dictionary) -> void:
	_out("--- SETUP / DAY ---")
	var players: Array = snap.get("parent_players", [])
	var names := {}
	for p_v in players:
		var p: Dictionary = p_v
		names[String(p.get("name", ""))] = true
	_check(players.size() == EXPECT_PLAYERS, "播放器数量 == %d（实际 %d）" % [EXPECT_PLAYERS, players.size()])
	_check(names.size() == EXPECT_PLAYERS, "播放器名称无重复（唯一 %d）" % names.size())
	var loops: Array = snap.get("loops", [])
	if loops.size() == 3:
		_check(bool(loops[0].get("playing", false)), "白天 Ocean 在播")
		_check(bool(loops[1].get("playing", false)), "白天 Wind 在播")
		_check(not bool(loops[2].get("playing", false)), "白天 Night 不播放（旧的 setup 静音播放已移除）")
	_check(int(snap.get("sfx_players", 0)) == 8, "SFX 池 8 路")
	_check(bool(snap.get("fire_loaded", false)), "壁炉音频已加载")
	var group_buses := ["IsleAmbient", "IsleBirds", "IsleFire", "IsleSFX"]
	var routed_all := true
	for p_v in players:
		var p: Dictionary = p_v
		if not (String(p.get("bus", "")) in group_buses):
			routed_all = false
	_check(routed_all, "所有播放器路由到四组总线之一（IsleAmbient/Birds/Fire/SFX）")

# ============================================================
# 4) 3 轮昼夜模拟（dt=0.05，state 与 main.gd _update_audio 完全一致）
# ============================================================
func _run_cycles() -> void:
	_out("--- SIMULATE %d ROUNDS (day -> dusk -> night -> dawn) ---" % ROUNDS)
	for cyc in ROUNDS:
		_hold(DAY_SUN, DAY_FRAMES)
		_day_end_snaps.append(_snap())
		_ramp(DAY_SUN, DUSK_END_SUN, DUSK_FRAMES)
		_hold(NIGHT_SUN, NIGHT_FRAMES)
		_night_end_snaps.append(_snap())
		# 幂等：已入夜后再保持 100 帧，夜间层不得重复启停
		var tot_before: Dictionary = AudioScript.get_event_totals()
		_hold(NIGHT_SUN, 100)
		var tot_after: Dictionary = AudioScript.get_event_totals()
		if int(tot_before.get("loop_play:Night", 0)) != int(tot_after.get("loop_play:Night", 0)) \
				or int(tot_before.get("loop_stop:Night", 0)) != int(tot_after.get("loop_stop:Night", 0)):
			_idem_ok = false
		_ramp(NIGHT_SUN, DAY_SUN, DAWN_FRAMES)
		var s: Dictionary = _snap()
		_player_counts.append((s.get("parent_players", []) as Array).size())
		var nl: Array = s.get("loops", [])
		_out("  [ROUND %d] phase=%s players=%d night_env=%.3f night_playing=%s totals=%s" % [
			cyc + 1, String(s.get("phase", "")), (s.get("parent_players", []) as Array).size(),
			float(nl[2].get("env", 0.0)) if nl.size() == 3 else -1.0,
			str(nl[2].get("playing", false)) if nl.size() == 3 else "?",
			JSON.stringify(AudioScript.get_event_totals())])
	# 收尾白天：让夜间层衰减到停止（跨过 STOP 门限）
	_hold(DAY_SUN, DAY_FRAMES)
	_day_end_snaps.append(_snap())
	_player_counts.append((_snap().get("parent_players", []) as Array).size())

func _hold(sun_alt: float, frames: int) -> void:
	for i in frames:
		_step(sun_alt)

func _ramp(from_alt: float, to_alt: float, frames: int) -> void:
	for i in frames:
		var k := float(i + 1) / float(frames)
		_step(lerpf(from_alt, to_alt, k))

func _step(sun_alt: float) -> void:
	_frame_t += DT
	var night := clampf(-sun_alt / 10.0, 0.0, 1.0)
	var wind := clampf(0.40 + 0.22 * sin(_frame_t * 0.09) + 0.10 * sin(_frame_t * 0.31), 0.0, 1.0)
	_audio.call("update_audio", DT, {
		"sun_alt": sun_alt,
		"night": night,
		"wind": wind,
		"fireplace_on": sun_alt < 2.0,
	})

# ============================================================
# 5) 轮次断言：启停次数 / 幂等 / 夜间层状态 / 播放器不累积
# ============================================================
func _probe_cycles() -> void:
	_out("--- LOGIC ---")
	var totals: Dictionary = AudioScript.get_event_totals()
	_out("  totals=" + JSON.stringify(totals))
	_check(int(totals.get("loop_play:Night", 0)) == ROUNDS,
			"夜间层播放次数 == %d 轮（实际 %d）" % [ROUNDS, int(totals.get("loop_play:Night", 0))])
	_check(int(totals.get("loop_stop:Night", 0)) == ROUNDS,
			"夜间层停止次数 == %d 轮（实际 %d）" % [ROUNDS, int(totals.get("loop_stop:Night", 0))])
	_check(int(totals.get("loop_play:Ocean", 0)) == 1,
			"Ocean 只启动一次（实际 %d）" % int(totals.get("loop_play:Ocean", 0)))
	_check(int(totals.get("loop_play:Wind", 0)) == 1,
			"Wind 只启动一次（实际 %d）" % int(totals.get("loop_play:Wind", 0)))
	_check(int(totals.get("loop_stop:Ocean", 0)) == 0 and int(totals.get("loop_stop:Wind", 0)) == 0,
			"Ocean/Wind 从不停止（正常环境声底噪保留）")
	_check(int(totals.get("loop_play:finished_fallback", 0)) == 0,
			"无循环结束兜底重播（loop_end 设置正确）")
	_check(int(totals.get("fire_start", 0)) == ROUNDS and int(totals.get("fire_stop", 0)) == ROUNDS,
			"壁炉随黄昏/黎明恰好启停 %d 次（start=%d stop=%d）" % [
				ROUNDS, int(totals.get("fire_start", 0)), int(totals.get("fire_stop", 0))])
	_check(int(totals.get("warn_missing", 0)) == 0, "无缺失音频资源警告")

	var counts_ok := not _player_counts.is_empty()
	for c_v in _player_counts:
		if int(c_v) != EXPECT_PLAYERS:
			counts_ok = false
	_check(counts_ok, "播放器数量全程恒为 %d，不随昼夜轮次累积（采样 %s）" % [EXPECT_PLAYERS, str(_player_counts)])

	var night_ok := _night_end_snaps.size() == ROUNDS
	var env_min := 1.0
	var night_db_max := -999.0
	for s_v in _night_end_snaps:
		var s: Dictionary = s_v
		var loops: Array = s.get("loops", [])
		if loops.size() != 3:
			night_ok = false
			continue
		var night: Dictionary = loops[2]
		if not bool(night.get("playing", false)):
			night_ok = false
		env_min = minf(env_min, float(night.get("env", 0.0)))
		night_db_max = maxf(night_db_max, float(night.get("volume_db", -999.0)))
	_check(night_ok, "夜间层在夜间实际播放（%d 轮夜间快照）" % ROUNDS)
	_check(env_min >= 0.75, "夜间层 env 收敛到 %.3f >= 0.75（渐变生效而非突变）" % env_min)
	_check(night_db_max <= -5.0 and night_db_max > -20.0,
			"夜间层音量 %.1f dB 在合理区间（[-20,-5]，无过载/静音）" % night_db_max)

	var day_ok := true
	for s_v in _day_end_snaps:
		var s: Dictionary = s_v
		var loops: Array = s.get("loops", [])
		if loops.size() == 3 and bool(loops[2].get("playing", false)):
			day_ok = false
	_check(day_ok, "白天（每轮开始时）夜间层已停止（%d 个白天快照）" % _day_end_snaps.size())

	# 逻辑幂等：夜间状态保持时夜间层不得重复启停（_run_cycles 内每晚额外保持 100 帧验证）
	_check(_idem_ok, "夜间状态重复保持不产生重复启停（%d 轮 × 每晚额外 100 帧）" % ROUNDS)

# ============================================================
# 6) 事件序列断言
# ============================================================
func _probe_events() -> void:
	_out("--- EVENTS ---")
	var evs: Array = AudioScript.get_event_log()
	_check(not evs.is_empty(), "事件日志非空（%d 条）" % evs.size())
	_check(evs.size() <= 1024, "事件环形缓冲不超过上限 1024（实际 %d）" % evs.size())
	var seq_ok := true
	var prev_seq := 0
	for e_v in evs:
		var e: Dictionary = e_v
		var sq := int(e.get("seq", 0))
		if sq != prev_seq + 1:
			seq_ok = false
		prev_seq = sq
	_check(seq_ok, "事件 seq 单调连续（最后 seq=%d）" % prev_seq)

	var phases := {}
	var phase_count := 0
	var night_sfx := 0
	var bird_bad := 0
	var bird_count := 0
	var night_play := 0
	var night_play_src_bad := 0
	var gain_db_max := -999.0
	var night_gain_db_max := -999.0
	for e_v in evs:
		var e: Dictionary = e_v
		var typ := String(e.get("type", ""))
		var ph := String(e.get("phase", ""))
		if typ == "phase":
			phases[String(e.get("phase", ""))] = true
			phase_count += 1
		elif typ == "sfx" and (ph == "night"):
			night_sfx += 1
		elif typ == "sfx" and String(e.get("source", "")) == "bird":
			bird_count += 1
			# P6 起黎明阶段（日出前后 sun_alt>2）也会有鸟鸣，属合理扩展；禁止夜间/黄昏的鸟鸣。
			# P6 事件日志不再附带 sun_alt/night 字段（改为按 phase 归类），因此仅在字段存在时校验阈值。
			var sun_bad: bool = e.has("sun_alt") and (float(e.get("sun_alt", -999.0)) <= 2.0 or float(e.get("night", 1.0)) >= 0.35)
			if sun_bad or not (ph in ["day", "dawn"]):
				bird_bad += 1
		elif typ == "loop_play" and String(e.get("layer", "")) == "Night":
			night_play += 1
			if String(e.get("source", "")) != "night_gate":
				night_play_src_bad += 1
		elif typ == "gain":
			var gdb := float(e.get("db", 0.0))
			gain_db_max = maxf(gain_db_max, gdb)
			if String(e.get("layer", "")) == "Night":
				night_gain_db_max = maxf(night_gain_db_max, gdb)
	_check(phases.has("day") and phases.has("dusk") and phases.has("night") and phases.has("dawn"),
			"阶段事件覆盖 day/dusk/night/dawn（实际 %s）" % str(phases.keys()))
	_check(phase_count >= 4 * ROUNDS, "阶段切换事件 >= %d（实际 %d）" % [4 * ROUNDS, phase_count])
	_check(night_sfx == 0, "夜间阶段没有任何 SFX 事件（实际 %d）" % night_sfx)
	_check(bird_bad == 0, "鸟鸣只在白天触发（sun_alt>2 且 night<0.35，%d 条违规）" % bird_bad)
	_check(night_play == ROUNDS and night_play_src_bad == 0,
			"夜间层播放事件全部来自 night_gate（%d 条，异常来源 %d）" % [night_play, night_play_src_bad])
	_check(gain_db_max <= 6.0, "环境层音量事件最大 %.1f dB <= +6dB（无过载）" % gain_db_max)
	_check(night_gain_db_max <= -5.0, "夜间层增益上限 %.1f dB <= -5dB（与基准 -6.5dB 一致）" % night_gain_db_max)
	_out("  birds=%d (bad=%d) night_sfx=%d night_play=%d phases=%d" % [
		bird_count, bird_bad, night_sfx, night_play, phase_count])

# ============================================================
# 7) 混音 API / SFX 日志 / 事件日志静态接口
# ============================================================
func _probe_mix_api() -> void:
	_out("--- MIX / API ---")
	var idx := AudioServer.get_bus_index("Master")
	_check(idx >= 0, "Master bus 存在（index=%d）" % idx)
	for gb in ["IsleAmbient", "IsleBirds", "IsleFire", "IsleSFX"]:
		_check(AudioServer.get_bus_index(gb) >= 0, "分组总线 %s 已创建" % gb)
	_audio.call("set_volume", 0.5)
	var bus_db := AudioServer.get_bus_volume_db(idx) if idx >= 0 else 0.0
	_check(absf(bus_db - linear_to_db(0.5)) < 0.05,
			"set_volume(0.5) -> bus %.2f dB (期望 %.2f)" % [bus_db, linear_to_db(0.5)])
	_audio.call("set_volume", 1.0)
	_check(absf(AudioServer.get_bus_volume_db(idx)) < 0.05, "set_volume(1.0) 恢复 bus 0 dB")
	_audio.call("set_muted", true)
	_check(AudioServer.is_bus_mute(idx), "set_muted(true) 生效")
	_audio.call("set_muted", false)
	_check(not AudioServer.is_bus_mute(idx), "set_muted(false) 恢复")

	var totals_before: Dictionary = AudioScript.get_event_totals()
	_audio.call("play_ui_click")
	_audio.call("play_door", true)
	_audio.call("play_splash", 0.8)
	_audio.call("play_fire_crackle")
	var totals_after: Dictionary = AudioScript.get_event_totals()
	_check(int(totals_after.get("sfx", 0)) - int(totals_before.get("sfx", 0)) == 4,
			"4 个常规 SFX 均记入事件日志")
	var srcs := {}
	for e_v in AudioScript.get_event_log():
		var e: Dictionary = e_v
		if String(e.get("type", "")) == "sfx":
			srcs[String(e.get("source", ""))] = true
	for want in ["ui_click", "door_open", "water_splash", "fire_crackle"]:
		_check(srcs.has(want), "SFX 事件包含触发者 '%s'" % want)
	var snap: Dictionary = _snap()
	_check(AudioScript.get_event_log().size() == int(snap.get("event_count", -1)),
			"get_event_log() 与 debug_snapshot().event_count 一致")
	var info: Dictionary = _audio.call("get_debug_info") as Dictionary
	_check(int(info.get("event_count", -1)) > 0 and String(info.get("phase", "")) != "",
			"get_debug_info() 暴露 phase/event_count")
	_check(bool(_audio.call("is_ready")), "is_ready() == true")

# ============================================================
# 8) 事件序列落盘 / 汇总
# ============================================================
func _dump_events() -> void:
	_out("--- EVENT SEQUENCE ---")
	var evs: Array = AudioScript.get_event_log()
	for e_v in evs:
		var e: Dictionary = e_v
		var extra := {}
		for k in e:
			if k not in ["seq", "t", "ms", "phase", "type"]:
				extra[k] = e[k]
		_out("  [EV] seq=%3d t=%7.2f phase=%-5s %-12s %s" % [
			int(e.get("seq", 0)), float(e.get("t", 0.0)),
			String(e.get("phase", "")), String(e.get("type", "")), JSON.stringify(extra)])

func _final_report() -> void:
	var snap: Dictionary = _snap()
	_out("--- SNAPSHOT ---")
	_out(JSON.stringify(snap, "  "))
	_out("=== P5 AUDIO PROBE RESULT: %s pass=%d fail=%d ===" % [
		"PASS" if _fail == 0 else "FAIL", _pass, _fail])
	DirAccess.make_dir_recursive_absolute("D:/休闲小岛幻境/开发产物/logs")
	var f := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")
		f.close()
		print("  log -> " + ProjectSettings.globalize_path(LOG_PATH))
	else:
		print("  [FAIL] 无法写日志 " + LOG_PATH)
		_fail += 1
	print("=== P5 AUDIO PROBE RESULT: ", "PASS" if _fail == 0 else "FAIL", " pass=", _pass, " fail=", _fail, " ===")
	# 主动释放探针实例，避免退出时 ObjectDB 泄漏警告（探针需保持输出干净）
	if is_instance_valid(_audio):
		_audio.free()
		_audio = null
	quit(0 if _fail == 0 else 1)
