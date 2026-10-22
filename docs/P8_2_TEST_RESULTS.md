# P8.2 测试证据索引（TEST RESULTS）

本文件是 **P8.2「工程收尾 / 精修」** 的测试证据索引：每个模块一行，给出探针/脚本、可复现命令、
结果数字、证据绝对路径、判定，以及**预存在失败**的标注。它是证据索引不是分析报告；分析结论以
各模块 owner 的报告与 docs/P8_2_REFINEMENT_REPORT.md 为准，本文件负责"结论能否追溯到证据"。

- 生成时间：2026-10-22（P8.2 收尾阶段）
- 分支：p82-integration（基线 ddcde3a = P8.1-08 冻结）
- 引擎：D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe（4.7.2.stable）
- 机器：NVIDIA GeForce RTX 2060（Vulkan 1.4.351），Windows，单 GPU 单实例
- 证据根（git 外）：D:/休闲小岛幻境/开发产物/p82/

## 0. 口径与证据分层

| 层 | 内容 | 位置 |
| --- | --- | --- |
| P8 历史证据 | P8 生态/季节/月相/天气系统测试与报告 | D:/休闲小岛幻境/开发产物/p8/、docs/P8_*_TEST_REPORT.md、docs/P8_TEST_RESULTS.md |
| P8.1 证据 | P8.1 精修（12 类天气/冬季白化/灯光预算/发布重建） | D:/休闲小岛幻境/开发产物/p81/、docs/P8_1_TEST_RESULTS.md、docs/P8_1_REFINEMENT_REPORT.md |
| P8.2 新证据 | 本阶段 01..06 模块证据 | D:/休闲小岛幻境/开发产物/p82/（01_fireplace、evidence/03_wind、04_winter、05_wheel、06_matrix、06_soak、release_preview、integrity） |

判定约定：
- **PASS**：探针自带 PASS 且证据文件齐全（退出码 0）。
- **GAP**：证据缺失/未登记（不影响历史结论，但最终报告不能引用不存在的证据）。
- **预存在失败**：P8.2 之前就存在、本阶段未修复或已披露的失败项，必须在本表标注，不能算作 P8.2 回归。
- **环境性噪声**：user:// 不可写导致的日志 ERROR、shader_rd _save_to_cache ERROR、Windows 系统证书读取 ERROR，
  每次真实运行都会出现，与产品行为无关（判定时排除）。

> **selftest 分母核对（Lead 修正，原记录有误）**：分母在 P8.1/base(ddcde3a)、P8.2 HEAD、正式发布包**三方完全一致，均为 73/73**。
> 此前「P8.2 HEAD 变成 75/75、新增 2 项」的说法是误读：`[TEST]` 行数 75 = **73 项 PASS + 1 项 SKIP（真实鼠标拖动，headless 下跳过）+ 1 行 RESULT**，不是 75 项断言。
> 证据（三份日志逐字同构）：`基线/selftest_HEAD_ddcde3a.log`、`final/20261022_205425/selftest.log`、`release_preview/build_20261022_214845/verify_selftest.log` → 各 `73 PASS / 1 SKIP / 1 RESULT`。



所有 Godot 运行必须走全局串行器（单 GPU 单实例锁，排队上限 30 分钟）：

    cd "D:/休闲小岛幻境/游戏工程" && bash "D:/休闲小岛幻境/开发产物/p82/run_godot.sh" --path . --resolution 1600x900 --script res://tools/probe_p82_xxx.gd -- <探针参数>

运行前如遇陈旧锁（进程被强杀时 trap 不执行）：

    rm -rf "D:/休闲小岛幻境/开发产物/p82/.engine.lock"

---

## 1. 发布包复现性证据（单列）

P8.2 改动后必须能证明"发布包仍可复现"，本阶段用**只读基线副本 + 新构建脚本**做了闭环验证：

| 项 | 数值 |
| --- | --- |
| 构建脚本 | D:/休闲小岛幻境/开发产物/p82/build_release.sh |
| 导出源 | D:/休闲小岛幻境/开发产物/p82/base（detached ddcde3a 只读副本，含 .godot） |
| 命令 | bash build_release.sh --skip-git --project="D:/休闲小岛幻境/开发产物/p82/base" --out="D:/休闲小岛幻境/开发产物/p82/release_preview/base_preview" |
| 产物 | D:/休闲小岛幻境/开发产物/p82/release_preview/base_preview/休闲小岛幻境.exe |
| 体积 | 117,238,104 B |
| SHA256 | c40376ad2dda1d8eb2e9848ca8a2ce00e4c1a841a03444fa9e9b80ef5d62b668 |
| 对照 | 与 P8.1 冻结发布包 **发布/休闲小岛幻境.exe 完全相同**（同 size 同 sha256） |
| 验收 | --headless --quit EXIT 0；--headless -- --selftest 73/73 passed EXIT 0 |
| 包内容 | savepack 113 文件；res://tools/ docs/ shots/ refshots/ addons/ sounds/ *.md 全 0；res://scripts/main.gd 在包；autoload/_mcp_game_helper 已剥离 |
| 独立复验 | bash verify_release.sh --exe=<预览包> --expect-sha256=... --expect-size=117238104 --expect-selftest=73/73 → RESULT PASS；对 发布/ 包同样 PASS |
| 日志 | D:/休闲小岛幻境/开发产物/p82/release_preview/base_preview.log、base_preview/build.log、release_preview/verify_runs.log、verify_preview/、verify_release_pkg/ |

