## Mobile tactical menu — a phone-first shell with 3D rotating drone hero and tactical FPV controls.
##
## Features:
##   - Interactive 3D drone turntable with slow continuous rotation and finger swipe
##   - Next / Previous drone selector buttons with live name, class and TWR specs
##   - Tactical radio controller screen: 2D live stick monitor, AETR/TAER mapping,
##     per-axis inversion, level-switched ARM, AUX switches, and quick auto-detect
##   - Safe area handling for iPhone 14 (Notch / Dynamic Island & Home indicator)
##   - Self-contained navigation (pause menu and flight returns cleanly to this menu)
extends Control

const ROUNDED_SHADER: Shader = preload("res://GUI/mobile/rounded_rect.gdshader")
const DronePropellerSystem = preload("res://scripts/util/DronePropellerSystem.gd")
const GlbMaterialUtilsScript = preload("res://scripts/util/glb_material_utils.gd")
const MenuIcons = preload("res://GUI/ui/MenuIcons.gd")
const CinematicOverlay = preload("res://scripts/util/cinematic_overlay.gd")
## OptionButton id for the disabled action row.  Godot's -1 means "auto id",
## so a dedicated sentinel is required to represent "no channel".
const ACTION_DISABLED_ID := 99

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
	{"id": "steppe", "name": "СТЕП", "name_en": "STEPPE", "tag": "ВІДКРИТА МІСЦЕВІСТЬ", "tag_en": "OPEN TERRAIN", "diff": "ЛЕГКА", "diff_en": "EASY", "col": "79a58a"},
	{"id": "village", "name": "СЕЛО", "name_en": "VILLAGE", "tag": "МІСЬКА ЗАБУДОВА", "tag_en": "BUILT-UP AREA", "diff": "СЕРЕДНЯ", "diff_en": "MEDIUM", "col": "e2c276"},
	{"id": "industrial", "name": "ПРОМЗОНА", "name_en": "INDUSTRIAL ZONE", "tag": "ЗАВОДИ Й ТРУБИ", "tag_en": "FACTORY COMPLEX", "diff": "СКЛАДНА", "diff_en": "HARD", "col": "c96f67"},
	{"id": "wetlands", "name": "БОЛОТА", "name_en": "WETLANDS", "tag": "ВОДА Й ОЧЕРЕТ", "tag_en": "WATER & REEDS", "diff": "СКЛАДНА", "diff_en": "HARD", "col": "79a58a"},
]
const MODE_META := [
	{"id": 3, "name": "ТУТОРІАЛ", "name_en": "TUTORIAL"},
	{"id": 0, "name": "ТРЕНУВАННЯ", "name_en": "TRAINING"},
	{"id": 1, "name": "БОЙОВИЙ", "name_en": "COMBAT"},
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
var _hud_frame_overlay: Control = null
var _root: VBoxContainer
var _content: Control
var _masthead: HBoxContainer = null
var _chips: HBoxContainer = null
var _gc_top_btn: Button = null
var _lang_top_btn: Button = null
var _main_logo: Label = null
var _main_hero: Control = null
var _screens: Dictionary = {}
var _current := "main"
var _back_btn: Button
var _top_brand: VBoxContainer = null
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
var _hero_perf_bars: Dictionary = {}
var _is_dragging_hero := false

# --- Sortie Setup (Play) ---
var _selected_map := "village"
var _selected_mode := Global.PlayMode.TUTORIAL
var _selected_mission := 1
var _selected_special := 0
var _map_cards: Dictionary = {}
var _maps_row: HBoxContainer = null
var _mission_row: HBoxContainer = null
var _mission_bar: ScrollContainer = null
var _mission_buttons: Dictionary = {}
var _diff_bar: HBoxContainer = null
var _diff_buttons: Dictionary = {}
var _briefing_btn: Button = null
var _briefing_modal: Control = null
var _briefing_title: Label = null
var _briefing_body: Label = null
var _kropyva_panel: Control = null
var _kropyva_canvas: Control = null
var _briefing_fiber_btn: Button = null
var _briefing_flank_btn: Button = null
var _play_caption: Label
var _play_daily_lbl: Label = null
var _loading_layer: CanvasLayer = null
var _prefetch_timer: Timer = null
var _prefetch_stage := 0

# --- Tactical Controller Setup & RadioMaster TX12 ---
var _radio: Node = null
var _radio_skeleton: Skeleton3D = null
var _radio_viewport: SubViewport = null
var _radio_camera: Camera3D = null
var _stick_readout: Label = null
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
var _hangar_perf_bars: Dictionary = {}
var _hangar_select_btn: Button = null
var _hangar_preview_idx: int = 0
var _hangar_list_container: VBoxContainer = null
var _hangar_scroll: ScrollContainer = null
var _hangar_scroll_dragging := false
var _hangar_scroll_drag_dist := 0.0
var _is_dragging_hangar: bool = false
# Guards the deferred one/two-frame fit.  The imported GLB prop nodes settle
# their transforms after being added; fitting the same frame can read an
# origin-space AABB and shrink the whole drone to a speck.
var _hero_load_token := 0
var _hangar_load_token := 0

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


## 2D Stick Monitor (Tactical FPV HUD: twin circles with crosshairs and live stick positions)
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
			# value.y is pitch: -1.0 forward, +1.0 backward.
			# In 2D, -Y is UP (forward), +Y is DOWN (backward).
			norm_pos = Vector2(clampf(value.x, -1.0, 1.0), clampf(value.y, -1.0, 1.0))

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
			# Forward stick (-value.y) displays positive % forward pitch
			line1 = "ТАНГАЖ: %+d%%" % int(round(-value.y * 100.0))
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
		var plot_rect := Rect2(Vector2(left, top), Vector2(right - left, bottom - top))
		draw_rect(plot_rect, Color(0.015, 0.042, 0.030, 0.82), true)
		draw_rect(plot_rect, Color(0.36, 0.56, 0.44, 0.45), false, 1.2)
		draw_line(Vector2(left, bottom), Vector2(right, top), Color(0.45, 0.65, 0.52, 0.16), 1.0)
		var grid := Color(0.30, 0.44, 0.35, 0.22)
		for i in range(5):
			var x := left + (right - left) * i / 4.0
			draw_line(Vector2(x, top), Vector2(x, bottom), grid, 1.0)
			var y := top + (bottom - top) * i / 4.0
			draw_line(Vector2(left, y), Vector2(right, y), grid, 1.0)
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(2, top + 5), "100%", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.65, 0.75, 0.68, 0.8))
		draw_string(font, Vector2(8, bottom + 12), "0", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.65, 0.75, 0.68, 0.8))
		var stick_axis_lbl := "STICK" if MenuUI.is_english() else "СТІК"
		draw_string(font, Vector2(right - 38, bottom + 12), stick_axis_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.65, 0.75, 0.68, 0.8))
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
	# Safety net for direct MobileMenu launches: load the persisted HUD/ELRS/
	# calibration file before any row is built.  On a normal iOS boot
	# GameSettings._ready() has already done this, but the menu must not depend
	# on the autoload order.
	GameSettings.load_hud_config()
	Graphics.load_graphics_settings()
	Audio.load_audio_settings()
	Controls.load_input_map(true)
	KeyboardControls.ensure_bindings()
	Global.load_menu_settings()
	if Global.menu_settings.has("selected_map"):
		var sm := str(Global.menu_settings["selected_map"])
		if not sm.is_empty():
			_selected_map = sm
	var embedded := has_meta("embedded_pause")
	if Global.menu_settings.has("selected_mode"):
		_selected_mode = Global.sanitize_play_mode(int(Global.menu_settings["selected_mode"]))
	else:
		_selected_mode = Global.sanitize_play_mode(Global.play_mode)
	if Global.menu_settings.has("selected_mission"):
		_selected_mission = clampi(int(Global.menu_settings["selected_mission"]), 1, 4)
	if Global.menu_settings.has("selected_special"):
		_selected_special = clampi(int(Global.menu_settings["selected_special"]), 0, 9)
	if not Global.is_mission_unlocked(_selected_mission):
		_selected_mission = 1 if Global.campaign_is_complete() else Global.campaign_unlocked_mission()
	if not embedded:
		Global.play_mode = _selected_mode
		if DisplayServer.get_name() != "headless":
			Audio.play_menu_music()
	else:
		is_pause_mode = true
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
	if not get_viewport().size_changed.is_connected(_on_mobile_viewport_resized):
		get_viewport().size_changed.connect(_on_mobile_viewport_resized)
	_apply_masthead_layout()
	_update_status()
	MenuUI.localize_tree(self)
	set_process(true)
	if not embedded:
		call_deferred("_prefetch_roster")


func _prefetch_roster() -> void:
	if not is_inside_tree() or _prefetch_timer != null:
		return
	_prefetch_stage = 0
	_prefetch_timer = Timer.new()
	_prefetch_timer.one_shot = true
	_prefetch_timer.wait_time = 0.25
	_prefetch_timer.timeout.connect(_on_prefetch_timer_timeout)
	add_child(_prefetch_timer)
	_prefetch_timer.start()


func _on_prefetch_timer_timeout() -> void:
	if not is_inside_tree():
		return
	if _prefetch_stage == 0:
		_prefetch_stage = 1
		var n := DroneCatalog.count()
		if n > 0:
			var cur := posmod(Global.drone_preset, n)
			DroneCatalog.prefetch_model(posmod(cur + 1, n))
			DroneCatalog.prefetch_model(posmod(cur - 1, n))
		if _prefetch_timer != null and is_instance_valid(_prefetch_timer):
			_prefetch_timer.wait_time = 1.75
			_prefetch_timer.start()
	else:
		DroneCatalog.prefetch_all_models()
		if _prefetch_timer != null and is_instance_valid(_prefetch_timer):
			_prefetch_timer.queue_free()
			_prefetch_timer = null


func _process(delta: float) -> void:
	_update_status()
	# One background model load per frame, never on the main thread.
	DroneCatalog.poll_model_prefetch()

	# 3D Drone Hero Turntable: continuous idle rotation and propeller animation.
	# Skip it while another screen is open; the hero viewport is hidden then.
	if _hero_holder != null and _current == "main":
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

		var thr_disp: float = clampf(thr, 0.0, 1.0)
		if _stick_readout != null:
			var thr_pct := int(round(thr_disp * 100.0))
			var yaw_pct := int(round(yaw * 100.0))
			var pit_pct := int(round(-pit * 100.0))
			var rol_pct := int(round(rol * 100.0))
			_stick_readout.text = ("THROTTLE: %d%%  •  YAW: %+d%%  •  PITCH: %+d%%  •  ROLL: %+d%%" \
				if MenuUI.is_english() else "ГАЗ: %d%%  •  РИСКАННЯ: %+d%%  •  ТАНГАЖ: %+d%%  •  КРЕН: %+d%%") \
				% [thr_pct, yaw_pct, pit_pct, rol_pct]

		# RadioMaster TX12 3D stick deflections:
		# In Mode 2, Throttle ranges 0.0 (idle/bottom) to 1.0 (full/top).
		# In 3D bone space, +1.0 tilts DOWN and -1.0 tilts UP.
		var thr_3d: float = 1.0 - (thr_disp * 2.0)

		if _radio != null and is_instance_valid(_radio):
			if _radio.has_method("set_throttle_stick"):
				_radio.call("set_throttle_stick", thr_3d)
			if _radio.has_method("set_yaw_stick"):
				_radio.call("set_yaw_stick", yaw)
			if _radio.has_method("set_pitch_stick"):
				_radio.call("set_pitch_stick", pit)
			if _radio.has_method("set_roll_stick"):
				_radio.call("set_roll_stick", rol)

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
	for glb_path in [
		"res://Assets/Drones/ua_norm/rc_transmitter_rig.glb",
		"res://Assets/Drones/ua_norm/rc_transmitter.glb"
	]:
		if ResourceLoader.exists(glb_path):
			var packed = load(glb_path)
			if packed is PackedScene:
				var inst := (packed as PackedScene).instantiate() as Node3D
				if inst != null:
					return inst
		var real_p := ProjectSettings.globalize_path(glb_path)
		var check_path: String = ""
		if FileAccess.file_exists(glb_path):
			check_path = glb_path
		elif FileAccess.file_exists(real_p):
			check_path = real_p
		if not check_path.is_empty():
			var bytes := FileAccess.get_file_as_bytes(check_path)
			if bytes.size() > 0:
				var doc := GLTFDocument.new()
				var state := GLTFState.new()
				var err := doc.append_from_buffer(bytes, "", state)
				if err == OK:
					var inst := doc.generate_scene(state) as Node3D
					if inst != null:
						return inst
	return null


# ---------------------------------------------------------------- Shell & Layout
func _vsize() -> Vector2:
	return get_viewport_rect().size


func _fs(px: float) -> int:
	var scale := clampf(_vsize().y / 760.0, 1.15, 1.55)
	return maxi(16, int(round(px * scale)))


func _gap(px: float) -> int:
	var scale := clampf(_vsize().y / 850.0, 0.85, 1.35)
	return maxi(3, int(round(px * scale)))


func _ui_sz(px: float) -> int:
	var scale := clampf(_vsize().y / 760.0, 1.15, 1.50)
	return maxi(40, int(round(px * scale)))


func _label(text: String, size: float, color: Color = MenuUI.TEXT) -> Label:
	var l := Label.new()
	l.text = MenuUI.translate_text(text)
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
	if border_width > 0:
		sb.border_width_left = maxi(border_width, 4)
		sb.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
		sb.shadow_size = 10
		sb.shadow_offset = Vector2(0, 4)
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


func _chip_panel(border: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.025, 0.055, 0.045, 0.92)
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.border_width_left = 3
	sb.set_corner_radius_all(_gap(6))
	sb.content_margin_left = _gap(8)
	sb.content_margin_right = _gap(8)
	sb.content_margin_top = _gap(3)
	sb.content_margin_bottom = _gap(3)
	p.add_theme_stylebox_override("panel", sb)
	return p


