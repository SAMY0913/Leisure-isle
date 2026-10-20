# P6 发布包与音频资源处理记录（P6_RELEASE_PACKAGING）

> 负责人：release（task-2）。记录任务 A（sounds/ 审计归档）、任务 B（发布包剥离 addons/godot_ai）、
> 任务 C（干净目录启动与资源完整性验收）的实测过程、证据与复现命令。
> 状态：试导出与 headless 验收已完成；最终发布导出/覆盖 `发布/`、窗口冒烟待 Lead 广播 FREEZE 后执行（见 §6）。

## 0. 结论摘要

| 项目 | 结果 |
| --- | --- |
| sounds/ 早期录音 | 4 文件 47.9 MB 全局零引用 → 已归档到 `开发产物/archive/sounds_legacy/`，导入告警消除，发布包不再包含 sounds/ |
| addons/godot_ai | `export_presets.cfg` 排除整目录后发布包不含任何 addon 资源；project.godot 的 autoload 由 addon 导出插件在导出时自动剥离，保留不影响发布包 |
| 试导出包体积 | 122,950,336 B（旧发布）→ 116,767,872 B（P6 试导出 trial2），减少 6,182,464 B（-5.03%） |
| 干净目录启动（headless） | `--headless -- --selftest` → `[TEST] RESULT 53/53 passed` |
| 字体/中文/音频完整性 | 包内 `res://fonts/simhei.ttf` 可加载（FontFile，28522 字符，含 休/闲/中）；11/11 音频全部可加载且时长 > 0；isle.tscn 可实例化；4 个着色器可加载 |
| 退出码（既有问题） | 导出 exe 自动化 selftest 跑完后进程退出码 `-1073740940 (0xC0000374 heap corruption)`；旧发布 exe 同样复现；普通 `--headless --quit` 退出码 0（详见 §5.3） |

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
"D:\休闲小岛幻境\引擎\Godot_v4.7.2-stable_win64_console.exe" --headless --path "D:\休闲小岛幻境\游戏工程" --export-release "Windows Desktop" "D:\休闲小岛幻境\开发产物\release_verify\p6_20261020\isle_p6.exe" --verbose > "D:\休闲小岛幻境\开发产物\logs\release\20_final_export.log" 2>&1
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
  "D:/休闲小岛幻境/开发产物/release_verify/p6_20261020/isle_p6.exe" --verbose \
  > 开发产物/logs/release/20_final_export.log 2>&1
```

注：`export_presets.cfg` 里的 `export_path` 是编辑器导出按钮用的；命令行导出以参数中的输出路径为准。

### 2.3 导出后校验命令

```bash
# 1) 干净目录 selftest（目录里只放 exe）
cd 开发产物/release_verify/p6_20261020
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

### 4.3 包内容与体积（试导出 trial2，代码快照 2026-10-20 23:16）

- 试导出 exe：`开发产物/release_verify/trial2/isle_trial2.exe`
  - 大小 116,767,872 B；sha256 `854bf2212a99123978240a4076790b89d984c66d32cb2db50c8cdfdfc22e3240`
- savepack 清单（`11_trial_export_tmpfix.log`）：79 个文件
  scripts 36 / .godot 16 / audio 11 / shaders 10 / icon.ico 2 / project.binary 1 / isle.tscn.remap 1 / fonts 1 / art 1；
  **addons=0、sounds=0、tools=0、docs=0、shots=0**
- 独立包校验（`13_pack_inspect_trial2.log`）：
  `PCK_MAGIC_AT=109128192 fmt=4 ver=4.7.2 flags=2 file_base=112`、`LOAD_PACK_OK=true`、
  `RES_ADDONS_DIR=false`、`RES_SOUNDS_DIR=false`、`RES_TOOLS_DIR=false`、`RES_DOCS_DIR=false`、
  `RES_SCRIPTS_DIR=true`、`RES_FONTS_DIR=true`、`PROJECT_BINARY_MAGIC=ECFG`、`PB_HAS_MCP_GAME_HELPER=false`
- 体积对比：

| 版本 | 大小 (B) | 说明 |
| --- | --- | --- |
| 旧发布 `发布/休闲小岛幻境.exe` | 122,950,336 | sha256 e2a9d242…（P6 前） |
| P6 试导出 trial2 | 116,767,872 | -6,182,464 B（-5.03%） |

- 既有告警（非本次引入，历史 `reorg_export.log` 同样存在）：图标缺尺寸 16/48/64/128/256、`icon.ico` 无效；
  exe 正常生成并可运行，属 P6 前既有资源问题，未在本次处理范围。

## 5. 任务 C：干净目录启动与资源验收

### 5.1 干净目录 headless selftest

目录 `开发产物/release_verify/trial2_clean/`（仅放 exe），执行 `./isle_trial2.exe --headless -- --selftest`：

- 结果：`[TEST] RESULT 53/53 passed`（与源码运行一致）
- 证据：`开发产物/release_verify/crash_evidence/trial2_selftest.stdout.log`、
  `开发产物/logs/release/12_source_selftest.log`（源码同条件 53/53、退出码 0）

### 5.2 字体/中文/音频/场景/着色器完整性（`14_res_inspect_trial2.log`）

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

