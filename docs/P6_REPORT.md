# P6 实施报告：画质系统 / 天体环境 / 音频 / 交互 / 水面

> 项目：休闲小岛幻境（Godot 4.7.2 stable · Forward+ · Vulkan · 纯 GDScript · 程序化资源）
> 工作区：`D:\休闲小岛幻境`，工程：`游戏工程/`
> 本报告只记录**实际执行过**的命令、探针与截图；静态检查与实际视觉/性能验证严格分开标注。
> 截图目录：`D:/休闲小岛幻境/开发产物/shots/`（本轮统一截图）、`开发产物/shots6/{t1,t3,t4,t5}/`（队友专项）

> **T7 收尾修订（2026-10-20 晚）**：本文件是 P6 阶段的历史记录。T7 复核发现并修复了「高级覆盖只改状态不改渲染」
> （AO 开关未接线、`lod_bias`/`fog_scale` 从未被渲染消费、菜单 AO 三态别名错误）；引擎体积雾经 A/B 实测
> 在黎明会染黑海面、与暖色艺术风格冲突，**决定不接入并从菜单移除该覆盖行**（证据 `docs/P6_AO_FOG_EVAL.md`）。
> 因此本文件 §4/§7/§9 中「三行高级 override」「体积雾可覆盖」等描述已过时，最终结论以
> `docs/P6_CLOSEOUT_REPORT.md`（T7 收尾报告）为准。

## 0. 结论摘要

本轮 13 项需求全部落地代码与数据；§7 的 20 条验收项中 16 条「通过」、4 条「部分」
（分辨率 4K 未实跑、夜间音频无主观听感、墙体遮光视觉对比弱、性能受共享环境波动），无未实现项。
另外发现并修复了两个此前未被发现的真 bug：**q2 及以上画质的全屏灰白蒙层**（自定义 AO 后处理与海面 SSR 都在
不透明 pass 采样屏幕纹理，读到未合成画面）和 **HUD 罗盘东西镜像**（与太阳方位角对照后发现）。
画质五档现在有真实差异（像素统计与截图见 §6.1）。

交付后用户实机试玩又反馈 3 个问题，本轮已全部定位并修复（见 §11）：**ESC 菜单旋转/缩放残留导致错位、且入场动画期间控件不可见**；**「高」及以上画质阁楼窗重影**（自定义 AO 在深度断裂处错误采样，窗洞亮度比 q2 0.496→0.995）；**HUD 缺少 C 键自动运镜提示**。修复后重新跑完全部 headless 与窗口回归。
实测性能（RTX 2060 / 1600×900，两次实跑区间）：q0 144–162fps、q1 98–126、q2 122–137、q3 64–81、q4 41–63fps（VRAM 878MB）。

## 1. 原始问题与真实根因

| # | 需求/现象 | 真实根因 | 修复 |
|---|---|---|---|
| 1 | 画质只有 3 档但滑条 5 刻度 | UI 滑条 tick 数与 `isle_quality` 预设数不一致，档位只切换 3 组效果 | 建立 `isle_quality.gd` 五档 24 参数体系 + `isle_settings.quality_overrides` 自定义态，UI 滑条 5 tick 一一对应 |
| 2 | 分辨率档位少、窗口不适配 | 只有全屏/窗口切换，无分辨率列表与缩放策略 | `RESOLUTIONS` 8 档（按显示器可用区域过滤）+ 三窗口模式 + canvas_items/expand/1440×900 基准 |
| 3 | 时间流速是倍率、难理解 | 旧 `day_length` 秒数直接暴露 | 十档“每游戏日现实分钟”+ 单一时钟 `_sim_seconds` 驱动全部系统 |
| 4 | fire crackle / night loop 刺耳 | 音频素材本身高频过亮（>8kHz 占比 11.7%/0.43%）、循环接缝有爆音、无总线 EQ | 重制素材（见 §4.3）+ 五总线 + 运行时 EQ/低通/压缩 |
| 5 | 太阳固定左右升落、月亮动画结束消失 | 日月按“伪动画”驱动，未用广州经纬度天文解算 | `isle_astro.gd` NOAA 太阳 + Meeus 月亮（见 §4.4），世界坐标映射北=-Z/东=+X |
| 6 | ESC 菜单无入场动画 | `_menu.open(false)` 标题菜单路径与 ESC 的 returning 路径不同 | 复用开局动画参数的屏外错峰入场 + 反向退场，单一 Tween 可中途反转（§4.5） |
| 7 | 灯塔光束穿墙照亮房屋背面 | 光束是 unshaded 解析锥，与房屋无遮挡关系；房屋虽不透明但光束不参与深度/阴影 | toon.gdshader 增加 12 盏自定义点光 + 世界空间 ray-AABB 遮挡（`beam_occlusion`），由 cottage 提供贴合盒（§4.6） |
| 8 | 阁楼玻璃不透、窗外有夜间光球 | 旧玻璃材质进 `window_mats` 被夜间 glow 当窗光雾化；窗外挂了 2 个 halo 球 | 阁楼单独双层低反射玻璃（不进 window_mats）+ 删除 2 个窗外 halo + 室内两盏灯（§4.7） |
| 9 | 海鸥停屋檐穿模 | 栖点是屋檐边界空中点，法线取屋顶近似值 | 真实瓦面射线求交生成 10 个栖点 + 姿态贴合法线（§4.8） |
| 10 | 自动运镜无快捷键 | 只有设置面板开关 | 正式 InputMap 动作 `toggle_auto_orbit`（默认 C）+ 平滑停止保留机位（§4.9） |
| 11 | 炊烟时段不对 | 定时器+固定时段 | 统一时钟 `_update_smoke_clock` → `ChimneySmoke.set_sim_seconds`，11–13 / 17–19 双窗口（§4.10） |
| 12 | 海面像平面贴图 | 只有 5 波小振幅且 CPU 与 GPU 不同源 | 7 组方向波 + CPU 同源 `IsleWaves` + 法线/泡沫/反射分档增强（§4.11） |
| 13 | 缺少更高画质档 | 高级后处理未接入 | 五档预算 + 自定义 AO（透明乘法）/解析反射/云层 0–3（§4.12） |

### 1.1 本轮额外发现（原计划外）

- **q2+ 全屏灰白蒙层**：`post_ao.gdshader` 原先在不透明 pass 用 `hint_screen_texture` 采样后整屏写回，读到的是未完成画面；
  `sea.gdshader` 的屏幕空间 SSR 同理，还叠加了竖条纹伪影。两者已在 §4.12 修复。
- **HUD 罗盘镜像**：旧公式 `atan2(-dir.x,dir.z)` 与天文方位角（az=0 北=-Z，90=东=+X）东西相反；
  修正为 `fposmod(rad_to_deg(atan2(dir.x, -dir.z)), 360.0)`，截图放大后与 NOAA 方位角逐帧对齐（07:12 显示 115°，参考 115.15°）。

## 2. 参考的官方文档 / 开源方案 / 实际采用

