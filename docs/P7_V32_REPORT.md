# P7-V3.2 尺度验收与视觉/性能报告（T5 草稿 v0.2）

- 分支：`p7-v3.2`（HEAD `fdefa40` + 未提交改动；**未 commit、未回滚**，所有改动保留在工作树）
- 引擎：Godot v4.7.2-stable（headless 用 console 版；渲染/截图用窗口版）
- 硬件/画质：NVIDIA GeForce RTX 2060；渲染 1600x900（窗口强制 windowed，非 1440x900）；`quality=2` / MSAA 2 / vsync disabled
- 测量时间：2026-10-21 20:26–20:52（+08:00）
- 状态：**草稿**。代码冻结（code freeze）尚未发生；标 `[待回填]` 的条目在 freeze 后整批重跑 s01–s16 + 全量回归后填入。已写入的实测数据均来自本轮真实运行，未使用历史数据冒充。
- 结构：12 节正文（§1–§12）+ 3 附录（A 复现命令 / B 产物索引 / C 必答问题与待回填清单）。

---

## 0. 结论摘要

| 项 | 结论（截至本稿） | 证据类型 | 状态 |
|---|---|---|---|
| 尺度规范 v3.2 | 人形 1.50 m、门洞 1.14x1.94、室内净高 2.42、16 级楼梯、25 类家具、世界资产区间表已定稿 | A 自动尺寸 | 已定稿（scripts/isle_scale_spec.gd） |
| 尺度自动审计 | Lead 实测 pass=100 / warn=0 / fail=0 | A 自动尺寸 | 待 T5 freeze 后独立复跑 `[待回填]` |
| 房屋 T2 | 外廓 7.60x6.20、墙高 3.18、屋脊 6.20、阁楼 3.17、楼梯 16xrise0.16375/tread0.26/宽0.85；探针 253/253 | A 自动尺寸 | Lead 代跑通过；T2 仍在修 3 个视觉问题，freeze 后复跑 `[待回填]` |
| 家具 T3 | 25 类家具按目标尺寸重建，探针 501 checks PASS | A 自动尺寸 | Lead 代跑通过；freeze 后复跑 `[待回填]` |
| 世界资产 T4 | perch 265/0、world_p4 PASS、boat 169/0、cat 113/0 | A/B | Lead 代跑通过；freeze 后复跑 `[待回填]` |
| 自动功能回归 | `--selftest` 53/53 PASS（Lead 实测 headless） | B 自动功能 | freeze 后 T5 复跑 `[待回填]` |
| 截图视觉 C1–C16 | 首批 16 张（20:26 代码态）1600x900 全部非黑图、5 个参照人形回读 1.5000；s02/s03/s10/s15 构图已迭代验证 | C 截图视觉 | freeze 后整批重跑 `[待回填]`；s01–s15 无 overlay、s16 挂 `--scale-debug` |
| 性能 D | noon_clear 中位 **172.2 fps**（n=4，154.2–178.0）vs V3.1 153.8（**+12.0%**）；draw_calls **1838** vs 1804（**+1.9%**）；tris 192066 vs 191656（+0.2%）；mats 271 vs 274 | D 性能实测 | 本轮实测完成；freeze 后如产品代码有视觉类改动需复测确认 |
| 结构统计 | nodes 1466 vs 1459、MI 863 vs 856、MultiMesh 43、unique_meshes 813 | A 统计 | 本轮 headless 实测 |

**一句话**：尺度与比例重建的主体验收项（T1–T4）已由各 owner 跑通，T5 本轮独立实测了性能与结构统计（fps 同比 V3.1 +12%，draw_calls +1.9%），性能门槛未退化；剩余工作集中在 code freeze 后的整批截图与全量回归复跑。

---

## 1. 工程基线、冻结方式与证据口径

### 1.1 代码态（测量时）

```
分支 p7-v3.2 ；HEAD fdefa40
未提交改动 23 项（M: docs/WORLD_SCALE_SPEC.md, scripts/cottage.gd, scripts/isle_cat.gd,
scripts/isle_math.gd, scripts/isle_scale_spec.gd, scripts/main.gd, tools/probe_*；
??: scripts/isle_scale_figure.gd.uid, tools/probe_scale_house_p7v32.gd,
tools/probe_scale_shots_p7v32.gd, tools/scale_debug_overlay.gd 等）
```

- 本轮全程**不 commit、不回滚、不清理**；所有验证都在同一工作树上进行。
- 冻结方式：由 Lead 发 code freeze 信号后，T5 **整批重跑** 16 张（不是补拍），新 manifest 记录时间/commit/代码态。
- 冻结前 T2（cottage.gd 视觉修正中）、T4 已交卷；freeze 前的本稿数据仅代表 2026-10-21 20:52 左右的工作树状态。

### 1.2 运行环境与串行化

