## Mobile tactical menu — a phone-first shell for the existing game systems.
##
## The layout follows the reference mobile FPV menus: a large left navigation,
## a cinematic drone hero, compact cards, big segmented tabs and finger-sized
## rows.  Colours and imagery stay in the Ukrainian mil-tech style of the game.
##
## This scene is standalone while the design is being reviewed.  It can be
## opened directly (res://GUI/mobile/MobileMenu.tscn) or from the old menu's
## beta link later, without touching the flight scenes.
extends Control

const BG_TEX: Texture2D = preload("res://Assets/Branding/mobile_menu_bg.png")
const BG_BLUR_TEX: Texture2D = preload("res://Assets/Branding/mobile_menu_bg_blur.png")
const DRONE_TEX: Texture2D = preload("res://Assets/Branding/mobile_menu_drone.png")
const KNOB_TEX: Texture2D = preload("res://Assets/Branding/mobile_knob.png")
const GRID_TEX: Texture2D = preload("res://Assets/Branding/mobile_grid.png")
const ROUNDED_SHADER: Shader = preload("res://GUI/mobile/rounded_rect.gdshader")

const MAP_IMAGES := {
	"steppe": preload("res://Assets/Branding/mobile_map_steppe.png"),
	"village": preload("res://Assets/Branding/mobile_map_village.png"),
	"industrial": preload("res://Assets/Branding/mobile_map_industrial.png"),
	"wetlands": preload("res://Assets/Branding/mobile_map_wetlands.png"),
}
const MAP_META := [
	{"id": "steppe", "name": "СТЕП", "tag": "ВІДКРИТА МІСЦЕВІСТЬ", "diff": "ЛЕГКА", "col": "79a58a"},
	{"id": "village", "name": "СЕЛО", "tag": "МІСЬКА ЗАБУДОВА", "diff": "СЕРЕДНЯ", "col": "e2c276"},
	{"id": "industrial", "name": "ПРОМЗОНА", "tag": "ЗАВОДИ Й ТРУБИ", "diff": "СКЛАДНА", "col": "c96f67"},
	{"id": "wetlands", "name": "БОЛОТА", "tag": "ВОДА Й ОЧЕРЕТ", "diff": "СКЛАДНА", "col": "79a58a"},
]
const MODE_META := [
	{"id": 0, "name": "ТРЕНУВАННЯ"},
	{"id": 1, "name": "БОЙОВИЙ"},
	{"id": 2, "name": "ШВИДКІСНИЙ"},
	{"id": 3, "name": "ТУТОРІАЛ"},
	{"id": 4, "name": "ХАОС"},
]
const RATE_AXES := [
	{"key": "roll", "name": "ROLL", "col": Color("c96f67")},
	{"key": "pitch", "name": "PITCH", "col": Color("79a58a")},
	{"key": "yaw", "name": "YAW", "col": Color("7f9bc4")},
]
const DRONE_TABS := [
	{"id": "frame", "name": "КОРПУС"},
	{"id": "motors", "name": "МОТОРИ"},
	{"id": "props", "name": "ПРОПЕЛЕРИ"},
	{"id": "battery", "name": "БАТАРЕЯ"},
	{"id": "straps", "name": "РЕМЕНІ"},
]
const DRONE_PARTS := {
	"frame": ["X5 VARAN FRAME", "SOURCE ONE 5", "APEX EVO 5"],
	"motors": ["2207 1960KV", "2207 2750KV", "2306 2450KV"],
	"props": ["51466 TRI-BLADE", "GEMFAN 5149", "HQ 5X4.3X3"],
	"battery": ["6S 1300 mAh", "6S 1100 mAh", "4S 1500 mAh"],
	"straps": ["LIPO STRAP", "TPU ANTENNA MOUNT", "ACTION-CAM MOUNT"],
}
const COLOR_SWATCHES := [
	{"name": "ХАКІ", "col": Color("59604a")},
	{"name": "ЧОРНИЙ", "col": Color("202622")},
	{"name": "ПІСОК", "col": Color("b09a72")},
	{"name": "СІРИЙ", "col": Color("5e6b66")},
]

var _bg_blur: TextureRect
var _screen_scrim: ColorRect
var _root: VBoxContainer
var _content: Control
var _screens: Dictionary = {}
var _current := "main"
var _back_btn: Button
var _menu_btn: Button
var _bottom_bar: HBoxContainer
var _bottom_mid: Label
var _bottom_player: Label
var _bottom_player_box: HBoxContainer
var _elrs_chip: PanelContainer
var _elrs_label: Label
var _input_chip: PanelContainer
var _input_label: Label

var _selected_map := "village"
var _selected_mode := 0
var _selected_mission := 1
var _map_group: ButtonGroup
var _map_cards: Dictionary = {}
var _mode_row: HBoxContainer
var _mission_row: HBoxContainer
var _mission_buttons: Dictionary = {}
var _mission_group: ButtonGroup
var _play_caption: Label

var _rate_tab := "radio"
var _rate_profiles: Dictionary = {}
var _rate_values: Dictionary = {}
var _rate_buttons: Dictionary = {}
var _rate_status: Label
var _rate_curve: RateCurve
var _rate_help: Control
var _rates_tabs_row: HBoxContainer
var _rates_tab_buttons: Dictionary = {}

var _drone_tab := "frame"
var _drone_parts: Dictionary = {}
var _drone_selected_color := "ХАКІ"
var _drone_color_label: Label
var _color_buttons: Dictionary = {}
var _drone_image: TextureRect
var _drone_caption: Label
var _drone_parts_box: VBoxContainer
var _drone_tab_buttons: Dictionary = {}
var _drone_tabs_row: HBoxContainer
var _photo_mode := false
var _photo_layer: Control

var _settings_name: LineEdit
var _settings_scale_value: Label
var _settings_fps_value: Label
var _settings_audio_value: Label
var _settings_music_toggle: ToggleSwitch
var _settings_ghost_toggle: ToggleSwitch
var _settings_racing_toggle: ToggleSwitch
var _settings_units_toggle: ToggleSwitch
var _stream_toggle: ToggleSwitch
var _stream_label: Label

var _source_buttons: Dictionary = {}
var _source_status: Label
var _stick_preview: StickPreview
var _invert_elrs_toggle: ToggleSwitch
var _invert_touch_toggle: ToggleSwitch


class ToggleSwitch extends Button:
	var on := false

	func _init(value: bool = false) -> void:
		on = value
		toggle_mode = true
		button_pressed = value
		focus_mode = Control.FOCUS_NONE
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(92, 44)
		add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		toggled.connect(_on_toggled)

	func _on_toggled(value: bool) -> void:
		on = value
		queue_redraw()

	func _draw() -> void:
		var h := size.y
		var r := h * 0.5
		var track := StyleBoxFlat.new()
		track.bg_color = Color(0.12, 0.22, 0.17, 0.95) if not on else Color(0.34, 0.57, 0.42, 0.98)
		track.border_color = Color(0.42, 0.56, 0.46, 0.7)
		track.set_border_width_all(1)
		track.set_corner_radius_all(int(r))
		draw_style_box(track, Rect2(Vector2.ZERO, size))
		var knob_x := size.x - r if on else r
		draw_circle(Vector2(knob_x, r), r * 0.73, Color(0.94, 0.97, 0.92, 1.0))


class StickPreview extends Control:
	var left := Vector2.ZERO
	var right := Vector2.ZERO

	func _init() -> void:
		custom_minimum_size = Vector2(0, 160)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_values(l: Vector2, r: Vector2) -> void:
		left = l.limit_length(1.0)
		right = r.limit_length(1.0)
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w < 20 or h < 30:
			return
		var radius := minf(w * 0.20, h * 0.36)
		var cy := h * 0.47
		var lc := Vector2(w * 0.28, cy)
		var rc := Vector2(w * 0.72, cy)
		_draw_stick(lc, radius, left, "THR / YAW")
		_draw_stick(rc, radius, right, "PITCH / ROLL")

	func _draw_stick(c: Vector2, r: float, value: Vector2, title: String) -> void:
		var fill := Color(0.03, 0.06, 0.05, 0.72)
		var rim := Color(0.48, 0.68, 0.54, 0.65)
		var cross := Color(0.48, 0.68, 0.54, 0.28)
		draw_circle(c, r, fill)
		draw_arc(c, r, 0.0, TAU, 48, rim, 1.5, true)
		draw_line(c - Vector2(r * 0.8, 0), c + Vector2(r * 0.8, 0), cross, 1.0)
		draw_line(c - Vector2(0, r * 0.8), c + Vector2(0, r * 0.8), cross, 1.0)
		var kp := c + Vector2(value.x, -value.y) * (r * 0.76)
		draw_circle(kp, r * 0.18, Color(0.93, 0.96, 0.91, 0.95))
		draw_arc(kp, r * 0.18, 0.0, TAU, 20, Color(0.40, 0.60, 0.46, 0.9), 1.2, true)
		var font := ThemeDB.fallback_font
		draw_string(font, c + Vector2(-r, -r - 8), title,
				HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 11,
				Color(0.72, 0.82, 0.74, 0.9))


