class_name IsleCottage
extends RefCounted
## 岛屿小屋 v4 —— P4 修缮版（真实洞口 / 无共面装饰 / 阁楼落地玻璃窗 + 室内 / 6 级台阶 / 字典鸟落点）。
##
## 1) 共面闪烁根治：墙体全部为不透明 toon 材质、深度正确；半木构件/窗套/门套均为“独立厚度”的
##    实体，向墙外凸出 0.05m、向墙内埋入 0.09-0.16m，任何外表面都不与墙皮/屋面端面/彼此共面。
##    门窗全部是真实墙体开口（分段墙围洞），不是贴片覆盖；玻璃用独立玻璃材质并凹入洞口。
## 2) 阁楼：前山墙重做为带真实矩形洞口的自定义网格，3.20m×2.60m 落地玻璃窗（双层玻璃 + 3x3 窗棂 +
##    内外窗套），阁楼内部有真实地板/斜顶/地毯/书桌+椅/床/衣柜/暖灯，全部经“屋面下皮”公式校核不穿模。
## 3) 门廊台阶由 3 级改为 6 级（rise=0.16m / run=0.30m），逐级接到地形，栏杆/扶手/望柱同步。
## 4) 山墙博风板外移 0.02m 与屋面板端面错开；檐口封檐板/雨棚封板/烟囱泛水全部沿法线错位。
## 5) perches 改为 Array[Dictionary]{id,pos,facing,radius,kind,normal,slope,slots?}：屋脊 3（脊瓦顶）+ 屋檐 4
##    （檐口筒瓦顶）+ 烟囱 1（顶石）+ 门廊梁 2（雨棚横梁顶）+ 门廊扶手 4（P7-V2：侧栏/前栏扶手顶面）
##    = 14 个真实瓦面/实体表面点，脚部间隙 0.03m；normal 为世界空间向上单位法线（eave normal.y≈0.827），
##    slope 为坡面倾角（ridge/chimney/porch=0，eave=pitch）。
##    P7-V2 门廊扶手点 kind="porch_rail"（porch_rail_L/R/FL/FR）：扶手实体宽 0.10m → slots=1（单鸟），
##    facing 沿扶手方向（侧栏局部 +Z、前栏局部 +X，与任务契约一致）；slots=1 时 fx 不产生槽位偏移。
## 6) Phase6/T4：导出灯塔光束遮挡盒 get_beam_occluders()（主体/屋面/烟囱 3 盒，世界 center/half/yaw），
##    阁楼改用独立低反射玻璃（opacity .020/.014、reflection_gain .34/.26）并可透视室内；删除窗外 2.10 光晕，
##    阁楼室内两盏暖灯走 light_sources；保留全部旧返回键，新增 beam_occluders / attic_glass_mats /
##    attic_lamp2_world / attic_window_world / attic_lamp_world。
##
## 局部坐标：root 位于 (M.HOUSE_X, M.house_ground_y(), M.HOUSE_Z)，rotation.y = M.HOUSE_YAW。
## 尺寸：w=10.6 d=8.4 wh=5.6 rh=3.6，floor_y=fy=0.55，屋脊沿局部 +Z，山墙在 ±Z，门在 +Z 立面。

const M := preload("res://scripts/isle_math.gd")
const P := preload("res://scripts/isle_house_props.gd")
const CAT := preload("res://scripts/isle_cat.gd")

## 世界坐标换算：运行时 root 已在场景树内时用 to_global；探针以游离节点构建时，Godot 4 的
## to_global 会退化为单位变换，此时用 root.transform * local 得到同样正确的世界坐标。
static func _world(root: Node3D, local: Vector3) -> Vector3:
	if root.is_inside_tree():
		return root.to_global(local)
	return root.transform * local

static func build(parent: Node3D) -> Dictionary:
	var root := Node3D.new()
	root.name = "Cottage"
	var gy: float = M.house_ground_y()
	root.position = Vector3(M.HOUSE_X, gy, M.HOUSE_Z)
	root.rotation.y = M.HOUSE_YAW
	parent.add_child(root)

	var C: Dictionary = _context(root)
	C["root"] = root
	# 供 get_beam_occluders(root) 反查尺寸（探针/其他系统可在 build 之后按 root 重建遮挡盒）
	root.set_meta("cottage_ctx", C)
	var fy: float = C["fy"]
	var hd: float = C["hd"]

	_plinth(root, C)
	_porch_steps(root, C)
	_walls(root, C)
	_windows(root, C)
	_door(root, C)
	_roof(root, C)
	_attic_window(root, C)
	_chimney(root, C)
	_porch(root, C)
	_stairs(root, C)          # P7-V3：L 形楼梯 + 楼梯井（先结构，后家具）
	_attic_interior(root, C)
	_interior(root, C)
	_cat(root, C, Vector3(2.30, C["deck_top"] + 0.05, 6.10))

	# ---- 交互命中体（main 用 collision_mask=2 的射线点击）----
	var door_hit := M.hitbox(parent, "DoorHit", _world(root, Vector3(0.0, fy + 1.70, hd + 0.55)), Vector3(3.0, 3.9, 2.0))
	var chimney_hit := M.hitbox(parent, "ChimneyHit", _world(root, Vector3(C["ch_x"], 8.55, C["ch_z"])), Vector3(1.95, 3.5, 1.95))
	var chimney_top := Node3D.new()
	chimney_top.name = "ChimneyTop"
	chimney_top.position = Vector3(C["ch_x"], C["ch_top"] + 0.05, C["ch_z"])
	root.add_child(chimney_top)

	# ---- 鸟落点：Array[Dictionary]（fx 需要 id/pos/facing/radius/kind）----
	var perches: Array[Dictionary] = _make_perches(root, C)

	# ---- 地面投影 ----
	M.shadow_blob(parent, _world(root, Vector3(0.0, 0.01, 0.55)), 7.8, 0.30)
	M.shadow_blob(parent, _world(root, Vector3(0.0, 0.01, 5.80)), 4.4, 0.20)

	# ---- 暖光光源位置（世界坐标；main 写进 shader 的解析点光）----
	var lantern_world: Vector3 = _world(root, C["lantern_pos"])
	var lantern_world_right: Vector3 = _world(root, C["lantern_pos_right"])
	var lamp_world: Vector3 = _world(root, Vector3(1.15, fy + 2.45, 1.95))
	var fire_world: Vector3 = _world(root, Vector3(C["ch_x"], fy + 0.55, -3.10))
	var attic_lamp_world: Vector3 = C["attic_lamp_world"]
	var attic_lamp2_world: Vector3 = _world(root, C["attic_lamp2_pos"])
	var attic_window_world: Vector3 = C["attic_window_world"]
	var light_sources: Array = []
	light_sources.append({"pos": lamp_world, "color": Color(1.0, 0.74, 0.44), "range": 7.5, "intensity": 1.60})
	light_sources.append({"pos": fire_world, "color": Color(1.0, 0.52, 0.22), "range": 5.4, "intensity": 1.30})
	# 门廊对称吊灯：左右各一盏，亮度收敛到与路灯同级（原左灯 1.35/6.5 + halo 2.10 过亮）
	light_sources.append({"pos": lantern_world, "color": Color(1.0, 0.78, 0.48), "range": 6.0, "intensity": 1.05})
	light_sources.append({"pos": lantern_world_right, "color": Color(1.0, 0.78, 0.48), "range": 6.0, "intensity": 1.05})
	# 阁楼：删除窗外 2.10m 的 ADD 光晕（夜间会糊成光球、挡住室内视线）后，用两盏室内暖灯经
	# main._collect_lights → toon 解析点光照亮书桌/床/地板/部分内墙，位置都在室内（离外墙 ≥1.9m）。
	light_sources.append({"pos": attic_lamp_world, "color": Color(1.0, 0.74, 0.44), "range": 6.4, "intensity": 1.50})
	light_sources.append({"pos": attic_lamp2_world, "color": Color(1.0, 0.70, 0.40), "range": 5.2, "intensity": 1.42})
	for wl in C["win_lights"]:
		light_sources.append({"pos": wl["pos"], "color": Color(1.0, 0.80, 0.52), "range": 3.8, "intensity": 0.70})
	# ---- 灯塔光束遮挡盒（世界空间 yaw 对齐 AABB；main._collect_beam_occluders 写 g_occ_*）----
	var beam_occluders: Array = _beam_occluders_world(root, C)

	# ---- P7-V3.1 静态合批（房屋外壳 / 一层室内 / 阁楼三层分区，家具与楼梯各自在自己的
	# 节点内已合批，不参与这里）----
	# 家具库 / 楼梯 / 墙体梁柱都是"建好就不再单独运动"的静态件，但每件是一个独立
	# MeshInstance3D（每个 = 1 surface × toon + outline 两个 pass），Forward+ 不做自动
	# 静态合批，因此 P7-V3 的 draw call 随部件数线性翻倍。这里在构建结束时按
	# （空间区域, 材质实例, 顶点属性签名）合并成少量多 surface ArrayMesh：
	#   * 材质对象原样复用 → next_pass 描边、self_lit、glow 参数全部不变；
	#   * 顶点/法线由 SurfaceTool.append_from 做局部→root 局部坐标变换，
	#     三角形与顶点总数与合并前严格相等（tools/probe_batch_merge_p7v31.gd 断言守恒）；
	#   * 门扇（no_batch）、猫（no_batch）、玻璃/光晕/影子斑（非 toon 材质）不参与；
	#   * 按区域分组，因此不会出现"整栋房屋只能整体显隐"。
	IsleBatch.merge_static(root, {
		"split": func(mi: Node3D) -> String: return _batch_region(root, mi),
	})

	return {
		"root": root,
		"door_pivot": C["door_pivot"],
		"door_hit": door_hit,
		"chimney_hit": chimney_hit,
		"chimney_top": chimney_top,
		"window_mats": C["window_mats"],
		"window_halos": C["window_halos"],
		"lantern_mat": C["lantern_mat"],
		"lantern_halo": C["lantern_halo"],
		"lantern_halos": C["lantern_halos"],
		"perches": perches,
		"lantern_world": lantern_world,
		"light_sources": light_sources,
		"glass_mats": C["glass_mats"],
		"interior_pos": _world(root, Vector3(0.35, fy + 1.60, -0.30)),
		"front_window_world": C["front_window_world"],
		"interior_lamp_world": lamp_world,
		"fireplace_world": fire_world,
		"attic_window_world": attic_window_world,
		"attic_lamp_world": attic_lamp_world,
		"attic_lamp2_world": attic_lamp2_world,
		"attic_glass_mats": C["attic_glass_mats"],
		"beam_occluders": beam_occluders,
		"cat": C.get("cat", {}),
		"stairs": C.get("stairs", {}),
	}

# ============================================================
# P7-V3.1 静态合批辅助
# ============================================================
## 合批区域划分：把 root 下的静态件按"所在空间"分成三层，避免整栋房屋被合并成
## 一个只能整体显隐的巨型网格，同时让视锥剔除粒度保持在"外壳 / 一层室内 / 阁楼"级别。
## 判定用 root 局部坐标（房子局部 ±X 为宽、±Z 为深）：
##   interior  一层室内  |x|<=4.95 |z|<=3.90 y<4.30
##   attic     二层阁楼  |x|<=4.95 |z|<=3.90 y>=5.40
##   shell     外墙/屋顶/勒脚/门廊/楼梯井壁等其余部分
static func _batch_region(root: Node3D, mi: Node3D) -> String:
	var p: Vector3 = root.to_local(mi.global_position)
	if absf(p.x) <= 4.95 and absf(p.z) <= 3.90:
		if p.y < 4.30:
			return "interior"
		if p.y >= 5.40:
			return "attic"
	return "shell"

## 把 parent 的直接子节点里所有 Prop_<kind>_<seq> 家具逐件静态合批。
## 只处理直接子节点：阁楼家具挂在 AtticInterior 下，一层家具挂 root 下，各管各的。
static func _merge_props_of(parent: Node3D) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	for c in parent.get_children():
		if c is Node3D and String(c.name).begins_with("Prop_"):
			IsleBatch.merge_static(c)

# ============================================================
# 0) 灯塔光束遮挡盒（Phase6/T4）
# ============================================================
# toon.gdshader 的解析锥只做几何方向判定，没有阴影贴图：光束会直接穿过墙/屋顶，
# 打到室内和背光墙面。这里导出小屋的遮挡盒，供 shader 用 ray-box 判定“该片元到灯室
# 的连线是否被屋子挡住”。
#
# 返回值：Array[Dictionary]，每个元素 {"center": Vector3 世界, "half": Vector3, "yaw": float 弧度}
#   * 盒是 yaw 对齐的 AABB：世界点 p 绕 Y 转 -yaw 后与 center±half 比较；
#   * yaw 取 cottage 世界旋转（本工程为 IsleMath.HOUSE_YAW=0.30），与 box 半尺寸同一坐标架；
#   * main._collect_beam_occluders() 取前 4 个写 g_occ_c0..c3 / g_occ_h0..h3 / g_occ_y0..y3。
#
# 尺寸取舍（重要）：
#   * 主体盒顶面 = 屋檐（roof_base=6.15），x/z 比墙外皮各外扩 0.02/0.04：受光面 p+0.06n
#     （shader 的 ro）落在盒外，避免受光墙把自己判成遮挡；背光面射线整段穿盒 → 全遮挡。
#   * 屋面盒是“屋檐 ~ 脊瓦顶”的整体包络（y 6.15~10.05）。屋顶是斜面，yaw-AABB 无法贴合；
#     宁大勿小：这样从屋顶上方/屋后射来的光不会漏进阁楼和背光山墙。代价是屋顶坡面自身
#     也落在盒内（beam 不会额外点亮坡面）——夜间屋顶本就暗，优先保证不穿墙。
#     z 半宽取 hd+0.04 而不是屋面挑檐的 hd+0.70：让前/后山墙外皮 p+0.06n 保持在盒外，
#     否则朝灯塔一侧的山墙（含阁楼窗）会被自己判遮挡、永远不受光。
#   * 烟囱盒覆盖泛水板之上到顶石（y 8.00~10.27，含压顶外扩 0.68）。
static func _beam_occluders_world(root: Node3D, C: Dictionary) -> Array:
	var xf: Transform3D = root.global_transform if root.is_inside_tree() else root.transform
	var hw: float = C["hw"]
	var hd: float = C["hd"]
	var roof_base: float = C["roof_base"]
	var ridge_y: float = C["ridge_y"]
	var eave_x: float = C["eave_x"]
	var ch_x: float = C["ch_x"]
	var ch_z: float = C["ch_z"]
	var ch_top: float = C["ch_top"]
	# toon.gdshader: p2 = R2d(-yaw) * (p - center)，R2d 为 (x,z) 平面标准旋转矩阵。
	# Godot 绕 Y 旋转 +a 的世界映射为 R2d(-a)，故要得到"世界→盒局部"必须传 yaw = -rotation.y。
	# 探针用同一公式复刻 shader 射线-盒判定并验证受光面 lit/背光面 occluded，勿改成 +rotation.y。
	var yaw: float = -atan2(xf.basis.z.x, xf.basis.z.z)
	var roof_top: float = ridge_y + 0.30
	var ch_lo: float = 8.00
	var ch_hi: float = ch_top + 0.35
	var out: Array = []
	# 1) 主体：地面/勒脚 ~ 屋檐（墙外皮 x=±5.30 / z=±4.20；半木立板与圈梁外凸到 5.36/4.255）
	out.append({
		"center": xf * Vector3(0.0, roof_base * 0.5, 0.0),
		"half": Vector3(hw + 0.02, roof_base * 0.5, hd + 0.04),
		"yaw": yaw,
	})
	# 2) 屋面：屋檐 ~ 脊瓦顶包络（x 到 eave_x=6.047；z 与主体一致见上）
	out.append({
		"center": xf * Vector3(0.0, (roof_base + roof_top) * 0.5, 0.0),
		"half": Vector3(eave_x, (roof_top - roof_base) * 0.5, hd + 0.04),
		"yaw": yaw,
	})
	# 3) 烟囱：泛水板 ~ 顶石
	out.append({
		"center": xf * Vector3(ch_x, (ch_lo + ch_hi) * 0.5, ch_z),
		"half": Vector3(0.68, (ch_hi - ch_lo) * 0.5, 0.65),
		"yaw": yaw,
	})
	return out

