# P6 自动化验收结果（T4 / verify-auto）

> 本文件为 T4 独立重跑记录。**所有判定以 Lead 发出 FREEZE 后、基于冻结 HEAD 的实际运行日志为准**；历史数字（docs/P6_REPORT.md §5/§8）仅作对照列，不作为本次结论。
>
> - 执行者：verify-auto（独立重跑；未修改源码/探针/断言）
> - 执行时间：headless 批 2026-10-20 23:45–23:53；窗口/perf 批 2026-10-20 23:53–2026-10-21 00:06；astro_xcheck 按 astro 提交 b56dc88 后重跑 00:07、headless perf 对照 00:10/00:12（本机日志时间戳，Asia/Shanghai）
> - 冻结 HEAD：`55a8d73735970d84a196e4dbe1e58c25bf7df837`，tag `freeze-p6close-20261021_0515`（基线 `baseline-p6close-20261020` = 8f80b13）
> - 运行期间 HEAD 前进到 `3161429`：`git diff 55a8d73..HEAD` 仅 docs 3 个验收文档 + `tools/probe_astro_xcheck_t7.gd`（test-only 例外授权），**scripts/ 与其余探针零改动**；代码判定仍以冻结 HEAD 55a8d73 为准。astro_xcheck 重跑使用 b56dc88 之后的探针版本（文件 23:51:27 保存，工作树无后续修改）。
> - 引擎：D:\休闲小岛幻境\引擎\Godot_v4.7.2-stable_win64_console.exe（Godot 4.7.2 stable, Forward+）
> - 硬件/显示：RTX 2060，显示器 2560×1440（性能测试窗口 1920×1080，自动化 shots/selftest 1600×900）
> - 日志根目录：`开发产物/logs/verify/`；截图根目录：`开发产物/shots6/verify/`（`--shots` 固定写入 `开发产物/shots/`，跑后按 mtime 归集/复制）
> - 历史对照来源：`游戏工程/docs/P6_REPORT.md` §5（自动化）、§8（性能）、§11（试玩修复）

## 1. 总览

| # | 测试项 | 结果 | 判定 | 证据（日志/截图） |
|---|--------|------|------|-------------------|
| 1 | `--selftest` headless | **RESULT 53/53 passed，exit 0**（SKIP 1 项：真实鼠标拖动，窗口模式覆盖） | ✅ PASS | `logs/verify/selftest_headless.log` |
| 2 | `--selftest` 窗口 1600×900 | **RESULT 55/55 passed，exit 0**（无 SKIP；headless 跳过的 2 项真实鼠标拖动在窗口实跑通过） | ✅ PASS | `logs/verify/selftest_window.log` |
| 3 | headless 探针 ×16（13 核心 + t7 新增 2 + astro_xcheck 1） | **16/16 退出码 0，所有汇总行 fail=0**；astro_xcheck 按 astro 提交 b56dc88 后重跑：`pass=2489 fail=0 skip=0 known_bug=0`（00:07，exit 0） | ✅ PASS | `logs/verify/probe_*.log` |
| 4 | 窗口探针（quality6 / ghost6 / ao_visual_t7 / ao_perf） | **4/4 全部 exit 0**：quality6 `checks=68 fails=0`（33.2s）、ghost6 `checks=26 fails=0`（57.4s）、ao_visual `RESULT 1/1 pass`、ao_perf q2/q3/q4 AO 开销 +1.13/+1.70/+4.33 ms；ui_matrix6 按 Lead 指示跳过（verify-visual 已在 T5 跑 1138 项） | ✅ PASS | `logs/verify/quality6_window.log`、`ghost6_window.log`、`ao_visual.log`、`ao_perf.log`；截图 `shots6/verify/{quality,ghost}` |
| 5 | `--shots` | **exit 0**、89s；`[SHOT]` 62 行 = **61 张 PNG** + 1 行 rocks 信息行（非 PNG）；61 个文件名与判定标准一致且无重复；日志无 SCRIPT/SHADER ERROR | ✅ PASS | `logs/verify/shots.log`；截图 `shots6/verify/shots/`（61） |
| 6 | `--transition` | **exit 0**；13 张：tr_00_menu + tr_01_0.15 / 0.35 / 0.55 / 0.80 / 1.05 / 1.30 / 1.55 / 1.90 / 2.30 / 2.90 / 3.60 / 4.40 | ✅ PASS | `logs/verify/transition.log`；截图 `shots6/verify/transition/`（13） |
| 7 | `--perf` 五档（独占窗口） | **exit 0**、52s；场景采样 9 组（fps 146.4–162.2、objects 1584–2530、draw_calls 1245–1768、VRAM≈350–352 MB）+ 五档 80.2 / 86.9 / 147.4 / 153.4 / 155.5 fps（均高于 P6_REPORT §8 第二轮，机器空闲，无回退）；**缺陷单列：`--quality N` 对场景采样无效**（§3.7） | ✅ PASS（--quality 缺陷记录，不影响默认画质） | `logs/verify/perf.log`、`perf_q0..q4.log`、`perf_headless.log`、`perf_headless_run2.log` |
| 8 | 干净启动 + 正常退出（headless / 窗口） | headless 4 次全部 exit 0：3 次零退出告警、1 次 8 个 ObjectDB 泄漏（`boot_clean_run1.log`，引擎 headless Dummy 音频退出竞态，lifecycle §4.3）；**窗口 exit 0、16s，无已知外 ERROR/WARNING** | ✅ PASS | `logs/verify/boot_clean_run1-3.log`、`boot_exit_headless.log`、`boot_exit_window.log` |
| 9 | 测试真实性审计（git diff baseline..HEAD） | 35 文件 +3140/-77；既有 51 个基线探针 .gd 零修改；selftest 断言 55→55 未减、第 24 组判据更严 | ✅ PASS | 本文件 §3.9；`logs/verify/assert_audit.txt` |

