# P8.2-02 性能测量报告（A/A 噪声底 + A/B new-vs-base）

执行：wind（task-7）。测量对象：P8.2 视觉/灯光改造（lighting 的 02 提交）相对 P8.1 冻结基线 `ddcde3a` 的帧时间与灯光质量差异。

> 本文只放**测量**结论。视觉/灯光内容验收见 `docs/P8_2_02_NOTES.md`（lighting）与总体报告。
> 原始数据与日志：`D:/休闲小岛幻境/开发产物/p82/evidence/02_perf/`（git 外）。

---

## 1. 方法学（可复现）

### 1.1 运行环境与串行化
- 引擎：Godot 4.7.2 stable（console 版），Windows，GPU NVIDIA GeForce RTX 2060（165W 限制）。
- 所有引擎运行经全局串行器 `D:/休闲小岛幻境/开发产物/p82/run_godot.sh`（v3）：先拿目录锁，再等**所有既有 Godot 引擎进程退出**，日志打印 `[run_godot] exclusive window pid=...` 后才启动；单次运行出现 2 个 Godot pid（console 启动器 + 运行版子进程）属正常。
- 只有日志含 `exclusive window` 且期间无并发引擎的 run 才计入。19:41 之前的 v1/v2 串行器存在独占确认 bug，那段时间的计时数据一律作废（见 `aa/`，仅作"窗口模式噪声大"的旁证）。

### 1.2 探针
- `tools/probe_p82_perf_ab.gd`（SceneTree 脚本，窗口模式，无头不适用）：实例化 `res://isle.tscn` → 跳菜单 → 固定日期/天气（`_p8_wfx_apply` 含 weather reset + 累计 240s 步进）→ 固定机位（`_p8_camera_island/_p8_camera_tree/_p8_camera_inside` 与壁炉/码头定点）→ 按档切画质 → 采样。
- 窗口固定 1600×900（`--resolution 1600x900` + 运行时 8 次 set_size 校验），`DisplayServer.VSYNC_DISABLED`，`Engine.max_fps = 0`（**在 _apply_quality 之后设置**，覆盖 q0/q1 预设的 60 上限，与历史性能口径一致；CSV 里 `preset_max_fps` 保留预设值 60/60/0/0/0）。
- 每单元流程：`_apply_quality(q)` → `Engine.max_fps=0` → 机位 → `settle=0.15s` → warmup 20 帧 → 采样 100 帧。
- 帧时间 = 相邻 `process_frame` 恢复点之间的墙钟差（`Time.get_ticks_usec`），包含主循环 + 渲染提交 + 交换等待。**不使用 `Performance.TIME_PROCESS`**：P8.2-03 已证实该 monitor 在窗口模式只报 15–18µs，而真实帧 6ms，是伪影（详见 `docs/P8_2_03_NOTES.md`）。
- 每 cell 同时记录：draw calls、objects、VRAM、`debug_light_state()`（active/budget/out/in/室内外池）、msaa_3d、scaling_3d_scale、日期、天气、season、`cell_unix`。

### 1.3 场景矩阵（7 场景 × q0..q4 = 35 单元/run）
| key | 日期/时间 | 天气 | 机位 |
|---|---|---|---|
| clear_day_outdoor | 2026-07-15 10:00 | clear | island |
| winter_white_outdoor | 2027-01-15 11:00 | heavy_snow（accum 30000s） | island |
| indoor_night | 2027-01-15 20:30 | clear | inside |
| fireplace_close | 2027-01-15 20:30 | clear | fireplace（cottage front/right + fireplace_world 定点） |
| dock_night | 2027-01-15 20:30 | clear | dock（_boat_dock_pos/heading） |
| heavy_rain | 2026-07-15 14:00 | heavy_rain（accum 600s） | island |
| heavy_snow_close | 2027-01-15 11:00 | heavy_snow（accum 30000s） | tree |

### 1.4 跨 run 漂移抑制（关键）
早期设计（70 cell/run、2 sweeps、无 warm-up）在 A/A 下出现 **12–25% 的 run 间漂移**（|d_p50| 中位 983µs、max 2218µs），完全淹没 A/B 差异。原因是：每个 run 起始的 GPU 热/时钟状态不同 + v2 串行器独占失效期间的并发窗口。最终设计加了三层抑制：

