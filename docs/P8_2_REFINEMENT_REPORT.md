# P8.2 工程收尾 / 室内灯光修复 / 性能与交互精修 — 精修报告

> 状态：**进行中（骨架，数据随各模块验收回填）**。冻结前本文件必须完成全部章节并通过 P8.2-06 集成回归。

## 0. 结论摘要（待回填）

| 模块 | 结论 | 证据索引 |
| --- | --- | --- |
| P8.2-01 壁炉/烟囱几何 | **已修复**：烟囱一层侵入 0.60 m→0，壁炉改真凹龛（凹深 0.18~0.21 m），火焰三机位可见 0/3→3/3；几何探针 before 30/10 → after **34/0** | §3 |
| P8.2-02 灯光质量 + 五档性能 | **视觉**：(a) 吊灯光晕纳入昼夜调光，`room_wide` 右上 ROI 近白 **42,309→0**、均值 −34.5%；(b) 壁炉光槽 energy 1.50→1.05、range 5→6，同 run 新旧参数 A/B 裁切 **−51.0%（day）/−53.7%（night）**，炉台暖光保留（p99 208/220、clip 0）；(c) 夜间悬空球 = **P8.1 既有**无阴影解析光墙热点（逐盏归因到 fireplace 槽），**NO-GO 不改**、登记 L-6；(d) 双池过渡带**未采纳**（回滚干净）。**性能**：五档 A/B 无超噪声回归（q0 −1.3%，其余 +0.5…+0.9%，≥773 µs 显著差异 **0** 个），激活灯数/预算两侧一致（10/11/12/14/16）；**q0 绝对 FPS 门 ≥170 仍未达**（本机 132–247，7 场景几何均值 181→183.5），与 P8.1 数字不可直接比较，登记为预存在天花板 | §4 |
| P8.2-03 强风 CPU | **P8.1 的 +1.93 ms 为 `Performance.TIME_PROCESS` 伪影**；强风视觉真实成本 41–47 µs/帧（0.7–0.8%），三项按需更新优化收回 19–31 µs/帧（相对同 run 未优化态 −35.9%…−42.7%，相对 P8 旧实现 −30.5%…−36.3%），视觉/行为逐帧等价 23/23 | §5 |
| P8.2-04 冬季细节 + 跨季生态 | **5 个冬季栖点中 1 个修复**（wb4 足部净空 −0.0154→+0.1125 m），其余 4 个几何+红花 5 朵全部通过；裸枝自然使用率 38.7%（12/31，5/5 点）、跨季/跨年/暂停恢复全通过、固定种子 soak **1407/0** | §6 |
| P8.2-05 日期滚轮窗口 E2E | **U-02…U-12 全部闭环**（U-02 帧时间 = **WARN 可测但不可分辨**：Δp50 中位 +0.400 ms vs A/A 噪声中位 0.729 ms；U-03/U-04 合成输入 PASS 但真机高 DPI/触屏未验证；其余 8 项 PASS）；窗口 behavior 87 项 **0 FAIL**、headless 82/82、UI 82 项 0 fail；生产码仅 1 行（常量去重，零行为变更） | §7 |
| P8.2-06 全量回归 + 发布包 | 待回填 | §8 |

## 1. 基线与方法

### 1.1 起点核实（实测，非假定）
- 工程根（git 仓库）：`D:/休闲小岛幻境/游戏工程`；外层 `D:/休闲小岛幻境` 不是 git 仓库。
- 历史基线：P8 tag `p8-weather-seasons-freeze-20261022` → 1cdae5b；P8.1 冻结代码 `6de37c4`、冻结 tag `p81-refinement-freeze-20261022` → ddcde3a（6de37c4 为新增 `.uid` 补交的父提交）；历史分支 `p81-integration` 停在 ddcde3a，工作树干净。
- P8.2 工作分支：`p82-integration`（从 ddcde3a 创建，未改写任何历史提交，未覆盖 P8/P8.1 冻结证据与发布包）。
- 冻结证据完整性：P8/P8.1 证据共 599 个文件在开工前做了 SHA-256 快照（`开发产物/p82/integrity/frozen_p81_p8_manifest_before.txt`），收尾时复算比对（见 §8.5）；旧发布包 SHA-256 已记录（`release_exe_before.txt`），新包不覆盖前先备份。

### 1.2 实测环境
- 引擎：`D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe`（4.7.2.stable.official.ed1daf0bf）。
- 硬件：AMD Ryzen 5 2600X（6C/12T）；NVIDIA GeForce RTX 2060；Windows；另有 Oray 虚拟显示器（截图/窗口测试需注意主显示器）。
- 基线自测：在 detached `ddcde3a` 副本上 `--headless --path . -- --selftest` = 73/73 PASS，EXIT 0（日志 `开发产物/p82/baseline/selftest_HEAD_ddcde3a.log`）。

### 1.3 测量与取样纪律
- 所有 Godot 进程串行执行（单 GPU）：全局锁 `开发产物/p82/run_godot.sh`（锁目录 `开发产物/p82/.engine.lock`，排队上限 1800 s，陈旧锁 40 min 自动清理），避免并发运行互相污染帧时间。
- A/B 对比一律使用 **同一台机、同一机位、同一引擎/画质/分辨率/VSync 设置**，base = detached `ddcde3a` 副本（`开发产物/p82/base`），new = p82-integration 工作树；交替执行、预热、记录中位与 P95。
- 帧时间以真实窗口渲染下的逐帧 delta 采样为准；**窗口模式下 `Performance.TIME_PROCESS` 为常量、不可用于帧耗时证明**（P8.1 P-6 已确认），本轮一律改用逐帧 delta 采样器。
- 所有截图/日志/CSV 写入 `开发产物/p82/<模块>/`（git 外），不写入 `开发产物/p81/**`、`p8/**`、`发布/`、既有 `构建输出/` exe。

### 1.4 串行器缺陷与影响披露（重要，诚实登记）
- `run_godot.sh` v2 的"独占确认"用 `tasklist | grep -E "Godot_v4\.7\.2-stable_win64(_console)?\.exe"`，但 git-bash 下 `tasklist` 把 Image Name 截断到 25 字符（`Godot_v4.7.2-stable_win64`，不含 `.exe`）→ **正则永不匹配，"拿锁后等既有引擎退出"是空操作**。v2 日志里的 `[run_godot] exclusive window` 是拿到锁后无条件打印，**只证明持锁，不证明无并发**。
- 19:37 实测到一次真实并发（两个不同模块同时运行），随即定位并修复为 v3（`grep -F "Godot_v4.7.2-stable_win64"`，同时澄清 console 启动器会 fork 一个运行版子进程、单次运行 2 个 pid 属正常）。修复脚本在 19:38 以就地重写方式落盘，导致当时两个正在运行的外层 bash 读到半截文件而报语法错（引擎本身已正常退出、产物有效），此后改为原子替换。
- 影响面与处理：
  - **P8.2-03 强风计时**（v3 前采集）：结论建立在**同一 build 内 new/off/legacy 交替**之上（同 run 内背靠背），对并发不敏感；但"独占窗口"这一表述降级为"持锁窗口"，绝对帧时间不作跨 run 结论。已在 §5.6 增加对应限制条目。
  - **P8.2-05 滚轮 UI10 帧时间**：旧数据（19:14，无 marker）作废，已在 v3 干净窗口重跑并采用新数字（§7）。
  - **P8.2-02 五档 A/B**：全部在 v3 修复后采集，每 run 前后记录 tasklist，不受影响。
  - 其余视觉/几何/生态证据不受影响（非计时）。

## 2. 修改文件与原因总表

| 文件 | 模块 | 原因 | 提交 |
| --- | --- | --- | --- |
| scripts/cottage.gd | 01 | 烟囱分段（一层零侵入）+ 石胸改框架形成 0.18m 真凹龛 + 火焰竖立退入 + halo 收小；新增 `probe_skip_batch` 探针开关（生产恒 false） | ce6fc30 |
| tools/probe_p82_fireplace.gd | 01 | 新增壁炉几何探针（34 项断言，geom/shot 两模式）+ 像素量化（13 机位对） | 1121f65 |
| docs/P8_2_01_NOTES.md | 01 | 壁炉专项笔记（before 10 失败项、修复参数、锚点不变清单、20 vs 19 口径说明） | 1121f65 / 41c4816 |
| scripts/main.gd | 03 | 5 段分段计时（默认关闭零开销）、`--p82windcpu` 采样 harness、落叶参数缓存、萤火 activity 缓存+属性写入门控、秋千 `*_into` 容器复用、`--windshotsout` 取证目录覆盖、`_p82opt_off` 测量开关 | 766ce21 |
| tools/probe_p82_wind_cpu.gd | 03 | 新增优化等价性/门控正确性探针 23 条 | 766ce21 |
| docs/P8_2_03_NOTES.md | 03 | 强风 CPU 专项笔记（方法/热点/数据/限制/开关） | 766ce21 |
| scripts/world.gd | 04 | 冬季裸枝栖点 `winter_branch_4` 从次级枝内插位置移到同枝外侧干净枝面（世界坐标 (-11.807,15.583,6.735)，t 0.750→0.835，法线/slope/facing 不变）+7/−1 | 429da59 |
| tools/probe_p82_eco_geom.gd / _soak.gd / _perch_diag.gd / _diag.gd / _shot.gd / _closeup.gd | 04 | 生态几何断言（135 项）、固定种子跨季 soak（1407 项）、栖点诊断、4 m 与 2.4 m 特写取证 | 0447c0f |
| docs/P8_2_04_NOTES.md | 04 | 冬季专项笔记（六项结论、usage 统计、限制披露） | 0447c0f |
| scripts/cottage.gd | 02(a) | 一层/阁楼吊灯 halo 基准 size 1.10/0.95→0.60、基准色 (2.2,1.5,0.85)→(1.25,0.82,0.42)，并入 `interior_halos` | ca22d08 |
| scripts/main.gd | 02(a) | 新增 `_interior_halos` 收集与逐帧昼夜写回（albedo/scale 随 `lanternI`） | ca22d08 |
| scripts/cottage.gd | 02(b) | 壁炉解析光槽 `energy 1.50→1.05`、`range 5.0→6.0`，位置与池归属不变 | befdb0f |
| tools/probe_p82_lights_visual.gd | 02 | 新增灯光视觉诊断探针（shots/diag/nodes/isolate2/isolate3/qa 六模式，windowed，`--out` 可覆盖） | 4ac7f0f |
| tools/probe_p81_lights.gd | 02 | **仅** `OUT_DIR` 改到 `开发产物/p82/02_lighting/probe_p81_lights/` + 1 行注释；147 条断言零改动 | 4ac7f0f |
| docs/P8_2_02_NOTES.md | 02 | 灯光专项笔记（a/b/c/d 四段 + 逐项结论表 + 回归表） | ca22d08 / befdb0f / 4ac7f0f |
| `shaders/toon.gdshader` + `scripts/main.gd`（global 参数注册） | 02(d) | 双池过渡带方案**未采纳**：global uniform 与注册时序不一致引发 4,374 条 shader 警告，已完整回滚（全树 `grep g_indoor_band` = 0），**无提交** | — |
| scripts/ui_datetime_wheel.gd | 05 | 生产码仅 1 行：`end_drag` 里的 `1.2` 字面量改引用既有 `FLICK_THRESHOLD` 常量（零行为变更） | 56bfbb1 |
| tools/probe_p81_datetime_wheel_ui.gd | 05 | `OUT_DIR` 改到 `开发产物/p82/05_wheel/`；UI10 帧时间段整段重写（逐帧 delta + A/A 噪声底 + CI，替代不可用的 `Performance.TIME_PROCESS`） | 56bfbb1 |
| tools/probe_p82_datetime_behavior.gd | 05 | 新增窗口行为探针 87 项（吸附/惯性/拖动/触摸/TAB/键重复/并发面板/失焦/跨午夜/极端年份/长时节点数） | 56bfbb1 |
| tools/probe_p82_datetime_dpi.gd | 05 | 新增窗口尺寸×DPI 几何与命中探针 12 项 | 56bfbb1 |
| tools/probe_p82_datetime_frame.gd | 05 | 新增窗口帧时间 A/B 探针（vsync 开/关 + A/A 噪声底） | 56bfbb1 |
| docs/P8_2_05_NOTES.md | 05 | 滚轮专项笔记（U-02…U-12 闭环、三层口径、未验证披露、P-1…P-6 处置） | 56bfbb1 |

## 3. P8.2-01 壁炉与烟囱几何（已修复，证据齐全）

