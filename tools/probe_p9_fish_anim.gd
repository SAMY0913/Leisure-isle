extends SceneTree
## P6 / 钓鱼动画 —— 岛民三个新剪辑（fish_hold / fish_cast / fish_reel）headless 自检探针。
##
## 运行：
##   "D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe" --headless \
##     --path "D:/休闲小岛幻境/游戏工程" --script res://tools/probe_p9_fish_anim.gd \
##     -- --out="D:/休闲小岛幻境/开发产物/P9/P6/r1_anim"
##
## 覆盖：
##   1) 动画库/时长/循环标志：原有 12 个剪辑不许回归 + 3 个新剪辑；
##   2) 新剪辑轨道数 ≥20（VALUE 轨道，23 条规格）；
##   3) 姿态采样（AnimationPlayer.seek 后读关节世界变换）：
##      持竿手明显抬高、循环内姿势稳定、首尾无缝；
##      抛竿“后引→前甩”持竿手位移、收势回到持竿；收线“提竿→回落”位移；
##      原有 idle/walk 采样无 NaN。
##
## 纪律：只读模型脚本，不改工程文件；产物只写到 --out 目录。

const MODEL_PATH := "res://scripts/isle_villager_model.gd"
const DEFAULT_OUT := "D:/休闲小岛幻境/开发产物/P9/P6/r1_anim"

## 原有 12 个剪辑的时长/循环标志（P7-V4 基线，本任务禁止改动）。
const EXISTING_CLIPS := {
	"idle": [5.0, true],
	"idle_alt": [5.2, true],
	"walk": [0.88, true],
	"sit_down": [0.80, false],
	"sit_idle": [4.0, true],
	"sit_up": [0.70, false],
	"bed_sit_down": [0.80, false],
	"bed_sit_up": [0.70, false],
	"eat": [3.0, true],
	"lie_down": [1.0, false],
	"sleep": [6.0, true],
	"get_up": [1.0, false],
}

## 新增 3 个钓鱼剪辑：时长/循环标志。
const NEW_CLIPS := {
	"fish_hold": [4.0, true],
	"fish_cast": [1.2, false],
	"fish_reel": [1.4, false],
}

const JOINT_KEYS := [
	"body_pos", "body_roll", "body_tilt", "pelvis", "torso", "neck", "head", "hair",
	"shoulder_l", "shoulder_r", "elbow_l", "elbow_r", "hand_l", "hand_r",
	"hip_l", "hip_r", "knee_l", "knee_r", "foot_l", "foot_r", "eyelid_l", "eyelid_r",
]

const EPS := 0.0001

var out_dir := DEFAULT_OUT
var _pass := 0
var _fail := 0
var _lines: Array = []
var _fail_names: Array = []
var _root: Node3D = null
var _anim: AnimationPlayer = null
var _clips_info := {}
var _metrics := {}


func _initialize() -> void:
	_parse_args()
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--out="):
			out_dir = s.substr(6).strip_edges().trim_suffix("/").trim_suffix("\\")
	if out_dir == "":
		out_dir = DEFAULT_OUT


func _run() -> void:
	var banner := "[FISHANIM] out=%s headless=%s godot=%s" % [
		out_dir, str(DisplayServer.get_name() == "headless"),
		String(Engine.get_version_info().get("string", ""))]
	print(banner)
	_lines.append(banner)
	await process_frame

	var built: Dictionary = (load(MODEL_PATH) as GDScript).create(0)
	_root = built["root"] as Node3D
	_anim = built["anim"] as AnimationPlayer
	if _root == null or _anim == null:
		print("[FISHANIM] 模型构建失败：", str(built))
		_lines.append("[FISHANIM] 模型构建失败")
		_write_report()
		print("[SUMMARY] checks=0 fail=1")
		print("[RESULT] FAIL")
		quit(1)
		return
	get_root().add_child(_root)
	await process_frame
	await process_frame

	_check_api()
	_check_clip_meta()
	_check_hold()
	_check_cast()
	_check_reel()
	_check_regression()

	_write_report()
	var summary := "[SUMMARY] checks=%d fail=%d" % [_pass + _fail, _fail]
	print(summary)
	_lines.append(summary)
	print("[RESULT] " + ("PASS" if _fail == 0 else "FAIL"))
	_lines.append("[RESULT] " + ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)


