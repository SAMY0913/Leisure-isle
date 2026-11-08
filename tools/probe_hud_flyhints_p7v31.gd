extends SceneTree
## P7-V3.1 自由视角 HUD 提示一致性探针（headless）
##
## 复核 P7-V3 遗留问题：右上角固定说明在自由视角下仍展示轨道相机文案。
## 本探针走**真实入口**（main._enter_flycam / _exit_flycam），因此同时覆盖
## main → hud.set_fly_hints 的接线，而不只是 HUD 单函数。
##
## 断言：
##  1) 轨道视角：四行提示为轨道文案，快捷行含 "C 自动运镜"
##  2) 自由视角：四行提示为飞行文案，快捷行**不**再出现自动运镜（该键只作用于轨道相机），
##     且出现 "F 退出自由视角"
##  3) 退出后逐字恢复轨道文案（含快捷行）
##  4) 飞行提示覆盖 isle_flycam.help_text() 里的全部关键操作
##     （WASD / Space / Ctrl / Shift / 右键转向 / 左键点击 / 退出）
##
## 运行：
##   ENG --headless --path <PROJ> --script res://tools/probe_hud_flyhints_p7v31.gd

var _pass: int = 0
var _fail: int = 0

var ORBIT_LINES := [
	"左键拖动 · 旋转视角",
	"右键拖动 · 平移观察点",
	"滚轮 · 推拉镜头",
	"点击 · 木门 / 烟囱 / 海面",
]
const ORBIT_KEYS := "空格 暂停 · Tab 天文历 · T 时间 · C 自动运镜 · H 隐藏界面"
const ORBIT_KEYS2 := "F2 截图 · F3 性能 · F11 全屏"

func _initialize() -> void:
	await process_frame
	var packed: PackedScene = load("res://isle.tscn") as PackedScene
	if packed == null:
		print("[FLYHINT] FAIL cannot load res://isle.tscn")
		quit(1)
		return
	var main: Node = packed.instantiate()
	get_root().add_child(main)
	await process_frame
	await process_frame
	var menu = main.get("_menu")
	if menu != null and menu.has_method("instant_finish"):
		menu.call("instant_finish")
	main.set("_mode", 1)
	main.set("_time_source", "sim")
	main.set("_realtime", false)
	main.set("_started", true)
	main.set("_paused", true)
	main.set("_auto_orbit", false)
	main.set("_blending", "")
	main.set("_sim_seconds", 0.0)
	await process_frame

	var hud: Node = main.get("_hud")
	if hud == null:
		print("[FLYHINT] FAIL no _hud")
		quit(1)
		return

	# ---- 1) 轨道视角基线 ----
	var orbit := _hints(hud)
	_ok(_lines_eq(orbit["lines"], ORBIT_LINES), "轨道视角四行提示 = 轨道文案", str(orbit["lines"]))
	_ok(String(orbit["keys"]).contains("自动运镜"), "轨道视角快捷行含 C 自动运镜", String(orbit["keys"]))
	_ok(String(orbit["keys2"]) == ORBIT_KEYS2, "轨道视角次要快捷行原样", String(orbit["keys2"]))

	# ---- 2) 进入自由视角（真实入口）----
	var flycam = main.get("_flycam")
	if flycam == null or not main.has_method("_enter_flycam"):
		print("[FLYHINT] FAIL 缺少 _flycam / _enter_flycam")
		quit(1)
		return
	main.call("_enter_flycam")
	await process_frame
	_ok(bool(flycam.get("active")), "自由视角已激活（真实入口）", str(flycam.get("active")))
	var fly := _hints(hud)
	var joined := ("%s %s %s" % [str(fly["lines"]), fly["keys"], fly["keys2"]])
	_ok(not _lines_eq(fly["lines"], ORBIT_LINES), "自由视角四行提示已切换", str(fly["lines"]))
	_ok(not joined.contains("自动运镜"), "自由视角提示不再出现『自动运镜』（避免冲突说明）", joined)
	_ok(joined.contains("WASD"), "自由视角提示含 WASD 水平移动", joined)
	_ok(joined.contains("Space 上升"), "自由视角提示含 Space 上升", joined)
	_ok(joined.contains("Ctrl 下降"), "自由视角提示含 Ctrl 下降", joined)
	_ok(joined.contains("Shift"), "自由视角提示含 Shift 冲刺", joined)
	_ok(joined.contains("转向"), "自由视角提示含鼠标转向", joined)
	_ok(joined.contains("左键"), "自由视角提示含左键交互", joined)
	_ok(joined.contains("F 退出自由视角"), "自由视角提示含退出方式", joined)

	# ---- 3) 与 flycam.help_text() 的关键操作集合交叉核对 ----
	if flycam.has_method("help_text"):
		var help := String(flycam.call("help_text"))
		var missing: Array = []
		for token in ["WASD", "Space", "Ctrl", "Shift", "转向", "左键"]:
			if help.contains(token) and not joined.contains(token):
				missing.append(token)
		_ok(missing.is_empty(), "右上角提示覆盖 help_text 的全部关键操作（缺：%s）" % str(missing), help)

	# ---- 4) 退出后恢复 ----
	main.call("_exit_flycam")
	await process_frame
	await process_frame
	var back := _hints(hud)
	_ok(bool(flycam.get("_exiting")), "自由视角已请求退出（active 含 smoothstep 回位混合期，故此处断言 _exiting）", str(flycam.get("_exiting")))
	_ok(_lines_eq(back["lines"], ORBIT_LINES), "退出后四行提示逐字恢复", str(back["lines"]))
	_ok(String(back["keys"]) == ORBIT_KEYS, "退出后快捷行逐字恢复", String(back["keys"]))
	_ok(String(back["keys2"]) == ORBIT_KEYS2, "退出后次要快捷行逐字恢复", String(back["keys2"]))

	# ---- 5) 开菜单的防御路径：飞行中开菜单必须先退出并恢复轨道文案 ----
	main.call("_enter_flycam")
	await process_frame
	main.call("_open_menu")
	await process_frame
	await process_frame
	var men := _hints(hud)
	_ok(bool(flycam.get("_exiting")), "飞行中打开菜单会先安全退出自由视角（_exiting=true）", str(flycam.get("_exiting")))
	_ok(String(men["keys"]) == ORBIT_KEYS, "开菜单后快捷行恢复轨道文案", String(men["keys"]))

	print("[FLYHINT] RESULT pass=%d fail=%d" % [_pass, _fail])
	await process_frame
	quit(0 if _fail == 0 else 1)

func _hints(hud: Node) -> Dictionary:
	var lines: Array = []
	var raw: Variant = hud.get("_hint_lines")
	if raw is Array:
		for l in (raw as Array):
			lines.append(String((l as Label).text if l is Label else ""))
	var k: Label = hud.get("_hint_keys")
	var k2: Label = hud.get("_hint_keys2")
	return {
		"lines": lines,
		"keys": String(k.text) if k != null else "",
		"keys2": String(k2.text) if k2 != null else "",
	}

func _lines_eq(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if String(a[i]) != String(b[i]):
			return false
	return true

func _ok(cond: bool, msg: String, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("[FLYHINT] PASS ", msg, ("  (" + detail + ")") if detail != "" else "")
	else:
		_fail += 1
		print("[FLYHINT] FAIL ", msg, ("  (" + detail + ")") if detail != "" else "")
