extends Node

## QA for the issues reported in IMG_6820:
##  - ARM must arm once (not arm+disarm through a second toggle_arm edge)
##  - ARM must not change the flight mode (TURTLE/LAUNCH)
##  - optional ELRS AUX actions must be disabled by default
##  - the mobile pause card and rows must be phone-sized
##  - the hero/hangar drone must not load as a speck
##  - a touch on the left stick must not pause the mission

var _fail := 0
var _settings: Node = null
var _real_settings_path := ""
var _controls: Node = null
var _real_input_map_path := ""
var _saved_hud: Dictionary = {}
var _saved_actions: Dictionary = {}
var _saved_arm_channel := 4
var _saved_mode_channel := -1
var _saved_video_channel := -1


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
	# Persistence/binding checks must never overwrite the real player profile.
	_settings = get_node_or_null("/root/GameSettings")
	var elrs_for_backup := get_node_or_null("/root/ElrsWifiInput")
	if _settings != null:
		_real_settings_path = str(_settings.get("game_settings_path"))
		_saved_hud = (_settings.get("hud_config") as Dictionary).duplicate(true)
		_settings.set("game_settings_path", "user://qa_video_fixes_settings.cfg")
	_controls = get_node_or_null("/root/Controls")
	if _controls != null:
		_real_input_map_path = str(_controls.get("input_map_path"))
		_controls.set("input_map_path", "user://qa_video_fixes_input.cfg")
	if elrs_for_backup != null:
		_saved_actions = (elrs_for_backup.get("action_channels") as Dictionary).duplicate(true)
		_saved_arm_channel = int(elrs_for_backup.get("arm_channel"))
		_saved_mode_channel = int(elrs_for_backup.get("mode_channel"))
		_saved_video_channel = int(elrs_for_backup.get("video_channel"))

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
		# CRSF 172-1811 and 15-bit 0-32767 ELRS scales both map to full-range
		# throttle. Values must rise smoothly rather than jump 0 -> 50%.
		var saved_channels: PackedFloat32Array = elrs.get("channels")
		var saved_valid := bool(elrs.get("valid"))
		var linear_channels := PackedFloat32Array()
		linear_channels.resize(16)
		linear_channels.fill(16384.0)
		elrs.set("valid", true)
		elrs.set("invert_throttle", false)
		var throttle_samples: Array[float] = []
		for raw in [172.0, 582.0, 992.0, 1401.0, 1811.0]:
			linear_channels[2] = raw
			elrs.set("channels", linear_channels)
			throttle_samples.append(float(elrs.call("throttle")))
		var throttle_linear := true
		for i in range(1, throttle_samples.size()):
			throttle_linear = throttle_linear and throttle_samples[i] > throttle_samples[i - 1]
		_check(throttle_linear and throttle_samples[2] > 0.40 \
				and throttle_samples[2] < 0.55,
				"left ELRS stick CRSF mid-range is normalized smoothly")
		elrs.set("channels", saved_channels)
		elrs.set("valid", saved_valid)
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
	var saved_deadzone := float(Controls.get("stick_deadzone"))
	var left_center: Vector2 = touch.get("_left_center")
	var radius := float(touch.get("_radius"))
	Controls.set("stick_deadzone", 0.10)
	touch.call("_update_stick", true, left_center + Vector2(radius * 0.05, 0.0))
	_check(is_zero_approx(float(touch.get("yaw"))),
			"touch stick deadzone slider is applied")
	Controls.set("stick_deadzone", 0.01)
	touch.call("_update_stick", true, left_center + Vector2(radius * 0.05, 0.0))
	_check(absf(float(touch.get("yaw"))) > 0.04,
			"touch stick response follows deadzone slider")
	Controls.set("stick_deadzone", saved_deadzone)
	touch.call("_reset_sticks")

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
	var stick_monitor = load("res://HUD/HUDStickInput.tscn").instantiate()
	add_child(stick_monitor)
	await get_tree().process_frame
	_check(stick_monitor.find_child("AxisLabel", true, false) == null,
			"flight stick monitor has no axis captions")
	stick_monitor.queue_free()
	# Phone quality tiers keep the high-level art, while adapting only 3D scale
	# and far foliage.  Desktop presets are left alone.
	var quality := load("res://scripts/util/quality_manager.gd")
	var had_mobile_env := OS.has_environment("MOBILE_UI")
	OS.set_environment("MOBILE_UI", "1")
	var phone_quality: Dictionary = quality.params()
	OS.unset_environment("MOBILE_UI")
	var desktop_quality: Dictionary = quality.params()
	if had_mobile_env:
		OS.set_environment("MOBILE_UI", "1")
	_check(bool(phone_quality.get("adaptive", false))
			and float(phone_quality.get("max_scale", 1.0)) < 1.0,
			"mobile quality uses adaptive resolution and device-safe scale")
	_check(not bool(desktop_quality.get("adaptive", false)),
			"desktop quality profile is unchanged")

	var current_preset := int(Global.drone_preset)
	var kamikaze_touch_ok := true
	var had_mobile_for_catalog := OS.has_environment("MOBILE_UI")
	OS.unset_environment("MOBILE_UI")
	var desktop_expected := {
		13: {"payload": 0, "fpv_cam_pos": Vector3(0.0, 0.06, -0.56)},
		14: {"payload": 0, "fpv_cam_pos": Vector3(0.0, 0.04, -0.42)},
		15: {"payload": 1, "fpv_cam_pos": Vector3(0.0, 0.06, -0.78)},
	}
	var pc_unchanged := true
	for preset_idx in desktop_expected:
		var desktop_preset: Dictionary = DroneCatalog.preset(preset_idx)
		pc_unchanged = pc_unchanged \
				and int(desktop_preset.get("payload", -1)) == int(desktop_expected[preset_idx]["payload"]) \
				and desktop_preset.get("fpv_cam_pos") == desktop_expected[preset_idx]["fpv_cam_pos"] \
				and bool(desktop_preset.get("fpv_hide_model", false)) \
				and not bool(desktop_preset.get("fpv_show_airframe", false))
	_check(pc_unchanged, "desktop fixed-wing loadout and FPV framing remain unchanged")
	if had_mobile_for_catalog:
		OS.set_environment("MOBILE_UI", "1")
	for preset_idx in [13, 14, 15]:
		Global.drone_preset = preset_idx
		kamikaze_touch_ok = kamikaze_touch_ok \
				and bool(DroneCatalog.preset(preset_idx).get("kamikaze", false)) \
				and DroneCatalog.supports_payload_actions(preset_idx) \
				and touch.call("_touch_payload_action") == "activate_payload"
	Global.drone_preset = current_preset
	_check(kamikaze_touch_ok, "Leleka/Furia/Chaklun touch button activates warhead")
	var audio := get_node_or_null("/root/Audio")
	if audio != null:
		var master_was_muted := AudioServer.is_bus_mute(0)
		# Simulate OS interruption muting the bus after the app pause event.
		AudioServer.set_bus_mute(0, false)
		audio.call("_notification", Node.NOTIFICATION_APPLICATION_PAUSED)
		AudioServer.set_bus_mute(0, true)
		audio.call("_notification", Node.NOTIFICATION_APPLICATION_RESUMED)
		await get_tree().process_frame
		_check(not AudioServer.is_bus_mute(0), "audio output resumes after app interruption")
		# A pilot's intentional mute is a setting, not an OS interruption; keep it.
		AudioServer.set_bus_mute(0, true)
		audio.call("_notification", Node.NOTIFICATION_APPLICATION_PAUSED)
		audio.call("_notification", Node.NOTIFICATION_APPLICATION_RESUMED)
		await get_tree().process_frame
		_check(AudioServer.is_bus_mute(0), "audio preserves intentional bus mute on resume")
		AudioServer.set_bus_mute(0, master_was_muted)

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
	var saved_preset := int(Global.drone_preset)
	for preset_idx in [13, 14, 15]:
		Global.drone_preset = preset_idx
		var kamikaze_action: String = touch.call("_touch_payload_action")
		_check(kamikaze_action == "activate_payload",
				"fixed-wing kamikaze preset %d routes touch button to warhead" % preset_idx)
	Global.drone_preset = saved_preset

	var holder: Node3D = menu.get("_hero_holder")
	var hero_box := _bounds(holder) if holder != null else AABB()
	var hero_max := maxf(hero_box.size.x, maxf(hero_box.size.y, hero_box.size.z))
	print("[VIDEOFIX] hero bounds=", hero_box.size, " max=", hero_max)
	_check(hero_max > 0.35 and hero_max < 0.75, "hero drone renders at full size")
	var cam: Camera3D = menu.get("_hero_camera")
	_check(cam != null and cam.global_position.distance_to(hero_box.get_center()) < 2.6,
			"hero camera stays close to the drone")
	for preset_idx in [13, 14, 15]:
		await DroneCatalog.wait_for_model(preset_idx)
		menu.call("_load_hero_model", preset_idx)
		for i in range(6):
			await get_tree().process_frame
		var aircraft_holder: Node3D = menu.get("_hero_holder")
		var aircraft: Node3D = aircraft_holder.get_child(0) if aircraft_holder.get_child_count() > 0 else null
		var source_path := str(aircraft.get_meta("source_glb", "")) if aircraft != null else ""
		var pivots: Array = aircraft.get_meta("prop_pivots", []) if aircraft != null else []
		_check(source_path.ends_with("_mobile.glb"),
				"airframe %d uses mobile-optimized mesh" % preset_idx)
		if preset_idx in [13, 14]:
			_check(not pivots.is_empty(), "airframe %d pusher prop is animated" % preset_idx)
	_check(bool(DroneCatalog.supports_payload_actions(13))
			and bool(DroneCatalog.supports_payload_actions(14))
			and bool(DroneCatalog.supports_payload_actions(15)),
			"Leleka/Furia/Chaklun integrated warhead is enabled")

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
	if _settings != null:
		_settings.set("game_settings_path", _real_settings_path)
		_settings.set("hud_config", _saved_hud)
	if _controls != null:
		_controls.set("input_map_path", _real_input_map_path)
	var elrs := get_node_or_null("/root/ElrsWifiInput")
	if elrs != null and not _saved_actions.is_empty():
		elrs.set("action_channels", _saved_actions)
		elrs.set("arm_channel", _saved_arm_channel)
		elrs.set("mode_channel", _saved_mode_channel)
		elrs.set("video_channel", _saved_video_channel)
	var qa_path := ProjectSettings.globalize_path("user://qa_video_fixes_settings.cfg")
	if FileAccess.file_exists("user://qa_video_fixes_settings.cfg"):
		DirAccess.remove_absolute(qa_path)
	var qa_controls_path := ProjectSettings.globalize_path("user://qa_video_fixes_input.cfg")
	if FileAccess.file_exists("user://qa_video_fixes_input.cfg"):
		DirAccess.remove_absolute(qa_controls_path)
	print("[VIDEOFIX] RESULT ", "PASS" if _fail == 0 else "FAIL", " failures=", _fail)
	get_tree().quit(0 if _fail == 0 else 1)