### 3.1 复现
- 机位：一楼室内正对壁炉（z 正方向看向 -z）、低机位、斜侧 30°；五档 q0..q4。
- 现象：室内只看到一块平整石板，看不到黑炉膛、火焰与壁炉光；室内地面/炉台无壁炉暖光。
- 探针：`tools/probe_p82_fireplace.gd --mode=geom`（`IsleCottage.probe_skip_batch=true` 跳过静态合批，逐件测 AABB）+ `--mode=shots`（生产合批路径，真实窗口截图）。
- before 证据：`开发产物/p82/01_fireplace/before/before_geom.log`（30 checks / 10 FAIL）、`before/q0..q4_fire_front.png`、`q0..q4_fire_oblique.png`、`day_*_shots`。

### 3.2 根因（实测几何，root 局部坐标；后墙内表面 z=-2.80、外表面 z=-3.10）
- 烟囱主体 `cottage.gd:1168`：Box `size=(0.88,5.75,0.80)` @ `(-2.200,3.325,-2.600)` → **z[-3.000,-2.200]**，越过内墙面 0.60 m，把整组壁炉包在体内：
  - 石胸 `@1245` z[-2.800,-2.540]、黑膛板 `@1246` z[-2.590,-2.530]、3 块火焰盒 z[-2.610,-2.430]、halo (z=-2.420)、壁炉光槽 local (-2.200,1.100,-2.300) 全在烟囱盒内 → G8b 判定 `inside=@MeshInstance3D@780`。
- 结构上也没有凹龛：石胸是整板 1.36×1.62×0.26，黑膛板贴在其前脸，凹深 0.00 m；火焰是 3 块 (0.14,0.07,0.18) 平躺方糖，只有 0.07 m 高、还有 0.11 m 露在烟囱前脸之外；halo 是半径 0.85 的加色 billboard，挂在 z=-2.420 —— 一旦可见就会经 glow/tonemap 饱和成硬边黄块。G6 front/low/oblique 三机位全部"看不到火"。
- 定性：P8 既有缺陷（P8.1 报告 §6.6 已记录为预存在），**不是 P8.1 回归**。

### 3.3 修复方式与参数（最小增量，`scripts/cottage.gd`）
- 烟囱改分段：
  - 上半段 `(0.88,3.10,0.80)`@`(ch_x,4.65,ch_z)` → y[3.10,6.20]，阁楼烟囱胸与屋面以上外观 **与原来完全一致**（z 仍 -3.00..-2.20）；
  - 一层/裙墙段 `(0.88,2.70,0.26)`@`(ch_x,1.79,-2.96)` → y[0.44,3.14]、z[-3.09,-2.83]，退成埋在后墙厚度（0.30）内的薄烟道，前后各留 0.01/0.03 m 防共面；一层室内侵入 = 0；
  - y=1.60 那道石箍随一层侵入体一起消失（原本只在一层室内可见），保留 3.40/5.40 两道。
- 石胸改"两侧石柱 + 上楣"框架（前脸 z=-2.55，开口净宽 0.86 m）：石柱 0.25×1.62×0.25 @x=ch_x±0.555；上楣 1.16×0.81×0.25 @y=fy+1.205（比柱前脸浅 1 cm、顶面低 1 cm 防 z-fighting）；黑膛板 0.82×0.72×0.06 @z=-2.76 → z[-2.79,-2.73]，**凹深 0.18 m**；炉膛地石 0.90×0.09×0.28 @y=fy+0.045（顶面比炉台石低 1 cm，z 向重叠 0.02 m）。
- 火焰：3 簇竖立盒 (0.12,0.20,0.10)/(0.13,0.26,0.10)/(0.12,0.20,0.10) @x=ch_x+{-0.15,0,+0.15}、z=-2.63（z[-2.68,-2.58]，整块退进凹龛），底部统一落在柴薪顶面；`glow 1.35→1.20`，基色 #ff9a3c→#ff8f30；柴薪移入凹龛 z=-2.66/-2.68。
- halo：半径 0.85→0.34，位置 z=-2.420→-2.565（凹龛内），加色 (2.4,1.2,0.45)→(1.7,0.85,0.32)。
- 未改动的结构锚点（全部由探针逐项断言）：`ch_top=6.20`、烟帽 (0.46,0.20,0.42)@y=6.45、`ChimneyTop` 节点、烟囱栖点 `chimney_0` @(-2.070,14.526,-2.434)、穿屋面处、泛水板/泛水石、`ChimneyHit` @(ch_x,5.10,ch_z) size(1.1,2.9,1.1)、壁炉光槽 local (ch_x,1.100,-2.30) 且仍属室内池。

### 3.4 验证
- before 几何：`30 checks / 10 FAIL`（`before/before_geom.log`），10 个失败项为：
G1 烟囱一层侵入、G2 贴墙进深超标、G2b 埋墙、G3c 黑膛板未退到开口平面后、G4b 火焰露在凹龛外、G5 halo 尺寸/位置、
G6-front / G6-low / G6-oblique 三机位看不到火、G8b 光槽在实体盒内。

- after 几何：`34 checks / 0 FAIL`（`after/after_geom.log`）。G1 一层零侵入、G2 贴墙件最大进深合规且不埋墙、G3 黑膛板 1 块且退到开口平面之后、G4 火焰整块在凹龛内且高度≥0.10、G5 halo 唯一且退入、G6 front/low/oblique 三机位全部可见、G7 烟帽/栖点/穿屋面/泛水不变、G8b 光槽不再位于任何实体盒内、G9 hitbox 不变。
- 像素量化（13 个机位对）：before 高热像素（火焰色域）=0；after = 3.6~6.8 万像素，前后对比可量化。
- 真实截图（2560×1440，生产合批路径）：`after/` 共 **20 张**（q0..q4_fire_front/oblique 10 张、q2_fire_low、q2_room_wide、q2_exterior_chimney、q2_attic_view、q2_attic_chimney_side、day_fire_front/oblique/room_wide，加 `q2_attic_breast`、`day_attic_breast` 两张新机位）；`before/` 同机位 **18 张**（base 副本实拍，新加的两张阁楼机位需要改副本探针，故未补拍）。逐张尺寸与 sha256 见 `开发产物/p82/01_fireplace/MANIFEST.csv`（after 20 + before 18）。
  口径说明：P8.1 阶段曾按 19 张登记，差异来源是本轮发现原阁楼机位被床/屋面遮挡后新增 `q2_attic_breast`（若只算这一张为 19）+ 白天版 `day_attic_breast`，不是多了 `day_fire_room_wide`（该机位不存在）。
- 人工目检（Lead 独立复核 after 全部 20 张）：正面与斜侧近景火焰清晰；暖光落在炉台石/地板/上方墙面；一楼与阁楼结构完整；`q2_exterior_chimney` 烟囱外观、石箍、泛水、烟帽、雪面与栖鸟自然，屋顶交界无异常。
- 外部依赖回归：cottage6 / p7v2_perch / p8_ecology / p81_tree_bird / world_scale / `--selftest`（结果回填于 §8.1）。
- 专项笔记：`docs/P8_2_01_NOTES.md`。

### 3.5 本项提交
- `ce6fc30` P8.2-01：烟囱分段+壁炉真实凹龛（仅 `scripts/cottage.gd`，49+/17−）。
- `1121f65` P8.2-01：新增壁炉几何探针（34 断言）+截图/像素比对+修复记录（`tools/probe_p82_fireplace.gd`、`docs/P8_2_01_NOTES.md`）。
- `41c4816` P8.2-01：NOTES 补充 34/0、before 10 个失败 check 名、20 张截图口径与 MANIFEST。
- 说明：按子里程碑拆为 3 个提交（代码 / 探针+笔记 / 笔记补充），未 amend 已提交内容，未把 wind 的 `scripts/main.gd` 混入；三个提交合起来即本项完整改动。

## 4. P8.2-02 灯光质量与 q0 性能边界（视觉与性能两部分；性能已完成，视觉见 4.1）

### 4.1 视觉问题清单与修复

**取证方式**：`tools/probe_p82_lights_visual.gd`（windowed，6 模式 `shots`/`diag`/`nodes`/`isolate2`/`isolate3`/`qa`，全部真实运行、真实窗口 2560×1440、`--out` 可覆盖），配合同机位 before/after 批与像素量化脚本 `analyze_lights.py`/`crop_report.py`。before 取自 detached `ddcde3a` 副本 `开发产物/p82/base`（探针副本仅去掉 01 新增的 `IsleCottage.probe_skip_batch` 三行，不触碰渲染），after 取自 HEAD；两批同机位、同分辨率、同画质默认值。

**逐项结论（任务书 3.1 七个子项）**：

| 子项 | 结论 | 关键数字 | 证据 |
| --- | --- | --- | --- |
| 门廊灯 glow 近景过曝 | P8.1 遗留项；本轮**未改 glow 参数**（改它需重拍整条门廊光照链），改为如实量化现状并与 before 同机位对照；01 阶段误判为「门廊/窗光白斑」的大光团经确定性定位实为**一层吊灯 halo**（见 (a)） | `night_porch` 同机位对照；近白像素见 `pixels_before.csv` vs `pixels_after.csv` | `02_lighting/before/night_porch.png`、`02_lighting/after/night_porch.png` |
| 室内外光照边界突兀 | **硬阶跃仍在**（(d) 双池过渡带未采纳，见下），本轮未恶化 | 门洞边缘梯度 day 4.62 / night 5.13，窗边 11.06 / 9.80（与 02 前基本一致） | `pixels_after.csv`、`after/day_door_inside.png`、`after/night_door_inside.png` |
| 壁炉对周边表面产生可辨识暖光 | **通过**：(b) 后炉台/地面/近墙无裁切、暖光保留 | hearth p99 day 208.0 / night 219.6（clip=0）；固定炉台 box 平均亮度 night 93.1→92.4（暖光未崩塌）、day 128.9→118.9 | `after/day_fire_low.png`、`after/night_fire_low.png`、`pixels_after.csv` |
| 吊灯/台灯/落地灯暖光 | **吊灯已修**：(a) 把一层/阁楼吊灯 halo 纳入昼夜调光（白天只剩微光点、夜间回升），台灯/落地灯沿用 P8.1 灯罩 glow + 解析点光（本轮未改） | 右上 ROI 近白 42,309→0、均值 191.6→125.5（−34.5%） | `after/night_chand_near.png`、`after/day_room_wide.png`、`pixels_after.csv` |
| 码头灯/船灯灯罩、照明与切换 | 本轮未改（P8.1 已验收）；夜景整岛可读性复测通过 | `night_island_lights` near-white 0、clip 0.46%；码头/船灯灯罩与光锥可辨 | `after/night_island_lights.png`、`pixels_after.csv` |
| 与冬季白化/积雪/雨天湿润协调 | 本轮未改材质；同机位冬/雪/雨实测无异常偏色或过曝 | hearth_p99 208.6 / 210.5 / 207.6（clip=0）；窗边梯度 11.02 / 8.33 / 9.53 | `after/winter_day_room.png`、`after/snow_day_room.png`、`after/rain_night_room.png` |
| q0 低画质仍能看出主要灯光 | **通过**：q0/q2/q4 三档真实拍摄 | `night_fire_low` p99 q0=124.3 / q2=130.0 / q4=136.7（clip=0），q0 仍可辨炉火与暖光 | `02_lighting/qa/`（6 张）、`pixels_qa.csv` |

**没有用「提高 glow 强度」或「灯罩自发光」冒充局部照明**：本轮唯一照明类改动是 (a) 把吊灯 halo 反向**收小**并纳入昼夜调光、(b) 把壁炉解析光槽能量**下调**（1.50→1.05）——两者都是减少过曝方向；灯罩 `self_lit` 语义未动。

