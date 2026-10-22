# P8 — Weather & Seasons：天气 / 四季 / 日历 / 生态联动实施计划

> 版本：v1.1（2026-10-22，Asia/Shanghai）
> **状态：已完成（2026-10-22）**。阶段 3–7 已实现并冻结；完成报告见 `docs/P8_REPORT.md`，测试证据见 `docs/P8_TEST_RESULTS.md`。
> 分支：`p8-weather-seasons`（从 `p7-v4-islander` / `ae9d104` 拉出）
> 本文是 P8 阶段 2 的强制交付物：先调研、先计划、后编码；编码与实测结果另见 P8_REPORT / P8_TEST_RESULTS。
> 口径：本文所有"现状"结论都来自对本机工作区源码的直接阅读（只读），行号指 2026-10-22 的工作区版本；所有外部资料均给出实际抓取状态。

---

## 1. 工程基线与回滚

| 项 | 值 |
|---|---|
| 工作区 | `D:/休闲小岛幻境` |
| 游戏工程仓库 | `D:/休闲小岛幻境/游戏工程`（独立 git 仓库） |
| P8 基线分支 | `p7-v4-islander` @ `ae9d104`（P7-V4 岛民，工作树干净） |
| P8 开发分支 | `p8-weather-seasons`（自 ae9d104） |
| 历史冻结 tag | `baseline-p6close-20261020`、`freeze-p6close-20261021_0515`、`p7-baseline-20261021`、`p7-v4-freeze-20261021` |
| 引擎 | `D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe`（4.7.2.stable.official.ed1daf0bf，Forward+，Vulkan 1.4.351） |
| 参考 GPU | NVIDIA GeForce RTX 2060（驱动 32.0.16.1742，本机） |
| 主场景 | `res://isle.tscn`（单一主场景，1440×900，canvas_items 拉伸） |
| 发布包 | `发布/休闲小岛幻境.exe`、`构建输出/休闲小岛幻境.exe`（116,917,880 B，P7-V3.1 构建，**本轮不覆盖**） |
| 自动化入口 | `--selftest`（53 断言）、`--perf`、`--shots`、`--p7shots`；探针 `godot --headless --path 游戏工程 --script res://tools/probe_xxx.gd` |
| 基线自测 | `开发产物/p8_baseline_selftest.log`：[TEST] RESULT 53/53 passed（1 项 SKIP：headless 无真实鼠标） |
| 回滚 | `git checkout p7-v4-islander`；或 `git reset --hard p7-v4-freeze-20261021`（冻结 tag）；新分支未合并前主分支不受影响 |

**回滚策略**：每个阶段结束打一个轻量 checkpoint commit；阶段验收不通过时只回滚该阶段文件集合（脚本 / shader / docs 三组），不 reset 全仓。发布包在本轮结束前不重新打包，若打包则先备份旧 exe 到 `开发产物/backup/release_pre_p8/` 并记录 sha256。

---

## 2. 需求—现状对照与真实完成度

### 2.1 现状结论（源码直读）

1. **日历**：不存在。工程只有"一天内的秒"（`main._sim_seconds`，0–86399 循环）与真实时间源（`_realtime`）。日期部分只由 `IsleAstro.local_datetime()` 做显示（`Time.get_datetime_dict_from_unix_time`），没有可编辑的年/月/日、没有模拟日期推进（跨日只是 86400 取模，日期不前进）、没有暂停按钮（仅空格）。
2. **季节**：不存在。全工程检索无 season 概念；唯一环境轴是 `IslePalette` 的昼夜 25 帧调色（`isle_palette.gd`）。植被颜色/花卉密度是 `world.gd` 构建时一次性烘焙。
3. **天气**：不存在。全工程检索无 weather/rain/snow；天空只有固定云层（`sky.gdshader` cloud_layers），海面只有波浪/泡沫（`sea.gdshader` + `isle_waves.gd` 契约），没有任何天气状态机、降水、积雪、风场统一驱动。
4. **月球**：`IsleAstro` 的 Meeus 47 章模型精度已被 P6 验证（升落 ±0.1 min、照度 ±1e-4），但**渲染层**存在需要 P8 核验的点：月盘可见性用 `smoothstep(-0.04,0.06,md.y)` 手工门限（`sky.gdshader:259-281`）；明暗由 `moon_waxing` 决定；云层会直接盖住月盘；没有"地平线下不可见/升落方向随日期变化"的自动化断言，也没有把月相与完整朔望周期固定样本对齐的回归。
5. **生态联动**：岛民只以 `sun_alt` 判室内/室外（`isle_villager_schedule.gd:187-198`，阈值 2.0/1.0/8.0）；海鸥只读 `sim_seconds/sim_rate/rising/paused`（`fx.gd:2177-2196`）；小船状态机只部分分支读模拟时间；炊烟有 `set_sim_seconds` 通道。全部没有天气输入。
6. **HUD**：已有时间台（折叠面板：时间来源、大字时钟、时区、每游戏日耗时、时间轴、快捷时刻）与年鉴面板；没有日历编辑、没有暂停按钮、没有天气面板。
7. **性能基线**：P7-V4 记录（154.8–159.9 FPS 全角色）来自上一轮，需按本任务条件重测（见 §10）。