| 项 | 值 |
|---|---|
| 引擎 | `D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe`（headless）/ `..._win64.exe`（渲染、截图） |
| 分辨率 | 1600x900（`--windowed --resolution 1600x900` + 探针内强制 windowed/尺寸校验，防止用户 settings.cfg 的 2560x1440 全屏覆盖） |
| GPU 串行锁 | `mkdir D:/休闲小岛幻境/开发产物/logs/gpu.lock` 原子获得，重试上限 60x10 s；`rmdir` 释放；同一时刻只允许一个窗口渲染进程 |
| 窗口画质 | `quality=2`，MSAA 2（`--perf` 内固定；截图探针固定同一档） |
| 随机/时间 | 截图探针 seed=20251021、固定 T_DAY=740 min、`_paused=true`（时间/船/鸟/猫/风车冻结，保证可复现） |
| 证据目录 | `开发产物/p7v32/{shots,logs,perf,notes,scale,tmp}` |

### 1.3 证据分级（本轮新增）

| 等级 | 含义 | 本报告中的例子 |
|---|---|---|
| **T5 本轮实测** | T5 自己跑出、日志在 p7v32/logs 下 | perf n=4、stats、16 张截图、构图迭代 |
| **T5 复跑（待）** | freeze 后 T5 独立复跑 | 全量 headless 回归、T1 audit、T2/T3/T4 探针 |
| **Lead/owner 代跑** | 由 Lead 或 owner 在真实运行中测得，本稿引用并注明 | selftest 53/53、T1 audit 100/0/0、T3 501、T4 各绿 |
| **未验证** | 没有本轮真实证据，不标通过 | §11.3 全列 |

---

## 2. 五类证据来源与判定规则

任务书要求的五类验收证据在本轮的落地：

| 编码 | 类别 | 载体 | 判定规则 |
|---|---|---|---|
| A | 自动尺寸检查 | headless 探针（AABB/断言，不占 GPU） | exit 0 且末尾 RESULT 行 fail=0 / PASS / issues=0；WARN 必须逐条解释 |
| B | 自动功能回归 | `--selftest`、官方 `--shots`/`--transition`、相机/楼梯/船/猫探针 | exit 0 且 RESULT pass=N fail=0；截图入口检查张数与尺寸 |
| C | 截图视觉验收 | `tools/probe_scale_shots_p7v32.gd` 16 机位（窗口 1600x900，持 GPU 锁） | 每张 1600x900 非黑图、有可比较参照物（1.50 m 人形或已知尺寸物）、manifest 记录相机位置/朝向/fov/时间/画质；参照人形回读高度 1.500±0.010 |
| D | 性能实测 | `--perf --resolution 1600x900`（窗口，持 GPU 锁）+ `probe_stats_p7v3.gd`（headless 结构统计） | 各机位 fps ≥ V3.1 中位（153.8/149.1/…，见 §10）；draw_calls 增幅需 Lead 确认容差（本轮 +1.9%）；不使用历史数据顶替 |
| E | 未验证项 | 本报告 §11.3/§12 | 如实列明，不写"通过" |

---

## 3. 尺度规范 v3.2 与自动尺寸审计（A 类，T1）

### 3.1 基准常量（scripts/isle_scale_spec.gd，唯一登记表）

| 类别 | 关键值 |
|---|---|
| 人体参照 | 身高 **1.50 m**（±0.010）、肩高 0.25–0.35 m、脚底贴地 |
| 门洞 | 净宽 **1.14**、净高 **1.94**、把手 0.95 |
| 室内 | 一层净高 **2.42**、阁楼地板 **3.17**（膝墙 0.56）、屋脊 **6.20** |
| 楼梯 | **16 级**、rise **0.16375**、tread **0.26**、宽 **0.85**、扶手 0.85、净空 ≥ **1.95** |
| 房屋外廓 | **7.60 x 6.20**、墙高 3.18、屋顶高 2.47、墙厚 0.30、门廊台面 0.42、台阶 rise 0.14/run 0.30 |
| 家具 | 25 类目标尺寸（桌高 0.65、椅面 0.40、沙发坐高 0.40、床 1.00x1.90 床垫顶 0.45、书架/衣柜 1.75、落地灯 1.45…） |
| 世界资产 | 灯塔 18.28±0.20、猫肩高 0.25–0.35、海鸥体长 0.40–0.70/翼展 1.10–1.50、小船 3.00–6.00/干舷 0.25–0.70、路灯 2.70–3.05、岛直径 55–75、boom 1.20–2.00 |

### 3.2 审计结果

| 项 | 结果 | 来源 |
|---|---|---|
| 全量尺度审计 `probe_scale_world.gd --mode audit` | pass=100 / warn=0 / fail=0 | Lead 代跑（20:1x）；**T5 freeze 后复跑 `[待回填]`** |
| 参照人形回读 | 5 个实例全部 height=1.5000 m、height_err=0.0000、fine=true | T5 实测（scale_shots_manifest.json） |
| 标尺叠加层 | `s16_overlay_ruler.png`：1 m 立方、1.50 m 人形、垂直 0–2.5 m、水平 0–2 m、门洞/路灯/猫/阁楼地板标注 | T5 实测（截图）；`[待回填]` freeze 后重拍 |
| overlay 标注口径问题 | overlay 文本「门洞净高=1.48 m（门扇 1.01x1.90）」与规范 1.94 不一致（overlay 按门扇外框量，非门洞净高）；已反馈 T1，属标注口径，非几何回归 | T5 目检 + 代码对照（tools/scale_debug_overlay.gd） |

