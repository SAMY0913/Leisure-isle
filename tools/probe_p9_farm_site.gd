extends SceneTree
## P9 / P0 —— 农田选址、空间测量与视觉验证探针（本阶段唯一允许新增的仓库文件）。
##
## 只读使用正式场景：加载 isle.tscn -> 读取真实运行时地形/散布实例 -> 计算候选 3x3 农田布局 ->
## 输出 JSON/MD/截图到仓库外目录。不修改任何正式场景、构建函数、相机默认参数或存档数据。
##
## 运行（headless 测量）：
##   "$ENG" --path "D:/休闲小岛幻境/游戏工程" --headless --script res://tools/probe_p9_farm_site.gd -- --out="D:/休闲小岛幻境/开发产物/P9/P0"
## 运行（窗口测量 + 截图，需 GPU）：
##   "$ENG" --path "D:/休闲小岛幻境/游戏工程" --script res://tools/probe_p9_farm_site.gd -- --p9shots --out="D:/休闲小岛幻境/开发产物/P9/P0"
## 注意：截图参数必须叫 --p9shots。main.gd:394 会把 --shots 当成项目内置截图流程，
## 并发改写时间/天气/相机并显示 HUD，从而污染本探针截图与 camera_default 读数。
## 可选参数：--center=lx,lz  --rot=deg  --gap=m  --cell=m  --border=m  --preview  --tag=前缀
## 判据：exit 0 且 [FARMSITE] RESULT fail=0；截图需人工查看。

const S := preload("res://scripts/isle_settings.gd")
const M := preload("res://scripts/isle_math.gd")

const DEFAULT_OUT := "D:/休闲小岛幻境/开发产物/P9/P0"
const SHOT_W := 1600
const SHOT_H := 1000

var out_dir := DEFAULT_OUT
var do_shots := false
var do_preview := false
var do_map := false
var do_heights := false
var cand_list: Array = []
var tag_prefix := ""
var center_override := Vector2.INF
var rot_deg := 0.0
## gap = 相邻耕格之间的净空隙（用户定：0.5 m）；格心距 pitch = cell + gap。
var gap := 0.50
var cell := 1.00
## 外圈操作走道（耕格外沿到土床外沿）。名称沿用以兼容旧日志，语义不是"装饰边"。
var border := 0.65
var gate_w := 1.10
var max_env_dh := 0.55
var max_env_slope := 15.0
## 用户拍板（m01333）：田块单一水平，但改为"向下发展"——台面贴最高地形，台面以下基座埋进坡地，
## 田台整体嵌入坡地（v4 镶嵌关系）：上坡侧台面与地面基本齐平、下坡侧露出垂直石砌基座；不做草裙、不做阶梯。
## 5 株冬季红花按用户 2026-10-23 决定全部删除（P2 删 world.gd:1094-1100 锚点）。
var max_podium := 1.95   # 下沉式基座向下埋深上限（m）：台面以下都算基座，越深越贵但不可见
var max_cut := 0.30      # 台面允许的切方上限（m）：只切最高处极浅一层，避免改动地形权威函数
var min_path_clear := 0.90
var do_search := false
var scatter_measured := false

var _main: Node = null
var _world: Dictionary = {}
var _pass := 0
var _fail := 0
var _checks: Array = []
var _shots: Array = []
var _scatter_nodes: Array = []
var _blooms: Array = []
var _lamps: Array = []
var _notes: Array = []
var _preview_tris := 0
var _preview_geo: Dictionary = {}
var _mesh_name_counts: Dictionary = {}
var _masked_saved: Array = []
var _shots_weather := ""


func _initialize() -> void:
	_run.call_deferred()


# ============================================================ arg parsing ===
func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--out="):
			out_dir = s.substr(6).strip_edges().trim_suffix("/").trim_suffix("\\")
		elif s == "--p9shots":
			# 注意：不能叫 --shots —— main.gd:394 会把它当成项目内置截图流程，
			# 并发改写时间/天气/相机并显示 HUD，污染本探针的截图与 camera_default 读数。
			do_shots = true
		elif s == "--preview":
			do_preview = true
		elif s == "--map":
			do_map = true
		elif s == "--heights":
			do_heights = true
		elif s.begins_with("--center="):
			var parts := s.substr(9).split(",")
			if parts.size() >= 2:
				center_override = Vector2(float(parts[0]), float(parts[1]))
		elif s.begins_with("--rot="):
			rot_deg = float(s.substr(6))
		elif s.begins_with("--gap="):
			gap = float(s.substr(6))
		elif s.begins_with("--cell="):
			cell = float(s.substr(7))
		elif s.begins_with("--border="):
			border = float(s.substr(9))
		elif s.begins_with("--tag="):
			tag_prefix = s.substr(6)
		elif s.begins_with("--max-dh="):
			max_env_dh = float(s.substr(9))
		elif s.begins_with("--max-slope="):
			max_env_slope = float(s.substr(12))
		elif s.begins_with("--min-clear="):
			min_path_clear = float(s.substr(12))
		elif s == "--search":
			do_search = true
		elif s.begins_with("--cand="):
			for part in s.substr(7).split(";"):
				var pp := String(part).split(",")
				if pp.size() >= 2:
					cand_list.append(Vector2(float(pp[0]), float(pp[1])))
	if out_dir == "":
		out_dir = DEFAULT_OUT


# ============================================================== utilities ===
## 房屋局部 (lx, lz) -> 世界 XZ。与 World._in_house 使用的变换互逆。
func _l2w(lx: float, lz: float) -> Vector2:
	var c := cos(M.HOUSE_YAW)
	var s := sin(M.HOUSE_YAW)
	return Vector2(M.HOUSE_X + lx * c + lz * s, M.HOUSE_Z - lx * s + lz * c)


## 世界 XZ -> 房屋局部。与 World._in_house 一致。
func _w2l(x: float, z: float) -> Vector2:
	var dx := x - M.HOUSE_X
	var dz := z - M.HOUSE_Z
	var c := cos(M.HOUSE_YAW)
	var s := sin(M.HOUSE_YAW)
	return Vector2(dx * c - dz * s, dx * s + dz * c)


## 农田局部 (fx, fz) -> 世界 XZ。
func _f2w(center: Vector2, fx: float, fz: float) -> Vector2:
	var r := deg_to_rad(rot_deg)
	var lx := center.x + fx * cos(r) - fz * sin(r)
	var lz := center.y + fx * sin(r) + fz * cos(r)
	return _l2w(lx, lz)


func _f2l(center: Vector2, fx: float, fz: float) -> Vector2:
	var r := deg_to_rad(rot_deg)
	return Vector2(center.x + fx * cos(r) - fz * sin(r), center.y + fx * sin(r) + fz * cos(r))


## 世界 XZ -> 农田局部（散布物归属判定）。
func _w2f(center: Vector2, x: float, z: float) -> Vector2:
	var l := _w2l(x, z)
	var r := deg_to_rad(rot_deg)
	var dx := l.x - center.x
	var dz := l.y - center.y
	return Vector2(dx * cos(r) + dz * sin(r), -dx * sin(r) + dz * cos(r))


## 格心距：相邻格中心距离 = 格尺寸 + 净空隙。
func _pitch() -> float:
	return cell + gap


## 九格最外沿半宽：3 列格心在 ±pitch，最外沿 = pitch + cell/2 = 1.5*cell + gap。
func _half_cells() -> float:
	return _pitch() + cell * 0.5


## 土床半宽 = 九格外沿 + 外圈操作走道（旧称 border；实测 0.65 m，含格间 0.10 m 之外的一圈走道）.
func _half_plot() -> float:
	return _half_cells() + border


func _half_fence() -> float:
	return _half_plot() + 0.06


func _check(id: String, ok: bool, detail: String, expected: String = "") -> bool:
	print(("[FARMSITE][PASS] " if ok else "[FARMSITE][FAIL] ") + id + " | " + detail + (" | expected=" + expected if expected != "" else ""))
	_checks.append({"id": id, "pass": ok, "detail": detail, "expected": expected})
	if ok:
		_pass += 1
	else:
		_fail += 1
	return ok