# =========================================================== 基础设施 =========

func _section(title: String) -> void:
	print("")
	print("== ", title, " ==")
	_lines.append("")
	_lines.append("== " + title + " ==")


func _check(name: String, ok: bool, expected: String, actual: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		_fail_names.append(name)
	var line := "[CHECK] %s | expected=%s actual=%s | %s" % [name, expected, actual, "PASS" if ok else "FAIL"]
	print(line)
	_lines.append(line)


func _write_report() -> void:
	var log_path := out_dir + "/probe_p9_fish_anim.log"
	var fa := FileAccess.open(log_path, FileAccess.WRITE)
	if fa != null:
		fa.store_string("\n".join(_lines) + "\n")
		fa.close()
		print("[FISHANIM] log=", log_path)
	var data := {
		"checks": _pass + _fail,
		"fail": _fail,
		"fail_names": _fail_names,
		"headless": DisplayServer.get_name() == "headless",
		"godot": String(Engine.get_version_info().get("string", "")),
		"clips": _clips_info,
		"metrics": _metrics,
	}
	var jf := FileAccess.open(out_dir + "/probe_p9_fish_anim.json", FileAccess.WRITE)
	if jf != null:
		jf.store_string(JSON.stringify(data, "  "))
		jf.close()


# =========================================================== 姿态采样 =========

## 把播放头定位到 t（root 局部坐标快照）。clip 非循环时 t 会被夹到 length-EPS。
func _pose_at(clip: String, t: float) -> Dictionary:
	var a := _anim.get_animation(clip)
	if a == null:
		return {}
	var tt := clampf(t, 0.0, maxf(0.0, a.length - EPS))
	_anim.play(clip)
	_anim.seek(tt, true)
	return _snapshot()


func _snapshot() -> Dictionary:
	var inv := _root.global_transform.affine_inverse()
	var out := {}
	for key in JOINT_KEYS:
		var j: Node3D = _root.get_joint(key)
		if j != null:
			out[key] = inv * j.global_transform
	return out


func _joint_pos(pose: Dictionary, key: String) -> Vector3:
	var t = pose.get(key)
	if t == null:
		return Vector3.ZERO
	return (t as Transform3D).origin


## 两个朝向的最大差异：三条基轴分别求夹角 + 长度差（rad / 比例，取大者）。
## 不用 get_euler() 相减 —— 欧拉分解在 |x| 接近 PI/2 时会换分支（如眼皮 EYELID_OPEN=-1.55
## 叠加头部俯仰后超过 -PI/2），同一个朝向会算出 ~4.4 rad 的假差异。
func _basis_delta(a: Basis, b: Basis) -> float:
	var worst := 0.0
	var ca := [a.x, a.y, a.z]
	var cb := [b.x, b.y, b.z]
	for i in 3:
		var va: Vector3 = ca[i]
		var vb: Vector3 = cb[i]
		var la := va.length()
		var lb := vb.length()
		worst = maxf(worst, absf(la - lb))
		if la > 0.000001 and lb > 0.000001:
			var d := clampf((va / la).dot(vb / lb), -1.0, 1.0)
			worst = maxf(worst, acos(d))
	return worst


## 两个快照的最大关节差（位置 m / 朝向 rad 取大者）。
func _pose_delta(a: Dictionary, b: Dictionary) -> float:
	var worst := 0.0
	for key in a:
		if not b.has(key):
			continue
		var ta: Transform3D = a[key]
		var tb: Transform3D = b[key]
		var dp := (ta.origin - tb.origin).length()
		var dr := _basis_delta(ta.basis, tb.basis)
		worst = maxf(worst, maxf(dp, dr))
	return worst


func _pose_finite(pose: Dictionary) -> bool:
	for key in pose:
		var t: Transform3D = pose[key]
		if not t.origin.is_finite():
			return false
		if not t.basis.x.is_finite() or not t.basis.y.is_finite() or not t.basis.z.is_finite():
			return false
	return true


func _scan(clip: String, t0: float, t1: float, step: float) -> Array:
	var out: Array = []
	var t := t0
	while t <= t1 + 0.000001:
		out.append({"t": t, "pose": _pose_at(clip, t)})
		t += step
	return out


# =========================================================== 检查项 ==========

func _check_api() -> void:
	_section("装配 / AnimationPlayer")
	_check("api/root_is_node3d", _root is Node3D, "Node3D", _root.get_class())
	_check("api/root_in_tree", _root.is_inside_tree(), "true", str(_root.is_inside_tree()))
	_check("api/anim_not_null", _anim != null, "AnimationPlayer", str(_anim))
	if _anim == null:
		return
	_check("api/anim_name", String(_anim.name) == "Anim", "Anim", String(_anim.name))
	_check("api/anim_parent", _anim.get_parent() == _root, "root", str(_anim.get_parent()))
	_check("api/anim_root_node", _anim.root_node == NodePath(".."), "..", str(_anim.root_node))
	_check("api/library_count", _anim.get_animation_library_list().size() == 1, "1", str(_anim.get_animation_library_list().size()))


func _check_clip_meta() -> void:
	_section("剪辑库 / 时长 / 循环标志 / 轨道")
	var names: PackedStringArray = _root.get_animation_names()
	print("[FISHANIM] CLIPS: " + ", ".join(names))
	var missing: Array = []
	for clip in EXISTING_CLIPS:
		if not names.has(clip):
			missing.append(clip)
	for clip in NEW_CLIPS:
		if not names.has(clip):
			missing.append(clip)
	_check("lib/anim_count", names.size() == EXISTING_CLIPS.size() + NEW_CLIPS.size(), "15", str(names.size()))
	_check("lib/all_15_names", missing.is_empty(), "[]", str(missing))

	for clip in EXISTING_CLIPS:
		var want: Array = EXISTING_CLIPS[clip]
		var a := _anim.get_animation(clip)
		_check("existing/%s_exists" % clip, a != null, "Animation", str(a != null))
		if a == null:
			continue
		_check("existing/%s_length" % clip, absf(a.length - float(want[0])) <= 0.001,
			"%.2f" % float(want[0]), "%.4f" % a.length)
		_check("existing/%s_loop" % clip, (a.loop_mode == Animation.LOOP_LINEAR) == bool(want[1]),
			str(bool(want[1])), str(a.loop_mode == Animation.LOOP_LINEAR))
		_record_clip(clip, a)

	for clip in NEW_CLIPS:
		var want: Array = NEW_CLIPS[clip]
		var a := _anim.get_animation(clip)
		_check("new/%s_exists" % clip, a != null, "Animation", str(a != null))
		if a == null:
			continue
		_check("new/%s_length" % clip, absf(a.length - float(want[0])) <= 0.001,
			"%.1f" % float(want[0]), "%.4f" % a.length)
		_check("new/%s_loop" % clip, (a.loop_mode == Animation.LOOP_LINEAR) == bool(want[1]),
			str(bool(want[1])), str(a.loop_mode == Animation.LOOP_LINEAR))
		_check("new/%s_track_count" % clip, a.get_track_count() >= 20, ">=20", str(a.get_track_count()))
		var broken := _broken_tracks(a)
		_check("new/%s_tracks_resolve" % clip, broken.is_empty(), "[]", str(broken))
		_record_clip(clip, a)
	print("[FISHANIM] CLIPINFO " + str(_clips_info))


func _record_clip(clip: String, a: Animation) -> void:
	_clips_info[clip] = {
		"length": a.length,
		"loop": a.loop_mode == Animation.LOOP_LINEAR,
		"tracks": a.get_track_count(),
	}


## VALUE 轨道路径形如 "节点:属性"，检查节点在 root 下存在且属性名非空。
func _broken_tracks(a: Animation) -> Array:
	var broken: Array = []
	for i in a.get_track_count():
		var p: NodePath = a.track_get_path(i)
		var node_path := NodePath(String(p).get_slice(":", 0))
		var prop := String(p).get_slice(":", 1)
		if prop == "" or _root.get_node_or_null(node_path) == null:
			broken.append(str(p))
	return broken


func _check_hold() -> void:
	_section("fish_hold 持竿待机（loop 4.0s）")
	var hold := _pose_at("fish_hold", 0.0)
	var idle := _pose_at("idle", 0.0)
	var hold_h := _joint_pos(hold, "hand_r")
	var idle_h := _joint_pos(idle, "hand_r")
	_metrics["hold_hand_y"] = hold_h.y
	_metrics["idle_hand_y"] = idle_h.y
	_metrics["hold_vs_idle_dy"] = hold_h.y - idle_h.y
	print("[FISHANIM] HOLD hand_r=(%.3f,%.3f,%.3f) idle_hand_r=(%.3f,%.3f,%.3f)" % [
		hold_h.x, hold_h.y, hold_h.z, idle_h.x, idle_h.y, idle_h.z])
	_check("fish_hold/hand_r_raised_vs_idle", hold_h.y - idle_h.y > 0.15, ">0.15 m",
		"%.3f m (hold y=%.3f, idle y=%.3f)" % [hold_h.y - idle_h.y, hold_h.y, idle_h.y])
	_check("fish_hold/hand_r_forward_of_body", hold_h.z < -0.20, "<-0.20 m",
		"z=%.3f" % hold_h.z)
	_check("fish_hold/hand_r_finite", hold_h.is_finite(), "true", str(hold_h.is_finite()))

	# 循环内稳定：呼吸/微摆只改躯干头，握竿手几乎不动
	var times := [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5]
	var worst_pos := 0.0
	var worst_delta := 0.0
	var finite := true
	for t in times:
		var p := _pose_at("fish_hold", t)
		if not _pose_finite(p):
			finite = false
		worst_pos = maxf(worst_pos, (_joint_pos(p, "hand_r") - hold_h).length())
		worst_delta = maxf(worst_delta, _pose_delta(p, hold))
	print("[FISHANIM] HOLD sway  hand_drift=%.4f m pose_drift=%.4f" % [worst_pos, worst_delta])
	_metrics["hold_hand_drift"] = worst_pos
	_metrics["hold_pose_drift"] = worst_delta
	_check("fish_hold/hand_r_stable_in_loop", worst_pos < 0.05, "<0.05 m", "%.4f m" % worst_pos)
	_check("fish_hold/pose_stable_in_loop", worst_delta < 0.12, "<0.12", "%.4f" % worst_delta)
	_check("fish_hold/samples_finite", finite, "true", str(finite))

	# 首尾无缝
	var seam := _pose_delta(_pose_at("fish_hold", 0.0), _pose_at("fish_hold", 4.0 - EPS))
	print("[FISHANIM] HOLD seam delta=%.6f" % seam)
	_metrics["hold_seam_delta"] = seam
	_check("fish_hold/loop_seam", seam < 0.01, "<0.01", "%.6f" % seam)


func _check_cast() -> void:
	_section("fish_cast 抛竿（one-shot 1.2s）")
	var hold := _pose_at("fish_hold", 0.0)
	var hold_h := _joint_pos(hold, "hand_r")

	var start := _pose_at("fish_cast", 0.0)
	var start_d := (_joint_pos(start, "hand_r") - hold_h).length()
	_metrics["cast_start_delta"] = start_d
	_check("fish_cast/starts_at_hold", start_d < 0.10, "<0.10 m", "%.4f m" % start_d)

	# 后引窗口 / 前甩窗口：root 局部 +Z 为身后、-Z 为身前（模型脸朝 -Z）
	var wind := _scan("fish_cast", 0.10, 0.44, 0.01)
	var rel := _scan("fish_cast", 0.48, 0.78, 0.01)
	var wind_z := -1e9
	var rel_z := 1e9
	var wind_p := Vector3.ZERO
	var rel_p := Vector3.ZERO
	var wind_t := 0.0
	var rel_t := 0.0
	var finite := true
	for s in wind:
		var p: Vector3 = _joint_pos(s["pose"], "hand_r")
		if not p.is_finite():
			finite = false
		if p.z > wind_z:
			wind_z = p.z
			wind_p = p
			wind_t = float(s["t"])
	for s in rel:
		var q: Vector3 = _joint_pos(s["pose"], "hand_r")
		if not q.is_finite():
			finite = false
		if q.z < rel_z:
			rel_z = q.z
			rel_p = q
			rel_t = float(s["t"])
	var disp := (rel_p - wind_p).length()
	var back_fwd := wind_z - rel_z
	print("[FISHANIM] CAST windup t=%.2f hand=(%.3f,%.3f,%.3f) release t=%.2f hand=(%.3f,%.3f,%.3f) disp=%.3f back_fwd=%.3f" % [
		wind_t, wind_p.x, wind_p.y, wind_p.z, rel_t, rel_p.x, rel_p.y, rel_p.z, disp, back_fwd])
	_metrics["cast_windup_t"] = wind_t
	_metrics["cast_release_t"] = rel_t
	_metrics["cast_hand_disp"] = disp
	_metrics["cast_back_then_fwd"] = back_fwd
	_check("fish_cast/windup_behind_release", back_fwd > 0.25, ">0.25 m", "%.3f m" % back_fwd)
	_check("fish_cast/hand_travel", disp > 0.25, ">0.25 m", "%.3f m" % disp)
	_check("fish_cast/samples_finite", finite, "true", str(finite))

	var end := _pose_at("fish_cast", 1.2 - EPS)
	var end_d := (_joint_pos(end, "hand_r") - hold_h).length()
	_metrics["cast_end_delta"] = end_d
	_check("fish_cast/ends_at_hold", end_d < 0.10, "<0.10 m", "%.4f m" % end_d)


func _check_reel() -> void:
	_section("fish_reel 收线（one-shot 1.4s）")
	var hold := _pose_at("fish_hold", 0.0)
	var hold_y := _joint_pos(hold, "hand_r").y
	var scan := _scan("fish_reel", 0.0, 1.35, 0.01)
	var peak_y := -1e9
	var peak_t := 0.0
	var finite := true
	for s in scan:
		var p: Vector3 = _joint_pos(s["pose"], "hand_r")
		if not p.is_finite():
			finite = false
		if float(s["t"]) > 0.10 and p.y > peak_y:
			peak_y = p.y
			peak_t = float(s["t"])
	print("[FISHANIM] REEL peak t=%.2f hand_y=%.3f hold_y=%.3f rise=%.3f" % [
		peak_t, peak_y, hold_y, peak_y - hold_y])
	_metrics["reel_peak_t"] = peak_t
	_metrics["reel_peak_y"] = peak_y
	_metrics["reel_rise"] = peak_y - hold_y
	_check("fish_reel/hand_r_rises_vs_hold", peak_y - hold_y > 0.08, ">0.08 m",
		"%.3f m (peak y=%.3f t=%.2f, hold y=%.3f)" % [peak_y - hold_y, peak_y, peak_t, hold_y])
	_check("fish_reel/samples_finite", finite, "true", str(finite))

	var end := _pose_at("fish_reel", 1.4 - EPS)
	var end_d := (_joint_pos(end, "hand_r") - _joint_pos(hold, "hand_r")).length()
	_metrics["reel_end_delta"] = end_d
	_check("fish_reel/settles_to_hold", end_d < 0.12, "<0.12 m", "%.4f m" % end_d)


func _check_regression() -> void:
	_section("原有剪辑回归（idle / walk 采样无 NaN）")
	for clip in ["idle", "walk"]:
		var a := _anim.get_animation(clip)
		var finite := true
		var samples := 0
		var t := 0.0
		while t < a.length - EPS:
			var p := _pose_at(clip, t)
			if not _pose_finite(p):
				finite = false
			samples += 1
			t += a.length / 12.0
		_check("existing/%s_samples_finite" % clip, finite, "true",
			"%s (%d samples)" % [str(finite), samples])