### 2.2 模块依赖图（现状 + P8 新增）

现状权威时间流（唯一源 `_sim_seconds`）：

```
_sim_seconds (main.gd:44, 秒级 0..86399 循环)
  ├─ IsleAstro.compute(_sim_seconds) ─► sun_alt/az, moon_alt/az/illum/waxing ─► _update_lighting()
  │     └─ IsleMath.theme_time() ─► IslePalette.sample(t) ─► 调色板字典
  │           └─ 写 sky.gdshader / sea.gdshader 材质 + toon/grass 全局 uniform(g_*)
  │                 └─ world 全部材质（toon/grass/terrain）→ 最终画面
  ├─ IsleAstro.day_events() ─► _events（日出/日落/月升/月落…）─► HUD 年鉴
  ├─ _eco_ctx() ─► 海鸥 update_birds()（只读 sim_seconds/rising/paused）
  ├─ _villager_ctx() ─► 岛民 sim_tick()（frozen 由 _paused 决定）
  ├─ _advance_sim() ─► _sim_delta / _sim_rate（船、烟、岛民跳时判定）
  ├─ _update_boat() ─► 小船 9 状态机（部分分支读 _sim_seconds/_sim_delta）
  └─ _update_ui() ─► HUD 时钟/日期/月相/太阳高度（只显示）
```

P8 追加（全部只从 `_sim_seconds` 派生，不新建时钟）：

```
_sim_seconds
  └─ IsleCalendar.parts(ls) ─► {y,m,d,h,mi,s,weekday,day_index,season,season_t,weights}
        ├─ IsleSeason.visual(parts) ─► 季节视觉参数（草色/树色/花密度/落叶率/环境色）
        │     └─ 写 grass tint、树冠实例色、花节点 visible、地面 albedo、g_season 全局
        └─ IsleWeather.step(state, dt, parts, seed) ─► 天气状态契约
              ├─ 写 g_weather/g_wind/云量/雨雪量全局 uniform
              ├─ 驱动 rain/snow/leaf 实例化降水层（单 draw call，shader 驱动）
              ├─ 写海面/天空材质参数（wave/foam/cloud_opacity，不改波系数）
              └─ 写生态上下文 weather 字段 ─► 岛民/海鸥/小船/炊烟/萤火/涟漪
```

关键不变量：**`_sim_seconds` 仍是唯一权威模拟时钟**；`IsleCalendar` / `IsleSeason` / `IsleWeather` 全部是纯函数 + 只读派生，不持有自己的时间；暂停/跳日的语义统一在 main.gd 一处判定，模块不自行计时。

---

## 3. 外部资料与官方文档调研（已实际抓取）

### 3.1 Godot 4.7 官方文档（HTTP 200，标题匹配；基址 `docs.godotengine.org/en/4.7/`）

| 主题 | URL | 与本项目相关的结论 |
|---|---|---|
| 全局 uniform | `tutorials/shaders/shader_reference/shading_language.html#global-uniforms` | 原文："Global uniforms allow you to create and update uniforms that will be available in all shaders, in every shader type (canvas_item, spatial, particles, sky and fog)… especially useful for environmental effects that affect many objects in a scene, like having foliage…"；**必须先注册再保存 shader**，否则编译失败；每帧 set 不触发同步/重编译；`global_shader_parameter_get` 有较大性能惩罚 |
| GPUParticles3D | `classes/class_gpuparticles3d.html` | `local_coords` 默认 false（世界坐标，粒子不随发射器移动）；`visibility_aabb` 默认 `AABB(-4,-4,-4,8,8,8)`，自定义体积必须显式设置否则被剔除；draw call 与粒子数无关（每 draw_pass 一次实例化）；`amount` 上限 1,000,000；改 `amount` 会重启系统、改 `amount_ratio` 不会 |
| MultiMesh | `classes/class_multimesh.html` | 原文："MultiMesh is much faster as it can draw thousands of instances with a single draw call"；缺点："if the instances are too far away from each other, performance may be reduced"，AABB 必须提供；多实例不接收光照 |
| MultiMeshInstance3D | `classes/class_multimeshinstance3d.html` | 节点封装，照常入场景树 |
| 3D 优化 | `tutorials/performance/optimizing_3d_performance.html` | 自动实例化仅在 Forward+ 且材质为 opaque/alpha-tested；否则用 MultiMesh；"ideal for flocks, grass, particles" |
| 粒子系统教程 | `tutorials/3d/particles/index.html` | GPUParticles3D（GPU 处理）vs CPUParticles3D（CPU）；本项目用 GPU |
| Environment | `tutorials/3d/environment_and_post_processing.html`、`classes/class_environment.html` | 有 fog_enabled/fog_sun_scatter/fog_height 等；但本项目 toon/sea/sky 均自写雾，Environment 雾对它们无效 |
| CompositorEffect | `classes/class_compositoreffect.html` | **Experimental**："The implementation may change as more of the rendering internals are exposed over time" → 不作为方案依赖 |
| Time | `classes/class_time.html` | Proleptic Gregorian；年 0 = 1 BC；转换方法不做时区/DST、不处理闰秒；`get_unix_time_from_datetime_dict` 空字典返回 0、缺省键按 Unix epoch；`_from_system` 用系统时钟可被用户手改，"Never use this method for precise time calculation" |
| 屏幕读取 shader | `tutorials/shaders/screen-reading_shaders.html` | `hint_depth_texture` 深度采样；Godot 4 已移除 DEPTH_TEXTURE 内置 |
| heightfield 碰撞 | `classes/class_gpuparticlescollisionheightfield3d.html` | 实时高度场，明确"cannot represent overhangs (e.g. indoors or caves)" → 不用于室内遮挡 |

