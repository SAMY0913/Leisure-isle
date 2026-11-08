# P6 发布包与音频资源处理记录（P6_RELEASE_PACKAGING）

> 负责人：release（task-2）。记录任务 A（sounds/ 审计归档）、任务 B（发布包剥离 addons/godot_ai）、
> 任务 C（干净目录启动与资源完整性验收）的实测过程、证据与复现命令。
> 状态：**已完成并发布**。FREEZE（commit 55a8d73，tag `freeze-p6close-20261021_0515`）后完成正式导出、headless
> 验收、退出码矩阵、窗口自动化验收（55/55 + 61 + 13 张）、覆盖 `发布/` 与 `构建输出/`，并在发布位置复测
> 可执行性（见 §5.4、§5.5、§6）。发布构建 HEAD：导出时 **6ac049e**（其后提交均为 docs/test-only）；
> 发布字节与 freeze 55a8d73 构建**完全一致**（sha256 `b3b4e4ab…`）。

## 0. 结论摘要

| 项目 | 结果 |
| --- | --- |
| sounds/ 早期录音 | 4 文件 47.9 MB 全局零引用 → 已归档到 `开发产物/archive/sounds_legacy/`，导入告警消除，发布包不再包含 sounds/ |
| addons/godot_ai | `export_presets.cfg` 排除整目录后发布包不含任何 addon 资源；project.godot 的 autoload 由 addon 导出插件在导出时自动剥离，保留不影响发布包 |
| 最终发布包体积 | 122,950,336 B（旧发布）→ **116,768,848 B**，减少 6,181,488 B（**-5.03%**）；sha256 `b3b4e4ab492b471da0472432749c9ac9faea225700443806389d803fbd9684f8`。已覆盖 `发布/`、`构建输出/`、`开发产物/release_verify/p6_20261021_final/` **三处完全一致**（构建 HEAD=6ac049e，字节等同 freeze 55a8d73） |
| 包内容 | 79 文件（scripts 36 / .godot 16 / audio 11 / shaders 10 / icon 2 / project.binary 1 / isle.tscn.remap 1 / fonts 1 / art 1）；**addons/sounds/tools/docs/shots 均 0 条**；包内 `project.binary` 无 `_mcp_game_helper` |
| 干净目录启动（headless） | `--headless -- --selftest` → `[TEST] RESULT 53/53 passed`，真实退出码 0（连跑 2 次一致） |
| 字体/中文/音频完整性 | 包内 `res://fonts/simhei.ttf` 可加载（FontFile，28522 字符，含 休/闲/中）；11/11 音频全部可加载且时长 > 0；isle.tscn 可加载且可实例化；4 个着色器可加载 |
| 退出码 | FREEZE 版 headless 矩阵：selftest×2 / perf / `--quit` **全部 EXIT=0，0xC0000374 未复现**（修复前 trial2/旧发布曾复现，见 §5.3 历史表） |
| 窗口自动化验收 | Lead m00549 方案（不做鼠标注入）：窗口 `--selftest` **55/55 passed（exit 0，31.2s）**、`--shots` **61 张**、`--transition` **13 张**，`RESULT=ALL_PASS`（§5.4） |
| 发布位置可执行性 | 对 `发布/休闲小岛幻境.exe`（最终交付字节）实测：`--headless --quit` **exit 0**；`--headless -- --selftest` **53/53 passed，exit 0**（§5.5） |
| 发布包画面复核 | verify-visual 对 61+13 张 EXE 截图逐张程序化+人工复核：与工程内同名图灰度相关 median 0.9932、无黑帧/白帧、无 P0/P1（commit 7a5b488） |

## 1. 环境与版本

- 引擎：`D:\休闲小岛幻境\引擎\Godot_v4.7.2-stable_win64_console.exe`（Godot 4.7.2.stable.official.ed1daf0bf）
- 工程：`D:\休闲小岛幻境\游戏工程`（主场景 `res://isle.tscn`，Forward+，1440x900）
- 导出预设：`Windows Desktop`，`binary_format/embed_pck=true`（PCK 嵌入 exe）
- 本机限制：Godot 子进程**无法写 `C:/Users/Administrator/AppData/**`**（`user://` 与系统临时目录均不可写）。因此：
  - 自动化运行日志里固定出现 3 条环境噪声 ERROR（`user://logs` 打不开 ×2、根证书读取失败 ×1），与发布包无关；
  - **导出必须把 TMP/TEMP 指到工作区可写目录**，否则 project.binary 写系统 temp 失败、包损坏（见 §2）。

