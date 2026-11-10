## Mobile tactical menu — a phone-first shell with 3D rotating drone hero and Feel FPV style controls.
##
## Features:
##   - Interactive 3D drone turntable with slow continuous rotation and finger swipe
##   - Next / Previous drone selector buttons with live name, class and TWR specs
##   - Feel FPV style radio controller screen: 2D stick monitor, AETR/TAER mapping,
##     per-axis inversion, level-switched ARM, AUX switches, and quick auto-detect
##   - Safe area handling for iPhone 14 (Notch / Dynamic Island & Home indicator)
##   - Self-contained navigation (pause menu and flight returns cleanly to this menu)
extends Control

const ROUNDED_SHADER: Shader = preload("res://GUI/mobile/rounded_rect.gdshader")
const DronePropellerSystem = preload("res://scripts/util/DronePropellerSystem.gd")
const GlbMaterialUtilsScript = preload("res://scripts/util/glb_material_utils.gd")
const MenuIcons = preload("res://GUI/ui/MenuIcons.gd")

static func _safe_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res: Resource = load(path)
		if res is Texture2D:
			return res as Texture2D
	var global_p: String = ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path) or FileAccess.file_exists(global_p):
		var img: Image = Image.load_from_file(global_p)
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	return null

var _bg_tex: Texture2D
var _bg_blur_tex: Texture2D
var _knob_tex: Texture2D
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
const COLOR_SWATCHES := [
	{"name": "ХАКІ", "col": Color("59604a")},
	{"name": "ЧОРНИЙ", "col": Color("202622")},
	{"name": "ПІСОК", "col": Color("b09a72")},
	{"name": "СІРИЙ", "col": Color("5e6b66")},
]

signal closed

var is_pause_mode := false
var _bg_blur: TextureRect
var _screen_scrim: ColorRect
var _root: VBoxContainer
var _content: Control
var _screens: Dictionary = {}
var _current := "main"
var _back_btn: Button
var _bottom_bar: HBoxContainer
var _elrs_chip: PanelContainer
var _elrs_label: Label
var _input_chip: PanelContainer
var _input_label: Label

# --- 3D Drone Hero Turntable ---
var _hero_container: SubViewportContainer
var _hero_viewport: SubViewport
var _hero_holder: Node3D
var _hero_camera: Camera3D
var _hero_drone_name: Label
var _hero_drone_tag: Label
var _hero_drone_specs: Label
var _is_dragging_hero := false

# --- Sortie Setup (Play) ---
var _selected_map := "village"
var _selected_mode := 0
var _selected_mission := 1
var _map_cards: Dictionary = {}
var _mission_buttons: Dictionary = {}
var _play_caption: Label

# --- Feel FPV Controller Setup & 3D RadioMaster TX12 ---
var _radio: Node3D = null
var _radio_skeleton: Skeleton3D = null
var _radio_viewport: SubViewport = null
var _radio_camera: Camera3D = null
var _stick_preview: StickPreview
var _source_status: Label
var _channel_options: Dictionary = {}
var _invert_buttons: Dictionary = {}
var _channel_bars: Dictionary = {}
var _action_options: Dictionary = {}
var _switch_status_labels: Dictionary = {}
var _arm_status_label: Label
var _arm_status_panel: PanelContainer
var _auto_target := ""
var _auto_detect_buttons: Dictionary = {}
var _calib_btn: Button
var _calib_hint: Label
var _calib_step := 0
var _calib_mins: Dictionary = {}
var _calib_maxs: Dictionary = {}

# --- Rates ---
var _rate_tab := "radio"
var _rate_profiles: Dictionary = {}
var _rate_curve: RateCurve
var _rate_status: Label

# --- Drone Hangar & 3D Showroom ---
var _hangar_container: SubViewportContainer = null
var _hangar_viewport: SubViewport = null
var _hangar_holder: Node3D = null
var _hangar_camera: Camera3D = null
var _hangar_drone_name: Label = null
var _hangar_drone_tag: Label = null
var _hangar_specs_lbl: Label = null
var _hangar_select_btn: Button = null
var _hangar_preview_idx: int = 0
var _hangar_list_container: VBoxContainer = null
var _is_dragging_hangar: bool = false

# --- Settings Tabs & PC Parity ---
var _settings_panels: Dictionary = {}
var _settings_tab: String = "sim"
var _settings_body_container: Control = null
var _settings_tab_buttons: Dictionary = {}
var _sim_toggles: Dictionary = {}
var _hud_toggles: Dictionary = {}
var _quality_buttons: Dictionary = {}
var _fps_slider_hud: HSlider = null
var _fps_label_hud: Label = null


# ---------------------------------------------------------------- UI Controls
class ToggleSwitch extends Button:
	var on := false

	func _init(value: bool = false) -> void:
		on = value
		toggle_mode = true
		button_pressed = value
		focus_mode = Control.FOCUS_NONE
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(96, 46)
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
		track.bg_color = Color(0.12, 0.22, 0.17, 0.95) if not on else Color(0.38, 0.68, 0.48, 1.0)
		track.border_color = Color(0.42, 0.56, 0.46, 0.7) if not on else Color(0.72, 0.95, 0.78, 0.9)
		track.set_border_width_all(2)
		track.set_corner_radius_all(int(r))
		draw_style_box(track, Rect2(Vector2.ZERO, size))
		var knob_x := size.x - r if on else r
		draw_circle(Vector2(knob_x, r), r * 0.76, Color(0.96, 0.99, 0.94, 1.0))


## 2D Stick Monitor (Feel FPV style: twin circles with crosshairs and live stick positions)
class StickPreview extends Control:
	var left := Vector2.ZERO   # Mode 2 Left: X = Yaw (-1..1), Y = Throttle (0..1)
	var right := Vector2.ZERO  # Mode 2 Right: X = Roll (-1..1), Y = Pitch (-1..1)

	func _init() -> void:
		custom_minimum_size = Vector2(0, 250)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_values(l: Vector2, r: Vector2) -> void:
		left = l
		right = r
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w < 20 or h < 30:
			return
		var radius := minf(w * 0.2, h * 0.30)
		var cy := h * 0.40
		var lc := Vector2(w * 0.28, cy)
		var rc := Vector2(w * 0.72, cy)
		_draw_stick(lc, radius, left, "ГАЗ / РИСКАННЯ", true)
		# (підписи тепер мають широку область і не обрізаються)
		_draw_stick(rc, radius, right, "ТАНГАЖ / КРЕН", false)

	func _draw_stick(c: Vector2, r: float, value: Vector2, title: String, is_left: bool) -> void:
		var fill := Color(0.02, 0.05, 0.04, 0.85)
		var rim := Color(0.40, 0.65, 0.50, 0.8)
		var cross := Color(0.40, 0.65, 0.50, 0.3)
		draw_circle(c, r, fill)
		draw_arc(c, r, 0.0, TAU, 48, rim, 1.8, true)
		draw_line(c - Vector2(r * 0.85, 0), c + Vector2(r * 0.85, 0), cross, 1.0)
		draw_line(c - Vector2(0, r * 0.85), c + Vector2(0, r * 0.85), cross, 1.0)

		var norm_pos: Vector2
		if is_left:
			var thr_norm := clampf(value.y, 0.0, 1.0) * 2.0 - 1.0
			norm_pos = Vector2(clampf(value.x, -1.0, 1.0), -thr_norm)
		else:
			norm_pos = Vector2(clampf(value.x, -1.0, 1.0), -clampf(value.y, -1.0, 1.0))

		var kp := c + norm_pos * (r * 0.76)
		draw_circle(kp, r * 0.20, Color(0.35, 0.90, 0.55, 0.95))
		draw_circle(kp, r * 0.12, Color(0.95, 1.0, 0.95, 1.0))
		draw_arc(kp, r * 0.20, 0.0, TAU, 24, Color(0.8, 1.0, 0.8, 0.9), 1.5, true)

		var font := ThemeDB.fallback_font
		var tw := maxf(r * 3.4, 200.0)
		var fs_title := int(clampf(r * 0.2, 12.0, 18.0))
		var fs_sub := int(clampf(r * 0.17, 11.0, 15.0))
		draw_string(font, c + Vector2(-tw * 0.5, -r - 10), title,
				HORIZONTAL_ALIGNMENT_CENTER, tw, fs_title,
				Color(0.85, 0.92, 0.85, 0.95))

		var line1 := ""
		var line2 := ""
		if is_left:
			var thr_pct := int(round(clampf(value.y, 0.0, 1.0) * 100.0))
			line1 = "ГАЗ: %d%%" % thr_pct
			line2 = "РИСКАННЯ: %+d%%" % int(round(value.x * 100.0))
		else:
			line1 = "ТАНГАЖ: %+d%%" % int(round(value.y * 100.0))
			line2 = "КРЕН: %+d%%" % int(round(value.x * 100.0))
		var sub_col := Color(0.70, 0.85, 0.72, 0.95)
		draw_string(font, c + Vector2(-tw * 0.5, r + 8 + fs_sub), line1,
				HORIZONTAL_ALIGNMENT_CENTER, tw, fs_sub, sub_col)
		draw_string(font, c + Vector2(-tw * 0.5, r + 10 + fs_sub * 2), line2,
				HORIZONTAL_ALIGNMENT_CENTER, tw, fs_sub, sub_col)


## Visual Rate Curve representation
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
		draw_string(font, Vector2(right - 34, bottom + 12), "СТІК", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.65, 0.75, 0.68, 0.8))
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


# ---------------------------------------------------------------- Lifecycle
func _ready() -> void:
	_bg_tex = _safe_texture("res://Assets/Branding/mobile_menu_bg.png")
	_bg_blur_tex = _safe_texture("res://Assets/Branding/mobile_menu_bg_blur.png")
	_knob_tex = _safe_texture("res://Assets/Branding/mobile_knob.png")
	if OS.has_feature("mobile") or OS.get_name() == "iOS":
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)
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
	_load_profiles()
	_build_background()
	_build_root()
	_build_main()
	_build_play()
	_build_controls()
	_build_rates()
	_build_drone()
	_build_settings()
	_show("main")
	_update_status()
	set_process(true)


func _process(delta: float) -> void:
	_update_status()

	# 3D Drone Hero Turntable: continuous idle rotation and propeller animation
	if _hero_holder != null:
		if not _is_dragging_hero:
			_hero_holder.rotation.y += delta * 0.45
		for child in _hero_holder.get_children():
			if child.has_meta("prop_pivots"):
				DroneCatalog.animate_propellers(child, delta * 0.8)

	# 3D Drone Hangar Turntable: rotation and propeller animation when viewing Hangar
	if _hangar_holder != null and _current == "drone":
		if not _is_dragging_hangar:
			_hangar_holder.rotation.y += delta * 0.45
		for child in _hangar_holder.get_children():
			if child.has_meta("prop_pivots"):
				DroneCatalog.animate_propellers(child, delta * 0.8)

	# 2D Live Stick Monitor & 3D RadioMaster TX12 Sticks Animation
	if _current == "controls":
		var elrs := get_node_or_null("/root/ElrsWifiInput")
		var touch := get_node_or_null("/root/TouchControls")
		var thr := 0.0
		var yaw := 0.0
		var pit := 0.0
		var rol := 0.0
		var is_elrs: bool = elrs != null and bool(elrs.get("valid"))
		if is_elrs:
			thr = float(elrs.throttle())
			yaw = float(elrs.yaw())
			pit = float(elrs.pitch())
			rol = float(elrs.roll())
		elif Controls.active_device >= 0 or Input.get_connected_joypads().size() > 0:
			var c_thr := Controls.physical_channel_value("throttle")
			var c_yaw := Controls.physical_channel_value("yaw")
			var c_pit := Controls.physical_channel_value("pitch")
			var c_rol := Controls.physical_channel_value("roll")
			thr = 0.0 if is_nan(c_thr) else c_thr
			yaw = 0.0 if is_nan(c_yaw) else c_yaw
			pit = 0.0 if is_nan(c_pit) else c_pit
			rol = 0.0 if is_nan(c_rol) else c_rol
		elif touch != null and bool(touch.get("touch_mode")):
			thr = float(touch.get("throttle"))
			yaw = float(touch.get("yaw"))
			pit = float(touch.get("pitch"))
			rol = float(touch.get("roll"))

		if _stick_preview != null:
			_stick_preview.set_values(Vector2(yaw, thr), Vector2(rol, pit))

		if _radio_skeleton != null:
			_set_radio_stick_bone("LeftStickVertical", Vector3.RIGHT, deg_to_rad(27.0 * thr))
			_set_radio_stick_bone("LeftStickHorizontal", Vector3.FORWARD, deg_to_rad(27.0 * yaw))
			_set_radio_stick_bone("RightStickVertical", Vector3.RIGHT, deg_to_rad(27.0 * -pit))
			_set_radio_stick_bone("RightStickHorizontal", Vector3.FORWARD, deg_to_rad(27.0 * rol))

		_process_controls_screen()


func _set_radio_stick_bone(bone_name: String, axis: Vector3, angle: float) -> void:
	if _radio_skeleton == null:
		return
	var b: int = _radio_skeleton.find_bone(bone_name)
	if b < 0:
		return
	var pose: Transform3D = _radio_skeleton.get_bone_rest(b)
	pose.basis = pose.basis.rotated(axis, angle)
	_radio_skeleton.set_bone_pose(b, pose)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _load_radio_model() -> Node3D:
	var glb_path := "res://Assets/Drones/ua_norm/radiomaster_tx12_rig.glb"
	if not FileAccess.file_exists(glb_path):
		glb_path = "res://Assets/Drones/ua_norm/radiomaster_tx12.glb"
	if FileAccess.file_exists(glb_path):
		var bytes := FileAccess.get_file_as_bytes(glb_path)
		if bytes.size() > 0:
			var doc := GLTFDocument.new()
			var state := GLTFState.new()
			var err := doc.append_from_buffer(bytes, "", state)
			if err == OK:
				return doc.generate_scene(state) as Node3D
	return null


