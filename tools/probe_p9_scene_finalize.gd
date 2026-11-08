extends SceneTree
## P7-FINALIZE / P9 场景验收探针（农田围栏断口修复 + 花圃长椅删除 + 秋千无风摆幅收紧）。
##
## A. headless 数值验收（不建真实窗口）：
##   ENG --headless --path GAME --script res://tools/probe_p9_scene_finalize.gd -- --out=DIR
##   1) 门前农田围栏 facts：rail_count/post_count/gate_rails_skipped/gate_w/gate_center_world；
##      并用 posts_local 复核四边端点闭合（相邻边端点 <0.02m）与门洞两侧门柱；
##      另外直接读取 FrontYardFenceRails MultiMesh 复核 60 根横杆首尾相接、四角各 4 个端点。
##   2) 花圃旁旧长椅签名（1.70x0.10x0.44 / 1.70x0.42x0.09 / 0.12x0.42x0.40）必须消失；
##      门廊长椅座板 0.42x0.09x1.10（含靠背/腿）必须仍在 Cottage 门廊原位。
##   3) 秋千：_weather_visual_wind=0 跑 _update_props 20s，max|rotation.x| 落在 [5,10]°；
##      强风 0.92 再跑 20s，最大摆幅显著更大且单帧变化 <=2°、无 NaN；风降回 0 后 10s 内
##      平滑回到 5–10° 区间。
##
## B. 真实窗口截图（必须非 headless）：
##   ENG --path GAME --script res://tools/probe_p9_scene_finalize.gd -- --scene-shots --out=DIR
##   注意：不能直接用 --shots —— 那是 main.gd 的全局生产自动截图开关（main.gd:441/545），
##   出现在命令行时 main._ready() 会调用 _run_shots() 接管菜单/相机/时间并把 60+ 张图写到
##   D:/休闲小岛幻境/开发产物/shots/（不在本任务允许写盘范围内）。探针里的等价模式开关是
##   --scene-shots；若误传 --shots 会立即中止并提示（exit 3），避免污染生产截图目录。
##   截图落到 OUT/shots/：围栏正面全景、四角近景、门洞正面、原长椅位置、门廊长椅、秋千无风/强风。
##
## 只读生产脚本：唯一写入是 本探针自身 + OUT 目录内的 JSON/LOG/PNG。

const MainScene := preload("res://isle.tscn")
const MainScript := preload("res://scripts/main.gd")
const WorldScript := preload("res://scripts/world.gd")
const MathScript := preload("res://scripts/isle_math.gd")
const CottageScript := preload("res://scripts/cottage.gd")

const DT := 1.0 / 60.0
const WIND_STRONG := 0.92
const WD_135 := Vector2(0.70710678, 0.70710678)
const DEFAULT_OUT := "D:/休闲小岛幻境/开发产物/P9/P7-finalize/evidence/scene"
const SHOT_W := 1920
const SHOT_H := 1080
const OLD_BENCH_SITE := Vector2(-6.15, -2.30)
const PORCH_BENCH_LOCAL := Vector2(2.30, 3.80)   # cottage 局部帧；座板 y = house_ground + 0.42 + 0.45

var out_dir := DEFAULT_OUT
var shots_mode := false
var shots_flag_literal := false
var _pass := 0
var _fail := 0
var _fails: Array = []
var _checks: Array = []
var _lines: Array = []
var _notes: Array = []
var _shots: Array = []
var _facts: Dictionary = {}
var m: Node = null

var OLD_BENCH_SIGS: Array = [
	Vector3(1.70, 0.10, 0.44),
	Vector3(1.70, 0.42, 0.09),
	Vector3(0.12, 0.42, 0.40),
]
var PORCH_SEAT_SIG := Vector3(0.42, 0.09, 1.10)
var PORCH_BACK_SIG := Vector3(0.08, 0.50, 1.10)
var PORCH_LEG_SIG := Vector3(0.07, 0.42, 0.07)


# ============================================================ entry / args ==
func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--out="):
			out_dir = s.substr(6).strip_edges().trim_suffix("/").trim_suffix("\\")
		elif s == "--shots":
			shots_mode = true
			shots_flag_literal = true
		elif s == "--scene-shots":
			shots_mode = true
	if shots_mode and shots_flag_literal:
		# --shots 是 main.gd 的全局生产自动截图开关（main.gd:441/545）：一旦出现在命令行，
		# main._ready() 末尾会调用 _run_shots() 接管菜单/相机/时间并把 60+ 张图写到
		# D:/休闲小岛幻境/开发产物/shots/（不在本任务允许的写盘范围内）。它无法被探针安全拦截
		# （Engine.time_scale 在 4.7.2 实测不冻结 SceneTreeTimer），所以这里硬拒绝并给出等价命令。
		print("[ABORT] --shots 会被 main.gd 识别为生产自动截图流水线（_run_shots），与场景验收冲突。")
		print("[ABORT] 请改用等价的本探针开关：--scene-shots（参数完全一致，仅换成该词）。")
		print("[ABORT] e.g. ENG --path GAME --script res://tools/probe_p9_scene_finalize.gd -- --scene-shots --out=DIR")
		quit(3)
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	if shots_mode:
		DirAccess.make_dir_recursive_absolute(out_dir + "/shots")
	_run.call_deferred()


func _run() -> void:
	if shots_mode:
		await _run_visual()
	else:
		await _run_numeric()
	var ok := _fail == 0 and _pass > 0
	if shots_mode:
		ok = ok and _shots.size() >= 10
	print("[SUMMARY] mode=%s checks=%d pass=%d fail=%d shots=%d" % [
		"shots" if shots_mode else "numeric", _checks.size(), _pass, _fail, _shots.size()])
	print("[RESULT] %s" % ("PASS" if ok else "FAIL"))
	for line in _fails:
		print("[FAILED] " + String(line))
	_write_outputs()
	quit(0 if ok else 1)


# ================================================================ utilities ==
func _check(name: String, ok: bool, expected: String, actual: String) -> void:
	var line := "[CHECK] %s | expected=%s actual=%s | %s" % [name, expected, actual, "PASS" if ok else "FAIL"]
	print(line)
	_lines.append(line)
	_checks.append({"name": name, "ok": ok, "expected": expected, "actual": actual})
	if ok:
		_pass += 1
	else:
		_fail += 1
		_fails.append(line)


func _check_near(name: String, actual: float, expected: float, tol: float, unit := "") -> void:
	_check(name, is_finite(actual) and absf(actual - expected) <= tol,
		"%.6f%s ±%.6f" % [expected, unit, tol],
		("%.6f%s" % [actual, unit]) if is_finite(actual) else "NaN/inf")


func _info(msg: String) -> void:
	print("[INFO] " + msg)
	_lines.append("[INFO] " + msg)


func _section(title: String) -> void:
	print("=== " + title + " ===")
	_lines.append("=== " + title + " ===")


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _v2a(v: Vector2) -> Array:
	return [v.x, v.y]


func _v3a(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


func _l2w(p: Vector2) -> Vector2:
	return WorldScript._yard_l2w(p.x, p.y)


func _l2w_v3(p: Vector2, y: float) -> Vector3:
	var w := _l2w(p)
	return Vector3(w.x, y, w.y)


func _l2w_dir(lx: float, lz: float) -> Vector2:
	return WorldScript._yard_l2w(lx, lz) - WorldScript._yard_l2w(0.0, 0.0)


func _yard_corners_local() -> Array:
	var c: Vector2 = WorldScript.YARD_FARM_C
	var h: float = float(WorldScript.YARD_FENCE_HALF)
	var x0 := c.x - h
	var x1 := c.x + h
	var z0 := c.y - h
	var z1 := c.y + h
	return [Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)]


func _dist2_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	var t := 0.0
	if l2 > 1e-9:
		t = clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _dist_xz_seg(p: Vector3, a: Vector2, b: Vector2) -> float:
	return _dist2_seg(Vector2(p.x, p.z), a, b)


func _project_t(p: Vector3, a: Vector2, b: Vector2) -> float:
	var q := Vector2(p.x, p.z)
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-9:
		return 0.0
	return clampf((q - a).dot(ab) / l2, 0.0, 1.0)


