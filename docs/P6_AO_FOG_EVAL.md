# P6 收尾：AO 后处理与引擎体积雾的实测评估

日期：2026-10-20（T7 收尾轮）
设备：RTX 2060，2560×1440 显示器；窗口渲染分辨率 1440×900（项目窗口尺寸，`--resolution 1600x900`
在自定义 `--script` 主循环下未生效）。
探针：`游戏工程/tools/probe_ao_visual_t7.gd`（窗口模式；headless 下自检 SKIP 退出 0）。
图像：`开发产物/shots6/ao/*.png`；像素差图 `diff_*.png`（差异放大 8 倍）。
统计脚本：`开发产物/py/diff_ao_fog.py`、`开发产物/py/diff_ao_fog2.py`（Pillow/numpy）。
日志：`开发产物/logs/probe_ao_visual_t7.log`。

## 一、AO（环境光遮蔽）实测

### 1.1 接线状态（本轮修复后）
- 着色器：`shaders/post_ao.gdshader`，透明乘法叠层（`ALBEDO=0, ALPHA=ao`），
  `render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, blend_mix, fog_disabled`；
  depth 纹理 + INV_PROJECTION_MATRIX 重建视空间位置，四邻深度不连续抑制（`edge_thr`）与逐采样深度差上限
  （`lim=rr*1.8+bias`）避免轮廓伪影。uniform：strength/radius/samples/bias/contrast/max_dist/ao_debug。
- 挂载：`main.gd` `_build_post()` 在 Camera3D 下创建全屏 Quad（`PostAO`，render_priority=127）。
- 本轮修复：`_apply_quality()` 之前只用 `ao_strength` 决定显隐，从不读 `posts_ao` 布尔 →
  菜单“环境光遮蔽 · AO”高级覆盖只改状态不改渲染。现已改为开关真正接线：
  `posts_ao=false → ao_strength=0 + 隐藏`；低/中档手动打开且强度为 0 时回落到 0.35；
  同时 `_quality_params()` 把菜单存档的 UI 别名 `post_ao` 归一为预设键 `posts_ao`。
- 档位：q0/q1 关；q2 strength=0.35；q3=0.55；q4=0.75（isle_quality.gd 预设不变）。

### 1.2 视觉差异（正午，q3，1440×900，静止画面 A/B）
| 机位 | mean abs diff | >2 灰阶像素 | >8 | >24 |
|---|---|---|---|---|
| house_front | 0.669 | 12.80% | 0.47% | 0.00% |
| stairs_close | 0.556 | 8.65% | 0.31% | 0.00% |
| roof_close | 0.532 | 10.25% | 0.63% | 0.00% |
| attic_window | 0.366 | 6.47% | 0.20% | 0.00% |

- 结论：AO 确实在渲染（差异集中在物体轮廓/接触边缘，`ao_debug=1` 可视化为沿几何边缘的窄带遮蔽），
  但对当前“全 unshaded 平涂 + 程序化 toon”画面只产生**轻微边缘/接触压暗**，正常观看几乎不可察觉。
- 未观察到伪影：天空、海面、玻璃窗、草地均无暗边或脏污；阁楼窗在此机位无重影
  （depth 不连续抑制生效）。这也与此前 P6 修复的“高画质阁楼窗重影”方向一致。
- 强度档位：直接对比 q2/q4 与 q3 的截图会同时混入其它画质参数差异，不能作为 AO 单独强度证据；
  AO 的实际差异幅度按 strength 线性缩放（q3 0.55 → q4 0.75 约 1.36 倍，仍属轻微级）。

### 1.3 成本（初步，窗口非独占）
- 1440×900、q3、静止场景、VSync 关闭、3 轮 off/on 各 90 帧：
  off 平均 9.570 ms/帧，on 平均 10.354 ms/帧，**Δ≈+0.78 ms/帧（约 +8%）**；单轮波动较大
  （7.4–12.2 ms），需在 GPU 独占下复测后才作为定稿数字。
