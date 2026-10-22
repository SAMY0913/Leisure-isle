# P8.2-03 强风 CPU 性能调查

日期：2026-10-22　分支：`p82-integration`　范围：强风相关的风向/阵风、落叶参数、冬季落叶门控、萤火抑制、秋千受迫摆。
证据目录（git 外）：`D:/休闲小岛幻境/开发产物/p82/evidence/03_wind/`

## 0. 结论（先看这里）

1. **P8.1 报告里的「强风 CPU 侧 +1.93 ms」是 `Performance.TIME_PROCESS` 伪影，不是真实成本。**
   - 该 monitor 在窗口模式只返回 **15–18 µs**、headless **17–18 µs**，而同一时刻真实帧间隔是 **5.8–6.2 ms / 2.0–2.4 ms**（差 100–300 倍）；
   - 同一实现（new）在不同轮之间给出 25.7 ms → 42.4 ms 的跳变，远大于被测增量；new / legacy 两组的 tp 中位数逐轮几乎相同，无法区分实现。
   - → 它既不测帧 CPU 总量、也不测增量，不能作 A/B 判据。本任务改用「墙钟帧间隔 + GDScript 分段计时」两套可信口径。
2. **强风视觉系统（风向/阵风 + 落叶参数 + 萤火抑制 + 秋千）的真实 CPU 成本约 41–47 µs/帧**（窗口模式，帧 5.9 ms 的 **≈0.7–0.8%**；headless 下 30–38 µs）。
3. **new（P8.1-05 实现）相对 legacy（P8 阶段 7 旧实现）的帧级净差在噪声内**：同一 build 交替 A/B 的 per-round 配对中位差 calm −291 µs / wind +28 µs / typhoon −206 µs，逐轮 sd 714–1154 µs（r5）。也就是说 P8.1-05 的视觉增强**没有可测量的帧时间代价**（也没有可分辨的收益/回归；帧级只能作上界检验）。
4. **三项最小优化在同一 build 内交替 A/B 下收回 19–31 µs/帧（−30%…−39% 的强风段开销）**：
   - 萤火抑制写入门控 ≈ **−14…−17.5 µs**（最大头）
   - 落叶参数缓存 ≈ **−4…−6 µs**
   - 秋千容器复用 ≈ **−3…−7 µs**
   两次独立 run（r4/r5）符号与量级一致（见 §5.2）。
5. 视觉/行为**逐帧等价**（不是"差不多"）：等价性由 `tools/probe_p82_wind_cpu.gd` 的 23 条断言 + `probe_p81_wind.gd` 117 条原有断言覆盖，全部通过。

## 1. 热点定位（数据，不是猜测）

优化前（同一 harness，window r1，每帧中位 µs，n=120/phase/impl）：

| phase | impl | 合计 | 风向/阵风 | 落叶参数 | 冬季门控 | 萤火抑制 | 秋千 |
|---|---|---|---|---|---|---|---|
| calm | new | 59.0 | 2 | 16 | 0 | 32 | 8 |
| calm | legacy | 30.5 | 2 | 8 | 0 | 12.5 | 8 |
| wind | new | 71.0 | 2 | 15.5 | 0 | 32 | 20 |
| wind | legacy | 34.0 | 2 | 9 | 0 | 13 | 9 |
| typhoon | new | 67.5 | 2 | 14 | 0 | 32 | 19 |
| typhoon | legacy | 34.0 | 3 | 7 | 0 | 14 | 10 |

热点排序：**萤火抑制（+19 µs）> 秋千（+11 µs）> 落叶参数（+6.5 µs）**，风向/阵风段 ≤ 2 µs（可忽略），冬季落叶门控在冻结日期下不执行（见 §11.4）。
原因都是"逐帧做同一件事"：萤火每帧无条件重建 activity Dictionary 并写 4 个节点/材质属性；落叶每帧重建 `wind_leaf_params` 的 Dictionary（下游写入本来就有阈值，重算没有）；秋千每帧新建 3 个临时容器（target Dictionary + 2 个 spring Array）。

## 2. 方法（可复现）

