# P7 昼夜行为与环境音协调 —— 实证审计报告（任务 C）

> 审计角色：eco-audit（只读审计，未修改任何现有源文件）。
> 审计对象：D:/休闲小岛幻境/游戏工程，分支 p7-v1（HEAD 79418169dc61ebe17e52d8f6e6c45af6d1d5ae6b）。
> 工作区快照（本报告行号基准）：Lead 未提交改动 scripts/main.gd、scripts/fx.gd、scripts/world.gd；blob 为
> main.gd c8a716caeb5c190cfef18e1ccb96d511b29fca24（mtime 2026-10-21 01:00:32, 178168B）、
> fx.gd 217222d3385b2ad3eb02a038a76f92e40800a916（00:43:35）、
> world.gd 3dc9de03a0861f077dc03f12ae9aa3a353d1fd42（00:43:44）；工作区 diff 608 insertions / 9 deletions。
> 只读文件（无改动）：isle_audio.gd 136791f1…、isle_astro.gd 66c647e4…、isle_math.gd 734bb86f…、isle_palette.gd 7df367a7…、cottage.gd 017b8df0…。
> **注意：main.gd / fx.gd / world.gd 正在 Lead 工作区改动中；若相关文件再次落盘，引用行号需按新 blob 重新对齐。**
> 默认日长 600 s（10 分钟/游戏日，时间流速 144×）见 isle_settings.gd:33、isle_settings.gd:213；本机设置时间源为 real（实例化时 events sunrise 06:26 / sunset 17:56 = 2026-10-21）。

## 0. 结论摘要

- 现有 headless 探针在当前代码上全部通过：audio6 232/0、audio_p5 85/0、smoke6 96/0、bird6 45/0、lighthouse_p5 17/0、boat_p5 76/0、eco7 123/0。
- probe_fx_p4 有 1 条失败（个体 8-20s 计时器错峰切换），经 baseline 对照确认是 **P6 遗留的过期断言**，不是 P7 回归。
- 已确认的不同步问题 6 条（见 3.1），其中对玩家可感知影响最大的是：**萤火完全不发射**、**时间跳转时夜间环境声单帧硬切约 73 dB**、**时间回溯到白天后帆船仍锁在 RESTING 约 20 游戏小时**。
- 海鸥黄昏归栖（任务 A）与船鸟联动（任务 B）的行为与断言一致，未发现会被归栖/联动破坏的白天行为；鸟鸣阈值与归栖阈值不冲突（见 4(a)）。

## 1. 方法与证据

- 只读源码（取最新落盘内容）+ 只跑 headless；未开窗口（GPU 由 baseline-verify 独占）；未用 godot-ai MCP。
- 运行现有探针共 9 个（日志见第 6 节），并在 baseline_wt（= tag p7-baseline-20261021，只读副本）跑同一 probe_fx_p4 做对照。
- 一次性 headless 探针写在 baseline_wt/tools/ 下（不污染主仓库），命名 _eco_audit_tmp.gd、_eco_audit_tmp2.gd，用后已删除 .gd 与 .uid；其中 tmp2 结果 PASS 13/0，专门测「夜间快照 + 时间跳转 + 帆船回溯」。
- 所有证据数字均为实测输出，不是按脚本名推测。

## 2. 真实行为对照表

### 2.1 总表（入口 / 真实条件 / 平滑写法 / 测试证据）

