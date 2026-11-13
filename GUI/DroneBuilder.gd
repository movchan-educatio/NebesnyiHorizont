## Interactive FPV Drone Modular Builder (Ukrainian Military Tech / C2 Workshop)
## Allows assembling custom FPV drones from interchangeable 3D components:
## - Frames (3" Cinewhoop, 5" Race, 7" Freestyle, 10" Heavy Kamikaze)
## - Motors (2207 HighKV, 2807 LowKV)
## - Propellers (5x4x3, 7x4x3, 10x5x3)
## - Batteries (4S 1500mAh LiPo, 6S 8400mAh Li-Ion)
## - Cameras (Analog FPV RGB, FLIR Boson 640 Thermal)
## - Payloads (Empty, VOG-17 Drop, PG-7VR Kamikaze Warhead)
##
## Features dynamic Marker3D hardpoints, real-time TTX/TWR/flight-time physics calculation,
## 3D orbit camera, technical workshop workbench, and direct test-flight deployment.
extends Control

const MAIN_MENU := "res://GUI/MainMenu.tscn"
const BIG_LEVEL := "res://sceneries/BigLevel.tscn"
const PARTS_JSON := "res://Assets/drone_parts/drone_parts_data.json"
const SAVE_PATH := "user://custom_drone_builder.json"
const PAINT_SCHEMES := ["field_olive", "race_orange", "search_sand"]
const PAINT_SCHEME_NAMES := ["ТАКТИЧНА ОЛИВА", "ГОНОЧНИЙ ОРАНЖ", "ПІСОЧНИЙ ПОШУК"]

const DronePropellerSystem = preload("res://scripts/util/DronePropellerSystem.gd")
const DroneAssemblyBuilder = preload("res://scripts/util/DroneAssemblyBuilder.gd")
const LocScript = preload("res://scripts/util/localization_manager.gd")

# Database & parts index
var _parts_db: Dictionary = {}
var _parts_by_id: Dictionary = {}
var _parts_by_category: Dictionary = {
	"frame": [],
	"motor": [],
	"prop": [],
	"battery": [],
	"camera": [],
	"payload": []
}

# Current drone build configuration (part IDs)
var _current_build: Dictionary = {
	"frame": "frame_race_5",
	"motor": "motor_2207_highkv",
	"prop": "prop_5x4x3",
	"battery": "battery_4s_1500",
	"camera": "camera_analog",
	"payload": "payload_empty",
	"paint_scheme": "field_olive"
}

# Category metadata for UI
const CATEGORIES := [
	{"id": "frame", "name": "РАМА", "icon": "🔲"},
	{"id": "motor", "name": "ДВИГУНИ (4x)", "icon": "⚙️"},
	{"id": "prop", "name": "ГВИНТИ (4x)", "icon": "🌀"},
	{"id": "battery", "name": "БАТАРЕЯ", "icon": "🔋"},
	{"id": "camera", "name": "КАМЕРА", "icon": "📷"},
	{"id": "payload", "name": "БОЙОВА ЧАСТИНА", "icon": "💣"}
]

var _active_category_idx: int = 0

# 3D Viewport & Scene references
var _sub_viewport: SubViewport = null
var _drone_root: Node3D = null
var _bench_root: Node3D = null
var _cam_pivot: Node3D = null
var _camera: Camera3D = null

# Orbit Camera State
var _cam_yaw: float = 0.65
var _cam_pitch: float = 0.32
var _cam_dist: float = 0.58
var _is_dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _auto_spin: bool = false
var _props_spinning: bool = false
var _prop_rpm: float = 0.0

# UI references
var _cat_buttons: Array[Button] = []
var _cards_container: VBoxContainer = null
var _part_detail_label: Label = null
var _part_name_label: Label = null
var _paint_selector: OptionButton = null

# Telemetry UI references
var _val_mass: Label = null
var _val_thrust: Label = null
var _val_twr: Label = null
var _badge_twr: Label = null
var _val_hover: Label = null
var _val_time: Label = null
var _val_combat_type: Label = null
var _val_detonator: Label = null
var _compat_box: PanelContainer = null
var _compat_label: Label = null
var _toast_label: Label = null


func _ready() -> void:
	theme = MenuUI.theme()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_load_database()
	_load_saved_build()
	_build_ui()
	_setup_3d_workbench()
	_rebuild_drone()
	_update_telemetry()
	_select_category(0)
	MenuUI.localize_tree(self)


# ==============================================================================
# 1. DATABASE & PERSISTENCE
# ==============================================================================
func _load_database() -> void:
	if not FileAccess.file_exists(PARTS_JSON):
		printerr("[DroneBuilder] Missing database: ", PARTS_JSON)
		return
	var file := FileAccess.open(PARTS_JSON, FileAccess.READ)
	var text := file.get_as_text()
	var json := JSON.new()
	if json.parse(text) != OK:
		printerr("[DroneBuilder] JSON parse error: ", json.get_error_message())
		return
	_parts_db = json.data
	for p in _parts_db.get("parts", []):
		var id: String = p.get("id", "")
		var cat: String = p.get("category", "")
		_parts_by_id[id] = p
		if cat in _parts_by_category:
			_parts_by_category[cat].append(p)
	print("[DroneBuilder] Loaded ", _parts_by_id.size(), " parts.")


func _load_saved_build() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var json := JSON.new()
	if json.parse(f.get_as_text()) == OK and json.data is Dictionary:
		var d: Dictionary = json.data
		for k in _current_build.keys():
			if k not in d:
				continue
			if k == "paint_scheme":
				if str(d[k]) in PAINT_SCHEMES:
					_current_build[k] = str(d[k])
			elif _parts_by_id.has(str(d[k])):
				_current_build[k] = str(d[k])
		print("[DroneBuilder] Loaded saved build from ", SAVE_PATH)


func _save_current_build() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_current_build, "\t"))
	# Also inject directly into DroneCatalog preset 9 («QUAD-5» CUSTOM)
	_apply_to_catalog()
	_show_toast("КОНФІГУРАЦІЮ ЗБЕРЕЖЕНО В АНГАР")


