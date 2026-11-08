# P8 阶段 6 天气视觉测试报告

- 阶段：P8 Weather & Seasons / 阶段 6「天气视觉」
- 日期：2026-10-22
- 分支：`p8-weather-seasons`（基线 P7-V4 `ae9d104`）
- 引擎：Godot 4.7.2-stable（Forward+，Vulkan 1.4.351）
- 设备：RTX 2060 / 1600×900 / 画质档 2（另测 0、4 档）
- 本报告只记录**已跑通并有截图/日志证据**的内容；未验证项列入「已知限制」。

## 1. 实现构成（阶段 6）

| 模块 | 文件 | 说明 |
| --- | --- | --- |
| 共享天气参数 | `scripts/main.gd` `_setup_globals` / `_update_weather_fx` | `g_weather=(rain,snow,wet,snow_cover)`、`g_weather2=(cloud,storm,wind,indoor)`、`g_wind_dir=(dir_x,dir_z,strength,phase)`、`g_lightning`。全部启动注册一次，每帧 set，不重编译。 |
| 降水粒子 | `scripts/isle_weather_fx.gd`、`shaders/precip.gdshader` | 雨/雪各一个 GPUParticles3D，跟随相机水平位置并被限制在岛与近海；单 draw pass，不建逐滴节点。 |
| 室内剔除 | `shaders/precip.gdshader` + 小屋 `beam_occluders` 盒 | 逐粒子把进入小屋实体盒的雨雪淡出；相机在室内时窗外仍能看到雨雪，不是整套关掉。 |
| 屋檐滴水 | `_place_weather_drips` + 滴水粒子 | 按屋顶前坡外挑 0.46 m、檐口低于主体盒顶 0.33 m 定位，中雨以上出现。 |
| 地面水花 | `shaders/splash.gdshader` + MultiMesh | 220 个环形水花，只在下雨且无积雪覆盖时出现。 |
| 湿地/积雪 | `shaders/toon.gdshader` | 湿润压暗 + 掠射反光；积雪只挂朝上的面，按世界坐标噪声打散、低海拔淡出；草叶随积雪加深淡出。 |
| 全局配光 | `main.gd` `_grade_palette_for_weather` | 在调色板结果上做冷灰混合与压暗，不替换天文/调色板算法，也不叠黑罩。 |
| 台风 | 复用 sky/sea/grass/toon 参数 | 云量/云速/风力/海面风暴压暗/雨丝倾斜/浪花增强；海面 7 组波系数不动（isle_waves.gd 与船体浮力同源）。 |
| 闪电 | `_update_lightning` + sky/toon/grass/sea | 雷暴/台风/大雨 storm>0.55 时，4.5~13 s 随机间隔整场瞬时提亮；受雾衰减，远处远岛不会被点亮成白块；模拟暂停时亮度冻结。 |
| 落叶风场 | `scripts/fx.gd` `leaves` + `_update_weather_fx` | 落叶方向/横漂/下落速度由同一套风场驱动；叶形贴图改为椭圆收尖。 |

## 2. 截图证据（15 张，1600×900）

目录：`开发产物/p8/weatherfx/`。全部使用**固定日期 + 手动天气 + 暂停**拍摄，可复跑，不依赖现实时间。

| 文件 | 内容 | 结论 |
| --- | --- | --- |
| `p8_wfx_00_summer_clear.png` | 7/15 12:20 晴 | 基准晴日，天气视觉不介入 |
| `p8_wfx_01_summer_overcast.png` | 同刻阴天 | 云量 0.82、天色压灰、海面转冷，无雨 |
| `p8_wfx_02_summer_heavy_rain_day.png` | 同刻大雨（累积 900 s） | 雨丝、雨雾、湿地、海面雨纹同时成立；不靠黑罩压暗 |
| `p8_wfx_03_summer_heavy_rain_night.png` | 7/15 21:40 大雨 | 夜间雨丝仍可见，窗灯/路灯/灯塔光束正常 |
| `p8_wfx_04_autumn_typhoon.png` | 9/20 15:30 手动台风 | 云量 1.0、风暴 1.0、雨丝倾斜、海面白沫+压暗、秋树 |
| `p8_wfx_05_winter_heavy_snow_day.png` | 1/15 10:30 大雪（累积 30000 s） | 地面/屋顶/树冠上表面渐积雪；沙滩低海拔不刷白 |
| `p8_wfx_06_winter_snow_tree.png` | 树旁近景 | 树冠上白下绿按法线过渡，不是整树刷白 |
| `p8_wfx_07_winter_snow_night.png` | 1/15 21:10 中雪 | 暗天色下雪仍可见 |
| `p8_wfx_08_rain_indoor.png` | 室内机位 + 大雨 | 屋内无雨丝；窗外仍在下雨（逐粒子剔除而非整套关闭） |
| `p8_wfx_09_rain_ground_close.png` | 地面近景 + 大雨 | 地面湿润变色，水花环可见（部分被踏石深度遮挡属正常） |
| `p8_wfx_10_rain_eave_close.png` | 正面屋檐近景 | 屋檐下连续滴水线 |
| `p8_wfx_11_rain_splash_close.png` | 水花锚点俯拍 | 水花环与中心溅射几何可见 |
| `p8_wfx_12_rain_low_quality.png` | 最低画质（q0）大雨 | 仍能看出下雨（数量降但非零） |
| `p8_wfx_13_summer_thunder_flash.png` | 7/15 21:40 雷暴 + 闪电峰值帧 | 整场被冷白瞬光照亮；闪电按反照率提亮并受雾衰减；暂停时亮度冻结，便于取证 |
| `p8_wfx_14_autumn_leaves_wind.png` | 10/20 16:30 秋季强风 + 树旁近景 | 落叶随风横向漂移、下落变快；数量随秋季权重 |