| # | 系统 | 代码入口（文件:行号） | 真实触发条件与精确阈值 | 幂等/平滑写法 | 现有测试证据 |
|---|------|----------------------|------------------------|---------------|--------------|
| 1 | 太阳与天空 | scripts/main.gd:696-708（_update_lighting）；scripts/isle_astro.gd:402-422（compute）、433-440（day_events）、445+（_compute_day_events）、504-510（sunrise/sunset） | 每帧用 _sim_seconds 调 IsleAstro.compute；日出/日落按几何高度 SUN_RISE_ALT=-0.8333（isle_astro.gd:24）；民用 -6、航海 -12、天文 -18 各自 cross+refine | 天文本身连续；天空参数逐帧直写无平滑 | probe_astro6 423/0；probe_time_p5 1886/0 |
| 2 | 主题时间/调色板 | scripts/main.gd:707-708；scripts/isle_math.gd:133-155（theme_time）；scripts/isle_palette.gd:51-68（sample）、8（NUMBER_KEYS） | theme_time 分段阈值 rising：-18/-6/-0.833/6/62；setting：6/-0.833/-6/-18，值域 0.02..0.96；palette 在 25 个关键帧间线性插值 | 分段 smoothstep；关键帧 lerp（无跳变） | probe_pal.gd:12 数值键；probe_astro6 |
| 3 | 海鸥-昼夜/归栖 | scripts/fx.gd:2256-2270（_update_day_night）、2272-2277（夜落）、2279-2286（_on_dawn）、2290-2292（目标数）、2312-2382（_update_eco）、2381-2411（_update_perched）、2427-2450（_update_flying） | 昼夜滞回：太阳高度下穿 -2.0 转夜、上穿 +2.0 转昼；归栖启动：太阳下降且 alt<=4.0（DUSK_START_ALT，fx.gd:1483），回拖 >6.0 取消（DUSK_CANCEL_ALT，1484）；每模拟日只启动一次（按 ctx.day）；分批间隔 rand(0.7,1.5)s；目标空中数 round(6*(1-p))，p=clamp((4-alt)/6)，即 alt>=4:6、-2:0 | 每只鸟独立状态机；夜间 PERCH timer=999；黎明 PERCH 错峰 rand(2.0,14.0)s；飞行轨道 lerp(1-exp(-3.2*dt)) | probe_bird6 45/0；probe_eco7 123/0（A1 连续下降 max_jump=0.55m/landings=3/夜间 perched=10；A2 日出 171 帧后首飞；A3 抖动/回拖/跨日；A8 跳深夜不补演） |
| 4 | 海鸥-鸟鸣（环境音） | scripts/isle_audio.gd:529-534（update_audio 内）；main.gd:3689-3699（_update_audio）；main.gd:624（每帧） | 计时器到期 rand(6,14)s 后再判定：day>0.55 且 night<0.35 且 sun_alt>2.0；day=smoothstep(-4,9,alt)（isle_audio.gd:483），night=clamp(-alt/10,0,1)（main.gd:3692）；day>0.55 为紧约束 → 有效阈值 alt≈+2.94° | 随机间隔播放，无淡入淡出（单样本） | probe_audio6 232/0；probe_audio_p5 85/0；tmp2 实测阈值穿越 17:34（sim-day0）/17:39（real） |
| 5 | 帆船-作息与状态机 | main.gd:2877-2879（_is_boat_rest_hour）、2882-2887（_next_rest_end_sim）、2861-2874（_enter_resting）、2890-2900（_sync_boat_clock）、2902-2986（_update_boat）；常量 main.gd:14-26（BOAT_REST_START_HOUR=18.0/END=8.0） | 休息窗 18:00—次日 08:00（按模拟时钟）；到港后休息 rand(18,40)s（模拟秒按流速缩放）；夜间强制停到次日 08:00；DOCKED 停留 rand(3,7)s 后出航；8 条航线（4 coastal + 5 far）出航时随机选定，途中不重随机 | 出港/返航速度用加速上限平滑（+max(0.8,v*0.55)*dt 等）；返航最后 8m 减速；远海淡入淡出 | probe_boat_p5 76/0（休息窗、跳时等待、探照灯）；probe_eco7 B1-B3 + 主场景集成 |
| 6 | 帆船-近海触发（P7 任务 B） | main.gd:2790-2802（_set_boat_shore_window）、2932-2940（COASTAL_CRUISE 触发块）、2757-2789（_start_boat_departure）；world.gd:2660-2679（shore_trigger_dist）、2609-2654（_coastal_route 返回 shore_a0/a1）、2750-2774（_sail_routes） | 仅 coastal 航线；触发距离=近海方位弧段 [a0,a1] 在 out 折线上的前 28% 弧长（shore_trigger_dist）；_boat_shore_done 保证每航次一次；夜间/归栖中低太阳时由 _birds 内部跳过 | 一次性边界事件；不新建飞行 AI | probe_eco7：B1 trip7 ok birds=2 handled=7、重复 trip_done；主场景集成 out_len=44.8 trigger=23.1、第 621 帧越过、attempts 0→1、换 far 航线无触发 |
| 7 | 帆船-探照灯 | main.gd:2714-2742（_update_boat_spot）、2546-2555（_update_props 调用链） | 硬门：_sun_alt < 0.5（2717）且船可见/未淡出/非 OFFSCREEN_WAIT；strength=clamp(night*fade*moving)，night=1-smoothstep(-6,2,alt)（2729）、moving=1.0 或 0.42（2730）；可见门 strength>0.04（2733） | 强度随太阳平滑；但 on/off 硬门在 alt=0.5 单帧切换 | probe_boat_p5 spot_light（夜 alt=-12 strength>0.2、原点/方向/俯角、白天<0.01） |
| 8 | 炊烟 | scripts/fx.gd:586-597（常量与 is_smoke_window）、622-649（set_sim_seconds）、705-761（smoke 创建）；main.gd:1062-1068（_update_smoke_clock，调用点 471/644） | 两个左闭右开窗口：11:00–13:00、17:00–19:00；窗口内 ramp 0→1.5s 线性；窗外 ramp=0、emitting=false；时间跳转（首帧或 dt>30s）进窗直接满强度 | 1.5 s 线性爬坡；smoke_debug 幂等状态查询 | probe_smoke6 96/0；probe_main_smoke_t5 诊断（12:10 ratio=1.0、15:00 emitting=false）；tmp2 12:00 ratio=1.0 |
| 9 | 灯塔 | main.gd:3089-3094（_time_flow_scale）、3096-3148（_update_lighthouse_beam）；常量 main.gd:14-26（周期 20s、参考日长 480、俯角 34°、外/内锥 12°/3.5°、射程 120） | 旋转仅在 PLAYING；real: delta*TAU/20；sim: _sim_delta*TAU/(20*180)；夜间系数 night=1-smoothstep(-7,3,alt)（3118），强度=clamp(night*(0.22+lanternI*1.05),0,1)（3120）；可见门 strength>0.035（3125） | 角度 fposmod 连续、逐帧积分（跳时不跳变，lighthouse_p5 已验证）；强度随太阳平滑 | probe_lighthouse_p5 17/0（周期/倍速/暂停/跳时角度连续/30 与 120fps 一致/方向俯角） |
| 10 | 窗灯/灯串 | main.gd:817-829（window_mats/glow 与 halo）、830-853（吊灯/路灯/船灯）；cottage.gd:212-213、222-244、261-269、491-524 | 无开关阈值：每帧 glow=0.05+windowI*0.55、halo wf=clamp(0.02+windowI*0.55,0,1.2)；windowI 来自调色板（正午 0.224、深夜 1.535）→ 正午 glow≈0.173、深夜≈0.894 | 连续调光，无硬切 | probe_cottage6:428-433（window_mats.size()==1、阁楼玻璃不在其中）；probe_cottage_p4 计数 |
| 11 | 海浪与风（三层循环） | isle_audio.gd:48-54、474-486、508-515、547-560；main.gd:3692-3699 | Ocean 目标 0.88+0.12*day；Wind 目标 0.30+0.70*wind（wind 来自 main 三正弦 0.40+0.22*sin(0.09t)+0.10*sin(0.31t)）；Night 目标 smoothstep(0.02,0.9,clamp(-alt/10))；一阶平滑 tau=[2.4,3.2,2.0]s；音量=base_db+linear_to_db(env)，base=[0,-4.5,-6.5] | 指数趋近（1-exp(-dt/tau)）；停止后 volume_db=-80 | probe_audio6 232/0；probe_audio_p5 85/0 |
| 12 | 夜间环境声门控 | isle_audio.gd:493-506（门控）、508-515（env）、547-560（增益） | 双门限：target>=0.02 开（对应 alt≈-0.94°）；target<0.015 关（对应 alt≈-0.84°）；滞回带约 0.10°；门控带只在 target 语义上，正常太阳移动不会抖 | 开局 env=max(env,0.015) 软起 + tau=2.0s 淡入；**关闭分支直接 stop()，无淡出** | probe_audio6；一次性探针实测：自然黎明停点 alt=-0.838、停前 env=0.0154/db=-42.76，播放期间最大单帧变化 0.01dB；夜跳昼单帧 -6.94→-80 dB |
| 13 | 火焰声 | isle_audio.gd:518-527、75（FIRE_BASE_DB=-12）、113；main.gd:3698（fireplace_on=_sun_alt<2.0） | 仅当 fireplace_on 变化才切换：alt<2.0 播放（-12dB），alt>=2.0 停止；无淡入淡出 | 状态切换幂等；但无平滑 | probe_audio6；tmp2/一次性探针：alt=2.000 单步 stop（-12dB→静音） |
| 14 | 萤火 | scripts/fx.gd:763-795（fireflies 创建，769 emitting=false，791 mat=additive_material）；main.gd:447（创建）、854-859（写入） | **实际无任何生效条件**：fx 创建即 emitting=false 且全仓无置 true；main 试图写 amount_ratio，但 mat 是 StandardMaterial3D（isle_math.gd:214），as ShaderMaterial 恒为 null，854-859 分支永不执行 | 无（当前完全不发射） | **无运行时断言**：probe_pal.gd 只查 palette 数值键；一次性探针实测 mat=StandardMaterial3D、cast=null、30 帧后 emitting=false、节点 amount_ratio=1.0 但未发射 |
| 15 | 花瓣 | scripts/fx.gd:797-838（petals 创建，803 emitting=true） | 创建即全天发射，无昼夜/时间门 | 无 | 无运行时断言（仅 probe_quality_override_t7 引用） |
| 16 | 流星 | — | **项目无流星实现**：grep -rn 'meteor' scripts/ docs/ 0 匹配 | — | 无 |

