# P8.2-05 日期时间滚轮窗口端到端验证（NOTES）

分支 `p82-integration`，基线 `ddcde3a`（P8.1-08）。本文件随 P8.2-05 交付提交，供 Lead 汇总进 P8.2 总报告。

所有引擎运行唯一入口（工程根 `D:/休闲小岛幻境/游戏工程`）：

```bash
cd "D:/休闲小岛幻境/游戏工程"
bash "D:/休闲小岛幻境/开发产物/p82/run_godot.sh" <引擎参数>
```

证据（日志 / JSON / 截图）全部在仓库外：`D:/休闲小岛幻境/开发产物/p82/05_wheel/`。
本文件所有数字都取自**带 `exclusive window` 标记**的干净独占运行（串行器 v2 会在拿到锁后再等所有既有 Godot 进程退出），
唯一例外在 §3.5 明确标注（v1/v2 的 marker 不证明无并发）。

---

## 0. 结论摘要

| 项 | 内容 | 结论 | 关键数字 |
|----|------|------|----------|
| U-02 | 日历面板帧开销（UI10 重测，v3 干净窗口） | **WARN（可测但不可分辨）** | 逐对交错 12 对：Δp50 中位 **+0.400 ms**、均值 +0.380±0.098、95%CI 上限 +0.572 ms、正号 **11/12**；A/A 噪声 \|Δp50\| 中位 0.729 ms；结构增量 Δdraw **+92**、Δobjs **+649**。真实增量约 +0.4 ms，仍大于 0.3 ms 判据且与噪声同阶，**不宣称 PASS** |
| U-02 | 采样工具可信性（P-5 复核） | **已确认 P-5** | windowed 下 `Performance.TIME_PROCESS` 120 帧仅 **2 个唯一值**（量化成常量），不可作帧开销判据；已改用逐帧墙钟 `Time.get_ticks_usec` 差值（p50/p95/avg）+ `Performance.TIME_FPS` 与墙钟 fps 交叉校验 |
| U-03 | 窗口尺寸 × 高 DPI | **PASS（模拟）+ 披露** | 4 档窗口 canvas 恒 1600×900、k=0.800/1.000/1.200/1.600，面板 top=156/bottom=816 全在窗内，物理面板 288×528 / 360×660 / 432×792 / 576×1056，五档命中全部正确；无高 DPI 真机（screen_scale=1.000、dpi=120、max_scale=1.0） |
| U-04 | 桌面触摸 | **PASS（合成）+ 披露** | 合成 ScreenTouch 点击日列下一行 → 日期 +1（12:19→次日 12:19）；合成 12 步 ScreenDrag 上拖（断言口径=值改变且收敛）→ 小时变化（12:19→14:19，busy=false；落位行数受注入步速影响，本轮含 1 行惯性）；本机无触屏（`is_touchscreen_available()=false`） |
| U-05 | 滚轮吸附手感 | **PASS** | 吸附 47 步/0.392 s（解析期望 0.392 s，比值 1.00）、超调 0.0000 行；甩动 2.2 行/s 惯性滑行 -0.347（期望 0.367，比 0.95）、6.0 行/s → -1.003（期望 0.991，比 1.01）；阈值边界实测 1.3 行/s；年列橡皮筋 0.25 行、22 步回弹 |
| U-06 | TAB 切列 | **PASS** | Tab 序列 year→month→day→hour→minute→year→month；→/← 键逐列移动并在 minute/year 夹取；Tab 不误触天文历 |
| U-07 | 多面板并发 | **PASS** | 时间+日历+天文历+天气+性能 5 面板同开不崩，并发热键 notch 生效（30→29）且焦点保持，全关后滚轮隐藏、busy=false |
| U-08 | 跨午夜 / 跨年 | **PASS（sim 自然跨越）+ WARN（real 同步注入）** | sim（6 秒/秒）跨年 2026-12-31 23:59→2027-01-01 00:00、跨月 01-31→02-01、闰日 02-28→02-29，HUD clock/date 与日列上限同步；real 模式 23:59:59→+6 s = 2027-01-01 00:00:05（同步注入，非真实等待） |
| U-09 | 长时运行 / 反复开合 | **PASS** | 60 次开合 + 200 次交互：hud 节点 120→120、静态节点 1381→1381（Fx 已排除）、整树 Δ0、新增非 Fx 节点 []、3 条信号连接数全不变、objects 2326→2298（-28）、内存 +1.21 MB；1200 帧长跑草稿=权威、帧间隔 p50 **7.21 ms** / p95 **8.70 ms** / avg 7.42 ms |
| U-10 | 极端年份 / 跨年 / 闰年 / 月末 | **PASS** | 跳转 1999-12-31 23:59 / 2000-02-29 / 2001-01-31 / 0001-01-01 / 9999-12-31 全生效；2100-02-29 clamp→02-28（`days_in_month(2100,2)=28`、`(2000,2)=29`）；2001-01-31 月+1→02-28；年列 1/9999 边界 notch 不越界 |
| U-11 | 失焦 / 最小化 / 多显示器 | **PASS（单屏）+ 披露** | 失焦/回前台后 notch 正常（40→39）；最小化→恢复 1440×900，面板 (34,156 360×660) 不变；本机 screen_count=1（另有一块 Oray 虚拟显示，未作为第二物理屏暴露），多屏真机 SKIP |
| U-12 | 键重复率（key echo） | **PASS + 披露** | echo=true ×10 经 handler 与 GUI 焦点路由均不改值（10→10）；真实 KEY_DOWN ×10 → +10；真机 OS 自动重复率无法自动化测量（已披露） |
| P-1 | 合成输入需 `Input.warp_mouse` | **PASS（环境记录）** | 不 warp 时 hover 命中不稳定；warp 后 hover/焦点/点击全部确定 |
| P-2 | 假 dirty | **PASS（不复现）** | 打开 0.4 s 内 dirty 两次采样均为 false；草稿=权威 |
| P-3 | 双 notch | **PASS（已修在 P8.1，复核通过）** | 真实滚轮 pressed+released = 1 notch；只有 released 的事件被忽略；WHEEL_DOWN = +1 |
| P-4 | FLICK_THRESHOLD 字面量与常量重复 | **已修（去重，数值不变）** | `end_drag` 的 `1.2` 改为引用 `FLICK_THRESHOLD`（=1.2）；是否调轻到 0.67 属手感设计决策，本轮不改 |
| P-5 | `Performance.TIME_PROCESS` windowed 失真 | **已确认 + 已替换** | 唯一值=2；改用墙钟差值 + TIME_FPS/墙钟 fps 交叉校验 |
| P-6 | UI1 滚轮宽断言区间 | **已按 316→324 区间化** | 实测 canvas 宽 324（68+46×4+6×4+20），断言区间 316..340 |