| 主题 | 参考 | 实际采用 |
|---|---|---|
| 多分辨率与缩放 | Godot 官方 Multiple resolutions | `content_scale_mode=canvas_items` + `aspect=expand` + 基准 1440×900；`Window.size` 切窗口，不改 OS 分辨率 |
| 环境与后处理 | Godot 官方 Environment and post-processing | 使用其 Glow/tonemap/adjustment 对全屏有效的部分；SSAO/SSR/体积雾对 unshaded 管线无效，改为自定义实现 |
| 空间着色器 | Godot 官方 Your first shader / Spatial shader reference | sea/sky/toon/post_ao 均为 spatial shader；实测 4.7 限制：fragment 无 SCREEN_PIXEL_SIZE、fragment 禁止 return、用户函数不能引用 stage built-ins |
| 音频总线 | Godot 官方 AudioServer / Audio buses | 5 条总线 Master/IsleAmbient/IsleBirds/IsleFire/IsleSFX，运行时幂等效果链；线性→dB 用 `linear_to_db`，0 值额外 mute |
| 太阳位置 | NOAA Solar Calculator（官方网页算法） | NOAA 太阳赤纬/时差 + 地平坐标 atan2；日出日落高度 -0.8333°、晨昏 -6/-12/-18 |
| 月亮位置 | Meeus *Astronomical Algorithms* ch.47（47.A/47.B 表） | 完整 60 项黄经/距离 + 60 项黄纬 + 章动 + 视差 topocentric 修正；月相独立按朔望月 |
| 水面波动 | Godot 官方 3D shader 教程 + Gerstner 水项目（LesusX/Water-Shader，仅研究思路） | 不直接拷贝代码：采用“解析 sin 波叠加 + 解析法线 + CPU 同源”方案，理由见 docs/P6_RESEARCH_VISUAL.md（Gerstner 水平位移导致 CPU 反解抖动） |
| 画质预算 | Godot Forward+ 特性支持表（实测） | 只用当前渲染器真实有效的：MSAA/SSAA/TAA/FXAA、Glow、云层、波浪/泡沫、AO 自定义、LOD/密度 |

## 3. 修改清单（按模块）

### 3.1 脚本
- `scripts/isle_settings.gd`：全量重写 → 五档画质+override、十档 day_length、8 分辨率、三窗口模式、五组音量、时间来源/时区、旧配置迁移、`save/load`。
- `scripts/isle_quality.gd`（新增）：`QUALITY_PRESETS` 5 档 × 24 参数、`KEY_SPECS` 类型/范围、`sea_params()`、`preset()`、`apply_overrides()`、自定义判定。
- `scripts/isle_waves.gd`（新增）：7 组波表 CPU 复刻 `height/grad/normal/sample_stats`。
- `scripts/main.gd`：五档应用（MSAA/缩放/TAA/AA/云/海/草/灯/AO/SSR/雾/粒子/LOD/max_fps）、窗口三模式、分辨率 content scale、五总线路由、统一时钟（十档）、炊烟时钟、自动运镜 C 键与平滑停止、灯塔遮挡盒注册、HUD 显示、DOM/截图/性能/自检钩子、ESC 菜单 07 截图走真实 ESC 路径。
- `scripts/isle_astro.gd`：全量重写 → NOAA 太阳 + Meeus 月亮 + 视差/章动 + 晨昏 + 日月升落/方位/照度/相位、缓存与二分。
- `scripts/cottage.gd`：`get_beam_occluders()` 贴合盒、阁楼双层玻璃、删窗外 halo、室内双灯、`_roof_tile_data()/_make_perches()` 真实瓦面栖点。
- `scripts/fx.gd`：`ChimneySmoke` 双窗口统一时钟、`BirdFlock` 栖落法线/坡面姿态、海鸥模型网格细分。
- `scripts/menu.gd`：ESC 入场/退场动画（单 Tween、错峰、可反转、动画期禁交互）、五档画质/三行 override/十档时间/五组音量/分辨率确认层。
- `scripts/hud.gd`：自动运镜状态指示与 toast、时间面板“X 分钟/游戏日”、罗盘公式修正。
- `scripts/isle_audio.gd`：重写 5 总线 + 效果链 + 15 player + 调试快照。
- `scripts/world.gd`：`_build_perches` 去重、草/石/花 LOD 预算接入。
- `scripts/ui_slider.gd`：`set_tick_count` 支持五档刻度。

### 3.2 着色器
- `shaders/sea.gdshader`：7 波顶点位移（detail gate）+ 解析法线 + 深度泡沫 + 解析反射细节 `reflect_extra`（移除屏幕空间 SSR）。
- `shaders/sky.gdshader`：云层 0–3、日出日落暖带/维纳斯带/太阳盘色温连续过渡、星空/银河与月相联动。
- `shaders/toon.gdshader`：12 盏自定义点光（g_l0..11）+ `beam_occlusion` 世界空间 ray-AABB 光束遮挡。
- `shaders/post_ao.gdshader`（新增）：透明乘法 AO，`ALBEDO=0, ALPHA=ao` → dst*(1-ao)，视空间半球投影采样。
- 其余：`vignette/glass/grass` 小幅参数化。

### 3.3 配置/资源
- `project.godot`：`[input] toggle_auto_orbit`（C）、stretch aspect=expand、渲染器设置确认。
- `assets/audio/fire_crackle.wav`、`night_loop.wav`：按 §4.3 重制。
- `tools/`：新增/更新 probe_settings6、probe_quality6、probe_water6、probe_audio6、probe_cottage6、probe_bird6、probe_smoke6、probe_astro6、probe_menu6、probe_esc_e2e_t1 等 20+ 探针。
- `docs/P6_ASTRO_ACCURACY.md`、`docs/P6_RESEARCH_VISUAL.md`：技术报告。

## 4. 关键实现细节

### 4.1 统一时钟与十档“每游戏日耗时”
- 唯一时钟：`_sim_seconds`（自 1970-01-01 游戏本地秒）。模拟模式每帧 `_sim_seconds += delta * 86400.0 / max(day_length,1)`；
  现实模式 `_sim_seconds = _abs_unix + _offset_for(tz)`（时区换算），切换时间来源不丢模拟设置（两者独立保存）。
- 十档 `DAY_LENGTH_PRESETS = [60,300,600,900,1200,1500,1800,2400,2700,3600]` 秒现实/游戏日（1/5/10/15/20/25/30/40/45/60 分钟），
  `sanitize_day_length` 吸附到最近档，旧 480 秒自动迁移到 600 秒档。
- 所有依赖时间的系统都只读这个时钟：太阳/月亮位置、天空颜色、灯光、船出航/返航/夜间休息、海鸥作息、炊烟窗口、灯塔转速、自动运镜节拍。
  不存在第二个独立计时器（`_update_smoke_clock`、船/鸟均每帧读同一 `_sim_seconds`）。
- 现实时间模式下设置面板显示“模拟时间档位暂不生效”；暂停/恢复/手动调时/跨日由同一时钟处理。

### 4.2 五档画质 + 分辨率/窗口
- 五档 24 参数完整表见 `scripts/isle_quality.gd` 与 `docs/P6_RESEARCH_VISUAL.md` §2；关键差异：
  MSAA 0/2x/4x/8x/8x、3D 缩放 0.85/0.92/1.0/1.15/1.25（低档 FSR1，其余 bilinear）、TAA 仅 3/4 档、
  云层 0/1/2/2/3、海波 3/4/6/7/7 组、海网格 0.6/0.8/1.0/1.2/1.4、灯预算 4/6/8/10/12、
  glow 0.55/0.75/1.0/1.08/1.12、AO 关/关/0.35/0.55/0.75、max_fps 60/60/0/0/0。
