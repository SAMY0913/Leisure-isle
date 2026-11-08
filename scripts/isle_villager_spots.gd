class_name IsleVillagerSpots
extends RefCounted
## P7-V4: authoritative activity-spot + walk-graph data for the lone islander.
##
## No physics colliders exist in this project, so this graph is the single source of
## truth for where the villager may stand.  Indoor/porch nodes are authored in
## cottage-local metres and converted with the real cottage transform; outdoor nodes
## are world metres and take their height from IsleWorld.surface_y() (terrain+mounds).
##
## Node "mode":
##   "flat"    - y is already the walk surface (interior floor / porch / landing)
##   "stair"   - y is a tread top; segment height lerps between tread tops
##   "terrain" - y follows IsleWorld.surface_y(x,z) every frame
##   "yard"    - front-yard paved deck: y = IsleWorld._yard_pad_y()+YARD_FLOOR_LIFT
##   "yard_bed"- top face of a raised soil bed: yard deck + YARD_BED_RISE (P4-CLOSE)
##
## Spot kinds: "bed" | "eat" | "sit" | "view".
## A spot anchor is where the villager root sits for the final pose
## (sit = pelvis on seat surface, bed = pelvis on mattress, view = feet on ground).
## approach() returns the standing point in front of / behind the seat (feet anchor);
## the villager tweens its root from that feet anchor to the seat/mattress anchor while
## playing the sit_down / lie_down clip, so seat height never has to be assumed.
##
## Furniture yaw convention (isle_house_props.gd:16): node origin = footprint centre,
## rotation.y = yaw, local +Z is the furniture front.  So front = (sin yaw, 0, cos yaw).
##   "back"  side: stand behind the seat, i.e. anchor - front * dist (dining chairs,
##                 desk chairs, armchair whose front is blocked by a coffee table).
##   "front" side: stand in front of the seat and step backwards onto it (sofa /
##                 wall benches / reading chair whose back is close to the roof slope).

const W := preload("res://scripts/world.gd")
const M := preload("res://scripts/isle_math.gd")

const BODY_R := 0.10   # pathing guard radius: the sofa/coffee-table gap is only 0.45 m
                      # wide, so generous 0.2 m clearance would make the sofa unreachable

# ---- P6 钓鱼：唯一钓位（码头木板上，面朝海面抛竿）------------------------------
# P9 / P6-VISUAL-FIX：旧钓位 shore_stand 落在码头旁 0.96 m 高的沙滩斜坡上（地形高度
# 由 W.surface_y 给出），岛民站在绿色斜坡上而不是码头木板上，验收截图因此明显错误。
# 新钓位放在码头**船头端无栏杆区**（dock-local z=10.60 > 最后一根栏杆柱 z=10.40），
# 双脚在木板可站立范围（x ∈ [-1.70,1.70]，z ∈ [1.80,11.23]，板面 y = 0.72）内。
# 抛竿方向不能沿码头轴线：停泊帆船 Sailboat 的船体正好横在码头尽头
# （dock-local x ∈ [-2.65,2.51]，z ∈ [13.15,15.62]），3.2 m 直线抛投会落进船体。
# 因此 cast_dir = 码头向外轴线绕 +Y 偏 FISH_CAST_YAW_RAD，落到船体侧面的开阔海面。
const FISH_SPOT_NODE := "dock_fishing_stand"
const FISH_CAST_DIST := 3.2
const FISH_CAST_YAW_RAD := 1.0821        # 62°：实测离船体最近点 clearance ≈ 2.1 m
const FISH_DECK_Y := 0.72                # = IsleWorld.DECK_WORLD_Y（木板顶面世界高度）

## 码头的真实空间框架（世界原点 / 向海轴线 / 偏航）。整张图里所有码头站位都从这一份
## 数据派生，钓位朝向与抛竿落点也随之派生，避免"站位一套方向、抛竿另一套方向"。
static func dock_frame() -> Dictionary:
    var s := M.dock_start()
    var d := M.dock_dir()
    return {"origin": s, "dir": d, "yaw": atan2(d.x, d.z), "deck_y": FISH_DECK_Y}


## 码头局部 (lx, lz) → 世界水平坐标。与 world.gd::_dock() 的 node.position/rotation.y 同源。
static func dock_local_to_world(lx: float, lz: float) -> Vector3:
    var f := dock_frame()
    var o: Vector3 = f["origin"]
    var b := Basis(Vector3.UP, float(f["yaw"]))
    var rel: Vector3 = b * Vector3(lx, 0.0, lz)
    return Vector3(o.x + rel.x, 0.0, o.z + rel.z)


## 钓鱼点的事实快照（读图即可，不改变任何状态）。返回 {} = 图里没有钓位节点。
## point = 岛民站位（甲板面）；cast_point = 水面浮漂落点（海面 y=0）；
## cast_dir / face_yaw = 抛竿方向与岛民朝向（同一份数据派生）。
static func fishing_spot(graph: Dictionary) -> Dictionary:
    var nodes: Dictionary = graph.get("nodes", {})
    if not nodes.has(FISH_SPOT_NODE):
        return {}
    var p: Vector3 = (nodes[FISH_SPOT_NODE] as Dictionary)["pos"]
    var dock: Dictionary = graph.get("dock", {})
    var axis := Vector3.ZERO
    if dock.has("dir"):
        var d: Vector3 = dock["dir"]
        axis = Vector3(d.x, 0.0, d.z)
    if axis.length() < 0.001:
        axis = Vector3(p.x, 0.0, p.z)
    if axis.length() < 0.001:
        return {}
    axis = axis.normalized()
    var dir := axis.rotated(Vector3.UP, FISH_CAST_YAW_RAD)
    dir = Vector3(dir.x, 0.0, dir.z).normalized()
    var cast := Vector3(p.x + dir.x * FISH_CAST_DIST, 0.0, p.z + dir.z * FISH_CAST_DIST)
    return {
        "node": FISH_SPOT_NODE,
        "point": p,
        "cast_point": cast,
        "cast_dir": dir,
        "cast_axis": axis,
        "face_yaw": atan2(-dir.x, -dir.z),
    }

