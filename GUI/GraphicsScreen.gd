## Graphics settings screen. Writes straight into the Graphics autoload so the
## values are applied live and persisted to user://config_G3/Graphics.cfg.
extends Control

const MAIN_MENU := "res://GUI/MainMenu.tscn"

const QUALITY_ITEMS := ["Низька (120+ FPS)", "Середня (баланс)", "Висока (максимум якості)"]
const FPV_MODE_ITEMS := ["Аналог 5.8 GHz", "Digital O3 / Avatar", "FLIR White-Hot", "FLIR Black-Hot"]
const WINDOW_ITEMS := ["Повноекранний", "Повноекранний (вікно)", "Вікно", "Вікно без рамки"]
const RESOLUTION_VALUES := [100, 85, 75, 50]
const RESOLUTION_ITEMS := ["100%", "85%", "75%", "50%"]
const MSAA_ITEMS := ["Вимкнено", "2x", "4x", "8x", "16x"]
const SHADOWS_ITEMS := ["Вимкнено", "Низька", "Середня", "Висока", "Ультра"]
const FISHEYE_ITEMS := ["Вимкнено", "Повний", "Швидкий"]
const FISHEYE_RES_ITEMS := ["2160p", "1440p", "1080p", "720p", "480p", "240p"]
const FISHEYE_MSAA_ITEMS := ["Вимкнено", "2x", "4x", "8x", "16x", "Як у грі"]
const FPS_VALUES := [0, 30, 60, 90, 120, 144]
const FPS_ITEMS := ["Без обмежень", "30", "60", "90", "120", "144"]

signal back
var embedded := false

var _quality_option: OptionButton
var _quality_buttons: Array[Button] = []
var _fpv_mode_option: OptionButton
var _resolution_option: OptionButton
var _msaa_option: OptionButton
var _af_option: OptionButton
var _shadows_option: OptionButton
var _fisheye_mode_option: OptionButton
var _fisheye_res_option: OptionButton
var _fisheye_msaa_option: OptionButton
var _vsync_toggle: CheckButton
var _fps_option: OptionButton


func _ready() -> void:
	theme = MenuUI.theme()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_build()


