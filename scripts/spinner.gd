extends Node2D

@onready var spinner: Sprite2D = $Spinner

func _process(delta: float) -> void:
	spinner.rotation += delta * 1.5
	var pulse := 1.0 + 0.12 * sin(Time.get_ticks_msec() / 260.0)
	spinner.scale = Vector2.ONE * pulse
