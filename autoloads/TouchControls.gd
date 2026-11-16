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

const MenuUI = preload("res://GUI/ui/MenuUI.gd")
const NO_TOUCH := -2
const MOUSE_TOUCH := -1
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
var _toast: Label = null
var _toast_time := 0.0
var _mode_refresh := 0.0
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
var _invert_touch_pitch_check: CheckBox = null
## Touch roll inversion (the ELRS radio has its own invert flag).
var invert_roll := false
## Touch pitch inversion.  Default false: standard FPV, stick-up = nose-down
## (matches the keyboard and ELRS convention).  Enable for arcade "up = up".
var invert_pitch := false
var _throttle_grab_y := 0.0
var _throttle_grab_value := 0.0
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
## Compact in-flight top bar: only MENU + options button by default; the secondary
## toggles (mode/input/reset/video/touch/tilt) live inside the quick-options drawer.
var _bar_open := false
var _more_button: Button = null
var _more_panel: PanelContainer = null
var _float_button: Button = null
var _spring_button: Button = null
var _tilt_down_button: Button = null
var _tilt_up_button: Button = null
var _panel_menu_button: Button = null
var _left_anchor := Vector2.ZERO
var _right_anchor := Vector2.ZERO
var _touch_floating_sticks := false
var _touch_left_spring := false
var _touch_sensitivity := 1.0
var _touch_expo := 0.2


func _tx(ua: String, en: String) -> String:
	return en if MenuUI.is_english() else ua


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

	_arm_button = Button.new()
	_arm_button.name = "TouchArmButton"
	_arm_button.text = _tx("АРМ", "ARM")
	_arm_button.focus_mode = Control.FOCUS_NONE
	_arm_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_arm_button.add_theme_font_size_override("font_size", 28)
	_arm_button.add_theme_color_override("font_color", Color(1.0, 0.94, 0.88))
	_arm_button.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_arm_button.add_theme_constant_override("outline_size", 4)
	_arm_button.button_down.connect(_on_arm_pressed)
	_root.add_child(_arm_button)

	_pause_button = _make_top_button(_tx("МЕНЮ", "MENU"), _on_pause_pressed)
	_more_button = _make_top_button("", Callable(self, "_on_more_pressed"))
	_more_button.name = "TouchMoreButton"
	var more_tex := MenuIcons.icon_more(Color(0.90, 0.96, 0.91))
	if more_tex != null:
		_more_button.icon = more_tex
		_more_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_more_button.expand_icon = false
	else:
		_more_button.text = _tx("ОПЦ", "OPTIONS")

	_build_more_panel()

	_drop_button = Button.new()
	_drop_button.name = "TouchDropButton"
	_drop_button.text = _tx("СКИД", "DROP")
	_drop_button.focus_mode = Control.FOCUS_NONE
	_drop_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_drop_button.add_theme_font_size_override("font_size", 24)
	_drop_button.add_theme_color_override("font_color", Color(1.0, 0.95, 0.86))
	_drop_button.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_drop_button.add_theme_constant_override("outline_size", 4)
	_drop_button.button_down.connect(_on_action_pressed.bind("deploy_payload"))
	_drop_button.visible = false
	_root.add_child(_drop_button)

	_toast = Label.new()
	_toast.name = "TouchToast"
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 22)
	_toast.add_theme_color_override("font_color", Color(1.0, 0.86, 0.55))
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_toast.add_theme_constant_override("outline_size", 5)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	_root.add_child(_toast)

	visible = false
	set_process_input(false)
	refresh_touch_settings()
	get_viewport().size_changed.connect(_layout)
	_layout()
	_refresh_language_labels()


func _refresh_language_labels() -> void:
	if _arm_button != null:
		_arm_button.text = _tx("АРМ", "ARM")
	if _pause_button != null:
		_pause_button.text = _tx("МЕНЮ", "MENU")
	if _more_button != null and _more_button.icon == null:
		_more_button.text = _tx("ОПЦ", "OPTIONS")
	if _drop_button != null:
		_drop_button.text = _tx("СКИД", "DROP")
	if _setup_root != null:
		MenuUI.localize_tree(_setup_root)
	_refresh_more_panel_labels()
	_update_mode_button()
	_sync_flight_mode_label()


func begin(owner_id: int = 0) -> void:
	## Called by the level when its HUD is ready.  The owner id prevents an
	## outgoing level's _exit_tree() from switching off the new level's sticks.
	if _preview:
		set_menu_preview(false)
	_owner_id = owner_id
	if not _should_enable():
		set_enabled(false)
		return
	_refresh_language_labels()
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
				_reset_button, _video_button, _mode_button, _arm_button, _more_button]:
			if b != null:
				b.visible = false
		if _more_panel != null:
			_more_panel.visible = false
		if _setup_root != null:
			_setup_root.visible = false
		_drawer.queue_redraw()
		return
	if not _preview:
		return
	_preview = false
	process_mode = Node.PROCESS_MODE_INHERIT
	set_enabled(false)
	_bar_open = false
	for b in [_arm_button]:
		if b != null:
			b.visible = true
	if _drop_button != null:
		_drop_button.visible = false


func _should_enable() -> bool:
	return OS.get_name() == "iOS" or OS.has_environment("TOUCH_CONTROLS") \
			or DisplayServer.is_touchscreen_available()