# ---------------------------------------------------------------- Shell & Layout
func _vsize() -> Vector2:
	return get_viewport_rect().size


func _fs(px: float) -> int:
	return maxi(9, int(round(px * clampf(_vsize().y / 1080.0, 0.52, 1.6))))


func _gap(px: float) -> int:
	return maxi(2, int(round(px * clampf(_vsize().y / 1080.0, 0.5, 1.5))))


func _label(text: String, size: float, color: Color = MenuUI.TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", _fs(size))
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.65))
	l.add_theme_constant_override("outline_size", _gap(3))
	return l


func _panel_style(bg: Color = Color(0.035, 0.075, 0.06, 0.88),
		border: Color = Color(0.34, 0.5, 0.4, 0.5),
		border_width: int = 1, radius: int = 16) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = _gap(16)
	sb.content_margin_right = _gap(16)
	sb.content_margin_top = _gap(12)
	sb.content_margin_bottom = _gap(12)
	return sb


func _panel(bg: Color = Color(0.035, 0.075, 0.06, 0.88),
		border: Color = Color(0.34, 0.5, 0.4, 0.5),
		border_width: int = 1, radius: int = 16) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _panel_style(bg, border, border_width, radius))
	return p


func _button_style(bg: Color, border: Color, border_width: int = 1, radius: int = 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = _gap(16)
	sb.content_margin_right = _gap(16)
	sb.content_margin_top = _gap(2)
	sb.content_margin_bottom = _gap(2)
	return sb


func _button(text: String, height: float, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, _fs(height))
	b.add_theme_font_size_override("font_size", _fs(22 if not primary else 28))
	b.add_theme_color_override("font_color", Color(0.06, 0.09, 0.07) if primary else MenuUI.TEXT)
	b.add_theme_color_override("font_hover_color", Color(0.06, 0.09, 0.07) if primary else MenuUI.TEXT)
	b.add_theme_color_override("font_pressed_color", Color(0.06, 0.09, 0.07) if primary else MenuUI.TEXT)
	var normal_bg := Color(0.72, 0.82, 0.65, 0.98) if primary else Color(0.04, 0.08, 0.065, 0.88)
	var hover_bg := Color(0.82, 0.90, 0.72, 1.0) if primary else Color(0.08, 0.15, 0.11, 0.96)
	var pressed_bg := Color(0.58, 0.70, 0.50, 1.0) if primary else Color(0.10, 0.22, 0.15, 1.0)
	var border := Color(0.88, 0.76, 0.46, 0.9) if primary else Color(0.32, 0.48, 0.38, 0.6)
	b.add_theme_stylebox_override("normal", _button_style(normal_bg, border, 1, 12))
	b.add_theme_stylebox_override("hover", _button_style(hover_bg, border, 1, 12))
	b.add_theme_stylebox_override("pressed", _button_style(pressed_bg, border, 1, 12))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


func _nav_button(icon_tex: Texture2D, text: String, primary: bool, callback: Callable) -> Button:
	var compact := _vsize().y < 700.0
	var height := (64.0 if not primary else 72.0) if compact else (84.0 if not primary else 94.0)
	var b := _button("  " + text, height, primary)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if icon_tex != null:
		b.icon = icon_tex
		b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.expand_icon = true
	b.add_theme_font_size_override("font_size", _fs(26 if not primary else 30))
	b.add_theme_constant_override("h_separation", _gap(14))
	b.pressed.connect(callback)
	return b


func _slider(value: float, minv: float, maxv: float, step: float, on_change: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = minv
	s.max_value = maxv
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(0, _fs(28))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _knob_tex != null:
		s.add_theme_icon_override("grabber", _knob_tex)
		s.add_theme_icon_override("grabber_highlight", _knob_tex)
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


func _style_option_button(opt: OptionButton) -> void:
	opt.focus_mode = Control.FOCUS_NONE
	opt.add_theme_font_size_override("font_size", _fs(16))
	opt.add_theme_stylebox_override("normal", _panel_style(Color(0.04, 0.09, 0.07, 0.95), Color(0.35, 0.52, 0.42, 0.7), 1, 8))
	opt.add_theme_stylebox_override("hover", _panel_style(Color(0.08, 0.16, 0.12, 1.0), Color(0.55, 0.75, 0.62, 0.9), 1, 8))
	opt.add_theme_stylebox_override("pressed", _panel_style(Color(0.06, 0.12, 0.09, 1.0), Color(0.35, 0.52, 0.42, 0.7), 1, 8))
	opt.add_theme_color_override("font_color", MenuUI.TEXT)
	opt.add_theme_color_override("font_hover_color", MenuUI.TEXT)
	opt.add_theme_color_override("font_pressed_color", MenuUI.TEXT)


func _style_progress_bar(bar: ProgressBar) -> void:
	var bg_sb := StyleBoxFlat.new()
	bg_sb.bg_color = Color(0.04, 0.08, 0.06, 0.95)
	bg_sb.border_color = Color(0.24, 0.36, 0.28, 0.6)
	bg_sb.set_border_width_all(1)
	bg_sb.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg_sb)

	var fill_sb := StyleBoxFlat.new()
	fill_sb.bg_color = Color(0.38, 0.65, 0.48, 0.95)
	fill_sb.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fill_sb)


func _build_background() -> void:
	var bg := TextureRect.new()
	if _bg_tex != null:
		bg.texture = _bg_tex
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_bg_blur = TextureRect.new()
	if _bg_blur_tex != null:
		_bg_blur.texture = _bg_blur_tex
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

	# iPhone 14 Safe Area Handling (Notch / Dynamic Island & Home indicator)
	var safe := DisplayServer.get_display_safe_area()
	var left_pad := 24
	var right_pad := 24
	var top_pad := 12
	var bottom_pad := 14
	if safe.size.x > 0 and safe.size.y > 0 and DisplayServer.screen_get_size().x > 0:
		var scale_x := s.x / float(DisplayServer.screen_get_size().x)
		var scale_y := s.y / float(DisplayServer.screen_get_size().y)
		left_pad = maxi(left_pad, int(safe.position.x * scale_x))
		right_pad = maxi(right_pad, int((DisplayServer.screen_get_size().x - safe.end.x) * scale_x))
		top_pad = maxi(top_pad, int(safe.position.y * scale_y))
		bottom_pad = maxi(bottom_pad, int((DisplayServer.screen_get_size().y - safe.end.y) * scale_y))

	margin.add_theme_constant_override("margin_left", left_pad)
	margin.add_theme_constant_override("margin_right", right_pad)
	margin.add_theme_constant_override("margin_top", top_pad)
	margin.add_theme_constant_override("margin_bottom", bottom_pad)
	add_child(margin)

	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", _gap(8))
	margin.add_child(_root)

	# Top Masthead
	var top := HBoxContainer.new()
	top.custom_minimum_size.y = _fs(64)
	top.add_theme_constant_override("separation", _gap(12))
	_root.add_child(top)

	_back_btn = _button("НАЗАД", 44)
	_back_btn.icon = MenuIcons.icon_back(MenuUI.TEXT)
	_back_btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_back_btn.add_theme_constant_override("h_separation", _gap(8))
	_back_btn.custom_minimum_size = Vector2(_fs(140), _fs(44))
	_back_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_back_btn.pressed.connect(_on_back)
	_back_btn.visible = false
	top.add_child(_back_btn)

	var brand := VBoxContainer.new()
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand.alignment = BoxContainer.ALIGNMENT_CENTER
	brand.add_theme_constant_override("separation", _gap(1))
	top.add_child(brand)

	var logo := _label("НЕБЕСНИЙ ГОРИЗОНТ", 34, MenuUI.TEXT)
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	brand.add_child(logo)
	var brand_sub := _label("БОЙОВИЙ FPV СИМУЛЯТОР  •  МОБІЛЬНИЙ ТЕРМІНАЛ", 13, MenuUI.MUTED)
	brand_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	brand.add_child(brand_sub)

	var chips := HBoxContainer.new()
	chips.alignment = BoxContainer.ALIGNMENT_END
	chips.add_theme_constant_override("separation", _gap(8))
	top.add_child(chips)

	_elrs_chip = _panel(Color(0.03, 0.07, 0.055, 0.85), Color(0.40, 0.62, 0.48, 0.65), 1, 8)
	_elrs_label = _label("ELRS: ПОШУК", 13, MenuUI.MUTED)
	_elrs_chip.add_child(_elrs_label)
	chips.add_child(_elrs_chip)

	_input_chip = _panel(Color(0.03, 0.07, 0.055, 0.85), Color(0.62, 0.76, 0.55, 0.65), 1, 8)
	_input_label = _label("ВХІД: СЕНСОР", 13, MenuUI.FPV_CYAN)
	_input_chip.add_child(_input_label)
	chips.add_child(_input_chip)

	_content = Control.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_child(_content)


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
	_screen_scrim.color = Color(0.015, 0.045, 0.035, 0.10 if name == "main" else 0.22)
	_update_status()


func _on_back() -> void:
	if is_pause_mode:
		emit_signal("closed")
		visible = false
		is_pause_mode = false
	else:
		_show("main")


func open_tab(tab_name: String, pause_mode: bool = false) -> void:
	is_pause_mode = pause_mode
	visible = true
	_show(tab_name)


func show_main() -> void:
	_show("main")


func show_play() -> void:
	_show("play")


func show_controls() -> void:
	_show("controls")


func show_rates() -> void:
	_show("rates")


func show_drone() -> void:
	_show("drone")


func show_settings() -> void:
	_show("settings")


func _update_status() -> void:
	if _elrs_label == null:
		return
	var elrs := get_node_or_null("/root/ElrsWifiInput")
	var valid: bool = elrs != null and bool(elrs.get("valid"))
	var status := str(elrs.get("status_text")) if elrs != null else ""
	if valid or status.find("ПОТІК") >= 0:
		_elrs_label.text = "ELRS: ПОТІК"
		_elrs_label.add_theme_color_override("font_color", MenuUI.FPV_GREEN)
		if _input_label != null:
			_input_label.text = "ВХІД: ELRS (POCKET)"
			_input_label.add_theme_color_override("font_color", MenuUI.FPV_GREEN)
	else:
		_elrs_label.text = status if not status.is_empty() else "ELRS: ВИМК."
		_elrs_label.add_theme_color_override("font_color", MenuUI.MUTED)
		if _input_label != null:
			_input_label.text = "ВХІД: СЕНСОР"
			_input_label.add_theme_color_override("font_color", MenuUI.FPV_CYAN)


# ---------------------------------------------------------------- MAIN SCREEN WITH 3D HERO
func _build_main() -> void:
	var screen := _make_screen("main")
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.add_theme_constant_override("separation", _gap(20))
	screen.add_child(h)

	# Left Nav Rail
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.42
	left.add_theme_constant_override("separation", _gap(10))
	h.add_child(left)

	left.add_child(_label("ГОЛОВНЕ МЕНЮ // ТЕРМІНАЛ", 15, MenuUI.FPV_AMBER))
	left.add_child(_spacer(_gap(4)))

	left.add_child(_nav_button(MenuIcons.icon_play(Color(0.06, 0.09, 0.07)), "ОДИНОЧНА ГРА", true, func(): _show("play")))
	left.add_child(_nav_button(MenuIcons.icon_radio(MenuUI.TEXT), "ПУЛЬТ ТА ELRS", false, func(): _show("controls")))
	left.add_child(_nav_button(MenuIcons.icon_rates(MenuUI.TEXT), "РЕЙТИ ТА ЕКСПО", false, func(): _show("rates")))
	left.add_child(_nav_button(MenuIcons.icon_hangar(MenuUI.TEXT), "АНГАР ДРОНІВ", false, func(): _show("drone")))
	left.add_child(_nav_button(MenuIcons.icon_settings(MenuUI.TEXT), "НАЛАШТУВАННЯ", false, func(): _show("settings")))

	left.add_child(_spacer(_gap(6)))

	# Tactical Changelog Card for this version
	var chg_card := _panel(Color(0.02, 0.048, 0.038, 0.92), Color(0.38, 0.54, 0.42, 0.70), 1, 12)
	chg_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var chg_m := MarginContainer.new()
	chg_m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	chg_m.add_theme_constant_override("margin_left", _fs(14))
	chg_m.add_theme_constant_override("margin_right", _fs(14))
	chg_m.add_theme_constant_override("margin_top", _fs(10))
	chg_m.add_theme_constant_override("margin_bottom", _fs(10))
	chg_card.add_child(chg_m)

	var chg_v := VBoxContainer.new()
	chg_v.add_theme_constant_override("separation", _gap(6))
	chg_m.add_child(chg_v)

	var chg_hdr := HBoxContainer.new()
	chg_hdr.add_child(_label("ОНОВЛЕННЯ // СПИСОК ЗМІН", 15, MenuUI.FPV_AMBER))
	chg_hdr.add_child(_spacer(0, Control.SIZE_EXPAND_FILL))
	chg_hdr.add_child(_label("v1.40-b24", 13, MenuUI.FPV_GREEN))
	chg_v.add_child(chg_hdr)

	var changes := [
		"• Повний військовий інтерфейс Feel FPV та темна тема",
		"• 3D ангар та огляд 13 бортів на платформі",
		"• Підтримка пультів RadioMaster TX12 та ELRS Wi-Fi",
		"• Калібрування стіків, налаштування AUX та рейт",
		"• Оптимізація 60/120 FPS для iPhone та сенсорний ввід"
	]
	for c_txt in changes:
		var cl := Label.new()
		cl.text = c_txt
		cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cl.add_theme_font_size_override("font_size", _fs(13))
		cl.add_theme_color_override("font_color", Color(0.85, 0.94, 0.88))
		chg_v.add_child(cl)

	left.add_child(chg_card)
	left.add_child(_spacer(0, Control.SIZE_EXPAND_FILL))

	var quit_btn := _button("  ВИХІД З ГРИ", 48)
	quit_btn.icon = MenuIcons.icon_close(Color(0.95, 0.45, 0.45))
	quit_btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	quit_btn.add_theme_font_size_override("font_size", _fs(18))
	quit_btn.custom_minimum_size = Vector2(_fs(220), _fs(48))
	quit_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	quit_btn.pressed.connect(func(): get_tree().quit())
	left.add_child(quit_btn)

	# Right 3D Rotating Drone Hero
	var hero := _build_3d_hero()
	hero.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero.size_flags_stretch_ratio = 0.58
	h.add_child(hero)


