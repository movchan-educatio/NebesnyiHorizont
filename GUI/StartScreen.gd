## FPV home screen: intro video, aligned navigation rail, and flight-mode tabs.
##
## The whole UI is authored on a fixed 1920x1080 design canvas and uniformly
## scaled into the real viewport.  That keeps every panel, label and button on
## the same grid at 720p, 1080p, 1440p and ultrawide resolutions.
extends Control

const MAIN_MENU := "res://GUI/MainMenu.tscn"
const MOBILE_MENU := "res://GUI/mobile/MobileMenu.tscn"
const DRONE_HANGAR := "res://GUI/DroneSelectScreen.tscn"
const OPTIONS_SCENE := "res://GUI/OptionsMenu.tscn"
const LEVEL := "res://sceneries/CourseLevel.tscn"
const CombatSfxScript = preload("res://combat/sfx.gd")

const DESIGN_SIZE := Vector2(1920.0, 1080.0)

const QA_ENV := ["DRONE_AUTOTEST", "DRONE_AUTOTEST_COMBAT", "DRONE_AUTOTEST_INFANTRY",
		"DRONE_CLEAR_RANGE", "DRONE_SCREENSHOT", "DRONE_SHOWCASE",
		"DRONE_COMBAT_DEMO", "DRONE_AA_DEMO", "DRONE_RESULTS_DEMO",
		"DRONE_INFANTRY_DEMO", "DRONE_RESTART_TEST", "DRONE_WALK_DEMO",
		"DRONE_FPS_BENCH", "DRONE_FLYTEST", "DRONE_PREWARM_TEST", "DRONE_SHOT_TEST",
		# DebugShot captures whatever scene is running, so a screenshot request
		# must skip the cinematic home screen just like the other QA runners.
		"SHOT_PATH"]

var _menu_music: AudioStreamPlayer = null
var _brand_project: Label = null
var _brand_title: Label = null
var _brand_subtitle: Label = null
var _status_label: Label = null
var _mode_prompt: Label = null
var _ui_layer: Control = null
var _design_root: Control = null
var _nav_entries: Array[Dictionary] = []
var _mode_buttons: Dictionary = {}
var _mode_summary: Label = null
var _selected_home_mode: int = Global.PlayMode.TUTORIAL
var _options_overlay: Control = null
var _lang_btn: Button = null
var _mode_bar_heading: Label = null
var _home_action_btn: Button = null
var _quick_tut_btn: Button = null
var _quick_ct_btn: Button = null
var _daily_badge_lbl: Label = null
var _news_heading: Control = null
var _news_labels: Array[Label] = []
var _author_lbl: Label = null
var _nav_heading: Control = null
var _social_btns: Array[Button] = []


## Small monochrome vector icons keep the navigation rows visually identical
## regardless of which emoji font happens to be installed on the machine.
class _MenuIcon extends Control:
	var kind: String = "drone"
	var icon_color: Color = Color.WHITE

	func _init(p_kind: String, p_color: Color) -> void:
		kind = p_kind
		icon_color = p_color
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(30, 28)

	func _draw() -> void:
		var c := Vector2(size.x * 0.5, size.y * 0.5)
		var col := icon_color
		match kind:
			"drone":
				var r := 5.2
				for p in [Vector2(-9, -7), Vector2(9, -7), Vector2(-9, 7), Vector2(9, 7)]:
					draw_arc(c + p, r, 0.0, TAU, 18, col, 1.7)
				draw_line(c + Vector2(-9, -7), c + Vector2(9, 7), col, 1.5)
				draw_line(c + Vector2(9, -7), c + Vector2(-9, 7), col, 1.5)
				draw_rect(Rect2(c - Vector2(4, 3), Vector2(8, 6)), col, false, 1.5)
			"hangar":
				draw_polyline(PackedVector2Array([
					c + Vector2(-11, -1), c + Vector2(0, -9), c + Vector2(11, -1)
				]), col, 1.8)
				draw_line(c + Vector2(-10, -1), c + Vector2(-10, 9), col, 1.8)
				draw_line(c + Vector2(10, -1), c + Vector2(10, 9), col, 1.8)
				draw_line(c + Vector2(-10, 9), c + Vector2(10, 9), col, 1.8)
				draw_rect(Rect2(c + Vector2(-4, 4), Vector2(8, 5)), col, false, 1.5)
			"gear":
				draw_arc(c, 7.5, 0.0, TAU, 24, col, 1.8)
				draw_circle(c, 2.2, col)
				for i in range(8):
					var a := TAU * float(i) / 8.0
					var d := Vector2(cos(a), sin(a))
					draw_line(c + d * 8.0, c + d * 11.5, col, 1.8)
			"power":
				draw_arc(c, 8.5, -PI * 0.35, PI * 1.35, 24, col, 1.9)
				draw_line(c + Vector2(0, -11), c + Vector2(0, 2), col, 1.9)
			"phone":
				draw_rect(Rect2(c - Vector2(6, 10), Vector2(12, 20)), col, false, 1.6)
				draw_line(c + Vector2(-2, 6), c + Vector2(2, 6), col, 1.5)
				draw_line(c + Vector2(-2, -7), c + Vector2(2, -7), col, 1.5)
			_:
				draw_set_transform(c, PI * 0.25, Vector2.ONE)
				draw_rect(Rect2(Vector2(-8, -8), Vector2(16, 16)), col, false, 1.6)
				draw_rect(Rect2(Vector2(-3.5, -3.5), Vector2(7, 7)), col, false, 1.3)


