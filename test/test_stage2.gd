extends Node

func _ready() -> void:
	print("==================================================")
	print("=== RUNNING STAGE 2 TEST: 4-MOTOR THRUST & TWR ===")
	print("==================================================")
	
	var catalog := DroneCatalog
	var drone_scene := load("res://drone/drones/Drone1.tscn") as PackedScene
	assert(drone_scene != null, "Drone1.tscn must load")
	var drone := drone_scene.instantiate() as Drone
	add_child(drone)
	
	# Verify 4 motors
	assert(drone.motors.size() == 4, "Drone must have exactly 4 motors")
	print("[TEST] 4 Motors verified at coordinates:")
	for i in range(4):
		var m: Node3D = drone.motors[i]
		print(" Motor %d pos: %s, CW: %s" % [i + 1, m.transform.origin, m.clockwise])
	
	# Test 1: Freestyle 5" («ГОЛКА») - high TWR (8:1 - 10:1)
	catalog.apply_to_drone(drone, 0)
	var holka_mass: float = drone.mass
	var holka_weight: float = holka_mass * 9.81
	
	# Set 100% throttle on all 4 motors
	var total_max_thrust_holka := 0.0
	for m in drone.motors:
		m.set_rpm(m.MAX_RPM)
		m.propeller.update_forces()
		total_max_thrust_holka += m.propeller.forces[0].y
	
	var twr_holka := total_max_thrust_holka / holka_weight
	print("[TEST] «ГОЛКА» (0.60kg): Weight = %.2f N, Total Max Thrust = %.2f N, TWR = %.2f:1" % [
		holka_weight, total_max_thrust_holka, twr_holka
	])
	assert(twr_holka >= 7.5 and twr_holka <= 10.5, "Holka TWR must be between 7.5:1 and 10.5:1")
	
	# Test 2: Heavy Combat 8.5" («СТРІЛА-8» with 1.4kg payload = 3.0kg) - combat TWR (~2.7:1)
	catalog.apply_to_drone(drone, 7)
	var strila_mass: float = drone.mass
	var strila_weight: float = strila_mass * 9.81
	
	var total_max_thrust_strila := 0.0
	for m in drone.motors:
		m.set_rpm(m.MAX_RPM)
		m.propeller.update_forces()
		total_max_thrust_strila += m.propeller.forces[0].y
	
	var twr_strila := total_max_thrust_strila / strila_weight
	print("[TEST] «СТРІЛА-8» (3.00kg): Weight = %.2f N, Total Max Thrust = %.2f N, TWR = %.2f:1" % [
		strila_weight, total_max_thrust_strila, twr_strila
	])
	assert(twr_strila >= 2.2 and twr_strila <= 4.5, "Armed Strila-8 TWR must be between 2.2:1 and 4.5:1")
	
	# Test 3: Differential torque verification (differential thrust around CoG)
	# Set rear motors (3 & 4) to 100%, front motors (1 & 2) to 50% -> should pitch nose DOWN (-X torque)
	drone.motors[0].set_rpm(drone.motors[0].MAX_RPM * 0.5)
	drone.motors[1].set_rpm(drone.motors[1].MAX_RPM * 0.5)
	drone.motors[2].set_rpm(drone.motors[2].MAX_RPM * 1.0)
	drone.motors[3].set_rpm(drone.motors[3].MAX_RPM * 1.0)
	
	var diff_torque := Vector3.ZERO
	for m in drone.motors:
		m.propeller.update_forces()
		var prop_force: Vector3 = m.propeller.forces[0]
		var r_arm: Vector3 = m.transform.origin - drone.center_of_mass
		diff_torque += r_arm.cross(prop_force)
	
	print("[TEST] Differential pitch torque (rear 100%%, front 50%%): %s" % diff_torque)
	assert(diff_torque.x < -0.1, "Pitch torque must push nose down with rear motors stronger")
	
	# Cleanup
	drone.queue_free()
	print("==================================================")
	print("=== STAGE 2 TEST PASSED SUCCESSFULLY! ===")
	print("==================================================")
	get_tree().quit(0)