- 切换不重建场景：只更新材质 uniform、引擎属性、已有节点密度；昂贵资源（海网格）用 `_apply_sea_mesh` 复用一次调用并防抖。
- 自定义态：设置面板三行高级 override（`sea_ssr` / `post_ao→posts_ao` / `volumetric_fog`）任一与预设不同即显示“自定义”，重选预设恢复整组参数。
- 分辨率：8 档（1280×720、1366×768、1440×900、1600×900、1920×1080、2560×1440、3440×1440、3840×2160），按 `DisplayServer.screen_get_usable_rect()` 过滤；窗口模式 windowed/fullscreen/borderless 三态；危险切换（全屏/超宽）有 12 秒确认层自动回退。
- 窗口：`Window.size`/全屏切换，`content_scale_size=1440×900`、`mode=canvas_items`、`aspect=expand`、最小 1024×576；UI 随内容缩放，超宽屏按 expand 加宽不拉伸。

### 4.3 音频
- 总线：Master（最终）、IsleAmbient（海浪/风/夜晚循环）、IsleBirds（鸟鸣）、IsleFire（火焰）、IsleSFX（交互/船/水花/按钮）；
  `AudioServer` 各总线运行时加**幂等效果链**（P6_ 前缀去重）：Ambient=LowPass 11200Hz+EQ6；Birds=EQ6+LowPass 13200Hz；
  Fire=LowPass 8200Hz+EQ6+Compressor；SFX=Compressor+EQ6。15 个 player 全部路由到总线，没有每 player 固定冲突音量。
- 素材重制（T2 用离线频谱分析驱动）：
  - `fire_crackle.wav` 4s：>8kHz 能量占比 11.67%→0%，频谱质心 4567→670Hz，峰值 -6→-4.52dBFS（不削波）；
  - `night_loop.wav` 16s：>8kHz 0.43%→0%，2–6kHz 占比 47.3%→10.7%，循环接缝 EDGE 1.69→-0.02dB。
- 音量：线性 0..1 → `linear_to_db`；0 值→-80dB 且只 mute 自身总线（不 mute 其他组）；播放中修改即时生效（总线音量）；重启读回 `settings.cfg`。
  配置写入 5 个 `volume_*` 键并镜像旧 `volume`（兼容旧版）。

### 4.4 日月天文
- 位置：`IsleAstro.compute(sim_seconds, tz)` 每帧 <0.2ms；`day_events` 缓存每日结果（冷 2.4ms）。
- 世界坐标映射：地理方位角 az（0=北，顺时针）→ `sun_dir=(sin az*cos alt, sin alt, -cos az*cos alt)`，即**北=-Z、东=+X**；
  `IsleMath.sun_dir` 与 `sky.gdshader` 使用同一映射，无任何子节点额外旋转（Island/world 根 rotation=0；cottage 自身 rotation.y=0.30 只影响小屋）。
- 天空：太阳高度破晓 -18°→-6°→-0.83° 连续过渡；地平线暖带宽度/颜色随 `low_sun` 连续变化；日落后星空/银河/月光渐入；太阳盘色温随高度白→橙；进入地平线下自然淡出（不瞬间创建/删除）。
- 月亮：Meeus 47 表 + 章动 + 视差 topocentric；月升/月没阈值 -(0.5667°+sd)；月相由日期与朔望月周期单独计算（`moon_phase`），与位置解耦。
- 精度（对 NOAA / astronomy-engine 2.1.19 基准，10 个日期）：日出最大误差 3.2s、日落 2.5s、太阳方位 0.001°、
  月出 5.4s、月没 3.8s、月亮方位 0.013°、正午照度 1e-4；24h 相邻秒日月高度差 <0.004°（无跳变）。
  明确标注：这是近似天文模型（非完全精确天文模拟）。

### 4.5 ESC 菜单动画
- 复用 T1 在开局标题菜单的缓动参数：`ANIM_ITEM_TIME=0.52s`、`ANIM_STAGGER=0.04s×7`、总 0.80s、`ease_out_back`。
- 打开：8 个选项从屏幕外（左/右/上三方向错峰）滑入 + 透明度渐显，动画期 `_set_menu_interactive(false)` 防止点到未到位控件；
  关闭：同一 Tween 从当前 `_anim_t` 反向播放；动画中再按 ESC 调 `_reverse_anim()`，不叠加 Tween、不重复创建。
- 实测 07_menu_enter_012/042/stable/exit_018 四帧（真实 ESC 注入路径），见 §7.6。

### 4.6 灯塔光束与房屋遮光
- 房屋墙体：`cottage.gd` 全部墙体使用不透明 toon 材质、双面几何完整、不参与任何透明排序；`cast_shadow` 保持开启（虽然 toon 管线自行解析光照，遮挡由自定义遮挡盒完成）。
- 遮挡：`get_beam_occluders()` 返回 3 个世界空间 OBB（两层主体 + 阁楼山墙），yaw=-0.30 与小屋 rotation.y 一致；
  `toon.gdshader` 对每盏自定义灯做世界空间 ray-AABB：光束进入盒后穿行 <0.2m 不衰减、>1.2m 完全遮挡，
  `blit *= occlusion`，所以背光墙不会被照穿。
- 探针：`probe_cottage6` 15/15 射线遮挡断言通过（近光侧 occl=1.000，背光墙/屋后地面/室内/阁楼内=0.060）。

### 4.7 阁楼玻璃与光球
- 只改阁楼：双层独立玻璃材质（外 opacity .020/tint .10/f0 .030/refl .34；内 .014/.08/.026/.26），
  双层透过率 ≈0.817，head-on 实测 alpha 外 0.0551/内 0.0435；**不加入 `window_mats`**，避免夜间 glow 把它当窗光雾化。
- 删除阁楼窗外 2 个 halo 球（`window_halos` 6→5）；室内新增第 2 盏暖橙灯（light_sources 9→10），夜间只靠室内灯照亮书桌/椅子/地毯/地板/内墙。
- 截图 06_attic_window_night 实测：室内家具清晰可见、玻璃通透、窗外无高亮球体。

### 4.8 海鸥瓦面栖落
- `cottage._roof_tile_data()` 生成真实瓦面网格数据；`_make_perches()` 从瓦面/屋脊/烟囱/门廊梁向下发射射线求交点，
  生成 10 个栖点（ridge 3、eave 4、chimney 1、porch 2）；法线 y 门槛 ≥0.827（≤34°坡），脚底沿法线抬 0.03m。
- `BirdFlock` 降落状态按栖点法线插值身体姿态（最大倾角 35°），脚-瓦面间距探针 0.044–0.050m；
  同屋顶多鸟保持 ≥0.98m 间距；栖点占用/预订互斥保留；窄瓦面点标记不可用不强行停靠。

