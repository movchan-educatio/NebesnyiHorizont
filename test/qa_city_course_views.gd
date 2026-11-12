extends Node

## QA for the two legacy city scenes that are not yet in the mobile menu.
## Loads CityLevel and CourseLevel, verifies their scripts/FPV camera, captures
## spawn frames and probes a straight corridor at three heights for blocked
## segments. Usage: MOBILE_MAP_SHOT_DIR=<dir> ... qa_city_course_views.tscn
const SCENES := ["CityLevel", "CourseLevel"]
var _failures := 0


func _ready() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	print("[CITY_COURSE_QA] ", "PASS " if ok else "FAIL ", label)
	if not ok:
		_failures += 1


func _run() -> void:
	var output := OS.get_environment("MOBILE_MAP_SHOT_DIR")
	if output.is_empty():
		push_error("[CITY_COURSE_QA] missing MOBILE_MAP_SHOT_DIR")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output)
	for scene_name in SCENES:
		var packed := load("res://sceneries/%s.tscn" % scene_name) as PackedScene
		if packed == null:
			_check(false, scene_name + " scene loads")
			continue
		var level := packed.instantiate() as Node3D
		get_tree().root.add_child(level)
		get_tree().current_scene = level
		await get_tree().create_timer(4.0).timeout
		_check(level.get_script() != null, scene_name + " script is present")
		var drone := level.get_node_or_null("Drone") as Node3D
		var fpv := level.get_node_or_null("Drone/FPVCamera") as Camera3D
		var city := level.get_node_or_null("City") as Node3D
		_check(drone != null and fpv != null, scene_name + " has Drone/FPVCamera")
		_check(city != null, scene_name + " has the City environment node")
		if fpv != null:
			await _capture(output.path_join(scene_name.to_lower() + "_spawn.png"), fpv)
		# Straight 200 m corridor north from the spawn area, probed at 8/20/40 m.
		if drone != null:
			var origin := drone.global_position
			var space := level.get_world_3d().direct_space_state
			var steps := 20
			for height in [8.0, 20.0, 40.0]:
				var blocked := 0
				for i in range(steps):
					var a := origin + Vector3(0, height, float(i) * 10.0)
					var b := origin + Vector3(0, height, float(i + 1) * 10.0)
					var query := PhysicsRayQueryParameters3D.create(a, b)
					query.collision_mask = 1
					var hit := space.intersect_ray(query)
					if not hit.is_empty():
						var normal: Vector3 = hit.get("normal", Vector3.UP)
						if normal.y < 0.65:
							blocked += 1
				var ratio := float(blocked) / float(steps)
				print("[CITY_COURSE_QA] ", scene_name, " corridor h=", height,
						" blocked=", blocked, "/", steps, " ratio=", snappedf(ratio, 0.01))
				if ratio >= 0.5:
					_failures += 1
		level.queue_free()
		await get_tree().process_frame
	print("[CITY_COURSE_QA] failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _capture(path: String, fpv: Camera3D) -> void:
	fpv.current = true
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	if err != OK:
		_failures += 1
		push_error("[CITY_COURSE_QA] save failed: %s (%d)" % [path, err])
	else:
		print("[CITY_COURSE_QA] saved ", path)
