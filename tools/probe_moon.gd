extends SceneTree
func _init() -> void:
	for h in range(0, 25):
		var a: Dictionary = IsleAstro.compute(float(h) * 3600.0)
		print("h=", h, " sun_alt=", snappedf(float(a["sun_alt"]), 0.1), " moon_alt=", snappedf(float(a["moon_alt"]), 0.1), " moon_az=", snappedf(float(a["moon_az"]), 0.1), " illum=", snappedf(float(a["moon_illum"]), 0.01))
	quit()