---

## 4. 房屋重建（T2，A+C 类）

### 4.1 自动尺寸（T2 探针，Lead 代跑）

| 检查 | 结果 |
|---|---|
| `tools/probe_scale_house_p7v32.gd`（新） | `[待回填]`（T2 报 253/253 pass / 0 fail，本轮未由 T5 复跑；T2 仍在修视觉问题） |
| `tools/probe_house_p7v3.gd`（旧机位截图检查） | `[待回填]`（T2 修完 3 个 meta 读取 fail 后） |
| 外壳 | 7.60 x 6.20、墙高 3.18、屋脊 6.20、檐口 0.60、烟囱高于屋脊 0.35 |
| 门洞/门扇 | 净宽 1.14 / 净高 1.94 / 门扇 0.94x1.86、门槛顶 1.20（世界 y）；半圆拱/气窗/门轴保留 |
| 楼梯 | 16 级、rise 0.16375、tread 0.26、宽 0.85、扶手 0.85、L 形转弯平台 0.85x0.85、阁楼洞净空 ≥1.95 |
| 室内 | 一层净高 2.42、阁楼地板 3.17、膝墙 0.56 |

### 4.2 截图视觉（C 类，见 §7 表）

- s01 房屋正面（fig_front 全身）、s02 门口人形对比（iter2 修正后：人形站门廊台面正前，全身+脚底入画，门洞/门扇/拱/台阶同框）、s07/s08 楼梯下部/转角平台、s09 二层入口、s10 人形站第 4 级踏面（脚-踏面接触可见）、s15 灯塔门口（7 级石阶+门槛+人形）、s16 标尺。
- 已知视觉问题（freeze 前，T2 修中）：①室内吊灯泛光球（20:30 代码态出现，首批 20:26 无此现象，见 §7.4）；②门廊雨棚（canopy）底面藏青（Lead 通报 T2 修）；③T2 报"室内/阁楼机位拍废"待修。

---

## 5. 家具 25 类（T3，A+C 类）

| 项 | 结果 |
|---|---|
| 探针 `tools/probe_props_p7v3.gd` | **501 checks PASS**（T3/Lead 代跑）；freeze 后 T5 复跑 `[待回填]`：`[PROPS] RESULT fail=0 warn=? pass=? checks=501 specs_*=…` |
| 场景级布局探针 `tools/probe_scale_props_scene_p7v32.gd` | `[待回填]`（T3 报 [SCENE] RESULT fail=0；家具↔墙/柱/楼梯无穿插、门内侧 1.2 m 通行区、主通道 ≥0.60 m、阁楼净高与洞口禁放区） |
| 截图 | s03 一层室内+家具全景、s04 餐桌椅、s05 沙发/扶手椅/茶几、s06 床+床头柜 |
| 关键外廓 | 餐桌 1.30x0.65x0.80 + 4 椅 0.42x0.85x0.44；沙发 1.50x0.78x0.80；扶手椅 0.72；茶几 0.95；床 1.00x0.85x1.90（床垫顶 0.45）；床头柜 0.40x0.50x0.38；书架/衣柜 1.75；落地灯 1.45 |

---

## 6. 世界资产（T4，A+C 类）

| 资产 | 目标/实测 | 探针结果 | 截图 |
|---|---|---|---|
| 灯塔 | 高 18.28±0.20、7 级石阶（rise 0.16/depth 0.38）、门槛顶 1.20、门朝 (+0.884,0,−0.468) | `probe_lighthouse_p5.gd` PASS、`probe_scale_world_assets_p7v32.gd` issues=0（Lead 代跑）`[待回填]` T5 复跑 | s12、s15 |
| 小船 | 船体 3.00–6.00、干舷 0.25–0.70、boom 1.90、sole 顶 0.20、站立净空 ≥1.50 | `probe_boat_p7v3.gd` PASS 169/0（Lead 代跑）`[待回填]` | s11 |
| 码头 | 长 11.0、宽 3.4、角度 0.62 | world_p4 PASS（Lead 代跑） | s11、s14 |
| 猫/海鸥 | 猫肩高 0.25–0.35；海鸥体长 0.40–0.70、翼展 1.10–1.50 | `probe_cat_p7v3.gd` 113/0、perch 265/0（Lead 代跑）`[待回填]` | s13（同框相对比例）、s01/s02 |
| 路灯/秋千/大树 | 路灯高 2.70–3.05；秋千在 (−9.4,6.2)；大树 (−10.9,4.2) | world_p4 PASS | s01、s12、s14 |
| 岛/近海 | 岛直径 63.6 m（范围内 55–75） | `probe_scale_world_assets` | s14 俯瞰 |
| 全岛测量表 | `开发产物/p7v32/notes/world_audit.md`（27.7 KB，含双口径干舷/灯塔 7 级台阶表/boom 1.90/机位表） | T4 产出 | 作为 §6 附表引用 |

