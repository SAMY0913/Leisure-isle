# P6 T1 生命周期排查报告（ObjectDB / RID 退出告警与运行期 orphan）

- 负责人：teammate lifecycle；范围：退出阶段 ObjectDB/RID 泄漏、运行期 orphan 节点、音频资源/总线名生命周期、导出 exe 退出码异常
- 环境：Windows 10（2560x1440 / RTX 2060），Godot 4.7.2.stable.official.ed1daf0bf（Forward+），主场景 res://isle.tscn
- 引擎：D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe；工程：D:/休闲小岛幻境/游戏工程
- 日志与复现材料：D:/休闲小岛幻境/开发产物/logs/lifecycle/（下文日志名均相对该目录）
- 本报告全部数字来自本次实测；历史日志只用于对照，已单独标注。

## 0. 结论摘要

1) 应用侧真实根因 1 个，已修复：fx.gd 的 Splash / Ripples 对象池把退役单元 remove_child() 后只放进 _free 数组，场景树退出/池节点销毁时没有任何钩子释放这些已脱离场景树的节点子树 -> 退出阶段 ObjectDB / RID / PagedAllocator 泄漏，运行期计入 Performance.OBJECT_ORPHAN_NODE_COUNT。修复后 --selftest 的 50 ObjectDB + 全部 Dummy RID + PagedAllocator 报错归零，探针中池销毁后 orphan 由 11 降为 0。
2) 引擎/后端本底 2 类，不修（附证据）：
   - headless Dummy 音频驱动的退出竞态：每次泄漏固定为 8 个对象（4xAudioStreamWAV + 4xAudioStreamPlaybackWAV，refcount 1）+ Orphan StringName IsleFire / IsleAmbient，非确定性（复现率约 1/2~5/8）；在 isle_audio 中加了停播放器+清 stream+删 4 条命名总线的退出清理并验证 _exit_tree 确实执行后，泄漏与 StringName 仍原样出现、频率无变化 -> 判定为 AudioServer/Dummy 驱动 shutdown 竞态，应用侧无法消除，已回滚该试验 patch（不留未验证代码）。
   - user:// 不可写导致 shader cache 保存失败：_save_to_cache ... Condition f.is_null() ERROR，属环境本底（沙箱禁止 user:// 写入），与泄漏无关。
3) 未解决、独立问题：导出的 release exe 在 --selftest / --perf 退出阶段 0xC0000374（heap corruption）；旧发布 exe（P6 前）同样复现 -> 非 P6 引入，且与上述 ObjectDB 泄漏不同源（plain --quit 同样有 8 音频泄漏但退出码 0）。已给出复现矩阵与采样方法，需单独 triage。

## 1. 复现矩阵（before；本机实测）

| # | 场景 / 命令 | 观察结果 | 日志 |
|---|---|---|---|
| a | 最小对照工程 headless 60 帧（空 Node3D） | 无任何 RID/ObjectDB 退出告警 | 01_min_bare_headless_verbose_20261020_2315.log |
| a2 | 最小对照工程 headless 60 帧（MeshInstance3D+StandardMaterial3D+QuadMesh+MultiMesh） | 无任何退出告警 | 02b_min_render_headless_verbose_20261020_2318.log |
| b | 游戏工程 smoke_test.tscn headless 60 帧 | 无任何退出告警 | 03_smoke_headless_quit60_verbose_20261020_2320.log |
| c | isle.tscn headless 菜单态 2s / 6s / 12s / 20s（--fixed-fps 60 --quit-after 120/360/720/1200） | 无 RID/ObjectDB 告警；6s 偶发 8 音频对象泄漏（见 4.3） | 04_2560...、05_2560...、06_2560...、13_2560(20s) |
| d | isle.tscn headless -- --selftest | 15 DummyMaterial / 3 DummyShader / 6 DummyMultiMesh / 4 DummyMesh / 1 DummyTexture / 20 RendererSceneCull Instance RID + PagedAllocator GeometryInstanceDummy pages in use + 3 Leaked instance dependency + 50 ObjectDB leaked + 15 unclaimed string names | 11_selftest_headless_verbose_20261020_2340.log |
| e | isle.tscn 窗口模式 1600x900 6s（真实渲染器） | 无 RID/ObjectDB/PagedAllocator 告警；仅 _save_to_cache f.is_null() ERROR（user:// 不可写） | 12_isle_windowed_1600x900_6s_verbose_20261020_2342.log |
| e2 | 最小对照工程窗口 1280x720 2s | 无任何退出告警 | 10_min_windowed_720p_2s_verbose_20261020_2337.log |
| f | 导出 release exe（试导出 116,767,872B，嵌入 pck）headless -- --selftest | 打印 [TEST] RESULT 53/53 passed 后退出阶段崩溃 EXIT=-1073740940 (0xC0000374)，22.4s | 35_export_trial2_selftest_headless_r3.out/.err/.godot.log |
| f2 | 旧发布 exe（122,950,336B，P6 前）headless -- --selftest | [TEST] RESULT 44/46 passed 后同样 EXIT=-1073740940 (0xC0000374)，19.2s | 38_export_old_selftest_headless.* |
| f3 | 导出 exe headless -- --perf | [PERF] after_6s objects=24 orphan=0.0、[PERF] end 后同样 EXIT=-1073740940，45.7s | 40_export_trial2_perf_headless.* |
| f4 | 导出/旧发布 exe headless --quit-after 120/360/600（菜单态） | EXIT=0；stderr 有 8 ObjectDB leaked 警告（1 次 31s 长跑无警告） | 36/37/42/43、39 各 .out/.err.log |

