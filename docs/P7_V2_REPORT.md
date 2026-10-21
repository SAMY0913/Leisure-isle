# P7-V2 实施报告：海鸥行为细化、全画质夜间照明与自由飞行相机

> 项目：《休闲小岛幻境》（Leisure Isle of Dusk & Dawn）
> 工程：`D:/休闲小岛幻境/游戏工程`；引擎：`D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe`（Godot v4.7.2.stable.official.ed1daf0bf，Forward Plus）
> 分支：`p7-v2`（自 `p7-v1` HEAD `99e2fac` 建立）；基线只读 worktree：`开发产物/p7/baseline_wt`（tag `p7-baseline-20261021`），本轮未动
> 日期：2026-10-21

## 结论摘要

- **A 海鸥待机动作**：已实现。在既有程序化海鸥模型（body/head/tail/legs/wing_l/wing_r/elbow_l/elbow_r 分部节点）上，用**单一待机调度器**实现观察四周、理羽、抖羽、轻跳、调整站姿、夜间休息 6 类动作；每只鸟独立随机间隔与初相位，夜间休息权重提升，轻跳只在通过坡度/法线/空间检查的落点启用，所有动作结束后完全归位；与起飞/降落/夜间归栖状态机互不覆盖。
- **B 随机朝向、随机栖息与屋顶分布**：已实现。栖息点从修改前 26 个真实落点扩充到 **36 个**（新增门廊扶手 4 个、路灯灯帽 6 个，全部按真实几何校核）；每次新的停栖决策从全局可用落点中**加权随机重选**（不再按鸟编号固定屋脊），带屋顶区上限 2、屋脊同排上限 2、同/邻区占用惩罚与最小间距偏好；保留落点预约、占用互斥、法线/坡度/脚部间隙约束。
- **C 烟囱出烟与夜间禁停**：已实现。栖息点有效性统一由 `_perch_eligible()` 判定：炊烟窗口 11:00–13:00 / 17:00–19:00 内与夜间禁止选择烟囱；按**当前时间倍率**换算提前起飞量，正常提前驱逐不冻结烟雾；任意时刻跳入窗口时，用一次性烟雾压制（hold）作安全回退，鸟经既有起飞状态机离开后立即恢复出烟。
- **D 全画质夜间路灯照地**：已实现。根因是旧灯光收集按能量排序后按画质截断——真实场景复现：低档 budget=4、中档 6 时参与着色的路灯数为 **0**。修复后 6 盏路灯在所有画质档位固定前排参与 toon 点光，行进照明由既有 `g_l0..g_l11` + `toon.gdshader` 的 12 盏点光完成（未新增 `Light3D`、未改 Shader、未加实时阴影）；五档预算 7/8/9/11/12，窗口实测五档路面均获得暖色照地，低/极致亮度比 0.912，无过曝。
- **E 自由飞行相机**：已实现。新增独立逻辑件 `scripts/isle_flycam.gd`（纯逻辑、不拥有 Camera3D），main.gd 只做进入/每帧/退出三点接线；F 进入/退出、WASD 水平飞行、鼠标转向、Space 上升、Shift 下降、Ctrl 加速（2.0865×）、ESC 优先退出；以实测岛岸线最大直径 ≈63.6 m 校准：水平边界 R=130 m、观察范围 D=260 m、普通 10.4 m/s（穿越 D≈25 s）、加速 21.7 m/s（≈12 s）、最高 130 m；退出 0.6 s smoothstep 精确回位并恢复原自动运镜状态。
- **测试**：headless 侧新增/更新探针全绿（`probe_p7v2_bird` 681/0、`probe_p7v2_light` 窗口 88/0、`probe_p7v2_perch` 271/0、`probe_bird_p7v2` 108/0、`probe_flycam_p7v2` 219/0、`--selftest` 53/53；既有 18 项回归与 P7-V1 基线一致，无新增失败）；窗口截图覆盖五档昼夜路灯、自由视角全岛俯瞰与回位、烟囱边界前后；`--shots` / `--transition` / `--perf` 完整执行（数字见 §9）。
- **未完成/受限**：声音听感、真实玩家连续长时间主观观察、以及 61 张 `--shots` 的逐张人工复核未做；headless 无法验证材质像素与真实鼠标模式（已由窗口测试补证）；路灯灯帽落点的站立净空仅约 28.5 mm，属"达标但偏紧"的遗留风险。详见 §10。

---

## 1. 修改前的实际状态与问题证据

### 1.1 工作区核实（实施前）

- 游戏工程 git 根：`D:/休闲小岛幻境/游戏工程`；实施前分支 `p7-v1`，HEAD `99e2fac`（`feat(p7): 黄昏归栖与船鸟联动 + 昼夜协调四项修复`），**工作树干净**；另有 `main`、`p6-closeout` 分支与只读基线 worktree（`开发产物/p7/baseline_wt`，detached 7941816）。
- 本轮在上述 HEAD 上创建并切换分支 `p7-v2`，未 reset、未清理任何历史 worktree/报告/归档、未覆盖用户无关修改。
- `project.godot`：`run/main_scene="res://isle.tscn"`、Forward Plus、1440×900；修改前 InputMap 仅有 `toggle_auto_orbit`（C）等既有项，无任何飞行/相机自定义动作。
- 引擎/窗口/探针环境与 P7-V1 相同；窗口 GPU 测试串行独占（同一时间只跑一个窗口进程）。

### 1.2 修改前基线测试

全部在 `p7-v1` HEAD 的原始工作树上、修改任何文件之前采集（headless）：

| 项目 | 修改前结果 | 证据 |
|---|---|---|
| `--selftest`（headless） | 53/53 passed（1 SKIP：真实鼠标拖动） | `开发产物/p7v2/logs/baseline_selftest.log` |
| `probe_bird6` | 45/0 PASS | `开发产物/p7v2/logs/baseline_probe_bird6.log` |
| `probe_eco7` | 123/0 PASS | `baseline_probe_eco7.log` |
| `probe_smoke6` | 96/0 PASS | `baseline_probe_smoke6.log` |
| `probe_boat_p5` | 76/0 PASS | `baseline_probe_boat_p5.log` |
| `probe_p7c` | 38/0 PASS | `baseline_probe_p7c.log` |
| `probe_world_p5` | PASS | `baseline_probe_world_p5.log` |
| `probe_lighthouse_p5` | 17/0 PASS | `baseline_probe_lighthouse_p5.log` |
| `probe_frame_t5` | 5/0 PASS | `baseline_probe_frame_t5.log` |
| `probe_settings6` | ALL PASS | `baseline_probe_settings6.log` |
| `probe_quality6` | rc=0 | `baseline_probe_quality6.log` |
| 基线总览 | 全绿 | `开发产物/p7v2/logs/baseline_index.txt` |

> 说明：窗口基线 `--perf` / `--shots` 在 08:53 之后启动，此时 Lead 的夜间灯光改动已于 08:52:36 落盘，因此**该窗口基线不是严格"修改前"数值**；headless 功能基线使用上表。性能对照在 §9.5 以 08:55 同会话 `baseline_perf_q2.log` 作最接近的近似参考（已含 D 改动，仅用于检测方向性退化），并另列 `docs/P7_V1_REPORT.md` 的同机 17 条 `[PERF]` 与 VRAM 作为跨会话历史参考；两者均非严格同热状态改前基线，已在 §9.5 / §10.2 明确标注。

### 1.3 五个问题的根因与证据

| # | 问题 | 实际根因（修改前代码） | 证据 |
|---|---|---|---|
| A1 | 海鸥落地后基本静止、姿态机械 | `fx.gd::_pose_perched` 只有收翼 + 头部正弦摆动（`look=sin(_t*0.65+phase*2.7)*0.26`），没有待机动作、没有逐鸟动作调度 | `scripts/fx.gd` 原 `_pose_perched`；headless 观察 `debug_snapshot()` |
| B1 | 三只海鸥长期固定在屋脊同一排 | `_reseat_all(initial)` 对 `index<3` 强制 `_find_free_slot_kind("ridge")`；`_update_perched` 对 `kind=="ridge"` 的鸟白天**永不主动起飞**（硬编码特例）；`_find_free_slot` 取"全局最近空槽"，无分散意识 | `scripts/fx.gd` 原 `:2114/:2381` 段 |
| B2 | 门廊栏杆、路灯顶部等真实表面未被利用 | `cottage.gd::_make_perches` 只有屋脊3+屋檐4+烟囱1+门廊梁2=10；`world.gd::_build_perches` 只有树/灯塔/码头/花园门柱=16；均无门廊扶手与路灯灯帽点 | `scripts/cottage.gd`、`scripts/world.gd` 修改前代码；实测扶手/灯帽为真实实体表面 |
| C1 | 海鸥可能停在烟囱上被出烟穿过 | 无"烟囱不可用"判定；栖息点选点/落点复核都不检查炊烟窗口与夜间；无提前驱逐、无跳时保护 | `fx.gd` 原 `_find_free_slot`/`_normalize_perches`；`isle_smoke` 窗口常量 |
| D1 | 低/中画质夜间道路无照明 | `main.gd::_collect_lights` 将 cottage+world 全部 18 个光源按 energy 降序后 `slice(0,12)`；`_update_lighting` 再按 `light_budget`（旧值 4/6/8/10/12）截断。6 盏路灯 energy=1.35 排在 1.60/1.50/1.42/1.40 之后。**在真实场景上复现旧算法**：budget=4 → 路灯 0 盏（全是环境灯）、budget=6 → 路灯 0 盏、budget=8 → 2 盏、budget=10 → 4 盏、budget=12 → 6 盏 | `开发产物/p7v2/logs/lead_old_light_algo.log`（[OLD] 行） |
| E1 | 无自由飞行观察模式 | 相机只有轨道相机与菜单电影机位；`_update_camera` 每帧只由 `_auto_orbit/_theta/_elev/_radius` 写变换；InputMap 无飞行动作 | `main.gd` 修改前 `_update_camera/_unhandled_input`；`project.godot` |

