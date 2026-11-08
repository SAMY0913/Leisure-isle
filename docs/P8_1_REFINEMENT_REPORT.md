# P8.1 精修阶段实施报告

> **状态**：已完成（P8.1-02…P8.1-07 已提交并通过阶段验收；P8.1-08 全量回归/发布完成，代码冻结于 **6de37c4**，冻结 tag **p81-refinement-freeze-20261022** 指向其后的文档提交）。
> **基线**：从 P8 冻结 tag **p8-weather-seasons-freeze-20261022**（commit **ae1c29d**）出发，在分支 **p81-integration** 上完成 11 个提交（8 个功能/计划提交 f9cc8b3→00ff6c1 + 3 个 -08 提交：572af3d 构建修复、6de37c4 .uid 补交、本轮文档提交）；文中「代码冻结」= **6de37c4**。
> **生成日期**：2026-10-22；**配套文档**：`docs/P8_1_TEST_RESULTS.md`（测试与证据索引）、`docs/P8_1_REFINEMENT_PLAN.md`（计划书，含实施状态回填）。
> **数字纪律**：本文所有数字来自各阶段证据目录中的日志/JSON/探针输出、`git` 实际输出或本次逐行实读源码；无法运行时闭环的一律标「未验证/待实测」或「待 Lead 核实」，不凭记忆补数。

## 目录

- §0 数字口径与结论摘要
- §1 基线与阶段总览（提交 / tag / 变更规模）
- §2 P8.1-02 冬季裸树、裸枝栖点、屋前红花
- §3 P8.1-03 冬季白化与室内豁免
- §4 P8.1-04 天气权重校准（13 → 12 类）
- §5 P8.1-05 强风视觉（落叶 / 萤火 / 秋千）
- §6 P8.1-06 壁炉与室内外照明（16 槽双池）
- §7 P8.1-07 原生日期时间滚轮
- §8 与 P8 冻结基线的关系与历史文档注记
- §9 阶段验收门汇总（G2–G8）
- §10 与计划书的偏差清单
- §11 回滚方案
- §12 未验证与遗留
- §13 结论与后续建议
- 附录 A 关键文件与行号索引
- 附录 B 占位符回填值表

---

## §0 数字口径与结论摘要

### 0.1 数字口径

1. **改动规模**：一律用 `git diff --numstat / --shortstat` 口径；证据 README 中手工统计与 numstat 的差异会在对应阶段注明（已知：-03、-05 的 README 摘要与 numstat 不同，正文用 numstat）。
2. **探针计数**：以证据日志中的 `RESULT/SUMMARY` 行为准；同一探针跨阶段计数可能变化（`probe_p8_weather` 在 P8 为 3135，-04 后为 3145），引用时注明阶段。各阶段重跑同一探针属于回归复跑，做总量统计时按最终口径去重。
3. **性能**：全部为**同机、同 HEAD 导出副本的 A/B** 或“阶段改动 vs 基线副本”对照；不与 P8 报告中的历史绝对值直接比较（存在整机/时段漂移）。帧时间单位 ms，质量为 q0–q4 五档。
4. **截图**：-08 已将 -02/-03/-05 证据统一重拍为 **1600×900（147 张）**；-06 正式矩阵为 2560×1440；-07 阶段二 9 张为 1440×900 输入基准 + 1600×900 复检；P8 冻结 46 张为 1600×900、未重拍（U45），**仍不做逐像素对比**。文字中的“目视通过”指人工查看证据 PNG。
5. **未验证标记**：文中「未验证/待实测」= 没有运行时或像素证据；「待 Lead 核实」= 来自任务书或二手摘要但未在本阶段证据文件中直接闭环。G8 全量数字已由 -08 执行并回填（见 §9）。

### 0.2 结论摘要

| # | 结论 | 关键证据 |
|---|---|---|
| 1 | 冬季树冠从“保留 10% 随机实例”改为 **0**：44 个 Canopy blob 全隐藏，叶卡 0，冬季为纯树干+裸枝，**不再有悬空树冠球** | isle_season.gd:55-56；selftest 断言 canopy hidden==count；p81_02 四视图截图 |
| 2 | 树顶红梅（P8 的 WinterPlum，7 个枝轴端点 + ±0.32 m 抖动）**整体删除**；冬季红花改为**屋前草坪 5 朵地栽花**，仅冬季随权重渐显 | main.gd 删除 WinterPlum；world.gd winter_bloom；selftest 断言冬季可见/夏季隐藏 |
| 3 | 新增 **5 个冬季专用裸枝栖点**（kind=`winter_branch`，位在真实枝面），仅冬季启用；原 6 个树冠球面栖点在冬季**门控关闭**，避免海鸥悬空 | world.gd 栖点表；fx.gd 季节门控；probe_p81_tree_bird 149/0 |
| 4 | 季节切换**不传送**、**不残留预约**：驱逐走 `_begin_takeoff`（从当前位置起飞），失效路径改用 `_enter_fly_inplace`，预约由 `_release_perch` 清理 | fx.gd:2538-2559、:3196-3220；probe 断言 teleports 不增、season_evictions 增加 |
| 5 | 冬季白化与降雪积雪**分离**：季节白化走 `g_winter`，降雪走 `g_weather`；室外按材质接收系数渐进白化，**室内一层/阁楼完全豁免**（像素差 0.0000%） | toon.gdshader indoor_mask；-03 G3 13 项全 PASS |
| 6 | 天气类型 **13 → 12**（windy 并入 strong_wind），四季权重换为**澎湖 2023–2025 观测小时占比**，自动雪权重归零、旧存档自动迁移 | isle_weather.gd:57-64；probe_p8_weather 3145/0；静态校验 54/0 |
| 7 | 强风视觉三件套上线：落叶风场输运（冬季门控）、萤火虫三通道抑制（强风约 1/12 而非全灭）、秋千受迫摆（顺风偏摆+弹簧阻尼+阵风包络）；帧时间 **+0.012 ms** 通过，CPU 侧 +1.93 ms 如实披露 | probe_p81_wind 117/0；REPORT_p81_05 |
| 8 | 照明改为 **16 槽解析光双池**（室外 10 + 室内 6），五档预算 10/11/12/14/16；壁炉/吊灯/台灯/落地灯/门廊灯/窗灯/码头灯/船灯全部接入；q2 性能最大 **+0.60 ms**、draw +2、node +2、VRAM ±0 | -06 REPORT；probe_p81_lights 147/0；L1–L8 全 PASS |
| 9 | 日期时间编辑改为**五列原生滚轮**（组件 841 行），权威时钟仍是 `main.gd::_sim_seconds`；阶段一无头 82/0，阶段二窗口端到端 **80 pass / 2 warn / 0 fail** | -07 两阶段报告；UI1–UI10 表 |
| 10 | 遗留集中在三类：P8 既有壁炉被烟囱遮挡（P8.2 几何修）、q0 FPS 门在漂移机器上不可判定、滚轮 UI10 帧时间无法证明（U-02） | §6.6、§12 |
| 11 | **发布包构建缺陷已修复**：main.gd:26 preload 的 `tools/scale_debug_overlay.gd` 被导出过滤 `tools/*` 排除，自 P7-V3.2（fdefa40 引入该 preload）起所有导出构建 main.gd 解析失败、发布 exe 完全不可用；-08 将文件移入 `scripts/` 并更新引用，未改功能与导出过滤。旧 P7-V3.1 包（构建早于该 preload）可正常启动并自测 53/53 | 572af3d；发布 exe `--headless -- --selftest` 73/73；§10 D14 |

---

## §1 基线与阶段总览

### 1.1 起点与终点

| 项 | 值 |
|---|---|
| 起点 | tag **p8-weather-seasons-freeze-20261022** = commit **ae1c29d**（P8 冻结） |
| 工作分支 | **p81-integration** |
| 当前 HEAD | **6de37c4**（-08 构建修复 572af3d + .uid 补交；本轮文档提交前最后一次代码提交） |
| 冻结后提交数 | **11**：8 个功能/计划提交（f9cc8b3 → 00ff6c1，含 -01 计划文档）+ 3 个 -08 提交（572af3d、6de37c4、本轮文档提交） |
| 冻结 tag（-08） | **p81-refinement-freeze-20261022**（指向本轮文档提交；代码冻结点 = **6de37c4**） |
| 发布包 | `发布/休闲小岛幻境.exe` = 117,238,104 B，sha256 `c40376ad2dda1d8eb2e9848ca8a2ce00e4c1a841a03444fa9e9b80ef5d62b668`（详见 §8.3） |

### 1.2 阶段 / commit / tag

| 阶段 | commit | tag | 内容 |
|---|---|---|---|
| P8.1-01 调研与计划 | f9cc8b3 | — | 新增 `docs/P8_1_REFINEMENT_PLAN.md`（13 章，1233 行） |
| P8.1-02 冬季树/栖点/红花 | 07752e2 | p81-02-accepted-20261022 | 冬季完全裸枝、删树顶红梅、5 裸枝栖点、5 朵屋前红花 |
| P8.1-04 天气权重校准 | 285648e | p81-04-accepted-20261022 | 13→12 类、观测权重、旧存档迁移 |
| P8.1-03 冬季白化 | 3add702 | p81-03-accepted-20261022 | 季节白化与积雪分离、室内豁免 |
| P8.1-07 阶段一 滚轮组件 | 024da24 | p81-07-stage1-accepted-20261022 | `ui_datetime_wheel.gd` + HUD 集成 + 无头 probe |
| P8.1-05 强风视觉 | 95263d0 | p81-05-accepted-20261022 | 落叶风场、萤火抑制、秋千受迫摆 |
| P8.1-07 阶段二 端到端 | 0136363 | p81-07-accepted-20261022 | main selftest 注入 + 窗口端到端 UI 验收 |
| P8.1-06 照明 | 00ff6c1 | p81-06-accepted-20261022 | 16 槽双池解析光、家具灯、灯罩 glow |
| P8.1-08 构建修复 | 572af3d | — | 发布包不再 preload 被导出过滤的 `tools/scale_debug_overlay.gd`（移入 `scripts/`），修复导出构建 main.gd 解析失败 |
| P8.1-08 .uid 补交 | 6de37c4 | — | 18 个 P8/P8.1 新增脚本与 shader 的 `.uid` 文件（chore） |
| P8.1-08 全量回归/发布 | 6de37c4（代码冻结） | p81-refinement-freeze-20261022 | 全量回归、截图矩阵、性能、发布包；tag 指向本轮文档提交 |

> 注：-02 与 -04 是两个**独立提交**（07752e2 / 285648e）。`p81-02-accepted-20261022` 曾误指 285648e，已用 `git tag -f` 重建指向 07752e2；以 commit 号为准，见 §10 D16。

### 1.3 变更规模（git numstat，freeze..HEAD）

| commit | 文件与净变更 | shortstat |
|---|---|---|
| f9cc8b3 | docs/P8_1_REFINEMENT_PLAN.md 新增 | 1 file, +1233 |
| 07752e2 | fx.gd、isle_season.gd、main.gd、world.gd、probe_p81_tree_bird.gd（新）、probe_p8_season.gd | 6 files, +696/−114 |
| 285648e | hud.gd、isle_settings.gd、isle_weather.gd、probe_p8_weather.gd | 4 files, +109/−58 |
| 3add702 | main.gd、grass.gdshader、toon.gdshader、probe_p81_whiteness.gd（新） | 4 files, +905/−5 |
| 024da24 | hud.gd、ui_datetime_wheel.gd（新 841）、probe_p81_datetime_wheel.gd（新） | 3 files, +1450/−71 |
| 95263d0 | fx.gd、main.gd、probe_p81_wind.gd（新） | 3 files, +949/−24 |
| 0136363 | ui_datetime_wheel.gd、probe_p81_datetime_wheel_ui.gd（新） | 2 files, +1559/−2 |
| 00ff6c1 | toon.gdshader、grass.gdshader、isle_quality.gd、cottage.gd、isle_house_props.gd、main.gd、probe_p7v2_light.gd、probe_p81_lights.gd（新） | 8 files, +946/−96 |
| 572af3d | isle_scale_figure.gd、main.gd、scale_debug_overlay.gd（tools→scripts 重命名）、probe_scale_shots_p7v32.gd、probe_scale_world.gd | 6 files, +6/−6 |
| 6de37c4 | 18 个 `.uid` 文件（chore） | 18 files, +18/−0 |
| **合计** | **8 个功能/计划提交：23 个文件，+7837 / −360**；-08 代码提交：572af3d 6 files +6/−6、6de37c4 18 files +18/−0 | 含计划文档 1233 行；代码/探针文件 22 个；`.uid` 为 Godot 4.7 资源标识 |

