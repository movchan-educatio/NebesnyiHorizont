extends CanvasLayer

## Touch controls for phones/tablets (iOS, Android) and for desktop QA.
##
## Left stick: vertical = throttle (holds on release), horizontal = yaw
## (self-centres).  Right stick: pitch/roll (self-centres).  The ARM button
## remains in the level HUD; this overlay only supplies the flight axes.
##
## The overlay is enabled by BigLevel and disabled when the level is left.
## On desktop it stays off unless TOUCH_CONTROLS=1 is set, which also makes
## the mouse behave like one finger so the layout can be tested on Windows.

signal mode_changed(using_touch: bool)

const NO_TOUCH := -2
const MOUSE_TOUCH := -1
const DEADZONE := 0.06
const MARGIN := 40.0
const BOTTOM_MARGIN := 48.0

var enabled := false
var touch_mode := false
var throttle := 0.0
var yaw := 0.0
var roll := 0.0
var pitch := 0.0

var _root: Control = null
var _drawer: Control = null
var _mode_button: Button = null
var _arm_button: Button = null
var _left_center := Vector2.ZERO
var _right_center := Vector2.ZERO
var _radius := 100.0
var _left_knob := Vector2.ZERO
var _right_knob := Vector2.ZERO
var _left_index := NO_TOUCH
var _right_index := NO_TOUCH
var _mouse_down := false
var _owner_id := 0


func _ready() -> void:
	layer = 30
	_root = Control.new()
	_root.name = "TouchRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_drawer = Control.new()
	_drawer.name = "TouchDrawer"
	_drawer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drawer.draw.connect(_on_drawer_draw)
	_root.add_child(_drawer)

	_mode_button = Button.new()
	_mode_button.name = "TouchModeButton"
	_mode_button.focus_mode = Control.FOCUS_NONE
	_mode_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_mode_button.add_theme_font_size_override("font_size", 16)
	_mode_button.add_theme_color_override("font_color", Color(0.9, 0.96, 1.0))
	_mode_button.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_mode_button.add_theme_constant_override("outline_size", 3)
	_mode_button.pressed.connect(_on_mode_pressed)
	_root.add_child(_mode_button)

	_arm_button = Button.new()
	_arm_button.name = "TouchArmButton"
	_arm_button.text = "ARM"
	_arm_button.focus_mode = Control.FOCUS_NONE
	_arm_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_arm_button.add_theme_font_size_override("font_size", 24)
	_arm_button.add_theme_color_override("font_color", Color(1.0, 0.94, 0.88))
	_arm_button.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_arm_button.add_theme_constant_override("outline_size", 4)
	_arm_button.pressed.connect(_on_arm_pressed)
	_root.add_child(_arm_button)

	visible = false
	set_process_input(false)
	get_viewport().size_changed.connect(_layout)
	_layout()
	_update_mode_button()


func begin(owner_id: int = 0) -> void:
	## Called by the level when its HUD is ready.  The owner id prevents an
	## outgoing level's _exit_tree() from switching off the new level's sticks.
	_owner_id = owner_id
	if not _should_enable():
		set_enabled(false)
		return
	set_enabled(true)


func end(owner_id: int = 0) -> void:
	if owner_id != 0 and owner_id != _owner_id:
		return
	_owner_id = 0
	set_enabled(false)


func _should_enable() -> bool:
	return OS.get_name() == "iOS" or OS.has_environment("TOUCH_CONTROLS") \
			or DisplayServer.is_touchscreen_available()


func set_enabled(value: bool) -> void:
	enabled = value
	visible = value
	set_process_input(value)
	if value:
		_layout()
		# Default to touch only when there is no live ELRS stream; a pilot
		# with the radio already connected keeps the radio as primary and can
		# switch with the MODE button.
		var elrs := get_node_or_null("/root/ElrsWifiInput")
		var stream_valid: bool = elrs != null and bool(elrs.get("valid"))
		touch_mode = not stream_valid
		_reset_sticks()
		_update_mode_button()
	else:
		touch_mode = false
		_reset_sticks()
	mode_changed.emit(touch_mode)


