# 《休闲小岛幻境》世界尺度规范（WORLD_SCALE_SPEC）

> **版本**：P7-V3.2 · v1.3（按 Lead m00438 口径修订 + 标尺运行时自检，2026-10-21）
> **适用工程**：Godot 4.7.2 stable · Forward+ · 工程 `D:/休闲小岛幻境/游戏工程`（分支 `p7-v3.2`，基线 `eaf1559` = V3.1）
> **作者**：T1 尺度工具与审计（scale-tools）· 主责文件：`scripts/isle_scale_spec.gd`、`scripts/isle_scale_figure.gd`、`tools/probe_scale_world.gd`、`tools/scale_debug_overlay.gd`、本文档
> **实测来源（全部真实运行，无手工编造）**：
> - 基线原始尺寸：`开发产物/p7v32/scale/inventory_baseline.json` / `.md`（wt_baseline，detached `eaf1559`，headless inventory 模式，102 项）
> - 当前主树：`开发产物/p7v32/scale/inventory.json` / `.md`（headless audit 模式，对照本规范判定，107 项）
> - 日志：`开发产物/p7v32/logs/scale_audit_main.log`、`开发产物/p7v32/logs/scale_inventory_baseline.log`、标尺自检 `开发产物/p7v32/logs/scale_overlay_selftest.log`
> **复现命令**（`ENG=D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe`）：
> ```powershell
> # 当前主树审计（有 FAIL 退出码 1，可进 CI）
> & $ENG --headless --path D:/休闲小岛幻境/游戏工程 --script res://tools/probe_scale_world.gd -- --mode audit --tag scale_audit_main
> # 基线清单（wt_baseline 内 untracked 探针，只记录不判分）
> & $ENG --headless --path D:/休闲小岛幻境/开发产物/p7v32/wt_baseline --script res://tools/probe_scale_world.gd -- --mode inventory --tag scale_inventory_baseline
> # 开发标尺运行时自检（headless 真实实例化，11 项断言）
> & $ENG --headless --path D:/休闲小岛幻境/游戏工程 --script res://tools/probe_scale_world.gd -- --mode overlay --tag scale_overlay_selftest
> # 规范文档表格同步（从 inventory*.json 重建，幂等）
> node "D:/休闲小岛幻境/开发产物/p7v32/scale/update_spec_tables.mjs" [--write]
> ```

## 0. 当前审计结果摘要

- 当前主树：`[SCALE] RESULT pass=90 warn=0 fail=0 info=17 mode=audit tag=scale_audit_main`（PASS 90 / WARN 0 / FAIL 0 / INFO 17）
- 基线：`[SCALE] RESULT pass=0 warn=0 fail=0 info=102 mode=inventory tag=scale_inventory_baseline`（inventory 只记录实测值，不判分）
- 本轮 m00438 四项口径修订结果：烟囱顶读真实几何 AABB **+0.350 m PASS**；屋脊/屋顶结构线（root meta `ridge_y=6.20`、`roof_base=3.73`）**2.470 m PASS**；`camera_fov` 区间改 **[32,75]**（默认 42° 保留）**PASS**；`boat_freeboard` 区间改 **[0.25,0.78]**、midship/max sheer 双口径登记 **PASS**（midship 实测 0.535 m，最高舷弧 0.724 m；T4 的 0.660 为四分之一站位口径，站位定义差异已在 §5 说明）。
- 无 FAIL / 无 WARN；INFO = reference_keep 7 项（§7）+ 双口径/世界量法/仅登记 10 项（不作为评分）。
- 开发标尺运行时自检（`probe_scale_world.gd --mode overlay`，headless 真实实例化）：`[SCALE] RESULT pass=11 warn=0 fail=0 info=0 mode=overlay tag=scale_overlay_selftest`（exit 0）；详见 §11。

| 组 | 项数 | PASS | WARN | FAIL | INFO |
| --- | --- | --- | --- | --- | --- |
| 1.50 m 人体参照 | 13 | 13 | 0 | 0 | 0 |
| 测量自检（识别整节点缩放漂移） | 1 | 1 | 0 | 0 | 0 |
| 房屋 / 门窗 / 楼梯 / 门廊 | 34 | 34 | 0 | 0 | 0 |
| 25 项家具 | 25 | 25 | 0 | 0 | 0 |
| 船只 / 码头 / 灯塔 / 路灯 / 树木 / 生物 / 环境 | 29 | 13 | 0 | 0 | 16 |
| 相机与灯光 | 5 | 4 | 0 | 0 | 1 |

## 1. 单位与坐标规范

| 规范 | 取值 | 说明 |
| --- | --- | --- |
| 世界单位 | **1 Godot 单位 = 1 米** | `IsleScaleSpec.UNITS_PER_METER = 1.0`、`CM = 0.01` |
| 人体基准 | 1.50 m（裸足脚底→头顶） | 绘本夸张的小人国比例：1.50 m 人 ≈ 门洞净高 1.94 m 的 77% |
| 建筑基准 | 门洞净高 1.94 m / 一层净高 2.42 m / 楼梯 16 级 × 0.16375 m | 见 §2、§3 |
| 坐标 | 世界 Y 为高度、海面 y=0；房屋局部 +Z 为正面（门所在立面），屋脊沿局部 +Z | `cottage.gd` 局部坐标系 |
| 缩放禁令 | **禁止用整节点 scale 冒充重建**（仅 Lead 同意、比例本已统一的装饰件例外） | 审计用"父节点 scale=2 自检"抓漂移：参照人形在缩放父节点下实测 3.000 m 即判 FAIL |
| 标尺显示 | 仅开发测量模式（CLI `--scale-debug`），默认隐藏、不进发布 | `tools/scale_debug_overlay.gd` |
| 容差 | 单轴 `TOL=±5%` / `WARN_TOL=±10%` / 绝对值 `TOL_ABS=±0.010 m`；区间项：区间内 PASS、超区间 10% 宽 WARN、再外 FAIL | `IsleScaleSpec.check()/check_range()` |

## 2. 1.50 m 人体参照（`scripts/isle_scale_figure.gd`）

定义：脚底局部 y=0、头顶世界 AABB 高 **1.500 ± 0.010 m**；12 个 MeshInstance（脚/腿/髋/躯干/颈/头/臂/手）；landmark 标记 Node3D（foot/ankle/knee/hip/waist/hand/shoulder/chin/eye/head_top）；材质复用 `IsleMath.toon_material`（醒目橙/黄/蓝），无动画、无 `_process`。API：

```gdscript
static func build(parent: Node3D, pos: Vector3, yaw: float = 0.0) -> Node3D
static func measure(node: Node3D) -> Dictionary  # world/local AABB、height、foot_y_world、landmarks、ancestor_scale（父节点缩放会如实放大）
static func world_height(node: Node3D) -> float
```