class RateCurve extends Control:
	var profile: Dictionary = {}

	func _init() -> void:
		custom_minimum_size = Vector2(0, 150)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_profile(value: Dictionary) -> void:
		profile = value
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w < 10 or h < 10:
			return
		var left := 42.0
		var right := w - 18.0
		var top := 14.0
		var bottom := h - 24.0
		var grid := Color(0.30, 0.44, 0.35, 0.22)
		for i in range(5):
			var x := left + (right - left) * i / 4.0
			draw_line(Vector2(x, top), Vector2(x, bottom), grid, 1.0)
			var y := top + (bottom - top) * i / 4.0
			draw_line(Vector2(left, y), Vector2(right, y), grid, 1.0)
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(2, top + 5), "100%", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.65, 0.75, 0.68, 0.8))
		draw_string(font, Vector2(8, bottom + 12), "0", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.65, 0.75, 0.68, 0.8))
		draw_string(font, Vector2(right - 30, bottom + 12), "STICK", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.65, 0.75, 0.68, 0.8))
		var legend := [
			{"key": "roll", "name": "ROLL", "col": Color("c96f67")},
			{"key": "pitch", "name": "PITCH", "col": Color("79a58a")},
			{"key": "yaw", "name": "YAW", "col": Color("7f9bc4")},
		]
		for n in range(legend.size()):
			var item: Dictionary = legend[n]
			var lx := left + 10.0 + n * 74.0
			draw_rect(Rect2(lx, top + 2.0, 8.0, 8.0), item["col"] as Color, true)
			draw_string(font, Vector2(lx + 12.0, top + 10.0), str(item["name"]),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.72, 0.82, 0.74, 0.9))
		for n in range(legend.size()):
			var axis: Dictionary = legend[n]
			var rate := float(profile.get("rate_" + str(axis["key"]), 667))
			var expo := float(profile.get("expo_" + str(axis["key"]), 0.2))
			var shift := (float(n) - 1.0) * 2.5
			var points := PackedVector2Array()
			for i in range(33):
				var x := i / 32.0
				var shaped := x * (1.0 - expo) + pow(x, 3.0) * expo
				var norm := clampf(shaped * (rate / 900.0), 0.0, 1.0)
				points.append(Vector2(left + (right - left) * x,
						bottom - (bottom - top) * norm + shift))
			draw_polyline(points, axis["col"] as Color, 2.4 - n * 0.25, true)


func _ready() -> void:
	if OS.has_feature("mobile"):
		# Rotate with the device; the layout uses symmetric safe margins so the
		# camera notch is clear in both landscape orientations.
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)
	# This scene is the phone home screen, but it can also be opened directly
	# from the editor or a saved shortcut.  Make sure the persisted input,
	# graphics and audio settings are applied in that case too.
	if Global.startup:
		Global.initialize()
	Graphics.load_graphics_settings()
	Audio.load_audio_settings()
	Controls.load_input_map(true)
	KeyboardControls.ensure_bindings()
	Global.load_menu_settings()
	if DisplayServer.get_name() != "headless":
		Audio.play_menu_music()
	theme = MenuUI.theme()
	_build_background()
	_build_root()
	_build_main()
	_build_play()
	_show("main")
	_update_status()
	set_process(true)


func _process(_delta: float) -> void:
	_update_status()
	if _stick_preview != null:
		var mobile := get_node_or_null("/root/MobileInput")
		if mobile != null:
			_stick_preview.set_values(
					Vector2(float(mobile.call("axis", 3)), float(mobile.call("axis", 2))),
					Vector2(float(mobile.call("axis", 0)), -float(mobile.call("axis", 1))))


# --------------------------------------------------------------- scaling
func _vsize() -> Vector2:
	return get_viewport_rect().size


func _fs(px: float) -> int:
	return maxi(8, int(round(px * clampf(_vsize().y / 1080.0, 0.52, 1.6))))


func _gap(px: float) -> int:
	return maxi(2, int(round(px * clampf(_vsize().y / 1080.0, 0.5, 1.5))))


func _label(text: String, size: float, color: Color = MenuUI.TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", _fs(size))
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("outline_size", _gap(3))
	return l


func _panel_style(bg: Color = Color(0.035, 0.075, 0.06, 0.88),
		border: Color = Color(0.34, 0.5, 0.4, 0.5),
		border_width: int = 1, radius: int = 18) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = _gap(18)
	sb.content_margin_right = _gap(18)
	sb.content_margin_top = _gap(14)
	sb.content_margin_bottom = _gap(14)
	return sb


func _panel(bg: Color = Color(0.035, 0.075, 0.06, 0.88),
		border: Color = Color(0.34, 0.5, 0.4, 0.5),
		border_width: int = 1, radius: int = 18) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _panel_style(bg, border, border_width, radius))
	return p


func _button(text: String, height: float, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, _fs(height))
	b.add_theme_font_size_override("font_size", _fs(26 if not primary else 34))
	b.add_theme_color_override("font_color", Color(0.06, 0.09, 0.07) if primary else MenuUI.TEXT)
	b.add_theme_color_override("font_hover_color", Color(0.06, 0.09, 0.07) if primary else MenuUI.TEXT)
	b.add_theme_color_override("font_pressed_color", Color(0.06, 0.09, 0.07) if primary else MenuUI.TEXT)
	var normal_bg := Color(0.75, 0.84, 0.66, 0.98) if primary else Color(0.04, 0.08, 0.065, 0.86)
	var hover_bg := Color(0.85, 0.92, 0.74, 1.0) if primary else Color(0.08, 0.15, 0.11, 0.96)
	var pressed_bg := Color(0.60, 0.73, 0.52, 1.0) if primary else Color(0.10, 0.22, 0.15, 1.0)
	var border := Color(0.88, 0.76, 0.46, 0.9) if primary else Color(0.32, 0.48, 0.38, 0.6)
	b.add_theme_stylebox_override("normal", _panel_style(normal_bg, border, 1, 14))
	b.add_theme_stylebox_override("hover", _panel_style(hover_bg, border, 1, 14))
	b.add_theme_stylebox_override("pressed", _panel_style(pressed_bg, border, 1, 14))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


func _nav_button(icon: String, text: String, primary: bool) -> Button:
	var compact := _vsize().y < 700.0
	var height := (64.0 if not primary else 72.0) if compact \
			else (86.0 if not primary else 96.0)
	var b := _button("%s   %s" % [icon, text], height, primary)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", _fs(29 if not primary else 34))
	b.add_theme_constant_override("h_separation", _gap(12))
	return b


func _chip(text: String, col: Color) -> PanelContainer:
	var p := _panel(Color(0.03, 0.07, 0.055, 0.8), col, 1, 10)
	p.add_theme_stylebox_override("panel", _panel_style(Color(0.03, 0.07, 0.055, 0.8), col, 1, 10))
	var l := _label(text, 15, col)
	p.add_child(l)
	return p


func _masked_texture(tex: Texture2D, radius: int) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = ROUNDED_SHADER
	mat.set_shader_parameter("radius", float(radius))
	mat.set_shader_parameter("rect_size", tr.size)
	tr.material = mat
	tr.resized.connect(func() -> void:
		mat.set_shader_parameter("rect_size", tr.size)
		mat.set_shader_parameter("radius", float(radius))
	)
	return tr


func _scrim(bottom_alpha: float = 0.92) -> TextureRect:
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(0.01, 0.03, 0.025, 0.0),
			Color(0.01, 0.03, 0.025, bottom_alpha)])
	grad.offsets = PackedFloat32Array([0.45, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 4
	tex.height = 256
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


func _slider(value: float, minv: float, maxv: float, step: float,
		on_change: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = minv
	s.max_value = maxv
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(0, _fs(30))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_theme_icon_override("grabber", KNOB_TEX)
	s.add_theme_icon_override("grabber_highlight", KNOB_TEX)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.10, 0.18, 0.14, 0.95)
	track.set_corner_radius_all(_gap(4))
	track.content_margin_top = _gap(3)
	track.content_margin_bottom = _gap(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.47, 0.70, 0.53, 0.95)
	fill.set_corner_radius_all(_gap(4))
	fill.content_margin_top = _gap(3)
	fill.content_margin_bottom = _gap(3)
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	s.value_changed.connect(on_change)
	return s


func _stepper(value: float, minv: float, maxv: float, step: float,
		on_change: Callable, width: float = 250.0) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _gap(4))
	row.custom_minimum_size = Vector2(_fs(width), _fs(44))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var minus := _button("◀", 44)
	minus.custom_minimum_size = Vector2(_fs(38), _fs(44))
	minus.add_theme_font_size_override("font_size", _fs(18))
	row.add_child(minus)
	var value_label := _label("", 24, MenuUI.TEXT)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.custom_minimum_size = Vector2(_fs(90), 0)
	value_label.size_flags_horizontal = Control.SIZE_FILL
	row.add_child(value_label)
	var plus := _button("▶", 44)
	plus.custom_minimum_size = Vector2(_fs(38), _fs(44))
	plus.add_theme_font_size_override("font_size", _fs(18))
	row.add_child(plus)
	var current := value
	var update := func() -> void:
		value_label.text = _format_stepper(current, step)
	var set_value := func(v: float) -> void:
		current = clampf(v, minv, maxv)
		update.call()
		on_change.call(current)
	minus.pressed.connect(func() -> void:
		set_value.call(current - step)
	)
	plus.pressed.connect(func() -> void:
		set_value.call(current + step)
	)
	update.call()
	row.set_meta("set_value", set_value)
	row.set_meta("get_value", func() -> float: return current)
	return row


func _format_stepper(value: float, step: float) -> String:
	if step >= 1.0:
		return str(int(round(value)))
	return "%.2f" % value


func _segmented(options: Array, selected: String, callback: Callable,
		height: float = 44.0) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _gap(3))
	var group := ButtonGroup.new()
	var buttons: Array = []
	var ids: Array = []
	for opt in options:
		var b := Button.new()
		b.text = str(opt["name"])
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, _fs(height))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", _fs(24))
		b.add_theme_stylebox_override("normal", _panel_style(
				Color(0.04, 0.08, 0.065, 0.9), Color(0.34, 0.5, 0.4, 0.65), 1, 10))
		b.add_theme_stylebox_override("hover", _panel_style(
				Color(0.09, 0.16, 0.12, 0.98), MenuUI.FPV_GREEN, 1, 10))
		b.add_theme_stylebox_override("pressed", _panel_style(
				Color(0.68, 0.78, 0.58, 1.0), Color(0.75, 0.85, 0.65, 0.9), 1, 10))
		b.pressed.connect(callback.bind(str(opt["id"])))
		row.add_child(b)
		buttons.append(b)
		ids.append(str(opt["id"]))
		if str(opt["id"]) == selected:
			b.button_pressed = true
		b.toggled.connect(func(_on: bool) -> void: _sync_segmented_colors(row, buttons))
	row.set_meta("seg_buttons", buttons)
	row.set_meta("seg_ids", ids)
	_sync_segmented_colors(row, buttons)
	return row


func _set_segmented_selected(row: HBoxContainer, id: String) -> void:
	if row == null:
		return
	var buttons: Array = row.get_meta("seg_buttons", [])
	var ids: Array = row.get_meta("seg_ids", [])
	for i in range(buttons.size()):
		var b := buttons[i] as Button
		if b != null:
			b.button_pressed = i < ids.size() and str(ids[i]) == id
	_sync_segmented_colors(row, buttons)