要点：

- 新文件 **7 个代码文件**：`scripts/ui_datetime_wheel.gd`、`tools/probe_p81_tree_bird.gd`、`probe_p81_whiteness.gd`、`probe_p81_wind.gd`、`probe_p81_datetime_wheel.gd`、`probe_p81_datetime_wheel_ui.gd`、`probe_p81_lights.gd`（另有 -01 计划文档）。
- 触摸到的核心运行文件：`main.gd`（合计约 +1416 行改动）、`fx.gd`、`world.gd`、`isle_season.gd`、`isle_weather.gd`、`isle_settings.gd`、`isle_quality.gd`、`cottage.gd`、`isle_house_props.gd`、`hud.gd`、`toon.gdshader`、`grass.gdshader`。
- 冻结探针 `probe_p7v2_light.gd` 的期望预算常量在 -06 发生了契约变更（见 §6.5、§10 D10），经 Lead 裁决后允许。

---

## §2 P8.1-02 冬季裸树、裸枝栖点、屋前红花

### 2.1 问题与根因（P8 遗留）

P8 冬季截图暴露三类可见缺陷，本次调研（P8.1-01）确认根因如下：

1. **悬空残冠**：P8 冬季 `canopy_keep=0.10`，44 个 Canopy blob 按“确定性洗牌后的尾部隐藏”保留 4 个实例（`round(44×0.10)`）。洗牌（`main.gd:918-925`，seed=name+kind）与层/枝没有关联，保留的 4 个实例可能来自高层（y≥9.45，高于树顶 9.30），从任意角度看都是浮在枝干外的球。
2. **树冠仍黄绿**：冬季 `foliage_tint=(0.88,0.78,0.66)` 在 `toon.gdshader:206` 以乘法作用于绿色顶点色，结果是黄绿，而不是“枯色/落净”。
3. **红点漂浮枝梢外**：P8 的 `WinterPlum` 取 7 个**枝轴端点**作锚点（主枝轴端、横枝轴端、秋千横枝轴端），再叠加 ±0.32 m 随机抖动与球半径 0.09–0.14 m；锚点本身在枝轴内部/表面，叠完抖动后中心可离开枝面 0.1–0.4 m，视觉上即“红花悬空”。

### 2.2 实现

| 文件 | 关键锚点 | 改动 |
|---|---|---|
| `scripts/isle_season.gd` | :55（canopy）、:56（cards） | winter `canopy 0.10 → 0.0`；`leafcard_keep` 保持 0.0；注释明确“残冠是随机子集，会悬空” |
| `scripts/world.gd` | :52-54 | `build(parent, include_winter := false)`：**默认 false** 保持旧探针 36 点栖点契约；main 显式传 `true` 得到 41 点 |
| `scripts/world.gd` | :72、:108-111、:1090-1122 | `_winter_blooms(root)` 建 `WinterBloomStems` / `WinterBloomHeads` 两个 5 实例 MultiMesh（同 Transform） |
| `scripts/world.gd` | :3806-3838 | `include_winter` 时追加 5 个 `winter_branch` 栖点（坐标/法线/朝向/坡角硬编码，无 rng），radius 0.55 → slots 1 |
| `scripts/main.gd` | :96、:644 | `_winter_bloom` 字段；`_build_world` 从 world 字典取 `winter_bloom` |
| `scripts/main.gd` | :1054-1074 | 冬季红花驱动：`bloom = clamp((winter_w−0.25)/0.55, 0, 1)`，`show = bloom>0.03`；stems/heads 共用同一 Transform（只写花头会变悬空花）；缩放随 bloom 渐显 |
| `scripts/main.gd` | :3877-3938（selftest） | 冬季断言：`canopy_keep≤0.001`、冬季花床全 0、落叶不发射、winter bloom heads 冬季可见；跳夏季后隐藏且 `WinterPlum` 节点不存在；栖点门控双向断言（冬季 winter_branch 开 / tree_branch 关，夏季相反） |
| `scripts/main.gd` | :6570-6600 附近 | `--p81treebird` 截图模式，输出到独立目录 `开发产物/p81/evidence/p81_02/`（绝不写 P8 冻结目录） |
| `scripts/fx.gd` | :1642-1645、:1876-1879、:2270-2278、:2595、:2801、:3100-3108、:3183/3202、:3260-3286 | 新增 `_winter_perch_open / _leafy_perch_open / _teleports_total / _season_evictions`；`_perch_eligible` 按 kind 做季节门控（winter_branch 需 winter≥0.60；tree_branch 需 canopy_keep≥0.40；reason=`season_off`）；`_update_perch_evictions` 泛化（非 eligible → `_begin_takeoff` 不传送）；新增 `_enter_fly_inplace` 替代 `_update_landing` / `_check_perch_validity` 中的 `_set_fly`（原路径会瞬移）；`set_season_gate()` 测试钩子；`debug_perch_stats` 增 teleports/season_evictions/winter_open/leafy_open |
| `tools/probe_p81_tree_bird.gd` | 新增 381 行 | 树/红花/栖点门控/无传送/预约清理/季节连续性专项探针 149 条 |
| `tools/probe_p8_season.gd` | +4/−3 | 原冬季红梅断言改写为“WinterPlum 不存在 + 冬季 canopy 全隐藏” |

### 2.3 冬季树目标结构

- **保留**：树干 5 段（`world.gd:1720-1724`）、5 条根爪、4 条主枝、秋千专用粗枝与两条横枝、每条主枝 2–3 条次生细枝、秋千绳/座；这些都是独立 `MeshInstance3D + CylinderMesh`，几何完全不重建。
- **隐藏**：Canopy（44 blob）、LeafCards（80 quad）、BgTreeCanopy（4 棵背景树共 32 blob）、Bushes 的冬季保留量全部压到 0；冬季树 = 树干 + 裸枝 + 枝上积雪（积雪来自天气 `g_weather.w`，与季节白化 `g_winter` 分离）。
- **门控**：原 6 个 `tree_branch` 栖点位于树冠层 2/3 的球面附近（BigTree 局部 y≈10.6–12.4，世界 y≈18.5–20.3），冬季必须关闭，由 5 个裸枝栖点替代。

### 2.4 5 个冬季裸枝栖点（世界坐标 = BigTree base + 局部坐标；base = (−10.9, 7.8677, 4.2)）

| # | BigTree 局部 (x, y, z) | 世界坐标 (x, y, z) | 枝面法线 | 坡角 | facing（水平朝向） |
|---|---|---|---|---|---|
| 0 | (1.248, 5.827, 0.015) | (−9.652, 13.695, 4.215) | (−0.015, 1.000, 0.000) | 0.9° | (1.0, 0, 0) |
| 1 | (2.818, 5.665, 0.833) | (−8.082, 13.533, 5.033) | (−0.337, 0.935, −0.112) | 20.8° | (0.949, 0, 0.316) |
| 2 | (−2.009, 6.382, 0.437) | (−12.909, 14.250, 4.637) | (0.411, 0.908, −0.077) | 24.7° | (−0.983, 0, 0.184) |
| 3 | (0.975, 7.155, 2.328) | (−9.925, 15.023, 6.528) | (−0.117, 0.901, −0.418) | 25.7° | (0.271, 0, 0.963) |
| 4 | (−0.777, 7.610, 2.267) | (−11.677, 15.478, 6.467) | (0.164, 0.926, −0.339) | 22.1° | (−0.436, 0, 0.900) |

- 5 点均取自主枝/横枝圆柱表面（解析求得），并避开秋千绳区（局部 x≈2.6–3.4）。
- `radius 0.55` → 默认 `slots = clampi(floor(0.55/0.62),1,6) = 1`，即每个栖点 1 只鸟；世界栖点总数 16 → 21（main 下 41）。
- 季节门控阈值：`main._eco_ctx` 增加 `season = {"winter": 冬季权重, "canopy_keep": 当前树冠保留量}`；`fx._perch_eligible`：`winter_branch` 需 winter ≥ 0.60（约 12 月下旬—2 月上旬），`tree_branch` 需 canopy_keep ≥ 0.40（春/夏/秋可用，冬季关）。
- **不传送/不残留**：季节门控驱逐走 `_begin_takeoff`（`from_p = node.position`）、失效路径走 `_enter_fly_inplace`、预约由 `_release_perch` 清理；禁止在季节切换时调用 `set_perches()/setup()/_reseat_all()`（会 `_set_fly` 传送），该负向契约由探针覆盖。

### 2.5 屋前 5 朵冬季红花

| # | 世界 XZ | 说明 |
|---|---|---|
| 0 | (0.123, 8.716) | 屋前草坪；`_in_porch` 外、离主路缘 ≥0.88 m、离门 3.6–5.7 m |
| 1 | (1.285, 9.089) | 同上 |
| 2 | (1.968, 8.250) | 同上 |
| 3 | (1.014, 9.906) | 同上 |
| 4 | (−0.309, 9.687) | 同上 |

- 落点 y = `world._h(x, z) − 0.01`（运行时取地形高度；静态复算约 7.34–7.52，属未运行时验证）。
- 花体：`_flower_stem_mesh(3, 0.62, 0.06)` + `_poppy_head_mesh(Color("e14a3f"), 0.62, 0.06)`；材质 `toon_material(WHITE, vertex_color, bands 3, rim 0.04, outline 0)`，花头颜色烘焙在网格里（不依赖季节 tint，避免冬季被染黄绿）。
- 缩放 1.30–1.60（比常规 Poppy 更大），原因是冬季深色草地对比度不足；这是 -02 视觉打磨后的取值（`world.gd:1107-1108` 注释）。
- 节点名 `WinterBloomStems / WinterBloomHeads`（**不以 Flower 开头**）：`main._setup_season_visuals` 用 `find_children("Flower*")` 自动接管花节点，命名规避后由 `_apply_season_visuals` 专用代码驱动。
- 显隐：`bloom = clamp((winter_w−0.25)/0.55, 0, 1)`，`show = bloom>0.03`；12/1 起冬权重 0.5，故 12 月上旬即出现并渐显，春夏秋隐藏。花床与春夏秋花系统不受影响（冬季花床仍全收）。

### 2.6 测试证据

| 测试 | 命令（简） | 结果 |
|---|---|---|
| 主自测 | `Godot --headless --path . -- --selftest` | **73/73 passed**（EXIT=0） |
| P8.1 树/鸟专项 | `--headless --script res://tools/probe_p81_tree_bird.gd` | **PASS pass=149 fail=0** |
| P8 季节回归 | `--headless --script res://tools/probe_p8_season.gd` | **PASS**（checks=114 fail=0） |
| P7 栖点契约 | `--headless --script res://tools/probe_p7v2_perch.gd` | **PASS pass=265 fail=0**（36 点契约未被默认值破坏） |
| P7 海鸥回归 | `--headless --script res://tools/probe_p7v2_bird.gd` | **PASS pass=681 fail=0** |

