# P6 收尾与质量加固报告（T7 / 2026-10-21）

> 项目：休闲小岛幻境（Leisure Isle of Dusk & Dawn）
> 工程：`D:\休闲小岛幻境\游戏工程`；引擎：Godot 4.7.2.stable.official.ed1daf0bf（Forward+）
> 运行环境：Windows + RTX 2060 + 2560×1440（自动化截图/性能为 1600×900/1920×1080 窗口）
> 代码冻结：tag `freeze-p6close-20261021_0515` = `55a8d73`（分支 `p6-closeout`）；基线 tag `baseline-p6close-20261020` = `8f80b13`
> 本报告全部数字来自本轮实测日志；历史报告（`docs/P6_REPORT.md` 等）只作对照，不作为本次结论。

## 0. 结论摘要（TL;DR）

| 维度 | 状态 | 证据 |
|---|---|---|
| 可回滚基线 | ✅ 已建立 | git 基线 tag + 发布版备份（§2） |
| 水面波浪同源 | ✅ 已核实且同一参数源 | probe_water6 17/0、4320 点 CPU/GPU 误差 0.000000 m（§4） |
| AO 后处理 | ✅ 已评估并接入（弱增强，非卖点；q0/q1 关闭） | 四机位像素差 + 分档成本 +1.13/1.70/4.33ms（q2/q3/q4，§5） |
| 体积雾 | ✅ 评估后明确不接入，删除误导入口 | dawn 场景 mean 32.34 vs 噪声 1.42（§5） |
| 天文模型 | ✅ 独立交叉验证通过 + 修复 1 个 P1 时区语义 BUG | probe 2489/0、NOAA+AE 46/46 PASS（§6） |
| ObjectDB/RID 生命周期 | ✅ 应用侧根因已修复；残余引擎/导出告警已分类留证 | selftest 泄漏行 50→0、orphan 11→0（§7） |
| 五档画质接线 | ✅ 24 键逐一验证真实作用 | probe_quality_override_t7 173/173（§8.1） |
| 分辨率/窗口/DPI | ✅ 矩阵 934 项 + 回退 118 项，0 FAIL；真实高 DPI 未验证 | §8.2 |
| 音频/资源/发布包 | ✅ 最终包已导出、校验并覆盖发布位置 | 79 文件 / 116,768,848 B / sha256 `b3b4e4ab…`；窗口 55/55 + 61 图 ALL_PASS（§8.3/§9.4） |
| 自动化/截图/转场/性能 | ✅ 本轮实测完成 | headless 53/53 + 16 探针全绿；窗口 55/55、61 截图、13 转场；五档性能表见 §9 |
| 视觉验收 | ✅ 已实际查看截图（T5 实看 85 张 + 发布包 EXE 实看 27 张） | 14 类检查 0 P0/P1/P2，2 条 P3 风格项（§9.2） |
| 是否可进入下一阶段 | ✅ 可以（无不可接受阻塞项） | §13 五项结论；剩余为下阶段 triage 项（§11） |

## 1. 复核结果：初始线索 vs 当前真实状态

| # | 初始线索 | 复核结论 | 处置 |
|---|---|---|---|
| 1 | `main.gd` 的 `_wave_h()` 仍内联 5 组正弦，与 `isle_waves.gd` 不一致 | **已不存在**。基线 `8f80b13` 时 `main.gd` 的 `_wave_h(x,z)` 已 `return IsleWaves.height(x, z, _frame_t, wd, _wave_height)`；7 组波浪参数与 `sea.gdshader` 一致（容差 1e-6） | 本轮补独立证据（§4），无需改代码 |
| 2 | `post_ao.gdshader` 已写但 `_build_post()` 未挂载 | **表述不准确**。基线已挂载（`_build_post()` 创建 `PostAO` 全屏 quad 并加载 shader），真实缺陷是：`posts_ao` 开关与菜单高级覆盖别名 `post_ao` 从未被 `_apply_quality` 读取 → “关掉 AO 只改状态不改渲染” | 已修复（`633ec8c`），并按 §5 评估接入 |
| 3 | `docs/P6_RESEARCH_VISUAL.md` 与 `tools/probe_water6.gd` 缺失 | **已不存在**：前者 21.7KB 存在于 docs/，后者存在且 17/17 PASS。全局引用审计 53 条未解析引用中真实失效 0 条 | 修正 1 处文档路径写法；审计见 `docs/P6_REFERENCE_AUDIT.md` |
| 4 | `shots6/` 截图集未完成 | 属实（基线无完整 P6 截图集） | 本轮生成 AO/FOG 20 张、UI 矩阵 37 张；--shots/--transition 全集见 §9 |
| 5 | 退出时 75–126 条 ObjectDB/RID 告警、6s 后 22 orphan | **部分属实且已定位**：selftest 退出 50 ObjectDB + 15 DummyMaterial + 20 Instance RID + PagedAllocator 报错；运行期 orphan 11（1 splash+1 ripple 退役后）。根因是 FX 池游离单元，已修复归零；另有音频 8 对象引擎退出竞态与导出 exe 0xC0000374 两项独立问题（§7） | 修复 + 留证 |
| 6 | `sounds/` 约 47MB 早期音频 + 海浪导入告警 | 属实：4 个 wav 共 47.9MB 全局零引用；`海浪声.wav` 为 WAVE_FORMAT_EXTENSIBLE 24-bit（Godot 不支持）→ 导入告警根因 | 归档到 `开发产物/archive/sounds_legacy/` 并从导出排除（§8.3） |
| 7 | 发布包含 `addons/godot_ai/`；scripts/ 有 P6 中间文件 | 属实：`export_presets.cfg` 原仅排除部分 addon 路径；scripts/ 中 5 个中间文件无引用 | 导出排除整目录；中间文件已归档（§9.3） |
| 8 | 无 Git 版本管理 | 属实 | 已建立仓库、基线 tag、.gitignore、分支工作流（§2） |
| 9 | 1080p/4K/高 DPI/不同比例适配风险 | 真实存在但多数可控：矩阵 934 项 0 FAIL；1280×720/1366×768 小字可读性偏弱（37 WARN）；真实高 DPI 未验证（本机系统缩放固定 100%） | §8.2 |

## 2. 基线、回滚与工作方式

### 2.1 修改前基线
- **git**：仓库根 `游戏工程/`；基线提交 `8f80b13`（544 文件），tag `baseline-p6close-20261020`；工作分支 `p6-closeout`；FREEZE tag `freeze-p6close-20261021_0515` = `55a8d73`（562 文件）。
- **发布版备份**：`开发产物/backup/release_pre_p6close/休闲小岛幻境_20261020_2045.exe`（122,950,336 B，sha256 `e2a9d2420375051022f38fe45a0c0786cc4a8ac4a30b345ed8378f2108a2cf8f`）；`发布/` 与 `构建输出/` 旧 exe 在最终导出验证通过前未覆盖。
- **.gitignore**：排除 `.godot/`、`*.log`、`*.tmp`、`__pycache__/` 等；不排除 `*.uid`（Godot 4.7 稳定 UID 需入库）。`发布/`、`构建输出/`、`开发产物/` 位于仓库外，不进入版本历史。
- **基线清单**：`docs/P6_BASELINE.md`（260 行：环境、12 条已知故障、文件差异、归档明细、回滚手册）。

### 2.2 回滚方法
```bash
cd D:/休闲小岛幻境/游戏工程
git checkout baseline-p6close-20261020        # 或 git reset --hard <hash>
# 发布版回滚：
copy /Y "D:\休闲小岛幻境\开发产物\backup\release_pre_p6close\休闲小岛幻境_20261020_2045.exe" "D:\休闲小岛幻境\发布\休闲小岛幻境.exe"
```
> 注：`开发产物/` 下的归档（sounds_legacy、scripts_p6_intermediate、root_cleanup）含归档前 SHA256 清单，可反向恢复。

