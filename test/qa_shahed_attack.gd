extends Node3D

## Regression test for the Shahed-136 route patrol.  The airframe is a target,
## not an attacker: it must hold cruise altitude, follow its waypoints and never
## dive at, ram or damage the player drone.

const VehicleScript = preload("res://combat/vehicle.gd")

class DummyTarget extends RigidBody3D:
	var flight_controller: Dictionary = {"state_armed": true, "flight_mode": 0}


class CombatStub extends Node:
	var hit_count := 0
	var last_damage := 0.0

	func damage_drone(amount: float, _hit_position: Vector3 = Vector3.ZERO,
			_source_position: Vector3 = Vector3.ZERO) -> void:
		hit_count += 1
		last_damage = amount


var _failures := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(500.0, 2.0, 500.0)
	floor_shape.shape = floor_box
	floor_shape.position.y = -1.0
	ground.add_child(floor_shape)
	add_child(ground)

	var target := DummyTarget.new()
	target.name = "Drone"
	target.gravity_scale = 0.0
	target.position = Vector3(0.0, 7.0, 0.0)
	add_child(target)
	var combat := CombatStub.new()
	combat.name = "CombatSystem"
	add_child(combat)

	var shahed := VehicleScript.new()
	shahed.name = "TestShahed"
	shahed.kind = VehicleScript.Kind.SHAHED
	shahed.hostile = true
	shahed.move_speed = 24.0
	shahed.cruise_height = 42.0
	add_child(shahed)
	shahed.set_physics_process(false)
	shahed.global_position = Vector3(0.0, 42.0, 55.0)
	shahed.set_waypoints([Vector3(0.0, 0.0, 105.0), Vector3(0.0, 0.0, 55.0)])
	await get_tree().physics_frame
	await get_tree().physics_frame

	var cruise_y := shahed.global_position.y
	var start := shahed.global_position
	var min_y := cruise_y
	var moved := 0.0
	for _i in range(400):
		shahed.call("_move_along_route", 0.05)
		shahed.call("_update_height", 0.05)
		min_y = minf(min_y, shahed.global_position.y)
		moved = maxf(moved, start.distance_to(shahed.global_position))
	_check(int(shahed.get("_shahed_phase")) == 0,
			"Shahed stays in route-patrol state near an armed drone")
	_check(absf(min_y - cruise_y) < 1.5,
			"Shahed never leaves cruise altitude (min %.2f, cruise %.2f)" % [
				min_y, cruise_y])
	_check(moved > 30.0, "Shahed keeps flying its route")
	_check(combat.hit_count == 0, "route patrol never damages the player drone")

	# Point-blank hover: the airframe still must not turn into a suicide drone.
	target.global_position = shahed.global_position + Vector3(0.0, -1.0, -7.0)
	for _i in range(120):
		shahed.call("_move_along_route", 0.05)
		shahed.call("_update_height", 0.05)
	_check(int(shahed.get("_shahed_phase")) == 0,
			"point-blank player proximity does not trigger an attack state")
	_check(combat.hit_count == 0, "point-blank proximity deals no damage")
	_check(absf(shahed.global_position.y - (cruise_y)) < 3.0,
			"point-blank proximity does not pull the Shahed into a dive")

	print("[SHAHED_QA] failures=", _failures,
			" phase=", shahed.get("_shahed_phase"),
			" hits=", combat.hit_count)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(ok: bool, label: String) -> void:
	if ok:
		print("[SHAHED_QA] PASS ", label)
	else:
		_failures += 1
		push_error("[SHAHED_QA] FAIL " + label)