### 2.7 截图证据（`开发产物/p81/evidence/p81_02/`，10 张 1600×900（-08 重拍））

| 文件 | 内容 | 目视结论 |
|---|---|---|
| p81_winter_wide.png | 冬季全岛 | 大树/背景树纯裸枝、无残冠、无浮空球；屋前红花可见 |
| p81_winter_tree.png | 同 P8 大树机位 | 纯裸枝，可与春夏秋对照 |
| p81_winter_tree_close.png | 裸枝近景 | 裸枝 + 秋千完整，无浮空叶团/球 |
| p81_winter_bloom_front.png | 屋前草坪 | 5 朵红花地栽可见，不在树上 |
| spring/summer/autumn × wide/tree（6 张） | 对照 | 树冠完整（canopy 0.96/1.00/0.94、cards 0.86/1.00/1.00） |

> 限制：-08 已重拍为 **1600×900**；仍不与 P8 冻结 46 张做逐像素对比（U45）。海鸥是否恰好停在裸枝是随机的，不作“栖点被使用”的证据（该项由 probe_p81_tree_bird 的 FXGATE 组承担）。

### 2.8 G2 验收结论

| G2 条件（计划 §11.2） | 结果 | 依据 |
|---|---|---|
| 冬季四视图无浮空残冠、无树顶红花 | **PASS** | 四张冬季截图目视 |
| 春夏秋树冠与 P8 一致（diff<1%） | **PASS（参数级）** | canopy 0.96/1.00/0.94、cards 0.86/1.00/1.00 与 P8 相同；像素 diff 未做（分辨率不同） |
| 海鸥冬季只落 5 个新点 | **PASS（门控级）** | selftest + probe：冬季 winter_branch eligible、tree_branch season_off |
| 切季不瞬移、不残留预约 | **PASS** | probe teleports/season_evictions/预约清理断言 |
| P7 36 点契约仍通过 | **PASS** | probe_p7v2_perch 265/0 |
| 屋前 5 朵红花（不在树顶） | **PASS** | 截图 + selftest 冬季可见/夏季隐藏 |

### 2.9 偏差与未验证

| 项 | 偏差/取舍 | 理由 |
|---|---|---|
| world.build 签名 | 新增第 2 参 `include_winter`，**默认 false** | 保 P7-V2 探针 36 点契约；main 显式 true 得 41 个世界栖点（+5 冬季） |
| 截图机位与输出名 | 删除原 _p8_camera_winter_plum，输出改独立目录 | 红梅已删，原机位无对象；且 -02 禁止写 P8 冻结目录 |
| 冬季红花尺寸 | 花头 0.62 m、缩放 1.30–1.60 | 深色冬草上的可读性，刻意艺术取舍 |

未验证（详见 §12）：红花逐朵地形高度/坡度/穿模、海鸥自然（非门控）落到新点的概率、裸枝粗细观感、跨季长程 soak。

---

## §3 P8.1-03 冬季白化与室内豁免

### 3.1 目标与方案

- **季节白化（winter_whiteness）与天气降雪积雪（snow_cover）严格分离**：季节白化由冬季权重驱动 `g_winter`；降雪/积雪仍由 `g_weather` 驱动，两者不共用变量。
- 室外按材质接收系数渐进白化：地形、树冠/叶卡、灌木、屋顶、灯塔、码头、树干裸枝、草各自有 `(snow, frost, ground_tint, foliage_desat)`；`self_lit`（灯罩/炉火/窗光）、动态对象、花与冬季红花完全豁免。
- 室内（房屋一层 + 阁楼）完全不受影响：`toon.gdshader` 的 `indoor_mask()` 按房屋局部体积 + 屋顶斜面判定，白化/积雪乘 `(1−indoor)`；**与相机位置无关**。
- 新增 global uniform：`g_winter`、`g_house=(origin.xyz, cos_yaw)`、`g_house2=(sin_yaw, half_x, half_z, floor_local)`、`g_roof=(ridge_y, tan_pitch, under_margin, first_floor_top)`。
- **U11 澄清**：计划书 U11 质疑 `snow_line=1.05–3.20` 的语义；-03 确认该区间是**海平面/岸线方向的低海拔淡出**（世界 y 绝对高度，用于避免海面/沙滩被雪盖白），**不是岛面高程白化阈值**。因此季节白化另立 `g_winter` 通道，不复用 `snow_line`，避免“高处反而更白/低处不白”的语义冲突。

### 3.2 改动清单（-03 提交 3add702；行号为该提交时点）

| 文件 | numstat | 关键锚点 | 内容 |
|---|---|---|---|
| `scripts/main.gd` | +485/−3 | :562-572 uniform 注册、:1238-1262 写 g_house/g_house2/g_roof/g_winter、:1264 起 _tag_winter_materials、:704 调用、:1824-1836 _eco_ctx、:6744-6760 ON/OFF 对照、:6853+ --p81snow | 4 个 uniform；季节权重→g_winter；启动遍历约 990 个 GeometryInstance/217 材质打 winter_recv 接收系数；证据模式 --p81snow / --p81whiteness |
| `shaders/toon.gdshader` | +70/−1 | :71-79 uniform 声明、:105 winter_recv、:201-221 indoor_mask()、:254-273 白化块、:336-341 积雪 max(降雪,季节)×(1−indoor) | 白化/结霜/地色/叶色去饱和 + 室内 mask + 积雪叠加 |
| `shaders/grass.gdshader` | +43/−1 | :37-38/48/76、:111-122 | 草的白化/地色/去饱和接收 |
| `tools/probe_p81_whiteness.gd` | 新增 307 | — | 白化专项探针 34 条 |
| 其他 | — | — | world/isle_house_props/cottage/isle_quality 的材质标记（本阶段实现） |

> 口径差异：-03 证据 README 记 main.gd +488、toon +71、grass +44、probe 269 行；git numstat 为 +485/−3、+70/−1、+43/−1、probe 新 307。本文采用 numstat。

### 3.3 材质接收系数（-03 证据 README 实测表）

| 材质组 | 数量 | (snow, frost, ground_tint, foliage_desat) |
|---|---|---|
| `self_lit`（灯罩/炉火/窗光） | 47 | (0, 0, 0, 0) |
| 地形 | — | (0.90, 0.55, 1.00, 0.00) |
| 树冠/叶卡/背景冠 | 3 | (0.30, 0.45, 0.00, 0.85) |
| 屋顶 | 3 | (0.95, 0.35, 0.35, 0) |
| 灯塔 | 96 | (0.90, 0.45, 0.60, 0) |
| 大树树干裸枝 | — | (0.50, 0.30, 0.30, 0) |
| 动态对象 | 182 | (0, 0, 0, 0) |
| 花 / WinterBloom | 13 | (0, 0, 0, 0) |
| 草 | — | (0.90, 0, 0.55, 0.85) |
| 默认 toon | 966 | (0.85, 0.35, 0, 0) |

### 3.4 G3 验收（13 项，全 PASS）

| 编号 | 条件 | 实测 |
|---|---|---|
| W1 白化可见 | 地面裁剪区均值（0–255）：夏季 126.9 → 冬季 142.8 / 189.6 / 190.8 | PASS |
| W1 曲线 | 2026-12-01 whiteness 0.2651（crop 142.8）；2027-01-15 1.0（189.6）；02-15 1.0（190.8）；03-05 0（112.8，winter 权重 0.2962→0） | PASS |
| W5 手动大雪 | 独立叠加 type=heavy_snow snow=0.95 snow_depth=0.61 whiteness=1.0 | PASS |
| W6 窗外看室内 | 窗外白化显著：44.9786%（冬）/ 41.5265%（雪） | PASS |
| W7 一层严格无窗 | 白天 0.0000% / 夜晚 0.0056%（冬）/ 0.0065%（手动大雪） | PASS |
| W8 阁楼 | 0.0000% | PASS |
| W9 冬雨湿暗同日共存 | wet=0.465（shader 中 wet 先于冬白化） | PASS |
| W10 五档可见 | q0–q4 白化均可辨识；clear crop 均值 191.9/192.7/190.3/191.5/192.9；snow=153.0/156.5/157.2/159.2/160.8 | PASS |
| W11 截图 | 规定 10 张实拍，实际 46 clear + 25 snow + 9 diff 覆盖 | PASS |
| W12 回归 | P8 全 probe PASS（season 114、weather 3145、ecology 41、moon 233、calendar 2672） | PASS |
| W13 性能 | q2 clear Δ = **−0.01 ms**（6.705 vs 6.695）；objects 1928、draw_calls 1838、VRAM 272.5 MB 与同 HEAD 副本一致 | PASS |
| W2–W4 | 季节曲线/边界/材质分类细节见证据 README 与探针 34 条 | PASS |

> 像素差口径统一：**逐通道最大差 >8/255（Pillow）、全帧 1600×900**；噪声基线 **0.0053%**（-03 验收时 ON/ON2/OFF/ON3 四联测得），室内夜晚 0.0056%/0.0065% 与噪声同量级 → G3 判 PASS；室内白天/阁楼 0.0000% 与窗外 44.9786%/41.5265% 差异显著。
>
> 性能口径：P8 冻结 clear q2 的 5.56 ms 是另一时段基线，同 HEAD 本机为 6.69–6.72（漂移 +1.13）；因此只与同机 HEAD 导出副本对比（Δ −0.01 ms），另 heavy_snow Δ +0.145 ms。

### 3.5 已知限制（-03 证据 README，12 条摘要）

shader 逐片元耗时未验证；极端贴墙机位（indoor_mask 硬阶跃）未验证；玻璃/金属霜雪未实现；屋顶色相淡粉白待美术确认；阁楼灯焰 halo 部分验证；分辨率可移植未验证（全部 1600×900）；极端天气截图未覆盖；[P81W] tagged 计数受限；兼容渲染器未验证；冬季树冠几何非本任务（由 -02 负责）；室内家具朝上面整体豁免为设计取舍；门廊/屋檐判室外有雪为设计取舍。

---

## §4 P8.1-04 天气权重校准（13 → 12 类）

### 4.1 目标

- 删除 windy（13 → 12 类，windy 并入 strong_wind 的强风表达；日常轻风改由连续风力参数 `wind_strength` 表达）。
- 四季权重换成**澎湖 2023–2025 再分析观测小时占比 ×100**（每季和 = 100）；自动雪权重 = 0（三年 ERA5 snowfall 全 0、ISD 马公站无雪码、Tmin 11.6 ℃），雪保留为冬季**手动**选项（`type_legal` 的 winter_w≥0.60 仍成立）。
- `strong_wind` 参数微调；旧存档（含 windy）加载迁移到 strong_wind；自动模式雪 = 0、手动保留。

### 4.2 改动清单（-04 提交 285648e）

| 文件 | 关键锚点 | 内容 |
|---|---|---|
| `scripts/isle_weather.gd` | :24-31 TYPE_ORDER、:33-40 TYPE_LABELS、:41-56 TYPE_PARAMS、:57-64 SEASON_WEIGHTS、:134 season_type_weights | 12 类顺序；删 windy 参数；`strong_wind: cloud 0.48→0.55、wind 0.88→0.92、storm 0.08→0.10`；权重表换观测值 |
| `scripts/isle_settings.gd` | :72-78 WEATHER_TYPES、:264+ sanitize | 12 类；新增 `WEATHER_TYPE_ALIASES={windy:strong_wind}`，sanitize 先迁移后校验（旧存档不回落 clear） |
| `scripts/hud.gd` | :111、:583 _build_weather_console | 手动面板 12 类（注释：最多 11 按钮 4 列 3 行，6 列会溢出）；动态面板按类型生成 |
| `tools/probe_p8_weather.gd` | :25 起 _init、:75/85/96/98/106、:146-161、:180、:400、:447 | 断言改为 12 类精确顺序/权重和/strong_wind 参数/自动无雪扫描；积雪测试改手动注入 |

