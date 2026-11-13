extends Node

## Regression: mobile fixed-wing presets (7/8/9) must keep a clean FPV lens.
## The old "show airframe" framing put the lens at wing height on the high-wing
## Leleka/Furia, so the wing filled the centre of the screen (owner video
## 06:40-07:10).  This QA loads the real level per preset, asserts the drone
## model is hidden in FPV and saves a screenshot for visual review.
## Run: MOBILE_FIXED_WING_SHOT_DIR=<dir> ... qa_mobile_fixed_wing_fpv.tscn
const TEST_NAME := "MOBILE_FIXED_WING_FPV"
const PRESETS := [7, 8, 9]
var _failures := 0


func _ready() -> void:
	OS.set_environment("MOBILE_UI", "1")
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	print("[", TEST_NAME, "] ", "PASS " if ok else "FAIL ", label)
	if not ok:
		_failures += 1


func _run() -> void:
	var output := OS.get_environment("MOBILE_FIXED_WING_SHOT_DIR")
	if output.is_empty():
		output = "user://fixed_wing_fpv"
	DirAccess.make_dir_recursive_absolute(output)
	Global.play_mode = Global.PlayMode.TRAINING
	Global.special_mission = 0
	for idx in PRESETS:
		Global.drone_preset = idx
		var preset := DroneCatalog.preset(idx)
		_check(bool(preset.get("fpv_hide_model", false))
				and not bool(preset.get("fpv_show_airframe", false)),
				"preset %d keeps the clean FPV lens" % idx)
		var packed := load("res://sceneries/SteppeLevel.tscn") as PackedScene
		if packed == null:
			_check(false, "SteppeLevel loads")
			break
		var level := packed.instantiate() as Node3D
		get_tree().root.add_child(level)
		get_tree().current_scene = level
		await get_tree().create_timer(5.0).timeout
		var model_root := level.get("_model_root") as Node3D
		_check(model_root != null and not model_root.visible,
				"preset %d hides the drone model in FPV" % idx)
		var cam := level.get_node_or_null("Drone/FPVCamera") as Camera3D
		_check(cam != null and cam.position.distance_to(
				preset.get("fpv_cam_pos", Vector3.ZERO)) < 0.05,
				"preset %d camera sits at the preset nose position" % idx)
		if cam != null and DisplayServer.get_name() != "headless":
			cam.current = true
			await get_tree().process_frame
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			var path := output.path_join("fixed_wing_%d.png" % idx)
			var err := img.save_png(path)
			_check(err == OK, "preset %d screenshot saved (%s)" % [idx, path])
		level.queue_free()
		await get_tree().process_frame
	print("[", TEST_NAME, "] failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)