func _button_style(bg: Color, border: Color, border_width: int = 1, radius: int = 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	if border_width > 0:
		sb.border_width_left = maxi(border_width, 4)
		sb.shadow_color = Color(0.0, 0.0, 0.0, 0.38)
		sb.shadow_size = 6
		sb.shadow_offset = Vector2(0, 3)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = _gap(16)
	sb.content_margin_right = _gap(16)
	sb.content_margin_top = _gap(2)
	sb.content_margin_bottom = _gap(2)
	return sb


func _button(text: String, height: float = 48.0, primary: bool = false) -> Button:
	var b := Button.new()
	var leading_spaces := ""
	for character in text:
		if character != " ":
			break
		leading_spaces += " "
	b.text = leading_spaces + MenuUI.translate_text(text.strip_edges())
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	b.focus_mode = Control.FOCUS_NONE
	var min_h: int = maxi(_ui_sz(height), _fs(46.0))
	b.custom_minimum_size = Vector2(0, min_h)
	b.add_theme_font_size_override("font_size", _fs(19 if not primary else 23))
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
	var height: float = 62.0 if not primary else 70.0
	var b := _button("  " + text, height, primary)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if icon_tex != null:
		b.icon = icon_tex
		b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.expand_icon = true
	b.add_theme_font_size_override("font_size", _fs(21 if not primary else 24))
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

	# Grade the real menu artwork once, then draw all panels on top untouched.
	var cinematic := CinematicOverlay.attach(self, 0.38, 0.014, 0.004, 0.0, 0.30)
	if cinematic != null:
		move_child(cinematic, 1)

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

	_hud_frame_overlay = Control.new()
	_hud_frame_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud_frame_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_frame_overlay.draw.connect(_on_draw_hud_frame)
	add_child(_hud_frame_overlay)


func _on_draw_hud_frame() -> void:
	if _hud_frame_overlay == null:
		return
	var sz := _hud_frame_overlay.size
	if sz.x <= 40.0 or sz.y <= 40.0:
		return
	var safe_m: Dictionary = MenuUI.get_safe_margins(sz)
	var lp := maxf(10.0, float(safe_m.get("left", 0)) * 0.5 + 8.0)
	var rp := maxf(10.0, float(safe_m.get("right", 0)) * 0.5 + 8.0)
	var tp := maxf(8.0, float(safe_m.get("top", 0)) * 0.5 + 6.0)
	var bp := maxf(8.0, float(safe_m.get("bottom", 0)) * 0.5 + 6.0)
	var tl := Vector2(lp, tp)
	var tr := Vector2(sz.x - rp, tp)
	var bl := Vector2(lp, sz.y - bp)
	var br := Vector2(sz.x - rp, sz.y - bp)
	var br_len := 26.0
	var line_col := Color(0.52, 0.86, 0.64, 0.50)
	var pip_col := Color(0.95, 0.78, 0.34, 0.85)
	# Outer subtle perimeter hairline
	_hud_frame_overlay.draw_rect(Rect2(tl, br - tl), Color(0.32, 0.54, 0.40, 0.18), false, 1.0)
	# 4 Avionics Corner L-Brackets + Amber Pips
	_hud_frame_overlay.draw_line(tl, tl + Vector2(br_len, 0), line_col, 2.2)
	_hud_frame_overlay.draw_line(tl, tl + Vector2(0, br_len), line_col, 2.2)
	_hud_frame_overlay.draw_rect(Rect2(tl - Vector2(1.5, 1.5), Vector2(4.5, 4.5)), pip_col, true)
	_hud_frame_overlay.draw_line(tr, tr + Vector2(-br_len, 0), line_col, 2.2)
	_hud_frame_overlay.draw_line(tr, tr + Vector2(0, br_len), line_col, 2.2)
	_hud_frame_overlay.draw_rect(Rect2(tr - Vector2(3.0, 1.5), Vector2(4.5, 4.5)), pip_col, true)
	_hud_frame_overlay.draw_line(bl, bl + Vector2(br_len, 0), line_col, 2.2)
	_hud_frame_overlay.draw_line(bl, bl + Vector2(0, -br_len), line_col, 2.2)
	_hud_frame_overlay.draw_rect(Rect2(bl - Vector2(1.5, 3.0), Vector2(4.5, 4.5)), pip_col, true)
	_hud_frame_overlay.draw_line(br, br + Vector2(-br_len, 0), line_col, 2.2)
	_hud_frame_overlay.draw_line(br, br + Vector2(0, -br_len), line_col, 2.2)
	_hud_frame_overlay.draw_rect(Rect2(br - Vector2(3.0, 3.0), Vector2(4.5, 4.5)), pip_col, true)
	# Top & bottom telemetry azimuth ticks
	var mid_x := sz.x * 0.5
	var tick_col := Color(0.55, 0.85, 0.65, 0.34)
	for i in range(-10, 11):
		var tx := mid_x + float(i) * 24.0
		var th := 6.0 if (i % 5 == 0) else 3.0
		_hud_frame_overlay.draw_line(Vector2(tx, tp), Vector2(tx, tp + th), tick_col, 1.2)
		_hud_frame_overlay.draw_line(Vector2(tx, sz.y - bp), Vector2(tx, sz.y - bp - th), tick_col, 1.2)


func _build_perf_bars_row(store: Dictionary) -> HBoxContainer:
	store.clear()
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", _gap(10))
	var defs := [
		{"key": "speed", "ua": "ШВИДКІСТЬ", "en": "SPEED", "col": Color(0.38, 0.90, 0.96, 0.95)},
		{"key": "thrust", "ua": "ТЯГА", "en": "THRUST", "col": Color(0.46, 0.92, 0.60, 0.95)},
		{"key": "agility", "ua": "МАНЕВР", "en": "AGILITY", "col": Color(0.96, 0.78, 0.34, 0.95)},
		{"key": "payload", "ua": "БЧ", "en": "PAYLOAD", "col": Color(0.94, 0.48, 0.40, 0.95)},
	]
	for d in defs:
		var col_box := VBoxContainer.new()
		col_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col_box.add_theme_constant_override("separation", _gap(2))
		var lbl := _label(str(d["en" if MenuUI.is_english() else "ua"]), 10, Color(0.82, 0.90, 0.85))
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col_box.add_child(lbl)
		var bar := ProgressBar.new()
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.min_value = 0.0
		bar.max_value = 100.0
		bar.value = 70.0
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(_ui_sz(68), _gap(7))
		var bg_sb := StyleBoxFlat.new()
		bg_sb.bg_color = Color(0.03, 0.07, 0.05, 0.92)
		bg_sb.border_color = Color(0.28, 0.44, 0.34, 0.65)
		bg_sb.set_border_width_all(1)
		bg_sb.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("background", bg_sb)
		var fill_sb := StyleBoxFlat.new()
		fill_sb.bg_color = d["col"] as Color
		fill_sb.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("fill", fill_sb)
		col_box.add_child(bar)
		row.add_child(col_box)
		store[str(d["key"])] = {"label": lbl, "bar": bar, "ua": str(d["ua"]), "en": str(d["en"])}
	return row


func _update_perf_bars(store: Dictionary, p: Dictionary) -> void:
	if store.is_empty():
		return
	var is_en := MenuUI.is_english()
	var kv := float(p.get("kv", 1800.0))
	var twr := float(p.get("twr", 4.5))
	var dry := float(p.get("dry", 0.45))
	var batt := float(p.get("batt", 0.25))
	var vals := {
		"speed": clampf((kv / 2600.0) * 52.0 + (twr / 9.0) * 48.0, 32.0, 98.0),
		"thrust": clampf((twr / 9.2) * 100.0, 34.0, 99.0),
		"agility": clampf((1.85 - clampf(dry, 0.15, 1.65)) / 1.70 * 100.0, 28.0, 98.0),
		"payload": clampf(((dry + batt) / 2.1) * 100.0, 26.0, 98.0),
	}
	for k in vals.keys():
		if not store.has(k):
			continue
		var item: Dictionary = store[k]
		var v_pct := int(round(float(vals[k])))
		var bar: ProgressBar = item.get("bar") as ProgressBar
		if bar != null:
			bar.value = float(v_pct)
		var lbl: Label = item.get("label") as Label
		if lbl != null:
			var t_str := str(item.get("en" if is_en else "ua", ""))
			lbl.text = "%s %d%%" % [t_str, v_pct]


func _build_root() -> void:
	var s := _vsize()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# iPhone / Notch / Dynamic Island & Home indicator Safe Area Handling
	var safe_m: Dictionary = MenuUI.get_safe_margins(s)
	var left_pad := maxi(24, int(safe_m.get("left", 0)))
	var right_pad := maxi(24, int(safe_m.get("right", 0)))
	var top_pad := maxi(12, int(safe_m.get("top", 0)))
	var bottom_pad := maxi(14, int(safe_m.get("bottom", 0)))

	margin.add_theme_constant_override("margin_left", left_pad)
	margin.add_theme_constant_override("margin_right", right_pad)
	margin.add_theme_constant_override("margin_top", top_pad)
	margin.add_theme_constant_override("margin_bottom", bottom_pad)
	add_child(margin)

	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", _gap(8))
	margin.add_child(_root)

	# Top Masthead
	_masthead = HBoxContainer.new()
	var top := _masthead
	top.custom_minimum_size.y = _fs(46)
	top.add_theme_constant_override("separation", _gap(10))
	_root.add_child(top)

	_back_btn = _button(" НАЗАД", 48)
	_back_btn.icon = MenuIcons.icon_back(MenuUI.TEXT)
	_back_btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_back_btn.add_theme_constant_override("h_separation", _gap(8))
	_back_btn.add_theme_font_size_override("font_size", _fs(19))
	_back_btn.custom_minimum_size = Vector2(_ui_sz(150), _ui_sz(46))
	_back_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_back_btn.pressed.connect(_on_back)
	_back_btn.visible = false
	top.add_child(_back_btn)

	# Left horizontal expanding spacer
	var top_spacer_left := Control.new()
	top_spacer_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_spacer_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(top_spacer_left)

	_top_brand = VBoxContainer.new()
	_top_brand.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_top_brand.alignment = BoxContainer.ALIGNMENT_CENTER
	_top_brand.add_theme_constant_override("separation", _gap(1))
	_top_brand.visible = false
	top.add_child(_top_brand)

	var logo := _label("НЕБЕСНИЙ ГОРИЗОНТ", 26, MenuUI.TEXT)
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_top_brand.add_child(logo)
	var brand_sub := _label("ТАКТИЧНИЙ FPV-СИМУЛЯТОР  •  МОБІЛЬНИЙ ТЕРМІНАЛ", 11, MenuUI.MUTED)
	brand_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_top_brand.add_child(brand_sub)

	# Right horizontal expanding spacer (guarantees chips are pinned to the top-right corner)
	var top_spacer_right := Control.new()
	top_spacer_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_spacer_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(top_spacer_right)

	_chips = HBoxContainer.new()
	var chips := _chips
	chips.alignment = BoxContainer.ALIGNMENT_END
	chips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chips.add_theme_constant_override("separation", _gap(6))
	top.add_child(chips)

	var gc_top_label := ("GC" if Global.is_game_center_available() else "RECORDS") \
			if MenuUI.is_english() else "РЕКОРДИ"
	_gc_top_btn = _button(gc_top_label, 32, false)
	var gc_top_btn := _gc_top_btn
	gc_top_btn.name = "GcTopButton"
	gc_top_btn.icon = MenuIcons.icon_trophy(MenuUI.FPV_AMBER, 20)
	gc_top_btn.expand_icon = false
	gc_top_btn.add_theme_constant_override("h_separation", _gap(6))
	gc_top_btn.custom_minimum_size = Vector2(_ui_sz(112 if MenuUI.is_english() else 124), _ui_sz(32))
	gc_top_btn.tooltip_text = Global.get_leaderboard_summary(MenuUI.is_english())
	gc_top_btn.pressed.connect(_open_mobile_records)
	chips.add_child(gc_top_btn)

	_lang_top_btn = _button("EN" if MenuUI.is_english() else "UA", 32, false)
	var lang_top_btn := _lang_top_btn
	lang_top_btn.custom_minimum_size = Vector2(_ui_sz(48), _ui_sz(32))
	lang_top_btn.pressed.connect(func():
		Loc.toggle_language()
		MenuUI.localize_tree(self)
		call_deferred("_rebuild_screens")
	)
	chips.add_child(lang_top_btn)

	_elrs_chip = _chip_panel(Color(0.40, 0.62, 0.48, 0.65))
	_elrs_label = _label("ELRS: ПОШУК", 11, MenuUI.MUTED)
	_elrs_chip.add_child(_elrs_label)
	chips.add_child(_elrs_chip)

	_input_chip = _chip_panel(Color(0.62, 0.76, 0.55, 0.65))
	_input_label = _label("ВХІД: СЕНСОР", 11, MenuUI.FPV_CYAN)
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
	if _top_brand != null:
		_top_brand.visible = (name != "main")
	_apply_masthead_layout()
	if name == "play":
		if _maps_row != null:
			_update_map_cards(_maps_row)
		_refresh_mobile_mission_strip()
	if name == "drone":
		if _hangar_preview_idx != Global.drone_preset:
			_hangar_preview_idx = Global.drone_preset
			_load_hangar_model(_hangar_preview_idx)
		_update_hangar_list_styles()
	_screen_scrim.color = Color(0.015, 0.045, 0.035, 0.10 if name == "main" else 0.22)
	_update_status()


func _on_mobile_viewport_resized() -> void:
	_apply_masthead_layout()
	if _hud_frame_overlay != null:
		_hud_frame_overlay.queue_redraw()
	if _root != null:
		_root.queue_sort()


func _apply_masthead_layout() -> void:
	if _masthead == null:
		return
	var compact := _vsize().x < 700.0
	if _main_logo != null:
		_main_logo.add_theme_font_size_override("font_size",
				_fs(24 if _vsize().x < 520.0 else 30))
	if _main_hero != null:
		# A portrait phone cannot fit the nav rail and the 3D hangar card side
		# by side; leaving the hero in the HBox produced a clipped sliver.
		_main_hero.visible = not (_vsize().x < 700.0 and _vsize().y > _vsize().x)
	if _top_brand != null:
		_top_brand.visible = not compact and _current != "main"
	if _gc_top_btn != null:
		var gc_label := ("GC" if Global.is_game_center_available() else "RECORDS") \
				if MenuUI.is_english() else "РЕКОРДИ"
		_gc_top_btn.text = "" if compact else gc_label
		_gc_top_btn.custom_minimum_size = Vector2(_ui_sz(44 if compact else (112 if MenuUI.is_english() else 124)),
				_ui_sz(32))
	if _elrs_chip != null:
		_elrs_chip.visible = not compact
	if _input_chip != null:
		_input_chip.visible = not compact
	if _back_btn != null:
		_back_btn.custom_minimum_size.x = _ui_sz(104 if compact else 150)
	if _chips != null:
		_chips.add_theme_constant_override("separation", _gap(6 if compact else 6))


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


func show_settings_tab(tab_id: String) -> void:
	show_settings()
	if _settings_tab_buttons.has(tab_id):
		_settings_tab = tab_id
		_switch_settings_tab()


func _update_status() -> void:
	if _elrs_label == null:
		return
	var elrs := get_node_or_null("/root/ElrsWifiInput")
	var valid: bool = elrs != null and bool(elrs.get("valid"))
	var status := str(elrs.get("status_text")) if elrs != null else ""
	if valid or status.find("ПОТІК") >= 0:
		_elrs_label.text = MenuUI.translate_text("ELRS: ПОТІК")
		_elrs_label.add_theme_color_override("font_color", MenuUI.FPV_GREEN)
		if _input_label != null:
			_input_label.text = MenuUI.translate_text("ВХІД: ELRS (POCKET)")
			_input_label.add_theme_color_override("font_color", MenuUI.FPV_GREEN)
	else:
		_elrs_label.text = MenuUI.translate_text(status if not status.is_empty() else "ELRS: ВИМК.")
		_elrs_label.add_theme_color_override("font_color", MenuUI.MUTED)
		if _input_label != null:
			_input_label.text = MenuUI.translate_text("ВХІД: СЕНСОР")
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
	left.add_theme_constant_override("separation", _gap(6))
	h.add_child(left)

	# Title centered exactly in the middle above the "ОДИНОЧНА ГРА" button
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.alignment = BoxContainer.ALIGNMENT_CENTER
	title_box.add_theme_constant_override("separation", _gap(2))

	var main_logo := _label("НЕБЕСНИЙ ГОРИЗОНТ", 30, MenuUI.TEXT)
	_main_logo = main_logo
	main_logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_box.add_child(main_logo)

	var main_sub := _label("ТАКТИЧНИЙ FPV-СИМУЛЯТОР", 12, MenuUI.FPV_AMBER)
	main_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_box.add_child(main_sub)

	left.add_child(title_box)
	left.add_child(_spacer(_gap(8)))

	if not Global.is_tutorial_completed():
		var quick_btn := _nav_button(MenuIcons.icon_play(Color(0.06, 0.09, 0.07)),
				"ШВИДКИЙ СТАРТ: ТУТОРІАЛ" if not MenuUI.is_english() else "QUICK START: TUTORIAL",
				true, func():
					_selected_mode = Global.PlayMode.TUTORIAL
					_selected_map = "village"
					_launch()
		)
		left.add_child(quick_btn)

	# Always-visible first-strike lesson, matching the desktop home screen.
	# It is a separate TRAINING session with one tank and three explicit steps,
	# and it never writes a campaign record.
	var ct_done := Global.is_combat_training_completed()
	var ct_text := ("✓ БОЙОВЕ ТРЕНУВАННЯ · ПОВТОРИТИ" if ct_done \
			else "БОЙОВЕ ТРЕНУВАННЯ: 3 КРОКИ") if not MenuUI.is_english() \
			else ("✓ COMBAT TRAINING · REPEAT" if ct_done \
			else "COMBAT TRAINING: 3 STEPS")
	left.add_child(_nav_button(MenuIcons.icon_trophy(MenuUI.WARN_AMBER),
			ct_text, false, func():
				_selected_mode = Global.PlayMode.TRAINING
				_selected_map = "village"
				_launch(true)
	))

	var sp_primary := Global.is_tutorial_completed()
	var sp_icon_col := Color(0.06, 0.09, 0.07) if sp_primary else Color(0.84, 0.96, 0.87)
	left.add_child(_nav_button(MenuIcons.icon_play(sp_icon_col), "ОДИНОЧНА ГРА", sp_primary, func(): _show("play")))
	left.add_child(_nav_button(MenuIcons.icon_radio(MenuUI.TEXT), "ПУЛЬТ ТА ELRS", false, func(): _show("controls")))
	left.add_child(_nav_button(MenuIcons.icon_rates(MenuUI.TEXT), "РЕЙТИ ТА ЕКСПО", false, func(): _show("rates")))
	left.add_child(_nav_button(MenuIcons.icon_hangar(MenuUI.TEXT), "АНГАР ДРОНІВ", false, func(): _show("drone")))
	left.add_child(_nav_button(MenuIcons.icon_settings(MenuUI.TEXT), "НАЛАШТУВАННЯ", false, func(): _show("settings")))

	left.add_child(_spacer(_gap(4)))

	# Tactical Changelog & Daily Challenge Card for this version
	var chg_card := _panel(Color(0.02, 0.048, 0.038, 0.92), Color(0.38, 0.54, 0.42, 0.70), 1, 12)
	chg_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var chg_m := MarginContainer.new()
	chg_m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	chg_m.add_theme_constant_override("margin_left", _gap(12))
	chg_m.add_theme_constant_override("margin_right", _gap(12))
	chg_m.add_theme_constant_override("margin_top", _gap(8))
	chg_m.add_theme_constant_override("margin_bottom", _gap(8))
	chg_card.add_child(chg_m)

	var chg_v := VBoxContainer.new()
	chg_v.add_theme_constant_override("separation", _gap(3))
	chg_m.add_child(chg_v)

	var chg_hdr := HBoxContainer.new()
	chg_hdr.add_child(_label("ОНОВЛЕННЯ // СПИСОК ЗМІН", 13, MenuUI.FPV_AMBER))
	chg_hdr.add_child(_spacer(0, Control.SIZE_EXPAND_FILL))
	chg_hdr.add_child(_label("v1.19.0", 12, MenuUI.FPV_GREEN))
	chg_v.add_child(chg_hdr)

	var dc := Global.get_daily_challenge()
	var is_en := MenuUI.is_english()
	var dc_title := str(dc.get("title_en" if is_en else "title_ua", dc.get("title_uk", "")))
	var dc_line := ("★ ВИКЛИК ДНЯ: %s (+%d)" if not is_en else "★ DAILY CHALLENGE: %s (+%d)") % [dc_title, int(dc.get("bonus_score", 500))]
	var trec := Global.get_training_record("course")
	var course_line := "• Траса тренування: пройдіть ворота на ★ / S–B (з Привидом)"
	if bool(trec.get("completed", false)):
		course_line = ("• Траса: рекорд %.1f с · %s [%s]" if not is_en else "• Course best: %.1fs · %s [%s]") % [
			float(trec.get("best_time", 0.0)), "★".repeat(int(trec.get("stars", 1))), str(trec.get("best_rank", "B"))]

	var changes := [
		dc_line,
		course_line,
		"• Режими: Туторіал (м’яка Angle) → Тренування → Бойовий",
		"• Геймпади, ELRS Wi-Fi, UA/EN та Safe Area",
	]
	for c_txt in changes:
		var cl := Label.new()
		cl.text = c_txt
		cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cl.add_theme_font_size_override("font_size", _fs(14))
		cl.add_theme_color_override("font_color", Color(0.85, 0.94, 0.88))
		chg_v.add_child(cl)

	left.add_child(chg_card)
	left.add_child(_spacer(0, Control.SIZE_EXPAND_FILL))

	# Right 3D Rotating Drone Hero
	var hero := _build_3d_hero()
	_main_hero = hero
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
	_hero_container.custom_minimum_size = Vector2(0, 0)
	_hero_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hero_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hero_container.mouse_filter = Control.MOUSE_FILTER_PASS
	_hero_container.gui_input.connect(_on_hero_gui_input)
	card.add_child(_hero_container)

	_hero_viewport = SubViewport.new()
	_hero_viewport.own_world_3d = true
	_hero_viewport.transparent_bg = true
	_hero_viewport.msaa_3d = Viewport.MSAA_2X
	# MSAA already handles the turntable edges; skip the extra full-screen
	# FXAA pass on the phone GPU.
	_hero_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	# Only render the turntable while its screen is actually visible.
	_hero_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
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

	_hero_drone_name = _label("«ГРІМ-7»", 32, MenuUI.TEXT)
	_hero_drone_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_box.add_child(_hero_drone_name)

	_hero_drone_tag = _label("УДАРНИЙ 8–10\"  •  БОЙОВИЙ БПЛА", 14, MenuUI.FPV_AMBER)
	_hero_drone_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_box.add_child(_hero_drone_tag)

	_hero_drone_specs = _label("МАСА: 1400 г  •  TWR: 3.5:1  •  1350 KV", 12, MenuUI.MUTED)
	_hero_drone_specs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_box.add_child(_hero_drone_specs)
	info_box.add_child(_build_perf_bars_row(_hero_perf_bars))

	v.add_child(_spacer(0, Control.SIZE_EXPAND_FILL))

	# Bottom Selector Bar & Play Action (Centered Launch Action)
	var bottom_selector := HBoxContainer.new()
	bottom_selector.add_theme_constant_override("separation", _gap(12))
	bottom_selector.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(bottom_selector)

	var prev_btn := _button("ПОПЕРЕДНІЙ", 46)
	prev_btn.custom_minimum_size.x = _ui_sz(150)
	prev_btn.pressed.connect(_select_prev_drone)
	bottom_selector.add_child(prev_btn)

	var play_text := "ПРОДОВЖИТИ ПОЛІТ" if is_pause_mode else "ПОЧАТИ ВИЛІТ"
	var play_btn := _button(play_text, 50, true)
	play_btn.custom_minimum_size.x = _ui_sz(260)
	play_btn.pressed.connect(func():
		if is_pause_mode:
			emit_signal("closed")
			visible = false
			is_pause_mode = false
		else:
			_show("play")
	)
	bottom_selector.add_child(play_btn)

	var next_btn := _button("НАСТУПНИЙ", 46)
	next_btn.custom_minimum_size.x = _ui_sz(150)
	next_btn.pressed.connect(_select_next_drone)
	bottom_selector.add_child(next_btn)

	_update_hero_drone_info(Global.drone_preset)
	return card


func _setup_hero_3d_world() -> void:
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
	cyl.top_radius = 0.50
	cyl.bottom_radius = 0.54
	cyl.height = 0.018
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
	torus.inner_radius = 0.44
	torus.outer_radius = 0.48
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
	_add_tactical_podium_details(_hero_viewport, -0.2045, 0.50)

	_hero_camera = Camera3D.new()
	_hero_camera.fov = 30.0
	_hero_camera.current = true
	_hero_viewport.add_child(_hero_camera)

	_hero_holder = Node3D.new()
	_hero_viewport.add_child(_hero_holder)
	_load_hero_model(Global.drone_preset)


func _load_hero_model(preset_idx: int) -> void:
	if _hero_holder == null:
		return
	_hero_load_token += 1
	var token := _hero_load_token
	var p := DroneCatalog.preset(preset_idx)
	var is_vtol: bool = str(p.get("name", "")).contains("VTOL") or str(p.get("tag", "")).contains("VTOL")
	var target_sz: float = 0.46 if is_vtol else 0.52
	_update_hero_drone_info(preset_idx)
	for child in _hero_holder.get_children():
		_hero_holder.remove_child(child)
		child.queue_free()
	await DroneCatalog.wait_for_model(preset_idx)
	if token != _hero_load_token:
		return
	var model: Node3D = DroneCatalog.attach_model(_hero_holder, preset_idx)
	if model == null:
		_fit_hero_camera()
		return
	model.set_meta("preset_idx", preset_idx)
	# Hide during the two-frame transform settle so full-scale 2m–2.8m planes
	# never flash visibly over the pedestal before fit_preview_model scales them.
	model.visible = false
	# Let the imported prop/motor children enter the tree and update their
	# global transforms before measuring the bounds.  Measuring on the same
	# frame occasionally produced an origin-space AABB and a tiny drone.
	await get_tree().process_frame
	await get_tree().process_frame
	if token != _hero_load_token or not is_instance_valid(model) \
			or model.get_parent() != _hero_holder:
		return
	MenuUI.fit_preview_model(model, target_sz, -0.205)
	_ensure_preview_scale(_hero_holder, model, target_sz, -0.205)
	_fit_hero_camera()
	model.visible = true


func _fit_hero_camera() -> void:
	if _hero_holder == null or _hero_camera == null:
		return
	var box := _combined_bounds(_hero_holder)
	var center := box.get_center() if box.size.length() > 0.01 else Vector3.ZERO
	var max_dim := maxf(box.size.x, maxf(box.size.y, box.size.z))
	var focus := Vector3(center.x, center.y + 0.025, center.z)
	_hero_camera.fov = 30.0
	var dist := clampf(max_dim * 1.55 + 0.35, 1.45, 2.05)
	var dir := Vector3(0.48, 0.28, 0.76).normalized()
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


## Keeps a preview model inside a sane size band on the card.  The old guard
## only up-scaled tiny models, so one bad AABB measurement could leave an
## oversized model clipped by the card and covering the specs text.  Clamp
## both ways (±18%) and re-seat the model on the pedestal.
func _ensure_preview_scale(holder: Node3D, model: Node3D, target: float,
		bottom: float) -> void:
	if holder == null or model == null or target <= 0.0:
		return
	var box := _combined_bounds(holder)
	var max_dim := maxf(box.size.x, maxf(box.size.y, box.size.z))
	if max_dim <= 0.0001:
		return
	var wanted := clampf(max_dim, target * 0.82, target * 1.18)
	if absf(wanted - max_dim) <= 0.001:
		return
	model.scale *= wanted / max_dim
	model.force_update_transform()
	var fitted := _combined_bounds(holder)
	model.position.y += bottom - fitted.position.y
	model.force_update_transform()


func _update_hero_drone_info(preset_idx: int) -> void:
	var p := DroneCatalog.preset(preset_idx)
	if _hero_drone_name != null:
		_hero_drone_name.text = MenuUI.translate_text(DroneCatalog.get_drone_name(preset_idx))
	if _hero_drone_tag != null:
		_hero_drone_tag.text = MenuUI.translate_text(DroneCatalog.get_drone_tag(preset_idx))
	if _hero_drone_specs != null:
		var mass := int(round((float(p.get("dry", 0.4)) + float(p.get("batt", 0.2))) * 1000.0))
		var twr := float(p.get("twr", 5.0))
		var kv := int(p.get("kv", 2000))
		if MenuUI.is_english():
			_hero_drone_specs.text = "MASS: %d g  •  TWR: %.1f:1  •  MOTORS: %d KV" % [mass, twr, kv]
		else:
			_hero_drone_specs.text = "МАСА: %d г  •  TWR: %.1f:1  •  МОТОРИ: %d KV" % [mass, twr, kv]
	_update_perf_bars(_hero_perf_bars, p)


func _select_next_drone() -> void:
	var total := DroneCatalog.count()
	var next_idx := (Global.drone_preset + 1) % total
	Global.drone_preset = next_idx
	Global.menu_settings["drone_preset"] = next_idx
	Global.save_menu_settings()
	DroneCatalog.apply(next_idx)
	DroneCatalog.prefetch_model((next_idx + 1) % total)
	DroneCatalog.prefetch_model((next_idx - 1 + total) % total)
	_load_hero_model(next_idx)


func _select_prev_drone() -> void:
	var total := DroneCatalog.count()
	var prev_idx := (Global.drone_preset - 1 + total) % total
	Global.drone_preset = prev_idx
	Global.menu_settings["drone_preset"] = prev_idx
	Global.save_menu_settings()
	DroneCatalog.apply(prev_idx)
	DroneCatalog.prefetch_model((prev_idx + 1) % total)
	DroneCatalog.prefetch_model((prev_idx - 1 + total) % total)
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


# ---------------------------------------------------------------- TACTICAL CONTROLLER SCREEN
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

	left_v.add_child(_label("RC-ПУЛЬТ (MODE 2)", 15, MenuUI.FPV_AMBER))

	# RadioMaster TX12 3D Realtime Animated Transmitter (Prominent & Centered)
	var radio_panel := _panel(Color(0.02, 0.05, 0.04, 0.85), Color(0.38, 0.54, 0.42, 0.55), 1, 10)
	radio_panel.custom_minimum_size = Vector2(0, _fs(340))
	radio_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_v.add_child(radio_panel)

	var radio_holder := SubViewportContainer.new()
	radio_holder.stretch = true
	radio_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	radio_panel.add_child(radio_holder)

	var radio_vp := SubViewport.new()
	radio_vp.own_world_3d = true
	radio_vp.transparent_bg = true
	radio_vp.handle_input_locally = false
	radio_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	radio_holder.add_child(radio_vp)

	var radio_scn = load("res://GUI/ControlsMenuRadioTransmitter.tscn")
	if radio_scn != null:
		_radio = radio_scn.instantiate()
		radio_vp.add_child(_radio)
		_radio.set("accept_input", false)

	# Clean tactical stick telemetry readout (ZERO 2D circular overlays!)
	_stick_readout = _label("ГАЗ: 0%  •  РИСКАННЯ: +0%  •  ТАНГАЖ: +0%  •  КРЕН: +0%", 14, MenuUI.FPV_CYAN)
	_stick_readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left_v.add_child(_stick_readout)

	_calib_hint = _label("Стіки мають досягати 100% у кутах та повертатися в 0%", 12, MenuUI.MUTED)
	_calib_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_calib_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_v.add_child(_calib_hint)

	_calib_btn = _button("КАЛІБРУВАТИ СТІКИ", 42, true)
	_calib_btn.pressed.connect(_on_calibrate_pressed)
	left_v.add_child(_calib_btn)

	var elrs_help_btn := _button("ДОВІДКА: ПІДКЛЮЧЕННЯ ELRS Wi-Fi", 38, false)
	elrs_help_btn.pressed.connect(_open_elrs_guide_modal)
	left_v.add_child(elrs_help_btn)

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
	row.add_theme_constant_override("separation", _gap(10))
	row.custom_minimum_size.y = _fs(48)

	var lbl := _label(label_txt, 16, MenuUI.TEXT)
	lbl.custom_minimum_size.x = _fs(180)
	row.add_child(lbl)

	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(_fs(110), _fs(44))
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

	var auto_b := _button("АВТО", 44)
	auto_b.custom_minimum_size.x = _fs(80)
	auto_b.pressed.connect(_start_auto_detect.bind(stick_name, auto_b))
	_auto_detect_buttons[stick_name] = auto_b
	row.add_child(auto_b)

	var inv_b := _button("ІНВЕРТ", 44)
	inv_b.custom_minimum_size.x = _fs(92)
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
	bar.custom_minimum_size.y = _fs(20)
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
	row.add_theme_constant_override("separation", _gap(10))
	row.custom_minimum_size.y = _fs(48)

	var lbl := _label(label_txt, 15, MenuUI.TEXT)
	lbl.custom_minimum_size.x = _fs(240)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(_fs(150), _fs(44))
	_style_option_button(opt)
	# Godot treats an explicit id of -1 as "assign automatically" (0), so use
	# a separate sentinel for the disabled row.  Otherwise "ВИМК." would pass
	# channel 0 and the guard below would refuse to disable the action.
	opt.add_item("ВИМК. (-)", ACTION_DISABLED_ID)
	# Only CH5-CH16 are AUX switches.  CH1-CH4 are the sticks: putting an
	# action there makes it fire while the pilot is only flying.
	for i in range(4, 16):
		var tag := " (AUX%d)" % [i - 3]
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
			if target_ch == ACTION_DISABLED_ID:
				target_ch = -1
			elrs.set_action_channel(action_name, target_ch)
			# A bind can move ARM to another free AUX channel; update every
			# row so the screen never shows a stale switch.
			_refresh_action_options()
	)
	_action_options[action_name] = opt
	row.add_child(opt)

	var auto_b := _button("АВТО", 44)
	auto_b.custom_minimum_size.x = _fs(80)
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


