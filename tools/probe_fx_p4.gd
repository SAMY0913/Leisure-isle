extends SceneTree
## P4 FX 验收探针（不加载 isle.tscn、不渲染、不截图）：
##   <godot_console.exe> --headless --path D:/休闲小岛幻境/游戏工程 --script res://tools/probe_fx_p4.gd
## 手动以 dt=1/60 步进 Splash / Ripples / BirdFlock，打印：
##   [SPLASH] 环面 AABB x/z 比、水滴粒子数
##   [RIPPLES] 涟漪圆度、五次点击鱼跃
##   [BIRDS] 白天 30s flying/perched 比例、空中最小间距、perch 占用冲突、夜间 20s 全栖息
## 退出码：0 = 全部断言通过。

const Fx := preload("res://scripts/fx.gd")
const DT := 1.0 / 60.0
const DAY_SECS := 30.0
const NIGHT_SECS := 20.0

var _pass := 0
var _fail := 0

func _initialize() -> void:
	print("=== P4 FX PROBE START ===")
	# 等待 root 真正进入 SceneTree，否则 CPUParticles3D 会刷 !is_inside_tree 警告
	await process_frame
	probe_splash()
	probe_ripples()
	probe_birds()
	probe_wake()
	probe_waiting()
	print("=== P4 FX PROBE RESULT: ", "PASS" if _fail == 0 else "FAIL", " pass=", _pass, " fail=", _fail, " ===")
	quit(0 if _fail == 0 else 1)

func _check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("  [OK] ", msg)
	else:
		_fail += 1
		print("  [FAIL] ", msg)

func _fmt_counts(st: Dictionary) -> String:
	return "birds=%d fly=%d takeoff=%d landing=%d perch=%d airborne=%d waiting=%d night=%s slots=%d used=%d conflicts=%d min_gap=%.2f takeoffs=%d landings=%d night_takeoffs=%d" % [
		int(st["birds"]), int(st["flying"]), int(st["takeoff"]), int(st["landing"]),
		int(st["perched"]), int(st["airborne"]), int(st["waiting"]), str(st["night"]),
		int(st["perch_slots"]), int(st["perch_used"]), int(st["perch_conflicts"]),
		float(st["air_min_dist"]), int(st["takeoffs"]), int(st["landings"]), int(st["takeoffs_night"]),
	]

func _free_splash(splash) -> void:
	for u_v in splash.get("_units"):
		var u: Dictionary = u_v
		var root: Node3D = u["root"]
		root.free()
	for u_v2 in splash.get("_free"):
		var u2: Dictionary = u_v2
		var root2: Node3D = u2["root"]
		root2.free()
	splash.free()

func _free_ripples(ripples) -> void:
	for it_v in ripples.get("_free"):
		var it: Dictionary = it_v
		(it["node"] as MeshInstance3D).free()
	ripples.free()

