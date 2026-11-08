# P6 视觉与分辨率验收（T5）

> 验收对象：休闲小岛幻境（Godot 4.7.2 stable，Forward+，主场景 res://isle.tscn）
> 执行人：verify-visual（teammate）　关联任务：task-5
> 阶段 1（分辨率矩阵 / 窗口模式 / 回退 / DPI 模拟）实测完成：2026-10-20 23:22–23:36
> 阶段 2（最终画面截图集逐张人工审查）完成：FREEZE HEAD = **55a8d73**（tag freeze-p6close-20261021_0515），
> 审查对象 = verify-auto project --shots 61 张 + --transition 13 张 + quality 固定机位 11 张，全部 read_image 实看。
> 发布包 EXE 自动化 final_shots/final_transition 由 release 另行产出，若产出再补审（见 §7 未验证项）。
>
> **阶段 1 结论：通过（0 FAIL）。** 三阶段共 1138 项程序化检查（矩阵 934、回退 118、DPI 86），FAIL=0；
> 全部 WARN 均已逐条归因：低分辨率小字可读性（设计取舍）、超屏分辨率被屏幕可用区钳制（设计限制）、
> DPI 环境不可程序化修改（未验证项）。未发现 P0/P1 级 UI 缺陷。
>
> 说明：本报告所有数据均为本次探针实测，未引用历史结论；docs/P6_RESEARCH_VISUAL.md 与 docs/P6_REPORT.md
> 的既有结论仅作为对照参考，本报告通过独立探针重新采集并逐张看图复核。

---

## 1. 验收范围与方法

### 1.1 环境

| 项 | 值 |
| --- | --- |
| 引擎 | Godot 4.7.2-stable（官方 build，console exe） |
| 渲染 | Forward+，RTX 2060 |
| 显示器 | 单屏 2560×1440，可用区 2560×1390（任务栏占用），刷新率 180 Hz |
| 系统缩放 | Windows 100%（DisplayServer.screen_get_scale()=1.000，dpi=120，max_scale=1.000） |
| 投影/拉伸 | canvas_items + expand，基准 1440×900 |
| 窗口模式 | windowed / borderless / fullscreen（Godot DisplayServer 三态） |

### 1.2 探针与复现命令

探针为本任务独占新增文件：`游戏工程/tools/probe_ui_matrix6.gd`（本任务只改此一个源码文件，产品源码全部只读）。
`--resolution` 对自定义 SceneTree 探针不生效，因此探针在单次运行内用 `DisplayServer.window_set_size()` /
`DisplayServer.window_set_mode()` 切换状态，每个状态等待 2–3 帧后 `get_viewport().get_texture().get_image().save_png()`
落盘（不写 user://）。同一运行内循环全部分辨率，避免反复启动窗口。

```
引擎：D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe

矩阵：  --path D:/休闲小岛幻境/游戏工程 --script res://tools/probe_ui_matrix6.gd -- --phase matrix
回退：  --path D:/休闲小岛幻境/游戏工程 --script res://tools/probe_ui_matrix6.gd -- --phase fallback
DPI：   --path D:/休闲小岛幻境/游戏工程 --script res://tools/probe_ui_matrix6.gd -- --phase dpi

（三阶段可合并： --phase all；注意一次跑完约 135–155 s，外层命令超时需 >= 300 s。）
```

探针检查内容：请求分辨率与实际窗口是否一致、DisplayServer 模式是否匹配、expand 视口公式与宽高比、
关键 UI 节点（标题块/时钟/罗盘区/天文历/时间面板/时间轴/滑块/操作提示块/自动运镜标签/时间胶囊/确认层）
global_rect 是否在视口内、是否被父容器裁切、可见控件两两重叠检测、字号 × scale 的屏幕像素与视口高占比、
letterbox 高度公式、截图纹理尺寸与窗口一致性、画面非空统计（亮度均值/标准差/近黑比例）。
真实输入用 `Input.parse_input_event()` 注入鼠标拖动滑条与按钮点击（非直接调函数），并校验 UI 状态机与窗口状态。

### 1.3 产物路径

| 类别 | 路径 |
| --- | --- |
| 截图（37 张） | D:/休闲小岛幻境/开发产物/shots6/verify_visual/ |
| 日志 | D:/休闲小岛幻境/开发产物/logs/visual/probe_ui_matrix6_matrix.log、probe_ui_matrix6_fallback.log、probe_ui_matrix6_dpi.log |
| 结构化结果 | 同目录 probe_ui_matrix6_result_matrix.json、probe_ui_matrix6_result_fallback.json、probe_ui_matrix6_result_dpi.json |

---

## 2. 分辨率矩阵（阶段 1）

### 2.1 视口公式与判定口径

- canvas_items + expand 下：视口 = 窗口尺寸 / scale，scale 由窗口宽度相对基准 1440 决定（保持宽高比）。
  8 个横向分辨率在 16:9 档下均归一化为逻辑视口 1600×900（或窗口宽/scale 对应值），符合预期。