# ============================================================ main flow ====
func _run() -> void:
	_parse_args()
	var headless := DisplayServer.get_name() == "headless"
	DirAccess.make_dir_recursive_absolute(out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir + "/shots")
	print("[FARMSITE] out=%s headless=%s shots=%s preview=%s rot=%.2f gap=%.3f cell=%.3f border=%.3f" % [out_dir, str(headless), str(do_shots), str(do_preview), rot_deg, gap, cell, border])

	var scene: PackedScene = load("res://isle.tscn")
	if scene == null:
		_check("scene_load", false, "isle.tscn 加载失败")
		_finish()
		return
	_check("scene_load", true, "isle.tscn")
	_main = scene.instantiate()
	root.add_child(_main)
	await process_frame
	await process_frame
	_main.set("_settings", S.defaults())
	_main.call("_apply_user_settings", false)
	await process_frame
	if not headless:
		DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))
		await process_frame
		await process_frame
		await process_frame
	_main.set("_settings_save_delay", -1.0)
	_main.set("_mode", 1)
	_main.set("_started", true)
	_main.set("_paused", false)
	_main.set("_blending", "")
	_main.set("_auto_orbit", false)
	_main.set("_settings_save_delay", -1.0)
	# 隐藏标题菜单（只影响本次探针运行，不改动场景/脚本/存档）
	var menu: Node = _main.get("_menu")
	if menu != null:
		if menu.has_method("instant_finish"):
			menu.call("instant_finish")
		menu.set("menu_visible", false)
		(menu as CanvasLayer).visible = false
	_main.call("_set_time_of_day", 12.0 * 60.0 + 20.0)
	# 先记录 _ready 产出的默认相机参数（本轮不得改变）
	var cam: Camera3D = _main.get("_cam") as Camera3D
	var def_theta := float(_main.get("_theta"))
	var def_elev := float(_main.get("_elev"))
	var def_radius := float(_main.get("_radius"))
	var def_fov := float(_main.get("_fov"))
	_check("camera_fov_default_42", is_equal_approx(def_fov, 42.0), "字段回读 %.2f（非相机变换回读）" % def_fov)
	_check("camera_theta_default", absf(def_theta - M.CAM_START_THETA) <= 0.02, "字段回读 %.4f（非相机变换回读；start %.2f, tol 0.02）" % [def_theta, M.CAM_START_THETA])
	_check("camera_elev_default", absf(def_elev - 0.28) <= 0.02, "字段回读 %.4f（非相机变换回读）" % def_elev)
	_check("camera_radius_default", absf(def_radius - M.CAM_START_R) <= 0.01, "字段回读 %.4f（非相机变换回读）" % def_radius)
	if cam != null:
		print("[FARMSITE] camera_world=%s fov=%.2f" % [str(cam.global_transform.origin), cam.fov])
	_pose_play_default()
	await process_frame
	await process_frame

	var w = _main.get("_world")
	if not (w is Dictionary) or not (w as Dictionary).has("root"):
		_check("world_ready", false, "main._world 缺失")
		_finish()
		return
	_world = w as Dictionary
	_check("world_ready", true, "Island 根节点与散布实例可用")

	_collect_scatter()
	_collect_blooms()
	_collect_lamps()

	var w1 := _l2w(-1.5, 9.7)
	var rt := _w2l(w1.x, w1.y)
	_check("coord_roundtrip", rt.distance_to(Vector2(-1.5, 9.7)) < 1e-4, str(rt))
	var old_rot := rot_deg
	rot_deg = 37.0
	var fwd := _f2w(Vector2(-1.5, 9.7), 1.3, -0.7)
	var back := _w2f(Vector2(-1.5, 9.7), fwd.x, fwd.y)
	rot_deg = old_rot
	_check("field_coord_roundtrip_rot37", back.distance_to(Vector2(1.3, -0.7)) < 1e-4, "field back=(%.4f,%.4f)" % [back.x, back.y])
	# 与引擎内 _in_house/_in_porch 交叉验证：我们的局部->世界转换必须与正式判定一致
	var mism := 0
	var samples: Array = [
		[Vector2(0.0, 0.0), true, false], [Vector2(3.4, 2.6), true, false], [Vector2(-3.9, 0.0), false, false],
		[Vector2(0.0, 5.0), false, true], [Vector2(0.0, 8.0), false, false], [Vector2(-2.0, 9.5), false, false],
		[Vector2(-2.0, 10.8), false, false],
	]
	for smp in samples:
		var sm := smp as Array
		var lp := sm[0] as Vector2
		var ww := _l2w(lp.x, lp.y)
		var want_house := bool(sm[1])
		var want_porch := bool(sm[2])
		if IsleWorld._in_house(ww.x, ww.y, 0.0) != want_house:
			mism += 1
			print("[FARMSITE][COORD] _in_house mismatch at local=(%.1f,%.1f) world=(%.2f,%.2f)" % [lp.x, lp.y, ww.x, ww.y])
		if IsleWorld._in_porch(ww.x, ww.y, 0.0) != want_porch:
			mism += 1
			print("[FARMSITE][COORD] _in_porch mismatch at local=(%.1f,%.1f) world=(%.2f,%.2f)" % [lp.x, lp.y, ww.x, ww.y])
	_check("coord_matches_game_transforms", mism == 0, "cross-check mismatches=%d of %d samples (house/porch rect)" % [mism, samples.size()])

	var cands: Array = []
	if center_override != Vector2.INF:
		cands.append(center_override)
	elif cand_list.size() > 0:
		cands = cand_list
	else:
		cands = [
			Vector2(-1.5, 9.7),
			Vector2(-1.5, 10.4),
			Vector2(-2.2, 10.1),
			Vector2(-2.8, 9.7),
			Vector2(-0.9, 10.6),
			Vector2(-2.2, 10.8),
			Vector2(0.0, 10.2),
			Vector2(-0.9, 11.4),
			Vector2(-1.5, 11.8),
			Vector2(-2.2, 12.2),
			Vector2(0.4, 11.2),
			Vector2(-3.0, 11.2),
			Vector2(-0.6, 12.6),
			Vector2(-1.5, 8.9),
		]
	if do_map:
		_map_mode()
	if do_heights:
		_heights_mode()
	var results: Array = []
	if do_search:
		results = _search_mode()
	else:
		for c in cands:
			results.append(_eval_candidate(c as Vector2))
	var best: Dictionary = _pick_best(results)
	if best.is_empty():
		_check("candidate_available", false, "没有可评测候选（搜索区域为空？）")
		_finish()
		return
	_check("candidate_available", true, "evaluated=%d" % results.size())

	for r in results:
		var rr := r as Dictionary
		var cl := rr["center_local"] as Array
		print("[FARMSITE] candidate local=(%.2f,%.2f) fail=%d scatter=%d blooms=%d hspread=%.3f slope=%.1f" % [
			cl[0], cl[1], int(rr["fail_count"]), int(rr["scatter_inside"]), int(rr["bloom_inside"]),
			float(rr["height_spread"]), float(rr["max_slope_deg"])])
	for r in results:
		var rr := r as Dictionary
		var cl := rr["center_local"] as Array
		var fails: Array = []
		for ck in (rr["checks"] as Array):
			var ckd := ck as Dictionary
			if not bool(ckd["pass"]):
				fails.append("%s{%s}" % [String(ckd["id"]), String(ckd["detail"])])
		print("[FARMSITE] candidate (%.2f,%.2f) failing=%d :: %s" % [cl[0], cl[1], fails.size(), " ; ".join(fails)])
	var rcl := best["center_local"] as Array
	print("[FARMSITE] recommended local=(%.2f,%.2f) fail=%d hard=%d env_dh=%.3f env_slope=%.1f blooms=%d" % [
		rcl[0], rcl[1], int(best["fail_count"]), int(best["hard_fail"]),
		float(best["envelope_height_spread"]), float(best["envelope_max_slope_deg"]), int(best["bloom_inside"])])
	_diag_scatter(Vector2(rcl[0], rcl[1]) as Vector2)

	if do_preview or do_shots:
		_build_preview(best)
		_check_preview_parallel(best)
	if do_shots and not headless:
		await _shots_for(best)
	elif do_shots and headless:
		_notes.append("headless 模式无法真实渲染：截图为未验证")
		_check("shots_rendered", false, "headless 模式无法渲染，未验证（须窗口模式重跑）")

	if not scatter_measured:
		_notes.append("散布冲突为未验证：headless 模式下 MultiMesh 变换不可读，必须窗口模式复测（已单独用窗口模式实测并在报告中给出数量）")
	_check("recommended_no_hard_fail", int(best["hard_fail"]) == 0,
		"recommended local=(%.2f,%.2f) hard_fail=%d fail_total=%d" % [rcl[0], rcl[1], int(best["hard_fail"]), int(best["fail_count"])])
	_check("recommended_level_podium", float(best["platform_cut"]) <= max_cut and float(best["platform_fill"]) <= max_podium,
		"cut=%.3f<=%.2f podium_down=%.3f<=%.2f (single level, downward base)" % [float(best["platform_cut"]), max_cut, float(best["platform_fill"]), max_podium])
	# v4 用户决定：5 株红花删除，不再作为设计约束
	_check("winter_bloom_removed_by_user", true,
		"5 株冬季红花按用户 2026-10-23 决定全部删除；探针运行时隐藏全部实例，P2 删除 world.gd:1094-1100 锚点；不再有移栽方案")
	# P8.1 冻结机位（main.gd:6963 target=(0.82,7.80,9.13)，对准 5 株冬季红花质心）是否被新田占据：
	# 对焦点落在田块包络之外 => 该证据机位的构图不被新田占据（P8.1 证据可复现）。
	var rw81 := best["center_world"] as Array
	var p81 := Vector3(0.82, 7.80, 9.13)
	var d81 := Vector2(p81.x - float(rw81[0]), p81.z - float(rw81[1])).length()
	var hf81: float = best["half_fence"]
	_check("p8_1_pose_focus_outside_farm", d81 > hf81,
		"P8.1 冻结机位对焦点 (0.82,7.80,9.13) 距田心 %.3f m > 围栏半宽 %.2f m（仅说明对焦点落在田外；对焦点外的前景是否被田块占据，见 shot 16 实拍，需用户拍板）" % [d81, hf81])
	if do_shots and not headless:
		_check("shots_rendered", _shots.size() >= 12, "shots=%d" % _shots.size())

	_write_json(best, results)
	_write_md(best, results)
	_finish()


# ======================================================= scene inventory ===
func _collect_mm(node: Node, out: Array) -> void:
	if node is MultiMeshInstance3D:
		var mmi := node as MultiMeshInstance3D
		if mmi.multimesh != null and mmi.multimesh.instance_count > 0:
			var arr := PackedVector3Array()
			for i in range(mmi.multimesh.instance_count):
				var t: Transform3D = mmi.multimesh.get_instance_transform(i)
				arr.append(mmi.global_transform * t.origin)
			out.append({"name": String(mmi.name), "count": arr.size(), "pos": arr, "node": mmi})
	for c in node.get_children():
		_collect_mm(c, out)


func _collect_scatter() -> void:
	var nodes: Array = []
	_collect_mm(_main, nodes)
	_scatter_nodes = nodes
	var total := 0
	var names: Array = []
	for n in nodes:
		total += int(n["count"])
		names.append("%s:%d" % [String(n["name"]), int(n["count"])])
	scatter_measured = false
	for n in nodes:
		var pos0: PackedVector3Array = n["pos"]
		for p0 in pos0:
			if p0.length() > 0.5:
				scatter_measured = true
				break
		if scatter_measured:
			break
	print("[FARMSITE] multimesh nodes=%d instances=%d scatter_measured=%s" % [nodes.size(), total, str(scatter_measured)])
	print("[FARMSITE] multimesh inventory: " + ", ".join(names))


func _collect_blooms() -> void:
	_blooms = []
	var wb = _world.get("winter_bloom", {})
	if wb is Dictionary:
		var base = (wb as Dictionary).get("base", [])
		if base is Array:
			for b in base:
				if b is Dictionary and (b as Dictionary).has("pos"):
					var bp: Vector3 = (b as Dictionary)["pos"]
					_blooms.append({"pos": bp})
	print("[FARMSITE] winter_bloom count=%d" % _blooms.size())


func _collect_lamps() -> void:
	_lamps = []
	var found := _main.find_children("PathLamp*", "Node3D", true, false)
	for nd in found:
		var n3 := nd as Node3D
		if n3 != null:
			_lamps.append(n3.global_position)
	print("[FARMSITE] lamp nodes=%d at %s" % [_lamps.size(), str(_lamps)])


# ================================================== scatter diagnostics ====
func _diag_scatter(center: Vector2) -> void:
	var cw := _l2w(center.x, center.y)
	print("[FARMSITE][DIAG] scatter diagnostic at field local=(%.2f,%.2f) world=(%.2f,%.2f)" % [center.x, center.y, cw.x, cw.y])
	print("[FARMSITE][DIAG] IsleWorld._grass_spot at plot center=%.3f  corners: %s" % [
		IsleWorld._grass_spot(cw.x, cw.y),
		", ".join([
			"%.2f" % IsleWorld._grass_spot(_f2w(center, -2.5, -2.5).x, _f2w(center, -2.5, -2.5).y),
			"%.2f" % IsleWorld._grass_spot(_f2w(center, 2.5, -2.5).x, _f2w(center, 2.5, -2.5).y),
			"%.2f" % IsleWorld._grass_spot(_f2w(center, 2.5, 2.5).x, _f2w(center, 2.5, 2.5).y),
			"%.2f" % IsleWorld._grass_spot(_f2w(center, -2.5, 2.5).x, _f2w(center, -2.5, 2.5).y)])])
	print("[FARMSITE][DIAG] _grass_weight center=%.3f  _norm_radius=%.3f  _h=%.3f  _path_clearance=%.3f  _in_porch=%.3f pad" % [
		IsleWorld._grass_weight(cw.x, cw.y), IsleWorld._norm_radius(cw.x, cw.y), IsleWorld._h(cw.x, cw.y),
		IsleWorld._path_clearance(cw.x, cw.y), (1.0 if IsleWorld._in_porch(cw.x, cw.y, 0.70) else 0.0)])
	for want in ["GrassNear", "GrassFar", "Clover"]:
		for nd in _scatter_nodes:
			if String(nd["name"]) != want:
				continue
			var pos: PackedVector3Array = nd["pos"]
			var near: Array = []
			var n3 := 0
			var n6 := 0
			var n10 := 0
			for p in pos:
				var d := Vector2(p.x, p.z).distance_to(cw)
				near.append([d, p.x, p.z])
				if d <= 3.0:
					n3 += 1
				if d <= 6.0:
					n6 += 1
				if d <= 10.0:
					n10 += 1
			near.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
			print("[FARMSITE][DIAG] %s count=%d within 3/6/10m = %d/%d/%d  nearest=%.2fm" % [want, pos.size(), n3, n6, n10, float(near[0][0]) if near.size() > 0 else -1.0])
			var shown := 0
			for e in near:
				if shown >= 5:
					break
				var ex := float(e[1])
				var ez := float(e[2])
				var fl := _w2f(center, ex, ez)
				print("[FARMSITE][DIAG]   nearest %s #%d world=(%.2f,%.2f) field=(%.2f,%.2f) d=%.2fm" % [want, shown, ex, ez, fl.x, fl.y, float(e[0])])
				shown += 1


# ================================================== height raster scan ====
func _heights_mode() -> void:
	print("[FARMSITE][HEIGHTS] 房屋局部地形高度栅格（单位 m，0.25m 步长）")
	var lx0 := -8.0
	var lx1 := 2.0
	var lz0 := 7.6
	var lz1 := 15.0
	var step := 0.25
	var cols := int(round((lx1 - lx0) / step)) + 1
	var rows := int(round((lz1 - lz0) / step)) + 1
	var hdr := "        "
	for i in range(cols):
		var lx := lx0 + float(i) * step
		hdr += ("%d" % (int(round(lx * 2.0)) % 10) if i % 4 == 0 else " ")
	print("[FARMSITE][HEIGHTS] " + hdr)
	var hmin := 1e9
	var hmax := -1e9
	for j in range(rows - 1, -1, -1):
		var lz := lz0 + float(j) * step
		var line := "lz=%5.2f " % lz
		for i in range(cols):
			var lx := lx0 + float(i) * step
			var w := _l2w(lx, lz)
			var h := IsleWorld.surface_y(w.x, w.y)
			hmin = minf(hmin, h)
			hmax = maxf(hmax, h)
			line += "%5.2f" % h
		print("[FARMSITE][HEIGHTS] " + line)
	print("[FARMSITE][HEIGHTS] 该区域高度范围 %.2f .. %.2f (跨度 %.2f m)" % [hmin, hmax, hmax - hmin])

	# 对若干候选矩形报告角点高差与最大坡度
	for c in [Vector2(-1.5, 9.7), Vector2(-1.5, 10.4), Vector2(-2.2, 10.8), Vector2(-1.7, 11.6),
			Vector2(-1.5, 12.2), Vector2(-2.2, 12.4), Vector2(-4.8, 10.6), Vector2(-5.4, 11.4),
			Vector2(-4.2, 11.8)]:
		var cc := c as Vector2
		var half := _half_plot()
		var lo := 1e9
		var hi := -1e9
		var sl2 := 0.0
		for s in range(11):
			var t: float = -half + float(s) * half / 5.0
			for e in [Vector2(t, -half), Vector2(t, half), Vector2(-half, t), Vector2(half, t)]:
				var ee := e as Vector2
				var w := _f2w(cc, ee.x, ee.y)
				var h := IsleWorld.surface_y(w.x, w.y)
				lo = minf(lo, h)
				hi = maxf(hi, h)
				var nrm: Vector3 = IsleWorld._hn(w.x, w.y)
				sl2 = maxf(sl2, rad_to_deg(acos(clampf(nrm.y, -1.0, 1.0))))
		print("[FARMSITE][HEIGHTS] rect center=(%.2f,%.2f) half=%.2f 角点高差=%.3f 最大坡度=%.1f" % [cc.x, cc.y, half, hi - lo, sl2])


