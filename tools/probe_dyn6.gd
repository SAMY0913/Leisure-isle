extends SceneTree
func _init() -> void:
	var s: Script = load("res://scripts/fx.gd") as Script
	var names: Array = []
	for m in s.get_script_method_list():
		names.append(String(m.get("name", "")))
	print("[DYN] static_count=", names.size(), " has_gull=", names.has("_gull_primary_count"), " has_smoke=", names.has("smoke"))
	var r: Variant = s.call("_gull_primary_count")
	print("[DYN] call static result=", r)
	var n: Variant = s.get_script_constant_map().get("Splash", null)
	print("[DYN] const_map Splash=", n != null, " key_count=", s.get_script_constant_map().size())
	quit(0)
