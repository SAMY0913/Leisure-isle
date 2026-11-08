extends SceneTree
## P7-V4 岛民视觉验收截图（真实窗口渲染，headless 直接退出 1）
##
## 覆盖任务书要求的视觉检查：正面/侧面/背面、固定服装细节、两种发型对照、待机、
## 行走两个 contact 相位与 passing、餐桌进食、椅子坐下/起身、躺床睡眠/起床、
## 楼梯中段/转角平台、白天/黄昏/夜间外观。
## 全部用真实场景 isle.tscn + 真实 villager 状态机/路径/活动点；静止帧暂停取景，
## 过渡帧用 Engine.time_scale 慢放抓相位。
##
## 运行（必须真实窗口）：
##   "D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe" --path "D:/休闲小岛幻境/游戏工程" \
##     --resolution 1600x900 --script res://tools/probe_villager_shots.gd -- --stage=look --only=v_front
##   --stage=look|walk|stairs|eat|sit|bed|all   --only=id1,id2
## 产物：开发产物/p7v4/shots/*.png + MANIFEST_villager.md + villager_shots_manifest.json

const SHOT_W := 1600
const SHOT_H := 900
const OUT_DIR := "D:/休闲小岛幻境/开发产物/p7v4/shots/"
const T_DAY := 740.0
const T_DUSK := 1045.0
const T_NIGHT := 1320.0

var _main: Node = null
var _cam: Camera3D = null
var _v: Node3D = null
var _model: Node3D = null
var _cottage: Dictionary = {}
var _cr: Node3D = null

var _stage := "all"
var _only: Array = []
var _manifest: Array = []
var _fails: Array = []


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i in range(args.size()):
		var a := String(args[i])
		if a.begins_with("--stage="):
			_stage = a.substr(8)
		elif a.begins_with("--only="):
			for s in a.substr(7).split(","):
				var t := String(s).strip_edges()
				if t != "":
					_only.append(t)
	print("=== P7-V4 VILLAGER SHOTS START stage=", _stage, " only=", str(_only), " ===")
	if DisplayServer.get_name() == "headless":
		print("[V4SHOT] SKIP headless：真实渲染截图必须在窗口模式运行")
		quit(1)
		return
	_run()


func _run() -> void:
	var packed: PackedScene = load("res://isle.tscn") as PackedScene
	if packed == null:
		print("[V4SHOT] FAIL 无法加载 res://isle.tscn")
		quit(1)
		return
	_main = packed.instantiate()
	get_root().add_child(_main)
	await process_frame
	await process_frame
	var menu: Node = _main.get("_menu") as Node
	if menu != null and menu.has_method("instant_finish"):
		menu.call("instant_finish")
	_main.set("_mode", 1)
	_main.set("_time_source", "sim")
	_main.set("_realtime", false)
	_main.set("_started", true)
	_main.set("_paused", true)
	_main.set("_auto_orbit", false)
	_main.set("_blending", "")
	_force_windowed()
	await _settle(12)
	_force_windowed()
	await _settle(4)
	var hud: Node = _main.get("_hud") as Node
	if hud != null and hud.has_method("set_hud_visible"):
		hud.call("set_hud_visible", false, false)
	_cam = _main.get("_cam") as Camera3D
	_v = _main.get("_villager") as Node3D
	_cottage = _main.get("_cottage") as Dictionary
	if _v == null or _cam == null or _cottage.is_empty():
		print("[V4SHOT] FAIL 场景引用缺失 cam=", _cam, " villager=", _v, " cottage_empty=", _cottage.is_empty())
		quit(1)
		return
	_cr = _cottage.get("root") as Node3D
	_model = _v.get("model_root") as Node3D
	_v.set("debug_log", true)
	_v.set("_last_sim", -1.0)
	_main.set("_day_length", 86400.0)
	_set_time(T_DAY)
	await _settle(4)
	print("[V4SHOT] window=", DisplayServer.window_get_size(), " villager=", _v.name,
		" spawn=", _f3(_v.global_position), " hair=", _v.get("hair_style"))
	_dump_graph()

	_main.set("_paused", false)
	await _settle(8)

	if _want_stage("look"):
		await _stage_look()
	if _want_stage("walk"):
		await _stage_walk()
	if _want_stage("stairs"):
		await _stage_stairs()
	if _want_stage("eat"):
		await _stage_eat()
	if _want_stage("sit"):
		await _stage_sit()
	if _want_stage("bed"):
		await _stage_bed()

	Engine.time_scale = 1.0
	_write_manifest()
	print("[V4SHOT] FAILS=", str(_fails))
	print("[V4SHOT] RESULT shots=", _manifest.size(), " fail=", _fails.size(), " out=", OUT_DIR)
	quit(0 if _fails.is_empty() else 1)


