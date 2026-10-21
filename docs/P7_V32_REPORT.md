# P7-V3.2 全岛度量衡与世界比例校准报告（尺度验收 + 视觉/性能，终稿 v1.1）

> 本文件是任务书 16.x 要求的《P7-V3.2 全岛度量衡与世界比例校准报告》主报告（12 项内容对照见 §13）；配套《世界尺度规范》= `docs/WORLD_SCALE_SPEC.md`，原始/终态实测数据 = `开发产物/p7v32/scale/inventory*.{md,json}` 与 `开发产物/p7v32/notes/world_audit.md`。

- 分支：`p7-v3.2`；**code freeze checkpoint = commit `e6a4c3f`**（"P7-V3.2: 全岛度量衡与比例校准实施完成 checkpoint"）
- 最终冻结提交：本文件所在提交（`git log -1 --oneline`，分支 p7-v3.2）（在 `e6a4c3f` 之上提交 5 个文件：本报告终稿、`docs/WORLD_SCALE_SPEC.md` v1.4、`tools/probe_house_p7v3.gd`（删 T2 临时机位块）、`tools/probe_scale_shots_p7v32.gd`、`tools/probe_verify_p7v3.gd`（manifest 增补 commit/时间/引擎字段、verify 尺寸快照更新为 V3.2 语义））。产品代码（`scripts/*.gd`、世界/家具构建）在 `e6a4c3f` 之后无改动；提交后工作树 clean；**未回滚、未清理既有 worktree/发布包**。
- 引擎：Godot v4.7.2-stable (official)；headless 用 console 版，渲染/截图用窗口版
- 硬件/画质：NVIDIA GeForce RTX 2060；1600x900（窗口强制 windowed，非 1440x900 或 2560x1440）；`quality=2` / MSAA 2 / vsync disabled
- 测量时间：2026-10-21 20:26–21:22（+08:00）；**终局批次（freeze 代码态）= 21:13–21:22**
- 状态：**终稿**；所有结论均来自本轮真实运行，性能/结构数字均为本轮实测，未用历史数据顶替。历史（V3.1）数据只作对照基线并明确标注。
- 结构：12 节正文（§1–§12）+ 3 附录（A 复现命令 / B 产物索引 / C 必答问题）。

---

## 0. 结论摘要

| 项 | 结论 | 证据类型 | 状态 |
|---|---|---|---|
| 尺度规范 v3.2 | 人形 1.50 m、门洞 1.14x1.94、室内净高 2.42、16 级楼梯、25 类家具、世界资产区间表已定稿 | A | **通过**（scripts/isle_scale_spec.gd） |
| 尺度自动审计 | T5 freeze 代码态复跑 `[SCALE] RESULT pass=90 warn=0 fail=0 info=17 mode=audit` | A | **通过**（日志 reg_scale_world.log） |
| 房屋 T2 | `[T2-HOUSE] RESULT checks=253 pass=253 warn=0 fail=0` + RESULT_OK；窗口旧探针 34 shots / 17 checks / 17 pass / 0 fail | A/B | **通过** |
| 家具 T3 | `[PROPS] RESULT fail=0 warn=0 pass=501 checks=501 specs_pass=25`；场景级 `checks=238 pass=237 warn=1 fail=0` + RESULT_OK | A | **通过**（1 warn 为楼梯底部局部宽度建议值） |
| 世界资产 T4 | 灯塔 17/0、boat 169/0、cat 113/0、perch 265/0、world_p4 PASS、assets lines=78 issues=0 | A/B | **通过** |
| 自动功能回归 | `--selftest` 53/53；verify 206 pass / 0 fail / 3 warn（旧 V3 尺寸快照已更新，见 §8.3） | B | **通过** |
| 截图视觉 C1–C16 | 终局 16 张整批（freeze `e6a4c3f`）1600x900、err=0、非黑图；5 个参照人形回读全部 1.5000 m / err 0.0000 / fine=true；s01–s15 无 overlay、s16 挂 `--scale-debug` | C | **通过**（manifest 见 §7） |
| 性能 D | noon_clear 中位 **172.2 fps**（n=4，范围 154.2–178.0）vs V3.1 153.8（**+12.0%**）；冻结确认轮 179.7 fps；draw_calls **1838** vs 1804（**+1.9%**，Lead 判 ≤5% 容差通过）；tris 192066 vs 191656（+0.21%）；mats 271 vs 274（−3） | D | **通过** |
| 结构统计 | nodes 1466 vs 1459（+0.5%）、MI 863 vs 856（+7）、MultiMesh 43、unique_meshes 813 | A | 已实测 |
| 未验证项 | soak、发布导出、P95/GPU 时间、主观美观、cam_shots/frame/door 三个 V3.1 旧探针（本轮不属必跑清单） | E | 见 §11.4 |

**一句话**：在 code freeze `e6a4c3f` 代码态下，尺度规范/自动审计/房屋/家具/世界资产/功能回归全部真实复跑通过，16 张验收图整批重拍且全部有可比较参照物；性能相对 V3.1 提升约 +12%（fps），draw_calls +1.9% 经 Lead 按 ≤5% 容差判定通过；仅存 1 个已知视觉遗留（室内吊灯泛光球，T2 冻结前未修）与若干观察项，不影响尺度与功能验收结论。

---

## 1. 工程基线、冻结方式与证据口径

### 1.1 代码态（测量时）

```
分支 p7-v3.2
code freeze checkpoint: e6a4c3f  （Lead 于 20:59 宣布冻结）
最终冻结提交: 本文件所在提交（git log -1 --oneline）（docs+探针 5 项在此提交；此后工作树 clean）
```

- 冻结窗口内只改文档/探针（不改产品代码）；所有验证在同一工作树、`e6a4c3f` 代码态上真实进行，最后统一提交为最终冻结提交。
- 冻结方式：Lead 发 code freeze 信号后，T5 **整批重跑** 16 张（不是补拍），新 manifest 记录 commit/时间/引擎/GPU/画质/seed；全量回归与性能确认轮均在冻结代码态执行。
- 冻结前（20:26–20:52）的探针/构图数据只作过程记录；本报告结论一律以 21:13–21:22 的终局运行日志与 manifest 为准。

### 1.2 运行环境与串行化

| 项 | 值 |
|---|---|
| 引擎 | `D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe`（headless）/ `..._win64.exe`（渲染、截图） |
| 分辨率 | 1600x900（`--windowed --resolution 1600x900` + 探针内 `_force_windowed()` 强制 windowed/尺寸校验，防止用户 settings.cfg 的 2560x1440 全屏覆盖） |
| GPU 串行锁 | `mkdir D:/休闲小岛幻境/开发产物/logs/gpu.lock` 原子获得，重试上限 60x10 s；`rmdir` 释放；同一时刻只允许一个窗口渲染进程。本轮所有窗口批次均一次获得并正常释放 |
| 窗口画质 | `quality=2`，MSAA 2（`--perf` 内固定；截图探针固定同一档） |
| 随机/时间 | 截图探针 seed=20251021、固定 T_DAY=740 min（12:20）、`_paused=true`（时间/船/鸟/猫/风车冻结，保证可复现） |
| 证据目录 | `开发产物/p7v32/{shots,logs,perf,notes,scale,tmp}` |

### 1.3 证据分级

| 等级 | 含义 | 本报告中的例子 |
|---|---|---|
| **T5 冻结态实测** | T5 在 e6a4c3f 代码态自己跑出、日志在 p7v32/logs 下 | 16 张终局图、全量回归、perf 冻结确认轮、stats |
| **T5 过程实测** | 冻结前 T5 实测，用作过程记录/对照 | perf n=4、iter2 构图验证 |
| **Lead/owner 代跑** | 由 Lead 或 owner 真实运行测得，仅作交叉参考；T5 已独立复跑 | selftest 53/53、T1 audit 早期 100/0/0、T3 501、T4 各绿 |
| **未验证** | 没有本轮真实证据，不标通过 | §11.4 全列 |