复跑命令：

```
"D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe" --path "D:/休闲小岛幻境/游戏工程" --resolution 1600x900 -- --p8wfx
```

日志：`开发产物/p8/logs/p8wfx_stdout_stage6h.log`（exit 0，SCRIPT ERROR 0）。

## 3. 自动化测试

| 测试 | 结果 | 日志 |
| --- | --- | --- |
| headless `--selftest` | **70/70 passed**（原 68 + 阶段 6 两条：降水系统与室内剔除数据就绪 / 低画质仍保留降水且积雪随降雪累积） | `开发产物/p8/logs/selftest_stage6_final.log` |
| `tools/probe_p8_weather.gd` | **3135 checks / fail 0**（类型合法性、分季权重、确定性、暂停冻结、手动跨季回退） | 终端输出 `PROBE_P8_WEATHER RESULT: PASS` |

## 4. 性能（`--p8perf`，同机同机位对比）

命令：`--p8perf`（RTX 2060 / 1600×900 / VSync off / 岛固定机位 / HUD 隐藏，每场景采样 180 帧）。
日志：`开发产物/p8/logs/p8perf_final.log`。

| 场景 | q | FPS | frame ms | draw calls | VRAM MB |
| --- | --- | --- | --- | --- | --- |
| 晴 clear | 2 | 180.0 | 5.56 | 1838 | 272.5 |
| 阴 overcast | 2 | 176.9 | 5.65 | 1838 | 272.5 |
| 大雨 heavy_rain | 2 | 169.2 | 5.91 | 1853 | 272.6 |
| 雷暴 thunder | 2 | 176.7 | 5.66 | 1842 | 272.6 |
| 大雪 heavy_snow | 2 | 176.6 | 5.66 | 1839 | 272.6 |
| 台风 typhoon | 2 | 174.5 | 5.73 | 1841 | 272.6 |
| 大雨 q0 | 0 | 177.0 | 5.65 | 1840 | 168.9 |
| 大雨 q4 | 4 | 106.6 | 9.38 | 1841 | 625.9 |

结论：
- 降水只增加 **15 个 draw call**（雨/雪/滴水/水花/落叶节点），不是逐滴节点；大雨相对晴天的帧率代价约 **−6.0%**（同机位同 harness）。
- 低画质（q0）帧率与晴天几乎持平，且雨仍可见；高画质（q4，MSAA3+1.25 缩放+12 灯）主要开销来自既有画质档，不是天气系统。
- 本表与阶段 1 的 136.6 FPS 基线**不可直接比较**（相机、HUD、采样 harness 均不同），只用同表内相对差值。
- 打印的 `rain/snow` 已改为实际投影值（此前误读不存在的 state 键恒 0）。

## 5. 已知限制（诚实登记）

1. 闪电是整场瞬时提亮，没有可见的锯齿状闪电柱/分叉；雷暴的辨识度依赖亮度脉冲+雨+云。
2. 水花环远景基本不可见（设计为「少量地面水花」），近景才看得清。
3. 雨是局部粒子域（岛与近海），不是屏幕空间雨幕；远海没有雨丝，超出域外会看到边界淡出。
4. 雪在树冠上按法线过渡，冠底仍有部分绿色（上白下绿），不是逐资产雪帽。
5. 室内剔除只针对小屋主体盒；其他建筑/灯塔内部不适用（当前无室内相机可进入）。
6. 落叶为圆形/椭圆风格化纸片，不是逐叶模型；数量随季节与画质缩放。
7. 台风海面增强只调既有 uniform，不做独立浪型/泡沫几何。
8. 远岛在闪电峰值会略微提亮（已按雾衰减压到可接受，但非零）。
9. 低画质降雨量按 `particle_density` 降，但仍保证 >0.05 amount_ratio。
10. 闪电间隔由天气种子与视觉时钟决定，仅影响观感，不写入权威模拟状态；暂停冻结是刻意行为。

## 6. 复跑与回滚

- 复跑视觉：`--p8wfx`；性能：`--p8perf`；自测：`--selftest`。
- 回滚：`git reset --hard p8-5-weather`（阶段 5 冻结点），截图/日志在 `开发产物/p8/` 不受影响。
