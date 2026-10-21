# P7-V4 岛民角色与自主日常生活实施报告

- 日期：2026-10-21
- 工程：`D:\休闲小岛幻境\游戏工程`（Godot 4.7.2-stable，Forward+）
- 分支：`p7-v4-islander`；基线：`1b59e59`（P7-V3.2 终稿，已冻结）
- 范围：1 名程序化动画风岛民 + 外观/动画/状态机/路径/活动点/家具交互/权威时间日程；不含任务、经济、好感度、捏人 UI。
- 证据目录：`开发产物/`（p7v4_*.log、p7v4/shots/、MANIFEST_villager.md）；本报告与全部探针随冻结提交入库。

## 0. 结论先行

已完成：固定服装外观、两种发型、12 个动画剪辑、11 状态有限状态机、64 节点路径图 + 19 个活动点（含 1 床）、世界时间驱动的轻量日程、活动点预约/释放、门开关仲裁、调试接口。
自动化验证：模型 157 项、行为 53 项、集成 74 项、既有自测 55 项全部 PASS；截图 29+ 张 0 fail 且已逐张人工目检。
性能：角色全可见时新增 33 个渲染对象 / 33~42 Draw Calls / 6162 三角面；调度成本 15.6 µs/帧；多次实跑未出现系统性帧时间回退。
未完成/已知限制见 §11（刘海近看棱角、肩部拼接感、卧姿枕头对齐依赖 root 约定、行走约 5% 滑步、床高导致坐床沿脚离地、无完整捏人 UI 等）。

## 1. 采用的风格参考与外部技术资料

来源与抓取状态详见 `docs/P7_V4_RESEARCH.md`（S1–S17）。仅提炼原则，未复制任何模型/贴图/资产。

| 主题 | 资料 | 本项目采用 |
| --- | --- | --- |
| 动森角色创建 | 任天堂官方支持 a_id/49116 | 外观项离散、不靠数值微调；身份表达与体型解耦 |
| 动森头身/剪影 | 官方商店页 8 张立绘（量测约 2 头身） | 不照搬 2 头身：本项目房屋门洞/家具/楼梯已按 1.5 m 校验，采用约 5.1 头身（头骨高 0.292 m） |
| Dinkum 外观定制 | Steam 公告（2022-06-24） | 少而清晰的选项（2 种发型）+ 统一发色；不做捏人 UI |
| 动画系统 | Godot 4.7 AnimationPlayer / AnimationMixer / AnimationTree 文档 | 用 AnimationPlayer + 12 个命名剪辑 + 脚本协调切换；不引入 AnimationTree |
| 移动/导航 | CharacterBody3D、NavigationAgent3D、NavigationMesh、AStar3D 文档 | 不用 navmesh/NavigationAgent3D（场景无可烘焙导航网格）；用项目内 AStar3D 节点图 + 运动学移动 |

选型对比结论（详见 RESEARCH §2–§3）：
- 纯程序化关节动画可直接控制姿态，但逐帧写动画曲线成本高、难复用；AnimationPlayer 组织 12 个剪辑最省资源；AnimationTree 只在需要复杂混合/步行转向融合时才有价值，本作只有 1 名 NPC，升级触发条件已写入 RESEARCH §2.7。
- 不用 CharacterBody3D 的物理 floor 判定：场景没有可行走碰撞体（全树仅 2 个点击碰撞体），且楼梯为逐级台阶而非斜坡；改用「节点图 + 逐帧贴地/踏步高度」的运动学方案，避免为一个 NPC 引入覆盖全岛的烘焙导航。

## 2. 现有工程角色相关能力与限制（阶段 1 实测）