## 2. 判定标准（执行前确认，供复核）

- **selftest**：日志须出现 `[TEST] RESULT 53/53 passed`（headless）或 `55/55 passed`（窗口），exit code 0。
  - 依据 `scripts/main.gd`：`results.append` 共 55 处，其中 2 处（"设置滑条可真实鼠标拖动"、"时间轴可真实鼠标拖动并改变时刻"）位于 `else` 窗口分支；headless 分支打印 `[TEST] SKIP 真实鼠标拖动…`。故 headless 53 项 / 窗口 55 项。
- **headless 探针**：各探针自身汇总行（`checks=… fails=0` / `PROBE STATUS: PASS` / `SUMMARY PASS=… FAIL=0` / `RESULT pass=… fail=0` 等）与 exit code 0 同时满足。
- **--shots**：`[SHOT]` 行 62 行 = 61 张 PNG + 1 行 `[SHOT] rocks hero kinds=…` 信息；exit code 0；日志无 SCRIPT ERROR / SHADER ERROR（已知 user:// 日志写入失败属环境限制，单列说明）。
- **--transition**：13 张（`tr_00_menu` + `tr_01_0.15` … `tr_12_4.40`），exit code 0。
- **--perf**：`[PERF]` 场景采样与五档全部输出、无脚本错误、exit code 0；数值与历史对照列对比，回退需给出解释（不得为指标删视觉）。
- **干净退出**：exit code 0；退出期 RID/ObjectDB 行数量与 lifecycle 任务（P6_LIFECYCLE_FINDINGS.md）结论对照分类（真实泄漏/退出顺序/引擎诊断），不隐藏、不关日志。

## 3. 明细

### 3.1 `--selftest` headless

```
"D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe" --headless --path "D:/休闲小岛幻境/游戏工程" -- --selftest
```

- 结果：**RESULT 53/53 passed，exit 0**（23:52:27 完成；同版本两次运行结果一致）
- FAIL/SKIP 明细：无 FAIL；SKIP 1 项——`[TEST] SKIP  真实鼠标拖动（headless 无 GUI 输入；窗口模式 --selftest 覆盖）`，由 §3.2 窗口 55/55 覆盖。
- 历史对照：53/53（P6_REPORT §5.1，22:17/22:49）
- 历史对照：53/53（P6_REPORT §5.1，22:17/22:49）
- 证据：`开发产物/logs/verify/selftest_headless.log`

### 3.2 `--selftest` 窗口（真实鼠标拖动/ESC e2e 覆盖）

```
"D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe" --path "D:/休闲小岛幻境/游戏工程" --resolution 1600x900 -- --selftest
```

