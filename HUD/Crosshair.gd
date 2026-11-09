## Dashed crosshair reticle with a centre ring — the white "camera alignment"
## style marker used in simulators and in-camera FPV overlays. Drop it on any
## Control as a full-rect child and it draws itself centred.
class_name Crosshair
extends Control


@export var color := Color(1, 1, 1, 0.88)
@export var thickness := 2.5
@export var dash_length := 14.0
@export var gap_length := 11.0
@export var arm_horizontal := 250.0
@export var arm_vertical := 150.0
## Distance from the centre before the dashes begin.
@export var centre_gap := 30.0
@export var ring_radius := 15.0
@export var ring_width := 2.5
@export var dot_radius := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	resized.connect(queue_redraw)
	if not get_viewport().size_changed.is_connected(queue_redraw):
		get_viewport().size_changed.connect(queue_redraw)
	call_deferred("queue_redraw")


func _draw() -> void:
	# Work off the viewport rect so it is correct both inside ordinary Control
	# trees and when placed directly on a CanvasLayer.
	var rect := get_viewport_rect().size
	if rect.x < 1.0 or rect.y < 1.0:
		rect = size
	var centre := rect * 0.5
	_dashed(centre, Vector2.RIGHT, arm_horizontal)
	_dashed(centre, Vector2.LEFT, arm_horizontal)
	_dashed(centre, Vector2.DOWN, arm_vertical)
	_dashed(centre, Vector2.UP, arm_vertical)
	if ring_radius > 0.0:
		draw_arc(centre, ring_radius, 0.0, TAU, 48, color, ring_width, true)
	if dot_radius > 0.0:
		draw_circle(centre, dot_radius, color)


func _dashed(centre: Vector2, dir: Vector2, length: float) -> void:
	var pos := centre_gap + ring_radius
	while pos < length:
		var a := centre + dir * pos
		var b := centre + dir * minf(pos + dash_length, length)
		draw_line(a, b, color, thickness, true)
		pos += dash_length + gap_length
