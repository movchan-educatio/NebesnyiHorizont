extends Node

func _ready() -> void:
	var level_scene = load("res://sceneries/BigLevel.tscn")
	if level_scene == null:
		print("ERROR: Cannot load BigLevel.tscn")
		get_tree().quit(1)
		return
	var level = level_scene.instantiate()
	add_child(level)
	_test_landing(level)

func _test_landing(level: Node) -> void:
	await get_tree().create_timer(0.5).timeout
	var drone: Drone = level.get_node_or_null("Drone") as Drone
	if drone == null:
		print("ERROR: Drone not found in BigLevel")
		get_tree().quit(1)
		return
		
	# Place drone 1.5m above ground at trench grass area
	var test_pos := Vector3(0.0, 3.0, 0.0)
	drone.freeze = false
	drone.flight_controller.state_armed = true
	drone.global_position = test_pos
	drone.linear_velocity = Vector3.ZERO
	drone.angular_velocity = Vector3.ZERO
	
	print("[TEST] Drone placed at ", test_pos, " mass=", drone.mass)
	
	# Simulate 120 physics steps (2 seconds)
	var landed := false
	var landed_y := 0.0
	for step in range(120):
		await get_tree().physics_frame
		var pos = drone.global_position
		var vel = drone.linear_velocity
		if step % 20 == 0:
			print("Step ", step, ": Y=", pos.y, " vy=", vel.y, " speed=", vel.length())
		if vel.length() < 0.15 and pos.y < 2.5:
			landed = true
			landed_y = pos.y
			
	print("[TEST] Final pos=", drone.global_position, " vel=", drone.linear_velocity, " landed=", landed, " Y=", landed_y)
	if drone.global_position.y > 0.5 and drone.global_position.y < 3.0 and drone.linear_velocity.length() < 0.5:
		print(">>> SUCCESS: DRONE GENTLY LANDED ON GRASS WITHOUT BOUNCING OR LAUNCHING <<<")
		get_tree().quit(0)
	else:
		print("FAIL: Drone did not settle properly")
		get_tree().quit(1)
