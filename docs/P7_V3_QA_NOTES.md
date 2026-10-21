# P7-V3 QA 验收备注（工具用法与结论索引）

本文件供后续复跑/复核使用，详细结论见 `开发产物/p7v3/REGRESSION_P7V3.md`。

## 截图 harness 用法（Lead/其他成员可复用）

```
ENG="D:/休闲小岛幻境/引擎/Godot_v4.7.2-stable_win64_console.exe"
PROJ="D:/休闲小岛幻境/游戏工程"
# 全场景机位批量截图（窗口，需 GPU 串行锁）
"$ENG" --path "$PROJ" --resolution 1600x900 --script res://tools/probe_frame_p7v3.gd -- --stage=all
# 指定分组 / 自定义输出目录 / 指定 FOV
"$ENG" --path "$PROJ" --resolution 1600x900 --script res://tools/probe_frame_p7v3.gd -- --stage=door,porch,interior --out=D:/休闲小岛幻境/开发产物/p7v3/shots/custom --fov=55
```

- 默认输出：`D:/休闲小岛幻境/开发产物/p7v3/shots/frame/`，每张图在 MANIFEST.md 有说明；日志标记 `[P7V3F]`。
- 门廊画质/亮度对比：`... --script res://tools/probe_porch_quality_p7v3.gd` → `shots/porchq/`（q2/q4 × 白天/黄昏/夜景 + 左右灯近景，MANIFEST 内含平均亮度）。
- 结构断言：`"$ENG" --headless --path "$PROJ" --script res://tools/probe_verify_p7v3.gd`，通过标准 `[VERIFY] RESULT ... fail=0` 且 exit 0。
- FOV 真实落盘/重启恢复：先 `export APPDATA=D:/休闲小岛幻境/开发产物/p7v3/userdir`，再按 `开发产物/p7v3/logs/run_fov_e2e.sh` 跑 cold/check58/check42，结束后删除 userdir（脚本已做）。

## 冻结版本关键结论

- headless：selftest 53/53、verify 177/0（warn 3 已闭环）、其余 8 个探针全过；FOV e2e 23 断言全过。
- 官方窗口：--shots 61 张、--transition 13 张、--perf EXIT=0；专项截图 door 11/house 34/cam 9/boat 11/cat 4+11/props 10/frame 39+fov 27/porchq 10。
- 视觉：门/门廊灯/室内四角/二层/楼梯/小船/猫咪/FOV/过渡关键项通过；备注见 REGRESSION §6.1。
- 性能：默认画质 CPU-bound 机位 -28%~-40%、draw_calls 约 +100%，未过 §14 ±10% 门限，待 Lead 决策（REGRESSION §7）。
- 门廊亮度：q4 夜间 ≥ q2（+5~7%），V3 vs V2 同机位 04_night_lights ROI +1.4%，无回退。
