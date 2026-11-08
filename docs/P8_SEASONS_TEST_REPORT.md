# P8 阶段 4 · 四季系统测试报告

> 版本：v1.0（2026-10-22）｜分支 `p8-weather-seasons`｜阶段 4（Seasons）
> 唯一权威时钟：`main.gd` 的 `_sim_seconds`；季节是 `IsleCalendar` 对它的只读投影，不新增时钟。

## 1. 结论摘要

| 项目 | 结果 |
| --- | --- |
| 日历季节投影 | 北半球公历季（春 3-5 / 夏 6-8 / 秋 9-11 / 冬 12-2），边界 ±10 天 smoothstep 连续混合，权重和恒为 1 |
| 视觉联动 | 草色 / 叶色 / 灌木 / 树冠保留率 / 叶卡 / 四种花保留率 / 落叶密度 / 落叶色，全部由季权连续插值 |
| 静态探针 | `probe_p8_season.gd` **114 checks / 0 fail**（权重/边界/极值/花物种/确定性/连续性） |
| 运行期自测 | `--selftest` **64/64 passed**（含 4 条 P8 阶段 4 断言） |
| 截图验收 | 13 张（4 季 × 全岛/大树近景/花园近景 + 冬季红梅特写），固定日期、可复跑 |
| 冬季红梅 | 树梢花簇方案（30 实例、单 draw call），仅冬季权重 0.25→0.80 渐显，春夏秋完全隐藏 |
| 新增权威时钟 | 无；无逐帧几何重建；无新贴图/模型/依赖 |

## 2. 实现构成

| 文件 | 改动 |
| --- | --- |
| `scripts/isle_season.gd`（新增） | 四季参数表 + `visuals(weights)` 连续插值 + `dominant/weight_delta/flower_keep_for` 纯函数 |
| `scripts/main.gd` | `_setup_season_visuals/_season_add_entry/_apply_season_visuals/_apply_season_keep/_update_season`；草材质 tint；树冠/叶卡/灌木实例稀疏化；花按物种显隐；落叶粒子；冬季红梅；`--p8seasons` 截图模式 |
| `shaders/toon.gdshader` | 新增 `uniform vec3 foliage_tint`，在顶点色乘法之后乘到 base（树冠/叶卡/灌木季节染色） |
| `scripts/fx.gd` | 新增 `IsleFx.leaves()` 落叶粒子（GPUParticles3D，64 片，程序化叶片贴图）与 `leaf_texture()` |
| `tools/probe_p8_season.gd`（新增） | 114 条纯函数断言 |
| `scripts/isle_calendar.gd` | 阶段 3 已含 `season_at/season_weights`，本阶段只消费 |

实现约束（与 P8 任务书一致）：

- 不重写 `world.gd`：只按节点名（`Canopy` / `LeafCards` / `BgTreeCanopy` / `Bushes` / `Flower*`）取既有 MultiMesh，改材质参数或实例保留数，不重建树/花/地形。
- 不与画质草密度互相覆盖：草只改 `grass.gdshader` 的 `tint`，从不写 `visible_instance_count`。
- 不污染 `IsleMath.toon_material` 的全局材质缓存：树冠/叶卡/灌木各自 `duplicate()` 一份材质再写 `foliage_tint`。
- 稀疏化不使用 `visible_instance_count`（截断只保留前 N 个会按生成顺序成片消失），而是以确定性洗牌顺序把多余实例的 basis 缩到 0.0001；花条目改为逆序（花床实例在 world.gd 末尾追加，优先保留花床里的整齐花）。

## 3. 季节规则

`IsleCalendar.season_at()`：

- 季节相位以 3 月 1 日 0 点为 0，6 月 1 日 0.25，9 月 1 日 0.5，12 月 1 日 0.75；季长按真实公历月天数分段线性。
- 每个边界前后各 `TRANSITION_DAYS = 10` 天做 smoothstep 混合：区间内本季权重从 0.5→1.0（季初）或 1.0→0.5（季末），与相邻季严格互补；权重和恒为 1。
- 1-2 月按“上一年冬季尾段”折算到相位 0.75→1.0，跨年连续；闰年 2 月自动多一天。
- 视觉参数全部由权重线性插值，因此任何一天都不存在硬切；跳日期时只读取当前权重，不补演中间季节。

## 4. 四季视觉映射（`isle_season.gd` SEASON_TABLE）