结论：**P8.1 冻结包可由新脚本逐字节复现**（导出管线可复现），且 发布/ 在本阶段未被覆盖
（verify_release.sh 用 integrity/release_exe_before.txt 记录的 sha256 复核仍一致）。
最终代码冻结后仍需用 build_release.sh --copy-to-release 生成 P8.2 正式包并重新验收。

### 1.1 P8.2 正式包（已重建并验收，2026-10-22 21:48–21:53）

> 本小节在**代码冻结、build_release.sh --copy-to-release 成功、verify_release.sh PASS** 之后填写（已满足）。
> 旧 P8.1 包数字仅用于对照，不作为本节结论。

| 项 | 值 |
| --- | --- |
| 构建 commit | `f5f2fef431db351f5aeeb016c5e1ce5aa6c98a10`（record.json `git_head`，构建时工作树干净） |
| 构建时间 | 2026-10-22 21:48:45（stamp `20261022_214845`） |
| 命令 | `bash 开发产物/p82/build_release.sh --copy-to-release`（日志 `开发产物/p82/build_release_run_214845.log`，verdict=PASS） |
| 导出日志 | `开发产物/p82/release_preview/build_20261022_214845/{record.json,build.log,verify_quit.log,verify_selftest.log,savepack_list.txt}` |
| 正式包路径 | D:/休闲小岛幻境/发布/休闲小岛幻境.exe（同步 构建输出/休闲小岛幻境.exe） |
| 体积 | **117,248,168 B** |
| SHA256 | **`994ea96a635eaacf0cefdc9225474851f9e4c0fc3fba521bf049ab80bc243795`** |
| --headless --quit | **EXIT 0**，`verify_quit.log` 无 Parse Error / Corrupted header / SCRIPT ERROR |
| --headless -- --selftest | **73/73 PASS + 1 SKIP（真实鼠标拖动）**，EXIT 0 |
| 包内容排除检查 | `savepack_list.txt` 113 行：`res://tools/` 0、`res://docs/` 0、`res://shots/` 0、`res://refshots/` 0、`res://addons/godot_ai/` 0、`*.md` 0、`res://smoke_test.tscn` 0、`res://build/` 0；`res://scripts/main.gd` 在包；`_mcp_game_helper` 0 命中 |
| 与 P8.1 冻结包 c40376ad…b668 的关系 | 体积 **+10,064 B**（117,238,104→117,248,168）、sha256 变化；差异来源 = 本轮脚本改动（`scripts/cottage.gd` 烟囱分段/壁炉凹龛、`scripts/main.gd` 灯光与分段计时、`scripts/world.gd` 栖点、`scripts/ui_datetime_wheel.gd` 常量引用）与 pck 内时间戳相关字节；导出管线本身已由 base 副本预览导出的逐字节复现（同 sha）证明未变；排除项集合与 P8.1 一致 |
| 旧包备份 | `开发产物/backup/release_pre_p82/休闲小岛幻境_pre_p82_20261022_214845.exe`（117,238,104 B，sha256 c40376ad…b668，含旧 size/sha 记录；回滚即 cp 回 `发布/` 与 `构建输出/`） |
| 独立验收 | `bash verify_release.sh --exe="D:/休闲小岛幻境/发布/休闲小岛幻境.exe" --expect-sha256=994ea96a… --expect-size=117248168 --expect-selftest=73/73` → **RESULT PASS**（EXIT 0，`开发产物/p82/verify_release_run_215233.log`，`发布/verify_result_20261022_215233.json`） |

---

## 2. 模块证据索引

### P8.2-01 壁炉 / 室内表现（owner 交付，本索引转录）