- 全屏 12 采样、无分辨率缩放，成本随输出分辨率线性增长（4K 约为 1440×900 的 4 倍像素）。

### 1.4 结论
- **保留接入**：q2+ 默认开启，高级覆盖开关现已在真实渲染路径生效（`probe_quality_override_t7`
  173/173 通过，覆盖 q2 关 → AO 真关、q0 开 → AO 真开且强度 0.35、菜单存档→渲染往返）。
- 定位：AO 是“轻微质量增强/边缘压暗”，不是显著卖点；不夸大为大幅提升。
- 后续可选路线（不在本轮）：提高半径/采样做更明显的接触阴影（需重新做伪影与成本评估），
  或烘焙顶点 AO；若追求性能，可在 q2 关闭 AO 仅保留 q3/q4。

## 二、引擎体积雾（volumetric_fog）实测

### 2.1 背景
- 五档预设中 `volumetric_fog` 全为 false；`main.gd` 恒定 `_env.volumetric_fog_enabled = false`；
  但 `menu.gd` 曾把“体积雾 · FOG”列为高级覆盖行，属于“只改状态不改渲染”的误导性入口。
- 本轮用 A/B 实测判断引擎体积雾在自定义 unshaded 管线下是否值得接入。

### 2.2 实测（1440×900，q3）
| 场景 | mean abs diff | >2 | >8 | >24 | 观察 |
|---|---|---|---|---|---|
| 黎明（日出+8min）小屋正面 | 32.34 | 77.6% | 76.0% | 48.0% | **海面被明显染暗近黑、远山成黑带**，破坏暖色晨景 |
| 正午海景 | 6.95 | 92.3% | 44.8% | 1.2% | 轻微泛白雾感，观感尚可但属风格改变 |
| 黄昏海景 | 5.52 | 89.0% | 28.8% | 0.5% | 同上，会削弱暖色反差 |
| 黎明同条件噪声地板（关→关复拍） | 1.42 | 25.6% | 5.1% | 0.2% | 仅时间性抖动 |

- 根因判断：体积雾进入通用 spatial 片元阶段，但项目大量材质是自发光/平涂 unshaded，
  雾本身在黎明/黄昏几乎不受方向光照射，呈未受光的暗色体积，叠加到亮海面上即“染黑”；
  并非简单的“无可见效果”。正午观感尚可，但会削弱本作暖色手绘风与既有时段调色。
- 结论：**不接入**体积雾，也不在菜单暴露覆盖开关。
  - `menu.gd` 已删除“体积雾 · FOG”高级覆盖行（`OVERRIDE_ROWS` 现为 SSR、AO 两行）。
  - `main.gd` `_apply_quality()` 保持 `volumetric_fog_enabled = false`，注释改为记录本次实测根因。
  - `isle_quality.gd` 保留 `volumetric_fog` 键（全档 false）以兼容既有预设/探针契约，不驱动渲染。
  - 文档不再宣称“体积雾可覆盖/可提升画质”。
- 后续可选路线（不在本轮）：为雾单独做受光/颜色随时段调色、或改为高度雾/屏幕空间大气效果，
  需要新的美术与性能评估，不属于 P6 收尾范围。

## 三、复现命令

```powershell
# AO/体积雾 A/B + 成本（窗口；必须先关闭其他 Godot 进程）
$env:APPDATA='D:\休闲小岛幻境\开发产物\appdata'
& 'D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe' --path 'D:/休闲小岛幻境/游戏工程' `
  --resolution 1600x900 --script res://tools/probe_ao_visual_t7.gd
# 像素差统计
& <python> 开发产物/py/diff_ao_fog2.py
```

## 四、限制
- 成本数据为窗口非独占、1440×900 的初步值；GPU 独占复测见 `docs/P6_TEST_RESULTS.md` 的性能章节。
- 视觉结论基于本机单型号 GPU 的截图与像素统计；不同 GPU/驱动下 AO 采样与体积雾表现可能有差异。
- AO 对“不透明平涂”材质的增益天然有限；本评估只说明当前实现的实际作用与成本，不宣称更高画质收益。