## 2. 导出必读：TMP/TEMP 必须指向可写目录

### 2.1 不设置的后果（实测）

不设置 TMP/TEMP 时导出日志 `开发产物/logs/release/10_trial_export.log` 出现：

```
ERROR: Couldn't save project.binary at 'C:/Users/Administrator/AppData/Local/Temp/tmpproject.binary'.
   at: save (core/config/project_settings.cpp:1080)
```

产物 exe 启动即报（`trial1_selftest.log`）：

```
ERROR: Corrupted header in binary project.binary (not ECFG).
   at: _load_settings_binary (core/config/project_settings.cpp:918)
ERROR: Couldn't load file 'res://project.binary', error code 16.
ERROR: Couldn't load project data at path ".". Is the .pck file missing?
```

### 2.2 正确命令（Windows cmd / bash 均可用）

先建可写临时目录，再导出（`--verbose` 保留 savepack 全清单，便于核对包内容）：

```bat
:: cmd
cd /d D:\休闲小岛幻境
mkdir D:\休闲小岛幻境\开发产物\release_verify\tmpdir 2>nul
set TMP=D:\休闲小岛幻境\开发产物\release_verify\tmpdir
set TEMP=%TMP%
"D:\休闲小岛幻境\引擎\Godot_v4.7.2-stable_win64_console.exe" --headless --path "D:\休闲小岛幻境\游戏工程" --export-release "Windows Desktop" "D:\休闲小岛幻境\开发产物\release_verify\p6_20261021_final\isle_p6.exe" --verbose > "D:\休闲小岛幻境\开发产物\logs\release\20_final_export.log" 2>&1
echo EXIT=%ERRORLEVEL%
```

```bash
# bash（等价）
cd /d/休闲小岛幻境
mkdir -p 开发产物/release_verify/tmpdir
TMP="D:/休闲小岛幻境/开发产物/release_verify/tmpdir" \
TEMP="D:/休闲小岛幻境/开发产物/release_verify/tmpdir" \
"D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe" --headless \
  --path "D:/休闲小岛幻境/游戏工程" --export-release "Windows Desktop" \
  "D:/休闲小岛幻境/开发产物/release_verify/p6_20261021_final/isle_p6.exe" --verbose \
  > 开发产物/logs/release/20_final_export.log 2>&1
```

注：`export_presets.cfg` 里的 `export_path` 是编辑器导出按钮用的；命令行导出以参数中的输出路径为准。

### 2.3 导出后校验命令

```bash
# 1) 干净目录 selftest（目录里只放 exe）
cd 开发产物/release_verify/p6_20261021_final
./isle_p6.exe --headless -- --selftest

# 2) 嵌入 PCK 内容校验（脚本加载 pack 后检查目录/项目配置，输出见 13_pack_inspect_*.log）
TMP=D:/休闲小岛幻境/开发产物/release_verify/tmpdir TEMP=D:/休闲小岛幻境/开发产物/release_verify/tmpdir \
  D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe --headless \
  --path D:/休闲小岛幻境/开发产物/release_verify/probe_project \
  --script res://inspect_pack.gd

# 3) 字体/中文/音频/场景/着色器完整性（输出见 14_res_inspect_*.log）
TMP=D:/休闲小岛幻境/开发产物/release_verify/tmpdir TEMP=D:/休闲小岛幻境/开发产物/release_verify/tmpdir \
  D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe --headless \
  --path D:/休闲小岛幻境/开发产物/release_verify/probe_project \
  --script res://inspect_resources.gd -- <导出exe绝对路径>
```

## 3. 任务 A：sounds/ 审计与归档

### 3.1 4 个早期录音（归档前实测）