# 对外 API：build 之后按 root 取遮挡盒（供 main / 调试 / 探针使用）。
# 参数 root 必须是 IsleCottage.build() 返回的 "root" 节点（build 会写 meta cottage_ctx）。
static func get_beam_occluders(root: Node3D = null) -> Array:
	if root == null or not is_instance_valid(root):
		push_warning("IsleCottage.get_beam_occluders(): root 为空")
		return []
	if not root.has_meta("cottage_ctx"):
		push_warning("IsleCottage.get_beam_occluders(): root 缺少 cottage_ctx meta")
		return []
	var C: Dictionary = root.get_meta("cottage_ctx")
	return _beam_occluders_world(root, C)
# ============================================================
# 尺寸与共享材质上下文
# ============================================================
static func _context(root: Node3D) -> Dictionary:
	var w: float = M.HOUSE_W
	var d: float = M.HOUSE_D
	var wh: float = M.HOUSE_WALL_H
	var rh: float = M.HOUSE_ROOF_H
	var fy: float = 0.55
	var hw: float = w * 0.5
	var hd: float = d * 0.5
	var wall_t: float = 0.36
	var roof_base: float = fy + wh
	var ridge_y: float = roof_base + rh
	var pitch: float = atan(rh / hw)
	var cp: float = cos(pitch)
	var sp: float = sin(pitch)
	var eave_ov: float = 0.90
	var slope_len: float = sqrt(hw * hw + rh * rh) + eave_ov
	var eave_x: float = hw + eave_ov * cp
	var eave_y: float = ridge_y - slope_len * sp
	var roof_z: float = d + 1.4
	# 窗玻璃：主玻璃为共享材质（main 只改 window_mats 的 glow）；内层玻璃单列，形成双层玻璃层次。
	var glass_mat: ShaderMaterial = M.glass_material(0.06)
	# 内层玻璃：只保留极淡的第二层反射/吸收，避免双层叠加再把室内“糊”成乳白。
	var inner_glass: ShaderMaterial = M.glass_material(0.0)
	inner_glass.set_shader_parameter("tint", Color(0.80, 0.87, 0.89))
	inner_glass.set_shader_parameter("opacity", 0.045)
	inner_glass.set_shader_parameter("tint_strength", 0.16)
	inner_glass.set_shader_parameter("surface_rough", 0.04)
	inner_glass.set_shader_parameter("reflection_gain", 1.25)
	inner_glass.set_shader_parameter("refract_strength", 0.0)
	# 阁楼落地窗：夜间 main 会把 window_mats 的 glow 写到约 0.6，若共用则整面玻璃变成乳白雾面，
	# 从室外完全看不见室内。这里用两片独立材质压到“几乎纯透射”（法线入射 alpha≈0.05，双层透过率≈0.87）：
	#   outer=外侧低反射层（opacity 0.020 / fresnel_f0 0.030 / reflection_gain 0.34 / front_sheen 0.006）
	#   inner=室内侧更淡的一层（opacity 0.014 / fresnel_f0 0.026 / reflection_gain 0.26）
	# 两者都不进 window_mats，main 写 glow 不会命中它们；blend_mix + depth_draw_never 保留背景透过。
	var attic_outer_glass: ShaderMaterial = M.glass_material(0.0)
	attic_outer_glass.set_shader_parameter("tint", Color(0.86, 0.92, 0.94))
	attic_outer_glass.set_shader_parameter("opacity", 0.020)
	attic_outer_glass.set_shader_parameter("tint_strength", 0.10)
	attic_outer_glass.set_shader_parameter("fresnel_f0", 0.030)
	attic_outer_glass.set_shader_parameter("fresnel_power", 4.0)
	attic_outer_glass.set_shader_parameter("reflection_gain", 0.34)
	attic_outer_glass.set_shader_parameter("front_sheen", 0.006)
	attic_outer_glass.set_shader_parameter("refract_strength", 0.0)
	var attic_inner_glass: ShaderMaterial = M.glass_material(0.0)
	attic_inner_glass.set_shader_parameter("tint", Color(0.88, 0.93, 0.95))
	attic_inner_glass.set_shader_parameter("opacity", 0.014)
	attic_inner_glass.set_shader_parameter("tint_strength", 0.08)
	attic_inner_glass.set_shader_parameter("fresnel_f0", 0.026)
	attic_inner_glass.set_shader_parameter("fresnel_power", 4.0)
	attic_inner_glass.set_shader_parameter("reflection_gain", 0.26)
	attic_inner_glass.set_shader_parameter("front_sheen", 0.004)
	attic_inner_glass.set_shader_parameter("refract_strength", 0.0)
	# 门廊吊灯材质：main 会持续写 "glow"，不能和别的网格共用同一缓存实例。
	var lantern_mat: ShaderMaterial = M.toon_material(Color("ffcf9a"), {"self_lit": true, "glow": 1.0})
	# ---- P7-V3 楼梯井（与 _stairs / _interior / _attic_interior 共用，探针可直接读）----
	var attic_floor: float = 5.70
	var stair_risers: float = 27.0
	var stair_rise: float = (attic_floor - fy) / stair_risers
	return {
		"root": root,
		"w": w, "d": d, "wh": wh, "rh": rh, "fy": fy,
		"hw": hw, "hd": hd, "wall_t": wall_t,
		"roof_base": roof_base, "ridge_y": ridge_y,
		"pitch": pitch, "cp": cp, "sp": sp,
		"slope_len": slope_len, "eave_x": eave_x, "eave_y": eave_y,
		"roof_z": roof_z,
		"deck_top": 0.42,
		"stair_risers": stair_risers,
		"stair_rise": stair_rise,
		"stair_tread": 0.245,
		"stair_flight_a": {"x0": 3.70, "x1": 4.80, "z0": 0.55, "z1": -2.88, "land_top": fy + 15.0 * stair_rise},
		"stair_flight_b": {"x0": 3.70, "x1": 1.005, "z0": -3.80, "z1": -2.63},
		"stair_hole_r1": Rect2(3.65, -3.83, 1.17, 3.28),
		"stair_hole_r2": Rect2(1.005, -3.83, 2.645, 1.23),
		"ch_x": -2.40, "ch_z": -4.05, "ch_top": 9.92,
		"lantern_pos": Vector3(-2.80, 3.20, 6.55),
		"lantern_pos_right": Vector3(2.80, 3.20, 6.55),
		"attic_floor": 5.70,      # 阁楼地板顶面
		"attic_hw": 1.60,         # 阁楼窗半宽（洞口 3.20m 宽）
		"attic_top": 8.30,        # 阁楼窗洞顶（洞口 2.60m 高，跨前墙 0.45 + 山墙 2.15）
		"glass_mat": glass_mat,
		"inner_glass": inner_glass,
		"attic_outer_glass": attic_outer_glass,
		"attic_inner_glass": attic_inner_glass,
		"attic_glass_mats": [attic_outer_glass, attic_inner_glass],
		"lantern_mat": lantern_mat,
		"window_mats": [glass_mat],
		"glass_mats": [glass_mat, inner_glass],
		"window_halos": [],
		"win_lights": [],
		"front_window_world": [],
		"attic_window_world": Vector3.ZERO,
		"attic_lamp_world": Vector3.ZERO,
		"attic_lamp2_pos": Vector3(-0.60, 6.70, 0.20),
	}

# ============================================================
# 1) 石砌台基 / 勒脚
# ============================================================
static func _plinth(root: Node3D, C: Dictionary) -> void:
	var w: float = C["w"]
	var d: float = C["d"]
	var fy: float = C["fy"]
	var hw: float = C["hw"]
	var hd: float = C["hd"]
	var pw: float = w + 1.4
	var pd: float = d + 0.10
	# 台基主体（顶面 0.39 与压顶石底面 0.39 对接，避免两顶面共面）
	M.box(root, Vector3(pw, 1.14, pd), Vector3(0.0, -0.18, 0.0), M.C_STONE_DARK, 0.0, {"outline": 0.05})
	# 台基压顶石
	M.box(root, Vector3(pw + 0.26, 0.16, pd + 0.26), Vector3(0.0, fy - 0.08, 0.0), M.C_STONE, 0.0, {"outline": 0.03})
	# 台基四周两皮错缝石环（MultiMesh 实例化，颜色微差）
	var stone_mesh := BoxMesh.new()
	stone_mesh.size = Vector3(0.86, 0.19, 0.22)
	var stone_mat: ShaderMaterial = M.toon_material(M.C_STONE, {"vertex_color": true, "bands": 3.0, "soft": 0.50, "rim": 0.05})
	var sxf: Array = []
	var scol: Array = []
	for f in range(2):
		var sgn: float = -1.0 + 2.0 * float(f)
		for row in range(2):
			var yy: float = 0.10 + float(row) * 0.19
			var off: float = 0.45 if row == 1 else 0.0
			for i in range(14):
				var xx: float = -6.0 + (12.0 / 13.0) * (float(i) + 0.5) + off
				if xx > 6.02:
					xx -= 12.04
				sxf.append(Transform3D(Basis.IDENTITY, Vector3(xx, yy, sgn * (pd * 0.5))))
				var t: float = M.noise01(float(i) * 0.73 + float(row) * 2.1, float(f) * 1.7)
				var mm: float = 0.86 + t * 0.26
				scol.append(Color(mm, mm * 0.985, mm * 0.95, 1.0))
			for i in range(10):
				var zz: float = -pd * 0.5 + (pd / 10.0) * (float(i) + 0.5) + off
				if zz > pd * 0.5:
					zz -= pd
				sxf.append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(sgn * (pw * 0.5), yy, zz)))
				var t2: float = M.noise01(float(i) * 0.61 + 3.7, float(row) * 1.9 + float(f) * 4.3)
				var mm2: float = 0.86 + t2 * 0.26
				scol.append(Color(mm2, mm2 * 0.985, mm2 * 0.95, 1.0))
	M.multis(root, "PlinthStones", stone_mesh, sxf, scol, stone_mat)
	# 墙脚石裙 / 勒脚（门洞位置留空；外表面 4.36 不与墙皮 4.20 共面）
	M.box(root, Vector3(3.90, 0.50, 0.26), Vector3(-3.38, fy + 0.25, hd + 0.03), M.C_STONE_DARK, 0.0, {"outline": 0.03})
	M.box(root, Vector3(3.90, 0.50, 0.26), Vector3(3.38, fy + 0.25, hd + 0.03), M.C_STONE_DARK, 0.0, {"outline": 0.03})
	M.box(root, Vector3(w + 0.04, 0.50, 0.26), Vector3(0.0, fy + 0.25, -hd - 0.03), M.C_STONE_DARK, 0.0, {"outline": 0.03})
	M.box(root, Vector3(0.26, 0.52, d + 0.02), Vector3(-hw - 0.03, fy + 0.27, 0.0), M.C_STONE_DARK, 0.0, {"outline": 0.03})
	M.box(root, Vector3(0.26, 0.52, d + 0.02), Vector3(hw + 0.03, fy + 0.27, 0.0), M.C_STONE_DARK, 0.0, {"outline": 0.03})

# ============================================================
# 1.5) 门廊台阶：6 级（旧版 3 级 -> +3 级），rise 0.16 / run 0.30，接到地形
# ============================================================
static func _porch_steps(root: Node3D, C: Dictionary) -> void:
	var deck_top: float = C["deck_top"]
	var run: float = 0.30
	var n: int = 6
	var z_top: float = 7.20
	var widths: Array = [3.60, 3.45, 3.30, 3.15, 3.00, 2.85]
	var stones: Array = [M.C_STONE, M.C_STONE_DARK]
	# 依据台阶前缘实际地形反算 rise：底级踏面比地面高 0.02，保证“不悬浮、不埋没”
	var wpos: Vector3 = _world(root, Vector3(0.0, 0.0, z_top + run * float(n) + 0.05))
	var ground_local: float = M.terrain_height(wpos.x, wpos.z) - root.position.y
	var bottom_y: float = ground_local + 0.02
	var rise: float = (deck_top - bottom_y) / float(n)
	var steps := Node3D.new()
	steps.name = "PorchSteps"
	root.add_child(steps)
	for i in range(n):
		var ty: float = deck_top - rise * float(i + 1)
		var h: float = ty + 1.05
		var zc: float = z_top + run * (float(i) + 0.5)
		var wd: float = widths[i]
		M.box(steps, Vector3(wd, h, run), Vector3(0.0, ty - h * 0.5, zc), stones[i % 2], 0.0, {"outline": 0.025})
	steps.set_meta("step_count", n)
	steps.set_meta("rise", rise)
	steps.set_meta("run", run)
	steps.set_meta("top_y", deck_top)
	steps.set_meta("bottom_y", bottom_y)
	steps.set_meta("z_top", z_top)
	# 台阶两侧望柱 + 顺坡扶手 + 栏杆条（全部按实际 rise 计算，与门廊栏杆同高衔接）
	var z_newel: float = z_top + run * float(n)
	var y_deck_rail: float = deck_top + 0.95
	var y_newel_top: float = bottom_y + 0.90
	for sx in [-1.0, 1.0]:
		var nb: float = ground_local - 0.55
		var nh: float = y_newel_top - nb
		M.box(root, Vector3(0.12, nh, 0.12), Vector3(sx * 1.88, nb + nh * 0.5, z_newel), M.C_WOOD_DARK, 0.0, {"outline": 0.025})
		var dy: float = y_newel_top - y_deck_rail
		var dz: float = z_newel - 6.95
		var rlen: float = sqrt(dy * dy + dz * dz)
		var rot_x: float = atan2(-dy, dz)
		M.box_rot(root, Vector3(0.09, 0.09, rlen + 0.06), Vector3(sx * 1.88, (y_newel_top + y_deck_rail) * 0.5, (z_newel + 6.95) * 0.5), M.C_WOOD, Vector3(rot_x, 0.0, 0.0), {"outline": 0.02})
		# 3 根栏杆条（跟随台阶高度与扶手坡度变化）
		for k in [1, 3, 5]:
			var zc2: float = z_top + run * (float(k) + 0.5)
			var by2: float = deck_top - rise * float(k + 1)
			var f2: float = (zc2 - 6.95) / dz
			var ry2: float = y_deck_rail + (y_newel_top - y_deck_rail) * f2
			var bh2: float = ry2 - by2 - 0.02
			M.box(root, Vector3(0.05, bh2, 0.05), Vector3(sx * 1.88, by2 + bh2 * 0.5, zc2), M.C_WOOD_DARK, 0.0, {})