func _build_3d_hero() -> Control:
	var card := _panel(Color(0.025, 0.065, 0.05, 0.92), Color(0.38, 0.54, 0.42, 0.55), 1, 18)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# 3D Viewport container for interactive turntable
	_hero_container = SubViewportContainer.new()
	_hero_container.stretch = true
	_hero_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hero_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hero_container.mouse_filter = Control.MOUSE_FILTER_PASS
	_hero_container.gui_input.connect(_on_hero_gui_input)
	card.add_child(_hero_container)

	_hero_viewport = SubViewport.new()
	_hero_viewport.own_world_3d = true
	_hero_viewport.transparent_bg = true
	_hero_viewport.msaa_3d = Viewport.MSAA_2X
	_hero_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	_hero_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_hero_viewport.size = Vector2i(1280, 720)
	_hero_container.add_child(_hero_viewport)

	_setup_hero_3d_world()

	# Overlay UI on top of 3D Hero
	var overlay := MarginContainer.new()
	overlay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overlay.size_flags_vertical = Control.SIZE_EXPAND_FILL
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		overlay.add_theme_constant_override("margin_%s" % side, _gap(16))
	card.add_child(overlay)

	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(v)

	# Top info chip
	var top_info := HBoxContainer.new()
	top_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top_info)

	var info_box := VBoxContainer.new()
	info_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_box.add_theme_constant_override("separation", _gap(2))
	top_info.add_child(info_box)

	_hero_drone_name = _label("«ГОЛКА»", 32, MenuUI.TEXT)
	_hero_drone_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_box.add_child(_hero_drone_name)

	_hero_drone_tag = _label("ФРІСТАЙЛ 5\"  •  БОРТ ЗА ЗАМОВЧУВАННЯМ", 14, MenuUI.FPV_AMBER)
	_hero_drone_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_box.add_child(_hero_drone_tag)

	_hero_drone_specs = _label("МАСА: 600 г  •  TWR: 8.5:1  •  2500 KV", 12, MenuUI.MUTED)
	_hero_drone_specs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_box.add_child(_hero_drone_specs)

	v.add_child(_spacer(0, Control.SIZE_EXPAND_FILL))

	# Bottom Selector Bar & Play Action (Centered Launch Action)
	var bottom_selector := HBoxContainer.new()
	bottom_selector.add_theme_constant_override("separation", _gap(12))
	bottom_selector.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(bottom_selector)

	var prev_btn := _button("ПОПЕРЕДНІЙ", 50)
	prev_btn.custom_minimum_size.x = _fs(165)
	prev_btn.pressed.connect(_select_prev_drone)
	bottom_selector.add_child(prev_btn)

	var play_text := "ПРОДОВЖИТИ ПОЛІТ" if is_pause_mode else "ПОЧАТИ ВИЛЬОТ"
	var play_btn := _button(play_text, 54, true)
	play_btn.custom_minimum_size.x = _fs(280)
	play_btn.pressed.connect(func():
		if is_pause_mode:
			emit_signal("closed")
			visible = false
			is_pause_mode = false
		else:
			_show("play")
	)
	bottom_selector.add_child(play_btn)

	var next_btn := _button("НАСТУПНИЙ", 50)
	next_btn.custom_minimum_size.x = _fs(165)
	next_btn.pressed.connect(_select_next_drone)
	bottom_selector.add_child(next_btn)

	_update_hero_drone_info(Global.drone_preset)
	return card


func _setup_hero_3d_world() -> void:
	_hero_viewport.size = Vector2i(1280, 720)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.80, 0.75)
	env.ambient_light_energy = 1.35
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.08
	var world := WorldEnvironment.new()
	world.environment = env
	_hero_viewport.add_child(world)

	# Key Light (top-front-right)
	var key := DirectionalLight3D.new()
	key.light_energy = 2.4
	key.light_color = Color(1.0, 0.96, 0.88)
	key.rotation_degrees = Vector3(-35.0, 45.0, 0.0)
	_hero_viewport.add_child(key)

	# Fill Light (left)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 1.4
	fill.light_color = Color(0.55, 0.78, 0.65)
	fill.rotation_degrees = Vector3(-20.0, -60.0, 0.0)
	_hero_viewport.add_child(fill)

	# Rim Light (back-right)
	var rim := DirectionalLight3D.new()
	rim.light_energy = 2.2
	rim.light_color = Color(0.80, 0.95, 0.85)
	rim.rotation_degrees = Vector3(25.0, -145.0, 0.0)
	_hero_viewport.add_child(rim)

	# Front fill
	var front := DirectionalLight3D.new()
	front.light_energy = 1.0
	front.light_color = Color(0.78, 0.88, 0.90)
	front.rotation_degrees = Vector3(-10.0, 0.0, 0.0)
	_hero_viewport.add_child(front)

	# Illuminated turntable pedestal
	var pedestal := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.74
	cyl.bottom_radius = 0.78
	cyl.height = 0.02
	cyl.radial_segments = 48
	pedestal.mesh = cyl
	pedestal.position = Vector3(0.0, -0.215, 0.0)
	var ped_mat := StandardMaterial3D.new()
	ped_mat.albedo_color = Color(0.12, 0.17, 0.15)
	ped_mat.roughness = 0.85
	ped_mat.metallic = 0.3
	pedestal.material_override = ped_mat
	_hero_viewport.add_child(pedestal)

	# Glowing tactical accent ring (flush with surface to avoid cutting through drone arms/motors)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.68
	torus.outer_radius = 0.72
	torus.rings = 48
	torus.ring_segments = 24
	ring.mesh = torus
	ring.scale = Vector3(1.0, 0.04, 1.0)
	ring.position = Vector3(0.0, -0.2045, 0.0)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = MenuUI.ACCENT
	ring.material_override = ring_mat
	_hero_viewport.add_child(ring)

	_hero_camera = Camera3D.new()
	_hero_camera.fov = 38.0
	_hero_camera.current = true
	_hero_viewport.add_child(_hero_camera)

	_hero_holder = Node3D.new()
	_hero_viewport.add_child(_hero_holder)
	_load_hero_model(Global.drone_preset)


func _load_hero_model(preset_idx: int) -> void:
	if _hero_holder == null:
		return
	for child in _hero_holder.get_children():
		child.queue_free()
	var model: Node3D = DroneCatalog.attach_model(_hero_holder, preset_idx)
	if model != null:
		MenuUI.fit_preview_model(model, 0.86, -0.205)
	_fit_hero_camera()
	_update_hero_drone_info(preset_idx)


func _fit_hero_camera() -> void:
	if _hero_holder == null or _hero_camera == null:
		return
	var box := _combined_bounds(_hero_holder)
	var center := box.get_center() if box.size.length() > 0.01 else Vector3.ZERO
	var fov := 36.0
	var aspect := 1.7
	if _hero_viewport != null and _hero_viewport.size.y > 0:
		aspect = float(_hero_viewport.size.x) / float(_hero_viewport.size.y)
	var half_w := maxf(box.size.x, box.size.z) * 0.5
	var vfov := deg_to_rad(fov)
	var hfov := 2.0 * atan(tan(vfov * 0.5) * aspect)
	var dist_w := half_w / maxf(tan(hfov * 0.5), 0.001)
	
	var focus_y := clampf(center.y + 0.06, 0.08, 0.42)
	var focus := Vector3(center.x, focus_y, center.z)
	var top_extent := (box.position.y + box.size.y) - focus_y
	var btm_extent := focus_y - box.position.y
	var half_h := maxf(maxf(top_extent, btm_extent), box.size.y * 0.60)
	var dist_h := half_h / maxf(tan(vfov * 0.5), 0.001)
	
	var dist := clampf(maxf(dist_w * 1.55, dist_h * 1.75), 1.20, 4.30)
	var dir := Vector3(0.48, 0.36, 0.85).normalized()
	_hero_camera.fov = fov
	var cam_pos := focus + dir * dist
	_hero_camera.look_at_from_position(cam_pos, focus, Vector3.UP)


func _combined_bounds(node: Node3D) -> AABB:
	var result := AABB()
	var first := true
	var stack: Array = [node]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is VisualInstance3D:
			var vi := n as VisualInstance3D
			var b: AABB = vi.global_transform * vi.get_aabb()
			if first:
				result = b
				first = false
			else:
				result = result.merge(b)
		for c in (n as Node).get_children():
			if c is Node3D:
				stack.append(c)
	return result


func _update_hero_drone_info(preset_idx: int) -> void:
	var p := DroneCatalog.preset(preset_idx)
	if _hero_drone_name != null:
		_hero_drone_name.text = str(p.get("name", "ДРОН"))
	if _hero_drone_tag != null:
		_hero_drone_tag.text = str(p.get("tag", "FPV"))
	if _hero_drone_specs != null:
		var mass := int(round((float(p.get("dry", 0.4)) + float(p.get("batt", 0.2))) * 1000.0))
		var twr := float(p.get("twr", 5.0))
		var kv := int(p.get("kv", 2000))
		_hero_drone_specs.text = "МАСА: %d г  •  TWR: %.1f:1  •  МОТОРИ: %d KV" % [mass, twr, kv]


func _select_next_drone() -> void:
	var total := DroneCatalog.count()
	var next_idx := (Global.drone_preset + 1) % total
	Global.drone_preset = next_idx
	Global.menu_settings["drone_preset"] = next_idx
	Global.save_menu_settings()
	DroneCatalog.apply(next_idx)
	_load_hero_model(next_idx)


func _select_prev_drone() -> void:
	var total := DroneCatalog.count()
	var prev_idx := (Global.drone_preset - 1 + total) % total
	Global.drone_preset = prev_idx
	Global.menu_settings["drone_preset"] = prev_idx
	Global.save_menu_settings()
	DroneCatalog.apply(prev_idx)
	_load_hero_model(prev_idx)


func _on_hero_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_is_dragging_hero = mb.pressed
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		_is_dragging_hero = st.pressed
	elif event is InputEventMouseMotion and _is_dragging_hero:
		var mm := event as InputEventMouseMotion
		if _hero_holder != null:
			_hero_holder.rotation.y += mm.relative.x * 0.012
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if _hero_holder != null:
			_hero_holder.rotation.y += sd.relative.x * 0.012