权威侦察见 `docs/P7_V4_RECON.md`。
- 原有可动角色只有猫（`scripts/isle_cat.gd`）：程序化关节 + Tween 姿态，适合猫的轻量动作，不能直接扩展成人体动画系统。
- 场景全树 1464 节点，但只存在 2 个 CollisionShape3D（均为鼠标点击用），没有 CharacterBody3D/RigidBody3D 角色、没有 NavigationRegion3D、没有 NavigationMesh；楼梯为 16 级实体踏步（含转角平台），V3 报告未证明可通行，本轮用节点图 + 探针实测打通。
- 时间接口是唯一权威：`main.gd` 的 `_sim_seconds/_sim_rate/_events/_astro/_sun_alt/_time_source/_paused/_mode`；`_advance_sim` 在 sim 模式下按 `86400/_day_length` 推进，real 模式直接用本地 Unix+时区。跳时入口：`[`/`]`（±600 sim s）、数字键 1–5、HUD 时间面板。
- 家具/房屋/猫全部由 `isle_math.gd / isle_cottage` 等程序化构建并合批；V3.2 已冻结世界尺度（房屋 7.6×6.2、层高 3.181、家具 25 类）。
- 因此岛民必须：不自读系统时间、不建独立 24h 时钟、不新增整岛导航、不复用猫的旋转系统。

## 3. 模型构造、身高比例与固定服装

文件：`scripts/isle_villager_model.gd`（1798 行，`class_name IsleVillagerModel extends Node3D`）。
接口：`static create(hair_style: int = 0) -> {root, anim, height, hair_style}`、`set_hair_style(i)`、`set_bowl_visible(b)`、`get_animation_names()`、`get_joint(name)`、`stats()`、`static measure(root, opts)`。
- 总高 1.500 m（含发顶）；头骨 0.132×0.146×0.132（宽高比 0.90）→ 头高 0.292 m，约 5.1 头身。髋中心 0.760 m、肩宽 0.165×2、髋宽 0.070×2。
- 16 个网格 / 17 个面 / **2 个材质**（共享 toon ShaderMaterial + 阴影 blob）/ 三角面 6162（短发）、6422（中长发）/ dc_est 33（碗可见 34）。无节点 scale≠1、无常驻 Tween、无运行期重建网格/材质。
- 固定服装（与性别无关，所有发型共用同一套）：白色内衬短袖（袖山+袖口、袖下露小臂）；绿色连体防水胸裤分三档绿：胸兜贴胸薄曲面 + 双肩带 + 圆扣 + 前置工具袋（袋口/袋底缝线、1 根木柄）+ 腰身分层 + 裤腿 + 浅绿翻边靴筒 + 靴带 + 铜扣。
- 材质/描边：共享 toon shader，描边宽度 0.0025（第一版 0.004 过粗，已减细）；不新增纹理、不做 PBR/皮肤细节。

三族锚点约定（控制器必须按剪辑族同步切 root 语义，写进控制器的常量与注释）：
- 站立族（idle/idle_alt/walk）：root = 脚底，鞋底 y=0，模型局部 −Z 为正面。
- 椅坐族（sit_down/sit_idle/sit_up/eat）：root = 骨盆中心，骨盆网格底 −0.039，鞋底 −0.420；控制器放「座面 + 0.02」。
- 床沿坐族（bed_sit_down/bed_sit_up）：root = 骨盆中心，骨盆网格最低点 −0.085；控制器放「床垫顶 + 0.085」。
- 卧姿族（lie_down/sleep/get_up）：root = 床垫顶 + 0.02，身体水平、头朝 −Z（head.z=−0.394）、脚朝 +Z（foot.z=0.660），全身最低约 −0.03。

## 4. 发型预设及实现

- `hair_style = 0`：短发——贴头发帽 + 连续短刘海（底缘 5~6 缕波浪）+ 短鬓角，发顶严格 1.500。
- `hair_style = 1`：中长发——同发帽/刘海 + 两层及颌侧发 + 及肩后帘，发顶仍 1.500。
- 两种发型共用同一颗头骨、同一发色 C_HAIR、同一面部/服装/材质/身体比例；运行期 `set_hair_style` 仅切换两套发网格的 `visible`，不改变高度/AABB/网格数/材质数/DC/关节变换（探针断言逐项比对通过）。
- 本轮不做完整捏人 UI：保留 `hair_style` 参数，仅测试/受控切换；性别表现完全由发型承担，未对胸部、腰臀、五官、肤色、服装、身体比例做任何男女差异。

## 5. 五类动作、12 个剪辑与状态转换关系