### 3.2 天文与月相基准

| 来源 | 状态 | 用途与口径 |
|---|---|---|
| NASA GSFC《Phases of the Moon: 2001 to 2100》（Espenak）`https://eclipse.gsfc.nasa.gov/phase/phases2001.html` | **HTTP 200，已抓表** | 逐年 UT 月相时刻；平均朔望月 29.530588 天。P8 用 2026 全年新月/上弦/满月/下弦样本做固定断言（本地 UTC+8 = UT+8h） |
| NASA Science 月相页 `https://science.nasa.gov/moon/moon-phases/` | HTTP 200 | 月相命名与照度语义核对 |
| USNO AA API `https://aa.usno.navy.mil/api/...` | **不可达**（getaddrinfo EAI_AGAIN，DNS 失败） | 与 P6 记录一致；文档如实记录，不伪造 |
| timeanddate.com | HTTP 403（Cloudflare） | 不可用 |
| P6 已建立的 astronomy-engine 2.1.19 基准 | 本地 npm 包 + `开发产物/t6_astro/` 缓存 | 月升/月落/照度数值参考；P8 月相验收沿用 |
| NOAA Solar Calculator `https://gml.noaa.gov/grad/solcalc/` | HTTP 200（P6 已验证） | 太阳升落/方位参考 |

**月相回归方案**（阶段 3.2）：固定 2026 年 8 个相位时刻（新月/娥眉月/上弦/盈凸/满月/亏凸/下弦/残月各一），对每个样本断言：(a) `IsleAstro.compute` 的 `moon_illum` 落在该相位 ±0.06 内；(b) `moon_waxing` 在盈/亏侧正确；(c) 月盘世界高度与 `moon_alt` 一致（渲染层可见性函数）；(d) 月出/月落时刻与 NASA（转换成本地时刻）差 ≤10 min；(e) 24h 连续采样无跳变。**覆盖完整朔望周期**（2026-01-03 至 2026-01-31 连续 29.5 天，每 30 min 采样），而不是只测 18:00 单点。

### 3.3 社区/工程资料

| 来源 | 状态 | 用途 |
|---|---|---|
| godotshaders.com 积雪覆盖 surface 参考 | 抓取受限（页面未取得完整正文） | 仅作思路参考：world normal 朝上 + 阈值混合；本项目落点在 toon.gdshader |
| Godot 4.4 Ubershader / shader baker | 官方 release notes / PR 引用 | 新 shader 首次编译的 PSO 卡顿可由载入期预热规避；P8 新增 shader 统一在场景构建时预热 |
| 本项目 P6_AO_FOG_EVAL.md | 本地 | 全 unshaded 管线 AO/体积雾无效、体积雾会把海面染暗 → 天气不引入体积雾 |
| 本项目 P6_ASTRO_ACCURACY.md | 本地 | 天文精度验收口径（见 §3.2） |

---

## 4. 候选方案对比与选型

> 原则：不因"技术上存在"就选；每项给出官方证据、对现有管线的侵入、成本估算与结论。数值型过度绘制/填充率为按 RTX 2060/1600×900/170 FPS 的**估算**（文档不提供 overdraw 实测），待阶段 6 用游戏内 A/B 实测替换。

| 方案 | 做法 | 利 | 弊 / 风险 | 结论 |
|---|---|---|---|---|
| A 局部 GPUParticles3D | 岛 + 近海发射盒内 GPU 粒子 | 官方主路径、可 GPU 模拟、draw call 与粒子数无关、改 `amount_ratio` 不重启 | 需显式 `visibility_aabb`（默认 8³ 会被剔除）；透明过度绘制；headless 下无法断言粒子状态；室内遮挡要额外处理 | **主力**（分档 1.5k/5k/12k/24k/48k + 溅落；雪取 1/4） |
| B MultiMesh 雨丝 + CPU 更新 | 每条雨丝一个实例，CPU 每帧改 transform | 单 draw call | CPU 更新 5 万级即 ≫ 帧预算（估算 50 万实例 100–250 ms/帧）；无逐实例剔除 | **不采用**（仅用于可完全 shader 驱动的落叶/静态雪片等） |
| C 全局 uniform 参数化 | 新增 `g_weather`(vec4)/`g_wind`(vec4)（+可选 `g_season`），所有材质共享 | 官方明确支持"environmental effects… foliage"；每帧 set 无性能影响；与现有 30+ 个 `g_*` 一致；单一事实源 | 新增全局 uniform 前必须先注册再加载 shader；类型不能运行时变；`get` 有惩罚 | **全案基础** |
| D 屏幕空间雨幕/深度遮罩 | 相机子节点全屏 quad + `hint_depth_texture` | 可精确区分窗内外、远处海面雨帘；1 draw call；与粒子数无关 | CompositorEffect 仍 Experimental（不依赖）；需重建世界坐标；透明叠层排序 | **只在室内精确遮挡 / 远景雨帘**使用；沿用 `post_ao.gdshader` 已验证的全屏 quad + 反向 Z 约定 |
| E 雾 / 积雪低成本方案 | 复用 sky/sea/toon 的雾与混色 | 零新增几何/零 draw call；积雪为连续 uniform 插值，屋顶/石台/草叶天然同步 | 需给 toon 加世界法线 + 世界坐标；水平面判断要抑制垂直面"刷白" | **采用**：积雪在 `toon.gdshader` 末段混色（约 6 行）；雨雾继续用现有 `g_fog_near/far` |
| F heightfield 降水碰撞 | GPUParticlesCollisionHeightField3D | 官方称适合雨雪 | 官方明确无法表达 overhang（室内/屋檐）；`follow_camera_enabled` 强制重建；分辨率 256–2048 成本高 | **不采用**（室内用 `g_occ_*` 盒 + indoor uniform 淡出） |

