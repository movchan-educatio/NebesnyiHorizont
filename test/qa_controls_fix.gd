## QA-only: exercises the touch action paths that the pilot reported as dead:
## flight-mode cycling and the video filter.  Also checks the round drop button.
extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().create_timer(3.0).timeout
	var drone := get_tree().current_scene.get_node_or_null("Drone")
	var fc = drone.get("flight_controller") if drone != null else null
	if fc == null:
		print("[CTRLQA] FAIL: no flight controller")
		get_tree().quit()
		return
	var touch := get_node_or_null("/root/TouchControls")
	print("[CTRLQA] mode_start=", int(fc.get("flight_mode")))
	for i in range(3):
		_dispatch("cycle_flight_modes")
		await get_tree().create_timer(0.45).timeout
		print("[CTRLQA] mode_after_", i + 1, "=", int(fc.get("flight_mode")))
	var overlay := get_tree().current_scene.get_node_or_null("FPVOverlay")
	var before_mode := int(get_node("/root/Graphics").get("fpv_video_mode"))
	_dispatch("cycle_video_mode")
	await get_tree().create_timer(0.3).timeout
	var after_mode := int(get_node("/root/Graphics").get("fpv_video_mode"))
	var overlay_visible := overlay != null and bool(overlay.get("visible"))
	print("[CTRLQA] video_before=", before_mode, " video_after=", after_mode,
			" overlay_visible=", overlay_visible)
	if touch != null:
		var drop: Button = touch.get("_drop_button")
		print("[CTRLQA] drop_button=", drop != null,
				" visible=", drop.visible if drop != null else false,
				" size=", drop.size if drop != null else Vector2.ZERO,
				" pos=", drop.position if drop != null else Vector2.ZERO)
	var ok := after_mode != before_mode and overlay_visible
	print("[CTRLQA] ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)


func _dispatch(action: String) -> void:
	if not InputMap.has_action(action):
		print("[CTRLQA] missing action ", action)
		return
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	ev.strength = 1.0
	Input.parse_input_event(ev)
	Input.action_press(action)
	await get_tree().process_frame
	var rel := InputEventAction.new()
	rel.action = action
	rel.pressed = false
	rel.strength = 0.0
	Input.parse_input_event(rel)
	Input.action_release(action)
