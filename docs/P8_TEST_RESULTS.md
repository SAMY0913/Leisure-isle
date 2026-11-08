# P8 — Weather & Seasons：测试结果

> 版本：v1.0（2026-10-22，Asia/Shanghai）
> 分支：`p8-weather-seasons`；冻结 tag：`p8-weather-seasons-freeze-20261022`
> 截图清单：`开发产物/p8/shots/MANIFEST_p8.md`；总体说明见 `docs/P8_REPORT.md`。
> 所有测试均可离线复跑，不依赖现实日期/时刻/联网。

---

## 1. 环境

| 项 | 值 |
|---|---|
| 工程 | `D:/休闲小岛幻境/游戏工程` |
| 引擎 | Godot 4.7.2-stable（Forward+，console 版） |
| 系统 | Windows 10 专业版 |
| GPU | NVIDIA GeForce RTX 2060（驱动 32.0.16.1742） |
| 分辨率 | 1600×900（截图/性能）；headless 用于 selftest/探针 |
| 基线提交 | `ae9d104`（`p7-v4-islander`） |
| P8 分支 | `p8-weather-seasons` |
| 默认画质 | quality 2（高 · 精致） |

---

## 2. 结果总览

| 类别 | 结果 |
|---|---|
| headless 自测 | **71/71 passed**（P8 新增 18 条） |
| P8 探针 | **6195 项检查 / 0 失败** |
| 旧探针抽查 | **全部通过**（详见 §4） |
| 截图验收 | **46 张**（月球 10 + 四季 13 + 天气面板 5 + 天气视觉 15 + 生态 3） |
| P8 性能 | 大雨 +0.35 ms / 台风 +0.17 ms / 雪 +0.10 ms（默认机位 q2），均在 +2.0 ms 预算内 |
| 失败/阻塞项 | 无 |

---

## 3. 自测（selftest）

命令：

```powershell
& "D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe" --headless --path "D:/休闲小岛幻境/游戏工程" -- --selftest
```

结果：`[TEST] RESULT 71/71 passed`（exit 0）。最后日志：`开发产物/p8/logs/selftest_final.log`；各阶段日志亦保留（`selftest_stage5.log`、`selftest_stage7c.log`、`selftest_stage7d.log`）。

P8 新增 18 条断言（全部 PASS）：

| 阶段 | 断言 |
|---|---|
| 3 日历/暂停 | P8 公历跨闰日/跨年推进；P8 可见暂停按钮与空格共享状态；P8 暂停冻结权威时钟；P8 日历编辑后跳转即时生效；P8 跨年跳转进入合法状态；P8 日历收折恢复面板高度 |
| 3.2 月球 | P8 月相随机跳日期更新；P8 月球可见性由真实高度决定 |
| 4 四季 | P8 四季视觉参数与日历联动；P8 冬季树冠实例按比例收起；P8 冬季红梅花簇只出现在冬季 |
| 5 天气 | P8 天气状态契约与季节合法性；P8 暂停冻结天气调度与过渡；P8 手动天气按季节合法且跨季回退；P8 天气面板展开收折与 H 同步 |
| 6 视觉 | P8 降水系统与室内剔除数据就绪；P8 低画质仍保留降水且积雪随降雪累积 |
| 7 生态 | P8 生态天气上下文与雨天船只停航 |

原有 53 条断言全部保持 PASS（无回归）。

---

## 4. 探针

命令模板：

```powershell
& "D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe" --headless --path "D:/休闲小岛幻境/游戏工程" --script res://tools/<probe>.gd
```

### 4.1 P8 新增探针

| 探针 | 结果 | 耗时 | 覆盖 |
|---|---|---|---|
| `probe_p8_calendar.gd` | `checks=2672 fail=0` → PASS | 80 ms | 公历/闰年/大小月/跨年/权重和/季节边界/jump clamp/日索引 |
| `probe_p8_moon.gd` | `233/233 passed, 0 failed` | — | A 相位时刻对 HKO；B 位置对 MET Norway；C 完整朔望月；D 月盘朝向；E 可见性契约 |
| `probe_p8_season.gd` | `checks=114 fail=0` → PASS | 12 ms | 四季表、权重混合、花/树/草参数、冬季红梅、跨季连续性 |
| `probe_p8_weather.gd` | `checks=3135 fail=0` → PASS | 208 ms | 13 类型/权重/合法性/确定性/轮次边界/过渡/暂停/手动/湿润积雪/跨季回退/状态契约 |
| `probe_p8_ecology.gd` | `checks=41 fail=0` → PASS | 23 ms | 岛民天气过滤、海鸥/帆船/萤火阈值、源码契约 |

