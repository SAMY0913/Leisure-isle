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

---

## 2. 模块证据索引

### P8.2-01 壁炉 / 室内表现（owner 交付，本索引转录）

| 项 | 内容 |
| --- | --- |
| 证据目录 | D:/休闲小岛幻境/开发产物/p82/01_fireplace/（after/、before/、pixel/、regress/、analyze_fireplace.py、run_after_shots_and_regr.sh） |
| 截图 | after/ 20 张 PNG（q0..q4 壁炉正视/斜视、q2 低机位/房间全景/烟囱外景/阁楼、day 白天组等）；before/ 18 张；pixel/ 16 张（像素级对比） |
| 日志 | after/after_shots.log、after/shots.log、after/after_geom.log、before/*.log；regress/ 下 cottage6 / p7v2_perch / p81_tree_bird / p8_ecology / scale_house_p7v32 / scale_world_audit 回归日志 |
| 判定 | 待 owner 结论（本索引暂记 TODO）；截图张数：Lead 口径 19 张，实际 after/ 20 张，差 1 需 owner 确认口径（check_evidence.py 记为 GAP） |
| 缺口 | after/ 下 PNG 未登记 MANIFEST（尺寸/sha256 未入册，check_evidence.py GAP） |

### P8.2-02 菜单 / 开场（TODO）

| 项 | 内容 |
| --- | --- |
| 证据目录 | **不存在** D:/休闲小岛幻境/开发产物/p82/02_*（模块尚未交付证据或使用其他目录） |
| 判定 | TODO：需 owner 补证据目录与判据，否则最终报告不能引用 |

### P8.2-03 风场 / CPU 开销（owner 交付，本索引转录）

| 项 | 内容 |
| --- | --- |
| 证据目录 | D:/休闲小岛幻境/开发产物/p82/evidence/03_wind/ |
| 关键文件 | analysis_optab.txt（AB 工况 p50/p95/均值）、analysis_windcpu.txt、compare_before_after.txt、log_selftest.txt、12 张 after_wind_shots/*.png、headless/* 日志 |
| 数字摘录 | headless r4 成对比较 calm：new-legacy 中位 -67us；wind：new-legacy 中位 +107.5us（n=9，sd≈375）；window 模式 calm/wind/typhoon 的 new 与 legacy p50 基本持平（如 typhoon r2 new p50=5466 legacy p50=5579），p95 受窗口/系统噪声影响大 |
| 自测 | log_selftest.txt：RESULT 73/73 passed |
| 判定 | 待 owner 结论（本索引暂记 TODO）；数值证据齐全，check_evidence.py PASS |

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
| 结果 JSON | probe_p82_datetime_behavior_result.json，started_at 2026-10-22T11:10:56，共 84 项：**pass=75 / fail=3 / skip=1 / warn=5** |
| 3 个 FAIL | 全在 U09（长时反复开合）：①整树节点 1544→1556（Δ=+12）；②RENDER_TOTAL_OBJECTS 2326→2309（Δ=-17）；③HUD/整树节点 1555→1545 且新增节点 1 个 |
| 5 个 WARN（已披露的环境限制） | U05 合成输入需 warp（与 P8.1 P-1 一致，非产品缺陷）、U12 真机 OS 自动重复率不可自动化测量、U06 TAB 第 5 次后焦点回到 Wheel_year、U08 现实时间 23:59:59→00:00:05 为注入而非真实等待、U11 多显示器/高 DPI 仅模拟 |
| 1 个 SKIP | U11 多显示器真机（screen_count=1，无法验证） |
| 判定 | **预存在失败**（U09 节点/对象 ±Δ 属于长时波动，需与 P8.1 同口径对比定性）；截图/行为断言主体 PASS |
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

本阶段实跑（2026-10-22，full 模式）：

    PASS 28  FAIL 0  GAP 4  WARN 1   用时 2.12s（预算 5.0s）
    结论：PASS（缺口不阻断，仅列清单）

当时 4 个 GAP 与 1 个 WARN：
- 06_soak.final_run：最新摘要来自 2min 短跑，30min 正式 soak 待最终阶段（预期）
- 06_matrix.dims_in_manifest：已在本文件写完后修复（MANIFEST 校验表已含尺寸，重跑后该项转 PASS）
- 01_fireplace.shots_count：after/ 20 张 vs Lead 口径 19 张，差 1 需 owner 确认
- 01_fireplace.after.sha_in_manifest：01 模块 PNG 未登记 MANIFEST（owner TODO）
- WARN 05_wheel.result：fail=3 属预存在失败（见 2.5 节）

（上述 GAP 中除"30min soak 未跑"与"01 模块证据登记"外都已在本阶段处理；最终冻结前用 --strict 跑一次应为 PASS。）

---

## 4. 预存在失败 / 披露清单（最终报告必须体现）

| 编号 | 内容 | 证据 | 状态 |
| --- | --- | --- | --- |
| PRE-1 | 05 滚轮 U09 长时节点/对象波动（+12 / -17 节点/对象） | 05_wheel/probe_p82_datetime_behavior_result.json | 预存在，已披露，需与 P8.1 同口径对比定性 |
| PRE-2 | 04 生态长跑「无鸟钻地」89 次（dock_rail/dock_bollard） | 04_winter/eco_soak_v2_20261022.log | 预存在，待 owner 定性（栖点选点 vs 断言口径） |
| PRE-3 | 05 U11 多显示器/高 DPI 无法真机验证 | 05_wheel JSON（SKIP/WARN） | 环境限制，如实披露 |
| PRE-4 | 多处 user:// 日志写入失败、shader cache 保存失败、Windows 证书库读取失败 | 任意真实运行日志 | 环境性噪声，非产品缺陷 |
| PRE-5 | 04 自测尾部 "8 ObjectDB instances were leaked at exit" | 04_winter/regress_selftest_20261022.log | 历史已知（P7 起），不影响退出码 0 |

## 5. TODO（最终阶段补齐后本索引即可冻结）

1. 30min 正式 soak（06-A）→ 用 C1 趋势结论替换 2.6 节的"短跑"标注，把 final 目录写进本索引。
2. 01_fireplace 证据登记（MANIFEST 尺寸+sha256）与张数口径（19 vs 20）由 owner 确认；补齐后把 2.1 节 TODO 换成结论。
3. 02 菜单模块证据目录与判据（2.2 节）。
4. 03/04/05 的 owner 最终结论与 P8.1 同口径对比（本索引只转录数据，不代替结论）。
5. 代码冻结后 build_release.sh --copy-to-release + verify_release.sh，把 P8.2 正式包的 size/sha256/版本写入第 1 节，并与 P8.1 冻结包 c40376ad…b668 做差异说明。
6. 全量跑一次 python check_evidence.py --strict，结果贴进 P8.2 报告证据索引。