**选型结论**：C + A + E 为主，D 仅做室内精确遮挡与远景雨帘补充，B/F 弃用。所有新增 shader 首次使用时在载入阶段预热一帧（避免首次下雨卡顿）。

**最小隔离原型（阶段 6 前置，实测选型证据）**：在游戏内新增 `--p8perf` 采样模式，同一机位对 晴 / 小雨 / 中雨 / 大雪 / 台风 五态各采 180 帧，记录 FPS/frame_ms/cpu_ms/draw_calls/objects/VRAM；并临时用命令行 `--rain-count N` 扫 1.5k/12k/48k 三档，验证"draw call 恒定、帧时间随数量线性上升"。结果写回本文 §10 并进入阶段 6 报告。若 48k 档在 1600×900/quality2 下 frame_ms 超过预算，则默认档降到 24k 并把 48k 只留给极致档。

---

## 5. 日期 / 日历规则（阶段 3 规格）

- **单一权威源**：`main._sim_seconds`（模拟秒，UTC+8 本地秒数轴）。不新增任何"季节时钟/天气时钟"。
- **日历体系**：Proleptic Gregorian（与 Godot `Time` 一致，1582-10-15 前为 1582-10-14），年份支持 1–9999（显示；内部用 Unix 秒）。闰年：`y%4==0 and (y%100!=0 or y%400==0)`；大小月：1/3/5/7/8/10/12=31，4/6/9/11=30，2 月平年 28/闰年 29。
- **实现**：`scripts/isle_calendar.gd`（`class_name IsleCalendar`，全 static）：
  - `parts(local_seconds) -> Dictionary`（y/m/d/h/mi/s/weekday/day_index/sod/season/season_t/season_weights/season_label）
  - `to_local_seconds(parts) -> float`（非法输入 clamp，返回当天 0 点 + 时分秒）
  - `is_leap(y)` / `days_in_month(y,m)` / `days_in_year(y)` / `weekday_cn(d)`
  - 不依赖 Godot `Time` 之外的外部状态；纯函数可 headless 断言。
- **一年天数** 365/366；跨年、跨月、跨日由 `_sim_seconds` 连续推进自然完成（模拟模式 `_sim_seconds += delta*86400/day_length`，不再对"天"取模——现有代码只用 `fposmod(...,86400)` 取当天内秒数，日期从绝对秒数派生即可）。
- **现实时间模式**：`_sim_seconds = now+28800`（现状不变），日历显示真实日期；不允许改日历（与现状时间轴禁用一致），只读。
- **暂停**：模拟模式下新增可见暂停按钮 + 空格同一状态 `_paused`；暂停时 `_advance_sim` 不推进 → 日期/季节/天气调度/岛民日程/船/鸟/模拟动画全部冻结（它们都只从`_sim_seconds`/`_sim_delta` 派生）；HUD 时钟、天气面板、菜单仍可操作（不依赖推进）。
- **跳转**：日历面板可直接编辑 年/月/日/时/分（± 按钮与直接数值滚动），确认后调用 `_jump_datetime(y,m,d,h,mi)`：写 `_sim_seconds`、重算 `_events`、清 `_time_jump` 语义（`_time_jump += Δ` 供岛民/船"跳时不补演"判定）、立即 `_update_lighting()` 与天气重评估；跳转后不播过渡动画（不补演雨/雪/日程），直接进入目标时刻合法状态。
- **视觉动画**：降水/落叶的相位动画由 shader 的 `TIME` 驱动，暂停时**同时冻结**（暂停把全局 `g_weather.w/相位` 停更，shader 用 uniform 时间而非内置 TIME）；天气过渡本身按真实 delta 插值但暂停时冻结。文档明确两者关系。

---

## 6. 季节规格（阶段 4）

- **北半球公历季**：春 3–5、夏 6–8、秋 9–11、冬 12–2。季节边界做 **±10 天连续混合**（`season_weights` 在边界两侧 smoothstep），不瞬间切换。
- 季节只修改"视觉/生态参数"，不替代日月算法，不改 `IslePalette` 帧表；调色叠加在 `sample()` 结果之上。
- 参数模型（`IsleSeason.visual(parts) -> Dictionary`）：
  `{grass_tint, ground_tint, foliage_tint, leaf_fall, flower_scale, flower_species_scale, snow_ok, ambient_tint, name, t}`。