| 文件 | 大小 (B) | 格式 | Godot 导入 | uid |
| --- | --- | --- | --- | --- |
| sea-waves-on-a-rocky-shore-1190.wav | 21,359,622 | PCM 16-bit stereo 44100 | 正常 | uid://dxgncaa68wf78 |
| windy-sea-loop-.wav | 5,361,358 | PCM 16-bit stereo | 正常 | uid://2hfkygtq4k7t |
| 海浪声.wav | 20,600,780 | WAVE_FORMAT_EXTENSIBLE (0xFFFE) 24-bit stereo 44100 | **失败**（非 PCM 不支持） | uid://0gd8kfg3hnl8 |
| 鸟叫声.WAV | 1,828,102 | PCM 16-bit stereo | 正常 | uid://sfwfoipvu6md |

导入告警实测（归档前，`开发产物/logs/release/01_import_baseline.log`）：

```
ERROR: Format not supported for WAVE file (not PCM). Save WAVE files as uncompressed PCM or IEEE float instead.
   at: load_from_buffer (scene/resources/audio_stream_wav.cpp:738)
ERROR: Can't save empty resource to path 'res://.godot/imported/海浪声.wav-3e4f0c26447a6175d2050b4f057945af.sample'.
```

### 3.2 引用复核（全局，结论：零引用）

复核范围：工程内全部 `*.gd / *.tscn / *.tres / *.cfg / *.godot / *.shader / *.json / *.md`，含
scripts/、shaders/、tools/、docs/、addons/ 自身、project.godot、export_presets.cfg、.godot/ 缓存；
并检查动态拼接 `res://sounds/`、目录遍历加载、AudioStream 资源路径。结果：除 4 个 `.wav.import`
自身与 `.godot` 编辑器缓存条目外，**没有任何运行时引用**；历史导出 savepack 中的 sounds 条目来自
`export_filter="all_resources"` 的资源收集，不是被引用。

因此按方案整体归档（保留原文件名），并清理 `.godot/imported` 中对应残留（4 组 md5/sample），
同时更新 `filesystem_cache10`/`uid_cache.bin`（headless 导入后自动刷新，实测无 sounds 条目）。

- 归档目录：`开发产物/archive/sounds_legacy/`（4 个 wav + 4 个 .import，保留原文件名）
- 哈希清单：`开发产物/archive/sounds_legacy/SHA256SUMS_before_move.txt`
- 可回溯性：git tag `baseline-p6close-20261020`（commit 8f80b13）仍保留原文件，可随时恢复

### 3.3 归档后复测

`开发产物/logs/release/02_import_after_sounds_archive.log`：headless 导入/启动 EXIT=0，
**无任何 wav/sounds/海浪 相关 ERROR**，只剩 3 条环境噪声 ERROR（user:// 不可写、根证书）。

## 4. 任务 B：发布包剥离 addons/godot_ai

### 4.1 改动（唯一修改文件：`游戏工程/export_presets.cfg:11`）

```diff
-exclude_filter="shots/*, refshots/*, logs/*, tools/*, build/*, smoke_test.tscn, addons/godot_ai/clients/*, addons/godot_ai/handlers/*, addons/godot_ai/dock_panels/*, addons/godot_ai/export/*, addons/godot_ai/debugger/*, addons/godot_ai/testing/*, addons/godot_ai/custom_tools/*, addons/godot_ai/*.md, *.md, game_stdout.log, game_stderr.log, .game_pid, %SystemDrive%/*"
+exclude_filter="shots/*, refshots/*, logs/*, tools/*, build/*, smoke_test.tscn, addons/godot_ai/*, *.md, game_stdout.log, game_stderr.log, .game_pid, %SystemDrive%/*"
```

原过滤器只排了 addon 的部分子目录，`addons/godot_ai/` 根目录 `.gd`、`utils/`、`runtime/` 等仍会进包；
改为整目录排除。**不删除**编辑器插件文件，开发环境（编辑器插件/MCP 桥）不受影响。

### 4.2 autoload 处理（project.godot 保持不动）

- `project.godot` 的 `[autoload] _mcp_game_helper="*res://addons/godot_ai/runtime/game_helper.gd"` 由插件
  `addons/godot_ai/plugin.gd` 的 `_ensure_game_helper_autoload()` 在编辑器启动时自动注册/写回；
  删除后编辑器再开又会写回，且开发期 MCP 依赖它，故保留。
