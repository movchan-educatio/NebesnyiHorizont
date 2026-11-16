extends Node

## Valley-only regression audit for the legacy training map's generated gates.
## The frontline map audit lives in qa_mobile_map_views.gd.

const CLEARANCE_SIZE := Vector3(18.0, 18.0, 18.0)

var _failures := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	Global.play_mode = Global.PlayMode.TRAINING
	Global.special_mission = 0
	Global.drone_preset = 0
	var packed := load("res://sceneries/BigLevel.tscn") as PackedScene
	if packed == null:
		push_error("[VALLEY_TRAINING] BigLevel.tscn failed to load")
		get_tree().quit(1)
		return
	var level := packed.instantiate() as Node3D
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	await get_tree().create_timer(5.0).timeout
	var ring_value: Variant = level.get("_training_rings")
	if not (ring_value is Array) or (ring_value as Array).size() != 24:
		_failures += 1
		push_error("[VALLEY_TRAINING] expected 24 rings")
	else:
		var rings: Array = ring_value
		var drone := level.get_node_or_null("Drone") as CollisionObject3D
		var space := level.get_world_3d().direct_space_state
		var clearance := BoxShape3D.new()
		clearance.size = CLEARANCE_SIZE
		var overlaps := 0
		var min_height := INF
		var max_height := -INF
		for i in range(rings.size()):
			var ring := rings[i] as Area3D
			if ring == null or not is_instance_valid(ring):
				overlaps += 1
				continue
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = clearance
			query.transform = Transform3D(Basis.IDENTITY, ring.global_position)
			query.collision_mask = 1
			query.collide_with_bodies = true
			query.collide_with_areas = false
			query.exclude = [drone.get_rid()] if drone != null else []
			if not space.intersect_shape(query, 12).is_empty():
				overlaps += 1
				push_warning("[VALLEY_TRAINING] ring %d intersects a collider at %s"
						% [i + 1, str(ring.global_position)])
			var ground := float(level.call("_find_ground_y",
					ring.global_position.x, ring.global_position.z))
			var height := ring.global_position.y - ground
			min_height = minf(min_height, height)
			max_height = maxf(max_height, height)
		if overlaps > 0:
			_failures += overlaps
		else:
			print("[VALLEY_TRAINING] PASS 24 clear gates; AGL range=",
					snappedf(min_height, 0.1), "..", snappedf(max_height, 0.1), " m")
		await _capture_training_view(level, rings)
	print("[VALLEY_TRAINING] failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _capture_training_view(level: Node3D, rings: Array) -> void:
	var output := OS.get_environment("TRAINING_SHOT_DIR")
	if output.is_empty() or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(output)
	var fpv := level.get_node_or_null("Drone/FPVCamera") as Camera3D
	if fpv != null:
		fpv.current = true
		await RenderingServer.frame_post_draw
		var fpv_image := get_viewport().get_texture().get_image()
		fpv_image.save_png(output.path_join("valley_training_fpv.png"))
	var ring := rings[0] as Area3D
	if ring == null:
		return
	var camera := Camera3D.new()
	camera.name = "TrainingGateQACamera"
	camera.fov = 66.0
	camera.far = 1800.0
	level.add_child(camera)
	var normal := ring.global_transform.basis.z.normalized()
	camera.global_position = ring.global_position + normal * 27.0 + Vector3.UP * 2.0
	camera.look_at(ring.global_position, Vector3.UP)
	await get_tree().process_frame
	camera.current = true
	await RenderingServer.frame_post_draw
	var ring_image := get_viewport().get_texture().get_image()
	ring_image.save_png(output.path_join("valley_training_ring.png"))
