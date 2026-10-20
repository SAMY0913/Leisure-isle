# P6 视觉技术调研与实现（T3）

> 目标：把"休闲小岛幻境"从 P5 的三档粗粒度画质，升级为 **五档电影感画质**，
> 且每一档的差异都在本项目的**自定义 unshaded 渲染管线**里真实可见。
> 环境：Godot 4.7.2 stable / Forward+ / Vulkan / 纯 GDScript / 无外部美术资源。

## 1. 渲染器限制（实测结论，决定方案）

本项目 toon / sea / sky / glass **全部是自定义 unshaded 着色器**（不读引擎光照/阴影/环境光），
因此引擎内置后处理对画面几乎无效：

| 引擎特性 | 对 unshaded 管线是否有效 | 结论 |
|---|---|---|
| SSAO / SSIL | 无效（需要深度+法线来自引擎不透明几何，且 AO 只作用于引擎 PBR 材质） | 不用；改为自定义 AO |
| SSR (Environment SSR) | 无效（只对引擎 PBR/StandardMaterial 生效） | 不用；在 sea.gdshader 里做近似 SSR |
| 阴影贴图 / 实时点光 | 基本无效（unshaded 不采样 shadow map / light） | 灯预算改为"片元内自算点光数量" |
| Glow / tonemap / adjustment | **有效**（屏幕空间后处理，对所有渲染结果生效） | 保留并纳入档位 |
| MSAA / SSAA(3D scaling) / TAA / FXAA | **有效**（影响全屏） | 作为基础档位差异 |
| 雾（Environment fog） | 无效（unshaded 不采样） | 自定义 shader 内 fog 公式 |
| 体积雾 | 效果极弱且贵 | 不用（保留开关位） |

补充实测（Godot 4.7.2，headless dummy renderer 也会编译 shader，可用于校验）：
1. **用户函数内不能引用 stage built-ins**：PROJECTION_MATRIX / CAMERA_POSITION_WORLD /
   INV_PROJECTION_MATRIX / VIEW_MATRIX 放进自定义函数体报 "Unknown identifier"，
   必须在 vertex()/fragment() 内联，或作为参数/普通 uniform 传入。
2. fragment 阶段**没有 SCREEN_PIXEL_SIZE**（inline 也报错），替代 `vec2 px = 1.0 / max(VIEWPORT_SIZE, vec2(1.0))`。
3. Godot 4.7 的 fragment() **禁止 return**（用嵌套 if/else）。
4. 全屏后处理读深度必须用 **spatial shader + QuadMesh 铺满**（canvas_item 不能读 depth texture）。

## 2. 五档预算与差异点

参数唯一数据源：`scripts/isle_quality.gd`（24 键，`KEY_SPECS` 定义类型/范围/默认）。

| 键 | 低·流畅 | 中·均衡 | 高·精致(默认) | 极高·细腻 | 极致·电影 |
|---|---|---|---|---|---|
| msaa_3d | 0 | 1(2x) | 2(4x) | 3(8x) | 3(8x) |
| scaling_3d_scale | 0.85 FSR1 | 0.92 | 1.0 | 1.15 | 1.25 |
| sky_cloud_detail | 0 | 1 | 2 | 2 | 3(第4层) |
| sea_wave_detail | 0(3波) | 1(3波) | 2(5波) | 3(7波) | 3(7波) |
| sea_foam / reflection / SSR | 0/0/0 | .62/1.0/0 | .86/1.0/0 | .92/1.15/.58 | 1.0/1.25/.62 |
| sea_normal/foam/refl detail | .45/0/0 | .72/1/1 | 1/1.7/1 | 1.2/2.1/1.5 | 1.35/2.4/2.0 |
| sea_mesh_scale | 0.6 | 0.8 | 1.0 | 1.2 | 1.4 |
| grass / particle density | .45/.5 | .7/.75 | 1/1 | 1.2/1.2 | 1.4/1.35 |
| light_budget | 4 | 6 | 8 | 10 | 12 |
| glow_strength / exposure | .55/1.0 | .75/1.0 | 1.0/1.0 | 1.08/1.02 | 1.12/1.04 |
| posts_ao / ao_strength | off/0 | off/0 | on/.35 | on/.55 | on/.75 |
| fog_scale / lod_bias | .85/.8 | .92/.9 | 1/1 | 1.06/1.15 | 1.1/1.3 |

