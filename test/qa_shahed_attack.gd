extends Node3D

## Isolated regression test for the Shahed attack run.  It exercises acquire,
## dive, proximity damage, recovery and the unarmed-target safety gate.

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
	shahed.call("_move_along_route", 0.05)
	_check(int(shahed.get("_shahed_phase")) == 1,
			"armed target makes Shahed acquire instead of circle")
	var saw_dive := false
	for _i in range(120):
		shahed.call("_move_along_route", 0.05)
		shahed.call("_update_height", 0.05)
		if int(shahed.get("_shahed_phase")) == 2:
			saw_dive = true
		if combat.hit_count > 0:
			break
	_check(saw_dive or combat.hit_count > 0, "Shahed commits to a dive")
	_check(shahed.global_position.y < cruise_y - 8.0,
			"cruise altitude lock is bypassed during the dive")
	_check(combat.hit_count == 1, "proximity pass damages the armed drone once")
	_check(combat.last_damage > 0.0, "attack damage is difficulty-scaled and non-zero")
	_check(int(shahed.get("_shahed_phase")) == 3,
			"after the attack the Shahed overshoots and recovers")
	var reattacked := false
	for _i in range(600):
		shahed.call("_move_along_route", 0.05)
		shahed.call("_update_height", 0.05)
		if combat.hit_count >= 2:
			reattacked = true
			break
	_check(reattacked, "Shahed returns to patrol and commits to another attack run")

	# Disarming cancels an attack immediately; no extra damage can be delivered.
	target.flight_controller["state_armed"] = false
	for _i in range(8):
		shahed.call("_move_along_route", 0.05)
	_check(int(shahed.get("_shahed_phase")) == 0,
			"disarming returns the Shahed to patrol")
	_check(combat.hit_count == 2, "disarmed drone receives no further attack")

	print("[SHAHED_QA] failures=", _failures,
			" phase=", shahed.get("_shahed_phase"),
			" hit_damage=", combat.last_damage)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(ok: bool, label: String) -> void:
	if ok:
		print("[SHAHED_QA] PASS ", label)
	else:
		_failures += 1
		push_error("[SHAHED_QA] FAIL " + label)
