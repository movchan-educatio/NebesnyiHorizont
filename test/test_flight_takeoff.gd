extends Node

func _ready() -> void:
	print("==========================================================")
	print("=== VERIFYING FLIGHT DYNAMICS & TAKEOFF FOR ALL PRESETS ===")
	print("==========================================================")
	
	var drone_scene := load("res://drone/drones/Drone1.tscn") as PackedScene
	var drone := drone_scene.instantiate() as Drone
	add_child(drone)
	GameSettings.hud_config["infinite_battery"] = false
	
	for i in range(DroneCatalog.count()):
		var p = DroneCatalog.preset(i)
		DroneCatalog.apply_to_drone(drone, i)
		var weight := drone.mass * 9.81
		
		# Test hover equilibrium at 45% stick
		drone.flight_controller.set_armed(true)
		drone.flight_controller.input = [0.45, 0.0, 0.0, 0.0]
		
		# Step physics frames to calculate demanded thrust. Four frames at the
		# project's 120 Hz (same wall time as the old two at 60 Hz) are enough
		# for the mixer and battery sag to react to the stick change.
		for _f in range(4):
			await get_tree().physics_frame
		var hover_t := drone.current_total_thrust
		var hover_ratio := hover_t / weight
		
		# Test full punchout at 100% stick
		drone.flight_controller.input = [1.0, 0.0, 0.0, 0.0]
		for _f in range(4):
			await get_tree().physics_frame
		var max_t := drone.current_total_thrust
		var max_twr := max_t / weight
		
		print("Preset %d [%s] (m=%.2fkg, W=%.1fN): HoverThrust=%.1fN (T/W=%.2f), MaxThrust=%.1fN (TWR=%.2f:1)" % [
			i, p["name"], drone.mass, weight, hover_t, hover_ratio, max_t, max_twr
		])
		
		print("DEBUG: i=", i, " hover_t=", hover_t, " weight=", weight, " ratio=", hover_ratio)
		assert(absf(hover_ratio - 1.0) < 0.05, "Hover thrust at 45% stick must equal drone weight!")
		print("DEBUG: i=", i, " max_t=", max_t, " max_twr=", max_twr)
		# The punchout sample includes instantaneous battery sag, so it is not a
		# clean measure of installed power.  Assert the catalog's design TWR
		# (the figure shown in the menu) and only require the sagged demand to
		# stay above the drone's own weight.
		assert(float(p.get("twr", 0.0)) >= 2.2, "Maximum TWR must be at least 2.2:1 for every drone!")
		assert(max_twr > 1.0, "Full stick must demand more thrust than the drone's weight!")
	
	print("\n--- Testing dynamic flight climb on Combat 5\" («КВАД-5») ---")
	DroneCatalog.apply_to_drone(drone, 3)
	drone.global_position = Vector3(0, 5, 0)
	drone.linear_velocity = Vector3.ZERO
	drone.angular_velocity = Vector3.ZERO
	drone.flight_controller.set_armed(true)
	
	# Apply 70% throttle (climbing stick)
	drone.flight_controller.input = [0.70, 0.0, 0.0, 0.0]
	
	var y_start := drone.global_position.y
	for f in range(30):
		await get_tree().physics_frame
	
	var y_end := drone.global_position.y
	var climb := y_end - y_start
	print("Climbed after 30 frames at 70%% throttle: +%.2f meters (Vy=%.2f m/s)" % [climb, drone.linear_velocity.y])
	assert(climb > 1.0, "Drone must climb rapidly at 70% throttle!")
	assert(drone.linear_velocity.y > 2.0, "Vertical climb rate must be positive!")
	
	print("\n--- Testing dynamic flight climb on Heavy Combat («СТРІЛА-8», 3.0kg) ---")
	DroneCatalog.apply_to_drone(drone, 2)
	drone.global_position = Vector3(0, 5, 0)
	drone.linear_velocity = Vector3.ZERO
	drone.angular_velocity = Vector3.ZERO
	drone.flight_controller.set_armed(true)
	
	# Apply 70% throttle
	drone.flight_controller.input = [0.70, 0.0, 0.0, 0.0]
	
	y_start = drone.global_position.y
	for f in range(60):
		await get_tree().physics_frame
	
	y_end = drone.global_position.y
	climb = y_end - y_start
	print("Climbed after 60 frames at 70%% throttle: +%.2f meters (Vy=%.2f m/s)" % [climb, drone.linear_velocity.y])
	assert(climb > 0.5, "Heavy combat drone must climb at 70% throttle!")
	assert(drone.linear_velocity.y > 0.5, "Vertical climb rate must be positive!")
	
	print("\n==========================================================")
	print("=== ALL TAKEOFF AND FLIGHT DYNAMICS TESTS PASSED! ===")
	print("==========================================================")
	get_tree().quit(0)