func _mesh_box_size(mi: Node) -> Vector3:
	if mi is MeshInstance3D:
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh is BoxMesh:
			return (mesh as BoxMesh).size
		return Vector3.ZERO
	if mi is MultiMeshInstance3D:
		var mm: MultiMesh = (mi as MultiMeshInstance3D).multimesh
		if mm != null and mm.mesh is BoxMesh:
			return (mm.mesh as BoxMesh).size
	return Vector3.ZERO


func _collect_meshes(root: Node, out: Array) -> void:
	if root is MeshInstance3D or root is MultiMeshInstance3D:
		out.append(root)
	for c in root.get_children():
		_collect_meshes(c, out)


func _find_named(root: Node, want: String) -> Node:
	if String(root.name) == want:
		return root
	for c in root.get_children():
		var r := _find_named(c, want)
		if r != null:
			return r
	return null


func _has_ancestor_named(n: Node, want: String) -> bool:
	var p := n.get_parent()
	while p != null:
		if String(p.name) == want:
			return true
		p = p.get_parent()
	return false


func _bench_sig_index(size: Vector3, tol := 0.03) -> int:
	for i in range(OLD_BENCH_SIGS.size()):
		var s: Vector3 = OLD_BENCH_SIGS[i]
		if absf(size.x - s.x) <= tol and absf(size.y - s.y) <= tol and absf(size.z - s.z) <= tol:
			return i
	return -1


func _write_outputs() -> void:
	var stem := "probe_p9_scene_finalize" if not shots_mode else "probe_p9_scene_finalize_shots"
	var lf := FileAccess.open("%s/%s.log" % [out_dir, stem], FileAccess.WRITE)
	if lf != null:
		for line in _lines:
			lf.store_line(String(line))
		lf.close()
	var data := {
		"probe": "probe_p9_scene_finalize",
		"mode": "shots" if shots_mode else "numeric",
		"godot": String(Engine.get_version_info().get("string", "")),
		"display_server": DisplayServer.get_name(),
		"out_dir": out_dir,
		"timestamp": Time.get_datetime_string_from_system(),
		"pass": _pass, "fail": _fail, "checks_total": _checks.size(),
		"fails": _fails,
		"checks": _checks,
		"facts": _facts,
		"shots": _shots,
		"notes": _notes,
	}
	var jf := FileAccess.open("%s/%s.json" % [out_dir, stem], FileAccess.WRITE)
	if jf != null:
		jf.store_string(JSON.stringify(data, "  "))
		jf.close()
	print("[WRITE] %s/%s.json" % [out_dir, stem])
	print("[WRITE] %s/%s.log" % [out_dir, stem])


# ============================================================ A. numeric ====
func _run_numeric() -> void:
	_section("A0 environment")
	_info("godot=%s display=%s" % [String(Engine.get_version_info().get("string", "")), DisplayServer.get_name()])
	await process_frame
	await _diag_scene_tree_timer()

	# 门廊长椅的 BoxMesh 签名只有在“不合批”时仍以 MeshInstance3D 存在（生产默认合批）；
	# cottage.gd 提供探针专用静态开关，几何/材质/位置完全不变，仅关闭静态合批。仅 A 模式使用。
	CottageScript.probe_skip_batch = true
	m = MainScene.instantiate()
	get_root().add_child(m)
	await _frames(3)
	m.set_process(false)
	m.set_physics_process(false)
	var world: Dictionary = m.get("_world")
	_check("scene.world_built", not world.is_empty(), "world facts 非空", "keys=%d" % world.size())

	var fy: Dictionary = world.get("front_yard", {})
	_check("scene.front_yard", not fy.is_empty(), "front_yard facts 存在", "keys=%d" % fy.size())
	var fence: Dictionary = fy.get("fence", {})
	_check("scene.fence_facts", not fence.is_empty(), "fence facts 存在", "keys=%d" % fence.size())

	await _phase_fence(fy, fence)
	await _phase_post_closure(fy, fence)
	await _phase_rails(fy)
	await _phase_benches(fy)
	await _phase_swing()
	await _phase_facts(fy, fence)


func _diag_scene_tree_timer() -> void:
	var old := Engine.time_scale
	Engine.time_scale = 0.000001
	var t := create_timer(0.01, true)
	var before := t.time_left
	for i in range(10):
		await process_frame
	var after := t.time_left
	Engine.time_scale = old
	var frozen := absf(after - before) < 1e-9
	_info("DIAG SceneTreeTimer under Engine.time_scale=1e-6: time_left %.6f -> %.6f (%s)" % [
		before, after, "FROZEN(=scaled delta)" if frozen else "NOT-FROZEN"])
	_facts["diag_timer_frozen_by_time_scale"] = frozen


# ---------------------------------------------------------------- A1 fence --
func _phase_fence(fy: Dictionary, fence: Dictionary) -> void:
	_section("A1 fence facts / gate")
	var rail_count := int(fence.get("rail_count", -1))
	var post_count := int(fence.get("post_count", -1))
	var skipped := int(fence.get("gate_rails_skipped", -1))
	var gate_w := float(fence.get("gate_w", -1.0))
	var posts: Array = fence.get("posts_local", [])
	var gate_center: Vector2 = fence.get("gate_center_world", Vector2.ZERO)
	var gate_span: Array = fence.get("gate_span_world", [])
	var c: Vector2 = WorldScript.YARD_FARM_C
	var gate_half: float = gate_w * 0.5
	var z0 := c.y - float(WorldScript.YARD_FENCE_HALF)
	var expect_center := _l2w(Vector2(c.x, z0))

	_check("fence.rail_count", rail_count == 60, "60", str(rail_count))
	_check("fence.post_count", post_count == 34, "34", str(post_count))
	_check("fence.gate_rails_skipped", skipped == 2, "2", str(skipped))
	_check_near("fence.gate_w", gate_w, 1.10, 0.0005, "m")
	_check("fence.posts_local_size", posts.size() == post_count, "== post_count %d" % post_count, str(posts.size()))
	_check("fence.gate_span_count", gate_span.size() == 2, "2", str(gate_span.size()))
	if gate_span.size() == 2:
		var ga: Vector2 = gate_span[0]
		var gb: Vector2 = gate_span[1]
		_check_near("fence.gate_span_width", ga.distance_to(gb), 1.10, 0.01, "m")
		var mid := (ga + gb) * 0.5
		_check("fence.gate_center_is_span_mid", mid.distance_to(gate_center) <= 1e-4,
			"<=0.0001", "%.9f" % mid.distance_to(gate_center))
	_check("fence.gate_center_matches_house_frame", gate_center.distance_to(expect_center) <= 1e-4,
		"<=0.0001", "%.9f" % gate_center.distance_to(expect_center))
	var checks: Dictionary = fy.get("checks", {})
	_check("fence.gate_on_pad", bool(checks.get("pad_contains_gate", false)), "true", str(checks.get("pad_contains_gate", null)))
	var walk: Dictionary = fy.get("walkway", {})
	if walk.has("to_world"):
		var wto: Vector2 = walk["to_world"]
		_check("fence.gate_center_matches_walkway", wto.distance_to(gate_center) <= 1e-4,
			"<=0.0001", "%.9f" % wto.distance_to(gate_center))
	# 门柱必须在 posts_local 中，且位置=门洞两端
	for k in range(2):
		var gp := Vector2(c.x + (gate_half if k == 1 else -gate_half), z0)
		var best := 999.0
		for p in posts:
			best = minf(best, (p as Vector2).distance_to(gp))
		_check("fence.gate_post_present_%d" % k, best <= 0.02, "<=0.02", "%.5f" % best)
	# 横杆不得落在门洞净宽内（门洞保持通行）
	var opening := {"rails_in_gate": 0, "count": 0}
	var fy_node: Node3D = fy.get("node", null) as Node3D
	if fy_node != null:
		var rn := fy_node.get_node_or_null("FrontYardFenceRails") as MultiMeshInstance3D
		if rn != null and rn.multimesh != null:
			var mm := rn.multimesh
			for i in range(mm.instance_count):
				var mid2 := mm.get_instance_transform(i).origin
				var lq := Vector2(mid2.x, mid2.z)
				if _dist2_seg(lq, Vector2(c.x - gate_half, z0), Vector2(c.x + gate_half, z0)) < 0.05:
					if absf(lq.x - c.x) < gate_half - 0.01:
						opening["rails_in_gate"] = int(opening["rails_in_gate"]) + 1
				opening["count"] = int(opening["count"]) + 1
	_check("fence.gate_rails_absent_in_opening", int(opening["rails_in_gate"]) == 0,
		"0 根横杆落入门洞净宽内", str(opening["rails_in_gate"]))
	# 门柱 MultiMesh 数量
	if fy_node != null:
		var gn := fy_node.get_node_or_null("FrontYardGatePosts") as MultiMeshInstance3D
		var gcount := 0
		if gn != null and gn.multimesh != null:
			gcount = gn.multimesh.instance_count
		_check("fence.gate_post_multimesh_count", gcount == 2, "2", str(gcount))
	_facts["fence"] = {
		"rail_count": rail_count, "post_count": post_count,
		"gate_rails_skipped": skipped, "gate_w": gate_w,
		"gate_center_world": _v2a(gate_center),
		"gate_span_world": [[gate_span[0].x, gate_span[0].y], [gate_span[1].x, gate_span[1].y]] if gate_span.size() == 2 else [],
		"gate_post_local": [c.x - gate_half, c.x + gate_half, z0],
		"rails_in_gate_opening": opening["rails_in_gate"],
		"walkway_to_world": _v2a(walk.get("to_world", Vector2.ZERO)) if walk.has("to_world") else [],
	}