| 项 | 内容 |
| --- | --- |
| 提交 | ce6fc30 / 1121f65 / 41c4816（scripts/cottage.gd + tools/probe_p82_fireplace.gd + docs/P8_2_01_NOTES.md） |
| 证据目录 | D:/休闲小岛幻境/开发产物/p82/01_fireplace/（after/、before/、pixel/、regress/、MANIFEST.csv、analyze_fireplace.py、run_after_shots_and_regr.sh） |
| 截图（已定口径） | **after/ 20 张**、**before/ 18 张**；pixel/ 16 张（像素级对比）。after 20 = before 同机位 18 张 + q2_attic_breast + day_attic_breast：原阁楼机位被床/屋面遮挡，改机位后新增两张；before 侧是只读副本 ddcde3a，无法也不应补拍 → 两侧张数天然不同，**不是缺失** |
| MANIFEST | D:/休闲小岛幻境/开发产物/p82/01_fireplace/MANIFEST.csv：逐张 filename/width/height/bytes/sha256，after 20 + before 18（共 38 行），按 "# dir=after" / "# dir=before" 分节 |
| 尺寸 | 全部 2560x1440（真实窗口截图，非 1600x900；与 06_matrix 分辨率不同，比较像素统计时需注意） |
| 日志 | after/after_shots.log、after/shots.log、after/after_geom.log、before/*.log；regress/ 下 cottage6 / p7v2_perch / p81_tree_bird / p8_ecology / scale_house_p7v32 / scale_world_audit 回归日志 |
| 判定 | owner 结论见 docs/P8_2_01_NOTES.md；本索引核对：20/18 张与 MANIFEST 逐张登记一致，尺寸统一 |
| 预存在 | regress/scale_house_p7v32.log：252 checks / 245 pass / **7 fail**（light_sources 契约，见 PRE-6） |

### P8.2-02 灯光质量 + 五档性能（owner：lighting 视觉 / wind 性能；本索引转录）

| 项 | 内容 |
| --- | --- |
| 提交 | 02(a) `ca22d08`、02(b) `befdb0f`、诊断工具链与 NOTES `4ac7f0f`；性能 A/B `f9123a4` `76787bf` |
| 证据目录 | `D:/休闲小岛幻境/开发产物/p82/02_lighting/`（before/、after/、after_pre_02/、qa/、crop/、report_crop/、regress/、pixel*）与 `开发产物/p82/evidence/02_perf/` |
| 视觉数字 | `day_room_wide` 右上 ROI 近白像素(min>235)：before(base) **42,309** → after(HEAD) **0**；ROI 均值 191.6→125.5（−34.5%）；壁炉光槽同 run 新旧参数 A/B：day 裁切 max=255 **11,634→5,694（−51.0%）**、night **47,125→21,836（−53.7%）**；炉台暖光保留（night 均值 93.1→92.4，hearth p99 208/220，clip 0） |
| 02(c) 悬空球 | 逐盏隔离归因到 `L[13] fireplace`（关它 → ②③ 贡献 57%/63%）；**P8.1 基线 ddcde3a 同样存在** → 无阴影解析光墙热点，**NO-GO 不改**，登记 L-6 |
| 02(d) 过渡带 | 未采纳（g_indoor_band 注册时序不一致 → 整体回滚，全树 grep 0），登记 L-7 |
| 性能 A/B | base=ddcde3a vs new=befdb0f，8 次计时 ABBA + 2 次 warmup；A/A 单元级 |Δ| 中位 38 µs、p90 **386 µs**（显著阈值）；new−base 帧时间几何均值：q0 −72 µs(−1.3%)、q1 +44、q2 +36、q3 +47、q4 +91 µs；7 场景 −126…+154 µs；超过 773 µs 的单元 **0 个** → 无超噪声底回归；激活灯数两侧一致 10/11/12/14/16 |
| q0 绝对 FPS | 7 场景几何均值 181.1→183.5 fps；clear_day 145.2、heavy_rain 132.2、winter_white 129.6 **均 < P8.1 遗留门 170** → 如实登记未达（G-4），与 P8.1 历史 166.1 不可直接比较（本机当前慢 10–20%） |
| 判定 | **视觉 PASS（a/b）**；c/d 如实登记未采纳；**性能 PASS（相对判据）**，绝对 q0 门未达 |

### P8.2-03 风场 / CPU 开销（owner：wind，NOTES 已提交 766ce21；本索引含独立复算）

| 项 | 内容 |
| --- | --- |
| 结论（owner） | ① P8.1 报告的「强风 CPU +1.93 ms」是 `Performance.TIME_PROCESS` 伪影：该 monitor 在窗口模式只报 15–18 µs、headless 17–18 µs，而同一时刻真实帧间隔为 5.9–6.2 ms / 2.0–2.4 ms（差 100–300 倍），且 new/legacy 两组 tp 中位数逐轮几乎相同、无法区分实现；② 强风视觉系统真实成本 **41–47 µs/帧**（窗口 5.9 ms 帧的 **≈0.7–0.8%**；headless 30–38 µs）；③ P8.1-05 增强相对 legacy 的帧级净差在噪声内（-291 / +28 / -206 µs，sd 714–1154，只作“无回归”上界）；④ 三项最小优化在同一 build 交替 A/B 下收回 **19–31 µs/帧（-30%…-39%）**：萤火门控 -14…-17.5、落叶参数缓存 -4…-6、秋千容器复用 -3…-7；⑤ 逐帧等价：probe_p82_wind_cpu 23/0、probe_p81_wind 117/0、selftest 73/73（P8.2 HEAD 现为 75/75）。 |
| 证据目录 | D:/休闲小岛幻境/开发产物/p82/evidence/03_wind/ |
| 主数据（r5 独占窗口，window） | window/p82windcpu_window_r5_1792667748.csv（10800 行）+ log_window_r5.txt + analysis_optab.txt |
| r5 分段合计（new / off / legacy，µs/帧） | calm **41 / 64 / 31**；wind **47 / 78.5 / 31**；typhoon **43 / 75 / 27.5**；new-off = **-22 / -30.5 / -30**（萤火 -16/-17.5/-17、落叶 -6/-6/-6、秋千 0/-7/-7、风向 ≤0 且 0） |
| 复现性（r4，同一 build，20 min 前） | window_r4：calm 35/53、wind 42/64、typhoon 45/66 → new-off **-19 / -22 / -20**，分量 firefly -14、leaf -4…-5、swing -3…-4 → 与 r5 符号/排序/量级一致 |
| headless 交叉验证（r5） | headless/p82windcpu_headless_r5_1792667848.csv：分段合计 calm 38/48、wind 30/59、typhoon 65/74 → new-off **-11.5 / -28 / -8**；typhoon 的 swing +2.5 为小数值段噪声（owner §11.1 已披露） |
| 优化前基线（r1） | window_r1：calm 59/30.5、wind 71/34、typhoon 67.5/34（new/legacy）——对应 NOTES §1 热点表（萤火 32 > 秋千 20 > 落叶 15.5） |
| AB 帧级（r5，n=9 轮 × 120 帧/组） | p50：calm new 5857 / off 6231 / legacy 6028；wind 6236 / 5830 / 6098；typhoon 6241 / 6000 / 6000（µs，新的是相机/场景负载，不是被测增量）；per-round 配对 new-off 中位 -574.5 / +266.5 / +2.0（sd 779/1059/1045），new-legacy -291 / +28 / -205.5（sd 714/1154/1088） |
| 验收探针 | probe_p82_wind_cpu（等价性 **23 PASS / 0 FAIL**）、probe_p81_wind（**117 PASS / 0 FAIL**）、probe_p8_ecology PASS、probe_p8_season PASS、selftest 73/73（P8.1 口径）→ P8.2 HEAD 75/75 |
| 截图 | after_wind_shots/ 12 张（最终 build 重拍）；before 引用 开发产物/p81/evidence/p81_05/p81_wind_*.png（只读，未覆盖） |
| 判定 | **PASS**（owner 结论 + 本索引独立复算一致），详见下文核对 |

**本索引的独立复算（不抄 NOTES，直接重算 CSV）**

用 python 直接读上述 4 份 CSV（window r5/r4/r1、headless r5）重算，核对结果：

1. **行数与分组自洽**：r5/r4/headless 各 10800 行 = AB 9720 + prof 1080；AB = 9 轮 × 3 phase × 3 impl × 120 帧（无缺组、无长度异常）；prof = 9 组 × 120 帧且 round 恒为 -1（与「prof 段单独采样一次」的设计一致）；r1 为 7200 行（只有 new/legacy 两 impl，AB 6480 + prof 720）。
2. **§5.1 主表逐格命中**：9 个「5 段合计」全部一致（41/64/31、47/78.5/31、43/75/27.5），new-off 的三个 sum 与五个分量全部一致（-22、-30.5、-30；萤火 -16/-17.5/-17 等）。
3. **§5.2 / §6 / §1 旁证命中**：r4 的 35/53、42/64、45/66 与 -19/-22/-20 一致；headless r5 的 38/48、30/59、65/74 与 -11.5/-28/-8 一致；r1 优化前 59/30.5、71/34、67.5/34 与 §1 热点表一致。
4. **帧级配对命中**：per-round new-off 中位 -574.5 / +266.5 / +2.0（窗口 r5）与 §5.1 一致；new-legacy -291 / +28 / -205.5（NOTES 写 -206，四舍五入一致）；sd 714–1154 与 NOTES §11.2 的「0.7–1.2 ms」一致。
5. **TP 伪影证据复核**：r5 所有 phase/impl 的 tp_us 中位 15–20 µs，同组 frame_us 中位 5857–6241 µs（窗口）/ 2172–2453 µs（headless），比值 ~300×，且 new/off/legacy 的 tp 中位差 ≤5 µs、无法区分实现 → 支撑「TP 不可作 A/B 判据」的结论。
6. **保留意见（不推翻结论，但最终报告应带）**：① prof 段只有单轮 n=120/组，段中位数采样噪声约 ±1–2 µs，因此「-19…-31 µs」的**量级**可靠、小数点后一位不可当精确值（owner §11.1 已披露）；② legacy 段本身仅 5–13 µs，扣减后相对误差大，故归因用 new-off 而非 new-legacy；③ headless typhoon swing +2.5 与我复算一致（new 26 vs off 23.5），属该段抖动，不影响窗口结论。
7. 复算脚本：临时 python（读 CSV → 按 (phase,impl) 取 prof 段五列中位数与和的 median、AB 段 p50/p95、逐轮 new-other 配对），一次性运行后删除，未写入任何模块目录；输入 CSV 的 sha256 可由 evidence/03_wind 原文件复核。

### P8.2-04 冬季白化 / 生态回归（owner 交付，本索引转录）

| 项 | 内容 |
| --- | --- |
| 证据目录 | D:/休闲小岛幻境/开发产物/p82/04_winter/ |
| 截图 | shots/ 8 张（winter_bare_close/wide、perch4_actual/fixed 的 before/after，2560x1440）；日志 shot_before/after_20261022.log 记录 [SHOT] saved |
| 自测 | regress_selftest_20261022.log：RESULT 73/73 passed（EXIT 0，尾部有 8 个 ObjectDB leaked WARNING，历史已知） |
| 生态长跑 | eco_soak_20261022.log / eco_soak_v2_20261022.log：v2 共 899 个 [OK] 与 **89 个 [FAIL]「无鸟钻地」**（bad=1，位置 dock_rail/dock_bollard，如 pos=(27.76,1.69,17.75) terrain=-3.70 gap=5.39）；属**预存在失败**，需 owner 定性（是栖点选点问题还是该断言口径问题），最终报告必须披露 |
| 回归 | regress_probe_p7v2_bird / p7v2_perch / p81_tree_bird 日志（本阶段转录，结论待 owner） |
| 判定 | **PASS**（owner 提交 `429da59`+`0447c0f`；自测 73/73、近景截图 5 有效+2 作废、几何 135/0、**soak v3 1407/0 PASS**）。注：`eco_soak_v2` 的 89 条「无鸟钻地」是**探针口径错误**（把码头 rail/bollard 下方海床 terrain≈−3.7~−4.8 m 当作可站立表面），v3 改为「可站立表面 = max(地形, 0)」后为 0；跨季/跨年/暂停恢复一致；自然使用率 38.7%（12/31，5/5 点） |

### P8.2-05 日期时间滚轮 / 面板（owner 交付，本索引转录）

| 项 | 内容 |
| --- | --- |
| 证据目录 | D:/休闲小岛幻境/开发产物/p82/05_wheel/（21 张 PNG + 行为 JSON + 多份 stdout） |
| 结果 JSON（最新，wheel 连续重跑中） | probe_p82_datetime_behavior_result.json，started_at 2026-10-22T11:28:16，共 87 项：**pass=80 / fail=0 / skip=1 / warn=6**。注：wheel 在本索引写作期间仍在重跑，引用数字时请以 JSON 的 started_at 为准 |
| 曾出现但现已不复现的 FAIL（两次） | ①首轮（11:10:56）U09 长时反复开合的 3 项节点/对象波动；②11:25:25 一次的 2 项桌面合成触摸（tap=221.0x578.0 前=后=2026-10-22 12:19；拖动 busy=false）。11:28:16 重跑后二者均 PASS；按 Lead 口径不删记录，作为 PRE-1 / PRE-7 预存在/环境相关项披露（合成事件走 emulate_mouse_from_touch，本机 is_touchscreen_available()=false，无真机触屏可复验） |
| 6 个 WARN（环境限制/行为记录） | P-1 合成输入需 warp（与 P8.1 一致，非产品缺陷）、真机 OS 自动重复率不可自动化测量、TAB 第 5 次后焦点离开滚轮到 Wheel_year（记录行为）、现实时间 23:59:59→00:00:05 为同步注入、多显示器/高 DPI 仅模拟、无真机触屏（DisplayServer.is_touchscreen_available()=false） |
| 1 个 SKIP | 多显示器真机（screen_count=1，无法验证） |
| 历史首轮（11:10:56，84 项：75/3/1/5） | 3 个 FAIL 全在 U09 长时反复开合：①整树节点 1544→1556（Δ=+12）；②RENDER_TOTAL_OBJECTS 2326→2309（Δ=-17）；③HUD/整树节点 1555→1545 且新增节点 1 个。重跑后 U09 未再 FAIL（波动未复现），但按 Lead 口径仍作为 **PRE-1 预存在失败**保留披露，与 P8.1 同口径对比定性由 owner 完成 |
| 判定 | **当前 80/0/1/6 全 PASS**（仅剩 6 WARN 环境披露 + 1 SKIP）；历史 U09 波动与合成触摸 FAIL 均未复现，保留 PRE-1 / PRE-7 披露 |
| 备注 | JSON 中中文详情的编码在某些控制台显示为乱码（文件本身 UTF-8），引用时请用 UTF-8 打开 |

### P8.2-06 回归基础设施（本模块，已完成）

#### 06-A 长时 soak 探针 tools/probe_p82_soak.gd（提交 d95f4b2）

| 项 | 内容 |
| --- | --- |
| 命令（短跑） | bash run_godot.sh --path . --resolution 1600x900 --script res://tools/probe_p82_soak.gd -- --minutes=2 --op-scale=0.1 --sample=5 --out=... |
| 命令（最终 30min） | ... -- --minutes=30 --out="D:/休闲小岛幻境/开发产物/p82/06_soak/final" |
| 短跑证据 | D:/休闲小岛幻境/开发产物/p82/06_soak/_short_window2/（soak_2026-10-22T19-00-35.csv/.log/_summary.json/_summary.md、stdout.txt） |
| 短跑结果 | RESULT PASS；window=1600x900 vsync=off；elapsed=120.7s；samples=24；ops=45(ok=45 fail=0)；首窗 p50=10.08 p95=16.67 max=150.00；末窗 p50=11.67 p95=16.67 max=145.86；nodes 1546→1585；orphan +22；vram +296.7MB（启动期驻留）；mem_static +18.8MB |
| 操作覆盖 | quality 19 / weather 13（12 类全覆盖）/ date 7（四季+跨年 2028-01-01+闰年 2028-02-29+月末 1/31→2/1）/ hud 6 |
| 判定（短跑） | C1 SKIP（<720s 趋势无意义）、C2~C6 PASS |
| **30min 正式跑结果** | `RESULT PASS`：elapsed=1800.0s、samples=360、ops=68(ok=68/fail=0)；C1 首末窗 p95 16.67→16.67 ms（limit 22.83）、C2 nodes 1546→1554（+8，limit 81）、C3 最长连续<20fps 1 次（仅 t=0）、C5 0 断言失败、C6 isle_valid=true；证据 `开发产物/p82/final/20261022_205425/soak_2026-10-22T21-06-01.*`；附注：q0/q1 档自带 `max_fps=60`，该档 p50=16.67 ms 为限帧所致 |
| 已知噪声 | 3 个历史 smoke/短跑摘要同目录存在（18-56-06、18-57-55、19-00-35），check_evidence.py 取最新一份 |

#### 06-B 五档画质矩阵 tools/probe_p82_matrix_shots.gd（提交 310edae）

| 项 | 内容 |
| --- | --- |
| 命令 | bash run_godot.sh --path . --resolution 1600x900 --script res://tools/probe_p82_matrix_shots.gd -- --out="D:/休闲小岛幻境/开发产物/p82/06_matrix" |
| 证据 | D:/休闲小岛幻境/开发产物/p82/06_matrix/（shots/ 30 PNG + shots/SHA256SUMS、matrix.csv 22 列、MANIFEST.md、matrix_summary_2026-10-22T19-07-27.json、contact_sheet.png 1600x1080、stdout.txt） |
| 矩阵 | q0..q4 x {clear_day_outdoor, winter_white_outdoor, indoor_night_fireplace, dock_night, heavy_rain, heavy_snow_close} = 30 张，全部 1600x900 |
| 判定（正式跑 RUN_ID=20261022_205425） | RESULT PASS：H1 30/30；H2 6/6 场景 q0 vs q4 有可测差异；H3 夜间最低 mean **32.04**（下限 12）@dock_night q0；H4 夜间最高白点 **0.00007**（上限 0.02）；H5 无 runtime error；51 checks/0 fail/30 张；证据 `final/20261022_205425/matrix/`（短跑数字 31.64/0.00009 为 19:07 的早期 smoke，仅存档） q4；H5 无异常 |
| 登记 | 30 张的尺寸 + sha256 已写入 MANIFEST.md 校验表与 shots/SHA256SUMS（后处理补录，PNG 未修改）；机器尺寸与 CSV width/height 30/30 一致 |
| 备注 | 首轮码头机位构图错误（相机进礁石），已改复用 main.gd 的 _boat_dock_pos/_boat_dock_heading，_dockfix/ 单场景复验 PASS 后重跑；旧 summary 归档 06_matrix/_prev_run/ |

#### 06-C 发布构建 / 独立验收（git 外）

| 项 | 内容 |
| --- | --- |
| 脚本 | D:/休闲小岛幻境/开发产物/p82/build_release.sh、verify_release.sh |
| dry-run | 环境检查 PASS；工作树有他人未提交改动时 dry-run 放行、真实构建中止（冻结门禁有效，HEAD=429da59 时实测） |
| 预览导出 | 见第 1 节（base 副本 → sha256 复现 P8.1 冻结包） |
| 最终阶段 | 代码冻结后 bash build_release.sh --copy-to-release（先备份 开发产物/backup/release_pre_p82/）→ bash verify_release.sh → 把新 size/sha256/版本写入本索引第 1 节与 P8.2 报告 |

---

## 3. 证据完整性检查器

D:/休闲小岛幻境/开发产物/p82/check_evidence.py（不占 GPU，纯文件校验）：

    python check_evidence.py            # 全量：含 760.5MB 冻结证据逐文件 sha256（实测约 2-3s）
    python check_evidence.py --quick    # 冻结证据只校验存在+体积（<1s）
    python check_evidence.py --strict   # 缺口(GAP)也算失败，用于冻结前门禁
    python check_evidence.py --json=out.json   # 机器可读输出

检查内容：① 各模块证据目录/关键文件/截图数量；② 每个 PNG 的尺寸与 sha256 是否登记在 MANIFEST
并与实际文件一致；③ 开发产物/p81 与 开发产物/p8 的 599 个冻结文件与
integrity/frozen_p81_p8_manifest_before.txt 逐文件 sha256 是否一致（防误覆盖）；④ 发布/ 的 exe 是否
仍是 integrity/release_exe_before.txt 记录的 c40376ad…b668；⑤ 06_soak/06_matrix 的探针结论是否落证。

本阶段实跑（2026-10-22，full 模式，01 口径确认 + checker 升级后）：

    PASS 40  FAIL 0  GAP 1  WARN 0   用时 2.02s（预算 5.0s）
    结论：PASS（缺口不阻断，仅列清单）
    唯一 GAP：06_soak.final_run —— 最新摘要仍是 120.7s 短跑，30min 正式 soak 待代码冻结后执行
    05_wheel.result 已转 PASS（最新 started_at 11:28:16：pass=80 fail=0 skip=1 warn=6；历史 FAIL 见 PRE-1/PRE-7）

相较初版（PASS 28 / GAP 4）已关闭的项：
- 01_fireplace.shots_count：口径确认为 after **20** / before **18**（lighting 提交 ce6fc30/1121f65/41c4816），checker 期望值同步改为 20/18
- 01_fireplace.*.sha_in_manifest：已读 01_fireplace/MANIFEST.csv 的 "# dir=after/before" 分节，after 20 + before 18 的尺寸(2560x1440)/bytes/sha256 逐张登记并校验一致
- 06_matrix.dims_in_manifest：MANIFEST 校验表已含尺寸，PNG 实际尺寸与 CSV 30/30 一致

checker 的两点增强（本阶段）：① 01 证据按 MANIFEST.csv 分节索引（after/before 存在同名文件但 sha 不同，旧实现按 basename 全局索引会误判）；② 06_soak 额外扫描 开发产物/p82/final/*/soak*，且 final_run 判据为 elapsed_s>=1500 秒且摘要不来自 _short_window/_smoke —— 直接对齐 runbook 的 --long 输出目录，长跑落地后该项自动转 PASS。

