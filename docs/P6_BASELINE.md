# P6 收尾基线清单（baseline-p6close-20261020）

> 维护：T3 工程卫生（teammate hygiene）。生成时间：2026-10-20 23:2x（Asia/Shanghai）。
> 口径说明：本文第 1–4 节是**从 git tag 基线对象与本机系统实测**得到的当前事实；第 5 节是**历史测试结果**（来自 开发产物/logs 与 docs/P6_REPORT.md），已明确标注为历史参考，不等于本次实测。
> 关联文档：[docs/P6_TESTING.md](P6_TESTING.md)（CLI/探针一键复现）、[docs/P6_REFERENCE_AUDIT.md](P6_REFERENCE_AUDIT.md)（全局失效引用审计与归档清单）、[docs/P6_REPORT.md](P6_REPORT.md)（P6 技术报告）、[docs/P6_TEST_RESULTS.md](P6_TEST_RESULTS.md)（T4 验证结果，由 verify 维护）。

## 1. 仓库快照

| 项 | 值 |
|---|---|
| 仓库根 | D:/休闲小岛幻境/游戏工程（git 目录 D:/休闲小岛幻境/游戏工程/.git） |
| 分支 | p6-closeout |
| tag | baseline-p6close-20261020 |
| commit（完整） | 8f80b139d7f38c98df969b316c59d2bd96ac7871 |
| commit（短） | 8f80b13 |
| commit 时间 | 2026-10-20 23:05:31 +0800 |
| commit 说明 | chore: P6 收尾基线（修改前快照） |
| 跟踪文件数 | 544 |
| 所有 blob 体积之和 | 69,802,088 字节（约 66.6 MiB） |
| 行数口径 A（任务书采用） | **92,689 行**（非二进制文件行数） |
| 行数口径 B | 92,440 行（303 个纯文本扩展文件） |
| .uid 文件数/行数 | 220 / 220 |
| 文本 + .uid | 92,660 行 |

**行数口径说明**：92,689 来自基线统计脚本 `开发产物/baseline/count_stats_tag.py` 输出的 NONBINARY_LINES —— 对 tag 中每个非二进制 blob 按「换行符个数，末尾无换行则补 1」计数；它等于「纯文本扩展 92,440 + .uid 220 + 其余非二进制小文件（.gitignore、LICENSE 等无文本扩展名的文件）29 行」。另有口径 B「92,440」只统计 .gd/.tscn/.tres/.godot/.cfg/.json/.md/.gdshader/.mjs/.py/.ps1/.bat/.import/.txt 这些文本扩展名，不含 .uid。两者是同一基线的不同统计口径，引用时请写明口径，不要混用。

### 1.1 文件构成（tag 基线实测，544 个跟踪文件）

按目录（git ls-tree -r -z 精确计数）：

| 目录 | 文件数 | 说明 |
|---|---|---|
| addons/ | 313 | godot-ai MCP 插件（第三方，导出时排除） |
| tools/ | 131 | 探针、构建/分析脚本、base_env.json、rcedit |
| scripts/ | 38 | 18 个 .gd + 18 个 .gd.uid + menusplice 报告与 menu_orig uid（P6 归档后已移出，见第 9 节） |
| audio/ | 22 | 11 个 wav + 11 个 .import |
| shaders/ | 19 | 10 个 .gdshader + 9 个 .gdshader.uid |
| sounds/ | 8 | 4 个 wav + 4 个 .import |
| docs/ | 3 | P6_ASTRO_ACCURACY.md、P6_REPORT.md、P6_RESEARCH_VISUAL.md（P6_TEST_RESULTS.md 由 verify 于基线后新增） |
| fonts/ | 2 | simhei.ttf + .import |
| art/ | 1 | spinner.tres |
| 仓库根 | 7 | .gitignore、export_presets.cfg、icon.ico、isle.tscn、project.godot、smoke_test.tscn、w3.txt |

