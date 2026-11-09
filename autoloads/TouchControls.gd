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
var _pause_button: Button = null
var _flight_button: Button = null
var _setup_button: Button = null
var _drop_button: Button = null
var _use_button: Button = null
var _reset_button: Button = null
var _video_button: Button = null
var _setup_root: Control = null
var _setup_panel: PanelContainer = null
var _setup_timer: Timer = null
var _channel_labels: Array = []
var _arm_option: OptionButton = null
var _mode_option: OptionButton = null
var _video_option: OptionButton = null
var _invert_elrs_check: CheckBox = null
var _invert_touch_check: CheckBox = null
## Touch roll inversion (the ELRS radio has its own invert flag).
var invert_roll := false
var _left_center := Vector2.ZERO
var _right_center := Vector2.ZERO
var _radius := 100.0
var _left_knob := Vector2.ZERO
var _right_knob := Vector2.ZERO
var _left_index := NO_TOUCH
var _right_index := NO_TOUCH
var _mouse_down := false
var _owner_id := 0
## Menu preview: the calibration/controls screens show only the twin sticks,
## without the flight buttons.  Keeps the exact same stick feel as in flight.
var _preview := false


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
	_arm_button.text = "АРМ"
	_arm_button.focus_mode = Control.FOCUS_NONE
	_arm_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_arm_button.add_theme_font_size_override("font_size", 24)
	_arm_button.add_theme_color_override("font_color", Color(1.0, 0.94, 0.88))
	_arm_button.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_arm_button.add_theme_constant_override("outline_size", 4)
	_arm_button.pressed.connect(_on_arm_pressed)
	_root.add_child(_arm_button)

	_pause_button = _make_top_button("МЕНЮ", _on_pause_pressed)
	_flight_button = _make_top_button("РЕЖИМ", _on_flight_pressed)
	_setup_button = _make_top_button("НАЛАШТ.", _on_setup_pressed)
	_drop_button = _make_top_button("СКИД", _on_action_pressed.bind("deploy_payload"))
	_use_button = _make_top_button("ЗАСТ.", _on_action_pressed.bind("activate_payload"))
	_reset_button = _make_top_button("РЕСЕТ", _on_action_pressed.bind("respawn"))
	_video_button = _make_top_button("ВІДЕО", _on_action_pressed.bind("cycle_video_mode"))
	_build_setup_panel()

	visible = false
	set_process_input(false)
	get_viewport().size_changed.connect(_layout)
	_layout()
	_update_mode_button()


func begin(owner_id: int = 0) -> void:
	## Called by the level when its HUD is ready.  The owner id prevents an
	## outgoing level's _exit_tree() from switching off the new level's sticks.
	if _preview:
		set_menu_preview(false)
	_owner_id = owner_id
	if not _should_enable():
		set_enabled(false)
		return
	set_enabled(true)
	if OS.has_environment("TOUCH_SETUP_TEST"):
		call_deferred("_on_setup_pressed")


func end(owner_id: int = 0) -> void:
	if owner_id != 0 and owner_id != _owner_id:
		return
	_owner_id = 0
	set_enabled(false)


## Show the twin sticks over a menu scene (calibration / controls) without the
## flight action bar.  Safe to call on desktop QA with TOUCH_CONTROLS=1.
func is_menu_preview() -> bool:
	return _preview


func set_menu_preview(on: bool) -> void:
	if on:
		if _preview or not _should_enable():
			return
		_preview = true
		process_mode = Node.PROCESS_MODE_ALWAYS
		enabled = true
		visible = true
		set_process_input(true)
		touch_mode = true
		_layout()
		_reset_sticks()
		for b in [_pause_button, _flight_button, _setup_button, _drop_button,
				_use_button, _reset_button, _video_button, _mode_button, _arm_button]:
			if b != null:
				b.visible = false
		if _setup_root != null:
			_setup_root.visible = false
		_drawer.queue_redraw()
		return
	if not _preview:
		return
	_preview = false
	process_mode = Node.PROCESS_MODE_INHERIT
	set_enabled(false)
	for b in [_pause_button, _flight_button, _setup_button, _drop_button,
			_use_button, _reset_button, _video_button, _mode_button, _arm_button]:
		if b != null:
			b.visible = true


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
		var gs := get_node_or_null("/root/GameSettings")
		if gs != null:
			invert_roll = bool(gs.hud_config.get("touch_invert_roll", false))
		_reset_sticks()
		_update_mode_button()
	else:
		if _setup_root != null and _setup_root.visible:
			_on_setup_close()
		touch_mode = false
		_reset_sticks()
	mode_changed.emit(touch_mode)


