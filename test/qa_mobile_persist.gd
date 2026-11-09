## QA-only: verifies that the ELRS/touch keys added to hud_config survive a
## save/load round-trip.  Uses a temporary settings file, never the real one.
extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().create_timer(0.3).timeout
	var settings := get_node_or_null("/root/GameSettings")
	if settings == null:
		print("[PERSISTQA] FAIL: GameSettings missing")
		get_tree().quit()
		return
	var real_path: String = settings.get("game_settings_path")
	settings.set("game_settings_path", "user://qa_mobile_settings.cfg")
	settings.set("hud_config", {
		"fps": 20, "crosshair": false, "horizon": true, "ladder": false,
		"speed": true, "altitude": true, "heading": true, "sticks": true,
		"rpm": false, "osd": true, "fpv_rig": false, "weather": 0,
		"sim_thrust": true, "infinite_battery": true, "link_limit": false,
		"wind_sim": false, "reb_zones": false, "realism_profile": "arcade",
		"angle_mode": true, "acro_mode": true,
		"elrs_invert_roll": true, "elrs_arm_channel": 4,
		"elrs_mode_channel": 5, "elrs_video_channel": 6,
		"elrs_action_channels": {},
		"touch_invert_roll": false, "mobile_input_calibration": {},
	})
	var calibration := {"elrs": {"roll": {"min": -0.9, "max": 0.9, "center": 0.0}}}
	var actions := {"toggle_arm": 7, "deploy_payload": 11}
	var hud: Dictionary = settings.get("hud_config")
	hud["elrs_invert_roll"] = false
	hud["elrs_arm_channel"] = 7
	hud["elrs_mode_channel"] = 8
	hud["elrs_video_channel"] = 9
	hud["elrs_action_channels"] = actions
	hud["touch_invert_roll"] = true
	hud["mobile_input_calibration"] = calibration
	settings.call("save_hud_config")

	hud["elrs_invert_roll"] = true
	hud["elrs_arm_channel"] = 4
	hud["elrs_mode_channel"] = 5
	hud["elrs_video_channel"] = 6
	hud["elrs_action_channels"] = {}
	hud["touch_invert_roll"] = false
	hud["mobile_input_calibration"] = {}
	settings.call("load_hud_config")
	hud = settings.get("hud_config")

	var ok := true
	ok = ok and not bool(hud.get("elrs_invert_roll", true))
	ok = ok and int(hud.get("elrs_arm_channel", 0)) == 7
	ok = ok and int(hud.get("elrs_mode_channel", 0)) == 8
	ok = ok and int(hud.get("elrs_video_channel", 0)) == 9
	ok = ok and bool(hud.get("touch_invert_roll", false))
	var loaded_cal: Dictionary = hud.get("mobile_input_calibration", {})
	ok = ok and not loaded_cal.is_empty()
	var loaded_actions: Dictionary = hud.get("elrs_action_channels", {})
	ok = ok and int(loaded_actions.get("toggle_arm", -1)) == 7
	ok = ok and int(loaded_actions.get("deploy_payload", -1)) == 11
	print("[PERSISTQA] invert=", hud.get("elrs_invert_roll"),
			" arm=", hud.get("elrs_arm_channel"),
			" mode=", hud.get("elrs_mode_channel"),
			" video=", hud.get("elrs_video_channel"),
			" actions=", loaded_actions,
			" touch=", hud.get("touch_invert_roll"),
			" cal=", loaded_cal)
	print("[PERSISTQA] ", "PASS" if ok else "FAIL")

	settings.set("game_settings_path", real_path)
	var absolute := ProjectSettings.globalize_path("user://qa_mobile_settings.cfg")
	if FileAccess.file_exists("user://qa_mobile_settings.cfg"):
		DirAccess.remove_absolute(absolute)
	# Restore the real settings in memory; do not overwrite the player file.
	settings.call("load_hud_config")
	get_tree().quit()