按扩展名：.gd 229、.uid 220、.py 17、.import 16、.wav 15、.gdshader 10、.tscn 8、.ps1 7、.md 4、.mjs 3、.txt 2、.json 2、.cfg 2，其余 .ttf/.tres/.pyc/.ico/.godot/.gitignore/.exe/.bat/LICENSE 各 1。

> 备注：仓库根有 w3.txt（2 字节，内容 hi，tracked）。疑似临时文件，但不在 T3 write scope（scripts/ 之外），本次只登记不处理，待 Lead 决定是否清理。

## 2. 发布版基线（修改前快照）

| 路径 | 大小 | sha256 |
|---|---|---|
| D:/休闲小岛幻境/发布/休闲小岛幻境.exe | 122,950,336 字节 | e2a9d2420375051022f38fe45a0c0786cc4a8ac4a30b345ed8378f2108a2cf8f |
| D:/休闲小岛幻境/构建输出/休闲小岛幻境.exe | 122,950,336 字节 | e2a9d2420375051022f38fe45a0c0786cc4a8ac4a30b345ed8378f2108a2cf8f |
| D:/休闲小岛幻境/发布/休闲小岛幻境.lnk | 818 字节 | 535dfd13874c4ae1b0f102cbee582094e7c0af474a7be918a8e54887620771fa |
| D:/休闲小岛幻境/开发产物/backup/release_pre_p6close/休闲小岛幻境_20261020_2045.exe | 122,950,336 字节 | e2a9d2420375051022f38fe45a0c0786cc4a8ac4a30b345ed8378f2108a2cf8f |

**结论**：发布目录、构建输出、P6 修改前备份三份 exe 字节完全一致（sha256 相同）；发布版即基线发布版，可用于回滚对照。

### 2.1 其它备份物（开发产物/backup/，均不在 git 仓库内）

| 文件 | 大小 | 用途 |
|---|---|---|
| _menu_tail_t1.tmp | 28,173 字节 | P6.1 菜单拼接临时片段（历史过程物） |
| fx_truncated_2152.gd | 51,170 字节 | fx.gd 截断事故备份（历史过程物） |
| menu_orig_t1.gd | 36,206 字节 | 旧 menu.gd 原始版本（对应 scripts/menu_orig_t1.gd 已从仓库删除） |
| release_pre_p6close/休闲小岛幻境_20261020_2045.exe | 122,950,336 字节 | P6 修改前发布版（见上表） |

## 3. 引擎基线

| 项 | 值 |
|---|---|
| 版本串 | 4.7.2.stable.official.ed1daf0bf |
| 控制台版 | D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe，198,152 字节，sha256 c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643 |
| 纯窗口版 | D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64.exe，180,858,888 字节，sha256 ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424 |

核验：`"D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe" --version` 应输出 4.7.2.stable.official.ed1daf0bf。

## 4. 运行环境（本机实测，2026-10-20）

| 项 | 值 |
|---|---|
| 操作系统 | Windows 10 专业版，10.0.19045，build 19045 |
| CPU | AMD Ryzen 5 2600X Six-Core（6 核 12 线程） |
| 内存 | 16 GB |
| GPU | NVIDIA GeForce RTX 2060（Win32_VideoController 报 AdapterRAM 4095 MB），驱动 32.0.16.1742 |
| 显示模式 | 2560×1440 @ 179 Hz（NVIDIA 输出当前模式）；显示器 HKC2412（53×29 cm） |
| 附加显示适配器 | OrayIddDriver Device（向日葵虚拟显示器，当前无有效模式） |
| 渲染后端 | Godot 4.7.2 Forward+（项目 project.godot 未改 rendering method，沿用默认 Forward+） |
| 引擎沙箱限制 | 历史会话中 DSH 文件沙箱禁止 Godot 写 C:/Users/...（user://），因此所有探针/截图/日志/自测配置一律写 D:/休闲小岛幻境/开发产物/；本文与 P6_TESTING.md 的命令均遵循该约定 |

> 提示：多个 teammate 共享同一台机器和 GPU。运行 --perf、--shots 或任何会开窗口的 Godot 前，先 tasklist 检查是否已有 Godot 进程；性能类测试需独占 GPU（由 Lead 统一安排），一般 headless 探针可并行。

