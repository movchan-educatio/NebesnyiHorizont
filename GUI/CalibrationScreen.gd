extends Control

const MAIN_MENU := "res://GUI/MainMenu.tscn"
const RADIO_SCENE := preload("res://GUI/ControlsMenuRadioTransmitter.tscn")
const VIRTUAL_DEVICE := -2

## Optional override set by ControlsScreen before opening the wizard so
## «Назад» returns to the caller instead of always jumping to the main menu.
static var return_scene := ""

const CHANNEL_NAMES := {
	"throttle": ["ГАЗ", "THROTTLE"],
	"yaw": ["РИСКАННЯ", "YAW"],
	"pitch": ["ТАНГАЖ", "PITCH"],
	"roll": ["КРЕН", "ROLL"],
}

const STEP_TEXTS := [
	"1. Рухайте ОБИДВА стіки по колу до упору в усі боки\n(визначаємо активні осі передавача)",
	"2. Відпустіть правий стік у центр\n(газ може залишатися внизу)",
	"3. ЛІВИЙ СТІК — ГАЗ ДОНИЗУ (0% мінімум)",
	"4. ЛІВИЙ СТІК — ГАЗ ВГОРУ (100% максимум)",
	"5. Поверніть ЛІВИЙ СТІК близько до середини",
	"6. ЛІВИЙ СТІК — РИСКАННЯ (YAW) ВЛІВО до упору",
	"7. ЛІВИЙ СТІК — РИСКАННЯ (YAW) ВПРАВО до упору",
	"8. Відпустіть ЛІВИЙ СТІК у центр",
	"9. ПРАВИЙ СТІК — ТАНГАЖ (PITCH) ВІД СЕБЕ (ніс донизу)",
	"10. ПРАВИЙ СТІК — ТАНГАЖ (PITCH) ДО СЕБЕ (ніс догори)",
	"11. Відпустіть ПРАВИЙ СТІК у центр",
	"12. ПРАВИЙ СТІК — КРЕН (ROLL) ВЛІВО до упору",
	"13. ПРАВИЙ СТІК — КРЕН (ROLL) ВПРАВО до упору",
	"14. Відпустіть ПРАВИЙ СТІК у центр",
]

const STEP_TEXTS_EN := [
	"1. Move BOTH sticks in circles to all limits\n(detecting the controller axes)",
	"2. Release the right stick to center\n(throttle may remain at the bottom)",
	"3. LEFT STICK — THROTTLE DOWN (0% minimum)",
	"4. LEFT STICK — THROTTLE UP (100% maximum)",
	"5. Return the LEFT STICK near center",
	"6. LEFT STICK — YAW LEFT to the limit",
	"7. LEFT STICK — YAW RIGHT to the limit",
	"8. Release the LEFT STICK to center",
	"9. RIGHT STICK — PITCH AWAY (nose down)",
	"10. RIGHT STICK — PITCH TOWARD YOU (nose up)",
	"11. Release the RIGHT STICK to center",
	"12. RIGHT STICK — ROLL LEFT to the limit",
	"13. RIGHT STICK — ROLL RIGHT to the limit",
	"14. Release the RIGHT STICK to center",
]

var device := 0
var axes := []
var throttle := []
var yaw := []
var pitch := []
var roll := []

var calibration_step := -1
var calibration_finished := false
var _no_controller := false
var _step_elapsed := 0.0
## Touch sources have a fixed AETR map, but the pilot must still demonstrate
## that each axis moves and that the sticks return to centre before the wizard
## advances.  This keeps the first three steps from flashing past in a second.
var _virtual_start: Array = []
var _virtual_seen: Array = [false, false, false, false]

## Centre-measurement state for the current wizard step.  The centre is only
## accepted after the stick has left the previous end stop and has stopped
## moving for a moment.  Capturing the first sample near zero while the
## self-centring stick is still flying back through neutral stores a shifted
## centre, which in flight looks like a dead spot around the middle.
var _center_tracking := false
var _center_left_start := false
var _center_start_value := 0.0
var _center_ref := 0.0
var _center_sum := 0.0
var _center_samples := 0
var _center_stable := 0.0

## Endpoint-capture state for the current wizard step.  The first sample that
## crosses the old 0.65 threshold is usually taken well before the physical
## stop, which throws away a third of the stick travel and amplifies any centre
## error.  Instead, keep the furthest value seen and capture it only after it
## has stopped changing for a moment.
var _extreme_axis := -1
var _extreme_peak := 0.0
var _extreme_peak_time := 0.0

var radio: Node = null
signal back
var embedded := false

var _instruction: Label
var _status: Label
var _device_label: Label
var _axes_label: Label
var _check_button: Button
var _retry_button: Button
var _back_step_button: Button
var _source_button: Button = null
var _protocol_label: Label = null
var _mobile_values: Label = null
var _mobile_pad: Control = null
var _gimbal_widget: _DualGimbalPreview = null

## ELRS WiFi / touch-stick bridge.  When no USB joypad exists, the wizard
## reads the virtual AETR axes instead of Input.get_joy_axis().
var _virtual := false
var _virtual_source := ""
## True after the pilot presses the source button, so a late ELRS connection
## does not override their choice.
var _source_explicit := false


