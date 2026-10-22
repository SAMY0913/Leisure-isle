# P8.1 精修阶段测试结果

> **状态**：P8.1-02…P8.1-07 已验收；P8.1-08 全量回归与发布已完成（结果见 §9，代码冻结 **6de37c4** / 冻结 tag **p81-refinement-freeze-20261022**）。
> **口径**：所有数字取自各阶段证据目录中的日志/JSON 或 `git` 实际输出；阶段重跑同一探针不重复计数；性能只做同机 A/B。未跑/未闭环项标「未验证」。
> **配套文档**：`docs/P8_1_REFINEMENT_REPORT.md`（实施报告）、`docs/P8_1_REFINEMENT_PLAN.md`（计划书 + 实施状态回填）。
> **基线**：P8 冻结 tag `p8-weather-seasons-freeze-20261022` = `ae1c29d`；P8.1 阶段验收 HEAD = `00ff6c1`；-08 代码冻结 = **6de37c4**（另有构建修复 572af3d、.uid 补交 6de37c4），冻结 tag = **p81-refinement-freeze-20261022**。

## §1 结果总览

### 1.1 主自测（--selftest）

| 时点 | 通过/总数 | 说明 |
|---|---|---|
| P8 冻结基线 | **71/71** | P8 原有断言 |
| P8.1-02 后 | **73/73** | +2：冬季裸枝/红花与栖点季节门控断言 |
| P8.1-06 后（窗口模式） | **75/75** | +2：16 槽双池与壁炉/家具灯断言 |
| P8.1-08 回归（编辑器 headless） | **73/73** | headless 跳过 main.gd:3621-3623 两条真实鼠标拖动用例（故较窗口少 2） |
| P8.1-08 发布 exe | **73/73** | `发布/休闲小岛幻境.exe --headless -- --selftest` EXIT 0 |

日志：`开发产物/p81/evidence/p81_05/log_selftest_clean.txt`（73/73）、`开发产物/p81/evidence/p81_06/_reg_selftest.log`（75/75）；-08 最终：`开发产物/logs/p81_08/selftest.log`（编辑器 73/73）、`release_selftest3.log`（发布 exe 73/73）。

### 1.2 断言总量（去重后）

| 组 | 探针 | 断言数 |
|---|---|---|
| P8 核心回归 | probe_p8_calendar | 2672 |
| P8 核心回归 | probe_p8_weather（12 类口径） | 3145 |
| P8 核心回归 | probe_p8_moon | 233 |
| P8 核心回归 | probe_p8_season | 114 |
| P8 核心回归 | probe_p8_ecology | 41 |
| **P8 核心小计** | | **6205** |
| P7 契约回归 | probe_p7v2_perch | 265 |
| P7 契约回归 | probe_p7v2_bird | 681 |
| **P7 小计** | | **946** |
| P8.1 新增 | probe_p81_tree_bird | 149 |
| P8.1 新增 | probe_p81_whiteness | 34 |
| P8.1 新增 | probe_p81_wind | 117 |
| P8.1 新增 | probe_p81_lights | 147 |
| P8.1 新增 | probe_p81_datetime_wheel（headless） | 82 |
| **P8.1 小计** | | **529** |
| 窗口端到端 | probe_p81_datetime_wheel_ui | 82（80 pass / 2 warn / 0 fail） |
| 静态校验 | check_p81_04_static.py | 54 |
| **Godot 断言合计（不含窗口/静态）** | | **7680**（6205 + 946 + 529） |

> 口径说明：P8 核心的 3145 是 **-04 之后（12 类）** 的数字；P8 冻结报告中的同探针为 3135，差额来自 windy 删除后的测试矩阵调整。P7 的 265/681 为「-02 改动后仍通过」的契约回归，不属于 P8.1 新增断言，故单列。

### 1.3 失败与已知非绿

