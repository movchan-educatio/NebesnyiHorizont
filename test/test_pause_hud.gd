extends Node

## Regression: opening the pause menu must not overwrite the saved HUD state
## with the already-hidden state.  Resuming has to restore every HUD layer.

func _ready() -> void:
	await get_tree().process_frame
	Global.play_mode = Global.PlayMode.COMBAT
	Global.chain_briefing_pending = false
	Global.drone_preset = 2
	var packed := load("res://sceneries/VillageLevel.tscn") as PackedScene
	var level: Variant = packed.instantiate()
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	await get_tree().create_timer(3.0).timeout
	get_tree().paused = false

	var pause_canvas: Node = level.get_node_or_null("PauseCanvasLayer")
	var pause_menu = pause_canvas.get_child(0) if pause_canvas != null \
			and pause_canvas.get_child_count() > 0 else null
	var ok := true
	if pause_menu == null:
		printerr("[PAUSEHUD] FAIL pause menu missing")
		get_tree().quit(1)
		return
	var level_hud: CanvasLayer = level.get("_hud")
	var drone: Node = level.get_node_or_null("Drone")
	var drone_hud = drone.get("hud") if drone != null else null
	if level_hud == null or not level_hud.visible:
		printerr("[PAUSEHUD] FAIL flight HUD not visible before pause")
		ok = false
	if drone_hud is CanvasItem and not (drone_hud as CanvasItem).visible:
		printerr("[PAUSEHUD] FAIL drone HUD not visible before pause")
		ok = false

	# This path triggers suppression twice: once from show_menu(), once from
	# visibility_changed().  The old implementation saved the hidden state.
	get_tree().paused = true
	pause_menu.show_menu(true)
	await get_tree().process_frame
	if level_hud.visible:
		printerr("[PAUSEHUD] FAIL flight HUD should be hidden while paused")
		ok = false
	pause_menu._on_resume_pressed()
	await get_tree().process_frame
	if not level_hud.visible:
		printerr("[PAUSEHUD] FAIL flight HUD stayed hidden after resume")
		ok = false
	if drone_hud is CanvasItem and not (drone_hud as CanvasItem).visible:
		printerr("[PAUSEHUD] FAIL drone HUD stayed hidden after resume")
		ok = false
	if get_tree().paused:
		printerr("[PAUSEHUD] FAIL tree stayed paused after resume")
		ok = false

	# Regression: the pause freezer must restore the pre-pause state.  A drone
	# still parked on its launch pad is frozen until arming; resuming from the
	# menu used to unfreeze it and drop it out of the sky.
	if drone != null:
		drone.freeze = true
		pause_menu._set_drone_frozen(true)
		pause_menu._set_drone_frozen(false)
		if not drone.freeze:
			printerr("[PAUSEHUD] FAIL parked drone unfroze after resume")
			ok = false
		drone.freeze = false
		drone.linear_velocity = Vector3(4.0, 2.0, 1.0)
		drone.angular_velocity = Vector3(0.5, 0.4, 0.3)
		pause_menu._set_drone_frozen(true)
		if drone.linear_velocity.length() > 0.001:
			printerr("[PAUSEHUD] FAIL drone velocity not cleared on pause")
			ok = false
		pause_menu._set_drone_frozen(false)
		if drone.freeze:
			printerr("[PAUSEHUD] FAIL airborne drone stayed frozen after resume")
			ok = false

	# Also cover the Level._input -> resumed -> Level._on_resume path, which
	# hides the menu by setting visible=false instead of calling the menu's
	# resume button directly.
	get_tree().paused = true
	pause_menu.show_menu(true)
	await get_tree().process_frame
	level.call("_on_resume")
	await get_tree().process_frame
	if not level_hud.visible:
		printerr("[PAUSEHUD] FAIL HUD stayed hidden after Level._on_resume")
		ok = false
	if get_tree().paused:
		printerr("[PAUSEHUD] FAIL tree stayed paused after Level._on_resume")
		ok = false
	print("[PAUSEHUD] RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