最终冻结前用 --strict 跑一次；届时唯一应剩的 GAP（final_run）也会转 PASS，预期 **PASS 41 / FAIL 0 / GAP 0 / WARN 0**（若届时 05_wheel 又出现 fail，会以 WARN 形式回来，不阻断但需披露）。

---

## 4. 预存在失败 / 披露清单（最终报告必须体现）

| 编号 | 内容 | 证据 | 状态 |
| --- | --- | --- | --- |
| PRE-1 | 05 滚轮 U09 长时节点/对象波动（首轮整树节点 +12 / RENDER_TOTAL_OBJECTS -17；后续 11:25/11:28 两次重跑均未复现） | 05_wheel/probe_p82_datetime_behavior_result.json（首轮 started_at 11:10:56；最新 11:28:16 为 pass=80/fail=0） | 预存在波动，保留披露；结论「未复现」需 owner 在最终报告说明，不做无证据的"已修复"表述 |
| PRE-2 | 04 生态长跑「无鸟钻地」89 次（dock_rail/dock_bollard） | 04_winter/eco_soak_v2_20261022.log | 预存在，待 owner 定性（栖点选点 vs 断言口径） |
| PRE-3 | 05 U11 多显示器/高 DPI 无法真机验证 | 05_wheel JSON（SKIP/WARN） | 环境限制，如实披露 |
| PRE-4 | 多处 user:// 日志写入失败、shader cache 保存失败、Windows 证书库读取失败 | 任意真实运行日志 | 环境性噪声，非产品缺陷（soak/matrix/selftest 退出码均为 0） |
| PRE-5 | 自测尾部 "8 ObjectDB instances were leaked at exit"；**分母更正：P8.1/base、P8.2 HEAD、发布包三方均为 73/73（此前「75/75、新增 2 项」为 `[TEST]` 行数误读，已修正）** | 04_winter/regress_selftest_20261022.log；baseline/selftest_HEAD_ddcde3a.log（73 PASS/1 SKIP/1 RESULT）；final/20261022_205425/selftest.log；release_preview/build_20261022_214845/verify_selftest.log | 历史已知（P7 起），不影响退出码 0；分母变化非回归异常（来源由 lighting 在 01 NOTES 说明） |
| PRE-6 | probe_scale_house_p7v32 252 checks / 245 pass / **7 fail**（EXIT=1），7 条全在 light_sources 契约：探针期望「6 固定 + 5 窗」共 11 个光位，实际 P8.1-06 双池聚合后 light_sources=10 | 当前 HEAD：D:/休闲小岛幻境/开发产物/p82/01_fireplace/regress/scale_house_p7v32.log；冻结基线复现（逐字相同的 245/7）：D:/休闲小岛幻境/开发产物/p82/01_fireplace/regress/base_scale_house_p7v32.log | **预存在失败**（P8.1 冻结副本即可复现，非 P8.2 引入）；探针期望值过时。注意：若 02 模块改动 light_sources 结构，需同步更新该探针的期望值，否则会持续误报 |
| PRE-7 | 05 桌面合成触摸点击/拖动曾一次不等价鼠标（tap=221.0x578.0 前后日期均为 2026-10-22 12:19；拖动 busy=false），11:28:16 重跑后 2 项均 PASS | 05_wheel/probe_p82_datetime_behavior_result.json（11:25:25 与 11:28:16 两次 started_at） | 环境相关/间歇：合成事件走 emulate_mouse_from_touch，本机无真机触屏（is_touchscreen_available=false），无法进一步复验；如实披露，不宣称"已修复" |

