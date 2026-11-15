extends Node

## Runtime flight envelope QA across all DroneCatalog presets (0..9):
## checks hover stability, yaw responsiveness, forward pitch maneuver at 50% SoC,
## HORIZON self-leveling, RATE roll controllability, and empty-battery cutoff.

var _drone_scene: PackedScene = null


func _ready() -> void:
	var saved_angle: Variant = GameSettings.hud_config.get("angle_mode", true)
	var saved_acro: Variant = GameSettings.hud_config.get("acro_mode", true)
	var saved_inf: Variant = GameSettings.hud_config.get("infinite_battery", false)
	var saved_wind: Variant = GameSettings.hud_config.get("wind_sim", false)
	var saved_reb: Variant = GameSettings.hud_config.get("reb_zones", false)
	var saved_bank: float = QuadSettings.level_bank
	var saved_again: float = QuadSettings.level_angle_gain
	var saved_rgain: float = QuadSettings.level_rate_gain
	var saved_rlim: float = QuadSettings.level_rate_limit
	QuadSettings.level_bank = 28.0
	QuadSettings.level_angle_gain = 2.2
	QuadSettings.level_rate_gain = 0.22
	QuadSettings.level_rate_limit = 3.5
	GameSettings.hud_config["angle_mode"] = true
	GameSettings.hud_config["acro_mode"] = true
	GameSettings.hud_config["infinite_battery"] = false
	GameSettings.hud_config["wind_sim"] = false
	GameSettings.hud_config["reb_zones"] = false

	_drone_scene = load("res://drone/drones/Drone1.tscn") as PackedScene
	if _drone_scene == null:
		printerr("[QA-DRONES] FAIL: Drone1.tscn failed to load")
		get_tree().quit(1)
		return

	var count: int = DroneCatalog.PRESETS.size()
	var failures: Array[String] = []
	for idx in range(count):
		var err_msg: String = await _test_preset(idx)
		if not err_msg.is_empty():
			failures.append(err_msg)

	GameSettings.hud_config["angle_mode"] = saved_angle
	GameSettings.hud_config["acro_mode"] = saved_acro
	GameSettings.hud_config["infinite_battery"] = saved_inf
	GameSettings.hud_config["wind_sim"] = saved_wind
	GameSettings.hud_config["reb_zones"] = saved_reb
	QuadSettings.level_bank = saved_bank
	QuadSettings.level_angle_gain = saved_again
	QuadSettings.level_rate_gain = saved_rgain
	QuadSettings.level_rate_limit = saved_rlim

	if not failures.is_empty():
		for f in failures:
			printerr("[QA-DRONES] FAIL: %s" % f)
		get_tree().quit(1)
		return

	print("[QA-DRONES] PASS: All %d drone presets verified across LEVEL/HORIZON/RATE/cutoff" % count)
	get_tree().quit(0)


func _spawn_preset(idx: int) -> Drone:
	var drone: Drone = _drone_scene.instantiate() as Drone
	add_child(drone)
	DroneCatalog.apply_to_drone(drone, idx)
	_reset_drone_state(drone, Vector3(0.0, 120.0, 0.0))
	drone.freeze = true
	await get_tree().physics_frame
	drone.freeze = false
	drone.flight_controller.reset()
	drone.flight_controller.select_flight_mode(FlightController.FlightMode.LEVEL)
	drone.control_profile.set_level_control(28.0, 2.2, 0.22, 3.5)
	drone.flight_controller.request_arm(true)
	return drone


func _reset_drone_state(drone: Drone, origin: Vector3) -> void:
	drone.global_transform = Transform3D(Basis.IDENTITY, origin)
	drone.linear_velocity = Vector3.ZERO
	drone.angular_velocity = Vector3.ZERO
	drone.reset_motion_history()
	for m in drone.motors:
		if m != null:
			m.set_rpm(0.0)
	var fc: FlightController = drone.flight_controller
	var prev_mode: int = fc.flight_mode
	var was_armed: bool = fc.state_armed
	fc.reset()
	fc.angles = Vector3.ZERO
	fc.select_flight_mode(prev_mode)
	if was_armed:
		fc.state_armed = true


func _step_input(drone: Drone, inp: Array, duration_s: float) -> float:
	var fc: FlightController = drone.flight_controller
	var max_ang: float = 0.0
	var tps: float = float(Engine.physics_ticks_per_second)
	var steps: int = maxi(int(round(duration_s * tps)), 1)
	for _s in range(steps):
		fc.input = inp
		await get_tree().physics_frame
		max_ang = maxf(max_ang, drone.angular_velocity.length())
	return max_ang


