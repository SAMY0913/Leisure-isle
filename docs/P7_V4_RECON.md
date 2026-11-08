# P7-V4 工程侦察报告（task-2 / 只读侦察）

> 本报告为 P7-V4 立项前的工程侦察（recon），**未修改任何产品代码/场景/资源**。
> 唯一新增文件：探针 tools/probe_recon_p7v4.gd（可随时删除）；本报告路径 游戏工程/docs/P7_V4_RECON.md。
> 采集环境：Godot 4.7.2 stable / Forward+ / D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe；
> 工程 D:/休闲小岛幻境/游戏工程（分支 p7-v4-islander，HEAD 1b59e59 = P7-V3.2 冻结）。
> 除标注「计算值」外，所有坐标/高度均为 headless 探针在真实场景树里实测。

## 0. 结论速览（先看这 10 条）

1. **没有任何可行走角色/碰撞/导航**：全场景树 StaticBody3D 仅 2 个、CollisionShape3D 仅 2 个；CharacterBody3D=0、RigidBody3D=0、Area3D=0、CollisionPolygon3D=0、NavigationRegion3D=0、NavigationAgent3D=0、NavigationObstacle3D=0。地形/地板/楼梯全部只有视觉网格。
2. 这 2 个碰撞体是**点击交互盒**（collision_layer=2、collision_mask=0），不是可站立面：DoorHit（世界 (1.805, 9.596, 2.648)，2.0×2.6×1.4）与 ChimneyHit（世界 (-2.070, 13.046, -2.434)，1.1×2.9×1.1），见 cottage.gd:106-107 与 isle_math.gd:452-464。
3. 因此对任务的直接回答：**走到「餐桌座位/床边/二楼床边/门口/观景点」当前在引擎里不成立**——不是被家具挡住，而是根本没有碰撞面、没有角色、没有导航。几何上这些位置彼此是连通的（见 §3.5）：门洞净 1.14×1.94 m、1F 净高 2.42 m、楼梯 16 级×0.16375 m 且最小净高 2.14775 m、阁楼站立区 |x|≤2.10 m。
4. 小屋世界变换：原点 (0.800, 7.9456, -0.600)，rotation.y=0.3000 rad（17.19°）；室内地面世界 y=8.4956，门廊台面 8.3656，阁楼地面 11.1156，屋脊 14.1456（§3.1）。
5. 楼梯几何真实且合理：rise 0.16375 / tread 0.26 / 宽 0.85 / 16 级 / 平台 1.86 / 顶层 3.17；但 Staircase 节点下**没有任何 CollisionShape3D**，只有 MeshInstance（cottage.gd:1332-1486）。
6. 家具 38 件（1F 23 + 阁楼 15），全部由 cottage.gd:1764-1786 与 1620-1638 调 IsleHouseProps.build(parent, kind, 局部坐标, 局部 yaw) 摆放；世界 yaw = 局部 yaw + 0.3000 rad，节点 transform 是唯一坐标来源（无额外 meta 位姿）。（§4）
7. 时间核心是 **绝对秒**（≈Unix 秒 + 28800 s 时区偏移，含日期）；推进速率 = 86400/_day_length（默认 600 s/游戏日 ⇒ 144 模拟秒/现实秒），real 模式 1:1；暂停只有 _paused，只冻结 _advance_sim，不冻结灯光/道具动画。（§1）
8. 时间跳转入口齐全：[ ] ±600 s、数字键 1..5 跳当天 05:36/12:00/17:24/18:36/22:00、HUD 时间轴拖动/面板、perf/shots 专用 set；全部在 real 模式被拒绝。（§1.5）
9. 世界方面：主路从门口到码头折线 4 段地形最大坡度 7.92° / 26.05° / 44.61° / 50.74°；码头甲板固定世界 y=0.72，但岸端地形 1.857 m ⇒ 码头靠岸约 1.9 m 与 3 块石踏步被沙埋 0.16–1.14 m（§8.3，P7-V4 需修）。
10. 猫/材质/批量/性能工具链可直接复用：猫是纯程序化（无 AnimationPlayer），isle_math.toon_material + outline 0.02 + isle_batch.merge_static 的 no_batch 契约完整；--perf/--shots/--selftest 与 [PERF]/[SHOT]/[TEST]/[SCALE] 日志格式稳定（§5–§7）。

---

## 1. 时间系统（权威接口）

### 1.1 变量与量纲

| 变量 | 位置 | 语义（精确） |
| --- | --- | --- |
| _sim_seconds | main.gd:42 | **绝对秒**：模拟时间戳，单位秒，包含日期；sim 模式从 62280.0 起算（17:18），real 模式等于 系统 Unix 秒 + IsleAstro.TZ_SECONDS（+28800 s）；小数保留 |
| _day_length | main.gd:43 | 一个游戏日（00:00→次日 00:00）对应的**现实秒数**；默认 600.0（isle_settings.gd:34/78），档位 [60,300,600,900,1200,1500,1800,2400,2700,3600]（isle_settings.gd:33） |
| _realtime | main.gd:44 | real 模式缓存布尔；真实来源是 _time_source 字符串（'sim'|'real'） |
| _events | main.gd:45 | IsleAstro.day_events(_sim_seconds) 结果，跨天时重算 |
| _sim_delta | main.gd:188 | 上一帧推进的模拟秒数（灯塔转速/远海等待共用） |
| _sim_rate | main.gd:189 | 上一帧「模拟秒/现实秒」；sim=86400/_day_length，real=1.0 |
| _time_jump | main.gd:190 | 手动调时/时间轴跳转累计秒数，用于对齐小船远海等待（main.gd:3198-3214 _sync_boat_clock） |

**注意**：工程里没有 _time_rate 这个变量；任务描述中的 _time_rate 对应 main.gd:189 的 _sim_rate，以及 main.gd:3405-3408 的 _time_flow_scale()（real→1.0；sim→480.0/maxf(_day_length,1)）。

### 1.2 初始化与推进（精确代码）

- `_init_time()` main.gd:315-324：先取 `_abs_unix = Time.get_unix_time_from_system()`；real 模式 `_sim_seconds = _abs_unix + IsleAstro.TZ_SECONDS`；否则 `_sim_seconds = 17.0*3600.0 + 18.0*60.0 = 62280.0`（注释「参考项目的氛围起点：傍晚 17:18」）；随后 `_events = IsleAstro.day_events(_sim_seconds)`。
- `_advance_sim(delta)` main.gd:644-659：
  - before = fposmod(_sim_seconds, 86400.0)；sim_before = _sim_seconds；
  - real：_abs_unix = Time.get_unix_time_from_system()；_sim_seconds = _abs_unix + TZ_SECONDS；_sim_rate = 1.0；
  - sim：rate = 86400.0 / maxf(_day_length, 1.0)；_sim_seconds += delta*rate；_sim_rate = rate；
  - after = fposmod(_sim_seconds,86400)；_sim_delta = _sim_seconds - sim_before；若 after < before（跨天）→ _events = IsleAstro.day_events(_sim_seconds)。
- `_now_sim_seconds()` main.gd:661-662 返回 IsleAstro.now_local_seconds()，即**现实时钟**（isle_astro.gd:660-661 = unix + TZ_SECONDS），**不是** _sim_seconds；任何「取当前模拟时刻」的代码都不得调用它。
- 时钟消费：`_update_lighting()`（main.gd:753）每帧读 _sim_seconds/_events/_pal；灯塔光束 `_update_lighthouse_beam`（3410-3462）在 sim 模式用 `_sim_delta * TAU / (20.0*86400.0/480.0)`（旋转周期 20 s 对应参考日长 480 s，main.gd:17-18），real 模式用 `delta*TAU/20.0`（3414-3420 注释+代码）。

### 1.3 暂停 / 菜单状态机

- 状态：`enum Mode { MENU, PLAYING }` main.gd:32；_mode:33、_paused:34、_started:35。
- 暂停唯一开关 `_paused`：在 `_tick` 中只影响推进条件 `if _mode == Mode.PLAYING and (not _paused or _time_source == "real"): _advance_sim(delta)`（main.gd:674-681）。
  - 空格键 main.gd:1331-1336：real 模式直接 toast「现实时间模式：时间随现实时钟前进」并 return；否则 `_paused = not _paused`，toast「时间暂停/时间继续」。
  - 暂停时 **不冻结** 相机/灯光/道具：_update_lighting（689）内部 :938 调 `_update_props(get_process_delta_time())`，秋千（_frame_t 正弦）、水花、船仍推进；唯一受 _paused 影响的船逻辑是 DOCKED 停留窗口（约 3198-3232 区域）。HUD 相位标签在 _phase_update（main.gd:1002-1006）：_paused → 「已暂停 / PAUSE」。