func _sync_segmented_colors(row: HBoxContainer, buttons: Array) -> void:
	for b in buttons:
		var btn := b as Button
		if btn == null:
			continue
		var on := btn.button_pressed
		btn.add_theme_color_override("font_color", Color(0.06, 0.09, 0.07) if on else MenuUI.TEXT)
		btn.add_theme_color_override("font_hover_color", Color(0.06, 0.09, 0.07) if on else MenuUI.TEXT)
		btn.add_theme_color_override("font_pressed_color", Color(0.06, 0.09, 0.07) if on else MenuUI.TEXT)



# --------------------------------------------------------------- shell
func _build_background() -> void:
	var bg := TextureRect.new()
	bg.texture = BG_TEX
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_bg_blur = TextureRect.new()
	_bg_blur.texture = BG_BLUR_TEX
	_bg_blur.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg_blur.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg_blur.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg_blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_blur.visible = false
	add_child(_bg_blur)

	_screen_scrim = ColorRect.new()
	_screen_scrim.color = Color(0.015, 0.045, 0.035, 0.12)
	_screen_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_screen_scrim)


func _build_root() -> void:
	var s := _vsize()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var edges := MenuUI.mobile_edge_margins(s)
	var notch := MenuUI.mobile_notch_insets(s)
	margin.add_theme_constant_override("margin_left", int(edges.x))
	margin.add_theme_constant_override("margin_right", int(edges.z))
	# Vertical space is tighter on a landscape phone; keep a small top gap and
	# clear the home indicator at the bottom without squeezing the hero card.
	margin.add_theme_constant_override("margin_top", maxi(12, int(s.y * 0.02 + notch.y)))
	margin.add_theme_constant_override("margin_bottom", maxi(16, int(s.y * 0.03 + notch.w)))
	add_child(margin)

	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", _gap(10))
	margin.add_child(_root)

	var top := Control.new()
	top.custom_minimum_size.y = _fs(96)
	_root.add_child(top)

	# Large centred masthead, as in the reference.  The live chips sit in the
	# top-right corner without stealing the title's centre line.
	var brand := VBoxContainer.new()
	brand.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	brand.alignment = BoxContainer.ALIGNMENT_CENTER
	brand.add_theme_constant_override("separation", _gap(2))
	top.add_child(brand)
	var logo := _label("НЕБЕСНИЙ ГОРИЗОНТ", 48, MenuUI.TEXT)
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	brand.add_child(logo)
	var brand_sub := _label("БОЙОВИЙ FPV СИМУЛЯТОР  •  МОБІЛЬНИЙ ТЕРМІНАЛ", 15, MenuUI.MUTED)
	brand_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	brand.add_child(brand_sub)

	var chips := HBoxContainer.new()
	chips.alignment = BoxContainer.ALIGNMENT_END
	chips.add_theme_constant_override("separation", _gap(8))
	chips.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	chips.offset_left = -_fs(470)
	chips.offset_top = _fs(8)
	chips.offset_right = 0
	chips.offset_bottom = _fs(66)
	top.add_child(chips)
	_elrs_chip = _panel(Color(0.03, 0.07, 0.055, 0.82), Color(0.40, 0.62, 0.48, 0.65), 1, 10)
	_elrs_label = _label("ELRS: ПОШУК", 15, MenuUI.MUTED)
	_elrs_chip.add_child(_elrs_label)
	chips.add_child(_elrs_chip)
	_input_chip = _panel(Color(0.03, 0.07, 0.055, 0.82), Color(0.62, 0.76, 0.55, 0.65), 1, 10)
	_input_label = _label("ВХІД: СЕНСОР", 15, MenuUI.FPV_CYAN)
	_input_chip.add_child(_input_label)
	chips.add_child(_input_chip)

	_content = Control.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_child(_content)

	var bottom := HBoxContainer.new()
	_bottom_bar = bottom
	bottom.custom_minimum_size.y = _fs(52)
	bottom.add_theme_constant_override("separation", _gap(10))
	# On a short landscape phone the hero card reaches the bottom of the
	# content area; the decorative version/pilot strip is hidden so it cannot
	# print over the launch button.  The back button still needs this row.
	bottom.visible = _vsize().y >= 700.0
	_root.add_child(bottom)

	_back_btn = _button("◀", 62)
	_back_btn.custom_minimum_size = Vector2(_fs(82), _fs(62))
	_back_btn.add_theme_font_size_override("font_size", _fs(28))
	_back_btn.visible = false
	_back_btn.pressed.connect(_on_back)
	bottom.add_child(_back_btn)

	_bottom_mid = _label("НЕБЕСНИЙ ГОРИЗОНТ  •  %s" % _version(), 14, MenuUI.MUTED)
	_bottom_mid.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bottom_mid.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bottom_mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_bottom_mid)

	var player := HBoxContainer.new()
	_bottom_player_box = player
	player.add_theme_constant_override("separation", _gap(8))
	player.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_child(player)
	_bottom_player = _label("ГРАВЕЦЬ: %s" % _pilot_name(), 14, MenuUI.MUTED)
	player.add_child(_bottom_player)
	var flag := HBoxContainer.new()
	flag.add_theme_constant_override("separation", 0)
	flag.custom_minimum_size = Vector2(_fs(30), _fs(19))
	player.add_child(flag)
	var flag_blue := ColorRect.new()
	flag_blue.color = Color(0.20, 0.42, 0.78)
	flag_blue.custom_minimum_size = Vector2(0, _fs(10))
	flag_blue.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flag.add_child(flag_blue)
	var flag_yellow := ColorRect.new()
	flag_yellow.color = Color(0.95, 0.80, 0.28)
	flag_yellow.custom_minimum_size = Vector2(0, _fs(9))
	flag_yellow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flag.add_child(flag_yellow)


func _version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "1.15.0"))


func _pilot_name() -> String:
	var gs := get_node_or_null("/root/GameSettings")
	if gs == null:
		return "ПІЛОТ"
	var hud: Dictionary = gs.get("hud_config")
	return str(hud.get("mobile_pilot_name", "ПІЛОТ"))


func _make_screen(name: String) -> Control:
	var s := Control.new()
	s.name = "Screen_" + name
	s.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	s.visible = false
	_content.add_child(s)
	_screens[name] = s
	return s


func _show(name: String) -> void:
	if not _screens.has(name):
		return
	for key in _screens.keys():
		(_screens[key] as Control).visible = str(key) == name
	_current = name
	_bg_blur.visible = name != "main"
	_back_btn.visible = name != "main"
	if _bottom_bar != null:
		# Home uses the full height for the hero card; the version/pilot strip
		# is decorative and would print over the launch button.  Sub-screens
		# keep the row for the back button.
		_bottom_bar.visible = name != "main"
	if _bottom_mid != null:
		_bottom_mid.visible = false
	if _bottom_player_box != null:
		_bottom_player_box.visible = false
	_screen_scrim.color = Color(0.015, 0.045, 0.035, 0.10 if name == "main" else 0.18)
	_photo_mode = false
	if _photo_layer != null:
		_photo_layer.visible = false
	if _rate_help != null:
		_rate_help.visible = false
	_update_status()


func _on_back() -> void:
	if _current != "main":
		_show("main")


func _open_old_menu() -> void:
	get_tree().change_scene_to_file("res://GUI/MainMenu.tscn")


func _open_old_controls() -> void:
	get_tree().change_scene_to_file("res://GUI/ControlsScreen.tscn")


func _open_calibration() -> void:
	get_tree().change_scene_to_file("res://GUI/CalibrationScreen.tscn")


func _open_hangar() -> void:
	get_tree().change_scene_to_file("res://GUI/DroneSelectScreen.tscn")


func _open_help() -> void:
	get_tree().change_scene_to_file("res://GUI/HelpScreen.tscn")


func _open_quad_settings() -> void:
	get_tree().change_scene_to_file("res://GUI/QuadSettingsMenu.tscn")


func _open_options() -> void:
	get_tree().change_scene_to_file("res://GUI/OptionsMenu.tscn")


func _update_status() -> void:
	if _elrs_label == null:
		return
	var elrs := get_node_or_null("/root/ElrsWifiInput")
	var valid := elrs != null and bool(elrs.get("valid"))
	var status := str(elrs.get("status_text")) if elrs != null else ""
	if valid or status.find("ПОТІК") >= 0:
		_elrs_label.text = "ELRS: ПОТІК"
		_elrs_label.add_theme_color_override("font_color", MenuUI.FPV_GREEN)
	elif status.find("ЗНАЙДЕНО") >= 0 or status.find("ПІДКЛЮЧЕНО") >= 0:
		_elrs_label.text = "ELRS: МОДУЛЬ"
		_elrs_label.add_theme_color_override("font_color", MenuUI.FPV_AMBER)
	else:
		_elrs_label.text = "ELRS: НЕМАЄ"
		_elrs_label.add_theme_color_override("font_color", MenuUI.FPV_RED)
	var mobile := get_node_or_null("/root/MobileInput")
	var active_source := str(mobile.call("source")) if mobile != null else ""
	var touch_source := active_source == "touch"
	_input_label.text = "ВХІД: СЕНСОР" if touch_source else ("ВХІД: ПУЛЬТ" if active_source == "elrs" else "ВХІД: —")
	_input_label.add_theme_color_override("font_color", MenuUI.FPV_CYAN if touch_source else MenuUI.FPV_AMBER)
	if _source_status != null:
		var src := str(mobile.call("source_name")) if mobile != null else "Немає джерела"
		_source_status.text = "АКТИВНЕ ДЖЕРЕЛО: %s" % src
		_refresh_source_buttons()
	if _rate_status != null:
		_rate_status.text = "ПРОФІЛЬ: %s" % ("ПУЛЬТ" if _rate_tab == "radio" else "СЕНСОР")
	if _stream_label != null:
		_stream_label.text = "УВІМК." if _stream_mode() else "ВИМК."


func _stream_mode() -> bool:
	var gs := get_node_or_null("/root/GameSettings")
	if gs == null:
		return false
	var hud: Dictionary = gs.get("hud_config")
	return bool(hud.get("mobile_stream_mode", false))


