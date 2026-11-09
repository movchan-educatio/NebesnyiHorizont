## QA-only: drives the touch calibration wizard through all 14 steps without
## a human finger.  Enabled by CALIBRATION_QA=1 together with TOUCH_CONTROLS=1.
extends Node

var _pad: Node = null
var _cal: Node = null


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().create_timer(2.6).timeout
	_pad = get_node_or_null("/root/TouchControls")
	_cal = get_tree().current_scene
	if _pad == null or _cal == null or not _cal.has_method("reset_calibration"):
		print("[CALQA] FAIL: missing touch pad or calibration screen")
		get_tree().quit()
		return
	_pad.call("set_menu_preview", true)

	# Step 0 now needs real movement on all four axes; step 1 needs the
	# self-centring axes released.  Demonstrate both before the main sequence.
	_set_sticks(1.0, -1.0, -1.0, -1.0)
	await get_tree().create_timer(0.7).timeout
	_set_sticks(0.0, 0.0, 0.0, 0.0)
	await get_tree().create_timer(1.1).timeout
	print("[CALQA] after axis sweep/centre step=", int(_cal.get("calibration_step")))

	var sequence := [
		[0.0, 0.0, 0.0, 0.0, 0.8],   # 2 throttle down
		[1.0, 0.0, 0.0, 0.0, 0.8],   # 3 throttle up
		[0.5, 0.0, 0.0, 0.0, 1.0],   # 4 throttle centre
		[0.5, -1.0, 0.0, 0.0, 0.8],  # 5 yaw left
		[0.5, 1.0, 0.0, 0.0, 0.8],   # 6 yaw right
		[0.5, 0.0, 0.0, 0.0, 0.9],   # 7 yaw centre
		[0.5, 0.0, -1.0, 0.0, 0.8],  # 8 pitch away
		[0.5, 0.0, 1.0, 0.0, 0.8],   # 9 pitch toward
		[0.5, 0.0, 0.0, 0.0, 0.9],   # 10 pitch centre
		[0.5, 0.0, 0.0, -1.0, 0.8],  # 11 roll left
		[0.5, 0.0, 0.0, 1.0, 0.8],   # 12 roll right
		[0.5, 0.0, 0.0, 0.0, 1.0],   # 13 roll centre
	]
	for item in sequence:
		_set_sticks(item[0], item[1], item[2], item[3])
		await get_tree().create_timer(item[4]).timeout
		if not is_instance_valid(_cal):
			print("[CALQA] FAIL: calibration screen disappeared early")
			get_tree().quit()
			return
		print("[CALQA] step=", int(_cal.get("calibration_step")),
				" finished=", bool(_cal.get("calibration_finished")))

	# _on_calibration_done sets calibration_finished immediately, then waits
	# 1.4 s before returning to the menu.
	await get_tree().create_timer(0.8).timeout
	if is_instance_valid(_cal):
		var finished := bool(_cal.get("calibration_finished"))
		var step := int(_cal.get("calibration_step"))
		print("[CALQA] RESULT step=", step, " finished=", finished)
		print("[CALQA] ", "PASS" if finished else "FAIL")
	get_tree().quit()


func _set_sticks(throttle: float, yaw: float, pitch: float, roll: float) -> void:
	_pad.set("throttle", throttle)
	_pad.set("yaw", yaw)
	_pad.set("pitch", pitch)
	_pad.set("roll", roll)