const NODE_DEFS := [
    # ---- outdoor (world metres) -------------------------------------------------
    ["front_path_1", 2.20, 6.40, 0.0, "terrain", "outdoor"],
    ["front_path_2", 5.60, 8.60, 0.0, "terrain", "outdoor"],
    # ---- P6 钓鱼：沿既有砾石主路（门廊→码头）走到岸线，再下到沙滩钓位 ----------------
    # 主路中心线采样自 world.gd _prepare()（5.6,8.6 -> 9.6,10.2 -> 14.2,11.8 -> dock_start），
    # 因此这三段与玩家可见小路重合，不穿越房屋/围栏/农田。dock_shoreside 就在码头根部
    # 的砾石路终点；随后三个节点沿沙坡折向水面（地形高度由 surface_y 提供）。
    ["shore_path_1", 9.60, 10.20, 0.0, "terrain", "outdoor"],
    ["shore_path_2", 14.20, 11.80, 0.0, "terrain", "outdoor"],
    ["dock_shoreside", 19.78485, 14.12459, 0.0, "terrain", "outdoor"],
    # ---- P9 / P6-VISUAL-FIX：码头木板上的钓鱼站位 ------------------------------
    # 全部用 **dock 局部坐标**（lx, lz）授权，世界坐标由 dock_local_to_world() 从
    # isle_math.dock_start()/dock_dir() 派生，与 world.gd::_dock() 同一份几何，
    # 不再出现“路径点写死世界坐标、和木板对不上”的问题：
    #   dock_step_a/b：下沙滩的两级（y 取真实地形 surface_y，和码头石阶同一个坡）
    #   dock_deck_in ：踏上第一块木板（板面 y = 0.72）
    #   dock_walk_mid：木板中段（3.4 m 宽甲板的中线，离两侧栏杆 1.68 m）
    #   dock_fishing_stand：船头端无栏杆区（z=10.60 > 最后一根栏杆柱 z=10.40），
    #                        双脚在木板可站立范围 z ∈ [1.80, 11.23] 内。
    ["dock_step_a", 0.0, 0.50, 0.0, "dock_terrain", "outdoor"],
    ["dock_step_b", 0.0, 1.20, 0.0, "dock_terrain", "outdoor"],
    ["dock_step_c", 0.0, 1.55, 0.0, "dock_terrain", "outdoor"],
    ["dock_deck_in", 0.0, 1.95, 0.72, "dock", "outdoor"],
    ["dock_walk_mid", 0.0, 6.40, 0.72, "dock", "outdoor"],
    ["dock_fishing_stand", 0.0, 10.60, 0.72, "dock", "outdoor"],
    # P9：码头尽头无栏杆区（z>10.40）的观海站位：面朝海面（dock +Z 轴）
    ["dock_sea_watch", 0.0, 11.10, 0.72, "dock", "outdoor"],
    # 旧沙滩钓位节点保留（不再作为钓位，供历史探针/P7 路线报告引用，避免删数据）。
    ["shore_bank", 20.90, 13.35, 0.0, "terrain", "outdoor"],
    ["shore_sand", 22.00, 12.90, 0.0, "terrain", "outdoor"],
    ["shore_stand", 23.10915, 12.56604, 0.0, "terrain", "outdoor"],
    ["garden_0", 1.20, 7.10, 0.0, "terrain", "outdoor"],
    ["garden_1", -1.60, 6.55, 0.0, "terrain", "outdoor"],
    ["garden_2", -3.90, 4.90, 0.0, "terrain", "outdoor"],
    ["garden_3", -5.40, 2.60, 0.0, "terrain", "outdoor"],
    ["garden_4", -6.40, 0.00, 0.0, "terrain", "outdoor"],
    ["garden_5", -7.05, -1.90, 0.0, "terrain", "outdoor"],
    ["garden_6", -7.45, -2.95, 0.0, "terrain", "outdoor"],
    ["garden_7", -7.82, -2.95, 0.0, "terrain", "outdoor"],
    ["garden_8", -7.82, -6.20, 0.0, "terrain", "outdoor"],
    ["garden_cross", -6.20, -6.20, 0.0, "terrain", "outdoor"],
    ["tree_view", -8.47, 3.27, 0.0, "terrain", "outdoor"],
    ["swing_view", -8.06, 5.32, 0.0, "terrain", "outdoor"],
    # P9：秋千座点的真实站位（秋千座在 (-7.90, y, 4.20)，摆平面是 Z 轴，所以从 +X 侧上座最安全）
    ["swing_stand", -7.05, 4.20, 0.0, "terrain", "outdoor"],
    # ---- P2-B front-yard farm: 9-bed walkway ring (yard-local metres) ------------
    # P4: the islander must physically walk to each bed.  The approved 2.05-2.65 m
    # walkway band is the only walkable surface between the raised beds (beds are
    # 1.0 m wide with a 0.5 m gap that the P2-B plan treats as impassable), so every
    # yard node below sits at the band centre line, 0.85 m out from the bed centre.
    # Gate posts are on z = 8.99; the 1.10 m opening spans x = -4.90 .. -3.80.
    ["yard_path_a", -1.60, 5.65, 0.0, "yard", "outdoor"],
    ["yard_path_b", -2.98, 7.32, 0.0, "yard", "outdoor"],
    ["yard_gate_out", -4.35, 8.90, 0.0, "yard", "outdoor"],
    ["yard_gate_in", -4.35, 9.35, 0.0, "yard", "outdoor"],
    ["yard_slot_0", -5.85, 9.35, 0.0, "yard", "outdoor"],
    ["yard_slot_2", -2.85, 9.35, 0.0, "yard", "outdoor"],
    ["yard_slot_5", -2.00, 11.70, 0.0, "yard", "outdoor"],
    ["yard_slot_8", -2.85, 14.05, 0.0, "yard", "outdoor"],
    ["yard_slot_7", -4.35, 14.05, 0.0, "yard", "outdoor"],
    ["yard_slot_6", -5.85, 14.05, 0.0, "yard", "outdoor"],
    ["yard_slot_3", -6.70, 11.70, 0.0, "yard", "outdoor"],
    # P4：走道环 45° 圆角节点。环是圆角矩形带，直接连对角槽位会形成 2.499 m 弦，
    # 实测斜穿土床角（偏离环中线 0.617 m、34/81 采样落床内）。四个角点把弦拆成
    # 2.273 m + 0.776 m 两段，两段都贴合环中线且在环带内（P4-A 实测建议）。
    ["yard_corner_ne", -2.0779, 9.4279, 0.0, "yard", "outdoor"],
    ["yard_corner_se", -2.0779, 13.9721, 0.0, "yard", "outdoor"],
    ["yard_corner_sw", -6.6221, 13.9721, 0.0, "yard", "outdoor"],
    ["yard_corner_nw", -6.6221, 9.4279, 0.0, "yard", "outdoor"],
    # P4-CLOSE：中心格 slot4 的真实可达性。九格之间的 0.5 m 草坪缝仍然不可通行
    # （缝内没有任何节点/边），唯一被承认的「踩上台面」路径是前排北侧苗床：
    #   yard_bed_step 走道带上（到中心格心 2.177 m，径向在 2.05–2.65 环带内）
    #   yard_bed_up   床顶近边内侧（x=-4.80 处床顶 z 从约 9.79 起）
    #   yard_slot_4   同床远边内侧，距中心格格心 1.235 m ≤ 1.30 m 交互臂展
    # 上台只在 step→up 这段 0.23 m 内抬升 0.20 m，与走道/床面的真实高差一致。
    ["yard_bed_step", -4.80, 9.57, 0.0, "yard", "outdoor"],
    ["yard_bed_up", -4.80, 9.80, 0.0, "yard_bed", "outdoor"],
    ["yard_slot_4", -4.80, 10.55, 0.0, "yard_bed", "outdoor"],
    # ---- porch / door (house-local) ---------------------------------------------
    ["lawn", 0.0, 5.95, 0.0, "terrain_local", "porch"],
    ["step3", 0.0, 5.45, 0.00, "flat", "porch"],
    ["step2", 0.0, 5.15, 0.14, "flat", "porch"],
    ["step1", 0.0, 4.85, 0.28, "flat", "porch"],
    ["deck", 0.0, 4.55, 0.42, "flat", "porch"],
    ["deck_out", 0.0, 4.05, 0.42, "flat", "porch"],
    ["porch_bench_front", 1.75, 3.80, 0.42, "flat", "porch"],
    ["door_sill", 0.0, 3.18, 0.55, "flat", "porch"],
    # ---- ground floor (house-local) ---------------------------------------------
    ["room_in", 0.0, 2.70, 0.57, "flat", "floor1"],
    ["doormat", 0.0, 2.30, 0.57, "flat", "floor1"],
    ["hall", 0.0, 1.85, 0.57, "flat", "floor1"],
    # north of the dining table: route along z >= 2.0 so it clears the north chair,
    # then turn south through the east aisle.
    ["east_top", 2.20, 2.05, 0.57, "flat", "floor1"],
    ["shoe_front", 1.15, 2.02, 0.57, "flat", "floor1"],
    # east aisle: z stays > 0.08 so it clears the stair footprint
    ["aisle_e", 2.55, 1.25, 0.57, "flat", "floor1"],
    ["stair_foot", 3.065, 0.16, 0.57, "flat", "floor1"],
    ["mid", 0.00, 0.60, 0.57, "flat", "floor1"],
    ["south_mid", 0.00, -0.60, 0.57, "flat", "floor1"],
    ["dining_s", 1.45, -0.60, 0.57, "flat", "floor1"],
    ["sofa_front", -2.10, 1.60, 0.57, "flat", "floor1"],
    ["armchair_front", -0.20, 1.40, 0.57, "flat", "floor1"],
    ["desk_front", -2.05, 0.30, 0.57, "flat", "floor1"],
    # ---- attic (house-local) -----------------------------------------------------
    ["attic_exit", 0.55, -2.05, 3.181, "flat", "attic"],
    ["attic_1", 0.45, -1.70, 3.181, "flat", "attic"],
    ["attic_2", -0.35, -1.65, 3.181, "flat", "attic"],
    ["attic_3", -0.60, -1.05, 3.181, "flat", "attic"],
    ["attic_4", -0.80, -0.15, 3.181, "flat", "attic"],
    ["bed_stand", -2.00, -0.10, 3.181, "flat", "attic"],
    ["attic_aisle_1", 1.10, -1.68, 3.181, "flat", "attic"],
    ["attic_aisle_2", 0.80, 0.20, 3.181, "flat", "attic"],
    ["reading_front", 0.98, 1.10, 3.181, "flat", "attic"],
    ["attic_north", 1.10, 2.00, 3.181, "flat", "attic"],
    ["attic_window", 1.00, 2.30, 3.181, "flat", "attic"],
    ["attic_plant_view", 2.05, 1.70, 3.181, "flat", "attic"],
    ["attic_desk_front", 0.00, 1.40, 3.181, "flat", "attic"],
]