func _apply_to_catalog() -> void:
	if not _parts_by_id.has(_current_build["frame"]):
		return
	var frame: Dictionary = _parts_by_id[_current_build["frame"]]
	var motor: Dictionary = _parts_by_id[_current_build["motor"]]
	var prop: Dictionary = _parts_by_id[_current_build["prop"]]
	var battery: Dictionary = _parts_by_id[_current_build["battery"]]
	var camera: Dictionary = _parts_by_id[_current_build["camera"]]
	var payload: Dictionary = _parts_by_id[_current_build["payload"]]
	var is_en := MenuUI.is_english()

	var dry_g := float(frame.get("weight_g", 70)) + \
			float(motor.get("weight_g", 32)) * 4.0 + \
			float(prop.get("weight_g", 4)) * 4.0 + \
			float(camera.get("weight_g", 8)) + 35.0 # 35g electronics
	var batt_g := float(battery.get("weight_g", 180))
	var payload_g := float(payload.get("weight_g", 0))

	var total_mass_kg := (dry_g + batt_g + payload_g) / 1000.0
	var total_thrust_g := float(motor.get("thrust_g", 1600)) * 4.0
	var twr := total_thrust_g / maxf(1.0, dry_g + batt_g + payload_g)

	var is_combat := (str(payload.get("id")) != "payload_empty")
	var has_drop := (str(payload.get("id")) == "payload_drop_vog")

	var catalog_preset: Dictionary = {
		"name": ("CUSTOM UAV [%s]" if is_en else "«КАСТОМНИЙ БПЛА» [%s]") % str(frame.get("name", "5\"")),
		"name_en": "CUSTOM UAV [%s]" % str(frame.get("name_en", frame.get("name", "5\""))),
		"tag": ("BUILDER %s\"" if is_en else "КОНСТРУКТОР %s\"") % str(frame.get("size_inch", 5.0)),
		"desc": "Individual modular drone build" if is_en else "Індивідуальна збірка з компонентів конструктора",
		"desc_en": "Individual modular drone build",
		"info": "Custom FPV drone: frame %s, motors %s, battery %s, payload %s." % [
			frame.get("name", ""), motor.get("name", ""), battery.get("name", ""), payload.get("name", "")
		] if is_en else "Кастомний FPV-дрон: рама %s, мотори %s, акумулятор %s, навантаження %s." % [
			frame.get("name", ""), motor.get("name", ""), battery.get("name", ""), payload.get("name", "")
		],
		"info_en": "Custom FPV drone: frame %s, motors %s, battery %s, payload %s." % [
			frame.get("name_en", frame.get("name", "")), motor.get("name_en", motor.get("name", "")),
			battery.get("name_en", battery.get("name", "")), payload.get("name_en", payload.get("name", ""))
		],
		"dry": dry_g / 1000.0,
		"batt": batt_g / 1000.0,
		"kv": int(motor.get("kv_rating", 2450)),
		"torque": float(motor.get("thrust_g", 1600)) * 0.9,
		"rpm": float(motor.get("kv_rating", 2450)) * float(battery.get("voltage_v", 14.8)),
		"prop_d": float(prop.get("diameter_inch", 5.1)),
		"prop_p": float(prop.get("pitch_inch", 4.6)),
		"blades": int(prop.get("blades", 3)),
		"rate": 750 if twr > 4.0 else 550,
		"motor_size": 2207 if int(motor.get("kv_rating", 2450)) > 2000 else 2807,
		"payload": 1 if is_combat else 0,
		"payload_mass": payload_g / 1000.0,
		"combat": is_combat,
		"has_drop": has_drop,
		"drop_name": "ВОГ-17 ОФ (340г)" if has_drop else "",
		"drop_name_en": "VOG-17 HE (340 g)" if has_drop else "",
		"twr": twr,
		"cog_offset": Vector3(0.0, 0.005, 0.0),
		"dimensions": Vector3(0.25, 0.08, 0.25),
		"drag_area": Vector3(0.015, 0.018, 0.008),
		"parts_profile": 9,
		"model_builder_config": _current_build.duplicate(),
		"is_builder_custom": true,
		"model": str(frame.get("mesh_path", "")),
		"model_size": float(frame.get("size_inch", 5.0)) * 0.045,
		"model_fit": false,
		"fpv_cam_pos": Vector3(0.0, 0.025, -0.075),
		"fpv_cam_pitch": -8.0
	}

	var slot := DroneCatalog.custom_preset_index()
	DroneCatalog.set_custom_preset(slot, catalog_preset)


func _launch_test_flight() -> void:
	_save_current_build()
	var slot := DroneCatalog.custom_preset_index()
	Global.drone_preset = slot
	DroneCatalog.apply(slot)
	get_tree().change_scene_to_file(BIG_LEVEL)


