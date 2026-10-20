extends SceneTree

func _initialize() -> void:
	var P = load("res://scripts/isle_palette.gd")
	for t in [0.0, 0.3, 0.44, 0.6, 0.75, 0.9]:
		var d: Dictionary = P.sample(t)
		var ks: Array = d.keys()
		ks.sort()
		if t == 0.44:
			print("KEYS:", ks)
		var parts: Array = []
		for k in ["lanternI", "windowI", "fireflyI", "fogNear", "fogFar", "outline", "fog", "hemiI", "sunI", "moonI", "sunColor", "hemiSky"]:
			if d.has(k):
				parts.append(str(k) + "=" + str(d[k]))
		print("t=", t, " ", ", ".join(parts))
	quit()
