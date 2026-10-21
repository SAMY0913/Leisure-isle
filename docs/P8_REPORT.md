# P8 — Weather & Seasons：完成报告

> 版本：v1.0（2026-10-22，Asia/Shanghai）
> 分支：`p8-weather-seasons`（从 `p7-v4-islander` / `ae9d104` 拉出）
> 冻结 tag：`p8-weather-seasons-freeze-20261022`
> 关联文档：`docs/P8_WEATHER_SEASONS_PLAN.md`（调研与计划）、`docs/P8_TEST_RESULTS.md`（测试结果）、阶段报告 `P8_MOON_TEST_REPORT.md` / `P8_SEASONS_TEST_REPORT.md` / `P8_WEATHER_SYSTEM_TEST_REPORT.md` / `P8_WEATHER_VISUAL_TEST_REPORT.md` / `P8_ECOLOGY_TEST_REPORT.md`

---

## 1. 概要

P8 为《休闲小岛幻境》补上了“日历 / 月球 / 四季 / 天气 / 生态联动”这一整层**可选、不打扰、不会失败**的环境表达：

- **统一日历与时间编辑**：完整可编辑公历（年月日时分秒、大小月/闰年/跨年），模拟可暂停、可跳转，现实时间模式只读；仍然只有 `main.gd._sim_seconds` 一个权威时间源。
- **月球修正**：相位命名、明暗轴、可见性、跳日期更新全部按真实天文状态工作，并用 HKO / MET Norway 公开数据做了可复跑回归。
- **四季**：北半球公历季 + 边界 ±10 天连续混合；草色、树冠、花量、落叶、冬季裸枝与红梅联动，全部走实例化/材质参数，不重建几何。
- **天气**：13 种天气、分季权重、确定性调度、20 分钟过渡、湿润与积雪累积/消融、自动/手动双模式、可固定 seed；HUD 天气面板可折叠，仅影响观感，不改变任何进度。
- **天气视觉**：一份共享天气参数驱动天空/云/草/海/材质；雨雪各一个 GPU 粒子系统 + 逐粒子室内剔除、屋檐滴水、水花、积雪、湿地面、台风、闪电，5 档画质均有降级路径。
- **生态联动**：岛民雨天改去门廊、强天气回室内，海鸥避风避雨，帆船恶劣天气停航，炊烟受风/雨影响，萤火在雨雪/大风/雷暴中消失；同时修复了 P7 遗留的“萤火发射器埋在地下”问题。

**规模**：29 个文件变更，+6131 / −85 行；新增 4 个脚本（`isle_calendar` / `isle_season` / `isle_weather` / `isle_weather_fx`，共 1043 行）、2 个 shader、5 个 P8 探针、6 份阶段文档。  
**验证**：headless `--selftest` **71/71**（其中 P8 新增 18 条断言）；5 个 P8 探针共 **6195 项检查 0 失败**（calendar 2672 + moon 233 + season 114 + weather 3135 + ecology 41）；旧探针抽查全部通过；5 组共 **46 张**固定日期截图。

---

## 2. 需求—完成度核对