补充说明（D）：道路不是独立贴片网格，而是地形（MeshInstance3D "Terrain"）的**顶点色**；地形材质 `IsleMath.terrain_material()` 使用自定义 `toon.gdshader`（unshaded/自定义光照），不接收引擎 `Light3D`。因此问题只能是"12 盏全局点光里没有路灯"，而不是"灯节点不够亮"。

### 1.4 既有机制复用与保护

- **海鸥**：全部行为增量建立在既有 `BirdFlock` 状态机（`FLY/TAKEOFF/LANDING/PERCH`）、逐鸟字典、`_find_free_slot/_reserve_slot/_release_perch/_apply_perch_pose`、昼夜滞回（-2°/+2°）、P7-V1 `ROOST_*` 黄昏归栖与 `on_boat_shore_pass` 之上；未新建第二套状态机、未重复实现归栖/船鸟联动。
- **烟囱/时间**：炊烟窗口常量（`SMOKE_WINDOW_A/B`，左闭右开）与 `-2°/+2°` 夜间判定均沿用既有实现；只新增"落点资格"接口与提前驱逐，不新建时钟。
- **灯光**：复用既有全局 `g_l0..g_l11`（12 盏）+ `toon.gdshader::add_point_light` 管线与既有 `lanternI` 昼夜渐变；未新增 `Light3D`、未改 Shader、未加实时阴影。
- **相机**：自由相机只作为逻辑件接入，轨道相机参数冻结/恢复；未重写 `main.gd` 相机体系，未动菜单转场、点击交互、自动运镜与设置持久化。
- **画质**：仅调整 `light_budget` 预设值与保底逻辑；其余画质键、`_apply_quality` 消费方式不变。

---

## 2. 外部调研与最终设计选择

### 2.1 参考资料（实际抓取）

- **海鸥停栖行为**：Beauchamp (2009) `Sleeping gulls`（PMC2657747）——睡眠中的海鸥仍会睁眼"peek"扫描，邻居警觉会打断/增加警戒扫描；群体中理羽、睡眠、警戒并存，个体不同步。→ 本项目待机动作采用 look/preen/rest 组合，**个体错峰**，夜间休息权重最高，不追求"同步表演"。
- **海鸥理羽/姿态图片**（Getty 等）：仅用于理解头颈转向、身体重心的姿态常识；**未下载/未使用任何受版权保护的图片或模型资产**，全部动作用程序化节点变换实现。
- **Godot Free Look Camera 1.2.0**（Godot Asset Library #1317，MIT）：自由相机社区习惯——鼠标观察 + WASD 移动 + 垂直键 + 加速键。→ 只借鉴输入处理思想与操作习惯，**未安装插件**，在本项目 InputMap 内实现。
- **Godot 4.7 输入文档**（`tutorials/inputs/input_examples.html`）：InputMap 动作、`Input.get_vector`、`InputEventMouseMotion.relative`。→ 新增 8 个正式 InputMap 动作（`fly_toggle` 等），在 `_unhandled_input` 中按模式优先消费。
- **Minecraft 飞行机制**：普通飞行 10.92 m/s、加速 21.6 m/s（≈2×）、加速 FOV +10%。→ 只作为"速度量级与加速倍率"的比较基准；本项目按实测地图尺度 D 自行标定（§8.1），未照搬数值。

### 2.2 设计取舍

| 议题 | 选择 | 理由 |
|---|---|---|
| 海鸥动画 | 程序化节点变换 + 单调度器 | 模型无骨骼；新增骨骼/Tween 系统会显著放大复杂度；单调度器避免 10 只鸟 10 个 Timer |
| 栖息点随机 | 加权随机（区权重×占用惩罚×间距偏好）+ 上限 | 纯均匀抽签会过度集中/过度分散；权重法实现简单、可实测 |
| 烟囱避让 | 统一 `_perch_eligible`，按时间倍率算提前量 | 所有选点路径共用一套判定，不在每只鸟脚本重复写时间判断 |
| 跳时穿模 | 一次性烟雾压制（hold）回退 | 禁止删除海鸥/关闭烟囱；hold 只在"跳入窗口时鸟尚未离开"触发，正常提前驱逐不触发 |
| 夜间照地 | 修灯光收集/预算，不新增 Light3D | 道路材质是自定义 toon 顶点色，Light3D 无效；既有 12 盏点光管线已验证可用、成本低 |
| 自由相机 | 独立逻辑件 + main 三点接线 | 避免轨道/自由两套相机同时写同一变换；逻辑件可在 headless 单测 |

---

## 3. 修改文件、模块职责与边界

| 文件 | 改动量 | 职责 |
|---|---|---|
| `scripts/fx.gd` | +691 / −62（现 3395 行） | A/B/C 全部海鸥行为：待机调度器与姿态、区域/分散选点、烟囱资格与提前驱逐、跳时烟雾 hold、探针接口；未新建状态机 |
| `scripts/cottage.gd` | +30 / −5 | 新增 4 个真实门廊扶手落点（porch_rail_L/R/FL/FR，slots=1）；`_mk_perch` 支持可选 slots |
| `scripts/world.gd` | +55 / −4 | 新增 6 个真实路灯灯帽落点（lamp_0..5，slots=1）；`_build_perches` 接收 lamps（第 4 参默认 []，旧三参兼容仍 16 点） |
| `scripts/main.gd` | +221 / −11 | D：路灯优先的光源收集、画质预算保底、debug_light_state；E：IsleFlyCam 创建/接线/输入隔离/退出恢复/debug_flycam；C：`_update_smoke_clock` 传入 bird smoke hold；`_eco_ctx` 增加 sim_rate；`_sim_rate` 记录 |
| `scripts/isle_quality.gd` | +6 / −4 | 五档 `light_budget` 4/6/8/10/12 → 7/8/9/11/12（保证 6 盏路灯 + 船灯不被截断），注释说明 |
| `scripts/isle_flycam.gd`（新增，+uid） | 470 行 | 自由飞行相机纯逻辑件：输入、速度阻尼、边界、FOV、退出混合、调试状态 |
| `project.godot` | +40 | 新增 8 个正式 InputMap 动作：`fly_toggle`(F)、`fly_forward`(W)、`fly_back`(S)、`fly_left`(A)、`fly_right`(D)、`fly_up`(Space)、`fly_down`(Shift)、`fly_boost`(Ctrl) |
| `tools/probe_p7v2_bird.gd`（新增，987 行） | 测试者终验探针 | A/B/C 不变量、边界、跳时、倍率、分布 |
| `tools/probe_p7v2_perch.gd`（新增，842 行） | perch-dev 探针 | 36 个真实落点的几何贴合、净空、fx 接受、夜间稳定 |
| `tools/probe_p7v2_light.gd`（新增，524 行） | 测试者终验探针 | 五档光源清单 + 窗口逐盏隔离像素证据 |
| `tools/probe_p7v2_flycam.gd`（新增，348 行） | 测试者终验探针 | 从 `main.debug_flycam()` 读实际边界/速度并验证控制与恢复 |
| `tools/probe_bird_p7v2.gd`（新增，827 行） | bird-dev 自测 | 动作/错峰/跳时 hold/分布统计 |
| `tools/probe_flycam_p7v2.gd`（新增，797 行） | flycam-dev 自测 | 219 断言相机逻辑回归 |
| `tools/probe_p7v2_shots.gd`（新增） | 测试者终验探针 | 30 张 suite 截图（道路五档/海鸥待机/栖点/烟囱边界/自由视角），输出 `开发产物/p7v2/shots/suite/` |
| `tools/probe_p7v2_light_shots.gd` / `probe_p7v2_flycam_shots.gd`（新增） | 窗口截图探针 | 五档夜景/黄昏/白天 12 张；自由视角 5 张 |
| `tools/probe_bird6.gd` / `probe_cottage6.gd` / `probe_frame_t5.gd` | 更新断言 | 旧口径与新验收冲突的断言更新（屋顶排队、cottage 落点数 10→14、分布不变量） |

