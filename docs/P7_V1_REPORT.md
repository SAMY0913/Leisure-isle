# P7-V1 实施报告：小岛会生活——生态节奏与跨系统事件联动

> 项目：《休闲小岛幻境》（Leisure Isle of Dusk & Dawn）
> 工程：`D:/休闲小岛幻境/游戏工程`；引擎：`D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe`（Godot v4.7.2.stable.official.ed1daf0bf，Forward Plus）
> 分支：`p7-v1`；基线交接点：`p6-closeout` / `7941816`；基线回滚 tag：`p7-baseline-20261021`
> 日期：2026-10-21

## 结论摘要

- **A 黄昏归栖**：已实现。按太阳高度下降穿越 +4° 启动，每模拟日一次，按"目标空中数"分批降落 0.7–1.5 s 错峰，复用既有海鸥状态机与落点预约；夜间稳定后不重复要求归栖，清晨由既有日间规则恢复；时间跳转不补演、不重放。
- **B 船鸟联动**：已实现。仅 `coastal` 近海航线可用，触发点由真实航线几何计算（近海方位弧段在 out 折线上的前 28% 弧长），每航次最多一次；每次最多 1–2 只合格海鸥，响应 9–15 s 后回到既有飞行状态机。
- **C 昼夜协调**：审计 16 个系统，确认 6 个问题；本轮修复 4 个（C1 萤火完全不发射、C2 跳时夜声单帧 -73 dB 硬切、C3 火焰声硬切、C4 时间回溯后帆船锁死 RESTING）；C5 炊烟收尾、C6 死代码经证据评估后**不改**（理由见 §6）。
- **测试**：新增 `probe_eco7`（123 断言）与 `probe_p7c`（38 断言）全绿；`--selftest` 53/53；18 项 headless 套件回归与基线一致（仅 2 项既有 P6 过期断言失败，非 P7 回归）；窗口 `--p7shots` 产出 14 张专项截图并逐张实检；`--shots` 61 张回归截图、`--perf` 17 条性能记录均成功执行。
- **性能**：同机同引擎同分辨率下，默认画质 9 场景与五档画质全部帧率不低于基线（`frame_ms` 5.47–5.62 对基线 5.47–6.68），VRAM 各档完全一致，未见新增调度带来的帧时间波动。
- **视觉验收**：黄昏归栖开始/中段/夜间稳定/清晨恢复/船过近海/船鸟响应与恢复均有截图与日志双重证据；**声音听感（C2/C3 的"听感"层面）与连续长时间主观观察未完成，如实标注**（见 §10）。

---

## 1. 修改前的实际状态与已存在的相关功能

### 1.1 工作区核实（实施前）

- 实际 HEAD = `7941816`（`p6-closeout` 交接点），工作区**干净**；本轮在此之上建立独立分支 `p7-v1`，未回退、未重置、未清理任何历史归档。
- 存在基线只读 worktree：`D:/休闲小岛幻境/开发产物/p7/baseline_wt`（detached `7941816`，tag `p7-baseline-20261021`），用于前后对照，本轮保留未动。
- 基线采集期间发现 2 个非本任务启动的 Godot GUI 进程（PID 35464/36936）；本轮窗口测试前确认无残留 Godot GUI 进程（仅 godot-ai 桥进程），GPU 独占后才执行截图/性能测试。
- `project.godot`：config_version=5；`[application] config/name="休闲小岛幻境"`、`run/main_scene="res://isle.tscn"`；`config/features=("4.7","Forward Plus")`；视口 1440×900、stretch canvas_items/expand；MSAA 3D=2；输入动作仅 `toggle_auto_orbit`（C 键）等既有配置；autoload 仅 `_mcp_game_helper`（godot-ai 插件）。本任务未改 `project.godot`。

### 1.2 修改前的基线数据

| 项目 | 修改前结果 | 证据 |
|---|---|---|
| `--selftest`（headless） | 53/53 passed（1 SKIP：真实鼠标拖动） | `开发产物/p7/logs/baseline_selftest_headless.log` |
| headless 探针 | 17 项中 15 项全绿；`probe_fx_p4` 64/1、`probe_world_p4` 3 FAIL | `开发产物/p7/logs/baseline_probe_*.log` |
| `--p7shots` 专项截图 | 当时尚不存在（本轮新增入口） | — |
| `--shots` 截图 | exit0、61 张 PNG 1600×900 | `开发产物/p7/logs/baseline_shots.log` |
| `--perf` 性能 | exit0、17 条 `[PERF]` | `开发产物/p7/logs/baseline_perf.log` |
| 基线总览 | 229 行报告 | `开发产物/p7/logs/baseline_summary.md` |

两个既有失败经在 baseline worktree 上复跑同数值确认：`probe_fx_p4` 失败断言为"个体 8–20 s 计时器错峰"（P6 行为已改、断言过期）；`probe_world_p4` 为 `missing perch kind: roof/eave`（P5/P6 已把屋顶栖息点迁到 `cottage.gd`，断言未更新）。二者均非 P7 回归，本轮**未删除/未降低**这些断言。