- 菜单：进入游玩 `_enter_playing()` main.gd:1057-1062（_started=true、_mode=PLAYING、_paused=false、HUD 显示）；ESC→`_open_menu()` main.gd:1064-1077（_mode=MENU、_menu.open(true)、HUD 隐藏、_movie_theta=_theta、混合到 _play_pose()）；菜单里「继续观景」→ `_on_menu_start(true)` main.gd:1051-1055（_menu.close(cb _enter_playing) + _start_blend("to_game", _movie_pose())）；菜单内再按 ESC 复用同一路径（main.gd:1282-1285）。
  - 混合：BLEND_DUR = 2.4 s（main.gd:74），`_start_blend` main.gd:733-737；菜单待机镜头 `_movie_theta += delta*0.035`、`_movie_theta = lerp_angle(...)`（main.gd:682-686）。菜单期间 sim 不推进（_mode != PLAYING），但灯光/道具仍按真实帧推进。
- 相关菜单/HUD 接口：menu.gd open(returning) 1003 / close(on_done) 1038 / instant_finish 1104 / open_settings 804 / close_settings 819 / open_timezone_picker 727；hud.gd _time_open:61、toggle_time_panel:615、set_hud_visible:769（781-782 会关时间面板）、_on_time_mode_pressed:566、_on_time_scrubbed:601。

### 1.4 时间跳转入口（全部落点）

| 入口 | 位置 | 行为 |
| --- | --- | --- |
| `[` 键 | main.gd:1353-1360 | real 拒绝（toast「现实时间模式不可调时」）；否则 _time_jump-=600、_sim_seconds-=600、_events=day_events(...)、_sync_boat_clock() |
| `]` 键 | main.gd:1361-1368 | 同上 +600 s |
| 数字键 1..5 | main.gd:1369-1380 | 目标小时 [5.6,12.0,17.4,18.6,22.0]；today=_sim_seconds-fposmod(_sim_seconds,86400)；_time_jump += today+target*60-_sim_seconds；_sim_seconds=today+target*60；toast 跳至 清晨/正午/黄金时刻/日落/夜晚 |
| HUD 时间轴拖动 | hud.gd:601 _on_time_scrubbed(sec_of_day) → main.gd:2821-2830 _on_time_set | day_start = _sim_seconds - fposmod(_sim_seconds,86400)；_sim_seconds = day_start + clampf(sec_of_day,0,86399)；_time_jump += 差额；重算 _events + _sync_boat_clock |
| HUD 时间面板 ± 按钮 | main.gd:2811-2818 _on_time_adjust(seconds_delta) | 同 ±600 逻辑（按参数） |
| 面板开合 | T 键 main.gd:1347-1348 → hud.gd:615 toggle_time_panel | 无时间变更 |
| 自动化工具 | main.gd:2567-2570 _set_time_of_day(minutes) / main.gd:4294 _set_p7_sim_time(seconds) | perf/shots 专用，直接改 _sim_seconds 并重算事件 |

所有跳转都会重算 `_events = IsleAstro.day_events(_sim_seconds)` 并调用 `_sync_boat_clock()`（main.gd:3198-3214：消费 _time_jump，缩短船只离屏等待/提前解锁 RESTING）。

### 1.5 real 模式

- 切换：R 键 main.gd:1337-1338 → `_toggle_time_source()` main.gd:3694-3695 → `_on_time_mode_requested` main.gd:3699-3732：写 settings、_time_source/_realtime；real→`_sim_seconds = _abs_unix + TZ`；sim→`_paused=false`；_sim_delta=0；立刻 _update_lighting + _sync_boat_clock；`_set_time_source(src,tz)` main.gd:3734-3744。
- real 语义：时间只由系统时钟驱动（main.gd:647-651）；暂停无效（main.gd:680、1331-1336）；所有调时被拒绝（1354-1356/1362-1364/1370-1372）；_day_length 不生效；灯塔用真实 delta（3414-3420）；`_time_flow_scale()` 返回 1.0（3405-3408）。

### 1.6 天文/时间 API（isle_astro.gd）

- TZ_MINUTES=480、TZ_SECONDS=480*60（isle_astro.gd:15-16）；`jd_from_local(local_seconds) = (local_seconds-TZ_SECONDS)/86400.0 + 2440587.5`（159-160）。
- `day_events(local_seconds)` 433 起，返回字典 551-574：sunrise、sunset、sunrise_az、sunset_az、noon_alt、noon_az、noon_time、day_length（初值 -1.0，日出日落都有效时 = sunset-sunrise）、moonrise、moonset、moonrise_az、moonset_az、noon_illum、civil_dawn、civil_dusk、nautical_dawn、nautical_dusk、astronomical_dawn、astronomical_dusk。时刻单位 = **当天分钟数**。
- `local_datetime(local_seconds)` 657-658 = Time.get_datetime_dict_from_unix_time(int(floor(local_seconds)))；`clock_text(minute_of_day)` 663-667 = fposmod 1440 → HH:MM；`format_minutes` 669+。
- 探针实测（headless，两帧后）：_sim_seconds=1792620060.241、_day_length=600.0、_sim_rate=1.0000、_sim_delta=0.0、_time_source=sim、_paused=true、SceneTree.paused=false。_sim_seconds 的绝对值来自本机 user://settings.cfg 里 time_source 曾为 real（_init_time 时读取），可作为「绝对时间含日期」的实证。

---

## 2. 物理 / 导航 / 角色现状（连通性事实基础）

### 2.1 全树盘点（headless，node_total=1464）

| 类型 | 数量 |
| --- | --- |
| StaticBody3D | 2 |
| CollisionShape3D | 2 |
| CharacterBody3D | 0 |
| RigidBody3D | 0 |
| Area3D | 0 |
| CollisionPolygon3D | 0 |
| NavigationRegion3D | 0 |
| NavigationAgent3D | 0 |
| NavigationObstacle3D | 0 |
| MeshInstance3D | 863 |
| MultiMeshInstance3D | 43 |

全工程 grep（scripts/、tools/、*.tscn、project.godot）：NavigationRegion3D / NavigationMesh / NavigationAgent3D / NavigationObstacle 命中 **0**；CharacterBody3D / move_and_slide 命中 **0**；无玩家/头像节点。isle.tscn 仅 227 B（根 Node3D + main.gd）。

### 2.2 仅有的 2 个碰撞体（点击用）

isle_math.gd:452-464 `hitbox(parent,name,pos,size)`：StaticBody3D + collision_layer=2、collision_mask=0 + BoxShape3D。

| 节点 | 创建 | 世界位置 | 尺寸 (x,y,z) | 层/掩码 |
| --- | --- | --- | --- | --- |
| DoorHit | cottage.gd:106 | (1.805, 9.596, 2.648) | (2.0, 2.6, 1.4) | layer 2 / mask 0 |
| ChimneyHit | cottage.gd:107 | (-2.070, 13.046, -2.434) | (1.1, 2.9, 1.1) | layer 2 / mask 0 |

交互链路：main.gd:1391-1417 `_click_at` 用 ray collision_mask=2；命中 DoorHit → `_toggle_door` main.gd:1419-1429（door_pivot rotation.y tween 到 -1.85 rad 开 / 0.0 关，0.95 s，TRANS_CUBIC EASE_IN_OUT，toast「小屋的门开了 / 小屋的门轻轻合上」）；命中 ChimneyHit → toast；否则在 y=0 平面生成涟漪/水花（距离 < 420）。

### 2.3 自由相机不是角色

isle_flycam.gd：RefCounted 纯逻辑类，自身不拥有 Camera3D，只写现有相机。参数：DEFAULT_SPEED_REGULAR 12.48 m/s、BOOST 24.96、VERTICAL 6.6、LOOK 0.0022 rad/px、RADIUS 130.0、MIN_Y 1.2、MAX_Y 130.0、TERRAIN_CLEARANCE 0.8、PITCH_LIMIT 1.45 rad、EXIT_BLEND 0.6 s（42-64）；WASD + Space/Ctrl + Shift，`_apply_bounds`（379）只用 terrain_height 限制相机 Y。**它不产生碰撞、不探测家具**。