### 2.3 分工与写隔离
Team Lead + 6 teammates（lifecycle / release / hygiene / verify-auto / verify-visual / astro），共享工作目录；每人只提交自己 scope 路径，Lead 统一冻结与最终报告。写 scope 在任务板登记，FREEZE 后仅允许 docs 提交。

## 3. 核心修改清单（基线与 FREEZE 之间，11 个提交）

| commit | 内容 |
|---|---|
| `633ec8c` | 画质高级覆盖真正接入渲染：AO 开关 `posts_ao`（兼容 UI 别名 `post_ao`）、`lod_bias` 递归缩放岩石 LOD、`fog_scale` 缩放海面/全局雾距；删除菜单无效“体积雾”入口；`_quality_params` 归一别名 |
| `705b535` | 卫生基线/测试说明/引用审计文档；补交 19 个探针 .uid；完善 .gitignore |
| `173abe3`/`c88a25b` | 引用审计复跑口径、--check-only 实测与 user:// 噪音记录 |
| `fef93a6` | 移除根目录临时 w3.txt（已归档）；P6_REPORT 标注 T7 过时项 |
| `78251ee` | T5 分辨率/UI 矩阵探针 + 视觉验收报告阶段 1 |
| `a02b6dc` | T6 天文独立交叉校验探针 + NOAA/AE 参考生成/比对脚本 + 验收文档 |
| `a43ca8c` | **P1 修复**：现实时间天体时钟固定岛屿参考时区，显示时区不再平移天体 |
| `bd078b0` | **P0 修复**：FX 对象池退出时释放游离单元，消除 ObjectDB/RID 退出泄漏 |
| `75df4f6` | 补交 post_ao.gdshader.uid |
| `55a8d73` | 发布包排除 addons/godot_ai 整目录；归档早期 sounds/；发布打包文档 |

> FREEZE 之后另有 test/docs-only 提交（`b56dc88` astro 探针、`037cc4c`/`3ab7d9a`/`6ac049e`/`7a5b488` 验收文档、`3161429` 发布文档、`d98f60c` T4 测试结果、本报告提交）；`scripts/` 与既有 51 个基线探针零改动。发布包在 `3ab7d9a`/`6ac049e` 两次重导出均与 FREEZE `55a8d73` 字节一致（§9.4），docs/test 提交不影响交付物。

主要文件：`scripts/main.gd`（画质解析/AO/LOD/雾 + 时区语义 + selftest 第 24 组）、`scripts/menu.gd`（高级覆盖行/三态/规范键）、`scripts/fx.gd`（池生命周期）、`export_presets.cfg`（导出过滤）；新增 `docs/P6_*.md` 9 份、`tools/probe_{quality_override_t7,ui_matrix6,astro_xcheck_t7,exit_diag_t7,ao_visual_t7}.gd` 等探针。

> `main.gd` 未做整体拆分（用户 §9.3 明确：无直接问题不开展大重构）。

## 4. 水面波浪同源化（T7 复核，无需改代码）

### 4.1 结论：CPU 与 GPU 已是同一参数源
- 单一参数源：`scripts/isle_waves.gd`（`class_name IsleWaves`）的 7 组 `WAVES`（前 5 组沿用 P5 参数 amp .420/.260/.150/.085/.050，新增 .072/.038；波数门槛 need 0/0/0/0.5/1.5/1.5/2.5）。
- `main.gd` 的 `_wave_h(x,z)` 直接调用 `IsleWaves.height(x, z, _frame_t, wd, _wave_height)`；`sea.gdshader` 的 7 组 wave 参数与 `isle_waves.gd` 在容差 1e-6 内一致；画质档只决定启用的波数（detail：低/中/高/极致 → 3/4/6/7 组），不是两套硬编码。
- 船舶起伏/俯仰/横滚与尾迹取样同用 `_wave_h`（同一时间输入 `_frame_t`），不存在“船按旧 5 波、海面按 7 波”的分裂。

### 4.2 数值证据（tools/probe_water6.gd，headless）
| 检查 | 结果 |
|---|---|
| probe_water6 | checks=17 fails=0 |
| shader 7 组参数 vs isle_waves.gd | 容差 1e-6 内一致 |
| CPU `IsleWaves.height` vs shader 公式独立复算（4320 采样点） | 最大误差 **0.000000 m** |
| 画质档启用波数 | [3,4,6,7] |
| detail=3 理论最大振幅 | 1.075 m |
| 1cm 步长最大高度跃变 | 0.00047 m（无台阶/跳变） |

### 4.3 视觉与档位协调
- 画质切换只改波数，不改波长/振幅/方向/速度 → 切档不会造成浪高突变（参数表按档位裁剪，其余参数不变）。
- 近岸/码头边界无新增漏洞（--shots/--transition 与 T5 审查覆盖；长滩/礁石截图见 `开发产物/shots/`）。
- 低画质不启用 7 组（detail=3 时仅 3 组，headless 数值已验证）；未破坏原水面观感（视觉对比由 T5 审查确认）。

## 5. AO 后处理评估（评估后决定：接入，但定位为“轻微边缘增强”）

### 5.1 实现检查
- `post_ao.gdshader` 使用深度纹理 + 逆投影重建视空间位置，8 方向采样；边界处 `UV` 钳制；含深度差/法线近似（深度导数）判据；参数 `ao_strength/radius/samples/bias/contrast/max_dist` 由 `_apply_quality` 按档写入；渲染顺序 `render_priority=127`，在 vignette/glow 之后。
- 修复前的问题不是 shader 而是接线：`posts_ao` 布尔从未被读取，菜单高级覆盖写的 `post_ao` 别名也不生效 → 关闭 AO 只改 UI 状态。
- 修复后：`posts_ao`（兼容 `post_ao`）控制显隐与强度；q0/q1 `posts_ao=false`（不付全屏 pass），q2/q3/q4 默认强度 0.35/0.55/0.75；手动开启低档时给 0.35，避免“开了但看不见”。

### 5.2 实际效果与成本（窗口实测，1440×900）
- 像素差（AO off vs on，q3）：四机位 mean 0.37–0.67/255，>2/255 比例 6.5–12.8%，>8/255 仅 0.2–0.6%，>24/255 为 0%；diff 图显示差异集中在物体轮廓/接触边缘窄带，无大面积接触阴影。
- 目视：无天空/海面/玻璃/草地暗边，无阁楼窗重影；因项目以 unshaded 平涂 + toon 管线为主，AO 只产生轻微边缘压暗 → **定位为质量增强而非卖点**。
- 成本：1440×900 单轮初测 off 9.570ms / on 10.354ms，Δ≈+0.78ms（约 +8%，窗口非独占）；T4 独立 `ao_perf` 在 1600×900 三档对比（同一场景同轮切换）：**q2 120.4→106.0 fps（+1.13ms / +13.6%）、q3 67.9→60.9（+1.70ms / +11.6%）、q4 56.9→45.7（+4.33ms / +24.6%）**。绝对耗时随档位上升（全屏 pass 与分辨率缩放叠加），q4 相对成本最高但仍保持 45fps+，且低档 q0/q1 完全不付该成本。
- 画质分档：q0/q1 关闭（0 成本）；q2 0.35 / q3 0.55 / q4 0.75，符合“低档不负担、高档有提升”的设计；高级覆盖可独立开关，不被预设切换覆盖。