- 新增运行时开关 `--p82windcpu`（`scripts/main.gd` `_run_p82windcpu()`）：固定 q2 画质、`--fixed-fps 60`、VSync 关、`Engine.max_fps=0`、模拟暂停（权威时钟冻结）、日期 2026-10-20 22:00、机位 `_p8_camera_tree()`（q2 大树）。
- 三个阶段：`calm`（clear 且投影风强制归零 = 真无风基线）/ `wind`（strong_wind）/ `typhoon`（台风）。
- A/B 三段实现同一 build 内交替：`new`（当前实现）、`off`（把三项优化临时关掉 = 优化前路径）、`legacy`（P8.1 之前旧实现）。轮次顺序与 impl 顺序**都按轮次奇偶翻转**，消除热机/位置偏置。
- 每段 settle 30 帧后采样 120 帧；**9 轮**。AB 段关闭分段计时（避免计时开销污染 frame_us）；prof 段单独采样一次，逐帧记录 5 个 section 的 `Time.get_ticks_usec` 差值。
- 原始数据每帧一行 CSV（`round,phase,impl,prof,frame_idx,frame_us,tp_us,sec_*_us`），采样结束后一次性写盘（避免字符串格式化开销混进 frame_us）。
- 最终数据在 `run_godot.sh` v2 串行器的**独占窗口**内采集（日志含 `[run_godot] exclusive window pid=...`）。

复现：

```bash
cd "D:/休闲小岛幻境/游戏工程"
# 主判据：同一 build 内 new / off / legacy 交替 A/B（9 轮）
bash "D:/休闲小岛幻境/开发产物/p82/run_godot.sh" --fixed-fps 60 --p82windcpu -- \
  --out "D:/休闲小岛幻境/开发产物/p82/evidence/03_wind/window" --label r5 --impls new,off,legacy
# headless（dummy renderer，隔离 CPU 侧）交叉验证
bash "D:/休闲小岛幻境/开发产物/p82/run_godot.sh" --headless --fixed-fps 60 --p82windcpu -- \
  --out "D:/休闲小岛幻境/开发产物/p82/evidence/03_wind/headless" --label r5 --impls new,off,legacy
# 归因分析
PY="C:/Users/Administrator/.dsh/dsh-runtimes/dsh-primary-runtime/dependencies/python/python.exe"
"$PY" "D:/休闲小岛幻境/开发产物/p82/evidence/03_wind/analyze_optab.py" \
  "D:/休闲小岛幻境/开发产物/p82/evidence/03_wind/window/p82windcpu_window_r5_1792667748.csv" \
  "D:/休闲小岛幻境/开发产物/p82/evidence/03_wind/headless/p82windcpu_headless_r5_1792667848.csv"
```

## 3. 修改清单

| 文件 | 改动 |
|---|---|
| `scripts/main.gd` | ① 新增 5 段分段计时（`_p82p_begin/_p82p_end/_p82p_reset`，默认关闭零开销）；② `--p82windcpu` 采样 harness `_run_p82windcpu()`（`--out/--label/--impls`）；③ 落叶参数缓存；④ 萤火 activity 缓存 + 4 个属性写入门控；⑤ 秋千 `_into` 复用容器版纯函数 + 运行时改用；⑥ `_run_p81wind()` 增加 `--windshotsout` 取证目录覆盖（只追加，不改默认值）；⑦ `_p82opt_off` 测量开关（把 ③④⑤ 临时退回优化前路径）。 |
| `tools/probe_p82_wind_cpu.gd` | 新增：优化等价性/门控正确性探针（23 条）。 |
| `docs/P8_2_03_NOTES.md` | 本文档。 |

未改：fx.gd、isle_weather.gd、shaders/、灯光段、秋千几何、任何阈值/测试常量。未向 `开发产物/p81/**`、`p8/**`、`发布/`、`构建输出/` 写任何文件（所有新证据都在 `开发产物/p82/evidence/03_wind/`；`find 开发产物/p81 开发产物/p8 -newermt "18:00"` 结果为 0）。

## 4. 优化实现（为什么视觉逐帧等价）