| 项 | 结果 | 性质 |
|---|---|---|
| probe_p7v2_light | **66 pass / 1 fail** | **预存在**：断言「路灯相对地形高度 ∈ [1.2,2.6] m」，实测第 3 盏 2.84 m 超界；用 HEAD `0136363` 干净副本逐条复核**同样 66/1、同一断言** |
| probe_cottage6 | **26 pass / 5 fail** | **预存在**：box1 center、solid coverage 5/7、beam occlusion 13/15、perches 12/14、attic lights found 0；HEAD 基线**同样 26/5，逐条相同** |
| probe_p7v2_flycam | **76 pass / 7 fail** | **预存在**：headless 无 GUI 鼠标注入，7 条均为鼠标/速度类断言；-08 回归纳入，基线复跑逐条相同 |
| probe_p8_weather `_run_step_independence` | 1 条非致命 `SCRIPT ERROR：Invalid call. Nonexistent 'String' constructor.` | **P8 起即存在**的历史瑕疵，不影响 PASS 判定 |
| probe_p81_datetime_wheel_ui | 2 warn（UI10 帧时间、桌面触摸） | 未证明项，保留为 U-02/U-04 |
| probe_p81_lights 视觉质量 | 147 条断言全过 | 截图内容质量不在断言覆盖内（-06 未验证 10 条之一） |

## §2 环境与命令

### 2.1 环境

| 项 | 值 |
|---|---|
| 引擎 | `D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe` |
| 版本串 | `Godot Engine v4.7.2.stable.official.ed1daf0bf` |
| 工程 | `D:/休闲小岛幻境/游戏工程`（分支 `p81-integration`） |
| 窗口验收副本 | `D:/p81_final_r2`（`git archive 0136363` + 复用 `.godot`） |
| 主机 | Windows，RTX 2060 级 GPU（P8 报告口径），VSync off 性能测试 |
| 日志根 | `开发产物/p81/evidence/<phase>/`①、`开发产物/logs/p81_lead/`② |

### 2.2 通用命令

```
:: 主自测（headless）
<engine> --headless --path . -- --selftest

:: 无头探针
<engine> --headless --path . --script res://tools/probe_<name>.gd

:: 窗口端到端（-07 阶段二）
<engine> --path . --script res://tools/probe_p81_datetime_wheel_ui.gd

:: 仅编译检查（不跑场景）
<engine> --headless --path . -- --check-only
```

> 说明：`--script` 方式下 `RenderingServer.global_shader_parameter_get` 返回 null（引擎 headless 限制），涉及 uniform 真实值的断言由窗口像素断言覆盖；探针内部对「不可回读」已做跳过处理并在输出中标注。

## §3 主自测断言的增量来源

| 阶段 | 新增断言 | 内容 |
|---|---|---|
| -02 | +2 | ①冬季 `canopy_keep≈0`、Canopy 实例全隐藏、`WinterPlum` 节点不存在、冬季红花可见/夏季隐藏；②栖点季节门控双向（winter_branch 冬开夏关、tree_branch 冬关夏开） |
| -06 | +2 | ①16 槽双池预算与激活数一致（五档）；②壁炉/吊灯/台灯在室内池激活且室外池不串光 |

其余阶段（-03/-04/-05/-07）以探针与窗口验收为主，selftest 无新增断言（沿用 73/73 口径）。

## §4 探针清单