| 项目 | V3.1 原始实测（基线 wt_baseline） | 目标 / 范围 | 当前主树实测 | 状态 | 对应资产脚本 · 节点 | 依据 / 变更原因与测试结果 |
| --- | --- | --- | --- | --- | --- | --- |
| height | 1.500 m | 1.500 m | 1.500 m | 符合 | scripts/isle_scale_figure.gd · 12 MeshInstance（Ref_*） | human_ref 世界 AABB 高 实测 1.5000 m / 目标 1.500 ± 0.010 m（脚底世界 y=50.000） |
| bbox_hw_d | 0.47 × 1.50 × 0.24 | 0.47 × 1.50 × 0.24 | 0.47 × 1.50 × 0.24 | 符合 | scripts/isle_scale_figure.gd · 世界 AABB | bbox_hw_d 实测 0.470×1.500×0.240 m / 目标 0.470×1.500×0.240 m（最大轴 +0.0%；宽含双臂外缘/深含身体） |
| foot_local_y | 0.000 m | 0.000 m | 0.000 m | 符合 | Ref_Foot_L/R（脚底局部 y=0） | foot_local_y 实测 0.000 m / 目标 0.000 m（绝对误差 0.000，容差 ±0.002；脚底必须贴在局部 y=0） |
| landmark_foot | 0.000 m | 0.000 m | 0.000 m | 符合 | scripts/isle_scale_figure.gd · LM_foot_L/R landmark | landmark_foot 实测 0.000 m / 目标 0.000 m（绝对误差 0.000，容差 ±0.030；landmark 高度（相对脚底）） |
| landmark_ankle | 0.060 m | 0.060 m | 0.060 m | 符合 | scripts/isle_scale_figure.gd · LM_ankle_L/R landmark | landmark_ankle 实测 0.060 m / 目标 0.060 m（绝对误差 0.000，容差 ±0.030；landmark 高度（相对脚底）） |
| landmark_knee | 0.420 m | 0.420 m | 0.420 m | 符合 | scripts/isle_scale_figure.gd · LM_knee_L/R landmark | landmark_knee 实测 0.420 m / 目标 0.420 m（绝对误差 0.000，容差 ±0.030；landmark 高度（相对脚底）） |
| landmark_hip | 0.780 m | 0.780 m | 0.780 m | 符合 | scripts/isle_scale_figure.gd · LM_hip_L/R landmark | landmark_hip 实测 0.780 m / 目标 0.780 m（绝对误差 0.000，容差 ±0.030；landmark 高度（相对脚底）） |
| landmark_waist | 0.920 m | 0.920 m | 0.920 m | 符合 | scripts/isle_scale_figure.gd · LM_waist_L/R landmark | landmark_waist 实测 0.920 m / 目标 0.920 m（绝对误差 0.000，容差 ±0.030；landmark 高度（相对脚底）） |
| landmark_hand | 0.950 m | 0.950 m | 0.950 m | 符合 | scripts/isle_scale_figure.gd · LM_hand_L/R landmark | landmark_hand 实测 0.950 m / 目标 0.950 m（绝对误差 0.000，容差 ±0.030；landmark 高度（相对脚底）） |
| landmark_shoulder | 1.240 m | 1.240 m | 1.240 m | 符合 | scripts/isle_scale_figure.gd · LM_shoulder_L/R landmark | landmark_shoulder 实测 1.240 m / 目标 1.240 m（绝对误差 0.000，容差 ±0.030；landmark 高度（相对脚底）） |
| landmark_chin | 1.320 m | 1.320 m | 1.320 m | 符合 | scripts/isle_scale_figure.gd · LM_chin_L/R landmark | landmark_chin 实测 1.320 m / 目标 1.320 m（绝对误差 0.000，容差 ±0.030；landmark 高度（相对脚底）） |
| landmark_eye | 1.380 m | 1.380 m | 1.380 m | 符合 | scripts/isle_scale_figure.gd · LM_eye_L/R landmark | landmark_eye 实测 1.380 m / 目标 1.380 m（绝对误差 0.000，容差 ±0.030；landmark 高度（相对脚底）） |
| landmark_head_top | 1.500 m | 1.500 m | 1.500 m | 符合 | scripts/isle_scale_figure.gd · LM_head_top_L/R landmark | landmark_head_top 实测 1.500 m / 目标 1.500 m（绝对误差 0.000，容差 ±0.030；landmark 高度（相对脚底）） |

| 项目 | V3.1 原始实测（基线 wt_baseline） | 目标 / 范围 | 当前主树实测 | 状态 | 对应资产脚本 · 节点 | 依据 / 变更原因与测试结果 |
| --- | --- | --- | --- | --- | --- | --- |
| scaled_parent_measured | 3.000 m | 3.000 m | 3.000 m | 符合 | 探针自检：父节点 scale=2 重建 1.50 m | 父节点 scale=2 时测得世界高 3.000 m（期望 3.000）→ AABB 测量能暴露整节点缩放漂移 |

## 3. 房屋基准（`scripts/cottage.gd` + `scripts/isle_math.gd`）

目标常量（Lead 定稿、`IsleScaleSpec` 同步登记）：`HOUSE_W=7.60`、`HOUSE_D=6.20`、`HOUSE_WALL_H=3.18`、`HOUSE_ROOF_H=2.47`、`HOUSE_RIDGE_Y=6.20`（自 `fy=0.55` 起算）、`HOUSE_WALL_T=0.30`、`HOUSE_EAVE_OV=0.60`、`HOUSE_PITCH_DEG=33.0`、`HOUSE_ATTIC_FLOOR_Y=3.17`、`HOUSE_ATTIC_KNEE_H=0.56`、`HOUSE_CHIMNEY_ABOVE_RIDGE=0.35`；门洞净 1.14×1.94 m；窗 1.00×1.15（前）/1.00×0.95（侧）/0.90×0.90（后）/1.50×1.50（阁楼）；楼梯 16 级 × rise 0.16375 / tread 0.26 / 宽 0.85 / 平台 0.85 / 扶手 0.85 / 净空 ≥1.95；门廊台面 0.42–0.44、台阶 3 级 × 0.14。

**结构线口径（m00438 修订）**：屋脊/屋顶高/坡度/膝墙统一用 cottage `root.get_meta("cottage_ctx")` 的施工结构线（`ridge_y=6.20`、`roof_base=3.73`、`attic_floor=3.17`）；真实几何 AABB 的屋脊顶为 **6.384 m**（含脊瓦厚度 +0.184 m），只作为 RAW `house.ridge_geom` 登记，不参与判定。烟囱顶读**真实几何**（root `batch_manifest` 中烟囱平面附近部件的 AABB 顶 = **6.550 m**），不读 `ChimneyTop` 标记节点（该标记在 6.25 m，比真实石块顶低 0.30 m）。

测量方法（全部读真实生成网格；合并后读 `batch_manifest` 顶点/部件，非登记表）：
- **外廓**：每方向 9/11 条射线取**众数**（墙面占多数，门洞/窗洞/线脚为少数，避免被凹进拉偏）；墙厚 0.30、檐口挑出 0.60。
- **地坪/天花/阁楼楼板**：`batch_manifest` 结构大板 AABB 顶/底（headless 下 MultiMesh 实例变换不可读，不能读楼板条 MultiMesh，见 §9）。
- **屋脊/屋顶高/坡度/膝墙**：结构线（`cottage_ctx`）+ 几何交叉验证（坡度 `atan2(ridge−roof_base, w/2)`；膝墙 `roof_base−attic_floor`）。
- **门洞**：T2 新 cottage 构建时写 `root.set_meta("door_clear", {w,h,spring_y,arch_ri,arch_ro,fanlight_r,handle_h,...})`，运行时净尺寸为权威；保留前墙外皮 25 cm 内**射线-三角扫描**作交叉验证（RAW `house.door.geom`）。纯射线会把门套内凹算进去（1.06 vs 1.14）。
- **窗**：各窗容器下真实玻璃 BoxMesh（非 toon）AABB + 0.02 缝；侧窗容器旋转 90° 做朝向修正；阁楼窗读 `AtticWindow` 双层玻璃。
- **楼梯**：优先读 `Staircase` 运行时 meta（`risers/rise/tread/width/land_top/attic_floor`、平台 `landing_size`、扶手 `handrail_top_offset`）；几何法保留作 RAW（几何 tread 含 0.05 压边，meta 更准）。
- **门廊**：`PorchSteps` meta `top_y/rise/run/step_count` + 台面顶点实测交叉校验（几何 0.39 与 meta 0.42 差 >0.02 时采用 meta 并注明来源）。