### 4.3 12 类与四季权重（`isle_weather.gd:57-64` 实际值，数组顺序 = TYPE_ORDER，每季和 = 100）

| 季节 | clear | partly | overcast | strong_wind | light_rain | mid_rain | heavy_rain | light_snow | mid_snow | heavy_snow | thunder | typhoon |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| spring | 32.82 | 23.48 | 27.78 | 3.15 | 11.29 | 1.16 | 0.0 | 0.0 | 0.0 | 0.0 | 0.32 | 0.0 |
| summer | 19.57 | 19.93 | 35.82 | 0.35 | 18.37 | 1.45 | 0.21 | 0.0 | 0.0 | 0.0 | 2.43 | 1.87 |
| autumn | 37.31 | 20.34 | 18.09 | 11.83 | 8.23 | 0.44 | 0.13 | 0.0 | 0.0 | 0.0 | 0.21 | 3.42 |
| winter | 34.03 | 23.52 | 19.07 | 18.68 | 4.61 | 0.09 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |

> 自动雪列全 0；手动模式冬季仍可选三种雪。台风只出现在夏/秋，雷暴只保留春/夏/秋的观测残量（冬季 0）。

### 4.4 测试证据

| 测试 | 命令 | 结果 |
|---|---|---|
| 天气探针 | `--headless --script res://tools/probe_p8_weather.gd` | **PASS**，`[SUMMARY] checks=3145 fail=0 elapsed_ms=661` |
| 静态校验 | `python 开发产物/p81/weather/check_p81_04_static.py` | **checks=54 fail=0 / PASS / EXIT=0**（本机复跑确认） |
| 主自测 | `--selftest` | 73/73（-04 时点口径，沿用 -02/-03 同一 HEAD 回归） |

静态校验 54 项覆盖：TYPE_ORDER 长度 12、无 windy、strong_wind 索引 3、12 类精确顺序、LABELS/PARAMS key 一致、SEASON_WEIGHTS 四季各 12 维且和=100 等。

已知历史瑕疵（P8 起即存在，非 -04 引入）：`probe_p8_weather.gd:472 _run_step_independence` 在 headless 下有 1 条非致命 `SCRIPT ERROR（Invalid call. Nonexistent 'String' constructor.）`，不影响 PASS；-08 复制日志时需注明，避免误读为回归。

### 4.5 G4 验收结论

| G4 条件 | 结果 |
|---|---|
| 主自测全过 | PASS（73/73） |
| probe_p8_weather 全过 | PASS（3145/0） |
| 旧存档（含 windy）迁移到 strong_wind | 由 `isle_settings.sanitize_weather_type` 实现，静态校验 + probe 覆盖；窗口加载旧 cfg 实测未做（待 Lead 核实） |
| HUD 12 类 | 静态校验 + probe 覆盖；HUD 视觉见 -08 窗口截图 |
| 自动模式冬季无雪 | 权重表全 0 + 静态校验；长程抽样未跑（U 类） |

---

## §5 P8.1-05 强风视觉（落叶 / 萤火 / 秋千）

### 5.1 目标

1. **落叶风场输运**：强风时落叶不再垂直下落，而是顺风横向输运 + 自旋 + 抬高；冬季风场门控（裸树期不产叶）。
2. **萤火虫三通道抑制**：风、风暴、降水三个通道独立抑制萤火；强风下不“全灭”而是微弱残留。
3. **秋千受迫摆**：顺风偏摆 + 弹簧阻尼 + 阵风包络，替代原来的纯正弦空摆。

### 5.2 实现

| 文件 | numstat | 关键行（-05 报告口径） | 内容 |
|---|---|---|---|
| `scripts/main.gd` | +419/−17 | 纯函数层 :1355-1446（wind_gust :1368、wind_leaf_params :1372、wind_leaf_gate :1391、wind_leaf_tint :1395、firefly_wind_ratio :1400、firefly_wind_activity :1407、swing_wind_targets :1419、swing_idle_rot :1437、swing_spring_step :1441）、落叶运行时 :1499-1534、冬季叶色/门控 :1002-1021、萤火 :2029-2073、秋千 :4377-4396、证据 harness :6181-6390、帧采样 :5127-5143 | 纯函数层 + 运行时接线 + 证据模式 |
| `scripts/fx.gd` | +16/−7 | leaves :897-940（lifetime 9→5.0、preprocess 3.0、AABB(−18,−14,−18/36,20,36)、spread 50、color_ramp offsets [0,0.12,0.55,1.0] alpha [0,0.95,0.30,0]）；fireflies :815-880 返回 pm | 粒子参数与返回句柄 |
| `tools/probe_p81_wind.gd` | 新增 514 | B0 + F1–F10 + S1–S6 共 117 条 | 强风视觉专项探针 |

> 口径：-05 REPORT 摘要记 main.gd +436、fx.gd +23；git numstat 为 +419/−17、+16/−7。本文用 numstat。

### 5.3 F/S 实测摘要（全部 PASS，117/0）

| 编号 | 结论与数字 |
|---|---|
| F1 静风落叶 | tr=0；direction.y=0.9609；gravity.y=−0.568；lifetime 5 s |
| F2 强风输运 | tr=smoothstep(0.40,0.95,0.92)=0.991；lateral=1.6+1.8tr；grav_side=0.55+2.0tr；gravity.y −0.568→−1.980，自旋 160→398，倾角>69° |
| F3 输运不瞬移 | 只改 direction，不改位置 |
| F4 冬季门控 | `wind_leaf_gate=clamp(1−winter_w×1.35,0,1)`；w=0.74→0.001，w=1→0；`emitting=(leaf_fall×gate)>0.03`；冬季截图 leaf_emit=false leaf_ratio=0.00 |
| F5 无新增节点 | 240 帧节点 1533→1533，drawpass 0 |
| F6 萤火抑制 | clear 0.970 / strong 0.081（≈1/12）；`ratio=base_i×windf×stormf×precf` |
| F7 组合抑制 | 小雨 0.4300；强风+小雨 0.0359；雷暴/台风 0 |
| F8 低比活性 | r=1 寿命 9；r=0.1 寿命 5.0 / 范围 3.9 / 速度 0.505 / 亮度 0.595×；r=0 关发射 |
| F9 不 restart | 120 帧无 restart |
| F10 legacy 开关 | 有效（用于 A/B 性能对照） |
| S1 空摆一致性 | 与旧实现逐字符一致，逐帧误差 0.00000000 |
| S2 偏摆范围 | roll clamp[−0.18,0.42]；均值 0.182，极值 0.296/0.036；座面高 下风 9.301 / 平衡 8.632 / 上风 8.213 m |
| S3 换向平稳 | 最大单帧 0.0038 rad；5 s 到 −0.180 |
| S4 阵风包络 | `gust=1+(0.22 sin1.13t+0.13 sin(2.7t+1.2))tr`；`acc=(2.2w+0.8tr)gust` |
| S5 几何不变 | 吊点 (−7.9, 13.41769, 4.2)、绳长 5.216、座椅 1.12×0.07×0.46 不变 |
| S6 极端风 clamp | 台风级 clamp；pitch[−0.62,0.62] |

### 5.4 性能（q2、vsync off、秋 2026-10-20 22:00、strong_wind、大树机位、180 帧×2 轮）

| 版本 | frame_ms | 说明 |
|---|---|---|
| new（-05 实现） | 5.684 / 5.674（均值 5.679） | 强风视觉开启 |
| legacy（F10 开关） | 5.689 / 5.645（均值 5.667） | 旧版行为 |
| 差值 | **+0.012 ms**（门 ≤ +0.3 ms → PASS） | |
| CPU 侧 | new 9.615 ms vs legacy 7.681 ms = **+1.93 ms**（两轮波动 ±1.5–2.3 ms） | 如实披露；未 profile 到具体函数，建议后续 4 Hz 节流 |

### 5.5 口径裁决（Lead 裁决，已写入 -05 报告 §10）

| 编号 | 裁决 |
|---|---|
| D1（F6） | 维持 1/12（0.081 vs 0.970）；验收门改为「amount_ratio_strong ≤ 1/5 且 ≥ 1/60（不得完全消失）且 clear 仍有可见萤火」；计划书 1/5 是设计目标而非验收门 |
| D2（F8/F7） | 按实现口径：emitting=ratio>0.02 + 寿命缩短（r=0 时 4 s）+ 收缩范围/降速/压暗，保 F7 强风+小雨 0.0359 微弱残留；F8 门 = 「ratio<0.05 时不得以原寿命/原范围继续发射（寿命≤5 s 或范围≤35%）」；字面 0.25 阈值因与 F7 冲突被否决 |
| U5 | 关闭：clear-vs-strong 绝对帧差不再单独测，用 new-vs-legacy 净成本（+0.012 ms）+ 绝对 5.68 ms（q2）口径 |
| U6 | 由 -08 全量矩阵统一重拍销账 |

### 5.6 G5 与未验证

| G5 条件 | 结果 |
|---|---|
| F1–F10、S1–S6 全过 | PASS（probe_p81_wind 117/0） |
| clear vs strong_wind 截图各 2 张 | PASS（12 张证据：leaf_clear/strong、wide_autumn、swing_clear/downwind/upwind/dir_shift_mid/end、firefly_clear/strong、winter_bare/wide） |
| 无瞬移 | PASS（F3/S2/S3） |
| q2 ≤ +0.3 ms | PASS（+0.012 ms） |

未验证：CPU +1.93 ms 的来源与是否影响低端机；萤火“可见残留”的观感阈值（只有 ratio 数字）；秋千在台风级风速下的手感（clamp 后未做主观评审）。

---

## §6 P8.1-06 壁炉与室内外照明（16 槽双池）

### 6.1 目标与方案选择

- 目标：让壁炉、台灯、落地灯、吊灯、门廊灯、窗光、码头灯、船灯产生**真实局部照明**，夜间/室内可读；同时不破坏 P8/P8.1 的帧预算。
- 方案 A（真实 `Light3D` + 阴影）在 task-11 原型实测：draw **+286**、VRAM **+33~51 MB**、帧时间 **+0.44~0.72 ms**，超门一个数量级，**不采用**。
- 采用**方案 B**：解析光槽 12 → **16**，室内外**双池**（室外 `g_l0..g_l9`、室内 `g_l10..g_l15`），shader 内按 `indoor_mask` 选池；灯罩由“自发光材质”改为“非自发光 + glow + 灯色”；补 4 盏家具灯。

### 6.2 实现

| 文件 | numstat | 关键锚点 | 内容 |
|---|---|---|---|
| `shaders/toon.gdshader` | +24/−3 | :21-25 双池契约 + `g_light_indoor`；:50-57 g_l12..g_l15；:359-380 选池 | 室外片元只吃室外池、室内只吃室内池；与相机无关 |
| `shaders/grass.gdshader` | +11/−4 | g_l8/g_l9、夜间循环 8→10 槽、灯色乘 lc.rgb | 草受近场灯影响 |
| `scripts/isle_quality.gd` | +30/−8 | :119-122 `LIGHT_INDOOR_BUDGET=[3,3,3,4,6]`、:150-160 `light_indoor_budget()/light_split()`、五档 `light_budget`=10/11/12/14/16 | 预算与拆分 |
| `scripts/cottage.gd` | +52/−15 | :127-143 新增 8 个世界坐标（含 4 盏家具灯）；:144-156 light_sources 10 条；:353 门廊灯罩 `self_lit=false glow=1.0`；:1623-1624/:1764-1765 两层吊灯罩+独立灯泡 | 小屋灯清单 |
| `scripts/isle_house_props.gd` | +12/−3 | :267-280 `_shade_cyl`；:845/:865 台灯/落地灯罩 `self_lit=false glow=0.55` | 家具灯灯罩 |
| `scripts/main.gd` | +220/−60 | :210-215 `_lights_outdoor/_lights_indoor/_boat_light_gain`；:527-530 注册 `g_light_indoor`；:1954-1993 `_update_lighting` 双池写槽；:4140 `_light_rank_of`；:4188-4230 `_compute_light_pools`（船灯替换窗光槽 +0.4 s 淡入淡出）；:4336 `debug_light_state`；:5644-5650 兜底；:5809 性能面板 lights 改实际激活数 | 双池调度 |
| `tools/probe_p7v2_light.gd` | +5/−3 | EXP_BUDGET 10/11/12/14/16（旧值注释保留）；:192-193/:295 active、g_light_count 上限 16 | 契约随实现更新 |
| `tools/probe_p81_lights.gd` | 新增 592 | `--mode=checks` 147 项；`--mode=shots` 27 张 | -06 专项探针 |

