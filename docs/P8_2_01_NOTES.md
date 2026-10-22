# P8.2-01 壁炉几何：修复烟囱侵入室内导致火焰/炉膛不可见

- 阶段：P8.2 工程收尾/精修
- 分支：p82-integration（基线 ddcde3a = P8.1 冻结）
- 负责：teammate "lighting"
- 证据目录（git 外）：`D:/休闲小岛幻境/开发产物/p82/01_fireplace/`
  - `before/`：基线副本 ddcde3a 的 18 张同机位截图 + `before_geom.log`
  - `after/`：当前分支 20 张同机位截图 + `after_geom.log`
  - `regress/`：回归探针日志
  - `pixel/`：像素量化 CSV + before|after ROI 对比图
- 性质：**P8 既有缺陷**（非 P8.1 回归）。P8.1 报告 §6.6 已实测记录，本阶段修复。

## 1. 缺陷与根因

### 1.1 现象
一楼室内看壁炉只有一整块平整石面（石胸前脸），中央有一个模糊暗斑；看不到黑炉膛、看不到火焰、看不到柴薪。壁炉光槽（local z=-2.30）落在烟囱实体内部，导致"壁炉亮但照不出东西"。

### 1.2 根因（几何，不是灯光）
旧 `scripts/cottage.gd` 的烟囱主体是一整块 `M.box(size=(0.88,5.75,0.80), center=(ch_x,3.325,ch_z=-2.60))`：

| 件 | 旧尺寸 | 旧中心 | 旧 z 跨度 |
| --- | --- | --- | --- |
| 烟囱主体 | (0.88, 5.75, 0.80) | (-2.200, 3.325, -2.600) | **[-3.000, -2.200]** |
| y=1.60 石箍 | (1.00, 0.18, 0.92) | (-2.200, 1.600, -2.600) | [-3.060, -2.140] |
| 壁炉石胸 | (1.36, 1.62, 0.26) | (-2.200, 1.360, -2.670) | [-2.800, -2.540] |
| 黑膛板 | (0.82, 0.72, 0.06) | (-2.200, 1.050, -2.560) | [-2.590, -2.530] |
| 火焰盒 ×3 | (0.14, 0.07, 0.18) | y=0.710, z=-2.520 | [-2.610, -2.430] |
| halo（Quad） | 0.85 | (-2.200, 0.870, -2.420) | - |

后墙内表面在 z=-2.80（墙厚 0.30，外表面 -3.10）。烟囱主体前脸到 z=-2.20，即**侵入一层室内 0.60 m**，把石胸(前脸 -2.54)、黑膛板、火焰盒、halo 全部包在体内或挡在体后：
- 三机位射线：火焰可见 0/3，遮挡者都是烟囱主体（t=0.853 front / 0.808 low / 0.842 oblique）；
- 壁炉光槽 local=(-2.200,1.100,-2.300) 落在烟囱主体 AABB 内 → 光槽在实体里，室内表面只得到极弱/方向错误的衰减 → 石面中央暗斑；
- 唯一可见的是被 glow/tonemap 饱和后露在烟囱前脸外的 halo，形成"一整块硬边黄方块"。

## 2. 修复方式（最小增量，单文件 scripts/cottage.gd）

### 2.1 烟囱改为分段（不改 `ch_z`）
不改 `ch_z=-2.60` 的原因：烟囱栖点 `chimney_0`、`ChimneyTop` 节点（炊烟发射源 main.gd:666）、`ChimneyHit` 碰撞盒、筒瓦洞口跳过条件、泛水板/压顶/烟帽全部以 `ch_z` 定位；改 `ch_z` 会牵连 5 处外部契约。改用"上下分段"：

