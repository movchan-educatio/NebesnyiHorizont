## Tactical Options / Settings Menu (Ukrainian Mil-Tech C2).
## Embedded seamlessly within Tactical Pause or accessed from Main Menu.
extends Control

signal back

const CONTROLS_SCREEN := "res://GUI/ControlsScreen.tscn"
const CALIBRATION_SCREEN := "res://GUI/CalibrationScreen.tscn"
const GRAPHICS_SCREEN := "res://GUI/GraphicsScreen.tscn"
const OTHER_SCREEN := "res://GUI/OtherSettingsScreen.tscn"
const HELP_SCREEN := "res://GUI/HelpScreen.tscn"

var _center_container: CenterContainer = null
var _active_sub_screen: Control = null
var _first_btn: Button = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = MenuUI.theme()
	for side in ["left", "right", "top", "bottom"]:
		add_theme_constant_override("margin_%s" % side, 0)
	MenuUI.full_rect(self)
	_build_ui()


func _build_ui() -> void:
	# Clear any old children from .tscn
	for c in get_children():
		c.queue_free()

	add_child(MenuUI.background(MenuUI.FPV_BG, false))

	_center_container = CenterContainer.new()
	MenuUI.full_rect(_center_container)
	var viewport_size := get_viewport_rect().size
	if MenuUI.is_mobile_ui():
		var edges := MenuUI.mobile_edge_margins(viewport_size)
		_center_container.offset_top = int(edges.y)
		_center_container.offset_bottom = -int(edges.w)
	add_child(_center_container)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(minf(580.0, viewport_size.x - 32.0), minf(520.0, viewport_size.y - 32.0))
	var card_sb := MenuUI._style(MenuUI.PANEL, MenuUI.BORDER_HIGHLIGHT, 2, 3, 24, 20, 5)
	card.add_theme_stylebox_override("panel", card_sb)
	_center_container.add_child(card)

	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_%s" % side, 20)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	card.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6 if MenuUI.is_mobile_ui() else 8)
	margin.add_child(vbox)

	var title := MenuUI.title("НАЛАШТУВАННЯ", 22 if MenuUI.is_mobile_ui() else 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	if not MenuUI.is_mobile_ui():
		var sub := MenuUI.body("Керування, графіка, звук і симуляція", 12, MenuUI.MUTED)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(sub)
	vbox.add_child(MenuUI.spacer(4 if MenuUI.is_mobile_ui() else 6))

	var btn_controls := MenuUI.button("КЕРУВАННЯ", 38)
	_bind_button(btn_controls, _open_screen.bind(CONTROLS_SCREEN))
	vbox.add_child(btn_controls)
	_first_btn = btn_controls

	var btn_calib := MenuUI.button("КАЛІБРУВАННЯ СТІКІВ", 38)
	_bind_button(btn_calib, _open_screen.bind(CALIBRATION_SCREEN))
	vbox.add_child(btn_calib)

	var btn_graphics := MenuUI.button("ГРАФІКА", 38)
	_bind_button(btn_graphics, _open_screen.bind(GRAPHICS_SCREEN))
	vbox.add_child(btn_graphics)

	var btn_audio := MenuUI.button("ЗВУК, HUD І СИМУЛЯЦІЯ", 38)
	_bind_button(btn_audio, _open_screen.bind(OTHER_SCREEN))
	vbox.add_child(btn_audio)

	var btn_help := MenuUI.button("ДОВІДКА Й КЕРУВАННЯ", 38)
	_bind_button(btn_help, _open_screen.bind(HELP_SCREEN))
	vbox.add_child(btn_help)

	var btn_mobile := MenuUI.button("МОБІЛЬНИЙ ІНТЕРФЕЙС", 38)
	_bind_button(btn_mobile, func() -> void:
		get_tree().change_scene_to_file("res://GUI/mobile/MobileMenu.tscn"))
	# On the phone this screen is already the mobile interface; the entry is
	# only a desktop preview link.
	btn_mobile.visible = not MenuUI.is_mobile_ui()
	vbox.add_child(btn_mobile)

	vbox.add_child(MenuUI.spacer(4))

	var btn_back := MenuUI.button("←  НАЗАД", 38)
	_bind_button(btn_back, _on_back_pressed)
	vbox.add_child(btn_back)

	if MenuUI.is_mobile_ui():
		# Seven rows plus a title must fit a 590 px-tall phone screen with
		# safe margins; 50 px is still a comfortable thumb target.
		for child in vbox.get_children():
			if child is Button:
				(child as Button).custom_minimum_size.y = 46.0

	if not visibility_changed.is_connected(_on_visibility_changed):
		visibility_changed.connect(_on_visibility_changed)
	MenuUI.localize_tree(self)


func _bind_button(b: Button, target: Callable) -> void:
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(target)
	b.mouse_entered.connect(b.grab_focus)


func _on_visibility_changed() -> void:
	if visible and _center_container != null and _center_container.visible:
		if _first_btn != null and is_instance_valid(_first_btn):
			_first_btn.grab_focus()


func _open_screen(scene_path: String) -> void:
	if not ResourceLoader.exists(scene_path):
		return
	var scene := load(scene_path) as PackedScene
	if scene == null:
		return
	var screen := scene.instantiate() as Control
	if screen == null:
		return

	if "embedded" in screen:
		screen.set("embedded", true)
	screen.process_mode = Node.PROCESS_MODE_ALWAYS

	if screen.has_signal("back"):
		screen.connect("back", Callable(self, "_on_sub_screen_back"))

	_active_sub_screen = screen
	_center_container.visible = false
	add_child(screen)
	MenuUI.localize_tree(screen)


func _on_sub_screen_back() -> void:
	if _active_sub_screen != null and is_instance_valid(_active_sub_screen):
		_active_sub_screen.queue_free()
		_active_sub_screen = null
	_center_container.visible = true
	if _first_btn != null and is_instance_valid(_first_btn):
		_first_btn.grab_focus()


func _on_back_pressed() -> void:
	if _active_sub_screen != null and is_instance_valid(_active_sub_screen):
		_on_sub_screen_back()
		return
	if get_signal_connection_list("back").is_empty():
		# Opened as a full screen from the mobile menu: return there instead
		# of emitting into the void.
		get_tree().change_scene_to_file("res://GUI/mobile/MobileMenu.tscn")
		return
	emit_signal("back")


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if (event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.keycode == KEY_ESCAPE and event.is_pressed())) and not event.is_echo():
		accept_event()
		_on_back_pressed()
