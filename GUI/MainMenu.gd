## Ukrainian Military Tactical Terminal (C2 / Mil-Tech) Main Menu.
## Features:
##   1. Left Panel: Mode & Mission selection, live Recon Map Preview, and prominent Launch Button.
##   2. Right Panel: Active Drone Intel, Interactive 3D Rotatable Drone Viewport, and System Navigation.
##   3. Tactical C2 aesthetic (MGRS grid, phosphor green, armor border, amber alerts).
extends Control

const LEVEL := "res://sceneries/BigLevel.tscn"
const FRONTLINE_LEVELS := {
	"valley": "res://sceneries/BigLevel.tscn",
	"steppe": "res://sceneries/SteppeLevel.tscn",
	"village": "res://sceneries/VillageLevel.tscn",
	"industrial": "res://sceneries/IndustrialLevel.tscn",
	"wetlands": "res://sceneries/WetlandsLevel.tscn",
}
## The old valley/BigLevel scene is the legacy test range.  It stays in
## FRONTLINE_LEVELS because TAC-05 (the naval mission) still uses it, but it is
## never offered as a normal map: only the four finished frontline maps are.
const SELECTABLE_MAPS := ["steppe", "village", "industrial", "wetlands"]
const SPECIAL_MISSIONS := [
	{"id": 1, "code": "REC-01", "name": "Розвідка", "name_en": "Reconnaissance", "desc": "Пройти 3 зони спостереження", "desc_en": "Survey all three observation zones.", "diff": "Легка", "diff_en": "Easy", "col": Color("79a58a")},
	{"id": 2, "code": "ESC-02", "name": "Супровід", "name_en": "Convoy Escort", "desc": "Провести дружню колону", "desc_en": "Escort the friendly convoy to its destination.", "diff": "Середня", "diff_en": "Medium", "col": Color("e2c276")},
	{"id": 3, "code": "EVAC-03", "name": "Евакуація", "name_en": "Pilot Extraction", "desc": "Забрати пілота й повернутися", "desc_en": "Locate the downed pilot and return to base.", "diff": "Середня", "diff_en": "Medium", "col": Color("e2c276")},
	{"id": 4, "code": "CARG-04", "name": "Доставка вантажу", "name_en": "Cargo Delivery", "desc": "Забрати й доставити вантаж", "desc_en": "Recover and deliver the cargo.", "diff": "Легка", "diff_en": "Easy", "col": Color("79a58a")},
	{"id": 5, "code": "NGHT-05", "name": "Нічний виліт", "name_en": "Night Strike", "desc": "Удар по ЗРК у темряві", "desc_en": "Strike the SAM site under cover of darkness.", "diff": "Важка", "diff_en": "Hard", "col": Color("c96f67")},
	{"id": 6, "code": "EW-06", "name": "Прорив РЕБ", "name_en": "EW Breach", "desc": "Пробитися крізь глушіння", "desc_en": "Penetrate the enemy electronic-warfare jamming zone.", "diff": "Екстрим", "diff_en": "Extreme", "col": Color("c96f67")},
	{"id": 7, "code": "CONV-07", "name": "Тилова колона", "name_en": "Rear-Area Convoy", "desc": "Знищити колону забезпечення: Урал, МТ-СМ, БТР", "desc_en": "Destroy the supply convoy: Ural truck, MTSM carrier, and BTR.", "diff": "Середня", "diff_en": "Medium", "col": Color("e2c276")},
	{"id": 8, "code": "MSL-08", "name": "Орешник", "name_en": "Oreshnik Strike", "desc": "Знищити ракетний комплекс і його охорону", "desc_en": "Destroy the Oreshnik launcher and its escort.", "diff": "Важка", "diff_en": "Hard", "col": Color("c96f67")},
	{"id": 9, "code": "DEEP-09", "name": "Глибокий тил", "name_en": "Deep-Strike Operation", "desc": "Комбінований удар по тиловій базі", "desc_en": "Conduct a combined strike on the rear-area base.", "diff": "Екстрим", "diff_en": "Extreme", "col": Color("c96f67")},
	{"id": 10, "code": "MSL-10", "name": "Перехоплення ракет", "name_en": "Cruise Missile Intercept", "desc": "Відбити 6 хвиль — по одній крилатій ракеті", "desc_en": "Defend against 6 waves of single cruise missiles.", "diff": "Екстрим", "diff_en": "Extreme", "col": Color("c96f67")},
]
const START_SCREEN := "res://GUI/StartScreen.tscn"
const GRAPHICS_SCREEN := "res://GUI/GraphicsScreen.tscn"
const CALIBRATION_SCREEN := "res://GUI/CalibrationScreen.tscn"
const OTHER_SCREEN := "res://GUI/OtherSettingsScreen.tscn"
const HELP_SCREEN := "res://GUI/HelpScreen.tscn"
const CONTROLS_SCREEN := "res://GUI/ControlsScreen.tscn"
const DRONE_SCREEN := "res://GUI/DroneSelectScreen.tscn"
const OPTIONS_SCREEN := "res://GUI/OptionsMenu.tscn"
const DronePropellerSystem = preload("res://scripts/util/DronePropellerSystem.gd")
const LocScript = preload("res://scripts/util/localization_manager.gd")

# Selection state
var _selected_mode: int = Global.PlayMode.TUTORIAL
var _selected_mission: int = 1
var _selected_map := "village"

# UI Element references for live updates
var _mode_buttons: Dictionary = {}
var _map_buttons: Dictionary = {}
var _mission_buttons: Dictionary = {}
var _mission_code_labels: Dictionary = {}
var _special_mission_btns: Dictionary = {}
var _selected_special := 0
var _quick_diff_btns: Dictionary = {}
var _quick_diff_lbl: Label = null
var _quick_diff_container: VBoxContainer = null
var _realism_profile_btns: Dictionary = {}
var _realism_checks: Dictionary = {}
var _realism_hint: Label = null
var _realism_container: VBoxContainer = null
var _briefing_btn: Button = null
var _map_canvas: _TacticalMapCanvas = null
var _map_title_lbl: Label = null
var _map_obj_lbl: Label = null
var _map_stats_lbl: Label = null
var _launch_btn: Button = null
var _drone_title_lbl: Label = null
var _drone_sub_lbl: Label = null
var _prev_drone_btn: Button = null
var _next_drone_btn: Button = null
var _top_title_lbl: Label = null
var _top_vtx_lbl: Label = null
var _rc_status_lbl: Label = null
var _top_palette_btn: Button = null
var _lang_btn: Button = null
var _gc_btn: Button = null
var _daily_lbl: Label = null
var _quick_tut_btn: Button = null
var _quick_ct_btn: Button = null
var _foot_status_lbl: Label = null
var _settings_overlay: Control = null
var _mode_copy: Dictionary = {}

# Tactical Mission Briefing Modal references
var _briefing_modal: Control = null
var _briefing_title_lbl: Label = null
var _briefing_sub_lbl: Label = null
var _briefing_intel_lbl: Label = null
var _briefing_tasks_vbox: VBoxContainer = null
var _briefing_threats_lbl: Label = null
var _briefing_drone_lbl: Label = null
var _briefing_weather_lbl: Label = null
var _briefing_rewards_lbl: Label = null
var _briefing_record_lbl: Label = null
var _briefing_diff_btns: Dictionary = {}
var _briefing_diff_desc: Label = null
var _briefing_map_canvas: _TacticalMapCanvas = null
var _campaign_progress_lbl: Label = null
var _continue_campaign_btn: Button = null

# 3D Drone Viewport references & camera rotation state
var _viewport_container: SubViewportContainer = null
var _sub_viewport: SubViewport = null
var _camera: Camera3D = null
var _model_holder: Node3D = null
var _cam_yaw: float = 0.55
var _cam_pitch: float = 0.26
var _cam_dist: float = 1.05
var _auto_cam_dist: float = 1.05
var _preview_focus_y: float = -0.08
var _is_dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _auto_orbit: bool = true
var _auto_orbit_btn: Button = null
var _ribbon_buttons: Dictionary = {}


# ==============================================================================
# CAMPAIGN MISSION BRIEFINGS DOSSIER
# ==============================================================================
const BRIEFINGS := {
	1: {
		"code": "TAC-01",
		"name": "ПІХОТА В УКРИТТЯХ",
		"op_name": "ОПЕРАЦІЯ «ЧИСТЕ ПОЛЕ»",
		"sector": "Сектор «Альфа-1» · Навчальний рубіж",
		"time": "20:00 хв",
		"diff": "ЛЕГКА",
		"desc": "Виявлення та ураження умовних цілей в окопах та бліндажах.",
		"intel": "Розвідкою БПЛА виявлено передові спостережні пункти та навчальні вогневі позиції в лісосмузі вздовж польової дороги. Умовний противник закріпився в польових укриттях та траншеях.",
		"tasks": [
			"Виявити та знешкодити 6 умовних цілей у навчальному секторі",
			"Виконати точне скидання або керований захід у фортифікаційні споруди",
			"Уникати зустрічного вогню на гранично малих висотах"
		],
		"threats": [
			"Стрілецька зброя (АК-74 / ПКМ) — прицільний радіус до 45м",
			"Маскування під кронами дерев та в польових траншеях"
		],
		"drone": "7\" Квадрокоптер зі скидами (ВОГ-17) або 8\" Ударний FPV",
		"weather": "Вітер: помірний 3–5 м/с · Видимість 100% · Світла пора доби",
		"rewards": [
			"★★★ Золотий Хрест (Ас): Час < 4:00 або складна ліквідація на рівні «Ас»",
			"★★ Срібна відзнака: Час < 8:00 або рівень «Оператор»",
			"★ Бронзова відзнака: Успішна зачистка всіх 6 цілей"
		]
	},
	2: {
		"code": "TAC-02",
		"name": "КОЛОНА БРОНЕТЕХНІКИ",
		"op_name": "ОПЕРАЦІЯ «СТАЛЕВИЙ ПРИМАРК»",
		"sector": "Маршрут S-40 · Навчальний коридор",
		"time": "20:00 хв",
		"diff": "СЕРЕДНЯ",
		"desc": "Ураження макетів танка Т-72Б та БТР-82А на марші.",
		"intel": "Навчальна бронегрупа у складі танка Т-72Б та колісного БТР-82А висувається маршрутом у степовому секторі. Техніка рухається колоною під прикриттям бортових систем.",
		"tasks": [
			"Знищити головний танк Т-72Б (удар у дах башти або корму двигуна)",
			"Уразити бронетранспортер БТР-82А (бортова проекція або відсік МТО)",
			"Знешкодити колону до досягнення рубежу розгортання"
		],
		"threats": [
			"30-мм автоматична гармата 2А72 на БТР-82А (високий темп вогню)",
			"Зенітний кулемет Корд на командирській вежі Т-72Б",
			"Комбінована броня та динамічний захист «Контакт-1»"
		],
		"drone": "10\" Важкий ударний FPV з кумулятивним макетом БЧ (ПГ-7ВР)",
		"weather": "Вітер: поривчастий 5–8 м/с · Локальне задимлення палаючої посадки",
		"rewards": [
			"★★★ Золотий Хрест (Ас): Час < 5:00 або рівень «Ас»",
			"★★ Срібна відзнака: Час < 9:00 або рівень «Оператор»",
			"★ Бронзова відзнака: Повне знищення бронегрупи"
		]
	},
	3: {
		"code": "TAC-03",
		"name": "УДАРНИЙ ГЕЛІКОПТЕР",
		"op_name": "ОПЕРАЦІЯ «РОЗПРАВЛЕНІ КРИЛА»",
		"sector": "Повітряний ешелон 20–30 м · Русло річки · Азимут 085°",
		"time": "20:00 хв",
		"diff": "ВАЖКА",
		"desc": "Низьковисотне перехоплення повітряної цілі.",
		"intel": "Навчальний гелікоптер типу Мі-8/Ка-52 баражує на гранично малій висоті (20–30 м) зі швидкістю до 45 км/год вздовж річкового русла. Необхідно зайти на зустрічно-пересічний курс.",
		"tasks": [
			"Набрати висоту 20–30 метрів по вектору руху борту",
			"Здійснити лобовий або верхній таран несучого гвинта або кабіни екіпажу",
			"Компенсувати потужну аеродинамічну турбулентність лопатей (downwash)"
		],
		"threats": [
			"Швидкість зближення до 45 км/год",
			"Потужний індуктивний потік від гвинтів (ризик зриву потоку дрона)",
			"Бортові кулеметні розрахунки"
		],
		"drone": "7\"–8\" Високошвидкісний перехоплювач (3000 KV, TWR 8.5:1)",
		"weather": "Турбулентність, висхідні потоки гарячого повітря над схилами",
		"rewards": [
			"★★★ Золотий Хрест (Ас): Час < 3:30 або рівень «Ас»",
			"★★ Срібна відзнака: Час < 7:00 або рівень «Оператор»",
			"★ Бронзова відзнака: Збиття гелікоптера противника"
		]
	},
	4: {
		"code": "TAC-04",
		"name": "БАРАЖУЮЧИЙ БПЛА-136",
		"op_name": "ОПЕРАЦІЯ «ЧИСТЕ НЕБО»",
		"sector": "Ешелон 18–30 м · курс 240° · швидкість 58–72 км/год",
		"time": "20:00 хв",
		"diff": "ЕКСТРЕМ",
		"desc": "Повітряне перехоплення високошвидкісної БПЛА-мішені «Дельта-136».",
		"intel": "Радіолокаційними постами полігону зафіксовано одиночний високошвидкісний БПЛА-мішень «Дельта-136», що прямує на захищений енерговузол. Крейсерська швидкість 58–72 км/год за автопілотом. Час на реакцію обмежений.",
		"tasks": [
			"Вийти на точку рандеву з випередженням курсу цілі",
			"Розігнати перехоплювач до максимальної швидкості у похилому пікіруванні",
			"Здійснити кінетичний таран штовхаючого гвинта або кореневої частини крила"
		],
		"threats": [
			"Швидкість цілі 58–72 км/год",
			"Обмежене вікно перехоплення до виходу з радіусу телеметрії",
			"Висока кінетична енергія при зіткненні"
		],
		"drone": "7\" FPV-перехоплювач з екстремальним TWR (10:1)",
		"weather": "Сутінки, слабкий боковий вітер",
		"rewards": [
			"★★★ Золотий Хрест (Ас): Час < 3:00 або рівень «Ас»",
			"★★ Срібна відзнака: Час < 6:00 або рівень «Оператор»",
			"★ Бронзова відзнака: Перехоплення БПЛА «Дельта-136»"
		]
	}
}

const BRIEFINGS_EN := {
	1: {
		"name": "INFANTRY IN COVER",
		"op_name": "OPERATION \"CLEAR FIELD\"",
		"sector": "Sector Alpha-1 · Training Range",
		"intel": "Recon has identified forward observation posts and range positions in a tree line along a farm road. Simulated OPFOR targets are positioned in field shelters and trenches overlooking the approach route.",
		"tasks": ["Locate and neutralize six range targets", "Strike or drop payloads into fortified positions", "Avoid defensive fire at very low altitude"],
		"threats": ["Small arms fire, effective range up to 45 m", "Camouflaged positions under trees and in trenches"],
		"drone": "7-inch quad with VOG-17 drop system or an 8-inch strike quad",
		"weather": "Moderate wind: 3–5 m/s · Visibility: clear · Daylight",
		"rewards": ["★★★ Gold Cross (Ace): under 4:00 or complete on Ace", "★★ Silver award: under 8:00 or complete on Operator", "★ Bronze award: clear all six range targets"]
	},
	2: {
		"name": "ARMORED COLUMN",
		"op_name": "OPERATION \"STEEL PHANTOM\"",
		"sector": "Route S-40 · Training Corridor",
		"intel": "A simulated OPFOR armor group—one T-72B tank and one BTR-82A APC—is moving along the training route. The column is escorted by onboard defensive systems.",
		"tasks": ["Disable the lead T-72B (turret roof or rear engine deck)", "Disable the BTR-82A from the side or engine compartment", "Stop the column before it reaches its deployment line"],
		"threats": ["BTR-82A 30 mm autocannon", "Turret machine gun on the T-72B", "Composite and reactive armor plating"],
		"drone": "10-inch heavy strike quad with shaped-charge payload",
		"weather": "Gusty wind: 5–8 m/s · Local smoke over the tree line",
		"rewards": ["★★★ Gold Cross (Ace): under 5:00 or complete on Ace", "★★ Silver award: under 9:00 or complete on Operator", "★ Bronze award: disable the entire armor group"]
	},
	3: {
		"name": "ATTACK HELICOPTER",
		"op_name": "OPERATION \"WINGS CLIPPED\"",
		"sector": "Air corridor · 20–30 m AGL · Riverbed · Heading 085°",
		"intel": "A simulated Mi-8 / Ka-52 helicopter target is flying low along the river at 20–30 m and up to 45 km/h. Intercept on a crossing or head-on course.",
		"tasks": ["Climb to 20–30 m along the aircraft's flight vector", "Intercept the rotor or cockpit on a crossing course", "Compensate for severe rotor-wash turbulence"],
		"threats": ["Closing speed up to 45 km/h", "Strong rotor downwash may destabilize the quad", "Side defensive fire arcs"],
		"drone": "7–8-inch high-speed interceptor (3000 KV, TWR 8.5:1)",
		"weather": "Turbulence · Ridge updrafts and hot-air currents",
		"rewards": ["★★★ Gold Cross (Ace): under 3:30 or complete on Ace", "★★ Silver award: under 7:00 or complete on Operator", "★ Bronze award: intercept the helicopter"]
	},
	4: {
		"name": "LOITERING UAV-136",
		"op_name": "OPERATION \"CLEAR SKY\"",
		"sector": "Air corridor · 18–30 m AGL · Heading 240° · 58–72 km/h",
		"intel": "Range radar has detected a Delta-136 target UAV heading toward a simulated power node. It is flying on autopilot at 58–72 km/h; the interception window is short.",
		"tasks": ["Reach the rendezvous point ahead of the target", "Build speed in a shallow dive", "Intercept the pusher propeller or wing root"],
		"threats": ["Target speed: 58–72 km/h", "Short interception window before telemetry is lost", "High kinetic energy on impact"],
		"drone": "7-inch FPV interceptor with extreme thrust-to-weight ratio (10:1)",
		"weather": "Twilight · Light crosswind",
		"rewards": ["★★★ Gold Cross (Ace): under 3:00 or complete on Ace", "★★ Silver award: under 6:00 or complete on Operator", "★ Bronze award: intercept the Delta-136 UAV"]
	}
}


