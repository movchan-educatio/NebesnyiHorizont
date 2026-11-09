extends Node

## QA campaign runner: drives the real MainMenu selection for every map/mode,
## launches the level, checks spawn/HUD/mode setup, performs an automated
## take-off, saves a screenshot and returns to the menu for the next case.
##
## Started by DebugShot when DRONE_CAMPAIGN_TEST is set.  It lives under the
## tree root, so it survives the menu -> level -> menu scene changes.

const MAIN_MENU := "res://GUI/MainMenu.tscn"
const SHOT_DIR := "res://qa_shots/campaign"

var _failures: Array[String] = []
var _cases: Array[Dictionary] = []
var _saved_records: Dictionary = {}


func _ready() -> void:
	if Global.startup:
		Global.initialize()
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		get_window().size = Vector2i(1280, 720)
		get_window().move_to_center()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	_saved_records = Global.campaign_records.duplicate(true)
	_build_cases()
	var only := OS.get_environment("DRONE_CAMPAIGN_ONLY")
	if not only.is_empty():
		_cases = _cases.filter(func(c): return str(c["tag"]).contains(only))
	var limit := int(OS.get_environment("DRONE_CAMPAIGN_LIMIT"))
	if limit > 0 and _cases.size() > limit:
		_cases.resize(limit)
	print("[CAMPAIGN] cases=", _cases.size())
	if not OS.has_environment("DRONE_CAMPAIGN_SKIP_START"):
		await _check_start_screen()
	else:
		# Let StartScreen finish its video/UI setup before the first scene swap;
		# freeing it mid-coroutine produced look_at/process_frame errors.
		await get_tree().create_timer(2.0).timeout
	for i in range(_cases.size()):
		await _run_case(_cases[i], i)
	Global.campaign_records = _saved_records
	print("[CAMPAIGN] failures=", _failures.size())
	for f in _failures:
		print("[CAMPAIGN] FAIL ", f)
	print("[CAMPAIGN] RESULT ", "PASS" if _failures.is_empty() else "FAIL")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _build_cases() -> void:
	var maps := ["steppe", "village", "industrial", "wetlands"]
	for map in maps:
		_cases.append({"tag": "combat_" + map, "mode": Global.PlayMode.COMBAT,
				"map": map, "mission": 1, "special": 0})
	for map in maps:
		_cases.append({"tag": "training_" + map, "mode": Global.PlayMode.TRAINING,
				"map": map, "mission": 1, "special": 0})
	for map in maps:
		_cases.append({"tag": "speed_" + map, "mode": Global.PlayMode.SPEED,
				"map": map, "mission": 1, "special": 0})
	_cases.append({"tag": "tutorial_village", "mode": Global.PlayMode.TUTORIAL,
			"map": "village", "mission": 1, "special": 0})
	_cases.append({"tag": "chaos_industrial", "mode": Global.PlayMode.CHAOS,
			"map": "industrial", "mission": 1, "special": 0})
	var special_maps := ["industrial", "village", "steppe", "wetlands"]
	for s in range(1, 7):
		var smap: String = special_maps[(s - 1) % special_maps.size()]
		_cases.append({"tag": "special_%d_%s" % [s, smap],
				"mode": Global.PlayMode.COMBAT,
				"map": smap, "mission": 1, "special": s})
	for m in range(2, 6):
		var map := "valley" if m == 5 else "industrial"
		_cases.append({"tag": "campaign_m%d_%s" % [m, map],
				"mode": Global.PlayMode.COMBAT,
				"map": map, "mission": m, "special": 0})


func _check_start_screen() -> void:
	_free_loading_overlay()
	get_tree().change_scene_to_file("res://GUI/StartScreen.tscn")
	var start = await _wait_scene("StartScreen", 10.0)
	if start == null:
		_fail("start_screen", "StartScreen did not load")
		return
	await get_tree().create_timer(0.8).timeout
	start.call("_on_start_pressed")
	var menu = await _wait_scene("MainMenu", 10.0)
	if menu == null:
		_fail("start_screen", "Start -> MainMenu failed")
	else:
		await get_tree().create_timer(0.6).timeout
		print("[CAMPAIGN] OK start_screen -> MainMenu")