| 要求 | 实现 | 状态 |
|---|---|---|
| 可选、不打扰、不会失败 | 天气只影响观感与生态表现；无签到/任务/进度条/失败结算；关闭或任意失败路径均回落默认值 | ✅ |
| 一个权威模拟日期时间源 | 仍只有 `main._sim_seconds`；日历/季节/天气都是只读派生（`IsleWeather` 不持有独立时钟） | ✅ |
| 完整公历可编辑 | `IsleCalendar.parts / to_local_seconds / clamp_parts / season_at`；年月日时分可编辑，大小月/闰年/跨年；范围 1–9999 年 | ✅ |
| 模拟暂停与时间控制同状态 | 空格键与 HUD 可见暂停按钮共用 `_paused`；暂停冻结权威时钟及天气调度/岛民日程/船只/动物/动画 | ✅ |
| 保留现实时间语义 | `time_source="real"` 时只读系统时钟；不修改系统时间；现实模式禁用暂停/编辑 | ✅ |
| 月球真实相位/位置/可见性 | Meeus 既有算法 + 渲染端三处修复；相位按真实日月视黄经距角八扇区；可见性由真实高度决定 | ✅ |
| 四季连续过渡 | 边界 ±10 天 smoothstep；权重和恒为 1；不瞬间切换；不替代日月算法 | ✅ |
| 天气状态机与季节分离 | `IsleWeather` 独立于季节；季节只提供类型权重和合法性；跨季跳转立即合法化 | ✅ |
| 天气面板 | 独立可折叠面板，风格与时间面板一致；自动/手动、当前类型/强度/持续、季节合法选项 | ✅ |
| 天气视觉逐轮优化 | 雨/雪/台风/雷暴/低画质/室内/近景/远景均实拍验收；共享参数而非复制天空海洋系统 | ✅ |
| 生态联动 | 岛民/海鸥/帆船/炊烟/萤火全部接入 `weather` 上下文 | ✅ |
| 不加未批准依赖/资产 | 无新插件；雨丝/雪花/水花贴图均为运行时程序生成；仅新增 GDScript 与 shader | ✅ |
| 不覆盖发布包 | `发布/`、`构建输出/` 的 P7-V3.1 exe 未触碰；P8 不产出新发布包 | ✅ |

---

## 3. 架构与依赖图

```text
main.gd::_sim_seconds（唯一权威模拟时钟，秒；现实模式 = unix + 时区偏移）
  │
  ├─ IsleAstro.compute()/day_events()      → 太阳/月亮高度方位、月相、升落时刻
  │      └─ IslePalette.sample(theme_t)    → 昼夜调色板（25 关键帧）
  │
  ├─ IsleCalendar.parts()/season_at()      → 年/月/日/时/分/秒/星期/季节权重
  │      └─ IsleSeason.visuals()           → 草色、树冠保留与色相、花量、落叶率、红梅
  │
  ├─ IsleWeather(seed).tick(t, dt, advancing)（只读 t，不持有时钟）
  │      ├─ schedule_at(t, seed)           → 当前/下一轮天气、强度、过渡、湿润、积雪
  │      ├─ main._update_weather()         → _weather_state → _apply_weather_view()
  │      ├─ main._update_weather_fx()      → IsleWeatherFx（雨/雪/滴水/水花）
  │      │      └─ 共享 uniform：g_weather / g_weather2 / g_wind_dir / g_lightning
  │      └─ main._weather_eco()            → 岛民日程、海鸥、帆船、炊烟、萤火
  │
  └─ HUD / 菜单（显示、编辑、跳转的入口；不直接改时间，回调 main 执行）
```

**关键约束**：天气/季节/日历模块都不写 `_sim_seconds`。时间跳转、暂停、现实/模拟切换只由 `main.gd` 执行，然后统一触发 `_update_lighting()` 与 `_update_weather(..., force)`，避免出现第二套时钟或补演。

---

## 4. 分阶段实现

### 4.1 日历、暂停与跳转（阶段 3，commit `da11377`）

- 新增 `scripts/isle_calendar.gd`（183 行，`class_name IsleCalendar`，全 static）：
  - `is_leap / days_in_month / days_in_year / day_of_year`；公历 `MONTH_DAYS`；范围 `MIN_YEAR=1..MAX_YEAR=9999`。
  - `parts(local_seconds)` → `{year,month,day,hour,minute,second,weekday,sod,day_index,season,season_t,season_weights,…}`。
  - `to_local_seconds(...)` / `clamp_parts(...)`：越界日期 clamp 到合法值，跳转后直接进入合法状态。
  - `season_at / season_phase / season_label / season_name / full_label`。
  - 时区固定 `TZ_SECONDS=28800`（Asia/Shanghai）；不读系统时区，避免 Godot 无 IANA 规则的问题。