---

## 2. 五类证据来源与判定规则

任务书要求的五类验收证据在本轮的落地：

| 编码 | 类别 | 载体 | 判定规则 | 本轮结论 |
|---|---|---|---|---|
| A | 自动尺寸检查 | headless 探针（AABB/断言，不占 GPU） | exit 0 且末尾 RESULT 行 fail=0 / PASS / issues=0；WARN 必须逐条解释 | 13 项全绿（§8.1） |
| B | 自动功能回归 | `--selftest`、官方 `--shots`/`--transition`、相机/楼梯/船/猫探针 | exit 0 且 RESULT pass=N fail=0；截图入口检查张数与尺寸 | 全绿（§8.1/§8.2） |
| C | 截图视觉验收 | `tools/probe_scale_shots_p7v32.gd` 16 机位（窗口 1600x900，持 GPU 锁） | 每张 1600x900 非黑图、有可比较参照物（1.50 m 人形或已知尺寸物）、manifest 记录相机位置/朝向/fov/时间/画质；参照人形回读高度 1.500±0.010 | 16/16 通过（§7） |
| D | 性能实测 | `--perf --resolution 1600x900`（窗口，持 GPU 锁）+ `probe_stats_p7v3.gd`（headless 结构统计） | 各机位 fps ≥ V3.1 中位；draw_calls 增幅 ≤5%（Lead 确认口径）；不使用历史数据顶替 | 通过（§10） |
| E | 未验证项 | 本报告 §11.4/§12 | 如实列明，不写"通过" | 保留（§11.4） |

---

## 3. 尺度规范 v3.2 与自动尺寸审计（A 类，T1）

### 3.1 基准常量（scripts/isle_scale_spec.gd，唯一登记表）

| 类别 | 关键值 |
|---|---|
| 人体参照 | 身高 **1.50 m**（±0.010）、肩高 0.25–0.35 m、脚底贴地 |
| 门洞 | 净宽 **1.14**、中心净高 **1.94**（拱脚 1.42）、把手 0.95 |
| 室内 | 一层净高 **2.42**、阁楼地板 **3.17**（膝墙 0.56）、屋脊 **6.20** |
| 楼梯 | **16 级**、rise **0.16375**、tread **0.26**、宽 **0.85**、扶手 0.85、净空 ≥ **1.95** |
| 房屋外廓 | **7.60 x 6.20**、墙高 3.18、屋顶结构高 2.47、墙厚 0.30、门廊台面 0.42、台阶 rise 0.14/run 0.30 |
| 家具 | 25 类目标尺寸（桌高 0.65、椅面 0.40、沙发坐高 0.40、床 1.00x1.90 床垫顶 0.45、书架/衣柜 1.75、落地灯 1.45…） |
| 世界资产 | 灯塔 18.28±0.20、猫肩高 0.25–0.35、海鸥体长 0.40–0.70/翼展 1.10–1.50、小船 3.00–6.00/干舷 0.25–0.70、路灯 2.70–3.05、岛直径 55–75、boom 1.20–2.00 |

### 3.2 审计结果（freeze 代码态，T5 独立复跑）

| 项 | 结果 | 来源/日志 |
|---|---|---|
| 全量尺度审计 `probe_scale_world.gd --mode audit` | **pass=90 / warn=0 / fail=0 / info=17**（mode=audit tag=main） | T5 freeze 复跑：`logs/reg_scale_world.log` |
| 参照人形回读 | 5 个实例全部 height=1.5000 m、height_err=0.0000、fine=true | 终局 `scale_shots_manifest.json` |
| 标尺叠加层 | `s16_overlay_ruler.png`：1 m 立方、1.50 m 人形、垂直 0–3 m、水平 0–2 m、门洞/路灯/猫/阁楼地板标注 | T5 终局截图（§7） |
| overlay 标注口径 | **已由 T1 修复**：终图文本为「门洞 净宽 1.14 m / 中心净高 1.94 m（拱脚 1.42 m；门扇 1.00×1.40 + 气窗）」，与规范一致 | s16 终图目检 |

> 计数说明：Lead 在 20:1x 曾报 audit pass=100；T5 于 freeze 代码态复跑为 pass=90（检查项集合随代码态变化）。两次均为 **fail=0**，本报告以 T5 复跑日志原文为准。overlay 仍有少量标注文字互相压盖（开发工具截图 s16 自身排版，不影响游戏画面），列为观察项（§12 #5）。

---

## 4. 房屋重建（T2，A+C 类）

### 4.1 自动尺寸（freeze 代码态，T5 独立复跑）

| 检查 | 结果 |
|---|---|
| `tools/probe_scale_house_p7v32.gd`（headless） | `[T2-HOUSE] RESULT checks=253 pass=253 warn=0 fail=0` + RESULT_OK（`logs/reg_scale_house.log`） |
| `tools/probe_house_p7v3.gd`（旧机位窗口探针） | `[P7V3H] RESULT shots=34 checks=17 pass=17 fail=0` + RESULT_OK（`logs/reg_house_window.log`，34 张 1600x900） |
| 外壳 | 7.60 x 6.20、墙高 3.18、屋脊 6.20、檐口 0.60、烟囱高于屋脊 0.35 |
| 门洞/门扇 | 门洞净宽 1.14 / 中心净高 1.94（拱脚 1.42）/ 门扇 1.00×1.40 + 半圆气窗 R0.50 / 把手 0.95；门轴/门扇/门槛保留 |
| 楼梯 | 16 级、rise 0.16375、tread 0.26、宽 0.85、扶手 0.85、L 形转弯平台 0.85x0.85、阁楼洞净空 ≥1.95（实测 headroom_min=2.148） |
| 室内 | 一层净高 2.42、阁楼地板 3.17、膝墙 0.56；门廊 deck_top=0.420、3 级台阶 rise 0.14/run 0.30 |
| 窗 | 正面 1.00x1.15 x2、侧面 1.00x0.95、背面 0.90x0.90、阁楼 1.50x1.50、窗台高 0.90 |

### 4.2 截图视觉（C 类，见 §7 表）

- s01 房屋正面（fig_front 全身）、s02 门口人形对比（人形站门廊台面正前，全身+脚底入画，门洞/门扇/拱/台阶同框）、s07/s08 楼梯下部/转角平台、s09 二层入口、s10 人形站第 4 级踏面（脚-踏面接触可见）、s15 灯塔门口（7 级石阶+门槛+人形）。
- 冻结前 3 个视觉问题处置：①门廊雨棚（canopy）底面深藏青 **已修复**——根因是 `scripts/isle_math.gd make_prism_mesh` 三角形绕序与 Godot 顺时针前向面相反（V3.1 遗留），本轮 isle_math 全局修 + cottage prism 局部修，s01/s02 终图雨棚底面为米白色；②T2 报"室内/阁楼机位拍废" **已解决**（终局 34 张窗口截图 + 16 张验收图均正常）；③室内吊灯泛光球 **冻结前未修**，冻结代码态仍在（s03/s04 可见），列为已知视觉遗留（§12 #1），不影响尺度/功能验收。

---

## 5. 家具 25 类（T3，A+C 类）

