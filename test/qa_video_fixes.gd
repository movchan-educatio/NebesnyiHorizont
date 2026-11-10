extends Node

## QA for the issues reported in IMG_6820:
##  - ARM must arm once (not arm+disarm through a second toggle_arm edge)
##  - ARM must not change the flight mode (TURTLE/LAUNCH)
##  - optional ELRS AUX actions must be disabled by default
##  - the mobile pause card and rows must be phone-sized
##  - the hero/hangar drone must not load as a speck
##  - a touch on the left stick must not pause the mission

var _fail := 0


func _ready() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	print("[VIDEOFIX] ", "PASS " if ok else "FAIL ", label)
	if not ok:
		_fail += 1


func _bounds(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for vi in root.find_children("*", "VisualInstance3D", true, false):
		var v := vi as VisualInstance3D
		var b: AABB = v.global_transform * v.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _run() -> void:
	await get_tree().process_frame

	# --- ELRS AUX defaults -------------------------------------------------
	var elrs := get_node_or_null("/root/ElrsWifiInput")
	_check(elrs != null, "ElrsWifiInput present")
	if elrs != null:
		var actions: Dictionary = elrs.get("action_channels")
		_check(int(actions.get("pause_menu", 99)) == -1, "pause_menu is not on an AUX channel")
		_check(int(actions.get("mode_turtle", 99)) == -1, "mode_turtle is not on an AUX channel")
		_check(int(actions.get("cycle_flight_modes", 99)) == -1,
				"flight-mode cycling is not on an AUX channel")
		_check(int(actions.get("arm", -1)) == 4, "arm stays on CH5")
		elrs.call("set_action_channel", "deploy_payload", 0)
		_check(int(elrs.call("get_action_channel", "deploy_payload")) != 0,
				"actions cannot bind to a stick channel")
		elrs.call("set_action_channel", "cycle_flight_modes", 8)
		_check(int(elrs.call("get_action_channel", "cycle_flight_modes")) == 8,
				"mode action binds to an AUX channel")
		elrs.call("set_action_channel", "cycle_flight_modes", -1)
		_check(int(elrs.call("get_action_channel", "cycle_flight_modes")) == -1,
				"disabled mode action stays disabled after save")

	# --- minimal level with a real drone --------------------------------
	var level := Node3D.new()
	level.name = "QaLevel"
	var drone: Node3D = load("res://drone/drones/Drone1.tscn").instantiate()
	drone.name = "Drone"
	level.add_child(drone)
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	await get_tree().process_frame
	await get_tree().process_frame
	var fc = drone.get("flight_controller")
	_check(fc != null, "drone flight controller")
	if fc == null:
		_finish()
		return
	fc.request_disarm()
	var mode_before := int(fc.get("flight_mode"))
	var touch := get_node_or_null("/root/TouchControls")
	touch.set_enabled(true)
	touch.call("_layout")

	touch.call("_on_arm_pressed")
	await get_tree().process_frame
	_check(bool(fc.get("state_armed")), "ARM button arms the drone")
	_check(int(fc.get("flight_mode")) == mode_before, "ARM button keeps the flight mode")
	touch.call("_on_arm_pressed")
	await get_tree().process_frame
	_check(not bool(fc.get("state_armed")), "second ARM press disarms")

	Input.action_press("mode_turtle")
	touch.call("_on_arm_pressed")
	await get_tree().process_frame
	_check(bool(fc.get("state_armed")), "ARM works while turtle input is held")
	_check(int(fc.get("flight_mode")) == mode_before,
			"held turtle input cannot change mode during ARM")
	touch.call("_on_arm_pressed")
	Input.action_release("mode_turtle")
	await get_tree().process_frame

	# --- touch stick must not pause -------------------------------------
	var stick_pos: Vector2 = touch.get("_left_center")
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.position = stick_pos
	ev.pressed = true
	touch.call("_input", ev)
	await get_tree().process_frame
	_check(not get_tree().paused, "touch on the left stick does not pause")

	# --- pause card size -------------------------------------------------
	var pause = load("res://GUI/PauseMenu.tscn").instantiate()
	add_child(pause)
	for i in range(5):
		await get_tree().process_frame
	var panel := pause.find_child("PanelContainer", true, false) as Control
	var resume := pause.find_child("ButtonResume", true, false) as Button
	print("[VIDEOFIX] pause panel size=", panel.size, " resume_h=", resume.custom_minimum_size.y)
	_check(panel.size.x >= 900.0, "mobile pause card is wide")
	_check(resume.custom_minimum_size.y >= 80.0, "mobile pause rows are tall")
	_check(pause.get("mobile_menu") != null, "pause can open the mobile sub-menus")
	var desktop_quit: Button = pause.get("btn_quit")
	_check(desktop_quit != null and desktop_quit.visible, "desktop keeps the quit button")
	# iOS must not show a dead "quit" button (SceneTree.quit is a no-op there).
	OS.set_environment("SIMULATE_IOS", "1")
	var pause_ios = load("res://GUI/PauseMenu.tscn").instantiate()
	add_child(pause_ios)
	for i in range(3):
		await get_tree().process_frame
	var ios_quit: Button = pause_ios.get("btn_quit")
	_check(ios_quit != null and not ios_quit.visible, "iOS hides the dead quit button")
	var found_hint := false
	for lbl in pause_ios.find_children("*", "Label", true, false):
		if String((lbl as Label).text).contains("свайпом"):
			found_hint = true
	_check(found_hint, "iOS shows the swipe-to-close hint")
	OS.unset_environment("SIMULATE_IOS")
	pause_ios.queue_free()

	# --- hero model size on first load ----------------------------------
	var menu = load("res://GUI/mobile/MobileMenu.tscn").instantiate()
	add_child(menu)
	for i in range(30):
		await get_tree().process_frame
	var action_options: Dictionary = menu.get("_action_options")
	var aux_only := not action_options.is_empty()
	for key in action_options.keys():
		var opt: OptionButton = action_options[key]
		for item_idx in range(opt.item_count):
			var item_id := opt.get_item_id(item_idx)
			if item_id >= 0 and item_id < 4:
				aux_only = false
	_check(aux_only, "action dropdown lists only AUX channels CH5-CH16")
	if action_options.has("arm"):
		var arm_opt: OptionButton = action_options["arm"]
		_check(arm_opt.get_item_id(0) == 99, "disabled row uses a safe sentinel id")
	if action_options.has("deploy_payload"):
		var deploy_opt: OptionButton = action_options["deploy_payload"]
		var ch7_idx := 0
		var off_idx := 0
		for item_idx in range(deploy_opt.item_count):
			if deploy_opt.get_item_id(item_idx) == 6:
				ch7_idx = item_idx
			elif deploy_opt.get_item_id(item_idx) == 99:
				off_idx = item_idx
		deploy_opt.select(ch7_idx)
		deploy_opt.item_selected.emit(ch7_idx)
		_check(int(elrs.call("get_action_channel", "deploy_payload")) == 6,
				"dropdown bind reaches CH7")
		deploy_opt.select(off_idx)
		deploy_opt.item_selected.emit(off_idx)
		_check(int(elrs.call("get_action_channel", "deploy_payload")) == -1,
				"dropdown disable row really unbinds")

	var holder: Node3D = menu.get("_hero_holder")
	var hero_box := _bounds(holder) if holder != null else AABB()
	var hero_max := maxf(hero_box.size.x, maxf(hero_box.size.y, hero_box.size.z))
	print("[VIDEOFIX] hero bounds=", hero_box.size, " max=", hero_max)
	_check(hero_max > 0.35 and hero_max < 0.75, "hero drone renders at full size")
	var cam: Camera3D = menu.get("_hero_camera")
	_check(cam != null and cam.global_position.distance_to(hero_box.get_center()) < 2.6,
			"hero camera stays close to the drone")

	# --- hangar model size after switching back -------------------------
	menu.call("_show", "drone")
	for i in range(10):
		await get_tree().process_frame
	var hangar: Node3D = menu.get("_hangar_holder")
	var idx: int = int(menu.get("_hangar_preview_idx"))
	menu.call("_load_hangar_model", (idx + 1) % 16)
	for i in range(10):
		await get_tree().process_frame
	menu.call("_load_hangar_model", idx)
	for i in range(25):
		await get_tree().process_frame
	var hbox := _bounds(hangar) if hangar != null else AABB()
	var hmax := maxf(hbox.size.x, maxf(hbox.size.y, hbox.size.z))
	print("[VIDEOFIX] hangar bounds=", hbox.size, " max=", hmax)
	_check(hmax > 0.35 and hmax < 0.75, "hangar drone renders at full size after reload")

	_finish()


func _finish() -> void:
	print("[VIDEOFIX] RESULT ", "PASS" if _fail == 0 else "FAIL", " failures=", _fail)
	get_tree().quit(0 if _fail == 0 else 1)