# ==============================================================================
# TACTICAL RECON MAP CANVAS (Custom procedural 2D radar/map widget)
# ==============================================================================
class _TacticalMapCanvas extends Control:
	var mode: int = Global.PlayMode.COMBAT
	var mission_id: int = 1

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, 110)

	func set_selection(p_mode: int, p_mission: int) -> void:
		mode = p_mode
		mission_id = p_mission
		queue_redraw()

	func _draw_map_text(font: Font, position: Vector2, source_text: String,
			font_size: int, color: Color, alignment: int = HORIZONTAL_ALIGNMENT_LEFT) -> void:
		var text := MenuUI.translate_text(source_text)
		var safe_width := maxf(24.0, size.x - 16.0)
		var measured := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var truncated := false
		while measured > safe_width and text.length() > 2:
			text = text.left(text.length() - 1)
			measured = font.get_string_size(text + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			truncated = true
		if truncated:
			text += "…"
		if alignment == HORIZONTAL_ALIGNMENT_CENTER:
			var fitted_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			position.x = maxf(4.0, (size.x - fitted_width) * 0.5)
		else:
			position.x = clampf(position.x, 4.0, maxf(4.0, size.x - measured - 4.0))
		draw_string(font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

	func _draw() -> void:
		var sz := size
		if sz.x <= 8.0 or sz.y <= 8.0:
			return

		# 1. Base dark modern card
		draw_rect(Rect2(Vector2.ZERO, sz), MenuUI.FPV_BG_CARD, true)
		draw_rect(Rect2(Vector2.ZERO, sz), MenuUI.FPV_BORDER, false, 1.0)

		# 2. Minor coordinate grid
		var grid_col := Color(0.18, 0.24, 0.35, 0.25)
		var step := 28.0
		var x := step
		while x < sz.x:
			draw_line(Vector2(x, 0), Vector2(x, sz.y), grid_col, 1.0)
			x += step
		var y := step
		while y < sz.y:
			draw_line(Vector2(0, y), Vector2(sz.x, y), grid_col, 1.0)
			y += step

		# 3. Concentric radar ranges & azimuth crosshair
		var center := sz * 0.5
		var radar_col := Color(0.22, 0.55, 0.85, 0.15)
		draw_arc(center, minf(sz.y * 0.38, sz.x * 0.24), 0.0, TAU, 36, radar_col, 1.0)
		draw_arc(center, minf(sz.y * 0.72, sz.x * 0.44), 0.0, TAU, 36, radar_col, 1.0)
		draw_line(Vector2(center.x, 6), Vector2(center.x, sz.y - 6), radar_col, 1.0)
		draw_line(Vector2(10, center.y), Vector2(sz.x - 10, center.y), radar_col, 1.0)

		# Compass indicators
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(center.x - 4, 12), "N", HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(0.6, 0.75, 0.9, 0.7))
		draw_string(font, Vector2(sz.x - 14, center.y + 4), "E", HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(0.6, 0.75, 0.9, 0.7))

		# 4. Friendly FPV launch point (Base)
		var base_pos := center + Vector2(-sz.x * 0.32, sz.y * 0.22)
		draw_circle(base_pos, 3.5, MenuUI.FPV_BLUE)
		draw_arc(base_pos, 7.0, 0.0, TAU, 20, Color(0.2, 0.6, 1.0, 0.5), 1.0)
		_draw_map_text(font, base_pos + Vector2(9, 3), "СТАРТ FPV", 11, MenuUI.FPV_CYAN)

		# 5. Mission-specific tactical overlays
		if mode == Global.PlayMode.COMBAT:
			_draw_combat_recon(sz, center, base_pos, font)
		elif mode == Global.PlayMode.TRAINING:
			_draw_training_recon(sz, center, base_pos, font)
		elif mode == Global.PlayMode.TUTORIAL:
			_draw_tutorial_recon(sz, center, base_pos, font)

	func _draw_combat_recon(sz: Vector2, center: Vector2, base_pos: Vector2, font: Font) -> void:
		var tgt_red := Color(0.95, 0.28, 0.22, 0.95)
		var amber := Color(0.92, 0.69, 0.21, 0.90)

		# Flight sector line from base
		var sector_target := center + Vector2(sz.x * 0.15, -sz.y * 0.10)
		draw_dashed_line(base_pos, sector_target, Color(0.2, 0.9, 0.8, 0.35), 1.0, 3.5)

		if mission_id == 1:
			# TAC-01: INFANTRY
			var targets := [
				Vector2(center.x - 10, center.y - 18),
				Vector2(center.x + 35, center.y - 8),
				Vector2(center.x + 80, center.y - 26),
				Vector2(center.x + 115, center.y + 12),
				Vector2(center.x + 60, center.y + 26),
			]
			for i in range(targets.size()):
				var tp: Vector2 = targets[i]
				draw_rect(Rect2(tp - Vector2(3, 3), Vector2(6, 6)), tgt_red, true)
				_draw_map_text(font, tp + Vector2(7, 3), ("INF-%d" if MenuUI.is_english() else "ПІХ-%d") % (i + 1), 10, tgt_red)
			_draw_map_text(font, Vector2(center.x - 20, sz.y - 6), "СЕКТОР: ОКОПНА ЛІНІЯ / ПОСАДКА", 11, amber, HORIZONTAL_ALIGNMENT_CENTER)

		elif mission_id == 2:
			# TAC-02: ARMOR
			var p1 := Vector2(center.x - 50, center.y + 25)
			var p2 := Vector2(center.x + 130, center.y - 35)
			draw_line(p1 - Vector2(25, -12), p2 + Vector2(25, -12), Color(0.4, 0.45, 0.4, 0.5), 2.5)

			var tank_pos := center + Vector2(40, -8)
			var btr_pos := center + Vector2(95, -24)
			# Tank diamond
			draw_line(tank_pos + Vector2(0, -5), tank_pos + Vector2(5, 0), tgt_red, 1.5)
			draw_line(tank_pos + Vector2(5, 0), tank_pos + Vector2(0, 5), tgt_red, 1.5)
			draw_line(tank_pos + Vector2(0, 5), tank_pos + Vector2(-5, 0), tgt_red, 1.5)
			draw_line(tank_pos + Vector2(-5, 0), tank_pos + Vector2(0, -5), tgt_red, 1.5)
			_draw_map_text(font, tank_pos + Vector2(8, 3), "Т-72Б", 11, tgt_red)

			# BTR diamond
			draw_line(btr_pos + Vector2(0, -4), btr_pos + Vector2(4, 0), amber, 1.5)
			draw_line(btr_pos + Vector2(4, 0), btr_pos + Vector2(0, 4), amber, 1.5)
			draw_line(btr_pos + Vector2(0, 4), btr_pos + Vector2(-4, 0), amber, 1.5)
			draw_line(btr_pos + Vector2(-4, 0), btr_pos + Vector2(0, -4), amber, 1.5)
			_draw_map_text(font, btr_pos + Vector2(7, 3), "БТР-82А", 10, amber)
			_draw_map_text(font, Vector2(center.x - 20, sz.y - 6), "КОЛОНА НА МАРШІ (ЗАГРОЗА ППО)", 11, amber, HORIZONTAL_ALIGNMENT_CENTER)

		elif mission_id == 3:
			# TAC-03: HELICOPTER
			var heli_pos := center + Vector2(65, -12)
			draw_circle(heli_pos, 4.0, tgt_red)
			draw_arc(heli_pos, 9.0, 0.0, TAU, 18, tgt_red, 1.1)
			draw_line(heli_pos, heli_pos + Vector2(-36, 10), tgt_red, 1.4)
			_draw_map_text(font, heli_pos + Vector2(12, -3), "МІ-8 / КА-52", 11, tgt_red)
			_draw_map_text(font, heli_pos + Vector2(12, 7), "20–30 м · 45 км/год", 10, amber)
			_draw_map_text(font, Vector2(center.x - 20, sz.y - 6), "ПЕРЕХОПЛЕННЯ В ПОВІТРІ", 11, amber, HORIZONTAL_ALIGNMENT_CENTER)

		elif mission_id == 4:
			# TAC-04: DELTA-136
			var sh_pos := center + Vector2(75, -20)
			draw_line(sh_pos + Vector2(7, 0), sh_pos + Vector2(-7, -5), tgt_red, 1.6)
			draw_line(sh_pos + Vector2(-7, -5), sh_pos + Vector2(-3, 0), tgt_red, 1.6)
			draw_line(sh_pos + Vector2(-3, 0), sh_pos + Vector2(-7, 5), tgt_red, 1.6)
			draw_line(sh_pos + Vector2(-7, 5), sh_pos + Vector2(7, 0), tgt_red, 1.6)
			draw_line(sh_pos, sh_pos + Vector2(-48, 18), tgt_red, 1.4)
			_draw_map_text(font, sh_pos + Vector2(11, -3), "ДЕЛЬТА-136", 11, tgt_red)
			_draw_map_text(font, sh_pos + Vector2(11, 7), "58–72 км/год · КУРС 240°", 10, tgt_red)
			_draw_map_text(font, Vector2(center.x - 20, sz.y - 6), "ШВИДКІСНИЙ ПЕРЕХОПЛЮВАЧ", 11, tgt_red, HORIZONTAL_ALIGNMENT_CENTER)

	func _draw_training_recon(sz: Vector2, center: Vector2, base_pos: Vector2, font: Font) -> void:
		var green := Color(0.4, 0.85, 0.35, 0.85)
		var box_rect := Rect2(center - Vector2(sz.x * 0.25, sz.y * 0.32), Vector2(sz.x * 0.62, sz.y * 0.64))
		draw_rect(box_rect, Color(0.3, 0.7, 0.3, 0.08), true)
		draw_rect(box_rect, green, false, 1.1)
		_draw_map_text(font, box_rect.position + Vector2(6, 13), "ЗОНА ВІЛЬНОГО ПОЛЬОТУ", 11, green)

		var pts := PackedVector2Array([
			Vector2(center.x - 40, sz.y - 10),
			Vector2(center.x - 10, center.y + 8),
			Vector2(center.x + 30, center.y - 8),
			Vector2(center.x + 90, 14)
		])
		draw_polyline(pts, Color(0.35, 0.6, 0.4, 0.35), 1.8)
		_draw_map_text(font, Vector2(center.x + 10, center.y + 18), "РУСЛО ДОЛИНИ", 10, Color(0.65, 0.8, 0.65, 0.7))
		_draw_map_text(font, Vector2(center.x - 20, sz.y - 6), "БЕЗ БОЙОВИХ ЗАГРОЗ · ВІЛЬНИЙ ПОЛІТ І ТРАСА", 11, green, HORIZONTAL_ALIGNMENT_CENTER)

	func _draw_tutorial_recon(sz: Vector2, center: Vector2, base_pos: Vector2, font: Font) -> void:
		var green := Color(0.35, 0.95, 0.45, 0.9)
		var amber := Color(0.92, 0.69, 0.21, 0.9)
		var cyan := Color(0.2, 0.9, 0.8, 0.9)

		var hover_pos := base_pos + Vector2(25, -15)
		var gate1 := hover_pos + Vector2(35, -15)
		var gate2 := gate1 + Vector2(35, 10)
		var gate3 := gate2 + Vector2(35, -20)
		var flare := gate3 + Vector2(30, 15)
		var pad := flare + Vector2(25, 0)

		var route := PackedVector2Array([base_pos, hover_pos, gate1, gate2, gate3, flare, pad])
		draw_polyline(route, Color(0.35, 0.85, 0.4, 0.35), 2.0)

		draw_circle(hover_pos, 4.0, cyan)
		_draw_map_text(font, hover_pos + Vector2(6, 3), "1.ВИСІННЯ", 9, cyan)

		draw_circle(gate1, 4.0, amber)
		_draw_map_text(font, gate1 + Vector2(6, 3), "2.ВОР-1", 9, amber)

		draw_circle(gate2, 4.0, amber)
		draw_circle(gate3, 4.0, amber)
		_draw_map_text(font, gate3 + Vector2(6, 3), "3.ВІРАЖ", 9, amber)

		draw_circle(flare, 5.0, Color(0.95, 0.5, 0.2))
		_draw_map_text(font, flare + Vector2(6, 3), "4.FLARE", 9, Color(0.95, 0.5, 0.2))

		draw_rect(Rect2(pad - Vector2(5, 5), Vector2(10, 10)), green, false, 1.5)
		_draw_map_text(font, pad + Vector2(7, 3), "5.ПОСАДКА [H]", 9, green)

		_draw_map_text(font, Vector2(center.x - 40, sz.y - 6), "ШКОЛА FPV · 10 НАВЧАЛЬНИХ МОДУЛІВ", 11, green, HORIZONTAL_ALIGNMENT_CENTER)


# ==============================================================================
# MAIN MENU INITIALIZATION & LAYOUT
# ==============================================================================
func _ready() -> void:
	# LOWSPEC renders levels at 720p; the menu always returns to native UI.
	if get_window() != null and get_window().content_scale_mode == Window.CONTENT_SCALE_MODE_VIEWPORT:
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		get_window().content_scale_size = Vector2i(0, 0)
	theme = MenuUI.theme()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().paused = false
	# The flight-prep checkboxes must show the persisted aids, not just the
	# in-memory defaults, even before a drone scene has loaded the config.
	GameSettings.load_hud_config()
	Audio.play_menu_music()
	_selected_mode = Global.sanitize_play_mode(
			int(Global.menu_settings.get("selected_mode", Global.play_mode)))
	Global.play_mode = _selected_mode
	_selected_mission = clampi(int(Global.menu_settings.get("selected_mission", 1)), 1, 5)
	_selected_map = str(Global.menu_settings.get("selected_map", "village"))
	if not SELECTABLE_MAPS.has(_selected_map):
		_selected_map = "village"
	_selected_special = int(Global.menu_settings.get("selected_special", 0))
	if _selected_special < 1 or _selected_special > SPECIAL_MISSIONS.size():
		_selected_special = 0
	if _selected_mode != Global.PlayMode.COMBAT:
		_selected_special = 0
	if OS.has_environment("DRONE_COMBAT_MISSION"):
		_selected_mode = Global.PlayMode.COMBAT
		_selected_mission = int(OS.get_environment("DRONE_COMBAT_MISSION"))
		_selected_special = 0
	elif OS.has_environment("DRONE_TUTORIAL") or (OS.has_environment("DRONE_PLAY_MODE") and OS.get_environment("DRONE_PLAY_MODE").to_lower() == "tutorial"):
		_selected_mode = Global.PlayMode.TUTORIAL
		_selected_special = 0
	elif OS.has_environment("DRONE_PLAY_MODE") and OS.get_environment("DRONE_PLAY_MODE").to_lower() == "training":
		_selected_mode = Global.PlayMode.TRAINING
		_selected_special = 0
	elif OS.has_environment("DRONE_PLAY_MODE") and OS.get_environment("DRONE_PLAY_MODE").to_lower() == "combat":
		_selected_mode = Global.PlayMode.COMBAT
	Global.special_mission = _selected_special
	if _selected_mode == Global.PlayMode.COMBAT and not OS.has_environment("DRONE_COMBAT_MISSION"):
		_selected_mission = mini(_selected_mission, Global.campaign_unlocked_mission())
	_selected_mission = clampi(_selected_mission, 1, 4)
	_build()
	_update_selection_ui()
	MenuUI.localize_tree(self)
	if OS.has_environment("DRONE_LOADING_TEST"):
		call_deferred("_qa_loading_test")
	if OS.has_environment("DRONE_MENU_CYCLE_TEST"):
		call_deferred("_qa_cycle_to_preset")


func _qa_loading_test() -> void:
	await get_tree().create_timer(1.0).timeout
	_begin_loading("res://sceneries/VillageLevel.tscn")


func _qa_cycle_to_preset() -> void:
	await get_tree().process_frame
	var guard := 0
	var target_idx := mini(1, maxi(DroneCatalog.count() - 1, 0))
	while Global.drone_preset != target_idx and guard < DroneCatalog.count():
		_cycle_drone(1)
		guard += 1
	var ok := Global.drone_preset == target_idx \
			and DroneCatalog.is_combat(Global.drone_preset)
	print("[MENU-TEST] selected=", Global.drone_preset,
			" mode=", _selected_mode, " result=", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)


func _build() -> void:
	add_child(MenuUI.background(MenuUI.FPV_BG))

	var root_margin := MarginContainer.new()
	MenuUI.full_rect(root_margin)
	root_margin.add_theme_constant_override("margin_left", minf(20.0, get_viewport_rect().size.x * 0.02))
	root_margin.add_theme_constant_override("margin_right", minf(20.0, get_viewport_rect().size.x * 0.02))
	root_margin.add_theme_constant_override("margin_top", 10)
	root_margin.add_theme_constant_override("margin_bottom", minf(36.0, get_viewport_rect().size.y * 0.05))
	add_child(root_margin)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	root_margin.add_child(main_vbox)

	# 1. Clean Top Navigation & Status Bar
	main_vbox.add_child(_build_top_telemetry_bar())

	# 2. Main Split: Left = Modes, Missions, Recon Plan & Launch; Right = Active Drone Intel & 3D Stage
	var center_split := HBoxContainer.new()
	center_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center_split.add_theme_constant_override("separation", 12)
	main_vbox.add_child(center_split)

	# --- LEFT COLUMN (FLIGHT MODES, MISSIONS, RECON PLAN & LAUNCH) ---
	var left_panel := PanelContainer.new()
	left_panel.custom_minimum_size = Vector2(minf(470.0, get_viewport_rect().size.x * 0.38), 0)
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel.add_theme_stylebox_override("panel", MenuUI.feel_style(MenuUI.FPV_PANEL, MenuUI.FPV_BORDER, 1, 8, 12, 10))
	center_split.add_child(left_panel)

	var left_wrapper := VBoxContainer.new()
	left_wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_wrapper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_wrapper.add_theme_constant_override("separation", 8)
	left_panel.add_child(left_wrapper)
	var left_scroll := ScrollContainer.new()
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_wrapper.add_child(left_scroll)
	var left_box := VBoxContainer.new()
	left_box.add_theme_constant_override("separation", 6)
	left_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.add_child(left_box)

	# Flight modes (Feel FPV Segmented Pill Bar)
	left_box.add_child(MenuUI.feel_section("Режими польоту"))
	var mode_grid := HBoxContainer.new()
	mode_grid.add_theme_constant_override("separation", 4)
	left_box.add_child(mode_grid)

	var tut_star: String = " ★" if Global.is_tutorial_completed() else ""
	var tut_btn := _build_mode_btn("🎓 Туторіал" + tut_star, "🎓 Tutorial" + tut_star, "10 модулів", "10 modules", Global.PlayMode.TUTORIAL)
	var train_btn := _build_mode_btn("🌲 Тренування", "🌲 Training", "Полігон + траса", "Range + course", Global.PlayMode.TRAINING)
	var combat_mode_btn := _build_mode_btn("⚔️ Бойовий", "⚔️ Combat", "4 місії + 9 СО", "4 missions + 9 ops", Global.PlayMode.COMBAT)
	mode_grid.add_child(tut_btn)
	mode_grid.add_child(train_btn)
	mode_grid.add_child(combat_mode_btn)
	_mode_buttons[Global.PlayMode.TUTORIAL] = tut_btn
	_mode_buttons[Global.PlayMode.TRAINING] = train_btn
	_mode_buttons[Global.PlayMode.COMBAT] = combat_mode_btn
	_ribbon_buttons[Global.PlayMode.TUTORIAL] = tut_btn
	_ribbon_buttons[Global.PlayMode.TRAINING] = train_btn
	_ribbon_buttons[Global.PlayMode.COMBAT] = combat_mode_btn

	# Frontline map selector.  The four procedural Ukrainian maps live in
	# sceneries/*Level.tscn; "valley" keeps the original map.
	left_box.add_child(MenuUI.feel_section("Карта / Frontline"))
	var map_row := HBoxContainer.new()
	map_row.add_theme_constant_override("separation", 4)
	left_box.add_child(map_row)
	var map_defs := [
		{"id": "steppe", "uk": "Посадки", "en": "Steppe"},
		{"id": "village", "uk": "Село", "en": "Village"},
		{"id": "industrial", "uk": "Промзона", "en": "Industry"},
		{"id": "wetlands", "uk": "Плавні", "en": "Wetlands"},
	]
	_map_buttons.clear()
	for md in map_defs:
		var map_btn := MenuUI.feel_button(
				str(md["en"]) if MenuUI.is_english() else str(md["uk"]), 30, false)
		map_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		map_btn.add_theme_font_size_override("font_size", 10)
		map_btn.toggle_mode = true
		map_btn.button_pressed = (str(md["id"]) == _selected_map)
		map_btn.pressed.connect(_select_map.bind(str(md["id"])))
		map_row.add_child(map_btn)
		_map_buttons[str(md["id"])] = map_btn

	# Combat missions
	left_box.add_child(MenuUI.feel_section("Бойові завдання"))
	var m_defs := [
		{"id": 1, "code": "TAC-01", "name": "1. Піхота в окопах", "desc": "Виявлення та ліквідація живої сили", "diff": "Легка", "col": MenuUI.FPV_GREEN},
		{"id": 2, "code": "TAC-02", "name": "2. Колона бронетехніки", "desc": "Ураження танка Т-72Б та БТР-82А", "diff": "Середня", "col": MenuUI.FPV_AMBER},
		{"id": 3, "code": "TAC-03", "name": "3. Гелікоптер у русі", "desc": "Перехоплення низьковисотної авіації", "diff": "Важка", "col": MenuUI.FPV_AMBER},
		{"id": 4, "code": "TAC-04", "name": "4. БПЛА «Дельта-136»", "desc": "Швидкісне перехоплення БПЛА", "diff": "Екстрим", "col": MenuUI.FPV_RED},
	]
	for md in m_defs:
		var m_btn := _build_mission_btn(md)
		left_box.add_child(m_btn)
		_mission_buttons[int(md["id"])] = m_btn

	# Standalone special operations.  They reuse the combat sandbox but have
	# their own objectives and do not touch campaign stars/records.
	left_box.add_child(MenuUI.feel_section("Спецоперації"))
	var special_hint := MenuUI.body(
			"Окремі вильоти поза кампанією: розвідка, супровід, евакуація, доставка, нічний удар, прорив РЕБ, тилова колона, «Орешник» і глибокий тил.",
			11, MenuUI.FPV_MUTED)
	special_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_box.add_child(special_hint)
	for md in SPECIAL_MISSIONS:
		var s_btn := _build_special_mission_btn(md)
		left_box.add_child(s_btn)
		_special_mission_btns[int(md["id"])] = s_btn

	# Recon Map Card & Launch Button
	left_box.add_child(MenuUI.feel_section("План вильоту"))
	left_box.add_child(_build_recon_card())
	if _quick_diff_container != null:
		var diff_parent := _quick_diff_container.get_parent()
		if diff_parent != null:
			diff_parent.remove_child(_quick_diff_container)
		left_wrapper.add_child(_quick_diff_container)
	if _realism_container != null:
		var realism_parent := _realism_container.get_parent()
		if realism_parent != null:
			realism_parent.remove_child(_realism_container)
		left_wrapper.add_child(_realism_container)
	if _launch_btn != null:
		var action_parent := _launch_btn.get_parent()
		if action_parent != null:
			action_parent.remove_child(_launch_btn)
		_launch_btn.custom_minimum_size = Vector2(0, 48)
		_launch_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left_wrapper.add_child(_launch_btn)

	# --- RIGHT COLUMN (ACTIVE DRONE INTEL, MASSIVE INTERACTIVE 3D MODEL) ---
	var right_panel := PanelContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.add_theme_stylebox_override("panel", MenuUI.feel_style(MenuUI.FPV_PANEL, MenuUI.FPV_BORDER, 1, 8, 12, 10))
	center_split.add_child(right_panel)

	var right_box := VBoxContainer.new()
	right_box.add_theme_constant_override("separation", 6)
	right_panel.add_child(right_box)

	right_box.add_child(MenuUI.feel_section("Активний дрон"))
	right_box.add_child(_build_drone_intel_card())

	# Full-height cinematic 3D Drone Viewport
	right_box.add_child(_build_3d_drone_card())

	# 3. Bottom Action Bar (Sleek Minimal Footer)
	var bottom_bar := HBoxContainer.new()
	bottom_bar.add_theme_constant_override("separation", 14)
	main_vbox.add_child(bottom_bar)

	var back_btn := MenuUI.feel_button("←  Головне меню", 34, false)
	back_btn.custom_minimum_size.x = 180
	back_btn.pressed.connect(_go.bind(START_SCREEN))
	bottom_bar.add_child(back_btn)

	var foot_spacer := Control.new()
	foot_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_bar.add_child(foot_spacer)

	_foot_status_lbl = Label.new()
	_foot_status_lbl.text = _ui_text(
			"НЕБЕСНИЙ ГОРИЗОНТ · ТАКТИЧНИЙ FPV-СИМУЛЯТОР · v1.19.0",
			"NEBESNYI HORIZONT · TACTICAL FPV SIMULATOR · v1.19.0")
	_foot_status_lbl.add_theme_font_size_override("font_size", 11)
	_foot_status_lbl.add_theme_color_override("font_color", MenuUI.FPV_MUTED)
	bottom_bar.add_child(_foot_status_lbl)

	var foot_spacer2 := Control.new()
	foot_spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_bar.add_child(foot_spacer2)

	var help_btn := MenuUI.feel_button("📖 Довідка", 34, false)
	help_btn.custom_minimum_size.x = 140
	help_btn.pressed.connect(_go.bind(HELP_SCREEN))
	bottom_bar.add_child(help_btn)

	var quit_btn := MenuUI.feel_button("✕  Вихід", 34, false)
	quit_btn.custom_minimum_size.x = 120
	quit_btn.pressed.connect(_on_quit_pressed)
	bottom_bar.add_child(quit_btn)

	# 4. Tactical Campaign Briefing Modal Overlay
	_build_briefing_modal()


# ===============================================================================
# LEFT PANEL: RECON INTEL CARD & COMMAND LAUNCH BUTTON
# ==============================================================================
func _build_recon_card() -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", MenuUI.feel_style(MenuUI.FPV_BG_CARD, MenuUI.FPV_BORDER, 1, 8, 10, 8))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)

	# Vector procedural map widget
	_map_canvas = _TacticalMapCanvas.new()
	_map_canvas.custom_minimum_size = Vector2(0, 95)
	vbox.add_child(_map_canvas)

	# Mission Briefing labels
	_map_title_lbl = Label.new()
	_map_title_lbl.add_theme_font_size_override("font_size", 13)
	_map_title_lbl.add_theme_color_override("font_color", MenuUI.FPV_CYAN)
	vbox.add_child(_map_title_lbl)

	_map_obj_lbl = Label.new()
	_map_obj_lbl.add_theme_font_size_override("font_size", 11)
	_map_obj_lbl.add_theme_color_override("font_color", MenuUI.FPV_TEXT)
	_map_obj_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_map_obj_lbl)

	_map_stats_lbl = Label.new()
	_map_stats_lbl.add_theme_font_size_override("font_size", 11)
	_map_stats_lbl.add_theme_color_override("font_color", MenuUI.FPV_MUTED)
	vbox.add_child(_map_stats_lbl)

	_campaign_progress_lbl = Label.new()
	_campaign_progress_lbl.add_theme_font_size_override("font_size", 11)
	_campaign_progress_lbl.add_theme_color_override("font_color", MenuUI.FPV_CYAN)
	_campaign_progress_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_campaign_progress_lbl)

	_daily_lbl = Label.new()
	_daily_lbl.add_theme_font_size_override("font_size", 10)
	_daily_lbl.add_theme_color_override("font_color", MenuUI.FPV_AMBER)
	_daily_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_daily_lbl)

	if not Global.is_tutorial_completed():
		_quick_tut_btn = MenuUI.feel_button(_ui_text(
				"🎓 ШВИДКИЙ СТАРТ: ПЕРШИЙ ПОЛІТ (ANGLE)",
				"🎓 QUICK START: FIRST FLIGHT (ANGLE)"), 32, false)
		_quick_tut_btn.add_theme_font_size_override("font_size", 11)
		_quick_tut_btn.add_theme_color_override("font_color", MenuUI.FPV_CYAN)
		_quick_tut_btn.pressed.connect(func():
			_select_mode(Global.PlayMode.TUTORIAL)
			_launch_current_selection()
		)
		vbox.add_child(_quick_tut_btn)

	# Explicit first-strike training: one tank, three steps, no campaign record.
	var ct_done := Global.is_combat_training_completed()
	_quick_ct_btn = MenuUI.feel_button(_ui_text(
			"🎯 БОЙОВЕ ТРЕНУВАННЯ: 3 КРОКИ" if not ct_done \
					else "✓ БОЙОВЕ ТРЕНУВАННЯ ПРОЙДЕНО · ПОВТОРИТИ",
			"🎯 COMBAT TRAINING: 3 STEPS" if not ct_done \
					else "✓ COMBAT TRAINING DONE · REPEAT"), 34, false)
	_quick_ct_btn.add_theme_font_size_override("font_size", 11)
	_quick_ct_btn.add_theme_color_override("font_color", MenuUI.FPV_AMBER)
	_quick_ct_btn.pressed.connect(func(): _launch_current_selection(true))
	vbox.add_child(_quick_ct_btn)

	# Quick Difficulty Selector Row
	var diff_box := VBoxContainer.new()
	_quick_diff_container = diff_box
	diff_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	diff_box.add_theme_constant_override("separation", 2)
	vbox.add_child(diff_box)

	var diff_title_row := HBoxContainer.new()
	diff_title_row.add_theme_constant_override("separation", 6)
	var diff_badge := Label.new()
	diff_badge.text = "Складність:"
	diff_badge.add_theme_font_size_override("font_size", 11)
	diff_badge.add_theme_color_override("font_color", MenuUI.FPV_MUTED)
	diff_title_row.add_child(diff_badge)
	diff_box.add_child(diff_title_row)

	var diff_btns_row := HBoxContainer.new()
	diff_btns_row.add_theme_constant_override("separation", 4)
	diff_btns_row.add_child(_build_quick_diff_btn("РЕКРУТ", Global.Difficulty.RECRUIT))
	diff_btns_row.add_child(_build_quick_diff_btn("ОПЕРАТОР", Global.Difficulty.OPERATOR))
	diff_btns_row.add_child(_build_quick_diff_btn("АС", Global.Difficulty.ACE))
	diff_box.add_child(diff_btns_row)

	_quick_diff_lbl = Label.new()
	_quick_diff_lbl.add_theme_font_size_override("font_size", 10)
	_quick_diff_lbl.add_theme_color_override("font_color", MenuUI.FPV_MUTED)
	_quick_diff_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	diff_box.add_child(_quick_diff_lbl)

	# Realism profile: one tap switches the whole field model for the sortie.
	# Kept outside the combat-only difficulty block so it is available in the
	# academy and free-flight screens too.
	_realism_container = VBoxContainer.new()
	_realism_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_realism_container.add_theme_constant_override("separation", 0)
	var realism_title_row := HBoxContainer.new()
	realism_title_row.add_theme_constant_override("separation", 6)
	var realism_badge := Label.new()
	realism_badge.text = "Реалізм:"
	realism_badge.add_theme_font_size_override("font_size", 11)
	realism_badge.add_theme_color_override("font_color", MenuUI.FPV_MUTED)
	realism_title_row.add_child(realism_badge)
	var realism_profile_row := HBoxContainer.new()
	realism_profile_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	realism_profile_row.add_theme_constant_override("separation", 4)
	realism_profile_row.add_child(_build_realism_profile_btn(
			"АРКАДА", GameSettings.REALISM_ARCADE))
	realism_profile_row.add_child(_build_realism_profile_btn(
			"БОЙОВИЙ", GameSettings.REALISM_COMBAT))
	realism_title_row.add_child(realism_profile_row)
	_realism_container.add_child(realism_title_row)

	var realism_checks := VBoxContainer.new()
	realism_checks.add_theme_constant_override("separation", 0)
	for entry in [
			["wind_sim", "Вплив вітру",
					"Поривчастий вітер, турбулентність і знос дрона."],
			["reb_zones", "Зони РЕБ",
					"Глушіння відео та керування поблизу ворожих антен."],
			["link_battery", "Обмеження зв’язку та батареї",
					"Дальність/рельєф впливають на LQ, батарея просідає під газом."]]:
		realism_checks.add_child(_build_realism_check(
				str(entry[1]), str(entry[0]), str(entry[2])))
	_realism_container.add_child(realism_checks)

	_realism_hint = Label.new()
	_realism_hint.add_theme_font_size_override("font_size", 9)
	_realism_hint.add_theme_color_override("font_color", MenuUI.FPV_MUTED)
	_realism_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_realism_container.add_child(_realism_hint)

	# Action Bar: [ 📋 Брифінг ] and [ ▶  ПОЧАТИ ВИЛІТ ]
	var act_row := HBoxContainer.new()
	act_row.add_theme_constant_override("separation", 8)
	vbox.add_child(act_row)

	var campaign_row := HBoxContainer.new()
	campaign_row.add_theme_constant_override("separation", 6)
	vbox.add_child(campaign_row)
	_continue_campaign_btn = MenuUI.feel_button("▶  ПРОДОВЖИТИ КАМПАНІЮ", 30, false)
	_continue_campaign_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_continue_campaign_btn.add_theme_font_size_override("font_size", 11)
	_continue_campaign_btn.pressed.connect(_continue_campaign)
	campaign_row.add_child(_continue_campaign_btn)

	_briefing_btn = Button.new()
	_briefing_btn.text = "📋  Брифінг"
	_briefing_btn.custom_minimum_size = Vector2(115, 42)
	_briefing_btn.focus_mode = Control.FOCUS_ALL
	_briefing_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_briefing_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_briefing_btn.add_theme_font_size_override("font_size", 13)
	_briefing_btn.add_theme_color_override("font_color", MenuUI.BUTTON_TEXT)
	_briefing_btn.add_theme_stylebox_override("normal", MenuUI.feel_style(MenuUI.BUTTON_BG, MenuUI.FPV_BORDER, 1, 1, 10, 4))
	_briefing_btn.add_theme_stylebox_override("hover", MenuUI.feel_style(MenuUI.BUTTON_HOVER, MenuUI.FPV_GREEN, 1, 1, 10, 4))
	_briefing_btn.add_theme_stylebox_override("pressed", MenuUI.feel_style(MenuUI.BUTTON_ACTIVE, MenuUI.FPV_GREEN, 1, 1, 10, 4))
	_briefing_btn.add_theme_stylebox_override("focus", MenuUI.feel_style(MenuUI.BUTTON_HOVER, MenuUI.FPV_GREEN, 1, 1, 10, 4))
	_briefing_btn.pressed.connect(func(): _open_briefing_dialog(_selected_mission))
	if not _briefing_btn.mouse_entered.is_connected(_briefing_btn.grab_focus):
		_briefing_btn.mouse_entered.connect(_briefing_btn.grab_focus)
	act_row.add_child(_briefing_btn)

	# Primary launch action, moved into the fixed footer below the scrollable list.
	_launch_btn = Button.new()
	_launch_btn.custom_minimum_size = Vector2(0, 42)
	_launch_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_launch_btn.focus_mode = Control.FOCUS_ALL
	_launch_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_launch_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_launch_btn.add_theme_stylebox_override("normal", MenuUI.feel_style(MenuUI.BUTTON_ACTIVE, MenuUI.FPV_GREEN, 2, 1, 14, 6))
	_launch_btn.add_theme_stylebox_override("hover", MenuUI.feel_style(MenuUI.BUTTON_ACTIVE.lightened(0.08), MenuUI.FPV_GREEN, 2, 1, 14, 6))
	_launch_btn.add_theme_stylebox_override("pressed", MenuUI.feel_style(MenuUI.BUTTON_ACTIVE.darkened(0.08), MenuUI.FPV_GREEN, 2, 1, 14, 6))
	_launch_btn.add_theme_stylebox_override("focus", MenuUI.feel_style(MenuUI.BUTTON_ACTIVE.lightened(0.08), MenuUI.FPV_GREEN, 2, 1, 14, 6))
	_launch_btn.add_theme_font_size_override("font_size", 14)
	_launch_btn.add_theme_color_override("font_color", Color.WHITE)
	_launch_btn.add_theme_color_override("font_hover_color", Color.WHITE)
	_launch_btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	_launch_btn.pressed.connect(_launch_current_selection)
	if not _launch_btn.mouse_entered.is_connected(_launch_btn.grab_focus):
		_launch_btn.mouse_entered.connect(_launch_btn.grab_focus)
	_launch_btn.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
			accept_event()
			_launch_current_selection()
	)
	act_row.add_child(_launch_btn)

	return card