- 植被（低成本、零重建）：
  - **草**：改 `GrassNear/GrassFar` 材质 `tint`（两材质独立，每帧只写参数）；冬季偏黄绿、夏季饱和；密度仍由画质 `grass_density` 控制（季节只调色，不调密度，避免两条写入路径互相覆盖）。
  - **树冠**：不重建 mesh；按构建时记录的节点/实例色基色，按季节插值写回实例色（44+80 实例级，可接受）；秋季黄橙红、冬季降低饱和度并转裸枝色（叶卡 visible 或色值变暗）。
  - **花**：按节点名 `FlowerStems_<Name>` / `FlowerHeads_<Name>_<vi>` 的 `visible` 控制季节显隐与规模（春渐开、夏盛、秋减、冬仅红梅）。**红梅**：冬季只保留少量隐藏品种（新增一个最小梅花物种或复用一个现有 head 变体染红），不新增贴图/模型，仅程序化几何/顶点色。
  - **地面**：在 `terrain_material` 的 albedo 上乘季节色（不改顶点色、不重烘焙）。
- **验收**：四季基线截图（同一机位、同一时刻）→ 季节过渡逐 7 天采样截图；跨季跳转后节点数不增长、无失效实例、资源计数稳定。
- **不做**：不做雪帽几何（材质混色优先）；不做地形重烘焙；不每帧重建树/花。

---

## 7. 天气状态模型与联动（阶段 5）

### 7.1 状态契约（单一结构，模块/生态统一消费）

```
{
  mode: "auto"|"manual",
  type: String,             # 13 种之一
  label: String,            # 中文显示
  intensity: float,         # 0..1（同类强度）
  intensity_label: String,  # 小/中/大（可无）
  transition: float,        # 0..1 向当前 type/intensity 的过渡进度
  season: int,              # 0春1夏2秋3冬
  season_label: String,
  season_t: float,
  cloud: float,             # 0..1 云量
  wind_dir: Vector2,        # xz 风向单位向量
  wind_strength: float,     # 0..1
  precip_type: String,      # "none"|"rain"|"snow"
  precip_intensity: float,  # 0..1
  wetness: float,           # 0..1 环境湿润
  snow_depth: float,        # 0..1 积雪程度
  snow_trend: float,        # >0 积累 / <0 消融 / 0 稳定
  hold_left: float,         # 当前天气剩余秒（模拟秒）
  auto: bool
}
```
写全局 uniform：`g_weather = vec4(rain, snow, indoor, snow_cover)`、`g_wind = vec4(dir.x, dir.z, strength, t)`（`t` 为动画相位，暂停冻结）；另可直接写现有 sky/sea 材质参数（cloud_opacity/cloud_detail/foam/wave 等）。

> **P8.1 注记**：状态契约 `type` 自 P8.1-04 起为 **12 类之一**（windy 并入 strong_wind），新增字段与口径以实现为准。详见 docs/P8_1_REFINEMENT_REPORT.md §4。

### 7.2 13 种天气

晴 / 多云 / 阴 / 有风 / 强风 / 小雨 / 中雨 / 大雨 / 小雪 / 中雪 / 大雪 / 雷暴 / 台风。
- 雪只在冬季为合法自动选项；其余季手动可选（广州自动雪概率极低，艺术化权重）。
- 台风主要夏秋；雷暴按季节权重（春夏高、秋冬低/无）。
- 自然倾向与手动区分：自动权重表按季；手动选择不做季节惩罚（但可在提示里标注"少见"）。

> **P8.1 注记**：P8.1 起为 **12 类**（“有风”并入强风状态）；自动雪权重为 0，雪仅冬季手动可选；台风仅夏/秋。详见 docs/P8_1_REFINEMENT_REPORT.md §4。

### 7.3 自动天气调度（确定性、可复现、跳时不补演）

- 只读权威 `parts.day_index` + `_weather_seed`（默认取设置/命令行）；以"天气槽"推进：每个槽有持续时长（按类型与强度从区间取，如 6–20 min 模拟时间，具体见实现表），槽内类型/强度恒定，槽间做 1.5–4 s 平滑过渡。
- 随机源：`hash(seed, slot_index)` 派生（不用 `randf()` 全局状态），保证同 seed/同日同时刻结果一致；提供 `--weather-seed` 与设置项便于测试。
- 分季权重（示意，最终以实装表为准）：
  春：晴 0.30 / 多云 0.22 / 阴 0.12 / 有风 0.10 / 小雨 0.12 / 中雨 0.06 / 大雨 0.02 / 雷暴 0.03 / 强风 0.02 / 台风 0.01
  夏：晴 0.26 / 多云 0.18 / 阴 0.08 / 有风 0.06 / 小雨 0.10 / 中雨 0.08 / 大雨 0.06 / 雷暴 0.08 / 强风 0.04 / 台风 0.06
  秋：晴 0.34 / 多云 0.22 / 阴 0.12 / 有风 0.10 / 小雨 0.08 / 中雨 0.05 / 大雨 0.02 / 雷暴 0.03 / 强风 0.03 / 台风 0.01
  冬：晴 0.38 / 多云 0.24 / 阴 0.14 / 有风 0.10 / 强风 0.04 / 小雨 0.04 / 中雨 0.02 / 小雪 0.02 / 中雪 0.01 / 大雪 0.005 / 雷暴 0.0 / 台风 0.0
