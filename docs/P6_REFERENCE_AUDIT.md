# P6 全局失效引用审计报告

> 维护：T3 工程卫生（teammate hygiene）。生成时间：2026-10-20 23:3x（Asia/Shanghai）。
> 基线：tag baseline-p6close-20261020（commit 8f80b13）时的工程快照 + 扫描时工作树（含 P6 收尾期间其他同学的改动；已排除 .godot/、.git/、__pycache__/）。
> 原始扫描输出：开发产物/baseline/reference_audit_v3.md、reference_audit.json；扫描脚本：开发产物/baseline/scan_references_v3.py（只读）。

## 1. 结论（TL;DR）

- 扫描 280 个文件（游戏工程全部文本类源码/资源/配置/文档 + 工作区 文档/ 与根 md），提取 900 条静态路径引用，**未解析到目标的 53 条**。
- **项目源码、场景、资源、配置（.gd/.tscn/.tres/.gdshader/.godot/.cfg/.json 与 project.godot）中不存在真正的失效引用**；53 条全部可归入以下无害类别：
  - **运行时生成路径 16 条**（日志/截图/临时配置，运行时才创建，不算失效，不修）。
  - **第三方 addon 内部文本/示例 29 条**（addons/godot_ai 的说明文字与示例路径，导出时被 export_presets 排除，不适用本项目，不修）。
  - **历史记录/归档路径 3 条**（旧阶段报告里的历史日志与已滞后文档互引，标注为历史即可，不补内容）。
  - **前向引用 5 条**（P6_TEST_RESULTS.md 中 verify 将来才会产出的证据日志/截图与 lifecycle 待产出文档，待其产出后自然成立，不补空文件）。
- 实际修复 1 处文档写法错误：游戏工程/docs/P6_RESEARCH_VISUAL.md:156（截图相对路径 `../开发产物/...` 少了工作区层级，实际文件存在，见 §5）。
- uid 一致性：基线 220 个 .uid 全部可映射；孤儿 .uid 仅 1 个（scripts/menu_orig_t1.gd.uid，已归档删除）；.gd 缺 .gd.uid 在基线上为 0；.import 无源文件 0；0 字节文件 0。
- **复核口径（2026-10-20 23:28 提交 705b535 后复跑）**：工作树复跑得 FILES 286 / REFS 1144 / DANGLING 130，比基线快照的 53 条多出的 77 条全部是**文档自引用噪音与队友前向产出**，不是新缺陷：本审计报告自己引用缺失证据路径 65 条、P6_BASELINE.md 引用已归档/删除文件 9 条、P6_TESTING.md 引用运行时输出路径 3 条、P6_TEST_RESULTS.md 前向引用 5 条、历史文档 4 条、新增未跟踪探针 3 条。按**代码/配置口径**（排除 .md，仅 .gd/.tscn/.tres/.gdshader/.godot/.cfg/.json/.import）统计：**未解析 42 条 = addons/godot_ai 第三方 29 条 + 运行时输出路径 12 条 + verify 新探针前向输出 1 条，真实失效 0 条**。

## 2. 扫描方法与复跑方式

```bash
# 依赖：系统 python 3.13（python 命令）；只读扫描，不写工程
python D:/休闲小岛幻境/开发产物/baseline/scan_references_v3.py
# 输出：D:/休闲小岛幻境/开发产物/baseline/reference_audit_v3.md 与 reference_audit.json
```