回归：headless 滚轮探针 **82/82 PASS**、窗口滚轮探针 **82 项 80 pass / 2 warn / 0 fail**、
`--selftest 73/73 passed`、行为探针 **87 项 80 pass / 6 warn / 1 skip / 0 fail**、DPI 探针 **12 项 10 pass / 2 warn / 0 fail**。

---

## 1. 修改文件与原因

### 1.1 `scripts/ui_datetime_wheel.gd`（1 行 + 2 行注释，唯一生产代码改动）

唯一改动：结束拖动时判定是否进入惯性，把重复的字面量改为引用已有常量（**数值与行为完全不变**）。

```gdscript
# P-4：原为硬编码字面量 1.2，与常量 FLICK_THRESHOLD 重复；改为引用常量（数值不变，行为不变）。
# 是否把阈值调轻到 0.67 属于手感设计决策，本轮不动数值。
if absf(_ema_vel) > FLICK_THRESHOLD:
```

- 未改任何物理参数（ω=18、ζ=1、摩擦 6、收敛 0.01/0.05、橡皮筋 0.25、拖动阈值 3、EMA 0.35），
  未改 841 行结构，未动布局常量与列宽。
- 阈值扫描实测边界 1.3 行/s（EMA 滞后于瞬时速度），与常量 1.2 一致；改动前后数值相同，故未做 A/B 手感对比
  （无行为差异可对比），仅做去重与可读性修正。

### 1.2 `tools/probe_p81_datetime_wheel_ui.gd`（P8.1 窗口探针，按 Lead 指令修订）

两处改动：

1. `OUT_DIR` 从 `D:/休闲小岛幻境/开发产物/p81/evidence/p81_07_stage2` 改为
   `D:/休闲小岛幻境/开发产物/p82/05_wheel/p81_ui_regression` —— P8.1 冻结证据只读，P8.2 结果不得覆盖。
   仅改输出常量，探针逻辑其余部分不动（文件头注释同步说明）。
2. `_ui10()` 帧时间测量整段重写（原本三轮 ABBA 长段采样，在 windowed 下被 `TIME_PROCESS` 失真 + 段间漂移淹没）：
   关 vsync + `Engine.max_fps=0`，**逐对交错** 12 对（每对 A=面板全关 40 帧、B=日历打开 40 帧，对间关面板并把鼠标移到远离面板处），
   再做 8 对 A/A 对照估噪声，输出 Δp50 的均值/中位/95%CI/正号数、Δdraw/Δobjs、TIME_FPS 与墙钟 fps、`TIME_PROCESS` 唯一值个数。

### 1.3 新增探针（2 个，均为窗口模式，可从命令行复跑）

| 探针 | 覆盖 | 项数 |
|------|------|------|
| `tools/probe_p82_datetime_behavior.gd` | P-2 假 dirty、U-05 手感、U-12 echo、U-06 TAB/焦点、U-07 并发、U-08 跨午夜/跨年、U-10 极端年份、U-11 失焦/最小化/多屏、U-09 长时运行、U-04 桌面触摸 | 87 |
| `tools/probe_p82_datetime_dpi.gd` | U-03：4 档窗口尺寸的物理/画布几何 + 命中；`content_scale_factor` 1.0/1.2/1.25/1.5/2.0 压力 | 12 |

两个探针的输出常量均为 `D:/休闲小岛幻境/开发产物/p82/05_wheel`（已 grep 核对，未写 p81/p8/发布/构建输出）。
**未修改**：`main.gd`、`hud.gd`、`cottage.gd`、`world.gd`、`isle_season.gd`、`fx.gd`、`shaders/`、`isle_quality.gd`、`.godot`。

---

### 1.4 `tools/probe_p82_datetime_frame.gd`（**重写补入**，非原文件恢复）

- 背景：P8.2-05 第一版帧/几何采样脚本（原名即 `probe_p82_datetime_frame.gd`）在后续重构中被我删除且**从未入库**（winter §10 审计发现：`开发产物/p82/05_wheel/probe_p82_datetime_frame_result.json` 与 9 张截图在 `tools/` 下无可复跑脚本）。
- 处理：按**同一口径重写为最小复现版**（约 250 行），复现三件事：① P-5（windowed 下 `Performance.TIME_PROCESS` 取值被量化 → 不可作判据）；② 朴素长段 ABBA（每段 240 帧、vsync 关）的噪声底 > 信号（这是后来改用逐对交错 + A/A + 95%CI 的动因）；③ 四档窗口尺寸下的 `visible_rect`/面板/滚轮几何（expand 语义）。
- 诚实标注：**原文件内容不可恢复**（未入库、已删，git 无 blob）；本文件是等价重写，**不产生新的性能结论**（性能结论一律以 UI10 为准），输出到 `_repro.log/_repro.json`，不与第一版 JSON 混用。
- 运行：`bash "D:/休闲小岛幻境/开发产物/p82/run_godot.sh" --path . --script res://tools/probe_p82_datetime_frame.gd`（**必须窗口**；headless 会打印 SKIP 后退出 0）。
## 2. 复现步骤（每条都能独立重跑）

### 2.1 UI10 帧时间（可信方法）

```bash
cd "D:/休闲小岛幻境/游戏工程"
bash "D:/休闲小岛幻境/开发产物/p82/run_godot.sh" --path . --script res://tools/probe_p81_datetime_wheel_ui.gd
# 看日志 D:/休闲小岛幻境/开发产物/p82/05_wheel/_run_p81_ui_exclusive.txt 里的 [UI10] 段
# 以及 p81_ui_regression/probe_p81_datetime_wheel_ui.log/_result.json
```

### 2.2 行为/交互全量（U-04..U-12 + P-2）