| # | 探针文件 | 类型 | 覆盖 | 断言数 | 首次引入 |
|---|---|---|---|---|---|
| 1 | tools/probe_p8_calendar.gd | headless | 日历/时间跳转/跨年 | 2672 | P8 |
| 2 | tools/probe_p8_weather.gd | headless | 12 类天气/权重/参数/室内剔除 | 3145 | P8（-04 改写） |
| 3 | tools/probe_p8_season.gd | headless | 四季权重/视觉参数/红梅（-02 改写） | 114 | P8 |
| 4 | tools/probe_p8_moon.gd | headless | 月球轨迹/相位 | 233 | P8 |
| 5 | tools/probe_p8_ecology.gd | headless | 生态联动/雨天停航 | 41 | P8 |
| 6 | tools/probe_p7v2_perch.gd | headless | 栖点契约（36 点） | 265 | P7-V2 |
| 7 | tools/probe_p7v2_bird.gd | headless | 海鸥状态机/预约/落地 | 681 | P7-V2 |
| 8 | tools/probe_p7v2_light.gd | headless | 解析光预算/active | 67（66/1 预存在） | P7-V2（-06 更新契约常量） |
| 9 | tools/probe_cottage6.gd | headless | 小屋几何/栖点/阁楼灯 | 31（26/5 预存在） | P6 |
| 10 | tools/probe_lights_p7v3.gd | headless | 灯照契约 | EXIT 0 | P7-V3.1 |
| 11 | tools/probe_p81_tree_bird.gd | headless | 冬季树/红花/栖点门控/不传送/预约清理 | 149 | P8.1-02 |
| 12 | tools/probe_p81_whiteness.gd | headless | 季节白化/室内豁免/五档 | 34 | P8.1-03 |
| 13 | tools/probe_p81_wind.gd | headless | 落叶风场/萤火抑制/秋千受迫摆 | 117 | P8.1-05 |
| 14 | tools/probe_p81_lights.gd | headless + shots | 16 槽双池/五档预算/室内外隔离 | 147（+27 张截图模式） | P8.1-06 |
| 15 | tools/probe_p81_datetime_wheel.gd | headless | 滚轮组件/边界/状态机 | 82 | P8.1-07 阶段一 |
| 16 | tools/probe_p81_datetime_wheel_ui.gd | windowed | 滚轮端到端 UI（真实 isle.tscn） | 82（80/2/0） | P8.1-07 阶段二 |
| 17 | 开发产物/p81/weather/check_p81_04_static.py | Python 静态 | 12 类/权重和/LABELS-PARAMS 一致性 | 54 | P8.1-04 |

## §5 分阶段结果

### 5.1 P8.1-02 冬季裸树 / 裸枝栖点 / 屋前红花（07752e2）

