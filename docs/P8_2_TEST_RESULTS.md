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

> **selftest 分母变化（不要当回归异常）**：P8.1 及 base(ddcde3a) 副本为 **73/73**；P8.2 HEAD 为 **75/75**
> （新增 2 项自测，来源见 lighting 的 01 NOTES）。因此第 1 节 base 副本的 73/73 与 P8.2 当前 HEAD 的 75/75
> 不可直接对比；对比同一 commit 的分子分母即可。



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

### 1.1 P8.2 正式包（代码冻结后填写，数字待填）

> 本小节在**代码冻结、build_release.sh --copy-to-release 成功、verify_release.sh PASS** 之后填写；
> 在此之前下列字段一律保留 TODO，不得用 P8.1 冻结包数字冒充。

| 项 | 值 |
| --- | --- |
| 构建 commit | TODO（git rev-parse HEAD，冻结 tag 见 docs/P8_2_06_NOTES.md「冻结后流程」） |
| 构建时间 | TODO |
| 命令 | bash build_release.sh --copy-to-release（日志 开发产物/p82/final/<RUN_ID>/build_release.log） |
| 导出日志 | TODO（build_release 产物目录 build.log / record.json） |
| 正式包路径 | D:/休闲小岛幻境/发布/休闲小岛幻境.exe（同步 构建输出/休闲小岛幻境.exe） |
| 体积 | TODO B |
| SHA256 | TODO |
| --headless --quit | TODO（期望 EXIT 0，且无 SCRIPT ERROR / Parse Error / Corrupted header） |
| --headless -- --selftest | TODO（期望 75/75，EXIT 0） |
| 包内容排除检查 | TODO（tools/ docs/ shots/ refshots/ addons/ sounds/ *.md 全 0；scripts/main.gd 在包；_mcp_game_helper 已剥离） |
| 与 P8.1 冻结包 c40376ad…b668 的关系 | TODO：说明 size/sha256 差异来源（本次改动涉及脚本，预期 sha256 必然变化；重点记录体积变化幅度与排除项一致性；若 size 完全一致需核实是否真的重新导出） |
| 旧包备份 | 开发产物/backup/release_pre_p82/休闲小岛幻境_pre_p82_<stamp>.exe（由 --copy-to-release 自动生成） |
| 独立验收 | bash verify_release.sh --exe="D:/休闲小岛幻境/发布/休闲小岛幻境.exe" --expect-sha256=<上表> --expect-size=<上表> --expect-selftest=75/75 → 结果 TODO |

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

### P8.2-02 菜单 / 开场（TODO）

| 项 | 内容 |
| --- | --- |
| 证据目录 | **不存在** D:/休闲小岛幻境/开发产物/p82/02_*（模块尚未交付证据或使用其他目录） |
| 判定 | TODO：需 owner 补证据目录与判据，否则最终报告不能引用 |

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
| 判定 | 部分 PASS（自测/截图/几何诊断）；生态长跑存在预存在失败，TODO 定性 |

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
| 判定 | C1 SKIP（<720s 趋势无意义）、C2/C3/C4/C5/C6 PASS；**30min 正式跑待最终阶段**（唯一能触发 C1 的一次） |
| 已知噪声 | 3 个历史 smoke/短跑摘要同目录存在（18-56-06、18-57-55、19-00-35），check_evidence.py 取最新一份 |

#### 06-B 五档画质矩阵 tools/probe_p82_matrix_shots.gd（提交 310edae）

