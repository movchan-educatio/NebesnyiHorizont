extends MarginContainer


signal closed


@onready var panel := $PanelContainer
@onready var vbox := $PanelContainer/VBoxContainer

@onready var quad_grid := $PanelContainer/VBoxContainer/SettingsHBox/QuadScroll/Quad
@onready var angle_slider := $PanelContainer/VBoxContainer/SettingsHBox/QuadScroll/Quad/AngleSlider
@onready var angle_text := $PanelContainer/VBoxContainer/SettingsHBox/QuadScroll/Quad/AngleCurrent
@onready var weight_slider := $PanelContainer/VBoxContainer/SettingsHBox/QuadScroll/Quad/DryWeightSlider
@onready var weight_text := $PanelContainer/VBoxContainer/SettingsHBox/QuadScroll/Quad/DryWeightCurrent
@onready var batt_slider := $PanelContainer/VBoxContainer/SettingsHBox/QuadScroll/Quad/BatteryWeightSlider
@onready var batt_text := $PanelContainer/VBoxContainer/SettingsHBox/QuadScroll/Quad/BatteryWeightCurrent

@onready var rates := $PanelContainer/VBoxContainer/SettingsHBox/RatesScroll/Rates
@onready var rate_grid := $PanelContainer/VBoxContainer/SettingsHBox/RatesScroll/Rates/RateAdjust
@onready var pitch_slider := rate_grid.get_node("PitchSlider")
@onready var pitch_text := rate_grid.get_node("PitchRate")
@onready var pitch_expo_slider := rate_grid.get_node("PitchExpoSlider")
@onready var pitch_expo_text := rate_grid.get_node("PitchExpo")
@onready var roll_slider := rate_grid.get_node("RollSlider")
@onready var roll_text := rate_grid.get_node("RollRate")
@onready var roll_expo_slider := rate_grid.get_node("RollExpoSlider")
@onready var roll_expo_text := rate_grid.get_node("RollExpo")
@onready var yaw_slider := rate_grid.get_node("YawSlider")
@onready var yaw_text := rate_grid.get_node("YawRate")
@onready var yaw_expo_slider := rate_grid.get_node("YawExpoSlider")
@onready var yaw_expo_text := rate_grid.get_node("YawExpo")

@onready var rate_graph := $PanelContainer/VBoxContainer/SettingsHBox/RatesScroll/Rates/RateGraph

@onready var buttons := $PanelContainer/VBoxContainer/ButtonsHBox
@onready var reset_quad := $PanelContainer/VBoxContainer/ButtonsHBox/ButtonResetQuad
@onready var reset_rates := $PanelContainer/VBoxContainer/ButtonsHBox/ButtonResetRates
@onready var back := $PanelContainer/VBoxContainer/ButtonsHBox/ButtonBack

var _preset_buttons := {}
var _preset_desc: Label = null
var _summary_label: Label = null
var _header_left: Label = null
var _header_right: Label = null
var _title_label: Label = null
var _rates_title: Label = null


func _ui_text(uk: String, en: String) -> String:
	return en if MenuUI.is_english() else uk


func _ready() -> void:
	theme = MenuUI.theme()
	_apply_military_styling()

	var _discard = angle_slider.connect("value_changed", Callable(self, "_on_angle_changed"))
	_discard = weight_slider.connect("value_changed", Callable(self, "_on_weight_changed"))
	_discard = batt_slider.connect("value_changed", Callable(self, "_on_batt_changed"))

	_discard = pitch_slider.connect("value_changed", Callable(self, "_on_pitch_rate_changed"))
	_discard = pitch_expo_slider.connect("value_changed", Callable(self, "_on_pitch_expo_changed"))
	_discard = roll_slider.connect("value_changed", Callable(self, "_on_roll_rate_changed"))
	_discard = roll_expo_slider.connect("value_changed", Callable(self, "_on_roll_expo_changed"))
	_discard = yaw_slider.connect("value_changed", Callable(self, "_on_yaw_rate_changed"))
	_discard = yaw_expo_slider.connect("value_changed", Callable(self, "_on_yaw_expo_changed"))

	_discard = reset_quad.connect("pressed", Callable(self, "_on_reset_quad_pressed"))
	_discard = reset_rates.connect("pressed", Callable(self, "_on_reset_rates_pressed"))
	_discard = back.connect("pressed", Callable(self, "_on_back_pressed"))

	_build_flight_preset_strip()
	_build_left_telemetry_card()

	QuadSettings.load_quad_settings()
	update_QuadGUI()
	update_RatesGUI()
	rate_graph.set_rates(Vector3(pitch_slider.value, roll_slider.value, yaw_slider.value),
			Vector3(pitch_expo_slider.value, roll_expo_slider.value, yaw_expo_slider.value))
	MenuUI.localize_tree(self)


