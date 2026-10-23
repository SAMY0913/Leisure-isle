class_name IsleFarm
extends RefCounted
## P9 / P1 —— 九格农田数据层（RefCounted，不依赖场景/UI/NPC）。
##
## 唯一权威状态：九格 Dictionary + 外部注入的库存（未来 IsleInventory）。
## 本类绝不自己保存种子库存；库存通过鸭子类型接口注入：
##   get_count(item_id: String) -> int
##   remove_item(item_id: String, amount: int) -> bool
##   add_items(item_deltas: Dictionary) -> bool   # 一次采收的成品+返还种子必须原子提交
##
## 时间：只接受主系统传入的模拟秒快照（IsleFarm.advance_to(sim_seconds)），
## 不使用 Timer / Time.get_ticks_msec / 任何独立时钟。模拟时间不推进 => 作物不生长。
##
## 九格索引：s = j * 3 + i，i=0..2 左->右（房屋局部 X），j=0..2 前->后（房屋局部 Z）。
## 与 P0 验收的田块索引一致；GRID_PITCH 为 P0 实测格心距 1.5 m，供 P2 视觉层复用。
##
## 事务规则：
##   播种：校验空位/作物/季节/种子 -> remove_item 成功 -> 才写入格状态；任何失败不改状态。
##   采收：校验成熟 -> 计算成品与首收种子 -> add_items 原子提交成功 -> 才写状态。
## 重复调用（重入/中断后重试）不会重复扣种子或重复发农产品：状态在提交后才变化。
## plant()/harvest() 带重入守卫：若注入的库存实现同步回调农田（例如扣种子时再触发
## 一次播种/采收），回调会得到 {ok:false, reason:"busy"}，不会双扣种子或双发产出。

## 静态作物定义（preload 而非依赖全局 class 缓存，headless --script 首跑也能解析）。
const CROPS := preload("res://scripts/isle_crops.gd")

const SLOT_COUNT := 9
const GRID_PITCH := 1.5
const STATE_VERSION := 1

## 外部库存（Object，鸭子类型）。null 表示未注入：播种/采收返回明确失败，不崩溃。
var _inventory: Object = null
var _slots: Array = []
var _sim_seconds := 0.0
var _clock_ready := false
var _busy := false
var _last_chosen := ""
## 暖季作物冬季能否新种：实例级配置（不是全局 static，避免跨存档/跨探针泄漏）。
var allow_warm_in_winter := false
var _rng := RandomNumberGenerator.new()


func _init(inventory: Object = null) -> void:
	_rng.randomize()
	if inventory != null:
		set_inventory(inventory)
	reset()


# ============================================================ 基础 =========
## 注入库存（任何实现 get_count/remove_item/add_items 的对象）。
## 事务进行中（库存回调里）忽略重设，避免半途换库存破坏原子性。
func set_inventory(inventory: Object) -> void:
	if _busy:
		return
	_inventory = inventory


## 设置可复现随机数种子（自动选种测试用）。事务进行中忽略。
func set_rng_seed(seed_value: int) -> void:
	if _busy:
		return
	_rng.seed = seed_value


## 仅供测试/回放：读取当前 RNG 状态（不改变状态）。
func rng_state() -> int:
	return _rng.state


## 清空九格（保留库存引用与当前模拟时刻）。仅用于测试/重置，不是游戏内"铲除"功能。
## 事务进行中（库存回调里）忽略，避免已扣种子后清空/重建路径不一致。
func reset() -> void:
	if _busy:
		return
	_slots.clear()
	for _i in range(SLOT_COUNT):
		_slots.append(_empty_slot())
	_last_chosen = ""


func slot_index(i: int, j: int) -> int:
	return clampi(j, 0, 2) * 3 + clampi(i, 0, 2)


func slot_ij(index: int) -> Vector2i:
	return Vector2i(index % 3, int(index / 3))


## 该格中心相对田心的局部偏移（米）；P2 视觉层用它放置九格中心。
func slot_offset(index: int) -> Vector2:
	var ij := slot_ij(index)
	return Vector2(float(ij.x - 1) * GRID_PITCH, float(ij.y - 1) * GRID_PITCH)


func slot_count() -> int:
	return SLOT_COUNT