const EDGE_DEFS := [
    ["front_path_1", "front_path_2"],
    # P6 钓鱼：主路岸线段（与上方针脚同一条真实砾石路），再沿沙坡到钓位。
    ["front_path_2", "shore_path_1"],
    ["shore_path_1", "shore_path_2"],
    ["shore_path_2", "dock_shoreside"],
    # P9 / P6-VISUAL-FIX：码头登板链（下沙滩 → 石阶坡 → 第一块木板 → 甲板中段 → 钓位）
    ["dock_shoreside", "dock_step_a"],
    ["dock_step_a", "dock_step_b"],
    ["dock_step_b", "dock_step_c"],
    ["dock_step_c", "dock_deck_in"],
    ["dock_deck_in", "dock_walk_mid"],
    ["dock_walk_mid", "dock_fishing_stand"],
    ["dock_fishing_stand", "dock_sea_watch"],
    # 旧的沙滩支线（保留为观赏节点，不再通往钓位）
    ["dock_shoreside", "shore_bank"],
    ["shore_bank", "shore_sand"],
    ["shore_sand", "shore_stand"],
    ["front_path_1", "lawn"],
    ["garden_0", "lawn"],
    ["garden_0", "garden_1"],
    ["garden_1", "yard_path_a"],
    # P7.1（用户反馈）：农田出口直连门廊草坪。此前农田→钓鱼必须沿花园支路绕到 garden_1/
    # garden_0 再回门前（37.18 m / 15 跳 / 3 个 >120° 折返），只有一条通往田野的路。
    # 现在 yard_path_a 直接接 lawn（1.63 m），出田后直奔门前主路；既有花园边全部保留，
    # 绕行观赏路线与 P4 的九格走道完全不变。
    ["yard_path_a", "lawn"],
    ["yard_path_a", "yard_path_b"],
    ["yard_path_b", "yard_gate_out"],
    ["yard_gate_out", "yard_gate_in"],
    ["yard_gate_in", "yard_slot_0"],
    ["yard_gate_in", "yard_slot_2"],
    ["yard_slot_2", "yard_corner_ne"],
    ["yard_corner_ne", "yard_slot_5"],
    ["yard_slot_5", "yard_corner_se"],
    ["yard_corner_se", "yard_slot_8"],
    ["yard_slot_8", "yard_slot_7"],
    ["yard_slot_7", "yard_slot_6"],
    ["yard_slot_6", "yard_corner_sw"],
    ["yard_corner_sw", "yard_slot_3"],
    ["yard_slot_3", "yard_corner_nw"],
    ["yard_corner_nw", "yard_slot_0"],
    # P4-CLOSE：上台路径（走道 → 北排中间苗床顶面 → 中心格操作站位）。只连到这一张
    # 苗床，不跨 0.5 m 草缝、不连其它床，场地方案与草地缝规则保持不变。
    ["yard_gate_in", "yard_bed_step"],
    ["yard_slot_0", "yard_bed_step"],
    ["yard_bed_step", "yard_bed_up"],
    ["yard_bed_up", "yard_slot_4"],
    ["garden_1", "garden_2"],
    ["garden_2", "garden_3"],
    ["garden_2", "tree_view"],
    ["tree_view", "swing_view"],
    ["swing_view", "swing_stand"],
    ["garden_3", "garden_4"],
    ["garden_4", "garden_5"],
    ["garden_5", "garden_6"],
    ["garden_6", "garden_7"],
    ["garden_7", "garden_8"],
    ["garden_8", "garden_cross"],
    ["lawn", "step3"],
    ["step3", "step2"],
    ["step2", "step1"],
    ["step1", "deck"],
    ["deck", "deck_out"],
    ["deck", "porch_bench_front"],
    ["deck_out", "door_sill"],
    ["door_sill", "room_in"],
    ["room_in", "doormat"],
    ["doormat", "hall"],
    ["hall", "shoe_front"],
    ["shoe_front", "east_top"],
    ["east_top", "aisle_e"],
    ["hall", "sofa_front"],
    ["hall", "armchair_front"],
    ["mid", "desk_front"],
    ["hall", "mid"],
    ["mid", "south_mid"],
    ["south_mid", "dining_s"],
    ["aisle_e", "stair_foot"],
    ["attic_exit", "attic_1"],
    ["attic_1", "attic_2"],
    ["attic_2", "attic_3"],
    ["attic_3", "attic_4"],
    ["attic_4", "bed_stand"],
    ["attic_1", "attic_aisle_1"],
    ["attic_aisle_1", "attic_aisle_2"],
    ["attic_aisle_2", "reading_front"],
    ["attic_aisle_2", "attic_desk_front"],
    ["attic_aisle_2", "attic_north"],
    ["attic_north", "attic_window"],
    ["attic_north", "attic_plant_view"],
]