### 2.2 阈值—太阳时刻锚点（供判断边界差异）

实测太阳高度穿越时刻（sim-day0 = 1970-01-01；real = 2026-10-21）：

| 太阳高度 | sim-day0 日落侧 | real 日落侧 | sim-day0 日出侧 | real 日出侧 |
|---|---|---|---|---|
| +4.0°（归栖启动） | 17:29 | 17:35 | 07:31 | 06:47 |
| +2.94°（鸟鸣停/起，有效阈值） | 17:34 | 17:39 | 07:26 | 06:43 |
| +2.0°（海鸥夜间门；火焰声门） | 17:38 | 17:44 | 07:21 | 06:38 |
| +0.5°（船探照灯硬门） | 17:46 | 17:50 | 07:14 | 06:32 |
| -0.84°（日出/日落几何） | 17:52 | 17:56 | 07:08 | 06:26 |
| -2.0°（海鸥夜间飞行转降落门） | 17:58 | 18:01 | 07:02 | 06:21 |
| -6.0°（民用暮光） | 18:17 | 18:19 | 06:43 | 06:03 |

- sunrise/sunset：sim-day0 07:08/17:52，noon 12:30（alt 43.83）；real 2026-10-21 06:26/17:56，noon 12:11（alt 56.19）。
- 默认日长 600s 时 1 游戏日=600 真实秒（144×）：日落后 4.0°→-2.0° 约 29 游戏分≈12 真实秒；1°≈2 真实秒。**因此清单里大多数阈值差（1–3°）在默认流速下只差 2–6 秒真实时间，肉眼基本不可察；唯一硬切换点见 3.1/3.2。**