# ---------------------------------------------------------------- FEEL FPV CONTROLLER SCREEN
func _build_controls() -> void:
	var screen := _make_screen("controls")
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", _gap(10))
	screen.add_child(v)

	# Header with status
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", _gap(14))
	v.add_child(hdr)

	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", _gap(2))
	hdr.add_child(title_box)
	title_box.add_child(_label("НАЛАШТУВАННЯ ПУЛЬТА ТА СТІКІВ", 32, MenuUI.TEXT))
	title_box.add_child(_label("Канали AETR/TAER, інверсія, калібрування та тумблери", 14, MenuUI.MUTED))

	hdr.add_child(_spacer(0, Control.SIZE_EXPAND_FILL))

	_source_status = _label("ELRS: ПОШУК", 16, MenuUI.FPV_GREEN)
	hdr.add_child(_source_status)

	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", _gap(14))
	v.add_child(cols)

	# --- Left Column: 3D RadioMaster TX12 Transmitter + Stick Monitor & Calibration ---
	var left_card := _panel(Color(0.025, 0.065, 0.05, 0.92), Color(0.38, 0.54, 0.42, 0.55), 1, 16)
	left_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_card.size_flags_stretch_ratio = 0.88
	cols.add_child(left_card)

	var left_v := VBoxContainer.new()
	left_v.add_theme_constant_override("separation", _gap(6))
	left_card.add_child(left_v)

	left_v.add_child(_label("ПУЛЬТ RADIOMASTER TX12 (MODE 2)", 15, MenuUI.FPV_AMBER))

	# 3D Radio Viewport Container
	var radio_cont := SubViewportContainer.new()
	radio_cont.stretch = true
	radio_cont.custom_minimum_size = Vector2(0, _fs(210))
	radio_cont.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_v.add_child(radio_cont)

	_radio_viewport = SubViewport.new()
	_radio_viewport.own_world_3d = true
	_radio_viewport.transparent_bg = true
	_radio_viewport.msaa_3d = Viewport.MSAA_2X
	_radio_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	_radio_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_radio_viewport.size = Vector2i(720, 480)
	radio_cont.add_child(_radio_viewport)

	var r_env := Environment.new()
	r_env.background_mode = Environment.BG_CLEAR_COLOR
	r_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	r_env.ambient_light_color = Color(0.85, 0.90, 0.88)
	r_env.ambient_light_energy = 0.95
	var r_we := WorldEnvironment.new()
	r_we.environment = r_env
	_radio_viewport.add_child(r_we)

	var r_light := DirectionalLight3D.new()
	r_light.light_energy = 1.8
	r_light.look_at_from_position(Vector3(0.3, 1.5, 0.8), Vector3(0.0, 0.0, 0.033), Vector3.UP)
	_radio_viewport.add_child(r_light)

	var r_fill := DirectionalLight3D.new()
	r_fill.light_energy = 0.7
	r_fill.look_at_from_position(Vector3(-0.4, 1.3, -0.6), Vector3(0.0, 0.0, 0.033), Vector3.UP)
	_radio_viewport.add_child(r_fill)

	var r_model := _load_radio_model()
	if r_model != null:
		_radio_viewport.add_child(r_model)
		_radio = r_model
		_radio_skeleton = _find_skeleton(r_model)
	else:
		# Fallback to high-res 2D texture if 3D model fails
		var fb_tex: Texture2D = null
		for p in ["res://Assets/Drones/ua/radiomaster_tx12_0.png", "res://Assets/Drones/ua_norm/radiomaster_tx12_rig_Image_0.png", "res://Assets/Drones/ua_norm/radiomaster_tx12_Image_0.png"]:
			if ResourceLoader.exists(p):
				fb_tex = load(p) as Texture2D
				if fb_tex != null:
					break
			if FileAccess.file_exists(p):
				var b_data := FileAccess.get_file_as_bytes(p)
				if b_data.size() > 0:
					var img := Image.new()
					if img.load_png_from_buffer(b_data) == OK:
						fb_tex = ImageTexture.create_from_image(img)
						break
		if fb_tex != null:
			var fb_rect := TextureRect.new()
			fb_rect.texture = fb_tex
			fb_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			fb_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			fb_rect.custom_minimum_size = Vector2(0, _fs(210))
			fb_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
			left_v.add_child(fb_rect)
			left_v.move_child(fb_rect, 1)
			radio_cont.visible = false

	var r_omni := OmniLight3D.new()
	r_omni.position = Vector3(0.0, 1.15, 0.033)
	r_omni.light_energy = 0.9
	_radio_viewport.add_child(r_omni)

	_radio_camera = Camera3D.new()
	_radio_camera.fov = 20.0
	_radio_camera.look_at_from_position(Vector3(0.0, 1.0, 0.033), Vector3(0.0, 0.0, 0.033), Vector3.FORWARD)
	_radio_viewport.add_child(_radio_camera)
	_radio_camera.current = true

	# 2D Live Stick Monitor Readout
	_stick_preview = StickPreview.new()
	_stick_preview.custom_minimum_size = Vector2(0, _fs(110))
	left_v.add_child(_stick_preview)

	_calib_hint = _label("Стіки мають досягати 100% у кутах та повертатися в 0%", 12, MenuUI.MUTED)
	_calib_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_v.add_child(_calib_hint)

	_calib_btn = _button("КАЛІБРУВАТИ СТІКИ", 42, true)
	_calib_btn.pressed.connect(_on_calibrate_pressed)
	left_v.add_child(_calib_btn)

	var tuning_v := VBoxContainer.new()
	tuning_v.add_theme_constant_override("separation", _gap(2))
	left_v.add_child(tuning_v)

	var dead_row := HBoxContainer.new()
	dead_row.add_child(_label("Мертва зона: 2%", 11, MenuUI.MUTED))
	dead_row.add_child(_slider(Controls.stick_deadzone, 0.0, 0.15, 0.01, func(val: float):
		Controls.stick_deadzone = val
		Controls.save_bindings()
	))
	tuning_v.add_child(dead_row)

	var smooth_row := HBoxContainer.new()
	smooth_row.add_child(_label("Згладжування: 0.10", 12, MenuUI.MUTED))
	smooth_row.add_child(_slider(Controls.stick_smoothing, 0.0, 0.35, 0.01, func(val: float):
		Controls.stick_smoothing = val
		Controls.save_bindings()
	))
	tuning_v.add_child(smooth_row)

	# --- Right Column: Channels & Switches Mapping ---
	var right_card := _panel(Color(0.025, 0.065, 0.05, 0.92), Color(0.38, 0.54, 0.42, 0.55), 1, 16)
	right_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_card.size_flags_stretch_ratio = 1.15
	cols.add_child(right_card)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	right_card.add_child(scroll)

	var right_v := VBoxContainer.new()
	right_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_v.add_theme_constant_override("separation", _gap(8))
	scroll.add_child(right_v)

	right_v.add_child(_label("ОСНОВНІ КАНАЛИ СТІКІВ", 16, MenuUI.FPV_AMBER))
	right_v.add_child(_build_stick_row("roll", "КРЕН (ROLL)", 0))
	right_v.add_child(_build_stick_row("pitch", "ТАНГАЖ (PITCH)", 1))
	right_v.add_child(_build_stick_row("throttle", "ГАЗ (THROTTLE)", 2))
	right_v.add_child(_build_stick_row("yaw", "РИСКАННЯ (YAW)", 3))

	right_v.add_child(_spacer(_gap(4)))
	right_v.add_child(_label("БОЙОВІ ФУНКЦІЇ, СКИД ТА ПІДРИВ", 15, MenuUI.FPV_AMBER))
	right_v.add_child(_build_switch_row("arm", "АРМУВАННЯ ДВИГУНІВ (ARM)", 4, true))
	right_v.add_child(_build_switch_row("deploy_payload", "СКИД БОЄПРИПАСУ (DROP)", 5, false))
	right_v.add_child(_build_switch_row("activate_payload", "ПІДРИВ ДРОНА / БЧ (DETONATE)", 6, false))

	right_v.add_child(_spacer(_gap(4)))
	right_v.add_child(_label("РЕЖИМИ ПОЛЬОТУ ТА АСИСТЕНТИ", 15, MenuUI.FPV_AMBER))
	right_v.add_child(_build_switch_row("cycle_flight_modes", "ЦИКЛ РЕЖИМІВ (CYCLE MODES)", 7, false))
	right_v.add_child(_build_switch_row("mode_turtle", "РЕЖИМ TURTLE (ПЕРЕВЕРТАННЯ)", 8, false))
	right_v.add_child(_build_switch_row("mode_angle", "РЕЖИМ ANGLE (СТАБІЛІЗАЦІЯ)", 9, false))
	right_v.add_child(_build_switch_row("mode_horizon", "РЕЖИМ HORIZON (ГОРИЗОНТ+АКРО)", 10, false))
	right_v.add_child(_build_switch_row("altitude_hold", "УТРИМАННЯ ВИСОТИ (ASSIST)", 11, false))

	right_v.add_child(_spacer(_gap(4)))
	right_v.add_child(_label("СИСТЕМНІ ТА ОПТИЧНІ ТУМБЛЕРИ", 15, MenuUI.FPV_AMBER))
	right_v.add_child(_build_switch_row("cycle_video_mode", "ВІДЕО / ПНБ / ТЕПЛОВІЗОР", 12, false))
	right_v.add_child(_build_switch_row("respawn", "ШВИДКИЙ РЕСПАВН (RESPAWN)", 13, false))
	right_v.add_child(_build_switch_row("toggle_weather", "ЗМІНА ПОГОДИ / ВІТЕР", 14, false))
	right_v.add_child(_build_switch_row("pause_menu", "МЕНЮ ПАУЗИ (PAUSE)", 15, false))
	right_v.add_child(_build_switch_row("toggle_osd", "ПЕРЕМИКАННЯ OSD (HUD)", -1, false))


func _build_stick_row(stick_name: String, label_txt: String, default_ch: int) -> Control:
	var elrs := get_node_or_null("/root/ElrsWifiInput")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _gap(8))
	row.custom_minimum_size.y = _fs(40)

	var lbl := _label(label_txt, 14, MenuUI.TEXT)
	lbl.custom_minimum_size.x = _fs(150)
	row.add_child(lbl)

	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(_fs(90), _fs(34))
	_style_option_button(opt)
	for i in range(16):
		opt.add_item("CH %d" % [i + 1], i)
	var cur_ch: int = int(elrs.get_stick_channel(stick_name)) if elrs != null else default_ch
	opt.selected = cur_ch
	opt.item_selected.connect(func(idx: int):
		if elrs != null:
			elrs.set_stick_channel(stick_name, idx)
	)
	_channel_options[stick_name] = opt
	row.add_child(opt)

	var auto_b := _button("АВТО", 34)
	auto_b.custom_minimum_size.x = _fs(64)
	auto_b.pressed.connect(_start_auto_detect.bind(stick_name, auto_b))
	_auto_detect_buttons[stick_name] = auto_b
	row.add_child(auto_b)

	var inv_b := _button("ІНВЕРТ", 34)
	inv_b.custom_minimum_size.x = _fs(74)
	var is_inv: bool = bool(elrs.is_stick_inverted(stick_name)) if elrs != null else false
	_update_invert_style(inv_b, is_inv)
	inv_b.pressed.connect(func():
		if elrs != null:
			var now_inv: bool = not bool(elrs.is_stick_inverted(stick_name))
			elrs.set_stick_invert(stick_name, now_inv)
			_update_invert_style(inv_b, now_inv)
	)
	_invert_buttons[stick_name] = inv_b
	row.add_child(inv_b)

	var bar := ProgressBar.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size.y = _fs(16)
	bar.min_value = -1.0 if stick_name != "throttle" else 0.0
	bar.max_value = 1.0
	bar.value = 0.0
	bar.show_percentage = false
	_style_progress_bar(bar)
	_channel_bars[stick_name] = bar
	row.add_child(bar)

	return row


func _build_switch_row(action_name: String, label_txt: String, default_ch: int, is_arm: bool) -> Control:
	var elrs := get_node_or_null("/root/ElrsWifiInput")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _gap(8))
	row.custom_minimum_size.y = _fs(40)

	var lbl := _label(label_txt, 13, MenuUI.TEXT)
	lbl.custom_minimum_size.x = _fs(210)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(_fs(124), _fs(34))
	_style_option_button(opt)
	opt.add_item("ВИМК. (-)", -1)
	for i in range(16):
		var tag := " (AUX%d)" % [i - 3] if i >= 4 else ""
		opt.add_item("CH %d%s" % [i + 1, tag], i)
	var cur_ch: int = int(elrs.get_action_channel(action_name)) if elrs != null else default_ch
	if cur_ch >= 0 and cur_ch < 16:
		for item_idx in range(opt.item_count):
			if opt.get_item_id(item_idx) == cur_ch:
				opt.selected = item_idx
				break
	else:
		opt.selected = 0
	opt.item_selected.connect(func(idx: int):
		if elrs != null:
			var target_ch: int = opt.get_item_id(idx)
			elrs.set_action_channel(action_name, target_ch)
	)
	_action_options[action_name] = opt
	row.add_child(opt)

	var auto_b := _button("АВТО", 34)
	auto_b.custom_minimum_size.x = _fs(64)
	auto_b.pressed.connect(_start_auto_detect.bind(action_name, auto_b))
	_auto_detect_buttons[action_name] = auto_b
	row.add_child(auto_b)

	if is_arm:
		_arm_status_panel = _panel(Color(0.04, 0.08, 0.06), Color(0.3, 0.4, 0.3), 1, 8)
		_arm_status_panel.custom_minimum_size = Vector2(_fs(110), _fs(34))
		_arm_status_label = _label("ДИЗАРМ", 11, MenuUI.MUTED)
		_arm_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_arm_status_panel.add_child(_arm_status_label)
		row.add_child(_arm_status_panel)
	else:
		var st_panel := _panel(Color(0.04, 0.08, 0.06), Color(0.22, 0.32, 0.26), 1, 6)
		st_panel.custom_minimum_size = Vector2(_fs(56), _fs(34))
		var st_lbl := _label("OFF", 11, MenuUI.MUTED)
		st_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		st_panel.add_child(st_lbl)
		row.add_child(st_panel)
		_switch_status_labels[action_name] = st_lbl

	return row


func _update_invert_style(btn: Button, is_inv: bool) -> void:
	if is_inv:
		btn.add_theme_color_override("font_color", Color(0.95, 0.85, 0.2))
	else:
		btn.add_theme_color_override("font_color", MenuUI.MUTED)


func _start_auto_detect(target: String, btn: Button) -> void:
	var elrs := get_node_or_null("/root/ElrsWifiInput")
	if elrs == null or not bool(elrs.get("valid")):
		if _calib_hint != null:
			_calib_hint.text = "Підключіть ELRS Wi-Fi перед призначенням!"
		return
	_auto_target = target
	btn.text = "РУХ..."
	btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	elrs.capture_baseline()