### 4.9 自动运镜快捷键
- `project.godot [input] toggle_auto_orbit`（默认 C，不与现有键冲突：WASD/方向键/空格/Tab/T/H/F2/F3/F11/Esc 已占用）。
- `_unhandled_input` 只听这一个 InputMap 动作（无重复监听）；开启后按现有自动运镜规则平滑；再按立即停止且**保留当前机位/朝向**（角速度平滑收敛，不跳回起点）。
- 手动相机操作优先：拖拽/滚轮时自动运镜让位；暂停/ESC 菜单锁视角时暂停自动运镜；HUD 右上常驻状态 + 2.6s toast，不长期遮挡。
- 可重绑定：动作是正式 InputMap 动作，可在设置中改键（沿用项目键位设置机制）。

### 4.10 炊烟双窗口
- 统一时钟：main 每帧把 `fposmod(_sim_seconds,86400)` 传给 `ChimneySmoke.set_sim_seconds`；窗口左闭右开 11:00–13:00、17:00–19:00。
- 进入窗口 1.5s ramp 渐增 `amount_ratio`；离开窗口立即停止发射（emitting=false），已有粒子自然消散（lifetime 6s）；
  跨日/重载不会重复创建发射器（`IsleFx.smoke` 幂等复用）；时间大跳时按整窗状态直接重置，不会“错过边界后补发”。
- 探针 `probe_smoke6` 96/96 断言通过（含 10:59/11:00/13:00/16:59/17:00/19:00 六边界）。

### 4.11 水面波动
- 方案：**7 组解析方向波顶点位移 + 解析法线 + CPU 完全同源**（不用 Gerstner 水平位移，避免 CPU 反解高度抖动）。
  波表：amp .420/.260/.150/.085/.050/.072/.038，波矢/角速度/相位见 `isle_waves.gd`，detail 0..3 门槛 0/0/0/0.5/1.5/1.5/2.5。
- 网格：`sea_mesh_scale` 0.6/0.8/1.0/1.2/1.4 控制岛屿周围海面网格细分（远处网格粗但不改 shader 几何，避免摩尔纹）。
- 细节：`sea_normal_detail` 两层 vnoise 有限差分法线；`sea_foam_detail` 分层浪峰泡沫 + 近岸深度泡沫；`sea_refl_detail/ssr_strength` 解析反射（云絮/低太阳暖色反光带/月光），不读屏幕纹理。
- 船与水：main 的 `_wave_h` 调 `IsleWaves.height`，与 GPU 同一帧、同一 detail、同一 wave_height，船体吃水/俯仰/横滚不抖动；
  船头浪花/船尾尾迹仍由既有 Splash/Wake 系统在解析水面高度上生成。
- 分档：低 3 波/无法线/无泡沫/无反射；中 4 波+法线 0.72+泡沫 .62；高 6 波+三层泡沫；极高/极致 7 波+法线 1.2/1.35+反射细节。

### 4.12 极致画质与后处理
- 自定义 AO（`post_ao.gdshader`）：透明队列 QuadMesh，`ALBEDO=0, ALPHA=clamp(ao)` → 屏幕 = dst*(1-ao)，
  render_priority=127，不读 screen_texture；深度重建视空间坐标，视空间半球投影采样比较深度；ao_strength 0/0/0.35/0.55/0.75。
- 解析反射：`reflect_extra` 只加不换（云絮 + 低太阳暖色反光带 + 月光），避免整屏洗白。
- 有效高级项：MSAA 8x、SSAA 1.25、TAA、云层第 4 层、Glow 1.12、曝光 1.04、灯预算 12、海网格 1.4、草 1.4、粒子 1.35。
- 无效/不支持项已明确不启用：引擎 SSAO/SSIL/SSR/体积雾对 unshaded 管线无效（实测），不切换渲染器，不把不支持特性算作已实现。

## 5. 测试执行记录

全部数字来自实跑日志（`开发产物/logs/`），未估算。

### 5.1 headless 自动化（最终代码重跑：2026-10-20 22:17）
- `--selftest`：**53 PASS / 0 FAIL**（另有 1 项「真实鼠标拖动」SKIP，headless 无 GUI 输入）——覆盖五档画质、十档时间吸附、五组音量、ESC 开/关、遮挡盒注册、炊烟时钟、自动运镜 C 键。日志 `final_selftest.log`。
- `probe_quality6`：**checks=51 fails=0**（五档 24 键类型/范围/单调性、低档保底、极致上限、override、材质映射、sea_params 键、AO/SSR 透明乘法断言）。日志 `final_quality.log`。
- `probe_water6`：**checks=17 fails=0**（7 组波与 shader 逐项一致、CPU/GPU 4320 点波高误差 0.000000m、各 detail 波数 [3,4,6,7]、1cm 步长最大跃变 0.00047m）。日志 `final_water.log`。
- `probe_settings6` 46/0；`probe_audio6` 232/0（旧 `probe_audio_p5` 85/0 兼容）；`probe_cottage6` 31/0（遮挡 15/15、实体覆盖 7/7、泄漏 0/6、栖点 10/10）；`probe_bird6` **45/0**（脚-瓦间隙 0.0000m、ridge 白天保留 3 只、max_drift 0.0、conflicts 0）；`probe_smoke6` **96/0**（11 个时间边界）；`probe_astro6` 423/0；`probe_menu6` 152/0；`probe_esc_e2e_t1` 19/0；`probe_frame_t5` 5/0。
- `--check-only`：main.gd 与队友脚本、5 个 shader 编译全部通过。

### 5.1b 第二轮（试玩反馈修复后）重跑
- `--selftest`：**53 PASS / 0 FAIL**（日志 `final_selftest2.log`）
- `probe_menu7_t1`：**50 PASS / 0 FAIL**（新增 ESC 入场可见性断言）
- `probe_quality6`：**51/0**；`probe_water6`：**17/0**；`probe_ghost6`（窗口）：**26 checks / 0 fail**
- 全部 exit 0，无 SCRIPT/SHADER ERROR。

### 5.2 窗口实跑
- 统一截图 `--shots`：最终 22:11 一次 **62 张 [SHOT]、exit 0、无 SCRIPT/SHADER ERROR**（1600×900，Forward+）。
- `--perf`：22:05 与 22:15 两次完整五档+场景采样（见 §8）。
- 队友窗口探针：T3 五档/AO/SSR 11 张（2560×1440）、T4 小屋 5 张、T5 炊烟/海鸥 6 张（2560×1440）、T1 720p/3440×1440 设置面板与 ESC 帧。

### 5.3 已知测试环境限制（影响解释，不影响结果）
- 本机 DSH 沙箱禁止 Godot 子进程写 `C:/Users`，`user://` 配置/日志/截图失败（ERR_FILE_CANT_OPEN 12）；探针与截图已统一改写到 `D:/休闲小岛幻境/开发产物/`。生产机 `user://` 正常。
- 性能采样期间团队其他探针/DSH 活动同时运行，两轮数字差异可达 35%（见 §8），因此报告给区间而非单值。

## 6. 视觉验证（真实窗口渲染）

> 证据：`开发产物/shots/`（1600×900 统一截图 + 复制入内的 2560×1440 专项图）、`开发产物/shots6/{t1,t3,t4,t5}/`（队友原始证据）。
> 以下结论来自实际 PNG 像素统计与人工目视；无法用像素证明的部分单独标注「部分验证/未验证」。