#### (a) 室内吊灯光晕：近景白色光斑收放（提交 `ca22d08`）
- 根因：一层吊灯 halo（`halo r=1.10`，位于 `(1.45, in_top-0.62, 0.80)`）距 `room_wide` 机位约 1.5 m，`Glow` 后处理把它放大成占据画面上部约 1/4 的白团；且它不受昼夜因子影响（白天也全亮）。
- 修复：`scripts/cottage.gd` 的 `_context` 新增 `"interior_halos": []`，一层/阁楼吊灯 halo 基准 size 1.10→0.60、0.95→0.60，基准色 (2.2,1.5,0.85)→(1.25,0.82,0.42)，并入 `interior_halos`；`scripts/main.gd` 的 `_update_lighting()` 逐帧按 `lanternI` 写回 `albedo=(1.25,0.82,0.42)*ihf`、`scale=(ihs,ihs,1)`，其中 `ihf=clamp(0.02+lanternI^1.6*0.95,0,1.2)`、`ihs=clamp(0.30+lanternI*0.70,0.30,1.0)`。
- 效果（同机位 `room_wide`，右上 ROI `x∈[1900,2560), y∈[150,900)`）：仅 01 修复时近白 26,436 → 含 (a) **0**；HEAD 重拍同 ROI：base 42,309 → after **0**，`min>245` 2,913→0，ROI 均值 191.6→**125.5（−34.5%）**；q0/q2/q4 三档同为 0。
- **刻意收敛说明**：夜间 `scale` 上限 1.0 使吊灯光晕半径从 1.10 收到 0.60 m，这是为了近景不糊屏；`night_chand_near` 证明灯泡与灯罩本体仍清晰、暖光仍在（不是「把灯调暗了事」）。

#### (b) 壁炉解析光槽近距离过曝（提交 `befdb0f`）
- 修复：壁炉光槽 `energy 1.50→1.05`、`range 5.0→6.0`，**位置与池归属不动**（`(-2.200,1.100,-2.300)` 室内池，01 几何探针 G8 把它钉死）。
- 效果用**同一次运行内的新旧参数 A/B**（`shots` 模式末尾调用 `_restore_old_fire_light()` 还原旧参数再拍一张，两图除本项完全相同）：`day_room_wide` 裁切像素 (max=255) **11,634→5,694（−51.0%）**、近白 (max≥250) **20,810→8,946（−57.0%）**；`night_room_wide` 裁切 **47,125→21,836（−53.7%）**、近白 **59,284→33,684（−43.2%）**；差异>2 的像素占比 day 40.5% / night 78.0%，平均 |diff| 3.42 / 8.26。
- 未走「全局调暗」或「移动光槽」路线：亮度下沉只作用于这一盏，炉台与地面暖光仍在（见上表「壁炉暖光」行）。

#### (c) 夜间「悬空加色球」：确定性归因 + **NO-GO**（提交 `4ac7f0f` 记录，不改参数）
- 现象：`night_room_wide` 稳定出现三个悬空亮黄球，屏幕坐标 ①(412,424) ②(1289,472) ③(1259,562)（2560×1440）。
- 三层确定性诊断（`02_lighting/regress/{nodes,isolate2,isolate3}_diag.log`）：① `nodes` 枚举 23 个 additive/Glow 节点，最近的 billboard 距三点 131.7 / 371.3 / 276.5 px → **排除 halo / Glow / 萤火广告牌**；② `isolate2` 把全部解析光 energy 置 0 → 三点降到 (3,10,25)/(4,11,30)/(4,12,30)（全黑）→ **是解析点光**；③ `isolate3` 逐盏关 18 盏：**唯一主力是 `L[13] kind=fireplace`（world (-1.981,9.046,-2.147)，range 6.0，energy 1.05，color (1.0,0.52,0.22)，indoor）**，关掉后 ②(88,63,40)、③(87,63,41)、①(21,17,25)，贡献 ②57% / ③63%；次为 `table_lamp`（≈8%），其余 16 盏 ≤19。
- 机制：壁炉光槽在炉膛内，石胸只遮到 local y≈2.17，再往上是无遮挡薄墙；P8.1 的 16 槽解析光**不做阴影**，所以点光在墙上直接刷出径向热点，再被 `Glow` 放大成「球」。
- **预存在性**：base(ddcde3a) 同机位同样存在（before 三点 (102,44,25)/(204,101,41)/(164,87,38)）→ **P8.1 既有、非本轮引入**；本轮 (b) 已把它从「裁切白」降为「橙色热点」。
- **裁决 NO-GO（不改参数）**：把 `range` 压到 <1.6 m 才能截断热点，等于废掉这盏灯；再降 `energy` 与 01 验收「壁炉暖光落在合理室内表面」冲突；挪光槽位置会破坏 01 探针 G8 与已验收几何；加遮挡需要阴影架构（本轮明确禁止）。→ 登记为**已知限制 L-6**（见 §9），影响面仅限夜间室内宽景/近景。

#### (d) 室内外双池过渡带（`g_indoor_band`）：**未采纳，已完整回滚**
- 方案：在 `toon.gdshader` 池选择处加房屋壳 ±0.2 m 过渡带，缓解门洞/窗边硬阶跃。
- **失败与处置**：global uniform 先落盘、`main.gd` 的 `RenderingServer.global_shader_parameter_add` 注册晚一步，导致当时另一条窗口运行出现 **4,374 条** `WARNING: Shader uses global parameter 'g_indoor_band', but it was removed at some point. Material will not display correctly.` 并每帧报错；该轮 UI 数据因此作废（wheel 已重跑干净批）。随后 `git checkout -- shaders/toon.gdshader` + 删除 `main.gd` 两处注册，全树 `grep g_indoor_band` = 0 确认回滚干净。
- 结论：**登记为未采纳**（理由：引入渲染风险且收益未验证），对应限制「室内外仍有硬阶跃」写入 §9。教训：shader global 参数必须与注册同一次提交落地，不能留中间态。

### 4.2 五档性能 A/B（方法、原始数据、结论）

**测量方法（可复现）**
- 探针：`tools/probe_p82_perf_ab.gd`（外部 `SceneTree`，窗口 1600×900，VSync 关、`Engine.max_fps=0`，记录 `preset_max_fps` 以便审计是否被人为放宽）；7 场景 × q0..q4 共 35 单元，每单元 30 帧预热 + 100 帧采样（另有 8 s soak 温度拉平），2 次往返 sweep 奇偶反向。
- 两侧：**base = `ddcde3a`（P8.1 冻结树副本 `开发产物/p82/ab_meas/base_copy`）**，**new = `befdb0f`（P8.2 冻结测量树 `开发产物/p82/ab_meas/new_wt`）**；两侧 `dirty=0`、`.godot` 导入缓存同源（同一份 250 MB 副本），避免首帧导入抖动。
- 采集：10 runs = 2 次不计时 warmup（base→new）+ 8 次计时 **ABBA**（base,new,new,base,new,base,base,new），位置平均值 4.5（平衡漂移）；每 run 前后记录 `tasklist`（pre-run Godot 进程应为空）、`nvidia-smi`（GPU 59–66 °C、时钟 idle 1365 MHz ↔ 跑动 ~1860 MHz）、`RUN_T0/T1`；全部 run `exit=0`、`exclusive=1`、`cells=35`。
- 噪声底（A/A，base vs base 4 runs）：run 级 p50 6385 / 6275 / 6337 / 6289 µs（跨 run 1.7%）；**单元级 |Δ| 中位 38 µs、均值 127 µs、p90 386 µs、max 840 µs** → 判定阈值取 **386 µs（p90）**，**773 µs（2×p90）** 视为显著。

**结果（帧时间几何均值，new−base）**

| 画质 | base 帧时间 (µs) | new 帧时间 (µs) | Δ (µs) | Δ% | 超噪声底单元 |
| --- | --- | --- | --- | --- | --- |
| q0 | 5521 | 5449 | **−72** | −1.3% | 0 |
| q1 | 5326 | 5370 | **+44** | +0.8% | 0 |
| q2 | 5974 | 6010 | **+36** | +0.6% | 0 |
| q3 | 9080 | 9127 | **+47** | +0.5% | 0 |
| q4 | 10652 | 10743 | **+91** | +0.9% | 0 |

- 逐场景 7 个几何均值差区间 **−126…+154 µs（−2.3%…+2.7%）**。
- 逐单元 35 个中 **32 个 |Δp50| < 386 µs**；逐单元 |Δ| 中位 83 µs、p90 323 µs。
- 落在 386–773 µs 的 3 个单元：fireplace q0 −528 µs、heavy_rain q2 +434 µs、winter_white q0 +570 µs —— 方向有正有负，与 A/A 中同类高方差单元一致 → 判为噪声。
- **≥ 773 µs（2×p90 显著线）的单元：0 个。**

**结论**：P8.2-02 的灯光改动（室内吊灯光晕昼夜调光、壁炉光槽近距过曝参数）**相对 P8.1 冻结树无超出噪声底的帧时间回归**（相对帧时间预算超限 0 项）。由于五档几何均值差有正有负且均在噪声底内，**不得据此宣称"灯光改动提高了性能"**，只能声明"无可测回归"。

**灯光质量一致性（同批 A/B 顺带取到的结构量）**
- 两侧激活灯数完全一致：q0 10（外 7 + 内 3）、q1 11（8+3）、q2 12（9+3）、q3 14（10+4）、q4 16（10+6），budget 10→16 —— 说明 02 的改动没有偷减激活灯数。
- Draw Calls 差 ≤2（户外 ~1838–1844、dock 471–472、snow 754–760）；`fireplace_close` 448→435（−13，对应 02(a)/(b) 的光晕与光槽参数调整）。
- 全量原始数据：`开发产物/p82/evidence/02_perf/ab/analysis_ab.txt`（含 §8–§11 判定汇总）、`perf_*.csv`、`frames_*.csv`、`logs/ab_*.txt`；方法与表格：`docs/P8_2_02_PERF_MEASURE.md` §1–§6。

### 4.3 q0 绝对 FPS 结论与限制披露

| 场景（q0） | base fps | new fps | Δ |
| --- | --- | --- | --- |
| clear_day | 145.2 | 145.1 | −0.1 |
| dock | 223.6 | 241.1 | +17.5 |
| fireplace_close | 218.9 | 247.5 | +28.6 |
| heavy_rain | 132.2 | 136.8 | +4.6 |
| heavy_snow_close | 204.4 | 205.6 | +1.2 |
| indoor | 237.9 | 222.2 | −15.7 |
| winter_white | 140.0 | 129.6 | −10.4 |
| **7 场景几何均值** | **181.1** | **183.5** | **+1.3%（噪声内）** |

- **P8.1 遗留的 "q0 绝对 FPS ≥ 170" 门：本轮仍未达成**，如实登记。q0 下 clear_day 145、heavy_rain 132–137、winter_white 130–140 三个场景明显低于 170；dock / fireplace_close / indoor / heavy_snow_close 在 205–247 之间达标。
- **与 P8.1 历史数字不可直接比较**：P8.1 记录 heavy_rain_q0 = 166.1 fps，本轮同场景 132.2（base）→ 136.8（new），差 ~20%。原因是机器当前状态（后台占用、GPU 温度/时钟、显示驱动/窗口合成状态）与 P8.1 采样时不同；本轮 A/A 噪声底与 ABBA 位置平衡只保证**同一时段内的相对比较**有效。因此本条**只作相对判据**，既不能用来宣称 P8.1 达成，也不能用来指控 P8.2 造成回归。
- 归因边界：本轮灯光改动相对噪声底无可测帧时间代价（§4.2），故 q0 绝对值的差异**不能归因给 P8.2**；q0 绝对门未达属**预存在性能天花板**（与 P8.1 §6.7 / D15 一致）。
- 未测：GPU 时间线（无 marker/GPU 计时，只有墙钟帧时间与 `Performance` 代理）；p99 仅作参考；单 GPU 单显示器。

**本节提交**
- `f9123a4` P8.2-02：五档画质性能 A/B 可信测量（`tools/probe_p82_perf_ab.gd` 565 行 + `docs/P8_2_02_PERF_MEASURE.md` 213 行）。
- `76787bf` P8.2-02：性能报告小节编号与过时 q0 数字修正（仅 docs，3 行）。
- 冻结测量树说明：A/B 的 new 侧固定为 `befdb0f`；其后提交（wheel 的滚轮 UI 1 行 + 探针、lighting 的探针输出目录与 NOTES、本报告）**均不进渲染/场景路径**，故测量口径不受影响（已在 `P8_2_02_PERF_MEASURE.md` §1 写明）。

## 5. P8.2-03 强风 CPU 性能调查（已完成，证据齐全）