# ==============================================================================
# 2. UI LAYOUT & CONTROLS
# ==============================================================================
func _build_ui() -> void:
	# Tactical MGRS background
	add_child(MenuUI.background(MenuUI.BG))

	var main_box := VBoxContainer.new()
	MenuUI.full_rect(main_box)
	main_box.add_theme_constant_override("separation", 6)
	add_child(main_box)

	# --- 1. TOP HEADER BAR ---
	var top_bar := PanelContainer.new()
	var top_sb := StyleBoxFlat.new()
	top_sb.bg_color = MenuUI.PANEL_HEADER
	top_sb.border_color = MenuUI.BORDER
	top_sb.border_width_bottom = 2
	top_sb.content_margin_left = 18
	top_sb.content_margin_right = 18
	top_sb.content_margin_top = 8
	top_sb.content_margin_bottom = 8
	top_bar.add_theme_stylebox_override("panel", top_sb)
	main_box.add_child(top_bar)

	var top_h := HBoxContainer.new()
	top_h.add_theme_constant_override("separation", 16)
	top_bar.add_child(top_h)

	var back_btn := MenuUI.button("← НАЗАД В МЕНЮ", 38)
	back_btn.custom_minimum_size = Vector2(160, 38)
	back_btn.pressed.connect(func(): get_tree().change_scene_to_file(MAIN_MENU))
	top_h.add_child(back_btn)

	var title_v := VBoxContainer.new()
	title_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_h.add_child(title_v)

	var title_lbl := MenuUI.title("КОНСТРУКТОР ТАКТИЧНИХ ТА СПОРТИВНИХ БПЛА", 24)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title_v.add_child(title_lbl)

	var sub_lbl := MenuUI.subtitle("МОДУЛЬНА ЗБІРКА З 3D-ДЕТАЛЕЙ · РОЗРАХУНОК ТЯГИ ТА БАЛАНСУ · ТЕСТОВИЙ ВИЛІТ")
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title_v.add_child(sub_lbl)

	_toast_label = Label.new()
	_toast_label.text = ""
	_toast_label.add_theme_font_size_override("font_size", 14)
	_toast_label.add_theme_color_override("font_color", MenuUI.WARN_AMBER)
	top_h.add_child(_toast_label)

	var reset_btn := MenuUI.button("🔄 СТАНДАРТНИЙ 5\"", 38)
	reset_btn.custom_minimum_size = Vector2(170, 38)
	reset_btn.pressed.connect(_reset_to_default)
	top_h.add_child(reset_btn)

	# --- 2. MAIN 3-PANEL WORKSPACE ---
	var workspace_h := HBoxContainer.new()
	workspace_h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace_h.add_theme_constant_override("separation", 8)
	main_box.add_child(workspace_h)

	# LEFT: Part Catalog & Category Selector
	var left_panel := _build_left_panel()
	left_panel.custom_minimum_size = Vector2(360, 0)
	workspace_h.add_child(left_panel)

	# CENTER: 3D Workshop Viewport + Camera Overlay Controls
	var center_panel := _build_center_viewport()
	center_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace_h.add_child(center_panel)

	# RIGHT: Live Telemetry & Balance Dashboard
	var right_panel := _build_right_dashboard()
	right_panel.custom_minimum_size = Vector2(380, 0)
	workspace_h.add_child(right_panel)

	# --- 3. BOTTOM ACTION BAR ---
	var btm_bar := PanelContainer.new()
	var btm_sb := StyleBoxFlat.new()
	btm_sb.bg_color = MenuUI.PANEL_HEADER
	btm_sb.border_color = MenuUI.BORDER
	btm_sb.border_width_top = 2
	btm_sb.content_margin_left = 18
	btm_sb.content_margin_right = 18
	btm_sb.content_margin_top = 8
	btm_sb.content_margin_bottom = 8
	btm_bar.add_theme_stylebox_override("panel", btm_sb)
	main_box.add_child(btm_bar)

	var btm_h := HBoxContainer.new()
	btm_h.add_theme_constant_override("separation", 14)
	btm_bar.add_child(btm_h)

	var save_btn := MenuUI.button("💾 ЗБЕРЕГТИ В АНГАР", 46)
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn.pressed.connect(_save_current_build)
	btm_h.add_child(save_btn)

	var launch_btn := Button.new()
	launch_btn.text = "⚡ ТЕСТОВИЙ ВИЛІТ (БОЙОВИЙ ПОЛІГОН)"
	launch_btn.custom_minimum_size = Vector2(0, 46)
	launch_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l_sb := StyleBoxFlat.new()
	l_sb.bg_color = Color("234b22")
	l_sb.border_color = MenuUI.ACCENT
	l_sb.border_width_left = 4
	l_sb.border_width_right = 2
	l_sb.border_width_top = 2
	l_sb.border_width_bottom = 2
	l_sb.set_corner_radius_all(3)
	launch_btn.add_theme_stylebox_override("normal", l_sb)
	launch_btn.add_theme_color_override("font_color", MenuUI.TEXT)
	launch_btn.add_theme_font_size_override("font_size", 18)
	launch_btn.pressed.connect(_launch_test_flight)
	btm_h.add_child(launch_btn)


# --- LEFT PANEL: Categories & Part Cards ---
func _build_left_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	margin.add_child(v)

	v.add_child(MenuUI.section("ВИБІР КОМПОНЕНТА", "МОДУЛІ"))

	# Category Tabs Container
	var cat_scroll := ScrollContainer.new()
	cat_scroll.custom_minimum_size = Vector2(0, 78)
	cat_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(cat_scroll)

	var cat_grid := GridContainer.new()
	cat_grid.columns = 3
	cat_grid.add_theme_constant_override("h_separation", 4)
	cat_grid.add_theme_constant_override("v_separation", 4)
	cat_scroll.add_child(cat_grid)

	_cat_buttons.clear()
	for i in range(CATEGORIES.size()):
		var c: Dictionary = CATEGORIES[i]
		var btn := Button.new()
		btn.text = "%s %s" % [c["icon"], MenuUI.translate_text(str(c["name"]))]
		btn.custom_minimum_size = Vector2(108, 34)
		btn.add_theme_font_size_override("font_size", 12)
		var idx := i
		btn.pressed.connect(func(): _select_category(idx))
		cat_grid.add_child(btn)
		_cat_buttons.append(btn)

	v.add_child(MenuUI.hline())

	# Scrollable Part Cards List
	var cards_scroll := ScrollContainer.new()
	cards_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cards_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(cards_scroll)

	_cards_container = VBoxContainer.new()
	_cards_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards_container.add_theme_constant_override("separation", 6)
	cards_scroll.add_child(_cards_container)

	v.add_child(MenuUI.hline())

	# Selected Part Description Box
	var desc_box := PanelContainer.new()
	var d_sb := StyleBoxFlat.new()
	d_sb.bg_color = MenuUI.PANEL_HEADER
	d_sb.border_color = MenuUI.BORDER
	d_sb.border_width_left = 3
	d_sb.set_corner_radius_all(2)
	d_sb.content_margin_left = 8
	d_sb.content_margin_right = 8
	d_sb.content_margin_top = 6
	d_sb.content_margin_bottom = 6
	desc_box.add_theme_stylebox_override("panel", d_sb)
	v.add_child(desc_box)

	var desc_v := VBoxContainer.new()
	desc_v.add_theme_constant_override("separation", 2)
	desc_box.add_child(desc_v)

	_part_name_label = Label.new()
	_part_name_label.text = "Деталь"
	_part_name_label.add_theme_font_size_override("font_size", 14)
	_part_name_label.add_theme_color_override("font_color", MenuUI.WARN_AMBER)
	desc_v.add_child(_part_name_label)

	_part_detail_label = Label.new()
	_part_detail_label.text = "Характеристики деталі"
	_part_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_part_detail_label.add_theme_font_size_override("font_size", 12)
	_part_detail_label.add_theme_color_override("font_color", MenuUI.MUTED)
	desc_v.add_child(_part_detail_label)

	return panel


func _select_category(idx: int) -> void:
	_active_category_idx = clampi(idx, 0, CATEGORIES.size() - 1)
	for i in range(_cat_buttons.size()):
		var b := _cat_buttons[i]
		if i == _active_category_idx:
			b.add_theme_color_override("font_color", MenuUI.WARN_AMBER)
		else:
			b.remove_theme_color_override("font_color")
	_populate_category_cards(CATEGORIES[_active_category_idx]["id"])