func _process_controls_screen() -> void:
	var elrs := get_node_or_null("/root/ElrsWifiInput")
	if elrs == null:
		return

	# Handle Auto-Detect movement
	if not _auto_target.is_empty() and bool(elrs.get("valid")):
		var moved_ch: int = int(elrs.detect_moved_channel(3800.0))
		if moved_ch >= 0:
			if _auto_target in ["roll", "pitch", "throttle", "yaw"]:
				elrs.set_stick_channel(_auto_target, moved_ch)
				if _channel_options.has(_auto_target):
					_channel_options[_auto_target].selected = moved_ch
			else:
				elrs.set_action_channel(_auto_target, moved_ch)
				if _action_options.has(_auto_target):
					var opt: OptionButton = _action_options[_auto_target]
					for item_idx in range(opt.item_count):
						if opt.get_item_id(item_idx) == moved_ch:
							opt.selected = item_idx
							break
			if _auto_detect_buttons.has(_auto_target):
				var b: Button = _auto_detect_buttons[_auto_target]
				b.text = "АВТО"
				b.add_theme_color_override("font_color", MenuUI.TEXT)
			_auto_target = ""

	# Update ARM Status Badge in real-time
	if _arm_status_label != null:
		var arm_ch := int(elrs.get_action_channel("arm"))
		if arm_ch >= 0 and arm_ch < elrs.channels.size():
			var is_armed: bool = _switch_level(float(elrs.channels[arm_ch]), _arm_status_label.text.begins_with("АРМОВАНО"))
			if is_armed:
				_arm_status_label.text = "АРМОВАНО ✓"
				_arm_status_label.add_theme_color_override("font_color", MenuUI.FPV_GREEN)
			else:
				_arm_status_label.text = "ДИЗАРМ (OFF)"
				_arm_status_label.add_theme_color_override("font_color", MenuUI.MUTED)
		else:
			_arm_status_label.text = "ВИМКНЕНО"
			_arm_status_label.add_theme_color_override("font_color", MenuUI.MUTED)

	# Update AUX Switches Live Indicator Pills
	for act in _switch_status_labels.keys():
		var ch: int = int(elrs.get_action_channel(act))
		var lbl: Label = _switch_status_labels[act]
		if ch >= 0 and ch < elrs.channels.size():
			var is_on: bool = _switch_level(float(elrs.channels[ch]), lbl.text == "ON")
			if is_on:
				lbl.text = "ON"
				lbl.add_theme_color_override("font_color", MenuUI.FPV_GREEN)
			else:
				lbl.text = "OFF"
				lbl.add_theme_color_override("font_color", MenuUI.MUTED)
		else:
			lbl.text = "-"
			lbl.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))

	# Update Live Signal Bars
	for key in _channel_bars.keys():
		var b: ProgressBar = _channel_bars[key]
		match key:
			"roll": b.value = elrs.roll()
			"pitch": b.value = elrs.pitch()
			"throttle": b.value = elrs.throttle()
			"yaw": b.value = elrs.yaw()

	# Live Calibration recording in Step 1.  Samples are taken in the SAME space the
	# flight code calibrates (after inversion/deadband), otherwise inverted axes
	# would be calibrated backwards.
	if _calib_step == 1 and bool(elrs.get("valid")):
		for stick_name in ["roll", "pitch", "throttle", "yaw"]:
			var norm := _calib_sample(elrs, stick_name)
			_calib_mins[stick_name] = minf(float(_calib_mins.get(stick_name, norm)), norm)
			_calib_maxs[stick_name] = maxf(float(_calib_maxs.get(stick_name, norm)), norm)


func _switch_level(raw: float, prev_on: bool) -> bool:
	# Same hysteresis as ElrsWifiInput so the menu badge matches real behaviour.
	if raw > 18000.0:
		return true
	if raw < 14000.0:
		return false
	return prev_on


func _calib_sample(elrs: Node, stick_name: String) -> float:
	match stick_name:
		"roll": return float(elrs.roll())
		"pitch": return float(elrs.pitch())
		"yaw": return float(elrs.yaw())
		"throttle": return float(elrs.throttle()) * 2.0 - 1.0
	return 0.0


func _on_calibrate_pressed() -> void:
	var elrs := get_node_or_null("/root/ElrsWifiInput")
	var mobile := get_node_or_null("/root/MobileInput")
	var elrs_valid: bool = elrs != null and bool(elrs.get("valid"))
	var joy_valid: bool = Controls.active_device >= 0 or Input.get_connected_joypads().size() > 0
	if not elrs_valid and not joy_valid and not DisplayServer.is_touchscreen_available():
		_calib_step = 0
		_calib_btn.text = "КАЛІБРУВАТИ СТІКИ"
		if _calib_hint != null:
			_calib_hint.text = "Підключіть пульт (Bluetooth, USB або ELRS Wi-Fi), щоб відкалібрувати стіки!"
		return
	if _calib_step == 0:
		_calib_step = 1
		_calib_mins.clear()
		_calib_maxs.clear()
		_calib_btn.text = "ДАЛІ: ВІДПУСТІТЬ СТІКИ"
		if _calib_hint != null:
			_calib_hint.text = "КРОК 1: Покрутіть обидва стіки пульта до крайніх положень по колу!"
	elif _calib_step == 1:
		_calib_step = 2
		_calib_btn.text = "ГОТОВО: ЗБЕРЕГТИ"
		if _calib_hint != null:
			_calib_hint.text = "КРОК 2: Відпустіть стіки по центру (газ у нуль) і натисніть Зберегти."
	elif _calib_step == 2:
		var saved := 0
		var failed: Array[String] = []
		if mobile != null:
			for stick_name in ["roll", "pitch", "throttle", "yaw"]:
				var center := _calib_sample(elrs, stick_name)
				var lo: float = float(_calib_mins.get(stick_name, -1.0))
				var hi: float = float(_calib_maxs.get(stick_name, 1.0))
				if absf(hi - lo) < 0.20:
					failed.append(stick_name)
					continue
				mobile.call("set_calibration", "elrs", stick_name, lo, hi, center)
				saved += 1
			if saved > 0:
				mobile.call("save_calibration")
				if elrs_valid and elrs.has_method("save_settings"):
					elrs.save_settings()
		if joy_valid:
			for stick_name in ["roll", "pitch", "throttle", "yaw"]:
				var b: Dictionary = Controls.stick_bindings.get(stick_name, {})
				if not b.is_empty():
					var axis: int = int(b["axis"])
					var lo: float = float(_calib_mins.get(stick_name, -1.0))
					var hi: float = float(_calib_maxs.get(stick_name, 1.0))
					var center := _calib_sample(elrs, stick_name)
					Controls.apply_stick_calibrated(stick_name, axis, lo, hi, center)
					saved += 1
			Controls.save_bindings()
		_calib_step = 0
		_calib_btn.text = "КАЛІБРУВАТИ СТІКИ"
		if _calib_hint != null:
			if failed.is_empty() and saved > 0:
				_calib_hint.text = "Калібрування збережено! Діапазони та центри оновлено."
			elif saved > 0:
				_calib_hint.text = "Збережено. Не рухались: %s." % ", ".join(failed)
			else:
				_calib_hint.text = "Калібрування завершено та збережено для активного пульта."


# ---------------------------------------------------------------- RATES SCREEN
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
		_rate_profiles["radio"] = {"rate_roll": 667, "rate_pitch": 667, "rate_yaw": 667, "expo_roll": 0.2, "expo_pitch": 0.2, "expo_yaw": 0.2}
	if not _rate_profiles.has("touch"):
		_rate_profiles["touch"] = {"rate_roll": 500, "rate_pitch": 500, "rate_yaw": 500, "expo_roll": 0.3, "expo_pitch": 0.3, "expo_yaw": 0.3}


func _build_rates() -> void:
	var screen := _make_screen("rates")
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", _gap(12))
	screen.add_child(v)

	v.add_child(_label("РЕЙТИ ТА ЕКСПОНЕНТА (BETAFLIGHT)", 32, MenuUI.TEXT))

	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", _gap(16))
	v.add_child(cols)

	var left_card := _panel(Color(0.025, 0.065, 0.05, 0.92), Color(0.38, 0.54, 0.42, 0.55), 1, 16)
	left_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left_card)

	var left_v := VBoxContainer.new()
	left_v.add_theme_constant_override("separation", _gap(10))
	left_card.add_child(left_v)
	left_v.add_child(_label("КРИВА ВІДГУКУ СТІКІВ", 16, MenuUI.FPV_AMBER))

	_rate_curve = RateCurve.new()
	_rate_curve.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rate_curve.set_profile(_rate_profiles.get(_rate_tab, {}))
	left_v.add_child(_rate_curve)

	var right_card := _panel(Color(0.025, 0.065, 0.05, 0.92), Color(0.38, 0.54, 0.42, 0.55), 1, 16)
	right_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right_card)

	var right_v := VBoxContainer.new()
	right_v.add_theme_constant_override("separation", _gap(10))
	right_card.add_child(right_v)

	var axis_controls := {}
	for axis in RATE_AXES:
		var ax_box := VBoxContainer.new()
		ax_box.add_theme_constant_override("separation", _gap(2))
		right_v.add_child(ax_box)

		var a_key: String = str(axis["key"])
		var a_name: String = str(axis["name"])
		var cur_rate: float = float(_rate_profiles[_rate_tab].get("rate_" + a_key, 667))
		var rate_lbl := _label("%s RATE: %d deg/s" % [a_name, int(cur_rate)], 13, axis["col"] as Color)
		ax_box.add_child(rate_lbl)
		var rate_slider := _slider(cur_rate, 200, 1000, 10, func(val: float):
			rate_lbl.text = "%s RATE: %d deg/s" % [a_name, int(val)]
			_rate_profiles[_rate_tab]["rate_" + a_key] = val
			_rate_curve.set_profile(_rate_profiles[_rate_tab])
		)
		ax_box.add_child(rate_slider)

		var cur_expo: float = float(_rate_profiles[_rate_tab].get("expo_" + a_key, 0.2))
		var expo_lbl := _label("%s EXPO: %.2f" % [a_name, cur_expo], 12, MenuUI.MUTED)
		ax_box.add_child(expo_lbl)
		var expo_slider := _slider(cur_expo, 0.0, 0.8, 0.05, func(val: float):
			expo_lbl.text = "%s EXPO: %.2f" % [a_name, val]
			_rate_profiles[_rate_tab]["expo_" + a_key] = val
			_rate_curve.set_profile(_rate_profiles[_rate_tab])
		)
		ax_box.add_child(expo_slider)
		axis_controls[a_key] = {
			"rate_lbl": rate_lbl, "rate_slider": rate_slider,
			"expo_lbl": expo_lbl, "expo_slider": expo_slider,
			"name": a_name
		}

	right_v.add_child(_spacer(_gap(8)))
	right_v.add_child(_label("ГОТОВІ ПРЕСЕТИ РЕЙТІВ", 13, MenuUI.FPV_AMBER))

	var preset_row := HBoxContainer.new()
	preset_row.add_theme_constant_override("separation", _gap(6))
	right_v.add_child(preset_row)

	var presets: Array[Dictionary] = [
		{"name": "🎓 ТРЕНУВАННЯ", "rate": 450.0, "expo": 0.30},
		{"name": "⚡ ФРІСТАЙЛ", "rate": 667.0, "expo": 0.20},
		{"name": "🏁 ГОНКИ", "rate": 850.0, "expo": 0.15},
		{"name": "🎬 КІНОДРОН", "rate": 350.0, "expo": 0.40},
	]
	for p_info in presets:
		var p_btn := _button(str(p_info["name"]), 38)
		p_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var r_val: float = float(p_info["rate"])
		var e_val: float = float(p_info["expo"])
		p_btn.pressed.connect(func():
			for a_key in axis_controls:
				_rate_profiles[_rate_tab]["rate_" + a_key] = r_val
				_rate_profiles[_rate_tab]["expo_" + a_key] = e_val
				var ctrl: Dictionary = axis_controls[a_key]
				var r_lbl: Label = ctrl["rate_lbl"]
				var r_s: Slider = ctrl["rate_slider"]
				var e_lbl: Label = ctrl["expo_lbl"]
				var e_s: Slider = ctrl["expo_slider"]
				r_lbl.text = "%s RATE: %d deg/s" % [ctrl["name"], int(r_val)]
				r_s.value = r_val
				e_lbl.text = "%s EXPO: %.2f" % [ctrl["name"], e_val]
				e_s.value = e_val
			_rate_curve.set_profile(_rate_profiles[_rate_tab])
		)
		preset_row.add_child(p_btn)

	right_v.add_child(_spacer(_gap(4)))
	var save_rates_btn := _button("✓  ЗБЕРЕГТИ РЕЙТИ ДЛЯ ПОЛЬОТУ", 44, true)
	save_rates_btn.pressed.connect(func():
		var gs := get_node_or_null("/root/GameSettings")
		if gs != null:
			var hud: Dictionary = gs.get("hud_config")
			hud["mobile_rate_profiles"] = _rate_profiles.duplicate(true)
			gs.save_config()
		save_rates_btn.text = "✓  ЗБЕРЕЖЕНО!"
	)
	right_v.add_child(save_rates_btn)