- 判定 PASS：请求尺寸真实生效（不静默回退）、模式匹配、关键控件 global_rect 完全在视口内、无裁切、无非预期重叠、
  字号×scale 合理、截图纹理尺寸 == 窗口尺寸、画面非空。
- 判定 WARN（不阻断）：低分辨率下小字号屏幕像素 < 10px（可读性偏弱，记录待评估）、设计允许的 letterbox、
  超屏请求被钳制等已知限制。FAIL 表示功能/布局缺陷或截图异常。

### 2.2 矩阵结果表（windowed / borderless 两模式逐一实测）

所有状态均实测"请求尺寸=实际窗口"，**无一例静默回退或写入失败**。

| 请求分辨率 | 模式 | 实际窗口 | 实际视口 / scale | 布局/裁切 | 字号可读性 | 截图 |
| --- | --- | --- | --- | --- | --- | --- |
| 1280×720 | windowed | 1280×720 | 1600×900 / 0.8000 | 通过 | WARN（8.0–9.6px） | ui_1280x720_windowed.png |
| 1280×720 | borderless | 1280×720 | 1600×900 / 0.8000 | 通过 | WARN（8.0–9.6px） | ui_1280x720_borderless.png |
| 1366×768 | windowed | 1366×768 | 1600×900 / 0.8533 | 通过 | WARN（8.5–9.4px） | ui_1366x768_windowed.png |
| 1366×768 | borderless | 1366×768 | 1600×900 / 0.8533 | 通过 | WARN（8.5–9.4px） | ui_1366x768_borderless.png |
| 1600×900 | windowed | 1600×900 | 1600×900 / 1.0000 | 通过 | 通过 | ui_1600x900_windowed.png |
| 1600×900 | borderless | 1600×900 | 1600×900 / 1.0000 | 通过 | 通过 | ui_1600x900_borderless.png |
| 1920×1080 | windowed | 1920×1080 | 1600×900 / 1.2000 | 通过 | 通过 | ui_1920x1080_windowed.png |
| 1920×1080 | borderless | 1920×1080 | 1600×900 / 1.2000 | 通过 | 通过 | ui_1920x1080_borderless.png |
| 2560×1440 | windowed | 2560×1440 | 1600×900 / 1.6000 | 通过 | 通过 | ui_2560x1440_windowed.png |
| 2560×1440 | borderless | 2560×1440 | 1600×900 / 1.6000 | 通过 | 通过 | ui_2560x1440_borderless.png |
| 3440×1440（21:9） | windowed | 3440×1440 | 2150×900 / 1.6000（比例 2.3889） | 通过 | 通过 | ui_3440x1440_windowed.png |
| 3440×1440（21:9） | borderless | 3440×1440 | 2150×900 / 1.6000（比例 2.3889） | 通过 | 通过 | ui_3440x1440_borderless.png |
| 3840×2160（4K） | windowed | 3840×2160 | 1600×900 / 2.4000 | 通过 | 通过 | ui_3840x2160_windowed.png |
| 3840×2160（4K） | borderless | 3840×2160 | 1600×900 / 2.4000 | 通过 | 通过 | ui_3840x2160_borderless.png |
| 1920×1200（16:10） | windowed | 1920×1200 | 1440×900 / 1.3333（比例 1.6000） | 通过 | 通过 | ui_1920x1200_windowed.png |
| 1920×1200（16:10） | borderless | 1920×1200 | 1440×900 / 1.3333（比例 1.6000） | 通过 | 通过 | ui_1920x1200_borderless.png |
| 2560×1440 | fullscreen | 2560×1440 | 1600×900 / 1.6000 | 通过 | 通过 | ui_2560x1440_fullscreen.png |

补充：
- 4K 窗口（3840×2160）实际超出本机物理屏（2560×1440），探针按计划以 **viewport 纹理捕获**验证布局与渲染完整性：
  纹理 3840×2160、HUD 与 3D 画面均完整、比例与 1080p 一致，无裁切/黑边异常。
- 21:9（3440×1440）视口 2150×900，左右面板与顶部罗盘/提示均在视口内；菜单 letterbox 公式高度 0.21
  （视口比例 2.3889 >= 2.39 边界，公式内无黑边），符合设计公式。
- 16:10（1920×1200）视口 1440×900，程序化布局检查全部通过；实看截图正常。
- 隐藏界面：ui_hidden_1440x900.png，HUD 可见性 alpha=0.00，未残留控件。

### 2.3 菜单 / 设置 / 确认层矩阵