复现命令（headless 探针/矩阵）：

    ENG="D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe"
    PROJ="D:/休闲小岛幻境/游戏工程"
    # 场景矩阵（--verbose 必须在 -- 之前才生效）
    "$ENG" --headless --path "$PROJ" --verbose --quit-after 360
    # selftest
    "$ENG" --headless --path "$PROJ" --verbose -- --selftest
    # T1 诊断探针（FX 池 / 音频）
    "$ENG" --headless --path "$PROJ" --verbose --script res://tools/probe_exit_diag_t7.gd
    "$ENG" --headless --path "$PROJ" --verbose --script res://tools/probe_exit_diag_t7.gd -- --audio-probe

导出 exe 退出码采样（GUI 子系统 exe，PowerShell & 与 bash 拿不到真实退出码；必须 Start-Process -Wait）：

    $p = Start-Process -FilePath '<exe>' -ArgumentList @('--headless','--','--selftest') -WorkingDirectory '<exe目录>' -Wait -PassThru -RedirectStandardOutput out.log -RedirectStandardError err.log
    $code = $p.ExitCode
    $u = [BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$code),0)   # -1073740940 -> 0xC0000374

## 2. 告警分类表

| 类别 | 告警（before） | 判定 | 出现条件 | 窗口模式 | 最小工程 |
|---|---|---|---|---|---|
| A. FX 池游离单元（应用真实泄漏） | 50 ObjectDB（14xMeshInstance3D、14xStandardMaterial3D、6xCPUParticles3D、6xCylinderMesh、6xSphereMesh、6xArrayMesh、6xGradient、2xGradientTexture2D、2xPlaneMesh、2xNode3D 等，Node path 均为空=树外）、15 DummyMaterial、3 DummyShader、6 DummyMultiMesh、4 DummyMesh、1 DummyTexture、20 RendererSceneCull Instance RID、PagedAllocator GeometryInstanceDummy pages in use | 真实泄漏，已修复 | 仅当 Splash/Ripples 产生过退役单元（selftest / --perf / --shots / 实际游玩） | 同样发生（窗口 selftest 修复前亦可复现） | 否 |
| B. 由 A 牵连的引擎诊断 | 上述 Dummy* RID / RendererSceneCull Instance RID / PagedAllocator / Leaked instance dependency | A 的伴生诊断：headless Dummy 后端为未释放的节点/资源登记了 RID，A 修复后全部消失 | 同 A | - | - |
| C. headless 音频退出竞态（引擎） | 8 ObjectDB（4xAudioStreamWAV + 4xAudioStreamPlaybackWAV，refcount 1）+ Orphan StringName IsleFire、IsleAmbient + 2 unclaimed string names | 引擎侧真实泄漏，应用侧清理无效（证据见 4.3） | 需有活跃 AudioStreamPlayback 时退出；非确定性，6s 菜单态约 3/6~5/8 次 | 未观察到 | 是（无音频 -> 无此告警） |
| D. shader cache 环境噪音 | _save_to_cache ... Condition f.is_null() ERROR | 环境本底：user:// 不可写 | 窗口模式必现 | 是 | 窗口模式有 |
| E. 导出 release exe 退出崩溃 | EXIT=0xC0000374（heap corruption），无 ObjectDB 泄漏行 | 未解决、独立问题（见 5） | 仅导出 exe；--selftest/--perf 等实际运行后退出 | - | - |