**未修改**：`shaders/` 下全部 shader（toon/sea/sky/post/glass/grass…）、`scripts/isle_astro.gd`、`isle_time.gd`、`isle_palette.gd`、`isle_audio.gd`、`isle_settings.gd`、`hud.gd`、`menu.gd`、场景 `isle.tscn` 与任何资源/模型/音频文件。改动合计（tracked）：**1170 insertions / 148 deletions**（另新增 1 个脚本 `isle_flycam.gd` 与 9 个探针文件）。

> 备注：`main.gd::_run_shots` 内新增了截图专用 helper `_stage_bird_for_shot(index, perch_kind)`（通过 `debug_force_perch` 把 2 只鸟预置到真实屋脊栖点，仅用于官方 `04_bird_perch`/`06_bird_roof` 取景，不影响生态规则运行），约 +35 行已计入 main.gd 总量。

### 3.1 边界

- 生态行为全部在既有 `BirdFlock` 内增量实现；无第二状态机、无第二时钟。
- 灯光仍走既有 12 盏全局 uniform 管线；无新增 `Light3D`、无每帧新建节点/材质、无实时阴影。
- 自由相机逻辑件不拥有 Camera3D、不改场景物体世界坐标；main 只在进入/每帧/退出三点调用。
- 烟囱窗口、夜间判定、自动运镜、菜单、点击交互、设置持久化、HUD 结构均沿用既有实现。

---

## 4. 任务 A：海鸥落地后的待机动作

### 4.1 现有模型能力（先检查）

程序化海鸥模型（`fx.gd::_make_bird`）为纯 Node3D + 网格组合，节点原点在脚底、局部 +Z 为前向，可独立控制的分部：

`body`（躯干）、`head`（含眼/喙）、`tail`、`legs`、`wing_l/wing_r`（翼根）、`elbow_l/elbow_r`（翼肘，嵌套在翼根内）、`wing_outer`。**没有骨骼/蒙皮**。因此待机动作全部用分部节点的局部 rotation/position 程序化实现，未新增模型或动画文件。

### 4.2 动作种类与表现（≥4 类要求，实际 6 类）

| 动作 | 预期表现 | 实现（fx.gd:3148-3183） | 幅度/时长 |
|---|---|---|---|
| `look_around` 观察四周 | 头部左右轻转、偶尔低头警戒，不规则间隔 | 头部 yaw 叠加 `side*sin(it*2.1)*0.55*env`，head.x −0.18·env | 1.1–2.2 s |
| `preen` 理羽 | 头转向翼侧并低头，同侧翼面微抬、翼肘内收 | head.x +0.72·env、head.y +side·0.95·env；同侧 wing.z +0.42·env、elbow.y ∓0.25·env | 1.2–2.4 s |
| `shake` 抖羽 | 身体短促小幅抖动、双翼高频错相位羽颤，随后自然恢复 | body.z ±0.10·env、head.y +f·0.34、tail.x +f·0.10，双翼 `sin(it*46+2.2/3.9)*0.075` | 0.45–0.75 s |
| `hop` 轻跳 | 小幅向上、短暂离面后落回原落脚点 | 沿落点法线 `sin(pi*q)*hop_h`，legs.x −0.30·env、body.x −0.10·env | 0.34 s，峰值 0.11 m（随机 0.75–1.15×） |
| `adjust_stance` 调整站姿 | 双脚不动、身体/头部微调方向 | body.z side·0.07·env、tail.x 摆动、head.x −0.08·env | 0.8–1.4 s |
| `rest` 休息/睡眠 | 头部收拢下压、身体略放松 | head.x +0.62·env、head.y 衰减 85%、head.z side·0.16·env、legs.x −0.18·env、body.x +0.06·env | 2.4–4.5 s |

- 所有动作共享平滑包络 `env = smoothstep(0,0.16,q) * (1-smoothstep(0.80,1.0,q))`，`q=t/dur`；动作结束后 `env→0` 且所有通道经 lerp 收敛回基础停栖姿态（收翼、tail.x=−0.16、legs.x=0、头部基础 look），**不会残留偏移**。
- 轻跳只在 `slope ≤ 10°`、`normal.y ≥ 0.95`、落点槽位合法时进入动作候选；跳跃位移只沿表面法线，脚底不进入屋面/栏杆/灯具网格（probe 实测峰值 0.1099 m、回槽误差 ≤1e-4）。
- "跳跃"明确是风格化小岛动画，不宣称是已证实的特定海鸥行为。

### 4.3 调度（单调度器、逐鸟独立、夜间偏静）

- **单一调度器** `_update_idle(delta)`（fx.gd:2400）遍历 10 只鸟，无 per-bird Timer/Tween 常驻。
- 每只鸟落地稳定后先随机静置 `idle_cool = 0.8–2.4 s`（`_begin_landing` 落位时重置，fx.gd:3030-3032），随后才可能出现第一个动作。
- 动作间隔：白天 `2.2–7.5 s`；夜间 `2.0–6.0 s`（更长安静期）；动作结束后重新随机冷却，**不会连续高频跳跃/连续抖羽/不停转头**。
- 每次动作开始时由 `_idle_pick_action`（fx.gd:2353）按权重抽取：
  - 白天：`look 3 / preen 2 / shake 1.2 / adjust 1`（轻跳安全时 +hop 1.3）；
  - 夜间：`rest 8 / look 1.2 / preen 0.8`（跳跃与抖羽不进入夜间候选）；
  - 黄昏归栖 ACTIVE：`look 1 / preen 1.2 / rest 1`（安静，不干扰归栖）。
- 初相位/动作随机数使用独立 `_vis_rng`（seed 77123），与栖息/飞行随机流 `_rng` 分离：不会因为飞行决策改变待机节奏，也保证 10 只鸟不同步（probe 实测 10 只鸟首个动作起始帧各不相同）。
- 动作开始条件：鸟必须仍为 `PERCH` 且 `idle_active` 合法；任何状态切换立即 `_cancel_idle`。

### 4.4 与状态机的衔接（不反向覆盖）

- `_release_perch` / `_set_fly` / `_begin_takeoff` / `_begin_landing` 都会先 `_cancel_idle`；起飞瞬间 `_snap_perch_foot` 清掉当前跳跃偏移，避免带位移起飞。
- `_update_visuals` 仅在 `PERCH` 状态把 `node.position = 槽位点 + idle_off`（fx.gd:3248 附近）；飞行/起降状态位置完全由状态机/速度驱动，待机偏移不参与。
- 待机动作只写分部节点局部 rotation 与一个沿法线的小偏移；不写 `node.basis`（停栖基仍由落点法线决定），因此不会破坏脚部贴面关系。
- 夜间归栖、船鸟响应、时间跳转等行为照旧；待机动作不会让鸟主动起飞或改变落点。
- 夜间：以既有 `_night`（太阳高度滞回 −2°/+2°）为准，不另建夜间判定。

### 4.5 验证

- `probe_bird_p7v2.gd`（bird-dev，827 行）**PASS 108/0**：5 类以上动作实际触发、夜间 rest 次数 4369 vs 其他动作 1010、10 鸟首个动作起始帧全不同、轻跳峰值 0.1099 m / 回槽 ≤1e-4、夜间/黄昏权重、动作结束姿态恢复。
- `probe_p7v2_bird.gd`（tester，987 行）**PASS 681/0**：覆盖动作调度、边界（60×/1440× 倍率）、烟囱窗口、跳时 hold、屋顶分布等。
- 窗口截图：海鸥近景（开发产物/p7v2/shots，见 §9）可辨识头颈转向、理羽低头与抖羽姿态变化；远机位未见夸张抖动。

---

## 5. 任务 B：随机朝向、随机栖息与屋顶分布

### 5.1 栖息点清单（真实几何，26 → 36）

修改前共 26 个真实表面点：小屋 10（屋脊3、屋檐4、烟囱1、门廊梁2）+ 世界 16（大树6、灯塔4、码头2、花园门柱4）。本轮新增 10 个**真实存在结构**上的落点：

| 来源 | 新增点 | 依据的真实几何 | 参数 |
|---|---|---|---|
| `cottage.gd` | `porch_rail_L/R`（侧栏）、`porch_rail_FL/FR`（前栏） | `_porch`：侧栏 `M.box(0.10,0.09,2.60)` 中心 (±4.12, deck_top+0.895, 5.78)，顶面 y=deck_top+0.94；前栏 `M.box(2.24,0.09,0.10)` 中心 (±3.00, deck_top+0.90, 6.95)，顶面 y=deck_top+0.945；立柱间自由段取中点 | pos=顶面+0.03 gap；facing 沿栏杆（侧栏 +Z、前栏 +X）；radius 0.18、normal UP、slope 0、slots=1 |
| `world.gd` | `lamp_0..5` 灯帽顶 | `_lamp()`：灯帽上盖 `cyl(top_r 0.13, h 0.06)` 中心 local (0.42, 2.15, 0)，顶面 local y=2.18；吊杆 r=0.013 在 (0.42,2.19)，故侧偏 0.105 m（<0.13 帽半径）避开吊杆 | pos=灯帽顶+0.03；facing 朝路；radius 0.20、normal UP、slope 0、slots=1 |

