## "Other settings": master volume, intro video sound and the HUD element
## toggles. Everything is applied live and saved through the existing
## Audio / GameSettings autoloads.
extends Control

const MAIN_MENU := "res://GUI/MainMenu.tscn"

const HUD_TOGGLES := [
	["horizon", "Штучний горизонт"],
	["ladder", "Шкала тангажу"],
	["speed", "Швидкість"],
	["altitude", "Висота"],
	["heading", "Курс"],
	["sticks", "Позиція стіків"],
	["rpm", "Оберти моторів"],
	["osd", "Увесь OSD (H)"],
	["fpv_rig", "FPV-обвіс: вусики + бомба (J)"],
]

const SIM_TOGGLES := [
	["link_limit", "Обмеження зв'язку (дальність/рельєф)",
			"Вимкніть, щоб літати без втрати відео та керування на будь-якій відстані."],
	["reb_zones", "Зони РЕБ (глушіння)",
			"Ворожі антени глушать відео та керування. Потребує обмежень зв'язку."],
	["wind_sim", "Імітація вітру та поривів",
			"Вимкніть, щоб прибрати знос дрона вітром, пориви й турбулентність."],
	["angle_mode", "Режим Angle (стабілізація)",
			"Дозволити самовирівнювання. Якщо вимкнути Angle і Acro, лишиться HORIZON."],
	["acro_mode", "Режим Acro (ручний)",
			"Дозволити ручний режим. Якщо вимкнути Angle і Acro, лишиться HORIZON."],
	["infinite_battery", "Нескінченна батарея (тренажер)",
			"Батарея не розряджається під час польоту."],
]

signal back
var embedded := false

var _volume_slider: HSlider
var _volume_label: Label
var _fps_slider: HSlider
var _fps_label: Label
var _sim_toggles: Dictionary = {}
var _profile_btns: Dictionary = {}


func _ready() -> void:
	theme = MenuUI.theme()
	GameSettings.load_hud_config()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_build()


