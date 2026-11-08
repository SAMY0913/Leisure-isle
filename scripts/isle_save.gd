class_name IsleSave
extends RefCounted
## P7-FINALIZE —— 最小世界状态存档（共享库存 + 九格农田）。
##
## 只解决"真实时间农作 / 三次收获"不可缺少的持久化，不新建全局存档系统：
##   user://save.cfg
##     [meta]      version / saved_unix / godot / note
##     [inventory] state = IsleInventory.export_state()
##     [farm]      state = IsleFarm.export_state()
## 契约：
##   - 读档先完整校验（库存 + 农田都合法）才整体提交；任何一段非法 => 整份不采用，调用方走新游戏。
##   - 写档先备份旧文件；写失败/校验失败时恢复备份，绝不静默覆盖有效数据。
##   - 离线生长：saved_unix 到当前 unix 的差值（夹取 0..MAX_OFFLINE_SECONDS）作为现实经过秒数
##     注入 IsleFarm.advance_realtime，因此"关掉游戏期间作物也在按现实时间生长"。
##   - 系统时钟回拨（now < saved_unix）不产生负生长：离线秒数按 0 处理（进度保持，不倒退）。
##   - settings.cfg 只存偏好，本文件只存世界状态，两者互不覆盖。

const PATH := "user://save.cfg"
const BACKUP_PATH := "user://save.cfg.bak"
## P7-FINALIZE：主 user:// 不可写时（沙箱/权限）的兜底世界存档，位置同 settings 兜底：
## 开发运行 = 项目根目录；导出运行 = 可执行文件目录。正常环境不使用。
const FALLBACK_NAME := "save_fallback.cfg"
const SAVE_VERSION := 1
## 离线补涨上限：本作最长首次成熟约 105 现实分钟；1 天足以覆盖任何正常间隔，
## 同时避免系统时钟被大幅前调时出现"瞬间成熟很多轮"的异常。
const MAX_OFFLINE_SECONDS := 86400.0

const FarmScript := preload("res://scripts/isle_farm.gd")
const InvScript := preload("res://scripts/isle_inventory.gd")


## 当前现实 unix 秒（独立函数便于测试注入）。
static func now_unix() -> float:
	return Time.get_unix_time_from_system()


## 兜底世界存档绝对路径（仅主路径写失败时使用；正常玩家环境不会产生）。
static func fallback_path() -> String:
	var base := ""
	if OS.has_feature("editor"):
		base = ProjectSettings.globalize_path("res://")
	else:
		base = OS.get_executable_path().get_base_dir().path_join("")
	if base.is_empty():
		return ""
	return base.path_join(FALLBACK_NAME)


## 读档路径选择：主文件存在且不旧于兜底 -> 主；否则兜底；都无 -> 主（会返回 no_save）。
static func resolve_read_path(path: String = PATH) -> String:
	var fb := fallback_path()
	var has_primary := FileAccess.file_exists(path)
	var has_fallback := fb != "" and FileAccess.file_exists(fb)
	if has_fallback:
		if not has_primary:
			return fb
		if FileAccess.get_modified_time(fb) > FileAccess.get_modified_time(path):
			return fb
	return path


## 离线秒数：负值/无效值按 0，超过上限按上限。纯函数，便于测试。
static func offline_seconds(saved_unix: float, current_unix: float) -> float:
	if not is_finite(saved_unix) or not is_finite(current_unix):
		return 0.0
	return clampf(current_unix - saved_unix, 0.0, MAX_OFFLINE_SECONDS)


