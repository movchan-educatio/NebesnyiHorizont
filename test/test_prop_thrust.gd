extends Node


func _ready() -> void:
	var packed := load("res://drone/drones/Drone1.tscn") as PackedScene
	if packed == null:
		push_error("Could not load Drone1.tscn")
		get_tree().quit(1)
		return
	var drone := packed.instantiate() as Drone
	add_child(drone)
	await get_tree().physics_frame
	DroneCatalog.apply_to_drone(drone, 0)
	drone.global_position = Vector3(0.0, 50.0, 0.0)
	await get_tree().physics_frame

	var weight := drone.mass * 9.81
	print("[THRUST-CAL] preset=", DroneCatalog.preset(0)["name"],
		" mass=", drone.mass, "kg target_twr=", drone.target_max_twr,
		" physical_twr=", drone.physical_max_twr, " weight=", weight, "N")
	var curve_twr: float = drone.physical_max_twr if drone.physical_max_twr > 0.01 else drone.target_max_twr
	drone.flight_controller.configure_throttle_curve(true, curve_twr)
	var hover_pwm: float = drone.flight_controller.throttle_to_motor_pwm(0.45)
	var hover_thrust := 0.0
	for motor in drone.motors:
		motor.set_rpm(float(motor.MAX_RPM) * hover_pwm)
		motor.propeller.set_velocity(Vector3.ZERO)
		motor.propeller.update_forces()
		hover_thrust += maxf(float(motor.propeller.forces[0].y), 0.0)
	var hover_twr := hover_thrust / maxf(weight, 0.001)
	print("[THRUST-CAL] hover stick=0.45 maps to PWM=", hover_pwm,
		" actual_twr=", hover_twr)
	assert(absf(hover_twr - 1.0) < 0.12,
		"0.45 throttle must map to approximately one-g thrust")

	for pwm in [0.25, 0.30, 0.35, 0.40, 0.45, 0.50, 0.60, 1.0]:
		var total_thrust := 0.0
		for motor in drone.motors:
			motor.set_rpm(float(motor.MAX_RPM) * float(pwm))
			motor.propeller.set_velocity(Vector3.ZERO)
			motor.propeller.update_forces()
			total_thrust += maxf(float(motor.propeller.forces[0].y), 0.0)
		print("[THRUST-CAL] pwm=", pwm, " thrust=", total_thrust,
			"N twr=", total_thrust / maxf(weight, 0.001))

	get_tree().quit()