# --------------------------------------------------------------- main
func _build_main() -> void:
	var screen := _make_screen("main")
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.add_theme_constant_override("separation", _gap(26))
	screen.add_child(h)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.34
	left.add_theme_constant_override("separation", _gap(10))
	h.add_child(left)

	left.add_child(_label("ОПЕРАТИВНИЙ ЦЕНТР", 15, MenuUI.FPV_AMBER))
	left.add_child(_spacer(_gap(6)))

	var nav := [
		["▶", "ГРАТИ", true, _build_play_action],
		["◎", "КЕРУВАННЯ", false, _open_old_controls],
		["◈", "РЕЙТИ", false, _open_quad_settings],
		["▣", "АНГАР", false, _open_hangar],
		["⚙", "НАЛАШТУВАННЯ", false, _open_options],
		["≡", "ДОВІДКА", false, _open_help],
	]
	for item in nav:
		var b := _nav_button(str(item[0]), str(item[1]), bool(item[2]))
		b.pressed.connect(item[3])
		left.add_child(b)

	left.add_child(_spacer(_gap(10)))
	var stream_card := _panel(Color(0.03, 0.07, 0.055, 0.86), Color(0.42, 0.58, 0.44, 0.45), 1, 14)
	left.add_child(stream_card)
	var stream_box := HBoxContainer.new()
	stream_box.add_theme_constant_override("separation", _gap(12))
	stream_card.add_child(stream_box)
	var stream_text := VBoxContainer.new()
	stream_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stream_box.add_child(stream_text)
	stream_text.add_child(_label("СТРІМ-РЕЖИМ", 17, MenuUI.TEXT))
	_stream_label = _label("ВИМК.", 12, MenuUI.MUTED)
	stream_text.add_child(_stream_label)
	_stream_toggle = ToggleSwitch.new(_stream_mode())
	_stream_toggle.custom_minimum_size = Vector2(_fs(80),
			_fs(30 if _vsize().y < 700.0 else 38))
	_stream_toggle.toggled.connect(_on_stream_toggled)
	stream_box.add_child(_stream_toggle)

	left.add_child(_spacer(0, Control.SIZE_EXPAND_FILL))
	var old_menu := _button("ПОВНЕ МЕНЮ  ↗", 44)
	old_menu.add_theme_font_size_override("font_size", _fs(18))
	old_menu.pressed.connect(_open_old_menu)
	left.add_child(old_menu)

	var hero := _build_hero()
	h.add_child(hero)


func _build_play_action() -> void:
	_show("play")


func _build_hero() -> Control:
	var card := _panel(Color(0.03, 0.07, 0.055, 0.9), Color(0.42, 0.58, 0.44, 0.5), 1, 22)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.add_child(holder)

	var img := _masked_texture(DRONE_TEX, _gap(20))
	img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(img)
	var scrim := _scrim(0.96)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(scrim)

	var overlay := MarginContainer.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		overlay.add_theme_constant_override("margin_%s" % side, _gap(28))
	holder.add_child(overlay)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_END
	v.add_theme_constant_override("separation", _gap(14))
	overlay.add_child(v)
	v.add_child(_label("СИСТЕМА ГОТОВА  •  ELRS WIFI", 14, MenuUI.FPV_AMBER))
	var hero_title := _label("ОБЕРИ МІСІЮ", 46, MenuUI.TEXT)
	v.add_child(hero_title)
	v.add_child(_label("4 мапи  •  6 місій  •  сенсорний пульт або Pocket", 16, MenuUI.MUTED))
	var start := _button("ПОЧАТИ ОПЕРАЦІЮ  ▶", 72, true)
	start.custom_minimum_size.x = _fs(330)
	start.pressed.connect(_build_play_action)
	v.add_child(start)

	# Small status card pinned to the top-right of the hero.
	var status := _panel(Color(0.02, 0.05, 0.04, 0.82), Color(0.42, 0.58, 0.44, 0.45), 1, 12)
	status.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	status.offset_left = -_fs(330)
	status.offset_right = -_fs(20)
	status.offset_top = _fs(20)
	status.offset_bottom = _fs(118)
	holder.add_child(status)
	var sb := VBoxContainer.new()
	sb.add_theme_constant_override("separation", _gap(2))
	status.add_child(sb)
	sb.add_child(_label("ПОЛЬОТНИЙ СТАТУС", 12, MenuUI.MUTED))
	sb.add_child(_label("ГОТОВО ДО ВИЛЬОТУ", 18, MenuUI.FPV_GREEN))
	sb.add_child(_label("HUD • ELRS • ТЕЛЕМЕТРІЯ", 12, MenuUI.MUTED))

	return card


func _spacer(height: float, flags: int = Control.SIZE_SHRINK_CENTER) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = _fs(height)
	c.size_flags_vertical = flags
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _on_stream_toggled(on: bool) -> void:
	var gs := get_node_or_null("/root/GameSettings")
	if gs != null:
		var hud: Dictionary = gs.get("hud_config")
		hud["mobile_stream_mode"] = on
		gs.call("save_hud_config")
	if _stream_label != null:
		_stream_label.text = "УВІМК." if on else "ВИМК."


# --------------------------------------------------------------- play
func _build_play() -> void:
	var screen := _make_screen("play")
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", _gap(12))
	screen.add_child(v)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", _gap(16))
	v.add_child(header)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	titles.add_child(_label("ОПЕРАЦІЇ", 40, MenuUI.TEXT))
	titles.add_child(_label("Вибір мапи, режиму та запуск вильоту", 16, MenuUI.MUTED))
	_play_caption = _label("", 15, MenuUI.FPV_AMBER)
	_play_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_play_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_play_caption)

	_map_group = ButtonGroup.new()
	var maps := HBoxContainer.new()
	maps.size_flags_vertical = Control.SIZE_EXPAND_FILL
	maps.add_theme_constant_override("separation", _gap(12))
	v.add_child(maps)
	for meta in MAP_META:
		maps.add_child(_map_card(meta))

	var bottom := VBoxContainer.new()
	bottom.add_theme_constant_override("separation", _gap(6))
	v.add_child(bottom)
	var modes_row := HBoxContainer.new()
	modes_row.add_theme_constant_override("separation", _gap(10))
	bottom.add_child(modes_row)
	_mode_row = _segmented(MODE_META, str(_selected_mode), _select_mode, 84)
	_mode_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modes_row.add_child(_mode_row)
	var launch := _button("ЗАПУСК  ▶", 96, true)
	launch.custom_minimum_size.x = _fs(330)
	launch.pressed.connect(_launch)
	modes_row.add_child(launch)

	_mission_row = HBoxContainer.new()
	_mission_row.add_theme_constant_override("separation", _gap(6))
	bottom.add_child(_mission_row)
	var mission_label := _label("МІСІЯ", 17, MenuUI.MUTED)
	mission_label.custom_minimum_size.x = _fs(84)
	mission_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_mission_row.add_child(mission_label)
	var missions := [
		"1 ПІХОТА", "2 ТАНКИ", "3 АВІАЦІЯ", "4 ШАХЕД", "5 МАГУРА", "6 СПЕЦОП",
	]
	_mission_group = ButtonGroup.new()
	for i in range(missions.size()):
		var mid := i + 1
		var b := _button(str(missions[i]), 62)
		b.toggle_mode = true
		b.button_group = _mission_group
		b.add_theme_font_size_override("font_size", _fs(19))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_select_mission.bind(mid))
		_mission_row.add_child(b)
		_mission_buttons[mid] = b
	_refresh_mission_row()
	_refresh_play_caption()


func _map_card(meta: Dictionary) -> Button:
	var id := str(meta["id"])
	var card := Button.new()
	card.toggle_mode = true
	card.button_group = _map_group
	card.focus_mode = Control.FOCUS_NONE
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(_fs(220), _fs(360))
	card.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	card.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	card.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	card.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	var img := _masked_texture(MAP_IMAGES.get(id, BG_TEX), _gap(16))
	img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The recon captures are intentionally dark aerial photos; lift them so the
	# map layout (roads, buildings, tree lines) reads at a glance on a phone.
	img.modulate = Color(1.45, 1.45, 1.45, 1.0)
	card.add_child(img)
	var scrim := _scrim(0.86)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.add_child(scrim)
	var grid := TextureRect.new()
	grid.texture = GRID_TEX
	grid.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	grid.stretch_mode = TextureRect.STRETCH_SCALE
	grid.modulate = Color(1.0, 1.0, 1.0, 0.42)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.add_child(grid)
	var recon := _label("RECON / %s" % id.to_upper(), 10, Color(0.72, 0.88, 0.76, 0.78))
	recon.set_anchors_preset(Control.PRESET_TOP_LEFT)
	recon.offset_left = _fs(14)
	recon.offset_top = _fs(12)
	card.add_child(recon)

	var border := Panel.new()
	border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	border.add_theme_stylebox_override("panel", _panel_style(
			Color(0, 0, 0, 0), Color(0.42, 0.58, 0.44, 0.55), 1, 16))
	card.add_child(border)

	var info_margin := MarginContainer.new()
	info_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		info_margin.add_theme_constant_override("margin_%s" % side, _gap(16))
	card.add_child(info_margin)
	var info := VBoxContainer.new()
	info.alignment = BoxContainer.ALIGNMENT_END
	info.add_theme_constant_override("separation", _gap(3))
	info_margin.add_child(info)
	info.add_child(_label(str(meta["diff"]), 13, Color(str(meta["col"]))))
	var name := _label(str(meta["name"]), 28, MenuUI.TEXT)
	info.add_child(name)
	info.add_child(_label(str(meta["tag"]), 12, MenuUI.MUTED))

	card.set_meta("border", border)
	card.set_meta("id", id)
	card.pressed.connect(_select_map.bind(id))
	_map_cards[id] = card
	if id == _selected_map:
		card.button_pressed = true
		_set_map_border(card, true)
	return card


func _set_map_border(card: Button, selected: bool) -> void:
	var border := card.get_meta("border") as Panel
	if border == null:
		return
	border.add_theme_stylebox_override("panel", _panel_style(
			Color(0.44, 0.30, 0.10, 0.16) if selected else Color(0, 0, 0, 0),
			MenuUI.FPV_AMBER if selected else Color(0.42, 0.58, 0.44, 0.55),
			3 if selected else 1, 16))