class _DualGimbalPreview extends Control:
	var left_pos := Vector2.ZERO   # x = yaw (-1..1), y = throttle (-1..1, +1 is up)
	var right_pos := Vector2.ZERO  # x = roll (-1..1), y = pitch (-1..1, +1 is up)

	func _init() -> void:
		custom_minimum_size = Vector2(360, 148)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_gimbals(l: Vector2, r: Vector2) -> void:
		left_pos = Vector2(clampf(l.x, -1.0, 1.0), clampf(l.y, -1.0, 1.0))
		right_pos = Vector2(clampf(r.x, -1.0, 1.0), clampf(r.y, -1.0, 1.0))
		queue_redraw()

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var box_s := 112.0
		var gap := 36.0
		var start_x := (size.x - (box_s * 2.0 + gap)) * 0.5
		var top_y := 22.0
		_draw_gimbal(Rect2(Vector2(start_x, top_y), Vector2(box_s, box_s)),
				left_pos, MenuUI.translate_text("ЛІВИЙ СТІК (ГАЗ/YAW)"), font)
		_draw_gimbal(Rect2(Vector2(start_x + box_s + gap, top_y), Vector2(box_s, box_s)),
				right_pos, MenuUI.translate_text("ПРАВИЙ СТІК (PITCH/ROLL)"), font)

	func _draw_gimbal(rect: Rect2, val: Vector2, caption: String, font: Font) -> void:
		draw_rect(rect, Color("0b110a"), true)
		draw_rect(rect, MenuUI.BORDER, false, 1.5)
		var c := rect.get_center()
		var grid_col := Color(0.36, 0.52, 0.28, 0.35)
		draw_line(Vector2(rect.position.x + 6, c.y), Vector2(rect.end.x - 6, c.y), grid_col, 1.0)
		draw_line(Vector2(c.x, rect.position.y + 6), Vector2(c.x, rect.end.y - 6), grid_col, 1.0)
		draw_arc(c, rect.size.x * 0.32, 0.0, TAU, 32, grid_col, 1.0)
		# Marker position: +Y in val means UP on screen (negative screen Y offset)
		var pt := c + Vector2(val.x, -val.y) * (rect.size.x * 0.42)
		draw_line(c, pt, Color(0.92, 0.69, 0.21, 0.55), 1.5)
		draw_circle(pt, 6.0, MenuUI.WARN_AMBER)
		draw_circle(pt, 3.0, MenuUI.ACCENT)
		if font != null:
			draw_string(font, Vector2(rect.position.x - 8, rect.position.y - 6),
					caption, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x + 16, 11, MenuUI.MIL_GREEN_LIGHT)


func _ready() -> void:
	theme = MenuUI.theme()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	Controls.load_input_map()
	Controls.refresh_stick_bindings()
	_virtual_source = MobileInput.source()
	_build_ui()
	reset_calibration()
	_update_virtual_preview()
	MenuUI.localize_tree(self)


func _exit_tree() -> void:
	_update_virtual_preview(true)
	MobileInput.clear_source_override()


func _ui_text(uk: String, en: String) -> String:
	return en if MenuUI.is_english() else uk


func _is_virtual() -> bool:
	return device == VIRTUAL_DEVICE


func _axis_value(axis: int) -> float:
	if _is_virtual():
		return MobileInput.axis(axis)
	return Input.get_joy_axis(device, axis)


func _device_name() -> String:
	if _is_virtual():
		return MobileInput.source_name()
	return Input.get_joy_name(device)


func _update_source_button() -> void:
	if _source_button == null:
		return
	_source_button.visible = _is_virtual()
	_source_button.disabled = MobileInput.available_sources().size() < 2
	_source_button.text = "ДЖЕРЕЛО: %s" % MobileInput.short_source_name(_virtual_source)


func _cycle_source() -> void:
	var sources := MobileInput.available_sources()
	if sources.size() < 2:
		return
	var index := sources.find(_virtual_source)
	_virtual_source = String(sources[(index + 1) % sources.size()])
	_source_explicit = true
	MobileInput.set_source(_virtual_source)
	_update_virtual_preview()
	reset_calibration()


func _update_virtual_preview(hide: bool = false) -> void:
	var pad := get_node_or_null("/root/TouchControls")
	if pad == null or not pad.has_method("set_menu_preview"):
		return
	var show := not hide and _is_virtual() and _virtual_source == MobileInput.SOURCE_TOUCH
	pad.call("set_menu_preview", show)
	if _mobile_pad != null:
		_mobile_pad.custom_minimum_size = Vector2(0, 300 if show else 12)
	if _protocol_label != null and _is_virtual():
		_protocol_label.text = _ui_text("ДЖЕРЕЛО: ", "SOURCE: ") \
				+ MobileInput.short_source_name(_virtual_source)
	_update_source_button()


func _ensure_touch_preview() -> void:
	if not _is_virtual() or _virtual_source != MobileInput.SOURCE_TOUCH:
		return
	var pad := get_node_or_null("/root/TouchControls")
	if pad != null and pad.has_method("is_menu_preview") \
			and not bool(pad.call("is_menu_preview")):
		_update_virtual_preview()


func _sync_virtual_source() -> void:
	if not _is_virtual():
		return
	if not _source_explicit:
		var auto := MobileInput.source()
		if auto.is_empty():
			_virtual = false
			device = -1
			_show_no_controller()
			return
		if auto != _virtual_source:
			_virtual_source = auto
			reset_calibration()
			return
	elif not MobileInput.available_sources().has(_virtual_source):
		_source_explicit = false
		MobileInput.clear_source_override()
		_virtual_source = MobileInput.default_source()
		reset_calibration()
		return
	var actual := MobileInput.source()
	if actual.is_empty():
		_virtual = false
		device = -1
		_show_no_controller()
		return
	if actual != _virtual_source:
		_virtual_source = actual
		_update_virtual_preview()
	_update_source_button()


