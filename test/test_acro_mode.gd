extends Node

func _ready() -> void:
	print("==================================================")
	print("=== RUNNING ACRO (RATE) MODE & FREESTYLE TRICKS TEST ===")
	print("==================================================")
	
	var saved_angle: Variant = GameSettings.hud_config.get("angle_mode", true)
	var saved_acro: Variant = GameSettings.hud_config.get("acro_mode", true)
	var saved_inf: Variant = GameSettings.hud_config.get("infinite_battery", false)
	GameSettings.hud_config["angle_mode"] = true
	GameSettings.hud_config["acro_mode"] = true
	GameSettings.hud_config["infinite_battery"] = false

	var catalog := DroneCatalog
	var drone_scene := load("res://drone/drones/Drone1.tscn") as PackedScene
	if drone_scene == null:
		printerr("Drone1.tscn failed to load")
		get_tree().quit(1)
		return
		
	var drone := drone_scene.instantiate() as Drone
	add_child(drone)
	
	catalog.apply_to_drone(drone, 3) # «КВАД-5» 5" Combat FPV
	var fc: FlightController = drone.flight_controller
	
	# 1. Verify default flight mode is LEVEL (self-levelling, beginner-friendly).
	if fc.flight_mode != FlightController.FlightMode.LEVEL:
		printerr("FAIL: Flight mode must default to LEVEL (ANGLE)")
		get_tree().quit(1)
		return
	print("[PASS] 1. Drone defaults to LEVEL (ANGLE), then switches to ACRO for the tricks.")
	fc.state_armed = true
	fc.select_flight_mode(FlightController.FlightMode.RATE)
	if fc.flight_mode != FlightController.FlightMode.RATE:
		printerr("FAIL: Could not select RATE (Acro)")
		get_tree().quit(1)
		return
	
	# 2. Verify HUD mode display
	drone.hud.update_flight_mode(fc.flight_mode)
	var hud_text: String = drone.hud.get_node("MarginContainer/FlightMode").text
	print("[PASS] 2. HUD in RATE mode displays: '%s'" % hud_text)
	if hud_text != "ACRO":
		printerr("FAIL: HUD text was not ACRO")
		get_tree().quit(1)
		return
	
	# 3. Test Mode Toggle ('M' key / radio switch)
	fc._on_cycle_flight_modes()
	if fc.flight_mode != FlightController.FlightMode.LEVEL:
		printerr("FAIL: Toggling mode from RATE should enter LEVEL (ANGLE)")
		get_tree().quit(1)
		return
	drone.hud.update_flight_mode(fc.flight_mode)
	hud_text = drone.hud.get_node("MarginContainer/FlightMode").text
	print("[PASS] 3a. Mode cycled to LEVEL, HUD displays: '%s'" % hud_text)
	if hud_text != "ANGLE":
		printerr("FAIL: HUD text was not ANGLE")
		get_tree().quit(1)
		return
	
	fc._on_cycle_flight_modes()
	if fc.flight_mode != FlightController.FlightMode.HORIZON:
		printerr("FAIL: Toggling mode from LEVEL should enter HORIZON")
		get_tree().quit(1)
		return
	drone.hud.update_flight_mode(fc.flight_mode)
	hud_text = drone.hud.get_node("MarginContainer/FlightMode").text
	print("[PASS] 3b. Mode cycled to HORIZON, HUD displays: '%s'" % hud_text)
	if hud_text != "HORIZON":
		printerr("FAIL: HUD text was not HORIZON")
		get_tree().quit(1)
		return

	fc._on_cycle_flight_modes()
	if fc.flight_mode != FlightController.FlightMode.RATE:
		printerr("FAIL: Toggling mode from HORIZON should return to RATE (ACRO)")
		get_tree().quit(1)
		return
	print("[PASS] 3c. Mode cycled back to ACRO (RATE).")
	
	# 4. Air Mode & Control Torque at ZERO Throttle
	# In Acro mode, pilot cuts throttle to 0% and deflects roll stick to 1.0 (full right roll)
	fc.input = [0.0, 0.0, 1.0, 0.0] # Throttle=0, Yaw=0, Roll=1.0, Pitch=0
	# Keep the stick held for several PID iterations: control must be sustained,
	# not just a one-frame feedforward kick.
	for _i in range(8):
		fc.integrate_loop(0.016, drone.global_position, drone.global_transform.basis, Vector3.ZERO, Vector3.ZERO)
	var roll_rate_target: float = fc.pid_controllers[FlightController.Controller.ROLL_SPEED].target
	if roll_rate_target <= 10.0:
		printerr("FAIL: Held roll stick must create a persistent angular-rate target")
		get_tree().quit(1)
		return
	
	var m1_pwm: float = drone.motors[0].get_rpm_target() / drone.motors[0].MAX_RPM
	var m2_pwm: float = drone.motors[1].get_rpm_target() / drone.motors[1].MAX_RPM
	print("[PASS] 4. Air Mode at 0%% throttle: Left Motor PWM=%.2f, Right Motor PWM=%.2f (diff=%.2f)" % [
		m1_pwm, m2_pwm, m1_pwm - m2_pwm
	])
	if m1_pwm - m2_pwm <= 0.08:
		printerr("FAIL: Air Mode differential RPM too low at 0 throttle")
		get_tree().quit(1)
		return
	
	# 5. Full 360-degree Roll & Inverted Flight simulation
	drone.global_position = Vector3(0, 50, 0)
	drone.linear_velocity = Vector3.ZERO
	drone.angular_velocity = Vector3.ZERO
	
	var max_roll_reached := 0.0
	var completed_inverted := false
	var completed_full_roll := false
	var total_roll_accumulated := 0.0
	
	var max_t: float = drone.mass * 9.81 * drone.target_max_twr
	var arm_len: float = drone.frame_dimensions.x * 0.5
	var inertia_z: float = drone.inertia.z if drone.inertia.z > 0.0001 else 0.0035
	
	for frame in range(120):
		fc.integrate_loop(0.016, drone.global_position, drone.global_transform.basis, drone.linear_velocity, drone.angular_velocity)
		
		var pitch_roll_cap: float = max_t * 0.40 * drone.battery_sag_factor
		var left_pwr: float = (float(drone.motors[0].rpm_target) + float(drone.motors[3].rpm_target)) * 0.5 / maxf(float(drone.motors[0].MAX_RPM), 1.0)
		var right_pwr: float = (float(drone.motors[1].rpm_target) + float(drone.motors[2].rpm_target)) * 0.5 / maxf(float(drone.motors[0].MAX_RPM), 1.0)
		var diff_r: float = left_pwr - right_pwr
		
		var tau_roll: Vector3 = drone.global_transform.basis * Vector3(0, 0, -diff_r * pitch_roll_cap * arm_len)
		var ang_accel: Vector3 = tau_roll * (1.0 / inertia_z)
		drone.angular_velocity += ang_accel * 0.016
		drone.angular_velocity *= 0.98
		
		var delta_rot := drone.angular_velocity * 0.016
		if delta_rot != Vector3.ZERO:
			drone.global_transform.basis = drone.global_transform.basis.rotated(delta_rot.normalized(), delta_rot.length())
		
		total_roll_accumulated += abs(drone.angular_velocity.z) * 0.016
		var current_roll_deg: float = rad_to_deg(abs(drone.global_transform.basis.get_euler().z))
		max_roll_reached = maxf(max_roll_reached, current_roll_deg)
		if current_roll_deg > 140.0:
			completed_inverted = true
		if total_roll_accumulated > 2.0 * PI:
			completed_full_roll = true
	
	print("[PASS] 5. Acro Roll Dynamics: Total Rotation=%.1f deg, Max Roll=%.1f deg" % [
		rad_to_deg(total_roll_accumulated), max_roll_reached
	])
	
	if not completed_inverted:
		printerr("FAIL: Drone in Acro mode did not reach inverted flight")
		get_tree().quit(1)
		return
		
	if not completed_full_roll:
		printerr("FAIL: Drone in Acro mode did not complete full 360 roll")
		get_tree().quit(1)
		return
		
	if fc.flight_mode != FlightController.FlightMode.RATE:
		printerr("FAIL: Drone unexpectedly switched mode out of RATE")
		get_tree().quit(1)
		return
	
	drone.queue_free()
	GameSettings.hud_config["angle_mode"] = saved_angle
	GameSettings.hud_config["acro_mode"] = saved_acro
	GameSettings.hud_config["infinite_battery"] = saved_inf
	print("==================================================")
	print("=== ALL ACRO MODE AND FREESTYLE TRICKS TESTS PASSED! ===")
	print("==================================================")
	get_tree().quit(0)