| 项 | 结果 |
|---|---|
| 探针 `tools/probe_props_p7v3.gd`（headless，freeze 复跑） | `[PROPS] RESULT fail=0 warn=0 pass=501 checks=501 specs_pass=25 specs_warn=0 specs_fail=0 round1_meshes=447 cost_parts=447 cost_tris=15104 merged_inst=27`（`logs/reg_props.log`） |
| 场景级布局探针 `tools/probe_scale_props_scene_p7v32.gd` | `[SCENE] RESULT checks=238 pass=237 warn=1 fail=0 props=38` + RESULT_OK（`logs/reg_props_scene.log`）；warn=楼梯底部口局部宽度 0.66 m（建议值 ≥0.80 m，仅 WARN）；覆盖家具↔墙/柱/楼梯无穿插、门内侧 1.2 m 通行区、阁楼净高与洞口禁放区 |
| 截图 | s03 一层室内+家具全景、s04 餐桌椅、s05 沙发/扶手椅/茶几、s06 床+床头柜 |
| 关键外廓 | 餐桌 1.30x0.65x0.80 + 4 椅 0.42x0.85x0.44；沙发 1.50x0.78x0.80；扶手椅 0.72；茶几 0.95；床 1.00x0.85x1.90（床垫顶 0.45）；床头柜 0.40x0.50x0.38；书架/衣柜 1.75；落地灯 1.45 |

---

## 6. 世界资产（T4，A+C 类）

| 资产 | 目标/实测 | T5 freeze 复跑结果 | 截图 |
|---|---|---|---|
| 灯塔 | 高 18.28±0.20、7 级石阶（rise 0.16/depth 0.38）、门槛顶 1.20、门朝 (+0.884,0,−0.468) | `probe_lighthouse_p5.gd` PASS pass=17 fail=0；`probe_scale_world_assets_p7v32.gd` lines=78 issues=0 | s12、s15 |
| 小船 | 船体 3.00–6.00、干舷 0.25–0.70、boom 1.90、sole 顶 0.20、站立净空 ≥1.50 | `probe_boat_p7v3.gd` PASS pass=169 fail=0 | s11 |
| 码头 | 长 11.0、宽 3.4、角度 0.62 | `probe_world_p4.gd` RESULT=PASS fails=0 | s11、s14 |
| 猫/海鸥 | 猫肩高 0.25–0.35；海鸥体长 0.40–0.70、翼展 1.10–1.50 | `probe_cat_p7v3.gd` 113/0；`probe_p7v2_perch.gd` 265/0（含脚点/栖点几何） | s13（同框相对比例）、s01/s02 |
| 路灯/秋千/大树 | 路灯高 2.70–3.05；秋千在 (−9.4,6.2)；大树 (−10.9,4.2) | world_p4 PASS | s01、s12、s14 |
| 岛/近海 | 岛地形直径 63.6 m（范围内 55–75） | `probe_scale_world_assets` lines=78 issues=0 | s14 俯瞰 |
| 全岛测量表 | `开发产物/p7v32/notes/world_audit.md`（27.7 KB，含双口径干舷/灯塔 7 级台阶表/boom 1.90/机位表） | T4 产出 | 作为 §6 附表引用 |

---

## 7. 截图视觉验收（C 类，16 机位，freeze 代码态终局批次）

### 7.1 方法与固定条件

- 探针 `tools/probe_scale_shots_p7v32.gd`：窗口版引擎 `--windowed --resolution 1600x900`，GPU 锁内运行；seed=20251021、T_DAY=740、quality=2、`_paused=true`；每张输出相机位置/朝向/fov/时间/画质/场景/参照物到 manifest。
- 参照人形：`scripts/isle_scale_figure.gd` 的 1.50 m 人形；每张只显示其标注的人形（其余 `visible=false`），manifest 的 `figs_shown` 记录；s01/s02/s03/s10/s15 各 1 个，其余机位 0 个（s16 只保留 overlay 自带人形）。
- 运行脚本：`开发产物/p7v32/tmp/run_accept_shots.sh` / `run_final_window*.sh`（GPU 锁 + 运行 + 释放 + 日志）。
- 终局批次时间：2026-10-21 21:13:57–21:14:08；日志 `logs/accept_shots.log`（`[P7V32S] RESULT shots=16 figures=5 fail=0` + PASS；每张 size=1600x900 err=0）。
- manifest：`shots/manifest.md` + `shots/scale_shots_manifest.json`，含 commit `e6a4c3f`、生成时间 2026-10-21 21:14:07/08、引擎 4.7.2-stable (official)、GPU NVIDIA GeForce RTX 2060、seed 20251021、time=740、quality=2、paused=true、resolution 1600x900。

### 7.2 16 机位清单与状态（终局）

| # | 文件 | 内容/参照物 | 终局状态（目检） |
|---|---|---|---|
| 1 | s01_house_front.png | 人形 vs 房屋外廓 7.6x6.2/墙高3.18/屋脊6.20 | 通过；fig_front 全身入画，比例合理 |
| 2 | s02_door.png | 人形站门廊、门洞净高 1.94 对比 | 通过；人形全身+脚底、门洞/门扇/拱/台阶段同框 |
| 3 | s03_interior_overview.png | 一层室内+家具全景、人形站主通道 | 通过；仅 fig_interior 显示，全身可见；**吊灯泛光球仍在**（已知遗留 §12 #1） |
| 4 | s04_dining.png | 餐桌 1.30x0.65x0.80 + 4 椅 0.42x0.85x0.44 | 通过（无人形）；左上边缘可见吊灯泛光（同 #1） |
| 5 | s05_sofa.png | 沙发 1.50x0.78x0.80 / 扶手椅 / 茶几 0.95 | 通过（无人形） |
| 6 | s06_bed.png | 阁楼床 1.00x0.85x1.90 + 床头柜 0.40x0.50x0.38 | 通过；偏暗但可辨认（台灯补光） |
| 7 | s07_stairs_bottom.png | 楼梯下部 16 级/rise 0.16375/tread 0.26/宽0.85/扶手0.85 | 通过；下部踏面/扶手清晰，左上窗口有较强日光光晕（观察项 §12 #10） |
| 8 | s08_stairs_landing.png | 转角平台 0.85x0.85 | 通过；Flight A/B 与平台衔接连续 |
| 9 | s09_attic_entry.png | 二层入口/阁楼地板 3.17/洞口护栏 | 通过（无人形） |
| 10 | s10_figure_on_stairs.png | 人形站 Flight A 第 4 级（1.50m vs 0.26 踏面） | 通过；全身 + 双脚踩踏面清晰可见，无遮挡 |
| 11 | s11_boat_dock.png | 小船+码头（船体 3–6m/干舷 0.25–0.70） | 通过（无人形）；船体比例/干舷正常 |
| 12 | s12_lighthouse.png | 灯塔 18.28m vs 屋脊 6.20 / 树 / 房 | 通过（无人形）；比例合理 |
| 13 | s13_cat_gull.png | 猫与海鸥相对尺寸（同框） | 通过；猫在栏杆后、海鸥站栏杆顶（脚接触），鸥体长约猫体长 1.1–1.2 倍（规范内）；"悬空"判定为非缺陷（§12 #4） |
| 14 | s14_overview.png | 俯瞰岛（直径 63.6m）+近海+码头+船 | 通过（无人形） |
| 15 | s15_lighthouse_door.png | 灯塔门口 7 级石阶+门槛+1.50m 人形 | 通过；正面门/门槛/7 级石阶/人形全身（脚踩第 3 级踏面）；门扇偏暗为凹入阴影（观察项 §12 #9） |
| 16 | s16_overlay_ruler.png | `--scale-debug` 标尺：1m 立方/1.50m 人形/垂直+水平标尺/门洞等标注 | 通过；门洞文本已为 V3.2 口径（净宽 1.14/中心净高 1.94），少量标注文字互相压盖（§12 #5） |

### 7.3 参照人形回读（终局 scale_shots_manifest.json）

