extends Node


signal hud_config_updated

## Realism presets.  Arcade is the default for a fresh install: a new pilot
## gets a calm, predictable aircraft for the first sorties.  Combat restores
## the full field model (gusts, EW domes, range/terrain link loss and pack sag).
const REALISM_ARCADE := "arcade"
const REALISM_COMBAT := "combat"
const REALISM_CUSTOM := "custom"


var game_settings_path := "%s/GameSettings.cfg" % Global.config_dir

var hud_config := {"fps": 20, "crosshair": false, "horizon": true, "ladder": false,
		"speed": true, "altitude": true, "heading": true, "sticks": true, "rpm": false,
		"osd": true, "fpv_rig": false, "weather": 0, "sim_thrust": true,
		"infinite_battery": true,
		# Simulator aids.  Kept in the same persisted dictionary so older
		# GameSettings.cfg files keep working (missing keys use these defaults).
		"link_limit": false, "wind_sim": false, "reb_zones": false,
		"realism_profile": REALISM_ARCADE,
		"angle_mode": true, "acro_mode": true,
		# ELRS WiFi / mobile input.  These keys must live in the default
		# dictionary, otherwise load_hud_config() would drop them when the
		# saved file is read back (it only copies known keys).
		"elrs_invert_roll": true,
		"elrs_arm_channel": 4,
		"elrs_mode_channel": 5,
		"elrs_video_channel": 6,
		"elrs_action_channels": {},
		"touch_invert_roll": false,
		"mobile_input_calibration": {},
		"mobile_pilot_name": "ПІЛОТ",
		"mobile_render_scale": 80,
		"mobile_stream_mode": false,
		"mobile_ghost": false,
		"mobile_racing_line": false,
		"mobile_distance_units": "km",
		"mobile_rate_profiles": {},
		"mobile_drone_tint": "ХАКІ",
		"mobile_drone_parts": {}}


func load_hud_config() -> void:
	var config := ConfigFile.new()
	var text := ""
	var err := config.load(game_settings_path)
	if err == OK:
		var hud_section := "hud_config"
		var has_reb_zones := false
		var has_profile := false
		if config.has_section(hud_section):
			for key in config.get_section_keys(hud_section):
				var value = config.get_value(hud_section, key)
				if key == "reb_zones":
					has_reb_zones = true
				if hud_config.has(key):
					if key == "fps" and (value is int or value is float):
						hud_config[key] = clamp(int(value), 5, 60)
					elif key == "weather" and (value is int or value is float):
						hud_config[key] = clampi(int(value), 0, 2)
					elif key == "realism_profile" and value is String:
						var profile_text := String(value).to_lower()
						if profile_text in [REALISM_ARCADE, REALISM_COMBAT, REALISM_CUSTOM]:
							hud_config[key] = profile_text
							has_profile = true
					elif key in ["elrs_arm_channel", "elrs_mode_channel", "elrs_video_channel"] \
							and (value is int or value is float):
						hud_config[key] = clampi(int(value), 0, 15)
					elif key in ["mobile_input_calibration", "elrs_action_channels",
							"mobile_rate_profiles", "mobile_drone_parts"] \
							and value is Dictionary:
						hud_config[key] = value
					elif key in ["mobile_pilot_name", "mobile_distance_units",
							"mobile_drone_tint"] and value is String:
						hud_config[key] = value
					elif key == "mobile_render_scale" and (value is int or value is float):
						hud_config[key] = clampi(int(value), 50, 100)
					elif key in ["mobile_stream_mode", "mobile_ghost", "mobile_racing_line"] \
							and value is bool:
						hud_config[key] = value
					elif value is bool:
						hud_config[key] = value
		hud_config["crosshair"] = false
		# Migration for settings files written before the realism profile
		# existed.  REB used to be bundled into "link_limit", so keep that
		# behaviour for an existing player, then infer the closest preset.
		if not has_reb_zones:
			hud_config["reb_zones"] = bool(hud_config.get("link_limit", false))
		if not has_profile:
			hud_config["realism_profile"] = infer_realism_profile()
		return
	elif err == ERR_PARSE_ERROR:
		Global.log_error(err, "Parse error while loading HUD config.")
		text = "Error parsing settings file, default settings will be loaded."
	elif err != ERR_FILE_NOT_FOUND:
		Global.log_error(err, "Error while loading HUD config.")
		text = "Error loading settings file, default settings will be loaded."
	if text != "":
		Global.log_error(err, text)
		var scene := get_tree().current_scene
		if scene is Control:
			Global.show_error_popup(scene, text)


func save_hud_config() -> void:
	var config := ConfigFile.new()
	var err := config.load(game_settings_path)
	if err == OK or err == ERR_FILE_NOT_FOUND or err == ERR_PARSE_ERROR:
		for key in hud_config.keys():
			config.set_value("hud_config", key, hud_config[key])
		var _discard = config.save(game_settings_path)
		emit_signal("hud_config_updated")
	else:
		Global.log_error(err, "Error while saving HUD config.")


## Derive the closest preset from the individual simulator aids.  Manual
## changes outside a preset are reported as "custom" so the menu can say so.
func infer_realism_profile() -> String:
	var wind := bool(hud_config.get("wind_sim", false))
	var reb := bool(hud_config.get("reb_zones", false))
	var link := bool(hud_config.get("link_limit", false))
	var infinite := bool(hud_config.get("infinite_battery", false))
	if not wind and not reb and not link and infinite:
		return REALISM_ARCADE
	if wind and reb and link and not infinite:
		return REALISM_COMBAT
	return REALISM_CUSTOM


func refresh_realism_profile() -> String:
	var profile := infer_realism_profile()
	hud_config["realism_profile"] = profile
	return profile


## Apply a preset atomically.  Saves (and emits hud_config_updated) unless the
## caller is batching several changes and wants to save once at the end.
func apply_realism_profile(profile: String, save := true) -> bool:
	var preset := profile.to_lower()
	if preset != REALISM_ARCADE and preset != REALISM_COMBAT:
		return false
	var realism := preset == REALISM_COMBAT
	hud_config["wind_sim"] = realism
	hud_config["reb_zones"] = realism
	hud_config["link_limit"] = realism
	hud_config["infinite_battery"] = not realism
	hud_config["realism_profile"] = preset
	if save:
		save_hud_config()
	else:
		emit_signal("hud_config_updated")
	return true