- 结果：**RESULT 55/55 passed，exit 0**（无 SKIP；headless 跳过的 2 项——「设置滑条可真实鼠标拖动」「时间轴可真实鼠标拖动并改变时刻」——在窗口模式真实执行并通过）
- 说明：旧窗口日志（20:42）只有 48 项且一版 47/48（FAIL 立体水花可生成），为旧代码；本次冻结后新跑 55/55，覆盖真实鼠标拖动/ESC e2e。
- 证据：`开发产物/logs/verify/selftest_window.log`

### 3.3 headless 探针（16 项：13 核心 + t7 新增 2 + astro_xcheck）

| 探针 | 命令（--script 后脚本名） | 期望（历史对照） | 本次结果 | exit | 判定 | 日志 |
|------|---------------------------|------------------|----------|------|------|------|
| probe_water6 | `res://tools/probe_water6.gd` | checks=17 fails=0 | checks=17 fails=0 warns=0 | 0 | ✅ PASS | `logs/verify/probe_water6.log` |
| probe_quality6（headless 契约） | `res://tools/probe_quality6.gd` | checks=51 fails=0 | checks=51 fails=0 用时=1.0s | 0 | ✅ PASS | `logs/verify/probe_quality6.log` |
| probe_settings6 | `res://tools/probe_settings6.gd` | 46 项全 PASS | [RESULT] ALL PASS（[PASS]30+[DAY]10 全过，无 [FAIL]） | 0 | ✅ PASS | `logs/verify/probe_settings6.log` |
| probe_audio6 | `res://tools/probe_audio6.gd` | 232 checks 0 failures | PROBE RESULT: 232 checks, 0 failures / PROBE STATUS: PASS | 0 | ✅ PASS | `logs/verify/probe_audio6.log` |
| probe_cottage6 | `res://tools/probe_cottage6.gd` | pass=31 fail=0 | [PROBE6] RESULT pass=31 fail=0 -> OK | 0 | ✅ PASS | `logs/verify/probe_cottage6.log` |
| probe_bird6 | `res://tools/probe_bird6.gd` | pass=45 fail=0 | T5 BIRD PROBE RESULT: PASS pass=45 fail=0 | 0 | ✅ PASS | `logs/verify/probe_bird6.log` |
| probe_smoke6 | `res://tools/probe_smoke6.gd` | pass=96 fail=0 | T5 SMOKE PROBE RESULT: PASS pass=96 fail=0 | 0 | ✅ PASS | `logs/verify/probe_smoke6.log` |
| probe_astro6 | `res://tools/probe_astro6.gd` | PASS（423 项） | [SUMMARY] checks=423 fail=0（16.98s）/ PROBE6 RESULT: PASS | 0 | ✅ PASS | `logs/verify/probe_astro6.log` |
| probe_menu6 | `res://tools/probe_menu6.gd` | PASS=152 FAIL=0 | SUMMARY PASS=152 FAIL=0 | 0 | ✅ PASS | `logs/verify/probe_menu6.log` |
| probe_menu7_t1 | `res://tools/probe_menu7_t1.gd` | PASS=50 FAIL=0 | SUMMARY PASS=50 FAIL=0 | 0 | ✅ PASS | `logs/verify/probe_menu7_t1.log` |
| probe_esc_e2e_t1 | `res://tools/probe_esc_e2e_t1.gd` | PASS=19 FAIL=0 | === SUMMARY PASS=19 FAIL=0 === | 0 | ✅ PASS | `logs/verify/probe_esc_e2e_t1.log` |
| probe_frame_t5 | `res://tools/probe_frame_t5.gd` | pass=5 fail=0 | T5 FRAME PROBE RESULT: PASS pass=5 fail=0 | 0 | ✅ PASS | `logs/verify/probe_frame_t5.log` |
| probe_main_smoke_t5（集成诊断） | `res://tools/probe_main_smoke_t5.gd` | [DIAG] 输出无异常，exit 0 | [DIAG] 输出完整（smoke/时间窗/粒子状态），无脚本错误，诊断型无断言 | 0 | ✅ PASS | `logs/verify/probe_main_smoke_t5.log` |
| probe_quality_override_t7（T7 新增，Lead） | `res://tools/probe_quality_override_t7.gd` | 24 键真实接线 + AO 覆盖三态 + 往返，全 PASS（预检 173/173） | RESULT 173/173 pass, 0 fail | 0 | ✅ PASS | `logs/verify/probe_quality_override_t7.log` |
| probe_exit_diag_t7（T1 新增诊断） | `res://tools/probe_exit_diag_t7.gd` | [DIAG] 观察型，exit 0；孤儿单元/池销毁数据供 lifecycle 分类 | baseline orphan=0 → 退役后 delta=11 → 池销毁后 orphan=0 | 0 | ✅ PASS | `logs/verify/probe_exit_diag_t7.log` |
| probe_astro_xcheck_t7（T7 新增，astro） | `res://tools/probe_astro_xcheck_t7.gd` | `[SUMMARY] pass=… fail=0 …` + `T7 ASTRO XCHECK PROBE RESULT: PASS`，exit 0；已知 bug 单独计数 | [SUMMARY] pass=2489 fail=0 skip=0 known_bug=0 raw_lines=684 elapsed_ms=47350、RESULT PASS（00:07，astro b56dc88 后重跑；23:49 旧版 2488 保留为 `probe_astro_xcheck_t7_OLD_pre_astro_fix.log`） | 0 | ✅ PASS | `logs/verify/probe_astro_xcheck_t7.log` |