func _populate_category_cards(cat_id: String) -> void:
	for c in _cards_container.get_children():
		c.queue_free()

	var parts: Array = _parts_by_category.get(cat_id, [])
	var active_part_id: String = _current_build.get(cat_id, "")

	for p in parts:
		var p_id: String = p.get("id", "")
		var is_selected := (p_id == active_part_id)

		var card := Button.new()
		card.custom_minimum_size = Vector2(0, 56)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		# Custom styling
		var sb := StyleBoxFlat.new()
		sb.bg_color = MenuUI.CARD_ACTIVE if is_selected else MenuUI.CARD
		sb.border_color = MenuUI.WARN_AMBER if is_selected else MenuUI.BORDER
		sb.border_width_left = 5 if is_selected else 2
		sb.border_width_right = 1
		sb.border_width_top = 1
		sb.border_width_bottom = 1
		sb.set_corner_radius_all(2)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		card.add_theme_stylebox_override("normal", sb)

		var card_h := HBoxContainer.new()
		card_h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_h.add_theme_constant_override("separation", 8)
		card.add_child(card_h)

		var info_v := VBoxContainer.new()
		info_v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_v.add_theme_constant_override("separation", 2)
		card_h.add_child(info_v)

		var name_lbl := Label.new()
		name_lbl.text = MenuUI.translate_text(str(p.get("name", "")))
		name_lbl.add_theme_font_size_override("font_size", 14)
		name_lbl.add_theme_color_override("font_color", MenuUI.WARN_AMBER if is_selected else MenuUI.TEXT)
		info_v.add_child(name_lbl)

		var sub_txt := _build_part_quick_stat(p)
		var sub_lbl := Label.new()
		sub_lbl.text = sub_txt
		sub_lbl.add_theme_font_size_override("font_size", 12)
		sub_lbl.add_theme_color_override("font_color", MenuUI.MUTED)
		info_v.add_child(sub_lbl)

		# Type badge (Civilian vs Military)
		var badge := Label.new()
		var is_mil := (str(p.get("type", "")) == "military")
		badge.text = ("[ COMBAT ]" if is_mil else "[ SPORT ]") if MenuUI.is_english() else ("[ БОЙОВИЙ ]" if is_mil else "[ СПОРТ ]")
		badge.add_theme_font_size_override("font_size", 11)
		badge.add_theme_color_override("font_color", MenuUI.DANGER if is_mil else MenuUI.ACCENT)
		card_h.add_child(badge)

		var chosen_id := p_id
		var part_dict: Dictionary = p
		card.pressed.connect(func():
			_choose_part(cat_id, chosen_id, part_dict)
		)

		_cards_container.add_child(card)

		if is_selected:
			_update_part_detail(p)


func _build_part_quick_stat(p: Dictionary) -> String:
	var cat: String = p.get("category", "")
	var is_en := MenuUI.is_english()
	var w: String = "%s g" % str(p.get("weight_g", 0)) if is_en else "%s г" % str(p.get("weight_g", 0))
	match cat:
		"frame":
			return ("Size: %s\" · Weight: %s" if is_en else "Розмір: %s\" · Вага: %s") % [str(p.get("size_inch", 0)), w]
		"motor":
			return ("Thrust: %s g · KV: %s · Weight: %s" if is_en else "Тяга: %s г · KV: %s · Вага: %s") % [str(p.get("thrust_g", 0)), str(p.get("kv_rating", 0)), w]
		"prop":
			return ("Diameter: %s\" · Pitch: %s\" · Weight: %s" if is_en else "Діаметр: %s\" · Крок: %s\" · Вага: %s") % [str(p.get("diameter_inch", 0)), str(p.get("pitch_inch", 0)), w]
		"battery":
			return ("Capacity: %s mAh · Voltage: %s V · Weight: %s" if is_en else "Ємність: %s mAh · Напруга: %s В · Вага: %s") % [str(p.get("capacity_mah", 0)), str(p.get("voltage_v", 0)), w]
		"camera":
			return ("Sensor: %s · Latency: %s ms" if is_en else "Сенсор: %s · Затримка: %s мс") % [str(p.get("sensor_type", "")), str(p.get("latency_ms", 0))]
		"payload":
			if str(p.get("id")) == "payload_empty":
				return "No payload · Weight: 5 g" if is_en else "Без навантаження · Вага: 5 г"
			elif p.get("armor_penetration", 0.0) > 50.0:
				return ("Penetration: %s mm · Weight: %s" if is_en else "Бронепробивність: %s мм · Вага: %s") % [str(p.get("armor_penetration", 0)), w]
			else:
				return ("Damage radius: %s m · Weight: %s" if is_en else "Радіус ураження: %s м · Вага: %s") % [str(p.get("damage_radius", 0)), w]
	return w


func _choose_part(cat_id: String, p_id: String, p: Dictionary) -> void:
	_current_build[cat_id] = p_id
	_update_part_detail(p)
	_rebuild_drone()
	_update_telemetry()
	_select_category(_active_category_idx) # Refresh selection highlights


func _update_part_detail(p: Dictionary) -> void:
	var is_en := MenuUI.is_english()
	if _part_name_label != null:
		_part_name_label.text = "%s  (%s)" % [MenuUI.translate_text(str(p.get("name", ""))), str(p.get("weight_g", 0)) + (" g" if is_en else " г")]
	if _part_detail_label != null:
		_part_detail_label.text = MenuUI.translate_text(str(p.get("description", "")))


func _reset_to_default() -> void:
	_current_build = {
		"frame": "frame_race_5",
		"motor": "motor_2207_highkv",
		"prop": "prop_5x4x3",
		"battery": "battery_4s_1500",
		"camera": "camera_analog",
		"payload": "payload_empty",
		"paint_scheme": "field_olive"
	}
	_rebuild_drone()
	_update_telemetry()
	_select_category(_active_category_idx)
	_show_toast("ЗБІРКУ СКИНУТО ДО СТАНДАРТУ")
	if _paint_selector != null:
		_paint_selector.select(0)


func _on_paint_scheme_selected(index: int) -> void:
	if index < 0 or index >= PAINT_SCHEMES.size():
		return
	_current_build["paint_scheme"] = PAINT_SCHEMES[index]
	_rebuild_drone()
	_show_toast("СХЕМУ ФАРБУВАННЯ ЗАСТОСОВАНО")