# ============================================================ 时间 =========
## 注入权威模拟秒快照。第一次成功调用即视为"主时钟已就绪"（未就绪时禁止播种，
## 避免用 0 时刻种下作物后，第一次快照让它瞬间成熟）。
##
## 时间回退（玩家拨时间 / 切换 real↔sim 时间源）不会让作物退回幼苗：
## 所有格内时间戳按同一个 delta 平移，作物的"年龄"保持不变，也不会出现
## "死区"（旧实现直接忽略回退，会让作物冻结到主时钟重新追上旧快照）。
func advance_to(sim_seconds: float) -> void:
	# 非有限/负时钟（损坏的存档或引擎异常值）不参与时间语义，直接忽略。
	if not is_finite(sim_seconds) or sim_seconds < 0.0:
		return
	if sim_seconds < _sim_seconds:
		_shift_slots(sim_seconds - _sim_seconds)
		_sim_seconds = sim_seconds
		_clock_ready = true
		_notes_guard_backward(sim_seconds)
		return
	_sim_seconds = sim_seconds
	_clock_ready = true


func now() -> float:
	return _sim_seconds


## 主时钟是否已经至少成功同步过一次（P2 集成前置条件：先 advance_to 再播种）。
func clock_ready() -> bool:
	return _clock_ready


## 仅供探针诊断：是否发生过时间回退（状态已按 delta 平移，不会冻结/回退阶段）。
func _shift_slots(delta: float) -> void:
	if delta == 0.0:
		return
	for s in _slots:
		var slot: Dictionary = s
		if String(slot.get("crop_id", "")).is_empty():
			continue
		slot["planted_at"] = maxf(0.0, float(slot.get("planted_at", 0.0)) + delta)
		slot["cycle_started_at"] = maxf(0.0, float(slot.get("cycle_started_at", 0.0)) + delta)
		slot["next_ready_at"] = maxf(0.0, float(slot.get("next_ready_at", 0.0)) + delta)


var _backward_attempts := 0

func backward_attempts() -> int:
	return _backward_attempts

func _notes_guard_backward(_attempt: float) -> void:
	_backward_attempts += 1


# ============================================================ 查询 =========
func is_empty(index: int) -> bool:
	if not _valid_index(index):
		return true
	return String((_slots[index] as Dictionary).get("crop_id", "")).is_empty()


## 返回格状态副本；空格的 crop_id 为空串。
func get_slot(index: int) -> Dictionary:
	var out := _empty_slot()
	if not _valid_index(index):
		out["empty"] = true
		return out
	var s: Dictionary = _slots[index]
	out = (s as Dictionary).duplicate(true)
	out["empty"] = String(s.get("crop_id", "")).is_empty()
	return out


func crop_id_at(index: int) -> String:
	if not _valid_index(index):
		return ""
	return String((_slots[index] as Dictionary).get("crop_id", ""))


## 根据权威时间与周期起点算出的阶段 id；空格返回空串。
func stage_id(index: int) -> String:
	if is_empty(index):
		return ""
	var s: Dictionary = _slots[index]
	var crop := String(s.get("crop_id", ""))
	var cycle := _cycle_for(crop, int(s.get("harvest_count", 0)))
	if cycle <= 0.0:
		return ""
	var elapsed := maxf(0.0, _sim_seconds - float(s.get("cycle_started_at", 0.0)))
	return CROPS.stage_at(crop, elapsed, cycle)


func stage_index(index: int) -> int:
	if is_empty(index):
		return -1
	var s: Dictionary = _slots[index]
	var crop := String(s.get("crop_id", ""))
	var cycle := _cycle_for(crop, int(s.get("harvest_count", 0)))
	if cycle <= 0.0:
		return -1
	var elapsed := maxf(0.0, _sim_seconds - float(s.get("cycle_started_at", 0.0)))
	return CROPS.stage_index_at(crop, elapsed, cycle)


## 距离当前周期成熟还剩多少模拟秒（已成熟返回 0）。
func seconds_to_mature(index: int) -> float:
	if is_empty(index):
		return -1.0
	return maxf(0.0, float((_slots[index] as Dictionary).get("next_ready_at", 0.0)) - _sim_seconds)


func is_mature(index: int) -> bool:
	if is_empty(index):
		return false
	# 1e-6 的容差只吸收浮点表示误差，不改变语义。
	return _sim_seconds + 0.000001 >= float((_slots[index] as Dictionary).get("next_ready_at", 0.0))