# ================================================ free-space map scan ====
func _pt_free(lx: float, lz: float, pad: float) -> bool:
	var w := _l2w(lx, lz)
	if IsleWorld._path_clearance(w.x, w.y) < pad:
		return false
	if IsleWorld._in_house(w.x, w.y, 0.05) or IsleWorld._in_porch(w.x, w.y, 0.05) \
			or IsleWorld._in_garden(w.x, w.y, 0.05) or IsleWorld._in_field(w.x, w.y, 0.05) \
			or IsleWorld._in_bed(w.x, w.y, 0.05):
		return false
	return true


func _map_mode() -> void:
	print("[FARMSITE][MAP] 房屋局部坐标可用区扫描（列=lx 0.2m，行=lz 0.2m）图例: #=房屋 p=门廊 G=花圃 F=菜地 =道路内 ~道路边0.6m .可用")
	var lx0 := -6.6
	var lx1 := 2.2
	var lz0 := 6.8
	var lz1 := 14.8
	var step := 0.2
	var cols := int(round((lx1 - lx0) / step)) + 1
	var rows := int(round((lz1 - lz0) / step)) + 1
	var hdr := "        "
	for i in range(cols):
		var lx := lx0 + float(i) * step
		hdr += (str(int(round(lx)) % 10) if i % 5 == 0 else " ")
	print("[FARMSITE][MAP] " + hdr)
	for j in range(rows - 1, -1, -1):
		var lz := lz0 + float(j) * step
		var line := "lz=%5.1f " % lz
		for i in range(cols):
			var lx := lx0 + float(i) * step
			var w := _l2w(lx, lz)
			var ch := "."
			if IsleWorld._in_house(w.x, w.y, 0.05):
				ch = "#"
			elif IsleWorld._in_porch(w.x, w.y, 0.05):
				ch = "p"
			elif IsleWorld._in_garden(w.x, w.y, 0.05):
				ch = "G"
			elif IsleWorld._in_field(w.x, w.y, 0.05):
				ch = "F"
			else:
				var pc: float = IsleWorld._path_clearance(w.x, w.y)
				if pc < 0.10:
					ch = "="
				elif pc < 0.60:
					ch = "~"
			line += ch
		print("[FARMSITE][MAP] " + line)

	for hh in [1.70, 1.90, 2.10, 2.20]:
		var half := float(hh)
		var found: Array = []
		var bx := 0.0
		var bz := 0.0
		var bh := 1e9
		var bs := 1e9
		var stepc := 0.10
		var cx := -4.6
		while cx <= 0.8:
			var cz := 8.6
			while cz <= 13.6:
				var okc := true
				for s in range(int(ceil(half * 2.0 / 0.30)) + 1):
					var t: float = -half + float(s) * 0.30
					if not okc:
						break
					for e in [Vector2(t, -half), Vector2(t, half), Vector2(-half, t), Vector2(half, t)]:
						var ee := e as Vector2
						if not _pt_free(cx + ee.x, cz + ee.y, 0.10):
							okc = false
							break
				if okc:
					var hm := 1e9
					var hx := -1e9
					var sl := 0.0
					for j2 in range(3):
						for i2 in range(3):
							var cfx := float(i2 - 1) * _pitch()
							var cfz := float(j2 - 1) * _pitch()
							var wl := _l2w(cx + cfx, cz + cfz)
							var hh2 := IsleWorld.surface_y(wl.x, wl.y)
							hm = minf(hm, hh2)
							hx = maxf(hx, hh2)
					if half >= 2.0:
						var nrm: Vector3 = IsleWorld._hn(_l2w(cx, cz).x, _l2w(cx, cz).y)
						sl = rad_to_deg(acos(clampf(nrm.y, -1.0, 1.0)))
					found.append([cx, cz, hx - hm, sl])
					if (hx - hm) < bh:
						bh = hx - hm
						bx = cx
						bz = cz
						bs = sl
				cz += stepc
			cx += stepc
		if found.size() == 0:
			print("[FARMSITE][MAP] half=%.2fm 无可用中心（0.10m 扫描 lx[-4.6,0.8] lz[8.6,13.6]）" % half)
		else:
			print("[FARMSITE][MAP] half=%.2fm 可用中心=%d 最平中心=(%.2f,%.2f) 九格高差=%.3f 中心坡度=%.1f" % [half, found.size(), bx, bz, bh, bs])


# ===================================================== candidate evaluate ==
func _rect_point_dist(p: Vector2, x0: float, x1: float, z0: float, z1: float) -> float:
	var dx := maxf(maxf(x0 - p.x, 0.0), p.x - x1)
	var dz := maxf(maxf(z0 - p.y, 0.0), p.y - z1)
	return sqrt(dx * dx + dz * dz)


func _perimeter_points(hp: float, step: float) -> Array:
	var out: Array = []
	var n := int(ceil(hp * 2.0 / step))
	for s in range(n + 1):
		var t := -hp + float(s) / float(n) * (2.0 * hp)
		out.append(Vector2(t, -hp))
		out.append(Vector2(t, hp))
		out.append(Vector2(-hp, t))
		out.append(Vector2(hp, t))
	return out


## 冬季花卉落位方案（数值规划，非视觉证据）：
## 土床 1.91 与围栏 1.97 之间只有 0.06 m 余带，托不住花株，因此方案改为
## “把落在围栏内的花沿径向外推到围栏外 0.42 m 的草坪”，而不是塞进围栏内。
## 判据逐条计算：必须在围栏外、不得落在耕格或门洞通道内、道路余量达标、不侵房屋/门廊/花圃/菜地。
func _bloom_moves(center: Vector2, hc: float, hf: float) -> Array:
	var moves: Array = []
	var out_dist := hf + 0.42
	for b in _blooms:
		var bp: Vector3 = b["pos"]
		var fl := _w2f(center, bp.x, bp.z)
		var inside_fence := absf(fl.x) <= hf + 0.02 and absf(fl.y) <= hf + 0.02
		if not inside_fence:
			moves.append({"from_world": [bp.x, bp.y, bp.z], "from_field": [fl.x, fl.y],
				"to_field": [fl.x, fl.y], "to_world": [bp.x, bp.y, bp.z],
				"dist": 0.0, "keep_outside": true, "target_ok": true, "reason": "已在围栏外，保持原位"})
			continue
		var plan := _bloom_target(center, fl, hc, hf, out_dist)
		var target: Vector2 = plan["target"]
		var nw := _f2w(center, target.x, target.y)
		moves.append({"from_world": [bp.x, bp.y, bp.z], "from_field": [fl.x, fl.y],
			"to_field": [target.x, target.y],
			"to_world": [nw.x, IsleWorld.surface_y(nw.x, nw.y) - 0.01, nw.y],
			"dist": target.distance_to(fl), "keep_outside": false,
			"target_ok": bool(plan["ok"]), "reason": String(plan["reason"])})
	return moves


## 沿围栏外侧扫描：在围栏外 0.28/0.42/0.60 m 三圈、每 3° 取一个候选点，
## 挑“位移最小且满足全部约束”的落点。这样优先贴着自己那一侧的围栏，不被西侧固定方向拽走。
func _bloom_target(center: Vector2, fl: Vector2, hc: float, hf: float, out_dist: float) -> Dictionary:
	var gate := Vector2(0.0, -hf)
	var best := {"target": fl, "ok": false, "reason": "无可用落点"}
	var best_dist := 1e9
	var cands: Array = []
	for r in [hf + 0.28, hf + 0.42, hf + 0.60]:
		for adeg in range(0, 360, 3):
			var a := deg_to_rad(float(adeg))
			cands.append(Vector2(sin(a), cos(a)) * float(r))
	for cand in cands:
		var c := cand as Vector2
		var nw := _f2w(center, c.x, c.y)
		var edge := maxf(absf(c.x), absf(c.y))
		var outside_fence := edge >= hf + 0.14
		var clear_cells := edge >= hc + 0.14
		var pc := IsleWorld._path_clearance(nw.x, nw.y)
		var in_structures := IsleWorld._in_house(nw.x, nw.y, 0.12) or IsleWorld._in_porch(nw.x, nw.y, 0.12) \
			or IsleWorld._in_garden(nw.x, nw.y, 0.12) or IsleWorld._in_field(nw.x, nw.y, 0.12)
		# 门洞通道：大门在 -fz 边中点，门外 1.4 m 内不得摆花
		var in_gate_lane := absf(c.x) <= gate_w * 0.5 + 0.40 and c.y <= -hf + 0.10 and c.y >= -hf - 1.40
		var near_gate := c.distance_to(gate) < 0.85
		var ok := outside_fence and clear_cells and pc >= maxf(min_path_clear, 0.55) \
			and not in_structures and not in_gate_lane and not near_gate
		var d := c.distance_to(fl)
		if ok and d < best_dist:
			best_dist = d
			best = {"target": c, "ok": true, "reason": "side=(%.2f,%.2f) move=%.2f path_clear=%.2f" % [c.x, c.y, d, pc]}
		elif not ok and best_dist > 1e8 and pc > -1e8:
			best = {"target": c, "ok": false, "reason": "无满足全部约束的落点（候选 (%.2f,%.2f) path_clear=%.2f gate_lane=%s near_gate=%s）" % [
				c.x, c.y, pc, str(in_gate_lane), str(near_gate)]}
	return best


## 供截图用：把 5 株冬花实例临时搬到规划落点并强制可见（只改运行时 MultiMesh，不写文件、不改季节状态）。
func _apply_bloom_plan(rec: Dictionary) -> Dictionary:
	var moves: Array = rec["bloom_moves"]
	var stems: MultiMeshInstance3D = null
	var heads: MultiMeshInstance3D = null
	for nd in _scatter_nodes:
		var nm := String(nd["name"])
		if nm == "WinterBloomStems":
			stems = nd.get("node") as MultiMeshInstance3D
		elif nm == "WinterBloomHeads":
			heads = nd.get("node") as MultiMeshInstance3D
	var saved: Array = []
	var applied := 0
	for mi in [stems, heads]:
		var mmi := mi as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null:
			continue
		var mm := mmi.multimesh
		var per_node: Array = []
		for i in range(mini(mm.instance_count, moves.size())):
			var t: Transform3D = mm.get_instance_transform(i)
			per_node.append(t)
			var mv := moves[i] as Dictionary
			var tw: Array = mv["to_world"]
			var nt := t
			nt.origin = Vector3(float(tw[0]), float(tw[1]), float(tw[2]))
			mm.set_instance_transform(i, nt)
		saved.append({"node": mmi, "xforms": per_node})
		applied += 1
	if stems != null:
		stems.visible = true
	if heads != null:
		heads.visible = true
	return {"saved": saved, "applied": applied}


func _restore_bloom_plan(saved: Array) -> void:
	for s in saved:
		var d := s as Dictionary
		var mmi := d["node"] as MultiMeshInstance3D
		var xs: Array = d["xforms"]
		for i in range(xs.size()):
			mmi.multimesh.set_instance_transform(i, xs[i] as Transform3D)
	for nd in _scatter_nodes:
		var nm := String(nd["name"])
		if nm == "WinterBloomStems" or nm == "WinterBloomHeads":
			var mmi2 := nd.get("node") as MultiMeshInstance3D
			if mmi2 != null:
				mmi2.visible = false


func _grid_points(half: float, step: float) -> Array:
	var out: Array = []
	var n := int(ceil(half * 2.0 / step))
	for j in range(n + 1):
		for i in range(n + 1):
			out.append(Vector2(-half + float(i) / float(n) * (2.0 * half), -half + float(j) / float(n) * (2.0 * half)))
	return out