func _ready() -> void:
	if OS.has_environment("UI_SHOT_QA"):
		return
	# Headless/QA runs expect the level, not the menu: jump straight there.
	if _is_qa_session():
		if OS.get_environment("DRONE_PLAY_MODE").is_empty():
			Global.play_mode = Global.PlayMode.COMBAT
		var bench_level := OS.get_environment("DRONE_BENCH_LEVEL")
		get_tree().change_scene_to_file.call_deferred(
				bench_level if not bench_level.is_empty() else LEVEL)
		return
	# Phones boot straight into the finger-sized tactical menu.  The desktop
	# keeps the cinematic video home screen.
	if MenuUI.is_mobile_ui() or OS.has_feature("ios") or OS.get_name() == "iOS":
		_initialize_settings()
		get_tree().change_scene_to_file.call_deferred(MOBILE_MENU)
		return
	theme = MenuUI.theme()
	_initialize_settings()
	_selected_home_mode = Global.sanitize_play_mode(Global.play_mode)
	Global.play_mode = _selected_home_mode
	_start_menu_music()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().paused = false
	_build()
	_refresh_home_language()
	MenuUI.localize_tree(self)


func _initialize_settings() -> void:
	if Global.startup:
		Global.initialize()
	# `Global._ready()` already consumed `startup` before this screen exists, so
	# the settings must load unconditionally.  The old guard meant Graphics.cfg
	# (fullscreen, quality, FPV effects) and Audio.cfg were never applied on a
	# normal launch.
	GameSettings.load_hud_config()
	Graphics.load_graphics_settings()
	Audio.load_audio_settings()
	Controls.load_input_map(true)
	KeyboardControls.ensure_bindings()
	Global.load_menu_settings()


func _build() -> void:
	add_child(MenuUI.background(MenuUI.FPV_BG, false))

	var tint := ColorRect.new()
	tint.color = Color(0.008, 0.018, 0.012, 0.40)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MenuUI.full_rect(tint)
	add_child(tint)
	var left_fade := TextureRect.new()
	left_fade.texture = _make_horizontal_fade()
	left_fade.stretch_mode = TextureRect.STRETCH_SCALE
	left_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MenuUI.full_rect(left_fade)
	add_child(left_fade)

	_build_home_overlay()
	_refresh_home_language()
	MenuUI.localize_tree(self)
	get_viewport().size_changed.connect(_layout_design)
	# Keyboard/gamepad users need a visible initial focus; mouse hover used to
	# be the only path into the navigation rail.
	if not _nav_entries.is_empty():
		(_nav_entries[0]["button"] as Button).grab_focus()