func _refresh_action_options() -> void:
	var elrs := get_node_or_null("/root/ElrsWifiInput")
	if elrs == null:
		return
	for action in _action_options.keys():
		var opt: OptionButton = _action_options[action]
		if opt == null:
			continue
		var ch := int(elrs.get_action_channel(action))
		var selected_idx := 0
		for item_idx in range(opt.item_count):
			if opt.get_item_id(item_idx) == ch:
				selected_idx = item_idx
				break
		opt.selected = selected_idx


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
		var is_aux: bool = not (_auto_target in ["roll", "pitch", "throttle", "yaw"])
		var moved_ch: int = int(elrs.detect_moved_channel(3800.0, is_aux))
		if moved_ch >= 0:
			if _auto_target in ["roll", "pitch", "throttle", "yaw"]:
				elrs.set_stick_channel(_auto_target, moved_ch)
				if _channel_options.has(_auto_target):
					_channel_options[_auto_target].selected = moved_ch
			else:
				elrs.set_action_channel(_auto_target, moved_ch)
				_refresh_action_options()
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
		save_rates_btn.text = MenuUI.translate_text("✓  ЗБЕРЕЖЕНО!")
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

	# Mode tabs (strictly: Tutorial -> Training -> Combat)
	var modes_row := HBoxContainer.new()
	modes_row.add_theme_constant_override("separation", _gap(8))
	v.add_child(modes_row)

	var is_en := MenuUI.is_english()
	for m in MODE_META:
		var m_title := str(m.get("name_en" if is_en else "name", m.get("name", "")))
		var btn := _button(m_title, 40, int(m["id"]) == _selected_mode)
		btn.pressed.connect(func():
			_selected_mode = Global.sanitize_play_mode(int(m["id"]))
			_update_play_modes(modes_row)
		)
		btn.set_meta("mode_id", int(m["id"]))
		modes_row.add_child(btn)

	var modes_spacer := Control.new()
	modes_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modes_row.add_child(modes_spacer)

	_diff_bar = HBoxContainer.new()
	_diff_bar.add_theme_constant_override("separation", _gap(5))
	_diff_bar.visible = (_selected_mode == Global.PlayMode.COMBAT)
	modes_row.add_child(_diff_bar)
	var diff_defs := [
		[Global.Difficulty.RECRUIT, "RECRUIT" if is_en else "РЕКРУТ"],
		[Global.Difficulty.OPERATOR, "OPERATOR" if is_en else "ОПЕРАТОР"],
		[Global.Difficulty.ACE, "ACE" if is_en else "АС"],
	]
	for dd in diff_defs:
		var d_id := int(dd[0])
		var db := _button(str(dd[1]), 34, Global.difficulty == d_id)
		db.custom_minimum_size = Vector2(_ui_sz(82), _fs(34))
		db.add_theme_font_size_override("font_size", _fs(13))
		db.pressed.connect(_select_mobile_difficulty.bind(d_id))
		_diff_bar.add_child(db)
		_diff_buttons[d_id] = db

	_briefing_btn = _button("BRIEFING" if is_en else "БРИФІНГ", 34, false)
	_briefing_btn.custom_minimum_size = Vector2(_ui_sz(98), _fs(34))
	_briefing_btn.add_theme_font_size_override("font_size", _fs(13))
	_briefing_btn.visible = (_selected_mode == Global.PlayMode.COMBAT)
	_briefing_btn.pressed.connect(_open_mobile_briefing)
	modes_row.add_child(_briefing_btn)

	var daily_row := HBoxContainer.new()
	daily_row.add_theme_constant_override("separation", _gap(8))
	v.add_child(daily_row)
	var dc := Global.get_daily_challenge()
	var dc_title := str(dc.get("title_en" if is_en else "title_ua", dc.get("title_uk", "")))
	var dc_done := " ✓" if bool(dc.get("completed", false)) else ""
	var trec := Global.get_training_record("course")
	var rec_suffix := ""
	if bool(trec.get("completed", false)):
		rec_suffix = ("  ·  Course: %.1fs %s [%s]" if is_en else "  ·  Траса: %.1f с %s [%s]") % [
			float(trec.get("best_time", 0.0)), "★".repeat(int(trec.get("stars", 1))), str(trec.get("best_rank", "B"))]
	_play_daily_lbl = _label(("★ %s (+%d)%s%s" % [dc_title, int(dc.get("bonus_score", 500)), dc_done, rec_suffix]), 13, MenuUI.FPV_CYAN)
	_play_daily_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	daily_row.add_child(_play_daily_lbl)

	_build_mobile_mission_strip(v, is_en)

	# Map cards
	_maps_row = HBoxContainer.new()
	_maps_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_maps_row.add_theme_constant_override("separation", _gap(10))
	v.add_child(_maps_row)

	var map_idx := 0
	for mp in MAP_META:
		map_idx += 1
		var card := _panel(Color(0.025, 0.065, 0.05, 0.92), Color(0.38, 0.54, 0.42, 0.55), 1, 14)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.set_meta("map_id", str(mp["id"]))
		card.mouse_filter = Control.MOUSE_FILTER_PASS
		var card_id := str(mp["id"])
		card.gui_input.connect(func(ev: InputEvent):
			if (ev is InputEventScreenTouch and ev.pressed) or (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT):
				_select_map(card_id)
		)
		_maps_row.add_child(card)

		var card_v := VBoxContainer.new()
		card_v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_v.add_theme_constant_override("separation", _gap(5))
		card.add_child(card_v)

		var sec_lbl := _label(("SECTOR 0%d" if is_en else "СЕКТОР 0%d") % map_idx, 11, MenuUI.FPV_CYAN)
		sec_lbl.set_meta("map_text_ua", "СЕКТОР 0%d" % map_idx)
		sec_lbl.set_meta("map_text_en", "SECTOR 0%d" % map_idx)
		sec_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_v.add_child(sec_lbl)

		var map_img_path: String = "res://Assets/Branding/mobile_map_%s.png" % str(mp["id"])
		var map_tex: Texture2D = _safe_texture(map_img_path)
		if map_tex != null:
			var img_frame := PanelContainer.new()
			img_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
			img_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
			var f_sb := StyleBoxFlat.new()
			f_sb.bg_color = Color(0.015, 0.04, 0.03, 0.9)
			f_sb.border_color = Color(0.36, 0.58, 0.44, 0.65)
			f_sb.set_border_width_all(1)
			f_sb.set_corner_radius_all(8)
			f_sb.content_margin_left = 2
			f_sb.content_margin_right = 2
			f_sb.content_margin_top = 2
			f_sb.content_margin_bottom = 2
			img_frame.add_theme_stylebox_override("panel", f_sb)
			var img_rect := TextureRect.new()
			img_rect.texture = map_tex
			img_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			img_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			img_rect.custom_minimum_size.y = _fs(118)
			img_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
			img_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			img_frame.add_child(img_rect)
			card_v.add_child(img_frame)

		var name_lbl := _label(str(mp.get("name_en" if is_en else "name", mp["name"])), 24, MenuUI.TEXT)
		name_lbl.set_meta("map_text_ua", str(mp["name"]))
		name_lbl.set_meta("map_text_en", str(mp.get("name_en", mp["name"])))
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_v.add_child(name_lbl)
		var tag_lbl := _label(str(mp.get("tag_en" if is_en else "tag", mp["tag"])), 13, MenuUI.FPV_AMBER)
		tag_lbl.set_meta("map_text_ua", str(mp["tag"]))
		tag_lbl.set_meta("map_text_en", str(mp.get("tag_en", mp["tag"])))
		tag_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_v.add_child(tag_lbl)
		var diff_raw := str(mp.get("diff", "СЕРЕДНЯ"))
		var diff_col := MenuUI.FPV_GREEN if diff_raw == "ЛЕГКА" else (MenuUI.FPV_AMBER if diff_raw == "СЕРЕДНЯ" else Color("e07b72"))
		var diff_lbl := _label(("DIFFICULTY: " if is_en else "СКЛАДНІСТЬ: ")
				+ str(mp.get("diff_en" if is_en else "diff",
				"MEDIUM" if is_en else "СЕРЕДНЯ")), 12, diff_col)
		diff_lbl.set_meta("map_text_ua", "СКЛАДНІСТЬ: " + str(mp.get("diff", "СЕРЕДНЯ")))
		diff_lbl.set_meta("map_text_en", "DIFFICULTY: " + str(mp.get("diff_en", "MEDIUM")))
		diff_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_v.add_child(diff_lbl)

		var is_sel := (str(mp["id"]) == _selected_map)
		var sel_btn := _button(("SELECTED ✓" if is_sel else "SELECT") if is_en \
				else ("ОБРАНО ✓" if is_sel else "ОБРАТИ"), 46, is_sel)
		sel_btn.pressed.connect(func():
			_select_map(card_id)
		)
		sel_btn.set_meta("map_id", card_id)
		card.set_meta("btn", sel_btn)
		card_v.add_child(sel_btn)

	_update_map_cards(_maps_row)

	# Centered Bottom Bar (Finger-friendly Launch Button at Bottom Center)
	var bottom_center := VBoxContainer.new()
	bottom_center.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_center.add_theme_constant_override("separation", _gap(6))
	v.add_child(bottom_center)

	_play_caption = _label("", 18, MenuUI.MUTED)
	_play_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom_center.add_child(_play_caption)
	_update_play_caption()

	var start_mission_btn := _button("ПОЧАТИ ВИЛІТ", 62, true)
	start_mission_btn.custom_minimum_size = Vector2(_fs(420), _fs(62))
	start_mission_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start_mission_btn.pressed.connect(_launch)
	bottom_center.add_child(start_mission_btn)

	_build_mobile_briefing_modal(self, is_en)


