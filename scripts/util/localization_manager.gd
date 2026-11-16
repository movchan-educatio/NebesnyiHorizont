## Centralized Localization (UA / EN) & OSD Color Accessibility Manager.
class_name Loc
extends Node

enum Language { UA = 0, EN = 1 }

enum OsdPalette {
	DEFAULT = 0,       # Classic Tactical Neon Green / Amber
	HIGH_CONTRAST = 1, # Ultra Crisp White / Solid Black (low vision accessibility)
	CYAN_AMBER = 2,    # Colorblind Friendly (Deuteranopia / Protanopia / Tritanopia)
	PHOSPHOR_GREEN = 3,# Monochrome Phosphor Tactical NVG Green
	RED_NIGHT = 4      # Aviation Night-Vision Safe Crimson Red
}

static var _current_lang: Language = Language.UA
static var _current_palette: OsdPalette = OsdPalette.DEFAULT
static var _initialized: bool = false

const DICT: Dictionary = {
	# Menu & Navigation
	"MENU_TITLE": {Language.UA: "НЕБЕСНИЙ ГОРИЗОНТ · FPV", Language.EN: "HEAVENLY HORIZON · FPV"},
	"BTN_LAUNCH": {Language.UA: "ПОЧАТИ ВИЛІТ", Language.EN: "START SORTIE"},
	"BTN_BRIEFING": {Language.UA: "БРИФІНГ", Language.EN: "BRIEFING"},
	"BTN_TUTORIAL": {Language.UA: "ТУТОРІАЛ", Language.EN: "TUTORIAL"},
	"BTN_TRAINING": {Language.UA: "ТРЕНУВАННЯ", Language.EN: "TRAINING"},
	"BTN_COMBAT": {Language.UA: "БОЙОВИЙ РЕЖИМ", Language.EN: "COMBAT"},
	"BTN_SETTINGS": {Language.UA: "ПАРАМЕТРИ", Language.EN: "SETTINGS"},
	"BTN_HANGAR": {Language.UA: "АНГАР", Language.EN: "HANGAR"},
	"BTN_HELP": {Language.UA: "ДОВІДКА", Language.EN: "HELP / CONTROLS"},
	"BTN_BACK": {Language.UA: "ПОВЕРНУТИСЯ", Language.EN: "BACK"},
	"BTN_RETRY": {Language.UA: "ПОВТОРИТИ", Language.EN: "RETRY"},
	"BTN_NEXT": {Language.UA: "НАСТУПНА МІСІЯ", Language.EN: "NEXT MISSION"},
	"BTN_QUIT": {Language.UA: "ВИХІД", Language.EN: "EXIT"},
	"BTN_LANG_TOGGLE": {Language.UA: "МОВА: UA / EN", Language.EN: "LANG: EN / UA"},
	"BTN_QUICK_TUTORIAL": {Language.UA: "▶ ШВИДКИЙ СТАРТ: ТУТОРІАЛ (60с)", Language.EN: "▶ QUICK START: TUTORIAL (60s)"},

	# Modes & Headers
	"HDR_MODES": {Language.UA: "РЕЖИМИ ВИЛЬОТУ", Language.EN: "FLIGHT MODES"},
	"HDR_MISSIONS": {Language.UA: "ТАКТИЧНІ ЗАВДАННЯ", Language.EN: "TACTICAL MISSIONS"},
	"HDR_DIFFICULTY": {Language.UA: "РІВЕНЬ СКЛАДНОСТІ", Language.EN: "DIFFICULTY STANDARD"},
	"DIFF_RECRUIT": {Language.UA: "РЕКРУТ", Language.EN: "RECRUIT"},
	"DIFF_OPERATOR": {Language.UA: "ОПЕРАТОР", Language.EN: "OPERATOR"},
	"DIFF_ACE": {Language.UA: "АС", Language.EN: "ACE"},

	# Daily Challenge, Ratings & Game Center
	"DAILY_HDR": {Language.UA: "ЩОДЕННИЙ ВИКЛИК", Language.EN: "DAILY CHALLENGE"},
	"DAILY_DONE": {Language.UA: "ВИКОНАНО ✓", Language.EN: "COMPLETED ✓"},
	"DAILY_PLAY": {Language.UA: "ПРИЙНЯТИ ВИКЛИК", Language.EN: "ACCEPT CHALLENGE"},
	"RANK_LABEL": {Language.UA: "РАНГ", Language.EN: "RANK"},
	"BEST_TIME": {Language.UA: "КРАЩИЙ ЧАС", Language.EN: "BEST TIME"},
	"GC_HDR": {Language.UA: "ТАБЛИЦЯ РЕКОРДІВ / СТАТИСТИКА", Language.EN: "PILOT RECORDS & STATS"},
	"GC_BTN": {Language.UA: "ВІДКРИТИ РЕКОРДИ", Language.EN: "VIEW RECORDS"},

	# Telemetry & HUD
	"HUD_ARMED": {Language.UA: "ДВИГУНИ УВІМКНЕНО", Language.EN: "ARMED / MOTORS ON"},
	"HUD_DISARMED": {Language.UA: "ДВИГУНИ ВИМКНЕНО", Language.EN: "DISARMED"},
	"HUD_TIME": {Language.UA: "ЧАС", Language.EN: "TIME"},
	"HUD_SCORE": {Language.UA: "ОЧКИ", Language.EN: "SCORE"},
	"HUD_AMMO": {Language.UA: "ПІДВІС", Language.EN: "PAYLOAD"},
	"HUD_SPEED": {Language.UA: "ШВИДКІСТЬ", Language.EN: "SPEED"},
	"HUD_ALTITUDE": {Language.UA: "ВИСОТА", Language.EN: "ALTITUDE"},
	"HUD_BATTERY": {Language.UA: "БАТАРЕЯ", Language.EN: "BATTERY"},
	"HUD_READY": {Language.UA: "ГОТОВИЙ ДО СТАРТУ", Language.EN: "READY FOR TAKEOFF"},
	"HUD_GHOST_ON": {Language.UA: "ПРИВИД АКТИВНИЙ", Language.EN: "GHOST ACTIVE"},

	# Kill-Cam & Radio
	"KILLCAM_TITLE": {Language.UA: "ПОВТОР УРАЖЕННЯ ЦІЛІ", Language.EN: "TARGET IMPACT REPLAY"},
	"RADIO_LINK": {Language.UA: "РАДІОЗВ'ЯЗОК", Language.EN: "RADIO COMMS"},
	"RADIO_CRSF": {Language.UA: "ТЕЛЕМЕТРІЯ ELRS / CRSF", Language.EN: "ELRS / CRSF TELEMETRY"},

	# Calibration & Audio Sub-Buses
	"CAL_TITLE": {Language.UA: "КАЛІБРУВАННЯ ПУЛЬТА ТА КРИВІ", Language.EN: "CONTROLLER CALIBRATION & CURVES"},
	"CAL_PRESETS": {Language.UA: "ШВИДКІ ПРЕСЕТИ ПУЛЬТА", Language.EN: "QUICK CONTROLLER PRESETS"},
	"CAL_EXPO": {Language.UA: "Експонента (Expo)", Language.EN: "Stick Expo"},
	"CAL_SUPER_RATE": {Language.UA: "Суперрейт (SuperRate)", Language.EN: "SuperRate"},
	"CAL_DEADZONE": {Language.UA: "Мертва зона (Deadzone)", Language.EN: "Deadzone"},
	"BUS_ENGINE": {Language.UA: "Двигуни та гвинти", Language.EN: "Motors & Props"},
	"BUS_WIND": {Language.UA: "Вітер та аеродинаміка", Language.EN: "Wind & Airflow"},
	"BUS_COMBAT": {Language.UA: "Влучання та ефекти", Language.EN: "Impacts & Effects"},
	"BUS_RADIO": {Language.UA: "Радіоефір", Language.EN: "Radio Comms"},
	"BUS_WARNING": {Language.UA: "Сигнали тривоги OSD", Language.EN: "OSD Warnings"},

	# Optics & Weather
	"VISION_NORMAL": {Language.UA: "ОПТИКА: ДЕННА (RGB)", Language.EN: "OPTICS: DAYLIGHT (RGB)"},
	"VISION_NVG": {Language.UA: "ОПТИКА: НІЧНЕ БАЧЕННЯ (NVG)", Language.EN: "OPTICS: NIGHT VISION (NVG)"},
	"VISION_WHITE_HOT": {Language.UA: "ТЕПЛОВІЗОР: WHITE-HOT", Language.EN: "THERMAL: WHITE-HOT (FLIR)"},
	"VISION_BLACK_HOT": {Language.UA: "ТЕПЛОВІЗОР: BLACK-HOT", Language.EN: "THERMAL: BLACK-HOT (FLIR)"},

	"WEATHER_CLEAR": {Language.UA: "ПОГОДА: ЯСНО", Language.EN: "WEATHER: CLEAR"},
	"WEATHER_RAIN": {Language.UA: "ПОГОДА: ДОЩ", Language.EN: "WEATHER: RAIN"},
	"WEATHER_STORM": {Language.UA: "ПОГОДА: ГРОЗА ТА БЛИСКАВКА", Language.EN: "WEATHER: THUNDERSTORM"},
	"WEATHER_NIGHT": {Language.UA: "ЧАС ДОБИ: НІЧ", Language.EN: "TIME: NIGHT FLIGHT"},
	"WEATHER_DUST": {Language.UA: "ПОГОДА: ПИЛ / ТУМАН", Language.EN: "WEATHER: DUST / FOG"},

	# Flight School
	"FS_TITLE": {Language.UA: "ТУТОРІАЛ: ШКОЛА ПІЛОТА FPV", Language.EN: "TUTORIAL: FPV PILOT SCHOOL"},
	"FS_GOLDEN_CERT": {Language.UA: "СЕРТИФІКАТ ОПЕРАТОРА FPV", Language.EN: "CERTIFIED FPV PILOT"},
	"FS_COMPLETE_TITLE": {Language.UA: "ТУТОРІАЛ ЗАВЕРШЕНО!", Language.EN: "TUTORIAL COMPLETED!"},
	"FS_STEP_ARM": {Language.UA: "МОДУЛЬ 0: АРМУВАННЯ ДВИГУНІВ ТА ЗЛІТ", Language.EN: "MODULE 0: ENGINE ARM & TAKEOFF"},
	"FS_STEP_HOVER": {Language.UA: "МОДУЛЬ 1: УТРИМАННЯ ВИСОТИ 2-4м", Language.EN: "MODULE 1: ALTITUDE HOLD 2-4m"},
	"FS_STEP_PITCH": {Language.UA: "МОДУЛЬ 2: ТАНГАЖ ТА ВОРОТА 1", Language.EN: "MODULE 2: PITCH & GATE 1"},
	"FS_STEP_TURN": {Language.UA: "МОДУЛЬ 3: КООРДИНОВАНИЙ ВІРАЖ", Language.EN: "MODULE 3: COORDINATED TURN"},
	"FS_STEP_FLARE": {Language.UA: "МОДУЛЬ 4: ЕКСТРЕНЕ ГАЛЬМУВАННЯ", Language.EN: "MODULE 4: EMERGENCY BRAKE (FLARE)"},
	"FS_STEP_LAND": {Language.UA: "МОДУЛЬ 5: ПОСАДКА НА МАЙДАНЧИК", Language.EN: "MODULE 5: TOUCHDOWN & DISARM"},

	# Error Assistant Toasts
	"ERR_WHISKEY": {
		Language.UA: "⚠ ПЕРЕГАЗОВКА (WHISKEY THROTTLE)! Скиньте газ до 40% та вирівняйте дрон.",
		Language.EN: "⚠ WHISKEY THROTTLE! Lower throttle to 40% and level your horizon."
	},
	"ERR_HORIZON": {
		Language.UA: "⚠ ВТРАТА ГОРИЗОНТУ! Дрон перевернутий. Вирівняйте крен у протилежний бік.",
		Language.EN: "⚠ INVERTED DISORIENTATION! Drone is upside down. Roll counter-direction."
	},
	"ERR_VRS": {
		Language.UA: "⚠ ЗВАЛЮВАННЯ (ВИХРОВЕ КІЛЬЦЕ / VRS)! Не спускайтесь вертикально у власному потоці — дайте крок уперед.",
		Language.EN: "⚠ VORTEX RING STATE (VRS)! Avoid purely vertical descent into rotor wash - pitch forward."
	},
	"ERR_SKID": {
		Language.UA: "💡 НЕКООРДИНОВАНИЙ БІЧНИЙ ЗНОС! Додайте крен (Roll) разом із рисканням (Yaw) для плавного віражу.",
		Language.EN: "💡 UNCOORDINATED YAW SKID! Add Roll banking together with Yaw for a smooth carve."
	}
}


