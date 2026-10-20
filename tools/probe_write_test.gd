extends SceneTree
func _init() -> void:
	var targets := [
		"C:/Users/Administrator/AppData/Roaming/godot_wtest.txt",
		"C:/Users/Administrator/AppData/Local/Temp/godot_wtest.txt",
		"C:/Users/Administrator/AppData/Roaming/Godot/godot_wtest.txt",
		"C:/Users/Administrator/Documents/godot_wtest.txt",
		"D:/休闲小岛幻境/开发产物/logs/w5.txt"
	]
	for t in targets:
		var fa := FileAccess.open(t, FileAccess.WRITE)
		print("[W] ", t, " -> ", "OK" if fa != null else "NULL", " err=", FileAccess.get_open_error())
		if fa != null:
			fa.store_string("hi")
			fa.close()
	quit()