1. **soak=8s 热稳态**：boot 后先固定首场景 + q2 连续渲染 8 秒，再开始采样。让每个 run 从同一热状态出发（GPU 时钟/风扇/驱动队列）。
2. **短 run（35 cell 单 sweep，~59s/run）**：缩短单个 run 暴露给外部负载的窗口；只做 1 个 sweep。
3. **位置平衡 ABBA**：A/B 标签在 run 序列上位置均值相同（4 runs 时 A=位置 1,4，B=2,3；8 runs 时 A=1,4,6,7，B=2,3,5,8），线性/慢变漂移在组均值中抵消。
4. 辅助：每 cell 记录 `cell_unix`、每 run 记录开始/结束 unix 与 nvidia-smi 温度/频率；异常 run 可事后标记重跑。

### 1.5 A/B 两侧的构建与缓存口径
- base 侧：`D:/休闲小岛幻境/开发产物/p82/ab_meas/base_copy`（`ddcde3a` 的 `cp -r` 副本，含 P8.1 冻结时的 `.godot` 导入/着色器缓存）。
- new 侧：`git worktree add --detach D:/休闲小岛幻境/开发产物/p82/ab_meas/new_wt <冻结SHA>`，再把**同一份 `p82/base/.godot` 复制进 new_wt**——两侧 import/shader 缓存同源，避免"new 侧首次冷启动重建缓存"造成的单向偏差；探针文件同步复制两份。
- 即便缓存同源，new 侧新增/改动的 shader 仍需首次编译。因此 A/B 开始前**两侧各做 1 次不计时的 warmup run**（同 soak、同 35 cell，结果的耗时数据丢弃，只把缓存固化；记录 start/end unix），随后立即进入 8 个计时 run，并确认 warmup 与计时 run 之间没有其它引擎 run 插入（tasklist + 锁日志核对）。
- 两侧 `git rev-parse HEAD` 与 `git status --porcelain` 必须记录；new_wt 必须 `dirty=0`，否则 abort。
- **冻结测量树 = `befdb0f`**（P8.2-02-a `ca22d08` + 02-b `befdb0f`，含 lighting 的全部灯光/场景/着色器改动）。其后仓库里的提交只有 tools/docs/UI 面板类改动（wheel 的 `ui_datetime_wheel.gd` 常量一行、探针 `OUT_DIR` 一行、各 NOTES），**不进入渲染/场景/环境路径**；计时场景 HUD 隐藏、无滚轮 UI，所以以 `befdb0f` 作为 new 侧冻结 SHA 是有效口径。

---

## 2. A/A 噪声底（同一份 base_copy 跑两遍）

4 runs 顺序 `aaA_r1 → aaB_r1 → aaB_r2 → aaA_r2`，两侧都是 `D:/休闲小岛幻境/开发产物/p82/ab_meas/base_copy`（`ddcde3a` 的副本，带同一份 .godot 缓存）。每 run：soak 8s + 35 cell × 100 帧，59s 左右，全部 exit=0 / exclusive=1 / cells=35。

| run | 开始 | p50 均值 µs | p95 均值 µs | 备注 |
|---|---|---|---|---|
| aaA_r1 | 19:46:29 | 6385 | 9544 | |
| aaB_r1 | 19:47:33 | 6275 | 9391 | |
| aaB_r2 | 19:48:35 | 6337 | 9546 | |
| aaA_r2 | 19:52:24 | 6289 | 9411 | 中间被别人的 2 个 run 插队，隔 6 分钟 |

- run 级离散：p50 均值跨度 **110µs（1.7%）**；相隔 6 分钟的 aaA_r1 vs aaA_r2 差 96µs。
- 单元级（35 单元，位置平衡）：
  - p50：d 中位 **-12µs**；|d| 中位 **38µs**、均值 127µs、p90 **386µs**、max 840µs
  - p95：|d| 中位 244µs、均值 449µs、p90 965µs、max 2198µs
  - |d%|：中位 **0.63%**、p90 5.85%、max 23.55%