### 6.1 五档画质（同机位 12:20，2560×1440，`shots6/t3/quality_fixed_q{0..4}.png`）
| 档位 | 全图亮度 | 海面区亮度 | 岛屿区亮度 | 探针窗口 FPS | 海面网格顶点 |
|---|---|---|---|---|---|
| 0 低·流畅 | 0.5396 | 0.3562 | 0.5741 | 64.4 | 11881（108²） |
| 1 中·均衡 | 0.5812 | 0.4800 | 0.5993 | 68.0 | 21025（144²） |
| 2 高·精致 | 0.5782 | 0.4824 | 0.5830 | 89.1 | 32761（180²） |
| 3 极高·细腻 | 0.5879 | 0.4965 | 0.5881 | 40.5 | 47089（216²） |
| 4 极致·电影 | 0.5962 | 0.5057 | 0.5925 | 37.1 | 64009（252²） |

- 档间像素差：q0→q2 mean 0.0601（92.81% 像素变化）、q2→q4 mean 0.0304（91.69%）、q0→q4 mean 0.0790（96.83%）；1600×900 官方图 q0-q4 平均绝对差 23.50（54.7% 像素 >12）、q2-q4 12.33（29.8%）——五档画面确有可见差异。
- **洗白回归检查（本轮修复的 bug）PASS**：亮度差 Δlum(q3−q2)=+0.0097、Δlum(q4−q2)=+0.0180（阈值 +0.025/+0.035），饱和度比 q3=0.999、q4=1.002；目视 q2/q4 均无水洗蒙层、无竖条纹。
- AO（q4 开 0.75/1.0/16 与关）：65.35% 像素变化，整体亮度比 0.9741（约暗 2.6%，符合接触阴影预期）；`ao_debug` 岛屿区 p50=0.000 / p90=0.835 / p99=1.000、遮挡值 >0.05 占 37.12%——说明 AO 不是纯黑屏或全白噪点。
- q4 水面反射开/关：75.96% 海面像素变化，全图亮度 0.5966→0.5932（Δ−0.0034），不产生洗白。
- 目视：q0 无 MSAA/低缩放、阴影/水波最简；q4 水面细波与泡沫、云层四层、AO 接触暗部、灯数 12、草地 22500、MSAA 4×（msaa=3）+TAA，层次最好且无过曝。

### 6.2 水面波动
- `05_water_ultra.png` 与 `05_water_low.png`（同机位 06:xx 海面）：低档是低成本法线细纹；极致档可见 7 组方向波叠加的连续波峰/波谷、暖色低角度反射与近处细节，远海无明显几何畸变。
- T3 窗口水面对照（`shots6/t3/t3_water_ultra.png`、`t3_water_low.png`）：ultra 可见波峰高光与泡沫，low 仅细纹。
- 船体/尾迹/水花：`04_boat_wake_close.png`、`04_splash.png` 复核仍正常，船与水面未出现大面积穿插（顶点位移仅视觉网格，船浮动用同一 `IsleWaves.height` 采样）。
- 海岸泡沫：q2 起按 `sea_foam` 增强，`05_quality_high.png` 岛缘白色浪线连续，无边缘漏洞。

### 6.3 日月与天空
- 日出方位：`02_sunrise_sky.png`（07:12）HUD 罗盘 115°，天文计算 az=115.15°；日落：`02_sunset_sky.png`（17:51）HUD 244° vs 245.03°；`04_sky_up.png` 仰视 244° vs 244.26°；`01_night.png` 夜空 315° 与期望 317.6° 一致——旧镜像公式会显示相反值，证明坐标映射修复由真实渲染确认。
- `01_sunrise.png / 01_golden.png / 01_sunset.png / 01_dusk.png / 01_night.png` 与 `02_*_sky.png`：日出前地平线渐亮、金色时段暖色带、日落沿正确方位下降并自然退出、入夜星空/月亮渐显，无「日出瞬间创建太阳」跳变。
- 月亮：夜间 `01_night.png`/`04_sky_up.png` 可见月亮，位置由统一时间驱动（probe_astro6 423/0：日出 max 3.2s、日落 2.5s、太阳方位 0.001°、月出 5.4s、月亮方位 0.013°）。

### 6.4 ESC 菜单入场动画（`07_menu_*.png`，1600×900）
- `07_menu_enter_012.png`：letterbox 展开、菜单项尚未入画（第一项仍在屏外）。
- `07_menu_enter_042.png`：标题与「继续观景/设置/离开」半透明、错峰进入中（0.52s+0.04s×7=0.80s、ease_out_back）。
- `07_menu_stable.png`：完整菜单，「继续观景」橙色高亮，动画结束恢复交互。
- `07_menu_exit_018.png`：反向淡出/位移残影。真实 ESC 路径（非直接调 open/close）由注入 Escape 事件拍摄；动画期禁点、半途再按 ESC 反向不叠加，由 `probe_esc_e2e_t1` 19/0 与 `probe_menu6` 152/0 覆盖。

### 6.5 灯塔光束与墙体遮光（**部分验证**）
- `06_beam_ground_occluded.png`：光束扫过时地面/码头出现被照亮的亮区，而小屋整体未被穿亮，符合「光只落在未被遮住的位置」。
- 静态数学：`probe_cottage6` 31/0——ray-box 遮挡 15/15（近光侧 occl=1.000；背光墙/屋后地面/室内/阁楼内 0.060）、实体覆盖 7/7、泄漏 0/6、3 个 yaw=−0.300 的 AABB；shader 内射线-AABB 是 stay>0.20m 起挡、>1.20m 全挡，`blit*=occlusion`。
- **如实说明**：`06_beam_house_side` 与 `06_beam_house_side_off`（光束 +180°）同机位目视几乎一致——该机位光束体积感弱，墙面暖色主要来自室内点光泄漏；因此「背光侧明显更暗」只有数学与广角图支持，未获得理想的前后对比图。原因见 §9（toon 为 unshaded 解析光，点光无引擎阴影）。

### 6.6 阁楼玻璃（`06_attic_window_night.png`，2560×1440）
- 夜间可清楚看到室内书桌、台灯、椅子、地毯、地板与内墙；玻璃通透，无窗外独立高亮光球（已删除阁楼窗外 2.10 的 halo，`window_halos` 6→5）。
- 双层独立低反射玻璃（外层 opacity .020/tint .10/f0 .030/refl .34；内层 .014/.08/.026/.26；双层透过率≈0.817），未改动其他窗户材质。

### 6.7 海鸥瓦面栖落（2560×1440 专项，`shots6/t5/`）
- `06_bird_roof_t5.png`（10:00 官方机位）：屋脊 3 只（ridge_1/ridge_2/ridge_0），每只 `foot_gap=0.0000`，画面可见 2 只脚踩脊瓦；`day_bird_ridge_close_t5.png` 近景同样脚-瓦间隙 0。
- `dusk_bird_roof_close_t5.png`（19:20，屋面 6 只 = 屋脊×3 + 檐口 RP/LP/RN）与 `night_bird_roof_close_t5.png`（22:10，bird7 在 eave_LP）脚明确压在筒瓦上、无穿瓦；`probe_bird6` 45/0、`max_drift=0.0`、`conflicts=0`。