| 段 | 新尺寸 | 新中心 | 新 z 跨度 | 说明 |
| --- | --- | --- | --- | --- |
| 屋面以上（含阁楼） | (0.88, 3.10, 0.80) | (-2.200, 4.650, -2.600) | [-3.000, -2.200] | 外观与旧版完全一致；阁楼内仍是真实烟囱胸 |
| 一层/裙墙段薄烟道 | (0.88, 2.70, 0.26) | (-2.200, 1.790, -2.960) | **[-3.090, -2.830]** | 整体埋在后墙体(-3.10..-2.80)内，前后各留 0.01/0.03 避免共面 |
| 石箍 | 保留 y=3.40 / 5.40 两道 | — | [-3.060,-2.140] | y=1.60 那道原本只在一层室内可见，随侵入体一起删除 |

泛水板 / 泛水石 / 压顶 / 顶盖 / 顶钮 5 件保持原位（仍用 `ch_z`），烟帽最高点仍为 y=6.55，屋面交界/石箍/雪面外观不变。

### 2.2 壁炉石胸改为真实凹龛
旧石胸是一整块 (1.36,1.62,0.26)@z=-2.67（前脸 -2.54），即使烟囱退走也只是"一块更靠内的石板"。改为"两侧石柱 + 上楣"框架 + 退后的黑膛板 + 立起来的火焰：

| 件 | 新尺寸 | 新中心 | 说明 |
| --- | --- | --- | --- |
| 左右石柱 | (0.25, 1.62, 0.25) | x=ch_x±0.555, y=1.360, z=-2.675 | 前脸 z=-2.550 |
| 上楣 | (1.16, 0.81, 0.25) | (ch_x, 1.755, -2.670) | 前脸/顶面比石柱浅/低 1cm 防共面 |
| 炉膛地石 | (0.90, 0.09, 0.28) | (ch_x, 0.595, -2.660) | 顶面比炉台石低 1cm 形成台阶 |
| 黑膛板 | (0.82, 0.72, 0.06) | (ch_x, 0.990, -2.760) | z=[-2.790,-2.730]，凹龛后壁 |
| 柴薪 ×2 | r=0.07/0.06 | y=0.690/0.680, z=-2.660/-2.680 | 移进凹龛，不再与烟囱穿插 |
| 火焰 ×3 | (0.12,0.20,0.10)/(0.13,0.26,0.10)/(0.12,0.20,0.10) | x=ch_x-0.15/0/ +0.15, y=0.800/0.830/0.800, z=-2.630 | z=[-2.680,-2.580]，全部在凹龛内；三簇不等高 |
| halo | 0.85 → **0.34** | (-2.200, 0.910, -2.565) | 加色 billboard 收进凹龛，颜色 (2.4,1.2,0.45)→(1.7,0.85,0.32) |

保留不动：装饰石柱 (0.22,0.90,0.18)@x±0.48,z=-2.48；横梁 (1.34,0.18,0.22)@y=1.50,z=-2.47；木架 (1.46,0.09,0.28)@y=1.66,z=-2.44；炉台石 (1.70,0.10,0.60)@y=0.60,z=-2.24。
火焰材质仍为 `self_lit=true` 的 toon 自发光（不是真实 Light3D），glow 1.35→1.20；壁炉的局部照明仍由既有 `fireplace` 光槽提供，**光槽 local 位置 (-2.200,1.100,-2.300) 完全未改**（外部探针契约），只是现在它落在凹龛前方的室内、不再被实体包住。

开口净尺寸：x ±0.43（0.86 宽）× y 0.65..1.35（0.70 高），凹深 0.18~0.21 m。

### 2.3 新增的探针专用开关（不改变生产渲染路径）
`scripts/cottage.gd` 新增 `static var probe_skip_batch: bool = false`；`build()` 里把 `IsleBatch.merge_static(...)` 包进 `if not probe_skip_batch:`。生产路径该值恒为 false（无任何调用方设置它），合批行为与 P8.1 完全一致；只有 `tools/probe_p82_fireplace.gd --mode=geom` 会置 true，以便在真实构建的几何上逐件测 AABB（合批后 MeshInstance 会被消耗）。

## 3. 复现与探针

