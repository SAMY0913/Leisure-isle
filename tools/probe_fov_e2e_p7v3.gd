extends SceneTree
## P7-V3 FOV 真实落盘 + 重启恢复 端到端探针
## 前置：本机 Godot 子进程写不了真实 user://（FileAccess error=12），
##       需用 APPDATA 覆盖把 user 数据目录挪到可写工作区：
##   APPDATA="D:/休闲小岛幻境/开发产物/p7v3/userdir" <引擎> --headless --path "<游戏工程>" ##       --script res://tools/probe_fov_e2e_p7v3.gd -- --mode=cold
## 三次进程共用同一 APPDATA/userdir：
##   mode=cold    : 空 userdir 冷启动 → 默认 fov=42（设置/相机）；经 _on_settings_changed 改 58 → 等 0.25s 防抖落盘 → 断言 user://settings.cfg fov=58
##   mode=check58 : 重启进程 → 读到 58（Settings/_fov/cam.fov）→ 经同一 handler 改回 42 → 防抖落盘
##   mode=check42 : 再重启进程 → 读到 42（设置/相机均恢复默认）→ 清理临时 user://settings.cfg
## 退出码 0 = 全过；1 = 有 FAIL。out 日志由外层 bash 收集。

const S := preload("res://scripts/isle_settings.gd")
const USER_CFG := "user://settings.cfg"
const WRITE_TEST := "user://.fov_e2e_write_test"

var _pass := 0
var _fail := 0
var _fails: Array[String] = []

func _chk(cond: bool, label: String, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("[FOVE2E] PASS ", label, "  ", detail)
	else:
		_fail += 1
		_fails.append(label)
		print("[FOVE2E] FAIL ", label, "  ", detail)

func _near(a: float, b: float, eps: float = 0.01) -> bool:
	return absf(a - b) <= eps

func _mode() -> String:
	for raw in OS.get_cmdline_user_args():
		var a := String(raw)
		if a.begins_with("--mode="):
			return a.substr(7)
	return "all"

func _cfg_path() -> String:
	return ProjectSettings.globalize_path(USER_CFG)

func _read_cfg_fov() -> float:
	var cfg := ConfigFile.new()
	if cfg.load(USER_CFG) != OK:
		return -1.0
	return float(cfg.get_value("settings", "fov", -1.0))

func _load_main() -> Node:
	var packed := load("res://isle.tscn") as PackedScene
	if packed == null:
		return null
	var m: Node = packed.instantiate()
	get_root().add_child(m)
	await process_frame
	await process_frame
	return m

func _wait_flush(target: float) -> bool:
	for i in range(240):
		await process_frame
		var v := _read_cfg_fov()
		if _near(v, target, 0.05):
			return true
	return false

func _cam_of(m: Node) -> Camera3D:
	return m.get("_cam") as Camera3D

## 菜单观景机位固定 36°（main.gd _movie_pose），玩家 FOV 只在 PLAYING 机位生效；
## 因此断言相机 fov 前先切到 playing 并等两帧让 _update_camera 应用 _play_pose()。
func _enter_play(m: Node) -> void:
	m.set("_mode", 1)  # main.gd enum Mode.PLAYING
	m.set("_started", true)
	m.set("_paused", true)
	m.set("_auto_orbit", false)
	m.set("_blending", "")
	await process_frame
	await process_frame

func _run_cold() -> void:
	if FileAccess.file_exists(USER_CFG):
		DirAccess.remove_absolute(_cfg_path())
	_chk(not FileAccess.file_exists(USER_CFG), "冷启动前 user://settings.cfg 不存在", _cfg_path())
	# user:// 可写性自检（APPDATA 覆盖是否生效）
	var wf := FileAccess.open(WRITE_TEST, FileAccess.WRITE)
	_chk(wf != null, "user:// 可写（APPDATA 覆盖生效）", "err=" + str(FileAccess.get_open_error()) if wf == null else _cfg_path())
	if wf != null:
		wf.store_string("ok")
		wf.close()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(WRITE_TEST))
	var s: Dictionary = S.load_settings()
	var f0 := float(s.get("fov", -1.0))
	_chk(_near(f0, 42.0), "冷启动 Settings.load_settings().fov=42", str(f0))
	var m: Node = await _load_main()
	_chk(m != null, "isle.tscn 加载成功")
	if m == null:
		return
	await _enter_play(m)
	var mfov := float(m.get("_fov"))
	_chk(_near(mfov, 42.0), "冷启动 main._fov=42（_ready 读取默认）", str(mfov))
	var cam := _cam_of(m)
	_chk(cam != null and _near(cam.fov, 42.0), "冷启动 _cam.fov=42（PLAYING 机位）", "null" if cam == null else str(cam.fov))
	m.call("_on_settings_changed", {"fov": 58.0})
	_chk(_near(float(m.get("_fov")), 58.0), "改设置后 main._fov=58（设置应用链路）", str(float(m.get("_fov"))))
	await process_frame
	await process_frame
	var cam2 := _cam_of(m)
	_chk(cam2 != null and _near(cam2.fov, 58.0), "改设置后相机 fov=58（实时生效）", "null" if cam2 == null else str(cam2.fov))
	var flushed: bool = await _wait_flush(58.0)
	_chk(flushed, "0.25s 防抖后 user://settings.cfg 落盘 fov=58", _cfg_path())
	var fv := _read_cfg_fov()
	_chk(_near(fv, 58.0), "落盘文件 settings/fov=58", str(fv))

