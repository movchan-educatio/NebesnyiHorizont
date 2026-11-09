extends Node

## QA: climb at 70% throttle, then release the left stick to its centre (45%)
## and check whether the drone holds altitude or falls/shakes.

var drone: Drone = null
var elapsed := 0.0
var preset := 7
var last_log := -1.0
var max_tilt := 0.0
var max_ang := 0.0


func _ready() -> void:
	if OS.has_environment("DRONE_TEST_PRESET"):
		preset = int(OS.get_environment("DRONE_TEST_PRESET"))
	var packed := load("res://drone/drones/Drone1.tscn") as PackedScene
	drone = packed.instantiate() as Drone
	add_child(drone)
	DroneCatalog.apply_to_drone(drone, preset)
	var alt := 150.0
	if OS.has_environment("DRONE_TEST_ALT"):
		alt = float(OS.get_environment("DRONE_TEST_ALT"))
	drone.global_position = Vector3(0.0, alt, 0.0)
	drone.linear_velocity = Vector3.ZERO
	drone.angular_velocity = Vector3.ZERO
	drone.reset_motion_history()
	drone.freeze = true
	await get_tree().physics_frame
	drone.freeze = false
	drone.flight_controller.reset()
	drone.flight_controller.request_arm(true)
	print("[RLS] preset=", preset, " name=", DroneCatalog.preset(preset)["name"],
			" mass=", drone.mass, " mode=", drone.flight_controller.flight_mode,
			" sim=", drone.sim_thrust_mode,
			" phys_twr=", snappedf(drone.physical_max_twr, 0.01),
			" pwm45=", snappedf(drone.flight_controller.throttle_to_motor_pwm(0.45), 0.001),
			" pwm70=", snappedf(drone.flight_controller.throttle_to_motor_pwm(0.70), 0.001),
			" weight=", snappedf(drone.mass * 9.81, 0.01))


func _physics_process(delta: float) -> void:
	if drone == null or not drone.flight_controller.state_armed:
		return
	elapsed += delta
	var tilt_now := rad_to_deg(Vector3.UP.angle_to(drone.global_transform.basis.y))
	max_tilt = maxf(max_tilt, tilt_now)
	max_ang = maxf(max_ang, drone.angular_velocity.length())
	var hold := 5.2
	if OS.has_environment("DRONE_TEST_HOLD"):
		hold = float(OS.get_environment("DRONE_TEST_HOLD"))
	var hold_thr := 0.45
	if OS.has_environment("DRONE_TEST_HOLD_THR"):
		hold_thr = float(OS.get_environment("DRONE_TEST_HOLD_THR"))
	if elapsed < 1.6:
		drone.flight_controller.input = [0.70, 0.0, 0.0, 0.0]
	elif elapsed < hold:
		drone.flight_controller.input = [hold_thr, 0.0, 0.0, 0.0]
	else:
		var fc := drone.flight_controller
		print("[RLS] final vy=", snappedf(drone.linear_velocity.y, 0.01),
				" vz=", snappedf(drone.linear_velocity.z, 0.01),
				" tilt=", snappedf(rad_to_deg(Vector3.UP.angle_to(
						drone.global_transform.basis.y)), 0.1),
				" max_tilt=", snappedf(max_tilt, 0.1),
				" max_ang=", snappedf(max_ang, 0.01),
				" pitch=", snappedf(rad_to_deg(fc.angles.x), 0.1),
				" rpm=", snappedf(drone.flight_controller.motors[0].rpm, 1.0), " rpm_t=", snappedf(drone.flight_controller.motors[0].rpm_target, 1.0))
		get_tree().quit()
	if elapsed - last_log >= 0.25:
		last_log = elapsed
		var fc := drone.flight_controller
		print("[RLS] t=", snappedf(elapsed, 0.01),
				" thr_in=", fc.input[0],
				" vy=", snappedf(drone.linear_velocity.y, 0.01),
				" vz=", snappedf(drone.linear_velocity.z, 0.01),
				" tilt=", snappedf(rad_to_deg(Vector3.UP.angle_to(
						drone.global_transform.basis.y)), 0.1),
				" ang=", snappedf(drone.angular_velocity.length(), 0.01),
				" rpm=", snappedf(drone.flight_controller.motors[0].rpm, 1.0), " rpm_t=", snappedf(drone.flight_controller.motors[0].rpm_target, 1.0))