func _eval_candidate(center: Vector2) -> Dictionary:
	var hc := _half_cells()
	var hp := _half_plot()
	var hf := _half_fence()
	var fail := 0
	var soft_fail := 0
	var checks: Array = []
	var cells: Array = []
	var hmin := 1e9
	var hmax := -1e9
	var max_slope := 0.0
	var min_cell_pc := 1e9
	var cell_dh_max := 0.0

	for j in range(3):
		for i in range(3):
			var fx := float(i - 1) * _pitch()
			var fz := float(j - 1) * _pitch()
			var w := _f2w(center, fx, fz)
			var h := IsleWorld.surface_y(w.x, w.y)
			var cmin := 1e9
			var cmax := -1e9
			var cslope := 0.0
			var ch := cell * 0.5
			for k in range(4):
				var cxk := fx + (ch if (k % 2) == 0 else -ch)
				var czk := fz + (ch if k < 2 else -ch)
				var wk := _f2w(center, cxk, czk)
				var hk := IsleWorld.surface_y(wk.x, wk.y)
				cmin = minf(cmin, hk)
				cmax = maxf(cmax, hk)
				var nk: Vector3 = IsleWorld._hn(wk.x, wk.y)
				var sl := rad_to_deg(acos(clampf(nk.y, -1.0, 1.0)))
				cslope = maxf(cslope, sl)
			hmin = minf(hmin, cmin)
			hmax = maxf(hmax, cmax)
			max_slope = maxf(max_slope, cslope)
			cell_dh_max = maxf(cell_dh_max, cmax - cmin)
			var pc: float = IsleWorld._path_clearance(w.x, w.y)
			min_cell_pc = minf(min_cell_pc, pc)
			var in_house: bool = IsleWorld._in_house(w.x, w.y, 0.10)
			var in_porch: bool = IsleWorld._in_porch(w.x, w.y, 0.10)
			var in_garden: bool = IsleWorld._in_garden(w.x, w.y, 0.10)
			var in_field: bool = IsleWorld._in_field(w.x, w.y, 0.10)
			var in_bed: bool = IsleWorld._in_bed(w.x, w.y, 0.10)
			var clearcell := not (in_house or in_porch or in_garden or in_field or in_bed)
			var edge_pc := pc - cell * 0.5
			var cellok := clearcell and edge_pc >= 0.20
			if not cellok:
				fail += 1
			checks.append({"id": "cell_r%d_c%d" % [j, i], "pass": cellok,
				"detail": "local=(%.2f,%.2f) world=(%.3f,%.3f) h=%.3f cellH=[%.3f,%.3f] slope=%.1fdeg path_clear=%.3f house=%s porch=%s garden=%s field=%s bed=%s" % [
					fx, fz, w.x, w.y, h, cmin, cmax, cslope, pc,
					str(in_house), str(in_porch), str(in_garden), str(in_field), str(in_bed)]})
			var hl := _f2l(center, fx, fz)
			cells.append({"i": i, "j": j, "field_local": [fx, fz], "house_local": [hl.x, hl.y],
				"world_xz": [w.x, w.y], "surface_y": h, "corner_h": [cmin, cmax], "max_slope_deg": cslope,
				"path_clearance": pc, "clear": clearcell})

	# ---- 外围包络（围栏）：整块区域高度/坡度/道路余量采样 ----
	var envelop_fail := 0
	var min_fence_pc := 1e9
	var worst_pc := Vector2.ZERO
	var env_hmin := 1e9
	var env_hmax := -1e9
	var env_slope := 0.0
	var env_pts := _grid_points(hf, 0.25)
	var env_heights: Array = []
	for cf in env_pts:
		var cc := cf as Vector2
		var w := _f2w(center, cc.x, cc.y)
		var hh: float = IsleWorld.surface_y(w.x, w.y)
		env_heights.append(hh)
		env_hmin = minf(env_hmin, hh)
		env_hmax = maxf(env_hmax, hh)
		var nk: Vector3 = IsleWorld._hn(w.x, w.y)
		env_slope = maxf(env_slope, rad_to_deg(acos(clampf(nk.y, -1.0, 1.0))))
		var pcc: float = IsleWorld._path_clearance(w.x, w.y)
		if pcc < min_fence_pc:
			min_fence_pc = pcc
			worst_pc = cc
		if pcc < min_path_clear:
			envelop_fail += 1
		if IsleWorld._in_house(w.x, w.y, 0.05) or IsleWorld._in_porch(w.x, w.y, 0.05) \
				or IsleWorld._in_garden(w.x, w.y, 0.05) or IsleWorld._in_field(w.x, w.y, 0.05) \
				or IsleWorld._in_bed(w.x, w.y, 0.05):
			envelop_fail += 1
	var env_dh := env_hmax - env_hmin
	var env_tilt := rad_to_deg(atan(env_dh / maxf(0.01, hf * 2.0)))
	var env_ok := envelop_fail == 0
	if not env_ok:
		fail += 1
	checks.append({"id": "plot_envelope_clear", "pass": env_ok,
		"detail": "half=%.2fm envelope_violations=%d min_path_clear=%.3f at local=(%.2f,%.2f) require>=%.2f" % [
			hf, envelop_fail, min_fence_pc, worst_pc.x, worst_pc.y, min_path_clear]})
	# ---- 下沉式水平台面（向下发展）：台面标高贴住地块最高地形，基座整体向下埋入坡地；
	#      不再把低处填到最高处，而是把台面作为“挖到顶”的基准，四周用草坡过渡（P2 建过渡网格）。
	var plateau := env_hmax - 0.04
	var podium_depth := plateau - env_hmin
	var platform_cut := env_hmax - plateau
	var platform_ok := platform_cut <= max_cut and podium_depth <= max_podium
	if not platform_ok:
		fail += 1
	checks.append({"id": "level_podium", "pass": platform_ok,
		"detail": "single-level top=%.3f m; terrain envelope [%.3f, %.3f]; cut_top=%.3f m (<=%.2f, no terrain rewrite); podium_depth_down=%.3f m (<=%.2f, hidden below grade); terrain slope=%.1fdeg (for edge transition)" % [
			plateau, env_hmin, env_hmax, platform_cut, max_cut, podium_depth, max_podium, env_slope]})

	# ---- 与门廊 / 花圃 / 既有菜地 / 房屋 / 树的距离 ----
	var d_porch := 1e9
	var d_house := 1e9
	var d_garden := 1e9
	var d_field := 1e9
	var d_tree := 1e9
	var c_local := center
	var cr := deg_to_rad(rot_deg)
	for cf in _perimeter_points(hp, 0.10):
		var cc := cf as Vector2
		var l := Vector2(c_local.x + cc.x * cos(cr) - cc.y * sin(cr), c_local.y + cc.x * sin(cr) + cc.y * cos(cr))
		var w := _l2w(l.x, l.y)
		d_porch = minf(d_porch, _rect_point_dist(l, -4.30, 4.30, 3.40, 7.45))
		d_house = minf(d_house, _rect_point_dist(l, -M.HOUSE_W * 0.5, M.HOUSE_W * 0.5, -M.HOUSE_D * 0.5, M.HOUSE_D * 0.5))
		d_garden = minf(d_garden, _rect_point_dist(w, IsleWorld.GARDEN_X0, IsleWorld.GARDEN_X1, IsleWorld.GARDEN_Z0, IsleWorld.GARDEN_Z1))
		d_field = minf(d_field, _rect_point_dist(w, IsleWorld.FIELD_X0, IsleWorld.FIELD_X1, IsleWorld.FIELD_Z0, IsleWorld.FIELD_Z1))
		d_tree = minf(d_tree, IsleWorld._tree_min_dist(w.x, w.y))
	var dist_ok := d_porch >= 0.45 and d_garden >= 0.40 and d_field >= 0.40 and d_house >= 0.45
	if not dist_ok:
		soft_fail += 1
	checks.append({"id": "clearances", "pass": dist_ok,
		"detail": "porch=%.2f house=%.2f garden=%.2f field=%.2f tree=%.2f (require porch>=0.45 garden>=0.40 field>=0.40 house>=0.45)" % [
			d_porch, d_house, d_garden, d_field, d_tree]})

	var d_lamp := 1e9
	if not _lamps.is_empty():
		for cf in _perimeter_points(hf, 0.25):
			var cc := cf as Vector2
			var w := _f2w(center, cc.x, cc.y)
			for lp in _lamps:
				var l3 := lp as Vector3
				d_lamp = minf(d_lamp, Vector2(w.x - l3.x, w.y - l3.z).length())
	var lamp_ok := _lamps.is_empty() or d_lamp >= 0.30
	if not lamp_ok:
		soft_fail += 1
	checks.append({"id": "lamp_clear", "pass": lamp_ok,
		"detail": "nearest lamp to fence edge=%.2f m (>=0.30; P9 不新增路灯，light_sources 预算 8 不变)" % d_lamp})

	var fence_ok := min_fence_pc >= min_path_clear
	if not fence_ok:
		fail += 1
	checks.append({"id": "fence_off_path", "pass": fence_ok,
		"detail": "min fence path_clearance=%.3f (>=%.2f) at local=(%.2f,%.2f)" % [min_fence_pc, min_path_clear, worst_pc.x, worst_pc.y]})

	var gate_world := _f2w(center, 0.0, -hf)
	var gate_pc: float = IsleWorld._path_clearance(gate_world.x, gate_world.y)
	var gate_ok := gate_pc <= 1.20
	if not gate_ok:
		soft_fail += 1
	checks.append({"id": "gate_stub_path_needed", "pass": gate_ok,
		"detail": "gate world=(%.2f,%.2f) path_clearance=%.3f -> 门到路缘需 %.2f m 连接小径/踏步（P2 建）" % [
			gate_world.x, gate_world.y, gate_pc, maxf(0.0, gate_pc)]})

	var hspread := hmax - hmin
	# 九格全部落在同一个水平台面上：台面以上只允许极浅的切方；地形高差由台面以下的基座吸收。
	var cell_cut_max := 0.0
	for c in cells:
		cell_cut_max = maxf(cell_cut_max, float((c as Dictionary)["surface_y"]) - plateau)
	var level_ok := cell_cut_max <= max_cut
	if not level_ok:
		fail += 1
	checks.append({"id": "nine_cell_level_bench", "pass": level_ok,
		"detail": "all 9 cells share bench top=%.3f m; max terrain above bench under cells=%.3f m (<=%.2f cut); terrain spread under cells=%.3f m absorbed below bench" % [
			plateau, cell_cut_max, max_cut, hspread]})

	var in_plot := 0
	var in_fence := 0
	var per_node: Dictionary = {}
	var scatter_pts: Array = []
	for nd in _scatter_nodes:
		var nm := String(nd["name"])
		var pos: PackedVector3Array = nd["pos"]
		var c_plot := 0
		for p in pos:
			var f := _w2f(center, p.x, p.z)
			var inside_plot := absf(f.x) <= hp and absf(f.y) <= hp
			var inside_fence := absf(f.x) <= hf and absf(f.y) <= hf
			if inside_plot:
				c_plot += 1
				in_plot += 1
				if scatter_pts.size() < 60:
					scatter_pts.append({"node": nm, "x": p.x, "z": p.z, "field": [f.x, f.y]})
			elif inside_fence:
				in_fence += 1
		if c_plot > 0:
			per_node[nm] = c_plot
	# 散布在 headless 下取不到真实 MultiMesh 变换（dummy RenderingServer 全返回 0），
	# 因此这里只判断"是否真实测得"，测得后按 P2 排除方案（_in_farm）处理，不算硬冲突。
	var scatter_ok := scatter_measured
	var sdet := "UNMEASURED: headless dummy MultiMesh 变换全 0，须窗口模式复测"
	if scatter_measured:
		sdet = "instances inside plot=%d (fence ring only=%d) per_node=%s -> P2 需 _in_farm 排除" % [in_plot, in_fence, JSON.stringify(per_node)]
	checks.append({"id": "scatter_measured", "pass": scatter_ok, "detail": sdet})

	var bloom_inside := 0
	var bloom_in_cells := 0
	var bloom_list: Array = []
	for b in _blooms:
		var bp: Vector3 = b["pos"]
		var f := _w2f(center, bp.x, bp.z)
		var inside := absf(f.x) <= hp and absf(f.y) <= hp
		if inside:
			bloom_inside += 1
		if absf(f.x) <= hc + 0.02 and absf(f.y) <= hc + 0.02:
			bloom_in_cells += 1
		bloom_list.append({"world": [bp.x, bp.y, bp.z], "field": [f.x, f.y], "inside_plot": inside})
	# v4：用户 2026-10-23 决定"红花不要了"——5 株冬季红花全部删除（P2 删除 world.gd:1094-1100 的锚点），
	# 因此不再有移栽/避让约束；探针只保留原位置记录，检查项改为"按用户决定删除"。
	var bloom_moves: Array = []
	var bloom_move_ok := true
	var bloom_move_max := 0.0
	var moved := 0
	var kept_outside := 0
	var bloom_ok := true
	var orig_txt: Array = []
	for b in _blooms:
		var bp0: Vector3 = b["pos"]
		orig_txt.append("(%.3f, %.3f)" % [bp0.x, bp0.z])
	var bloom_detail := "user decision 2026-10-23: %d 株红花全部删除，不再移栽/避让；预览隐藏全部实例；P2 删除 world.gd:1094-1100 的锚点；原世界 XZ=%s" % [
		_blooms.size(), ", ".join(orig_txt)]
	checks.append({"id": "winter_bloom_removed_by_user", "pass": true, "detail": bloom_detail})

	var corners_world: Array = []
	for cf in [Vector2(-hf, -hf), Vector2(hf, -hf), Vector2(hf, hf), Vector2(-hf, hf)]:
		var cc := cf as Vector2
		var w := _f2w(center, cc.x, cc.y)
		corners_world.append({"world_xz": [w.x, w.y], "surface_y": IsleWorld.surface_y(w.x, w.y)})

	var fail_total := fail + soft_fail
	return {
		"center_local": [center.x, center.y],
		"center_world": [_l2w(center.x, center.y).x, _l2w(center.x, center.y).y],
		"fail_count": fail_total,
		"hard_fail": fail,
		"checks": checks,
		"cells": cells,
		"half_cells": hc, "half_plot": hp, "half_fence": hf,
		"gate_world": [gate_world.x, 0.0, gate_world.y],
		"gate_path_clearance": gate_pc,
		"height_spread": hspread, "max_slope_deg": max_slope, "cell_dh_max": cell_dh_max,
		"cell_path_clear_min": min_cell_pc,
		"min_fence_path_clear": min_fence_pc,
		"min_fence_path_clear_at": [worst_pc.x, worst_pc.y],
		"envelope_height_spread": env_dh, "envelope_max_slope_deg": env_slope,
		"envelope_mean_tilt_deg": env_tilt,
		"platform_y": plateau, "platform_fill": podium_depth, "platform_cut": platform_cut, "max_podium": max_podium, "max_cut": max_cut,
		"pitch": _pitch(),
		"dist_porch": d_porch, "dist_house": d_house, "dist_garden": d_garden,
		"dist_field": d_field, "dist_tree": d_tree, "dist_lamp": d_lamp,
		"scatter_inside": in_plot, "scatter_fence_ring": in_fence,
		"scatter_by_node": per_node, "scatter_samples": scatter_pts,
		"bloom_inside": bloom_inside, "bloom_in_cells": bloom_in_cells, "blooms": bloom_list, "bloom_moves": bloom_moves,
		"bloom_plan_ok": bloom_ok, "bloom_moved_max": bloom_move_max, "bloom_moved": moved, "bloom_kept_outside": kept_outside,
		"corners_world": corners_world,
	}