统一命令模板：

```
"D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe" --headless --path "D:/休闲小岛幻境/游戏工程" --script res://tools/<probe>.gd
```

- 未纳入本轮 16 项清单的其余探针（tools/probe_*.gd 共 56 个）说明：
  - 历史版本探针（`*_p4`、`*_p5`、`probe_time_p4/p5`、`probe_world_p4/p5`、`probe_boat_p5` 等）：其断言契约已被 P6 的 `*6`/`*_t5` 新探针覆盖（同一系统更新版），按 P6_TESTING.md 核心清单不再重复跑；如需历史对照见 docs/P6_REPORT.md §5.1。
  - 视觉/截图类探针（`probe_ui_matrix6`、`probe_shots6_t5`、`probe_quality_shots_t1`、`probe_world_p5_shot` 等）归 verify-visual 主责（task-5 视觉验证矩阵），T4 仅在 GPU 空档交叉复跑 `probe_ui_matrix6` 作为窗口批补充。
  - 临时/工具脚本（`probe_write_test`、`probe_dims_tmp`、`probe_menu6_shots`、`probe_smoke_lead`、`probe_smoke_visual_t5` 等）无稳定断言契约或属队友专用诊断，不纳入验收清单。
  - `probe_fx_p4`（鸟群 1 项 FAIL）为 baseline 8f80b13 已复现的既有基线问题（lifecycle 文档 §4.4 有证据），非本次回归；如纳入清单应标 baseline-known。

### 3.4 窗口探针

| 探针 | 命令 | 期望（历史对照） | 本次结果 | exit | 判定 | 日志/截图 |
|------|------|------------------|----------|------|------|-----------|
| probe_quality6 窗口矩阵 | `--path 游戏工程 --script res://tools/probe_quality6.gd -- --window --out=D:/休闲小岛幻境/开发产物/shots6/verify/quality` | 窗口矩阵版含截图检查，历史窗口 68 checks | checks=68 fails=0 用时=33.2s | 0 | ✅ PASS | `logs/verify/quality6_window.log`；截图 `shots6/verify/quality/`（11 png） |
| probe_ghost6 | `--path 游戏工程 --script res://tools/probe_ghost6.gd -- --window --out=D:/休闲小岛幻境/开发产物/shots6/verify/ghost` | checks=26 fails=0（56.8s） | checks=26 fails=0 用时=57.4s | 0 | ✅ PASS | `logs/verify/ghost6_window.log`；截图 `shots6/verify/ghost/`（22 png） |
| probe_ao_perf | `--path 游戏工程 --script res://tools/probe_ao_perf.gd -- --window` | AO 开销数据（q2/q3/q4） | q2 ao_off 120.4fps/8.30ms → ao_on 106.0/9.43（+1.13ms / 13.6%）；q3 67.9/14.72 → 60.9/16.42（+1.70ms / 11.6%）；q4 56.9/17.57 → 45.7/21.89（+4.33ms / 24.6%）；viewport=1600x900 | 0 | ✅ PASS | `logs/verify/ao_perf.log` |
| probe_ao_visual_t7（T7 新增，Lead） | `--path 游戏工程 --resolution 1600x900 --script res://tools/probe_ao_visual_t7.gd` | AO 真实效果/体积雾可见性/AO 帧成本；`RESULT x/x pass` | RESULT 1/1 pass（该探针恒 quit 0，以 RESULT 行为判定；日志含 AO cost off avg=4.893ms → on avg=5.729ms，delta=0.836ms） | 0 | ✅ PASS | `logs/verify/ao_visual.log`；本次截图 21 张写探针固定目录 `开发产物/shots6/ao/`（目录累计 45 张含历史 A/B） |
| probe_ui_matrix6（T5 视觉矩阵，verify-visual 归属） | `--path 游戏工程 --script res://tools/probe_ui_matrix6.gd -- --phase all` | 视觉/分辨率/回退/DPI 矩阵 | **按 Lead GPU_GO 指示跳过**（verify-visual 已在 T5 跑 1138 项，避免重复占用 GPU） | — | ➖ 跳过（Lead 指定，非 FAIL） | — |