func harvest_count(index: int) -> int:
	if is_empty(index):
		return 0
	return int((_slots[index] as Dictionary).get("harvest_count", 0))


func seed_returned(index: int) -> bool:
	if is_empty(index):
		return false
	return bool((_slots[index] as Dictionary).get("seed_returned", false))


# ============================================================ 播种 =========
## 校验能否播种；返回 {ok: bool, reason: String}，reason 为空表示可播。
## reason 取值：invalid_index / occupied / unknown_crop / season_not_allowed / no_inventory / no_seed。
func can_plant(index: int, crop_id: String, season_id: String) -> Dictionary:
	if not _valid_index(index):
		return _res(false, "invalid_index")
	if not is_empty(index):
		return _res(false, "occupied")
	if not CROPS.has_crop(crop_id):
		return _res(false, "unknown_crop")
	if not CROPS.plantable(crop_id, season_id, allow_warm_in_winter):
		return _res(false, "season_not_allowed")
	if not _inventory_ready():
		return _res(false, "no_inventory")
	if not _clock_ready:
		return _res(false, "clock_not_ready")
	var seed_id := CROPS.seed_item(crop_id)
	if _inv_count(seed_id) <= 0:
		return _res(false, "no_seed")
	return _res(true, "")


## 播种事务：先扣种子（原子），成功后才建立植株状态；失败时库存与农田都不变。
func plant(index: int, crop_id: String, season_id: String) -> Dictionary:
	if _busy:
		return _res(false, "busy")
	_busy = true
	var check := can_plant(index, crop_id, season_id)
	if not bool(check.get("ok", false)):
		_busy = false
		return check
	var seed_id := CROPS.seed_item(crop_id)
	if not _inv_remove(seed_id, 1):
		_busy = false
		return _res(false, "inventory_remove_failed")
	var first := CROPS.first_maturity_seconds(crop_id)
	_slots[index] = {
		"crop_id": crop_id,
		"planted_at": _sim_seconds,
		"cycle_started_at": _sim_seconds,
		"next_ready_at": _sim_seconds + maxf(first, 0.0),
		"harvest_count": 0,
		"seed_returned": false,
	}
	# 只有成功的植物才更新"上一次选中作物"（choose_crop 本身是纯函数）。
	_last_chosen = crop_id
	_busy = false
	return _res(true, "")


# ============================================================ 采收 =========
## 校验能否采收；返回 {ok: bool, reason: String}。
## reason 取值：invalid_index / empty / not_mature / no_inventory。
func can_harvest(index: int) -> Dictionary:
	if not _valid_index(index):
		return _res(false, "invalid_index")
	if is_empty(index):
		return _res(false, "empty")
	if not is_mature(index):
		return _res(false, "not_mature")
	if not _inventory_ready():
		return _res(false, "no_inventory")
	return _res(true, "")