约束：tonemap 五档统一 LINEAR（项目按 LINEAR 调过色，换 ACES/AGX 会整体偏灰偏色）；
低档保底 FXAA + 0.85 SSAA + 3 组大波，不出现"糊成一片"；极致档曝光 1.04/glow 1.12 防止过曝。

## 3. 海面：7 组方向波 + CPU 完全同源

`shaders/sea.gdshader` 顶点位移 = 7 组 sin 波，按 `wave_detail` 用 gate() 逐层启用
（need = 0/0/0/0.5/1.5/1.5/2.5，最终 = floor(wave_detail) ≥ need）：

| # | amp | kx | kz | omega | phase |
|---|---|---|---|---|---|
| 1 | .420 | .035 | .028 | .420 | 0 |
| 2 | .260 | -.061 | .052 | .580 | 1.700 |
| 3 | .150 | .124 | -.087 | .860 | 3.100 |
| 4 | .085 | -.201 | -.168 | 1.220 | 5.000 |
| 5 | .050 | .317 | .244 | 1.630 | 0.600 |
| 6 | .072 | .148 | .212 | 1.020 | 2.350 |
| 7 | .038 | -.256 | .183 | 1.380 | 4.450 |

`scripts/isle_waves.gd` 用**同一波表**做 CPU 复刻：
`static func height(x, z, t, detail=3.0, height_scale=1.0) -> float`，
main.gd 的 `_wave_h` / 船体吃水直接调它，保证船不穿水/悬空。
法线：shader 内 `wave_grad` 解析求导 + `detail_grad` 两层 vnoise 有限差分（随 sea_normal_detail）。

近岸/远景：mesh 由 main 按 `sea_mesh_scale` 控制细分（shader 不重建网格），
远处用 `wave_scale` 与 gate 衰减避免摩尔纹。

## 4. 天空：云层 0..3 + 日出日落连续化

`shaders/sky.gdshader`（uniform 数量不变，沿用 cloud_detail）：
- detail 0：无云；1：卷云+丝云；2：加厚度积云（P5 观感）；2.5+：第 4 层高空卷云带 + 更密星空/银河细化。
- 日出日落：`low_sun = 1 - smoothstep(0.055, 0.34, sun_dir.y)`，地平线暖带随太阳高度角连续加宽/变暖；
  反日方向加"维纳斯带"；太阳盘色温由白→橙随太阳高度连续过渡（disk_tint）。
- 月相/星空与时间统一：moon_phase / moon_waxing 与星空亮度联动，第 4 档加暗星与银河尘带。

## 5. 自定义屏幕空间 AO（shaders/post_ao.gdshader）

引擎 SSAO 对全 unshaded 管线无效（见 §1），故自建全屏 AO。**两版实现与踩坑记录**：

### 5.1 失败版本（已废弃）：不透明 pass 读屏幕纹理再写回
- 曾用 `spatial` + QuadMesh，fragment 里读 `screen_tex : hint_screen_texture`，算完 AO 后输出 `ALBEDO = screen_col * (1 - ao)`。
- **实测后果**：q2/q3/q4 整屏发白、对比度/饱和度塌陷；且与 ao_strength 无关（ao=0 也洗）。
  窗口对照：AO 关的 q4 帧 mean=(0.328,0.602,0.638) sat=0.540 正常；AO 开（哪怕 ao=0）整屏变 (0.405,0.605,0.603) 的浅色蒙层。
- **根因**：Forward+ 不透明 pass 里 `hint_screen_texture` 不是最终画面（天空与后续不透明物尚未合成），把它整屏乘系数写回等于用中间画面覆盖最终画面。这是本任务最重要的渲染陷阱。