# ------------------------------------------------------- A2 post closure --
func _phase_post_closure(fy: Dictionary, fence: Dictionary) -> void:
	_section("A2 posts: four edges end-to-end closure")
	var posts_raw: Array = fence.get("posts_local", [])
	var posts: Array = []
	for p in posts_raw:
		if p is Vector2:
			posts.append(p)
	var corners := _yard_corners_local()
	var corner_min: Array = [99.0, 99.0, 99.0, 99.0]
	var corner_cnt: Array = [0, 0, 0, 0]
	for i in range(4):
		var cpt: Vector2 = corners[i]
		for p in posts:
			var d: float = (p as Vector2).distance_to(cpt)
			if d < float(corner_min[i]):
				corner_min[i] = d
			if d <= 0.02:
				corner_cnt[i] = int(corner_cnt[i]) + 1
	for i in range(4):
		_check("posts.corner_%d_closed" % i, float(corner_min[i]) <= 0.02,
			"corners 有柱 (<=0.02m)", "min_dist=%.5f count_within_0.02=%d" % [corner_min[i], corner_cnt[i]])
	# 相邻边端点：E_i 终点与 E_{i+1} 起点必须落在同一根角柱上（距离 <0.02）
	for i in range(4):
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var end_pt: Vector2 = b
		var start_pt: Vector2 = corners[(i + 1) % 4]
		var e_dist := end_pt.distance_to(start_pt)
		var near_end := 99.0
		var near_start := 99.0
		for p in posts:
			near_end = minf(near_end, (p as Vector2).distance_to(end_pt))
			near_start = minf(near_start, (p as Vector2).distance_to(start_pt))
		_check("posts.edge_%d_joins_next" % i, e_dist < 0.02 and near_end <= 0.02 and near_start <= 0.02,
			"end==start<0.02 且两侧都有柱", "end_to_start=%.6f post_end=%.5f post_start=%.5f" % [e_dist, near_end, near_start])
		# 边本身起终点都有柱
		_check("posts.edge_%d_endpoints_have_posts" % i, near_end <= 0.02 and near_start <= 0.02,
			"start/end <=0.02", "start=%.5f end=%.5f" % [near_start, near_end])
	# 每条边的柱距链（去重后）无 >0.72m 断口；近边门洞恰有一段 1.10m
	var edge_names := ["near(z0)", "east(x1)", "far(z1)", "west(x0)"]
	var edge_report: Array = []
	for e in range(4):
		var a2: Vector2 = corners[e]
		var b2: Vector2 = corners[(e + 1) % 4]
		var items: Array = []
		for p in posts:
			var q: Vector2 = p
			if _dist2_seg(q, a2, b2) < 0.05:
				items.append({"t": _project_t(Vector3(q.x, 0.0, q.y), a2, b2), "p": q})
		# insertion sort by t
		for ii in range(1, items.size()):
			var cur: Dictionary = items[ii]
			var jj := ii - 1
			while jj >= 0 and float(items[jj]["t"]) > float(cur["t"]):
				items[jj + 1] = items[jj]
				jj -= 1
			items[jj + 1] = cur
		# dedup coincident posts (corner shared between edges / C0 duplicated in posts list)
		var uniq: Array = []
		for it in items:
			var q2: Vector2 = it["p"]
			if uniq.is_empty() or q2.distance_to(uniq[uniq.size() - 1]["p"]) > 0.005:
				uniq.append(it)
		var gaps: Array = []
		for k in range(uniq.size() - 1):
			gaps.append((uniq[k + 1]["p"] as Vector2).distance_to(uniq[k]["p"] as Vector2))
		var max_gap := 0.0
		var big_gaps := 0
		var gate_gap := 0.0
		for g in gaps:
			max_gap = maxf(max_gap, float(g))
			if float(g) > 0.72:
				big_gaps += 1
			if float(g) >= 1.0 and float(g) <= 1.2:
				gate_gap = float(g)
		var start_err: float = 0.0
		var end_err: float = 0.0
		if uniq.size() > 0:
			start_err = (uniq[0]["p"] as Vector2).distance_to(a2)
			end_err = (uniq[uniq.size() - 1]["p"] as Vector2).distance_to(b2)
		var ok_chain := start_err <= 0.02 and end_err <= 0.02 and big_gaps == 0
		if e == 0:
			ok_chain = start_err <= 0.02 and end_err <= 0.02 and big_gaps == 1 \
				and gate_gap >= 1.09 and gate_gap <= 1.11
		_check("posts.edge_%d_chain" % e, ok_chain,
			("仅 1 段门洞 %.3fm" % 1.10) if e == 0 else "无 >0.72m 断口",
			"posts=%d uniq=%d max_gap=%.4f big_gaps=%d gate_gap=%.4f start=%.5f end=%.5f" % [
				items.size(), uniq.size(), max_gap, big_gaps, gate_gap, start_err, end_err])
		edge_report.append({"edge": e, "name": edge_names[e], "posts_spatial": items.size(),
			"posts_uniq": uniq.size(), "max_gap": max_gap, "big_gaps": big_gaps,
			"gate_gap": gate_gap, "start_err": start_err, "end_err": end_err})
	_facts["posts"] = {
		"count": posts.size(), "corner_min_dists": corner_min, "corner_counts_within_0.02": corner_cnt,
		"edges": edge_report,
	}