func _apply_military_styling() -> void:
	# Remove outer transparent margin so our Tactical C2 Backdrop covers 100% of the screen
	for side in ["left", "right", "top", "bottom"]:
		add_theme_constant_override("margin_%s" % side, 0)

	var bg := MenuUI.background(MenuUI.BG, false)
	add_child(bg)
	move_child(bg, 0)

	# Wrap PanelContainer inside a padded MarginContainer so it sits framed inside the C2 border
	var frame_margin := MarginContainer.new()
	var viewport_size := get_viewport_rect().size
	for side in ["left", "right"]:
		frame_margin.add_theme_constant_override("margin_%s" % side, minf(48.0, viewport_size.x * 0.025))
	for side in ["top", "bottom"]:
		frame_margin.add_theme_constant_override("margin_%s" % side, minf(36.0, viewport_size.y * 0.04))
	remove_child(panel)
	add_child(frame_margin)
	frame_margin.add_child(panel)

	var p_sb := MenuUI._style(MenuUI.PANEL, MenuUI.BORDER_HIGHLIGHT, 2, 3, 28, 22, 5)
	panel.add_theme_stylebox_override("panel", p_sb)
	vbox.add_theme_constant_override("separation", 20)
	var settings_hbox := vbox.get_node("SettingsHBox") as HBoxContainer
	var quad_scroll := settings_hbox.get_node("QuadScroll") as ScrollContainer
	var rates_scroll := settings_hbox.get_node("RatesScroll") as ScrollContainer
	for scroll in [quad_scroll, rates_scroll]:
		scroll.custom_minimum_size.x = 0.0
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_stretch_ratio = 1.0
	settings_hbox.add_theme_constant_override("separation", minf(32.0, viewport_size.x * 0.025))

	# Add Military C2 Top Strip above Title
	var header_strip := PanelContainer.new()
	var hs_sb := StyleBoxFlat.new()
	hs_sb.bg_color = MenuUI.PANEL_HEADER
	hs_sb.border_color = MenuUI.WARN_AMBER
	hs_sb.border_width_left = 4
	hs_sb.border_width_bottom = 1
	hs_sb.content_margin_left = 14
	hs_sb.content_margin_right = 14
	hs_sb.content_margin_top = 6
	hs_sb.content_margin_bottom = 6
	header_strip.add_theme_stylebox_override("panel", hs_sb)
	var hs_row := HBoxContainer.new()
	header_strip.add_child(hs_row)
	_header_left = MenuUI.body(_ui_text("НАЛАШТУВАННЯ ПОЛЬОТУ · FPV", "FLIGHT SETTINGS · FPV"), 14, MenuUI.WARN_AMBER)
	_header_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hs_row.add_child(_header_left)
	_header_right = MenuUI.body(_ui_text("КОНФІГУРАЦІЯ ПОЛЬОТНОГО КОНТРОЛЕРА", "FLIGHT CONTROLLER CONFIGURATION"), 13, MenuUI.MIL_GREEN_LIGHT)
	hs_row.add_child(_header_right)
	vbox.add_child(header_strip)
	vbox.move_child(header_strip, 0)

	_title_label = vbox.get_node_or_null("Title") as Label
	if _title_label != null:
		_title_label.text = _ui_text("ПАРАМЕТРИ ДРОНА", "DRONE SETTINGS")
		_title_label.add_theme_font_size_override("font_size", 28)
		_title_label.add_theme_color_override("font_color", MenuUI.FPV_TEXT)

	# Translate Left Grid Labels
	var angle_lbl := quad_grid.get_node_or_null("AngleLabel") as Label
	if angle_lbl != null:
		angle_lbl.text = _ui_text("Кут камери FPV:", "FPV camera angle:")
		angle_lbl.add_theme_color_override("font_color", MenuUI.TEXT)
	var dry_lbl := quad_grid.get_node_or_null("DryWeightLabel") as Label
	if dry_lbl != null:
		dry_lbl.text = _ui_text("Суха маса борту:", "Dry aircraft mass:")
		dry_lbl.add_theme_color_override("font_color", MenuUI.TEXT)
	var batt_lbl := quad_grid.get_node_or_null("BatteryWeightLabel") as Label
	if batt_lbl != null:
		batt_lbl.text = _ui_text("Маса акумулятора:", "Battery mass:")
		batt_lbl.add_theme_color_override("font_color", MenuUI.TEXT)

	quad_grid.add_theme_constant_override("h_separation", 24)
	quad_grid.add_theme_constant_override("v_separation", 18)
	rate_grid.add_theme_constant_override("h_separation", 6)
	rate_grid.add_theme_constant_override("v_separation", 10)
	for slider_name in ["PitchSlider", "RollSlider", "YawSlider"]:
		(rate_grid.get_node(slider_name) as HSlider).custom_minimum_size.x = 130.0
	for slider_name in ["PitchExpoSlider", "RollExpoSlider", "YawExpoSlider"]:
		(rate_grid.get_node(slider_name) as HSlider).custom_minimum_size.x = 70.0
	for label_name in ["PitchRate", "RollRate", "YawRate"]:
		(rate_grid.get_node(label_name) as Label).custom_minimum_size.x = 82.0
	for label_name in ["PitchExpo", "RollExpo", "YawExpo"]:
		(rate_grid.get_node(label_name) as Label).custom_minimum_size.x = 74.0

	# Translate Right Rates Labels
	_rates_title = rates.get_node_or_null("RatesLabel") as Label
	if _rates_title != null:
		_rates_title.text = _ui_text("ПРОФІЛЬ РЕЙТІВ ТА ЕКСПО", "RATES & EXPO PROFILE")
		_rates_title.add_theme_font_size_override("font_size", 16)
		_rates_title.add_theme_color_override("font_color", MenuUI.FPV_GREEN)

	var p_lbl := rate_grid.get_node_or_null("PitchLabel") as Label
	if p_lbl != null:
		p_lbl.text = "Тангаж"
		p_lbl.add_theme_color_override("font_color", Color("ff6e59"))
	var r_lbl := rate_grid.get_node_or_null("RollLabel") as Label
	if r_lbl != null:
		r_lbl.text = "Крен"
		r_lbl.add_theme_color_override("font_color", MenuUI.ACCENT)
	var y_lbl := rate_grid.get_node_or_null("YawLabel") as Label
	if y_lbl != null:
		y_lbl.text = "Рискання"
		y_lbl.add_theme_color_override("font_color", Color("6bc2ff"))

	# Translate bottom action buttons
	buttons.add_theme_constant_override("separation", 18)
	reset_quad.text = _ui_text("⟲  СКИНУТИ ПАРАМЕТРИ БОРТУ", "⟲  RESET AIRCRAFT SETTINGS")
	reset_quad.custom_minimum_size = Vector2(280, 46)
	reset_rates.text = _ui_text("⟲  СКИНУТИ РЕЙТИ", "⟲  RESET RATES")
	reset_rates.custom_minimum_size = Vector2(230, 46)
	back.text = _ui_text("←  НАЗАД ДО ПАУЗИ", "←  BACK TO PAUSE")
	back.custom_minimum_size = Vector2(240, 46)


