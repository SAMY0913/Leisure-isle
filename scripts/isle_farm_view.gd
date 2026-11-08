class_name IsleFarmView
extends Node3D
## P3 —— 九格农田的作物视觉协调器。
##
## 职责边界（硬约束）：
##   - 只读 IsleFarm 的权威状态（crop_id_at / stage_id / is_regrow_cycle），绝不反向写入。
##   - 不持有计时器、不推导成熟时间、不改动库存；阶段完全来自 IsleFarm。
##   - 同作物同阶段共享 IsleCropModels 的 Mesh 与材质；只在"显示内容真的变了"时换 mesh。
##
## 九格锚点来自 world.gd 的农田 facts：
##   facts["beds"]["bed_top_y"] 为九格共用的土面高度（米），
##   facts["slots"][k]["world"] 为格心世界 XZ（Vector2），
##   整块苗床在世界系里按 IsleMath.HOUSE_YAW 旋转。

const MODELS := preload("res://scripts/isle_crop_models.gd")
const M := preload("res://scripts/isle_math.gd")

const SLOT_COUNT := 9

var _farm: Object = null
var _bed_top_y := 0.0
var _anchors: Array[Node3D] = []
var _views: Array[MeshInstance3D] = []
var _keys: Array[String] = []
var _crops: Array[String] = []
var _stages: Array[String] = []
var _setup_done := false
var _sync_count := 0
var _change_count := 0


func is_ready() -> bool:
	return _setup_done


## 绑定农田数据并就地搭好九个锚点。front_yard 传 world.gd 产出的 facts。
## 返回 false 表示 facts 不完整（此时不建立任何节点，调用方可直接跳过）。
func setup(farm: Object, front_yard: Dictionary) -> bool:
	if _setup_done:
		return true
	if farm == null:
		return false
	var beds: Dictionary = front_yard.get("beds", {})
	if beds.is_empty():
		return false
	var rows: Array = front_yard.get("slots", [])
	if rows.size() < SLOT_COUNT:
		return false
	_bed_top_y = float(beds.get("bed_top_y", 0.0))
	var by_index := {}
	for row in rows:
		var idx := int((row as Dictionary).get("index", -1))
		if idx >= 0 and idx < SLOT_COUNT:
			by_index[idx] = row
	for k in range(SLOT_COUNT):
		if not by_index.has(k):
			return false
	_anchors.resize(SLOT_COUNT)
	_views.resize(SLOT_COUNT)
	_keys.resize(SLOT_COUNT)
	_crops.resize(SLOT_COUNT)
	_stages.resize(SLOT_COUNT)
	for k in range(SLOT_COUNT):
		_keys[k] = ""
		_crops[k] = ""
		_stages[k] = ""
		var row: Dictionary = by_index[k]
		var w: Vector2 = row.get("world", Vector2.ZERO)
		var anchor := Node3D.new()
		anchor.name = "Slot%d" % k
		add_child(anchor)
		# 格心：世界 XZ + 共用土面高度；朝向与苗床一致（只影响横向铺展方向）。
		anchor.global_position = Vector3(w.x, _bed_top_y, w.y)
		anchor.rotation = Vector3(0.0, M.HOUSE_YAW, 0.0)
		var view := MeshInstance3D.new()
		view.name = "CropModel"
		view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		view.visible = false
		anchor.add_child(view)
		_anchors[k] = anchor
		_views[k] = view
	_farm = farm
	_setup_done = true
	sync()
	return true


## 按当前权威状态刷新九格显示；返回本次真正换了外观的格数。
## 幂等：状态没变时不会重建 mesh，也不会触碰材质。
func sync() -> int:
	if not _setup_done or _farm == null:
		return 0
	var changed := 0
	for k in range(SLOT_COUNT):
		var crop := String(_farm.crop_id_at(k))
		var stage := ""
		if not crop.is_empty():
			var raw_stage := String(_farm.stage_id(k))
			if raw_stage.is_empty():
				# 数据层暂时给不出阶段（异常存档/时钟未就绪）：不显示模型，也不猜一个阶段。
				crop = ""
			else:
				stage = MODELS.display_stage(raw_stage, bool(_farm.is_regrow_cycle(k)))
		var key := "" if crop.is_empty() else crop + "|" + stage
		if key == _keys[k]:
			continue
		_keys[k] = key
		_crops[k] = crop
		_stages[k] = stage
		changed += 1
		var view := _views[k]
		if key.is_empty():
			view.mesh = null
			view.visible = false
			view.set_meta("crop_id", "")
			view.set_meta("stage_id", "")
		else:
			view.mesh = MODELS.mesh_for(crop, stage)
			view.material_override = MODELS.material()
			view.visible = true
			view.set_meta("crop_id", crop)
			view.set_meta("stage_id", stage)
	_change_count += changed
	_sync_count += 1
	return changed


## 丢弃显示缓存，强制下一次 sync() 重建（存档恢复/场景重建后用）。
func invalidate() -> void:
	for k in range(_keys.size()):
		_keys[k] = "#invalid"


# ============================================================ 只读查询（测试用） =========
func shown_key(index: int) -> String:
	if index < 0 or index >= _keys.size():
		return ""
	return _keys[index]


func shown_crop(index: int) -> String:
	if index < 0 or index >= _crops.size():
		return ""
	return _crops[index]


func shown_stage(index: int) -> String:
	if index < 0 or index >= _stages.size():
		return ""
	return _stages[index]


func mesh_at(index: int) -> Mesh:
	if index < 0 or index >= _views.size():
		return null
	return _views[index].mesh


func visible_count() -> int:
	var n := 0
	for view in _views:
		if view.visible and view.mesh != null:
			n += 1
	return n


func anchor_world_position(index: int) -> Vector3:
	if index < 0 or index >= _anchors.size():
		return Vector3.ZERO
	return _anchors[index].global_position


func bed_top_y() -> float:
	return _bed_top_y


func stats() -> Dictionary:
	return {
		"ready": _setup_done,
		"syncs": _sync_count,
		"changes": _change_count,
		"visible": visible_count(),
	}