### 5.2 现行版本：透明 pass 纯乘法叠层
- render_mode：`unshaded, cull_disabled, depth_test_disabled, depth_draw_never, blend_mix, fog_disabled`。
- 顶点：`POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0)` 全屏铺满（可直接挂 Camera3D 下）。
- fragment 正常输出：`ALBEDO = vec3(0.0); ALPHA = clamp(ao, 0.0, 1.0);` → 屏幕结果 = dst × (1-ao)，alpha=0 处**完全透传**（实测 AO 开、strength=0 与 AO 关逐像素完全一致）。
- 只保留 `depth_tex : hint_depth_texture`（透明 pass 同样可读深度），不读屏幕纹理。

### 5.3 AO 数学：视空间半球投影（第二版踩坑）
- 第一版采样是"屏幕空间圆环 + 深度差"：平面上采样点与中心同平面，遮挡恒为 0，只有物体轮廓处有值。实测 q4 岛区 AO 图 p99=0、max=0.039（等于没有 AO）。
- 现行：以视空间中心点 p + 邻域深度重建的法线 n 建正交基，在法线半球取余弦加权样本 sp，用 `v_proj`（顶点传入的 PROJECTION_MATRIX）把 sp 投到屏幕、采深度重建场景点 sq，`sq.z > sp.z + ao_bias` 记遮挡（场景点比采样点更靠近相机）。
- 深度约定：Godot 4.7 Vulkan **反向 Z**，depth 采样值近=1/远=0/天空=0，直接乘 INV_PROJECTION_MATRIX（`depth_convention=1` 为 GL 的 raw*2-1，保留用于校准/调试）。
- 参数：ao_strength / ao_radius / ao_samples / ao_bias / ao_max_dist / ao_contrast / depth_convention / ao_debug。
- `ao_debug`：1=AO 值灰度；2/3=两种约定的视距/200m；4=原始深度（用于窗口校准）。
- 挂载（main._build_post）：_cam 下 MeshInstance3D+QuadMesh(1×1)，material render_priority=127，extra_cull_margin=16384，cast_shadow OFF，position (0,0,-0.6)；AO 只压暗、不改变色相。

## 6. 海面反射：从"屏幕空间 SSR"改为"解析反射细节增强"

- 原方案：sea.gdshader 用 `sea_screen_tex : hint_screen_texture` + `ssr_cam_vp` 做世界空间步进投影采样屏幕颜色，只在 ssr_strength>0 时启用。
- **实测后果（与 §5.1 同一陷阱）**：sea 是不透明 pass，采样到未合成天空的中间画面 → q2→q3 第二段整屏洗白 + 船/岛竖条纹伪影：
  q2 ref lum/sat=0.495/0.687 → q2 加 ssr .58 = 0.529/0.553；
  q3 ref 0.537/0.548 → q3 关 SSR = 0.505/0.676；q4 ref 0.547/0.537 → q4 关 SSR = 0.512/0.674。
- **现行方案**：删除 `sea_screen_tex` 与屏幕步进，只用解析量：`reflect_extra(R)` = 更高频云絮（fbm3 两层，随 cloud_opacity）+ 太阳方向暖色反光带（低太阳时偏橙，随 sun_i 加权）+ 月光冷色反光；由 `ssr_strength`（q3=0.58/q4=0.62）小权重叠加并 clamp，只做"更贵的反射"锦上添花，不得整屏提亮。
- 接口兼容：`ssr_strength`、`ssr_cam_vp` 等 main 会写的 uniform 名保留（ssr_cam_vp 已不参与运算，保留声明仅为兼容 main 的每帧 set_shader_parameter）。

## 7. 验证方式