| 项目 | V3.1 原始实测（基线 wt_baseline） | 目标 / 范围 | 当前主树实测 | 状态 | 对应资产脚本 · 节点 | 依据 / 变更原因与测试结果 |
| --- | --- | --- | --- | --- | --- | --- |
| outer_w | 10.600 m | 7.600 m | 7.600 m | 符合 | scripts/cottage.gd · 外墙盒（_walls）+ IsleMath.HOUSE_W | outer_w 实测 7.600 m / 目标 7.600 m（+0.0%；外墙外皮宽（x 向）） |
| outer_d | 8.400 m | 6.200 m | 6.200 m | 符合 | cottage.gd · 外墙盒 + IsleMath.HOUSE_D | outer_d 实测 6.200 m / 目标 6.200 m（+0.0%；外墙外皮深（z 向）） |
| wall_h | 5.580 m | 3.180 m | 3.180 m | 符合 | cottage.gd · _walls 墙顶 + IsleMath.HOUSE_WALL_H | wall_h 实测 3.180 m / 目标 3.180 m（+0.0%；fy→墙顶（檐口结构线）） |
| ridge_y | 9.750 m | 6.200 m | 6.200 m | 符合 | cottage.gd · root meta cottage_ctx.ridge_y（结构线；几何 AABB 含脊瓦记 RAW） | ridge_y 实测 6.200 m / 目标 6.200 m（+0.0%；屋脊结构线（root meta cottage_ctx.ridge_y；几何 AABB 6.384 含脊瓦厚度 → RAW house.ridge_geom）） |
| roof_h | 3.600 m | 2.470 m | 2.470 m | 符合 | cottage.gd · ridge_y − roof_base 结构线 | roof_h 实测 2.470 m / 目标 2.470 m（+0.0%；檐口结构线→屋脊结构线（roof_base→ridge_y）） |
| pitch_deg | 34.2 ° | 33.0 ° | 33.0 ° | 符合 | cottage.gd · _roof 坡面几何 | pitch_deg 实测 33.024 deg / 目标 33.000 deg（绝对误差 0.024，容差 ±2.500；几何法：atan2(实测屋脊-实测墙顶, 实测外墙半宽)；法线法结果见 RAW house.pitch_normals） |
| eave_overhang_h | 0.744 m | 0.503 m | 0.506 m | 符合 | cottage.gd · _roof 檐口出挑 + IsleMath.HOUSE_EAVE_OV | eave_overhang_h 实测 0.506 m / 目标 0.503 m（绝对误差 0.003，容差 ±0.100；檐口水平挑出（沿坡 0.60 → 水平 0.50）） |
| room_clear | 3.580 m | 2.420 m | 2.420 m | 符合 | cottage.gd · 一层天花板板 + IsleMath.ROOM_CLEAR_H | room_clear 实测 2.420 m / 目标 2.420 m（+0.0%；一层地板面→阁楼楼板底） |
| attic_floor_y | 5.700 m | 3.170 m | 3.170 m | 符合 | cottage.gd · 阁楼楼板大板 + IsleMath.HOUSE_ATTIC_FLOOR_Y | attic_floor_y 实测 3.170 m / 目标 3.170 m（+0.0%；阁楼楼板顶标高（局部 y）） |
| attic_knee_h | 0.450 m | 0.560 m | 0.560 m | 符合 | cottage.gd · roof_base − attic_floor（cottage_ctx） | attic_knee_h 实测 0.560 m / 目标 0.560 m（绝对误差 0.000，容差 ±0.120；阁楼膝墙高 = 实测墙顶 − 实测阁楼楼板顶（檐口平面定义）） |
| door_opening | 2.58 × 3.42 × 0.30 | 1.14 × 1.94 × 0.30 | 1.14 × 1.94 × 0.30 | 符合 | cottage.gd · DoorPivot/DoorArch · root meta door_clear | door_opening 实测 1.140×1.940×0.300 m / 目标 1.140×1.940×0.300 m（最大轴 +0.0%；T2 新 cottage root meta door_clear 净尺寸（w=1.14,h=1.94；射线实测 RA… |
| door_handle_h | 1.030 m | 0.950 m | 0.950 m | 符合 | cottage.gd · DoorPivot 把手 sphere | door_handle_h 实测 0.950 m / 目标 0.950 m（绝对误差 0.000，容差 ±0.060；门把手中心高（自室内地面；T2 meta handle_h 优先，射线实测 RAW house.door.handle_h = 0.950）） |
| window_front | 1.40 × 1.70 × 0.10 | 1.00 × 1.15 × 0.10 | 1.00 × 1.15 × 0.10 | 符合 | cottage.gd · WindowFront_0/1 玻璃 BoxMesh | window_front 实测 1.000×1.150×0.100 m / 目标 1.000×1.150×0.100 m (误差 0.0%)；玻璃实测 宽0.980/厚0.035 + 0.02 缝 = 洞口；z 用登记墙厚 |
| sill_h_window_front | 1.440 m | 0.900 m | 0.915 m | 符合 | WindowFront_* 玻璃底 − 地坪 | sill_h_window_front 实测 0.915 m / 目标 0.900 m（绝对误差 0.015，容差 ±0.120；窗台高（自室内地面）） |
| window_front | —（基线无此项） | 1.00 × 1.15 × 0.10 | 1.00 × 1.15 × 0.10 | 符合 | cottage.gd · WindowFront_0/1 玻璃 BoxMesh | window_front 实测 1.000×1.150×0.100 m / 目标 1.000×1.150×0.100 m (误差 0.0%)；玻璃实测 宽0.980/厚0.035 + 0.02 缝 = 洞口；z 用登记墙厚 |
| sill_h_window_front | —（基线无此项） | 0.900 m | 0.915 m | 符合 | WindowFront_* 玻璃底 − 地坪 | sill_h_window_front 实测 0.915 m / 目标 0.900 m（绝对误差 0.015，容差 ±0.120；窗台高（自室内地面）） |
| window_side | 1.50 × 1.30 × 0.10 | 1.00 × 0.95 × 0.10 | 1.00 × 0.95 × 0.10 | 符合 | cottage.gd · WindowSideL/R 玻璃 | window_side 实测 1.000×0.950×0.100 m / 目标 1.000×0.950×0.100 m (误差 0.0%)；玻璃实测 宽0.980/厚0.035 + 0.02 缝 = 洞口；z 用登记墙厚 |
| sill_h_window_side | 1.790 m | 0.900 m | 0.910 m | 符合 | WindowSideL/R 玻璃底 − 地坪 | sill_h_window_side 实测 0.910 m / 目标 0.900 m（绝对误差 0.010，容差 ±0.120；窗台高（自室内地面）） |
| window_back | 1.40 × 1.30 × 0.10 | 0.90 × 0.90 × 0.10 | 0.90 × 0.90 × 0.10 | 符合 | cottage.gd · WindowBack 玻璃 | window_back 实测 0.900×0.900×0.100 m / 目标 0.900×0.900×0.100 m (误差 0.0%)；玻璃实测 宽0.880/厚0.035 + 0.02 缝 = 洞口；z 用登记墙厚 |
| sill_h_window_back | 1.840 m | 0.900 m | 0.910 m | 符合 | WindowBack 玻璃底 − 地坪 | sill_h_window_back 实测 0.910 m / 目标 0.900 m（绝对误差 0.010，容差 ±0.120；窗台高（自室内地面）） |
| window_attic | 3.32 × 2.72 × 0.10 | 1.50 × 1.50 × 0.10 | 1.48 × 1.46 × 0.10 | 符合 | cottage.gd · AtticWindow 玻璃 | window_attic 实测 1.480×1.460×0.100 m / 目标 1.500×1.500×0.100 m (误差 2.7%)；玻璃实测 宽1.460 + 0.02 缝；z 用登记墙厚 |
| attic_window_bottom | -0.050 m | 0.100 m | 0.130 m | 符合 | AtticWindow 玻璃底 − 阁楼楼板 | attic_window_bottom 实测 0.130 m / 目标 0.100 m（绝对误差 0.030，容差 ±0.100；阁楼窗底高（自阁楼楼板）） |
| stair_rise | 0.191 m | 0.164 m | 0.164 m | 符合 | cottage.gd · Staircase meta rise | stair_rise 实测 0.164 m / 目标 0.164 m（+0.0%；实测踏高（相邻踏面高差中位数）） |
| stair_tread | 0.295 m | 0.260 m | 0.260 m | 符合 | Staircase meta tread | stair_tread 实测 0.260 m / 目标 0.260 m（+0.0%；实测踏面深（Flight A 踏面 z 尺寸）） |
| stair_width | 1.100 m | 0.850 m | 0.850 m | 符合 | Staircase meta width | stair_width 实测 0.850 m / 目标 0.850 m（+0.0%；实测梯段净宽（Flight A 踏面 x 尺寸）） |
| stair_total_rise | 5.191 m | 2.620 m | 2.560 m | 符合 | Staircase 踏面几何 + attic_floor | stair_total_rise 实测 2.560 m / 目标 2.620 m（绝对误差 0.060，容差 ±0.100；第一级踏面顶到阁楼楼板底的总升（几何法比设计总升少约一级踏高，容差 ±0.10；设计总升 = 16 级 × 0.1638 = 2.62 … |
| stair_landing | 0.950 m | [0.80 – 1.00] m | 0.850 m | 符合 | Staircase 平台板 meta landing_size | stair_landing 实测 0.850 m / 区间 [0.800, 1.000] PASS → PASS；平台短边实测 |
| stair_handrail_h | 0.835 m | 0.850 m | 0.940 m | 符合 | Staircase · StairHandrailA meta handrail_top_offset | stair_handrail_h 实测 0.940 m / 目标 0.850 m（绝对误差 0.090，容差 ±0.100；平台/梯段扶手高） |
| stair_count | 27 级 | 16 级 | 16 级 | 符合 | Staircase meta risers | 实测踏面数 16 / 目标 16 |
| porch_deck_y | 0.420 m | [0.42 – 0.44] m | 0.420 m | 符合 | cottage.gd · PorchSteps meta top_y（几何台面已交叉校验） | porch_deck_y 实测 0.420 m / 区间 [0.420, 0.440] PASS → PASS；门廊台面（向上面实测） |
| porch_step_rise | 0.210 m | 0.140 m | 0.140 m | 符合 | PorchSteps meta rise | porch_step_rise 实测 0.140 m / 目标 0.140 m（绝对误差 0.000，容差 ±0.050；门廊台阶实测踏高） |
| porch_step_run | 3.000 m | 0.300 m | 0.300 m | 符合 | PorchSteps meta run | porch_step_run 实测 0.300 m / 目标 0.300 m（绝对误差 0.000，容差 ±0.080；门廊台阶实测踏面深） |
| porch_step_count | 3 级 | 3 级 | 3 级 | 符合 | PorchSteps meta step_count | 门廊台阶实测级数 3（Plan 目标 3 级×0.14） |
| chimney_above_ridge | 0.520 m | 0.350 m | 0.350 m | 符合 | cottage.gd · _chimney 真实部件 AABB 顶（root batch_manifest）− 屋脊结构线 | chimney_above_ridge 实测 0.350 m / 目标 0.350 m（绝对误差 0.000，容差 ±0.200；烟囱真实几何 AABB 顶（batch_manifest 烟囱平面附近部件）− 屋脊结构线；ChimneyTop 标记仅参考（RA… |

