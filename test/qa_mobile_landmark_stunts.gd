extends Node

## Fast landmark-opening regression: instantiates the six landmark GLBs
## directly (no full map load) and casts rays through the ridge skylights, the
## hollow chimney, the cargo holds and the door bays.  Doors face -Z after the
## glTF axis conversion.
const TEST_NAME := "LANDMARK_STUNTS"
const ROOT := "res://Assets/handcrafted/landmarks/"
var _failures := 0
var _world: Node3D


func _ready() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	print("[", TEST_NAME, "] ", "PASS " if ok else "FAIL ", label)
	if not ok:
		_failures += 1


func _run() -> void:
	_world = Node3D.new()
	add_child(_world)
	var cases := {
		"warehouse": [
			["ridge skylight", Vector3(0, 30, 0), 2.0, true],
			["door bay", Vector3(0, 2.5, 14), 24.0, true, Vector3(0, 2.5, -14)],
		],
		"factory_plant": [
			["ridge skylight", Vector3(0, 30, 0), 2.0, true],
			["chimney", Vector3(17.5, 30, 6.0), 1.0, true],
			["door bay", Vector3(0, 2.5, 12), 20.0, true, Vector3(0, 2.5, -12)],
		],
		"farm_complex": [
			["ridge skylight", Vector3(0, 30, 0), 2.0, true],
			["door bay", Vector3(0, 2.2, 10), 8.0, true, Vector3(0, 2.2, -10)],
		],
		"cargo_ship": [
			["hold A", Vector3(-8, 20, 0), 4.0, true],
			["hold B", Vector3(6, 20, 0), 4.0, true],
		],
	}
	for name in cases:
		var packed := load(ROOT + name + ".glb") as PackedScene
		if packed == null:
			_check(false, name + " loads")
			continue
		var inst := packed.instantiate() as Node3D
		_world.add_child(inst)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var space := _world.get_world_3d().direct_space_state
		for case in cases[name]:
			if bool(case[3]) and case.size() >= 5:
				var length := _ray_length(space, inst, case[1], case[4])
				_check(length > float(case[2]),
						"%s %s is open (%.1f m)" % [name, case[0], length])
			else:
				var y := _down_hit(space, inst, case[1], float(case[2]))
				# A hollow shell has no floor in the GLB, so "no hit" also means
				# the roof/hull opening is clear; a solid roof stops the ray at
				# the roof height and fails.
				var open := is_inf(y) or y < float(case[2])
				_check(open, "%s %s is open (hit y=%.2f)"
						% [name, case[0], y])
		inst.queue_free()
		await get_tree().process_frame
	print("[", TEST_NAME, "] failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _down_hit(space: PhysicsDirectSpaceState3D, prop: Node3D, local: Vector3,
		limit: float) -> float:
	var from := prop.to_global(local)
	var to := prop.to_global(Vector3(local.x, -2.0, local.z))
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return INF
	return float(hit["position"].y) - prop.global_position.y


func _ray_length(space: PhysicsDirectSpaceState3D, prop: Node3D, a: Vector3,
		b: Vector3) -> float:
	var from := prop.to_global(a)
	var to := prop.to_global(b)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return 1000.0
	return from.distance_to(hit["position"])