func _configured_input_mode() -> String:
	var g := get_node_or_null("/root/Global")
	if g != null and g.get("menu_settings") is Dictionary:
		var m := str((g.get("menu_settings") as Dictionary).get("touch_input_mode", "auto")).to_lower()
		if m in ["auto", "controller", "touch"]:
			return m
	return "auto"


func _set_configured_input_mode(mode: String) -> void:
	var clean := mode.to_lower()
	if not (clean in ["auto", "controller", "touch"]):
		clean = "auto"
	var g := get_node_or_null("/root/Global")
	if g != null and g.get("menu_settings") is Dictionary:
		g.menu_settings["touch_input_mode"] = clean
		if g.has_method("save_menu_settings"):
			g.save_menu_settings()


func _has_active_controller() -> bool:
	var elrs := get_node_or_null("/root/ElrsWifiInput")
	if elrs != null:
		if bool(elrs.get("valid")):
			return true
		if elrs.has_method("was_recently_active") and bool(elrs.call("was_recently_active", 20000)):
			return true
	return false


func is_controller_locked() -> bool:
	return _configured_input_mode() == "controller"


func set_controller_only(controller_only: bool) -> void:
	if controller_only:
		_set_configured_input_mode("controller")
		touch_mode = false
		_reset_sticks()
	else:
		# When no radio is connected, return to "auto" so sticks work right
		# away and still yield cleanly if an ELRS link comes online later.
		_set_configured_input_mode("touch" if _has_active_controller() else "auto")
		if enabled:
			touch_mode = true
			_reset_sticks()
	_update_mode_button()
	if _drawer != null:
		_drawer.queue_redraw()
	mode_changed.emit(touch_mode)


func toggle_touch_sticks_preference() -> bool:
	var currently_touch := (not is_controller_locked()) and (touch_mode or not _has_active_controller())
	set_controller_only(currently_touch)
	return touch_mode


func _any_modal_menu_open() -> bool:
	var scene := get_tree().current_scene if get_tree() != null else null
	if scene == null:
		return false
	for node_name in ["PauseMenu", "pause_menu", "OptionsMenu", "QuadSettingsMenu", "MobileMenu"]:
		var n := scene.get_node_or_null(node_name)
		if n is CanvasItem and (n as CanvasItem).visible:
			return true
	var pause_node = scene.get("pause_menu")
	if pause_node is CanvasItem and (pause_node as CanvasItem).visible:
		return true
	var brief = scene.get("_chain_brief")
	if brief is CanvasItem and (brief as CanvasItem).visible:
		return true
	var results = scene.get("_results")
	if results is CanvasItem and (results as CanvasItem).visible:
		return true
	return false


func set_enabled(value: bool) -> void:
	enabled = value
	visible = value
	set_process_input(value)
	if value:
		refresh_touch_settings()
		_layout()
		var cfg_mode := _configured_input_mode()
		if cfg_mode == "controller":
			touch_mode = false
		elif cfg_mode == "touch":
			touch_mode = true
		else:
			touch_mode = not _has_active_controller()
		var gs := get_node_or_null("/root/GameSettings")
		if gs != null:
			invert_roll = bool(gs.hud_config.get("touch_invert_roll", false))
			invert_pitch = bool(gs.hud_config.get("touch_invert_pitch", false))
		_reset_sticks()
		_update_mode_button()
		_refresh_more_panel_labels()
	else:
		_bar_open = false
		if _more_panel != null:
			_more_panel.visible = false
		if _setup_root != null and _setup_root.visible:
			_on_setup_close()
		touch_mode = false
		_reset_sticks()
		if _drop_button != null:
			_drop_button.visible = false
	mode_changed.emit(touch_mode)


func _make_top_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.name = "Touch" + text.capitalize().replace(" ", "") + "Button"
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", Color(0.90, 0.96, 1.0))
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	b.add_theme_constant_override("outline_size", 3)
	b.button_down.connect(cb)
	_root.add_child(b)
	return b


func refresh_touch_settings() -> void:
	var g := get_node_or_null("/root/Global")
	if g != null and g.get("menu_settings") is Dictionary:
		var ms: Dictionary = g.get("menu_settings")
		_touch_floating_sticks = bool(ms.get("touch_floating_sticks", false))
		_touch_left_spring = bool(ms.get("touch_left_spring", false))
		_touch_sensitivity = clampf(float(ms.get("touch_sensitivity", 1.0)), 0.4, 1.6)
		_touch_expo = clampf(float(ms.get("touch_expo", 0.2)), 0.0, 0.7)
	_refresh_more_panel_labels()


func _make_quick_btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.custom_minimum_size = Vector2(0, 46)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", Color(0.90, 0.96, 0.92))
	b.button_down.connect(cb)
	return b