### 3.1 修复前（基线副本，只读）
```
# 几何断言
cd "D:/休闲小岛幻境/游戏工程" && bash "D:/休闲小岛幻境/开发产物/p82/run_godot.sh" --headless --path . \
  --script res://tools/probe_p82_fireplace.gd -- --mode=geom
# 结果：SUMMARY checks=30 fails=10
```
`before_geom.log` 的 10 条 FAILED_ITEM（原样记录）：
`G1, G2, G2b, G3c, G4b, G5, G6(front/low/oblique), G8b`
- G1 一层室内有进深 0.80m 的烟囱体侵入；
- G2/G2b 贴墙件进深超限（烟囱体 0.80、石胸 0.26 前脸越出）；
- G3c 黑膛板不在开口平面之后（前脸 -2.53 反而更靠近室内）；
- G4b 火焰有 0.11m 露在烟囱前脸 -2.20 之外；
- G5 halo 数量/位置不合凹龛（探针初版未识别 StandardMaterial3D 加色材质，已修）；
- G6 三机位火焰可见 0/3；
- G8b 壁炉光槽被烟囱实体 AABB 包住。

"before 截图"取法（不改冻结副本）：`cp -r 开发产物/p82/base 开发产物/p82/before_shot`，把探针拷进去、去掉其中对 `probe_skip_batch` 的引用（base=ddcde3a 无该 static var），用同一支探针 `--mode=shots` 在 base 上跑出 18 张；脚本见 `01_fireplace/patch_before_probe.py`。

### 3.2 修复后
```
# 几何断言（34 项）
cd "D:/休闲小岛幻境/游戏工程" && bash "D:/休闲小岛幻境/开发产物/p82/run_godot.sh" --headless --path . \
  --script res://tools/probe_p82_fireplace.gd -- --mode=geom
# => [P82FP] SUMMARY checks=34 fails=0
# 截图（20 张，窗口）
bash ".../run_godot.sh" --path . --resolution 1600x900 \
  --script res://tools/probe_p82_fireplace.gd -- --mode=shots --out=D:/休闲小岛幻境/开发产物/p82/01_fireplace/after/
# 像素量化
"<python>" "D:/休闲小岛幻境/开发产物/p82/01_fireplace/analyze_fireplace.py"
```
探针采集到逐件 MeshInstance3D 432 件（probe_skip_batch=true）；房屋原点 (0.8, 7.9456, -0.6)、yaw=0.30。

## 4. 真实数字（before → after，root 局部坐标；后墙内表面 z=-2.80）

| 件 | before | after |
| --- | --- | --- |
| 一层烟囱体 | (0.88,5.75,0.80) z=[-3.000,-2.200]，前脸 -2.20 | 薄烟道 (0.88,2.70,0.26) z=[-3.090,-2.830]，整体在墙内 |
| 屋面以上烟囱 | 同一块 | (0.88,3.10,0.80) z=[-3.000,-2.200] y=[3.100,6.200] |
| 石胸 | 整板 (1.36,1.62,0.26) z=[-2.800,-2.540] | 石柱 (0.25,1.62,0.25)×2 z=[-2.800,-2.550] + 上楣 (1.16,0.81,0.25) z=[-2.795,-2.545] |
| 黑膛板 | z=[-2.590,-2.530]（比开口更靠前） | z=[-2.790,-2.730]，凹深 0.18~0.21 |
| 火焰 | 0.14×0.07×0.18 平躺，z=[-2.610,-2.430]，0.11m 露出烟囱前脸 | 0.12~0.13×0.20~0.26×0.10 立起，z=[-2.680,-2.580]，全在凹龛内 |
| halo | 0.85 @z=-2.420（烟囱前脸外） | 0.34 @z=-2.565（凹龛内） |
| 火焰可见性 | front 0/3、low 0/3、oblique 0/3 | **front 3/3、low 3/3、oblique 3/3** |
| 壁炉光槽 | local (-2.200,1.100,-2.300)，被烟囱 AABB 包住 | 同一位置，**不在任何实体盒内** |
| 烟帽最高点 | 6.550 | 6.550（不变） |
| ChimneyTop world y | 14.496 | 14.496（不变） |
| 烟囱栖点 world | (-2.070,14.526,-2.434) kind=chimney | 同左（不变） |
| ChimneyHit | (-2.200,5.100,-2.600) size (1.1,2.9,1.1) | 同左（不变） |

