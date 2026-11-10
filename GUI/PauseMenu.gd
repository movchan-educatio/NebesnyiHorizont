extends MarginContainer


signal resumed
signal menu

const MAIN_MENU := "res://GUI/MainMenu.tscn"

@onready var panel := $PanelContainer
@onready var vbox := $PanelContainer/VBoxContainer
@onready var btn_resume := $PanelContainer/VBoxContainer/ButtonResume
@onready var btn_quad := $PanelContainer/VBoxContainer/ButtonQuad
@onready var btn_help := $PanelContainer/VBoxContainer/ButtonHelp
@onready var btn_options := $PanelContainer/VBoxContainer/ButtonOptions
@onready var btn_main_menu := $PanelContainer/VBoxContainer/ButtonMainMenu
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

	btn_quit = Button.new()
	btn_quit.name = "ButtonQuit"
	btn_quit.text = "✕  ВИЙТИ З СИМУЛЯТОРА"
	btn_quit.custom_minimum_size = Vector2(0, 48)
	vbox.add_child(btn_quit)

	_bind_button(btn_resume, Callable(self, "_on_resume_pressed"))
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
	# Also ensure hovering with mouse highlights and selects the button
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
	var pause_vp := get_viewport_rect().size
	var pause_safe := MenuUI.mobile_safe_margin(pause_vp) if MenuUI.is_mobile_ui() else 20.0
	panel.custom_minimum_size = Vector2(
			minf(720.0 if MenuUI.is_mobile_ui() else 560.0,
					pause_vp.x - pause_safe * 2.0), 0)
	panel.add_theme_stylebox_override("panel", MenuUI._style(
			MenuUI.FPV_BG_CARD if MenuUI.is_mobile_ui() else MenuUI.PANEL,
			MenuUI.BORDER_HIGHLIGHT, 2,
			16 if MenuUI.is_mobile_ui() else 3, 30, 24, 5))
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_theme_constant_override("separation", 14)

	var header := MenuUI.section("МЕНЮ ПАУЗИ", "ESC")
	vbox.add_child(header)
	vbox.move_child(header, 0)

	var title_lbl := vbox.get_node_or_null("Title") as Label
	if title_lbl != null:
		title_lbl.text = "ПАУЗА"
		title_lbl.add_theme_font_size_override("font_size", 28)
		title_lbl.add_theme_color_override("font_color", MenuUI.FPV_TEXT)
		if MenuUI.is_mobile_ui():
			title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	for b in [btn_resume, btn_quad, btn_options, btn_main_menu, btn_quit]:
		if b != null:
			b.mouse_filter = Control.MOUSE_FILTER_STOP
			b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var pause_btn_height := 58.0 if MenuUI.is_mobile_ui() else 48.0
	btn_resume.text = "▶  ПРОДОВЖИТИ ПОЛІТ"
	btn_resume.custom_minimum_size = Vector2(0, pause_btn_height)
	btn_quad.text = "✈  ПАРАМЕТРИ БОРТУ ТА РЕЙТИ"
	btn_quad.custom_minimum_size = Vector2(0, pause_btn_height)
	btn_options.text = "⚙  НАЛАШТУВАННЯ ТА КЕРУВАННЯ"
	btn_options.custom_minimum_size = Vector2(0, pause_btn_height)
	btn_main_menu.text = "⌂  ДО ГОЛОВНОГО МЕНЮ"
	btn_main_menu.custom_minimum_size = Vector2(0, pause_btn_height)
	if MenuUI.is_mobile_ui():
		var primary := MenuUI.feel_style(Color(0.62, 0.74, 0.55, 1.0),
				MenuUI.FPV_GREEN, 2, 14, 18, 12)
		var primary_hover := MenuUI.feel_style(Color(0.70, 0.82, 0.62, 1.0),
				MenuUI.FPV_GREEN, 2, 14, 18, 12)
		btn_resume.add_theme_stylebox_override("normal", primary)
		btn_resume.add_theme_stylebox_override("hover", primary_hover)
		btn_resume.add_theme_stylebox_override("focus", primary_hover)
		btn_resume.add_theme_stylebox_override("pressed", MenuUI.feel_style(
				Color(0.10, 0.22, 0.15, 1.0), MenuUI.FPV_GREEN, 2, 14, 18, 12))
		btn_resume.add_theme_color_override("font_color", Color(0.06, 0.09, 0.07))
		btn_resume.add_theme_color_override("font_hover_color", Color(0.06, 0.09, 0.07))
		btn_resume.add_theme_color_override("font_pressed_color", MenuUI.FPV_TEXT)


func _on_visibility_changed() -> void:
	if visible:
		MenuUI.localize_tree(self)
	if visible or (quad_settings != null and quad_settings.visible) or (options_menu != null and options_menu.visible):
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
		mobile_menu.visible = false
		mobile_menu.process_mode = Node.PROCESS_MODE_ALWAYS
		sibling_parent.call_deferred("add_child", mobile_menu)
		mobile_menu.visibility_changed.connect(_on_visibility_changed)
		if mobile_menu.has_signal("closed"):
			mobile_menu.connect("closed", Callable(self, "_on_sub_menu_closed"))


func _set_flight_hud_suppressed(suppress: bool) -> void:
	if suppress:
		# The pause flow calls this from both _input() and visibility_changed().
		# Without the guard the second call saves the already-hidden state as
		# "visible" source, so resuming leaves the whole flight HUD invisible.
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
			_set_flight_hud_suppressed(true)
			show_menu(true)
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		elif visible:
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


## Pause/photo use: stop the airframe completely.  Without this the physics
## kept the last velocity/PID state and the drone drifted behind the menu.
## The pre-pause freeze state is preserved: a drone that was still parked on
## its launch pad (freeze = true until the pilot arms) must stay parked after
## the menu closes instead of dropping out of the sky.
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


func _on_quad_pressed() -> void:
	show_menu(false)
	_set_flight_hud_suppressed(true)
	if MenuUI.is_mobile_ui() and mobile_menu != null:
		mobile_menu.call("open_tab", "rates", true)
	else:
		quad_settings.show_menu(true)


func _on_options_pressed() -> void:
	show_menu(false)
	_set_flight_hud_suppressed(true)
	if MenuUI.is_mobile_ui() and mobile_menu != null:
		mobile_menu.call("open_tab", "controls", true)
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