func _test_preset(idx: int) -> String:
	var preset: Dictionary = DroneCatalog.PRESETS[idx]
	var pname: String = String(preset.get("name", "preset_%d" % idx))
	var drone: Drone = await _spawn_preset(idx)
	var fc: FlightController = drone.flight_controller
	var hover_thr: float = clampf(fc.throttle_hover_point, 0.25, 0.72)

	# 1. LEVEL hover stability (1.4s)
	var hover_max_ang: float = await _step_input(drone, [hover_thr, 0.0, 0.0, 0.0], 1.4)
	var hover_tilt: float = rad_to_deg(Vector3.UP.angle_to(drone.global_transform.basis.y))
	var hover_dy: float = drone.global_position.y - 120.0

	# 2. LEVEL yaw step responsiveness (0.55s)
	await _step_input(drone, [hover_thr, 0.60, 0.0, 0.0], 0.55)
	var yaw_rate: float = absf(drone.angular_velocity.y)
	var yaw_tilt: float = rad_to_deg(Vector3.UP.angle_to(drone.global_transform.basis.y))

	# 3. Forward flight at 50% SoC (0.3s pre-hover so props are spun up, then 1.5s pitch -0.85)
	_reset_drone_state(drone, Vector3(0.0, 120.0, 0.0))
	drone.battery_used_mah = drone.battery_capacity_mah * 0.50
	await _step_input(drone, [hover_thr, 0.0, 0.0, 0.0], 0.3)
	var fwd_thr: float = clampf(hover_thr + 0.16, 0.42, 0.82)
	await _step_input(drone, [fwd_thr, 0.0, 0.0, -0.85], 1.5)
	var hspeed: float = Vector2(drone.linear_velocity.x, drone.linear_velocity.z).length()
	var fwd_tilt: float = rad_to_deg(Vector3.UP.angle_to(drone.global_transform.basis.y))
	var fwd_dy: float = drone.global_position.y - 120.0

	# 4. HORIZON self-leveling check & RATE roll controllability
	_reset_drone_state(drone, Vector3(0.0, 120.0, 0.0))
	drone.battery_used_mah = 0.0
	fc.select_flight_mode(FlightController.FlightMode.HORIZON)
	await _step_input(drone, [hover_thr, 0.0, 0.0, 0.0], 0.4)
	var horizon_tilt: float = rad_to_deg(Vector3.UP.angle_to(drone.global_transform.basis.y))

	fc.select_flight_mode(FlightController.FlightMode.RATE)
	await _step_input(drone, [hover_thr, 0.0, 0.35, 0.0], 0.3)
	var acro_rate: float = drone.angular_velocity.length()

	# 5. Empty battery cutoff (<2% SoC)
	fc.select_flight_mode(FlightController.FlightMode.LEVEL)
	drone.battery_used_mah = drone.battery_capacity_mah
	await _step_input(drone, [0.85, 0.0, 0.0, 0.0], 0.35)
	var cutoff_ok: bool = float(drone.get("_battery_cutoff")) <= 0.02
	var cutoff_vy: float = drone.linear_velocity.y

	print("[QA-DRONE %d %s] hover_tilt=%.1fd dy=%.2fm max_w=%.2f | yaw=%.2frad/s (tilt=%.1fd) | fwd_v=%.1fm/s dy=%.1fm tilt=%.1fd | hor_tilt=%.1fd rate_w=%.2f | cutoff=%s vy=%.2f" % [
		idx, pname, hover_tilt, hover_dy, hover_max_ang,
		yaw_rate, yaw_tilt, hspeed, fwd_dy, fwd_tilt,
		horizon_tilt, acro_rate, str(cutoff_ok), cutoff_vy
	])

	drone.queue_free()
	await get_tree().process_frame

	if hover_tilt > 6.5 or hover_max_ang > 1.2 or hover_dy < -6.5:
		return "%d %s unstable hover (tilt=%.1f max_w=%.2f dy=%.2f)" % [idx, pname, hover_tilt, hover_max_ang, hover_dy]
	if yaw_rate < 0.30 or yaw_rate > 9.5 or yaw_tilt > 14.0:
		return "%d %s bad yaw (rate=%.2f tilt=%.1f)" % [idx, pname, yaw_rate, yaw_tilt]
	if hspeed < 4.5 or fwd_tilt > 55.0 or fwd_dy < -12.0:
		return "%d %s bad forward 50%%SoC (v=%.1f tilt=%.1f dy=%.1f)" % [idx, pname, hspeed, fwd_tilt, fwd_dy]
	if horizon_tilt > 7.5:
		return "%d %s HORIZON drifted (tilt=%.1f)" % [idx, pname, horizon_tilt]
	if acro_rate < 0.35 or acro_rate > 12.5:
		return "%d %s RATE uncontrollable (w=%.2f)" % [idx, pname, acro_rate]
	if not cutoff_ok or cutoff_vy > 0.5:
		return "%d %s battery cutoff failed (cutoff=%s vy=%.2f)" % [idx, pname, str(cutoff_ok), cutoff_vy]
	return ""