# ---------------------------------------------------------------- SORTIE SETUP (PLAY)
func _build_play() -> void:
	var screen := _make_screen("play")
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", _gap(10))
	screen.add_child(v)

	v.add_child(_label("ВИБІР ВИЛЬОТУ ТА РЕЖИМУ", 32, MenuUI.TEXT))

	# Mode tabs
	var modes_row := HBoxContainer.new()
	modes_row.add_theme_constant_override("separation", _gap(8))
	v.add_child(modes_row)

	for m in MODE_META:
		var btn := _button(str(m["name"]), 40, int(m["id"]) == _selected_mode)
		btn.pressed.connect(func():
			_selected_mode = int(m["id"])
			_update_play_modes(modes_row)
		)
		btn.set_meta("mode_id", int(m["id"]))
		modes_row.add_child(btn)

	# Map cards
	var maps_row := HBoxContainer.new()
	maps_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	maps_row.add_theme_constant_override("separation", _gap(10))
	v.add_child(maps_row)

	for mp in MAP_META:
		var card := _panel(Color(0.025, 0.065, 0.05, 0.92), Color(0.38, 0.54, 0.42, 0.55), 1, 14)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		maps_row.add_child(card)

		var card_v := VBoxContainer.new()
		card_v.add_theme_constant_override("separation", _gap(6))
		card.add_child(card_v)

		var map_img_path: String = "res://Assets/Branding/mobile_map_%s.png" % str(mp["id"])
		var map_tex: Texture2D = _safe_texture(map_img_path)
		if map_tex != null:
			var img_rect := TextureRect.new()
			img_rect.texture = map_tex
			img_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			img_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			img_rect.custom_minimum_size.y = _fs(120)
			img_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
			card_v.add_child(img_rect)

		var name_lbl := _label(str(mp["name"]), 22, MenuUI.TEXT)
		card_v.add_child(name_lbl)
		var tag_lbl := _label(str(mp["tag"]), 11, MenuUI.FPV_AMBER)
		card_v.add_child(tag_lbl)
		var diff_lbl := _label("СКЛАДНІСТЬ: " + str(mp.get("diff", "СЕРЕДНЯ")), 11, MenuUI.MUTED)
		card_v.add_child(diff_lbl)

		var sel_btn := _button("ОБРАТИ", 38, str(mp["id"]) == _selected_map)
		sel_btn.pressed.connect(func():
			_selected_map = str(mp["id"])
			_update_map_cards(maps_row)
		)
		sel_btn.set_meta("map_id", str(mp["id"]))
		card_v.add_child(sel_btn)

	# Centered Bottom Bar (Finger-friendly Launch Button at Bottom Center)
	var bottom_center := VBoxContainer.new()
	bottom_center.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_center.add_theme_constant_override("separation", _gap(6))
	v.add_child(bottom_center)

	_play_caption = _label("ОБРАНО: СЕЛО · БОЙОВИЙ · ДРОН: %s" % DroneCatalog.preset(Global.drone_preset)["name"], 14, MenuUI.MUTED)
	_play_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom_center.add_child(_play_caption)

	var start_mission_btn := _button("ПОЧАТИ ВИЛЬОТ", 56, true)
	start_mission_btn.custom_minimum_size = Vector2(_fs(380), _fs(56))
	start_mission_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start_mission_btn.pressed.connect(_launch)
	bottom_center.add_child(start_mission_btn)


func _update_play_modes(row: HBoxContainer) -> void:
	for c in row.get_children():
		if c is Button:
			var mid := int(c.get_meta("mode_id", -1))
			c.modulate = Color(1, 1, 1, 1.0 if mid == _selected_mode else 0.7)


func _update_map_cards(row: HBoxContainer) -> void:
	for c in row.get_children():
		for b in c.find_children("*", "Button"):
			var mid := str(b.get_meta("map_id", ""))
			b.text = "ОБРАНО ✓" if mid == _selected_map else "ОБРАТИ"


func _launch() -> void:
	Global.play_mode = _selected_mode
	if _selected_mode == Global.PlayMode.COMBAT:
		Global.combat_mission = _selected_mission
		Global.special_mission = 0
	Global.menu_settings["selected_map"] = _selected_map
	Global.menu_settings["selected_mode"] = _selected_mode
	Global.menu_settings["selected_mission"] = _selected_mission
	Global.menu_settings["drone_preset"] = Global.drone_preset
	Global.save_menu_settings()
	var scenes := {
		"steppe": "res://sceneries/SteppeLevel.tscn",
		"village": "res://sceneries/VillageLevel.tscn",
		"industrial": "res://sceneries/IndustrialLevel.tscn",
		"wetlands": "res://sceneries/WetlandsLevel.tscn",
	}
	var path: String = scenes.get(_selected_map, "res://sceneries/VillageLevel.tscn")
	get_tree().change_scene_to_file(path)


# ---------------------------------------------------------------- HANGAR / DRONE SHOWROOM
func _build_drone() -> void:
	var screen := _make_screen("drone")
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", _gap(8))
	screen.add_child(v)

	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", _gap(12))
	v.add_child(hdr)

	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", _gap(2))
	hdr.add_child(title_box)
	title_box.add_child(_label("АНГАР ДРОНІВ", 32, MenuUI.TEXT))
	title_box.add_child(_label("Оберіть борт для бойових завдань та тренувань", 13, MenuUI.MUTED))

	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", _gap(12))
	v.add_child(cols)

	# --- Left Column: 13 Drones Scrollable List ---
	var list_card := _panel(Color(0.025, 0.065, 0.05, 0.92), Color(0.38, 0.54, 0.42, 0.55), 1, 14)
	list_card.custom_minimum_size.x = _fs(340)
	cols.add_child(list_card)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	list_card.add_child(scroll)

	_hangar_list_container = VBoxContainer.new()
	_hangar_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hangar_list_container.add_theme_constant_override("separation", _gap(6))
	scroll.add_child(_hangar_list_container)

	_hangar_preview_idx = Global.drone_preset

	for i in range(DroneCatalog.count()):
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, _fs(58))
		btn.focus_mode = Control.FOCUS_NONE
		btn.set_meta("drone_idx", i)

		var m := MarginContainer.new()
		m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m.add_theme_constant_override("margin_left", _fs(12))
		m.add_theme_constant_override("margin_right", _fs(10))
		m.add_theme_constant_override("margin_top", _fs(6))
		m.add_theme_constant_override("margin_bottom", _fs(6))
		btn.add_child(m)

		var bv := VBoxContainer.new()
		bv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bv.add_theme_constant_override("separation", _gap(2))
		m.add_child(bv)

		var title_lbl := Label.new()
		title_lbl.name = "TitleLabel"
		title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title_lbl.add_theme_font_size_override("font_size", _fs(15))
		bv.add_child(title_lbl)

		var tag_lbl := Label.new()
		tag_lbl.name = "TagLabel"
		tag_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag_lbl.add_theme_font_size_override("font_size", _fs(11))
		bv.add_child(tag_lbl)

		var cur_i := i
		btn.pressed.connect(func():
			_hangar_preview_idx = cur_i
			_load_hangar_model(cur_i)
			_update_hangar_list_styles()
		)
		_hangar_list_container.add_child(btn)

	_update_hangar_list_styles()

	# --- Right Column: 3D Turntable Showroom ---
	var showroom_card := _panel(Color(0.025, 0.065, 0.05, 0.92), Color(0.38, 0.54, 0.42, 0.55), 1, 16)
	showroom_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(showroom_card)

	_hangar_container = SubViewportContainer.new()
	_hangar_container.stretch = true
	_hangar_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hangar_container.mouse_filter = Control.MOUSE_FILTER_PASS
	_hangar_container.gui_input.connect(_on_hangar_gui_input)
	showroom_card.add_child(_hangar_container)

	_hangar_viewport = SubViewport.new()
	_hangar_viewport.own_world_3d = true
	_hangar_viewport.transparent_bg = true
	_hangar_viewport.msaa_3d = Viewport.MSAA_2X
	_hangar_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	_hangar_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_hangar_viewport.size = Vector2i(1280, 720)
	_hangar_container.add_child(_hangar_viewport)

	_setup_hangar_3d_world()

	# Overlay UI on top of 3D Showroom
	var overlay := MarginContainer.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		overlay.add_theme_constant_override("margin_%s" % side, _gap(16))
	showroom_card.add_child(overlay)

	var ov_box := VBoxContainer.new()
	ov_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ov_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(ov_box)

	# Top Specs Overlay
	var info_panel := _panel(Color(0.02, 0.05, 0.04, 0.80), Color(0.3, 0.45, 0.35, 0.5), 1, 10)
	info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov_box.add_child(info_panel)

	var info_v := VBoxContainer.new()
	info_v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_v.add_theme_constant_override("separation", _gap(2))
	info_panel.add_child(info_v)

	_hangar_drone_name = _label("«ГОЛКА»", 28, MenuUI.TEXT)
	info_v.add_child(_hangar_drone_name)
	_hangar_drone_tag = _label("ФРІСТАЙЛ 5\" • КЛАС: 4S", 13, MenuUI.FPV_AMBER)
	info_v.add_child(_hangar_drone_tag)
	_hangar_specs_lbl = _label("МАСА: 600 г • TWR: 8.5:1 • МОТОРИ: 2500 KV", 12, MenuUI.MUTED)
	info_v.add_child(_hangar_specs_lbl)

	ov_box.add_child(_spacer(0, Control.SIZE_EXPAND_FILL))

	# Centered Bottom Selection Bar
	var sel_bar := HBoxContainer.new()
	sel_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	sel_bar.add_theme_constant_override("separation", _gap(12))
	ov_box.add_child(sel_bar)

	_hangar_select_btn = _button("ОБРАТИ ЦЕЙ ДРОН", 52, true)
	_hangar_select_btn.custom_minimum_size = Vector2(_fs(360), _fs(52))
	_hangar_select_btn.pressed.connect(_on_hangar_choose_pressed)
	sel_bar.add_child(_hangar_select_btn)

	_load_hangar_model(_hangar_preview_idx)
	_update_hangar_info(_hangar_preview_idx)


func _setup_hangar_3d_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.80, 0.75)
	env.ambient_light_energy = 1.35
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.08
	var world := WorldEnvironment.new()
	world.environment = env
	_hangar_viewport.add_child(world)

	var key := DirectionalLight3D.new()
	key.light_energy = 2.4
	key.light_color = Color(1.0, 0.96, 0.88)
	key.look_at_from_position(Vector3(2.5, 3.5, 2.8), Vector3.ZERO, Vector3.UP)
	_hangar_viewport.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.light_energy = 1.0
	fill.light_color = Color(0.65, 0.85, 0.78)
	fill.look_at_from_position(Vector3(-2.8, 1.8, -2.0), Vector3.ZERO, Vector3.UP)
	_hangar_viewport.add_child(fill)

	var ring := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.74
	cyl.bottom_radius = 0.78
	cyl.height = 0.02
	cyl.radial_segments = 48
	ring.mesh = cyl
	ring.position = Vector3(0.0, -0.1875, 0.0)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.12, 0.17, 0.15)
	ring_mat.roughness = 0.85
	ring_mat.metallic = 0.3
	ring.material_override = ring_mat
	_hangar_viewport.add_child(ring)

	var h_ring := MeshInstance3D.new()
	var h_torus := TorusMesh.new()
	h_torus.inner_radius = 0.68
	h_torus.outer_radius = 0.72
	h_torus.rings = 48
	h_torus.ring_segments = 24
	h_ring.mesh = h_torus
	h_ring.scale = Vector3(1.0, 0.04, 1.0)
	h_ring.position = Vector3(0.0, -0.1770, 0.0)
	var h_ring_mat := StandardMaterial3D.new()
	h_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	h_ring_mat.albedo_color = MenuUI.ACCENT
	h_ring.material_override = h_ring_mat
	_hangar_viewport.add_child(h_ring)

	_hangar_camera = Camera3D.new()
	_hangar_camera.fov = 38.0
	_hangar_camera.current = true
	_hangar_viewport.add_child(_hangar_camera)

	_hangar_holder = Node3D.new()
	_hangar_viewport.add_child(_hangar_holder)


func _load_hangar_model(preset_idx: int) -> void:
	if _hangar_holder == null:
		return
	for child in _hangar_holder.get_children():
		child.queue_free()
	var model: Node3D = DroneCatalog.attach_model(_hangar_holder, preset_idx)
	if model != null:
		MenuUI.fit_preview_model(model, 0.86, -0.1775)
	_fit_hangar_camera()
	_update_hangar_info(preset_idx)


func _fit_hangar_camera() -> void:
	if _hangar_holder == null or _hangar_camera == null:
		return
	var box := _combined_bounds(_hangar_holder)
	var center := box.get_center() if box.size.length() > 0.01 else Vector3.ZERO
	var fov := 36.0
	var aspect := 1.7
	if _hangar_viewport != null and _hangar_viewport.size.y > 0:
		aspect = float(_hangar_viewport.size.x) / float(_hangar_viewport.size.y)
	var half_w := maxf(box.size.x, box.size.z) * 0.5
	var vfov := deg_to_rad(fov)
	var hfov := 2.0 * atan(tan(vfov * 0.5) * aspect)
	var dist_w := half_w / maxf(tan(hfov * 0.5), 0.001)
	
	var focus_y := clampf(center.y + 0.06, 0.08, 0.42)
	var focus := Vector3(center.x, focus_y, center.z)
	var top_extent := (box.position.y + box.size.y) - focus_y
	var btm_extent := focus_y - box.position.y
	var half_h := maxf(maxf(top_extent, btm_extent), box.size.y * 0.60)
	var dist_h := half_h / maxf(tan(vfov * 0.5), 0.001)
	
	var dist := clampf(maxf(dist_w * 1.55, dist_h * 1.75), 1.20, 4.30)
	var dir := Vector3(0.48, 0.36, 0.85).normalized()
	_hangar_camera.fov = fov
	var cam_pos := focus + dir * dist
	_hangar_camera.look_at_from_position(cam_pos, focus, Vector3.UP)