# ============================================================
# 1) 水花：XZ 真圆环 + 球体水滴 + 池化上限
# ============================================================
func probe_splash() -> void:
	print("--- SPLASH ---")
	var ring_mesh: ArrayMesh = Fx._torus_ring_mesh()
	var ring_aabb: AABB = ring_mesh.get_aabb()
	var ring_ratio: float = ring_aabb.size.x / maxf(ring_aabb.size.z, 0.0001)
	var ring_flat: float = ring_aabb.size.y / maxf(ring_aabb.size.x, 0.0001)
	print("[SPLASH] torus ring mesh AABB size=", ring_aabb.size, " x/z=", "%.4f" % ring_ratio, " y/x=", "%.4f" % ring_flat)
	_check(absf(ring_ratio - 1.0) < 0.01, "环面网格 AABB x/z ≈ 1（XZ 平面真圆环）")
	_check(ring_flat < 0.25, "环面网格扁平贴水（y/x < 0.25）")

	var splash = Fx.Splash.new()
	root.add_child(splash)
	var before: int = splash.get_child_count()
	splash.splash_at(Vector3(30.0, 0.0, -18.0), 1.0)
	var after: int = splash.get_child_count()
	var st0: Dictionary = splash.get_state_counts()
	print("[SPLASH] splash_at(power=1.0): children ", before, "→", after, " active=", st0["active"], " created=", st0["created"], " free=", st0["free"])
	_check(after > before, "splash_at 后活跃水花子节点增加")

	var units: Array = splash.get("_units")
	_check(units.size() == 1, "活跃水花 unit = 1")
	var unit: Dictionary = units[0]
	var rings: Array = unit["rings"]
	var ring_xz_ok := true
	var ring_scale_ok := true
	var ring_tiers: Array = []
	for r_v in rings:
		var info: Dictionary = r_v
		var mi: MeshInstance3D = info["node"]
		ring_tiers.append("%.2f@y%.2f/life%.2f" % [float(info["r1"]), float(info["y"]), float(info["life"])])
		if absf(mi.scale.x - mi.scale.z) > 0.0001:
			ring_xz_ok = false
		if absf(mi.scale.y - mi.scale.x * 0.42) > 0.0001:
			ring_scale_ok = false
	print("[SPLASH] rings=", rings.size(), " tiers(r1/y/life)=", ", ".join(PackedStringArray(ring_tiers)))
	_check(rings.size() == 3, "3 圈不同半径/高度/寿命的泡沫环")
	_check(ring_xz_ok, "ring 节点 scale.x == scale.z（XZ 等比 → 世界 AABB x/z = 1）")
	_check(ring_scale_ok, "ring 节点 y = 0.42x（压扁但保持圆形）")
	var r0: MeshInstance3D = rings[0]["node"]
	var ring_world_ratio: float = (ring_aabb.size.x * r0.scale.x) / maxf(ring_aabb.size.z * r0.scale.z, 0.0001)
	print("[SPLASH] ring world AABB x/z=", "%.4f" % ring_world_ratio)
	_check(absf(ring_world_ratio - 1.0) < 0.01, "ring 世界 AABB x/z ≈ 1（不再椭圆）")

	var cols: Array = unit["cols"]
	var cols_ok := true
	for c_v in cols:
		var ci: Dictionary = c_v
		var cmi: MeshInstance3D = ci["node"]
		if absf(cmi.scale.x - cmi.scale.z) > 0.0001:
			cols_ok = false
	print("[SPLASH] columns=", cols.size())
	_check(cols.size() == 3, "3 根交叉水柱")
	_check(cols_ok, "水柱 XZ 等比（有厚度/体积）")

	var particles: Array = unit["particles"]
	var drop_total := 0
	var emitting := 0
	var one_shot_ok := true
	for p_v in particles:
		var ps: CPUParticles3D = p_v
		drop_total += ps.amount
		if ps.emitting:
			emitting += 1
		if not ps.one_shot:
			one_shot_ok = false
	var first_ps: CPUParticles3D = particles[0]
	print("[SPLASH] droplets: emitters=", particles.size(), " particles=", drop_total, " emitting=", emitting, " one_shot=", one_shot_ok, " mesh=", first_ps.mesh.get_class())
	_check(particles.size() == 3, "3 组球体水滴粒子")
	_check(drop_total >= 40, "水滴粒子数 >= 40（power=1.0）")
	_check(emitting == 3, "水滴粒子已发射（emitting=true）")
	_check(one_shot_ok, "水滴为 one_shot 生命周期粒子")
	_check(first_ps.mesh is SphereMesh, "水滴使用 3D 球体网格")

	for i in range(15):
		splash.splash_at(Vector3(20.0 + float(i) * 2.5, 0.0, -10.0), 0.8 + 0.1 * float(i))
	var st1: Dictionary = splash.get_state_counts()
	print("[SPLASH] after 16 requests: ", st1, " children=", splash.get_child_count())
	_check(int(st1["active"]) <= Fx.SPLASH_MAX_ACTIVE, "活跃水花有上限")
	_check(splash.get_child_count() == int(st1["active"]), "只有活跃 unit 是子节点")
	_check(int(st1["created"]) <= Fx.SPLASH_MAX_UNITS, "总 unit 数有上限")

	for i in range(int(2.6 / DT)):
		splash.update(DT)
	var st2: Dictionary = splash.get_state_counts()
	print("[SPLASH] after 2.6s: ", st2, " children=", splash.get_child_count())
	_check(int(st2["active"]) == 0, "水花按寿命回收")
	_check(splash.get_child_count() == 0, "回收后无活跃子节点")
	_check(int(st2["free"]) == int(st2["created"]), "空闲 unit 全部回池")
	var created_before: int = int(st2["created"])
	splash.splash_at(Vector3(30.0, 0.0, -18.0), 1.0)
	var st3: Dictionary = splash.get_state_counts()
	print("[SPLASH] reuse: created=", st3["created"], " active=", st3["active"], " free=", st3["free"])
	_check(int(st3["created"]) == created_before, "复用池化 unit（不新建资源）")
	for i in range(400):
		splash.update(DT)
	_check(splash.get_child_count() == 0, "长时间推进后无子节点泄漏")
	print("[SPLASH] final: ", splash.get_state_counts())
	_free_splash(splash)

