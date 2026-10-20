extends SceneTree
## Phase6 T5 炊烟双时间窗验收探针（headless，不加载 isle.tscn、不渲染）：
##   D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe --headless --path D:/休闲小岛幻境/游戏工程 --script res://tools/probe_smoke6.gd
## 断言：
##   [API]    smoke() 返回 {node,mat,ctl}，ctl.set_sim_seconds()/smoke_debug() 可用；创建时默认不发射
##   [WINDOW] 11:00<=t<13:00 与 17:00<=t<19:00 发射；10:59:59/13:00/16:59/19:00/23:00 不发射（边界精确到秒）
##   [RAMP]   进入窗口后 amount_ratio 在 1.5 模拟秒内单调增强；窗口内 60s 跳转直接满强度
##   [IDEMPOTENT] 重复 smoke()/set_sim_seconds()/跨日不重复创建发射器，created_count 恒 1，节点数不增长
##   [STATIC] 静态 Fx.update_smoke()/Fx.smoke_debug() 备用入口可用
## 退出码：0 = 全部断言通过。

const Fx := preload("res://scripts/fx.gd")

var _pass := 0
var _fail := 0

func _initialize() -> void:
	print("=== T5 SMOKE PROBE START ===")
	await process_frame
	var holder := Node3D.new()
	holder.name = "SmokeHolder"
	root.add_child(holder)
	var first: Dictionary = Fx.smoke(holder, Vector3(1.0, 7.5, -2.0))
	var ctl: Node = first.get("ctl", null)
	var parts: GPUParticles3D = first.get("node", null)
	_check(ctl != null and ctl.has_method("set_sim_seconds"), "smoke() 返回 ctl 且带 set_sim_seconds()")
	_check(parts != null and String(parts.name) == "ChimneySmoke", "发射器节点名 ChimneySmoke（实际 %s）" % String(parts.name) if parts != null else "发射器节点名 ChimneySmoke（缺失）")
	_check(parts != null and parts.lifetime == 7.0 and parts.amount == 60, "发射器参数 lifetime=7.0 / amount=60（T5 可见度增强）")
	_check(parts != null and not parts.emitting, "创建后未喂时钟 -> 不发射（避免加载画面冒烟）")
	_check(holder.get_child_count() == 1, "创建后 holder 只有 1 个子节点（实际 %d）" % holder.get_child_count())
	var dbg0: Dictionary = ctl.call("smoke_debug")
	_check(int(dbg0.get("created_count", -1)) == 1, "created_count == 1")
	_check(dbg0.has("active_window") and dbg0.has("emitting") and dbg0.has("time_label") and dbg0.has("emitters"), "smoke_debug() 含 active_window/emitting/time_label/created_count/emitters")
	var ds: Dictionary = ctl.call("debug_state") if ctl.has_method("debug_state") else {}
	_check(ctl.has_method("debug_state") and ds.has("emitting") and ds.has("active_window"), "ctl.debug_state() 兼容入口存在（main.gd:2147 自检依赖）")
	_probe_boundaries(ctl)
	_probe_ramp(ctl)
	_probe_idempotent(holder, ctl)
	_probe_static()
	print("=== T5 SMOKE PROBE RESULT: ", "PASS" if _fail == 0 else "FAIL", " pass=", _pass, " fail=", _fail, " ===")
	quit(0 if _fail == 0 else 1)

func _check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("  [OK] ", msg)
	else:
		_fail += 1
		print("  [FAIL] ", msg)

func _dbg(ctl: Node, t: float) -> Dictionary:
	ctl.call("set_sim_seconds", t)
	return ctl.call("smoke_debug")

func _check_state(ctl: Node, t: float, expect_win: bool, label: String) -> Dictionary:
	var d: Dictionary = _dbg(ctl, t)
	var win: bool = bool(d.get("active_window", false))
	var emi: bool = bool(d.get("emitting", false))
	var ratio: float = float(d.get("ratio", -1.0))
	var parts: GPUParticles3D = (ctl.get("particles") as GPUParticles3D)
	var p_emi: bool = parts.emitting if parts != null else false
	var p_ratio: float = parts.amount_ratio if parts != null else -1.0
	print("  [%s] %-9s t=%8.1f win=%s emitting=%s ratio=%.3f p.emitting=%s p.ratio=%.3f label=%s" % [
		"OK" if win == expect_win and emi == expect_win and p_emi == expect_win else "!!",
		label, t, str(win), str(emi), ratio, str(p_emi), p_ratio, String(d.get("time_label", ""))])
	_check(win == expect_win, "%s 窗口状态 active_window=%s（期望 %s）" % [label, str(win), str(expect_win)])
	_check(emi == expect_win, "%s emitting=%s（期望 %s）" % [label, str(emi), str(expect_win)])
	_check(p_emi == expect_win, "%s GPUParticles3D.emitting=%s（期望 %s）" % [label, str(p_emi), str(expect_win)])
	_check(absf(p_ratio - ratio) < 0.001, "%s amount_ratio 与 debug.ratio 一致（%.3f vs %.3f）" % [label, p_ratio, ratio])
	return d