- 规则：最短持续（如 4 min）/ 事件冷却（强天气后 15–30 min）；允许长时间晴、连续阴、偶发强天气；季节切换时把不兼容天气在过渡内转为合法类型（雪→雨/阴并渐融雪）；暂停不推进；跳日期直接按目标时刻重算槽位，不补演中间过程。

### 7.4 生态联动

| 对象 | 接入点 | 行为 |
|---|---|---|
| 岛民 | `main._villager_ctx()` 加 `weather` 键 → `isle_villager.gd` 透传 → `schedule.gd` 在 187-198 后并联：雨/雪→户外活动改门廊/室内；强风/台风→不出门；雪天可赏雪（少量户外活动） | 不改变既有日程窗口与预约逻辑，只加过滤 |
| 海鸥 | `_eco_ctx()` 加 `weather`；`BirdFlock` 在暴雨/大雪/台风时降低活动、缩短飞行、回栖枝；风向影响飞行方向偏移 | 不改变栖点分配算法 |
| 小船 | `_start_boat_departure` 开头加天气门控：大雨/雷暴/台风/大雪不出港；糟糕天气返回时提前回港 | 不改航线数据 |
| 炊烟 | 已有 `set_sim_seconds` 通道加 weather 参数：强风时烟更斜/更短、雨雪时烟更淡 | 只改参数 |
| 萤火 | 雨/雪/强风时 `emitting=false` 或降量 | 只改开关 |
| 涟漪/水花 | `Ripples.update(delta, sun_alt, weather)` 加雨强系数（雨点涟漪） | 复用现成系统 |
| 风场 | `g_wind` 同驱草摆/树冠/雨线/雪花/云速/海浪白沫；海面**不缩放波幅**（与 `isle_waves.gd` 契约），只改泡沫/纹理/云 | 统一一个风向量 |

### 7.5 UI 方案（阶段 5）

- 时间台扩展：折叠面板内加"日历"行（年/月/日 + 时:分 编辑、± 按钮）+ "暂停 / 继续"按钮（与空格同一状态）；保留观景简洁感，面板可收起（T 键同）。
- 天气面板：独立可折叠面板（仿时间台样式：折叠胶囊 + 展开面板），内容：模式（自动/手动）开关、当前天气大字 + 强度、手动选择（只列当前季节合法项，非法项隐藏/置灰并提示）、季节/过渡进度、未来趋势（下一槽类型/距现在）、风速/云量小字。自动模式下手动选择自动切手动；手动模式可切回自动。
- 设置：`isle_settings` 新增键 `weather_mode`（auto/manual）、`weather_manual`（字符串）、`weather_seed`（整数）；菜单"设置→天气"区块（三行，随现有 row 工厂）；HUD 观景模式隐藏时面板同步收起。

---

## 8. 分阶段任务 / 依赖 / 验收 / 回滚

| 阶段 | 内容 | 依赖 | 验收 | 回滚 |
|---|---|---|---|---|
| 1 | 侦察 + 基线重测 + 本文 | — | 基线 selftest 53/53；perf 数据；依赖图 | 无需 |
| 2 | 本文档（外部资料/选型/规则/UI/预算/风险） | 1 | 本文评审通过、链接可核 | 只回滚文档 |
| 3 | 日历模块 + 时间台编辑/暂停 + 探针 | 2 | 探针断言：闰年/大小月/跨年/跨日推进/跳转合法/暂停冻结全部通过；截图 | 删 `isle_calendar.gd` + 回退 HUD/main 改动 |
| 3.2 | 月球核验（渲染可见性/明暗/跳日/朔望周期） | 3 | `probe_p8_moon` 全绿 + 8 相位截图 + 报告 | 只回退 sky/main 月盘改动 |
| 4 | 季节视觉（草/树/花/地面/红梅）+ 过渡 | 3 | 四季/过渡截图；节点数稳定；季节切换无残留 | 只回退 `isle_season.gd` + world/main 季节写入 |
| 5 | 天气状态机 + 设置 + 面板 + 确定性探针 | 4 | 13 类型合法/分季权重/暂停/跳日/最短持续/冷暖区间/UI 截图 | 回退 `isle_weather.gd` + UI/设置改动 |
| 6 | 天气视觉逐轮：6.1 全局氛围 / 6.2 雨 / 6.3 雪 / 6.4 风落叶台风 | 5 | 每类"基础→近景→远景→低画质→回归修复"截图 + 性能对照；低画质仍可辨识 | 按小节回退 shader/参数 |
| 7 | 生态联动（岛民/海鸥/船/烟/萤火/涟漪） | 5,6 | 探针断言 + 截图；无行为回归 | 回退各接入点 |
| 8 | 全量回归（selftest 53 + 新增 P8 断言）、性能矩阵、截图终验、P8_REPORT/P8_TEST_RESULTS、冻结 tag | 全部 | 全部通过 | 按阶段 checkpoint 回滚 |

> **P8.1 注记**：阶段 5 验收中的“13 类型合法”在 P8.1 后按 **12 类型** 口径执行（windy 已并入 strong_wind）。详见 docs/P8_1_REFINEMENT_REPORT.md / P8_1_TEST_RESULTS.md。