# ============================================================
# 2) 涟漪 + 鱼跃：真圆扩张 + 五次点击触发
# ============================================================
func probe_ripples() -> void:
	print("--- RIPPLES / FISH ---")
	var plane: PlaneMesh = Fx._plane_xz_mesh()
	var pa: AABB = plane.get_aabb()
	var pr: float = pa.size.x / maxf(pa.size.z, 0.0001)
	print("[RIPPLES] plane mesh AABB size=", pa.size, " x/z=", "%.4f" % pr, " orientation=FACE_Y")
	_check(absf(pr - 1.0) < 0.01, "涟漪网格 AABB x/z ≈ 1（网格本身在 XZ 平面）")

	var splash2 = Fx.Splash.new()
	root.add_child(splash2)
	var ripples = Fx.Ripples.new()
	root.add_child(ripples)
	ripples.splash_cb = splash2.splash_at
	var c0: int = ripples.get_child_count()
	for i in range(5):
		ripples.ripple_at(Vector3(10.0 + float(i) * 0.3, 0.0, -6.0), 0.9)
	var st: Dictionary = ripples.get_state_counts()
	print("[RIPPLES] 5 clicks: ripples=", st["ripples"], " fish=", st["fish"], " clicks=", st["clicks"], " children=", ripples.get_child_count())
	print("[RIPPLES] click-triggered splash: ", splash2.get_state_counts())
	_check(int(st["fish"]) >= 1, "2.5s 内五次点击触发小鱼鱼跃")
	_check(ripples.get_child_count() > c0, "涟漪/鱼节点已挂载")
	_check(int(splash2.get_state_counts()["active"]) >= 1, "鱼跃通过 splash_cb 触发水花")
	var items: Array = ripples.get("_items")
	var scale_ok := true
	var mat_unique := true
	for it_v in items:
		var it: Dictionary = it_v
		var mi: MeshInstance3D = it["node"]
		if absf(mi.scale.x - mi.scale.z) > 0.0001:
			scale_ok = false
		if absf(mi.rotation.x) > 0.0001 or absf(mi.rotation.z) > 0.0001:
			scale_ok = false
	if items.size() >= 2:
		var a0: StandardMaterial3D = items[0]["mat"]
		var a1: StandardMaterial3D = items[1]["mat"]
		mat_unique = a0 != a1
	print("[RIPPLES] active=", items.size(), " scale_xz_equal=", scale_ok, " per_item_material=", mat_unique)
	_check(scale_ok, "涟漪节点 scale.x == scale.z（无旋转真圆扩张）")
	_check(mat_unique, "每条涟漪独立淡出材质")
	for i in range(int(4.0 / DT)):
		ripples.update(DT, 22.0)
		splash2.update(DT)
	var st2: Dictionary = ripples.get_state_counts()
	print("[RIPPLES] after 4s: ", st2, " children=", ripples.get_child_count(), " splash=", splash2.get_state_counts())
	_check(int(st2["ripples"]) == 0, "涟漪按寿命回收")
	_check(ripples.get_child_count() == 0, "涟漪/鱼回收后无子节点")
	_free_splash(splash2)
	_free_ripples(ripples)

	# 周期鱼：白天会自发生成，夜间不生成
	var r_day = Fx.Ripples.new()
	root.add_child(r_day)
	var day_max_fish := 0
	for i in range(int(20.0 / DT)):
		r_day.update(DT, 22.0)
		day_max_fish = maxi(day_max_fish, int(r_day.get_state_counts()["fish"]))
	print("[RIPPLES] periodic fish day 20s: max_fish=", day_max_fish)
	_check(day_max_fish >= 1, "白天周期鱼跃保留")
	_free_ripples(r_day)
	var r_night = Fx.Ripples.new()
	root.add_child(r_night)
	var night_max_fish := 0
	for i in range(int(25.0 / DT)):
		r_night.update(DT, -3.0)
		night_max_fish = maxi(night_max_fish, int(r_night.get_state_counts()["fish"]))
	print("[RIPPLES] periodic fish night 25s: max_fish=", night_max_fish)
	_check(night_max_fish == 0, "夜间不生成周期鱼")
	_free_ripples(r_night)