**灯清单（18 条 light_sources；world 8 + cottage 10）**

| 灯 | 世界坐标 / energy / range / 颜色 | 池 / priority / 档位 |
|---|---|---|
| street_lamp ×6 | 1.35 / 7.5 / (1.0,0.76,0.45) | 室外 / 1000 / q0–q4 |
| lighthouse | (−17.00,22.01,9.00) 1.65 / 17 / (1.0,0.82,0.55) | 室外 / 900 / 恒在 |
| dock | (27.81,2.27,18.97) 1.40 / 8 | 室外 / 800 / q1+ |
| porch_lantern | (2.14,10.00,3.75) 1.20 / 5.2 | 室外 / 700 / q2+ |
| window_glow | (1.92,9.98,3.03) 0.70 / 4.2 | 室外 / 660 / q3+ |
| fireplace | (−1.98,9.05,−2.15) 1.50 / 5 / (1.0,0.52,0.22) | 室内 / 900 / 恒在 |
| chandelier 一层 | (2.42,10.30,−0.26) 1.55 / 5.4 | 室内 / 850 / 恒在 |
| table_lamp 一层 | (0.22,9.71,−3.14) 0.85 / 3.4 | 室内 / 800 / 恒在 |
| floor_lamp | (−1.49,9.79,2.57) 1.30 / 4.4 | 室内 / 750 / q3+ |
| attic_chandelier | (1.26,13.23,0.20) 1.45 / 4.6 | 室内 / 700 / q4 |
| attic_chandelier2 | (−1.70,12.01,−1.92) 1.35 / 4.0 | 室内 / 650 / q4 |
| attic_table_lamp ×2（备选） | (−0.77,12.03,−1.80)/(1.98,12.18,1.70) 0.65 / 3.0 | 室内 / 600、590 / q4（预算满时未激活） |
| boat lantern | energy 1.30×gain / 6.5 | 室外 / 船可见时替换窗光槽（q3+） |

**五档预算**：q0 10（外 7 / 内 3）、q1 11（8/3）、q2 12（9/3）、q3 14（10/4）、q4 16（10/6）。所有档位至少 10 盏解析光。

**光照公式**：`att=clamp(1-dist/max(range,0.001),0,1)^2`；`ndl=pow(clamp(dot(Nw,L)*0.5+0.5,0,1),1.5)`；`col += base*light_rgb*energy*att*(0.22+0.78*ndl)`；`self_lit>0.5` 走 `col=base*glow` 分支；空槽写 `(0,-999,0,1)`。壁炉闪烁 `fl=1+sin(t*6.7+i*2.1)*0.10+sin(t*11.9+i*1.3)*0.05`（其它灯 0.05/0.025，相位按槽错开）。

### 6.3 L1–L8 验收（全部 PASS，对应 probe_p81_lights 147 条 + 27 张截图）

| 编号 | 条件 | 结果 |
|---|---|---|
| L1 壁炉全档光照 | q0–q4 壁炉均激活并有可见暖光 | PASS |
| L2 家具灯 | 台灯/落地灯/吊灯按档位点亮，灯罩 glow 不破坏 toon 风格 | PASS |
| L3 门廊/窗灯门控 | 门廊 q2+、窗光 q3+ | PASS |
| L4 码头灯 | q1+ 激活 | PASS |
| L5 室内外不串光 | 室内片元只吃室内池、室外只吃室外池 | PASS（shader 选池 + 截图） |
| L6 无灯槽泄漏/NaN | 空槽写哨兵、无 NaN 光斑 | PASS |
| L7 预算与激活一致 | 各档 active 数 = 预算；≤16 | PASS |
| L8 叠加仍生效 | 白化/积雪/湿反与灯光叠加无破图 | PASS（截图 × 27） |

### 6.4 性能（q2、1600×900、VSync off、每场景 3 次取中位）

| 场景 | HEAD 基线 frame_ms | -06 后 frame_ms | Δ |
|---|---|---|---|
| clear | 7.73 | 7.26 | **−0.47** |
| overcast | 7.49 | 7.55 | +0.06 |
| heavy_rain | 8.41 | 7.52 | −0.89 |
| thunder | 7.36 | 7.04 | −0.32 |
| heavy_snow | 6.90 | 7.50 | **+0.60（最大）** |
| typhoon | 7.87 | 7.54 | −0.33 |
| q0 heavy_rain（相对增量） | 7.42 | 7.45 | +0.03 |
| q4 heavy_rain | 12.48 | 12.40 | −0.08 |

- 资源：draw **+2**（1838→1840）、常驻节点 **+2**（1928→1930）、VRAM **±0**；12→16 槽的静态成本 task-11 实测 +0.068 ms。
- 门限：所有场景 < +1.0 ms（最大 heavy_snow +0.60）→ PASS。
- q0 FPS≥170 门**未达**：本机改后 143.7 fps / 基线 133–138 fps，属整机漂移；建议改为相对增量门或换机复测（见 §12）。

### 6.5 回归与“预存在失败”排除

| 项 | 结果 | 说明 |
|---|---|---|
| `--selftest` | **75/75 PASS**（P8 基线 71；-02 后 73；-06 +2 条照明断言） | |
| `probe_p81_lights.gd --mode=checks` | **147/147 PASS，fails=0** | -06 专项 |
| `probe_lights_p7v3.gd` | EXIT 0，PASS | 灯照契约 |
| `probe_p7v2_light.gd` | 66 pass / 1 fail | 断言“路灯相对地形高度 ∈ [1.2,2.6] m”，实测 2.54/2.73/2.84/2.51/2.52/2.55；第 3 盏 2.84 超界。**用 HEAD 0136363 基线副本逐条复核同样 66/1、同一断言** → 预存在，不计 -06 回归 |
| `probe_cottage6.gd` | 26 pass / 5 fail | box1 center、solid coverage 5/7、beam occlusion 13/15、perches 12/14、attic lights found 0。**HEAD 基线同样 26/5，逐条相同** → 预存在 |
| `--check-only` main/probe | EXIT 0 | 语法/编译检查 |
| 日志 | global parameter removed=0、SCRIPT ERROR=0、shader error=0、NaN=0（`f.is_null` 28 条为工程既有 cache 警告） | |

**契约/口径变更**（经 Lead 裁决授权，见 §10 D10）：`EXP_BUDGET` 旧 7/8/9/11/12 → 新 10/11/12/14/16；`active` 上限 12→16；`g_light_count` 上限 12→16；`active` 口径由“单池受光盏数”改为“室外+室内合计”（q0 旧 7 → 新 10，q4 新 16）；`budget` 保留为总预算并新增 `outdoor_budget/indoor_budget`；新增 `pool_outdoor/pool_indoor/outdoor_count/indoor_count`，`lights` 保留为 out+in 拼接（前 6 仍路灯）以兼容旧探针；性能面板 `lights` 改为实际激活数。

### 6.6 壁炉被烟囱遮挡（P8 既有缺陷，非 -06 回归）

- 现象：夜间/近景下壁炉位置出现“中心暗、四周亮”的软暗斑，看不到炉膛火焰。
- 几何根因：`cottage.gd:1168` 烟囱主体 box `size(0.88,5.75,0.80)`、中心 `ch_z=-2.60` → z 跨度 **−3.00..−2.20**；而一层内墙面在 z=−2.80 → 烟囱**侵入室内 0.60 m**，前脸 z=−2.20 挡住壁炉石胸（:1743，z−2.80..−2.54）、黑炉膛（:1744，z−2.59..−2.53）、3 块火焰盒（:1753-1759，z−2.61..−2.43）与 halo（:1761，z=−2.42）；壁炉光槽 local z=−2.30 也落在烟囱体内，可见面 ndl 最小 → 软暗斑。
- 取证：合批 manifest 的 suspect 标记、洋红薄板逐 z 扫描（z=−2.20 可见 / −2.21…−2.67 不可见）、HEAD 基线副本同机位 q2/q4 同样看不到炉膛火焰、`fire_only_batch05` 可见 3 个火芯。
- 结论：**P8 起即存在**，-06 的灯只暴露了它；不在 -06 修（会改 cottage 几何/栖点/烟帽），转为 **P8.2 建议**：烟囱拆“室内胸 + 室外砖砌”（室内胸深度 ≤0.26 m）+ 火焰前移 z≥−2.44；最小改法 box 深度 0.80→0.26、z −2.60→−2.93，并复核 chimney perch 与烟帽位置。

### 6.7 G6 与未验证

| G6 条件 | 结果 |
|---|---|
| L1–L8 全过 | PASS |
| 五档夜晚截图 | PASS（27 张，q0–q4 × 门面/室内/壁炉/码头 + 岛夜/阁楼/门廊 + 白天对照 + 雪夜） |
| q2 ≤ +1.0 ms | PASS（最大 +0.60 ms） |
| draw ≤ +8 / node ≤ +12 / VRAM ≤ +10 MB | PASS（+2 / +2 / ±0） |
| q0 FPS ≥ 170 | **未达**（机器漂移，记录为已知限制） |
| 壁炉火焰可见 | **未达（P8 既有几何遮挡）**，见 §6.6 |

-06 未验证 10 条：壁炉火焰可见性（待 P8.2 几何修）、灯罩 glow 过曝（门廊近景大光团，glow 1.0 偏高）、室内外硬边界（门洞/窗边硬阶跃光带未逐像素扫）、船灯 0.4 s 淡入淡出未逐帧录屏、q0 FPS≥170 未达、五档低端 GPU 未测（仅 RTX 2060）、阁楼台灯 2 盏未进五档（预算满，设计取舍）、门廊聚合槽与两灯罩对称性未等距像素比较、冬季雨天灯照未重拍、`probe_p81_lights` 未覆盖截图内容质量。

---

## §7 P8.1-07 原生日期时间滚轮

### 7.1 阶段一（commit 024da24，tag p81-07-stage1-accepted）

