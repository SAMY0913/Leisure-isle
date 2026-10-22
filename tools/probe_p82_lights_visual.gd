extends SceneTree

# P8.2-02 灯光视觉探针：像素 → 对象定位（halo / self_lit 灯泡 / 灯罩），以及视觉修复证据截图。
# 用法（都要真实窗口，不要 --headless）：
#   Godot --path <工程> --resolution 1600x900 --script res://tools/probe_p82_lights_visual.gd -- --mode=diag --out=<证据目录>
#   Godot --path <工程> --resolution 1600x900 --script res://tools/probe_p82_lights_visual.gd -- --mode=shots --out=<证据目录>
#
# diag 模式：设 IsleCottage.probe_skip_batch=true（保留逐件 MeshInstance），摆到 day_room_wide 机位，
#   把全部 halo（StandardMaterial3D 加色 billboard）、self_lit 网格（灯泡/灯罩/火焰）、SphereMesh 灯泡投影到屏幕，
#   并对 --px 指定的像素点做射线/AABB 求交，打印最近命中与同屏候选（含节点路径、相机距离、像素半径）。
#   默认 px=1587,331 与 1613,274（2560x1440 口径，即 lead 指出的两个悬空发光小球）。

const OUT_DIR := "D:/休闲小岛幻境/开发产物/p82/02_lighting/shots/"

var _mode := "diag"
var _out := OUT_DIR
var _queries: Array = []
var _only: Array = []
var _isle: Node = null
var _root: Node3D = null
var _C: Dictionary = {}
var _fy := 0.55
var _in_top := 2.97
var _ch_x := -2.20
var _ch_z := -2.60
var _cands: Array = []

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--mode="):
			_mode = s.substr(7)
		elif s.begins_with("--out="):
			_out = s.substr(6)
		elif s.begins_with("--only="):
			_only = s.substr(7).split(",")
		elif s.begins_with("--px="):
			var parts := s.substr(5).split(",")
			if parts.size() == 2:
				_queries.append(Vector2(float(parts[0]), float(parts[1])))
	_run.call_deferred()

func _wait(sec: float) -> void:
	await create_timer(sec).timeout

func _w(local: Vector3) -> Vector3:
	return _root.to_global(local)

func _run() -> void:
	var booted := await _boot()
	if not booted:
		quit(1)
		return
	if _mode == "isolate":
		await _isolate()
		print("[P82LV] SUMMARY mode=isolate done out=" + _out)
		quit(0)
		return
	if _mode == "batch":
		await _batch_bisect()
		print("[P82LV] SUMMARY mode=batch done out=" + _out)
		quit(0)
		return
	if _mode == "shots":
		await _shots()
		print("[P82LV] SUMMARY mode=shots done out=" + _out)
		quit(0)
		return
	if _mode == "band":
		await _band()
		print("[P82LV] SUMMARY mode=band done out=" + _out)
		quit(0)
		return
	if _mode == "bandperf":
		await _band_perf()
		print("[P82LV] SUMMARY mode=bandperf done out=" + _out)
		quit(0)
		return
	if _mode == "qa":
		await _quality_affirm()
		print("[P82LV] SUMMARY mode=qa done out=" + _out)
		quit(0)
		return
	if _mode == "nodes":
		await _node_probe()
		print("[P82LV] SUMMARY mode=nodes done out=" + _out)
		quit(0)
		return
	if _mode == "isolate3":
		await _isolate3()
		print("[P82LV] SUMMARY mode=isolate3 done out=" + _out)
		quit(0)
		return
	if _mode == "isolate2":
		await _isolate2()
		print("[P82LV] SUMMARY mode=isolate2 done out=" + _out)
		quit(0)
		return
	await _diag()
	quit(0)

func _boot() -> bool:
	if _mode == "diag" or _mode == "isolate":
		IsleCottage.probe_skip_batch = true
	var packed: PackedScene = load("res://isle.tscn")
	if packed == null:
		print("[P82LV] FAIL isle.tscn 不可加载")
		return false
	_isle = packed.instantiate()
	root.add_child(_isle)
	for i in range(6):
		await process_frame
	var c = _isle._cottage
	if not (c is Dictionary and c.has("root")):
		print("[P82LV] FAIL cottage 字典缺失")
		return false
	_root = c["root"]
	_C = _root.get_meta("cottage_ctx")
	_fy = float(_C["fy"])
	_in_top = float(_C["in_top"])
	_ch_x = float(_C["ch_x"])
	_ch_z = float(_C["ch_z"])
	print("[P82LV] boot ok fy=%.3f in_top=%.3f ch_x=%.3f ch_z=%.3f" % [_fy, _in_top, _ch_x, _ch_z])
	return true

# ---------------------------------------------------------------- 通用：摆机位/固定场景
func _prepare() -> void:
	_isle._mode = 1
	_isle._started = true
	_isle._paused = true
	_isle._blending = ""
	if _isle._menu != null:
		_isle._menu.instant_finish()
	if _isle._hud != null:
		_isle._hud.set_hud_visible(false, false)
	_isle._auto_orbit = false
	_isle._shot_beam_lock = true
	_isle._time_source = "sim"
	await _wait(0.8)

func _cam(eye_local: Vector3, target_local: Vector3, fov: float) -> void:
	_isle._pose_look(_w(eye_local), _w(target_local), fov)

func _skip(tag: String) -> bool:
	return not _only.is_empty() and not _only.has(tag)

func _pixel_dir(cam: Camera3D, ix: float, iy: float) -> Vector3:
	# 2560x1440 图像坐标 → 世界方向（相机基向量直接构造，避免依赖 viewport 尺寸）
	var vp := Vector2(1600.0, 900.0)
	var ndc := Vector2(ix / 2560.0 * vp.x, iy / 1440.0 * vp.y)
	var half_h: float = tan(deg_to_rad(cam.fov) * 0.5)
	var half_w: float = half_h * (vp.x / vp.y)
	var fwd: Vector3 = -cam.global_transform.basis.z
	var right: Vector3 = cam.global_transform.basis.x
	var up: Vector3 = cam.global_transform.basis.y
	var dir: Vector3 = fwd + right * ((ndc.x / vp.x * 2.0 - 1.0) * half_w) + up * (-(ndc.y / vp.y * 2.0 - 1.0) * half_h)
	return dir.normalized()