## 4. 25 项家具（`scripts/isle_house_props.gd`）

对 `IsleHouseProps.kinds()` 的 25 类逐个 `build()` 到临时 holder（真实生成全部 MeshInstance），合并世界 AABB（剔除 `Glow/Halo/Blob/Shadow` 前缀与透明材质），按 宽×高×深 与注册表目标比对（坐标轴归一化，摆放 yaw 不影响）。T3 已改造，当前 25/25 PASS；V3.1 原始值见"原始实测"列，前后对比即本轮改动依据。

| 项目 | V3.1 原始实测（基线 wt_baseline） | 目标 / 范围 | 当前主树实测 | 状态 | 对应资产脚本 · 节点 | 依据 / 变更原因与测试结果 |
| --- | --- | --- | --- | --- | --- | --- |
| armchair | 0.86 × 0.84 × 0.84 | 0.72 × 0.78 × 0.76 | 0.72 × 0.78 × 0.76 | 符合 | scripts/isle_house_props.gd · Prop_<kind>_<seq> | armchair 实测 0.720×0.777×0.760 m / 目标 0.720×0.780×0.760 m (误差 0.3%)；真实 Mesh AABB（排除发光/光晕/影子） |
| bed | 1.40 × 0.95 × 2.05 | 1.00 × 0.85 × 1.90 | 1.00 × 0.85 × 1.90 | 符合 | scripts/isle_house_props.gd · Prop_<kind>_<seq> | bed 实测 1.000×0.850×1.900 m / 目标 1.000×0.850×1.900 m (误差 0.0%)；真实 Mesh AABB（排除发光/光晕/影子） |
| bookshelf | 0.95 × 1.90 × 0.32 | 0.85 × 1.75 × 0.30 | 0.85 × 1.75 × 0.30 | 符合 | scripts/isle_house_props.gd · Prop_<kind>_<seq> | bookshelf 实测 0.850×1.750×0.300 m / 目标 0.850×1.750×0.300 m (误差 0.0%)；真实 Mesh AABB（排除发光/光晕/影子） |
| chair | 0.46 × 0.90 × 0.46 | 0.42 × 0.85 × 0.44 | 0.42 × 0.85 × 0.44 | 符合 | scripts/isle_house_props.gd · Prop_<kind>_<seq> | chair 实测 0.420×0.850×0.440 m / 目标 0.420×0.850×0.440 m (误差 0.0%)；真实 Mesh AABB（排除发光/光晕/影子） |
| coat_rack | 1.00 × 0.81 × 0.16 | 0.80 × 1.20 × 0.14 | 0.80 × 1.20 × 0.14 | 符合 | scripts/isle_house_props.gd · Prop_<kind>_<seq> | coat_rack 实测 0.800×1.200×0.140 m / 目标 0.800×1.200×0.140 m (误差 0.0%)；真实 Mesh AABB（排除发光/光晕/影子） |
| coffee_table | 1.10 × 0.42 × 0.55 | 0.95 × 0.38 × 0.50 | 0.95 × 0.38 × 0.50 | 符合 | scripts/isle_house_props.gd · Prop_<kind>_<seq> | coffee_table 实测 0.950×0.380×0.500 m / 目标 0.950×0.380×0.500 m (误差 0.0%)；真实 Mesh AABB（排除发光/光晕/影子） |
| curtain | 0.75 × 1.66 × 0.09 | 0.70 × 1.35 × 0.08 | 0.70 × 1.35 × 0.08 | 符合 | scripts/isle_house_props.gd · Prop_<kind>_<seq> | curtain 实测 0.698×1.350×0.080 m / 目标 0.700×1.350×0.080 m (误差 0.3%)；真实 Mesh AABB（排除发光/光晕/影子） |
| desk | 1.70 × 0.76 × 0.90 | 1.20 × 0.65 × 0.60 | 1.20 × 0.65 × 0.60 | 符合 | scripts/isle_house_props.gd · Prop_<kind>_<seq> | desk 实测 1.200×0.650×0.600 m / 目标 1.200×0.650×0.600 m (误差 0.0%)；真实 Mesh AABB（排除发光/光晕/影子） |
| dining_table | 1.60 × 0.78 × 0.97 | 1.30 × 0.65 × 0.80 | 1.30 × 0.65 × 0.80 | 符合 | scripts/isle_house_props.gd · Prop_<kind>_<seq> | dining_table 实测 1.300×0.650×0.800 m / 目标 1.300×0.650×0.800 m (误差 0.0%)；真实 Mesh AABB（排除发光/光晕/影子） |
| doormat | 1.40 × 0.03 × 0.85 | 1.00 × 0.02 × 0.60 | 1.00 × 0.02 × 0.60 | 符合 | scripts/isle_house_props.gd · Prop_<kind>_<seq> | doormat 实测 1.000×0.020×0.600 m / 目标 1.000×0.020×0.600 m (误差 0.0%)；真实 Mesh AABB（排除发光/光晕/影子） |
| firewood_basket | 0.60 × 0.49 × 0.44 | 0.52 × 0.44 × 0.38 | 0.52 × 0.44 × 0.38 | 符合 | scripts/isle_house_props.gd · Prop_<kind>_<seq> | firewood_basket 实测 0.520×0.440×0.380 m / 目标 0.520×0.440×0.380 m (误差 0.0%)；真实 Mesh AABB（排除发光/光晕/影子） |
| floor_lamp | 0.38 × 1.50 × 0.40 | 0.36 × 1.45 × 0.36 | 0.35 × 1.45 × 0.37 | 符合 | scripts/isle_house_props.gd · Prop_<kind>_<seq> | floor_lamp 实测 0.354×1.450×0.372 m / 目标 0.360×1.450×0.360 m (误差 3.3%)；真实 Mesh AABB（排除发光/光晕/影子） |
| nightstand | 0.45 × 0.55 × 0.40 | 0.40 × 0.50 × 0.38 | 0.40 × 0.50 × 0.38 | 符合 | scripts/isle_house_props.gd · Prop_<kind>_<seq> | nightstand 实测 0.400×0.500×0.380 m / 目标 0.400×0.500×0.380 m (误差 0.0%)；真实 Mesh AABB（排除发光/光晕/影子） |
| picture_frame | 0.62 × 0.48 × 0.05 | 0.55 × 0.42 × 0.04 | 0.55 × 0.42 × 0.04 | 符合 | scripts/isle_house_props.gd · Prop_<kind>_<seq> | picture_frame 实测 0.550×0.420×0.040 m / 目标 0.550×0.420×0.040 m (误差 0.0%)；真实 Mesh AABB（排除发光/光晕/影子） |
| plant_pot | 0.47 × 0.71 × 0.47 | 0.42 × 0.70 × 0.42 | 0.42 × 0.71 × 0.42 | 符合 | scripts/isle_house_props.gd · Prop_<kind>_<seq> | plant_pot 实测 0.422×0.708×0.421 m / 目标 0.420×0.700×0.420 m (误差 1.2%)；真实 Mesh AABB（排除发光/光晕/影子） |
| reading_chair | 0.80 × 1.19 × 0.77 | 0.70 × 1.05 × 0.72 | 0.70 × 1.05 × 0.72 | 符合 | scripts/isle_house_props.gd · Prop_<kind>_<seq> | reading_chair 实测 0.700×1.048×0.720 m / 目标 0.700×1.050×0.720 m (误差 0.2%)；真实 Mesh AABB（排除发光/光晕/影子） |
| rug | 2.60 × 0.03 × 1.90 | 2.20 × 0.02 × 1.60 | 2.20 × 0.02 × 1.60 | 符合 | scripts/isle_house_props.gd · Prop_<kind>_<seq> | rug 实测 2.200×0.020×1.600 m / 目标 2.200×0.020×1.600 m (误差 0.0%)；真实 Mesh AABB（排除发光/光晕/影子） |
| shoe_bench | 0.90 × 0.47 × 0.35 | 0.80 × 0.42 × 0.32 | 0.80 × 0.42 × 0.32 | 符合 | scripts/isle_house_props.gd · Prop_<kind>_<seq> | shoe_bench 实测 0.800×0.420×0.320 m / 目标 0.800×0.420×0.320 m (误差 0.0%)；真实 Mesh AABB（排除发光/光晕/影子） |
| side_table | 0.43 × 0.55 × 0.45 | 0.40 × 0.50 × 0.40 | 0.39 × 0.50 × 0.41 | 符合 | scripts/isle_house_props.gd · Prop_<kind>_<seq> | side_table 实测 0.390×0.500×0.410 m / 目标 0.400×0.500×0.400 m (误差 2.5%)；真实 Mesh AABB（排除发光/光晕/影子） |
| sideboard | 1.20 × 0.88 × 0.42 | 1.00 × 0.80 × 0.40 | 1.00 × 0.80 × 0.40 | 符合 | scripts/isle_house_props.gd · Prop_<kind>_<seq> | sideboard 实测 1.000×0.800×0.400 m / 目标 1.000×0.800×0.400 m (误差 0.0%)；真实 Mesh AABB（排除发光/光晕/影子） |
| sofa | 1.80 × 0.86 × 0.85 | 1.50 × 0.78 × 0.80 | 1.50 × 0.78 × 0.80 | 符合 | scripts/isle_house_props.gd · Prop_<kind>_<seq> | sofa 实测 1.500×0.777×0.800 m / 目标 1.500×0.780×0.800 m (误差 0.3%)；真实 Mesh AABB（排除发光/光晕/影子） |
| table_lamp | 0.27 × 0.50 × 0.28 | 0.24 × 0.50 × 0.24 | 0.24 × 0.50 × 0.25 | 符合 | scripts/isle_house_props.gd · Prop_<kind>_<seq> | table_lamp 实测 0.236×0.500×0.248 m / 目标 0.240×0.500×0.240 m (误差 3.3%)；真实 Mesh AABB（排除发光/光晕/影子） |
| tall_cupboard | 0.90 × 1.95 × 0.44 | 0.80 × 1.70 × 0.40 | 0.80 × 1.70 × 0.40 | 符合 | scripts/isle_house_props.gd · Prop_<kind>_<seq> | tall_cupboard 实测 0.800×1.700×0.400 m / 目标 0.800×1.700×0.400 m (误差 0.0%)；真实 Mesh AABB（排除发光/光晕/影子） |
| wall_clock | 0.46 × 0.48 × 0.11 | 0.40 × 0.40 × 0.10 | 0.40 × 0.40 × 0.10 | 符合 | scripts/isle_house_props.gd · Prop_<kind>_<seq> | wall_clock 实测 0.400×0.400×0.099 m / 目标 0.400×0.400×0.100 m (误差 1.0%)；真实 Mesh AABB（排除发光/光晕/影子） |
| wardrobe | 1.25 × 1.75 × 0.60 | 1.00 × 1.75 × 0.55 | 1.00 × 1.75 × 0.55 | 符合 | scripts/isle_house_props.gd · Prop_<kind>_<seq> | wardrobe 实测 1.000×1.750×0.550 m / 目标 1.000×1.750×0.550 m (误差 0.0%)；真实 Mesh AABB（排除发光/光晕/影子） |