- `main.gd`：新增 `_jump_datetime(year,month,day,hour,minute,second)`（现实模式拒绝；clamp → 写 `_sim_seconds` → 重算 `_events` → `_sync_boat_clock` → `_update_lighting`）；所有跳转统一走它。
- `hud.gd`（+539 行）：时间面板加入日期行、可见暂停按钮、可折叠“编辑日期与时间”区（年/月/日/时/分五步进器 + 预览 + 跳转/回到当前）。展开时高度 `TIME_PANEL_TOP` → `TIME_PANEL_TOP_CAL`，收起恢复；与 H 隐藏、空闲自动收折一致。
- 暂停语义：空格与 HUD 按钮共用 `_paused`；暂停时 `_advance_sim` 不推进，`IsleWeather.tick(advancing=false)` 冻结调度/过渡/湿润/积雪，岛民 `frozen`、船/鸟/模拟动画全部停；菜单、时间控件、HUD 仍可操作。
- 验证：selftest 新增 6 条断言（闰日/跨年、按钮与空格同状态、暂停冻结时钟、编辑后跳转即时生效、跨年合法状态、面板收折高度）。

### 4.2 月球（阶段 3.2）

- 保留既有 Meeus 47 章月亮算法（`isle_astro.gd`），在其上修正渲染端三处真实 bug：
  1. **明暗轴**：旧实现用固定世界基 `cross(UP, moon_dir)` 计算月面明暗分界，月亮高悬时亮面方向错误。改为把 `sun_dir` 投影到月盘切平面得到 `a`、`b=cross(md,a)`，用真实日月距角 `cosα=2k−1` 判定明暗（`shaders/sky.gdshader` 月盘段）。
  2. **可见性**：旧实现只看调色板时刻的 `moonAlpha/moonDiskI`，导致“只按时刻判显示”、白天月盘几乎不可见。改为 `main.gd` 用真实 `moon_alt` 做 `smoothstep(-0.02,0.06,sin(alt))`，并叠加“白天保留 45%–100%”的可见度，再与调色板取 max。
  3. **相位命名**：旧实现按照亮比例阈值，k≈0.5 的上/下弦会被误标为盈凸/亏凸。改为按真实日月视黄经距角 Δλ 每 45° 八扇区命名（`isle_astro.gd` 新增 `moon_phase_deg`，main 生成“新月/娥眉月/上弦月/盈凸月/满月/亏凸月/下弦月/残月”）。
- 跳日期、现实/模拟切换统一经 `_update_lighting`，月相/位置立即一致。
- 回归：`tools/probe_p8_moon.gd` 233 项（A 相位时刻对 HKO XML；B 月出/月落/中天/方位对 MET Norway；C 完整朔望月连续性；D 渲染端月盘朝向；E 可见性契约），0 失败；10 张固定日期截图；详见 `docs/P8_MOON_TEST_REPORT.md`。

### 4.3 四季（阶段 4，commit `fcc3fda`）

- 新增 `scripts/isle_season.gd`（133 行）：`SEASON_TABLE` 定义四季视觉参数，`visuals(weights)` 按权重连续混合。北半球公历季：春 3–5、夏 6–8、秋 9–11、冬 12–2；季节边界前后各 10 天用 smoothstep 连续过渡，四权重和恒为 1。
- 关键表现（实测表）：
  - 草色乘色：春 `(1.04,1.07,0.98)`、夏 `(0.94,1.05,0.82)`、秋 `(1.22,0.99,0.55)`、冬 `(0.92,0.87,0.72)`。
  - 树冠保留比例：春 0.96、夏 1.00、秋 0.94、冬 0.10；冬季叶卡 0（无悬空菱形叶卡）。
  - 秋叶 `foliage_tint=(1.48,0.86,0.34)`；落叶仅秋季开启（`IsleFx.leaves()`，GPUParticles3D 64 片）。
  - 花量保留：春 1/1/1/.92、夏 .62/1/.86/1、秋 .05/.28/.06/.48、冬 0（按 Tulip/Daisy/Bluebell/Poppy 四种）；冬季红梅用树梢 30 实例 MultiMesh（单 draw call）实现。