func _build() -> void:
	add_child(MenuUI.background(MenuUI.BG))

	var center := CenterContainer.new()
	MenuUI.full_rect(center)
	var viewport_size := get_viewport_rect().size
	if MenuUI.is_mobile_ui():
		var edges := MenuUI.mobile_edge_margins(viewport_size)
		center.offset_top = int(edges.y)
		center.offset_bottom = -int(edges.w)
	add_child(center)

	var panel := PanelContainer.new()
	var panel_width := minf(900.0, viewport_size.x - 24.0)
	panel.custom_minimum_size = Vector2(panel_width, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_%s" % side, 22)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	box.add_child(MenuUI.title("ГРАФІКА", 40))

	# Three quality presets in a single row.
	var preset_row := GridContainer.new()
	preset_row.columns = 3
	preset_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preset_row.add_theme_constant_override("h_separation", 7)
	preset_row.add_theme_constant_override("v_separation", 6)
	var preset_labels := [
		("1. LOW" if MenuUI.is_english() else "1. НИЗЬКА"),
		("2. MEDIUM" if MenuUI.is_english() else "2. СЕРЕДНЯ"),
		("3. HIGH" if MenuUI.is_english() else "3. ВИСОКА"),
	]
	_quality_buttons.clear()
	var current_q := clampi(int(Graphics.graphics_settings.get("quality", 2)), 0, 2)
	for q_idx in range(3):
		var q_btn := MenuUI.button(preset_labels[q_idx], 46)
		q_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		q_btn.toggle_mode = true
		q_btn.button_pressed = (q_idx == current_q)
		q_btn.pressed.connect(_on_quality_changed.bind(q_idx))
		preset_row.add_child(q_btn)
		_quality_buttons.append(q_btn)
	box.add_child(preset_row)
	var q_hint := MenuUI.body(
			"НИЗЬКА — максимум FPS: FSR 40–72%, легка рослинність, короткі тіні. СЕРЕДНЯ — баланс: FSR 55–85%, щільна трава, тіні 120 м. ВИСОКА — максимум якості: нативна роздільність, SSAO, м'які тіні 180 м."
			if not MenuUI.is_english() else
			"LOW = maximum FPS: FSR 40–72%, light vegetation, short shadows. MEDIUM = balance: FSR 55–85%, dense grass, 120 m shadows. HIGH = maximum quality: native scale, SSAO, soft 180 m shadows.",
			12, MenuUI.MUTED)
	q_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(q_hint)

	var scroll := ScrollContainer.new()
	var scroll_height := viewport_size.y - (330.0 if MenuUI.is_mobile_ui() else 260.0)
	scroll.custom_minimum_size = Vector2(maxf(240.0, panel_width - 56.0),
			maxf(130.0, minf(420.0, scroll_height)))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)

	_quality_option = MenuUI.option(QUALITY_ITEMS, current_q)
	_quality_option.item_selected.connect(_on_quality_changed)
	_add_row(grid, "Рівень графіки (3 рівні)", _quality_option)

	_fpv_mode_option = MenuUI.option(FPV_MODE_ITEMS,
			clampi(int(Graphics.graphics_settings.get("fpv_video_mode", 0)), 0, 3))
	_fpv_mode_option.item_selected.connect(_on_fpv_mode_changed)
	_add_row(grid, "FPV-канал (відеолінк)", _fpv_mode_option)

	var window_option := MenuUI.option(WINDOW_ITEMS, int(Graphics.graphics_settings["window_mode"]))
	window_option.item_selected.connect(_on_window_mode_changed.bind(window_option))
	_add_row(grid, "Режим вікна", window_option)

	_resolution_option = MenuUI.option(RESOLUTION_ITEMS,
			RESOLUTION_VALUES.find(int(Graphics.graphics_settings["resolution"])))
	_resolution_option.item_selected.connect(_on_resolution_changed)
	_add_row(grid, "Масштаб роздільності", _resolution_option)

	_msaa_option = MenuUI.option(MSAA_ITEMS, int(Graphics.graphics_settings["msaa"]))
	_msaa_option.item_selected.connect(_on_msaa_changed)
	_add_row(grid, "Згладжування (MSAA)", _msaa_option)

	_af_option = MenuUI.option(MSAA_ITEMS, int(Graphics.graphics_settings["af"]))
	_af_option.item_selected.connect(_on_af_changed)
	_add_row(grid, "Анізотропна фільтрація", _af_option)

	_shadows_option = MenuUI.option(SHADOWS_ITEMS, int(Graphics.graphics_settings["shadows"]))
	_shadows_option.item_selected.connect(_on_shadows_changed)
	_add_row(grid, "Якість тіней", _shadows_option)

	_fisheye_mode_option = MenuUI.option(FISHEYE_ITEMS, int(Graphics.graphics_settings["fisheye_mode"]))
	_fisheye_mode_option.item_selected.connect(_on_fisheye_mode_changed)
	_add_row(grid, "FPV-об'єктив (риб'яче око)", _fisheye_mode_option)

	_fisheye_res_option = MenuUI.option(FISHEYE_RES_ITEMS, int(Graphics.graphics_settings["fisheye_resolution"]))
	_fisheye_res_option.item_selected.connect(_on_fisheye_res_changed)
	_add_row(grid, "Роздільність об'єктива", _fisheye_res_option)

	_fisheye_msaa_option = MenuUI.option(FISHEYE_MSAA_ITEMS, int(Graphics.graphics_settings["fisheye_msaa"]))
	_fisheye_msaa_option.item_selected.connect(_on_fisheye_msaa_changed)
	_add_row(grid, "MSAA об'єктива", _fisheye_msaa_option)

	_vsync_toggle = CheckButton.new()
	_vsync_toggle.button_pressed = bool(Graphics.graphics_settings["vsync"])
	_vsync_toggle.toggled.connect(_on_vsync_toggled)
	_add_row(grid, "Вертикальна синхронізація", _vsync_toggle)

	_fps_option = MenuUI.option(FPS_ITEMS, FPS_VALUES.find(int(Graphics.graphics_settings["fps_limit"])))
	_fps_option.item_selected.connect(_on_fps_changed)
	_add_row(grid, "Обмеження FPS", _fps_option)

	_update_fisheye_enabled()

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	var reset := MenuUI.button("СКИНУТИ ГРАФІКУ", 48)
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset.pressed.connect(_on_reset_pressed)
	bottom.add_child(reset)
	var back := MenuUI.button("←  НАЗАД", 48)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(_go_back)
	bottom.add_child(back)
	box.add_child(bottom)

	back.grab_focus()
	MenuUI.localize_tree(self)


func _add_row(grid: GridContainer, label_text: String, control: Control) -> void:
	var label := MenuUI.body(label_text, 19, MenuUI.TEXT)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_child(label)
	grid.add_child(control)


func _update_fisheye_enabled() -> void:
	var off := int(Graphics.graphics_settings["fisheye_mode"]) == Graphics.FisheyeMode.OFF
	if _fisheye_res_option != null:
		_fisheye_res_option.disabled = off
	if _fisheye_msaa_option != null:
		_fisheye_msaa_option.disabled = off