## 5. 船只 / 码头 / 灯塔 / 路灯 / 树木 / 生物 / 环境

| 对象 | 目标 / 保留理由 |
| --- | --- |
| 小船（Sailboat） | 船体长 3–6 m、宽 1.20–2.00 m（实测 5.011 × 1.620 PASS）。干舷两口径（Lead m00438 放宽至 0.25–0.78）：①**midship** 局部设计水线口径 = 船舯附近舷缘顶 y（本探针实测 **0.535**；T4 报的 0.660 为四分之一/靠后站位，站位定义不同，均落在区间内）；②**max sheer** = 最高舷弧点（实测 0.724，仅 INFO）。世界量法（舷缘世界 Y − 海面 0）：midship 0.819 / max sheer 1.009（随航行摇晃变化，仅登记）。**保留船体与状态机/航线**（boat_behavior）：远景唯一动态叙事道具，可读性优先 |
| 码头（Dock） | 甲板世界高 **0.720 m**（统一口径 = `IsleWorld.DECK_WORLD_Y`，与 T4 施工一致）；宽 3.4 / 长 11.0（实测 3.45 × 11.475）；测量取真实栏杆扶手几何反推（扶手顶 − 0.96 = 甲板顶）。历史 1.907 的来源见 §9 |
| 灯塔（Lighthouse） | 高 18.28 m：**reference_keep 保留**——岛的地标/导航视觉锚点（远海可见、夜景光柱），按真实 1:1 灯塔缩放会丢失取景层级；入口环绕石阶 7 级 × 0.16、径向 0.38、门槛顶 1.20 |
| 路灯（6 盏） | 总高 2.70–3.05 m（实测 2.885、T4 帽顶 2.75）、灯中心 2.45–2.65（实测 2.550）：1.50 m 人物抬头即见光斑，夜景可读性 |
| 大树（BigTree） | 10.35 m：**reference_keep 保留**（取景框 + 秋千挂点 + 树冠层次），不按真实树径缩 |
| 猫（PorchCat） | 坐姿肩/背高 0.25–0.35（实测 0.293）、体长 0.40–0.60（实测 0.512）；真实家猫比例；耳尖高 0.445 仅登记 |
| 海鸥（Bird0..9） | body-only 体长 0.40–0.70（实测 0.671：**保留·远景可读性 + 绘本夸张**，不缩）；翼展 1.10–1.50（实测 1.219 PASS） |
| 岛屿/海面 | 岛径 55–75（实测 60.144，reference_keep 保留地形/岸线/海面）；海面 y=0；昼夜循环保留 |