### 5.3 体积雾：不接入
- 引擎 `volumetric_fog` 实测（dawn 海景）：off/on 像素差 mean 32.34，而 off/off2 噪声地板 1.42；目视海面被染暗近黑、远山出现黑带，破坏暖色晨景；noon/dusk 只是泛白并削弱反差。
- 处置：不接入引擎体积雾；删除菜单中只改状态不改渲染的“体积雾 · FOG”高级覆盖行（原为误导入口）；preset 的 `volumetric_fog` 键保留全档 false（兼容探针契约）。
- 现有雾仍由自定义 `fog_scale` 控制海面/全局雾距（已接入渲染），视觉风格不变。

## 6. 天文系统独立交叉校验

### 6.1 方法与数据范围
- 参考实现：项目自带 NOAA 官方 JS + astronomy-engine（node 脚本 `开发产物/logs/astro/gen_ref_t7.js` 生成 `ref_t7.json`）。
- 被测：`tools/probe_astro_xcheck_t7.gd`（headless，读取 isle_astro 输出）→ `compare_t7.js`（判据先行、容差写死）。
- 覆盖：太阳 2026 全年每周 57 日期 + 春分/秋分/夏至/冬至 + 日出/日落/正午 + 11 采样点 + 跨日/日期切换 + 现实/模拟两种模式；月亮 50 个四相日期 × ±0/6/24h = 150 点 + 月出月落（每日 0/1/2 次，含跨午夜）+ 地平线下 + 相位-位置解耦 + ±60s 无突跳；Phase B 时间系统 9 组（十档流速、灯塔、天空调色、两个炊烟窗口、小船夜间休息、海鸥迟滞、夜间灯光/环境音交叉淡化、统一 `_sim_seconds`、现实时区显示）。

### 6.2 结果（本轮实测）
- probe（最终版，2489 项）：`[SUMMARY] pass=2489 fail=0 skip=0 known_bug=0`（Phase A 2481 项 + Phase B 8 组行为测试；B8 已改为生产路径）；compare：`[RESULT] PASS`，46/46 类别在容差内 + 1 INFO（NOAA-vs-AE 自身方位病态项）。修复前 probe 为 2481/known_bug=1，Phase A 684 行 RAW 与最终版逐字节 diff=0（test-only 改动零影响）。
- 容差（未放宽）：太阳时刻 ≤0.5min、月亮 ≤1.0min；太阳角度 0.05°、月高 0.5°、月方向 0.1°、月升落方位 0.5°、照度 0.005、相位角 0.5°、地心距 100km、视半径 0.02°。
- 实测最大误差（最终版）：日出 vs NOAA **0.0510min（3.06s）**、日落 **0.0686min（4.11s）**、正午高度 vs AE **0.00395°**（时刻对照受 NOAA 1min 网格限制 0.2629min）；太阳采样高度 **0.01338°**、方向夹角 **0.01276°**、升落方位 ≤**0.00622°**；月出 **0.2181min（13.1s）**、月落 **0.1798min（10.8s）**；月高 **0.01324°**、方位(alt<80°) **0.0544°**；照度 **1.27e-4**；相位角 **0.01651°**；地心距 **23.48km**；视半径 1.6e-5°。
- 局限：近似星历截断级数固有 1e-2°/0.1s 量级；只验证 2026 + 广州；月落 2/57 日期 AE 无本地事件；NOAA 正午为 1min 网格。**不宣称“精确星历”，只宣称与参考实现一致且在容差内**。

### 6.3 发现并修复的 P1 BUG（real 模式时区语义）
- 现象：现实模式下切换“显示时区”会平移天体位置（unix=1773968400 实测 max|dalt|=66.14°、max|daz|=179.30°）。
- 根因：`main.gd` real 模式 `_sim_seconds = _abs_unix + 所选时区偏移`，而 `isle_astro.jd_from_local` 固定按 -28800（广州）解释 → 时区选择污染了天体时钟。
- 修复（commit `a43ca8c`）：real 模式 `_sim_seconds = _abs_unix + IsleAstro.TZ_SECONDS`（(`IsleAstro.TZ_SECONDS=28800`)，5 处同步点）；显示时区只影响 `_display_datetime()` 与 `_local_seconds_to_display_text()`（删除 real 特判，统一换算）。
- 回归：selftest 第 24 组 4 条断言重写（数量不变）——天体时钟固定参考时区、日出文本按东京偏移换算、切换显示时区前后 `_sun_alt/_sun_az` 变化 <0.05°、显示小时正确；headless `-- --selftest` **53/53 PASS**（日志 `开发产物/logs/verify/t7_selftest_after_tzfix.log`）。
- astro B8（已改为生产路径行为测试，FREEZE 后 test-only 例外，commit `b56dc88`）实测：跨时区 `max|dsim|=0.042s`（判据 ≤0.1s）、`|_sim_seconds-(_abs_unix+TZ_SECONDS)|=0`、`_update_lighting` 太阳位置跨时区 `max dalt=0.000059°/daz=0.000692°`、墙钟按 offset 换算误差 0.00min、连续切换上海→纽约天体差 0/0；旧映射反事实（66.1445°/179.2974°）仅作 [INFO] 保留。全量 probe `pass=2489 fail=0 known_bug=0`，compare 46/46 PASS。文档 `docs/P6_ASTRO_ACCEPTANCE.md §8` 已标为已修复（commit `037cc4c`）。
- 与用户 §5.3 要求一致：**没有把时区显示调整改成天体地理位置变化**；模拟模式下切时区天体严格不变（astro 探针已断言）。

## 7. 生命周期：ObjectDB/RID 退出告警与 orphan

### 7.1 复现矩阵（before）
| 场景 | 观察 |
|---|---|
| 最小空场景 / 仅渲染节点 / smoke_test headless 60 帧 | 无任何退出告警（引擎本底干净） |
| isle.tscn headless 菜单态 2/6/12/20s | 无 RID/ObjectDB；6s 偶发 8 音频对象泄漏 |
| isle.tscn headless `-- --selftest` | 50 ObjectDB + 15 DummyMaterial + 3 DummyShader + 6 DummyMultiMesh + 4 DummyMesh + 1 DummyTexture + 20 RendererSceneCull Instance RID + PagedAllocator 报错 + 15 unclaimed string names |
| isle.tscn 窗口 1600×900 6s | 无 RID/ObjectDB；仅 user:// 不可写的 shader cache ERROR（环境） |
| 导出 release exe headless selftest/perf | 功能完成后退出阶段 0xC0000374（独立问题，见 §7.4） |

### 7.2 根因与修复（commit `bd078b0`，scripts/fx.gd +46 行）
- 根因：Splash/Ripples 对象池退役单元时 `remove_child()` 后仅由 `_free` 数组持有 → 树外 orphan；池节点随场景树退出被释放时不会触及这些游离子树（Splash 每单元 1 Node3D + 6 MeshInstance3D + 3 CPUParticles3D；Ripples 为 MeshInstance3D），数量签名与 selftest 泄漏完全吻合。
- 修复：Splash（L873-896）与 Ripples（L1286-1305）新增 `_exit_tree()` / `_notification(NOTIFICATION_PREDELETE)` / `_release_detached()`，池退出/销毁时对 `_free` 内单元（Variant + `is_instance_valid` 防已释放）执行 remove_child + free() + clear()；幂等、双钩子。运行期语义不变（`get_child_count()==活跃单元数`，probe_fx_p4 与 selftest 断言不受影响）。

### 7.3 修复后复测
| 指标 | before | after |
|---|---|---|
| headless `--selftest` 退出泄漏行 | 50 ObjectDB + 15 DummyMaterial + 20 Instance RID + PagedAllocator | **0**（3 连跑，断言仍 53/53） |
| 探针池销毁后 orphan | 11 | **0**（`14_/15_/23_` 日志） |
| 窗口 isle 6s / minproj / smoke_test | 无泄漏 | 无泄漏 |