func _build_home_overlay() -> void:
	# Fixed 1920x1080 authoring canvas, uniformly scaled into the viewport.
	_design_root = Control.new()
	_design_root.size = DESIGN_SIZE
	_design_root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_design_root)
	_layout_design()

	# --- Brand block: centred masthead, as in the approved layout sketch ----
	var mark := _MenuIcon.new("logo", MenuUI.FPV_CYAN)
	_place(mark, Rect2(945, 22, 30, 30))
	_design_root.add_child(mark)

	_brand_project = Label.new()
	_brand_project.add_theme_font_size_override("font_size", 13)
	_brand_project.add_theme_color_override("font_color", Color(0.72, 0.77, 0.73))
	_brand_project.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_brand_project, Rect2(610, 58, 700, 20))
	_design_root.add_child(_brand_project)

	_brand_title = Label.new()
	_brand_title.add_theme_font_size_override("font_size", 42)
	_brand_title.add_theme_color_override("font_color", MenuUI.FPV_TEXT)
	_brand_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_brand_title, Rect2(460, 78, 1000, 54))
	_design_root.add_child(_brand_title)

	_brand_subtitle = Label.new()
	_brand_subtitle.add_theme_font_size_override("font_size", 13)
	_brand_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_brand_subtitle.add_theme_color_override("font_color", MenuUI.FPV_GREEN)
	_place(_brand_subtitle, Rect2(460, 136, 1000, 22))
	_design_root.add_child(_brand_subtitle)

	_lang_btn = MenuUI.feel_button("🌐 UA / EN", 38, false)
	_lang_btn.add_theme_font_size_override("font_size", 14)
	_lang_btn.pressed.connect(_on_toggle_language)
	_place(_lang_btn, Rect2(1748, 22, 132, 38))
	_design_root.add_child(_lang_btn)

	# --- Left navigation rail ------------------------------------------------
	var nav_panel := PanelContainer.new()
	nav_panel.add_theme_stylebox_override("panel",
			MenuUI.feel_style(Color(0.025, 0.04, 0.03, 0.88), MenuUI.FPV_BORDER, 1, 2, 12, 12))
	# Large left navigation block, as in the sketch: title above, menu below.
	_place(nav_panel, Rect2(38, 214, 470, 566))
	_design_root.add_child(nav_panel)

	var nav_margin := MarginContainer.new()
	for side in ["left", "right"]:
		nav_margin.add_theme_constant_override("margin_%s" % side, 18)
	for side in ["top", "bottom"]:
		nav_margin.add_theme_constant_override("margin_%s" % side, 18)
	nav_panel.add_child(nav_margin)
	var nav_box := VBoxContainer.new()
	nav_box.add_theme_constant_override("separation", 12)
	nav_margin.add_child(nav_box)

	var nav_heading := MenuUI.section("ГОЛОВНЕ МЕНЮ", "FPV")
	nav_heading.custom_minimum_size = Vector2(0, 34)
	if nav_heading.get_child_count() > 1 and nav_heading.get_child(1) is Label:
		(nav_heading.get_child(1) as Label).add_theme_font_size_override("font_size", 20)
	nav_box.add_child(nav_heading)

	_nav_entries.clear()
	_nav_entries.append(_make_nav_entry(
		"ОДИНОЧНА ГРА", "SINGLE PLAYER",
		"ВИЛІТ · МІСІЇ", "SORTIE · MISSIONS",
		"drone", true, _on_start_pressed))
	_nav_entries.append(_make_nav_entry(
		"АНГАР", "HANGAR",
		"ГОТОВІ ДРОНИ", "READY AIRCRAFT",
		"hangar", false, _open_hangar))
	_nav_entries.append(_make_nav_entry(
		"НАЛАШТУВАННЯ", "SETTINGS",
		"ГРАФІКА · КЕРУВАННЯ", "GRAPHICS · CONTROLS",
		"gear", false, _open_options))
	_nav_entries.append(_make_nav_entry(
		"МОБІЛЬНИЙ РЕЖИМ", "MOBILE UI",
		"IPHONE 14 ІНТЕРФЕЙС", "IPHONE 14 UI",
		"phone", false, func():
			get_tree().change_scene_to_file.call_deferred(MOBILE_MENU)
	))
	if OS.get_name() != "iOS":
		_nav_entries.append(_make_nav_entry(
			"ВИХІД", "QUIT",
			"ЗАВЕРШИТИ ГРУ", "QUIT THE GAME",
			"power", false, _on_quit_pressed))
	for entry in _nav_entries:
		nav_box.add_child(entry["button"])

	# --- Mode selector, news, action and contacts ---------------------------
	_mode_prompt = Label.new()
	_mode_prompt.add_theme_font_size_override("font_size", 14)
	_mode_prompt.add_theme_color_override("font_color", Color(0.68, 0.74, 0.70))
	_place(_mode_prompt, Rect2(580, 184, 900, 22))
	_design_root.add_child(_mode_prompt)

	_build_home_mode_bar()
	_build_news_panel()
	_build_home_action()
	_build_social_bar()

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", MenuUI.FPV_MUTED)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_place(_status_label, Rect2(38, 1022, 620, 22))
	_design_root.add_child(_status_label)


func _build_home_mode_bar() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
			MenuUI.feel_style(Color(0.025, 0.04, 0.03, 0.82), MenuUI.FPV_BORDER, 1, 2, 20, 18))
	_place(panel, Rect2(560, 214, 1320, 150))
	_design_root.add_child(panel)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	panel.add_child(content)
	_mode_bar_heading = MenuUI.body("РЕЖИМ ПОЛЬОТУ", 15, Color(0.70, 0.76, 0.72))
	content.add_child(_mode_bar_heading)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	content.add_child(row)

	var modes := [
		{"id": Global.PlayMode.TUTORIAL, "title": "ТУТОРІАЛ", "en": "TUTORIAL"},
		{"id": Global.PlayMode.TRAINING, "title": "ФРІСТАЙЛ", "en": "FREESTYLE"},
		{"id": Global.PlayMode.COMBAT, "title": "БОЙОВИЙ РЕЖИМ", "en": "COMBAT MODE"}
	]
	_mode_buttons.clear()
	for entry in modes:
		var mode := int(entry["id"])
		var button := _make_home_mode_button(str(entry["title"]), mode)
		button.set_meta("title_uk", str(entry["title"]))
		button.set_meta("title_en", str(entry["en"]))
		row.add_child(button)
		_mode_buttons[mode] = button

	_mode_summary = MenuUI.body("", 22, MenuUI.FPV_TEXT)
	_place(_mode_summary, Rect2(580, 378, 1280, 62))
	_mode_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_design_root.add_child(_mode_summary)
	_refresh_home_mode()