- 合计 36 个落点、36 个槽位，区域分布：`tree 6 / lighthouse 4 / dock 2 / garden 4 / lamp 6 / roof 8 / porch 6`（probe 输出）。
- `world.gd::_build_perches` 第 4 参 `lamps:Array=[]` 有默认值，旧三参调用仍返回 16 点（兼容旧探针）；12 个旧行为点（pos/facing/radius/kind）完全不变，不产生回归。
- 所有新点由 `isle_fx` 的 `_normalize_perches` 正常接受（无点被丢弃），脚部间隙 0.03 m，probe 校验灯帽/扶手垂直间隙 0.0300、灯帽净空 body ≥0.0285 m / legs ≥0.0305 m、脚点距吊杆 0.092 m。

### 5.2 朝向约束（几何决定，不做落地后无约束随机旋转）

- 每个落点在数据层给出**已验证的合理朝向** `facing`：屋脊/门廊梁/门廊扶手沿结构长轴；屋檐沿屋檐外法向（朝外、不穿墙/瓦/窗）；树/灯塔/码头/花园门柱朝安全外侧或岛心；路灯灯帽朝道路侧。
- `_perch_basis`（fx.gd:2043）把 +Y 对齐落点法线（超过 35° 夹紧），+Z 取 facing 在切平面上的投影；屋檐倾斜面上鸟体随法线倾斜、脚底沿法线抬 0.02 m（`PERCH_FOOT_LIFT`），脚部贴面关系不变。
- **"随机"体现在每次停栖决策从 36 个候选落点及其验证朝向西中重新选择**，而不是落地后再随机转 yaw/pitch/roll；因此不会出现朝向穿墙、勾住栏杆、站在灯罩内部等错误姿态。
- 若某落点的实际几何不允许安全朝向，其 `slope/normal/radius` 或选点位置已被排除（如灯帽侧偏保证不压在吊杆上）。

### 5.3 选点算法（加权随机 + 分散意识 + 上限）

修改前：`_find_free_slot` 取"全局最近空槽"，且初始 3 只强制屋脊、屋脊鸟白天不主动起飞 → 三只排队。修改后（fx.gd:2081-2290）：

1. `_collect_free_slots` 收集所有"当前可用且未占用"的槽位，先做硬过滤：烟囱资格、屋顶区占用上限 `PERCH_ROOF_ZONE_MAX=2`、屋脊同排上限 `PERCH_RIDGE_ROW_MAX=2`。
2. 对每个候选计算权重 `_slot_weight`：
   - 区域权重（白天 lighthouse 1.05 / tree 1.0 / roof 0.95 / dock 0.9 / porch 0.8 / garden 0.65 / lamp 0.55；夜间 tree 1.25 / lighthouse 1.1 / roof 1.0 / porch 0.6 / dock 0.55 / garden 0.45 / lamp 0.4）；
   - 同区已占用惩罚 `(1+zone_used)^-0.35`、同落点已占槽惩罚 `(1+slot_used)^-0.35`；
   - 空间分散偏好：`0.2+0.8*min(dist_to_nearest_bird/6.0)`，并轻微偏好离当前起飞点较近的落点（避免长途横穿）。
3. 加权随机抽签（非"最近空槽"），选中后走既有 `_reserve_slot` 占用互斥。
4. 若硬过滤后无解：先按 `relax_caps` 放宽屋顶/屋脊上限（仍**永不放宽烟囱资格**），记 `cap_fallbacks`；仍无解则 `waiting=true` 跳过本次降落（`no_slot_skips`），**无无限重试**。
5. 鸟起飞时 `_release_perch` 立即释放槽位，其他鸟可用；`_check_perch_validity` 每 2 s 清理失效落点。
6. 移除 `_reseat_all` 的"index<3 强制屋脊"与"ridge 白天永不主动起飞"特例：所有鸟按同一套随机规则选点，并在既有 `BIRD_TIMER_MIN/MAX` 计时器自然起飞后重新随机选择；不会为了分散而频繁起飞。

---

## 6. 任务 C：烟囱出烟期间与夜间禁停

### 6.1 权威时间与窗口（沿用既有规则，未新造时钟）

- 炊烟窗口仍为 `IsleFx.SMOKE_WINDOW_A = 11:00–13:00`、`SMOKE_WINDOW_B = 17:00–19:00`（左闭右开，单位游戏本地秒），窗口、1.5 s 爬升（`SMOKE_RAMP_SECONDS`）与粒子实现完全未改（`fx.gd:596-620`）。
- 每帧由 `main._update_smoke_clock()`（main.gd:1145）把 `fposmod(_sim_seconds, 86400)` 传给 `IsleFx.set_sim_seconds(sim, hold)`，其中 `_sim_seconds` 是项目既有模拟时间源（`isle_time.gd`），时间流速、时间跳转、时间源切换全部沿用原逻辑。
- 夜间判定沿用 `BirdFlock` 既有 `_night`（由太阳高度带滞回 −2°/+2° 得出，P7-V1 归栖同一状态），**没有**新增写死 `18:00` 的夜间判断。

### 6.2 落点资格接口（所有选点路径统一调用）

`fx.gd` 新增 `_perch_eligible(perch, sim_seconds, sun_alt, night, sim_rate) -> Dictionary`（fx.gd:2157），对 `kind != "chimney"` 恒返回可用；仅对烟囱点依次判断：

| 条件 | 判定 | reason |
|---|---|---|
| 当前模拟时间在任一炊烟窗口内 | 不可用 | `"smoke"` |
| 既有夜间状态为真 | 不可用 | `"night"` |
| 距离下一个窗口开始 ≤ 提前量 | 不可用（`lead_left` 返回剩余秒） | `"smoke_lead"` |
| 其他 | 可用 | `""` |

- 提前量 `_smoke_lead_seconds = (BIRD_TRANSITION_MAX + PERCH_SMOKE_LEAD_BUFFER) * max(sim_rate, 0.001)` = `(1.0 + 0.35) s × 时间倍率`（fx.gd:2153）。因 `sim_rate` 由 `main._eco_ctx()` 提供（模拟源 = 86400/day_length，真实源 = 1.0，main.gd:621/717），无论 60×、144× 还是 1440×，换算到游戏时间的提前量始终覆盖"0.6–1.0 s 起飞过渡 + 0.35 s 缓冲"，**不是硬编码单一时间流速的常数**。
- 候选收集 `_collect_free_slots`（fx.gd:2247）先做资格硬过滤；即使屋顶/屋脊上限进入 `relax_caps` 兜底，**烟囱资格永不放宽**。`_begin_landing` 飞行末段与落位瞬间都会再查一次 `_perch_eligible_now`，防止"选中后被占用/时间跨入窗口"的竞态。
- 烟囱被禁用不影响其他建筑、屋顶、栏杆、灯塔、灯帽落点：仅一个 kind 被过滤。

### 6.3 提前驱逐与时间跳转安全回退

- 每帧 `_update_perch_evictions()`（fx.gd:2451）检查停在烟囱上的鸟：一旦资格变为不可用，走既有 `_begin_takeoff` 正常起飞状态机离开（不瞬移），并累计 `chimney_evictions`。夜间入夜同理：先起飞，再按新的随机选点去其他有效落点。
- 正常情况：在窗口开始前的提前量内鸟已离场，烟雾按 1.5 s 正常爬升，`smoke_hold_count = 0`（实测 600 s 日长、144× 下 10:57 起飞，距 11:00 有 180 游戏秒 < 194.4 s 提前量）。
- **时间轴突然跳入窗口**（如时间面板 / 快捷键跳时）：bird 侧立即触发驱逐并把 `_smoke_hold_t` 置为 `BIRD_TRANSITION_MAX + 0.6 = 1.6 s`（真实秒）。`main._update_smoke_clock` 把 `smoke_hold_remaining() > 0` 作为 `hold` 传给 `ChimneySmoke.set_sim_seconds(sim, hold)`：
  - hold 期间**仍更新** `_last_sim`、窗口状态、时间标签，但强制 `_ramp=0 / _ratio=0 / amount_ratio=0 / emitting=false`，即粒子不生成；
  - 一段连续压制只记 1 次 `_hold_count` 与 `_last_hold_reason="bird_on_chimney"`，可在 `debug_state()/smoke_debug()` 查；
  - 鸟起飞完成后 hold 自然到期，粒子从 0 按 1.5 s 爬升正常恢复，不会整段消失或永久关闭。
  - 该路径是**异常跳时的安全回退**，不是常规行为：正常提前驱逐不触发 hold（实测 hold_count=0）。