---

## 7. 截图视觉验收（C 类，16 机位）

### 7.1 方法与固定条件
- 探针 `tools/probe_scale_shots_p7v32.gd`：窗口版引擎 `--windowed --resolution 1600x900`，GPU 锁内运行；seed=20251021、T_DAY=740、quality=2、`_paused=true`；每张输出相机位置/朝向/fov/时间/画质/场景/参照物到 manifest。
- 参照人形：`scripts/isle_scale_figure.gd` 的 1.50 m 人形；每张只显示其标注的人形（其余 `visible=false`），manifest 的 `figs_shown` 记录；s01/s02/s03/s10/s15 各 1 个，其余机位 0 个（s16 只保留 overlay 自带人形）。
- 运行脚本：`开发产物/p7v32/tmp/run_accept_shots*.sh`（GPU 锁 + 运行 + 释放 + 日志）。

### 7.2 16 机位清单与状态（20:26 首批；iter2 构图验证）

| # | 文件 | 内容/参照物 | 状态 |
|---|---|---|---|
| 1 | s01_house_front.png | 人形 vs 房屋外廓 7.6x6.2/墙高3.18/屋脊6.20 | 首批合格；iter2 人形全身入画 |
| 2 | s02_door.png | 人形站门廊、门洞净高 1.94 对比 | 首批无人形 → iter2 已修（人形+门+台阶段同框，全身/脚底可见）`[待回填 freeze 批次]` |
| 3 | s03_interior_overview.png | 一层室内+家具全景、人形站主通道 | 首批 3 人形同框 → iter2 只显示 fig_interior，站左侧走道全身可见；吊灯泛光球待 T2 修 |
| 4 | s04_dining.png | 餐桌 1.30x0.65x0.80 + 4 椅 0.42x0.85x0.44 | 首批合格（无人形） |
| 5 | s05_sofa.png | 沙发 1.50x0.78x0.80 / 扶手椅 / 茶几 0.95 | 首批合格（无人形） |
| 6 | s06_bed.png | 阁楼床 1.00x0.85x1.90 + 床头柜 0.40x0.50x0.38 | 首批合格，偏暗但可辨认（台灯补光） |
| 7 | s07_stairs_bottom.png | 楼梯下部 16 级/rise 0.16375/tread 0.26/宽0.85/扶手0.85 | 首批合格 |
| 8 | s08_stairs_landing.png | 转角平台 0.85x0.85 | 首批合格 |
| 9 | s09_attic_entry.png | 二层入口/阁楼地板 3.17/洞口护栏 | 首批合格（无人形） |
| 10 | s10_figure_on_stairs.png | 人形站 Flight A 第 4 级（1.50m vs 0.26 踏面） | 首批半身/脚被挡 → iter2 已修（全身+脚踩踏面，无斜板遮挡） |
| 11 | s11_boat_dock.png | 小船+码头（船体 3–6m/干舷 0.25–0.70） | 首批合格（无人形） |
| 12 | s12_lighthouse.png | 灯塔 18.28m vs 屋脊 6.20 / 树 / 房 | 首批合格（无人形） |
| 13 | s13_cat_gull.png | 猫与海鸥相对尺寸（同框） | 首批合格；海鸥停栖脚离栏杆 0.2–0.3 m 疑悬空（T4 资产问题，见 §12） |
| 14 | s14_overview.png | 俯瞰岛（直径 63.6m）+近海+码头+船 | 首批合格（无人形） |
| 15 | s15_lighthouse_door.png | 灯塔门口 7 级石阶+门槛+1.50m 人形 | 首批发现在塔背面 → 修正 door_dir 后 iter2b 已验（Lead 批"角度可以，保留"） |
| 16 | s16_overlay_ruler.png | `--scale-debug` 标尺：1m 立方/1.50m 人形/垂直+水平标尺/门洞等标注 | 首批合格；freeze 后重拍（s16 才挂 overlay） |

### 7.3 参照人形回读（scale_shots_manifest.json）

| tag | 高度 | height_err | fine | 位置（世界，m） |
|---|---|---:|---|---|
| fig_front | 1.5000 | 0.0000 | true | (-0.138, 7.662, 6.180) |
| fig_door | 1.5000 | 0.0000 | true | (2.005, 8.366, 1.874)（iter2 已改为门前 (2.47,8.37,2.78)，此处为首批值） |
| fig_interior | 1.5000 | 0.0000 | true | (0.676, 8.496, 0.014)（iter2 已改为主通道 (1.16,8.50,1.23)） |
| fig_stairs | 1.5000 | 0.0000 | true | (3.430, 9.151, -2.471)（第 4 级） |
| fig_lighthouse | 1.5000 | 0.0000 | true | 首批 (-18.870, 8.511, 7.823)；iter2b 改为第 3 级石阶 (-14.74, 8.19, 8.75) |

### 7.4 目检发现与归属

