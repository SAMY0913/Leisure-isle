extends SceneTree
func _init() -> void:
	var now := 17.0 * 3600.0 + 18.0 * 60.0
	var c: Dictionary = IsleAstro.compute(now)
	print("COMPUTE ", JSON.stringify(c))
	var e: Dictionary = IsleAstro.day_events(now)
	print("EVENTS ", JSON.stringify(e))
	var e2: Dictionary = IsleAstro.day_events(12.0 * 3600.0)
	print("EVENTS_NOON ", JSON.stringify(e2))
	quit()