- 导出时 addon 的导出插件 `addons/godot_ai/export/mcp_export_plugin.gd` 会在 `_export_begin()` 把
  `autoload/_mcp_game_helper` 临时置空、`_export_end()` 恢复，导出日志实测（`11_trial_export_tmpfix.log:43`）：

```
MCP | export: stripping autoload/_mcp_game_helper from the exported pack (restored in the editor after export)
```

- 独立校验（`13_pack_inspect_trial2.log`）：包内 `project.binary` 中 `_mcp_game_helper` / `addons/godot_ai`
  均不存在；游戏脚本/场景对该 autoload 零引用。**结论：保留 project.godot 的 autoload 不影响发布包。**

### 4.3 包内容与体积（FREEZE 正式导出，commit 55a8d73）

- 正式导出 exe：`开发产物/release_verify/p6_20261021_final/isle_p6.exe`
  - 大小 **116,768,848 B**；sha256 `b3b4e4ab492b471da0472432749c9ac9faea225700443806389d803fbd9684f8`
  - 导出日志 `20_final_export.log`（EXPORT_EXIT=0，含 TMP/TEMP 指向工作区）
- savepack 清单（`20_final_export.log` 提取，`20_final_savepack_list.txt`）：79 个文件
  scripts 36 / .godot 16 / audio 11 / shaders 10 / icon.ico 2 / project.binary 1 / isle.tscn.remap 1 / fonts 1 / art 1；
  **addons=0、sounds=0、tools=0、docs=0、shots=0**（脚本逐条断言，命中即 exit 1）
- 独立包校验（`13_pack_inspect_final.log`）：
  `PCK_MAGIC_AT=109128192 fmt=4 ver=4.7.2 flags=2 file_base=112`、`LOAD_PACK_OK=true`、
  `RES_ADDONS_DIR=false`、`RES_SOUNDS_DIR=false`、`RES_TOOLS_DIR=false`、`RES_DOCS_DIR=false`、
  `RES_SCRIPTS_DIR=true`、`RES_FONTS_DIR=true`、`PROJECT_BINARY_MAGIC=ECFG`、`PB_HAS_MCP_GAME_HELPER=false`
- 体积对比：

| 版本 | 大小 (B) | sha256 前缀 | 说明 |
| --- | --- | --- | --- |
| 旧发布 `发布/休闲小岛幻境.exe` | 122,950,336 | `e2a9d242` | P6 前（备份 `开发产物/backup/release_pre_p6close/`） |
| P6 试导出 trial2（历史） | 116,767,872 | `854bf221` | 验证过滤方案时产物（2026-10-20 23:16） |
| **P6 正式导出（FREEZE）** | **116,768,848** | **`b3b4e4ab`** | -6,181,488 B（**-5.03%**） |

> 历史试导出 trial2 的 savepack/包校验证据保留在 `11_trial_export_tmpfix.log`、`13_pack_inspect_trial2.log`；
> 正式导出与 trial2 的清单结构一致（仅代码变化导致字节数 +1,024 B）。

**FREEZE 后 HEAD 漂移的复核（实测）**：FREEZE tag 55a8d73 之后又有 5 笔提交（b56dc88 test-only、
037cc4c docs、3ab7d9a docs、6ac049e docs、7a5b488 docs，均不在导出范围）。为确认发布字节不受影响，
分别在 HEAD=3ab7d9a 与 HEAD=**6ac049e** 重新执行完整导出管线（`final_run3_console.log`、`final_run4_copy_console.log`）：

| 导出时 HEAD | 大小 | sha256 | savepack 清单 |
| --- | --- | --- | --- |
| 55a8d73（freeze） | 116,768,848 | `b3b4e4ab…` | 79 行，sha256 `b8cd0996…` |
| 3ab7d9a（重导出 1） | 116,768,848 | `b3b4e4ab…` | diff=0（与 freeze 清单完全一致） |
| **6ac049e（重导出 2 = 发布构建）** | **116,768,848** | **`b3b4e4ab…`** | diff=0 |

结论：后置 docs/test 提交**未改变发布字节**；报告以“发布构建 HEAD=6ac049e，内容等同 freeze 55a8d73”记录。