func _run_case(c: Dictionary, index: int) -> void:
	var tag: String = str(c["tag"])
	print("[CAMPAIGN] START %d/%d %s" % [index + 1, _cases.size(), tag])
	_prepare_unlock(int(c.get("mission", 1)))
	_free_loading_overlay()
	var menu := get_tree().current_scene
	if menu == null or not String(menu.name).contains("MainMenu"):
		get_tree().change_scene_to_file(MAIN_MENU)
		menu = await _wait_scene("MainMenu", 10.0)
	if menu == null:
		_fail(tag, "MainMenu did not load")
		_free_loading_overlay()
		return
	await get_tree().create_timer(0.5).timeout
	menu.set("_selected_mission", int(c.get("mission", 1)))
	menu.set("_selected_special", int(c.get("special", 0)))
	# Use the same menu handlers the buttons call, not just raw fields, so mode
	# switching, mission unlock/clamping and drone restrictions are exercised.
	menu.call("_select_mode", int(c["mode"]))
	if int(c.get("special", 0)) > 0:
		menu.call("_select_special_mission", int(c["special"]))
	elif int(c["mode"]) == Global.PlayMode.COMBAT:
		menu.call("_select_mission", int(c.get("mission", 1)))
	menu.call("_select_map", str(c["map"]))
	Global.play_mode = int(c["mode"])
	Global.special_mission = int(c.get("special", 0))
	Global.combat_mission = int(c.get("mission", 1))
	menu.call("_launch_current_selection")
	var level = await _wait_level(45.0)
	if level == null:
		var cs := get_tree().current_scene
		print("[CAMPAIGN] DIAG current_scene=",
				"null" if cs == null else String(cs.name),
				" path=", "" if cs == null else String(cs.scene_file_path))
		print("[CAMPAIGN] DIAG overlay=",
				get_tree().root.get_node_or_null("GlobalLoadingOverlay") != null,
				" paused=", get_tree().paused)
		_fail(tag, "level did not load")
		_free_loading_overlay()
		return
	await get_tree().create_timer(2.5).timeout
	var fails_before := _failures.size()
	await _validate_case(tag, c, level)
	if _failures.size() == fails_before:
		print("[CAMPAIGN] OK ", tag)
	if OS.has_environment("DRONE_CAMPAIGN_SHOTS") \
			and DisplayServer.get_name() != "headless":
		await _capture(tag)
	_free_loading_overlay()
	get_tree().change_scene_to_file(MAIN_MENU)
	await _wait_scene("MainMenu", 8.0)
	await get_tree().create_timer(0.2).timeout


func _validate_case(tag: String, c: Dictionary, level: Node) -> void:
	var drone = level.get_node_or_null("Drone")
	if drone == null:
		_fail(tag, "no Drone")
		return
	var hud = level.get("_hud")
	if hud is CanvasLayer and not (hud as CanvasLayer).visible:
		_fail(tag, "flight HUD not visible")
	var hud_label = level.get("_hud_label")
	if hud_label is Label:
		print("[CAMPAIGN] HUD ", tag, " play_mode=", Global.play_mode,
				" text=", String((hud_label as Label).text).replace("\n", " | "))
	var mode := int(c["mode"])
	var special := int(c.get("special", 0))
	var mission := int(c.get("mission", 1))
	# Mode-specific setup.
	match mode:
		Global.PlayMode.TRAINING:
			# Frontline training is intentionally free flight: the old 24-ring
			# course lives only on the legacy valley map and was removed here
			# because it covered the OSD and cluttered the hero-hall approach.
			if int(level.get("_rings_total")) < 0:
				_fail(tag, "invalid ring count")
		Global.PlayMode.SPEED:
			var cps: Array = level.get("_speed_checkpoints")
			if cps.is_empty():
				_fail(tag, "no speed checkpoints")
		Global.PlayMode.TUTORIAL:
			if level.get("_flight_school") == null:
				_fail(tag, "no flight school")
		Global.PlayMode.CHAOS:
			if level.get_node_or_null("ChaosBattle") == null:
				_fail(tag, "no ChaosBattle")
		Global.PlayMode.COMBAT:
			if special == 0 and mission != 5:
				if int(level.get("_mission_targets_total")) <= 0:
					_fail(tag, "no mission targets")
			elif special > 0:
				var zones: Array = level.get("_special_zones")
				var beacons: Array = level.get("_special_beacons")
				var convoy = level.get("_special_convoy")
				if zones.is_empty() and beacons.is_empty() and convoy == null \
						and int(level.get("_mission_targets_total")) <= 0:
					_fail(tag, "special mission has no objectives")
	# Spawn: the camera must not start inside a wall/terrain.  A small sphere
	# at the airframe centre (excluding the drone) is enough to catch clipping.
	if DisplayServer.get_name() != "headless":
		var space = level.get_world_3d().direct_space_state
		if space != null and drone is CollisionObject3D:
			var shape := SphereShape3D.new()
			shape.radius = 0.25
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = shape
			q.exclude = [(drone as CollisionObject3D).get_rid()]
			q.transform = Transform3D(Basis.IDENTITY,
					drone.global_position + Vector3(0.0, 0.35, 0.0))
			if not space.intersect_shape(q, 1).is_empty():
				_fail(tag, "spawn overlaps geometry")
	# Automated take-off (skip the boat and the school, which owns the sticks).
	var naval := int(Global.drone_preset) == 10
	if not naval and mode != Global.PlayMode.TUTORIAL:
		await _test_takeoff(tag, level, drone)