func _build_ui() -> void:
	add_child(MenuUI.background(MenuUI.BG))

	var root_margin := MarginContainer.new()
	MenuUI.full_rect(root_margin)
	var cal_viewport := get_viewport_rect().size
	var cal_edges := MenuUI.mobile_edge_margins(cal_viewport) if MenuUI.is_mobile_ui() else Vector4(28, 18, 28, 32)
	root_margin.add_theme_constant_override("margin_left", int(cal_edges.x))
	root_margin.add_theme_constant_override("margin_right", int(cal_edges.z))
	root_margin.add_theme_constant_override("margin_top", maxi(18, int(cal_edges.y)))
	root_margin.add_theme_constant_override("margin_bottom", maxi(32, int(cal_edges.w)))
	add_child(root_margin)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 12)
	root_margin.add_child(main_vbox)

	# Military C2 Header Bar
	var top_bar := PanelContainer.new()
	var top_sb := StyleBoxFlat.new()
	top_sb.bg_color = MenuUI.PANEL_HEADER
	top_sb.border_color = MenuUI.WARN_AMBER
	top_sb.border_width_bottom = 2
	top_sb.border_width_left = 4
	top_sb.content_margin_left = 18
	top_sb.content_margin_right = 18
	top_sb.content_margin_top = 8
	top_sb.content_margin_bottom = 8
	top_bar.add_theme_stylebox_override("panel", top_sb)
	main_vbox.add_child(top_bar)

	var top_row := HBoxContainer.new()
	top_bar.add_child(top_row)
	var sys_lbl := MenuUI.body(_ui_text("КАЛІБРУВАННЯ ПЕРЕДАВАЧА · MODE 2", "CONTROLLER CALIBRATION · MODE 2"), 15, MenuUI.WARN_AMBER)
	sys_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(sys_lbl)
	_protocol_label = MenuUI.body(_ui_text("ПРОТОКОЛ: CRSF / EDGETX / USB-HID", "PROTOCOL: CRSF / EDGETX / USB HID"), 13, MenuUI.MIL_GREEN_LIGHT)
	top_row.add_child(_protocol_label)

	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_%s" % side, 26)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	margin.add_child(outer)

	outer.add_child(MenuUI.title("КАЛІБРУВАННЯ СТІКІВ ПУЛЬТА", 34))

	var viewport_size := get_viewport_rect().size
	var stacked_layout := viewport_size.x < 1100.0 \
			or (MenuUI.is_mobile_ui() and viewport_size.y < 700.0)
	var content: BoxContainer
	if stacked_layout:
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.custom_minimum_size.y = clampf(viewport_size.y - 250.0, 220.0, 420.0)
		outer.add_child(scroll)
		# Side-by-side: the 3D transmitter stays visible while the step card
		# explains what to do.  On a narrow phone the pair can still scroll.
		var stacked := HBoxContainer.new()
		stacked.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stacked.add_theme_constant_override("separation", 16)
		scroll.add_child(stacked)
		content = stacked
	else:
		var columns := HBoxContainer.new()
		columns.add_theme_constant_override("separation", 28)
		columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
		outer.add_child(columns)
		content = columns

	content.add_child(_build_radio_preview(stacked_layout))

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(box)

	box.add_child(MenuUI.section("ПОКРОКОВИЙ МАЙСТЕР КАЛІБРУВАННЯ", "КРОК"))

	var inst_card := PanelContainer.new()
	var ic_sb := MenuUI._style(MenuUI.CARD, MenuUI.BORDER_HIGHLIGHT, 1, 2, 20, 18, 4)
	inst_card.add_theme_stylebox_override("panel", ic_sb)
	box.add_child(inst_card)

	var inst_vbox := VBoxContainer.new()
	inst_vbox.add_theme_constant_override("separation", 10)
	inst_card.add_child(inst_vbox)

	_instruction = MenuUI.body("", 22, MenuUI.TEXT)
	_instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_instruction.custom_minimum_size = Vector2(0, 84)
	inst_vbox.add_child(_instruction)

	_status = MenuUI.body("", 18, MenuUI.WARN_AMBER)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inst_vbox.add_child(_status)

	box.add_child(MenuUI.section("ДІАГНОСТИКА ОСЕЙ ПЕРЕДАВАЧА", "ТЕЛЕМЕТРІЯ"))

	var diag_card := PanelContainer.new()
	diag_card.add_theme_stylebox_override("panel", MenuUI._style(Color("0c130b"), MenuUI.BORDER, 1, 2, 16, 12, 3))
	box.add_child(diag_card)

	var diag_vbox := VBoxContainer.new()
	diag_vbox.add_theme_constant_override("separation", 6)
	diag_card.add_child(diag_vbox)

	_device_label = MenuUI.body("", 15, MenuUI.MIL_GREEN_LIGHT)
	_device_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	diag_vbox.add_child(_device_label)

	_axes_label = MenuUI.body("", 14, MenuUI.TEXT)
	_axes_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	diag_vbox.add_child(_axes_label)

	box.add_child(MenuUI.spacer(6))

	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	box.add_child(buttons)

	_check_button = MenuUI.button("ПЕРЕВІРИТИ ПУЛЬТ", 46)
	_check_button.pressed.connect(reset_calibration)
	buttons.add_child(_check_button)

	_source_button = MenuUI.button("", 46)
	_source_button.visible = false
	_source_button.pressed.connect(_cycle_source)
	buttons.add_child(_source_button)

	var step_row := HBoxContainer.new()
	step_row.add_theme_constant_override("separation", 12)
	buttons.add_child(step_row)

	_back_step_button = MenuUI.button("← ПОПЕРЕДНІЙ КРОК", 46)
	_back_step_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_back_step_button.pressed.connect(_step_back)
	step_row.add_child(_back_step_button)

	_retry_button = MenuUI.button("ПОЧАТИ СПОЧАТКУ", 46)
	_retry_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_retry_button.pressed.connect(reset_calibration)
	step_row.add_child(_retry_button)

	var back := MenuUI.button("← ПОВЕРНУТИСЯ НАЗАД", 46)
	back.pressed.connect(_go_back)
	buttons.add_child(back)
	back.grab_focus()