- 既有告警（非本次引入，历史 `reorg_export.log` 同样存在）：图标缺尺寸 16/48/64/128/256、`icon.ico` 无效；
  exe 正常生成并可运行，属 P6 前既有资源问题，未在本次处理范围。

## 5. 任务 C：干净目录启动与资源验收

### 5.1 干净目录 headless selftest（FREEZE 正式包）

目录 `开发产物/release_verify/p6_20261021_final/`（仅放 `isle_p6.exe`），执行
`./isle_p6.exe --headless -- --selftest`：

- 结果：`[TEST] RESULT 53/53 passed`（与源码同条件 53/53 一致）
- 真实退出码：0（`Start-Process -Wait -PassThru`，连跑 2 次一致，见 §5.3）
- 证据：`开发产物/logs/release/21_final_selftest.log`、
  `开发产物/release_verify/crash_evidence/final/selftest_1.stdout.log`、`selftest_2.stdout.log`；
  源码基线 `开发产物/logs/release/12_source_selftest.log`

### 5.2 字体/中文/音频/场景/着色器完整性（FREEZE 正式包，`14_res_inspect_final.log`）

```
FONT_LOAD path=res://fonts/simhei.ttf class=FontFile
  ZH_CHARS=28522 HAS_XIU=true HAS_XIAN=true HAS_ZHONG=true
AUDIO_FILES=11 ["bird_1.wav.import", ... "wind_loop.wav.import"]
AUDIO_OK=11/11   # bird_1 0.55s / bird_2 0.42s / bird_3 0.45s / door_close 0.70s / door_open 0.90s
                 # fire_crackle 4.0s / night_loop 16.0s / ocean_loop 24.0s / ui_click 0.12s / water_splash 1.1s / wind_loop 16.0s
SCENE_LOAD res://isle.tscn class=PackedScene
SCENE_CAN_INSTANTIATE=true
SHADER_LOAD res://shaders/post_ao.gdshader class=Shader（sea/sky/toon 同）
```

注：`--headless selftest` 不渲染画面；窗口自动化验收方案见 §5.4。

### 5.3 退出码矩阵（FREEZE 正式包：0xC0000374 未复现）

同一 PowerShell `Start-Process -Wait -PassThru` 采集真实退出码（`crash_evidence/final/exit_codes.txt`）：

| 对象（FREEZE 导出 exe，sha256 `b3b4e4ab…`） | 命令 | 结果 | 耗时 | 退出码 |
| --- | --- | --- | --- | --- |
| 正式导出 exe | `--headless -- --selftest`（第 1 次） | `[TEST] RESULT 53/53 passed` | 22.0s | **0** |
| 正式导出 exe | `--headless -- --selftest`（第 2 次） | `[TEST] RESULT 53/53 passed` | 21.8s | **0** |
| 正式导出 exe | `--headless -- --perf` | `[PERF] end` | 44.2s | **0** |
| 正式导出 exe | `--headless --quit` | 正常退出 | 6.4s | **0** |

- **0xC0000374 在 FREEZE 版未复现**（lifecycle 的 FX 退出释放修复 `bd078b0` 已进冻结代码）。
- stderr 仅环境噪声：user://logs 打不开 ×2、根证书 store ×1；另 selftest_2/perf_1 出现
  `WARNING: 4 ObjectDB instances were leaked at exit`（退出期警告，非崩溃；selftest_1/quit 无）。
- 证据：`开发产物/release_verify/crash_evidence/final/exit_codes.txt` 与
  `selftest_1|selftest_2|perf_1|quit` 的 stdout/stderr；控制台 `开发产物/logs/release/final_exit_matrix_console.log`。

历史（修复前，复现材料保留）：

| 对象 | 命令 | 结果 | 退出码 |
| --- | --- | --- | --- |
| P6 试导出 trial2 | `--headless --quit` | 正常 | 0 |
| P6 试导出 trial2 | `--headless -- --selftest` | 53/53 passed（连续 2 次一致） | **-1073740940 (0xC0000374)** |
| 旧发布 exe | `--headless --quit` | 正常 | 0 |
| 旧发布 exe | `--headless -- --selftest` | 44/46 passed（2 项为 user:// 不可写导致的设置持久化失败） | **-1073740940 (0xC0000374)** |
| 源码工程 | `--headless -- --selftest` | 53/53 passed | 0 |