### 2.4 由此得到的连通性结论

- 引擎内不存在任何可站立碰撞面：地形、1F 地板、台阶、楼梯踏步、阁楼地板都只是 MeshInstance3D/MultiMeshInstance3D；没有任何 floor/step 碰撞。
- 因而「角色走到 X」的判定**当前一律为否**（不是几何阻塞，而是系统缺失）。P7-V4 若要做可走岛民，最小闭环是：CharacterBody3D（胶囊，按 isle_scale_spec 人形 1.50 m/眼高 1.38 m）+ 地形/地板/踏步碰撞（ConcavePolygonShape3D 或简化 StaticBody）+ 楼梯 step_height ≥ 0.16375 m + NavigationRegion3D（或 AStar 网格）。
- 几何侧已具备可走条件（§3.5 给逐点数据），无需改房屋主体尺寸。

---

## 3. 小屋几何与可通行性（cottage.gd）

**风格提醒**：cottage.gd 用 4 空格缩进（其余 .gd 为 tab），改动时保持一致。

### 3.1 世界变换与层高

- 建造入口 `build()` cottage.gd:76-174；根节点 Cottage：位置 **(0.800, 7.9456, -0.600)**、rotation.y = **0.3000 rad（17.19°）**。来源：isle_math.gd:6-8 HOUSE_X=0.8 / HOUSE_Z=-0.6 / HOUSE_YAW=0.30；house_ground_y() = terrain_height(0.8, -0.6) = 7.9456（isle_math.gd:119）。
- 局部坐标约定：局部 **+Z = 正面/门**，屋脊沿局部 Z；**fy = 0.55 是室内地板局部高度**；世界 = 根变换 × 局部。

| 层位（局部） | 世界 Y | 出处 |
| --- | --- | --- |
| 基座底面 -0.75 | 7.1956 | _plinth 372-417（基座体高 1.14，中心 y=-0.18） |
| 门廊台面 deck_top 0.42 | 8.3656 | _porch_steps 422-468 |
| 室内地板 fy 0.55 | 8.4956 | _context 267-367 |
| 1F 顶棚 in_top 2.97 | 10.9156 | _context；1F 净高 = 2.97-0.55 = **2.42 m** |
| 门洞顶 2.49 | 10.4356 | _door 619-668（净高 1.94） |
| 阁楼结构板 3.005–3.17 | 10.9506–11.1156 | _attic_interior 1491-1640（板厚 0.20） |
| 阁楼地面 3.17 | 11.1156 | _context / 楼梯 meta |
| 屋面底（檐口）3.73 | 11.6756 | _context roof_base |
| 屋脊 6.20 | 14.1456 | _context；烟囱顶 6.55 → 14.4956 |

### 3.2 墙 / 门 / 门廊（精确尺寸）

- 外轮廓 7.6 (X) × 6.2 (Z)，墙厚 0.30（_context 267-367；isle_math.gd:13-25）；墙体中心：前 z=+2.95、后 z=-2.95、侧 x=±3.65（_walls 473-535）⇒ 外皮 z=+3.10，内皮 z=+2.80。
- **门洞净空 1.14 m（x -0.57..+0.57）× 1.94 m（y 0.55..2.49）**，拱肩线 spring_y=1.97，内拱 R0.52 / 外拱 R0.66，扇形窗 R0.50，把手高 0.95 m（世界 9.4456），门扇 1.00×1.40，门槛石顶面 = 地板面 0.55（0.30 深墙洞）。meta：root.door_clear 660-666、root.door_opening=(1.14,1.94,0.30) 659、DoorPivot 641 带 meta **no_batch=true**。
- 门轴局部 (-0.50, 0.55, 3.04)（在门洞内偏 -X 侧）；开门 tween rotation.y = **-1.85 rad**，门扇向**门廊外侧**摆开：开门后门尖局部 (-0.776, 0.55, 4.001)、世界 (1.242, 8.496, 3.452)；关门门尖局部 (0.500, 0.55, 3.040)。门廊前沿局部 z=4.70 ⇒ 开门尖距廊边 0.699 m，不撞廊沿。
- 门洞中心世界坐标（门洞几何中心）：**(1.716, 9.466, 2.362)**；门前小径端点（isle_math.door_approach，岛面 y）: **(2.425, 7.9456, 4.654)**（= 根 + front×5.50，front=(0.2955,0,0.9553)）。
- 门廊：台面 0.42（世界 8.3656），3 级台阶 rise 0.14 / run 0.30，踏面宽 2.60/2.40/2.20，顶面局部 0.28/0.14/0.00（z 中心 4.85/5.15/5.45），最下级底面局部 -0.20268（世界 7.7429 = 当地地形）。探针：三级踏面高出地形 0.474 / 0.340 / 0.212 m；廊栏顶局部 y=deck_top+0.80=1.22（世界 9.5856）。

### 3.3 楼梯（cottage.gd:1332-1486）

节点 Staircase；root meta stairs（risers/rise/tread/width/handrail_h/land_top/attic_floor/flight_a_len/flight_b_len/hole_r1/hole_r2/landing_center/landing_size/headroom_min/treads[16]）。

| 参数 | 值 |
| --- | --- |
| 级数 | 16（8 + 平台 + 8，实际 15 级踏步 + 阁楼地板作为第 16 级顶面） |
| 踏步高 rise | **0.16375 m** |
| 踏步深 tread | **0.26 m**（踏板实体 0.31 深，含 0.05 前缘鼻） |
| 梯宽 width | **0.85 m** |
| 平台 | 0.85×0.85×0.10，顶面局部 **1.860**（第 8 级），中心 (3.065, 1.860, -2.365) |
| 顶层 | 局部 **3.17** = 阁楼地面，位置 (0.82, 3.17, -2.365) |
| 最小净高 headroom_min | **2.14775 m**（逐踏步对屋面/阁楼板取最小，≥ spec 1.95） |
| 扶手高 | 0.85（内扶手 x=2.67，meta handrail_top_offset=0.85） |
| 楼梯井 | hole_r1 = Rect2(2.64, -2.79, 0.85, 2.67)（A 段上方）；hole_r2 = Rect2(0.82, -2.79, 1.82, 0.85)（B 段上方） |
| 梯段长度 | flight_a_len = flight_b_len = 2.24243171579426 m |

几何序列（局部，x/y/z）：floor 0.55 → 1 级顶 0.71375 → … → 7 级顶 1.70125 → 平台 1.860（z=-2.365）→ 9 级顶 2.02375 → … → 15 级顶 3.00625（x=0.82）→ 16 级顶 3.17 = 阁楼地面。A 段沿 **-Z**（z 从 -0.12 到 -1.94，x 3.065 中心），B 段沿 **-X**（x 从 2.64 到 0.82，z=-2.365 中心）。踏步实体：A 段 (0.85,0.06,0.31)，B 段 (0.31,0.06,0.85)；立板厚 0.035；斜梁 (0.06,0.32,2.242)，A 段绕 X 转 -a_ang，B 段绕 Z 转 -b_ang；内外两段均有栏杆柱/扶手/将军柱。

**楼梯可通行性判定**：几何上可通行——rise 0.16375 m < 常见 step_height 0.25–0.30 m；tread 0.26 m；净宽 0.85 m > 肩宽 0.36 m（isle_scale_spec.gd:30）；最小净高 2.14775 m > 1.50 m 人高。**物理上不可通行**——Staircase 下只有 MeshInstance3D，没有 StaticBody3D/CollisionShape3D，也没有斜坡代理。

### 3.4 阁楼（_attic_interior 1491-1640）