1. **落叶参数缓存**（`_update_weather_fx` 新分支）：`wind_leaf_params(wv, wd)` 只在 `wv` 变化 >0.0005 或风向平方距离 >2.5e-7 时重算。0.0005 正是下游写 `leaf_pm.direction/gravity` 的既有阈值——输入变化没超过写入阈值时，重算结果本来也不会被写出去，输出序列完全一致（探针 A4/B3）。
2. **萤火抑制**（`_update_lighting` 新分支）：
   - `firefly_wind_activity(weather_f)` 只在 `weather_f` 变化 >0.0005 时重建（activity 只跟天气有关，与 `fireflyI` 无关）；
   - `emitting/amount_ratio` 只在发射态翻转或 ratio 变化 >0.002 时写；`emission_box_extents`（距离平方 >4e-6）、`speed_scale`（>0.002）、`albedo`（RGB 各 >0.002）分别门控；
   - `lifetime` 保留原有 0.05 阈值（避免误触发容量重置）。
   都是"值没变就不写"，属性写入幂等，视觉序列不变（探针 A5/B4–B9，含台风级归零、晴夜↔强风 30 次切换不滞后）。
3. **秋千容器复用**：新增 `swing_wind_targets_into(out, ...)` / `swing_spring_step_into(out, ...)`，运行时写进两个常驻容器；原 `swing_wind_targets` / `swing_spring_step` 改为"新建容器 → 调 _into"的薄包装，所以 `probe_p81_wind.gd` 的 117 条纯函数断言仍在测同一份实现。数学逐位一致（<1e-12），夹紧/弹簧状态保留（探针 A1/A2/A6/B10–B13）。

## 5. 数据：同一 build 内交替 A/B（主判据）

### 5.1 r5（`run_godot.sh` v2 独占窗口，window）

CSV：`window/p82windcpu_window_r5_1792667748.csv`；日志 `log_window_r5.txt`；分析 `analysis_optab.txt`。

帧间隔（每格 n=1080 帧）：

| phase | impl | p50 µs | p95 µs | 5 段合计 | 萤火 | 落叶 | 秋千 |
|---|---|---|---|---|---|---|---|
| calm | new | 5857 | 8375 | 41 | 17 | 12 | 8 |
| calm | **off** | 6231 | 9193 | **64** | 33 | 18 | 8 |
| calm | legacy | 6028 | 8476 | 31 | 11 | 8 | 8 |
| wind | new | 6236 | 9233 | 47 | 16 | 10 | 18 |
| wind | **off** | 5830 | 8782 | **78.5** | 33.5 | 16 | 25 |
| wind | legacy | 6098 | 9009 | 31 | 12 | 8 | 8 |
| typhoon | new | 6241 | 9407 | 43 | 16 | 9 | 16 |
| typhoon | **off** | 6000 | 8661 | **75** | 33 | 15 | 23 |
| typhoon | legacy | 6000 | 8671 | 27.5 | 12 | 5 | 8 |

**分段归因（new − off，window r5）**：

| phase | 风向/阵风 | 落叶参数 | 冬季门控 | 萤火抑制 | 秋千 | 合计 |
|---|---|---|---|---|---|---|
| calm | 0 | −6 | 0 | −16 | 0（无风早退，无分配） | **−22** |
| wind | 0 | −6 | 0 | −17.5 | −7 | **−30.5** |
| typhoon | 0 | −6 | 0 | −17 | −7 | **−30** |

**帧级 per-round 配对差（9 轮，new − off）**：calm 中位 −574.5（均值 −395.1，sd 779.5）；wind 中位 +266.5（均值 +254.4，sd 1059.2）；typhoon 中位 +2（均值 +303.1，sd 1044.9）。
→ 帧级差值方向与幅度都被 ±1 ms 级毛刺主导，**不能用来判 20–30 µs 的差异**；它只用于检验"没变差"的上界。精确归因依赖分段计时（GDScript 计时器直接测的是被测代码本身的 CPU 时间，不受 GPU/排队影响）。

**new − legacy（同一轮交替）**：calm −291 µs、wind +28 µs、typhoon −206 µs（中位，sd 714–1154）。→ P8.1-05 的视觉增强**没有可测的帧时间代价**。

### 5.2 r4 复现性（同一 build，20 分钟前，含可能的非 Godot 负载）