func _build_more_panel() -> void:
	_more_panel = PanelContainer.new()
	_more_panel.name = "TouchMorePanel"
	_more_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_more_panel.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.06, 0.05, 0.92)
	sb.border_color = Color(0.45, 0.78, 0.56, 0.70)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	_more_panel.add_theme_stylebox_override("panel", sb)
	_root.add_child(_more_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	_more_panel.add_child(vb)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(grid)

	_float_button = _make_quick_btn(_tx("ПЛАВ. СТІК: ВИКЛ", "FLOATING STICK: OFF"), _on_toggle_floating_sticks)
	_float_button.name = "TouchFloatingButton"
	grid.add_child(_float_button)

	_spring_button = _make_quick_btn(_tx("ГАЗ: КЛАСИК", "THROTTLE: CLASSIC"), _on_toggle_left_spring)
	_spring_button.name = "TouchSpringButton"
	grid.add_child(_spring_button)

	_tilt_down_button = _make_quick_btn(_tx("КАМЕРА -5°", "CAMERA -5°"), _adjust_camera_tilt.bind(-5.0))
	_tilt_down_button.name = "TouchTiltDownButton"
	grid.add_child(_tilt_down_button)

	_tilt_up_button = _make_quick_btn(_tx("КАМЕРА +5°", "CAMERA +5°"), _adjust_camera_tilt.bind(5.0))
	_tilt_up_button.name = "TouchTiltUpButton"
	grid.add_child(_tilt_up_button)

	_flight_button = _make_quick_btn(_tx("РЕЖИМ: ANGLE", "MODE: ANGLE"), _on_flight_pressed)
	_flight_button.name = "TouchFlightModeButton"
	grid.add_child(_flight_button)

	_mode_button = _make_quick_btn(_tx("ВВІД: СЕНСОР", "INPUT: TOUCH"), _on_mode_pressed)
	_mode_button.name = "TouchModeButton"
	grid.add_child(_mode_button)

	_video_button = _make_quick_btn(_tx("ВІДЕО", "VIDEO"), _on_action_pressed.bind("cycle_video_mode"))
	_video_button.name = "TouchVideoButton"
	grid.add_child(_video_button)

	_reset_button = _make_quick_btn(_tx("РЕСЕТ", "RESET"), _on_action_pressed.bind("respawn"))
	_reset_button.name = "TouchResetButton"
	grid.add_child(_reset_button)

	_panel_menu_button = _make_quick_btn(_tx("МЕНЮ / ПАУЗА", "MENU / PAUSE"), _on_pause_pressed)
	_panel_menu_button.name = "TouchPanelMenuButton"
	vb.add_child(_panel_menu_button)


func _refresh_more_panel_labels() -> void:
	if _float_button != null:
		_float_button.text = _tx(
				"ПЛАВ. СТІК: ВКЛ" if _touch_floating_sticks else "ПЛАВ. СТІК: ВИКЛ",
				"FLOATING STICK: ON" if _touch_floating_sticks else "FLOATING STICK: OFF")
	if _spring_button != null:
		_spring_button.text = _tx(
				"ГАЗ: ПРУЖИНА" if _touch_left_spring else "ГАЗ: КЛАСИК",
				"THROTTLE: SPRING" if _touch_left_spring else "THROTTLE: CLASSIC")
	_style_more_panel_buttons()


func _style_more_panel_buttons() -> void:
	for b in [_float_button, _spring_button, _tilt_down_button, _tilt_up_button,
			_flight_button, _mode_button, _video_button, _reset_button, _panel_menu_button]:
		if b == null:
			continue
		var active := false
		if b == _float_button:
			active = _touch_floating_sticks
		elif b == _spring_button:
			active = _touch_left_spring
		elif b == _mode_button:
			active = touch_mode
		var n := StyleBoxFlat.new()
		n.bg_color = Color(0.11, 0.24, 0.16, 0.94) if active else Color(0.05, 0.09, 0.08, 0.90)
		n.border_color = Color(0.55, 0.90, 0.65, 0.85) if active else Color(0.45, 0.65, 0.52, 0.50)
		n.set_border_width_all(1)
		n.set_corner_radius_all(8)
		var p := n.duplicate() as StyleBoxFlat
		p.bg_color = Color(0.18, 0.36, 0.24, 0.98)
		b.add_theme_stylebox_override("normal", n)
		b.add_theme_stylebox_override("hover", n)
		b.add_theme_stylebox_override("pressed", p)


func _on_toggle_floating_sticks() -> void:
	Haptics.trigger_ui_tap()
	_touch_floating_sticks = not _touch_floating_sticks
	var g := get_node_or_null("/root/Global")
	if g != null and g.get("menu_settings") is Dictionary:
		g.menu_settings["touch_floating_sticks"] = _touch_floating_sticks
		if g.has_method("save_menu_settings"):
			g.save_menu_settings()
	if not _touch_floating_sticks and _left_index == NO_TOUCH and _right_index == NO_TOUCH:
		_left_center = _left_anchor
		_right_center = _right_anchor
		if _drawer != null:
			_drawer.queue_redraw()
	_refresh_more_panel_labels()
	_show_toast(_tx(
			"ПЛАВАЮЧИЙ СТІК: %s" % ("ВКЛ" if _touch_floating_sticks else "ВИКЛ"),
			"FLOATING STICK: %s" % ("ON" if _touch_floating_sticks else "OFF")))


func _on_toggle_left_spring() -> void:
	Haptics.trigger_ui_tap()
	_touch_left_spring = not _touch_left_spring
	var g := get_node_or_null("/root/Global")
	if g != null and g.get("menu_settings") is Dictionary:
		g.menu_settings["touch_left_spring"] = _touch_left_spring
		if g.has_method("save_menu_settings"):
			g.save_menu_settings()
	if _left_index == NO_TOUCH:
		if _touch_left_spring:
			throttle = 0.45
			_left_knob = Vector2.ZERO
		else:
			_left_knob = Vector2(0.0, (0.5 - throttle) * 2.0 * _radius)
		if _drawer != null:
			_drawer.queue_redraw()
	_refresh_more_panel_labels()
	_show_toast(_tx(
			"ЛІВИЙ СТІК: %s" % ("ПРУЖИНА (ANGLE)" if _touch_left_spring else "КЛАСИК 0-100%"),
			"LEFT STICK: %s" % ("SPRING (ANGLE)" if _touch_left_spring else "CLASSIC 0-100%")))


func _adjust_camera_tilt(delta_deg: float) -> void:
	Haptics.trigger_ui_tap()
	var scene := get_tree().current_scene
	var fpv: Camera3D = null
	if scene != null:
		var cam = scene.get("camera")
		if cam is Camera3D and cam.name == "FPVCamera":
			fpv = cam as Camera3D
		if fpv == null:
			var drone := scene.get_node_or_null("Drone")
			if drone != null:
				fpv = drone.get_node_or_null("FPVCamera") as Camera3D
	if fpv == null:
		var vp := get_viewport()
		var c := vp.get_camera_3d() if vp != null else null
		if c != null and c.name == "FPVCamera":
			fpv = c
	var qs := get_node_or_null("/root/QuadSettings")
	if fpv != null:
		var new_pitch := clampf(fpv.rotation_degrees.x + delta_deg, -35.0, 45.0)
		fpv.rotation_degrees.x = new_pitch
		if fpv.has_meta("base_rot"):
			var br := fpv.get_meta("base_rot") as Vector3
			fpv.set_meta("base_rot", Vector3(new_pitch, br.y, br.z))
		if qs != null:
			qs.set("angle", int(roundf(new_pitch)))
		if scene != null and scene.has_method("_on_camera_tilt_changed"):
			scene.call("_on_camera_tilt_changed", new_pitch)
		_show_toast(_tx("КАМЕРА: %+d°" % int(roundf(new_pitch)),
				"CAMERA: %+d°" % int(roundf(new_pitch))))
	else:
		var cur_q := int(qs.get("angle")) if qs != null else 0
		var next_q := clampi(cur_q + roundi(delta_deg), -35, 45)
		if qs != null:
			qs.set("angle", next_q)
		_show_toast(_tx("КАМЕРА: %+d°" % next_q, "CAMERA: %+d°" % next_q))


func _on_more_pressed() -> void:
	Haptics.trigger_ui_tap()
	_bar_open = not _bar_open
	refresh_touch_settings()
	_sync_flight_mode_label()
	_apply_top_bar_visibility()
	_layout()


func _apply_top_bar_visibility() -> void:
	var live := enabled and not _preview
	if _pause_button != null:
		_pause_button.visible = live
	if _more_button != null:
		_more_button.visible = live
	var open := live and _bar_open
	if _more_panel != null:
		_more_panel.visible = open
	for b in [_flight_button, _setup_button, _reset_button, _video_button, _mode_button]:
		if b != null:
			b.visible = open


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
	# Notch / Dynamic Island / rounded-corner / home-indicator safe area.
	var safe_dict := MenuUI.get_safe_margins(vs)
	var notch := Vector4(
		maxf(float(safe_dict.get("left", 0.0)), MenuUI.mobile_notch_insets(vs).x),
		maxf(float(safe_dict.get("top", 0.0)), MenuUI.mobile_notch_insets(vs).y),
		maxf(float(safe_dict.get("right", 0.0)), MenuUI.mobile_notch_insets(vs).z),
		maxf(float(safe_dict.get("bottom", 0.0)), MenuUI.mobile_notch_insets(vs).w)
	)
	if _preview:
		# Menu calibration: compact sticks in the bottom corners keep the
		# instruction card and action buttons clear in the middle.  The UI
		# canvas is 1080 units high on a phone (canvas_items stretch), hence
		# the larger radius than the raw physical window might suggest.
		_radius = clampf(minf(vs.x, vs.y) * 0.115, 96.0, 120.0)
		var preview_bottom := vs.y - 16.0 - notch.w
		_left_anchor = Vector2(_radius + 34.0 + notch.x, preview_bottom - _radius)
		_right_anchor = Vector2(vs.x - _radius - 34.0 - notch.z, preview_bottom - _radius)
	else:
		# Larger sticks pulled in from the edges and lifted clear of the
		# home-indicator strip.  The pilot's thumbs naturally rest at
		# 28 % / 72 % of the width.
		_radius = clampf(minf(vs.x, vs.y) * 0.16, 86.0, 176.0)
		var bottom := vs.y - maxf(64.0, notch.w + 16.0)
		_left_anchor = Vector2(maxf(vs.x * 0.28, _radius + notch.x + 12.0),
				bottom - _radius)
		_right_anchor = Vector2(minf(vs.x * 0.72,
				vs.x - _radius - notch.z - 12.0), bottom - _radius)
	if _left_index == NO_TOUCH:
		_left_center = _left_anchor
	if _right_index == NO_TOUCH:
		_right_center = _right_anchor
	# In-flight compact menu/options anchor at top-left, placed cleanly below
	# telemetry & 3-line mission badge HUD rows (bottom ~158) while leaving
	# the left thumb stick clear.
	var side_x := 18.0 + notch.x
	var menu_w := 132.0
	var menu_h := 54.0
	var more_h := 48.0
	var min_side_y := notch.y + 178.0
	var max_side_y := maxf(min_side_y, _left_anchor.y - _radius - menu_h - more_h - 14.0)
	var side_y := clampf(min_side_y, min_side_y, max_side_y)
	if _pause_button != null and _more_button != null:
		_pause_button.position = Vector2(side_x, side_y)
		_pause_button.size = Vector2(menu_w, menu_h)
		_more_button.position = Vector2(side_x, side_y + menu_h + 8.0)
		_more_button.size = Vector2(menu_w, more_h)
	if _more_panel != null:
		var panel_w := clampf(344.0, 240.0, maxf(240.0, vs.x - side_x - menu_w - notch.z - 22.0))
		var panel_h := minf(276.0, maxf(190.0, vs.y - side_y - notch.w - 16.0))
		_more_panel.position = Vector2(side_x + menu_w + 10.0, side_y)
		_more_panel.size = Vector2(panel_w, panel_h)
	_apply_top_bar_visibility()
	var arm_w := 220.0
	var arm_x := clampf(vs.x * 0.5 - arm_w * 0.5, notch.x + 12.0, vs.x - notch.z - arm_w - 12.0)
	var arm_y := clampf(vs.y - 170.0 - notch.w, notch.y + 80.0, vs.y - notch.w - 92.0)
	_arm_button.position = Vector2(arm_x, arm_y)
	_arm_button.size = Vector2(arm_w, 78.0)
	var drop_size := clampf(_radius * 0.60, 78.0, 106.0)
	_drop_button.position = Vector2(_left_anchor.x + _radius + 24.0,
			_left_anchor.y - drop_size * 0.5)
	_drop_button.size = Vector2(drop_size, drop_size)
	_drop_button.add_theme_font_size_override("font_size", int(clampf(drop_size * 0.24, 16.0, 24.0)))
	var drop_style := StyleBoxFlat.new()
	drop_style.bg_color = Color(0.20, 0.075, 0.04, 0.86)
	drop_style.border_color = Color(1.0, 0.60, 0.30, 0.85)
	drop_style.set_border_width_all(2)
	drop_style.set_corner_radius_all(int(drop_size * 0.5))
	var drop_pressed := drop_style.duplicate() as StyleBoxFlat
	drop_pressed.bg_color = Color(0.48, 0.14, 0.07, 0.95)
	_drop_button.add_theme_stylebox_override("normal", drop_style)
	_drop_button.add_theme_stylebox_override("hover", drop_style)
	_drop_button.add_theme_stylebox_override("pressed", drop_pressed)
	_drop_button.visible = enabled and touch_mode and not _preview
	if _toast != null:
		_toast.position = Vector2(vs.x * 0.5 - 330.0, 238.0 + notch.y)
		_toast.size = Vector2(660.0, 52.0)
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
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.04, 0.07, 0.10, 0.72)
	normal.border_color = Color(0.55, 0.82, 1.0, 0.5)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(8)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.12, 0.30, 0.44, 0.85)
	for b in [_pause_button, _setup_button, _more_button]:
		if b != null:
			b.add_theme_stylebox_override("normal", normal)
			b.add_theme_stylebox_override("hover", normal)
			b.add_theme_stylebox_override("pressed", pressed)
	_style_more_panel_buttons()
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
	if _mode_button != null:
		_mode_button.text = _tx("ВВІД: СЕНСОР", "INPUT: TOUCH") if touch_mode \
				else _tx("ВВІД: ПУЛЬТ", "INPUT: RC")
		_style_more_panel_buttons()
	if _drop_button != null:
		_drop_button.visible = enabled and touch_mode and not _preview
		var action := _touch_payload_action()
		_drop_button.text = _tx("БЧ", "WARHEAD") if action == "activate_payload" \
				else _tx("СКИД", "DROP")


