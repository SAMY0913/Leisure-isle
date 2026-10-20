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
## 5) perches 改为 Array[Dictionary]{id,pos,facing,radius,kind,normal,slope}：屋脊 3（脊瓦顶）+ 屋檐 4
##    （檐口筒瓦顶）+ 烟囱 1（顶石）+ 门廊梁 2 = 10 个真实瓦面/实体表面点，脚部间隙 0.03m；
##    normal 为世界空间向上单位法线（eave normal.y≈0.827），slope 为坡面倾角（ridge/chimney/porch=0，eave=pitch）。
## 6) Phase6/T4：导出灯塔光束遮挡盒 get_beam_occluders()（主体/屋面/烟囱 3 盒，世界 center/half/yaw），
##    阁楼改用独立低反射玻璃（opacity .020/.014、reflection_gain .34/.26）并可透视室内；删除窗外 2.10 光晕，
##    阁楼室内两盏暖灯走 light_sources；保留全部旧返回键，新增 beam_occluders / attic_glass_mats /
##    attic_lamp2_world / attic_window_world / attic_lamp_world。
##
## 局部坐标：root 位于 (M.HOUSE_X, M.house_ground_y(), M.HOUSE_Z)，rotation.y = M.HOUSE_YAW。
## 尺寸：w=10.6 d=8.4 wh=5.6 rh=3.6，floor_y=fy=0.55，屋脊沿局部 +Z，山墙在 ±Z，门在 +Z 立面。