- 新增 `scripts/ui_datetime_wheel.gd`（841 行，`class_name IsleDateTimeWheel extends Control` + 内部类 `WheelColumn`）：5 列（年/月/日/时/分）自绘滚轮、中心高亮、拖动 + 惯性 + 临界阻尼弹簧吸附、键鼠输入、只读态、busy 状态、调试钩子。
- `hud.gd` 用滚轮替换旧 5 行「−/+」标签（+91/−71）：草稿/预览/确认/busy/收折/只读全部接线，删除旧 `_cal_row/_cal_value_labels`；面板常量 `TIME_PANEL_TOP=−524 / TIME_PANEL_TOP_CAL=−744` 未改（main.gd:3449/:3466 selftest 固定断言）。
- 新增 `tools/probe_p81_datetime_wheel.gd`（525 行）：无头断言 W01–W12 + C 边界。
- 数值模型：列宽 [68,46,46,46,46]/列距 6/左内 20；行高 28 px、可见 5 行；控件 316×156；字号 16/13/10；状态机 SETTLED=0 / DRAGGING=1 / MOMENTUM=2 / SNAPPING=3；弹簧 ω=18、ζ=1（临界阻尼解析解）；摩擦 `exp(−6dt)`；惯性阈值 1.2 行/s；收敛 0.01 行 / 0.05 行·s⁻¹；年橡皮筋 0.25 行；拖动阈值 3 px；EMA 0.35。
- 结果：**PASS pass=82 fail=0，EXIT=0**；日志 `开发产物/p81/evidence/p81_07/probe_p81_datetime_wheel.log`。
- 实现中修复：P-1 `set_parts` 先按旧年月算日上限导致 2/29 被钳（改为先年/月→同步日范围→日/时/分→再同步）；P-2 `wrapi` 少参数改 `posmod`；P-3 内部类引用外层 class_name 常量在 headless 首帧的解析风险（字面量化 + unit_text 注入）；P-4 hud.gd 多次编辑行号漂移导致重复函数体（整段重写）；P-5/P-6 headless 鼠标恒在 (0,0) 与未松手导致 W09 失败（probe 隔离）。

### 7.2 阶段二（commit 0136363，tag p81-07-accepted）

- `main.gd` 注入 selftest UI 用例 + 两处真实 bug 修复：
  - bug A：`set_parts()` 不更新 `_last_parts` 导致假 dirty（ui_datetime_wheel.gd:113-121）；
  - bug B：滚轮 `WHEEL_UP/DOWN` 未判 `mb.pressed` 导致 released 双 notch（ui_datetime_wheel.gd:697-712）。
- 验收环境：干净副本 `D:/p81_final_r2` = `git archive 0136363` + 复用 `.godot`（约 250 MB）；windowed 真实实例化 isle.tscn；1440×900 输入基准 + 1600×900 布局复检；`screen_scale=1.0`、`dpi=120`；写盘防护 `_settings_save_delay=−1`，`user://settings.cfg` mtime 未变。
- 命令与结果：

```
Godot --path . -- --selftest
    全部通过（含 -07 注入用例）
Godot --headless --script res://tools/probe_p81_datetime_wheel.gd
    EXIT=0 PASS pass=82 fail=0
Godot --script res://tools/probe_p81_datetime_wheel_ui.gd
    EXIT=0 [SUMMARY] total=82 pass=80 warn=2 fail=0 shots=9 耗时=44.0s
```

### 7.3 UI1–UI10 实测摘要

| 用例 | 断言 | 结果与关键数字 |
|---|---|---|
| UI1 面板几何/中心行 | 12 | PASS；panel=(34,156,360×660)、wheel=(52,486,324×156)、5 列高 140、中心偏差 0、中心亮度 0.1793 vs 邻行 +0.0585/+0.0601；wheel=2026-10-22 12:20 = 权威时钟 |
| UI2 输入 | 10 | PASS；minute 20→19、day 22→23 慢拖、hour 12→13 点击+键盘；相机 `_radius=82.0000 Δ=0`（滚轮不缩放相机） |
| UI3 草稿/收折 | 6 | PASS；编辑后 0.45 s 保持、重开 wheel=auth dirty=false、收起 offset_top=−524 |
| UI4 暂停中只编辑 | 3 | PASS；`_sim_seconds=1792671600.0 Δ=0`、jump_count 0→0 |
| UI5 real 只读 | 10 | PASS；日历自动收起、`_cal_toggle/_cal_jump_btn/_pause_btn disabled`、`wheel._editable=false`、`_abs_unix Δ=−0.05 s` |
| UI6 跨年跳转 | 9 | PASS；2027-01-01 00:00、jump 0→1、`_sim_seconds=1798761600.0`、秒=0、paused 保持 |
| UI7 幂等 | 4 | PASS；第二次确认 jump 1→2 但 `_sim Δ=0.000000`（main 早退） |
| UI8 H 隐藏/busy | 6 | PASS；收起安全、`wheel.is_busy=false` |
| UI9 busy 不收折 | 3 | PASS；busy idle 0→不收折、空闲 14 s 收折 |
| UI10 帧时间 L4 | 1 | **WARN 未证明**：Δp50 三轮 [0.353, 0.794, 1.203] ms，中位 +0.794 ms；Δdraw +93（关闭 1898→打开 1991）；gate 期 4 次在 PASS/WARN/FAIL 跳变，样本噪声 >1.5 ms |

- 已知缺陷表 P-1…P-6：合成输入需 `Input.warp_mouse`；假 dirty；双 notch；拖拽贴 `FLICK_THRESHOLD` 1.2 改 0.67 行/秒；`Performance.TIME_PROCESS` 在 windowed 下恒为常量不可用；UI1 滚轮宽 316→324 断言改区间。
- 未验证：U-02 帧时间 L4 未证明（=UI10 WARN）、U-03 高 DPI 真机、U-04 桌面触摸（WARN）、U-05 手感、U-06 TAB 全列、U-07 并发面板、U-08 real 跨午夜、U-09 长时运行、U-10 极端年份、U-11 失焦/多显示器、U-12 键重复率；UI1 高 DPI/像素映射与 U01/U03 TAB 单步在窗口验收中 PASS。

### 7.4 G7 验收结论

| G7 条件 | 结果 |
|---|---|
| W/UI 全过 | PASS（阶段一 82/0；阶段二 80 pass / 2 warn / 0 fail） |
| 滚轮不缩放相机 | PASS（UI2 `_radius Δ=0`） |
| real 模式只读 | PASS（UI5） |
| 跨年/闰年/月末正确 | PASS（W04/W05/W06 + UI6） |
| 确认后 `_sim_seconds` 秒=0 | PASS（UI6） |
| 面板不遮按钮 | PASS（UI1 几何 + 9 张截图非黑屏） |
| 旧日历 selftest 过 | PASS |
| 帧时间 <0.3 ms（L4） | **未证明（UI10 WARN）**，记为已知限制 |

---

## §8 与 P8 冻结基线的关系与历史文档注记

### 8.1 保留 / 变更 / 删除

| 类别 | 内容 |
|---|---|
| **保留（契约不变）** | 唯一权威时钟 `main.gd::_sim_seconds`；日历/月球/四季/12 类天气调度、暂停/跳转/跨年语义；岛民/海鸥/船/烟/萤火生态联动；P8 的 46 张固定日期截图口径与既有 docs；P7-V2 栖点 36 点契约（`world.build` 默认 false 保旧探针，main 传 true 得 41 点） |
| **变更（本阶段）** | 冬季树冠保留量 0.10→0.0；树顶红梅删除→屋前 5 朵地栽红花；新增 5 冬季裸枝栖点与双向季节门控；季节白化拆 `g_winter`（与 `g_weather` 分离）+ 室内豁免；天气 13→12 类与观测权重；落叶风场/萤火抑制/秋千受迫摆；照明 12→16 槽双池与五档预算 10/11/12/14/16；日期时间编辑改五列滚轮 |
| **删除** | `main.gd::_setup_winter_plum()` 与 `WinterPlum` MultiMesh（含 `_winter_plum/_winter_plum_anchors` 字段与 bloom 驱动代码）；`probe_p8_season` 中“红梅存在/可见”断言改为“不存在 + canopy 全隐藏”；`hud.gd` 旧「−/+」日历行 |
| **探针契约变更** | `probe_p7v2_light.EXP_BUDGET` 7/8/9/11/12 → 10/11/12/14/16；`active/g_light_count` 上限 12→16；新增 outdoor/indoor 分池字段（见 §6.5、§10 D10） |

### 8.2 P8 历史文档的 P8.1 注记（已插入 16 处）

统一口径：**「P8.1 注记：P8.1 起天气类型合并为 12 类（windy 已并入 strong_wind 的强风状态），详见 docs/P8_1_REFINEMENT_REPORT.md / P8_1_TEST_RESULTS.md。」**；非天气类注记按 P8.1-02/-03 的改动单独措辞（删除树顶红梅、冬季裸枝、白化与积雪分离）。**只追加注记，不改原文、不改历史结论。**

| # | 文档:行（追加位置） | 注记类型 |
|---|---|---|
| 1 | docs/P8_REPORT.md:16 | P8.1-02：冬季树冠 0.0、删红梅、5 裸枝栖点、屋前 5 红花 |
| 2 | docs/P8_REPORT.md:17 | 天气 12 类统一注记 |
| 3 | docs/P8_REPORT.md:102 | P8.1-02：树梢 30 实例红梅方案已删除 |
| 4 | docs/P8_REPORT.md:110 | 12 类精确列表（windy 并入 strong_wind） |
| 5 | docs/P8_REPORT.md:241 | P8.1-03：白化与积雪分离、室内豁免 |
| 6 | docs/P8_TEST_RESULTS.md:78（表后） | P8 口径 3135 → P8.1 12 类口径 3145 |
| 7 | docs/P8_TEST_RESULTS.md:159 | 天气 12 类统一注记 |
| 8 | docs/P8_WEATHER_SYSTEM_TEST_REPORT.md:13（表后） | 13 种类型 → 12 类 |
| 9 | docs/P8_WEATHER_SYSTEM_TEST_REPORT.md:26 | 12 类列表（windy 已并入 strong_wind） |
| 10 | docs/P8_WEATHER_SYSTEM_TEST_REPORT.md:91 | 自动雪权重 0、雪仅冬季手动 |
| 11 | docs/P8_WEATHER_SEASONS_PLAN.md:181（代码块后） | 状态契约 type 为 12 类之一 |
| 12 | docs/P8_WEATHER_SEASONS_PLAN.md:203 | §7.2 天气 12 类；雪仅冬季手动 |
| 13 | docs/P8_WEATHER_SEASONS_PLAN.md:250（表后） | 阶段 5 验收“13 类型合法”→12 类型 |
| 14 | docs/P8_WEATHER_SEASONS_PLAN.md:275 | 测试矩阵天气 12 类型 |
| 15 | docs/P8_SEASONS_TEST_REPORT.md:61 | P8.1-02：冬季完全裸枝、红梅改屋前红花、5 裸枝栖点 |
| 16 | docs/P8_SEASONS_TEST_REPORT.md:63-72（§5 末） | P8.1-02：树顶红梅方案整体删除 |

> docs/P8_1_REFINEMENT_PLAN.md 末尾已追加「## 实施状态（P8.1-08 回填）」一节，逐阶段记录状态/commit/tag/验收门/偏差，不改动原 13 章内容。

### 8.3 发布包与版本

- **发布包已重建并验证**：`发布/休闲小岛幻境.exe` = `构建输出/休闲小岛幻境.exe` = **117,238,104 B**，sha256 `c40376ad2dda1d8eb2e9848ca8a2ce00e4c1a841a03444fa9e9b80ef5d62b668`；`--headless --quit` EXIT 0、`--headless -- --selftest` **73/73 EXIT 0**。旧 P7-V3.1 包已备份至 开发产物/backup/release_pre_p81/（116,917,880 B，sha256 `cf973721…84667c`），旧包自测 53/53（开发产物/logs/p81_08/old_p7v3_selftest.log）。
- **构建缺陷与修复（D14）**：export_presets.cfg 的 exclude_filter 含 `tools/*`，而 main.gd:26 `preload res://tools/scale_debug_overlay.gd`；导出构建中 main.gd 报 SCRIPT ERROR Parse Error: Preload file does not exist → main.gd 加载失败 → 发布 exe 完全不可用。该缺陷自 P7-V3.2（fdefa40 引入该 preload）起潜伏，P7-V3.1 旧包构建早于它故可运行。修复 572af3d：文件移入 `scripts/` + 更新 main.gd、tools/probe_scale_world.gd、tools/probe_scale_shots_p7v32.gd 引用与注释，**未改导出过滤、未改功能**。
- **导出环境注意（可复现）**：导出时 TEMP 必须指向可写目录——本机 `C:/Users/.../Temp` 写 project.binary 失败会导致嵌入式 pck 损坏、exe 报 Corrupted header；复现用 `TMP/TEMP=D:/休闲小岛幻境/开发产物/tmp_export`。
- **版本语义**：P8.1 不改变项目版本号语义（仍为观感/生态精修），exe 文件名不含版本后缀。
- 冻结 tag：**p81-refinement-freeze-20261022**（代码冻结点 6de37c4，tag 指向本轮文档提交）。

