extends MarginContainer


signal resumed
signal menu

const MAIN_MENU := "res://GUI/MainMenu.tscn"
const MenuIcons = preload("res://GUI/ui/MenuIcons.gd")

@onready var panel := $PanelContainer
@onready var vbox := $PanelContainer/VBoxContainer
@onready var btn_resume := $PanelContainer/VBoxContainer/ButtonResume
@onready var btn_quad := $PanelContainer/VBoxContainer/ButtonQuad
@onready var btn_help := $PanelContainer/VBoxContainer/ButtonHelp
@onready var btn_options := $PanelContainer/VBoxContainer/ButtonOptions
@onready var btn_main_menu := $PanelContainer/VBoxContainer/ButtonMainMenu
var btn_controls: Button
var btn_quit: Button

var quad_settings: Control = preload("res://GUI/QuadSettingsMenu.tscn").instantiate()
var options_menu: Control = preload("res://GUI/OptionsMenu.tscn").instantiate()
var mobile_menu: Control = null

var can_show := true
var can_resume := true
var _bg: Control = null
var _saved_hud_vis := {}
var _hud_suppressed := false
var _drone_was_frozen := false
var _pause_freeze_applied := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = MenuUI.theme()
	_apply_military_styling()
	visibility_changed.connect(_on_visibility_changed)

	_bind_button(btn_resume, Callable(self, "_on_resume_pressed"))
	_bind_button(btn_controls, Callable(self, "_on_controls_pressed"))
	_bind_button(btn_quad, Callable(self, "_on_quad_pressed"))
	if btn_help != null:
		btn_help.visible = false
	_bind_button(btn_options, Callable(self, "_on_options_pressed"))
	_bind_button(btn_main_menu, Callable(self, "_on_main_menu_pressed"))
	_bind_button(btn_quit, Callable(self, "_on_quit_pressed"))
	MenuUI.localize_tree(self)

	add_Sibling_Menus()


func _bind_button(b: Button, target: Callable) -> void:
	if b == null:
		return
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if not b.pressed.is_connected(target):
		b.pressed.connect(target)
	if not b.mouse_entered.is_connected(b.grab_focus):
		b.mouse_entered.connect(b.grab_focus)