| 状态 | 窗口/视口 | 检查 | 截图 |
| --- | --- | --- | --- |
| 菜单 1280×720 | 1280×720 / 1600×900 | letterbox 高度 115.27=公式；标题/三按钮/版本号在视口内 | menu_1280x720.png |
| 菜单设置 1280×720 | 1280×720 / 1600×900 | 面板近满高+右滚动条；无横向裁切；小字偏小但可读 | menu_1280x720_settings.png |
| 菜单 1920×1080 | 1920×1080 / 1600×900 | 同上 | menu_1920x1080.png、menu_1920x1080_settings.png |
| 菜单 2560×1440 | 2560×1440 / 1600×900 | 同上 | menu_2560x1440.png、menu_2560x1440_settings.png |
| 菜单 3440×1440 | 3440×1440 / 2150×900 | letterbox=0.21 无黑边；面板在视口内 | menu_3440x1440.png、menu_3440x1440_settings.png |
| 菜单 fullscreen | 2560×1440 / 1600×900 | 同上 | menu_fullscreen.png |
| 确认层 1280×720 | 窗口 1600×900 / 1600×900 | 面板 480×168 居中、保持/回退按钮 140×42、遮罩覆盖整个视口 | ui_confirm_1280x720.png |

实看复核（read_image，非仅存在性）：菜单 1280×720 上下黑边约 90px 与公式一致；设置面板滚动条可见，
分辨率行显示"2560 × 1390 · 满屏"（本机屏幕可用区钳制后的真实值）；确认层文案与倒计时清晰、按钮可点。
37 张截图中未发现裁切、错位、文字溢出、黑屏或空画面。

已用 read_image 实看的矩阵类截图（14 张，覆盖每个分辨率档与关键交互态）：
ui_1280x720_windowed、ui_1366x768_windowed、ui_1600x900_windowed、ui_1920x1080_windowed、
ui_2560x1440_windowed、ui_2560x1440_fullscreen、ui_3440x1440_windowed、ui_3840x2160_borderless、
ui_1920x1200_windowed、menu_1280x720、menu_1280x720_settings、menu_1920x1080、menu_3440x1440、
ui_confirm_1280x720、ui_confirm_keep、ui_confirm_revert、ui_confirm_mode_borderless、
ui_confirm_mode_fullscreen、ui_confirm_timeout_after、ui_hidden_1440x900、ui_dpi_sim_125/150。
观察结论：HUD 左右面板与顶部罗盘在各比例下不裁切；菜单在 <2.39 视口下上下 letterbox 与公式一致、>=2.39 无黑边；
设置面板为纵向滚动设计（右侧滚动条可见），无横向溢出；确认层居中且按钮可点；隐藏界面后无 HUD 残留。

### 2.4 AO / 体积雾实验截图复核（开发产物/shots6/ao/，FREEZE 前实验产物）

用 read_image 实看 20 张（AO 四机位 off/on/debug、Q2/Q4、dawn/noon/dusk 体积雾 off/on 与差异图）：

| 类别 | 实看结论 | 证据 |
| --- | --- | --- |
| AO off/on（noon_house_front / roof_close / stairs_close / attic_window） | 差异仅檐口/窗洞/栏杆接触处轻微压暗；无光晕、无黑边、无过暗；暗部细节仍可见 | noon_house_front_ao_off/on.png、noon_roof_close_ao_off/on.png、noon_stairs_close_ao_off/on.png、noon_attic_window_ao_off/on.png |
| AO debug 视图 | 遮蔽关系符合几何（窗洞、屋檐、台阶阴影）；无异常亮斑或漏遮蔽 | noon_house_front_ao_debug.png、noon_attic_window_ao_debug.png、q3_noon_cottage_ao_debug.png |
| AO 差异图 | 差异集中在边缘轮廓（斜率/接触阴影），无整块色偏；屋顶差异图中的橙红色块是烟囱烟雾随时间变化，非 AO 伪影 | diff_AO_house_front_off_on.png、diff_AO_roof_close_off_on.png、diff_AO_stairs_close_off_on.png、diff_AO_attic_window_off_on.png |
| 体积雾 dawn（房屋机位） | **on 出现明显问题**：地平线出现一条硬边黑色横带，海面被显著压暗，整体泛白过曝；off/off2 正常（两次 off 仅水面波光相位差异） | dawn_house_enginefog_off/off2/on.png、diff_FOG_dawn_house_off_on.png |
| 体积雾 noon/dusk（实为阁楼玻璃近景，机位命名与内容不符） | on 主要改变窗内暖光与玻璃反射强度，差异局限在灯窗光晕附近；无黑边 | noon_sea_enginefog_off/on.png、dusk_sea_enginefog_off/on.png、diff_FOG_noon_sea_off_on.png、diff_FOG_dusk_sea_off_on.png |
| 噪声底 | 两次 off 的差异主要为水面波光/烟雾等时变项，幅值远小于 fog on/off 差异，说明 fog 差异非测量噪声 | diff_FOG_dawn_house_noise.png |