### 3.5 `--shots`

```
"D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe" --path "D:/休闲小岛幻境/游戏工程" --resolution 1600x900 -- --shots
```

- 结果：**exit 0**、用时 89s（23:56:48 完成）；`[SHOT]` 共 **62 行 = 61 张 PNG + 1 行信息**：`[SHOT] rocks hero kinds=6 at (17.75201, 0.58535, -10.14263)`（该行为 main.gd 额外 print，不产生 PNG，不是「多出来的一张」）；61 个 PNG 文件名与判定标准名单一致、无重复 → release 脚本按 61 张断言正确。
- 输出目录：`开发产物/shots/`（代码常量 SHOTS_DIR 固定）；本次运行新生成 PNG 已按日志名单归集到 `开发产物/shots6/verify/shots/`（61 个文件已核对）。
- 日志检查：无 SCRIPT ERROR / SHADER ERROR；ERROR 行 = 24 条 `Condition f.is_null() is true` @ `servers/rendering/renderer_rd/shader_rd.cpp:696`（调用栈 `_build_environment` main.gd:376 / `_ready` main.gd:254，= user:// shader 缓存写入被沙箱阻止，环境限制）+ 2 条 `Failed to open user://logs/...` + 1 条 root certificate store；另有 `[SHOTDBG]` 第二次 ESC 注入未生效后回退 `_on_menu_start(true)`（与历史一致，`07_menu_exit_018` 截图正常）。
- 证据：`logs/verify/shots.log`（stdout/stderr 合并重定向）

### 3.6 `--transition`

```
"D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe" --path "D:/休闲小岛幻境/游戏工程" --resolution 1600x900 -- --transition
```

- 结果：**exit 0**（23:55:15 完成）；13 张：`tr_00_menu` + `tr_01_0.15`、`tr_02_0.35`、`tr_03_0.55`、`tr_04_0.80`、`tr_05_1.05`、`tr_06_1.30`、`tr_07_1.55`、`tr_08_1.90`、`tr_09_2.30`、`tr_10_2.90`、`tr_11_3.60`、`tr_12_4.40`（时间轴 times 数组与 main.gd `_run_transition` 实现一致）。
- 日志无 SCRIPT ERROR；`f.is_null` shader 缓存环境错误同 §3.5。
- 证据：`logs/verify/transition.log`；截图归集 `shots6/verify/transition/`（13 个已核对）

### 3.7 `--perf`（独占窗口）

```
"D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe" --path "D:/休闲小岛幻境/游戏工程" --resolution 1920x1080 -- --perf
```

- 执行前提：tasklist 确认无其他 Godot 进程；Lead 统一排程独占时段（GPU_GO）后执行，用时 52s，exit 0。
- 实测分辨率：请求 1920×1080，实际 `[PERF] begin viewport=1600x900`（`_apply_resolution` 对自动化跳过，已知限制 §4.2）；begin 参数 msaa=2 quality=2 grass=22500 lights=8 vsync_disabled。

场景采样（每场景 180 帧，time_panel 120 帧，lite 各 120 帧）：