func _process(_delta: float) -> void:
	if visible and DisplayServer.get_name() != "headless":
		if Input.get_mouse_mode() != Input.MOUSE_MODE_VISIBLE:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _apply_military_styling() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		add_theme_constant_override("margin_%s" % side, 0)

	_bg = MenuUI.background(MenuUI.FPV_BG, false)
	add_child(_bg)
	move_child(_bg, 0)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MenuUI.full_rect(center)
	remove_child(panel)
	add_child(center)
	center.add_child(panel)

	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var mobile_ui := MenuUI.is_mobile_ui()
	var pause_vp := get_viewport_rect().size
	var pause_safe := MenuUI.mobile_safe_margin(pause_vp) if mobile_ui else 20.0
	# On a phone the old 640-unit card was only ~27% of the 1280-wide capture
	# and the 54-unit rows were hard to hit.  An 1180-unit card with 84-unit
	# rows doubles the text size while still fitting 1080 units of canvas
	# height with the safe areas.
	panel.custom_minimum_size = Vector2(
			minf(1180.0 if mobile_ui else 540.0,
					pause_vp.x - pause_safe * 2.0), 0)
	panel.add_theme_stylebox_override("panel", MenuUI._style(
			MenuUI.FPV_BG_CARD if mobile_ui else MenuUI.PANEL,
			MenuUI.BORDER_HIGHLIGHT, 2,
			22 if mobile_ui else 4, 40 if mobile_ui else 32,
			38 if mobile_ui else 28, 6))
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_theme_constant_override("separation", 16 if mobile_ui else 12)

	var header := MenuUI.section("БОЙОВИЙ FPV СИМУЛЯТОР // ПАУЗА", "ESC")
	vbox.add_child(header)
	vbox.move_child(header, 0)
	if mobile_ui:
		for lbl in header.find_children("*", "Label", true, false):
			(lbl as Label).add_theme_font_size_override("font_size", 20)

	var title_lbl := vbox.get_node_or_null("Title") as Label
	if title_lbl != null:
		title_lbl.text = "РЕЖИМ ПАУЗИ"
		title_lbl.add_theme_font_size_override("font_size", 38 if mobile_ui else 24)
		title_lbl.add_theme_color_override("font_color", MenuUI.FPV_AMBER)
		title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Create Dedicated Controls Button
	btn_controls = Button.new()
	btn_controls.name = "ButtonControls"
	vbox.add_child(btn_controls)

	btn_quit = Button.new()
	btn_quit.name = "ButtonQuit"
	vbox.add_child(btn_quit)

	# Ensure clean order: header -> title -> resume -> controls -> quad -> options -> main_menu -> quit
	var desired_order := [header, title_lbl, btn_resume, btn_controls, btn_quad, btn_options, btn_main_menu, btn_quit]
	var order_idx := 0
	for el in desired_order:
		if el != null and el.get_parent() == vbox:
			vbox.move_child(el, order_idx)
			order_idx += 1

	var pause_btn_height := 84.0 if mobile_ui else 46.0
	var btn_list := [btn_resume, btn_controls, btn_quad, btn_options, btn_main_menu, btn_quit]

	for b in btn_list:
		if b != null:
			b.custom_minimum_size = Vector2(0, pause_btn_height)
			b.alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.mouse_filter = Control.MOUSE_FILTER_STOP
			b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			b.add_theme_font_size_override("font_size", 26 if mobile_ui else 16)

	btn_resume.text = "  ПРОДОВЖИТИ ПОЛІТ"
	btn_resume.icon = MenuIcons.icon_play(Color(0.06, 0.09, 0.07))
	btn_resume.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT

	btn_controls.text = "  ПУЛЬТ ТА КАЛІБРУВАННЯ"
	btn_controls.icon = MenuIcons.icon_radio(Color(0.85, 0.95, 0.88))
	btn_controls.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT

	btn_quad.text = "  РЕЙТИ ТА ЕКСПО БОРТУ"
	btn_quad.icon = MenuIcons.icon_rates(Color(0.85, 0.95, 0.88))
	btn_quad.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT

	btn_options.text = "  НАЛАШТУВАННЯ ГРИ ТА РЕБ"
	btn_options.icon = MenuIcons.icon_settings(Color(0.85, 0.95, 0.88))
	btn_options.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT

	btn_main_menu.text = "  ДО ГОЛОВНОГО МЕНЮ"
	btn_main_menu.icon = MenuIcons.icon_home(Color(0.85, 0.95, 0.88))
	btn_main_menu.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT

	btn_quit.text = "  ВИЙТИ З СИМУЛЯТОРА"
	btn_quit.icon = MenuIcons.icon_close(Color(0.95, 0.45, 0.45))
	btn_quit.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	# SceneTree.quit() is a no-op on iOS (Apple manages app lifetime).  Hide the
	# dead control instead of leaving a button that appears broken.
	if OS.get_name() == "iOS" or OS.has_feature("ios") \
			or OS.has_environment("SIMULATE_IOS"):
		btn_quit.visible = false
		var ios_hint := Label.new()
		ios_hint.text = "iOS: закрий гру свайпом догори"
		ios_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ios_hint.add_theme_font_size_override("font_size", 15)
		ios_hint.add_theme_color_override("font_color", MenuUI.MUTED)
		vbox.add_child(ios_hint)

	var primary := MenuUI.feel_style(Color(0.62, 0.74, 0.55, 1.0),
			MenuUI.FPV_GREEN, 2, 12, 16, 8)
	var primary_hover := MenuUI.feel_style(Color(0.70, 0.82, 0.62, 1.0),
			MenuUI.FPV_GREEN, 2, 12, 16, 8)
	btn_resume.add_theme_stylebox_override("normal", primary)
	btn_resume.add_theme_stylebox_override("hover", primary_hover)
	btn_resume.add_theme_stylebox_override("focus", primary_hover)
	btn_resume.add_theme_stylebox_override("pressed", MenuUI.feel_style(
			Color(0.10, 0.22, 0.15, 1.0), MenuUI.FPV_GREEN, 2, 12, 16, 8))
	btn_resume.add_theme_color_override("font_color", Color(0.06, 0.09, 0.07))
	btn_resume.add_theme_color_override("font_hover_color", Color(0.06, 0.09, 0.07))
	btn_resume.add_theme_color_override("font_pressed_color", MenuUI.FPV_TEXT)

	var def_style := MenuUI.feel_style(Color(0.04, 0.08, 0.065, 0.92),
			Color(0.32, 0.48, 0.38, 0.6), 1, 12, 16, 8)
	var def_hover := MenuUI.feel_style(Color(0.08, 0.15, 0.11, 0.96),
			Color(0.45, 0.65, 0.50, 0.85), 1, 12, 16, 8)
	for b in [btn_controls, btn_quad, btn_options, btn_main_menu]:
		b.add_theme_stylebox_override("normal", def_style)
		b.add_theme_stylebox_override("hover", def_hover)
		b.add_theme_stylebox_override("focus", def_hover)
		b.add_theme_color_override("font_color", MenuUI.FPV_TEXT)

	var quit_style := MenuUI.feel_style(Color(0.12, 0.04, 0.04, 0.9),
			Color(0.55, 0.25, 0.25, 0.7), 1, 12, 16, 8)
	var quit_hover := MenuUI.feel_style(Color(0.20, 0.06, 0.06, 0.95),
			Color(0.75, 0.35, 0.35, 0.9), 1, 12, 16, 8)
	btn_quit.add_theme_stylebox_override("normal", quit_style)
	btn_quit.add_theme_stylebox_override("hover", quit_hover)
	btn_quit.add_theme_stylebox_override("focus", quit_hover)
	btn_quit.add_theme_color_override("font_color", Color(0.95, 0.7, 0.7))