---

## 9. 性能预算与测试矩阵

### 9.1 预算（1600×900 / quality 2 / VSync off / 晴空正午为基准）

| 项 | 预算 |
|---|---|
| 默认晴天空旷场景 | 不许低于基线 -5%（P8 空闲开销） |
| 中雨 / 中雪 / 台风（quality 2） | frame_ms 增加 ≤ +2.0 ms |
| 低画质（quality 0）雨雪 | 仍可辨识，frame_ms 增加 ≤ +1.2 ms |
| 新增 draw call | 降水 ≤ +4（雨、雪、溅落、落叶各 1）；全天气态总量 ≤ +8 |
| 常驻节点 | ≤ +12 个节点（天气层 + UI 面板） |
| VRAM | 增量 ≤ +40 MB（实例缓冲/纹理） |

### 9.2 测试矩阵

- **日历**：闰年 1900/2000/2024/2026/2100；大小月/跨年/跨月；跳转越界 clamp；暂停冻结（日期、天气槽、岛民日程、船、鸟全部不推进）；现实模式只读。
- **月相**：2026 八个相位时刻 + 连续 29.5 天每 30 min 采样（照度/升降/可见性/明暗方向）；固定日期样本对 NASA（UT+8）。
- **季节**：四季 + 边界前后各 10 天；跳季不残留；四季截图；跨季跳转节点/资源计数稳定。
- **天气**：13 类型 × 季节合法性；auto 权重与最短持续；seed 可复现；暂停/跳日；切换画质 5 档下渲染参数正确；手动选择合法性。
- **P8.1 注记**：天气测试矩阵在 P8.1 后按 **12 类型 × 季节合法性** 口径执行（windy 并入 strong_wind）；自动雪权重为 0、雪仅冬季手动。详见 docs/P8_1_TEST_RESULTS.md。
- **视觉**：6.1–6.4 每类至少 5 张（基础/近景/远景默认机位/低画质/修复后回归）；雨雪室内外、屋檐、海面、夜间、台风。
- **回归**：`--selftest` 53/53 + P8 新增断言；`probe_p8_*` 全绿；旧探针抽查（astro/water/villager/bird/boat）。
- **性能**：晴/小雨/中雨/大雪/台风 × {默认轨道, 近景, 飞行, 室内, 低机位} × quality {0,2,4}，记录 FPS/frame_ms/cpu_ms/P95/draw_calls/objects/VRAM。

---

## 10. 基线实测（阶段 1 结果）

> 条件：RTX 2060、1600×900、quality 2、VSync off、`--perf` 标准场景；原始日志 `开发产物/p8/logs/baseline_perf_stdout.log`；复跑命令见 §11。
> 基线 selftest：`[TEST] RESULT 53/53 passed`（`开发产物/p8_baseline_selftest.log`）。

**实测（2026-10-22 01:11，运行 60 s，exit 0）**。`--perf` 每场景采样 180 帧；`cpu_ms` 为 `Performance.TIME_PROCESS` 监视器读数，出现大于 frame_ms 的噪声（监视器口径与采样窗口不一致），**以 frame_ms/FPS 为主指标**；GPU 时间无直接监视器，按 frame_ms 与 CPU 读数估算。

| 场景 | FPS | frame_ms | cpu_ms* | objects | draw_calls | VRAM MB |
|---|---|---|---|---|---|---|
| noon_clear（默认 12:20 轨道） | 136.6 | 7.32 | 15.23 | 2264 | 1871 | 267.9 |
| golden_cloud_water（17:40 低仰角） | 140.9 | 7.10 | 35.64 | 2281 | 1892 | 268.0 |
| night_shadows（22:40） | 146.1 | 6.84 | 24.93 | 2053 | 1664 | 268.0 |
| night_close（22:40 近景 r=30） | 160.1 | 6.25 | 11.66 | 1645 | 1296 | 268.0 |
| far_island（12:20 r=168） | 114.4 | 8.74 | 18.17 | 2288 | 1895 | 268.0 |
| sky_up（22:40 仰角） | 135.1 | 7.40 | 14.33 | 2044 | 1655 | 268.0 |
| time_panel_open（时间面板展开） | 144.7 | 6.91 | 34.72 | 2466 | 1704 | 269.8 |
| lite_noon_nomultimesh（关 MultiMesh+水面细节） | 153.9 | 6.50 | 22.14 | 1995 | 1602 | 269.7 |
| lite_night_nomultimesh | 159.0 | 6.29 | 13.90 | 1994 | 1605 | 269.7 |
| quality_4（极致） | 80.4 | 12.44 | 18.25 | 2053 | 1660 | 622.5（msaa3 scale1.25 grass22500 lights12） |
| quality_3（极高） | 115.0 | 8.70 | 207.80 | 2046 | 1653 | 562.1（msaa3 scale1.15 lights11） |
| quality_2（高，默认） | 155.8 | 6.42 | 20.30 | 2041 | 1648 | 269.9（msaa2 scale1.00 grass22500 lights9） |
| quality_1（中） | 150.3 | 6.65 | 42.87 | 2039 | 1646 | 202.7（msaa1 scale0.92 grass15750 lights8） |
| quality_0（低） | 129.1 | 7.75 | 47.67 | 2039 | 1646 | 166.5（msaa0 scale0.85 grass10125 lights7） |
| after_6s | — | — | — | nodes=1546 orphan=21 | — | — |

