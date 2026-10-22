# P8.2-02 灯光质量与 q0 性能边界 — 实施与证据记录

> 执行：teammate "lighting"。证据根目录：`D:/休闲小岛幻境/开发产物/p82/02_lighting/`。
> before 一律用冻结基线副本 `D:/休闲小岛幻境/开发产物/p82/before_shot`（detached ddcde3a）拍；所有数字来自真实运行。

## (a) 室内吊灯光晕：近景"白色光斑"收放（已提交）

### 问题
一层吊灯 halo（`scripts/cottage.gd` `_interior` 内 `M.halo(root, Vector3(1.45, in_top-0.62, 0.80), 1.10, Color(2.2,1.5,0.85))`）
与阁楼吊灯 halo（`_attic_interior`，size 0.95，同色）**没有加入任何昼夜调光数组**，白天也是满亮度加色广告牌；
room_wide 机位距相机仅 1.41 m，投影半径 ≈467 px，画面右上出现一大片近白圆盘（旧图 `02_lighting/crop/day_room_wide_small.png`）。

### 修改
| 文件 | 改动 |
| --- | --- |
| `scripts/cottage.gd` | `_context` 新增 `"interior_halos": []`；一层吊灯/阁楼吊灯 halo 基准 size 1.10→0.60、0.95→0.60，基准色 (2.2,1.5,0.85)→(1.25,0.82,0.42)，两者 append 进 `interior_halos` |
| `scripts/main.gd` | 新增 `var _interior_halos`；`_build_world` 收集；`_update_lighting` 按 `lanternI` 写回 albedo 与 scale：`ihf=clamp(0.02+lanternI^1.6*0.95,0,1.2)`、`ihs=clamp(0.30+lanternI*0.70,0.30,1.0)`（白天只有微光点，夜间回升暖光晕） |

只改自发光广告牌的亮度/尺寸，**没有**新增 Light3D、没有提高 glow 强度、灯罩材质 `self_lit` 仍为 false。

### 真实运行像素量化（2560×1440，同机位 room_wide，右上 ROI = x∈[1900,2560), y∈[150,900)）

| 样本 | 说明 | 近白像素 min>235 | 近白像素 min>245 | ROI 平均亮度 |
| --- | --- | --- | --- | --- |
| `01_fireplace/before/day_room_wide.png` | base 副本 | 26,553 | 117 | 226.9 |
| `01_fireplace/after/day_room_wide.png` | 仅 01 壁炉修复（02-a 未生效） | 26,436 | 131 | 227.0 |
| `02_lighting/after/day_room_wide.png` | 含 02-a | **0** | **0** | **170.3 (−25.0%)** |

→ 01 的壁炉修复对该区域 **无影响**（26,553→26,436，−0.4%），白斑整体消失完全由 02-a 造成；本项 before/after 用前两行 vs 第三行对比。
像素表原始输出：`02_lighting/analyze_lights.py`（+ 本文件数字由同脚本逻辑计算）。

### HEAD 重拍复核（`02_lighting/before/` vs `02_lighting/after/`，同机位 2560×1440，同 ROI x∈[1900,2560) y∈[150,900)）
| 样本 | 近白 min>235 | 近白 min>245 | ROI 平均亮度 |
| --- | --- | --- | --- |
| `before/day_room_wide.png`（base ddcde3a） | 42,309 | 2,913 | 191.6 |
| `after/day_room_wide.png`（HEAD befdb0f） | **0** | **0** | **125.5（−34.5%）** |
| `after/day_room_wide_q0.png`（HEAD, q0） | 0 | 0 | 124.6 |
| `after/..._q2` / `q4` | 0 / 0 | 0 / 0 | 126.2 / 129.7 |

→ 三档画质下右上白斑均消失（q0 也一样），低画质不会因光晕收敛而看不到灯（`qa/night_fire_low_q*` 炉火与暖光仍在）。

### 截图
- before：`02_lighting/before/day_room_wide.png`（base 副本；本轮运行产出）
- after：`02_lighting/after/day_room_wide.png`（当前分支）
- 近景对照：`02_lighting/after/night_chand_near.png` / `after/day_chand_near.png`（吊灯近景）

### 限制
- 白天光晕仍有 ~0.02 的极弱点（便于看到灯泡位置），ROI 内已无近白像素；
- 阁楼吊灯同数组，夜间亮度由 `lanternI` 驱动，未单独做机位截图（阁楼夜景在 `after/night_attic.png` 可核对）。

## (b) 壁炉槽近距离过曝参数（已提交）