func _layout() -> void:
	if _root == null or _drawer == null:
		return
	var vs := get_viewport().get_visible_rect().size
	if vs.x < 2.0 or vs.y < 2.0:
		return
	_root.position = Vector2.ZERO
	_root.size = vs
	_drawer.position = Vector2.ZERO
	_drawer.size = vs
	_radius = clampf(minf(vs.x, vs.y) * 0.135, 62.0, 132.0)
	var bottom := vs.y - maxf(BOTTOM_MARGIN, MARGIN)
	_left_center = Vector2(maxf(MARGIN + _radius, _radius + 12.0),
			bottom - _radius)
	_right_center = Vector2(vs.x - maxf(MARGIN + _radius, _radius + 12.0),
			bottom - _radius)
	var bw := 176.0
	_mode_button.position = Vector2(vs.x * 0.5 - bw * 0.5, 144.0)
	_mode_button.size = Vector2(bw, 38.0)
	_arm_button.position = Vector2(vs.x * 0.5 - 86.0, vs.y - 198.0)
	_arm_button.size = Vector2(172.0, 64.0)
	_apply_button_style()
	_drawer.queue_redraw()


func _apply_button_style() -> void:
	if _mode_button == null:
		return
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.04, 0.07, 0.10, 0.72)
	normal.border_color = Color(0.55, 0.82, 1.0, 0.5)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(8)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.12, 0.30, 0.44, 0.85)
	_mode_button.add_theme_stylebox_override("normal", normal)
	_mode_button.add_theme_stylebox_override("hover", normal)
	_mode_button.add_theme_stylebox_override("pressed", pressed)
	if _arm_button == null:
		return
	var arm_normal := StyleBoxFlat.new()
	arm_normal.bg_color = Color(0.10, 0.04, 0.03, 0.72)
	arm_normal.border_color = Color(1.0, 0.55, 0.32, 0.62)
	arm_normal.set_border_width_all(1)
	arm_normal.set_corner_radius_all(8)
	var arm_pressed := arm_normal.duplicate() as StyleBoxFlat
	arm_pressed.bg_color = Color(0.38, 0.10, 0.06, 0.88)
	_arm_button.add_theme_stylebox_override("normal", arm_normal)
	_arm_button.add_theme_stylebox_override("hover", arm_normal)
	_arm_button.add_theme_stylebox_override("pressed", arm_pressed)


func _update_mode_button() -> void:
	if _mode_button == null:
		return
	_mode_button.text = "MODE: TOUCH" if touch_mode else "MODE: RADIO"


func _on_mode_pressed() -> void:
	if touch_mode:
		touch_mode = false
		_reset_sticks()
	else:
		touch_mode = true
		# Start with the throttle at zero even if the radio was at power.
		throttle = 0.0
		yaw = 0.0
		roll = 0.0
		pitch = 0.0
		_left_knob = Vector2(0.0, _radius)
		_right_knob = Vector2.ZERO
	_update_mode_button()
	_drawer.queue_redraw()
	mode_changed.emit(touch_mode)


func _on_arm_pressed() -> void:
	# Same synthetic action path as the keyboard/gamepad arm switch.
	var event := InputEventAction.new()
	event.action = "toggle_arm"
	event.pressed = true
	event.strength = 1.0
	Input.parse_input_event(event)


func _input(event: InputEvent) -> void:
	if not enabled or not touch_mode or get_tree().paused:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if _handle_touch(touch.index, touch.position, touch.pressed):
			get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if _drag_touch(drag.index, drag.position):
			get_viewport().set_input_as_handled()
		return
	# Desktop QA: one mouse pointer behaves like one finger.
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		_mouse_down = mb.pressed
		if _handle_touch(MOUSE_TOUCH, mb.position, mb.pressed):
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and _mouse_down:
		var mm := event as InputEventMouseMotion
		if _drag_touch(MOUSE_TOUCH, mm.position):
			get_viewport().set_input_as_handled()


func _handle_touch(index: int, pos: Vector2, pressed: bool) -> bool:
	if not pressed:
		var released := false
		if index == _left_index:
			_release_stick(true)
			released = true
		if index == _right_index:
			_release_stick(false)
			released = true
		return released
	if index == _left_index:
		_update_stick(true, pos)
		return true
	if index == _right_index:
		_update_stick(false, pos)
		return true
	if _left_index == NO_TOUCH and pos.distance_to(_left_center) <= _radius * 1.35:
		_left_index = index
		_update_stick(true, pos)
		return true
	if _right_index == NO_TOUCH and pos.distance_to(_right_center) <= _radius * 1.35:
		_right_index = index
		_update_stick(false, pos)
		return true
	return false