| 项目 | V3.1 原始实测（基线 wt_baseline） | 目标 / 范围 | 当前主树实测 | 状态 | 对应资产脚本 · 节点 | 依据 / 变更原因与测试结果 |
| --- | --- | --- | --- | --- | --- | --- |
| boat_hull_len | 5.011 m | [3.00 – 6.00] m | 5.011 m | 符合 | world.gd _sailboat · Hull 组（船体 ArrayMesh） | boat_hull_len 实测 5.011 m / 区间 [3.000, 6.000] PASS → PASS；船体局部 z 向 AABB（船长） |
| boat_hull_beam | 1.620 m | [1.20 – 2.00] m | 1.620 m | 符合 | world.gd _sailboat · Hull 组 | boat_hull_beam 实测 1.620 m / 区间 [1.200, 2.000] PASS → PASS；船体局部 x 向 AABB（船宽） |
| boat_freeboard | 0.535 m | [0.25 – 0.78] m | 0.535 m | 符合 | world.gd _sailboat · Gunwale 舷缘（midship 局部设计水线） | boat_freeboard 实测 0.535 m / 区间 [0.250, 0.780] PASS → PASS；midship 局部舷缘顶 y（局部设计水线量法，T4 口径 0.660；max sheer 0.724 另记 RAW） |
| boat_freeboard_max_sheer | 0.724 m | —（保留/仅记录） | 0.724 m | 保留·仅记录 | world.gd _sailboat · Gunwale 最高舷弧点 | boat_freeboard_max_sheer 0.72449469566345（仅登记·不评分）；max sheer 局部舷缘顶（最高舷弧点，仅登记；两口径并列） |
| boat_freeboard_world | 1.008 m | —（保留/仅记录） | 1.008 m | 保留·仅记录 | world.gd _sailboat · 舷缘世界 Y − 海面 0（max sheer） | boat_freeboard_world 1.00818181037903（仅登记·不评分）；世界量法 max sheer：舷缘顶世界 Y − 海面 0 |
| boat_freeboard_midship_world | 0.818 m | —（保留/仅记录） | 0.819 m | 保留·仅记录 | world.gd _sailboat · 舷缘世界 Y − 海面 0（midship） | boat_freeboard_midship_world 0.81868380308151（仅登记·不评分）；世界量法 midship：舷缘顶世界 Y − 海面 0 |
| boat_deck_top | 0.555 m | —（保留/仅记录） | 0.605 m | 保留·仅记录 | world.gd _sailboat · Deck 组 | boat_deck_top 0.60500007867813（仅登记·不评分）；甲板顶局部 y（船局部 y=0 为水面） |
| boat_behavior | 0.000 m | —（保留/仅记录） | 0.000 m | 保留·仅记录 | world.gd Sailboat 状态机（保留） | boat_behavior（保留·不评分）实测 0.000 / hint 0.000，偏差 0.000；航线/回港/夜景状态机保留（未改），仅船体几何审计 |
| dock_deck_world_y | 0.720 m | —（保留/仅记录） | 0.720 m | 保留·仅记录 | world.gd _dock · 栏杆扶手几何反推甲板顶 | dock_deck_world_y 0.72000002861023（仅登记·不评分）；码头甲板世界高（统一口径 = DECK_WORLD_Y 0.720 m；数据来源 railing-geometry）。历史值 1.907 的来源：早期版本直接读 DockP… |
| dock_length | 11.475 m | —（保留/仅记录） | 11.475 m | 保留·仅记录 | world.gd _dock · DOCK_LENGTH 实测 | dock_length 11.4749984741211（仅登记·不评分）；码头局部 z 向长（DOCK_LENGTH 目标 11.0 m） |
| dock_width | 3.450 m | —（保留/仅记录） | 3.450 m | 保留·仅记录 | world.gd _dock · DOCK_WIDTH 实测 | dock_width 3.45000243186951（仅登记·不评分）；码头局部 x 向宽（DOCK_WIDTH 目标 3.4 m） |
| lighthouse_h | 18.276 m | —（保留/仅记录） | 18.276 m | 保留·仅记录 | world.gd _lighthouse · toon 子树 AABB + meta height | lighthouse_h（保留·不评分）实测 18.276 / hint 18.280，偏差 0.004；灯塔是岛屿地标与夜间导航视觉焦点：18.28 m 保证 60 m 外仍可读，灯室/平台/perch/光束已按此高度设计，缩小后与远岛群比例失衡 |
| lighthouse_gallery_y | 13.600 m | —（保留/仅记录） | 13.600 m | 保留·仅记录 | world.gd _lighthouse · GalleryPlatform | lighthouse_gallery_y 13.6000003814697（仅登记·不评分）；观景平台局部 y |
| lighthouse_lamp_y | 14.620 m | —（保留/仅记录） | 14.620 m | 保留·仅记录 | world.gd _lighthouse · Lamp | lighthouse_lamp_y 14.6199998855591（仅登记·不评分）；灯室旋转灯局部 y |
| lighthouse_steps_count | 0 级 | [6.90 – 7.10] 级 | 7 级 | 符合 | world.gd _lighthouse · DoorStep0..6 | lighthouse_steps_count 实测 7.000 step / 区间 [6.900, 7.100] PASS → PASS；Lighthouse/DoorStep* 节点数 |
| lighthouse_step_rise | —（基线无此项） | [0.15 – 0.17] m | 0.160 m | 符合 | DoorStep 顶面高差 | lighthouse_step_rise 实测 0.160 m / 区间 [0.150, 0.170] PASS → PASS；石阶踏高（顶面高差中位数） |
| lighthouse_step_depth | —（基线无此项） | [0.34 – 0.42] m | 0.380 m | 符合 | DoorStep BoxMesh 径向 | lighthouse_step_depth 实测 0.380 m / 区间 [0.340, 0.420] PASS → PASS；石阶径向踏面深（BoxMesh 局部 z） |
| lighthouse_step_top | —（基线无此项） | [1.10 – 1.14] m | 1.120 m | 符合 | DoorStep0 顶面 | lighthouse_step_top 实测 1.120 m / 区间 [1.100, 1.140] PASS → PASS；最高一级石阶顶局部 y |
| street_lamp_h | 2.350 m | [2.70 – 3.05] m | 2.885 m | 符合 | world.gd _street_lamps/_lamp · PathLamp1-3/GardenLamp1-3 | street_lamp_h 实测 2.885 m / 区间 [2.700, 3.050] PASS → PASS；6 盏路灯总高（基座底→杆/灯帽顶）中位数；节点 PathLamp1,PathLamp2,PathLamp3,GardenLamp1,Garden… |
| street_lamp_center | 1.980 m | [2.45 – 2.65] m | 2.550 m | 符合 | world.gd _lamp · self_lit 灯箱中心 | street_lamp_center 实测 2.550 m / 区间 [2.450, 2.650] PASS → PASS；灯具/光心离地中位数（自发光灯箱网格中心） |
| big_tree_h | 10.353 m | —（保留/仅记录） | 10.353 m | 保留·仅记录 | world.gd _big_tree · BigTree AABB | big_tree_h（保留·不评分）实测 10.353 / hint 12.000，偏差 1.647；大树是取景框/秋千挂点，保留树高 |
| cat_shoulder_h | 0.503 m | [0.25 – 0.35] m | 0.295 m | 符合 | scripts/isle_cat.gd PorchCat · Body 组 AABB | cat_shoulder_h 实测 0.295 m / 区间 [0.250, 0.350] PASS → PASS；PorchCat Body 组 AABB 顶（坐姿肩/背高；T4 修后 0.297） |
| cat_body_len | 0.853 m | [0.40 – 0.60] m | 0.512 m | 符合 | PorchCat · Body+Head AABB 深 | cat_body_len 实测 0.512 m / 区间 [0.400, 0.600] PASS → PASS；Body+Head 合并 AABB 深（体长，不含尾） |
| gull_body_len | 0.672 m | [0.40 – 0.70] m | 0.672 m | 符合 | scripts/fx.gd BirdFlock · Bird0 躯干+头+喙+尾 | gull_body_len 实测 0.672 m / 区间 [0.400, 0.700] PASS → PASS；海鸥躯干+头+喙+尾网格合并 AABB 深（不含翼/腿） |
| gull_wingspan | 1.219 m | [1.10 – 1.50] m | 1.219 m | 符合 | fx.gd Bird0 · 翼节点旋转归零后 x 跨度 | gull_wingspan 实测 1.219 m / 区间 [1.100, 1.500] PASS → PASS；双翼旋转归零后翼网格 x 向跨度（设计翼展） |
| island_diameter | 60.144 m | —（保留/仅记录） | 60.144 m | 保留·仅记录 | world.gd IsleWorld.island_diameter / coast_radius | island_diameter（保留·不评分）实测 60.144 / hint 63.600，偏差 3.456；世界岛径（world.island_diameter）；Terrain 网格 AABB 含水下裙边 = 90.524×16.941×86.053 |
| sea_surface_y | 0.000 m | —（保留/仅记录） | 0.000 m | 保留·仅记录 | main.gd _build_sea · Sea 节点 y=0 | sea_surface_y（保留·不评分）实测 0.000 / hint 0.000，偏差 0.000；海面 y=0 是干舷/码头/船只吃水共同基准 |
| day_night_cycle | 0.000 m | —（保留/仅记录） | 0.000 m | 保留·仅记录 | main.gd 昼夜循环（保留） | day_night_cycle（保留·不评分）实测 0.000 / hint 0.000，偏差 0.000；日月球/光照比例保留；本轮只审计相机与灯光距离：none |
| windmill_old | 12.184 m | —（保留/仅记录） | 12.184 m | 保留·仅记录 | world.gd _windmill 旧风车基准（保留） | windmill_old（保留·不评分）实测 12.184 / hint 12.190，偏差 0.006；旧风车已由灯塔替换，仅历史记录（world.gd windmill_old_height） |