func _make_top_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.name = "Touch" + text.capitalize().replace(" ", "") + "Button"
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", Color(0.90, 0.96, 1.0))
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	b.add_theme_constant_override("outline_size", 3)
	b.pressed.connect(cb)
	_root.add_child(b)
	return b


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
	if _preview:
		# Menu calibration: compact sticks in the bottom corners keep the
		# instruction card and action buttons clear in the middle.  The UI
		# canvas is 1080 units high on a phone (canvas_items stretch), hence
		# the larger radius than the raw physical window might suggest.
		_radius = clampf(minf(vs.x, vs.y) * 0.14, 110.0, 150.0)
		var preview_bottom := vs.y - 20.0
		_left_center = Vector2(_radius + 42.0, preview_bottom - _radius)
		_right_center = Vector2(vs.x - _radius - 42.0, preview_bottom - _radius)
	else:
		_radius = clampf(minf(vs.x, vs.y) * 0.135, 62.0, 132.0)
		var bottom := vs.y - maxf(BOTTOM_MARGIN, MARGIN)
		_left_center = Vector2(maxf(MARGIN + _radius, _radius + 12.0),
				bottom - _radius)
		_right_center = Vector2(vs.x - maxf(MARGIN + _radius, _radius + 12.0),
				bottom - _radius)
	var bar_w := 96.0 + 8.0 + 108.0 + 8.0 + 96.0 + 8.0 + 176.0
	var bar_x := (vs.x - bar_w) * 0.5
	_pause_button.position = Vector2(bar_x, 144.0)
	_pause_button.size = Vector2(96.0, 38.0)
	_flight_button.position = Vector2(bar_x + 104.0, 144.0)
	_flight_button.size = Vector2(108.0, 38.0)
	_setup_button.position = Vector2(bar_x + 220.0, 144.0)
	_setup_button.size = Vector2(96.0, 38.0)
	_mode_button.position = Vector2(bar_x + 324.0, 144.0)
	_mode_button.size = Vector2(176.0, 38.0)
	var row2: Array[Button] = [_drop_button, _use_button, _reset_button, _video_button]
	var row2_w := 4.0 * 90.0 + 3.0 * 8.0
	var row2_x := (vs.x - row2_w) * 0.5
	for i in range(row2.size()):
		row2[i].position = Vector2(row2_x + i * 98.0, 190.0)
		row2[i].size = Vector2(90.0, 34.0)
	_arm_button.position = Vector2(vs.x * 0.5 - 86.0, vs.y - 198.0)
	_arm_button.size = Vector2(172.0, 64.0)
	if _setup_root != null:
		_setup_root.position = Vector2.ZERO
		_setup_root.size = vs
	if _setup_panel != null:
		var pw := minf(vs.x - 80.0, 820.0)
		var ph := minf(vs.y - 80.0, 440.0)
		_setup_panel.size = Vector2(pw, ph)
		_setup_panel.position = (vs - Vector2(pw, ph)) * 0.5
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
	for b in [_pause_button, _flight_button, _setup_button, _drop_button, _use_button, _reset_button, _video_button]:
		if b != null:
			b.add_theme_stylebox_override("normal", normal)
			b.add_theme_stylebox_override("hover", normal)
			b.add_theme_stylebox_override("pressed", pressed)
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
	_mode_button.text = "ВВІД: СЕНСОР" if touch_mode else "ВВІД: ПУЛЬТ"


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
	_dispatch_action("toggle_arm")