func _shot(tag: String) -> void:
	if _skip(tag):
		return
	await _isle._save_shot(tag, _out)

# 一层广角机位（lead 指认的三处缺陷都在这张图里）
func _cam_room_wide() -> void:
	_cam(Vector3(1.30, _fy + 1.75, 2.20), Vector3(-1.60, _fy + 0.95, -2.55), 62.0)

# ---------------------------------------------------------------- diag
func _mat_kind(mi: MeshInstance3D) -> String:
	var m: Material = mi.material_override
	if m == null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
		m = mi.mesh.surface_get_material(0)
	if m is StandardMaterial3D:
		var sm := m as StandardMaterial3D
		if sm.blend_mode == BaseMaterial3D.BLEND_MODE_ADD:
			return "halo"
		return "standard"
	if m is ShaderMaterial:
		var sh := m as ShaderMaterial
		if sh.shader != null and String(sh.shader.code).find("self_lit") >= 0:
			if float(sh.get_shader_parameter("self_lit") if sh.get_shader_parameter("self_lit") != null else 0.0) >= 0.5:
				return "self_lit"
		return "toon"
	return "other"

func _halo_size(mi: MeshInstance3D) -> float:
	if mi.mesh is QuadMesh:
		return (mi.mesh as QuadMesh).size.x
	return 0.0

func _mat_desc(mi: MeshInstance3D) -> String:
	var m: Material = mi.material_override
	if m == null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
		m = mi.mesh.surface_get_material(0)
	if m is StandardMaterial3D:
		var col: Color = (m as StandardMaterial3D).albedo_color
		return "albedo=(%.2f,%.2f,%.2f,%.2f)" % [col.r, col.g, col.b, col.a]
	if m is ShaderMaterial:
		var sh := m as ShaderMaterial
		var g: Variant = sh.get_shader_parameter("glow")
		var sl: Variant = sh.get_shader_parameter("self_lit")
		return "glow=%s self_lit=%s" % [str(g), str(sl)]
	return "?"

func _walk(n: Node) -> void:
	for ch in n.get_children():
		if ch is MultiMeshInstance3D:
			continue
		if ch is MeshInstance3D:
			var mi := ch as MeshInstance3D
			_cands.append({
				"node": mi,
				"path": str(mi.get_path()),
				"kind": _mat_kind(mi),
				"world": mi.global_position,
				"halo": _halo_size(mi),
				"desc": _mat_desc(mi),
				"aabb": mi.global_transform * mi.get_aabb(),
			})
		_walk(ch)

