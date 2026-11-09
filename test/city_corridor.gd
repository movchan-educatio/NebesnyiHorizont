extends Node


func _ready() -> void:
	var packed := load("res://sceneries/CityLevel.tscn") as PackedScene
	var level := packed.instantiate() as Node3D
	add_child(level)
	await get_tree().create_timer(6.0).timeout
	var city := level.get_node_or_null("City") as Node3D
	var y := (city.global_position.y if city != null else 0.0) + 15.0
	var space: PhysicsDirectSpaceState3D = level.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
			Vector3(-900.0, y, 0.0), Vector3(900.0, y, 0.0))
	q.collision_mask = 1
	var corridor: Dictionary = space.intersect_ray(q)
	print("[CITYCOR] y=", y, " corridor_hit=", not corridor.is_empty(),
			" pos=", corridor.get("position", Vector3.ZERO),
			" col=", (corridor.get("collider") as Node).name if not corridor.is_empty() else "-")
	var q2 := PhysicsRayQueryParameters3D.create(
			Vector3(-900.0, y, 40.0), Vector3(900.0, y, 40.0))
	q2.collision_mask = 1
	var wall: Dictionary = space.intersect_ray(q2)
	print("[CITYCOR] wall_hit=", not wall.is_empty(),
			" pos=", wall.get("position", Vector3.ZERO))
	get_tree().quit()