- 阁楼地面 3.17（世界 11.1156）；结构板厚 0.20；围绕 L 形楼梯井由 3 块楼板组成（局部）：A x -3.50..0.82 & z -2.80..2.80；B x 0.82..2.64 & z -1.94..2.80；C x 2.64..3.50 & z -0.12..2.80。
- 井口收边条 trim_y=3.20：4 条（0.08×0.06×0.85 / 1.82×0.06×0.08 / 0.08×0.06×2.67 / 0.86×0.06×0.08）；护栏高 rh=0.90 沿井口三边：(0.82,-1.94)→(2.64,-1.94)、(2.64,-1.94)→(2.64,-0.12)、(2.64,-0.12)→(3.49,-0.12)；4 根角柱 0.09×1.02。**楼梯到达边（x=0.82，z=-2.365）无护栏**，即从第 16 级直接踏上阁楼 A 区。
- 屋面下皮（局部）：`y = 6.20 - 0.6494*|x| - 0.167`（0.6494 = tan(33.02°)，0.167 = 屋面厚）。站立净高（相对阁楼地面 3.17）：`h(x) = 2.863 - 0.6494*|x|`。

| \|x\| (m) | 0 | 1.0 | 2.0 | 2.10 | 2.31 | 2.95 |
| --- | --- | --- | --- | --- | --- | --- |
| 净高 (m) | 2.863 | 2.214 | 1.564 | 1.50 | 1.363 | 0.947 |

⇒ **站立（≥1.50 m）可用区 |x| ≤ 2.10 m**；2.10–2.95 m 为屈身区；床（顶面局部 4.040）在 |x|=2.0 处上方余量 0.694 m。

### 3.5 逐点连通性回答（任务关键问题）

先给结论表（几何，按 1.50 m 人形 + 肩宽 0.36 m 计；均无碰撞，见 §2）：

| 目标 | 几何可达？ | 关键净空/证据 |
| --- | --- | --- |
| 门口（进出） | 是 | 门洞 1.14×1.94 m，门槛与室内外高差 0.13 m（室内 8.4956 / 廊面 8.3656）；开门摆向廊外，门尖距廊沿 0.699 m |
| 门廊→室外地面 | 是 | 3 级×0.14 m，最后一级顶面比地形高 0.212 m（可一步下） |
| 餐桌座位（4 把） | 是 | 椅子座面 0.40 m、桌面 0.65 m；桌下净空 0.615 m；椅子前沿各嵌入桌沿 0.10 m；座位世界坐标见 §4.3 |
| 1F 各处（沙发/扶手椅/书桌） | 是 | 1F 净高 2.42 m；主通道 1.3–2.6 m；最窄家具间隙 0.325 m（扶手椅↔茶几）、0.36 m（书桌椅↔茶几），需绕行但不阻碍主通道 |
| 楼梯上下 | 是（几何）/ 否（物理） | 16×0.16375 / 0.26 / 0.85；最小净高 2.14775 |
| 二楼床边 | 是（几何） | 到达：第 16 级 (0.82, 3.17, -2.365) → A 区地板 x<0.82；床边站立点 |x|≈0.7–2.0 ⇒ 净高 1.56–2.34 m；床侧通道：衣柜前沿 z=-2.24 与床头柜后沿 z=-1.80 之间 **0.44 m**（唯一窄点） |
| 阁楼书桌/阅读椅 | 是 | 书桌 (0,0,2.44) 与椅 (0,0,1.95) 在 A 区中心，|x|≤0.6 ⇒ 净高 ≥2.47 m |
| 观景点（屋外） | 是（相机/将来角色） | 见 §8.4 坐标表 |

**1F 关键净宽（计算值：DIMS×yaw 的轴对齐包围盒，局部坐标）**：

| 通道 | 净宽 | 计算依据 |
| --- | --- | --- |
| 门洞中线 → 餐椅背 | ≥1.3 m | 沙发右缘 x=-1.35 至餐椅左缘 x=1.24 = 2.59 m；门厅段无阻挡 |
| 沙发（前沿 z=1.82）↔ 茶几（后沿 z=1.37） | 0.45 m | 局部 AABB |
| 扶手椅（右缘 x=-1.30）↔ 茶几（左缘 x=-1.625） | **0.325 m（最窄）** | 扶手椅 0.72×0.76 @yaw -90° ⇒ x -1.30..-0.54, z 0.76..1.48 |
| 书桌椅（后沿 z=0.51）↔ 茶几（前沿 z=0.87） | 0.36 m | 椅 0.42×0.44 @yaw -90° ⇒ x -2.84..-2.40 |
| 门厅东侧 → 楼梯口 | ≥1.3 m | 鞋凳 x≤1.55、盆栽 x≥2.94（z 2.31..2.73）之间 1.39 m；餐桌东缘 x=1.85 以东 ≥1.3 m 至楼梯口 |
| 楼梯 A 段（x 2.64..3.49）入口 | 0.85 m | 踏板实体；两侧为墙/扶手 |

**若要补角色，建议一并修的几何点**（不改产品代码，仅记录）：
1. 楼梯无碰撞（P0）；2. 阁楼 x>2.10 区域净高 <1.50 m，若角色可上去需限制/加提示；3. 开门碰撞盒 DoorHit 只有 2.0×2.6×1.4，精确门洞 1.14×1.94，做角色后可换成门框碰撞；4. 地板/台阶与墙之间无缝隙数据异常（见 §8.2 地形与基座）。

---

## 4. 家具（isle_house_props.gd + cottage.gd 摆放）

### 4.1 坐标/朝向来源（唯一事实链）

1. 尺寸：isle_house_props.gd:63-89 DIMS（Vector3(宽X, 深Z, 高Y)，米），与 scripts/isle_scale_spec.gd 的 _REGISTRY 同源（isle_scale_spec.gd:63，校验工具 tools/probe_props_p7v3.gd）。
2. 摆放：cottage.gd `_interior()` 1764-1786 共 23 件（1F）、`_attic_interior()` 1620-1638 共 15 件（阁楼），全部调用 `IsleHouseProps.build(parent, kind, Vector3(局部x, 地面/壁挂高度, 局部z), 局部yaw)`（isle_house_props.gd:127）。
3. 节点 transform：`build` 里 node.position = pos、node.rotation.y = yaw，**局部 +Z = 家具正面**；floor 类 pos.y = 地面高度、所有部件 y≥0；wall 类（WALL_KINDS 91：coat_rack/wall_clock/picture_frame/curtain）原点在墙面基准、+Z 指向室内、竖直居中（帘向下垂）。返回 {node,footprint,height,kind,lights}，lights 恒为空（灯只做自发光材质，Light3D 由 main.gd 统一注册）。
4. 世界变换：root = Cottage（0.8, 7.9456, -0.6, yaw 0.30）；**世界位置 = root.transform × 局部位置；世界 yaw = 局部 yaw + 0.3000 rad（17.19°）**。节点 meta 只有 prop_kind / prop_wall_mounted（部件另有 prop_role），**没有**额外位姿 meta —— 位置与朝向的唯一来源就是 build 调用的参数 + 节点 transform。
5. 命名/批量：节点名 Prop_<kind>_<seq>（1F seq 016-038，阁楼 001-015）；cottage `_merge_props_of` 196-201 会把 Prop_* 子节点并入静态批（split 区域见 _batch_region 185-194：interior=|x|≤3.55&|z|≤2.85&y<3.05，attic=y≥3.10 同 AABB，其余 shell）。

### 4.2 关键高度（座位/桌面/床，精确值）