func _select_map(card_id: String, row: HBoxContainer = null) -> void:
	_selected_map = card_id
	Global.menu_settings["selected_map"] = _selected_map
	Global.save_menu_settings()
	var target_row: HBoxContainer = row if row != null else _maps_row
	if target_row != null:
		_update_map_cards(target_row)


func _apply_button_primary_style(btn: Button, primary: bool) -> void:
	if btn == null:
		return
	var h: float = btn.custom_minimum_size.y if btn.custom_minimum_size.y > 0 else 46.0
	var r := int(minf(h * 0.42, 16.0))
	var s_norm := StyleBoxFlat.new()
	s_norm.set_corner_radius_all(r)
	var s_hov := StyleBoxFlat.new()
	s_hov.set_corner_radius_all(r)
	var s_press := StyleBoxFlat.new()
	s_press.set_corner_radius_all(r)
	var text_col: Color
	if primary:
		s_norm.bg_color = MenuUI.ACCENT
		s_norm.border_color = Color(0.92, 0.84, 0.56, 0.95)
		s_norm.set_border_width_all(1)
		s_norm.border_width_left = 4
		s_norm.shadow_color = Color(0.0, 0.0, 0.0, 0.42)
		s_norm.shadow_size = 6
		s_norm.shadow_offset = Vector2(0, 3)
		s_hov.bg_color = Color(0.82, 0.90, 0.72, 1.0)
		s_hov.border_color = Color(0.95, 0.88, 0.62, 1.0)
		s_hov.set_border_width_all(1)
		s_hov.border_width_left = 4
		s_press.bg_color = Color(0.58, 0.70, 0.50, 1.0)
		s_press.border_color = Color(0.58, 0.70, 0.50, 1.0)
		text_col = Color(0.06, 0.09, 0.07)
	else:
		s_norm.bg_color = Color(0.04, 0.08, 0.065, 0.88)
		s_norm.border_color = Color(0.32, 0.48, 0.38, 0.6)
		s_norm.set_border_width_all(1)
		s_norm.border_width_left = 3
		s_norm.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
		s_norm.shadow_size = 5
		s_norm.shadow_offset = Vector2(0, 2)
		s_hov.bg_color = Color(0.08, 0.15, 0.11, 0.96)
		s_hov.border_color = Color(0.45, 0.65, 0.52, 0.8)
		s_hov.set_border_width_all(1)
		s_hov.border_width_left = 4
		s_press.bg_color = Color(0.10, 0.22, 0.15, 1.0)
		s_press.border_color = Color(0.50, 0.75, 0.60, 0.9)
		s_press.set_border_width_all(1)
		s_press.border_width_left = 4
		text_col = MenuUI.TEXT
	btn.add_theme_color_override("font_color", text_col)
	btn.add_theme_color_override("font_hover_color", text_col)
	btn.add_theme_color_override("font_pressed_color", text_col)
	btn.add_theme_stylebox_override("normal", s_norm)
	btn.add_theme_stylebox_override("hover", s_hov)
	btn.add_theme_stylebox_override("pressed", s_press)


func _mode_title(mode_id: int) -> String:
	var key := "name_en" if MenuUI.is_english() else "name"
	for m in MODE_META:
		if int(m["id"]) == mode_id:
			return str(m.get(key, m.get("name", ""))).to_upper()
	return "TUTORIAL" if MenuUI.is_english() else "ТУТОРІАЛ"


func _build_mobile_mission_strip(parent: VBoxContainer, is_en: bool) -> void:
	_mission_buttons.clear()
	_mission_row = HBoxContainer.new()
	_mission_row.add_theme_constant_override("separation", _gap(6))
	_mission_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mission_row.visible = (_selected_mode == Global.PlayMode.COMBAT)
	parent.add_child(_mission_row)

	_mission_bar = ScrollContainer.new()
	_mission_bar.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_mission_bar.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_mission_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mission_bar.custom_minimum_size = Vector2(0, _fs(38))
	_mission_row.add_child(_mission_bar)

	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", _gap(6))
	_mission_bar.add_child(strip)

	for m_id in range(1, 5):
		var unlocked := Global.is_mission_unlocked(m_id)
		var b := _button("TAC-0%d" % m_id, 34, _selected_special == 0 and _selected_mission == m_id)
		b.custom_minimum_size = Vector2(_ui_sz(78), _fs(34))
		b.add_theme_font_size_override("font_size", _fs(14))
		b.disabled = not unlocked
		b.modulate = Color(1, 1, 1, 1 if unlocked else 0.45)
		b.pressed.connect(_select_mobile_mission.bind(m_id, 0))
		strip.add_child(b)
		_mission_buttons["tac:%d" % m_id] = b

	for s_id in range(1, 10):
		var op_prefix := "OP" if is_en else "СО"
		var b := _button("%s-0%d · %s" % [op_prefix, s_id, Global.get_special_mission_name(s_id)],
				34, _selected_special == s_id)
		b.custom_minimum_size = Vector2(0, _fs(34))
		b.add_theme_font_size_override("font_size", _fs(14))
		b.pressed.connect(_select_mobile_mission.bind(-1, s_id))
		strip.add_child(b)
		_mission_buttons["spec:%d" % s_id] = b

	var scroll_btn := _button("»", 34, false)
	scroll_btn.custom_minimum_size = Vector2(_ui_sz(40), _fs(34))
	scroll_btn.add_theme_font_size_override("font_size", _fs(18))
	scroll_btn.add_theme_color_override("font_color", MenuUI.FPV_AMBER)
	scroll_btn.pressed.connect(func():
		if _mission_bar != null:
			_mission_bar.scroll_horizontal += _ui_sz(280)
	)
	_mission_row.add_child(scroll_btn)
	_refresh_mobile_mission_strip()


func _select_mobile_mission(mission_id: int, special_id: int) -> void:
	if mission_id >= 1:
		_selected_mission = clampi(mission_id, 1, 4)
	_selected_special = clampi(special_id, 0, 9)
	if _selected_special == 0 and not Global.is_mission_unlocked(_selected_mission):
		_selected_mission = 1 if Global.campaign_is_complete() else Global.campaign_unlocked_mission()
	Global.menu_settings["selected_mission"] = _selected_mission
	Global.menu_settings["selected_special"] = _selected_special
	Global.save_menu_settings()
	_refresh_mobile_mission_strip()
	_update_play_caption()


func _refresh_mobile_mission_strip() -> void:
	var is_combat := (_selected_mode == Global.PlayMode.COMBAT)
	if _mission_row != null:
		_mission_row.visible = is_combat
	if _mission_bar != null:
		_mission_bar.visible = is_combat
	if _diff_bar != null:
		_diff_bar.visible = is_combat
	if _briefing_btn != null:
		_briefing_btn.visible = is_combat
	for d_id in _diff_buttons.keys():
		var db: Button = _diff_buttons[d_id] as Button
		if db != null:
			_apply_button_primary_style(db, int(Global.difficulty) == int(d_id))
	var is_en := MenuUI.is_english()
	for m_id in range(1, 5):
		var b: Button = _mission_buttons.get("tac:%d" % m_id, null) as Button
		if b != null:
			var unlocked := Global.is_mission_unlocked(m_id)
			var mrec := Global.get_mission_record(m_id)
			var m_stars := int(mrec.get("stars", 0)) if bool(mrec.get("completed", false)) else 0
			b.text = ("TAC-0%d %s" % [m_id, "★".repeat(m_stars)]) if m_stars > 0 else ("TAC-0%d" % m_id)
			b.disabled = not unlocked
			b.modulate = Color(1, 1, 1, 1 if unlocked else 0.45)
			_apply_button_primary_style(b, _selected_special == 0 and _selected_mission == m_id)
	var op_prefix := "OP" if is_en else "СО"
	for s_id in range(1, 10):
		var b: Button = _mission_buttons.get("spec:%d" % s_id, null) as Button
		if b != null:
			var srec := Global.get_special_mission_record(s_id) if Global.has_method("get_special_mission_record") else {}
			var s_stars := int(srec.get("stars", 0)) if bool(srec.get("completed", false)) else 0
			var suffix := (" " + "★".repeat(s_stars)) if s_stars > 0 else ""
			b.text = "%s-0%d · %s%s" % [op_prefix, s_id, Global.get_special_mission_name(s_id), suffix]
			_apply_button_primary_style(b, _selected_special == s_id)


func _select_mobile_difficulty(diff: int) -> void:
	Global.difficulty = clampi(diff, 0, 2)
	Global.menu_settings["difficulty"] = Global.difficulty
	Global.save_menu_settings()
	_refresh_mobile_mission_strip()
	_update_play_caption()


func _mobile_airframe_budget() -> int:
	match Global.difficulty:
		Global.Difficulty.RECRUIT:
			return 5
		Global.Difficulty.ACE:
			return 2
		_:
			return 3


func _build_mobile_briefing_modal(host: Control, is_en: bool) -> void:
	if _briefing_modal != null and is_instance_valid(_briefing_modal):
		_briefing_modal.free()
		_briefing_modal = null
	_briefing_modal = PanelContainer.new()
	_briefing_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_briefing_modal.z_index = 40
	_briefing_modal.visible = false
	_briefing_modal.add_theme_stylebox_override("panel", _panel_style(
			Color(0.012, 0.028, 0.022, 0.988), MenuUI.ACCENT, 2, 16))
	host.add_child(_briefing_modal)

	var safe_m: Dictionary = MenuUI.get_safe_margins(_vsize())
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", maxi(24, int(safe_m.get("left", 0))) + _gap(12))
	margin.add_theme_constant_override("margin_right", maxi(24, int(safe_m.get("right", 0))) + _gap(12))
	margin.add_theme_constant_override("margin_top", maxi(18, int(safe_m.get("top", 0))) + _gap(8))
	margin.add_theme_constant_override("margin_bottom", maxi(18, int(safe_m.get("bottom", 0))) + _gap(8))
	_briefing_modal.add_child(margin)

	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", _gap(10))
	margin.add_child(bv)

	var hdr := HBoxContainer.new()
	bv.add_child(hdr)
	_briefing_title = _label("BRIEFING" if is_en else "БРИФІНГ МІСІЇ", 24, MenuUI.FPV_AMBER)
	_briefing_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(_briefing_title)
	var close_btn := _button("CLOSE" if is_en else "ЗАКРИТИ", 36, false)
	close_btn.custom_minimum_size = Vector2(_ui_sz(116), _fs(36))
	close_btn.pressed.connect(func():
		if _briefing_modal != null:
			_briefing_modal.visible = false)
	hdr.add_child(close_btn)

	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", _gap(14))
	bv.add_child(split)

	var left_col := VBoxContainer.new()
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.add_theme_constant_override("separation", _gap(8))
	split.add_child(left_col)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.add_child(scroll)
	_briefing_body = _label("", 15, MenuUI.TEXT)
	_briefing_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_briefing_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_briefing_body)

	var tac_opts := HBoxContainer.new()
	tac_opts.add_theme_constant_override("separation", _gap(8))
	left_col.add_child(tac_opts)
	_briefing_fiber_btn = _button("", 42, false)
	_briefing_fiber_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_briefing_fiber_btn.pressed.connect(func():
		var cur_f := bool(Global.menu_settings.get("fiber_optic_mode", false))
		Global.menu_settings["fiber_optic_mode"] = not cur_f
		Global.save_menu_settings()
		_refresh_briefing_tactical_buttons()
		if _kropyva_canvas != null:
			_kropyva_canvas.queue_redraw())
	tac_opts.add_child(_briefing_fiber_btn)

	_briefing_flank_btn = _button("", 42, false)
	_briefing_flank_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_briefing_flank_btn.pressed.connect(func():
		var cur_fl := bool(Global.menu_settings.get("flank_spawn", false))
		Global.menu_settings["flank_spawn"] = not cur_fl
		Global.save_menu_settings()
		_refresh_briefing_tactical_buttons()
		if _kropyva_canvas != null:
			_kropyva_canvas.queue_redraw())
	tac_opts.add_child(_briefing_flank_btn)

	_kropyva_panel = PanelContainer.new()
	_kropyva_panel.custom_minimum_size = Vector2(_ui_sz(340), _ui_sz(280))
	_kropyva_panel.add_theme_stylebox_override("panel", _panel_style(
			Color(0.015, 0.038, 0.026, 0.98), Color(0.32, 0.68, 0.45, 0.85), 1, 10))
	split.add_child(_kropyva_panel)
	_kropyva_canvas = Control.new()
	_kropyva_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_kropyva_canvas.draw.connect(_draw_kropyva_map)
	_kropyva_panel.add_child(_kropyva_canvas)
	_refresh_briefing_tactical_buttons()