## Seats: [id, kind, path_node, local x, local z, floor local y (walk surface),
##         seat surface local y, furniture yaw, approach side ("back"/"front"),
##         approach distance, name]
## Seat surface = furniture base (attic: attic_floor+0.02 = 3.19, floor1: 0.57,
## porch deck: 0.42) + 0.40 for every chair/sofa/reading chair; shoe bench 0.42;
## porch bench top = deck 0.42 + 0.45 + 0.045 = 0.915.
const SEAT_DEFS := [
    ["eat_n", "eat", "shoe_front", 1.45, 1.57, 0.57, 0.97, "PI", "back", 0.55, "餐桌椅·北"],
    ["eat_s", "eat", "dining_s", 1.45, 0.03, 0.57, 0.97, "0", "back", 0.55, "餐桌椅·南"],
    ["eat_w", "eat", "mid", 0.93, 0.80, 0.57, 0.97, "PI/2", "back", 0.55, "餐桌椅·西"],
    ["eat_e", "eat", "aisle_e", 1.97, 0.80, 0.57, 0.97, "-PI/2", "back", 0.55, "餐桌椅·东"],
    ["sofa", "sit", "sofa_front", -2.10, 2.22, 0.57, 0.97, "PI", "front", 0.62, "沙发"],
    ["armchair", "sit", "armchair_front", -0.92, 1.12, 0.57, 0.97, "-PI/2", "back", 0.62, "扶手椅"],
    ["desk_chair", "sit", "desk_front", -2.62, 0.30, 0.57, 0.97, "-PI/2", "back", 0.55, "书桌椅"],
    ["shoe_bench", "sit", "shoe_front", 1.15, 2.60, 0.57, 0.99, "PI", "front", 0.55, "鞋凳"],
    ["porch_bench", "sit", "porch_bench_front", 2.30, 3.80, 0.42, 0.915, "-PI/2", "front", 0.55, "门廊长椅"],
    ["reading_chair", "sit", "reading_front", 1.60, 1.10, 3.181, 3.59, "-PI/2", "front", 0.62, "阅读椅"],
    ["attic_desk_chair", "sit", "attic_desk_front", 0.00, 1.95, 3.181, 3.59, "0", "back", 0.55, "阁楼书桌椅"],
]

## Fixed standing/view spots: [id, node, yaw_local_deg, name]
const VIEW_DEFS := [
    ["view_porch", "deck_out", 180.0, "门廊看海"],
    ["view_attic_window", "attic_window", 180.0, "阁楼窗边"],
    ["view_tree", "tree_view", 0.0, "远望大树"],
    ["view_swing", "swing_view", 0.0, "秋千旁"],
    ["view_garden", "garden_8", 0.0, "花园里"],
    ["view_front", "front_path_1", 0.0, "门前小路"],
    ["idle_living", "hall", 0.0, "起居室"],
]