### 1.3 已存在且可复用的相关功能

- **海鸥**：`scripts/fx.gd` `BirdFlock` 已有完整状态机 `State.FLY/TAKEOFF/LANDING/PERCH`，逐鸟字典状态、起飞/寻找落点/降落接口（`_begin_takeoff`/`_begin_landing`/`_find_free_slot`/`_reserve_slot`）、落点法线与脚部高度/坡度约束、栖息点占用互斥、昼夜滞回（-2°/+2°）与夜间落栖 `_request_night_landings`、黎明错峰起飞。**修改前没有黄昏归栖状态机、没有船鸟联动**（grep + 审计确认），本轮未新建第二套状态机。
- **帆船**：`scripts/main.gd` 已有 8 条航线（4 coastal + 5 far）、生命周期 `DOCKED/COASTAL_CRUISE/RETURNING/OFFSCREEN_WAIT/RESTING`、航次号 `_boat_trip`、夜间休息窗 18:00–08:00、探照灯。**修改前没有"近海航段"几何元数据**，本轮在 `world.gd` 航线生成处补充 `shore_a0/shore_a1` 与弧长换算，未改任何航线坐标/生命周期规则。
- **时间**：`main.gd` `_sim_seconds`/`_time_source`/`_time_jump`/`_tick``_advance_sim` 为唯一权威时间；`_update_lighting` 每帧用 `_sim_seconds` 调 `isle_astro.gd` 得到 `_sun_alt/_rising/_night`；本轮事件全部读这套时间与 `ctx={day,rising,sim_seconds,time_source,paused}`，未建第二时钟、未改天文算法。
- **音频**：`isle_audio.gd` 三层环境循环（Ocean/Wind/Night）+ 鸟鸣 + 火焰声 + 夜间门控，均有既有探针；本轮只修 C2/C3 两处门控收尾，未动总线架构。

---

## 2. 本次发现的问题与证据

审计报告：`游戏工程/docs/P7_BEHAVIOR_TABLE.md`（209 行，16 系统行为对照表 + 阈值时刻锚点 + 跳时重校准矩阵）；证据日志：`开发产物/p7/audit/`（23 个）。

### 2.1 已确认（6 项，均有截图/探针/日志证据）

| # | 问题 | 根因与证据 | 处理 |
|---|---|---|---|
| C1 | 萤火从创建起**永不发射** | `fx.gd` 创建时 `emitting=false` 且全仓无置 true；`main.gd` 试图以 `ff["mat"] as ShaderMaterial` 写入，但 `ff["mat"]` 实际是 `StandardMaterial3D`，cast 恒 null，写 amount_ratio 的分支永不执行。headless 快照：夜间 30 帧后 `emitting=false`、`amount_ratio=1.0` 但不发射 | **已修**（§3 C1） |
| C2 | 时间跳转时夜间环境声**单帧 -73.1 dB 硬切** | 停止分支直接 `stop()`：22:00 跳正午时 env 0.9510/-6.94 dB → playing=false/env=0/-80 dB；自然黎明停点为 env≈0.0154/-42.76 dB | **已修**（§3 C2） |
| C3 | 火焰声在 alt≥2.0 时**一步 -12 dB→静音** | 仅按 sun_alt<2.0 开关，无淡出 | **已修**（§3 C3） |
| C4 | 时间回溯到白天后，帆船**锁在 RESTING 约 20 游戏小时** | `_sync_boat_clock` 消费 `_time_jump` 时未处理 RESTING 早于当前时刻的 `rest_until`；22:00→12:00 后 `rest_until-now=19.99 h`，白天不出海，也丢失船鸟联动机会 | **已修**（§3 C4） |
| C5 | 炊烟 13:00/19:00 窗口结束时 emitting 单帧断发射 | `fx.gd` 窗外 ramp 直接置 0 并关发射；但"已存在烟团是否立即消失"只有 headless 推断，无窗口截图证据 | **不改**（证据不足，且属于禁改的两个炊烟窗口语义；记录为风险） |
| C6 | 死代码 `_boat_depart_hours`（18.6）与休息窗 18:00 矛盾 | 全仓唯一引用且从未被使用，无行为影响 | **不改**（无行为影响、清理无关） |

### 2.2 待验证（7 项，见对照表 3.2）与未发现（5 项，见对照表 3.3）

- 待验证：萤火修复后视觉密度/亮度、夜声硬切听感、炊烟视觉尾巴、船探照灯 alt<0.5 硬门 pop、花瓣全天、灯塔跳时强度跳变、阈值边界肉眼可察性。其中**萤火修复后视觉已由本轮截图补证**（p7_04_night_calm / p7_04b_night_perch_close），其余听感/主观项仍未验证。
- 未发现：流星（项目未实现）；除帆船 RESTING 外的跳时长期错位（光照/天空/调色板/窗灯/灯塔/炊烟/音频/星空/归栖均每帧按权威时间重算）；鸟鸣阈值与归栖阈值冲突；清晨各系统独立节奏是设计而非错误；音频总线架构问题。

