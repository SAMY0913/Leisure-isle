# P8.2-06 回归基础设施笔记（soak 探针 / 画质矩阵探针 / 发布脚本）

本笔记记录 P8.2-06「工程收尾 / 精修」里**回归基础设施**部分的交付物、用法、短跑证据与
最终阶段仍需执行的事项。三个交付各自独立、互不依赖：

| 交付 | 文件 | 位置 | 状态 |
| --- | --- | --- | --- |
| 长时 soak 探针 | tools/probe_p82_soak.gd（d95f4b2） | 工程内（git 跟踪） | 2 分钟窗口短跑 PASS |
| 五档画质矩阵截图探针 | tools/probe_p82_matrix_shots.gd（310edae） | 工程内（git 跟踪） | 30/30 张实拍 PASS |
| 发布构建 / 独立验收 | build_release.sh / verify_release.sh | 开发产物/p82/（git 外） | dry-run + 基线副本预览导出 + 双包验收全部 PASS |

探针均被 export_presets.cfg 的 exclude_filter 里的 tools/* 排除，且不被 main.gd / game preload
（D14 教训：一旦被 preload，发布 exe 的 main.gd 解析失败）。本次两个探针都只在命令行用
--script 挂载，不进入游戏启动路径。

---

## 0. 运行铁律（所有 Godot 运行都必须遵守）

单 GPU 单实例串行器，排队上限 30 分钟：

      cd "D:/休闲小岛幻境/游戏工程" && bash "D:/休闲小岛幻境/开发产物/p82/run_godot.sh" --path . --resolution 1600x900 --script res://tools/probe_p82_xxx.gd -- --minutes=2

- run_godot.sh 用 mkdir 做引擎锁（.engine.lock），trap 清理，1800s 等待上限，参数透传。
- 进程被强杀时 trap 不执行，**下次运行前先删陈旧锁**：
      rm -rf "D:/休闲小岛幻境/开发产物/p82/.engine.lock"
- 长任务一律后台 job + 输出重定向到文件，再读文件；不要前台跑 30 分钟（会被 120s 超时杀掉）。
- 每次运行日志里出现下面两条 ERROR 属正常，不影响结果（user:// 不可写 / shader 缓存存不下）：
  - ERROR: Failed to open 'user://logs/godot*.log'.
  - ERROR: Condition "f.is_null()" is true. at: _save_to_cache (servers/rendering/renderer_rd/shader_rd.cpp:696)

---

## 1. 交付一：长时 soak 探针 tools/probe_p82_soak.gd

### 1.1 用法

      # 最终验收（30 分钟，默认 op-scale=1）
      bash ".../run_godot.sh" --path . --resolution 1600x900 --script res://tools/probe_p82_soak.gd -- --minutes=30 --out="D:/休闲小岛幻境/开发产物/p82/06_soak/final"

      # 快速自洽（2 分钟，操作节奏压缩到 10%）
      ... --script res://tools/probe_p82_soak.gd -- --minutes=2 --op-scale=0.1 --sample=5 --out=...

参数：--minutes=30 --out=<目录> --sample=5（采样秒） --op-scale=1（周期操作节奏倍率）
      --vsync=off --settle=0.5。

### 1.2 采样口径

- 真实渲染窗口，启动后循环钉到 **1600x900**（main.gd 的 _apply_resolution 会延迟按玩家存档
  改成 2560x1440，所以探针在 boot 里连续 8 轮 window_set_size + 补一帧，且不改 _settings 以免
  污染玩家存档；不改档是刻意选择）。
- vsync 关闭（DisplayServer.VSYNC_DISABLED），否则 refresh 上限会把 p95 压在 16.67ms。
- 帧时间用挂在场景树上的采样 Node（class FrameSampler extends Node）的 _process(delta) 累计
  **真实帧间隔**；不用 Performance.TIME_PROCESS（窗口模式不可信）。
- 采样周期 5s，写 CSV 一行，字段：
  t, fps, p50, p95, p99, max, frames, engine_fps, nodes, orphan, objects, dc, vram, mem_static,
  obj_count, res_count, lights_active, light_budget, weather, season, datetime, quality, max_fps。

### 1.3 周期真实操作（每项都回读断言，不是"调用了就算"）

| 周期 | 操作 | 断言 |
| --- | --- | --- |
| 60s | _apply_quality(q)，q 在 0..4 循环 | _quality == q、viewport.msaa_3d 一致、Engine.max_fps 一致、debug_light_state().budget 一致、0 <= active <= budget |
| 90s | _on_weather_type_requested(12 类循环) | 类型合法（snow 需 winter_w>=0.60 先跳 2027-01-15，typhoon 需 warm_w>=0.60 先跳 2026-07-15）、_weather_state.type 回读、label 回读 |
| 150s | _jump_datetime 跳 11 个日期 | 年月日时分 + 季节 id 全等回读；含四季、跨年 2027-12-31→2028-01-01、闰年 2028-02-29、月末 2027-01-31→2027-02-01、非闰年 2026-02-28→03-01 |
| 180s | 开关时间面板 / 日历 / 天气面板 / 性能面板 / 年历，及 HUD 整体隐藏-恢复 | 开关 flag 翻转、panel.visible == flag、再点回还原；隐藏时各面板全折叠、_visible_now=false |

（跳日期前先 _paused=true：_day_length=480s/天，真实 1s ≈ 模拟 180s，不暂停分钟会漂。）

### 1.4 自带 PASS/FAIL 判定（写进日志 + JSON + MD，退出码 0=PASS）

- C1_frame_p95_degrade：运行 < 720s 记 SKIP（趋势无意义）；否则 末窗 p95 <= 首窗 p95*1.25 + 2.0ms，
  窗口 min(300s, max(20s, elapsed*0.5))。
- C2_node_growth：首 3 行 / 末 3 行 nodes 中位数，增长 <= n0*2% + 50。
- C3_fps_floor：不得出现连续 3 次采样 fps < 20。
- C4_op_coverage：四类操作次数 >= 计划次数的 70%（运行 < 600s 时按 max(1, min(计划,2)) 放宽），
  且 >= 600s 时要求 12 类天气全覆盖。
- C5_zero_assert_fail：本脚本所有断言 0 失败。
- C6_state_sane：退出时 isle 仍在场景树、_mode == 1。

产物：soak_<stamp>.csv / .log / _summary.json（含全部 checks、ops、samples）/ _summary.md。

### 1.5 短跑证据（2 分钟，已 PASS）

目录 D:/休闲小岛幻境/开发产物/p82/06_soak/_short_window2/：

- verdict=PASS，elapsed=120.7s，samples=24，ops=45（ok=45 fail=0），window=1600x900，vsync=off
- frame：首窗 p50=10.08 / p95=16.67 / max=150.00；末窗 p50=11.67 / p95=16.67 / max=145.86
- state delta：nodes +39、orphan +22、vram +296.7MB、mem_static +18.8MB
- ops coverage：quality 19、weather 13（12 类全到）、date 7、hud 6
- C1 SKIP（<720s）、C2 PASS（1546→1585，上限 +81）、C3 PASS、C4 PASS、C5 PASS（0 断言失败）、C6 PASS
- 说明：vram +296.7MB 是首窗之后 shader/纹理才全部驻留的启动期增长，不是泄漏；30 分钟跑里
  C1 会用真实窗口对比，若继续单调增长会在末窗暴露。

### 1.6 最终阶段仍需执行

- 30 分钟正式 soak（--minutes=30，op-scale=1）：这是唯一能触发 C1 的运行，务必跑；
  期间不要并行跑其他 Godot 实例（会互相抢 GPU 并污染 frame 数据）。
- 判 PASS 后再进入发布冻结流程。

---

## 2. 交付二：五档画质矩阵截图探针 tools/probe_p82_matrix_shots.gd

### 2.1 用法

      bash ".../run_godot.sh" --path . --resolution 1600x900 --script res://tools/probe_p82_matrix_shots.gd -- --out="D:/休闲小岛幻境/开发产物/p82/06_matrix"

参数：--out= --scene=<key>（只拍一个场景，排障用） --quality=<0..4>（只拍一档）
      --max-white=0.02（夜间白点上限） --min-mean=12（夜间最低平均亮度）
      --min-lum-diff=1.0 --min-dc-diff=10 --min-white-diff=0.002（q0 vs q4 差异阈值）
      --settle=0.9 --contact（拼 contact sheet） --no-window-pin。

### 2.2 矩阵：q0..q4 × 6 场景 = 30 张，全部 1600x900

| key | 场景 | 工况（日期时间 / 天气 / 累积） | 机位 |
| --- | --- | --- | --- |
| clear_day_outdoor | 清晰白天室外主岛全景 | 2026-07-15 10:00 clear 0s | _p8_camera_island |
| winter_white_outdoor | 冬季白化室外 | 2027-01-15 11:00 heavy_snow 30000s | _p8_camera_island |
| indoor_night_fireplace | 室内夜间壁炉近景 | 2027-01-15 20:30 clear 0s | 壁炉近景（P8.1 机位） |
| dock_night | 码头夜间（帆船 / 灯塔光束） | 2027-01-15 20:30 clear 0s | main.gd 自带 _boat_dock_pos/_boat_dock_heading  oblique 机位 |
| heavy_rain | 强降雨 | 2026-07-15 14:00 heavy_rain 600s | _p8_camera_island |
| heavy_snow_close | 大雪近景树下 | 2027-01-15 11:00 heavy_snow 30000s | _p8_camera_tree |

- 场景工况统一走 main.gd 现成的 _p8_wfx_apply(y, mo, d, h, mi, type, accum_s)，比手写状态稳；
  室内/码头机位把相机定死，跑完回读日历与天气 label 断言场景确实生效。
- 机位踩坑：不要用 IsleMath.dock_start/end 手算码头机位（相机会进礁石/栈桥内部，画面是近景遮挡 +
  紫夜空）。改用 main.gd 的 _boat_dock_pos / _boat_dock_heading 算水平外法线 dock_out，取
  _pose_look(dock_c + dock_out*8.5 + (0,5.2,0), dock_c - dock_out*1.5 + (0,0.40,0), 54)。
- 画质切换：先写 _settings["quality"]/quality_overrides（与游戏内切档等价），再 _apply_quality(q)；
  每张前重新 _pose_look 一遍，等 settle 后 RenderingServer.frame_post_draw 再取图。

### 2.3 每张的量化字段（matrix.csv，22 列）

file, quality, scene, label, date, weather, accum_s, camera, width, height,
mean_lum, max_lum, p95_lum, dark_ratio(灰度<25 占比), white_ratio(灰度>=250 占比),
draw_calls, objects, lights_active, light_budget, msaa_3d, max_fps, capture_ok

### 2.4 判定 H1–H5（阈值可配，默认值见上）

- H1_coverage：30/30 张、尺寸全部 1600x900。
- H2_quality_visual_diff：同一场景 q0 vs q4 至少一项超阈值（mean>=1.0 或 dc>=10 或 white>=0.002）。
- H3_night_not_black：夜间场景（indoor_night_fireplace / dock_night）最低平均亮度 >= 12。
- H4_night_not_clipped：夜间场景最高白点占比 <= 0.02。
- H5_no_runtime_error：探针侧无异常。

### 2.5 实跑结果（PASS，证据目录 D:/休闲小岛幻境/开发产物/p82/06_matrix/）

- RESULT PASS：captured=30/30；H2 6/6 场景 q0 vs q4 有可测差异
- H3 夜间最低平均亮度 31.64（下限 12）@dock_night q0
- H4 夜间最高白点占比 0.00009（上限 0.02）@dock_night q4
- 产物：shots/ 30 张 PNG、matrix.csv、MANIFEST.md、matrix_summary_<stamp>.json、contact_sheet.png（5 列 × 6 行）
- 首轮曾因码头机位构图错误（row4）单场景修复验证：06_matrix/_dockfix/（5 张，PASS）后重跑全矩阵；
  旧的 summary 已归档到 06_matrix/_prev_run/。

### 2.6 数据解读纪律

本探针只给 data 与阈值判定，不下"画质是否够好"的审美结论。matrix.csv 的 mean/p95/dark/white 是
**整帧灰度统计**，用于：① 五档是否真的产生差异；② 夜间是否全黑 / 高光是否过曝；③ 各档 dc/objects
随画质变化的趋势。审美判断仍需人眼看 shots/ 与 contact_sheet.png。

---

## 3. 交付三：发布包构建 build_release.sh / 独立验收 verify_release.sh

两个脚本都在 **git 外**：D:/休闲小岛幻境/开发产物/p82/。依据 docs/P8_1_REFINEMENT_REPORT.md 8.3
与 P6 的 final_release.sh 累积经验重写，做到"默认绝不覆盖 发布/"。

### 3.1 build_release.sh

      bash build_release.sh --dry-run                 # 只做环境检查 + 打印导出命令
      bash build_release.sh                           # 导出到 release_preview/build_<stamp>/，跑完验收
      bash build_release.sh --skip-git --project="D:/休闲小岛幻境/开发产物/p82/base" --out=...
                                                     # 用只读基线副本验证管线
      bash build_release.sh --copy-to-release          # 验收 PASS 才备份旧包并覆盖 发布/ 与 构建输出/

关键实现（全部有实测）：

- 导出前 **TMP=TEMP=D:/休闲小岛幻境/开发产物/tmp_export**（否则嵌入式 pck 的 project.binary 损坏），
  导出命令：--headless --path <工程> --export-release "Windows Desktop" <out.exe> --verbose，
  timeout 1800，日志 export.log；
- 导出后先查日志里 project.binary 错误（Corrupted header / Could not save project.binary），命中即中止；
- 静态查包内容：解析 savepack 清单（grep "正在保存文件"），逐目录确认 res://tools/、docs/、shots/、
  refshots/、addons/、sounds/ 与 *.md 全为 0，且 res://scripts/main.gd 在包内；并确认导出插件日志出现
  "stripping autoload/_mcp_game_helper"（未见只 WARN，因插件版本措辞可能变化）；
- 记录 size + sha256 + 引擎版本 + export_presets.cfg 的产品名/版本；
- 验收 ① exe --headless --quit 退出码 0 且日志无 SCRIPT ERROR / Parse Error / Corrupted header；
  ② exe --headless -- --selftest 退出码 0、解析 "[TEST] RESULT N/M passed" 且 N == M；
- --copy-to-release 时旧包先备份到 **开发产物/backup/release_pre_p82/休闲小岛幻境_pre_p82_<stamp>.exe**
  （并记录旧包 size/sha），再覆盖 发布/ 与 构建输出/；
- 产物：build.log、export.log、savepack_list.txt、verify_quit.log、verify_selftest.log、record.json、RECORD.md；
- git 冻结门禁：默认检查 scripts/ shaders/ audio/ fonts/ isle.tscn project.godot export_presets.cfg 是否
  有未提交改动（忽略 .uid），脏则中止；--allow-dirty 放行（结果不能作为发布候选），--skip-git 用于基线副本。

### 3.2 verify_release.sh

      bash verify_release.sh                                   # 验收 发布/休闲小岛幻境.exe
      bash verify_release.sh --exe=<path> --logdir=<dir> \
           --expect-sha256=<hex> --expect-size=<bytes> --expect-selftest=73/73

只读验收、不改 发布/：存在性/体积/SHA256（可对期望值）→ --headless --quit → --headless -- --selftest
（可对期望分数）→ 脚本错误扫描 → 版本信息 → 写 verify_result_<stamp>.json / VERIFY.md。退出码 0=PASS。

### 3.3 已完成的脚本验证（全部 PASS）

1) dry-run（当前工作树）：
   OK 引擎/工程/预设/TMP 可写；git HEAD=429da59，scripts/cottage.gd、scripts/main.gd 有他人未提交改动
   → 打印 WARN 并 dry-run PASS（真实构建会正确中止，门禁有效）。

2) 基线副本预览导出（验证完整管线，不碰 发布/）：
   bash build_release.sh --skip-git --project="D:/休闲小岛幻境/开发产物/p82/base" \
        --out="D:/休闲小岛幻境/开发产物/p82/release_preview/base_preview"
   → RESULT PASS：savepack 113 个文件、排除目录全 0、main.gd 在包、autoload 已剥离、
     size=117238104、sha256=c40376ad2dda1d8eb2e9848ca8a2ce00e4c1a841a03444fa9e9b80ef5d62b668、
     产品 休闲小岛幻境 1.0.0、quit_rc=0、selftest 73/73。
   **该 sha256 与现有 发布/休闲小岛幻境.exe 完全一致**——说明导出管线可复现、脚本行为与 P8.1 手工发布等价。

3) verify_release.sh 双包验收：
   - 预览包：--expect-sha256/--expect-size/--expect-selftest 全中，RESULT PASS；
   - 正式包 发布/休闲小岛幻境.exe：size/sha 与前一致，quit_rc=0，selftest 73/73，RESULT PASS
     （日志见 release_preview/verify_runs.log、verify_preview/、verify_release_pkg/）。

### 3.4 最终阶段仍需执行（等 Lead 宣布代码冻结后）

1. 确认工作树只含预期的已提交内容（构建脚本会拦 dirty）。
2. bash build_release.sh（不带 --copy-to-release）先出一份 release_preview 并复核 PASS；
3. bash build_release.sh --copy-to-release 正式覆盖 发布/ 与 构建输出/（自动备份旧包）；
4. bash verify_release.sh 对 发布/ 再验收一次，把 size/sha256/版本写进 P8.2 报告与测试结果文档；
5. 记录新包 sha256 与 P8.1 包（c40376ad...b668）的差异说明。

---

## 4. 已知问题 / 注意

- 每次运行都有 user:// 日志写入 ERROR 与 shader_rd _save_to_cache ERROR：环境性的，非代码缺陷，
  不影响 CSV/截图/自测结果。
- 运行中偶见 "[0] save_settings (res://scripts/isle_settings.gd:425) / [1] _tick (res://scripts/main.gd:1817)"
  栈帧：探针改画质会触发设置保存路径，属预期（探针不改档时会话内也会周期性触发），不影响判定。
- 探针不得设 _shots=true（main.gd 会跑整套自动截图），窗口尺寸靠循环 window_set_size 钉；
  _apply_resolution 在 _shots/_perf/_p8perf/_selftest/_transition 为 true 时才跳过。
- 新探针上库后如果被任何启动路径 preload，会导致发布包 main.gd 解析失败（D14）；新增探针请保持
  只在 --script 下运行，且 export exclude_filter 保持 tools/*。