- `tools/probe_water6.gd`（headless）：逐文本比对 shader 波表与 isle_waves.gd WAVES（7 组、容差 1e-6）、CPU 4320 点复算最大误差、波高范围/连续性/grad/normal、shader 顶点位移行格式、main 是否已同源。
- `tools/probe_quality6.gd`：
  - headless：五档 24 键类型/范围/单调性、低档保底、极致档上限、merge_overrides、isle_settings 桥接、sea_params/sky_params/render_params 映射、着色器静态接口（uniform 名、无屏幕纹理、AO 半球采样）。
  - `-- --window --out=DIR`：实例化 isle.tscn，同机位 12:20 / 74° 拍 `quality_fixed_q0..q4.png`；每档统计全图/天空/海面/岛屿区亮度与饱和度；q2→q4 洗白检查（Δlum、饱和度比）；q4 SSR 开/关像素差（确认可见但不洗白）；AO 开/关像素差 + `quality_fixed_ao_debug.png` 岛区 AO 分位数。

## 8. 实测记录

| 项目 | 结果 |
|---|---|
| probe_water6 headless | PASS 17 / FAIL 0 / WARN 0（shader 7 波表与 CPU 一致，4320 点最大误差 0.000000 m） |
| probe_quality6 headless | PASS 51 / FAIL 0（24 键契约 + 映射 + shader 接口 + AO 半球采样） |
| sea/sky/post_ao/toon/vignette shader headless 编译 | 全部通过（无 SHADER ERROR） |
| AO 透明叠层恒等性 | AO 开 strength=0 与 AO 关逐像素相同（窗口实测两帧 mean=(0.222,0.561,0.622)） |
| AO 洗白根因对照 | 旧版 AO 开（strength=0）整屏变 (0.405,0.605,0.603) vs AO 关 (0.328,0.602,0.638) |
| SSR 洗白根因对照 | q3 开 0.537/0.548 vs 关 0.505/0.676；q4 开 0.547/0.537 vs 关 0.512/0.674（lum/sat） |
| 窗口五档 / AO / SSR 最终数字 | 见 §9（2026-10-20 22:04 实测，68 checks / 0 fail） |
| probe_ghost6 窗口（task-8 重影回归） | PASS 26 / FAIL 0（修复后 22:44，56.8 s；窗洞亮度比 0.496/0.410/0.369 → 0.995/0.992/0.989） |
| probe_ao_perf 窗口（AO pass 开销） | q2 +1.14 ms、q4 +1.93 ms（12 采样，1600×900 内部视口） |

## 9. 最终窗口实测（2026-10-20 22:04，2560×1440，同机位 12:20、74°，q0..q4）

探针修正（重要）：main 默认停在 MENU 模式，`_process` 每帧用 `_movie_pose()` 覆盖相机；
且持久化设置可能 `time_source="real"`。窗口探针现在会 `_mode=1`(PLAYING)、`_auto_orbit=false`、
`_time_source="sim"`、`_paused=true`，并在开头断言 5 帧机位漂移 < 0.5 m（实测 0.054 m）——
否则各档截图会落在电影机位/真实夜间，档间对比无意义。

| 档位 | MSAA | SSAA | TAA | 海网格 | FPS | 全图亮度 | 饱和度 | 天空区 | 海面区 | 岛屿区 |
|---|---|---|---|---|---|---|---|---|---|---|
| q0 低 | 0 | 0.85 | 否 | 108²/11881 | 64.4 | 0.5396 | 0.443 | 0.6861 | 0.3562 | 0.5741 |
| q1 中 | 2x | 0.92 | 否 | 144²/21025 | 68.0 | 0.5812 | 0.367 | 0.7067 | 0.4800 | 0.5993 |
| q2 高 | 4x | 1.00 | 否 | 180²/32761 | 89.1 | 0.5782 | 0.369 | 0.7048 | 0.4824 | 0.5830 |
| q3 极高 | 8x | 1.15 | 是 | 216²/47089 | 40.5 | 0.5879 | 0.369 | 0.7121 | 0.4965 | 0.5881 |
| q4 极致 | 8x | 1.25 | 是 | 252²/64009 | 37.1 | 0.5962 | 0.370 | 0.7230 | 0.5057 | 0.5925 |