### 2.3 与 A/B 直接相关的"功能缺失"确认

- 修改前不存在黄昏归栖：海鸥只有"夜门 -2° 后转降落"与黎明起飞，黄昏没有逐步减飞/分批回栖逻辑 → 本轮新增 `ROOST_*` 状态与调度（仍复用既有逐鸟状态机）。
- 修改前不存在船鸟联动：帆船经过近海没有任何海鸥响应接口，也没有"近海航段"几何 → 本轮新增航段元数据 + `on_boat_shore_pass` 入口。

---

## 3. 实际修改文件、模块职责与关键实现

| 文件 | 改动量 | 职责 |
|---|---|---|
| `scripts/fx.gd` | +293/−3 | `BirdFlock` 内新增 P7 生态层：黄昏归栖（A）与船鸟联动（B）的状态、资格、分批调度、调试快照；全部复用既有状态机接口 |
| `scripts/main.gd` | +314/−14 | C1 萤火驱动、C4 帆船跳时重校准、近海触发窗口接线、`_eco_ctx` 权威上下文、`--p7shots` 专项截图入口（仅自动化用） |
| `scripts/isle_audio.gd` | +32/−8 | C2 夜层"淡出到低谷再 stop"、C3 火焰声连续淡出；未动音频总线 |
| `scripts/world.gd` | +28/−0 | 近海航线几何：`_coastal_route` 返回 `shore_a0/shore_a1`；新增 `static func shore_trigger_dist(out_pts,a0,a1)->float` |
| `docs/P7_BEHAVIOR_TABLE.md` | 新增 209 行 | 任务 C 真实行为对照表、跳时矩阵、问题分级与证据索引 |
| `tools/probe_eco7.gd`（+uid） | 新增 731 行 | A/B headless 探针（123 断言） |
| `tools/probe_p7c.gd`（+uid） | 新增 276 行 | C1–C4 修复探针（38 断言） |

改动合计（tracked）：**667 insertions / 25 deletions**。未改 `project.godot`、未新增资源/模型/UI/音效、未动存档与设置。

### 3.1 与既有模块的边界

- 未新增"生态协调器"类；A/B 逻辑作为 `BirdFlock` 的生态子状态实现（该模块本就是海鸥行为的所有者），事件入口 `on_boat_shore_pass` 由 `main.gd` 的帆船生命周期在既有 `COASTAL_CRUISE` 状态边界调用一次。
- 未在 `main.gd` 增加新的每帧业务逻辑；每帧仅 `update_birds(delta,sun_alt,ctx)` 传入上下文（既有调用点 `_update_lighting`），其余为一次性事件接线。
- 未接管全局时间、未重算日月、未创建第二状态机、未重写航行、未接管音频。

---

## 4. 任务 A：黄昏归栖

### 4.1 触发条件（为什么不是 `sun_alt < 4` 每帧）

`fx.gd::_update_eco(delta,sun_alt,ctx)` 同时检查：

1. **太阳高度**：`sun_alt <= DUSK_START_ALT(4.0)`；
2. **下降方向**：优先用权威上下文 `ctx.rising` 取反；缺失时用历史采样 `_sun_prev`（`sun_alt < _sun_prev - 0.0005`）；
3. **世界阶段**：`_night` 为真时直接进入夜间协调，不启动归栖；
4. **本次事件是否已触发**：`day != _roost_day`（按权威模拟日 `ctx.day = int(floor(_sim_seconds/86400))`，每模拟日最多启动一次）；
5. **跳转后校准**：`first_sample`（首帧无历史）不触发；暂停时 `ctx.paused` 只维护状态、不消耗计时器；
6. **取消/回拖**：进行中若太阳回到 `> DUSK_CANCEL_ALT(6.0)` → `cancel_return_day` 取消，空中鸟恢复白天规则，且 `_roost_day` 保留，同一日不复演。

日出上升阶段不满足"下降方向 + day 未消费"双条件，不会误触发。

### 4.2 分批归栖行为

- 目标空中数：`target = round(6 * (1 - p))`，`p = clamp((4 - alt)/6)`；即 alt≥4° 时 6 只、alt→-2° 时 0 只，随黄昏单调减少。
- 调度：空中数 > target 时，每 `rand(0.7,1.5) s` 尝试一只；候选只从**飞行中、非 waiting、已飞行 ≥1.0 s** 的鸟中挑选；调用既有 `_begin_landing`（内部走 `_find_free_slot`+`_reserve_slot`，失败则 `waiting=true` 并保留 0.9 s 重试间隔）。
- **不瞬移**：所有位置变化经由既有 TAKEOFF/FLY/LANDING 状态与 Tween/lerp；不写世界坐标。
- **不打断关键转换**：候选过滤排除 PERCH 起飞/降落/LANDING 中的鸟（状态机自然处理），夜门触发后由既有 `_request_night_landings` 收尾。
- **尊重栖息点约束**：落点位置、法线/脚高/坡度、占用互斥全部沿用既有机制（`_find_free_slot` 返回既有树/屋顶/屋檐/码头/灯塔等有效落点）。
- 允许跳过：无合适鸟记 `no_eligible_bird`，无空位记 `no_free_slot`；不强制、不刷屏（仅状态变化日志）。