func _build_mode_btn(uk_title: String, en_title: String, uk_desc: String, en_desc: String, mode: int) -> Button:
	_mode_copy[mode] = {"uk_title": uk_title, "en_title": en_title,
		"uk_desc": uk_desc, "en_desc": en_desc}
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 36)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.focus_mode = Control.FOCUS_ALL
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_stylebox_override("normal", MenuUI.feel_style(MenuUI.BUTTON_BG, MenuUI.FPV_BORDER, 1, 1, 6, 2))
	btn.add_theme_stylebox_override("hover", MenuUI.feel_style(MenuUI.BUTTON_HOVER, MenuUI.FPV_GREEN, 2, 1, 6, 2))
	btn.add_theme_stylebox_override("pressed", MenuUI.feel_style(MenuUI.BUTTON_ACTIVE, MenuUI.FPV_GREEN, 2, 1, 6, 2))
	btn.add_theme_stylebox_override("focus", MenuUI.feel_style(MenuUI.BUTTON_HOVER, MenuUI.FPV_GREEN, 2, 1, 6, 2))

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 0)
	btn.add_child(vbox)
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 2)

	var lbl1 := Label.new()
	lbl1.name = "Title"
	lbl1.text = en_title if MenuUI.is_english() else uk_title
	lbl1.add_theme_font_size_override("font_size", 12)
	lbl1.add_theme_color_override("font_color", MenuUI.BUTTON_TEXT)
	lbl1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lbl1)

	var lbl2 := Label.new()
	lbl2.name = "Sub"
	lbl2.text = en_desc if MenuUI.is_english() else uk_desc
	lbl2.add_theme_font_size_override("font_size", 10)
	lbl2.add_theme_color_override("font_color", Color("59645c"))
	lbl2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lbl2)

	btn.pressed.connect(_select_mode.bind(mode))
	if not btn.mouse_entered.is_connected(btn.grab_focus):
		btn.mouse_entered.connect(btn.grab_focus)
	return btn


