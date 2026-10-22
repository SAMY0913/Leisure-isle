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

## 原始日志
- `02_lighting/shots_after.log`：当前分支 24 张截图运行日志（EXIT=0）
- `02_lighting/shots_before.log`：base 副本 before 运行
- `02_lighting/batch/batch.log`：合批/光晕/自发光 bisect（42 个 Batch_ 节点清单）