- 不发生"删除海鸥网格/关闭烟囱系统/永久禁用落点"之类绕过。

### 6.4 边界验证（实测）

- `probe_p7v2_bird.gd`（tester）**PASS 681/0** 覆盖：10:59 / 11:00 / 13:00、16:59 / 17:00 / 19:00、正常日落入夜、白天直接跳夜、烟囱有人跨窗口、60×/1440× 倍率跨边界；断言窗口内部无新烟囱落点、窗口内已有鸟会离开、夜间无新烟囱落点、其他 kind 不受影响。
- Lead 用真实 `isle.tscn` + 真实 `main._update_smoke_clock` 的整合探针（20 断言全过，临时文件已删）：
  - 正常路径：10:54 强制落 `chimney_0` → 10:57 起飞离开，hold=false、hold_count 0；
  - 跳时路径：12:00 → 11:05 同帧 hold=true、emitting=false、ratio=0、hold_count 0→1；跳转帧鸟仍在烟囱（min_dist 0.067 m）但烟被压制；1.5 s 内采样 220 帧无"鸟+烟"近距重叠；hold 释放时鸟已离 4.473 m；推进 18 游戏秒后 emitting=true、ratio=1.000，min_dist 4.473 m。
- 逻辑层无重复触发、无永久锁定：`debug_perch_stats()` 暴露 `smoke_hold/hold_reason/chimney_evictions`，多轮起降窗口探针确认 hold 计数按段增长而非每帧增长。

---

## 7. 任务 D：五档画质下夜间路灯照地

### 7.1 真实渲染管线检查结论

- **道路没有独立网格**：道路是地形顶点色的一部分（`world.gd::_build_terrain` 的 `Terrain` MeshInstance3D），材质为 `IsleMath.terrain_material()` → 自定义 `toon.gdshader`（顶点色 + 细节贴图 + **12 盏自定义点光数组** `g_l0..g_l11` + `g_light_count`）。因此 `Light3D` 不会照亮道路，只加灯节点无效。
- 六盏路灯在 `world.gd::_street_lamps()`（3 盏主路 `PathLamp` + 3 盏花园 `GardenLamp`），每盏返回真实灯罩世界坐标 `l[2].pos`（灯罩中心）、暖色 `(1.0,0.76,0.45)`、能量 1.35、半径 7.5。
- 灯光数组由 `main._collect_lights()` 收集、`_update_lighting()` 每帧写入 12 盏 `g_l{i}_pos/col`；`toon.gdshader::add_point_light` 已有距离衰减（`clamp(1-dist/range)^2`）+ half-Lambert，材质本身能接收这路光。

### 7.2 根因（修改前复现）

- 旧 `_collect_lights()` 把全部 18 个光源（含小屋门灯 1.65 / 壁炉 1.60 / 阁楼灯 1.5 等）**按能量降序**取前 12；6 盏路灯能量 1.35 排在末尾。
- 旧 `_update_lighting()` 再按画质 `light_budget` 截断有效光源数（旧预算：低4 / 中6 / 高8 / 极高10 / 极致12）。用旧算法真实复现（日志 `开发产物/p7v2/logs/lead_old_light_algo.log`）：`sources=18 top12=12`，energies `[1.65,1.60,1.50,1.42,1.40,1.35×7]`；各档实际参与着色的路灯数为 **低 0 / 中 0 / 高 2 / 极高 4 / 极致 6**。
- 结论：低、中档夜里道路完全失去路灯照明，高/极高只亮部分路灯——与"前四档都应有清晰道路照明"直接冲突。

### 7.3 实现（沿用现有管线，未加 Light3D、未改 shader）

1. **路灯优先收集**（`main.gd::_collect_lights`，:2494-2562）：先取 `_world["lamps"]` 六盏灯罩位置生成 `kind="street_lamp"`，永远排最前；再收集 小屋+世界 的其他光源，凡与某路灯灯罩距离² < 0.0025（0.05 m）者去重（避免同一盏灯重复占槽），标注 `lighthouse/dock/other`；其余按能量降序，`merged = 6 路灯 + 其余`，仍 slice(0,12)。
2. **预算保底**（`main.gd::_update_lighting`，:811-847）：`active_lights = max(min(_light_budget,12), lamp_need + boat_extra)`，即无论哪档，6 盏路灯全部进入 `g_light_count`（船灯临时插入时也保留）；随后 `min(lights.size(),12)`。其余环境灯按原有能量顺序补足。
3. **画质预算调整**（`scripts/isle_quality.gd` + main 兜底一致）：`light_budget` 低/中/高/极高/极致 = **7 / 8 / 9 / 11 / 12**（原 4/6/8/10/12）。低档 = 6 路灯 + 1 盏门灯，既保证照地又保持低配开销；高档逐级增加环境灯/光晕细节。
4. **昼夜渐变沿用现有链路**：亮度 = `light_scale = clamp(0.10 + lanternI*1.05, 0, 1.30)`，`lanternI` 来自既有昼夜/橱窗灯渐变（P6 已有）；白天灯参数≈0.10（近乎不亮），黄昏与夜间逐渐增强，无独立灯光时间控制器。
5. 不使用实时阴影、不新增每帧节点/材质实例；12 盏 uniform 数组是既有固定成本，改动只是"谁占槽"。

### 7.4 验收（窗口真实渲染 + 像素证据）

- 同一机位（俯视路灯照地机位）五档夜景截图：`开发产物/p7v2/shots/light/night_q0..q4.png`；近景低/极致 `night_close_q0/q4.png`；黄昏三档 `dusk_q0/q2/q4.png`；白天两档 `day_q0/q4.png`（2560×1440，见 §9）。
- 逐盏隔离像素证据（tester 窗口探针，五档）：对"只开该盏路灯"帧与"全关"帧求灯下区域亮度差——`lamp_box` 平均亮度五档 = 0.2426 / 0.2625 / 0.2549 / 0.2771 / 0.2735，全关 = 0.0263 / 0.0256 / 0.0224 / 0.0264 / 0.0289，**delta = 0.2216 / 0.2464 / 0.2326 / 0.2562 / 0.2456**（均远大于 0.003 阈值）；过曝像素比例 `clipped=0.0000`；低档/极致基础照地亮度比 **q0/q4 = 0.912**（落在 [0.55,1.6] 验收区间内）。
- `probe_p7v2_light.gd` **PASS 88/0**：五档 `debug_light_state()` 前 6 盏均为 `street_lamp` 且坐标与 `world["lamps"]` 一一对应，`budget=active=7/8/9/11/12`，环境灯种类 `[lighthouse, other×3, dock, other]` 未被全部挤掉。
- 目视（Lead 亲自）：低档与极致档均见路灯暖色池状照地，路面可辨识、土路/踏石/草地有层次，衰减连续，无纯白亮盘/无悬浮亮斑；q0 与 q4 基础体验接近；黄昏过渡自然，白天不亮。
- 已知限制：headless 下 `RenderingServer.global_shader_parameter_get()` 不可用（dummy renderer 返回 null），所以 uniform 数值断言改为"窗口逐盏隔离像素证据 + `debug_light_state` 光源清单"两层，避免以参数值冒充画面证据。

---

## 8. 任务 E：自由飞行相机

### 8.1 组件与职责

- 新增 `scripts/isle_flycam.gd`（`class_name IsleFlyCam extends RefCounted`，470 行）：**纯逻辑件，不拥有 Camera3D**，只维护位置/朝向/速度/边界并与 Camera3D 解耦；`main.gd` 仅负责创建、把当前相机变换交给它、每帧 `update()+apply_to()`、退出时恢复。
- 未新增场景节点、未改 Camera3D 层级；不安装任何第三方插件（参考 Community "Free Look Camera" 的输入习惯：鼠标看、WASD 平移、升降键、Shift 加速）。

### 8.2 控制映射（正式 InputMap 动作）

| 输入 | 动作名（project.godot） | 行为 |
|---|---|---|
| W/A/S/D | `fly_forward/left/back/right` | 沿**摄像机水平朝向**（yaw 平面）移动；向下看不会自动向下飞 |
| 鼠标 | 事件 `InputEventMouseMotion` | 调整 yaw/pitch（进入时捕获鼠标） |
| Space | `fly_up` | 独立上升 |
| Shift | `fly_down` | 独立下降（不再与 Ctrl 混用） |
| Ctrl | `fly_boost` | 临时加速 2.0865×，松开立即回落 |
| F | `fly_toggle` | 进入 / 退出自由视角 |
| ESC | 原生键分支 | 飞行中优先退出自由视角；退出后 ESC 才回到既有菜单行为 |