func _build_mission_btn(md: Dictionary, special := false) -> Button:
	var is_en := MenuUI.is_english()
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 44)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.focus_mode = Control.FOCUS_ALL
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var accent_col: Color = md["col"] as Color
	var normal_sb := MenuUI.feel_style(MenuUI.BUTTON_BG, MenuUI.FPV_BORDER, 1, 1, 8, 4)
	normal_sb.border_width_left = 3
	normal_sb.border_color = accent_col
	btn.add_theme_stylebox_override("normal", normal_sb)

	var hover_sb := MenuUI.feel_style(MenuUI.BUTTON_HOVER, MenuUI.FPV_GREEN, 2, 1, 8, 4)
	hover_sb.border_width_left = 3
	btn.add_theme_stylebox_override("hover", hover_sb)
	btn.add_theme_stylebox_override("focus", hover_sb)

	var hbox := HBoxContainer.new()
	hbox.name = "HBox"
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 8)
	btn.add_child(hbox)
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)

	var code_lbl := Label.new()
	code_lbl.text = "[ %s ]" % str(md["code"])
	code_lbl.add_theme_font_size_override("font_size", 12)
	code_lbl.add_theme_color_override("font_color", MenuUI.BUTTON_TEXT)
	hbox.add_child(code_lbl)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 1)
	hbox.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.name = "Title"
	var name_ua := str(md["name"])
	title_lbl.text = str(md.get("name_en", MenuUI.translate_text(name_ua))) if is_en else name_ua
	title_lbl.add_theme_font_size_override("font_size", 13)
	title_lbl.add_theme_color_override("font_color", MenuUI.BUTTON_TEXT)
	vbox.add_child(title_lbl)

	var desc_lbl := Label.new()
	desc_lbl.name = "Description"
	var desc_ua := str(md["desc"])
	desc_lbl.text = str(md.get("desc_en", MenuUI.translate_text(desc_ua))) if is_en else desc_ua
	desc_lbl.add_theme_font_size_override("font_size", 10)
	desc_lbl.add_theme_color_override("font_color", Color("59645c"))
	vbox.add_child(desc_lbl)

	var diff_badge := PanelContainer.new()
	diff_badge.name = "DifficultyBadge"
	var d_sb := StyleBoxFlat.new()
	d_sb.bg_color = Color(accent_col.r, accent_col.g, accent_col.b, 0.15)
	d_sb.border_color = accent_col
	d_sb.set_border_width_all(1)
	d_sb.set_corner_radius_all(4)
	d_sb.content_margin_left = 6
	d_sb.content_margin_right = 6
	d_sb.content_margin_top = 2
	d_sb.content_margin_bottom = 2
	diff_badge.add_theme_stylebox_override("panel", d_sb)

	var diff_lbl := Label.new()
	diff_lbl.name = "Difficulty"
	var diff_ua := str(md["diff"])
	diff_lbl.text = str(md.get("diff_en", MenuUI.translate_text(diff_ua))) if is_en else diff_ua
	diff_lbl.add_theme_font_size_override("font_size", 10)
	diff_lbl.add_theme_color_override("font_color", MenuUI.BUTTON_TEXT)
	diff_badge.add_child(diff_lbl)
	hbox.add_child(diff_badge)

	var m_id := int(md["id"])
	if special:
		btn.pressed.connect(_select_special_mission.bind(m_id))
	else:
		_mission_code_labels[m_id] = code_lbl
		btn.pressed.connect(_select_mission.bind(m_id))
	if not btn.mouse_entered.is_connected(btn.grab_focus):
		btn.mouse_entered.connect(btn.grab_focus)
	return btn


func _build_special_mission_btn(md: Dictionary) -> Button:
	return _build_mission_btn(md, true)


func _special_mission_def(mission_id: int) -> Dictionary:
	for md in SPECIAL_MISSIONS:
		if int(md["id"]) == mission_id:
			return md
	return {}


func _select_mode(mode: int) -> void:
	mode = Global.sanitize_play_mode(mode)
	_selected_mode = mode
	Global.play_mode = mode
	_selected_special = 0
	Global.special_mission = 0
	Global.menu_settings["selected_special"] = 0
	if mode == Global.PlayMode.COMBAT:
		_selected_mission = mini(_selected_mission, Global.campaign_unlocked_mission())
	Global.menu_settings["selected_mode"] = mode
	Global.save_menu_settings()
	_update_selection_ui()


func _select_mission(m_id: int) -> void:
	m_id = clampi(m_id, 1, 4)
	if not Global.is_mission_unlocked(m_id):
		_update_selection_ui()
		return
	_selected_mode = Global.PlayMode.COMBAT
	Global.play_mode = Global.PlayMode.COMBAT
	_selected_special = 0
	Global.special_mission = 0
	_selected_mission = m_id
	Global.menu_settings["selected_mode"] = Global.PlayMode.COMBAT
	Global.menu_settings["selected_mission"] = m_id
	Global.menu_settings["selected_special"] = 0
	Global.save_menu_settings()
	_update_selection_ui()


func _select_special_mission(mission_id: int) -> void:
	if mission_id < 1 or mission_id > SPECIAL_MISSIONS.size():
		return
	_selected_mode = Global.PlayMode.COMBAT
	Global.play_mode = Global.PlayMode.COMBAT
	_selected_special = mission_id
	Global.special_mission = mission_id
	Global.menu_settings["selected_mode"] = Global.PlayMode.COMBAT
	Global.menu_settings["selected_special"] = mission_id
	Global.save_menu_settings()
	if not DroneCatalog.is_combat(Global.drone_preset):
		QuadSettings.custom_rates = false
		DroneCatalog.apply(DroneCatalog.first_combat_index())
		_load_drone_model()
	_update_selection_ui()


func _continue_campaign() -> void:
	# Continue at the first incomplete mission.  The briefing opens first, so
	# the player still chooses difficulty and sees the objectives.
	_selected_mode = Global.PlayMode.COMBAT
	Global.play_mode = Global.PlayMode.COMBAT
	_selected_special = 0
	Global.special_mission = 0
	_selected_mission = 1 if Global.campaign_is_complete() else Global.campaign_unlocked_mission()
	Global.menu_settings["selected_mode"] = Global.PlayMode.COMBAT
	Global.menu_settings["selected_mission"] = _selected_mission
	Global.menu_settings["selected_special"] = 0
	Global.save_menu_settings()
	_update_selection_ui()
	_open_briefing_dialog(_selected_mission)


## Frontline map picker.  Only affects which scene is loaded at launch; the
## valley map is forced back for the TAC-05 naval mission.
func _select_map(map_id: String) -> void:
	if not SELECTABLE_MAPS.has(map_id):
		return
	_selected_map = map_id
	Global.menu_settings["selected_map"] = map_id
	Global.save_menu_settings()
	for key in _map_buttons.keys():
		var b: Button = _map_buttons[key]
		if b != null and is_instance_valid(b):
			b.button_pressed = (str(key) == _selected_map)
	_update_selection_ui()