func _on_mode_pressed() -> void:
	Haptics.trigger_ui_tap()
	set_controller_only(touch_mode)
	_show_toast(_tx("ВВІД: %s" % ("СЕНСОР" if touch_mode else "ПУЛЬТ"),
			"INPUT: %s" % ("TOUCH" if touch_mode else "RC")))


func _on_arm_pressed() -> void:
	# Drive the flight controller directly and ONLY once.  Dispatching
	# toggle_arm as well made Level._input see a second edge in the same
	# frame and immediately disarm (or switch modes through an AUX switch),
	# so the ARM button appeared dead on the phone.
	var scene := get_tree().current_scene
	var drone := scene.get_node_or_null("Drone") if scene != null else null
	var fc = drone.get("flight_controller") if drone != null else null
	if fc != null:
		if bool(fc.get("state_armed")):
			fc.request_disarm()
			_show_toast(_tx("ДИСАРМ", "DISARM"))
		else:
			var armed := bool(fc.call("request_arm", true))
			_show_toast(_tx("АРМ", "ARM") if armed \
					else _tx("АРМ НЕ ДОЗВОЛЕНО", "ARMING NOT ALLOWED"))
			if not armed:
				Haptics.trigger_ui_tap()
		return
	Haptics.trigger_ui_tap()
	# Menu / calibration preview has no flight controller: keep the synthetic
	# action path for any listener that still wants the edge.
	_dispatch_action("toggle_arm")