## 写档。返回 {ok, reason, path, saved_unix, farm_clock}。
## 旧文件会先复制到 .bak；save 失败或回读校验失败时恢复 .bak。
static func save_state(inventory: Object, farm: Object, current_unix: float = -1.0, path: String = PATH) -> Dictionary:
	if inventory == null or not inventory.has_method("export_state"):
		return {"ok": false, "reason": "no_inventory"}
	if farm == null or not farm.has_method("export_state"):
		return {"ok": false, "reason": "no_farm"}
	var stamp := current_unix if (is_finite(current_unix) and current_unix > 0.0) else now_unix()
	var inv_state: Variant = inventory.call("export_state")
	var farm_state: Variant = farm.call("export_state")
	if not (inv_state is Dictionary) or not (farm_state is Dictionary):
		return {"ok": false, "reason": "bad_export"}

	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", SAVE_VERSION)
	cfg.set_value("meta", "saved_unix", stamp)
	cfg.set_value("meta", "farm_clock_seconds", float(farm.call("now")))
	cfg.set_value("meta", "note", "P7-FINALIZE world save (inventory + 9-slot farm)")
	cfg.set_value("inventory", "state", inv_state)
	cfg.set_value("farm", "state", farm_state)

	var had_old := FileAccess.file_exists(path)
	if had_old:
		var old_bytes := FileAccess.get_file_as_bytes(path)
		if old_bytes.size() > 0:
			var bf := FileAccess.open(BACKUP_PATH, FileAccess.WRITE)
			if bf != null:
				bf.store_buffer(old_bytes)
				bf.close()
	var target_path := path
	var err: int = cfg.save(path)
	if err != OK:
		_restore_backup(had_old, path)
		# P7-FINALIZE：主 user:// 不可写（沙箱/权限 error 12）时回退到项目/可执行文件旁，
		# 让"关闭游戏后重新打开"仍能恢复农田与库存；正常环境永远走主路径。
		var fb := fallback_path()
		var err2 := -1
		if fb != "":
			var fcfg := ConfigFile.new()
			fcfg.set_value("meta", "version", SAVE_VERSION)
			fcfg.set_value("meta", "saved_unix", stamp)
			fcfg.set_value("meta", "farm_clock_seconds", float(farm.call("now")))
			fcfg.set_value("meta", "note", "P7-FINALIZE world save (fallback copy)")
			fcfg.set_value("inventory", "state", inv_state)
			fcfg.set_value("farm", "state", farm_state)
			err2 = fcfg.save(fb)
		if err2 != OK:
			push_warning("[SAVE] world save failed: %s (error %d) / fallback error %d" % [path, err, err2])
			return {"ok": false, "reason": "save_failed:%d" % err}
		target_path = fb
		push_warning("[SAVE] primary save failed (error %d), fallback saved %s" % [err, fb])
	# 回读校验：能读回、版本/关键段都在才算成功。
	var check := ConfigFile.new()
	var lerr: int = check.load(target_path)
	if lerr != OK or int(check.get_value("meta", "version", -1)) != SAVE_VERSION \
			or not (check.get_value("inventory", "state", null) is Dictionary) \
			or not (check.get_value("farm", "state", null) is Dictionary):
		_restore_backup(had_old, path)
		push_warning("[SAVE] world save verify failed: %s" % path)
		return {"ok": false, "reason": "verify_failed"}
	return {"ok": true, "reason": "", "path": target_path, "saved_unix": stamp,
		"farm_clock": float(farm.call("now"))}


static func _restore_backup(had_old: bool, path: String) -> void:
	if not had_old or not FileAccess.file_exists(BACKUP_PATH):
		return
	var bytes := FileAccess.get_file_as_bytes(BACKUP_PATH)
	if bytes.is_empty():
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_buffer(bytes)
		f.close()