### 4.3 幂等、夜间稳定与清晨恢复

- 同一模拟日只启动一次（`_roost_day`）；阈值浮动/多次采样不会重复；前跳跨到新一天的黄昏允许按新一天 restart 一次（每日一次语义）。
- 夜间：`_night` 时 `ROOST_ACTIVE → ROOST_NIGHT`（仅一次日志），已栖息鸟不再被要求归栖，PERCH timer=999 由既有夜间逻辑维持；`_roost_timer` 清零。
- 白天/黎明：`ROOST_NIGHT → ROOST_NONE`，每只栖鸟按既有黎明错峰（rand 2–14 s）与起飞接口恢复，不会全体同步起飞；黄昏未完成动画不会残留（状态机内自洽，无外部 Tween 引用）。
- 时间跳转：直接跳深夜 → 不补演归栖动画，仅状态协调 + 既有夜间落栖；跳回白天 → 先取消归栖、鸟恢复日间规则后再起飞；后拖跨日 → 按"新模拟日"规则处理，不重放已消费事件。

---

## 5. 任务 B：帆船经过近海航段时的海鸥联动

### 5.1 真实近海航段的确定（不是按名字猜）

- `world.gd::_coastal_route` 是 4 条 coastal 航线的真实生成器（方位弧 `a0..a1` + 外/返两段折线 + 正弦鼓包），本轮在返回值中补充真实几何元数据 `shore_a0/shore_a1`（远海 `_far_route` 不返回这两个字段）。
- `world.gd::shore_trigger_dist(out_pts,a0,a1)` 遍历 out 折线累计弧长，把"方位角落在近海弧段"的首末弧长换算为触发点：`first + (last-first)*0.28`。取 28% 而非弧段起点，是因为船刚进入可观察的近海弧段、海鸥有响应时间且船仍在视野内；该比例由航线几何与既有截图机位观察确定，不是凭空半径。
- `main.gd::_set_boat_shore_window(route)`：仅 `kind=="coastal"` 且含 shore 元数据时设置 `_boat_shore_trigger`，否则 `_boat_shore_done=true` 禁用（远海航线完全不受影响）。
- `main.gd::_update_boat` 的 `COASTAL_CRUISE` 状态中，每帧只做"是否越过触发弧长"的一次性边界判断：`if not _boat_shore_done and _boat_shore_trigger>0 and _boat_route_dist>=trigger and not _paused` → `_boat_shore_done=true` 且调用一次 `_birds.on_boat_shore_pass(_boat_trip, boat_pos, sun_alt)`；连续移动不会重复触发（无每帧协程/Tween/临时节点）。

### 5.2 候选海鸥筛选与行为

`fx.gd::on_boat_shore_pass(trip, boat_pos, sun_alt)` 的资格与选鸟：

1. 无鸟 → `no_birds`；
2. 该航次已尝试过 → `trip_done`（**每航次最多一次，含跳过**，见 5.3）；
3. 夜间 → `night`；归栖进行中 → `dusk_roost`；太阳高度 < `BOAT_RESP_MIN_ALT(8.0)` → `low_sun`；
4. 候选：**已停栖且无延迟**优先（从原栖点走既有 `_begin_takeoff` 正常起飞，释放既有落点预约），不足时用**飞行中且非 waiting、已飞 ≥1.2 s** 的空闲个体；
5. 无候选 → `no_candidate`（安静跳过，不重试）；
6. 数量：默认 1 只；候选池 ≥2 时以 0.62 概率选 2 只（**事件上限 1–2 只**）；
7. 错峰：第一只立即响应，第二只 `resp_delay=rand(0.5,1.1) s`，由既有 `_update_perched` 到期后走既有起飞接口；两鸟朝向 `boat_az ± 0.16 rad` 各自随机，不同步；
8. 响应行为：`_update_boat_response` 让 `resp_w` 以 1.8 s 上升、2.4 s 回落，`_flight_target` 在既有轨道点基础上加 `10 m × w` 的水平外移与 `-4 m × w` 的高度下压，时长 `rand(9,15) s`；结束后 `resp_w→0`，鸟回到原有 FLY 逻辑（继续日常飞行，或按既有逻辑寻机降落），不强制状态、无瞬移、不穿船/穿屋、不追船。

### 5.3 单次航行限制与恢复