| 家具 | 尺寸 宽×深×高 (m) | 关键高度（自地面算） | 构建行 |
| --- | --- | --- | --- |
| chair | 0.42×0.44×0.85 | 座面顶 **0.40**；座板顶 0.38；靠背顶 0.85；前腿高 0.335 | 428-454 |
| sofa | 1.50×0.80×0.78 | 坐垫顶 **0.40**（垫厚 0.09）；底座 0.22；靠背顶 0.78；扶手顶 0.65；腿 0.13 | 459-489 |
| armchair | 0.72×0.76×0.78 | 座面顶 **0.40**；靠背 0.78；扶手 0.65；腿 0.13 | 494-518 |
| reading_chair | 0.70×0.72×1.05 | 座面顶 **0.40**；高靠背顶 1.05；扶手 0.60；腿 0.16 | 780-804 |
| shoe_bench | 0.80×0.32×0.42 | 坐垫顶 **0.42**（厚 0.055）；框 0.325；鞋架 0.14；腿 0.30 | 374-394 |
| dining_table | 1.30×0.80×**0.65** | 桌面顶 **0.65**（板厚 0.035）；桌裙下沿 0.515；车木腿高 0.60（r 0.032→0.040） | 399-423 |
| coffee_table | 0.95×0.50×**0.38** | 桌面顶 **0.38**；裙 0.315；下层板 0.12；腿 0.335 | 523-542 |
| desk | 1.20×0.60×**0.65** | 桌面顶 **0.65**；两侧柜 0.36 宽（x=±0.40）⇒ 膝部净空 **0.44**；背板 0.45；左 3 抽屉把手 0.13/0.30/0.47 | 749-775 |
| side_table | 0.40×0.40×**0.50** | 圆桌面顶 **0.50**（r=0.205）；裙 0.425；下层 0.14；腿 0.44 | 809-821 |
| bed | 1.00×1.90×0.85 | 床架顶 0.22（腿 0.17、侧梁 0.16）；**床垫 0.90×0.18×1.66，顶 0.45**；被子厚 0.06，顶 0.51（覆盖 +Z 半侧）；**床头板在局部 -Z 端，顶 0.85**；床尾板在 +Z 端，顶 0.55；枕头 0.44×0.11×0.30 位于 (±0.235, 0.505, -0.66)，倾 -0.10 rad | 658-696 |
| nightstand | 0.40×0.38×**0.50** | 台面顶 **0.50**（比床垫高 0.05）；双段前脸 | 701-717 |
| wardrobe | 1.00×0.55×1.75 | 顶 1.75；门把手 1.17；抽屉把手 0.42/0.60 | 722-744 |
| wall_clock | 0.40×0.10×0.40 | 挂钟（墙面基准） | 866-891 |
| picture_frame | 0.55×0.04×0.42 | 挂画（墙面基准） | 893-919 |
| curtain | 0.70×0.08×1.35 | 窗帘（向下垂，墙面基准） | 921-947 |
| table_lamp | 0.24×0.24×0.50 | 台灯（自发光灯罩，无 Light3D） | 826-844 |
| floor_lamp | 0.36×0.36×1.45 | 落地灯（自发光灯罩） | 846-864 |

座位/桌面关系（计算值）：餐桌桌面下沿 0.615，椅座 0.40 ⇒ 大腿净空 0.215 m；4 把餐椅前沿均嵌入桌沿 0.10 m（正常收拢姿态）。沙发-茶几间距 0.45 m。

### 4.3 38 件家具世界坐标/朝向（探针实测 + 摆放行号）

说明：yaw 为**世界 yaw**（= 局部 yaw + 17.19°）；y 为节点原点（地面/壁挂基准）世界高度；位置为节点原点世界坐标。parent：1F=Cottage，阁楼=AtticInterior。

| # | kind | 摆放行 | 局部坐标 (x,y,z) | 局部 yaw | 世界坐标 | 世界 yaw | 墙挂 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 016 | doormat | 1764 | (0.000, 0.570, 2.300) | 0 | (1.480, 8.516, 1.597) | 17.2° | |
| 017 | shoe_bench | 1765 | (1.150, 0.570, 2.600) | PI | (2.667, 8.516, 1.544) | -162.8° | |
| 018 | coat_rack | 1766 | (-1.150, 1.470, 2.790) | PI | (0.526, 9.416, 2.405) | -162.8° | 是 |
| 019 | wall_clock | 1767 | (3.490, 2.150, 0.600) | -PI/2 | (4.311, 10.096, -1.058) | -72.8° | 是 |
| 020 | plant_pot | 1768 | (3.150, 0.570, 2.520) | 0.6 | (4.554, 8.516, 0.877) | 51.6° | |
| 021 | rug | 1769 | (-2.100, 0.574, 1.620) | 0 | (-0.727, 8.520, 1.568) | 17.2° | |
| 022 | sofa | 1770 | (-2.100, 0.570, 2.220) | PI | (-0.550, 8.516, 2.141) | -162.8° | |
| 023 | coffee_table | 1771 | (-2.100, 0.570, 1.120) | 0 | (-0.875, 8.516, 1.091) | 17.2° | |
| 024 | armchair | 1772 | (-0.920, 0.570, 1.120) | -PI/2 | (0.252, 8.516, 0.742) | -72.8° | |
| 025 | floor_lamp | 1773 | (-3.120, 0.570, 2.350) | 0.3 | (-1.486, 8.516, 2.567) | 34.4° | |
| 026 | firewood_basket | 1774 | (-2.950, 0.570, -1.700) | 0.4 | (-2.521, 8.516, -1.352) | 40.1° | |
| 027 | desk | 1775 | (-3.190, 0.570, 0.300) | PI/2 | (-2.159, 8.516, 0.629) | 107.2° | |
| 028 | chair | 1776 | (-2.620, 0.570, 0.300) | -PI/2 | (-1.614, 8.516, 0.461) | -72.8° | |
| 029 | bookshelf | 1777 | (-3.340, 0.570, -1.000) | PI/2 | (-2.686, 8.516, -0.568) | 107.2° | |
| 030 | tall_cupboard | 1778 | (-1.000, 0.570, -2.600) | 0 | (-0.924, 8.516, -2.788) | 17.2° | |
| 031 | sideboard | 1779 | (0.200, 0.570, -2.600) | 0 | (0.223, 8.516, -3.143) | 17.2° | |
| 032 | table_lamp | 1780 | (0.200, 1.370, -2.600) | 0 | (0.223, 9.316, -3.143) | 17.2° | |
| 033 | dining_table | 1781 | (1.450, 0.570, 0.800) | PI/2 | (2.422, 8.516, -0.264) | 107.2° | |
| 034 | chair（餐桌 +Z 位） | 1782 | (1.450, 0.570, 1.570) | PI | (2.649, 8.516, 0.471) | -162.8° | |
| 035 | chair（餐桌 -Z 位） | 1783 | (1.450, 0.570, 0.030) | 0 | (2.194, 8.516, -1.000) | 17.2° | |
| 036 | chair（餐桌 +X 位） | 1784 | (1.970, 0.570, 0.800) | -PI/2 | (2.918, 8.516, -0.418) | -72.8° | |
| 037 | chair（餐桌 -X 位） | 1785 | (0.930, 0.570, 0.800) | PI/2 | (1.925, 8.516, -0.111) | 107.2° | |
| 038 | picture_frame | 1786 | (-3.490, 2.000, 0.900) | PI/2 | (-2.268, 9.946, 1.291) | 107.2° | 是 |
| 001 | bed | 1620 | (-2.000, 3.190, -0.900) | -PI/2 | (-1.377, 11.136, -0.869) | -72.8° | |
| 002 | nightstand | 1623 | (-1.150, 3.190, -1.610) | 0 | (-0.774, 11.136, -1.798) | 17.2° | |
| 003 | table_lamp | 1624 | (-1.150, 3.690, -1.610) | 0 | (-0.774, 11.636, -1.798) | 17.2° | |
| 004 | wardrobe | 1626 | (-0.620, 3.190, -2.515) | 0 | (-0.536, 11.136, -2.819) | 17.2° | |
| 005 | bookshelf | 1627 | (0.370, 3.190, -2.630) | 0 | (0.376, 11.136, -3.222) | 17.2° | |
| 006 | desk | 1628 | (0.000, 3.190, 2.440) | PI | (1.521, 11.136, 1.731) | -162.8° | |
| 007 | chair | 1629 | (0.000, 3.190, 1.950) | 0 | (1.376, 11.136, 1.263) | 17.2° | |
| 008 | table_lamp | 1630 | (0.450, 3.840, 2.550) | 0 | (1.983, 11.786, 1.703) | 17.2° | |
| 009 | reading_chair | 1631 | (1.600, 3.190, 1.100) | -PI/2 | (2.654, 11.136, -0.022) | -72.8° | |
| 010 | side_table | 1632 | (1.600, 3.190, 0.450) | 0 | (2.462, 11.136, -0.643) | 17.2° | |
| 011 | rug | 1633 | (0.000, 3.194, 0.900) | 0 | (1.066, 11.140, 0.260) | 17.2° | |
| 012 | plant_pot | 1634 | (2.550, 3.190, 2.200) | 0 | (3.886, 11.136, 0.748) | 17.2° | |
| 013 | picture_frame | 1635 | (1.120, 4.650, -2.790) | 0 | (1.045, 12.596, -3.596) | 17.2° | 是 |
| 014 | curtain | 1637 | (-1.030, 4.920, 2.800) | PI | (0.643, 12.866, 2.379) | -162.8° | 是 |
| 015 | curtain | 1638 | (1.030, 4.920, 2.800) | PI | (2.611, 12.866, 1.771) | -162.8° | 是 |