```bash
cd "D:/休闲小岛幻境/游戏工程"
bash "D:/休闲小岛幻境/开发产物/p82/run_godot.sh" --path . --script res://tools/probe_p82_datetime_behavior.gd
# 约 50 s；输出 05_wheel/_final_behavior_HHMM.txt（本批为一次跑三套）、probe_p82_datetime_behavior.log/_result.json + 10 张截图
```

### 2.3 U-03 尺寸 / 高 DPI

```bash
cd "D:/休闲小岛幻境/游戏工程"
bash "D:/休闲小岛幻境/开发产物/p82/run_godot.sh" --path . --script res://tools/probe_p82_datetime_dpi.gd
# 约 28 s；输出 probe_p82_datetime_dpi.log/_result.json + a_*/b_* 截图（含 _panel 裁剪）
```

### 2.4 headless 82 项回归

```bash
cd "D:/休闲小岛幻境/游戏工程"
bash "D:/休闲小岛幻境/开发产物/p82/run_godot.sh" --headless --path . --script res://tools/probe_p81_datetime_wheel.gd
# 期望最后一行：=== P8.1-07 DATETIME WHEEL PROBE RESULT: PASS pass=82 fail=0 ===（本批输出 _final_headless82_HHMM.txt）
```

### 2.5 自检回归（含 P8 日历/时钟/滚轮 UI 项）

```bash
cd "D:/休闲小岛幻境/游戏工程"
bash "D:/休闲小岛幻境/开发产物/p82/run_godot.sh" --headless --path . -- --selftest
# 期望：[TEST] RESULT 73/73 passed（本批输出 _final_selftest_HHMM.txt）
# 三套一次跑完的便捷脚本（我实际用的）：bash "D:/休闲小岛幻境/开发产物/p82/05_wheel/run_batch_final.sh"
```

---

## 3. U-02：帧时间采样工具核实与 UI10 重测

### 3.1 为什么 P8.1 的 UI10 数据不可用

P8.1 窗口探针用 `Performance.get_monitor(Performance.TIME_PROCESS)` 作为帧耗时。本次在 windowed 下 120 帧采样：

- `TIME_PROCESS` min=p50=25.2640 ms、max=52.0390 ms、**唯一值只有 2 个** —— 该 monitor 在 windowed 下被量化成近似常量，
  反映的是某个固定分片而非每帧耗时（P-5 确认）；
- 同时 `Performance.TIME_FPS` p50=122.00 与墙钟 fps=124.50 一致 → `TIME_FPS` 可用作交叉校验；
- 因此 P8.1 报的 Δp50 只能当噪声，不能作性能门证据。

### 3.2 新方法（`probe_p81_datetime_wheel_ui.gd:_ui10`，本次重写）

1. **环境固定**：`DisplayServer.window_set_vsync_mode(VSYNC_DISABLED)` + `Engine.max_fps=0`（测完恢复原值）；
   开始前 `_close_all_panels()`，`Input.warp_mouse(窗口 - (60,80))` 把光标移离面板，等 0.3 s 稳定；
2. **预热 / 排空**：每个测量段开头 `await _frames(6)`（丢掉改 vsync、开关面板后的前几帧），再连续采 40 帧；
3. **逐对交错（配对法）**：12 对，每对严格 **先 A（面板全关）后 B（日历打开）**；每段前后 `_keep()` 续命
   （防止 `_time_idle > 14 s` 自动收折改变被测状态）；每对结束关面板、warp 光标、等 0.05 s 再进下一对。
   每段各算 p50，**配对相减**得 Δp50 → 段间漂移/温漂在差分中抵消（P8.1 三轮 ABBA 的最大问题：同一“全关”状态两段能差 1.3 ms）；
4. **A/A 对照**：8 对“连续两段都全关”，给出噪声底 |Δp50| 中位 / p95 —— 用来判断 Δp50 是否超出噪声；
5. **采样口径**：逐帧 `Time.get_ticks_usec()` 差值（墙钟 ms，含 vsync/合成器/进程调度全部开销）；
   同时记录 `Performance.TIME_FPS`（引擎口径）与墙钟换算 fps（交叉校验两者一致）、`Performance.TIME_PROCESS` 唯一值个数
   （仅作 P-5 证据，不作判据）、`RENDER_TOTAL_DRAW_CALLS_IN_FRAME` 与 `RENDER_TOTAL_OBJECTS_IN_FRAME`（结构增量的确定性证据）；
6. **统计**：配对差的中位、均值 ± se、95%CI 上限（均值 + 1.96·se）、正号数；
7. **判据（三层口径，已与 Lead 对齐）**：95%CI 上限 < 0.3 ms → PASS；0.3~1.5 ms 或 CI 过宽 → WARN；≥1.5 ms 或 draw 无增量 → FAIL。
   **绝不把 0.3~1.5 ms 的不可分辨区间写成 PASS。**

### 3.3 实测数据（v3 干净独占窗口：2026-10-22 19:54:51 → 19:55:47，54.2 s，`exclusive window pid=4974`）

| 指标 | 数值 |
|------|------|
| 逐对 Δp50（ms） | +0.859, +0.425, +0.464, +0.375, +0.185, +0.425, +0.294, +0.167, -0.231, +0.454, +0.071, +1.066 |
| Δp50 中位 / 均值±se | **+0.400** / +0.380 ± 0.098 |
| 95%CI 上限 | **+0.572 ms**（判据要求 < 0.3） |
| 正号数 | **11 / 12** |
| 关 / 开 p50 中位 | 6.434 / 6.801 ms |
| A/A \|Δp50\| 中位 / p95 | 0.729 / 1.302 ms（8 对：0.333, 0.779, 0.849, 0.679, 1.826, 1.302, 0.167, 0.099） |
| Δdraw / Δobjs | **+92**（1887→1979） / **+649** |
| TIME_FPS（引擎）/ 墙钟 | 124.0 / ≈136.6 fps（两者同量级，采样口径自洽） |
| TIME_PROCESS 唯一值 | **2**（P-5 量化证据，不作判据） |
| 回归 | 82 项：**80 pass / 2 warn / 0 fail**，9 图 |

### 3.4 结论

