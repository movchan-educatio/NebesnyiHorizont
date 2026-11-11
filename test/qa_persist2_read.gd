extends Node

## QA-only: second process. Reads the values written by qa_persist2_write
## BEFORE any screen/menu is opened.  This is exactly the on-launch path that
## was losing HUD/ELRS/calibration settings on iOS.

func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	var gs := get_node_or_null("/root/GameSettings")
	var elrs := get_node_or_null("/root/ElrsWifiInput")
	var controls := get_node_or_null("/root/Controls")
	var mobile := get_node_or_null("/root/MobileInput")
	var ok := true
	var fps: int = int(gs.hud_config.get("fps", 0))
	var scale: int = int(gs.hud_config.get("mobile_render_scale", 0))
	var pilot: String = str(gs.hud_config.get("mobile_pilot_name", ""))
	var cal: Dictionary = gs.hud_config.get("mobile_input_calibration", {})
	var deploy: int = int(elrs.get_action_channel("deploy_payload"))
	var pitch_ch: int = int(elrs.call("get_stick_channel", "pitch"))
	var pitch_inv: bool = bool(elrs.get("invert_pitch"))
	var palette: int = int(gs.hud_config.get("osd_palette", -1))
	var status_vis: bool = bool(gs.hud_config.get("status", true))
	var defaults_ver: int = int(gs.hud_config.get("elrs_action_defaults_version", 0))
	controls.call("load_input_map")
	var deadzone := float(controls.get("stick_deadzone"))
	var smoothing := float(controls.get("stick_smoothing"))
	var button_ok := false
	for event in InputMap.action_get_events("deploy_payload"):
		if event is InputEventJoypadButton and event.button_index == 7:
			button_ok = true
	ok = ok and fps == 37 and scale == 73 and pilot == "PERSIST-TEST"
	ok = ok and cal.has("sentinel")
	ok = ok and deploy == 9
	ok = ok and pitch_ch == 3 and pitch_inv
	ok = ok and palette == 2 and not status_vis and defaults_ver == 2
	ok = ok and absf(deadzone - 0.033) < 0.0001
	ok = ok and absf(smoothing - 0.11) < 0.0001
	ok = ok and button_ok
	print("[PERSIST2] fps=", fps, " scale=", scale, " pilot=", pilot,
			" cal=", cal.has("sentinel"), " deploy_ch=", deploy + 1,
			" pitch_ch=", pitch_ch + 1, " pitch_inv=", pitch_inv,
			" palette=", palette, " status=", status_vis, " ver=", defaults_ver,
			" deadzone=", deadzone, " smoothing=", smoothing,
			" gamepad_button7=", button_ok)
	print("[PERSIST2] ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
