## Controls / bindings screen.
##
## Detects connected radios and gamepads by GUID, lets the player choose the
## active device, and binds sticks/buttons through quick auto-detection:
## press «Авто», move the stick (or press a button) and the input is captured.
##
## The Radiomaster TX12 preview mirrors the live stick channels, so the radio
## and the axis grid always move together.
extends Control

const MAIN_MENU := "res://GUI/MainMenu.tscn"
const CALIBRATION_SCREEN := "res://GUI/CalibrationScreen.tscn"
const CALIBRATION_SCRIPT := preload("res://GUI/CalibrationScreen.gd")
const RADIO_SCENE := preload("res://GUI/ControlsMenuRadioTransmitter.tscn")

const CHANNELS := ["throttle", "yaw", "pitch", "roll"]
const CHANNEL_LABELS := {
	"throttle": "ГАЗ",
	"yaw": "РИСКАННЯ",
	"pitch": "ТАНГАЖ",
	"roll": "КРЕН",
}
const CHANNEL_AXIS_HINTS := {
	"throttle": "↕",
	"yaw": "↔",
	"pitch": "↕",
	"roll": "↔",
}

const STICK_ROWS := [
	["throttle", "Газ"],
	["yaw", "Рискання"],
	["pitch", "Тангаж"],
	["roll", "Крен"],
]

const ACTION_ROWS := [
	["toggle_arm", "Увімкнути / вимкнути двигуни"],
	["arm", "Запуск моторів"],
	["deploy_payload", "Скид боєприпасу"],
	["activate_payload", "Активація БЧ / миттєва детонація"],
	["mode_angle", "Режим ANGLE"],
	["mode_horizon", "Режим HORIZON"],
	["mode_speed", "Режим SPEED"],
	["mode_position", "Режим POSITION"],
	["mode_turtle", "Режим TURTLE"],
	["mode_launch", "Режим LAUNCH"],
	["altitude_hold", "Допомога газу"],
	["respawn", "Відновлення дрона"],
	["cycle_flight_modes", "Цикл режимів"],
	["toggle_fpv_effects", "Відеофільтр FPV"],
	["tutorial_help", "Довідка"],
	["tutorial_retry", "Повторити модуль"],
	["pause_menu", "Пауза"],
]

signal back

## When true the screen is embedded by the legacy options menu and «Назад»
## returns to it instead of switching the whole scene.
var embedded := false

var _device_option: OptionButton
var _default_toggle: CheckButton
var _guid_label: Label
var _status_label: Label
var _message: Label
var _live_label: Label
var _axis_bars: Array[HSlider] = []
var _axis_tags: Array[Label] = []
var _axis_values: Array[Label] = []
var _channel_bars: Array[HSlider] = []
var _channel_values: Array[Label] = []
var _radio: Node = null
var _stick_values := {}
var _action_values := {}
var _invert_state_label: Label
var _virtual_invert_elrs: CheckBox = null
var _virtual_invert_touch: CheckBox = null
var _latency_label: Label
## Timestamp of the last joypad event, used to measure input-to-frame latency.
var _motion_stamp_usec := -1
var _input_latency_ms := 0.0
var _has_motion_sample := false

var _detect := ""
var _detect_channel := ""
var _detect_action := ""
var _detect_initial_axes := {}
## ELRS switch capture: no joypad events exist on a phone, so polling the live
## channel frame is how the old «Авто» button learns which switch was moved.
var _detect_virtual := false
var _detect_virtual_time := 0.0
var _detect_virtual_baseline := PackedFloat32Array()

var _connected: Array = []
## Virtual source selected in the device list ("" = physical controller).
var _active_virtual := ""
## True after the pilot picks a source manually.  A late ELRS connection then
## no longer overrides an explicit «Сенсорні стіки» choice.
var _source_explicit := false
var _device_entries: Array = []
var _mobile_note: Label = null
var _mobile_bottom_pad: Control = null
## Set while handing the selected ELRS/touch source to the calibration wizard;
## _exit_tree() must not clear it before the new screen reads it.
var _keep_source_override := false


func _ready() -> void:
	theme = MenuUI.theme()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_build()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_refresh_devices()
	_refresh_binding_labels()
	_sync_virtual_options()
	MenuUI.localize_tree(self)


func _exit_tree() -> void:
	_set_touch_preview(false)
	if not _keep_source_override:
		MobileInput.clear_source_override()


func _is_virtual() -> bool:
	return not _active_virtual.is_empty() and MobileInput.source() == _active_virtual


func _set_touch_preview(on: bool) -> void:
	var pad := get_node_or_null("/root/TouchControls")
	if pad != null and pad.has_method("set_menu_preview"):
		pad.call("set_menu_preview", on)


func _ui_text(uk: String, en: String) -> String:
	return en if MenuUI.is_english() else uk