| 场景 | fps | frame_ms | cpu_ms | objects | draw_calls | VRAM(MB) |
|------|-----|----------|--------|---------|------------|----------|
| noon_clear | 158.1 | 6.33 | 8.17 | 2080 | 1687 | 350.3 |
| golden_cloud_water | 147.9 | 6.76 | 27.05 | 2096 | 1707 | 350.4 |
| night_shadows | 146.4 | 6.83 | 11.78 | 2105 | 1716 | 350.4 |
| night_close | 148.8 | 6.72 | 16.21 | 1584 | 1245 | 350.4 |
| far_island | 162.2 | 6.17 | 7.93 | 2103 | 1710 | 350.4 |
| sky_up | 151.8 | 6.59 | 19.43 | 2103 | 1714 | 350.4 |
| time_panel_open | 153.6 | 6.51 | 21.72 | 2530 | 1768 | 352.1 |
| lite_noon_nomultimesh | 150.8 | 6.63 | — | 2049 | 1656 | 352.1 |
| lite_night_nomultimesh | 157.6 | 6.34 | — | 2058 | 1669 | 352.1 |

五档循环（单次 `--perf` 自带 q4→q0，各 120 帧；`[PERF] quality_N` 实测）：

| quality | fps | frame_ms | msaa | render_scale | grass | lights | VRAM(MB) |
|---------|-----|----------|------|--------------|-------|--------|----------|
| q4 | 80.2 | 12.47 | 3 | 1.25 | 22500 | 12 | 879.3 |
| q3 | 86.9 | 11.50 | 3 | 1.15 | 22500 | 10 | 759.5 |
| q2 | 147.4 | 6.78 | 2 | 1.00 | 22500 | 8 | 352.2 |
| q1 | 153.4 | 6.52 | 1 | 0.92 | 15750 | 6 | 260.5 |
| q0 | 155.5 | 6.43 | 0 | 0.85 | 10125 | 4 | 219.6 |

- **`--quality N` 缺陷（如实记录，未改代码）**：另跑 5 次 `-- --perf --quality 0..4`（`perf_q0..q4.log`），全部 exit 0，但每次场景采样 `[PERF] begin quality=2` 恒为默认档 → 该参数未生效。根因（静态定位）：`main.gd:246-251` 用 `_cmdline_value("--quality")` 覆盖 `_quality`（`_cmdline_value` 定义 `main.gd:276`，命令语法 `-- --perf --quality N` 正确），但紧接着 `main.gd:255` 调 `_apply_user_settings(false)` → `main.gd:3253` `_quality = Settings.sanitize_quality(_settings.get("quality", 2))` 将其重置为 2。属测试工具路径缺陷，不影响玩家默认画质/渲染；修复需改代码（超冻结范围，只报告不修改）。五档差异验收以每次 `--perf` 自带循环数据为准。
- **after_6s 退出前对象（orphan 定性）**：`perf.log` objects=24 nodes=1635 orphan=10；`perf_q1..q4` orphan=20（q4 nodes=1625）；对照 headless 同命令 2 次 after_6s orphan=0、nodes=1645（`perf_headless*.log`；两次 exit 0，其中 run2 退出期有 4 ObjectDB leaked，属 §3.8 同一类引擎 headless Dummy 清理竞态，非应用对象泄漏）。窗口 (nodes+orphan) 恒 = 1645（= headless 基线）：10 节点/单元 = Splash 池退役单元 1×Node3D + 3×Ring Mesh + 3×Column Mesh + 3×CPUParticles3D（`scripts/fx.gd:943-990`），退役路径 `_finish()`→`remove_child`+`_free.append`（`fx.gd:1043-1057`），触发链为 Ripples 自动鱼跃（`fx.gd:1445-1450`）→落水 `_fire_splash`→Splash 激活→退役；池销毁/退出时释放（`fx.gd:881-897`、`1323-1337`；`probe_exit_diag_t7` 实测池销毁后 orphan 11→0）。六份窗口 perf 日志 + 窗口 selftest/shots/transition/探针/干净退出日志 **0 条 leaked/ObjectDB/RID 告警** → 判定为**设计内 FX 池化游离单元，非泄漏，不影响 exit 0**。未解释项如实记录：headless 本次为何不产生退役单元未做节点级逐帧定位（冻结期不加插桩），不作为通过依据。
- 历史对照：P6_REPORT §8 第二轮 q4 40.9 / q3 63.7 / q2 121.9 / q1 98.3 / q0 143.9 fps。本次五档均更高（机器空闲，无其他 Godot 进程），**无性能回退**；不同轮次不可直接类比，仅记录。
- 判定：✅ PASS（性能无回退；`--quality` 为测试工具路径缺陷单列，未删除任何视觉效果）。
- 证据：`logs/verify/perf.log`（主跑）、`perf_q0..q4.log`（--quality 尝试）、`perf_headless.log`、`perf_headless_run2.log`（对照）