- 日历面板确实带来**确定性结构增量**：draw calls **+92**、objects **+649**（P8.1 记 +93 / 1898→1991，同量级）。
- 帧时间增量**方向为正且高度一致**（12 对中 11 对为正，中位 **+0.400 ms**，均值 +0.380±0.098，CI 上限 +0.572 ms）——
  比 19:14 那次非独占数据（中位 +0.778、CI 上限 +1.204、正号 8/12）更小也更集中，说明干净窗口下测量确实更稳。
- 但它**仍大于 0.3 ms 判据、且小于单对噪声底**（A/A 中位 0.729 ms、p95 1.302 ms）：即“开了面板确实略慢，
  慢的幅度在 +0.4 ms 量级；这个量级与配对噪声同阶，无法证明它 <0.3 ms”。按三层口径 → **WARN（可测但不可分辨）**，
  **不宣称 PASS**，也不判 FAIL（远低于 1.5 ms 且 draw 有确定性增量）。
- P8.1 的 UI10 WARN 至此闭环：旧数据用的是 `Performance.TIME_PROCESS`（windowed 唯一值=2，失真）+ 三轮 ABBA（段间漂移 ±1.3 ms），
  本次换用墙钟逐帧差值 + 逐对交错 + A/A 噪声底 + 95%CI，结论同样是 WARN，但**方法与数字可复核**。
- 要把门限真正压到 0.3 ms 以内需要：独占全屏/固定 GPU 时钟、30+ 对采样、或 GPU timestamp query；
  本轮条件（RTX 2060 + 桌面窗口 + 与其它 teammate 共享机器）不足，不做。

### 3.5 老证据降级（必须知道的方法学事实）

P8.2 早期串行器（v1/v2）在拿到锁后会打印 `[run_godot] exclusive window pid=...`，但 v2 里“等既有 Godot 进程退出”的检测正则
要求进程名带 `.exe`，而 git-bash 的 `tasklist` 把 Image Name 截断到 25 字符（`Godot_v4.7.2-stable_win64`，无 `.exe`），
所以那段检测**从未匹配**、`exclusive window` 是无条件打印的 —— **它只证明“拿到了锁”，不证明“没有并发”**（v3 已修正）。

因此本文件按以下口径使用证据：

| 运行 | 时间 | marker | 本文件如何引用 |
|------|------|--------|----------------|
| p81 窗口探针（旧 UI10 数据来源） | 19:14 | 无 marker | **仅作方法学参考，不作计时证据**（§3.3 已用干净重跑数据替换） |
| behavior 探针 | 19:27 | v2 marker（不可靠） | 交互/物理类结论只依赖真实输入与状态，不受并发影响；帧间隔仅稳定性记录 |
| headless82 + selftest | 19:34 | v2 marker（不可靠） | 纯逻辑断言（headless 无渲染计时），不受并发影响 |
| p81 窗口探针 + behavior 探针（本次最终） | 20:0x | **v3 marker** | 本文件 §3.3 / §14 的正式计时与最终 87 项数字以此为准 |

结论：**计时/性能类结论只用 v3 干净窗口数据**；交互正确性类结论在 v2 窗口下同样成立（不涉及帧时间），已在 NOTES 明确标注。

---

## 4. U-03：窗口尺寸与高 DPI

### 4.1 四档窗口（`project.godot`：stretch mode=`canvas_items`、aspect=`expand`、content_scale_size=1440×900）

| 物理窗口 | 画布 visible_rect | 物理缩放 k | 面板 canvas rect | 面板物理像素 | 命中（小时列下一行） |
|----------|------------------|-----------|------------------|--------------|----------------------|
| 1280×720 | 1600×900 | 0.800 | (34,156) 360×660 | 288×528 | 12→13 ✔ |
| 1600×900 | 1600×900 | 1.000 | (34,156) 360×660 | 360×660 | 13→14 ✔ |
| 1920×1080 | 1600×900 | 1.200 | (34,156) 360×660 | 432×792 | 14→15 ✔ |
| 2560×1440 | 1600×900 | 1.600 | (34,156) 360×660 | 576×1056 | 15→16 ✔ |

- `expand` 语义：画布按窗口纵横比扩展后恒为 1600×900（所有四档一致），面板顶 156 / 底 816 全在窗内，
  五列全部在滚轮 rect 内；滚轮 canvas 宽 324（=68+46×4+6×4+20），对应 P-6 的 316→324 区间化。
- 截图：`probe_p82_datetime_dpi_a_1280x720_calendar_open.png`、`a_1600x900_`、`a_1920x1080_`、`a_2560x1440_`（各带 `_panel` 裁剪）。

### 4.2 高 DPI（无真机，做等价模型 + 压力注入）

- 本机显示环境：`screen_count=1`、2560×1440（可用 2560×1390）、`screen_scale=1.000`、`screen_dpi=120`、`screen_max_scale=1.0`
  → **不存在系统级高 DPI 缩放环境**，真机高 DPI 未验证（WARN 披露）。
  替代方案：在 `canvas_items+expand` 下改窗口物理尺寸，即等价于“同一画布整体等比放大”，
  这正是 Windows 125%/150% 缩放在该 stretch 模式下的表现 → 4.1 的四档即为等价模型，全部 PASS。
- 额外压力注入（产品不可达路径，仅证明“若有人把 `content_scale_factor` 调大”会怎样）：

| content_scale_factor | 画布 | 面板 top | 顶部被裁 | 命中 |
|----------------------|------|----------|----------|------|
| 1.00 | 1440×900 | 156 | 0 | ✔ |
| 1.20 | 1200×750 | 6 | 0 | ✔ |
| 1.25 | 1152×720 | -24 | 24 px | ✔（面板上溢，日期行被裁） |
| 1.50 | 960×600 | -144 | 144 px | ✔ |
| 2.00 | 720×450 | -294 | 294 px | ✔ |

  结论：factor ≤ 1.2 完整可见；≥1.25 面板（固定高 660 canvas 单位、`PRESET_BOTTOM_LEFT` 锚定）必然从顶部被裁。
  **这不是产品缺陷**：`scripts/` 里只有 `main.gd:5645` 设 `content_scale_size`，没有任何 UI 缩放设置会改 factor；
  此段仅记录边界，供未来若新增“UI 缩放”设置时参考（WARN 披露）。
- 截图：`probe_p82_datetime_dpi_b_factor1.25_calendar_open.png`、`b_factor1.50_`、`b_factor2.00_`。

