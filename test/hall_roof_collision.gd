extends Node

## QA: raycast up from inside the industrial hero hall.  A roof collider must
## stop the ray; otherwise the player can fly through the roof.


func _ready() -> void:
	var packed := load("res://sceneries/IndustrialLevel.tscn") as PackedScene
	var level := packed.instantiate() as Node3D
	add_child(level)
	await get_tree().create_timer(5.0).timeout
	var ft = load("res://scripts/util/frontline_terrain.gd")
	var gy: float = ft.height_at("industrial", 50.0, 80.0)
	var space: PhysicsDirectSpaceState3D = level.get_world_3d().direct_space_state
	var from := Vector3(50.0, gy + 2.0, 80.0)
	var to := Vector3(50.0, gy + 70.0, 80.0)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		print("[ROOF] NO HIT from inside -> roof collision missing")
	else:
		var col = hit.get("collider")
		print("[ROOF] hit y=", snappedf((hit["position"] as Vector3).y, 0.1),
				" collider=", (col.name if col != null else "null"))
	get_tree().quit()