### 3.8 干净启动与正常退出

| 场景 | 命令 | exit | ERROR/WARNING 摘要 | 判定 | 日志 |
|------|------|------|-------------------|------|------|
| headless 启动 10s 退出 | `--headless --path 游戏工程 --quit-after 600` | **0**（4/4 次） | ERROR 仅 3 条已知：2×`Failed to open 'user://logs/...'`（沙箱禁写 user://）+ 1×`Failed to read the root certificate store`（headless 无系统证书库）。退出期 ObjectDB 泄漏偶发：4 次中仅 `boot_clean_run1.log` 出现 **8 ObjectDB instances leaked**，其余 3 次 0 行 | ✅ PASS | `logs/verify/boot_exit_headless.log`、`boot_clean_run1-3.log` |
| 窗口启动 10s 退出 | `--path 游戏工程 --resolution 1600x900 --quit-after 600` | **0**（16s） | 无已知外 ERROR/WARNING；仅 user:// shader 缓存 `f.is_null` 环境错误（同 §3.5） | ✅ PASS | `logs/verify/boot_exit_window.log` |

- 退出期 RID/ObjectDB 行按 lifecycle 结论（`docs/P6_LIFECYCLE_FINDINGS.md` §4.3/§4.4）分类：
  - headless 1 次 8 个 ObjectDB 泄漏（其余 3 次 0）：**引擎侧 headless Dummy 音频驱动退出竞态**（非应用对象泄漏、不影响 exit 0，lifecycle 报告 §4.3）；`probe_exit_diag_t7` 实测应用侧 FX 池退役单元在池销毁后 orphan 归 0，佐证应用对象无真实泄漏。
  - `probe_quality_override_t7` 退出期 10 ObjectDB + 1 resource 警告：headless 渲染/音频 Dummy 对象清理顺序，非应用泄漏（同样归类）。
  - 窗口 perf `after_6s orphan=10/20`：已定位为 Splash FX 池设计内退役游离单元（非泄漏，详见 §3.7）；窗口全部日志 0 条 ObjectDB/RID 泄漏告警。
  - headless perf 对照 run2 退出期 4 ObjectDB leaked（run1 为 0）：与 headless 启动退出同类（引擎 Dummy 清理竞态），两次 exit 0、after_6s orphan=0。

### 3.9 测试真实性审计（只读）

```
git -C 游戏工程 diff baseline-p6close-20261020..HEAD -- scripts tools docs
```

- 审计范围：`git diff baseline-p6close-20261020..freeze-p6close-20261021_0515 -- scripts tools`（FREEZE tag 55a8d73）；原始 diff 3602 行见 `logs/verify/audit_full.diff`。
- 变更统计：35 文件 +3140/-77。scripts：main.gd +112（时区语义 P1 修复、fog_scale/lod 接线、FX 池生命周期调用）、fx.gd +46（对象池退出释放）、menu.gd +16（AO 覆盖别名归一、移除体积雾覆盖入口）。
- **测试文件未被修改**：既有 51 个基线探针 `.gd` 无任何 M 记录；tools/ 仅新增 5 个探针（probe_ao_visual_t7、probe_astro_xcheck_t7、probe_exit_diag_t7、probe_quality_override_t7、probe_ui_matrix6）与 19 个 `.gd.uid`；删除项全部为临时/清理文件（`_tmp_inst_test.gd`、`_tmp_typed_test.gd`、`__pycache__/*.pyc`、`menusplice_report.txt`、`menu_orig_t1.gd.uid`）。
- 断言数量：`grep -c 'results.append'` 基线 55 / 冻结 55（未减；含 2 条窗口专属）。第 24 组 4 条数量不变：删除“现实时间天空与东京时区同源”“切换时区天空立即同源（纽约）”两条旧判据，替换为“现实时间天体时钟固定为岛屿参考时区”（_sim_seconds 与 _abs_unix+IsleAstro.TZ_SECONDS 差<5s 且日出文本按显示时区换算一致）与“切换显示时区天体不移动（纽约）”（|Δsun_alt|<0.05°、|wrap(Δsun_az)|<0.05°），判据更严。
- 结论：**未发现放宽断言、删除测试或关闭日志掩盖问题**（PASS）。详见 `logs/verify/assert_audit.txt`。

## 4. 已知环境限制（沿用历史，本次复核）