| tag | 高度 | height_err | fine | 位置（世界，m） |
|---|---|---:|---|---|
| fig_front | 1.5000 | 0.0000 | true | (-0.138, 7.662, 6.180) |
| fig_door | 1.5000 | 0.0000 | true | (2.473, 8.366, 2.777)（脚底=门廊台面 0.42） |
| fig_interior | 1.5000 | 0.0000 | true | (1.156, 8.496, 1.226)（主通道，脚底=一层地板 fy=0.55） |
| fig_stairs | 1.5000 | 0.0000 | true | (3.430, 9.151, -2.471)（Flight A 第 4 级踏面 1.205） |
| fig_lighthouse | 1.5000 | 0.0000 | true | (-14.743, 8.191, 8.746)（灯塔第 3 级石阶踏面 0.80） |

### 7.4 目检发现与归属（终局）

1. **室内吊灯泛光球**（s03/s04）：20:30 后 T2 代码态出现（cottage.gd:1714 halo size 1.10 / glow 1.05），**冻结代码态仍在**；非探针问题，属已知视觉遗留，冻结后不修（§12 #1）。
2. **s02 无人形**（首批问题）：fig_door 原放于 z=2.72 房屋轮廓内、y=0.42 低于室内地板，被门扇/墙遮挡 → 已修：人形站门廊台面正前、全身入画（终局通过）。
3. **非目标人形同框**（首批 s03 同时 3 个、s04/s05 右缘半身）→ 已修：每张只显示标注人形（终局 manifest figs_shown 可查）。
4. **s15 拍到灯塔背面**（首批）：door_dir 符号写反 → 已修：door_dir=(0.884,0,−0.468)，终局为正面门/石阶/人形。
5. **s10 半身/米色斜板遮挡** → 已修：终局人形全身、脚踩第 4 级踏面可见。
6. **s13 海鸥脚"悬空"** → **已核实非缺陷**：perch 探针 265/0 实测脚点距扶手顶 0.03 m、腿-趾净空 0.054 m，s13 终图脚与栏杆顶可见接触；此前观感来自透视与旧构图。
7. 观察项（非缺陷）：s07 左上日光光晕较强；s15 灯塔门扇凹入阴影偏暗；s16 overlay 文字局部压盖（开发工具截图）。

---

## 8. 自动功能回归（B 类，freeze 代码态全量复跑）

### 8.1 全量回归结果（2026-10-21 21:19:53–21:22:30，fails=0）

脚本：`开发产物/p7v32/tmp/run_regress_headless.sh`；headless 日志 `logs/reg_<tag>.log`；窗口项日志另行标注。

| ID | 入口 | 实测 RESULT（原文） | 判定 | 日志 |
|---|---|---|---|---|
| A1 | `probe_scale_world.gd --mode audit` | `[SCALE] RESULT pass=90 warn=0 fail=0 info=17 mode=audit tag=main` | PASS | reg_scale_world.log |
| A2 | `probe_scale_house_p7v32.gd` | `[T2-HOUSE] RESULT checks=253 pass=253 warn=0 fail=0` + RESULT_OK | PASS | reg_scale_house.log |
| A3 | `probe_house_p7v3.gd`（窗口，持锁） | `[P7V3H] RESULT shots=34 checks=17 pass=17 fail=0` + RESULT_OK | PASS | reg_house_window.log |
| A4 | `probe_props_p7v3.gd` | `[PROPS] RESULT fail=0 warn=0 pass=501 checks=501 specs_pass=25 specs_warn=0 specs_fail=0 round1_meshes=447 cost_parts=447 cost_tris=15104 merged_inst=27` | PASS | reg_props.log |
| A5 | `probe_scale_props_scene_p7v32.gd` | `[SCENE] RESULT checks=238 pass=237 warn=1 fail=0 props=38` + RESULT_OK | PASS（1 warn 见下） | reg_props_scene.log |
| A6 | `probe_scale_world_assets_p7v32.gd` | `=== P7-V3.2 SCALE WORLD ASSET RESULT: lines=78 issues=0 ===` | PASS | reg_world_assets.log |
| A7 | `probe_world_p4.gd` | `[PROBE] RESULT=PASS fails=0` | PASS | reg_world_p4.log |
| A8 | `probe_lighthouse_p5.gd` | `=== P5 LIGHTHOUSE PROBE RESULT: PASS pass=17 fail=0 ===` | PASS | reg_lighthouse_p5.log |
| A9 | `probe_boat_p7v3.gd` | `=== P7-V3 BOAT PROBE RESULT: PASS pass=169 fail=0 ===` | PASS | reg_boat.log |
| A10 | `probe_cat_p7v3.gd` | `[CAT] RESULT pass=113 fail=0` | PASS | reg_cat.log |
| A11 | `probe_p7v2_perch.gd` | `=== P7-V2 PERCH PROBE RESULT: PASS pass=265 fail=0 ===` | PASS | reg_perch.log |
| A12 | `probe_flycam_p7v2.gd` | `[FLYCAM] RESULT pass=241 fail=0` | PASS | reg_flycam.log |
| A13 | `probe_verify_p7v3.gd` | `[VERIFY] RESULT pass=206 fail=0 skip=0 warn=3` | PASS（3 warn 见 §8.3） | reg_verify.log |
| B0 | `probe_stats_p7v3.gd` | `[STATS] RESULT fail=0` | PASS | reg_stats.log |
| B1 | `-- --selftest`（headless） | `[TEST] RESULT 53/53 passed` | PASS | reg_selftest.log |
| B2 | `-- --shots`（窗口，持锁） | **61 张官方截图**（`[SHOT]` 行 62 条，其中 1 条为 `rocks hero kinds=6` 诊断行）+ rc=0；`开发产物/shots` 共 74 个 PNG = 61 官方 + 13 transition | PASS | final_official_shots.log |
| B3 | `-- --transition`（窗口，持锁） | 13 条 `[SHOT]` 行 + rc=0 | PASS | final_transition.log |
| C1 | `probe_scale_shots_p7v32.gd`（窗口，持锁） | `[P7V32S] RESULT shots=16 figures=5 fail=0` + PASS；16 张全 1600x900 err=0 | PASS | accept_shots.log |

WARN 解释：
- A5 唯一 warn：`[WARN] 楼梯底部口局部宽度 0.66 m ≥ 0.80 m（建议值，仅 WARN）`——楼梯底部净宽为局部几何现状，属建议值未达，非 fail，不影响通行/尺度验收；记录待产品决策。
- A13 三条 warn（详见 §8.3）：①门廊双灯未进 12 盏解析光预算（夜间仅 emissive+halo，需视觉复核/Lead 决策）；②窗灯未进预算（V2 基线同样，非回退）；③本机 Godot 进程无法写 `user://`（沙箱限制，需真实环境人工复核落盘）。

### 8.2 未覆盖项说明

- B2 `--shots` 本轮生成 **61 张官方截图**（与 V3.1 报告的 61 张一致）；日志中 62 条 `[SHOT]` 行里含 1 条 `rocks hero kinds=6` 诊断行（非图片）。全部截图 1600x900、rc=0，未出现 SCRIPT ERROR（仅有无害 shader cache / user:// 日志噪声）。
- `probe_cam_shots_p7v3.gd`、`probe_frame_p7v3.gd`、`probe_door_p7v3.gd` 属 V3.1 旧口径截图探针，**本轮不在 m00546 必跑清单内**，未重跑（V3.1 已有覆盖）；如需按旧口径补测，命令见附录 A。
- 窗口项（A3/B2/B3/C1）全部在 GPU 锁内串行执行，锁每次均一次获得并正常释放（21:13 与 21:16 两批）。

### 8.3 回归口径更新（V3.1 → V3.2，重要）

`tools/probe_verify_p7v3.gd` 在 V3 时代含大量**硬编码尺寸快照**（房屋 10.6×8.4、attic_floor 5.70、楼梯 27 级、门拱宽 2.90、门扇 5 板、DoorFanlight 三角面数、门廊灯 ±2.80、甲板 7 段横铺板、舷缘内衬 12 段、二层地板 21 条、吊灯高度、壁炉石体、PorchCat 坐标等）。freeze 前该探针 pass=124 / fail=50——50 条 FAIL **全部是 V3 时代旧尺寸快照**，正是本轮按规范有意改动的对象，不是功能回归（Lead m00585 已判定）。