func _test_takeoff(tag: String, level: Node, drone: Node) -> void:
	var fc = drone.get("flight_controller")
	var radio = level.get_node_or_null("RadioController")
	if fc == null:
		_fail(tag, "no flight controller")
		return
	drone.set("freeze", false)
	fc.call("request_arm", true)
	await get_tree().create_timer(0.35).timeout
	if not bool(fc.get("state_armed")):
		_fail(tag, "arm failed")
		return
	if radio != null:
		var twr := float(DroneCatalog.preset(Global.drone_preset).get("twr", 2.0))
		var hover := 0.45 + 0.55 * sqrt(1.0 / maxf(twr, 1.0))
		radio.set("test_throttle", clampf(hover + 0.08, 0.60, 0.95))
		radio.set("test_pitch", 0.0)
	var y0: float = drone.global_position.y
	await get_tree().create_timer(1.2).timeout
	var rise: float = drone.global_position.y - y0
	if radio != null:
		radio.set("test_throttle", 0.0)
	fc.call("request_arm", false)
	print("[CAMPAIGN] takeoff ", tag, " rise=%.2f" % rise)
	if rise < 0.5:
		_fail(tag, "take-off rise %.2f m" % rise)


func _prepare_unlock(mission: int) -> void:
	for i in range(1, mission):
		var rec: Dictionary = Global.get_mission_record(i).duplicate(true)
		rec["completed"] = true
		Global.campaign_records["mission_%d" % i] = rec


func _wait_scene(name_part: String, timeout: float) -> Node:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var scene := get_tree().current_scene
		if scene != null and String(scene.name).contains(name_part):
			return scene
		await get_tree().process_frame
	# A synchronous level load can block past the deadline; check once more.
	var final_scene := get_tree().current_scene
	if final_scene != null and String(final_scene.name).contains(name_part):
		return final_scene
	return null


func _wait_level(timeout: float) -> Node:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var scene := get_tree().current_scene
		if scene != null and not String(scene.name).contains("MainMenu") \
				and scene.get_node_or_null("Drone") != null:
			return scene
		await get_tree().process_frame
	# On Intel UHD the first windowed level can take >15 s to build while the
	# main thread is blocked, so the coroutine only resumes after the deadline.
	var final_scene := get_tree().current_scene
	if final_scene != null and not String(final_scene.name).contains("MainMenu") \
			and final_scene.get_node_or_null("Drone") != null:
		return final_scene
	return null


func _free_loading_overlay() -> void:
	var overlay := get_tree().root.get_node_or_null("GlobalLoadingOverlay")
	if overlay != null:
		overlay.queue_free()


func _capture(tag: String) -> void:
	await get_tree().process_frame
	if tag.begins_with("chaos"):
		var vp := get_viewport().get_visible_rect().size
		for n in get_tree().root.find_children("*", "Control", true, false):
			var c := n as Control
			if c == null or not c.is_visible_in_tree():
				continue
			if c.size.y < vp.y * 0.8 or c.size.x < 40.0:
				continue
			var col := ""
			if c is ColorRect:
				col = " color=" + (c as ColorRect).color.to_html()
			print("[CAMPAIGN] CTRL ", c.get_path(), " pos=", c.global_position,
					" size=", c.size, col)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return
	var path := ProjectSettings.globalize_path(SHOT_DIR).path_join(tag + ".png")
	img.save_png(path)


func _fail(tag: String, message: String) -> void:
	_failures.append("%s: %s" % [tag, message])
	print("[CAMPAIGN] CHECK-FAIL %s: %s" % [tag, message])