- 绑定已有 `_boat_trip`（既有航次号）：`_boat_trip_handled` 记录已处理航次；**进入函数即先标记**（即使因夜间/归栖/低太阳/无候选跳过，也不在同航次重试），满足"一次航行最多一次、跳过安静"。
- 新航次（`_boat_trip` 递增）→ 资格自动更新；船离开/等待/返航/重新离港由既有状态机管理，不影响本事件。
- 场景重载：`BirdFlock` 与 `_boat_trip_handled` 随实例重建，不持久化、不重放已消费事件（本轮不新增存档）。
- 时间跳转/状态重算：`_boat_shore_done` 仅在 `_set_boat_shore_window`（航次开始时）重置；跳时若仍在同航次，不会重放。
- **未新增全局冷却**：每航次一次已经足够，没有证据支持再加一层冷却计时器。

---

## 6. 任务 C：昼夜行为与环境音协调

### 6.1 真实行为对照表（完整表见 `docs/P7_BEHAVIOR_TABLE.md`）

| 系统 | 真实入口 | 修改前真实条件 |
|---|---|---|
| 太阳/天空/调色板 | `main.gd::_update_lighting`；`isle_astro.gd::compute/day_events`；`isle_math.gd::theme_time`；`isle_palette.gd::sample` | 每帧按 `_sim_seconds` 计算；日出/日落几何高度 -0.8333°；theme_time 分段 smoothstep；调色板 25 关键帧 lerp |
| 海鸥 | `fx.gd::_update_day_night/_update_perched/_update_flying/update_birds` | 昼夜滞回 -2°/+2°；夜间转落栖；黎明错峰 2–14 s；飞行轨道指数趋近 |
| 鸟鸣 | `isle_audio.gd:update_audio`（day>0.55 紧约束）；`main.gd::_update_audio` | 随机间隔 6–14 s，有效阈值 alt≈+2.94° |
| 帆船 | `main.gd::_update_boat/_sync_boat_clock/_enter_resting/_is_boat_rest_hour` | 休息窗 18:00–08:00；DOCKED 3–7 s 出航；返航减速、远海淡入淡出 |
| 炊烟 | `fx.gd::is_smoke_window/set_sim_seconds`；`main.gd::_update_smoke_clock` | 11:00–13:00、17:00–19:00 左闭右开；1.5 s 线性爬坡；窗外直接关发射 |
| 灯塔 | `main.gd::_update_lighthouse_beam/_time_flow_scale` | 周期 20 s（sim 按日长缩放）；强度随太阳平滑；跳时角度连续 |
| 窗灯/灯串 | `main.gd::_update_lighting` + `cottage.gd` | 无开关阈值，逐帧连续调光 |
| 海浪/风/夜声 | `isle_audio.gd` 三循环层 + 夜间门控 | 一阶指数平滑 tau=[2.4,3.2,2.0] s；夜层双门限 0.02/0.015；**关闭分支直接 stop** |
| 火焰声 | `isle_audio.gd` 火焰块；`main.gd`（`fireplace_on=_sun_alt<2.0`） | 开关变化即切 -12 dB / 静音，无淡出 |
| 萤火/花瓣/流星 | `fx.gd::fireflies/petals`；流星无实现 | 萤火从不发射（C1）；花瓣全天发射；无昼夜门 |

### 6.2 本轮实际修复的节奏问题（只修有证据的）

- **C1（main.gd `_update_lighting`）**：改读 `_fx["fireflies"]["node"]`（真实 `GPUParticles3D`），按调色板亮度 `fireflyI` 驱动 `emitting = (ffi > 0.02)` 与 `amount_ratio = max(ffi,0)`。未改 fx 创建逻辑与夜间效果设计。
- **C2（isle_audio.gd 夜层门控）**：新增 `NIGHT_FADE_STOP_ENV := 0.015`；停止条件改为"目标已低于 NIGHT_STOP_ENV 且当前 env 已淡到 ≤0.015"，淡出沿用既有 `LOOP_TAU[2]=2.0 s` 指数包络，到低谷才 `stop()`（`loop_stop` 事件附 `fade_tau`），并把"不再播放时的 env 强制清零"限制在真正停止之后，避免打断淡出。共 8.5 s 内平滑收尾，不再单帧 -73 dB。
- **C3（isle_audio.gd 火焰声）**：新增 `_fire_env`，关闭时不再一步静音，而是按 `FIRE_FADE_TAU=0.9 s` 指数淡出、到 `FIRE_FADE_STOP_ENV=0.015` 才 stop（`fire_stop{source:"fireplace_off",stop_env,fade_tau}`），开启时恢复 `FIRE_BASE_DB=-12`。
- **C4（main.gd `_sync_boat_clock`）**：用 `jumped := absf(_time_jump) > 0.001` 区分真实跳转；仅跳转时，若 RESTING 的 `rest_until > _sim_seconds` 且当前不在休息时段，则把 `rest_until` 收敛到当前时刻（提前结束休息）；夜间/休息时段内仍保持到次日 08:00；正常白天短停靠不受影响。

