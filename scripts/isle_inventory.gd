class_name IsleInventory
extends RefCounted
## P9 / P4 —— 全岛共享运行时库存（RefCounted，不依赖场景/UI/NPC）。
##
## 权威职责：物品 ID -> 非负整数数量。农田（IsleFarm）通过公开接口请求扣种/入账，
## 岛民行为层不直接读写本字典；视觉层只读。
##
## 物品 ID：isle_crops.gd 的 seed_<crop> / <crop>（五种作物）+
## isle_fish.gd 的 fish_<species>（六种近岸鱼）。规范顺序 = 种子、产物、鱼（鱼在最后）。
## 未知 ID 的任何写操作都整笔失败（不留下部分变更）；鱼与作物共享同一套校验/事务语义。
## 未来烹饪等物品在各阶段继续扩展目录，不提前造 ID。
##
## 事务：add_items / remove_item / try_consume_items 先完整校验再提交；
## 校验失败时字典与数量完全不变。数量必须是非负整数，任何操作都不会产生负数。
## 容量无限（不实现格子/容量上限），但仍校验 ID/数量并保证原子性。
##
## 初始种子：STARTING_SEEDS_PER_CROP 仅在新运行时的首次初始化发放一次；
## 场景重建/重复初始化/农田视觉刷新都不会再次发放（见 grant_starting_seeds 的实例内守卫）。

## 作物定义（preload 而非依赖全局 class 缓存，headless --script 首跑也能解析）。
const CROPS := preload("res://scripts/isle_crops.gd")
## 鱼类目录（P6）：库存只依赖其静态 ID/判定，不依赖场景。
const FISH := preload("res://scripts/isle_fish.gd")

## 状态版本保持 1：新增鱼只是扩大"规范 ID"集合，导出结构不变；旧存档缺少鱼条目按 0 读取。
const STATE_VERSION := 1

## 新游戏初始种子：五种作物各 9 颗（仅让九格农田在任一季节至少有一种可种作物时能填满，
## 不代表最终经济平衡）。发放逻辑集中在 grant_starting_seeds()，正式初始化只在 main 调用一次。
const STARTING_SEEDS_PER_CROP := 9

## 物品数量上限：只是防御非法数据（float 溢出/JSON 脏数据），远大于任何正常游戏数量。
const MAX_COUNT := 1_000_000_000

var _items: Dictionary = {}
## 本实例是否已经发放过初始种子（避免 _ready/_build_world 重入时重复发放）。
var _starting_granted := false


func _init(initial: Dictionary = {}) -> void:
	if not initial.is_empty():
		# 构造注入：非法数据直接丢弃整份初始状态（保持空库存），不留下部分写入。
		if not restore_state({"version": STATE_VERSION, "items": initial}):
			_items.clear()


# ============================================================ 物品目录 =====
## 全部规范物品 ID（种子 + 产物 + 鱼，顺序固定便于测试/导出/背包排序）。
func known_item_ids() -> Array:
	return catalog_ids()


## 规范目录顺序的静态版本（背包排序/探针不需要实例）。
## 顺序：五种种子 -> 五种产物 -> 六种鱼（鱼在最后），与 known_item_ids 严格同序。
static func catalog_ids() -> Array:
	var out: Array = []
	for crop_id in CROPS.CROP_IDS:
		out.append(CROPS.seed_item(String(crop_id)))
	for crop_id in CROPS.CROP_IDS:
		out.append(CROPS.produce_item(String(crop_id)))
	for fish_id in FISH.FISH_IDS:
		out.append(String(fish_id))
	return out


func is_known_item(item_id: String) -> bool:
	return CROPS.has_crop(_crop_of_seed(item_id)) or CROPS.has_crop(item_id) or FISH.has_fish(item_id)


func _crop_of_seed(item_id: String) -> String:
	for crop_id in CROPS.CROP_IDS:
		var cid := String(crop_id)
		if CROPS.seed_item(cid) == item_id:
			return cid
	return ""


# ============================================================ 背包分类 =====
## 物品大类："seed" 种子 / "produce" 产物 / "fish" 鱼获 / "" 未知 ID（HUD 整理只读消费）。
static func item_category(item_id: String) -> String:
	for crop_id in CROPS.CROP_IDS:
		if CROPS.seed_item(String(crop_id)) == item_id:
			return "seed"
	if CROPS.has_crop(item_id):
		return "produce"
	if FISH.has_fish(item_id):
		return "fish"
	return ""


## 大类排序权重：seed 0 < produce 1 < fish 2 < 未知 3。
## 背包"一键整理"按 (category_rank, catalog_index) 升序即可稳定排序。
static func category_rank(item_id: String) -> int:
	match item_category(item_id):
		"seed":
			return 0
		"produce":
			return 1
		"fish":
			return 2
		_:
			return 3


## 在 known_item_ids() 规范顺序中的下标；未知 ID 返回 -1。
## 同大类内下标严格递增（种子 < 产物 < 鱼），可直接作为次级排序键。
static func catalog_index(item_id: String) -> int:
	var ids := catalog_ids()
	for i in range(ids.size()):
		if String(ids[i]) == item_id:
			return i
	return -1


# ============================================================ 查询 =========
## 查询数量；未知 ID 返回 0（只读查询不写入、不报错）。
func get_count(item_id: String) -> int:
	if not _items.has(item_id):
		return 0
	return int(_items[item_id])