合计：2672 + 233 + 114 + 3135 + 41 = **6195 项检查，0 失败**。

> **P8.1 注记**：P8 冻结口径为 weather **3135**（13 类）。P8.1-04 起天气合并为 12 类后，同一探针为 **checks=3145 fail=0**，合计为 2672 + 233 + 114 + 3145 + 41 = **6205**。详见 docs/P8_1_REFINEMENT_REPORT.md / P8_1_TEST_RESULTS.md。

### 4.2 旧探针抽查（回归）

| 探针 | 结果 |
|---|---|
| `probe_astro6.gd` | 423/0 PASS |
| `probe_astro_xcheck_t7.gd` | pass=2489 fail=0 skip=0 known_bug=0 PASS |
| `probe_water6.gd` | 18 项全 PASS，FAIL=0 |
| `probe_villager_integration.gd` | 74/74 passed |
| `probe_bird6.gd` | pass=47 fail=0 PASS |
| `probe_boat_p7v3.gd` | pass=169 fail=0 PASS |

### 4.3 关键断言摘要

- **日历**：闰年 1900/2000/2024/2026/2100 规则、12 月/1 月跨年、跳转越界 clamp、季节权重和恒 1、暂停时 `_sim_seconds` 不变。
- **月球**：八相时刻与 HKO 相差 ≤5 min；月出/月落/中天对 MET ≤3 min、方位 ≤1.0°、高度 ≤0.8°；完整周期 `Δλ` 回绕；新月日 18:00 高度必须在地平线下；月盘亮面方向与太阳投影一致。
- **天气**：同 seed 同时间结果确定；轮次长度 1–5 游戏小时且连续无缝；60 s 步长过渡 max_step<0.08（无硬切）；雪不在春/夏/秋、台风不在春/冬；暂停冻结；手动跨季回退；冬季自动雪占比 <6%。
- **生态**：雨天岛民出门廊（不淋雨）、强天气回室内但保留吃饭/睡觉区域；雨天海鸥停栖、帆船停航；萤火雨天 amount_ratio=0。

---

## 5. 截图验收

共 **46 张**（1600×900，固定模拟日期/时刻/天气，不依赖现实时间）。完整清单、条件与逐张结论见：

> `开发产物/p8/shots/MANIFEST_p8.md`

分组：

| 组 | 数量 | 目录 | 验收结论 |
|---|---|---|---|
| 月球八相 + 实景 | 10 | `开发产物/p8/moon/` | 相位形状/明暗方向/可见性正确；新月在地平线下无月 |
| 四季 wide/tree/garden + 红梅 | 13 | `开发产物/p8/seasons/` | 四季差异明确；冬季残冠/裸枝/枝梢红梅成立 |
| 天气面板 | 5 | `开发产物/p8/weather/` | 自动/手动、季节合法选项、胶囊并列、布局无空白 |
| 天气视觉 | 15 | `开发产物/p8/weatherfx/` | 晴/阴/雨/夜雨/台风/雪/树雪/夜雪/室内/地面/屋檐/水花/低画质/闪电/落叶 |
| 生态 | 3 | `开发产物/p8/ecology/` | 雨日门廊岛民、晴夜萤火、雨夜无萤火 |

---

## 6. 性能

条件：1600×900、RTX 2060、quality 2、VSync off、默认全岛机位；日志 `开发产物/p8/logs/p8perf_final.log`；`cpu_ms` 为 `Performance.TIME_PROCESS` 采样，噪声较大，**以 frame_ms/FPS 为准**。

| 场景 | FPS | frame_ms | objects | draw calls | VRAM(MB) |
|---|---|---|---|---|---|
| clear | 180.0 | 5.56 | 1928 | 1838 | 272.5 |
| overcast | 176.9 | 5.65 | 1928 | 1838 | 272.5 |
| heavy_rain | 169.2 | 5.91 | 1943 | 1853 | 272.6 |
| thunder | 176.7 | 5.66 | 1932 | 1842 | 272.6 |
| heavy_snow | 176.6 | 5.66 | 1929 | 1839 | 272.6 |
| typhoon | 174.5 | 5.73 | 1931 | 1841 | 272.6 |
| heavy_rain q0 | 177.0 | 5.65 | 1930 | 1840 | 168.9 |
| heavy_rain q4 | 106.6 | 9.38 | 1931 | 1841 | 625.9 |

预算核对：

| 预算项 | 计划 | 实测 | 结论 |
|---|---|---|---|
| frame_ms 增量（雨/雪/台风，q2） | ≤ +2.0 ms | +0.35 / +0.10 / +0.17 ms | ✅ |
| 新增 draw call | ≤ +8 | +15（大雨） | ⚠️ 超预算，已记录 |
| 常驻节点 | ≤ +12 | +15 | ⚠️ 超预算，已记录 |
| VRAM 增量 | ≤ +40 MB | +0.1 MB（q2） | ✅ |
| 低画质降雨可辨识 | 是 | q0 大雨截图 + 177 FPS | ✅ |