func _update_selection_ui() -> void:
	if _map_title_lbl == null:
		return
	# Update mode buttons style
	for m in _mode_buttons.keys():
		var b: Button = _mode_buttons[m]
		var is_active: bool = (_selected_mode == int(m))
		if is_active:
			b.add_theme_stylebox_override("normal", MenuUI.feel_style(MenuUI.BUTTON_ACTIVE, MenuUI.FPV_GREEN, 2, 1, 6, 2))
		else:
			b.add_theme_stylebox_override("normal", MenuUI.feel_style(MenuUI.BUTTON_BG, MenuUI.FPV_BORDER, 1, 1, 6, 2))
		var mode_hover := MenuUI.BUTTON_ACTIVE.lightened(0.08) if is_active else MenuUI.BUTTON_HOVER
		b.add_theme_stylebox_override("hover", MenuUI.feel_style(mode_hover, MenuUI.FPV_GREEN, 2, 1, 6, 2))
		b.add_theme_stylebox_override("focus", MenuUI.feel_style(mode_hover, MenuUI.FPV_GREEN, 2, 1, 6, 2))
		var title_node = b.get_node_or_null("VBox/Title") as Label
		if title_node != null:
			title_node.add_theme_color_override("font_color", MenuUI.BUTTON_ACTIVE_TEXT if is_active else MenuUI.BUTTON_TEXT)
		var subtitle_node = b.get_node_or_null("VBox/Sub") as Label
		if subtitle_node != null:
			subtitle_node.add_theme_color_override("font_color", Color("e1ebe4") if is_active else Color("59645c"))

	# Update mission buttons style
	for mid in _mission_buttons.keys():
		var b: Button = _mission_buttons[mid]
		var unlocked := Global.is_mission_unlocked(int(mid))
		var is_active: bool = (_selected_mode == Global.PlayMode.COMBAT \
				and _selected_special == 0 and _selected_mission == int(mid))
		b.disabled = not unlocked
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if unlocked else Control.CURSOR_ARROW
		b.tooltip_text = "" if unlocked else (
			"Complete the previous mission to unlock this sortie." if LocScript.get_language() == LocScript.Language.EN
			else "Завершіть попередню місію, щоб відкрити цей виліт.")
		if not unlocked:
			var dis_sb := MenuUI.feel_style(MenuUI.BUTTON_BG.darkened(0.18), Color(0.18, 0.22, 0.20), 1, 1, 8, 4)
			dis_sb.border_width_left = 3
			b.add_theme_stylebox_override("disabled", dis_sb)
			b.add_theme_stylebox_override("normal", dis_sb)
		elif is_active:
			var act_sb := MenuUI.feel_style(MenuUI.BUTTON_ACTIVE, MenuUI.FPV_GREEN, 2, 1, 8, 4)
			act_sb.border_width_left = 4
			b.add_theme_stylebox_override("normal", act_sb)
		else:
			var norm_sb := MenuUI.feel_style(MenuUI.BUTTON_BG, MenuUI.FPV_BORDER, 1, 1, 8, 4)
			norm_sb.border_width_left = 3
			b.add_theme_stylebox_override("normal", norm_sb)
		var mission_hover := MenuUI.BUTTON_ACTIVE.lightened(0.08) if is_active else MenuUI.BUTTON_HOVER
		var mission_hover_sb := MenuUI.feel_style(mission_hover, MenuUI.FPV_GREEN, 2, 1, 8, 4)
		mission_hover_sb.border_width_left = 4 if is_active else 3
		b.add_theme_stylebox_override("hover", mission_hover_sb)
		b.add_theme_stylebox_override("focus", mission_hover_sb)
		var title_node := b.get_node_or_null("HBox/VBox/Title") as Label
		var desc_node := b.get_node_or_null("HBox/VBox/Description") as Label
		if title_node != null:
			title_node.add_theme_color_override("font_color",
					MenuUI.BUTTON_ACTIVE_TEXT if is_active and unlocked
					else (Color("59645c") if not unlocked else MenuUI.BUTTON_TEXT))
		if desc_node != null:
			desc_node.add_theme_color_override("font_color",
					Color("e1ebe4") if is_active and unlocked
					else (Color("3f4a43") if not unlocked else Color("59645c")))

	# Update special-operation buttons style
	for sid in _special_mission_btns.keys():
		var sb: Button = _special_mission_btns[sid]
		var s_active: bool = (_selected_mode == Global.PlayMode.COMBAT \
				and _selected_special == int(sid))
		var s_sb := MenuUI.feel_style(
				MenuUI.BUTTON_ACTIVE if s_active else MenuUI.BUTTON_BG,
				MenuUI.FPV_GREEN if s_active else MenuUI.FPV_BORDER,
				2 if s_active else 1, 1, 8, 4)
		s_sb.border_width_left = 4 if s_active else 3
		sb.add_theme_stylebox_override("normal", s_sb)
		var s_hover := MenuUI.BUTTON_ACTIVE.lightened(0.08) if s_active else MenuUI.BUTTON_HOVER
		var s_hover_sb := MenuUI.feel_style(s_hover, MenuUI.FPV_GREEN, 2, 1, 8, 4)
		s_hover_sb.border_width_left = 4 if s_active else 3
		sb.add_theme_stylebox_override("hover", s_hover_sb)
		sb.add_theme_stylebox_override("focus", s_hover_sb)
		var s_title := sb.get_node_or_null("HBox/VBox/Title") as Label
		var s_desc := sb.get_node_or_null("HBox/VBox/Description") as Label
		var s_diff := sb.get_node_or_null("HBox/DifficultyBadge/Difficulty") as Label
		var s_def := _special_mission_def(int(sid))
		if s_title != null and not s_def.is_empty():
			s_title.text = str(s_def.get("name_en" if MenuUI.is_english() else "name",
					s_def.get("name", "")))
		if s_desc != null and not s_def.is_empty():
			s_desc.text = str(s_def.get("desc_en" if MenuUI.is_english() else "desc",
					s_def.get("desc", "")))
		if s_diff != null and not s_def.is_empty():
			s_diff.text = str(s_def.get("diff_en" if MenuUI.is_english() else "diff",
					s_def.get("diff", "")))
		if s_title != null:
			s_title.add_theme_color_override("font_color",
					MenuUI.BUTTON_ACTIVE_TEXT if s_active else MenuUI.BUTTON_TEXT)
		if s_desc != null:
			s_desc.add_theme_color_override("font_color",
					Color("e1ebe4") if s_active else Color("59645c"))

	# Update ribbon buttons style
	for k in _ribbon_buttons.keys():
		var b: Button = _ribbon_buttons[k]
		var is_active: bool = false
		if k is int:
			is_active = (_selected_mode == int(k))
		if is_active:
			b.add_theme_stylebox_override("normal", MenuUI.feel_style(MenuUI.BUTTON_ACTIVE, MenuUI.FPV_GREEN, 2, 1, 8, 3))
			b.add_theme_color_override("font_color", MenuUI.BUTTON_ACTIVE_TEXT)
		else:
			b.add_theme_stylebox_override("normal", MenuUI.feel_style(MenuUI.BUTTON_BG, MenuUI.FPV_BORDER, 1, 1, 8, 3))
			b.add_theme_color_override("font_color", MenuUI.BUTTON_TEXT)

	# Update Recon Map Widget
	var map_mission := _selected_mission if _selected_special == 0 else 0
	if _map_canvas != null:
		_map_canvas.set_selection(_selected_mode, map_mission)
	if _briefing_map_canvas != null:
		_briefing_map_canvas.set_selection(_selected_mode, map_mission)

	# Update Briefing text & Launch button
	var is_en := (LocScript.get_language() == LocScript.Language.EN)
	if _selected_mode == Global.PlayMode.TUTORIAL:
		_map_title_lbl.text = "TUTORIAL · PILOT ACADEMY" if is_en else "ТУТОРІАЛ · ШКОЛА ПІЛОТА"
		var angle_note := ""
		if Global.should_use_gentle_angle_assist():
			angle_note = " · Gentle Angle assist ON" if is_en else " · М’яка стабілізація Angle УВІМК."
		_map_obj_lbl.text = ("10 modules: controls, arm/disarm, throttle, altitude hold, yaw, gates, slalom, window pass, braking and landing." if is_en else "10 модулів: стіки, увімкнення/вимкнення двигунів, газ, утримання висоти, рискання, ворота, слалом, проліт крізь вікно, гальмування та посадка.") + angle_note
		_map_stats_lbl.text = "MODULES: 10/10  •  ERROR ASSISTANT: ACTIVE  •  CERTIFICATE: AVAILABLE" if is_en else "МОДУЛІВ: 10/10  •  АСИСТЕНТ ПОМИЛОК: АКТИВНИЙ  •  СЕРТИФІКАТ: ДОСТУПНИЙ"
		_launch_btn.text = "▶  START FPV TUTORIAL" if is_en else "▶  ПОЧАТИ ТУТОРІАЛ FPV"
	elif _selected_mode == Global.PlayMode.TRAINING:
		var trec := Global.get_training_record("course")
		var rank_info := ""
		if bool(trec.get("completed", false)):
			var s_str := "★".repeat(int(trec.get("stars", 1)))
			rank_info = ("  •  COURSE BEST: %.1fs %s [%s]" if is_en else "  •  РЕКОРД ТРАСИ: %.1f с %s [%s]") % [float(trec.get("best_time", 0.0)), s_str, str(trec.get("best_rank", "B"))]
		_map_title_lbl.text = "TRAINING · PROVING GROUND & COURSE" if is_en else "ТРЕНУВАННЯ · ПОЛІГОН ТА ТРАСА"
		_map_obj_lbl.text = "Free flight training, stick calibration, checkpoint course timer and Ghost replay." if is_en else "Вільний політ, калібрування стіків, тренувальна траса на час і політ із Привидом."
		_map_stats_lbl.text = ("TIME LIMIT: UNLIMITED  •  DAMAGE: DISABLED" if is_en else "ЧАС: БЕЗЛІМІТ  •  ПОШКОДЖЕННЯ: ВИМКНЕНО") + rank_info
		_launch_btn.text = "▶  START TRAINING" if is_en else "▶  ПОЧАТИ ТРЕНУВАННЯ"
	elif _selected_special > 0:
		var sdef := _special_mission_def(_selected_special)
		var s_name := str(sdef.get("name", "СПЕЦОПЕРАЦІЯ"))
		var s_desc := str(sdef.get("desc", ""))
		var s_time := ("%d:00 MIN" if is_en else "%d:00 ХВ") % int(Global.get_difficulty_time_limit() / 60.0)
		var s_diff := MenuUI.translate_text(Global.get_difficulty_name())
		_map_title_lbl.text = ("SPECIAL OPERATION · %s" if is_en else "СПЕЦОПЕРАЦІЯ · %s") % s_name
		_map_obj_lbl.text = s_desc
		_map_stats_lbl.text = ("Time: %s  ·  %s  ·  Campaign: unaffected" if is_en else "Час: %s  ·  %s  ·  Кампанія: без змін") % [s_time, s_diff]
		_launch_btn.text = ("▶  START SPECIAL OP: %s" if is_en else "▶  ПОЧАТИ СПЕЦОПЕРАЦІЮ: %s") % s_name
	else:
		var t_limit_s := Global.get_difficulty_time_limit()
		var t_limit_str := ("%d:00 MIN" if is_en else "%d:00 ХВ") % int(t_limit_s / 60.0)
		var diff_str := MenuUI.translate_text(Global.get_difficulty_name())
		match _selected_mission:
			1:
				_map_title_lbl.text = "TAC-01: TRENCH LINE · PERSONNEL" if is_en else "TAC-01: Окопна лінія · Умовний противник"
				_map_obj_lbl.text = "Locate and neutralize 6 targets in fortified trenches." if is_en else "Виявити та знешкодити 6 умовних цілей в укриттях."
				_map_stats_lbl.text = ("Targets: 6  ·  Time: %s  ·  Diff: %s" if is_en else "Цілей: 6  ·  Час: %s  ·  Складність: %s") % [t_limit_str, diff_str]
				_launch_btn.text = "▶  START MISSION: TAC-01" if is_en else "▶  ПОЧАТИ ВИЛІТ: TAC-01"
			2:
				_map_title_lbl.text = "TAC-02: ROUTE S-40 · ARMOR" if is_en else "TAC-02: Маршрут S-40 · Бронетехніка"
				_map_obj_lbl.text = "Disable T-72B tank and BTR-82A APC on the move." if is_en else "Знешкодити танк Т-72Б та бронетранспортер БТР-82А на марші."
				_map_stats_lbl.text = ("Targets: 1 tank + 1 APC  ·  Time: %s  ·  Diff: %s" if is_en else "Цілей: 1 танк + 1 БТР  ·  Час: %s  ·  Складність: %s") % [t_limit_str, diff_str]
				_launch_btn.text = "▶  START MISSION: TAC-02" if is_en else "▶  ПОЧАТИ ВИЛІТ: TAC-02"
			3:
				_map_title_lbl.text = "TAC-03: LOW ALTITUDE · HELICOPTER" if is_en else "TAC-03: Низька висота · Гелікоптер"
				_map_obj_lbl.text = "Intercept low-flying attack helicopter target." if is_en else "Перехопити низьколетючий ударний гелікоптер."
				_map_stats_lbl.text = ("Target: Helicopter (20–30 m)  ·  Time: %s  ·  Diff: %s" if is_en else "Ціль: гелікоптер (20–30 м)  ·  Час: %s  ·  Складність: %s") % [t_limit_str, diff_str]
				_launch_btn.text = "▶  START MISSION: TAC-03" if is_en else "▶  ПОЧАТИ ВИЛІТ: TAC-03"
			4:
				_map_title_lbl.text = "TAC-04: HEADING 240° · DELTA-136" if is_en else "TAC-04: Курс 240° · Дельта-136"
				_map_obj_lbl.text = "Intercept incoming high-speed Delta-136 target UAV." if is_en else "Перехоплення швидкісного БПЛА-мішені «Дельта-136»."
				_map_stats_lbl.text = ("Target: Delta-136 (58–72 km/h)  ·  Time: %s  ·  Difficulty: %s" if is_en else "Ціль: Дельта-136 (58–72 км/год)  ·  Час: %s  ·  Складність: %s") % [t_limit_str, diff_str]
				_launch_btn.text = "▶  START MISSION: TAC-04" if is_en else "▶  ПОЧАТИ ВИЛІТ: TAC-04"
	if _launch_btn != null:
		match _selected_mode:
			Global.PlayMode.TUTORIAL:
				_launch_btn.text = "▶  START TUTORIAL" if is_en else "▶  ПОЧАТИ ТУТОРІАЛ"
			Global.PlayMode.TRAINING:
				_launch_btn.text = "▶  START TRAINING" if is_en else "▶  ПОЧАТИ ТРЕНУВАННЯ"
			_:
				if _selected_special > 0:
					_launch_btn.text = ("▶  START SPECIAL OP: %s" if is_en else "▶  ПОЧАТИ СПЕЦОПЕРАЦІЮ: %s") \
							% Global.get_special_mission_name(_selected_special)
				else:
					_launch_btn.text = "▶  START MISSION" if is_en else "▶  ПОЧАТИ МІСІЮ"

	if _launch_btn != null and _selected_mode != Global.PlayMode.TUTORIAL:
		# Make the destination map explicit: the mission buttons and the map
		# picker are separate, and the old menu gave no clue which scene loads.
		_launch_btn.text += "  ·  " + str(_selected_map).to_upper()
	if _daily_lbl != null:
		var dc := Global.get_daily_challenge()
		var dc_title := str(dc.get("title_en" if is_en else "title_ua", dc.get("title_uk", "")))
		var dc_status := ("DONE" if is_en else "ВИКОНАНО") if bool(dc.get("completed", false)) else ("+%d PTS" if is_en else "+%d ОЧК.") % int(dc.get("bonus_score", 500))
		_daily_lbl.text = ("★ DAILY: %s · %s" if is_en else "★ ВИКЛИК ДНЯ: %s · %s") % [dc_title, dc_status]
	if _quick_tut_btn != null:
		_quick_tut_btn.visible = not Global.is_tutorial_completed()
		_quick_tut_btn.text = "🎓 QUICK START: FIRST FLIGHT (ANGLE)" if is_en else "🎓 ШВИДКИЙ СТАРТ: ПЕРШИЙ ПОЛІТ (ANGLE)"
	if _gc_btn != null:
		var gc_ready := Global.is_game_center_available()
		_gc_btn.text = "🏆 GC" if is_en else "🏆 Рейтинг"
		_gc_btn.tooltip_text = Global.get_leaderboard_summary(is_en)
		_gc_btn.modulate = Color.WHITE if gc_ready else Color(0.82, 0.90, 0.85, 0.85)
	if _lang_btn != null:
		_lang_btn.text = "🌐 EN → UA" if is_en else "🌐 UA → EN"
	if _top_title_lbl != null:
		_top_title_lbl.text = "SORTIE SETUP" if is_en else "Підготовка до вильоту"
	if _foot_status_lbl != null:
		_foot_status_lbl.text = "NEBESNYI HORIZONT · TACTICAL FPV SIMULATOR · v1.19.0" if is_en else "НЕБЕСНИЙ ГОРИЗОНТ · ТАКТИЧНИЙ FPV-СИМУЛЯТОР · v1.19.0"

	if _quick_diff_container != null:
		_quick_diff_container.visible = (_selected_mode == Global.PlayMode.COMBAT)
	if _briefing_btn != null:
		_briefing_btn.visible = (_selected_mode == Global.PlayMode.COMBAT \
				and _selected_special == 0)

	# Update mission stars from campaign records
	for mid in _mission_code_labels.keys():
		var clbl: Label = _mission_code_labels[mid]
		var rec: Dictionary = Global.get_mission_record(mid)
		var active_mission: bool = (_selected_mode == Global.PlayMode.COMBAT \
				and _selected_special == 0 and _selected_mission == int(mid))
		var base_code := "TAC-0%d" % mid
		var mission_unlocked := Global.is_mission_unlocked(int(mid))
		if not mission_unlocked:
			clbl.text = ("[ %s · LOCK ]" if LocScript.get_language() == LocScript.Language.EN
					else "[ %s · ЗАКРИТО ]") % base_code
			clbl.add_theme_color_override("font_color", Color("3f4a43"))
		elif bool(rec.get("completed", false)):
			var stars := int(rec.get("stars", 1))
			var stars_str := ""
			for s in range(stars):
				stars_str += "★"
			clbl.text = "[ %s %s ]" % [base_code, stars_str]
			clbl.add_theme_color_override("font_color", MenuUI.BUTTON_ACTIVE_TEXT if active_mission else Color("355c43"))
		else:
			clbl.text = "[ %s ]" % base_code
			clbl.add_theme_color_override("font_color", MenuUI.BUTTON_ACTIVE_TEXT if active_mission else Color("59645c"))

	# Campaign progress is shown in the reconnaissance card and updated after
	# every completed sortie.
	var is_en_campaign := (LocScript.get_language() == LocScript.Language.EN)
	var completed := Global.campaign_completed_count()
	var stars_total := Global.campaign_stars_total()
	var unlocked_mission := Global.campaign_unlocked_mission()
	if _campaign_progress_lbl != null:
		if _selected_special > 0:
			_campaign_progress_lbl.text = ("SPECIAL OP · %s · CAMPAIGN UNAFFECTED" if is_en_campaign
					else "СПЕЦОПЕРАЦІЯ · %s · КАМПАНІЯ НЕ ЗМІНЮЄТЬСЯ") % Global.get_special_mission_name(_selected_special)
			_campaign_progress_lbl.add_theme_color_override("font_color", MenuUI.FPV_AMBER)
		elif Global.campaign_is_complete():
			_campaign_progress_lbl.text = ("CAMPAIGN COMPLETE · %d/4 · ★ %d/12" if is_en_campaign
					else "КАМПАНІЮ ЗАВЕРШЕНО · %d/4 · ★ %d/12") % [completed, stars_total]
			_campaign_progress_lbl.add_theme_color_override("font_color", MenuUI.ACCENT)
		else:
			_campaign_progress_lbl.text = ("CAMPAIGN %d/4 · NEXT: TAC-0%d · ★ %d/12" if is_en_campaign
					else "КАМПАНІЯ %d/4 · ДАЛІ: TAC-0%d · ★ %d/12") % [completed, unlocked_mission, stars_total]
			_campaign_progress_lbl.add_theme_color_override("font_color", MenuUI.FPV_CYAN)
	if _continue_campaign_btn != null:
		_continue_campaign_btn.visible = (_selected_mode == Global.PlayMode.COMBAT \
				and _selected_special == 0)
		if Global.campaign_is_complete():
			_continue_campaign_btn.text = "↺  ПЕРЕПРОЙТИ КАМПАНІЮ: TAC-01" if not is_en_campaign else "↺  REPLAY CAMPAIGN: TAC-01"
		else:
			_continue_campaign_btn.text = ("▶  CONTINUE CAMPAIGN: TAC-0%d" if is_en_campaign
					else "▶  ПРОДОВЖИТИ КАМПАНІЮ: TAC-0%d") % unlocked_mission

	_update_diff_buttons()
	_refresh_realism_controls()
	_update_drone_intel()
	MenuUI.localize_tree(self)


func _build_quick_diff_btn(text: String, diff: int) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 26)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.focus_mode = Control.FOCUS_ALL
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_stylebox_override("normal", MenuUI.feel_style(MenuUI.BUTTON_BG, MenuUI.FPV_BORDER, 1, 1, 6, 2))
	btn.add_theme_stylebox_override("hover", MenuUI.feel_style(MenuUI.BUTTON_HOVER, MenuUI.FPV_GREEN, 2, 1, 6, 2))
	btn.add_theme_stylebox_override("pressed", MenuUI.feel_style(MenuUI.BUTTON_ACTIVE, MenuUI.FPV_GREEN, 2, 1, 6, 2))
	btn.add_theme_color_override("font_color", MenuUI.BUTTON_TEXT)
	btn.add_theme_color_override("font_hover_color", MenuUI.BUTTON_TEXT)
	btn.add_theme_color_override("font_pressed_color", MenuUI.BUTTON_ACTIVE_TEXT)
	btn.pressed.connect(_select_diff.bind(diff))
	if not btn.mouse_entered.is_connected(btn.grab_focus):
		btn.mouse_entered.connect(btn.grab_focus)
	_quick_diff_btns[diff] = btn
	return btn


func _build_realism_profile_btn(text: String, profile: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 22)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.focus_mode = Control.FOCUS_ALL
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_size_override("font_size", 10)
	btn.add_theme_stylebox_override("normal", MenuUI.feel_style(MenuUI.BUTTON_BG, MenuUI.FPV_BORDER, 1, 1, 6, 2))
	btn.add_theme_stylebox_override("hover", MenuUI.feel_style(MenuUI.BUTTON_HOVER, MenuUI.FPV_GREEN, 2, 1, 6, 2))
	btn.add_theme_stylebox_override("pressed", MenuUI.feel_style(MenuUI.BUTTON_ACTIVE, MenuUI.FPV_GREEN, 2, 1, 6, 2))
	btn.add_theme_color_override("font_color", MenuUI.BUTTON_TEXT)
	btn.add_theme_color_override("font_hover_color", MenuUI.BUTTON_TEXT)
	btn.add_theme_color_override("font_pressed_color", MenuUI.BUTTON_ACTIVE_TEXT)
	if profile == GameSettings.REALISM_ARCADE:
		btn.tooltip_text = "Штиль, без РЕБ, запас батареї та 100% зв’язку."
	else:
		btn.tooltip_text = "Вітер, зони РЕБ, дальність/рельєф і просідання напруги."
	btn.pressed.connect(_select_realism_profile.bind(profile))
	_realism_profile_btns[profile] = btn
	return btn


func _build_realism_check(text: String, key: String, hint: String) -> CheckButton:
	var check := CheckButton.new()
	check.text = text
	check.tooltip_text = hint
	check.add_theme_font_size_override("font_size", 10)
	check.focus_mode = Control.FOCUS_ALL
	check.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	check.toggled.connect(_on_realism_toggled.bind(key))
	_realism_checks[key] = check
	return check


func _select_realism_profile(profile: String) -> void:
	if GameSettings.apply_realism_profile(profile):
		_refresh_realism_controls()


func _on_realism_toggled(pressed: bool, key: String) -> void:
	if key == "reb_zones" and not bool(GameSettings.hud_config.get("link_limit", false)):
		_refresh_realism_controls()
		return
	match key:
		"wind_sim":
			GameSettings.hud_config["wind_sim"] = pressed
		"reb_zones":
			GameSettings.hud_config["reb_zones"] = pressed
		"link_battery":
			GameSettings.hud_config["link_limit"] = pressed
			GameSettings.hud_config["infinite_battery"] = not pressed
	GameSettings.refresh_realism_profile()
	GameSettings.save_hud_config()
	_refresh_realism_controls()


