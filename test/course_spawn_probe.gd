extends Node

## QA: inspect the Course gate layout and the current spawn so the start point
## can be placed behind gate 0 instead of in a random city street.

func _ready() -> void:
	var packed := load("res://sceneries/CourseLevel.tscn") as PackedScene
	var level := packed.instantiate()
	add_child(level)
	await get_tree().create_timer(4.0).timeout
	var track := level.get_node_or_null("Track")
	var d := level.get_node_or_null("Drone")
	var respawn := level.get_node_or_null("Respawn") as Node3D
	print("[COURSE] drone=", d.global_position if d != null else "null",
			" respawn=", respawn.global_position if respawn != null else "null")
	if track != null:
		var cps: Array = track.get("checkpoints")
		print("[COURSE] checkpoints=", cps.size())
		for i in range(mini(cps.size(), 10)):
			var cp := cps[i] as Node3D
			if cp == null:
				continue
			var xf := cp.global_transform
			print("[COURSE] cp", i, " name=", cp.name, " pos=", xf.origin,
					" fwd=", -xf.basis.z, " up=", xf.basis.y)
	get_tree().quit()