| 测试 | 命令 | 结果 | 日志/证据 |
|---|---|---|---|
| selftest | `--headless -- --selftest` | **73/73 PASS** | 开发产物/p81/evidence/p81_05/log_selftest_clean.txt（同 HEAD 复跑） |
| 树/鸟专项 | `--script res://tools/probe_p81_tree_bird.gd` | **PASS pass=149 fail=0** | 开发产物/p81/evidence/p81_02/README.md、p81_03/_probe_p81_tree_bird.log |
| P8 季节回归 | `--script res://tools/probe_p8_season.gd` | **PASS checks=114 fail=0** | p81_03/_probe_p8_season.log |
| P7 栖点契约 | `--script res://tools/probe_p7v2_perch.gd` | **PASS pass=265 fail=0**（36 点契约） | p81_05/log_probe_p7v2_perch.txt |
| P7 海鸥回归 | `--script res://tools/probe_p7v2_bird.gd` | **PASS pass=681 fail=0** | p81_05/log_probe_p7v2_bird.txt |
| 窗口截图 | `-- --p81treebird` | 10 张 **1600×900（-08 重拍）** | p81_02/*.png |

### 5.2 P8.1-03 冬季白化与室内豁免（3add702）

| 测试 | 命令 | 结果 | 日志/证据 |
|---|---|---|---|
| selftest | `--headless -- --selftest` | **73/73 PASS** | p81_03/_probe_p81_tree_bird.log 同批回归；selftest 见 README |
| 白化专项 | `--script res://tools/probe_p81_whiteness.gd` | **checks=34 fails=0 PASS** | p81_03/_probe_p81_whiteness.log |
| P8 全量回归 | 5 个 P8 探针 | calendar 2672/0、season 114/0、weather 3145/0、ecology 41/0、moon 233/0 | p81_03/_probe_p8_*.log |
| 树/鸟回归 | probe_p81_tree_bird | PASS pass=149 fail=0 | p81_03/_probe_p81_tree_bird.log |
| 像素断言 | 室内一层/阁楼/窗外 | 一层白天 0.0000%、夜晚 **0.0056%（冬）/0.0065%（手动大雪）**；阁楼 0.0000%；窗外 **44.9786%（冬）/41.5265%（雪）**；口径：逐通道最大差 **>8/255**（Pillow）、全帧 1600×900；噪声基线 0.0053% | p81_03/diff_stats.json |
| 性能 | q2 A/B | clear **Δ −0.01 ms**；heavy_snow Δ +0.145 ms | p81_03/_run_p8perf*.log |

### 5.3 P8.1-04 天气权重校准（285648e）

| 测试 | 命令 | 结果 | 日志/证据 |
|---|---|---|---|
| 天气探针 | `--script res://tools/probe_p8_weather.gd` | **PASS checks=3145 fail=0 elapsed_ms=661** | 开发产物/logs/p81_lead/p8_weather.log；p81_03/_probe_p8_weather.log |
| 静态校验 | `python 开发产物/p81/weather/check_p81_04_static.py` | **checks=54 fail=0 / PASS / EXIT=0** | 本机复跑输出 |
| 主自测 | `--selftest` | 73/73（沿用同 HEAD 回归） | — |

### 5.4 P8.1-05 强风视觉（95263d0）

| 测试 | 命令 | 结果 | 日志/证据 |
|---|---|---|---|
| selftest | `--headless -- --selftest` | **73/73 PASS** | p81_05/log_selftest_clean.txt |
| 强风专项 | `--script res://tools/probe_p81_wind.gd` | **PASS pass=117 fail=0 checks=117** | p81_05/log_probe_p81_wind.txt |
| 回归 4 项 | p8_season / tree_bird / p7v2_perch / p7v2_bird | 全部 PASS（114、149、265、681） | p81_05/log_probe_*.txt |
| 性能 A/B | new vs legacy，180 帧×2 轮 | frame_ms **5.679 vs 5.667 = +0.012**（门 ≤+0.3 PASS）；CPU **9.615 vs 7.681 = +1.93 ms** | p81_05/log_p81windperf_clean.txt |
| 窗口截图 | `-- --p81wind` | 12 张 **1600×900（-08 重拍）** | p81_05/p81_wind_*.png + MANIFEST |

### 5.5 P8.1-06 照明（00ff6c1）

| 测试 | 命令 | 结果 | 日志/证据 |
|---|---|---|---|
| selftest | `--headless -- --selftest` | **75/75 PASS** | p81_06/_reg_selftest.log |
| 照明专项 | `--script res://tools/probe_p81_lights.gd --mode=checks` | **checks=147 fails=0 PASS** | p81_06/_probe_checks.log |
| P7 灯照契约 | `probe_lights_p7v3.gd` | EXIT 0 PASS | p81_06/_reg_probe_lights_p7v3.log |
| P7 灯预算 | `probe_p7v2_light.gd` | 66 pass / 1 fail（预存在，基线同） | p81_06/_reg_probe_p7v2_light.log |
| P6 小屋 | `probe_cottage6.gd` | 26 pass / 5 fail（预存在，基线同） | p81_06/_reg_probe_cottage6.log |
| 编译检查 | `-- --check-only`（main/probe） | EXIT 0 | p81_06/_check_main.log、_check_probe.log |
| 性能 A/B | 6 场景 ×3 次中位 | Δ clear −0.47、overcast +0.06、heavy_rain −0.89、thunder −0.32、heavy_snow **+0.60**、typhoon −0.33；q0 +0.03、q4 −0.08 | p81_06/_perf_compare.json |
| 窗口截图 | `--mode=shots` | 27 张正式 + 壁炉取证组 | p81_06/ |

### 5.6 P8.1-07 日期滚轮

| 阶段 | 命令 | 结果 | 日志/证据 |
|---|---|---|---|
| 阶段一（024da24） | `--headless --script res://tools/probe_p81_datetime_wheel.gd` | **PASS pass=82 fail=0，EXIT=0** | p81_07/probe_p81_datetime_wheel.log |
| 阶段二（0136363） | `--script res://tools/probe_p81_datetime_wheel_ui.gd`（窗口，1440×900 + 1600×900 复检） | **EXIT=0 total=82 pass=80 warn=2 fail=0 shots=9 耗时=44.0s** | p81_07_stage2/final_stage2_probe.log、final_stage2_result.json |

## §6 回归与契约

| 项 | 结果 | 说明 |
|---|---|---|
| P7-V2 栖点 36 点契约 | **265/0** | `world.build(parent, include_winter := false)` 默认保旧契约；main 显式传 true 得 41 点 |
| P7-V2 海鸥 | **681/0** | 含 zone 映射、槽位、预约 |
| P8 五探针 | 2672/233/114/3145/41 全绿 | -03 与 -05 两次全量复跑一致 |
| `--check-only` | EXIT 0 | 语法/编译 |
| 日志扫描 | global parameter removed=0、SCRIPT ERROR=0、shader error=0、NaN=0 | `f.is_null` 28 条为工程既有 shader cache 警告 |
| 预存在失败基线复核 | p7v2_light 66/1、cottage6 26/5 | 用 HEAD `0136363` 干净副本复跑，逐条相同 → 排除 -06 回归 |

## §7 性能结果

### 7.1 P8.1-03（q2、1600×900、VSync off）

| 场景 | 改动后 | 基线 HEAD | Δ |
|---|---|---|---|
| clear | 6.69 / 6.66（两轮） | 6.69 / 6.72 | **≈ −0.01 ms（报告口径）** |
| heavy_snow | 6.71 / 6.86 | 6.71 / 6.70 | **+0.145 ms（报告口径）** |
| 资源 | objects 1928、draw 1838、VRAM 272.5 MB | 同 | ±0 |

### 7.2 P8.1-05（q2、秋 2026-10-20 22:00、strong_wind、180 帧×2 轮）

| 版本 | frame_ms（两轮） | 均值 | CPU ms |
|---|---|---|---|
| new | 5.684 / 5.674 | **5.679** | 10.777 / 8.453 → 均值 9.615 |
| legacy | 5.689 / 5.645 | **5.667** | 8.419 / 6.943 → 均值 7.681 |
| Δ | | **+0.012 ms**（门 ≤ +0.3 PASS） | **+1.93 ms**（如实披露，未 profile） |
| objects/calls | new 768/748（轮 0） | legacy 772/752 | 无新增节点 |

### 7.3 P8.1-06（q2、1600×900、VSync off、3 次取中位）

| 场景 | 基线 HEAD | -06 后 | Δ |
|---|---|---|---|
| clear | 7.73 | 7.26 | **−0.47** |
| overcast | 7.49 | 7.55 | +0.06 |
| heavy_rain | 8.41 | 7.52 | −0.89 |
| thunder | 7.36 | 7.04 | −0.32 |
| heavy_snow | 6.90 | 7.50 | **+0.60（最大）** |
| typhoon | 7.87 | 7.54 | −0.33 |
| heavy_rain_q0 | 7.42 | 7.45 | +0.03（相对增量） |
| heavy_rain_q4 | 12.48 | 12.40 | −0.08 |

资源：draw **1838→1840（+2）**、常驻节点 **1928→1930（+2）**、VRAM **±0**；12→16 槽静态成本 task-11 实测 +0.068 ms。门限「所有场景 < +1.0 ms」通过；q0 FPS≥170 门未达（机器漂移，见报告 §6.7）。

### 7.4 P8.1-08 最终性能

-08 最终 A/B：**5 轮交替取中位**（1600×900、q2、VSync off；final = 6de37c4 代码，base = 0136363），日志 开发产物/logs/p81_08/perf_final_r0..r5.log、perf_base_r0..r5.log，汇总 perf_ab_summary.json。

| 场景（q2） | base ms | final ms | Δ |
|---|---|---|---|
| clear | 5.83 | 5.91 | **+0.08** |
| overcast | 5.87 | 6.03 | +0.16 |
| heavy_rain | 6.19 | 6.30 | +0.11 |
| thunder | 5.99 | 6.06 | +0.07 |
| heavy_snow | 5.87 | 5.94 | +0.07 |
| typhoon | 5.90 | 5.97 | +0.07 |
| heavy_rain_q0 | 5.85 | 6.02 | +0.17（FPS 170.9 → **166.1**，门 ≥170 未达） |
| heavy_rain_q4 | 9.58 | 9.55 | −0.03 |

资源：objects **+2**、draw **+2**、VRAM **±0.0 MB**。帧时间门（q2 ≤+1.0 ms）**PASS**；q0 FPS 门**条件通过**（D15：绝对 166.1 未达，相对 +0.17 ms 在帧时间预算内）。

## §8 截图矩阵

| 阶段 | 数量 | 分辨率 | 位置 |
|---|---|---|---|
| -02 冬季/四季 | **10** | 1600×900（-08 重拍） | 开发产物/p81/evidence/p81_02/ |
| -03 白化 | 目录顶层 **125** 张 PNG；README 正式矩阵口径 80（46 clear + 25 snow + 9 diff） | 1600×900 | 开发产物/p81/evidence/p81_03/ |
| -05 强风视觉 | **12** | 1600×900（-08 重拍） | 开发产物/p81/evidence/p81_05/ |
| -06 照明 | 目录 **53** 张 PNG（27 张正式矩阵 + 壁炉遮挡取证/对比组） | 2560×1440 | 开发产物/p81/evidence/p81_06/ |
| -07 阶段二 UI | **9** | 1440×900 与 1600×900 | 开发产物/p81/evidence/p81_07_stage2/ |
| **合计（正式口径）** | 10 + 80 + 12 + 27 + 9 = **138**；-08 重拍原始文件 = 10 + 125 + 12 = **147 张** | | |
| -08 最终重拍 | **147**（-02 10、-03 125、-05 12；1600×900）；-06 保持 27 张正式矩阵未重拍 | 1600×900 | 各阶段目录（原地重拍，日志 开发产物/logs/p81_08/shots_treebird.log、shots_white.log、shots_wind.log） |

> 限制：-08 已把 -02/-03/-05 统一重拍为 **1600×900**；-06 为 2560×1440 且未重拍；**不做跨分辨率像素 diff**。P8 冻结的 46 张固定日期截图**未重拍**（任务书要求保护冻结证据，U45），最终以 P8.1 三组 147 张为基线。

## §9 P8.1-08 最终回归

### 9.1 验收门 G8 回填结果

| 验收门 | 要求 | 实测 | 结论 |
|---|---|---|---|
| G8-A 主自测 | 编辑器 headless ≥73/73 且 EXIT 0；发布 exe 同 | 编辑器 headless **73/73** EXIT 0（窗口模式 75/75）；发布 exe **73/73** EXIT 0 | **PASS** |
| G8-B 全量探针 | 17 项 headless：15 PASS/exit0 + 2 项预存在失败（与基线一致） | 15 项 PASS/exit0；p7v2_light 66/1、p7v2_flycam 76/7，基线 0136363 复跑逐条相同 | **PASS（含预存在）** |
| G8-C 性能 | q2 6 场景 Δ ≤ +1.0 ms；q0 FPS ≥170 | 5 轮中位 q2 Δ ≤ **+0.17 ms**；q0 FPS **166.1** vs base 170.9 | **条件通过**（帧时间 PASS；q0 FPS 未达，见 D15） |
| G8-D 截图 | P8.1 核心矩阵最终重拍、分辨率统一 | -02 10 + -03 125 + -05 12 = **147 张 1600×900**；-06 27 张未重拍；P8 冻结 46 张未覆盖（U45）；G3 像素差（逐通道 >8/255、1600×900）：室内白天 0.0000%、夜 0.0056%/0.0065%、阁楼 0.0000%、窗外 44.9786%/41.5265%（噪声基线 0.0053%） | **条件通过**（P8.1 矩阵齐全；P8 冻结未覆盖） |
| G8-E 发布包 | 真实构建并运行验证 + sha256 | 117,238,104 B / sha256 `c40376ad…5d62b668`；quit EXIT 0、selftest 73/73 | **PASS** |
| G8-F 冻结 | 代码冻结 commit + tag + 工作树状态 | 代码冻结 **6de37c4**；tag **p81-refinement-freeze-20261022**（指向其后文档提交） | **PASS（待文档提交）** |

> **G8 总判定：条件通过** —— G8-A/B/E/F PASS；G8-C q0 FPS 未达（D15）、G8-D P8 冻结 46 张未覆盖（U45），均已在报告 §10/§12 记录。

### 9.2 -08 最终回归（17 项 headless）

日志根：`开发产物/logs/p81_08/`；逐项汇总：`summary_20261022_155832.txt`。

| # | 命令 | 结果 | 备注 |
|---|---|---|---|
| 1 | `-- --selftest`（编辑器 headless） | **73/73** RESULT，EXIT 0 | 跳过 main.gd:3621-3623 两条鼠标拖动用例 |
| 2 | probe_p8_calendar.gd | 2672 pass / 0 fail，EXIT 0 | |
| 3 | probe_p8_weather.gd | 3145 pass / 0 fail，EXIT 0 | 12 类口径 |
| 4 | probe_p8_moon.gd | 233 pass / 0 fail，EXIT 0 | |
| 5 | probe_p8_season.gd | 114 pass / 0 fail，EXIT 0 | |
| 6 | probe_p8_ecology.gd | 41 pass / 0 fail，EXIT 0 | |
| 7 | probe_p81_tree_bird.gd | 149 pass / 0 fail，EXIT 0 | |
| 8 | probe_p81_whiteness.gd | PASS，EXIT 0 | |
| 9 | probe_p81_wind.gd | 117 pass / 0 fail，EXIT 0 | |
| 10 | probe_p81_lights.gd --mode=checks | 147 pass / 0 fail，EXIT 0 | |
| 11 | probe_p81_datetime_wheel.gd | 82 pass / 0 fail，EXIT 0 | headless |
| 12 | probe_p7v2_perch.gd | 265 pass / 0 fail，EXIT 0 | |
| 13 | probe_p7v2_bird.gd | 681 pass / 0 fail，EXIT 0 | |
| 14 | probe_p7v2_light.gd | **66 pass / 1 fail**，EXIT 1 | 预存在，基线相同 |
| 15 | probe_p7v2_flycam.gd | **76 pass / 7 fail**，EXIT 1 | 预存在，headless 鼠标/速度断言 |
| 16 | probe_p7v3_lights.gd | exit 0 | |
| 17 | probe_p7v3_boat.gd | 169 pass / 0 fail，EXIT 0 | |
| 附 | probe_p81_datetime_wheel_ui.gd（窗口，非 headless） | 82：pass 80 / warn 2 / fail 0 | U-02/U-04 保留 |

### 9.3 发布包构建验证

| 项 | 值 |
|---|---|
| 产物 | `发布/休闲小岛幻境.exe` = `构建输出/休闲小岛幻境.exe`，**117,238,104 B** |
| sha256 | `c40376ad2dda1d8eb2e9848ca8a2ce00e4c1a841a03444fa9e9b80ef5d62b668` |
| 启动验证 | `--headless --quit` → **EXIT 0**（日志 release_quit3.log） |
| 自测验证 | `--headless -- --selftest` → **73/73 EXIT 0**（日志 release_selftest3.log） |
| 旧包备份 | `开发产物/backup/release_pre_p81/休闲小岛幻境_p7v3_发布.exe`，116,917,880 B，sha256 `cf97372108dcaec55292b6b473e4d9e26fcef456a315f5ae293f3478ca84667c`；旧包可启动、自测 53/53（证明缺陷自 P7-V3.2 起潜伏，D14） |
| 构建注意 | 导出时 TEMP/TMP 必须指向可写目录（本机默认 Temp 写 project.binary 失败→嵌入式 pck 损坏→exe 报 Corrupted header）；复现用 `TMP/TEMP=D:/休闲小岛幻境/开发产物/tmp_export` |

## §10 复现命令清单

```
:: 1) 主自测
<engine> --headless --path . -- --selftest

:: 2) P8 核心回归（5 个）
<engine> --headless --path . --script res://tools/probe_p8_calendar.gd
<engine> --headless --path . --script res://tools/probe_p8_weather.gd
<engine> --headless --path . --script res://tools/probe_p8_moon.gd
<engine> --headless --path . --script res://tools/probe_p8_season.gd
<engine> --headless --path . --script res://tools/probe_p8_ecology.gd

:: 3) P7 契约回归
<engine> --headless --path . --script res://tools/probe_p7v2_perch.gd
<engine> --headless --path . --script res://tools/probe_p7v2_bird.gd
<engine> --headless --path . --script res://tools/probe_p7v2_light.gd

:: 4) P8.1 新增
<engine> --headless --path . --script res://tools/probe_p81_tree_bird.gd
<engine> --headless --path . --script res://tools/probe_p81_whiteness.gd
<engine> --headless --path . --script res://tools/probe_p81_wind.gd
<engine> --headless --path . --script res://tools/probe_p81_lights.gd --mode=checks
<engine> --headless --path . --script res://tools/probe_p81_datetime_wheel.gd
<engine> --path . --script res://tools/probe_p81_datetime_wheel_ui.gd     :: 窗口端到端

:: 5) 静态校验
python 开发产物/p81/weather/check_p81_04_static.py

:: 6) 发布包构建与验证（-08；TEMP/TMP 必须可写，见 §9.3）
::    用 Godot 导出 Windows 预设（export_presets.cfg）到 构建输出/休闲小岛幻境.exe
copy 构建输出\休闲小岛幻境.exe 发布\休闲小岛幻境.exe
发布\休闲小岛幻境.exe --headless --quit
发布\休闲小岛幻境.exe --headless -- --selftest
```

> 工程根目录 = `D:/休闲小岛幻境/游戏工程`；性能测试必须用「同 HEAD 干净副本 + 复用 .godot」避免工作树脏文件影响。

## §11 证据索引与限制

### 11.1 索引

| 阶段 | 目录 | 关键内容 |
|---|---|---|
| -02 | 开发产物/p81/evidence/p81_02/ | README.md（命令/断言/截图清单）+ 10 张 PNG |
| -03 | 开发产物/p81/evidence/p81_03/ | README.md（392 行）+ 探针日志 + diff_stats.json + 截图 |
| -04 | 开发产物/logs/p81_lead/p8_weather.log；开发产物/p81/weather/ | 3145/0 日志；静态校验脚本与数据 |
| -05 | 开发产物/p81/evidence/p81_05/ | REPORT_p81_05.md + MANIFEST + 8 份日志 + 12 张 PNG |
| -06 | 开发产物/p81/evidence/p81_06/ | REPORT_p81_06.md（292 行）+ MANIFEST + 探针/性能/取证日志 + 53 张 PNG |
| -07 | 开发产物/p81/evidence/p81_07/、p81_07_stage2/ | 阶段一 REPORT + 探针日志；阶段二 REPORT + final_stage2_probe.log + result.json + 9 张 PNG |
| -08 | 开发产物/logs/p81_08/；发布/、构建输出/、开发产物/backup/release_pre_p81/ | 17 探针日志 + 性能 final/base 各 5 轮 + summary_20261022_155832.txt + 发布 exe 验证日志（quit/selftest）+ 147 张重拍截图（原地覆盖 -02/-03/-05） |

### 11.2 限制

1. 探针只覆盖逻辑与几何断言，**不覆盖截图观感质量**（比例、构图、过曝）。
2. headless 下 global shader parameter 不可回读，涉及真实 uniform 数值的断言由窗口像素断言替代；未覆盖的以「未验证」记录。
3. 性能全部为同机 A/B；P8 冻结报告的绝对 ms 与本阶段不可直接比较（漂移 +1.13 ms 量级）。
4. 多分辨率（1440×900 vs 1600×900 vs 2560×1440）截图不做像素 diff。
5. 预存在失败（p7v2_light 66/1、p7v2_flycam 76/7、cottage6 26/5）不因 P8.1 转绿，需在 P8.2 或后续修断言/几何。

## §12 回填记录（占位符已清零）

| 占位符 | 回填值（摘要） | 落点 |
|---|---|---|
| FREEZE_COMMIT | 6de37c4（代码冻结；tag 指向本轮文档提交） | 标题下、§9.1 |
| FREEZE_TAG | p81-refinement-freeze-20261022 | 标题下、§9.1 |
| FINAL_SELFTEST | 编辑器 headless 73/73（窗口 75/75）；发布 exe 73/73 | §1.1、§9.1、§9.3 |
| FINAL_PROBES | 17 项：15 PASS/exit0 + 2 预存在（66/1、76/7） | §1.3、§9.1、§9.2 |
| FINAL_PERF | 5 轮中位；q2 Δ ≤+0.17 ms（PASS）；q0 FPS 166.1 vs 170.9（条件通过） | §7.4、§9.1 |
| FINAL_SCREENSHOTS | 重拍 147 张（-02 10 + -03 125 + -05 12，1600×900）；P8 冻结 46 张未覆盖 | §8、§11.1、§9.1 |
| FINAL_RELEASE | 发布 exe 117,238,104 B / sha256 c40376ad…；quit EXIT 0、selftest 73/73 | §9.3、§11.1 |

> 校验：以「双花括号 + 大写名」模式 grep 全文**无输出（0 残留）**。

---

**文档备注**：本文为 P8.1-08 文档合并产物；所有数字来自上列日志/JSON/报告，未运行 Godot、未改代码/证据、未做 git 写操作。