func _build_left_telemetry_card() -> void:
	var quad_scroll := quad_grid.get_parent()
	if quad_scroll == null:
		return
	var left_vbox := VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_vbox.add_theme_constant_override("separation", 18)

	quad_scroll.remove_child(quad_grid)
	quad_scroll.add_child(left_vbox)

	left_vbox.add_child(MenuUI.section("ФІЗИЧНІ ПАРАМЕТРИ БОРТУ", "БОРТ"))
	left_vbox.add_child(quad_grid)

	left_vbox.add_child(MenuUI.section("ТАКТИКО-ТЕХНІЧНЕ ЗВЕДЕННЯ (ТТХ)", "ТТХ"))
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", MenuUI._style(MenuUI.CARD, MenuUI.BORDER, 1, 2, 18, 14, 4))
	left_vbox.add_child(card)

	_summary_label = MenuUI.body("", 15, MenuUI.TEXT)
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(_summary_label)
	_refresh_summary_card()


func _refresh_summary_card() -> void:
	if _summary_label == null:
		return
	var p := DroneCatalog.preset(Global.drone_preset)
	var dry_g := int(round(QuadSettings.dry_weight * 1000.0))
	var batt_g := int(round(QuadSettings.battery_weight * 1000.0))
	var pay_g := int(round(QuadSettings.payload_weight * 1000.0))
	var total_g := dry_g + batt_g + pay_g
	var is_en := MenuUI.is_english()
	var drone_name := str(p.get("name_en", MenuUI.translate_text(str(p.get("name", "UAV"))))) if is_en else str(p.get("name", "БПЛА"))
	var drone_tag := MenuUI.translate_text(str(p.get("tag", "FPV"))) if is_en else str(p.get("tag", "FPV"))
	var drop_info := "Kamikaze / no drop" if is_en else "Камікадзе / без скиду"
	if not bool(p.get("combat", false)):
		drop_info = "Training / civilian" if is_en else "Тренувальний / цивільний"
	elif is_en:
		drop_info = str(p.get("drop_name_en", "Kamikaze payload" if not bool(p.get("has_drop", false)) else "Payload drop"))
	else:
		drop_info = str(p.get("drop_name", drop_info))
	if is_en:
		_summary_label.text = (
			"ACTIVE AIRCRAFT:  %s  [%s]\n"
			+ "DRY MASS:  %d g   •   BATTERY:  %d g   •   PAYLOAD:  %d g\n"
			+ "TAKEOFF MASS:  %d g (%.2f kg)\n"
			+ "MOTORS:  %d KV   •   PROPS:  %.1f\" × %.1f (%d blades)\n"
			+ "PAYLOAD PROFILE:  %s"
		) % [drone_name, drone_tag, dry_g, batt_g, pay_g, total_g,
			float(total_g) / 1000.0, int(p.get("kv", 1700)), float(p.get("prop_d", 7.0)),
			float(p.get("prop_p", 4.0)), int(p.get("blades", 3)), drop_info]
	else:
		_summary_label.text = (
			"АКТИВНИЙ БОРТ:  %s  [%s]\n"
			+ "СУХА МАСА:  %d г   •   АКБ:  %d г   •   БЧ:  %d г\n"
			+ "ПОВНА ЗЛІТНА МАСА:  %d г (%.2f кг)\n"
			+ "МОТОРИ:  %d KV   •   ПРОПЕЛЕРИ:  %.1f\" × %.1f (%d лоп.)\n"
			+ "БОЙОВЕ ОСНАЩЕННЯ:  %s"
		) % [drone_name, drone_tag, dry_g, batt_g, pay_g, total_g,
			float(total_g) / 1000.0, int(p.get("kv", 1700)), float(p.get("prop_d", 7.0)),
			float(p.get("prop_p", 4.0)), int(p.get("blades", 3)), drop_info]