static func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	var env_lang := OS.get_environment("DRONE_LANG").strip_edges().to_lower()
	var saved_lang := str(GameSettings.hud_config.get("language", "ua")).strip_edges().to_lower()
	if env_lang == "en" or (env_lang.is_empty() and saved_lang == "en"):
		_current_lang = Language.EN
	else:
		_current_lang = Language.UA
	GameSettings.hud_config["language"] = "en" if _current_lang == Language.EN else "ua"
	var saved_pal := int(GameSettings.hud_config.get("osd_palette", 0))
	_current_palette = clampi(saved_pal, 0, 4) as OsdPalette


static func get_language() -> Language:
	if not _initialized:
		initialize()
	return _current_lang


static func set_language(p_lang: Language, save: bool = true) -> void:
	_initialized = true
	_current_lang = Language.EN if p_lang == Language.EN else Language.UA
	GameSettings.hud_config["language"] = "en" if _current_lang == Language.EN else "ua"
	if save and Engine.get_main_loop() != null:
		GameSettings.save_hud_config()


static func toggle_language() -> Language:
	var next := Language.EN if get_language() == Language.UA else Language.UA
	set_language(next, true)
	return next


static func get_language_code() -> String:
	return "EN" if get_language() == Language.EN else "UA"


static func t(key: String) -> String:
	if not _initialized:
		initialize()
	var d = DICT.get(key)
	if d is Dictionary:
		return str(d.get(_current_lang, d.get(Language.UA, key)))
	return key


