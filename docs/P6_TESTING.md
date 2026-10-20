# P6 测试与探针复现说明

> 维护：T3 工程卫生（teammate hygiene）。生成时间：2026-10-20 23:2x（Asia/Shanghai）。
> 基线：tag baseline-p6close-20261020（commit 8f80b13），详见 [docs/P6_BASELINE.md](P6_BASELINE.md)。
> 本文命令均在本机实际核对；标注「实测」的条目为本次 T3 亲自运行的结果，标注「历史」的来自 docs/P6_REPORT.md 与 开发产物/logs/ 下的历史日志，二者不要混用。

## 0. 前置约定

1. 引擎用控制台版：D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe（版本 4.7.2.stable.official.ed1daf0bf，可按 docs/P6_BASELINE.md §3 核验）。
2. 工程路径固定 D:/休闲小岛幻境/游戏工程，主场景 res://isle.tscn。
3. **Godot 不写 user://**：历史会话的 DSH 沙箱禁止 Godot 写 C:/Users/...，所有截图/日志/临时配置一律写 D:/休闲小岛幻境/开发产物/；探针与 main.gd 自动化已按此实现，不要改回 user://。
4. **不要用 godot-ai MCP 工具**（当前没有 Godot 编辑器进程，只有 MCP 桥）。
5. 多个 teammate 共用本机 GPU：运行 --perf、--shots、窗口截图或任何会开窗的 Godot 前先 `tasklist` 检查；性能测试必须独占 GPU（由 Lead 统一安排）。headless 探针可并行（但也别同时开太多窗口实例）。
6. 参数分隔：`--` 之前的参数交给引擎（--headless/--path/--resolution/--script），之后的参数交给游戏脚本（`OS.get_cmdline_user_args()`）。main.gd 同时接受放在 -- 之前的自动化参数，但推荐统一用 `--` 分隔。

## 1. 环境变量（tools/base_env.json）

D:/休闲小岛幻境/游戏工程/tools/base_env.json 是一份 Windows 环境变量字典（SystemRoot/WINDIR/SystemDrive/ComSpec/PATHEXT/PATH/USERPROFILE/APPDATA/LOCALAPPDATA/TEMP/TMP/NUMBER_OF_PROCESSORS 等），用于给 Godot 子进程固定一套可复现的环境。历史运行脚本 开发产物/run_shots6.ps1、run_perf6.ps1 会先读取它并逐键 `Set-Item env:`，再 Start-Process 启动 Godot。

- **手动在 cmd/bash 里直接跑命令不需要它**（继承当前 shell 环境即可，本次 T3 实测均如此）。
- **用 PowerShell 脚本/CI 批量跑时建议走 run_*.ps1**，保证子进程环境一致（例如 TEMP 指向用户临时目录而不是异常路径）。
- base_env.json 是必须入库的用例文件，不得删除；它是 tools/ 下唯一被运行脚本读取的配置。

## 2. 自动化入口总览（main.gd，基线 tag 行号）