---

## 5. U-04：桌面触摸（合成输入）

- 本机 `DisplayServer.is_touchscreen_available() = false`，属桌面无触屏 → 用合成事件覆盖，并披露局限。
- **关键坑（探针层，不是产品缺陷）**：`Window.push_input()`（以及 `root.push_input()`）**不做 touch→mouse 模拟**，
  合成 `InputEventScreenTouch` 走这条路值不变（首版探针 FAIL：tap=(221,578) 前后都是 2026-10-22 12:19）。
  改用 `Input.parse_input_event(ev)`（走正常输入管线，项目 `input_devices/pointing/emulate_mouse_from_touch=true` 才生效）后通过。
- 结果：
  - 合成点击“日列中心下一行” → 2026-10-22 12:19 → **2026-10-23 12:19**（+1 天）；
  - 合成 12 步 `InputEventScreenDrag`（每步 -28/12 px、index=0、同时设 `relative`）上拖 1 行 → 12:19 → **13:19**，`busy=false`；
  - 截图：`u04_touch_tap.png` / `u04_touch_drag.png`。
- 局限：合成触摸无法覆盖真实触屏的手掌误触、多点指压、触摸滚动惯性与系统手势竞争；真机触屏未验证（WARN 披露）。

---

## 6. U-05：滚轮吸附手感（P-1/P-3/P-4 复核）

### 6.1 物理量（`debug_*` 钩子以固定 dt 同步推进，等价于引擎帧积分；生产 `_process` 调同一个 `tick`）

| 用例 | 结果 |
|------|------|
| 慢拖 0.6 行/s 释放 | mode=3（弹簧吸附），pos 9.400→9.000 |
| 吸附收敛 | **47 步 / 0.392 s**，起始偏移 0.400 行，临界阻尼解析期望 **0.392 s**，比值 **1.00** |
| 吸附超调 | **0.0000 行**（ζ=1 无超调，符合设计） |
| 吸附落位 | pos=9.0000、vel=0、整数行 |
| 甩动 2.2 行/s | mode=2，EMA=-2.20；惯性段滑行 **-0.347 行**（v/6 期望 0.367，比值 0.95）；48 步 0.800 s；单步最大位移 0.048 行（无跳变） |
| 甩动 6.0 行/s | mode=2，EMA=-5.95；滑行 **-1.003**（期望 0.991，比值 1.01）；56 步 0.933 s；max_step 0.099 |
| 阈值扫描 0.3 / 0.7 / 1.0 行/s | mode=3（吸附） |
| 阈值扫描 1.3 / 2.0 / 5.0 行/s | mode=2（惯性） |
| 实测临界 | **1.3 行/s**（EMA 0.35 滞后于瞬时速度，故实测边界略高于常量 1.20） |
| 年列下界橡皮筋 | 拖 3 行 → pos=**0.7500**（=1-0.25）；22 步回弹到 1；过程最小值 0.7500（不塌陷） |
| 年列上界橡皮筋 | 拖 3 行 → pos=**9999.2500**；22 步回 9999；越界 notch 不改值 |
| 循环列 | 时/分/月循环进 1（23:59 +1 → 2026-01-01 00:00） |
| 月末钳制 | 1/31 改月 → 02-28，日列 range=1..28 |
| 日列下界 | 1 不下溢；越界后 0.75 回弹 1 |
| 真实鼠标拖 1 行 | 2026-10-22 10:00 → **11:00**（release 后 pos=11、vel=0、mode=0） |
| 真实滚轮 pressed+released | **1 notch**（11:00→11:59）—— P-3 无双 notch |
| 只给 released 的滚轮事件 | 被忽略（11:59→11:59） |
| 真实滚轮 WHEEL_DOWN | +1 notch（11:59→11:00） |
| 空闲 2 s | 五列 mode=0、vel=0、pos 为整数（无残留漂移） |

### 6.2 P-1（合成输入需 warp）与"合成拖动位置不一致"伪影

- P-1 复核：不 `Input.warp_mouse` 时 hover/命中不稳定；warp 后 hover=Wheel_minute、点击/拖动全部确定。
  探针保留一条 WARN 记录运行环境（合成输入必须先 warp），**产品侧无缺陷**。
- 但 P-1 只解决了"命中"，没解决"拖动过程中的位置一致性"。本轮把"真实鼠标向上拖 1 行"做成硬断言后，
  连续三次跑出 **+2 / +5 / +1 小时** 的不稳定结果，逐帧打点后定位到**探针注入方式**（不是产品缺陷）：
  1. 合成 `InputEventMouseMotion` **不移动 OS 光标**。只 warp 一次时，引擎记录的"真实"鼠标位置仍停在按下点；
     拖动期间任何一次真实位置刷新（窗口/焦点/DPI 事件）都会把 `event.position` 报回按下点 →
     `_last_y / pos` 被重置回起点（打点实测 step 40 处 `last_y=70.00 pos=10.0000`，而当时合成点已在 544.87）。
  2. 反过来"每步 warp + 每步合成 push"会让同一帧内出现两个位置相同/相邻的 motion 事件，
     `_dt_since_last()` 被压到毫秒级下限 → 瞬时速度 `inst` 爆表、EMA 尖峰（实测 **2.5~3.2 行/s**，真实拖速仅 0.66 行/s）→
     `end_drag` 误判为甩动进入惯性（mode=2），额外滑 1 行后落位 → 值多 +1。
- 最终修法（只改探针 `_inject_drag_col`）：拖动步进**只调 `Input.warp_mouse(p)`**，不再叠发合成 motion，
  由引擎产生位置一致、dt 为真实帧间隔的 MouseMotion（等价人手匀速拖动）；释放后加 settle 等待（mode=0 或 ≤2 s）。
  修后该断言稳定 PASS：**2026-10-22 10:00 → 11:00**，release 时 `pos=11.0000`、`vel=0`、`mode=0`、`_ema_vel=0.401`
  （0.401 < FLICK_THRESHOLD 1.2 → 走弹簧吸附而非惯性，与"拖 1 行落 1 行"一致）。对照伪影期：EMA 2.5~3.2、release 后 pos=12、值 +2。
