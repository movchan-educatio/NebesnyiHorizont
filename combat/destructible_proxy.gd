class_name DestructibleProxy
extends StaticBody3D

## Lightweight proxy script attached to authored StaticBody3D nodes inside
## destructible landmarks (such as arch, bridges, checkpoints).
## Forwards damage to the parent DestructibleLandmark so the authored
## collision geometry (including holes/openings) is preserved.

var landmark: Node = null


func take_damage(amount: float, hit_position: Vector3 = Vector3.ZERO) -> void:
	if landmark != null and is_instance_valid(landmark):
		landmark.call("take_damage", amount, hit_position)