func _refresh_realism_controls() -> void:
	if _realism_checks.is_empty() and _realism_profile_btns.is_empty():
		return
	var hc := GameSettings.hud_config
	var profile := String(hc.get("realism_profile", GameSettings.REALISM_CUSTOM))
	var link_on := bool(hc.get("link_limit", false))
	var wind_cb: CheckButton = _realism_checks.get("wind_sim")
	if wind_cb != null:
		wind_cb.set_pressed_no_signal(bool(hc.get("wind_sim", false)))
	var reb_cb: CheckButton = _realism_checks.get("reb_zones")
	if reb_cb != null:
		reb_cb.set_pressed_no_signal(bool(hc.get("reb_zones", false)))
		reb_cb.disabled = not link_on
		reb_cb.modulate = Color.WHITE if link_on else Color(1.0, 1.0, 1.0, 0.62)
		reb_cb.tooltip_text = "Глушіння відео та керування поблизу ворожих антен." if link_on \
				else "Спочатку увімкніть обмеження зв’язку та батареї."
	var link_cb: CheckButton = _realism_checks.get("link_battery")
	if link_cb != null:
		link_cb.set_pressed_no_signal(link_on and not bool(hc.get("infinite_battery", false)))

	for p in _realism_profile_btns.keys():
		var b: Button = _realism_profile_btns[p]
		var active := profile == String(p)
		b.add_theme_stylebox_override("normal", MenuUI.feel_style(
				MenuUI.BUTTON_ACTIVE if active else MenuUI.BUTTON_BG,
				MenuUI.FPV_GREEN if active else MenuUI.FPV_BORDER,
				2 if active else 1, 1, 6, 2))
		b.add_theme_color_override("font_color",
				MenuUI.BUTTON_ACTIVE_TEXT if active else MenuUI.BUTTON_TEXT)

	if _realism_hint != null:
		match profile:
			GameSettings.REALISM_ARCADE:
				_realism_hint.text = "Аркада: штиль, без РЕБ, запас батареї та чисті 100% зв’язку."
			GameSettings.REALISM_COMBAT:
				_realism_hint.text = "Бойовий: вітер, зони РЕБ, дальність/рельєф і просідання напруги."
			_:
				_realism_hint.text = "Власний набір: окремі параметри увімкнено вручну."


func _build_modal_diff_btn(text: String, diff: int) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 32)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.focus_mode = Control.FOCUS_ALL
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_stylebox_override("normal", MenuUI.feel_style(MenuUI.BUTTON_BG, MenuUI.FPV_BORDER, 1, 1, 8, 3))
	btn.add_theme_stylebox_override("hover", MenuUI.feel_style(MenuUI.BUTTON_HOVER, MenuUI.FPV_GREEN, 2, 1, 8, 3))
	btn.add_theme_stylebox_override("pressed", MenuUI.feel_style(MenuUI.BUTTON_ACTIVE, MenuUI.FPV_GREEN, 2, 1, 8, 3))
	btn.add_theme_color_override("font_color", MenuUI.BUTTON_TEXT)
	btn.add_theme_color_override("font_hover_color", MenuUI.BUTTON_TEXT)
	btn.add_theme_color_override("font_pressed_color", MenuUI.BUTTON_ACTIVE_TEXT)
	btn.pressed.connect(_select_diff.bind(diff))
	if not btn.mouse_entered.is_connected(btn.grab_focus):
		btn.mouse_entered.connect(btn.grab_focus)
	_briefing_diff_btns[diff] = btn
	return btn


func _select_diff(diff: int) -> void:
	Global.difficulty = diff
	Global.menu_settings["difficulty"] = diff
	Global.save_menu_settings()
	_update_diff_buttons()
	_update_selection_ui()


func _update_diff_buttons() -> void:
	var is_en := MenuUI.is_english()
	for d in _quick_diff_btns.keys():
		var b: Button = _quick_diff_btns[d]
		var active: bool = int(Global.difficulty) == int(d)
		var hover_bg := MenuUI.BUTTON_ACTIVE.lightened(0.08) if active else MenuUI.BUTTON_HOVER
		b.add_theme_stylebox_override("normal", MenuUI.feel_style(
			MenuUI.BUTTON_ACTIVE if active else MenuUI.BUTTON_BG,
			MenuUI.FPV_GREEN if active else MenuUI.FPV_BORDER,
			2 if active else 1, 1, 6, 2))
		b.add_theme_stylebox_override("hover", MenuUI.feel_style(hover_bg, MenuUI.FPV_GREEN, 2, 1, 6, 2))
		b.add_theme_stylebox_override("focus", MenuUI.feel_style(hover_bg, MenuUI.FPV_GREEN, 2, 1, 6, 2))
		b.add_theme_color_override("font_color", MenuUI.BUTTON_ACTIVE_TEXT if active else MenuUI.BUTTON_TEXT)
		b.add_theme_color_override("font_hover_color", MenuUI.BUTTON_ACTIVE_TEXT if active else MenuUI.BUTTON_TEXT)

	for d in _briefing_diff_btns.keys():
		var b: Button = _briefing_diff_btns[d]
		var active: bool = int(Global.difficulty) == int(d)
		var hover_bg := MenuUI.BUTTON_ACTIVE.lightened(0.08) if active else MenuUI.BUTTON_HOVER
		b.add_theme_stylebox_override("normal", MenuUI.feel_style(
			MenuUI.BUTTON_ACTIVE if active else MenuUI.BUTTON_BG,
			MenuUI.FPV_GREEN if active else MenuUI.FPV_BORDER,
			2 if active else 1, 1, 8, 4))
		b.add_theme_stylebox_override("hover", MenuUI.feel_style(hover_bg, MenuUI.FPV_GREEN, 2, 1, 8, 4))
		b.add_theme_stylebox_override("focus", MenuUI.feel_style(hover_bg, MenuUI.FPV_GREEN, 2, 1, 8, 4))
		b.add_theme_color_override("font_color", MenuUI.BUTTON_ACTIVE_TEXT if active else MenuUI.BUTTON_TEXT)
		b.add_theme_color_override("font_hover_color", MenuUI.BUTTON_ACTIVE_TEXT if active else MenuUI.BUTTON_TEXT)

	if _quick_diff_lbl != null:
		match Global.difficulty:
			Global.Difficulty.RECRUIT:
				_quick_diff_lbl.text = "Recruit: +25% time (25 min) · light wind · reduced damage · score x1.0" if is_en else "Рекрут: +25% часу (25 хв) · помірний вітер · знижена шкода · бал x1.0"
			Global.Difficulty.OPERATOR:
				_quick_diff_lbl.text = "Operator: 20 min · realistic wind · full damage · score x1.25" if is_en else "Оператор: 20 хв · реалістичний вітер · бойова шкода · бал x1.25"
			Global.Difficulty.ACE:
				_quick_diff_lbl.text = "Ace: strict 15 min limit · gusting wind · accurate air defenses · score x1.75" if is_en else "Ас: жорсткий ліміт 15 хв · шквальний вітер · точне ППО · бал x1.75"

	if _briefing_diff_desc != null:
		match Global.difficulty:
			Global.Difficulty.RECRUIT:
				_briefing_diff_desc.text = "Recruit:\n• Time limit: 25:00 (+25%)\n• Light field wind (0.45)\n• 35% less damage from bullets and air defenses\n• Score multiplier: x1.00" if is_en else "Рекрут:\n• Ліміт часу: 25:00 хв (+25%)\n• Помірний польовий вітер (0,45)\n• На 35% менше шкоди від куль і ППО\n• Множник очок: x1,00"
			Global.Difficulty.OPERATOR:
				_briefing_diff_desc.text = "Operator:\n• Standard time: 20:00\n• Realistic turbulence and wind (1.00)\n• Full damage (100%)\n• Score multiplier: x1.25" if is_en else "Оператор:\n• Стандартний час: 20:00 хв\n• Реалістична турбулентність і вітер (1,00)\n• Повна бойова шкода (100%)\n• Множник очок: x1,25"
			Global.Difficulty.ACE:
				_briefing_diff_desc.text = "Ace:\n• Strict time limit: 15:00 (-25%)\n• Strong gusts (1.45)\n• Aggressive, accurate fire (+35% damage)\n• Score multiplier: x1.75" if is_en else "Ас:\n• Жорсткий ліміт часу: 15:00 хв (-25%)\n• Шквальні пориви вітру (1,45)\n• Агресивний і точний вогонь (+35% шкоди)\n• Множник очок: x1,75"

	_update_drone_intel()


func _launch_current_selection(combat_training: bool = false) -> void:
	Global.combat_training = combat_training
	Global.play_mode = _selected_mode
	if combat_training:
		# Three-step first-strike training: village north field, combat-ready
		# dropper, no campaign records and no freestyle ring course.
		Global.play_mode = Global.PlayMode.TRAINING
		_selected_mode = Global.PlayMode.TRAINING
		_selected_map = "village"
		Global.special_mission = 0
		QuadSettings.custom_rates = false
		DroneCatalog.apply(1)
	elif _selected_mode == Global.PlayMode.COMBAT:
		if _selected_special > 0:
			Global.special_mission = _selected_special
			Global.chain_briefing_pending = false
			if not DroneCatalog.is_combat(Global.drone_preset):
				QuadSettings.custom_rates = false
				DroneCatalog.apply(DroneCatalog.first_combat_index())
		else:
			Global.special_mission = 0
			if not Global.is_mission_unlocked(_selected_mission):
				_selected_mission = 1 if Global.campaign_is_complete() else Global.campaign_unlocked_mission()
			Global.combat_mission = clampi(_selected_mission, 1, 4)
			if not DroneCatalog.is_combat(Global.drone_preset):
				QuadSettings.custom_rates = false
				DroneCatalog.apply(DroneCatalog.first_combat_index())
	else:
		Global.special_mission = 0
	var map_id := _selected_map
	var scene_path: String = FRONTLINE_LEVELS.get(map_id, LEVEL)
	# The flight school has a fixed training strip on the north field of the
	# village map; the selected combat map must not move the course into water
	# or a forest.  The combat map choice itself is left untouched.
	if _selected_mode == Global.PlayMode.TUTORIAL:
		scene_path = FRONTLINE_LEVELS["village"]
	Global.menu_settings["selected_map"] = map_id
	Global.menu_settings["selected_mode"] = _selected_mode
	Global.menu_settings["selected_mission"] = _selected_mission
	Global.menu_settings["selected_special"] = _selected_special
	Global.menu_settings["drone_preset"] = Global.drone_preset
	Global.save_menu_settings()
	_begin_loading(scene_path)


func _build_briefing_modal() -> void:
	_briefing_modal = Control.new()
	MenuUI.full_rect(_briefing_modal)
	_briefing_modal.visible = false
	_briefing_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_briefing_modal)

	# 1. Dark frosted glass backdrop
	var backdrop := ColorRect.new()
	MenuUI.full_rect(backdrop)
	backdrop.color = Color(0.04, 0.06, 0.09, 0.88)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
			_close_briefing_dialog()
	)
	_briefing_modal.add_child(backdrop)

	# 2. Center container
	var center_c := CenterContainer.new()
	MenuUI.full_rect(center_c)
	center_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_briefing_modal.add_child(center_c)

	# 3. Main Dossier Card
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1000, 620)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", MenuUI.feel_style(MenuUI.FPV_BG_CARD, MenuUI.FPV_BORDER, 1, 10, 20, 16))
	center_c.add_child(panel)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	panel.add_child(main_vbox)

	# --- Header Bar ---
	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 12)
	main_vbox.add_child(top_bar)

	_briefing_title_lbl = Label.new()
	_briefing_title_lbl.text = "БОЙОВЕ ЗАВДАННЯ: [ TAC-01 ] ПІХОТА В УКРИТТЯХ"
	_briefing_title_lbl.add_theme_font_size_override("font_size", 16)
	_briefing_title_lbl.add_theme_color_override("font_color", MenuUI.FPV_TEXT)
	top_bar.add_child(_briefing_title_lbl)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(sp)

	var secret_badge := Label.new()
	secret_badge.text = "[ БОЙОВА ОПЕРАЦІЯ ЗСУ ]"
	secret_badge.add_theme_font_size_override("font_size", 11)
	secret_badge.add_theme_color_override("font_color", MenuUI.FPV_CYAN)
	top_bar.add_child(secret_badge)

	var close_btn := Button.new()
	close_btn.text = " ✕ "
	close_btn.custom_minimum_size = Vector2(32, 28)
	close_btn.focus_mode = Control.FOCUS_ALL
	close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	close_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close_btn.add_theme_font_size_override("font_size", 13)
	close_btn.add_theme_stylebox_override("normal", MenuUI.feel_style(MenuUI.BUTTON_BG, MenuUI.FPV_BORDER, 1, 1, 6, 2))
	close_btn.add_theme_stylebox_override("hover", MenuUI.feel_style(MenuUI.BUTTON_HOVER, MenuUI.FPV_GREEN, 2, 1, 6, 2))
	close_btn.add_theme_color_override("font_color", MenuUI.BUTTON_TEXT)
	close_btn.add_theme_color_override("font_hover_color", MenuUI.BUTTON_TEXT)
	close_btn.pressed.connect(_close_briefing_dialog)
	top_bar.add_child(close_btn)

	_briefing_sub_lbl = Label.new()
	_briefing_sub_lbl.text = "ОПЕРАЦІЯ: ...  •  СЕКТОР: ..."
	_briefing_sub_lbl.add_theme_font_size_override("font_size", 12)
	_briefing_sub_lbl.add_theme_color_override("font_color", MenuUI.FPV_MUTED)
	main_vbox.add_child(_briefing_sub_lbl)

	var sep1 := HSeparator.new()
	sep1.add_theme_stylebox_override("separator", MenuUI.feel_style(MenuUI.FPV_BORDER, MenuUI.FPV_BORDER, 1, 0, 0, 0))
	main_vbox.add_child(sep1)

	# --- 2 Columns Content ---
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 16)
	main_vbox.add_child(cols)

	# Left Column: Scrollable intelligence dossier
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cols.add_child(scroll)

	var left_dossier := VBoxContainer.new()
	left_dossier.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_dossier.add_theme_constant_override("separation", 6)
	scroll.add_child(left_dossier)

	left_dossier.add_child(MenuUI.feel_section("Розвіддані та обстановка"))
	_briefing_intel_lbl = Label.new()
	_briefing_intel_lbl.add_theme_font_size_override("font_size", 12)
	_briefing_intel_lbl.add_theme_color_override("font_color", MenuUI.FPV_TEXT)
	_briefing_intel_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_dossier.add_child(_briefing_intel_lbl)

	left_dossier.add_child(MenuUI.feel_section("Завдання операції"))
	_briefing_tasks_vbox = VBoxContainer.new()
	_briefing_tasks_vbox.add_theme_constant_override("separation", 4)
	left_dossier.add_child(_briefing_tasks_vbox)

	left_dossier.add_child(MenuUI.feel_section("Виявлені загрози"))
	_briefing_threats_lbl = Label.new()
	_briefing_threats_lbl.add_theme_font_size_override("font_size", 11)
	_briefing_threats_lbl.add_theme_color_override("font_color", Color(0.95, 0.65, 0.65))
	_briefing_threats_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_dossier.add_child(_briefing_threats_lbl)

	left_dossier.add_child(MenuUI.feel_section("Рекомендований дрон"))
	_briefing_drone_lbl = Label.new()
	_briefing_drone_lbl.add_theme_font_size_override("font_size", 12)
	_briefing_drone_lbl.add_theme_color_override("font_color", MenuUI.FPV_AMBER)
	left_dossier.add_child(_briefing_drone_lbl)

	left_dossier.add_child(MenuUI.feel_section("Метеоумови"))
	_briefing_weather_lbl = Label.new()
	_briefing_weather_lbl.add_theme_font_size_override("font_size", 11)
	_briefing_weather_lbl.add_theme_color_override("font_color", MenuUI.FPV_MUTED)
	left_dossier.add_child(_briefing_weather_lbl)

	# Right Column: Recon Minimap, Difficulty Selector, Rewards & Records
	var right_col := VBoxContainer.new()
	right_col.custom_minimum_size = Vector2(360, 0)
	right_col.add_theme_constant_override("separation", 6)
	cols.add_child(right_col)

	right_col.add_child(MenuUI.feel_section("Мапа сектору"))
	_briefing_map_canvas = _TacticalMapCanvas.new()
	_briefing_map_canvas.custom_minimum_size = Vector2(0, 110)
	right_col.add_child(_briefing_map_canvas)

	right_col.add_child(MenuUI.feel_section("Складність вильоту"))
	var diff_box := HBoxContainer.new()
	diff_box.add_theme_constant_override("separation", 6)
	diff_box.add_child(_build_modal_diff_btn("РЕКРУТ", Global.Difficulty.RECRUIT))
	diff_box.add_child(_build_modal_diff_btn("ОПЕРАТОР", Global.Difficulty.OPERATOR))
	diff_box.add_child(_build_modal_diff_btn("АС", Global.Difficulty.ACE))
	right_col.add_child(diff_box)

	_briefing_diff_desc = Label.new()
	_briefing_diff_desc.add_theme_font_size_override("font_size", 11)
	_briefing_diff_desc.add_theme_color_override("font_color", MenuUI.FPV_TEXT)
	_briefing_diff_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_col.add_child(_briefing_diff_desc)

	right_col.add_child(MenuUI.feel_section("Рекорди та нагороди"))
	_briefing_record_lbl = Label.new()
	_briefing_record_lbl.add_theme_font_size_override("font_size", 11)
	_briefing_record_lbl.add_theme_color_override("font_color", MenuUI.FPV_CYAN)
	_briefing_record_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_col.add_child(_briefing_record_lbl)

	_briefing_rewards_lbl = Label.new()
	_briefing_rewards_lbl.add_theme_font_size_override("font_size", 11)
	_briefing_rewards_lbl.add_theme_color_override("font_color", MenuUI.FPV_AMBER)
	_briefing_rewards_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_col.add_child(_briefing_rewards_lbl)

	var sep2 := HSeparator.new()
	sep2.add_theme_stylebox_override("separator", MenuUI.feel_style(MenuUI.FPV_BORDER, MenuUI.FPV_BORDER, 1, 0, 0, 0))
	main_vbox.add_child(sep2)

	# --- Bottom Action Bar ---
	var modal_actions := HBoxContainer.new()
	modal_actions.add_theme_constant_override("separation", 12)
	main_vbox.add_child(modal_actions)

	var cancel_btn := MenuUI.feel_button("←  Назад до меню", 38, false)
	cancel_btn.custom_minimum_size = Vector2(180, 38)
	cancel_btn.pressed.connect(_close_briefing_dialog)
	modal_actions.add_child(cancel_btn)

	var start_mission_btn := Button.new()
	start_mission_btn.text = "▶  ПІДТВЕРДИТИ ТА ПОЧАТИ ВИЛІТ"
	start_mission_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_mission_btn.custom_minimum_size = Vector2(0, 38)
	start_mission_btn.focus_mode = Control.FOCUS_ALL
	start_mission_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	start_mission_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	start_mission_btn.add_theme_font_size_override("font_size", 14)
	start_mission_btn.add_theme_color_override("font_color", MenuUI.BUTTON_ACTIVE_TEXT)
	start_mission_btn.add_theme_color_override("font_hover_color", MenuUI.BUTTON_ACTIVE_TEXT)
	start_mission_btn.add_theme_stylebox_override("normal", MenuUI.feel_style(MenuUI.BUTTON_ACTIVE, MenuUI.FPV_GREEN, 2, 1, 14, 6))
	start_mission_btn.add_theme_stylebox_override("hover", MenuUI.feel_style(MenuUI.BUTTON_ACTIVE.lightened(0.08), MenuUI.FPV_GREEN, 2, 1, 14, 6))
	start_mission_btn.add_theme_stylebox_override("pressed", MenuUI.feel_style(MenuUI.BUTTON_ACTIVE.darkened(0.08), MenuUI.FPV_GREEN, 2, 1, 14, 6))
	start_mission_btn.add_theme_stylebox_override("focus", MenuUI.feel_style(MenuUI.BUTTON_ACTIVE.lightened(0.08), MenuUI.FPV_GREEN, 2, 1, 14, 6))
	start_mission_btn.pressed.connect(_confirm_and_launch_mission)
	modal_actions.add_child(start_mission_btn)