## 采收事务：成品与"首收返还种子"合并成一次 add_items 原子提交；提交失败不改农田状态。
## 返回 {ok, reason, crop_id, produce_item, produce_amount, seed_returned, plant_removed}。
func harvest(index: int) -> Dictionary:
	if _busy:
		var busy := _res(false, "busy")
		busy["produce_item"] = ""
		busy["produce_amount"] = 0
		busy["seed_returned"] = 0
		busy["plant_removed"] = false
		return busy
	_busy = true
	var check := can_harvest(index)
	if not bool(check.get("ok", false)):
		check["produce_item"] = ""
		check["produce_amount"] = 0
		check["seed_returned"] = 0
		check["plant_removed"] = false
		_busy = false
		return check
	var s: Dictionary = _slots[index]
	var crop := String(s.get("crop_id", ""))
	var produce_id := CROPS.produce_item(crop)
	var produce_amount := CROPS.harvest_amount(crop)
	var seed_amount := 0
	if not bool(s.get("seed_returned", false)) and CROPS.returns_seed_on_first_harvest(crop):
		seed_amount = 1
	var deltas: Dictionary = {}
	if produce_amount > 0:
		deltas[produce_id] = int(deltas.get(produce_id, 0)) + produce_amount
	if seed_amount > 0:
		var seed_id := CROPS.seed_item(crop)
		deltas[seed_id] = int(deltas.get(seed_id, 0)) + seed_amount
	if deltas.is_empty():
		_busy = false
		var ed := _res(false, "empty_delta")
		ed["produce_item"] = ""
		ed["produce_amount"] = 0
		ed["seed_returned"] = 0
		ed["plant_removed"] = false
		return ed
	if not _inv_add(deltas):
		var fail := _res(false, "inventory_add_failed")
		fail["produce_item"] = ""
		fail["produce_amount"] = 0
		fail["seed_returned"] = 0
		fail["plant_removed"] = false
		_busy = false
		return fail

	# ---- 库存已原子提交，下面只做不会失败的内存状态更新 ----
	var count := int(s.get("harvest_count", 0)) + 1
	var returned := 1 if seed_amount > 0 else 0
	var plant_removed := false
	if CROPS.is_regrowing(crop):
		# 快进后只按"当前时刻 + 一轮再生成熟"计算下一次成熟，绝不补发错过的多轮。
		# 可配置总收获次数上限（含首收；-1=无限，P1 缺省无限）：达到上限后植株结束。
		var limit := CROPS.harvest_cycle_limit(crop)
		if limit > 0 and count >= limit:
			_slots[index] = _empty_slot()
			plant_removed = true
		else:
			var regrow := CROPS.regrow_seconds(crop)
			if regrow <= 0.0:
				regrow = CROPS.first_maturity_seconds(crop)
			s["harvest_count"] = count
			s["seed_returned"] = true if returned > 0 else bool(s.get("seed_returned", false))
			s["cycle_started_at"] = _sim_seconds
			s["next_ready_at"] = _sim_seconds + regrow
			_slots[index] = s
	else:
		_slots[index] = _empty_slot()
		plant_removed = true

	var out := _res(true, "")
	out["crop_id"] = crop
	out["produce_item"] = produce_id
	out["produce_amount"] = produce_amount
	out["seed_returned"] = returned
	out["plant_removed"] = plant_removed
	_busy = false
	return out


# ============================================================ 自动选种 ====
## 均衡随机选种：只考虑"库存有种子 + 当前季节允许新种"的作物；
## 优先当前在田株数最少的一组；组内用可注入 RNG 随机，且多候选中降低连续同种概率。
## 不修改农田状态（slots / _last_chosen 只在 plant() 成功后才更新），可安全重复调用；
## 但随机选择本身会消耗注入 RNG 的随机序列（这是设计行为，不是状态突变）。
## 没有任何可选作物时返回空串（调用方据此得到"没有可执行种植目标"，不得生成种子）。
func choose_crop(season_id: String) -> String:
	if not _inventory_ready():
		return ""
	var candidates: Array = []
	for crop_id in CROPS.all_ids():
		var cid := String(crop_id)
		if not CROPS.plantable(cid, season_id, allow_warm_in_winter):
			continue
		if _inv_count(CROPS.seed_item(cid)) <= 0:
			continue
		candidates.append(cid)
	if candidates.is_empty():
		return ""
	var counts := _crop_counts()
	var min_count := 2147483647
	for crop_id in candidates:
		min_count = mini(min_count, int(counts.get(crop_id, 0)))
	var group: Array = []
	for crop_id in candidates:
		if int(counts.get(crop_id, 0)) == min_count:
			group.append(crop_id)
	# 组内多候选时，按概率把上一次选中的作物移出本轮候选：既降低连续同种概率，
	# 又不会在只有 2 个候选时退化成严格的确定性交替。
	if group.size() > 1 and group.has(_last_chosen) and _rng.randf() < 0.70:
		group.erase(_last_chosen)
	return String(group[_rng.randi_range(0, group.size() - 1)])


## 自动播种：先选种再播种，返回播种结果并附 crop_id（无目标时 ok=false, reason="no_candidate"）。
## 前置校验（索引/时钟/空格/库存）全部在 choose_crop 之前完成：
## 这些失败路径不消耗任何 RNG，保证"失败的自动播种"不会扰动后续选种随机序列。
func plant_auto(index: int, season_id: String) -> Dictionary:
	if not _valid_index(index):
		return _auto_fail("invalid_index")
	if not _clock_ready:
		return _auto_fail("clock_not_ready")
	if not is_empty(index):
		return _auto_fail("occupied")
	if not _inventory_ready():
		return _auto_fail("no_inventory")
	var crop := choose_crop(season_id)
	if crop.is_empty():
		return _auto_fail("no_candidate")
	var out := plant(index, crop, season_id)
	out["crop_id"] = crop
	return out