# ============================================================ best pick ====
func _score(rr: Dictionary) -> float:
	var cl := rr["center_local"] as Array
	# 用户要求：整体做大、离开房屋更远（横向纵向都向外）。偏好区中心 (-3.2, lz 12.6)。
	var off := Vector2(cl[0], cl[1]).distance_to(Vector2(-4.0, 13.2))
	return float(rr["hard_fail"]) * 1000.0 + float(rr["bloom_inside"]) * 30.0 \
		+ float(rr["platform_fill"]) * 12.0 + float(rr["platform_cut"]) * 200.0 \
		+ float(rr["envelope_max_slope_deg"]) * 3.0 + off * 8.0


func _search_mode() -> Array:
	var found: Array = []
	# v3：用户要求再向“房子对面”外移 1 m（田心目标 lz 13.2），因此搜索区间随之外移；
	# 横向 -5.0..-1.6（再往左是内陆巨石组/灯塔基座），纵向 12.4..14.2。
	var lx := -5.0
	while lx <= -1.6:
		var lz := 12.4
		while lz <= 14.2:
			found.append(_eval_candidate(Vector2(lx, lz)))
			lz += 0.2
		lx += 0.2
	var feasible: Array = []
	for r in found:
		var rr := r as Dictionary
		rr["score"] = _score(rr)
		if int(rr["hard_fail"]) == 0:
			feasible.append(rr)
	found.sort_custom(func(a, b): return float((a as Dictionary)["score"]) < float((b as Dictionary)["score"]))
	feasible.sort_custom(func(a, b): return float((a as Dictionary)["score"]) < float((b as Dictionary)["score"]))
	print("[FARMSITE] search grid: evaluated=%d feasible(hard_fail=0)=%d params gap=%.2f cell=%.2f border=%.2f" % [
		found.size(), feasible.size(), gap, cell, border])
	for i in range(mini(10, found.size())):
		var rr := found[i] as Dictionary
		var cl := rr["center_local"] as Array
		print("[FARMSITE] top%02d local=(%.2f,%.2f) score=%.1f hard=%d blooms=%d env_dh=%.3f env_slope=%.1f clr=%.2f" % [
			i + 1, cl[0], cl[1], float(rr["score"]), int(rr["hard_fail"]), int(rr["bloom_inside"]),
			float(rr["envelope_height_spread"]), float(rr["envelope_max_slope_deg"]), float(rr["min_fence_path_clear"])])
	var sj := {"params": {"gap": gap, "cell": cell, "border": border, "rot": rot_deg},
		"thresholds": {"max_env_dh": max_env_dh, "max_env_slope": max_env_slope, "min_path_clear": min_path_clear, "max_cut": max_cut, "max_podium": max_podium},
		"evaluated": found.size(), "feasible": feasible.size(),
		"top": found.slice(0, mini(40, found.size()))}
	var fp2 := FileAccess.open(out_dir + "/search_results.json", FileAccess.WRITE)
	if fp2 != null:
		fp2.store_string(JSON.stringify(sj, "  "))
		fp2.close()
		print("[FARMSITE] wrote search_results.json")
	var start_i := 0
	if feasible.size() > 0:
		# 先输出可行解，再补最不坏解作对比
		var out_list: Array = feasible.slice(0, mini(12, feasible.size()))
		var remain := 12 - out_list.size()
		for i in range(found.size()):
			if remain <= 0:
				break
			var rr2 := found[i] as Dictionary
			if int(rr2["hard_fail"]) == 0:
				continue
			out_list.append(rr2)
			remain -= 1
		return out_list
	return found.slice(0, mini(12, found.size()))

func _pick_best(results: Array) -> Dictionary:
	if results.is_empty():
		return {}
	var best: Dictionary = results[0]
	var best_score := 1e9
	for r in results:
		var rr := r as Dictionary
		var score := _score(rr)
		if score < best_score:
			best_score = score
			best = rr
	best["score"] = best_score
	return best


# ====================================================== temp preview viz ==
func _mat(col: Color) -> Material:
	return M.toon_material(col, {"bands": 4.0, "soft": 0.55, "rim": 0.10})


func _add_box(parent: Node3D, nm: String, c: Vector3, size: Vector3, col: Color, rot: Vector3 = Vector3.ZERO) -> void:
	var mi := M.box_rot(parent, size, c, col, rot, {"rim": 0.05})
	mi.name = nm


func _add_cyl(parent: Node3D, nm: String, c: Vector3, r: float, h: float, col: Color) -> void:
	var mi := M.cyl(parent, r, r, h, c, col)
# ---- 圆角台面 / 石砌基座 / 围栏网格工具（仅临时可视化；不写场景、不改地形权威函数） ----

func _mk_mesh(parent: Node3D, nm: String, verts: PackedVector3Array, idx: PackedInt32Array, col: Color,
		vcols: PackedColorArray = PackedColorArray(), uvs: PackedVector2Array = PackedVector2Array(),
		mat: Material = null) -> MeshInstance3D:
	# 用 SurfaceTool 逐个三角加顶点并生成法线：ArrayMesh 只给 VERTEX 时 toon 着色器没有 NORMAL 会发黑/不可见。
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 每个三角按正反两种绕序各发一次：背面剔除下任一视角只会画出朝向相机的一份，
	# 因此不会 z-fighting，同时从根本上避免手写网格绕序错误导致的“看不见”。
	var has_col := vcols.size() == verts.size()
	var has_uv := uvs.size() == verts.size()
	for t in range(0, idx.size(), 3):
		var ia := idx[t]
		var ib := idx[t + 1]
		var ic := idx[t + 2]
		for ii in [ia, ib, ic, ia, ic, ib]:
			if has_col:
				st.set_color(vcols[ii])
			if has_uv:
				st.set_uv(uvs[ii])
			st.add_vertex(verts[ii])
	st.generate_normals()
	var am: ArrayMesh = st.commit()
	# 每个逻辑三角按正反绕序各发了 3 个顶点，故逻辑三角形数 = 索引数 / 6。
	_preview_tris += int(idx.size() / 6)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = _mat(col) if mat == null else mat
	parent.add_child(mi)
	# add_child 之后再设唯一名：同名节点会被 Godot 自动改名为 @FenceRail@N，
	# 导致 begins_with("FenceRail") 的平行性检查漏检 75/76 根横杆（D8 M1）。
	var name_i := int(_mesh_name_counts.get(nm, 0))
	_mesh_name_counts[nm] = name_i + 1
	mi.name = nm if name_i == 0 else "%s_%02d" % [nm, name_i]
	return mi


func _fl2world(center: Vector2, off: Vector2) -> Vector2:
	var l := Vector2(center.x + off.x, center.y + off.y)
	return _l2w(l.x, l.y)


func _local_pos_world(center: Vector2, off: Vector2) -> Vector3:
	var a := _l2w(center.x + off.x, center.y + off.y)
	var b := _l2w(center.x, center.y)
	return Vector3(a.x - b.x, 0.0, a.y - b.y)


## 圆角矩形轮廓（field 局部 xz，逆时针），四边与四角各自细分。
func _rr_outline(half: Vector2, radius: float, seg_side: int, seg_corner: int) -> Array:
	var r := maxf(0.01, minf(radius, minf(half.x, half.y) * 0.9))
	var cx := half.x - r
	var cz := half.y - r
	var pts: Array = []
	for k in range(seg_side):
		var t := float(k) / float(seg_side)
		pts.append(Vector2(half.x, lerpf(-cz, cz, t)))
	for k in range(seg_corner + 1):
		var a := lerpf(0.0, PI * 0.5, float(k) / float(seg_corner))
		pts.append(Vector2(cx + r * cos(a), cz + r * sin(a)))
	for k in range(1, seg_side):
		var t := float(k) / float(seg_side)
		pts.append(Vector2(lerpf(cx, -cx, t), half.y))
	for k in range(seg_corner + 1):
		var a := lerpf(PI * 0.5, PI, float(k) / float(seg_corner))
		pts.append(Vector2(-cx + r * cos(a), cz + r * sin(a)))
	for k in range(1, seg_side):
		var t := float(k) / float(seg_side)
		pts.append(Vector2(-half.x, lerpf(cz, -cz, t)))
	for k in range(seg_corner + 1):
		var a := lerpf(PI, PI * 1.5, float(k) / float(seg_corner))
		pts.append(Vector2(-cx + r * cos(a), -cz + r * sin(a)))
	for k in range(1, seg_side):
		var t := float(k) / float(seg_side)
		pts.append(Vector2(lerpf(-cx, cx, t), -half.y))
	for k in range(seg_corner):
		var a := lerpf(PI * 1.5, TAU, float(k) / float(seg_corner))
		pts.append(Vector2(cx + r * cos(a), -cz + r * sin(a)))
	return pts


## 圆角台面/土床：顶面 + 倒角环 + 侧壁（顶点为 field 局部坐标，节点只绕 Y 旋转 yaw）。
func _add_slab(parent: Node3D, nm: String, center: Vector2, half: Vector2, radius: float,
		y_top: float, depth: float, bevel: float, col: Color, rot_y: float,
		seg_side: int = 12, seg_corner: int = 6) -> MeshInstance3D:
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	var outer := _rr_outline(half, radius, seg_side, seg_corner)
	var inner := _rr_outline(Vector2(maxf(0.02, half.x - bevel), maxf(0.02, half.y - bevel)),
		maxf(0.01, radius - bevel), seg_side, seg_corner)
	var n := outer.size()
	verts.append(Vector3(0.0, y_top, 0.0))
	var top_start := verts.size()
	for q in inner:
		var qq := q as Vector2
		verts.append(Vector3(qq.x, y_top, qq.y))
	for i in range(n):
		var ai := top_start + i
		var bi := top_start + (i + 1) % n
		idx.append_array([0, bi, ai])
	var mid_start := verts.size()
	for q in outer:
		var qq := q as Vector2
		verts.append(Vector3(qq.x, y_top - bevel, qq.y))
	for i in range(n):
		var a0 := top_start + i
		var a1 := top_start + (i + 1) % n
		var b0 := mid_start + i
		var b1 := mid_start + (i + 1) % n
		idx.append_array([a0, b0, b1, a0, b1, a1])
	var bot_start := verts.size()
	var y_bot := y_top - depth
	for q in outer:
		var qq := q as Vector2
		verts.append(Vector3(qq.x, y_bot, qq.y))
	for i in range(n):
		var a0 := mid_start + i
		var a1 := mid_start + (i + 1) % n
		var b0 := bot_start + i
		var b1 := bot_start + (i + 1) % n
		idx.append_array([a0, b1, b0, a0, a1, b1])
	var mi := _mk_mesh(parent, nm, verts, idx, col)
	mi.rotation = Vector3(0.0, rot_y, 0.0)
	return mi


