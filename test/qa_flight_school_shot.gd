extends Node

## Visual QA for the interactive tutorial card and its help sheet.

var _failures := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	OS.set_environment("DRONE_TUTORIAL_SKIP_BRIEF", "1")
	Global.play_mode = Global.PlayMode.TUTORIAL
	Global.special_mission = 0
	Global.drone_preset = 0
	var packed := load("res://sceneries/VillageLevel.tscn") as PackedScene
	if packed == null:
		push_error("[FLIGHT_SCHOOL_SHOT] VillageLevel failed to load")
		get_tree().quit(1)
		return
	var level := packed.instantiate() as Node3D
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	await get_tree().create_timer(5.0).timeout
	var school = level.get("_flight_school")
	if school == null or school.get("hud_container") == null:
		_failures += 1
		push_error("[FLIGHT_SCHOOL_SHOT] tutorial card did not initialize")
	else:
		print("[FLIGHT_SCHOOL_SHOT] PASS step=", school.get("current_step"),
				" card_size=", school.get("panel_card").size)
		var output := OS.get_environment("TRAINING_SHOT_DIR")
		if not output.is_empty() and DisplayServer.get_name() != "headless":
			DirAccess.make_dir_recursive_absolute(output)
			await _capture(output.path_join("flight_school_course.png"))
			if school.has_method("open_help"):
				school.call("open_help")
				await get_tree().process_frame
				await _capture(output.path_join("flight_school_help.png"))
				school.call("close_help")
	print("[FLIGHT_SCHOOL_SHOT] failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	if err != OK:
		_failures += 1
		push_error("[FLIGHT_SCHOOL_SHOT] failed to save %s (%d)" % [path, err])
	else:
		print("[FLIGHT_SCHOOL_SHOT] saved ", path)
