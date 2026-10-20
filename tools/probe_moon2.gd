extends SceneTree
func _initialize() -> void:
	for m in [60.0, 90.0, 120.0, 150.0, 180.0]:
		var a: Dictionary = IsleAstro.compute(m * 60.0)
		print("t=", int(m/60), ":", int(m)%60, " moon_alt=", snappedf(float(a["moon_alt"]), 0.01), " moon_az=", snappedf(float(a["moon_az"]), 0.01), " illum=", snappedf(float(a["moon_illum"]), 0.01), " waxing=", a["moon_waxing"], " sun_alt=", snappedf(float(a["sun_alt"]), 0.01))
	quit()