# ------------------------------------------------------------- A3 rails ----
func _phase_rails(fy: Dictionary) -> void:
	_section("A3 rails MultiMesh: continuous chain / four corners")
	var res := _analyze_rails(fy)
	_facts["rails"] = res
	if not bool(res.get("found", false)):
		_check("rails.node_present", false, "FrontYardFenceRails MultiMesh", str(res.get("errors", [])))
		return
	_check("rails.instance_count", int(res["instance_count"]) == 60, "60", str(res["instance_count"]))
	if bool(res.get("headless_dummy", false)):
		_info("SKIP rails 实例变换链：headless dummy renderer 不保留 MultiMesh 实例缓冲，改由 --scene-shots 真实窗口模式复核（B 段）")
		return
	var per_edge: Array = res.get("per_edge", [])
	var expect_counts := [12, 16, 16, 16]
	var total := 0
	for e in range(per_edge.size()):
		var pe: Dictionary = per_edge[e]
		total += int(pe.get("count", 0))
		_check("rails.edge_%d_count" % e, int(pe.get("count", -1)) == expect_counts[e],
			"*2 层 = %d" % expect_counts[e], str(pe.get("count", -1)))
	_check("rails.total", total == 60, "60", str(total))
	# 四角端点：每个角应各有 4 个横杆端点（2 条边 x 2 层）重合
	var corners_w: Array = []
	for p in _yard_corners_local():
		corners_w.append(_l2w(p))
	var corner_epc: Array = res.get("corner_endpoint_counts", [0, 0, 0, 0])
	for i in range(4):
		_check("rails.corner_%d_connect" % i, int(corner_epc[i]) == 4,
			"4 个横杆端点 (2 边 x 2 层)", str(corner_epc[i]))
	# 非门洞边逐层连续：首尾贴边、内部间隙 <0.02m
	for e in range(4):
		var pe: Dictionary = per_edge[e]
		var levels: Array = pe.get("levels", [])
		_check("rails.edge_%d_two_levels" % e, levels.size() == 2, "2 层 (+0.34/+0.64)", str(levels.size()))
		for li in range(levels.size()):
			var lv: Dictionary = levels[li]
			var name := "rails.edge_%d_level_%d" % [e, li]
			if e == 0:
				var gmid := Vector2.ZERO
				var run_info: Array = lv.get("runs", [])
				var ok_gate: bool = run_info.size() == 2
				if ok_gate:
					var r0: Dictionary = run_info[0]
					var r1: Dictionary = run_info[1]
					gmid = ((r0["end"] as Vector2) + (r1["start"] as Vector2)) * 0.5
					var gwidth: float = (r1["start"] as Vector2).distance_to(r0["end"] as Vector2)
					var gate_center: Vector2 = fy.get("fence", {}).get("gate_center_world", Vector2.ZERO)
					_check(name + "_gate_gap", absf(gwidth - 1.355) <= 0.02 and gmid.distance_to(gate_center) <= 0.02,
						"gap 1.355±0.02 且中点=门洞中心", "width=%.4f mid_dist=%.4f" % [gwidth, gmid.distance_to(gate_center)])
					_check(name + "_runs_start_end", float(r0.get("start_err", 9)) <= 0.02 and float(r1.get("end_err", 9)) <= 0.02,
						"左右跑段起止贴角柱 <=0.02", "left_start=%.4f right_end=%.4f" % [float(r0.get("start_err", 9)), float(r1.get("end_err", 9))])
			else:
				_check(name + "_continuous", float(lv.get("max_gap", 9)) < 0.02 \
						and float(lv.get("start_err", 9)) <= 0.02 and float(lv.get("end_err", 9)) <= 0.02,
					"max_gap<0.02 且首尾贴角柱", "max_gap=%.4f start=%.4f end=%.4f n=%d" % [
						float(lv.get("max_gap", 9)), float(lv.get("start_err", 9)), float(lv.get("end_err", 9)), int(lv.get("n", 0))])
			# 长度合法
			_check(name + "_lengths", bool(lv.get("length_ok", false)), "0.10m<len<1.45m 且无 NaN", str(lv.get("len_range", [])))
	# 顶部汇总 facts
	_facts["rails"] = res


func _analyze_rails(fy: Dictionary) -> Dictionary:
	var out := {"found": false, "instance_count": 0, "per_edge": [], "corner_endpoint_counts": [0, 0, 0, 0],
		"errors": [], "levels_separation": []}
	var fy_node: Node3D = fy.get("node", null) as Node3D
	if fy_node == null:
		out["errors"].append("front_yard.node 缺失")
		return out
	var rn := fy_node.get_node_or_null("FrontYardFenceRails") as MultiMeshInstance3D
	if rn == null or rn.multimesh == null:
		out["errors"].append("FrontYardFenceRails/MultiMesh 缺失")
		return out
	out["found"] = true
	var mm := rn.multimesh
	out["instance_count"] = mm.instance_count
	# headless dummy rendering server 不保留 MultiMesh 实例缓冲（get_instance_transform 全为 identity）。
	# 这种情况只校验 instance_count，横杆几何连续性改在 --scene-shots 真实窗口渲染下复核。
	var dummy := false
	if mm.instance_count > 0:
		var xf0: Transform3D = mm.get_instance_transform(0)
		dummy = xf0.origin.is_zero_approx() and xf0.basis.is_equal_approx(Basis.IDENTITY)
	out["headless_dummy"] = dummy
	var corners_local := _yard_corners_local()
	var corners_w: Array = []
	for p in corners_local:
		corners_w.append(_l2w(p))
	# per-instance classification
	var recs: Array = []
	var edge_ys: Array = [[], [], [], []]
	for i in range(mm.instance_count):
		var xf: Transform3D = mm.get_instance_transform(i)
		var axis: Vector3 = xf.basis.y
		var ln := axis.length()
		var mid := xf.origin
		var dirn := axis / ln if ln > 0.000001 else Vector3.ZERO
		var p0 := mid - dirn * (ln * 0.5)
		var p1 := mid + dirn * (ln * 0.5)
		var be := -1
		var bd := 1e9
		var bt := 0.0
		for e in range(4):
			var a2: Vector2 = corners_w[e]
			var b2: Vector2 = corners_w[(e + 1) % 4]
			var d := _dist_xz_seg(mid, a2, b2)
			if d < bd:
				bd = d
				be = e
				bt = _project_t(mid, a2, b2)
		if bd > 0.06:
			out["errors"].append("rail %d 不在四边上 dist=%.3f" % [i, bd])
			continue
		recs.append({"i": i, "edge": be, "t": bt, "len": ln, "y": mid.y, "p0": p0, "p1": p1, "mid": mid})
		(edge_ys[be] as Array).append(mid.y)
	# level split per edge: y 聚成 2 层（+0.34 / +0.64）
	var level_threshold: Array = [0.0, 0.0, 0.0, 0.0]
	var level_sep: Array = [0.0, 0.0, 0.0, 0.0]
	for e in range(4):
		var ys: Array = edge_ys[e]
		if ys.is_empty():
			out["errors"].append("edge %d 无横杆实例" % e)
			continue
		ys.sort()
		var split := 0.0
		for k in range(ys.size() - 1):
			split = maxf(split, float(ys[k + 1]) - float(ys[k]))
		level_sep[e] = split
		level_threshold[e] = float(ys[0]) + split * 0.5
	out["levels_separation"] = level_sep
	# build per edge/level buckets
	var buckets := {}
	for rec in recs:
		var e := int(rec["edge"])
		var lv := 0 if float(rec["y"]) <= float(level_threshold[e]) else 1
		rec["level"] = lv
		var key := "e%d_l%d" % [e, lv]
		if not buckets.has(key):
			buckets[key] = []
		(buckets[key] as Array).append(rec)
	var gate_center: Vector2 = fy.get("fence", {}).get("gate_center_world", Vector2.ZERO)
	for e in range(4):
		var a2: Vector2 = corners_w[e]
		var b2: Vector2 = corners_w[(e + 1) % 4]
		var edge_count := 0
		var levels_out: Array = []
		for lv in range(2):
			var key := "e%d_l%d" % [e, lv]
			var arr: Array = buckets.get(key, [])
			edge_count += arr.size()
			# insertion sort by t
			for ii in range(1, arr.size()):
				var cur: Dictionary = arr[ii]
				var jj := ii - 1
				while jj >= 0 and float(arr[jj]["t"]) > float(cur["t"]):
					arr[jj + 1] = arr[jj]
					jj -= 1
				arr[jj + 1] = cur
			var max_gap := 0.0
			var length_ok := true
			var lmin := 99.0
			var lmax := 0.0
			var runs: Array = []
			var cur_run := {"start": Vector2.ZERO, "end": Vector2.ZERO, "start_err": 0.0, "end_err": 0.0}
			for k in range(arr.size()):
				var r: Dictionary = arr[k]
				var ln2: float = r["len"]
				lmin = minf(lmin, ln2)
				lmax = maxf(lmax, ln2)
				if ln2 < 0.10 or ln2 > 1.45 or not is_finite(ln2):
					length_ok = false
				var q0 := Vector2((r["p0"] as Vector3).x, (r["p0"] as Vector3).z)
				var q1 := Vector2((r["p1"] as Vector3).x, (r["p1"] as Vector3).z)
				if k == 0:
					cur_run["start"] = q0
					cur_run["start_err"] = q0.distance_to(a2)
				else:
					var prev: Dictionary = arr[k - 1]
					var prev_end := Vector2((prev["p1"] as Vector3).x, (prev["p1"] as Vector3).z)
					var gap: float = q0.distance_to(prev_end)
					max_gap = maxf(max_gap, gap)
					if gap > 0.02:
						cur_run["end"] = prev_end
						cur_run["end_err"] = prev_end.distance_to(_corner_of_edge(e, 0))
						runs.append(cur_run)
						cur_run = {"start": q0, "end": Vector2.ZERO, "start_err": q0.distance_to(a2), "end_err": 0.0}
						cur_run["start"] = q0
				if k == arr.size() - 1:
					cur_run["end"] = q1
			if arr.size() > 0:
				var last_q1 := Vector2((arr[arr.size() - 1]["p1"] as Vector3).x, (arr[arr.size() - 1]["p1"] as Vector3).z)
				cur_run["end"] = last_q1
				cur_run["end_err"] = last_q1.distance_to(b2)
				runs.append(cur_run)
			if e != 0 and runs.size() == 1:
				runs[0]["start_err"] = runs[0]["start"].distance_to(a2)
				runs[0]["end_err"] = runs[0]["end"].distance_to(b2)
			levels_out.append({"level": lv, "n": arr.size(), "max_gap": max_gap,
				"start_err": float(runs[0]["start_err"]) if runs.size() > 0 else 9.0,
				"end_err": float(runs[runs.size() - 1]["end_err"]) if runs.size() > 0 else 9.0,
				"runs": runs, "length_ok": length_ok, "len_range": [lmin, lmax]})
		out["per_edge"].append({"edge": e, "count": edge_count, "levels": levels_out})
	# four corner endpoint counts (2 edges x 2 levels = 4 per corner)
	var epc := [0, 0, 0, 0]
	for rec in recs:
		for wp in [rec["p0"], rec["p1"]]:
			var q := Vector2((wp as Vector3).x, (wp as Vector3).z)
			for ci in range(4):
				if q.distance_to(corners_w[ci]) <= 0.02:
					epc[ci] = int(epc[ci]) + 1
	out["corner_endpoint_counts"] = epc
	return out