# --- CENTER: 3D Workshop Viewport & Overlay ---
func _build_center_viewport() -> Control:
	var root := Control.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var vp_container := SubViewportContainer.new()
	MenuUI.full_rect(vp_container)
	vp_container.stretch = true
	root.add_child(vp_container)

	_sub_viewport = SubViewport.new()
	_sub_viewport.own_world_3d = true
	_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# The builder preview is a separate viewport, so it does not inherit the
	# root MSAA; ask for it explicitly like the hangar/main-menu previews.
	_sub_viewport.msaa_3d = Viewport.MSAA_4X
	_sub_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	vp_container.add_child(_sub_viewport)

	# Mouse input handler for orbit dragging
	vp_container.gui_input.connect(_on_viewport_input)

	# Overlay controls (Camera View buttons & Propeller spin toggle)
	var overlay_v := VBoxContainer.new()
	overlay_v.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	overlay_v.offset_left = 12
	overlay_v.offset_top = 12
	overlay_v.offset_right = -12
	overlay_v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(overlay_v)

	var view_h := HBoxContainer.new()
	view_h.add_theme_constant_override("separation", 6)
	overlay_v.add_child(view_h)

	var btn_persp := MenuUI.button("3D ОГЛЯД", 30)
	btn_persp.pressed.connect(func(): _set_cam_view(0.65, 0.32, 0.58))
	view_h.add_child(btn_persp)

	var btn_top := MenuUI.button("ЗВЕРХУ", 30)
	btn_top.pressed.connect(func(): _set_cam_view(0.0, 1.48, 0.52))
	view_h.add_child(btn_top)

	var btn_front := MenuUI.button("СПЕРЕДУ", 30)
	btn_front.pressed.connect(func(): _set_cam_view(0.0, 0.05, 0.45))
	view_h.add_child(btn_front)

	var btn_side := MenuUI.button("ЗБОКУ", 30)
	btn_side.pressed.connect(func(): _set_cam_view(PI * 0.5, 0.05, 0.45))
	view_h.add_child(btn_side)

	var btn_spin := MenuUI.button("🔄 АВТО-ОБЕРТАННЯ", 30)
	btn_spin.pressed.connect(func(): _auto_spin = not _auto_spin)
	view_h.add_child(btn_spin)

	var btn_props := MenuUI.button("⚡ ТЕСТ МОТОРІВ", 30)
	btn_props.pressed.connect(func(): _props_spinning = not _props_spinning)
	view_h.add_child(btn_props)

	var paint_row := HBoxContainer.new()
	paint_row.add_theme_constant_override("separation", 8)
	overlay_v.add_child(paint_row)
	var paint_label := Label.new()
	paint_label.text = "ФАРБУВАННЯ"
	paint_label.add_theme_font_size_override("font_size", 12)
	paint_label.add_theme_color_override("font_color", MenuUI.TEXT)
	paint_row.add_child(paint_label)
	_paint_selector = OptionButton.new()
	_paint_selector.custom_minimum_size = Vector2(190, 30)
	_paint_selector.add_theme_font_size_override("font_size", 12)
	for scheme_name in PAINT_SCHEME_NAMES:
		_paint_selector.add_item(scheme_name)
	var selected_scheme := PAINT_SCHEMES.find(str(_current_build.get("paint_scheme", "field_olive")))
	_paint_selector.select(maxi(0, selected_scheme))
	_paint_selector.item_selected.connect(_on_paint_scheme_selected)
	paint_row.add_child(_paint_selector)

	# Bottom hint
	var hint := Label.new()
	hint.text = "🖱️ Затисніть ЛКМ/ПКМ для обертання камери навколо дрона · Коліщатко — масштаб"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", MenuUI.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_bottom = -8
	root.add_child(hint)

	return root


# --- RIGHT PANEL: Telemetry, TTX & Compatibility Dashboard ---
func _build_right_dashboard() -> PanelContainer:
	var panel := PanelContainer.new()
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	margin.add_child(v)

	v.add_child(MenuUI.section("ТТХ ТА БАЛАНС ДРОНУ", "ІНТЕЛ"))

	# Telemetry Metrics Grid
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	v.add_child(grid)

	_val_mass = _add_stat_row(grid, "ЗЛІТНА МАСА (AUW):", "0 г")
	_val_thrust = _add_stat_row(grid, "СУМАРНА ТЯГА (4x):", "0 г")
	_val_twr = _add_stat_row(grid, "ТЯГООСНАЩЕНІСТЬ:", "0.0 : 1")
	_val_hover = _add_stat_row(grid, "ГАЗ ВИСІННЯ:", "0 %")
	_val_time = _add_stat_row(grid, "ЧАС ПОЛЬОТУ:", "0.0 хв")
	_val_combat_type = _add_stat_row(grid, "ПРИЗНАЧЕННЯ:", "СПОРТ")

	# TWR Dynamic Tactical Badge
	_badge_twr = Label.new()
	_badge_twr.text = "ЗБАЛАНСОВАНИЙ ФРІСТАЙЛ"
	_badge_twr.add_theme_font_size_override("font_size", 13)
	_badge_twr.add_theme_color_override("font_color", MenuUI.ACCENT)
	_badge_twr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_badge_twr)

	v.add_child(MenuUI.hline())

	# Combat Specifications Box
	v.add_child(MenuUI.section("БОЙОВИЙ ПРОФІЛЬ ТА БЧ", "ЗСУ"))
	var combat_box := PanelContainer.new()
	var c_sb := StyleBoxFlat.new()
	c_sb.bg_color = MenuUI.PANEL_HEADER
	c_sb.border_color = MenuUI.BORDER
	c_sb.border_width_left = 3
	c_sb.set_corner_radius_all(2)
	c_sb.content_margin_left = 8
	c_sb.content_margin_right = 8
	c_sb.content_margin_top = 6
	c_sb.content_margin_bottom = 6
	combat_box.add_theme_stylebox_override("panel", c_sb)
	v.add_child(combat_box)

	var c_v := VBoxContainer.new()
	c_v.add_theme_constant_override("separation", 4)
	combat_box.add_child(c_v)

	_val_detonator = Label.new()
	_val_detonator.text = "ДЕТОНАТОР: ВІДСУТНІЙ"
	_val_detonator.add_theme_font_size_override("font_size", 13)
	_val_detonator.add_theme_color_override("font_color", MenuUI.MUTED)
	c_v.add_child(_val_detonator)

	v.add_child(MenuUI.hline())

	# Compatibility & Warning Box
	v.add_child(MenuUI.section("ПЕРЕВІРКА СУМІСНОСТІ", "КОНТРОЛЬ"))

	_compat_box = PanelContainer.new()
	var cp_sb := StyleBoxFlat.new()
	cp_sb.bg_color = MenuUI.PANEL_HEADER
	cp_sb.border_color = MenuUI.BORDER
	cp_sb.border_width_left = 4
	cp_sb.set_corner_radius_all(2)
	cp_sb.content_margin_left = 8
	cp_sb.content_margin_right = 8
	cp_sb.content_margin_top = 8
	cp_sb.content_margin_bottom = 8
	_compat_box.add_theme_stylebox_override("panel", cp_sb)
	v.add_child(_compat_box)

	_compat_label = Label.new()
	_compat_label.text = "✅ ВСІ КОМПОНЕНТИ СУМІСНІ"
	_compat_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_compat_label.add_theme_font_size_override("font_size", 12)
	_compat_label.add_theme_color_override("font_color", MenuUI.ACCENT)
	_compat_box.add_child(_compat_label)

	return panel


