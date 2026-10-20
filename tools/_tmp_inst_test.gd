extends SceneTree
func _initialize() -> void:
	var A = load("res://scripts/isle_audio.gd")
	print("script=", A, " class=", A.get_global_name())
	var host := Node.new()
	host.name = "Host"
	root.add_child(host)
	var audio = A.new()
	audio.name = "Audio"
	host.add_child(audio)
	print("before setup, loop_streams size=", audio._loop_streams.size(), " typed=", audio._loop_streams.is_typed(), " type=", audio._loop_streams.get_typed_builtin(), "/", audio._loop_streams.get_typed_class_name())
	audio.setup(host)
	print("after setup, players=", audio._loop_players.size(), " streams=", audio._loop_streams.size())
	for i in range(audio._loop_streams.size()):
		print("  stream[", i, "]=", audio._loop_streams[i])
	quit(0)
