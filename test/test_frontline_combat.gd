extends Node

## Headless check for the vehicle weak-spot damage model and bonus score.

var _failed := false


func _ready() -> void:
	var vehicle := Vehicle.new()
	vehicle.kind = Vehicle.Kind.TANK
	add_child(vehicle)
	await get_tree().process_frame

	var spots: Array = vehicle.get("_weak_spots")
	_check(spots.size() == 2, "tank has engine and ammo weak spots")

	var engine: Dictionary = spots[0]
	var engine_world: Vector3 = vehicle.to_global(engine["pos"])
	var before: float = vehicle.health
	vehicle.take_damage(10.0, engine_world)
	var dealt: float = before - vehicle.health
	_check(is_equal_approx(dealt, 10.0 * float(engine["mult"])),
			"engine hit deals %.1f damage (x%.2f)" % [dealt, float(engine["mult"])])
	_check(int(vehicle.get("_bonus_points")) == int(engine["bonus"]),
			"engine hit awards %d bonus points" % int(engine["bonus"]))

	# Second hit on the same module must not farm the bonus again.
	before = vehicle.health
	vehicle.take_damage(10.0, engine_world)
	dealt = before - vehicle.health
	_check(is_equal_approx(dealt, 10.0 * float(engine["mult"])),
			"engine stays vulnerable after the first hit")
	_check(int(vehicle.get("_bonus_points")) == int(engine["bonus"]),
			"engine bonus is awarded once")

	# A hit on the thick front glacis uses the normal damage multiplier.
	var front: Vector3 = vehicle.to_global(Vector3(0.0, 0.7, -3.2))
	before = vehicle.health
	vehicle.take_damage(10.0, front)
	dealt = before - vehicle.health
	_check(is_equal_approx(dealt, 10.0), "front hull hit deals normal damage")

	var ammo_world: Vector3 = vehicle.to_global(spots[1]["pos"])
	before = vehicle.health
	vehicle.take_damage(10.0, ammo_world)
	dealt = before - vehicle.health
	_check(is_equal_approx(dealt, 10.0 * float(spots[1]["mult"])),
			"ammo rack hit deals %.1f damage" % dealt)
	_check(int(vehicle.get("_bonus_points")) ==
			int(engine["bonus"]) + int(spots[1]["bonus"]),
			"ammo bonus stacks with engine bonus")

	vehicle.queue_free()
	await get_tree().process_frame
	if _failed:
		print("FRONTLINE COMBAT TEST: FAIL")
	else:
		print("FRONTLINE COMBAT TEST: PASS")
	get_tree().quit(1 if _failed else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[PASS] ", message)
	else:
		_failed = true
		print("[FAIL] ", message)