- 档间像素差：q0→q2 mean 0.0601（92.81% 像素）、q2→q4 mean 0.0304（91.69%）、q0→q4 mean 0.0790（96.83%）。
- 洗白检查：Δlum(q3-q2)=+0.0097、Δlum(q4-q2)=+0.0180（阈值 +0.025/+0.035）；饱和度比 q3=0.999、q4=1.002（阈值 0.85）→ **高档不再发白/灰**。
- 解析反射增强（q4 ssr_strength 0.62 vs 0）：mean 0.0197、75.96% 海面像素变化，全图亮度 0.5966→0.5932（Δ=-0.0034，仅海面微调，无整屏提亮）。旧屏幕 SSR 的船/岛竖条纹伪影已消失。
- 自定义 AO（开 strength .75/radius 1.0/samples 16 vs 关）：mean 0.0228、65.35% 像素变化，全图亮度比 0.9741（局部接触阴影，非蒙层）；AO debug 岛区 p50=0.000/p90=0.835/p99=1.000、>0.05 占比 37.12%（密集草叶几何产生强遮蔽，符合预期）。
- 截图：`../开发产物/shots6/t3/quality_fixed_q0..q4.png`（同机位五档）、`quality_fixed_ao_off/on/debug.png`、`quality_fixed_q4_ssr0.png`、`t3_water_ultra.png` / `t3_water_low.png`（海面近景，q4/q0）。
- 视觉核查（人眼对比截图）：q0 为干净低配（无云、海面细节少但完整）；q2 云层/岸浪出现；q4 天空出现第 4 层高云、海面高频波纹与反射细节、草地纹理明显更密，未见整屏灰白或过曝。

## 10. 高画质「阁楼窗重影」根因与修复（task-8，2026-10-20）

### 10.1 用户现象与复现

用户反馈（05:14「破晓前」正对阁楼落地窗截图，`../开发产物/shots6/feedback/user_ghost_attic.jpg`）：
窗内暖灯/桌/梁架旁出现**成片深色矩形与横向阶梯暗带**，窗棂与窗框像是多了错位半透明「暗副本」，
屋顶斜面轮廓外还有羽化黑块。仅在**「高」及以上**档出现（q2/q3/q4）。

复现探针：`tools/probe_ghost6.gd`（窗口模式）。
- 机位：05:14、正面阁楼窗（用户同构图），cam=(2.597, 12.896, 9.832)、target=(2.047, 14.996, 3.432)、fov 50、
  窗投影 ROI=(0.346, 0.305, 0.314, 0.423)，内部视口 1600×900，截图 2560×1440。
- 每个变体只改一个因子；`_mode=1`(PLAYING)+暂停+冻结时间源，避免 main 的 `_process` 覆盖机位。
- 运行：`../开发产物/shots6/ghost/run_ghost_probe.sh`（拿 .winlock → console exe → 释放锁）。

### 10.2 修复前隔离矩阵（2026-10-20 22:37，24 张截图，76 s）

窗洞 ROI 亮度（`roi_lum`，同一机位同时间）：

| 变体 | roi_lum | 相对 AO 关 | 说明 |
|---|---|---|---|
| q2 高（AO .35） | 0.0989 | **0.496** | 窗内被 AO 压暗 50% |
| q3 极高（AO .55） | 0.0818 | **0.410** | 压暗 59% |
| q4 极致（AO .75） | 0.0737 | **0.369** | 压暗 63%，并出现轮廓黑块 |
| q2 关 AO | 0.1983 | 1.000 | 窗内干净正常 |
| q2 AO=.75（强制） | 0.0653 | 0.329 | 强度越大鬼影越重 |
| q2 TAA 关 / MSAA 0/2/8x / FXAA | 0.0989~0.0997 | ≈1.00 | **与 AO 无关** |
| q4 TAA 关 / MSAA 2x 开 | 0.0740/0.0736 | ≈1.00 | TAA/MSAA 组合不改变窗内亮度 |
| q4 缩放 1.0（无 SSAA） | 0.0738 | ≈1.00 | SSAA 无关 |
| q2 玻璃全关 / 只留外层 / 只留内层 / refract .006 | 0.1014/0.1000/0.1003/0.0989 | ±0.014 | 玻璃层与屏幕折射无关 |

