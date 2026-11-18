extends Node3D

## Mobile vehicle engagement profile checks: SAM/BMP hold distance, the
## helicopter orbits while engaging, and the truck flees faster. These are
## behaviour assertions on a synthetic scene, not measurements on a device.
class TestFlightController:
	extends Node
	var state_armed := true


class TestDrone:
	extends Node3D
	var flight_controller: Node = null


var _failures := 0


func _ready() -> void:
	OS.set_environment("MOBILE_UI", "1")
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	print("[MOBILE_VEHICLE] ", "PASS " if ok else "FAIL ", label)
	if not ok:
		_failures += 1


## The synthetic test scene has no world colliders; remove the vehicle's own
## StaticBody children so the engagement line-of-sight ray reaches the drone.
func _neutralize_self_colliders(vehicle: Vehicle) -> void:
	for body in vehicle.find_children("*", "StaticBody3D", true, false):
		(body as StaticBody3D).collision_layer = 0
		(body as StaticBody3D).collision_mask = 0


func _run() -> void:
	var drone := TestDrone.new()
	drone.name = "QaDrone"
	add_child(drone)
	var fc := TestFlightController.new()
	fc.name = "flight_controller"
	drone.add_child(fc)
	drone.flight_controller = fc
	await get_tree().physics_frame

	var sam := Vehicle.new()
	sam.kind = Vehicle.Kind.SAM
	add_child(sam)
	_neutralize_self_colliders(sam)
	sam.hostile = true
	sam.fire_range = 150.0
	sam.move_speed = 8.0
	sam._drone = drone
	sam.global_position = Vector3(0, 0, 0)
	drone.global_position = Vector3(0, 0, 40)
	sam.call("_combat_engage", 0.1)
	_check(bool(sam.get("_retreating")), "SAM retreats under 35% of its fire range")
	_check(sam.global_position.distance_to(drone.global_position) > 40.0,
			"SAM increases distance while retreating")

	var bmp := Vehicle.new()
	bmp.kind = Vehicle.Kind.BMP
	add_child(bmp)
	_neutralize_self_colliders(bmp)
	bmp.hostile = true
	bmp.fire_range = 120.0
	bmp.move_speed = 7.0
	bmp._drone = drone
	bmp.global_position = Vector3(0, 0, 0)
	drone.global_position = Vector3(0, 0, 35)
	bmp.call("_combat_engage", 0.1)
	_check(bool(bmp.get("_retreating")), "BMP retreats under 35% of its fire range")

	var heli := Vehicle.new()
	heli.kind = Vehicle.Kind.HELI
	add_child(heli)
	_neutralize_self_colliders(heli)
	heli.hostile = true
	heli.fire_range = 140.0
	heli.move_speed = 12.0
	heli._drone = drone
	heli.global_position = Vector3(0, 8, 60)
	drone.global_position = Vector3(0, 8, 0)
	heli.call("_combat_engage", 0.2)
	_check(float(heli.get("_orbit_phase")) > 0.0,
			"helicopter advances its orbit phase while engaging")
	_check(heli.global_position.distance_to(drone.global_position) < 95.0,
			"helicopter holds the engagement ring instead of closing straight in")

	var truck := Vehicle.new()
	truck.kind = Vehicle.Kind.TRUCK
	add_child(truck)
	# Only hostile supply/recon trucks break away from an approaching armed
	# drone; a friendly one keeps its route speed.
	truck.hostile = true
	truck.move_speed = 10.0
	truck._damage_speed_mult = 1.0
	truck.meander_amplitude = 0.0
	truck._drone = drone
	truck._waypoints = PackedVector3Array([Vector3(120, 0, -200)])
	truck.global_position = Vector3(120, 0, 0)
	drone.global_position = Vector3(120, 0, 50)
	truck.call("_move_along_route", 0.5)
	var truck_speed := float(truck.get("_step")) / 0.5
	_check(truck_speed >= 14.5, "truck flees faster on mobile (%.1f m/s)" % truck_speed)

	var apc := Vehicle.new()
	apc.kind = Vehicle.Kind.APC
	add_child(apc)
	_neutralize_self_colliders(apc)
	apc.hostile = true
	apc.fire_range = 110.0
	apc.move_speed = 9.0
	apc._drone = drone
	apc.global_position = Vector3(0, 0, 0)
	drone.global_position = Vector3(0, 0, 40)
	apc.call("_combat_engage", 0.1)
	_check(bool(apc.get("_retreating")), "APC retreats under 45% of its fire range")

	var tank := Vehicle.new()
	tank.kind = Vehicle.Kind.TANK
	add_child(tank)
	_neutralize_self_colliders(tank)
	tank.hostile = true
	tank.fire_range = 125.0
	tank.move_speed = 6.0
	tank.meander_amplitude = 0.0
	tank.halt_interval = 0.0
	tank._drone = drone
	tank._waypoints = PackedVector3Array([Vector3(0, 0, -100)])
	tank.global_position = Vector3(0, 0, 0)
	drone.global_position = Vector3(0, 0, 60)
	tank.call("_combat_engage", 0.1)
	var tank_z_before := tank.global_position.z
	tank.call("_physics_process", 0.1)
	_check(bool(tank.get("_engaging")) and absf(tank.global_position.z - tank_z_before) < 0.01,
			"tank holds position while engaging on mobile")

	var shahed := Vehicle.new()
	shahed.kind = Vehicle.Kind.SHAHED
	add_child(shahed)
	shahed.hostile = true
	shahed.move_speed = 14.0
	shahed._damage_speed_mult = 1.0
	shahed.meander_amplitude = 0.0
	shahed._drone = drone
	shahed._waypoints = PackedVector3Array([Vector3(0, 0, -200)])
	shahed.global_position = Vector3(0, 0, 0)
	drone.global_position = Vector3(0, 0, 80)
	shahed.call("_move_along_route", 0.5)
	shahed.call("_move_along_route", 0.5)
	shahed.call("_move_along_route", 0.5)
	var to_wp := Vector3(0.0, 0.0, -200.0) - shahed.global_position
	to_wp.y = 0.0
	var forward := -shahed.global_transform.basis.z
	forward.y = 0.0
	var angle_deg := rad_to_deg(absf(angle_difference(atan2(-forward.x, -forward.z),
			atan2(-to_wp.x, -to_wp.z))))
	_check(angle_deg < 20.0, "Shahed follows its route waypoint on mobile (%.1f deg)" % angle_deg)
	_check(int(shahed.get("_shahed_phase")) == 0,
			"Shahed stays in route patrol near the armed drone on mobile")
	_check(not bool(shahed.get("_engaging")),
			"Shahed does not enter an attack engagement on mobile")

	print("[MOBILE_VEHICLE] failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)