func _make_home_mode_button(title: String, mode: int) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = Vector2(0, 54)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_stylebox_override("normal", MenuUI.feel_style(
			MenuUI.BUTTON_BG, MenuUI.FPV_BORDER, 1, 1, 10, 6))
	button.add_theme_stylebox_override("hover", MenuUI.feel_style(
			MenuUI.BUTTON_HOVER, MenuUI.FPV_GREEN, 2, 1, 10, 6))
	button.add_theme_stylebox_override("pressed", MenuUI.feel_style(
			MenuUI.BUTTON_ACTIVE, MenuUI.FPV_GREEN, 2, 1, 10, 6))
	button.add_theme_color_override("font_color", MenuUI.BUTTON_TEXT)
	button.add_theme_color_override("font_hover_color", MenuUI.BUTTON_TEXT)
	button.pressed.connect(_select_home_mode.bind(mode))
	return button


func _select_home_mode(mode: int) -> void:
	_selected_home_mode = Global.sanitize_play_mode(mode)
	Global.play_mode = _selected_home_mode
	_refresh_home_mode()


func _refresh_home_mode() -> void:
	if _mode_summary == null:
		return
	var is_en := MenuUI.is_english()
	var description := ""
	match _selected_home_mode:
		Global.PlayMode.TUTORIAL:
			if is_en:
				description = "Tutorial (Recommended first): 10 modules — sticks, arm, throttle, yaw, gates, braking and landing."
			else:
				description = "Туторіал (перший політ): 10 модулів — стіки, армінг, газ, рискання, ворота, гальмування й посадка."
			if Global.should_use_gentle_angle_assist():
				description += ("  [Angle Assist ON]" if is_en else "  [М’яка стабілізація Angle]")
		Global.PlayMode.TRAINING:
			var sel_map := str(Global.menu_settings.get("selected_map", "uman"))
			var rec := Global.get_training_record(sel_map)
			var best_suffix := ""
			if bool(rec.get("completed", false)):
				best_suffix = ("  · Best: %.1fs (Rank %s)" if is_en else "  · Рекорд: %.1f с (Ранг %s)") % [float(rec.get("best_time", 0.0)), str(rec.get("rank", rec.get("best_rank", "B")))]
			description = ("Freestyle flight, stick calibration, and timed checkpoint course with Ghost replay." if is_en else "Вільний фрістайл, калібрування, траса на час із записом Привида.") + best_suffix
		_:
			description = "Select a tactical scenario, configure drone loadout, and prepare for launch." if is_en else "Оберіть тактичний сценарій та підготуйте дрон до вильоту."
	_mode_summary.text = description
	for mode in _mode_buttons:
		var button := _mode_buttons[mode] as Button
		button.text = str(button.get_meta("title_en" if is_en else "title_uk", button.text))
		var active := int(mode) == _selected_home_mode
		button.add_theme_stylebox_override("normal", MenuUI.feel_style(
			MenuUI.BUTTON_ACTIVE if active else MenuUI.BUTTON_BG,
			MenuUI.FPV_GREEN if active else MenuUI.FPV_BORDER,
			2 if active else 1, 1, 10, 6))
		var hover_bg := MenuUI.BUTTON_ACTIVE.lightened(0.08) if active else MenuUI.BUTTON_HOVER
		button.add_theme_stylebox_override("hover", MenuUI.feel_style(hover_bg, MenuUI.FPV_GREEN, 2, 1, 10, 6))
		button.add_theme_stylebox_override("focus", MenuUI.feel_style(hover_bg, MenuUI.FPV_GREEN, 2, 1, 10, 6))
		button.add_theme_color_override("font_color",
			MenuUI.BUTTON_ACTIVE_TEXT if active else MenuUI.BUTTON_TEXT)
		button.add_theme_color_override("font_hover_color",
			MenuUI.BUTTON_ACTIVE_TEXT if active else MenuUI.BUTTON_TEXT)