func _on_pause_pressed() -> void:
	_dispatch_action("pause_menu")


func _on_flight_pressed() -> void:
	Haptics.trigger_ui_tap()
	var scene := get_tree().current_scene
	var drone := scene.get_node_or_null("Drone") if scene != null else null
	var fc = drone.get("flight_controller") if drone != null else null
	if fc != null and fc.has_method("select_flight_mode"):
		var cur := int(fc.get("flight_mode"))
		# 0 = RATE (ACRO), 1 = LEVEL (ANGLE)
		var want := 0 if cur == 1 else 1
		if fc.has_method("is_mode_available") and not bool(fc.call("is_mode_available", want)):
			_dispatch_action("cycle_flight_modes")
		else:
			fc.call("select_flight_mode", want)
		_sync_flight_mode_label()
		var after := int(fc.get("flight_mode"))
		var mode_txt := "ANGLE" if after == 1 else ("ACRO" if after == 0 else "HORIZON")
		_show_toast(_tx("РЕЖИМ: %s" % mode_txt, "MODE: %s" % mode_txt))
		return
	_dispatch_action("cycle_flight_modes")


func _on_action_pressed(action: String) -> void:
	Haptics.trigger_ui_tap()
	if action == "deploy_payload":
		var actual_action := _touch_payload_action()
		if not _payload_available(actual_action):
			_show_toast(_tx("НЕМАЄ БОЄПРИПАСУ", "NO PAYLOAD AVAILABLE"))
			return
		_show_toast(_tx("БЧ АКТИВОВАНО", "WARHEAD DETONATED")
				if actual_action == "activate_payload" else _tx("СКИД", "DROP"))
		_dispatch_action(actual_action)
		return
	_dispatch_action(action)