| 参数 | 春 | 夏 | 秋 | 冬 |
| --- | --- | --- | --- | --- |
| grass 乘色 | (1.04,1.07,0.98) | (0.94,1.05,0.82) | (1.22,0.99,0.55) | (0.92,0.87,0.72) |
| foliage 乘色 | (0.98,1.12,0.80) | (0.84,1.00,0.78) | (1.48,0.86,0.34) | (0.88,0.78,0.66) |
| bush 乘色 | (1.02,1.14,0.82) | (0.90,1.03,0.80) | (1.30,0.92,0.42) | (0.90,0.82,0.72) |
| canopy 保留率 | 0.96 | 1.00 | 0.94 | **0.10** |
| leafcard 保留率 | 0.86 | 1.00 | 1.00 | **0.00** |
| 花保留（Tulip/Daisy/Bluebell/Poppy） | 1/1/1/0.92 | 0.62/1/0.86/1 | 0.05/0.28/0.06/0.48 | 0/0/0/0 |
| leaf_fall | 0 | 0 | **1.0** | 0 |
| drift 落叶色 | 白 | (1.0,0.92,0.72) | (0.95,0.52,0.18) | (0.92,0.92,0.94) |

- 春：草略提亮偏黄绿、树冠满、花全开、花瓣飘落（petals 随春季权重淡入，其它季停发）。
- 夏：草绿更深、花量仍高（Tulip 减、Poppy/Daisy 满）、无落叶。
- 秋：草黄、树冠橙黄（`foliage_tint` 乘色）、部分花收、落叶开启（64 片 GPU 粒子，颜色随 drift 从枯黄到暖橙）。
- 冬：树冠只留 10%（约 4/44 个 blob）、叶卡全收（此前 3% 残留会形成悬空叶卡，已修）、花床全收、地面草色去饱和；树梢出现红梅花簇。
  - **P8.1 注记**（P8.1-02）：冬季树冠保留量改为 **0**（完全裸枝，44 个 blob 全隐藏，不再有悬空残冠）；树顶红梅已删除、改为屋前 5 朵地栽红花；原树冠球面栖点冬季关闭，新增 **5 个冬季裸枝栖点**。详见 docs/P8_1_REFINEMENT_REPORT.md §2。

## 5. 冬季红梅方案说明

**为什么放弃“花床里留 Poppy”**：花床里 Poppy 的花头是低多边几何 + 深色花心（`Color("3a3230")`，半径 0.04），顶点色数据正确（ARRAY_COLOR 均值 (0.557,0.373,0.257)、变体色 `d97b45`），但从任何常规机位看主要体积都是背光/深色花心，像素取样 (70-76,55-61,34-45) 与土色几乎同值，读不出“红花”。保留 18% 只会得到“土里几个深色小圆盘”。

**现方案**：在 `main.gd` 建 `WinterPlum` MultiMesh：

- 锚点取 `world.gd` 大树的固定枝梢（主枝末端 4 处、两条横枝末端、秋千横枝末端），每处 2-3 簇、±0.32 m 抖动；
- 30 个 `SphereMesh`（radius 0.14，6×3）实例、单 draw call，材质 `toon_material(Color("c94f5c"))`；
- 出现条件：`bloom = clamp((winter_w - 0.25)/0.55, 0, 1)`，`bloom > 0.03` 才 visible，实例缩放随 bloom 渐大；花床花量同时为 0；
- 季节切换/跳日期时由 `_update_season` 立即重算（跳转后 `force=true`），不残留、不补演。

> **P8.1 注记**（P8.1-02）：上述 `WinterPlum` 树梢红梅方案已**整体删除**（锚点取枝轴端点 + ±0.32 m 抖动，实测必然出现“红点漂浮枝梢外”）；冬季红花改为屋前草坪 5 朵地栽花，仅冬季随权重渐显，春夏秋隐藏。详见 docs/P8_1_REFINEMENT_REPORT.md §2。
## 6. 验证与复跑

### 6.1 静态探针（114 checks）

```
'D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe' --headless --path 'D:/休闲小岛幻境/游戏工程' --script res://tools/probe_p8_season.gd
```

覆盖：权重和=1/非负（15 样本 + 空/负输入）、四季中点 one-hot、边界日 0 点 50/50、边界逐小时 max_step<0.03、跨年连续、视觉参数极值、日变化 <0.1、花物种顺序与保留率、未知物种回退、visuals 确定性、weight_delta 对称性、日历投影确定性。结果 **PASS（114/114，~40 ms）**。

### 6.2 运行期自测（64/64）

```
'D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe' --headless --path 'D:/休闲小岛幻境/游戏工程' -- --selftest
```

P8 阶段 4 断言：