### 2.3 时间跳转后的重校准矩阵（[ / ]、数字键 1-5、时间面板）

共同路径：三种跳时都只做 _sim_seconds 更新 + _events=day_events() + _sync_boat_clock()（main.gd:1169-1196、2503-2522），其余系统靠每帧读 _sim_seconds/_sun_alt 自洽。

| 系统 | 跳时后行为 | 结论 | 证据 |
|---|---|---|---|
| 太阳/天空/调色板/星空/雾 | 下一帧 _update_lighting 全量重算 | 立即正确 | main.gd:696-708、720-738 |
| 窗灯/路灯/船挂灯/吊灯 | 下一帧按新 windowI/lanternI 重写 glow | 立即正确（跳时本来就会瞬间变化） | main.gd:817-853 |
| 灯塔强度/可见 | 下一帧按新太阳高度重算，可见门瞬时切换 | 立即正确；角度连续不跳变 | main.gd:3108-3125；lighthouse_p5 |
| 炊烟 | _update_smoke_clock 每帧调用；跳时 dt>30s 直接满强度/窗外直接 0 | 立即正确（设计如此） | fx.gd:636-648；tmp2 12:00 ratio=1.0 |
| 夜间环境声 | 门控当帧判定：夜→昼单帧硬停；昼→夜软起 | **夜→昼硬切是问题 C2** | isle_audio.gd:493-515；tmp2 |
| 火焰声 | 当帧硬切（-12dB↔静音） | 立即切换，但硬切（C3） | isle_audio.gd:518-527 |
| 海鸥昼夜/归栖 | 下一帧按 _sun_alt 切昼夜；_update_eco 按 ctx.day 与太阳高度判定 | 立即正确；不补演已错过的归栖动画 | fx.gd:2256-2382；probe_eco7 A8 |
| 帆船-远海等待 | _sync_boat_clock 把 |跳时| 从 _boat_wait_sim 扣除 | 立即正确 | main.gd:2893-2896；boat_p5 |
| 帆船-DOCKED/RESTING | 跳进休息时段→RESTING；RESTING+休息时段→延到次日 08:00；**跳回白天不取消 RESTING** | **回溯到白天长期锁定是问题 C4** | main.gd:2890-2900、2975-2983；tmp2 实测 19.99h |
| 船探照灯 | 下一帧按新太阳高度开关 | 立即正确（硬门 pop 见 T4） | main.gd:2714-2742 |
| 时间源切换（R） | _on_time_mode_requested 重设模式并调 _update_lighting + _sync_boat_clock | 一致 | main.gd:3375-3409 |
| 萤火 | 当前无效果；修复后需随跳时立即重算 | 修复项 | 见 C1 |

## 3. 候选问题清单

### 3.1 已确认（代码/探针可直接证明，6 条）