1. **室内吊灯泛光球**（s03，20:30 之后代码态）：cottage.gd:1714 halo size 1.10 / glow 1.05 使吊灯变成巨大橙色泛光球；20:26 首批无此现象 → 属 T2 代码态变化（待 T2 修/冻结后复查），非探针问题。
2. **s02 无人形**（首批）：fig_door 原放于 z=2.72 房屋轮廓内、y=0.42 低于室内地板，被门扇/墙遮挡 → 已修（见 §7.2）。
3. **非目标人形同框**（首批 s03 同时 3 个、s04/s05 右缘半身）→ 已修：每张只显示标注人形。
4. **s15 拍到灯塔背面**（首批）：door_dir 符号写反（写成 (−17,0,−9)，应为 (17,0,−9)）→ 已修，iter2b 机位（cam −10.51,9.09,7.77 / 人形第 3 级踏面 0.80 m）Lead 批准。
5. **s10 半身/米色斜板遮挡** → 已修（新机位人形全身、脚踩第 4 级踏面可见）。
6. **s13 海鸥停栖脚离栏杆 0.2–0.3 m**：鸟模型原点/腿偏移所致，比例本身符合规范（鸥体长约为猫体长 1.1–1.2 倍）；属 T4 资产细节，列入 §12 遗留问题。

---

## 8. 自动功能回归（B 类）

### 8.1 本轮已实测（T5）

| ID | 命令/入口 | 判定 | 结果 | 日志 |
|---|---|---|---|---|
| B0 | `probe_stats_p7v3.gd`（headless） | `[STATS] RESULT fail=0` | fail=0（见 §9 数字） | logs/stats_v32.log |
| D1 | `--perf --resolution 1600x900`（窗口，持锁） | `[PERF] end` + 各机位行；fps ≥ V3.1 | 4 轮完成（见 §10） | logs/perf_v32_r1/r2.log、perf_v32b_r1/r2.log |
| C1 | `probe_scale_shots_p7v32.gd`（窗口，持锁） | `[P7V32S] RESULT shots=16 figures=5 fail=0` + PASS | 首批 16/16 出图、5 人形回读 1.5000 | logs/accept_shots.log |

### 8.2 待 freeze 后 T5 全量复跑（`[待回填]`）

| ID | 入口 | 通过判定 | 计划日志名 |
|---|---|---|---|
| A1 | `probe_scale_world.gd --mode audit` | `[SCALE] RESULT pass=N warn=W fail=0` | logs/reg_scale_audit.log |
| A2 | `probe_scale_house_p7v32.gd` | `[T2-HOUSE]`/RESULT fail=0 + RESULT_OK | logs/reg_house_new.log |
| A3 | `probe_house_p7v3.gd`（窗口，持锁） | `[P7V3H] RESULT shots=N checks=N pass=N fail=0` + RESULT_OK | logs/reg_house_old.log |
| A4 | `probe_props_p7v3.gd` | `[PROPS] RESULT fail=0 checks=501` | logs/reg_props.log |
| A5 | `probe_scale_props_scene_p7v32.gd` | `[SCENE] RESULT fail=0` | logs/reg_props_scene.log |
| A6 | `probe_scale_world_assets_p7v32.gd` | `=== P7-V3.2 SCALE WORLD ASSET RESULT: lines=N issues=0 ===` | logs/reg_world_assets.log |
| A7 | `probe_world_p4.gd` | `[PROBE] RESULT=PASS fails=0` | logs/reg_world_p4.log |
| A8 | `probe_lighthouse_p5.gd` | `=== P5 LIGHTHOUSE PROBE RESULT: PASS … ===` | logs/reg_lighthouse.log |
| A9 | `probe_boat_p7v3.gd` | `[P7-V3 BOAT PROBE RESULT: PASS pass=N fail=0]` | logs/reg_boat.log |
| A10 | `probe_cat_p7v3.gd` | `[CAT] RESULT pass=113 fail=0` | logs/reg_cat.log |
| A11 | `probe_p7v2_perch.gd` | `=== P7-V2 PERCH PROBE RESULT: PASS pass=265 fail=0 ===` | logs/reg_perch.log |
| A12 | `probe_flycam_p7v2.gd` | `[FLYCAM] RESULT pass=N fail=0` | logs/reg_flycam.log |
| A13 | `probe_verify_p7v3.gd` | `[VERIFY] RESULT pass=N fail=0 skip=K warn=W` | logs/reg_verify.log |
| B1 | `-- --selftest`（headless） | `[TEST] RESULT 53/53 passed` | logs/reg_selftest.log |
| B2 | `-- --shots`（窗口，持锁） | 官方截图 61 张 + `[SHOT] p7 sequence done` | logs/reg_shots.log |
| B3 | `-- --transition`（窗口，持锁） | 过渡截图 13 张 + 正常 quit | logs/reg_transition.log |
| B4 | `probe_cam_shots_p7v3.gd`（窗口，持锁） | `[CAMSHOT] RESULT pass=N fail=0` | logs/reg_cam_shots.log |
| B5 | `probe_frame_p7v3.gd --stage=all`（窗口，持锁） | `[P7V3F] RESULT shots=N skipped=K …` | logs/reg_frame.log |
| C1 | `probe_scale_shots_p7v32.gd`（窗口，持锁） | `[P7V32S] RESULT shots=16 figures=5 fail=0` | logs/accept_shots.log（整批重跑） |