func _want_stage(s: String) -> bool:
	return _stage == "all" or _stage == s


# ============================================================ 场景查询 ======
func _dump_graph() -> void:
	var g: Dictionary = _v.get("graph")
	var nodes: Dictionary = g.get("nodes", {})
	var spots: Dictionary = g.get("spots", {})
	print("[V4SHOT] GRAPH nodes=", nodes.size(), " spots=", spots.size(),
		" house_root=", _f3(_cr.global_position))
	for sid in spots.keys():
		var sp: Dictionary = spots[sid]
		print("[V4SHOT] SPOT ", sid, " kind=", String(sp.get("kind", "")),
			" anchor=", _f3(sp.get("anchor", Vector3.ZERO)),
			" approach=", _f3(sp.get("approach", Vector3.ZERO)),
			" approach_node=", String(sp.get("approach_node", "")),
			" level=", int(sp.get("level", 0)))


func _mfw() -> Vector3:
	if _model == null:
		return Vector3(0.0, 0.0, -1.0)
	var z: Vector3 = _model.global_transform.basis.z
	var f := Vector3(-z.x, 0.0, -z.z)
	if f.length_squared() < 1e-6:
		return Vector3(0.0, 0.0, -1.0)
	return f.normalized()


func _mrt() -> Vector3:
	if _model == null:
		return Vector3(1.0, 0.0, 0.0)
	var x: Vector3 = _model.global_transform.basis.x
	var r := Vector3(x.x, 0.0, x.z)
	if r.length_squared() < 1e-6:
		return Vector3(1.0, 0.0, 0.0)
	return r.normalized()


func _model_aabb() -> AABB:
	var out := AABB()
	var first := true
	for n in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if not mi.is_visible_in_tree():
			continue
		if mi.name == "Shadow":
			continue
		var bb: AABB = mi.mesh.get_aabb()
		var xf: Transform3D = mi.global_transform
		for ci in range(8):
			var corner := bb.position + Vector3(
				bb.size.x * float(ci & 1),
				bb.size.y * float((ci >> 1) & 1),
				bb.size.z * float((ci >> 2) & 1))
			var wp: Vector3 = xf * corner
			if first:
				out = AABB(wp, Vector3.ZERO)
				first = false
			else:
				out = out.expand(wp)
	return out


func _joint(name: String) -> Vector3:
	if _model != null:
		var j: Variant = _model.call("get_joint", name)
		if j is Node3D:
			return (j as Node3D).global_position
	var a := _model_aabb()
	return a.get_center() + Vector3(0.0, a.size.y * 0.36, 0.0)


func _head_pos() -> Vector3:
	return _joint("head")


func _torso_pos() -> Vector3:
	return _joint("torso")


func _local(p: Vector3) -> Vector3:
	return _cr.global_transform * p


func _local_inv(p: Vector3) -> Vector3:
	return _cr.global_transform.affine_inverse() * p


func _f3(v: Vector3) -> String:
	return "%.2f,%.2f,%.2f" % [v.x, v.y, v.z]


# ============================================================ 帧控制 ========
func _settle(n: int) -> void:
	for i in range(maxi(n, 0)):
		await process_frame


func _freeze() -> void:
	_main.set("_paused", true)
	await _settle(3)