逐像素对照（全部 2560×1440，luminance 归一化，阈值 0.004）：q2 vs q2 关 AO → mean 0.02805、30.79% 像素；
q3 → mean 0.05248、41.89%；q4 → mean 0.06598、59.07%。而 q4 TAA on/off 仅 mean 0.00137/5.64%、
玻璃全关 mean 0.00040、refract mean 0.00021、SSAA mean 0.00147 —— 量级差 1~2 个数量级。

### 10.3 根因（自定义 PostAO 后处理，非 TAA、非玻璃、非 SSR）

旧 `post_ao.gdshader` 的半球 AO 有三个缺陷：
1. **遮挡深度差无上限**：像素在室内 15 m 深处时，前方 6.4 m 的窗棂/窗框/梁被当作「更近的遮挡物」，
   每个采样点都记为全强度遮蔽；
2. **世界半径投影过大**：0.9~1.0 m 世界半径在 6.4 m 视距处的屏幕偏移可达窗宽 10%+，
   于是每个室内像素被前景窗棂压出一个「半径大小的暗副本」= 用户看到的重影/暗带；
3. **轮廓法线退化**：邻域含天空时视空间法线重建错误，轮廓外产生黑色羽化糊块；
   同时强度映射 `pow(occ*3.2, ...)*2.4` 极易饱和到全黑，进一步放大上述错误。

为什么只有「高」及以上：q0/q1 `posts_ao=false`（AO 节点隐藏），q2 是第一档开启 AO（.35），q3/q4 逐档加码。

### 10.4 修复（`shaders/post_ao.gdshader`，不改 main 的 uniform 契约）

1. **每样本遮挡深度差上限** `float lim = rr * 1.8 + ao_bias;` 超出即不算遮挡，并按
   `1-smoothstep(lim*0.45, lim, diff)` 淡出 —— 9 m 外的窗棂不再压黑室内；
2. **轮廓跳过**：要求四邻深度都有效（非天空）且视距跳变 < `max(ao_radius*2, view_dist*0.05)`，
   否则该像素不施加 AO —— 消除屋顶/窗框轮廓外的黑色糊块；
3. **温和映射** `ao = clamp(pow(occ*1.35, ao_contrast),0,1)*ao_strength`，替换旧 `*3.2 / *2.4` 饱和映射；
4. **投影偏移上限**（`distance(suv, SCREEN_UV) < 0.30`）与近/远距离淡出，避免掠射角脏边。

AO 仍是「透明 pass 纯乘法叠层」（`ALBEDO=0, ALPHA=ao` → 屏幕 = dst*(1-ao)），不读屏幕纹理、不覆盖像素。

### 10.5 修复后回归（2026-10-20 22:44，`probe_ghost6` 窗口，26 checks / 0 fail，56.8 s）

| 指标 | q2 高 | q3 极高 | q4 极致 | 结论 |
|---|---|---|---|---|
| 窗洞亮度比（AO 开/关） | **0.995** | **0.992** | **0.989** | 修复前 0.496/0.410/0.369 → 鬼影不可察觉 |
| AO 仍有真实效果（开/关像素差） | 5.14% | 8.56% | 10.38% | 未被偷偷关掉 |
| AO 改变量 mean | 0.00070 | 0.00124 | 0.00167 | 柔和接触阴影，非蒙层 |

- 岛景 AO 有效性（恢复 12:20/74° 机位，q4 AO .75）：开/关像素差 13.28%、岛屿区亮度比 0.9942；
  调试图 p50=0 / p90=0.235 / p99=0.341、>0.05 占 28.59% —— 草叶接地处有遮蔽，但整体只暗 0.6%。
- 排除项复核：q4 TAA on/off mean 0.00100/4.56%、窗洞比 1.001；玻璃全关 7.69%/mean 0.00102/窗洞比 1.037
  （仅为玻璃反光边缘的轻微变化，无暗块）；refract .006 → 1.06%/mean 0.00034。