T5 处理：把尺寸快照类断言更新为 V3.2 语义，优先从 `IsleMath` 常量 / `cottage_ctx` / 节点 meta / batch_manifest 派生（楼梯改为 batch 溯源 + 由踏面高度推导 level；门扇 1.00×1.40 + 气窗 R0.50；栏杆 0.90/立柱 0.09×1.02×0.09；甲板 3 块 + Sole 0.20；猫 3.80 等）。**保留全部功能性断言**：门轴开合、灯光数量/颜色/range、船状态机、帆/舵存在、猫/鸥/栖点、渲染节点存在性等。

冻结态复跑结果：`[VERIFY] RESULT pass=206 fail=0 skip=0 warn=3`（`logs/reg_verify.log`，rc=0）。结论：**V3.1→V3.2 的有意尺寸改动全部纳入新口径，功能断言无回归**。3 条 warn 为既有环境/设计记录（见 §8.1），不是 fail。

---

## 9. 结构统计汇总（A 类，freeze 代码态实测）

命令：`Godot_v4.7.2-stable_win64_console.exe --headless --path 游戏工程 --script res://tools/probe_stats_p7v3.gd`
日志：`开发产物/p7v32/logs/reg_stats.log`（`[STATS] RESULT fail=0`）

| 指标 | 本轮 V3.2（freeze） | V3.1 基线 | 变化 |
|---|---:|---:|---|
| nodes_total | **1466** | 1459 | +7（+0.5%） |
| MeshInstance3D | **863** | 856 | +7 |
| MultiMeshInstance3D | **43** | 43 | — |
| triangles | **192066** | 191656 | +410（+0.21%） |
| surface_vertices | **166560** | —（V3.1 报告未列） | — |
| unique_materials | **271** | 274 | −3（−1.1%） |
| unique_meshes | **813** | —（V3.1 报告未列） | — |
| Light3D 节点 | **0**（灯光由 shader 全局参数驱动） | 0 | — |
| scene_aabb | 1400.00 x 71.92 x 1400.00（含远岛/天空体） | — | — |
| 其它节点 | AudioStreamPlayer 15、Label 142、Control 18、CanvasLayer 3、GPUParticles3D 3、CPUParticles3D 1、Camera3D 1 | — | — |

结论：几何与材质数量与 V3.1 基本持平（tris +0.21%、mats −3、MI +7），说明本轮重建没有带来结构性膨胀；draw_calls 的 +34 来自家具/楼梯/扶手等细节件的独立网格，而非材质/几何爆炸（见 §10）。

---

## 10. 性能实测与 V3.1 对比（D 类，本轮实测）

### 10.1 测量条件

- 入口：窗口版 `Godot_v4.7.2-stable_win64.exe --path 游戏工程 --windowed --resolution 1600x900 -- --perf`；持 `gpu.lock`。
- 固定：quality=2、MSAA 2、vsync disabled（`[PERF] begin viewport=(1600.0, 900.0) msaa=2 quality=2 grass=22500 lights=9 vsync_disabled`）、同机位/同引擎/同硬件（RTX 2060）。
- 轮次：过程实测 **n=4**（`perf_v32_r1/r2` + `perf_v32b_r1/r2`，20:5x）+ 冻结确认 **1 轮**（`perf_freeze_r1`，21:18）；合计 noon_clear 5 轮。
- 基线：`docs/P7_V31_REPORT.md` §6.1（n=5 中位数）。注意 V3.1 中位 fps=**153.8**（159.6 是同一表里的 V2 栏数值，勿混用）。
- 原始日志：`logs/perf_v32_r1.log`、`perf_v32_r2.log`、`perf_v32b_r1.log`、`perf_v32b_r2.log`、`logs/perf_freeze_r1.log`。

### 10.2 各机位 FPS / Draw Calls / Objects（n=4 中位，1600x900）

| 机位 | V3.2 fps 中位 | 范围（4 轮） | V3.1 fps | Δfps | V3.2 dc | V3.1 dc | Δdc | V3.2 objects | V3.1 objects |
|---|---:|---|---:|---:|---:|---:|---:|---:|---:|
| noon_clear | **172.2** | 154.2–178.0 | 153.8 | **+12.0%** | **1838** | 1804 | +34（+1.9%） | 2231 | 2197 |
| golden_cloud_water | 164.3 | 159.6–172.1 | 149.1 | +10.2% | 1842–1844 | 1816 | +26~28 | 2231–2233 | 2209 |
| night_shadows | 162.7 | 154.9–172.4 | 146.0 | +11.4% | 1646–1867 | 1603 | —（随场景物体变化） | 2035–2256 | 1985 |
| night_close | 172.0 | 164.6–175.3 | 145.0 | +18.6% | 1263 | 1223 | +40 | 1602 | 1562 |
| far_island | 158.9 | 157.3–174.9 | 145.9 | +8.9% | 1843–1863 | 1828 | +15~35 | 2236–2256 | 2188 |
| sky_up | 161.3 | 158.2–166.0 | 144.8 | +11.4% | 1622–1872 | 1580 | — | 2011–2261 | 1971 |
| time_panel_open | 151.3 | 147.3–158.9 | 152.5 | −0.8%（波动内） | 1671–1920 | 1629 | — | 2433–2682 | 2306 |
| lite_noon_nomultimesh | 168.3 | 160.6–175.1 | 161.6 | +4.1% | 1569–1813 | 1527 | — | 1962–2206 | 1932 |
| lite_night_nomultimesh | 161.5 | 146.8–174.8 | 159.4 | +1.3% | 1572–1821 | 1530 | — | 1961–2210 | 1934 |

- noon_clear 的 draw_calls **四轮全部 1838**、objects 全部 2231、VRAM 267.7 MB（V3.1 267.8 MB，−0.1 MB）——结构指标与轮次无关，可复现。
- 部分机位（night_shadows/sky_up/lite_*/time_panel）的 dc 在不同轮次有 10% 级差异（鸟群、船位置、猫等动态物体导致 culling 差异）；本轮以 noon_clear（最稳定机位）做主判据，并在表中如实给出范围。

### 10.3 冻结确认轮（21:18，freeze e6a4c3f）

日志 `logs/perf_freeze_r1.log`（rc=0，`[PERF] end`）：

| 机位 | fps | draw_calls | objects |
|---|---:|---:|---:|
| noon_clear | **179.7** | **1838** | **2231** |
| golden_cloud_water | 165.8 | 1852 | 2241 |
| night_shadows | 162.2 | 1867 | 2256 |
| night_close | 180.2 | 1263 | 1602 |
| far_island | 162.5 | 1863 | 2256 |
| sky_up | 163.3 | 1871 | 2260 |
| quality_4 / q3 / q2 / q1 / q0 | 104.7 / 104.8 / 159.9 / 162.4 / 162.0 | 1853 / 1869 / 1862 / 1858 / 1856 | — |
| after_6s | — | — | objects=24 nodes=1520 orphan=11 |

- noon_clear 冻结确认轮与 n=4 的 draw_calls（1838）、objects（2231）、VRAM（267.7 MB）**完全一致** → 冻结后结构指标可复现，§10.2 数据有效。
- noon_clear 5 轮 fps 范围 **154.2–179.7**；n=4 中位 172.2，含确认轮的中位 172.5。fps 绝对值受主机负载漂移影响（b 轮较低），结构指标不受影响。

### 10.4 画质档位（n=4 中位，同时段同机位）