func _thaw() -> void:
	_main.set("_paused", false)
	await _settle(2)


func _set_time(minutes: float) -> void:
	_main.call("_set_time_of_day", minutes)
	_main.call("_update_lighting")


func _force_windowed() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))


func _state() -> String:
	var ds: Dictionary = _v.call("debug_state")
	return String(ds.get("state", ""))


func _clip_pos() -> float:
	var ds: Dictionary = _v.call("debug_state")
	return float(ds.get("clip_pos", 0.0))


func _wait_state(target: String, timeout_s: float) -> bool:
	var t0 := Time.get_ticks_msec()
	var limit := int(timeout_s * 1000.0)
	while Time.get_ticks_msec() - t0 < limit:
		await process_frame
		if _state() == target:
			return true
	print("[V4SHOT] TIMEOUT wait_state ", target, " now=", _state(), " pos=", _f3(_v.global_position))
	return false


# ============================================================ 截图核心 ======
func _want(id: String) -> bool:
	if _only.is_empty():
		return true
	return _only.has(id)


func _shot(id: String, desc: String, cam: Vector3, target: Vector3, fov: float, check: Variant = null) -> void:
	if not _want(id):
		return
	_main.call("_pose_look", cam, target, fov)
	await _settle(5)
	await RenderingServer.frame_post_draw
	var img: Image = _main.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var path := OUT_DIR + id + ".png"
	var err := ERR_CANT_CREATE
	var iw := 0
	var ih := 0
	if img != null:
		err = img.save_png(path)
		iw = img.get_width()
		ih = img.get_height()
	var ds: Dictionary = _v.call("debug_state")
	var aabb := _model_aabb()
	var ck: Vector3 = target
	if check is Vector3:
		ck = check
	var info := _screen_info(ck, aabb)
	var actual_cam := _cam.global_position
	print("[V4SHOT] SHOT ", id, " state=", String(ds.get("state", "")), " clip=", String(ds.get("clip", "")),
		" cp=%.2f" % float(ds.get("clip_pos", 0.0)),
		" pos=", _f3(_v.global_position), " aabb=", _f3(aabb.size),
		" cam=", _f3(actual_cam), " target=", _f3(target),
		" uv=", str(info.get("uv", Vector2i.ZERO)), " frac=", "%.2f" % float(info.get("frac", 0.0)),
		" lum=", "%.3f" % _mean_luma(img), " err=", err, " size=", iw, "x", ih,
		" desc=", desc)
	if err != OK or iw != SHOT_W or ih != SHOT_H:
		_fails.append("save:" + id)
	if not bool(info.get("in", false)):
		_fails.append("frame:" + id)
	_manifest.append({
		"id": id,
		"file": id + ".png",
		"desc": desc,
		"state": String(ds.get("state", "")),
		"clip": String(ds.get("clip", "")),
		"clip_pos": float(ds.get("clip_pos", 0.0)),
		"villager_pos": _v3(_v.global_position),
		"aabb_size": _v3(aabb.size),
		"cam": _v3(actual_cam),
		"target": _v3(target),
		"fov": fov,
		"screen_uv": [int(info.get("uv", Vector2i.ZERO).x), int(info.get("uv", Vector2i.ZERO).y)],
		"screen_frac": float(info.get("frac", 0.0)),
		"luma": _mean_luma(img),
		"size": [iw, ih],
		"err": err,
	})


func _screen_info(point: Vector3, aabb: AABB) -> Dictionary:
	var vp := Vector2(_cam.get_viewport().get_visible_rect().size)
	var behind := _cam.is_position_behind(point)
	var uv := _cam.unproject_position(point)
	var inside := (not behind) and uv.x >= 0.0 and uv.y >= 0.0 and uv.x <= vp.x and uv.y <= vp.y
	var top := _cam.unproject_position(aabb.get_center() + Vector3(0.0, aabb.size.y * 0.5, 0.0))
	var bot := _cam.unproject_position(aabb.get_center() - Vector3(0.0, aabb.size.y * 0.5, 0.0))
	var frac := absf(top.y - bot.y) / maxf(vp.y, 1.0)
	return {"in": inside, "uv": Vector2i(int(uv.x), int(uv.y)), "frac": frac, "behind": behind}


