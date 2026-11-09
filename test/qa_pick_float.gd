extends Node

## QA: identify the objects the player sees near the three floating "chimneys"
## by raycasting through the same camera pose as the screenshot.

func _ready() -> void:
	Global.play_mode = Global.PlayMode.COMBAT
	Global.special_mission = 1
	Global.combat_mission = 1
	Global.drone_preset = 6
	var packed := load("res://sceneries/IndustrialLevel.tscn") as PackedScene
	var level := packed.instantiate()
	add_child(level)
	await get_tree().create_timer(5.0).timeout
	get_viewport().size = Vector2i(1600, 900)
	var cam := Camera3D.new()
	cam.fov = 90.0
	cam.near = 0.05
	cam.far = 4000.0
	level.add_child(cam)
	cam.global_position = Vector3(-80.0, 25.0, -100.0)
	cam.look_at(Vector3(-138.0, 15.0, -146.0), Vector3.UP)
	cam.current = true
	await get_tree().process_frame
	var space: PhysicsDirectSpaceState3D = level.get_world_3d().direct_space_state
	for px in [683, 750, 860, 555, 597, 1013]:
		for py in [220, 255, 280]:
			var origin := cam.project_ray_origin(Vector2(px, py))
			var dir := cam.project_ray_normal(Vector2(px, py))
			var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 800.0)
			q.collide_with_areas = true
			var hit: Dictionary = space.intersect_ray(q)
			if not hit.is_empty():
				var col := hit["collider"] as Node
				print("[PICK] px=%d,%d hit=%s path=%s dist=%.1f" % [
					px, py, str(hit["position"]),
					String(level.get_path_to(col)) if col != null else "?",
					origin.distance_to(hit["position"])])
	get_tree().quit()