# ============================================================
# 2) 四面墙板：真实门窗洞口 + 半木结构（所有装饰外凸 0.04-0.06，独立厚度/背面埋入墙体，禁止与墙皮共面）
# ============================================================
static func _walls(root: Node3D, C: Dictionary) -> void:
	var w: float = C["w"]
	var d: float = C["d"]
	var wh: float = C["wh"]
	var fy: float = C["fy"]
	var hw: float = C["hw"]
	var hd: float = C["hd"]
	var wall_t: float = C["wall_t"]
	var roof_base: float = C["roof_base"]
	var zf: float = hd - wall_t * 0.5
	var zb: float = -zf
	var mid_y: float = fy + wh * 0.5
	var wcol: Color = M.C_WALL
	var wo: Dictionary = {"bands": 4.0, "soft": 0.60, "rim": 0.10}
	var tcol: Color = M.C_WOOD_DARK
	var to: Dictionary = {"bands": 4.0, "soft": 0.50, "rim": 0.18, "outline": 0.03}

	# ---- 前墙（+Z）：门洞 x±1.30 (y 0.55..4.20) + 两窗洞 + 阁楼窗下部洞口（x±1.60, y 5.70..6.15）----
	M.box(root, Vector3(1.15, wh, wall_t), Vector3(-4.725, mid_y, zf), wcol, 0.0, wo)
	M.box(root, Vector3(1.40, 1.45, wall_t), Vector3(-3.45, fy + 0.725, zf), wcol, 0.0, wo)
	M.box(root, Vector3(1.40, 2.45, wall_t), Vector3(-3.45, fy + 4.375, zf), wcol, 0.0, wo)
	M.box(root, Vector3(1.15, wh, wall_t), Vector3(-2.175, mid_y, zf), wcol, 0.0, wo)
	M.box(root, Vector3(0.30, 5.15, wall_t), Vector3(-1.45, 3.125, zf), wcol, 0.0, wo)
	M.box(root, Vector3(2.60, 1.50, wall_t), Vector3(0.0, 4.95, zf), wcol, 0.0, wo)
	M.box(root, Vector3(0.30, 5.15, wall_t), Vector3(1.45, 3.125, zf), wcol, 0.0, wo)
	M.box(root, Vector3(1.15, wh, wall_t), Vector3(2.175, mid_y, zf), wcol, 0.0, wo)
	M.box(root, Vector3(1.40, 1.45, wall_t), Vector3(3.45, fy + 0.725, zf), wcol, 0.0, wo)
	M.box(root, Vector3(1.40, 2.45, wall_t), Vector3(3.45, fy + 4.375, zf), wcol, 0.0, wo)
	M.box(root, Vector3(1.15, wh, wall_t), Vector3(4.725, mid_y, zf), wcol, 0.0, wo)

	# ---- 两侧墙：各一窗 ----
	for sx in [-1.0, 1.0]:
		var xw: float = sx * (hw - wall_t * 0.5)
		M.box(root, Vector3(wall_t, wh, 2.79), Vector3(xw, mid_y, -2.445), wcol, 0.0, wo)
		M.box(root, Vector3(wall_t, 1.80, 1.50), Vector3(xw, fy + 0.90, -0.30), wcol, 0.0, wo)
		M.box(root, Vector3(wall_t, 2.50, 1.50), Vector3(xw, fy + 4.35, -0.30), wcol, 0.0, wo)
		M.box(root, Vector3(wall_t, wh, 3.39), Vector3(xw, mid_y, 2.145), wcol, 0.0, wo)

	# ---- 后墙：一窗 ----
	M.box(root, Vector3(6.80, wh, wall_t), Vector3(-1.90, mid_y, zb), wcol, 0.0, wo)
	M.box(root, Vector3(1.40, 1.85, wall_t), Vector3(2.20, fy + 0.925, zb), wcol, 0.0, wo)
	M.box(root, Vector3(1.40, 2.45, wall_t), Vector3(2.20, fy + 4.375, zb), wcol, 0.0, wo)
	M.box(root, Vector3(2.40, wh, wall_t), Vector3(4.10, mid_y, zb), wcol, 0.0, wo)

	# ---- 半木结构：四角立板（独立厚度 0.16，外凸 0.05，顶端低于圈梁）----
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			M.box(root, Vector3(0.30, wh - 0.04, 0.16), Vector3(sx * (hw - 0.16), fy + 2.76, sz * (hd - 0.03)), tcol, 0.0, to)
			M.box(root, Vector3(0.16, wh - 0.04, 0.30), Vector3(sx * (hw - 0.03), fy + 2.76, sz * (hd - 0.16)), tcol, 0.0, to)
	# 顶圈梁（前圈梁在阁楼窗处断开；外表面 z=4.255 / x=±5.36，独立厚度，不与墙皮共面）
	var zfo: float = zf + 0.135
	var xo: float = hw - 0.03
	M.box(root, Vector3(3.73, 0.26, 0.20), Vector3(-3.565, roof_base - 0.14, zfo), tcol, 0.0, {"outline": 0.03})
	M.box(root, Vector3(3.73, 0.26, 0.20), Vector3(3.565, roof_base - 0.14, zfo), tcol, 0.0, {"outline": 0.03})
	M.box(root, Vector3(w + 0.26, 0.26, 0.20), Vector3(0.0, roof_base - 0.14, -zfo), tcol, 0.0, {"outline": 0.03})
	M.box(root, Vector3(0.18, 0.22, d + 0.26), Vector3(xo, roof_base - 0.11, 0.0), tcol, 0.0, {"outline": 0.03})
	M.box(root, Vector3(0.18, 0.22, d + 0.26), Vector3(-xo, roof_base - 0.11, 0.0), tcol, 0.0, {"outline": 0.03})
	# 门两侧外立柱（顶端 5.69 止于阁楼窗台下方，避免挡窗）+ 门上过梁
	for sx in [-1.0, 1.0]:
		M.box(root, Vector3(0.24, 5.14, 0.18), Vector3(sx * 1.53, 3.12, zf + 0.14), tcol, 0.0, {"outline": 0.03})
	M.box(root, Vector3(3.26, 0.22, 0.15), Vector3(0.0, fy + 3.95, zf + 0.14), tcol, 0.0, {"outline": 0.03})
	# 前墙窗下横梁（门洞处断开）
	M.box(root, Vector3(3.70, 0.18, 0.14), Vector3(-3.30, fy + 1.28, zf + 0.15), tcol, 0.0, {"outline": 0.02})
	M.box(root, Vector3(3.70, 0.18, 0.14), Vector3(3.30, fy + 1.28, zf + 0.15), tcol, 0.0, {"outline": 0.02})
	# 四角斜撑（外凸 0.04，独立厚度 0.11，背面埋入墙体）
	var by: float = roof_base - 0.40
	M.box_rot(root, Vector3(0.95, 0.20, 0.11), Vector3(-4.55, by, hd - 0.015), tcol, Vector3(0.0, 0.0, 0.72), {"outline": 0.02})
	M.box_rot(root, Vector3(0.95, 0.20, 0.11), Vector3(4.55, by, hd - 0.015), tcol, Vector3(0.0, 0.0, -0.72), {"outline": 0.02})
	M.box_rot(root, Vector3(0.95, 0.20, 0.11), Vector3(-4.55, by, -hd + 0.015), tcol, Vector3(0.0, 0.0, -0.72), {"outline": 0.02})
	M.box_rot(root, Vector3(0.95, 0.20, 0.11), Vector3(4.55, by, -hd + 0.015), tcol, Vector3(0.0, 0.0, 0.72), {"outline": 0.02})
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			M.box_rot(root, Vector3(0.11, 0.20, 0.95), Vector3(sx * (hw - 0.015), by, sz * 3.55), tcol, Vector3(sz * 0.72, 0.0, 0.0), {"outline": 0.02})

# ============================================================
# 3) 窗：真实洞口 + 木框（重叠洞口边）+ 窗棂 + 凹入玻璃 + 窗外光晕
# ============================================================
static func _windows(root: Node3D, C: Dictionary) -> void:
	var fy: float = C["fy"]
	var hd: float = C["hd"]
	var hw: float = C["hw"]
	var wall_t: float = C["wall_t"]
	var zf: float = hd - wall_t * 0.5
	var xf: float = hw - wall_t * 0.5
	for sx in [-1.0, 1.0]:
		var pf := Node3D.new()
		pf.name = "WindowFront"
		pf.position = Vector3(sx * 3.45, fy + 2.30, zf)
		root.add_child(pf)
		_window_assembly(root, pf, C, 1.40, 1.70, true)
	var pl := Node3D.new()
	pl.name = "WindowLeft"
	pl.position = Vector3(-xf, fy + 2.45, -0.30)
	pl.rotation.y = -PI * 0.5
	root.add_child(pl)
	_window_assembly(root, pl, C, 1.50, 1.30, false)
	var pr := Node3D.new()
	pr.name = "WindowRight"
	pr.position = Vector3(xf, fy + 2.45, -0.30)
	pr.rotation.y = PI * 0.5
	root.add_child(pr)
	_window_assembly(root, pr, C, 1.50, 1.30, false)
	var pb := Node3D.new()
	pb.name = "WindowBack"
	pb.position = Vector3(2.20, fy + 2.50, -zf)
	pb.rotation.y = PI
	root.add_child(pb)
	_window_assembly(root, pb, C, 1.40, 1.30, false)