- 空中按 F 退出；飞行中所有输入事件被自由相机优先消费/吞掉：**不会**触发海面点击涟漪、门/烟囱点击、C 自动运镜、Space 暂停、滚轮缩放；HUD 悬停提示（`_update_hover`）在飞行中直接跳过。
- 鼠标捕获/释放规则：`enter()` 置 `Input.MOUSE_MODE_CAPTURED`，`request_exit()` 立即 `MOUSE_MODE_VISIBLE`；退出后不会锁死鼠标。
- 帮助提示：进入时用既有 `HUD.show_toast()` 显示一行 `help_text()`，不遮挡主景观、不新增面板，退出后 HUD 状态自动恢复。

### 8.3 相机模式切换（不与轨道相机争夺同一变换）

- 进入：`_enter_flycam()`（main.gd:1059）从当前相机 global_transform 与 FOV 起步（画面不跳变），取消拖拽/平移状态，轨道相机参数（`_theta/_elev/_radius/_cam_target/_fov/_auto_orbit`）原样冻结；`_update_camera()` 顶部发现 `_flycam.active` 时只执行 `_flycam.update(delta, terrain_height)` + `apply_to(_cam)` 并 return，轨道分支本帧不运行。
- 退出：`_exit_flycam()`（:1072）调用 `request_exit()`，自由相机记录 home 变换（进入瞬间的相机变换）并用 `smoothstep` 在 0.6 s 内平滑过渡回 home；混合结束后 `active=false` 并精确写回 home 变换。之后轨道相机用**之前保存的参数**继续（自动运镜、当前的 theta/elev/radius 都不变），不会跳回初始机位，也不改海鸥/船舶/灯塔/昼夜等任何场景物体世界坐标。
- 菜单安全：`_open_menu()` 若正在飞行先 `request_exit()`，确保不会两套相机同时写变换。
- 画质切换：自由相机只写相机变换与 FOV，不依赖画质档位，五档均可用。

### 8.4 速度换算与地图尺度（实测标定）

- 实测海岸线（`IsleMath.coast_radius` 采样）：平均半径 25.5 m、最大半径约 31.8 m → **最大直径约 63.6 m**；地形网格外缘约 40 m。定义自由视角水平观察范围直径 `D = 2×边界半径`。
- 边界半径 `R = 130 m ≈ 2.0× 小岛直径`（任务书建议 2–3×），故 `D = 260 m`。
- **普通飞行 10.4 m/s = D/25 → 穿越 D 约 25.0 s**（验收 20–30 s 区间）；
  **加速 21.7 m/s = D/12 → 穿越 D 约 11.98 s**（验收 10–15 s 区间）；倍率 **2.0865×**；垂直速度 5.5 m/s。
- 最高高度 `max_y = 130 m ≈ 2.0× 小岛直径`（建议 1.5–2.5×）；最低高度 `max(1.2, 地形高度+0.8)`，不会进入海平面以下或穿地形。
- 速度用指数阻尼 + 解析积分实现：与帧率无关（以 m/s 计），且加减速平滑；单帧 `delta` 上限 0.1 s 防止掉帧跳变。
- 鼠标灵敏度 = 用户设置 `_sensitivity × 0.0022`；pitch 限幅 ±1.45 rad，不会翻转；加速时 FOV +4.5° 并平滑恢复。

### 8.5 边界与恢复

- 水平边界：半径 130 m 圆；越界时把位置投影回圆内并**保留切向速度**（沿边界滑动），不会瞬移回中心；实测探针越界后位置 clamp 至 R、切向继续。
- 垂直边界：`y ∈ [max(1.2, 地形+0.8), 130]`，到顶/到底平稳钳制，可无限微调但不会飞出/沉入。
- 边界内可俯瞰全岛、海岸、灯塔、码头与周边海域（窗口截图确认 126 m 高空全岛+海域完整、边距充足）。
- 退出恢复：探针实测 51 帧（≈0.6 s@85fps）混合后 `active=false`、相机位置与进入前完全一致（`pos=(53.18274,27.66116,58.15555)` 等）、FOV 恢复、轨道参数与 `auto_orbit` 保持原值、退出后自动运镜继续；可重复进入/退出。
- 已知限制：headless 无真实鼠标捕获/释放设备，该项在 headless 探针中标记 SKIP（2 项），由窗口运行与截图/人工检查覆盖；不支持手柄（未在需求内）。

---

## 9. 自动化测试、截图与性能实测

### 9.1 环境与基线

- 引擎：Godot 4.7.2.stable.official（ed1daf0bf），Forward+，Vulkan 1.4.351；GPU：NVIDIA GeForce RTX 2060；窗口测试 1600×900（截图探针窗口自身保存为 2560×1440，见各 MANIFEST 注明）。
- 工程：`D:/休闲小岛幻境/游戏工程`，分支 `p7-v2`（自 `p7-v1` HEAD `99e2fac` 新建）。
- 改前逻辑基线（2026-10-21 08:50，headless，`开发产物/p7v2/logs/baseline_*`）：probe_bird6 45/0、probe_eco7 123/0、probe_smoke6 96/0、probe_quality6 rc0、probe_boat_p5 76/0、probe_p7c 38/0、probe_world_p5 PASS、probe_lighthouse_p5 17/0、probe_frame_t5 5/0、probe_settings6 ALL PASS、`--selftest` 53/53。
- **性能对照基准**：本轮创建分支后的第一次窗口 `--perf`（08:53 启动）已包含 D 改动（main/isle_quality 于 08:52:36 落盘），**不是严格改前值**。§9.5 因此采用两层参考：① 同会话 08:55 `baseline_perf_q2.log`（最接近的近似基线，用于检测方向性退化）；② `docs/P7_V1_REPORT.md` 记录的同机 17 条 `[PERF]` + VRAM（跨会话历史参考）。两者条件差异均在 §9.5 / §10.2 标注，结论只作方向性判断，不作严格回归定论。

### 9.2 headless 全量回归（`开发产物/p7v2/logs/post_*`）

| 探针 | 结果（pass/fail 或状态） | 与改前基线对比 |
|---|---|---|
| `--selftest`（53 项） | **53/53 PASS**（1 项真实鼠标拖动 SKIP） | 一致 |
| probe_audio6 / probe_audio_p5 | 232/0、85/0 | 一致 |
| probe_astro6 / probe_astro_xcheck_t7 | PASS / PASS | 一致 |
| probe_eco7 / probe_boat_p5 / probe_p7c | 123/0、76/0、38/0 | 一致 |
| probe_smoke6 / probe_time_p5 | 96/0、1886/0 | 一致 |
| probe_quality6 / probe_settings6 / probe_water6 | rc0 / ALL PASS / PASS | 一致 |
| probe_bird6 | **47/0**（口径更新为 P7-V2：屋顶区≤2、屋脊同排≤2、多 kind） | 旧口径 45/0；旧断言与新验收冲突已按新设计更新，属**口径变更**非放宽 |
| probe_cottage6 | **31/0**（落点数断言 10→14：+4 门廊扶手） | 口径变更，其余断言不变 |
| probe_frame_t5 | **7/0**（口径更新：分布不变量 + 取景可见性；旧 P6"屋脊≥3"断言删除） | 口径变更，历史日志保留 |
| probe_bird_roof_t5 | 无断言失败（信息性输出） | 一致 |
| 既有 probe_world_p4 | rc=3（2 FAIL）：`missing perch kind: roof/eave` | **P6 过期断言**（P7-V1 报告亦记录该项失败）；本轮不作为回归失败（roof/eave 由 cottage.gd 拥有，符合现架构） |
| probe_fx_p4 / probe_lighthouse_p5 | 65/0、17/0 | 一致 |

结论：除 `probe_world_p4` 的 P6 过期断言（基线同项即失败）外，**headless 回归全绿**；两条因 P7-V2 验收口径变化而更新的旧断言（probe_bird6、probe_frame_t5）已在报告与历史日志中注明。

### 9.3 P7-V2 新增专项探针

| 探针 | 结果 | 覆盖 |
|---|---|---|
| `tools/probe_p7v2_bird.gd` | **pass=681 fail=0** | A/B/C：待机动作类别/错峰/夜间权重、轻跳回槽、屋顶分布上限、烟囱资格、10:59/11:00/13:00/16:59/17:00/19:00 边界、正常入夜/白天跳夜、60×/1440× 倍率、跳时 hold |
| `tools/probe_p7v2_light.gd` | 窗口 **88/0**；headless 逻辑段 **67/0** | 五档 `debug_light_state`、6 盏路灯位置对应、预算保底；窗口逐盏隔离像素证据（headless 无 uniform 像素，走截图/像素层） |
| `tools/probe_p7v2_perch.gd` | **271/0** | 36 点真实几何贴合（脚部间隙 0.03）、扶手/灯帽净空、fx 全部接受、夜间强制停栖稳定、无槽位冲突 |
| `tools/probe_p7v2_flycam.gd` | headless **83/0** + 窗口 **85/0**（headless 另 2 SKIP，鼠标模式由窗口覆盖） | 进入/退出、方向、速度、边界、y 限幅、FOV、轨道参数冻结与恢复、自动运镜、菜单与点击隔离 |
| `tools/probe_p7v2_shots.gd` | 生成 30 张 suite 截图 | 道路昼/昏/夜 × 五档、海鸥待机/夜栖近景、门廊扶手/灯帽栖点、烟囱边界前后、自由视角与回位 |
| `tools/probe_bird_p7v2.gd`（bird-dev） | **108/0** | 动作/调度/分布/边界/跳时 hold 的独立实现级验证 |
| `tools/probe_flycam_p7v2.gd`（flycam-dev） | **219/0** | 自由相机逻辑全量回归（边界、速度、混合、home 快照） |
| Lead 临时整合探针（已删除） | **20/0** | 真实 `isle.tscn` + 真实 `main._update_smoke_clock` 的烟囱正常/跳时路径闭环 |

