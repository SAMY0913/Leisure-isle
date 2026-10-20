extends SceneTree
func _initialize() -> void:
	var a: Array[AudioStream] = []
	a.resize(3)
	var st: AudioStream = load("res://audio/night_loop.wav") as AudioStream
	print("loaded class=", st.get_class())
	var dup: AudioStream = st.duplicate(true) as AudioStream
	print("dup class=", dup.get_class())
	a[0] = dup
	print("assign typed ok, size=", a.size(), " val=", a[0])
	var b := []
	b.resize(3)
	b[1] = dup
	print("untyped ok, val=", b[1])
	quit(0)