func _corner_of_edge(e: int, which: int) -> Vector2:
	var corners := _yard_corners_local()
	return _l2w(corners[(e + which) % 4])


# ------------------------------------------------------------ A4 benches ---
func _phase_benches(fy: Dictionary) -> void:
	_section("A4 benches: old garden bench removed / porch bench kept")
	var world_root: Node3D = null
	var world: Dictionary = m.get("_world")
	world_root = world.get("root", null) as Node3D
	if world_root == null:
		# fallback: find node named World
		world_root = _find_named(m, "World") as Node3D
	var garden := _find_named(world_root, "Garden") if world_root != null else null
	_check("garden.node_present", garden != null and garden is Node3D, "World/Garden Node3D", str(garden != null))
	_check("garden.parent_is_world", garden != null and _has_ancestor_named(garden, "World"), "Garden under World", str(garden != null))
	var garden_meshes: Array = []
	if garden != null:
		_collect_meshes(garden, garden_meshes)
	var old_matches: Array = []
	var closest := {"diff": 99.0, "size": Vector3.ZERO, "path": ""}
	for mi in garden_meshes:
		var sz := _mesh_box_size(mi)
		if sz == Vector3.ZERO:
			continue
		var idx := _bench_sig_index(sz)
		if idx >= 0:
			old_matches.append({"path": String(mi.get_path()), "size": _v3a(sz), "sig": idx})
		# closest signature distance (for diagnostics)
		for sig in OLD_BENCH_SIGS:
			var diff: float = absf(sz.x - sig.x) + absf(sz.y - sig.y) + absf(sz.z - sig.z)
			if diff < float(closest["diff"]):
				closest = {"diff": diff, "size": sz, "path": String(mi.get_path())}
	_check("garden.old_bench_absent", old_matches.is_empty(),
		"Garden 下无 BoxMesh 长椅签名", "matches=%d closest_sumdiff=%.4f size=%s path=%s" % [
			old_matches.size(), float(closest["diff"]), str(_v3a(closest["size"])), String(closest["path"])])
	# 全场景再扫一遍旧签名，但没有一个落在旧长椅位置附近（半径 1.0m）
	var all_meshes: Array = []
	_collect_meshes(m, all_meshes)
	var scene_matches: Array = []
	var near_site: Array = []
	for mi in all_meshes:
		var sz2 := _mesh_box_size(mi)
		if sz2 == Vector3.ZERO:
			continue
		var idx2 := _bench_sig_index(sz2)
		if idx2 >= 0:
			var gp: Vector3 = (mi as Node3D).global_position
			var rec := {"path": String(mi.get_path()), "size": _v3a(sz2), "world": _v3a(gp)}
			scene_matches.append(rec)
			if Vector2(gp.x, gp.z).distance_to(OLD_BENCH_SITE) <= 1.0:
				near_site.append(rec)
	_check("garden.old_bench_absent_near_site", near_site.is_empty(),
		"世界 XZ%s 半径 1m 内无长椅签名" % str(_v2a(OLD_BENCH_SITE)), "matches=%d" % near_site.size())
	_info("全场景长椅签名 MeshInstance 计数：%d（供参考；Garden 内必须为 0）" % scene_matches.size())
	# 旧长椅位置地形高度 / 周边网格（证据）
	var site_terrain: float = float(MathScript.terrain_height(OLD_BENCH_SITE.x, OLD_BENCH_SITE.y))
	var site_mesh_count := 0
	for mi in all_meshes:
		var gp2: Vector3 = (mi as Node3D).global_position
		if Vector2(gp2.x, gp2.z).distance_to(OLD_BENCH_SITE) <= 0.9:
			site_mesh_count += 1
	var pots := 0
	for mi in all_meshes:
		if mi is MeshInstance3D and (mi as MeshInstance3D).mesh is CylinderMesh:
			var cm := (mi as MeshInstance3D).mesh as CylinderMesh
			var gp3: Vector3 = (mi as Node3D).global_position
			if absf(cm.height - 0.34) <= 0.02 and Vector2(gp3.x, gp3.z).distance_to(OLD_BENCH_SITE) <= 2.5:
				pots += 1
	# 门廊长椅：Cottage 局部 (2.30, deck=0.42+0.45, 3.80)
	var gy: float = float(MathScript.house_ground_y())
	var expect_w2: Vector2 = _l2w(PORCH_BENCH_LOCAL)
	var expect_world := Vector3(expect_w2.x, gy + 0.42 + 0.45, expect_w2.y)
	var seat_hits: Array = []
	var back_hits: Array = []
	var leg_hits: Array = []
	for mi in all_meshes:
		var sz3 := _mesh_box_size(mi)
		if sz3 == Vector3.ZERO:
			continue
		var node3 := mi as Node3D
		var gp4: Vector3 = node3.global_position
		if absf(sz3.x - PORCH_SEAT_SIG.x) <= 0.01 and absf(sz3.y - PORCH_SEAT_SIG.y) <= 0.01 and absf(sz3.z - PORCH_SEAT_SIG.z) <= 0.01:
			seat_hits.append({"path": String(mi.get_path()), "world": _v3a(gp4), "dist": gp4.distance_to(expect_world), "cottage": _has_ancestor_named(mi, "Cottage")})
		elif absf(sz3.x - PORCH_BACK_SIG.x) <= 0.01 and absf(sz3.y - PORCH_BACK_SIG.y) <= 0.01 and absf(sz3.z - PORCH_BACK_SIG.z) <= 0.01:
			back_hits.append({"path": String(mi.get_path()), "world": _v3a(gp4), "dist": gp4.distance_to(expect_world)})
		elif absf(sz3.x - PORCH_LEG_SIG.x) <= 0.01 and absf(sz3.y - PORCH_LEG_SIG.y) <= 0.01 and absf(sz3.z - PORCH_LEG_SIG.z) <= 0.01:
			leg_hits.append({"path": String(mi.get_path()), "world": _v3a(gp4), "dist": gp4.distance_to(expect_world)})
	var seat_near := 0
	var seat_dist := 99.0
	for s in seat_hits:
		seat_dist = minf(seat_dist, float(s["dist"]))
		if float(s["dist"]) <= 0.15 and bool(s["cottage"]):
			seat_near += 1
	_check("porch_bench.seat_present", seat_near >= 1, "Cottage 门廊座板 0.42x0.09x1.10 在期望位置 ±0.15m",
		"seat_hits=%d near=%d min_dist=%.4f expect_world=%s" % [seat_hits.size(), seat_near, seat_dist, str(_v3a(expect_world))])
	var back_near := 0
	for b in back_hits:
		if float(b["dist"]) <= 0.4:
			back_near += 1
	_check("porch_bench.backrest_present", back_near >= 1, "靠背 0.08x0.50x1.10 在座板 0.4m 内", "back_hits=%d near=%d" % [back_hits.size(), back_near])
	var legs_near := 0
	for l in leg_hits:
		if float(l["dist"]) <= 0.6:
			legs_near += 1
	_check("porch_bench.legs_present", legs_near >= 4, "4 条腿 0.07x0.42x0.07 在座板 0.6m 内", "leg_hits=%d near=%d" % [leg_hits.size(), legs_near])
	# 门廊长椅不能被误判成旧长椅签名
	var porch_false := false
	for s in seat_hits:
		if _bench_sig_index(Vector3(PORCH_SEAT_SIG.x, PORCH_SEAT_SIG.y, PORCH_SEAT_SIG.z)) >= 0:
			porch_false = true
	_check("porch_bench.not_old_signature", not porch_false, "门廊座板尺寸不属于旧长椅签名", "false=%s" % str(porch_false))
	_facts["garden"] = {
		"node_path": String(garden.get_path()) if garden != null else "",
		"mesh_instance_count": garden_meshes.size(),
		"old_bench_matches": old_matches,
		"closest_box": {"sumdiff": float(closest["diff"]), "size": _v3a(closest["size"]), "path": String(closest["path"])},
		"old_bench_site_world_xz": _v2a(OLD_BENCH_SITE),
		"old_bench_site_terrain_y": site_terrain,
		"meshes_within_0.9m_of_site": site_mesh_count,
		"terracotta_pots_within_2.5m": pots,
	}
	_facts["porch_bench"] = {
		"seat_sig": _v3a(PORCH_SEAT_SIG),
		"expected_world": _v3a(expect_world),
		"seat_hits": seat_hits, "back_hits": back_hits, "leg_hits_near": legs_near,
	}