## （v4 已不再使用；保留作历史对照）旧草裙过渡：环向 n 段、径向 rings 圈，逐点采样 surface_y。
func _add_skirt(parent: Node3D, nm: String, center: Vector2, base_pos: Vector3, half: Vector2, radius: float,
		y0: float, d1: float, rings: int, seg_side: int, seg_corner: int, col: Color, rot_y: float) -> void:
	var outline := _rr_outline(half, radius, seg_side, seg_corner)
	var n := outline.size()
	var normals: Array = []
	for i in range(n):
		var prev := outline[(i - 1 + n) % n] as Vector2
		var next := outline[(i + 1) % n] as Vector2
		var tan := (next - prev).normalized()
		var nrm := Vector2(tan.y, -tan.x)
		if nrm.dot(outline[i] as Vector2) < 0.0:
			nrm = -nrm
		normals.append(nrm)
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	var vcols := PackedColorArray()
	var uvs := PackedVector2Array()
	# 台面外沿的“贴地圆角”：内圈贴在台面侧壁基部（高出自然地面 0.55 m，被 clamp 到台面下 0.02），
	# 外圈落到自然地形 +0.02；径向 1.60 m / 8 圈（72 段/圈），坡度更缓、面数足够，而不是一整块水平外沿。
	# 用户 m01333 要求“做好田周边地形的边缘过渡，面数要足够”，故此处优先用多圈多段平滑下降。
	for ri in range(rings + 1):
		var t := float(ri) / float(rings)
		var d := d1 * t
		for i in range(n):
			var p := (outline[i] as Vector2) + (normals[i] as Vector2) * d
			var w := _fl2world(center, p)
			var te: float = IsleWorld.surface_y(w.x, w.y)
			var y_in := clampf(te + 0.55, te + 0.02, y0 - 0.02)
			var y := lerpf(y_in, te + 0.02, smoothstep(0.0, 1.0, t))
			verts.append(Vector3(p.x, y, p.y))
			var tc := Color(0.53, 0.62, 0.42)
			var ter: Color = IsleWorld._terrain_color(w.x, w.y, te, 0.0, 0.72)
			tc = tc.lerp(ter, smoothstep(0.0, 0.75, t))
			vcols.append(tc)
			uvs.append(Vector2(w.x, w.y) * 0.09)
	for ri in range(rings):
		for i in range(n):
			var a0 := ri * n + i
			var a1 := ri * n + (i + 1) % n
			var b0 := (ri + 1) * n + i
			var b1 := (ri + 1) * n + (i + 1) % n
			idx.append_array([a0, a1, b0, b0, a1, b1])
	var mat := M.toon_material(Color.WHITE, {"vertex_color": true, "bands": 4.0, "soft": 0.55, "rim": 0.10})
	var mi := _mk_mesh(parent, nm, verts, idx, col, vcols, uvs, mat)
	mi.position = base_pos
	mi.rotation = Vector3(0.0, rot_y, 0.0)


## 横杆：沿 field 局部方向的八棱柱（圆木条观感）。
func _add_rail(parent: Node3D, center: Vector2, base_pos: Vector3, a: Vector2, b: Vector2, y: float, r: float,
		col: Color, rot_y: float) -> void:
	var dir := b - a
	var length := dir.length()
	if length < 0.02:
		return
	var seg := 8
	var side := Vector2(-dir.y, dir.x) / length
	var base_a := Vector3(a.x, y, a.y)
	var base_b := Vector3(b.x, y, b.y)
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	for k in range(seg):
		var ang := TAU * float(k) / float(seg)
		var offv := Vector3(side.x * cos(ang) * r, sin(ang) * r, side.y * cos(ang) * r)
		verts.append(base_a + offv)
	for k in range(seg):
		var ang := TAU * float(k) / float(seg)
		var offv := Vector3(side.x * cos(ang) * r, sin(ang) * r, side.y * cos(ang) * r)
		verts.append(base_b + offv)
	for k in range(seg):
		var k2 := (k + 1) % seg
		idx.append_array([k, k2, seg + k2, k, seg + k2, seg + k])
	var mi := _mk_mesh(parent, "FenceRail", verts, idx, col)
	mi.position = base_pos
	mi.rotation = Vector3(0.0, rot_y, 0.0)


## 临时可视化（v4 镶嵌式）：嵌坡草台 + 垂直石砌基座 + 圆角土床 + 圆木围栏。
## 仍是“单块水平台面、无阶梯”；台面以下向下发展，台面外沿向下/向外过渡到自然地形。仅本次运行存在，不写场景。
func _build_preview(rec: Dictionary) -> void:
	var cl := rec["center_local"] as Array
	var center := Vector2(cl[0], cl[1])
	var hf: float = rec["half_fence"]
	var plateau: float = rec["platform_y"]
	var podium_depth: float = rec["platform_fill"]
	var cut: float = rec["platform_cut"]
	_preview_tris = 0
	var node := Node3D.new()
	node.name = "P9FarmPreview"
	_main.add_child(node)
	var grass := Color(0.57, 0.68, 0.40)
	var grass_side := Color(0.42, 0.50, 0.33)
	var soil_rim := Color(0.70, 0.50, 0.33)
	var soil_top := Color(0.65, 0.45, 0.29)
	var stone := Color(0.72, 0.70, 0.64)
	var wood := Color(0.65, 0.47, 0.31)
	# box_rot / 网格节点：局部 +X 经 rotation.y=yaw 后 = 田块帧 +X；yaw = HOUSE_YAW - rot。
	var yaw := M.HOUSE_YAW - deg_to_rad(rot_deg)
	var cw := _f2w(center, 0.0, 0.0)
	var base_pos := Vector3(cw.x, 0.0, cw.y)
	var podium_half := hf + 0.10
	var base_depth := maxf(1.20, podium_depth + 0.80)
	# 2) v4 镶嵌关系（用户 2026-10-23 指示）：田台整体嵌入坡地——
	#    草台顶面与上坡侧地面基本齐平，下坡侧露出垂直石砌基座；基座插入地形，无草裙、无阶梯。
	var top := _add_slab(node, "PodiumTop", center, Vector2(podium_half, podium_half), 0.52,
		plateau, 0.32, 0.06, grass, yaw, 12, 6)
	top.position = base_pos
	var base := _add_slab(node, "PodiumBase", center, Vector2(podium_half, podium_half), 0.10,
		plateau - 0.30, base_depth, 0.02, stone, yaw, 12, 6)
	base.position = base_pos
	# 3) 九格土床：圆角、微微高出草台；格心距 pitch，九格同一标高
	for j in range(3):
		for i in range(3):
			var off := Vector2(float(i - 1) * _pitch(), float(j - 1) * _pitch())
			var pw := base_pos + _local_pos_world(center, off)
			var rim := _add_slab(node, "SoilRim_%d_%d" % [i, j], center, Vector2(0.57, 0.57), 0.18,
				plateau + 0.055, 0.06, 0.02, soil_rim, yaw, 8, 6)
			rim.position = pw
			var bed := _add_slab(node, "SoilTop_%d_%d" % [i, j], center, Vector2(0.52, 0.52), 0.15,
				plateau + 0.20, 0.16, 0.05, soil_top, yaw, 8, 6)
			bed.position = pw
	# 4) 围栏线：不铺石砌底沿（参考图田2 是木柱直接立在草台上），只记录四条边与门洞。
	var sides: Array = [
		[Vector2(-hf, -hf), Vector2(hf, -hf)],
		[Vector2(-hf, hf), Vector2(hf, hf)],
		[Vector2(-hf, -hf), Vector2(-hf, hf)],
		[Vector2(hf, -hf), Vector2(hf, hf)],
	]
	var gate_half := gate_w * 0.5
	# 5) 围栏：柱高 0.80 m、柱距 ~0.70 m、两道圆木横杆；门开在 -fz（房屋/门廊一侧）
	var post_h := 0.80
	var rail_hs := [0.34, 0.64]
	for si in range(4):
		var seg := sides[si] as Array
		var p0 := seg[0] as Vector2
		var p1 := seg[1] as Vector2
		var segs: Array = [[p0, p1]]
		if si == 0:
			segs = [[p0, Vector2(-gate_half, -hf)], [Vector2(gate_half, -hf), p1]]
		for sg in segs:
			var a := (sg as Array)[0] as Vector2
			var b := (sg as Array)[1] as Vector2
			var length := a.distance_to(b)
			if length < 0.05:
				continue
			var nposts := maxi(2, int(ceil(length / 0.70)) + 1)
			for s in range(nposts):
				var t := float(s) / float(nposts - 1)
				var cf := a.lerp(b, t)
				var w := _f2w(center, cf.x, cf.y)
				_add_cyl(node, "FencePost", Vector3(w.x, plateau + post_h * 0.5, w.y), 0.045, post_h, wood)
			var nseg := maxi(1, int(ceil(length / 0.60)))
			for s in range(nseg):
				var t0 := float(s) / float(nseg)
				var t1 := float(s + 1) / float(nseg)
				var fa := a.lerp(b, t0)
				var fb := a.lerp(b, t1)
				for rh in rail_hs:
					_add_rail(node, center, base_pos, fa, fb, plateau + float(rh), 0.030, wood, yaw)
	# 6) 大门 -> 主路的小径：台面外沿直接嵌入地形（上坡侧与地面齐平），门外铺一排贴地石板连接主路
	var path_len := 2.40
	var nslab := 8
	for s in range(nslab):
		var d := 0.16 + float(s) * (path_len - 0.16) / float(nslab - 1)
		var w := _f2w(center, 0.0, -hf - d)
		var h := IsleWorld.surface_y(w.x, w.y)
		var ptop := maxf(h + 0.05, plateau - 0.06)
		_add_box(node, "GatePath", Vector3(w.x, ptop - 0.030, w.y), Vector3(0.86, 0.07, 0.26),
			Color(0.78, 0.75, 0.68), Vector3(0.0, yaw, 0.0))
	_preview_geo = {"objects": node.get_child_count(), "triangles": _preview_tris,
		"podium_half": podium_half, "podium_radius": 0.52, "podium_bevel": 0.02,
		"embed_mode": "inlaid: pad top near uphill ground, vertical stone base sunk into slope, no skirt",
		"pad_thickness": 0.32, "base_depth": base_depth, "base_top_y": plateau - 0.30,
		"platform_y": plateau, "podium_down": podium_depth, "platform_cut": cut,
		"post_h": post_h, "rail_heights": rail_hs, "post_spacing": 0.70,
		"soil_top_y": plateau + 0.20, "soil_rim_top_y": plateau + 0.055,
		"gate_path_len": float(rec["gate_path_clearance"]),
		"gate_gap_remaining": maxf(0.0, float(rec["gate_path_clearance"]) - 2.40),
		"forced_weather": "clear (runtime _weather.set_manual_type; no settings write)"}
	print("[FARMSITE] preview built (v4 inlaid): half_fence=%.2f gate=%.2f plateau=%.3f cut=%.3f podium_down=%.3f pitch=%.2f objects=%d tris=%d" % [
		hf, gate_w, plateau, cut, podium_depth, _pitch(), node.get_child_count(), _preview_tris])
	_mask_scatter(center)


## 平行性运行期实测：直接读取已实例化的预览节点 global_transform，比较其局部 X 轴与田块帧 X 轴。
## 方形/长条构件按 90° 周期取最小偏差；阈值 0.5°。这是对“所有构件与围栏平行”的硬验证，不依赖截图目视。
func _check_preview_parallel(rec: Dictionary) -> void:
	var node := _main.get_node_or_null("P9FarmPreview") as Node3D
	if node == null:
		_check("preview_parallel", false, "P9FarmPreview 未创建")
		return
	var expect := deg_to_rad(rot_deg) - M.HOUSE_YAW
	var u := Vector3(cos(expect), 0.0, sin(expect))
	var up := Vector3(-u.z, 0.0, u.x)
	# 按族计数与逐族最大偏差：同名节点在 add_child 后被唯一化，必须按前缀归族（D8 M1）。
	var fams := ["PodiumTop", "SoilRim", "SoilTop", "FenceRail", "GatePath"]
	var expect_counts := {"PodiumTop": 1, "SoilRim": 9, "SoilTop": 9, "FenceRail": 76, "GatePath": 8}
	var counts := {}
	var fam_dev := {}
	var fam_worst := {}
	for k in fams:
		counts[k] = 0
		fam_dev[k] = 0.0
		fam_worst[k] = ""
	for ch in node.get_children():
		var mi := ch as Node3D
		if mi == null:
			continue
		var nm := String(mi.name)
		var fam := ""
		for k in fams:
			if nm.begins_with(k):
				fam = k
				break
		if fam == "":
			continue
		counts[fam] = int(counts[fam]) + 1
		var ax := mi.global_transform.basis.x
		ax.y = 0.0
		if ax.length() < 0.01:
			continue
		ax = ax.normalized()
		var dotp := maxf(absf(ax.dot(u)), absf(ax.dot(up)))
		var ed := rad_to_deg(acos(clampf(dotp, 0.0, 1.0)))
		if ed > float(fam_dev[fam]):
			fam_dev[fam] = ed
			fam_worst[fam] = "%s %.2fdeg" % [nm, ed]
	var max_err := 0.0
	var worst := ""
	var total := 0
	var cov_ok := true
	var cov_txt: Array = []
	for k in fams:
		total += int(counts[k])
		var d := float(fam_dev[k])
		if d > max_err:
			max_err = d
			worst = str(fam_worst[k])
		if int(counts[k]) != int(expect_counts[k]):
			cov_ok = false
		cov_txt.append("%s %d/%d %.3f" % [k, int(counts[k]), int(expect_counts[k]), d])
	# 横杆圆木的方向已烘焙进顶点，basis 只反映节点 yaw；因此本检查覆盖"各构件族的放置朝向"，
	# 不覆盖横杆顶点几何自身的摆向（顶点在 _add_rail 里按 a->b 构造）。
	_check("preview_parallel", max_err <= 0.5 and cov_ok,
		"boxes=%d/103 covered=%s max_dev=%.3f deg (<=0.50) worst=%s | %s" % [
			total, str(cov_ok), max_err, worst, " ".join(cov_txt)])


