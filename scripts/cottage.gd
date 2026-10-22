class_name IsleCottage
extends RefCounted
## 岛屿小屋 P7-V3.2 —— 全尺度重建版（1 世界单位 = 1 米，人体基准 1.50m）。
##
## 本轮（P7-V3.2 全岛度量衡校准）按 Lead 的 lead_scale_plan_v1.md 与 IsleMath.HOUSE_* 常量整栋重建，
## 不再有旧 10.6x8.4x5.6 外壳 / 27 级楼梯 / 2.60x3.65 门洞参数：
##   * 外廓 7.6(X) x 6.2(Z)，门在 +Z；一层净高 2.42，楼板 0.20，阁楼地板 3.17；
##   * 墙高 3.18、屋顶高 2.47（坡 33.02°）、屋脊 6.20、檐口出挑 0.60；
##   * 门洞净宽 1.14 / 净高 1.94（自 fy 起）：半圆拱（内 R0.52 / 外 R0.66）+ 气窗 R0.50 + 5 板门扇；
##   * 前窗 1.00x1.15 x2 / 侧窗 1.00x0.95 / 后窗 0.90x0.90 / 阁楼山墙窗 1.50x1.50；
##   * 16 级 L 形楼梯（8+8+平台，rise 0.16375 / tread 0.26 / 宽 0.85 / 净空 >=1.95）；
##   * 门廊台面 0.42，3 级 x0.14 台阶；烟囱顶 6.55（ridge+0.35）。
## 保留 P4/P7-V2 的外观语言：墙体真实洞口、半木构件、"独立厚度"装饰（外凸 0.04-0.06、内埋），
## 绘本 toon 材质 + 描边、门扇半圆气窗/拱形门框/门轴动画/DoorHit、阁楼落地窗、猫与 14 个栖息点、
## 灯塔光束遮挡盒、静态合批分区（外壳/一层室内/阁楼）。所有返回键与旧契约一致。
##
## 局部坐标：root 位于 (M.HOUSE_X, M.house_ground_y(), M.HOUSE_Z)，rotation.y = M.HOUSE_YAW。
## floor_y=fy=0.55，屋脊沿局部 +Z，山墙在 ±Z，门在 +Z 立面。

const M := preload("res://scripts/isle_math.gd")
const P := preload("res://scripts/isle_house_props.gd")
const CAT := preload("res://scripts/isle_cat.gd")

# P8.2-01：探针专用开关。true 时 build() 跳过 IsleBatch.merge_static，保留逐件 MeshInstance，
# 供 tools/probe_p82_fireplace.gd 在真实构建几何上逐件测量 AABB。生产路径恒为 false，不影响渲染。
static var probe_skip_batch: bool = false

## 世界坐标换算：运行时 root 已在场景树内时用 to_global；探针以游离节点构建时，Godot 4 的
## to_global 会退化为单位变换，此时用 root.transform * local 得到同样正确的世界坐标。
static func _world(root: Node3D, local: Vector3) -> Vector3:
    if root.is_inside_tree():
        return root.to_global(local)
    return root.transform * local

## P7-V3.2 修正：isle_math.make_prism_mesh 的三角形绕序在 Godot 中全是背面
## （主 pass 被 cull_back 剔除，只剩 outline next_pass 的 cull_front 轮廓壳可见，
##  门廊雨棚前山墙因此整片显示成描边深藏青）。这里给出绕序修正的同形状版本：
## 参数/尺寸/位置/材质口径与 M.prism 完全一致，只是三角形顶点顺序反转（法线保持外向）。
static func _add_tri_front(st: SurfaceTool, p: Vector3, q: Vector3, r: Vector3) -> void:
    var n: Vector3 = (q - p).cross(r - p).normalized()
    st.set_normal(n)
    st.add_vertex(p)
    st.set_normal(n)
    st.add_vertex(r)
    st.set_normal(n)
    st.add_vertex(q)

## 四个点按 isle_math._add_quad 的同一顺序给（a,b,c,d 共面，外法线 = (b-a)x(c-a)）。
static func _add_quad_front(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
    _add_tri_front(st, a, b, c)
    _add_tri_front(st, a, c, d)

## 山墙三角板（绕序修正版 M.prism）：w 沿 X、h 沿 +Y、d 沿 Z，pos 为底面中心。
static func prism_front(parent: Node3D, w: float, h: float, d: float, pos: Vector3, color: Color, rot_y: float = 0.0, opts: Dictionary = {}) -> MeshInstance3D:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var hw: float = w * 0.5
    var hd: float = d * 0.5
    var a := Vector3(-hw, 0.0, -hd)
    var b := Vector3(hw, 0.0, -hd)
    var c := Vector3(0.0, h, -hd)
    var e := Vector3(-hw, 0.0, hd)
    var f := Vector3(hw, 0.0, hd)
    var g := Vector3(0.0, h, hd)
    _add_tri_front(st, a, c, b)      # 后盖（外法线 -Z）
    _add_tri_front(st, e, f, g)      # 前盖（外法线 +Z）
    _add_quad_front(st, a, b, f, e)  # 底
    _add_quad_front(st, a, e, g, c)  # 左坡
    _add_quad_front(st, b, c, g, f)  # 右坡
    st.index()
    var mi := MeshInstance3D.new()
    mi.mesh = st.commit()
    mi.material_override = M.toon_material(color, opts)
    mi.position = pos
    mi.rotation.y = rot_y
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    parent.add_child(mi)
    return mi

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
    _stairs(root, C)          # P7-V3.2：16 级 L 形楼梯（先结构，后家具）
    _attic_interior(root, C)
    _interior(root, C)
    _cat(root, C, Vector3(1.70, C["deck_top"] + 0.02, 3.80))

    # ---- 交互命中体（main 用 collision_mask=2 的射线点击）----
    var door_hit := M.hitbox(parent, "DoorHit", _world(root, Vector3(0.0, fy + 1.10, hd + 0.30)), Vector3(2.0, 2.6, 1.4))
    var chimney_hit := M.hitbox(parent, "ChimneyHit", _world(root, Vector3(C["ch_x"], 5.10, C["ch_z"])), Vector3(1.1, 2.9, 1.1))
    var chimney_top := Node3D.new()
    chimney_top.name = "ChimneyTop"
    chimney_top.position = Vector3(C["ch_x"], C["ch_top"] + 0.35, C["ch_z"])
    root.add_child(chimney_top)

    # ---- 鸟落点：Array[Dictionary]（fx 需要 id/pos/facing/radius/kind）----
    var perches: Array[Dictionary] = _make_perches(root, C)

    # ---- 地面投影 ----
    M.shadow_blob(parent, _world(root, Vector3(0.0, 0.01, 0.40)), 5.4, 0.30)
    M.shadow_blob(parent, _world(root, Vector3(0.0, 0.01, 3.90)), 3.0, 0.20)

    # ---- 暖光光源位置（世界坐标；main 写进 shader 的解析点光）----
    # P8.1-06：16 槽 = 室外池 g_l0..g_l9（上限 10）+ 室内池 g_l10..g_l15（上限 6）。
    # 每盏灯带 kind / indoor / priority（池内排序，越大越优先）；main 按画质预算截断后上传。
    # priority 约定：路灯 900（main 赋）、灯塔 800（main 赋）、门廊 700、窗光 660、码头 650（main 赋）；
    #                壁炉 900、一层吊灯 850、一层台灯 800、一层落地灯 750、阁楼吊灯1 700、阁楼吊灯2 650、阁楼台灯 600/590。
    var lantern_world: Vector3 = _world(root, C["lantern_pos"])
    var lantern_world_right: Vector3 = _world(root, C["lantern_pos_right"])
    var lamp_world: Vector3 = _world(root, Vector3(1.45, C["in_top"] - 0.62, 0.80))
    var fire_world: Vector3 = _world(root, Vector3(C["ch_x"], fy + 0.55, -2.30))
    var attic_lamp_world: Vector3 = C["attic_lamp_world"]
    var attic_lamp2_world: Vector3 = _world(root, C["attic_lamp2_pos"])
    var attic_window_world: Vector3 = C["attic_window_world"]
    # 门廊对称吊灯 → 1 个聚合槽（两盏相距 3.90m，取中点；两盏网格仍各自发光）
    var lantern_mid_world: Vector3 = _world(root, (C["lantern_pos"] + C["lantern_pos_right"]) * 0.5)
    # 窗光 → 1 个聚合槽：前立面两窗中线、墙外 0.70m（与 _window_assembly 的 win_lights 锚点同深度）
    var window_glow_world: Vector3 = _world(root, Vector3(0.0, fy + 1.48, C["hd"] + 0.70))
    # 一层家具灯具的灯泡位置（家具 builder 内灯泡局部 y：台灯 0.390 / 落地灯 1.270）
    var fl1: float = fy + 0.02
    var sideboard_lamp_world: Vector3 = _world(root, Vector3(0.20, fl1 + 0.80 + 0.390, -2.60))
    var floor_lamp_world: Vector3 = _world(root, Vector3(-3.12, fl1 + 1.270, 2.35))
    # 阁楼家具灯具的灯泡位置（床头柜台灯 y=+0.50、书桌台灯 y=+0.65，再 +0.390）
    var flat: float = C["attic_floor"] + 0.02
    var attic_bedside_lamp_world: Vector3 = _world(root, Vector3(-1.15, flat + 0.50 + 0.390, -1.61))
    var attic_desk_lamp_world: Vector3 = _world(root, Vector3(0.45, flat + 0.65 + 0.390, 2.55))
    var light_sources: Array = []
    # ---- 池 A：室外 -------
    light_sources.append({"pos": lantern_mid_world, "color": Color(1.0, 0.78, 0.48), "range": 5.2, "intensity": 1.20, "energy": 1.20, "kind": "porch_lantern", "indoor": false, "priority": 700})
    light_sources.append({"pos": window_glow_world, "color": Color(1.0, 0.80, 0.52), "range": 4.2, "intensity": 0.70, "energy": 0.70, "kind": "window_glow", "indoor": false, "priority": 660})
    # ---- 池 B：室内 -------
    # P8.2-02(b)：炉台石/地面在近距离被 1.5/5.0 的壁炉槽打到接近裁切，且顶面 vs 前脸硬边过强。
    # 位置由 P8.2-01 探针 G8 钉死不可移，只把能量 1.50→1.05、半径 5.0→6.0：
    # 近距离衰减更缓（0.45m 处直射 -31%）→ 去掉炉台石裁切与硬边，远处（≥3m）反而略增，房间暖光不变。
    light_sources.append({"pos": fire_world, "color": Color(1.0, 0.52, 0.22), "range": 6.0, "intensity": 1.05, "energy": 1.05, "kind": "fireplace", "indoor": true, "priority": 900})
    light_sources.append({"pos": lamp_world, "color": Color(1.0, 0.74, 0.44), "range": 5.4, "intensity": 1.55, "energy": 1.55, "kind": "chandelier", "indoor": true, "priority": 850})
    light_sources.append({"pos": sideboard_lamp_world, "color": Color(1.0, 0.82, 0.56), "range": 3.4, "intensity": 0.85, "energy": 0.85, "kind": "table_lamp", "indoor": true, "priority": 800})
    light_sources.append({"pos": floor_lamp_world, "color": Color(1.0, 0.80, 0.52), "range": 4.4, "intensity": 1.30, "energy": 1.30, "kind": "floor_lamp", "indoor": true, "priority": 750})
    light_sources.append({"pos": attic_lamp_world, "color": Color(1.0, 0.74, 0.44), "range": 4.6, "intensity": 1.45, "energy": 1.45, "kind": "attic_chandelier", "indoor": true, "priority": 700})
    light_sources.append({"pos": attic_lamp2_world, "color": Color(1.0, 0.70, 0.40), "range": 4.0, "intensity": 1.35, "energy": 1.35, "kind": "attic_chandelier", "indoor": true, "priority": 650})
    light_sources.append({"pos": attic_bedside_lamp_world, "color": Color(1.0, 0.78, 0.50), "range": 3.0, "intensity": 0.65, "energy": 0.65, "kind": "attic_table_lamp", "indoor": true, "priority": 600})
    light_sources.append({"pos": attic_desk_lamp_world, "color": Color(1.0, 0.78, 0.50), "range": 3.0, "intensity": 0.65, "energy": 0.65, "kind": "attic_table_lamp", "indoor": true, "priority": 590})
    # ---- 灯塔光束遮挡盒（世界空间 yaw 对齐 AABB；main._collect_beam_occluders 写 g_occ_*）----
    var beam_occluders: Array = _beam_occluders_world(root, C)

    # ---- P7-V3.1 静态合批（房屋外壳 / 一层室内 / 阁楼三层分区，家具与楼梯各自在自己的
    # 节点内已合批，不参与这里）----
    if not probe_skip_batch:
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
        # P8.1-06：一层/阁楼吊灯灯罩（main 每帧按昼夜写 glow=0.10+lanternI*1.05）
        "interior_shade_mats": [C.get("interior_shade_mat", null), C.get("attic_shade_mat", null)],
        "lantern_halo": C["lantern_halo"],
        "lantern_halos": C["lantern_halos"],
        "perches": perches,
        "lantern_world": lantern_world,
        "light_sources": light_sources,
        "glass_mats": C["glass_mats"],
        "interior_pos": _world(root, Vector3(0.35, fy + 1.20, 0.00)),
        "front_window_world": C["front_window_world"],
        "interior_lamp_world": lamp_world,
        "fireplace_world": fire_world,
        "attic_window_world": attic_window_world,
        "attic_lamp_world": attic_lamp_world,
        "attic_lamp2_world": attic_lamp2_world,
        # P8.1-06：门廊/窗光聚合槽 + 4 盏家具灯具（台灯/落地灯）的世界光源位置，供 probe/截图机位使用。
        "lantern_mid_world": lantern_mid_world,
        "window_glow_world": window_glow_world,
        "table_lamp_world": sideboard_lamp_world,
        "floor_lamp_world": floor_lamp_world,
        "attic_bedside_lamp_world": attic_bedside_lamp_world,
        "attic_desk_lamp_world": attic_desk_lamp_world,
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
##   interior  一层室内  |x|<=3.55 |z|<=2.85 y<3.05
##   attic     二层阁楼  |x|<=3.55 |z|<=2.85 y>=3.10
##   shell     外墙/屋顶/勒脚/门廊等其余部分
static func _batch_region(root: Node3D, mi: Node3D) -> String:
    var p: Vector3 = root.to_local(mi.global_position)
    if absf(p.x) <= 3.55 and absf(p.z) <= 2.85:
        if p.y < 3.05:
            return "interior"
        if p.y >= 3.10:
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
# 打到室内和背光墙面。这里导出小屋的遮挡盒，供 shader 用 ray-box 判定"该片元到灯室
# 的连线是否被屋子挡住"。
#
# 返回值：Array[Dictionary]，每个元素 {"center": Vector3 世界, "half": Vector3, "yaw": float 弧度}
#   * 盒是 yaw 对齐的 AABB：世界点 p 绕 Y 转 -yaw 后与 center±half 比较；
#   * yaw 取 cottage 世界旋转（本工程为 IsleMath.HOUSE_YAW=0.30），与 box 半尺寸同一坐标架；
#   * main._collect_beam_occluders() 取前 4 个写 g_occ_c0..c3 / g_occ_h0..h3 / g_occ_y0..y3。
#
# 尺寸取舍（P7-V3.2 按新尺度）：
#   * 主体盒顶面 = 屋檐（roof_base=3.73），x/z 比墙外皮各外扩 0.02/0.04；
#   * 屋面盒是"屋檐 ~ 脊瓦顶"的整体包络（y 3.73~6.44）；z 半宽取 hd+0.04，让前/后山墙
#     外皮 p+0.06n 保持在盒外，否则朝灯塔一侧的山墙会被自己判遮挡、永远不受光；
#   * 烟囱盒覆盖泛水板之上到顶石（y 3.93~6.55）。
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
    # Godot 绕 Y 旋转 +a 的世界映射为 R2d(-a)，故要得到"世界→盒局部"必须传 yaw = -rotation.y。
    var yaw: float = -atan2(xf.basis.z.x, xf.basis.z.z)
    var roof_top: float = ridge_y + 0.24
    var ch_lo: float = 3.93
    var ch_hi: float = ch_top + 0.35
    var out: Array = []
    out.append({
        "center": xf * Vector3(0.0, roof_base * 0.5, 0.0),
        "half": Vector3(hw + 0.02, roof_base * 0.5, hd + 0.04),
        "yaw": yaw,
    })
    out.append({
        "center": xf * Vector3(0.0, (roof_base + roof_top) * 0.5, 0.0),
        "half": Vector3(eave_x, (roof_top - roof_base) * 0.5, hd + 0.04),
        "yaw": yaw,
    })
    out.append({
        "center": xf * Vector3(ch_x, (ch_lo + ch_hi) * 0.5, ch_z),
        "half": Vector3(0.50, (ch_hi - ch_lo) * 0.5, 0.46),
        "yaw": yaw,
    })
    return out

# 对外 API：build 之后按 root 取遮挡盒（供 main / 调试 / 探针使用）。
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
# 尺寸与共享材质上下文（全部由 IsleMath.HOUSE_* / IsleScaleSpec 推导）
# ============================================================
static func _context(root: Node3D) -> Dictionary:
    var w: float = M.HOUSE_W                    # 7.6
    var d: float = M.HOUSE_D                    # 6.2
    var wh: float = M.HOUSE_WALL_H              # 3.18
    var rh: float = M.HOUSE_ROOF_H              # 2.47
    var fy: float = 0.55                        # 一层地板面（净高起算面）
    var hw: float = w * 0.5                     # 3.8
    var hd: float = d * 0.5                     # 3.1
    var wall_t: float = 0.30
    var roof_base: float = fy + wh              # 3.73（檐口）
    var ridge_y: float = roof_base + rh         # 6.20
    var pitch: float = atan(rh / hw)            # 33.02°
    var cp: float = cos(pitch)
    var sp: float = sin(pitch)
    var eave_ov: float = 0.60
    var slope_len: float = sqrt(hw * hw + rh * rh) + eave_ov
    var eave_x: float = hw + eave_ov * cp
    var eave_y: float = ridge_y - slope_len * sp
    var roof_z: float = d + 1.2
    var in_top: float = fy + 2.42               # 2.97 一层净高天花板
    var attic_floor: float = fy + 2.62          # 3.17（楼板 0.20 → 板底 2.97）
    var attic_slab_t: float = 0.20
    var attic_hw: float = 0.75                  # 阁楼窗半宽（1.50 宽）
    var attic_top: float = attic_floor + 1.60   # 4.77（窗洞顶）
    var stair_risers: float = 16.0
    var stair_rise: float = 0.16375
    var stair_tread: float = 0.26
    # 窗玻璃：主玻璃为共享材质（main 只改 window_mats 的 glow）；内层玻璃单列，形成双层玻璃层次。
    var glass_mat: ShaderMaterial = M.glass_material(0.06)
    var inner_glass: ShaderMaterial = M.glass_material(0.0)
    inner_glass.set_shader_parameter("tint", Color(0.80, 0.87, 0.89))
    inner_glass.set_shader_parameter("opacity", 0.045)
    inner_glass.set_shader_parameter("tint_strength", 0.16)
    inner_glass.set_shader_parameter("surface_rough", 0.04)
    inner_glass.set_shader_parameter("reflection_gain", 1.25)
    inner_glass.set_shader_parameter("refract_strength", 0.0)
    # 阁楼落地窗：夜间 main 会把 window_mats 的 glow 写到约 0.6，若共用则整面玻璃变成乳白雾面，
    # 从室外完全看不见室内。这里用两片独立材质压到"几乎纯透射"：
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
    # P8.1-06：灯罩类材质改 self_lit=false + 保留 glow —— 罩体由 glow 维持发亮观感，
    # 同时接受解析点光/环境光，灯本身才能照亮门廊台阶与室外地面。
    var lantern_mat: ShaderMaterial = M.toon_material(Color("ffcf9a"), {"self_lit": false, "glow": 1.0})
    # L 形楼梯（Flight A 沿 -Z 上行 7 踏 + 平台第 8 级；Flight B 沿 -X 上行 7 踏接阁楼）
    var land_top: float = fy + 8.0 * stair_rise   # 1.860
    return {
        "root": root,
        "w": w, "d": d, "wh": wh, "rh": rh, "fy": fy,
        "hw": hw, "hd": hd, "wall_t": wall_t,
        "roof_base": roof_base, "ridge_y": ridge_y,
        "pitch": pitch, "cp": cp, "sp": sp,
        "slope_len": slope_len, "eave_x": eave_x, "eave_y": eave_y,
        "roof_z": roof_z,
        "in_top": in_top,
        "attic_floor": attic_floor,
        "attic_slab_t": attic_slab_t,
        "attic_knee": 0.56,
        "deck_top": 0.42,
        "stair_risers": stair_risers,
        "stair_rise": stair_rise,
        "stair_tread": stair_tread,
        "stair_flight_a": {"x0": 2.64, "x1": 3.49, "z0": -0.12, "z1": -1.94, "land_top": land_top},
        "stair_flight_b": {"x0": 2.64, "x1": 0.82, "z0": -2.79, "z1": -1.94},
        "stair_hole_r1": Rect2(2.64, -2.79, 0.85, 2.67),
        "stair_hole_r2": Rect2(0.82, -2.79, 1.82, 0.85),
        "ch_x": -2.20, "ch_z": -2.60, "ch_top": 6.20,
        "lantern_pos": Vector3(-1.95, 2.05, 4.55),
        "lantern_pos_right": Vector3(1.95, 2.05, 4.55),
        "attic_hw": attic_hw,     # 阁楼窗半宽（1.50 宽）
        "attic_top": attic_top,   # 阁楼窗洞顶 4.77
        "glass_mat": glass_mat,
        "inner_glass": inner_glass,
        "attic_outer_glass": attic_outer_glass,
        "attic_inner_glass": attic_inner_glass,
        "attic_glass_mats": [attic_outer_glass, attic_inner_glass],
        "lantern_mat": lantern_mat,
        "window_mats": [glass_mat],
        "glass_mats": [glass_mat, inner_glass],
        "window_halos": [],
        "lantern_halos": [],
        # P8.2-02：室内吊灯光晕（一层吊灯 + 阁楼吊灯）。原先未纳入任何数组，白天也满亮度，
        # 近景变成直径 ~1m 的白色光斑；改由 main._update_lighting 按 lanternI 收放亮度与半径。
        "interior_halos": [],
        "win_lights": [],
        "front_window_world": [],
        "attic_window_world": Vector3.ZERO,
        "attic_lamp_world": Vector3.ZERO,
        "attic_lamp2_pos": Vector3(-2.00, 4.06, -2.00),
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
    var pw: float = w + 1.0            # 8.60
    var pd: float = d + 0.10           # 6.30
    # 台基主体（顶面 0.39 与压顶石底面 0.39 对接，避免两顶面共面）
    M.box(root, Vector3(pw, 1.14, pd), Vector3(0.0, -0.18, 0.0), M.C_STONE_DARK, 0.0, {"outline": 0.05})
    # 台基压顶石
    M.box(root, Vector3(pw + 0.26, 0.16, pd + 0.26), Vector3(0.0, fy - 0.08, 0.0), M.C_STONE, 0.0, {"outline": 0.03})
    # 台基四周两皮错缝石环（MultiMesh 实例化，颜色微差）
    var stone_mesh := BoxMesh.new()
    stone_mesh.size = Vector3(0.68, 0.16, 0.18)
    var stone_mat: ShaderMaterial = M.toon_material(M.C_STONE, {"vertex_color": true, "bands": 3.0, "soft": 0.50, "rim": 0.05})
    var sxf: Array = []
    var scol: Array = []
    for f in range(2):
        var sgn: float = -1.0 + 2.0 * float(f)
        for row in range(2):
            var yy: float = 0.08 + float(row) * 0.16
            var off: float = 0.34 if row == 1 else 0.0
            for i in range(12):
                var xx: float = -pw * 0.5 + (pw / 12.0) * (float(i) + 0.5) + off
                if xx > pw * 0.5:
                    xx -= pw
                sxf.append(Transform3D(Basis.IDENTITY, Vector3(xx, yy, sgn * (pd * 0.5))))
                var t: float = M.noise01(float(i) * 0.73 + float(row) * 2.1, float(f) * 1.7)
                var mm: float = 0.86 + t * 0.26
                scol.append(Color(mm, mm * 0.985, mm * 0.95, 1.0))
            for i in range(9):
                var zz: float = -pd * 0.5 + (pd / 9.0) * (float(i) + 0.5) + off
                if zz > pd * 0.5:
                    zz -= pd
                sxf.append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(sgn * (pw * 0.5), yy, zz)))
                var t2: float = M.noise01(float(i) * 0.61 + 3.7, float(row) * 1.9 + float(f) * 4.3)
                var mm2: float = 0.86 + t2 * 0.26
                scol.append(Color(mm2, mm2 * 0.985, mm2 * 0.95, 1.0))
    M.multis(root, "PlinthStones", stone_mesh, sxf, scol, stone_mat)
    # 墙脚石裙 / 勒脚（门洞位置留空；外表面比墙皮外凸 0.05）
    M.box(root, Vector3(2.90, 0.40, 0.22), Vector3(-2.30, fy + 0.20, hd + 0.03), M.C_STONE_DARK, 0.0, {"outline": 0.03})
    M.box(root, Vector3(2.90, 0.40, 0.22), Vector3(2.30, fy + 0.20, hd + 0.03), M.C_STONE_DARK, 0.0, {"outline": 0.03})
    M.box(root, Vector3(w + 0.04, 0.40, 0.22), Vector3(0.0, fy + 0.20, -hd - 0.03), M.C_STONE_DARK, 0.0, {"outline": 0.03})
    M.box(root, Vector3(0.22, 0.42, d + 0.02), Vector3(-hw - 0.03, fy + 0.22, 0.0), M.C_STONE_DARK, 0.0, {"outline": 0.03})
    M.box(root, Vector3(0.22, 0.42, d + 0.02), Vector3(hw + 0.03, fy + 0.22, 0.0), M.C_STONE_DARK, 0.0, {"outline": 0.03})