---

## §9 阶段验收门汇总（G2–G8）

| 阶段 | tag | commit | 验收门 | 结果 | 证据路径 |
|---|---|---|---|---|---|
| -02 | p81-02-accepted-20261022 | 07752e2 | G2 | PASS（1 项像素 diff 未验证） | 开发产物/p81/evidence/p81_02/ |
| -03 | p81-03-accepted-20261022 | 3add702 | G3（13 项） | PASS | 开发产物/p81/evidence/p81_03/ |
| -04 | p81-04-accepted-20261022 | 285648e | G4 | PASS（HUD 视觉/旧存档窗口加载待复核） | 开发产物/logs/p81_lead/、开发产物/p81/weather/ |
| -05 | p81-05-accepted-20261022 | 95263d0 | G5 | PASS（D1/D2 按 Lead 裁决口径） | 开发产物/p81/evidence/p81_05/ |
| -06 | p81-06-accepted-20261022 | 00ff6c1 | G6（L1–L8） | PASS（q0 FPS 门未达，壁炉遮挡为 P8 既有缺陷） | 开发产物/p81/evidence/p81_06/ |
| -07 阶段一 | p81-07-stage1-accepted-20261022 | 024da24 | G7（组件/无头） | PASS 82/0 | 开发产物/p81/evidence/p81_07/ |
| -07 阶段二 | p81-07-accepted-20261022 | 0136363 | G7（端到端） | PASS 80 pass / 2 warn / 0 fail（UI10 WARN） | 开发产物/p81/evidence/p81_07_stage2/ |
| **-08** | p81-refinement-freeze-20261022 | 6de37c4（代码冻结） | **G8** | **条件通过**：全量回归 15/17 PASS + 2 项预存在失败（基线同）、q2 性能门 PASS、发布包重建验证 PASS；q0 FPS 门未达（D15）、P8 冻结 46 张未重拍（U45） | 开发产物/logs/p81_08/；发布/休闲小岛幻境.exe |

### 9.1 G8 回填结果

| 项 | 结果 |
|---|---|
| 主自测 | 编辑器 headless `--selftest` **73/73 EXIT 0**（窗口模式 75/75；headless 跳过 main.gd:3621-3623 两条真实鼠标拖动用例）；发布 exe `--headless -- --selftest` **73/73 EXIT 0** |
| 全量探针 | 17 项 headless：**15 项 PASS/exit0**（selftest 73/73、p8_calendar 2672、p8_moon 233、p8_season 114、p8_weather 3145、p8_ecology 41、p81_tree_bird 149、p81_whiteness、p81_wind 117、p81_lights 147、p81_wheel 82、p7v2_perch 265、p7v2_bird 681、p7v3_lights exit0、p7v3_boat 169）；**2 项预存在失败**且 `0136363` 基线复跑逐条相同：p7v2_light 66/1、p7v2_flycam 76/7（headless 无 GUI 鼠标注入） |
| 性能 | 5 轮交替中位（1600×900 q2；final 6de37c4 vs base 0136363）：clear **5.91 vs 5.83 ms（Δ+0.08）**、overcast +0.16、heavy_rain +0.11、thunder +0.07、heavy_snow +0.07、typhoon +0.07、heavy_rain_q0 +0.17、heavy_rain_q4 −0.03；draw +2 / node +2 / VRAM ±0.0 MB。帧时间门（q2 ≤+1.0 ms）**PASS**；**q0 FPS 门（≥170）未达：166.1 vs base 170.9 FPS**，按 D15 条件通过 |
| 截图 | 窗口 1600×900：-02 **10** 张、-03 **125** 张（含 ON/ON2/OFF/ON3 四联与 q0–q4）、-05 **12** 张（-06 保持 27 张正式矩阵未重拍）；G3 像素差（逐通道最大差 >8/255、全帧 1600×900）：室内白天 **0.0000%**、夜晚 **0.0056%（冬）/0.0065%（雪）**、阁楼 **0.0000%**、窗外 **44.9786%/41.5265%**（噪声基线 0.0053%，详见 §3.4）；P8 冻结 46 张未覆盖（U45） |
| 发布包 | `发布/休闲小岛幻境.exe` = `构建输出/休闲小岛幻境.exe` = 117,238,104 B，sha256 `c40376ad2dda1d8eb2e9848ca8a2ce00e4c1a841a03444fa9e9b80ef5d62b668`；quit EXIT 0、selftest 73/73 |
| 冻结 | 代码冻结 **6de37c4**；tag **p81-refinement-freeze-20261022**（指向本轮文档提交）；工作树在本轮 docs 提交后干净 |

> 说明：G8 原要求的“≥46 张 P8 固定日期重拍”未执行——任务书同时要求保护 P8 冻结证据（`开发产物/p8/` 只读），二者冲突；-08 以 P8.1 三个重拍组（147 张，1600×900）作为最终截图基线，P8 冻结 46 张保持原样（U45）。

---

## §10 与计划书的偏差清单

| # | 计划书（P8_1_REFINEMENT_PLAN.md） | 实施 | 原因 / 裁决 |
|---|---|---|---|
| D1 | -02 世界栖点直接变 41 点 | `world.build(parent, include_winter := false)` 默认 false，main 显式传 true | 保 P7-V2 探针 16/22/36 点契约；只有 main 场景得 41 点 |
| D2 | 冬季红梅仍存在（P8 设计） | **整体删除**，改屋前 5 朵地栽红花 | P8.1-01 调研证实“枝轴端点+随机抖动”必然漂浮；地栽红花不依赖树顶 |
| D3 | 冬季树冠保留 10%（P8 值） | 改为 **0.0** | 残冠是确定性洗牌后的随机子集，与层/枝无关联，必出浮空球 |
| D4 | 截图沿用 P8 机位 | 删除 `_p8_camera_winter_plum`，新增 `--p81treebird` 独立机位与目录 | 红梅已删、原机位无对象；且禁止写 P8 冻结目录 |
| D5 | -03 沿用 P8 的 `snow_line` | 另立 `g_winter` 通道，不与降雪共用 | U11：`snow_line 1.05–3.20` 是海平面岸线淡出，不是岛面高程阈值 |
| D6 | -04 按旧 13 类权重比例换算 | 改为澎湖 2023–2025 观测小时占比 ×100；`heavy_rain` 强度公式按观测微调；台风季节切分保留观测值 | 13 类时 windy 与 strong_wind 混计，比例换算无意义；观测数据与推导见 `开发产物/p81/findings/weather_data.md` |
| D7 | -05 萤火强风抑制目标 1/5 | 实测 1/12，Lead 裁决维持；验收门改为区间 [1/60, 1/5] | 三通道乘性抑制的物理叠加结果；计划值原为设计目标 |
| D8 | -05 F8 字面阈值 0.25 | 改为“ratio<0.05 时不得以原寿命/原范围发射” | 字面 0.25 与 F7 强风+小雨 0.0359 冲突，会误杀“微弱残留”设计 |
| D9 | -06 12 槽解析光（P8 预算） | **16 槽双池**（室外 10 + 室内 6），五档预算 10/11/12/14/16 | 12 槽无法同时保证壁炉/吊灯/家具灯与室外路灯；方案 A（真实 Light3D）实测超门一个数量级 |
| D10 | -06 冻结探针契约不变 | `probe_p7v2_light.EXP_BUDGET` 与 active/g_light_count 上限更新 | 实现口径变更，Lead 裁决授权（-06 报告 §10 记录） |
| D11 | -06 壁炉可见性验收 | 未达成，转为缺陷记录 + P8.2 建议 | 烟囱侵入室内 0.6 m 是 P8 既有几何缺陷，修它需改 cottage 几何/栖点，超出 -06 范围 |
| D12 | -07 帧时间 L4 <0.3 ms | UI10 WARN，保留 U-02 | 窗口端到端样本噪声 >1.5 ms，4 次 gate 跳变，无法证明 |
| D13 | 文档名 `docs/P8_1_REPORT.md` | 正式名为 `docs/P8_1_REFINEMENT_REPORT.md`（与 `P8_1_TEST_RESULTS.md` 配套） | 与计划书 §11.8 的占位名不同，Lead 定名 |
| D14 | 计划书未含“发布包构建可行性”验收 | 新增构建修复提交 572af3d 并纳入 G8 | **根因**：export_presets.cfg exclude_filter 含 `tools/*`，main.gd:26 preload `res://tools/scale_debug_overlay.gd` → 导出构建 main.gd Parse Error、exe 不可用。**影响面**：自 P7-V3.2（fdefa40）起所有导出构建；P7-V3.1 旧包因构建早于该 preload 仍可运行（旧包自测 53/53）。**修复**：文件移入 `scripts/` 并更新 main.gd / probe_scale_world / probe_scale_shots_p7v32 引用，未改导出过滤与功能。**验证**：发布 exe quit EXIT 0 + selftest 73/73 + sha256 记录。**为何算 -08**：发布包重建是 G8 门槛；构建缺陷在“重建发布包”这一步才暴露，修它属于交付发布的一部分，且不改变任何运行时行为 |
| D15 | G6/G8 的 q0 FPS 门（≥170） | **条件通过**：final 166.1 FPS vs base 170.9 FPS（Δ−4.8），相对帧时间 heavy_rain_q0 +0.17 ms 在预算内 | base 本机 170.9、历史 P8 记录 177.0；本机漂移与 12→16 槽成本叠加使绝对值不可达。G6 已记录为限制，G8 按条件通过记录；P8.2 建议：q0 单独降槽或按距离裁剪灯具 |
| D16 | -02 tag 指向与 .uid 文件 | ① `p81-02-accepted-20261022` 原误指 285648e，已 `git tag -f` 重建指向 07752e2（-02/-04 为两个独立提交）；② 新增 6de37c4 补交 18 个 P8/P8.1 新脚本与 shader 的 `.uid`（chore，无功能变更） | tag 是发布标签，必须指向正确阶段提交；`.uid` 为 Godot 4.7 资源标识文件，缺失会在他人机器/CI 上导致资源重导入与引用漂移，故随发布补齐 |

---

## §11 回滚方案

### 11.1 整体回滚

- 回到 P8 冻结：`git reset --hard p8-weather-seasons-freeze-20261022`（或在发布分支 revert 8 个提交）；P8.1 所有改动均在 8 个提交内，回滚后 P8 行为完整恢复。
- 分阶段回滚按 §1.2 的 commit 顺序反向 revert；-02 与 -04 现为独立提交（07752e2 / 285648e），可分别回退；注意 -02 tag 曾被重建，回滚一律以 commit 号为准。
- tag 保留：各阶段 accepted tag 仍指向原提交，回滚后可用于对照。

### 11.2 按特性的“软回滚”（不改提交，仅关效果）