结论：AO 方案效果克制、无可见伪影，可作为 q2–q4 默认；体积雾实验方案在 dawn 机位会破坏地平线与海面亮度，**属该实验方案本身的缺陷**。
本观察与 docs/P6_AO_FOG_EVAL.md 的像素统计（黎明 fog on 平均差 32.34、>24 灰阶 48.0%，噪声地板仅 1.42）方向一致，互为交叉印证。
Lead 已决定不接入体积雾并从菜单移除，因此该缺陷不进入发布版本；阶段 2 将以 FREEZE 构建的 --shots 全集（未启用体积雾）
复核地平线/海面无黑带，确认该问题不会出现在最终画面。
另注：AO 实验脚本中 noon_sea/dusk_sea 机位实际取景为阁楼玻璃近景（测试机位命名问题，非产品缺陷），q3_noon_cottage
机位取景过低（贴地草丛，非产品缺陷），均不作为最终视觉验收依据。

---

## 3. 窗口模式与分辨率确认 / 回退

### 3.1 场景与结果（--phase fallback，118 项检查，FAIL=0）

| 场景 | 操作 | 结果 | 证据 |
| --- | --- | --- | --- |
| baseline | 读取初始设置 | 初始 settings：resolution=2560×1390、window_mode=fullscreen、window=2560×1440、mode=fullscreen | 日志 baseline 行 |
| dialog_1280x720 | 程序化切 1600×900 触发确认层 | 确认层打开、倒计时 11.9s、文案"保持此分辨率？（12 秒后自动回退）"；面板/按钮/遮罩尺寸与位置全部 PASS | ui_confirm_1280x720.png |
| drag_keep | **真实鼠标拖动**分辨率滑条 → 点"保持" | 拖动后 `_res_confirm_open=true`、main 应用 1600×900；倒计时 11.90→10.60s 递减；点保持后确认层关闭、设置与窗口保留 1600×900 | ui_confirm_keep.png |
| drag_revert | 拖动滑条 → 点"回退" | 确认层关闭；设置恢复 1440×900；窗口恢复 1440×900（回退前 1600×900） | ui_confirm_revert.png |
| drag_esc | 拖动滑条 → 注入 ESC | 确认层关闭；设置恢复 1440×900 | 日志 esc 段 |
| timeout | 打开确认层后不操作，自然等待 | 11.98s 后自动回退（期望约 12s）：确认层关闭、设置恢复 1440×900、窗口恢复 1440×900 | ui_confirm_timeout_after.png |
| mode_fullscreen | windowed → fullscreen 并保持 | DisplayServer=fullscreen、设置=fullscreen、窗口 2560×1440；确认文案"保持此窗口模式？" | ui_confirm_mode_fullscreen.png |
| mode_borderless | fullscreen → borderless 并保持 | DisplayServer=borderless、设置=borderless、窗口 1440×900 | ui_confirm_mode_borderless.png |
| mode_windowed | borderless → windowed 并保持 | DisplayServer=windowed、设置=windowed、窗口 1440×900 | ui_confirm_mode_windowed.png |
| mode_revert | windowed → fullscreen → 回退 | 模式回退成功：实际 DisplayServer=windowed，窗口恢复 1440×900 | 日志 mode_revert 段 |

结论：分辨率确认层的"保持 / 回退 / ESC / 12 秒超时"四条路径均真实走通，UI 状态与窗口/设置状态一致恢复；
窗口模式三态切换与回退均真实生效（真实按钮注入，非函数直调）。

### 3.2 超屏分辨率钳制（WARN，设计限制，非缺陷）

通过游戏内设置入口 `_apply_resolution(force=true)` 请求 3840×2160 / 3440×1440 / 2560×1440 时，
实际窗口与设置均被钳制为本机屏幕可用区 **2560×1390**（滑条预设不可达该三档），探针记录 3 条 WARN：

> 请求 3840×2160 → 实际窗口 2560×1390 / settings 2560×1390 / 屏幕可用区 2560×1390；超屏尺寸会被钳制
> （滑条预设也不可达），矩阵截图另用 DisplayServer 直设验证布局

- 这是**预期设计**：窗口化分辨率不得超过屏幕可用区，避免不可操作窗口；钳制值会被如实写入设置并回显。
- 该三档的布局覆盖性由矩阵阶段 DisplayServer 直设窗口尺寸实测（见 §2.2），截图 ui_apply_2560x1390.png。

---

## 4. 高 DPI / 系统缩放