## Compact iPhone layout: header, current step, live channel values and the
## three action buttons.  The touch sticks are drawn by TouchControls in menu
## preview mode; the ELRS source uses the physical Pocket sticks.
func _build_mobile_ui() -> void:
	add_child(MenuUI.background(MenuUI.BG))

	var margin := MarginContainer.new()
	MenuUI.full_rect(margin)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_%s" % side, 24)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 18)
	root.add_child(header)

	var title := MenuUI.title("КАЛІБРУВАННЯ", 64)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(title)

	_source_button = MenuUI.button("ELRS", 92)
	_source_button.custom_minimum_size = Vector2(420, 92)
	_source_button.add_theme_font_size_override("font_size", 34)
	_source_button.pressed.connect(_cycle_source)
	header.add_child(_source_button)

	_status = MenuUI.body("", 34, MenuUI.WARN_AMBER)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_status)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	scroll.add_child(content)

	var inst_card := PanelContainer.new()
	inst_card.add_theme_stylebox_override("panel",
			MenuUI._style(MenuUI.CARD, MenuUI.BORDER_HIGHLIGHT, 2, 3, 32, 26, 6))
	content.add_child(inst_card)

	_instruction = MenuUI.body("", 44, MenuUI.TEXT)
	_instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_instruction.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_instruction.custom_minimum_size = Vector2(0, 150)
	inst_card.add_child(_instruction)

	var values_card := PanelContainer.new()
	values_card.add_theme_stylebox_override("panel",
			MenuUI._style(Color("0c130b"), MenuUI.BORDER, 2, 3, 28, 20, 5))
	content.add_child(values_card)

	_mobile_values = MenuUI.body("", 40, MenuUI.MIL_GREEN_LIGHT)
	_mobile_values.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	values_card.add_child(_mobile_values)

	_device_label = MenuUI.body("", 28, MenuUI.MUTED)
	_device_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_device_label)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 18)
	root.add_child(footer)

	_retry_button = MenuUI.button("СПОЧАТКУ", 100)
	_retry_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_retry_button.add_theme_font_size_override("font_size", 36)
	_retry_button.pressed.connect(reset_calibration)
	footer.add_child(_retry_button)

	_back_step_button = MenuUI.button("КРОК НАЗАД", 100)
	_back_step_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_back_step_button.add_theme_font_size_override("font_size", 36)
	_back_step_button.pressed.connect(_step_back)
	footer.add_child(_back_step_button)

	var back := MenuUI.button("НАЗАД", 100)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.add_theme_font_size_override("font_size", 36)
	back.pressed.connect(_go_back)
	footer.add_child(back)

	_mobile_pad = Control.new()
	_mobile_pad.custom_minimum_size = Vector2(0, 300)
	_mobile_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_mobile_pad)


func _build_radio_preview(compact: bool = false) -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(420, 0)
	col.add_theme_constant_override("separation", 8)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	if compact:
		col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	col.add_child(MenuUI.section("3D-МОНІТОР ПУЛЬТА RADIOMASTER TX12", "TX12"))

	var frame := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("0b120a")
	sb.border_color = MenuUI.BORDER
	sb.set_border_width_all(1)
	sb.border_width_left = 4
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	frame.add_theme_stylebox_override("panel", sb)
	col.add_child(frame)

	var container := SubViewportContainer.new()
	container.stretch = true
	container.custom_minimum_size = Vector2(400, 170 if compact else 300)
	if compact:
		container.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	frame.add_child(container)

	var viewport := SubViewport.new()
	viewport.size = Vector2i(400, 300)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)

	radio = RADIO_SCENE.instantiate()
	viewport.add_child(radio)

	# 2D Dual-Gimbal Tactical Crosshair Monitor (Left Stick = Throttle/Yaw, Right Stick = Pitch/Roll)
	_gimbal_widget = _DualGimbalPreview.new()
	col.add_child(_gimbal_widget)

	var hint := MenuUI.body(
			_ui_text("Лівий стік: ГАЗ / РИСКАННЯ  •  Правий стік: ТАНГАЖ / КРЕН",
				"Left stick: THROTTLE / YAW  •  Right stick: PITCH / ROLL"),
			13, MenuUI.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)
	return col


## Reads normalized [-1..+1] value for a stick channel:
## 1) If already captured in the current wizard run (`captured_arr`), uses that axis.
## 2) Otherwise uses `Controls.channel_value(channel)` (the exact same binding used in-game!).
## 3) Otherwise falls back to standard FPV Mode 2 AETR axis (`fallback_axis`).
func _read_calibration_channel(channel: String, captured_arr: Array, fallback_axis: int,
		invert_fallback: bool = false) -> float:
	if not captured_arr.is_empty():
		var ax := int(captured_arr[0])
		var raw := _axis_value(ax)
		if captured_arr.size() >= 2 and captured_arr[1] is InputEventJoypadMotion:
			var first := captured_arr[1] as InputEventJoypadMotion
			if captured_arr.size() >= 3 and captured_arr[2] is InputEventJoypadMotion:
				var opposite := captured_arr[2] as InputEventJoypadMotion
				var lo := first.axis_value
				var hi := opposite.axis_value
				var center: float = (lo + hi) * 0.5
				if captured_arr.size() >= 4:
					center = float(captured_arr[3])
				return Controls.normalize_range_value(raw, lo, hi, center)
			# Only the negative extreme has been captured so far.  Make the
			# preview follow the same direction the radio will use in game.
			var sign_flip := -1.0 if first.axis_value > 0.0 else 1.0
			return clampf(raw * sign_flip, -1.0, 1.0)
		return clampf(-raw if invert_fallback else raw, -1.0, 1.0)

	var bound_val := Controls.physical_channel_value(channel)
	if not is_nan(bound_val):
		return clampf(bound_val, -1.0, 1.0)

	var raw_fallback := _axis_value(fallback_axis)
	return clampf(-raw_fallback if invert_fallback else raw_fallback, -1.0, 1.0)