## Bed geometry (attic): mattress top = furniture base 3.19 + 0.45 = 3.64;
## villager pelvis rests 0.02 above it (3.66).  Bed footprint (yaw -PI/2) is
## x [-2.95, -1.05], z [-1.40, -0.40]; headboard is the +X end (nightstand at x -1.15).
## Sitting on the south edge faces +Z (world local yaw PI); lying down rotates the
## root to local yaw -PI/2 so the model's -Z (head) points at +X (headboard).
## P9 / P7-FINALIZE（C 报告 D1/D4/D5，S1/S5）：
## - 躺姿锚点从床心 (-2.00,-0.90) 移到枕头 A 正下方 (-1.842,-0.733)：头心（模型反算相对 root
##   +0.502 x / +0.068 z，见 tools/probe_p9_life_anim.gd 实测）正好落在枕头 A（房屋局部
##   x[-1.49,-1.19] / z[-0.885,-0.445]，中心 -1.34/-0.665）上方，不再卡在两枕之间的 3 cm 缝里。
## - 坐床沿点 y 由 3.66 降到 3.62（root = 3.62+0.085 = 3.705），z 由 -0.55 放到 -0.42（床沿外沿
##   z=-0.40 → 骨盆中心离沿内缩 0.02 m，腿真正垂在床边）；配合 _bed_sit() 放长腿让鞋底落地。
const BED := {
    "id": "bed_attic",
    "kind": "bed",
    "node": "bed_stand",
    "anchor_local": Vector3(-1.842, 3.66, -0.733),
    "edge_sit_local": Vector3(-2.00, 3.62, -0.42),
    "sit_yaw_local": PI,
    "approach_local": Vector3(-2.00, 3.181, -0.10),
    "approach_yaw_local": PI,
    "yaw_local": -PI * 0.5,
    # 床的“由床沿指向床心”方向（坐床沿 root 用；躺姿锚点已不在同一条法线上）
    "inward_local": Vector3(0.0, 0.0, -1.0),
    "name": "阁楼床",
}

## Obstacle footprints for build-time validation: [name, cx, cz, hx, hz, level]
## level 0 = ground floor + porch, level 1 = attic.  Only same-level comparisons
## are meaningful because furniture at different heights overlaps in plan view.
const OBSTACLES := [
    # ---- floor1 (level 0) --------------------------------------------------------
    ["dining_table", 1.45, 0.80, 0.40, 0.65, 0],
    ["chair_eat_n", 1.45, 1.57, 0.21, 0.22, 0],
    ["chair_eat_s", 1.45, 0.03, 0.21, 0.22, 0],
    ["chair_eat_e", 1.97, 0.80, 0.22, 0.21, 0],
    ["chair_eat_w", 0.93, 0.80, 0.22, 0.21, 0],
    ["sofa", -2.10, 2.22, 0.75, 0.40, 0],
    ["coffee_table", -2.10, 1.12, 0.475, 0.25, 0],
    ["armchair", -0.92, 1.12, 0.38, 0.36, 0],
    ["desk_chair", -2.62, 0.30, 0.22, 0.21, 0],
    ["desk", -3.19, 0.30, 0.30, 0.60, 0],
    ["bookshelf", -3.34, -1.00, 0.15, 0.425, 0],
    ["tall_cupboard", -1.00, -2.60, 0.40, 0.20, 0],
    ["sideboard", 0.20, -2.60, 0.50, 0.20, 0],
    ["shoe_bench", 1.15, 2.60, 0.40, 0.16, 0],
    ["firewood_basket", -2.95, -1.70, 0.26, 0.19, 0],
    ["plant_pot_f1", 3.15, 2.52, 0.21, 0.21, 0],
    ["coat_rack", -1.15, 2.79, 0.15, 0.15, 0],
    ["floor_lamp", -3.12, 2.35, 0.18, 0.18, 0],
    # ---- attic (level 1) ---------------------------------------------------------
    ["bed", -2.00, -0.90, 0.95, 0.50, 1],
    ["nightstand", -1.15, -1.61, 0.20, 0.19, 1],
    ["wardrobe", -0.62, -2.515, 0.50, 0.275, 1],
    ["attic_bookshelf", 0.37, -2.63, 0.425, 0.15, 1],
    ["attic_desk", 0.00, 2.44, 0.60, 0.30, 1],
    ["attic_chair", 0.00, 1.95, 0.21, 0.22, 1],
    ["reading_chair", 1.60, 1.10, 0.36, 0.35, 1],
    ["attic_side_table", 1.60, 0.45, 0.20, 0.20, 1],
    ["attic_plant_pot", 2.55, 2.20, 0.21, 0.21, 1],
    # stair well openings in the attic floor (cottage stair_hole_r1 / r2)
    ["stair_hole_r1", 3.065, -1.455, 0.425, 1.335, 1],
    ["stair_hole_r2", 1.73, -2.365, 0.91, 0.425, 1],
]

static func _yaw_from_local(house_yaw: float, local_yaw: float) -> float:
    return wrapf(house_yaw + local_yaw, -PI, PI)

static func _yaw_to_face(forward: Vector3) -> float:
    return atan2(-forward.x, -forward.z)

static func _parse_yaw(s: String) -> float:
    match s:
        "PI":
            return PI
        "0":
            return 0.0
        "PI/2":
            return PI * 0.5
        "-PI/2":
            return -PI * 0.5
        _:
            return 0.0

static func _front_from_yaw(yaw: float) -> Vector3:
    return Vector3(sin(yaw), 0.0, cos(yaw))

static func _level_of_region(region: String) -> int:
    return 1 if region == "attic" else 0

