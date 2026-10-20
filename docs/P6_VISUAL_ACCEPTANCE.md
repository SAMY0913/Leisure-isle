# P6 视觉与分辨率验收（T5）

> 验收对象：休闲小岛幻境（Godot 4.7.2 stable，Forward+，主场景 res://isle.tscn）
> 执行人：verify-visual（teammate）　关联任务：task-5
> 阶段 1（分辨率矩阵 / 窗口模式 / 回退 / DPI 模拟）实测完成：2026-10-20 23:22–23:36
> 阶段 2（最终画面截图集逐张人工审查）：**待 Lead 发出 FREEZE 后执行**，本文件先固化阶段 1 数据。
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

## 7. 阶段 2：最终画面截图集逐张审查（待 Lead FREEZE）

**状态：待执行。** Lead 发出 FREEZE 后，按下表逐项用 read_image 实看最终截图集
（目录建议：D:/休闲小岛幻境/开发产物/shots6/verify_visual/final/；若项目 --shots 已产出完整集则直接审查并补缺），
逐张记录"通过 / 不通过 / 未验证 + 证据路径"：

- [ ] 正午场景：曝光/亮度溢出、阴影、海面完整性
- [ ] 日出前后：暖色过渡、过曝、阴影异常
- [ ] 黄昏/日落：辉光、色彩、暗部细节
- [ ] 夜景与灯塔光束：光束伪影、亮度溢出、暗部噪点
- [ ] 海面近景：水面边界漏洞/漏水、反射/折射、AA 锯齿
- [ ] 船舶与水面：船体穿模/悬浮、倒影、接触阴影
- [ ] 小屋正面/背面/阁楼玻璃：玻璃反射是否过强、室内是否可见、遮挡异常
- [ ] 海鸥停靠：穿模/悬空/比例异常
- [ ] 画质档位同机位对比（q0 vs q2 vs q4）：差异合理性、AA 噪点/闪烁
- [ ] 菜单/设置/关键转场：UI 裁切/比例、转场黑帧/闪白
- [ ] 补充缺失机位（若项目 --shots 集不全）

---

## 8. 阶段 1 结论

1. **分辨率矩阵通过**：16 个窗口化/无边框状态 + 1 个全屏状态全部实测生效，expand 视口公式、比例、
   HUD/菜单/设置/确认层布局全部 PASS；4K 与 21:9、16:10 均无裁切或比例异常。
2. **窗口模式与回退流程通过**：保持/回退/ESC/12 秒超时/模式三态循环与模式回退全部真实注入验证，状态恢复一致。
3. **DPI**：真实系统缩放未验证（环境限制）；模拟 1.25 倍通过，1.5 倍越界压力测试仅包围盒告警、实看无碰撞。
4. **WARN 归因清楚**：29 + 4 + 4 条 WARN 分别为低分辨率小字可读性、超屏钳制（设计）、letterbox 无黑边（设计）、
   DPI 环境未验证、测试静音提示；无一条属于布局缺陷。
5. **未发现 P0/P1 视觉/UI 缺陷**；建议的非阻塞优化：最小分辨率档最小字号略增、后续支持 UI 缩放。

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

- 截图（37）：D:/休闲小岛幻境/开发产物/shots6/verify_visual/
- 日志（3）：D:/休闲小岛幻境/开发产物/logs/visual/probe_ui_matrix6_{matrix,fallback,dpi}.log
- 结构化结果（3）：同目录 probe_ui_matrix6_result_{matrix,fallback,dpi}.json