- 历史崩溃发生在 selftest 结束、进程退出阶段；stdout 已完整打印 `RESULT`；trial2 `--quit` stderr 可见
  `WARNING: 8 ObjectDB instances were leaked at exit`。
- 历史证据：`crash_evidence/exit_codes.txt`、`trial2_quit.*`、`trial2_selftest.*`、`trial2_selftest_run2.*`、
  `old_quit.*`、`old_selftest.*`。

### 5.4 窗口自动化验收（Lead m00549 方案，已执行：ALL_PASS）

> 旧版鼠标注入冒烟（`window_smoke.ps1`）因窗口无法置前、输入未生效，Lead 已判定不可作为验收证据；
> 改用导出包内置自动化入口（不依赖窗口焦点、不做输入注入）。

脚本：`开发产物/logs/release/window_auto_smoke.ps1`
（预检无其它 Godot/isle 进程、打印 SIZE/SHA256/HEAD，退出码 0 = 全绿）。

| 步骤 | 命令（exe = `开发产物/release_verify/p6_20261021_final/isle_p6.exe`） | 期望 | 产物 |
| --- | --- | --- | --- |
| ① 窗口 selftest | `isle_p6.exe --resolution 1600x900 -- --selftest` | `[TEST] RESULT 55/55 passed`、exit 0（窗口模式比 headless 多 2 项真实鼠标拖动：设置滑条/时间轴，源码 `scripts/main.gd:2099-2169`） | `window_smoke/auto_selftest.out.log` |
| ② 画面自动化 | `isle_p6.exe --resolution 1600x900 -- --shots` | 61 张 PNG | `window_smoke/final_shots/` |
| ③ 转场自动化 | `isle_p6.exe --resolution 1600x900 -- --transition` | 13 张 PNG（`tr_00`…`tr_12`，源码 `scripts/main.gd:1822-1837`） | `window_smoke/final_transition/` |

- 汇总：`window_smoke/auto_smoke_summary.txt` + `开发产物/logs/release/30_window_auto_smoke.log`
- 截图从 `开发产物/shots/` 按 mtime 快照只归集本轮新写文件（避免历史 166 张图污染）。
- 窗口关闭：Lead 已 PowerShell 手动实测 `CloseMainWindow=True`、`WaitForExit(20s)=True`（正常退出）。
- **实测结果（2026-10-21 00:08–00:10，GPU 独占；EXE sha256 `b3b4e4ab…`，HEAD=3ab7d9a 构建）：**

| 步骤 | 实测结果 | 退出码 | 截图数 | 耗时 |
| --- | --- | --- | --- | --- |
| ① 窗口 selftest | `[TEST] RESULT 55/55 passed`（含 2 项真实鼠标拖动） | **0** | - | 31.2s |
| ② `--shots` | 61 张 PNG（`final_shots/`） | **0** | **61** | 85.7s |
| ③ `--transition` | 13 张 PNG（`final_transition/`） | **0** | **13** | 22.7s |

- 汇总：`RESULT=ALL_PASS`（`window_smoke/auto_smoke_summary.txt`、`30_window_auto_smoke.log`）。
- PNG 实测尺寸 **1600×900**（自动化按逻辑视口截图，而非窗口物理尺寸）；无黑帧/白帧。
- stderr 全部为本机环境噪声，无脚本/资源错误：selftest 96 行 = 91× `_save_to_cache f.is_null()`（user:// 不可写）、
  user:// 日志打不开 ×2、user://screenshots 保存失败 ×1、根证书 ×1、FSR 下采样提示 WARNING ×1；shots 94 行、
  transition 74 行同类。**无 SCRIPT ERROR、无资源缺失、无加载失败。**
- 每步 stdout/stderr：`window_smoke/auto_{selftest,shots,transition}.{out,err}.log`。
- EXE 截图复核（verify-visual，commit 7a5b488）：61+13 张与工程内同名图逐张配对，灰度相关 median 0.9932 /
  min 0.8768；实看 27 张（菜单/设置/六时段/夜景/水面/转场首末帧等），字体中文、布局、渲染与源码版一致，
  无方块字/UI 裁切/黑帧，未发现需补拍问题。

