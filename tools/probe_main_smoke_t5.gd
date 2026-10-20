extends SceneTree

## 临时诊断：headless 实例化 isle.tscn 主场景，检查炊烟节点在真实集成下的发射状态。

func _initialize() -> void:
	await process_frame
	var ps: PackedScene = load("res://isle.tscn") as PackedScene
	if ps == null:
		print("[DIAG] isle.tscn 加载失败")
		quit(1)
		return
	var main: Node = ps.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	await process_frame
	var fx: Variant = main.get("_fx")
	print("[DIAG] main=", main.name, " class=", main.get_class(), " _fx=", fx is Dictionary)
	if not (fx is Dictionary):
		quit(1)
		return
	var smoke: Variant = (fx as Dictionary).get("smoke", null)
	print("[DIAG] smoke=", smoke is Dictionary)
	if not (smoke is Dictionary):
		quit(1)
		return
	var ctl: Variant = (smoke as Dictionary).get("ctl", null)
	var p: Variant = (smoke as Dictionary).get("node", null)
	print("[DIAG] ctl=", ctl, " node=", p)
	if ctl == null or p == null:
		quit(1)
		return
	var pp := p as GPUParticles3D
	print("[DIAG] particles emitting=", pp.emitting, " amount_ratio=", pp.amount_ratio, " visible=", pp.visible, " in_tree=", pp.is_visible_in_tree(), " pos=", pp.global_position)
	print("[DIAG] debug=", ctl.smoke_debug())
	var sim0: Variant = main.get("_sim_seconds")
	print("[DIAG] _sim_seconds=", sim0)
	# 设到 12:10（窗口内）
	main.call("_set_time_of_day", 12.0 * 60.0 + 10.0)
	for i in range(8):
		await process_frame
	print("[DIAG] after set 12:10 _sim_seconds=", main.get("_sim_seconds"))
	print("[DIAG] after 12:10 emitting=", pp.emitting, " ratio=", pp.amount_ratio)
	print("[DIAG] after 12:10 debug=", ctl.smoke_debug())
	# 设到 15:00（窗口外）
	main.call("_set_time_of_day", 15.0 * 60.0)
	for i in range(8):
		await process_frame
	print("[DIAG] after 15:00 emitting=", pp.emitting, " ratio=", pp.amount_ratio)
	print("[DIAG] after 15:00 debug=", ctl.smoke_debug())
	main.queue_free()
	await process_frame
	quit(0)