- 实现方式：草只改 `grass.gdshader` 的 `tint`；树冠/红梅改 MultiMesh 实例色与 `visible_instance_count`（或节点可见性）；花按节点名显隐；地形/材质用季节乘色。**不重建树/花/地形，不逐帧改 2 万+草实例**。
- 跨季跳转：只更新参数，无粒子/节点累积；selftest 断言冬季树冠实例收起、红梅只在冬季。
- 验收：13 张截图（4 季 × wide/tree/garden + 冬季红梅）；`probe_p8_season.gd` 114 项 0 失败；详见 `docs/P8_SEASONS_TEST_REPORT.md`。

### 4.4 天气状态机与面板（阶段 5，commit `60085d9`）

- 新增 `scripts/isle_weather.gd`（500 行，`class_name IsleWeather extends RefCounted`，依赖全部 preload，兼容 `--script` 模式）：
  - **13 类型**：`clear / partly / overcast / windy / strong_wind / light_rain / mid_rain / heavy_rain / light_snow / mid_snow / heavy_snow / thunder / typhoon`。
  - **确定性调度**：30 模拟分钟一个槽（`BLOCK_SECONDS=1800`）；5 游戏小时一个“超级块”，内部按 seed 确定性切分为长度和恒为 10 的若干轮（1–4 轮/超级块），每轮 1–5 游戏小时；`_rand01` 用 xorshift32（seed/index/salt），完全可复现；默认 seed `20261022`。
  - **分季权重**（13 维，和不必为 100，按相对权重抽取）：
    ```
    spring [26,18,16,12, 5, 8,5,2, 0, 0, 0, 3, 0]
    summer [18,16, 8, 7, 6, 8,7,4, 0, 0, 0, 9, 3]
    autumn [22,18,13,11, 6, 8,6,2, 0, 0, 0, 4, 3]
    winter [18,19,17, 8, 6, 7,4,2, 1.2,0.6,0.2,0.5,0]
    ```
    即：雪只在冬季合法（冬季雪权重合计约 2%，自动“广州极少下雪”，但手动可选小雪/中雪/大雪）；台风主要在夏秋；雷暴按季节权重。艺术化气候权重，不是真实气候统计。
  - **过渡**：一轮结束前 1200 模拟秒按 smoothstep 混合到下一轮；风向按最短弧插值。
  - **合法化**：跨季跳转/切季时，当前与下一轮类型立即经 `type_legal/_legal_fallback` 修正（雪→雨、台风→雷暴或强风）；手动类型跨季也自动回退到本季合法类型。
  - **湿润/积雪**：`wetness` 约 420 s 增 / 5400 s 干；`snow_depth` 约 9000 s 积 / 14000 s 融（模拟秒），状态输出 `snow_trend`（−1/0/+1）。
  - **状态契约**（`state()` 至少 21 键）：`mode/auto/manual_type/available_types/type/label/intensity/transition/cloud/wind_strength/wind_dir/storm/precip_type/precip_intensity/wetness/snow_depth/snow_trend/season/season_label/season_t/hold_left/hold_total/run_start/run_end/seed`。
  - **暂停/跳日期**：`tick(..., advancing=false)` 完全冻结；跳日期用 `schedule_at` 直接求当前轮，不补演历史。
- `hud.gd` 新增天气面板：左下“☁ 天气 …”胶囊 + 可收折面板（宽 356，位于时间面板右侧，`WEATHER_PANEL_TOP=-338`），内容为当前类型/强度、自动/手动、持续与趋势、本季合法类型网格；W 键开关；14 秒空闲自动收折；H 隐藏界面时同步收起。
- `isle_settings.gd` / `menu.gd`：新增 `weather_seed / weather_auto / weather_type` 三项持久化与回写。
- 验收：selftest 新增 4 条（状态契约与季节合法、暂停冻结、手动跨季回退、面板与 H 同步）；`probe_p8_weather.gd` 3135 项 0 失败；5 张面板截图；详见 `docs/P8_WEATHER_SYSTEM_TEST_REPORT.md`。