func _build_home_action() -> void:
	_home_action_btn = MenuUI.feel_button("ПЕРЕЙТИ ДО МІСІЙ", 80, true)
	_home_action_btn.add_theme_font_size_override("font_size", 27)
	_home_action_btn.add_theme_stylebox_override("normal",
			MenuUI.feel_style(MenuUI.BUTTON_ACTIVE, MenuUI.FPV_GREEN, 2, 1, 18, 10))
	_home_action_btn.add_theme_stylebox_override("hover",
			MenuUI.feel_style(MenuUI.BUTTON_ACTIVE.lightened(0.08), MenuUI.FPV_GREEN, 2, 1, 18, 10))
	_home_action_btn.add_theme_stylebox_override("pressed",
			MenuUI.feel_style(MenuUI.BUTTON_ACTIVE.darkened(0.08), MenuUI.FPV_GREEN, 2, 1, 18, 10))
	_home_action_btn.add_theme_stylebox_override("focus",
			MenuUI.feel_style(MenuUI.BUTTON_ACTIVE.lightened(0.08), MenuUI.FPV_GREEN, 2, 1, 18, 10))
	_home_action_btn.pressed.connect(_on_start_pressed)
	_design_root.add_child(_home_action_btn)

	if not Global.is_tutorial_completed():
		_quick_tut_btn = MenuUI.feel_button("▶ ШВИДКИЙ СТАРТ: ТУТОРІАЛ", 80, false)
		_quick_tut_btn.add_theme_font_size_override("font_size", 21)
		_quick_tut_btn.add_theme_stylebox_override("normal",
				MenuUI.feel_style(Color(0.06, 0.16, 0.20, 0.95), MenuUI.FPV_CYAN, 2, 1, 18, 10))
		_quick_tut_btn.add_theme_stylebox_override("hover",
				MenuUI.feel_style(Color(0.10, 0.22, 0.28, 0.98), MenuUI.FPV_CYAN, 2, 1, 18, 10))
		_quick_tut_btn.add_theme_stylebox_override("focus",
				MenuUI.feel_style(Color(0.10, 0.22, 0.28, 0.98), MenuUI.FPV_CYAN, 2, 1, 18, 10))
		_quick_tut_btn.add_theme_color_override("font_color", MenuUI.FPV_CYAN)
		_quick_tut_btn.add_theme_color_override("font_hover_color", Color.WHITE)
		_quick_tut_btn.pressed.connect(_on_quick_tutorial_pressed)
		_place(_home_action_btn, Rect2(560, 800, 740, 84))
		_place(_quick_tut_btn, Rect2(1320, 800, 560, 84))
		_design_root.add_child(_quick_tut_btn)
	else:
		_place(_home_action_btn, Rect2(560, 800, 1320, 84))

	# Always-available first-strike training.  It is deliberately separate from
	# the campaign mode tabs and never writes campaign mission records.
	_quick_ct_btn = MenuUI.feel_button("🎯 БОЙОВЕ ТРЕНУВАННЯ: 3 КРОКИ", 58, false)
	_quick_ct_btn.add_theme_font_size_override("font_size", 19)
	_quick_ct_btn.add_theme_stylebox_override("normal",
			MenuUI.feel_style(Color(0.16, 0.11, 0.04, 0.94), MenuUI.WARN_AMBER, 2, 1, 18, 10))
	_quick_ct_btn.add_theme_stylebox_override("hover",
			MenuUI.feel_style(Color(0.24, 0.17, 0.06, 0.98), MenuUI.WARN_AMBER, 2, 1, 18, 10))
	_quick_ct_btn.add_theme_stylebox_override("focus",
			MenuUI.feel_style(Color(0.24, 0.17, 0.06, 0.98), MenuUI.WARN_AMBER, 2, 1, 18, 10))
	_quick_ct_btn.add_theme_color_override("font_color", MenuUI.WARN_AMBER)
	_quick_ct_btn.add_theme_color_override("font_hover_color", Color.WHITE)
	_quick_ct_btn.pressed.connect(_on_quick_combat_training_pressed)
	_place(_quick_ct_btn, Rect2(660, 896, 1120, 58))
	_design_root.add_child(_quick_ct_btn)


func _build_news_panel() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
			MenuUI.feel_style(Color(0.025, 0.04, 0.03, 0.84), MenuUI.FPV_BORDER, 1, 2, 20, 18))
	_place(panel, Rect2(560, 462, 1320, 314))
	_design_root.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	_news_heading = MenuUI.section("БРИФІНГ СИМУЛЯТОРА", "SIM BRIEFING")
	_news_heading.custom_minimum_size = Vector2(0, 32)
	vb.add_child(_news_heading)

	_daily_badge_lbl = MenuUI.body("", 15, MenuUI.FPV_CYAN)
	_daily_badge_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_daily_badge_lbl)

	_news_labels.clear()
	for _i in range(5):
		var l := MenuUI.body("", 14, Color(0.84, 0.89, 0.85))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(l)
		_news_labels.append(l)

	_author_lbl = MenuUI.body("Автор: Сергій · @matilda.poetry", 13, MenuUI.WARN_AMBER)
	vb.add_child(_author_lbl)