# ============================================================
# 3) 鸟群：白天 60% 飞行 / 夜间全栖息
# ============================================================
func _make_perches() -> Array:
	return [
		Vector3(-16.3, 11.7, 8.9), Vector3(-16.9, 11.9, 7.4), Vector3(-15.2, 12.4, 9.4),
		Vector3(6.5, 2.05, 8.6), Vector3(-9.0, 1.42, 2.0), Vector3(2.0, 1.42, -9.0),
		{"id": "ridge_a", "pos": Vector3(0.0, 9.2, -2.85), "facing": Vector3(0.0, 0.0, 1.0), "radius": 1.4, "kind": "ridge"},
		{"id": "ridge_b", "pos": Vector3(0.0, 9.2, 2.55), "facing": 0.0, "radius": 1.4, "kind": "ridge"},
		{"id": "porch", "pos": Vector3(0.55, 4.92, 5.90), "facing": Vector3(0.3, 0.0, 1.0), "radius": 1.25, "kind": "porch"},
	]

func probe_birds() -> void:
	print("--- BIRDS ---")
	var flock = Fx.BirdFlock.new()
	root.add_child(flock)
	flock.setup(_make_perches())
	var perches: Array = flock.get_perches()
	var slots := 0
	var dict_count := 0
	var vec_count := 0
	for p_v in perches:
		var p: Dictionary = p_v
		slots += int(p["slots"])
		if String(p["kind"]) == "generic":
			vec_count += 1
		else:
			dict_count += 1
	print("[BIRDS] perches=", perches.size(), " (Vector3=", vec_count, ", Dictionary=", dict_count, ") slots=", slots, " bird_count=", Fx.BIRD_COUNT)
	_check(perches.size() == 9, "9 个栖枝（world+cottage 合并）全部归一化")
	_check(dict_count == 3 and vec_count == 6, "Dictionary 与 Vector3 两种栖枝格式都兼容")
	_check(slots >= Fx.BIRD_COUNT, "总槽位 >= 鸟数（夜间可全部栖息）")
	var st_setup: Dictionary = flock.get_state_counts()
	print("[BIRDS] initial: ", _fmt_counts(st_setup))

	# ---- 白天 30s ----
	var frames := int(DAY_SECS / DT)
	var sum_fly := 0.0
	var sum_air := 0.0
	var sum_perch := 0.0
	var min_gap := 1.0e9
	var gap_frames := 0
	var max_conf := 0
	var max_waiting := 0
	var airborne_lo := 99
	var airborne_hi := -1
	var in_band := 0
	var takeoff_events := 0
	var landing_events := 0
	var seen_states: Dictionary = {}
	var last_takeoffs := int(st_setup["takeoffs"])
	var last_landings := int(st_setup["landings"])
	for i in range(frames):
		flock.update_birds(DT, 22.0)
		var st: Dictionary = flock.get_state_counts()
		sum_fly += float(st["flying"])
		sum_air += float(st["airborne"])
		sum_perch += float(st["perched"])
		max_conf = maxi(max_conf, int(st["perch_conflicts"]))
		max_waiting = maxi(max_waiting, int(st["waiting"]))
		var ab: int = int(st["airborne"])
		airborne_lo = mini(airborne_lo, ab)
		airborne_hi = maxi(airborne_hi, ab)
		if ab >= Fx.BIRD_FLY_LOW and ab <= Fx.BIRD_FLY_HIGH:
			in_band += 1
		var g: float = float(st["air_min_dist"])
		if g >= 0.0:
			min_gap = minf(min_gap, g)
			gap_frames += 1
		if int(st["takeoffs"]) > last_takeoffs:
			takeoff_events += 1
			last_takeoffs = int(st["takeoffs"])
		if int(st["landings"]) > last_landings:
			landing_events += 1
			last_landings = int(st["landings"])
		if int(st["flying"]) > 0:
			seen_states["FLY"] = true
		if int(st["takeoff"]) > 0:
			seen_states["TAKEOFF"] = true
		if int(st["landing"]) > 0:
			seen_states["LANDING"] = true
		if int(st["perched"]) > 0:
			seen_states["PERCH"] = true
	var n := float(frames)
	var fly_avg: float = sum_fly / n
	var air_avg: float = sum_air / n
	var perch_avg: float = sum_perch / n
	print("[BIRDS] DAY ", int(DAY_SECS), "s: flying avg=", "%.2f" % fly_avg, " (", "%.1f%%" % (100.0 * fly_avg / float(Fx.BIRD_COUNT)), ")", " airborne avg=", "%.2f" % air_avg, " (", "%.1f%%" % (100.0 * air_avg / float(Fx.BIRD_COUNT)), ")", " perched avg=", "%.2f" % perch_avg)
	print("[BIRDS] DAY airborne range=[", airborne_lo, ",", airborne_hi, "] in_band(", Fx.BIRD_FLY_LOW, "..", Fx.BIRD_FLY_HIGH, ")=", "%.1f%%" % (100.0 * float(in_band) / n), " takeoff_events=", takeoff_events, " landing_events=", landing_events, " states=", seen_states.keys())
	print("[BIRDS] DAY min_air_gap=", "%.3f" % min_gap, "m over ", gap_frames, "/", frames, " frames; max perch conflicts=", max_conf, " max waiting=", max_waiting)
	print("[BIRDS] DAY final: ", _fmt_counts(flock.get_state_counts()))
	_check(absf(air_avg / float(Fx.BIRD_COUNT) - 0.6) < 0.18, "白天空中比例 ≈60%")
	_check(fly_avg >= 4.0 and fly_avg <= 8.0, "白天飞行个体数在 4~8（目标 6）")
	_check(min_gap >= Fx.BIRD_MIN_AIR_GAP - 0.02, "空中最小间距 >= 1.6m")
	_check(gap_frames == frames, "每帧都能测到空中间距")
	_check(max_conf == 0, "全程 perch 预订/占用无冲突")
	_check(max_waiting <= 2, "无落点时盘旋等待受控")
	_check(takeoff_events >= 4 and landing_events >= 4, "个体 8-20s 计时器错峰切换（多次起飞/降落）")
	_check(seen_states.has("FLY") and seen_states.has("TAKEOFF") and seen_states.has("LANDING") and seen_states.has("PERCH"), "白天四种状态都出现")

	# ---- 夜间 20s ----
	var night_frames := int(NIGHT_SECS / DT)
	var first_all_perched := -1
	var max_night_air := 0
	var night_takeoffs0: int = int(flock.get_state_counts()["takeoffs_night"])
	for i in range(night_frames):
		flock.update_birds(DT, -18.0)
		var st2: Dictionary = flock.get_state_counts()
		var ab2: int = int(st2["flying"]) + int(st2["takeoff"]) + int(st2["landing"])
		max_night_air = maxi(max_night_air, ab2)
		if first_all_perched < 0 and int(st2["perched"]) == Fx.BIRD_COUNT:
			first_all_perched = i
	var st_night: Dictionary = flock.get_state_counts()
	var night_takeoffs: int = int(st_night["takeoffs_night"]) - night_takeoffs0
	var all_perch_time := "never"
	if first_all_perched >= 0:
		all_perch_time = "%.2fs" % (float(first_all_perched) * DT)
	print("[BIRDS] NIGHT ", int(NIGHT_SECS), "s: first_all_perched=", all_perch_time, " max_airborne=", max_night_air, " night_self_takeoff=", night_takeoffs)
	print("[BIRDS] NIGHT final: ", _fmt_counts(st_night))
	_check(first_all_perched >= 0, "夜间 20s 内全部栖息")
	_check(int(st_night["perched"]) == Fx.BIRD_COUNT, "夜间 perched=10")
	_check(int(st_night["perch_used"]) == Fx.BIRD_COUNT, "夜间栖枝占用=10")
	_check(night_takeoffs == 0, "夜间不自发起飞")
	_check(int(st_night["perch_conflicts"]) == 0, "夜间无栖枝占用冲突")

	# ---- 栖枝替换 / 失效重选 ----
	flock.set_perches(_make_perches())
	for i in range(int(8.0 / DT)):
		flock.update_birds(DT, -18.0)
	var st_re: Dictionary = flock.get_state_counts()
	print("[BIRDS] after set_perches(): ", _fmt_counts(st_re))
	_check(int(st_re["perch_conflicts"]) == 0, "set_perches 后无占用冲突")
	_check(int(st_re["perched"]) == Fx.BIRD_COUNT, "set_perches 后夜间仍全部栖息")
	flock.set_perches([Vector3(-16.3, 11.7, 8.9), Vector3(6.5, 2.05, 8.6)])
	for i in range(int(10.0 / DT)):
		flock.update_birds(DT, -18.0)
	var st_re2: Dictionary = flock.get_state_counts()
	print("[BIRDS] reduced-perch night final: ", _fmt_counts(st_re2))
	_check(int(st_re2["perch_conflicts"]) == 0, "栖枝减少后无占用冲突")
	_check(int(st_re2["perched"]) == Fx.BIRD_COUNT, "栖枝槽位自动扩容后仍可全部栖息")

	# ---- 不新增每帧资源：空闲稳定期对象数不增长 ----
	var oc0: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	for i in range(600):
		flock.update_birds(DT, 22.0)
	var oc1: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	print("[FX] object count delta over 600 day frames =", oc1 - oc0)
	_check(oc1 - oc0 <= 10, "每帧更新不新建节点/资源（对象数稳定）")
	flock.free()

