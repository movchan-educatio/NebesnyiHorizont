extends Node

## QA: all three valley smokestacks must be open at the top so the drone can
## dive into the bore (the reference video from the player).

func _ready() -> void:
	Global.play_mode = Global.PlayMode.TRAINING
	Global.special_mission = 0
	Global.drone_preset = 6
	var packed := load("res://sceneries/BigLevel.tscn") as PackedScene
	var level := packed.instantiate()
	add_child(level)
	await get_tree().create_timer(7.0).timeout
	var space: PhysicsDirectSpaceState3D = level.get_world_3d().direct_space_state
	var stacks := level.find_children("Smokestack*", "MeshInstance3D", true, false)
	print("[STACKQA] found=", stacks.size())
	var all_open := true
	for n in stacks:
		var mi := n as MeshInstance3D
		var bb: AABB = mi.global_transform * mi.get_aabb()
		var top := bb.end.y
		var c := bb.get_center()
		var q := PhysicsRayQueryParameters3D.create(
				Vector3(c.x, top + 25.0, c.z), Vector3(c.x, top - 2.0, c.z))
		var hit: Dictionary = space.intersect_ray(q)
		var hit_y := 9999.0
		if not hit.is_empty():
			hit_y = (hit["position"] as Vector3).y
		var is_open := hit.is_empty() or hit_y < top - 1.0
		print("[STACKQA] ", mi.name, " top=%.1f hit_y=%.1f open=%s" % [
			top, hit_y, is_open])
		if not is_open:
			all_open = false
	print("[STACKQA] RESULT ", "PASS" if all_open and stacks.size() >= 3 else "FAIL")
	get_tree().quit(0 if (all_open and stacks.size() >= 3) else 1)