### 5.5 发布位置可执行性冒烟（最终交付字节）

对 `发布/休闲小岛幻境.exe`（复制后，sha256 `b3b4e4ab…`，LastWriteTime 2026-10-21 00:13）执行：

| 命令 | 结果 | 退出码 |
| --- | --- | --- |
| `发布/休闲小岛幻境.exe --headless --quit` | 正常退出 | **0** |
| `发布/休闲小岛幻境.exe --headless -- --selftest` | `[TEST] RESULT 53/53 passed` | **0** |

- stderr 仅已知环境噪声 + `WARNING: 4 ObjectDB instances were leaked at exit`（退出期警告，非崩溃）。
- 证据：`开发产物/logs/release/22_final_location_selftest.out.log` / `.err.log`。

## 6. 最终发布流程（FREEZE 后，实际执行记录）

1. FREEZE 确认：commit **55a8d73**（tag `freeze-p6close-20261021_0515`）；导出/窗口验收前 `tasklist` 确认无其它
   Godot 进程（`godot-ai.exe` 除外）。
2. 一键 headless 管线：`bash 开发产物/logs/release/final_release.sh`（脚本内部设置 TMP/TEMP；导出到
   `开发产物/release_verify/p6_20261021_final/`；清单断言；包校验；资源校验；干净目录 selftest）。
   **已执行**：EXPORT_EXIT=0、79 文件、selftest 53/53、`AUDIO_OK=11/11`。
3. headless 退出码矩阵：`pwsh -File 开发产物/logs/release/final_exit_matrix.ps1` → selftest×2 / perf / quit
   **全部 EXIT=0，0xC0000374 未复现**（§5.3）。
4. 窗口自动化验收（GPU 独占，Lead 广播 GPU_FREE 后执行）：`pwsh -File 开发产物/logs/release/window_auto_smoke.ps1`
   → 窗口 selftest **55/55**、`--shots` **61 张**、`--transition` **13 张**，`RESULT=ALL_PASS`（§5.4）。
   脚本预检只拦“窗口模式”Godot 进程，允许其他 teammate 的 headless 探针并行。
5. 验收全绿后发布（**已于 00:12–00:13 执行**）：`COPY_TO_RELEASE=1 ALLOW_PARALLEL=1 bash 开发产物/logs/release/final_release.sh`
   → 重新导出并复验（EXPORT_EXIT=0、79 文件、selftest 53/53、AUDIO_OK=11/11），覆盖 `发布/休闲小岛幻境.exe` 与
   `构建输出/休闲小岛幻境.exe`；三处 sha256 均为 `b3b4e4ab492b471da0472432749c9ac9faea225700443806389d803fbd9684f8`。
   导出时 HEAD=**6ac049e**（字节与 freeze 55a8d73 完全一致，见 §4.3）。
   旧版备份：`开发产物/backup/release_pre_p6close/休闲小岛幻境_20261020_2045.exe`（sha256 `e2a9d242…`，回滚见 §7 末尾）。
6. 发布位置可执行性复测：对 `发布/休闲小岛幻境.exe` 跑 `--headless --quit`（exit 0）与 `--headless -- --selftest`
   （53/53 passed，exit 0），证据 §5.5。
7. 更新本文件（体积/sha256/窗口结果/日志路径/发布 HEAD）→ `git add docs/P6_RELEASE_PACKAGING.md` 提交
   （`export_presets.cfg`/`sounds/`/首版文档已在 55a8d73 提交）→ 向 Lead 报最终 commit hash。

## 7. 证据与文件索引