### 5.1 Profiling 方法与采样口径
- **先证伪再优化**：P8.1 报告的「强风 CPU 侧 +1.93 ms」来自 `Performance.TIME_PROCESS`。实测该 monitor 在窗口模式只返回 **15–18 µs**、headless **17–18 µs**，而同 run 真实帧间隔是 **5.8–6.2 ms（窗口）/ 1.47–2.45 ms（headless 五轮 p50）**（差 100–350 倍）；同一实现跨轮给出 25.7 ms→42.4 ms 跳变；new/legacy 两组 tp 中位逐轮几乎相同（15/16/17 µs），分辨不出实现。→ 该 monitor 不测帧 CPU 总量也不测增量，**不能作 A/B 判据**。
- 改用双口径：**墙钟逐帧间隔**（frame_us，采样结束一次性写盘避免格式化开销）+ **GDScript 分段计时**（5 段：风向/阵风、落叶参数、冬季落叶门控、萤火抑制、秋千；`Time.get_ticks_usec` 差值，默认关闭时零开销）。
- Harness：`--p82windcpu`（`main.gd` `_run_p82windcpu()`），固定 q2、`--fixed-fps 60`、VSync 关、`Engine.max_fps=0`、模拟暂停、日期 2026-10-20 22:00、机位 `_p8_camera_tree()`；三阶段 calm（clear 且风强制归零）/ wind（strong_wind）/ typhoon（台风）；**同一 build 内 new / off（临时关三项优化）/ legacy（P8 阶段 7 旧实现）交替**，轮次顺序与 impl 顺序都按奇偶翻转；每段 settle 30 帧后采样 120 帧，9 轮。
- 最终数据取自 `run_godot.sh` v2 串行器的**独占窗口**（日志含 `[run_godot] exclusive window`）；同时用 headless 交叉验证 CPU 侧。

### 5.2 热点定位（优化前，window r1，每帧中位 µs，n=120/phase/impl）
| phase | impl | 合计 | 风向/阵风 | 落叶参数 | 冬季门控 | 萤火抑制 | 秋千 |
|---|---|---|---|---|---|---|---|
| calm | new | 59.0 | 2 | 16 | 0 | 32 | 8 |
| calm | legacy | 30.5 | 2 | 8 | 0 | 12.5 | 8 |
| wind | new | 71.0 | 2 | 15.5 | 0 | 32 | 20 |
| wind | legacy | 34.0 | 2 | 9 | 0 | 13 | 9 |
| typhoon | new | 67.5 | 2 | 14 | 0 | 32 | 19 |
| typhoon | legacy | 34.0 | 3 | 7 | 0 | 14 | 10 |

排序：**萤火抑制 +19 µs > 秋千 +11 µs > 落叶参数 +6.5 µs**；风向/阵风段 ≤2 µs 可忽略；冬季落叶门控在冻结日期下根本不执行（季节权重变化阈值 + `_season_timer` 使 `_update_season` 每帧提前返回）。根因一致：逐帧重算/无条件写属性/临时容器分配（萤火每帧重建 activity Dictionary 并写 4 个节点/材质属性；落叶每帧重建 `wind_leaf_params` Dictionary；秋千每帧新建 3 个临时容器）。

### 5.3 优化实现与等价性验证
1. **落叶参数缓存**：`wind_leaf_params(wv, wd)` 只在 `wv` 变化 >0.0005 或风向平方距离 >2.5e-7 时重算——0.0005 正是下游写 `leaf_pm.direction/gravity` 的既有阈值，输入未超阈值时重算结果本来也不会被写出 → 输出序列完全一致（探针 A4/B3）。
2. **萤火抑制**：`firefly_wind_activity(weather_f)` 只在 `weather_f` 变化 >0.0005 时重建；`emitting/amount_ratio` 仅在发射态翻转或 ratio 变化 >0.002 时写；`emission_box_extents`（>4e-6）、`speed_scale`（>0.002）、`albedo`（RGB 各 >0.002）分别门控；`lifetime` 保留原 0.05 阈值（避免误触发容量重置）。（A5/B4–B9，含台风归零、晴夜↔强风 30 次切换不滞后）
3. **秋千容器复用**：新增 `swing_wind_targets_into` / `swing_spring_step_into`，运行时写进两个常驻容器；原纯函数改为"新建容器→调 _into"的薄包装，故 `probe_p81_wind.gd` 的 117 条纯函数断言仍在测同一份实现。数学逐位一致（<1e-12），夹紧/弹簧状态保留（A1/A2/A6/B10–B13）。
- 等价性探针 `tools/probe_p82_wind_cpu.gd` **PASS 23 / 0 fail**（A1–A6 纯函数等价，B1–B13 真实场景门控/弹簧/夹紧/无瞬移/风向反转/台风归零/30 次晴↔强风切换）。

### 5.4 新旧版本 CPU / frame_ms 对照（同一 build 交替 A/B，r5 独占窗口）
| phase | impl | p50 µs | p95 µs | 5 段合计 µs | 萤火 | 落叶 | 秋千 |
|---|---|---|---|---|---|---|---|
| calm | new | 5857 | 8375 | 41 | 17 | 12 | 8 |
| calm | off | 6231 | 9193 | **64** | 33 | 18 | 8 |
| wind | new | 6236 | 9233 | 47 | 16 | 10 | 18 |
| wind | off | 5830 | 8782 | **78.5** | 33.5 | 16 | 25 |
| typhoon | new | 6241 | 9407 | 43 | 16 | 9 | 16 |
| typhoon | off | 6000 | 8661 | **75** | 33 | 15 | 23 |

- 归因（new−off）：calm **−22**（萤火 −16、落叶 −6）、wind **−30.5**（萤火 −17.5、秋千 −7、落叶 −6）、typhoon **−30**；r4 复现 run 为 −19/−22/−20，符号与量级一致（r5 机器空载绝对值更大）。
- **强风视觉系统真实成本 ≈41–47 µs/帧**（窗口帧 5.9 ms 的 0.69–0.75%；headless r5 calm/wind 30–38 µs，r1 wind/typhoon 段 65 µs — 与机器状态/旧实现相关），优化后同 run 未优化态→new 为 **−35.9% / −40.1% / −42.7%**（calm/wind/typhoon），相对 P8 旧实现（new−legacy 分段）为 −30.5% / −33.8% / −36.3%。
- new−legacy 帧级配对中位：calm −291 µs / wind +28 µs / typhoon −206 µs（sd 714–1154 µs）→ **P8.1-05 视觉增强没有可测帧时间代价**；帧级 A/B 只能作"无回归"上界检验，20–30 µs 量级必须用分段计时判。
- 视觉：after 12 张（最终 build 重拍，`03_wind/after_wind_shots/`）与 P8.1 before 逐张比对，构图/天气/落叶密度流向/秋千姿态/萤火可见量一致，秋千无穿模；差异仅分辨率与粒子随机相位。

### 5.5 验证
| 探针 | 结果 |
|---|---|
| `probe_p82_wind_cpu.gd` | **PASS 23 / 0 fail** |
| `probe_p81_wind.gd`（117 条，未改阈值） | **PASS 117 / 0 fail** |
| `probe_p8_ecology.gd` | PASS |
| `probe_p8_season.gd` | PASS |
| `--selftest` | 73/73 |
| `--headless --check-only --script res://scripts/main.gd` | 无 SCRIPT ERROR |
- 未改：fx.gd、isle_weather.gd、shaders/、灯光段、秋千几何、任何阈值/测试常量；未向 `开发产物/p81/**`、`p8/**`、`发布/`、`构建输出/` 写文件（`find ... -newermt` 验证为 0）。

### 5.6 限制披露
1. 分段计时分辨率 ≈±1 µs；legacy 段仅 5–13 µs，噪声占比高，故归因以 new−off（同一 build）为准。
2. 帧级 per-round 配对差 sd 0.7–1.2 ms（窗口）/ 0.2–0.5 ms（headless），远大于 20–30 µs 被测效应 → 帧级只证"无回归"，不量化收益；独占窗口只排除其它 Godot 引擎，不排除同机其它进程，故两次 run 绝对帧时间差 ~7% 属机器状态差异。
3. 机器存在 5–15 µs/帧 run 间漂移（legacy 自身可漂 ~10 µs），这正是选择"同一 build 内交替 A/B"而非"改前改后两次 run"的原因。
4. `winter_leaf_gate` 段在本 harness 下恒 0：模拟暂停+固定日期时季节更新每帧提前返回，该逻辑只在季节切换执行一次，不是每帧成本 → 未做优化。
5. 未采用"4 Hz 更新+插值"：落叶参数段仅 10–15 µs，插值会引入相位误差与秋千/萤火视觉风险，收益远小于按需写入，按最小增量原则放弃。
6. Godot 4.7.2 无逐帧内置 CPU profiler，故用分段计时+墙钟；未引入外部 profiler。强风 **GPU/渲染侧**成本不在本任务范围。
7. headless 日志中的 `_save_to_cache` / `Failed to open user://logs/...` 是本机 `user://` 写入受限的既有环境噪声，不影响测量。
8. **串行器独占标记的口径降级**（见 §1.4）：本项数据采集于 v3 修复前，`exclusive window` 只证明持锁；因此本项结论不依赖跨 run 绝对帧时间，而依赖同一 build 内 new/off/legacy 背靠背交替（同 run 内受同一环境漂移影响，归因稳健）。若需更强证据，应在 v3 下重跑，成本约 15 min，本轮未重跑（时间预算用于 P8.2-02 五档 A/B 与 P8.2-06）。
- 专项笔记：`docs/P8_2_03_NOTES.md`；证据：`开发产物/p82/evidence/03_wind/`（window/headless CSV、analysis_optab.txt、compare_before_after.txt、after_wind_shots 12 张、各 log）。

## 6. P8.2-04 冬季细节与跨季节稳定性（已完成）

### 6.1 截图审查结论（先只读审查，后决定改不改）
- **裸枝与鸟脚粗细比例：合理，不加粗。** 5 个冬季专用栖点所处枝径 0.630 / 0.311 / 0.345 / 0.345 / 0.316 m，海鸥脚掌实测 0.114 m（legs 网格），比例 2.73–5.54 倍；2.4–2.47 m 特写（fov 30，投影 1088 px/m）实测脚掌 ≈124 px、wb3 枝径 ≈375 px ≈ **3.03:1**，两只脚掌完整站在枝面上、无悬空。按任务书"只有近景截图证明比例不合理才修改"的要求，**不改模型**（加粗会连带改变栖点贴面与世界尺度规范）。
- **5 个冬季栖点真实枝面**：`probe_p82_eco_geom.gd` **135 checks / 0 FAIL**；修复后 wb4 足部区净空 −0.0154 → **+0.1125 m**，贴面偏差 0.0000、内插 0.0000、离地 8.02 m、距离 wb3 1.974 m。
- **屋前五朵红花**：解析高度场 raycast 与花基误差 **0.000 m**，坡度 6.2–7.6°（阈值 18°），悬空/埋根 ≤0.019 m，路缘 0.88–2.33 m，门距 3.62–5.73 m，最小间距 1.08 m —— 全通过，**不改地形/模型**。

### 6.2 实际修改与理由（只改一处）
- `scripts/world.gd` 单点修复（429da59，+7/−1）：`winter_local[4]` (-0.777,7.610,2.267) → (-0.9066,7.7154,2.5349)（世界 (-11.807,15.583,6.735)，树基 (-10.9,7.868,4.2)，同枝 t 0.750→0.835、位移 0.316 m），normal/facing/slope(22.1°) 保持不变；栖点名 `winter_branch_4` 与 kind `winter_branch` 未改。
- **未改 `fx.gd`**：使用率已健康（见 6.3），按任务书"优先调合法目标权重/冷却"的要求先验证现有权重是否失衡，结论是失衡不存在，故不动；也**未**改 `main.gd`/`isle_season.gd`/`cottage.gd`/shaders，未瞬移、未绕状态机。

### 6.3 裸枝自然使用率与候选权重（固定种子 soak，8 轮冬季）
| 项 | 实测 |
|---|---|
| 自然停栖总次数 | 31 次 |
| 落在 5 个冬季裸枝点 | 12 次 = **38.7%** |
| 逐点分布 | {wb0:3, wb1:3, wb2:1, wb3:2, wb4:3}，used **5/5**，max/min = 3/1 |
| 候选权重份额（诊断实测） | 41.5% |

结论：使用率与权重份额同量级（38.7% vs 41.5%），无系统性冷落/垄断，**无需调整权重或冷却**。

### 6.4 跨季状态一致性
- **秋→冬**：树冠 0/76、叶片 cards 0/80、红花 5/5 仍可见（scale=1.000）、落叶发射停止、冬季栖点预约建立且旧栖点关闭；鸟类起飞无瞬移。
- **冬→春**：树冠 73 = round(76×0.96)、cards 69 = round(80×0.86)、红花隐藏、花瓣发射恢复、冬季预约**零残留**。
- **快速跳季 6 跳 / 跨年 2035–2037 / 暂停 180 帧 + 恢复 300 帧**：状态一致，无预约泄漏、无重复占位。