## Build the walk graph + spots. Returns {"nodes", "adj", "spots", "house_yaw", "root", "obstacles"}.
static func build(cottage: Dictionary) -> Dictionary:
    var root: Node3D = cottage["root"] as Node3D
    var house_yaw := root.rotation.y
    var dock := dock_frame()
    var dock_basis := Basis(Vector3.UP, float(dock["yaw"]))
    var dock_origin: Vector3 = dock["origin"]
    var nodes: Dictionary = {}
    for d in NODE_DEFS:
        var id := String(d[0])
        var lx := float(d[1])
        var lz := float(d[2])
        var y := float(d[3])
        var mode := String(d[4])
        var region := String(d[5])
        var world: Vector3
        if mode == "terrain":
            world = Vector3(lx, W.surface_y(lx, lz), lz)
            y = world.y
        elif mode == "terrain_local":
            var w2 := root.to_global(Vector3(lx, 0.0, lz))
            world = Vector3(w2.x, W.surface_y(w2.x, w2.z), w2.z)
            y = world.y
        elif mode == "yard":
            # P4: P2-B 门前土地台面。lx/lz 是门前方院局部坐标（与房屋局部同一帧），
            # 高度取 world.gd 的台面规则 _yard_pad_y()+YARD_FLOOR_LIFT，与走道环/石板
            # 小径完全同高，绝不能退回 surface_y()（那是填方前的老地形）。
            var wy := W._yard_l2w(lx, lz)
            world = Vector3(wy.x, W._yard_pad_y(lx, lz) + W.YARD_FLOOR_LIFT, wy.y)
            y = world.y
        elif mode == "yard_bed":
            # P4-CLOSE: 土床顶面 = 台面 + YARD_BED_RISE（与 world.gd _yard_build_beds
            # 的 top_p 完全同源，实测 bed_top_spread == 0，即九床顶面同一高度）。
            var wyb := W._yard_l2w(lx, lz)
            world = Vector3(wyb.x, W._yard_pad_y(lx, lz) + W.YARD_FLOOR_LIFT + W.YARD_BED_RISE, wyb.y)
            y = world.y
        elif mode == "dock":
            # P9 / P6-VISUAL-FIX：码头局部坐标；y 是木板/石阶顶面的**世界**高度
            # （甲板 0.72 由 world.gd DECK_WORLD_Y 给定，地形在这里已经是 -5 m 深水，
            #  绝不能用 surface_y）。
            var wd := dock_origin + dock_basis * Vector3(lx, 0.0, lz)
            world = Vector3(wd.x, y, wd.z)
        elif mode == "dock_terrain":
            # 码头局部坐标 + 真实沙滩地形高度（登板前的下坡段）。
            var wdt := dock_origin + dock_basis * Vector3(lx, 0.0, lz)
            world = Vector3(wdt.x, W.surface_y(wdt.x, wdt.z), wdt.z)
            y = world.y
        else:
            world = root.to_global(Vector3(lx, y, lz))
        nodes[id] = {"id": id, "pos": world, "mode": mode, "region": region, "local": Vector3(lx, y, lz)}
    # ---- stairs from authoritative stair data -----------------------------------
    # cottage treads list = 15 entries: flight A levels 1..7, flight B levels 9..15,
    # then level 16 (the attic arrival tread).  The landing (level 8) is separate.
    var st: Dictionary = cottage.get("stairs", {})
    var treads: Array = st.get("treads", [])
    var stair_ids: Array = []
    for i in range(treads.size()):
        var t: Dictionary = treads[i]
        var c: Vector3 = t.get("center", Vector3.ZERO)
        var top := float(t.get("top", 0.0))
        var sid := "tread_%02d" % (i + 1)
        nodes[sid] = {
            "id": sid,
            "pos": root.to_global(Vector3(c.x, top, c.z)),
            "mode": "stair",
            "region": "stairs",
            "local": Vector3(c.x, top, c.z),
        }
        stair_ids.append(sid)
    var landing_center: Vector3 = st.get("landing_center", Vector3.ZERO)
    var land_top := float(st.get("land_top", 1.86))
    nodes["landing"] = {
        "id": "landing",
        "pos": root.to_global(Vector3(landing_center.x, land_top, landing_center.z)),
        "mode": "flat",
        "region": "stairs",
        "local": Vector3(landing_center.x, land_top, landing_center.z),
    }
    nodes["landing"]["local"] = Vector3(landing_center.x, land_top, landing_center.z)
    # ---- adjacency ---------------------------------------------------------------
    var adj: Dictionary = {}
    for e in EDGE_DEFS:
        _add_edge(adj, String(e[0]), String(e[1]))
    # stair chain: foot -> A treads 1..7 -> landing (level 8) -> B treads 9..15
    # (tread_08..tread_14) -> arrival tread 16 (tread_15) -> attic_exit
    if stair_ids.size() >= 15:
        _add_edge(adj, "stair_foot", String(stair_ids[0]))
        for i in range(0, 6):
            _add_edge(adj, String(stair_ids[i]), String(stair_ids[i + 1]))
        _add_edge(adj, String(stair_ids[6]), "landing")
        _add_edge(adj, "landing", String(stair_ids[7]))
        for i in range(7, 14):
            _add_edge(adj, String(stair_ids[i]), String(stair_ids[i + 1]))
        _add_edge(adj, String(stair_ids[14]), "attic_exit")
    # ---- spots -------------------------------------------------------------------
    var spots: Dictionary = {}
    for s in SEAT_DEFS:
        var sid := String(s[0])
        var node_id := String(s[2])
        var lx := float(s[3])
        var lz := float(s[4])
        var floor_y := float(s[5])
        var seat_y := float(s[6])
        var seat_yaw := _parse_yaw(String(s[7]))
        var side := String(s[8])
        var dist := float(s[9])
        var front_local := _front_from_yaw(seat_yaw)
        var sign := -1.0 if side == "back" else 1.0
        var ap_local := Vector3(lx + front_local.x * sign * dist, floor_y, lz + front_local.z * sign * dist)
        var anchor_world := root.to_global(Vector3(lx, seat_y, lz))
        var ap_world := root.to_global(ap_local)
        var front_world := (root.global_transform.basis * front_local).normalized()
        var front_flat := Vector3(front_world.x, 0.0, front_world.z).normalized()
        var yaw_w := _yaw_to_face(front_flat)
        spots[sid] = {
            "id": sid,
            "kind": String(s[1]),
            "anchor": anchor_world,
            "yaw": yaw_w,
            "approach": ap_world,
            "approach_local": ap_local,
            "approach_node": node_id,
            "approach_yaw": yaw_w,
            # P9：坐具的进入方向（"back" = 从椅背后方接近，需要弧线/侧向过渡绕开靠背）
            "approach_side": side,
            "seat_h": seat_y - floor_y,
            "level": _level_of_region(String(nodes[node_id]["region"])),
            "name": String(s[10]),
            "region": String(nodes[node_id]["region"]),
            "reserved": false,
        }
    for v in VIEW_DEFS:
        var vid := String(v[0])
        var node_id := String(v[1])
        var node: Dictionary = nodes[node_id]
        var pos: Vector3 = node["pos"]
        var yaw_w := 0.0
        var patch_target := Vector3.ZERO
        var has_target := true
        match vid:
            "view_tree":
                patch_target = Vector3(-10.90, pos.y, 4.20)
            "view_swing":
                # P9 / P7-FINALIZE：真实秋千吊点 = 大树 base + (3.0, SWING_LIMB_Y, 0) = (-7.90, y, 4.20)。
                # 旧目标 (-9.40, 6.20) 是 isle_math.SWING_X/SWING_Z 的陈旧写死值，与真实秋千差 132°，
                # 导致角色站在秋千旁却背对秋千。这里改为与 world.gd::_swing 同源派生。
                patch_target = Vector3(M.BIG_TREE_X + 3.0, pos.y, M.BIG_TREE_Z)
            "view_garden":
                patch_target = Vector3(-7.00, pos.y, -5.80)
            "view_front":
                patch_target = Vector3(16.0, pos.y, 13.0)
            _:
                has_target = false
        if has_target:
            var fwd := (patch_target - pos)
            fwd.y = 0.0
            if fwd.length() > 0.001:
                yaw_w = _yaw_to_face(fwd.normalized())
        else:
            yaw_w = _yaw_from_local(house_yaw, deg_to_rad(float(v[2])))
        spots[vid] = {
            "id": vid,
            "kind": "view",
            "anchor": pos,
            "yaw": yaw_w,
            "approach": pos,
            "approach_local": node["local"],
            "approach_node": node_id,
            "approach_yaw": yaw_w,
            "seat_h": 0.0,
            "level": _level_of_region(String(node["region"])),
            "name": String(v[3]),
            "region": String(node["region"]),
            "reserved": false,
        }
    # ---- P9：秋千座点（真实世界几何由吊点/绳长推导，与 world.gd::_swing 同源）----
    var sw_px := M.BIG_TREE_X + 3.0
    var sw_pz := M.BIG_TREE_Z
    var sw_pivot_y := W._h(M.BIG_TREE_X, M.BIG_TREE_Z) + W.SWING_LIMB_Y
    var sw_ground := W._h(sw_px, sw_pz)
    var sw_rope := maxf(2.6, sw_pivot_y - (sw_ground + 0.55))
    var sw_seat_top := sw_pivot_y - sw_rope + 0.035
    var sw_yaw := 0.0  # 摆平面沿世界 Z，人物面朝 -Z（模型正面）
    var sw_stand_ground := W._h(sw_px + 0.85, sw_pz)
    var sw_stand_pos := Vector3(sw_px + 0.85, sw_stand_ground, sw_pz)
    # 站位 yaw：面向秋千座（-X 方向）
    var sw_ap_yaw := _yaw_to_face(Vector3(-1.0, 0.0, 0.0))
    spots["swing"] = {
        "id": "swing",
        "kind": "swing",
        "anchor": Vector3(sw_px, sw_seat_top + 0.02, sw_pz),
        "yaw": sw_yaw,
        "sit_yaw": sw_yaw,
        "approach": sw_stand_pos,
        "approach_local": Vector3(sw_px + 0.85, sw_stand_ground, sw_pz),
        "approach_node": "swing_stand",
        "approach_yaw": sw_ap_yaw,
        "approach_side": "side",
        "seat_h": sw_seat_top - sw_stand_ground,
        "level": 0,
        "name": "大树秋千",
        "region": "outdoor",
        "reserved": false,
        # 供探针/报告读取的几何事实
        "pivot_y": sw_pivot_y,
        "rope_len": sw_rope,
        "seat_top_y": sw_seat_top,
    }
    # ---- P9：码头观海点（真实到达 dock_sea_watch，面朝海面）----
    var sv_node: Dictionary = nodes["dock_sea_watch"]
    var sv_dir: Vector3 = (dock["dir"] as Vector3)
    sv_dir.y = 0.0
    sv_dir = sv_dir.normalized()
    spots["sea_view"] = {
        "id": "sea_view",
        "kind": "sea_view",
        "anchor": sv_node["pos"],
        "yaw": _yaw_to_face(sv_dir),
        "approach": sv_node["pos"],
        "approach_local": sv_node["local"],
        "approach_node": "dock_sea_watch",
        "approach_yaw": _yaw_to_face(sv_dir),
        "seat_h": 0.0,
        "level": 0,
        "name": "码头观海",
        "region": "outdoor",
        "reserved": false,
    }
    var bed_anchor: Vector3 = root.to_global(BED["anchor_local"])
    var bed_edge: Vector3 = root.to_global(BED["edge_sit_local"])
    var bed_ap: Vector3 = root.to_global(BED["approach_local"])
    var bed_inward_w: Vector3 = (root.global_transform.basis * (BED["inward_local"] as Vector3))
    bed_inward_w.y = 0.0
    bed_inward_w = bed_inward_w.normalized() if bed_inward_w.length() > 0.001 else Vector3(0.0, 0.0, -1.0)
    spots[BED["id"]] = {
        "id": BED["id"],
        "kind": "bed",
        "anchor": bed_anchor,
        "yaw": _yaw_from_local(house_yaw, float(BED["yaw_local"])),
        "sit_yaw": _yaw_from_local(house_yaw, float(BED["sit_yaw_local"])),
        "anchor_edge": bed_edge,
        "inward": bed_inward_w,
        "approach": bed_ap,
        "approach_local": BED["approach_local"],
        "approach_node": String(BED["node"]),
        "approach_yaw": _yaw_from_local(house_yaw, float(BED["approach_yaw_local"])),
        "seat_h": 0.46,
        "level": 1,
        "name": String(BED["name"]),
        "region": "attic",
        "reserved": false,
    }
    return {
        "nodes": nodes,
        "adj": adj,
        "spots": spots,
        "house_yaw": house_yaw,
        "root": root,
        "obstacles": OBSTACLES,
        # 码头空间框架：钓位朝向 / 抛竿落点全部从这里派生（见 fishing_spot()）。
        "dock": dock,
    }