说明：
- 与阶段 1 基线（不同机位/时刻）不可直接相减；上表为 P8 内部一致口径的对比。
- 未记录 P95；未覆盖近景/飞行/室内/低机位性能矩阵（这些场景有截图，但无 FPS 表）。
- q4 的 625.9 MB 主要来自画质档（MSAA/渲染比例），不是天气增量。

---

## 7. 覆盖矩阵与未覆盖项

### 已覆盖
- 日历：闰年/大小月/跨年/跳转 clamp/暂停冻结/现实模式只读语义（代码级）。
- 月球：4 个朔望月 × 4 主相、12 天升落/中天/方位、8 相渲染、新月不可见、完整周期。
- 四季：四季 × 三机位截图、边界权重、跨季参数连续性、冬季红梅/残冠、花量/草色/落叶。
- 天气：13 类型 × 季节合法性、自动权重/确定性/最短-最长轮次/过渡、暂停、跳日期、手动跨季回退、湿润/积雪趋势、状态契约。
  - **P8.1 注记**：P8.1-04 起天气类型为 **12 类**（windy 已并入 strong_wind 的强风状态），自动雪权重为 0、雪仅冬季手动可选；对应 `probe_p8_weather` 为 3145 项检查。详见 docs/P8_1_REFINEMENT_REPORT.md / P8_1_TEST_RESULTS.md。
- 视觉：雨（日/夜/近景/屋檐/水花/室内/低画质）、雪（日/夜/树/积雪）、台风、雷暴闪电、落叶风场。
- 生态：岛民 4 类天气场景、海鸥、帆船、炊烟、萤火（晴/雨）。
- 兼容：旧探针抽查（天文/水波/岛民/海鸥/帆船）、selftest 原 53 条无回归。

### 未覆盖 / 限制
1. **P95 未统计**：p8perf 只输出均值 FPS/frame_ms。
2. **性能矩阵不完整**：未逐项测近景/飞行/室内/低机位；仅默认机位。
3. **画质矩阵不完整**：天气视觉性能只测 q0/q2/q4 的雨，雪/台风未逐档测。
4. **未重复 P7 的 12 分钟长时 soak**；P8 新增泄漏未单独做长跑（当前退出 ObjectDB 泄漏仍为 8 条，与 P7 相同）。
5. **现实时间模式**只做了代码语义与 selftest 覆盖，未做长时间实景截图。
6. **4K/其他分辨率**未覆盖。
7. 截图验收为人工目视 + 部分像素分析（月球亮面质心），不是逐像素自动化回归。

---

## 8. 证据与复跑

### 日志
- `开发产物/p8/logs/selftest_final.log`（最终 71/71）
- `开发产物/p8/logs/p8moon_stdout.log`、`season_stdout.log`、`p8weather_stdout.log`、`p8wfx_stdout.log`、`p8eco_stdout.log`（截图运行）
- `开发产物/p8/logs/p8perf_final.log`（性能）
- `开发产物/p8/logs/baseline_perf_stdout.log`（阶段 1 基线）

### 一键复跑（PowerShell）

```powershell
$EXE = "D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe"
$P   = "D:/休闲小岛幻境/游戏工程"

& $EXE --headless --path $P -- --selftest

foreach ($p in "probe_p8_calendar","probe_p8_moon","probe_p8_season","probe_p8_weather","probe_p8_ecology") {
  & $EXE --headless --path $P --script "res://tools/$p.gd"
}

& $EXE --path $P --resolution 1600x900 -- --p8moon
& $EXE --path $P --resolution 1600x900 -- --p8seasons
& $EXE --path $P --resolution 1600x900 -- --p8weather
& $EXE --path $P --resolution 1600x900 -- --p8wfx
& $EXE --path $P --resolution 1600x900 -- --p8eco
& $EXE --path $P --resolution 1600x900 -- --p8perf
```

---

## 9. 结论

P8 的日历/月球/四季/天气/生态功能已全部实现并通过可复跑验证：self-test 71/71、P8 探针 6195/6195、旧探针抽查全绿、46 张固定日期截图人工复核通过。性能在默认机位 q2 下处于预算内（帧时间增量 ≤+0.35 ms），但 draw call/节点数小幅超预算、P95 与部分机位/画质性能矩阵尚未覆盖，已在 `docs/P8_REPORT.md` §9 与本文 §7 明确记录。P8 可冻结。