func _update_hangar_info(preset_idx: int) -> void:
	var p := DroneCatalog.preset(preset_idx)
	if _hangar_drone_name != null:
		_hangar_drone_name.text = str(p.get("name", "ДРОН"))
	if _hangar_drone_tag != null:
		_hangar_drone_tag.text = str(p.get("tag", "FPV"))
	if _hangar_specs_lbl != null:
		var mass: int = int(round((float(p.get("dry", 0.4)) + float(p.get("batt", 0.2))) * 1000.0))
		var twr: float = float(p.get("twr", 5.0))
		var kv: int = int(p.get("kv", 2000))
		var tilt: int = int(p.get("cam_tilt", 25))
		_hangar_specs_lbl.text = "МАСА: %d г  •  TWR: %.1f:1  •  МОТОРИ: %d KV  •  КУТ КАМЕРИ: %d°" % [mass, twr, kv, tilt]
	if _hangar_select_btn != null:
		if preset_idx == Global.drone_preset:
			_hangar_select_btn.text = "ОБРАНО ДЛЯ ВИЛЬОТІВ"
			_hangar_select_btn.modulate = Color(0.75, 1.0, 0.75)
		else:
			_hangar_select_btn.text = "ОБРАТИ ЦЕЙ ДРОН"
			_hangar_select_btn.modulate = Color(1.0, 1.0, 1.0)


func _update_hangar_list_styles() -> void:
	if _hangar_list_container == null:
		return
	for c in _hangar_list_container.get_children():
		if c is Button:
			var idx: int = int(c.get_meta("drone_idx", -1))
			var is_sel := (idx == _hangar_preview_idx)
			var is_cur := (idx == Global.drone_preset)
			var p := DroneCatalog.preset(idx)
			var mark := "  [ ОБРАНО ✓ ]" if is_cur else ""

			var title_lbl := c.find_child("TitleLabel", true, false) as Label
			var tag_lbl := c.find_child("TagLabel", true, false) as Label

			if title_lbl != null:
				title_lbl.text = "%d. %s%s" % [idx + 1, str(p.get("name")), mark]
				if is_sel:
					title_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
				elif is_cur:
					title_lbl.add_theme_color_override("font_color", Color(0.95, 0.90, 0.55))
				else:
					title_lbl.add_theme_color_override("font_color", Color(0.90, 0.94, 0.92))

			if tag_lbl != null:
				tag_lbl.text = str(p.get("tag")).to_upper()
				if is_sel:
					tag_lbl.add_theme_color_override("font_color", Color(0.55, 0.92, 0.68))
				elif is_cur:
					tag_lbl.add_theme_color_override("font_color", Color(0.90, 0.78, 0.45))
				else:
					tag_lbl.add_theme_color_override("font_color", Color(0.65, 0.78, 0.70))

			var bg_col: Color
			var b_col: Color
			var b_w: int = 1
			if is_sel:
				bg_col = Color(0.12, 0.25, 0.18, 0.98)
				b_col = Color(0.48, 0.85, 0.60, 0.95)
				b_w = 2
			elif is_cur:
				bg_col = Color(0.06, 0.12, 0.08, 0.90)
				b_col = Color(0.88, 0.76, 0.46, 0.75)
			else:
				bg_col = Color(0.035, 0.075, 0.055, 0.85)
				b_col = Color(0.24, 0.38, 0.30, 0.60)

			c.add_theme_stylebox_override("normal", _panel_style(bg_col, b_col, b_w, 8))
			c.add_theme_stylebox_override("hover", _panel_style(bg_col.lightened(0.08), b_col.lightened(0.1), b_w, 8))
			c.add_theme_stylebox_override("pressed", _panel_style(bg_col.darkened(0.1), b_col, b_w, 8))


func _on_hangar_choose_pressed() -> void:
	Global.drone_preset = _hangar_preview_idx
	Global.menu_settings["drone_preset"] = _hangar_preview_idx
	Global.save_menu_settings()
	DroneCatalog.apply(_hangar_preview_idx)
	_load_hero_model(_hangar_preview_idx)
	_update_hangar_info(_hangar_preview_idx)
	_update_hangar_list_styles()
	if _play_caption != null:
		var map_name: String = _selected_map
		for m in MAP_META:
			if str(m["id"]) == _selected_map:
				map_name = str(m["name"])
				break
		var mode_name: String = str(MODE_META[_selected_mode]["name"]) if _selected_mode < MODE_META.size() else "БОЙОВИЙ"
		_play_caption.text = "ОБРАНО: %s · %s · ДРОН: %s" % [map_name, mode_name, DroneCatalog.preset(Global.drone_preset)["name"]]


func _on_hangar_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_is_dragging_hangar = mb.pressed
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		_is_dragging_hangar = st.pressed
	elif event is InputEventMouseMotion and _is_dragging_hangar:
		var mm := event as InputEventMouseMotion
		if _hangar_holder != null:
			_hangar_holder.rotation.y += mm.relative.x * 0.012
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if _hangar_holder != null:
			_hangar_holder.rotation.y += sd.relative.x * 0.012


# ---------------------------------------------------------------- SETTINGS SCREEN (100% PC PARITY)
func _build_settings() -> void:
	var screen := _make_screen("settings")
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", _gap(10))
	screen.add_child(v)

	v.add_child(_label("НАЛАШТУВАННЯ ТА СИМУЛЯЦІЯ", 32, MenuUI.TEXT))

	# 4 Tabs Bar
	var tabs_row := HBoxContainer.new()
	tabs_row.add_theme_constant_override("separation", _gap(8))
	v.add_child(tabs_row)

	var tab_defs := [
		{"id": "sim", "label": "СИМУЛЯЦІЯ ТА РЕБ"},
		{"id": "hud", "label": "ІНТЕРФЕЙС (HUD)"},
		{"id": "gfx", "label": "ГРАФІКА ТА FPS"},
		{"id": "sys", "label": "ЗВУК ТА СИСТЕМА"},
	]

	for td in tab_defs:
		var tab_id: String = td["id"]
		var btn := _button(td["label"], 48, tab_id == _settings_tab)
		btn.add_theme_font_size_override("font_size", _fs(20))
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(func():
			_settings_tab = tab_id
			_switch_settings_tab()
		)
		_settings_tab_buttons[tab_id] = btn
		tabs_row.add_child(btn)

	_settings_body_container = Control.new()
	_settings_body_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_settings_body_container)

	_build_settings_tab_sim()
	_build_settings_tab_hud()
	_build_settings_tab_gfx()
	_build_settings_tab_sys()

	_switch_settings_tab()


func _switch_settings_tab() -> void:
	for tab_id in _settings_panels.keys():
		var p: Control = _settings_panels[tab_id]
		p.visible = (tab_id == _settings_tab)
	for tab_id in _settings_tab_buttons.keys():
		var b: Button = _settings_tab_buttons[tab_id]
		var is_active: bool = (tab_id == _settings_tab)
		var normal_bg: Color = Color(0.72, 0.82, 0.65, 0.98) if is_active else Color(0.04, 0.08, 0.065, 0.88)
		var border: Color = Color(0.88, 0.76, 0.46, 0.9) if is_active else Color(0.32, 0.48, 0.38, 0.6)
		b.add_theme_stylebox_override("normal", _panel_style(normal_bg, border, 1, 12))
		b.add_theme_color_override("font_color", Color(0.06, 0.09, 0.07) if is_active else MenuUI.TEXT)
		b.modulate = Color(1.0, 1.0, 1.0, 1.0)


func _build_settings_tab_sim() -> void:
	var card := _panel(Color(0.025, 0.065, 0.05, 0.92), Color(0.38, 0.54, 0.42, 0.55), 1, 16)
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_body_container.add_child(card)
	_settings_panels["sim"] = card

	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", _gap(16))
	card.add_child(sv)

	sv.add_child(_label("ТРЕНАЖЕР / СИМУЛЯЦІЯ РЕАЛІЗМУ", 24, MenuUI.FPV_AMBER))
	sv.add_child(_label("Полегшення та фізика діють одразу під час польоту", 14, MenuUI.MUTED))

	var prof_row := HBoxContainer.new()
	prof_row.add_theme_constant_override("separation", _gap(12))
	prof_row.add_child(_label("Профіль реалізму:", 20, MenuUI.TEXT))

	var cur_prof: String = str(GameSettings.hud_config.get("realism_profile", GameSettings.REALISM_ARCADE))
	var arcade_btn := _button("АРКАДА (ПОЛЕГШЕНА)", 44, cur_prof == GameSettings.REALISM_ARCADE)
	arcade_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prof_row.add_child(arcade_btn)

	var combat_btn := _button("БОЙОВИЙ РЕАЛІЗМ", 44, cur_prof == GameSettings.REALISM_COMBAT)
	combat_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prof_row.add_child(combat_btn)

	arcade_btn.pressed.connect(func():
		GameSettings.apply_realism_profile(GameSettings.REALISM_ARCADE)
		arcade_btn.modulate = Color(1, 1, 1, 1)
		combat_btn.modulate = Color(1, 1, 1, 0.6)
		_refresh_sim_toggles()
	)
	combat_btn.pressed.connect(func():
		GameSettings.apply_realism_profile(GameSettings.REALISM_COMBAT)
		combat_btn.modulate = Color(1, 1, 1, 1)
		arcade_btn.modulate = Color(1, 1, 1, 0.6)
		_refresh_sim_toggles()
	)
	sv.add_child(prof_row)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", _gap(24))
	grid.add_theme_constant_override("v_separation", _gap(12))
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.add_child(grid)

	var sim_items := [
		["link_limit", "Обмеження зв'язку (дальність/рельєф)"],
		["reb_zones", "Зони РЕБ (глушіння)"],
		["wind_sim", "Імітація вітру та поривів"],
		["angle_mode", "Режим Angle (стабілізація)"],
		["acro_mode", "Режим Acro (ручний)"],
		["infinite_battery", "Нескінченна батарея (тренажер)"],
	]

	for item in sim_items:
		var key: String = item[0]
		var label_txt: String = item[1]
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var lbl := _label(label_txt, 18, MenuUI.TEXT)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)

		var cur_val: bool = bool(GameSettings.hud_config.get(key, true))
		var sw := ToggleSwitch.new(cur_val)
		sw.toggled.connect(func(on: bool):
			GameSettings.hud_config[key] = on
			GameSettings.save_hud_config()
		)
		_sim_toggles[key] = sw
		row.add_child(sw)
		grid.add_child(row)


func _refresh_sim_toggles() -> void:
	for key in _sim_toggles.keys():
		var sw: ToggleSwitch = _sim_toggles[key]
		sw.set_pressed_no_signal(bool(GameSettings.hud_config.get(key, true)))
		sw.queue_redraw()


func _build_settings_tab_hud() -> void:
	var card := _panel(Color(0.025, 0.065, 0.05, 0.92), Color(0.38, 0.54, 0.42, 0.55), 1, 16)
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_body_container.add_child(card)
	_settings_panels["hud"] = card

	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", _gap(14))
	card.add_child(sv)

	sv.add_child(_label("ЕЛЕМЕНТИ БОЙОВОГО ТА ПОЛЬОТНОГО ІНТЕРФЕЙСУ (HUD / OSD)", 24, MenuUI.FPV_AMBER))

	# FPS Counter row (Toggle + Slider 5..60 + Number)
	var fps_row := HBoxContainer.new()
	fps_row.add_theme_constant_override("separation", _gap(12))
	var fps_lbl := _label("Лічильник FPS:", 18, MenuUI.TEXT)
	fps_row.add_child(fps_lbl)

	var is_fps_on: bool = int(GameSettings.hud_config.get("fps", 0)) > 0
	var fps_sw := ToggleSwitch.new(is_fps_on)
	fps_row.add_child(fps_sw)

	var cur_fps_rate: int = maxi(5, int(GameSettings.hud_config.get("fps", 20)))
	_fps_label_hud = _label("%d" % cur_fps_rate, 18, MenuUI.FPV_GREEN)
	_fps_label_hud.custom_minimum_size.x = _fs(40)

	_fps_slider_hud = _slider(cur_fps_rate, 5, 60, 1, func(val: float):
		if _fps_label_hud != null:
			_fps_label_hud.text = "%d" % int(val)
		if int(GameSettings.hud_config.get("fps", 0)) > 0:
			GameSettings.hud_config["fps"] = int(val)
			GameSettings.save_hud_config()
	)
	_fps_slider_hud.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fps_row.add_child(_fps_slider_hud)
	fps_row.add_child(_fps_label_hud)
	sv.add_child(fps_row)

	fps_sw.toggled.connect(func(on: bool):
		if on:
			var target_val: int = int(_fps_slider_hud.value) if _fps_slider_hud != null else 20
			GameSettings.hud_config["fps"] = maxi(5, target_val)
		else:
			GameSettings.hud_config["fps"] = 0
		GameSettings.save_hud_config()
	)

	# 9 HUD toggles in 2 columns
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", _gap(24))
	grid.add_theme_constant_override("v_separation", _gap(10))
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.add_child(grid)

	var hud_items := [
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

	for item in hud_items:
		var key: String = item[0]
		var label_txt: String = item[1]
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var lbl := _label(label_txt, 18, MenuUI.TEXT)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)

		var cur_val: bool = bool(GameSettings.hud_config.get(key, true))
		var sw := ToggleSwitch.new(cur_val)
		sw.toggled.connect(func(on: bool):
			GameSettings.hud_config[key] = on
			GameSettings.save_hud_config()
		)
		_hud_toggles[key] = sw
		row.add_child(sw)
		grid.add_child(row)

	sv.add_child(_spacer(0, Control.SIZE_EXPAND_FILL))

	var reset_hud_btn := _button("СКИНУТИ HUD ДО СТАНДАРТНИХ", 44)
	reset_hud_btn.custom_minimum_size.x = _fs(280)
	reset_hud_btn.pressed.connect(func():
		GameSettings.reset_hud_to_defaults()
		for k in _hud_toggles.keys():
			var sw: ToggleSwitch = _hud_toggles[k]
			sw.set_pressed_no_signal(bool(GameSettings.hud_config.get(k, true)))
			sw.queue_redraw()
	)
	sv.add_child(reset_hud_btn)