### 问题
`scripts/cottage.gd` `build()` 的 `light_sources` 壁炉槽原参数 range 5.0 / intensity 1.50 / energy 1.50，
`hearth` 台面与前脸距槽位 0.45 m 内，直射分量把炉台石顶面推到接近裁切（`fire_low` 机位 p99≈255），并形成强硬边。

### 修改
`range` 5.0→6.0、`intensity/energy` 1.50→1.05；**位置不动**（P8.2-01 探针 G8 已钉死 `fire_world`），颜色不动 `(1.0,0.52,0.22)`。

### 真实运行像素量化：同机位、同一次运行内 A/B（`shots` 模式末尾 `_restore_old_fire_light()` 把壁炉槽临时还原为旧参数 5.0/1.50 再拍一张，因此两图除本项外完全相同）

| 场景（2560×1440） | 指标 | 新参数 (6.0/1.05) | 旧参数 (5.0/1.50) | 变化 |
| --- | --- | --- | --- | --- |
| `day_room_wide` | 裁切像素 (max=255) | **5,694** | 11,634 | **−51.0%** |
| `day_room_wide` | 近白面积 (max≥250) | **8,946** | 20,810 | **−57.0%** |
| `night_room_wide` | 裁切像素 | **21,836** | 47,125 | **−53.7%** |
| `night_room_wide` | 近白面积 | **33,684** | 59,284 | **−43.2%** |
| `day_room_wide` | 两图差异>2 的像素占比 / 平均 |diff| | — | — | 40.5% / 3.42 |
| `night_room_wide` | 两图差异>2 的像素占比 / 平均 |diff| | — | — | 78.0% / 8.26 |

→ 旧参数下炉台/地面/近墙大面积过曝（裁切像素约为新的 2 倍），新参数把直射亮度压掉约一半但保留房间暖光（room_wide 全景暖色仍在，见 `after/day_room_wide.png`）。
近距离证据图：`after/night_fire_low.png`、`after/day_fire_low.png`（炉台石顶面不再整片纯白，火焰与石胸轮廓可辨）。

### 夜间近景：为什么把吊灯光晕半径上限收到 0.60（刻意收敛，不是"变暗"）
P8.1 的一层吊灯光晕固定 size=1.10 且白天也满亮，room_wide 机位距灯 1.41 m 时投影半径 ≈467 px，
在 2560 宽的图里就是一大片白盘（`02_lighting/crop/day_room_wide_small.png`）。本项把基准收到 0.60、
夜间 scale 上限 1.0（即最大 0.60 m，比 P8.1 的 1.10 小 45%），是**刻意收紧近景光斑**；
灯本身仍亮：`after/night_chand_near.png` 实测 max=255、p99=255、亮度>200 的像素占 14.5%、>240 占 6.6%
（白天近景分别为 8.1% / 6.3%），灯罩依旧是最亮的物体，不存在"夜里看不见灯"。

## (c) 悬空加色球：定位与结论

### 现象（Lead 在 `02_lighting/after/night_room_wide.png` 实测）
三处悬空亮黄加色圆盘：①(412,424) ②(1289,472) ③(1259,562)（2560×1440 图像坐标）；day 图同类位置不明显。
裁切证据：`02_lighting/crop/night_ballL.png`、`crop/night_ballC1.png`。

### 定位手段（确定性，不靠肉眼 bisect）
`tools/probe_p82_lights_visual.gd --mode=nodes`：夜间 room_wide 机位下遍历**所有** MeshInstance3D，
筛出 material_override 为 `BLEND_MODE_ADD`（或名字含 Glow/halo）的节点，逐个打印
路径 / 父节点 / 世界坐标 / 面片尺寸 / albedo / 距离 / **相机 unproject 像素** / 估计屏幕半径 / 所属调光数组，
再对 ①②③ 做最近邻匹配；同时列出 self_lit 自发光节点与 glow 后处理参数（排除 bloom 假象）。

### 实测路径与结论（三层确定性诊断，日志 `02_lighting/regress/{nodes,isolate2,isolate3}_diag.log`）

1. **排除广告牌**（`--mode=nodes`）：夜间 room_wide 同机位（chandelier 灯投影 px=(2216,493) 与 shots 的 PX 行完全一致，机位校验通过），
   枚举全部 MeshInstance3D 中 additive / 名字含 Glow-halo 的节点共 **23 个**；①②③ 的最近邻 billboard 分别在 131.7 / 371.3 / 276.5 px 外，
   **没有任何加色广告牌落在三点上** → 不是 halo、不是 `isle_house_props._glow()`、不是萤火粒子。
2. **锁定光类型**（`--mode=isolate2`）：隐藏 halo 收集器返回 0（未生效）、隐藏萤火只让三点随火焰闪烁微动；
   **18 盏解析点光 energy=0 → 三点全黑** (3,10,25)/(4,11,30)/(4,12,30) ⇒ 由解析点光造成。