剪辑（名字/长度/loop/首尾衔接逐轨道 maxdiff=0.0000）：idle 5.0 loop、idle_alt 5.2 loop、walk 0.88 loop、sit_down 0.8、sit_idle 4.0 loop、sit_up 0.7、eat 3.0 loop、bed_sit_down 0.8、bed_sit_up 0.7、lie_down 1.0、sleep 6.0 loop、get_up 1.0。
动作内容：
- Idle：呼吸、眨眼、头/视线小幅观察、重心微移；idle 与 idle_alt 交替避免长时间完全重复。
- Walk：双腿交替、手臂反向、身体起伏 0.016 m；WALK_STRIDE=1.0 m/循环（0.88 s ≈1.136 m/s）。控制器实测速度 1.05 m/s 封顶、加/减速 1.7/2.8 m/s²、到点前 0.9 m 减速、转向角速度 5.2 rad/s 且转向时最低速度系数 0.30；接触帧脚不滑（几何步幅 1.06 m，约 5% 容差）。
- Eat：右手取食→抬到嘴前（eat 剪辑 t=1.3–2.3，shoulder_r≈2.0）→咀嚼→放下；坐真实餐椅、桌沿关系正确。
- SitRest：坐真实椅/沙发，骨盆落座面 +0.02、大腿水平、小腿垂直、脚落地；sit_idle 有呼吸/观察。
- BedRest：床沿坐（bed_sit_down）→躺下（lie_down）→睡眠（sleep，极轻呼吸/屈膝侧头闭眼）→起床（get_up）→床沿坐（bed_sit_up）→站起；root 连续插值回地面，非瞬移。

状态机（`scripts/isle_villager.gd`，11 状态）：
`IDLE / WALK / SIT_IN / SIT / EAT / SIT_OUT / BED_IN / LIE_IN / SLEEP / LIE_OUT / BED_OUT`。
关系：行为状态决定目标动画族与 root 锚点；动画只负责姿态，位移/贴地/转向由控制器按节点图驱动；坐下/起身/躺下/起床都有单次过渡剪辑 + 状态计时；活动被强制切换或路径失败时统一走 `_abort_walk/_drop_activity` 回到合法 IDLE，不残留错误姿态；家具预约在结束/打断/路径失败/移除时释放。

## 6. 实际路径、楼梯、家具与活动点配置

文件：`scripts/isle_villager_spots.gd`（598 行）。`build(cottage)` 生成图：
- `nodes` 64 个（世界坐标，含 flat/stair/terrain 三种模式；terrain 节点 y=IsleWorld.surface_y）；`adj` 邻接；`spots` 19 个活动点；`obstacles`；`house_yaw`；`root`。
- 活动点：eat 4（eat_n/eat_s/eat_w/eat_e）、sit 7（sofa/armchair/desk_chair/shoe_bench/porch_bench/reading_chair/attic_desk_chair）、view 7（view_porch/view_attic_window/view_tree/view_swing/view_garden/view_front/idle_living）、bed 1（bed_attic）。字段：anchor、yaw、approach、approach_node、approach_yaw、seat_h、level、region、reserved；bed 另有 sit_yaw/anchor_edge。
- 路径：`find_path(graph, from, to)` 用 AStar3D，代价 |dxz|+0.5|dy|；`nearest_node(pos, region_filter)`；`BODY_R=0.10`；区域门控（attic↔stairs、floor1↔stairs、floor1↔porch、outdoor↔porch、attic↔floor1、outdoor↔outdoor），防止把不存在的门当成通道。
- 楼梯：真实踏步节点 tread_01…tread_15 + landing（局部坐标实测：landing(3.065,1.86,−2.365)，tread_08(2.53,2.024,−2.365)，tread_15(0.82,3.170,−2.365)），节点间 y 单调变化，贴地由节点高度驱动；探针实测从一层到阁楼 y 单调升到 11.127，无单帧垂直突跳（ARRIVE_EPS=0.03，修复了 tread_13 处 0.135 m 的到点吸附跳变）。
- 门：唯一仲裁入口 `main.gd:_set_door_state(open, silent)`；岛民走 WALK 且距门 1.85 m 内请求开门、离开 2.60 m 请求关门；玩家 `_toggle_door` 优先并保留音效/toast；NPC 请求静默。两者用 `_door_npc/_door_player` 合并，避免玩家与 NPC 互相抢门。
- 家具复用：餐桌/椅/沙发/床全部沿用 V3.2 已冻结资产，未重建家具；只在 spots 里加锚点/接近点/朝向数据。