func _add_stat_row(grid: GridContainer, title: String, init_val: String) -> Label:
	var lbl_t := Label.new()
	lbl_t.text = title
	lbl_t.add_theme_font_size_override("font_size", 13)
	lbl_t.add_theme_color_override("font_color", MenuUI.MUTED)
	grid.add_child(lbl_t)

	var lbl_v := Label.new()
	lbl_v.text = init_val
	lbl_v.add_theme_font_size_override("font_size", 14)
	lbl_v.add_theme_color_override("font_color", MenuUI.TEXT)
	lbl_v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(lbl_v)
	return lbl_v


func _show_toast(msg: String) -> void:
	if _toast_label != null:
		_toast_label.text = "✓ %s" % MenuUI.translate_text(msg)
		var t := create_tween()
		t.tween_interval(3.0)
		t.tween_callback(func(): _toast_label.text = "")


# ==============================================================================
# 3. 3D WORKBENCH & CAMERA SETUP
# ==============================================================================
func _setup_3d_workbench() -> void:
	if _sub_viewport == null:
		return

	# 1. World Environment (PBR SSAO, SSR, Glow, ACES)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("26322c")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.70, 0.76, 0.70)
	env.ambient_light_energy = 1.65
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.16
	env.ssao_enabled = true
	env.ssr_enabled = true
	env.glow_enabled = false

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_sub_viewport.add_child(world_env)

	# 2. Lighting Rig
	# Primary Overhead Workshop Spotlight (warm workbench light)
	var spot := SpotLight3D.new()
	spot.position = Vector3(0.18, 0.95, 0.55)
	spot.light_color = Color(1.0, 0.95, 0.88)
	spot.light_energy = 2.5
	spot.spot_range = 3.5
	spot.spot_angle = 62.0
	spot.shadow_enabled = true
	_sub_viewport.add_child(spot)
	spot.look_at(Vector3.ZERO, Vector3.UP)

	# Tactical Cool Rim Light (Phosphor cyan backlight)
	var rim := SpotLight3D.new()
	rim.position = Vector3(-0.65, 0.72, -0.72)
	rim.light_color = Color(0.65, 0.85, 0.75)
	rim.light_energy = 1.4
	rim.spot_range = 2.8
	rim.spot_angle = 60.0
	_sub_viewport.add_child(rim)
	rim.look_at(Vector3.ZERO, Vector3.UP)

	# Soft ambient fill
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-45.0, 45.0, 0.0)
	fill.light_color = Color(0.4, 0.5, 0.45)
	fill.light_energy = 1.0
	_sub_viewport.add_child(fill)

	# 3. Technical Workbench Table (Dark brushed metal with anti-static mat)
	_bench_root = Node3D.new()
	_bench_root.name = "Workbench"
	_sub_viewport.add_child(_bench_root)

	var table_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.2, 0.04, 1.0)
	table_mesh.mesh = box
	table_mesh.position = Vector3(0.0, -0.02, 0.0)

	var table_mat := StandardMaterial3D.new()
	table_mat.albedo_color = Color("141b14")
	table_mat.metallic = 0.75
	table_mat.roughness = 0.35
	table_mesh.material_override = table_mat
	_bench_root.add_child(table_mesh)

	# Carbon Mounting Stand / Jig for the drone
	var stand_mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.045
	cyl.bottom_radius = 0.065
	cyl.height = 0.08
	stand_mesh.mesh = cyl
	stand_mesh.position = Vector3(0.0, 0.04, 0.0)

	var stand_mat := StandardMaterial3D.new()
	stand_mat.albedo_color = Color("1f2d1e")
	stand_mat.metallic = 0.85
	stand_mat.roughness = 0.25
	stand_mesh.material_override = stand_mat
	_bench_root.add_child(stand_mesh)

	# 4. Drone Root Container (elevated on top of stand)
	_drone_root = Node3D.new()
	_drone_root.name = "DroneAssembly"
	_drone_root.position = Vector3(0.0, 0.082, 0.0)
	_sub_viewport.add_child(_drone_root)

	# 5. Orbit Camera Rig
	_cam_pivot = Node3D.new()
	_cam_pivot.name = "CameraPivot"
	_cam_pivot.position = Vector3(0.0, 0.082, 0.0)
	_sub_viewport.add_child(_cam_pivot)

	_camera = Camera3D.new()
	_camera.name = "OrbitCamera"
	_camera.fov = 42.0
	_cam_pivot.add_child(_camera)
	_update_cam_transform()


func _update_cam_transform() -> void:
	if _camera == null or _cam_pivot == null:
		return
	_cam_pitch = clampf(_cam_pitch, -0.15, 1.50)
	_cam_dist = clampf(_cam_dist, 0.22, 1.25)

	var rot_basis := Basis.IDENTITY.rotated(Vector3.UP, _cam_yaw)
	rot_basis = rot_basis.rotated(rot_basis.x, -_cam_pitch)
	_cam_pivot.transform.basis = rot_basis
	_camera.position = Vector3(0.0, 0.0, _cam_dist)
	_camera.look_at(_cam_pivot.position, Vector3.UP)


func _set_cam_view(yaw: float, pitch: float, dist: float) -> void:
	_cam_yaw = yaw
	_cam_pitch = pitch
	_cam_dist = dist
	_update_cam_transform()