## Compact iPhone layout.  The desktop three-column cockpit does not fit a
## 390-pixel-high landscape screen, so mobile shows the live source, channels,
## axes, calibration button and back button in one scrollable column.
func _build_mobile() -> void:
	add_child(MenuUI.background(MenuUI.BG))

	var margin := MarginContainer.new()
	MenuUI.full_rect(margin)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_%s" % side, 24)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 18)
	box.add_child(header)

	var title := MenuUI.title("КЕРУВАННЯ", 64)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(title)

	var back_button := MenuUI.button("←  НАЗАД", 96)
	back_button.custom_minimum_size = Vector2(360, 96)
	back_button.add_theme_font_size_override("font_size", 34)
	back_button.pressed.connect(_go_back)
	header.add_child(back_button)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 14)
	scroll.add_child(column)

	# --- source / device ---
	var device_panel := _card()
	column.add_child(device_panel)
	var device_box := VBoxContainer.new()
	device_box.add_theme_constant_override("separation", 10)
	device_panel.add_child(device_box)

	_device_option = OptionButton.new()
	_device_option.custom_minimum_size = Vector2(0, 96)
	_device_option.add_theme_font_size_override("font_size", 36)
	_device_option.item_selected.connect(_on_device_selected)
	device_box.add_child(_device_option)

	_status_label = MenuUI.body("", 30, MenuUI.MUTED)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	device_box.add_child(_status_label)

	_message = MenuUI.body("", 30, MenuUI.ACCENT)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	device_box.add_child(_message)

	var calibrate := MenuUI.button("КАЛІБРУВАННЯ СТІКІВ", 110)
	calibrate.add_theme_font_size_override("font_size", 38)
	calibrate.pressed.connect(_go_calibration)
	column.add_child(calibrate)

	# --- live channels ---
	column.add_child(MenuUI.body(_ui_text("ЖИВИЙ ВХІД", "LIVE INPUT"), 32, MenuUI.ACCENT))
	var channels_panel := _card()
	column.add_child(channels_panel)
	var channels_box := VBoxContainer.new()
	channels_box.add_theme_constant_override("separation", 12)
	channels_panel.add_child(channels_box)
	for channel in CHANNELS:
		channels_box.add_child(_build_channel_row(channel))

	_live_label = MenuUI.body("", 30, MenuUI.ACCENT)
	_live_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_live_label)

	# --- axes (only the four sticks matter on a phone) ---
	column.add_child(MenuUI.body(_ui_text("ОСІ", "AXES"), 32, MenuUI.ACCENT))
	var axes_panel := _card()
	column.add_child(axes_panel)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 18)
	axes_panel.add_child(grid)
	for i in range(4):
		grid.add_child(_build_axis_cell(i))

	column.add_child(MenuUI.body(_ui_text("КНОПКИ ТА ПЕРЕМИКАЧІ",
			"BUTTONS & SWITCHES"), 32, MenuUI.ACCENT))
	var bind_hint := MenuUI.body(_ui_text(
			"Натисни «Авто» біля дії й перемкни тумблер Pocket (CH5–CH16).",
			"Press Auto next to an action, then flip a Pocket switch (CH5–CH16)."),
			28, MenuUI.MUTED)
	bind_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(bind_hint)
	var bindings_panel := _card()
	column.add_child(bindings_panel)
	var bindings := VBoxContainer.new()
	bindings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bindings.add_theme_constant_override("separation", 10)
	bindings_panel.add_child(bindings)
	for entry in ACTION_ROWS:
		bindings.add_child(_binding_row("action", entry[0], entry[1]))

	_latency_label = MenuUI.body("", 28, MenuUI.MUTED)
	column.add_child(_latency_label)

	_mobile_note = MenuUI.body(
			_ui_text("ELRS: натисни «Авто» біля дії й перемкни тумблер на Pocket (CH5–CH16). Сенсорні кнопки АРМ/СКИД/ЗАСТ./РЕСЕТ/ВІДЕО/МЕНЮ вже на екрані.",
					"ELRS: press Auto next to an action, then flip a Pocket switch (CH5–CH16). Touch ARM/DROP/USE/RESET/VIDEO/MENU buttons are already on screen."),
			28, MenuUI.MUTED)
	_mobile_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_mobile_note)

	# Keep the last rows scrollable above the twin-stick preview.
	_mobile_bottom_pad = Control.new()
	_mobile_bottom_pad.custom_minimum_size = Vector2(0, 330)
	_mobile_bottom_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_mobile_bottom_pad)


func _build() -> void:
	add_child(MenuUI.background(MenuUI.BG))

	var margin := MarginContainer.new()
	MenuUI.full_rect(margin)
	var viewport_size := get_viewport_rect().size
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_%s" % side, minf(24.0, viewport_size.x * 0.025))
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 32)
	add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	box.add_child(MenuUI.title("КЕРУВАННЯ", 40))
	box.add_child(MenuUI.subtitle(
			_ui_text("Пульт TX12 повторює рухи стіків — сітка осей показує живий вхід",
				"The TX12 preview mirrors your stick inputs; the axis grid shows live signals.")))

	var radio_column := _build_radio_column()
	var axis_column := _build_axis_column()
	var bindings_column := _build_device_bindings_column()
	if viewport_size.x < 1100.0:
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.custom_minimum_size.y = maxf(180.0, viewport_size.y - 220.0)
		box.add_child(scroll)
		var stacked := VBoxContainer.new()
		stacked.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stacked.add_theme_constant_override("separation", 12)
		scroll.add_child(stacked)
		stacked.add_child(radio_column)
		stacked.add_child(axis_column)
		stacked.add_child(bindings_column)
	else:
		var main := HBoxContainer.new()
		main.add_theme_constant_override("separation", 14)
		main.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(main)
		main.add_child(radio_column)
		main.add_child(axis_column)
		main.add_child(bindings_column)

	_message = MenuUI.body("", 15, MenuUI.ACCENT)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_message)

	var back_button := MenuUI.button("←  НАЗАД", 38)
	back_button.pressed.connect(_go_back)
	box.add_child(back_button)


## Same modern card as MenuUI, but with tighter inner padding so three
## columns still fit a 1280×720 window without clipping.
func _card() -> PanelContainer:
	var panel := PanelContainer.new()
	var base := MenuUI.theme().get_stylebox("panel", "PanelContainer")
	if base is StyleBoxFlat:
		var style: StyleBoxFlat = (base as StyleBoxFlat).duplicate()
		style.content_margin_left = 16
		style.content_margin_right = 16
		style.content_margin_top = 14
		style.content_margin_bottom = 14
		panel.add_theme_stylebox_override("panel", style)
	return panel


func _build_radio_column() -> Control:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(360, 0)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_stretch_ratio = 1.15
	column.add_theme_constant_override("separation", 8)

	column.add_child(MenuUI.section("ПУЛЬТ  RADIOMASTER  TX12"))

	var panel := _card()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(panel)

	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.custom_minimum_size = Vector2(0, 380)
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(holder)

	var viewport := SubViewport.new()
	viewport.size = Vector2i(520, 620)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.handle_input_locally = false
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	holder.add_child(viewport)

	_radio = RADIO_SCENE.instantiate()
	viewport.add_child(_radio)
	_radio.accept_input = false

	var calibrate := MenuUI.button("КАЛІБРУВАННЯ СТІКІВ", 38)
	calibrate.pressed.connect(_go_calibration)
	column.add_child(calibrate)

	return column


func _build_axis_column() -> Control:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(370, 0)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 6)
	column.alignment = BoxContainer.ALIGNMENT_CENTER

	column.add_child(MenuUI.section("СІТКА ОСЕЙ"))

	var panel := _card()
	column.add_child(panel)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	panel.add_child(grid)
	for i in range(8):
		grid.add_child(_build_axis_cell(i))

	column.add_child(MenuUI.spacer(4))
	column.add_child(MenuUI.section("КАНАЛИ ПУЛЬТА"))

	var channels_panel := _card()
	column.add_child(channels_panel)
	var channels_box := VBoxContainer.new()
	channels_box.add_theme_constant_override("separation", 4)
	channels_panel.add_child(channels_box)
	for channel in CHANNELS:
		channels_box.add_child(_build_channel_row(channel))

	_live_label = MenuUI.body("", 13, MenuUI.ACCENT)
	_live_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_live_label)

	_latency_label = MenuUI.body("", 11, MenuUI.MUTED)
	column.add_child(_latency_label)

	return column