| PRE-8 | `probe_p81_datetime_wheel_ui` 的 UI2「拖动 1 行 → 日期 +1」断言非确定性失败，落点每次不同（22→16 / 22→24 / 22→5 / 22→22），同代码 20:26 曾 PASS（82 项 80/2/0） | 当前 HEAD：开发产物/p82/final/20261022_205425/probe_p81_datetime_wheel_ui.window.log、开发产物/p82/verify_wheel/rerun1_213900.log、rerun2_214011.log、diag_*.log（插桩：`_ema_vel=-4.892`、物理位移正好 28 px=1 行）；**P8.1 基线 ddcde3a 同探针复现**：开发产物/p82/verify_wheel/base_p81_run_*.log（day 22→1） | **预存在 + 非确定性**：机制为 `ui_datetime_wheel.gd:624` 的瞬时速度用 `_dt_since_last()` 的 dt 下限 0.001 s，合并事件时 dt=1 ms 把速度放大 25 倍 → 越过 `FLICK_THRESHOLD=1.2` 走惯性滑行。P8.2 对该文件唯一改动（56bfbb1）是字面量 1.2→常量引用，行为不变。不修改断言/阈值，不在冻结前改动手感逻辑；建议下一迭代把 dt 下限提到 ~1/240 s 或对 inst 做 clamp（未实施） |
### 4.1 非确定性统计断言（NONDET，非本轮代码回归）

