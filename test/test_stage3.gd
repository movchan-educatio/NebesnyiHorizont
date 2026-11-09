extends Node

func _ready() -> void:
	print("==================================================")
	print("=== RUNNING STAGE 3 TEST: ACRO/RATE PID CONTROLLER ===")
	print("==================================================")
	
	var catalog := DroneCatalog
	var drone_scene := load("res://drone/drones/Drone1.tscn") as PackedScene
	assert(drone_scene != null, "Drone1.tscn must load")
	var drone := drone_scene.instantiate() as Drone
	add_child(drone)
	
	catalog.apply_to_drone(drone, 0)
	var fc: FlightController = drone.flight_controller
	fc.state_armed = true
	fc.select_flight_mode(FlightController.FlightMode.RATE)
	
	# 1. Test Acro/Rate mode stick command
	# Stick input format in FlightController: [throttle, yaw, roll, pitch]
	# Throttle at 50% (0.5), Roll stick at +0.5 (half right)
	fc.input = [0.5, 0.0, 0.5, 0.0]
	fc.dt = 0.016
	
	# Simulate 1 step from stationary gyro (ang_vel = 0)
	fc.integrate_loop(0.016, drone.global_position, drone.global_transform.basis, Vector3.ZERO, Vector3.ZERO)
	
	var pwm_0: float = drone.motors[0].get_rpm_target() / drone.motors[0].MAX_RPM
	var pwm_1: float = drone.motors[1].get_rpm_target() / drone.motors[1].MAX_RPM
	var pwm_2: float = drone.motors[2].get_rpm_target() / drone.motors[2].MAX_RPM
	var pwm_3: float = drone.motors[3].get_rpm_target() / drone.motors[3].MAX_RPM
	
	print("[TEST] Roll stick +0.5 -> Motor PWMs: M1=%.2f, M2=%.2f, M3=%.2f, M4=%.2f" % [
		pwm_0, pwm_1, pwm_2, pwm_3
	])
	# When rolling right, left motors (0, 3) must spin faster than right motors (1, 2)
	assert(pwm_0 > pwm_1, "Motor 1 (left) must spin faster than Motor 2 (right)")
	assert(pwm_3 > pwm_2, "Motor 4 (left) must spin faster than Motor 3 (right)")
	assert(pwm_0 - pwm_1 < 0.65,
		"Half-stick roll must not saturate the motor mixer")
	
	# 2. Test Gyro rate feedback tracking:
	# Now simulate that drone is rolling at target rate
	# Actual Rates use a 200 deg/s centre sensitivity and a 900 deg/s maximum;
	# at half-stick, the shaped target is about 169 deg/s (2.95 rad/s).
	var roll_target_rate: float = fc.pid_controllers[FlightController.Controller.ROLL_SPEED].target
	print("[TEST] Roll Target Rate: %.2f rad/s (%.1f deg/s)" % [
		roll_target_rate, rad_to_deg(roll_target_rate)
	])
	assert(roll_target_rate > 2.0, "Roll target rate must be significant for 50% stick")
	
	# Feed matching body angular rate
	var matching_ang_vel: Vector3 = drone.global_transform.basis * Vector3(0, 0, -roll_target_rate)
	fc.integrate_loop(0.016, drone.global_position, drone.global_transform.basis, Vector3.ZERO, matching_ang_vel)
	var err: float = fc.pid_controllers[FlightController.Controller.ROLL_SPEED].err
	print("[TEST] Gyro feedback matching target -> Error: %.4f" % err)
	assert(abs(err) < 0.1, "Error must drop to near zero when gyro rate matches target")
	
	# 3. Test AirMode: Zero throttle stick, full roll stick
	fc.input = [0.0, 0.0, 1.0, 0.0]
	fc.integrate_loop(0.016, drone.global_position, drone.global_transform.basis, Vector3.ZERO, Vector3.ZERO)
	var air_pwm_0: float = drone.motors[0].get_rpm_target() / drone.motors[0].MAX_RPM
	var air_pwm_1: float = drone.motors[1].get_rpm_target() / drone.motors[1].MAX_RPM
	print("[TEST] AirMode at ZERO throttle: M1=%.2f, M2=%.2f, diff=%.2f" % [
		air_pwm_0, air_pwm_1, air_pwm_0 - air_pwm_1
	])
	assert(air_pwm_0 - air_pwm_1 > 0.3, "AirMode must maintain full differential control at 0 throttle")
	assert(air_pwm_1 >= drone.motors[1].MIN_POWER / 100.0, "Motor must not fall below idle PWM")
	
	# 4. Anti-Windup test
	var roll_pid: PID = fc.pid_controllers[FlightController.Controller.ROLL_SPEED]
	print("[TEST] Anti-Windup status: windup=%s, saturated=%s" % [roll_pid.windup, roll_pid.saturated])
	
	drone.queue_free()
	print("==================================================")
	print("=== STAGE 3 TEST PASSED SUCCESSFULLY! ===")
	print("==================================================")
	get_tree().quit(0)