func _build_axis_cell(index: int) -> Control:
	var cell := VBoxContainer.new()
	cell.custom_minimum_size = Vector2(145, 0)
	cell.add_theme_constant_override("separation", 2)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	cell.add_child(top)

	var name_label := MenuUI.body("%s %d" % [_ui_text("ВІСЬ", "AXIS"), index], 11, MenuUI.MUTED)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_label)

	var tag := MenuUI.body("", 10, MenuUI.ACCENT)
	top.add_child(tag)

	var value := MenuUI.body("0.00", 10, MenuUI.MUTED)
	value.custom_minimum_size = Vector2(36, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(value)

	var bar := HSlider.new()
	bar.min_value = -1.0
	bar.max_value = 1.0
	bar.step = 0.01
	bar.editable = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.custom_minimum_size = Vector2(0, 18)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.add_child(bar)

	_axis_bars.append(bar)
	_axis_tags.append(tag)
	_axis_values.append(value)
	return cell


func _build_channel_row(channel: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var name_label := MenuUI.body("%s  %s" % [
			CHANNEL_LABELS[channel], CHANNEL_AXIS_HINTS[channel]], 14, MenuUI.TEXT)
	name_label.custom_minimum_size = Vector2(108, 0)
	row.add_child(name_label)

	var bar := HSlider.new()
	bar.min_value = -1.0
	bar.max_value = 1.0
	bar.step = 0.01
	bar.editable = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.custom_minimum_size = Vector2(0, 18)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bar)

	var value := MenuUI.body("0.00", 13, MenuUI.MUTED)
	value.custom_minimum_size = Vector2(44, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)

	_channel_bars.append(bar)
	_channel_values.append(value)
	return row


func _build_device_bindings_column() -> Control:
	# The column holds the device card, stick tuning and the binding list.  Wrap
	# it in a scroll container so adding more controls can never push the
	# bindings off the bottom of a 720p window.
	var outer := ScrollContainer.new()
	outer.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	outer.custom_minimum_size = Vector2(430, 380)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 6)
	outer.add_child(column)

	column.add_child(MenuUI.section("ELRS / СЕНСОР"))
	var virtual_panel := _card()
	column.add_child(virtual_panel)
	var virtual_box := VBoxContainer.new()
	virtual_box.add_theme_constant_override("separation", 4)
	virtual_panel.add_child(virtual_box)

	_virtual_invert_elrs = CheckBox.new()
	_virtual_invert_elrs.text = _ui_text("Інверсія крену (ELRS)", "Invert roll (ELRS)")
	_virtual_invert_elrs.add_theme_font_size_override("font_size", 14)
	_virtual_invert_elrs.add_theme_color_override("font_color", MenuUI.TEXT)
	_virtual_invert_elrs.toggled.connect(_on_virtual_invert_elrs)
	virtual_box.add_child(_virtual_invert_elrs)

	_virtual_invert_touch = CheckBox.new()
	_virtual_invert_touch.text = _ui_text("Інверсія крену (сенсор)", "Invert roll (touch)")
	_virtual_invert_touch.add_theme_font_size_override("font_size", 14)
	_virtual_invert_touch.add_theme_color_override("font_color", MenuUI.TEXT)
	_virtual_invert_touch.toggled.connect(_on_virtual_invert_touch)
	virtual_box.add_child(_virtual_invert_touch)

	var virtual_hint := MenuUI.body(_ui_text(
			"Якщо крен перевернутий — увімкни відповідний пункт. Зберігається автоматично.",
			"If roll is reversed, enable the matching option. Saved automatically."), 11, MenuUI.MUTED)
	virtual_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	virtual_box.add_child(virtual_hint)

	column.add_child(MenuUI.section("ПРИСТРІЙ"))

	var device_panel := _card()
	column.add_child(device_panel)
	var device_box := VBoxContainer.new()
	device_box.add_theme_constant_override("separation", 5)
	device_panel.add_child(device_box)

	_device_option = OptionButton.new()
	_device_option.custom_minimum_size = Vector2(0, 34)
	_device_option.item_selected.connect(_on_device_selected)
	device_box.add_child(_device_option)

	_default_toggle = CheckButton.new()
	_default_toggle.text = "Використовувати за замовчуванням"
	_default_toggle.add_theme_font_size_override("font_size", 12)
	_default_toggle.toggled.connect(_on_default_toggled)
	device_box.add_child(_default_toggle)

	_guid_label = MenuUI.body("", 11, MenuUI.MUTED)
	_guid_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	device_box.add_child(_guid_label)

	_status_label = MenuUI.body("", 13, MenuUI.MUTED)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	device_box.add_child(_status_label)

	# Quick profiles row for instant 1-click binding
	device_box.add_child(MenuUI.spacer(2))
	var prof_title := MenuUI.body(_ui_text("ШВИДКІ ПРИЗНАЧЕННЯ:", "QUICK BINDINGS:"), 11, MenuUI.ACCENT)
	device_box.add_child(prof_title)
	var prof_row := HBoxContainer.new()
	prof_row.add_theme_constant_override("separation", 6)
	device_box.add_child(prof_row)

	var btn_radio := MenuUI.button("EdgeTX AETR", 28)
	btn_radio.tooltip_text = _ui_text("Стандартна схема Mode 2 (AETR). Якщо стіки не відповідають — скористайтеся калібруванням.", "Standard Mode 2 AETR. If the sticks do not match, use calibration.")
	btn_radio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_radio.add_theme_font_size_override("font_size", 11)
	btn_radio.pressed.connect(_apply_radiomaster_preset)
	prof_row.add_child(btn_radio)

	var btn_pad := MenuUI.button("Геймпад", 28)
	btn_pad.tooltip_text = _ui_text("Стандартний геймпад Xbox / PlayStation", "Standard Xbox / PlayStation gamepad")
	btn_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_pad.add_theme_font_size_override("font_size", 11)
	btn_pad.pressed.connect(_apply_gamepad_preset)
	prof_row.add_child(btn_pad)

	var btn_kb := MenuUI.button("Клавіатура", 28)
	btn_kb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_kb.add_theme_font_size_override("font_size", 11)
	btn_kb.pressed.connect(_apply_keyboard_preset)
	prof_row.add_child(btn_kb)

	# --- Stick tuning panel ---
	device_box.add_child(MenuUI.spacer(4))
	device_box.add_child(MenuUI.section("НАЛАШТУВАННЯ СТІКІВ", "STICK TUNING"))

	var stick_vbox := VBoxContainer.new()
	stick_vbox.add_theme_constant_override("separation", 4)
	device_box.add_child(stick_vbox)

	var deadzone_row := HBoxContainer.new()
	deadzone_row.add_theme_constant_override("separation", 8)
	stick_vbox.add_child(deadzone_row)
	var dz_label := MenuUI.body(_ui_text("Мертва зона:", "Deadband:"), 12, MenuUI.TEXT)
	dz_label.tooltip_text = _ui_text("Значення навколо центру, яке ігнорується (за замовчуванням 0.02)", "Values near centre that are ignored (default 0.02)")
	deadzone_row.add_child(dz_label)
	var dz_slider := HSlider.new()
	dz_slider.min_value = 0.0
	dz_slider.max_value = 0.25
	dz_slider.step = 0.01
	dz_slider.value = Controls.stick_deadzone
	dz_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deadzone_row.add_child(dz_slider)
	var dz_val := MenuUI.body("%.2f" % Controls.stick_deadzone, 11, MenuUI.MUTED)
	dz_val.custom_minimum_size = Vector2(32, 0)
	deadzone_row.add_child(dz_val)
	dz_slider.value_changed.connect(func(v):
		Controls.stick_deadzone = float(v)
		dz_val.text = "%.2f" % v)
	dz_slider.drag_ended.connect(func(_changed): Controls.save_bindings())

	var smooth_row := HBoxContainer.new()
	smooth_row.add_theme_constant_override("separation", 8)
	stick_vbox.add_child(smooth_row)
	var sm_label := MenuUI.body(_ui_text("Згладжування:", "Smoothing:"), 12, MenuUI.TEXT)
	sm_label.tooltip_text = _ui_text("0 — миттєвий відгук; більше значення додає інерцію та затримку", "0 = instant response; higher values add inertia and lag")
	smooth_row.add_child(sm_label)
	var sm_slider := HSlider.new()
	sm_slider.min_value = 0.0
	sm_slider.max_value = 0.5
	sm_slider.step = 0.05
	sm_slider.value = Controls.stick_smoothing
	sm_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	smooth_row.add_child(sm_slider)
	var sm_val := MenuUI.body("%.2f" % Controls.stick_smoothing, 11, MenuUI.MUTED)
	sm_val.custom_minimum_size = Vector2(32, 0)
	smooth_row.add_child(sm_val)
	sm_slider.value_changed.connect(func(v):
		Controls.stick_smoothing = float(v)
		sm_val.text = "%.2f" % v)
	sm_slider.drag_ended.connect(func(_changed): Controls.save_bindings())

	var inv_row := HBoxContainer.new()
	inv_row.add_theme_constant_override("separation", 8)
	stick_vbox.add_child(inv_row)
	var inv_label := MenuUI.body(_ui_text("Інвертувати всі стіки:", "Invert all sticks:"), 12, MenuUI.TEXT)
	inv_row.add_child(inv_label)
	var inv_btn := MenuUI.button("⇄", 30)
	inv_btn.add_theme_font_size_override("font_size", 14)
	inv_btn.tooltip_text = _ui_text("Інвертувати напрямок усіх чотирьох стіків одночасно", "Invert direction of all four sticks at once")
	inv_btn.pressed.connect(_invert_all_sticks)
	inv_row.add_child(inv_btn)
	_invert_state_label = MenuUI.body(_invert_state_text(), 11, MenuUI.MUTED)
	inv_row.add_child(_invert_state_label)
	inv_row.add_child(MenuUI.spacer(2))

	column.add_child(MenuUI.spacer(2))
	column.add_child(MenuUI.section("ПРИВ’ЯЗКИ"))

	var bindings_panel := _card()
	bindings_panel.size_flags_vertical = Control.SIZE_FILL
	column.add_child(bindings_panel)

	var bindings := VBoxContainer.new()
	bindings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bindings.add_theme_constant_override("separation", 5)
	bindings_panel.add_child(bindings)

	bindings.add_child(MenuUI.section("СТІКИ"))
	for entry in STICK_ROWS:
		bindings.add_child(_binding_row("stick", entry[0], entry[1]))

	bindings.add_child(MenuUI.spacer(2))
	bindings.add_child(MenuUI.section("КНОПКИ ТА ПЕРЕМИКАЧІ"))
	for entry in ACTION_ROWS:
		bindings.add_child(_binding_row("action", entry[0], entry[1]))

	return outer