### 6.3 明确未改的（避免"为整齐而破坏合理独立节奏"）

- 未改天文计算、未改航线与生命周期规则、未改 11:00–13:00/17:00–19:00 炊烟窗口、未重构音频总线、未统一各系统昼夜阈值、未删除夜间效果、未迁移到新控制器。
- 鸟鸣阈值 +2.94° 与归栖 4.0°、夜飞门 -2.0° 的原生顺序为"归栖开始 → 鸟鸣停 → 全栖"，自然且不冲突 → 保留。灯塔/窗灯/炊烟/帆船各自的独立节奏属设计，保留。
- C5 炊烟收尾、C6 死代码：证据/影响不足，未改（见 §2.1）。

---

## 7. 新增与执行的测试、命令、通过情况及失败项

### 7.1 headless 自动化（真实执行，退出码与断言数均为实测）

通用命令形式：
```
ENG="D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe"
PROJ="D:/休闲小岛幻境/游戏工程"
"$ENG" --headless --path "$PROJ" --script res://tools/<probe>.gd
```

| 测试 | 覆盖 | 结果 | 日志 |
|---|---|---|---|
| `probe_eco7.gd`（新增） | A：连续下降启动、上升不误触发、阈值抖动/回拖/跨日、暂停、无栖点跳过、分批非同步、夜间稳定、跳深夜不补演；B：航段几何、可触发/不可触发、候选资格、≤2 只、每航次一次、连续范围去重、跳过原因、栖点互斥、换航次资格、远海/夜间/返航不受影响；main 集成 | **pass=123 fail=0**，exit 0 | `开发产物/p7/logs/post/final_eco7.log`（过程日志 `probe_eco7_fix.log`） |
| `probe_p7c.gd`（新增） | C1 萤火节点/材质/夜间 emitting/amount_ratio、白天关闭；C2 跳时首帧仍播、env 单帧跌幅<0.20、淡出期音量单帧跌幅<3 dB、停止时间 2–12 s、stop_env 与 `fade_tau`；C3 火焰声同法（实测单帧跌幅 1.93 dB、3.6 s 停）；C4 帆船四种跳时/正常工况 | **pass=38 fail=0**，exit 0 | `开发产物/p7/logs/post/final_p7c.log` |
| `--selftest` | 既有交互/菜单/音频等 53 项 | **53/53 passed**，exit 0 | `开发产物/p7/logs/post/final_selftest.log` |

### 7.2 既有探针回归（修复后重跑，脚本 `开发产物/p7/logs/post/run_post_suite.sh`）

| 探针 | 结果 | 探针 | 结果 |
|---|---|---|---|
| probe_audio6 | 232 checks / 0 fail | probe_audio_p5 | 85/0 |
| probe_boat_p5 | 76/0 | probe_smoke6 | 96/0 |
| probe_astro6 | PROBE6 PASS | probe_time_p5 | 1886/0 |
| probe_eco7 | 123/0 | probe_bird6 | 45/0 |
| probe_world_p5 | PASS | probe_lighthouse_p5 | 17/0 |
| probe_settings6 | ALL PASS | probe_quality6 | rc0（既有入口，无独立断言行） |
| probe_water6 | rc0 | probe_frame_t5 | 5/0 |
| probe_astro_xcheck_t7 | PASS | probe_p7c | 38/0 |
| probe_fx_p4 | 64/1（与基线同数值，P6 过期断言） | probe_world_p4 | 3 FAIL（与基线同，P6 过期断言） |

失败项说明：仅上述 2 项既有失败，且在未修改的 baseline worktree 上同数值复现，判定非 P7 回归；未删除/未降低任何断言。

### 7.3 窗口测试（GPU 独占）

| 入口 | 命令 | 结果 |
|---|---|---|
| P7 专项截图 | `"$ENG" --path "$PROJ" --resolution 1600x900 -- --p7shots` | exit 0；14 张 1600×900 PNG；`开发产物/p7/logs/post/p7shots_fix2.log` |
| 回归截图 | `"$ENG" --path "$PROJ" --resolution 1600x900 -- --shots` | exit 0；61 张 PNG 重新生成；`开发产物/p7/logs/post/shots_post.log` |
| 性能 | `"$ENG" --path "$PROJ" --resolution 1600x900 -- --perf` | exit 0；17 条 `[PERF]`；`开发产物/p7/logs/post/perf_post.log` |

说明：`--shots` 日志尾部有引擎 `user://` 日志/管线缓存写入 ERROR（与基线 `baseline_perf.log` 同类、退出码 0，不影响截图产物）；该目录历史文件累积 166 张，本轮按 mtime 确认新生成 61 张。

---

## 8. 关键场景截图的真实路径与实际检查

P7 专项截图目录：`D:/休闲小岛幻境/开发产物/p7/shots/`（1600×900）。逐张实检结论：

