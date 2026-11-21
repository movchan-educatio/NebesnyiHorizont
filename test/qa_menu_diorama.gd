extends Node

## Visual & functional QA for the Blender 3D military backdrop diorama and
## interactive rolling/falling brass shell casings in drone preview menus.

const SHOT_DIR := "C:/Users/USER_UA/.gemini/antigravity/brain/3e1fc674-fea9-4635-a574-57c85e14dad7/scratch/diorama_shots"

var _fails := 0
var _checks := 0


func _ready() -> void:
	call_deferred("_run")


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		printerr("[DIORAMA_QA] FAIL: ", msg)
	else:
		print("[DIORAMA_QA] PASS: ", msg)


func _save_shot(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		_check(false, "Valid viewport image for " + filename)
		return
	var path := SHOT_DIR.path_join(filename)
	var err := img.save_png(path)
	_check(err == OK, "Saved screenshot " + filename)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	if DisplayServer.get_name() != "headless":
		get_window().size = Vector2i(1280, 720)

	var saved_preset := Global.drone_preset
	var saved_mode := Global.play_mode
	var saved_settings := Global.menu_settings.duplicate(true)

	OS.set_environment("DRONE_NO_RECORD", "1")
	OS.set_environment("QA_NO_AMBIENT", "1")
	OS.set_environment("MOBILE_UI", "1")
	OS.set_environment("TOUCH_CONTROLS", "1")
	Global.menu_settings["selected_map"] = "industrial"
	Global.menu_settings["language"] = "uk"
	Global.menu_settings["drone_preset"] = 3
	Global.drone_preset = 3
	Global.play_mode = Global.PlayMode.COMBAT

	var packed := load("res://GUI/mobile/MobileMenu.tscn") as PackedScene
	_check(packed != null, "Loaded MobileMenu.tscn")
	if packed == null:
		get_tree().quit(1)
		return

	var menu := packed.instantiate()
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	await get_tree().process_frame
	menu.set("_selected_map", "industrial")
	menu.set("_selected_mode", Global.PlayMode.COMBAT)
	DroneCatalog.apply(3)
	menu.call("_load_hero_model", 3)
	var hero_holder := menu.get("_hero_holder") as Node3D
	for _w in range(100):
		await get_tree().create_timer(0.05).timeout
		if hero_holder != null and hero_holder.get_child_count() > 0:
			var ch := hero_holder.get_child(hero_holder.get_child_count() - 1) as Node3D
			if ch != null and ch.visible:
				break
	await get_tree().create_timer(0.2).timeout

	var hero_vp := menu.get("_hero_viewport") as Node
	var hero_diorama := menu.get("_hero_diorama") as Node3D
	var hero_container := menu.get("_hero_container") as SubViewportContainer
	var hero_cam := menu.get("_hero_camera") as Camera3D

	_check(hero_diorama != null, "_hero_diorama attached")
	if hero_diorama != null:
		_check(hero_diorama.get_parent() == hero_vp, "_hero_diorama is child of _hero_viewport")
		_check(hero_diorama.get_parent() != hero_holder, "_hero_diorama is isolated from _hero_holder AABB")

		var idle_stats: Dictionary = hero_diorama.call("get_debug_stats")
		print("[DIORAMA_QA] idle stats=", idle_stats)
		_check(int(idle_stats.get("prop_count", 0)) >= 7,
				"Hero diorama loaded >= 7 sculpted props (got %d)" % int(idle_stats.get("prop_count", 0)))
		_check(int(idle_stats.get("shell_count", 0)) >= 16,
				"Hero diorama spawned >= 16 brass shells (got %d)" % int(idle_stats.get("shell_count", 0)))
		_check(int(idle_stats.get("on_deck_count", 0)) >= 12,
				"Hero diorama starts with >= 12 shells on deck (got %d)" % int(idle_stats.get("on_deck_count", 0)))

	await _save_shot("menu_diorama_idle.png")

	# Close-up showcase framing to inspect Blender crate, ammo cans, Pelican, sandbags, radio & shells
	if hero_cam != null:
		var saved_xf := hero_cam.global_transform
		var cam_dir := Vector3(0.48, 0.25, 0.76).normalized()
		var back_xz := Vector3(-cam_dir.x, 0.0, -cam_dir.z).normalized()
		hero_cam.fov = 36.0
		hero_cam.look_at_from_position(
			Vector3(0.0, 0.26, 0.0) + cam_dir * 1.18,
			back_xz * 0.56 + Vector3(0.0, -0.09, 0.0),
			Vector3.UP
		)
		await _save_shot("menu_diorama_closeup_props.png")
		hero_cam.fov = 30.0
		hero_cam.global_transform = saved_xf
		menu.call("_fit_hero_camera")
		await get_tree().process_frame

	# Simulate realistic finger swipe across hero viewport
	var min_seen_y := 999.0
	if hero_container != null and hero_diorama != null:
		var rect := hero_container.get_global_rect()
		var pos := rect.get_center()
		var touch_down := InputEventScreenTouch.new()
		touch_down.index = 0
		touch_down.pressed = true
		touch_down.position = pos
		menu.call("_on_hero_gui_input", touch_down)

		for step_i in range(22):
			var drag := InputEventScreenDrag.new()
			drag.index = 0
			pos.x += 18.0
			pos.y += 1.0
			drag.position = pos
			drag.relative = Vector2(18.0, 1.0)
			menu.call("_on_hero_gui_input", drag)
			await get_tree().process_frame
			var st_mid: Dictionary = hero_diorama.call("get_debug_stats")
			min_seen_y = minf(min_seen_y, float(st_mid.get("min_shell_y", 999.0)))
			if step_i == 10:
				await _save_shot("menu_diorama_swipe_rolling.png")
			elif step_i == 14:
				await _save_shot("menu_diorama_shells_falling.png")

		var touch_up := InputEventScreenTouch.new()
		touch_up.index = 0
		touch_up.pressed = false
		touch_up.position = pos
		menu.call("_on_hero_gui_input", touch_up)

		# Let momentum carry shells right over the edge and tumble down
		for f_i in range(22):
			await get_tree().process_frame
			var st_fall: Dictionary = hero_diorama.call("get_debug_stats")
			min_seen_y = minf(min_seen_y, float(st_fall.get("min_shell_y", 999.0)))

		var post_stats: Dictionary = hero_diorama.call("get_debug_stats")
		print("[DIORAMA_QA] post-swipe stats=", post_stats, " min_seen_y=", min_seen_y)
		_check(float(post_stats.get("total_roll_rad", 0.0)) > 4.0,
				"Swipe caused brass casings to physically roll (roll_rad=%.2f)" % float(post_stats.get("total_roll_rad", 0.0)))
		_check(int(post_stats.get("total_fallen_events", 0)) >= 3,
				"Swipe knocked >= 3 casings off the turntable edge (events=%d)" % int(post_stats.get("total_fallen_events", 0)))
		_check(min_seen_y < -0.2045 - 0.10,
				"Fallen casings dropped below deck (-0.305 > %.3f)" % min_seen_y)

		# Wait for smooth replenishment so subsequent swipes always have brass on deck
		await get_tree().create_timer(2.8).timeout
		var replenish_stats: Dictionary = hero_diorama.call("get_debug_stats")
		print("[DIORAMA_QA] replenish stats=", replenish_stats)
		_check(int(replenish_stats.get("on_deck_count", 0)) >= 10,
				"Deck shells smoothly replenished after tumble (on_deck=%d)" % int(replenish_stats.get("on_deck_count", 0)))

	# Check alternate airframe (Chaklun Jet preset 9) still frames cleanly with diorama behind
	Global.drone_preset = 9
	DroneCatalog.apply(9)
	menu.call("_load_hero_model", 9)
	for _w2 in range(100):
		await get_tree().create_timer(0.05).timeout
		if hero_holder != null and hero_holder.get_child_count() > 0:
			var ch2 := hero_holder.get_child(hero_holder.get_child_count() - 1) as Node3D
			if ch2 != null and ch2.visible:
				break
	await get_tree().create_timer(0.2).timeout
	await _save_shot("menu_diorama_alt_drone.png")

	# Check Hangar tab diorama and unified 13-drone list (including Uman freestyle drones 10..12)
	menu.call("_show", "drone")
	await get_tree().create_timer(0.5).timeout
	var hangar_diorama := menu.get("_hangar_diorama") as Node3D
	_check(hangar_diorama != null, "_hangar_diorama attached")
	if hangar_diorama != null:
		var h_stats: Dictionary = hangar_diorama.call("get_debug_stats")
		_check(int(h_stats.get("prop_count", 0)) >= 7,
				"Hangar diorama loaded >= 7 sculpted props (got %d)" % int(h_stats.get("prop_count", 0)))
	var list_box := menu.get("_hangar_list_container") as VBoxContainer
	_check(list_box != null and list_box.get_child_count() == 13,
			"General Hangar displays all 13 drones together (got %d)" % (list_box.get_child_count() if list_box != null else -1))
	await _save_shot("menu_diorama_hangar.png")

	# Verify selecting Uman freestyle drone (preset 10 «ДЖМІЛЬ-3») in general hangar works on non-Uman maps in Freestyle mode
	menu.set("_selected_map", "industrial")
	menu.set("_selected_mode", Global.PlayMode.COMBAT)
	menu.set("_hangar_preview_idx", 10)
	menu.call("_on_hangar_choose_pressed")
	await get_tree().create_timer(0.1).timeout
	_check(Global.drone_preset == 10,
			"Chosen freestyle drone 10 active in general hangar (got %d)" % Global.drone_preset)
	_check(str(menu.get("_selected_map")) == "industrial",
			"Freestyle drone preserves non-Uman map selection (got %s)" % str(menu.get("_selected_map")))
	_check(int(menu.get("_selected_mode")) == Global.PlayMode.TRAINING,
			"Freestyle drone automatically locks mode to Freestyle/TRAINING (got %d)" % int(menu.get("_selected_mode")))
	menu.call("_select_map", "wetlands")
	_check(Global.drone_preset == 10 and int(menu.get("_selected_mode")) == Global.PlayMode.TRAINING,
			"Switching map to wetlands keeps freestyle drone 10 in Freestyle mode")

	get_tree().current_scene = null
	menu.queue_free()
	await get_tree().process_frame

	# Sanity check Desktop MainMenu.tscn attaches 360 diorama without errors
	OS.unset_environment("MOBILE_UI")
	OS.unset_environment("TOUCH_CONTROLS")
	var desktop_packed := load("res://GUI/MainMenu.tscn") as PackedScene
	_check(desktop_packed != null, "Loaded desktop MainMenu.tscn")
	if desktop_packed != null:
		var dm := desktop_packed.instantiate()
		get_tree().root.add_child(dm)
		get_tree().current_scene = dm
		await get_tree().create_timer(0.3).timeout
		var d_diorama := dm.get("_diorama") as Node3D
		_check(d_diorama != null, "Desktop MainMenu attached _diorama")
		if d_diorama != null:
			var ds: Dictionary = d_diorama.call("get_debug_stats")
			_check(int(ds.get("prop_count", 0)) >= 6,
					"Desktop MainMenu diorama loaded >= 6 props (got %d)" % int(ds.get("prop_count", 0)))
		await _save_shot("desktop_mainmenu_diorama.png")
		get_tree().current_scene = null
		dm.queue_free()
		await get_tree().process_frame

	# Restore saved global settings
	Global.drone_preset = saved_preset
	Global.play_mode = saved_mode
	Global.menu_settings = saved_settings
	Global.save_menu_settings()

	print("[DIORAMA_QA] SUMMARY checks=", _checks, " fails=", _fails)
	get_tree().quit(0 if _fails == 0 else 1)
