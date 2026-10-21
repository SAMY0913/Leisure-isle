# P8 阶段 7 · 生态联动测试报告（Weather / Seasons → Island Life）

- 日期：2026-10-22
- 分支：`p8-weather-seasons`（基于 p7-v4-islander @ ae9d104）
- 范围：岛民日程、海鸥、帆船、炊烟、萤火与统一天气快照的联动；不包含新天气类型/新 UI。
- 结论：**通过**。headless selftest 71/71、weather probe 3135/3135、ecology probe 41/41；三张固定日期截图人工复核合格。

## 1. 目标与设计约束

P8 要求天气/季节与岛上生物、交通、生活细节自然联动，且：

- 只有一个权威模拟时钟（main 的 `_sim_seconds`）；生态模块只读 main 注入的天气快照，不读取系统时间、不新建时钟。
- 可选、不打扰、不会失败：天气只影响观感与行为偏好，不产生任务/惩罚/进度；生态行为最坏退化为室内停留，不会卡死。
- 暂停时天气调度与过渡冻结（阶段 5 已实现），生态侧沿用 main 的 `_paused`/`frozen` 语义。
- 不新增节点/材质/贴图；全部复用现有状态机、粒子系统与材质。

## 2. 联动清单与参数

天气快照由 main 的 `_weather_eco()` 生成，同时注入 `_eco_ctx()`（海鸥）与 `_villager_ctx()`（岛民），字段：
`{type, precip_type, precip_intensity, wind_strength, wind_x, wind_z, storm, cloud}`；风向取平滑后的 `_weather_wind_dir_smooth`（过场不再瞬跳）。

| 对象 | 触发条件 | 行为 | 实现位置 |
| --- | --- | --- | --- |
| 岛民（日程层） | `storm > 0.60` 或 type ∈ {thunder, typhoon} | 户外/门廊活动改为室内 idle；**已在 floor1/attic 的日程保留原区域**（午餐/睡眠不被破坏） | `scripts/isle_villager_schedule.gd` `choose()` 天气过滤块 |
| 岛民（日程层） | 降水且 `precip_intensity > 0.25`，或 `wind > 0.72` | outdoor → porch，stroll → sit | 同上 |
| 岛民（例外） | 雪且 `precip_intensity < 0.40` 且 `storm <= 0.60` | 保留户外，可安静赏雪（艺术化取舍） | 同上 `wx_snow_calm` |
| 岛民（透传） | — | `_choose_activity()` 把 `weather` 放进 schedule ctx；`debug_state()` 增加 `region` 便于取证 | `scripts/isle_villager.gd` |
| 海鸥 | `storm > 0.60`，或降水且强度 `> 0.62` | 不再起飞/盘旋：停栖分支直接 return，飞行个体被改为短计时并尽快落下 | `scripts/fx.gd` BirdFlock `_update_weather_eco()` |
| 海鸥（风） | `wind_strength > 0.05` | 飞行位置叠加风向漂移（每帧 `wind * 1.6 * delta`），强风时明显偏移 | 同上 `_update_flying()` |
| 帆船 | `storm > 0.55`，或 type ∈ {heavy_rain, thunder, typhoon, heavy_snow}，或 `snow >= 0.55` | DOCKED 时拒绝出港，`_sail_dwell = 30s` 后重试；天气转好自动恢复 | `scripts/main.gd` `_boat_weather_hold()` |
| 炊烟 | 风/雨/雪/风暴 | 风向拉斜、速度加快、雨雪天变淡（alpha 0.72→0.30） | `scripts/fx.gd` ChimneySmoke `set_weather()`，main 每 tick 喂参数 |
| 萤火 | 雨/雪 `1.8×`、风 `>0.55`、风暴 `>0.35` 各自线性衰减相乘 | 发光比例 `ffi` 被缩放；雨夜/雪夜/台风夜数量趋近 0，晴夜恢复 | `scripts/main.gd` `_update_lighting()` 萤火块 `wx_fire` |

### 顺带修复（P8 阶段 7 发现）

- 萤火发射器旧坐标 `Vector3(-3.0, 2.0, 3.5)` 固定在岛面以下（小屋/草地一带地面约 y≈8.4），P7 以来实际夜间不可见。现改为 `IsleMath.terrain_height(-3.0, 3.5) + 1.5`，并把 0.42 m 面片收敛到 0.16 m（否则近景像漂浮灯笼）。仍由同一发射器、同一昼夜/天气逻辑驱动，不新增节点。
- selftest 旧断言「帆船出港航行」会被夜间休息窗口或自动天气停航干扰，测试内固定为 12:20 晴天 + DOCKED + 清 rest，测完恢复自动天气。这是测试稳定性修复，不是放宽产品逻辑。

## 3. 验证方式

### 3.1 headless 集成断言（`--selftest`）

```
[TEST] PASS  P8 生态天气上下文与雨天船只停航
[TEST] RESULT 71/71 passed
```

断言内容：