### 4.5 天气视觉（阶段 6，commit `d1403b8`）

- **共享参数**（只在启动注册，每帧 set，不重编译）：
  - `g_weather = (rain, snow, wetness, snow_cover)`
  - `g_weather2 = (cloud, storm, wind, indoor)`
  - `g_wind_dir = (wind_x, wind_strength, wind_z, 0)`
  - `g_lightning`（瞬时亮度）
- **系统改动**：
  - `toon.gdshader`：湿润压暗 + sheen、朝上表面按 `snow_cover` + 世界坐标噪声 + 低海拔淡出混雪色、云影压直射、风偏。
  - `grass.gdshader`：季节 `tint`、风力缩放/方向偏置、积雪后草叶逐步淡出。
  - `sky.gdshader`：云量/云色/星/月盘由天气参数调制；雷暴闪电统一由 `g_lightning` 驱动。
  - `sea.gdshader`：雨纹/泡沫/反射/风暴增强——**不改 7 组波系数**（与 `isle_waves.gd` 逐系数一致，船体浮力依赖）。
- **降水**：雨、雪各 1 个 `GPUParticles3D`（世界空间、盒形发射、跟随相机 xz、固定 AABB 防裁剪），`precip.gdshader` 按小屋 4 个遮挡盒**逐粒子剔除**——相机在室内看不到穿顶雨雪，但从窗户仍能看到屋外在下雨/下雪。另有屋檐滴水线、220 个 MultiMesh 水花、落叶粒子。
- **天气渲染基调**：`_grade_palette_for_weather()` 对昼夜调色板做冷灰/压暗/去饱和，再由现有天空/海面/材质管线消费（不靠黑罩、不复制天空海洋系统）；台风复用 sky/sea/grass/toon 全链路放大云量、风力、浪花、雨斜与植被摆动。
- **画质**：粒子数量随 `particle_density` 与 drawn amount 缩放；低画质仍保留可见雨雪；雨/雪/溅落/滴水各 1 draw call 量级。
- 验收：15 张截图（晴/阴/日雨/夜雨/台风/日雪/树雪/夜雪/室内/地面/屋檐/水花/低画质/闪电/落叶）；selftest 新增 2 条（降水系统与室内剔除数据、低画质保留降水且积雪累积）；详见 `docs/P8_WEATHER_VISUAL_TEST_REPORT.md`。

### 4.6 生态联动（阶段 7，commit `6c43493`）

- `main.gd::_weather_eco()` 输出 `{type, precip_type, precip_intensity, wind_strength, wind_x, wind_z, storm, cloud}`；`_eco_ctx()` 与 `_villager_ctx()` 都带 `weather` 键。
- **岛民**（`isle_villager_schedule.gd::choose`，在既有日程之后并联过滤，不改 11 状态机）：
  - 强天气（storm>0.60 或 thunder/typhoon）：户外/门廊改为室内，但保留 floor1（吃饭）与 attic（睡觉）。
  - 湿/大风（precip!="none" 且强度>0.25，或 wind>0.72）：户外改门廊；小雪且 calm 时保留户外赏雪。