| 编号 | 现象 | 证据 | 定性 |
| --- | --- | --- | --- |
| NONDET-P82-1 | 04 生态 soak 的两条**统计断言**（「5 个冬季裸枝点都被自然使用过」「使用分布无极端偏斜」）在 `--headless --fixed-fps 60` 下**确定性失败**：33 个停栖事件里 `winter_branch_2` 未被采样（used 4/5，min=0），两次运行分布**逐字相同**；同一探针在**实时 headless**（不加 `--fixed-fps`，31 个事件）下 used 5/5 PASS | PASS：`04_winter/eco_soak_v3_20261022.log`（{3,3,1,2,3}=12/31=38.7%）；fixed-fps FAIL：`final/20261022_205425/probe_p82_eco_soak.headless.log` 与 `final/20261022_203054/probe_p82_eco_soak.headless.log`（均 `step_events=33`、`winter_branch_2:0`）；候选权重：`04_winter/eco_diag_20261022.log`（wb2 w=1.2613，与其余 4 点 1.2559–1.2806 相差 <2%，**无系统性低权重**） | **统计性 + 运行模式相关，不是本轮代码回归**：单次只采样 17–33 个事件，5 点均分 41.5% 权重份额时任一点 0 次的概率约 25%；跨模式聚合 5 个点全部被自然使用过。处置：**断言与阈值都不改**，runbook 将其记为 `nondet` 并要求人工核对分布列；报告 §6.3/§8.1 同步披露 |