3. **逐灯归因**（`--mode=isolate3`，18 盏逐盏单独 energy=0 采样，9×9 邻域均值，2560×1440）：

| 关断的灯 | ①(412,424) | ②(1289,472) | ③(1259,562) |
| --- | --- | --- | --- |
| （无，基准） | (120,52,25) | (208,103,42) | (236,113,44) |
| **L[13] kind=fireplace**（world (-1.981,9.046,-2.147)，range 6.0，energy 1.05，color (1.0,0.52,0.22)，indoor） | **(21,17,25)** | **(88,63,40)** | **(87,63,41)** |
| L[14] kind=table_lamp | (116,50,25) | (190,83,30) | (219,96,33) |
| 其余 16 盏（含 L[10] attic_chandelier、L[12] porch_lantern、L[15] window_glow） | 各项偏差 ≤ 13 | ≤ 19 | ≤ 19 |

→ ② 的壁炉灯贡献 ≈ 57%（206→88），③ ≈ 63%（235→87），table_lamp ≈ 8%，其余 <10%；① 无单灯主导（多灯叠加 + 附近 halo）。

### 机制（为什么会有"悬空球"）
壁炉光槽（`light_sources` 中 priority 900 的 indoor 槽）位于炉膛内（local z=-2.30），
而 P8.1 起**解析光照不做阴影**：光穿过石胸上方的薄墙，在壁炉上方高墙/西墙上部形成径向亮斑；
夜间环境光低 → 亮斑对比强，再被 glow 后处理放大成近白圆盘（旧 `after_pre_02/night_room_wide.png` 三点为 (218,219,146)/(253,253,230)/(255,255,204)，即已裁切）。

### 预存在性（关键）
- 冻结基线副本 base(ddcde3a) 的 `before/night_room_wide.png` 同三点 = **(102,44,25)/(204,101,41)/(164,87,38)** ⇒ **P8.1 就存在，不是 P8.2 引入的回归**。
- (b) 提交后 HEAD（1.05/6.0）实测三点 = (120,52,25)/(208,103,42)/(236,113,44)，已从裁切白降为橙色热点（③ 236 而非 255）。

### 处置：**NO-GO，不改参数，登记为已知限制**（Lead 21:00 前裁决）
- 继续降 energy：会同步压暗壁炉对炉台/地面/近墙的合法暖光，与 P8.2-01 已验收的"壁炉暖光落在合理室内表面"冲突；
- 收 range：热点距灯仅约 1.6 m，需 range<1.6 m 才能截断 = 等于废掉这盏灯；
- 挪位置：会破坏 `probe_p82_fireplace` G8 断言（光槽 local pos 钉死）与 01 已验收几何；
- 加遮挡/阴影：属全局灯光架构（P8.1 16 槽解析光双池），本轮明令禁止。
- **影响面**：仅夜间室内宽景/近景可见；白天环境光将其掩盖（`after/day_room_wide.png` 不可见）。后续若做"局部遮挡体/阴影探针"可再评估。

## (d) 室内外双池过渡带（`g_indoor_band`）：**未采纳，已完整回滚**

- 设计：toon.gdshader 加 `global uniform float g_indoor_band`，在房屋壳体 ±band 内用 `indoor_soft()`
  同时累加室内/室外两池（带外仍单池），目标消掉门洞/窗边硬阶跃光带。
- 回滚原因：中间态（shader 已声明该 global uniform、main.gd 尚未注册写值）在他人运行中出现
  **4374 条** `WARNING: Shader uses global parameter 'g_indoor_band', but it was removed at some point`，
  污染他人帧时间采样且可能渲染不正确。按 Lead「不留半成品」要求：
  `shaders/toon.gdshader` 已 `git checkout` 回 HEAD（与仓库逐字节一致），main.gd 两处 band 代码删净（全树 grep=0）。
- 若要重做：正确顺序必须是先 `RenderingServer.global_shader_parameter_add` 注册并写默认值、再在 shader 引用，
  且与 P8.1 双池契约一起走完整回归；本轮不引入该风险。

## §2 灯光视觉逐项结论（每项一句结论 + 证据路径）

