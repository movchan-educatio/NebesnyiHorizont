## QA-only: drives the ELRS calibration wizard with synthetic channel frames.
## Enabled by CALIBRATION_ELRS_QA=1.  Saves to a temporary settings file and
## restores the player's real configuration before quitting.
extends Node

var _cal: Node = null
var _wifi: Node = null
var _mobile: Node = null
var _settings: Node = null
var _saved_hud: Dictionary = {}
var _saved_calibration: Dictionary = {}
var _real_path := ""


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().create_timer(2.0).timeout
	_cal = get_tree().current_scene
	_wifi = get_node_or_null("/root/ElrsWifiInput")
	_mobile = get_node_or_null("/root/MobileInput")
	_settings = get_node_or_null("/root/GameSettings")
	if _cal == null or _wifi == null or _mobile == null or _settings == null \
			or not _cal.has_method("reset_calibration"):
		print("[CALELRSQA] FAIL: missing nodes")
		get_tree().quit()
		return
	_saved_hud = (_settings.get("hud_config") as Dictionary).duplicate(true)
	_saved_calibration = (_mobile.get("calibration") as Dictionary).duplicate(true)
	_real_path = str(_settings.get("game_settings_path"))
	_settings.set("game_settings_path", "user://qa_cal_elrs.cfg")

	_wifi.set("valid", true)
	_wifi.set("module_ip", "127.0.0.1")
	_set_channels(0, 16383, 16383, 16383)
	_cal.call("reset_calibration")

	# Step 0 requires all four axes to move; step 1 requires the self-centring
	# axes released.  ELRS shares the virtual input path, so demonstrate both.
	_set_channels(32767, 0, 0, 0)
	await get_tree().create_timer(0.9).timeout
	_set_channels(0, 16383, 16383, 16383)
	await get_tree().create_timer(1.1).timeout

	# Hold the value each step asks for until the wizard advances.  This is
	# robust against the exact frame timing of the centre/extreme detectors.
	var last_step := -999
	var deadline := Time.get_ticks_msec() + 30000
	while is_instance_valid(_cal) and Time.get_ticks_msec() < deadline:
		var step := int(_cal.get("calibration_step"))
		if bool(_cal.get("calibration_finished")):
			break
		if step != last_step:
			print("[CALELRSQA] step=", step)
			last_step = step
		match step:
			2:
				_set_channels(0, 16383, 16383, 16383)
			3:
				_set_channels(32767, 16383, 16383, 16383)
			4:
				_set_channels(16383, 16383, 16383, 16383)
			5:
				_set_channels(16383, 0, 16383, 16383)
			6:
				_set_channels(16383, 32767, 16383, 16383)
			7:
				_set_channels(16383, 16383, 16383, 16383)
			8:
				_set_channels(16383, 16383, 0, 16383)
			9:
				_set_channels(16383, 16383, 32767, 16383)
			10:
				_set_channels(16383, 16383, 16383, 16383)
			11:
				_set_channels(16383, 16383, 16383, 0)
			12:
				_set_channels(16383, 16383, 16383, 32767)
			13:
				_set_channels(16383, 16383, 16383, 16383)
		await get_tree().create_timer(0.1).timeout

	await get_tree().create_timer(0.4).timeout
	var cal_table: Dictionary = _mobile.get("calibration")
	var has_elrs := cal_table.has("elrs") and not (cal_table["elrs"] as Dictionary).is_empty()
	print("[CALELRSQA] table=", cal_table)
	print("[CALELRSQA] ", "PASS" if has_elrs else "FAIL")

	# Restore the real player settings; the temp file is disposable.
	_settings.set("hud_config", _saved_hud)
	_mobile.set("calibration", _saved_calibration)
	_settings.set("game_settings_path", _real_path)
	var absolute := ProjectSettings.globalize_path("user://qa_cal_elrs.cfg")
	if FileAccess.file_exists("user://qa_cal_elrs.cfg"):
		DirAccess.remove_absolute(absolute)
	get_tree().quit()


func _set_channels(throttle: float, yaw: float, pitch: float, roll: float) -> void:
	var channels := PackedFloat32Array()
	channels.resize(16)
	channels.fill(16383.0)
	channels[0] = roll
	channels[1] = pitch
	channels[2] = throttle
	channels[3] = yaw
	_wifi.set("channels", channels)
	_wifi.set("valid", true)
	_wifi.set("_last_frame_ms", Time.get_ticks_msec())