- **判定阈值（本文所有 A/B 结论都按此）**：
  - **中位分辨率 38µs**：多单元/多对配对取中位时，可分辨几十 µs 级差异；
  - **单单元判据：|Δp50| < 386µs（p90）不可分辨；≥ 773µs（2×p90）视为显著**；
  - 离群单元集中在场景切换后的首档（winter_white q2）与 indoor_night q0，属机位/画质切换残差，不作为信号。
- 对比：v2+无 soak 时代 A/A 的 |d_p50| 中位 983µs、run 级漂移 12–25%。最终设计把噪声压低约 **25 倍**（中位 983 → 38µs）。

---

## 3. A/B：new（02 视觉冻结）vs base（ddcde3a）

执行：`warmup_base → warmup_new →` 8 个计时 run（顺序 `base,new,new,base,new,base,base,new` = ABBA 位置平衡，base 位置 1/4/6/7、new 位置 2/3/5/8，位置均值都 4.5）。new 侧 = `new_wt`（detached 冻结 SHA）+ 与 base_copy 同源的 .godot 副本；两侧各 warmup 一次固化缓存。

| # | run | side | 开始 | 结束 | p50 均值 µs | 校验 |
|---|---|---|---|---|---|---|
| — | ab_warmup_base | base | 20:10:49 | 20:12:03 | 7629 | exit0/excl1/cells35（不计时） |
| — | ab_warmup_new | new | 20:12:04 | 20:13:17 | 7681 | 同上（不计时） |
| 1 | ab_base_1 | base | 20:13:18 | 20:14:30 | 7784 | exit0/excl1/cells35 |
| 2 | ab_new_1 | new | 20:14:31 | 20:15:43 | 7580 | 同上 |
| 3 | ab_new_2 | new | 20:15:44 | 20:16:56 | 7553 | 同上 |
| 4 | ab_base_2 | base | 20:16:57 | 20:18:06 | 7366 | 同上 |
| 5 | ab_new_3 | new | 20:18:07 | 20:19:16 | 7435 | 同上 |
| 6 | ab_base_3 | base | 20:19:16 | 20:20:27 | 7424 | 同上 |
| 7 | ab_base_4 | base | 20:20:28 | 20:21:38 | 7420 | 同上 |
| 8 | ab_new_4 | new | 20:21:39 | 20:22:50 | 7422 | 同上 |

两侧 SHA：base = ddcde3ae6d4203182155f41041e0dcd0da5f7c09、new = befdb0f4a67e00d1c3b2c2d6a0367d5e6dc662bf；两侧 git status 除手工复制的探针文件外为空（dirty=0）。CSV/日志：evidence/02_perf/ab/ 与 logs/ab_*.txt。

### 3.1 逐单元帧时间（base vs new，中位 µs）
（每 cell 先取该侧 4 个 run 的中位；d = new − base，正 = new 更慢；DC 差异 ≤2，激活灯数两侧完全一致 10/11/12/14/16。）