- 方法学结论（给后续探针复用）：**Godot 窗口下做"真实鼠标拖动"注入，只能用 OS 光标驱动（warp），
  不能用合成 MouseMotion 叠加**；否则速度 EMA 与位置锚点都会被污染。此结论已写入 §2.2 的命令注释里（同一文件）。

### 6.3 P-4：阈值去重（不是调参）

- 原 `end_drag` 里写死 `1.2`，与 `const FLICK_THRESHOLD := 1.2` 重复且易漂移 → 改为引用常量，数值不变。
- P8.1 报告建议把阈值调轻到 0.67 行/s。该数值直接决定“轻拖是否变成惯性滑行”，属**手感设计决策**，
  本任务只做端到端验证，不擅自改产品手感 → 明确保留 1.2，并把“是否调 0.67”留给 Lead/设计决策。

---

## 7. U-06 / U-12：TAB 切列与键重复率

- Tab 焦点序列（`root.push_input` 走 GUI 焦点路由，p81 用的 `Input.parse_input_event` 在窗口非聚焦时会丢）：
  `DateTimeWheel/Wheel_year → Wheel_month → Wheel_day → Wheel_hour → Wheel_minute → Wheel_year → Wheel_month`
  —— 5 列全覆盖，且 Tab 遍历期间 `_almanac_open=false`（不误触天文历）。第 6 次 Tab 会离开滚轮（离开到上一级/其他控件），
  这是 Godot 默认焦点链行为，记录为 WARN（不是缺陷）。
- 方向键：→ 逐列右移并在 minute 夹取（4 次后停在 minute）；← 在 year 夹取（不循环）。
- key echo：`ui_datetime_wheel.gd:736` 对 `key.echo` 直接 return。
  - echo=true × 10（handler 路径）→ 值不变（10→10）；
  - echo=true × 10（GUI 焦点路由）→ 值不变（10→10）；
  - 真实 KEY_DOWN × 10 → +10（10→20）；handler 3 次 → +3（20→23）。
- 局限：真机 OS 自动重复率（~30 Hz）与 `echo` 时序无法在合成输入下复现 → WARN 披露；
  echo 守卫本身已在两条路径上验证有效。

---

## 8. U-07：多面板并发

- 同时打开：时间面板 + 日历展开 + 天文历 + 天气 + 性能面板 → 不崩溃、无报错。
- 并发态下滚轮仍响应（notch 30→29）、焦点保持 `DateTimeWheel/Wheel_minute`。
- 全关后滚轮 `visible_in_tree=false`、`busy=false`、`_time_open=false`、`_cal_open=false`。
- 截图：`u07_concurrent_panels.png`。

---

## 9. U-08：现实时间跨午夜 / 跨年（含注入方式说明）

### 9.1 模拟模式下的**真实自然跨越**（不是注入）

把 `_day_length` 设为 14400（=6 秒/真实秒），从目标时刻前 1 分钟起跑，让它自然跨过：

| 用例 | 结果 |
|------|------|
| 跨年 2026-12-31 23:59 → 2027-01-01 | 跨越成功；HUD `clock='00:00'`、`date='2027年1月1日  周五'`；日列 range=1..31；草稿=权威 |
| 跨月 2026-01-31 23:59 → 2026-02-01 | 跨越成功；`date='2026年2月1日  周日'`；日列 range=1..28 |
| 闰日 2028-02-28 23:59 → 2028-02-29 | 跨越成功；`date='2028年2月29日  周二'`；日列 range=1..29 |

### 9.2 现实时间模式：23:59:59 → 00:00:05

- 为什么是“同步注入”：`main.gd:877 _advance_sim()` 在现实模式**每帧**重取 `Time.get_unix_time_from_system()`
  覆盖 `_abs_unix`，在不改 `main.gd`（禁区）的前提下无法注入时钟 → 只能临时写 `_abs_unix` 后**同步**调用
  `_display_datetime()/_display_clock_text()` 读结果，再立刻恢复原值（`_time_source`/`_abs_unix` 已核对恢复）。
- 结果：23:59:59 → clock=23:59、偏移 28800；+6 s → **2027-01-01 00:00:05**、clock=00:00、星期=周五（日期正确进位）。
- 注入期间踩到并修正的坑（探针层）：偏移必须用**目标时刻**的 `_offset_for()`，用 epoch 偏移会得到 +8 h（曾出现 08:00:05）。
- WARN 披露：这是同步注入验证，不等于“真实等待 6 秒跨午夜”。真实等待路径由 9.1 的自然跨越覆盖（sim 模式同一个 `_advance_sim` 分支逻辑）。

---

## 10. U-10：极端年份 / 跨年 / 闰年 / 月末

| 用例 | 结果 |
|------|------|
| 跳转 1999-12-31 23:59 / 2000-02-29 12:00 / 2001-01-31 12:00 / 0001-01-01 00:00 / 9999-12-31 23:59 | 全部生效，`datetime_jump_requested` 各 1 次 |
| 2100-02-29（非闰年） | `clamp_parts(2100,2,29)` → 2100-02-28；`days_in_month(2100,2)=28`；`days_in_month(2000,2)=29`（世纪闰年规则正确） |
| 跳转 2100-02-28 | 生效 |
| 2001-01-31 月 +1 | 草稿 → 2001-02-28，日列 range=1..28 |
| 跳转 2001-02-28 | 生效 |
| 年列边界 | 9999 notch(+1) 仍是 9999（橡皮筋后回弹）；1 notch(-1) 仍是 1 |

---

## 11. U-11：失焦 / 最小化 / 多显示器

- 失焦（`NOTIFICATION_APPLICATION_FOCUS_OUT`）→ 回前台（`FOCUS_IN`）：面板保持打开，滚轮 notch 正常（40→39）。
- 最小化 → 恢复：窗口回到 1440×900，面板 rect 仍 (34,156 360×660)，notch 正常（40→41）；截图 `u11_after_restore.png`。
- 多显示器：本机 `screen_count=1`（2560×1440；另有一块 **Oray 虚拟显示**，未以第二物理屏暴露给引擎）→ 真机多屏 **SKIP**（WARN 披露）。
  未验证项：把窗口拖到第二屏/不同 DPI 屏后，`DisplayServer.screen_get_scale()` 变化时面板的重排行为。

---

## 12. U-09：长时间运行与面板反复开关