func _update_radio() -> void:
	if radio == null:
		return
	var pads := Input.get_connected_joypads()
	if pads.is_empty() and not _is_virtual():
		if radio.has_method("set_left_stick_position"):
			radio.set_left_stick_position(0.0, 0.0)
			radio.set_right_stick_position(0.0, 0.0)
		if _gimbal_widget != null:
			_gimbal_widget.set_gimbals(Vector2.ZERO, Vector2.ZERO)
		return

	# Standard Mode 2 AETR fallback axes on EdgeTX / OpenTX radios:
	# Roll (A) = 0, Pitch (E) = 1, Throttle (T) = 2, Yaw (R) = 3
	var th := _read_calibration_channel("throttle", throttle, 2, false)
	var yw := _read_calibration_channel("yaw", yaw, 3, false)
	var pt := _read_calibration_channel("pitch", pitch, 1, false)
	var rl := _read_calibration_channel("roll", roll, 0, false)

	# Drive the 3D TX12 sticks identically to ControlsScreen.gd:
	# Left stick = Yaw (X) & Throttle (Y), Right stick = Roll (X) & Pitch (Y)
	if radio.has_method("set_throttle_stick"):
		radio.set_throttle_stick(-th)
		radio.set_yaw_stick(yw)
		radio.set_pitch_stick(pt)
		radio.set_roll_stick(rl)
	elif radio.has_method("set_left_stick_position"):
		radio.set_left_stick_position(yw, -th)
		radio.set_right_stick_position(rl, pt)

	if _gimbal_widget != null:
		_gimbal_widget.set_gimbals(Vector2(yw, th), Vector2(rl, -pt))


func _show_no_controller() -> void:
	_no_controller = true
	_virtual = false
	device = -1
	_update_virtual_preview(true)
	_update_source_button()
	_instruction.text = _ui_text(
		"Пульт або геймпад не виявлено.\nПідключіть передавач (USB-HID / EdgeTX) або увімкни ELRS WiFi / сенсорне керування й натисни «ПЕРЕВІРИТИ».",
		"No controller or gamepad detected.\nConnect a transmitter (USB HID / EdgeTX), or enable ELRS WiFi / touch input and press TEST.")
	_status.text = _ui_text("ПІДКЛЮЧЕНИХ ПЕРЕДАВАЧІВ: 0", "CONNECTED CONTROLLERS: 0")
	_device_label.text = _ui_text("СТАТУС USB-HID: ОЧІКУВАННЯ ПІДКЛЮЧЕННЯ", "USB HID STATUS: WAITING FOR CONNECTION")
	if _axes_label != null:
		_axes_label.text = _ui_text("Осі 0–7:  немає активного сигналу", "Axes 0–7: no active signal")
	if _mobile_values != null:
		_mobile_values.text = "—"
	if _check_button != null:
		_check_button.visible = true
	if _retry_button != null:
		_retry_button.visible = false
	if _back_step_button != null:
		_back_step_button.visible = false


func reset_calibration() -> void:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		if not MobileInput.available():
			_show_no_controller()
			return
		_virtual = true
		device = VIRTUAL_DEVICE
		if not _source_explicit:
			_virtual_source = MobileInput.source()
		elif not MobileInput.available_sources().has(_virtual_source):
			_source_explicit = false
			MobileInput.clear_source_override()
			_virtual_source = MobileInput.default_source()
		var actual := MobileInput.source()
		if actual.is_empty():
			_show_no_controller()
			return
		if _virtual_source.is_empty():
			_virtual_source = actual
		if _source_explicit:
			MobileInput.set_source(_virtual_source)
	else:
		_virtual = false
		device = Controls.active_device if pads.has(Controls.active_device) else pads[0]
	_no_controller = false
	calibration_finished = false
	calibration_step = -1
	_step_elapsed = 0.0
	axes.clear()
	throttle.clear()
	yaw.clear()
	pitch.clear()
	roll.clear()
	if _check_button != null:
		_check_button.visible = false
	if _retry_button != null:
		_retry_button.visible = true
	if _back_step_button != null:
		_back_step_button.visible = false
	_update_virtual_preview()
	_update_source_button()
	go_to_next_step()


func go_to_next_step() -> void:
	calibration_step += 1
	_step_elapsed = 0.0
	_reset_center_tracking()
	_reset_extreme_tracking()
	if _is_virtual() and calibration_step == 0:
		_virtual_start = [
			_axis_value(0), _axis_value(1), _axis_value(2), _axis_value(3),
		]
		_virtual_seen = [false, false, false, false]
	if _back_step_button != null:
		_back_step_button.visible = (calibration_step > 0 and not calibration_finished)
	if calibration_step >= 0 and calibration_step < STEP_TEXTS.size():
		_instruction.text = STEP_TEXTS_EN[calibration_step] if MenuUI.is_english() else STEP_TEXTS[calibration_step]
		_status.text = _ui_text("КРОК %02d / %02d", "STEP %02d / %02d") % [calibration_step + 1, STEP_TEXTS.size()]
	else:
		_instruction.text = _ui_text("КАЛІБРУВАННЯ УСПІШНО ЗАВЕРШЕНО!\nПрофіль передавача збережено в системі.", "CALIBRATION COMPLETE!\nTransmitter profile saved.")
		_status.text = _ui_text("✓ ГОТОВО ДО БОЙОВОГО ВИЛЬОТУ", "✓ READY FOR FLIGHT")
		_on_calibration_done()


func _step_back() -> void:
	if calibration_finished or calibration_step <= 0:
		return
	match calibration_step:
		1:
			axes.clear()
			calibration_step = -1
		2:
			throttle.clear()
			calibration_step = 0
		3:
			throttle.clear()
			calibration_step = 1
		4:
			if throttle.size() > 2:
				throttle.resize(2)
			calibration_step = 2
		5:
			yaw.clear()
			calibration_step = 3
		6:
			yaw.clear()
			calibration_step = 4
		7:
			if yaw.size() > 2:
				yaw.resize(2)
			calibration_step = 5
		8:
			pitch.clear()
			calibration_step = 6
		9:
			pitch.clear()
			calibration_step = 7
		10:
			if pitch.size() > 2:
				pitch.resize(2)
			calibration_step = 8
		11:
			roll.clear()
			calibration_step = 9
		12:
			roll.clear()
			calibration_step = 10
		13:
			if roll.size() > 2:
				roll.resize(2)
			calibration_step = 11
		_:
			calibration_step = max(-1, calibration_step - 2)
	go_to_next_step()