func _mean_luma(img: Image) -> float:
	if img == null:
		return -1.0
	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0:
		return -1.0
	var acc := 0.0
	var n := 0
	for y in range(0, h, 16):
		for x in range(0, w, 16):
			var c := img.get_pixel(x, y)
			acc += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
	return acc / float(maxi(n, 1))


func _v3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


# ============================================================ 阶段 A 外观 =
func _stage_look() -> void:
	print("[V4SHOT] --- stage LOOK ---")
	# 移到草坪开阔地：门前甲板太窄，背面机位会进墙
	_v.call("force_walk_to_node", "lawn")
	var arrived := await _wait_state("IDLE", 40.0)
	if not arrived:
		_fails.append("look_move")
	_v.call("force_idle", 1.0e9)
	await _settle(50)
	_freeze()
	var c := _model_aabb().get_center()
	var fwd := _mfw()
	var right := _mrt()
	var head := _head_pos()
	var torso := _torso_pos()
	await _shot("v_front", "正面全身：固定服装（白内衬+绿色防水背带裤）、脸与发型、toon 描边",
		c + fwd * 3.0 + Vector3(0.0, 0.12, 0.0), c, 40.0)
	await _shot("v_side", "侧面全身：站立轮廓、身体厚度、服装侧面接缝、手臂自然下垂",
		c + (right * 0.88 + fwd * 0.48).normalized() * 3.0 + Vector3(0.0, 0.12, 0.0), c, 40.0)
	await _shot("v_back", "背面全身：发型后轮廓、肩带背面、腰臀与裤腿连贯",
		c - fwd * 3.0 + Vector3(0.0, 0.12, 0.0), c, 40.0)
	await _shot("v_idle_34", "待机 3/4 视角：站姿重心、呼吸起伏、头部小幅观察",
		c + (fwd + right * 0.8).normalized() * 2.8 + Vector3(0.0, 0.20, 0.0), c, 40.0)
	await _shot("v_face_close", "面部近景：眼睛高光/眉/鼻/嘴、耳、头颈发际线",
		head + fwd * 0.92 + Vector3(0.0, 0.03, 0.0), head + Vector3(0.0, -0.02, 0.0), 34.0, head)
	await _shot("v_cloth_detail", "服装细节近景：白色内衬领口/袖、绿色胸兜、肩带、扣件、前置口袋",
		torso + fwd * 1.05 + right * 0.35 + Vector3(0.0, 0.10, 0.0), torso + Vector3(0.0, -0.02, 0.0), 38.0)
	_v.call("set_hair_style", 0)
	await _settle(3)
	await _shot("v_hair0", "发型 0（偏短）对照：同机位同姿势，仅发型不同",
		head + fwd * 0.78 + right * 0.32 + Vector3(0.0, 0.16, 0.0), head, 36.0, head)
	_v.call("set_hair_style", 1)
	await _settle(3)
	await _shot("v_hair1", "发型 1（中长）对照：身体/面部/服装与发型 0 完全一致",
		head + fwd * 0.78 + right * 0.32 + Vector3(0.0, 0.16, 0.0), head, 36.0, head)
	_v.call("set_hair_style", 0)
	await _settle(2)
	await _shot("v_day", "白天外观：正午 12:20 暖光下的完整角色",
		c + fwd * 3.2 + Vector3(0.0, 0.12, 0.0), c, 40.0)
	_set_time(T_DUSK)
	await _settle(6)
	await _shot("v_dusk", "黄昏外观：17:25 低角度暖光下的角色明暗",
		c + fwd * 3.2 + Vector3(0.0, 0.12, 0.0), c, 40.0)
	_set_time(T_NIGHT)
	await _settle(6)
	await _shot("v_night", "夜间外观：22:00 月光/门廊灯下的角色可读性",
		c + fwd * 3.2 + Vector3(0.0, 0.12, 0.0), c, 40.0)
	_set_time(T_DAY)
	await _settle(4)
	await _thaw()
	print("[V4SHOT] LOOK done")