func _drag_touch(index: int, pos: Vector2) -> bool:
	if index == _left_index:
		_update_stick(true, pos)
		return true
	if index == _right_index:
		_update_stick(false, pos)
		return true
	return false


func _update_stick(left: bool, pos: Vector2) -> void:
	var center := _left_center if left else _right_center
	var offset := (pos - center).limit_length(_radius)
	if left:
		_left_knob = offset
		throttle = clampf(0.5 - offset.y / (2.0 * _radius), 0.0, 1.0)
		var x := offset.x / _radius
		yaw = 0.0 if absf(x) < DEADZONE else clampf(x, -1.0, 1.0)
	else:
		_right_knob = offset
		var x := offset.x / _radius
		var y := offset.y / _radius
		roll = 0.0 if absf(x) < DEADZONE else clampf(x, -1.0, 1.0)
		pitch = 0.0 if absf(y) < DEADZONE else clampf(y, -1.0, 1.0)
	_drawer.queue_redraw()


func _release_stick(left: bool) -> void:
	if left:
		_left_index = NO_TOUCH
		# The throttle stays where it was released; yaw self-centres.
		_left_knob.x = 0.0
		yaw = 0.0
	else:
		_right_index = NO_TOUCH
		_right_knob = Vector2.ZERO
		roll = 0.0
		pitch = 0.0
	_drawer.queue_redraw()


func _reset_sticks() -> void:
	_left_index = NO_TOUCH
	_right_index = NO_TOUCH
	_mouse_down = false
	# Throttle 0 is the bottom of the left stick, not its centre.
	_left_knob = Vector2(0.0, _radius)
	_right_knob = Vector2.ZERO
	throttle = 0.0
	yaw = 0.0
	roll = 0.0
	pitch = 0.0
	if _drawer != null:
		_drawer.queue_redraw()


func _on_drawer_draw() -> void:
	# In radio mode the existing HUD stick visualiser is shown instead; the
	# touch overlay only keeps its MODE button visible.
	if not enabled or _drawer == null or not touch_mode:
		return
	_draw_stick(_drawer, _left_center, _left_knob, "THR / YAW", 1.0)
	_draw_stick(_drawer, _right_center, _right_knob, "PITCH / ROLL", 1.0)


func _draw_stick(c: Control, center: Vector2, knob: Vector2,
		label: String, alpha: float) -> void:
	var base := Color(0.03, 0.06, 0.09, 0.38 * alpha)
	var rim := Color(0.70, 0.86, 1.0, 0.45 * alpha)
	var cross := Color(0.70, 0.86, 1.0, 0.20 * alpha)
	var knob_col := Color(0.80, 0.93, 1.0, 0.42 * alpha)
	c.draw_circle(center, _radius, base)
	c.draw_arc(center, _radius, 0.0, TAU, 64, rim, 2.0, true)
	c.draw_line(center - Vector2(_radius * 0.78, 0.0),
			center + Vector2(_radius * 0.78, 0.0), cross, 1.0, true)
	c.draw_line(center - Vector2(0.0, _radius * 0.78),
			center + Vector2(0.0, _radius * 0.78), cross, 1.0, true)
	var knob_pos := center + knob
	var knob_r := _radius * 0.29
	c.draw_circle(knob_pos, knob_r, knob_col)
	c.draw_arc(knob_pos, knob_r, 0.0, TAU, 32, rim, 1.5, true)
	var font := ThemeDB.fallback_font
	var font_size := int(clampf(_radius * 0.15, 12.0, 18.0))
	c.draw_string(font, center + Vector2(-_radius, -_radius - 12.0),
			label, HORIZONTAL_ALIGNMENT_CENTER, _radius * 2.0, font_size,
			Color(0.85, 0.94, 1.0, 0.75 * alpha))


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT \
			or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		# Do not keep a throttle value when the phone is backgrounded.
		_reset_sticks()