func _diag() -> void:
	await _prepare()
	_isle._apply_quality(2)
	_isle._p8_wfx_apply(2027, 1, 15, 14, 0, "clear", 0.0)
	await _wait(0.8)
	_cam_room_wide()
	await _wait(0.4)
	var cam: Camera3D = _isle._cam
	var vp := cam.get_viewport().get_visible_rect().size
	var img_size: Vector2i = get_root().get_texture().get_image().get_size()
	print("[P82LV] viewport=%.0fx%.0f image=%dx%d fov=%.2f" % [vp.x, vp.y, img_size.x, img_size.y, cam.fov])
	print("[P82LV] camera_world=" + str(cam.global_position) + " cam_target=" + str(_isle._cam_target))
	_cands.clear()
	_walk(_root)
	var focal: float = (vp.y * 0.5) / tan(deg_to_rad(cam.fov) * 0.5)
	var qs: Array = _queries.duplicate()
	if qs.is_empty():
		qs = [Vector2(1587, 331), Vector2(1613, 274), Vector2(984, 820), Vector2(210, 304)]
	# 全部候选的屏幕投影
	var on_screen: Array = []
	for c in _cands:
		var kind: String = c["kind"]
		if kind == "toon" or kind == "standard" or kind == "other":
			continue
		var wp: Vector3 = c["world"]
		var dist: float = cam.global_position.distance_to(wp)
		var behind: bool = cam.is_position_behind(wp)
		var px: Vector2 = cam.unproject_position(wp)
		var rad_px: float = 0.0
		if c["halo"] > 0.0:
			rad_px = float(c["halo"]) * 0.5 * focal / maxf(dist, 0.01)
		elif (c["node"] as MeshInstance3D).mesh is SphereMesh:
			rad_px = float(((c["node"] as MeshInstance3D).mesh as SphereMesh).radius) * focal / maxf(dist, 0.01)
		var rec := {"kind": kind, "px": px, "dist": dist, "rad_px": rad_px, "path": c["path"], "world": wp, "desc": c["desc"], "halo": c["halo"], "behind": behind}
		if not behind and px.x >= -rad_px and px.x <= vp.x + rad_px and px.y >= -rad_px and px.y <= vp.y + rad_px:
			on_screen.append(rec)
	# 打印 halo / 灯泡总览（按屏幕面积降序）
	on_screen.sort_custom(func(a, b): return float(a["rad_px"]) > float(b["rad_px"]))
	print("[P82LV] on_screen_glow_candidates=%d (halo + self_lit + sphere bulbs)" % on_screen.size())
	for rec in on_screen:
		var sx: float = float(rec["px"].x) / vp.x * img_size.x
		var sy: float = float(rec["px"].y) / vp.y * img_size.y
		print("[P82LV] CAND kind=%s px_img=(%.0f,%.0f) dist=%.2fm rad_px=%.1f size=%.2f %s | %s" % [rec["kind"], sx, sy, rec["dist"], rec["rad_px"], rec["halo"], rec["desc"], rec["path"]])
	# 查询像素：射线 + 最近 AABB 命中 + 附近候选
	var space: PhysicsDirectSpaceState3D = _isle.get_world_3d().direct_space_state
	for q in qs:
		var qv := Vector2(float(q.x) / img_size.x * vp.x, float(q.y) / img_size.y * vp.y)
		print("[P82LV] --- QUERY img_px=(%.0f,%.0f) viewport_px=(%.1f,%.1f)" % [q.x, q.y, qv.x, qv.y])
		var o: Vector3 = cam.project_ray_origin(qv)
		var d: Vector3 = cam.project_ray_normal(qv)
		# 1) 物理射线（真实碰撞体）
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(o, o + d * 60.0))
		if hit.is_empty():
			print("[P82LV]   physics_ray: no hit")
		else:
			print("[P82LV]   physics_ray: t=%.3f collider=%s" % [o.distance_to(hit["position"]), str(hit["collider"].get_path() if hit["collider"] is Node else hit["collider"])])
		# 2) 全部候选 AABB 求交（含 halo/灯罩，找沿射线最近的对象）
		var hits: Array = []
		for c in _cands:
			var bb: AABB = c["aabb"]
			var hp: Variant = bb.intersects_ray(o, d)
			if hp != null:
				hits.append({"t": o.distance_to(hp), "path": c["path"], "kind": c["kind"], "world": c["world"], "desc": c["desc"]})
		hits.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
		print("[P82LV]   aabb_hits=%d" % hits.size())
		for h in hits.slice(0, 12):
			print("[P82LV]     t=%.3f kind=%s world=%s %s | %s" % [h["t"], h["kind"], str(h["world"]), h["desc"], h["path"]])
		# 2b) 屏幕距离 <=45px 的**全部** MeshInstance（不限发光类别）
		var near_all: Array = []
		for c in _cands:
			var mi2 := c["node"] as MeshInstance3D
			var wp2: Vector3 = c["world"]
			if cam.is_position_behind(wp2):
				continue
			var sp2: Vector2 = cam.unproject_position(wp2)
			var dpx2: float = sp2.distance_to(qv)
			if dpx2 <= 45.0:
				near_all.append({"dpx": dpx2, "c": c, "px": sp2})
		near_all.sort_custom(func(a, b): return float(a["dpx"]) < float(b["dpx"]))
		print("[P82LV]   near_all_meshes=%d" % near_all.size())
		for n in near_all.slice(0, 14):
			var c: Dictionary = n["c"]
			print("[P82LV]     dpx=%.1f kind=%s world=%s mesh=%s %s | %s" % [n["dpx"], c["kind"], str(c["world"]), (c["node"] as MeshInstance3D).mesh.get_class() if (c["node"] as MeshInstance3D).mesh != null else "null", c["desc"], c["path"]])
		# 3) 屏幕距离 <40px 的发光候选
		var near: Array = []
		for rec in on_screen:
			var sp: Vector2 = rec["px"]
			var dpx: float = sp.distance_to(qv)
			if dpx <= 40.0:
				near.append({"dpx": dpx, "rec": rec})
		near.sort_custom(func(a, b): return float(a["dpx"]) < float(b["dpx"]))
		print("[P82LV]   near_glow_candidates=%d" % near.size())
		for n in near:
			var rec: Dictionary = n["rec"]
			print("[P82LV]     dpx=%.1f kind=%s dist=%.2fm rad_px=%.1f %s | %s" % [n["dpx"], rec["kind"], rec["dist"], rec["rad_px"], rec["desc"], rec["path"]])
	# 萤火/粒子：确认白天是否仍有发光粒子
	var ff: Dictionary = _isle._fx.get("fireflies", {})
	if ff.has("node"):
		var fn: GPUParticles3D = ff["node"] as GPUParticles3D
		print("[P82LV] fireflies node=%s world=%s emitting=%s amount_ratio=%.3f visible=%s" % [str(fn.get_path()), str(fn.global_position), str(fn.emitting), fn.amount_ratio, str(fn.visible)])
	else:
		print("[P82LV] fireflies node: (none in _fx)")
	# 灯罩/灯泡材质与发光数组归属
	print("[P82LV] window_halos=%d lantern_halos=%d lamp_halos=%d interior_shade_mats=%d" % [
		int(_isle._window_halos.size()), int(_isle._lantern_halos.size()), int(_isle._lamp_halos.size()), int(_isle._interior_shade_mats.size())])
	for nm in ["_window_halos", "_lantern_halos", "_lamp_halos"]:
		var arr: Array = _isle.get(nm)
		for h in arr:
			if h is MeshInstance3D:
				print("[P82LV] %s: %s world=%s" % [nm, str((h as MeshInstance3D).get_path()), str((h as MeshInstance3D).global_position)])

# ---------------------------------------------------------------- shots
func _scene(year: int, month: int, day: int, hour: int, minute: int, type_id: String, accum: float) -> void:
	_isle._p8_wfx_apply(year, month, day, hour, minute, type_id, accum)
	await _wait(0.7)

func _cam_chand_near() -> void:
	_cam(Vector3(0.85, _fy + 1.95, 1.55), Vector3(1.45, _in_top - 0.62, 0.80), 55.0)

func _cam_chand_far() -> void:
	_cam(Vector3(-1.80, _fy + 1.20, 2.55), Vector3(1.45, _in_top - 0.62, 0.80), 60.0)

func _cam_fire_low() -> void:
	_cam(Vector3(_ch_x + 0.10, _fy + 0.95, -0.95), Vector3(_ch_x, _fy + 0.45, -2.60), 52.0)

func _cam_door_inside() -> void:
	_cam(Vector3(0.0, _fy + 1.60, 1.30), Vector3(0.0, _fy + 1.30, 3.20), 60.0)

func _cam_window_inside() -> void:
	_cam(Vector3(0.20, _fy + 1.75, 0.50), Vector3(0.20, _fy + 1.90, -2.90), 55.0)

func _cam_porch() -> void:
	_cam(Vector3(0.20, _fy + 1.95, 6.10), Vector3(-1.95, 2.05, 4.55), 55.0)