### 9.4 截图（全部窗口真实渲染）

| 目录 | 数量 | 内容 |
|---|---|---|
| `开发产物/p7v2/shots/suite/`（+MANIFEST.md） | 30 | 道路昼/黄昏/夜 × q0..q4 同机位 15 张；海鸥白天 4 类待机近景 + 夜间休息 2 张；门廊扶手/灯帽栖点 2 张；烟囱 10:58:30 前 / 跳时 11:00 / 11:00:32 后 3 张；自由视角昼/海岸/夜/退出恢复 4 张 |
| `开发产物/p7v2/shots/light/` | 12 | 五档夜景 + 夜景近景低/极致 + 黄昏 3 档 + 白天 2 档（Lead 首轮 D 验收） |
| `开发产物/p7v2/shots/flycam/` | 5 | 126m 高空全岛昼/夜、中空海岸、低空灯塔、退出恢复原轨道机位 |
| `开发产物/shots/` 官方 `--shots` | **61**（RC=0） | 既有官方截图套件（与基线 61 张一致）；04_bird_perch / 06_bird_roof 经 Lead 目视有清晰鸟主体，04_birds 与基线一致（该机位鸟群主体不在取景内，属既有构图，非回归）。06_bird_roof 使用 `_stage_bird_for_shot()` 把 2 只鸟预置到**真实屋脊栖点**（仅截图取景，不改生态规则），呈现 P7-V2 允许的"屋脊 2 只"而非旧的 3 只排队 |
| `开发产物/shots/` 官方 `--transition` | 13（RC=0） | 菜单过渡逐帧截图 |

- 关键画面目视结论（Lead 亲自）：`night_q0/q4` 与 `road_night_q0..q4` 均见 6 盏路灯暖色池状照地，路面/踏石/草地层次清楚、衰减连续、无纯白过曝、q0 与 q4 基础感接近；`perch_porch_rail_group` 4 只鸟站在真实扶手顶面且长轴沿栏杆；`perch_lamp_group` 鸟站在灯帽顶面未进入灯罩/吊杆；`chimney_1102_after` 修复后可见炊烟且烟囱无鸟；`flycam_*` 126m 高空全岛+周边海域完整，退出后恢复原轨道夜景机位。

### 9.5 性能实测（3 次独立窗口 `--perf`，1600×900，RTX 2060）

同会话近似基线 = 08:55 `开发产物/p7v2/logs/baseline_perf_q2.log`（**已含 D 改动**，只用于检测方向性退化）；原始数据与逐次明细见 `开发产物/p7v2/REGRESSION_P7V2.md` §5。

| 机位 | 08:55 同会话近似基线 fps | 本轮 run1 / run2 / run3 fps | 中位 | 相对近似基线判定 |
|---|---|---|---|---|
| noon_clear | 149.2 | 165.6 / 171.8 / 158.7 | 165.6 | 不低 |
| golden_cloud_water | 148.9 | 159.3 / 144.4 / 146.0 | 146.0 | ±10% 噪声 |
| night_shadows | 132.7 | 164.2 / 152.5 / 153.0 | 153.0 | 更快 |
| night_close | 165.6 | 177.5 / 149.5 / 151.1 | 151.1 | ±10% 噪声 |
| far_island | 145.8 | 162.0 / 143.2 / 153.5 | 153.5 | ±10% 噪声 |
| sky_up | 149.7 | 157.2 / 159.0 / 155.7 | 157.2 | 不低 |
| time_panel_open | 140.7 | 143.0 / 155.6 / 156.3 | 155.6 | 不低 |
| lite_noon_nomultimesh | 152.7 | 150.5 / 150.6 / 166.8 | 150.6 | ±10% 噪声 |
| lite_night_nomultimesh | 140.5 | 150.8 / 161.8 / 154.5 | 154.5 | 更快 |
| quality_4（12 灯） | 89.8 | 86.0 / 86.0 / 85.5 | 86.0 | −4%（噪声下限） |
| quality_3（11 灯） | 110.8 | 95.3 / 99.1 / 99.1 | 99.1 | −11%（需同热状态基线定性） |
| quality_2（9 灯） | 153.0 | 148.8 / 149.2 / 160.1 | 149.2 | ±10% 噪声 |
| quality_1（8 灯） | 100.5 | 146.9 / 158.3 / 159.1 | 158.3 | 基线异常低，本次更快 |
| quality_0（7 灯） | 135.3 | 151.0 / 164.0 / 167.8 | 164.0 | 更快 |

- 默认画质（quality 2）中位 149.2 fps / 6.54–6.72 ms；极致画质 86.0 fps / 11.62–11.69 ms，仍高于 60 fps；全部 14 个机位未出现方向性退化。
- VRAM（MB）：q4/q3/q2/q1/q0 = 621.3 / 561.1 / 268.8 / 201.6 / 165.4，与同一基线（621.3 / 561.1 / 268.8 / 201.6 / 165.4）**逐档完全一致**，未因本功能增加显存占用；对象数 1575–2526、draw calls 1246–1764 同量级，`after_6s orphan = 0/10/10`（基线 41）。
- 跨会话历史参考（`docs/P7_V1_REPORT.md`）：q4 111.9、q3 130.7、q2 177.9、q1 181.9、q0 184.5 fps，默认场景 176–200 fps。本会话基线自身抖动很大（例如 q1 基线 100.5 vs 本轮 158.3、q3 基线 110.8 vs 本轮 99.1），因此**不能把与历史值的差异定性为回归**；本功能未增加任何每帧 GPU 工作量（光源数仍为既有 12 盏 uniform 上限的重新分配、shader 未改、无新增节点/材质/阴影），VRAM 逐档一致也支持这一判断。
- 低/中档光源数由旧 4/6 提升到 7/8（多 3/2 盏 toon 点光），实测 q0/q1 中位反而高于近似基线（135.3→164.0、100.5→158.3），未出现"明显性能回退"；q4 的 −4% 与光源数无对应关系。严格结论仍受"无同热状态改前基线"限制，列入 §10.2。

### 9.6 失败项与未覆盖项

1. `probe_world_p4` rc=3（2 FAIL）：P6 过期断言（世界栖点不应包含 roof/eave），P7-V1 基线同项亦失败，**非本轮回归**；未修改栖点归属架构。
2. headless SKIP：`probe_p7v2_flycam` 2 项（鼠标捕获/释放需真实窗口）、`probe_p7v2_light` 的窗口像素段（headless dummy renderer 无 uniform/像素）。窗口探针已覆盖：flycam 窗口 **85/0** 断言 `Input.mouse_mode` 进入 CAPTURED、退出 VISIBLE；light 窗口 **88/0** 逐盏隔离像素。剩余仅"真实鼠标手感/操作舒适度"属人工体验项。
3. 官方截图 `06_bird_roof`（以及 04_bird_perch）为"截图专用摆位"：用 `_stage_bird_for_shot()` 把鸟放到真实栖点再拍，仅证明取景与姿态，不证明自然分布；自然分布由 bird 探针的覆盖统计与 suite 的 forced 栖点近景覆盖。
4. 性能：与 08:55 同会话近似基线相比 q4 −4%、q3 −11%，其余机位在噪声内且 q0/q1 更快；无同热状态改前基线，不能定性为回归（见 9.5，跨会话 P7_V1 历史值差异更大且基线自身抖动达 40%+）。
5. 未做**真实时间流速下连续数分钟~小时**的连续烟囱窗口观察（只在 60×/144×/1440× 下做边界与跳时采样、窗口截图前后对比）；理论上不排除极端跳时/极端帧率下的过渡毛刺，但 hold 机制 + 提前量公式已覆盖已知路径。
6. 海鸥待机动作在"镜头极远"下的细微抖动未单独量化（目视无异常）；声音未改动。

---

## 10. 未完成事项、环境限制、遗留风险与交付分类

### 10.1 已实现且通过验证