| scene | q | base_p50 | base_p95 | new_p50 | new_p95 | d_p50 | d% | 判定 |
|---|---|---|---|---|---|---|---|---|
| clear_day_outdoor | q0 | 6885 | 9545 | 6893 | 8163 | +8 | +0.1% | 噪声内 |
| clear_day_outdoor | q1 | 6750 | 7756 | 6807 | 8607 | +57 | +0.9% | 噪声内 |
| clear_day_outdoor | q2 | 6736 | 8056 | 6737 | 8624 | +1 | +0.0% | 噪声内 |
| clear_day_outdoor | q3 | 9969 | 10355 | 9961 | 10381 | -7 | -0.1% | 噪声内 |
| clear_day_outdoor | q4 | 11841 | 12309 | 11830 | 12278 | -11 | -0.1% | 噪声内 |
| dock_night | q0 | 4471 | 6030 | 4148 | 4863 | -323 | -7.2% | 噪声内 |
| dock_night | q1 | 4396 | 5840 | 4494 | 5760 | +98 | +2.2% | 噪声内 |
| dock_night | q2 | 5761 | 5980 | 5781 | 5981 | +19 | +0.3% | 噪声内 |
| dock_night | q3 | 8873 | 9181 | 8905 | 9110 | +32 | +0.4% | 噪声内 |
| dock_night | q4 | 10239 | 10497 | 10365 | 10824 | +126 | +1.2% | 噪声内 |
| fireplace_close | q0 | 4568 | 5861 | 4040 | 5848 | -528 | -11.6% | 可疑（<2×p90） |
| fireplace_close | q1 | 4158 | 5056 | 4014 | 4582 | -144 | -3.5% | 噪声内 |
| fireplace_close | q2 | 4620 | 6412 | 4595 | 4834 | -25 | -0.6% | 噪声内 |
| fireplace_close | q3 | 7155 | 7355 | 7309 | 7472 | +154 | +2.2% | 噪声内 |
| fireplace_close | q4 | 8193 | 8486 | 8418 | 8859 | +224 | +2.7% | 噪声内 |
| heavy_rain | q0 | 7563 | 10116 | 7308 | 9249 | -255 | -3.4% | 噪声内 |
| heavy_rain | q1 | 6986 | 8563 | 7264 | 9403 | +277 | +4.0% | 噪声内 |
| heavy_rain | q2 | 7021 | 8962 | 7456 | 9192 | +434 | +6.2% | 可疑（<2×p90） |
| heavy_rain | q3 | 10645 | 10937 | 10677 | 10930 | +32 | +0.3% | 噪声内 |
| heavy_rain | q4 | 12398 | 13547 | 12531 | 13699 | +133 | +1.1% | 噪声内 |
| heavy_snow_close | q0 | 4893 | 6162 | 4863 | 6403 | -29 | -0.6% | 噪声内 |
| heavy_snow_close | q1 | 4767 | 5808 | 4656 | 5489 | -110 | -2.3% | 噪声内 |
| heavy_snow_close | q2 | 6146 | 6440 | 6173 | 6492 | +27 | +0.4% | 噪声内 |
| heavy_snow_close | q3 | 9561 | 9741 | 9571 | 9825 | +10 | +0.1% | 噪声内 |
| heavy_snow_close | q4 | 11544 | 12001 | 11460 | 12078 | -83 | -0.7% | 噪声内 |
| indoor_night | q0 | 4203 | 5137 | 4501 | 5428 | +297 | +7.1% | 噪声内 |
| indoor_night | q1 | 4228 | 4961 | 4401 | 5463 | +173 | +4.1% | 噪声内 |
| indoor_night | q2 | 4918 | 6241 | 4926 | 6103 | +8 | +0.2% | 噪声内 |
| indoor_night | q3 | 7644 | 7798 | 7677 | 7857 | +33 | +0.4% | 噪声内 |
| indoor_night | q4 | 8834 | 9379 | 9009 | 9536 | +175 | +2.0% | 噪声内 |
| winter_white_outdoor | q0 | 7144 | 9574 | 7715 | 10602 | +570 | +8.0% | 可疑（<2×p90） |
| winter_white_outdoor | q1 | 6990 | 8572 | 7040 | 8924 | +49 | +0.7% | 噪声内 |
| winter_white_outdoor | q2 | 7135 | 9173 | 6975 | 8897 | -159 | -2.2% | 噪声内 |
| winter_white_outdoor | q3 | 10332 | 10721 | 10367 | 10729 | +35 | +0.3% | 噪声内 |
| winter_white_outdoor | q4 | 12388 | 13306 | 12363 | 12895 | -25 | -0.2% | 噪声内 |

**统计：32/35 单元 |Δp50| < 386µs；3 个落在 386–773µs（fireplace q0 −528、heavy_rain q2 +434、winter_white q0 +570，方向有正有负，均 < 2×p90）；0 个 ≥ 773µs（显著）。** 逐 cell |Δp50| 中位 83µs、p90 323µs、max 570µs；35 个 Δ 的中位 +27µs（+0.4% 量级）。

> 注意 heavy_rain q0 在 base 侧 p95 高达 10116µs、dock/fireplace/base 的 p95 也高于 p50 很多（这些场景在 100 帧里偶发长帧），p95 差异不作为判据；判定只用 p50。