func _select_map(id: String) -> void:
	_selected_map = id
	for key in _map_cards.keys():
		var card: Button = _map_cards[key]
		card.button_pressed = str(key) == id
		_set_map_border(card, str(key) == id)
	_refresh_play_caption()


func _select_mode(id: String) -> void:
	_selected_mode = int(id)
	if _selected_mode == Global.PlayMode.COMBAT \
			and not Global.is_mission_unlocked(_selected_mission):
		_selected_mission = Global.campaign_unlocked_mission()
	_set_segmented_selected(_mode_row, str(_selected_mode))
	_refresh_mission_row()
	_refresh_play_caption()


func _select_mission(id: int) -> void:
	if not Global.is_mission_unlocked(id):
		return
	_selected_mission = id
	_refresh_mission_row()
	_refresh_play_caption()


func _refresh_mission_row() -> void:
	if _mission_row == null:
		return
	var combat := _selected_mode == Global.PlayMode.COMBAT
	_mission_row.visible = combat
	for mid in _mission_buttons.keys():
		var b: Button = _mission_buttons[mid]
		var unlocked := Global.is_mission_unlocked(int(mid))
		b.disabled = not unlocked
		b.modulate = Color(1, 1, 1, 1.0 if unlocked else 0.42)
		if int(mid) == _selected_mission:
			b.button_pressed = true


func _mode_name() -> String:
	for meta in MODE_META:
		if int(meta["id"]) == _selected_mode:
			return str(meta["name"])
	return "ТРЕНУВАННЯ"


func _map_name(id: String) -> String:
	for meta in MAP_META:
		if str(meta["id"]) == id:
			return str(meta["name"])
	return id.to_upper()


func _refresh_play_caption() -> void:
	if _play_caption == null:
		return
	var text := "%s  •  %s" % [_map_name(_selected_map), _mode_name()]
	if _selected_mode == Global.PlayMode.COMBAT:
		text += "  •  МІСІЯ %d" % _selected_mission
	_play_caption.text = text


func _launch() -> void:
	Global.play_mode = _selected_mode
	if _selected_mode == Global.PlayMode.COMBAT:
		Global.combat_mission = _selected_mission
		Global.special_mission = 0
	Global.menu_settings["selected_map"] = _selected_map
	Global.menu_settings["selected_mode"] = _selected_mode
	Global.menu_settings["selected_mission"] = _selected_mission
	Global.menu_settings["selected_special"] = 0
	Global.menu_settings["drone_preset"] = Global.drone_preset
	Global.save_menu_settings()
	var scenes := {
		"steppe": "res://sceneries/SteppeLevel.tscn",
		"village": "res://sceneries/VillageLevel.tscn",
		"industrial": "res://sceneries/IndustrialLevel.tscn",
		"wetlands": "res://sceneries/WetlandsLevel.tscn",
	}
	var path: String = scenes.get(_selected_map, "res://sceneries/VillageLevel.tscn")
	if _selected_mode == Global.PlayMode.TUTORIAL:
		path = "res://sceneries/VillageLevel.tscn"
	get_tree().change_scene_to_file(path)