func _on_viewport_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			_is_dragging = mb.pressed
			_drag_start = mb.position
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_dist -= 0.04
			_update_cam_transform()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_dist += 0.04
			_update_cam_transform()
	elif event is InputEventMouseMotion and _is_dragging:
		var mm := event as InputEventMouseMotion
		_cam_yaw -= mm.relative.x * 0.008
		_cam_pitch += mm.relative.y * 0.008
		_update_cam_transform()


func _process(delta: float) -> void:
	if _auto_spin:
		_cam_yaw += delta * 0.45
		_update_cam_transform()

	if _drone_root != null:
		if _props_spinning:
			_prop_rpm = move_toward(_prop_rpm, 4800.0, delta * 3000.0)
		else:
			_prop_rpm = move_toward(_prop_rpm, 0.0, delta * 4000.0)
		if _prop_rpm > 1.0:
			DronePropellerSystem.animate_propellers(_drone_root, delta, [_prop_rpm, _prop_rpm, _prop_rpm, _prop_rpm])


# ==============================================================================
# 4. 3D DRONE DYNAMIC ASSEMBLY VIA MARKER3D
# ==============================================================================
## Converts Blender coordinates [x, y, z] to Godot Vector3(x, z, -y)
static func to_godot_pos(b: Array) -> Vector3:
	if b.size() < 3:
		return Vector3.ZERO
	return Vector3(float(b[0]), float(b[2]), -float(b[1]))


func _rebuild_drone() -> void:
	if _drone_root == null:
		return

	# 1. Clear old drone parts
	for child in _drone_root.get_children():
		child.queue_free()

	# 2. Assemble modular drone using DroneAssemblyBuilder
	var assembled := DroneAssemblyBuilder.build_drone_node(_current_build)
	if assembled != null:
		_drone_root.add_child(assembled)
		# Propagate prop pivots to _drone_root so DronePropellerSystem can spin them
		var pivots = assembled.get_meta("prop_pivots", [])
		_drone_root.set_meta("prop_pivots", pivots)
		_drone_root.set_meta("preset_index", 9)
		_fit_camera_to_model(assembled)


func _fit_camera_to_model(model: Node3D) -> void:
	if model == null or not is_instance_valid(model) or _cam_pivot == null:
		return
	var bounds: AABB = DroneCatalog.model_bounds_full(model)
	if bounds.size.length_squared() < 0.000001:
		return
	_cam_pivot.global_position = bounds.get_center()
	var diagonal := bounds.size.length()
	# Adapt preview zoom to the selected frame instead of cropping 10-inch builds
	# or making small cinewhoops look like dots.
	_cam_dist = clampf(diagonal * 1.38, 0.24, 1.80)
	_update_cam_transform()


func _instantiate_mesh(path: String) -> Node3D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var inst := packed.instantiate() as Node3D
	return inst


# ==============================================================================
# 5. REAL-TIME TTX, BALANCE & COMPATIBILITY CALCULATION
# ==============================================================================
func _update_telemetry() -> void:
	if not _parts_by_id.has(_current_build["frame"]):
		return
	var is_en := MenuUI.is_english()

	var frame: Dictionary = _parts_by_id[_current_build["frame"]]
	var motor: Dictionary = _parts_by_id[_current_build["motor"]]
	var prop: Dictionary = _parts_by_id[_current_build["prop"]]
	var battery: Dictionary = _parts_by_id[_current_build["battery"]]
	var camera: Dictionary = _parts_by_id[_current_build["camera"]]
	var payload: Dictionary = _parts_by_id[_current_build["payload"]]

	# 1. AUW (All Up Weight)
	var m_frame := float(frame.get("weight_g", 0))
	var m_motors := float(motor.get("weight_g", 0)) * 4.0
	var m_props := float(prop.get("weight_g", 0)) * 4.0
	var m_batt := float(battery.get("weight_g", 0))
	var m_cam := float(camera.get("weight_g", 0))
	var m_payload := float(payload.get("weight_g", 0))
	var m_electronics := 35.0 # Flight Controller, ESC 4in1, VTX, Antenna

	var total_mass_g := m_frame + m_motors + m_props + m_batt + m_cam + m_payload + m_electronics
	var total_mass_kg := total_mass_g / 1000.0

	# 2. Total Thrust
	var total_thrust_g := float(motor.get("thrust_g", 0)) * 4.0

	# 3. TWR & Hover Throttle
	var twr := total_thrust_g / maxf(1.0, total_mass_g)
	var hover_throttle := clampf((1.0 / twr) * 100.0, 8.0, 99.0)

	# 4. Estimated Flight Time
	var mah := float(battery.get("capacity_mah", 1500))
	var volts := float(battery.get("voltage_v", 14.8))
	var energy_wh := (mah / 1000.0) * volts * 0.80 # 80% usable LiPo/Li-Ion capacity
	var hover_power_w := total_mass_kg * 165.0 # Average 165 W/kg hover efficiency
	var flight_time_min := (energy_wh / maxf(10.0, hover_power_w)) * 60.0

	# Update Labels
	if _val_mass != null:
		_val_mass.text = ("%d g (%.2f kg)" if is_en else "%d г (%.2f кг)") % [int(total_mass_g), total_mass_kg]
	if _val_thrust != null:
		_val_thrust.text = ("%d g (%.2f kg)" if is_en else "%d г (%.2f кг)") % [int(total_thrust_g), total_thrust_g / 1000.0]
	if _val_twr != null:
		_val_twr.text = "%.2f : 1" % twr
		_val_twr.add_theme_color_override("font_color", _get_twr_color(twr))
	if _val_hover != null:
		_val_hover.text = "%d %%" % int(hover_throttle)
	if _val_time != null:
		_val_time.text = ("%.1f min" if is_en else "%.1f хв") % flight_time_min

	# Dynamic TWR badge
	if _badge_twr != null:
		if twr < 1.8:
			_badge_twr.text = "⚠️ CRITICAL OVERLOAD: UNCONTROLLABLE" if is_en else "⚠️ КРИТИЧНЕ ПЕРЕВАНТАЖЕННЯ: ВТРАТА КЕРОВАНОСТІ"
			_badge_twr.add_theme_color_override("font_color", MenuUI.DANGER)
		elif twr < 3.0:
			_badge_twr.text = "⚡ HEAVY TACTICAL (HIGH INERTIA)" if is_en else "⚡ ТАКТИЧНИЙ ВАНТАЖНИЙ (ВИСОКА ІНЕРЦІЯ)"
			_badge_twr.add_theme_color_override("font_color", MenuUI.WARN_AMBER)
		elif twr < 6.0:
			_badge_twr.text = "🚀 BALANCED / FREESTYLE (OPTIMAL RESPONSE)" if is_en else "🚀 ЗБАЛАНСОВАНИЙ / ФРІСТАЙЛ (ОПТИМАЛЬНА ДИНАМІКА)"
			_badge_twr.add_theme_color_override("font_color", MenuUI.ACCENT)
		else:
			_badge_twr.text = "⚡⚡ EXTREME SPORT / RACING" if is_en else "⚡⚡ ЕКСТРЕМАЛЬНИЙ СПОРТ / РЕЙСИНГ"
			_badge_twr.add_theme_color_override("font_color", MenuUI.MIL_GREEN_LIGHT)

	# Combat Profile Matrix
	var is_pg7 := (str(payload.get("id")) == "payload_kamikaze_pg7")
	var is_vog := (str(payload.get("id")) == "payload_drop_vog")

	if _val_combat_type != null:
		if is_pg7:
			_val_combat_type.text = "STRIKE / KAMIKAZE" if is_en else "УДАРНИЙ КАМІКАДЗЕ"
			_val_combat_type.add_theme_color_override("font_color", MenuUI.DANGER)
		elif is_vog:
			_val_combat_type.text = "BOMBER" if is_en else "БОМБАРДУВАЛЬНИК"
			_val_combat_type.add_theme_color_override("font_color", MenuUI.WARN_AMBER)
		else:
			_val_combat_type.text = "SPORT / RECON" if is_en else "СПОРТ / РОЗВІДКА"
			_val_combat_type.add_theme_color_override("font_color", MenuUI.ACCENT)

	if _val_detonator != null:
		if is_pg7:
			_val_detonator.text = "FUZE: ACTIVE (contact probes) · Penetration: 650 mm RHA" if is_en else "ДЕТОНАТОР: АКТИВОВАНО (контактні датчики) · Бронепробивність: 650 мм RHA"
			_val_detonator.add_theme_color_override("font_color", MenuUI.DANGER)
		elif is_vog:
			_val_detonator.text = "RELEASE SYSTEM: READY · Fragmentation radius: 7.5 m" if is_en else "СИСТЕМА СКИДУ: ГОТОВА · Радіус ураження: 7,5 м"
			_val_detonator.add_theme_color_override("font_color", MenuUI.WARN_AMBER)
		else:
			_val_detonator.text = "PAYLOAD: NONE (CLEAN FLIGHT)" if is_en else "НАВАНТАЖЕННЯ: ВІДСУТНЄ (ЧИСТИЙ ПОЛІТ)"
			_val_detonator.add_theme_color_override("font_color", MenuUI.MUTED)

	# Compatibility & Dimension Check
	_check_compatibility(frame, motor, prop, battery, payload, twr)