func _open_briefing_dialog(mission_id: int) -> void:
	if not BRIEFINGS.has(mission_id):
		return
	if not Global.is_mission_unlocked(mission_id):
		return
	_selected_mode = Global.PlayMode.COMBAT
	_selected_mission = mission_id
	var b: Dictionary = BRIEFINGS[mission_id]
	var is_en := MenuUI.is_english()
	var content: Dictionary = BRIEFINGS_EN.get(mission_id, {}) if is_en else b
	if is_en:
		_briefing_title_lbl.text = "MISSION ORDER: [ %s ] %s" % [b["code"], content.get("name", b["name"])]
		_briefing_sub_lbl.text = "%s   •   SECTOR: %s" % [content.get("op_name", b["op_name"]), content.get("sector", b["sector"])]
	else:
		_briefing_title_lbl.text = "БОЙОВИЙ НАКАЗ ШТАБУ: [ %s ] %s" % [b["code"], b["name"]]
		_briefing_sub_lbl.text = "%s   •   СЕКТОР: %s" % [b["op_name"], b["sector"]]
	_briefing_intel_lbl.text = str(content.get("intel", b["intel"]))

	for c in _briefing_tasks_vbox.get_children():
		c.queue_free()
	for t in content.get("tasks", b["tasks"]):
		var t_row := HBoxContainer.new()
		t_row.add_theme_constant_override("separation", 6)
		var check := Label.new()
		check.text = "✔"
		check.add_theme_font_size_override("font_size", 12)
		check.add_theme_color_override("font_color", MenuUI.ACCENT)
		t_row.add_child(check)

		var t_lbl := Label.new()
		t_lbl.text = str(t)
		t_lbl.add_theme_font_size_override("font_size", 12)
		t_lbl.add_theme_color_override("font_color", Color(0.90, 0.95, 0.90))
		t_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t_row.add_child(t_lbl)
		_briefing_tasks_vbox.add_child(t_row)

	_briefing_threats_lbl.text = "• " + "\n• ".join(content.get("threats", b["threats"]))
	_briefing_drone_lbl.text = str(content.get("drone", b["drone"]))
	_briefing_weather_lbl.text = str(content.get("weather", b["weather"]))
	_briefing_rewards_lbl.text = "\n".join(content.get("rewards", b["rewards"]))

	var rec: Dictionary = Global.get_mission_record(mission_id)
	if bool(rec.get("completed", false)):
		var stars := int(rec.get("stars", 1))
		var stars_str := ""
		for s in range(stars):
			stars_str += "★"
		_briefing_record_lbl.text = ("YOUR RECORD: %d PTS  •  BEST TIME: %s  •  AWARD: %s" if is_en else "ВАШ РЕКОРД: %d ОЧОК  •  НАЙКРАЩИЙ ЧАС: %s  •  ВІДЗНАКА: %s") % [
			int(rec.get("best_score", 0)),
			_format_time(float(rec.get("best_time", 0.0))),
			stars_str
		]
		_briefing_record_lbl.add_theme_color_override("font_color", MenuUI.ACCENT)
	else:
		_briefing_record_lbl.text = "STATUS: NOT COMPLETED — FLY THIS SORTIE TO SET A RECORD" if is_en else "СТАТУС: МІСІЮ ЩЕ НЕ ВИКОНАНО — ВИЛЕТІТЬ, ЩОБ УСТАНОВИТИ РЕКОРД"
		_briefing_record_lbl.add_theme_color_override("font_color", MenuUI.MUTED)

	if _briefing_map_canvas != null:
		_briefing_map_canvas.set_selection(Global.PlayMode.COMBAT, mission_id)

	_update_diff_buttons()
	_briefing_modal.visible = true
	_update_selection_ui()
	MenuUI.localize_tree(self)


func _close_briefing_dialog() -> void:
	if _briefing_modal != null:
		_briefing_modal.visible = false
	if _launch_btn != null and _launch_btn.is_inside_tree():
		_launch_btn.grab_focus()


func _confirm_and_launch_mission() -> void:
	if _briefing_modal != null:
		_briefing_modal.visible = false
	_launch_current_selection()


func _format_time(sec: float) -> String:
	var total_s := int(floor(sec))
	var m := total_s / 60
	var s := total_s % 60
	var cs := int(floor((sec - floor(sec)) * 100.0))
	return "%02d:%02d.%02d" % [m, s, cs]


# ==============================================================================
# RIGHT PANEL: 3D ROTATABLE DRONE PREVIEW & INTEL
# ==============================================================================
func _build_drone_intel_card() -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", MenuUI.feel_style(MenuUI.FPV_BG_CARD, MenuUI.FPV_BORDER, 1, 8, 10, 6))

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	card.add_child(hbox)

	# Left Arrow Button: ◄
	_prev_drone_btn = Button.new()
	_prev_drone_btn.text = " ◄ "
	_prev_drone_btn.custom_minimum_size = Vector2(34, 34)
	_prev_drone_btn.tooltip_text = "Попередній дрон"
	_prev_drone_btn.focus_mode = Control.FOCUS_ALL
	_prev_drone_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_prev_drone_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_prev_drone_btn.add_theme_font_size_override("font_size", 14)
	_prev_drone_btn.add_theme_color_override("font_color", MenuUI.BUTTON_TEXT)
	_prev_drone_btn.add_theme_color_override("font_hover_color", MenuUI.BUTTON_TEXT)
	_prev_drone_btn.add_theme_stylebox_override("normal", MenuUI.feel_style(MenuUI.BUTTON_BG, MenuUI.FPV_BORDER, 1, 1, 6, 2))
	_prev_drone_btn.add_theme_stylebox_override("hover", MenuUI.feel_style(MenuUI.BUTTON_HOVER, MenuUI.FPV_GREEN, 2, 1, 6, 2))
	# One click must move exactly one drone.  `pressed` already covers mouse,
	# keyboard and gamepad; the old `gui_input` handler fired on the same click
	# and skipped two frames.
	_prev_drone_btn.pressed.connect(_cycle_drone.bind(-1))
	if not _prev_drone_btn.mouse_entered.is_connected(_prev_drone_btn.grab_focus):
		_prev_drone_btn.mouse_entered.connect(_prev_drone_btn.grab_focus)
	hbox.add_child(_prev_drone_btn)

	var title_vbox := VBoxContainer.new()
	title_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	title_vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(title_vbox)

	_drone_title_lbl = Label.new()
	_drone_title_lbl.add_theme_font_size_override("font_size", 14)
	_drone_title_lbl.add_theme_color_override("font_color", MenuUI.FPV_TEXT)
	title_vbox.add_child(_drone_title_lbl)

	_drone_sub_lbl = Label.new()
	_drone_sub_lbl.add_theme_font_size_override("font_size", 11)
	_drone_sub_lbl.add_theme_color_override("font_color", MenuUI.FPV_MUTED)
	title_vbox.add_child(_drone_sub_lbl)

	# Right Arrow Button: ►
	_next_drone_btn = Button.new()
	_next_drone_btn.text = " ► "
	_next_drone_btn.custom_minimum_size = Vector2(34, 34)
	_next_drone_btn.tooltip_text = "Наступний дрон"
	_next_drone_btn.focus_mode = Control.FOCUS_ALL
	_next_drone_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_next_drone_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_next_drone_btn.add_theme_font_size_override("font_size", 14)
	_next_drone_btn.add_theme_color_override("font_color", MenuUI.BUTTON_TEXT)
	_next_drone_btn.add_theme_color_override("font_hover_color", MenuUI.BUTTON_TEXT)
	_next_drone_btn.add_theme_stylebox_override("normal", MenuUI.feel_style(MenuUI.BUTTON_BG, MenuUI.FPV_BORDER, 1, 1, 6, 2))
	_next_drone_btn.add_theme_stylebox_override("hover", MenuUI.feel_style(MenuUI.BUTTON_HOVER, MenuUI.FPV_GREEN, 2, 1, 6, 2))
	_next_drone_btn.pressed.connect(_cycle_drone.bind(1))
	if not _next_drone_btn.mouse_entered.is_connected(_next_drone_btn.grab_focus):
		_next_drone_btn.mouse_entered.connect(_next_drone_btn.grab_focus)
	hbox.add_child(_next_drone_btn)

	_update_drone_intel()
	return card


func _cycle_drone(dir: int) -> void:
	var total := DroneCatalog.count()
	if total <= 0:
		return
	var new_idx := (Global.drone_preset + dir + total) % total
	if _selected_mode == Global.PlayMode.COMBAT \
			and not DroneCatalog.is_combat(new_idx):
		_selected_mode = Global.PlayMode.TRAINING
		_selected_special = 0
		Global.play_mode = Global.PlayMode.TRAINING
		Global.menu_settings["selected_mode"] = Global.PlayMode.TRAINING
		Global.menu_settings["selected_special"] = 0
	# Choosing a drone in the menu applies its parameters
	QuadSettings.custom_rates = false
	DroneCatalog.apply(new_idx)
	Global.menu_settings["drone_preset"] = new_idx
	Global.save_menu_settings()
	_update_drone_intel()
	_load_drone_model()
	_update_selection_ui()


func _update_drone_intel() -> void:
	if _drone_title_lbl == null or _drone_sub_lbl == null:
		return
	var is_en := (LocScript.get_language() == LocScript.Language.EN)
	var idx := Global.drone_preset
	var total := DroneCatalog.count()
	var p := DroneCatalog.preset(idx)
	var drone_preset_name := MenuUI.translate_text(DroneCatalog.get_drone_name(idx)).to_upper()
	var drone_tag := MenuUI.translate_text(DroneCatalog.get_drone_tag(idx))
	if is_en:
		_drone_title_lbl.text = "ACTIVE CRAFT [%d/%d]:  %s  [%s]" % [idx + 1, total, drone_preset_name, drone_tag]
	else:
		_drone_title_lbl.text = "АКТИВНИЙ ДРОН [%d/%d]:  %s  [%s]" % [idx + 1, total, drone_preset_name, drone_tag]

	var total_mass: float = float(p.get("dry", 0.4)) + float(p.get("batt", 0.2)) + float(p.get("payload_mass", 0.0))
	var is_combat: bool = bool(p.get("combat", false))
	var has_drop: bool = bool(p.get("has_drop", false))
	var ammo: int = int(p.get("payload", 0)) if is_combat else 0
	var ammo_text: String
	if not is_combat:
		ammo_text = "NONE" if is_en else "ВІДСУТНІЙ"
	elif has_drop:
		ammo_text = ("%s [DROP]" if is_en else "%s [СКИД]") % DroneCatalog.get_drone_drop_name(idx)
	else:
		ammo_text = ("%dx TACTICAL PAYLOAD" if is_en else "%dх ТАКТ. НАВАНТ.") % ammo
	if is_en:
		_drone_sub_lbl.text = "⚖️ MASS: %.2f kg  ·  ⚡ MOTORS: %d KV  ·  🚀 TWR: %.1f:1  ·  💣 %s" % [
			total_mass, int(p.get("kv", 2200)), float(p.get("twr", 6.0)), ammo_text
		]
	else:
		_drone_sub_lbl.text = "⚖️ Маса: %.2f кг  ·  ⚡ Мотори: %d KV  ·  🚀 Тяга: %.1f:1  ·  💣 %s" % [
			total_mass, int(p.get("kv", 2200)), float(p.get("twr", 6.0)), ammo_text
		]


func _build_3d_drone_card() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0, 180)
	panel.add_theme_stylebox_override("panel", MenuUI.feel_style(MenuUI.FPV_PANEL, MenuUI.FPV_BORDER, 1, 8, 8, 6))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	# One unobtrusive spin toggle; the model itself can be dragged and zoomed.
	var view_bar := HBoxContainer.new()
	view_bar.add_theme_constant_override("separation", 6)
	vbox.add_child(view_bar)

	_auto_orbit_btn = Button.new()
	_auto_orbit_btn.text = "↻"
	_auto_orbit_btn.tooltip_text = _ui_text("Автообертання", "Auto-rotate")
	_auto_orbit_btn.custom_minimum_size = Vector2(34, 28)
	_auto_orbit_btn.add_theme_font_size_override("font_size", 16)
	_auto_orbit_btn.add_theme_stylebox_override("normal", MenuUI.feel_style(MenuUI.FPV_BG_CARD, MenuUI.FPV_BLUE, 1, 6, 8, 2))
	_auto_orbit_btn.add_theme_color_override("font_color", MenuUI.FPV_CYAN)
	_auto_orbit_btn.pressed.connect(func():
		_auto_orbit = not _auto_orbit
		_auto_orbit_btn.text = "↻" if _auto_orbit else "Ⅱ"
		_auto_orbit_btn.tooltip_text = _ui_text("Автообертання", "Auto-rotate") if _auto_orbit else _ui_text("Обертання призупинено", "Rotation paused")
		_auto_orbit_btn.add_theme_color_override("font_color", MenuUI.FPV_CYAN if _auto_orbit else MenuUI.FPV_MUTED)
	)
	view_bar.add_child(_auto_orbit_btn)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view_bar.add_child(sp)

	# Interactive model viewport.
	_viewport_container = SubViewportContainer.new()
	_viewport_container.stretch = true
	_viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_viewport_container.mouse_filter = Control.MOUSE_FILTER_STOP
	_viewport_container.mouse_default_cursor_shape = Control.CURSOR_CROSS
	_viewport_container.gui_input.connect(_on_3d_gui_input)
	vbox.add_child(_viewport_container)

	_sub_viewport = SubViewport.new()
	_sub_viewport.own_world_3d = true
	_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# The preview is a separate viewport: it does NOT inherit the root
	# viewport's MSAA. 2x MSAA keeps edges crisp without driver stalls.
	_sub_viewport.msaa_3d = Viewport.MSAA_2X
	_sub_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_viewport_container.add_child(_sub_viewport)

	_setup_3d_scene()

	var hint_lbl := Label.new()
	hint_lbl.text = _ui_text("Перетягніть, щоб обертати · Колесо — масштаб", "Drag to rotate · Scroll to zoom")
	hint_lbl.add_theme_font_size_override("font_size", 10)
	hint_lbl.add_theme_color_override("font_color", MenuUI.FPV_MUTED)
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint_lbl)

	return panel


func _build_view_btn(text: String, en_text: String, action: Callable) -> Button:
	var btn := Button.new()
	var is_en := (LocScript.get_language() == LocScript.Language.EN)
	btn.text = en_text if is_en else text
	btn.custom_minimum_size = Vector2(0, 26)
	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_stylebox_override("normal", MenuUI.feel_style(MenuUI.FPV_BG_CARD, MenuUI.FPV_BORDER, 1, 6, 8, 2))
	btn.add_theme_stylebox_override("hover", MenuUI.feel_style(Color("162438"), MenuUI.FPV_CYAN, 1, 6, 8, 2))
	btn.add_theme_color_override("font_color", MenuUI.FPV_TEXT)
	btn.add_theme_color_override("font_hover_color", MenuUI.FPV_CYAN)
	btn.pressed.connect(action)
	return btn