| 参数 | 作用 | 是否需要窗口渲染 | 输出 | 历史结果（历史参考） |
|---|---|---|---|---|
| `--selftest` | 运行 53 项内建自测（几何/材质/光照/时间/画质/音量/菜单/遮挡盒等） | headless 可；窗口模式才覆盖真实鼠标拖动与分辨率项 | 控制台 [TEST] PASS/FAIL 行；headless 下 [TEST] SKIP 真实鼠标拖动；配置写 开发产物/logs/settings_selftest.cfg | 53/0（P6_REPORT §5.1） |
| `--shots` | 菜单/设置面板/滑条/各时段机位截图 | 必须（GUI 渲染） | 开发产物/shots/*.png，控制台打印 [SHOT] 名称 WxH | 62 张 [SHOT]、0 SCRIPT/SHADER ERROR（P6_REPORT §5.2） |
| `--transition` | 从菜单点击开始游戏后的 12 帧过渡截图 | 必须（GUI 渲染） | 开发产物/shots/tr_*.png | 历史用于过渡验证 |
| `--perf` | 六场景 + 面板 + 五档画质性能采样（180/120 帧） | 必须（GUI 渲染；headless 无意义） | 控制台 [PERF] 行 + 开发产物/logs/perf6_all_*.log（经 run_perf6.ps1） | q0–q4 两轮，见 P6_REPORT §8 |
| `--quality N` | 指定画质档 0–4，仅与 --perf 同用时生效 | 随 --perf | 同上 | 五档 0..4 |
| `--audio-log` | （见 scripts/isle_audio.gd）音频事件逐条以 [IsleAudio] json 打印 | headless 可 | 控制台 | 历史音频排查用 |

实现位置（tag 8f80b13 的 scripts/main.gd）：参数解析 225–228 行、--quality 246 行、分发 260–270 行、_run_shots 1247 行、_run_transition 1813 行、_run_selftest 1859 行、[TEST] RESULT 2296 行、_save_shot 2304 行、_run_perf 3094 行；音频参数 scripts/isle_audio.gd:950。**行号以基线 tag 为准**，工作树被其它 P6 改动后可能浮动，用 `git show baseline-p6close-20261020:scripts/main.gd | grep -n ...` 复核。

## 3. 一键复现命令

以下命令均在任意目录执行（--path 用绝对路径）；Windows 下建议 bash（Git Bash）或 cmd，PowerShell 注意引号。

### 3.1 headless 自测（最快、无 GPU 争用）

```bash
"D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe" --headless --path D:/休闲小岛幻境/游戏工程 -- --selftest
```

**通过判据**：退出码 0；输出含 `[TEST] RESULT 53/53 passed`；无 `[TEST] FAIL` 行；允许 1 条 `[TEST] SKIP 真实鼠标拖动`。

**本次 T3 实测（2026-10-20 23:18）**：exit 0，耗时 26 秒，53 PASS / 0 FAIL / 1 SKIP，RESULT 53/53 passed；日志 开发产物/logs/t3_selftest_headless.log。

### 3.2 窗口自测（覆盖拖动与分辨率项）

```bash
"D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe" --path D:/休闲小岛幻境/游戏工程 --resolution 1600x900 -- --selftest
```

**通过判据**：窗口跑完后 RESULT passed=总项数；无 FAIL；真实鼠标拖动项实际执行。需交互式桌面会话；历史日志 开发产物/logs/final_selftest_window.log 为早期 48/48（当时自测项少于最终 53 项）。**本次 T3 未重跑窗口项**（GPU 由 verify 使用中），重跑请与 Lead 协调。

### 3.3 截图矩阵 --shots（窗口）

推荐用既有脚本（自动准备环境变量、重定向日志、超时 420s）：

```powershell
pwsh D:/休闲小岛幻境/开发产物/run_shots6.ps1
```

或手动：

```bash
"D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe" --path D:/休闲小岛幻境/游戏工程 --resolution 1600x900 -- --shots
```

**通过判据**：输出 `[SHOT] <name> WxH` 约 62 条（历史数量，见 P6_REPORT §5.2）；`开发产物/shots/` 下对应 png 存在；无 `SCRIPT ERROR` / `SHADER ERROR`；exit 0。历史日志：开发产物/logs/shots6_final_stdout.log、shots6_final_stderr.log。

### 3.4 过渡 --transition（窗口）

```bash
"D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe" --path D:/休闲小岛幻境/游戏工程 --resolution 1600x900 -- --transition
```

判据：开发产物/shots/ 下出现 tr_*.png（过渡帧序列）且无 SCRIPT ERROR。

### 3.5 性能 --perf（窗口，**T3 不跑，需独占 GPU**）

```powershell
pwsh D:/休闲小岛幻境/开发产物/run_perf6.ps1
```

**注意**：--perf 与 --shots 会抢 GPU，且性能受共享负载影响（历史两轮差异可达 35%）。不要与 verify 的 --perf 同时运行；本次 T3 未运行 --perf（按任务约定）。判据：控制台 [PERF] 行完整、`[PERF] end` 出现、退出期 RID 警告属正常；数值与 P6_REPORT §8 同档对比。

### 3.6 单个探针（headless 示例）

```bash
"D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe" --headless --path D:/休闲小岛幻境/游戏工程 --script res://tools/probe_water6.gd
```

**本次 T3 实测（2026-10-20 23:25）**：
- probe_settings6 → exit 0，`[RESULT] ALL PASS`（日志 开发产物/logs/t3_probe_settings6.log）。
- probe_water6 → exit 0，`=== probe_water6 结果: checks=17 fails=0 warns=0 ===`（日志 开发产物/logs/t3_probe_water6.log）。

**通过判据**：exit 0 且无 FAIL 行（多数探针以 `quit(0 if fails == 0 else 1)` 收尾，见各探针文件末尾）。不同探针的汇总行不同（[RESULT] ALL PASS / `结果: checks=.. fails=0` / `PROBE STATUS: PASS` / `PROBE6 RESULT: PASS` 等），以「fails=0 + 退出码 0」为准。

### 3.7 窗口探针示例（--window / --out）

```bash
# 五档画质窗口矩阵（截图 + 渲染断言）
"D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe" --path D:/休闲小岛幻境/游戏工程 --script res://tools/probe_quality6.gd -- --window --out=D:/休闲小岛幻境/开发产物/shots6/verify/quality

# 阁楼窗重影隔离矩阵（窗口，约 57 秒）
"D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe" --path D:/休闲小岛幻境/游戏工程 --script res://tools/probe_ghost6.gd -- --window --out=D:/休闲小岛幻境/开发产物/shots6/verify/ghost
```

说明：`--out=` 指定截图输出目录；不带 --window 时 probe_quality6 走 headless 契约校验。窗口探针需交互式桌面，禁止与 --perf/--shots 并行。

### 3.8 脚本语法/依赖静态检查（可选）

```bash
"D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe" --headless --path D:/休闲小岛幻境/游戏工程 --check-only --script res://scripts/main.gd
```

历史 P6_REPORT §5.1 用它做过 main.gd + 队友脚本 + 5 个 shader 的静态检查。**本次 T3 实测（23:29）**：exit 0；但本机沙箱下引擎启动时会额外打印 2 行 user:// 日志写入失败（见 §6 噪音 5），属预期。日志 开发产物/logs/t3_checkonly_main.log。

## 4. P6 阶段当前有效探针（13 个核心验收探针）

以下为 P6 收尾实际使用并有历史 PASS 记录的探针（证据见 P6_REPORT §5.1 与 开发产物/logs/）。除特别注明外均为 headless：

| 探针 | 模式/参数 | 检查内容 | 历史结果 |
|---|---|---|---|
| tools/probe_quality6.gd | headless；`--window --out=...` 出截图矩阵 | 五档画质契约（24 键/类型/区间/档间差异/映射/设置桥接） | checks=51 fails=0（final_quality.log） |
| tools/probe_water6.gd | headless | 海水 shader 波函数与 isle_waves.gd 同源、连续性、梯度 | checks=17 fails=0（final_water.log；本次 T3 复测 17/0） |
| tools/probe_settings6.gd | headless | 设置 schema/默认值/往返/迁移 | 46/0（本次 T3 复测 [RESULT] ALL PASS） |
| tools/probe_audio6.gd | headless | 音频混音器音量/总线/持久化/旧配置迁移 | 232/0 |
| tools/probe_cottage6.gd | headless | 小屋几何/材质/穿模 | 31/0 |
| tools/probe_bird6.gd | headless | 海鸥栖枝/朝向 | 45/0 |
| tools/probe_smoke6.gd | headless | 炊烟双时间窗逻辑 | 96/0 |
| tools/probe_astro6.gd | headless | 天文精度（太阳/月亮/星表） | 423/0 |
| tools/probe_menu6.gd | headless | 设置面板/ESC 动画/HUD 自动运镜 | 152/0 |
| tools/probe_menu7_t1.gd | headless | P6.1 菜单拼接回归（含 _fly_out 后 open 等） | 50/0 |
| tools/probe_esc_e2e_t1.gd | headless | 真实 main+menu 的 ESC 端到端开关 | 19/0 |
| tools/probe_frame_t5.gd | headless | 06_bird_roof/06_smoke_noon 机位取景与烟柱高度估算 | 5/0 |
| tools/probe_ghost6.gd | 窗口 `--window --out=...` | 阁楼窗重影隔离回归矩阵 | 26/0（约 56.8s） |

> 基线之后 verify-visual 新增的探针（tools/probe_ui_matrix6.gd、probe_ao_visual_t7.gd、probe_exit_diag_t7.gd、probe_quality_override_t7.gd）由 verify-visual 维护与说明，不属于基线 51 个探针；它们的命令示例见 docs/P6_TEST_RESULTS.md。

## 5. 基线 51 个探针清单（完整清单）

以下为 tag baseline-p6close-20261020 中 tools/probe_*.gd 的 51 个探针。「模式」依据头注释与源码是否含 save_png/get_viewport 判定；T3 未逐个重跑，历史通过情况以 P6_REPORT 与各阶段报告为准。默认模式 = headless（不渲染）。

| # | 探针 | 模式 | 用途/说明 |
|---|---|---|---|
| 1 | probe_ao_perf.gd | 窗口（--window） | PostAO 后处理开销 A/B |
| 2 | probe_astro.gd | headless | P4 天文/日照早期检查 |
| 3 | probe_astro6.gd | headless | T6 天文精度验证（P6 核心） |
| 4 | probe_audio6.gd | headless | P6 音频混音器验收（P6 核心） |
| 5 | probe_audio_p5.gd | headless | P5 夜间音效验收 |
| 6 | probe_bird6.gd | headless | T5 海鸥栖枝验收（P6 核心） |
| 7 | probe_bird_p5.gd | headless | P5 海鸥模型与朝向 |
| 8 | probe_bird_p5_shot.gd | 窗口 | P5 海鸥多机位截图 |
| 9 | probe_bird_roof_t5.gd | headless（实例化主场景） | 不同时刻海鸥栖树枝/屋顶分布检查 |
| 10 | probe_boat_p5.gd | headless（实例化主场景） | P5 小船生命周期 |
| 11 | probe_boat_smoke.gd | headless（实例化主场景） | 小船冒烟早期冒烟检查 |
| 12 | probe_cam.gd | headless | 相机参数早期检查 |
| 13 | probe_color.gd | 窗口 | 颜色采样并保存截图 |
| 14 | probe_cottage6.gd | headless | P6 小屋验收（P6 核心） |
| 15 | probe_cottage_p4.gd | headless | P4 小屋数值/共面/穿模 |
| 16 | probe_dims_tmp.gd | headless（实例化主场景） | 尺寸临时测量 |
| 17 | probe_dyn6.gd | headless | 动态物件早期检查 |
| 18 | probe_esc_e2e_t1.gd | headless（真实 main+menu） | ESC 端到端（P6 核心） |
| 19 | probe_esc_lead.gd | headless（实例化主场景） | Lead 的 ESC 诊断 |
| 20 | probe_frame_t5.gd | headless（实例化主场景） | 06 机位取景验证（P6 核心） |
| 21 | probe_fx_p4.gd | headless | P4 特效验收 |
| 22 | probe_ghost6.gd | 窗口（--window --out=） | 阁楼窗重影矩阵（P6 核心） |
| 23 | probe_glass_p5.gd | headless（--render-check 走窗口） | 玻璃模块契约 |
| 24 | probe_house.gd | 窗口 | 小屋屋顶低角度渲染调试 |
| 25 | probe_lighthouse_p5.gd | headless（实例化主场景） | P5 灯塔旋转 |
| 26 | probe_main_smoke_t5.gd | headless（实例化主场景） | 主场景炊烟发射状态诊断 |
| 27 | probe_mat_check.gd | headless | 材质参数检查 |
| 28 | probe_menu6.gd | headless | 设置面板/ESC/HUD 自动验收（P6 核心） |
| 29 | probe_menu6_shots.gd | 窗口（GUI 渲染） | 设置面板/HUD 截图 |
| 30 | probe_menu7_t1.gd | headless | P6.1 菜单回归（P6 核心） |
| 31 | probe_moon.gd | headless | 月相检查 |
| 32 | probe_moon2.gd | headless | 月相检查 v2 |
| 33 | probe_outline.gd | 窗口 | 描边截图 |
| 34 | probe_pal.gd | headless | 调色板检查 |
| 35 | probe_quality6.gd | headless / --window | 五档画质（P6 核心） |
| 36 | probe_quality_shots_t1.gd | 窗口（GUI） | 五档画质同机位对比截图 |
| 37 | probe_roof.gd | 窗口 | 屋顶渲染调试 |
| 38 | probe_scene_smoke_t5.gd | 窗口 | 主场景炊烟/海鸥集成截图 |
| 39 | probe_settings6.gd | headless | 设置 schema（P6 核心） |
| 40 | probe_shots6_t5.gd | 窗口 | T5 窗口截图 |
| 41 | probe_smoke6.gd | headless | 炊烟双时间窗（P6 核心） |
| 42 | probe_smoke_lead.gd | headless（实例化主场景） | Lead 炊烟时钟/粒子诊断 |
| 43 | probe_smoke_visual_t5.gd | 窗口 | 炊烟粒子截图诊断 |
| 44 | probe_task7_shots_t1.gd | 窗口（1600×900） | task-7 视觉流程截图 |
| 45 | probe_time_p4.gd | headless | P4 时间系统 |
| 46 | probe_time_p5.gd | headless（可选 --ui 窗口） | P5 时间 UI |
| 47 | probe_water6.gd | headless | 水面同源（P6 核心） |
| 48 | probe_world_p4.gd | headless | P4 world（灯塔/岩石/花/航线/栖枝） |
| 49 | probe_world_p5.gd | headless | P5 world 运行时 |
| 50 | probe_world_p5_shot.gd | 窗口（--resolution 1440x900） | 码头/路灯/船灯截图 |
| 51 | probe_write_test.gd | headless | 文件写入能力测试（早期排查） |

## 6. 常见 headless 限制与故障排除

1. **headless 无渲染**：`--headless` 使用 dummy 渲染器，任何 save_png/get_viewport 探针（上表「窗口」项）必须在窗口模式跑；headless 跑会拿不到图像或直接失败。
2. **真实鼠标拖动只能窗口测**：selftest 在 headless 下打印 `[TEST] SKIP 真实鼠标拖动（headless 无 GUI 输入；窗口模式 --selftest 覆盖）`；这是预期行为，不是失败。
3. **分辨率自测项只在窗口模式实测**；--resolution 是引擎窗口尺寸参数（如 --resolution 1600x900），不是游戏设置。
4. **user:// 写入失败**：历史沙箱下出现 `ERR_FILE_CANT_OPEN`；项目自动化已把所有输出改到 开发产物/。不要在新代码里写 user://。
5. **无害噪音**（可忽略，不是失败）：
   - `ERROR: Failed to open 'user://logs/godot2026-....log'.` 与 `ERROR: Failed to open log file for writing: user://logs/godot.log`（每次启动各 1 行；本机沙箱禁止 Godot 写用户目录，引擎自身日志落盘失败，不影响运行与退出码——这正是 P6 约定不写 user:// 的原因）。
   - `ERROR: Failed to read the root certificate store.`（headless 下 Windows 证书存储读取失败）
   - `[godot_ai game_helper] registered mcp capture ...`（addons/godot_ai 的帮助器注册日志）
   添加了该 autoload。
   - 退出时 `ERROR: N RID allocations ... were leaked at exit.`（清理顺序问题，历史 --perf after_6s orphan 稳定）
6. **窗口模式差异**：窗口/桌面会话不同分辨率、DPI、虚拟显示器（本机有向日葵 OrayIddDriver）都会影响截图；对比截图请固定 --resolution 并同环境跑。
7. **性能数据不可跨轮直接比**：共享 GPU/后台进程会造成 35% 级差异；性能结论必须同轮、独占、同分辨率。
8. **探针退出码**：多数探针用 `quit(0 if fails == 0 else 1)`，CI 里用退出码判定最稳；部分探针（如 probe_audio6/astro6）打印自己的 PASS/FAIL 汇总行。
9. **--check-only** 只做脚本解析检查，不运行游戏逻辑（Godot 引擎参数）。
10. 若窗口启动后卡住/无响应：先 tasklist 查遗留 Godot 进程并结束（确认不是他人正在跑的验证）；日志在 开发产物/logs/ 下按脚本名/时间区分。

## 7. 输出位置与 开发产物 目录归属规则

`D:/休闲小岛幻境/开发产物/` 在 git 仓库之外，**永远不入库**。归属与清理规则：

| 子目录/文件 | 生成者 | 内容 | 是否可清理 | 入库 |
|---|---|---|---|---|
| 开发产物/logs/ | 各验证者、run_*.ps1、探针重定向 | 运行日志（*.log、*.cfg、分析 txt） | 可清理（保留关键 PASS 证据即可；历史证据删前先确认引用） | 否 |
| 开发产物/shots/、shots6/<子集>/ | --shots、--transition、窗口探针 | 截图 png（含历史验收矩阵） | 可清理，但历史验收截图是证据，删除前确认 | 否 |
| 开发产物/probes/ | 探针/验证者 | 探针中间产物 | 可清理 | 否 |
| 开发产物/baseline/ | T3 | 引用审计脚本（scan_references_v3.py、count_stats*.py）与原始输出（reference_audit_v3.md/json） | **保留**（审计可复现依据） | 否 |
| 开发产物/archive/scripts_p6_intermediate/ | T3 | P6 中间文件归档（menusplice 报告、孤儿 uid、临时探针、pyc） | **保留**（可回溯） | 否 |
| 开发产物/backup/ | 各阶段 | 修改前备份（发布版 exe、菜单/特效源码备份） | **保留**（回滚依据） | 否 |
| 构建输出/、发布/ | 导出/发布流程 | exe 构建产物与发布副本 | 由发布流程管理 | 否 |
| 引擎/ | 环境 | Godot 可执行文件 | 否 | 否 |

规则：**只有 游戏工程/ 下被 git 跟踪的文件入库**；开发产物下的任何日志、截图、备份、归档都不提交。仓库内不入库（.gitignore）：.godot/、*.log、*.import.tmp、.editor_pid、.game_pid、__pycache__/、*.pyc。必须入库：tools/base_env.json、tools/probe_*.gd 及其 .gd.uid。

## 8. .uid 文件策略（P6 结论）

Godot 4.4+ 会为每个 .gd/.gdshader 生成同名 .uid（如 scripts/main.gd.uid，内容 uid://yt2p6age324u）。**结论：.uid 必须与源文件成对提交，禁止用 .gitignore 忽略 *.uid。**

依据与现状（tag 基线实测）：
- 基线 544 个文件中已跟踪 220 个 .uid；tools/ 下有 37 个 .gd.uid；.tscn 通过 uid:// 引用脚本（isle.tscn 引用 res://scripts/main.gd 的 uid://yt2p6age324u），缺失 .uid 时引擎会重新生成新 uid，历史引用会失效。
- P6 收尾期间运行 Godot 导入时又产生了一批未跟踪 .uid（本轮观测 20 个：19 个 tools/probe_*.gd.uid + 1 个 shaders/post_ao.gdshader.uid），当时未提交。
- 处理：T3 已补交与**基线已跟踪源文件**配对的 tools/probe_*.gd.uid（19 个，见 T3 提交）；shaders/post_ao.gdshader.uid 属 lifecycle 的 write scope（shaders/），由 lifecycle 随着色器改动提交；verify-visual 新增探针（probe_*_t7、probe_ui_matrix6）的 .uid 由其与源文件一起提交。
- 开发约定：新增 .gd/.gdshader 时同时 `git add` 源文件与同名 .uid；不要单独提交孤儿 .uid（源已删除的 .uid 应删除，P6 已归档一例 script/menu_orig_t1.gd.uid）。

## 9. 本次 T3 实测记录（可复核）

| 时间 | 命令 | 结果 | 日志 |
|---|---|---|---|
| 23:18 | `console.exe --headless --path D:/休闲小岛幻境/游戏工程 -- --selftest` | exit 0，26 秒，53 PASS / 0 FAIL / 1 SKIP，RESULT 53/53 | 开发产物/logs/t3_selftest_headless.log |
| 23:25 | `console.exe --headless --path ... --script res://tools/probe_settings6.gd` | exit 0，[RESULT] ALL PASS | 开发产物/logs/t3_probe_settings6.log |
| 23:25 | `console.exe --headless --path ... --script res://tools/probe_water6.gd` | exit 0，checks=17 fails=0 warns=0 | 开发产物/logs/t3_probe_water6.log |
| 23:2x | 工程卫生扫描（引用审计/uid/import/空文件） | 见 docs/P6_REFERENCE_AUDIT.md | 开发产物/baseline/reference_audit_v3.md |

> 未运行项：窗口自测、--shots、--transition、--perf（任务约定 T3 不跑 --perf；窗口任务需独占 GPU，由 Lead 安排）。历史窗口结果见 docs/P6_BASELINE.md §5，仅作历史参考。

## 10. 变更记录

| 日期 | 变更 | 作者 |
|---|---|---|
| 2026-10-20 | 新建本文档：CLI 参数表、一键复现命令、13 个 P6 核心探针、51 个基线探针清单、headless 限制、开发产物归属、.uid 策略、实测记录 | T3 hygiene |