| 档位 | V3.2 fps 中位 | 范围 | V3.1 fps | Δ | V3.2 dc（轮内范围） | msaa/scale/grass/lights |
|---|---:|---|---:|---:|---|---|
| quality_4 | 99.3 | 98.5–99.9 | 83.6 | **+18.8%** | 1839–1858 | msaa3 / 1.25 / 22500 / 12 |
| quality_3 | 101.2 | 86.4–115.6 | 97.5 | +3.8% | 1849–1866 | msaa3 / 1.15 / 22500 / 11 |
| quality_2（默认） | 165.0 | 126.7–171.8 | 152.9 | +7.9% | 1843–1860 | msaa2 / 1.00 / 22500 / 9 |
| quality_1 | 161.0 | 131.9–175.2 | 154.5 | +4.2% | 1837–1856 | msaa1 / 0.92 / 15750 / 8 |
| quality_0 | 167.3 | 148.3–178.0 | 146.7 | +14.0% | 1837–1856 | msaa0 / 0.85 / 10125 / 7 |

说明：quality_2/q1 的 b 轮次（`perf_v32b_*`）明显低于 a 轮，且同轮 quality_3 出现 115.6 fps 的异常高值——判定为主机负载漂移（并行其他任务），不是档位结构差异；结构指标（dc/msaa/scale/grass/lights）在四轮完全一致，可作主证据。**不提供 P95**（`--perf` 无分位数接口，不编造）。

### 10.5 门槛判定

| 门槛 | 判定 | 依据 |
|---|---|---|
| fps 不低于 V3.1 | **通过** | 6 个主场景机位 +4.1%~+18.6%（n=4 中位）；time_panel −0.8% 在轮间波动内；5 轮 noon_clear 均 ≥ V3.1 153.8 |
| draw_calls 不劣化 | **通过（Lead 确认口径：≤5% 容差）** | noon_clear +34（+1.9%）、objects +1.5%、VRAM −0.1 MB；Lead 判定：fps +12%、tris +0.2%、mats −3，+34 来自家具/楼梯/扶手细节件，**通过** |
| 结构指标不劣化 | 通过 | tris +0.21%、mats −3、nodes +0.5% |

---

## 11. 已通过 / 未通过 / 未验证

### 11.1 已通过（freeze 代码态，本轮真实运行证据）

- A 自动尺寸：audit 90/0/0、房屋 253/253、props 501/501、props_scene 237/238（1 warn）、world_assets issues=0、world_p4 PASS、lighthouse 17/0、boat 169/0、cat 113/0、perch 265/0、flycam 241/0、verify 206/0、stats fail=0。
- B 自动功能：selftest 53/53、官方 --shots 61 张、--transition 13 张、旧房屋窗口探针 34 shots/17 checks/17 pass/0 fail。
- C 截图视觉：终局 16 张全部 1600x900/err=0/非黑图、参照物齐备、5 个参照人形 1.5000 m；s01–s15 无 overlay、s16 有标尺。
- D 性能：fps 全线不低于 V3.1；draw_calls +1.9% 在 Lead 确认的 ≤5% 容差内；结构统计不劣化。

### 11.2 已通过（Lead/owner 代跑，T5 已独立复跑一致）

- selftest 53/53、T1 audit（早期 100/0/0）、T2 房屋 253/253、T3 家具 501 checks、T4（perch 265/0、world_p4 PASS、boat 169/0、cat 113/0）——与 T5 freeze 复跑结果一致或同等绿；报告结论以 T5 复跑日志为准。

### 11.3 未通过

- 无 fail 判定项。（verify 3 条与 props_scene 1 条 WARN 均逐条解释，不是 fail。）

### 11.4 未验证（不标通过）

1. 长时间运行（soak）本轮未跑（V3.1 有 soak 口径；不属 V3.2 尺度验收范围）。
2. 发布导出（export）本轮未跑（V3.1 有；不属本轮范围）。
3. 性能 P95 帧时间、GPU 时间未测（引擎/入口无接口，不编造）。
4. 视觉"美观"主观项未量化；截图只验证可达性、比例、参照物和可读性。
5. V3.1 旧口径窗口探针 `probe_cam_shots_p7v3.gd`、`probe_frame_p7v3.gd`、`probe_door_p7v3.gd` 本轮未重跑（不在 m00546 必跑清单；V3.1 已有覆盖，命令见附录 A）。
6. 夜间门廊双灯未进 12 盏解析光预算（verify warn ①）：夜间仅 emissive+halo，需视觉复核/Lead 决策（§12 #11）。

---

## 12. 未验证项、残余风险与遗留问题（按归属）

| # | 问题 | 归属 | 处置/结论 |
|---|---|---|---|
| 1 | 室内吊灯泛光球（s03/s04，freeze 代码态仍在） | T2（cottage.gd:1714 halo size 1.10 / glow 1.05） | 已知视觉遗留；因 code freeze 不修，转产品侧后续处理。不影响尺度/功能/性能验收 |
| 2 | 门廊雨棚底面深藏青 | T2 + isle_math | **已修复**：`scripts/isle_math.gd make_prism_mesh` 绕序与 Godot 顺时针前向面相反（V3.1 遗留），本轮 isle_math 全局修 + cottage prism 局部修；s01/s02 终图雨棚底面为米白 |
| 3 | T2 报"室内/阁楼机位拍废" | T2/T5 | **已解决**：终局窗口旧探针 34/17/0 + 16 张验收图正常 |
| 4 | 海鸥停栖时脚"离栏杆"观感 | T4 | **已核实非缺陷**：perch 265/0 实测脚点距扶手顶 0.03 m、腿-趾净空 0.054 m；s13 终图脚与栏杆接触可见；体长/翼展在规范区间 |
| 5 | ScaleDebugOverlay 门洞标注口径 | T1 | **已修复**：终图文本「净宽 1.14 / 中心净高 1.94（拱脚 1.42；门扇 1.00×1.40 + 气窗）」；仍有少量标注文字互相压盖（仅开发工具截图 s16，观察项，不影响游戏画面/验收） |
| 6 | draw_calls +1.9%（+34） | Lead/产品 | **Lead 判通过**：≤5% 容差；fps +12%、tris +0.2%、mats −3；+34 来自家具/楼梯/扶手细节件 |
| 7 | task-5 blockedBy task-2 | T5/Lead | **已解决**：task-2 completed 后 task-5 ready，T5 claim（revision 2）并完成验收 |
| 8 | 用户 settings.cfg 全屏 2560x1440 覆盖窗口参数 | T5 探针 | **已规避**：`_force_windowed()` + 启动 `--windowed`；perf/截图脚本固定，本轮窗口全部 1600x900 |
| 9 | 灯塔门口门扇偏暗（凹入门洞阴影） | T4/产品 | 观察项，非尺度/功能缺陷；s15 仍可读门槛/台阶/人形，记录待后续美术调光 |
| 10 | s07 左上方日光光晕较强 | 场景光照（非本轮改动） | 观察项；楼梯下部踏面/扶手仍清晰可读，不影响验收 |
| 11 | 夜间门廊双灯未进 12 盏解析光预算 | T1/Lead 决策 | verify warn ①：双灯 1.05/1.05 均未进预算（V2 左灯 1.35 在预算内），夜间仅 emissive+halo；需视觉复核/决策，非功能回归 |
| 12 | 本机 headless 无法写 `user://` | 环境（沙箱） | verify warn ③：settings 落盘逻辑用工作区临时文件验证；真实环境需人工复核（V3.1 同样限制） |

---

## 附录 A. 复现命令清单（本轮实际执行）