func _touch_payload_action() -> String:
	var preset := DroneCatalog.preset(Global.drone_preset)
	if bool(preset.get("kamikaze", false)) and not bool(preset.get("has_drop", false)):
		return "activate_payload"
	return "deploy_payload"


func _payload_available(action: String = "deploy_payload") -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return true
	if bool(scene.get("_payload_dropped")):
		return false
	# Kamikaze/warhead drones carry an integrated charge rather than a
	# detachable ammo count, so they must not be rejected by the drop-ammo HUD.
	if action == "activate_payload":
		var payload_enabled = scene.get("_payload_enabled")
		return payload_enabled == null or bool(payload_enabled)
	if scene.has_method("_ammo_count"):
		if int(scene.call("_ammo_count")) <= 0:
			return false
	var enabled = scene.get("_payload_enabled")
	if enabled is bool and not bool(enabled):
		return false
	return true


func _show_toast(text: String) -> void:
	if _toast == null:
		return
	_toast.text = MenuUI.translate_text(text)
	_toast.visible = true
	_toast_time = 1.4


func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		if _toast_time <= 0.0 and _toast != null:
			_toast.visible = false
	_mode_refresh -= delta
	if _mode_refresh <= 0.0:
		_mode_refresh = 0.35
		_sync_flight_mode_label()
		if enabled and not _preview:
			var elrs := get_node_or_null("/root/ElrsWifiInput")
			var live_elrs: bool = elrs != null and bool(elrs.get("valid"))
			if touch_mode and live_elrs and _configured_input_mode() == "auto":
				touch_mode = false
				_reset_sticks()
				_update_mode_button()
				_drawer.queue_redraw()
				mode_changed.emit(false)
	if _drawer != null and _touch_floating_sticks and touch_mode:
		var moved := false
		var k := minf(1.0, delta * 14.0)
		if _left_index == NO_TOUCH and _left_center.distance_to(_left_anchor) > 0.5:
			_left_center = _left_center.lerp(_left_anchor, k)
			if _left_center.distance_to(_left_anchor) <= 0.5:
				_left_center = _left_anchor
			moved = true
		if _right_index == NO_TOUCH and _right_center.distance_to(_right_anchor) > 0.5:
			_right_center = _right_center.lerp(_right_anchor, k)
			if _right_center.distance_to(_right_anchor) <= 0.5:
				_right_center = _right_anchor
			moved = true
		if moved:
			_drawer.queue_redraw()


func _sync_flight_mode_label() -> void:
	if _flight_button == null:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var drone := scene.get_node_or_null("Drone")
	var fc = drone.get("flight_controller") if drone != null else null
	if fc == null:
		_flight_button.text = _tx("РЕЖИМ", "MODE")
		return
	var mode := int(fc.get("flight_mode"))
	var names := ["ACRO", "ANGLE", "SPEED", "TRACK", "LAUNCH", "TURTLE", "AUTO", "HORIZON"]
	var label: String = names[mode] if mode >= 0 and mode < names.size() else str(mode)
	_flight_button.text = _tx("РЕЖИМ: %s" % label, "MODE: %s" % label)


func _dispatch_action(action: String) -> void:
	if not InputMap.has_action(action):
		return
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	event.strength = 1.0
	Input.parse_input_event(event)
	# Also pulse the polling state so handlers using is_action_just_pressed() see a clean edge
	Input.action_press(action)
	call_deferred("_release_action", action)