### 3.2 场景汇总（5 档中位帧时间几何均值）
| scene | base | new | d | d% |
|---|---|---|---|---|
| clear_day_outdoor | 8195 | 8208 | +14 | +0.2% |
| dock_night | 6346 | 6303 | -43 | -0.7% |
| fireplace_close | 5525 | 5399 | -126 | -2.3% |
| heavy_rain | 8669 | 8806 | +137 | +1.6% |
| heavy_snow_close | 6916 | 6873 | -43 | -0.6% |
| indoor_night | 5678 | 5833 | +154 | +2.7% |
| winter_white_outdoor | 8547 | 8655 | +108 | +1.3% |

### 3.3 画质汇总（7 场景中位帧时间几何均值）
| q | base | new | d | d% | 逐 cell d% 中位 |
|---|---|---|---|---|---|
| q0 | 5521 | 5449 | -72 | -1.3% | -0.60% |
| q1 | 5326 | 5370 | +44 | +0.8% | +0.85% |
| q2 | 5974 | 6010 | +36 | +0.6% | +0.16% |
| q3 | 9080 | 9127 | +47 | +0.5% | +0.34% |
| q4 | 10652 | 10743 | +91 | +0.9% | +1.08% |

q0–q4 的帧时间几何均值差全部 ≤ 91µs（≤1.3%），远低于单单元 386µs 的 A/A 噪声底；q0 是唯一一档几何均值变快（-72µs / -1.3%），q1–q4 变慢 +36…+91µs（+0.5…+0.9%），方向混合、量级在噪声内。

### 3.4 与噪声底的关系（判定）
- 判定口径：|Δp50| < 386µs（A/A p90）不可分辨；≥ 773µs（2×p90）显著；跨单元中位差的分辨率约 38µs。
- **画质维度**：q0 -72µs / q1 +44 / q2 +36 / q3 +47 / q4 +91µs，全部 < 386µs → **五档均无超出噪声底的回归**（q0 反而略快，但同样在噪声内，不宣称"优化生效"）。
- **场景维度**：7 个场景的 5 档几何均值差 -126…+154µs（-2.3%…+2.7%），最大 fireplace_close -2.3%（new 更快）与 indoor_night +2.7%（new 更慢），方向混合、均 < 386µs → 无场景级回归。
- **单元维度**：32/35 在噪声内；3 个 386–773µs 的"可疑"单元（fireplace q0 -528、heavy_rain q2 +434、winter_white q0 +570）方向不一致，且同场景其它档大体反向（如 fireplace q4 +224），符合 A/A 中同类高方差单元的表现（A/A 里 fireplace q0 也曾有 +839µs），**判定为噪声，非回归**；0 个单元 ≥ 773µs。
- 结论：**lighting 的 P8.2-02 视觉/灯光改造相对 P8.1 基线无可测帧时间回归（相对预算 0，噪声底内）；q0 绝对 FPS 见 §4。**
- 过程健康度：10 个 run 全部 exit=0 / exclusive=1 / cells=35；pre-run godot 进程检查全空；GPU 温度 59–66°C；run 间 GPU 时钟从空闲 1365MHz 回升到 ~1860MHz（每次 run 结束 ~1860、下次 start 前回落到 idle），soak 8s 就是为把每次都拉到同一热/时钟状态；warmup run 的帧时间（base run 均值 7629 / new 7681µs）与随后计时 run 同量级，说明缓存确已预热。

## 4. 绝对帧时间与灯光质量基线

### 4.0 q0 绝对帧时间/帧率（new = befdb0f；由 p50 换算）
| scene | base µs | base fps | new µs | new fps | Δfps |
|---|---|---|---|---|---|
| clear_day_outdoor | 6885 | 145.2 | 6894 | 145.1 | -0.1 |
| dock_night | 4472 | 223.6 | 4148 | 241.1 | +17.5 |
| fireplace_close | 4568 | 218.9 | 4040 | 247.5 | +28.6 |
| heavy_rain | 7563 | 132.2 | 7308 | 136.8 | +4.6 |
| heavy_snow_close | 4893 | 204.4 | 4864 | 205.6 | +1.2 |
| indoor_night | 4204 | 237.9 | 4501 | 222.2 | -15.7 |
| winter_white_outdoor | 7144 | 140.0 | 7715 | 129.6 | -10.4 |