func _build_social_bar() -> void:
	var tiktok := Label.new()
	tiktok.text = "TikTok: @matilda.poetry"
	tiktok.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tiktok.add_theme_font_size_override("font_size", 13)
	tiktok.add_theme_color_override("font_color", Color(0.78, 0.84, 0.80))
	_place(tiktok, Rect2(720, 1018, 480, 24))
	_design_root.add_child(tiktok)

	var socials := [
		["Instagram", "https://www.instagram.com/matilda.poetry"],
		["TikTok", "https://www.tiktok.com/@matilda.poetry"],
		["Facebook", "https://www.facebook.com/share/1MDqKqW2rE/"],
	]
	var x := 1330.0
	for entry in socials:
		var b := Button.new()
		b.text = str(entry[0])
		b.tooltip_text = "Відкрити " + str(entry[0])
		b.focus_mode = Control.FOCUS_ALL
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.add_theme_font_size_override("font_size", 14)
		b.add_theme_color_override("font_color", MenuUI.BUTTON_TEXT)
		b.add_theme_color_override("font_hover_color", MenuUI.BUTTON_TEXT)
		b.add_theme_stylebox_override("normal",
				MenuUI.feel_style(MenuUI.BUTTON_BG, MenuUI.FPV_BORDER, 1, 1, 10, 5))
		b.add_theme_stylebox_override("hover",
				MenuUI.feel_style(MenuUI.BUTTON_HOVER, MenuUI.FPV_GREEN, 2, 1, 10, 5))
		b.add_theme_stylebox_override("focus",
				MenuUI.feel_style(MenuUI.BUTTON_HOVER, MenuUI.FPV_GREEN, 2, 1, 10, 5))
		b.pressed.connect(_open_url.bind(str(entry[1])))
		_place(b, Rect2(x, 1006, 172, 40))
		_design_root.add_child(b)
		x += 184.0


func _open_url(url: String) -> void:
	if url.is_empty():
		return
	OS.shell_open(url)


func _make_nav_entry(uk_title: String, en_title: String, uk_desc: String,
		en_desc: String, icon: String, primary: bool, action: Callable) -> Dictionary:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 86)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_stylebox_override("normal", MenuUI.feel_style(
		MenuUI.BUTTON_ACTIVE if primary else MenuUI.BUTTON_BG,
		MenuUI.FPV_GREEN if primary else MenuUI.FPV_BORDER,
		2 if primary else 1, 1, 18, 8))
	var hover_bg := MenuUI.BUTTON_ACTIVE.lightened(0.08) if primary else MenuUI.BUTTON_HOVER
	button.add_theme_stylebox_override("hover", MenuUI.feel_style(
		hover_bg, MenuUI.FPV_GREEN, 2, 1, 18, 8))
	# Mouse-enter grabs focus. Without an explicit focus style the theme's white
	# box replaced the green primary row while its child labels stayed white,
	# so the selected menu item looked like an empty white rectangle.
	button.add_theme_stylebox_override("focus", MenuUI.feel_style(
		hover_bg, MenuUI.FPV_GREEN, 2, 1, 18, 8))
	button.add_theme_stylebox_override("pressed", MenuUI.feel_style(
		MenuUI.BUTTON_ACTIVE if primary else MenuUI.BUTTON_HOVER,
		MenuUI.FPV_GREEN, 2, 1, 18, 8))
	button.pressed.connect(action)
	button.mouse_entered.connect(button.grab_focus)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 18)
	button.add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 20)

	var icon_node := _MenuIcon.new(icon,
			Color.WHITE if primary else Color(0.44, 0.58, 0.49))
	icon_node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon_node)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.alignment = BoxContainer.ALIGNMENT_CENTER
	text_box.add_theme_constant_override("separation", 4)
	row.add_child(text_box)
	var title := Label.new()
	title.add_theme_font_size_override("font_size", 23)
	title.add_theme_color_override("font_color", MenuUI.BUTTON_ACTIVE_TEXT if primary else MenuUI.BUTTON_TEXT)
	text_box.add_child(title)
	var detail := Label.new()
	detail.add_theme_font_size_override("font_size", 14)
	detail.add_theme_color_override("font_color",
			Color(0.82, 0.89, 0.84) if primary else Color(0.42, 0.48, 0.44))
	text_box.add_child(detail)

	var arrow := Label.new()
	arrow.text = "›"
	arrow.add_theme_font_size_override("font_size", 30)
	arrow.add_theme_color_override("font_color",
			MenuUI.BUTTON_ACTIVE_TEXT if primary else Color(0.44, 0.58, 0.49))
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(arrow)
	var entry := {"button": button, "title": title, "detail": detail,
		"uk_title": uk_title, "en_title": en_title, "uk_desc": uk_desc, "en_desc": en_desc}
	return entry


