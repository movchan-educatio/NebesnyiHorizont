extends Node

## Verifies the "infinite battery" training toggle and the realistic sag path.

func _ready() -> void:
	var scene := load("res://drone/drones/Drone1.tscn") as PackedScene
	var drone := scene.instantiate() as Drone
	add_child(drone)
	GameSettings.hud_config["infinite_battery"] = false
	DroneCatalog.apply_to_drone(drone, 12)
	for motor in drone.motors:
		motor.set_rpm(motor.MAX_RPM)
	drone.update_voltage_sag(0.1)
	var realistic_sag: float = drone.battery_sag_factor
	var realistic_ok := realistic_sag < 0.999
	GameSettings.hud_config["infinite_battery"] = true
	drone.update_voltage_sag(0.1)
	var infinite_ok := is_equal_approx(drone.battery_sag_factor, 1.0) \
			and is_equal_approx(drone.battery_current_draw, 0.0) \
			and is_equal_approx(drone.battery_cell_voltage, drone.battery_cell_voltage_rest)
	print("[BATTERY] realistic_sag=%.2f infinite_ok=%s" % [realistic_sag, str(infinite_ok)])
	GameSettings.hud_config["infinite_battery"] = false
	print("[BATTERY] RESULT ", "PASS" if realistic_ok and infinite_ok else "FAIL")
	get_tree().quit(0 if realistic_ok and infinite_ok else 1)