- **海鸥**（`fx.gd::BirdFlock`）：storm>0.60 或降水强度>0.62 时停栖避雨，飞行个体受风偏移并缩短计时。
- **帆船**：`_boat_weather_hold()` 在 storm>0.55 或 heavy_rain/thunder/typhoon/heavy_snow 或 snow≥0.55 时停航（保留 DOCKED，不删船）。
- **炊烟**：`fx.gd::ChimneySmoke.set_weather()` 随风向/风力偏斜、受雨雪压暗。
- **萤火**：按雨/雪、风、storm 三项衰减，恶劣天气 `emitting=false`、`amount_ratio→0`。
- 同时修复 P7 遗留 bug：萤火发射器 y=2.0 在岛面以下（该处地面约 8.4 m），改为 `terrain_height(-3,3.5)+1.5`，并把萤火 quad 从 0.42 收到 0.16（近景自然）。
- 验收：3 张生态截图；selftest 新增 1 条（生态上下文/雨天停航）；`probe_p8_ecology.gd` 41 项 0 失败；详见 `docs/P8_ECOLOGY_TEST_REPORT.md`。

---

## 5. 关键规则速查

| 项目 | 规则 |
|---|---|
| 时区 | 固定 Asia/Shanghai（+08:00）；不读系统时区，不随系统 DST 变化 |
| 公历 | 预计格里高利历；闰年规则；1–9999 年；跳转越界 clamp |
| 季节 | 北半球公历季；边界 3-01/6-01/9-01/12-01 前后 ±10 天 smoothstep 混合；权重和=1 |
| 天气槽 | 30 模拟分钟；每轮 1–5 游戏小时；过渡 20 模拟分钟；seed 默认 20261022 |
| 自动权重 | 雪仅冬（冬约 2% 自动概率，手动可选）；台风夏秋；雷暴夏秋权重高 |
| 手动模式 | 只列本季合法类型；跨季自动回退；切回自动后按季节权重重新抽取 |
| 暂停 | 暂停冻结权威时钟、天气调度/过渡、湿润/积雪、岛民日程、船、鸟、模拟动画；HUD/菜单仍可操作 |
| 现实模式 | 只读系统时钟；不可暂停/编辑；天气随现实时间继续 |
| 生态阈值 | 岛民 severe: storm>0.60 或 thunder/typhoon；wet: precip≠none & 强度>0.25；gusty: wind>0.72；雪 calm: snow & 强度<0.40 & storm≤0.60 |
| 海鸥 | bad: storm>0.60 或降水强度>0.62 |
| 帆船 | hold: storm>0.55 或 heavy_rain/thunder/typhoon/heavy_snow 或 snow≥0.55 |

---

## 6. 与权威时间 / 暂停 / 现实模式的关系

| 场景 | 权威时钟 | 天气调度 | 岛民/船/鸟 | 视觉动画 |
|---|---|---|---|---|
| 模拟 · 运行 | `_sim_seconds` 按 `86400/day_length` 推进 | 推进 | 推进 | 推进 |
| 模拟 · 暂停 | 冻结 | 冻结 | 冻结 | 冻结模拟动画（烟/萤火等表现仍由渲染帧驱动） |
| 现实模式 | `unix+28800`，不可暂停 | 随现实时间推进 | 推进 | 推进 |
| 跳日期/时间 | 直接赋值，不补演 | `schedule_at` 立即求当前轮 | 下一帧重规划 | `_update_lighting` + 天气 view 立即刷新 |

所有天气视觉参数都是 `_weather_*` 的**只读投影**；没有第二套 RNG 时钟或独立“weather year/day”。

---

## 7. 性能实测

条件：1600×900、RTX 2060、quality 2、VSync off、默认全岛机位、`--p8perf`（固定日期 2026-07-15 12:20 起）；日志 `开发产物/p8/logs/p8perf_final.log`。数值为退出前统计均值；`cpu_ms` 来自 `Performance.TIME_PROCESS`，存在采样噪声，**以 frame_ms/FPS 为准**。