# --------------------------------------------------------------- controls
func _build_controls() -> void:
	var screen := _make_screen("controls")
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", _gap(12))
	screen.add_child(v)
	v.add_child(_label("КЕРУВАННЯ", 40, MenuUI.TEXT))
	v.add_child(_label("Джерело входу, інверсія та калібрування", 16, MenuUI.MUTED))

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", _gap(16))
	v.add_child(columns)

	var source_card := _panel(Color(0.03, 0.07, 0.055, 0.9), Color(0.42, 0.58, 0.44, 0.55), 1, 18)
	source_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	source_card.size_flags_stretch_ratio = 1.1
	columns.add_child(source_card)
	var source_v := VBoxContainer.new()
	source_v.add_theme_constant_override("separation", _gap(10))
	source_card.add_child(source_v)
	source_v.add_child(_label("ДЖЕРЕЛО ВХОДУ", 18, MenuUI.FPV_AMBER))
	source_v.add_child(_label("Обери, чим керувати дроном зараз.", 14, MenuUI.MUTED))
	_source_status = _label("АКТИВНЕ ДЖЕРЕЛО: —", 16, MenuUI.FPV_GREEN)
	source_v.add_child(_source_status)
	source_v.add_child(_spacer(_gap(4)))

	var elrs_btn := _source_button("ELRS WiFi", "Пульт Radiomaster Pocket", "elrs", MenuUI.FPV_GREEN)
	source_v.add_child(elrs_btn)
	var touch_btn := _source_button("СЕНСОРНІ СТІКИ", "Екранні стіки телефона", "touch", MenuUI.FPV_CYAN)
	source_v.add_child(touch_btn)
	_stick_preview = StickPreview.new()
	_stick_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	source_v.add_child(_stick_preview)
	var hint := _label("ELRS з’являється тут лише тоді, коли в HUD є «ELRS: ПОТІК».", 13, MenuUI.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	source_v.add_child(hint)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", _gap(12))
	columns.add_child(right)

	var inv_card := _panel(Color(0.03, 0.07, 0.055, 0.9), Color(0.42, 0.58, 0.44, 0.55), 1, 18)
	right.add_child(inv_card)
	var inv := VBoxContainer.new()
	inv.add_theme_constant_override("separation", _gap(8))
	inv_card.add_child(inv)
	inv.add_child(_label("ІНВЕРСІЯ КРЕНУ", 18, MenuUI.FPV_AMBER))
	inv.add_child(_label("Якщо дрон валиться не в той бік — перемкни потрібний пункт.", 14, MenuUI.MUTED))
	var elrs_row := _toggle_row("ELRS (Pocket)", _elrs_invert(), _on_invert_elrs)
	_invert_elrs_toggle = elrs_row.get_meta("toggle")
	inv.add_child(elrs_row)
	var touch_row := _toggle_row("Сенсорні стіки", _touch_invert(), _on_invert_touch)
	_invert_touch_toggle = touch_row.get_meta("toggle")
	inv.add_child(touch_row)
	inv.add_child(_separator())
	var stream_row := _toggle_row("Стрім-режим: стіки в HUD", _stream_mode(), _on_stream_toggled)
	inv.add_child(stream_row)
	var stream_hint := _label("Глядачі бачать рух стіків під час стріму.", 12, MenuUI.MUTED)
	stream_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inv.add_child(stream_hint)

	var cal_card := _panel(Color(0.03, 0.07, 0.055, 0.9), Color(0.42, 0.58, 0.44, 0.55), 1, 18)
	right.add_child(cal_card)
	var cal := VBoxContainer.new()
	cal.add_theme_constant_override("separation", _gap(8))
	cal_card.add_child(cal)
	cal.add_child(_label("КАЛІБРУВАННЯ ТА ПРИВ’ЯЗКИ", 18, MenuUI.FPV_AMBER))
	cal.add_child(_label("Повний екран КЕРУВАННЯ — як на ПК: сітка осей, прив’язки, 3D-пульт.", 14, MenuUI.MUTED))
	var full := _button("ПОВНИЙ ЕКРАН КЕРУВАННЯ  ↗", 60)
	full.add_theme_font_size_override("font_size", _fs(20))
	full.pressed.connect(_open_old_controls)
	cal.add_child(full)
	var calib := _button("КАЛІБРУВАННЯ СТІКІВ  ▶", 60, true)
	calib.add_theme_font_size_override("font_size", _fs(20))
	calib.pressed.connect(_open_calibration)
	cal.add_child(calib)

	right.add_child(_spacer(0, Control.SIZE_EXPAND_FILL))
	var note := _label("Сенсорні стіки працюють завжди. Pocket з’являється як окреме джерело після Wi-Fi підключення.", 13, MenuUI.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(note)
	_refresh_source_buttons()


func _source_button(title: String, desc: String, source: String, col: Color) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = _fs(92)
	b.add_theme_stylebox_override("normal", _panel_style(
			Color(0.035, 0.075, 0.06, 0.92), Color(0.30, 0.44, 0.36, 0.6), 1, 14))
	b.add_theme_stylebox_override("hover", _panel_style(
			Color(0.06, 0.12, 0.09, 0.96), col, 1, 14))
	b.add_theme_stylebox_override("pressed", _panel_style(
			Color(0.08, 0.15, 0.11, 0.98), col, 2, 14))
	b.add_theme_stylebox_override("disabled", _panel_style(
			Color(0.02, 0.04, 0.033, 0.78), Color(0.22, 0.30, 0.25, 0.5), 1, 14))
	b.add_theme_color_override("font_disabled_color", Color(0.52, 0.60, 0.54, 0.8))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_%s" % side, _gap(12))
	b.add_child(m)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", _gap(1))
	m.add_child(v)
	var t := _label(title, 22, MenuUI.TEXT)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	var d := _label(desc, 13, MenuUI.MUTED)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(d)
	b.pressed.connect(_on_source_pressed.bind(source))
	b.set_meta("source", source)
	_source_buttons[source] = b
	return b


func _on_source_pressed(source: String) -> void:
	var mobile := get_node_or_null("/root/MobileInput")
	if mobile != null:
		mobile.call("set_source", source)
	_refresh_source_buttons()
	_update_status()


func _refresh_source_buttons() -> void:
	var mobile := get_node_or_null("/root/MobileInput")
	var active := str(mobile.call("source")) if mobile != null else ""
	var elrs := get_node_or_null("/root/ElrsWifiInput")
	var elrs_ok := elrs != null and bool(elrs.get("valid"))
	for key in _source_buttons.keys():
		var b: Button = _source_buttons[key]
		b.button_pressed = str(key) == active
		b.disabled = str(key) == "elrs" and not elrs_ok
		b.modulate = Color(1, 1, 1, 0.45 if b.disabled else 1.0)


func _source_is_active(source: String) -> bool:
	var mobile := get_node_or_null("/root/MobileInput")
	return mobile != null and str(mobile.call("source")) == source


func _elrs_invert() -> bool:
	var elrs := get_node_or_null("/root/ElrsWifiInput")
	return elrs != null and bool(elrs.get("invert_roll"))


func _touch_invert() -> bool:
	var pad := get_node_or_null("/root/TouchControls")
	return pad != null and bool(pad.get("invert_roll"))


func _on_invert_elrs(on: bool) -> void:
	var elrs := get_node_or_null("/root/ElrsWifiInput")
	if elrs != null:
		elrs.set("invert_roll", on)
		elrs.call("save_settings")


func _on_invert_touch(on: bool) -> void:
	var pad := get_node_or_null("/root/TouchControls")
	if pad != null:
		pad.set("invert_roll", on)
	var gs := get_node_or_null("/root/GameSettings")
	if gs != null:
		var hud: Dictionary = gs.get("hud_config")
		hud["touch_invert_roll"] = on
		gs.call("save_hud_config")


func _toggle_row(text: String, initial: bool, callback: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _gap(10))
	row.custom_minimum_size.y = _fs(58)
	var label := _label(text, 18, MenuUI.TEXT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var toggle := ToggleSwitch.new(initial)
	toggle.custom_minimum_size = Vector2(_fs(88), _fs(42))
	toggle.toggled.connect(callback)
	row.add_child(toggle)
	row.set_meta("toggle", toggle)
	return row


# --------------------------------------------------------------- rates
func _load_profiles() -> void:
	var gs := get_node_or_null("/root/GameSettings")
	var stored := {}
	if gs != null:
		var hud: Dictionary = gs.get("hud_config")
		stored = hud.get("mobile_rate_profiles", {})
		if not (stored is Dictionary):
			stored = {}
	_rate_profiles = stored.duplicate(true)
	if not _rate_profiles.has("radio"):
		_rate_profiles["radio"] = _default_rate_profile()
	if not _rate_profiles.has("touch"):
		_rate_profiles["touch"] = _default_rate_profile()


func _default_rate_profile() -> Dictionary:
	var q := get_node_or_null("/root/QuadSettings")
	var rate := 667
	var expo := 0.2
	var limit := 4.0
	if q != null:
		rate = int(q.get("rate_roll"))
		expo = float(q.get("expo_roll"))
		limit = float(q.get("level_rate_limit"))
	return {
		"rate_roll": rate, "rate_pitch": rate, "rate_yaw": rate,
		"expo_roll": expo, "expo_pitch": expo, "expo_yaw": expo,
		"limit": limit,
	}


func _build_rates() -> void:
	var screen := _make_screen("rates")
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", _gap(10))
	screen.add_child(v)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", _gap(12))
	v.add_child(header)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	titles.add_child(_label("РЕЙТИ", 40, MenuUI.TEXT))
	titles.add_child(_label("Пресети та точне налаштування швидкості обертання", 16, MenuUI.MUTED))
	var help := _button("?", 44)
	help.custom_minimum_size = Vector2(_fs(52), _fs(44))
	help.add_theme_font_size_override("font_size", _fs(22))
	help.pressed.connect(show_rates_help)
	header.add_child(help)
	_rate_status = _label("", 14, MenuUI.FPV_AMBER)
	_rate_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_rate_status)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", _gap(10))
	v.add_child(top_row)
	_rates_tabs_row = _segmented([
		{"id": "radio", "name": "ПУЛЬТ"},
		{"id": "touch", "name": "СЕНСОР"},
	], _rate_tab, _select_rate_tab, 52)
	_rates_tabs_row.custom_minimum_size.x = _fs(360)
	top_row.add_child(_rates_tabs_row)
	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", _gap(6))
	presets.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(presets)
	for entry in [
		{"id": "beginner", "name": "ПОЧАТКІВЕЦЬ"},
		{"id": "freestyle", "name": "ФРИСТАЙЛ"},
		{"id": "race", "name": "ГОНКА"},
	]:
		var b := _button(str(entry["name"]), 52)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", _fs(17))
		b.pressed.connect(_apply_rate_preset.bind(str(entry["id"])))
		presets.add_child(b)

	var table := _panel(Color(0.02, 0.05, 0.04, 0.9), Color(0.42, 0.58, 0.44, 0.55), 1, 18)
	table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(table)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", _gap(6))
	table.add_child(tv)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", _gap(6))
	tv.add_child(head)
	var axis_head := _label("ВІСЬ", 14, MenuUI.MUTED)
	axis_head.custom_minimum_size.x = _fs(170)
	head.add_child(axis_head)
	for title in ["МАКС. РЕЙТ", "EXPO", "ОБМЕЖ."]:
		var l := _label(title, 14, MenuUI.MUTED)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(l)

	_rate_buttons.clear()
	for axis in RATE_AXES:
		var key := str(axis["key"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", _gap(6))
		row.custom_minimum_size.y = _fs(78)
		tv.add_child(row)
		var name_panel := _panel(axis["col"] as Color, (axis["col"] as Color).lightened(0.2), 1, 10)
		name_panel.custom_minimum_size.x = _fs(170)
		var name_label := _label(str(axis["name"]), 22, Color(0.06, 0.08, 0.06))
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_panel.add_child(name_label)
		row.add_child(name_panel)
		var profile := _profile(_rate_tab)
		var fields := {
			"rate": ["rate_" + key, 90.0, 1800.0, 10.0, 180.0],
			"expo": ["expo_" + key, 0.0, 1.0, 0.05, 160.0],
			"limit": ["limit", 1.0, 12.0, 1.0, 150.0],
		}
		var axis_rows := {}
		for field in fields.keys():
			var spec: Array = fields[field]
			var value := float(profile.get(spec[0], 0.0))
			var step := _stepper(value, float(spec[1]), float(spec[2]), float(spec[3]),
					_on_rate_value_changed.bind(key, field), float(spec[4]))
			step.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(step)
			axis_rows[field] = step
		_rate_buttons[key] = axis_rows

	_rate_curve = RateCurve.new()
	_rate_curve.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tv.add_child(_rate_curve)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", _gap(8))
	tv.add_child(footer)
	var note := _label("Зміни застосовуються одразу та зберігаються у Quad.cfg.", 13, MenuUI.MUTED)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(note)
	var reset := _button("СКИНУТИ", 42)
	reset.custom_minimum_size.x = _fs(180)
	reset.add_theme_font_size_override("font_size", _fs(16))
	reset.pressed.connect(_apply_rate_preset.bind("beginner"))
	footer.add_child(reset)

	_apply_rate_profile(_rate_tab)
	_refresh_rate_status()


func _profile(tab: String) -> Dictionary:
	if not _rate_profiles.has(tab):
		_rate_profiles[tab] = _default_rate_profile()
	return _rate_profiles[tab]


func _on_rate_value_changed(value: float, axis: String, field: String) -> void:
	var profile := _profile(_rate_tab)
	match field:
		"rate":
			profile["rate_" + axis] = int(round(value))
		"expo":
			profile["expo_" + axis] = float(value)
		"limit":
			profile["limit"] = float(value)
	_save_rate_profiles()
	_apply_rate_profile(_rate_tab)


func _select_rate_tab(tab: String) -> void:
	_rate_tab = tab
	_set_segmented_selected(_rates_tabs_row, tab)
	_apply_rate_profile(tab)
	_refresh_rate_widgets()
	_refresh_rate_status()


func _apply_rate_preset(id: String) -> void:
	var rate := 667
	var expo := 0.2
	var limit := 4.0
	match id:
		"beginner":
			rate = 450
			expo = 0.35
			limit = 3.0
		"race":
			rate = 900
			expo = 0.12
			limit = 5.0
		_:
			rate = 667
			expo = 0.2
			limit = 4.0
	var profile := _profile(_rate_tab)
	for axis in ["roll", "pitch", "yaw"]:
		profile["rate_" + axis] = rate
		profile["expo_" + axis] = expo
	profile["limit"] = limit
	_save_rate_profiles()
	_apply_rate_profile(_rate_tab)
	_refresh_rate_widgets()
	_refresh_rate_status()


func _apply_rate_profile(tab: String) -> void:
	var profile := _profile(tab)
	var q := get_node_or_null("/root/QuadSettings")
	if q == null:
		return
	q.set("rate_roll", int(profile.get("rate_roll", 667)))
	q.set("rate_pitch", int(profile.get("rate_pitch", 667)))
	q.set("rate_yaw", int(profile.get("rate_yaw", 667)))
	q.set("expo_roll", float(profile.get("expo_roll", 0.2)))
	q.set("expo_pitch", float(profile.get("expo_pitch", 0.2)))
	q.set("expo_yaw", float(profile.get("expo_yaw", 0.2)))
	q.set("level_rate_limit", float(profile.get("limit", 4.0)))
	q.set("custom_rates", true)
	q.call("save_quad_settings")
	if _rate_curve != null:
		_rate_curve.set_profile(profile)


func _refresh_rate_widgets() -> void:
	var profile := _profile(_rate_tab)
	for axis in RATE_AXES:
		var key := str(axis["key"])
		var rows: Dictionary = _rate_buttons.get(key, {})
		for field in rows.keys():
			var row: HBoxContainer = rows[field]
			var setter: Callable = row.get_meta("set_value")
			match field:
				"rate":
					setter.call(float(profile.get("rate_" + key, 667)))
				"expo":
					setter.call(float(profile.get("expo_" + key, 0.2)))
				"limit":
					setter.call(float(profile.get("limit", 4.0)))


func _save_rate_profiles() -> void:
	var gs := get_node_or_null("/root/GameSettings")
	if gs == null:
		return
	var hud: Dictionary = gs.get("hud_config")
	hud["mobile_rate_profiles"] = _rate_profiles.duplicate(true)
	gs.call("save_hud_config")


func _refresh_rate_status() -> void:
	if _rate_status != null:
		_rate_status.text = "ПРОФІЛЬ: %s" % ("ПУЛЬТ" if _rate_tab == "radio" else "СЕНСОР")


func show_rates_help() -> void:
	if _rate_help == null:
		return
	_rate_help.visible = true


func _build_rate_help() -> void:
	_rate_help = Control.new()
	_rate_help.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rate_help.visible = false
	add_child(_rate_help)
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.025, 0.02, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rate_help.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rate_help.add_child(center)
	var panel := _panel(Color(0.025, 0.06, 0.048, 0.98), MenuUI.FPV_AMBER, 2, 18)
	panel.custom_minimum_size = Vector2(_fs(780), _fs(430))
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", _gap(10))
	panel.add_child(v)
	var title_row := HBoxContainer.new()
	v.add_child(title_row)
	var title := _label("ПРОФІЛІ РЕЙТІВ", 30, MenuUI.TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var close := _button("✕", 36)
	close.custom_minimum_size = Vector2(_fs(44), _fs(36))
	close.pressed.connect(func() -> void: _rate_help.visible = false)
	title_row.add_child(close)
	v.add_child(_label("ПУЛЬТ І СЕНСОР — ОКРЕМІ ПРОФІЛІ", 15, MenuUI.FPV_AMBER))
	var text := _label(
			"Налаштуй рейти під свій стиль. Пульт і сенсорні стіки зберігаються окремо.\n"
			+ "Макс. рейт — швидкість обертання, Expo — пом’якшення центру, Обмеж. — запобіжник для LEVEL-режиму.\n"
			+ "Зміни застосовуються одразу й зберігаються у Quad.cfg.",
			16, MenuUI.TEXT)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(text)
	v.add_child(_spacer(0, Control.SIZE_EXPAND_FILL))
	var ok := _button("ЗРОЗУМІЛО", 50, true)
	ok.pressed.connect(func() -> void: _rate_help.visible = false)
	v.add_child(ok)


# --------------------------------------------------------------- drone
func _build_drone() -> void:
	_load_drone_state()
	var screen := _make_screen("drone")
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", _gap(10))
	screen.add_child(v)
	v.add_child(_label("ДРОН", 40, MenuUI.TEXT))
	v.add_child(_label("Корпус, мотори, пропелери, батарея та кріплення", 16, MenuUI.MUTED))

	_drone_tabs_row = _segmented(
			[{"id": "frame", "name": "КОРПУС"}, {"id": "motors", "name": "МОТОРИ"},
			{"id": "props", "name": "ПРОПЕЛЕРИ"}, {"id": "battery", "name": "БАТАРЕЯ"},
			{"id": "straps", "name": "РЕМЕНІ"}],
			_drone_tab, _select_drone_tab, 52)
	v.add_child(_drone_tabs_row)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", _gap(12))
	v.add_child(columns)

	var color_card := _panel(Color(0.03, 0.07, 0.055, 0.9), Color(0.42, 0.58, 0.44, 0.55), 1, 18)
	color_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	color_card.size_flags_stretch_ratio = 0.7
	columns.add_child(color_card)
	var color_v := VBoxContainer.new()
	color_v.add_theme_constant_override("separation", _gap(8))
	color_card.add_child(color_v)
	color_v.add_child(_label("КОЛІР", 18, MenuUI.FPV_AMBER))
	color_v.add_child(_label("Акцент корпусу", 13, MenuUI.MUTED))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", _gap(6))
	grid.add_theme_constant_override("v_separation", _gap(6))
	color_v.add_child(grid)
	for sw in COLOR_SWATCHES:
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(_fs(94), _fs(64))
		b.add_theme_stylebox_override("normal", _panel_style(
				Color(sw["col"]) as Color, Color(0.3, 0.42, 0.34, 0.7), 1, 10))
		b.add_theme_stylebox_override("hover", _panel_style(
				(sw["col"] as Color).lightened(0.12), MenuUI.FPV_AMBER, 2, 10))
		b.add_theme_stylebox_override("pressed", _panel_style(
				(sw["col"] as Color).lightened(0.08), MenuUI.FPV_AMBER, 2, 10))
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.pressed.connect(_select_color.bind(str(sw["name"])))
		b.set_meta("color_name", str(sw["name"]))
		grid.add_child(b)
		_color_buttons[str(sw["name"])] = b
		if str(sw["name"]) == _drone_selected_color:
			b.button_pressed = true
	_drone_color_label = _label("АКЦЕНТ: %s" % _drone_selected_color, 14, MenuUI.TEXT)
	color_v.add_child(_drone_color_label)
	color_v.add_child(_spacer(0, Control.SIZE_EXPAND_FILL))
	var photo := _button("ФОТОРЕЖИМ  ◎", 52)
	photo.add_theme_font_size_override("font_size", _fs(16))
	photo.pressed.connect(_enter_photo_mode)
	color_v.add_child(photo)

	var drone_card := _panel(Color(0.03, 0.07, 0.055, 0.9), Color(0.42, 0.58, 0.44, 0.55), 1, 20)
	drone_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(drone_card)
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	drone_card.add_child(holder)
	_drone_image = _masked_texture(DRONE_TEX, _gap(18))
	_drone_image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(_drone_image)
	var scrim := _scrim(0.92)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(scrim)
	var overlay := VBoxContainer.new()
	overlay.alignment = BoxContainer.ALIGNMENT_END
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.offset_left = _fs(24)
	overlay.offset_right = -_fs(24)
	overlay.offset_top = _fs(24)
	overlay.offset_bottom = -_fs(20)
	overlay.add_theme_constant_override("separation", _gap(2))
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(overlay)
	var tag := _label("X5 VARAN  •  FPV", 13, MenuUI.FPV_AMBER)
	overlay.add_child(tag)
	var name := _label("БОЙОВИЙ ДРОН", 30, MenuUI.TEXT)
	overlay.add_child(name)
	_drone_caption = _label("", 15, MenuUI.MUTED)
	overlay.add_child(_drone_caption)

	var parts_card := _panel(Color(0.03, 0.07, 0.055, 0.9), Color(0.42, 0.58, 0.44, 0.55), 1, 18)
	parts_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parts_card.size_flags_stretch_ratio = 0.8
	columns.add_child(parts_card)
	var parts_v := VBoxContainer.new()
	parts_v.add_theme_constant_override("separation", _gap(6))
	parts_card.add_child(parts_v)
	parts_v.add_child(_label("КОМПЛЕКТУЮЧІ", 18, MenuUI.FPV_AMBER))
	parts_v.add_child(_label("Обери варіант для активної вкладки", 12, MenuUI.MUTED))
	_drone_parts_box = VBoxContainer.new()
	_drone_parts_box.add_theme_constant_override("separation", _gap(4))
	parts_v.add_child(_drone_parts_box)
	parts_v.add_child(_spacer(0, Control.SIZE_EXPAND_FILL))
	var change := _button("ЗМІНИТИ ДРОН  ↗", 52)
	change.add_theme_font_size_override("font_size", _fs(16))
	change.pressed.connect(_open_hangar)
	parts_v.add_child(change)

	_populate_drone_parts()


func _load_drone_state() -> void:
	var gs := get_node_or_null("/root/GameSettings")
	if gs == null:
		return
	var hud: Dictionary = gs.get("hud_config")
	var parts = hud.get("mobile_drone_parts", {})
	if parts is Dictionary:
		_drone_parts = (parts as Dictionary).duplicate(true)
	else:
		_drone_parts = {}
	var tint := str(hud.get("mobile_drone_tint", "ХАКІ"))
	if not tint.is_empty():
		_drone_selected_color = tint


func _save_drone_state() -> void:
	var gs := get_node_or_null("/root/GameSettings")
	if gs == null:
		return
	var hud: Dictionary = gs.get("hud_config")
	hud["mobile_drone_parts"] = _drone_parts.duplicate(true)
	hud["mobile_drone_tint"] = _drone_selected_color
	gs.call("save_hud_config")


func _selected_part(tab: String) -> String:
	var list: Array = DRONE_PARTS.get(tab, [])
	var value := str(_drone_parts.get(tab, list[0] if not list.is_empty() else ""))
	return value


func _select_drone_tab(tab: String) -> void:
	_drone_tab = tab
	_set_segmented_selected(_drone_tabs_row, tab)
	_populate_drone_parts()


func _populate_drone_parts() -> void:
	if _drone_parts_box == null:
		return
	for child in _drone_parts_box.get_children():
		child.queue_free()
	var list: Array = DRONE_PARTS.get(_drone_tab, [])
	var selected := _selected_part(_drone_tab)
	for part in list:
		var b := _button(str(part), 56)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", _fs(16))
		b.toggle_mode = true
		b.button_pressed = str(part) == selected
		b.pressed.connect(_select_part.bind(_drone_tab, str(part)))
		_drone_parts_box.add_child(b)
	if _drone_caption != null:
		_drone_caption.text = selected


func _select_part(tab: String, part: String) -> void:
	_drone_parts[tab] = part
	_save_drone_state()
	_populate_drone_parts()


func _select_color(name: String) -> void:
	_drone_selected_color = name
	_save_drone_state()
	for key in _color_buttons.keys():
		var b: Button = _color_buttons[key]
		b.button_pressed = str(key) == name
	if _drone_color_label != null:
		_drone_color_label.text = "АКЦЕНТ: %s" % name


func _build_photo_layer() -> void:
	_photo_layer = Control.new()
	_photo_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_photo_layer.visible = false
	_photo_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_photo_layer)
	var bg := ColorRect.new()
	bg.color = Color(0.005, 0.015, 0.012, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_photo_layer.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_photo_layer.add_child(center)
	var img := _masked_texture(DRONE_TEX, _gap(20))
	img.custom_minimum_size = Vector2(_fs(1280), _fs(800))
	center.add_child(img)
	var top := _label("PHOTO MODE", 18, MenuUI.FPV_AMBER)
	top.set_anchors_preset(Control.PRESET_TOP_LEFT)
	top.offset_left = _fs(28)
	top.offset_top = _fs(24)
	_photo_layer.add_child(top)
	var close := _button("ЗАКРИТИ  ✕", 44)
	close.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	close.offset_left = -_fs(180)
	close.offset_right = -_fs(28)
	close.offset_top = _fs(20)
	close.pressed.connect(_exit_photo_mode)
	_photo_layer.add_child(close)


func _enter_photo_mode() -> void:
	_show("drone")
	_photo_mode = true
	if _photo_layer != null:
		_photo_layer.visible = true


func _exit_photo_mode() -> void:
	_photo_mode = false
	if _photo_layer != null:
		_photo_layer.visible = false


func show_drone_photo() -> void:
	_show("drone")
	_enter_photo_mode()


# --------------------------------------------------------------- settings
func _build_settings() -> void:
	var screen := _make_screen("settings")
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", _gap(10))
	screen.add_child(v)
	v.add_child(_label("НАЛАШТУВАННЯ", 40, MenuUI.TEXT))
	v.add_child(_label("Профіль пілота, графіка, звук і помічники", 16, MenuUI.MUTED))

	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", _gap(10))
	v.add_child(row)
	var left_pad := Control.new()
	left_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_pad.size_flags_stretch_ratio = 0.22
	row.add_child(left_pad)
	var card := _panel(Color(0.025, 0.06, 0.048, 0.92), Color(0.42, 0.58, 0.44, 0.55), 1, 20)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(card)
	var right_pad := Control.new()
	right_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_pad.size_flags_stretch_ratio = 0.22
	row.add_child(right_pad)

	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", _gap(10))
	card.add_child(cv)

	var profile := HBoxContainer.new()
	profile.add_theme_constant_override("separation", _gap(12))
	cv.add_child(profile)
	var plabel := _label("ПОЗИВНИЙ", 18, MenuUI.TEXT)
	plabel.custom_minimum_size.x = _fs(250)
	plabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	profile.add_child(plabel)
	_settings_name = LineEdit.new()
	_settings_name.text = _pilot_name()
	_settings_name.max_length = 18
	_settings_name.custom_minimum_size = Vector2(0, _fs(50))
	_settings_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings_name.add_theme_font_size_override("font_size", _fs(19))
	_settings_name.add_theme_stylebox_override("normal", _panel_style(
			Color(0.08, 0.14, 0.11, 0.9), Color(0.35, 0.5, 0.4, 0.7), 1, 10))
	_settings_name.add_theme_stylebox_override("focus", _panel_style(
			Color(0.10, 0.18, 0.14, 0.95), MenuUI.FPV_AMBER, 2, 10))
	_settings_name.text_changed.connect(_on_name_changed)
	profile.add_child(_settings_name)
	var flag := HBoxContainer.new()
	flag.add_theme_constant_override("separation", 0)
	flag.custom_minimum_size = Vector2(_fs(44), _fs(28))
	var fb := ColorRect.new(); fb.color = Color(0.20, 0.42, 0.78); fb.custom_minimum_size = Vector2(0, _fs(14)); fb.size_flags_horizontal = Control.SIZE_EXPAND_FILL; flag.add_child(fb)
	var fy := ColorRect.new(); fy.color = Color(0.95, 0.80, 0.28); fy.custom_minimum_size = Vector2(0, _fs(14)); fy.size_flags_horizontal = Control.SIZE_EXPAND_FILL; flag.add_child(fy)
	profile.add_child(flag)

	cv.add_child(_separator())

	var scale_default := 80
	var gs := get_node_or_null("/root/GameSettings")
	var hud: Dictionary = gs.get("hud_config") if gs != null else {}
	scale_default = int(hud.get("mobile_render_scale", 80))
	_settings_scale_value = _label("%d%%" % scale_default, 17, MenuUI.FPV_AMBER)
	var scale_slider := _slider(scale_default, 50, 100, 5, _on_scale_changed)
	cv.add_child(_setting_row("МАСШТАБ РЕНДЕРУ", scale_slider, _settings_scale_value))

	var fps := 120
	if has_node("/root/Graphics"):
		fps = int(get_node("/root/Graphics").get("graphics_settings").get("fps_limit", 120))
	_settings_fps_value = _label("%d FPS" % fps, 17, MenuUI.FPV_AMBER)
	var fps_slider := _slider(fps, 30, 120, 30, _on_fps_changed)
	cv.add_child(_setting_row("ЛІМІТ FPS", fps_slider, _settings_fps_value))

	var vol := 100
	if has_node("/root/Audio"):
		var audio_settings: Dictionary = get_node("/root/Audio").get("audio_settings")
		vol = int(round(float(audio_settings.get("master_volume", 1.0)) * 100.0))
	_settings_audio_value = _label("%d%%" % vol, 17, MenuUI.FPV_AMBER)
	var audio_slider := _slider(vol, 0, 100, 1, _on_audio_changed)
	cv.add_child(_setting_row("ГУЧНІСТЬ ЗВУКУ", audio_slider, _settings_audio_value))

	cv.add_child(_separator())
	var music_row := _toggle_row("МУЗИКА В МЕНЮ", _music_on(), _on_music_toggled)
	_settings_music_toggle = music_row.get_meta("toggle")
	cv.add_child(music_row)
	var ghost_row := _toggle_row("GHOST DRONE (СЛІД)", bool(hud.get("mobile_ghost", false)), _on_ghost_toggled)
	_settings_ghost_toggle = ghost_row.get_meta("toggle")
	cv.add_child(ghost_row)
	var racing_row := _toggle_row("RACING LINE (ТРАСА)", bool(hud.get("mobile_racing_line", false)), _on_racing_toggled)
	_settings_racing_toggle = racing_row.get_meta("toggle")
	cv.add_child(racing_row)
	var units_row := _toggle_row("ОДИНИЦІ: КМ/ГОД", str(hud.get("mobile_distance_units", "km")) == "km", _on_units_toggled)
	_settings_units_toggle = units_row.get_meta("toggle")
	cv.add_child(units_row)
	var stream_row := _toggle_row("СТРІМ-РЕЖИМ (СТІКИ В HUD)", _stream_mode(), _on_stream_toggled)
	cv.add_child(stream_row)

	cv.add_child(_separator())
	var old := _button("ПОВНЕ МЕНЮ  ↗", 54)
	old.add_theme_font_size_override("font_size", _fs(18))
	old.pressed.connect(_open_old_menu)
	cv.add_child(old)
	cv.add_child(_label("Версія %s  •  мобільний інтерфейс (прототип)" % _version(), 12, MenuUI.MUTED))


func _separator() -> HSeparator:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", _gap(2))
	return sep


func _setting_row(text: String, control: Control, value_label: Label) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _gap(12))
	row.custom_minimum_size.y = _fs(58)
	var label := _label(text, 18, MenuUI.TEXT)
	label.custom_minimum_size.x = _fs(250)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	value_label.custom_minimum_size.x = _fs(86)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(value_label)
	return row


func _save_hud_key(key: String, value: Variant) -> void:
	var gs := get_node_or_null("/root/GameSettings")
	if gs == null:
		return
	var hud: Dictionary = gs.get("hud_config")
	hud[key] = value
	gs.call("save_hud_config")


func _on_name_changed(text: String) -> void:
	var clean := text.strip_edges()
	if clean.length() > 18:
		clean = clean.substr(0, 18)
	_save_hud_key("mobile_pilot_name", clean)
	if _bottom_player != null:
		_bottom_player.text = "ГРАВЕЦЬ: %s" % (clean if not clean.is_empty() else "ПІЛОТ")


func _on_scale_changed(value: float) -> void:
	if _settings_scale_value != null:
		_settings_scale_value.text = "%d%%" % int(value)
	_save_hud_key("mobile_render_scale", int(value))
	get_viewport().scaling_3d_scale = clampf(value / 100.0, 0.5, 1.0)


func _on_fps_changed(value: float) -> void:
	if _settings_fps_value != null:
		_settings_fps_value.text = "%d FPS" % int(value)
	if has_node("/root/Graphics"):
		var graphics := get_node("/root/Graphics")
		var gs: Dictionary = graphics.get("graphics_settings")
		gs["fps_limit"] = int(value)
		graphics.call("update_fps_limit")
		graphics.call("save_graphics_settings")
	_save_hud_key("fps", int(value))


func _on_audio_changed(value: float) -> void:
	if _settings_audio_value != null:
		_settings_audio_value.text = "%d%%" % int(value)
	if has_node("/root/Audio"):
		var audio := get_node("/root/Audio")
		var settings: Dictionary = audio.get("audio_settings")
		settings["master_volume"] = clampf(value / 100.0, 0.0, 1.0)
		audio.call("update_master_volume")
		audio.call("save_audio_settings")


func _music_on() -> bool:
	if not has_node("/root/Audio"):
		return true
	var settings: Dictionary = get_node("/root/Audio").get("audio_settings")
	return float(settings.get("music_volume", 0.55)) > 0.001


func _on_music_toggled(on: bool) -> void:
	if has_node("/root/Audio"):
		var audio := get_node("/root/Audio")
		var settings: Dictionary = audio.get("audio_settings")
		settings["music_volume"] = 0.55 if on else 0.0
		audio.call("save_audio_settings")
		if on:
			audio.call("play_menu_music")
		else:
			audio.call("stop_menu_music", 0.2)


func _on_ghost_toggled(on: bool) -> void:
	_save_hud_key("mobile_ghost", on)


func _on_racing_toggled(on: bool) -> void:
	_save_hud_key("mobile_racing_line", on)


func _on_units_toggled(on: bool) -> void:
	_save_hud_key("mobile_distance_units", "km" if on else "m")


# --------------------------------------------------------------- screenshot API
func show_main() -> void:
	_show("main")


func show_play() -> void:
	_show("play")


func show_play_village() -> void:
	_show("play")
	_select_map("village")
	_select_mode("0")


func show_play_industrial() -> void:
	_show("play")
	_select_map("industrial")
	_select_mode("1")


func show_play_combat() -> void:
	_show("play")
	_select_map("village")
	_select_mode("1")
	_select_mission(1)


func show_controls() -> void:
	_show("controls")


func demo_stick_pose() -> void:
	var pad := get_node_or_null("/root/TouchControls")
	if pad != null:
		pad.set("throttle", 0.82)
		pad.set("yaw", 0.72)
		pad.set("pitch", -0.63)
		pad.set("roll", 0.55)
	_show("controls")


func show_rates() -> void:
	_show("rates")


func show_rates_touch() -> void:
	_show("rates")
	_select_rate_tab("touch")
	_refresh_rate_widgets()
	_refresh_rate_status()


func show_rates_help_screen() -> void:
	_show("rates")
	show_rates_help()


func show_drone() -> void:
	_show("drone")


func show_drone_motors() -> void:
	_show("drone")
	_select_drone_tab("motors")


func show_settings() -> void:
	_show("settings")







