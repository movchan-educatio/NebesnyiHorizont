extends Node

## QA: exercise the three remaining quality presets through the same Graphics
## API the menu uses, then verify the stored settings and QualityManager params.


func _ready() -> void:
	var low_ok := await _check(0, 0.67, 0.40, 118.0, false, 120,
			Graphics.Shadows.LOW)
	var med_ok := await _check(1, 0.8, 0.55, 118.0, false, 120,
			Graphics.Shadows.MEDIUM)
	var high_ok := await _check(2, 1.0, 1.0, 60.0, true, 120,
			Graphics.Shadows.HIGH)
	print("[PRESETTEST] low=", low_ok, " medium=", med_ok, " high=", high_ok,
			" -> ", "PASS" if (low_ok and med_ok and high_ok) else "FAIL")
	# Leave the default profile for the next normal launch.
	Graphics.apply_quality_preset(Graphics.QualityPreset.LOW)
	get_tree().quit(0 if (low_ok and med_ok and high_ok) else 1)


func _check(index: int, scale: float, min_scale: float, target: float,
		ssao: bool, fps: int, shadow: int) -> bool:
	Graphics.apply_quality_preset(index)
	await get_tree().process_frame
	var p := QualityManager.params()
	var ok := int(Graphics.graphics_settings["quality"]) == index \
			and QualityManager.get_active_level() == index \
			and int(Graphics.graphics_settings["fps_limit"]) == fps \
			and int(Graphics.graphics_settings["shadows"]) == shadow \
			and is_equal_approx(float(p["scale_3d"]), scale) \
			and is_equal_approx(float(p["min_scale"]), min_scale) \
			and is_equal_approx(float(p["target_fps"]), target) \
			and bool(p["ssao"]) == ssao
	print("[PRESETTEST] idx=", index, " quality=",
			Graphics.graphics_settings["quality"], " level=",
			QualityManager.get_active_level(), " scale=", p["scale_3d"],
			" min=", p["min_scale"], " ssao=", p["ssao"], " shadows=",
			Graphics.graphics_settings["shadows"], " -> ",
			"PASS" if ok else "FAIL")
	return ok