其中 fl：1F = fy+0.02 = 0.57；阁楼 = attic_floor+0.02 = 3.19（cottage.gd:1620 前的局部定义，见 1491-1640 段）。

**床朝向语义（阁楼床 #001）**：局部 yaw = -PI/2 ⇒ 世界 -72.8°；家具局部 +Z 为床尾方向 ⇒ 床尾朝世界 (-0.955, 0, +0.296)（-X/+Z 向墙），床头朝 (0.955, 0, -0.296)（+X/-Z，朝阁楼中央）。床长 1.9 m 沿该轴：床头端 ≈ 世界 (-0.470, 11.136, -1.150)，床尾端 ≈ (-2.284, 11.136, -0.588)。床头柜世界 (-0.774, 11.136, -1.798) 位于床头左后侧（与床 Z 边留 0.21 m）。

**1F 无床**；可坐面只有 chair/sofa/armchair/reading_chair（0.40 m）与 shoe_bench（0.42 m）。

---

## 5. 猫的程序化动画（isle_cat.gd，可复用经验）

- 结构：`class CatIdleDriver extends Node`（58）持 controller，`_process(delta)` 每帧 `controller.advance(delta)`（61-63）——因此**动画由场景树驱动，暂停场景/禁用 driver 即可静止**（探针可 `cat["driver"].set_process(false)` 后手动 `idle.advance()` / `debug_force_event()`）。`class CatIdle extends RefCounted`（68）是纯状态机。
- 尺寸来历（38-43）：旧猫过大（坐姿耳尖 0.742 m、鼻到尾 0.732 m），全部字面量 × `CAT_MODEL_SCALE = 0.60` ⇒ 目标耳尖 0.445 m、鼻尾 0.44 m、体宽 0.276 m、站立肩高 0.256 m（isle_cat.gd:43）。
- 常量（69-114）：呼吸 BREATH_AMP 0.015、周期 3.2–4.2 s；尾巴 TAIL_AMP 0.18 周期 5–8 s、TAIL_AMP2 0.60、TAIL_AMP3 0.35、TAIL_UP_AMP 0.03；耳朵 EAR_AMP 0.25、抖动 0.13 s/间隔 0.20/事件 0.34、下次 6–14；眨眼 LID_OPEN 1.38 / LID_CLOSED -0.10、闭 0.12/停 0.06/睁 0.12（总 0.30）、下次 4–9；张望 LOOK_YAW 0.35、转 1.2/停 0.5–0.9/回 1.2、下次 10–20；舔毛 LICK_PITCH 0.35、LICK_RAISE 0.072（=0.12×0.60）、侧转 0.14、抬腿 -0.30、上抬 0.60/停 0.6–1.2/放下 0.60、下次 20–35。
- 层级（build 457-539）：root PorchCat(meta isle_cat=true 463、**no_batch=true 466**) → Body（呼吸只做 scale.y，230-231：`breath = 1.0 + 0.015*sin(TAU*t/period + phase)`）→ 躯干/头（Head 位置 HEAD_PIVOT×scale、rot x -0.04）→ HeadCore → 耳/眼/眼睑/胡须；root → Tail（位置 (0.02,0.17,-0.33)×scale，3 节链）；root → Legs（后腿静态、前腿 pivot）；shadow_blob (0,0,0.02)×scale，半径 0.42/0.30×scale。返回 dict 含 root/body/head/ears/eyes/eyelids/whiskers/tail/legs/front_legs/paws/shadow/driver/idle（523-539）。
- 调试 API：`debug_state()` 371（breath_period/breath_scale/counts/history/timers）、`debug_clear_events()` 413、`debug_force_event(kind, phase=0.5, side_override=-1)` 420（立即摆姿势 446）、`_lick_active_side_setup` 448。
- 复用经验：① 呼吸只改 Body.scale.y（保头部/尾巴 pivot 不漂移）；② 眨眼用眼睑旋转而非网格缩放；③ 事件用「下次触发时间 + 阶段插值」而不是 AnimationPlayer，便于探针确定性验证（seed 固定）；④ 动画子树必须 no_batch（否则 merge_static 会合并掉 pivot）；⑤ 影子用 shadow_blob（无 Shadow 开销）。
- 小屋调用：cottage.gd:103 `CAT.build(root, Vector3(1.70, C.deck_top+0.02, 3.80), -0.6)` ⇒ 猫世界 (3.547, 8.386, 2.528)、yaw -17.2°，站在门廊甲板（局部 0.44=deck_top+0.02）。探针读数：driver is_processing=true、breath_period=3.921（随机 3.2–4.2）、breath_scale=0.9973。

---

## 6. 材质 / 网格 / 批量工具（isle_math / isle_palette / isle_batch）

### 6.1 isle_math.gd

- `toon_material(color, opts)` 198-227：参数 opts 键与默认值：bands=4.0、soft=0.55、rim=0.15、wind=0.0、glow=0.0、vertex_color=false、outline=0.0、self_lit=false、rim_color；材质缓存 `_mat_cache`（复合 key），同参数只建一次。
- 描边约定：`outline > 0` 时设 `next_pass = outline_material(width)`（188，按 width 缓存）；家具/房屋可见部件统一 outline 0.02（isle_house_props 全件、cottage 部件），大面积地形/海面不用。
- 网格 helper：box 284、box_rot 296、cyl 308、cyl_rot 324、sphere 340、quad 355、make_prism_mesh 399、prism 419、shadow_blob 429、halo 441、multis 598（MultiMeshInstance3D 快捷）、ribbon_mesh 617、glass_material 575、ground_detail_texture 481、terrain_material 511、grass_blade_texture 530、grass_material 567。`hitbox` 452-464 见 §2.2。
- 世界常量/地形 API：HOUSE_X/Z/YAW 6-8；HOUSE_W 7.6 / HOUSE_D 6.2 / HOUSE_WALL_H 3.18 / HOUSE_ROOF_H 2.47 13-16；HOUSE_FY 0.55 等 18-25；coast_radius 73-75；profile_at 77-94；terrain_height 96-110；house_ground_y 119；house_front 122；door_world 125；door_approach 130；dock_dir 135；dock_start 138；dock_end 143；BIG_TREE/SMALL_TREE/GARDEN/SWING/CAM_* 26-40。

### 6.2 isle_palette.gd

- 22 个颜色键（COLOR_KEYS 6）+ 22 个数值键（NUMBER_KEYS 8），25 帧关键帧 FRAMES（11-35，t=0.0..1.0）；`sample(t)` 51-68 对 t=fposmod(t,1.0) 线性插值，返回含 t 的字典。夜间照明消费的数值键：sunI/moonI/hemiI/fogNear/fogFar/starAlpha/moonAlpha/cloudOpacity/waterGlitterI/windowI/lanternI/fireflyI/birdsAlpha/bloom/exposure/saturation/contrast/warmth/vignette/grain。

### 6.3 isle_batch.gd（合并契约）

- `merge_static(group, opts)` 54 起；opts：skip（跳过子树数组）、split（Callable MeshInstance3D→region 字符串）、dry_run、min_instances 默认 2。
- 只合并「整个 MeshInstance3D 的所有 surface 材质都通过 _mat_allows」（319）的网格；bucket key = split + 材质实例 id + `_fmt_key(mesh, surface)`（顶点属性格式），不同格式/材质绝不合并；几何经 `_rel_xf`（332）变换后用 SurfaceTool.append_from 拼接；每组按 (split, cast_shadow, layers) 生成一个 ArrayMesh；若合并后 surface 数 ≥ 原数（无收益）则放弃（约 119 行 gate）。
- 合并后组上写 meta `batch_manifest`（{name,kind,size,...} 数组，约 158-180），供探针断言部件级几何。
- **no_batch 契约**：任何逐帧动画/需要 pivot 的动态子树必须 `set_meta("no_batch", true)`，实例：DoorPivot（cottage.gd:641）、猫根（isle_cat.gd:466）；否则合并后 pivot 丢失。cottage 合并区域由 `_batch_region` 185-194 给出：interior（|x|≤3.55 且 |z|≤2.85 且 y<3.05）/ attic（同 AABB，y≥3.10）/ shell（其余）。