# ============================================================ 阶段 B 行走 =
func _stage_walk() -> void:
	print("[V4SHOT] --- stage WALK ---")
	_v.call("force_idle", 0.05)
	await _settle(2)
	# 先确保在室外门廊：LOOK 阶段结束时角色可能已在 lawn（否则直接 walk lawn 会立即到达）
	_v.call("force_walk_to_node", "deck")
	await _wait_state("IDLE", 20.0)
	await _settle(2)
	var ok := bool(_v.call("force_walk_to_node", "lawn"))
	print("[V4SHOT] force_walk_to_node(lawn)=", ok)
	# 门廊上的侧后机位会被柱子/屋檐挡住：等角色走下台阶到开阔草地再抓第一张
	var g0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - g0 < 20000:
		await process_frame
		if _state() != "WALK":
			break
		if _v.global_position.y < 7.98:
			break
	await _cap_phase("v_walk_a", "行走 contact A：前腿伸出/后腿蹬地，双臂反向摆动",
		"WALK", 0.02, 0.14,
		func() -> Vector3: return _model_aabb().get_center() + _mrt() * 2.9 + Vector3(0.0, 0.10, 0.0),
		func() -> Vector3: return _model_aabb().get_center(), 40.0, 12.0)
	var got := await _wait_state("IDLE", 20.0)
	print("[V4SHOT] walk arrive(lawn)=", got, " pos=", _f3(_v.global_position))
	# 再走一段开阔草地长路线，抓另外两个相位（避免门廊结构挡镜头）
	var ok2 := bool(_v.call("force_walk_to_node", "tree_view"))
	print("[V4SHOT] force_walk_to_node(tree_view)=", ok2)
	await _cap_phase("v_walk_b", "行走 contact B：另一次触地，手臂摆动相反，验证非滑步",
		"WALK", 0.47, 0.58,
		func() -> Vector3: return _model_aabb().get_center() - _mrt() * 2.7 + Vector3(0.0, 0.18, 0.0),
		func() -> Vector3: return _model_aabb().get_center(), 40.0, 12.0)
	await _cap_phase("v_walk_side", "行走 passing 相位：支撑腿直立、摆动腿越过、身体起伏",
		"WALK", 0.22, 0.33,
		func() -> Vector3: return _model_aabb().get_center() + (_mfw() + _mrt() * 0.55).normalized() * 3.0 + Vector3(0.0, 0.10, 0.0),
		func() -> Vector3: return _model_aabb().get_center(), 40.0, 12.0)
	var got2 := await _wait_state("IDLE", 30.0)
	print("[V4SHOT] walk arrive(tree_view)=", got2, " pos=", _f3(_v.global_position))
	if not got:
		_fails.append("walk_arrive")
	print("[V4SHOT] WALK done")


# ============================================================ 阶段 C 楼梯 =
func _stage_stairs() -> void:
	print("[V4SHOT] --- stage STAIRS ---")
	_v.call("force_idle", 0.05)
	await _settle(2)
	var ok := bool(_v.call("force_walk_to_node", "attic_exit"))
	print("[V4SHOT] force_walk_to_node(attic_exit)=", ok)
	if not ok:
		_fails.append("stairs_plan")
	await _cap_stairs("v_stairs_mid", "楼梯中段通行：脚踩真实踏步、沿坡面前进、不穿梯梁/扶手",
		1.02, 1.48, Vector3(-1.55, 0.80, 2.45), 60.0)
	await _cap_stairs("v_stairs_landing", "楼梯转角平台：真实转向与平台踏面，人物完整站立",
		1.66, 1.98, Vector3(-0.60, 0.15, 2.90), 60.0, true)
	var got := await _wait_state("IDLE", 30.0)
	print("[V4SHOT] stairs arrive=", got, " pos=", _f3(_v.global_position))
	if not got:
		_fails.append("stairs_arrive")
	print("[V4SHOT] STAIRS done")