func _release_action(action: String) -> void:
	if InputMap.has_action(action):
		Input.action_release(action)


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
	title.text = _tx("НАЛАШТУВАННЯ ELRS / СЕНСОРА", "ELRS / TOUCH SETUP")
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.92, 0.97, 1.0))
	vb.add_child(title)

	var hint := Label.new()
	hint.text = _tx(
		"Тут — ARM, режими й відео. Скид, застосування БЧ, ресет та інші дії призначаються в «Налаштування → КЕРУВАННЯ» (працює з ELRS на телефоні).",
		"Configure ARM, flight modes, and video here. Payload release, warhead activation, reset, and other actions are assigned under Settings → Controls. ELRS works over your phone's local Wi-Fi.")
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

	_arm_option = _make_mapping_row(vb, _tx("Канал ARM", "ARM CHANNEL"), "arm",
			_elrs_channel("arm_channel", 4))
	_mode_option = _make_mapping_row(vb, _tx("Канал режимів", "FLIGHT MODE CHANNEL"), "mode",
			_elrs_channel("mode_channel", 5))
	_video_option = _make_mapping_row(vb, _tx("Канал відео", "VIDEO CHANNEL"), "video",
			_elrs_channel("video_channel", 6))

	var invert_box := HBoxContainer.new()
	invert_box.add_theme_constant_override("separation", 22)
	vb.add_child(invert_box)
	_invert_elrs_check = CheckBox.new()
	_invert_elrs_check.text = _tx("Інверсія крену (ELRS)", "Invert ELRS roll")
	_invert_elrs_check.add_theme_font_size_override("font_size", 15)
	_invert_elrs_check.add_theme_color_override("font_color", Color(0.92, 0.97, 1.0))
	_invert_elrs_check.toggled.connect(_on_invert_elrs_toggled)
	invert_box.add_child(_invert_elrs_check)
	_invert_touch_check = CheckBox.new()
	_invert_touch_check.text = _tx("Інверсія крену (сенсор)", "Invert touch roll")
	_invert_touch_check.add_theme_font_size_override("font_size", 15)
	_invert_touch_check.add_theme_color_override("font_color", Color(0.92, 0.97, 1.0))
	_invert_touch_check.toggled.connect(_on_invert_touch_toggled)
	invert_box.add_child(_invert_touch_check)
	_invert_touch_pitch_check = CheckBox.new()
	_invert_touch_pitch_check.text = _tx("Інверсія тангажу (сенсор)", "Invert touch pitch")
	_invert_touch_pitch_check.add_theme_font_size_override("font_size", 15)
	_invert_touch_pitch_check.add_theme_color_override("font_color", Color(0.92, 0.97, 1.0))
	_invert_touch_pitch_check.toggled.connect(_on_invert_touch_pitch_toggled)
	invert_box.add_child(_invert_touch_pitch_check)

	var close := Button.new()
	close.text = _tx("ЗАКРИТИ", "CLOSE")
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


func _on_invert_touch_pitch_toggled(on: bool) -> void:
	invert_pitch = on
	var gs := get_node_or_null("/root/GameSettings")
	if gs != null:
		gs.hud_config["touch_invert_pitch"] = on
		gs.save_hud_config()


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
	if _invert_touch_pitch_check != null:
		_invert_touch_pitch_check.set_pressed_no_signal(invert_pitch)
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
	if not enabled or (get_tree().paused and not _preview) or (not _preview and _any_modal_menu_open()):
		return
	if event is InputEventScreenTouch and not touch_mode:
		var t_ev := event as InputEventScreenTouch
		if _preview:
			if t_ev.pressed:
				touch_mode = true
				_reset_sticks()
				_update_mode_button()
				mode_changed.emit(touch_mode)
		elif t_ev.pressed and _configured_input_mode() == "auto" and not _has_active_controller() \
				and not _point_hits_ui(t_ev.position):
			# Only activate touch sticks on a genuine flight-area touch when no
			# physical controller is active and the user has not locked controller mode.
			var vp := get_viewport()
			var vs := vp.get_visible_rect().size if vp != null else Vector2(1280, 720)
			if t_ev.position.y >= vs.y * 0.45:
				touch_mode = true
				_reset_sticks()
				_update_mode_button()
				mode_changed.emit(touch_mode)
		else:
			return
	if not touch_mode:
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


func _point_hits_ui(pos: Vector2) -> bool:
	if _setup_root != null and _setup_root.visible:
		return true
	for c in [_pause_button, _more_button, _arm_button, _drop_button, _more_panel]:
		if c != null and c.visible and c.get_global_rect().has_point(pos):
			return true
	var scene := get_tree().current_scene if get_tree() != null else null
	if scene != null:
		var help_btn := scene.find_child("TutorialHelpBtn", true, false) as Control
		if help_btn != null and help_btn.is_visible_in_tree() and help_btn.get_global_rect().has_point(pos):
			return true
	return false