func _build() -> void:
	add_child(MenuUI.background(MenuUI.BG))
	var viewport_size := get_viewport_rect().size

	var center := CenterContainer.new()
	MenuUI.full_rect(center)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(minf(900.0, viewport_size.x - 32.0), 0)
	panel.add_theme_stylebox_override("panel", MenuUI.feel_style(
			MenuUI.PANEL, MenuUI.BORDER_HIGHLIGHT, 2, 12, 20, 16))
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_%s" % side, minf(24.0, viewport_size.x * 0.03))
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	margin.add_child(layout)

	# A plain Control caps the scroll view without forcing the panel to the full
	# window height when the content is short.  The action bar stays outside the
	# scroll view so it can never overlap the panel frame.
	var scroll_holder := Control.new()
	scroll_holder.custom_minimum_size = Vector2(0, 240)
	scroll_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll_holder)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll_holder.add_child(scroll)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	box.add_child(MenuUI.title("ІНШІ НАЛАШТУВАННЯ", 36))

	box.add_child(MenuUI.section("ЗВУК"))
	var volume_row := HBoxContainer.new()
	volume_row.add_theme_constant_override("separation", 16)
	volume_row.add_child(MenuUI.body("Загальна гучність", 19))
	_volume_slider = HSlider.new()
	_volume_slider.min_value = 0
	_volume_slider.max_value = 100
	_volume_slider.step = 1
	_volume_slider.value = round(float(Audio.audio_settings["master_volume"]) * 100.0)
	_volume_slider.custom_minimum_size = Vector2(300, 28)
	_volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_volume_slider.value_changed.connect(_on_volume_changed)
	volume_row.add_child(_volume_slider)
	_volume_label = MenuUI.body("%d%%" % int(_volume_slider.value), 18, MenuUI.MUTED)
	_volume_label.custom_minimum_size = Vector2(64, 0)
	_volume_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	volume_row.add_child(_volume_label)
	box.add_child(volume_row)

	var video_audio := CheckButton.new()
	video_audio.text = "Звук у вступному відео"
	video_audio.button_pressed = bool(Global.menu_settings["video_audio"])
	video_audio.toggled.connect(_on_video_audio_toggled)
	box.add_child(video_audio)

	box.add_child(MenuUI.hline())
	box.add_child(MenuUI.section("ТРЕНАЖЕР / СИМУЛЯЦІЯ"))
	var sim_hint := MenuUI.body(
			"Полегшення діють одразу, у тому числі під час польоту.", 13, MenuUI.MUTED)
	box.add_child(sim_hint)

	var profile_row := HBoxContainer.new()
	profile_row.add_theme_constant_override("separation", 8)
	profile_row.add_child(MenuUI.body("Профіль реалізму:", 16))
	for entry in [["АРКАДА", GameSettings.REALISM_ARCADE],
			["БОЙОВИЙ РЕАЛІЗМ", GameSettings.REALISM_COMBAT]]:
		var profile_btn := MenuUI.button(str(entry[0]), 34)
		profile_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		profile_btn.toggle_mode = true
		profile_btn.pressed.connect(_on_profile_selected.bind(str(entry[1])))
		_profile_btns[str(entry[1])] = profile_btn
		profile_row.add_child(profile_btn)
	box.add_child(profile_row)

	var sim_grid := GridContainer.new()
	sim_grid.columns = 1 if viewport_size.x < 1000.0 else 2
	sim_grid.add_theme_constant_override("h_separation", 40)
	sim_grid.add_theme_constant_override("v_separation", 6)
	for entry in SIM_TOGGLES:
		var key: String = entry[0]
		var toggle := CheckButton.new()
		toggle.text = entry[1]
		toggle.tooltip_text = entry[2]
		toggle.button_pressed = bool(GameSettings.hud_config.get(key, true))
		toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		toggle.toggled.connect(_on_sim_toggled.bind(key))
		_sim_toggles[key] = toggle
		sim_grid.add_child(toggle)
	box.add_child(sim_grid)
	_refresh_sim_controls()

	box.add_child(MenuUI.hline())
	box.add_child(MenuUI.section("ІНТЕРФЕЙС (HUD)"))

	var fps_row := HBoxContainer.new()
	fps_row.add_theme_constant_override("separation", 16)
	var fps_toggle := CheckButton.new()
	fps_toggle.text = "Лічильник FPS"
	fps_toggle.button_pressed = bool(GameSettings.hud_config["fps"] > 0)
	fps_toggle.toggled.connect(_on_fps_toggled)
	fps_row.add_child(fps_toggle)
	_fps_slider = HSlider.new()
	_fps_slider.min_value = 5
	_fps_slider.max_value = 60
	_fps_slider.step = 1
	_fps_slider.value = max(5, int(GameSettings.hud_config["fps"]))
	_fps_slider.custom_minimum_size = Vector2(240, 28)
	_fps_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fps_slider.value_changed.connect(_on_fps_rate_changed)
	fps_row.add_child(_fps_slider)
	_fps_label = MenuUI.body("%d" % int(_fps_slider.value), 18, MenuUI.MUTED)
	_fps_label.custom_minimum_size = Vector2(48, 0)
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fps_row.add_child(_fps_label)
	box.add_child(fps_row)

	var grid := GridContainer.new()
	grid.columns = 1 if viewport_size.x < 1000.0 else 2
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 6)
	for entry in HUD_TOGGLES:
		var key: String = entry[0]
		var toggle := CheckButton.new()
		toggle.text = entry[1]
		toggle.button_pressed = bool(GameSettings.hud_config[key])
		toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		toggle.toggled.connect(_on_hud_toggled.bind(key))
		grid.add_child(toggle)
	box.add_child(grid)

	box.add_child(MenuUI.spacer(4))
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	var reset := MenuUI.button("СКИНУТИ HUD", 48)
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset.pressed.connect(_on_reset_hud)
	bottom.add_child(reset)
	var back := MenuUI.button("←  НАЗАД", 48)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(_go_back)
	bottom.add_child(back)
	for b in [reset, back]:
		b.add_theme_stylebox_override("focus", MenuUI.feel_style(
				MenuUI.BUTTON_BG, MenuUI.BUTTON_BG, 1, 4, 12, 6))
	layout.add_child(bottom)
	var card_height := minf(box.get_combined_minimum_size().y,
			maxf(240.0, viewport_size.y - 180.0))
	scroll_holder.custom_minimum_size.y = card_height
	back.grab_focus()
	MenuUI.localize_tree(self)