### 6.8 炊烟双时间窗（`06_smoke_noon.png` + `shots6/t5/`）
- 官方 22:11 图 `06_smoke_noon.png`（12:10，q2）：烟囱上方烟柱清晰可见，屋脊同时有 3 只海鸥；T5 近景 `06_smoke_noon_close_t5.png` 更清楚（`emitting=true ratio=1.0 amount=60 lifetime=7.0 created_count=1`）。
- 边界由 `probe_smoke6` 96/0 覆盖：10:59 关、11:00 开、13:00 关、16:59 关、17:00 开、19:00 关，`created_count` 恒 1（无重复创建发射器），跨午夜/回拨正确。

### 6.9 负面/未确证结论（不隐瞒）
- 光束「体积」在静帧中很弱，透明锥近似无法与真实体积散射相比。
- 音频无主观听感验证（本机无音频输出设备），仅频谱/总线/参数验证。
- 4K 未做长时间 3D 实跑（仅设置面板 720p/3440 布局截图）。
- 极致档实跑 40.9–63.0 fps（RTX 2060、1600×900），非「任何设备都能开」。

## 7. 验收清单状态

状态定义：**通过** = 真实运行/像素或探针实测满足要求；**部分** = 已实现且静态+自动验证通过，但某一项视觉或主观验证不完整；**未验证** = 未实跑。

| # | 检查项 | 要求 | 状态 | 证据 |
|---|---|---|---|---|
| 1 | 画质档位 | 五刻度与五档一一对应 | **通过** | UI 5 tick + probe_settings6 46/0；五档截图可见差异 |
| 2 | 极致画质 | 真实可见提升 + 性能已检查 | **通过（性能见 #19）** | q4 vs q2 91.69% 像素变化、AO/SSR/云/水细节；FPS 40.9–63.0 |
| 3 | 分辨率 | 常见档位，UI/3D 正常适配 | **部分** | 720p/1600×900/3440×1440 面板与 HUD 布局通过（T1 probe 152/0、截图）；4K 未实跑 |
| 4 | 时间流速 | 十档「每游戏日耗时」 | **通过** | probe_settings6 十档 label/吸附；UI「10 分钟 / 游戏日」；selftest |
| 5 | 时间统一 | 天体/船/鸟/炊烟/灯塔同一时钟 | **通过** | 单一 _sim_seconds 驱动；selftest 炊烟时钟/遮挡盒；probe_astro6 |
| 6 | 夜间音频 | 火焰/蟋蟀不再刺耳 | **部分** | 重制素材：>8k 能量 11.67%→0%、夜循环 2–6k 47.3%→10.7%、接缝 1.69→−0.02dB；**无主观试听** |
| 7 | 音量控制 | 主/环境/鸟鸣/火焰/音效独立 | **通过（听觉未验证）** | 5 总线+效果链；probe_audio6 232/0（路由/dB/0 mute/持久化） |
| 8 | 太阳位置 | 与岛屿朝向及广州位置协调 | **通过** | HUD 罗盘 vs 天文 az 差 <1°（115/244/317 实测）；probe_astro6 423/0 |
| 9 | 月亮位置 | 随日期时间运动、不消失 | **通过** | Meeus 47 表 + 统一时钟；夜间截图可见；月出/月没误差 5.4s/3.8s |
| 10 | 日出日落 | 天空/太阳/环境光自然过渡 | **通过** | 01_sunrise/golden/sunset/dusk/night + 02_*_sky 图；无瞬时创建 |
| 11 | ESC 菜单 | 屏外进入、开闭动画稳定 | **通过** | 07_menu_* 四帧；0.80s 错峰、禁点、反向；probe_esc_e2e_t1 19/0 |
| 12 | 墙体遮光 | 灯塔光不穿实心房屋 | **部分** | probe_cottage6 31/0（15/15 遮挡、0/6 泄漏）+ 06_beam_ground_occluded；前后对比图区分度弱 |
| 13 | 阁楼玻璃 | 透明可见家具；光球移除 | **通过** | 06_attic_window_night 清楚见书桌/台灯/地毯；halo 6→5 |
| 14 | 海鸥落点 | 站瓦面、无穿模 | **通过** | 06_bird_roof_t5 / night+dusk close：foot_gap 0.0000；probe_bird6 45/0 |
| 15 | 自动运镜 | 快捷键开关、不冲突 | **通过** | InputMap toggle_auto_orbit=C；selftest C 键保留机位；HUD 指示+toast |
| 16 | 炊烟 | 11–13 / 17–19 两窗 | **通过** | 06_smoke_noon 烟柱；probe_smoke6 96/0 全边界 |
| 17 | 水面波动 | 可感知起伏、船水自然 | **通过** | 7 组 Gerstner；05_water_ultra/low；probe_water6 17/0（CPU=GPU） |
| 18 | 画质兼容性 | 高级效果与渲染器兼容 | **通过** | 明确不启用引擎 SSAO/SSIL/SSR/体积雾（unshaded 无效），自研 AO/解析反射；未切渲染器 |
| 19 | 性能 | 无明显泄漏/不可接受回退 | **部分** | 两次实跑（§8）：q2 122–137fps，q4 41–63fps/VRAM 878MB；共享环境波动 ±35% |
| 20 | 回归测试 | 船只/灯塔/海鸥/草地/时间正常 | **通过** | selftest 53/53、旧探针 probe_bird_p5/audio_p5 通过、--shots 62 张无脚本错误 |
| 21 | ESC 菜单错位（试玩反馈） | 控件水平、入场全程可见 | **通过** | probe_menu7_t1 50/0；13a/13/13b/14 窗口截图 |
| 22 | 高画质阁楼窗重影（试玩反馈） | q2+ 无重影且 AO 仍生效 | **通过** | probe_ghost6 26/0；窗洞亮度比 .995/.992/.989；comparison_ao_ghost.png |
| 23 | HUD 自动运镜提示（试玩反馈） | 界面内可见 C 键与状态 | **通过** | 15_hud_c_hint_1600x900.png |

## 8. 性能

### 8.1 测试环境与方法
- 机器：AMD Ryzen 5 2600X（6C12T）/ NVIDIA GeForce RTX 2060 / 16GB RAM / Windows 10 19045；驱动 32.0.16.1742。
- 渲染：Godot 4.7.2 Forward+，窗口 **1600×900**（--resolution 1920x1080 被 _apply_resolution 在截图/性能模式下跳过，故所有数字是 1600×900），vsync 关闭，采样期间强制 Engine.max_fps=0（否则 q0/q1 预设的 60 上限会掩盖真实成本）。
- 方法：固定 6 机位各采样 180 帧；再跑五档 _apply_quality(4..0) 循环；--shots/--perf 与团队其他探针共享同一台机器，两轮之间负载不同。

### 8.2 场景采样（quality=2「高·精致」，1600×900）
| 场景 | run1 22:05 fps / frame_ms | run2 22:15 fps / frame_ms |
|---|---|---|
| noon_clear | 122.4 / 8.17 | 136.9 / 7.30 |
| golden_cloud_water | 133.8 / 7.47 | 108.5 / 9.22 |
| night_shadows | 121.6 / 8.22 | 120.2 / 8.32 |
| night_close | 136.9 / 7.30 | 137.0 / 7.30 |
| far_island | 113.2 / 8.83 | 133.3 / 7.50 |
| sky_up | 132.8 / 7.53 | 64.3 / 15.54 |
| time_panel_open | 112.5 / 8.89 | 67.3 / 14.85 |
| lite_noon_nomultimesh | 148.2 / 6.75 | 118.8 / 8.42 |
| lite_night_nomultimesh | 137.5 / 7.27 | 87.2 / 11.46 |