## 5. 历史测试结果（历史参考，非本次实测）

来源：docs/P6_REPORT.md 第 5、8、9 节；原始日志在 D:/休闲小岛幻境/开发产物/logs/。以下数字是 2026-10-20 P6 收尾阶段跑出的历史记录，仅用于对照与回滚后的合理性判断；**不要当作本次 T3 的实测结论**。

| 项目 | 历史结果 | 证据（历史日志） |
|---|---|---|
| headless 自测 --selftest | 53 PASS / 0 FAIL / 1 SKIP（真实鼠标拖动），RESULT 53/53 passed，exit 0 | 开发产物/logs/final_selftest.log、final_selftest2.log（22:16、22:49） |
| 窗口自测 --selftest | 48/48 passed（早期自测项少于最终 53 项） | 开发产物/logs/final_selftest_window.log（20:42） |
| probe_quality6（headless） | checks=51 fails=0 | 开发产物/logs/final_quality.log |
| probe_water6（headless） | checks=17 fails=0 warns=0 | 开发产物/logs/final_water.log |
| probe_settings6 | 46/0 | docs/P6_REPORT.md §5.1 |
| probe_audio6 | 232/0（旧 probe_audio_p5 85/0） | 同上 |
| probe_cottage6 / probe_bird6 | 31/0 / 45/0 | 同上 |
| probe_smoke6 / probe_astro6 | 96/0 / 423/0 | 同上 |
| probe_menu6 / probe_menu7_t1 | 152/0 / 50/0 | 同上 |
| probe_esc_e2e_t1 / probe_frame_t5 | 19/0 / 5/0 | 同上 |
| --shots（窗口 1600×900） | 62 张 [SHOT]，0 条 SCRIPT ERROR / SHADER ERROR，exit 0 | 开发产物/logs/shots6_final_stdout.log、shots6_final_stderr.log（22:11） |
| --perf（窗口 1920×1080） | 两轮（22:05、22:15）；q0–q4 与各场景 fps 见 P6_REPORT §8；共享负载导致两轮差约 35% | 开发产物/logs/perf6_all_stdout.log、perf6_all_stderr.log |
| P6.1 菜单拼接后回归 | selftest 53/0（final_selftest2.log）、probe_menu7_t1 50/0、probe_ghost6（窗口）26/0 | P6_REPORT §5.1 末段 |

> 本次 T3 的实测范围（供区分）：headless 跑通 probe_settings6（[RESULT] ALL PASS，exit 0）与 headless --selftest（53/53、0 FAIL、26 秒、exit 0），日志 开发产物/logs/t3_selftest_headless.log；详见 docs/P6_TESTING.md 第 8 节。

## 6. 已知故障与限制清单

来自 docs/P6_REPORT.md §5.3、§9、§10 与历史日志，均为**已知/已接受**问题，不属于本次卫生任务要修复的范围：