func _crop_counts() -> Dictionary:
	var counts: Dictionary = {}
	for s in _slots:
		var crop := String((s as Dictionary).get("crop_id", ""))
		if crop.is_empty():
			continue
		counts[crop] = int(counts.get(crop, 0)) + 1
	return counts


# ============================================================ 导出/恢复 ===
## 导出稳定状态（P1 不写存档文件；P2/后续存档系统复用该结构）。
func export_state() -> Dictionary:
	var slots: Array = []
	for s in _slots:
		var src: Dictionary = s
		slots.append({
			"crop_id": String(src.get("crop_id", "")),
			"planted_at": float(src.get("planted_at", 0.0)),
			"cycle_started_at": float(src.get("cycle_started_at", 0.0)),
			"next_ready_at": float(src.get("next_ready_at", 0.0)),
			"harvest_count": int(src.get("harvest_count", 0)),
			"seed_returned": bool(src.get("seed_returned", false)),
		})
	return {
		"version": STATE_VERSION,
		"slot_count": SLOT_COUNT,
		# 仅作为"导出时刻"元数据；主时钟（IsleFarm.advance_to 的快照）才是权威。
		"saved_at_sim_seconds": _sim_seconds,
		"last_chosen": _last_chosen,
		"slots": slots,
	}


## 从导出数据恢复；先完整校验到临时结构，全部合法才整体提交（失败时状态不变）。
## 校验项包括：版本/格数/作物/有限非负时间戳/timestamps 顺序/下一次成熟=本轮起点+周期/
## 播种与本轮起点不晚于存档时刻/一次性作物无采收次数/采收次数不超过再生上限/
## 种子返还与采收次数一致。
## 主时钟权威：导出里的 saved_at_sim_seconds 只是"存档时刻"元数据，不当作第二个时钟。
## current_sim_seconds 可选：读档时主时钟若与存档时刻不同（real 模式换天/切时间源），
## 传当前主时钟；格内时间戳按 delta 整体平移以保持阶段，不制造死区/瞬间成熟。
## 事务中（_busy）直接返回 false：不得在库存 remove_item/add_items 的同步回调里读档，
## 否则会替换外层事务正在修改的 _slots。
## 说明：下方"有限再生上限"分支（regrow_cycles>0）是给未来配置预留的防御校验；
## 当前五种作物均为无限再生或一次性，该分支无数据可触发、未经运行验证。
func restore_state(data: Dictionary, current_sim_seconds: float = NAN) -> bool:
	if _busy:
		return false
	var version := int(data.get("version", -1))
	if version != STATE_VERSION:
		return false
	if int(data.get("slot_count", -1)) != SLOT_COUNT:
		return false
	var slots_raw = data.get("slots", null)
	if not (slots_raw is Array) or (slots_raw as Array).size() != SLOT_COUNT:
		return false
	var has_current := not is_nan(current_sim_seconds)
	var stored_sim := _sim_seconds
	if data.has("saved_at_sim_seconds"):
		stored_sim = float(data.get("saved_at_sim_seconds", 0.0))
		if not is_finite(stored_sim) or stored_sim < 0.0:
			return false
	if has_current:
		if not is_finite(current_sim_seconds) or current_sim_seconds < 0.0:
			return false
	var temp: Array = []
	for raw in (slots_raw as Array):
		if not (raw is Dictionary):
			return false
		var d: Dictionary = raw
		var crop := String(d.get("crop_id", ""))
		if crop.is_empty():
			temp.append(_empty_slot())
			continue
		if not CROPS.has_crop(crop):
			return false
		var planted := float(d.get("planted_at", 0.0))
		var cycle_started := float(d.get("cycle_started_at", 0.0))
		var next_ready := float(d.get("next_ready_at", 0.0))
		var count_raw := float(d.get("harvest_count", 0.0))
		# 不接受小数采收次数（JSON 数字读回是 float，因此先做整数性校验再转 int）。
		if not is_finite(count_raw) or count_raw < 0.0 or absf(count_raw - floor(count_raw)) > 0.000001:
			return false
		var count := int(count_raw)
		var returned := bool(d.get("seed_returned", false))
		if not is_finite(planted) or not is_finite(cycle_started) or not is_finite(next_ready):
			return false
		if planted < 0.0 or cycle_started < 0.0 or next_ready < 0.0:
			return false
		if count < 0:
			return false
		if planted > cycle_started + 0.000001:
			return false
		if next_ready < cycle_started:
			return false
		# 一次性作物不可能有采收次数（收获即清空）。
		if not CROPS.is_regrowing(crop) and count != 0:
			return false
		# 有限再生上限（regrow_cycles>0）：达到上限的植株应已被清空，
		# 存档中若仍存在说明是旧配置或伪造数据，整份存档拒绝。
		var cycle_limit := CROPS.harvest_cycle_limit(crop)
		if cycle_limit > 0 and count >= cycle_limit:
			return false
		# 时间戳一致性：下一次成熟必须等于"本轮起点 + 本轮周期"（防止篡改/旧版本错配）。
		var expected_cycle := CROPS.cycle_seconds(crop, count)
		if expected_cycle <= 0.0:
			return false
		if absf((next_ready - cycle_started) - expected_cycle) > 0.01:
			return false
		# 存档时刻之前不应出现"未来的种植/本轮起点"；next_ready_at 可以是未来（生长中）。
		if cycle_started > stored_sim + 0.01 or planted > stored_sim + 0.01:
			return false
		# 种子返还状态必须与采收次数一致：首次采收会返还并置位；
		# 若该作物配置为不返还种子，则 returned 必须始终为 false。
		if CROPS.returns_seed_on_first_harvest(crop):
			if count > 0 and not returned:
				return false
			if count == 0 and returned:
				return false
		elif returned:
			return false
		temp.append({
			"crop_id": crop,
			"planted_at": planted,
			"cycle_started_at": cycle_started,
			"next_ready_at": next_ready,
			"harvest_count": count,
			"seed_returned": returned,
		})
	# 全部合法，整体提交。
	var target_sim := current_sim_seconds if has_current else stored_sim
	var delta := target_sim - stored_sim
	if delta != 0.0:
		for s in temp:
			var slot: Dictionary = s
			if String(slot.get("crop_id", "")).is_empty():
				continue
			slot["planted_at"] = maxf(0.0, float(slot.get("planted_at", 0.0)) + delta)
			slot["cycle_started_at"] = maxf(0.0, float(slot.get("cycle_started_at", 0.0)) + delta)
			slot["next_ready_at"] = maxf(0.0, float(slot.get("next_ready_at", 0.0)) + delta)
	_slots = temp
	_sim_seconds = target_sim
	_clock_ready = true
	_last_chosen = String(data.get("last_chosen", ""))
	if not CROPS.has_crop(_last_chosen):
		_last_chosen = ""
	return true