## 把「分析用关键世界点」投影成 2560x1440 图像坐标，写进日志，供像素脚本确定 ROI。
func _emit_px(tag: String) -> void:
	if _skip(tag):
		return
	var cam: Camera3D = _isle._cam
	var vp := cam.get_viewport().get_visible_rect().size
	var img: Vector2i = get_root().get_texture().get_image().get_size()
	var pts := {
		"chand": _w(Vector3(1.45, _in_top - 0.62, 0.80)),
		"attic_lamp": _w(Vector3(0.20, 5.33, 0.90)),
		"hearth_c": _w(Vector3(_ch_x, _fy + 0.10, -2.24)),
		"hearth_l": _w(Vector3(_ch_x - 0.85, _fy + 0.05, -2.54)),
		"hearth_r": _w(Vector3(_ch_x + 0.85, _fy + 0.05, -1.94)),
		"firebox": _w(Vector3(_ch_x, _fy + 0.35, -2.70)),
		"door": _w(Vector3(0.0, _fy + 1.05, 2.80)),
		"win_back": _w(Vector3(0.20, _fy + 1.35, -2.80)),
	}
	var parts: Array = []
	for k in pts:
		var wp: Vector3 = pts[k]
		if cam.is_position_behind(wp):
			parts.append("%s=behind" % k)
			continue
		var sp: Vector2 = cam.unproject_position(wp)
		var ix: float = sp.x / vp.x * img.x
		var iy: float = sp.y / vp.y * img.y
		parts.append("%s=(%.0f,%.0f)" % [k, ix, iy])
	print("[P82LV] PX %s %s" % [tag, " ".join(parts)])

func _shots() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	await _prepare()
	_isle._apply_quality(2)
	# ---------- 白天 ----------
	await _scene(2027, 1, 15, 14, 0, "clear", 0.0)
	_cam_room_wide()
	await _shot("day_room_wide")
	_emit_px("day_room_wide")
	_cam_chand_far()
	await _shot("day_chand_far")
	_emit_px("day_chand_far")
	_cam_chand_near()
	await _shot("day_chand_near")
	_emit_px("day_chand_near")
	_cam_fire_low()
	await _shot("day_fire_low")
	_emit_px("day_fire_low")
	_cam_door_inside()
	await _shot("day_door_inside")
	_emit_px("day_door_inside")
	_cam_window_inside()
	await _shot("day_window_inside")
	_emit_px("day_window_inside")
	# ---------- 夜间 ----------
	await _scene(2027, 1, 15, 20, 30, "clear", 0.0)
	_cam_room_wide()
	await _shot("night_room_wide")
	_emit_px("night_room_wide")
	_cam_chand_far()
	await _shot("night_chand_far")
	_emit_px("night_chand_far")
	_cam_chand_near()
	await _shot("night_chand_near")
	_emit_px("night_chand_near")
	_cam_fire_low()
	await _shot("night_fire_low")
	_emit_px("night_fire_low")
	_cam_door_inside()
	await _shot("night_door_inside")
	_emit_px("night_door_inside")
	_cam_window_inside()
	await _shot("night_window_inside")
	_emit_px("night_window_inside")
	_cam_porch()
	await _shot("night_porch")
	_emit_px("night_porch")
	# ---------- 五档画质：夜间一层广角（q0 低画质仍应看出主要灯光） ----------
	for q in range(5):
		_isle._apply_quality(q)
		await _wait(0.6)
		_cam_room_wide()
		await _shot("q%d_night_room" % q)
	_isle._apply_quality(2)
	# ---------- 冬季 / 大雪 / 雨夜 ----------
	await _scene(2027, 1, 15, 14, 0, "clear", 1.0)
	_cam_room_wide()
	await _shot("winter_day_room")
	_emit_px("winter_day_room")
	await _scene(2027, 1, 15, 12, 0, "heavy_snow", 1.0)
	_cam_room_wide()
	await _shot("snow_day_room")
	_emit_px("snow_day_room")
	await _scene(2027, 7, 15, 20, 30, "heavy_rain", 1.0)
	_cam_room_wide()
	await _shot("rain_night_room")
	_emit_px("rain_night_room")
	# ---------- 岛屿夜景（码头灯/船灯/灯塔可读性） ----------
	await _scene(2027, 1, 15, 20, 30, "clear", 0.0)
	_isle._p8_camera_island()
	await _wait(0.5)
	await _shot("night_island_lights")
	_emit_px("night_island_lights")
	# ---------- P8.2-02(b) 对照：把壁炉光槽临时还原成旧参数（range 5.0 / energy 1.50），证明炉台过曝来源
	# 只改 main._lights 里 kind=="fireplace" 的条目（每帧 _update_lighting 从这里读 energy/range），不改任何资源/场景。
	await _scene(2027, 1, 15, 14, 0, "clear", 0.0)
	_restore_old_fire_light()
	await _wait(0.6)
	_cam_room_wide()
	await _shot("day_room_wide_fl15")
	_emit_px("day_room_wide_fl15")
	await _scene(2027, 1, 15, 20, 30, "clear", 0.0)
	await _wait(0.4)
	_cam_room_wide()
	await _shot("night_room_wide_fl15")
	_emit_px("night_room_wide_fl15")