func _process(delta: float) -> void:
	_update_radio()
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		if not MobileInput.available():
			if not _no_controller:
				_show_no_controller()
			return
		if not _is_virtual():
			reset_calibration()
			if not _is_virtual():
				return
		_sync_virtual_source()
		if not _is_virtual():
			return
		_ensure_touch_preview()
	else:
		if _is_virtual():
			reset_calibration()
		if _no_controller:
			device = pads[0]
			reset_calibration()
	_update_device_readout()
	if calibration_finished:
		return
	_step_elapsed += delta
	_poll_calibration_steps()


## Direction-agnostic step polling.  The wizard captures whichever end of the
## axis the pilot moves first and then the opposite end; it never assumes that
## "throttle down" is negative or that "yaw left" is negative.  That matters
## for EdgeTX radios, where any channel can be reversed.
func _poll_calibration_steps() -> void:
	match calibration_step:
		0:
			if _is_virtual():
				# Fixed AETR mapping.  On the phone require real movement on
				# all four axes so the step is not skipped; the desktop virtual
				# path keeps its original short delay.
				if axes.size() < 4:
					axes = [0, 1, 2, 3]
				if not MenuUI.is_mobile_ui():
					if _step_elapsed >= 0.7:
						go_to_next_step()
				else:
					if _virtual_start.size() < 4:
						_virtual_start = [
							_axis_value(0), _axis_value(1), _axis_value(2),
							_axis_value(3),
						]
					for i in range(4):
						if absf(_axis_value(i) - _virtual_start[i]) > 0.35:
							_virtual_seen[i] = true
					if not _virtual_seen.has(false) and _step_elapsed >= 0.8:
						go_to_next_step()
			elif axes.size() >= 4:
				go_to_next_step()
		1:
			if _is_virtual():
				if not MenuUI.is_mobile_ui():
					if _step_elapsed >= 0.7:
						go_to_next_step()
					return
				# The self-centring axes must be released; throttle may stay
				# at the bottom exactly as the instruction says.
				var centred := absf(_axis_value(0)) < 0.22 \
						and absf(_axis_value(1)) < 0.22 \
						and absf(_axis_value(3)) < 0.22
				if centred and _step_elapsed >= 0.6:
					go_to_next_step()
				return
			var off_centre := 0
			for axis in axes:
				if absf(Input.get_joy_axis(device, axis)) > 0.3:
					off_centre += 1
			if off_centre <= 1:
				go_to_next_step()
		2:
			_poll_first_extreme(throttle, [])
		3:
			_poll_opposite_extreme(throttle)
		4:
			_poll_center(throttle, 2.0)
		5:
			_poll_first_extreme(yaw, [throttle])
		6:
			_poll_opposite_extreme(yaw)
		7:
			_poll_center(yaw, 3.0, true)
		8:
			_poll_first_extreme(pitch, [throttle, yaw])
		9:
			_poll_opposite_extreme(pitch)
		10:
			_poll_center(pitch, 3.0, true)
		11:
			_poll_first_extreme(roll, [throttle, yaw, pitch])
		12:
			_poll_opposite_extreme(roll)
		13:
			_poll_center(roll, 3.0, true)


## Capture the first extreme of an unused detected axis.
## The pilot is told which direction to move (throttle down, yaw left, etc.),
## so the first captured end is always the channel's logical negative end —
## whatever raw sign the radio reports for it.  Requiring a particular raw
## sign here would stall the wizard on a transmitter with a reversed channel.
## The value is not taken at the first threshold crossing: the furthest point
## is tracked and captured once the stick has settled against its stop, so the
## saved range covers the real physical travel.
func _poll_first_extreme(target: Array, used: Array) -> void:
	# Keep each instruction on screen long enough to read before a stick that
	# is already at the requested stop can advance the wizard.  The shorter PC
	# timing is preserved.
	var min_dwell := 0.8 if MenuUI.is_mobile_ui() else 0.35
	if _step_elapsed < min_dwell:
		return
	var best_axis := -1
	var best_value := 0.0
	for axis in axes:
		if _axis_used(axis, used):
			continue
		var value := _axis_value(axis)
		if absf(value) > absf(best_value):
			best_axis = axis
			best_value = value
	if best_axis < 0:
		return
	if best_axis != _extreme_axis:
		_extreme_axis = best_axis
		_extreme_peak = best_value
		_extreme_peak_time = _step_elapsed
	elif absf(best_value) > absf(_extreme_peak):
		_extreme_peak = best_value
		_extreme_peak_time = _step_elapsed
	# Wait until the stick has been held (or has bounced off) the stop for a
	# moment.  Half travel is the minimum that can plausibly be an end stop.
	if absf(_extreme_peak) < 0.5 or _step_elapsed - _extreme_peak_time < 0.25:
		return
	target.clear()
	target.append(_extreme_axis)
	target.append(_make_motion(_extreme_axis, _extreme_peak))
	go_to_next_step()


## Capture the opposite end of the axis captured by `_poll_first_extreme`.
## Only values on the far side of the centre are considered, and the furthest
## one is captured after it settles — same reasoning as above.
func _poll_opposite_extreme(target: Array) -> void:
	var min_dwell := 0.5 if MenuUI.is_mobile_ui() else 0.25
	if target.size() < 2 or _step_elapsed < min_dwell:
		return
	var axis := int(target[0])
	var first := target[1] as InputEventJoypadMotion
	var first_sign := signf(first.axis_value)
	var value := _axis_value(axis)
	if signf(value) != first_sign and absf(value) > absf(_extreme_peak):
		_extreme_peak = value
		_extreme_peak_time = _step_elapsed
	if absf(_extreme_peak) < 0.5 or _step_elapsed - _extreme_peak_time < 0.25:
		return
	target.append(_make_motion(axis, _extreme_peak))
	go_to_next_step()