func _build_settings_tab_gfx() -> void:
	var card := _panel(Color(0.025, 0.065, 0.05, 0.92), Color(0.38, 0.54, 0.42, 0.55), 1, 16)
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_body_container.add_child(card)
	_settings_panels["gfx"] = card

	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", _gap(14))
	card.add_child(sv)

	sv.add_child(_label("ГРАФІКА ТА ОПТИМІЗАЦІЯ ДЛЯ IPHONE 14", 24, MenuUI.FPV_AMBER))

	# 3 Quality Presets Row
	var q_row := HBoxContainer.new()
	q_row.add_theme_constant_override("separation", _gap(10))
	var cur_q := clampi(int(Graphics.graphics_settings.get("quality", 1)), 0, 2)
	var q_labels := ["1. НИЗЬКА (120+ FPS)", "2. СЕРЕДНЯ (БАЛАНС)", "3. ВИСОКА (МАКСИМУМ)"]
	var q_btns: Array[Button] = []
	for q_i in range(3):
		var q_btn := _button(q_labels[q_i], 44, q_i == cur_q)
		q_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var target_q := q_i
		q_btn.pressed.connect(func():
			Graphics.apply_quality_preset(target_q)
			Graphics.save_graphics_settings()
			for b_idx in range(q_btns.size()):
				q_btns[b_idx].modulate = Color(1, 1, 1, 1.0 if b_idx == target_q else 0.6)
		)
		q_row.add_child(q_btn)
		q_btns.append(q_btn)
	sv.add_child(q_row)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", _gap(24))
	grid.add_theme_constant_override("v_separation", _gap(10))
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.add_child(grid)

	# FPV video channel dropdown
	var fpv_row := HBoxContainer.new()
	fpv_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fpv_row.add_child(_label("FPV-канал (відеолінк):", 18, MenuUI.TEXT))
	var fpv_opt := OptionButton.new()
	fpv_opt.custom_minimum_size = Vector2(_fs(190), _fs(40))
	_style_option_button(fpv_opt)
	var fpv_modes := ["Аналог 5.8 GHz", "Digital O3 / Avatar", "FLIR White-Hot", "FLIR Black-Hot"]
	for item in fpv_modes:
		fpv_opt.add_item(item)
	fpv_opt.selected = clampi(int(Graphics.graphics_settings.get("fpv_video_mode", 0)), 0, 3)
	fpv_opt.item_selected.connect(func(idx: int):
		Graphics.set_fpv_video_mode(idx)
	)
	fpv_row.add_child(fpv_opt)
	grid.add_child(fpv_row)

	# Resolution scale dropdown
	var res_row := HBoxContainer.new()
	res_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	res_row.add_child(_label("Масштаб роздільності:", 18, MenuUI.TEXT))
	var res_opt := OptionButton.new()
	res_opt.custom_minimum_size = Vector2(_fs(160), _fs(40))
	_style_option_button(res_opt)
	var res_vals := [100, 85, 75, 50]
	var res_items := ["100%", "85%", "75%", "50%"]
	for item in res_items:
		res_opt.add_item(item)
	var cur_res: int = int(Graphics.graphics_settings.get("resolution", 100))
	var sel_res_idx: int = res_vals.find(cur_res)
	res_opt.selected = sel_res_idx if sel_res_idx >= 0 else 0
	res_opt.item_selected.connect(func(idx: int):
		Graphics.graphics_settings["resolution"] = res_vals[idx]
		Graphics.update_resolution()
		Graphics.save_graphics_settings()
	)
	res_row.add_child(res_opt)
	grid.add_child(res_row)

	# Shadows quality
	var sh_row := HBoxContainer.new()
	sh_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sh_row.add_child(_label("Якість тіней:", 18, MenuUI.TEXT))
	var sh_opt := OptionButton.new()
	sh_opt.custom_minimum_size = Vector2(_fs(160), _fs(40))
	_style_option_button(sh_opt)
	var sh_items := ["Вимкнено", "Низька", "Середня", "Висока", "Ультра"]
	for item in sh_items:
		sh_opt.add_item(item)
	sh_opt.selected = clampi(int(Graphics.graphics_settings.get("shadows", 2)), 0, 4)
	sh_opt.item_selected.connect(func(idx: int):
		Graphics.graphics_settings["shadows"] = idx
		Graphics.update_shadows()
		Graphics.save_graphics_settings()
	)
	sh_row.add_child(sh_opt)
	grid.add_child(sh_row)

	# MSAA
	var msaa_row := HBoxContainer.new()
	msaa_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	msaa_row.add_child(_label("Згладжування (MSAA):", 18, MenuUI.TEXT))
	var msaa_opt := OptionButton.new()
	msaa_opt.custom_minimum_size = Vector2(_fs(160), _fs(40))
	_style_option_button(msaa_opt)
	var msaa_items := ["Вимкнено", "2x", "4x", "8x", "16x"]
	for item in msaa_items:
		msaa_opt.add_item(item)
	msaa_opt.selected = clampi(int(Graphics.graphics_settings.get("msaa", 1)), 0, 4)
	msaa_opt.item_selected.connect(func(idx: int):
		Graphics.graphics_settings["msaa"] = idx
		Graphics.update_msaa()
		Graphics.save_graphics_settings()
	)
	msaa_row.add_child(msaa_opt)
	grid.add_child(msaa_row)

	# Fisheye mode
	var fish_row := HBoxContainer.new()
	fish_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fish_row.add_child(_label("FPV-об'єктив (риб'яче око):", 18, MenuUI.TEXT))
	var fish_opt := OptionButton.new()
	fish_opt.custom_minimum_size = Vector2(_fs(160), _fs(40))
	_style_option_button(fish_opt)
	var fish_items := ["Вимкнено", "Повний", "Швидкий"]
	for item in fish_items:
		fish_opt.add_item(item)
	fish_opt.selected = clampi(int(Graphics.graphics_settings.get("fisheye_mode", 0)), 0, 2)
	fish_opt.item_selected.connect(func(idx: int):
		Graphics.graphics_settings["fisheye_mode"] = idx
		Graphics.save_graphics_settings()
	)
	fish_row.add_child(fish_opt)
	grid.add_child(fish_row)

	# FPS limit
	var fps_lim_row := HBoxContainer.new()
	fps_lim_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fps_lim_row.add_child(_label("Обмеження FPS:", 18, MenuUI.TEXT))
	var fps_lim_opt := OptionButton.new()
	fps_lim_opt.custom_minimum_size = Vector2(_fs(190), _fs(40))
	_style_option_button(fps_lim_opt)
	var fps_lim_vals := [0, 30, 60, 90, 120, 144]
	var fps_lim_items := ["Без обмежень", "30", "60", "90", "120 (iPhone Pro)", "144"]
	for item in fps_lim_items:
		fps_lim_opt.add_item(item)
	var cur_fps_lim: int = int(Graphics.graphics_settings.get("fps_limit", 60))
	var fps_lim_idx: int = fps_lim_vals.find(cur_fps_lim)
	fps_lim_opt.selected = fps_lim_idx if fps_lim_idx >= 0 else 2
	fps_lim_opt.item_selected.connect(func(idx: int):
		Graphics.graphics_settings["fps_limit"] = fps_lim_vals[idx]
		Engine.max_fps = fps_lim_vals[idx]
		Graphics.save_graphics_settings()
	)
	fps_lim_row.add_child(fps_lim_opt)
	grid.add_child(fps_lim_row)

	# V-Sync toggle
	var vsync_row := HBoxContainer.new()
	vsync_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vsync_row.add_child(_label("Вертикальна синхронізація (V-Sync):", 18, MenuUI.TEXT))
	var vsync_sw := ToggleSwitch.new(bool(Graphics.graphics_settings.get("vsync", true)))
	vsync_sw.toggled.connect(func(on: bool):
		Graphics.graphics_settings["vsync"] = on
		Graphics.save_graphics_settings()
	)
	vsync_row.add_child(vsync_sw)
	grid.add_child(vsync_row)

	sv.add_child(_spacer(0, Control.SIZE_EXPAND_FILL))

	var reset_gfx_btn := _button("СКИНУТИ ГРАФІКУ ДО СТАНДАРТНИХ", 48)
	reset_gfx_btn.custom_minimum_size.x = _fs(280)
	reset_gfx_btn.pressed.connect(func():
		Graphics.reset_to_defaults()
	)
	sv.add_child(reset_gfx_btn)


func _build_settings_tab_sys() -> void:
	var card := _panel(Color(0.025, 0.065, 0.05, 0.92), Color(0.38, 0.54, 0.42, 0.55), 1, 16)
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_body_container.add_child(card)
	_settings_panels["sys"] = card

	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", _gap(20))
	card.add_child(sv)

	sv.add_child(_label("ЗВУК ТА СИСТЕМА", 24, MenuUI.FPV_AMBER))

	# 1. Master Volume
	var vol_box := VBoxContainer.new()
	vol_box.add_theme_constant_override("separation", _gap(6))
	var vol_hdr := HBoxContainer.new()
	vol_hdr.add_child(_label("Загальна гучність аудіо", 20, MenuUI.TEXT))
	var cur_vol: float = round(float(Audio.audio_settings.get("master_volume", 1.0)) * 100.0)
	var vol_lbl := _label("%d%%" % int(cur_vol), 20, MenuUI.FPV_GREEN)
	vol_lbl.custom_minimum_size.x = _fs(60)
	vol_hdr.add_child(_spacer(0, Control.SIZE_EXPAND_FILL))
	vol_hdr.add_child(vol_lbl)
	vol_box.add_child(vol_hdr)
	vol_box.add_child(_label("Регулює звук моторів FPV, свист гвинтів, вітер та ефекти детонації", 14, MenuUI.MUTED))
	
	var vol_slider := _slider(cur_vol, 0, 100, 1, func(val: float):
		vol_lbl.text = "%d%%" % int(val)
		Audio.audio_settings["master_volume"] = val / 100.0
		Audio.update_master_volume()
		Audio.save_audio_settings()
	)
	vol_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vol_box.add_child(vol_slider)
	sv.add_child(vol_box)

	# 2. Intro video audio toggle
	var vid_box := HBoxContainer.new()
	var vid_info := VBoxContainer.new()
	vid_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vid_info.add_child(_label("Звук у вступному відео", 20, MenuUI.TEXT))
	vid_info.add_child(_label("Відтворювати музичну тему та радіообмін під час старту симулятора", 14, MenuUI.MUTED))
	vid_box.add_child(vid_info)
	var is_vid_audio: bool = bool(Global.menu_settings.get("video_audio", true))
	var vid_sw := ToggleSwitch.new(is_vid_audio)
	vid_sw.toggled.connect(func(on: bool):
		Global.menu_settings["video_audio"] = on
		Global.save_menu_settings()
	)
	vid_box.add_child(vid_sw)
	sv.add_child(vid_box)

	# 3. Haptics toggle
	var hap_box := HBoxContainer.new()
	var hap_info := VBoxContainer.new()
	hap_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hap_info.add_child(_label("Тактильний відгук (Haptics / Вібрація)", 20, MenuUI.TEXT))
	hap_info.add_child(_label("Вібрація Taptic Engine iPhone при перевантаженнях, торканні землі та вибухах", 14, MenuUI.MUTED))
	hap_box.add_child(hap_info)
	var is_hap: bool = bool(Global.menu_settings.get("haptics_enabled", true))
	var hap_sw := ToggleSwitch.new(is_hap)
	hap_sw.toggled.connect(func(on: bool):
		Global.menu_settings["haptics_enabled"] = on
		Global.save_menu_settings()
	)
	hap_box.add_child(hap_sw)
	sv.add_child(hap_box)

	# 4. Safe area
	var safe_box := HBoxContainer.new()
	var safe_info := VBoxContainer.new()
	safe_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	safe_info.add_child(_label("Безпечна зона iPhone 14 (Safe Area)", 20, MenuUI.TEXT))
	safe_info.add_child(_label("Автоматичні поля від динамічного острова (Dynamic Island) та закруглень", 14, MenuUI.MUTED))
	safe_box.add_child(safe_info)
	var safe_tag := _label("АКТИВНА (+52px)", 18, MenuUI.FPV_GREEN)
	safe_box.add_child(safe_tag)
	sv.add_child(safe_box)

	# 5. Language
	var lang_box := HBoxContainer.new()
	var lang_info := VBoxContainer.new()
	lang_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lang_info.add_child(_label("Мова терміналу та бойового HUD", 20, MenuUI.TEXT))
	lang_info.add_child(_label("Повна українізація: радіообмін, параметри бортів, телеметрія OSD", 14, MenuUI.MUTED))
	lang_box.add_child(lang_info)
	var lang_lbl := _label("УКРАЇНСЬКА (UA)", 18, MenuUI.FPV_GREEN)
	lang_box.add_child(lang_lbl)
	sv.add_child(lang_box)


func _spacer(height: float, flags: int = Control.SIZE_SHRINK_CENTER) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = _fs(height)
	c.size_flags_vertical = flags
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