func _on_visibility_changed() -> void:
	if visible:
		MenuUI.localize_tree(self)
	if visible or (quad_settings != null and quad_settings.visible) or (options_menu != null and options_menu.visible) or (mobile_menu != null and mobile_menu.visible):
		_set_flight_hud_suppressed(true)
	else:
		_set_flight_hud_suppressed(false)


func add_Sibling_Menus() -> void:
	await self.ready
	quad_settings.visible = false
	options_menu.visible = false
	quad_settings.process_mode = Node.PROCESS_MODE_ALWAYS
	options_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	var sibling_parent := get_parent()
	if sibling_parent == null:
		return
	sibling_parent.call_deferred("add_child", quad_settings)
	quad_settings.visibility_changed.connect(_on_visibility_changed)
	if quad_settings.has_signal("closed"):
		var _discard = quad_settings.connect("closed", Callable(self, "_on_sub_menu_closed"))
	sibling_parent.call_deferred("add_child", options_menu)
	options_menu.visibility_changed.connect(_on_visibility_changed)
	if options_menu.has_signal("back"):
		var _discard = options_menu.connect("back", Callable(self, "_on_sub_menu_closed"))
	elif options_menu.has_signal("closed"):
		var _discard = options_menu.connect("closed", Callable(self, "_on_sub_menu_closed"))

	var mobile_scene = load("res://GUI/mobile/MobileMenu.tscn")
	if mobile_scene is PackedScene:
		mobile_menu = (mobile_scene as PackedScene).instantiate() as Control
		mobile_menu.set_meta("embedded_pause", true)
		mobile_menu.visible = false
		mobile_menu.process_mode = Node.PROCESS_MODE_ALWAYS
		sibling_parent.call_deferred("add_child", mobile_menu)
		mobile_menu.visibility_changed.connect(_on_visibility_changed)
		if mobile_menu.has_signal("closed"):
			var _discard = mobile_menu.connect("closed", Callable(self, "_on_sub_menu_closed"))


func _set_flight_hud_suppressed(suppress: bool) -> void:
	if suppress:
		if _hud_suppressed:
			return
		_hud_suppressed = true
		_saved_hud_vis.clear()
		var level_hud = get_scene_hud()
		if level_hud is CanvasLayer:
			_saved_hud_vis["level_hud"] = (level_hud as CanvasLayer).visible
			(level_hud as CanvasLayer).visible = false
		var combat_hud := get_scene_combat_hud()
		if combat_hud != null:
			_saved_hud_vis["combat_hud"] = combat_hud.visible
			combat_hud.visible = false
		var drone := get_scene_drone()
		if drone != null:
			var dhud = drone.get("hud")
			if dhud is CanvasItem:
				_saved_hud_vis["drone_hud"] = (dhud as CanvasItem).visible
				(dhud as CanvasItem).visible = false
	else:
		if not _hud_suppressed:
			return
		_hud_suppressed = false
		var level_hud = get_scene_hud()
		if level_hud is CanvasLayer and _saved_hud_vis.has("level_hud"):
			(level_hud as CanvasLayer).visible = bool(_saved_hud_vis["level_hud"])
		var combat_hud := get_scene_combat_hud()
		if combat_hud != null and _saved_hud_vis.has("combat_hud"):
			combat_hud.visible = bool(_saved_hud_vis["combat_hud"])
		var drone := get_scene_drone()
		if drone != null and _saved_hud_vis.has("drone_hud"):
			var dhud = drone.get("hud")
			if dhud is CanvasItem:
				(dhud as CanvasItem).visible = bool(_saved_hud_vis["drone_hud"])
		_saved_hud_vis.clear()