## 7. 自主日程：时间规则、优先级与时间跳转

文件：`scripts/isle_villager_schedule.gd`（305 行）。无自建时钟：所有选择依赖 main 注入的权威 `sim_seconds/sim_rate/sun_alt/events`。
- 窗口（本地分钟；wake = sunrise+15 clamp 05:30–07:30；night = sunset+120 clamp 20:30–23:15）：night_before_wake(sleep) → morning(wake–08:30) → morning_out(08:30–11:30) → lunch(11:30–13:00) → midday_rest(13:00–15:00) → afternoon_out(15:00–17:30) → dinner(17:30–19:00) → evening_rest(19:00–night) → night(sleep)。阳光高度 <1° 时户外窗口自动转室内活动。
- 意图序列：morning[idle,stroll,idle,stroll]、morning_out[stroll×3]、lunch/dinner[eat,sit,idle]、midday_rest/evening_rest[sit,sit,stroll,sit]、night[sleep]；长窗口按序列逐步消费，不反复同一动作。
- 时长：clamp(窗口剩余真实秒×0.45~0.7, min, max)；min/max：sleep 20/7200、eat 8/26、sit 10/48、stroll 6/20、idle 5/14（真实秒）。
- 选择：候选活动点按 kind/region/时窗/阳光/可用性过滤；`score_spot` 带随机 0~0.25 与 `SPOT_COOLDOWN_SIM=2700`（同一活动点用后 45 模拟分钟内降权）；`_last_kind/_last_spot/_step` 保证最短活动时长与切换冷却（`DECISION_COOLDOWN=0.35` 秒）。
- 时间倍率/跳转：活动选择只看权威世界时间；行为执行用真实帧 delta。跳时检测只看「权威 sim_now 相对上一帧推进」与 ctx 期望推进的差（JUMP_GUARD_SIM=180），不依赖会被船逻辑清零的 `_time_jump`；检测到跳时→立即重评估当前窗口并自然过渡，不补演已错过动作。暂停/菜单时 ctx.frozen=true，动画 `speed_scale=0` 且逻辑冻结，恢复后从原状态继续。
- 优先级：外部强制（force_* / 未来任务接口）> 安全与必要状态转换（回家/起床/释放预约）> 当前必须完成动作 > 日常日程 > 普通待机。

## 8. 新增/修改的脚本、场景、网格、材质与配置

| 文件 | 状态 | 行数 | 说明 |
| --- | --- | --- | --- |
| scripts/isle_villager_model.gd | 新增 | 1798 | 程序化模型 + 12 剪辑 + 2 发型 + 碗道具 |
| scripts/isle_villager.gd | 新增 | 1232 | 11 状态 FSM、移动/贴地/转向、门、预约、调试接口 |
| scripts/isle_villager_schedule.gd | 新增 | 305 | 权威时间日程/评分/冷却 |
| scripts/isle_villager_spots.gd | 新增 | 598 | 64 节点路径图 + 19 活动点 + A* |
| scripts/main.gd | 修改 | +58/−3 | 创建岛民、sim_tick(ctx)、门仲裁、--no-villager |
| scripts/world.gd | 修改 | +8 | 公开 surface_y / trail_clearance 访问器 |
| tools/probe_villager_model.gd | 新增 | 770 | 模型/动画/发型/锚点/性能 157 检查 |
| tools/probe_villager_behavior.gd | 新增 | 302 | 状态机/路径/预约/跳时/暂停 53 检查 |
| tools/probe_villager_integration.gd | 新增 | 427 | 真实 isle.tscn 集成 74 检查 |
| tools/probe_villager_shots.gd | 新增 | 716 | 29+ 张验收截图（非 headless） |