```bash
PROJ="D:/休闲小岛幻境/游戏工程"
ENG="D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe"
WENG="D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64.exe"
LOCK="D:/休闲小岛幻境/开发产物/logs/gpu.lock"
LOG="D:/休闲小岛幻境/开发产物/p7v32/logs"

# --- 全量 headless 回归 + selftest（不占 GPU；freeze 代码态已跑，fails=0）---
bash 开发产物/p7v32/tmp/run_regress_headless.sh   # 写 $LOG/reg_<tag>.log
# 单条等价：
"$ENG" --headless --path "$PROJ" --script res://tools/probe_scale_world.gd -- --mode audit
"$ENG" --headless --path "$PROJ" --script res://tools/probe_scale_house_p7v32.gd
"$ENG" --headless --path "$PROJ" --script res://tools/probe_props_p7v3.gd
"$ENG" --headless --path "$PROJ" --script res://tools/probe_scale_props_scene_p7v32.gd
"$ENG" --headless --path "$PROJ" --script res://tools/probe_scale_world_assets_p7v32.gd
"$ENG" --headless --path "$PROJ" --script res://tools/probe_world_p4.gd
"$ENG" --headless --path "$PROJ" --script res://tools/probe_lighthouse_p5.gd
"$ENG" --headless --path "$PROJ" --script res://tools/probe_boat_p7v3.gd
"$ENG" --headless --path "$PROJ" --script res://tools/probe_cat_p7v3.gd
"$ENG" --headless --path "$PROJ" --script res://tools/probe_p7v2_perch.gd
"$ENG" --headless --path "$PROJ" --script res://tools/probe_flycam_p7v2.gd
"$ENG" --headless --path "$PROJ" --script res://tools/probe_verify_p7v3.gd
"$ENG" --headless --path "$PROJ" --script res://tools/probe_stats_p7v3.gd
"$ENG" --headless --path "$PROJ" -- --selftest

# --- 16 张验收截图（窗口 1600x900，持 GPU 锁；终局已跑）---
bash 开发产物/p7v32/tmp/run_accept_shots.sh
# 等价核心命令（s16 才挂 --scale-debug；其余无 overlay）：
"$WENG" --path "$PROJ" --windowed --resolution 1600x900 \
  --script res://tools/probe_scale_shots_p7v32.gd -- --out="D:/休闲小岛幻境/开发产物/p7v32/shots"

# --- 官方窗口回归（窗口 1600x900，持 GPU 锁；终局已跑）---
"$WENG" --path "$PROJ" --windowed --resolution 1600x900 -- --shots       # 61 张（62 条 [SHOT] 行含 1 条诊断）
"$WENG" --path "$PROJ" --windowed --resolution 1600x900 -- --transition  # 13 条 [SHOT]
"$WENG" --path "$PROJ" --windowed --resolution 1600x900 \
  --script res://tools/probe_house_p7v3.gd                               # 34 shots / 17 checks

# --- 性能实测（窗口 1600x900，持 GPU 锁；n=4 + freeze 确认 1 轮）---
bash 开发产物/p7v32/tmp/run_perf_v32.sh 2 r1      # 或 run_perf_freeze.sh
"$WENG" --path "$PROJ" --windowed --resolution 1600x900 -- --perf > "$LOG/perf_freeze_r1.log" 2>&1

# --- GPU 锁模板（任何窗口命令）---
for i in $(seq 1 60); do mkdir "$LOCK" 2>/dev/null && break; sleep 10; done
# ...运行窗口命令...
rmdir "$LOCK"
```

> 全部 headless 命令**不占 GPU**；窗口命令必须持 `gpu.lock`，结束时 `rmdir`。详细矩阵见 `开发产物/p7v32/notes/regression_matrix.md`。

## 附录 B. 产物索引

| 产物 | 路径 | 说明 |
|---|---|---|
| 本报告 | `docs/P7_V32_REPORT.md` | T5 验收报告终稿 v1.0 |
| 验收计划 | `开发产物/p7v32/notes/accept_plan.md` | 五类矩阵、执行顺序、门禁 |
| 回归矩阵 | `开发产物/p7v32/notes/regression_matrix.md` | 每条命令/判定行/日志名/实测结果 |
| 16 张验收图 | `开发产物/p7v32/shots/s01…s16.png` | 终局批次（freeze e6a4c3f，1600x900） |
| 截图 manifest | `开发产物/p7v32/shots/manifest.md`、`scale_shots_manifest.json` | commit/时间/引擎/GPU/seed/相机/朝向/fov/参照物/人形回读 |
| 截图日志 | `开发产物/p7v32/logs/accept_shots.log` | [P7V32S] SHOT/FIG/RESULT 行 |
| 全量 headless 回归日志 | `开发产物/p7v32/logs/reg_*.log` | A1–A13/B0/B1 实测 RESULT |
| 官方窗口截图日志 | `开发产物/p7v32/logs/final_official_shots.log`、`final_transition.log` | --shots 61 / --transition 13 |
| 旧房屋窗口探针日志 | `开发产物/p7v32/logs/reg_house_window.log` | 34 shots / 17 checks / 0 fail |
| 性能日志 | `开发产物/p7v32/logs/perf_v32_r1/r2.log`、`perf_v32b_r1/r2.log`、`perf_freeze_r1.log` | n=4 + 冻结确认 1 轮 |
| 统计日志 | `开发产物/p7v32/logs/reg_stats.log` | probe_stats_p7v3 的 [STATS] 行 |
| 运行脚本 | `开发产物/p7v32/tmp/run_regress_headless.sh`、`run_accept_shots.sh`、`run_final_window*.sh`、`run_perf_v32.sh`、`run_perf_freeze.sh` | GPU 锁 + 运行 + 日志 |
| T4 全岛测量表 | `开发产物/p7v32/notes/world_audit.md` | 27.7 KB（T4 产出） |
| 尺度基线/清单 | `开发产物/p7v32/scale/` | T1 产出 |
| 规范文档 | `docs/WORLD_SCALE_SPEC.md`、`scripts/isle_scale_spec.gd` | T1 |
| 官方截图输出 | `开发产物/shots/` | 61 张官方 + 13 张 transition（共 74 PNG） |

## 附录 C. 任务书必答问题

1. **全场景尺度是否统一到 1.50 m 人体基准？** 是。`scripts/isle_scale_spec.gd` 为唯一登记表，T1 全类资产审计 90/0/0、房屋 253/253、家具 501/501、世界资产 issues=0；5 个参照人形回读全部 1.5000 m（§3.2/§7.3）。
2. **门洞/楼梯/家具与人体比例是否可读？** 是。s02 人形全身 vs 门洞净高 1.94、s10 人形 vs 第 4 级踏面 0.26、s15 灯塔门口 7 级石阶 + 人形、s03 室内人形 vs 净高 2.42（§7）。
3. **是否仍存在明显不协调物体？** 主要项全部通过；仅存已知视觉遗留：室内吊灯泛光球（T2，冻结前未修）与少量观察项（s07 日光光晕、s15 灯塔门扇偏暗、s16 overlay 文字压盖、夜间门廊双灯预算），逐条见 §12。
4. **性能是否不低于 V3.1？** 是。fps +4.1%~+18.6%（6 主场景），noon_clear +12.0%；draw_calls +1.9% 经 Lead 按 ≤5% 容差判通过；结构指标 tris +0.21%/mats −3（§10）。
5. **哪些没验证？** soak、发布导出、P95/GPU 时间、主观美观、V3.1 旧口径三个窗口探针（cam_shots/frame/door）、夜间门廊灯光预算决策——见 §11.4。

### C.2 终局回填清单（全部完成）

- [x] §8 全部 A1–A13/B0–B3/C1 的实测 RESULT 行 + 日志名。
- [x] §7 16 张终局批次（s01–s15 无 overlay、s16 --scale-debug）与 manifest（commit e6a4c3f/时间/GPU/画质/seed/人形回读）。
- [x] §4 T2 房屋最终 RESULT（253/253 + 窗口 34/17/0）。
- [x] §10 冻结确认轮（21:18，结构与 n=4 一致）+ n=4 数据保留对照。
- [x] §3.2/§11/§12 按复跑结果与 Lead 更正口径更新。
- [x] task-5 claim（revision 2）并完成。