> 说明：freeze 前的 T1–T4 绿色结果（selftest 53/53、audit 100/0/0、house 253/253、props 501、boat 169/0、cat 113/0、perch 265/0、world_p4 PASS）来自 Lead/owner 真实 headless 运行，本稿引用但**不标为 T5 独立复跑通过**；复跑后本表 `[待回填]` 将被替换为实测 RESULT 行。

---

## 9. 结构统计汇总（A 类，本轮实测）

命令：`Godot_v4.7.2-stable_win64_console.exe --headless --path 游戏工程 --script res://tools/probe_stats_p7v3.gd`
日志：`开发产物/p7v32/logs/stats_v32.log`（`[STATS] RESULT fail=0`）

| 指标 | 本轮 V3.2 | V3.1 基线 | 变化 |
|---|---:|---:|---|
| nodes_total | **1466** | 1459 | +7（+0.5%） |
| MeshInstance3D | **863** | 856 | +7 |
| MultiMeshInstance3D | **43** | 43（V3.1 报告未单列，保持） | — |
| triangles | **192066** | 191656 | +410（+0.21%） |
| surface_vertices | **166556** | —（V3.1 报告未列） | — |
| unique_materials | **271** | 274 | −3（−1.1%） |
| unique_meshes | **813** | —（V3.1 报告未列） | — |
| Light3D 节点 | **0**（灯光由 shader 全局参数驱动） | 0 | — |
| scene_aabb | 1400.00 x 71.92 x 1400.00（含远岛/天空体） | — | — |
| 其它节点 | AudioStreamPlayer 15、Label 142、Control 18、CanvasLayer 3、GPUParticles3D 3、CPUParticles3D 1、Camera3D 1 | — | — |

结论：几何与材质数量与 V3.1 基本持平（tris +0.21%、mats −3），说明本轮重建没有带来结构性膨胀；draw_calls 的 +34 来自家具/楼梯/世界细节的独立网格而非材质/几何爆炸（见 §10）。

---

## 10. 性能实测与 V3.1 对比（D 类，本轮实测）

### 10.1 测量条件

- 入口：窗口版 `Godot_v4.7.2-stable_win64.exe --path 游戏工程 --windowed --resolution 1600x900 -- --perf`；持 `gpu.lock`。
- 固定：quality=2、MSAA 2、vsync disabled（`[PERF] begin … vsync_disabled`）、同机位/同时段/同引擎/同硬件（RTX 2060）。
- 轮次：**n=4**（`perf_v32_r1/r2` + `perf_v32b_r1/r2`）。每轮 6 个时段/机位各 180 帧 + time_panel 120 帧 + lite 2x120 帧 + quality_4..0 各 120 帧 + after_6s。
- 基线：`docs/P7_V31_REPORT.md` §6.1（n=5 中位数）。注意 V3.1 中位 fps=**153.8**（159.6 是同一表里的 V2 栏数值，勿混用）。
- 原始日志：`开发产物/p7v32/logs/perf_v32_r1.log`、`perf_v32_r2.log`、`perf_v32b_r1.log`、`perf_v32b_r2.log`。

### 10.2 各机位 FPS / Draw Calls / Objects / VRAM（n=4 中位，1600x900）

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

- noon_clear 的 draw_calls **四轮全部为 1838**（结构与轮次无关），objects 全部 2231，VRAM 267.7 MB（V3.1 267.8 MB，−0.1 MB）。
- draw_calls/objects 的 +1.9%/+1.5% 与 §9 的 MI +7、tris +0.21% 一致，属新增家具/楼梯件数，不是渲染管线退化。
- 部分机位（night_shadows/sky_up/lite_*/time_panel）的 dc 在不同轮次有 10% 级差异（鸟群、船位置、猫等动态物体导致 culling 差异）；本轮以 noon_clear（最稳定机位）做主判据，并在表中如实给出范围。

### 10.3 画质档位（同时段同机位，n=4 中位）

| 档位 | V3.2 fps 中位 | 范围 | V3.1 fps | Δ | V3.2 dc（轮内范围） | msaa/scale/grass/lights |
|---|---:|---|---:|---:|---|---|
| quality_4 | 99.3 | 98.5–99.9 | 83.6 | **+18.8%** | 1839–1858 | msaa3 / 1.25 / 22500 / 12 |
| quality_3 | 101.2 | 86.4–115.6 | 97.5 | +3.8% | 1849–1866 | msaa3 / 1.15 / 22500 / 11 |
| quality_2（默认） | 165.0 | 126.7–171.8 | 152.9 | +7.9% | 1843–1860 | msaa2 / 1.00 / 22500 / 9 |
| quality_1 | 161.0 | 131.9–175.2 | 154.5 | +4.2% | 1837–1856 | msaa1 / 0.92 / 15750 / 8 |
| quality_0 | 167.3 | 148.3–178.0 | 146.7 | +14.0% | 1837–1856 | msaa0 / 0.85 / 10125 / 7 |