## 6. 相机与灯光

- 相机：`Camera3D fov=42° / near=0.3 / far=2200`；初始轨道半径 `main._radius=82`（`IsleMath.CAM_START_R`）；自由视角 `IsleFlyCam radius=130 / max_y=130`、速度 12.48 / 24.96 m/s、垂直 6.6 m/s。
- 灯光：路灯 Light3D range 7.5 / intensity 1.35；灯塔灯 range 17.0 / intensity 1.65；窗口 halo 由 main 夜间调制。
- fov 42° 为既有设计（main.gd:69 `_fov:=42`，菜单可调档），spec 区间按 Lead m00438 定为 **[32,75]**，**不得为过审计改相机**。

| 项目 | V3.1 原始实测（基线 wt_baseline） | 目标 / 范围 | 当前主树实测 | 状态 | 对应资产脚本 · 节点 | 依据 / 变更原因与测试结果 |
| --- | --- | --- | --- | --- | --- | --- |
| camera_fov | 42.0 ° | [32.00 – 75.00] ° | 42.0 ° | 符合 | main.gd _build_camera · Camera3D.fov | camera_fov 实测 42.000 deg / 区间 [32.000, 75.000] PASS → PASS；Camera3D.fov |
| camera_near | 0.300 m | [0.10 – 0.50] m | 0.300 m | 符合 | main.gd _build_camera · Camera3D.near | camera_near 实测 0.300 m / 区间 [0.100, 0.500] PASS → PASS；Camera3D.near（far=2200.0） |
| camera_orbit_r | 82.000 m | [70.00 – 95.00] m | 82.000 m | 符合 | main.gd _build_camera · _radius=IsleMath.CAM_START_R | camera_orbit_r 实测 82.000 m / 区间 [70.000, 95.000] PASS → PASS；main._radius 初始轨道半径 |
| camera_distance_now | 82.000 m | —（保留/仅记录） | 82.000 m | 保留·仅记录 | main.gd 当前相机位置 ↔ _cam_target | camera_distance_now 82.0（仅登记·不评分）；当前相机帧到 _cam_target 实测距离 |
| camera_fly_radius | 130.000 m | [110.00 – 150.00] m | 130.000 m | 符合 | scripts/isle_flycam.gd radius/max_y | camera_fly_radius 实测 130.000 m / 区间 [110.000, 150.000] PASS → PASS；IsleFlyCam.radius 自由视角半径 |

## 7. reference_keep（明确保留的夸张比例及理由）

| 对象 | 现状值 | 资产/节点 | 保留理由 | 保留条件 |
| --- | --- | --- | --- | --- |
| 灯塔 | 18.28 m | `Island/Lighthouse` | 地标与夜景光柱锚点；远景层级与取景构图 | 高度不缩；入口石阶层数与门槛高按人体尺度校准（实测 7 级 × 0.16、顶 1.12） |
| 岛屿地形/岸线/海面 | 岛径 60.144 m；海面 y=0 | `Island/Terrain`、`Sea` | 整岛布局、草密度、远景岛群与航线按现尺寸调优 | 地形尺度不动；仅建筑落位与人体比例对齐 |
| 大树 | 10.35 m | `Island/BigTree` | 取景框、秋千挂点、树冠穿光层次 | 树高不缩；树下道具按人体尺度 |
| 旧风车基准 | 12.19 m | `world.gd _windmill` 系列 | 远景剪影与既有轮廓锚点 | 轮廓不变 |
| 小船行为 | 船体 5.0×1.62 m | `Island/Sailboat` | 动态叙事道具；已有航线/靠岸/摇晃状态机 | 船体不缩；干舷/靠岸高度对齐口径（midship 0.535 / max sheer 0.724 / 甲板 0.72） |
| 昼夜循环 | — | `main.gd` | 光照基调与夜景可读性 | 不改循环参数 |

## 8. 容差与判定规则