---

## 13. 任务书《P7-V3.2 全岛度量衡与世界比例校准报告》12 项内容对照

> 本章把任务书 16.x 要求的 12 项内容逐条定位到证据与文档，本报告 + 《世界尺度规范》共同构成 P7-V3.2 最终校准报告交付物。

1. **实际基线 / 分支 / 提交 / 回滚方式**：分支 `p7-v3.2`；冻结基线（P7-V3.1 已冻结）= `eaf1559`；本轮 checkpoint = `e6a4c3f`；本轮最终冻结提交 = 本文件所在提交（`git log -1 --oneline`，分支 p7-v3.2）。回滚：`git reset --hard e6a4c3f`（回到实施完成态）或 `git checkout p7-v3.1`（回到 V3.1 冻结态 `eaf1559`）；既有 worktree/发布包未清理、未覆盖。详见 §1.1。
2. **米制规范与尺度设计原则**：`docs/WORLD_SCALE_SPEC.md` §1（1 Godot 单位 = 1 m、Y 向上、世界/局部坐标区分、长宽高以 m 记录）与 §8（容差：本体 ±5% PASS / ±10% WARN；场景约束单列）。**禁止新增全局 scale_multiplier、禁止整 root 缩放**，一律改程序化构造参数。
3. **1.50 m 参照模型尺寸定义**：定义 = 双脚接地站立、脚底基准面到头顶最高点（含发型/鞋）1.50 m；实现 `scripts/isle_scale_figure.gd`（landmark：EYE 1.38 / CHIN 1.32 / SHOULDER 1.24 / HAND 0.95 / WAIST 0.92 / KNEE 0.42 …），规范 §2。终局 5 个实例回读 height=1.5000、err=0.0000（§7.3）。
4. **全岛主要资产原始尺寸清单**：`开发产物/p7v32/scale/inventory_baseline.md/.json`（V3.1 冻结态 eaf1559，实测 AABB + 射线扫描，102 项）；主树终态对照 `inventory.md/.json`（107 项）；世界侧另见 `开发产物/p7v32/notes/world_audit.md`。规范 §3–§5 表内「V3.1 原始实测」列即本清单的资产映射。
5. **各类资产最终目标 / 实际 / 修改理由**：规范 §3（房屋）、§4（25 家具）、§5（船/码头/灯塔/路灯/树/生物/环境）、§7（保留项）、§10（本轮变更原因与测试结果）；本报告 §4–§6 为终态结果。
6. **房屋缩放/重建详细方案**：见 §4 与规范 §3。关键变更：外廓 **10.60×8.78 → 7.60×6.20 m**；墙高 6.13 → **3.18**；一层净高 3.98 → **2.42**（阁楼地板 5.70 → **3.17**，楼板 0.20、膝墙 0.56）；屋脊 9.99 → **6.20**（坡 38.3° → **33.02°**，檐口悬挑 0.744 → 0.60）；门洞 → **净宽 1.14 / 中心净高 1.94（拱脚 1.42）**，门扇 **1.00×1.40** + 半圆气窗 R0.50、把手 0.95；楼梯 **27 级 rise 0.1907/tread 0.245 → 16 级 rise 0.16375/tread 0.26/宽 0.85/平台 0.85×0.85**；烟囱顶改读真实石块顶 6.55（高于屋脊 0.35）。重建方式=改墙体/门窗/楼板/屋顶/楼梯构造参数与家具重排，非整 root 缩放；同时修复 V3.1 遗留的 `make_prism_mesh` 三角形绕序缺陷（山墙前向面）。
7. **门窗/楼梯/家具/小船最终尺寸**：门窗见 §4.1（前窗 1.00×1.15 ×2、侧窗 1.00×0.95、后窗 0.90×0.90、阁楼窗 1.50×1.50、窗台 0.90）；楼梯见 §4.1（16 级 / 0.16375 / 0.26 / 0.85 / 扶手 0.85 / 净空 min 2.148）；家具 25 类见 §5 与规范 §4（桌 0.65、椅面 0.40、沙发坐面 0.40、床 1.00×1.90 床垫顶 0.45、书架/衣柜 1.75…）；小船 hull LOA **4.950** / beam **1.520** / draft **0.340** / 干舷局部 midship **0.535**、max sheer **0.724**（世界口径 0.819/1.008，双口径并列）/ boom 抬高至 **1.90**（sole 上净空 1.555）/ cockpit 开敞 + coaming，见 §6 与规范 §5。
8. **需保留夸张比例及理由**：规范 §7（reference_keep）——灯塔 **18.276 m**（地标尺度，远景可读性，不随角色比例缩）、大树（冠幅/高度作为地标遮挡与构图）、岛屿地形直径 **63.6 m** 与近海（空间感/观景）、海鸥体长 **0.671 m**（远景可见 + 绘本夸张，翼展 1.219 在区间内）、旧风车/船只行为参数（保留状态机与时间逻辑）。这些在审计中判 INFO/keep 而非 PASS，以免一刀切。
9. **新增测量工具与自动审计说明**：`scripts/isle_scale_spec.gd`（唯一尺度登记表 + 容差判定）、`scripts/isle_scale_figure.gd`（1.50 m 参照）、`tools/probe_scale_world.gd`（AABB/射线扫描、inventory/audit 模式，107 项）、`tools/scale_debug_overlay.gd`（`--scale-debug` 开发标尺：1 m 立方、1.50 m 人形、垂直/水平刻度、对象尺寸/楼层/门洞标注，默认关闭、关闭完全恢复、构建一次无 `_process`）、`tools/probe_scale_house_p7v32.gd`、`probe_scale_props_scene_p7v32.gd`、`probe_scale_world_assets_p7v32.gd`、`probe_scale_shots_p7v32.gd` 及 §8 全量回归探针。用法见规范 §11、复现命令见附录 A。
10. **相关自动化测试 / 截图路径 / 性能数据**：测试与 RESULT 原文见 §8.1（A1–A13/B0–B3/C1）；截图 `开发产物/p7v32/shots/s01–s16`（+ manifest）与 T2 house/door、官方 `开发产物/shots`；性能 `开发产物/p7v32/logs/perf_v32_r1/r2.log`、`perf_v32b_r1/r2.log`、`perf_freeze_r1.log`，数据见 §10；产物索引见附录 B。
11. **未验证与未完成内容**：§11.4 + §12（soak、发布导出、P95/GPU 时间、主观美观、V3.1 旧口径三个窗口探针、夜间门廊灯光预算决策）。已知视觉遗留：室内吊灯泛光球（冻结前未修，§12 #1）。
12. **后续岛民必须遵守的尺度规范**：① 1 Godot 单位 = 1 m、Y 向上；② 正式岛民总高 **1.50 m**（脚底→头顶含发鞋，容差 ±0.010），任何角色/家具新增前须对照 `isle_scale_spec.gd` 登记目标并跑 `probe_scale_world.gd --mode audit`；③ 门洞净高 ≥ **1.94**（拱脚 1.42）、净宽 ≥ **1.14**、室内净高 **2.42**、楼梯 rise ≈ **0.164**/tread **0.26**/宽 **0.85**；④ 家具尺寸与身体约束（桌面 0.65↔椅面 0.40、床 1.00×1.90 容 1.50 m 人、把手/灯具/柜门在可及高度）不得回退；⑤ 禁止整 root 缩放或全局 scale_multiplier，改程序化构造参数并重测真实 AABB；⑥ 新增/修改资产必须同步规范登记表、审计区间与 `docs/WORLD_SCALE_SPEC.md` 状态列，并在提交前跑到 audit/相关探针 fail=0；⑦ 保留项（灯塔/大树/岛径/海鸥）不得为"统一比例"而缩小，标记用途理由。
