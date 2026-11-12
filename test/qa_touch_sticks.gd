## QA-only: feeds synthetic screen touches through the same handler used by the
## real touch layer and checks that yaw / throttle / roll / pitch reach
## MobileInput.  Also checks that the touch roll inversion flips the sign.
extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().create_timer(2.0).timeout
	var pad := get_node_or_null("/root/TouchControls")
	var mobile := get_node_or_null("/root/MobileInput")
	if pad == null or mobile == null:
		print("[STICKQA] FAIL: missing nodes")
		get_tree().quit()
		return
	pad.call("set_menu_preview", true)
	var old_source := str(mobile.get("source_override"))
	mobile.call("set_source", "touch")
	await get_tree().create_timer(0.3).timeout

	var left: Vector2 = pad.get("_left_center")
	var right: Vector2 = pad.get("_right_center")
	var radius: float = float(pad.get("_radius"))
	print("[STICKQA] left=", left, " right=", right, " radius=", radius)

	# Direct calls exercise exactly the same handler that InputEventScreenTouch
	# reaches on iOS; synthetic OS events are not delivered reliably in headless.
	pad.call("_handle_touch", 0, left, true)
	pad.call("_handle_touch", 0, left + Vector2(radius * 0.8, -radius * 0.8), true)
	await get_tree().process_frame
	var yaw := float(pad.get("yaw"))
	var throttle := float(pad.get("throttle"))
	var yaw_axis := float(mobile.call("axis", 3))
	var throttle_axis := float(mobile.call("axis", 2))
	print("[STICKQA] left horizontal yaw=", yaw, " axis3=", yaw_axis)
	print("[STICKQA] left vertical throttle=", throttle, " axis2=", throttle_axis)
	pad.call("_handle_touch", 0, left, false)

	pad.call("_handle_touch", 1, right, true)
	pad.call("_handle_touch", 1, right + Vector2(radius * 0.8, -radius * 0.8), true)
	await get_tree().process_frame
	var roll := float(pad.get("roll"))
	var pitch := float(pad.get("pitch"))
	var roll_axis := float(mobile.call("axis", 0))
	var pitch_axis := float(mobile.call("axis", 1))
	print("[STICKQA] right horizontal roll=", roll, " axis0=", roll_axis)
	print("[STICKQA] right vertical pitch=", pitch, " axis1=", pitch_axis)
	pad.call("_handle_touch", 1, right, false)

	# Inversion: same right-stick drag must produce the opposite roll sign.
	var old_invert := bool(pad.get("invert_roll"))
	pad.set("invert_roll", false)
	pad.call("_handle_touch", 1, right, true)
	pad.call("_handle_touch", 1, right + Vector2(radius * 0.8, 0.0), true)
	await get_tree().process_frame
	var roll_plain := float(pad.get("roll"))
	pad.call("_handle_touch", 1, right, false)
	pad.set("invert_roll", true)
	pad.call("_handle_touch", 1, right, true)
	pad.call("_handle_touch", 1, right + Vector2(radius * 0.8, 0.0), true)
	await get_tree().process_frame
	var roll_inverted := float(pad.get("roll"))
	pad.call("_handle_touch", 1, right, false)
	pad.set("invert_roll", old_invert)
	print("[STICKQA] roll plain=", roll_plain, " inverted=", roll_inverted)

	var ok := absf(yaw) > 0.5 and absf(yaw_axis) > 0.5 \
			and throttle > 0.5 and throttle_axis > 0.0 \
			and absf(roll) > 0.5 and absf(roll_axis) > 0.5 \
			and pitch < -0.5 and pitch_axis < -0.5 \
			and absf(roll_plain) > 0.5 and absf(roll_inverted) > 0.5 \
			and signf(roll_plain) != signf(roll_inverted)
	print("[STICKQA] pitch (stick-up must be negative = nose-down) =", pitch)
	print("[STICKQA] ", "PASS" if ok else "FAIL")
	mobile.call("set_source", old_source)
	get_tree().quit()
