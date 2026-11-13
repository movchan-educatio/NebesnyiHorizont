extends Node

func _ready() -> void:
	print("==================================================")
	print("=== RUNNING STAGE 5 TEST: COMBAT DROP & VOLTAGE SAG ===")
	print("==================================================")
	
	var catalog := DroneCatalog
	var drone_scene := load("res://drone/drones/Drone1.tscn") as PackedScene
	assert(drone_scene != null, "Drone1.tscn must load")
	var drone := drone_scene.instantiate() as Drone
	add_child(drone)
	GameSettings.hud_config["infinite_battery"] = false
	
	# ----------------------------------------------------
	# 1. Combat Payload Drop Test («ГРІМ-7М» - 2x VOG drop)
	# ----------------------------------------------------
	catalog.apply_to_drone(drone, 1) # Preset 1: «ГРІМ-7М»
	print("[TEST] Armed «ГРІМ-7М»: Mass=%.2f kg, CoG=%s, Payloads=%d" % [
		drone.mass, drone.center_of_mass, drone.payload_count
	])
	assert(abs(drone.mass - 2.16) < 0.02, "Initial mass must be ~2.16 kg")
	assert(drone.center_of_mass.y < -0.005, "CoG must be slung down under belly")
	assert(drone.has_payload == true, "Must have payload active")
	
	# First drop
	drone.linear_velocity = Vector3.ZERO
	var dropped_1: float = drone.drop_payload_action()
	print("[TEST] Drop 1: Dropped %.2f kg -> New Mass=%.2f kg, Hop Vy=%.2f m/s" % [
		dropped_1, drone.mass, drone.linear_velocity.y
	])
	assert(abs(dropped_1 - 0.20) < 0.05 or abs(dropped_1 - 0.40) < 0.05, "Dropped weight must match bomblet mass")
	assert(drone.linear_velocity.y > 0.3, "Drone must experience upward separation hop")
	
	# Second drop (empties payload)
	while drone.has_payload:
		drone.drop_payload_action()
	
	print("[TEST] After all drops: Mass=%.2f kg, CoG=%s, has_payload=%s" % [
		drone.mass, drone.center_of_mass, drone.has_payload
	])
	assert(abs(drone.mass - 1.36) < 0.02, "Empty mass must be 1.36 kg")
	assert(Vector2(drone.center_of_mass.x, drone.center_of_mass.z).length() < 0.001 and drone.center_of_mass.y < 0.02, "CoG must return to neutral after drop")
	assert(drone.has_payload == false, "Payload flag must be false")
	
	# ----------------------------------------------------
	# 2. Battery Voltage Sag Test
	# ----------------------------------------------------
	# A) Heavy 3.0kg combat drone («СТРІЛА-8»)
	catalog.apply_to_drone(drone, 2)
	print("[TEST] Resting voltage: %.2f V, Sag Factor: %.2f" % [
		drone.battery_cell_voltage, drone.battery_sag_factor
	])
	assert(drone.battery_sag_factor == 1.0, "Resting sag factor must be 1.0")
	
	# Full punch-out (100% throttle on all motors)
	for m in drone.motors:
		m.set_rpm(m.MAX_RPM)
	
	# Simulate 2 seconds of sustained full throttle punch-out
	for step in range(20):
		drone.update_voltage_sag(0.1)
	
	var heavy_sag: float = drone.battery_sag_factor
	var heavy_volts: float = drone.battery_cell_voltage
	print("[TEST] «СТРІЛА-8» Full Throttle Sag: Factor=%.2f, Cell Voltage=%.2f V" % [
		heavy_sag, heavy_volts
	])
	assert(heavy_sag < 0.85, "Heavy combat drone must experience significant voltage sag (<0.85)")
	assert(heavy_volts < 3.6, "Cell voltage must sag below 3.6V under heavy punch-out")
	
	# B) Light 5" drone («КВАД-5» 0.83kg) comparison
	catalog.apply_to_drone(drone, 3)
	for m in drone.motors:
		m.set_rpm(m.MAX_RPM)
	for step in range(20):
		drone.update_voltage_sag(0.1)
	var light_sag: float = drone.battery_sag_factor
	print("[TEST] «КВАД-5» Full Throttle Sag: Factor=%.2f, Cell Voltage=%.2f V" % [
		light_sag, drone.battery_cell_voltage
	])
	assert(light_sag > heavy_sag, "Light combat drone must experience LESS sag than heavy combat drone")
	
	# C) Battery recovery when throttle eased off to idle
	for m in drone.motors:
		m.set_rpm(0.0)
	for step in range(30):
		drone.update_voltage_sag(0.1)
	print("[TEST] After easing off throttle: Sag Factor=%.2f, Cell Voltage=%.2f V" % [
		drone.battery_sag_factor, drone.battery_cell_voltage
	])
	assert(drone.battery_sag_factor > 0.95, "Battery must bounce back when throttle is eased off")
	
	drone.queue_free()
	print("==================================================")
	print("=== STAGE 5 TEST PASSED SUCCESSFULLY! ===")
	print("==================================================")
	get_tree().quit(0)
