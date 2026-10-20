extends SceneTree
## Lead-owned settings schema probe (Phase 6).
const S = preload("res://scripts/isle_settings.gd")

func _ok(tag: String, cond: bool, detail: String = "") -> void:
	print(("[PASS] " if cond else "[FAIL] ") + tag + (" " + detail if detail != "" else ""))
	if not cond:
		_fail += 1

var _fail := 0

func _init() -> void:
	print("[SET] quality_count=", S.QUALITY_COUNT, " labels=", S.QUALITY_LABELS)
	_ok("quality_count_5", S.QUALITY_COUNT == 5)
	_ok("quality_labels_5", S.QUALITY_LABELS.size() == 5)
	_ok("day_presets_10", S.DAY_LENGTH_PRESETS.size() == 10)
	var expect := [60.0, 300.0, 600.0, 900.0, 1200.0, 1500.0, 1800.0, 2400.0, 2700.0, 3600.0]
	_ok("day_presets_values", S.DAY_LENGTH_PRESETS == expect)
	for p in S.DAY_LENGTH_PRESETS:
		print("[DAY] ", int(p), "s -> ", S.day_length_label(p), " idx=", S.day_length_index(p))
	_ok("day_label_600", S.day_length_label(600.0) == "10 分钟 / 游戏日", S.day_length_label(600.0))
	_ok("day_label_3600", S.day_length_label(3600.0) == "60 分钟 / 游戏日", S.day_length_label(3600.0))
	_ok("migrate_480_to_600", absf(S.sanitize_day_length(480.0) - 600.0) < 0.01, str(S.sanitize_day_length(480.0)))
	_ok("migrate_1234_to_1200", absf(S.sanitize_day_length(1234.0) - 1200.0) < 0.01, str(S.sanitize_day_length(1234.0)))
	print("[SET] audio_groups=", S.audio_groups())
	_ok("audio_groups_5", S.audio_groups().size() == 5)
	_ok("audio_bus_names", S.audio_groups()[1]["bus"] == "IsleAmbient" and S.audio_groups()[4]["bus"] == "IsleSFX")
	print("[SET] resolutions=", S.RESOLUTIONS)
	_ok("res_3440", S.RESOLUTIONS.has(Vector2i(3440, 1440)))
	_ok("res_4k", S.RESOLUTIONS.has(Vector2i(3840, 2160)))
	var d: Dictionary = S.defaults()
	print("[SET] defaults=", d)
	_ok("default_quality_high", int(d["quality"]) == 2)
	_ok("default_day_600", absf(float(d["day_length"]) - 600.0) < 0.01)
	_ok("default_volume_master", absf(float(d["volume_master"]) - 0.8) < 0.001)
	_ok("default_overrides_empty", (d["quality_overrides"] as Dictionary).is_empty())
	_ok("default_window_mode", str(d["window_mode"]) == "windowed")
	# 保存 / 读取往返
	var tmp := "D:/休闲小岛幻境/开发产物/logs/probe_settings6.cfg"
	var v: Dictionary = S.defaults()
	v["quality"] = 3
	v["day_length"] = 1800.0
	v["volume_ambient"] = 0.42
	v["quality_overrides"] = {"sea_foam": 0.9}
	v["window_mode"] = "borderless"
	v["resolution"] = Vector2i(2560, 1440)
	v["timezone"] = "Asia/Shanghai"
	S.save_settings(v, tmp)
	var back: Dictionary = S.load_settings(tmp)
	print("[SET] roundtrip=", back)
	_ok("rt_quality", int(back["quality"]) == 3)
	_ok("rt_day", absf(float(back["day_length"]) - 1800.0) < 0.01)
	_ok("rt_ambient", absf(float(back["volume_ambient"]) - 0.42) < 0.001)
	_ok("rt_overrides", not (back["quality_overrides"] as Dictionary).is_empty())
	_ok("rt_window_mode", str(back["window_mode"]) == "borderless")
	_ok("rt_resolution", back["resolution"] == Vector2i(2560, 1440))
	_ok("rt_fullscreen_derived", bool(back["fullscreen"]) == false)
	_ok("custom_flag", S.quality_custom(back) == true)
	_ok("custom_summary", S.quality_summary(back) == "自定义")
	# 旧版仅 volume + fullscreen 配置迁移
	var cfg := ConfigFile.new()
	cfg.set_value("settings", "volume", 0.33)
	cfg.set_value("settings", "fullscreen", true)
	cfg.set_value("settings", "quality", 2)
	cfg.set_value("settings", "day_length", 480.0)
	cfg.save(tmp)
	var mig: Dictionary = S.load_settings(tmp)
	print("[SET] migrated=", mig)
	_ok("mig_volume", absf(float(mig["volume_master"]) - 0.33) < 0.001)
	_ok("mig_fullscreen_mode", str(mig["window_mode"]) == "fullscreen" and bool(mig["fullscreen"]))
	_ok("mig_quality", int(mig["quality"]) == 2)
	_ok("mig_day", absf(float(mig["day_length"]) - 600.0) < 0.01)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	print("[SET] fail_count=", _fail)
	if _fail == 0:
		print("[RESULT] ALL PASS")
	quit(1 if _fail > 0 else 0)