窗口 1440×900、日历打开态，统计口径分三个（Fx 动效子树单独计，避免把涟漪/水花按需生成当成泄漏）：

| 阶段 | hud 节点 | 静态节点（排除 /root/Isle/Fx） | 整树节点 | Fx 节点 | 渲染 objects | 内存 |
|------|----------|-------------------------------|----------|---------|--------------|------|
| 基线 | 120 | 1381 | 1544 | 163 | 2326 | 185.4 MB |
| 60 次开合 + 200 次交互后 | **120** | **1381** | 1544 | 163 | 2298 | 186.6 MB |
| Δ | **0** | **0** | **0** | 0 | **-28** | +1.21 MB |

- 新增非 Fx 节点路径集合：**[]（空）**；
- 信号连接数：`hud.datetime_jump_requested` 2→2、`wheel.parts_changed` 1→1、`wheel.editing_changed` 1→1（全不变）；
- 1200 帧长跑（日历打开、每 200 帧续命 `_time_idle`）：起始/结束草稿=权威=2026-10-22 12:19，
  HUD/静态节点不增长，同面板态 objects 2977→2975（-2），帧间隔 p50=7.21 ms / p95=8.70 ms / avg=8.32 ms（vsync 开启，仅作稳定性记录）；
- 截图：`u09_long_run_calendar_open.png`。
- 局限：1200 帧 ≈ 10 s，属“短时稳定性”而非多小时 soak；本任务的泄漏主判据是 60 次开合 + 200 次交互的节点/连接集合对比（Δ0）。

---

## 13. P-1..P-6 复核结论

| 编号 | 原状 | 本轮结论 |
|------|------|----------|
| P-1 | 合成输入需 `Input.warp_mouse` | 复核成立（环境约束），探针已按此注入；生产无缺陷 |
| P-2 | 打开日历出现“假 dirty” | **不复现**：打开 0.4 s 内两次采样 dirty 均 false，草稿=权威；编辑/跳转/关闭三态行为符合设计 |
| P-3 | 滚轮一次滚动触发双 notch | **不复现**：pressed+released=1 notch，仅 released 被忽略，WHEEL_DOWN=+1（P8.1 修复有效） |
| P-4 | `end_drag` 硬编码 1.2 与常量重复 | **已修**：改为引用 `FLICK_THRESHOLD`（数值不变）；0.67 调参留给设计决策 |
| P-5 | `Performance.TIME_PROCESS` windowed 失真 | **已确认并替换**：唯一值=2；UI10 改用墙钟逐帧差值 + TIME_FPS/墙钟 fps 交叉校验 |
| P-6 | UI1 滚轮宽 316 断言 vs 实际 324 | 维持区间断言 316..340；四档窗口实测 canvas 宽 324 |

---

## 14. 回归结果（全部 exclusive）

> **最终干净批次（本文数字出自此批）**：2026-10-22 20:26:12 → 20:27:11，一个 GPU 窗口内串行跑
> check-only(帧探针) → behavior(窗口, 87 项) → headless 82，三套 **RC=0**；日志内 `[run_godot] exclusive window confirmed`
> 分别出现于 20:26:15 / 20:27:07（无其它 Godot 进程），behavior `fail=0`、headless `pass=82 fail=0`。
> 脚本：`开发产物/p82/05_wheel/run_batch_final.sh`。

> 运维教训（本次踩坑，供后续复用）：① **kill 掉一个"可能已持锁"的排队 job 前必须先看 `.engine.lock` 的 owner**——
> 我在 20:08 kill 了已拿到锁并拉起引擎的排队 job，bash 被杀、trap 未执行 → 留下 owner=探针脚本、pid 已死的孤儿锁，
> 阻塞了 wind 的排期（Lead 已升级 run_godot.sh v4：持有者 pid 不存在且 age>30s 即自动清锁，并加 HUP trap）。
> ② 排期变化时不要 kill 排队 job，让它自然排队更安全。③ 探针日志不要跨次复用同一文件名（被截断会误导归因），
> 本次改为 `_final_<name>_<HHMM>.txt`。

> 数据取舍说明（重要）：本文所有"最终数字"均取 **v3 串行器（grep -F 修正）+ exclusive window 行** 之后、
> 且无其它 teammate 正在改工程文件的运行。以下运行**不作为最终数据**：
> - 19:14 那次 p81 UI 跑（串行器 v2，marker 只证明拿到锁、不证明无并发）；
> - 19:27 / 19:34 的 behavior / headless 跑（同上）；
> - 19:58 那次 behavior 跑（日志 4374 条 `Shader uses global parameter 'g_indoor_band' ...`，
>   是 lighting 正在改 `toon.gdshader` 的中间态污染，属"工程被人同时改"）。


| 套件 | 命令 | 结果 | 证据 |
|------|------|------|------|
| headless 滚轮探针 | `probe_p81_datetime_wheel.gd`（--headless） | **PASS pass=82 fail=0** | `_final_headless82_2026.txt` |
| 窗口滚轮探针（p81，UI10 已重写） | `probe_p81_datetime_wheel_ui.gd` | **82 项：80 pass / 2 warn / 0 fail**，9 图 | `_run_p81_ui_v3.txt`、`p81_ui_regression/` |
| 行为/交互探针（本轮新增） | `probe_p82_datetime_behavior.gd` | **87 项：80 pass / 6 warn / 1 skip / 0 FAIL**，10 图 | `_final_behavior_2026.txt`、`probe_p82_datetime_behavior.log/_result.json` |
| DPI/尺寸探针（本轮新增） | `probe_p82_datetime_dpi.gd` | **12 项：10 pass / 2 warn / 0 fail**，10 图 | `probe_p82_datetime_dpi.log/_result.json` |
| 自检 | `-- --selftest` | **73/73 passed** | `_run_selftest.txt`（runbook 统一跑，Lead m00794） |

`--selftest` 中与时间/日历/UI 相关的项全部 PASS，包括：可拖动时间轴设定当天时刻、现实时间模式、IANA 时区切换（东京 UTC+09）、
现实时间天体时钟固定为岛屿参考时区、切换显示时区天体不移动（纽约）、十档每日流速（60..3600s，边界吸附）、
P8 公历跨闰日/跨年推进、P8 可见暂停按钮与空格共享状态、P8 暂停冻结权威时钟、P8 日历编辑后跳转即时生效、
P8 跨年跳转进入合法状态、P8 日历收折恢复面板高度、P8 月相随机跳日期更新、滚轮可拉近至近景。