func _build_flight_preset_strip() -> void:
	if rates == null:
		return
	var strip := VBoxContainer.new()
	strip.add_theme_constant_override("separation", 6)
	strip.add_child(MenuUI.section("ПРЕСЕТ ПОЛЬОТУ", "РЕЖИМ"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)

	for p in QuadSettings.FLIGHT_PRESETS:
		var id := str(p["id"])
		var btn := Button.new()
		btn.text = MenuUI.translate_text(str(p["name"]))
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(0, 34)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 13)
		btn.pressed.connect(_on_flight_preset_pressed.bind(id))
		grid.add_child(btn)
		_preset_buttons[id] = btn
	strip.add_child(grid)

	_preset_desc = Label.new()
	_preset_desc.add_theme_font_size_override("font_size", 12)
	_preset_desc.add_theme_color_override("font_color", MenuUI.FPV_MUTED)
	_preset_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preset_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip.add_child(_preset_desc)

	rates.add_child(strip)
	rates.move_child(strip, 1)


func _on_flight_preset_pressed(id: String) -> void:
	QuadSettings.apply_flight_preset(id)
	update_RatesGUI()
	save_quad_settings()


func _refresh_preset_buttons() -> void:
	for id in _preset_buttons.keys():
		var btn: Button = _preset_buttons[id]
		btn.set_pressed_no_signal(id == QuadSettings.flight_preset)
	if _preset_desc == null:
		return
	var idx := QuadSettings.flight_preset_index()
	if idx >= 0:
		var p: Dictionary = QuadSettings.FLIGHT_PRESETS[idx]
		var preset_name := MenuUI.translate_text(str(p["name"]))
		var preset_desc := MenuUI.translate_text(str(p["desc"]))
		_preset_desc.text = _ui_text(
			"%s: %s (нахил %d°, ліміт %.1f рад/с)",
			"%s: %s (bank %d°, rate limit %.1f rad/s)") % [
				preset_name, preset_desc, int(p["bank"]), float(p["rate_limit"])]
	else:
		_preset_desc.text = _ui_text("ІНДИВІДУАЛЬНИЙ ПРОФІЛЬ: ручне налаштування рейтів та експоненти",
			"CUSTOM PROFILE: adjust rates and expo manually")