### 6.5 固定种子跨季 soak
- `probe_p82_eco_soak.gd` **PASS 1407 / 0 FAIL**（8 轮秋冬春 + 跳季 + 跨年 + 暂停恢复）。
- FINAL：teleports=6（**全部为 boot 初始落座，各阶段增量断言 0**）、season_evictions=12、cap_fallbacks=0、no_slot_skips=0、conflicts=0。
- 回归：probe_p7v2_perch 265/0、probe_p7v2_bird 681/0、probe_p81_tree_bird 149/0、p8_ecology 41/0、`--selftest` 73/73。

### 6.6 修复前后视觉对照
- 修复点位 4 m 同机位对（before=base 副本，after=当前树）：wb4 两次都由**自然停栖**命中（before 8254 帧/137.6 s，after 9456 帧/157.6 s）——before 鸟落在旧点、足部与次级枝相交；after 落在新点、枝面干净。文件：`开发产物/p82/04_winter/shots/`（8 张 2560×1440 + zoom2x）。
- 2.4 m 多方位特写：**两次均未在 18000 帧（≈310 s）内自然命中 wb4**，按预定回退规则落到 wb3（未被修复点）——该组仅作**比例证据**，不作 before/after 证据（如实披露，不包装）。文件：`开发产物/p82/04_winter/closeup/{before,after}/` 各 5 张。
- 同点像素差（maxdelta>6）：side1 12.58%、side2 13.54%、axis1 9.86%、axis2 35.40%、context3m 22.31% —— 差异来自海水/云动画与飞行海鸥姿态，**未**用作修复效果证据（同口径 wb2 仅 1.42%/1.47%）。
- 目录实况（独立审计核对）：`closeup/{before,after}/` 各含 7 个 PNG = 5 张 v2 有效 + 2 张 v1 作废（v1 已改 `_INVALID` 前缀）+ 另 4 张 `_crop` 局部裁切（用于像素量化）；因此目录内 PNG 数多于「各 5 张」的表述。
- 本次审计 IA6：halo z=-2.420 在 before_geom.log 无独立记录（G5 count=0 是探针自身缺陷，NOTES 已披露），其数值出处为 `scripts/cottage.gd` 与 `docs/P8_2_01_NOTES.md`。

### 6.7 限制披露
1. 2.4 m 特写未自然命中修复点（见 6.6），修复点位的视觉证据依赖 4 m 自然停栖图。
2. closeup v1（19:35/19:37）与另一模块 19:37 的运行存在并发窗口 → 该轮作废，不作任何证据。
3. 单 GPU / 单显示器 / 无触屏环境；soak 为 `--fixed-fps 60` 的逻辑断言，**不是真实帧时间**（真实帧时间由 P8.2-06 的 30 min 窗口 soak 承担）。
4. 地形无碰撞体，红花/栖点用解析高度场步进替代 raycast（P8.1 既有做法）。
5. 预约表 radius 声明 0.55 m 与实际枝半径 0.158–0.315 m 的既有差异未改（会改 P8.1 断言口径，属本项边界外）。
- 专项笔记：`docs/P8_2_04_NOTES.md`；证据：`开发产物/p82/04_winter/`。
- 提交：`429da59`（world.gd 修复）、`0447c0f`（探针 6 个 + NOTES）。

## 7. P8.2-05 日期时间滚轮窗口端到端（已完成，含未验证项披露）

**起点**：P8.1 已有 headless 82/82 与窗口 82 项（80 pass / 2 warn / 0 fail），但 U-02…U-12 共 11 项未闭环，且 UI10 帧时间用了 `Performance.TIME_PROCESS`（windowed 下恒为常量，数据不可用）。生产码 841 行 `scripts/ui_datetime_wheel.gd` **未重写**，本轮生产码只改 1 行（见 §7.5）。

**最终干净批次（20:26:12–20:27:11，独占窗口确认 20:26:15 / 20:27:07）**

| 套件 | 结果 |
| --- | --- |
| `probe_p82_datetime_behavior.gd`（窗口） | **87 项：80 pass / 6 warn / 0 FAIL / 1 skip**，10 图，47.8 s |
| `probe_p81_datetime_wheel.gd`（headless） | **82/82 PASS** |
| `probe_p81_datetime_wheel_ui.gd`（窗口，UI10 重写后） | **82 项：80 pass / 2 warn / 0 fail**，9 图 |
| `probe_p82_datetime_dpi.gd`（窗口） | 12 项：10 pass / 2 warn |

| 未验证项 | 本轮验证方式 | 结果 | 证据 |
| --- | --- | --- | --- |
| U-02 帧时间可信度 | 先证明 `Performance.TIME_PROCESS` 在 windowed 下 120 帧仅 2 个唯一值（**不可用**），改用**帧间隔墙钟采样**重写 UI10：关/开各 12 对交替，A/A（关/关）作噪声底 | 关/开 p50 中位 6.434/6.801 ms；**Δp50 中位 +0.400 ms**（均值 +0.380±0.098、95% CI 上限 +0.572、正号 11/12）；A/A |Δp50| 中位 **0.729 ms**、p95 1.302 ms；Δdraw **+92**（1887→1979）、Δobjs **+649** → 按三层口径判 **WARN（可测但不可分辨）**，不冒充 PASS | `05_wheel/_final_batch_console.txt`、`probe_p81_lights` 同批日志、`docs/P8_2_05_NOTES.md` §3.3 |
| U-03 高 DPI / 窗口尺寸 | 4 档窗口尺寸 × 3 档 `content_scale_factor`（k=0.800/1.000/1.200/1.600 组合）；检查面板在窗内、列在滚轮内、点击命中 | **PASS**：面板恒在窗内、命中全对；**真机 OS 缩放未验证**（模拟 `content_scale_factor` 1.5/2.0 时 `visible_rect` 缩小导致的“面板不在窗内”已判定为模拟假象，不能在真机上代表缺陷） | `probe_p82_datetime_dpi.gd`、`05_wheel/dpi/` |
| U-04 触摸 | 合成 `ScreenTouch`/`ScreenDrag` 事件：点击日期、拖动小时列 | **PASS**（合成触摸能改值并收敛）；**无真机触屏**，已披露 | `probe_p82_datetime_behavior.gd` U-04 段、10 张 png |
| U-05 手感（吸附/惯性/阈值/橡皮筋） | 解析解对照：吸附 47 步 / 0.392 s（理论比值 1.00、超调 0）、甩动 2.2/6.0 行·s⁻¹ 滑行比 0.95/1.01、惯性阈值边界 1.3 行/s、年列橡皮筋 0.25 行 22 步、**真实鼠标拖 1 行 = 10:00→11:00** | **PASS**；并修掉一个**探针注入伪影**：合成 `MouseMotion` 不移动 OS 光标会被真实刷新事件重置，改为“只 `warp_mouse` 让引擎产生真实 motion”后 EMA=0.401、release pos=11.0000、值 +1 稳定 | `05_wheel/`、`docs/P8_2_05_NOTES.md` §6.2 |
| U-06 TAB/键重复 | TAB 逐列前进 5 列 + ←/→ 夹取 + 第 6 次 TAB 离开滚轮 | **PASS** | behavior U-06 段 |
| U-07 并发面板 | 5 面板同开 + 并发热键 + 焦点保持 | **PASS** | behavior U-07 段、截图 |
| U-08 跨午夜 | sim 模式自然跨越（23:59:59→00:00:05、跨月、跨年、闰日）+ 现实模式同步注入 | **PASS**（sim 自然跨越）；**现实模式为同步注入**，无法在有限时间内真等待跨午夜 → WARN 并披露（`main.gd` 为禁区） | behavior U-08 段 |
| U-09 长时节点数 | 60 次开合 + 200 次交互：hud 120→120、静态 1381→1381、连接数全不变、objects 2326→2298、内存 +1.21 MB；1200 帧长跑 | **PASS**（无节点/连接泄漏） | behavior U-09 段、`05_wheel/probe_p82_datetime_behavior_u09_*.png` |
| U-10 极端年份/闰年 | 0001/9999 边界、2100-02-29→02-28、2001-01-31 月+1→02-28 | **PASS** | behavior U-10 段 |
| U-11 失焦/多显示器 | 失焦/最小化后恢复；多显示器 | 单屏 **PASS**；**第二物理屏 SKIP（无硬件）** → 已披露 | behavior U-11 段 |
| U-12 键盘重复率 | 长按 ↑/↓ 的 echo 守卫（重复事件不叠加位移） | **PASS** | behavior U-12 段 |

**§7.5 本轮改动的生产码（唯一 1 行）**
- `scripts/ui_datetime_wheel.gd`：`end_drag` 里的 `1.2` 字面量 → 引用既有的 `FLICK_THRESHOLD` 常量（**零行为变更**，属 P-4 常量去重）。`0.67` 轻阈值**未采纳**：无复现证据、属手感设计决策，且改动会使本轮全部手感断言基线失效，已保留常量作为调参入口。

**§7.6 明确未做（如实披露）**
- 真机高 DPI（OS 缩放）、真机触屏、第二物理屏、真实等待跨午夜、GPU timestamp 级性能测量。
- 性能门若要求 0.3 ms 级判定：本机条件不足（需独占全屏 + 30 对以上 + GPU timestamp）。故 U-02 结论保持 **WARN**，不落 PASS。

**§7.7 提交**
- `56bfbb1` P8.2-05：滚轮窗口端到端验证 + UI10 帧时间可信重测（6 files / +3047 −49；生产码 1 行 + 探针 4 个 + `docs/P8_2_05_NOTES.md` 523 行）。
  - 说明：`tools/probe_p82_datetime_frame.gd` 原文件不可恢复（从未入库、无 blob），本轮按同口径**等价重写**并已在 NOTES §1.4 标注；其指标不进任何性能结论（性能以 UI10 为准）。

## 8. P8.2-06 全量回归与发布

### 8.1 自测与专项探针矩阵（预存在失败 vs 本轮新增失败分开登记）

**台账**：`cd 开发产物/p82 && bash final_regression.sh`（本 run 另加 `--windowed --long`）。RUN_ID `20261022_205425`，控制台日志 `开发产物/p82/final_run_windowed_205425.txt`，机器可读台账 `开发产物/p82/final/20261022_205425/regression.csv`（列：`name,mode,rc,expected_fail,status,fail_count,counts,log`），每个探针独立日志在同目录，历史证据先备份到 `evidence_backup/`。**本 HEAD = `4ac7f0f`（代码冻结点）。**

**A. 自测与语法**

| 项 | 结果 |
| --- | --- |
| `--headless --path . -- --selftest` | rc=0，全部 PASS（分母 **75/75**，P8.1 为 73/73，新增 2 项来源见 PRE-5） |
| `--headless --check-only --script res://scripts/main.gd` | rc=0（语法/类型检查通过；注意引擎选项必须在 `--` 之前） |

**B. 历史专项探针（P8 / P8.1）**

| 探针 | 结果 | 登记值 | 判定 |
| --- | --- | --- | --- |
| probe_p8_calendar | checks=2672 fail=0 | — | ok |
| probe_p8_weather | checks=3145 fail=0 | — | ok |
| probe_p8_moon | rc=0 | — | ok |
| probe_p8_season | checks=114 fail=0 | — | ok |
| probe_p8_ecology | checks=41 fail=0 | — | ok |
| probe_p7v2_perch | pass=265 fail=0 | — | ok |
| probe_p7v2_bird | pass=681 fail=0 | — | ok |
| probe_p7v2_light | pass=66 **fail=1** | 预存在 1 | ✓ expected-fail（PRE：路灯相对地形高度须 ∈[1.2,2.6]，实测 2.84） |
| probe_p7v2_flycam | pass=76 **fail=7** | 预存在 7 | ✓ expected-fail |
| probe_cottage6 | pass=26 **fail=5** | 预存在 5 | ✓ expected-fail（含 attic 灯在 light_sources 中 found 0 等） |
| probe_lights_p7v3 | rc=0 | — | ok |
| probe_p81_tree_bird | pass=149 fail=0 | — | ok |
| probe_p81_whiteness | checks=34 PASS(WARN) | — | ok |
| probe_p81_wind | pass=117 fail=0 | — | ok |
| probe_p81_datetime_wheel | pass=82 fail=0 | — | ok |
| probe_scale_house_p7v32 | checks=252 pass=245 **fail=7** | 预存在 7 | ✓ expected-fail（探针期望 11 个光位，P8.1-06 双池聚合后为 10；base 副本逐字复现） |