func _refresh_home_language() -> void:
	var is_en := MenuUI.is_english()
	if _brand_project != null:
		_brand_project.text = "TACTICAL FPV FLIGHT SIMULATOR" if is_en else "ТАКТИЧНИЙ FPV-СИМУЛЯТОР"
	if _brand_title != null:
		_brand_title.text = "NEBESNYI HORIZONT" if is_en else "НЕБЕСНИЙ ГОРИЗОНТ"
	if _brand_subtitle != null:
		_brand_subtitle.text = "TUTORIAL  ·  COMBAT TRAINING  ·  TACTICAL MISSIONS" if is_en else "ТУТОРІАЛ  ·  БОЙОВЕ ТРЕНУВАННЯ  ·  БОЙОВИЙ РЕЖИМ"
	if _quick_ct_btn != null:
		var ct_done := Global.is_combat_training_completed()
		_quick_ct_btn.text = ("✓ COMBAT TRAINING DONE · REPEAT" if ct_done \
				else "🎯 COMBAT TRAINING: 3 STEPS") if is_en \
				else ("✓ БОЙОВЕ ТРЕНУВАННЯ ПРОЙДЕНО · ПОВТОРИТИ" if ct_done \
				else "🎯 БОЙОВЕ ТРЕНУВАННЯ: 3 КРОКИ")
	if _lang_btn != null:
		_lang_btn.text = "🌐 EN → UA" if is_en else "🌐 UA → EN"
	if _mode_bar_heading != null:
		_mode_bar_heading.text = "FLIGHT MODE (ORDER: TUTORIAL → FREESTYLE → COMBAT)" if is_en else "РЕЖИМ ПОЛЬОТУ"
	for entry in _nav_entries:
		(entry["title"] as Label).text = str(entry["en_title"] if is_en else entry["uk_title"])
		(entry["detail"] as Label).text = str(entry["en_desc"] if is_en else entry["uk_desc"])
	if _home_action_btn != null:
		_home_action_btn.text = "OPEN SORTIE DECK" if is_en else "ПЕРЕЙТИ ДО МІСІЙ"
	if _quick_tut_btn != null:
		_quick_tut_btn.text = "▶ QUICK START: TUTORIAL" if is_en else "▶ ШВИДКИЙ СТАРТ: ТУТОРІАЛ"
	if _daily_badge_lbl != null:
		var dc := Global.get_daily_challenge()
		var dc_done := "[DONE] " if bool(dc.get("completed", false)) else ""
		var dc_title := str(dc.get("title_en" if is_en else "title_uk", ""))
		_daily_badge_lbl.text = ("★ DAILY CHALLENGE: %s%s (+%d PTS)" if is_en else "★ ЩОДЕННИЙ ВИКЛИК: %s%s (+%d ОЧКІВ)") % [
			dc_done, dc_title, int(dc.get("bonus_score", 500))]
	var news_lines_uk := [
		"• Рекомендований старт: Туторіал (10 модулів + м'яка стабілізація Angle для першого вильоту).",
		"• Фрістайл: вільний політ, запис Привида на трасі, рейтинги ★ / S–B та калібрування стіків.",
		"• Тактична кампанія 1–4: послідовне відкриття місій, брифінг → виліт → дебрифінг.",
		"• Ангар FPV: українські та спортивні дрони, інтерактивний 3D-огляд і швидке налаштування кривих.",
		"• Повна підтримка української й англійської мов, геймпадів, USB-C ELRS та сенсорного керування.",
	]
	var news_lines_en := [
		"• Recommended start: Tutorial (10 pilot modules + gentle Angle stabilization assist).",
		"• Training mode: free flight, checkpoint course Ghost replay, ★ / S–B ranks & stick calibration.",
		"• Tactical Campaign 1–4: progressive unlock, briefing → sortie → debriefing & star ratings.",
		"• Fleet Hangar: FPV craft catalog, interactive 3D preview, Expo/SuperRate/Deadzone presets.",
		"• Full UA/EN bilingual UI, Gamepad / Apple MFi / USB-C ELRS calibration & Safe Area mobile HUD.",
	]
	var active_lines := news_lines_en if is_en else news_lines_uk
	for i in range(mini(_news_labels.size(), active_lines.size())):
		_news_labels[i].text = active_lines[i]
	if _author_lbl != null:
		_author_lbl.text = "Author: Serhii · @matilda.poetry" if is_en else "Автор: Сергій · @matilda.poetry"
	if _status_label != null:
		var campaign_done := Global.campaign_completed_count()
		var campaign_stars := Global.campaign_stars_total()
		if is_en:
			_status_label.text = "FPV SIMULATOR · VERSION 1.20.0 · UKRAINE · CAMPAIGN %d/4 · ★ %d/12" % [campaign_done, campaign_stars]
		else:
			_status_label.text = "FPV-СИМУЛЯТОР · ВЕРСІЯ 1.20.0 · УКРАЇНА · КАМПАНІЯ %d/4 · ★ %d/12" % [campaign_done, campaign_stars]
	if _mode_prompt != null:
		_mode_prompt.text = "SELECT FLIGHT MODE" if is_en else "ОБЕРІТЬ РЕЖИМ ПОЛЬОТУ"
	_refresh_home_mode()