1. “P8 四季视觉参数与日历联动”：秋 `leaf_fall>0.95`、树冠保留 <1、落叶粒子 emitting；冬树冠 ≤0.25、花全收、红梅 visible；秋草色 r>1.1 且春草色 g>1.0。
2. “P8 冬季树冠实例按比例收起”：`Canopy` 条目 hidden ≥ count×0.5（headless dummy Renderer 不回读 MultiMesh Transform，故断言逻辑计数，像素由窗口截图验收）。
3. “P8 冬季红梅花簇只出现在冬季”：跳 2026-07-15 后 `_winter_plum` 存在但不可见。
4. “P8 季节参数不依赖现实时间”：以上样本均走 `_jump_datetime` 固定日期。

### 6.3 截图（1600×900，固定日期）

```
'D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe' --path 'D:/休闲小岛幻境/游戏工程' --resolution 1600x900 -- --p8seasons
```

| 文件（开发产物/p8/seasons/） | 日期 | 内容 |
| --- | --- | --- |
| p8_season_spring_wide.png | 2026-04-15 10:00 | 春·全岛（草亮、树冠满、花园花满） |
| p8_season_spring_tree.png | 同上 | 春·大树近景（满冠亮绿） |
| p8_season_spring_garden.png | 同上 | 春·花园（粉紫郁金香/蓝铃/雏菊） |
| p8_season_summer_wide.png | 2026-07-15 10:00 | 夏·全岛 |
| p8_season_summer_tree.png | 同上 | 夏·大树近景 |
| p8_season_summer_garden.png | 同上 | 夏·花园（花量高） |
| p8_season_autumn_wide.png | 2026-10-20 16:30 | 秋·全岛（树橙黄、草黄、落叶粒子） |
| p8_season_autumn_tree.png | 同上 | 秋·大树近景（橙黄冠） |
| p8_season_autumn_garden.png | 同上 | 秋·花园（花大幅减少） |
| p8_season_winter_wide.png | 2027-01-15 10:00 | 冬·全岛（残冠、地面去饱和） |
| p8_season_winter_tree.png | 同上 | 冬·大树近景（约 4/44 blob + 枝梢红梅） |
| p8_season_winter_garden.png | 同上 | 冬·花园（花床全空） |
| p8_season_winter_plum.png | 同上 | 冬·红梅特写（枝梢红簇） |

看图结论：四季 wide 差异一眼可辨，春/夏满冠、秋橙黄、冬稀疏；花园帧春/夏花开、秋零星、冬空；冬季树梢红梅可见且只出现在枝梢附近。截图机位与日期写死在 `_run_p8seasonshots()`，复跑结果稳定。

## 7. 性能影响

- 静态几何：零重建；新增仅 1 个 MultiMesh（30 实例、1 draw call）与 1 个 GPUParticles3D（`Leaves`，amount 64，量随画质 `particle_density` 缩放）。
- 每帧成本：无逐实例 CPU 更新；`_update_season` 以 0.25 s 节流，权重变化 <0.002 直接返回；`_apply_season_visuals` 只在参数变化时写材质/实例。
- 树冠稀疏化一次性写 44 个 Transform（仅在季节权重跨过阈值时）；花/叶卡/灌木同理。
- 正式数值对比统一放到阶段 6 性能矩阵（四季×天气的对照），本阶段只保证结构成本可忽略。

## 8. 已知限制

1. 地形顶点色不随季节变化（`world._terrain_color` 是烘焙色），冬季地表仍偏绿；只靠草 tint 与雾/光去饱和。若要真正的冬季地表需要给地形加 `ground_tint` 顶点/材质参数，列入后续可选优化。
2. 隐藏实例是把 basis 缩到 0.0001，仍在 MultiMesh 缓冲中（44/80 量级，成本可忽略）；不用 `visible_instance_count` 是为了避免按生成顺序成片消失。
3. 大树与背景树共用 `canopy_keep` 参数，冬季背景树也变稀疏；目前视觉可接受，未做逐树差异。
4. 树的“裸枝”是保留 10% 残冠 + 露出既有枝干几何，不是新增冬季枝干模型；树冠本身是 44 个 blob 的风格化造型。
5. 花是整实例显隐（按物种），没有“渐开/渐谢”的逐花动画；季节边界处靠连续权重让花量平滑变化。
6. 冬季红梅是 30 个低多边球簇，风格化表现，不追求逐朵花/花蕊；只在冬季权重高时出现。
7. 未实现积雪与天气（阶段 5/6），冬季目前只有季节色调。

## 9. 交付物与提交

- 新增：`scripts/isle_season.gd`、`tools/probe_p8_season.gd`、本报告、13 张截图。
- 修改：`scripts/main.gd`、`shaders/toon.gdshader`、`scripts/fx.gd`。
- 提交与 tag：见 git 历史（`P8 阶段4：四季视觉联动…`，tag `p8-4-seasons`）。