**C. P8.2 新增 headless 探针**

| 探针 | 结果 | 说明 |
| --- | --- | --- |
| probe_p82_eco_geom | pass=135 fail=0 | 5 冬季栖点 + 5 朵红花几何 |
| probe_p82_wind_cpu | pass=23 fail=0 | 强风三项优化的等价性/门控正确性 |
| probe_p82_eco_soak | pass=1405 **fail=2** → `nondet` | 两条 usage 统计断言在 `--fixed-fps 60` 下确定性失败（33 事件、wb2 未采样），实时 headless 下 5/5 PASS；登记 **NONDET-P82-1**，断言与阈值都不改，见 `docs/P8_2_TEST_RESULTS.md` §4.1 |

**D. 判定**
- 4 条预存在失败（p7v2_light 1、p7v2_flycam 7、cottage6 5、scale_house 7）的 **rc 与失败条数与登记逐一吻合**（runbook 对 `expected_fail` 做数量比对，不等即记 `FAIL-count-mismatch`）。
- **历史失败与本轮新增失败分开登记**：历史见 `docs/P8_2_TEST_RESULTS.md` §4 的 PRE-1…PRE-7；本轮唯一非预存在项是窗口探针 `probe_p81_datetime_wheel_ui` 的 1 条间歇失败（见 §8.2），生态 soak 的 2 条统计断言见 NONDET-P82-1。
- 未经当前 HEAD 复跑的旧结论一律不沿用：上述 20 个 headless 探针全部在本 HEAD 实跑。

### 8.2 实际窗口端到端

以下 7 项**不是 headless**：全部以真实窗口（1600×900 或探针自设 1440×900/2560×1440）驱动真实渲染、真实 `_process`、真实输入注入（`Input.parse_input_event` + `Input.warp_mouse`），并由 `run_godot.sh` 的独占引擎锁串行执行（每项日志首行都有 `exclusive window`）。

| 探针 | 项数 | 结果 | 说明 |
| --- | --- | --- | --- |
| probe_p81_lights | 147 | **0 失败** | P8.1 灯光专项（含 27 张图），P8.2 改动后重跑通过 |
| probe_p82_fireplace（geom） | 34 | **0 失败** | 01 修复后的几何断言（与 01 提交时同代码） |
| probe_p82_matrix_shots | 51 | **0 失败**，30/30 张 | 五档×6 场景矩阵，见 §8.4 |
| probe_p82_datetime_dpi | 12 | 10 pass / 2 warn / 0 fail | 高 DPI 与窗口尺寸矩阵；2 条 WARN 为「content_scale_factor 模拟下可见矩形变化」的模拟假象，见 §7 与 L-8 |
| probe_p82_datetime_behavior | 87 | 80 pass / 6 warn / **0 fail** / 1 skip | 滚轮交互行为（吸附/惯性/TAB/并发面板/跨年/极端年/节点计数），见 §7 |
| probe_p82_lights_visual（shots） | — | 0 fail，8 WARN | 8 条 WARN 全是本机 `settings.cfg (error 12)` 环境噪声（PRE-4 类） |
| probe_p81_datetime_wheel_ui | 82 | 79 pass / 2 warn / **1 fail** | **已知非确定性项**，见下 |

#### 8.2.1 `probe_p81_datetime_wheel_ui` 的 UI2 拖动断言：非确定性 + 预存在（PRE-8）

**现象**：断言「在计日列慢速拖动 1 行，日期应 +1」偶发不成立，且失败时的落点每次不同：

| 运行 | 结果 | 备注 |
| --- | --- | --- |
| 20:26:12 干净批（同一 HEAD 代码） | day 22 → 23 | **PASS**，整轮 82 项 80/2/0 |
| 21:00:54 runbook D 段 | day 22 → **16** | FAIL |
| 21:39:35 复验第 1 次 | day 22 → **24** | FAIL |
| 21:40:35 复验第 2 次 | day 22 → **5** | FAIL |
| 21:43:56 插桩诊断（临时打点，跑完已 `git checkout` 还原） | day 22 → **22** | FAIL，见下方内部状态 |
| 21:46:23 **P8.1 基线副本 ddcde3a**（同一探针） | day 22 → **1** | **FAIL —— 基线同样复现** |

**插桩读到的内部状态**（诊断打点）：`_ema_vel=-4.892`、`mode=0`、`pos=22.000`、`anchor=22.000`、`press_y=70.00`、`last_y=42.00`。即：物理拖动位移**正好 1 行**（`70→42` = 28 px = `ROW_H`），但滚轮内部速度 EMA 被估成 **−4.89 行/秒**，远超 `FLICK_THRESHOLD=1.2`，于是 `end_drag()` 走惯性分支（mode=2）滑行，落点随 EMA 大小漂移。EMA 虚高的机制在代码里可直接读出：`ui_datetime_wheel.gd:624` 的 `inst = -((y-_last_y)/row_h)/step_dt` 使用 `_dt_since_last()`，而 `_dt_since_last()`（`:650-655`）把 dt **下限夹到 0.001 s**——当两帧运动事件被压进同一毫秒（合成注入 + 帧调度抖动时会发生），dt=1 ms 会把瞬时速度放大 25 倍。

**归属判定**：
- **不是 P8.2 引入**：在 **P8.1 冻结代码副本（`ddcde3a`，`开发产物/p82/base`）** 上用同一探针跑出同样失败（day→1），证明该行为在 P8.1 就存在。
- **不是生产代码回归**：本轮对 `ui_datetime_wheel.gd` 的唯一改动（`56bfbb1`，P-4）是把 `end_drag` 里的字面量 `1.2` 换成常量 `FLICK_THRESHOLD`，数值与行为完全相同。
- **非确定性**：同一代码 20:26 通过、21:00 起连续 4 次失败且落点各不相同 → 由注入事件的 dt 抖动而非逻辑缺陷触发，登记 **PRE-8（预存在、非确定性、仅合成注入路径复现）**。

**处置（遵守「不得为过测试删真实要求」「不无故重写 841 行组件」）**：不在冻结阶段改滚轮速度估计逻辑（属手感设计，改它需要新的手感回归证据链，超出本轮证据范围）；断言与阈值**均未修改**；作为已知限制记入 §9（L-12）与 `docs/P8_2_TEST_RESULTS.md` PRE-8。真实鼠标路径的行为验证见 §7（U-05 手感：吸附 47 步/0.392 s、超调 0、甩动滑行比 0.95–1.01、阈值边界 1.3 行/秒）。

**给下一个迭代的建议（未实施）**：把 `inst` 的 dt 下限从 `0.001` 提到约 `1/240 s`，或对 `inst` 做 `clampf(±60)`，即可消除合并事件导致的 EMA 尖峰；本轮未做是为了不在冻结前改变手感参数。
### 8.3 30 分钟长时运行（天气/跨季/UI 操作）

**命令**：`bash 开发产物/p82/run_godot.sh --path . --script res://tools/probe_p82_soak.gd -- --minutes=30 --out=<RUN>/soak`（窗口 1600×900 真实渲染；由 runbook `--long` 段以独占引擎锁启动）。**证据**：`开发产物/p82/final/20261022_205425/soak/`（`soak_2026-10-22T21-06-01.{log,csv}`、`_summary.{json,md}`）。

| 项 | 实测 | 判定 |
| --- | --- | --- |
| 时长 / 采样 | 1800.0 s（30.0 min），360 个 5 s 样本，全程 `exclusive window` | — |
| 操作覆盖 | **68 次操作，ok=68 fail=0**；quality 29、weather 19（**12/12 种天气**）、date 11（跨月/跨季/跨年）、hud 9（面板开关） | C4 PASS（quality 29/21、weather 19/14、date 11/8、hud 9/7） |
| C1 帧时间劣化 | 首窗 p95 **16.67 ms**（28490 帧）→ 末窗 p95 **16.67 ms**，上限 22.83 ms | PASS |
| C2 节点增长 | nodes 1546 → 1554（**+8**），上限 +81 | PASS |
| C3 FPS 下限 | 最长连续 <20 fps 采样 **1** 次（阈值 3），仅出现在 t=0 s 启动帧 | PASS |
| C5 断言 | 0 项失败 | PASS |
| C6 状态 | `isle_valid=true in_tree=true mode=1` | PASS |
| 状态增量 | orphan **+62**、VRAM **+296.7 MB**、mem_static **+22.2 MB** | 观察项（见下） |
| 结论 | `[P82SOAK] verdict=PASS`、`RESULT PASS` | PASS |

**读法说明（防止误读）**：q0/q1 档位自带 `max_fps=60`（工程预设），画质循环到 q0/q1 时 p50 变成 16.67 ms 是帧率上限所致，不是卡顿；q2–q4 段 p50 为 7.14–11.11 ms。VRAM +296.7 MB 的主要来源是画质循环把 q2→q4 的 MSAA/纹理预算抬高（q2 335 MB ↔ q4 628 MB），属设计内；orphan 节点 +62 未伴随节点树增长（dc 1844→1890、objects 稳定），登记为观察项（L-11），不作为泄漏判定。

**探针自带限制**（已写入其输出）：本结论仅代表「本次 30 分钟未发现明显异常」，不构成内存泄漏或性能无回归的严格证明。

### 8.4 五档画质场景矩阵

**命令**：`probe_p82_matrix_shots.gd`（窗口 1600×900 真实渲染）。**证据**：`开发产物/p82/final/20261022_205425/matrix/`（`shots/` 30 张 PNG、`matrix.csv`、`MANIFEST.md`、`matrix_summary_2026-10-22T21-02-18.json`、`contact_sheet.png`）。

- 组合：**6 场景 × 5 档 = 30 张，成功 30/30**（`H1_coverage PASS`），耗时 71.3 s，0 失败（`H5_no_runtime_error PASS`）。
- 每张记录：`mean_lum / max_lum / p95_lum / dark_ratio / white_ratio / draw_calls / objects / lights_active / light_budget / msaa_3d / max_fps / capture_ok`（CSV 15 列）。

| 场景 | q0 平均亮度 | q1 | q2 | q3 | q4 | 激活灯 q0→q4 | draw calls q0→q4 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| clear_day_outdoor | 139.8 | 149.1 | 149.2 | 151.7 | 153.6 | 10/11/12/14/16 | 1839（五档同） |
| winter_white_outdoor | 109.9 | 117.9 | 118.1 | 120.0 | 121.8 | 10→16 | 1842→1844 |
| indoor_night_fireplace | 52.3 | 54.4 | 55.4 | 57.1 | 58.3 | 10→16 | 439→443 |
| dock_night | 32.0 | 52.1 | 56.1 | 62.4 | 63.4 | 10→16 | 461→462 |
| heavy_rain | 94.1 | 100.9 | 100.9 | 103.1 | 104.5 | 10→16 | 1855→1842 |
| heavy_snow_close | 109.7 | 112.1 | 112.4 | 113.6 | 114.6 | 10→16 | 757→765 |

**判定（探针内建 5 条）**

| 判定 | 结果 | 说明 |
| --- | --- | --- |
| H1_coverage | PASS | captured 30 / expected 30 |
| H2_quality_visual_diff | PASS | q0 与 q4 有可测差异的场景 **6/6**（mean≥1.00 或 dc≥10 或 white≥0.0020） |
| H3_night_not_black | PASS | 夜间最低平均亮度 **32.04**（下限 12.00）@ dock_night q0 |
| H4_night_not_clipped | PASS | 夜间最高白点占比 **0.00007**（上限 0.02000）@ dock_night q3 |
| H5_no_runtime_error | PASS | 探针侧未捕获错误 |

**关键画质差异与照明有效性**：五档差异在夜间场景最明显（dock_night 32.0 → 63.4，主因 q0 只开 10 灯、q4 开 16 灯），白天场景差异小而稳定（139.8→153.6）；六场景白点占比全部 ≤0.00038（远低于 0.02 上限）→ **低画质没有靠过曝换可读性，高画质也没有裁切**。`lights_active` 五档实测 10/11/12/14/16 与 §4.2 性能侧完全一致。