## 3. 应用侧根因与修复（fx.gd）

### 3.1 根因
- Splash（class Splash extends Node3D，约 L843-1090）：_finish() 退役单元时执行 root.visible=false + if root.get_parent()==self: remove_child(root) + _free.append(unit)（约 L1043-1057）-> 单元（1xNode3D + 6xMeshInstance3D + 3xCPUParticles3D）变成树外 orphan，只被池的 _free 数组引用；池节点随场景树退出被释放时不会触及这些游离子树。
- Ripples（约 L1240-1417）：update() 中涟漪寿命结束后 mi.visible=false; remove_child(mi); _free.append(it) -> 同样树外 orphan MeshInstance3D。
- 数量映射与 selftest 的泄漏签名完全吻合（14 MeshInstance3D=2 单元x6 ring/column、6 CPUParticles3D=2 单元x3、14 StandardMaterial3D=12+2、20 Instance RID=14 mesh+6 particles、6 DummyMultiMesh=CPUParticles 的 MultiMesh 等）。

### 3.2 修复（scripts/fx.gd，+46 行）
- Splash 新增（L873-896）：_exit_tree() -> _release_detached()；_notification(what) 在 NOTIFICATION_PREDELETE 时同样调用；_release_detached() 遍历 _free，用 Variant 接收 + is_instance_valid() 防已释放实例，remove_child（仅在仍为子节点时）+ free()，最后 _free.clear()。
- Ripples 新增（L1286-1305）：同样三函数，遍历 _free 取每项 node 释放并清空。
- 设计约束（必须保留）：tools/probe_fx_p4.gd:144/152/161/213 与 main.gd selftest L2003-2033 断言 get_child_count()==活跃单元数，因此不能改成保留隐藏子节点；修复只在池退出/销毁时释放游离单元，运行期语义不变。
- 幂等 + 双钩子：_exit_tree 与 NOTIFICATION_PREDELETE 二选一触发即可，重复调用安全。第一版直接用 var root: Node3D = unit.get("root") 在对象已 freed 时会报 Trying to assign invalid previously freed instance.（probe_fx_p4 手动清理路径），已改为 Variant+is_instance_valid，修复后该回归脚本 SCRIPT ERROR=0。

## 4. before/after 对比（同一命令、同一机器）

### 4.1 探针（tools/probe_exit_diag_t7.gd）

| 指标 | before（14_probe_exit_diag_before_20261021_0010.log） | after（15_probe_exit_diag_after_20261021_0014.log、23_probe_exit_diag_after_harden_20261021_0050.log） |
|---|---|---|
| 1 个 splash unit + 1 个 ripple 退役后 orphan 增量 | 11 | 11（设计内：池化复用单元仍在 _free） |
| 池节点 free（模拟场景树退出）后 orphan 相对基线增量 | 11（泄漏） | 0 |
| 引擎退出阶段 ObjectDB/RID/PagedAllocator 泄漏行 | 8 DummyMaterial / 3 DummyShader / 3 DummyMultiMesh / 4 DummyMesh / 1 DummyTexture / 10 Instance RID / 13 unclaimed string names / 29 ObjectDB leaked | 0 |

### 4.2 headless --selftest（53/53 断言不变）

| 指标 | before（11_selftest_headless_verbose_20261020_2340.log） | after（16_selftest_headless_after_run1/2/3_20261021_0016.log） |
|---|---|---|
| 断言 | 53/53（本次 before 泄漏但测试仍 53/53） | run1/run2/run3 均 53/53 |
| 泄漏行 | 50 ObjectDB + 15 DummyMaterial / 3 DummyShader / 6 DummyMultiMesh / 4 DummyMesh / 1 DummyTexture / 20 Instance RID + PagedAllocator | run1: 0；run3: 0；run2: 仅 C 类音频 8 对象（4+4，headless 竞态） |