| 子项 | 结论 | 证据 |
| --- | --- | --- |
| 门廊灯 glow 近景过曝 | P8.1 遗留（`cottage.gd` 门廊灯罩 self_lit=false、glow=1.0）；本轮**未改参数**（改它需重拍整条门廊光照链），量化现状见 `after/night_porch.png` 与 `before/night_porch.png` 同机位对照 | `02_lighting/after/night_porch.png`、`02_lighting/before/night_porch.png` |
| 室内外光照边界（门洞/窗边硬阶跃） | 硬阶跃仍在（d 未采纳）；HEAD 实测门洞边缘梯度 day 4.62 / night 5.13，窗边 11.06 / 9.80（与 02 改动前基本一致 → a/b 未恶化边界） | `02_lighting/pixels_after.csv`、`after/day_door_inside.png`、`after/night_door_inside.png` |
| 壁炉对周边表面的暖光 | 已可辨识：(b) 后炉台/地面/近墙无裁切（hearth p99 day 208.0 / night 219.6，clip=0），火焰与石胸轮廓清楚；固定炉台 box 平均亮度 night 93.1→92.4（基本不变，暖光保留）、day 128.9→118.9 | `after/day_fire_low.png`、`after/night_fire_low.png`、`pixels_after.csv` |
| 吊灯/台灯/落地灯暖光 | 吊灯光晕已纳入昼夜调光（a，HEAD 重拍右上 ROI 近白 0）；台灯/落地灯沿用 P8.1 灯罩 glow + 解析点光，本轮未改参数 | `after/night_chand_near.png`、`after/night_room_wide.png` |
| 码头灯/船灯灯罩与照明 | 本轮未改（P8.1 已验收）；夜景整岛可读性：`night_island_lights` near-white 0、clip 0.46%，码头/船灯灯罩与光锥可辨 | `after/night_island_lights.png`、`pixels_after.csv` |
| 与冬季白化/积雪/雨天湿润协调 | 本轮未改材质；同机位冬/雪/雨截图实测 hearth_p99 208.6/210.5/207.6 clip=0、窗边梯度 11.02/8.33/9.53，无异常偏色或过曝 | `after/winter_day_room.png`、`after/snow_day_room.png`、`after/rain_night_room.png` |
| q0 低画质仍看出主要灯光 | q0/q2/q4 三档 `night_fire_low_qN` + `day_room_wide_qN` 真实拍摄；night_fire_low p99 q0=124.3 / q2=130.0 / q4=136.7、clip=0，q0 仍可辨炉火与暖光 | `02_lighting/qa/`、`pixels_qa.csv` |

## 回归（HEAD=befdb0f，串行器真实运行，日志 `02_lighting/regress/`）

| 探针 | 结果 | 说明 |
| --- | --- | --- |
| `probe_p82_fireplace --mode=geom` | **34 checks / 0 fail** | G8b 壁炉光槽不在任何实体盒内；G7f 栖点 (-2.070,14.526,-2.434) 不变；G9 ChimneyHit OK |
| `probe_p81_lights` | **147 checks / 0 fail** | 五档双池/预算/槽位/冬季夜间双池全 OK |
| `probe_p7v2_light` | 66 pass / **1 fail（预存在）** | PRE：路灯相对地形高度须在 [1.2,2.6] m（实测 2.84） |
| `probe_cottage6` | 26 pass / **5 fail（预存在）** | 含 "2 attic interior lights in light_sources (found 0)" 等；base 逐字复现 |
| `probe_p7v2_perch` | **265 pass / 0 fail** | |
| `probe_p8_ecology` | **41 checks / 0 fail PASS** | |
| `probe_p81_tree_bird` | **149 pass / 0 fail** | |
| `--selftest` | **全 PASS，EXIT=0**（20:42:30） | 含 P8 天气/低画质降雪/生态天气上下文 |

**新增失败 0**；两处失败均为历史预存在（任务书已登记）。

## 证据目录命名（本轮新增，重要）
- `02_lighting/before/`：**24 张** 2560×1440，冻结基线副本 base(ddcde3a) 拍摄（before 对照）。
- `02_lighting/after_pre_02/`：**02(a)(b) 提交之前**的当前分支快照（旧 24 张），仅作"a/b 改动前"中间对照，**不代表 HEAD**；
  对应像素表已改名 `pixels_after_pre_02.csv`。
- `02_lighting/after/`：**HEAD（befdb0f）重拍的 24 张**，同机位/同名/2560×1440，是本轮交付的 after 证据；
  像素表 `pixels_after.csv`。
- `02_lighting/qa/`：q0/q2/q4 三档生效证明 6 张（day_room_wide_qN / night_fire_low_qN）。
- 批脚本：`02_lighting/run_regress_p82_02.sh`（回归）、`run_shots_p82_02.sh`（before+qa）、`run_wave1..4.sh`（窗口批）。

## 原始日志
- `02_lighting/shots_after.log`：当前分支 24 张截图运行日志（EXIT=0）
- `02_lighting/shots_before.log`：base 副本 before 运行
- `02_lighting/batch/batch.log`：合批/光晕/自发光 bisect（42 个 Batch_ 节点清单）