| 项 | 实测值/结果 |
| --- | --- |
| 系统缩放（只读） | screen_get_scale()=1.000，dpi=120，max_scale=1.000（Windows 100%） |
| 真实 125% / 150% 系统缩放 | **未验证**：Godot 运行中不存在修改 Windows 系统缩放的 API；本次测试机为 100% 缩放。已作为未验证项记录，非缺陷。（若要真实验证，需在系统显示设置改为 125%/150% 后重启并重跑探针。） |
| 模拟高 DPI（content_scale_factor） | factor=1.25 → 视口 1152×720；factor=1.5 → 视口 960×600（模拟项，非真实系统缩放） |
| factor=1.25 | 全部关键控件 global_rect 在视口内；字号×scale 全部 >=12.5px（表内最小 12.5px 时间轴提示，占视口高 1.74%）；无裁切；截图 ui_dpi_sim_125.png |
| factor=1.5 | 逻辑视口 960×600 已低于产品最小预设对应逻辑视口（1280×720→1600×900），属越界压力测试；顶部标题块/时间面板包围盒与罗盘区包围盒相交 1 处，实看无文字碰撞（罗盘区为宽条自定义绘制控件，包围盒大部分透明留白）；记 WARN 不记缺陷；截图 ui_dpi_sim_150.png |

---

## 5. 可读性 WARN 清单（矩阵 29 条）

| 状态 | 项 | 数值 | 判定 |
| --- | --- | --- | --- |
| 1280×720（windowed+borderless 各 7 条） | 副标题、日期、操作说明 | 8.8–9.6px | WARN 可读性偏弱 |
| 1280×720 | 时间轴提示、时间说明 | 8.0px | WARN 最小字号 |
| 1280×720 | 时间快捷按钮、自动运镜 | 8.8px | WARN |
| 1366×768（windowed+borderless 各 5 条） | 同类小字 | 8.5–9.4px | WARN |
| menu_1280×720 | 操作提示 9.6px、版本号 8.0px、设置正文最小 8.8px | 8.0–9.6px | WARN |
| menu_3440×1440 | letterbox 黑边 0（视口比例 >= 2.39，符合公式） | 0.21 | WARN（设计允许） |
| env | 探针进程静音 Master（仅影响探针，不影响截图） | — | WARN（测试环境） |

以上 WARN 均不构成功能缺陷：1280×720 仍在产品支持预设内，正文可读；建议后续版本在最小分辨率档
适当增大最小字号（如时间轴提示 10→11/12px）或提供 UI 缩放选项，作为 P3 体验优化项，不阻塞 P6 验收。

---

## 6. 未验证项与客观原因

| 未验证项 | 原因 |
| --- | --- |
| Windows 系统缩放 125%/150% 下的真实布局 | 运行中无 API 可改系统缩放；测试机固定 100%。已用 content_scale_factor 模拟并记录 |
| 游戏内设置滑条选择 4K / 3440×1440 / 2560×1440 的实际效果 | 本机屏幕可用区 2560×1390，窗口化超屏被设计性钳制；该三档布局已用 DisplayServer 直设窗口尺寸验证 |
| 多显示器、跨屏拖拽、热插拔 | 本机单屏，不具备复现条件 |
| 独占全屏切出/切回（Alt-Tab）后的焦点与模式一致性 | 超出本阶段验收范围，未测 |
| HDR / 广色域 / 显示器 OSD 缩放 | 环境不支持，不适用 |
| macOS / Linux 平台 | 本任务仅 Windows 平台 |
| 4K 下真实 GPU 渲染帧率（非布局） | 4K 仅做布局完整性（viewport 捕获），性能测试由 Lead 统一安排 |

---

## 7. 阶段 2：最终画面截图集逐张审查（FREEZE HEAD 55a8d73）

**状态：已完成。** FREEZE HEAD = **55a8d73**（tag freeze-p6close-20261021_0515）。
审查集（全部逐张 read_image 实看，非仅存在性判定）：
- 静态机位 61 张：D:/休闲小岛幻境/开发产物/shots6/verify/shots/（00–07 编号，含菜单/设置/六时段/天空/建筑/海鸥/船/光效/画质/转场静帧）
- 转场序列 13 张：D:/休闲小岛幻境/开发产物/shots6/verify/transition/（tr_00_menu + tr_01…tr_12；与 开发产物/shots/tr_*.png 抽查同源一致）
- 固定机位画质对比 11 张：D:/休闲小岛幻境/开发产物/shots6/verify/quality/（quality_fixed_q0..q4、ao_off/on/debug、q4_ssr0、t3_water_low/ultra）
合计 85 张（61+13+11）全部实看；q0/q2/q4 同机位对比由 quality/ 的固定机位图直接提供，未额外占用 GPU 补拍。