func _refresh_briefing_tactical_buttons() -> void:
	var is_en := MenuUI.is_english()
	var fiber := bool(Global.menu_settings.get("fiber_optic_mode", false)) if Global != null else false
	var flank := bool(Global.menu_settings.get("flank_spawn", false)) if Global != null else false
	if _briefing_fiber_btn != null:
		if is_en:
			_briefing_fiber_btn.text = "LINK: FIBER-OPTIC 10 KM ✓" if fiber else "LINK: RADIO (STANDARD)"
		else:
			_briefing_fiber_btn.text = "ЗВ'ЯЗОК: ОПТОВОЛОКНО 10 КМ ✓" if fiber else "ЗВ'ЯЗОК: РАДІОКАНАЛ"
	if _briefing_flank_btn != null:
		if is_en:
			_briefing_flank_btn.text = "APPROACH: FLANK BYPASS ✓" if flank else "APPROACH: MAIN VECTOR"
		else:
			_briefing_flank_btn.text = "ЗАХІД: ОБХІД З ФЛАНГУ ✓" if flank else "ЗАХІД: ОСНОВНА ПОЗИЦІЯ"


func _draw_kropyva_map() -> void:
	if _kropyva_canvas == null:
		return
	var sz := _kropyva_canvas.size
	if sz.x < 40.0 or sz.y < 40.0:
		return
	var is_en := MenuUI.is_english()
	var font := ThemeDB.fallback_font
	var pad := 14.0
	var rect := Rect2(Vector2(pad, pad + 22.0), Vector2(sz.x - pad * 2.0, sz.y - pad * 2.0 - 26.0))
	_kropyva_canvas.draw_rect(rect, Color(0.02, 0.055, 0.038, 1.0), true)
	# Topographic grid lines
	var grid_col := Color(0.22, 0.48, 0.32, 0.28)
	for i in range(1, 6):
		var gx := rect.position.x + rect.size.x * (float(i) / 6.0)
		var gy := rect.position.y + rect.size.y * (float(i) / 6.0)
		_kropyva_canvas.draw_line(Vector2(gx, rect.position.y), Vector2(gx, rect.end.y), grid_col, 1.0)
		_kropyva_canvas.draw_line(Vector2(rect.position.x, gy), Vector2(rect.end.x, gy), grid_col, 1.0)
	_kropyva_canvas.draw_rect(rect, Color(0.38, 0.78, 0.52, 0.65), false, 1.5)

	# Header bar ("KROPYVA // SECTOR 36U")
	var hdr_txt := "KROPYVA // SECTOR 36U-XA" if is_en else "КРОПИВА // СЕКТОР 36U-XA"
	_kropyva_canvas.draw_string(font, Vector2(pad, pad + 15.0), hdr_txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.55, 0.96, 0.68))

	var center := rect.get_center()
	# EW / SAM threat zone ring
	var ew_pos := center + Vector2(14.0, -18.0)
	_kropyva_canvas.draw_arc(ew_pos, minf(rect.size.x, rect.size.y) * 0.28, 0.0, TAU, 36,
			Color(1.0, 0.28, 0.22, 0.42), 1.5)
	_kropyva_canvas.draw_circle(ew_pos, minf(rect.size.x, rect.size.y) * 0.28,
			Color(0.95, 0.18, 0.14, 0.09))

	# Friendly launch position (Main vs Flank)
	var flank := bool(Global.menu_settings.get("flank_spawn", false)) if Global != null else false
	var fiber := bool(Global.menu_settings.get("fiber_optic_mode", false)) if Global != null else false
	var start_pt := Vector2(center.x - rect.size.x * 0.28, rect.end.y - 26.0) if flank \
			else Vector2(center.x + 12.0, rect.end.y - 24.0)
	var recon_pt := center + Vector2(-8.0, 18.0)
	var line_col := Color(0.35, 0.95, 1.0, 0.88) if fiber else Color(0.42, 0.96, 0.58, 0.85)
	_kropyva_canvas.draw_line(start_pt, recon_pt, line_col, 2.2)
	_kropyva_canvas.draw_line(recon_pt, ew_pos, Color(1.0, 0.76, 0.28, 0.82), 2.0)

	# Hostile target diamonds (NATO style)
	var tgt_offsets := [Vector2(-24, -12), Vector2(18, -28), Vector2(36, 4), Vector2(-6, -38)]
	for off in tgt_offsets:
		var tp: Vector2 = center + off
		var d_pts := PackedVector2Array([
			tp + Vector2(0, -7), tp + Vector2(7, 0),
			tp + Vector2(0, 7), tp + Vector2(-7, 0)
		])
		_kropyva_canvas.draw_colored_polygon(d_pts, Color(0.98, 0.24, 0.18, 0.92))
		_kropyva_canvas.draw_polyline(d_pts, Color(1.0, 0.82, 0.75, 0.95), 1.2)

	# Friendly Launch Triangle
	var s_pts := PackedVector2Array([
		start_pt + Vector2(0, -9), start_pt + Vector2(8, 7), start_pt + Vector2(-8, 7)
	])
	_kropyva_canvas.draw_colored_polygon(s_pts, Color(0.25, 0.88, 1.0, 0.95))
	var st_lbl := "FLANK" if (is_en and flank) else ("START" if is_en else ("ФЛАНГ" if flank else "СТАРТ"))
	_kropyva_canvas.draw_string(font, start_pt + Vector2(-22.0, 20.0), st_lbl,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.55, 0.95, 1.0))
	var tgt_lbl := "TARGETS / EW" if is_en else "ЦІЛІ / РЕБ"
	_kropyva_canvas.draw_string(font, ew_pos + Vector2(-32.0, -minf(rect.size.x, rect.size.y) * 0.28 - 6.0),
			tgt_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.48, 0.42))


func _open_mobile_records() -> void:
	var is_en := MenuUI.is_english()
	Global.open_game_center_leaderboard()
	if _play_daily_lbl != null and is_instance_valid(_play_daily_lbl):
		_play_daily_lbl.text = Global.get_leaderboard_summary(is_en)
	if Global.is_game_center_available():
		return
	if _briefing_modal == null or _briefing_title == null or _briefing_body == null:
		return
	_briefing_title.text = "PILOT RECORDS & STATS" if is_en else "РЕКОРДИ ТА СТАТИСТИКА ПІЛОТА"
	_briefing_body.text = Global.get_records_report(is_en)
	if _kropyva_panel != null:
		_kropyva_panel.visible = false
	if _briefing_fiber_btn != null:
		_briefing_fiber_btn.visible = false
	if _briefing_flank_btn != null:
		_briefing_flank_btn.visible = false
	_briefing_modal.visible = true


func _open_mobile_briefing() -> void:
	if _briefing_modal == null or _briefing_title == null or _briefing_body == null:
		return
	var is_en := MenuUI.is_english()
	var mm = load("res://GUI/MainMenu.gd")
	var craft_cap := _mobile_airframe_budget()
	var lines: PackedStringArray = []
	if _selected_special > 0:
		var op_name := Global.get_special_mission_name(_selected_special)
		_briefing_title.text = "%s-0%d · %s" % ["OP" if is_en else "СО", _selected_special, op_name]
		var desc := ""
		var sdiff := Global.get_difficulty_name()
		if mm != null:
			for md in mm.SPECIAL_MISSIONS:
				if int(md.get("id", 0)) == _selected_special:
					desc = str(md.get("desc_en" if is_en else "desc", md.get("desc", "")))
					sdiff = str(md.get("diff_en" if is_en else "diff", sdiff))
					break
		lines.append(desc if not desc.is_empty() else op_name)
		lines.append("")
		lines.append("%s: %s · %s: %d" % [
			"DIFFICULTY" if is_en else "СКЛАДНІСТЬ", Global.get_difficulty_name(),
			"AIRFRAMES" if is_en else "БОРТІВ НА ВИЛІТ", craft_cap])
		lines.append("%s: %s" % ["PROFILE" if is_en else "ПРОФІЛЬ", sdiff])
		var srec := Global.get_special_mission_record(_selected_special) if Global.has_method("get_special_mission_record") else {}
		if bool(srec.get("completed", false)):
			lines.append("%s: %d · ★%d" % [
				"BEST SCORE" if is_en else "РЕКОРД",
				int(srec.get("best_score", 0)), int(srec.get("stars", 1))])
	else:
		var mid := clampi(_selected_mission, 1, 4)
		var b: Dictionary = mm.BRIEFINGS.get(mid, {}) if mm != null else {}
		var content: Dictionary = mm.BRIEFINGS_EN.get(mid, b) if (mm != null and is_en) else b
		_briefing_title.text = "%s · %s" % [str(b.get("code", "TAC-0%d" % mid)), str(content.get("name", b.get("name", "")))]
		lines.append(str(content.get("op_name", b.get("op_name", ""))))
		lines.append(str(content.get("intel", b.get("intel", ""))))
		lines.append("")
		lines.append("TASKS:" if is_en else "ЗАВДАННЯ:")
		for t in content.get("tasks", b.get("tasks", [])):
			lines.append("  ✔ " + str(t))
		lines.append("")
		lines.append("THREATS:" if is_en else "ЗАГРОЗИ:")
		for th in content.get("threats", b.get("threats", [])):
			lines.append("  • " + str(th))
		lines.append("")
		lines.append("%s: %s · %s: %d" % [
			"DIFFICULTY" if is_en else "СКЛАДНІСТЬ", Global.get_difficulty_name(),
			"AIRFRAMES" if is_en else "БОРТІВ НА ВИЛІТ", craft_cap])
		lines.append("%s: %s" % ["RECOMMENDED" if is_en else "РЕКОМЕНДОВАНО", str(content.get("drone", b.get("drone", "")))])
	_briefing_body.text = "\n".join(lines)
	if _kropyva_panel != null:
		_kropyva_panel.visible = true
	if _briefing_fiber_btn != null:
		_briefing_fiber_btn.visible = true
	if _briefing_flank_btn != null:
		_briefing_flank_btn.visible = true
	_refresh_briefing_tactical_buttons()
	if _kropyva_canvas != null:
		_kropyva_canvas.queue_redraw()
	_briefing_modal.visible = true


func _update_play_caption() -> void:
	if _play_caption == null:
		return
	var is_en := MenuUI.is_english()
	var map_name := "VILLAGE" if is_en else "СЕЛО"
	for mp in MAP_META:
		if str(mp["id"]) == _selected_map:
			map_name = str(mp.get("name_en" if is_en else "name", mp["name"])).to_upper()
			break
	var mode_name := _mode_title(_selected_mode)
	var mission_tag := ""
	if _selected_mode == Global.PlayMode.COMBAT:
		var d_tag := "%s/%d" % [Global.get_difficulty_name(), _mobile_airframe_budget()]
		if _selected_special > 0:
			mission_tag = " · %s-0%d (%s) · %s" % [
				"OP" if MenuUI.is_english() else "СО",
				_selected_special,
				Global.get_special_mission_name(_selected_special),
				d_tag,
			]
		else:
			mission_tag = " · TAC-0%d · %s" % [_selected_mission, d_tag]
	var dname := MenuUI.translate_text(DroneCatalog.get_drone_name(Global.drone_preset))
	if MenuUI.is_english():
		_play_caption.text = "SELECTED: %s · %s%s · CRAFT: %s" % [map_name, mode_name, mission_tag, dname]
	else:
		_play_caption.text = "ОБРАНО: %s · %s%s · ДРОН: %s" % [map_name, mode_name, mission_tag, dname]


func _update_play_modes(row: HBoxContainer) -> void:
	for c in row.get_children():
		if c is Button and c.has_meta("mode_id"):
			var mid := int(c.get_meta("mode_id", -1))
			_apply_button_primary_style(c, mid == _selected_mode)
	_refresh_mobile_mission_strip()
	_update_play_caption()


func _update_map_cards(row: HBoxContainer) -> void:
	var is_en := MenuUI.is_english()
	for c in row.get_children():
		var mid := str(c.get_meta("map_id", ""))
		var is_sel := (mid == _selected_map)
		c.add_theme_stylebox_override("panel", _panel_style(
			Color(0.045, 0.10, 0.075, 0.96) if is_sel else Color(0.025, 0.065, 0.05, 0.92),
			MenuUI.ACCENT if is_sel else Color(0.38, 0.54, 0.42, 0.55),
			3 if is_sel else 1,
			14
		))
		var b: Button = c.get_meta("btn", null) as Button
		if b != null:
			b.text = ("SELECTED ✓" if is_sel else "SELECT") if is_en \
					else ("ОБРАНО ✓" if is_sel else "ОБРАТИ")
			_apply_button_primary_style(b, is_sel)
		var card_content := c.get_child(0) as VBoxContainer if c.get_child_count() > 0 else null
		if card_content != null:
			for child in card_content.get_children():
				if child is Label and child.has_meta("map_text_ua"):
					var label := child as Label
					label.text = str(label.get_meta("map_text_en" if is_en else "map_text_ua"))
	_update_play_caption()