func _input(event: InputEvent) -> void:
	if event.is_action("ui_cancel") and event.is_pressed() and not event.is_echo() and visible:
		accept_event()
		_on_back_pressed()


func show_menu(b: bool) -> void:
	visible = b
	if visible:
		_refresh_language_ui()
		_refresh_summary_card()
		back.grab_focus()


func _refresh_language_ui() -> void:
	if _header_left != null:
		_header_left.text = _ui_text("НАЛАШТУВАННЯ ПОЛЬОТУ · FPV", "FLIGHT SETTINGS · FPV")
	if _header_right != null:
		_header_right.text = _ui_text("КОНФІГУРАЦІЯ ПОЛЬОТНОГО КОНТРОЛЕРА", "FLIGHT CONTROLLER CONFIGURATION")
	if _title_label != null:
		_title_label.text = _ui_text("НАЛАШТУВАННЯ БОРТУ ТА ПРОФІЛЮ РЕЙТІВ", "AIRCRAFT & RATE PROFILE")
	if _rates_title != null:
		_rates_title.text = _ui_text("[ ПРОФІЛЬ КУТОВИХ ШВИДКОСТЕЙ (RATES / EXPO) ]", "[ ANGULAR RATE PROFILE (RATES / EXPO) ]")
	reset_quad.text = _ui_text("⟲  СКИНУТИ ПАРАМЕТРИ БОРТУ", "⟲  RESET AIRCRAFT SETTINGS")
	reset_rates.text = _ui_text("⟲  СКИНУТИ РЕЙТИ", "⟲  RESET RATES")
	back.text = _ui_text("←  НАЗАД ДО ПАУЗИ", "←  BACK TO PAUSE")
	MenuUI.localize_tree(self)
	update_QuadGUI()
	update_RatesGUI()


func update_QuadGUI() -> void:
	angle_slider.value = QuadSettings.angle
	angle_text.text = "%d°" % [angle_slider.value]
	weight_slider.value = QuadSettings.dry_weight * 1000.0
	weight_text.text = "%d %s" % [weight_slider.value, _ui_text("г", "g")]
	batt_slider.value = QuadSettings.battery_weight * 1000.0
	batt_text.text = "%d %s" % [batt_slider.value, _ui_text("г", "g")]
	_refresh_summary_card()


func update_RatesGUI() -> void:
	pitch_slider.value = QuadSettings.rate_pitch
	pitch_text.text = "%d %s" % [pitch_slider.value, _ui_text("град/с", "deg/s")]
	pitch_expo_slider.value = QuadSettings.expo_pitch
	pitch_expo_text.text = "%s %3.2f" % [_ui_text("Експо", "Expo"), pitch_expo_slider.value]
	roll_slider.value = QuadSettings.rate_roll
	roll_text.text = "%d %s" % [roll_slider.value, _ui_text("град/с", "deg/s")]
	roll_expo_slider.value = QuadSettings.expo_roll
	roll_expo_text.text = "%s %3.2f" % [_ui_text("Експо", "Expo"), roll_expo_slider.value]
	yaw_slider.value = QuadSettings.rate_yaw
	yaw_text.text = "%d %s" % [yaw_slider.value, _ui_text("град/с", "deg/s")]
	yaw_expo_slider.value = QuadSettings.expo_yaw
	yaw_expo_text.text = "%s %3.2f" % [_ui_text("Експо", "Expo"), yaw_expo_slider.value]
	_refresh_preset_buttons()


