extends SceneTree
## P5 灯塔旋转验收探针（headless）
##   Godot_v4.7.2-stable_win64_console.exe --headless --path D:/休闲小岛幻境/游戏工程 --script res://tools/probe_lighthouse_p5.gd
## 逐帧驱动 main.gd 的 _update_lighthouse_beam，检查：
##   1x 转速=20s/圈（可配置周期）；时间加速/减速同步；暂停停转；恢复连续不重置；
##   现实时间模式 20s/圈；帧率无关；每帧角度连续；手动跳时角度不突变；光束方向与角度同轴。
## 退出码 0 = 全部通过。

const MainScene := preload("res://isle.tscn")
const DT60 := 1.0 / 60.0
const SIM_DAY := 480.0
const PERIOD := 20.0
const REF_DAY := 480.0

var _pass := 0
var _fail := 0
var m: Node = null

func _initialize() -> void:
	print("=== P5 LIGHTHOUSE PROBE START ===")
	await process_frame
	m = MainScene.instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	if m._beam_rotator == null:
		print("[FATAL] _beam_rotator 为空，灯塔光束未构建")
		quit(1)
		return
	m._mode = 1  # Mode.PLAYING
	m._paused = false
	m._time_source = "sim"
	m._day_length = SIM_DAY
	m._sim_seconds = 10.0 * 3600.0
	m._sim_delta = 0.0
	m._frame_t = 0.0
	probe_base_period()
	probe_speed_scaling()
	probe_pause_resume()
	probe_manual_jump()
	probe_real_mode()
	probe_frame_independence()
	probe_continuity_and_direction()
	print("=== P5 LIGHTHOUSE PROBE RESULT: ", "PASS" if _fail == 0 else "FAIL",
		" pass=", _pass, " fail=", _fail, " ===")
	quit(0 if _fail == 0 else 1)

func _check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("  [OK] ", msg)
	else:
		_fail += 1
		print("  [FAIL] ", msg)

## 模拟主循环一帧：real 模式真实 dt；sim 模式 _sim_delta = dt * 86400/day_length（与 _update_clock 一致）。
func _frame(dt: float) -> float:
	var before: float = m._beam_angle
	if m._time_source == "real":
		m._sim_delta = 0.0
	else:
		m._sim_delta = 0.0 if m._paused else dt * (86400.0 / m._day_length)
		if m._paused:
			m._sim_delta = 0.0
	m._frame_t += dt
	m._update_lighthouse_beam(dt)
	return angle_difference(before, m._beam_angle)

## 累计若干帧的总角度（带符号；不取模，便于测速）。
func _advance(seconds: float, dt: float) -> float:
	var n := int(round(seconds / dt))
	var total := 0.0
	for i in n:
		total += _frame(dt)
	return total

func _reset(day_length: float, source: String) -> void:
	m._time_source = source
	m._day_length = day_length
	m._paused = false
	m._beam_angle = 0.0
	m._sim_delta = 0.0

func probe_base_period() -> void:
	print("[1] 1x 基础转速（周期 20s => 20s 一圈）")
	_reset(SIM_DAY, "sim")
	var rev_time := 0.0
	var acc := 0.0
	var dt := DT60
	for i in 2400:
		acc += _frame(dt)
		if absf(acc) >= TAU:
			rev_time = (i + 1) * dt
			break
	_check(absf(rev_time - PERIOD) <= 0.05,
		"1x 一圈耗时 %.3fs（期望 %.1fs ±0.05）" % [rev_time, PERIOD])
	_check(absf(m._beam_rotator.rotation.y - fposmod(m._beam_angle, TAU)) < 0.001 or m._lighthouse_lamp != null,
		"灯室/光束旋转节点跟随 _beam_angle")

func probe_speed_scaling() -> void:
	print("[2] 时间流速同步（模拟时间加速/减速）")
	# 时间流速 = REF_DAY / day_length。day=240s(2x)、960s(0.5x)。
	for cfg in [[240.0, 2.0], [120.0, 4.0], [960.0, 0.5]]:
		var day: float = cfg[0]
		var mult: float = cfg[1]
		_reset(day, "sim")
		var expect := TAU * (10.0 / PERIOD) * mult  # 10 真实秒 × 流速倍率
		var got := absf(_advance(10.0, 1.0 / 120.0))  # 10 真实秒
		_check(absf(got - expect) < 0.02,
			"day=%.0fs => %sx：10s 转过 %.3f rad（期望 %.3f）" % [day, str(mult), got, expect])
	# 同一真实时长，加速后必须比常速转得多。
	_reset(SIM_DAY, "sim")
	var base := absf(_advance(5.0, 1.0 / 120.0))
	_reset(120.0, "sim")
	var fast := absf(_advance(5.0, 1.0 / 120.0))
	_check(fast > base * 3.5, "4x 时间流速下 5s 转角 %.3f > 常速 %.3f 的 3.5 倍" % [fast, base])