## P8.2-02(c) 悬空加色球定位：枚举场景所有加色 billboard（halo/Glow/自发光），打印
## 节点路径 + 世界坐标 + 面片尺寸 + 颜色 + 所属调光数组 + 当前相机投影像素 + 估计屏幕半径，
## 并对 lead 报的三个可疑像素做最近邻匹配。全部来自真实运行，不靠肉眼 bisect。
func _node_probe() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	await _prepare()
	_isle._apply_quality(2)
	await _scene(2027, 1, 15, 20, 30, "clear", 0.0)
	_cam_room_wide()
	await _wait(0.6)
	var cam: Camera3D = _isle._cam
	var vp := cam.get_viewport().get_visible_rect().size
	var img: Vector2i = get_root().get_texture().get_image().get_size()
	print("[P82NODES] img=%s vp=%s cam_pos=%s cam_fov=%.2f" % [str(img), str(vp), str(cam.global_position), cam.fov])
	# ---- 数组归属表（实例 id -> 数组名[下标]）----
	var owner := {}
	var c: Dictionary = _isle._cottage
	var w: Dictionary = _isle._world
	for key in ["window_halos", "lantern_halos", "interior_halos", "lamp_halos"]:
		var arr: Array = []
		if c.has(key):
			arr = c[key]
		elif w.has(key):
			arr = w[key]
		else:
			var got = _isle.get(key)
			if got is Array:
				arr = got
		for i in range(arr.size()):
			var it = arr[i]
			if it is Node:
				owner[(it as Node).get_instance_id()] = "%s[%d]" % [key, i]
	# fireplace halo / boat halo 单独标注
	for k in ["fireplace_halo", "sailboat_lantern_halo"]:
		var g2 = _isle.get(k)
		if g2 == null:
			g2 = _isle._cottage.get(k)
		if g2 is Node:
			owner[(g2 as Node).get_instance_id()] = k
	var focal: float = (float(img.y) * 0.5) / tan(deg_to_rad(cam.fov * 0.5))
	var targets := [Vector2(412.0, 424.0), Vector2(1289.0, 472.0), Vector2(1259.0, 562.0)]
	var sx: float = float(img.x) / 2560.0
	var sy: float = float(img.y) / 1440.0
	var targets_img: Array = []
	for t in targets:
		targets_img.append(Vector2((t as Vector2).x * sx, (t as Vector2).y * sy))
	var cands: Array = []   # [{px,path,size,owner,albedo}]
	var emissive: Array = []
	var gi_list: Array = _isle.find_children("*", "MeshInstance3D", true, false)
	for gi in gi_list:
		var mi: MeshInstance3D = gi
		var nm := String(mi.name)
		var m: Material = mi.material_override
		if m == null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
			m = mi.mesh.surface_get_material(0)
		var additive := false
		var blend := -1
		var albedo := Color(0, 0, 0, 0)
		if m is StandardMaterial3D:
			blend = int((m as StandardMaterial3D).blend_mode)
			additive = blend == int(BaseMaterial3D.BLEND_MODE_ADD)
			albedo = (m as StandardMaterial3D).albedo_color
		var name_hit := ("Glow" in nm) or ("halo" in nm.to_lower()) or ("glow" in nm.to_lower())
		var quad := 0.0
		if mi.mesh is QuadMesh:
			quad = (mi.mesh as QuadMesh).size.x
		if additive or name_hit:
			var wp := mi.global_position
			var dist := cam.global_position.distance_to(wp)
			var px := Vector2(-1, -1)
			var pxstr := "behind"
			if not cam.is_position_behind(wp):
				var sp := cam.unproject_position(wp)
				px = Vector2(sp.x / vp.x * img.x, sp.y / vp.y * img.y)
				pxstr = "(%.0f,%.0f)" % [px.x, px.y]
			var rad_px := -1.0
			if dist > 0.01:
				rad_px = quad * 0.5 * focal / dist
			var ow := String(owner.get(mi.get_instance_id(), "-"))
			var par := ""
			if mi.get_parent() is Node:
				par = String((mi.get_parent() as Node).name)
			print("[P82NODES] additive=%s glow_name=%s path=%s parent=%s pos=%s size=%.3f albedo=(%.2f,%.2f,%.2f,%.2f) blend=%d dist=%.2f px=%s rad_px=%.1f owner=%s" % [
				str(additive), str(name_hit), String(_isle.get_path_to(mi)), par, str(wp), quad,
				albedo.r, albedo.g, albedo.b, albedo.a, blend, dist, pxstr, rad_px, ow])
			cands.append({"path": String(_isle.get_path_to(mi)), "px": px, "owner": ow})
		else:
			# 自发光但非加色（灯罩 / 灯泡）：记录下来，若有 glow 后处理会成为 bloom 圆盘
			if m is ShaderMaterial:
				var sl = (m as ShaderMaterial).get_shader_parameter("self_lit")
				var sl_on := false
				if sl is bool:
					sl_on = sl
				elif sl is float or sl is int:
					sl_on = float(sl) > 0.5
				if sl_on:
					emissive.append({"path": String(_isle.get_path_to(mi)), "pos": mi.global_position})
	print("[P82NODES] self_lit_nodes=%d" % emissive.size())
	for e in emissive:
		print("[P82NODES] emissive path=%s pos=%s" % [String((e as Dictionary)["path"]), str((e as Dictionary)["pos"])])
	# ---- 三个可疑像素的最近邻匹配 ----
	var idx := 0
	for t in targets_img:
		var best := ""
		var bestd := 1e9
		for cd in cands:
			var p2: Vector2 = (cd as Dictionary)["px"]
			if p2.x < 0.0:
				continue
			var dd: float = p2.distance_to(t)
			if dd < bestd:
				bestd = dd
				best = "%s owner=%s" % [String((cd as Dictionary)["path"]), String((cd as Dictionary)["owner"])]
		print("[P82NODES] MATCH target%d(%s) -> nearest %s dist=%.1fpx" % [idx, str(t), best if best != "" else "NONE", bestd])
		idx += 1
	# ---- 解析光（_lights）：若 ①②③ 不是 billboard，则很可能是点光在墙面上的径向衰减亮斑 ----
	var lights: Array = _isle._lights
	var light_cands: Array = []
	for li in range(lights.size()):
		var L: Dictionary = lights[li]
		var wp2: Vector3 = L.get("pos", Vector3.ZERO)
		if cam.is_position_behind(wp2):
			continue
		var sp2 := cam.unproject_position(wp2)
		var px2 := Vector2(sp2.x / vp.x * img.x, sp2.y / vp.y * img.y)
		light_cands.append({"px": px2, "info": "L[%d]%s" % [li, String(L.get("kind", "?"))]})
		print("[P82NODES] light L[%d] kind=%s indoor=%s pos=%s range=%.2f energy=%.2f color=%s px=(%.0f,%.0f) dist=%.2f" % [
			li, String(L.get("kind", "?")), str(L.get("indoor", false)), str(wp2),
			float(L.get("range", 0.0)), float(L.get("energy", 0.0)), str(L.get("color", Color.WHITE)),
			px2.x, px2.y, cam.global_position.distance_to(wp2)])
	idx = 0
	for t in targets_img:
		var b2 := ""
		var bd2 := 1e9
		for cd2 in light_cands:
			var p3: Vector2 = (cd2 as Dictionary)["px"]
			var dd2: float = p3.distance_to(t)
			if dd2 < bd2:
				bd2 = dd2
				b2 = String((cd2 as Dictionary)["info"])
		print("[P82NODES] LIGHTMATCH target%d -> nearest %s dist=%.1fpx" % [idx, b2, bd2])
		idx += 1
	# ---- glow 后处理参数（若是 bloom 而非节点，quad 之外还有 glow 放大）----
	if _isle._env != null:
		print("[P82NODES] glow_enabled=%s glow_intensity=%s glow_bloom=%s glow_strength=%s" % [
			str(_isle._env.glow_enabled), str(_isle._env.glow_intensity), str(_isle._env.glow_bloom), str(_isle._env.glow_hdr_threshold)])