**窗口 \`--perf\` 的 after_6s orphan=10–20 已定性（非泄漏）**：窗口六次 perf 运行 \`orphan=10/10/20/20/20/20\`，但 \`nodes+orphan\` 恒等于 1645（与 headless 基线一致；如 1635+10、1625+20）。10 节点/单元 = Splash 池单元（1 Node3D + 3 Ring MeshInstance3D + 3 Column MeshInstance3D + 3 CPUParticles3D，\`scripts/fx.gd:943-990\`）退役后由池 \`_free\` 持有等待复用（\`fx.gd:1043-1057\`）；触发链为 Ripples 自动鱼跃（\`fx.gd:1445-1450\`）→落水激活 Splash→退役。headless 同命令补跑 2 次 orphan=0；池销毁后由 \`fx.gd:881-897 / 1323-1337\` 显式释放，\`probe_exit_diag_t7\` 实测 11→0；六份窗口 perf/selftest/shots/transition/干净启动日志均 0 条 leaked/ObjectDB/RID 告警。历史窗口 perf 日志同样有 11/21/22/52 波动。结论：**FX 池化游离单元，设计内、退出归零、非泄漏、不影响 exit 0**。节点级逐帧触发差异未做插桩（冻结期不加代码），如实记录。

### 7.4 两项未能消除、已留证的问题（不阻塞交付）
1. **headless Dummy 音频退出竞态（引擎侧）**：固定 8 对象（4×AudioStreamWAV + 4×AudioStreamPlaybackWAV，refcount 1）+ Orphan StringName IsleFire/IsleAmbient，非确定性。实验：在 isle_audio 加停播放器/清 stream/删 4 条命名总线的退出清理并用 `--audio-log` 证实 `_exit_tree` 执行后，8 次仍 5 次命中同样对象 → 应用侧无法消除，已回滚试验 patch（无残留代码）。影响：仅退出日志 warning，不影响源码工程退出码 0 与窗口模式。
2. **导出 release exe 退出 0xC0000374（heap corruption）——FREEZE 构建复测未复现**：修复前试导出 exe 与旧发布 exe（P6 前）均在 `--selftest` 退出期出现 0xC0000374（旧发布 44/46 后同样），plain/菜单 `--quit-after` 退出码 0，源码工程 headless selftest 退出 0。加入 FX 池释放修复（`bd078b0`）后的 FREEZE 构建重新导出后，真实退出码矩阵 `selftest×2 / perf / quit` **全部 EXIT=0**（selftest 两次 53/53、22s/21.8s；perf 44.2s；quit 6.4s），0xC0000374 **未再出现**（`开发产物/release_verify/crash_evidence/final/exit_codes.txt`）。残留告警：该矩阵的 `selftest_2`/`perf_1` 两次 stderr 出现 `WARNING: 4 ObjectDB instances were leaked at exit`（退出码仍为 0；源码工程 headless/窗口、发布位置复测均未出现），与上条 Dummy 音频退出竞态同类，属导出包退出期引擎诊断，已留证、不影响可执行性。窗口 `--selftest` 55/55 exit 0 同样正常。结论：该崩溃与 FX 池游离单元释放时序高度相关，已随 `bd078b0` 消失；仍建议下阶段在 WER dump 可用时做一次符号化确认（非阻塞）。

### 7.5 既有基线问题（非本轮引入，仅记录）
- `tools/probe_fx_p4.gd` 鸟群起飞/降落 1 项 FAIL（30s takeoffs=1 landings=1，断言要求 ≥4）；在基线 commit `8f80b13` 的 fx.gd 隔离工程复现同签名 → 既有行为回归，与生命周期修复无关。是否修复需按玩法口径决策（本轮不改鸟群行为）。

## 8. UI / 画质 / 分辨率 / 音频 / 发布包

### 8.1 五档画质 24 键接线（commit `633ec8c`，探针 173/173）
- 审计发现 P1 缺陷：`posts_ao` / `volumetric_fog` / `fog_scale` / `lod_bias` 四键从未被渲染消费；菜单 AO 高级覆盖写 UI 键 `post_ao` 而 main 只读 `ao_strength` 且从不读开关；三态 `preset.get(key,true)` 因别名恒 true，q0/q1 循环方向错误。
- 修复：AO 开关真正控制显隐+强度；`_apply_lod_bias(bias)` 递归缩放 World 下 `Rocks_*_Near/Far` 的 `visibility_range`（Near end=28*b、Far begin=24*b，基准 world.gd:1658-1659）；`_update_lighting` 用 `fog_scale` 缩放海面/全局雾距并写 `_dbg_fog_near/_dbg_fog_far` 供探针断言；`_quality_params` 归一 `post_ao→posts_ao`；menu 新增 `_override_param_key`（内部规范键、外部存档仍存 UI 键）。
- 证据：`tools/probe_quality_override_t7.gd` 173/173 PASS（五档逐键 24 参数真实作用 + 覆盖真实渲染 + 菜单存档往返），`probe_quality6` 51/0、`probe_menu6` 152/0。
- 已知 P2（仅记录未改）：`isle_settings.gd:252-256` 的 `quality_effective` 只逐键拷贝（不 sanitize、不丢未知键），与 `isle_quality.gd` 的 `merge_overrides` 行为不一致；不影响本轮验收，建议下阶段统一。

### 8.2 分辨率 / 窗口 / 高 DPI（T5 阶段 1，commit `78251ee`）
- 三阶段 **1138 项：PASS=1101 / WARN=37 / FAIL=0**（`tools/probe_ui_matrix6.gd`，67.1s + 回退 + DPI）。
- 窗口矩阵 934 项：16 种窗口态 + 1 全屏实测生效；`aspect="expand"` 视口：1280×720→1600×900(scale 0.8)、1366×768(0.8533)、1600×900(1.0)、1920×1080(1.2)、2560×1440(1.6)、3440×1440→2150×900(1.6,2.3889)、3840×2160(2.4)、1920×1200→1440×900(1.3333)；4K 用 viewport 捕获验证（纹理 3840×2160）。
- 回退流程 118 项：真实鼠标拖滑条→确认层；保持 1600×900 倒计时 11.9→10.6s；回退恢复 1440×900；ESC 回退；自然超时 11.98s 自动回退；windowed→fullscreen→borderless→windowed 均真实切换。
- DPI 86 项：本机系统缩放固定 100%（dpi=120），125%/150% 用 `content_scale_factor` 模拟通过；**真实高 DPI 未验证**。
- 37 WARN 归因：1280×720/1366×768 小字 8.0–9.6px 可读性偏弱（设计取舍）；游戏内超屏被钳制 2560×1390；letterbox 无黑边；高 DPI 未验证。
- 截图 37 张：`开发产物/shots6/verify_visual/`；日志 `开发产物/logs/visual/probe_ui_matrix6_{matrix,fallback,dpi}.{log,json}`。

### 8.3 音频与资源清理
- **sounds/ 审计**：4 个早期 wav（`sea-waves-on-a-rocky-shore-1190.wav`、`windy-sea-loop-.wav`、`海浪声.wav`、`鸟叫声.WAV`，共 47.9MB）在场景/脚本/资源/导出预设中零引用；`海浪声.wav` 为 WAVE_FORMAT_EXTENSIBLE 24-bit（Godot 4.7 不支持，导入告警根因 `audio_stream_wav.cpp:738`）。已归档 `开发产物/archive/sounds_legacy/`（含 SHA256SUMS_before_move.txt）并删除 `sounds/`；归档后导入 0 相关 ERROR。
- **当前音频资源**：11/11 音频可加载且时长 >0（导出包内验证）；未发现削波/接缝的自动化证据（本轮无法试听，见 §10 未验证项）。
- **五总线**（Master/IsleAmbient/IsleBirds/IsleFire/IsleSFX）：probe_audio6 232/0（独立音量、主音量、交叉淡化、夜间启停、音效池生命周期）。
- **addons/godot_ai**：纯编辑器插件，运行时无引用；`export_presets.cfg` 由“部分排除”改为 `addons/godot_ai/*` 整目录；`project.godot` 不动（addon 导出插件在 `_export_begin` 临时剥离 `_mcp_game_helper` autoload）。
- **试导出包**（trial2）：116,767,872 B（旧 122,950,336，−6,182,464 B / −5.03%）；校验 `LOAD_PACK_OK=true`、`RES_ADDONS_DIR=false`、`RES_SOUNDS_DIR=false`、`RES_TOOLS_DIR=false`、`PB_HAS_MCP_GAME_HELPER=false`；干净目录 `--headless -- --selftest` 53/53；包内 `simhei.ttf` 加载 28522 字符含 休/闲/中、11/11 音频、isle.tscn、4 着色器。
- **导出关键坑（已写入 runbook）**：必须把 `TMP/TEMP` 指向工作区可写目录（`开发产物/release_verify/tmpdir`），否则 project.binary 临时文件写失败 → exe 报 “Corrupted header in binary project.binary (not ECFG)”。


## 9. 自动化验证、截图、转场与性能（T4/T5 实测）

> 说明：本节数字来自 FREEZE HEAD `55a8d73` 的独立重跑（verify-auto），历史数字（48/48、55 断言、旧性能）只作对照。
> 日志根：`D:\休闲小岛幻境\开发产物\logs\verify\`；截图根：`D:\休闲小岛幻境\开发产物\shots6\verify\`。

### 9.1 自动化测试（FREEZE 后重跑，verify-auto 独立执行）

**断言真实性审计（PASS）**：`git diff baseline(8f80b13)..freeze(55a8d73)` = 35 文件 +3140/−77；既有 51 个基线探针 .gd **零修改**；`main.gd` 的 `results.append` 55→55 未减；selftest 第 24 组 4 条数量不变，其中 2 条替换为更严判据（旧“天空时钟 <5s” → 参考时区 <5s + 日出文本换算；纽约新增 `|Δalt|<0.05°`、`|wrap Δaz|<0.05°`）；删除项仅 `_tmp_*`、`__pycache__`、`menusplice_report` 等临时文件。证据：`开发产物/logs/verify/{assert_audit.txt,audit_full.diff,audit_diffstat.txt}`。

**headless `--selftest`**：`[TEST] RESULT 53/53 passed`，exit 0，SKIP 1（“真实鼠标拖动”由窗口模式覆盖）。日志 `开发产物/logs/verify/selftest_headless.log`。

**16 个 headless 探针（全部 exit 0）**：
| 探针 | 结果 | 探针 | 结果 |
|---|---|---|---|
| water6 | 17/0 | quality6 | 51/0 |
| settings6 | ALL PASS | audio6 | 232/0 PASS |
| cottage6 | 31/0 | bird6 | 45/0 |
| smoke6 | 96/0 | astro6 | 423/0 PASS |
| menu6 | 152/0 | menu7_t1 | 50/0 |
| esc_e2e_t1 | 19/0 | frame_t5 | 5/0 |
| main_smoke_t5 | 纯诊断 exit 0 | quality_override_t7 | 173/173 |
| exit_diag_t7 | baseline orphan=0 → 退役后 +11 → 池释放后回 0，exit 0 | astro_xcheck_t7 | **2489/0/known_bug=0**（B8 改生产路径后），compare 46/46 PASS |

**干净启动 + 正常退出（headless）**：`--quit-after 600` 退出码 0；ERROR 仅 3 条已知环境噪声（2 条 user:// 日志沙箱限制 + 1 条 root certificate store）；ObjectDB 泄漏为偶发：首跑 8 个（分类为引擎侧 headless Dummy 音频退出竞态，非应用泄漏、不影响 exit 0），复跑 4 次中 1 次出现 1 行、其余 0，佐证竞态。日志 `boot_clean_run1-3.log`、`boot_exit_headless.log`。

**astro_xcheck_t7（FREEZE 后 test-only 例外）**：旧版探针 B8 硬编码 pre-fix 映射 → known_bug=1（2481/0）；更新为生产路径行为测试后（commit `b56dc88`）**2489/0/known_bug=0**，Phase A 684 行 RAW 与旧版逐字节 diff=0（零影响），node compare 46/46 PASS + 1 INFO（commit `037cc4c` 更新文档）。

### 9.2 截图集与转场

**工程内截图（窗口模式，FREEZE 源码）**：
- `--shots`：61 张，归集 `D:\休闲小岛幻境\开发产物\shots6\verify\shots\`（菜单/设置/六时段天空/建筑近景/海鸥/船/灯塔光效/画质对照），日志 `开发产物/logs/verify/shots.log`（62 行 [SHOT]，实际 61 PNG）。
- `--transition`：13 张 `tr_00…tr_12`，`开发产物/shots6/verify/transition/`，日志 `transition.log`。
- 五档固定机位：11 张 `quality_fixed_q0..q4 / ao_off / ao_on / ao_debug / q4_ssr0 / t3_water_low / t3_water_ultra`，`开发产物/shots6/verify/quality/`。

**T5 人工审查（read_image 逐张实看，非存在性检查）**：阶段2 共 **85 张**（61 shots + 13 transition + 11 quality），叠加阶段1 矩阵 37 张与 AO 实验 45 张，累计实看 **167 张**。结果：**14 类逐项通过，0 P0 / 0 P1 / 0 P2**；仅 2 条 P3 风格项（海鸥低模腿部轻微悬空感、船尾迹为环状泡沫非物理拖尾，均为既有艺术风格而非回归）。关键确认：水面岸线/泡沫环连续无漏水；阁楼白天/夜间与门廊玻璃室内可见、反射不过度；灯塔/探照灯/船灯无黑带或过曝；海鸥栖枝/屋脊无穿模；q0→q4 差异单调合理（q0 无云层、水面简化；q2–q4 阴影/反射递增），AO 仅边缘压暗无光晕，SSR 开关差异可见不突兀；菜单/设置/转场无裁切、无黑帧闪白。文档 `docs/P6_VISUAL_ACCEPTANCE.md`（commit `3ab7d9a`，阶段2 14 类结果表）。

**发布包 EXE 截图（窗口自动化，FREEZE 构建）**：`--shots` 61 张 + `--transition` 13 张，位于 `D:\休闲小岛幻境\开发产物\release_verify\window_smoke\final_shots\` 与 `...\final_transition\`；`RESULT=ALL_PASS`（`开发产物/logs/release/30_window_auto_smoke.log`，同时断言窗口 `--selftest` 55/55 + exit 0）。**T5 已完成 EXE 版复核（通过）**：实看 EXE 截图 27 张（指定 15 + 抽查 12），并对 61+13 张做全量数值配对——与工程内同名图 missing=0、降采样灰度相关系数 median=0.9932 / min=0.8768（01_night，动态灯光/水面相位）、MAE 0.83–4.31/255、黑帧 0、过曝白帧 0、转场亮度 85.6→138.1 单调无闪白；主菜单/设置页/六时段/灯塔/水面/画质 q0+q4/转场全部无字体缺失、无 UI 裁切、无贴图丢失；P0/P1/P2 异常 0（`docs/P6_VISUAL_ACCEPTANCE.md` 附录 D，commit `7a5b488`，证据 `开发产物/logs/visual/exe_consistency_check.py`、`exe_fullset_check.py`）。

### 9.3 性能（同条件前后对比）

**方法**：窗口模式 1600×900（`--shots/--perf` 下 `_apply_resolution` 跳过，实际逻辑视口 1600×900），vsync 关闭，采样期间 `Engine.max_fps=0`（否则 q0/q1 预设 60 上限掩盖真实成本）；固定 6 机位各 180 帧，随后单次运行内 `_apply_quality(4..0)` 循环五档。当前机器 RTX 2060 / Ryzen 5 2600X，与历史文档同一台机器，但本轮窗口未被其它任务独占，读数为区间；历史值取 `docs/P6_REPORT.md` §8（两轮 22:05/22:15）。

**场景采样（quality=2 高·精致，1600×900）**：

| 场景 | 本轮 fps / frame_ms | 历史区间 fps | objects / draw_calls |
|---|---|---|---|
| noon_clear | 157.4 / 6.35 | 122.4–136.9 | 2080 / 1687 |
| golden_cloud_water | 148.0 / 6.76 | 108.5–133.8 | 2079 / 1690 |
| night_shadows | 142.5 / 7.02 | 120.2–121.6 | 2101 / 1712 |
| night_close | 147.0 / 6.80 | 136.9–137.0 | 1584 / 1245 |
| far_island | 163.2 / 6.13 | 113.2–133.3 | 2098 / 1705 |
| sky_up | 149.8 / 6.68 | 64.3–132.8 | 2109 / 1720 |
| time_panel_open | 153.6 / 6.51 | 67.3–112.5 | 2530 / 1768 |
| lite_noon_nomultimesh | 150.8 / 6.63 | 118.8–148.2 | 2049 / 1656 |
| lite_night_nomultimesh | 157.6 / 6.34 | 87.2–137.5 | 2058 / 1669 |

VRAM q2 ≈ 350–352MB（历史 348.5–350.5MB），objects/draw_calls 与历史一致（≈1980–2109 / 1245–1720），无对象或绘制调用回退。

**五档画质成本（同一次运行内循环，1600×900）**：

| 档位 | 本轮 fps / ms | 历史 fps 区间 | VRAM | MSAA / 3D scale | 草实例 | 解析灯 | msaa 参数 |
|---|---|---|---|---|---|---|---|
| 4 极致 | **80.2 / 12.47** | 40.9–63.0 | 879.3MB | 4× / 1.25 | 22500 | 12 | 3 |
| 3 极高 | 86.9 / 11.50 | 63.7–80.8 | 759.5MB | 4× / 1.15 | 22500 | 10 | 3 |
| 2 高 | 147.4 / 6.78 | 121.9–134.5 | 352.2MB | 2× / 1.00 | 22500 | 8 | 2 |
| 1 中 | 153.4 / 6.52 | 98.3–126.5 | 260.5MB | 1× / 0.92 | 15750 | 6 | 1 |
| 0 低 | 155.5 / 6.43 | 143.9–162.3 | 219.6MB | 0 / 0.85 | 10125 | 4 | 0 |

**结论**：五档的成本排序、VRAM、草实例、解析灯与 MSAA/3D scale 与历史一致，**无未经解释的回退**；本轮 q4/q3 明显高于历史区间（80/87 vs 41–81，q2 147 vs 122–135），差异方向为变快，属于测试窗外负载更轻（历史报告已注明两轮差 35%、cpu 采样 142–198ms 尖峰噪声），不据此宣称性能优化。q2（默认档）本轮 142–163fps，保持 60fps 余量；q4 仍是唯一显著高成本档（879MB VRAM、80fps）。窗口 `--perf` 重复跑 6 次（perf.log/perf_q0..q4）的 `[PERF] begin` 均为 `quality=2`，说明 `--quality N` 在这批调用中未生效（参数优先级问题，见 §12.2 备注）；五档数据取自单次运行内部的 `_apply_quality` 循环，不受该问题影响。

### 9.4 发布版最终导出与干净目录验证

**构建来源**：FREEZE 后 HEAD 已有两笔 test/docs-only 提交（`b56dc88` astro 探针、`037cc4c` astro 文档、`3ab7d9a` 视觉文档），release 在 **HEAD=3ab7d9a** 用最终代码重新导出，并与 freeze `55a8d73` 构建对比：**SIZE=116,768,848 B、SHA256=`b3b4e4ab492b471da0472432749c9ac9faea225700443806389d803fbd9684f8`，字节完全一致（0 差异）**；savepack 清单 79 条 sha256=`b8cd0996…`，与 freeze 清单 diff 完全一致 → **后置两笔仅 test/docs，未改变发布字节；发布构建内容等同 FREEZE**。

**包内容与完整性校验（干净目录）**：79 文件（scripts 36 / .godot 16 / audio 11 / shaders 10 / icon 2 / project.binary 1 / isle.tscn.remap 1 / fonts 1 / art 1）；**无 addons/sounds/tools/docs/shots**（显式校验 0 条）；LOAD_PACK_OK=true、RES_ADDONS/SOUNDS/TOOLS/DOCS_DIR=false、PB_HAS_MCP_GAME_HELPER=false、PROJECT_BINARY_MAGIC=ECFG；字体 simhei.ttf FontFile（28522 汉字，含“休/闲/中”）、AUDIO_OK=11/11、isle.tscn 可实例化、4 个 shader 全部为 Shader；autoload stripping 行存在。旧发布对比：122,950,336 B → **116,768,848 B（−6,181,488 B ≈ −5.03%）**，减少部分 = addons/Godot AI 编辑器插件资源 + 未使用早期音频，不以体积下降单独判定成功（功能与资源校验见上）。

**干净目录 headless selftest**：`[TEST] RESULT 53/53 passed`，退出码 0（两次，22.0s / 21.8s）；`--perf` 退出码 0（44.2s）；plain `--quit-after` 退出码 0（6.4s）。**0xC0000374 未复现**（修复前试导出/旧发布均复现，见 §7.4）。证据 `开发产物/release_verify/crash_evidence/final/exit_codes.txt` 及各例 stdout/stderr。

**导出 EXE 窗口自动化验收（window_auto_smoke.ps1）**：`RESULT=ALL_PASS`
- ① 窗口 `--selftest`：EXIT=0，31.2s，**[TEST] RESULT 55/55 passed**（窗口模式含 2 项真实鼠标拖动）。
- ② `--shots`：EXIT=0，85.7s，**61 张 PNG**（`final_shots/`；日志 62 行 = 61 张 + 1 条 rocks hero 信息行，实际落盘 61，脚本按 61 断言未放宽）。
- ③ `--transition`：EXIT=0，22.7s，**13 张**（`final_transition/`）。
- 汇总 `开发产物/release_verify/window_smoke/auto_smoke_summary.txt`，总日志 `开发产物/logs/release/30_window_auto_smoke.log`；stderr 均为已知环境噪声（user:// 不可写导致 shader cache f.is_null、日志/截图写入失败、根证书），无 SCRIPT ERROR / 资源缺失。

**发布目录覆盖与发布位置可执行性**：
- 三处 sha256 全部 = `b3b4e4ab492b471da0472432749c9ac9faea225700443806389d803fbd9684f8`：`开发产物/release_verify/p6_20261021_final/isle_p6.exe`、`发布/休闲小岛幻境.exe`（116,768,848 B，00:13 覆盖）、`构建输出/休闲小岛幻境.exe`。旧发布已备份为 `开发产物/backup/release_pre_p6close/休闲小岛幻境_20261020_2045.exe`（122,950,336 B / `e2a9d242…`）。
- 在**最终交付位置** `发布/休闲小岛幻境.exe` 实测：`--headless --quit` 退出码 0；`--headless -- --selftest` **53/53 passed、退出码 0**（`开发产物/logs/release/22_final_location_selftest.out.log`，仅 1 项真实鼠标 SKIP）。
- 构建 HEAD 说明：文档记录的导出 HEAD 为 `6ac049e`（verify-visual 第一笔视觉文档提交），其后 `7a5b488`/`3161429` 均为 docs-only；`3ab7d9a` 与 `6ac049e` 两次重导出字节均与 freeze 完全一致，证明后置 docs/test 提交不影响发布字节。

## 10. 通过 / 未通过 / 未验证清单

### 10.1 已通过（有实测证据）
- 回滚能力：git 基线 tag + 发布版备份 + 归档 SHA256（§2）。
- 水面一致性：probe_water6 17/0，CPU/GPU 4320 点最大误差 0.000000 m，参数容差 1e-6；画质档波数 [3,4,6,7]（§4）。
- AO：接入并有真实效果/成本数据（四机位像素差；q2/q3/q4 成本 +1.13/+1.70/+4.33ms，q0/q1 关闭），无伪影；体积雾评估后不接入并移除误导入口（§5）。
- 天文：probe **2489/0/known_bug=0**、NOAA+AE **46/46 PASS**、误差在预设容差内；real 模式时区语义 BUG 已修复并回归（§6.3）。
- 生命周期：FX 池泄漏修复，selftest 泄漏行 50→0、orphan 11→0；两项独立问题已分类留证（§7）。
- 画质接线：24 键 173/173 真实作用，覆盖开关与预设不互相覆盖（§8.1）。
- 分辨率/窗口/回退：矩阵 934 + 回退 118 + DPI 86 = 1138 项，0 FAIL（§8.2）。
- 音频总线：probe_audio6 232/0（§8.3）。
- 引用完整性：53 条未解析引用真实失效 0（`docs/P6_REFERENCE_AUDIT.md`）。
- 波浪/AO/质量/菜单/设置等既有探针回归：423/0、232/0、173/173、152/0、51/0、17/0、46/0 等（§9.1）。

### 10.2 未通过 / 未解决（已量化、留证）
- **（原 P0 候选，已解除）导出 exe 退出 0xC0000374**：修复前试导出包/旧发布包曾复现；加入 FX 池释放修复后，FREEZE 构建与最终发布包的退出码矩阵（selftest×2 / perf / quit / 窗口 selftest）**全部 EXIT=0，未再复现**。保留历史崩溃材料 `开发产物/release_verify/crash_evidence/`，建议下阶段在 WER dump 可用时做一次符号化确认（非阻塞，§7.4）。
- `--quality N` 命令行参数在启动时被 `_apply_user_settings` 重置为存档值/默认 2（P2 测试工具缺陷）：`main.gd` 先在 `_ready` 读取命令行写入 `_quality`，随后 `_apply_user_settings(false)` 又按 `Settings.sanitize_quality(_settings.get("quality", 2))` 覆盖。只影响 `--perf --quality N` 这一测试入口；玩家路径与五档循环数据（`_run_perf` 内部 `_apply_quality(4..0)`）不受影响。修复方法：在 `_apply_user_settings` 质量赋值后重读 `_cmdline_value("--quality")`，冻结后未改代码（§12.2）。
- 导出 exe 退出期偶发 `WARNING: 4 ObjectDB instances were leaked at exit`（FREEZE 矩阵 selftest_2 / perf_1 各一次，退出码 0）：源码工程与发布位置复测均未出现；与 headless Dummy 音频退出竞态同类，属引擎退出诊断，已留证，不影响可执行性（§7.4）。
- headless Dummy 音频退出竞态 8 对象 + Orphan StringName：引擎侧，应用清理无效（实测），仅日志告警、不影响退出码；保留证据（§7.4）。
- probe_fx_p4 鸟群起飞/降落 1 项 FAIL：基线 `8f80b13` 已复现，既有行为回归，非本轮引入；是否修需玩法口径（§7.5）。
- `isle_settings.gd` 与 `isle_quality.gd` 的覆盖合并语义不一致（P2，仅记录）（§8.1）。

### 10.3 未验证（客观限制）
- **真实高 DPI（125%/150%/200%）**：本机系统缩放固定 100%，仅用 `content_scale_factor` 模拟；需在真实高 DPI 设备复测（§8.2）。
- **超宽屏/4K 实机窗口**：3440×1440 与 3840×2160 通过 viewport/窗口尺寸矩阵验证，未在对应物理显示器上肉眼确认（4K 用 viewport 捕获验证纹理 3840×2160）。
- **音频主观试听**（白天/黄昏/夜晚的火焰声、蟋蟀声、无重复/刺耳）：本轮无音频设备/无法主观试听，只有 probe_audio6 数值与生命周期断言；需人工试听确认。
- **视觉验收的“修改前后”对比**：AO/FOG 有 off/on 像素与截图对比（§5）；水面波浪同源属“核实既有实现”，无修改前后对比可做；其余画面已由 T5 阶段 2 人工看 85 张 + 发布包 EXE 实看 27 张 + 61/13 张全量数值配对（§9.2），无遗留未看项。
- **导出 exe 的窗口模式长时间稳定性**（>数分钟、Alt-Tab、分辨率切换）：仅做 6s 窗口冒烟与 selftest；长跑稳定性未验证。

## 11. 剩余风险与下阶段开始前必须处理的阻塞项

| 等级 | 项 | 影响 | 建议 |
|---|---|---|---|
| 发布阻塞 | **无**。最终包已完成 §9.4 全部校验（包内容/字体/音频/shader、窗口 55/55 + 61 截图 + 13 转场、退出码矩阵、发布位置复测）后覆盖 `发布/` | — | 旧版已备份 `开发产物/backup/release_pre_p6close/`，可回滚；运行手册 `开发产物/logs/release/FINAL_RELEASE_RUNBOOK.md` |
| 低 | 导出 exe 退出期偶发 `4 ObjectDB instances leaked` 警告 | 仅 stderr 诊断，退出码 0；发布位置/窗口复测未复现 | 下阶段随 0xC0000374 观察项一并观察 |
| 低 | `--quality` CLI 被重置（P2 测试工具） | 仅影响 `--perf --quality N` 命令行指定档位 | 下阶段一行修复并补断言 |
| 中 | 真实高 DPI 未验证 | 高 DPI 用户可能遇到缩放/点击区域问题 | 下阶段在 125%/150% 设备复测 |
| 中 | 音频主观试听未做 | 可能存在刺耳/重复等主观问题 | 下阶段人工试听并记录 |
| 低 | probe_fx_p4 鸟群基线 FAIL | 既有节奏断言与当前行为不符 | 按玩法口径决定修断言还是修行为 |
| 低 | 设置覆盖合并语义不一致（P2） | 极端自定义组合可能与预设合并结果不同 | 下阶段统一 merge_overrides 语义 |
| 低 | `sounds/` 删除已归档 | 若未来需要早期录音可从归档恢复 | 归档含 SHA256，可恢复 |

## 12. 复现命令与证据索引

### 12.1 环境准备（DSH 沙箱必须）
```bash
export APPDATA='D:\\休闲小岛幻境\\开发产物\\appdata'
ENG="D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe"
PROJ="D:/休闲小岛幻境/游戏工程"
```

### 12.2 关键命令
```bash
# 自测（headless 53/53；窗口 55/55 需 win64.exe）
"$ENG" --headless --path "$PROJ" -- --selftest
# 水面同源
"$ENG" --headless --path "$PROJ" --script res://tools/probe_water6.gd
# 画质 24 键 + 高级覆盖
"$ENG" --headless --path "$PROJ" --script res://tools/probe_quality_override_t7.gd
# 天文交叉校验（先 node gen_ref_t7.js 生成参考）
"$ENG" --headless --path "$PROJ" --script res://tools/probe_astro_xcheck_t7.gd
node 开发产物/logs/astro/compare_t7.js 开发产物/logs/astro/probe_t7.log 开发产物/logs/astro/ref_t7.json
# 生命周期退出诊断
"$ENG" --headless --path "$PROJ" --verbose -- --selftest   # 退出日志应无 ObjectDB/RID 泄漏行
"$ENG" --headless --path "$PROJ" --verbose --script res://tools/probe_exit_diag_t7.gd
# 分辨率/窗口/回退/DPI 矩阵
"$ENG" --path "$PROJ" --resolution 1600x900 --script res://tools/probe_ui_matrix6.gd
# 截图/转场/性能（窗口）
"D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64.exe" --path "$PROJ" --resolution 1600x900 -- --shots
"D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64.exe" --path "$PROJ" --resolution 1600x900 -- --transition
"D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64.exe" --path "$PROJ" -- --perf
# 最终发布导出（FREEZE 后）
bash 开发产物/logs/release/final_release.sh
```

> **备注（P2 已知缺陷，留待下阶段）**：`-- --perf --quality N` 的五档覆盖不生效——`_ready()` 里 `scripts/main.gd:247-251` 先按 `--quality` 赋值，随后 `_apply_user_settings(false)`（`scripts/main.gd:3252`）又用自动化默认设置 `quality=2` 覆盖，导致 `[PERF] begin ... quality=2`。修复方式（1 行）：在 `_apply_user_settings` 的质量赋值后加 `if _perf and _cmdline_value("--quality") != "": _quality = Settings.sanitize_quality(int(_cmdline_value("--quality")))`。**不影响本轮验收**：`_run_perf()` 内部本就执行 `_apply_quality(4..0)` 五档循环（`scripts/main.gd:3171` 起），§9.3 五档数据即来自该循环；且该参数只用于自动化跑分，玩家运行路径不涉及。因 FREEZE 后不再改产品源码、发布包已按 FREEZE 构建，本轮记录不修。

### 12.3 证据索引
| 内容 | 路径 |
|---|---|
| git 基线/回滚/环境/已知故障 | `游戏工程/docs/P6_BASELINE.md` |
| 测试说明与全部入口 | `游戏工程/docs/P6_TESTING.md` |
| 引用审计 | `游戏工程/docs/P6_REFERENCE_AUDIT.md` |
| AO/FOG 评估（像素统计/成本/复现） | `游戏工程/docs/P6_AO_FOG_EVAL.md` |
| 天文验收（方法/误差/局限） | `游戏工程/docs/P6_ASTRO_ACCEPTANCE.md`、`docs/P6_ASTRO_ACCURACY.md` |
| 生命周期（复现矩阵/分类/修复/证据） | `游戏工程/docs/P6_LIFECYCLE_FINDINGS.md` |
| 发布打包（sounds/addons/干净目录） | `游戏工程/docs/P6_RELEASE_PACKAGING.md` |
| 视觉/分辨率验收 | `游戏工程/docs/P6_VISUAL_ACCEPTANCE.md` |
| T4 重跑记录 | `游戏工程/docs/P6_TEST_RESULTS.md` |
| 日志 | `开发产物/logs/{lifecycle,release,visual,verify,astro}/` |
| 截图 | `开发产物/shots6/{ao,verify_visual,verify/shots,verify/transition}/` |
| 发布版备份 | `开发产物/backup/release_pre_p6close/` |
| 归档（sounds/中间脚本/根目录临时文件） | `开发产物/archive/` |

## 13. 最终结论

**总判断：当前版本稳定，可以进入下一阶段；没有不可接受的发布阻塞项。** P6 的功能已真正接通、关键问题有复测证据，工程处于可恢复（git 基线 tag + 旧发布版备份）、可测试（headless 53 条 + 窗口 55 条断言、16+6 探针、UI 矩阵 1138 项、发布包自动化冒烟）、可继续演进（分支 `p6-closeout`，FREEZE tag `freeze-p6close-20261021_0515`）的状态。

1. **当前版本是否稳定到足以进入下一阶段？**
   **是。** 依据：最终发布包 116,768,848 B（sha256 `b3b4e4ab492b471da0472432749c9ac9faea225700443806389d803fbd9684f8`）在干净目录与发布位置均实测——headless `--selftest` 53/53 exit 0、窗口 `--selftest` 55/55 exit 0、`--shots` 61 张、`--transition` 13 张、退出码矩阵 `selftest×2 / perf / quit` 全 0；FREEZE 后全量自动化（headless 16 探针 + 窗口 6 项）0 新增失败；T5 视觉审查实看 85 张 + 发布包 EXE 实看 27 张 + 61/13 张全量数值配对，无 P0/P1/P2。剩余项均为下阶段 triage/环境限制（§11），不阻塞。
2. **哪些问题已经彻底解决？**
   ① 波浪定义分裂（复核确认已同源，4320 点误差 0.000000 m，参数容差 1e-6，`probe_water6` 17/0）；② AO 与高级覆盖“只改状态不改渲染”（`633ec8c`，24 键 173/173，AO 有真实效果与分档成本）；③ 体积雾误导入口（评估后不接入并删除菜单项）；④ real 模式时区平移天体 P1 BUG（`a43ca8c`，selftest 断言重写 + astro 回归）；⑤ FX 池退出泄漏 P0（`bd078b0`：泄漏行 50→0、orphan 11→0，0xC0000374 未再复现）；⑥ `sounds/` 零引用 47.9MB 资源与海浪导入告警（归档 + 从包排除）；⑦ 发布包误带 `addons/godot_ai`（`55a8d73`，包内 0 条）；⑧ P6 中间文件与根目录临时文件；⑨ 缺失引用误报（真实失效 0 条）；⑩ 无 Git 版本管理与回滚点。
3. **哪些问题修复了代码但尚未完成视觉验证？**
   严格意义上没有“完全未看图”的代码改动：AO 有 off/on 四机位像素差、截图与 debug 遮蔽图；时区 P1 由 selftest/astro 数值断言覆盖且全量截图无时间错位；FX 生命周期属退出期行为（日志 + 断言可证）；24 键画质有窗口 `quality6` 11 张 + T5 q0–q4 对比；发布包有 EXE 61+13 张全量配对。仍属“未验证”的是必须动态观察或真机的项：动态抗锯齿/水面闪烁（无录屏）、真实 150%/200% 系统 DPI、物理超宽屏/4K 肉眼确认、音频主观试听。
4. **哪些问题存在客观环境限制？**
   真实高 DPI（本机系统缩放固定 100%，仅 `content_scale_factor` 模拟，1.25× 已覆盖、1.5× 为越界压力测试）；物理超宽屏/4K 输出（用窗口矩阵与 viewport 捕获替代肉眼）；音频主观试听（无音频设备/无法试听，仅数值与生命周期断言）；WER dump + release 符号（0xC0000374 未做符号级确认，且该崩溃在 FREEZE 构建已不复现）；headless Dummy 音频退出竞态与导出包偶发 4 对象退出告警（引擎侧，已实测应用侧无法消除）。
5. **下一阶段开始前，是否仍然存在不可接受的阻塞项？**
   **不存在。** 建议下一阶段任务清单保留 4 项 triage/补验（按优先级）：① 真实高 DPI 设备 + 音频主观试听；② `--quality` CLI 被重置的一行修复 + 对应断言（§12.2）；③ WER + release 符号确认 0xC0000374 已彻底消失；④ 设置覆盖合并语义统一（P2）与 `probe_fx_p4` 既有 FAIL 的玩法口径决策。以上均不得以删除检查项、放宽断言或修改文档状态的方式关闭。

**交接材料**：本报告 + `docs/P6_TEST_RESULTS.md`（T4 全量实测）+ `docs/P6_VISUAL_ACCEPTANCE.md`（T5 视觉/分辨率/EXE 复核）+ `docs/P6_RELEASE_PACKAGING.md`（T2 发布包）+ `docs/P6_LIFECYCLE_FINDINGS.md`（T1 生命周期）+ `docs/P6_REFERENCE_AUDIT.md`（T3 引用/卫生）；复现命令见 §12，证据索引见 §12.3。
