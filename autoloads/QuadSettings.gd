extends Node


signal settings_updated


func _ready() -> void:
	# Load the pilot's saved flight feel at startup so every menu and the live
	# drone see the same rates/expo/level values from the first frame on.
	load_quad_settings()


var quad_settings_path := "%s/Quad.cfg" % Global.config_dir

var angle := -5
var dry_weight := 0.55
var battery_weight := 0.18
var payload_weight := 0.0

var rate_pitch := 667
var rate_roll := 667
var rate_yaw := 667
## 0 = Actual Rates, 1 = Betaflight, 2 = Quick (matches ControlProfile.RateType).
var rate_type: int = 0
var expo_pitch := 0.2
var expo_roll := 0.2
var expo_yaw := 0.2

## LEVEL-mode attitude hold. Bank limit is the maximum lean in degrees; the
## angle/rate gains turn a stick deflection into a turn rate, and the rate
## feedback is what damps the old "seesaw" oscillation.
var level_bank := 28.0
var level_angle_gain := 2.2
var level_rate_gain := 0.22
var level_rate_limit := 3.5

## The name of the last flight-feel preset, "custom" after a slider edit.
var flight_preset := "stable"
## When true, the pilot's rates/expo take priority over a drone preset's own
## rates. This survives menu navigation and drone selection; only an explicit
## Reset Rates clears it, so a saved custom feel is never lost accidentally.
var custom_rates := false

const FLIGHT_PRESETS := [
	{
		"id": "stable", "name": "СТАБІЛЬНИЙ",
		"desc": "Плавний баланс контролю й тяги — оптимальний за замовчуванням",
		"rate": 450, "expo": 0.30, "bank": 28.0,
		"angle_gain": 2.2, "rate_gain": 0.22, "rate_limit": 3.5,
	},
	{
		"id": "sport", "name": "СПОРТ",
		"desc": "Звичний баланс швидкості й контролю",
		"rate": 667, "expo": 0.20, "bank": 30.0,
		"angle_gain": 2.2, "rate_gain": 0.20, "rate_limit": 4.0,
	},
	{
		"id": "race", "name": "ГОНКА",
		"desc": "Швидкі оберти, великий нахил, мінімум експо",
		"rate": 900, "expo": 0.12, "bank": 35.0,
		"angle_gain": 2.5, "rate_gain": 0.18, "rate_limit": 5.0,
	},
	{
		"id": "cinematic", "name": "КІНО",
		"desc": "Дуже м'які реакції для плавних прольотів",
		"rate": 300, "expo": 0.45, "bank": 15.0,
		"angle_gain": 1.2, "rate_gain": 0.30, "rate_limit": 2.0,
	},
]


func flight_preset_index(id: String = flight_preset) -> int:
	for i in range(FLIGHT_PRESETS.size()):
		if str(FLIGHT_PRESETS[i]["id"]) == id:
			return i
	return -1


func apply_flight_preset(id: String) -> void:
	var index := flight_preset_index(id)
	if index < 0:
		return
	var p: Dictionary = FLIGHT_PRESETS[index]
	rate_pitch = int(p["rate"])
	rate_roll = int(p["rate"])
	rate_yaw = int(p["rate"])
	expo_pitch = float(p["expo"])
	expo_roll = float(p["expo"])
	expo_yaw = float(p["expo"])
	level_bank = float(p["bank"])
	level_angle_gain = float(p["angle_gain"])
	level_rate_gain = float(p["rate_gain"])
	level_rate_limit = float(p["rate_limit"])
	flight_preset = id
	custom_rates = true