**C1 萤火完全不发射（双重失效）**
- 现象：夜间没有任何萤火粒子；调色板 fireflyI 每帧算了却无人消费。
- 证据：fx.gd:769 创建时 emitting=false，全仓无任何置 true 的代码；main.gd:854-859 用 ff["mat"] as ShaderMaterial 写 amount_ratio，而 mat 来自 fx.gd:791 → isle_math.gd:214 additive_material 返回 StandardMaterial3D，cast 恒 null，整段永不执行。一次性探针实测：mat class=StandardMaterial3D、cast=null、30 帧后 emitting=false；节点自身 amount_ratio=1.00 但未发射（main 也未写节点属性）。22:00 fireflyI=0.97、12:00=0.0（tmp2）。
- 影响：夜间核心氛围效果完全缺失；palette 的 fireflyI 与 854-859 成死逻辑。现有探针无运行时断言，故长期漏检。
- 最小修复：main.gd:854-859 改为写粒子节点：取 ff.get("node")，node.amount_ratio=clampf(fireflyI,0,1)，node.emitting = fireflyI > 0.05（或按太阳高度门 + 小滞回）。不触碰天文/航线/炊烟窗口/音频总线/夜间效果（只是让效果真正生效），风险低。修复后需补一条运行时断言（emitting 与 amount_ratio）。
- 是否触碰禁止项：否。

**C2 时间跳转时夜间环境声单帧硬切（约 73.1 dB）**
- 现象：按 [ / ] 或时间面板从夜晚跳到白天，Night 环境层瞬间消失（可闻断音/pop）。
- 证据：isle_audio.gd:502-506 停止分支直接 stop()，不经过 env 淡化；淡化只发生在未停止时的 508-515。一次性探针实测：22:00 夜稳态 env=0.9510、db=-6.94、playing=true；一步跳到白天（alt -30→+10，dt=0.05）后同帧 playing=false、env=0.0000、db=-80.00，事件 loop_stop env=0.9510（即从 -6.9dB 直落），单帧约 73.1 dB。自然黎明对照：停点 alt=-0.838、停前 env=0.0154/db=-42.76，停后 -80（此时已不可闻），自然过程平滑。
- 影响：跳时是常用操作（数字键 5=22:00 也很常用），夜声硬切明显；但不影响自然时间流逝时的听感。
- 最小修复：停止分支改为淡出后再 stop：保留播放、把 _loop_env[2]/目标压到 0（可用现有 tau=2.0s），env<0.001 后再 stop，日志保留 loop_stop（记录 fade 时长）。不动音频总线架构。
- 是否触碰禁止项：否（仅门控实现）。

**C3 火焰声在 alt=2.0 处硬启停（-12 dB 一步切）**
- 现象：自然日落时 fire crackle 在太阳高度 2.0° 那一帧从 -12dB 直接静音；跳时同理。
- 证据：main.gd:3698 fireplace_on = _sun_alt < 2.0；isle_audio.gd:518-527 只在布尔变化时 play（FIRE_BASE_DB=-12，isle_audio.gd:75）/stop，无渐变。实测 alt=2.000 单步 stop。自然日落 real 17:44 / sim-day0 17:38 各发生一次。
- 影响：音量 -12dB 的篝火声硬切可闻（尤其近屋时）；每日一次 + 每次跳时。
- 最小修复：改为常驻播放 + 用 lerp 调 volume_db（例如 1.0s 内从 -12 到 -80），或在 stop 前做 0.5–1s 淡出。不动音频总线架构。
- 是否触碰禁止项：否。

**C4 时间回溯到白天后帆船长期锁在 RESTING（约 20 游戏小时）**
- 现象：夜晚船在 RESTING（休息至次日 08:00），此时把时间调回当天 12:00，船仍保持 RESTING，整个白天不出海。
- 证据：main.gd:2890-2900 _sync_boat_clock 只处理「|跳时| 扣远海等待」「DOCKED+休息时段→RESTING」「RESTING+休息时段→延到次日 08:00」，不处理跳回白天；main.gd:2975-2983 RESTING 退出条件只有 _sim_seconds >= _boat_rest_until。tmp2 实测：22:00 从 DOCKED 进 RESTING（rest_until=次日 08:00，剩余 10.00h），_on_time_set(12*3600) 后单帧 state=RESTING，再 12 帧后 rest_until-now=19.99h、dwell=0。
- 影响：用户用数字键/时间面板回到白天后，帆船约 20 游戏小时（默认 600s 日长≈12 真实分钟）不再出海，属长期错位；影响「船鸟联动」的可体验频率。
- 最小修复：在 _sync_boat_clock 增加 elif _boat_state == "RESTING" and not _is_boat_rest_hour(): _boat_state="DOCKED"; _sail_dwell=randf_range(3.0,7.0)（或把 _boat_rest_until clamp 到 now）。休息窗口 18:00–08:00 与航线均不改。
- 是否触碰禁止项：否（不动航线/休息窗定义）。

