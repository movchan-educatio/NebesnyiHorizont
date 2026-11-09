## Bottom-of-screen stick visualiser.  It reuses the drone's own OSD widget
## (HUDStickInput.tscn) so every level shows the exact same square stick boxes:
## two divided squares with a round dot that follows each stick
## (left = throttle / yaw, right = pitch / roll).
class_name StickOverlay
extends Control


const STICK_SCENE := preload("res://HUD/HUDStickInput.tscn")
## The widget is authored at 128x128 with a 50 px dot travel from the centre.
const WIDGET_SIZE := 128.0
## Distance from the bottom of the screen to the centre of the boxes.
@export var bottom_margin := 34.0
@export var left_screen_ratio := 0.43
@export var right_screen_ratio := 0.57
## The stock widget is 128 px; 0.68 keeps the full 100% travel readable while
## taking noticeably less of the FPV image.
@export var widget_scale := 0.68
## Kept for compatibility with older call sites.  The stock HUD widget has no
## captions, so this flag does not draw anything.
@export var show_labels := false

## x = right, y = up (screen space is handled internally).
var left_stick := Vector2.ZERO
var right_stick := Vector2.ZERO
var left_label := "ГАЗ / РИСКАННЯ"
var right_label := "ТАНГАЖ / КРЕН"

var _left_widget: Control = null
var _right_widget: Control = null
var _left_cap: Label = null
var _right_cap: Label = null
var _tutorial_focus := "none"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_left_widget = _make_widget("HUDStickLeft")
	_right_widget = _make_widget("HUDStickRight")
	_left_cap = _make_caption("ЛІВИЙ СТІК")
	_right_cap = _make_caption("ПРАВИЙ СТІК")
	_layout()
	resized.connect(_layout)
	if not get_viewport().size_changed.is_connected(_layout):
		get_viewport().size_changed.connect(_layout)
	_apply_sticks()


func _make_caption(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 2)
	l.visible = false
	add_child(l)
	return l


## Tutorial-only focus: "left", "right", "both" or "none".  The focused stick
## frame is tinted and captioned so a beginner can see which stick the current
## lesson is talking about.
func set_tutorial_focus(mode: String) -> void:
	_tutorial_focus = mode
	var show := mode != "none"
	if _left_cap != null:
		_left_cap.visible = show
		_left_cap.text = "ЛІВИЙ СТІК · ГАЗ / РИСКАННЯ"
		_left_cap.add_theme_color_override("font_color",
				Color(1.0, 0.82, 0.35) if (mode == "left" or mode == "both")
				else Color(0.55, 0.62, 0.55))
	if _right_cap != null:
		_right_cap.visible = show
		_right_cap.text = "ПРАВИЙ СТІК · ТАНГАЖ / КРЕН"
		_right_cap.add_theme_color_override("font_color",
				Color(1.0, 0.82, 0.35) if (mode == "right" or mode == "both")
				else Color(0.55, 0.62, 0.55))
	_tint_widget(_left_widget, mode == "left" or mode == "both", show)
	_tint_widget(_right_widget, mode == "right" or mode == "both", show)
	_layout()


func _tint_widget(widget: Control, focused: bool, tutorial: bool) -> void:
	if widget == null:
		return
	var frame := widget.get_node_or_null("Frame") as CanvasItem
	if frame == null:
		return
	if not tutorial:
		frame.self_modulate = Color.WHITE
	elif focused:
		frame.self_modulate = Color(1.0, 0.86, 0.35)
	else:
		frame.self_modulate = Color(0.55, 0.60, 0.55)


## Feed the two sticks every frame. Values are in the range -1..1.
func set_sticks(left: Vector2, right: Vector2) -> void:
	left_stick = left
	right_stick = right
	_apply_sticks()


## Change the captions (kept so callers do not break; this style has none).
func set_labels(left: String, right: String) -> void:
	left_label = left
	right_label = right


func _make_widget(node_name: String) -> Control:
	var widget := STICK_SCENE.instantiate() as Control
	widget.name = node_name
	add_child(widget)
	widget.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	widget.custom_minimum_size = Vector2(WIDGET_SIZE, WIDGET_SIZE)
	widget.size = Vector2(WIDGET_SIZE, WIDGET_SIZE)
	widget.pivot_offset = Vector2(WIDGET_SIZE * 0.5, WIDGET_SIZE * 0.5)
	widget.scale = Vector2(widget_scale, widget_scale)
	widget.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return widget


func _layout() -> void:
	var vp := get_viewport_rect().size
	if vp.x < 1.0 or vp.y < 1.0:
		vp = size
	var half := WIDGET_SIZE * 0.5
	var visual_half := half * widget_scale
	var center_y := vp.y - bottom_margin - visual_half
	if _left_widget != null:
		_left_widget.position = Vector2(vp.x * left_screen_ratio - half,
				center_y - half)
	if _right_widget != null:
		_right_widget.position = Vector2(vp.x * right_screen_ratio - half,
				center_y - half)
	if _left_cap != null:
		_left_cap.position = Vector2(vp.x * left_screen_ratio - 105.0,
				center_y + visual_half + 2.0)
		_left_cap.size = Vector2(210, 14)
	if _right_cap != null:
		_right_cap.position = Vector2(vp.x * right_screen_ratio - 105.0,
				center_y + visual_half + 2.0)
		_right_cap.size = Vector2(210, 14)


func _apply_sticks() -> void:
	# HUDStickInput treats its input as a screen-space offset (y grows down),
	# while the public API here is y-up like a real stick.
	if _left_widget != null and _left_widget.has_method("update_stick_input"):
		_left_widget.call("update_stick_input", _to_screen(left_stick))
	if _right_widget != null and _right_widget.has_method("update_stick_input"):
		_right_widget.call("update_stick_input", _to_screen(right_stick))


func _to_screen(stick: Vector2) -> Vector2:
	return Vector2(clampf(stick.x, -1.0, 1.0), -clampf(stick.y, -1.0, 1.0))