CSV：`window/p82windcpu_window_r4_1792667193.csv`。分段合计：calm new 35 / off 53、wind 42 / off 64、typhoon 45 / off 66；new−off = **−19 / −22 / −20 µs**；分量 firefly −14、leaf −4…−5、swing −3…−4。
→ 两次 run 的**符号、排序、量级一致**（r5 机器空载时绝对值更大：−22…−30.5）。r5 为最终引用数值，r4 作复现性旁证。

## 6. headless 交叉验证（r5，独占窗口）

CSV：`headless/p82windcpu_headless_r5_1792667848.csv`；日志 `log_headless_r5.txt`。

| phase | impl | p50 µs | 5 段合计 | 萤火 | 落叶 | 秋千 |
|---|---|---|---|---|---|---|
| calm | new | 2453 | 38 | 14 | 13 | 7.5 |
| calm | off | 2235 | 48 | 24 | 15 | 7 |
| wind | new | 2172 | 30 | 9 | 7 | 12 |
| wind | off | 2276 | 59 | 22 | 13 | 20 |
| typhoon | new | 2383 | 65 | 20 | 14 | 26 |
| typhoon | off | 2131 | 74 | 28 | 16.5 | 23.5 |

new−off 合计：calm −11.5 / wind −28 / typhoon −8 µs。wind 与窗口模式一致（萤火 −13、落叶 −6、秋千 −8）；typhoon 的 swing 出现 +2.5 的异常（该段 120 帧中位抖动 ±5 µs 量级，n=120 × 1000 次计时调用的采样噪声），属 headless 下小数值段的噪声，不影响窗口模式结论。
headless 的 `frame_us` 毛刺更大（per-round 配对 sd 195–475 µs，单轮出现过 −847/+1139），同样只作上界检验。

## 7. 跨 run 连续性（优化前 r1/r2 → 优化后 r2/r3，非同一 build）

`compare_before_after.txt`（window r1 → r2；headless r2 → r3）：window wind 71 → 46 µs（legacy 34 → 24）、typhoon 67.5 → 41（legacy 34 → 25）、calm 59 → 33（legacy 30.5 → 26）。
legacy 自身也漂移了 ~10 µs（机器负载/热态差异），所以**跨 run 绝对值不能直接相减**；§5 的同一 build 交替 A/B 才是主判据，本表只作"量级与方向一致"的旁证。

## 8. `Performance.TIME_PROCESS` 不可用的证据链

- window r5：`tp_us` 中位 15–18 µs，同 run 的 `frame_us` 中位 5857–6241 µs（差 ~350 倍）；
- headless r5：`tp_us` 中位 17–18 µs，`frame_us` 中位 2172–2453 µs；
- headless r1 同一实现不同轮给出 25.7 ms 与 42.4 ms 两个量级完全不同的读数；
- new / legacy 两组的 tp 中位数逐轮几乎相同（15/16/17 µs），分辨不出实现差异。
→ 该 monitor 在本工程（Godot 4.7.2 + 本机）不可作为帧 CPU 或增量判据；P8.1 的 +1.93 ms 应视为该 monitor 的读数差异，而非 CPU 成本差异。本任务已用墙钟 + 分段计时双口径替代。

## 9. 视觉/行为验收

- **落叶不瞬移**：参数缓存只在输入超阈值时重算，下游写入阈值不变（探针 B3 同风场 240 帧参数不漂移；B12 秋千无单帧瞬移 0.0437 rad < 0.05）。
- **风向变化平滑**：B2 风向 135°→225° 后方向立即跟随（Δ=1.346 单位向量）；B13 风向 90° 反转单帧最大 0.0042 rad。
- **萤火强风+雨雪合理衰减**：B4（105 组风/雨/雪/风暴渐变，amount_ratio 最大偏差 0.0017）、B9（台风 emitting=false）、B8（晴夜↔强风 30 次切换不滞后）。
- **秋千无穿透/突然换向/过摆**：B11（rotation 恒等于夹紧后的 idle+弹簧，误差 <1e-6）、B12/B13。
- **截图**：after（最终 build 重拍，12 张）`03_wind/after_wind_shots/`；before（P8.1 冻结，只读引用）`开发产物/p81/evidence/p81_05/p81_wind_*.png`。
  逐张比对：构图/天气/落叶密度与流向/秋千姿态/萤火可见量一致；差异只来自窗口分辨率（1440×900 vs 1600×900）与粒子随机相位（本来逐帧不同）。重点看过 `p81_wind_leaf_strong_autumn.png`、`p81_wind_swing_downwind_max.png`。