func _on_quality_changed(index: int) -> void:
	Graphics.apply_quality_preset(index)
	Graphics.save_graphics_settings()
	if _quality_option != null and _quality_option.selected != index:
		_quality_option.select(index)
	for i in range(_quality_buttons.size()):
		_quality_buttons[i].set_pressed_no_signal(i == index)
	if _msaa_option != null:
		_msaa_option.select(int(Graphics.graphics_settings["msaa"]))
	if _af_option != null:
		_af_option.select(int(Graphics.graphics_settings["af"]))
	if _shadows_option != null:
		_shadows_option.select(int(Graphics.graphics_settings["shadows"]))
	if _vsync_toggle != null:
		_vsync_toggle.set_pressed_no_signal(bool(Graphics.graphics_settings["vsync"]))
	if _fps_option != null:
		var fps_idx := FPS_VALUES.find(int(Graphics.graphics_settings["fps_limit"]))
		if fps_idx >= 0:
			_fps_option.select(fps_idx)


func _on_fpv_mode_changed(index: int) -> void:
	Graphics.set_fpv_video_mode(index)
	if _fpv_mode_option != null and _fpv_mode_option.selected != index:
		_fpv_mode_option.select(index)


func _on_window_mode_changed(index: int, option: OptionButton) -> void:
	Graphics.graphics_settings["window_mode"] = index
	Graphics.update_window_mode()
	Graphics.update_resolution()
	Graphics.save_graphics_settings()


func _on_resolution_changed(index: int) -> void:
	Graphics.graphics_settings["resolution"] = RESOLUTION_VALUES[index]
	Graphics.update_resolution()
	Graphics.save_graphics_settings()


func _on_msaa_changed(index: int) -> void:
	Graphics.graphics_settings["msaa"] = index
	Graphics.update_msaa()
	Graphics.save_graphics_settings()


func _on_af_changed(index: int) -> void:
	Graphics.graphics_settings["af"] = index
	Graphics.update_af()
	Graphics.save_graphics_settings()


func _on_shadows_changed(index: int) -> void:
	Graphics.graphics_settings["shadows"] = index
	Graphics.update_shadows()
	Graphics.save_graphics_settings()


func _on_fisheye_mode_changed(index: int) -> void:
	Graphics.graphics_settings["fisheye_mode"] = index
	Graphics.update_fisheye_mode()
	_update_fisheye_enabled()
	Graphics.save_graphics_settings()


func _on_fisheye_res_changed(index: int) -> void:
	Graphics.update_fisheye_resolution(FISHEYE_RES_ITEMS[index])
	Graphics.save_graphics_settings()


func _on_fisheye_msaa_changed(index: int) -> void:
	Graphics.graphics_settings["fisheye_msaa"] = index
	Graphics.update_fisheye_msaa()
	Graphics.save_graphics_settings()


func _on_vsync_toggled(pressed: bool) -> void:
	Graphics.graphics_settings["vsync"] = pressed
	Graphics.update_vsync()
	Graphics.save_graphics_settings()


func _on_fps_changed(index: int) -> void:
	Graphics.graphics_settings["fps_limit"] = FPS_VALUES[index]
	Graphics.update_fps_limit()
	Graphics.save_graphics_settings()


func _on_reset_pressed() -> void:
	Graphics.graphics_settings["quality"] = Graphics.QualityPreset.HIGH
	Graphics.graphics_settings["window_mode"] = Graphics.WindowMode.FULLSCREEN
	Graphics.graphics_settings["resolution"] = 100
	Graphics.graphics_settings["msaa"] = Graphics.GameMSAA.OFF
	Graphics.graphics_settings["af"] = Graphics.GameAF.X4
	Graphics.graphics_settings["shadows"] = Graphics.Shadows.HIGH
	Graphics.graphics_settings["fisheye_mode"] = Graphics.FisheyeMode.OFF
	Graphics.graphics_settings["fisheye_resolution"] = Graphics.FisheyeResolution.FISHEYE_720P
	Graphics.graphics_settings["fisheye_msaa"] = Graphics.FisheyeMSAA.OFF
	Graphics.graphics_settings["vsync"] = false
	Graphics.graphics_settings["fps_limit"] = 120
	Graphics.graphics_settings["fpv_video_mode"] = Graphics.FpvVideoMode.ANALOG_58
	Graphics.update_window_mode()
	Graphics.update_resolution()
	Graphics.update_msaa()
	Graphics.update_af()
	Graphics.update_shadows()
	Graphics.update_fisheye_mode()
	Graphics.update_fisheye_resolution()
	Graphics.update_fisheye_msaa()
	Graphics.update_vsync()
	Graphics.update_fps_limit()
	Graphics.update_quality()
	Graphics.update_fpv_video_mode()
	Graphics.save_graphics_settings()
	get_tree().reload_current_scene()


func _go_back() -> void:
	if embedded:
		back.emit()
		return
	if OS.has_feature("mobile"):
		get_tree().change_scene_to_file("res://GUI/mobile/MobileMenu.tscn")
		return
	get_tree().change_scene_to_file(MAIN_MENU)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		_go_back()
