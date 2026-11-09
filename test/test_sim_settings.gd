extends Node

## Verifies the simulator-aid settings:
##   * link_limit off -> perfect link, no failsafe, EW masts hidden;
##   * angle_mode / acro_mode off -> safe mode fallback and cycle skipping;
##   * shared HUD labels cover every flight mode.

var _saved := {}


func _ready() -> void:
	for key in ["link_limit", "wind_sim", "reb_zones", "angle_mode", "acro_mode"]:
		_saved[key] = GameSettings.hud_config[key]
	GameSettings.hud_config["angle_mode"] = true
	GameSettings.hud_config["acro_mode"] = true

	var drone_scene := load("res://drone/drones/Drone1.tscn") as PackedScene
	var drone := drone_scene.instantiate() as Drone
	drone.name = "Drone"
	add_child(drone)
	var fc: FlightController = drone.flight_controller

	var ok := true
	ok = _expect_mode(fc, FlightController.FlightMode.LEVEL, "default ANGLE") and ok

	# Both manual and self-levelling modes disabled: HORIZON only.
	GameSettings.hud_config["angle_mode"] = false
	GameSettings.hud_config["acro_mode"] = false
	fc.flight_mode = FlightController.FlightMode.RATE
	fc._on_cycle_flight_modes()
	ok = _expect_mode(fc, FlightController.FlightMode.HORIZON, "both disabled fallback") and ok
	fc._on_cycle_flight_modes()
	ok = _expect_mode(fc, FlightController.FlightMode.HORIZON, "both disabled cycle stays HORIZON") and ok

	# Acro disabled, Angle enabled: LEVEL <-> HORIZON.
	GameSettings.hud_config["angle_mode"] = true
	fc.select_flight_mode(FlightController.FlightMode.RATE)
	ok = _expect_mode(fc, FlightController.FlightMode.LEVEL, "acro disabled selects ANGLE") and ok
	fc._on_cycle_flight_modes()
	ok = _expect_mode(fc, FlightController.FlightMode.HORIZON, "angle->horizon") and ok
	fc._on_cycle_flight_modes()
	ok = _expect_mode(fc, FlightController.FlightMode.LEVEL, "horizon->angle") and ok

	# Angle disabled, Acro enabled: RATE <-> HORIZON.
	GameSettings.hud_config["angle_mode"] = false
	GameSettings.hud_config["acro_mode"] = true
	fc.select_flight_mode(FlightController.FlightMode.LEVEL)
	ok = _expect_mode(fc, FlightController.FlightMode.RATE, "angle disabled selects ACRO") and ok
	fc._on_cycle_flight_modes()
	ok = _expect_mode(fc, FlightController.FlightMode.HORIZON, "acro->horizon") and ok
	fc._on_cycle_flight_modes()
	ok = _expect_mode(fc, FlightController.FlightMode.RATE, "horizon->acro") and ok

	# Both enabled: full original cycle.
	GameSettings.hud_config["angle_mode"] = true
	fc.select_flight_mode(FlightController.FlightMode.RATE)
	fc._on_cycle_flight_modes()
	ok = _expect_mode(fc, FlightController.FlightMode.LEVEL, "acro->angle") and ok
	fc._on_cycle_flight_modes()
	ok = _expect_mode(fc, FlightController.FlightMode.HORIZON, "angle->horizon full") and ok
	fc._on_cycle_flight_modes()
	ok = _expect_mode(fc, FlightController.FlightMode.RATE, "horizon->acro full") and ok

	# Shared HUD labels.
	for pair in [
			[FlightController.FlightMode.RATE, "ACRO"],
			[FlightController.FlightMode.LEVEL, "ANGLE"],
			[FlightController.FlightMode.HORIZON, "HORIZON"],
			[FlightController.FlightMode.AUTO, "AUTO"]]:
		var label: String = FlightController.mode_name(int(pair[0]))
		if label != pair[1]:
			printerr("[SIMSETTINGS] FAIL label %s != %s" % [label, pair[1]])
			ok = false
	drone.hud.update_flight_mode(FlightController.FlightMode.HORIZON)
	var hud_text: String = drone.hud.get_node("MarginContainer/FlightMode").text
	if hud_text != "HORIZON":
		printerr("[SIMSETTINGS] FAIL HUD horizon label: ", hud_text)
		ok = false

	# Link limits off: perfect link at an absurd distance and hidden EW masts.
	GameSettings.hud_config["link_limit"] = false
	var reb := RebSystem.new()
	reb.name = "RebSystem"
	reb.use_own_position_as_home = false
	reb.home_position = Vector3.ZERO
	add_child(reb)
	reb.add_ew_dome(Vector3(50.0, 0.0, 0.0), 220.0)
	drone.global_position = Vector3(6000.0, 120.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var unlimited_ok: bool = is_equal_approx(reb.link_quality, 1.0) \
			and is_equal_approx(reb.signal_strength, 1.0) \
			and reb.packet_loss == 0.0 and reb.stick_jitter == Vector2.ZERO \
			and not reb.failsafe and reb.get_status_text() == "UNLIMITED" \
			and reb.in_ew == 0.0 and not reb.blocked
	if not unlimited_ok:
		printerr("[SIMSETTINGS] FAIL unlimited link: ", reb.get_link_state())
		ok = false
	if reb._masts.is_empty() or reb._masts[0].visible:
		printerr("[SIMSETTINGS] FAIL EW mast must be hidden while link limits are off")
		ok = false

	# Re-enable: physics model comes back.  REB zones are an independent gate:
	# range loss can be active while the EW domes are disabled for training.
	drone.global_position = Vector3(50.0, 120.0, 0.0)
	GameSettings.hud_config["link_limit"] = true
	GameSettings.hud_config["reb_zones"] = false
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not reb.limits_enabled or reb.get_status_text() == "UNLIMITED":
		printerr("[SIMSETTINGS] FAIL link limits did not re-engage")
		ok = false
	if reb.in_ew > 0.0 or reb._masts[0].visible:
		printerr("[SIMSETTINGS] FAIL REB zones must stay off while reb_zones=false")
		ok = false

	# With the domes re-enabled the drone inside the radius is jammed again.
	GameSettings.hud_config["reb_zones"] = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	if reb.in_ew <= 0.0:
		printerr("[SIMSETTINGS] FAIL REB zone did not engage")
		ok = false
	if not reb._masts[0].visible:
		printerr("[SIMSETTINGS] FAIL EW mast must reappear with REB zones")
		ok = false

	# Wind gate reads the same persisted flag.
	GameSettings.hud_config["wind_sim"] = false
	if bool(GameSettings.hud_config.get("wind_sim", true)):
		printerr("[SIMSETTINGS] FAIL wind_sim flag not persisted")
		ok = false

	for key in _saved.keys():
		GameSettings.hud_config[key] = _saved[key]
	print("[SIMSETTINGS] RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)


func _expect_mode(fc: FlightController, mode: int, label: String) -> bool:
	if fc.flight_mode == mode:
		print("[SIMSETTINGS] PASS ", label, " -> ", FlightController.mode_name(mode))
		return true
	printerr("[SIMSETTINGS] FAIL ", label, ": got ", FlightController.mode_name(fc.flight_mode))
	return false