| 文件 | 场景 | 实检结果 / 日志证据 |
|---|---|---|
| `p7_01_day_gulls.png` | 白天活动 | 白天海面/岛屿正常，空中海鸥活动（airborne=5） |
| `p7_01b_day_gulls_close.png` | 白天近景 | 屋顶屋脊停栖与空中海鸥可辨 |
| `p7_02_dusk_roost_start.png` | 黄昏归栖开始 | sun_alt=3.83、roost_starts=1、state=ACTIVE、airborne=5 |
| `p7_02b_dusk_roost_close.png` | 黄昏开始近景 | 屋脊 3 只停栖 + 1 只空中，天色转暖 |
| `p7_03_dusk_roost_mid.png` | 归栖中段 | sun_alt=0.04、roost_landings=3、airborne 5→2、perched=8 |
| `p7_03b_dusk_mid_close.png` | 中段近景 | 晚霞里空中仅剩少量海鸥，多数已落栖 |
| `p7_04_night_calm.png` | 稳定夜间 | night=true、roost_state=NIGHT、airborne=0、perched=10；**清晰可见萤火粒子**（C1 修复视觉证据）+ 灯塔光束 + 小船 |
| `p7_04b_night_perch_close.png` | 夜间近景 | 灯塔旁/屋脊 3–4 只海鸥停栖、稀疏萤火，夜间不强飞 |
| `p7_05_dawn_recover.png` | 清晨恢复 | night=false、roost_state=0、takeoffs=2，活动恢复但非全体同步 |
| `p7_05b_dawn_recover_close.png` | 清晨近景 | 屋顶周边多只海鸥恢复活动/起飞 |
| `p7_06_boat_pass.png` | 船进入近海航段 | 宽景：船在近海浅水经过，岛与天空有海鸥；日志 `boat pass armed route=West Reach trip=2 trigger=23.1 len=44.8`、boat_pass_attempts=1、trip_handled=2 |
| `p7_06b_boat_respond_close.png` | 船鸟响应同框 | 近景同框：帆船 + 空中响应海鸥（多只鸟点），日志 birds=1–2（两次运行分别 1/2 只） |
| `p7_07_boat_recovered.png` | 船后恢复 | takeoffs=7、landings=8，船驶离后海鸥继续日常活动 |
| `p7_07b_boat_recovered_close.png` | 船后近景 | 屋脊/空中恢复常态 |

回归截图：`D:/休闲小岛幻境/开发产物/shots/`（本轮 61 张，含 00_menu、01_dock、05_quality_*、06_bird_roof、06_beam_house_*、07_menu_* 等），命令成功、与基线同流程；**未逐张人工复核**（P7 结论不依赖这组图，仅验证入口与菜单/相机/画质链路未回归）。

---

## 9. 修改前后性能对比与测试条件

条件：同机、同引擎 v4.7.2.stable.official.ed1daf0bf、1600×900、vsync 关闭、默认画质入口（quality=2），基线/修复后各一次，均为窗口运行。基线日志 `开发产物/p7/logs/baseline_perf.log`，修复后 `开发产物/p7/logs/post/perf_post.log`。

| 场景 | 基线 fps / frame_ms | 修复后 fps / frame_ms |
|---|---|---|
| noon_clear | 176.4 / 5.67 | 200.4 / 4.99 |
| golden_cloud_water | 175.4 / 5.70 | 187.2 / 5.34 |
| night_shadows | 155.6 / 6.43 | 185.6 / 5.39 |
| night_close | 182.9 / 5.47 | 200.2 / 5.00 |
| far_island | 149.6 / 6.68 | 182.5 / 5.48 |
| sky_up | 163.3 / 6.12 | 182.8 / 5.47 |
| time_panel_open | 162.9 / 6.14 | 179.2 / 5.58 |
| lite_noon_nomultimesh | 167.6 / 5.97 | 188.7 / 5.30 |
| lite_night_nomultimesh | 175.8 / 5.69 | 188.6 / 5.30 |
| quality_4 | 97.8 / 10.23 | 111.9 / 8.94 |
| quality_3 | 102.9 / 9.72 | 130.7 / 7.65 |
| quality_2 | 160.4 / 6.23 | 177.9 / 5.62 |
| quality_1 | 160.6 / 6.23 | 181.9 / 5.50 |
| quality_0 | 153.7 / 6.51 | 184.5 / 5.42 |

- **VRAM**：quality_4/3/2/1/0 分别 621.3/561.0/268.8/201.6/165.4 MB，基线与修复后逐档完全一致。
- **对象/节点**：各场景 ±约 3%，五档 ±约 5%（其中夜间场景因萤火粒子实际发射而略多，属 C1 修复的预期效果）；`after_6s` 泄漏观测 orphan 基线 21 → 修复后 32（均为低水位，且两次运行前后有其他进程/GPU 状态差异，未见随场景增长的泄漏）。
- **结论**：所有 14 个场景帧率不低于基线、frame_ms 不高于基线；新增每帧生态逻辑为常数级分支，未引入可见帧时间波动；萤火恢复发射后夜间场景仍快于基线。绝对帧率受 GPU 冷热/后台进程影响，故只作"无退化"判定，不宣称具体提升。