func _setup_3d_scene() -> void:
	# A calm studio sky replaces the flat viewport fill.  The warm horizon and
	# deep sage zenith separate dark carbon frames from the stage without adding
	# a costly background texture or another render pass.
	var env := Environment.new()
	var studio_sky_material := ProceduralSkyMaterial.new()
	studio_sky_material.sky_top_color = Color("15272b")
	studio_sky_material.sky_horizon_color = Color("34443d")
	studio_sky_material.ground_horizon_color = Color("34443d")
	studio_sky_material.ground_bottom_color = Color("101817")
	studio_sky_material.sun_angle_max = 0.0
	var studio_sky := Sky.new()
	studio_sky.sky_material = studio_sky_material
	env.background_mode = Environment.BG_SKY
	env.sky = studio_sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.74, 0.82, 0.76)
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.01
	env.adjustment_saturation = 1.08

	var world := WorldEnvironment.new()
	world.environment = env
	_sub_viewport.add_child(world)

	# Primary Key Directional Light (top-front-right)
	var key_light := DirectionalLight3D.new()
	key_light.light_energy = 1.5
	key_light.light_color = Color(1.0, 0.98, 0.95)
	key_light.rotation_degrees = Vector3(-35.0, 45.0, 0.0)
	_sub_viewport.add_child(key_light)

	# Studio Spotlight from directly above drone
	var spot := SpotLight3D.new()
	spot.position = Vector3(0.0, 2.3, 0.0)
	spot.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	spot.light_energy = 0.8
	spot.light_color = Color(0.88, 0.95, 1.0)
	spot.spot_range = 4.0
	spot.spot_angle = 50.0
	spot.spot_attenuation = 1.1
	_sub_viewport.add_child(spot)

	# Left Fill Light (soft cool cyan tint)
	var fill_light := DirectionalLight3D.new()
	fill_light.light_energy = 0.55
	fill_light.light_color = Color(0.28, 0.78, 0.56)
	fill_light.rotation_degrees = Vector3(-20.0, -75.0, 0.0)
	_sub_viewport.add_child(fill_light)

	# Right Rim Light (warm amber rim)
	var rim_light := DirectionalLight3D.new()
	rim_light.light_energy = 0.85
	rim_light.light_color = Color(1.0, 0.85, 0.60)
	rim_light.rotation_degrees = Vector3(25.0, 125.0, 0.0)
	_sub_viewport.add_child(rim_light)

	# Frontal fill for the nose and payload when the model faces the camera.
	var front_light := DirectionalLight3D.new()
	front_light.light_energy = 0.55
	front_light.light_color = Color(0.78, 0.88, 0.90)
	front_light.rotation_degrees = Vector3(-8.0, 0.0, 0.0)
	_sub_viewport.add_child(front_light)

	# Camera
	_camera = Camera3D.new()
	_camera.fov = 38.0
	_camera.near = 0.05
	_camera.far = 100.0
	_sub_viewport.add_child(_camera)
	_update_cam_transform()

	# Pedestal: Minimalist studio dark titanium disc
	var base_pedestal := MeshInstance3D.new()
	var base_cyl := CylinderMesh.new()
	base_cyl.top_radius = 0.52
	base_cyl.bottom_radius = 0.56
	base_cyl.height = 0.02
	base_pedestal.mesh = base_cyl
	base_pedestal.position = Vector3(0.0, -0.38, 0.0)
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.08, 0.10, 0.14)
	base_mat.roughness = 0.35
	base_mat.metallic = 0.8
	base_pedestal.material_override = base_mat
	_sub_viewport.add_child(base_pedestal)

	# Outer glowing ring (Electric FPV Blue)
	var outer_ring := MeshInstance3D.new()
	var outer_torus := TorusMesh.new()
	outer_torus.inner_radius = 0.48
	outer_torus.outer_radius = 0.50
	outer_ring.mesh = outer_torus
	outer_ring.position = Vector3(0.0, -0.368, 0.0)
	var outer_mat := StandardMaterial3D.new()
	outer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outer_mat.albedo_color = MenuUI.FPV_BLUE
	outer_ring.material_override = outer_mat
	_sub_viewport.add_child(outer_ring)

	# Holder node for the loaded 3D drone
	_model_holder = Node3D.new()
	_sub_viewport.add_child(_model_holder)

	call_deferred("_load_drone_model")


func _load_drone_model() -> void:
	if _model_holder == null:
		return
	for c in _model_holder.get_children():
		c.queue_free()
	var model := DroneCatalog.attach_model(_model_holder, Global.drone_preset)
	if model == null:
		return

	if not model.is_inside_tree():
		await model.ready

	# Normalize the live aircraft to the showcase stage. Previously a fixed 2.2m
	# target overwhelmed the small menu viewport and cropped the model.
	var target_bottom := -0.26
	var box := MenuUI.fit_preview_model(model, 1.15, target_bottom)
	# AABB fitting is not enough for every imported kit: skinned tailsitters
	# and a few GLBs report a bind-pose box that does not match the rendered
	# lowest point.  Correct against the actual world-space visual bounds and
	# give the known landing-skid airframes a little extra clearance.
	var actual := _preview_world_aabb(model)
	if actual.size.length_squared() > 0.000001:
		var extra_lift := 0.0
		match str(DroneCatalog.preset(Global.drone_preset).get("id", "")):
			"pisun_vtol":
				extra_lift = 0.10
			"grim7", "grim7m":
				extra_lift = 0.03
		model.position.y += (target_bottom - actual.position.y) + extra_lift
		model.force_update_transform()
		box = _preview_world_aabb(model)
	if box.size.length_squared() > 0.000001:
		# Tall VTOL airframes need both a longer lens distance and a raised
		# focus point; framing them around the pedestal clipped their noses and
		# landing gear.  Flat quads keep the original framing.
		_auto_cam_dist = clampf(
				maxf(box.size.length() * 1.10, box.size.y * 1.95), 1.25, 3.2)
		_cam_dist = _auto_cam_dist
		var tall := clampf((box.size.y - 0.25) / 0.65, 0.0, 1.0)
		_preview_focus_y = lerpf(-0.08, box.get_center().y, tall)
	_update_cam_transform()


func _preview_world_aabb(model: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for n in model.find_children("*", "VisualInstance3D", true, false):
		var visual := n as VisualInstance3D
		if visual == null:
			continue
		var box: AABB = visual.global_transform * visual.get_aabb()
		if first:
			result = box
			first = false
		else:
			result = result.merge(box)
	return result


func _on_3d_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_is_dragging = event.pressed
			_drag_start = event.position
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			# Reset to default tactical view
			_cam_yaw = 0.60
			_cam_pitch = 0.35
			_cam_dist = _auto_cam_dist
			_update_cam_transform()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_dist = clampf(_cam_dist - 0.08, 0.55, 4.6)
			_update_cam_transform()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_dist = clampf(_cam_dist + 0.08, 0.55, 4.6)
			_update_cam_transform()

	elif event is InputEventMouseMotion and _is_dragging:
		_cam_yaw -= event.relative.x * 0.012
		_cam_pitch = clampf(_cam_pitch + event.relative.y * 0.010, -0.65, 1.25)
		_update_cam_transform()


func _update_cam_transform() -> void:
	if _camera == null:
		return
	var cos_p := cos(_cam_pitch)
	var sin_p := sin(_cam_pitch)
	var cp := Vector3(cos_p * sin(_cam_yaw), sin_p, cos_p * cos(_cam_yaw)) * _cam_dist
	var focus := Vector3(0.0, _preview_focus_y, 0.0)
	_camera.look_at_from_position(focus + cp, focus, Vector3.UP)


func _process(delta: float) -> void:
	# Gentle tactical auto-orbit when the user is not actively dragging and auto-orbit is enabled
	if _auto_orbit and not _is_dragging:
		_cam_yaw += delta * 0.32
		_update_cam_transform()
	if _model_holder != null:
		for m in _model_holder.get_children():
			if m is Node3D:
				DroneCatalog.animate_propellers(m as Node3D, delta)
	_process_loading(delta)


# ==============================================================================
# SYSTEM & NAVIGATION HELPERS
# ==============================================================================
func _ui_text(uk: String, en: String) -> String:
	return en if MenuUI.is_english() else uk


func _refresh_mode_button_labels() -> void:
	for mode in _mode_buttons:
		var button := _mode_buttons[mode] as Button
		var copy: Dictionary = _mode_copy.get(mode, {})
		if button == null or copy.is_empty():
			continue
		var title := button.get_node_or_null("VBox/Title") as Label
		var subtitle := button.get_node_or_null("VBox/Sub") as Label
		if title != null:
			title.text = str(copy["en_title"] if MenuUI.is_english() else copy["uk_title"])
		if subtitle != null:
			subtitle.text = str(copy["en_desc"] if MenuUI.is_english() else copy["uk_desc"])


func _build_top_telemetry_bar() -> Control:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", MenuUI.feel_style(MenuUI.FPV_PANEL_HEADER, MenuUI.FPV_BORDER, 1, 10, 14, 6))

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	bar.add_child(hbox)

	_top_title_lbl = Label.new()
	_top_title_lbl.text = _ui_text("Підготовка до вильоту", "SORTIE SETUP")
	_top_title_lbl.add_theme_font_size_override("font_size", 18)
	_top_title_lbl.add_theme_color_override("font_color", MenuUI.FPV_TEXT)
	hbox.add_child(_top_title_lbl)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	_gc_btn = MenuUI.feel_button(
		_ui_text("🏆 Рекорди", "🏆 GC" if Global.is_game_center_available() else "🏆 Records"), 34, false)
	_gc_btn.custom_minimum_size.x = 112
	_gc_btn.pressed.connect(func():
		var is_en := MenuUI.is_english()
		if Global.is_game_center_available():
			Global.open_game_center_leaderboard()
		else:
			var dlg := AcceptDialog.new()
			dlg.title = "PILOT RECORDS" if is_en else "РЕКОРДИ ПІЛОТА"
			dlg.dialog_text = Global.get_records_report(is_en)
			dlg.confirmed.connect(dlg.queue_free)
			dlg.canceled.connect(dlg.queue_free)
			add_child(dlg)
			dlg.popup_centered(Vector2i(520, 420))
		if _daily_lbl != null:
			_daily_lbl.text = Global.get_leaderboard_summary(is_en)
	)
	hbox.add_child(_gc_btn)

	_lang_btn = MenuUI.feel_button(_ui_text("🌐 UA → EN", "🌐 EN → UA"), 34, false)
	_lang_btn.custom_minimum_size.x = 112
	_lang_btn.pressed.connect(_on_toggle_language)
	hbox.add_child(_lang_btn)

	var settings_btn := MenuUI.feel_button(_ui_text("⚙ Налаштування", "⚙ Settings"), 34, false)
	settings_btn.custom_minimum_size.x = 126
	settings_btn.pressed.connect(_open_settings_overlay)
	hbox.add_child(settings_btn)
	return bar


func _on_toggle_language() -> void:
	LocScript.toggle_language()
	_refresh_mode_button_labels()
	_update_selection_ui()
	MenuUI.localize_tree(self)


func _open_settings_overlay() -> void:
	if _settings_overlay != null and is_instance_valid(_settings_overlay):
		return
	var packed := load(OPTIONS_SCREEN) as PackedScene
	if packed == null:
		return
	_settings_overlay = packed.instantiate() as Control
	if _settings_overlay == null:
		return
	_settings_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	if _settings_overlay.has_signal("back"):
		_settings_overlay.connect("back", Callable(self, "_close_settings_overlay"))
	add_child(_settings_overlay)


func _close_settings_overlay() -> void:
	if _settings_overlay != null and is_instance_valid(_settings_overlay):
		_settings_overlay.queue_free()
	_settings_overlay = null


func _build_ufds_ribbon() -> Control:
	var ribbon := PanelContainer.new()
	ribbon.add_theme_stylebox_override("panel", MenuUI.feel_style(MenuUI.FPV_BG_CARD, MenuUI.FPV_BORDER, 1, 6, 8, 3))

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	ribbon.add_child(h)

	var tabs := [
		{"key": Global.PlayMode.TUTORIAL, "icon": "🎓", "title": "Туторіал", "en": "Tutorial", "action": func(): _select_mode(Global.PlayMode.TUTORIAL)},
		{"key": Global.PlayMode.TRAINING, "icon": "🌲", "title": "Тренування", "en": "Training", "action": func(): _select_mode(Global.PlayMode.TRAINING)},
		{"key": Global.PlayMode.COMBAT, "icon": "⚔️", "title": "Бойовий", "en": "Combat", "action": func(): _select_mode(Global.PlayMode.COMBAT)},
		{"key": "hangar", "icon": "🛸", "title": "Ангар", "en": "Fleet Hangar", "action": func(): _go(DRONE_SCREEN)},
		{"key": "calibration", "icon": "🕹️", "title": "Калібрування", "en": "RC Calibration", "action": func(): _go(CALIBRATION_SCREEN)},
		{"key": "settings", "icon": "⚙️", "title": "Налаштування", "en": "Settings", "action": func(): _go(GRAPHICS_SCREEN)}
	]

	var is_en := (LocScript.get_language() == LocScript.Language.EN)
	for t in tabs:
		var btn := Button.new()
		btn.text = "%s %s" % [t["icon"], t["en"] if is_en else t["title"]]
		btn.custom_minimum_size = Vector2(0, 32)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.focus_mode = Control.FOCUS_ALL
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.add_theme_font_size_override("font_size", 11)
		btn.add_theme_stylebox_override("normal", MenuUI.feel_style(MenuUI.FPV_BG_CARD, MenuUI.FPV_BORDER, 1, 6, 8, 3))
		btn.add_theme_stylebox_override("hover", MenuUI.feel_style(Color("162438"), MenuUI.FPV_CYAN, 1, 6, 8, 3))
		btn.add_theme_stylebox_override("pressed", MenuUI.feel_style(Color("0e1824"), MenuUI.FPV_CYAN, 2, 6, 8, 3))
		btn.add_theme_color_override("font_color", MenuUI.FPV_TEXT)
		btn.add_theme_color_override("font_hover_color", MenuUI.FPV_CYAN)
		var fn: Callable = t["action"]
		btn.pressed.connect(fn)
		if not btn.mouse_entered.is_connected(btn.grab_focus):
			btn.mouse_entered.connect(btn.grab_focus)
		h.add_child(btn)
		_ribbon_buttons[t["key"]] = btn

	return ribbon


func _set_cam_view(yaw: float, pitch: float, dist: float) -> void:
	_cam_yaw = yaw
	_cam_pitch = pitch
	_cam_dist = dist
	_update_cam_transform()


func _nav_button(text: String, scene: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 36)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_stylebox_override("normal", MenuUI.feel_style(MenuUI.FPV_BG_CARD, MenuUI.FPV_BORDER, 1, 6, 10, 4))
	button.add_theme_stylebox_override("hover", MenuUI.feel_style(Color("162438"), MenuUI.FPV_CYAN, 1, 6, 10, 4))
	button.add_theme_stylebox_override("pressed", MenuUI.feel_style(Color("0e1824"), MenuUI.FPV_CYAN, 2, 6, 10, 4))
	button.add_theme_stylebox_override("focus", MenuUI.feel_style(Color("162438"), MenuUI.FPV_CYAN, 1, 6, 10, 4))
	button.add_theme_color_override("font_color", MenuUI.FPV_TEXT)
	button.add_theme_color_override("font_hover_color", MenuUI.FPV_CYAN)
	if not button.mouse_entered.is_connected(button.grab_focus):
		button.mouse_entered.connect(button.grab_focus)
	if not scene.is_empty():
		button.pressed.connect(_go.bind(scene))
	return button


func _go(scene: String) -> void:
	if scene == CALIBRATION_SCREEN:
		Global.calibration_return_scene = ""
	get_tree().change_scene_to_file(scene)


func _on_quit_pressed() -> void:
	get_tree().quit()


func _input(event: InputEvent) -> void:
	if _briefing_modal != null and _briefing_modal.visible:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				_close_briefing_dialog()
				return
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_LEFT:
			get_viewport().set_input_as_handled()
			_cycle_drone(-1)
		elif event.keycode == KEY_RIGHT:
			get_viewport().set_input_as_handled()
			_cycle_drone(1)


func _unhandled_input(event: InputEvent) -> void:
	if _briefing_modal != null and _briefing_modal.visible:
		if event.is_action_pressed("ui_cancel"):
			accept_event()
			_close_briefing_dialog()
		return

	if event.is_action_pressed("ui_cancel"):
		accept_event()
		get_tree().change_scene_to_file(START_SCREEN)
	elif event.is_action_pressed("ui_left"):
		accept_event()
		_cycle_drone(-1)
	elif event.is_action_pressed("ui_right"):
		accept_event()
		_cycle_drone(1)

# ==============================================================================
# MISSION LOADING SCREEN
# ==============================================================================
var _loading_layer: CanvasLayer = null
var _loading_bar: ProgressBar = null
var _loading_target := ""
var _loading_elapsed := 0.0
var _loading_done := false
var _loading_progress: Array = []


## Shows a full-screen loading card and streams the mission scene on a thread
## so the menu stays responsive.  The mission opens only after the scene is
## fully loaded (and the card has been visible for at least a moment).
func _begin_loading(path: String) -> void:
	if _loading_layer != null:
		return
	_loading_target = path
	_loading_elapsed = 0.0
	_loading_done = false
	Audio.stop_menu_music(0.6)
	var overlay: Dictionary = LoadingScreen.build(_selected_mode, _selected_mission,
			str(Global.menu_settings.get("selected_map", "steppe")),
			Global.get_difficulty_name(), true)
	_loading_layer = overlay["layer"] as CanvasLayer
	_loading_bar = overlay["bar"] as ProgressBar
	# Reparent to the tree root: the overlay must survive the scene swap, not
	# die with the menu (that was the "old map flashes for a second" bug).
	get_tree().root.add_child.call_deferred(_loading_layer)

	# Threaded loading of this project's scenes is not reliable: BigLevel has
	# cyclic scene dependencies that GDScript cannot resolve on a loader thread
	# (the level fails with "Could not preload res://Assets/water.gdshader").
	# Keep the persistent overlay on the tree root, switch synchronously, and
	# let the new level dismiss it after its terrain is ready — that removes
	# the old-map flash without breaking resource loads.
	_loading_bar.value = 8.0
	var tween := create_tween()
	tween.tween_property(_loading_bar, "value", 92.0, 0.6) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tween.finished
	await get_tree().process_frame
	_loading_done = true
	get_tree().change_scene_to_file(path)


func _process_loading(_delta: float) -> void:
	pass


func _exit_tree() -> void:
	if _model_holder != null and is_instance_valid(_model_holder):
		for c in _model_holder.get_children():
			if is_instance_valid(c):
				c.queue_free()
	_settings_overlay = null
	_loading_layer = null
	_loading_bar = null