func _binding_row(kind: String, key: String, label_text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var label := MenuUI.body(label_text, 15)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var value := MenuUI.body("—", 13, MenuUI.MUTED)
	value.custom_minimum_size = Vector2(80, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	var detect := MenuUI.button("Авто", 30)
	detect.add_theme_font_size_override("font_size", 14)
	detect.custom_minimum_size = Vector2(64, 30)
	detect.pressed.connect(_start_detect.bind(kind, key))
	if kind == "action" and key == "activate_payload":
		var tip := _ui_text(
				"Призначте цю дію на тумблер/кнопку пульта. Працює для камікадзе та дронів з БЧ: підрив на місці.",
				"Bind this action to a transmitter switch/button. Works for kamikaze and warhead drones: instant detonation.")
		label.tooltip_text = tip
		detect.tooltip_text = tip
	row.add_child(detect)
	if kind == "stick":
		var invert := MenuUI.button("⇄", 30)
		invert.add_theme_font_size_override("font_size", 14)
		invert.custom_minimum_size = Vector2(36, 30)
		invert.tooltip_text = _ui_text("Інвертувати напрямок стіка", "Invert stick direction")
		invert.pressed.connect(_invert_binding.bind(key))
		row.add_child(invert)
	var clear := MenuUI.button("✕", 30)
	clear.add_theme_font_size_override("font_size", 14)
	clear.custom_minimum_size = Vector2(36, 30)
	clear.pressed.connect(_clear_binding.bind(kind, key))
	row.add_child(clear)
	if kind == "stick":
		_stick_values[key] = value
	else:
		_action_values[key] = value
	return row


# ------------------------------------------------------------------ devices

func _refresh_devices() -> void:
	_connected = Input.get_connected_joypads()
	_device_entries.clear()
	_device_option.clear()
	for device in _connected:
		_device_entries.append({"kind": "physical", "device": device})
	for source_name_value in MobileInput.available_sources():
		_device_entries.append({"kind": "virtual", "source": source_name_value})

	if _device_entries.is_empty():
		_active_virtual = ""
		_set_touch_preview(false)
		MobileInput.clear_source_override()
		if _mobile_bottom_pad != null:
			_mobile_bottom_pad.custom_minimum_size = Vector2(0, 8)
		_device_option.add_item(_ui_text("Пульт не знайдено", "No controller found"))
		_device_option.disabled = true
		if _default_toggle != null:
			_default_toggle.disabled = true
		if _guid_label != null:
			_guid_label.visible = false
		if _status_label != null:
			_status_label.text = _ui_text("Підключіть USB-пульт, геймпад або RC-передавач. Без пульта працюють клавіатура та мишка.",
					"Connect a USB controller, gamepad, or RC transmitter. Keyboard and mouse work without one.")
		return

	_device_option.disabled = false
	if _guid_label != null:
		_guid_label.visible = true
	var preferred_virtual := ""
	if _source_explicit and not _active_virtual.is_empty():
		preferred_virtual = _active_virtual
	elif MobileInput.elrs_available():
		preferred_virtual = MobileInput.SOURCE_ELRS
	elif not _active_virtual.is_empty():
		preferred_virtual = _active_virtual
	var selected := 0
	var found := false
	for i in range(_device_entries.size()):
		var entry: Dictionary = _device_entries[i]
		var label := ""
		if String(entry["kind"]) == "virtual":
			var source_id := String(entry["source"])
			label = MobileInput.display_name(source_id)
			if not found and source_id == preferred_virtual:
				selected = i
				found = true
		else:
			var device_id: int = int(entry["device"])
			label = Input.get_joy_name(device_id)
			if not found and preferred_virtual.is_empty() \
					and Input.get_joy_guid(device_id) == Controls.active_controller_guid:
				selected = i
				found = true
		_device_option.add_item(label)
		_device_option.set_item_metadata(i, entry)
	_device_option.select(selected)
	_apply_entry(_device_entries[selected], false)


func _apply_entry(entry: Dictionary, user_choice: bool) -> void:
	if String(entry.get("kind", "physical")) == "virtual":
		_apply_virtual_source(String(entry.get("source", "")), user_choice)
		return
	_source_explicit = user_choice
	_active_virtual = ""
	_set_touch_preview(false)
	MobileInput.clear_source_override()
	_apply_active_device(int(entry.get("device", 0)))


func _apply_virtual_source(source_name_value: String, user_choice: bool) -> void:
	if user_choice:
		_source_explicit = true
	_active_virtual = source_name_value
	MobileInput.set_source(source_name_value)
	var touch_source := source_name_value == MobileInput.SOURCE_TOUCH
	_set_touch_preview(touch_source)
	if _mobile_bottom_pad != null:
		_mobile_bottom_pad.custom_minimum_size = Vector2(0, 330 if touch_source else 8)
	if _guid_label != null:
		_guid_label.visible = true
		_guid_label.text = "ELRS WiFi" if source_name_value == MobileInput.SOURCE_ELRS else "TOUCH"
	if _default_toggle != null:
		_default_toggle.disabled = true
	if _status_label != null:
		_status_label.text = _ui_text("Джерело: %s", "Source: %s") % MobileInput.source_name()
	_refresh_binding_labels()
	_refresh_axis_tags()


func _on_joy_connection_changed(_device: int, _connected_now: bool) -> void:
	_refresh_devices()
	_refresh_binding_labels()


func _on_device_selected(index: int) -> void:
	if index < 0 or index >= _device_entries.size():
		return
	_apply_entry(_device_entries[index], true)


func _apply_active_device(device: int) -> void:
	_active_virtual = ""
	if _mobile_bottom_pad != null:
		_mobile_bottom_pad.custom_minimum_size = Vector2(0, 8)
	Controls.update_active_device(device)
	Controls.load_input_map()
	Controls.refresh_stick_bindings()
	var guid := Input.get_joy_guid(device)
	if _guid_label != null:
		_guid_label.text = "GUID: %s" % guid
	if _default_toggle != null:
		_default_toggle.disabled = false
		_default_toggle.set_pressed_no_signal(guid == Controls.default_controller_guid)
	_refresh_binding_labels()
	_refresh_axis_tags()


func _on_default_toggled(pressed: bool) -> void:
	var index := _device_option.selected
	if index < 0 or index >= _device_entries.size():
		return
	var entry: Dictionary = _device_entries[index]
	if String(entry.get("kind", "")) != "physical":
		return
	var device: int = int(entry.get("device", 0))
	Controls.update_default_device(device if pressed else -1)


func _sync_virtual_options() -> void:
	var elrs := _elrs()
	if _virtual_invert_elrs != null:
		_virtual_invert_elrs.set_pressed_no_signal(
				elrs != null and bool(elrs.get("invert_roll")))
	if _virtual_invert_touch != null:
		var pad := get_node_or_null("/root/TouchControls")
		_virtual_invert_touch.set_pressed_no_signal(
				pad != null and bool(pad.get("invert_roll")))


func _on_virtual_invert_elrs(on: bool) -> void:
	var elrs := _elrs()
	if elrs == null:
		return
	elrs.set("invert_roll", on)
	elrs.call("save_settings")
	var state := _ui_text("увімкнено", "enabled") if on else _ui_text("вимкнено", "disabled")
	_message.text = _ui_text("Інверсію крену ELRS %s",
			"ELRS roll inversion %s") % state


func _on_virtual_invert_touch(on: bool) -> void:
	var pad := get_node_or_null("/root/TouchControls")
	if pad != null:
		pad.set("invert_roll", on)
	var settings := get_node_or_null("/root/GameSettings")
	if settings != null:
		var hud: Dictionary = settings.get("hud_config")
		hud["touch_invert_roll"] = on
		settings.call("save_hud_config")
	var state := _ui_text("увімкнено", "enabled") if on else _ui_text("вимкнено", "disabled")
	_message.text = _ui_text("Інверсію крену сенсора %s",
			"Touch roll inversion %s") % state


# ------------------------------------------------------------------ bindings

func _refresh_binding_labels() -> void:
	var virtual := _is_virtual()
	for entry in STICK_ROWS:
		var channel: String = entry[0]
		var value: Label = _stick_values.get(channel)
		if value == null:
			continue
		if virtual:
			value.text = _ui_text("Вісь %d (фіксовано)", "Axis %d (fixed)") \
					% _virtual_axis_for(channel)
			continue
		var binding: Dictionary = Controls.stick_bindings.get(channel, {})
		if binding.is_empty():
			value.text = _ui_text("не призначено", "Unassigned")
		else:
			value.text = "%s%s" % [Controls.joy_axis_string(binding["axis"]),
					_ui_text("  (інв.)", "  (inv.)") if binding["inverted"] else ""]
	for entry in ACTION_ROWS:
		var action: String = entry[0]
		var value: Label = _action_values.get(action)
		if value == null:
			continue
		if virtual:
			if _active_virtual == MobileInput.SOURCE_ELRS:
				var channel := int(_elrs().call("get_action_channel", action)) \
						if _elrs() != null else -1
				value.text = _ui_text("ELRS CH%d", "ELRS CH%d") % (channel + 1) \
						if channel >= 0 else _ui_text("не призначено", "Unassigned")
			else:
				value.text = _touch_action_label(action)
		else:
			value.text = Controls.describe_binding(action)
	_refresh_axis_tags()


func _elrs() -> Node:
	return get_node_or_null("/root/ElrsWifiInput")


func _touch_action_label(action: String) -> String:
	match action:
		"toggle_arm", "arm":
			return _ui_text("ЕКРАН: АРМ", "SCREEN: ARM")
		"deploy_payload":
			return _ui_text("ЕКРАН: СКИД", "SCREEN: DROP")
		"activate_payload":
			return _ui_text("ЕКРАН: ЗАСТ.", "SCREEN: USE")
		"respawn":
			return _ui_text("ЕКРАН: РЕСЕТ", "SCREEN: RESET")
		"cycle_flight_modes":
			return _ui_text("ЕКРАН: РЕЖИМ", "SCREEN: MODE")
		"cycle_video_mode":
			return _ui_text("ЕКРАН: ВІДЕО", "SCREEN: VIDEO")
		"pause_menu":
			return _ui_text("ЕКРАН: МЕНЮ", "SCREEN: MENU")
	return "—"


func _virtual_axis_for(channel: String) -> int:
	match channel:
		"roll":
			return 0
		"pitch":
			return 1
		"throttle":
			return 2
		"yaw":
			return 3
	return 0


func _refresh_axis_tags() -> void:
	if _is_virtual():
		var fixed := ["КРЕН", "ТАНГАЖ", "ГАЗ", "РИСКАННЯ"]
		var english := ["ROLL", "PITCH", "THR", "YAW"]
		for i in range(_axis_tags.size()):
			_axis_tags[i].text = "" if i >= fixed.size() else (
					english[i] if MenuUI.is_english() else fixed[i])
		return
	for i in range(_axis_tags.size()):
		var names := PackedStringArray()
		for channel in CHANNELS:
			var binding: Dictionary = Controls.stick_bindings.get(channel, {})
			if not binding.is_empty() and int(binding["axis"]) == i:
				names.append(MenuUI.translate_text(str(CHANNEL_LABELS[channel])))
		_axis_tags[i].text = " · ".join(names)


func _start_detect(kind: String, key: String) -> void:
	if _is_virtual():
		if _active_virtual == MobileInput.SOURCE_ELRS:
			if kind == "stick":
				_message.text = _ui_text(
						"Стіки ELRS — CH1–CH4. Зміна призначення — на пульті EdgeTX.",
						"ELRS sticks are CH1–CH4. Change their mapping on the EdgeTX radio.")
				return
			_start_virtual_detect(key)
		else:
			_message.text = _ui_text(
					"Сенсорні кнопки вже на екрані: АРМ, СКИД, ЗАСТ., РЕСЕТ, ВІДЕО, МЕНЮ.",
					"Touch buttons are already on screen: ARM, DROP, USE, RESET, VIDEO, MENU.")
		return
	if _detect == "stick" and _detect_channel == key:
		_cancel_detect()
		return
	if _detect == "action" and _detect_action == key:
		_cancel_detect()
		return
	_detect = kind
	_detect_channel = key if kind == "stick" else ""
	_detect_action = key if kind == "action" else ""
	_detect_initial_axes.clear()
	var dev := Controls.active_device
	if dev >= 0:
		for a in range(16):
			_detect_initial_axes[a] = Input.get_joy_axis(dev, a)
	if kind == "stick":
		_message.text = _ui_text("Рухайте стік: %s", "Move stick: %s") % _stick_hint(key)
	else:
		_message.text = _ui_text("Натисніть кнопку або перемкніть тумблер для «%s»", "Press a button or switch for “%s”") % _action_label(key)


func _start_virtual_detect(action: String) -> void:
	if _detect == "action" and _detect_action == action and _detect_virtual:
		_cancel_detect()
		return
	var elrs := _elrs()
	if elrs == null:
		return
	_detect = "action"
	_detect_channel = ""
	_detect_action = action
	_detect_initial_axes.clear()
	_detect_virtual = true
	_detect_virtual_time = 0.0
	var channels: PackedFloat32Array = elrs.get("channels")
	_detect_virtual_baseline = channels.duplicate()
	_message.text = _ui_text(
			"Перемкни тумблер або кнопку на Pocket (CH5–CH16) для «%s»",
			"Flip a switch or press a button on the Pocket (CH5–CH16) for “%s”") \
			% _action_label(action)


func _poll_virtual_detect(delta: float) -> void:
	_detect_virtual_time += delta
	var elrs := _elrs()
	if elrs == null or not bool(elrs.get("valid")):
		if _detect_virtual_time > 12.0:
			_cancel_detect()
			_message.text = _ui_text("Немає потоку ELRS — перевір Wi-Fi пульта.",
					"No ELRS stream — check the radio Wi-Fi.")
		return
	if _detect_virtual_time > 20.0:
		_cancel_detect()
		_message.text = _ui_text("Час очікування вичерпано. Спробуй ще раз.",
				"Timed out. Try again.")
		return
	var channels: PackedFloat32Array = elrs.get("channels")
	if channels.size() < 5:
		return
	var best_channel := -1
	var best_delta := 0.0
	var count := mini(channels.size(), 16)
	for i in range(4, count):
		var baseline := 16384.0
		if i < _detect_virtual_baseline.size():
			baseline = _detect_virtual_baseline[i]
		var change := absf(channels[i] - baseline)
		if change > best_delta:
			best_delta = change
			best_channel = i
	if best_channel >= 0 and best_delta > 8192.0:
		var action := _detect_action
		elrs.call("set_action_channel", action, best_channel)
		_finish_detect(_ui_text("Прив’язано: %s → ELRS CH%d",
				"Bound: %s → ELRS CH%d") % [_action_label(action), best_channel + 1])


func _cancel_detect() -> void:
	_detect = ""
	_detect_channel = ""
	_detect_action = ""
	_detect_initial_axes.clear()
	_detect_virtual = false
	_detect_virtual_time = 0.0
	_detect_virtual_baseline = PackedFloat32Array()
	_message.text = _ui_text("Скасовано", "Cancelled")


func _finish_detect(text: String) -> void:
	_detect = ""
	_detect_channel = ""
	_detect_action = ""
	_detect_initial_axes.clear()
	_detect_virtual = false
	_detect_virtual_time = 0.0
	_detect_virtual_baseline = PackedFloat32Array()
	_message.text = MenuUI.translate_text(text)
	_refresh_binding_labels()


func _clear_binding(kind: String, key: String) -> void:
	if _is_virtual():
		if _active_virtual == MobileInput.SOURCE_ELRS and kind == "action":
			var elrs := _elrs()
			if elrs != null:
				elrs.call("set_action_channel", key, -1)
				_refresh_binding_labels()
				_message.text = _ui_text("Прив’язку очищено", "Binding cleared")
				return
		_message.text = _ui_text("Сенсорні кнопки фіксовані; ELRS-прив’язки змінюються тут.",
				"Touch buttons are fixed; ELRS bindings are changed here.")
		return
	if kind == "stick":
		Controls.stick_bindings[key] = {}
		var pair: Array = Controls.STICK_ACTIONS.get(key, [])
		for action in pair:
			if InputMap.has_action(action):
				InputMap.action_erase_events(action)
		Controls.restore_keyboard_shortcuts()
	else:
		Controls.clear_action(key)
	Controls.save_bindings()
	_refresh_binding_labels()
	_message.text = _ui_text("Прив’язку очищено", "Binding cleared")


func _invert_binding(channel: String) -> void:
	if _is_virtual():
		_message.text = _ui_text("Інверсія ELRS/сенсора — в екрані «НАЛАШТ.» у польоті.", "ELRS/touch inversion is in the in-flight SETUP screen.")
		return
	if Controls.stick_bindings.get(channel, {}).is_empty():
		_message.text = _ui_text("Спершу призначте стік (кнопка «Авто»)", "Assign a stick first (use the Auto button)")
		return
	Controls.invert_stick(channel)
	Controls.save_bindings()
	_refresh_binding_labels()
	_message.text = _ui_text("Напрямок «%s» інвертовано", "Inverted direction for “%s”") % _stick_label(channel)


func _apply_radiomaster_preset() -> void:
	# Standard Mode 2 AETR on OpenTX/EdgeTX (Roll=0, Pitch=1, Throttle=2, Yaw=3)
	Controls.apply_stick("roll", 0, 1.0)
	Controls.apply_stick("pitch", 1, -1.0)
	Controls.apply_stick("throttle", 2, 1.0)
	Controls.apply_stick("yaw", 3, 1.0)
	Controls.apply_action_binding("toggle_arm", ControllerAction.Type.BUTTON, 0)
	Controls.apply_action_binding("deploy_payload", ControllerAction.Type.BUTTON, 1)
	Controls.apply_action_binding("respawn", ControllerAction.Type.BUTTON, 3)
	# HORIZON mode switch — left upper switch (commonly SA on EdgeTX/OpenTX).
	Controls.apply_action_binding("mode_horizon", ControllerAction.Type.BUTTON, 5)
	Controls.reset_stick_filters()
	for ch in Controls.STICK_ACTIONS.keys():
		Controls.stick_invert[ch] = false
	Controls.save_bindings()
	_refresh_binding_labels()
	_message.text = _ui_text("✓ Застосовано EdgeTX AETR (Mode 2). Перевірте стіки; за потреби — «КАЛІБРУВАННЯ СТІКІВ».", "✓ Applied EdgeTX AETR (Mode 2). Check the sticks; use STICK CALIBRATION if needed.")


func _apply_gamepad_preset() -> void:
	# Standard Xbox / PlayStation controller (Left stick: Yaw/Throttle, Right stick: Roll/Pitch)
	Controls.apply_stick("yaw", 0, 1.0)
	Controls.apply_stick("throttle", 1, -1.0)
	Controls.apply_stick("roll", 2, 1.0)
	Controls.apply_stick("pitch", 3, -1.0)
	Controls.apply_action_binding("toggle_arm", ControllerAction.Type.BUTTON, JOY_BUTTON_A)
	Controls.apply_action_binding("respawn", ControllerAction.Type.BUTTON, JOY_BUTTON_B)
	Controls.apply_action_binding("deploy_payload", ControllerAction.Type.BUTTON, JOY_BUTTON_X)
	Controls.apply_action_binding("activate_payload", ControllerAction.Type.BUTTON, JOY_BUTTON_Y)
	# HORIZON mode switch — left shoulder / L1 (LB on Xbox).
	Controls.apply_action_binding("mode_horizon", ControllerAction.Type.BUTTON, JOY_BUTTON_LEFT_SHOULDER)
	Controls.reset_stick_filters()
	for ch in Controls.STICK_ACTIONS.keys():
		Controls.stick_invert[ch] = false
	Controls.save_bindings()
	_refresh_binding_labels()
	_message.text = _ui_text("✓ Застосовано профіль: Стандартний геймпад (Xbox / PS)", "✓ Applied profile: Standard gamepad (Xbox / PlayStation)")


func _apply_keyboard_preset() -> void:
	for ch in CHANNELS:
		Controls.stick_bindings[ch] = {}
		var pair: Array = Controls.STICK_ACTIONS.get(ch, [])
		for action in pair:
			if InputMap.has_action(action):
				InputMap.action_erase_events(action)
	Controls.reset_stick_filters()
	for ch in Controls.STICK_ACTIONS.keys():
		Controls.stick_invert[ch] = false
	Controls.restore_keyboard_shortcuts()
	Controls.save_bindings()
	_refresh_binding_labels()
	_message.text = _ui_text("✓ Застосовано профіль: Клавіатура (W/S, A/D, Стрілки, Space, F, C, V, R)", "✓ Applied profile: Keyboard (W/S, A/D, arrows, Space, F, C, V, R)")


func _invert_all_sticks() -> void:
	if _is_virtual():
		_message.text = _ui_text("Інверсія ELRS/сенсора — в екрані «НАЛАШТ.» у польоті.", "ELRS/touch inversion is in the in-flight SETUP screen.")
		return
	for ch in Controls.STICK_ACTIONS.keys():
		Controls.stick_invert[ch] = not bool(Controls.stick_invert.get(ch, false))
	# The filter state belongs to the old direction; never let it lag behind.
	Controls.reset_stick_filters()
	Controls.save_bindings()
	_refresh_binding_labels()
	if _invert_state_label != null:
		_invert_state_label.text = _invert_state_text()
	var state := _ui_text("увімкнено", "enabled") if bool(Controls.stick_invert.get("throttle", false)) else _ui_text("вимкнено", "disabled")
	_message.text = _ui_text("Інверсію стіків %s" % state, "Stick inversion %s" % state)


func _invert_state_text() -> String:
	for ch in Controls.stick_invert.keys():
		if bool(Controls.stick_invert[ch]):
			return _ui_text("УВІМК.", "ON")
	return _ui_text("ВИМК.", "OFF")


func _stick_label(channel: String) -> String:
	for entry in STICK_ROWS:
		if entry[0] == channel:
			return MenuUI.translate_text(str(entry[1]))
	return channel


func _stick_hint(channel: String) -> String:
	match channel:
		"throttle":
			return _ui_text("газ — до упору вгору (максимум)", "throttle — fully up (maximum)")
		"yaw":
			return _ui_text("рискання — вправо", "yaw — right")
		"pitch":
			return _ui_text("тангаж — до себе (ніс догори)", "pitch — toward you (nose up)")
		"roll":
			return _ui_text("крен — вправо", "roll — right")
	return channel


func _action_label(action: String) -> String:
	for entry in ACTION_ROWS:
		if entry[0] == action:
			return MenuUI.translate_text(str(entry[1]))
	return action


# ------------------------------------------------------------------ input

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadMotion or event is InputEventJoypadButton:
		var device := (event as InputEventJoypadMotion).device if event is InputEventJoypadMotion \
				else (event as InputEventJoypadButton).device
		if Controls.active_device < 0 or device == Controls.active_device:
			_motion_stamp_usec = Time.get_ticks_usec()
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		if _detect != "":
			_cancel_detect()
		else:
			_go_back()
		return
	if _detect_virtual or _detect == "":
		return
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if Controls.active_device >= 0 and motion.device != Controls.active_device:
			return
		if not _detect_initial_axes.has(motion.axis):
			_detect_initial_axes[motion.axis] = motion.axis_value
			return
		var init_val: float = float(_detect_initial_axes[motion.axis])
		var delta: float = motion.axis_value - init_val
		if _detect == "stick" and absf(delta) > 0.45:
			var direction_sign: float = 1.0 if delta > 0.0 else -1.0
			Controls.apply_stick(_detect_channel, motion.axis, direction_sign)
			Controls.save_bindings()
			_finish_detect(_ui_text("Прив’язано: %s", "Bound: %s") % Controls.describe_stick(_detect_channel))
			accept_event()
		elif _detect == "action" and absf(delta) > 0.55:
			var low := 0.5 if motion.axis_value > 0.0 else -1.0
			var high := 1.0 if motion.axis_value > 0.0 else -0.5
			Controls.apply_action_binding(_detect_action, ControllerAction.Type.AXIS,
					motion.axis, low, high)
			Controls.save_bindings()
			_finish_detect(_ui_text("Прив’язано: %s", "Bound: %s") % Controls.describe_binding(_detect_action))
			accept_event()
	elif event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		if _detect == "action" and button.pressed:
			Controls.apply_action_binding(_detect_action, ControllerAction.Type.BUTTON,
					button.button_index)
			Controls.save_bindings()
			_finish_detect(_ui_text("Прив’язано: %s", "Bound: %s") % Controls.describe_binding(_detect_action))
			accept_event()


func _process(_delta: float) -> void:
	if not _active_virtual.is_empty() and MobileInput.source_override.is_empty():
		MobileInput.set_source(_active_virtual)
	if _is_virtual() and _active_virtual == MobileInput.SOURCE_TOUCH:
		var pad := get_node_or_null("/root/TouchControls")
		if pad != null and pad.has_method("is_menu_preview") \
				and not bool(pad.call("is_menu_preview")):
			_set_touch_preview(true)
	if _device_entries.is_empty() and MobileInput.available():
		_refresh_devices()
	elif not _source_explicit and MobileInput.elrs_available() \
			and _active_virtual != MobileInput.SOURCE_ELRS:
		_refresh_devices()
	if not _active_virtual.is_empty() \
			and not MobileInput.available_sources().has(_active_virtual):
		_refresh_devices()
	if _detect_virtual:
		if not _is_virtual() or _active_virtual != MobileInput.SOURCE_ELRS:
			_cancel_detect()
		else:
			_poll_virtual_detect(_delta)
	var values := {}
	for channel in CHANNELS:
		values[channel] = _channel_value(channel)

	if _radio != null:
		# Mode 2: throttle/pitch are vertical, yaw/roll horizontal. Throttle up
		# tilts the left stick away from the pilot, exactly like the real one.
		_radio.set_throttle_stick(-values["throttle"])
		_radio.set_yaw_stick(values["yaw"])
		_radio.set_pitch_stick(values["pitch"])
		_radio.set_roll_stick(values["roll"])

	for i in range(_channel_bars.size()):
		var value: float = values[CHANNELS[i]]
		_channel_bars[i].value = value
		_channel_values[i].text = "0.00" if absf(value) < 0.005 else "%+.2f" % value

	if _is_virtual():
		for i in range(_axis_bars.size()):
			var raw := MobileInput.axis(i) if i < 4 else 0.0
			_axis_bars[i].value = raw
			_axis_values[i].text = "0.00" if absf(raw) < 0.005 else "%+.2f" % raw
	elif Controls.active_device >= 0:
		for i in range(_axis_bars.size()):
			var raw := Input.get_joy_axis(Controls.active_device, i)
			_axis_bars[i].value = raw
			_axis_values[i].text = "0.00" if absf(raw) < 0.005 else "%+.2f" % raw
	else:
		for i in range(_axis_bars.size()):
			_axis_bars[i].value = 0.0
			_axis_values[i].text = "0.00"

	if _live_label != null:
		_live_label.text = _ui_text("ГАЗ %s   РИСК %s   ТАНГАЖ %s   КРЕН %s", "THR %s   YAW %s   PIT %s   ROL %s") % [
				_sign_text(values["throttle"], "↑", "↓"),
				_sign_text(values["yaw"], "→", "←"),
				_sign_text(values["pitch"], "↑", "↓"),
				_sign_text(values["roll"], "→", "←")]

	# Input-to-frame latency: time from the last joypad event to this frame.
	# At 120 FPS it should sit around one frame (~8 ms); anything much larger
	# means the app is bogged down or the controller polls slowly.
	if _latency_label != null:
		if _motion_stamp_usec >= 0:
			_input_latency_ms = float(Time.get_ticks_usec() - _motion_stamp_usec) / 1000.0
			_motion_stamp_usec = -1
			_has_motion_sample = true
		var source := _ui_text("пульт", "controller") if Controls.active_device >= 0 \
				else _ui_text("клавіатура", "keyboard")
		if _is_virtual():
			source = MobileInput.source_name()
		var latency_text := "%.1f" % _input_latency_ms if _has_motion_sample else "—"
		_latency_label.text = _ui_text(
				"Відгук: %s мс • джерело: %s • %d FPS",
				"Response: %s ms • source: %s • %d FPS") % [
					latency_text, source, int(Engine.get_frames_per_second())]

	if _status_label != null:
		if _is_virtual():
			_status_label.text = _ui_text("Джерело: %s", "Source: %s") % MobileInput.source_name()
		elif not Controls.stick_conflicts.is_empty():
			_status_label.text = _ui_text("⚠ Конфлікт осей: %s — перекалібруйте стіки.", "⚠ Axis conflict: %s — recalibrate sticks.") % ", ".join(PackedStringArray(Controls.stick_conflicts))
		elif Controls.active_device >= 0:
			_status_label.text = _ui_text("Активний пульт: %s", "Active controller: %s") % Input.get_joy_name(Controls.active_device)
		elif _connected.is_empty():
			_status_label.text = _ui_text("Без пульта працюють клавіатура та мишка.", "Keyboard and mouse are available without a controller.")


func _channel_value(channel: String) -> float:
	if _is_virtual():
		return clampf(MobileInput.axis(_virtual_axis_for(channel)), -1.0, 1.0)
	var value := Controls.physical_channel_value(channel)
	if is_nan(value):
		var positive: String = Controls.STICK_POSITIVE[channel]
		var pair: Array = Controls.STICK_ACTIONS[channel]
		var negative: String = pair[1] if positive == pair[0] else pair[0]
		value = Input.get_action_strength(positive) - Input.get_action_strength(negative)
	return clampf(value, -1.0, 1.0)


func _sign_text(value: float, positive: String, negative: String) -> String:
	if value > 0.05:
		return "%s%.2f" % [positive, value]
	if value < -0.05:
		return "%s%.2f" % [negative, absf(value)]
	return "—"


func _go_back() -> void:
	if embedded:
		back.emit()
		return
	get_tree().change_scene_to_file(MAIN_MENU)


func _go_calibration() -> void:
	if _is_virtual():
		MobileInput.set_source(_active_virtual)
		_keep_source_override = true
	else:
		MobileInput.clear_source_override()
	if embedded:
		# The pause menu hosts us inside OptionsMenu.  Swap the sub-screen in
		# place instead of changing the whole scene, otherwise calibrating
		# during a pause would destroy the running flight.
		var host := get_parent()
		while host != null and not host.has_method("_open_screen"):
			host = host.get_parent()
		if host != null:
			Global.calibration_return_scene = ""
			CALIBRATION_SCRIPT.return_scene = ""
			host.call_deferred("_open_screen", CALIBRATION_SCREEN)
			queue_free()
			return
	# Return to this screen after the wizard instead of dumping the pilot into
	# the main menu.
	Global.calibration_return_scene = "res://GUI/ControlsScreen.tscn"
	CALIBRATION_SCRIPT.return_scene = "res://GUI/ControlsScreen.tscn"
	get_tree().change_scene_to_file(CALIBRATION_SCREEN)