**C5 炊烟窗口结束单帧切断发射（存量粒子处理需视觉确认）**
- 现象：13:00:00 / 19:00:00 一到，烟雾发射指令与 amount_ratio 在同一帧归零；窗口内进入侧有 1.5s 线性爬坡，离开侧没有收尾。
- 证据：fx.gd:622-649：窗外 _ramp=0.0、_ratio=0.0、_emitting=false。一次性探针实测 12:59:59.95 ratio=1.000/emitting=true → 13:00:00 ratio=0.000/emitting=false；跳 12:00→14:00 同样 ratio=0。
- 影响：发射确实单帧停止；GPUParticles3D 在 amount_ratio=0 时对已存在粒子的处理需实机确认（可能瞬间消失，也可能按 lifetime=7s 自然消散）→ 视觉严重度见 T3。
- 最小修复（若视觉突兀）：窗外时把 ramp 用 1.5s 线性降到 0 再关 emitting（复用现有 SMOKE_RAMP_SECONDS 常量），窗口时刻本身不改。
- 是否触碰禁止项：否（不改窗口时间）。

**C6 死代码 _boat_depart_hours 与休息窗矛盾**
- 现象：var _boat_depart_hours := [6.6, 9.5, 12.5, 15.5, 18.6]（main.gd:164）全仓仅此一处，从未被读取；其中 18.6 落在休息窗 18:00–08:00 内，与 BOAT_REST_START_HOUR=18.0 矛盾，易误导后续维护。
- 证据：grep -rn '_boat_depart_hours' scripts/ 仅 main.gd:164。
- 影响：无运行时行为影响（死代码）；但会让人误以为存在出航时刻表。
- 最小修复：删除该行，或改成注释说明出航由 dwell 随机驱动。
- 是否触碰禁止项：否。

### 3.2 待验证（需窗口截图或实际运行观察，7 条）