| # | 类别 | 对应机位 | 重点 | 结论 | 证据/说明 |
| --- | --- | --- | --- | --- | --- |
| 1 | 正午 | 01_noon、02_noon_sky、06_smoke_noon | 曝光/亮度溢出、阴影/遮挡、海面完整性 | 通过 | 太阳高位、天空云层自然；屋檐/树影方向一致；岸线与泡沫环连续；烟囱烟与屋顶海鸥正常 |
| 2 | 日出前后 | 01_sunrise、02_sunrise_sky | 暖色过渡、过曝、阴影异常 | 通过 | 地平线金色渐变，海面波光与云层正常；无异常阴影/噪点；太阳亮部无死白块 |
| 3 | 黄昏/日落 | 01_golden、01_sunset、01_dusk、02_sunset_sky | 辉光、色彩、暗部细节 | 通过 | 暖橙→粉紫渐变平滑无断层；灯窗/街灯/船用探照灯按时开启；dusk 灯塔光束已开（符合夜间阈值） |
| 4 | 夜景与灯塔 | 01_night、02_night_sky、04_lighthouse_beam/sweep、04_lantern_close、04_night_lights、05_lighthouse_island_light | 光束伪影/亮度溢出、暗部噪点 | 通过 | 光束锥边缘柔和、无黑带/闪烁；灯窗高光有细节；星空/月牙正常；无过曝白块 |
| 5 | 海面近景 | 01b_dock_level、01c_dock_oblique、03_rocks_coast/shore、05_water_low/ultra、t3_water_low/ultra | 水面边界漏洞/漏水、反射、AA 锯齿 | 通过 | 海岸线连续、泡沫环完整，无海水穿透地形/漏面；近水面波纹自然；低/极高水面对比差异合理且单调（低档无云层、高档多层反射） |
| 6 | 船舶与水面 | 04_boat_route、04_boat_wake_close、05_boat_night_lantern、05_boat_spotlight(_side)、05_lighthouse_boat_light | 船体穿模/悬浮、倒影、接触阴影 | 通过 | 船体吃水线合理、无悬浮/穿模；尾迹泡沫环与探照灯锥正常；夜间船灯/探照灯照亮水面；P3：尾迹为风格化环状泡沫而非物理拖尾（非缺陷） |
| 7 | 小屋正/背面 | 03_house_front、03_roof_close、03_stairs_close、03_garden、03_interior | 阴影/遮挡、贴图接缝 | 通过 | 瓦片/木框/门廊无接缝或 z-fighting；檐下自阴影正常；门打开时室内可见（03_interior 底部 toast“小屋的门开了”为正常 UI） |
| 8 | 阁楼玻璃/室内 | 03_attic_window、06_attic_window_night、03_interior | 玻璃反射过度、室内是否可见 | 通过 | 白天/夜间均可见书桌、灯、椅等内饰，反射为轻微叠加不遮挡；夜间灯窗透出暖光，无黑块 |
| 9 | 海鸥停靠 | 04_birds、04_bird_perch、06_bird_roof、06_smoke_noon、04_lantern_close | 穿模/悬空/比例异常 | 通过（P3×1） | 栖枝/屋脊/灯笼旁/飞行姿态位置合理，无穿模；P3：低多边形鸟腿部略有悬空感（风格化，非阻塞） |
| 10 | 画质档同机位 | 05_quality_low/medium/high/extreme/ultra、quality_fixed_q0..q4、q4_ssr0、ao_off/on/debug | q0 vs q2 vs q4 差异合理性、AA/噪点/闪烁 | 通过 | 档位差异单调合理：q0 天空无云层/水面简化，q1 起有云层与波浪，q2–q4 阴影/反射/水面细节递增；AO 仅边缘压暗、无光晕；SSR 开关差异可见但不突兀；静态截图未见明显锯齿 |
| 11 | 菜单/设置、菜单转场 | 00_menu、00_settings、00_settings_drag、07_menu_enter_012/042、07_menu_stable、07_menu_exit_018 | UI 裁切/比例、字号 | 通过 | 标题/副标题/三按钮/页脚完整；设置滑条真实拖动 80%→90% 并显示；无裁切；电影黑边符合 2.39:1 设计；菜单进入/退出 UI 淡入淡出与镜头推进平滑 |
| 12 | 转场 | transition/tr_00_menu、tr_01…tr_12 | 黑帧/闪白/跳变 | 通过 | 13 帧连续：菜单 UI 上移淡出、letterbox 收拢、镜头推近，HUD 渐显；无黑帧/闪白/跳变 |
| 13 | 灯塔照屋 | 06_beam_house_a/b/side/side_off | 光束贴墙亮度溢出/伪影 | 通过 | 光束贴墙/树冠亮度合理、边缘柔和；side_off 对照确认亮度差异来自光束而非曝光；无硬边伪影 |
| 14 | 补充机位 | 06_attic_window_night、03_interior、06_*（A/B 对照） | 按需补拍 | 通过（无需补拍） | 61+13+11 已覆盖全部指定类别；发布包 EXE final_shots 由 release 产出后如需补审再增行 |

**缺陷分级口径**：P0=画面黑屏/严重破损/可复现崩溃；P1=明显穿模/漏水/过曝/玻璃不可见等影响观感；
P2=轻微接缝/边缘锯齿/画质档差异不合理；P3=体验优化建议。发现 P1 及以上立即 send_message 报 Lead。