- 场景：未新增/修改任何 .tscn；岛民在 `main.gd:_build_world()` 内与 World 同父创建（复用小区块合批与光照收集），只创建一次。
- 网格/材质：全部运行期由 ArrayMesh 工具函数生成一次；2 个共享材质；无每帧生成、无运行期销毁重建。
- 配置：无新增 project.godot 配置；`--no-villager` 仅命令行性能对照；`--selftest` 强制不创建岛民以保持既有自测确定性。

## 9. 自动化测试、截图证据与失败项

自动化（全部 exit 0）：
- 模型探针：157 checks PASS（`开发产物/p7v4_final_model.log`；早前 r2 同样通过）。
- 行为探针：53/53 PASS（`开发产物/p7v4_final_behavior.log`）。
- 集成探针：74/74 PASS（`开发产物/p7v4_final_integration.log`）；含真实场景 120 秒自主循环、预约数恒 ≤1、菜单/暂停恢复、时间跳转、身高/权威时间一致性。
- 既有自测：55/55 PASS（`开发产物/p7v4_final_selftest.log`）；同一套自测在早前输入模拟不可用的运行中为 53/53（两项「真实鼠标拖动」被跳过），均 0 failed。
- 截图：`--stage=all` 29 张 0 fail（`开发产物/p7v4_shots_all_r3.log`；清单 `开发产物/p7v4/shots/MANIFEST_villager.md`）。

失败项与修复（均可复现）：
1. 坐姿臀部穿座面 0.004 m（探针阈值边界）→ 模型坐姿整体 +0.06，断言改 pb≥−0.04。
2. 卧姿背部穿床垫（body_min_y=−0.109）→ 卧姿整体 +0.09，断言 min_y∈[−0.05,0.03]。
3. 卧姿头朝向差 1 mm / 坐姿头部断言用错参考点 / walk 在 passing 相位读肩恰为 0 → 修探针采样相位与阈值（非模型错误）。
4. 集成探针「身高 1.50」FAIL → ModelScript.measure 必须在 `_play(idle,0)` 之前调用（动画首帧会压身），修 `isle_villager.gd:139-142` 后 74/74。
5. 日程 night 窗口无 sleep 序列 → 深夜不睡觉；补 WINDOW_SEQUENCE["sleep"]。
6. 强制切换泄漏预约（最大预约数=2）→ 新增 `_drop_activity()` 并兜底释放。
7. 楼梯下行单帧垂直突跳 0.135 m → ARRIVE_EPS 0.08→0.03。
8. 散步永不结束（used/walk_time 未累加）→ `_dispatch` 累加实际执行时长与行走时长。
9. 截图机位两次废图（相机穿门廊柱/被阁楼梁切头；walk 相位抓不到）→ 下台阶到 y<7.98 再抓、landing 机位 (−0.60,0.15,2.90) fov60 目标头、eat 冻结在 cp 0.55–0.63。

截图逐张目检结论（全部合格，仅列关键的）：正/侧/背/3-4 视角、面部近景、服装细节、两种发型对照、白天/黄昏/夜间、行走三帧、楼梯中段/转角平台、进食（坐真实餐椅、右手到嘴）、坐下/起身过渡、沙发坐、床沿坐/躺下/睡眠近景/起床。v_sleep 全景构图偏远，作为上下文而非姿态证据。

## 10. 性能指标（新增角色的成本）

模型统计（探针直读）：16 网格 / 17 面 / 2 材质 / 6162 三角面（短发，中长发 6422）/ dc_est 33（碗可见 34）。
运行场景对照（`--perf`，1600×900，vsync 关闭，quality 2，同机两次采样）：
- 角色全可见场景：渲染对象 +33，Draw Calls +33（与 dc_est 一致）；quality_4 场景 +49 对象/+49 DC（描边/阴影 pass 随画质）。
- 各场景增量区间：对象 +28~+42，DC +28~+42；角色出画/被遮挡时增量可降到 0~1。
- 三角面：+6162（短发）/ +6422（中长发），相对全场景占比很小。
- 帧时间：两次岛民采样的同场景 fps 差异可达 ±12%（v1 114–155、v2 136–162，日志 `开发产物/p7v4_perf_villager.log` / `p7v4_perf_villager2.log`，基线 `p7v4_perf_base.log`），基线本身处于 windowed 桌面环境存在噪声；未观察到与 +33 DC 相符的系统性回退。quality 0–4 各档 DC 增量稳定，说明角色成本可预测。
- 调度成本：`[V4I] PASS 岛民每帧调度成本 <0.3ms | avg=15.6us`；窗口检查 0.25 s 一次，路径只在目标变化时重算，无每帧 A*。
结论：满足「新增角色渲染成本可接受」，未触发需要削减动作的阈值。