---

## 7. 性能与验收工具（命令行/日志/产物格式）

### 7.1 命令行开关（main.gd:243-304）

| 参数 | 位置 | 行为 |
| --- | --- | --- |
| --perf | main.gd:249、294-295 → `_run_perf` 3467-3566 | 性能采样，结束 quit |
| --perf 配合 --quality N | main.gd:269-272 | 强制画质档 0..4（仅 perf 生效） |
| --shots | main.gd:246、300-301 → `_run_shots` 1487 | 截图序列 |
| --transition | main.gd:247、296-297 → `_run_transition` 2071 | 转场录制 |
| --selftest | main.gd:248、292-293 → `_run_selftest` 2117-2565 | 断言自测 |
| --p7shots | main.gd:245、298-299 → `_run_p7shots` 4121（_set_p7_sim_time 4294；4132 设 _day_length=3600） | P7 阶段截图 |
| --scale-debug | main.gd:284-291 | 挂 tools/scale_debug_overlay.gd（1 m 立方/1.50 m 人形/标尺），打印 [SCALE] installed built=.. children=.. |

自动化运行统一 `_settings = Settings.defaults()`（main.gd:254-255），保证可复现；普通启动才 load_settings()。

### 7.2 --perf 采样内容（`_run_perf` 3467-3566 / `_sample_frames` 3568-3584）

- 6 个固定机位（名称/时间/相机）：noon_clear（12:20）、golden_cloud_water（17:40）、night_shadows（22:40）、night_close（22:40）、far_island（12:20）、sky_up（22:40）；`_cam_target = Vector3(0,6,0)`；每机位 `_sample_frames(180)`。
- 追加：time_panel_open（120 帧）；lite_noon_nomultimesh / lite_night_nomultimesh（隐藏所有 MultiMeshInstance3D + 海面 wave_detail=0、foam_amount=0，各 120 帧）；quality_4..0 循环（Engine.max_fps=0，附加 msaa/scale/grass/lights 字段）；after_6s（objects/nodes/orphan）。
- 每行格式：`[PERF] %-20s fps=%.1f frame_ms=%.2f cpu_ms=%.2f objects=%d draw_calls=%d vram_mb=%.1f`，字段来源 _sample_frames：fps、frame_ms、cpu_ms、objects=RENDER_TOTAL_OBJECTS_IN_FRAME、calls=RENDER_TOTAL_DRAW_CALLS_IN_FRAME、vram=RENDER_VIDEO_MEM_USED/1048576。

### 7.3 截图/自测格式

- `_save_shot` 2572-2578：await RenderingServer.frame_post_draw → `get_viewport().get_texture().get_image().save_png(dir+name+.png)`，打印 `[SHOT] <name> <W>x<H>`；目录 SHOTS_DIR = D:/休闲小岛幻境/开发产物/shots/、P7_SHOTS_DIR = .../p7/shots/（main.gd:7-8）。
- `_run_selftest` 2117-2565：每条断言打印 `[TEST] PASS <label>` / `[TEST] FAIL ...`，结束 `[TEST] RESULT n/m passed` 并 quit。

### 7.4 探针风格（可复用的验收模板）

- `tools/probe_verify_p7v3.gd`：extends SceneTree，只读；计数器 _pass/_fail/_skip_count/_warn_count；`_ok(cond,label,detail)` / `_skip` / `_warn` / `_near(a,b,eps)` / `_near_vec` / `_walk(parent)`（DFS 子节点）；输出 `[V3] PASS|FAIL|SKIP|WARN ...`，结尾 `[VERIFY] RESULT pass=N fail=M skip=K warn=W`，fail>0 时 quit(1)；引导流程 189-209（instantiate isle.tscn→add_child→两帧→menu.instant_finish→set _mode/_time_source/_started/_paused/_auto_orbit/_blending）。
- `tools/probe_frame_p7v3.gd`：窗口截图（headless 下 quit(1) 拒绝）；DEFAULT_OUT D:/休闲小岛幻境/开发产物/p7v3/shots/frame/；1600×900；时间 T_DAY 745、T_DUSK 1050、T_NIGHT 1305（当天分钟）；参数 --stage=all|door|porch|interior|stairs|boat|cat（逗号列表）、--out、--fov（默认 42）；输出 `[P7V3F] STAGE/SHOT/SKIP`、结尾 `[P7V3F] RESULT shots=N skipped=K dir=...`；写 MANIFEST.md。
- `tools/probe_scale_world.gd`：headless 全岛尺度审计（- 头注释 2-16）；--mode audit|inventory、--tag、--out；DEFAULT_OUT D:/休闲小岛幻境/开发产物/p7v32/scale（23）；输出 `[SCALE] START`、`[SCALE] PASS/WARN/FAIL/INFO 分组/键 | 详情`、`[SCALE] RAW`、结尾 `[SCALE] RESULT pass=warn=fail=info= mode= tag=`；audit 有 FAIL 时 quit(1)，inventory quit(0)；写 inventory.json（JSON.stringify(payload,"  ")，1909-1935）与 inventory.md。
- 本报告新增 `tools/probe_recon_p7v4.gd`（headless，只读）：同款引导流程，输出 [RECON] 行（house/levels/stairs/props/physics/terrain/dock/path/cat/time），运行命令：
  `Godot_v4.7.2-stable_win64_console.exe --headless --path "D:/休闲小岛幻境/游戏工程" --script res://tools/probe_recon_p7v4.gd`（约 40–60 s，exit 0；headless 下 user://logs 打不开属正常告警）。可删除。

---

## 8. 世界可行走域 / 地形 / 码头 / 观景点（world.gd + isle_math.gd）

### 8.1 地形函数与可行走坡度

- 高度 = `isle_math.terrain_height(x,z)` 96-110：profile_at(r/coast_radius(atan2(z,x))) + 草甸摆动 + 悬崖细纹 + 高斯山丘 2.9·exp(-((x+13.5)^2+(z+11)^2)/130) + 0.18·海滩脊（n≈0.99）；`coast_radius` 73-75 = 25.5 + 2.8sin(3a+0.70) + 1.9cos(5a-1.20) + 1.1sin(7a+2.10) + 0.7cos(11a+0.40)；`profile_at` 77-94 控制点 [[0,7.55],[0.40,7.45],[0.54,7.05],[0.64,6.10],[0.73,4.95],[0.81,3.60],[0.88,2.10],[0.94,0.85],[1.00,0],[1.05,-1.05],[1.14,-3.10],[1.30,-5.60],[1.60,-7.20]]（smoothstep 插值）。
- **地形网格实际用 world.gd `_h` 270-290 = M.terrain_height + 3 个 smoothstep 土丘**：+0.34@(13.5,-4.0,r4.8)、+0.30@(5.3,16.3,r4.2)、+0.32@(-16.0,12.2,r4.5)（_build_terrain 400 用它采样 429）；这三个土丘离房屋/主路/码头均 >4 m（探针点最近 4.5 m 以上），故本报告房屋/码头/主路的 terrain_height 数值与网格一致。
- 主路折线（world.gd _prepare 163-167）：door_approach → (5.6,8.6) → (9.6,10.2) → (14.2,11.8) → dock_start，宽 0.62 m；花园支路（169-171）door→(1.2,7.1)→(-1.6,6.55)→(-3.9,4.9)→(-5.4,2.6)→(-6.4,0)→(-7.05,-1.9)→(-7.45,-2.95)，宽 0.50；花园内十字路 173-174（宽 0.44）；花园东门→田圃 176-177（宽 0.40）。
- 探针实测主路 4 段地形最大坡度（每段 8 采样，度）：**seg1 7.92、seg2 26.05、seg3 44.61、seg4 50.74**；折线顶点地形高度 7.731→7.414→6.729→5.019→1.857。⇒ 以 35° 为可走上限，**主路从 (9.6,10.2) 之后不可走**（现有路是视觉条带，不削地形）；若要可走岛民需重排码头段路径/做台阶或坡道。

### 8.2 房屋与地形（基座/地板穿透检查，探针实测）