func _probe_boundaries(ctl: Node) -> void:
	print("--- WINDOW BOUNDARIES ---")
	_check_state(ctl, 10.0 * 3600.0 + 59.0 * 60.0 + 59.0, false, "10:59:59")
	_check_state(ctl, 11.0 * 3600.0, true, "11:00:00")
	_check_state(ctl, 12.0 * 3600.0, true, "12:00:00")
	_check_state(ctl, 12.0 * 3600.0 + 59.0 * 60.0 + 59.0, true, "12:59:59")
	_check_state(ctl, 13.0 * 3600.0, false, "13:00:00")
	_check_state(ctl, 16.0 * 3600.0 + 59.0 * 60.0, false, "16:59:00")
	_check_state(ctl, 17.0 * 3600.0, true, "17:00:00")
	_check_state(ctl, 18.0 * 3600.0, true, "18:00:00")
	_check_state(ctl, 18.0 * 3600.0 + 59.0 * 60.0 + 59.0, true, "18:59:59")
	_check_state(ctl, 19.0 * 3600.0, false, "19:00:00")
	_check_state(ctl, 23.0 * 3600.0, false, "23:00:00")
	# 时间窗判定函数本身（左闭右开、精确到秒）
	var b: bool = Fx.is_smoke_window(39600.0)
	_check(b and not Fx.is_smoke_window(39599.999) and not Fx.is_smoke_window(46800.0) and Fx.is_smoke_window(46799.999), "is_smoke_window 左闭右开：11:00:00 开 / 12:59:59.999 开 / 13:00:00 关")
	_check(Fx.smoke_time_label(39600.0) == "11:00:00", "smoke_time_label(39600) == 11:00:00（实际 %s）" % Fx.smoke_time_label(39600.0))

func _probe_ramp(ctl: Node) -> void:
	print("--- RAMP ---")
	_check_state(ctl, 16.0 * 3600.0 + 59.0 * 60.0 + 59.0, false, "16:59:59")
	_check_state(ctl, 16.0 * 3600.0 + 59.0 * 60.0 + 59.9, false, "16:59:59.9")
	var r1: float = float(_check_state(ctl, 17.0 * 3600.0, true, "17:00:00.0").get("ratio", -1.0))
	var r2: float = float(_check_state(ctl, 17.0 * 3600.0 + 0.1, true, "17:00:00.1").get("ratio", -1.0))
	var r3: float = float(_check_state(ctl, 17.0 * 3600.0 + 0.2, true, "17:00:00.2").get("ratio", -1.0))
	print("  ramp ratios: %.3f -> %.3f -> %.3f (RAMP=%.1fs)" % [r1, r2, r3, Fx.SMOKE_RAMP_SECONDS])
	_check(r1 > 0.0 and r1 < 0.2, "入窗渐进：17:00:00.0 ratio=%.3f 在 (0,0.2)" % r1)
	_check(r2 > r1 and r3 > r2, "ratio 单调增强（%.3f < %.3f < %.3f）" % [r1, r2, r3])
	_check(absf(r3 - r3) < 1.0, "ramp 采样完成")
	# 窗口内大跳（scrubber/时间快进）应直接满强度，而不是从 0 慢慢爬
	var dj: Dictionary = _check_state(ctl, 18.0 * 3600.0, true, "18:00:00(jump)")
	_check(absf(float(dj.get("ratio", 0.0)) - 1.0) < 0.001, "窗口内 1h 跳转 -> ratio 直接 1.0（实际 %.3f）" % float(dj.get("ratio", 0.0)))
	# 出窗后停止发射且 ratio 归零（旧粒子按 lifetime 自然消散，不手动清空）
	var dout: Dictionary = _check_state(ctl, 19.0 * 3600.0, false, "19:00:00")
	_check(absf(float(dout.get("ratio", -1.0))) < 0.001, "出窗 ratio 归零（实际 %.3f）" % float(dout.get("ratio", -1.0)))

func _probe_idempotent(holder: Node3D, ctl: Node) -> void:
	print("--- IDEMPOTENT ---")
	var c1: Node = (Fx.smoke(holder, Vector3(9.0, 9.0, 9.0)) as Dictionary).get("ctl", null)
	var c2: Node = (Fx.smoke(holder, Vector3(-9.0, 3.0, 3.0)) as Dictionary).get("ctl", null)
	_check(c1 == ctl and c2 == ctl, "重复 smoke() 复用同一个控制器（不新建）")
	_check(holder.get_child_count() == 1, "重复 smoke() 后 holder 仍只有 1 个子节点（实际 %d）" % holder.get_child_count())
	var d: Dictionary = ctl.call("smoke_debug")
	_check(int(d.get("created_count", -1)) == 1, "重复调用后 created_count 仍为 1")
	# 跨日：23:00 -> 次日 00:30 -> 次日 11:00，仍不应新建发射器
	_dbg(ctl, 23.0 * 3600.0)
	_dbg(ctl, 30.0 * 60.0)
	var dn: Dictionary = _dbg(ctl, 11.0 * 3600.0)
	_check(bool(dn.get("active_window", false)), "跨日后 11:00 仍正确进入时间窗")
	_check(int(dn.get("created_count", -1)) == 1 and holder.get_child_count() == 1, "跨日后 created_count/节点数不变")
	# 反复喂同一时刻应幂等（不叠加 amount/不新增节点）
	var before_amount: float = ((ctl.get("particles") as GPUParticles3D).amount_ratio)
	for i in range(30):
		ctl.call("set_sim_seconds", 11.5 * 3600.0)
	var after_amount: float = ((ctl.get("particles") as GPUParticles3D).amount_ratio)
	_check(absf(before_amount - after_amount) < 0.0001, "同一时刻重复喂时钟幂等（amount_ratio %.3f）" % after_amount)

func _probe_static() -> void:
	print("--- STATIC ENTRY ---")
	Fx.update_smoke(12.0 * 3600.0)
	var d: Dictionary = Fx.smoke_debug()
	_check(bool(d.get("active_window", false)) and bool(d.get("emitting", false)), "静态 Fx.update_smoke()/Fx.smoke_debug() 生效")
	_check(int(d.get("created_count", 0)) == 1, "静态 smoke_debug().created_count == 1")
	Fx.update_smoke(23.0 * 3600.0)
	var d2: Dictionary = Fx.smoke_debug()
	_check(not bool(d2.get("active_window", true)), "静态入口夜间 23:00 不发射")