func _on_volume_changed(value: float) -> void:
	_volume_label.text = "%d%%" % int(value)
	Audio.audio_settings["master_volume"] = value / 100.0
	Audio.update_master_volume()
	Audio.save_audio_settings()


func _on_video_audio_toggled(pressed: bool) -> void:
	Global.menu_settings["video_audio"] = pressed
	Global.save_menu_settings()


func _on_fps_toggled(pressed: bool) -> void:
	GameSettings.hud_config["fps"] = int(_fps_slider.value) if pressed else 0
	GameSettings.save_hud_config()
	_fps_slider.editable = pressed


func _on_fps_rate_changed(value: float) -> void:
	_fps_label.text = "%d" % int(value)
	if bool(GameSettings.hud_config["fps"] > 0):
		GameSettings.hud_config["fps"] = int(value)
		GameSettings.save_hud_config()


func _on_hud_toggled(pressed: bool, key: String) -> void:
	GameSettings.hud_config[key] = pressed
	GameSettings.save_hud_config()


func _on_sim_toggled(pressed: bool, key: String) -> void:
	GameSettings.hud_config[key] = pressed
	GameSettings.refresh_realism_profile()
	GameSettings.save_hud_config()
	_refresh_sim_controls()


func _on_profile_selected(profile: String) -> void:
	if GameSettings.apply_realism_profile(profile):
		_refresh_sim_controls()


func _refresh_sim_controls() -> void:
	var hc := GameSettings.hud_config
	for key in _sim_toggles.keys():
		var toggle: CheckButton = _sim_toggles[key]
		toggle.set_pressed_no_signal(bool(hc.get(key, true)))
	var link_on := bool(hc.get("link_limit", false))
	var reb_toggle: CheckButton = _sim_toggles.get("reb_zones")
	if reb_toggle != null:
		reb_toggle.disabled = not link_on
		reb_toggle.modulate = Color.WHITE if link_on else Color(1.0, 1.0, 1.0, 0.62)
		reb_toggle.tooltip_text = "Ворожі антени глушать відео та керування." if link_on \
				else "Спочатку увімкніть обмеження зв'язку (дальність/рельєф)."
	var profile := String(hc.get("realism_profile", GameSettings.REALISM_CUSTOM))
	for preset in _profile_btns.keys():
		var btn: Button = _profile_btns[preset]
		var active := profile == String(preset)
		btn.set_pressed_no_signal(active)
		btn.add_theme_stylebox_override("normal", MenuUI.feel_style(
				MenuUI.BUTTON_ACTIVE if active else MenuUI.BUTTON_BG,
				MenuUI.FPV_GREEN if active else MenuUI.BORDER,
				2 if active else 1, 1, 8, 4))
		btn.add_theme_stylebox_override("hover", MenuUI.feel_style(
				MenuUI.BUTTON_HOVER, MenuUI.FPV_GREEN, 2, 1, 8, 4))
		btn.add_theme_stylebox_override("pressed", MenuUI.feel_style(
				MenuUI.BUTTON_ACTIVE, MenuUI.FPV_GREEN, 2, 1, 8, 4))
		btn.add_theme_color_override("font_color",
				MenuUI.BUTTON_ACTIVE_TEXT if active else MenuUI.BUTTON_TEXT)
		btn.add_theme_color_override("font_hover_color", MenuUI.BUTTON_TEXT)


func _on_reset_hud() -> void:
	GameSettings.hud_config["fps"] = 20
	for key in ["crosshair", "horizon", "speed", "altitude", "heading", "osd"]:
		GameSettings.hud_config[key] = true
	for key in ["ladder", "sticks", "rpm", "fpv_rig"]:
		GameSettings.hud_config[key] = false
	GameSettings.save_hud_config()
	get_tree().reload_current_scene()


func _go_back() -> void:
	if embedded:
		back.emit()
		return
	get_tree().change_scene_to_file(MAIN_MENU)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		_go_back()