## P8.2-02(c) 定向隔离：夜间 room_wide 机位，分别在 ①base ②隐藏全部 halo ③隐藏萤火 ④全部解析光 energy=0
## 四种状态下采样 ①②③ 目标像素邻域亮度，判定悬空球是 billboard / 粒子 / 解析光哪一种。
func _sample3(img: Image, pxs: Array) -> String:
	var out := ""
	for q in pxs:
		var pt: Vector2 = q
		var acc := Vector3.ZERO
		var n := 0
		var x0 := int(pt.x) - 4
		var y0 := int(pt.y) - 4
		for dy in range(9):
			for dx in range(9):
				var xx := x0 + dx
				var yy := y0 + dy
				if xx < 0 or yy < 0 or xx >= img.get_width() or yy >= img.get_height():
					continue
				var c := img.get_pixel(xx, yy)
				acc += Vector3(c.r, c.g, c.b) * 255.0
				n += 1
		if n > 0:
			acc /= float(n)
		out += " (%d,%d)=(%.0f,%.0f,%.0f)" % [int(pt.x), int(pt.y), acc.x, acc.y, acc.z]
	return out

func _isolate2() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	await _prepare()
	_isle._apply_quality(2)
	await _scene(2027, 1, 15, 21, 30, "clear", 0.0)
	_cam_room_wide()
	await _wait(0.8)
	var img_size: Vector2i = get_root().get_texture().get_image().get_size()
	var sc: float = float(img_size.x) / 2560.0
	var pxs := [Vector2(412, 424) * sc, Vector2(1289, 472) * sc, Vector2(1259, 562) * sc]
	var img0: Image = await _snap_img()
	print("[P82BALL] variant=base" + _sample3(img0, pxs))
	# ---- 1) 隐藏全部 halo（含 cottage/world/胶合板上的加色广告牌）----
	var halos := _all_halo_nodes()
	for h in halos:
		(h as Node3D).visible = false
	await _wait(0.5)
	print("[P82BALL] halos_hidden=%d variant=nohalo" % halos.size() + _sample3(await _snap_img(), pxs))
	for h in halos:
		(h as Node3D).visible = true
	await _wait(0.4)
	# ---- 2) 隐藏萤火粒子 ----
	var fn: GPUParticles3D = null
	var ff: Dictionary = _isle._fx.get("fireflies", {})
	if ff.has("node"):
		fn = ff["node"] as GPUParticles3D
		if fn != null:
			fn.visible = false
	await _wait(0.5)
	print("[P82BALL] fireflies_hidden=%s variant=nofireflies" % str(fn != null) + _sample3(await _snap_img(), pxs))
	if fn != null:
		fn.visible = true
	await _wait(0.4)
	# ---- 3) 全部解析光 energy=0（保留室内/室外池结构，只关灯）----
	var saved: Array = []
	for L in _isle._lights:
		var D: Dictionary = L
		saved.append([float(D.get("energy", 0.0)), float(D.get("intensity", 0.0))])
		D["energy"] = 0.0
		D["intensity"] = 0.0
	await _wait(0.6)
	print("[P82BALL] lights_off=%d variant=nolights" % saved.size() + _sample3(await _snap_img(), pxs))
	for i in range(_isle._lights.size()):
		var D2: Dictionary = _isle._lights[i]
		D2["energy"] = saved[i][0]
		D2["intensity"] = saved[i][1]
	await _wait(0.6)
	print("[P82BALL] variant=restored" + _sample3(await _snap_img(), pxs))

## P8.2-02(c) 逐灯归因：夜间 room_wide 机位，对 _lights 里每一盏灯单独 energy=0，采样 ①②③ 邻域，
## 谁关掉后目标像素显著变暗，就是那盏灯在墙面上的解析热点（无阴影导致的光斑）。
func _isolate3() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	await _prepare()
	_isle._apply_quality(2)
	await _scene(2027, 1, 15, 21, 30, "clear", 0.0)
	_cam_room_wide()
	await _wait(0.8)
	var img_size: Vector2i = get_root().get_texture().get_image().get_size()
	var sc: float = float(img_size.x) / 2560.0
	var pxs := [Vector2(412, 424) * sc, Vector2(1289, 472) * sc, Vector2(1259, 562) * sc]
	var base_s: String = _sample3(await _snap_img(), pxs)
	print("[P82PERLIGHT] base" + base_s)
	var n: int = _isle._lights.size()
	var saved: Array = []
	for L in _isle._lights:
		var D: Dictionary = L
		saved.append([float(D.get("energy", 0.0)), float(D.get("intensity", 0.0))])
	for li in range(n):
		var D2: Dictionary = _isle._lights[li]
		var e0: float = saved[li][0]
		var i0: float = saved[li][1]
		if e0 <= 0.0001:
			continue
		D2["energy"] = 0.0
		D2["intensity"] = 0.0
		await _wait(0.45)
		print("[P82PERLIGHT] off L[%d] kind=%s pos=%s" % [li, String(D2.get("kind", "?")), str(D2.get("pos", Vector3.ZERO))] + _sample3(await _snap_img(), pxs))
		D2["energy"] = e0
		D2["intensity"] = i0
		await _wait(0.30)
	print("[P82PERLIGHT] restored" + _sample3(await _snap_img(), pxs))

## 抓一帧图像（等到帧后读回）
func _snap_img() -> Image:
	await RenderingServer.frame_post_draw
	return get_root().get_texture().get_image()

## P8.2-02(a/b) 生效证明：q0/q2/q4 三档下，白天一层面北广角 + 夜间壁炉近景各一张。
## 用途：证明 (a) 吊灯光晕调光 与 (b) 壁炉槽参数在低画质也被正确应用（不是只在 q2 生效）。
func _quality_affirm() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	await _prepare()
	for q in [0, 2, 4]:
		_isle._apply_quality(q)
		await _wait(0.6)
		await _scene(2027, 1, 15, 14, 0, "clear", 0.0)
		await _wait(0.4)
		_cam_room_wide()
		await _shot("day_room_wide_q%d" % q)
		_emit_px("day_room_wide_q%d" % q)
		await _scene(2027, 1, 15, 20, 30, "clear", 0.0)
		await _wait(0.3)
		_cam_fire_low()
		await _shot("night_fire_low_q%d" % q)
		_emit_px("night_fire_low_q%d" % q)
	_isle._apply_quality(2)