### 4.3 音频 8 对象泄漏（C 类，未消除，已证实应用侧清理无效）
- before（29_audio_isle6s_before_run1..6_233742..233846）：6 次 6s headless 菜单态运行中 3 次命中，每次固定 8 对象（4xAudioStreamWAV + 4xAudioStreamPlaybackWAV，refcount 1，instance id 三次运行完全相同）+ 2xOrphan StringName（IsleFire/IsleAmbient）+ 2 unclaimed string names（25_..._0054 同签名）。
- 试验修复：isle_audio.gd _exit_tree 增 _shutdown_audio()：停全部播放器（loops/sfx/birds/fire）-> stream=null -> 清缓存 -> 移除 4 条命名总线的效果与总线。用既有 --audio-log 验证 _exit_tree 确实执行（D:/休闲小岛幻境/开发产物/logs/audio_main_run.log mtime 由 19:34 更新到 23:41）。
- after（30_audio_isle6s_after_run1..8_233912..234037）：8 次中 5 次命中，仍是完全相同的 8 对象 + 2 StringName，频率无改善（3/6 -> 5/8，统计上无差异）-> 应用侧清理无法消除，判为 AudioServer/Dummy 驱动 shutdown 竞态；已回滚该 patch（scripts/isle_audio.gd 当前无 diff）。
- 影响面：仅退出日志 warning，不影响 source 工程退出码（0）、不影响窗口模式；最小对照工程（无音频）无此告警。

### 4.4 回归检查
- tools/probe_fx_p4.gd（既有 FX 探针）：修复后 PROBE RESULT: FAIL pass=64 fail=1，失败项 个体 8-20s 计时器错峰切换（多次起飞/降落），[BIRDS] 30s takeoffs=1 landings=1（断言要求 >=4）。为排除本次修改影响，在隔离工程 开发产物/lifecycle_fxbase_proj/ 用 git show HEAD:scripts/fx.gd（baseline commit 8f80b13）跑同一探针：同样 FAIL、同样 [BIRDS] 数字（19_probe_fx_p4_baseline_fxgd_20261021_0030.log）-> 该失败在基线 fx.gd 上就存在，属既有行为回归（鸟群起飞/降落节奏调参），非本次生命周期修复引入；是否修复需按玩法口径由 Lead 决策。

## 5. 导出 exe 退出码 0xC0000374（未解决、独立问题）

见 1 表 f/f2/f3/f4。要点：
- 崩溃总在应用逻辑结束后（[TEST] RESULT / [PERF] end 已输出）的进程 shutdown 阶段，stderr 没有 ObjectDB 泄漏报告行（清理报告前就崩）。
- 新旧导出 exe 都是 0xC0000374；旧发布版是 P6 前构建 -> 非本次修改引入。
- plain --quit / 菜单态长跑 10s、31s 退出码 0（其中 plain 运行同样有 8 音频泄漏）-> 与 C 类泄漏不同源，不能靠修 FX/音频泄漏消除。
- 源码工程（editor/debug 构建）headless selftest 多次运行均退出 0（16_... 三连跑）-> 只出现在 release 导出包。
- 初步判断：release 构建在 selftest/perf 这类大量创建/释放后主动 quit 路径上的 shutdown 堆损坏（可能与嵌入式 pck + 音频线程/资源释放时序有关），需 WER LocalDumps + release 符号单独 triage；建议 FREEZE 后用最终代码重新导出复测：若仍 0xC0000374，作为已知问题记录，不应阻塞 P6 交付。

## 6. 修改文件与行号

| 文件 | 改动 |
|---|---|
| 游戏工程/scripts/fx.gd | +46 行：Splash L873-896、Ripples L1286-1305 新增 _exit_tree / _notification / _release_detached |
| 游戏工程/tools/probe_exit_diag_t7.gd | 新建诊断探针：默认 FX 池退出泄漏；-- --audio-probe 音频 8 对象/总线 StringName 复现，--audio-cleanup 清理对照组 |
| 游戏工程/docs/P6_LIFECYCLE_FINDINGS.md | 本报告 |
| 开发产物/logs/lifecycle/*.log、*.ps1 | 全部复现日志与导出 exe 采样脚本（不在 git 仓库内） |

scripts/isle_audio.gd 试验 patch 已回滚，无 diff。scripts/main.gd 本报告范围内未修改（Lead 独占）。

## 7. 未解决项 / 风险

| 项 | 状态 | 建议 |
|---|---|---|
| 导出 release exe selftest/perf 退出 0xC0000374 | 未解决，独立问题 | FREEZE 后最终导出复测；需 WER dump+符号单独 triage；不阻塞 P6 功能与断言 |
| headless Dummy 音频退出竞态 8 对象 + 2 StringName | 引擎侧，应用清理无效 | 保留本报告证据；若必须零警告，只能等引擎修复或在 headless 测试中接受（不影响退出码） |
| probe_fx_p4 鸟群起飞/降落既有失败 | 既有回归（baseline 复现） | 由 Lead/玩法负责人决定是否修 |
| user:// 不可写导致 shader cache ERROR | 环境本底 | 测试沙箱内接受，不作为泄漏处理 |