## Build-time geometry sanity: returns human readable issues (empty = clean).
static func validate(graph: Dictionary) -> Array:
    var issues: Array = []
    var nodes: Dictionary = graph["nodes"]
    var adj: Dictionary = graph["adj"]
    var root: Node3D = graph["root"]
    var seen: Dictionary = {}
    # 1) nodes themselves must not be inside same-level obstacles (except stair treads)
    for id in nodes.keys():
        var n: Dictionary = nodes[id]
        if String(n["mode"]) == "stair" or String(n["region"]) == "stairs":
            continue
        var lp: Vector3 = n["local"]
        var lv := _level_of_region(String(n["region"]))
        var hit := _point_blocked(lp.x, lp.z, 0.0, lv)
        if hit != "":
            issues.append("node %s inside %s" % [id, hit])
    # 2) edges: same-level obstacle sweep + region continuity
    for a in adj.keys():
        for b in (adj[a] as PackedStringArray):
            var sa := String(a)
            var sb := String(b)
            var key: String = sa + "|" + sb if sa < sb else sb + "|" + sa
            if seen.has(key):
                continue
            seen[key] = true
            var issue := _edge_issue(nodes, sa, sb, root)
            if issue != "":
                issues.append(issue)
    # 3) spot approach points must be clear, approach path from its node clear
    for sid in graph["spots"].keys():
        var sp: Dictionary = graph["spots"][sid]
        var ap_local: Vector3 = sp["approach_local"]
        var lv := int(sp["level"])
        var hit := _point_blocked(ap_local.x, ap_local.z, 0.0, lv)
        if hit != "":
            issues.append("spot %s approach inside %s" % [sid, hit])
        var node_id := String(sp["approach_node"])
        if nodes.has(node_id):
            var node_local: Vector3 = nodes[node_id]["local"]
            var seg := _segment_issue(Vector3(node_local.x, ap_local.y, node_local.z), ap_local, lv)
            if seg != "":
                issues.append("spot %s approach path from %s crosses %s" % [sid, node_id, seg])
    return issues

