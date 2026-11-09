extends Node

## QA: land on the factory hall roof (real trimesh, not a test platform).

func _ready() -> void:
	Global.play_mode = Global.PlayMode.COMBAT
	Global.special_mission = 1
	Global.combat_mission = 1
	Global.drone_preset = 6
	var packed := load("res://sceneries/IndustrialLevel.tscn") as PackedScene
	var level := packed.instantiate()
	add_child(level)
	await get_tree().create_timer(5.0).timeout
	var drone := level.get_node_or_null("Drone") as Drone
	if drone == null:
		print("[ROOFLAND] FAIL no drone")
		get_tree().quit(1)
		return
	var space: PhysicsDirectSpaceState3D = level.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
			Vector3(-200.0, 120.0, -175.0), Vector3(-200.0, -20.0, -175.0))
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		print("[ROOFLAND] FAIL no roof hit")
		get_tree().quit(1)
		return
	var roof: Vector3 = hit["position"]
	print("[ROOFLAND] roof=", roof, " normal=", hit["normal"])
	var crashed := [false]
	drone.crashed.connect(func(_r): crashed[0] = true)
	drone.freeze = false
	drone.global_position = roof + Vector3(0.0, 6.0, 0.0)
	drone.linear_velocity = Vector3.ZERO
	drone.angular_velocity = Vector3.ZERO
	drone.flight_controller.request_arm(true)
	var settled := false
	for i in range(360):
		await get_tree().physics_frame
		if drone.freeze and drone.global_position.y > roof.y - 1.0:
			settled = true
			break
	var pos := drone.global_position
	var ok: bool = settled and not crashed[0] and absf(pos.y - roof.y) < 1.5 \
			and Vector2(pos.x - roof.x, pos.z - roof.z).length() < 2.5
	print("[ROOFLAND] pos=", pos, " settled=", settled, " crashed=", crashed[0],
			" -> ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