func _cap_stairs(id: String, desc: String, ylo: float, yhi: float, cam_off: Vector3, fov: float, target_head: bool = false) -> bool:
	if not _want(id):
		return true
	var t0 := Time.get_ticks_msec()
	var limit := 120000
	var slowed := false
	while Time.get_ticks_msec() - t0 < limit:
		await process_frame
		if _state() != "WALK":
			if slowed:
				Engine.time_scale = 1.0
				slowed = false
			continue
		if not slowed:
			Engine.time_scale = 0.30
			slowed = true
		var lp := _local_inv(_v.global_position)
		if lp.y < ylo or lp.y > yhi:
			continue
		var c := _model_aabb().get_center()
		if target_head:
			c = _head_pos() - Vector3(0.0, 0.10, 0.0)
		var cam := _local(lp + cam_off)
		await _shot(id, desc, cam, c, fov)
		Engine.time_scale = 1.0
		return true
	Engine.time_scale = 1.0
	print("[V4SHOT] MISS stairs band ", id, " state=", _state(), " local=", _f3(_local_inv(_v.global_position)))
	_fails.append("stairs:" + id)
	return false


# ============================================================ 阶段 D 进食 =
func _stage_eat() -> void:
	print("[V4SHOT] --- stage EAT ---")
	_v.call("force_idle", 0.05)
	await _settle(2)
	var ok := bool(_v.call("force_eat", "eat_s"))
	print("[V4SHOT] force_eat(eat_s)=", ok)
	if not ok:
		_fails.append("eat_plan")
		return
	await _cap_phase("v_sit_down_mid", "餐桌旁坐下过渡中段：骨盆下沉/屈膝/上半身前倾，脚不穿桌腿",
		"SIT_IN", 0.24, 0.52,
		func() -> Vector3:
			var h := _head_pos()
			return h + _mfw() * 1.9 + _mrt() * 0.95 + Vector3(0.0, 0.30, 0.0),
		func() -> Vector3: return _torso_pos(), 50.0, 60.0)
	var got := await _wait_state("EAT", 60.0)
	print("[V4SHOT] eat state=", got, " pos=", _f3(_v.global_position))
	if not got:
		_fails.append("eat_state")
		return
	# 等到进食手势抬起（手靠近嘴）的相位再冻结：否则会停在手放桌面的起始相位
	var t_eat := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_eat < 9000:
		await process_frame
		var cp_e := _clip_pos()
		if cp_e >= 0.55 and cp_e <= 0.63:
			break
	_freeze()
	var c := _model_aabb().get_center()
	var h := _head_pos()
	await _shot("v_eat", "餐桌进食：坐在真实餐椅上，手取食靠近嘴、头部/躯干细节",
		h + _mfw() * 1.45 + _mrt() * 1.15 + Vector3(0.0, 0.28, 0.0), _torso_pos() + Vector3(0.0, -0.10, 0.0), 46.0)
	await _shot("v_eat_close", "进食近景：手—嘴距离、咀嚼表情、餐桌面关系（不穿模）",
		h + _mfw() * 1.15 + _mrt() * 0.95 + Vector3(0.0, 0.30, 0.0), h + Vector3(0.0, -0.08, 0.0), 42.0, h)
	await _thaw()
	_v.set("_hold_t", 999.0)
	await _settle(3)
	await _cap_phase("v_sit_stand_mid", "餐椅起身过渡中段：脚落地、身体前移站起，不瞬移离开座椅",
		"SIT_OUT", 0.20, 0.46,
		func() -> Vector3:
			var hh := _head_pos()
			return hh + _mfw() * 1.9 + _mrt() * 0.95 + Vector3(0.0, 0.30, 0.0),
		func() -> Vector3: return _torso_pos(), 50.0, 20.0)
	await _wait_state("IDLE", 10.0)
	print("[V4SHOT] EAT done")