func load_quad_settings() -> void:
	var config := ConfigFile.new()
	var text := ""
	var err := config.load(quad_settings_path)
	if err == OK:
		if config.has_section_key("quad", "angle"):
			angle = int(clamp(config.get_value("quad", "angle"), -20, 80))
		if config.has_section_key("quad", "dry_weight"):
			dry_weight = clamp(config.get_value("quad", "dry_weight"), 0.1, 40.0)
		if config.has_section_key("quad", "battery_weight"):
			battery_weight = clamp(config.get_value("quad", "battery_weight"), 0.05, 20.0)
		if config.has_section_key("quad", "payload_weight"):
			payload_weight = clamp(config.get_value("quad", "payload_weight"), 0.0, 25.0)
		if config.has_section_key("rates", "pitch"):
			rate_pitch = int(clamp(config.get_value("rates", "pitch"), 90, 1800))
		if config.has_section_key("rates", "roll"):
			rate_roll = int(clamp(config.get_value("rates", "roll"), 90, 1800))
		if config.has_section_key("rates", "yaw"):
			rate_yaw = int(clamp(config.get_value("rates", "yaw"), 90, 1800))
		if config.has_section_key("rates", "rate_type"):
			rate_type = clampi(int(config.get_value("rates", "rate_type")), 0, 2)
		if config.has_section_key("expos", "pitch"):
			expo_pitch = clamp(config.get_value("expos", "pitch"), 0.0, 1.0)
		if config.has_section_key("expos", "roll"):
			expo_roll = clamp(config.get_value("expos", "roll"), 0.0, 1.0)
		if config.has_section_key("expos", "yaw"):
			expo_yaw = clamp(config.get_value("expos", "yaw"), 0.0, 1.0)
		if config.has_section_key("level", "bank"):
			level_bank = clamp(config.get_value("level", "bank"), 5.0, 60.0)
		if config.has_section_key("level", "angle_gain"):
			level_angle_gain = clamp(config.get_value("level", "angle_gain"), 0.5, 12.0)
		if config.has_section_key("level", "rate_gain"):
			level_rate_gain = clamp(config.get_value("level", "rate_gain"), 0.01, 0.3)
		if config.has_section_key("level", "rate_limit"):
			level_rate_limit = clamp(config.get_value("level", "rate_limit"), 1.0, 12.0)
		if config.has_section_key("level", "preset"):
			flight_preset = str(config.get_value("level", "preset"))
		if config.has_section_key("level", "custom_rates"):
			custom_rates = bool(config.get_value("level", "custom_rates"))
		if flight_preset == "stable" and not custom_rates and is_equal_approx(level_bank, 20.0):
			apply_flight_preset("stable")
			custom_rates = false
		return
	elif err == ERR_PARSE_ERROR:
		Global.log_error(err, "Parse error while loading quad settings.")
		text = "Parse error while loading settings. Default settings will be loaded."
	elif err != ERR_FILE_NOT_FOUND:
		Global.log_error(err, "Error loading quad settings.")
		text = "Error loading settings. Default settings will be loaded."
	if text != "":
		Global.log_error(err, text)
		var scene := get_tree().current_scene
		if scene is Control:
			Global.show_error_popup(scene, text)


func save_quad_settings() -> void:
	var config := ConfigFile.new()
	var err := config.load(quad_settings_path)
	if err == OK or err == ERR_FILE_NOT_FOUND or err == ERR_PARSE_ERROR:
		config.set_value("quad", "angle", angle)
		config.set_value("quad", "dry_weight", dry_weight)
		config.set_value("quad", "battery_weight", battery_weight)
		config.set_value("quad", "payload_weight", payload_weight)
		config.set_value("rates", "pitch", rate_pitch)
		config.set_value("rates", "roll", rate_roll)
		config.set_value("rates", "yaw", rate_yaw)
		config.set_value("rates", "rate_type", clampi(rate_type, 0, 2))
		config.set_value("expos", "pitch", expo_pitch)
		config.set_value("expos", "roll", expo_roll)
		config.set_value("expos", "yaw", expo_yaw)
		config.set_value("level", "bank", level_bank)
		config.set_value("level", "angle_gain", level_angle_gain)
		config.set_value("level", "rate_gain", level_rate_gain)
		config.set_value("level", "rate_limit", level_rate_limit)
		config.set_value("level", "preset", flight_preset)
		config.set_value("level", "custom_rates", custom_rates)
		var _discard = config.save(quad_settings_path)
	else:
		Global.log_error(err, "Error while saving quad settings.")
	emit_signal("settings_updated")


func reset_quad() -> void:
	angle = 30
	dry_weight = 0.55
	battery_weight = 0.18
	payload_weight = 0.0


func reset_rates() -> void:
	# Only an explicit "Reset Rates" clears the pilot's custom-rate flag.
	# Prefer the active drone's factory rate when the catalogue provides one;
	# otherwise fall back to the neutral sport preset.
	var p: Dictionary = DroneCatalog.preset(Global.drone_preset)
	if not p.is_empty() and p.has("rate"):
		rate_pitch = int(p["rate"])
		rate_roll = int(p["rate"])
		rate_yaw = int(p["rate"])
	else:
		apply_flight_preset("sport")  # sets custom_rates = true, undone below
	custom_rates = false