- q0 的 7 场景几何均值：base 5521µs（≈181.1fps）→ new 5449µs（≈183.5fps），**+1.3% 吞吐（噪声内）**。
- **q0 ≥ 170fps 遗留门：未达**。new 侧只有 dock_night(241)、fireplace_close(247)、indoor_night(222)、heavy_snow_close(206) 过了 170；clear_day_outdoor 145、heavy_rain 137、winter_white_outdoor 130 均 < 170。**这是本机当前状态，不宣称通过、不改阈值。**
- 与 P8.1 的 heavy_rain_q0 166.1fps 相比，本轮同场景 132–137fps 明显更慢：机器/驱动/窗口模式噪声与当时不同，**不可直接比较**（见 §4.1），本报告不以历史数字为基线。

### 4.1 灯光质量关键差异（new 侧；base 侧激活灯数与 new 完全一致）
- 激活灯数随画质（7 场景全部一致）：q0 **10/10**（budget 10；outdoor pool 7 + indoor pool 3）、q1 11/11、q2 12/12、q3 14/14（out 10 + in 4）、q4 **16/16**（out 10 + in 6）——说明灯光预算/室内外池分配在两侧未改变激活数量。
- 关键画质项：msaa_3d = 0/1/2/3/3；scaling_3d_scale 0.85/0.92/1.0/1.15/1.25；preset_max_fps 60/60/0/0/0（测量时统一覆盖为 0）。
- draw calls：clear_day/heavy_rain/winter ~1838–1844（两侧差 ≤2）；dock 471–472；heavy_snow_close 754–760；**fireplace_close 448→435（new，-13，全部 5 档一致）**——与 02(a) 室内吊灯光晕、02(b) 解析光槽调整后的场景差异一致，是唯一可解释的静态差异，未带来帧时间回归。
- 结论：本报告确认**灯光质量档间差异（10→16 激活灯）与静态绘制负载（draw calls/VRAM）**，灯光视觉验收归 docs/P8_2_02_NOTES.md。

### 4.1 与 P8.1 历史数字的关系
P8.1 报告过 heavy_rain_q0 6.02ms / 166.1fps（门 ≥170 未达）。本轮 harness、帧数、机器状态与当时都不同（本机当前 q0 实测约 159–166fps），**两者不可直接比较**，本报告：
1. 只用**相对回归是否超出 A/A 噪声底**判定；
2. 只给 q0..q4 的帧时间与激活灯数是否符合预算的结论；
3. 不宣称 ≥170 门通过，也不把历史 166 当本轮基线。

## 5. 复现命令
```bash
EV="D:/休闲小岛幻境/开发产物/p82/evidence/02_perf"
# A/A 噪声底（4 runs，~4 分钟 + 锁排队）
bash "$EV/run_aa2.sh"
cd "$EV" && "C:/Users/Administrator/.dsh/dsh-runtimes/dsh-primary-runtime/dependencies/python/python.exe" analyze_aa2.py aa2 > aa2/analysis_aa2.txt
# A/B（8 runs，~8 分钟 + 锁排队）；先看 scripts 注释里的 new_wt 准备步骤
bash "$EV/run_ab.sh"
cd "$EV" && "C:/Users/Administrator/.dsh/dsh-runtimes/dsh-primary-runtime/dependencies/python/python.exe" analyze_ab.py ab > ab/analysis_ab.txt
```

## 6. 限制
- 窗口模式 + 单 GPU：帧时间含 GPU 提交与交换阻塞，绝对值受机器当前状态影响；p99 只作参考（100 帧，p95 更稳）。
- 同机并行 agent 的 CPU/IO 负载无法完全排除：靠 v3 独占 + soak + ABBA + 短 run 抑制，并用 `cell_unix` 事后核对。
- A/A 的离群单元（winter_white q2 等）说明"场景切换后第一档"有残差；A/B 判定以中位与多对配对为准，不以单单元单次值下结论。