# ============================================================
# 1.5) 门廊台阶：3 级 x0.14（Lead 目标），run 0.30，末级埋到地形
# ============================================================
static func _porch_steps(root: Node3D, C: Dictionary) -> void:
    var deck_top: float = C["deck_top"]        # 0.42
    var run: float = 0.30
    var n: int = 3
    var rise: float = 0.14
    var z_top: float = 4.70
    var widths: Array = [2.60, 2.40, 2.20]
    var stones: Array = [M.C_STONE, M.C_STONE_DARK]
    # 台阶前缘实际地形（局部高度）
    var wpos: Vector3 = _world(root, Vector3(0.0, 0.0, z_top + run * float(n) + 0.05))
    var ground_local: float = M.terrain_height(wpos.x, wpos.z) - root.position.y
    var bottom_y: float = ground_local + 0.02
    var steps := Node3D.new()
    steps.name = "PorchSteps"
    root.add_child(steps)
    for i in range(n):
        var ty: float = deck_top - rise * float(i + 1)
        var h: float = ty - bottom_y + 0.90
        var zc: float = z_top + run * (float(i) + 0.5)
        var wd: float = widths[i]
        M.box(steps, Vector3(wd, h, run), Vector3(0.0, ty - h * 0.5, zc), stones[i % 2], 0.0, {"outline": 0.025})
    steps.set_meta("step_count", n)
    steps.set_meta("rise", rise)
    steps.set_meta("run", run)
    steps.set_meta("top_y", deck_top)
    steps.set_meta("bottom_y", bottom_y)
    steps.set_meta("z_top", z_top)
    # 台阶两侧望柱 + 顺坡扶手 + 栏杆条（与门廊栏杆同高衔接）
    var z_newel: float = z_top + run * float(n)      # 5.60
    var y_deck_rail: float = deck_top + 0.80         # 1.22
    var y_newel_top: float = bottom_y + 0.85
    for sx in [-1.0, 1.0]:
        var nb: float = ground_local - 0.35
        var nh: float = y_newel_top - nb
        M.box(root, Vector3(0.10, nh, 0.10), Vector3(sx * 1.38, nb + nh * 0.5, z_newel), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
        var dy: float = y_newel_top - y_deck_rail
        var dz: float = z_newel - 4.60
        var rlen: float = sqrt(dy * dy + dz * dz)
        var rot_x: float = atan2(-dy, dz)
        M.box_rot(root, Vector3(0.09, 0.09, rlen + 0.06), Vector3(sx * 1.38, (y_newel_top + y_deck_rail) * 0.5, (z_newel + 4.60) * 0.5), M.C_WOOD, Vector3(rot_x, 0.0, 0.0), {"outline": 0.02})
        for k in range(n):
            var zc2: float = z_top + run * (float(k) + 0.5)
            var by2: float = deck_top - rise * float(k + 1)
            var f2: float = (zc2 - 4.60) / dz
            var ry2: float = y_deck_rail + (y_newel_top - y_deck_rail) * f2
            var bh2: float = ry2 - by2 - 0.02
            M.box(root, Vector3(0.05, bh2, 0.05), Vector3(sx * 1.38, by2 + bh2 * 0.5, zc2), M.C_WOOD_DARK, 0.0, {})

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
    var wt: float = C["wall_t"]
    var roof_base: float = C["roof_base"]
    var zf: float = hd - wt * 0.5      # 2.95 前/后墙中心
    var zb: float = -(hd - wt * 0.5)   # -2.95
    var xb: float = hw - wt * 0.5      # 3.65 侧墙中心
    var y0: float = fy
    var yt: float = roof_base
    var wall_mat: Color = M.C_WALL
    var yo: Dictionary = {"outline": 0.03}
    # ---- 前墙(+Z)：13 段围真实洞口（门 x±0.57 y0.55..2.49；窗 x±[1.80,2.80] y1.455..2.605；阁楼窗下部 x±0.75 y3.27..3.73）----
    M.box(root, Vector3(1.00, wh, wt), Vector3(-3.30, fy + wh * 0.5, zf), wall_mat, 0.0, yo)                       # [-3.80,-2.80]
    M.box(root, Vector3(1.00, 0.905, wt), Vector3(-2.30, 1.0025, zf), wall_mat, 0.0, yo)                          # 左窗下
    M.box(root, Vector3(1.00, 1.125, wt), Vector3(-2.30, 3.1675, zf), wall_mat, 0.0, yo)                          # 左窗上
    M.box(root, Vector3(1.05, wh, wt), Vector3(-1.275, fy + wh * 0.5, zf), wall_mat, 0.0, yo)                     # [-1.80,-0.75]
    M.box(root, Vector3(0.18, 1.94, wt), Vector3(-0.66, 1.52, zf), wall_mat, 0.0, yo)                             # 门左垛
    M.box(root, Vector3(0.18, 0.78, wt), Vector3(-0.66, 2.88, zf), wall_mat, 0.0, yo)                             # 门左顶段
    M.box(root, Vector3(1.14, 0.78, wt), Vector3(0.0, 2.88, zf), wall_mat, 0.0, yo)                               # 门顶段
    M.box(root, Vector3(0.18, 1.94, wt), Vector3(0.66, 1.52, zf), wall_mat, 0.0, yo)                               # 门右垛
    M.box(root, Vector3(0.18, 0.78, wt), Vector3(0.66, 2.88, zf), wall_mat, 0.0, yo)                               # 门右顶段
    M.box(root, Vector3(1.05, wh, wt), Vector3(1.275, fy + wh * 0.5, zf), wall_mat, 0.0, yo)                      # [0.75,1.80]
    M.box(root, Vector3(1.00, 0.905, wt), Vector3(2.30, 1.0025, zf), wall_mat, 0.0, yo)                           # 右窗下
    M.box(root, Vector3(1.00, 1.125, wt), Vector3(2.30, 3.1675, zf), wall_mat, 0.0, yo)                           # 右窗上
    M.box(root, Vector3(1.00, wh, wt), Vector3(3.30, fy + wh * 0.5, zf), wall_mat, 0.0, yo)                       # [2.80,3.80]
    # ---- 侧墙(±X)：窗洞 z-0.80..0.20 y1.45..2.40 → 各 4 段 ----
    for sx in [-1.0, 1.0]:
        M.box(root, Vector3(wt, wh, 2.00), Vector3(sx * xb, fy + wh * 0.5, -1.80), wall_mat, 0.0, yo)
        M.box(root, Vector3(wt, 0.90, 1.00), Vector3(sx * xb, 1.00, -0.30), wall_mat, 0.0, yo)
        M.box(root, Vector3(wt, 1.33, 1.00), Vector3(sx * xb, 3.065, -0.30), wall_mat, 0.0, yo)
        M.box(root, Vector3(wt, wh, 2.60), Vector3(sx * xb, fy + wh * 0.5, 1.50), wall_mat, 0.0, yo)
    # ---- 后墙(-Z)：窗 x-0.25..0.65（0.90 宽）y1.45..2.35 → 4 段 ----
    M.box(root, Vector3(3.55, wh, wt), Vector3(-2.025, fy + wh * 0.5, zb), wall_mat, 0.0, yo)
    M.box(root, Vector3(0.90, 0.90, wt), Vector3(0.20, 1.00, zb), wall_mat, 0.0, yo)
    M.box(root, Vector3(0.90, 1.38, wt), Vector3(0.20, 3.04, zb), wall_mat, 0.0, yo)
    M.box(root, Vector3(3.15, wh, wt), Vector3(2.225, fy + wh * 0.5, zb), wall_mat, 0.0, yo)
    # ---- 半木结构：四角立板 + 圈梁 + 门窗柱/过梁 + 斜撑 ----
    for sx in [-1.0, 1.0]:
        for sz in [-1.0, 1.0]:
            M.box(root, Vector3(0.30, wh - 0.04, 0.16), Vector3(sx * 3.64, fy + 1.57, sz * 3.07), M.C_WOOD_DARK, 0.0, yo)
            M.box(root, Vector3(0.16, wh - 0.04, 0.30), Vector3(sx * 3.77, fy + 1.57, sz * 2.94), M.C_WOOD_DARK, 0.0, yo)
    # 前/后/侧顶圈梁
    M.box(root, Vector3(3.05, 0.26, 0.20), Vector3(-2.275, 3.59, zf + 0.135), M.C_WOOD_DARK, 0.0, yo)
    M.box(root, Vector3(3.05, 0.26, 0.20), Vector3(2.275, 3.59, zf + 0.135), M.C_WOOD_DARK, 0.0, yo)
    M.box(root, Vector3(w + 0.26, 0.26, 0.20), Vector3(0.0, 3.59, zb - 0.135), M.C_WOOD_DARK, 0.0, yo)
    M.box(root, Vector3(0.18, 0.22, d + 0.26), Vector3(-3.77, 3.62, 0.0), M.C_WOOD_DARK, 0.0, yo)
    M.box(root, Vector3(0.18, 0.22, d + 0.26), Vector3(3.77, 3.62, 0.0), M.C_WOOD_DARK, 0.0, yo)
    # 门/窗木构
    M.box(root, Vector3(0.24, 2.71, 0.18), Vector3(-0.80, 1.905, zf + 0.14), M.C_WOOD_DARK, 0.0, yo)
    M.box(root, Vector3(0.24, 2.71, 0.18), Vector3(0.80, 1.905, zf + 0.14), M.C_WOOD_DARK, 0.0, yo)
    M.box(root, Vector3(1.67, 0.18, 0.15), Vector3(0.0, 2.72, zf + 0.14), M.C_WOOD_DARK, 0.0, yo)
    M.box(root, Vector3(2.84, 0.16, 0.14), Vector3(-2.22, 1.36, zf + 0.15), M.C_WOOD_DARK, 0.0, yo)
    M.box(root, Vector3(2.84, 0.16, 0.14), Vector3(2.22, 1.36, zf + 0.15), M.C_WOOD_DARK, 0.0, yo)
    # 四角斜撑（前/后山墙 + 侧墙）
    for sx in [-1.0, 1.0]:
        for sz in [-1.0, 1.0]:
            M.box_rot(root, Vector3(0.72, 0.16, 0.11), Vector3(sx * 3.25, 3.37, sz * (hd - 0.015)), M.C_WOOD_DARK, Vector3(0.0, 0.0, -sx * 0.72), yo)
            M.box_rot(root, Vector3(0.11, 0.16, 0.72), Vector3(sx * (hw - 0.015), 3.37, sz * 2.55), M.C_WOOD_DARK, Vector3(sz * 0.72, 0.0, 0.0), yo)

# ============================================================
# 3) 窗：前窗 1.00x1.15 x2 / 侧窗 1.00x0.95 / 后窗 0.90x0.90
# ============================================================
static func _windows(root: Node3D, C: Dictionary) -> void:
    var fy: float = C["fy"]
    var hd: float = C["hd"]
    var hw: float = C["hw"]
    var wt: float = C["wall_t"]
    var zf: float = hd - wt * 0.5
    var xb: float = hw - wt * 0.5
    # 前窗 x2：中心 x=±2.30，中心 y=fy+1.48
    for i in range(2):
        var sx: float = -1.0 + 2.0 * float(i)
        var pivot := Node3D.new()
        pivot.name = "WindowFront_%d" % i
        pivot.position = Vector3(sx * 2.30, fy + 1.48, zf)
        root.add_child(pivot)
        _window_assembly(root, pivot, C, 1.00, 1.15, true)
    # 侧窗：中心 z=-0.30，中心 y=fy+1.375
    var piv_l := Node3D.new()
    piv_l.name = "WindowSideL"
    piv_l.position = Vector3(-xb, 1.925, -0.30)
    piv_l.rotation.y = -PI * 0.5
    root.add_child(piv_l)
    _window_assembly(root, piv_l, C, 1.00, 0.95, false)
    var piv_r := Node3D.new()
    piv_r.name = "WindowSideR"
    piv_r.position = Vector3(xb, 1.925, -0.30)
    piv_r.rotation.y = PI * 0.5
    root.add_child(piv_r)
    _window_assembly(root, piv_r, C, 1.00, 0.95, false)
    # 后窗：中心 x=0.20，中心 y=1.90（=fy+1.35）
    var piv_b := Node3D.new()
    piv_b.name = "WindowBack"
    piv_b.position = Vector3(0.20, 1.90, -zf)
    piv_b.rotation.y = PI
    root.add_child(piv_b)
    _window_assembly(root, piv_b, C, 0.90, 0.90, false)

static func _window_assembly(root: Node3D, pivot: Node3D, C: Dictionary, ow: float, oh: float, is_front: bool) -> void:
    var wt: float = C["wall_t"]
    var vdepth: float = wt + 0.14
    var rdepth: float = wt + 0.08
    var hdepth: float = wt + 0.12
    var wood: Color = M.C_WOOD
    var wood_l: Color = M.C_WOOD_LIGHT
    var wood_d: Color = M.C_WOOD_DARK
    var yo: Dictionary = {"outline": 0.02}
    # 玻璃（共享材质；凹入洞口）
    var glass := MeshInstance3D.new()
    var gm := BoxMesh.new()
    gm.size = Vector3(ow - 0.02, oh - 0.02, 0.035)
    glass.mesh = gm
    glass.material_override = C["glass_mat"]
    glass.name = "Glass"
    glass.position = Vector3(0.0, 0.0, 0.01)
    pivot.add_child(glass)
    # 窗框：左右竖框 + 上下横框
    M.box(pivot, Vector3(0.14, oh + 0.18, vdepth), Vector3(-(ow * 0.5 + 0.02), 0.0, 0.0), wood, 0.0, yo)
    M.box(pivot, Vector3(0.14, oh + 0.18, vdepth), Vector3(ow * 0.5 + 0.02, 0.0, 0.0), wood, 0.0, yo)
    M.box(pivot, Vector3(ow + 0.04, 0.12, rdepth), Vector3(0.0, oh * 0.5 + 0.02, 0.0), wood_d, 0.0, yo)
    M.box(pivot, Vector3(ow + 0.04, 0.12, rdepth), Vector3(0.0, -(oh * 0.5 + 0.02), 0.0), wood_d, 0.0, yo)
    # 外/内窗台
    M.box(pivot, Vector3(ow + 0.32, 0.09, 0.22), Vector3(0.0, -(oh * 0.5 + 0.14), wt * 0.5 + 0.09), wood, 0.0, {"outline": 0.02})
    M.box(pivot, Vector3(ow + 0.24, 0.08, 0.20), Vector3(0.0, -(oh * 0.5 + 0.12), -(wt * 0.5 + 0.07)), wood_l, 0.0, {"outline": 0.02})
    # 窗楣
    M.box(pivot, Vector3(ow + 0.34, 0.14, hdepth), Vector3(0.0, oh * 0.5 + 0.15, 0.0), wood_d, 0.0, yo)
    # 格子窗棂（2x2）
    for sx in [-1.0, 1.0]:
        M.box(pivot, Vector3(0.05, oh - 0.04, 0.05), Vector3(sx * ow / 6.0, 0.0, 0.06), wood_d, 0.0, {})
    for sy in [-1.0, 1.0]:
        M.box(pivot, Vector3(ow - 0.04, 0.05, 0.03), Vector3(0.0, sy * oh / 6.0, 0.06), wood_d, 0.0, {})
    # 窗外暖光晕 + 点光锚点
    var halo: MeshInstance3D = M.halo(root, pivot.transform * Vector3(0.0, 0.0, wt * 0.5 + 0.45), 1.30, Color(2.2, 1.4, 0.7, 1.0))
    C["window_halos"].append(halo)
    C["win_lights"].append({"pos": _world(root, pivot.transform * Vector3(0.0, 0.0, wt * 0.5 + 0.70))})
    if is_front:
        C["front_window_world"].append(_world(root, pivot.transform * Vector3(0.0, 0.0, 0.02)))

# ============================================================
# 4) 门：半圆拱（内 R0.52 / 外 R0.66）+ 气窗 R0.50 + 5 板门扇 + 门轴
# ============================================================
static func _door(root: Node3D, C: Dictionary) -> void:
    var fy: float = C["fy"]
    var hd: float = C["hd"]
    var wt: float = C["wall_t"]
    var zf: float = hd - wt * 0.5
    var spring: float = fy + 1.42              # 1.97 拱脚
    # 拱形门框（外凸半环）
    _door_arch_ring(root, C)
    # 锁石（拱顶）
    M.box(root, Vector3(0.26, 0.24, 0.24), Vector3(0.0, spring + 0.66 + 0.14, zf + 0.10), M.C_WOOD_LIGHT, 0.0, {"outline": 0.025})
    # 门洞上部拱形补墙（矩形洞口的两个拱肩）
    _door_spandrel(root, C)
    # 拱脚立柱
    # 拱脚立柱：内表面 x=±0.57 → 门洞净宽 1.14（与墙洞一致）
    M.box(root, Vector3(0.30, 1.42, 0.30), Vector3(-0.72, fy + 0.71, zf + 0.05), M.C_WOOD_DARK, 0.0, {"outline": 0.025})
    M.box(root, Vector3(0.30, 1.42, 0.30), Vector3(0.72, fy + 0.71, zf + 0.05), M.C_WOOD_DARK, 0.0, {"outline": 0.025})
    # 门槛石
    M.box(root, Vector3(1.34, 0.12, 0.52), Vector3(0.0, fy - 0.06, hd + 0.12), M.C_STONE, 0.0, {"outline": 0.02})
    # 门扇 pivot（合页在左边缘 x=-0.50；main 把 rotation.y tween 到 -1.85 开门）
    var pivot := Node3D.new()
    pivot.name = "DoorPivot"
    pivot.position = Vector3(-0.50, fy, hd - 0.06)
    pivot.set_meta("no_batch", true)
    root.add_child(pivot)
    C["door_pivot"] = pivot
    var wood: Color = M.C_WOOD
    var wood_l: Color = M.C_WOOD_LIGHT
    var wood_d: Color = M.C_WOOD_DARK
    # 5 块竖板（门扇 1.00 宽 x 1.40 高）
    for i in range(5):
        var c: Color = wood_l if i % 2 == 0 else wood
        M.box(pivot, Vector3(0.20, 1.40, 0.09), Vector3(0.10 + 0.20 * float(i), 0.70, 0.0), c, 0.0, {"bands": 4.0, "outline": 0.02})
    # 边梃 + 3 横档
    M.box(pivot, Vector3(0.08, 1.44, 0.12), Vector3(0.04, 0.72, 0.0), wood_d, 0.0, {"outline": 0.02})
    M.box(pivot, Vector3(0.08, 1.44, 0.12), Vector3(0.96, 0.72, 0.0), wood_d, 0.0, {"outline": 0.02})
    for yy in [0.16, 0.70, 1.24]:
        M.box(pivot, Vector3(1.00, 0.10, 0.11), Vector3(0.50, yy, 0.0), wood_d, 0.0, {"outline": 0.02})
    # 气窗（半圆盘 R0.50 + 拱带 + 窗棂）
    _door_fanlight(pivot, C)
    # ---- T1/T5 可测结构：门洞净尺寸/拱半径/把手高（build 返回与 root meta 均可读）----
    C["door_opening"] = Vector3(1.14, 1.94, C["wall_t"])
    C["door_clear"] = {
        "w": 1.14, "h": 1.94,
        "spring_y": spring, "arch_ri": 0.52, "arch_ro": 0.66,
        "fanlight_r": 0.50, "handle_h": 0.95,
        "pivot_local": Vector3(-0.50, fy, hd - 0.06),
        "leaf_w": 1.00, "leaf_h": 1.40,
    }
    root.set_meta("door_opening", C["door_opening"])
    root.set_meta("door_clear", C["door_clear"])

static func _door_spandrel(root: Node3D, C: Dictionary) -> void:
    var fyv: float = C["fy"]
    var hd: float = C["hd"]
    var wt: float = C["wall_t"]
    var zf: float = hd - wt * 0.5
    var yc: float = fyv + 1.42          # 1.97
    var ytop: float = fyv + 1.94        # 2.49
    var half: float = 0.57
    var ra: float = 0.52
    var n: int = 16
    var zfr: float = zf + wt * 0.5      # 3.10
    var zbk: float = zf - wt * 0.5      # 2.80
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var front_n := Vector3(0.0, 0.0, 1.0)
    var back_n := Vector3(0.0, 0.0, -1.0)
    var pts_in: Array = []
    var pts_out: Array = []
    for i in range(n + 1):
        var a: float = PI * float(i) / float(n)
        var ca: float = cos(a)
        var sa: float = sin(a)
        var ro_a: float = (ytop - yc) / maxf(sa, 0.0001)
        var ro_b: float = half / maxf(absf(ca), 0.0001)
        var ro: float = minf(ro_a, ro_b)
        pts_in.append(Vector3(ra * ca, yc + ra * sa, 0.0))
        pts_out.append(Vector3(ro * ca, yc + ro * sa, 0.0))
    for i in range(n):
        var pi0: Vector3 = pts_in[i]
        var pi1: Vector3 = pts_in[i + 1]
        var po0: Vector3 = pts_out[i]
        var po1: Vector3 = pts_out[i + 1]
        # 前/后环面（矩形洞外、圆拱外的补墙）
        _st_quad_n(st,
            Vector3(pi0.x, pi0.y, zfr), Vector3(po0.x, po0.y, zfr),
            Vector3(po1.x, po1.y, zfr), Vector3(pi1.x, pi1.y, zfr), front_n)
        _st_quad_n(st,
            Vector3(pi0.x, pi0.y, zbk), Vector3(po0.x, po0.y, zbk),
            Vector3(po1.x, po1.y, zbk), Vector3(pi1.x, pi1.y, zbk), back_n)
        # 内弧侧壁（朝向门洞）
        var amid: float = PI * (float(i) + 0.5) / float(n)
        var n_in := Vector3(-cos(amid), -sin(amid), 0.0)
        _st_quad_n(st,
            Vector3(pi0.x, pi0.y, zfr), Vector3(pi1.x, pi1.y, zfr),
            Vector3(pi1.x, pi1.y, zbk), Vector3(pi0.x, pi0.y, zbk), n_in)
    # 两底封板（拱脚处，朝下）
    var down_n := Vector3(0.0, -1.0, 0.0)
    _st_quad_n(st, Vector3(ra, yc, zfr), Vector3(half, yc, zfr), Vector3(half, yc, zbk), Vector3(ra, yc, zbk), down_n)
    _st_quad_n(st, Vector3(-half, yc, zfr), Vector3(-ra, yc, zfr), Vector3(-ra, yc, zbk), Vector3(-half, yc, zbk), down_n)
    var mi := MeshInstance3D.new()
    mi.name = "DoorSpandrel"
    mi.mesh = st.commit()
    mi.material_override = M.toon_material(M.C_WALL, {"bands": 4.0, "outline": 0.02})
    mi.set_meta("no_batch", true)
    root.add_child(mi)

static func _door_arch_ring(root: Node3D, C: Dictionary) -> void:
    var fy: float = C["fy"]
    var hd: float = C["hd"]
    var wt: float = C["wall_t"]
    var zf: float = hd - wt * 0.5
    var yc: float = fy + 1.42          # 1.97 拱脚
    var ri: float = 0.52
    var ro: float = 0.66
    var n: int = 24
    var z_hi: float = zf + 0.19        # 3.14
    var z_lo: float = zf - 0.04        # 2.91
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var front_n := Vector3(0.0, 0.0, 1.0)
    var back_n := Vector3(0.0, 0.0, -1.0)
    for i in range(n):
        var a0: float = PI * float(i) / float(n)
        var a1: float = PI * float(i + 1) / float(n)
        var c0: float = cos(a0)
        var s0: float = sin(a0)
        var c1: float = cos(a1)
        var s1: float = sin(a1)
        var oi0_hi := Vector3(ro * c0, yc + ro * s0, z_hi)
        var oi1_hi := Vector3(ro * c1, yc + ro * s1, z_hi)
        var ii0_hi := Vector3(ri * c0, yc + ri * s0, z_hi)
        var ii1_hi := Vector3(ri * c1, yc + ri * s1, z_hi)
        var oi0_lo := Vector3(ro * c0, yc + ro * s0, z_lo)
        var oi1_lo := Vector3(ro * c1, yc + ro * s1, z_lo)
        var ii0_lo := Vector3(ri * c0, yc + ri * s0, z_lo)
        var ii1_lo := Vector3(ri * c1, yc + ri * s1, z_lo)
        var amid: float = PI * (float(i) + 0.5) / float(n)
        var n_out := Vector3(cos(amid), sin(amid), 0.0)
        var n_in := -n_out
        # 前后环面
        _st_quad_n(st, ii0_hi, oi0_hi, oi1_hi, ii1_hi, front_n)
        _st_quad_n(st, ii0_lo, oi0_lo, oi1_lo, ii1_lo, back_n)
        # 外弧壁 / 内弧壁
        _st_quad_n(st, oi0_hi, oi0_lo, oi1_lo, oi1_hi, n_out)
        _st_quad_n(st, ii0_hi, ii0_lo, ii1_lo, ii1_hi, n_in)
    # 两拱脚端面（朝下）
    var down_n := Vector3(0.0, -1.0, 0.0)
    _st_quad_n(st, Vector3(ro, yc, z_hi), Vector3(ro, yc, z_lo), Vector3(ri, yc, z_lo), Vector3(ri, yc, z_hi), down_n)
    _st_quad_n(st, Vector3(-ro, yc, z_hi), Vector3(-ro, yc, z_lo), Vector3(-ri, yc, z_lo), Vector3(-ri, yc, z_hi), down_n)
    var mi := MeshInstance3D.new()
    mi.name = "DoorArch"
    mi.mesh = st.commit()
    mi.material_override = M.toon_material(M.C_WOOD_DARK, {"bands": 4.0, "outline": 0.03})
    mi.set_meta("no_batch", true)
    root.add_child(mi)

static func _door_fanlight(pivot: Node3D, C: Dictionary) -> void:
    var cx: float = 0.50
    var cy: float = 1.40
    var r: float = 0.50
    var hz: float = 0.05
    var n: int = 14
    var wood: Color = M.C_WOOD
    var wood_d: Color = M.C_WOOD_DARK
    # 半圆盘（前/后面 + 弧壁 + 弦面）
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var front_n := Vector3(0.0, 0.0, 1.0)
    var back_n := Vector3(0.0, 0.0, -1.0)
    var center := Vector3(cx, cy, 0.0)
    for i in range(n):
        var a0: float = PI * float(i) / float(n)
        var a1: float = PI * float(i + 1) / float(n)
        var p0 := Vector3(cx + r * cos(a0), cy + r * sin(a0), hz)
        var p1 := Vector3(cx + r * cos(a1), cy + r * sin(a1), hz)
        var p0b := Vector3(cx + r * cos(a0), cy + r * sin(a0), -hz)
        var p1b := Vector3(cx + r * cos(a1), cy + r * sin(a1), -hz)
        _st_tri_n(st, center + Vector3(0.0, 0.0, hz), p0, p1, front_n)
        _st_tri_n(st, center + Vector3(0.0, 0.0, -hz), p0b, p1b, back_n)
        var amid: float = PI * (float(i) + 0.5) / float(n)
        var n_out := Vector3(cos(amid), sin(amid), 0.0)
        _st_quad_n(st, p0, p0b, p1b, p1, n_out)
    # 弦面（朝下）
    var down_n := Vector3(0.0, -1.0, 0.0)
    _st_quad_n(st, Vector3(cx - r, cy, hz), Vector3(cx + r, cy, hz), Vector3(cx + r, cy, -hz), Vector3(cx - r, cy, -hz), down_n)
    var mi := MeshInstance3D.new()
    mi.name = "DoorFanlight"
    mi.mesh = st.commit()
    mi.material_override = M.toon_material(wood, {"bands": 4.0, "outline": 0.02})
    pivot.add_child(mi)
    # 凸起拱带（拱形装饰，半径 rb0..rb1）
    var rb0: float = 0.38
    var rb1: float = 0.45
    var bz_hi: float = 0.085
    var bz_lo: float = 0.0505
    var st2 := SurfaceTool.new()
    st2.begin(Mesh.PRIMITIVE_TRIANGLES)
    for i in range(n):
        var a0: float = PI * float(i) / float(n)
        var a1: float = PI * float(i + 1) / float(n)
        var c0: float = cos(a0)
        var s0: float = sin(a0)
        var c1: float = cos(a1)
        var s1: float = sin(a1)
        var oi0_hi := Vector3(cx + rb1 * c0, cy + rb1 * s0, bz_hi)
        var oi1_hi := Vector3(cx + rb1 * c1, cy + rb1 * s1, bz_hi)
        var ii0_hi := Vector3(cx + rb0 * c0, cy + rb0 * s0, bz_hi)
        var ii1_hi := Vector3(cx + rb0 * c1, cy + rb0 * s1, bz_hi)
        var oi0_lo := Vector3(cx + rb1 * c0, cy + rb1 * s0, bz_lo)
        var oi1_lo := Vector3(cx + rb1 * c1, cy + rb1 * s1, bz_lo)
        var ii0_lo := Vector3(cx + rb0 * c0, cy + rb0 * s0, bz_lo)
        var ii1_lo := Vector3(cx + rb0 * c1, cy + rb0 * s1, bz_lo)
        var amid: float = PI * (float(i) + 0.5) / float(n)
        var n_out := Vector3(cos(amid), sin(amid), 0.0)
        _st_quad_n(st2, ii0_hi, oi0_hi, oi1_hi, ii1_hi, front_n)
        _st_quad_n(st2, ii0_lo, oi0_lo, oi1_lo, ii1_lo, back_n)
        _st_quad_n(st2, oi0_hi, oi0_lo, oi1_lo, oi1_hi, n_out)
        _st_quad_n(st2, ii0_hi, ii0_lo, ii1_lo, ii1_hi, -n_out)
    var down_n2 := Vector3(0.0, -1.0, 0.0)
    _st_quad_n(st2, Vector3(cx + rb1, cy, bz_hi), Vector3(cx + rb1, cy, bz_lo), Vector3(cx + rb0, cy, bz_lo), Vector3(cx + rb0, cy, bz_hi), down_n2)
    _st_quad_n(st2, Vector3(cx - rb1, cy, bz_hi), Vector3(cx - rb1, cy, bz_lo), Vector3(cx - rb0, cy, bz_lo), Vector3(cx - rb0, cy, bz_hi), down_n2)
    var mi2 := MeshInstance3D.new()
    mi2.name = "DoorFanlightTrim"
    mi2.mesh = st2.commit()
    mi2.material_override = M.toon_material(wood_d, {"bands": 4.0, "outline": 0.02})
    pivot.add_child(mi2)
    # 竖棂 + 弦线横档 + 门面竖条
    M.box(pivot, Vector3(0.055, 0.377, 0.05), Vector3(cx, cy + 0.1885, 0.055), wood_d, 0.0, {})
    M.box(pivot, Vector3(0.055, 0.337, 0.05), Vector3(cx - 0.164, cy + 0.1685, 0.055), wood_d, 0.0, {})
    M.box(pivot, Vector3(0.055, 0.337, 0.05), Vector3(cx + 0.164, cy + 0.1685, 0.055), wood_d, 0.0, {})
    M.box(pivot, Vector3(1.02, 0.09, 0.12), Vector3(cx, cy - 0.005, 0.0), wood_d, 0.0, {"outline": 0.02})
    for sx in [-1.0, 1.0]:
        M.box(pivot, Vector3(0.06, 1.41, 0.03), Vector3(cx + sx * 0.25, 0.71, sx * 0.055), wood_d, 0.0, {})
    # 金色把手 + 铜片 + 合页
    var knob := MeshInstance3D.new()
    var sm := SphereMesh.new()
    sm.radius = 0.075
    sm.height = 0.15
    sm.radial_segments = 8
    sm.rings = 5
    knob.mesh = sm
    knob.material_override = M.toon_material(Color("e0b45a"), {"bands": 4.0, "rim": 0.35})
    knob.position = Vector3(0.90, 0.95, 0.11)
    pivot.add_child(knob)
    M.box(pivot, Vector3(0.08, 0.22, 0.03), Vector3(0.90, 0.95, 0.065), Color("8a6a2e"), 0.0, {})
    for yy in [0.25, 1.15]:
        M.box(pivot, Vector3(0.07, 0.20, 0.12), Vector3(0.03, yy, 0.0), Color("3a3630"), 0.0, {})

# ============================================================
# 5) 屋顶：前山墙(带真实洞口) + 后山墙三棱柱 + 双坡屋面板 + 脊瓦/筒瓦/椽尾
# ============================================================
static func _roof(root: Node3D, C: Dictionary) -> void:
    var w: float = C["w"]
    var rh: float = C["rh"]
    var hd: float = C["hd"]
    var wt: float = C["wall_t"]
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
    # 前山墙（带 1.50x1.50 阁楼窗矩形洞口）+ 后山墙
    _front_gable(root, C)
    # 绕序修正版（M.prism 的盖面在 Godot 中是背面，会被主 pass 剔除）
    prism_front(root, w, rh, wt, Vector3(0.0, roof_base, -(hd - wt * 0.5)), M.C_WALL, 0.0, {"outline": 0.03})
    # 双坡屋面板
    for side in [-1.0, 1.0]:
        var down := Vector3(side * cp, -sp, 0.0)
        var nrm := Vector3(side * sp, cp, 0.0)
        var mid: Vector3 = Vector3(0.0, ridge_y, 0.0) + down * (slope_len * 0.5)
        M.box_rot(root, Vector3(slope_len, 0.14, roof_z), mid - nrm * 0.07, M.C_WOOD, Vector3(0.0, 0.0, -side * pitch), {"outline": 0.04})
    # 脊梁
    M.box(root, Vector3(0.34, 0.26, roof_z + 0.08), Vector3(0.0, ridge_y - 0.15, 0.0), M.C_WOOD_DARK, 0.0, {"outline": 0.03})
    # 脊瓦（MultiMesh）
    var cap: Dictionary = _roof_cap_data(C)
    M.multis(root, "RoofRidgeCaps", cap["mesh"], cap["xforms"], cap["colors"], cap["mat"])
    # 封檐板 / 博风板
    for side in [-1.0, 1.0]:
        M.box(root, Vector3(0.12, 0.26, roof_z + 0.02), Vector3(side * (eave_x - 0.05), eave_y - 0.10, 0.0), M.C_WOOD_DARK, 0.0, {"outline": 0.025})
        var down2 := Vector3(side * cp, -sp, 0.0)
        var nrm2 := Vector3(side * sp, cp, 0.0)
        var mid2: Vector3 = Vector3(0.0, ridge_y, 0.0) + down2 * (slope_len * 0.5)
        for sz in [-1.0, 1.0]:
            M.box_rot(root, Vector3(slope_len + 0.06, 0.24, 0.10), mid2 + nrm2 * 0.08 + Vector3(0.0, 0.0, sz * (hz + 0.02)), M.C_WOOD_DARK, Vector3(0.0, 0.0, -side * pitch), {"outline": 0.025})
    # 筒瓦（MultiMesh）+ 檐口椽尾（MultiMesh）
    var tile: Dictionary = _roof_tile_data(C)
    M.multis(root, "RoofTiles", tile["mesh"], tile["xforms"], tile["colors"], tile["mat"])
    var raf_mesh := BoxMesh.new()
    raf_mesh.size = Vector3(0.85, 0.11, 0.12)
    var raf_mat: ShaderMaterial = M.toon_material(M.C_WOOD_DARK, {"bands": 3.0})
    var rxf: Array = []
    var rn: int = int(roof_z / 0.50) + 1
    for side in [-1.0, 1.0]:
        var down3 := Vector3(side * cp, -sp, 0.0)
        var nrm3 := Vector3(side * sp, cp, 0.0)
        var base: Vector3 = Vector3(0.0, ridge_y, 0.0) + down3 * (slope_len - 0.18) - nrm3 * 0.20
        var bas := Basis(down3, nrm3, Vector3(0.0, 0.0, side))
        for i in range(rn):
            var zz: float = -3.45 + float(i) * 0.50
            rxf.append(Transform3D(bas, base + Vector3(0.0, 0.0, zz)))
    M.multis(root, "RoofRafters", raf_mesh, rxf, [], raf_mat)

static func _roof_cap_data(C: Dictionary) -> Dictionary:
    var ridge_y: float = C["ridge_y"]
    var roof_z: float = C["roof_z"]
    var mesh := CylinderMesh.new()
    mesh.top_radius = 0.12
    mesh.bottom_radius = 0.16
    mesh.height = 0.45
    mesh.radial_segments = 6
    mesh.rings = 1
    var xforms: Array = []
    var colors: Array = []
    var n: int = int(roof_z / 0.40) + 1
    var bas := Basis(Vector3(1.0, 0.0, 0.0), PI * 0.5)
    for i in range(n):
        var zz: float = -roof_z * 0.5 + 0.20 + float(i) * 0.40
        xforms.append(Transform3D(bas, Vector3(0.0, ridge_y + 0.08, zz)))
        var t: float = M.noise01(float(i) * 0.73, 1.7)
        var mm: float = 0.86 + t * 0.22
        colors.append(Color(mm, mm * 0.95, mm * 0.90, 1.0))
    var mat: ShaderMaterial = M.toon_material(M.C_TERRACOTTA_DARK, {"vertex_color": true, "bands": 3.0, "soft": 0.45})
    return {"mesh": mesh, "xforms": xforms, "colors": colors, "mat": mat}

static func _roof_tile_data(C: Dictionary) -> Dictionary:
    var ridge_y: float = C["ridge_y"]
    var roof_z: float = C["roof_z"]
    var slope_len: float = C["slope_len"]
    var cp: float = C["cp"]
    var sp: float = C["sp"]
    var ch_x: float = C["ch_x"]
    var ch_z: float = C["ch_z"]
    var hz: float = roof_z * 0.5
    var mesh := CylinderMesh.new()
    mesh.top_radius = 0.10
    mesh.bottom_radius = 0.12
    mesh.height = 0.38
    mesh.radial_segments = 6
    mesh.rings = 1
    var xforms: Array = []
    var colors: Array = []
    var row_step: float = 0.26
    var col_step: float = 0.23
    var rows: int = int((slope_len - 0.25) / row_step)
    var cols: int = int((roof_z - 0.22) / col_step)
    var zspan: float = float(cols - 1) * col_step
    for side in [-1.0, 1.0]:
        var down := Vector3(side * cp, -sp, 0.0)
        var nrm := Vector3(side * sp, cp, 0.0)
        var xax := Vector3(0.0, 0.0, -side)
        var bas := Basis(xax, down, xax.cross(down))
        for r in range(rows):
            var s: float = 0.22 + float(r) * row_step
            var odd: float = 0.115 if (r % 2) == 1 else 0.0
            for cix in range(cols):
                var zz: float = -zspan * 0.5 + float(cix) * col_step + odd
                if absf(zz) > hz - 0.12:
                    continue
                var pos: Vector3 = Vector3(side * cp * s, ridge_y - sp * s, 0.0) + nrm * 0.07 + Vector3(0.0, 0.0, zz)
                if absf(pos.x - ch_x) < 0.62 and absf(zz - ch_z) < 0.58:
                    continue
                xforms.append(Transform3D(bas, pos))
                var t: float = M.noise01(float(r) * 1.31 + float(cix) * 0.77, float(side) * 3.1)
                var mm: float = 0.90 + t * 0.18
                colors.append(Color(mm, mm * 0.95, mm * 0.88, 1.0))
    var mat: ShaderMaterial = M.toon_material(M.C_TERRACOTTA, {"vertex_color": true, "bands": 3.0, "soft": 0.45})
    return {"mesh": mesh, "xforms": xforms, "colors": colors, "mat": mat}

## 前山墙：五边形山墙 + 1.50x1.50 真实矩形洞口（洞口跨墙顶 + 山墙段），自建 mesh（前后山墙面 + 洞口侧壁）。
static func _front_gable(root: Node3D, C: Dictionary) -> void:
    var hw: float = C["hw"]
    var rh: float = C["rh"]
    var hd: float = C["hd"]
    var wt: float = C["wall_t"]
    var roof_base: float = C["roof_base"]
    var hole_hw: float = C["attic_hw"]       # 0.75
    var attic_top: float = C["attic_top"]
    var hole_top: float = attic_top - roof_base   # 1.04
    var sy: float = rh * (1.0 - hole_hw / hw)     # 洞口两侧屋面高 1.9825
    var zfr: float = wt * 0.5
    var zbk: float = -wt * 0.5
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var front_n := Vector3(0.0, 0.0, 1.0)
    var back_n := Vector3(0.0, 0.0, -1.0)
    # 前/后面：左三角 + 洞口上带 + 右三角
    for zf2 in [zbk, zfr]:
        var nn: Vector3 = front_n if zf2 > 0.0 else back_n
        var p_l0 := Vector3(-hw, 0.0, zf2)
        var p_l1 := Vector3(-hole_hw, 0.0, zf2)
        var p_l2 := Vector3(-hole_hw, sy, zf2)
        var p_r0 := Vector3(hole_hw, 0.0, zf2)
        var p_r1 := Vector3(hw, 0.0, zf2)
        var p_r2 := Vector3(hole_hw, sy, zf2)
        _st_tri_n(st, p_l0, p_l1, p_l2, nn)
        _st_tri_n(st, p_r0, p_r1, p_r2, nn)
        var a0 := Vector3(-hole_hw, hole_top, zf2)
        var a1 := Vector3(hole_hw, hole_top, zf2)
        var a2 := Vector3(hole_hw, sy, zf2)
        var a3 := Vector3(0.0, rh, zf2)
        var a4 := Vector3(-hole_hw, sy, zf2)
        _st_tri_n(st, a0, a1, a2, nn)
        _st_tri_n(st, a0, a2, a3, nn)
        _st_tri_n(st, a0, a3, a4, nn)
    # 洞口侧壁：左右 + 顶
    var left_n := Vector3(1.0, 0.0, 0.0)
    _st_quad_n(st, Vector3(-hole_hw, 0.0, zbk), Vector3(-hole_hw, 0.0, zfr), Vector3(-hole_hw, hole_top, zfr), Vector3(-hole_hw, hole_top, zbk), left_n)
    var right_n := Vector3(-1.0, 0.0, 0.0)
    _st_quad_n(st, Vector3(hole_hw, 0.0, zbk), Vector3(hole_hw, 0.0, zfr), Vector3(hole_hw, hole_top, zfr), Vector3(hole_hw, hole_top, zbk), right_n)
    var top_n := Vector3(0.0, -1.0, 0.0)
    _st_quad_n(st, Vector3(-hole_hw, hole_top, zbk), Vector3(-hole_hw, hole_top, zfr), Vector3(hole_hw, hole_top, zfr), Vector3(hole_hw, hole_top, zbk), top_n)
    var mi := MeshInstance3D.new()
    mi.name = "FrontGable"
    mi.mesh = st.commit()
    mi.material_override = M.toon_material(M.C_WALL, {"bands": 4.0, "outline": 0.03})
    mi.position = Vector3(0.0, roof_base, hd - wt * 0.5)
    root.add_child(mi)

# ============================================================
# SurfaceTool 三角/四边工具（显式法线；Godot 顺时针为正面）
# ============================================================
static func _st_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
    var n: Vector3 = (b - a).cross(c - a).normalized()
    for p in [a, b, c]:
        st.set_normal(n)
        st.add_vertex(p)

static func _st_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
    _st_tri(st, a, b, c)
    _st_tri(st, a, c, d)

static func _st_tri_n(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
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
# 6) 阁楼落地窗：1.50x1.50（洞口跨前墙 3.27..3.73 + 山墙 3.73..4.77）
# ============================================================
static func _attic_window(root: Node3D, C: Dictionary) -> void:
    var hd: float = C["hd"]
    var wt: float = C["wall_t"]
    var zf: float = hd - wt * 0.5
    var hwid: float = C["attic_hw"]
    var attic_floor: float = C["attic_floor"]
    var attic_top: float = C["attic_top"]
    var y0: float = attic_floor + 0.10     # 3.27
    var y1: float = attic_top              # 4.77
    var cy: float = (y0 + y1) * 0.5        # 4.02
    var node := Node3D.new()
    node.name = "AtticWindow"
    node.set_meta("width", hwid * 2.0)
    node.set_meta("height", y1 - y0)
    node.set_meta("center", Vector3(0.0, cy, hd))
    root.add_child(node)
    var wood: Color = M.C_WOOD
    var wood_l: Color = M.C_WOOD_LIGHT
    var wood_d: Color = M.C_WOOD_DARK
    # 外窗套
    var fx: float = hwid + 0.03
    var fz: float = zf + 0.08
    M.box(node, Vector3(0.12, (y1 - y0) + 0.24, 0.24), Vector3(-fx, 4.00, fz), wood, 0.0, {"outline": 0.025})
    M.box(node, Vector3(0.12, (y1 - y0) + 0.24, 0.24), Vector3(fx, 4.00, fz), wood, 0.0, {"outline": 0.025})
    M.box(node, Vector3(1.62, 0.09, 0.22), Vector3(0.0, y1 + 0.05, fz), wood_d, 0.0, {"outline": 0.02})
    M.box(node, Vector3(1.72, 0.12, 0.36), Vector3(0.0, y0 - 0.05, zf - 0.03), wood_l, 0.0, {"outline": 0.02})
    # 内窗套
    var iz: float = zf - 0.09
    M.box(node, Vector3(0.10, 1.70, 0.20), Vector3(-fx + 0.04, 4.01, iz), wood_l, 0.0, {"outline": 0.02})
    M.box(node, Vector3(0.10, 1.70, 0.20), Vector3(fx - 0.04, 4.01, iz), wood_l, 0.0, {"outline": 0.02})
    M.box(node, Vector3(1.60, 0.09, 0.18), Vector3(0.0, y1 + 0.01, iz), wood_l, 0.0, {"outline": 0.02})
    # 双层玻璃
    var g_out := MeshInstance3D.new()
    var gm := BoxMesh.new()
    gm.size = Vector3(hwid * 2.0 - 0.04, (y1 - y0) - 0.06, 0.02)
    g_out.mesh = gm
    g_out.material_override = C["attic_outer_glass"]
    g_out.position = Vector3(0.0, cy, zf + 0.03)
    node.add_child(g_out)
    var g_in := MeshInstance3D.new()
    var gm2 := BoxMesh.new()
    gm2.size = Vector3(hwid * 2.0 - 0.08, (y1 - y0) - 0.10, 0.02)
    g_in.mesh = gm2
    g_in.material_override = C["attic_inner_glass"]
    g_in.position = Vector3(0.0, cy, zf - 0.03)
    node.add_child(g_in)
    # 3x3 窗棂
    for sx in [-1.0, 1.0]:
        M.box(node, Vector3(0.06, (y1 - y0) - 0.10, 0.09), Vector3(sx * hwid / 3.0, cy, zf + 0.09), wood_d, 0.0, {})
    for ky in [1, 2]:
        var yy: float = y0 + (y1 - y0) * float(ky) / 3.0
        M.box(node, Vector3(hwid * 2.0 - 0.10, 0.06, 0.05), Vector3(0.0, yy, zf + 0.09), wood_d, 0.0, {})
    C["attic_window_world"] = _world(root, Vector3(0.0, cy, hd + 0.02))

# ============================================================
# 7) 烟囱（顶面 = ridge_y + 0.35 = 6.55）
# ============================================================
static func _chimney(root: Node3D, C: Dictionary) -> void:
    var ch_x: float = C["ch_x"]
    var ch_z: float = C["ch_z"]
    var ch_top: float = C["ch_top"]
    var ridge_y: float = C["ridge_y"]
    var pitch: float = C["pitch"]
    var cp: float = C["cp"]
    var sp: float = C["sp"]
    # P8.2-01：烟囱分段。旧版一层段是一整块 (0.88,5.75,0.80)@z=ch_z，z 跨度
    # -3.00..-2.20，侵入一层室内 0.60m，把壁炉炉膛/火焰/壁炉光槽全包在体内
    # （P8 既有缺陷，非 P8.1 回归）。改为：屋面以上保持原轮廓，屋面以下退成墙内薄烟道。
    # 上半段（阁楼 + 屋面以上）：外观与原来一致，z 仍为 -3.00..-2.20。
    M.box(root, Vector3(0.88, 3.10, 0.80), Vector3(ch_x, 4.65, ch_z), M.C_STONE, 0.0, {"outline": 0.04})
    # 一层/裙墙段：0.26m 薄烟道埋进后墙体（墙 z=-3.10..-2.80），
    # 前后各留 0.01/0.03 偏移避免与墙面共面，室内外都看不到突变。
    M.box(root, Vector3(0.88, 2.70, 0.26), Vector3(ch_x, 1.79, -2.96), M.C_STONE, 0.0, {"outline": 0.04})
    # 石箍：y=1.60 那道原本只在一层室内可见（随侵入体一起消失）；保留 3.40/5.40 两道。
    for yy in [3.40, 5.40]:
        M.box(root, Vector3(1.00, 0.18, 0.92), Vector3(ch_x, yy, ch_z), M.C_STONE_DARK, 0.0, {"outline": 0.03})
    # 泛水板 / 泛水石 / 压顶
    var roof_y: float = ridge_y - absf(ch_x) * tan(pitch)
    M.box_rot(root, Vector3(1.70, 0.14, 1.30), Vector3(ch_x - sp * 0.03, roof_y + cp * 0.03, ch_z), M.C_STONE_DARK, Vector3(0.0, 0.0, pitch), {"outline": 0.03})
    M.box(root, Vector3(1.14, 0.28, 1.08), Vector3(ch_x, roof_y + 0.30, ch_z), M.C_STONE, 0.0, {"outline": 0.03})
    M.box(root, Vector3(1.10, 0.16, 1.02), Vector3(ch_x, ch_top - 0.08, ch_z), M.C_STONE, 0.0, {"outline": 0.03})
    M.box(root, Vector3(0.94, 0.14, 0.88), Vector3(ch_x, ch_top + 0.07, ch_z), M.C_STONE_DARK, 0.0, {"outline": 0.03})
    M.box(root, Vector3(0.46, 0.20, 0.42), Vector3(ch_x, ch_top + 0.25, ch_z), M.C_STONE, 0.0, {"outline": 0.03})

# ============================================================
# 8) 门廊：平台 / 栏杆 / 雨棚 / 吊灯 / 长椅花箱
# ============================================================
static func _porch(root: Node3D, C: Dictionary) -> void:
    var hd: float = C["hd"]
    var fy: float = C["fy"]
    var deck_top: float = C["deck_top"]
    var wood: Color = M.C_WOOD
    var wood_l: Color = M.C_WOOD_LIGHT
    var wood_d: Color = M.C_WOOD_DARK
    var yo: Dictionary = {"outline": 0.025}
    # 平台
    M.box(root, Vector3(5.80, 0.20, 1.60), Vector3(0.0, deck_top - 0.10, hd + 0.80), M.C_WOOD_DARK, 0.0, {"outline": 0.03})
    var plank_mesh := BoxMesh.new()
    plank_mesh.size = Vector3(5.70, 0.04, 0.30)
    var plank_mat: ShaderMaterial = M.toon_material(Color("8b6844"), {"vertex_color": true, "bands": 3.0})
    var pxf: Array = []
    var pcol: Array = []
    for i in range(5):
        pxf.append(Transform3D(Basis.IDENTITY, Vector3(0.0, deck_top + 0.02, hd + 0.17 + float(i) * 0.32)))
        var t: float = M.noise01(float(i) * 1.13, 2.7)
        var mm: float = 0.90 + t * 0.18
        pcol.append(Color(mm, mm * 0.97, mm * 0.92, 1.0))
    M.multis(root, "PorchPlanks", plank_mesh, pxf, pcol, plank_mat)
    # 石墩
    for sx in [-1.0, 1.0]:
        for zz in [3.30, 4.40]:
            M.box(root, Vector3(0.30, 1.20, 0.30), Vector3(sx * 2.55, -0.20, zz), M.C_STONE_DARK, 0.0, {"outline": 0.025})
    # 栏杆立柱 / 扶手 / 栏板条
    for sx in [-1.0, 1.0]:
        M.box(root, Vector3(0.11, 0.84, 0.11), Vector3(sx * 2.82, deck_top + 0.42, 3.25), wood, 0.0, yo)
        M.box(root, Vector3(0.11, 0.84, 0.11), Vector3(sx * 2.82, deck_top + 0.42, 4.60), wood, 0.0, yo)
        M.box(root, Vector3(0.11, 0.84, 0.11), Vector3(sx * 1.45, deck_top + 0.42, 4.60), wood, 0.0, yo)
        # 门廊扶手保留独立 MeshInstance（no_batch）：T4 栖点探针需按扶手顶面真实 BoxMesh 反查
        var rail_side: MeshInstance3D = M.box(root, Vector3(0.09, 0.08, 1.36), Vector3(sx * 2.82, deck_top + 0.80, 3.925), wood_d, 0.0, yo)
        rail_side.name = "PorchRailSide" + ("L" if sx < 0.0 else "R")
        rail_side.set_meta("no_batch", true)
        var rail_front: MeshInstance3D = M.box(root, Vector3(1.40, 0.08, 0.09), Vector3(sx * 2.135, deck_top + 0.80, 4.60), wood_d, 0.0, yo)
        rail_front.name = "PorchRailFront" + ("L" if sx < 0.0 else "R")
        rail_front.set_meta("no_batch", true)
    var bal_mesh := BoxMesh.new()
    bal_mesh.size = Vector3(0.05, 0.60, 0.05)
    var bal_mat: ShaderMaterial = M.toon_material(wood_d, {"bands": 3.0})
    var bxf: Array = []
    for sx in [-1.0, 1.0]:
        for i in range(4):
            bxf.append(Transform3D(Basis.IDENTITY, Vector3(sx * 2.82, deck_top + 0.40, 3.45 + float(i) * 0.28)))
        for i in range(4):
            bxf.append(Transform3D(Basis.IDENTITY, Vector3(sx * (1.60 + float(i) * 0.26), deck_top + 0.40, 4.60)))
    M.multis(root, "PorchBalusters", bal_mesh, bxf, [], bal_mat)
    # 雨棚（双坡）
    var p2: float = atan(0.60 / 3.45)
    var c2: float = cos(p2)
    var s2: float = sin(p2)
    var clen: float = sqrt(3.45 * 3.45 + 0.60 * 0.60)
    var ridge2: float = deck_top + 2.70
    var cz: float = hd + 0.95
    var cdepth: float = 1.90
    for side in [-1.0, 1.0]:
        var down := Vector3(side * c2, -s2, 0.0)
        var nrm := Vector3(side * s2, c2, 0.0)
        var mid: Vector3 = Vector3(0.0, ridge2, cz) + down * (clen * 0.5) - nrm * 0.05
        M.box_rot(root, Vector3(clen, 0.10, cdepth), mid, M.C_WOOD, Vector3(0.0, 0.0, -side * p2), {"outline": 0.03})
    var ridge_log := MeshInstance3D.new()
    var cl := CylinderMesh.new()
    cl.top_radius = 0.08
    cl.bottom_radius = 0.08
    cl.height = cdepth + 0.08
    cl.radial_segments = 8
    ridge_log.mesh = cl
    ridge_log.material_override = M.toon_material(wood, {"bands": 3.0})
    ridge_log.rotation.x = PI * 0.5
    ridge_log.position = Vector3(0.0, ridge2 + 0.03, cz)
    root.add_child(ridge_log)
    # 前山墙封板 / 两侧封板
    # 绕序修正版（原先整片显示成 outline 深藏青——prism 盖面绕序反了）
    prism_front(root, 6.90, 0.60, 0.12, Vector3(0.0, ridge2 - 0.60, cz + cdepth * 0.5 - 0.03), M.C_WALL, 0.0, {"outline": 0.03})
    for side in [-1.0, 1.0]:
        M.box(root, Vector3(0.09, 0.18, cdepth + 0.04), Vector3(side * 3.47, ridge2 - 0.66, cz), M.C_WALL, 0.0, yo)
    # 雨棚柱 / 横梁 / 斜撑
    for side in [-1.0, 1.0]:
        var post := MeshInstance3D.new()
        var cm := CylinderMesh.new()
        cm.top_radius = 0.10
        cm.bottom_radius = 0.13
        cm.height = 2.08
        cm.radial_segments = 10
        post.mesh = cm
        post.material_override = M.toon_material(wood, {"bands": 4.0, "outline": 0.02})
        post.position = Vector3(side * 2.62, 1.46, 4.55)
        root.add_child(post)
        M.box_rot(root, Vector3(0.62, 0.11, 0.10), Vector3(side * 2.02, 2.37, 4.55), wood_d, Vector3(0.0, 0.0, side * 0.70), yo)
    M.box(root, Vector3(5.70, 0.16, 0.12), Vector3(0.0, 2.52, 4.55), wood_d, 0.0, {"outline": 0.025})
    # 雨棚瓦
    var pt_mesh := CylinderMesh.new()
    pt_mesh.top_radius = 0.10
    pt_mesh.bottom_radius = 0.12
    pt_mesh.height = 0.38
    pt_mesh.radial_segments = 6
    pt_mesh.rings = 1
    var pt_xf: Array = []
    var pt_col: Array = []
    var p_rows: int = int((clen - 0.25) / 0.26)
    var p_cols: int = int(cdepth / 0.24)
    var p_span: float = float(p_cols - 1) * 0.24
    var pt_mat: ShaderMaterial = M.toon_material(M.C_TERRACOTTA, {"vertex_color": true, "bands": 3.0, "soft": 0.45})
    for side in [-1.0, 1.0]:
        var down := Vector3(side * c2, -s2, 0.0)
        var nrm := Vector3(side * s2, c2, 0.0)
        var xax := Vector3(0.0, 0.0, -side)
        var bas := Basis(xax, down, xax.cross(down))
        for r in range(p_rows):
            var s: float = 0.18 + float(r) * 0.26
            var odd: float = 0.12 if (r % 2) == 1 else 0.0
            for cix in range(p_cols):
                var zz: float = -p_span * 0.5 + float(cix) * 0.24 + odd
                var pos: Vector3 = Vector3(side * c2 * s, ridge2 - s2 * s, cz) + nrm * 0.06 + Vector3(0.0, 0.0, zz)
                pt_xf.append(Transform3D(bas, pos))
                var t: float = M.noise01(float(r) * 1.17 + float(cix) * 0.61, float(side) * 2.3)
                var mm: float = 0.90 + t * 0.18
                pt_col.append(Color(mm, mm * 0.95, mm * 0.88, 1.0))
    M.multis(root, "PorchTiles", pt_mesh, pt_xf, pt_col, pt_mat)
    # 对称吊灯 x2
    for sx in [-1.0, 1.0]:
        var lpos: Vector3 = C["lantern_pos"] if sx < 0.0 else C["lantern_pos_right"]
        var rod := MeshInstance3D.new()
        var rm := CylinderMesh.new()
        rm.top_radius = 0.018
        rm.bottom_radius = 0.018
        rm.height = 0.42
        rm.radial_segments = 6
        rod.mesh = rm
        rod.material_override = M.toon_material(Color("3a3630"), {"bands": 3.0})
        rod.position = lpos + Vector3(0.0, 0.38, 0.0)
        root.add_child(rod)
        var body := MeshInstance3D.new()
        var bm := BoxMesh.new()
        bm.size = Vector3(0.24, 0.32, 0.24)
        body.mesh = bm
        body.material_override = C["lantern_mat"]
        body.position = lpos
        root.add_child(body)
        M.box(root, Vector3(0.30, 0.05, 0.30), lpos + Vector3(0.0, 0.19, 0.0), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
        M.box(root, Vector3(0.28, 0.04, 0.28), lpos + Vector3(0.0, -0.18, 0.0), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
        var halo: MeshInstance3D = M.halo(root, lpos, 1.10, Color(2.4, 1.6, 0.8, 1.0))
        C["lantern_halos"].append(halo)
        if not C.has("lantern_halo"):
            C["lantern_halo"] = halo
    # 长椅（右侧）
    var bench_z: float = 3.80
    M.box(root, Vector3(0.42, 0.09, 1.10), Vector3(2.30, deck_top + 0.45, bench_z), wood, 0.0, yo)
    M.box(root, Vector3(0.08, 0.50, 1.10), Vector3(2.48, deck_top + 0.72, bench_z), wood_l, 0.0, yo)
    for sz in [-1.0, 1.0]:
        for sx in [-1.0, 1.0]:
            M.box(root, Vector3(0.07, 0.42, 0.07), Vector3(2.30 + sx * 0.15, deck_top + 0.21, bench_z + sz * 0.44), wood_d, 0.0, {})
    # 花箱 + 花
    var fl_mesh := SphereMesh.new()
    fl_mesh.radius = 0.07
    fl_mesh.height = 0.14
    fl_mesh.radial_segments = 8
    fl_mesh.rings = 5
    var fl_mat: ShaderMaterial = M.toon_material(M.C_FLOWER_PINK, {"bands": 4.0, "rim": 0.20})
    var fl_xf: Array = []
    var fl_col: Array = []
    for sx in [-1.0, 1.0]:
        M.box(root, Vector3(1.10, 0.22, 0.26), Vector3(sx * 2.30, 1.32, hd + 0.13), wood_d, 0.0, {"outline": 0.02})
        for k in range(4):
            fl_xf.append(Transform3D(Basis.IDENTITY, Vector3(sx * 2.30 - 0.39 + float(k) * 0.26, 1.50, hd + 0.13)))
            var ct: Color = M.C_FLOWER_PINK if k % 2 == 0 else M.C_FLOWER_YELLOW
            fl_col.append(ct)
    M.multis(root, "PorchFlowers", fl_mesh, fl_xf, fl_col, fl_mat)
    # 扫帚 / 小木牌
    M.cyl_rot(root, 0.018, 0.022, 0.98, Vector3(1.85, deck_top + 0.60, 3.35), wood, Vector3(0.16, 0.0, 0.22), {})
    M.box(root, Vector3(0.10, 0.26, 0.16), Vector3(1.85, deck_top + 0.15, 3.30), Color("c9a86a"), 0.0, {"outline": 0.02})
    M.box(root, Vector3(0.34, 0.24, 0.08), Vector3(1.15, fy + 1.45, hd - 0.05), wood_l, 0.0, {"outline": 0.02})
    M.box(root, Vector3(0.26, 0.04, 0.06), Vector3(1.15, fy + 1.50, hd - 0.02), M.C_WOOD_DARK, 0.0, {})

# ============================================================
# 9) 16 级 L 形楼梯（Flight A 沿 -Z 7 踏 + 平台第 8 级；Flight B 沿 -X 7 踏 + 第 16 级接阁楼）
#     rise 0.16375 / tread 0.26 / 通行宽 0.85 / 扶手高 0.85 / 平台 0.85x0.85
# ============================================================
static func _stairs(root: Node3D, C: Dictionary) -> void:
    var fy: float = C["fy"]
    var attic_floor: float = C["attic_floor"]
    var rise: float = C["stair_rise"]
    var tread: float = C["stair_tread"]
    var fa: Dictionary = C["stair_flight_a"]
    var fb: Dictionary = C["stair_flight_b"]
    var ax0: float = fa["x0"]
    var ax1: float = fa["x1"]
    var az0: float = fa["z0"]
    var az1: float = fa["z1"]
    var land_top: float = fa["land_top"]
    var bx1: float = fb["x1"]
    var bz0: float = fb["z0"]
    var bz1: float = fb["z1"]
    var acx: float = (ax0 + ax1) * 0.5
    var sw: float = ax1 - ax0                 # 0.85
    var wood: Color = M.C_WOOD
    var wood_l: Color = M.C_WOOD_LIGHT
    var wood_d: Color = M.C_WOOD_DARK
    var st := Node3D.new()
    st.name = "Staircase"
    st.set_meta("risers", 16)
    st.set_meta("rise", rise)
    st.set_meta("tread", tread)
    st.set_meta("width", sw)
    st.set_meta("land_top", land_top)
    st.set_meta("attic_floor", attic_floor)
    st.set_meta("hole_r1", C["stair_hole_r1"])
    st.set_meta("hole_r2", C["stair_hole_r2"])
    root.add_child(st)
    var yo: Dictionary = {"outline": 0.02}
    # ---------- Flight A：沿 -Z 上行，7 级踏面 + 第 8 级落在平台 ----------
    var a_run: float = az0 - az1                      # 1.82
    var a_rise_total: float = land_top - fy           # 1.31
    var a_len: float = sqrt(a_run * a_run + a_rise_total * a_rise_total)
    var a_ang: float = atan2(a_rise_total, a_run)
    for i in range(1, 8):
        var top: float = fy + float(i) * rise
        var zris: float = az0 - float(i - 1) * tread
        var t_mi := M.box(st, Vector3(sw, 0.06, tread + 0.05), Vector3(acx, top - 0.03, zris - tread * 0.5 + 0.02), wood_l, 0.0, yo)
        t_mi.name = "StairTreadA_%02d" % i
        t_mi.set_meta("step_level", i)
        var r_mi := M.box(st, Vector3(sw, rise, 0.035), Vector3(acx, top - rise * 0.5 - 0.03, zris + 0.0175), wood, 0.0, {})
        r_mi.name = "StairRiserA_%02d" % i
    # 两侧梯梁
    var a_mid_y: float = (fy + land_top) * 0.5 - cos(a_ang) * 0.17
    var a_mid_z: float = (az0 + az1) * 0.5 - sin(a_ang) * 0.17
    for sx in [-1.0, 1.0]:
        var s_mi := M.box_rot(st, Vector3(0.06, 0.32, a_len), Vector3(acx + sx * (sw * 0.5 - 0.04), a_mid_y, a_mid_z), wood_d, Vector3(a_ang, 0.0, 0.0), {"outline": 0.02})
        s_mi.name = "StairStringerA_%s" % ("L" if sx < 0.0 else "R")
    # 内侧扶手 + 栏杆条 + 起端/平台端望柱
    var ax_rail: float = ax0 + 0.03
    var ar_mi := M.box_rot(st, Vector3(0.07, 0.06, a_len - 0.06), Vector3(ax_rail, (fy + land_top) * 0.5 + 0.85, (az0 + az1) * 0.5), wood, Vector3(a_ang, 0.0, 0.0), {"outline": 0.02})
    ar_mi.name = "StairHandrailA"
    ar_mi.set_meta("handrail_top_offset", 0.85)
    for i in range(1, 8):
        var top2: float = fy + float(i) * rise
        var zris2: float = az0 - float(i - 1) * tread
        var bl_mi := M.box(st, Vector3(0.035, 0.88, 0.035), Vector3(ax_rail, top2 + 0.44, zris2 - tread * 0.5 + 0.02), wood_d, 0.0, {})
        bl_mi.name = "StairBalusterA_%02d" % i
    var nw0 := M.box(st, Vector3(0.10, 1.06, 0.10), Vector3(ax_rail, fy + 0.53, az0 + 0.05), wood, 0.0, yo)
    nw0.name = "StairNewelA_0"
    var nc0 := M.box(st, Vector3(0.14, 0.05, 0.14), Vector3(ax_rail, fy + 1.085, az0 + 0.05), wood_l, 0.0, {})
    nc0.name = "StairNewelCapA_0"
    var nw1 := M.box(st, Vector3(0.10, 1.06, 0.10), Vector3(ax_rail, land_top + 0.53, az1 + 0.05), wood, 0.0, yo)
    nw1.name = "StairNewelA_1"
    var nc1 := M.box(st, Vector3(0.14, 0.05, 0.14), Vector3(ax_rail, land_top + 1.085, az1 + 0.05), wood_l, 0.0, {})
    nc1.name = "StairNewelCapA_1"
    # ---------- 平台（第 8 级顶面）：z 从楼梯端 az1=-1.94 到后墙端 bz0=-2.79，0.85×0.85 ----------
    var land_size := Vector3(sw, 0.10, az1 - bz0)
    var land_mi := M.box(st, land_size, Vector3(acx, land_top - 0.05, (bz0 + az1) * 0.5), wood_l, 0.0, yo)
    land_mi.name = "StairLanding"
    land_mi.set_meta("landing_top", land_top)
    land_mi.set_meta("landing_size", land_size)
    var le_mi := M.box(st, Vector3(sw, 0.12, 0.05), Vector3(acx, land_top - 0.05, az1 + 0.01), wood_d, 0.0, {})
    le_mi.name = "StairLandingNose"
    # 平台支撑柱（到一层地面）
    var post_h: float = land_top - 0.10 - fy
    for sx in [-1.0, 1.0]:
        var lp := M.box(st, Vector3(0.10, post_h, 0.10), Vector3(acx + sx * 0.36, fy + post_h * 0.5, bz0 + 0.10), wood_d, 0.0, {"outline": 0.02})
        lp.name = "StairLandingPost_%s" % ("L" if sx < 0.0 else "R")
    # ---------- Flight B：沿 -X 上行 7 级 + 第 16 级踢面 ----------
    var b_run: float = fb["x0"] - bx1                 # 1.82
    var b_rise_total: float = attic_floor - land_top  # 1.31
    var b_len: float = sqrt(b_run * b_run + b_rise_total * b_rise_total)
    var b_ang: float = atan2(b_rise_total, b_run)
    var bcz: float = (bz0 + bz1) * 0.5
    for j in range(1, 8):
        var top3: float = land_top + float(j) * rise
        var xris: float = C["stair_flight_b"]["x0"] - float(j - 1) * tread
        var bt_mi := M.box(st, Vector3(tread + 0.05, 0.06, sw), Vector3(xris - tread * 0.5 + 0.02, top3 - 0.03, bcz), wood_l, 0.0, yo)
        bt_mi.name = "StairTreadB_%02d" % (8 + j)
        bt_mi.set_meta("step_level", 8 + j)
        var br_mi := M.box(st, Vector3(0.035, rise, sw), Vector3(xris - 0.0175, top3 - rise * 0.5 - 0.03, bcz), wood, 0.0, {})
        br_mi.name = "StairRiserB_%02d" % (8 + j)
    # 第 16 级（最后一踢面：梯面 3.006 → 阁楼 3.17）
    var lv15: float = fy + 15.0 * rise
    var lr_mi := M.box(st, Vector3(0.035, attic_floor - lv15, sw), Vector3(bx1 - 0.0175, (lv15 + attic_floor) * 0.5, bcz), wood, 0.0, {})
    lr_mi.name = "StairRiserB_16"
    # 两侧梯梁（沿 X 坡）
    var b_mid_x: float = (fb["x0"] + bx1) * 0.5 - cos(b_ang) * 0.17
    var b_mid_y: float = (land_top + attic_floor) * 0.5 - sin(b_ang) * 0.17
    for sz in [-1.0, 1.0]:
        var sb := M.box_rot(st, Vector3(b_len, 0.32, 0.06), Vector3(b_mid_x, b_mid_y, bcz + sz * (sw * 0.5 - 0.04)), wood_d, Vector3(0.0, 0.0, -b_ang), {"outline": 0.02})
        sb.name = "StairStringerB_%s" % ("L" if sz < 0.0 else "R")
    # 临空侧（+Z 边）扶手 + 栏杆条 + 两端望柱
    var b_rail_z: float = bz1 - 0.03
    var brl := M.box_rot(st, Vector3(b_len - 0.10, 0.06, 0.07), Vector3((fb["x0"] + bx1) * 0.5, (land_top + attic_floor) * 0.5 + 0.85, b_rail_z), wood, Vector3(0.0, 0.0, -b_ang), {"outline": 0.02})
    brl.name = "StairHandrailB"
    for j in range(1, 8):
        var top4: float = land_top + float(j) * rise
        var xris2: float = C["stair_flight_b"]["x0"] - float(j - 1) * tread
        var bb := M.box(st, Vector3(0.035, 0.88, 0.035), Vector3(xris2 - tread * 0.5 + 0.02, top4 + 0.44, b_rail_z), wood_d, 0.0, {})
        bb.name = "StairBalusterB_%02d" % (8 + j)
    var bn1 := M.box(st, Vector3(0.10, 1.02, 0.10), Vector3(fb["x0"] - 0.02, land_top + 0.51, b_rail_z), wood, 0.0, yo)
    bn1.name = "StairNewelB_0"
    var bnc1 := M.box(st, Vector3(0.14, 0.05, 0.14), Vector3(fb["x0"] - 0.02, land_top + 1.045, b_rail_z), wood_l, 0.0, {})
    bnc1.name = "StairNewelCapB_0"
    var bn2 := M.box(st, Vector3(0.10, 0.96, 0.10), Vector3(bx1 + 0.02, attic_floor + 0.48, b_rail_z), wood, 0.0, yo)
    bn2.name = "StairNewelB_1"
    var bnc2 := M.box(st, Vector3(0.14, 0.05, 0.14), Vector3(bx1 + 0.02, attic_floor + 0.985, b_rail_z), wood_l, 0.0, {})
    bnc2.name = "StairNewelCapB_1"
    # 平台临空侧立柱（与 Flight B 起端连续）
    # ---- T1/T5 可测结构：楼梯井/每级踏面/平台/扶手参数（合批后这些数据仍可从节点 meta 读）----
    var tanp: float = tan(float(C["pitch"]))
    var roof_under_off: float = 0.20
    var h_min: float = 99.0
    for i in range(1, 8):
        var tp: float = fy + float(i) * rise
        h_min = minf(h_min, float(C["ridge_y"]) - absf(acx) * tanp - roof_under_off - tp)
    h_min = minf(h_min, float(C["ridge_y"]) - absf(acx) * tanp - roof_under_off - land_top)
    for j in range(1, 8):
        var tp2: float = land_top + float(j) * rise
        var xr: float = C["stair_flight_b"]["x0"] - float(j - 1) * tread
        h_min = minf(h_min, float(C["ridge_y"]) - absf(xr) * tanp - roof_under_off - tp2)
    var stair_data: Dictionary = {
        "risers": 16, "rise": rise, "tread": tread, "width": sw, "handrail_h": 0.85,
        "land_top": land_top, "attic_floor": attic_floor,
        "flight_a_len": a_len, "flight_b_len": b_len,
        "hole_r1": C["stair_hole_r1"], "hole_r2": C["stair_hole_r2"],
        "landing_center": Vector3(acx, land_top, (bz0 + az1) * 0.5),
        "landing_size": land_size,
        "headroom_min": h_min,
        "treads": [],
    }
    for i in range(1, 8):
        stair_data["treads"].append({"level": i, "top": fy + float(i) * rise, "center": Vector3(acx, fy + float(i) * rise, az0 - float(i - 1) * tread - tread * 0.5 + 0.02), "size": Vector3(sw, 0.06, tread + 0.05)})
    for j in range(1, 8):
        stair_data["treads"].append({"level": 8 + j, "top": land_top + float(j) * rise, "center": Vector3(C["stair_flight_b"]["x0"] - float(j - 1) * tread - tread * 0.5 + 0.02, land_top + float(j) * rise, bcz), "size": Vector3(tread + 0.05, 0.06, sw)})
    stair_data["treads"].append({"level": 16, "top": attic_floor, "center": Vector3(bx1, attic_floor, bcz), "size": Vector3(0.035, 0.0, sw)})
    C["stairs"] = stair_data
    st.set_meta("stair_data", stair_data)
    root.set_meta("stairs", stair_data)
    IsleBatch.merge_static(st)

# ============================================================
# 10) 阁楼室内：L 形楼板开洞 / 天花 / 板条 / 洞口护栏 / 椽条 / 15 件家具
# ============================================================
static func _attic_interior(root: Node3D, C: Dictionary) -> void:
    var attic_floor: float = C["attic_floor"]     # 3.17
    var slab_t: float = C["attic_slab_t"]         # 0.20
    var hw: float = C["hw"]
    var hd: float = C["hd"]
    var ridge_y: float = C["ridge_y"]
    var pitch: float = C["pitch"]
    var cp: float = C["cp"]
    var sp: float = C["sp"]
    var slope_len: float = C["slope_len"]
    var wall_t: float = C["wall_t"]
    var ia := Node3D.new()
    ia.name = "AtticInterior"
    root.add_child(ia)
    # L 洞外的 3 块矩形区域（x0,x1,z0,z1；局部坐标，内净区 x±3.50 z±2.80）
    var zones: Array = [
        {"x0": -3.50, "x1": 0.82, "z0": -2.80, "z1": 2.80},
        {"x0": 0.82, "x1": 2.64, "z0": -1.94, "z1": 2.80},
        {"x0": 2.64, "x1": 3.50, "z0": -0.12, "z1": 2.80},
    ]
    # 结构楼板（3.005..3.17）
    for zr in zones:
        var zw: float = zr["x1"] - zr["x0"]
        var zd: float = zr["z1"] - zr["z0"]
        M.box(ia, Vector3(zw, slab_t, zd), Vector3((zr["x0"] + zr["x1"]) * 0.5, attic_floor - slab_t * 0.5, (zr["z0"] + zr["z1"]) * 0.5), Color("5f4733"), 0.0, {"outline": 0.02})
    # 阁楼地板板条（按 x 列切；步长 0.45）
    var plank_mesh := BoxMesh.new()
    plank_mesh.size = Vector3(1.0, 0.02, 1.0)
    var plank_mat: ShaderMaterial = M.toon_material(Color("8b6a49"), {"vertex_color": true, "bands": 3.0})
    var pxf: Array = []
    var pcol: Array = []
    for i in range(17):
        var xx: float = -3.37 + float(i) * 0.45
        var zr2: Dictionary = zones[0]
        if xx >= 2.64:
            zr2 = zones[2]
        elif xx >= 0.82:
            zr2 = zones[1]
        var seg_len: float = zr2["z1"] - zr2["z0"]
        if seg_len <= 0.01:
            continue
        var bas := Basis.IDENTITY.scaled(Vector3(0.43, 1.0, seg_len))
        pxf.append(Transform3D(bas, Vector3(xx, attic_floor + 0.011, (zr2["z0"] + zr2["z1"]) * 0.5)))
        var t: float = M.noise01(float(i) * 1.37, 4.1)
        var mm: float = 0.92 + t * 0.16
        pcol.append(Color(mm, mm * 0.95, mm * 0.88, 1.0))
    M.multis(ia, "AtticFloor", plank_mesh, pxf, pcol, plank_mat)
    # 洞口木收边（楼板面）
    var trim_y: float = attic_floor + 0.03
    M.box(ia, Vector3(0.08, 0.06, 0.85), Vector3(0.86, trim_y, -2.365), M.C_WOOD, 0.0, {})
    M.box(ia, Vector3(1.82, 0.06, 0.08), Vector3(1.73, trim_y, -1.90), M.C_WOOD, 0.0, {})
    M.box(ia, Vector3(0.08, 0.06, 2.67), Vector3(2.60, trim_y, -1.455), M.C_WOOD, 0.0, {})
    M.box(ia, Vector3(0.86, 0.06, 0.08), Vector3(3.07, trim_y, -0.08), M.C_WOOD, 0.0, {})
    # 洞口护栏（rail_h=0.90；混凝土三段 + 四角柱；不走楼梯出口 x=0.82 边）
    var rh: float = 0.90
    var rail_mat: Color = M.C_WOOD
    var segs: Array = [
        {"ax": 0.82, "az": -1.94, "bx": 2.64, "bz": -1.94},
        {"ax": 2.64, "az": -1.94, "bx": 2.64, "bz": -0.12},
        {"ax": 2.64, "az": -0.12, "bx": 3.49, "bz": -0.12},
    ]
    for sg in segs:
        var ax: float = sg["ax"]
        var az: float = sg["az"]
        var bx: float = sg["bx"]
        var bz: float = sg["bz"]
        var seg_len2: float = sqrt((bx - ax) * (bx - ax) + (bz - az) * (bz - az))
        var cxr: float = (ax + bx) * 0.5
        var czr: float = (az + bz) * 0.5
        var yaw_r: float = atan2(bx - ax, bz - az) * 0.0
        var along_z: bool = absf(bz - az) > absf(bx - ax)
        var size: Vector3 = Vector3(0.08, 0.06, seg_len2) if along_z else Vector3(seg_len2, 0.06, 0.08)
        M.box(ia, size, Vector3(cxr, attic_floor + rh, czr), rail_mat, 0.0, {"outline": 0.02})
        var n_bal: int = int(seg_len2 / 0.22)
        for k in range(1, n_bal + 1):
            var tt: float = float(k) / float(n_bal + 1)
            var px: float = ax + (bx - ax) * tt
            var pz: float = az + (bz - az) * tt
            M.box(ia, Vector3(0.035, rh - 0.08, 0.035), Vector3(px, attic_floor + (rh - 0.08) * 0.5, pz), M.C_WOOD_DARK, 0.0, {})
    for corner in [Vector2(0.82, -1.94), Vector2(2.64, -1.94), Vector2(2.64, -0.12), Vector2(3.49, -0.12)]:
        M.box(ia, Vector3(0.09, rh + 0.12, 0.09), Vector3(corner.x, attic_floor + (rh + 0.12) * 0.5, corner.y), rail_mat, 0.0, {"outline": 0.02})
        M.box(ia, Vector3(0.13, 0.05, 0.13), Vector3(corner.x, attic_floor + rh + 0.145, corner.y), M.C_WOOD_LIGHT, 0.0, {})
    # 斜顶椽条 + 系梁
    for sz in [-1.90, 1.90]:
        for side in [-1.0, 1.0]:
            var down := Vector3(side * cp, -sp, 0.0)
            var nrm := Vector3(side * sp, cp, 0.0)
            var mid: Vector3 = Vector3(0.0, ridge_y, 0.0) + down * 3.165 - nrm * 0.22
            M.box_rot(ia, Vector3(3.93, 0.12, 0.12), mid + Vector3(0.0, 0.0, sz), M.C_WOOD_DARK, Vector3(0.0, 0.0, -side * pitch), {"outline": 0.02})
        M.box(ia, Vector3(2.10, 0.10, 0.14), Vector3(0.0, 5.30, sz), M.C_WOOD_DARK, 0.0, {"outline": 0.02})
    # 阁楼吊灯（屋脊下）：C["attic_lamp_world"] 供 main 光源
    var lamp_pos := Vector3(0.20, 5.28, 0.90)
    var rod := MeshInstance3D.new()
    var rm := CylinderMesh.new()
    rm.top_radius = 0.012
    rm.bottom_radius = 0.012
    rm.height = 0.55
    rm.radial_segments = 6
    rod.mesh = rm
    rod.material_override = M.toon_material(M.C_WOOD_DARK, {"bands": 3.0})
    rod.position = Vector3(0.20, 5.605, 0.90)
    ia.add_child(rod)
    # P8.1-06：罩体不再整体自发光（self_lit=false + glow），灯泡独立材质保持 self_lit。
    var lamp_mat: ShaderMaterial = M.toon_material(Color("ffd79b"), {"self_lit": false, "glow": 0.55})
    var bulb_mat: ShaderMaterial = M.toon_material(Color("ffd79b"), {"self_lit": true, "glow": 1.15})
    # 灯罩材质交给 main 做昼夜调光（白天微亮、夜里全亮），见 main._update_lighting 的 interior_shade_mats
    C["attic_shade_mat"] = lamp_mat
    var shade := MeshInstance3D.new()
    var sm := CylinderMesh.new()
    sm.top_radius = 0.05
    sm.bottom_radius = 0.22
    sm.height = 0.18
    sm.radial_segments = 10
    shade.mesh = sm
    shade.material_override = lamp_mat
    shade.position = Vector3(0.20, 5.33, 0.90)
    ia.add_child(shade)
    var bulb := MeshInstance3D.new()
    var bm := SphereMesh.new()
    bm.radius = 0.075
    bm.height = 0.15
    bm.radial_segments = 10
    bm.rings = 6
    bulb.mesh = bm
    bulb.material_override = bulb_mat
    bulb.position = lamp_pos
    ia.add_child(bulb)
    # P8.2-02：光晕基准尺寸 0.95→0.60、亮度 2.2/1.5/0.85→1.25/0.82/0.42（夜间由 main 调回暖光晕）。
    var halo: MeshInstance3D = M.halo(ia, lamp_pos, 0.60, Color(1.25, 0.82, 0.42, 1.0))
    ia.set_meta("attic_lamp_halo", halo)
    (C["interior_halos"] as Array).append(halo)
    C["attic_lamp_world"] = _world(root, lamp_pos)
    # ---- 阁楼家具 15 件（T3 最终 DIMS；原点=占地中心，落地件 y=地面）----
    var fl: float = attic_floor + 0.02
    # 床内移：床尾靠墙端 |x| 最大 2.95，屋面下皮(T3 口径 6.20-0.6494|x|-0.167)=4.117 > 床顶 4.04
    P.build(ia, "bed", Vector3(-2.00, fl, -0.90), -PI * 0.5)
    # 床头柜贴床头（床侧 z=-1.40，间隙 0.02）+ 台灯台面 0.50
    # 床头柜贴床头（床头板平面 x=-1.15，AABB 到床距 0.02 ≤0.20）
    P.build(ia, "nightstand", Vector3(-1.15, fl, -1.61), 0.0)
    P.build(ia, "table_lamp", Vector3(-1.15, fl + 0.50, -1.61), 0.0)
    # 衣柜/书架沿后墙（-Z）排开；书架 x 右缘 0.795 < 楼梯洞口 0.82，避免悬空
    P.build(ia, "wardrobe", Vector3(-0.62, fl, -2.515), 0.0)
    P.build(ia, "bookshelf", Vector3(0.37, fl, -2.63), 0.0)
    P.build(ia, "desk", Vector3(0.0, fl, 2.44), PI)
    P.build(ia, "chair", Vector3(0.0, fl, 1.95), 0.0)
    P.build(ia, "table_lamp", Vector3(0.45, fl + 0.65, 2.55), 0.0)
    P.build(ia, "reading_chair", Vector3(1.60, fl, 1.10), -PI * 0.5)
    P.build(ia, "side_table", Vector3(1.60, fl, 0.45), 0.0)
    P.build(ia, "rug", Vector3(0.0, fl + 0.004, 0.90), 0.0)
    P.build(ia, "plant_pot", Vector3(2.55, fl, 2.20), 0.0)
    P.build(ia, "picture_frame", Vector3(1.12, attic_floor + 1.48, -2.79), 0.0)
    # 帘杆高 = attic_floor+1.75（T3 区间 1.70-2.40；窗顶 4.77 上方 0.15）
    P.build(ia, "curtain", Vector3(-1.03, attic_floor + 1.75, 2.80), PI)
    P.build(ia, "curtain", Vector3(1.03, attic_floor + 1.75, 2.80), PI)
    _merge_props_of(ia)
    ia.set_meta("furniture_count", 15)

# ============================================================
# 11) 一层室内：地板 / 天花（L 洞） / 横梁 / 壁炉 / 吊灯 / 23 件家具
# ============================================================
static func _interior(root: Node3D, C: Dictionary) -> void:
    var fy: float = C["fy"]
    var hd: float = C["hd"]
    var hw: float = C["hw"]
    var in_top: float = C["in_top"]
    var ch_x: float = C["ch_x"]
    var fw: float = 6.98
    var fd: float = 5.58
    var wood: Color = M.C_WOOD
    var wood_l: Color = M.C_WOOD_LIGHT
    var wood_d: Color = M.C_WOOD_DARK
    var yo: Dictionary = {"outline": 0.02}
    # 地板结构 + 板条
    M.box(root, Vector3(fw, 0.14, fd), Vector3(0.0, fy - 0.07, 0.0), Color("5f4733"), 0.0, {})
    var plank_mesh := BoxMesh.new()
    plank_mesh.size = Vector3(0.40, 0.02, fd - 0.10)
    var plank_mat: ShaderMaterial = M.toon_material(Color("9c7457"), {"vertex_color": true, "bands": 3.0})
    var pxf: Array = []
    var pcol: Array = []
    for i in range(17):
        var xx: float = -3.36 + float(i) * 0.42
        pxf.append(Transform3D(Basis.IDENTITY, Vector3(xx, fy + 0.01, 0.0)))
        var t: float = M.noise01(float(i) * 1.21, 6.3)
        var mm: float = 0.92 + t * 0.16
        pcol.append(Color(mm, mm * 0.96, mm * 0.90, 1.0))
    M.multis(root, "InteriorFloor", plank_mesh, pxf, pcol, plank_mat)
    # 天花板（L 洞切 3 块；2.97..2.995）
    var zones: Array = [
        {"x0": -3.50, "x1": 0.82, "z0": -2.80, "z1": 2.80},
        {"x0": 0.82, "x1": 2.64, "z0": -1.94, "z1": 2.80},
        {"x0": 2.64, "x1": 3.50, "z0": -0.12, "z1": 2.80},
    ]
    for zr in zones:
        var zw: float = zr["x1"] - zr["x0"]
        var zd: float = zr["z1"] - zr["z0"]
        M.box(root, Vector3(zw, 0.025, zd), Vector3((zr["x0"] + zr["x1"]) * 0.5, in_top + 0.0125, (zr["z0"] + zr["z1"]) * 0.5), Color("d9c7a5"), 0.0, {})
    # 横梁（沿 X；遇楼梯洞截断）
    M.box(root, Vector3(4.32, 0.18, 0.20), Vector3(-1.34, in_top - 0.09, -2.20), wood, 0.0, yo)
    M.box(root, Vector3(6.14, 0.18, 0.20), Vector3(-0.43, in_top - 0.09, -0.90), wood, 0.0, yo)
    M.box(root, Vector3(fw, 0.18, 0.20), Vector3(0.0, in_top - 0.09, 0.90), wood, 0.0, yo)
    M.box(root, Vector3(fw, 0.18, 0.20), Vector3(0.0, in_top - 0.09, 2.70), wood, 0.0, yo)
    # 洞口托梁/收边（天花下侧）
    var ty: float = in_top - 0.10
    M.box(root, Vector3(0.10, 0.16, 0.85), Vector3(0.82, ty, -2.365), wood_d, 0.0, yo)
    M.box(root, Vector3(1.82, 0.16, 0.10), Vector3(1.73, ty, -1.94), wood_d, 0.0, yo)
    M.box(root, Vector3(0.10, 0.16, 2.67), Vector3(2.64, ty, -1.455), wood_d, 0.0, yo)
    M.box(root, Vector3(0.86, 0.16, 0.10), Vector3(3.07, ty, -0.12), wood_d, 0.0, yo)
    # 四角室内木柱
    for sx in [-1.0, 1.0]:
        for sz in [-1.0, 1.0]:
            M.box(root, Vector3(0.26, 2.36, 0.26), Vector3(sx * 3.37, fy + 1.18, sz * 2.67), wood, 0.0, {"outline": 0.025})
    # 踢脚线
    for sx in [-1.0, 1.0]:
        M.box(root, Vector3(2.93, 0.12, 0.05), Vector3(sx * 2.035, fy + 0.06, 2.77), wood_l, 0.0, {})
        M.box(root, Vector3(0.05, 0.12, 5.38), Vector3(sx * 3.47, fy + 0.06, 0.0), wood_l, 0.0, {})
    M.box(root, Vector3(6.78, 0.12, 0.05), Vector3(0.0, fy + 0.06, -2.77), wood_l, 0.0, {})
    # 后墙木饰（护墙板）
    for k in range(3):
        M.box(root, Vector3(6.74, 0.20, 0.06), Vector3(0.0, fy + 0.12 + float(k) * 0.24, -2.77), wood, 0.0, {"outline": 0.015})
    M.box(root, Vector3(6.78, 0.06, 0.08), Vector3(0.0, fy + 0.76, -2.77), wood_d, 0.0, {})
    # 门内侧木框
    for sx in [-1.0, 1.0]:
        M.box(root, Vector3(0.24, 2.07, 0.12), Vector3(sx * 0.66, fy + 1.035, 2.80), wood, 0.0, yo)
    M.box(root, Vector3(1.44, 0.14, 0.14), Vector3(0.0, 2.56, 2.80), wood, 0.0, yo)
    # ---- 壁炉（P8.2-01：真实凹龛，贴后墙内面 z=-2.80）----
    # 石胸由一块整板改为「两侧石柱 + 上楣」框架，中间留 0.86 x 0.70 的炉膛开口：
    #   框架前脸 z=-2.55，黑膛板退到 z=-2.79..-2.73 → 凹深 0.18m，火焰落在凹龛内。
    # 旧版石胸 z=-2.80..-2.54 被烟囱体（z 到 -2.20）整体挡住，室内只能看到一块石板。
    for sx in [-1.0, 1.0]:
        M.box(root, Vector3(0.25, 1.62, 0.25), Vector3(ch_x + sx * 0.555, fy + 0.81, -2.675), M.C_STONE, 0.0, {"outline": 0.03})
    # 上楣：比石柱前脸浅 1cm、顶面低 1cm，避免与前脸/顶面共面（z-fighting）
    M.box(root, Vector3(1.16, 0.81, 0.25), Vector3(ch_x, fy + 1.205, -2.67), M.C_STONE, 0.0, {"outline": 0.03})
    # 炉膛地石：顶上比炉台石低 1cm 形成台阶，且与炉台石在 z 向重叠 0.02m，避免共面
    M.box(root, Vector3(0.90, 0.09, 0.28), Vector3(ch_x, fy + 0.045, -2.66), M.C_STONE_DARK, 0.0, {})
    # 黑膛板（凹龛后壁）
    M.box(root, Vector3(0.82, 0.72, 0.06), Vector3(ch_x, fy + 0.44, -2.76), Color("211812"), 0.0, {})
    for sx in [-1.0, 1.0]:
        M.box(root, Vector3(0.22, 0.90, 0.18), Vector3(ch_x + sx * 0.48, fy + 0.60, -2.48), M.C_STONE_DARK, 0.0, {"outline": 0.02})
    M.box(root, Vector3(1.34, 0.18, 0.22), Vector3(ch_x, fy + 0.95, -2.47), M.C_STONE_DARK, 0.0, {"outline": 0.02})
    M.box(root, Vector3(1.46, 0.09, 0.28), Vector3(ch_x, fy + 1.11, -2.44), wood_l, 0.0, {"outline": 0.02})
    M.box(root, Vector3(1.70, 0.10, 0.60), Vector3(ch_x, fy + 0.05, -2.24), M.C_STONE, 0.0, {})
    # 柴薪移入凹龛（旧版整体探出到 z=-2.52 一带，与烟囱前脸互相穿插）
    M.cyl_rot(root, 0.07, 0.07, 0.40, Vector3(ch_x - 0.10, fy + 0.14, -2.66), Color("4a3222"), Vector3(0.0, 0.0, 1.5708), {})
    M.cyl_rot(root, 0.06, 0.06, 0.34, Vector3(ch_x + 0.12, fy + 0.13, -2.68), Color("553a26"), Vector3(0.0, 0.35, 1.5708), {})
    var fire_mat: ShaderMaterial = M.toon_material(Color("ff8f30"), {"self_lit": true, "glow": 1.20})
    # 火焰盒立起来（0.13x0.18）并整块退进凹龛 z=-2.68..-2.58；旧版 0.14x0.07 平躺、
    # z=-2.61..-2.43 有 0.11m 露在烟囱前脸之外，被 fbb 遮挡后只剩硬边黄方块。
    # 三簇火焰：不同高度 + 微错位，底部统一落在柴薪顶面（旧版三块等大平躺方糖，
    # 被烟囱前脸挡住后只剩一块硬边黄方块，完全读不出"火"）
    var flames := [
        {"x": -0.15, "h": 0.20, "w": 0.12},
        {"x": 0.00, "h": 0.26, "w": 0.13},
        {"x": 0.15, "h": 0.20, "w": 0.12},
    ]
    for f in flames:
        var fm := BoxMesh.new()
        fm.size = Vector3(float(f["w"]), float(f["h"]), 0.10)
        var fmi := MeshInstance3D.new()
        fmi.mesh = fm
        fmi.material_override = fire_mat
        fmi.position = Vector3(ch_x + float(f["x"]), fy + 0.15 + float(f["h"]) * 0.5, -2.63)
        root.add_child(fmi)
    # halo 收小（0.85→0.40）并退入凹龛；旧版 0.85 的加色 billboard 挂在烟囱前脸外侧，
    # 经 glow/tonemap 饱和成一块硬边黄方块。
    M.halo(root, Vector3(ch_x, fy + 0.36, -2.565), 0.34, Color(1.7, 0.85, 0.32, 1.0))
    # ---- 吊灯（餐桌上方）----
    # P8.1-06：罩体 self_lit=false + glow（可受光），灯泡独立材质保持 self_lit。
    var lamp_mat: ShaderMaterial = M.toon_material(Color("ffd79b"), {"self_lit": false, "glow": 0.55})
    var bulb_mat: ShaderMaterial = M.toon_material(Color("ffd79b"), {"self_lit": true, "glow": 1.15})
    # 灯罩材质交给 main 做昼夜调光（白天微亮、夜里全亮）
    C["interior_shade_mat"] = lamp_mat
    var rod := MeshInstance3D.new()
    var rm := CylinderMesh.new()
    rm.top_radius = 0.012
    rm.bottom_radius = 0.012
    rm.height = 0.45
    rm.radial_segments = 6
    rod.mesh = rm
    rod.material_override = M.toon_material(wood_d, {"bands": 3.0})
    rod.position = Vector3(1.45, in_top - 0.225, 0.80)
    root.add_child(rod)
    var shade := MeshInstance3D.new()
    var sm := CylinderMesh.new()
    sm.top_radius = 0.05
    sm.bottom_radius = 0.28
    sm.height = 0.22
    sm.radial_segments = 10
    shade.mesh = sm
    shade.material_override = lamp_mat
    shade.position = Vector3(1.45, in_top - 0.55, 0.80)
    root.add_child(shade)
    var bulb := MeshInstance3D.new()
    var bm := SphereMesh.new()
    bm.radius = 0.09
    bm.height = 0.18
    bm.radial_segments = 10
    bm.rings = 6
    bulb.mesh = bm
    bulb.material_override = bulb_mat
    bulb.position = Vector3(1.45, in_top - 0.62, 0.80)
    root.add_child(bulb)
    # P8.2-02：一层吊灯光晕纳入昼夜调光数组（基准 0.60，白天收小、夜间回满）
    var ch_halo: MeshInstance3D = M.halo(root, Vector3(1.45, in_top - 0.62, 0.80), 0.60, Color(1.25, 0.82, 0.42, 1.0))
    (C["interior_halos"] as Array).append(ch_halo)
    # ---- 一层家具 23 件（T3 最终 DIMS；fl=板条面）----
    var fl: float = fy + 0.02
    P.build(root, "doormat", Vector3(0.0, fl, 2.30), 0.0)
    P.build(root, "shoe_bench", Vector3(1.15, fl, 2.60), PI)
    P.build(root, "coat_rack", Vector3(-1.15, fy + 0.92, 2.79), PI)
    P.build(root, "wall_clock", Vector3(3.49, fy + 1.60, 0.60), -PI * 0.5)
    P.build(root, "plant_pot", Vector3(3.15, fl, 2.52), 0.6)
    P.build(root, "rug", Vector3(-2.10, fl + 0.004, 1.62), 0.0)
    P.build(root, "sofa", Vector3(-2.10, fl, 2.22), PI)
    P.build(root, "coffee_table", Vector3(-2.10, fl, 1.12), 0.0)
    P.build(root, "armchair", Vector3(-0.92, fl, 1.12), -PI * 0.5)
    P.build(root, "floor_lamp", Vector3(-3.12, fl, 2.35), 0.3)
    P.build(root, "firewood_basket", Vector3(-2.95, fl, -1.70), 0.4)
    P.build(root, "desk", Vector3(-3.19, fl, 0.30), PI * 0.5)
    P.build(root, "chair", Vector3(-2.62, fl, 0.30), -PI * 0.5)
    P.build(root, "bookshelf", Vector3(-3.34, fl, -1.00), PI * 0.5)
    P.build(root, "tall_cupboard", Vector3(-1.00, fl, -2.60), 0.0)
    P.build(root, "sideboard", Vector3(0.20, fl, -2.60), 0.0)
    P.build(root, "table_lamp", Vector3(0.20, fl + 0.80, -2.60), 0.0)
    P.build(root, "dining_table", Vector3(1.45, fl, 0.80), PI * 0.5)
    P.build(root, "chair", Vector3(1.45, fl, 1.57), PI)
    P.build(root, "chair", Vector3(1.45, fl, 0.03), 0.0)
    P.build(root, "chair", Vector3(1.97, fl, 0.80), -PI * 0.5)
    P.build(root, "chair", Vector3(0.93, fl, 0.80), PI * 0.5)
    P.build(root, "picture_frame", Vector3(-3.49, fy + 1.45, 0.90), PI * 0.5)
    _merge_props_of(root)

# ============================================================
# 12) 猫（位置由 T2，模型/尺寸由 T4）
# ============================================================
static func _cat(root: Node3D, C: Dictionary, pos: Vector3) -> void:
    var info = CAT.build(root, pos, -0.6)
    C["cat"] = info

# ============================================================
# 13) 鸟栖息点 14 个（全部从新屋面/栏杆几何推导）
# ============================================================
static func _make_perches(root: Node3D, C: Dictionary) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    var pitch: float = C["pitch"]
    var cp: float = C["cp"]
    var sp: float = C["sp"]
    var ridge_y: float = C["ridge_y"]
    var ch_x: float = C["ch_x"]
    var ch_z: float = C["ch_z"]
    var ch_top: float = C["ch_top"]
    var deck_top: float = C["deck_top"]
    var gap: float = 0.03
    # 屋脊 3（脊瓦顶 = ridge + 0.24）
    for i in range(3):
        var zz: float = [-2.40, 0.0, 2.40][i]
        out.append(_mk_perch(root, "ridge_%d" % i, Vector3(0.0, ridge_y + 0.24 + gap, zz), Vector3(0.0, 0.0, 1.0), Vector3(0.0, 1.0, 0.0), 0.0, 0.26, "ridge"))
    # 檐口 4（第 17 行筒瓦顶面）
    var eave_s: float = 0.22 + 17.0 * 0.26
    var tile_r_mid: float = 0.11
    for sx in [-1.0, 1.0]:
        for zz2 in [-2.415, 2.415]:
            var ex: float = cp * eave_s + sp * (0.07 + tile_r_mid)
            var ey: float = ridge_y - sp * eave_s + cp * (0.07 + tile_r_mid)
            out.append(_mk_perch(root, "eave_%s_%s" % ["L" if sx < 0.0 else "R", str(zz2)], Vector3(sx * ex, ey + gap, zz2), Vector3(sx, 0.0, 0.0), Vector3(sx * sp, cp, 0.0), pitch, 0.20, "eave"))
    # 烟囱顶 1
    out.append(_mk_perch(root, "chimney_0", Vector3(ch_x, ch_top + 0.35 + gap, ch_z), Vector3(0.0, 0.0, 1.0), Vector3(0.0, 1.0, 0.0), 0.0, 0.26, "chimney"))
    # 门廊横梁 2（梁顶 2.60）
    for sx2 in [-1.0, 1.0]:
        out.append(_mk_perch(root, "porch_beam_%s" % ("L" if sx2 < 0.0 else "R"), Vector3(sx2 * 2.10, 2.63 + gap, 4.55), Vector3(0.0, 0.0, 1.0), Vector3(0.0, 1.0, 0.0), 0.0, 0.18, "porch_beam"))
    # 门廊扶手 4（扶手顶 = deck_top + 0.84；栖点 = 顶面 + gap，与 _porch 的扶手几何同源）
    var rail_top: float = deck_top + 0.84
    for sx3 in [-1.0, 1.0]:
        out.append(_mk_perch(root, "porch_rail_%s" % ("L" if sx3 < 0.0 else "R"), Vector3(sx3 * 2.82, rail_top + gap, 3.925), Vector3(0.0, 0.0, 1.0), Vector3(0.0, 1.0, 0.0), 0.0, 0.18, "porch_rail", 1))
    # 门廊前扶手 2
    for sx4 in [-1.0, 1.0]:
        out.append(_mk_perch(root, "porch_rail_F%s" % ("L" if sx4 < 0.0 else "R"), Vector3(sx4 * 2.135, rail_top + gap, 4.60), Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), 0.0, 0.18, "porch_rail", 1))
    return out

static func _mk_perch(root: Node3D, id: String, local_pos: Vector3, facing_local: Vector3, normal_local: Vector3, slope: float, radius: float, kind: String, slots: int = 0) -> Dictionary:
    var xf: Transform3D = root.global_transform if root.is_inside_tree() else root.transform
    var d := {"id": id, "pos": _world(root, local_pos), "facing": (xf.basis * facing_local).normalized(),
        "normal": (xf.basis * normal_local).normalized(), "slope": slope, "radius": radius, "kind": kind}
    if slots > 0:
        d["slots"] = slots
    return d