func _get_twr_color(twr: float) -> Color:
	if twr < 1.8:
		return MenuUI.DANGER
	if twr < 3.0:
		return MenuUI.WARN_AMBER
	return MenuUI.ACCENT


func _check_compatibility(frame: Dictionary, motor: Dictionary, prop: Dictionary,
		battery: Dictionary, payload: Dictionary, twr: float) -> void:
	if _compat_label == null:
		return

	var errors: Array[String] = []
	var warnings: Array[String] = []
	var is_en := MenuUI.is_english()

	var frame_size: float = float(frame.get("size_inch", 5.0))
	var prop_d: float = float(prop.get("diameter_inch", 5.1))
	var batt_w: float = float(battery.get("weight_g", 180))
	var max_batt_w: float = float(frame.get("max_battery_weight", 500))
	var kv: int = int(motor.get("kv_rating", 2450))

	# 1. Prop size vs Frame size
	if prop_d > (frame_size + 0.3):
		errors.append(("❌ ERROR: %s\" propeller is too large for the %s\" frame; blades may overlap." if is_en else "❌ ПОМИЛКА: пропелер %s\" завеликий для рами %s\" — лопаті можуть перетинатися.") % [str(prop_d), str(frame_size)])

	# 2. Battery weight limit
	if batt_w > max_batt_w:
		warnings.append(("⚠️ OVERWEIGHT: battery (%d g) exceeds frame limit (%d g)." if is_en else "⚠️ ПЕРЕВАНТАЖЕННЯ: батарея (%d г) перевищує ліміт рами (%d г).") % [int(batt_w), int(max_batt_w)])

	# 3. Motor KV vs Prop Diameter
	if kv > 2000 and prop_d > 6.5:
		warnings.append(("⚠️ OVERHEAT RISK: high-KV motor (%d KV) is not suited to props over 6.5\"." if is_en else "⚠️ РИЗИК ПЕРЕГРІВУ: мотор із високим KV (%d) не призначений для пропелерів понад 6,5\".") % kv)

	# 4. Small frame + Heavy PG7
	if str(payload.get("id")) == "payload_kamikaze_pg7" and frame_size < 7.0:
		errors.append(("❌ UNSAFE: %s\" frame is too small for the 1.45 kg PG-7 payload. Use a 10\" frame." if is_en else "❌ НЕБЕЗПЕЧНО: рама %s\" замала для БЧ ПГ-7 масою 1,45 кг. Потрібна рама 10\".") % str(frame_size))

	# 5. TWR Critical
	if twr < 1.6:
		errors.append(("❌ INSUFFICIENT THRUST (TWR %.2f): the aircraft cannot take off with this load." if is_en else "❌ НЕДОСТАТНЯ ТЯГА (TWR %.2f): дрон не зможе злетіти з таким навантаженням.") % twr)

	if not errors.is_empty():
		_compat_label.text = "\n".join(errors)
		_compat_label.add_theme_color_override("font_color", MenuUI.DANGER)
	elif not warnings.is_empty():
		_compat_label.text = "\n".join(warnings)
		_compat_label.add_theme_color_override("font_color", MenuUI.WARN_AMBER)
	else:
		_compat_label.text = "✅ ALL COMPONENTS COMPATIBLE\nGeometry, thrust, and balance are within the configured limits." if is_en else "✅ УСІ КОМПОНЕНТИ СУМІСНІ\nГеометрія, тяга та баланс відповідають заданим вимогам."
		_compat_label.add_theme_color_override("font_color", MenuUI.ACCENT)