# ============================================================
# 4) Wake：船尾小水花共用 Splash 池（按 speed 区分规模）
# ============================================================
func probe_wake() -> void:
	print('--- WAKE / STERN SPLASH ---')
	var wake = Fx.Wake.new()
	root.add_child(wake)
	var boat := Vector3(24.0, 0.05, 6.0)
	var heading := 0.9
	var fwd := Vector3(sin(heading), 0.0, cos(heading))
	var max_stern_active := 0
	var max_stern_units := 0
	var children_after_init := -1
	for i in range(int(6.0 / DT)):
		boat += fwd * (3.6 * DT)
		wake.update(DT, boat, heading, 3.6)
		if i == 60:
			children_after_init = wake.get_child_count()
		var stern = wake.get('_stern_fx')
		if stern != null:
			var sst: Dictionary = stern.get_state_counts()
			max_stern_active = maxi(max_stern_active, int(sst['active']))
			max_stern_units = int(sst['max_units'])
	var children_after_move := wake.get_child_count()
	for i in range(int(4.0 / DT)):
		wake.update(DT, boat, heading, 0.0)
	var stern2 = wake.get('_stern_fx')
	var stern_active_stop := -1
	if stern2 != null:
		stern_active_stop = int(stern2.get_state_counts()['active'])
	var children_after_stop := wake.get_child_count()
	print('[WAKE] children=', children_after_stop, ' (init=', children_after_init, ', move=', children_after_move, ') stern_splash max_active=', max_stern_active, '/', max_stern_units, ' stop_active=', stern_active_stop)
	_check(wake.get_child_count() >= 3, 'Wake 已建尾迹网格/船头泡沫/船尾 Splash')
	_check(max_stern_active >= 2, '航行时船尾按 speed 持续生成小水花')
	_check(max_stern_active <= 10, '船尾水花共用池上限（不无限增长）')
	_check(children_after_move == children_after_init, '航行期间 Wake 子节点数稳定')
	_check(children_after_stop == children_after_move, '停车后 Wake 子节点数稳定')
	_check(stern_active_stop == 0, '停车 4s 后船尾水花全部回收')
	if stern2 != null:
		_free_splash(stern2)
	wake.free()