## 批量检查（不修改状态）。items 为空视为满足。
func has_items(items: Dictionary) -> bool:
	if not _valid_deltas(items):
		return false
	for item_id in items.keys():
		if get_count(String(item_id)) < int(items[item_id]):
			return false
	return true


## 导出普通物品表（副本；测试/调试用）。只读。
func item_snapshot() -> Dictionary:
	var out: Dictionary = {}
	for item_id in _items.keys():
		out[String(item_id)] = int(_items[item_id])
	return out


func total_count() -> int:
	var total := 0
	for item_id in _items.keys():
		total += int(_items[item_id])
	return total


# ============================================================ 写事务 =======
## 批量增加（原子）：全部 ID/数量合法才一次写入；否则整笔失败、库存不变。
## items 为空是合法的 no-op（返回 true）。
func add_items(items: Dictionary) -> bool:
	if not _valid_deltas(items):
		return false
	for item_id in items.keys():
		var id := String(item_id)
		_items[id] = get_count(id) + int(items[item_id])
	return true


## 扣除单一物品（原子）：数量足够才扣，否则返回 false 且库存不变。
func remove_item(item_id: String, amount: int) -> bool:
	if not is_known_item(item_id):
		return false
	if amount <= 0 or amount > MAX_COUNT:
		return false
	var have := get_count(item_id)
	if have < amount:
		return false
	_items[item_id] = have - amount
	return true


## 原子检查并扣除多种物品（供播种组合材料/未来烹饪复用）。
## 任一条目非法或数量不足 => 整笔失败，不会部分扣除。
func try_consume_items(items: Dictionary) -> bool:
	if not _valid_deltas(items):
		return false
	for item_id in items.keys():
		if get_count(String(item_id)) < int(items[item_id]):
			return false
	for item_id in items.keys():
		var id := String(item_id)
		_items[id] = get_count(id) - int(items[item_id])
	return true


# ============================================================ 初始种子 =====
## 新游戏初始种子表（不修改库存；供测试/报告核对）。
static func starting_seeds() -> Dictionary:
	var out: Dictionary = {}
	for crop_id in CROPS.CROP_IDS:
		out[CROPS.seed_item(String(crop_id))] = STARTING_SEEDS_PER_CROP
	return out


## 发放初始种子；每个实例最多成功一次（重入/重复初始化返回 false 且不改变库存）。
## 正式初始化只由 main._setup_inventory() 调一次；探针可对自建实例调用以验证幂等。
func grant_starting_seeds() -> bool:
	if _starting_granted:
		return false
	var seeds := starting_seeds()
	# 初始表恒合法（来自 isle_crops 规范 ID + 正数常量），失败只可能是代码被改坏。
	if not add_items(seeds):
		push_warning("P4: IsleInventory 初始种子表非法，未发放")
		return false
	_starting_granted = true
	return true


func starting_granted() -> bool:
	return _starting_granted


## P7-FINALIZE：读档恢复后标记"初始种子已处理"，防止同一实例再次 grant 造成 +45 种子。
## 只置位、不改变任何物品数量，由存档层在 restore_state 成功后调用。
func mark_starting_granted() -> void:
	_starting_granted = true


# ============================================================ 状态导出 =====
## 稳定导出（按物品 ID 排序，便于存档 diff/测试断言）。
func export_state() -> Dictionary:
	var ids: Array = _items.keys()
	ids.sort()
	var items: Dictionary = {}
	for item_id in ids:
		var count := int(_items[item_id])
		if count > 0:
			items[String(item_id)] = count
	return {
		"version": STATE_VERSION,
		"items": items,
	}


## 从导出数据恢复：先完整校验到临时字典，合法才整体替换；失败时库存不变。
## 接受整数型 JSON 数字（float 但必须整值）；0 数量合法但会被丢弃。
func restore_state(data: Dictionary) -> bool:
	if not data.has("version"):
		return false
	if not _is_integral(data["version"]) or int(data["version"]) != STATE_VERSION:
		return false
	if not data.has("items") or typeof(data["items"]) != TYPE_DICTIONARY:
		return false
	var src: Dictionary = data["items"]
	var next: Dictionary = {}
	for raw_id in src.keys():
		if typeof(raw_id) != TYPE_STRING:
			return false
		var item_id := String(raw_id)
		if not is_known_item(item_id):
			return false
		if not _is_integral(src[raw_id]):
			return false
		var count := int(src[raw_id])
		if count < 0 or count > MAX_COUNT:
			return false
		if count > 0:
			next[item_id] = count
	_items = next
	return true


# ============================================================ 内部校验 =====
## 校验一份 "ID -> 数量" 增量表：ID 必须是规范物品，数量必须是 1..MAX_COUNT 的整数。
func _valid_deltas(items: Dictionary) -> bool:
	for raw_id in items.keys():
		if typeof(raw_id) != TYPE_STRING:
			return false
		var item_id := String(raw_id)
		if not is_known_item(item_id):
			return false
		if not _is_integral(items[raw_id]):
			return false
		var amount := int(items[raw_id])
		if amount <= 0 or amount > MAX_COUNT:
			return false
	return true


## 只接受真正的整数值（int 或整值 float；拒绝 bool/String/NaN/Inf/小数）。
func _is_integral(value: Variant) -> bool:
	match typeof(value):
		TYPE_INT:
			return true
		TYPE_FLOAT:
			var f := float(value)
			return is_finite(f) and f == floor(f) and absf(f) <= float(MAX_COUNT)
		_:
			return false