| 用途 | 路径 |
| --- | --- |
| 试导出日志（失败，未设 TMP） | `开发产物/logs/release/10_trial_export.log` |
| 试导出日志（TMP 修复后） | `开发产物/logs/release/11_trial_export_tmpfix.log` |
| 正式导出日志（FREEZE） | `开发产物/logs/release/20_final_export.log` |
| 正式导出 savepack 清单 | `开发产物/logs/release/20_final_savepack_list.txt`（79 行） |
| 正式包 headless selftest | `开发产物/logs/release/21_final_selftest.log` |
| 正式包嵌入内容校验 | `开发产物/logs/release/13_pack_inspect_final.log` |
| 正式包资源完整性校验 | `开发产物/logs/release/14_res_inspect_final.log` |
| 源码 selftest 基线 | `开发产物/logs/release/12_source_selftest.log` |
| 导入告警（前/后） | `开发产物/logs/release/01_import_baseline.log`、`02_import_after_sounds_archive.log` |
| headless 退出码矩阵 | `开发产物/release_verify/crash_evidence/final/`（exit_codes.txt + 各例 stdout/stderr） |
| 历史退出码证据（0xC0000374） | `开发产物/release_verify/crash_evidence/` |
| 窗口自动化脚本/汇总/日志 | `开发产物/logs/release/window_auto_smoke.ps1`、`window_smoke/auto_smoke_summary.txt`、`30_window_auto_smoke.log` |
| 窗口截图（--shots / --transition） | `开发产物/release_verify/window_smoke/final_shots/`（61 张）、`final_transition/`（13 张） |
| 窗口每步 stdout/stderr | `开发产物/release_verify/window_smoke/auto_{selftest,shots,transition}.{out,err}.log` |
| 发布位置可执行性冒烟 | `开发产物/logs/release/22_final_location_selftest.out.log` / `.err.log` |
| 发布重建/COPY 控制台 | `开发产物/logs/release/final_run3_console.log`、`final_run4_copy_console.log` |
| 交付字节（三处一致） | `发布/休闲小岛幻境.exe`、`构建输出/休闲小岛幻境.exe`、`开发产物/release_verify/p6_20261021_final/isle_p6.exe`（均 116,768,848 B / `b3b4e4ab…`） |
| 正式导出 exe（构建目录） | `开发产物/release_verify/p6_20261021_final/isle_p6.exe`（116,768,848 B，sha256 `b3b4e4ab…`） |
| 试导出 exe（历史） | `开发产物/release_verify/trial2/isle_trial2.exe`（116,767,872 B，sha256 854bf221…） |
| 归档音频 | `开发产物/archive/sounds_legacy/`（含 SHA256SUMS_before_move.txt） |
| 旧发布备份 | `开发产物/backup/release_pre_p6close/休闲小岛幻境_20261020_2045.exe` |

## 8. 已知问题与限制

1. **导出 exe 自动化 selftest 退出码 0xC0000374**：修复前既有问题（旧发布 exe/trial2 同现），FREEZE 版
   （含 lifecycle FX 退出释放修复 bd078b0）**未复现**，headless 矩阵全部 EXIT=0，见 §5.3；历史复现材料保留。
2. 本机 Godot 无法写 user://，所有自动化日志固定带 2–3 条 user:// 环境噪声 ERROR（含 shader cache
   `_save_to_cache f.is_null()` 警告），不代表发布包缺陷；发布包在正常用户机器上 user:// 可写。
3. 图标告警（icon.ico 缺 16/48/64/128/256 多尺寸、导出日志 "无效的图标文件"）为 P6 前既有问题（历史
   `reorg_export.log` 同样存在），不在本次处理范围，exe 正常生成。
4. 窗口验收不使用鼠标注入：旧 `window_smoke.ps1` 因无法置前输入未生效，已被 Lead m00549 判定不可作为证据；
   现用导出包内置 `--selftest`/`--shots`/`--transition`（§5.4）。窗口关闭由 Lead PowerShell 手动实测
   `CloseMainWindow=True`、`WaitForExit(20s)=True`。
5. 窗口 selftest 分支中 `scripts/main.gd:3443` 不跳过 `_apply_resolution`，窗口物理尺寸会被本机
   `user://settings.cfg`（fullscreen=true / 2560x1390）覆盖；但自动化截图按逻辑视口输出 **1600×900**（实测，
   `--shots`/`--transition` 共 74 张 PNG 均为 1600×900），逻辑视口 1440x900（canvas_items + expand）不变，
   不影响 55 项断言（分辨率项自身用 1280x720 实测并恢复）。