- 场景 objects ≈ 1980–2087、draw_calls ≈ 1245–1720、VRAM ≈ 348.5MB（q2）。
- lite_*（无 MultiMesh 草/云/水波对照）在 run1 略快于完整场景，run2 因负载反而更慢——说明该机共享负载噪声大于这些优化项的收益，不能据此断言单项成本。

### 8.3 五档画质成本（同一次运行内循环，1600×900）
| 档位 | run1 fps / ms | run2 fps / ms | VRAM | MSAA/3D scale | 草实例 | 解析灯数 |
|---|---|---|---|---|---|---|
| 4 极致 | **63.0 / 15.87** | **40.9 / 24.43** | 877.6MB | 4× / 1.25 | 22500 | 12 |
| 3 极高 | 80.8 / 12.37 | 63.7 / 15.70 | 757.7MB | 4× / 1.15 | 22500 | 10 |
| 2 高 | 134.5 / 7.44 | 121.9 / 8.20 | 350.5MB | 2× / 1.00 | 22500 | 8 |
| 1 中 | 126.5 / 7.91 | 98.3 / 10.17 | 258.7MB | 1× / 0.92 | 15750 | 6 |
| 0 低 | 162.3 / 6.16 | 143.9 / 6.95 | 217.8MB | 0 / 0.85 | 10125 | 4 |

- 两轮差异最大 35%（q4、sky_up、q1 cpu 采样出现 142–198ms 尖峰），属于共享桌面与采样窗口噪声；**报告结论取区间**：q2 在 1600×900 稳定 120fps 以上，q4 在 41–63fps、VRAM 878MB。
- q4 的 MSAA 4×（msaa=3）+ 3D scale 1.25 是主要成本（等效渲染像素 ~1.56×），其次 12 个解析灯与 AO；这与「极致档需要较强 GPU」的预期一致。
- 稳定性：退出前 after_6s 场景节点约 1600、orphan 24–52；退出时的 RID/ObjectDB 警告属于关闭清理顺序（引擎在 --quit 下常见），运行期无持续增长（连续 6 场景 objects/draw_calls 不单调上升）。

### 8.4 结论
- 中档（默认 q2）在当前机器 1600×900 可稳定 120fps+，具备 60fps 余量；低档 q0 最快、适合弱机；q3 约 64–81fps；q4 41–63fps 属「有强 GPU 才建议开」。
- 未在低端集显/4K 下测；未做帧时间 p99 / GPU timestamp（引擎无简单接口），只给平均 fps/CPU/VRAM，不虚构更深指标。

## 9. 限制与未完成事项

1. **渲染管线限制（最重要）**：本项目所有可见对象使用自定义 unshaded 着色器（toon/sea/sky/glass/grass/beam），Forward+ 的引擎级 SSAO/SSIL/SSR/体积雾/软阴影对它们实际不生效（T3 已实测并记录在 docs/P6_RESEARCH_VISUAL.md）。因此本轮 AO 是自研 depth 半球后处理、反射是解析天空/太阳/月亮近似、玻璃是双面低反射近似——不是引擎原生效果。未切换渲染器（避免整体重写与兼容风险）。
2. **无 Light3D / 无引擎阴影**：灯塔探照灯与室内灯都是着色器解析光斑；墙体遮光用射线-AABB 遮挡（0.2–1.2m 过渡）近似。室内点光无阴影会溢到外墙（T4 标注），导致 06_beam_house_a/b 中山墙大面积暖色，光束体积感弱。彻底修复需给解析光重建 shadow map 或改用 Light3D，超出本轮预算，列为后续方向。
3. **水面顶点位移仅视觉**：GPU 顶点位移不写回 CPU，不改变碰撞/靠泊/物理；船舶浮动与波高采样共用 IsleWaves.height（CPU/GPU 同源，误差 0.000000m），所以船不会因渲染网格位移而物理穿插，但极端波峰边缘与岸线泡沫仍是视觉近似。
4. **音频无主观听感验证**：本机无可用音频输出设备。fire_crackle.wav 与 night_loop.wav 是程序化合成素材（非录音采样），已重制并做频谱/接缝/总线/dB/播放活性验证，但「是否仍刺耳」需在有音箱/耳机的机器上试听；若仍不满意，按 §4.3 的替换/删除流程处理。
5. **分辨率与高 DPI**：性能数据在 1600×900；4K/21:9 只验证了 T1 的设置面板与 HUD 布局截图（720p、3440×1440），未在 4K 下长时间跑 3D。窗口切换有 12s 自动回退确认层防止黑屏锁死。
6. **天文精度**：NOAA 太阳 + Meeus 47 表月亮近似，不含本地地平遮挡、地形遮蔽与精细大气折射积分；实测误差日出 3.2s / 日落 2.5s / 太阳方位 0.001° / 月出 5.4s / 月亮方位 0.013°。文档中标注为近似，不宣称完全精确天文模拟。
7. **极致档成本**：RTX 2060 @1600×900 下 q4 仅 41–63fps、VRAM 878MB；低端设备需降档。无自动降档（按要求不频繁自动切档），仅 HUD 可提示。
8. **测试环境沙箱**：本机 DSH 沙箱禁止 Godot 子进程写 C:/Users，user:// 配置/日志/截图报错（错误 12）；生产机无此限制。探针、截图、性能日志已改写到 D:/休闲小岛幻境/开发产物/。
9. **headless 限制**：真实鼠标拖动只能窗口测（selftest 中 1 项 SKIP）；headless 读不到 MultiMesh 实例变换，屋面海鸥几何校验走 cottage 共享 _roof_tile_data/_roof_cap_data（PASS）。
10. **光束体积**：灯塔光束为透明锥体近似，无真实体积散射/被遮挡的体积衰减；静帧观感偏弱。仍保留 beam_occlusion 使光斑本身正确被墙遮挡（这是验收点），视觉体积非验收硬指标。

## 10. 附录：命令与日志

- 引擎：`D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe`（headless/脚本）与 `..._win64.exe`（窗口）
- 统一截图：`pwsh 开发产物/run_shots6.ps1`（日志 `开发产物/logs/shots6_final_*.log`）
- 统一性能：`pwsh 开发产物/run_perf6.ps1`（日志 `开发产物/logs/perf6_all_*.log`）
- 探针：`Godot ... --path 游戏工程 --script res://tools/probe_*.gd`（headless）；窗口探针见 `开发产物/shots6/t3/`
- 已知环境限制：Godot 子进程在本机被限制写 `C:/Users`，`user://` 配置/日志/截图会失败（错误 12 ERR_FILE_CANT_OPEN）；
  探针与截图脚本已统一改写到 `D:/休闲小岛幻境/开发产物/`。生产机 `user://` 正常，此限制不影响项目代码。

## 11. 试玩反馈修复（P6.1）