| 项 | 内容 |
| --- | --- |
| 命令 | bash run_godot.sh --path . --resolution 1600x900 --script res://tools/probe_p82_matrix_shots.gd -- --out="D:/休闲小岛幻境/开发产物/p82/06_matrix" |
| 证据 | D:/休闲小岛幻境/开发产物/p82/06_matrix/（shots/ 30 PNG + shots/SHA256SUMS、matrix.csv 22 列、MANIFEST.md、matrix_summary_2026-10-22T19-07-27.json、contact_sheet.png 1600x1080、stdout.txt） |
| 矩阵 | q0..q4 x {clear_day_outdoor, winter_white_outdoor, indoor_night_fireplace, dock_night, heavy_rain, heavy_snow_close} = 30 张，全部 1600x900 |
| 判定 | RESULT PASS：H1 30/30；H2 6/6 场景 q0 vs q4 有可测差异；H3 夜间最低 mean 31.64（下限 12）@dock_night q0；H4 夜间最高白点 0.00009（上限 0.02）@dock_night q4；H5 无异常 |
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
| PRE-5 | 自测尾部 "8 ObjectDB instances were leaked at exit"；同时 selftest 分母由 **73/73（base ddcde3a / P8.1）** 变为 **75/75（P8.2 HEAD）**，新增 2 项 | 04_winter/regress_selftest_20261022.log；P8.2 HEAD 实测 | 历史已知（P7 起），不影响退出码 0；分母变化非回归异常（来源由 lighting 在 01 NOTES 说明） |
| PRE-6 | probe_scale_house_p7v32 252 checks / 245 pass / **7 fail**（EXIT=1），7 条全在 light_sources 契约：探针期望「6 固定 + 5 窗」共 11 个光位，实际 P8.1-06 双池聚合后 light_sources=10 | 当前 HEAD：D:/休闲小岛幻境/开发产物/p82/01_fireplace/regress/scale_house_p7v32.log；冻结基线复现（逐字相同的 245/7）：D:/休闲小岛幻境/开发产物/p82/01_fireplace/regress/base_scale_house_p7v32.log | **预存在失败**（P8.1 冻结副本即可复现，非 P8.2 引入）；探针期望值过时。注意：若 02 模块改动 light_sources 结构，需同步更新该探针的期望值，否则会持续误报 |
| PRE-7 | 05 桌面合成触摸点击/拖动曾一次不等价鼠标（tap=221.0x578.0 前后日期均为 2026-10-22 12:19；拖动 busy=false），11:28:16 重跑后 2 项均 PASS | 05_wheel/probe_p82_datetime_behavior_result.json（11:25:25 与 11:28:16 两次 started_at） | 环境相关/间歇：合成事件走 emulate_mouse_from_touch，本机无真机触屏（is_touchscreen_available=false），无法进一步复验；如实披露，不宣称"已修复" |

## 5. TODO（最终阶段补齐后本索引即可冻结）

已关闭：01 张数口径（after 20 / before 18）与 MANIFEST 登记、06_matrix 尺寸登记、checker 01/06 判据升级 —— 见 §2.1、§3。

仍待最终阶段（按执行顺序）：

1. **代码冻结后**跑 30min 正式 soak（06-A）：命令见 §2.6（06-A），输出目录约定 开发产物/p82/final/<RUN_ID>/soak/；把 C1 趋势结论与 final 目录写回 §2.6，替换"短跑"标注。
2. 跑 `python check_evidence.py --strict`：预期 final_run 转 PASS 后 **PASS 41 / FAIL 0 / GAP 0 / WARN 0**（05_wheel 最新 11:28:16 已 fail=0，故 WARN 归零；若届时又有 fail 会以 WARN 形式回来，不阻断但需披露），把该行贴进 §3 与 P8.2 报告证据索引。
3. 正式发布包：`bash 开发产物/p82/build_release.sh --copy-to-release`（自动备份旧包到 开发产物/backup/release_pre_p82/）→ `bash 开发产物/p82/verify_release.sh`；把 size/sha256/版本/--quit/selftest（期望 75/75）填入 §1.1，并与 P8.1 冻结包 c40376ad…b668 做差异说明（同源应一致；若不一致必须解释原因）。
4. 02 菜单模块：目录与判据待 Lead 通知合并（§2.2 仍为 TODO）。
5. 03/04/05 的 owner 最终结论与 P8.1 同口径对比（本索引只转录数据，不代替 owner 结论）；PRE-1/PRE-2/PRE-6/PRE-7 需在最终报告中各有一句定性。
6. 结果收口后本文件即可冻结（改动只允许追加最终数字与冻结 commit）。
