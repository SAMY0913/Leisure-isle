extends SceneTree
const MainScene := preload("res://isle.tscn")
func _initialize() -> void:
	await process_frame
	var m = MainScene.instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	print("mats=", m._boat_fade_mats.size(), " std=", m._boat_fade_std.size(), " boat=", m._sailboat)
	var seen := 0
	for c in m._sailboat.get_children():
		var gi = c as GeometryInstance3D
		if gi == null: continue
		var mat = gi.material_override
		print("child ", c.name, " override=", mat.get_class() if mat else "null")
		if mat is ShaderMaterial:
			print("  shader=", (mat as ShaderMaterial).shader.resource_path, " hasfade=", (mat as ShaderMaterial).get_shader_parameter("fade_alpha"), " uniforms=", (mat as ShaderMaterial).shader.get_shader_uniform_list().filter(func(u): return String(u.name).contains("fade")))
			seen += 1
		if seen > 4: break
	quit(0)
