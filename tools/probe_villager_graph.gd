extends SceneTree
## P7-V4: build the villager walk graph + spots from the live cottage and validate it.
## Prints [VGRAPH] JSON: issues, per-spot approach points, representative paths.
## Run: Godot_v4.7.2-stable_win64_console.exe --headless --path PROJ --script res://tools/probe_villager_graph.gd

const S := preload("res://scripts/isle_villager_spots.gd")
const W := preload("res://scripts/world.gd")

var _main: Node = null

func _initialize() -> void:
	await process_frame
	var packed: PackedScene = load("res://isle.tscn") as PackedScene
	if packed == null:
		print("[VGRAPH] FAIL cannot load isle.tscn")
		quit(1)
		return
	_main = packed.instantiate()
	get_root().add_child(_main)
	await process_frame
	await process_frame
	var menu = _main.get("_menu")
	if menu != null and menu.has_method("instant_finish"):
		menu.call("instant_finish")
	_main.set("_mode", 1)
	_main.set("_time_source", "sim")
	_main.set("_realtime", false)
	_main.set("_started", true)
	_main.set("_paused", true)
	_main.set("_auto_orbit", false)
	_main.set("_blending", "")
	_main.set("_sim_seconds", 0.0)
	await process_frame
	if _main.has_method("_set_time_of_day"):
		_main.call("_set_time_of_day", 740.0)
	await process_frame
	var cottage: Dictionary = _main.get("_cottage")
	var graph: Dictionary = S.build(cottage)
	var issues: Array = S.validate(graph)
	var nodes: Dictionary = graph["nodes"]
	var spots: Dictionary = graph["spots"]
	var adj: Dictionary = graph["adj"]
	var out := {}
	out["node_count"] = nodes.size()
	out["spot_count"] = spots.size()
	out["issues"] = issues
	var modes := {}
	for id in nodes.keys():
		var m := String(nodes[id]["mode"])
		modes[m] = int(modes.get(m, 0)) + 1
	out["modes"] = modes
	# spots: id -> kind/name/approach world + nearest node + distance to node
	var spot_rows := []
	for sid in spots.keys():
		var sp: Dictionary = spots[sid]
		var ap: Vector3 = sp["approach"]
		var nn := S.nearest_node(graph, ap)
		var np: Vector3 = nodes[nn]["pos"]
		spot_rows.append({
			"id": sid,
			"kind": sp["kind"],
			"name": sp["name"],
			"region": sp["region"],
			"approach_node": sp["approach_node"],
			"approach": [snappedf(ap.x, 0.0001), snappedf(ap.y, 0.0001), snappedf(ap.z, 0.0001)],
			"anchor": [snappedf(float(sp["anchor"].x), 0.0001), snappedf(float(sp["anchor"].y), 0.0001), snappedf(float(sp["anchor"].z), 0.0001)],
			"nearest": nn,
			"nearest_dist": snappedf(Vector2(ap.x - np.x, ap.z - np.z).length(), 0.001),
		})
	spot_rows.sort_custom(func(a, b): return String(a["id"]) < String(b["id"]))
	out["spots"] = spot_rows
	# representative paths from spawn node (hall) to every spot approach node
	var spawn := "hall"
	var path_rows := []
	for sid in spots.keys():
		var sp2: Dictionary = spots[sid]
		var target := String(sp2["approach_node"])
		var p := S.find_path(graph, spawn, target)
		var total := 0.0
		for i in range(1, p.size()):
			total += Vector2(nodes[p[i]]["pos"].x - nodes[p[i - 1]]["pos"].x, nodes[p[i]]["pos"].z - nodes[p[i - 1]]["pos"].z).length()
		path_rows.append({"spot": sid, "target_node": target, "path_len": p.size(), "dist": snappedf(total, 0.01), "path": Array(p)})
	path_rows.sort_custom(func(a, b): return String(a["spot"]) < String(b["spot"]))
	out["paths"] = path_rows
	# outdoor edge slopes (terrain-only edges)
	var slope_rows := []
	for a in adj.keys():
		for b in (adj[a] as PackedStringArray):
			if String(a) > String(b):
				continue
			var na: Dictionary = nodes[a]
			var nb: Dictionary = nodes[b]
			if String(na["mode"]) != "terrain" and String(na["mode"]) != "terrain_local":
				continue
			if String(nb["mode"]) != "terrain" and String(nb["mode"]) != "terrain_local":
				continue
			var pa: Vector3 = na["pos"]
			var pb: Vector3 = nb["pos"]
			var d := Vector2(pb.x - pa.x, pb.z - pa.z).length()
			if d < 0.01:
				continue
			var maxs := 0.0
			var n := maxi(2, int(ceil(d / 0.15)))
			var prev_y := W.surface_y(pa.x, pa.z)
			for i in range(1, n + 1):
				var t := float(i) / float(n)
				var x := lerpf(pa.x, pb.x, t)
				var z := lerpf(pa.z, pb.z, t)
				var y := W.surface_y(x, z)
				var step := absf(y - prev_y) / (d / float(n))
				maxs = maxf(maxs, step)
				prev_y = y
			slope_rows.append({"edge": "%s-%s" % [a, b], "len": snappedf(d, 0.01), "max_slope": snappedf(maxs, 0.01), "dy": snappedf(pb.y - pa.y, 0.01)})
	slope_rows.sort_custom(func(a, b): return String(a["edge"]) < String(b["edge"]))
	out["outdoor_slopes"] = slope_rows
	print("[VGRAPH] " + JSON.stringify(out))
	print("RESULT nodes=%d spots=%d issues=%d" % [nodes.size(), spots.size(), issues.size()])
	quit(0)