**与历史值差异说明**：P6/P7 记录的正午 172.2 FPS 是 1920×1080/1440×900 等不同条件下的历史值，本表是 P8 口径（1600×900/quality2）下的**本轮实测**，两者不可直接相减；P8 的对比基线一律以本表为准。注意 `quality_0` 的 FPS 低于 `quality_2`，是降分辨率/关 MSAA 后 GPU 受益被 CPU 抖动掩盖的已知噪声（同一轮内多次采样波动），不作为画质档位结论。

**基线截图**：`开发产物/p8/shots/baseline/`（默认轨道/近景/飞行/室内/低机位，`--p8shots --p8shot-set baseline` 生成；见 §11）。

**已知旧问题登记（非 P8 引入）**：
1. 退出时 8 条 ObjectDB 泄漏（P7-V4 遗留，selftest 不报错但日志可见）；
2. 吊灯泛光球过大（视觉遗留）;
3. 楼梯底部宽度 warn；
4. 日志轮转失败（`user://logs/godot.log` 无法写入，权限/路径问题，不影响运行）；
5. 根证书库读取失败（Windows 无证书库，环境性）；
6. P7 船航线注释"8 条"与实装 9 条（4 coastal + 5 far）不符（文档陈旧）。

---

## 11. 复跑命令

```powershell
# 自测
& 'D:\休闲小岛幻境\引擎\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'D:\休闲小岛幻境\游戏工程' -- --selftest

# 基线性能（本文件 §10 口径）
& 'D:\休闲小岛幻境\开发产物\p8\run_baseline_perf.ps1'

# P8 探针（阶段 3+）
& '...win64_console.exe' --headless --path 'D:\休闲小岛幻境\游戏工程' --script res://tools/probe_p8_calendar.gd
& '...win64_console.exe' --headless --path 'D:\休闲小岛幻境\游戏工程' --script res://tools/probe_p8_weather.gd
& '...win64_console.exe' --headless --path 'D:\休闲小岛幻境\游戏工程' --script res://tools/probe_p8_moon.gd

# P8 截图（阶段 3+）
& '...win64_console.exe' --path 'D:\休闲小岛幻境\游戏工程' --resolution 1600x900 -- --p8shots
```

---

## 12. 未定决策与风险

| # | 决策/风险 | 当前倾向 | 触发条件 |
|---|---|---|---|
| 1 | 雨用 GPUParticles3D 还是 shader 驱动的 MultiMesh 实例 | GPUParticles3D（官方主路径，draw call 恒定） | 阶段 6 实测 if 48k 档超预算 → 降档/改 shader 雨幕 |
| 2 | 室内遮挡用 uniform 淡出还是深度遮罩 | 先 uniform 淡出；若截图仍见室内雨再上深度遮罩 | 阶段 6.2 截图评审 |
| 3 | 冬天自动雪概率 | 极低（0.02 级），但手动可选 | 阶段 5 验收 |
| 4 | 红梅实现 | 复用现有花头几何 + 红色顶点色，新增一个冬季物种 | 阶段 4 截图 |
| 5 | 季节调色是否影响全局调色板 | 不改 `IslePalette` 帧表，只在 sample 结果上叠加 | 阶段 4 视觉回归 |
| 6 | 台风是否改海面波高 | **不改**（`isle_waves.gd` 契约，船体浮力依赖）；只改泡沫/风/云/雨 | 阶段 6.4 |
| 7 | 全局 uniform 类型变更 | `g_weather` 固定 vec4、`g_wind` 固定 vec4，不再改类型 | 全程 |
| 8 | 性能风险：新 shader 首次编译 PSO 卡顿 | 载入期预热 + 阶段 6 实测 | 阶段 6 |
| 9 | 暂停语义与现实时间模式冲突 | 现实模式禁止暂停（现状），日历只读 | 阶段 3 |
| 10 | USNO 不可达 | 用 NASA GSFC 表 + P6 astronomy-engine 基准，文档如实记录 | 阶段 3.2 |

---

## 13. 交付物清单

1. 代码：`scripts/isle_calendar.gd`、`scripts/isle_season.gd`、`scripts/isle_weather.gd`、`scripts/isle_weather_fx.gd`（或等价拆分），以及 main.gd/hud.gd/menu.gd/isle_settings.gd/world.gd/isle_math.gd 的最小侵入修改；新增 `shaders/rain.gdshader`、`shaders/snow.gdshader`（或统一 `precip.gdshader`）、`shaders/leaf.gdshader` 等。
2. 探针：`tools/probe_p8_calendar.gd`、`probe_p8_moon.gd`、`probe_p8_weather.gd`、`probe_p8_seasons.gd`、`probe_p8_integration.gd`。
3. 文档：本文 + `docs/P8_REPORT.md` + `docs/P8_TEST_RESULTS.md` + 截图清单（`开发产物/p8/shots/MANIFEST_p8.md`）。
4. 冻结 tag：`p8-weather-seasons-freeze-YYYYMMDD`（阶段 8 打）。