### 像素量化（before vs after，同机位，2560×1440，ROI 由 after 高热像素包围盒确定）
高热像素 = R>230 且 G>150 且 B<200（火焰/炉火发光核心）；edge = ROI 内亮度梯度均值。

| 机位 | after hot_px | after hot_ratio | before hot_px | 倍数 | edge before→after | 判定 |
| --- | --- | --- | --- | --- | --- | --- |
| q0_fire_front | 43121 | 0.4021 | 0 | ∞ | 0.01676→0.03010 | PASS |
| q1_fire_front | 48083 | 0.4355 | 0 | ∞ | 0.01672→0.02656 | PASS |
| q2_fire_front | 48154 | 0.4350 | 0 | ∞ | 0.01672→0.02656 | PASS |
| q3_fire_front | 47851 | 0.4350 | 0 | ∞ | 0.01671→0.02648 | PASS |
| q4_fire_front | 47590 | 0.4341 | 0 | ∞ | 0.01679→0.02665 | PASS |
| q0_fire_oblique | 37078 | 0.3719 | 0 | ∞ | 0.01690→0.03062 | PASS |
| q1_fire_oblique | 41722 | 0.4058 | 0 | ∞ | 0.01681→0.02714 | PASS |
| q2_fire_oblique | 38281 | 0.3738 | 0 | ∞ | 0.01677→0.02753 | PASS |
| q3_fire_oblique | 36935 | 0.3629 | 0 | ∞ | 0.01687→0.02721 | PASS |
| q4_fire_oblique | 36205 | 0.3557 | 0 | ∞ | 0.01688→0.02753 | PASS |
| q2_fire_low | 68433 | 0.4706 | 0 | ∞ | 0.01674→0.02455 | PASS |
| day_fire_front | 47043 | 0.4321 | 0 | ∞ | 0.00975→0.02424 | PASS |
| day_fire_oblique | 37192 | 0.3681 | 0 | ∞ | 0.01051→0.02460 | PASS |

结论：修复前**任何机位、任何画质（含白天）的高热像素都是 0**（火焰完全不可见）；修复后五档 + 白天 + 俯角机位均有 3.6 万~6.8 万高热像素，ROI 内占比 36%~47%，边缘密度提升 1.5~1.6 倍（火焰舌与炉膛结构可分辨）。原始数据：`01_fireplace/pixel/fireplace_pixels.csv`，逐机位 before|after 裁剪对比图：`01_fireplace/pixel/cmp_<tag>.png`。

## 5. 截图（真实窗口，2560×1440；before 来自 base 副本同机位同参数）
- before：`D:/休闲小岛幻境/开发产物/p82/01_fireplace/before/`（18 张）
- after：`D:/休闲小岛幻境/开发产物/p82/01_fireplace/after/`（20 张）
- 命名：`q<0..4>_fire_front`、`q<0..4>_fire_oblique`、`q2_fire_low`、`q2_room_wide`、`q2_exterior_chimney`、`q2_attic_view`、`q2_attic_chimney_side`、`q2_attic_breast`、`day_fire_front`、`day_fire_oblique`、`day_room_wide`、`day_attic_breast`
- 结构验收：屋外烟囱只露屋面以上部分，石箍/泛水石/压顶/顶盖/顶钮完整，雪面与屋顶交界自然，海鸥仍栖在檐口/屋脊；阁楼家具与屋面结构正常。

## 6. 回归（当前 HEAD 复跑；日志在 `01_fireplace/regress/`）