const M := preload("res://scripts/isle_math.gd")

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
	var lamp_world: Vector3 = _world(root, Vector3(0.50, fy + 2.45, 0.40))
	var fire_world: Vector3 = _world(root, Vector3(C["ch_x"], fy + 0.55, -3.10))
	var attic_lamp_world: Vector3 = C["attic_lamp_world"]
	var attic_lamp2_world: Vector3 = _world(root, C["attic_lamp2_pos"])
	var attic_window_world: Vector3 = C["attic_window_world"]
	var light_sources: Array = []
	light_sources.append({"pos": lamp_world, "color": Color(1.0, 0.74, 0.44), "range": 7.5, "intensity": 1.60})
	light_sources.append({"pos": fire_world, "color": Color(1.0, 0.52, 0.22), "range": 5.4, "intensity": 1.30})
	light_sources.append({"pos": lantern_world, "color": Color(1.0, 0.78, 0.48), "range": 6.5, "intensity": 1.35})
	# 阁楼：删除窗外 2.10m 的 ADD 光晕（夜间会糊成光球、挡住室内视线）后，用两盏室内暖灯经
	# main._collect_lights → toon 解析点光照亮书桌/床/地板/部分内墙，位置都在室内（离外墙 ≥1.9m）。
	light_sources.append({"pos": attic_lamp_world, "color": Color(1.0, 0.74, 0.44), "range": 6.4, "intensity": 1.50})
	light_sources.append({"pos": attic_lamp2_world, "color": Color(1.0, 0.70, 0.40), "range": 5.2, "intensity": 1.42})
	for wl in C["win_lights"]:
		light_sources.append({"pos": wl["pos"], "color": Color(1.0, 0.80, 0.52), "range": 3.8, "intensity": 0.70})
	# ---- 灯塔光束遮挡盒（世界空间 yaw 对齐 AABB；main._collect_beam_occluders 写 g_occ_*）----
	var beam_occluders: Array = _beam_occluders_world(root, C)

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
	}

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
	return {
		"root": root,
		"w": w, "d": d, "wh": wh, "rh": rh, "fy": fy,
		"hw": hw, "hd": hd, "wall_t": wall_t,
		"roof_base": roof_base, "ridge_y": ridge_y,
		"pitch": pitch, "cp": cp, "sp": sp,
		"slope_len": slope_len, "eave_x": eave_x, "eave_y": eave_y,
		"roof_z": roof_z,
		"deck_top": 0.42,
		"ch_x": -2.40, "ch_z": -4.05, "ch_top": 9.92,
		"lantern_pos": Vector3(-2.80, 3.20, 6.55),
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
	var yc: float = fy + 2.35
	# ---- 拱券门框：13 段小 box 沿半圆排布（外凸 0.04/0.05，切向 0.30 < 弦距 0.340，相邻不重叠）----
	for k in range(13):
		var a: float = PI * float(k) / 12.0
		var bx: float = cos(a) * 1.30
		var by: float = sin(a) * 1.30
		var bsize := Vector3(0.32, 0.30, 0.26)
		var bz: float = zf + 0.09
		var bcol: Color = M.C_WOOD_DARK
		if k == 6:
			bsize = Vector3(0.34, 0.34, 0.26)
			bz = zf + 0.105
			bcol = M.C_WOOD_LIGHT
		M.box_rot(root, bsize, Vector3(bx, yc + by, bz), bcol, Vector3(0.0, 0.0, a), {"outline": 0.03})
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
	var arc_cx: float = 1.13
	var arc_cy: float = 2.35
	M.cyl_rot(pivot, 1.10, 1.10, 0.09, Vector3(arc_cx, arc_cy, 0.0), M.C_WOOD, Vector3(PI * 0.5, 0.0, 0.0), {"outline": 0.02, "bands": 4.0})
	for k in range(7):
		var a2: float = PI * (float(k) + 0.5) / 7.0
		var cpos := Vector3(arc_cx + cos(a2) * 0.62, arc_cy + sin(a2) * 0.62, 0.055)
		var pc2: Color = M.C_WOOD_LIGHT if k % 2 == 0 else M.C_WOOD
		M.box_rot(pivot, Vector3(0.72, 0.62, 0.05), cpos, pc2, Vector3(0.0, 0.0, a2), {"outline": 0.02})
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
	root.add_child(mi)

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
	# ---- 吊灯（lantern_mat / lantern_halo 由 main 调光）----
	var lpos: Vector3 = C["lantern_pos"]
	var lm: ShaderMaterial = C["lantern_mat"]
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
	C["lantern_halo"] = M.halo(root, lpos, 2.10, Color(2.4, 1.6, 0.8, 1.0))
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
	# ---- 地板结构 + 板条 ----
	M.box(root, Vector3(fw + 0.04, 0.14, fd + 0.04), Vector3(0.0, floor_y - 0.07, 0.0), Color("5f4733"), 0.0, {"bands": 4.0})
	var fl_mesh := BoxMesh.new()
	fl_mesh.size = Vector3(0.42, 0.02, fd - 0.04)
	var flxf: Array = []
	var flcol: Array = []
	for i in range(21):
		var xx: float = -4.47 + float(i) * 0.447
		flxf.append(Transform3D(Basis.IDENTITY, Vector3(xx, floor_y + 0.005, 0.0)))
		var t: float = M.noise01(float(i) * 0.83, 4.7)
		var mm: float = 0.80 + t * 0.30
		flcol.append(Color(mm, mm * 0.96, mm * 0.90, 1.0))
	M.multis(root, "AtticFloor", fl_mesh, flxf, flcol, M.toon_material(Color("8b6a49"), {"vertex_color": true, "bands": 4.0, "soft": 0.55}))
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
	# ---- 家具 ----
	# 地毯
	M.box(ia, Vector3(2.80, 0.03, 2.00), Vector3(0.0, floor_y + 0.025, 2.05), Color("9a6b5c"), 0.0, {"bands": 3.0})
	M.box(ia, Vector3(2.30, 0.035, 1.60), Vector3(0.0, floor_y + 0.045, 2.05), Color("c9a78e"), 0.0, {"bands": 3.0})
	# 书桌（面向落地窗）
	M.box(ia, Vector3(1.70, 0.08, 0.90), Vector3(0.0, 6.42, 2.85), M.C_WOOD_LIGHT, 0.0, {"outline": 0.03})
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			M.box(ia, Vector3(0.08, 0.68, 0.08), Vector3(sx * 0.75, 6.04, 2.85 + sz * 0.36), M.C_WOOD_DARK, 0.0, {})
	# 桌上 3 本书 + 台灯
	var book_cols: Array = [Color("8a5a4a"), Color("5d7a6a"), Color("7a6a8a")]
	for k in range(3):
		M.box(ia, Vector3(0.10, 0.22, 0.16), Vector3(-0.45 + float(k) * 0.13, 6.57, 2.80), book_cols[k % 3], 0.0, {})
	M.cyl(ia, 0.07, 0.09, 0.05, Vector3(0.55, 6.485, 2.85), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
	M.cyl(ia, 0.018, 0.018, 0.30, Vector3(0.55, 6.66, 2.85), M.C_WOOD_DARK, 0.0, {})
	M.cyl(ia, 0.08, 0.16, 0.18, Vector3(0.55, 6.85, 2.85), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
	var shade_mat: ShaderMaterial = M.toon_material(Color("ffd79b"), {"self_lit": true, "glow": 1.15})
	var bulb := MeshInstance3D.new()
	var bsm := SphereMesh.new()
	bsm.radius = 0.065
	bsm.height = 0.13
	bsm.radial_segments = 8
	bsm.rings = 5
	bulb.mesh = bsm
	bulb.material_override = shade_mat
	bulb.position = Vector3(0.55, 6.84, 2.85)
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ia.add_child(bulb)
	M.halo(root, Vector3(0.55, 6.84, 2.85), 1.05, Color(1.9, 1.30, 0.62, 1.0))
	C["attic_lamp_world"] = _world(root, Vector3(0.55, 6.84, 2.85))
	# 椅子（面向窗）
	_chair(ia, Vector3(0.0, floor_y, 1.95), 0.0)
	# 床（-X 侧，全部在斜顶下）
	M.box(ia, Vector3(2.00, 0.24, 1.25), Vector3(-3.00, 6.01, -0.80), M.C_WOOD_DARK, 0.0, {"outline": 0.03})
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			M.box(ia, Vector3(0.10, 0.22, 0.10), Vector3(-3.00 + sx * 0.85, 5.81, -0.80 + sz * 0.50), M.C_WOOD_DARK, 0.0, {})
	M.box(ia, Vector3(1.90, 0.18, 1.15), Vector3(-3.00, 6.22, -0.80), Color("efe4cf"), 0.0, {"bands": 4.0})
	M.box(ia, Vector3(1.40, 0.12, 1.18), Vector3(-2.85, 6.36, -0.80), Color("c98e7f"), 0.0, {})
	M.box(ia, Vector3(0.12, 0.85, 1.30), Vector3(-3.96, 6.28, -0.80), M.C_WOOD, 0.0, {"outline": 0.02})
	M.box(ia, Vector3(0.50, 0.13, 0.50), Vector3(-3.55, 6.36, -0.80), Color("f6efe0"), 0.0, {})
	# 衣柜（+X 侧靠后，顶部低于斜顶）
	M.box(ia, Vector3(0.60, 1.75, 1.20), Vector3(2.30, 6.575, -1.60), M.C_WOOD, 0.0, {"outline": 0.03})
	M.box(ia, Vector3(0.04, 1.55, 0.52), Vector3(1.99, 6.575, -1.90), M.C_WOOD_LIGHT, 0.0, {"outline": 0.02})
	M.box(ia, Vector3(0.04, 1.55, 0.52), Vector3(1.99, 6.575, -1.30), M.C_WOOD_LIGHT, 0.0, {"outline": 0.02})
	M.box(ia, Vector3(0.54, 0.06, 1.14), Vector3(2.30, 7.48, -1.60), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
	ia.set_meta("furniture_count", 7)

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
	# 天花板 + 横梁（梁顶埋入天花 0.01）
	M.box(root, Vector3(fw, 0.10, fd), Vector3(0.0, in_top + 0.05, 0.0), Color("d9c7a5"), 0.0, {"bands": 4.0, "soft": 0.60, "glow": 0.04})
	for zz in [-2.70, -0.90, 0.90, 2.70]:
		M.box(root, Vector3(fw, 0.20, 0.22), Vector3(0.0, in_top - 0.09, zz), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
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
	# ---- 床 ----
	M.box(root, Vector3(2.05, 0.28, 1.35), Vector3(-3.75, fy + 0.30, -1.80), M.C_WOOD_DARK, 0.0, {"outline": 0.03})
	M.box(root, Vector3(0.12, 0.95, 1.45), Vector3(-4.78, fy + 0.62, -1.80), M.C_WOOD, 0.0, {"outline": 0.02})
	M.box(root, Vector3(1.95, 0.20, 1.25), Vector3(-3.75, fy + 0.53, -1.80), Color("efe4cf"), 0.0, {"bands": 4.0})
	M.box(root, Vector3(1.45, 0.14, 1.28), Vector3(-3.45, fy + 0.68, -1.80), Color("c98e7f"), 0.0, {})
	for sz in [-1.0, 1.0]:
		M.box(root, Vector3(0.50, 0.15, 0.55), Vector3(-4.52, fy + 0.68, -1.80 + sz * 0.28), Color("f6efe0"), 0.0, {})
	# ---- 桌子 + 三把椅子 ----
	M.box(root, Vector3(1.65, 0.10, 1.00), Vector3(1.55, fy + 0.76, 0.55), M.C_WOOD_LIGHT, 0.0, {"outline": 0.03})
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			M.box(root, Vector3(0.10, 0.72, 0.10), Vector3(1.55 + sx * 0.70, fy + 0.38, 0.55 + sz * 0.40), M.C_WOOD_DARK, 0.0, {})
	_chair(root, Vector3(1.55, fy, 1.42), PI)
	_chair(root, Vector3(1.55, fy, -0.32), 0.0)
	_chair(root, Vector3(2.72, fy, 0.55), -PI * 0.5)
	# ---- 靠墙橱柜 ----
	M.box(root, Vector3(0.50, 2.10, 1.50), Vector3(4.66, fy + 1.05, 1.70), M.C_WOOD, 0.0, {"outline": 0.03})
	for sz in [-1.0, 1.0]:
		M.box(root, Vector3(0.04, 1.70, 0.66), Vector3(4.40, fy + 1.10, 1.70 + sz * 0.36), M.C_WOOD_LIGHT, 0.0, {"outline": 0.02})
	M.box(root, Vector3(0.44, 0.06, 1.44), Vector3(4.62, fy + 2.12, 1.70), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
	# ---- 书架 + 书 ----
	M.box(root, Vector3(0.38, 1.85, 1.30), Vector3(4.72, fy + 0.925, -2.40), M.C_WOOD_DARK, 0.0, {"outline": 0.03})
	for yy in [0.55, 0.95, 1.35]:
		M.box(root, Vector3(0.32, 0.04, 1.24), Vector3(4.67, fy + yy, -2.40), M.C_WOOD, 0.0, {})
	var bcols: Array = [Color("8a5a4a"), Color("5d7a6a"), Color("b08a5a"), Color("7a6a8a"), Color("9a4f42")]
	for k in range(5):
		M.box(root, Vector3(0.22, 0.26, 0.09), Vector3(4.50, fy + 0.72, -2.92 + float(k) * 0.20), bcols[k % 5], 0.0, {})
	for k in range(4):
		M.box(root, Vector3(0.22, 0.24, 0.09), Vector3(4.50, fy + 1.11, -2.80 + float(k) * 0.22), bcols[(k + 2) % 5], 0.0, {})
	# ---- 地毯 ----
	M.box(root, Vector3(2.90, 0.03, 2.10), Vector3(1.55, fy + 0.045, 0.55), Color("9a6b5c"), 0.0, {"bands": 3.0})
	M.box(root, Vector3(2.30, 0.035, 1.60), Vector3(1.55, fy + 0.065, 0.55), Color("c9a78e"), 0.0, {"bands": 3.0})
	# ---- 窗边小桌 + 盆栽 ----
	M.box(root, Vector3(0.78, 0.08, 0.56), Vector3(-3.45, fy + 0.72, 3.45), M.C_WOOD_LIGHT, 0.0, {"outline": 0.02})
	M.box(root, Vector3(0.16, 0.70, 0.16), Vector3(-3.45, fy + 0.36, 3.45), M.C_WOOD_DARK, 0.0, {})
	M.cyl(root, 0.14, 0.10, 0.22, Vector3(-3.45, fy + 0.87, 3.45), M.C_TERRACOTTA, 0.0, {"outline": 0.02})
	M.sphere(root, 0.17, Vector3(-3.45, fy + 1.10, 3.45), M.C_LEAF_B, Vector3(1.0, 0.9, 1.0), {"bands": 3.0, "rim": 0.10})
	M.sphere(root, 0.12, Vector3(-3.28, fy + 1.03, 3.38), M.C_LEAF_A, Vector3(1.0, 1.1, 1.0), {"bands": 3.0})
	M.sphere(root, 0.11, Vector3(-3.60, fy + 1.02, 3.52), M.C_LEAF_A, Vector3(1.0, 1.1, 1.0), {"bands": 3.0})
	# ---- 室内吊灯 ----
	var lamp_mat: ShaderMaterial = M.toon_material(Color("ffd79b"), {"self_lit": true, "glow": 1.05})
	M.cyl(root, 0.018, 0.018, 0.55, Vector3(0.50, in_top - 0.28, 0.40), M.C_WOOD_DARK, 0.0, {})
	M.cyl(root, 0.06, 0.34, 0.28, Vector3(0.50, in_top - 0.66, 0.40), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
	var bulb := MeshInstance3D.new()
	var bsm := SphereMesh.new()
	bsm.radius = 0.11
	bsm.height = 0.22
	bsm.radial_segments = 8
	bsm.rings = 5
	bulb.mesh = bsm
	bulb.material_override = lamp_mat
	bulb.position = Vector3(0.50, in_top - 0.74, 0.40)
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(bulb)
	M.halo(root, Vector3(0.50, in_top - 0.74, 0.40), 1.35, Color(1.7, 1.15, 0.62, 1.0))

static func _chair(parent: Node3D, base: Vector3, rot_y: float) -> void:
	var n := Node3D.new()
	n.position = base
	n.rotation.y = rot_y
	parent.add_child(n)
	M.box(n, Vector3(0.46, 0.07, 0.46), Vector3(0.0, 0.45, 0.0), M.C_WOOD_LIGHT, 0.0, {"outline": 0.02})
	M.box(n, Vector3(0.46, 0.55, 0.06), Vector3(0.0, 0.76, -0.22), M.C_WOOD, 0.0, {"outline": 0.02})
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			M.box(n, Vector3(0.06, 0.45, 0.06), Vector3(sx * 0.18, 0.225, sz * 0.18), M.C_WOOD_DARK, 0.0, {})

# ============================================================
# 10) 门廊上的猫（保留旧版造型）
# ============================================================
static func _cat(root: Node3D, C: Dictionary, pos: Vector3) -> void:
	var cat := Node3D.new()
	cat.name = "PorchCat"
	cat.position = pos
	cat.rotation.y = -0.6
	root.add_child(cat)
	M.sphere(cat, 0.22, Vector3(0.0, 0.20, 0.0), Color("4a4e57"), Vector3(1.0, 0.85, 1.35), {"outline": 0.02, "rim": 0.10})
	M.sphere(cat, 0.17, Vector3(0.0, 0.38, 0.24), Color("555a64"), Vector3(1.0, 0.95, 1.0), {"outline": 0.02, "rim": 0.10})
	for sx in [-1.0, 1.0]:
		var ear := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.075
		cm.height = 0.13
		cm.radial_segments = 4
		ear.mesh = cm
		ear.material_override = M.toon_material(Color("555a64"), {"outline": 0.015})
		ear.position = Vector3(sx * 0.10, 0.51, 0.26)
		ear.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cat.add_child(ear)
	M.cyl_rot(cat, 0.045, 0.06, 0.55, Vector3(0.16, 0.18, -0.30), Color("4a4e57"), Vector3(0.9, 0.0, 0.0), {"outline": 0.02})
	M.sphere(cat, 0.10, Vector3(0.0, 0.26, 0.28), Color("d8d2c4"), Vector3(1.0, 1.0, 1.2), {"outline": 0.0})
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			M.sphere(cat, 0.055, Vector3(sx * 0.11, 0.04, sz * 0.16), Color("555a64"), Vector3(1.2, 0.6, 1.0), {"outline": 0.0})
	M.sphere(cat, 0.028, Vector3(0.0, 0.42, 0.40), Color("1e1a18"), Vector3(1.0, 1.0, 0.6), {"outline": 0.0})

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
	return out

# perch 数据契约：id / pos(世界) / facing(世界单位向量) / radius / kind / normal(世界向上单位向量) / slope(弧度)
static func _mk_perch(root: Node3D, id: String, local_pos: Vector3, facing_local: Vector3,
		normal_local: Vector3, slope: float, radius: float, kind: String) -> Dictionary:
	var wp: Vector3 = _world(root, local_pos)
	var wf: Vector3 = (_world(root, local_pos + facing_local) - wp)
	if wf.length() > 0.0001:
		wf = wf.normalized()
	var wn: Vector3 = (_world(root, local_pos + normal_local) - wp)
	if wn.length() > 0.0001:
		wn = wn.normalized()
	else:
		wn = Vector3.UP
	return {"id": id, "pos": wp, "facing": wf, "radius": radius, "kind": kind,
		"normal": wn, "slope": slope}