func _run_check58() -> void:
	var s: Dictionary = S.load_settings()
	var f0 := float(s.get("fov", -1.0))
	_chk(_near(f0, 58.0), "重启后 Settings.load_settings().fov=58", str(f0))
	var m: Node = await _load_main()
	_chk(m != null, "isle.tscn 加载成功")
	if m == null:
		return
	await _enter_play(m)
	var mfov := float(m.get("_fov"))
	_chk(_near(mfov, 58.0), "重启后 main._fov=58（_ready 读取玩家配置）", str(mfov))
	var cam := _cam_of(m)
	_chk(cam != null and _near(cam.fov, 58.0), "重启后 _cam.fov=58（PLAYING 机位）", "null" if cam == null else str(cam.fov))
	m.call("_on_settings_changed", {"fov": 42.0})
	_chk(_near(float(m.get("_fov")), 42.0), "恢复默认后 main._fov=42", str(float(m.get("_fov"))))
	await process_frame
	await process_frame
	var cam2 := _cam_of(m)
	_chk(cam2 != null and _near(cam2.fov, 42.0), "恢复默认后相机 fov=42", "null" if cam2 == null else str(cam2.fov))
	var flushed: bool = await _wait_flush(42.0)
	_chk(flushed, "恢复默认后 user://settings.cfg 落盘 fov=42", _cfg_path())
	var fv := _read_cfg_fov()
	_chk(_near(fv, 42.0), "落盘文件 settings/fov=42", str(fv))

func _run_check42() -> void:
	var s: Dictionary = S.load_settings()
	var f0 := float(s.get("fov", -1.0))
	_chk(_near(f0, 42.0), "二次重启后 Settings.load_settings().fov=42", str(f0))
	var m: Node = await _load_main()
	_chk(m != null, "isle.tscn 加载成功")
	if m == null:
		return
	await _enter_play(m)
	var mfov := float(m.get("_fov"))
	_chk(_near(mfov, 42.0), "二次重启后 main._fov=42", str(mfov))
	var cam := _cam_of(m)
	_chk(cam != null and _near(cam.fov, 42.0), "二次重启后 _cam.fov=42（PLAYING 机位）", "null" if cam == null else str(cam.fov))
	if FileAccess.file_exists(USER_CFG):
		DirAccess.remove_absolute(_cfg_path())
	_chk(not FileAccess.file_exists(USER_CFG), "清理临时 user://settings.cfg", _cfg_path())

func _initialize() -> void:
	var mode := _mode()
	print("[FOVE2E] mode=", mode)
	print("[FOVE2E] user_data_dir=", OS.get_user_data_dir())
	print("[FOVE2E] user_cfg=", _cfg_path())
	if mode == "cold":
		await _run_cold()
	elif mode == "check58":
		await _run_check58()
	elif mode == "check42":
		await _run_check42()
	else:
		_chk(false, "未知 --mode（需 cold|check58|check42）", mode)
	print("[FOVE2E] RESULT pass=", _pass, " fail=", _fail)
	for f in _fails:
		print("[FOVE2E] FAILED_ITEM ", f)
	quit(0 if _fail == 0 else 1)