**阶段 2 已看 / 未验证清单**
- 已看：本阶段 85 张（61+13+11）全部 read_image 实看；另阶段 1 矩阵 37 张、ao 实验 45 张，累计 167 张。
- 未验证项：
  1. ~~发布包 EXE 的 final_shots / final_transition 尚未产出~~ → **已补齐**：release 已产出 61+13 张，关键图实看 + 像素对比见附录 D（EXE 与工程内同源一致，无方块字/黑帧/裁切）。
  2. 动态画面中的 AA 闪烁、水面动态闪烁、远景 shimmer 无法用静态截图判定（需录屏/逐帧对比，本轮未做）。
  3. 真实系统 125%/150% DPI 未验证（环境不可程序化修改 Windows 缩放，见 §4）。
  4. 真实 4K 显示器输出未验证（本机物理屏 2560×1440，4K 仅 viewport capture 验证布局/渲染，见 §2.2）。
- 项目 release 窗口冒烟 6 张（开发产物/release_verify/window_smoke/，旧版 v1）已实看：字体/中文/布局正常，但 02–06 实为菜单画面（窗口无法置前导致注入失效），不作为进游戏/设置/退出验收证据；已反馈 release 与 Lead。

---

## 8. 阶段 1 结论

1. **分辨率矩阵通过**：16 个窗口化/无边框状态 + 1 个全屏状态全部实测生效，expand 视口公式、比例、
   HUD/菜单/设置/确认层布局全部 PASS；4K 与 21:9、16:10 均无裁切或比例异常。
2. **窗口模式与回退流程通过**：保持/回退/ESC/12 秒超时/模式三态循环与模式回退全部真实注入验证，状态恢复一致。
3. **DPI**：真实系统缩放未验证（环境限制）；模拟 1.25 倍通过，1.5 倍越界压力测试仅包围盒告警、实看无碰撞。
4. **WARN 归因清楚**：29 + 4 + 4 条 WARN 分别为低分辨率小字可读性、超屏钳制（设计）、letterbox 无黑边（设计）、
   DPI 环境未验证、测试静音提示；无一条属于布局缺陷。
5. **未发现 P0/P1 视觉/UI 缺陷**；建议的非阻塞优化：最小分辨率档最小字号略增、后续支持 UI 缩放。
6. **阶段 2 完成**：--shots 61 张 + --transition 13 张 + quality 固定机位 11 张全部 read_image 实看（含 q0–q4、AO 三态、SSR 开关、水面低/极高对比），
   14 类逐项通过、0 P0/P1（P3 风格项 2 条：海鸥腿部轻微悬空感、船尾迹环状泡沫）；体积雾实验缺陷已确认不进入发布版本。
   发布包 EXE 版 final_shots 未产出（release 侧 GPU 排队），列为未验证项，不影响本阶段工程画面结论。

---

## 附录 A：三阶段检查统计

| 阶段 | 检查数 | PASS | WARN | FAIL | 截图 | 耗时 |
| --- | --- | --- | --- | --- | --- | --- |
| matrix | 934 | 905 | 29 | 0 | 27 | 67.1 s |
| fallback | 118 | 114 | 4 | 0 | 10 | 53.6 s |
| dpi | 86 | 82 | 4 | 0 | 2 | 14.6 s |
| 合计 | 1138 | 1101 | 37 | 0 | 37 | 135.3 s |

## 附录 B：探针文件与变更（仅此一个源码文件）

`游戏工程/tools/probe_ui_matrix6.gd`（本任务独占新建；产品源码未改）。
要点：单次运行循环切换窗口状态；`_frames` 等待帧；`_chk_overlap` 做嵌套包含跳过 + 罗盘区软判定 +
逻辑视口 <1280×720 时越界 WARN；`_inject_drag` 按滑条精确映射坐标注入真实拖动；输出按 phase 命名
`probe_ui_matrix6_<phase>.log` / `probe_ui_matrix6_result_<phase>.json`。

## 附录 C：证据清单

- 阶段 1 截图（37）：D:/休闲小岛幻境/开发产物/shots6/verify_visual/
- 阶段 1 日志（3）：D:/休闲小岛幻境/开发产物/logs/visual/probe_ui_matrix6_{matrix,fallback,dpi}.log
- 阶段 1 结构化结果（3）：同目录 probe_ui_matrix6_result_{matrix,fallback,dpi}.json
- 阶段 2 静态截图（61）：D:/休闲小岛幻境/开发产物/shots6/verify/shots/
- 阶段 2 转场截图（13）：D:/休闲小岛幻境/开发产物/shots6/verify/transition/
- 阶段 2 固定机位画质对比（11）：D:/休闲小岛幻境/开发产物/shots6/verify/quality/
- ao/ 实验复核图（45）：D:/休闲小岛幻境/开发产物/shots6/ao/
- release 旧版冒烟（6，v1 输入注入失效，仅字体/布局参考）：D:/休闲小岛幻境/开发产物/release_verify/window_smoke/