## 只读检查存档是否存在且可读（不修改任何状态）。
static func has_save(path: String = PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var cfg := ConfigFile.new()
	return cfg.load(path) == OK and int(cfg.get_value("meta", "version", -1)) == SAVE_VERSION


## 读档并应用到 inventory/farm。
## 流程：读取 -> 用临时实例完整校验两段 -> 全部合法才写入真实对象 -> 注入离线生长。
## 返回 {ok, reason, offline_seconds, saved_unix, farm_clock, inventory}。
static func load_into(inventory: Object, farm: Object, current_unix: float = -1.0, path: String = PATH) -> Dictionary:
	# P7-FINALIZE：主存档/兜底存档取"较新的有效文件"；正常环境就是主存档，行为不变。
	# 显式传入 path（测试/迁移）时严格读该文件。
	var read_path := path
	if path == PATH:
		read_path = resolve_read_path(path)
	if not FileAccess.file_exists(read_path):
		return {"ok": false, "reason": "no_save"}
	var cfg := ConfigFile.new()
	if cfg.load(read_path) != OK:
		return {"ok": false, "reason": "load_failed"}
	if int(cfg.get_value("meta", "version", -1)) != SAVE_VERSION:
		return {"ok": false, "reason": "version_mismatch"}
	var saved_raw: Variant = cfg.get_value("meta", "saved_unix", null)
	if not (typeof(saved_raw) == TYPE_INT or typeof(saved_raw) == TYPE_FLOAT):
		return {"ok": false, "reason": "bad_saved_unix"}
	var saved_unix := float(saved_raw)
	if not is_finite(saved_unix) or saved_unix <= 0.0:
		return {"ok": false, "reason": "bad_saved_unix"}
	var inv_raw: Variant = cfg.get_value("inventory", "state", null)
	var farm_raw: Variant = cfg.get_value("farm", "state", null)
	if not (inv_raw is Dictionary) or not (farm_raw is Dictionary):
		return {"ok": false, "reason": "missing_sections"}
	var inv_state: Dictionary = inv_raw
	var farm_state: Dictionary = farm_raw

	# ---- 1) 临时实例完整校验（不碰真实对象） ----
	var tmp_inv = InvScript.new()
	if not bool(tmp_inv.call("restore_state", inv_state)):
		return {"ok": false, "reason": "bad_inventory"}
	var tmp_farm = FarmScript.new(null)
	tmp_farm.call("set_clock_mode", "real")
	if not bool(tmp_farm.call("restore_state", farm_state)):
		return {"ok": false, "reason": "bad_farm"}
	var now := current_unix if (is_finite(current_unix) and current_unix > 0.0) else now_unix()
	var offline := offline_seconds(saved_unix, now)

	# ---- 2) 校验通过后整体提交 ----
	if inventory == null or not inventory.has_method("restore_state"):
		return {"ok": false, "reason": "no_inventory"}
	if farm == null or not farm.has_method("restore_state"):
		return {"ok": false, "reason": "no_farm"}
	if not bool(inventory.call("restore_state", inv_state)):
		return {"ok": false, "reason": "inventory_commit_failed"}
	if not bool(farm.call("restore_state", farm_state)):
		return {"ok": false, "reason": "farm_commit_failed"}
	if inventory.has_method("mark_starting_granted"):
		inventory.call("mark_starting_granted")
	farm.call("set_clock_mode", "real")
	# 离线生长：恢复后的成长时钟 = 存档时刻；把离线秒数补进去。
	# 注意：IsleFarm.advance_realtime 对"单帧现实步长"有 MAX_REAL_STEP_SECONDS=300s 的夹取，
	# 离线补涨必须按该上限分块累加（否则关掉游戏 >5 分钟后作物离线生长被截断到 300s，
	# 与 MAX_OFFLINE_SECONDS=86400 的设计矛盾）。这是离线注入，不属于"单帧跳变"。
	if offline > 0.0 and farm.has_method("advance_realtime"):
		var remain := offline
		var step_cap := 300.0
		if FarmScript != null:
			step_cap = maxf(1.0, float(FarmScript.MAX_REAL_STEP_SECONDS))
		while remain > 0.0:
			var step := minf(remain, step_cap)
			farm.call("advance_realtime", step)
			remain -= step
	return {
		"ok": true, "reason": "", "offline_seconds": offline, "saved_unix": saved_unix,
		"farm_clock": float(farm.call("now")), "inventory": inventory.call("item_snapshot"),
	}


## 删除存档（只用于测试/重置；正式游戏不提供清档入口）。
static func clear_state(path: String = PATH) -> bool:
	var ok := true
	if FileAccess.file_exists(path):
		ok = DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK
	if FileAccess.file_exists(BACKUP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(BACKUP_PATH))
	return ok