## 仅为截图临时隐藏落在田块内的草/三叶草（P2 会用 _in_farm 排除实现同样效果；不写文件）。
## 隐藏前记录原始 transform，_unmask_scatter() 可原样恢复（v4 只遮田台足迹内草，通常无需恢复）。
func _mask_scatter(center: Vector2) -> void:
	# v4：只掩蔽田台足迹（草台 + 石基）。镶嵌模式下真实草紧贴基座生长是"嵌入地面"观感的一部分；
	# P2 的 _in_farm 排除矩形同样只需覆盖田台足迹（见报告 P2 执行清单）。
	var hp := _half_fence() + 0.14
	var moved_grass := 0
	for nd in _scatter_nodes:
		var nm := String(nd["name"])
		var mmi := nd.get("node") as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null:
			continue
		# 只遮蔽草/三叶草；红花由 _hide_winter_blooms() 按用户决定全部隐藏。
		var is_grass := nm.begins_with("Grass") or nm.begins_with("Clover")
		if not is_grass:
			continue
		var mm := mmi.multimesh
		for i in range(mm.instance_count):
			var t: Transform3D = mm.get_instance_transform(i)
			var wp: Vector3 = mmi.global_transform * t.origin
			if wp.y < -400.0:
				continue
			var fl := _w2f(center, wp.x, wp.z)
			if absf(fl.x) <= hp and absf(fl.y) <= hp:
				_masked_saved.append([mm, i, t])
				t.origin.y -= 500.0
				mm.set_instance_transform(i, t)
				moved_grass += 1
	print("[FARMSITE] preview mask: grass/clover hidden=%d (runtime-only, saved=%d, not saved to disk)" % [moved_grass, _masked_saved.size()])
	_hide_winter_blooms()


## v4：5 株冬季红花按用户 2026-10-23 决定全部删除（P2 删除 world.gd:1094-1100 的 5 个锚点）。
## 预览里把全部冬花实例隐藏，截图不再出现红花；仅运行期改 MultiMesh，不写文件、不改季节状态。
func _hide_winter_blooms() -> int:
	var n := 0
	for nd in _scatter_nodes:
		var nm := String(nd["name"])
		if not (nm.begins_with("WinterBloom")):
			continue
		var mmi := nd.get("node") as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null:
			continue
		var mm := mmi.multimesh
		for i in range(mm.instance_count):
			var t: Transform3D = mm.get_instance_transform(i)
			if t.origin.y < -400.0:
				continue
			_masked_saved.append([mm, i, t])
			t.origin.y -= 500.0
			mm.set_instance_transform(i, t)
			n += 1
	print("[FARMSITE] winter blooms hidden by user decision: %d (P2 删除锚点；仅运行期)" % n)
	return n


# ============================================================== screenshots =
func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var tex: ViewportTexture = root.get_texture()
	var img: Image = tex.get_image() if tex != null else null
	if img == null:
		_check("shot_" + tag, false, "viewport texture null")
		return
	var fn := tag_prefix + tag + ".png"
	var path := out_dir + "/shots/" + fn
	var err: int = img.save_png(path)
	print("[FARMSITE] shot %s %dx%d err=%d path=%s" % [tag, img.get_width(), img.get_height(), err, path])
	_check("shot_" + tag, err == OK, path)
	if err == OK:
		_shots.append({"tag": tag, "path": path, "size": [img.get_width(), img.get_height()]})


func _settle(sec: float) -> void:
	await create_timer(sec).timeout


func _pose_play_default() -> void:
	_main.set("_theta", M.CAM_START_THETA)
	_main.set("_elev", 0.28)
	_main.set("_radius", M.CAM_START_R)
	_main.set("_cam_target", M.CAM_TARGET)
	_main.set("_fov", 42.0)
	_main.call("_apply_pose", _main.call("_play_pose"))


func _shots_for(rec: Dictionary) -> void:
	var cl := rec["center_local"] as Array
	var center := Vector2(cl[0], cl[1])
	var cw := _f2w(center, 0.0, 0.0)
	# 田块整体坐落在单一水平基座上，机位高度以基座顶面（platform_y）为准，而不是中心点地形高度。
	var cy: float = rec["platform_y"]
	var fp := Vector3(cw.x, cy, cw.y)
	var v := Vector3(sin(M.CAM_START_THETA), 0.0, cos(M.CAM_START_THETA)).normalized()
	var hf: float = rec["half_fence"]
	var gate := rec["gate_world"] as Array

	# D10 M5：直接改运行期 _weather，不经过 _on_weather_type_requested。
	# 原因：main.gd:1801 会在该函数内把 _settings_save_delay 置 0.25，随后 _tick 调 Settings.save_settings，
	# 可写机器上会用"默认设置 + clear 天气"覆盖玩家 user://settings.cfg。本探针只允许运行期渲染，禁止写用户设置。
	var wry = _main.get("_weather")
	if wry != null and wry.has_method("set_manual_type"):
		wry.set_manual_type("clear")
		_main.set("_settings_save_delay", -1.0)
		if _main.has_method("_update_weather"):
			_main.call("_update_weather", 0.0, true)
		_shots_weather = "clear (runtime _weather.set_manual_type; no settings write)"
		print("[FARMSITE] shots weather state: %s" % str(_main.get("_weather_state")))
		await _settle(0.6)

	_pose_play_default()
	await _settle(0.7)
	await _shot("01_env_default_wide")

	_main.call("_pose_look", fp + v * 17.0 + Vector3(0.0, 7.5, 0.0), fp + Vector3(0.0, 0.7, 0.0), 40.0)
	await _settle(0.5)
	await _shot("02_env_field_context")

	_main.call("_pose_look", fp + v * 8.0 + Vector3(0.0, 4.4, 0.0), fp + Vector3(0.0, 0.5, 0.0), 46.0)
	await _settle(0.5)
	await _shot("03_near_nine_cells")

	_main.call("_pose_look", fp + v * 6.0 + Vector3(0.0, 9.0, 0.0), fp + Vector3(0.0, 0.4, 0.0), 52.0)
	await _settle(0.5)
	await _shot("04_high_cells_readability")

	_main.call("_pose_look", fp + v * (hf + 3.2) + Vector3(0.0, 1.45, 0.0), fp + Vector3(0.0, 0.45, 0.0), 52.0)
	await _settle(0.5)
	await _shot("05_fence_occlusion_eye_level")

	_main.call("_pose_look", Vector3(gate[0], IsleWorld.surface_y(gate[0], gate[2]) + 1.65, gate[2]) - v * 5.0,
		Vector3(cw.x, cy + 0.6, cw.y), 48.0)
	await _settle(0.5)
	await _shot("06_from_road_gate")

	# 07 正俯视：只看九格划分与入口（临时测试机位，不改默认值）
	_main.call("_pose_look", fp + Vector3(0.02, 13.0, 0.02), fp, 40.0)
	await _settle(0.5)
	await _shot("07_topdown_nine_cells")

	# 08 房屋/门廊一侧看田地（对应"从房子往外看"）。
	# 注意：不能用 fp + hdir*9 逼近房屋——房屋前立面距田仅约 2.5 m，会穿进屋内（旧版错误）。
	# 机位由 C2 视觉复核用投影法给出，实测无遮挡。
	# 机位放在默认相机反方向（即房屋/门廊一侧），抬高 3.2 m 越过门廊柱；旧 08A 数值 (2.425,4.654) 的视线被门廊/路灯柱挡住。
	var hc := _l2w(0.0, 0.0)
	var hdir := Vector3(hc.x - fp.x, 0.0, hc.y - fp.z).normalized()
	_main.call("_pose_look", fp - v * 7.5 + Vector3(0.0, 3.2, 0.0), Vector3(fp.x, fp.y + 0.5, fp.z), 48.0)
	await _settle(0.5)
	await _shot("08_from_house_side")

	# 09 人眼高度站在门口小径上看（检查相机侧围栏是否挡住格子）
	_main.call("_pose_look", fp - Vector3(hdir.x, 0.0, hdir.z) * 3.4 + Vector3(0.0, 1.45, 0.0), fp + Vector3(0.0, 0.35, 0.0), 52.0)
	await _settle(0.5)
	await _shot("09_gate_eye_level_view")

	# 10 四要素环境图：房屋 + 主路 + 四花床 + 旧菜地 + 新田同框（临时测试机位）
	_main.call("_pose_look", Vector3(30.78, 30.94, -11.97), Vector3(0.80, 8.95, -0.60), 52.0)
	await _settle(0.6)
	await _shot("10_env_four_elements")

	# 11 入口/门廊侧：从房屋一侧退到大门外 4.6 m、高 2.0 m 俯视，检查镶嵌台面、门洞、踏步与门廊/主路的衔接（红花已按用户决定删除）
	var gv11 := Vector3(float(gate[0]), float(rec["platform_y"]), float(gate[2]))
	_main.call("_pose_look", gv11 + hdir * 4.6 + Vector3(0.0, 2.0, 0.0),
		gv11 + Vector3(0.0, 0.45, 0.0), 55.0)
	await _settle(0.5)
	await _shot("11_gate_porch_approach")

	# 12 默认机位 + 1440x900 视口（玩家常见窗口尺寸），检查 HUD 之外的真实构图比例
	DisplayServer.window_set_size(Vector2i(1440, 900))
	await process_frame
	_pose_play_default()
	await _settle(0.8)
	await _shot("12_env_default_1440x900")
	DisplayServer.window_set_size(Vector2i(1600, 1000))
	await process_frame
	await _settle(0.4)

	# 13 大门 -> 主路衔接（站在门内侧向外看那 0.70 m 需要铺踏步的空隙）
	var gv := Vector3(float(gate[0]), float(rec["platform_y"]), float(gate[2]))
	var outw := (gv - fp).normalized()
	# 站在门外 3.2 m、高 3.2 m 俯视门洞，同框拍到门内九格、门外踏步与主路边缘
	_main.call("_pose_look", gv + outw * 3.2 + Vector3(0.0, 3.2, 0.0),
		gv + Vector3(0.0, 0.20, 0.0), 50.0)
	await _settle(0.5)
	await _shot("13_gate_to_road")

	# 14 下坡侧镶嵌：站在台面外侧下坡 4.5 m、眼高 1.25 m，检查石砌基座垂直插入地形、草紧贴基座
	var down := Vector3(-hdir.x, 0.0, -hdir.z).normalized()
	_main.call("_pose_look", fp + down * (hf + 4.5) + Vector3(0.0, 1.25, 0.0),
		fp + down * (hf + 0.10) + Vector3(0.0, -0.35, 0.0), 55.0)
	await _settle(0.5)
	await _shot("14_edge_transition_downhill")

	# 15 上坡侧齐平：从房屋/上坡一侧低机位看草台顶面与坡地齐平相接（镶嵌关系，无草裙、无外凸挡土墙）
	_main.call("_pose_look", fp + hdir * (hf + 2.0) + Vector3(0.0, 1.05, 0.0),
		fp + hdir * (hf + 0.05) + Vector3(0.0, -0.15, 0.0), 58.0)
	await _settle(0.5)
	await _shot("15_edge_transition_uphill")

	# 16 P8.1 冻结机位同机位实拍（scripts/main.gd:6961-6966）：仅运行期摆机位，不写 p81 冻结证据目录。
	# v4：5 株红花按用户决定删除，机位处现为空草坪；保留同机位确认田块围栏/台面是否进入该构图。
	var p81_t := Vector3(0.82, 7.80, 9.13)
	var p81_f := Vector3(sin(M.HOUSE_YAW), 0.0, cos(M.HOUSE_YAW))
	var p81_r := Vector3(cos(M.HOUSE_YAW), 0.0, -sin(M.HOUSE_YAW))
	_main.call("_pose_look", p81_t + p81_f * 6.2 + p81_r * 2.2 + Vector3(0.0, 2.6, 0.0), p81_t, 42.0)
	await _settle(0.6)
	await _shot("16_p8_1_frozen_pose")

	# 17 下坡侧镶嵌细节：贴近石砌基座与草地交界（真实草紧贴基座，无草裙、无阶梯）
	_main.call("_pose_look", fp + down * (hf + 2.2) + Vector3(0.0, 1.10, 0.0),
		fp + down * (hf + 0.02) + Vector3(0.0, -0.55, 0.0), 60.0)
	await _settle(0.5)
	await _shot("17_embed_base_detail")

	# 18 上坡侧齐平细节：草台顶面与坡地齐平相接（镶嵌关系）
	_main.call("_pose_look", fp + hdir * (hf + 1.35) + Vector3(0.0, 1.15, 0.0),
		fp + hdir * (hf - 0.10) + Vector3(0.0, 0.10, 0.0), 60.0)
	await _settle(0.5)
	await _shot("18_embed_flush_detail")

	_pose_play_default()
	await _settle(0.4)