规则要点：
- 扫描扩展名：.gd/.tscn/.tres/.gdshader/.shader/.godot/.cfg/.json/.md/.import；跳过 .godot/、.git/、__pycache__/。
- 识别模式：res:// 路径、user:// 路径、docs/xxx.md、tools/xxx.gd、开发产物/…、文档/…、游戏工程/…、assets 目录（audio/shaders/fonts/art 下带后缀资源）、uid://XXX、裸路径（工作区相对）。
- 判定「存在」时同时查工作区、游戏工程 与 游戏工程/docs 三个基准目录（文档里的相对路径按引用方目录父级解析）；uid:// 通过工程内 .uid/.tscn/.tres 头部映射；含通配符（* { $ % <>）的条目视为 shell 通配写法，检查通配前的目录/前缀是否存在；动态拼接字符串（如 `"res://" + name`）不产生静态引用、不算缺失。
- 排除项：export_presets.cfg 的 excluded_filter 条目不参与引用判定（tools/*、shots/*、*.md、addons/godot_ai 等在导出包中不存在属预期）。
- 第三方 addons/godot_ai 是 vendored 依赖，其内部文档/示例路径不按本项目资产判定。
- **复跑注意**：扫描器会无差别计入 .md 中的路径文本，因此本审计报告、P6_BASELINE.md、P6_TESTING.md 这类「记录缺失路径的文档」会被算成未解析引用（自引用噪音）；判断项目是否有真实失效引用请用代码/配置口径。可直接执行：

```bash
cd D:/休闲小岛幻境
python 开发产物/baseline/scan_references_v3.py >/dev/null 2>&1
python - <<'PY'
import json
d=json.load(open("开发产物/baseline/reference_audit.json",encoding="utf-8"))
code=[r for r in d["dangling_rows"] if not r["file"].lower().endswith(".md")]
print("code/config dangling:", len(code))
for r in code: print(r["file"], r["line"], r["raw"])
PY
```

2026-10-20 23:28 实测输出为 42 条（明细即 §3.2 与 §3.4 所列 + verify 新探针 1 条前向输出）。

## 3. 失效清单与逐条判定（53 条）

### 3.1 前向引用（5 条，待产出方，不补内容）

| 文件:行 | 引用原文 | 判定 | 说明 |
|---|---|---|---|
| 游戏工程/docs/P6_TEST_RESULTS.md:134 | docs/P6_LIFECYCLE_FINDINGS.md | 前向引用，不修 | lifecycle 队友待产出的退出期 RID/ObjectDB 结论文档；截至 2026-10-20 23:3x 复核仍不存在。产出后即成立。 |
| 游戏工程/docs/P6_TEST_RESULTS.md:48 | 开发产物/logs/verify/selftest_headless.log | 前向引用，不修 | verify 的待跑项证据日志（表中状态仍为 ⏳）；跑完由 verify 生成。 |
| 游戏工程/docs/P6_TEST_RESULTS.md:58 | 开发产物/logs/verify/selftest_window.log | 前向引用，不修 | 同上（窗口自测日志）。 |
| 游戏工程/docs/P6_TEST_RESULTS.md:90 | 开发产物/shots6/verify/quality | 前向引用，不修 | probe_quality6 窗口矩阵的输出目录待 verify 生成。 |
| 游戏工程/docs/P6_TEST_RESULTS.md:91 | 开发产物/shots6/verify/ghost | 前向引用，不修 | probe_ghost6 窗口矩阵输出目录待 verify 生成。 |

处理：**禁止用空文件/占位目录敷衍**；由 verify/lifecycle 实际产出后自然满足。若最终未产出，由 verify 在其报告中把对应行改为「未跑/不适用」。

### 3.2 运行时生成路径（16 条，不算失效，不修）

| 文件:行 | 引用原文 | 判定 | 说明 |
|---|---|---|---|
| 游戏工程/scripts/main.gd:2062 | 开发产物/logs/settings_selftest.cfg | 运行时生成 | selftest 临时配置文件，运行时写入。 |
| 游戏工程/scripts/main.gd:2099 | 开发产物/logs/settings_res_selftest.cfg | 运行时生成 | 同上（res 变体）。 |
| 游戏工程/scripts/main.gd:3722 | res://screenshots（注释） / 开发产物/photos | 受限回退目录 | F2 截图的三级回退：可执行目录→res://screenshots→开发产物/photos；均运行时创建，注释说明用途。 |
| 游戏工程/scripts/main.gd:3726 | res://screenshots | 受限回退目录 | 同上，ProjectSettings.globalize_path。 |
| 游戏工程/scripts/main.gd:3727 | 开发产物/photos | 运行时生成 | 同上。 |
| 游戏工程/scripts/main.gd:3722（out 模式匹配） | 开发产物/photos | 运行时生成 | 同一行注释中的回退目录说明。 |
| 游戏工程/tools/probe_time_p5.gd:446 | res://shots | 探针运行输出 | const UI_SHOT_DIR；UI 截图探针运行时生成，仅在 --ui 模式用。 |
| 文档/docs/P5_AUDIO_NOTES.md:128 | res://logs/audio_main_run.log | 历史文档说明 | 音频事件表落盘路径（历史阶段文档描述；运行时生成）。 |
| 游戏工程/tools/probe_audio6.gd:13 | 开发产物/logs/audio6_persist_probe.cfg | 运行时生成 | 持久化探针临时配置。 |
| 游戏工程/tools/probe_audio6.gd:14 | 开发产物/logs/audio6_legacy_probe.cfg | 运行时生成 | 旧配置迁移探针临时配置。 |
| 游戏工程/tools/probe_color.gd:69 | 开发产物/shots/probe_color.png | 运行时生成 | save_png 输出（窗口探针）。 |
| 游戏工程/tools/probe_outline.gd:40 | 开发产物/shots/probe_outline.png | 运行时生成 | save_png 输出。 |
| 游戏工程/tools/probe_roof.gd:60 | 开发产物/shots/probe_roof.png | 运行时生成 | save_png 输出。 |
| 游戏工程/tools/probe_settings6.gd:39 | 开发产物/logs/probe_settings6.cfg | 运行时生成 | 探针临时配置（本次 T3 实跑已验证会生成）。 |
| 游戏工程/tools/probe_quality_override_t7.gd:8 | 开发产物/logs/probe_quality_override_t7.log | 运行时生成 | verify-visual 新增探针的运行日志路径（头注释）。 |
| 游戏工程/tools/probe_quality_override_t7.gd:14 | 开发产物/logs/probe_quality_override_t7.log | 运行时生成 | 同上（LOG_PATH 常量）。 |

处理：不修。这些是「写路径」而非「读依赖」，运行时按需创建；写死到 开发产物 是 P6 的既定约定（Godot 不写 user://）。

> 行号说明：表中 scripts/main.gd 行号为审计时（基线 tag 8f80b13）口径；lifecycle 对 main.gd 的 P6 改动会让工作树行号偏移（例如复跑时这些引用显示在 3724/3728/3729 行），复核时以 tag 内文件或 grep 关键字为准。

### 3.3 历史记录/归档路径（3 条，标注为历史，不补内容）

| 文件:行 | 引用原文 | 判定 | 说明 |
|---|---|---|---|
| 文档/PHASE4_REPORT.md:501 | res://.godot/imported/海浪声.wav-… | 历史记录 | P4 阶段旧 WAV（非 PCM）导入失败的错误日志引用；.godot 导入缓存本就不可回滚、不修复。已在该报告语境中属历史故障记录。 |
| 文档/PHASE5_REPORT.md:128 | audio/isle_audio | 非实际引用 | 散文里描述 audio/isle_audio 模块目录名，不是可解析资产路径；扫描器误报，不修。 |
| 文档/reference-spec.md:43 | docs/PLAN-ECOSYSTEM.md | 历史归档 | 该文档位于工作区 文档/docs/PLAN-ECOSYSTEM.md（历史阶段规划文档已归档，当前不存在）；原文本身就是「状态仍写实施中，属文档滞后」的批注，属历史记录，不补。 |

处理：不修代码/文档内容；本报告作为「已知历史失真」的登记处。若后续要彻底清理历史文档，需用户确认（删除归档文档属另一件事）。

### 3.4 第三方 addon 内部文本/示例（29 条，不适用，不修）

全部位于 addons/godot_ai/（vendored 编辑器插件，export_presets.cfg 已排除导出）。典型例子：
- 文档互引：docs/steam-capability-directory.md、docs/client-configuration.md、docs/releasing.md、docs/tools/mcp-server.md、docs/users/features/mcp.md、docs/test-run-transport-starvation-plan.md、docs/port-conflicts.md、docs/plugin-architecture.md、docs/v4-migration.md、docs/server-lifecycle.md、docs/self-update.md（该 addon 的仓库侧文档未随插件包分发）。
- 示例/占位资源：res://materials/metal.tres、res://icon.svg、res://override.cfg、res://tests、res://game/arena.gd、res://addons/gdunit4_mcp/plugin.cfg、res://does/not/exist.tres、res://addons/godot_ai/foo.gd、res://addons/.godot_ai_update/…（插件说明/自更新临时目录）。
- 处理：**不修**（第三方文件，不在本项目 write scope；升级插件时由上游维护）。

完整 29 条明细见 开发产物/baseline/reference_audit_v3.md 的 F 表。

## 4. res:// / user:// / docs 等引用总体情况

- res:// 引用全部可解析（除上表 3.2 的运行时输出与 addons/godot_ai 示例）；主场景 isle.tscn 引用的 res://scripts/main.gd（uid://yt2p6age324u）、smoke_test.tscn 引用的 res://scripts/spinner.gd 与 res://art/spinner.tres 均存在。
- user:// 仅出现在 main.gd 历史回退注释与文档说明中；P6 约定不写 user://。
- docs/xxx.md 互引：docs/P6_BASELINE.md、docs/P6_TESTING.md、docs/P6_REFERENCE_AUDIT.md 之间互引在本报告生成时生效；P5 系列历史文档在 工作区 文档/docs/ 下（不在 游戏工程/docs/），其内部互引按相对父级解析可成立，属历史归档。
- 工作区根 md（文档/README.md、项目简介等）引用的 docs/… 指向 文档/docs/，除 §3.3 的 PLAN-ECOSYSTEM 外均可解析。

## 5. 本次实际修复

| 文件:行 | 问题 | 修复 |
|---|---|---|
| 游戏工程/docs/P6_RESEARCH_VISUAL.md:156 | 截图路径写成 `../开发产物/shots6/t3/quality_fixed_q0..q4.png`（相对 游戏工程/docs 解析成 游戏工程/开发产物，不存在；实际文件在工作区 开发产物/shots6/t3/ 下，已复核存在） | 把路径改为工作区绝对写法 `D:/休闲小岛幻境/开发产物/shots6/t3/quality_fixed_q0..q4.png`，与实际文件一致；不改任何数值结论。 |

## 6. uid / import / 空文件一致性检查（基线 tag 8f80b13）

| 检查项 | 结果 |
|---|---|
| uid:// 引用不可解析 | 0 |
| 孤儿 .uid（无对应 .gd/.cs/.gdshader） | 1：scripts/menu_orig_t1.gd.uid（源已删除；已归档删除，见 docs/P6_BASELINE.md §9） |
| .gd 缺 .gd.uid | 基线 0；扫描时工作树 1（tools/probe_quality_override_t7.gd 是 verify-visual 新增未跟踪文件，其 .uid 随之提交即可，不是缺陷） |
| .import 对应源文件缺失 | 0 |
| 0 字节文件 | 0 |

uid 提交策略见 docs/P6_TESTING.md §8（.uid 必须与源文件成对提交，禁止 .gitignore 忽略）。

## 7. 存疑 / 待确认项（需 Lead 或对应 owner 决定）

1. **P6_LIFECYCLE_FINDINGS.md（前向引用）**：lifecycle 是否确定产出？若最终不产出，请 lifecycle 改 P6_TEST_RESULTS.md:134 的表述。
2. **verify 证据日志/截图目录**：verify 尚未跑窗口套件，跑完后路径自洽；T3 不代跑（GPU 独占由 Lead 安排）。
3. **w3.txt**（游戏工程根，2 字节 "hi"，git 跟踪的疑似临时文件）：不在 T3 write scope（根目录非我的 scope），建议由 release/Lead 决定删除并提交。
4. **tscn 中 [ext_resource] path 与 .import 的对应**：已核 0 缺失；若后续新增贴图/音频，记得让 Godot 完成导入再提交，否则导出会缺资源。
5. **历史文档失真**（§3.3 的 PLAN-ECOSYSTEM、PHASE4 导入错误）保持原样，仅在此登记；如用户要求清理历史文档需另行授权。

## 8. 变更记录

| 日期 | 变更 | 作者 |
|---|---|---|
| 2026-10-20 | 新建：扫描器 v3 结果 53 条逐条判定、1 处文档路径修复、uid/import/空文件一致性、存疑项 | T3 hygiene |
