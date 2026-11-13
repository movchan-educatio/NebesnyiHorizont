extends Node


var drone: Drone = null
var elapsed := 0.0


func _ready() -> void:
	var packed := load("res://drone/drones/Drone1.tscn") as PackedScene
	drone = packed.instantiate() as Drone
	add_child(drone)
	GameSettings.hud_config["infinite_battery"] = false
	DroneCatalog.apply_to_drone(drone, 3)
	drone.global_position = Vector3(0.0, 100.0, 0.0)
	drone.linear_velocity = Vector3.ZERO
	drone.angular_velocity = Vector3.ZERO
	drone.reset_motion_history()
	drone.freeze = true
	await get_tree().physics_frame
	drone.freeze = false
	drone.flight_controller.reset()
	drone.flight_controller.request_arm(true)
	drone.flight_controller.input = [0.45, 0.0, 0.0, 0.0]
	print("[HOVER-TEST] mass=", drone.mass, " armed=",
		drone.flight_controller.state_armed)


func _physics_process(delta: float) -> void:
	if drone == null or not drone.flight_controller.state_armed:
		return
	drone.flight_controller.input = [0.45, 0.0, 0.0, 0.0]
	elapsed += delta
	if int(elapsed * 4.0) != int((elapsed - delta) * 4.0):
		var fc := drone.flight_controller
		var thrust := 0.0
		for motor in drone.motors:
			thrust += motor.propeller.forces[0].y
		print("[HOVER-TEST] t=", snappedf(elapsed, 0.01),
			" pos=", drone.global_position,
			" vel=", drone.linear_velocity,
			" ang_vel=", drone.angular_velocity,
			" angles=", fc.angles,
			" thrust=", thrust, " sag=", drone.battery_sag_factor,
			" rpm=", [drone.motors[0].get_rpm(), drone.motors[1].get_rpm(),
				drone.motors[2].get_rpm(), drone.motors[3].get_rpm()])
		if int(elapsed * 4.0) == 2:
			for i in range(4):
				var p: Propeller = drone.motors[i].propeller
				print("  motor", i, " pos=", drone.motors[i].transform.origin,
					" roll_moment=", p.forces[3], " pitch_moment=", p.forces[4],
					" yaw_torque=", drone.motors[i].get_torque(),
					" drag=", p.forces[1])
			print("  com=", drone.center_of_mass, " inertia=", drone.inertia)
	if elapsed >= 3.0:
		var tilt: float = rad_to_deg(Vector3.UP.angle_to(drone.global_transform.basis.y))
		print("[HOVER-TEST] final tilt_deg=", tilt,
			" vertical_vel=", drone.linear_velocity.y)
		if tilt < 8.0 and absf(drone.linear_velocity.y) < 2.0:
			print("[HOVER-TEST] PASS stable hover")
			get_tree().quit(0)
		else:
			print("[HOVER-TEST] FAIL unstable hover")
			get_tree().quit(1)