| 探针 | 结果 | 历史基线 | 新增失败 |
| --- | --- | --- | --- |
| `tools/probe_cottage6.gd` | pass=26 fail=5（`regress/cottage6.log`） | 5 项预存在 | 无（同样 5 条） |
| `tools/probe_p7v2_perch.gd` | pass=265 fail=0 | 265/0 | 无 |
| `tools/probe_p8_ecology.gd` | checks=41 fail=0 | 41/0 | 无 |
| `tools/probe_p81_tree_bird.gd` | pass=149 fail=0 | 149/0 | 无 |
| `--selftest`（窗口） | 75/75 passed（`regress/selftest.log`） | 73/73（本代新增 2 项） | 无 |
| `tools/probe_scale_world.gd -- --mode audit` | pass=90 warn=0 fail=0 info=17 | 90/0 | 无 |
| `tools/probe_scale_house_p7v32.gd` | checks=252 pass=245 fail=7（EXIT=1） | 未登记过 | 见下：**预存在** |

cottage6 的 5 条失败与历史完全一致（原样）：`box1 center matches root.transform*local`、`solid coverage: 5/7 wall/roof/chimney points inside boxes`、`beam occlusion behaviour: 13/15 probes as expected`、`perches standing on real roof surface (gap 0.012..0.080 m): 12/14 ok`、`2 attic interior lights in light_sources (found 0)`。

probe_scale_house_p7v32 的 7 条失败全部落在"光源契约"（`CONTRACT.lights` / `LIGHT.fireplace_pos` / `LIGHT.lantern_y`×2 / `LIGHT.lanterns` / `LIGHT.window_lights` / `LIGHT.anchors`），**不是本次几何改动引入**：
1. `git show ddcde3a:scripts/cottage.gd` 显示基线就已是 P8.1-06 的双池聚合结构（`light_sources` 10 项 = `porch_lantern` + `window_glow` 两个聚合槽 + 8 盏室内灯；返回字典已含 `lantern_mid_world`/`window_glow_world`/`table_lamp_world`/`floor_lamp_world`/`attic_bedside_lamp_world`/`attic_desk_lamp_world`），该探针的期望（6 固定 + 5 窗、2 盏门廊灯各自独立）停留在 P8.1-06 之前；
2. 实测证据：在基线副本 `开发产物/p82/before_shot`（=ddcde3a）上跑同一支探针（仅把日志输出改到本证据目录，避免覆盖 P8.1 日志），结果 `checks=252 pass=245 warn=0 fail=7`，7 条与当前分支**逐字相同**（`regress/base_scale_house_p7v32.log` / `base_scale_house_stdout.log`）。
本阶段 diff 未触碰 `light_sources` 数组与任何灯光槽。结论：登记为预存在契约漂移，P8.2-02 处理灯光时若改动 `light_sources` 结构需一并更新该探针期望。

## 7. 未完成 / 限制
1. 火焰仍是 3 个 `self_lit` toon 盒（P8 既有视觉语言），没有引入粒子/真实 Light3D；火舌轮廓是方柱状，与全组件的美术风格一致但不是拟真火焰。
2. halo 仍存在（0.34，颜色 (1.7,0.85,0.32)）；它在凹龛内起"暖光晕"作用，近景不饱和成硬边方块，但没有做逐画质的 halo 收缩（属 P8.2-02 灯光质量范围）。
3. 烟囱一层段改成墙内薄烟道后，**室外近看**后墙该处没有可见烟囱（原本也被墙体挡住/不可见），屋顶以上外观不变；一层墙体若被破坏性视角（穿墙调试）会看到薄烟道比旧主体薄。
4. `probe_skip_batch` 是仅供探针使用的静态开关；生产路径未设置，合批结果与 P8.1 一致（截图以合批路径产出，尺寸/外观可对比）。
5. 阁楼段烟囱胸在旧机位被床/屋面遮挡，已补 `q2_attic_breast` / `day_attic_breast` 两个正对机位确认结构完整。