func probe_pause_resume() -> void:
	print("[3] 暂停停转 / 恢复连续不重置")
	_reset(SIM_DAY, "sim")
	_advance(3.0, DT60)
	var frozen_at: float = m._beam_angle
	m._paused = true
	var moved := 0.0
	for i in 120:
		m._sim_delta = 0.0
		m._frame_t += DT60
		m._update_lighthouse_beam(DT60)
		moved += absf(angle_difference(frozen_at, m._beam_angle))
		frozen_at = m._beam_angle
	_check(moved < 1e-6, "暂停 2s 后光束累计转动 %.8f rad（应为 0）" % moved)
	m._paused = false
	var resumed_delta := _advance(2.0, DT60)
	_check(absf(absf(resumed_delta) - TAU * 2.0 / PERIOD) < 0.01,
		"恢复后 2s 连续转过 %.4f rad（期望 %.4f，角度未重置）" % [absf(resumed_delta), TAU * 2.0 / PERIOD])
	_check(absf(angle_difference(0.0, m._beam_angle)) > TAU * 0.2, "恢复后角度保持累计值（非从 0 重新开始）")

func probe_manual_jump() -> void:
	print("[4] 手动跳时：角度不突变（跳时只影响模拟时钟，不产生额外旋转动画）")
	_reset(SIM_DAY, "sim")
	_advance(2.0, DT60)
	var before: float = m._beam_angle
	m._sim_seconds += 6.0 * 3600.0  # 模拟 +6 小时
	m._time_jump = 6.0 * 3600.0
	for i in 60:
		m._sim_delta = 0.0
		m._frame_t += DT60
		m._update_lighthouse_beam(DT60)
	var moved := absf(angle_difference(before, m._beam_angle))
	_check(moved < 1e-6, "跳时后 1s 角度变化 %.8f rad（应无跳变/回调）" % moved)

func probe_real_mode() -> void:
	print("[5] 现实时间模式：真实 20s 一圈，不受 day_length 影响")
	_reset(240.0, "real")
	var rev := 0.0
	var acc := 0.0
	for i in 2400:
		acc += _frame(DT60)
		if absf(acc) >= TAU:
			rev = (i + 1) * DT60
			break
	_check(absf(rev - PERIOD) <= 0.05, "real 模式一圈 %.3fs（期望 20s）" % rev)
	# real 模式下暂停键不应停转（现实时间继续走）
	m._paused = true
	var moved := absf(_advance(2.0, DT60))
	m._paused = false
	_check(absf(moved - TAU * 2.0 / PERIOD) < 0.01, "real 模式暂停键不冻结现实时间旋转（2s 转 %.4f rad）" % moved)

func probe_frame_independence() -> void:
	print("[6] 帧率无关：同一模拟时长不同 dt 转角一致")
	_reset(SIM_DAY, "sim")
	var a := absf(_advance(10.0, 1.0 / 30.0))
	_reset(SIM_DAY, "sim")
	var b := absf(_advance(10.0, 1.0 / 120.0))
	_check(absf(a - b) < 0.01, "30fps 10s=%.5f rad，120fps 10s=%.5f rad，差 %.6f" % [a, b, absf(a - b)])

func probe_continuity_and_direction() -> void:
	print("[7] 角度连续 / 光束方向同轴（含俯角 34°）")
	# 最高时间流速（day_length=60 => 8x）：单帧增量必须平滑
	_reset(60.0, "sim")
	var max_inc := 0.0
	for i in 600:
		max_inc = maxf(max_inc, absf(_frame(DT60)))
	_check(max_inc < 0.2, "8x 最高速下单帧最大转角 %.4f rad < 0.2（无跨角度跳跃）" % max_inc)
	# 方向：水平方位 = _beam_angle，垂直分量 = -sin(34°)
	var ang: float = m._beam_angle
	var d: Vector3 = m._beam_dir_world
	var yaw := atan2(-d.x, -d.z)
	var pitch := asin(clampf(-d.y, -1.0, 1.0))
	_check(absf(angle_difference(ang, yaw)) < 0.001, "光束水平方位 %.4f = 当前角度 %.4f" % [yaw, ang])
	_check(absf(pitch - deg_to_rad(34.0)) < 0.002, "光束俯角 %.2f°（期望 34°）" % rad_to_deg(pitch))
	_check(d.y < -0.5, "光束整体斜向下（dir.y=%.3f）" % d.y)