func _apply_axis_curve(raw_val: float, deadzone: float, use_sensitivity: bool) -> float:
	var mag := absf(raw_val)
	if mag < deadzone:
		return 0.0
	var s := clampf(raw_val, -1.0, 1.0)
	if deadzone > 0.0 and deadzone < 0.9:
		s = signf(s) * ((absf(s) - deadzone) / (1.0 - deadzone))
	var curved := (1.0 - _touch_expo) * s + _touch_expo * (s * s * s)
	if use_sensitivity:
		curved *= _touch_sensitivity
	return clampf(curved, -1.0, 1.0)


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
	if _point_hits_ui(pos):
		return false
	var vp := get_viewport()
	var vs := vp.get_visible_rect().size if vp != null else Vector2(1280, 720)
	if _touch_floating_sticks:
		var safe_min_y := 100.0
		var safe_max_y := maxf(safe_min_y + 20.0, vs.y - BOTTOM_MARGIN - _radius * 0.7)
		if _left_index == NO_TOUCH and pos.x < vs.x * 0.5:
			var min_lx := maxf(MARGIN, _radius * 0.7)
			var max_lx := maxf(min_lx + 10.0, vs.x * 0.5 - _radius * 0.45)
			_left_center = Vector2(clampf(pos.x, min_lx, max_lx),
					clampf(pos.y, safe_min_y, safe_max_y))
			_left_index = index
			_throttle_grab_y = pos.y
			_throttle_grab_value = throttle
			_update_stick(true, pos)
			return true
		if _right_index == NO_TOUCH and pos.x >= vs.x * 0.5:
			var min_rx := vs.x * 0.5 + _radius * 0.45
			var max_rx := maxf(min_rx + 10.0, vs.x - maxf(MARGIN, _radius * 0.7))
			_right_center = Vector2(clampf(pos.x, min_rx, max_rx),
					clampf(pos.y, safe_min_y, safe_max_y))
			_right_index = index
			_update_stick(false, pos)
			return true
		return false
	if _left_index == NO_TOUCH and pos.distance_to(_left_center) <= _radius * 1.35:
		_left_index = index
		_throttle_grab_y = pos.y
		_throttle_grab_value = throttle
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
	var deadzone := Controls.stick_deadzone if Controls != null else 0.02
	var center := _left_center if left else _right_center
	var raw_offset := pos - center
	# Clamp pitch/roll/yaw/throttle axes independently inside [-radius, radius]
	# (square gimbal travel matching real RC gimbals) instead of circular
	# limit_length(), so full Yaw + full Throttle or diagonal roll+pitch
	# corners don't cap each other at ~70%.
	var offset := Vector2(
			clampf(raw_offset.x, -_radius, _radius),
			clampf(raw_offset.y, -_radius, _radius))
	if left:
		var active_drag_dy := absf(pos.y - _throttle_grab_y) if (not _touch_left_spring and _left_index != NO_TOUCH) else absf(offset.y)
		var yaw_deadband := maxf(deadzone, 0.09) if active_drag_dy > _radius * 0.22 else deadzone
		if _touch_left_spring:
			var y_norm := clampf((_left_center.y - pos.y) / _radius, -1.0, 1.0)
			var y_curved := _apply_axis_curve(y_norm, maxf(deadzone, 0.06), false)
			# Spring centre aligns with real hover thrust (0.45) instead of 0.50 climb.
			if y_curved >= 0.0:
				throttle = clampf(0.45 + y_curved * 0.55, 0.0, 1.0)
			else:
				throttle = clampf(0.45 + y_curved * 0.45, 0.0, 1.0)
		else:
			# Directional relative throttle with a gentle idle/hover band feel.
			var dy := _throttle_grab_y - pos.y
			var up_span := maxf(_radius * 0.70, _throttle_grab_y - (_left_center.y - _radius))
			var down_span := maxf(_radius * 0.70, (_left_center.y + _radius) - _throttle_grab_y)
			var span := up_span if dy >= 0.0 else down_span
			var next_thr := clampf(_throttle_grab_value + dy / span, 0.0, 1.0)
			# Soft detent right at 0.45 hover when near mid-stick to make mobile altitude holding steady.
			if absf(next_thr - 0.45) < 0.025 and absf(offset.x / maxf(_radius, 1.0)) > 0.12:
				next_thr = 0.45
			throttle = next_thr
		_left_knob = Vector2(offset.x, (0.5 - throttle) * 2.0 * _radius)
		var x := offset.x / _radius
		yaw = _apply_axis_curve(x, yaw_deadband, true)
	else:
		_right_knob = offset
		var x := offset.x / _radius
		var y := offset.y / _radius
		var r := _apply_axis_curve(x, deadzone, true)
		if invert_roll:
			r = -r
		roll = r
		pitch = _apply_axis_curve(y, deadzone, true)
		if invert_pitch:
			pitch = -pitch
	_drawer.queue_redraw()


func _release_stick(left: bool) -> void:
	if left:
		_left_index = NO_TOUCH
		# In center-spring mode (ANGLE hover) throttle returns cleanly to 0.5;
		# otherwise throttle holds while yaw self-centres.
		_left_knob.x = 0.0
		yaw = 0.0
		if _touch_left_spring:
			throttle = 0.45
			_left_knob.y = 0.0
		if not _touch_floating_sticks and _left_anchor != Vector2.ZERO:
			_left_center = _left_anchor
	else:
		_right_index = NO_TOUCH
		_right_knob = Vector2.ZERO
		roll = 0.0
		pitch = 0.0
		if not _touch_floating_sticks and _right_anchor != Vector2.ZERO:
			_right_center = _right_anchor
	_drawer.queue_redraw()


func _reset_sticks() -> void:
	_left_index = NO_TOUCH
	_right_index = NO_TOUCH
	_mouse_down = false
	if _left_anchor != Vector2.ZERO:
		_left_center = _left_anchor
	if _right_anchor != Vector2.ZERO:
		_right_center = _right_anchor
	if _touch_left_spring:
		throttle = 0.5
		_left_knob = Vector2.ZERO
	else:
		# Throttle 0 is the bottom of the left stick, not its centre.
		throttle = 0.0
		_left_knob = Vector2(0.0, _radius)
	_right_knob = Vector2.ZERO
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
	_draw_stick(_drawer, _left_center, _left_knob, 1.0)
	_draw_stick(_drawer, _right_center, _right_knob, 1.0)


func _draw_stick(c: Control, center: Vector2, knob: Vector2, alpha: float) -> void:
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


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT \
			or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		# Do not keep a throttle value when the phone is backgrounded.
		_reset_sticks()


func _exit_tree() -> void:
	var vp := get_viewport()
	if vp != null and vp.size_changed.is_connected(_layout):
		vp.size_changed.disconnect(_layout)
	if _setup_timer != null and is_instance_valid(_setup_timer):
		_setup_timer.stop()
	if _root != null and is_instance_valid(_root):
		_root.queue_free()
		_root = null
		_drawer = null
		_setup_root = null
		_setup_panel = null
		_setup_timer = null