1. **user:// 写入失败（环境限制）**：历史 DSH 沙箱禁止 Godot 写 C:/Users，user:// 配置/截图会报 ERR_FILE_CANT_OPEN；项目内自动化已改写到 开发产物/ 规避。发布版在普通 Windows 用户环境下不受此限制。
2. **headless 无法测真实鼠标拖动**：selftest 在 headless 下打印 [TEST] SKIP 真实鼠标拖动；滑条/时间轴拖动需窗口模式 --selftest 覆盖。
3. **分辨率自测项只在窗口模式实测**：headless 跳过；窗口模式使用 --resolution 指定窗口大小。
4. **SSAO/SSR/体积雾对 unshaded 无效**：引擎内置后处理对无光照材质不生效，项目改用自研 post_ao 与解析反射实现；这不是 bug。
5. **无 Light3D、无引擎阴影**：所有视觉效果用自发光/解析光照近似，室内光会溢出，属设计取舍。
6. **水面顶点位移仅视觉**：海浪高度 CPU/GPU 同源（probe_water6 保证），但物理层面无碰撞与浮力。
7. **天文为近似算法**：日出等事件与真实天文存在秒级误差（P6_ASTRO_ACCURACY.md 记录约 3.2 秒级），非精确星历。
8. **TAA 快速运动拖影**：Godot 4 TAA 已知现象，未在项目内规避。
9. **q4 极高画质性能偏低**：历史窗口实测 q4 约 41–63 fps、VRAM 约 878 MB；4K 分辨率未做长时间 3D 稳定性测试。
10. **音频无主观听感验证**：只有数值/状态级探针（probe_audio6 等），无人耳听感结论。
11. **退出期 RID/ObjectDB 泄漏警告**：退出时打印 RID 未释放警告，属清理顺序问题；历史 --perf after_6s objects 稳定（运行期无增长），不视为资源泄漏。日志中的 "ERROR: Failed to read the root certificate store." 为 headless 环境下 Windows 证书读取失败的无害噪音。
12. **性能数据受共享负载影响**：同一配置两轮 fps 可差 35%，比较性能时须同轮次、独占 GPU。

## 7. 完整回滚手册

### 7.1 代码回滚（git）

安全前提：**本仓库当前是多人共享工作树**（多个 teammate 同时改不同文件）。回滚前先 `git status --short` 确认要覆盖的文件没有别人的未提交改动。

推荐（只回滚指定路径，不动他人改动）：

```bash
cd D:/休闲小岛幻境/游戏工程

# 1) 先看当前状态与基线
git status --short
git rev-parse HEAD
git rev-parse baseline-p6close-20261020

# 2) 回滚单个/多个文件到 P6 基线（只覆盖工作树，不改分支指针）
git checkout baseline-p6close-20261020 -- scripts/main.gd scripts/menu.gd

# 3) 回滚整个工作树到 P6 基线（会覆盖所有已跟踪文件的未提交改动，慎用）
git checkout baseline-p6close-20261020 -- .

# 4) 撤销暂存区中自己误 add 的文件（不删工作树改动）
git restore --staged <path>
```

危险操作（**仅在确认独占仓库、且无人有未提交改动时**使用）：

```bash
# 会丢弃工作树全部未提交改动，并把当前分支移到基线 commit
git reset --hard baseline-p6close-20261020
```

禁止操作（会破坏其他 teammate 的工作树/历史）：`git checkout <其他分支>`、`git switch`、`git rebase`、`git commit --amend` 改写历史、`git tag -f` 覆盖基线 tag。

### 7.2 发布版回滚（exe）

```bash
cd D:/休闲小岛幻境
cp "开发产物/backup/release_pre_p6close/休闲小岛幻境_20261020_2045.exe" "发布/休闲小岛幻境.exe"
cp "开发产物/backup/release_pre_p6close/休闲小岛幻境_20261020_2045.exe" "构建输出/休闲小岛幻境.exe"
sha256sum "发布/休闲小岛幻境.exe" "构建输出/休闲小岛幻境.exe"
# 期望: e2a9d2420375051022f38fe45a0c0786cc4a8ac4a30b345ed8378f2108a2cf8f
```

### 7.3 回滚后检查单

1. `git rev-parse HEAD` 与 `git status --short`（确认回滚范围符合预期，未吞并他人改动）。
2. `git ls-files | wc -l` 应为 544（或回滚目标版本的跟踪数）。
3. headless 自测：`"D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe" --headless --path D:/休闲小岛幻境/游戏工程 -- --selftest`，期望 RESULT 53/53、exit 0（见 docs/P6_TESTING.md）。
4. 发布版 sha256 对照第 2 节。
5. 引擎版本：--version 输出 4.7.2.stable.official.ed1daf0bf。

### 7.4 引擎回滚

引擎目录 D:/休闲小岛幻境/引擎/ 独立于仓库，P6 期间未变更；如需重装 Godot 4.7.2 stable，用官方同名版本即可，不影响仓库与发布版。

## 8. .gitignore 与目录归属规则

