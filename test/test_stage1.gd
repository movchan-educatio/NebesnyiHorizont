extends Node

func _ready() -> void:
	print("==================================================")
	print("=== RUNNING STAGE 1 TEST: MASS & COG DISTRIBUTION ===")
	print("==================================================")
	
	# 1. Test DroneCatalog presets
	var catalog := DroneCatalog
	var preset_count := catalog.count()
	print("[TEST] Presets in catalog: ", preset_count)
	assert(preset_count >= 8, "Expected at least 8 presets in catalog")
	
	for i in range(preset_count):
		var p := catalog.preset(i)
		var total_m := float(p["dry"]) + float(p["batt"]) + float(p["payload_mass"])
		var cog: Vector3 = p["cog_offset"]
		var dims: Vector3 = p["dimensions"]
		print(" Preset %d [%s]: dry=%.2f batt=%.2f payload=%.2f -> total=%.2f kg, CoG=%s, Dims=%s" % [
			i, p["name"], p["dry"], p["batt"], p["payload_mass"], total_m, cog, dims
		])
		if not p.get("is_naval", false):
			# Real airframes span 0.6 kg racing quads to the 50.8 kg bomber and
			# the 12 kg jet interceptor; keep a per-class sanity range.
			if bool(p.get("heavy_bomber", false)):
				assert(total_m > 20.0 and total_m < 80.0, "Heavy bomber mass out of realistic range")
			elif bool(p.get("fixed_wing", false)):
				assert(total_m > 3.0 and total_m < 20.0, "Fixed-wing UAV mass out of realistic range")
			else:
				assert(total_m > 0.3 and total_m < 4.5, "Mass out of realistic range")
		else:
			assert(total_m > 500.0 and total_m < 2000.0, "Naval drone mass out of realistic range")
		assert(dims.length() > 0.1, "Dimensions must be non-zero")
	
	# 2. Test Drone instantiation and physics properties
	var drone_scene := load("res://drone/drones/Drone1.tscn") as PackedScene
	assert(drone_scene != null, "Drone1.tscn must load")
	var drone := drone_scene.instantiate() as Drone
	add_child(drone)
	
	# Test Freestyle preset («ГОЛКА»)
	catalog.apply_to_drone(drone, 0)
	print("[TEST] Preset 0 («ГОЛКА»): Mass = %.2f kg, CoG = %s, Inertia = %s" % [
		drone.mass, drone.center_of_mass, drone.inertia
	])
	assert(abs(drone.mass - 0.60) < 0.01, "Holka mass should be 0.60 kg")
	assert(Vector2(drone.center_of_mass.x, drone.center_of_mass.z).length() < 0.001 and drone.center_of_mass.y < 0.02, "Holka CoG should be centered")
	var holka_inertia := drone.inertia
	
	# Test Heavy Strike preset («СТРІЛА-8»)
	catalog.apply_to_drone(drone, 7)
	print("[TEST] Preset 7 («СТРІЛА-8»): Mass = %.2f kg, CoG = %s, Inertia = %s" % [
		drone.mass, drone.center_of_mass, drone.inertia
	])
	assert(abs(drone.mass - 3.00) < 0.01, "Strila-8 mass should be 3.00 kg")
	assert(drone.center_of_mass.y < -0.015, "Strila-8 CoG must be shifted down")
	assert(drone.center_of_mass.z < -0.01, "Strila-8 CoG must be shifted forward")
	assert(drone.inertia.x > holka_inertia.x * 3.0, "Heavy drone pitch inertia must be much larger than light drone")
	
	# Test Payload Drop toggle on «СТРІЛА-8»
	drone.set_payload_attached(false)
	print("[TEST] After payload dropped: Mass = %.2f kg, CoG = %s, Inertia = %s" % [
		drone.mass, drone.center_of_mass, drone.inertia
	])
	assert(abs(drone.mass - 1.60) < 0.01, "Empty Strila-8 mass should be 1.60 kg")
	assert(Vector2(drone.center_of_mass.x, drone.center_of_mass.z).length() < 0.001 and drone.center_of_mass.y < 0.02, "Empty Strila-8 CoG should return to neutral")
	
	# Cleanup
	drone.queue_free()
	print("==================================================")
	print("=== STAGE 1 TEST PASSED SUCCESSFULLY! ===")
	print("==================================================")
	get_tree().quit(0)