func save_quad_settings() -> void:
	QuadSettings.save_quad_settings()
	_refresh_summary_card()


func _on_angle_changed(value: float) -> void:
	QuadSettings.angle = int(value)
	angle_text.text = "%d°" % [angle_slider.value]
	save_quad_settings()


func _on_weight_changed(value: float) -> void:
	QuadSettings.dry_weight = value / 1000.0
	weight_text.text = "%d г" % [weight_slider.value]
	save_quad_settings()


func _on_batt_changed(value: float) -> void:
	QuadSettings.battery_weight = value / 1000.0
	batt_text.text = "%d г" % [batt_slider.value]
	save_quad_settings()


func _mark_custom_rates() -> void:
	QuadSettings.flight_preset = "custom"
	QuadSettings.custom_rates = true
	_refresh_preset_buttons()


func _on_pitch_rate_changed(value: float) -> void:
	QuadSettings.rate_pitch = int(value)
	pitch_text.text = "%d град/с" % [pitch_slider.value]
	rate_graph.set_rates(Vector3(value, roll_slider.value, yaw_slider.value),
			Vector3(pitch_expo_slider.value, roll_expo_slider.value, yaw_expo_slider.value))
	_mark_custom_rates()
	save_quad_settings()


func _on_pitch_expo_changed(value: float) -> void:
	QuadSettings.expo_pitch = value
	pitch_expo_text.text = "Експо %3.2f" % [pitch_expo_slider.value]
	rate_graph.set_rates(Vector3(pitch_slider.value, roll_slider.value, yaw_slider.value),
			Vector3(value, roll_expo_slider.value, yaw_expo_slider.value))
	_mark_custom_rates()
	save_quad_settings()


func _on_roll_rate_changed(value: float) -> void:
	QuadSettings.rate_roll = int(value)
	roll_text.text = "%d град/с" % [roll_slider.value]
	rate_graph.set_rates(Vector3(pitch_slider.value, value, yaw_slider.value),
			Vector3(pitch_expo_slider.value, roll_expo_slider.value, yaw_expo_slider.value))
	_mark_custom_rates()
	save_quad_settings()


func _on_roll_expo_changed(value: float) -> void:
	QuadSettings.expo_roll = value
	roll_expo_text.text = "Експо %3.2f" % [roll_expo_slider.value]
	rate_graph.set_rates(Vector3(pitch_slider.value, roll_slider.value, yaw_slider.value),
			Vector3(pitch_expo_slider.value, value, yaw_expo_slider.value))
	_mark_custom_rates()
	save_quad_settings()


func _on_yaw_rate_changed(value: float) -> void:
	QuadSettings.rate_yaw = int(value)
	yaw_text.text = "%d град/с" % [yaw_slider.value]
	rate_graph.set_rates(Vector3(pitch_slider.value, roll_slider.value, value),
			Vector3(pitch_expo_slider.value, roll_expo_slider.value, yaw_expo_slider.value))
	_mark_custom_rates()
	save_quad_settings()


func _on_yaw_expo_changed(value: float) -> void:
	QuadSettings.expo_yaw = value
	yaw_expo_text.text = "Експо %3.2f" % [yaw_expo_slider.value]
	rate_graph.set_rates(Vector3(pitch_slider.value, roll_slider.value, yaw_slider.value),
			Vector3(pitch_expo_slider.value, roll_expo_slider.value, value))
	_mark_custom_rates()
	save_quad_settings()


func _on_reset_quad_pressed() -> void:
	QuadSettings.reset_quad()
	update_QuadGUI()
	save_quad_settings()


func _on_reset_rates_pressed() -> void:
	QuadSettings.reset_rates()
	update_RatesGUI()
	save_quad_settings()


func _on_back_pressed() -> void:
	show_menu(false)
	emit_signal("closed")
