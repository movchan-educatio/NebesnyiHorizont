extends Node

## Headless smoke test: every play mode must build its objectives on a
## frontline map without script errors.  Loads the real IndustrialLevel once
## per mode and checks the mode-specific root nodes/arrays.

const LEVEL := "res://sceneries/IndustrialLevel.tscn"


func _ready() -> void:
	var fails := 0
	var checks := [
		[Global.PlayMode.TUTORIAL, "TUTORIAL"],
		[Global.PlayMode.TRAINING, "TRAINING"],
		[Global.PlayMode.COMBAT, "COMBAT"],
	]
	for entry in checks:
		var mode: int = int(entry[0])
		var name: String = String(entry[1])
		Global.play_mode = mode
		Global.special_mission = 0
		Global.combat_mission = 1
		var packed := load(LEVEL) as PackedScene
		var level := packed.instantiate()
		add_child(level)
		await get_tree().create_timer(4.0).timeout
		var ok := true
		var detail := ""
		match mode:
			Global.PlayMode.COMBAT:
				var targets := int(level.get("_mission_targets_total"))
				var inf: Array = level.get("_infantry_units")
				detail = "targets=%d infantry=%d" % [targets, inf.size()]
				ok = targets >= 2 and inf.size() >= 1
			Global.PlayMode.TRAINING:
				var rings: Array = level.get("_training_rings")
				var vis_count := 0
				var active_monitoring := 0
				for r in rings:
					var area := r as Area3D
					if is_instance_valid(area) and area.visible:
						vis_count += 1
					if is_instance_valid(area) and area.monitoring:
						active_monitoring += 1
				detail = "rings=%d visible=%d monitoring=%d" % [rings.size(), vis_count, active_monitoring]
				ok = rings.size() == 24 and vis_count == 24 and active_monitoring == 1
			Global.PlayMode.TUTORIAL:
				var school = level.get("_flight_school")
				detail = "flight_school=%s" % str(school != null)
				ok = school != null
		if not ok:
			fails += 1
		print("[MODE] %-8s %s %s" % [name, "PASS" if ok else "FAIL", detail])
		level.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	print("[MODE] fails=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