**T1 萤火修复后的视觉**：粒子密度/亮度/高度/夜间可见距离，是否会渗进室内或与窗灯光晕冲突。需要 C1 修复后截图对比；本审计只跑了 headless，未做视觉验证。
**T2 夜声硬切的实际听感**：-6.9dB→-80dB 是否被海浪/风声底噪掩盖、是否有明显 pop。建议在 22:00 按 [ 实测；headless 只能证明数字。
**T3 炊烟 13:00/19:00 的视觉尾巴**：amount_ratio 归零后已存在烟团是否立即消失（需窗口截图；GPU 被 Lead 对比占用时不要跑）。
**T4 船探照灯 alt<0.5 硬门的 pop**：门开瞬间 strength=night*fade*moving≈0.092（moving=1 时），可见门 0.04；若船正在可见位置，是「无→9%」单帧跳变。另：该门（0.5°）与灯塔首次可见（约 1.6~2.1°）、夜声起（-0.93°）不同步，默认 144× 下相差约 2–4 真实秒，需实机判断是否可察。
**T5 花瓣全天飘落是否符合设计**：fx.gd:803 emitting=true 无昼夜门；若设计意图是「白天花瓣」，则属漏加门；若设计就是全天，则不算问题。需产品/美术确认。
**T6 灯塔光束跳时强度跳变**：_beam_strength 由 night(_sun_alt) 瞬时重算，跳时从白天到夜晚 0→1 单帧 + visible 切换；自然日落是平滑的（-7..3 smoothstep）。跳时属瞬时重算，是否接受需产品判断。
**T7 阈值边界肉眼可察性综合**：见 2.2 数字。鸟鸣停 2.94°、归栖起 4.0°、灯塔约 1.6~2.1°、船灯 0.5°、夜声 -0.93°、火焰 2.0°、海鸥夜门 -2.0/+2.0。默认流速下相邻事件差 2–6 真实秒，预计不可察；唯一硬门是船探照灯（T4）。

### 3.3 未发现（5 条）

**N1 流星**：项目无流星实现（grep 0 匹配），无「昼夜条件」可审。
**N2 除帆船 RESTING 外的跳时长期错位**：光照/天空/调色板/窗灯/灯塔强度/炊烟/音频门控/星空/海鸥归栖/船探照灯均每帧按 _sim_seconds 或 _sun_alt 重算（2.3 矩阵）；probe_eco7 A8 验证跳深夜不补演、跳回白天先不起飞后恢复；tmp2 跳 22:00→12:00 后各系统同帧正确（除 C2/C3 硬切与 C4）。
**N3 海鸥日/夜阈值与鸟鸣阈值不冲突**：时间顺序为 归栖启动 4.0°（17:29/17:35）→ 鸟鸣停 2.94°（17:34/17:39）→ 夜间飞行门 -2.0°（17:58/18:01）；即先停止鸣叫、再逐步归栖、最后夜间全栖，符合自然顺序；鸟鸣比归栖晚停约 2 真实秒（默认 600s 日长）。清晨对称：日出 -0.84°（06:26）→ 海鸥可起飞 2.0°（06:38）→ 鸟鸣起 2.94°（06:43），也是先有飞行活动再有鸣叫。判定：协调，无需改（若想更细可让鸟鸣随归栖进度衰减，但非必要，且属可选打磨）。
**N4 清晨恢复节奏独立但合理**：海鸥 PERCH 错峰 rand(2,14)s（fx.gd:2286）、鸟鸣 2.94°、炊烟 11:00、帆船 08:00 是不同系统的独立节奏，不是错误；没有「同一事件必须同时发生」的设计约束。
**N5 音频总线架构**：三层环境循环/夜间层/鸟鸣/火焰/音效各在独立 bus，probe_audio6 232/0、probe_audio_p5 85/0，未发现回归；C2/C3 属门控实现问题，不需要动总线架构。

## 4. 对 Lead 五个重点问题的判断

**(a) 海鸥白天/黄昏飞行与鸟鸣太阳高度阈值是否协调**：协调。鸟鸣有效阈值 alt≈2.94°（day>0.55 紧约束，isle_audio.gd:533），黄昏归栖启动 4.0°（fx.gd:1483/2340），夜间飞行转降落门 -2.0°（fx.gd:2263-2270）。黄昏顺序是「归栖开始→鸟鸣停止→全部落栖→夜间稳定」，清晨是「日出→可起飞→鸟鸣恢复」；三者在自然时间线上错开 2–10 真实秒，不冲突。Lead 正在补的黄昏归栖修复保留了 -2/+2 滞回与每日一次语义，probe_eco7 123 断言全过；未发现需要强改的阈值。建议：若追求更自然，可让鸟鸣在 4.0°→2.0° 之间随归栖进度线性衰减（与 birdsAlpha 视觉节奏一致），但这是打磨项，不建议本轮改。

**(b) 夜间环境音启停是否突变**：自然时间流逝下不突变（双门限 + tau=2.0s 淡入；黎明停点 -42.76dB 已不可闻，播放期单帧最大 0.01dB）。**突变只发生在时间跳转**：夜→昼单帧 -6.94dB→-80dB（C2），这是已确认问题，建议按 C2 修。双门限滞回带 0.10°（alt -0.94..-0.84），正常太阳移动约 1 分钟游戏时间穿过，不抖；仅当 scrubber 在带内来回拖时才可能反复启停（低风险，可不为它加逻辑）。

**(c) 时间跳转后系统是否保持旧状态**：大多数系统每帧重算，跳时立即正确（2.3 矩阵）。**唯一长期错位是帆船 RESTING（C4）**：跳到白天后船约 20 游戏小时不出海。其余「旧状态」都是本帧硬切（C2 夜声、C3 火声、灯塔/探照灯/炊烟瞬时变化），不算长期错位。

**(d) 清晨恢复时间是否与其他系统脱节**：不是错误。海鸥 PERCH 2–14s 错峰是动画错峰；鸟鸣阈值 2.94° 与日出 -0.84° 相差约 17 游戏分（默认流速约 7 真实秒）属正常；炊烟 11:00、船 08:00 是各自活动时间，不要求与日出同步。仅提示：帆船 08:00 恢复与海鸥清晨活动有约 1–2 小时游戏时差，这是设定而非缺陷。

**(e) 窗灯/灯塔/萤火与太阳高度阈值边界差异是否肉眼可察**：数字见 2.2。窗灯无开关阈值（连续调光，正午 glow≈0.173、深夜≈0.894），不存在硬边；灯塔首次可见约 alt 1.6~2.1°（由 night*(0.22+lanternI*1.05)>0.035 解得，li 随调色板变化）；萤火当前不发射（C1），按 palette 设计 fireflyI 约在 -0.8°~-2.7° 间爬升；海鸥夜门 -2/+2；船探照灯 0.5° 硬门。默认 144× 下这些边界差 2–6 真实秒，肉眼基本不可察；**唯一可能可察的是船探照灯硬门 pop（T4）**，若要修，把 on 判断从硬门改为 strength>0 的平滑门即可（低优先级）。

## 5. 建议 Lead 优先修复 Top3

1. **C1 萤火完全不发射** — main.gd:854-859 + fx.gd:769。夜间核心效果 0 存在感，且现有探针无断言；改为写节点 emitting/amount_ratio 即可，改动小、不动禁止项，收益最高。
2. **C2 夜声跳时硬切 73 dB** — isle_audio.gd:502-506。跳时（尤其数字键 5→夜/回白天）体验硬伤；加淡出后再 stop，用现有 tau=2.0s，不动总线架构。
3. **C4 帆船回溯 RESTING 锁死约 20 游戏小时** — main.gd:2890-2900 与 2975-2983。跳回白天后看不到船、也丢失船鸟联动机会，属长期错位；在 _sync_boat_clock 增加「不在休息时段则提前结束休息」即可，不动航线与休息窗定义。
4. （可选）**C3 火焰声 alt=2.0 硬切 -12dB** — isle_audio.gd:518-527；与 C2 同一类修复手法，可顺手一起做。

## 6. 证据文件（均在 D:/休闲小岛幻境/开发产物/p7/audit/）

- 一次性探针 A（baseline_wt，未改动系统）：eco_audit_probe.log / eco_audit_probe_stdout.log —— 萤火失效三重证据、炊烟双窗、夜层双门限与自然黎明/跳时序列。
- 一次性探针 tmp2（baseline_wt，跑后删除）：eco_audit_jump_probe.log —— 天文锚点时刻、22:00 夜间快照、22:00→12:00 跳时快照、帆船 RESTING 19.99h。
- 当前代码回归：regress_probe_audio6.log、regress_probe_audio_p5.log、regress_probe_smoke6.log、regress_probe_bird6.log、regress_probe_lighthouse_p5.log、regress_probe_boat_p5.log、regress_probe_eco7.log（全部 PASS）。
- probe_fx_p4：regress_probe_fx_p4.log（64/1，唯一失败为过期断言）；baseline_fx_p4.log（未修改 baseline 相同数值失败）→ 判定非 P7 回归。

## 7. 复现方式（headless）

    D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe --headless --path D:/休闲小岛幻境/游戏工程 --script res://tools/probe_eco7.gd
    D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe --headless --path D:/休闲小岛幻境/游戏工程 --script res://tools/probe_audio6.gd
    # 其余探针同理；本审计未修改任何现有源文件。

> 边界说明：本报告基于 2026-10-21 01:00 左右落盘快照；Lead 仍在改 scripts/main.gd、scripts/fx.gd、scripts/world.gd，若继续落盘，行号可能偏移，请以 blob hash 与函数名重新对齐。

## 附录 A：已确认问题 × 修复动作 × 禁止项对照

| 问题 | 建议改动（文件:行号） | 改动类型 | 禁止项检查 |
|------|----------------------|----------|------------|
| C1 萤火不发射 | main.gd:854-859（改读 ff["node"] 写 amount_ratio/emitting）；fx.gd:769 保持由 main 控制 | 逻辑修复（让效果生效） | 不动天文/航线/炊烟窗口/音频总线；不删夜间效果（相反是恢复） |
| C2 夜声跳时硬切 | isle_audio.gd:502-506 停止分支加淡出 | 门控收尾 | 不动音频总线架构，仅停止分支 |
| C3 火声硬切 | isle_audio.gd:518-527（音量 lerp） | 音量平滑 | 同上 |
| C4 帆船回溯锁死 | main.gd:2890-2900（_sync_boat_clock 增加白天提前结束休息） | 状态重校准 | 不动航线、不动休息窗 18:00–08:00 |
| C5 炊烟收尾 | fx.gd:641-648（窗外 ramp 1.5s 降到 0 再关 emitting） | 收尾平滑 | 不改窗口时间 11:00–13:00 / 17:00–19:00 |
| C6 死代码 | main.gd:164 删除或改注释 | 清理 | 无 |

## 附录 B：审计边界与限制

- 全部验证为 headless；未开窗口、未截图、未跑 --perf（GPU 由 baseline-verify 独占），因此视觉/听感类结论归入待验证。
- 主仓库 scripts/main.gd、scripts/fx.gd、scripts/world.gd 为 Lead 工作区未提交改动；行号基于第 0 节列出的 blob hash 与 mtime。
- 一次性探针在 baseline_wt/tools/ 下创建并已删除（_eco_audit_tmp.gd、_eco_audit_tmp2.gd 及 .uid，脚本内 grep 计数为 0）；未改动主仓库任何现有源文件。
- baseline 对照仅用于 probe_fx_p4 的断言时效判定（同一探针在未修改 baseline 上相同数值失败）。
- 未运行 --selftest、未做 GPU 相关验证；探针日志内无害噪音（2 行 user:// 日志打开失败、root certificate store 失败、退出 ObjectDB/RID leak）不影响结论。

## 附录 C：headless 复现命令与参数

- 探针命令统一为：引擎 console.exe --headless --path D:/休闲小岛幻境/游戏工程 --script res://tools/<probe>.gd
- 本审计用到的现有探针：probe_audio6、probe_audio_p5、probe_smoke6、probe_bird6、probe_lighthouse_p5、probe_boat_p5、probe_eco7、probe_astro6、probe_time_p5、probe_fx_p4。
- 一次性探针 A：测萤火 emitting/材质类型、炊烟 11:00/13:00/17:00/19:00 边界、夜层双门限与自然黎明/跳时序列（日志 eco_audit_probe.log）。
- 一次性探针 tmp2：测 sim-day0 与 real-2026-10-21 的太阳高度穿越时刻、22:00 夜间快照、22:00→12:00 跳时快照、帆船 RESTING 剩余时间（日志 eco_audit_jump_probe.log）。
- 判据：exit 0 且探针自身的 PASS/FAIL 汇总为 fail=0；probe_fx_p4 的单条失败已按 baseline 对照归类为过期断言。
