extends Node

## QA-only: writes sentinel values into the real persistence files, then quits.
## Run this process first, then run qa_persist_read.tscn in a second process.

func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	var gs := get_node_or_null("/root/GameSettings")
	var elrs := get_node_or_null("/root/ElrsWifiInput")
	var controls := get_node_or_null("/root/Controls")
	var mobile := get_node_or_null("/root/MobileInput")
	if gs == null or elrs == null or controls == null or mobile == null:
		print("[PERSIST2] FAIL missing autoload")
		get_tree().quit(1)
		return
	gs.hud_config["fps"] = 37
	gs.hud_config["mobile_render_scale"] = 73
	gs.hud_config["mobile_pilot_name"] = "PERSIST-TEST"
	gs.hud_config["mobile_input_calibration"] = {
		"sentinel": {"roll": {"min": -0.88, "max": 0.77, "center": 0.01}}
	}
	gs.hud_config["osd_palette"] = 2
	gs.hud_config["status"] = false
	elrs.action_channels["deploy_payload"] = 9
	elrs.invert_pitch = true
	elrs.channel_map["pitch"] = 3
	elrs.arm_channel = 4
	# Force the no-controller section so the test is deterministic on a PC
	# that happens to have a radio plugged in.
	controls.active_controller_guid = ""
	controls.active_device = -1
	controls.default_controller_guid = ""
	controls.stick_deadzone = 0.033
	controls.stick_smoothing = 0.11
	controls.apply_action_binding("deploy_payload", ControllerAction.Type.BUTTON, 7)
	gs.save_hud_config()
	elrs.save_settings()
	controls.save_bindings()
	print("[PERSIST2] wrote settings")
	get_tree().quit(0)