# ============================================================ 阶段 E 坐休 =
func _stage_sit() -> void:
	print("[V4SHOT] --- stage SIT ---")
	_v.call("force_idle", 0.05)
	await _settle(2)
	var ok := bool(_v.call("force_sit", "sofa"))
	print("[V4SHOT] force_sit(sofa)=", ok)
	if not ok:
		_fails.append("sit_plan")
		return
	var got := await _wait_state("SIT", 40.0)
	print("[V4SHOT] sit state=", got, " pos=", _f3(_v.global_position))
	if not got:
		_fails.append("sit_state")
		return
	await _settle(60)
	_freeze()
	var h := _head_pos()
	var torso := _torso_pos()
	await _shot("v_sit_sofa", "沙发休息：骨盆真实落在座面、脚落地、轻微呼吸/观察姿态",
		torso + _mfw() * 2.15 + _mrt() * 0.95 + Vector3(0.0, 0.35, 0.0), torso, 50.0)
	await _shot("v_sit_close", "坐姿近景：坐高与座面对齐、膝/踝自然、服装与座面接触",
		h + _mfw() * 1.15 + _mrt() * 0.60 + Vector3(0.0, 0.06, 0.0), h + Vector3(0.0, -0.10, 0.0), 36.0, h)
	await _thaw()
	_v.set("_hold_t", 999.0)
	await _settle(3)
	await _cap_phase("v_stand_up_mid", "从沙发起身过渡中段：自然蹬地站起，无姿态跳变",
		"SIT_OUT", 0.18, 0.45,
		func() -> Vector3:
			var hh := _head_pos()
			return hh + _mfw() * 1.4 + _mrt() * 0.85 + Vector3(0.0, 0.30, 0.0),
		func() -> Vector3: return _torso_pos(), 50.0, 20.0)
	await _wait_state("IDLE", 10.0)
	print("[V4SHOT] SIT done")


# ============================================================ 阶段 F 床 ====
func _stage_bed() -> void:
	print("[V4SHOT] --- stage BED ---")
	_v.call("force_idle", 0.05)
	await _settle(2)
	var ok := bool(_v.call("force_bed"))
	print("[V4SHOT] force_bed=", ok)
	if not ok:
		_fails.append("bed_plan")
		return
	var bed_cam := _local(Vector3(1.30, 4.15, 1.85))
	await _cap_phase("v_bed_sit_down", "坐床沿过渡：臀部落床沿、双脚垂下、头与枕头方向",
		"BED_IN", 0.50, 0.68,
		func() -> Vector3: return _local(Vector3(-0.10, 4.06, 1.02)),
		func() -> Vector3: return _torso_pos(), 46.0, 70.0)
	await _cap_phase("v_lie_down_mid", "躺下过渡中段：头/躯干/腿连续转向卧姿，身体在床垫上方",
		"LIE_IN", 0.30, 0.68,
		func() -> Vector3: return bed_cam,
		func() -> Vector3: return _model_aabb().get_center(), 50.0, 40.0)
	var got := await _wait_state("SLEEP", 70.0)
	print("[V4SHOT] sleep state=", got, " pos=", _f3(_v.global_position))
	if not got:
		_fails.append("sleep_state")
		return
	await _settle(40)
	_freeze()
	var bc := _model_aabb().get_center()
	await _shot("v_sleep", "床上睡眠：身体正确躺在床垫表面、头与枕头协调、轻呼吸、闭眼",
		bed_cam, bc, 50.0)
	await _shot("v_sleep_close", "睡眠近景：背部贴合床垫、头在枕头上、屈膝侧头闭眼、手臂位置",
		_local(Vector3(-0.35, 4.28, 0.34)), bc + Vector3(0.0, 0.02, 0.0), 40.0)
	await _thaw()
	_v.set("_hold_t", 999.0)
	await _settle(3)
	await _cap_phase("v_lie_out_mid", "睡醒起身过渡（卧→坐）中段：连续抬身，不是瞬移",
		"LIE_OUT", 0.28, 0.64,
		func() -> Vector3: return bed_cam,
		func() -> Vector3: return _model_aabb().get_center(), 50.0, 20.0)
	await _cap_phase("v_bed_up_mid", "床沿起身过渡中段：从坐床沿到落地站起，root 连续插回地面",
		"BED_OUT", 0.20, 0.55,
		func() -> Vector3: return bed_cam,
		func() -> Vector3: return _torso_pos(), 50.0, 20.0)
	await _wait_state("IDLE", 10.0)
	print("[V4SHOT] BED done")


