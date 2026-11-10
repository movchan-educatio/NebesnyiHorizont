extends Control


@onready var frame: TextureRect = $Frame
@onready var stick: TextureRect = $StickPosition


func _ready() -> void:
	if stick != null:
		stick.set_anchors_preset(Control.PRESET_TOP_LEFT)
		stick.position = 0.5 * (size - stick.size)
	# Name the two physical axis pairs so the pilot can see which stick is
	# moving during a flight, not just a dot on an unlabelled frame.
	var label := Label.new()
	label.name = "AxisLabel"
	var left_pair := name.to_lower().contains("left")
	if MenuUI.is_english():
		label.text = "THR / YAW" if left_pair else "PITCH / ROLL"
	else:
		label.text = "ГАЗ / РИСК" if left_pair else "ТАНГАЖ / КРЕН"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.82, 1.0, 0.86, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	label.add_theme_constant_override("outline_size", 3)
	label.position = Vector2(-24, -30)
	label.size = Vector2(208, 22)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)


func update_stick_input(input: Vector2) -> void:
	if stick == null:
		return
	var center: Vector2 = size * 0.5
	var half_stick: Vector2 = stick.size * 0.5
	var travel: float = 48.0
	stick.position = center - half_stick + Vector2(clampf(input.x, -1.0, 1.0) * travel, clampf(input.y, -1.0, 1.0) * travel)