**注**：矩阵运行日志里 6+8 条 `WARNING: [settings] failed to save user://settings.cfg (error 12)` 是本机用户目录写入失败的环境噪声（PRE-4 类，历史多轮同样出现），不进入任何判定。
### 8.5 冻结证据完整性复核
- 开工前快照：`开发产物/p82/integrity/frozen_p81_p8_manifest_before.txt`（`开发产物/p81`+`开发产物/p8` 共 599 个文件 sha256）、`release_exe_before.txt`（发布包 exe sha256）。
- 本轮复核（19:19 实测）：`sha256sum -c frozen_p81_p8_manifest_before.txt` → **599/599 OK，0 变更**；`开发产物/p8`、`开发产物/p81` 的冻结证据（P8 原始截图、P8.1 三组 147 张 + -06 53 张）未被本轮任何探针覆盖。
- 冻结证据目录防写措施：把 `probe_p81_lights.gd`、`probe_p81_datetime_wheel_ui.gd` 等硬编码输出目录的探针改为写 `开发产物/p82/...`（改输出路径时随提交注明，P8.1 探针断言逻辑除 UI10 采样法重写外未改）；wind 用 `--windshotsout` 覆盖截图目录。
- 历史发布包未被覆盖：`发布/休闲小岛幻境.exe` 仍为 P8.1 冻结包（117,238,104 B，sha256 `c40376ad…b668`），P8.2 正式包在冻结阶段才覆盖，且先自动备份到 `开发产物/backup/release_pre_p82/`。
- 既有证据目录 `开发产物/p82/integrity/` 里另有 `release_exe_before.txt` 与复核命令，可复跑。
### 8.6 发布包（size / SHA-256 / 版本 / 退出测试 / 自测）
### 8.7 提交、tag 与回滚命令

## 9. 未完成事项与仍存在的限制

> 口径：按「模块 × 限制」列。每条给：限制 / 影响 / 是否已在本报告披露 / 证据或复现 / 责任人（lead、lighting=01/02、wind=03+06、winter=04、wheel=05）。**未验证项一律不写成已验证**；未修的缺陷不写成已修。

### 9.1 全局 / 测量环境

| 编号 | 限制 | 影响 | 证据 / 复现 |
| --- | --- | --- | --- |
| G-1 | 串行器早期版本（v2）用 `tasklist` 判引擎退出，Windows 把进程名截断到 25 字符（`Godot_v4.7.2-stable_win64`，无 `.exe`）→ 正则永不匹配，「拿锁」≠「独占」；v3 就地重写曾让两个在跑的 bash 读到半截脚本 | 03 的计时轮次降级为「同一 build 内交替 A/B」（§5 采用的口径）；05 旧 UI10 帧时间作废并重跑（§7）；02 A/B 在 v3 之后执行不受影响。v4 追加孤儿锁回收 + `HUP` 清理，此后全部运行经该锁 | §1.4；`开发产物/p82/run_godot.sh`；各 run 日志的 `[run_godot] exclusive window` |
| G-2 | 单 GPU（RTX 2060）+ 单物理显示器（另有 Oray 虚拟显示器） | 绝对帧时间不可跨机移植；多显示器/真机高 DPI 无法真机验证 | §1.2；§7 U-03/U-11 |
| G-3 | 无触屏（`is_touchscreen_available()=false`） | 触摸结论均为桌面合成输入等价性，不代表真机触屏手感 | §7 U-04；PRE-7 |
| G-4 | **q0 绝对 FPS 门 ≥170 未达**，且与 P8.1 历史数字不可直接比较 | 只能用 A/A 噪声底判「无回归」，不能宣称性能提升 | §4.3；`docs/P8_2_02_PERF_MEASURE.md` §4.1 |
| G-5 | `Performance.TIME_PROCESS` 在本机窗口模式不可用（中位 15–18 µs vs 真实帧 ~6 ms） | 帧耗时一律改用墙钟逐帧 delta | §1.3、§5.1、§7 U-02 |
| G-6 | 环境噪声：`user://logs` 写入失败、shader cache 保存失败、Windows 证书库 ERROR 每次运行都出现 | 日志扫描需白名单；不影响退出码与产品行为 | PRE-4 |
| G-7 | P8 冻结的 46 张 1600×900 截图未重拍（任务书要求保护 P8 冻结证据） | 不能与 P8 冻结截图逐像素对比；以 P8.1 的 147 张重拍图 + 本轮矩阵为视觉基线 | P8.1 §12.8 U45 |

### 9.2 P8.2-01 壁炉 / P8.2-02 灯光

| 编号 | 限制 | 影响 | 证据 / 复现 |
| --- | --- | --- | --- |
| L-1 | 火焰仍是 3 个 `self_lit` toon 盒（P8 既有视觉语言），未引入粒子/真实 Light3D | 只解决「看不见火焰」的几何遮挡，不是拟真火焰 | §3；01 探针 G4/G6（34/0） |
| L-2 | 壁炉 halo 仍存在（0.34、色 (1.7,0.85,0.32)），未按画质档收缩 | 近景不饱和，但无逐档验证 | 01 NOTES §7.2；`01_fireplace/after/` |
| L-3 | 烟囱一层段改为墙内薄烟道：室外近看该处无可见烟囱（原来也被墙体遮挡） | 仅穿墙调试视角可见厚度差异 | 01 NOTES §7.3 |
| L-4 | `probe_skip_batch` 为探针专用静态开关，生产路径不设置 | 合批结果与 P8.1 一致，截图走合批路径 | 01 NOTES §2.3/§7.4 |
| L-5 | 阁楼段烟囱胸在旧机位被床/屋面遮挡 | 已补 `q2_attic_breast` / `day_attic_breast` 两个正对机位 | 01 NOTES §7.5 |
| L-6 | **夜间室内「悬空加色球」未修（NO-GO）**：`night_room_wide` 三点 (412,424)/(1289,472)/(1259,562)（2560×1440） | 夜间室内宽景/近景可见亮球伪影；**base(ddcde3a) 同样存在 → P8.1 既有**；(b) 已把它从「裁切白」降为「橙色热点」 | §4.1(c)；`02_lighting/regress/isolate3_diag.log`（逐盏归因到 `L[13] fireplace` 槽，贡献 ②57%/③63%） |
| L-7 | 02(d) 室内外双池过渡带**未采纳**：global shader 参数与注册时序不一致曾产生 4,374 条 WARNING | 门洞/窗边仍有硬阶跃（但 a/b 未恶化边界） | §4.1(d)；回滚后全树 `grep g_indoor_band` = 0 |
| L-8 | 白天仍有极弱室内光晕（`ihf` 下限 0.02）；阁楼夜间仅由 `night_attic*` 核查 | 白天近白像素已归零，残余不可见 | 02 NOTES 限制段 |
| L-9 | 像素量化为固定 ROI（`x∈[1900,2560)`,`y∈[150,900)`），非全帧统计 | 只覆盖主要光晕区 | 02 NOTES；`pixels_after.csv` |
| L-10 | 门廊灯 glow=1.0（P8.1 遗留）本轮**未改参数** | 门廊近景光团只做现状量化与 before/after 对照，未解决 | §4.1 逐项表；`after/night_porch.png` |

### 9.3 P8.2-03 强风 CPU

| 编号 | 限制 | 影响 | 证据 / 复现 |
| --- | --- | --- | --- |
| W-1 | 分段计时 `Time.get_ticks_usec` 分辨率 ±1 µs，legacy 段本身仅 5–13 µs | 归因必须用同 build 的 new−off 差值，不能引用单段绝对值 | `docs/P8_2_03_NOTES.md` §11.1；`analysis_optab.txt` |
| W-2 | 帧级 per-round 配对差 sd 0.7–1.2 ms（窗口）/0.2–0.5 ms（headless），远大于 20–30 µs 的被测效应 | 帧级 A/B 只能证明「无回归」，不能量化优化收益 | 03 NOTES §11.2；`compare_before_after.txt` |
| W-3 | 机器存在 5–15 µs/帧的 run 间漂移 | 因此采用同 build 内交替 A/B，而非改前/改后两次 run | 03 NOTES §11.3 |
| W-4 | `winter_leaf_gate` 段在该 harness 下恒为 0（暂停 + 固定日期使 `_update_season` 提前返回） | 该段未优化，也没有声称优化 | 03 NOTES §11.4 |
| W-5 | 未做「4 Hz 低频参数更新 + 插值」重构 | 落叶参数段仅 10–15 µs，收益远小于相位误差/视觉风险 | 03 NOTES §11.5 |
| W-6 | Godot 4.7.2 无逐帧 CPU profiler，未引入外部 profiler | 只有分段计时 + 墙钟，无逐函数归属 | 03 NOTES §11.6 |
| W-7 | 强风 GPU/渲染侧成本不在范围 | 只证明 CPU 侧 −19…−30 µs | 03 NOTES §11.7 |
| W-8 | 独占窗口只排除其他 Godot 引擎，不排除同机其他进程 | 跨 run 绝对值仍受负载影响，靠 ABBA + 短 run 抑制 | 03 NOTES §11.2；PERF §6 |

### 9.4 P8.2-04 冬季细节与生态

| 编号 | 限制 | 影响 | 证据 / 复现 |
| --- | --- | --- | --- |
| E-1 | 2.4 m 特写两次 run 均未自然命中 `winter_branch_4`（各 18000 帧超时，回退 wb3） | 足部特写证据是 wb3；wb4 的 before/after 用 4 m 机位（两侧都自然命中） | 04 NOTES 截图段；`closeup_{before,after}_20261022.log`、`shots/p82_04_perch4_actual_*` |
| E-2 | 栖点 `radius=0.55` 与实际枝半径 0.158–0.315 m 不一致（P8.1 契约值，未改） | 影响槽位容量估算与旧探针期望；贴面位置由法线 + `PERCH_FOOT_LIFT` 决定，实测误差 0.0000 | 04 NOTES；`probe_p7v2_perch` 265/0 |
| E-3 | 生态 soak 是 `--headless --fixed-fps 60` 的逻辑断言（2400 帧/轮 × 8 轮），不是真实时长 soak | 只证明状态机在加速时钟下自洽，不能替代 06 的 30 min 真实运行 | 04 NOTES；§8.3（06 的真实 soak） |
| E-4 | 地形高度用解析高度场 `World.surface_y()`（全工程无地形碰撞体），非物理 raycast | 红花断言验证的是一致性，不等价物理碰撞 | 04 NOTES；`probe_p82_eco_geom.gd` `_terrain_raycast` |
| E-5 | 特写像素差含海水/云动画与飞行海鸥姿态（wb3 before/after 差 9.86%–35.40%） | 这些百分比不能当修复证据；修复证据是几何数字 + 4 m 机位视觉对比 | 04 NOTES；`diff_v2.py` |
| E-6 | 4 m 机位鸟体仅约 200 px | 粗细判定以 2.4 m 特写（脚掌 124 px / 枝径 375 px = 3.03:1）+ 几何比 2.73–5.54:1 为依据 | `closeup/.../p82_04_feet_winter_branch_3_side1_*` |
| E-7 | **NONDET-P82-1**：两条 usage 统计断言在 `--fixed-fps 60` 下确定性失败（33 事件、wb2 未采样），实时 headless 下 5/5 通过 | 单次运行的 usage 分布不能作为「是否可用」的判据；跨模式聚合 5/5 成立，无系统性低权重（逐点 w 差 <2%） | `docs/P8_2_TEST_RESULTS.md` §4.1；`04_winter/eco_soak_v3_20261022.log` vs `final/20261022_205425/probe_p82_eco_soak.headless.log` |

### 9.5 P8.2-05 日期时间滚轮

| 编号 | 限制 | 影响 | 证据 / 复现 |
| --- | --- | --- | --- |
| T-1 | U-02 帧时间沿用 v3 干净独占窗口口径，与 P8.1 旧「UI10」口径不同 | 不可与 P8.1 逐字对比；结论只到「无回归 + WARN 口径」 | §7 U-02；`_run_p81_ui_exclusive.txt` |
| T-2 | 05 的帧时间只做噪声底内比较 | 不能宣称滚轮帧时间显著改善 | PERF §2；05 NOTES §3.5 |
| T-3 | U-03 高 DPI/窗口尺寸用四档窗口 + `content_scale_factor` 等价模型，**无真机高 DPI** | 真机缩放行为未验证；模拟下「面板不在窗内」已判为模拟假象 | §7 U-03；`probe_p82_datetime_dpi_result.json` |
| T-4 | U-04 触摸为合成输入（`emulate_mouse_from_touch`），且曾一次不等价鼠标（PRE-7） | 只证明「可操作」，不证明真机触屏手感 | §7 U-04；PRE-7 |
| T-5 | U-11 多显示器无法真机验证（单物理屏 + 虚拟屏） | 只做 restore/失焦后的状态回读 | §7 U-11；05 JSON SKIP 项 |
| T-6 | U-09 长时节点/对象波动首轮 +12/−17 未复现 | 结论只到「未复现」，不宣称已修复 | PRE-1 |
| T-7 | 未采纳「0.67 轻阈值」（`FLICK_THRESHOLD` 仍 1.2） | 属手感设计决策且无复现证据；常量保留作调参入口 | §7.5；05 NOTES |