### 14.1 窗口滚轮探针的 2 条 WARN

1. **UI10 帧时间**：见 §3（可测但不可分辨，v3 干净窗口 Δp50 中位 **+0.400 ms**、CI 上限 +0.572 ms、A/A 噪声中位 **0.729 ms**）。
2. **U04 触摸注入**：p81 探针的触摸注入不经过 GUI 鼠标路由 → 值不变；桌面触摸由 `probe_p82_datetime_behavior.gd` 用
   `Input.parse_input_event` 单独验证通过（§5）。**不是产品缺陷，是旧探针方法局限。**

### 14.2 行为探针的 6 条 WARN + 1 条 SKIP

1. P-1 合成输入需 warp（环境记录）；
2. U-12 真机 OS 自动重复率无法自动化测量；
3. U-06 Tab 第 6 次会离开滚轮（Godot 默认焦点链，记录行为）；
4. U-08 现实时间为同步注入（`main.gd` 禁区，无法真等待）；
5. U-11 多屏/高 DPI 无真机（披露）；
6. U-04 合成触摸非真机触屏（披露）。
SKIP：U-11 多显示器真机（`screen_count=1`）。

---

## 15. 未完成 / 限制（如实披露）

1. **UI10 未达“<0.3 ms”门限**：真实增量约 +0.7~0.8 ms，被单对噪声（≈1.2 ms）覆盖；要证明 <0.3 ms 需要更强测量手段
   （独占全屏 + GPU timestamp、30+ 对采样、锁 GPU 时钟），本轮条件不足，按三层口径记 WARN，不冒充 PASS。
2. **高 DPI 真机未验证**：本机 `screen_scale=1.000`，只能做 stretch 等价模型（§4）。真实 125%/150% 系统缩放未覆盖。
3. **多显示器未验证**：`screen_count=1`；Oray 虚拟显示未作为第二物理屏暴露。
4. **桌面触摸为合成输入**：无触屏设备；多点/手掌误触/系统手势竞争未覆盖。
5. **现实时间跨午夜为同步注入**：未做“真实等待跨午夜”（`main.gd` 每帧重取系统时间，禁区）。
6. **长时间运行仅 1200 帧 + 60 次开合**：不是多小时 soak；更大规模泄漏（如连续数小时日历开着）未覆盖。
7. **P-4 阈值数值未调**：0.67 行/s 的建议属设计手感决策，本轮只去重。
8. **手感主观评价未做**：本任务验证物理量（收敛时间/超调/滑行距离/阈值边界），未做人眼“手感是否舒服”的主观评估。

---

### 15.1 未采纳的建议与理由（P-4 阈值 0.67）

P8.1 报告建议把惯性阈值从 1.2 行/s 调轻到 0.67 行/s（更容易触发惯性滑行、更“顺滑”）。本轮**不采纳**，理由：

1. **没有复现证据**：本轮阈值扫描（0.3/0.7/1.0/1.3/2.0/5.0 行/s）显示 1.2 阈值行为正常——低俗速度稳定吸附、高速稳定惯性，
   实测边界 1.3 行/s（EMA 滞后），无卡顿、无跳变、无双 notch；未观察到需要改阈值的缺陷。
2. **属于手感设计决策，不是缺陷修复**：阈值直接决定“轻拖一下是否变成滑行”，0.67 会明显提高惯性触发率，
   需要人眼/试玩的主观 A/B 才能判断是否更好；本轮任务是端到端验证，不应擅自改产品手感。
3. **风险与收益不成比例**：改数值会让全部手感断言（收敛时间、滑行距离、阈值边界）失效，需要重新标定一整套证据；
   在 P8.2 收尾阶段做无证据的数值改动，风险高于收益。
4. 已做的替代动作：把 `end_drag` 里重复的字面量 `1.2` 改为引用 `FLICK_THRESHOLD` 常量（**零行为变更**），
   并在常量处保留注释，等未来有试玩证据时只需改一个常量即可调参。

---

## 16. 证据文件清单（`D:/休闲小岛幻境/开发产物/p82/05_wheel/`）

| 文件 | 内容 |
|------|------|
| `_final_behavior_2026.txt` | 行为探针最终 stdout（exclusive，87 项） |
| `probe_p82_datetime_behavior.log` / `_result.json` | 行为探针逐项日志 + 结构化结果 |
| `_run_dpi_stdout2.txt`、`probe_p82_datetime_dpi.log` / `_result.json` | DPI/尺寸探针（12 项） |
| `_run_p81_ui_exclusive.txt`、`p81_ui_regression/*` | 窗口滚轮探针 82 项（exclusive）+ UI10 数据 |
| `_run_headless82.txt` / `_run_selftest.txt` | headless 82 项 / selftest 73 项 |
| `u04_touch_tap.png`、`u04_touch_drag.png` | 合成触摸点击/拖动前后 |
| `u06_focus_minute.png` | 键盘焦点到 minute 列（焦点下划线可见） |
| `u07_concurrent_panels.png` | 5 面板并发 |
| `u08_cross_year.png`、`u08_cross_month.png`、`u08_leap_day.png` | 自然跨越前后 |
| `u09_long_run_calendar_open.png` | 1200 帧长跑后 |
| `u11_after_restore.png` | 最小化恢复后 |
| `probe_p82_datetime_dpi_a_*_calendar_open.png`（4 档） / `b_factor1.25/1.50/2.00_*` | 尺寸与 DPI 压力截图 |

---

## 17. 一句话总结

滚轮窗口端的**交互正确性**（吸附/惯性/阈值/橡皮筋/循环/钳制/TAB/echo/触摸/并发/跨午夜/极端年份/开合泄漏）全部有真实运行证据并通过；
**唯一不达标的是帧开销的“可证伪精度”**：日历打开确有 +92 draw call / +649 objects 的确定性结构增量、帧时间方向为正约 +0.8 ms，
但被噪声覆盖，按三层口径记 WARN 而不冒充 PASS。生产代码只做了 1 行 P-4 去重，未动任何手感数值与 841 行组件结构。