# ============================================================
# 5) 栖枝不足：无可用落点时盘旋等待（不冲突/不消失）
# ============================================================
func probe_waiting() -> void:
	print('--- PERCH SHORTAGE / CIRCLING ---')
	var flock = Fx.BirdFlock.new()
	root.add_child(flock)
	flock.setup([Vector3(0.0, 12.0, 0.0)])
	var max_waiting := 0
	var max_conf := 0
	var slots := 0
	for i in range(int(12.0 / DT)):
		flock.update_birds(DT, -18.0)
		var st: Dictionary = flock.get_state_counts()
		max_waiting = maxi(max_waiting, int(st['waiting']))
		max_conf = maxi(max_conf, int(st['perch_conflicts']))
		slots = int(st['perch_slots'])
	var st_end: Dictionary = flock.get_state_counts()
	print('[BIRDS] perch-shortage night: slots=', slots, ' max_waiting=', max_waiting, ' max_conflicts=', max_conf, ' end=', _fmt_counts(st_end))
	_check(slots < Fx.BIRD_COUNT, '单栖枝扩容上限 < 鸟数（制造落点不足）')
	_check(max_waiting > 0, '无可用落点时进入盘旋等待')
	_check(max_conf == 0, '落点不足时仍无栖枝预订冲突')
	_check(int(st_end['airborne']) > 0, '落点不足时部分鸟持续在空中盘旋')
	_check(int(st_end['perched']) == slots, '可落鸟数等于可用槽位')
	flock.free()