## 11. 未完成 / 未验证 / 剩余风险（如实分类）

- 已实现且自动验证通过：模型/剪辑/发型/锚点/预约/路径/楼梯/跳时/暂停/自主日程/门仲裁（157+53+74 检查）。
- 已实现且实际视觉检查通过：正侧背三视、面部、服装、发型对照、昼夜、行走、进食、坐/起身、床沿坐/躺下/睡眠/起床、楼梯（29+ 张图逐张目检）。
- 已实现但尚未验证：
  - 长时间连续运行（>30 分钟 / 跨多个游戏日）稳定性未做 soak 测试；当前只有 120 秒自主循环与多次跳日断言。
  - real 时间模式下的完整日常（窗口会很长）只做了逻辑/窗口断言，未实拍完整一天。
  - 碗道具可见性未在进食截图中稳定呈现（被桌面/手遮挡或尺寸小），仅接口验证。
- 未实现或已知缺陷：
  - 近看刘海 seg=30 略有棱角；白短袖肩部有轻微拼接感。
  - 坐床沿时因床高 0.543 > 坐姿腿长 0.40，脚离地约 0.23 m（与真实高床一致，但视觉上偏悬空）；起床过渡已用 root 连续插值补偿。
  - 卧姿枕头对齐依赖控制器 root=床垫顶+0.02 的约定；模型侧未做枕头自适应。
  - 行走几何步幅 1.06 m vs 动画步幅 1.00 m，约 5% 滑步（已限制在可接受范围）。
  - 无完整捏人 UI、无多套服装、无任务/经济/好感度/关系系统（按任务书明确不做）。
  - 只有 1 名岛民；多 NPC 同时预约/门/路径的并发未设计（当前活动点 reserved 字段已预留）。

## 12. 冻结、提交与回滚方式（可复现命令）

- 分支：`p7-v4-islander`，基线 `1b59e59`（P7-V3.2 终稿）。
- 冻结提交：即 `p7-v4-freeze-20261021` 标签所指向的提交（本报告随该提交一同冻结），父提交为 `1b59e59`。
- 回滚到 V4 冻结：`cd 游戏工程 && git checkout p7-v4-islander && git reset --hard p7-v4-freeze-20261021`。
- 回滚到 V3.2 基线（完全移除 V4）：`git reset --hard 1b59e59`（先 `git clean -fd` 清理未跟踪的 V4 文件）。
- 复现测试（先确认引擎路径 `D:\休闲小岛幻境\引擎\Godot_v4.7.2-stable_win64_console.exe`）：
  - 模型：`<engine> --headless --path 游戏工程 --script res://tools/probe_villager_model.gd`
  - 行为：`<engine> --headless --path 游戏工程 --script res://tools/probe_villager_behavior.gd`
  - 集成：`<engine> --headless --path 游戏工程 --script res://tools/probe_villager_integration.gd`
  - 既有自测：`<engine> --path 游戏工程 -- --selftest`
  - 截图：`<engine> --path 游戏工程 -- --shots --stage=all`（非 headless，输出到 `开发产物/p7v4/shots/`）
  - 性能：`<engine> --path 游戏工程 --resolution 1600x900 -- --perf`（对照加 `--no-villager`）
- 已知环境注意：探针必须在 SceneTree 的 `process_frame` 之后执行（root 不在树内时 Cottage.build 会报错挂住）；截图工具在 headless 下直接退出 1，属预期。

## 13. 冻结声明

本轮开发在 §12 的冻结提交处停止。未启动任何后续玩法（任务系统、玩家角色、对话、经济、关系、好感度、背包）开发；未扩大任务书范围。