static func _window_assembly(root: Node3D, pivot: Node3D, C: Dictionary, ow: float, oh: float, is_front: bool) -> void:
	var wt: float = C["wall_t"]
	var glass_mat: ShaderMaterial = C["glass_mat"]
	var vdepth: float = wt + 0.18   # 立框厚 0.54
	var rdepth: float = wt + 0.10   # 上下框厚 0.46
	var hdepth: float = wt + 0.14   # 窗楣厚 0.50（三者互不共面）
	# 玻璃（共享材质，半透明、可透见室内；凹入洞口 0.14m，避免与墙面/窗套共面）
	var glass := MeshInstance3D.new()
	var gb := BoxMesh.new()
	gb.size = Vector3(ow - 0.02, oh - 0.02, 0.035)
	glass.mesh = gb
	glass.material_override = glass_mat
	glass.position = Vector3(0.0, 0.0, 0.01)
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(glass)
	# 木窗框：左右边框（宽 0.16，压住洞口边 0.06）/ 上下框（高 0.14，压住洞口边 0.05）
	M.box(pivot, Vector3(0.16, oh + 0.20, vdepth), Vector3(-(ow * 0.5 + 0.02), 0.0, 0.0), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
	M.box(pivot, Vector3(0.16, oh + 0.20, vdepth), Vector3(ow * 0.5 + 0.02, 0.0, 0.0), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
	M.box(pivot, Vector3(ow + 0.04, 0.14, rdepth), Vector3(0.0, oh * 0.5 + 0.02, 0.0), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
	M.box(pivot, Vector3(ow + 0.04, 0.14, rdepth), Vector3(0.0, -(oh * 0.5 + 0.02), 0.0), M.C_WOOD, 0.0, {"outline": 0.02})
	# 外窗台 / 内窗台
	M.box(pivot, Vector3(ow + 0.40, 0.10, 0.26), Vector3(0.0, -(oh * 0.5 + 0.16), wt * 0.5 + 0.10), M.C_WOOD, 0.0, {"outline": 0.02})
	M.box(pivot, Vector3(ow + 0.30, 0.09, 0.24), Vector3(0.0, -(oh * 0.5 + 0.14), -(wt * 0.5 + 0.08)), M.C_WOOD_LIGHT, 0.0, {"outline": 0.02})
	# 窗楣（外凸 0.09）
	M.box(pivot, Vector3(ow + 0.44, 0.16, hdepth), Vector3(0.0, oh * 0.5 + 0.17, 0.0), M.C_WOOD_DARK, 0.0, {"outline": 0.03})
	# 格子窗棂（竖棂 0.06 宽 / 横棂 0.04 深，前后错开不共面，互不接触玻璃）
	M.box(pivot, Vector3(0.06, oh - 0.04, 0.06), Vector3(-ow / 6.0, 0.0, 0.065), M.C_WOOD_DARK, 0.0, {})
	M.box(pivot, Vector3(0.06, oh - 0.04, 0.06), Vector3(ow / 6.0, 0.0, 0.065), M.C_WOOD_DARK, 0.0, {})
	M.box(pivot, Vector3(ow - 0.04, 0.06, 0.04), Vector3(0.0, -oh / 6.0, 0.065), M.C_WOOD_DARK, 0.0, {})
	M.box(pivot, Vector3(ow - 0.04, 0.06, 0.04), Vector3(0.0, oh / 6.0, 0.065), M.C_WOOD_DARK, 0.0, {})
	# 窗外暖光光晕（main 每帧调 albedo 亮度）
	var halo := M.halo(root, pivot.transform * Vector3(0.0, 0.0, wt * 0.5 + 0.50), 1.75, Color(2.2, 1.4, 0.7, 1.0))
	C["window_halos"].append(halo)
	C["win_lights"].append({"pos": _world(root, pivot.transform * Vector3(0.0, 0.0, wt * 0.5 + 0.85))})
	if is_front:
		C["front_window_world"].append(_world(root, pivot.transform * Vector3(0.0, 0.0, 0.02)))

# ============================================================
# 4) 门：真实矩形门洞（x±1.30, y 0.55..4.20）+ 拱券门框 + 拱形门扇 + 门洞上部真实拱形墙体补板
# ============================================================
static func _door(root: Node3D, C: Dictionary) -> void:
	var fy: float = C["fy"]
	var hd: float = C["hd"]
	var wt: float = C["wall_t"]
	var zf: float = hd - wt * 0.5
	# ---- 拱券门框：单片半环挤出网格（内 r=1.15 / 外 r=1.45 / 厚 0.26），替代原 13 段 box 拼接 ----
	_door_arch_ring(root, C)
	# 拱脚立柱（压住洞口两侧并覆盖门扇边 1cm，外凸 0.06；宽 0.40 → x 1.10..1.50，消除门扇与立柱之间的窄缝）
	M.box(root, Vector3(0.40, 2.40, 0.36), Vector3(-1.30, fy + 1.20, zf + 0.06), M.C_WOOD_DARK, 0.0, {"outline": 0.03})
	M.box(root, Vector3(0.40, 2.40, 0.36), Vector3(1.30, fy + 1.20, zf + 0.06), M.C_WOOD_DARK, 0.0, {"outline": 0.03})
	# 门前石门槛
	M.box(root, Vector3(2.70, 0.14, 0.85), Vector3(0.0, fy - 0.065, hd + 0.24), M.C_STONE, 0.0, {"outline": 0.02})
	# ---- 拱券以上补成真实拱形墙体（自定义网格，与墙前皮平齐、与门扇留 5mm 搭接），杜绝门洞上角透空 ----
	_door_spandrel(root, C)

	# ---- 门扇（door_pivot：铰链在左侧门边，rotation.y=0 关闭）----
	var pivot := Node3D.new()
	pivot.name = "DoorPivot"
	pivot.position = Vector3(-1.13, fy, hd - 0.06)
	# 门扇是唯一会被逐帧旋转的房屋部件：标记 no_batch，静态合批工具不会碰它
	# （它的子部件必须保持相对 pivot 的独立变换才能整体开门）。
	pivot.set_meta("no_batch", true)
	root.add_child(pivot)
	C["door_pivot"] = pivot
	for i in range(5):
		var px: float = 0.245 + float(i) * 0.442
		var pc: Color = M.C_WOOD_LIGHT if i % 2 == 0 else M.C_WOOD
		M.box(pivot, Vector3(0.43, 2.30, 0.10), Vector3(px, 1.15, 0.0), pc, 0.0, {"outline": 0.02, "bands": 4.0})
	M.box(pivot, Vector3(0.10, 2.34, 0.14), Vector3(0.07, 1.17, 0.0), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
	M.box(pivot, Vector3(0.10, 2.34, 0.14), Vector3(2.19, 1.17, 0.0), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
	for yy in [0.20, 1.15, 2.20]:
		M.box(pivot, Vector3(2.26, 0.12, 0.12), Vector3(1.13, yy, 0.0), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
	# ---- 门扇上方半圆气窗：半圆盘单体网格（半径 1.10，厚 0.10，与门板同厚齐平；含凸起拱带、竖棂与弦线横档）----
	_door_fanlight(pivot, C)
	for zz in [-0.075, 0.075]:
		M.box(pivot, Vector3(0.08, 2.28, 0.035), Vector3(0.56, 1.15, zz), M.C_WOOD_DARK, 0.0, {})
		M.box(pivot, Vector3(0.08, 2.28, 0.035), Vector3(1.70, 1.15, zz), M.C_WOOD, 0.0, {})
	var gold: ShaderMaterial = M.toon_material(Color("e0b45a"), {"bands": 4.0, "rim": 0.35})
	var knob := MeshInstance3D.new()
	var km := SphereMesh.new()
	km.radius = 0.085
	km.height = 0.17
	km.radial_segments = 8
	km.rings = 5
	knob.mesh = km
	knob.material_override = gold
	knob.position = Vector3(1.94, 1.05, 0.11)
	knob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(knob)
	M.box(pivot, Vector3(0.10, 0.26, 0.03), Vector3(1.94, 1.05, 0.065), Color("8a6a2e"), 0.0, {})
	for yy2 in [0.42, 1.92]:
		M.box(pivot, Vector3(0.09, 0.26, 0.16), Vector3(0.03, yy2, 0.0), Color("3a3630"), 0.0, {})

static func _door_spandrel(root: Node3D, C: Dictionary) -> void:
	# 矩形门洞上部补成真实拱形墙体（自建网格）：前/后墙面与墙体平齐，拱腹朝圆心，
	# 两侧底封板朝下；与门扇（半径 1.10，重叠 5mm）之间无透空缝、无共面重叠面。
	var hd: float = C["hd"]
	var wt: float = C["wall_t"]
	var fy: float = C["fy"]
	var zf: float = hd - wt * 0.5
	var yc: float = fy + 2.35
	var ytop: float = fy + 3.65
	var half: float = 1.30
	var ra: float = 1.095
	var zfr: float = zf + wt * 0.5
	var zbk: float = zf - wt * 0.5
	var n: int = 16
	var outer: Array[Vector2] = []
	var inner: Array[Vector2] = []
	for k in range(n):
		var a: float = PI * float(k) / float(n)
		var ca: float = cos(a)
		var sa: float = sin(a)
		var t: float = 1e9
		if absf(ca) > 1e-5:
			t = minf(t, half / absf(ca))
		if sa > 1e-5:
			t = minf(t, (ytop - yc) / sa)
		outer.append(Vector2(ca * t, sa * t))
		inner.append(Vector2(ca * ra, sa * ra))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(n - 1):
		var i0: Vector2 = inner[k]
		var i1: Vector2 = inner[k + 1]
		var o0: Vector2 = outer[k]
		var o1: Vector2 = outer[k + 1]
		_st_quad(st, Vector3(i0.x, yc + i0.y, zfr), Vector3(o0.x, yc + o0.y, zfr), Vector3(o1.x, yc + o1.y, zfr), Vector3(i1.x, yc + i1.y, zfr))
		_st_quad(st, Vector3(i0.x, yc + i0.y, zbk), Vector3(i1.x, yc + i1.y, zbk), Vector3(o1.x, yc + o1.y, zbk), Vector3(o0.x, yc + o0.y, zbk))
		_st_quad(st, Vector3(i0.x, yc + i0.y, zfr), Vector3(i1.x, yc + i1.y, zfr), Vector3(i1.x, yc + i1.y, zbk), Vector3(i0.x, yc + i0.y, zbk))
	_st_quad(st, Vector3(-half, yc, zfr), Vector3(-half, yc, zbk), Vector3(-ra, yc, zbk), Vector3(-ra, yc, zfr))
	_st_quad(st, Vector3(half, yc, zfr), Vector3(ra, yc, zfr), Vector3(ra, yc, zbk), Vector3(half, yc, zbk))
	var mi := MeshInstance3D.new()
	mi.name = "DoorSpandrel"
	mi.mesh = st.commit()
	mi.material_override = M.toon_material(M.C_WALL, {"bands": 4.0, "soft": 0.60, "rim": 0.10})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 门洞拱形补墙是单一自定义网格的关键结构件（不是重复小件），保留具名独立节点：
	# 合批收益只有 2 个 pass，换来的可调试性更重要。
	mi.set_meta("no_batch", true)
	root.add_child(mi)

static func _door_arch_ring(root: Node3D, C: Dictionary) -> void:
	# 拱券门框：半环单体挤出网格。前/后环面 + 外/内弧侧壁 + 左右拱脚端面全部一次生成，
	# 绕序与显式法线一致（Godot 默认背面剔除），不再有方块接缝、重叠描边与穿插。
	var hd: float = C["hd"]
	var wt: float = C["wall_t"]
	var fy: float = C["fy"]
	var zf: float = hd - wt * 0.5
	var yc: float = fy + 2.35
	var ri: float = 1.15
	var ro: float = 1.45
	var z_hi: float = zf + 0.22
	var z_lo: float = zf - 0.04
	var n: int = 24
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var of: Array[Vector3] = []
	var ob: Array[Vector3] = []
	var inf: Array[Vector3] = []
	var inb: Array[Vector3] = []
	for k in range(n + 1):
		var a: float = PI * float(k) / float(n)
		var ca: float = cos(a)
		var sa: float = sin(a)
		of.append(Vector3(ca * ro, yc + sa * ro, z_hi))
		ob.append(Vector3(ca * ro, yc + sa * ro, z_lo))
		inf.append(Vector3(ca * ri, yc + sa * ri, z_hi))
		inb.append(Vector3(ca * ri, yc + sa * ri, z_lo))
	for k in range(n):
		var am: float = PI * (float(k) + 0.5) / float(n)
		var out_n := Vector3(cos(am), sin(am), 0.0)
		_st_quad_n(st, of[k], of[k + 1], inf[k + 1], inf[k], Vector3(0.0, 0.0, 1.0))
		_st_quad_n(st, ob[k], ob[k + 1], inb[k + 1], inb[k], Vector3(0.0, 0.0, -1.0))
		_st_quad_n(st, of[k], of[k + 1], ob[k + 1], ob[k], out_n)
		_st_quad_n(st, inf[k], inf[k + 1], inb[k + 1], inb[k], -out_n)
	# 左右拱脚端面（朝下）
	_st_quad_n(st, Vector3(ri, yc, z_lo), Vector3(ro, yc, z_lo), Vector3(ro, yc, z_hi), Vector3(ri, yc, z_hi), Vector3(0.0, -1.0, 0.0))
	_st_quad_n(st, Vector3(-ri, yc, z_lo), Vector3(-ro, yc, z_lo), Vector3(-ro, yc, z_hi), Vector3(-ri, yc, z_hi), Vector3(0.0, -1.0, 0.0))
	var mi := MeshInstance3D.new()
	mi.name = "DoorArch"
	mi.mesh = st.commit()
	mi.material_override = M.toon_material(M.C_WOOD_DARK, {"bands": 4.0, "outline": 0.03})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 半圆拱券是门的关键轮廓结构件（单一自定义网格），保留具名独立节点。
	mi.set_meta("no_batch", true)
	root.add_child(mi)
	# 拱顶锁石：仅作拱顶装饰高光块，不参与半圆轮廓构成
	M.box_rot(root, Vector3(0.34, 0.30, 0.30), Vector3(0.0, yc + 1.31, zf + 0.10), M.C_WOOD_LIGHT, Vector3.ZERO, {"outline": 0.03})

static func _door_fanlight(pivot: Node3D, C: Dictionary) -> void:
	# 门扇上方半圆气窗：半圆盘单体挤出网格（弦线落在门板上沿 y=2.30，与门板无缝隙），
	# 正面/背面/外弧侧壁/弦线底封一次生成；另加同心凸起拱带与细竖棂、弦线横档。
	var cx: float = 1.13
	var cy: float = 2.35
	var r: float = 1.10
	var y_chord: float = 2.30
	var hz: float = 0.05
	var dy: float = y_chord - cy
	var xh: float = sqrt(maxf(r * r - dy * dy, 0.0))
	var a0: float = atan2(dy, xh)
	var a1: float = PI - a0
	var n: int = 24
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var front: Array[Vector3] = []
	var back: Array[Vector3] = []
	for k in range(n + 1):
		var a: float = lerpf(a0, a1, float(k) / float(n))
		var x: float = cx + cos(a) * r
		var y: float = cy + sin(a) * r
		front.append(Vector3(x, y, hz))
		back.append(Vector3(x, y, -hz))
	var c_f := Vector3(cx, y_chord, hz)
	var c_b := Vector3(cx, y_chord, -hz)
	for k in range(n):
		var am: float = lerpf(a0, a1, (float(k) + 0.5) / float(n))
		var out_n := Vector3(cos(am), sin(am), 0.0)
		_st_tri_n(st, c_f, front[k], front[k + 1], Vector3(0.0, 0.0, 1.0))
		_st_tri_n(st, c_b, back[k + 1], back[k], Vector3(0.0, 0.0, -1.0))
		_st_quad_n(st, back[k], back[k + 1], front[k + 1], front[k], out_n)
	# 弦线底封（朝下，与门板上沿贴合）
	_st_quad_n(st, Vector3(cx + xh, y_chord, -hz), Vector3(cx - xh, y_chord, -hz), Vector3(cx - xh, y_chord, hz), Vector3(cx + xh, y_chord, hz), Vector3(0.0, -1.0, 0.0))
	var mi := MeshInstance3D.new()
	mi.name = "DoorFanlight"
	mi.mesh = st.commit()
	mi.material_override = M.toon_material(M.C_WOOD, {"bands": 4.0, "outline": 0.02})
	pivot.add_child(mi)
	# 前脸同心凸起拱带（r 0.84..0.98，凸出 3.5cm）
	var bz_hi: float = 0.085
	var bz_lo: float = 0.0505
	var rb0: float = 0.84
	var rb1: float = 0.98
	var x0: float = sqrt(maxf(rb0 * rb0 - dy * dy, 0.0))
	var x1: float = sqrt(maxf(rb1 * rb1 - dy * dy, 0.0))
	var ab0: float = atan2(dy, x0)
	var ab1: float = PI - ab0
	var bst := SurfaceTool.new()
	bst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bof: Array[Vector3] = []
	var bob: Array[Vector3] = []
	var bif: Array[Vector3] = []
	var bib: Array[Vector3] = []
	for k in range(n + 1):
		var a: float = lerpf(ab0, ab1, float(k) / float(n))
		var ca: float = cos(a)
		var sa: float = sin(a)
		bof.append(Vector3(cx + ca * rb1, cy + sa * rb1, bz_hi))
		bob.append(Vector3(cx + ca * rb1, cy + sa * rb1, bz_lo))
		bif.append(Vector3(cx + ca * rb0, cy + sa * rb0, bz_hi))
		bib.append(Vector3(cx + ca * rb0, cy + sa * rb0, bz_lo))
	for k in range(n):
		var am: float = lerpf(ab0, ab1, (float(k) + 0.5) / float(n))
		var out_n := Vector3(cos(am), sin(am), 0.0)
		_st_quad_n(bst, bof[k], bof[k + 1], bif[k + 1], bif[k], Vector3(0.0, 0.0, 1.0))
		_st_quad_n(bst, bob[k], bob[k + 1], bib[k + 1], bib[k], Vector3(0.0, 0.0, -1.0))
		_st_quad_n(bst, bof[k], bof[k + 1], bob[k + 1], bob[k], out_n)
		_st_quad_n(bst, bif[k], bif[k + 1], bib[k + 1], bib[k], -out_n)
	_st_quad_n(bst, Vector3(cx + x1, y_chord, bz_lo), Vector3(cx + x0, y_chord, bz_lo), Vector3(cx + x0, y_chord, bz_hi), Vector3(cx + x1, y_chord, bz_hi), Vector3(0.0, -1.0, 0.0))
	_st_quad_n(bst, Vector3(cx - x1, y_chord, bz_lo), Vector3(cx - x0, y_chord, bz_lo), Vector3(cx - x0, y_chord, bz_hi), Vector3(cx - x1, y_chord, bz_hi), Vector3(0.0, -1.0, 0.0))
	var bmi := MeshInstance3D.new()
	bmi.name = "DoorFanlightTrim"
	bmi.mesh = bst.commit()
	bmi.material_override = M.toon_material(M.C_WOOD_DARK, {"bands": 4.0, "outline": 0.02})
	pivot.add_child(bmi)
	# 细竖棂（不跨拱带）与弦线横档（盖住门板/气窗接缝）
	M.box(pivot, Vector3(0.055, 0.83, 0.05), Vector3(cx, 2.715, 0.055), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
	for sx in [-0.36, 0.36]:
		M.box(pivot, Vector3(0.055, 0.742, 0.05), Vector3(cx + sx, 2.671, 0.055), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
	M.box(pivot, Vector3(2.24, 0.10, 0.14), Vector3(cx, 2.28, 0.0), M.C_WOOD_DARK, 0.0, {"outline": 0.02})

# ============================================================
# 5) 双坡瓦屋顶 + 前山墙真实洞口 + 错缝的博风/封檐/烟囱泛水
# ============================================================
static func _roof(root: Node3D, C: Dictionary) -> void:
	var w: float = C["w"]
	var hd: float = C["hd"]
	var rh: float = C["rh"]
	var wall_t: float = C["wall_t"]
	var roof_base: float = C["roof_base"]
	var ridge_y: float = C["ridge_y"]
	var pitch: float = C["pitch"]
	var cp: float = C["cp"]
	var sp: float = C["sp"]
	var slope_len: float = C["slope_len"]
	var eave_x: float = C["eave_x"]
	var eave_y: float = C["eave_y"]
	var roof_z: float = C["roof_z"]
	var hz: float = roof_z * 0.5
	# 前山墙：带真实矩形洞口的自定义网格；后山墙保留实心三角
	_front_gable(root, C)
	M.prism(root, w, rh, wall_t, Vector3(0.0, roof_base, -(hd - wall_t * 0.5)), M.C_WALL, 0.0, {"bands": 4.0, "soft": 0.60, "rim": 0.08})
	# 屋面板：两块 0.16 厚斜面（出檐 0.90）
	for side in [-1.0, 1.0]:
		var down := Vector3(side * cp, -sp, 0.0)
		var nrm := Vector3(side * sp, cp, 0.0)
		var mid: Vector3 = Vector3(0.0, ridge_y, 0.0) + down * (slope_len * 0.5)
		M.box_rot(root, Vector3(slope_len, 0.16, roof_z), mid - nrm * 0.08, M.C_WOOD, Vector3(0.0, 0.0, -side * pitch), {"outline": 0.0})
	# 屋脊梁 + 脊瓦（MultiMesh）
	M.box(root, Vector3(0.46, 0.34, roof_z + 0.10), Vector3(0.0, ridge_y - 0.20, 0.0), M.C_WOOD_DARK, 0.0, {"outline": 0.0})
	var cap_data: Dictionary = _roof_cap_data(C)
	M.multis(root, "RoofRidgeCaps", cap_data["mesh"], cap_data["xforms"], cap_data["colors"], M.toon_material(M.C_TERRACOTTA_DARK, {"vertex_color": true, "bands": 3.0, "soft": 0.45}))
	# 檐口封檐板（外表面 6.0646，与屋面板端面无共面）
	for side in [-1.0, 1.0]:
		M.box(root, Vector3(0.14, 0.34, roof_z + 0.02), Vector3(side * (eave_x - 0.05), eave_y - 0.12, 0.0), M.C_WOOD_DARK, 0.0, {"outline": 0.03})
	# 山墙博风板：z 方向外移 0.02（面 4.86/5.00），不再与屋面板端面 4.90 共面
	for side in [-1.0, 1.0]:
		var down2 := Vector3(side * cp, -sp, 0.0)
		var nrm2 := Vector3(side * sp, cp, 0.0)
		var mid2: Vector3 = Vector3(0.0, ridge_y, 0.0) + down2 * (slope_len * 0.5)
		for sz in [-1.0, 1.0]:
			var bpos: Vector3 = mid2 + nrm2 * 0.10 + Vector3(0.0, 0.0, sz * (hz + 0.02))
			M.box_rot(root, Vector3(slope_len + 0.08, 0.32, 0.12), bpos, M.C_WOOD_DARK, Vector3(0.0, 0.0, -side * pitch), {"outline": 0.03})
	# ---- 筒瓦：MultiMesh ----
	var tile_data: Dictionary = _roof_tile_data(C)
	var tile_mesh: CylinderMesh = tile_data["mesh"]
	var tile_mat: ShaderMaterial = M.toon_material(M.C_TERRACOTTA, {"vertex_color": true, "bands": 3.0, "soft": 0.45, "rim": 0.08})
	M.multis(root, "RoofTiles", tile_mesh, tile_data["xforms"], tile_data["colors"], tile_mat)
	# 檐口椽尾（MultiMesh）
	var raf_mesh := BoxMesh.new()
	raf_mesh.size = Vector3(1.05, 0.13, 0.15)
	var rxf: Array = []
	var raf_mat: ShaderMaterial = M.toon_material(M.C_WOOD_DARK, {"bands": 4.0, "soft": 0.5, "rim": 0.10})
	for side in [-1.0, 1.0]:
		var down := Vector3(side * cp, -sp, 0.0)
		var nrm := Vector3(side * sp, cp, 0.0)
		var rbasis := Basis(down, nrm, Vector3(0.0, 0.0, side))
		var base: Vector3 = Vector3(0.0, ridge_y, 0.0) + down * (slope_len - 0.22) - nrm * 0.24
		var rn: int = int(roof_z / 0.62) + 1
		var rspan: float = (float(rn) - 1.0) * 0.62
		for i in range(rn):
			var zz: float = -rspan * 0.5 + float(i) * 0.62
			rxf.append(Transform3D(rbasis, base + Vector3(0.0, 0.0, zz)))
	M.multis(root, "RoofRafters", raf_mesh, rxf, [], raf_mat)

## 脊瓦 MultiMesh 数据（网格/实例变换/逐实例颜色）：_roof 与 tools/probe_cottage6.gd 共用同一份，
## 避免探针复制公式导致"验证的几何"和"渲染的几何"漂移。
static func _roof_cap_data(C: Dictionary) -> Dictionary:
	var ridge_y: float = C["ridge_y"]
	var roof_z: float = C["roof_z"]
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = 0.22
	cap_mesh.bottom_radius = 0.22
	cap_mesh.height = 0.62
	cap_mesh.radial_segments = 6
	var cap_basis := Basis(Vector3(1.0, 0.0, 0.0), PI * 0.5)
	var cap_n: int = int(roof_z / 0.56) + 1
	var cap_span: float = (float(cap_n) - 1.0) * 0.56
	var xforms: Array = []
	var colors: Array = []
	for i in range(cap_n):
		var zz: float = -cap_span * 0.5 + float(i) * 0.56
		xforms.append(Transform3D(cap_basis, Vector3(0.0, ridge_y + 0.10, zz)))
		var t: float = M.noise01(float(i) * 0.71, 1.31)
		var mm: float = 0.86 + t * 0.22
		colors.append(Color(mm, mm * 0.96, mm * 0.92, 1.0))
	return {"mesh": cap_mesh, "xforms": xforms, "colors": colors}

## 筒瓦 MultiMesh 数据：行/列步长、奇偶行交错、檐口/烟囱避让全部在此，_roof 直接取用。
## 关键：筒瓦圆柱轴沿坡向（down），局部 -Z 指向屋面外法线 nrm，所以"瓦面顶母线"在实例中心
## 的 nrm 方向偏移 r（不是半径的竖直投影）——探针用同一 mesh/xform 复算命中点。
static func _roof_tile_data(C: Dictionary) -> Dictionary:
	var ridge_y: float = C["ridge_y"]
	var slope_len: float = C["slope_len"]
	var roof_z: float = C["roof_z"]
	var cp: float = C["cp"]
	var sp: float = C["sp"]
	var hz: float = roof_z * 0.5
	var chim_x: float = C["ch_x"]
	var chim_z: float = C["ch_z"]
	var tile_mesh := CylinderMesh.new()
	tile_mesh.top_radius = 0.135
	tile_mesh.bottom_radius = 0.165
	tile_mesh.height = 0.52
	tile_mesh.radial_segments = 6
	var xforms: Array = []
	var colors: Array = []
	var row_step: float = 0.36
	var col_step: float = 0.315
	var cols: int = int((roof_z - 0.30) / col_step)
	for side in [-1.0, 1.0]:
		var down := Vector3(side * cp, -sp, 0.0)
		var nrm := Vector3(side * sp, cp, 0.0)
		var xax := Vector3(0.0, 0.0, -side)
		var tbasis := Basis(xax, down, xax.cross(down))
		var rows: int = int((slope_len - 0.35) / row_step)
		var zspan: float = (float(cols) - 1.0) * col_step
		for r in range(rows):
			var s: float = 0.30 + float(r) * row_step
			for cix in range(cols):
				var zz: float = -zspan * 0.5 + float(cix) * col_step + (0.1575 if r % 2 == 1 else 0.0)
				if absf(zz) > hz - 0.16:
					continue
				var pos: Vector3 = Vector3(side * cp * s, ridge_y - sp * s, 0.0) + nrm * 0.10 + Vector3(0.0, 0.0, zz)
				if absf(pos.x - chim_x) < 0.88 and absf(zz - chim_z) < 0.78:
					continue
				xforms.append(Transform3D(tbasis, pos))
				var t2: float = M.noise01(float(r) * 1.7 + float(side) * 2.3, float(cix) * 0.61)
				var mm2: float = 0.90 + t2 * 0.18
				colors.append(Color(mm2 * 1.02, mm2 * 0.97, mm2 * 0.92, 1.0))
	return {"mesh": tile_mesh, "xforms": xforms, "colors": colors}

## 前山墙：带真实矩形洞口的墙体网格（前后面 + 洞口侧壁），用于阁楼落地玻璃窗。
static func _front_gable(root: Node3D, C: Dictionary) -> void:
	var hw: float = C["hw"]
	var rh: float = C["rh"]
	var wall_t: float = C["wall_t"]
	var roof_base: float = C["roof_base"]
	var hd: float = C["hd"]
	var hole_hw: float = C["attic_hw"]
	var hole_top: float = C["attic_top"] - roof_base
	var zf: float = wall_t * 0.5
	var zb: float = -wall_t * 0.5
	var sy: float = rh * (1.0 - hole_hw / hw)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 前面 (+Z)
	_st_tri(st, Vector3(-hw, 0.0, zf), Vector3(-hole_hw, 0.0, zf), Vector3(-hole_hw, sy, zf))
	_st_tri(st, Vector3(hole_hw, 0.0, zf), Vector3(hw, 0.0, zf), Vector3(hole_hw, sy, zf))
	var pa := Vector3(-hole_hw, hole_top, zf)
	var pb := Vector3(hole_hw, hole_top, zf)
	var pc := Vector3(hole_hw, sy, zf)
	var pd := Vector3(0.0, rh, zf)
	var pe := Vector3(-hole_hw, sy, zf)
	_st_tri(st, pa, pb, pc)
	_st_tri(st, pa, pc, pd)
	_st_tri(st, pa, pd, pe)
	# 背面 (-Z)
	_st_tri(st, Vector3(-hw, 0.0, zb), Vector3(-hole_hw, sy, zb), Vector3(-hole_hw, 0.0, zb))
	_st_tri(st, Vector3(hole_hw, 0.0, zb), Vector3(hole_hw, sy, zb), Vector3(hw, 0.0, zb))
	var qa := Vector3(-hole_hw, hole_top, zb)
	var qb := Vector3(hole_hw, hole_top, zb)
	var qc := Vector3(hole_hw, sy, zb)
	var qd := Vector3(0.0, rh, zb)
	var qe := Vector3(-hole_hw, sy, zb)
	_st_tri(st, qa, qc, qb)
	_st_tri(st, qa, qd, qc)
	_st_tri(st, qa, qe, qd)
	# 洞口侧壁（左右 + 顶）
	_st_quad(st, Vector3(-hole_hw, 0.0, zf), Vector3(-hole_hw, 0.0, zb), Vector3(-hole_hw, hole_top, zb), Vector3(-hole_hw, hole_top, zf))
	_st_quad(st, Vector3(hole_hw, 0.0, zf), Vector3(hole_hw, hole_top, zf), Vector3(hole_hw, hole_top, zb), Vector3(hole_hw, 0.0, zb))
	_st_quad(st, Vector3(-hole_hw, hole_top, zf), Vector3(-hole_hw, hole_top, zb), Vector3(hole_hw, hole_top, zb), Vector3(hole_hw, hole_top, zf))
	var mi := MeshInstance3D.new()
	mi.name = "FrontGable"
	mi.mesh = st.commit()
	mi.material_override = M.toon_material(M.C_WALL, {"bands": 4.0, "soft": 0.60, "rim": 0.08})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0.0, roof_base, hd - wall_t * 0.5)
	root.add_child(mi)

static func _st_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n: Vector3 = (b - a).cross(c - a).normalized()
	st.set_normal(n)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)

static func _st_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_st_tri(st, a, b, c)
	_st_tri(st, a, c, d)

static func _st_tri_n(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	# 显式法线版本：Godot 以顺时针为正面，故这里让 cross(b-a,c-a) 与目标法线相反（从正面看为顺时针），
	# 同时把外法线写入顶点，保证 cull_back 可见、toon 光照与 outline 外扩壳方向正确。
	if (b - a).cross(c - a).dot(n) > 0.0:
		var tmp: Vector3 = b
		b = c
		c = tmp
	for p in [a, b, c]:
		st.set_normal(n)
		st.set_uv(Vector2(p.x * 0.5 + 0.5, p.y * 0.5))
		st.add_vertex(p)

static func _st_quad_n(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	_st_tri_n(st, a, b, c, n)
	_st_tri_n(st, a, c, d, n)

# ============================================================
# 5.5) 阁楼落地玻璃窗：真实洞口（前墙 5.70..6.15 + 山墙 6.15..8.30）+ 双层玻璃 + 3x3 窗棂
# ============================================================
static func _attic_window(root: Node3D, C: Dictionary) -> void:
	var hd: float = C["hd"]
	var wt: float = C["wall_t"]
	var zf: float = hd - wt * 0.5
	var y0: float = C["attic_floor"]      # 5.70
	var y1: float = C["attic_top"]        # 8.30
	var hwid: float = C["attic_hw"]       # 1.60
	var cy: float = (y0 + y1) * 0.5       # 7.00
	var win := Node3D.new()
	win.name = "AtticWindow"
	root.add_child(win)
	win.set_meta("width", hwid * 2.0)
	win.set_meta("height", y1 - y0)
	win.set_meta("center", Vector3(0.0, cy, hd))
	# ---- 外侧窗套（外凸 0.07：外表面 4.27）----
	var fx: float = hwid + 0.03
	var fz: float = zf + 0.10             # 3.97..4.27
	var vh: float = (y1 - y0) + 0.30      # 5.60..8.35
	M.box(win, Vector3(0.14, vh, 0.30), Vector3(-fx, 6.975, fz), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
	M.box(win, Vector3(0.14, vh, 0.30), Vector3(fx, 6.975, fz), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
	M.box(win, Vector3(3.32, 0.10, 0.26), Vector3(0.0, y1 + 0.05, fz), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
	M.box(win, Vector3(3.52, 0.14, 0.44), Vector3(0.0, y0 - 0.05, zf + 0.06), M.C_WOOD, 0.0, {"outline": 0.02})
	# ---- 内侧窗套（凸入室内 0.05：外表面 3.79）----
	var iz: float = zf - 0.11             # 3.79..4.03
	M.box(win, Vector3(0.12, 2.63, 0.24), Vector3(-fx, 7.015, iz), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
	M.box(win, Vector3(0.12, 2.63, 0.24), Vector3(fx, 7.015, iz), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
	M.box(win, Vector3(3.28, 0.10, 0.20), Vector3(0.0, 8.33, iz), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
	# ---- 玻璃：外层主玻璃（共享发光材质）+ 内层更透的玻璃，形成双层玻璃层次 ----
	var outer := MeshInstance3D.new()
	var ob := BoxMesh.new()
	ob.size = Vector3(3.30, 2.70, 0.02)
	outer.mesh = ob
	outer.material_override = C["attic_outer_glass"]
	outer.position = Vector3(0.0, cy, zf + 0.04)   # z = 4.06
	outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	win.add_child(outer)
	var inner := MeshInstance3D.new()
	var ib := BoxMesh.new()
	ib.size = Vector3(3.24, 2.62, 0.02)
	inner.mesh = ib
	inner.material_override = C["attic_inner_glass"]
	inner.position = Vector3(0.0, cy, zf - 0.03)   # z = 3.99
	inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	win.add_child(inner)
	# ---- 3x3 窗棂（竖 2 / 横 2），位于外层玻璃前方 ----
	for sx in [-1.0, 1.0]:
		M.box(win, Vector3(0.07, (y1 - y0) - 0.10, 0.10), Vector3(sx * hwid / 3.0, cy, zf + 0.11), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
	for ky in [1, 2]:
		var yy: float = y0 + (y1 - y0) * float(ky) / 3.0
		M.box(win, Vector3((hwid * 2.0) - 0.10, 0.07, 0.06), Vector3(0.0, yy, zf + 0.11), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
	# Phase6：删除窗外 2.10m 的 ADD 光晕（夜间会糊成光球、挡住室内家具/地板）。阁楼照明改由
	# _context 里的两盏室内暖灯（light_sources）承担，窗外不再有独立光球；普通窗 halo 保持不变。
	C["attic_window_world"] = _world(root, Vector3(0.0, cy, hd + 0.02))

# ============================================================
# 6) 石烟囱（穿过坡面，带沿法线抬起的泛水收口与压顶）
# ============================================================
static func _chimney(root: Node3D, C: Dictionary) -> void:
	var ridge_y: float = C["ridge_y"]
	var pitch: float = C["pitch"]
	var sp: float = C["sp"]
	var cp: float = C["cp"]
	var chx: float = C["ch_x"]
	var chz: float = C["ch_z"]
	var top: float = C["ch_top"]
	var roof_y: float = ridge_y - absf(chx) * tan(pitch)
	M.box(root, Vector3(1.02, top - 1.00, 0.94), Vector3(chx, 1.00 + (top - 1.00) * 0.5, chz), M.C_STONE, 0.0, {"outline": 0.04})
	for yy in [2.55, 5.05, 7.55]:
		M.box(root, Vector3(1.14, 0.20, 1.06), Vector3(chx, yy, chz), M.C_STONE_DARK, 0.0, {"outline": 0.02})
	# 屋面交接：石泛水板（沿屋面法线抬起 0.03，厚 0.16：埋入 0.05 / 外露 0.11，不与屋面共面）
	M.box_rot(root, Vector3(2.20, 0.16, 1.70), Vector3(chx - sp * 0.03, roof_y + cp * 0.03, chz), M.C_STONE_DARK, Vector3(0.0, 0.0, pitch), {"outline": 0.02})
	M.box(root, Vector3(1.40, 0.34, 1.32), Vector3(chx, roof_y + 0.36, chz), M.C_STONE, 0.0, {"outline": 0.03})
	# 压顶
	M.box(root, Vector3(1.36, 0.18, 1.26), Vector3(chx, top - 0.10, chz), M.C_STONE_DARK, 0.0, {"outline": 0.03})
	M.box(root, Vector3(1.16, 0.16, 1.08), Vector3(chx, top + 0.06, chz), M.C_STONE, 0.0, {"outline": 0.02})
	M.box(root, Vector3(0.54, 0.22, 0.50), Vector3(chx, top + 0.24, chz), M.C_STONE_DARK, 0.0, {"outline": 0.02})

# ============================================================
# 7) 门廊：木平台 / 栏杆（中央留 3.76m 台阶口）/ 双坡雨棚 / 吊灯 / 长椅 / 花箱
# ============================================================
static func _porch(root: Node3D, C: Dictionary) -> void:
	var fy: float = C["fy"]
	var hd: float = C["hd"]
	var deck_top: float = C["deck_top"]
	M.box(root, Vector3(8.40, 0.24, 3.00), Vector3(0.0, deck_top - 0.12, hd + 1.50), M.C_WOOD, 0.0, {"outline": 0.045})
	var plank_mesh := BoxMesh.new()
	plank_mesh.size = Vector3(8.30, 0.05, 0.40)
	var pxf: Array = []
	var pcol: Array = []
	for i in range(7):
		var zz: float = hd + 0.23 + float(i) * 0.425
		pxf.append(Transform3D(Basis.IDENTITY, Vector3(0.0, deck_top + 0.025, zz)))
		var t: float = M.noise01(float(i) * 1.3, 0.7)
		var mm: float = 0.86 + t * 0.24
		pcol.append(Color(mm, mm * 0.97, mm * 0.92, 1.0))
	M.multis(root, "PorchPlanks", plank_mesh, pxf, pcol, M.toon_material(Color("8b6844"), {"vertex_color": true, "bands": 4.0, "soft": 0.55}))
	for sx in [-1.0, 1.0]:
		for zz2 in [4.70, 6.80]:
			M.box(root, Vector3(0.32, 1.60, 0.32), Vector3(sx * 3.70, -0.35, zz2), M.C_STONE_DARK, 0.0, {"outline": 0.02})
	# 栏杆立柱（前缘内柱外移到 ±1.88，给 3.76m 宽台阶让出通道）
	for sz in [4.60, 6.95]:
		for sx in [-1.0, 1.0]:
			M.box(root, Vector3(0.12, 0.95, 0.12), Vector3(sx * 4.12, deck_top + 0.475, sz), M.C_WOOD_DARK, 0.0, {"outline": 0.025})
	for sx in [-1.0, 1.0]:
		M.box(root, Vector3(0.12, 0.95, 0.12), Vector3(sx * 1.88, deck_top + 0.475, 6.95), M.C_WOOD_DARK, 0.0, {"outline": 0.025})
	# 扶手
	for sx in [-1.0, 1.0]:
		M.box(root, Vector3(0.10, 0.09, 2.60), Vector3(sx * 4.12, deck_top + 0.895, 5.78), M.C_WOOD, 0.0, {"outline": 0.02})
		M.box(root, Vector3(2.24, 0.09, 0.10), Vector3(sx * 3.00, deck_top + 0.90, 6.95), M.C_WOOD, 0.0, {"outline": 0.02})
	# 栏板条（MultiMesh）
	var bal_mesh := BoxMesh.new()
	bal_mesh.size = Vector3(0.06, 0.66, 0.06)
	var bxf: Array = []
	var bal_mat: ShaderMaterial = M.toon_material(M.C_WOOD_DARK, {"bands": 3.0, "soft": 0.5})
	for sx in [-1.0, 1.0]:
		for i in range(6):
			var zz3: float = 4.85 + float(i) * 0.36
			bxf.append(Transform3D(Basis.IDENTITY, Vector3(sx * 4.12, deck_top + 0.46, zz3)))
	for sx in [-1.0, 1.0]:
		for i in range(6):
			var xx: float = sx * (2.02 + float(i) * 0.36)
			bxf.append(Transform3D(Basis.IDENTITY, Vector3(xx, deck_top + 0.46, 6.95)))
	M.multis(root, "PorchBalusters", bal_mesh, bxf, [], bal_mat)
	# ---- 双坡雨棚 ----
	var p2: float = atan(0.90 / 4.30)
	var c2: float = cos(p2)
	var s2: float = sin(p2)
	var clen: float = sqrt(4.30 * 4.30 + 0.90 * 0.90)
	var ridge2: float = 4.60
	var cz: float = hd + 1.56
	var cdepth: float = 3.20
	var tile_mesh := CylinderMesh.new()
	tile_mesh.top_radius = 0.135
	tile_mesh.bottom_radius = 0.165
	tile_mesh.height = 0.52
	tile_mesh.radial_segments = 6
	var tile_mat: ShaderMaterial = M.toon_material(M.C_TERRACOTTA, {"vertex_color": true, "bands": 3.0, "soft": 0.45, "rim": 0.08})
	for side in [-1.0, 1.0]:
		var down := Vector3(side * c2, -s2, 0.0)
		var nrm := Vector3(side * s2, c2, 0.0)
		var mid: Vector3 = Vector3(0.0, ridge2, 0.0) + down * (clen * 0.5)
		M.box_rot(root, Vector3(clen, 0.12, cdepth), mid - nrm * 0.06, M.C_WOOD, Vector3(0.0, 0.0, -side * p2), {"outline": 0.0})
	M.cyl_rot(root, 0.10, 0.10, cdepth + 0.10, Vector3(0.0, ridge2 + 0.04, cz), M.C_WOOD_DARK, Vector3(PI * 0.5, 0.0, 0.0), {"outline": 0.02})
	# 前山墙封板：z 中心 7.33（面 7.26/7.40），把雨棚板端面 7.36 包在内部，避免共面
	M.prism(root, 8.60, 0.90, 0.14, Vector3(0.0, 3.70, cz + cdepth * 0.5 - 0.03), M.C_WALL, 0.0, {"bands": 4.0, "soft": 0.60})
	for side in [-1.0, 1.0]:
		M.box(root, Vector3(0.10, 0.22, cdepth + 0.04), Vector3(side * 4.28, 3.63, cz), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
	for sx in [-1.0, 1.0]:
		M.cyl(root, 0.13, 0.17, 3.36, Vector3(sx * 3.55, deck_top + 1.68, 6.95), M.C_WOOD_DARK, 0.0, {"outline": 0.03})
	M.box(root, Vector3(7.10, 0.16, 0.14), Vector3(0.0, deck_top + 3.30, 6.95), M.C_WOOD_DARK, 0.0, {"outline": 0.03})
	for sx in [-1.0, 1.0]:
		M.box_rot(root, Vector3(0.90, 0.14, 0.12), Vector3(sx * 3.05, deck_top + 3.00, 6.95), M.C_WOOD_DARK, Vector3(0.0, 0.0, sx * 0.70), {"outline": 0.02})
	# 雨棚瓦（第二个 MultiMesh）
	var ctile_xf: Array = []
	var ctile_col: Array = []
	var crow_step: float = 0.34
	var ccol_step: float = 0.30
	for side in [-1.0, 1.0]:
		var down := Vector3(side * c2, -s2, 0.0)
		var nrm := Vector3(side * s2, c2, 0.0)
		var xax := Vector3(0.0, 0.0, -side)
		var cbasis := Basis(xax, down, xax.cross(down))
		var rows: int = int((clen - 0.30) / crow_step)
		var cols: int = int(cdepth / ccol_step)
		var cspan: float = (float(cols) - 1.0) * ccol_step
		for r in range(rows):
			var s: float = 0.20 + float(r) * crow_step
			for cix in range(cols):
				var zz: float = cz - cspan * 0.5 + float(cix) * ccol_step + (0.15 if r % 2 == 1 else 0.0)
				if absf(zz - cz) > cdepth * 0.5 - 0.20:
					continue
				var pos: Vector3 = Vector3(side * c2 * s, ridge2 - s2 * s, 0.0) + nrm * 0.08 + Vector3(0.0, 0.0, zz)
				ctile_xf.append(Transform3D(cbasis, pos))
				var t3: float = M.noise01(float(r) * 1.1 + float(side) * 2.7, float(cix) * 0.53)
				var mm3: float = 0.90 + t3 * 0.18
				ctile_col.append(Color(mm3 * 1.02, mm3 * 0.97, mm3 * 0.92, 1.0))
	M.multis(root, "PorchTiles", tile_mesh, ctile_xf, ctile_col, tile_mat)
	# ---- 门廊对称吊灯（左右镜像；lantern_mat / lantern_halos 由 main 调光）----
	var lm: ShaderMaterial = C["lantern_mat"]
	var lantern_halos: Array = []
	for lpos_v in [C["lantern_pos"], C["lantern_pos_right"]]:
		var lpos: Vector3 = lpos_v
		M.cyl(root, 0.018, 0.018, 0.52, Vector3(lpos.x, lpos.y + 0.46, lpos.z), M.C_WOOD_DARK, 0.0, {})
		var body := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(0.30, 0.40, 0.30)
		body.mesh = bb
		body.material_override = lm
		body.position = lpos
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(body)
		M.box(root, Vector3(0.38, 0.06, 0.38), Vector3(lpos.x, lpos.y + 0.24, lpos.z), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
		M.box(root, Vector3(0.36, 0.05, 0.36), Vector3(lpos.x, lpos.y - 0.23, lpos.z), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
		# 原 2.10 的 halo 近景会成直径 1m+ 光球；1.10 与路灯 1.18 同级
		lantern_halos.append(M.halo(root, lpos, 1.10, Color(2.4, 1.6, 0.8, 1.0)))
	C["lantern_halos"] = lantern_halos
	C["lantern_halo"] = lantern_halos[0]
	# ---- 长椅 ----
	M.box(root, Vector3(0.52, 0.10, 1.70), Vector3(3.38, deck_top + 0.40, 5.95), M.C_WOOD, 0.0, {"outline": 0.03})
	M.box(root, Vector3(0.10, 0.62, 1.70), Vector3(3.62, deck_top + 0.72, 5.95), M.C_WOOD, 0.0, {"outline": 0.025})
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			M.box(root, Vector3(0.08, 0.40, 0.08), Vector3(3.38 + sx * 0.20, deck_top + 0.20, 5.95 + sz * 0.74), M.C_WOOD_DARK, 0.0, {})
	# ---- 前窗下花箱 + 花 ----
	var fl_mesh := SphereMesh.new()
	fl_mesh.radius = 0.085
	fl_mesh.height = 0.17
	fl_mesh.radial_segments = 6
	fl_mesh.rings = 4
	var fxf: Array = []
	var fcol: Array = []
	var flower_cols: Array = [Color("e8dfcf"), Color("e0b45a"), Color("cf8f99"), Color("f3ead6")]
	for sx in [-1.0, 1.0]:
		M.box(root, Vector3(1.45, 0.26, 0.30), Vector3(sx * 3.45, fy + 1.20, hd + 0.10), M.C_WOOD, 0.0, {"outline": 0.02})
		for k in range(4):
			var fx: float = sx * 3.45 - 0.51 + float(k) * 0.34
			fxf.append(Transform3D(Basis.IDENTITY, Vector3(fx, fy + 1.44, hd + 0.10)))
			fcol.append(flower_cols[k % 4])
	M.multis(root, "PorchFlowers", fl_mesh, fxf, fcol, M.toon_material(Color.WHITE, {"vertex_color": true, "bands": 4.0, "soft": 0.60}))
	# ---- 门边扫帚 + 小木牌 ----
	M.cyl_rot(root, 0.022, 0.026, 1.24, Vector3(1.95, deck_top + 0.62, 4.52), M.C_WOOD, Vector3(0.16, 0.0, 0.22), {})
	M.box(root, Vector3(0.10, 0.26, 0.16), Vector3(2.08, deck_top + 0.13, 4.60), Color("c9a35f"), 0.0, {})
	M.box(root, Vector3(0.46, 0.30, 0.10), Vector3(2.55, fy + 2.55, hd + 0.05), M.C_WOOD_LIGHT, 0.0, {"outline": 0.02})
	M.box(root, Vector3(0.34, 0.04, 0.07), Vector3(2.55, fy + 2.72, hd + 0.07), M.C_WOOD_DARK, 0.0, {})

# ============================================================
# 8b) P7-V3 楼梯：L 形（入口右侧沿右墙 15 级直梯 → 平台 → 靠后墙 12 级横梯 → 阁楼洞口）
#     层高 5.15 = 27 级 × 0.190741；踏面 0.245；Flight A 宽 1.10 / Flight B 宽 1.17
# ============================================================
static func _stairs(root: Node3D, C: Dictionary) -> void:
	var fy: float = C["fy"]
	var attic_floor: float = C["attic_floor"]
	var in_top: float = fy + 3.60
	var h: float = (attic_floor - fy) / 27.0
	var tr: float = 0.245
	var st := Node3D.new()
	st.name = "Staircase"
	st.set_meta("risers", 27)
	st.set_meta("rise", h)
	st.set_meta("tread", tr)
	st.set_meta("hole_r1", C["stair_hole_r1"])
	st.set_meta("hole_r2", C["stair_hole_r2"])
	root.add_child(st)
	var wood: Color = M.C_WOOD
	var wood_l: Color = M.C_WOOD_LIGHT
	var wood_d: Color = M.C_WOOD_DARK
	var wo := {"bands": 4.0, "soft": 0.55, "rim": 0.12, "outline": 0.02}
	# ---------- Flight A：14 级踏面 + 第 15 级踢面（平台前缘）----------
	var ax0: float = 3.70
	var ax1: float = 4.80
	var axc: float = (ax0 + ax1) * 0.5
	var az0: float = 0.55
	var a_run: float = 14.0 * tr
	var a_rise: float = 14.0 * h
	var a_ang: float = atan2(a_rise, a_run)
	var a_len: float = sqrt(a_run * a_run + a_rise * a_rise)
	var a_nrm := Vector3(0.0, cos(a_ang), sin(a_ang))
	for i in range(1, 15):
		var top: float = fy + float(i) * h
		var zris: float = az0 - float(i - 1) * tr
		M.box(st, Vector3(ax1 - ax0, 0.06, tr + 0.05), Vector3(axc, top - 0.03, zris - tr * 0.5 + 0.02), wood_l, 0.0, wo)
		M.box(st, Vector3(ax1 - ax0, h, 0.035), Vector3(axc, top - h * 0.5 - 0.03, zris + 0.0175), wood_d, 0.0, {"outline": 0.0})
	var az_end: float = az0 - a_run
	var ply: float = fy + 15.0 * h
	M.box(st, Vector3(ax1 - ax0, h, 0.035), Vector3(axc, ply - h * 0.5 - 0.03, az_end + 0.0175), wood_d, 0.0, {"outline": 0.0})
	# 梯梁（两侧）+ 中部支撑柱
	var a_mid := Vector3(0.0, fy + a_rise * 0.5, az0 - a_run * 0.5) - a_nrm * 0.17
	for sx in [ax0 + 0.03, ax1 - 0.03]:
		M.box_rot(st, Vector3(0.06, 0.32, a_len), Vector3(sx, a_mid.y, a_mid.z), wood_d, Vector3(a_ang, 0.0, 0.0), {"outline": 0.02})
	var sup_z: float = -1.45
	var sup_top: float = fy + (az0 - sup_z) / a_run * a_rise - 0.12
	M.box(st, Vector3(0.10, sup_top - fy, 0.10), Vector3(ax0 + 0.05, (sup_top + fy) * 0.5, sup_z), wood_d, 0.0, {"outline": 0.02})
	# 内侧扶手 + 立柱式栏杆
	var a_rail_y: float = fy + 0.90 + a_rise * 0.5
	M.box_rot(st, Vector3(0.075, 0.06, a_len - 0.16), Vector3(ax0 + 0.05, a_rail_y, az0 - a_run * 0.5), wood, Vector3(a_ang, 0.0, 0.0), {"outline": 0.02})
	for i in range(1, 15):
		var zc: float = az0 - (float(i) - 0.5) * tr
		var ytop: float = fy + 0.90 + (az0 - zc) / a_run * a_rise - 0.03
		var ybase: float = fy + float(i) * h
		M.box(st, Vector3(0.035, ytop - ybase, 0.035), Vector3(ax0 + 0.05, (ytop + ybase) * 0.5, zc), wood, 0.0, {})
	M.box(st, Vector3(0.10, 1.08, 0.10), Vector3(ax0 + 0.05, fy + 0.54, az0 + 0.09), wood_d, 0.0, {"outline": 0.02})
	M.box(st, Vector3(0.14, 0.05, 0.14), Vector3(ax0 + 0.05, fy + 1.10, az0 + 0.09), wood_d, 0.0, {})
	# ---------- 平台（顶 3.4111；x 3.69..4.82，z -3.83..-2.88）----------
	var px0: float = 3.69
	var px1: float = 4.82
	var pz0: float = -3.83
	var pz1: float = az_end
	var pcx: float = (px0 + px1) * 0.5
	M.box(st, Vector3(px1 - px0, 0.10, pz1 - pz0), Vector3(pcx, ply - 0.05, (pz0 + pz1) * 0.5), wood_l, 0.0, wo)
	M.box(st, Vector3(px1 - px0 + 0.02, 0.14, 0.06), Vector3(pcx, ply - 0.09, pz1 - 0.03), wood_d, 0.0, {"outline": 0.02})
	for pz in [pz0 + 0.20, pz1 - 0.20]:
		M.box(st, Vector3(0.12, ply - 0.10 - fy, 0.12), Vector3(px0 + 0.16, (ply - 0.10 + fy) * 0.5, pz), wood_d, 0.0, {"outline": 0.02})
	# 平台临空侧（+Z 边）不设栏杆：此处正是 Flight A 上来后的到达口（P7-V3 修正），
	# 只在 Flight A 内侧扶手末端加一根落地 newel 柱收头（扶手顶端 z≈-2.815，柱心 z=-2.87 与之相切）。
	var newel_z: float = -2.87
	var newel_y0: float = ply - 0.02
	var newel_h: float = 0.80
	M.box(st, Vector3(0.11, newel_h, 0.11), Vector3(ax0 + 0.05, newel_y0 + newel_h * 0.5, newel_z), wood_d, 0.0, {"outline": 0.025})
	M.box(st, Vector3(0.15, 0.06, 0.15), Vector3(ax0 + 0.05, newel_y0 + newel_h + 0.03, newel_z), wood_d, 0.0, {})
	# ---------- Flight B：平台向 -X 上行 11 级踏面 + 第 27 级接阁楼地面 ----------
	var bx0: float = 3.70
	var bx_end: float = 1.005
	var bz0: float = -3.80
	var bz1: float = -2.63
	var bzc: float = (bz0 + bz1) * 0.5
	var bwd: float = bz1 - bz0
	for j in range(16, 27):
		var top2: float = fy + float(j) * h
		var xris: float = bx0 - float(j - 16) * tr
		M.box(st, Vector3(tr + 0.05, 0.06, bwd), Vector3(xris - tr * 0.5 - 0.02, top2 - 0.03, bzc), wood_l, 0.0, wo)
		M.box(st, Vector3(0.035, h, bwd), Vector3(xris + 0.0175, top2 - h * 0.5 - 0.03, bzc), wood_d, 0.0, {"outline": 0.0})
	M.box(st, Vector3(0.035, h, bwd), Vector3(bx_end + 0.0175, attic_floor - h * 0.5, bzc), wood_d, 0.0, {"outline": 0.0})
	var b_run: float = bx0 - bx_end
	var b_rise: float = attic_floor - ply
	var b_ang: float = atan2(b_rise, b_run)
	var b_len: float = sqrt(b_run * b_run + b_rise * b_rise)
	var b_nrm := Vector3(sin(b_ang), cos(b_ang), 0.0)
	var b_mid := Vector3((bx0 + bx_end) * 0.5, (ply + attic_floor) * 0.5, 0.0) - b_nrm * 0.17
	for bz in [bz0 + 0.03, bz1 - 0.03]:
		M.box_rot(st, Vector3(b_len, 0.32, 0.06), Vector3(b_mid.x, b_mid.y, bz), wood_d, Vector3(0.0, 0.0, -b_ang), {"outline": 0.02})
	# 靠后墙壁装扶手 + 支架
	M.box_rot(st, Vector3(b_len - 0.20, 0.06, 0.07), Vector3((bx0 + bx_end) * 0.5, (ply + attic_floor) * 0.5 + 0.90, bz0 + 0.02), wood, Vector3(0.0, 0.0, -b_ang), {"outline": 0.02})
	for j in [17, 20, 23, 26]:
		var xb: float = bx0 - float(j - 16) * tr
		var yb: float = ply + 0.90 + (bx0 - xb) / b_run * b_rise
		M.box(st, Vector3(0.05, 0.05, 0.09), Vector3(xb, yb - 0.10, bz0 + 0.06), wood_d, 0.0, {})
	# ---------- 楼梯井井壁：封住天花板(4.25)与阁楼地板(5.63)之间的隐藏空腔 ----------
	var cav_lo: float = in_top + 0.10
	var cav_hi: float = attic_floor - 0.07
	var cav_h: float = cav_hi - cav_lo
	var cav_y: float = (cav_lo + cav_hi) * 0.5
	var wcol: Color = M.C_WALL
	var wopts := {"bands": 4.0, "soft": 0.60, "rim": 0.10}
	M.box(st, Vector3(2.645, cav_h, 0.08), Vector3(2.3275, cav_y, -2.60), wcol, 0.0, wopts)
	M.box(st, Vector3(0.08, cav_h, 2.05), Vector3(3.65, cav_y, -1.575), wcol, 0.0, wopts)
	M.box(st, Vector3(1.17, cav_h, 0.08), Vector3(4.235, cav_y, -0.55), wcol, 0.0, wopts)
	M.box(st, Vector3(0.08, cav_h, 3.28), Vector3(4.82, cav_y, -2.19), wcol, 0.0, wopts)
	# x=1.005 侧：楼梯在此穿过，井壁只做到楼梯下皮以下，上方由踏步/收边遮挡
	var p1_hi: float = 5.42
	M.box(st, Vector3(0.08, p1_hi - cav_lo, 1.23), Vector3(1.005, (p1_hi + cav_lo) * 0.5, -3.215), wcol, 0.0, wopts)
	# 井壁上下木质收边
	for yy in [cav_lo + 0.03, cav_hi - 0.03]:
		M.box(st, Vector3(2.645, 0.06, 0.12), Vector3(2.3275, yy, -2.60), wood_d, 0.0, {"outline": 0.02})
		M.box(st, Vector3(0.12, 0.06, 2.05), Vector3(3.65, yy, -1.575), wood_d, 0.0, {"outline": 0.02})
		M.box(st, Vector3(1.17, 0.06, 0.12), Vector3(4.235, yy, -0.55), wood_d, 0.0, {"outline": 0.02})
		M.box(st, Vector3(0.12, 0.06, 3.28), Vector3(4.82, yy, -2.19), wood_d, 0.0, {"outline": 0.02})
	M.box(st, Vector3(0.12, 0.06, 1.23), Vector3(1.005, cav_lo + 0.03, -3.215), wood_d, 0.0, {"outline": 0.02})
	# P7-V3.1：楼梯整段静态合批。99 个部件（踏步/踢面/梯梁/扶手/立柱/井壁/收边）按
	# （材质, 顶点属性）合并为 7 个 surface —— 材质对象与 next_pass 描边原样保留，
	# 三角形数与合并前严格相等（tools/probe_batch_merge_p7v31.gd 断言守恒）。
	IsleBatch.merge_static(st)

# ============================================================
# 8) 阁楼室内：真实地板 / 斜顶（椽条+系梁）/ 地毯 / 书桌+椅 / 床 / 衣柜 / 暖灯
# ============================================================
static func _attic_interior(root: Node3D, C: Dictionary) -> void:
	var w: float = C["w"]
	var d: float = C["d"]
	var hd: float = C["hd"]
	var wall_t: float = C["wall_t"]
	var floor_y: float = C["attic_floor"]
	var pitch: float = C["pitch"]
	var cp: float = C["cp"]
	var sp: float = C["sp"]
	var ridge_y: float = C["ridge_y"]
	var slope_len: float = C["slope_len"]
	var roof_z: float = C["roof_z"]
	var fw: float = w - wall_t * 2.0 - 0.08
	var fd: float = d - wall_t * 2.0 - 0.08
	var ia := Node3D.new()
	ia.name = "AtticInterior"
	root.add_child(ia)
	# ---- 地板结构（P7-V3：按 L 形楼梯井切分 4 块；R1 x[3.65,4.82] z[-3.83,-0.55]；R2 x[1.005,3.65] z[-3.83,-2.60]）----
	var slab_mat: Color = Color("5f4733")
	var slab_y: float = floor_y - 0.07
	M.box(root, Vector3(5.935, 0.14, fd), Vector3(-1.9625, slab_y, 0.0), slab_mat, 0.0, {"bands": 4.0})
	M.box(root, Vector3(2.645, 0.14, 6.43), Vector3(2.3275, slab_y, 0.615), slab_mat, 0.0, {"bands": 4.0})
	M.box(root, Vector3(1.17, 0.14, 4.38), Vector3(4.235, slab_y, 1.64), slab_mat, 0.0, {"bands": 4.0})
	M.box(root, Vector3(0.11, 0.14, fd), Vector3(4.875, slab_y, 0.0), slab_mat, 0.0, {"bands": 4.0})
	# ---- 板条：按洞口切分为多段（MultiMesh 缩放实例，保持单 draw call）----
	var fl_mesh := BoxMesh.new()
	fl_mesh.size = Vector3(1.0, 0.02, 1.0)
	var flxf: Array = []
	var flcol: Array = []
	var regions: Array = [
		[-4.93, 1.005, -3.81, 3.81],
		[1.005, 3.65, -2.58, 3.81],
		[3.65, 4.82, -0.53, 3.81],
		[4.82, 4.93, -3.81, 3.81],
	]
	for i in range(21):
		var xx: float = -4.47 + float(i) * 0.447
		var t: float = M.noise01(float(i) * 0.83, 4.7)
		var mm: float = 0.80 + t * 0.30
		var col: Color = Color(mm, mm * 0.96, mm * 0.90, 1.0)
		for rg in regions:
			var x0: float = maxf(xx - 0.21, rg[0])
			var x1: float = minf(xx + 0.21, rg[1])
			if x1 - x0 <= 0.03:
				continue
			var zl: float = float(rg[3]) - float(rg[2])
			flxf.append(Transform3D(Basis.from_scale(Vector3(x1 - x0, 1.0, zl)), Vector3((x0 + x1) * 0.5, floor_y + 0.006, (float(rg[2]) + float(rg[3])) * 0.5)))
			flcol.append(col)
	M.multis(root, "AtticFloor", fl_mesh, flxf, flcol, M.toon_material(Color("8b6a49"), {"vertex_color": true, "bands": 4.0, "soft": 0.55}))
	# ---- 洞口木质收边（顶面齐平，遮住板边与楼梯/井壁之间的缝）----
	M.box(root, Vector3(2.645, 0.07, 0.16), Vector3(2.3275, floor_y - 0.035, -2.60), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
	M.box(root, Vector3(0.16, 0.07, 2.05), Vector3(3.65, floor_y - 0.035, -1.575), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
	M.box(root, Vector3(1.17, 0.07, 0.16), Vector3(4.235, floor_y - 0.035, -0.55), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
	M.box(root, Vector3(0.16, 0.07, 3.28), Vector3(4.82, floor_y - 0.035, -2.19), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
	M.box(root, Vector3(0.16, 0.07, 1.23), Vector3(1.005, floor_y - 0.035, -3.215), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
	# ---- 阁楼栏杆（洞口三边；x=1.005 处为楼梯上口，留通）----
	var rail_h: float = 0.92
	var corners: Array = [Vector2(1.005, -2.60), Vector2(3.65, -2.60), Vector2(3.65, -0.55), Vector2(4.82, -0.55)]
	for cnr in corners:
		M.box(root, Vector3(0.10, rail_h + 0.14, 0.10), Vector3(cnr.x, floor_y + (rail_h + 0.14) * 0.5, cnr.y), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
		M.box(root, Vector3(0.13, 0.05, 0.13), Vector3(cnr.x, floor_y + rail_h + 0.16, cnr.y), M.C_WOOD_DARK, 0.0, {})
	for s in range(3):
		var a: Vector2 = corners[s]
		var b: Vector2 = corners[s + 1]
		var dvec := Vector3(b.x - a.x, 0.0, b.y - a.y)
		var seg_len: float = dvec.length()
		if seg_len < 0.05:
			continue
		var yaw: float = atan2(dvec.x, dvec.z)
		M.box_rot(root, Vector3(0.09, 0.06, seg_len), Vector3((a.x + b.x) * 0.5, floor_y + rail_h, (a.y + b.y) * 0.5), M.C_WOOD, Vector3(0.0, yaw, 0.0), {"outline": 0.02})
		var nb: int = maxi(2, int(seg_len / 0.22))
		for k in range(1, nb):
			var tv: float = float(k) / float(nb)
			M.box(root, Vector3(0.035, rail_h - 0.10, 0.035), Vector3(a.x + (b.x - a.x) * tv, floor_y + (rail_h - 0.10) * 0.5, a.y + (b.y - a.y) * tv), M.C_WOOD, 0.0, {})
	# ---- 斜顶：屋面下皮下方 0.02 的椽条（6 根）+ 2 根水平系梁 ----
	for side in [-1.0, 1.0]:
		var down := Vector3(side * cp, -sp, 0.0)
		var nrm := Vector3(side * sp, cp, 0.0)
		var mid: Vector3 = Vector3(0.0, ridge_y, 0.0) + down * (slope_len * 0.5)
		for zz in [-2.60, 0.0, 2.60]:
			var pos: Vector3 = mid - nrm * (0.16 + 0.02 + 0.07) + Vector3(0.0, 0.0, zz)
			M.box_rot(root, Vector3(slope_len - 1.00, 0.14, 0.14), pos, M.C_WOOD, Vector3(0.0, 0.0, -side * pitch), {"outline": 0.0})
	for zz in [-2.20, 2.20]:
		M.box(root, Vector3(5.90, 0.12, 0.16), Vector3(0.0, 7.35, zz), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
	# ---- P7-V3 阁楼家具：IsleHouseProps 统一库；全部避开楼梯洞口 x[1.005,4.82] z[-3.83,-2.60] ----
	# 睡眠区（左后，-X 侧斜顶下）：床（床头朝 -X）/ 床头柜 / 衣柜（后墙）
	P.build(ia, "bed", Vector3(-3.20, floor_y, -0.80), PI * 0.5, {"quilt": Color("c98e7f")})
	P.build(ia, "nightstand", Vector3(-2.05, floor_y, -1.75), 0.0)
	P.build(ia, "wardrobe", Vector3(-0.20, floor_y, -3.42), 0.0)
	P.build(ia, "bookshelf", Vector3(-1.55, floor_y, -3.52), 0.0)
	# 工作区（前落地窗下）：书桌（正面朝室内）/ 椅 / 桌上台灯
	P.build(ia, "desk", Vector3(0.30, floor_y, 2.80), PI, {"color": M.C_WOOD_LIGHT})
	P.build(ia, "chair", Vector3(0.30, floor_y, 1.90), 0.0, {"cushion": Color("8a6f5a")})
	P.build(ia, "table_lamp", Vector3(0.85, floor_y + 0.76, 2.80), 0.0)
	# 阅读区（右前）：阅读椅 / 边几 + 台灯 / 地毯 / 盆栽
	P.build(ia, "reading_chair", Vector3(2.20, floor_y, 1.55), -PI * 0.5, {"cushion": Color("6f7f6a")})
	P.build(ia, "side_table", Vector3(2.90, floor_y, 0.85), 0.0)
	P.build(ia, "table_lamp", Vector3(2.90, floor_y + 0.55, 0.85), 0.0)
	P.build(ia, "rug", Vector3(0.0, floor_y + 0.004, 0.65), 0.0)
	P.build(ia, "plant_pot", Vector3(3.30, floor_y, 2.95), 0.7)
	# 墙挂画框：原点贴着阁楼后墙内面 z=-3.84（后墙中心 -4.02、厚 0.36），yaw=PI 使其朝 +Z 室内展开
	P.build(ia, "picture_frame", Vector3(-2.55, 7.15, -3.84), PI)
	# 阁楼前窗两侧窗帘（计划 §12：±1.80 前窗；帘杆挂在窗顶 8.22，帘布向下 2.40 到 5.82）
	for sx in [-1.0, 1.0]:
		P.build(ia, "curtain", Vector3(float(sx) * 1.80, 8.22, 3.72), PI,
				{"width": 0.72, "height": 2.40})
	# 第二处光源锚点：跟随书桌台灯（main.gd light_sources 消费）
	C["attic_lamp_world"] = _world(root, Vector3(0.85, 6.75, 2.80))
	var halo2 := M.halo(root, Vector3(0.85, 6.72, 2.80), 1.05, Color(1.9, 1.30, 0.62, 1.0))
	halo2.set_meta("attic_lamp_halo", true)
	# P7-V3.1：阁楼家具逐件在自己的 Prop_<kind>_<seq> 节点内静态合批（材质/描边不变）
	_merge_props_of(ia)
	ia.set_meta("furniture_count", 15)

# ============================================================
# 9) 室内：木地板 / 天花梁 / 木饰 / 壁炉 / 家具 / 吊灯
# ============================================================
static func _interior(root: Node3D, C: Dictionary) -> void:
	var w: float = C["w"]
	var d: float = C["d"]
	var fy: float = C["fy"]
	var hw: float = C["hw"]
	var hd: float = C["hd"]
	var wall_t: float = C["wall_t"]
	var fw: float = w - wall_t * 2.0 - 0.02
	var fd: float = d - wall_t * 2.0 - 0.02
	var in_top: float = fy + 3.60
	M.box(root, Vector3(fw, 0.14, fd), Vector3(0.0, fy - 0.05, 0.0), Color("5f4733"), 0.0, {"bands": 4.0})
	var fl_mesh := BoxMesh.new()
	fl_mesh.size = Vector3(0.40, 0.035, fd - 0.12)
	var flxf: Array = []
	var flcol: Array = []
	for i in range(23):
		var xx: float = -4.62 + float(i) * 0.42
		flxf.append(Transform3D(Basis.IDENTITY, Vector3(xx, fy + 0.02, 0.0)))
		var t: float = M.noise01(float(i) * 0.91, 2.3)
		var mm: float = 0.82 + t * 0.30
		flcol.append(Color(mm, mm * 0.96, mm * 0.90, 1.0))
	M.multis(root, "InteriorFloor", fl_mesh, flxf, flcol, M.toon_material(Color("8b6a49"), {"vertex_color": true, "bands": 4.0, "soft": 0.55, "glow": 0.05}))
	# 天花板：P7-V3 按 L 形楼梯井切分为 4 块（R1 x[3.65,4.82] z[-3.83,-0.55]；R2 x[1.005,3.65] z[-3.83,-2.60]）
	var ccol := Color("d9c7a5")
	var copts := {"bands": 4.0, "soft": 0.60, "glow": 0.04}
	M.box(root, Vector3(5.935, 0.10, fd), Vector3(-1.9625, in_top + 0.05, 0.0), ccol, 0.0, copts)
	M.box(root, Vector3(2.645, 0.10, 6.43), Vector3(2.3275, in_top + 0.05, 0.615), ccol, 0.0, copts)
	M.box(root, Vector3(1.17, 0.10, 4.38), Vector3(4.235, in_top + 0.05, 1.64), ccol, 0.0, copts)
	M.box(root, Vector3(0.11, 0.10, fd), Vector3(4.875, in_top + 0.05, 0.0), ccol, 0.0, copts)
	# 横梁：z=-0.90 / -2.70 在洞口处截断（z=0.90 / 2.70 保留）
	M.box(root, Vector3(8.58, 0.20, 0.22), Vector3(-0.64, in_top - 0.09, -0.90), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
	M.box(root, Vector3(5.935, 0.20, 0.22), Vector3(-1.9625, in_top - 0.09, -2.70), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
	for zz in [0.90, 2.70]:
		M.box(root, Vector3(fw, 0.20, 0.22), Vector3(0.0, in_top - 0.09, zz), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
	# 洞口四周托梁/收边（截面 0.14×0.16，低于板底 0.11，遮住板边与楼梯之间的缝）
	var tob := {"outline": 0.02}
	M.box(root, Vector3(1.17, 0.16, 0.14), Vector3(4.235, in_top - 0.03, -0.55), M.C_WOOD_DARK, 0.0, tob)
	M.box(root, Vector3(0.14, 0.16, 3.28), Vector3(4.82, in_top - 0.03, -2.19), M.C_WOOD_DARK, 0.0, tob)
	M.box(root, Vector3(0.14, 0.16, 1.23), Vector3(1.005, in_top - 0.03, -3.215), M.C_WOOD_DARK, 0.0, tob)
	M.box(root, Vector3(2.645, 0.16, 0.14), Vector3(2.3275, in_top - 0.03, -2.60), M.C_WOOD_DARK, 0.0, tob)
	M.box(root, Vector3(0.14, 0.16, 2.05), Vector3(3.65, in_top - 0.03, -1.575), M.C_WOOD_DARK, 0.0, tob)
	# 室内四角木柱（内表面凸入室内 0.29，背面埋入墙 0.02）
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			M.box(root, Vector3(0.30, 3.60, 0.30), Vector3(sx * 4.795, fy + 1.80, sz * 3.695), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
	# 踢脚线（凸入室内 0.04，背面埋入 0.02）
	M.box(root, Vector3(3.75, 0.16, 0.06), Vector3(-3.05, fy + 0.08, 3.83), M.C_WOOD_DARK, 0.0, {})
	M.box(root, Vector3(3.75, 0.16, 0.06), Vector3(3.05, fy + 0.08, 3.83), M.C_WOOD_DARK, 0.0, {})
	M.box(root, Vector3(fw - 0.20, 0.16, 0.06), Vector3(0.0, fy + 0.08, -3.83), M.C_WOOD_DARK, 0.0, {})
	M.box(root, Vector3(0.06, 0.16, fd - 0.20), Vector3(-4.93, fy + 0.08, 0.0), M.C_WOOD_DARK, 0.0, {})
	M.box(root, Vector3(0.06, 0.16, fd - 0.20), Vector3(4.93, fy + 0.08, 0.0), M.C_WOOD_DARK, 0.0, {})
	# 后墙木饰（厚 0.08：背埋 0.015 / 外凸 0.065）
	for yy in [0.30, 0.62, 0.94]:
		M.box(root, Vector3(fw - 0.24, 0.26, 0.08), Vector3(0.0, fy + yy, -3.815), M.C_WOOD_LIGHT, 0.0, {})
	M.box(root, Vector3(fw - 0.20, 0.10, 0.09), Vector3(0.0, fy + 1.16, -3.81), M.C_WOOD_DARK, 0.0, {})
	# 门洞内侧木框（厚 0.14：背埋 0.03 / 凸入 0.11）
	for sx in [-1.0, 1.0]:
		M.box(root, Vector3(0.30, 3.55, 0.14), Vector3(sx * 1.30, fy + 1.78, 3.80), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
	M.box(root, Vector3(2.75, 0.16, 0.18), Vector3(0.0, fy + 3.58, 3.80), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
	# 室内顶圈梁（后墙 + 两侧）
	M.box(root, Vector3(fw, 0.16, 0.14), Vector3(0.0, in_top - 0.30, -3.79), M.C_WOOD_DARK, 0.0, {})
	M.box(root, Vector3(0.14, 0.16, fd), Vector3(4.88, in_top - 0.30, 0.0), M.C_WOOD_DARK, 0.0, {})
	M.box(root, Vector3(0.14, 0.16, fd), Vector3(-4.88, in_top - 0.30, 0.0), M.C_WOOD_DARK, 0.0, {})
	# ---- 壁炉（石体厚 0.56：背面贴墙内面 3.84，正面 -3.28）----
	var fpx: float = -2.40
	M.box(root, Vector3(1.70, 3.30, 0.56), Vector3(fpx, fy + 1.65, -3.56), M.C_STONE, 0.0, {"outline": 0.03})
	M.box(root, Vector3(1.15, 1.05, 0.06), Vector3(fpx, fy + 0.58, -3.27), Color("211812"), 0.0, {})
	for sx in [-1.0, 1.0]:
		M.box(root, Vector3(0.26, 1.30, 0.22), Vector3(fpx + sx * 0.70, fy + 0.65, -3.18), M.C_STONE_DARK, 0.0, {"outline": 0.02})
	M.box(root, Vector3(1.72, 0.22, 0.26), Vector3(fpx, fy + 1.33, -3.18), M.C_STONE_DARK, 0.0, {"outline": 0.02})
	M.box(root, Vector3(1.90, 0.10, 0.38), Vector3(fpx, fy + 1.47, -3.15), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
	M.box(root, Vector3(2.20, 0.12, 0.80), Vector3(fpx, fy + 0.06, -3.01), M.C_STONE_DARK, 0.0, {"outline": 0.03})
	M.cyl_rot(root, 0.07, 0.07, 0.85, Vector3(fpx, fy + 0.20, -3.16), M.C_WOOD_DARK, Vector3(0.0, 0.0, PI * 0.5), {})
	M.cyl_rot(root, 0.06, 0.06, 0.78, Vector3(fpx, fy + 0.31, -3.14), M.C_WOOD_DARK, Vector3(0.0, 0.30, PI * 0.5), {})
	for k in range(3):
		M.box(root, Vector3(0.16, 0.08, 0.20), Vector3(fpx - 0.22 + float(k) * 0.22, fy + 0.19, -3.12), Color("ff7a33"), 0.0, {"self_lit": true, "glow": 1.35})
	M.halo(root, Vector3(fpx, fy + 0.38, -3.02), 0.95, Color(2.0, 0.95, 0.35, 1.0))
	# ---- P7-V3 室内家具：统一走 IsleHouseProps 程序化库（家具原点 = 占地中心 / 落地 y=fy）----
	# 入口区（+Z 前墙）：门垫 / 换鞋凳 / 挂衣板 / 挂钟 / 盆栽
	P.build(root, "doormat", Vector3(0.0, fy, 3.30), 0.0)
	P.build(root, "shoe_bench", Vector3(2.15, fy, 3.34), PI, {"cushion": Color("c98e7f")})
	# 墙挂件原点必须贴在内墙面 z=3.84（前墙中心 4.02、厚 0.36），否则背板会埋进墙体
	P.build(root, "coat_rack", Vector3(2.15, 2.05, 3.84), PI)
	P.build(root, "wall_clock", Vector3(2.15, 3.05, 3.84), PI)
	P.build(root, "plant_pot", Vector3(4.42, fy, 3.42), 0.6)
	# 客厅区（左半）：地毯 / 沙发（面向壁炉）/ 茶几 / 扶手椅 / 落地灯
	P.build(root, "rug", Vector3(-2.30, fy + 0.004, -1.10), 0.0)
	P.build(root, "sofa", Vector3(-2.30, fy, -0.20), PI, {"cushion": Color("c98e7f")})
	P.build(root, "coffee_table", Vector3(-2.30, fy, -1.45), 0.0, {"color": M.C_WOOD_LIGHT})
	P.build(root, "armchair", Vector3(-4.10, fy, -1.95), 2.356, {"cushion": Color("6f7f6a")})
	P.build(root, "floor_lamp", Vector3(-4.34, fy, -2.72), 0.3)
	P.build(root, "firewood_basket", Vector3(-3.55, fy, -2.98), 0.4)
	# 工作角（左墙）：书桌 + 椅 + 书架
	P.build(root, "desk", Vector3(-4.44, fy, -0.30), PI * 0.5)
	P.build(root, "chair", Vector3(-3.70, fy, -0.30), -PI * 0.5, {"cushion": Color("8a6f5a")})
	P.build(root, "bookshelf", Vector3(-4.74, fy, 2.30), PI * 0.5)
	# 后墙（壁炉左/右）：高柜 / 矮边柜 + 台灯
	P.build(root, "tall_cupboard", Vector3(-4.10, fy, -3.58), 0.0)
	P.build(root, "sideboard", Vector3(0.90, fy, -3.60), 0.0)
	P.build(root, "table_lamp", Vector3(0.90, fy + 0.875, -3.60), 0.0)
	# 餐区（右前）：餐桌 + 4 椅
	P.build(root, "dining_table", Vector3(1.15, fy, 1.95), 0.0)
	P.build(root, "chair", Vector3(1.15, fy, 2.72), PI, {"cushion": Color("8a6f5a")})
	P.build(root, "chair", Vector3(1.15, fy, 1.18), 0.0, {"cushion": Color("8a6f5a")})
	P.build(root, "chair", Vector3(2.18, fy, 1.95), -PI * 0.5, {"cushion": Color("8a6f5a")})
	P.build(root, "chair", Vector3(0.12, fy, 1.95), PI * 0.5, {"cushion": Color("8a6f5a")})
	# 壁挂画框（左墙）
	P.build(root, "picture_frame", Vector3(-4.92, 2.70, 1.45), PI * 0.5)
	# ---- 室内吊灯：P7-V3 移到餐桌正上方（灯光 light_sources 同步在 build() 中改到 (1.15,fy+2.45,1.95)）----
	var lamp_mat: ShaderMaterial = M.toon_material(Color("ffd79b"), {"self_lit": true, "glow": 1.05})
	M.cyl(root, 0.018, 0.018, 0.55, Vector3(1.15, in_top - 0.28, 1.95), M.C_WOOD_DARK, 0.0, {})
	M.cyl(root, 0.06, 0.34, 0.28, Vector3(1.15, in_top - 0.66, 1.95), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
	var bulb := MeshInstance3D.new()
	var bsm := SphereMesh.new()
	bsm.radius = 0.11
	bsm.height = 0.22
	bsm.radial_segments = 8
	bsm.rings = 5
	bulb.mesh = bsm
	bulb.material_override = lamp_mat
	bulb.position = Vector3(1.15, in_top - 0.74, 1.95)
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(bulb)
	M.halo(root, Vector3(1.15, in_top - 0.74, 1.95), 1.35, Color(1.7, 1.15, 0.62, 1.0))
	# P7-V3.1：一层家具逐件在自己的 Prop_<kind>_<seq> 节点内静态合批（材质/描边不变）
	_merge_props_of(root)

# ============================================================
# 10) 门廊上的猫（P7-V3：isle_cat.gd 程序化造型 + 原地随机待机，模型/动画细节见该文件）
# ============================================================
static func _cat(root: Node3D, C: Dictionary, pos: Vector3) -> Dictionary:
	var info: Dictionary = CAT.build(root, pos, -0.6)
	C["cat"] = info
	return info

# ============================================================
# 11) 鸟落点：Array[Dictionary]{id,pos,facing,radius,kind}（世界坐标，真实可站）
# ============================================================
# Phase6：所有屋面栖枝都改为“真实瓦面表面点”（含瓦厚，脚部留 0.02~0.06m 间隙），
# 并给出世界空间向上法线 normal 与坡度 slope，供 fx 判断能否站（radius<=0 或 normal.y<0.35 跳过）。
# 旧实现取封檐板/脊梁顶面，鸟会浮空或埋进瓦里；这里按 MultiMesh 瓦片实际几何算到瓦面：
#   * 脊瓦 RoofRidgeCaps：CylinderMesh r=0.22 h=0.62 radial6，轴沿 Z，中心 y=ridge_y+0.10；
#     圆柱局部 +Z 顶点朝上（世界 +Y）→ 最高母线 = ridge_y+0.10+0.22 = ridge_y+0.32。
#   * 筒瓦 RoofTiles：r 0.135~0.165（沿坡向变化），轴沿坡向，中心再沿法线抬高 0.10；
#     六棱柱的顶点同样在“屋面外法线”方向上 → 沿外法线高出 r，竖直高度 = r*cp。
#     取最靠近檐口第 18 行：s=0.30+18*0.36=6.78，x=cp*6.78=5.6302，轴 y=6.05659，
#     r_mid=0.150 → 瓦面 y=6.05659+0.150*cp=6.18116，再留 0.03 间隙。
static func _make_perches(root: Node3D, C: Dictionary) -> Array[Dictionary]:
	var ridge_y: float = C["ridge_y"]
	var pitch: float = C["pitch"]
	var cp: float = C["cp"]
	var sp: float = C["sp"]
	var chx: float = C["ch_x"]
	var chz: float = C["ch_z"]
	var ch_top: float = C["ch_top"]
	var deck_top: float = C["deck_top"]
	var gap: float = 0.03  # 脚部间隙（验收要求 0.02~0.06）
	var out: Array[Dictionary] = []
	# ---- 屋脊 3 个：脊瓦顶母线（顶点朝上，表面 y=ridge_y+0.32），z 对齐脊瓦段中心 ----
	var ridge_surface: float = ridge_y + 0.10 + 0.22
	var ridge_z: Array = [-3.08, -0.28, 2.52]
	for i in range(3):
		out.append(_mk_perch(root, "ridge_%d" % i,
				Vector3(0.0, ridge_surface + gap, float(ridge_z[i])),
				Vector3(0.0, 0.0, 1.0), Vector3(0.0, 1.0, 0.0), 0.0, 0.30, "ridge"))
	# ---- 屋檐 4 个：檐口第 18 行筒瓦顶母线（真实瓦面，不再是封檐板顶面）----
	var eave_s: float = 6.78
	var tile_axis_y: float = ridge_y - sp * eave_s + cp * 0.10
	var tile_r_mid: float = 0.150
	var eave_surface_y: float = tile_axis_y + tile_r_mid * cp
	# 瓦面顶母线 = 实例中心 + nrm*(0.10+r_mid)，nrm=(sx*sp,cp,0)：x 也要加 sp*(0.10+r_mid)，
	# 只取 cp*eave_s 会让落点比瓦棱向内偏 0.14m（垂直射线会从瓦棱旁边擦过去 → 探针 hit=false）。
	var ex: float = cp * eave_s + sp * (0.10 + tile_r_mid)
	# 偶数行无 z 交错：zspan=(30-1)*0.315=9.135，cix=6/23 → z=∓2.6775
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var pid: String = "eave_%s%s" % ["L" if sx < 0.0 else "R", "N" if sz < 0.0 else "P"]
			out.append(_mk_perch(root, pid,
					Vector3(sx * ex, eave_surface_y + gap, sz * 2.6775),
					Vector3(sx, 0.0, 0.0),
					Vector3(sx * sp, cp, 0.0), pitch, 0.20, "eave"))
	# ---- 烟囱 1 个：压顶小石盒（y=top+0.24，h=0.22）顶面 = ch_top+0.35 ----
	out.append(_mk_perch(root, "chimney_0",
			Vector3(chx, ch_top + 0.35 + gap, chz),
			Vector3(0.0, 0.0, 1.0), Vector3(0.0, 1.0, 0.0), 0.0, 0.26, "chimney"))
	# ---- 门廊横梁 2 个（保留：真实横梁顶面，y=deck_top+3.38）----
	for sx in [-1.0, 1.0]:
		var pid2: String = "porch_beam_%s" % ("L" if sx < 0.0 else "R")
		out.append(_mk_perch(root, pid2,
				Vector3(sx * 2.20, deck_top + 3.38 + gap, 6.95),
				Vector3(0.0, 0.0, 1.0), Vector3(0.0, 1.0, 0.0), 0.0, 0.18, "porch_beam"))
	# ---- 门廊扶手 4 个（P7-V2：真实扶手实体顶面 + 0.03m 脚部间隙，slots=1）----
	# _porch：侧栏 M.box(0.10,0.09,2.60) 中心 (±4.12, deck_top+0.895, 5.78) → 顶面 y=deck_top+0.94；
	# 立柱(0.12 宽)在 z=4.60 / 6.95，顶面自由段 z∈[4.66,6.89]，取中点 z=5.775（距两立柱均 1.115m）。
	# facing 沿栏杆方向（侧栏局部 +Z、前栏局部 +X），鸟体长轴顺栏杆，站在 0.10m 窄面上不横向悬空。
	var rail_z: float = 5.775
	for sx in [-1.0, 1.0]:
		var pid3: String = "porch_rail_%s" % ("L" if sx < 0.0 else "R")
		out.append(_mk_perch(root, pid3,
				Vector3(sx * 4.12, deck_top + 0.94 + gap, rail_z),
				Vector3(0.0, 0.0, 1.0), Vector3(0.0, 1.0, 0.0), 0.0, 0.18, "porch_rail", 1))
	# 前栏 M.box(2.24,0.09,0.10) 中心 (±3.00, deck_top+0.90, 6.95) → 顶面 y=deck_top+0.945；
	# 立柱(0.12 宽)在 x=±1.88 / ±4.12，顶面自由段 x∈[1.94,4.06]，取中点 x=±3.00（距两立柱均 1.06m）。
	# facing 前栏局部 +X（沿栏杆方向）。
	for sx in [-1.0, 1.0]:
		var pid4: String = "porch_rail_F%s" % ("L" if sx < 0.0 else "R")
		out.append(_mk_perch(root, pid4,
				Vector3(sx * 3.00, deck_top + 0.945 + gap, 6.95),
				Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), 0.0, 0.18, "porch_rail", 1))
	return out

# perch 数据契约：id / pos(世界) / facing(世界单位向量) / radius / kind / normal(世界向上单位向量) / slope(弧度)
# slots > 0 时显式写入槽位数（窄栏/窄面用 slots=1，避免 fx 按 radius 自动展开多槽位）。
static func _mk_perch(root: Node3D, id: String, local_pos: Vector3, facing_local: Vector3,
		normal_local: Vector3, slope: float, radius: float, kind: String, slots: int = 0) -> Dictionary:
	var wp: Vector3 = _world(root, local_pos)
	var wf: Vector3 = (_world(root, local_pos + facing_local) - wp)
	if wf.length() > 0.0001:
		wf = wf.normalized()
	var wn: Vector3 = (_world(root, local_pos + normal_local) - wp)
	if wn.length() > 0.0001:
		wn = wn.normalized()
	else:
		wn = Vector3.UP
	var out := {"id": id, "pos": wp, "facing": wf, "radius": radius, "kind": kind,
		"normal": wn, "slope": slope}
	if slots > 0:
		out["slots"] = slots
	return out