| 位置 | 是否入库 | 归属/生成者 | 说明 |
|---|---|---|---|
| 游戏工程/（源码、场景、shaders、audio、sounds、fonts、art、docs、tools 源码、addons） | 入库 | 全体 | 受 git 管理，提交前确认自己的 write scope |
| 游戏工程/.godot/ | 不入库（.gitignore） | Godot 引擎自动生成 | 导入缓存，可随时删除重建 |
| 游戏工程/**/*.log、*.tmp、*.import.tmp、.editor_pid、.game_pid | 不入库（.gitignore） | 引擎/运行脚本 | 运行日志与临时文件（*.tmp 为 P6 新增规则） |
| 游戏工程/**/__pycache__/、*.pyc | 不入库（.gitignore，P6 新增） | Python（tools 下脚本） | 缓存，非源码 |
| 游戏工程/tools/base_env.json | **必须入库** | 人工维护 | 运行脚本用它固定 Godot 子进程环境变量，删除会破坏可复现性 |
| 游戏工程/tools/probe_*.gd（及 .gd.uid） | **必须入库** | 各阶段验证者 | 交付的自动化证据，不得删除现行探针 |
| D:/休闲小岛幻境/开发产物/ | 仓库外，不入库 | 测试/验证者、本任务 | logs/（运行日志）、shots/ 与 shots6/（截图）、probes/、baseline/（审计脚本与原始输出）、archive/（归档中间文件）、backup/（修改前备份）。可清理但需先确认无引用 |
| D:/休闲小岛幻境/构建输出/ | 仓库外，不入库 | 导出流程（export_presets.cfg 的 export_path） | exe 构建产物 |
| D:/休闲小岛幻境/发布/ | 仓库外，不入库 | 发布流程 | 对用户的发布副本（exe + 快捷方式） |
| D:/休闲小岛幻境/引擎/ | 仓库外，不入库 | 环境 | Godot 可执行文件 |

## 9. 本次卫生处理摘要（详见 P6_REFERENCE_AUDIT.md）

### 9.1 已归档并删除的 P6 中间文件（7 个）

处理方式：先复制到 `D:/休闲小岛幻境/开发产物/archive/scripts_p6_intermediate/`（保留原相对路径 scripts/、tools/、tools/__pycache__/），确认复制成功后再 `git rm`；删除后已用 sha256sum 逐个复核归档文件与删除前一致。

| 原路径 | 大小(B) | sha256（删除前=归档后） |
|---|---|---|
| scripts/menusplice_report.txt | 381 | 99b080546a2fc294218b3f28f641a819e965d9d59e5abc933abbfe05ad8d9e44 |
| scripts/menu_orig_t1.gd.uid（唯一孤儿 uid） | 20 | e7b9da1349a2a5e5fa6d301b1fdd4f4845cec13e8af20e768e71536752f404c4 |
| tools/_tmp_inst_test.gd | 718 | f3429e53564b003a6301b75295b8b2ba0cf30b0c544e227e62f56e81d1ac7a41 |
| tools/_tmp_inst_test.gd.uid | 20 | a1d552da39556050fa2002076682424ddfb6a699a40d8ed09822f7d33f30fa2e |
| tools/_tmp_typed_test.gd | 450 | d05ac4b186fb22b34bdc53fe21d8fa39efe665fac8c656d82afb228d2417bce6 |
| tools/_tmp_typed_test.gd.uid | 19 | 1df2db316849def7fe23b81482399475aaf4e86e6f656908ea96a04af24eaa5d |
| tools/__pycache__/gen_tz_data.cpython-313.pyc | 11246 | cf1351dddd3f2c8110633281774d350be999f354fa9e3ccb431a76317ec4e696 |

说明：这 7 个文件的 `git rm` 暂存删除被 Lead 的提交 **633ec8cf49d9a51de692807039f013e9553a64ae**（2026-10-20 23:23:09，`fix(quality): 高级覆盖真正接入渲染（AO/posts_ao 别名、lod_bias、fog_scale），移除无效体积雾入口`）一并带入（`git show --stat 633ec8c` 可见上述 7 条删除）。删除内容与归属均记录于此，**不要重复删除或回滚**；需要恢复时从归档目录复制回原路径即可（见下表）。

