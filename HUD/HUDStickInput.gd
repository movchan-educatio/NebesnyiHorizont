extends Control


@onready var frame: TextureRect = $Frame
@onready var stick: TextureRect = $StickPosition


func _ready() -> void:
	if stick != null:
		stick.set_anchors_preset(Control.PRESET_TOP_LEFT)
		stick.position = 0.5 * (size - stick.size)
	# Clean flight HUD: the small axis-pair captions above the stick frames were
	# visual noise on the phone.  The frames and their dots already show which
	# stick is moving, so no caption nodes are created.


func update_stick_input(input: Vector2) -> void:
	if stick == null:
		return
	var center: Vector2 = size * 0.5
	var half_stick: Vector2 = stick.size * 0.5
	var travel: float = 48.0
	stick.position = center - half_stick + Vector2(clampf(input.x, -1.0, 1.0) * travel, clampf(input.y, -1.0, 1.0) * travel)