---

## 10. 未完成事项、环境限制与遗留风险

1. **声音听感未做真实听觉验收**：C2/C3 只由 headless 探针验证了"单帧跌幅、停止门限、淡出时长"数值与事件；没有录音/回放对比，无法证明人耳听不到 pop。残余风险：低（-12 dB→淡出、-6.9 dB→-42.76 dB 再停），但如实标注未完成。
2. **视觉验收为固定机位静态截图 + 日志数值**，不是连续长时间观察；"自然、克制、不刻意"的主观目标无法用自动化证明，只能由本轮截图/日志与设计约束支撑。船鸟同框近景（p7_06b）中船与鸟的距离仍较远，肉眼识别度一般；已用日志（attempts/birds/trip_handled/takeoffs）补强。
3. **C5 炊烟 13:00/19:00 收尾**未修：缺少"已存在烟团是否瞬间消失"的视觉证据，且涉及禁改的两个炊烟窗口；保留为已知风险。
4. **C6 死代码** `_boat_depart_hours` 未清理（无行为影响，本轮不做无关清理）。
5. `probe_fx_p4`（64/1）与 `probe_world_p4`（3 FAIL）为 P6 过期断言，本轮按要求未删除/未改断言；它们在基线同样失败，故不阻塞 P7 验收，但会在套件中持续以"既有失败"出现。
6. **时间回拖语义**：后拖到前一个模拟日且随后再次经过黄昏时，按"新一天"规则允许再启动一次归栖（不补演、不重放已消费事件）；这是有意设计，但"回拖到当天黄昏"与"跨日"的行为差异需在后续维护中保留注释。
7. `--shots` 的 61 张回归截图未逐张人工复核（入口/菜单/相机/画质链路已跑通，P7 视觉结论不依赖它们）。
8. headless 环境限制：真实鼠标拖动（selftest 1 SKIP）、真实音频设备与听感、连续实时观察均无法自动覆盖。

---

## 11. 回滚方式与交付检查

### 11.1 回滚

- 本轮独立分支 `p7-v1`，基线与回滚 tag：`p7-baseline-20261021`（= 交接点 `7941816`），只读 worktree `D:/休闲小岛幻境/开发产物/p7/baseline_wt` 保留。
- 回滚到修改前：`git switch --detach 7941816`（或切回 `p6-closeout`）；回滚本轮提交：`git revert <p7 commit>`。
- 改动均为可逆文本修改：4 个脚本（667+/25-）+ 4 个新增文件（行为表、2 个探针及其 .uid）；未改资源、场景、工程配置、归档或历史 worktree。

### 11.2 完成条件对照

| 条件 | 状态 | 证据 |
|---|---|---|
| 黄昏归栖在实际运行场景可观察、可重复验证 | ✅ | p7_02/02b/03/03b/04/04b 截图 + eco 日志 roost_starts/landings/state；probe_eco7 123/0 |
| 清晨恢复正常，时间跳转不永久卡死/不重复演出 | ✅ | p7_05/05b；probe_eco7 A8/A10/A11、probe_p7c C4 |
| 船鸟联动符合航线/候选状态/单次航行限制 | ✅ | p7_06/06b/07/07b + `[ECO] boat_pass`/`boat_shore` 日志；probe_eco7 B1–B10 |
| 既有栖息点互斥、海鸥状态机、帆船生命周期无回归 | ✅ | probe_bird6 45/0、probe_boat_p5 76/0、probe_eco7 A6/A7、selftest 53/53 |
| 昼夜节奏协调经过完整周期检查 | ✅（行为/视觉）/ ⚠（听感） | 对照表 + C1–C4 探针 + 四时段截图；听感未验证见 §10 |
| 相关自动化测试真实执行且有明确结果 | ✅ | §7 全部命令与日志路径 |
| 视觉有实际观察证据，不能观察部分如实标记 | ✅ | §8 逐张实检；听感/连续观察已标注 |
| 无无关模块大规模重构或不可恢复修改 | ✅ | diff 仅 4 脚本 + 4 新增文件；未改工程配置/资源/归档 |

### 11.3 证据索引

- 基线：`开发产物/p7/logs/baseline_summary.md`、`baseline_*.log`、`baseline_shots`、`baseline_perf.log`
- 任务 C 审计：`游戏工程/docs/P7_BEHAVIOR_TABLE.md`、`开发产物/p7/audit/`（23 日志）
- 修复后回归：`开发产物/p7/logs/post/`（18 探针 + selftest + p7shots + shots + perf 日志）
- P7 截图：`开发产物/p7/shots/`（14 张）；回归截图：`开发产物/shots/`（本轮 61 张）
- 新增测试：`游戏工程/tools/probe_eco7.gd`、`游戏工程/tools/probe_p7c.gd`
