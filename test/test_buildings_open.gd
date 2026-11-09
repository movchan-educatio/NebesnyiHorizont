extends Node3D

## QA probe for the rebuilt procedural buildings: real door/window holes,
## exact prism roof collision, and no oversized collider over the roof eaves.

const TERRAIN := preload("res://scripts/util/frontline_terrain.gd")

var space: PhysicsDirectSpaceState3D


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	var root := Node3D.new()
	add_child(root)
	var hy := TERRAIN._height("industrial", 0.0, 0.0)
	TERRAIN._add_hall(root, "industrial", Vector2.ZERO, 40.0, 12.0, 24.0,
			0.0, mat, mat)
	var hv := TERRAIN._height("industrial", 100.0, 100.0)
	TERRAIN._add_simple_house(root, "industrial", Vector2(100.0, 100.0), 0.0,
			8.0, 7.0, 3.5, mat, mat, mat)
	var py := hy + 20.0
	TERRAIN._add_prism(root, Vector3(0.0, py, 80.0), Vector3(10.0, 4.0, 8.0),
			mat, 0.0)
	await get_tree().physics_frame
	space = get_world_3d().direct_space_state

	_report("hall_door_clear", _ray(Vector3(10.8, hy + 1.5, -30.0),
			Vector3(10.8, hy + 1.5, 0.0)).is_empty())
	_report("hall_window_clear", _ray(Vector3(5.6, hy + 5.0, -30.0),
			Vector3(5.6, hy + 5.0, 0.0)).is_empty())
	# A real opening must line up with the opposite facade, otherwise the drone
	# enters a short dead-end tunnel and still hits an invisible-looking wall.
	var through_door := _ray(Vector3(10.8, hy + 1.5, -40.0),
			Vector3(10.8, hy + 1.5, 40.0))
	var through_window := _ray(Vector3(5.6, hy + 5.0, -40.0),
			Vector3(5.6, hy + 5.0, 40.0))
	var through_side_door := _ray(Vector3(-40.0, hy + 1.5, 0.0),
			Vector3(40.0, hy + 1.5, 0.0))
	var through_side_window := _ray(Vector3(-40.0, hy + 5.0, 6.0),
			Vector3(40.0, hy + 5.0, 6.0))
	_report("hall_door_through", through_door.is_empty())
	_report("hall_window_through", through_window.is_empty())
	_report("hall_side_door_through", through_side_door.is_empty())
	_report("hall_side_window_through", through_side_window.is_empty())
	if not through_door.is_empty():
		print("[BUILD] door_block=", through_door.get("position"))
	if not through_window.is_empty():
		print("[BUILD] window_block=", through_window.get("position"))
	if not through_side_door.is_empty():
		print("[BUILD] side_door_block=", through_side_door.get("position"))
	if not through_side_window.is_empty():
		print("[BUILD] side_window_block=", through_side_window.get("position"))
	_report("hall_pier_solid", not _ray(Vector3(0.0, hy + 1.5, -30.0),
			Vector3(0.0, hy + 1.5, 0.0)).is_empty())
	_report("hall_side_door_clear", _ray(Vector3(30.0, hy + 1.5, 0.0),
			Vector3(10.0, hy + 1.5, 0.0)).is_empty())

	_report("house_door_clear", _ray(Vector3(100.0, hv + 1.0, 110.0),
			Vector3(100.0, hv + 1.0, 100.0)).is_empty())
	_report("house_window_clear", _ray(Vector3(102.4, hv + 1.9, 110.0),
			Vector3(102.4, hv + 1.9, 100.0)).is_empty())
	_report("house_window_sill_solid", not _ray(Vector3(102.4, hv + 0.6, 110.0),
			Vector3(102.4, hv + 0.6, 100.0)).is_empty())
	_report("house_pier_solid", not _ray(Vector3(103.4, hv + 1.9, 110.0),
			Vector3(103.4, hv + 1.9, 100.0)).is_empty())

	var apex_hit := _ray(Vector3(0.0, py + 10.0, 80.0),
			Vector3(0.0, py - 10.0, 80.0))
	var slope_hit := _ray(Vector3(4.0, py + 10.0, 80.0),
			Vector3(4.0, py - 10.0, 80.0))
	var side_hit := _ray(Vector3(-9.0, py + 1.5, 80.0),
			Vector3(9.0, py + 1.5, 80.0))
	print("[BUILD] prism_apex_y=", _axis(apex_hit, "y"), " expected ", py + 2.0)
	print("[BUILD] prism_slope_y=", _axis(slope_hit, "y"), " expected ", py - 1.2)
	print("[BUILD] prism_side_x=", _axis(side_hit, "x"), " expected -0.625")
	_report("prism_apex_hit", absf(_axis(apex_hit, "y") - (py + 2.0)) < 0.12)
	_report("prism_slope_exact", absf(_axis(slope_hit, "y") - (py - 1.2)) < 0.12)
	_report("prism_no_box_eave", absf(_axis(side_hit, "x") + 0.625) < 0.12)
	get_tree().quit()


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	return space.intersect_ray(q)


func _axis(hit: Dictionary, axis: String) -> float:
	if hit.is_empty():
		return 9999.0
	var p: Vector3 = hit["position"]
	return p.x if axis == "x" else (p.y if axis == "y" else p.z)


func _report(label: String, ok: bool) -> void:
	print("[BUILD] ", label, "=", "PASS" if ok else "FAIL")