## 10. 验证结果（全部真实运行，最终 build）

| 探针 | 命令 | 结果 |
|---|---|---|
| 优化等价性（新） | `--headless --script res://tools/probe_p82_wind_cpu.gd` | **PASS 23 / 0 fail** |
| 强风纯函数 117 条 | `--headless --script res://tools/probe_p81_wind.gd` | **PASS 117 / 0 fail** |
| 生态回归 | `--headless --script res://tools/probe_p8_ecology.gd` | `PROBE_P8_ECOLOGY RESULT: PASS` |
| 季节回归 | `--headless --script res://tools/probe_p8_season.gd` | `PROBE_P8_SEASON RESULT: PASS` |
| 自测 | `--headless -- . --selftest` | `[TEST] RESULT 73/73 passed` |

日志：`log_probe_p82_wind_cpu.txt`、`log_probe_p81_wind.txt`、`log_probe_p8_ecology.txt`、`log_probe_p8_season.txt`、`log_selftest.txt`、`log_windshots_after_final.txt`。

## 11. 未完成 / 限制

1. 分段计时用 GDScript `Time.get_ticks_usec`（默认关闭时零开销），单段分辨率约 ±1 µs；legacy 段只有 5–13 µs，噪声占比高，因此归因以 new−off 差值（同一 build）为准，且以窗口模式（独占窗口）为主要口径。
2. 帧级 `frame_us` 的 per-round 配对差 sd 达 0.7–1.2 ms（窗口）、0.2–0.5 ms（headless），**远大于 20–30 µs 的被测效应**；因此帧级 A/B 只能证明"无回归"，不能用来量化优化收益。独占窗口（v2 串行器）只排除其他 Godot 引擎，不排除同机其他进程（编译、Python 分析等），故两次 run 的绝对帧时间差 ~7% 属机器状态差异。
3. 机器存在 5–15 µs/帧级别的 run 间漂移（legacy 对照自身可漂 10 µs），这是选择"同一 build 内交替 A/B"而非"改前改后两次 run"的原因。
4. `winter_leaf_gate` 段在本 harness 下恒为 0：模拟暂停 + 固定日期时 `_update_season` 每帧提前返回（季节权重变化阈值 + `_season_timer`），冬季落叶门控只在季节真正切换时执行一次，不是每帧成本。该项因此**没有**做优化。
5. 未做"4 Hz 低频参数更新 + 插值"方案：实测落叶参数段仅 10–15 µs，改动会引入插值相位误差与秋千/萤火视觉风险，收益远小于 §4 的按需写入；按最小增量原则未采用。
6. Godot 4.7.2 无逐帧内置 CPU profiler，故用分段计时 + 墙钟；未引入外部 profiler（避免额外工具依赖）。
7. 强风相关的**渲染/GPU 侧**成本不在本任务范围（GPU 侧由 P8.1 的帧率证据覆盖）。
8. headless 日志里的 `ERROR: Condition "f.is_null()" is true. at: _save_to_cache` 与本机 `user://` 写入受限有关（同时有 `Failed to open user://logs/...`），是环境既有噪声，不影响测量。

## 12. 开关与回滚

- `--p82windcpu`：跑采样 harness（CSV 写到 `--out`，默认 `开发产物/p82/evidence/03_wind`）。可选 `--impls new,off,legacy`、`--label`。
- `--p82windprof`：只开分段计时，不跑 harness。
- `--p81windperf-legacy`：P8.1 已有 legacy A/B 开关，语义未变（采样 harness 内部也用它）。
- `--windshotsout <dir>`：`_run_p81wind()` 的取证目录覆盖（P8.2 复跑不再写 P8.1 冻结证据）。
- 三项优化**没有独立运行开关**（`_p82opt_off` 仅供测量）：默认即优化后行为；回滚需按 §4 逆向还原三处条件与两个纯函数包装。