注：`--headless selftest` 不渲染画面；**窗口模式实际渲染冒烟在 FREEZE 后执行**（见 §6 step 6）。

### 5.3 退出码（既有问题，复现材料）

同一 PowerShell `Start-Process -Wait -PassThru` 采集（`crash_evidence/exit_codes.txt`）：

| 对象 | 命令 | 结果 | 退出码 |
| --- | --- | --- | --- |
| P6 试导出 exe | `--headless --quit` | 正常 | 0 |
| P6 试导出 exe | `--headless -- --selftest` | 53/53 passed（连续 2 次一致） | **-1073740940 (0xC0000374)** |
| 旧发布 exe | `--headless --quit` | 正常 | 0 |
| 旧发布 exe | `--headless -- --selftest` | 44/46 passed（2 项为 user:// 不可写导致的设置持久化失败） | **-1073740940 (0xC0000374)** |
| 源码工程 | `--headless -- --selftest` | 53/53 passed | 0 |

- 崩溃发生在 selftest 结束、进程退出阶段；stdout 已完整打印 `RESULT`，stderr 无 `ObjectDB instances leaked` 行
  （即退出清理报告尚未输出即崩溃）。
- `--quit` 运行 stderr 可见 `WARNING: 8 ObjectDB instances were leaked at exit`（lifecycle 正在修复的泄漏项）。
- 结论：**该退出码异常为既有问题（旧发布 exe 同样复现），不是 P6 打包引入**；详细材料：
  - `开发产物/release_verify/crash_evidence/exit_codes.txt`
  - `trial2_quit.stdout/stderr.log`、`trial2_selftest.stdout/stderr.log`、`trial2_selftest_run2.*`
  - `old_quit.*`、`old_selftest.*`
  - 已同步 lifecycle；待其退出期修复后，用最终代码重新导出复测并更新本节。

## 6. 最终发布流程（FREEZE 后）

1. 确认无其他 teammate 在跑窗口 Godot：`tasklist | findstr -i godot`（导出/窗口冒烟前各查一次）。
2. 按 §2.2 命令导出到 `开发产物/release_verify/p6_20261020/isle_p6.exe`（**不要直接覆盖 `发布/`**），保留
   `20_final_export.log`；检查日志无 `project.binary` 错误、无 addon/sounds 条目。
3. 干净目录 `--headless -- --selftest`，要求 53/53（记日志 `21_final_selftest.log`）。
4. 跑 §2.3 的两个校验脚本（包内容 + 字体/音频完整性），要求 `RES_ADDONS_DIR=false`、`AUDIO_OK=11/11`。
5. 复制 `isle_p6.exe` → `发布/休闲小岛幻境.exe` 与 `构建输出/休闲小岛幻境.exe`，核对两处 sha256 一致
   （旧版备份已在 `开发产物/backup/release_pre_p6close/休闲小岛幻境_20261020_2045.exe`）。
6. 窗口模式冒烟（需 Lead 协调 GPU 独占）：干净目录启动约 10–20 s，取截图/日志，确认无渲染/资源/脚本错误后退出，
   退出后 tasklist 复查无残留 Godot 进程；记录 `22_window_smoke.log` 与截图路径。
7. 更新本文件 §0/§6 的最终 sha256/体积/日志路径；提交自己 scope 的文件（`export_presets.cfg`、`sounds/` 删除、
   本文件），向 Lead 报 commit hash。

## 7. 证据与文件索引

| 用途 | 路径 |
| --- | --- |
| 试导出日志（失败，未设 TMP） | `开发产物/logs/release/10_trial_export.log` |
| 试导出日志（TMP 修复后） | `开发产物/logs/release/11_trial_export_tmpfix.log` |
| 源码 selftest | `开发产物/logs/release/12_source_selftest.log` |
| 嵌入包内容校验 | `开发产物/logs/release/13_pack_inspect_trial2.log` |
| 资源完整性校验 | `开发产物/logs/release/14_res_inspect_trial2.log` |
| 导入告警（前/后） | `开发产物/logs/release/01_import_baseline.log`、`02_import_after_sounds_archive.log` |
| 退出码证据 | `开发产物/release_verify/crash_evidence/` |
| 试导出 exe | `开发产物/release_verify/trial2/isle_trial2.exe`（116,767,872 B，sha256 854bf221…） |
| 归档音频 | `开发产物/archive/sounds_legacy/`（含 SHA256SUMS_before_move.txt） |
| 旧发布备份 | `开发产物/backup/release_pre_p6close/休闲小岛幻境_20261020_2045.exe` |

## 8. 已知问题与限制

1. **导出 exe 自动化 selftest 退出码 0xC0000374**：既有问题（旧发布 exe 同现），见 §5.3；详细材料已交 lifecycle。
2. 本机 Godot 无法写 user://，所有自动化日志固定带 2–3 条 user:// 环境噪声 ERROR，不代表发布包缺陷；发布包在
   正常用户机器上 user:// 可写。
3. 图标告警（icon.ico 缺多尺寸）为 P6 前既有问题，不在本次处理范围。
4. headless selftest 不能证明窗口渲染；窗口冒烟待 FREEZE 后执行（§6 step 6）。