- 档间差异仍明确：q0→q2 77.68% 像素（mean 0.0497）、q2→q4 80.93%（mean 0.0312）。
- 静止时 TAA 历史拖影：q4 转 2° 抓 1 帧 move1-vs-converged mean 0.00287/16.24%，TAA 关为 0/0 —— 
  TAA 确有历史累积但仅边缘抖动，窗内无重影，判为非本次根因（保留为已知特性）。

### 10.6 性能（内部视口 1600×900，RTX 2060，同机位）

| 版本 | q2 | q3 | q4 |
|---|---|---|---|
| 修复前（22:37） | 109.3 fps / 9.15 ms | 66.1 / 15.14 | 53.1 / 18.82 |
| 修复后 run1（22:44） | 107.2 / 9.33 | 61.4 / 16.28 | 51.6 / 19.36 |
| 修复后 run2（22:44） | 102.4 / 9.76 | 58.8 / 17.00 | 45.9 / 21.78 |
| AO pass 开销 A/B（`probe_ao_perf.gd`） | +1.14 ms | ≈0（TAA 噪声） | +1.93 ms |

结论：修复后 AO 仍是全屏 12 采样 pass，开销约 **1.1~1.9 ms**（q2/q4，render scale 1.0/1.25）；
档间 fps 波动 ±5~10% 属 GPU 时钟/热噪声，与修复无系统性关系。

### 10.7 参考（Godot TAA / SSAO 伪影）

- Godot 3D antialiasing 文档：TAA 仅 Forward+；对透明物体提供完整抗锯齿；静止时轻微模糊、
  相机移动时模糊更明显；**moving objects 后面会出现 ghosting artifacts**；
  MSAA 2/4/8x 只作用于几何边缘，不减少 alpha scissor/透明与高光锯齿：
  https://docs.godotengine.org/en/stable/tutorials/3d/3d_antialiasing.html
- `Viewport.use_taa` 文档：实现尚未完成，粒子与蒙皮网格可能出现 artifacts：
  https://docs.godotengine.org/en/stable/classes/class_viewport.html#class-viewport-property-use-taa
- 已知 TAA ghosting 类问题（可解释「TAA 也可能产生重影」，因此必须先做隔离）：
  https://github.com/godotengine/godot/issues/69493 、TAA 修复跟踪 PR
  https://github.com/godotengine/godot/pull/123844
- SSAO 原理与采样数权衡（样本少 → banding，随机化 → 噪声需模糊；SSAO 只是屏幕空间近似，
  对屏幕外遮挡物与深度断裂天然无解）：
  https://learnopengl.com/Advanced-Lighting/SSAO

本次实测结论：本项目的重影**不是** Godot 内置 TAA 造成的（TAA 开/关窗洞亮度比 1.001、差异 4.56%），
而是自定义 AO 在**深度断裂处使用无上限深度差**造成的伪影 —— 属上表最后一类问题的自实现版本。

### 10.8 回归检查（已并入 `tools/probe_ghost6.gd`，窗口模式 26 项断言）

- q2/q3/q4 窗洞亮度比 > 0.92/0.90/0.88（重影消失）；
- AO 仍真实可见（开/关像素差 > 0.2%/0.4%/0.6%，且岛景 AO 有 0.8%+ 像素差、亮度比 0.85~0.9995）；
- q4 不洗白（lum 不高于 q2+0.03）、窗内亮度不低于 q2 的 60%；
- TAA/玻璃/refract 对照仍为「非根因」；q0→q2、q2→q4 档间差异仍明确；
- AO 调试图分位数非全零（防止 AO 被静默禁用）。

### 10.9 剩余风险

- AO 在轮廓像素有意跳过（避免糊块），极细物体（草叶/栏杆）的接触感略弱于传统 SSAO，但无脏边。
- AO 由深度重建法线，不写深度的透明物（玻璃）不产生 AO，符合预期。
- TAA 在相机运动时仍有历史拖影（官方已知特性）；若后续用户报告运动画面重影，
  可在 q3/q4 关闭 TAA 改用 MSAA8x+SSAA，或降低 TAA 权重（需 main 侧新参数）。
- 本轮只验证 05:14 阁楼窗近景与 12:20 岛景两个机位；其他时间/机位未逐张截图。