# ------------------------------------------------------------ A5 swing -----
func _reset_swing() -> void:
	m.set("_p81wind_legacy", false)
	m.set("_swing_roll", 0.0)
	m.set("_swing_roll_v", 0.0)
	m.set("_swing_pitch", 0.0)
	m.set("_swing_pitch_v", 0.0)
	m.set("_frame_t", 0.0)
	var pivot: Node3D = m.get("_swing_pivot") as Node3D
	if pivot != null:
		pivot.rotation = Vector3.ZERO


func _set_wind(visual: float, dir: Vector2) -> void:
	m.set("_weather_wind", visual)
	m.set("_weather_visual_wind", visual)
	m.set("_weather_wind_dir", dir)
	m.set("_weather_wind_dir_smooth", dir)


func _step_props(n: int, visual_wind: float, collect: bool = true) -> Array:
	var pivot: Node3D = m.get("_swing_pivot") as Node3D
	var out: Array = []
	for i in range(n):
		m.set("_frame_t", float(m.get("_frame_t")) + DT)
		m.call("_update_props", DT)
		var rot := pivot.rotation
		if collect:
			out.append(Vector3(rot.x, 0.0, rot.z))
	return out


func _phase_swing() -> void:
	_section("A5 swing: no-wind idle band / strong wind / recovery")
	var pivot: Node3D = m.get("_swing_pivot") as Node3D
	var seat: Node3D = null
	if pivot != null:
		seat = pivot.find_child("SwingSeat", true, false) as Node3D
	_check("swing.pivot_present", pivot != null, "_swing_pivot Node3D", str(pivot != null))
	_check("swing.seat_present", seat != null, "SwingSeat Node3D", str(seat != null))
	var world: Dictionary = m.get("_world")
	var big_tree: Vector3 = world.get("big_tree", Vector3.ZERO)
	var pivot_world := Vector3.ZERO
	if pivot != null:
		pivot_world = pivot.global_position
		var expect_pivot := big_tree + Vector3(3.0, 5.55, 0.0)
		_check("swing.pivot_world_unchanged", pivot_world.distance_to(expect_pivot) <= 0.02,
			str(_v3a(expect_pivot)), "dist=%.4f world=%s" % [pivot_world.distance_to(expect_pivot), str(_v3a(pivot_world))])
	var rope_len := 0.0
	var seat_world := Vector3.ZERO
	if seat != null:
		seat_world = seat.global_position
		rope_len = absf(seat.position.y)
		var smesh := seat.mesh as BoxMesh
		_check("swing.seat_mesh", smesh != null, "BoxMesh", str(smesh != null))
		if smesh != null:
			_check("swing.seat_size", smesh.size.distance_to(Vector3(1.12, 0.07, 0.46)) <= 0.001,
				"(1.12,0.07,0.46)", str(_v3a(smesh.size)))
	_check("swing.rope_len", rope_len > 4.5 and rope_len < 6.0, "4.5m<rope<6.0m", "%.3f" % rope_len)

	# ---- idle 20s：_weather_visual_wind = 0 ----
	_reset_swing()
	_set_wind(0.0, WD_135)
	var samples := _step_props(1200, 0.0)
	var idle_max_x := 0.0
	var idle_max_z := 0.0
	var idle_nan := false
	for s in samples:
		var v: Vector3 = s
		if not is_finite(v.x) or not is_finite(v.z):
			idle_nan = true
			continue
		idle_max_x = maxf(idle_max_x, absf(v.x))
		idle_max_z = maxf(idle_max_z, absf(v.z))
	var idle_deg := rad_to_deg(idle_max_x)
	var idle_roll_deg := rad_to_deg(idle_max_z)
	_check("swing.idle_no_nan", not idle_nan, "无 NaN/inf", str(idle_nan))
	_check("swing.idle_max_pitch_band", idle_deg >= 5.0 and idle_deg <= 10.0,
		"5° <= max|rotation.x| <= 10°", "%.3f°" % idle_deg)
	_check("swing.idle_roll_small", idle_roll_deg <= 2.5, "<=2.5°", "%.3f°" % idle_roll_deg)
	_info("秋千无风 20s：max|pitch|=%.3f° max|roll|=%.3f°" % [idle_deg, idle_roll_deg])

	# ---- strong wind 20s ----
	_reset_swing()
	_set_wind(WIND_STRONG, WD_135)
	var s_samples := _step_props(1200, WIND_STRONG)
	var strong_max_x := 0.0
	var strong_max_z := 0.0
	var strong_max_tilt := 0.0
	var strong_max_step := 0.0
	var strong_nan := false
	var prev := Vector3.ZERO
	var first := true
	for s in s_samples:
		var v2: Vector3 = s
		if not is_finite(v2.x) or not is_finite(v2.z):
			strong_nan = true
			continue
		if not first:
			strong_max_step = maxf(strong_max_step, maxf(absf(v2.x - prev.x), absf(v2.z - prev.z)))
		first = false
		prev = v2
		strong_max_x = maxf(strong_max_x, absf(v2.x))
		strong_max_z = maxf(strong_max_z, absf(v2.z))
		strong_max_tilt = maxf(strong_max_tilt, rad_to_deg(atan2(sqrt(v2.x * v2.x + v2.z * v2.z), 1.0)))
	var strong_deg := rad_to_deg(strong_max_x)
	var strong_roll_deg := rad_to_deg(strong_max_z)
	var strong_step_deg := rad_to_deg(strong_max_step)
	_check("swing.strong_no_nan", not strong_nan, "无 NaN/inf", str(strong_nan))
	_check("swing.strong_much_larger", strong_deg > idle_deg + 5.0 and strong_deg > 12.0,
		"> idle(%.2f°)+5° 且 >12°" % idle_deg, "%.3f°" % strong_deg)
	_check("swing.strong_smooth", strong_step_deg <= 2.0, "单帧角度变化 <=2°/帧", "%.4f°/帧" % strong_step_deg)
	_check("swing.strong_roll", strong_roll_deg > 5.0, ">5°（下风侧倾）", "%.3f°" % strong_roll_deg)
	_info("秋千强风(0.92,WD135) 20s：max|pitch|=%.3f° max|roll|=%.3f° max_tilt=%.3f° max_step=%.4f°/帧" % [
		strong_deg, strong_roll_deg, strong_max_tilt, strong_step_deg])

	# ---- wind off: _weather_wind -> 0（视觉风由 _update_weather_fx 平滑衰减）----
	m.set("_weather_wind", 0.0)
	var off_samples: Array = []
	var off_nan := false
	var off_max_step := 0.0
	var off_prev := Vector3.ZERO
	var off_first := true
	for i in range(600):
		m.call("_update_weather_fx", DT)
		m.set("_frame_t", float(m.get("_frame_t")) + DT)
		m.call("_update_props", DT)
		var v3: Vector3 = pivot.rotation if pivot != null else Vector3.ZERO
		if not is_finite(v3.x) or not is_finite(v3.z):
			off_nan = true
		if not off_first:
			off_max_step = maxf(off_max_step, maxf(absf(v3.x - off_prev.x), absf(v3.z - off_prev.z)))
		off_first = false
		off_prev = v3
		off_samples.append(v3)
	var final_max_deg := 0.0
	var final_max_roll := 0.0
	var n0 := maxi(0, off_samples.size() - 120)
	for i in range(n0, off_samples.size()):
		var v4: Vector3 = off_samples[i]
		final_max_deg = maxf(final_max_deg, rad_to_deg(absf(v4.x)))
		final_max_roll = maxf(final_max_roll, rad_to_deg(absf(v4.z)))
	_check("swing.windoff_no_nan", not off_nan, "无 NaN/inf", str(off_nan))
	_check("swing.windoff_final_band", final_max_deg >= 5.0 and final_max_deg <= 10.0,
		"最后 2s max|rotation.x| ∈[5°,10°]", "%.3f°" % final_max_deg)
	_check("swing.windoff_smooth", rad_to_deg(off_max_step) <= 10.0,
		"单帧变化 <=10°（无瞬移）", "%.4f°/帧" % rad_to_deg(off_max_step))
	_info("风降回 0 后 10s：末 2s max|pitch|=%.3f° max|roll|=%.3f° 全程 max_step=%.4f°/帧 视觉风终值=%.6f" % [
		final_max_deg, final_max_roll, rad_to_deg(off_max_step), float(m.get("_weather_visual_wind"))])
	_facts["swing"] = {
		"pivot_world": _v3a(pivot_world),
		"seat_world": _v3a(seat_world),
		"rope_len": rope_len,
		"big_tree": _v3a(big_tree),
		"idle_max_pitch_deg": idle_deg, "idle_max_roll_deg": idle_roll_deg,
		"strong_max_pitch_deg": strong_deg, "strong_max_roll_deg": strong_roll_deg,
		"strong_max_step_deg": strong_step_deg,
		"windoff_final_pitch_deg": final_max_deg, "windoff_max_step_deg": rad_to_deg(off_max_step),
		"const_swing_idle_pitch": float(MainScript.SWING_IDLE_PITCH),
		"const_swing_idle_roll": float(MainScript.SWING_IDLE_ROLL),
	}