func _launch(combat_training: bool = false) -> void:
	Global.combat_training = combat_training
	if combat_training:
		# Village north field + GRIM-7M (a combat airframe with a real payload
		# release).  The guide replaces the freestyle ring course in BigLevel.
		_selected_mode = Global.PlayMode.TRAINING
		_selected_map = "village"
		_selected_special = 0
		Global.special_mission = 0
		QuadSettings.custom_rates = false
		DroneCatalog.apply(1)
	_selected_mode = Global.sanitize_play_mode(_selected_mode)
	Global.play_mode = _selected_mode
	if _selected_mode == Global.PlayMode.COMBAT:
		Global.special_mission = _selected_special
		if _selected_special > 0:
			Global.combat_mission = 1
		else:
			if not Global.is_mission_unlocked(_selected_mission):
				_selected_mission = 1 if Global.campaign_is_complete() else Global.campaign_unlocked_mission()
			Global.combat_mission = _selected_mission
	else:
		Global.special_mission = 0
	Global.menu_settings["selected_map"] = _selected_map
	Global.menu_settings["selected_mode"] = _selected_mode
	Global.menu_settings["selected_mission"] = _selected_mission
	Global.menu_settings["selected_special"] = _selected_special
	Global.menu_settings["drone_preset"] = Global.drone_preset
	Global.save_menu_settings()
	var scenes := {
		"steppe": "res://sceneries/SteppeLevel.tscn",
		"village": "res://sceneries/VillageLevel.tscn",
		"industrial": "res://sceneries/IndustrialLevel.tscn",
		"wetlands": "res://sceneries/WetlandsLevel.tscn",
	}
	var launch_map := "village" if _selected_mode == Global.PlayMode.TUTORIAL else _selected_map
	var path: String = scenes.get(launch_map, "res://sceneries/VillageLevel.tscn")

	# Stop menu ambient / music
	Audio.stop_menu_music(0.5)

	# Tactical Mission Loading Screen (as in PC version)
	var overlay: Dictionary = LoadingScreen.build(_selected_mode, _selected_mission,
			launch_map, Global.get_difficulty_name(), true)
	_loading_layer = overlay.get("layer") as CanvasLayer
	var loading_bar: ProgressBar = overlay.get("bar") as ProgressBar
	if _loading_layer != null:
		get_tree().root.add_child(_loading_layer)
	if loading_bar != null:
		loading_bar.value = 12.0
		var tween := create_tween()
		tween.tween_property(loading_bar, "value", 92.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		await tween.finished
	await get_tree().process_frame
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
	list_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_card.clip_contents = true
	cols.add_child(list_card)

	var scroll := ScrollContainer.new()
	scroll.name = "HangarScroll"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.scroll_deadzone = 4
	scroll.follow_focus = false
	list_card.add_child(scroll)
	_hangar_scroll = scroll
	scroll.gui_input.connect(_on_hangar_scroll_gui_input.bind(scroll))

	_hangar_list_container = VBoxContainer.new()
	_hangar_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hangar_list_container.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
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
		btn.gui_input.connect(_on_hangar_scroll_gui_input.bind(scroll))
		btn.pressed.connect(func():
			# A vertical swipe that started on a row must scroll the hangar,
			# not select the drone under the finger.
			if _hangar_scroll_drag_dist > 12.0:
				return
			_hangar_preview_idx = cur_i
			var total := DroneCatalog.count()
			DroneCatalog.prefetch_model((cur_i + 1) % total)
			DroneCatalog.prefetch_model((cur_i - 1 + total) % total)
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
	_hangar_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_hangar_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
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

	_hangar_drone_name = _label("«ГРІМ-7»", 28, MenuUI.TEXT)
	info_v.add_child(_hangar_drone_name)
	_hangar_drone_tag = _label("ТАКТИЧНИЙ 8–10\" • FPV", 13, MenuUI.FPV_AMBER)
	info_v.add_child(_hangar_drone_tag)
	_hangar_specs_lbl = _label("МАСА: 1400 г • TWR: 3.5:1 • МОТОРИ: 1350 KV", 12, MenuUI.MUTED)
	info_v.add_child(_hangar_specs_lbl)
	info_v.add_child(_build_perf_bars_row(_hangar_perf_bars))

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
	cyl.top_radius = 0.50
	cyl.bottom_radius = 0.54
	cyl.height = 0.018
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
	h_torus.inner_radius = 0.44
	h_torus.outer_radius = 0.48
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
	_add_tactical_podium_details(_hangar_viewport, -0.1770, 0.50)

	_hangar_camera = Camera3D.new()
	_hangar_camera.fov = 30.0
	_hangar_camera.current = true
	_hangar_viewport.add_child(_hangar_camera)

	_hangar_holder = Node3D.new()
	_hangar_viewport.add_child(_hangar_holder)


func _add_tactical_podium_details(vp: Node, top_y: float, radius: float) -> void:
	# Stepped armored base & field crate plinth underneath the turntable
	var crate := MeshInstance3D.new()
	var crate_box := BoxMesh.new()
	crate_box.size = Vector3(radius * 1.48, 0.16, radius * 1.48)
	crate.mesh = crate_box
	crate.position = Vector3(0.0, top_y - 0.095, 0.0)
	crate.rotation.y = deg_to_rad(18.0)
	var crate_mat := StandardMaterial3D.new()
	crate_mat.albedo_color = Color(0.15, 0.19, 0.14)
	crate_mat.roughness = 0.82
	crate_mat.metallic = 0.22
	crate.material_override = crate_mat
	vp.add_child(crate)

	# Inner concentric calibration ring flush on the deck
	var inner_ring := MeshInstance3D.new()
	var inner_torus := TorusMesh.new()
	inner_torus.inner_radius = radius * 0.52
	inner_torus.outer_radius = radius * 0.55
	inner_torus.rings = 36
	inner_torus.ring_segments = 16
	inner_ring.mesh = inner_torus
	inner_ring.scale = Vector3(1.0, 0.03, 1.0)
	inner_ring.position = Vector3(0.0, top_y + 0.001, 0.0)
	var ir_mat := StandardMaterial3D.new()
	ir_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ir_mat.albedo_color = Color(0.95, 0.76, 0.30, 0.85)
	inner_ring.material_override = ir_mat
	vp.add_child(inner_ring)

	# 8 radial compass ticks + 4 outer corner lugs with amber LED pips
	var lug_mat := StandardMaterial3D.new()
	lug_mat.albedo_color = Color(0.20, 0.25, 0.21)
	lug_mat.roughness = 0.65
	lug_mat.metallic = 0.45
	for i in range(8):
		var a := float(i) * PI * 0.25
		var tick := MeshInstance3D.new()
		var t_box := BoxMesh.new()
		t_box.size = Vector3(0.016, 0.003, radius * 0.18)
		tick.mesh = t_box
		var r_mid := radius * 0.74
		tick.position = Vector3(sin(a) * r_mid, top_y + 0.0015, cos(a) * r_mid)
		tick.rotation.y = a
		tick.material_override = ir_mat if (i % 2 == 0) else lug_mat
		vp.add_child(tick)
		if i % 2 == 1:
			var lug := MeshInstance3D.new()
			var l_box := BoxMesh.new()
			l_box.size = Vector3(0.065, 0.022, 0.045)
			lug.mesh = l_box
			var r_lug := radius * 0.99
			lug.position = Vector3(sin(a) * r_lug, top_y - 0.004, cos(a) * r_lug)
			lug.rotation.y = a
			lug.material_override = lug_mat
			vp.add_child(lug)


func _load_hangar_model(preset_idx: int) -> void:
	if _hangar_holder == null:
		return
	_hangar_load_token += 1
	var token := _hangar_load_token
	var p := DroneCatalog.preset(preset_idx)
	var is_vtol: bool = str(p.get("name", "")).contains("VTOL") or str(p.get("tag", "")).contains("VTOL")
	var target_sz: float = 0.46 if is_vtol else 0.52
	_update_hangar_info(preset_idx)
	for child in _hangar_holder.get_children():
		_hangar_holder.remove_child(child)
		child.queue_free()
	await DroneCatalog.wait_for_model(preset_idx)
	if token != _hangar_load_token:
		return
	var model: Node3D = DroneCatalog.attach_model(_hangar_holder, preset_idx)
	if model == null:
		_fit_hangar_camera()
		return
	model.set_meta("preset_idx", preset_idx)
	# Hide during the two-frame settle so unscaled aircraft never flash over
	# the pedestal before MenuUI.fit_preview_model fits them to target_sz.
	model.visible = false
	# Same two-frame settle as the hero podium.  Without it the first drone
	# opened in the hangar could be a speck until Next/Previous reloaded it.
	await get_tree().process_frame
	await get_tree().process_frame
	if token != _hangar_load_token or not is_instance_valid(model) \
			or model.get_parent() != _hangar_holder:
		return
	MenuUI.fit_preview_model(model, target_sz, -0.1775)
	_ensure_preview_scale(_hangar_holder, model, target_sz, -0.1775)
	_fit_hangar_camera()
	model.visible = true


func _fit_hangar_camera() -> void:
	if _hangar_holder == null or _hangar_camera == null:
		return
	var box := _combined_bounds(_hangar_holder)
	var center := box.get_center() if box.size.length() > 0.01 else Vector3.ZERO
	var max_dim := maxf(box.size.x, maxf(box.size.y, box.size.z))
	var focus := Vector3(center.x, center.y + 0.025, center.z)
	_hangar_camera.fov = 30.0
	var dist := clampf(max_dim * 1.55 + 0.35, 1.45, 2.05)
	var dir := Vector3(0.48, 0.28, 0.76).normalized()
	var cam_pos := focus + dir * dist
	_hangar_camera.look_at_from_position(cam_pos, focus, Vector3.UP)


func _update_hangar_info(preset_idx: int) -> void:
	var p := DroneCatalog.preset(preset_idx)
	var is_en := MenuUI.is_english()
	if _hangar_drone_name != null:
		_hangar_drone_name.text = MenuUI.translate_text(DroneCatalog.get_drone_name(preset_idx))
	if _hangar_drone_tag != null:
		_hangar_drone_tag.text = MenuUI.translate_text(DroneCatalog.get_drone_tag(preset_idx))
	if _hangar_specs_lbl != null:
		var mass: int = int(round((float(p.get("dry", 0.4)) + float(p.get("batt", 0.2))) * 1000.0))
		var twr: float = float(p.get("twr", 5.0))
		var kv: int = int(p.get("kv", 2000))
		var tilt: int = int(p.get("cam_tilt", 25))
		if is_en:
			_hangar_specs_lbl.text = "MASS: %d g • TWR: %.1f:1 • MOTORS: %d KV • CAM TILT: %d°" % [mass, twr, kv, tilt]
		else:
			_hangar_specs_lbl.text = "МАСА: %d г • TWR: %.1f:1 • МОТОРИ: %d KV • КУТ КАМЕРИ: %d°" % [mass, twr, kv, tilt]
	_update_perf_bars(_hangar_perf_bars, p)
	if _hangar_select_btn != null:
		if preset_idx == Global.drone_preset:
			_hangar_select_btn.text = "SELECTED FOR SORTIES" if is_en else "ОБРАНО ДЛЯ ВИЛЬОТІВ"
			_hangar_select_btn.modulate = Color(0.75, 1.0, 0.75)
		else:
			_hangar_select_btn.text = "SELECT THIS CRAFT" if is_en else "ОБРАТИ ЦЕЙ ДРОН"
			_hangar_select_btn.modulate = Color(1.0, 1.0, 1.0)


func _update_hangar_list_styles() -> void:
	if _hangar_list_container == null:
		return
	var is_en := MenuUI.is_english()
	for c in _hangar_list_container.get_children():
		if c is Button:
			var idx: int = int(c.get_meta("drone_idx", -1))
			var is_sel := (idx == _hangar_preview_idx)
			var is_cur := (idx == Global.drone_preset)
			var mark := ("  [ SELECTED ✓ ]" if is_en else "  [ ОБРАНО ✓ ]") if is_cur else ""

			var title_lbl := c.find_child("TitleLabel", true, false) as Label
			var tag_lbl := c.find_child("TagLabel", true, false) as Label

			if title_lbl != null:
				title_lbl.text = "%d. %s%s" % [idx + 1,
						MenuUI.translate_text(DroneCatalog.get_drone_name(idx)), mark]
				if is_sel:
					title_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
				elif is_cur:
					title_lbl.add_theme_color_override("font_color", Color(0.95, 0.90, 0.55))
				else:
					title_lbl.add_theme_color_override("font_color", Color(0.90, 0.94, 0.92))

			if tag_lbl != null:
				tag_lbl.text = MenuUI.translate_text(
						DroneCatalog.get_drone_tag(idx).to_upper())
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
	_update_play_caption()


## Manual drag-to-scroll for the hangar list.  iOS sends touch drags directly
## (the rows are Buttons and consume the press), so scrolling is driven here
## instead of relying only on ScrollContainer's built-in desktop wheel path.
func _on_hangar_scroll_gui_input(event: InputEvent, scroll: ScrollContainer) -> void:
	if scroll == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_hangar_scroll_drag_dist = 0.0
			_hangar_scroll_dragging = mb.pressed
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_hangar_scroll_drag_dist = 0.0
		_hangar_scroll_dragging = st.pressed
	elif event is InputEventMouseMotion and _hangar_scroll_dragging:
		var mm := event as InputEventMouseMotion
		scroll.scroll_vertical -= int(mm.relative.y)
		_hangar_scroll_drag_dist += absf(mm.relative.y)
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		scroll.scroll_vertical -= int(sd.relative.y)
		_hangar_scroll_drag_dist += absf(sd.relative.y)


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

	var compact := _vsize().x < 700.0
	var settings_heading := "SETTINGS" if MenuUI.is_english() else "НАЛАШТУВАННЯ"
	if not compact:
		settings_heading = "SETTINGS & SIMULATION" if MenuUI.is_english() \
				else "НАЛАШТУВАННЯ ТА СИМУЛЯЦІЯ"
	var heading := _label(settings_heading, 32, MenuUI.TEXT)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(heading)

	# 4 Tabs Bar
	var tabs_row: Container
	if compact:
		var tabs_grid := GridContainer.new()
		tabs_grid.columns = 1
		tabs_grid.add_theme_constant_override("h_separation", _gap(8))
		tabs_grid.add_theme_constant_override("v_separation", _gap(6))
		tabs_row = tabs_grid
	else:
		var tabs_hbox := HBoxContainer.new()
		tabs_hbox.add_theme_constant_override("separation", _gap(8))
		tabs_row = tabs_hbox
	v.add_child(tabs_row)

	var tab_defs := [
		{"id": "sim", "label": ("SIMULATION" if MenuUI.is_english() else "СИМУЛЯЦІЯ") \
				if compact else ("СИМУЛЯЦІЯ ТА РЕБ" if not MenuUI.is_english() else "SIMULATION & EW")},
		{"id": "hud", "label": "HUD" if compact else ("ІНТЕРФЕЙС (HUD)" if not MenuUI.is_english() else "INTERFACE (HUD)")},
		{"id": "gfx", "label": ("GRAPHICS" if MenuUI.is_english() else "ГРАФІКА") \
				if compact else ("ГРАФІКА ТА FPS" if not MenuUI.is_english() else "GRAPHICS & FPS")},
		{"id": "sys", "label": ("SYSTEM" if MenuUI.is_english() else "СИСТЕМА") \
				if compact else ("ЗВУК ТА СИСТЕМА" if not MenuUI.is_english() else "AUDIO & SYSTEM")},
	]

	for td in tab_defs:
		var tab_id: String = td["id"]
		var btn := _button(td["label"], 48, tab_id == _settings_tab)
		btn.add_theme_font_size_override("font_size", _fs(16 if compact else 20))
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

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(scroll)

	var sv := VBoxContainer.new()
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.add_theme_constant_override("separation", _gap(14))
	scroll.add_child(sv)

	var compact := _vsize().x < 700.0
	var is_en := MenuUI.is_english()
	sv.add_child(_label(
			("TRAINING / REALISM" if is_en else "ТРЕНАЖЕР / РЕАЛІЗМ") if compact \
			else ("TRAINING / SIMULATION REALISM" if is_en else "ТРЕНАЖЕР / СИМУЛЯЦІЯ РЕАЛІЗМУ"),
			20 if compact else 24, MenuUI.FPV_AMBER))
	sv.add_child(_label(
			("Assists active in flight" if is_en else "Полегшення під час польоту") if compact \
			else ("Assists and physics apply during flight" if is_en else "Полегшення та фізика діють одразу під час польоту"),
			13 if compact else 14, MenuUI.MUTED))

	var prof_row: BoxContainer
	if compact:
		var prof_vbox := VBoxContainer.new()
		prof_vbox.add_theme_constant_override("separation", _gap(6))
		prof_row = prof_vbox
		sv.add_child(_label("Профіль:" if not is_en else "PROFILE:", 16, MenuUI.TEXT))
	else:
		var prof_hbox := HBoxContainer.new()
		prof_hbox.add_theme_constant_override("separation", _gap(12))
		prof_row = prof_hbox
		prof_row.add_child(_label("Профіль реалізму:" if not is_en else "Realism profile:", 20, MenuUI.TEXT))

	var cur_prof: String = str(GameSettings.hud_config.get("realism_profile", GameSettings.REALISM_ARCADE))
	var arcade_text := ("ARCADE" if is_en else "АРКАДА") if compact \
			else ("ARCADE (ASSISTED)" if is_en else "АРКАДА (ПОЛЕГШЕНА)")
	var arcade_btn := _button(arcade_text, 44, cur_prof == GameSettings.REALISM_ARCADE)
	arcade_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prof_row.add_child(arcade_btn)

	var combat_text := ("COMBAT" if is_en else "БОЙОВИЙ") if compact \
			else ("COMBAT REALISM" if is_en else "БОЙОВИЙ РЕАЛІЗМ")
	var combat_btn := _button(combat_text, 44, cur_prof == GameSettings.REALISM_COMBAT)
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
	grid.columns = 1 if compact else 2
	grid.add_theme_constant_override("h_separation", _gap(24))
	grid.add_theme_constant_override("v_separation", _gap(12))
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.add_child(grid)

	var sim_items := [
		["link_limit", "Зв'язок" if compact else "Обмеження зв'язку (дальність/рельєф)"],
		["reb_zones", "РЕБ" if compact else "Зони РЕБ (глушіння)"],
		["wind_sim", "Вітер" if compact else "Імітація вітру та поривів"],
		["angle_mode", "Режим Angle" if compact else "Режим Angle (стабілізація)"],
		["acro_mode", "Режим Acro" if compact else "Режим Acro (ручний)"],
		["infinite_battery", "Батарея без кінця" if compact else "Нескінченна батарея (тренажер)"],
	]

	for item in sim_items:
		var key: String = item[0]
		var label_txt: String = item[1]
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var lbl := _label(label_txt, 16 if compact else 18, MenuUI.TEXT)
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

	sv.add_child(_label(("TOUCH HUD" if is_en else "СЕНСОРНИЙ HUD") if compact \
			else ("СЕНСОРНЕ КЕРУВАННЯ (TOUCH)" if not is_en else "TOUCH CONTROLS"),
			18 if compact else 20, MenuUI.FPV_AMBER))

	var touch_grid := GridContainer.new()
	touch_grid.columns = 1 if compact else 2
	touch_grid.add_theme_constant_override("h_separation", _gap(24))
	touch_grid.add_theme_constant_override("v_separation", _gap(10))
	touch_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.add_child(touch_grid)

	var touch_items := [
		["touch_floating_sticks", "Плаваючий стік" if not is_en else "Floating sticks", false],
		["touch_left_spring", "Пружина газу (Angle)" if compact else "Авто-центр газу (Angle)", false],
	]
	for t_item in touch_items:
		var t_key: String = t_item[0]
		var t_lbl_txt: String = t_item[1]
		var t_def: bool = bool(t_item[2])
		var trow := HBoxContainer.new()
		trow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var tlbl := _label(t_lbl_txt, 16 if compact else 18, MenuUI.TEXT)
		tlbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		trow.add_child(tlbl)
		var tsw := ToggleSwitch.new(bool(Global.menu_settings.get(t_key, t_def)))
		tsw.toggled.connect(func(on: bool):
			Global.menu_settings[t_key] = on
			Global.save_menu_settings()
			var tc := get_node_or_null("/root/TouchControls")
			if tc != null and tc.has_method("refresh_touch_settings"):
				tc.call("refresh_touch_settings")
		)
		trow.add_child(tsw)
		touch_grid.add_child(trow)

	var ctrl_row := HBoxContainer.new()
	ctrl_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ctrl_text := ("Режим пульта" if compact else "Режим пульта (вимкнути сенсорні стіки)") \
			if not is_en else ("Controller mode" if compact else "Controller-only mode (disable touch sticks)")
	var ctrl_lbl := _label(ctrl_text, 16 if compact else 18, MenuUI.TEXT)
	ctrl_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctrl_row.add_child(ctrl_lbl)
	var is_ctrl_locked := str(Global.menu_settings.get("touch_input_mode", "auto")).to_lower() == "controller"
	var ctrl_sw := ToggleSwitch.new(is_ctrl_locked)
	ctrl_sw.toggled.connect(func(on: bool):
		var tc := get_node_or_null("/root/TouchControls")
		if tc != null and tc.has_method("set_controller_only"):
			tc.call("set_controller_only", on)
		else:
			Global.menu_settings["touch_input_mode"] = "controller" if on else "auto"
			Global.save_menu_settings()
	)
	ctrl_row.add_child(ctrl_sw)
	sv.add_child(ctrl_row)

	var touch_layout_label := ("TOUCH LAYOUT" if is_en else "НАЛАШТУВАТИ HUD") \
			if compact else ("CUSTOMIZE TOUCH LAYOUT" if is_en \
			else "НАЛАШТУВАТИ РОЗТАШУВАННЯ HUD")
	var touch_layout_button := _button(touch_layout_label, 52, true)
	touch_layout_button.pressed.connect(_open_touch_layout_settings)
	sv.add_child(touch_layout_button)

	var sens_row := HBoxContainer.new()
	sens_row.add_theme_constant_override("separation", _gap(12))
	var sens_lbl := _label("Чутливість:" if compact else "Чутливість сенсора:",
			16 if compact else 18, MenuUI.TEXT)
	sens_lbl.custom_minimum_size.x = _fs(128 if compact else 210)
	sens_row.add_child(sens_lbl)
	var cur_sens := clampf(float(Global.menu_settings.get("touch_sensitivity", 1.0)), 0.4, 1.6)
	var sens_val_lbl := _label("%.2fx" % cur_sens, 16 if compact else 18, MenuUI.FPV_GREEN)
	sens_val_lbl.custom_minimum_size.x = _fs(48 if compact else 64)
	var sens_sl := _slider(cur_sens, 0.4, 1.6, 0.05, func(val: float):
		var v := clampf(val, 0.4, 1.6)
		sens_val_lbl.text = "%.2fx" % v
		Global.menu_settings["touch_sensitivity"] = v
		Global.save_menu_settings()
		var tc := get_node_or_null("/root/TouchControls")
		if tc != null and tc.has_method("refresh_touch_settings"):
			tc.call("refresh_touch_settings")
	)
	sens_row.add_child(sens_sl)
	sens_row.add_child(sens_val_lbl)
	sv.add_child(sens_row)

	var expo_row := HBoxContainer.new()
	expo_row.add_theme_constant_override("separation", _gap(12))
	var expo_lbl := _label("Експо:" if compact else "Експо сенсора:",
			16 if compact else 18, MenuUI.TEXT)
	expo_lbl.custom_minimum_size.x = _fs(128 if compact else 210)
	expo_row.add_child(expo_lbl)
	var cur_expo := clampf(float(Global.menu_settings.get("touch_expo", 0.2)), 0.0, 0.7)
	var expo_val_lbl := _label("%.2f" % cur_expo, 16 if compact else 18, MenuUI.FPV_GREEN)
	expo_val_lbl.custom_minimum_size.x = _fs(48 if compact else 64)
	var expo_sl := _slider(cur_expo, 0.0, 0.7, 0.05, func(val: float):
		var v := clampf(val, 0.0, 0.7)
		expo_val_lbl.text = "%.2f" % v
		Global.menu_settings["touch_expo"] = v
		Global.save_menu_settings()
		var tc := get_node_or_null("/root/TouchControls")
		if tc != null and tc.has_method("refresh_touch_settings"):
			tc.call("refresh_touch_settings")
	)
	expo_row.add_child(expo_sl)
	expo_row.add_child(expo_val_lbl)
	sv.add_child(expo_row)


func _open_touch_layout_settings() -> void:
	var touch := get_node_or_null("/root/TouchControls")
	if touch != null and touch.has_method("open_layout_editor"):
		touch.call("open_layout_editor", true)


func _refresh_sim_toggles() -> void:
	for key in _sim_toggles.keys():
		var sw: ToggleSwitch = _sim_toggles[key]
		sw.set_pressed_no_signal(bool(GameSettings.hud_config.get(key, true)))
		sw.queue_redraw()


func _build_settings_tab_hud() -> void:
	var compact := _vsize().x < 700.0
	var card := _panel(Color(0.025, 0.065, 0.05, 0.92), Color(0.38, 0.54, 0.42, 0.55), 1, 16)
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_body_container.add_child(card)
	_settings_panels["hud"] = card

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(scroll)
	var sv := VBoxContainer.new()
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.add_theme_constant_override("separation", _gap(14))
	scroll.add_child(sv)

	var hud_heading := ("HUD / OSD" if MenuUI.is_english() else "НАЛАШТУВАННЯ HUD / OSD") \
			if compact else ("COMBAT / FLIGHT HUD ELEMENTS" if MenuUI.is_english() \
			else "ЕЛЕМЕНТИ БОЙОВОГО ТА ПОЛЬОТНОГО ІНТЕРФЕЙСУ (HUD / OSD)")
	sv.add_child(_label(hud_heading, 18 if compact else 24, MenuUI.FPV_AMBER))

	# FPS Counter row (Toggle + Slider 5..60 + Number)
	var fps_row := HBoxContainer.new()
	fps_row.add_theme_constant_override("separation", _gap(12))
	var fps_lbl := _label("FPS:" if compact else ("FPS:" if MenuUI.is_english() else "Лічильник FPS:"),
			16 if compact else 18, MenuUI.TEXT)
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

	# HUD toggles use one column on phones so labels never disappear beyond the
	# portrait safe area.
	var grid := GridContainer.new()
	grid.columns = 1 if compact else 2
	grid.add_theme_constant_override("h_separation", _gap(24))
	grid.add_theme_constant_override("v_separation", _gap(10))
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.add_child(grid)

	var hud_items := [
		["ladder", "Шкала тангажу" if not compact else "Тангаж"],
		["speed", "Швидкість"],
		["altitude", "Висота"],
		["heading", "Курс"],
		["sticks", "Позиція стіків" if not compact else "Стіки"],
		["rpm", "Оберти моторів" if not compact else "Оберти"],
		["osd", "Увесь OSD (H)" if not compact else "Увесь OSD"],
		["fpv_rig", "FPV-обвіс: вусики + бомба (J)" if not compact else "FPV-обвіс"],
	]

	for item in hud_items:
		var key: String = item[0]
		var label_txt: String = item[1]
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var lbl := _label(label_txt, 16 if compact else 18, MenuUI.TEXT)
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

	var reset_hud_text := ("RESET HUD" if MenuUI.is_english() else "СКИНУТИ HUD") if compact \
			else ("RESET HUD TO DEFAULTS" if MenuUI.is_english() else "СКИНУТИ HUD ДО СТАНДАРТНИХ")
	var reset_hud_btn := _button(reset_hud_text, 44)
	reset_hud_btn.custom_minimum_size.x = _fs(140 if compact else 280)
	reset_hud_btn.pressed.connect(func():
		GameSettings.reset_hud_to_defaults()
		for k in _hud_toggles.keys():
			var sw: ToggleSwitch = _hud_toggles[k]
			sw.set_pressed_no_signal(bool(GameSettings.hud_config.get(k, true)))
			sw.queue_redraw()
	)
	sv.add_child(reset_hud_btn)


func _build_settings_tab_gfx() -> void:
	var compact := _vsize().x < 700.0
	var is_en := MenuUI.is_english()
	var card := _panel(Color(0.025, 0.065, 0.05, 0.92), Color(0.38, 0.54, 0.42, 0.55), 1, 16)
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_body_container.add_child(card)
	_settings_panels["gfx"] = card

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(scroll)
	var sv := VBoxContainer.new()
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.add_theme_constant_override("separation", _gap(14))
	scroll.add_child(sv)

	var gfx_heading := ("GRAPHICS / FPS" if is_en else "ГРАФІКА / FPS") if compact \
			else ("GRAPHICS & IPHONE 14 OPTIMIZATION" if is_en \
			else "ГРАФІКА ТА ОПТИМІЗАЦІЯ ДЛЯ IPHONE 14")
	sv.add_child(_label(gfx_heading, 18 if compact else 24, MenuUI.FPV_AMBER))

	# 3 Quality Presets Row
	var q_row: BoxContainer
	if compact:
		var q_vbox := VBoxContainer.new()
		q_vbox.add_theme_constant_override("separation", _gap(6))
		q_row = q_vbox
	else:
		var q_hbox := HBoxContainer.new()
		q_hbox.add_theme_constant_override("separation", _gap(10))
		q_row = q_hbox
	var cur_q := clampi(int(Graphics.graphics_settings.get("quality", 0)), 0, 2)
	var q_labels := [
		("LOW" if is_en else "НИЗЬКА") if compact else "1. НИЗЬКА (120+ FPS)",
		("MEDIUM" if is_en else "СЕРЕДНЯ") if compact else "2. СЕРЕДНЯ (БАЛАНС)",
		("HIGH" if is_en else "ВИСОКА") if compact else "3. ВИСОКА (МАКСИМУМ)",
	]
	var q_btns: Array[Button] = []
	for q_i in range(3):
		var q_btn := _button(q_labels[q_i], 42 if compact else 44, q_i == cur_q)
		q_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var target_q := q_i
		q_btn.pressed.connect(func():
			Graphics.apply_quality_preset(target_q)
			Graphics.save_graphics_settings()
			_refresh_gfx_tab()
		)
		q_row.add_child(q_btn)
		q_btns.append(q_btn)
	sv.add_child(q_row)

	var grid := GridContainer.new()
	grid.columns = 1 if compact else 2
	grid.add_theme_constant_override("h_separation", _gap(24))
	grid.add_theme_constant_override("v_separation", _gap(10))
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.add_child(grid)

	# FPV video channel dropdown
	var fpv_row := HBoxContainer.new()
	fpv_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fpv_row.add_child(_label(("FPV CHANNEL:" if is_en else "FPV-КАНАЛ:") if compact \
			else ("FPV video channel:" if is_en else "FPV-канал (відеолінк):"),
			16 if compact else 18, MenuUI.TEXT))
	var fpv_opt := OptionButton.new()
	fpv_opt.custom_minimum_size = Vector2(_fs(100 if compact else 190), _fs(40))
	_style_option_button(fpv_opt)
	var fpv_modes := ["ANALOG", "DIGITAL", "FLIR W", "FLIR B"] if compact \
			else ["Аналог 5.8 GHz", "Digital HD" if is_en else "Цифровий HD", "FLIR White-Hot", "FLIR Black-Hot"]
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
	res_row.add_child(_label(("RESOLUTION:" if is_en else "РОЗДІЛЬНІСТЬ:") if compact \
			else ("Resolution scale:" if is_en else "Масштаб роздільності:"),
			16 if compact else 18, MenuUI.TEXT))
	var res_opt := OptionButton.new()
	res_opt.custom_minimum_size = Vector2(_fs(96 if compact else 160), _fs(40))
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
	sh_row.add_child(_label(("SHADOWS:" if is_en else "ТІНІ:") if compact \
			else ("Shadow quality:" if is_en else "Якість тіней:"),
			16 if compact else 18, MenuUI.TEXT))
	var sh_opt := OptionButton.new()
	sh_opt.custom_minimum_size = Vector2(_fs(96 if compact else 160), _fs(40))
	_style_option_button(sh_opt)
	var sh_items := ["Вимкнено", "Низька", "Середня", "Висока", "Ультра"]
	for item in sh_items:
		sh_opt.add_item(item)
	sh_opt.selected = clampi(int(Graphics.graphics_settings.get("shadows", 1)), 0, 4)
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
	msaa_row.add_child(_label(("MSAA:" if is_en else "MSAA:") if compact \
			else ("Anti-aliasing (MSAA):" if is_en else "Згладжування (MSAA):"),
			16 if compact else 18, MenuUI.TEXT))
	var msaa_opt := OptionButton.new()
	msaa_opt.custom_minimum_size = Vector2(_fs(80 if compact else 160), _fs(40))
	_style_option_button(msaa_opt)
	var msaa_items := ["Вимкнено", "2x", "4x", "8x", "16x"]
	for item in msaa_items:
		msaa_opt.add_item(item)
	msaa_opt.selected = clampi(int(Graphics.graphics_settings.get("msaa", 0)), 0, 4)
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
	fish_row.add_child(_label(("LENS:" if is_en else "ОБ'ЄКТИВ:") if compact \
			else ("Fisheye lens:" if is_en else "FPV-об'єктив (риб'яче око):"),
			16 if compact else 18, MenuUI.TEXT))
	var fish_opt := OptionButton.new()
	fish_opt.custom_minimum_size = Vector2(_fs(88 if compact else 160), _fs(40))
	_style_option_button(fish_opt)
	var fish_items := ["OFF", "FULL", "FAST"] if compact else ["Вимкнено", "Повний", "Швидкий"]
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
	fps_lim_row.add_child(_label(("FPS LIMIT:" if is_en else "FPS ЛІМІТ:") if compact \
			else ("FPS limit:" if is_en else "Обмеження FPS:"),
			16 if compact else 18, MenuUI.TEXT))
	var fps_lim_opt := OptionButton.new()
	fps_lim_opt.custom_minimum_size = Vector2(_fs(100 if compact else 190), _fs(40))
	_style_option_button(fps_lim_opt)
	var fps_lim_vals := [0, 30, 60, 90, 120, 144]
	var fps_lim_items := ["UNLIMITED", "30", "60", "90", "120", "144"] if compact \
			else ["Без обмежень", "30", "60", "90", "120 (iPhone Pro)", "144"]
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
	vsync_row.add_child(_label(("V-SYNC" if is_en else "V-SYNC") if compact \
			else ("Vertical sync (V-Sync):" if is_en else "Вертикальна синхронізація (V-Sync):"),
			16 if compact else 18, MenuUI.TEXT))
	var vsync_sw := ToggleSwitch.new(bool(Graphics.graphics_settings.get("vsync", true)))
	vsync_sw.toggled.connect(func(on: bool):
		Graphics.graphics_settings["vsync"] = on
		Graphics.save_graphics_settings()
	)
	vsync_row.add_child(vsync_sw)
	grid.add_child(vsync_row)

	sv.add_child(_spacer(0, Control.SIZE_EXPAND_FILL))

	var reset_gfx_text := ("RESET GRAPHICS" if MenuUI.is_english() else "СКИНУТИ ГРАФІКУ") if compact \
			else ("RESET GRAPHICS TO DEFAULTS" if MenuUI.is_english() else "СКИНУТИ ГРАФІКУ ДО СТАНДАРТНИХ")
	var reset_gfx_btn := _button(reset_gfx_text, 48)
	reset_gfx_btn.custom_minimum_size.x = _fs(150 if compact else 280)
	reset_gfx_btn.pressed.connect(func():
		Graphics.reset_to_defaults()
		_refresh_gfx_tab()
	)
	sv.add_child(reset_gfx_btn)


func _refresh_gfx_tab() -> void:
	if _settings_panels.has("gfx") and is_instance_valid(_settings_panels["gfx"]):
		_settings_panels["gfx"].queue_free()
		_settings_panels.erase("gfx")
	_build_settings_tab_gfx()
	_switch_settings_tab()


func _build_settings_tab_sys() -> void:
	var compact := _vsize().x < 700.0
	var card := _panel(Color(0.025, 0.065, 0.05, 0.92), Color(0.38, 0.54, 0.42, 0.55), 1, 16)
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_body_container.add_child(card)
	_settings_panels["sys"] = card

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(scroll)

	var sv := VBoxContainer.new()
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.add_theme_constant_override("separation", _gap(14))
	scroll.add_child(sv)

	var is_en := MenuUI.is_english()
	var sys_heading := ("AUDIO / SYSTEM" if is_en else "ЗВУК / СИСТЕМА") if compact \
			else ("AUDIO & SYSTEM" if is_en else "ЗВУК ТА СИСТЕМА")
	sv.add_child(_label(sys_heading, 18 if compact else 24, MenuUI.FPV_AMBER))

	# 1. Master Volume
	var vol_box := VBoxContainer.new()
	vol_box.add_theme_constant_override("separation", _gap(6))
	var vol_hdr := HBoxContainer.new()
	vol_hdr.add_child(_label(("Volume" if is_en else "Гучність") if compact \
			else ("Master Audio Volume" if is_en else "Загальна гучність аудіо"),
			16 if compact else 20, MenuUI.TEXT))
	var cur_vol: float = round(float(Audio.audio_settings.get("master_volume", 1.0)) * 100.0)
	var vol_lbl := _label("%d%%" % int(cur_vol), 16 if compact else 20, MenuUI.FPV_GREEN)
	vol_lbl.custom_minimum_size.x = _fs(48 if compact else 60)
	vol_hdr.add_child(_spacer(0, Control.SIZE_EXPAND_FILL))
	vol_hdr.add_child(vol_lbl)
	vol_box.add_child(vol_hdr)
	vol_box.add_child(_label(("Motors, wind, radio & FX" if is_en else "Мотори, вітер, радіо й ефекти") if compact \
			else ("Controls motors, prop wash, wind, radio and effects" if is_en else "Регулює звук моторів FPV, свист гвинтів, вітер та ефекти"),
			12 if compact else 14, MenuUI.MUTED))

	var vol_slider := _slider(cur_vol, 0, 100, 1, func(val: float):
		vol_lbl.text = "%d%%" % int(val)
		Audio.audio_settings["master_volume"] = val / 100.0
		Audio.update_master_volume()
		Audio.save_audio_settings()
	)
	vol_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vol_box.add_child(vol_slider)
	sv.add_child(vol_box)

	# 1b. Sub-bus sliders (Engine, Wind, Combat, Radio, Warning)
	if Audio.has_method("set_subbus_volume_linear") and Audio.has_method("get_subbus_volume_linear"):
		var bus_names := [
			{"id": "Engine", "uk": "Мотори і пропелери (Engine)", "en": "Motors & Props (Engine)"},
			{"id": "Wind", "uk": "Вітер і турбулентність (Wind)", "en": "Wind & Airflow (Wind)"},
			{"id": "Combat", "uk": "Тактичні ефекти (Combat)", "en": "Tactical FX (Combat)"},
			{"id": "Radio", "uk": "Радіозв'язок / БІП (Radio)", "en": "Radio Comms / Beeps (Radio)"},
			{"id": "Warning", "uk": "Сигнали тривоги (Warning)", "en": "Low-Batt / Alerts (Warning)"},
		]
		var bus_grid := GridContainer.new()
		bus_grid.columns = 1 if compact else 2
		bus_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bus_grid.add_theme_constant_override("h_separation", _gap(16))
		bus_grid.add_theme_constant_override("v_separation", _gap(8))
		for entry in bus_names:
			var bid := str(entry["id"])
			var btitle := str(entry["en" if is_en else "uk"])
			if compact:
				btitle = str({
					"Engine": "ENGINE" if is_en else "МОТОРИ",
					"Wind": "WIND" if is_en else "ВІТЕР",
					"Combat": "COMBAT" if is_en else "БОЙОВІ",
					"Radio": "RADIO" if is_en else "РАДІО",
					"Warning": "ALERTS" if is_en else "ТРИВОГА",
				}.get(bid, btitle))
			var bval := roundf(float(Audio.get_subbus_volume_linear(bid)) * 100.0)
			var bv := VBoxContainer.new()
			bv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bv.add_theme_constant_override("separation", _gap(2))
			var bh := HBoxContainer.new()
			bh.add_child(_label(btitle, 14 if compact else 15, MenuUI.TEXT))
			bh.add_child(_spacer(0, Control.SIZE_EXPAND_FILL))
			var bl := _label("%d%%" % int(bval), 14 if compact else 15, MenuUI.FPV_CYAN)
			bh.add_child(bl)
			bv.add_child(bh)
			var bs := _slider(bval, 0, 100, 1, func(val: float):
				bl.text = "%d%%" % int(val)
				Audio.set_subbus_volume_linear(bid, val / 100.0)
			)
			bs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bv.add_child(bs)
			bus_grid.add_child(bv)
		sv.add_child(bus_grid)

	# 2. Haptics toggle
	var hap_box := HBoxContainer.new()
	var hap_info := VBoxContainer.new()
	hap_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hap_info.add_child(_label(("Haptics" if is_en else "Тактильний відгук") if compact \
			else ("Haptic Feedback (Vibration)" if is_en else "Тактильний відгук (Haptics / Вібрація)"),
			16 if compact else 20, MenuUI.TEXT))
	hap_info.add_child(_label(("Impact / landing vibration" if is_en else "Вібрація при ударах і посадці") if compact \
			else ("Taptic Engine feedback on G-force, landing and impacts" if is_en else "Вібрація Taptic Engine iPhone при перевантаженнях, торканні землі та вибухах"),
			12 if compact else 14, MenuUI.MUTED))
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
	safe_info.add_child(_label("Safe area" if compact else "iPhone Safe Area / Dynamic Island", 16 if compact else 20, MenuUI.TEXT))
	safe_info.add_child(_label(("Notch / home bar" if is_en else "Виріз / домашня панель") if compact \
			else ("Automatic insets for Notch, Dynamic Island and Home bar" if is_en else "Автоматичні поля від динамічного острова (Dynamic Island) та закруглень"),
			12 if compact else 14, MenuUI.MUTED))
	safe_box.add_child(safe_info)
	var sm := MenuUI.get_safe_margins(_vsize())
	var safe_tag_text := "ACTIVE" if is_en else "АКТИВНА"
	if not compact:
		safe_tag_text = ("ACTIVE (L%d T%d R%d B%d)" if is_en else "АКТИВНА (Л%d В%d П%d Н%d)") % [
			int(sm.get("left", 0)), int(sm.get("top", 0)),
			int(sm.get("right", 0)), int(sm.get("bottom", 0))]
	var safe_tag := _label(safe_tag_text, 16, MenuUI.FPV_GREEN)
	safe_box.add_child(safe_tag)
	sv.add_child(safe_box)

	# 5. Interactive Language Switcher (UA <-> EN)
	var lang_box := HBoxContainer.new()
	var lang_info := VBoxContainer.new()
	lang_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lang_info.add_child(_label(("Language" if is_en else "Мова інтерфейсу") if compact \
			else ("Interface & HUD Language" if is_en else "Мова інтерфейсу та HUD"),
			16 if compact else 20, MenuUI.TEXT))
	lang_info.add_child(_label(("Menus and HUD language" if is_en else "Мова меню та HUD") if compact \
			else ("Switch between Ukrainian and English across menus and telemetry" if is_en else "Перемикання української та англійської мов для меню, дронів та OSD"),
			12 if compact else 14, MenuUI.MUTED))
	lang_box.add_child(lang_info)
	var lang_btn := _button("EN / UA" if compact else ("ENGLISH (EN) → UA" if is_en else "УКРАЇНСЬКА (UA) → EN"), 42, true)
	lang_btn.custom_minimum_size = Vector2(_ui_sz(100 if compact else 230), _ui_sz(42))
	lang_btn.pressed.connect(func():
		Loc.toggle_language()
		MenuUI.localize_tree(self)
		call_deferred("_rebuild_screens")
	)
	lang_box.add_child(lang_btn)
	sv.add_child(lang_box)

	# 6. Pilot records / optional Game Center leaderboard hook
	var gc_box := HBoxContainer.new()
	var gc_info := VBoxContainer.new()
	gc_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var gc_sys_title := ("Game Center & Records" if Global.is_game_center_available() else "Pilot Records & Stats") \
			if is_en else ("Game Center та рекорди" if Global.is_game_center_available() else "Рекорди та статистика пілота")
	gc_info.add_child(_label(("Records" if is_en else "Рекорди") if compact else gc_sys_title,
			16 if compact else 20, MenuUI.TEXT))
	gc_info.add_child(_label(("Leaderboard" if is_en else "Таблиця лідерів") if compact \
			else Global.get_leaderboard_summary(is_en), 12 if compact else 14, MenuUI.MUTED))
	gc_box.add_child(gc_info)
	var gc_btn := _button(("OPEN" if is_en else "ВІДКРИТИ"), 40, false)
	gc_btn.icon = MenuIcons.icon_trophy(MenuUI.FPV_AMBER, 22)
	gc_btn.expand_icon = false
	gc_btn.add_theme_constant_override("h_separation", _gap(8))
	gc_btn.custom_minimum_size = Vector2(_ui_sz(88 if compact else 150), _ui_sz(40))
	gc_btn.pressed.connect(_open_mobile_records)
	gc_box.add_child(gc_btn)
	sv.add_child(gc_box)

	# 7. Radio chatter mode selector (Minimal: Start/End only vs Full vs Off)
	var rad_box := HBoxContainer.new()
	var rad_info := VBoxContainer.new()
	rad_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rad_info.add_child(_label(("Radio Chatter" if is_en else "Радіоефір у місіях") if compact \
			else ("Mission Radio Chatter Mode" if is_en else "Режим голосового радіоефіру в місіях"),
			16 if compact else 20, MenuUI.TEXT))
	rad_info.add_child(_label(("Start & end only / Full / Off" if is_en else "Лише старт і фініш / Повний / Вимк.") if compact \
			else ("Play voice callouts only at mission start and completion (no replay on respawn)" if is_en else "Озвучення лише на старті та в кінці місії (без повторів після респавну)"),
			12 if compact else 14, MenuUI.MUTED))
	rad_box.add_child(rad_info)
	var cur_rmode := int(Global.menu_settings.get("radio_chatter_mode", 2))
	var rmode_names_ua := ["ВИМК.", "СТАРТ / ФІНІШ", "ПОВНИЙ"]
	var rmode_names_en := ["OFF", "START / END", "FULL"]
	var rmode_arr := rmode_names_en if is_en else rmode_names_ua
	var rad_btn := _button(rmode_arr[clampi(cur_rmode, 0, 2)], 40, true)
	rad_btn.custom_minimum_size = Vector2(_ui_sz(115 if compact else 185), _ui_sz(40))
	rad_btn.pressed.connect(func():
		var next_m := (int(Global.menu_settings.get("radio_chatter_mode", 2)) + 1) % 3
		Global.menu_settings["radio_chatter_mode"] = next_m
		Global.save_menu_settings()
		var arr_now := rmode_names_en if MenuUI.is_english() else rmode_names_ua
		rad_btn.text = arr_now[next_m]
	)
	rad_box.add_child(rad_btn)
	sv.add_child(rad_box)

	# 8. Step-by-step ELRS Wi-Fi Connection Guide
	var elrs_box := HBoxContainer.new()
	var elrs_info := VBoxContainer.new()
	elrs_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	elrs_info.add_child(_label(("ELRS Wi-Fi Guide" if is_en else "Підключення ELRS Wi-Fi") if compact \
			else ("ELRS Wi-Fi & RC Transmitter Guide" if is_en else "Довідка: Як підключити пульт через ELRS Wi-Fi"),
			16 if compact else 20, MenuUI.TEXT))
	elrs_info.add_child(_label(("Step-by-step setup (UDP 14550)" if is_en else "Покрокова інструкція (UDP 14550)") if compact \
			else ("Step-by-step instructions to connect an ExpressLRS transmitter over Wi-Fi" if is_en else "Покрокова інструкція з підключення апаратури ExpressLRS по Wi-Fi"),
			12 if compact else 14, MenuUI.MUTED))
	elrs_box.add_child(elrs_info)
	var elrs_btn := _button("GUIDE" if is_en else "ІНСТРУКЦІЯ", 40, false)
	elrs_btn.custom_minimum_size = Vector2(_ui_sz(96 if compact else 155), _ui_sz(40))
	elrs_btn.pressed.connect(_open_elrs_guide_modal)
	elrs_box.add_child(elrs_btn)
	sv.add_child(elrs_box)


func _open_elrs_guide_modal() -> void:
	var existing := get_node_or_null("MobileElrsGuideModal")
	if existing != null:
		existing.queue_free()
	var is_en := MenuUI.is_english()
	var backdrop := ColorRect.new()
	backdrop.name = "MobileElrsGuideModal"
	backdrop.color = Color(0.01, 0.02, 0.02, 0.94)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.z_index = 95
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var sm := MenuUI.get_safe_margins(_vsize())
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", int(sm["left"]) + _gap(28))
	margin.add_theme_constant_override("margin_right", int(sm["right"]) + _gap(28))
	margin.add_theme_constant_override("margin_top", int(sm["top"]) + _gap(18))
	margin.add_theme_constant_override("margin_bottom", int(sm["bottom"]) + _gap(18))
	backdrop.add_child(margin)

	var card := _panel(Color(0.02, 0.055, 0.045, 0.99), MenuUI.FPV_CYAN, 2, 18)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", _gap(10))
	card.add_child(vbox)

	var hdr := HBoxContainer.new()
	var title := _label(
		"HOW TO CONNECT RC TRANSMITTER VIA ELRS Wi-Fi" if is_en else "ЯК ПІДКЛЮЧИТИ ПУЛЬТ ЧЕРЕЗ ELRS Wi-Fi",
		20, MenuUI.FPV_AMBER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(title)
	var close_btn := _button("CLOSE" if is_en else "ЗАКРИТИ", 38, true)
	close_btn.custom_minimum_size = Vector2(_ui_sz(125), _ui_sz(38))
	close_btn.pressed.connect(func(): backdrop.queue_free())
	hdr.add_child(close_btn)
	vbox.add_child(hdr)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var guide_txt := (
		"1. УВІМКНІТЬ Wi-Fi НА ПЕРЕДАВАЧІ (ELRS):\n"
		+ "   • Відкрийте системне меню скриптів на пульті → ExpressLRS → WiFi Connectivity → Enable WiFi.\n"
		+ "   • На екрані пульта з'явиться повідомлення WiFi Running (IP: 10.0.0.1).\n\n"
		+ "2. ПІДКЛЮЧІТЬ ТЕЛЕФОН / ПЛАНШЕТ ДО МЕРЕЖІ ПУЛЬТА:\n"
		+ "   • Відкрийте Налаштування iOS → Wi-Fi та оберіть мережу «ExpressLRS TX».\n"
		+ "   • Стандартний пароль мережі: expresslrs\n\n"
		+ "3. ДОЗВІЛ «ЛОКАЛЬНА МЕРЕЖА» В iOS:\n"
		+ "   • При першому запуску дозвольте грі пошук пристроїв у локальній мережі (Налаштування → Небесний горизонт → Локальна мережа: УВІМК).\n\n"
		+ "4. АВТОМАТИЧНИЙ ПРИЙОМ КАНАЛІВ (CRSF / UDP 14550):\n"
		+ "   • Відкрийте розділ «ПУЛЬТ ТА ELRS» у грі. При русі стіків індикатори ГАЗ / РИСКАННЯ / ТАНГАЖ / КРЕН та 3D-модель пульта реагуватимуть у реальному часі.\n"
		+ "   • Натисніть «КАЛІБРУВАТИ СТІКИ» для точного центрування осей.\n\n"
		+ "5. СТАНДАРТНА СХЕМА КАНАЛІВ Mode 2 (AETR):\n"
		+ "   • CH1: Крен (Roll)  |  CH2: Тангаж (Pitch)  |  CH3: Газ (Throttle)  |  CH4: Рискання (Yaw)\n"
		+ "   • CH5 (SA): Армування двигунів (ARM)\n"
		+ "   • CH6 (SB): Перемикання режимів польоту (ANGLE / HORIZON / ACRO)\n"
		+ "   • CH7 (SC): Скид корисного навантаження (DROP)\n"
		+ "   • CH8 (SD): Підрив бойової частини (DETONATE)"
	) if not is_en else (
		"1. ENABLE Wi-Fi ON YOUR RC TRANSMITTER (ELRS):\n"
		+ "   • Open the system tools menu on your radio → ExpressLRS → WiFi Connectivity → Enable WiFi.\n"
		+ "   • The transmitter screen will show WiFi Running (IP: 10.0.0.1).\n\n"
		+ "2. CONNECT YOUR iPHONE / iPAD TO THE TRANSMITTER Wi-Fi:\n"
		+ "   • Open iOS Settings → Wi-Fi and join the “ExpressLRS TX” network.\n"
		+ "   • Default Wi-Fi password: expresslrs\n\n"
		+ "3. iOS LOCAL NETWORK PERMISSION:\n"
		+ "   • Allow Local Network access when prompted (or enable it in iOS Settings → NebesnyiHorizont → Local Network).\n\n"
		+ "4. AUTOMATIC CHANNEL STREAMING (CRSF / UDP 14550):\n"
		+ "   • Open “RADIO & ELRS” in the game. Moving your physical sticks will immediately animate the 3D transmitter and live channel bars.\n"
		+ "   • Tap “CALIBRATE STICKS” to center and scale all axes.\n\n"
		+ "5. STANDARD Mode 2 (AETR) CHANNEL MAPPING:\n"
		+ "   • CH1: Roll  |  CH2: Pitch  |  CH3: Throttle  |  CH4: Yaw\n"
		+ "   • CH5 (SA): Arm Motors (ARM)\n"
		+ "   • CH6 (SB): Cycle Flight Modes (ANGLE / HORIZON / ACRO)\n"
		+ "   • CH7 (SC): Payload Drop (DROP)\n"
		+ "   • CH8 (SD): Warhead Detonate (DETONATE)"
	)
	var body_lbl := _label(guide_txt, 15, MenuUI.TEXT)
	body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body_lbl)


## Rebuild every menu screen in place after a layout/presentation change.
## (accessibility font scale).  Deferred so the triggering control is no
## longer in its signal callback when its subtree is freed.
func _rebuild_screens() -> void:
	if _content == null:
		return
	var keep := _current if _screens.has(_current) else "main"
	for c in _content.get_children():
		c.free()
	_screens.clear()
	_settings_panels.clear()
	_settings_tab_buttons.clear()
	_build_main()
	_build_play()
	_build_controls()
	_build_rates()
	_build_drone()
	_build_settings()
	_show(keep)
	_update_status()


func _spacer(height: float, flags: int = Control.SIZE_SHRINK_CENTER) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = _fs(height)
	c.size_flags_vertical = flags
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _exit_tree() -> void:
	var vp := get_viewport()
	if vp != null and vp.size_changed.is_connected(_on_mobile_viewport_resized):
		vp.size_changed.disconnect(_on_mobile_viewport_resized)
	if _prefetch_timer != null and is_instance_valid(_prefetch_timer):
		_prefetch_timer.stop()
		_prefetch_timer.queue_free()
		_prefetch_timer = null
	if _hero_holder != null and is_instance_valid(_hero_holder):
		for c in _hero_holder.get_children():
			if is_instance_valid(c):
				c.queue_free()
	if _hangar_holder != null and is_instance_valid(_hangar_holder):
		for c in _hangar_holder.get_children():
			if is_instance_valid(c):
				c.queue_free()
	if _loading_layer != null and is_instance_valid(_loading_layer):
		_loading_layer.queue_free()
		_loading_layer = null
	_screens.clear()
	_settings_panels.clear()
	_settings_tab_buttons.clear()