func _on_pause_pressed() -> void:
	_dispatch_action("pause_menu")


func _on_flight_pressed() -> void:
	_dispatch_action("cycle_flight_modes")


func _on_action_pressed(action: String) -> void:
	_dispatch_action(action)


func _dispatch_action(action: String) -> void:
	if not InputMap.has_action(action):
		return
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	event.strength = 1.0
	Input.parse_input_event(event)
	# Also pulse the polling state so handlers using is_action_just_pressed()
	# see a clean edge; release after a short tap.
	Input.action_press(action)
	get_tree().create_timer(0.12).timeout.connect(Input.action_release.bind(action))


func _build_setup_panel() -> void:
	_setup_root = Control.new()
	_setup_root.name = "ElrsSetupRoot"
	_setup_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_setup_root.process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_root.visible = false
	_root.add_child(_setup_root)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.0, 0.0, 0.0, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_setup_root.add_child(dim)

	_setup_panel = PanelContainer.new()
	_setup_panel.name = "ElrsSetupPanel"
	_setup_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.045, 0.075, 0.105, 0.98)
	panel_style.border_color = Color(0.55, 0.82, 1.0, 0.55)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(10)
	_setup_panel.add_theme_stylebox_override("panel", panel_style)
	_setup_root.add_child(_setup_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	_setup_panel.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	margin.add_child(vb)

	var title := Label.new()
	title.text = "НАЛАШТУВАННЯ ELRS / СЕНСОРА"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.92, 0.97, 1.0))
	vb.add_child(title)

	var hint := Label.new()
	hint.text = "Тут — ARM, режими й відео. Скид, застосування БЧ, ресет та інші дії призначаються в «Налаштування → КЕРУВАННЯ» (працює з ELRS на телефоні)."
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.70, 0.82, 0.90))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(hint)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 2)
	vb.add_child(grid)
	_channel_labels.clear()
	for i in range(16):
		var label := Label.new()
		label.text = "CH%d: 16384" % (i + 1)
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", Color(0.62, 1.0, 0.76))
		label.custom_minimum_size = Vector2(150, 19)
		grid.add_child(label)
		_channel_labels.append(label)

	_arm_option = _make_mapping_row(vb, "Канал ARM", "arm",
			_elrs_channel("arm_channel", 4))
	_mode_option = _make_mapping_row(vb, "Канал режимів", "mode",
			_elrs_channel("mode_channel", 5))
	_video_option = _make_mapping_row(vb, "Канал відео", "video",
			_elrs_channel("video_channel", 6))

	var invert_box := HBoxContainer.new()
	invert_box.add_theme_constant_override("separation", 22)
	vb.add_child(invert_box)
	_invert_elrs_check = CheckBox.new()
	_invert_elrs_check.text = "Інверсія крену (ELRS)"
	_invert_elrs_check.add_theme_font_size_override("font_size", 15)
	_invert_elrs_check.add_theme_color_override("font_color", Color(0.92, 0.97, 1.0))
	_invert_elrs_check.toggled.connect(_on_invert_elrs_toggled)
	invert_box.add_child(_invert_elrs_check)
	_invert_touch_check = CheckBox.new()
	_invert_touch_check.text = "Інверсія крену (сенсор)"
	_invert_touch_check.add_theme_font_size_override("font_size", 15)
	_invert_touch_check.add_theme_color_override("font_color", Color(0.92, 0.97, 1.0))
	_invert_touch_check.toggled.connect(_on_invert_touch_toggled)
	invert_box.add_child(_invert_touch_check)

	var close := Button.new()
	close.text = "ЗАКРИТИ"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 18)
	close.custom_minimum_size = Vector2(0, 42)
	close.pressed.connect(_on_setup_close)
	vb.add_child(close)

	_setup_timer = Timer.new()
	_setup_timer.wait_time = 0.1
	_setup_timer.one_shot = false
	_setup_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_timer.timeout.connect(_update_setup_channels)
	_root.add_child(_setup_timer)