归档还原命令（如需）：

```bash
cd D:/休闲小岛幻境
cp -r 开发产物/archive/scripts_p6_intermediate/scripts/menu_orig_t1.gd.uid 游戏工程/scripts/
# 其余文件同理：archive/tools/... -> 游戏工程/tools/...
```

保留判断（未删除）：tools/_menu_splice_t1.py、_menu_introspect_t1.py、_checkmenu_t1.gd、_patch_probe*.py 等属 P6 修改过程工具脚本，虽无运行时引用，但体积小、可溯源，保留入库；scripts/ 下无其它 *.bak/*.orig/*.tmp（已扫）。

### 9.2 扫描与一致性结论

- 全工程引用扫描（开发产物/baseline/scan_references_v3.py）：280 文件 / 900 条引用 / 53 条未解析，逐条判定全部为：运行时输出 16 条、第三方 addons/godot_ai 文本与示例 29 条、历史记录 3 条、前向引用 5 条；**项目代码/资源/配置无真实失效引用**。唯一实际修复：docs/P6_RESEARCH_VISUAL.md:156 截图路径写法（详见 docs/P6_REFERENCE_AUDIT.md）。
- uid 一致性：基线已跟踪 220 个 .uid 全部可映射；孤儿 .uid 仅 menu_orig_t1.gd.uid（已归档删除）；.gd 缺 .gd.uid 基线为 0；.import 无源文件 0；0 字节文件 0。
- uid 提交策略：见 docs/P6_TESTING.md §8——.uid 必须与源文件成对提交，禁止用 .gitignore 忽略 *.uid；T3 补交 19 个与基线已跟踪探针配对的 tools/probe_*.gd.uid；shaders/post_ao.gdshader.uid 归 lifecycle 提交；verify-visual 新增探针的 .uid 由其随源文件提交。
- .gitignore 增补：*.tmp、__pycache__/、*.pyc、*.pyo；未忽略 *.uid。已用 `git check-ignore` 复核 tools/base_env.json、tools/probe_*.gd、*.gd.uid、export_presets.cfg、docs/*.md 均未被忽略，且 `git ls-files -ci --exclude-standard` 为空（无已跟踪文件被新增规则忽略）。

## 10. 基线核验命令（可复制执行）

```bash
cd D:/休闲小岛幻境/游戏工程
git rev-parse --abbrev-ref HEAD                    # p6-closeout
git rev-parse baseline-p6close-20261020            # 8f80b139d7f38c98df969b316c59d2bd96ac7871
git ls-files | wc -l                               # 544
git log -1 --format="%H %cd" --date=iso baseline-p6close-20261020
"D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe" --version   # 4.7.2.stable.official.ed1daf0bf

cd D:/休闲小岛幻境
sha256sum "发布/休闲小岛幻境.exe" "开发产物/backup/release_pre_p6close/休闲小岛幻境_20261020_2045.exe"
```

## 11. 变更记录

| 日期 | 变更 | 作者 |
|---|---|---|
| 2026-10-20 | 新建本文档，记录 baseline-p6close-20261020 基线、发布版/引擎/环境快照、历史测试声明、已知故障、回滚手册、目录归属规则 | T3 hygiene |
| 2026-10-20 | §9.1 补记：7 个 P6 中间文件归档明细（sha256/大小/还原命令）及其删除由 Lead 提交 633ec8c 携带的事实 | T3 hygiene |
| 2026-10-20 | §9.2 补记：引用审计结论（53 条全部非真实失效）、uid 一致性、uid 提交策略、.gitignore 实际增补与验证 | T3 hygiene |
| 2026-10-20 | 新增配套文档 docs/P6_TESTING.md（测试复现）与 docs/P6_REFERENCE_AUDIT.md（引用审计判定表） | T3 hygiene |