func _poll_center(target: Array, timeout: float, capture_center: bool = false) -> void:
	if target.is_empty():
		return
	var axis := int(target[0])
	var value := _axis_value(axis)
	if not _center_tracking:
		_center_tracking = true
		_center_start_value = value
		_center_ref = value
		_center_sum = value
		_center_samples = 1
	# Track stability from the first frame as well: if the pilot released the
	# stick before this step began, there is no "left the end stop" movement to
	# detect, and waiting for one would stall the wizard forever.
	if not _center_left_start:
		if absf(value - _center_start_value) > 0.2:
			_center_left_start = true
			_center_stable = 0.0
	if absf(value - _center_ref) <= 0.04:
		_center_stable += get_process_delta_time()
	else:
		# Still moving (or drifting): restart the settling window.
		_center_ref = value
		_center_stable = 0.0
		_center_sum = 0.0
		_center_samples = 0
	_center_sum += value
	_center_samples += 1
	var measured := _center_sum / float(maxi(_center_samples, 1))
	var settled := _center_left_start and _center_stable >= 0.2 \
			and _step_elapsed >= 0.35
	# A settled reading near neutral is a valid rest position even when the
	# stick was already centred at the start of the step.  Values held at the
	# previous end stop are far from zero and never qualify.
	var resting := absf(measured) < 0.35 and _center_stable >= 0.25 \
			and _step_elapsed >= 0.5
	if not capture_center:
		# Used only to bring the throttle back near neutral before the yaw
		# steps; the timeout keeps a ratcheted throttle from stalling the wizard.
		if absf(value) < 0.25 or (timeout > 0.0 and _step_elapsed >= timeout):
			go_to_next_step()
		return
	if settled or resting \
			or (_center_left_start and timeout > 0.0 and _step_elapsed >= timeout):
		if target.size() < 4:
			# Store the averaged, settled rest position.  On timeout this is
			# still a real measurement — never a fabricated midpoint.
			target.append(measured)
		go_to_next_step()


func _reset_center_tracking() -> void:
	_center_tracking = false
	_center_left_start = false
	_center_start_value = 0.0
	_center_ref = 0.0
	_center_sum = 0.0
	_center_samples = 0
	_center_stable = 0.0


func _reset_extreme_tracking() -> void:
	_extreme_axis = -1
	_extreme_peak = 0.0
	_extreme_peak_time = 0.0


func _make_motion(axis: int, value: float) -> InputEventJoypadMotion:
	var motion := InputEventJoypadMotion.new()
	motion.axis = axis
	motion.axis_value = value
	motion.device = device
	return motion


func _update_device_readout() -> void:
	if _device_label != null:
		if _is_virtual():
			_device_label.text = _ui_text("ДЖЕРЕЛО: %s", "SOURCE: %s") % MobileInput.source_name()
		else:
			_device_label.text = _ui_text("АКТИВНИЙ ПЕРЕДАВАЧ: %s  [ID: %d]",
					"ACTIVE CONTROLLER: %s  [ID: %d]") % [Input.get_joy_name(device), device]
	if _mobile_values != null:
		var th := _read_calibration_channel("throttle", throttle, 2, false)
		var yw := _read_calibration_channel("yaw", yaw, 3, false)
		var pt := _read_calibration_channel("pitch", pitch, 1, false)
		var rl := _read_calibration_channel("roll", roll, 0, false)
		_mobile_values.text = _ui_text(
				"ГАЗ %+.2f    РИСК %+.2f\nТАНГАЖ %+.2f    КРЕН %+.2f",
				"THR %+.2f    YAW %+.2f\nPITCH %+.2f    ROLL %+.2f") % [th, yw, pt, rl]
	if _axes_label != null:
		var count := 4 if _is_virtual() else 8
		var low := PackedStringArray()
		var high := PackedStringArray()
		for axis in range(count):
			var value := _axis_value(axis)
			var mark := "*" if axes.find(axis) >= 0 else " "
			var cell := "CH%d%s:%+.2f" % [axis + 1, mark, value]
			if axis < 4:
				low.append(cell)
			else:
				high.append(cell)
		if count <= 4:
			_axes_label.text = "   ".join(low)
		else:
			_axes_label.text = "%s\n%s" % ["   ".join(low), "   ".join(high)]
	_update_source_button()


func _input(event: InputEvent) -> void:
	if ((event.is_action("ui_cancel") or (event is InputEventJoypadButton and (event.button_index == JOY_BUTTON_B or event.button_index == JOY_BUTTON_BACK)))
			and event.is_pressed() and not event.is_echo()):
		accept_event()
		_go_back()
		return

	if ((event is InputEventKey and event.is_pressed() and not event.is_echo() and (event.keycode == KEY_BACKSPACE or event.keycode == KEY_Z))
			or (event is InputEventJoypadButton and event.is_pressed() and not event.is_echo() and (event.button_index == JOY_BUTTON_X or event.button_index == JOY_BUTTON_Y))):
		accept_event()
		_step_back()
		return

	if calibration_finished or not (event is InputEventJoypadMotion):
		return
	var motion := event as InputEventJoypadMotion
	if absf(motion.axis_value) > 0.35 \
			and Input.get_connected_joypads().has(motion.device):
		device = motion.device

	# Step 0 only discovers which axes are active.  All stick-direction
	# capture is done by `_poll_calibration_steps`, so reversed channels and
	# Mode 1/Mode 2 radios calibrate the same way.
	if calibration_step == 0 and absf(motion.axis_value) > 0.8:
		if axes.find(motion.axis) < 0 and axes.size() < 4:
			axes.append(motion.axis)
			_status.text = _ui_text("ВИЯВЛЕНО АКТИВНИХ ОСЕЙ: %d / 4", "ACTIVE AXES DETECTED: %d / 4") % axes.size()


