## QA-only: feeds synthetic screen touches into the menu twin-stick preview
## and checks that yaw / throttle / roll / pitch all reach MobileInput.
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
	await get_tree().create_timer(0.3).timeout

	var left: Vector2 = pad.get("_left_center")
	var right: Vector2 = pad.get("_right_center")
	var radius: float = float(pad.get("_radius"))
	print("[STICKQA] left=", left, " right=", right, " radius=", radius)

	_touch(0, left, true)
	_drag(0, left + Vector2(radius * 0.8, 0.0))
	await get_tree().process_frame
	var yaw := float(pad.get("yaw"))
	var yaw_axis := float(mobile.call("axis", 3))
	print("[STICKQA] left horizontal yaw=", yaw, " axis3=", yaw_axis)

	_drag(0, left + Vector2(radius * 0.8, -radius * 0.8))
	await get_tree().process_frame
	var throttle := float(pad.get("throttle"))
	var throttle_axis := float(mobile.call("axis", 2))
	print("[STICKQA] left vertical throttle=", throttle, " axis2=", throttle_axis)
	_touch(0, left, false)

	_touch(1, right, true)
	_drag(1, right + Vector2(radius * 0.8, 0.0))
	await get_tree().process_frame
	var roll := float(pad.get("roll"))
	var roll_axis := float(mobile.call("axis", 0))
	print("[STICKQA] right horizontal roll=", roll, " axis0=", roll_axis)

	_drag(1, right + Vector2(0.0, -radius * 0.8))
	await get_tree().process_frame
	var pitch := float(pad.get("pitch"))
	var pitch_axis := float(mobile.call("axis", 1))
	print("[STICKQA] right vertical pitch=", pitch, " axis1=", pitch_axis)
	_touch(1, right, false)

	var ok := absf(yaw) > 0.5 and absf(yaw_axis) > 0.5 \
			and throttle > 0.5 and throttle_axis > 0.0 \
			and absf(roll) > 0.5 and absf(roll_axis) > 0.5 \
			and absf(pitch) > 0.5 and absf(pitch_axis) > 0.5
	print("[STICKQA] ", "PASS" if ok else "FAIL")
	get_tree().quit()


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = pos
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _drag(index: int, pos: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = pos
	Input.parse_input_event(ev)