## 5. 收口记录（最终阶段已完成）

已关闭：01 张数口径（after 20 / before 18）与 MANIFEST 登记、06_matrix 尺寸登记、checker 01/06 判据升级 —— 见 §2.1、§3。

**最终阶段（RUN_ID=20261022_205425，窗口+长跑全量回归）逐项结果**：

1. **30min 正式 soak**：`RESULT PASS`（1800.0 s / 360 samples / 68 ops 全成功；C1 p95 16.67→16.67 ms、C2 nodes +8、C3 仅 t=0 一次、C5 0 失败、C6 isle_valid=true）→ 已写入 §2.6（06-A）。
2. **`check_evidence.py --strict`**：**PASS 41 / FAIL 0 / GAP 0 / WARN 0**（15.01 s；含 frozen.release_exe 与 frozen.sha256 两条冻结证据校验）→ 见 §3。
3. **正式发布包**：`build_release.sh --copy-to-release` verdict=PASS（旧包已备份）→ `verify_release.sh` **RESULT PASS**；size 117,248,168 B、sha256 `994ea96a…3795`、版本 1.0.0、`--quit` EXIT 0、selftest 73/73 → 已写入 §1.1。
4. **P8.2-02 证据合并**：02 模块是灯光+性能（非「菜单/开场」，原 §2.2 的判断错误已改正），证据见 §2.2 与 `开发产物/p82/02_lighting/`、`evidence/02_perf/`。
5. **预存在失败复核**：p7v2_light **1**、p7v2_flycam **7**、cottage6 **5**、scale_house_p7v32 **7** 四条在 P8.2 HEAD 上 rc 与失败数逐条吻合（无新增）；p82_eco_soak 2 条 = NONDET-P82-1（§4.1）；wheel_ui UI2 = PRE-8（§4）。
6. **实现修正**：selftest 分母此前记「75/75、新增 2 项」为 `[TEST]` 行数误读；实际 P8.1/base、P8.2 HEAD、正式包**三方均 73/73 + 1 SKIP**（Lead 修正，见顶部注记与 PRE-5）。

本文件随 P8.2 冻结提交一并冻结（提交号见 `docs/P8_2_REFINEMENT_REPORT.md` §8.7），冻结 tag `p8.2-final`。