## 把壁炉光槽还原为 P8.1/01 参数（range 5.0, energy 1.50），用于 before/after 定点对照。
func _restore_old_fire_light() -> void:
	var n := 0
	for L in (_isle._lights as Array):
		if typeof(L) == TYPE_DICTIONARY and String((L as Dictionary).get("kind", "")) == "fireplace":
			(L as Dictionary)["range"] = 5.0
			(L as Dictionary)["energy"] = 1.5
			n += 1
	print("[P82LV] restore_old_fire_light entries=%d" % n)

# ---------------------------------------------------------------- isolate（定位悬空发光球：逐个关闭候选光源再截图）
func _all_halo_nodes() -> Array:
	var out: Array = []
	for c in _cands:
		if String(c["kind"]) == "halo":
			out.append(c["node"])
	return out

func _isolate() -> void:
	await _prepare()
	_isle._apply_quality(2)
	await _scene(2027, 1, 15, 14, 0, "clear", 0.0)
	_cam_room_wide()
	_cands.clear()
	_walk(_root)
	await _shot("iso_base")
	_emit_px("iso_base")
	var halos := _all_halo_nodes()
	print("[P82LV] isolate halo_nodes=%d" % halos.size())
	for h in halos:
		print("[P82LV]   halo " + str((h as Node3D).get_path()) + " world=" + str((h as Node3D).global_position))
	# 1) 关闭全部 halo
	for h in halos:
		(h as Node3D).visible = false
	await _wait(0.4)
	await _shot("iso_nohalo")
	_emit_px("iso_nohalo")
	for h in halos:
		(h as Node3D).visible = true
	# 2) 关闭萤火粒子
	var ff: Dictionary = _isle._fx.get("fireflies", {})
	var fn: GPUParticles3D = null
	if ff.has("node"):
		fn = ff["node"] as GPUParticles3D
		fn.visible = false
	await _wait(0.4)
	await _shot("iso_nofireflies")
	_emit_px("iso_nofireflies")
	if fn != null:
		fn.visible = true
	# 3) 关闭全部 self_lit 网格（灯泡/火焰/灯罩）
	var lits: Array = []
	for c in _cands:
		if String(c["kind"]) == "self_lit":
			lits.append(c["node"])
	print("[P82LV] isolate self_lit_nodes=%d" % lits.size())
	for m in lits:
		(m as Node3D).visible = false
	await _wait(0.4)
	await _shot("iso_noselflit")
	_emit_px("iso_noselflit")
	for m in lits:
		(m as Node3D).visible = true
	await _wait(0.3)

# ---------------------------------------------------------------- batch 模式：定位"只存在于合批后"的异常发光球
# 前置事实：day_room_wide 的 (984,820) 黄球只在 IsleBatch 合批后的场景出现，isolate（不合批）没有。
# 做法：正常合批 → 逐类隐藏（glow / halo / self_lit / 单个 Batch_ 节点）后同机位截图 + 打印每个 Batch_ 的 surface/AABB 屏幕投影。
func _collect_batches(n: Node, out: Array) -> void:
	for ch in n.get_children():
		if ch is MeshInstance3D and String(ch.name).begins_with("Batch_"):
			out.append(ch)
		_collect_batches(ch, out)

func _quads_kind(mi: MeshInstance3D) -> String:
	var m: Material = null
	if mi.mesh != null:
		for i in range(mi.mesh.get_surface_count()):
			var mm: Material = mi.mesh.surface_get_material(i)
			if mm is StandardMaterial3D and (mm as StandardMaterial3D).blend_mode == BaseMaterial3D.BLEND_MODE_ADD:
				return "halo"
			if m == null:
				m = mm
	if m is ShaderMaterial:
		var sh := m as ShaderMaterial
		var sl: Variant = sh.get_shader_parameter("self_lit")
		if sl != null and float(sl) >= 0.5:
			return "self_lit"
	return "toon"

func _batch_bisect() -> void:
	await _prepare()
	_isle._apply_quality(2)
	_isle._p8_wfx_apply(2027, 1, 15, 14, 0, "clear", 0.0)
	await _wait(0.8)
	_cam_room_wide()
	await _wait(0.5)
	var all: Array = []
	_collect_batches(_root, all)
	print("[P82LV] batch_nodes=%d" % all.size())
	var cam: Camera3D = _isle._cam
	for bi in all:
		var mi := bi as MeshInstance3D
		var wp := mi.global_position
		var sp := cam.unproject_position(wp)
		print("[P82LV] BATCH %d %s surfaces=%d world=%s px=(%.0f,%.0f)" % [
			all.find(bi), str(mi.get_path()), mi.mesh.get_surface_count() if mi.mesh != null else -1,
			str(wp), sp.x / 1600.0 * 2560.0, sp.y / 900.0 * 1440.0])
	await _shot("b_base")
	# glow off
	_isle._env.glow_enabled = false
	await _wait(0.3)
	await _shot("b_noglow")
	_isle._env.glow_enabled = true
	# halo off
	var halos: Array = []
	var selflits: Array = []
	_walk(_root)
	for e in _cands:
		if String(e["kind"]) == "halo":
			halos.append(e["node"])
		elif String(e["kind"]) == "self_lit":
			selflits.append(e["node"])
	_cands.clear()
	for h in halos:
		(h as Node3D).visible = false
	await _wait(0.3)
	await _shot("b_nohalo")
	for h in halos:
		(h as Node3D).visible = true
	# self_lit off
	for h in selflits:
		(h as Node3D).visible = false
	await _wait(0.3)
	await _shot("b_noselflit")
	for h in selflits:
		(h as Node3D).visible = true
	# 只对"像素射线可能穿过"的 Batch_ 逐个隐藏（AABB 求交筛选，避免 20+ 张无意义截图）
	var ray_from: Vector3 = cam.global_position
	var ray_dir: Vector3 = _pixel_dir(cam, 984.0, 820.0)
	var ray := Vector3(ray_dir.x, ray_dir.y, ray_dir.z)
	var hit_idx: Array = []
	for i in range(all.size()):
		var mi := all[i] as MeshInstance3D
		var ab: AABB = mi.global_transform * mi.get_aabb()
		var p0 := ab.position
		var p1 := ab.end
		# slab test
		var tmin := 0.0
		var tmax := 1.0e9
		var ok := true
		for axis in range(3):
			var o: float = ray_from[axis]
			var d: float = ray[axis]
			var lo: float = min(p0[axis], p1[axis])
			var hi: float = max(p0[axis], p1[axis])
			if absf(d) < 1e-6:
				if o < lo or o > hi:
					ok = false
					break
			else:
				var t1: float = (lo - o) / d
				var t2: float = (hi - o) / d
				if t1 > t2:
					var tmp := t1
					t1 = t2
					t2 = tmp
				tmin = maxf(tmin, t1)
				tmax = minf(tmax, t2)
				if tmin > tmax:
					ok = false
					break
		if ok:
			hit_idx.append(i)
			print("[P82LV] RAYHIT batch=%d %s t=[%.2f,%.2f] aabb=%s" % [i, str(mi.get_path()), tmin, tmax, str(ab)])
	print("[P82LV] ray_candidates=%d" % hit_idx.size())
	# 先整组隐藏确认球来自合批
	for mi in all:
		(mi as MeshInstance3D).visible = false
	await _wait(0.35)
	await _shot("b_nobatch")
	for mi in all:
		(mi as MeshInstance3D).visible = true
	for i in hit_idx:
		var mi := all[i] as MeshInstance3D
		mi.visible = false
		await _wait(0.3)
		await _shot("b_bat%02d" % i)
		mi.visible = true
	await _wait(0.2)