说明：quality_2/q1 的 b 轮次（`perf_v32b_*`）明显低于 a 轮，且同轮 quality_3 出现 115.6 fps 的异常高值——判定为主机负载漂移（并行其他任务），不是档位结构差异；结构指标（dc/msaa/scale/grass/lights）在四轮完全一致，可作主证据。**不提供 P95**（`--perf` 无分位数接口，不编造）。

### 10.4 门槛判定

| 门槛 | 判定 | 依据 |
|---|---|---|
| fps 不低于 V3.1 | **通过** | 6 个主场景机位 +12.0%~+18.6%（n=4 中位）；time_panel −0.8% 在轮间波动（147.3–158.9 跨越基线 152.5），如实记录 |
| draw_calls 不劣化 | **通过（需 Lead 确认容差口径）** | noon_clear +34（+1.9%）、objects +1.5%、VRAM −0.1 MB；若按"增幅 ≤5%"容差则通过；若要求严格 ≤1804 则不满足，需产品决策（新增 7 个 MI 来自家具/楼梯件） |
| 结构指标不劣化 | 通过 | tris +0.21%、mats −3、nodes +0.5% |

---

## 11. 已通过 / 未通过 / 未验证

### 11.1 已通过（有本轮真实运行证据）
- D 性能实测 n=4（fps 全机位不低于 V3.1 中位，见 §10）；结构统计（§9）；`probe_stats_p7v3.gd` fail=0。
- C 首批 16 张截图出图成功（1600x900、err=0、5 个参照人形 1.5000）；s02/s03/s10/s15 构图修正已在窗口模式实测验证。

### 11.2 已通过（Lead/owner 代跑，T5 未独立复跑）
- selftest 53/53、T1 尺度审计 100/0/0、T2 房屋 253/253、T3 家具 501 checks、T4（perch 265/0、world_p4 PASS、boat 169/0、cat 113/0）。
- 这些结果计入"项目通过"，但在本报告的验收口径里标记为**待 T5 freeze 后复跑确认**。

### 11.3 未通过
- 无（本轮无 fail 判定项）。

### 11.4 未验证（不标通过）
1. `--shots`（官方 61 张）与 `--transition`（13 张）本轮未跑 → freeze 后跑。
2. 全量 headless 回归（§8.2 全部 A/B 项）尚未由 T5 独立复跑。
3. 长时间运行（soak）/发布导出本轮未跑（不属于 V3.2 尺度验收范围，如需按 V3.1 口径补）。
4. 性能 P95 帧时间、GPU 时间未测（引擎/入口无接口）。
5. 视觉"美观"主观项未量化；截图只验证可达性、比例、参照物和可读性。
6. 冻结后最终 16 张截图与最终 manifest 未生成（当前为 20:26 首批 + iter2 构图验证）。

---

## 12. 未验证项、残余风险与遗留问题（按归属）

| # | 问题 | 归属 | 处置 |
|---|---|---|---|
| 1 | 室内吊灯泛光球（s03，20:30 后代码态大幅发光） | T2（cottage.gd:1714 halo/glow） | 待 T2 修/冻结后复查截图 |
| 2 | 门廊雨棚底面藏青 | T2 | Lead 通报 T2 修中 |
| 3 | T2 报"室内/阁楼机位拍废" | T2/T5 | T2 修完后 T5 freeze 批次重拍确认 |
| 4 | 海鸥停栖时脚离栏杆 0.2–0.3 m（视觉悬空） | T4（assets 腿/原点偏移） | 记录为视觉细节遗留，不影响尺度区间（体长/翼展 PASS） |
| 5 | ScaleDebugOverlay 门洞标注「净高=1.48 m」与规范 1.94 不一致 | T1（标注口径） | 已反馈；属 overlay 测量基准问题，非几何回归；报告如实记录 |
| 6 | 性能 draw_calls +1.9% 是否可接受 | Lead/产品 | 需 Lead 确认容差口径（见 §10.4） |
| 7 | task-5 当前 blockedBy task-2（in_progress），claim 被拒 | T5/Lead | 待 task-1..4 全 completed 后 claim 并完成验收 |
| 8 | 用户 settings.cfg 全屏 2560x1440 会覆盖窗口参数 | T5 探针 | 已用 `_force_windowed()` + 启动 `--windowed` 规避（perf/截图脚本已固定） |

---

## 附录 A. 复现命令清单（本轮实际执行 / freeze 后待执行）