# ============================================================ 内部 =========
func _empty_slot() -> Dictionary:
	return {
		"crop_id": "",
		"planted_at": 0.0,
		"cycle_started_at": 0.0,
		"next_ready_at": 0.0,
		"harvest_count": 0,
		"seed_returned": false,
	}


func _cycle_for(crop_id: String, harvest_count_value: int) -> float:
	return CROPS.cycle_seconds(crop_id, harvest_count_value)


func _valid_index(index: int) -> bool:
	return index >= 0 and index < SLOT_COUNT


static func _res(ok: bool, reason: String) -> Dictionary:
	return {"ok": ok, "reason": reason}


## plant_auto 的失败返回（统一带空 crop_id），保持与成功返回同构。
static func _auto_fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "crop_id": ""}


func _inventory_ready() -> bool:
	return _inventory != null and _inventory.has_method("get_count") and _inventory.has_method("remove_item") and _inventory.has_method("add_items")


func _inv_count(item_id: String) -> int:
	if not _inventory_ready():
		return 0
	var v = _inventory.call("get_count", item_id)
	if typeof(v) == TYPE_INT:
		return int(v)
	if typeof(v) == TYPE_FLOAT:
		return int(v)
	return 0


func _inv_remove(item_id: String, amount: int) -> bool:
	if not _inventory_ready() or amount <= 0:
		return false
	var v = _inventory.call("remove_item", item_id, amount)
	return typeof(v) == TYPE_BOOL and bool(v)


func _inv_add(deltas: Dictionary) -> bool:
	if not _inventory_ready() or deltas.is_empty():
		return false
	var v = _inventory.call("add_items", deltas)
	return typeof(v) == TYPE_BOOL and bool(v)
