extends Control
class_name HUDLadder


@onready var _pivot := $LadderPivot

var center_pos := Vector2.ZERO

var pitch_marker_scene := preload("res://HUD/HUDPitchMarker.tscn")
var pitch_markers := []
var pitch_marker_spacing := 20


func _ready() -> void:
	_pivot.pivot_offset = _pivot.size / 2
	center_pos = size / 2 - _pivot.size / 2
	
	for i in range(-85, 90, 5):
		if i == 0:
			continue
		var marker := pitch_marker_scene.instantiate()
		_pivot.add_child(marker)
		pitch_markers.append(marker)
		marker.update_marker(i)
		marker.position = Vector2(_pivot.size.x / 2, -i * pitch_marker_spacing)

func update_ladder(pitch: float, roll: float) -> void:
	var span: float = size.x / maxf(absf(cos(roll)), 0.001)
	if span > size.length():
		span = size.y / maxf(absf(sin(roll)), 0.001)
	_pivot.size.x = span - 10
	_pivot.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	center_pos = size / 2.0 - _pivot.size / 2.0
	_pivot.position = center_pos + rad_to_deg(pitch * pitch_marker_spacing) * Vector2(-sin(roll), cos(roll))
	_pivot.pivot_offset = _pivot.size / 2.0
	_pivot.rotation = rad_to_deg(roll)