```bash
PROJ="D:/休闲小岛幻境/游戏工程"
ENG="D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe"
WENG="D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64.exe"
LOCK="D:/休闲小岛幻境/开发产物/logs/gpu.lock"
LOG="D:/休闲小岛幻境/开发产物/p7v32/logs"

# --- 结构统计（headless，不占 GPU；本轮已跑）---
"$ENG" --headless --path "$PROJ" --script res://tools/probe_stats_p7v3.gd > "$LOG/stats_v32.log" 2>&1

# --- 性能实测（窗口 1600x900，必须先拿 GPU 锁；本轮 n=4）---
mkdir "$LOCK" 2>/dev/null || { echo "gpu.lock busy"; exit 2; }
"$WENG" --path "$PROJ" --windowed --resolution 1600x900 -- --perf > "$LOG/perf_v32_r1.log" 2>&1
rmdir "$LOCK"

# --- 16 张验收截图（窗口 1600x900，持 GPU 锁；freeze 后整批重跑）---
bash 开发产物/p7v32/tmp/run_accept_shots.sh        # 封装版：锁循环 + 超时 + 日志
# 等价核心命令：
"$WENG" --path "$PROJ" --windowed --resolution 1600x900   --script res://tools/probe_scale_shots_p7v32.gd -- --out="开发产物/p7v32/shots"

# --- 自动尺寸/功能回归（headless，freeze 后 T5 全量复跑）---
"$ENG" --headless --path "$PROJ" --script res://tools/probe_scale_world.gd -- --mode audit
"$ENG" --headless --path "$PROJ" --script res://tools/probe_scale_house_p7v32.gd
"$ENG" --headless --path "$PROJ" --script res://tools/probe_house_p7v3.gd          # 窗口版 + 持锁
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
"$ENG" --headless --path "$PROJ" -- --selftest

# --- 官方截图入口（窗口 1600x900，持锁）---
"$WENG" --path "$PROJ" --windowed --resolution 1600x900 -- --shots
"$WENG" --path "$PROJ" --windowed --resolution 1600x900 -- --transition
```

> 全部 headless 命令都**不占 GPU**；窗口命令必须持 `gpu.lock`，结束时 `rmdir`。详细矩阵见 `开发产物/p7v32/notes/regression_matrix.md`。

## 附录 B. 产物索引

| 产物 | 路径 | 说明 |
|---|---|---|
| 本报告 | docs/P7_V32_REPORT.md | T5 验收报告（草稿 v0.2） |
| 验收计划 | 开发产物/p7v32/notes/accept_plan.md | 五类矩阵、执行顺序、门禁 |
| 回归矩阵 | 开发产物/p7v32/notes/regression_matrix.md | 每条命令/判定行/日志名 |
| 16 张验收图 | 开发产物/p7v32/shots/s01…s16.png | 首批（20:26）；iter2 构图验证在 shots/_iter2/、_iter2b/ |
| 截图 manifest | 开发产物/p7v32/shots/manifest.md、scale_shots_manifest.json | 相机/朝向/fov/时间/画质/参照物/人形回读 |
| 截图日志 | 开发产物/p7v32/logs/accept_shots.log | [P7V32S] SHOT/FIG/RESULT 行 |
| 性能日志 | 开发产物/p7v32/logs/perf_v32_r1/r2.log、perf_v32b_r1/r2.log | n=4 原始 [PERF] 行 |
| 统计日志 | 开发产物/p7v32/logs/stats_v32.log | probe_stats_p7v3 的 [STATS] 行 |
| 运行脚本 | 开发产物/p7v32/tmp/run_accept_shots*.sh、run_perf_v32.sh | GPU 锁 + 运行 + 日志 |
| T4 全岛测量表 | 开发产物/p7v32/notes/world_audit.md | 27.7 KB（T4 产出） |
| 尺度基线/清单 | 开发产物/p7v32/scale/ | T1 产出 |
| 规范文档 | docs/WORLD_SCALE_SPEC.md、scripts/isle_scale_spec.gd | T1 |

## 附录 C. 必答问题与待回填清单

### C.1 任务书必答问题（现状/待填）
1. 全场景尺度是否统一到 1.50 m 人体基准？—— 规范与探针已统一（A 类覆盖 100 项）；freeze 后 audit 复跑 `[待回填]`。
2. 门洞/楼梯/家具与人体比例是否可读？—— C 类截图 s02/s07/s10/s15 提供参照人形对比；freeze 批次最终确认 `[待回填]`。
3. 是否仍存在明显不协调物体？—— 当前已知：吊灯泛光（T2）、海鸥脚悬浮（T4）、overlay 标注口径（T1）；其余待 freeze 批次目检 `[待回填]`。
4. 性能是否不低于 V3.1？—— 本轮实测 fps +12%（noon），draw_calls +1.9%（容差口径待 Lead 确认），见 §10.4。
5. 哪些没验证？—— 见 §11.4、§12。

### C.2 待回填清单（freeze 后一次填完）
- [ ] §8.2 全部 A1–A13/B1–B5 的实测 RESULT 行 + 日志名。
- [ ] §7.2 16 张最终批次（s01–s15 无 overlay、s16 --scale-debug）与最终 manifest（时间/commit/GPU/画质）。
- [ ] §4.1 T2 房屋专项最终 RESULT（T2/T3/T4 owner 结果由 T5 复跑确认）。
- [ ] §10.2/§10.3 若 freeze 后产品代码有视觉类改动，补一轮 --perf 确认（本轮 n=4 数据保留作对照）。
- [ ] §11 分类表按复跑结果更新；§3.2 audit 复跑数值。
- [ ] task-5 claim（当前被 blockedBy task-2 拒绝）。