| 场景 | FPS | frame_ms | objects | draw calls | VRAM(MB) |
|---|---|---|---|---|---|
| clear | 180.0 | 5.56 | 1928 | 1838 | 272.5 |
| overcast | 176.9 | 5.65 | 1928 | 1838 | 272.5 |
| heavy_rain | 169.2 | 5.91 | 1943 | 1853 | 272.6 |
| thunder | 176.7 | 5.66 | 1932 | 1842 | 272.6 |
| heavy_snow | 176.6 | 5.66 | 1929 | 1839 | 272.6 |
| typhoon | 174.5 | 5.73 | 1931 | 1841 | 272.6 |
| heavy_rain q0 | 177.0 | 5.65 | 1930 | 1840 | 168.9 |
| heavy_rain q4 | 106.6 | 9.38 | 1931 | 1841 | 625.9 |

预算核对（计划 §9.1）：
- frame_ms 增量：大雨 +0.35 ms、雷暴 +0.10 ms、大雪 +0.10 ms、台风 +0.17 ms，均 **≤ +2.0 ms** ✅。
- 新增 draw call：+15（1838→1853，大雨态），**超过计划的 ≤ +8**，已记录为已知偏差；对 frame_ms 影响仍在预算内。主要是雨/雪/滴水/水花/落叶/红梅等少量独立绘制项。
- 常驻节点：+15（1928→1943），**超过计划 ≤ +12**，同属已记录偏差。
- VRAM：+0.1 MB（q2）✅；q4 的 625.9 MB 来自画质档本身（MSAA/scale），与天气无关。

注意：本表与阶段 1 基线（不同机位/时刻/统计方式）不可直接相减；P8 内部对比以上表为准。P95、近景/飞行/室内/低机位性能矩阵未在 p8perf 中覆盖（见 §9）。

---

## 8. 兼容与约束

- 不新增插件/依赖/外部贴图/模型/音频；雨丝/雪花/水花/落叶均为运行时程序化纹理或几何。
- 现有共享 shader 只**增加** global uniform 与消费分支，旧参数/旧行为在晴好天气下保持；global uniform 在启动时一次性注册。
- 世界尺度不变：1 单位=1 米、岛民 1.50 m；`docs/` 中 P7 的尺度规范未改。
- 世界/小屋/岛民/船只的既有生成与状态机未被重写：四季与天气走“材质参数 + 实例色/显隐 + 少量新粒子节点”，main 的改动集中在新增 P8 函数与少量调用点。
- 发布包 `发布/`、`构建输出/` 未覆盖；P8 未生成新 exe。

---

## 9. 已知问题与限制

### 9.1 旧问题（P8 之前已存在，未新增）
1. 退出时 8 条 ObjectDB 泄漏（P7 已知）。
2. 吊灯泛光球过大（P7 已知美术项）。
3. 楼梯底部宽度 warn（P7 已知）。
4. user:// 日志轮转失败、根证书库读取失败、shader cache `f.is_null()` ×5（本机环境/user:// 写入受限，非 P8 引入）。
5. 船航线注释陈旧。
6. 早期 P7 遗留萤火发射器埋地问题——**P8 已修复**（见 4.6）。

### 9.2 P8 新增限制
1. **性能矩阵不完整**：`--p8perf` 只测默认全岛机位 × 天气 × q0/q2/q4；未记录 P95，未覆盖近景/飞行/室内/低机位逐项性能（这些场景有截图验收，但没有 FPS 表）。
2. **draw call / 常驻节点超预算**：+15 / +15，超过计划 §9.1 的 ≤+8 / ≤+12；frame 时间仍在预算内，作为已知偏差记录。
3. **月盘为艺术放大**：`sky.gdshader` 月盘半径 0.013 rad（直径≈1.49°，真实≈0.52°），属既有美术选择，P8 未改尺寸。
4. **积雪覆盖范围**：toon 不透明表面（地面/屋顶/岩石/树冠上侧/树枝上侧/码头面等）生效；玻璃灯罩、halo、草叶按设计淡出而非积雪覆盖，属艺术取舍。
5. **自动气候为艺术权重**：广州冬季自动下雪约 2%，不代表真实气候；手动模式仍可在冬季选雪、夏秋选台风。
6. **室内剔除以小屋为准**：使用小屋 4 个遮挡盒；岛上其他无可进入室内，无影响。
7. **现实模式不可暂停**：沿用既有语义（现实时间应继续走），因此天气与生态在现实模式下也不会因暂停而冻结。
8. **天气只影响观感/生态，不改变任何进度**；这是需求约束，不是缺陷。