func _elrs_channel(property: String, fallback: int) -> int:
	var elrs := get_node_or_null("/root/ElrsWifiInput")
	if elrs == null:
		return fallback
	return clampi(int(elrs.get(property)), 0, 15)


func _make_mapping_row(parent: VBoxContainer, title: String, kind: String,
		selected: int) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var label := Label.new()
	label.text = title
	label.custom_minimum_size = Vector2(150, 26)
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.88, 0.94, 1.0))
	row.add_child(label)
	var option := OptionButton.new()
	option.focus_mode = Control.FOCUS_NONE
	option.add_theme_font_size_override("font_size", 15)
	option.add_theme_color_override("font_color", Color(0.90, 0.96, 1.0))
	for i in range(16):
		option.add_item("CH%d" % (i + 1))
	option.select(clampi(selected, 0, 15))
	option.custom_minimum_size = Vector2(160, 32)
	option.item_selected.connect(_on_mapping_changed.bind(kind))
	row.add_child(option)
	return option


func _on_mapping_changed(index: int, kind: String) -> void:
	var elrs := get_node_or_null("/root/ElrsWifiInput")
	if elrs == null:
		return
	match kind:
		"arm":
			elrs.set("arm_channel", index)
		"mode":
			elrs.set("mode_channel", index)
		"video":
			elrs.set("video_channel", index)
	elrs.call("save_settings")
	_refresh_setup()


func _on_invert_elrs_toggled(on: bool) -> void:
	var elrs := get_node_or_null("/root/ElrsWifiInput")
	if elrs == null:
		return
	elrs.set("invert_roll", on)
	elrs.call("save_settings")


func _on_invert_touch_toggled(on: bool) -> void:
	invert_roll = on
	var gs := get_node_or_null("/root/GameSettings")
	if gs != null:
		gs.hud_config["touch_invert_roll"] = on
		gs.call("save_hud_config")


func _on_setup_pressed() -> void:
	if _setup_root == null:
		return
	_refresh_setup()
	_setup_root.visible = true
	if _setup_timer != null:
		_setup_timer.start(0.1)
	_update_setup_channels()
	get_tree().paused = true


func _on_setup_close() -> void:
	if _setup_timer != null:
		_setup_timer.stop()
	if _setup_root != null:
		_setup_root.visible = false
	get_tree().paused = false


func _refresh_setup() -> void:
	if _setup_panel == null:
		return
	var elrs := get_node_or_null("/root/ElrsWifiInput")
	if elrs != null:
		if _arm_option != null:
			_arm_option.select(clampi(int(elrs.get("arm_channel")), 0, 15))
		if _mode_option != null:
			_mode_option.select(clampi(int(elrs.get("mode_channel")), 0, 15))
		if _video_option != null:
			_video_option.select(clampi(int(elrs.get("video_channel")), 0, 15))
		if _invert_elrs_check != null:
			_invert_elrs_check.set_pressed_no_signal(bool(elrs.get("invert_roll")))
	if _invert_touch_check != null:
		_invert_touch_check.set_pressed_no_signal(invert_roll)
	_update_setup_channels()


func _update_setup_channels() -> void:
	if _setup_root == null or not _setup_root.visible:
		return
	var elrs := get_node_or_null("/root/ElrsWifiInput")
	if elrs == null:
		return
	var ch: PackedFloat32Array = elrs.get("channels")
	for i in range(_channel_labels.size()):
		var raw := 16384
		if i < ch.size():
			raw = int(ch[i])
		_channel_labels[i].text = "CH%d: %d" % [i + 1, raw]


func _input(event: InputEvent) -> void:
	if not enabled or not touch_mode or (get_tree().paused and not _preview):
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
		var r := 0.0 if absf(x) < DEADZONE else clampf(x, -1.0, 1.0)
		if invert_roll:
			r = -r
		roll = r
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