# ============================================================ 相位捕获 =====
func _cap_phase(id: String, desc: String, st: String, lo: float, hi: float,
		cam_fn: Callable, target_fn: Callable, fov: float, timeout_s: float) -> bool:
	if not _want(id):
		return true
	var t0 := Time.get_ticks_msec()
	var limit := int(timeout_s * 1000.0)
	var slowed := false
	while Time.get_ticks_msec() - t0 < limit:
		await process_frame
		if _state() != st:
			if slowed:
				Engine.time_scale = 1.0
				slowed = false
			continue
		if not slowed:
			Engine.time_scale = 0.15
			slowed = true
		var cp := _clip_pos()
		if cp < lo or cp > hi:
			continue
		var cam: Vector3 = cam_fn.call()
		var tgt: Vector3 = target_fn.call()
		await _shot(id, desc, cam, tgt, fov)
		Engine.time_scale = 1.0
		return true
	Engine.time_scale = 1.0
	print("[V4SHOT] MISS phase ", id, " state=", st, " cp=", _clip_pos(), " now=", _state())
	_fails.append("phase:" + id)
	return false


# ============================================================ 清单 =========
func _write_manifest() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var meta := {
		"probe": "tools/probe_villager_shots.gd",
		"generated_at": Time.get_datetime_string_from_system(false, true),
		"engine": Engine.get_version_info().get("string", "?"),
		"renderer": DisplayServer.get_name(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"resolution": [SHOT_W, SHOT_H],
		"stage": _stage,
		"only": _only,
		"shots": _manifest,
		"fails": _fails,
	}
	var f := FileAccess.open(OUT_DIR + "villager_shots_manifest.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(meta, "  "))
		f.close()
	var md := "# P7-V4 岛民视觉验收截图清单\n\n"
	md += "- 工具：tools/probe_villager_shots.gd（真实窗口 1600x900）\n"
	md += "- 场景：真实 isle.tscn，真实 villager 状态机/路径/活动点；静止帧暂停取景，过渡帧 time_scale 慢放抓相位\n"
	md += "- 生成时间：%s\n" % Time.get_datetime_string_from_system(false, true)
	md += "- 引擎：%s / GPU：%s\n\n" % [Engine.get_version_info().get("string", "?"), RenderingServer.get_video_adapter_name()]
	md += "| 文件 | 状态/剪辑 | 内容 | 角色位置 | 屏幕点 | 画面占比 | 平均亮度 |\n"
	md += "| --- | --- | --- | --- | --- | --- | --- |\n"
	for m_v in _manifest:
		var m: Dictionary = m_v
		var sc: Array = m.get("screen_uv", [0, 0])
		md += "| %s | %s/%s | %s | (%.2f,%.2f,%.2f) | (%d,%d) | %.2f | %.3f |\n" % [
			String(m.get("file", "")), String(m.get("state", "")), String(m.get("clip", "")),
			String(m.get("desc", "")),
			float(m["villager_pos"][0]), float(m["villager_pos"][1]), float(m["villager_pos"][2]),
			int(sc[0]), int(sc[1]), float(m.get("screen_frac", 0.0)), float(m.get("luma", 0.0))]
	if not _fails.is_empty():
		md += "\n## 失败项\n\n"
		for x in _fails:
			md += "- %s\n" % String(x)
	var mf := FileAccess.open(OUT_DIR + "MANIFEST_villager.md", FileAccess.WRITE)
	if mf != null:
		mf.store_string(md)
		mf.close()
	print("[V4SHOT] manifest -> ", OUT_DIR + "MANIFEST_villager.md")