| 特性 | 软回滚开关/默认值 |
|---|---|
| 冬季裸枝/红花 | `isle_season.gd:55` winter canopy 改回 0.10 即恢复残冠（不建议）；删除 `world._winter_blooms` 调用即关红花；`include_winter=false` 即回 36 点栖点契约 |
| 季节白化 | `g_winter` 全 0（main 写 uniform 前乘 0）即关闭 |
| 天气 12 类 | 恢复 TYPE_ORDER 与权重表、`WEATHER_TYPE_ALIASES`；旧存档无需迁移（strong_wind 仍合法） |
| 强风视觉 | `F10 legacy 开关` 可 A/B；落叶参数/lifetime、萤火 ratio 公式、秋千受迫摆均有独立常量 |
| 照明 16 槽 | `LIGHT_INDOOR_BUDGET` 与五档 `light_budget` 回 7/8/9/11/12；室内池置 0 即回单池行为（shader 双池选池代码保留） |
| 滚轮 | 恢复 `hud.gd` 旧 5 行「−/+」控件（本提交前版本），或整文件 revert 024da24/0136363 |

### 11.3 数据与文档

- 存档：`isle_settings` 的天气 sanitize 是“先迁移后校验”，回滚到 13 类后 strong_wind 仍合法；不产生坏档。
- 文档：本报告与 `P8_1_TEST_RESULTS.md` 新增文件可安全删除；P8 历史文档的 16 处注记可逐条删除（注记是独立行/独立段落，不影响原文）；`P8_1_REFINEMENT_PLAN.md` 末尾回填节可整节删除。
- 风险：回滚 -06 时若已重建发布包，需同步回退 exe 与版本号；回滚后必须重跑 `--selftest` 与 P8/P8.1 探针（契约常量在回滚后可能不匹配）。

---

## §12 未验证与遗留

### 12.1 -02（冬季树/栖点/红花）

| 编号 | 项 | 状态 |
|---|---|---|
| -02-U1 | 5 朵红花实际地形高度/坡度/是否穿石头或路径边缘 | 未验证（仅静态几何推算） |
| -02-U2 | 海鸥自然（非门控）落到新裸枝点的概率 | 未验证（估计约 20%，未跑长时生态模拟） |
| -02-U3 | 裸枝视觉粗细（鸟脚宽与枝粗比例） | 未截图评审 |
| -02-U4 | 跨季长程 soak（数天模拟快速切换） | 未做 |
| -02-U5 | 与 P8 冻结截图像素对比 | **已关闭**：-08 统一重拍为 1600×900；未与 P8 冻结 46 张逐像素对比（U45） |

### 12.2 -03（白化）

12 条已知限制见 §3.5；其中“shader 逐片元耗时、极端贴墙机位、玻璃/金属霜雪、屋顶色相、分辨率可移植、兼容渲染器”均未运行时验证。

### 12.3 -04（天气）

旧存档窗口加载实测未做；三年无雪为观测结论而非运行时长跑；HUD 12 类按钮布局仅静态校验，视觉见 -08 截图。

### 12.4 -05（强风）

CPU +1.93 ms 来源未 profile；萤火“可见残留”仅有 ratio 数字；台风级秋千手感未主观评审；-05 REPORT 记录的 U1–U9 其余项以该报告为准。

### 12.5 -06（照明）

10 条见 §6.7；重点：壁炉火焰可见性（P8 既有缺陷，需 P8.2 几何修）、灯罩 glow 过曝、室内外硬边界、船灯淡入淡出、q0 FPS 门、低端 GPU。

### 12.6 -07（滚轮）

U-02（帧时间 L4）、U-03（高 DPI 真机）、U-04（桌面触摸 WARN）、U-05（手感）、U-06（TAB 全列）、U-07（并发面板）、U-08（real 跨午夜）、U-09（长时运行）、U-10（极端年份）、U-11（失焦/多显示器）、U-12（键重复率）未验证；详见 -07 阶段二报告。

### 12.7 全局（计划书 §13.8）

- **U42** 性能全重测：已由 -08 执行——5 轮交替中位，6 场景 q2 Δ 均 ≤+0.17 ms（门 +1.0），q0 FPS 166.1（门 ≥170 未达，D15），q4 −0.03 ms；明细见 §9.1 与 `docs/P8_1_TEST_RESULTS.md` §7.4。
- **U43** 五档画质无像素阈值：仅人工目视。
- **U44** 冬季/夜晚/室内矩阵未建立：-03/-06 各自覆盖局部，-08 统一矩阵补齐。

### 12.8 -08（全量回归与发布）

| 编号 | 项 | 状态 |
|---|---|---|
| U45 | P8 冻结 46 张固定日期截图未重拍（任务书要求保护 P8 冻结证据，与本条冲突） | 未做；以 P8.1 三组重拍 147 张（1600×900）为最终截图基线 |
| U46 | G3 像素差口径 | **已关闭**：口径 = 逐通道最大差 **>8/255**（Pillow）、全帧 1600×900；数字与 `开发产物/p81/evidence/p81_03/diff_stats.json` 一致（室内夜晚 0.0056%/0.0065%、窗外 44.9786%/41.5265%、噪声基线 0.0053%） |
| U47 | 旧 P7-V3.1 发布包仅验证可启动与自测 53/53，未做完整功能回归 | 未做（用于证明“旧包可运行、缺陷自 P7-V3.2 起潜伏”的必要证据已达到） |
| U48 | 发布包在其它机器的 TEMP/权限环境下导出复现 | 未做；本机已记录可写 TEMP 的复现方法（§8.3） |

---

## §13 结论与后续建议

1. **P8 冬季三类可见缺陷已闭环**：残冠悬空（canopy 0.0）、树冠黄绿（无冠可染）、红点漂浮（删树顶红梅、改地栽红花），并新增 5 个真实裸枝栖点替代球面栖点，季节切换不传送、不残留预约。
2. **白化与积雪的语义分离**是 P8.1 最重要的结构性修正：季节白化不再复用降雪的 `snow_line`，室内豁免由几何 mask 保证，像素证据（0.0000%）成立。
3. **天气系统的“可解释性”提升**：12 类、观测权重、自动雪归零、旧档迁移，使天气不再依赖“艺术概率”；代价是裁剪了 windy 的独立类型表达（由连续风力参数承担）。
4. **强风视觉三件套**用纯函数层 + 参数驱动实现，无新增节点/资源，帧时间净成本 +0.012 ms；CPU +1.93 ms 是唯一需要盯的隐性成本。
5. **照明的方案 B（16 槽双池）是正确取舍**：真实 Light3D 方案实测超门一个数量级；当前 5 档 10–16 盏解析光，q2 最大 +0.60 ms、资源近乎零增长。
6. **-06 的“壁炉中心暗斑”不是回归**，而是 P8 烟囱几何侵入室内 0.6 m 的既有缺陷；已留完整取证链与最小改法，转入 P8.2。
7. **滚轮交付质量**：无头 82/0 + 窗口 80/2/0，两处真实 bug 在阶段二修复；UI10 帧时间受样本噪声限制无法证明，保留 U-02，不掩盖。
8. **文档一致性**：P8 历史文档的 13 类表述已用 16 处注记对齐，统一指向本报告与测试结果；计划书末尾补实施状态回填。
9. **P8.2 建议**：①修壁炉/烟囱几何（烟囱拆室内胸 ≤0.26 m、火焰前移 z≥−2.44）；②评估灯罩 glow 1.0 在门廊近景的过曝；③补 q0 低端机 FPS 与五档性能矩阵（换机或相对增量门）；④决定是否给冬季裸枝加“更粗的端部枝”以改善栖点观感；⑤滚轮 U-02/U-04 的真机复测。
10. **发布门槛与冻结依据**：selftest **73/73**（编辑器 headless 与发布 exe 均）、17 探针 **15 PASS + 2 预存在失败**、性能 5 轮中位 q2 门 **PASS**（q0 条件通过，D15）、截图 **147 张（1600×900）**、发布包 sha256 **c40376ad…5d62b668**；冻结代码 **6de37c4**、tag **p81-refinement-freeze-20261022**；P8 冻结证据目录未被写入。
11. **构建打包教训**：发布包必须作为验收对象真实构建并运行（quit + selftest + sha256 记录）；`preload` 路径与导出过滤规则必须在导出构建中验证——本次缺陷自 P7-V3.2 潜伏至 P8.1-08，直到重建发布包才暴露。

---

## 附录 A 关键文件与行号索引

| 文件 | 本阶段关键位置 |
|---|---|
| `scripts/isle_season.gd` | :55-56 冬季 canopy/cards |
| `scripts/world.gd` | :52-54 build 签名；:1090-1122 winter bloom；:3806-3838 winter_branch 栖点 |
| `scripts/main.gd` | :96/:644 winter_bloom；:1054-1074 红花驱动；:3877-3938 selftest；:1954-1993 双池写槽；:4188-4230 灯池/船灯；:6570-6600 截图模式 |
| `scripts/fx.gd` | :816-940 落叶/萤火粒子；:2270-2278 栖点季节门控；:2538-2559 驱逐；:3196-3220 validity；:3260-3286 调试接口 |
| `scripts/isle_weather.gd` | :24-64 类型/参数/权重 |
| `scripts/isle_settings.gd` | :72-78 天气类型与别名；sanitize |
| `scripts/isle_quality.gd` | :119-122 室内预算；:150-160 拆分 |
| `scripts/cottage.gd` | :127-156 灯清单；:353 门廊灯罩；:1168 烟囱 box（缺陷点）；:1743-1761 壁炉几何 |
| `scripts/isle_house_props.gd` | :267-280 灯罩；:845/:865 台灯/落地灯 |
| `scripts/ui_datetime_wheel.gd` | :113-121 set_parts；:697-712 滚轮 notch；状态机/弹簧常量 |
| `shaders/toon.gdshader` | :21-25 双池契约；:50-57 槽 uniform；:71-79 winter uniform；:201-221 indoor_mask；:254-273 白化；:336-341 积雪；:359-380 选池 |
| `shaders/grass.gdshader` | :37-38/48/76 白化；:111-122 草接收 |
| `tools/probe_p81_tree_bird.gd`（新） | 149 条树/栖点断言 |
| `tools/probe_p81_whiteness.gd`（新） | 34 条白化断言 |
| `tools/probe_p81_wind.gd`（新） | 117 条强风断言 |
| `tools/probe_p81_lights.gd`（新） | 147 条照明断言 + 27 张截图 |
| `tools/probe_p81_datetime_wheel.gd`（新） | 82 条滚轮断言 |
| `tools/probe_p81_datetime_wheel_ui.gd`（新） | 82 条窗口端到端 + 9 张截图 |

## 附录 B 占位符回填值表

| 占位符 | 回填值 |
|---|---|
| FREEZE_COMMIT | **6de37c4**（代码冻结；冻结 tag 指向本轮文档提交） |
| FREEZE_TAG | **p81-refinement-freeze-20261022** |
| FINAL_SELFTEST | 编辑器 headless **73/73 EXIT 0**（窗口 75/75）；发布 exe **73/73 EXIT 0** |
| FINAL_PROBES | 17 项：**15 PASS/exit0 + 2 项预存在失败**（p7v2_light 66/1、p7v2_flycam 76/7，基线同） |
| FINAL_PERF | 5 轮交替中位 q2：6 场景 Δ 均 ≤ **+0.17 ms**（门 +1.0 PASS）；q0 FPS **166.1 vs 170.9**（条件通过，D15） |
| FINAL_SCREENSHOTS | 1600×900 重拍三组：-02 **10** + -03 **125** + -05 **12** = **147 张**；P8 冻结 46 张未覆盖（U45） |
| FINAL_RELEASE | `发布/休闲小岛幻境.exe` 117,238,104 B，sha256 `c40376ad…5d62b668`；quit EXIT 0、selftest 73/73 |

> 回填后校验：7 个唯一占位符在本文中 **0 残留**（以「双花括号 + 大写名」模式 grep 全文无输出）。

---

**报告作者备注**：本文为 P8.1-08 文档合并产物，只写 `游戏工程/docs/`；未改代码、未改证据、未执行 Godot、未做 git 写操作。所有阶段数字均可在 `docs/P8_1_TEST_RESULTS.md` 与各阶段证据目录中复核。