### 9.6 P8.2-06 回归 / soak / 矩阵 / 发布

| 编号 | 限制 | 影响 | 证据 / 复现 |
| --- | --- | --- | --- |
| F-1 | 30 min soak 为窗口 1600×900 + `max_fps=60` 的稳定性观测 | 该 run 帧时间受 60 fps 上限约束，**不能当性能上限证据**；只证明长时稳定性（C1–C6） | §8.3 |
| F-2 | 画质矩阵只覆盖单分辨率（1600×900）× 单 GPU × 6 场景 | 不覆盖多分辨率/低端 GPU/兼容渲染器 | §8.4；`matrix.csv` |
| F-3 | 发布包跨机器导出复现未做（仅本机验证 TEMP 可写流程） | 异机导出环境仍未知 | §8.6；P8.1 §12.8 U48 |
| F-4 | `check_evidence.py` 的 30 min soak 门禁依赖 `elapsed≥1500 s`，短跑会记为 GAP | 短跑只能作冒烟；正式验收必须跑长跑 | `check_evidence.py`；§8.3 |

### 9.7 汇总

- **本轮已修复的产品缺陷**：01 壁炉几何遮挡（30/10→34/0）；02 吊灯光晕白天近白圆盘（42,309→0）、壁炉槽过曝（裁切 −51.0%/−53.7%）；03 强风三段按需更新（−19…−30 µs/帧）；04 冬季裸枝栖点穿模（足部净空 −0.0154→+0.1125 m）；05 滚轮硬编码阈值常量化（1 行，零行为变更）。
- **本轮明确未修 / 未验证**：02 夜间悬空球（L-6，NO-GO，P8.1 既有）、门廊灯 glow（L-10）、室内外硬阶跃（L-7）、q0 ≥170 FPS（G-4）、真机高 DPI/多显示器/触屏（G-2/G-3/T-3/T-4/T-5）、生态 usage 单次统计（E-7）。
- **纪律**：以上未验证项均给出证据或复现路径；未用「计划/代码已写/静态检查通过」替代真实验收；未降低任何断言阈值（NONDET 只登记不弱化）。

## 10. 证据索引

> 仓库：`D:/休闲小岛幻境/游戏工程`；**证据根**：`D:/休闲小岛幻境/开发产物/p82/`（git 外，不在仓库内，便于体积不受版本库影响）；冻结证据根（只读，不覆盖）：`开发产物/p81/`、`开发产物/p8/`、`发布/`。
> 所有运行必须经全局串行器：`cd "D:/休闲小岛幻境/游戏工程" && bash "D:/休闲小岛幻境/开发产物/p82/run_godot.sh" <引擎参数> --script res://tools/<探针>.gd -- <探针参数>`；引擎 `D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe`。陈旧锁：`rm -rf 开发产物/p82/.engine.lock`。
> 一键复跑：`cd 开发产物/p82 && bash final_regression.sh`（headless 全量）/ 加 `--windowed` / 加 `--long`（30 min soak）/ 加 `--release`。产物在 `开发产物/p82/final/<RUN_ID>/`（`regression.csv` + 每个探针独立日志 + `evidence_backup/`）。

### 10.1 P8.2-01 壁炉/烟囱（`01_fireplace/`）

| 证据 | 路径 | 关键内容 |
| --- | --- | --- |
| 几何断言 after | `01_fireplace/after/after_geom.log` | `[P82FP] SUMMARY checks=34 fails=0` |
| 几何断言 before | `01_fireplace/before/before_geom.log` | `checks=30 fails=10`，10 条 FAILED_ITEM：G1/G2/G2b/G3c/G4b/G5/G6×3/G8b |
| 截图 | `01_fireplace/after/`（20 张）、`01_fireplace/before/`（18 张） | 2560×1440；q0..q4_fire_front/oblique、q2_room_wide/attic_view/attic_breast/exterior_chimney/attic_chimney_side、day_* |
| MANIFEST + 像素量化 | `01_fireplace/MANIFEST.csv`、`analyze_fireplace.py` | 38 行（每行 sha256/尺寸）；13 机位对高热像素 before 0 → after 3.6–6.8 万 |
| 回归 | `01_fireplace/regress/` | cottage6 26/5（同历史）、p7v2_perch 265/0、p8_ecology 41/0、p81_tree_bird 149/0、scale_world、selftest |

### 10.2 P8.2-02 灯光视觉 + 五档性能

| 证据 | 路径 | 关键内容 |
| --- | --- | --- |
| before/after 截图（各 24 张） | `02_lighting/before/`、`02_lighting/after/`、`02_lighting/after_pre_02/` | 2560×1440 同机位；`after_pre_02` 是 02(a)(b) 之前的旧快照（保留以证明改动前后差异） |
| 像素量化 | `02_lighting/pixels_{before,after,after_pre_02,qa}.csv`、`analyze_lights.py` | 右上 ROI 近白 42,309→0、均值 −34.5%；hearth p99 / clip / 边界梯度 |
| 悬空球归因 | `02_lighting/regress/{nodes,isolate2,isolate3}_diag.log` | 三层确定性诊断；逐盏关灯贡献表；NO-GO 依据 |
| 裁切对照 | `02_lighting/crop/`、`02_lighting/report_crop/`（6 张） | day_room_wide 右上、night_chand_near、night_firewall_hotspots 的 before/after |
| q 档取证 | `02_lighting/qa/`（6 张）、`pixels_qa.csv` | q0/q2/q4 × {day_room_wide, night_fire_low} |
| 性能 A/A 噪声底 | `evidence/02_perf/aa2/` | 4 runs base-vs-base；单元级 |Δ| 中位 38 µs、p90 386 µs → 判定阈值 |
| 性能 A/B | `evidence/02_perf/ab/`、`analyze_ab.py`、`summary.md` | 8 runs ABBA（base=ddcde3a / new=befdb0f）；五档与 7 场景帧时间、draw/objects/VRAM、激活灯数 |
| 方法文档 | `docs/P8_2_02_PERF_MEASURE.md`、`docs/P8_2_02_NOTES.md` | 方法学/缓存同源/A-A 阈值/§4.1 q0 限制 |

### 10.3 P8.2-03 强风 CPU（`evidence/03_wind/`）

| 证据 | 路径 | 关键内容 |
| --- | --- | --- |
| 主判据（窗口 r5） | `evidence/03_wind/window/`、`analysis_optab.txt` | new/off/legacy 三段中位；new−off −22/−30.5/−30 µs |
| headless 交叉验证 | `evidence/03_wind/headless/` | r1–r5 CSV + 日志 |
| 归因 | `evidence/03_wind/compare_before_after.txt`、`analysis_stdout.txt` | 分段（萤火/落叶/秋千/风向/冬季门控）+ 帧级配对差 |
| 视觉/行为 | `evidence/03_wind/after_wind_shots/`（12 张）、`log_probe_p81_wind.txt`（117/0）、`log_probe_p82_wind_cpu.txt`（23/0） | 落叶/萤火/秋千/冬季裸枝 |
| 方法/限制 | `docs/P8_2_03_NOTES.md` | §5.1/§5.2/§11 限制、`--p81windperf-legacy` 与 `--p82windcpu` 开关 |

### 10.4 P8.2-04 冬季细节与跨季生态（`04_winter/`）

| 证据 | 路径 | 关键内容 |
| --- | --- | --- |
| 几何断言 | `eco_geom_20261022.log`（134/1）、`eco_geom_after_fix_20261022.log`（**135/0**） | 5 冬季栖点贴面/枝径/净空 + 5 朵红花地形/坡度/净距 |
| 栖点诊断 | `perch_diag2_20261022.log`、`perch4_cand_20261022.log`、`eco_diag_20261022.log` | 候选权重（winter_branch 份额 41.546%）、逐点 w/dist |
| 固定种子跨季 soak | `eco_soak_v3_20261022.log`（**PASS 1407/0**）、`final/<RUN_ID>/probe_p82_eco_soak.headless.log` | usage {3,3,1,2,3}；跨年/快速跳季/暂停恢复；limited 见 NONDET-P82-1 |
| 截图 | `shots/`（4 m，8 张）、`closeup/{before,after}/`（2.4 m，各 5 有效 + 2 作废） | wb4 before/after 自然命中（8254/9456 帧）；wb3 只作粗细比例证据 |
| 回归 | `regress_probe_{p7v2_perch,p7v2_bird,p81_tree_bird,selftest}_20261022.log` | 265/0、681/0、149/0、73/73 |
| 说明 | `docs/P8_2_04_NOTES.md` | 六项结论 + usage 统计 + 限制（半径契约、解析高度场等） |

### 10.5 P8.2-05 日期时间滚轮（`05_wheel/`）

| 证据 | 路径 | 关键内容 |
| --- | --- | --- |
| U-02 帧时间（v3 干净独占窗口） | `_run_p81_ui_exclusive.txt`、`p81_ui_regression/`、`probe_p82_datetime_frame.log` | Δp50 中位 +0.400 ms、A/A 噪声 0.729 ms、Δdraw +92、Δobjs +649 |
| 行为 U-04…U-12 | `probe_p82_datetime_behavior_result.json`、`*_u0*.png` | 87 项 80 pass / 0 FAIL / 6 warn / 1 skip |
| 尺寸×DPI | `probe_p82_datetime_dpi_result.json`、`probe_p82_datetime_dpi_*.png` | 12 项 10 pass / 2 warn（高 DPI 模拟假象已甄别） |
| headless | `_run_headless82.txt`、`_run_selftest.txt` | 82/82 PASS |
| 说明 | `docs/P8_2_05_NOTES.md` | U 项闭环表、三层口径、未验证披露、P-1…P-6 处置 |

### 10.6 P8.2-06 回归 / soak / 矩阵 / 发布

| 证据 | 路径 | 关键内容 |
| --- | --- | --- |
| 全量回归台账 | `final/<RUN_ID>/regression.csv` + 各探针日志 + `evidence_backup/` | 列：name,mode,rc,expected_fail,status,fail_cnt,counts,log；含 `nondet` 分类 |
| 30 min soak | `final/<RUN_ID>/soak/`、`06_soak/` | 帧时间 p50/p95/p99 首末窗、nodes/orphan/objects/dc/vram、天气/季节/画质/面板循环 |
| 五档矩阵 | `final/<RUN_ID>/matrix/`、`06_matrix/` | 30 张 1600×900（q0..q4 × 6 场景）+ `matrix.csv` 22 列 + `MANIFEST.md` + `contact_sheet.png` |
| 发布管线 | `build_release.sh`、`verify_release.sh`、`release_preview/` | 预览导出复现 `sha256=c40376ad…b668`、size 117,238,104（与 P8.1 冻结包逐字节一致） |
| 冻结证据复核 | `integrity/frozen_p81_p8_manifest_before.txt`、`audit_sha_check_20261022.txt` | 599 文件 sha256；复核 599 OK / 0 FAILED（须在 `开发产物/` 下执行） |
| 索引文档 | `docs/P8_2_TEST_RESULTS.md`、`docs/P8_2_06_NOTES.md` | 口径分层、预存在失败 PRE-1…PRE-7、NONDET-P82-1、冻结后流程 |

### 10.7 本报告 § → 主证据映射

| 报告节 | 主证据 |
| --- | --- |
| §3 壁炉 | `01_fireplace/after/after_geom.log` + `MANIFEST.csv` + `analyze_fireplace.py` |
| §4.1 灯光视觉 | `02_lighting/{before,after}` + `pixels_after.csv` + `regress/isolate3_diag.log` |
| §4.2/4.3 性能 | `evidence/02_perf/{aa2,ab}` + `docs/P8_2_02_PERF_MEASURE.md` |
| §5 强风 | `evidence/03_wind/analysis_optab.txt` + `compare_before_after.txt` |
| §6 冬季 | `04_winter/eco_geom_after_fix_20261022.log` + `eco_soak_v3_20261022.log` + `shots/`、`closeup/` |
| §7 滚轮 | `05_wheel/probe_p82_datetime_behavior_result.json` + `_run_p81_ui_exclusive.txt` |
| §8 回归/发布 | `final/<RUN_ID>/regression.csv` + `verify_release` 记录 + `integrity/` |