1. Godot 子进程写 `C:/Users`（user://）被沙箱阻止：日志/配置可能出现 `ERROR: Failed to open 'user://...'`（数量 12 左右），不影响测试判定，但每次运行需记录条数。
2. `--shots`/`--perf` 自动化路径中 `_apply_resolution` 跳过（历史 1920×1080 请求实际 1600×900）；本次以日志 `[SHOT] WxH` / `[PERF] begin viewport=` 实测值为准。
3. 退出期 RID/ObjectDB 泄漏告警属关闭清理顺序（lifecycle 任务分类），不作为功能失败，但如实记录。
4. probe_astro_xcheck_t7 每行 RAW 输出前会打印一条引擎 ERROR `String formatting error: unsupported format character.`（probe 自身格式化 bug，684 条，纯 cosmetic；probe 自身 SUMMARY 仍 PASS，astro 侧 probe_t7.log 同样存在），不属被测工程错误。
5. 窗口批执行时若 release/verify-visual 也在用 GPU：按 Lead 统一排程，perf 需独占（本次按 Lead 指示执行）。
6. `--quality N` 在自动化 `--perf` 下无效（场景采样恒为默认 q2）：`main.gd:246-251` 的覆盖被 `main.gd:255` `_apply_user_settings(false)` → `main.gd:3253` 重置；属测试工具路径缺陷，不影响玩家/渲染。五档数据以 `--perf` 自带循环为准（本次未修改代码，按「只报告」处理）。

## 5. 复现命令汇总（本次实际执行）

```bash
EXE="D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe"
PROJ="D:/休闲小岛幻境/游戏工程"
LOG="D:/休闲小岛幻境/开发产物/logs/verify"
OUT="D:/休闲小岛幻境/开发产物/shots6/verify"

# 0) 记录冻结点（本次：HEAD 55a8d73，tag freeze-p6close-20261021_0515；基线 8f80b13）
git -C "$PROJ" log -1 --format=%H
git -C "$PROJ" tag --points-at HEAD

# 1) selftest：headless（53 项）与窗口（55 项）
"$EXE" --headless --path "$PROJ" -- --selftest > "$LOG/selftest_headless.log" 2>&1
"$EXE" --path "$PROJ" --resolution 1600x900 -- --selftest > "$LOG/selftest_window.log" 2>&1

# 2) headless 探针（16 项，批量脚本逐个记录 exit code）
bash "$LOG/run_headless_suite.sh"

# 3) 窗口批
"$EXE" --path "$PROJ" --resolution 1600x900 -- --shots > "$LOG/shots.log" 2>&1
"$EXE" --path "$PROJ" --resolution 1600x900 -- --transition > "$LOG/transition.log" 2>&1
bash "$LOG/run_window_suite.sh" quality6   # 同 ghost6 / ao_visual / ao_perf

# 4) perf（独占窗口；先 tasklist 确认无其他 Godot 进程）
"$EXE" --path "$PROJ" --resolution 1920x1080 -- --perf > "$LOG/perf.log" 2>&1

# 5) 干净启动 + 正常退出
"$EXE" --headless --path "$PROJ" --quit-after 600 > "$LOG/boot_exit_headless.log" 2>&1
"$EXE" --path "$PROJ" --resolution 1600x900 --quit-after 600 > "$LOG/boot_exit_window.log" 2>&1

# 6) 测试真实性审计（只读）
git -C "$PROJ" diff baseline-p6close-20261020..freeze-p6close-20261021_0515 -- scripts tools > "$LOG/audit_full.diff"
```

- 截图归集：`--shots` 固定写 `开发产物/shots/`（代码常量 SHOTS_DIR），本次按日志名单归集到 `shots6/verify/shots/`；`--transition` 同理归集 `shots6/verify/transition/`；窗口探针写 `shots6/verify/{quality,ghost}`；`probe_ao_visual_t7` 固定写 `开发产物/shots6/ao/`。
- 结果解析：`--selftest` 看 `[TEST] RESULT` 行；探针看各自 SUMMARY/RESULT 行 + exit code；`--shots` 看 `[SHOT]` 行数与 PNG 数；`--perf` 看 `[PERF]` 行（判定标准见 §2）。
- 证据索引（机器可读）：`bash logs/verify/parse_results.sh` 生成 `logs/verify/summary.tsv`（每项：log / exit / 关键结果行 / 退出期泄漏计数）。