# ------------------------------------------------------------- A6 facts ----
func _phase_facts(fy: Dictionary, fence: Dictionary) -> void:
	var corners := _yard_corners_local()
	var corners_w: Array = []
	for p in corners:
		corners_w.append(_v2a(_l2w(p)))
	var c: Vector2 = WorldScript.YARD_FARM_C
	var pad_y := float(fy.get("pad_y", 7.53))
	var gate_center: Vector2 = fence.get("gate_center_world", Vector2.ZERO)
	var corners_local_a: Array = []
	for p in corners:
		corners_local_a.append([p.x, p.y])
	_facts["scene"] = {
		"farm_center_local": _v2a(c),
		"farm_center_world": _v2a(fy.get("farm_center_world", Vector2.ZERO)),
		"pad_y": pad_y,
		"fence_half": float(WorldScript.YARD_FENCE_HALF),
		"fence_pitch": float(WorldScript.YARD_FENCE_PITCH),
		"corners_local": corners_local_a,
		"corners_world": corners_w,
		"gate_center_world_xz": _v2a(gate_center),
		"gate_center_world_y": pad_y + 0.006,
		"post_height": float(WorldScript.YARD_FENCE_POST_H),
		"gate_post_height": float(WorldScript.YARD_GATE_POST_H),
	}