> 触发：交付后用户实机试玩反馈 3 个问题。用户证据图：`开发产物/shots6/feedback/user_menu_rotated.jpg`（菜单错位）、`user_ghost_attic.jpg`（阁楼窗重影）。以下结论全部来自实际运行与窗口截图，不是静态推断。

### 11.1 ESC 菜单旋转错位 / 入场期间控件不可见

- **现象**：ESC 菜单标题「休闲小岛幻境」与「继续观景/设置/离开」全部斜向旋转约 −18°~−39°、彼此错位（用户截图）。
- **根因（代码审计 + 探针复现）**：标题菜单点击开始游戏走 `scripts/menu.gd` 的 `_fly_out()` 螺旋飞出，它给 8 个 item 写入 `ctl.rotation = spin*p*1.1`（±0.682 rad ≈ 39°）与 `scale=0.9`，收尾只把 item 设为 `visible=false`；游玩中按 ESC 走 `open(true)` 的 returning 入场分支，`_apply_anim` 只写 position 与 modulate，从不复位 rotation/scale，于是残留到 ESC 菜单。`open(false)`（标题菜单）分支本来有复位，而旧 `--shots` 自动化在开场用 `instant_finish()` 跳过螺旋关闭，所以自动截图从未暴露。
- **复现中追加发现**：`_fly_out` 收尾写入的 `visible=false` 同样没有被 returning 入场恢复 → 真实游戏里 ESC 菜单整个 0.80s 入场动画期间控件是隐形的，动画结束才突然出现。
- **修复**（`游戏工程/scripts/menu.gd`，10 处 + 1 处）：
  - 新增 `_fly_tweens` 数组、`_kill_fly_tweens()`、`_reset_items_transform()`；
  - `_apply_anim` 每帧强制 `rotation=0`、`scale=Vector2.ONE`；
  - `_on_enter_done`/`_on_exit_done`/`open()`/`close()`/`instant_finish()`/`_fly_out` 收尾统一复位并清理 tween（防重复动画竞争）；
  - `_start_enter_anim` 开头对所有 item 置 `visible=true`。
- **验证**：`tools/probe_menu7_t1.gd` **50 PASS / 0 FAIL**（手工注入旧残留 rotation=0.62/scale=0.9 后再 `open(true)`，0.12s 采样 max_rot=0.00000、max_scale_err=0.00000、结束 pos_home_err=0.00px；新增入场可见性断言）。`probe_menu6` 152/0、`probe_esc_e2e_t1` 19/0、`--selftest` 53/53。
- **窗口截图**（1600×900，真实 main + isle.tscn，开始游戏→ESC 打开）：`13a/13/13b_esc_menu_enter_*_1600x900.png`（t≈0.43/0.55/0.70s，控件水平滑入、8/8 可见）、`14_esc_menu_stable_1600x900.png`（稳定态无旋转）。

### 11.2 「高」及以上画质阁楼窗重影

- **现象**：q2「高」及以上档位，夜间正面阁楼落地窗出现整扇窗框 + 3×3 窗棂的偏移半透明暗影，屋顶轮廓外出现黑色糊块（用户 05:14 截图）。
- **隔离（窗口矩阵，同机位 05:14，冻结 main._process 防机位漂移，2560×1440）**：
  - q2 开 AO vs 关 AO：**30.8%** 像素变化，窗洞区亮度比 **0.496**（被压暗一半）；q3 **0.410**；q4 **0.369**。
  - TAA 开/关：mean=0.00137、仅 5.64% 像素，窗洞亮度不变；玻璃层全关 mean=0.0004；refract .006 mean=0.0002；q4 scale 1.0 mean=0.0015 → 全部排除。
  - 结论：**自定义 PostAO 后处理**（q2 正是第一个 `posts_ao=true` 的档位，与用户“高及以上才出现”完全吻合）。
- **机理**：`shaders/post_ao.gdshader` 视空间半球采样存在四个缺陷：①遮挡深度差无上限（室内 15m 处把前方 6.4m 的窗棂/窗框当遮挡）；②0.9–1m 世界半径在 6.4m 视距的屏幕投影偏移达窗宽 10%+，于是每个室内像素被前景框条压出“窗棂暗副本”；③轮廓邻域深度含天空时法线退化 → 黑色糊块；④强度映射 ×3.2/×2.4 会饱和成全黑。
- **修复**（只改 `shaders/post_ao.gdshader`；main 的 uniform 名与挂载方式完全不变）：
  1. 每样本遮挡深度差上限 `lim = rr*1.8 + ao_bias`，超出不算遮挡并 smoothstep 淡出；
  2. 四邻深度有效且视距跳变 <`max(ao_radius*2, view_dist*0.05)` 才重建法线，轮廓像素不施加 AO；
  3. 温和映射 `ao = clamp(pow(occ*1.35, ao_contrast),0,1)*ao_strength`；
  4. 投影偏移上限 0.30 + 近/远淡出。仍是透明 pass 纯乘法叠层（ALBEDO=0, ALPHA=ao），不读屏幕纹理。
- **修复后实测**：
  - 窗洞亮度比 q2 **0.995** / q3 **0.992** / q4 **0.989** → 鬼影不可察觉；
  - AO 并未被“糊弄关掉”：开/关像素差 q2 5.14%、q3 8.56%、q4 10.38%；12:20 岛景机位 13.28% 像素、岛屿亮度比 0.9942、ao_debug p90 0.235；
  - 不洗白：q4 全图亮度 0.2532 < q2 0.2274+0.03；档间差异仍明确（q0→q2 77.68%、q2→q4 80.93% 像素）；
  - AO pass 成本 q2 **+1.14ms**、q4 **+1.93ms**（12 采样）。
- **证据**：`tools/probe_ghost6.gd` 窗口 26 checks/0 fail（56.8s）；对比图 `开发产物/shots6/ghost/comparison_ao_ghost.png`（用户反馈 | 修复前 q2/q4 | 修复后 q2/q4），全套 `ghost_f_q0..q4` 与 AO/TAA/玻璃/refract 对照、`ghost_island_ao_on/off/debug`。

### 11.3 游戏内自动运镜快捷键提示

- `scripts/hud.gd`：右上操作提示行加入「C 自动运镜」；右上常驻状态改为「◉ 自动运镜 · 开 · 按 C 切换」/「○ 自动运镜 · 关 · 按 C 切换」；按 H 隐藏界面时一并隐藏。
- 截图：`开发产物/shots6/t1/15_hud_c_hint_1600x900.png`。

### 11.4 回归与残余风险

- 最终代码重跑：`--selftest` **53/53**、`probe_menu7_t1` **50/0**、`probe_quality6` **51/0**、`probe_water6` **17/0**、`probe_ghost6` **26/0**，全部 exit 0。
- 残余风险：TAA 在相机快速运动时仍有引擎官方已知的历史拖影（本场景静止不可见；q4 瞬时转 2° 抓帧 diff 0.00287/16.24%，TAA 关为 0），**不是本次重影根因**。若后续用户报运动拖影，可在 q3/q4 关闭 TAA 或降权重（需新增参数）。AO 在轮廓像素有意跳过：极细草叶的接触感略弱但无脏边；玻璃不写深度故不产生 AO，属预期。