| 规则 | 取值 | 适用 |
| --- | --- | --- |
| 尺寸相对容差 | `TOL = 0.05`（5%） | 家具/窗/门等三维尺寸 `check()` |
| 警告容差 | `WARN_TOL = 0.10`（10%） | 超 5% 记 WARN、超 10% 记 FAIL |
| 绝对容差 | `TOL_ABS = 0.010 m` | 人体总高 1.500±0.010、脚底 y=0 |
| 区间项 | 区间内 PASS；超区间但 ≤ 区间宽 10% 记 WARN；再外 FAIL | 相机距离/路灯/猫鸥/船只/石阶/保留参考项 |
| 保留项 | 只登记 `INFO`（保留·不评分） | reference_keep：灯塔/岛径/海面/大树/昼夜/旧风车/小船行为 |
| 失败退出 | audit 有 FAIL → 退出码 1；inventory 恒 0 | 回归/CI |

## 9. 已知测量口径与历史问题（防回归）

1. **dock 甲板世界高 1.907 m 的历史错误**：早期探针直接读 `DockPlanks` MultiMesh AABB。headless 的 dummy 渲染器读不到 MultiMesh 实例变换（`get_instance_transform()` 全 identity），于是把局部 BoxMesh 的 ±0.05 半高当甲板顶（+0.05），再叠加码头节点世界 Y 1.857（岸边地形高），得到 1.907。**现口径**：读真实栏杆扶手几何反推，甲板世界高 = 扶手顶 − 0.96 = **0.720 m**（与 T4 施工一致）。
2. **烟囱标记节点 ≠ 几何顶**：`ChimneyTop` 标记在 `ch_top+0.05=6.25`，真实石块顶 6.55。读标记会把"烟囱高出屋脊"测成 −0.134（m00438 的 FAIL 根因）。**现口径**：读 root `batch_manifest` 烟囱平面附近部件 AABB 顶。
3. **屋脊几何含脊瓦**：真实 AABB 顶 6.384 vs 结构线 6.20（+0.184）。判定统一用结构线；几何值只作 RAW。
4. **MultiMesh 陷阱**：headless 下所有 MultiMesh（InteriorFloor/AtticFloor/DockPlanks/草地）实例变换不可读 → 楼板/天花改读 `batch_manifest` 结构大板；任何 AABB 异常先确认是否来自 MultiMesh。
5. **坡度**：法线平均会被屋脊盖瓦/装饰斜件污染（V3.1 38.3°、主树 38.5°）→ 用几何法。
6. **膝墙高**：按檐口结构线 `roof_base − attic_floor`；内推屋檐下皮会 +0.24 m。
7. **门洞**：T2 新 cottage 的 `root meta door_clear` 为权威净尺寸；射线仅交叉验证（门套内凹少 ~0.08 m）。
8. **舷弧（sheer）**：舷缘沿船长是曲线，"干舷"必须标明站位——midship 与 max sheer 差可达 0.19 m（本船 0.535 vs 0.724）。探针两口径都输出，判定用 midship。
9. **家具尺寸朝向**：AABB 按 x=宽 / y=高 / z=深 归一化比较。
10. **合并网格**：房屋/楼梯/家具被 `IsleBatch.merge_static` 合并后原 MeshInstance 被释放，测量走 `batch_manifest`（部件级 size+xf）；未合并子树（门扇/玻璃/猫/鸟/船/灯）直接读真实 MeshInstance。

## 10. 变更原因与测试结果（本轮 T1 交付）

| 交付 | 文件 | 测试结果 |
| --- | --- | --- |
| 尺度规范注册表 | `scripts/isle_scale_spec.gd` | 新增资产区间/reference_keep/measurement_of/灯塔石阶/猫海鸥区间；fov 区间 [32,75]（默认 42）、boat_freeboard [0.25,0.78]；check/check_range/check_custom 自测通过 |
| 1.50 m 人形参照 | `scripts/isle_scale_figure.gd` | 世界 AABB 1.500 m、脚底局部 y=0、12 MeshInstance、父节点 scale=2 自检测得 3.000 m（抓整节点缩放漂移） |
| 世界实测探针 | `tools/probe_scale_world.gd` | headless 可重复；audit 当前树 `[SCALE] RESULT pass=90 warn=0 fail=0 info=17 mode=audit tag=scale_audit_main`；基线 `info=102`；产物 `inventory*.json/md` |
| 开发标尺 overlay | `tools/scale_debug_overlay.gd` | 语法通过；CLI `--scale-debug` 才构建、构建一次合批、无 `_process`；API 见 §11 |
| 基线原始尺寸 | `开发产物/p7v32/scale/inventory_baseline.{json,md}` | wt_baseline（eaf1559）真实运行，102 项原始实测 |
| 本文档 | `docs/WORLD_SCALE_SPEC.md` | 表格数据由探针 JSON 直接生成，非手工 |

## 11. 开发模式标尺（`tools/scale_debug_overlay.gd`）

- 启用：启动参数 `--scale-debug`（用户参数，任意位置）；可选 `--scale-debug-x <x> --scale-debug-z <z>` 指定落点（默认 Cottage 门前 +Z 方向 `D/2+1.9`）。
- 默认不显示：不传参时 `enabled()==false`，main 不实例化任何节点、零常驻开销。
- 内容：1 m 参照立方棱线；1.50 m 参照人形；垂直标尺 0–3.2 m（1 m/0.5 m/0.1 m 刻度 + 数字）；2 m 水平标尺；原点/XYZ 三轴辅助线；房屋层高/门洞/地面/阁楼/楼梯标注；小船/码头/灯塔/路灯/大树/猫/海鸥长宽高 Label3D。
- 构建一次后 `IsleBatch.merge_static()` 合批，无每帧重建；标签 Label3D billboard + no_depth_test，不参与光照。
- main.gd 集成（T4，3–5 行）：
```gdscript
const ScaleOverlay := preload("res://tools/scale_debug_overlay.gd")
if ScaleOverlay.enabled():
    var ov := ScaleOverlay.new()
    ov.name = "ScaleDebugOverlay"
    add_child(ov)
```
- **运行时自检（headless，无需窗口/GUI）**：`tools/probe_scale_world.gd --mode overlay --tag scale_overlay_selftest`
  真实实例化标尺并断言 11 项：不传参 `enabled()==false`、`is_built()==true`、合批后子树仅 1 个 `Batch_*` MeshInstance + 29 个 `Label3D`、1.50 m 人形高度（由合批 `batch_manifest` 的 `Ref_*` 部件反推 = 1.500 m）、脚底贴地、`rebuild()` 不重复叠加、隐藏开关只切显示、脚本无 `_process/_physics_process`、`free()` 后无残留。
  实测：`[SCALE] RESULT pass=11 warn=0 fail=0 info=0 mode=overlay tag=scale_overlay_selftest`（exit 0；日志 `开发产物/p7v32/logs/scale_overlay_selftest.log`）。

## 12. 复现与产物路径

| 产物 | 路径 |
| --- | --- |
| 当前树审计 JSON/MD | `开发产物/p7v32/scale/inventory.json`、`inventory.md` |
| 基线原始 JSON/MD | `开发产物/p7v32/scale/inventory_baseline.json`、`inventory_baseline.md` |
| 日志 | `开发产物/p7v32/logs/scale_audit_main.log`、`scale_inventory_baseline.log` |
| 规范注册表 | `scripts/isle_scale_spec.gd` |
| 参照人形 | `scripts/isle_scale_figure.gd` |
| 探针 | `tools/probe_scale_world.gd`（`--mode audit|inventory|overlay --tag <tag>`） |
| 标尺 | `tools/scale_debug_overlay.gd`（自检日志 `开发产物/p7v32/logs/scale_overlay_selftest.log`） |
| 表格更新器 | `开发产物/p7v32/scale/update_spec_tables.mjs`（`node update_spec_tables.mjs [--write]`，从 inventory*.json 重建表格 2–5/7 列，保留正文与「对应资产脚本·节点」列；幂等，当前 dry-run changed=0） |