1. **任务 A 待机动作**：6 类动作（观察四周/理羽/抖羽/轻跳/调整站姿/休息）在程序化模型上完整实现；逐鸟独立随机调度（白天 2.2–7.5 s、夜间 2.0–6.0 s、首动作前 0.8–2.4 s 静置）；夜间 rest 权重 8 且跳跃/抖羽不进入夜间候选；所有动作 env 包络归零并回到基础停栖姿态；轻跳峰值 0.11 m、回槽误差 ≤1e-4；起飞/降落/状态转换即时取消待机；探测 108/0 + 681/0 + 近景截图。
2. **任务 B 随机栖点与分布**：26→36 个真实落点（+4 门廊扶手、+6 灯帽顶），全部经几何贴合/净空/fx 接受校验；选点改为加权随机（区域权重 + 同区/同落点占用惩罚 + 最小间距偏好）+ 屋顶区≤2 / 屋脊同排≤2 硬上限 + 占用互斥 + 释放复用；移除"index<3 固定屋脊""ridge 白天不起飞"特例；白天 60 s 真实构造路径覆盖全部 7 个区域；探针 271/0 + 681/0 + 扶手/灯帽截图。
3. **任务 C 烟囱禁停**：两个炊烟窗口与 1.5 s 爬升完全不变；`_perch_eligible` 统一判定（窗口内/夜间/提前量）被所有选点路径调用且放宽上限时永不放宽烟囱；提前量 = (1.0 + 0.35 s)×时间倍率，60×/144×/1440× 自适应；停在烟囱的鸟在窗口前经既有起飞状态机离开；时间跳入窗口时 smoke hold 压制粒子直到鸟离场（一段只记 1 次，可查），之后 1.5 s 正常恢复；真实场景整合探针 20/0 + 探针 681/0 + 窗口前后三张截图。
4. **任务 D 五档夜间路灯照地**：根因定位为"按能量排序 + 画质预算截断"使低/中档 0 盏路灯参与着色（旧算法复现：4→0、6→0、8→2、10→4、12→6）；改为 6 盏路灯优先占位 + 预算保底 + 五档 light_budget 7/8/9/11/12；沿用既有 12 盏 toon 点光管线与昼夜渐变，无新增 Light3D/阴影/每帧节点；五档全有暖色照地，逐盏隔离像素 delta 0.2216–0.2562、过曝 0、q0/q4 亮度比 0.912；窗口探针 88/0 + 12 张五档/近景/黄昏/白天截图 + suite 15 张道路五档截图 + 像素统计。
5. **任务 E 自由飞行相机**：正式 InputMap 8 个动作（F/WASD/Space/Shift/Ctrl）；纯逻辑件 IsleFlyCam（470 行）与 main 三点接线；进入不跳画面、退出 0.6 s smoothstep 精确回原机位并恢复原轨道参数/自动运镜；WASD 水平、Space/Shift 独立升降、Ctrl 2.0865× 加速；R=130 m、D=260 m、普通 10.4 m/s（穿 D≈25 s）、加速 21.7 m/s（≈12 s）、最高 130 m、最低地形+0.8/1.2 m；边界切向滑动不瞬移；飞行中吞掉点击/暂停/自动运镜/滚轮并显示单行提示；headless 83/0（2 SKIP）+ 窗口 85/0（mouse CAPTURED/VISIBLE、52 帧回位）+ 逻辑 219/0 + 高空/海岸/夜景/退出恢复截图。
6. **既有功能保护**：`--selftest` 53/53、全部既有探针回归（除 P6 过期 probe_world_p4）、官方 `--shots` 61 张 RC=0（与基线一致）、`--transition` 13 张 RC=0、菜单/自动运镜/点击交互/设置持久化未改语义；shaders 与场景/资源零改动；`isle.tscn` 未改。

### 10.2 已实现但尚未完成验证

1. **性能的严格同条件归因**：见 §9.5。相对 08:55 同会话近似基线，q4 为 −4%（噪声下限）、q3 为 −11%，其余机位在 ±10% 噪声内且 q0/q1 更快；因该基线已含 D 改动且本会话基线自身抖动达 40%+（q1 100.5 vs 158.3、q3 110.8 vs 99.1），**不能定性为回归，也不能排除**。严格结论需在同一会话、同一 GPU 热状态下先回退 `main/isle_quality` 的 D 改动跑改前 `--perf`，再切回对照；本功能未增加每帧 GPU 工作量、VRAM 逐档一致，风险偏低。
2. **长时间连续生态观察**：真实时间流速下跨越 11:00/13:00/17:00/19:00 的连续小时级观察未做（探针在 60×/144×/1440× 加速倍率下覆盖边界、跳时与采样帧）；理论上定时器/浮点累积在超长时间下无已知问题，但未实测。
3. **官方截图摆位与自然分布的区别**：06_bird_roof/04_bird_perch 使用 `_stage_bird_for_shot()` 取景预置，只证明画面主体与姿态；自然分布证明在探针统计中（不是单张截图）。
4. **真实鼠标手感/长时间交互体验**：窗口探针已断言 `Input.mouse_mode` 进入 CAPTURED、退出 VISIBLE 且 52 帧精确回位，但灵敏度/加速曲线/锁定手感属主观体验，未做多设备/高 DPI 验证，也未做长时间连续飞行观察。

### 10.3 未实现或需要进一步处理

1. **同一落点上的"方向随机"未做**：当前每个落点由数据给出唯一已验证安全朝向（屋脊/梁/扶手沿结构、屋檐朝外、灯帽朝路），随机发生在"选哪个落点及其朝向组合"，未实现"同一屋脊点落地后随机朝前/朝后"。原因：增加反向需要逐点验证反向空间/结构安全，且任务明确禁止落地后无约束旋转；若后续需要更强随机感，可为屋脊/门廊梁等双向安全点增加 `facing_alt` 白名单并复用验面/净空校验，属可扩展项，不在本轮范围内。
2. **自由相机手柄/滚轮调速**：需求未要求，未实现。
3. **灯帽栖点净空偏紧（28.5 mm）**：探针与截图验证通过，但属于理论余量较小的落点；若后续鸟模型变大或增加待机动作幅度，需要重新评估或提高侧偏（当前 0.105 < 灯帽半径 0.13）。
4. **probe_world_p4 的 P6 过期断言**：按既有决定未修（P7-V1 同项失败），避免为测试改世界栖点归属。
5. **严格性能 A/B 基线**：缺少同热状态的改前基线；后续发布前建议在同一会话内回退 D 改动先跑 `--perf` 再切回对照（或使用独立 A/B worktree），并在干净 GPU 状态下复测。

### 10.4 环境限制

- headless（`--headless`）使用 dummy renderer：无法读取 `RenderingServer.global_shader_parameter_get`（返回 null），灯光 uniform 数值只能由窗口像素/截图验证；也无法模拟真实鼠标捕获/释放（窗口探针已通过 `Input.mouse_mode` 读取断言 CAPTURED/VISIBLE，设备级手感仍只能人工）。
- 窗口 `--script` 探针保存的截图尺寸为项目窗口尺寸 2560×1440（`--resolution` 不改变已保存的 Window size），已按实际尺寸记录，内容不受影响。
- 音频、真实输入设备手感、长时间稳定性无法在 headless 自动化中覆盖，只能依赖既有回归与人工目视。
- 本轮所有结论以当前代码 + 本轮实测日志为准；未使用历史性能数据替代本轮实测（历史值仅作跨会话参考并明确标注）。

### 10.5 复现命令

```
# 引擎与工程
ENG="D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe"
PROJ="D:/休闲小岛幻境/游戏工程"

# headless 功能探针（示例）
"$ENG" --headless --path "$PROJ" --script res://tools/probe_p7v2_bird.gd
"$ENG" --headless --path "$PROJ" --script res://tools/probe_p7v2_perch.gd
"$ENG" --headless --path "$PROJ" --script res://tools/probe_p7v2_flycam.gd
"$ENG" --headless --path "$PROJ" --script res://tools/probe_p7v2_light.gd
"$ENG" --headless --path "$PROJ" -- --selftest

# 窗口：画质/夜景/截图/性能/转场
"$ENG" --path "$PROJ" --resolution 1600x900 -- --perf
"$ENG" --path "$PROJ" --resolution 1600x900 -- --shots
"$ENG" --path "$PROJ" --resolution 1600x900 -- --transition
"$ENG" --path "$PROJ" --resolution 1600x900 --script res://tools/probe_p7v2_shots.gd
"$ENG" --path "$PROJ" --resolution 1600x900 --script res://tools/probe_p7v2_light_shots.gd
"$ENG" --path "$PROJ" --resolution 1600x900 --script res://tools/probe_p7v2_flycam_shots.gd
```

---

*报告结束。所有日志/截图证据索引见 §9 与 `开发产物/p7v2/REGRESSION_P7V2.md`（测试者汇总台账）；本轮未 commit，改动与新增文件见 §3。*