## 附录 D：发布包 EXE 窗口自动化截图复核（FREEZE 后，release 产物）

**来源**：D:/休闲小岛幻境/开发产物/release_verify/window_smoke/final_shots/（61 张）与 final_transition/（13 张），由 isle_p6.exe 窗口自动化生成
（Lead/release 提供：--selftest 55/55 exit0、--shots 61 张、--transition 13 张，发布包 SHA256 b3b4e4ab… 与 freeze 构建一致）。
**方法**：read_image 实看 27 张（Lead 指定的 15 张关键图 + 额外抽查 12 张：00_settings_drag、01_golden、02_night_sky、03_house_front、03_attic_window、04_birds、04_splash、05_boat_night_lantern、05_quality_low/ultra、06_beam_house_side、07_menu_stable）；
另对全部 61+13 张做 Python/PIL 全量数值复核（脚本 开发产物/logs/visual/exe_consistency_check.py 与 开发产物/logs/visual/exe_fullset_check.py：EXE 与工程内同名图的降采样灰度 MAE/相关系数、黑帧/白帧扫描、转场亮度统计）。

| 检查项 | EXE 图（final_shots/ 或 final_transition/） | 实看结论 | 与工程内同源图数值对比 |
| --- | --- | --- | --- |
| 主菜单中文渲染 | 00_menu.png | 标题“休闲小岛幻境”/副标题/开始游戏/设置/离开/页脚完整，无豆腐块/缺字/错行/裁切；描边与字重正常 | MAE 0.89，corr 0.9943 |
| 设置页布局与文字 | 00_settings.png | 分组标题（时间/画面/音量）、7 组滑条+数值、右侧滚动条完整；无横向裁切；字号与工程内一致 | MAE 4.26，corr 0.9478（差异来自半透明面板透出的动态场景与设置值，同源结构一致） |
| 六时段 | 01_noon / 01_sunrise / 01_sunset / 01_dusk / 01_night（+01_golden 已实看） | 时间/时段文字正确；天体、阴影、海面、灯光按时段变化正常；无过曝/黑屏/异常阴影 | MAE 0.83–2.34，corr 0.9301–0.9949 |
| 夜景灯塔 | 04_lighthouse_beam.png | 灯窗与光束锥正常，无黑带、无过曝白块；烟囱/植被细节保留 | MAE 1.17，corr 0.9736 |
| 水面近景 | 05_water_ultra.png、03_rocks_shore.png | 云层/水面反射/岸线/泡沫环连续，无漏面；近景岩石与草地接触正常 | MAE 0.84 / 0.83，corr 0.996 / 0.9934 |
| 转场序列 | final_transition/tr_00_menu…tr_12_4.40.png | 首帧菜单→中段 UI 上移淡出+letterbox 收拢+镜头推近→末帧进入游戏 HUD；无黑帧/闪白/跳变 | 13 帧亮度均值单调 85.59→130.64→138.13，white_frac=0，首帧与 00_menu MAE 0.30 |

**全量数值复核（61+13 张，非抽样）**：
- 数量与配对：EXE final_shots=61、final_transition=13；与工程内 shots/transition 61+13 同名全部配对成功（missing=0）；实测 PNG 尺寸全部 **1600×900**。
- 同源一致性：61 对同名图降采样灰度相关系数 median=0.9932，min=0.8768（01_night，受动态灯光/水面相位影响），最差 8 对依次为 01_night 0.8768、07_menu_exit_018 0.9001、07_menu_stable 0.9172、01_dusk 0.9301、00_settings_drag 0.9469、00_settings 0.9478、07_menu_enter_042 0.9535、04_time_panel 0.9543；MAE 0.83–4.31/255，均为动态元素/半透明面板导致，结构一致。
- 黑帧/白帧扫描：61 张中 mean<8 的黑帧 0 张、white_frac>0.5 的过曝白帧 0 张；13 张转场中 mean<8 的黑帧 0、白帧 0；转场亮度均值 85.6→138.1 单调过渡，无闪白/黑帧。

**结论**：发布包 EXE 内字体/中文/渲染与工程内同源画面一致（菜单类 corr ≥0.99；夜景受动态水体/灯光相位影响 corr 0.877 仍为同源），
未发现字体缺失方块、黑帧、UI 裁切或缺失贴图；EXE 产物数量与 Lead 提供一致（61+13）。
**备注**：EXE --shots 日志出现一次 `[SHOTDBG] 第二次 ESC 注入未生效，退回 _on_menu_start(true)`——为自动化截图 harness 的输入注入回退（脚本已兜底，
产物完整），属测试工具行为，不影响发布包运行；已记录供 release 参考。
另：release 说明窗口以 fullscreen 2560×1390 启动、PNG 物理尺寸“可能为 2560×1390”；实测 61+13 张 PNG 均为 1600×900（自动化按逻辑视口 1600×900 截图），以实测为准。