static func loc(key: String) -> String:
	return t(key)


static func get_palette() -> OsdPalette:
	if not _initialized:
		initialize()
	return _current_palette


static func set_palette(p_pal: OsdPalette) -> void:
	_current_palette = p_pal
	GameSettings.hud_config["osd_palette"] = int(_current_palette)
	GameSettings.save_hud_config()


static func cycle_palette() -> OsdPalette:
	var next_p := int((int(_current_palette) + 1) % 5) as OsdPalette
	set_palette(next_p)
	return next_p


static func get_palette_name(pal: OsdPalette = _current_palette) -> String:
	match pal:
		OsdPalette.HIGH_CONTRAST:
			return "КОНТРАСТ (B/W)" if _current_lang == Language.UA else "HIGH CONTRAST (B/W)"
		OsdPalette.CYAN_AMBER:
			return "ДАЛЬТОНІЗМ (CYAN/AMBER)" if _current_lang == Language.UA else "COLORBLIND (CYAN/AMBER)"
		OsdPalette.PHOSPHOR_GREEN:
			return "ФОСФОР (NVG GREEN)" if _current_lang == Language.UA else "PHOSPHOR (NVG GREEN)"
		OsdPalette.RED_NIGHT:
			return "НІЧНИЙ ЧЕРВОНИЙ" if _current_lang == Language.UA else "NIGHT CRIMSON"
		_:
			return "СТАНДАРТ ЗСУ" if _current_lang == Language.UA else "STANDARD TACTICAL"