func get_scene_hud() -> Node:
	var scene := get_tree().current_scene
	return scene.get("_hud") if scene != null else null


func get_scene_combat_hud() -> CanvasLayer:
	var scene := get_tree().current_scene
	return scene.get_node_or_null("CombatHUD") as CanvasLayer if scene != null else null


func get_scene_drone() -> Node:
	var scene := get_tree().current_scene
	return scene.get_node_or_null("Drone") if scene != null else null


func _input(event: InputEvent) -> void:
	if !can_show:
		return
	var esc_key := false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE:
			esc_key = true
	if (esc_key or event.is_action_pressed("pause_menu") or event.is_action_pressed("ui_cancel")) and not event.is_echo():
		if !visible and !quad_settings.visible and !options_menu.visible and (mobile_menu == null or !mobile_menu.visible):
			accept_event()
			get_tree().paused = true
			_set_drone_frozen(true)
			show_menu(true)
		elif visible and can_resume:
			accept_event()
			_on_resume_pressed()


func show_menu(show_flag: bool) -> void:
	visible = show_flag
	if visible:
		_set_flight_hud_suppressed(true)
		btn_resume.grab_focus()


func _on_resume_pressed() -> void:
	show_menu(false)
	_set_flight_hud_suppressed(false)
	get_tree().paused = false
	_set_drone_frozen(false)
	if DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	emit_signal("resumed")


func _set_drone_frozen(frozen: bool) -> void:
	var d = get_scene_drone()
	if d is Drone:
		var drone := d as Drone
		if frozen:
			if not _pause_freeze_applied:
				_drone_was_frozen = drone.freeze
				_pause_freeze_applied = true
			drone.freeze = true
			drone.linear_velocity = Vector3.ZERO
			drone.angular_velocity = Vector3.ZERO
		else:
			if _pause_freeze_applied:
				drone.freeze = _drone_was_frozen
				_pause_freeze_applied = false
			if drone.flight_controller != null:
				drone.flight_controller.input = [0.0, 0.0, 0.0, 0.0]


func _on_controls_pressed() -> void:
	show_menu(false)
	_set_flight_hud_suppressed(true)
	if mobile_menu != null:
		mobile_menu.call("open_tab", "controls", true)
	else:
		options_menu.visible = true


func _on_quad_pressed() -> void:
	show_menu(false)
	_set_flight_hud_suppressed(true)
	if mobile_menu != null:
		mobile_menu.call("open_tab", "rates", true)
	else:
		quad_settings.show_menu(true)


func _on_options_pressed() -> void:
	show_menu(false)
	_set_flight_hud_suppressed(true)
	if mobile_menu != null:
		mobile_menu.call("open_tab", "settings", true)
	else:
		options_menu.visible = true


func _on_main_menu_pressed() -> void:
	_set_flight_hud_suppressed(false)
	get_tree().paused = false
	if DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if get_signal_connection_list("menu").size() > 0:
		emit_signal("menu")
	else:
		var target_menu := "res://GUI/mobile/MobileMenu.tscn" if MenuUI.is_mobile_ui() else MAIN_MENU
		get_tree().change_scene_to_file(target_menu)


func _on_quit_pressed() -> void:
	get_tree().paused = false
	get_tree().quit()


func _on_sub_menu_closed() -> void:
	if options_menu != null:
		options_menu.visible = false
	if quad_settings != null:
		quad_settings.visible = false
	if mobile_menu != null:
		mobile_menu.visible = false
	show_menu(true)