---

## 10. 交付物与复跑

### 代码/资源
- 新增：`scripts/isle_calendar.gd`、`scripts/isle_season.gd`、`scripts/isle_weather.gd`、`scripts/isle_weather_fx.gd`、`shaders/precip.gdshader`、`shaders/splash.gdshader`。
- 修改：`scripts/main.gd`、`hud.gd`、`menu.gd`、`isle_settings.gd`、`fx.gd`、`isle_astro.gd`、`isle_villager.gd`、`isle_villager_schedule.gd`；`shaders/toon.gdshader`、`sky.gdshader`、`sea.gdshader`、`grass.gdshader`。
- 探针：`tools/probe_p8_calendar.gd`、`probe_p8_moon.gd`、`probe_p8_season.gd`、`probe_p8_weather.gd`、`probe_p8_ecology.gd`。
- 文档：本文件 + `docs/P8_TEST_RESULTS.md` + 6 份阶段文档 + 截图清单 `开发产物/p8/shots/MANIFEST_p8.md`。

### 复跑
```powershell
$EXE = "D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe"
$P   = "D:/休闲小岛幻境/游戏工程"

# 自测
& $EXE --headless --path $P -- --selftest

# P8 探针
& $EXE --headless --path $P --script res://tools/probe_p8_calendar.gd
& $EXE --headless --path $P --script res://tools/probe_p8_moon.gd
& $EXE --headless --path $P --script res://tools/probe_p8_season.gd
& $EXE --headless --path $P --script res://tools/probe_p8_weather.gd
& $EXE --headless --path $P --script res://tools/probe_p8_ecology.gd

# 截图（窗口，1600×900）
& $EXE --path $P --resolution 1600x900 -- --p8moon
& $EXE --path $P --resolution 1600x900 -- --p8seasons
& $EXE --path $P --resolution 1600x900 -- --p8weather
& $EXE --path $P --resolution 1600x900 -- --p8wfx
& $EXE --path $P --resolution 1600x900 -- --p8eco

# 性能
& $EXE --path $P --resolution 1600x900 -- --p8perf
```

---

## 11. 回滚

P8 全部提交都在分支 `p8-weather-seasons` 上，可按阶段 tag 回退：

| tag | 内容 |
|---|---|
| `p8-3.2-moon-20261022` | 日历/暂停/月球修复 |
| `p8-4-seasons` | 四季视觉联动 |
| `p8-5-weather` | 天气状态机与面板 |
| `p8-6-weather-visual` | 天气视觉 |
| `p8-7-ecology` | 生态联动 |
| `p8-weather-seasons-freeze-20261022` | P8 冻结（本报告 + 测试结果） |

完全回滚：`git checkout p7-v4-islander`（P8 基线）；或 `git checkout <tag>` 取对应阶段。无发布包被覆盖，无需回滚 exe。

---

## 12. 后续建议

1. **重打发布包**：`发布/`、`构建输出/` 仍是 P7-V3.1；P8 功能要进发布包需按既有流程重新构建并验收。
2. **补性能矩阵**：在近景/飞行/室内/低机位补 FPS/P95，并评估把 draw call +15 收敛（例如合批水花/滴水、削减低画质粒子 draw pass）。
3. **真实气候数据（可选）**：若希望“广州冬季不下雪”更贴近现实，可把自动权重改为按月份曲线，但保留手动选项与“艺术化”开关。
4. **更多生态**：可让屋顶积雪随日照/温度趋势局部融化、屋檐冰凌、风与晾晒物等，继续复用现有共享 uniform。
5. **发布前回归**：保留 `--selftest` 71 条与 5 个 P8 探针作为 P9 的回归门槛。