static func get_palette_colors(pal: OsdPalette = _current_palette) -> Dictionary:
	match pal:
		OsdPalette.HIGH_CONTRAST:
			return {
				"primary": Color(1.0, 1.0, 1.0, 1.0),
				"accent": Color(1.0, 1.0, 1.0, 1.0),
				"warning": Color(1.0, 0.9, 0.2, 1.0),
				"danger": Color(1.0, 0.1, 0.1, 1.0),
				"text": Color(1.0, 1.0, 1.0, 1.0),
				"bg": Color(0.0, 0.0, 0.0, 0.85),
				"border": Color(1.0, 1.0, 1.0, 1.0)
			}
		OsdPalette.CYAN_AMBER:
			return {
				"primary": Color(0.15, 0.85, 0.95, 0.95),
				"accent": Color(0.95, 0.70, 0.15, 0.95),
				"warning": Color(0.95, 0.70, 0.15, 0.95),
				"danger": Color(0.95, 0.35, 0.15, 1.0),
				"text": Color(0.90, 0.96, 1.0, 0.95),
				"bg": Color(0.04, 0.08, 0.12, 0.75),
				"border": Color(0.20, 0.65, 0.85, 0.8)
			}
		OsdPalette.PHOSPHOR_GREEN:
			return {
				"primary": Color(0.25, 0.98, 0.35, 0.95),
				"accent": Color(0.40, 1.00, 0.50, 0.95),
				"warning": Color(0.70, 0.95, 0.30, 0.95),
				"danger": Color(0.95, 0.85, 0.25, 1.0),
				"text": Color(0.35, 0.98, 0.45, 0.95),
				"bg": Color(0.02, 0.08, 0.03, 0.80),
				"border": Color(0.25, 0.80, 0.30, 0.8)
			}
		OsdPalette.RED_NIGHT:
			return {
				"primary": Color(0.98, 0.25, 0.25, 0.95),
				"accent": Color(1.00, 0.45, 0.35, 0.95),
				"warning": Color(0.98, 0.65, 0.20, 0.95),
				"danger": Color(1.00, 0.15, 0.15, 1.0),
				"text": Color(0.98, 0.35, 0.35, 0.95),
				"bg": Color(0.08, 0.02, 0.02, 0.80),
				"border": Color(0.80, 0.20, 0.20, 0.8)
			}
		_: # DEFAULT
			return {
				"primary": Color(0.92, 0.69, 0.21, 0.95), # WARN_AMBER
				"accent": Color(0.35, 0.85, 0.40, 0.95),  # ACCENT Green
				"warning": Color(0.95, 0.70, 0.20, 0.95),
				"danger": Color(0.95, 0.28, 0.22, 1.0),
				"text": Color(0.92, 0.96, 0.94, 0.95),
				"bg": Color(0.08, 0.11, 0.09, 0.75),
				"border": Color(0.24, 0.38, 0.20, 0.8)
			}