1. `_eco_ctx()["weather"]` 含 type / precip_type / wind_strength / storm，且岛民 ctx 里的 type 与生态 ctx 一致（同一份快照，不是两套天气）。
2. 晴朗夜晚萤火 `emitting == true` 且 `amount_ratio > 0.1`；大雨后 `emitting == false` 且 `amount_ratio <= 0.02`。
3. 大雨时 `_boat_weather_hold() == true`，晴天为 false。

日志：`开发产物/p8/logs/selftest_stage7d.log`。

### 3.2 纯函数探针 `tools/probe_p8_ecology.gd`

```
[SUMMARY] checks=41 fail=0
PROBE_P8_ECOLOGY RESULT: PASS
```

覆盖：

- 夏日 10:00（morning_out）clear → outdoor / stroll；
- heavy_rain → porch / sit；mid_rain → porch；thunder / typhoon → indoor / idle；strong_wind → porch / sit；
- 冬季小雪（calm）→ 仍 outdoor / stroll；heavy_snow → porch；
- lunch（12:00）雷暴 → 仍 floor1 / eat；night（23:00）台风 → sleep / attic；
- 不传 `weather` 键时行为与 P7 一致（outdoor / stroll）；
- 源码契约：main 确实生成并分发同一份天气快照、调用 `_boat_weather_hold()`、有 `wx_fire`、炊烟 `ctl.set_weather`；fx 有 `set_weather` / `_update_weather_eco`；villager 透传 `weather`；schedule 含 `wx_severe` / `wx_snow_calm`；两个生态文件不出现 `Time.get_unix_time_from_system`（无第二时钟）。

### 3.3 固定日期截图 `--p8eco`（1600×900，可复跑）

```
'D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe' --path 'D:/休闲小岛幻境/游戏工程' --resolution 1600x900 -- --p8eco
```

输出（`开发产物/p8/logs/p8eco_stdout.log`，exit 0，无 SCRIPT ERROR）：

```
[P8ECO] rain state=WALK kind=sit region=porch window=morning_out pos=(3.5066, 8.365581, 2.588162)
[P8ECO] clear firefly amount_ratio=0.970
[P8ECO] rain firefly amount_ratio=0.000
[P8ECO] rain boat_hold=true type=heavy_rain storm=0.30
[P8ECO] clear boat_hold=false type=clear
```

截图（目录 `开发产物/p8/ecology/`）：

| 文件 | 场景 | 观察 |
| --- | --- | --- |
| `p8_eco_00_rain_villager_porch.png` | 2026-07-15 10:00 手动大雨 | 岛民在门廊（kind=sit / region=porch），雨丝、屋檐滴水、地面积水环、海鸥停栖在檐口，而不是在岛中央散步 |
| `p8_eco_01_clear_night_fireflies.png` | 同日 22:00 晴 | 草地上空可见大量小型暖黄萤火，尺度自然（0.16 m 面片） |
| `p8_eco_02_rain_night_fireflies.png` | 同日 22:00 大雨 | 同一机位萤火完全消失（amount_ratio=0.000），雨丝与湿地可见；等待 9.6 s 让旧粒子自然消亡，未用 restart() 造假 |

## 4. 暂停与时钟

- 天气状态机在暂停时冻结过渡与调度（阶段 5 已有断言）；生态只读取 `_weather_state`，不自行推进。
- 岛民在 `frozen` 时动画与逻辑冻结（P7 语义）；海鸥 `_eco_paused` 时天气行为关闭；船只由 main 的 pause 分支冻结；萤火是纯视觉，随天气/昼夜参数变化，不持有时间状态。
- 没有新增任何时钟读取；probe 对此做了源码契约断言。

## 5. 已知限制

1. 海鸥行为只通过源码契约与日志验证，未做逐鸟位置的像素级断言；截图只能证明雨日停栖状态（檐口/灯柱上的鸟可见）。
2. 岛民一次只有一个（P7 设定）；天气对多人岛民的影响未覆盖。
3. 手动台风在岛上仍会保留室内日程，但台风期间船只停航只按天气类型/风暴判定，不模拟浪高对码头的影响。
4. 小雪赏雪是艺术化例外：广州冬季自动降雪概率很低（阶段 5 权重），手动可选；并非真实气候模型。
5. 萤火修复改变了 P7 以来的可见性（从不可见变为可见），属于修正而非新功能；如果后续想恢复更低亮度，可调 `fx.gd` 的 additive 颜色或数量。

## 6. 变更文件

- `scripts/main.gd`：`_weather_eco()`、ctx 注入、萤火天气因子与地形抬升、船只停航、炊烟喂参、`--p8eco` 截图模式、selftest 断言。
- `scripts/fx.gd`：ChimneySmoke `set_weather()`、BirdFlock `_update_weather_eco()` 与风漂移、萤火面片尺寸。
- `scripts/isle_villager.gd`：天气透传、`debug_state().region`。
- `scripts/isle_villager_schedule.gd`：`wx_severe` / `wx_wet` / `wx_gusty` / `wx_snow_calm` 过滤；severe 时保留 floor1/attic。
- `tools/probe_p8_ecology.gd`：新增探针。
- `docs/P8_ECOLOGY_TEST_REPORT.md`：本报告。