static func _pair_allowed(ra: String, rb: String) -> bool:
    if ra == rb:
        return true
    var pair := [ra, rb]
    pair.sort()
    var joined := String(pair[0]) + "|" + String(pair[1])
    return joined in [
        "attic|stairs", "floor1|stairs", "floor1|porch", "outdoor|porch", "attic|floor1", "outdoor|outdoor",
    ]

static func _edge_issue(nodes: Dictionary, a: String, b: String, _root: Node3D) -> String:
    var na: Dictionary = nodes[a]
    var nb: Dictionary = nodes[b]
    var la: Vector3 = na["local"]
    var lb: Vector3 = nb["local"]
    var ra := String(na["region"])
    var rb := String(nb["region"])
    if not _pair_allowed(ra, rb):
        return "edge %s-%s crosses regions %s/%s" % [a, b, ra, rb]
    # stair tread edges live inside the stair shaft; the stair geometry itself is
    # guaranteed by construction, and the attic-floor hole obstacles are handled by
    # the stair-mode exemption above.
    if ra == "stairs" or rb == "stairs":
        return ""
    if ra == "outdoor" or rb == "outdoor":
        return ""
    var lv := 1 if (ra == "attic" and rb == "attic") else 0
    if ra == "attic" and rb != "attic":
        lv = 1
    var issue := _segment_issue(la, lb, lv)
    if issue != "":
        return "edge %s-%s crosses %s" % [a, b, issue]
    return ""

static func _point_blocked(x: float, z: float, pad: float, level: int = 0) -> String:
    for o in OBSTACLES:
        if int(o[5]) != level:
            continue
        var ox := float(o[1])
        var oz := float(o[2])
        var hx := float(o[3]) + BODY_R + pad
        var hz := float(o[4]) + BODY_R + pad
        if absf(x - ox) < hx and absf(z - oz) < hz:
            return String(o[0])
    return ""

static func _segment_issue(a: Vector3, b: Vector3, level: int = 0) -> String:
    # sample the segment densely; enough for authored short edges (< 1.5 m)
    var n := maxi(4, int(ceil(a.distance_to(b) / 0.08)))
    for i in range(n + 1):
        var t := float(i) / float(n)
        var p := a.lerp(b, t)
        var hit := _point_blocked(p.x, p.z, 0.0, level)
        if hit != "":
            return hit
    return ""

static func _add_edge(adj: Dictionary, a: String, b: String) -> void:
    if not adj.has(a):
        adj[a] = PackedStringArray()
    if not adj.has(b):
        adj[b] = PackedStringArray()
    var la: PackedStringArray = adj[a]
    if not la.has(b):
        la.append(b)
        adj[a] = la
    var lb: PackedStringArray = adj[b]
    if not lb.has(a):
        lb.append(a)
        adj[b] = lb

## Shortest node path (A* over node distance). Empty = unreachable.
static func find_path(graph: Dictionary, from_id: String, to_id: String) -> PackedStringArray:
    var nodes: Dictionary = graph["nodes"]
    var adj: Dictionary = graph["adj"]
    if not nodes.has(from_id) or not nodes.has(to_id):
        return PackedStringArray()
    if from_id == to_id:
        return PackedStringArray([from_id])
    var open: Array = [from_id]
    var came: Dictionary = {}
    var gscore: Dictionary = {from_id: 0.0}
    var fscore: Dictionary = {from_id: _dist(nodes, from_id, to_id)}
    while not open.is_empty():
        var best_i := 0
        for i in range(1, open.size()):
            if float(fscore.get(open[i], 1e20)) < float(fscore.get(open[best_i], 1e20)):
                best_i = i
        var cur: String = String(open[best_i])
        if cur == to_id:
            var out: PackedStringArray = PackedStringArray()
            var c := cur
            while true:
                out.append(c)
                if not came.has(c):
                    break
                c = String(came[c])
            out.reverse()
            return out
        open.remove_at(best_i)
        for nb in (adj.get(cur, PackedStringArray()) as PackedStringArray):
            var tentative := float(gscore.get(cur, 1e20)) + _dist(nodes, cur, nb)
            if tentative < float(gscore.get(nb, 1e20)):
                came[nb] = cur
                gscore[nb] = tentative
                fscore[nb] = tentative + _dist(nodes, nb, to_id)
                if not open.has(nb):
                    open.append(nb)
    return PackedStringArray()

static func _dist(nodes: Dictionary, a: String, b: String) -> float:
    var pa: Vector3 = nodes[a]["pos"]
    var pb: Vector3 = nodes[b]["pos"]
    return Vector2(pa.x - pb.x, pa.z - pb.z).length() + absf(pa.y - pb.y) * 0.5

static func nearest_node(graph: Dictionary, pos: Vector3, region_filter: String = "") -> String:
    var nodes: Dictionary = graph["nodes"]
    var best := ""
    var best_d := 1e20
    for id in nodes.keys():
        var n: Dictionary = nodes[id]
        if region_filter != "" and String(n["region"]) != region_filter:
            continue
        var p: Vector3 = n["pos"]
        var d := Vector2(p.x - pos.x, p.z - pos.z).length() + absf(p.y - pos.y) * 2.0
        if d < best_d:
            best_d = d
            best = String(id)
    return best