func _on_toggle_language() -> void:
	Loc.toggle_language()
	_refresh_home_language()
	MenuUI.localize_tree(self)


func _on_quick_tutorial_pressed() -> void:
	Global.combat_training = false
	_selected_home_mode = Global.PlayMode.TUTORIAL
	Global.set_play_mode(Global.PlayMode.TUTORIAL)
	Global.menu_settings["selected_mode"] = Global.PlayMode.TUTORIAL
	Global.menu_settings["selected_map"] = "promzona_plavni"
	Global.save_menu_settings()
	Audio.stop_menu_music(0.35)
	get_tree().change_scene_to_file("res://sceneries/PromzonaPlavniLevel.tscn")


func _on_quick_combat_training_pressed() -> void:
	_selected_home_mode = Global.PlayMode.TRAINING
	Global.combat_training = true
	Global.set_play_mode(Global.PlayMode.TRAINING)
	Global.special_mission = 0
	Global.menu_settings["selected_mode"] = Global.PlayMode.TRAINING
	Global.menu_settings["selected_map"] = "promzona_plavni"
	# GRIM-7M: combat airframe with a physical payload release, ideal for the
	# first "find, hover, drop" lesson.
	DroneCatalog.apply(1)
	Global.save_menu_settings()
	Audio.stop_menu_music(0.35)
	get_tree().change_scene_to_file("res://sceneries/PromzonaPlavniLevel.tscn")


func _place(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size


func _layout_design() -> void:
	if _design_root == null or not is_inside_tree():
		return
	var vp := get_viewport_rect().size
	var s := minf(vp.x / DESIGN_SIZE.x, vp.y / DESIGN_SIZE.y)
	_design_root.scale = Vector2(s, s)
	_design_root.position = (vp - DESIGN_SIZE * s) * 0.5


func _open_hangar() -> void:
	get_tree().change_scene_to_file(DRONE_HANGAR)


func _open_options() -> void:
	if _options_overlay != null and is_instance_valid(_options_overlay):
		return
	var scene := load(OPTIONS_SCENE) as PackedScene
	if scene == null:
		return
	_options_overlay = scene.instantiate() as Control
	if _options_overlay == null:
		return
	_options_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	if _options_overlay.has_signal("back"):
		_options_overlay.connect("back", Callable(self, "_close_options"))
	# Overlays are parented to the real UI root so they stay viewport-sized,
	# while their own layout still follows the 1920x1080 design canvas.
	if _ui_layer != null:
		_ui_layer.add_child(_options_overlay)
	else:
		add_child(_options_overlay)


func _close_options() -> void:
	if _options_overlay != null and is_instance_valid(_options_overlay):
		_options_overlay.queue_free()
	_options_overlay = null


func _start_menu_music() -> void:
	if DisplayServer.get_name() == "headless":
		return
	# The shared Audio autoload owns the 32-second menu theme; starting it here
	# means the music continues seamlessly into the main menu.
	Audio.play_menu_music()


func _make_fade() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, 0))
	gradient.set_color(1, Color(0, 0, 0, 0.82))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 64
	texture.height = 256
	texture.fill_from = Vector2(0.5, 0.0)
	texture.fill_to = Vector2(0.5, 1.0)
	return texture


func _make_horizontal_fade() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.005, 0.012, 0.008, 0.82))
	gradient.set_color(1, Color(0.005, 0.012, 0.008, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 512
	texture.height = 8
	texture.fill_from = Vector2(0.0, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture


func _on_start_pressed() -> void:
	Global.play_mode = _selected_home_mode
	get_tree().change_scene_to_file(MAIN_MENU)


func _on_quit_pressed() -> void:
	if OS.get_name() == "iOS":
		return
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		accept_event()
		_on_start_pressed()


func _is_qa_session() -> bool:
	for name in QA_ENV:
		if OS.has_environment(name):
			return true
	return false


func _exit_tree() -> void:
	var vp := get_viewport()
	if vp != null and vp.size_changed.is_connected(_layout_design):
		vp.size_changed.disconnect(_layout_design)