# ============================================================ B. window =====
func _run_visual() -> void:
	_section("B0 window boot")
	_info("godot=%s display=%s out=%s" % [String(Engine.get_version_info().get("string", "")), DisplayServer.get_name(), out_dir])
	if DisplayServer.get_name() == "headless":
		_check("window.non_headless", false, "非 --headless 真实窗口", "headless")
		return
	_check("window.non_headless", true, "非 --headless 真实窗口", DisplayServer.get_name())
	var screen := DisplayServer.screen_get_size()
	_info("screen=%dx%d requested_shot=%dx%d" % [screen.x, screen.y, SHOT_W, SHOT_H])
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(shot_size_x(), shot_size_y()))
	await _frames(3)
	get_root().size = Vector2i(shot_size_x(), shot_size_y())
	await _frames(3)
	_info("window_size=%s root_size=%s" % [str(DisplayServer.window_get_size()), str(get_root().size)])

	# 截图需要逐件位置（门廊长椅）：probe-only 关闭静态合批，几何/材质/位置不变，仅多 draw call。
	CottageScript.probe_skip_batch = true
	m = MainScene.instantiate()
	get_root().add_child(m)
	await _frames(10)
	_check("window.scene_loaded", m != null and not (m.get("_world") as Dictionary).is_empty(), "isle.tscn world built", "world_keys=%d" % (m.get("_world") as Dictionary).size())
	m.set_process(false)
	m.set_physics_process(false)
	await _frames(2)

	# UI / 相机 / 时间
	var menu: Node = m.get("_menu")
	if menu != null and menu.has_method("instant_finish"):
		menu.call("instant_finish")
		if menu is CanvasLayer:
			(menu as CanvasLayer).visible = false
	var hud: Node = m.get("_hud")
	if hud != null:
		if hud.has_method("set_hud_visible"):
			hud.call("set_hud_visible", false, false)
		if hud is CanvasLayer:
			(hud as CanvasLayer).visible = false
	m.set("_mode", 1)          # MainScript.Mode.PLAYING
	m.set("_started", true)
	m.set("_paused", false)
	m.set("_auto_orbit", false)
	m.set("_p81wind_legacy", false)
	m.call("_jump_datetime", 2026, 10, 24, 12, 20, 0)
	_force_clear_weather()
	m.call("_update_lighting")
	m.call("_update_weather_fx", 0.0)
	# 正式设置的窗口尺寸会覆盖启动参数；截图前再按屏幕可用尺寸统一一次（任务允许 2560x1440 或当前窗口尺寸）
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(shot_size_x(), shot_size_y()))
	get_root().size = Vector2i(shot_size_x(), shot_size_y())
	await _frames(6)
	_info("shot window_size=%s root_size=%s" % [str(DisplayServer.window_get_size()), str(get_root().size)])
	var cam: Camera3D = m.get("_cam") as Camera3D
	_check("window.camera", cam != null and cam.current, "main._cam current", str(cam != null))

	var world: Dictionary = m.get("_world")
	var fy: Dictionary = world.get("front_yard", {})
	var fence: Dictionary = fy.get("fence", {})
	# 真实渲染器下复核横杆 MultiMesh：60 根、四角各 4 端点、非门洞边连续、门洞 1.355m 缺口。
	await _phase_rails(fy)
	var pad_y := float(fy.get("pad_y", 7.53))
	var c: Vector2 = WorldScript.YARD_FARM_C
	var gate_center: Vector2 = fence.get("gate_center_world", Vector2.ZERO)
	var corners := _yard_corners_local()
	var shot_meta: Array = []

	# 1) 围栏正面全景（房屋侧看三面连接：近边+两侧+远边）
	var yc := Vector2(c.x, 11.70)
	var pano_eye := _l2w_v3(Vector2(c.x - 2.2, c.y - 6.8), pad_y + 6.5)
	var pano_tgt := _l2w_v3(yc, pad_y + 0.45)
	await _pose_and_shot("01_fence_front_panorama", pano_eye, pano_tgt, 55.0, shot_meta)
	# 2) 四角近景
	var corner_names := ["02_corner_1_near_left", "03_corner_2_near_right", "04_corner_3_far_right", "05_corner_4_far_left"]
	for i in range(4):
		var cw: Vector2 = _l2w(corners[i])
		var yard_w: Vector2 = _l2w(c)
		var outward := (cw - yard_w).normalized()
		var eye := Vector3(cw.x + outward.x * 2.3, pad_y + 1.45, cw.y + outward.y * 2.3)
		var tgt := Vector3(cw.x, pad_y + 0.55, cw.y)
		await _pose_and_shot(corner_names[i], eye, tgt, 42.0, shot_meta)
	# 3) 门洞正面（从房屋侧看门洞）
	var gate_dir := _l2w_dir(0.0, 1.0).normalized()
	var gate_eye := Vector3(gate_center.x - gate_dir.x * 3.2, pad_y + 0.95, gate_center.y - gate_dir.y * 3.2)
	var gate_tgt := Vector3(gate_center.x, pad_y + 0.55, gate_center.y)
	await _pose_and_shot("06_gate_front", gate_eye, gate_tgt, 45.0, shot_meta)
	# 4) 花圃旁原长椅位置（地面/陶盆/围栏，证明长椅消失）
	var site_terrain := float(MathScript.terrain_height(OLD_BENCH_SITE.x, OLD_BENCH_SITE.y))
	var site_eye := Vector3(OLD_BENCH_SITE.x, site_terrain + 1.65, OLD_BENCH_SITE.y + 3.2)
	var site_tgt := Vector3(OLD_BENCH_SITE.x, site_terrain + 0.35, OLD_BENCH_SITE.y)
	await _pose_and_shot("07_garden_old_bench_site", site_eye, site_tgt, 45.0, shot_meta)
	# 5) 门廊长椅（Cottage 局部 (2.30, 3.80)，座板顶 gy+0.87）
	# 机位放在门廊正前方台阶缺口上方（前栏杆在 x≈±1.44 之外，中线无遮挡），斜看右侧长椅。
	var gy: float = float(MathScript.house_ground_y())
	var porch_w2 := _l2w(PORCH_BENCH_LOCAL)
	var porch_tgt := Vector3(porch_w2.x, gy + 0.42 + 0.45 + 0.10, porch_w2.y)
	var porch_cam_local := Vector2(-1.3, 5.9)
	var porch_cam_w2 := _l2w(porch_cam_local)
	var porch_eye := Vector3(porch_cam_w2.x, gy + 0.42 + 1.55, porch_cam_w2.y)
	await _pose_and_shot("08_porch_bench", porch_eye, porch_tgt, 44.0, shot_meta)
	# 6) 秋千：无风静置 / 强风摆动
	var pivot: Node3D = m.get("_swing_pivot") as Node3D
	var seat: Node3D = null
	if pivot != null:
		seat = pivot.find_child("SwingSeat", true, false) as Node3D
	if pivot == null or seat == null:
		_check("window.swing_bind", false, "_swing_pivot/SwingSeat", "null")
	else:
		# 两张秋千图共用同一固定机位（以自然悬垂座面为基准），摆幅差异才可比。
		pivot.rotation = Vector3.ZERO
		await _frames(2)
		var nominal_seat := seat.global_position
		var swing_eye := nominal_seat + Vector3(5.4, 1.6, 4.4)
		var swing_tgt := nominal_seat + Vector3(0.0, 0.45, 0.0)
		# 无风：_weather_visual_wind=0，模拟 20s 取 max|pitch| 帧
		_reset_swing()
		_set_wind(0.0, WD_135)
		var idx_idle := _find_max_pitch_index(1200)
		_reset_swing()
		_set_wind(0.0, WD_135)
		_step_props(idx_idle + 1, 0.0)
		await _swing_shot("09_swing_idle_nowind", pivot, swing_eye, swing_tgt, 46.0, shot_meta)
		# 强风：0.92，模拟 20s 取 max|pitch| 帧
		_reset_swing()
		_set_wind(WIND_STRONG, WD_135)
		var idx_strong := _find_max_pitch_index(1200)
		_reset_swing()
		_set_wind(WIND_STRONG, WD_135)
		_step_props(idx_strong + 1, WIND_STRONG)
		await _swing_shot("10_swing_strong_wind", pivot, swing_eye, swing_tgt, 46.0, shot_meta)

	_facts["shots_meta"] = shot_meta
	# 输出目录里至少 10 张、每张非空
	_check("window.shots_count", _shots.size() >= 10, ">=10 张", str(_shots.size()))
	var all_ok := _shots.size() > 0
	for s in _shots:
		if not bool(s.get("ok", false)):
			all_ok = false
	_check("window.shots_all_saved", all_ok, "全部 PNG 保存成功", str(_shots.size()))


func shot_size_x() -> int:
	var scr := DisplayServer.screen_get_size()
	return mini(SHOT_W, maxi(scr.x, 640))


func shot_size_y() -> int:
	var scr := DisplayServer.screen_get_size()
	return mini(SHOT_H, maxi(scr.y, 360))


func _verify_freeze() -> Dictionary:
	var out := {"frozen": false, "delta": -1.0}
	if not bool(m.get("_shots")):
		out["frozen"] = true
		out["delta"] = 0.0
		return out
	var t := create_timer(0.01, true)
	var before := t.time_left
	for i in range(10):
		await process_frame
	var after := t.time_left
	out["delta"] = absf(before - after)
	out["frozen"] = absf(after - before) < 1e-9
	return out


func _force_clear_weather() -> void:
	var wx: Object = m.get("_weather")
	if wx == null:
		return
	wx.call("set_manual_type", "clear")
	wx.call("reset", float(m.get("_sim_seconds")))
	m.call("_update_weather", 0.0, true)


func _pose_and_shot(name: String, eye: Vector3, target: Vector3, fov: float, meta: Array) -> void:
	m.call("_pose_look", eye, target, fov)
	var cam: Camera3D = m.get("_cam") as Camera3D
	if cam != null:
		cam.current = true
	await _frames(3)
	var actual_eye := cam.global_position if cam != null else eye
	var actual_tgt: Vector3 = m.get("_cam_target")
	meta.append({"name": name, "eye": _v3a(actual_eye), "target": _v3a(actual_tgt), "fov": fov})
	await _shot(name)


func _swing_shot(name: String, pivot: Node3D, eye: Vector3, tgt: Vector3, fov: float, meta: Array) -> void:
	var pivot_rot := pivot.rotation
	meta.append({"name": name, "eye": _v3a(eye), "target": _v3a(tgt), "fov": fov,
		"pivot_rot_x_deg": rad_to_deg(pivot_rot.x), "pivot_rot_z_deg": rad_to_deg(pivot_rot.z)})
	m.call("_pose_look", eye, tgt, fov)
	var cam: Camera3D = m.get("_cam") as Camera3D
	if cam != null:
		cam.current = true
	await _frames(3)
	await _shot(name)


func _find_max_pitch_index(n: int) -> int:
	var pivot: Node3D = m.get("_swing_pivot") as Node3D
	var best := 0.0
	var best_i := 0
	# 采样后回放：为了不改变调用方的模拟状态，先完整跑一遍再返回最大帧号（调用方自行重置重跑）。
	for i in range(n):
		m.set("_frame_t", float(m.get("_frame_t")) + DT)
		m.call("_update_props", DT)
		var ax := absf(pivot.rotation.x)
		if ax > best:
			best = ax
			best_i = i
	return best_i


func _shot(name: String) -> void:
	var dir := out_dir + "/shots"
	DirAccess.make_dir_recursive_absolute(dir)
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null or img.get_width() <= 0:
		_check("shot." + name, false, "非空 PNG", "empty image")
		_shots.append({"name": name, "ok": false, "path": ""})
		return
	var path := dir + "/" + name + ".png"
	var err := img.save_png(path)
	_check("shot." + name, err == OK, "save_png OK", "w=%d h=%d err=%s path=%s" % [
		img.get_width(), img.get_height(), str(err), path])
	if err == OK:
		_shots.append({"name": name, "ok": true, "path": path, "w": img.get_width(), "h": img.get_height()})
		print("[SHOT] %s %dx%d %s" % [name, img.get_width(), img.get_height(), path])
		_lines.append("[SHOT] %s %dx%d %s" % [name, img.get_width(), img.get_height(), path])
	else:
		_shots.append({"name": name, "ok": false, "path": path, "w": img.get_width(), "h": img.get_height()})