# ---------------------------------------------------------------- band 模式（P8.2-02(d) 双池过渡带证据）
# 用全局 uniform g_indoor_band 切换：0=关闭（P8.1 硬切），0.2=壳体 ±0.2m 过渡带。
# 同一机位各拍一张，供 python 逐像素差分：证明差异只出现在房屋壳体薄壳内（带外等价）。
func _set_band(v: float) -> void:
	RenderingServer.global_shader_parameter_set("g_indoor_band", v)
	await process_frame

func _shot_pair(tag: String) -> void:
	await _set_band(0.0)
	await _wait(0.25)
	await _shot(tag + "_band0")
	_emit_px(tag + "_band0")
	await _set_band(0.2)
	await _wait(0.25)
	await _shot(tag + "_band020")
	_emit_px(tag + "_band020")

func _cam_ext_door() -> void:
	_cam(Vector3(0.0, _fy + 1.55, 6.20), Vector3(0.0, _fy + 1.15, 3.00), 55.0)

func _band() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	await _prepare()
	_isle._apply_quality(2)
	await _set_band(0.0)
	await _scene(2027, 1, 15, 14, 0, "clear", 0.0)
	_cam_room_wide()
	await _shot_pair("day_room_wide")
	_cam_door_inside()
	await _shot_pair("day_door_inside")
	_cam_window_inside()
	await _shot_pair("day_window_inside")
	_cam_ext_door()
	await _shot_pair("day_ext_door")
	await _scene(2027, 1, 15, 20, 30, "clear", 0.0)
	_cam_room_wide()
	await _shot_pair("night_room_wide")
	_cam_door_inside()
	await _shot_pair("night_door_inside")
	_cam_window_inside()
	await _shot_pair("night_window_inside")
	_cam_ext_door()
	await _shot_pair("night_ext_door")
	_isle._apply_quality(0)
	await _wait(0.5)
	_cam_room_wide()
	await _shot_pair("q0_night_room_wide")
	_isle._apply_quality(2)
	await _set_band(0.0)

# ---------------------------------------------------------------- bandperf 模式：过渡带成本 A/B（q0）
func _sample_stats(n: int) -> Dictionary:
	var arr: Array = []
	await process_frame
	for i in range(n):
		var t0 := Time.get_ticks_usec()
		await process_frame
		arr.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	arr.sort()
	var med: float = arr[arr.size() / 2]
	var p95: float = arr[int(float(arr.size() - 1) * 0.95)]
	var sum := 0.0
	for v in arr:
		sum += v
	return {"med": med, "p95": p95, "mean": sum / float(arr.size()), "fps": 1000.0 / maxf(med, 0.001),
		"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"vram": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0}

func _band_perf() -> void:
	await _prepare()
	_isle._apply_quality(0)
	Engine.max_fps = 0
	await _scene(2027, 1, 15, 20, 30, "clear", 0.0)
	var cams := {"room_wide": _cam_room_wide, "door_inside": _cam_door_inside, "ext_door": _cam_ext_door}
	for cname in cams:
		(cams[cname] as Callable).call()
		await _wait(2.2)
		var a: Array = []
		var b: Array = []
		for r in range(5):
			await _set_band(0.0)
			await _wait(0.35)
			a.append(await _sample_stats(180))
			await _set_band(0.2)
			await _wait(0.35)
			b.append(await _sample_stats(180))
		await _set_band(0.0)
		var sum_a := 0.0
		var sum_b := 0.0
		for i in range(5):
			sum_a += float(a[i]["med"])
			sum_b += float(b[i]["med"])
			print("[P82LV] BANDPERF cam=%s rep=%d band0_med=%.3f band020_med=%.3f delta=%.3f p95_0=%.3f p95_20=%.3f" % [
				cname, i, float(a[i]["med"]), float(b[i]["med"]), float(b[i]["med"]) - float(a[i]["med"]),
				float(a[i]["p95"]), float(b[i]["p95"])])
		print("[P82LV] BANDPERF_AVG cam=%s band0_med=%.3f band020_med=%.3f delta_ms=%.3f objects=%d calls=%d vram=%.1f" % [
			cname, sum_a / 5.0, sum_b / 5.0, (sum_b - sum_a) / 5.0, int(a[0]["objects"]), int(a[0]["calls"]), float(a[0]["vram"])])
	Engine.max_fps = 0
	_isle._apply_quality(2)

