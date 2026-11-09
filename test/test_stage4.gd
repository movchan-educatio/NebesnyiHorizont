extends Node

func _ready() -> void:
	print("==================================================")
	print("=== RUNNING STAGE 4 TEST: AERODYNAMIC DRAG & BODY LIFT ===")
	print("==================================================")
	
	var catalog := DroneCatalog
	var drone_scene := load("res://drone/drones/Drone1.tscn") as PackedScene
	assert(drone_scene != null, "Drone1.tscn must load")
	var drone := drone_scene.instantiate() as Drone
	add_child(drone)
	catalog.apply_to_drone(drone, 0)
	
	# 1. Quadratic Drag Test (v vs 2v -> 4x force)
	var v1 := Vector3(0, 0, -10.0) # 10 m/s forward
	var v2 := Vector3(0, 0, -20.0) # 20 m/s forward
	var drag1: Array = drone.get_drag(v1, Vector3.ZERO, Basis.IDENTITY)
	var drag2: Array = drone.get_drag(v2, Vector3.ZERO, Basis.IDENTITY)
	
	var f_drag1: float = abs(drag1[0].z)
	var f_drag2: float = abs(drag2[0].z)
	var ratio := f_drag2 / maxf(f_drag1, 0.0001)
	print("[TEST] Drag at 10m/s: %.3f N, at 20m/s: %.3f N -> Ratio: %.2f (Expected ~4.0x)" % [
		f_drag1, f_drag2, ratio
	])
	assert(ratio >= 3.8 and ratio <= 4.2, "Drag must follow quadratic v^2 law")
	
	# 2. Body Lift in Forward Tilted Flight
	# Drone tilted 35 degrees nose down (positive rotation around +X axis in Godot)
	var tilt_basis := Basis.IDENTITY.rotated(Vector3.RIGHT, deg_to_rad(35.0))
	var forward_flight_vel := Vector3(0, 0, -25.0) # 90 km/h
	var drag_tilted: Array = drone.get_drag(forward_flight_vel, Vector3.ZERO, tilt_basis)
	var world_drag_force: Vector3 = drag_tilted[0]
	print("[TEST] Drag in 35-deg tilt forward flight: Force = %s (Y component = %.3f N)" % [
		world_drag_force, world_drag_force.y
	])
	assert(world_drag_force.y > 0.0, "Aerodynamic body lift must produce positive vertical force")
	
	# 3. Angular Damping
	var spin_rate := Vector3(0, 10.0, 0) # 10 rad/s yaw spin
	var spin_drag: Array = drone.get_drag(Vector3.ZERO, spin_rate, Basis.IDENTITY)
	var damp_torque: Vector3 = spin_drag[1]
	print("[TEST] Damping torque for 10 rad/s yaw spin: %s" % damp_torque)
	assert(damp_torque.y < -0.01, "Angular damping must oppose rotation")
	
	drone.queue_free()
	print("==================================================")
	print("=== STAGE 4 TEST PASSED SUCCESSFULLY! ===")
	print("==================================================")
	get_tree().quit(0)