# ================================================================ outputs ==
func _write_json(rec: Dictionary, results: Array) -> void:
	var ct: Vector3 = _main.get("_cam_target")
	var doc := {
		"probe": "probe_p9_farm_site",
		"generated_at_utc": Time.get_datetime_string_from_system(true),
		"godot_version": String(Engine.get_version_info()["string"]),
		"display": DisplayServer.get_name(),
		"params": {"center_override": [center_override.x, center_override.y] if center_override != Vector2.INF else null,
			"rot_deg": rot_deg, "gap": gap, "cell": cell, "border": border, "gate_w": gate_w,
		"plot_margin": border,
		"thresholds_note": "Lead 设定（用户拍板 m01333 + m02048）：田块水平是必须的；v4 改为镶嵌关系——草台顶面与上坡侧地面基本齐平，下坡侧露出垂直石砌基座并向下插入坡地，不做草裙、不做阶梯。5 株红花按用户 2026-10-23 决定删除。格 1.0m、格间净距 0.50m、外圈走道 0.65m、围栏高 0.80m；沿路余量>=0.90m。cut<=0.30m（只切最高处极浅一层，不改地形权威函数）、podium_down<=1.95m（向下埋深上限）。阈值不是物理定律，出处见 farm_site_report.md §4/§7；max_env_dh/max_env_slope 仅为信息项（代码不据此判 FAIL）。",
		"geometry_note": "gap 语义 = 相邻耕格之间的净空隙；格心距 pitch = cell + gap。",

			"search": do_search},
		"thresholds": {"max_env_dh": max_env_dh, "max_env_slope": max_env_slope, "min_path_clear": min_path_clear, "max_cut": max_cut, "max_podium": max_podium},
		"scatter_measured": scatter_measured,
		"probe_file": {"path": "res://tools/probe_p9_farm_site.gd",
			"sha256": FileAccess.get_sha256("res://tools/probe_p9_farm_site.gd")},
		"camera_default": {"target": [ct.x, ct.y, ct.z], "theta": M.CAM_START_THETA, "elev": 0.28, "r": M.CAM_START_R, "fov": 42.0},
		"recommended": rec,
		"candidates": results,
		"shots_weather": _shots_weather,
		"preview_geometry": _preview_geo,
		"github": _git_info(),
		"summary": {"checks": _pass + _fail, "pass": _pass, "fail": _fail},
		"shots": _shots,
		"checks": _checks,
		"notes": _notes,
	}
	var f := FileAccess.open(out_dir + "/farm_site_report.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(doc, "  "))
		f.close()
		print("[FARMSITE] wrote farm_site_report.json")


func _git_info() -> Dictionary:
	var out: Array = []
	var branch := ""
	var head := ""
	var dirty: Array = []
	if OS.execute("git", ["-C", "D:/休闲小岛幻境/游戏工程", "status", "--porcelain=v1", "-b"], out, true) == 0 and out.size() > 0:
		var lines := String(out[0]).split("\n")
		for i in range(lines.size()):
			var ln := String(lines[i]).strip_edges()
			if ln == "":
				continue
			if i == 0:
				branch = ln
			else:
				dirty.append(ln)
	var out2: Array = []
	if OS.execute("git", ["-C", "D:/休闲小岛幻境/游戏工程", "rev-parse", "HEAD"], out2, true) == 0 and out2.size() > 0:
		head = String(out2[0]).strip_edges()
	return {"branch": branch, "head": head, "dirty": dirty, "dirty_count": dirty.size()}


func _write_md(rec: Dictionary, results: Array) -> void:
	var L: Array = []
	L.append("# P9-P0 农田选址测量结果（探针原始输出）")
	L.append("")
	L.append("- 由 tools/probe_p9_farm_site.gd 在真实 isle.tscn 运行时生成")
	L.append("- Godot: %s；Display: %s" % [String(Engine.get_version_info()["string"]), DisplayServer.get_name()])
	L.append("- 布局参数：rotation=%.2f°、单格 %.3f m、格间净距 %.2f m、格心距 %.2f m、外圈走道 %.3f m、门宽 %.2f m、围栏高 %.2f m" % [rot_deg, cell, gap, _pitch(), border, gate_w, 0.80])
	L.append("- 判据来源（Lead 设定，非物理定律）：整块田单一水平台面，台面以下基座向下发展、不做阶梯；台面切方 <= %.2f m（不改地形权威函数）、向下埋深 <= %.2f m；沿路余量 >= %.2f m。说明见 farm_site_report.md §4/§7。" % [max_cut, max_podium, min_path_clear])

	L.append("")
	L.append("## 候选评测汇总")
	L.append("")
	L.append("| 候选 local | 失败项 | 散布侵入 | 花卉侵入 | 高差 m | 最大坡度° | 世界 XZ |")
	L.append("| --- | --- | --- | --- | --- | --- | --- |")
	for r in results:
		var rr := r as Dictionary
		var cl := rr["center_local"] as Array
		var cwt := rr["center_world"] as Array
		L.append("| (%.2f, %.2f) | %d | %d | %d | %.3f | %.1f | (%.2f, %.2f) |" % [cl[0], cl[1], rr["fail_count"], rr["scatter_inside"], rr["bloom_inside"], rr["height_spread"], rr["max_slope_deg"], cwt[0], cwt[1]])
	L.append("")
	var rc := rec["center_local"] as Array
	var rw := rec["center_world"] as Array
	L.append("## 推荐布局")
	L.append("")
	L.append("- 房屋局部中心 (lx, lz) = (%.3f, %.3f)" % [rc[0], rc[1]])
	L.append("- 世界中心 XZ = (%.3f, %.3f)" % [rw[0], rw[1]])
	L.append("- 旋转 %.2f°（相对房屋局部帧，所有格/草台/围栏共用一个朝向）；单格 %.3f m；格间净距 %.2f m；格心距 %.2f m" % [rot_deg, cell, gap, _pitch()])
	L.append("- 九格外沿半宽 %.3f m（格心 ±%.2f、格尺寸 %.3f ⇒ 外沿=pitch+cell/2）；外圈走道 %.3f m；土床半宽 %.3f m；围栏半宽 %.3f m；整体占地 %.2f × %.2f m" % [
		rec["half_cells"], _pitch(), cell, border, rec["half_plot"], rec["half_fence"], float(rec["half_fence"]) * 2.0, float(rec["half_fence"]) * 2.0])

	L.append("- 门口世界 XZ = (%.3f, %.3f)，围栏线到道路边缘总距 %.3f m（预览临时踏步覆盖 %.2f m，剩余约 %.2f m 由 P2 小径补齐）" % [
		(rec["gate_world"] as Array)[0], (rec["gate_world"] as Array)[2], rec["gate_path_clearance"],
		float(_preview_geo.get("gate_path_len", 2.40)), float(_preview_geo.get("gate_gap_remaining", 0.75))])
	var soil_top: float = float(_preview_geo.get("soil_top_y", float(rec["platform_y"]) + 0.20))
	L.append("- 水平台面顶面 = %.3f m；地形起伏 %.3f m 由“台面嵌入坡地”吸收（草台顶面与上坡侧地面基本齐平，下坡侧露出垂直石砌基座；基座向下插入地形 podium_down=%.3f m，名义切方 cut=%.3f m；不做草裙、不做阶梯）；土床顶面 = %.3f m（土床厚 0.16，底面 %.3f m）；单格最大地形四角高差 %.3f m（已被水平台面吸收）" % [
		rec["platform_y"], rec["height_spread"], rec["platform_fill"], rec["platform_cut"], soil_top, soil_top - 0.16, rec["cell_dh_max"]])
	L.append("- 切方语义：cut 为名义值——最高包络点地形（%.3f m）比台面（%.3f m）高 %.3f m；P2 需切掉这薄薄一层或允许凸出（不改地形权威函数）" % [
		float(rec["platform_y"]) + float(rec["platform_cut"]), rec["platform_y"], rec["platform_cut"]])
	L.append("- 最近路灯到围栏边缘 %.2f m（P9 不新增路灯）" % rec["dist_lamp"])
	if _preview_geo.size() > 0:
		L.append("- 预览视觉几何（P2 施工参照，v4 镶嵌式）：%d 个对象、%d 个三角形；台面圆角 r=%.2f、倒角 %.2f；草台厚 %.2f m、石砌基座向下 %.2f m（基座顶面 %.3f m，垂直插入地形）；围栏柱高 %.2f m、柱距 %.2f m、横杆高度 %s" % [
			int(_preview_geo["objects"]), int(_preview_geo["triangles"]), float(_preview_geo["podium_radius"]), float(_preview_geo["podium_bevel"]),
			float(_preview_geo["pad_thickness"]), float(_preview_geo["base_depth"]), float(_preview_geo["base_top_y"]),
			float(_preview_geo["post_h"]), float(_preview_geo["post_spacing"]), str(_preview_geo["rail_heights"])])
	L.append("- 围栏包络地形高差 %.3f m、最大地表坡度 %.1f°（均为信息项：基座已把整块做平，不做阶梯）" % [
		rec["envelope_height_spread"], rec["envelope_max_slope_deg"]])
	L.append("- 包络到道路最不利余量 %.3f m（阈值 %.2f，局部 %s）" % [
		rec["min_fence_path_clear"], min_path_clear, str(rec["min_fence_path_clear_at"])])
	L.append("- 散布实测=%s（headless=false 才能读真实 MultiMesh）" % str(scatter_measured))
	L.append("- 截图天气：%s（探针直接调用 _weather.set_manual_type(clear)，不经过 _on_weather_type_requested，因此不触发 Settings.save_settings，不写 user://settings.cfg）" % (_shots_weather if _shots_weather != "" else "未截图"))
	L.append("- 临时遮罩：截图时只隐藏田台足迹内（|field| <= half_fence+0.14）的草/三叶草；真实草紧贴石基生长，是镶嵌观感的一部分；5 株红花按用户决定在预览中全部隐藏（P2 删除锚点）")
	L.append("- 到门廊 %.2f m；到房屋 %.2f m；到花圃 %.2f m；到既有菜地 %.2f m" % [rec["dist_porch"], rec["dist_house"], rec["dist_garden"], rec["dist_field"]])
	L.append("")
	L.append("## 九格坐标表（推荐布局）")
	L.append("")
	L.append("| 格 (i,j) | 农田局部 | 房屋局部 | 世界 XZ | 地表高度 | 角点高差 | 最大坡度° | 道路余量 |")
	L.append("| --- | --- | --- | --- | --- | --- | --- | --- |")
	for c in rec["cells"]:
		var cc := c as Dictionary
		var fl := cc["field_local"] as Array
		var hl := cc["house_local"] as Array
		var wx := cc["world_xz"] as Array
		var chh := cc["corner_h"] as Array
		L.append("| (%d,%d) | (%.2f, %.2f) | (%.2f, %.2f) | (%.3f, %.3f) | %.3f | %.3f | %.1f | %.3f |" % [
			cc["i"], cc["j"], fl[0], fl[1], hl[0], hl[1], wx[0], wx[1], cc["surface_y"], float(chh[1]) - float(chh[0]), cc["max_slope_deg"], cc["path_clearance"]])
	L.append("")
	L.append("## 检查项")
	L.append("")
	for chk in _checks:
		var ck := chk as Dictionary
		L.append("- %s [%s] %s" % ["PASS" if ck["pass"] else "FAIL", ck["id"], ck["detail"]])
	L.append("")
	L.append("## 散布侵入明细（推荐布局）")
	L.append("")
	L.append("- 图内实例数 %d；围栏环内(不含图内) %d" % [rec["scatter_inside"], rec["scatter_fence_ring"]])
	L.append("- 按节点: %s" % JSON.stringify(rec["scatter_by_node"]))
	for sp in rec["scatter_samples"]:
		var d := sp as Dictionary
		var ff := d["field"] as Array
		L.append("  - %s world=(%.2f, %.2f) field=(%.2f, %.2f)" % [d["node"], d["x"], d["z"], ff[0], ff[1]])
	L.append("")
	L.append("## 冬季花卉（v4：按用户决定删除）")
	L.append("")
	L.append("- 用户 2026-10-23 指示“红花不要了”：5 株冬季红花全部删除，不再移栽/避让；P2 在 world.gd:1094-1100 删除对应 5 个锚点")
	L.append("- 原世界位置（供追溯）：")
	for b in rec["blooms"]:
		var bb := b as Dictionary
		var ww := bb["world"] as Array
		var ff := bb["field"] as Array
		L.append("  - world=(%.3f, %.3f, %.3f) field=(%.2f, %.2f) inside_plot=%s" % [ww[0], ww[1], ww[2], ff[0], ff[1], str(bb["inside_plot"])])
	L.append("")
	L.append("## 截图")
	L.append("")
	if _shots.is_empty():
		L.append("- 无（headless 模式或未启用 --p9shots；该部分为未验证）")
	for s in _shots:
		var sd := s as Dictionary
		L.append("- [%s](%s)" % [sd["tag"], sd["path"]])
	L.append("")
	L.append("## 说明 / 未验证项")
	L.append("")
	for n in _notes:
		L.append("- " + String(n))
	L.append("- 岛民接近点、最终入口朝向与围栏具体样式属于 P2 决策，本探针只验证空间可行性")
	L.append("- 探针不修改任何正式场景文件；候选田块仅为运行时临时可视化 P9FarmPreview，退出即消失")
	var f := FileAccess.open(out_dir + "/probe_p9_farm_site.md", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(L))
		f.close()
		print("[FARMSITE] wrote probe_p9_farm_site.md")


func _finish() -> void:
	print("[FARMSITE] SUMMARY checks=%d pass=%d fail=%d" % [_pass + _fail, _pass, _fail])
	print("[FARMSITE] RESULT %s pass=%d fail=%d" % ["PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit(0 if _fail == 0 else 1)