func _on_calibration_done() -> void:
	if calibration_finished:
		return
	if throttle.size() < 3 or yaw.size() < 3 or pitch.size() < 3 or roll.size() < 3:
		_status.text = _ui_text("Калібрування неповне — натисніть «ПОЧАТИ СПОЧАТКУ»", "Calibration incomplete — press RESTART")
		calibration_finished = false
		calibration_step = -1
		return
	var used := {}
	for pair in [["throttle", throttle], ["yaw", yaw], ["pitch", pitch], ["roll", roll]]:
		var axis := int(pair[1][0])
		if used.has(axis):
			_status.text = _ui_text("Помилка: вісь %d призначена двом каналам. Перекалібруйте.", "Error: axis %d is assigned to two channels. Recalibrate.") % axis
			calibration_finished = false
			calibration_step = -1
			return
		used[axis] = pair[0]

	# Every captured pair must actually span a usable part of the axis.  A
	# transmitter whose endpoint did not register (or a stick moved only a few
	# percent) would otherwise be saved as \"full travel\" and the drone would
	# fly at a fraction of the commanded rate.
	var channels := {
		"throttle": throttle,
		"yaw": yaw,
		"pitch": pitch,
		"roll": roll,
	}
	for channel in channels:
		var capture: Array = channels[channel]
		var first := capture[1] as InputEventJoypadMotion
		var second := capture[2] as InputEventJoypadMotion
		if first == null or second == null \
				or absf(second.axis_value - first.axis_value) < 0.35:
			var names: Array = CHANNEL_NAMES.get(channel, [channel, channel])
			_status.text = _ui_text(
					"Хід каналу «%s» замалий. Перекалібруйте, доводячи стік до упору.",
					"Channel \"%s\" travel is too small. Recalibrate and push the stick to the end stop."
					) % _ui_text(names[0], names[1])
			calibration_finished = false
			calibration_step = -1
			return

	calibration_finished = true
	if _is_virtual():
		if _virtual_source == MobileInput.SOURCE_ELRS:
			for channel in channels:
				var capture: Array = channels[channel]
				var negative_end := (capture[1] as InputEventJoypadMotion).axis_value
				var positive_end := (capture[2] as InputEventJoypadMotion).axis_value
				var center := NAN
				if capture.size() >= 4:
					center = float(capture[3])
				MobileInput.set_calibration(MobileInput.SOURCE_ELRS, channel,
						negative_end, positive_end, center)
			MobileInput.save_calibration()
			_status.text = _ui_text("✓ КАЛІБРУВАННЯ ELRS ЗБЕРЕЖЕНО",
					"✓ ELRS CALIBRATION SAVED")
		else:
			# Touch sticks are generated from a fixed radius; there is no ADC
			# drift to trim, so the wizard is a direction/travel check.
			_status.text = _ui_text("✓ СЕНСОРНІ СТІКИ ПЕРЕВІРЕНО",
					"✓ TOUCH STICKS VERIFIED")
		_instruction.text = _ui_text(
				"ГОТОВО. Сенсорні стіки вже мають точний центр і повний хід; напрямки перевірено.",
				"DONE. Touch sticks already have an exact centre and full travel; directions verified.") \
				if _virtual_source == MobileInput.SOURCE_TOUCH else _ui_text(
				"ГОТОВО. Калібрування ELRS збережено — воно застосується до польоту.",
				"DONE. ELRS calibration saved and will be used in flight.")
	else:
		Controls.active_device = device
		Controls.active_controller_guid = Input.get_joy_guid(device)

		# Save the real endpoints (and the measured centre) of every channel. The
		# first captured end is the channel's logical negative direction, the
		# second the positive one, matching the wizard texts.  apply_stick_calibrated
		# also clears any stale manual inversion, so a fresh wizard run always leaves
		# roll/pitch/yaw turning the way the labels say.
		for channel in channels:
			var capture: Array = channels[channel]
			var negative_end := (capture[1] as InputEventJoypadMotion).axis_value
			var positive_end := (capture[2] as InputEventJoypadMotion).axis_value
			var center := NAN
			if capture.size() >= 4:
				center = float(capture[3])
			Controls.apply_stick_calibrated(channel, int(capture[0]),
					negative_end, positive_end, center)

		for action in ["throttle_up", "throttle_down", "yaw_left", "yaw_right", "pitch_up", "pitch_down", "roll_left", "roll_right"]:
			InputMap.action_set_deadzone(action, Controls.stick_deadzone)
		# A correct calibration gives an exact neutral, so a huge deadband that was
		# set to mask centre drift is no longer needed.  Leaving it at e.g. 0.25
		# would itself feel like a dead spot for the first quarter of stick travel.
		if Controls.stick_deadzone > 0.10:
			Controls.stick_deadzone = Controls.MOBILE_STICK_DEADZONE \
					if MenuUI.is_mobile_ui() else Controls.DEFAULT_STICK_DEADZONE
		Controls.refresh_stick_bindings()
		Controls.reset_stick_filters()
		Controls.restore_keyboard_shortcuts()
		Controls.make_joypad_events_global()
		Controls.save_bindings()
	await get_tree().create_timer(1.4).timeout
	if is_inside_tree():
		_go_back()


func _axis_used(axis: int, channels: Array) -> bool:
	for channel in channels:
		if channel is Array and not channel.is_empty() and int(channel[0]) == axis:
			return true
	return false


func _get_return_scene() -> String:
	if not Global.calibration_return_scene.is_empty():
		return Global.calibration_return_scene
	if not return_scene.is_empty():
		return return_scene
	if OS.has_feature("mobile"):
		return "res://GUI/mobile/MobileMenu.tscn"
	return MAIN_MENU


func _go_back() -> void:
	if embedded:
		back.emit()
		return
	var target := _get_return_scene()
	Global.calibration_return_scene = ""
	return_scene = ""
	get_tree().change_scene_to_file(target)