| 点 | 地形 y | 说明 |
| --- | --- | --- |
| house_ground_y(0.8,-0.6) | 7.9456 | 房屋根 y、门廊平台基准 |
| 室内楼板四角（局部 ±3.49,±2.79） | 8.207 / 7.877 / 7.747 / 7.655 | 楼板底面世界 8.3556 ⇒ 最小净空 **0.148 m**（西北角），无地形穿透 |
| 基座外四角（局部 ±4.30,±3.15） | 8.359 / 7.846 / 7.705 / 7.589 | 基座底 7.1956 ⇒ 埋深 0.394–1.164 m，无悬空 |

结论：地形没有穿进室内（最小 0.148 m），房屋基座四角均埋入地形，可放心在其上做角色/导航；唯一注意点是西北角地形离楼板底面仅 0.148 m（若做挖填/抬高地形需复测）。

### 8.3 码头（world.gd:2344-2462）

- Dock 节点世界原点 (19.785, 1.857, 14.125)，rotation.y=0.62 rad；方向 (cos0.62,0,sin0.62)=(0.8139,0,0.5810)；甲板**绝对世界 y = DECK_WORLD_Y = 0.72**（world.gd:31）。18 块板 BoxMesh(3.4,0.10,0.50) z=2.05+i·0.525；桩 6 对 x=±1.50（z 2.20/3.92/5.64/7.36/9.08/10.40），桩顶世界 0.78、底 -3.40；除靠岸第一对外均有栏杆（栏顶世界 1.64）；系船柱 (±1.10, deck_y+0.55, 9.65)；梯子 z=11.18 下到 -2.20；3 块靠岸石踏步（宽 2.70）z=1.70/1.42/1.14，顶面世界 0.78/0.86/0.94。
- **岸端埋没问题（P7-V4 必修）**：沿码头局部 z 的地形 y 与甲板高差：z=0 → 地形 1.857（甲板低 1.137 m）；z=0.5 → 1.397（低 0.677）；z=1.0 → 1.128（低 0.408）；z=1.5 → 1.021（低 0.301）；**z=2.0 → 0.650（甲板高出地形 0.070 m，甲板从此露头）**；z=2.5 → 0.282；z=3.0 → 0.001；z=5.0 → -1.743；z=10.0 → -5.373；z=11.0 → -5.603；z=12.0 → -5.694。⇒ 靠岸约 1.9 m 甲板、3 块石踏步（顶面比地形低 0.16/0.18/0.19 m）、首对桩与岸端栏杆全部埋在沙里；从沙滩上甲板需在 z≈2.0 处跨 0.07 m 台阶。
- 码头端 x/z (28.738, 20.516)，甲板面 y=0.72；dock lantern_world / perch 由 world.gd:2344-2462 返回 dict（end/perch/bollard/light:{pos,color(1.0,0.76,0.45),range 8.0,intensity 1.40}）。

### 8.4 观景点坐标（世界，供 V4 交互/截图参考）

| 观景点 | 世界坐标 | 地面/台面 y | 备注 |
| --- | --- | --- | --- |
| 门廊台面中心（局部 (0,0.42,3.90)） | (1.952, 8.366, 3.126) | 8.3656 | 门口正前，猫所在甲板 |
| 门前小径起点 door_approach | (2.425, -, 4.654) | 7.9456 | 坡度 3.25° |
| 码头尽头 | (28.738, -, 20.516) | 0.72 | 甲板面；岸端埋沙见 §8.3 |
| 灯塔基座 | (-17.000, -, 9.000) | 6.1705 | 塔高 18.2759 m（world.gd:30 = 1.5× 旧风车 AABB 12.1839），坡度 4.24° |
| 秋千 | (-7.90, -, 4.20) | 7.6518 | SWING_PIVOT_X/Z world.gd:35-36，LIMB_Y 5.55（横梁高），坡度 6.08° |
| 花园中心 | (-7.0, -, -5.8) | 9.1985 | 坡度 16.47°，花园矩形 X0 -9.75/X1 -5.90，Z0 -9.45/Z1 -2.95 |
| 田圃中心 | 约 (-3.3, -, -8.25) | 8.6006 | 田圃 X0 -4.90/X1 -1.70，Z0 -9.60/Z1 -6.90，坡度 10.64° |
| 大树立点 | (-10.9, -, 4.2) | 7.8677 | 树位 world.gd:185，坡度 5.83° |
| 屋脊（非人行） | (0.0908, 14.4156, -2.8928) | 14.4156 | ridge perch r=0.26，猫/鸟停靠点（cottage.gd:1799-1834） |
| 岛原点 | (0, -, 0) | 8.0017 | 地形 AABB P(-43.563, -7.173, -43.773) S(90.524, 16.941, 86.053)，岛直径 60.144 m |

小屋 perch 共 14（屋脊 3、檐口 4、烟囱 1、门廊梁 2、门廊栏 4），世界 perch 共 22；`_make_perches` cottage.gd:1799-1834 返回 {id,pos,facing,normal,slope,radius,kind,slots?}。

---

## 9. P7-V4 风险与建议（只记录，不实施）

| 风险 | 证据 | 建议 |
| --- | --- | --- |
| **P0：无角色/无碰撞/无导航** | §2 全树盘点与 grep 0 命中 | 先做 CharacterBody3D + 地形/地板/楼梯碰撞 + NavigationRegion3D；否则任何「走/上楼/坐下」任务都无法验收 |
| P1：楼梯几何 OK 但无碰撞体 | §3.3，Staircase 仅 Mesh | 给 15 级踏步 + 平台加 BoxShape（或 1 个 ConcavePolygonShape3D），step_height≥0.164 |
| P1：主路入海口段坡度 44.6°/50.7°，不可走 | §8.1 主路 4 段采样 | 重排 (9.6,10.2)→(14.2,11.8)→dock 段为折返/台阶，或在码头前设坡道；地形不改则角色走不到码头 |
| P1：码头岸端埋沙 0.30–1.14 m、石踏步埋 0.16–0.19 m | §8.3 逐 z 采样 | 调 DECK_WORLD_Y 或局部压低地形/抬高岸端，否则角色/相机从沙滩上码头会穿地 |
| P2：阁楼 x>2.10 m 净高 <1.50 m；床尾侧仅 0.947 m | §3.4 净高表 | 若角色可上阁楼：加头部碰撞提示或限制活动区；床边交互点放在 |x|≤2.0 |
| P2：家具最窄间隙 0.325 m（扶手椅↔茶几） | §3.5 净宽表 | 若做碰撞家具，需接受绕行或把扶手椅外移 ≥0.1 m；主通道 1.3–2.6 m 不受影响 |
| P2：门碰撞盒过粗（2.0×2.6×1.4，layer2） | cottage.gd:106 | 做角色后把门框/门扇换成真实碰撞，门洞 1.14×1.94 |
| P3：暂停不冻结道具动画 | main.gd:680/938 | 若 V4 需要「真暂停」，把 _update_props/灯光按 _paused 冻结（注意船只生命周期） |
| P3：_now_sim_seconds() 返回现实时钟 | main.gd:661-662 | 后续代码不要用它取模拟时刻；统一用 _sim_seconds/_sim_delta |

---

## 附录 A：本报告数据来源与复现

- 代码阅读：main.gd 4366 行、world.gd 3752、cottage.gd 1841、isle_house_props.gd 1011（先 grep "^func " 建索引再定位，行号已逐条核对）。
- 引入的探针：tools/probe_recon_p7v4.gd（只读、headless、不写产品文件）；输出标签 [RECON]。
- 复现命令（bash，工作目录 D:/休闲小岛幻境/游戏工程）：
  `/d/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe --headless --path "D:/休闲小岛幻境/游戏工程" --script res://tools/probe_recon_p7v4.gd 2>&1 | grep "\[RECON\]"`
- 已核对的关键行号（可直接跳转）：main.gd:32-46、180-190、243-304、315-324、644-662、674-692、733-737、753/938、1002-1006、1051-1077、1278-1286、1330-1380、1391-1429、2117-2565、2567-2578、2811-2830、2854、3198-3214、3405-3462、3467-3584、3605-3744、4086-4132、4294；world.gd:15-37、52-187、270-290、392-436、2344-2462；cottage.gd:76-174、185-201、267-367、372-535、540-668、871-1130、1332-1640、1764-1786、1792-1834；isle_house_props.gd:63-127、327-983；isle_math.gd:6-40、73-143、188-227、284-464、598-617；isle_batch.gd:43、54-180、319-343。
