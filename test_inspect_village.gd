extends Node3D

func _ready():
	print("=== RUNNING VILLAGE LEVEL INSPECTOR ===")
	Global.play_mode = Global.PlayMode.TRAINING
	var packed = load("res://sceneries/VillageLevel.tscn")
	var level = packed.instantiate()
	add_child(level)
	
	# Wait 2 frames for physics and transforms to update
	await get_tree().process_frame
	await get_tree().process_frame
	
	var drone = level.get_node_or_null("Drone")
	if drone == null:
		print("ERROR: Drone not found!")
		get_tree().quit()
		return
		
	print("Drone global_position: ", drone.global_position)
	print("Drone rotation: ", drone.rotation)
	
	var pos = drone.global_position
	var space = get_world_3d().direct_space_state
	
	# Raycast straight up
	var up_query = PhysicsRayQueryParameters3D.create(pos, pos + Vector3(0, 100, 0))
	up_query.exclude = [drone.get_rid()]
	var up_hit = space.intersect_ray(up_query)
	if not up_hit.is_empty():
		print("COLLIDER ABOVE DRONE: ", up_hit["collider"].name, " (", up_hit["collider"].get_class(), ") at ", up_hit["position"])
		var parent = up_hit["collider"].get_parent()
		if parent != null:
			print("  Parent: ", parent.name, " (", parent.get_class(), ")")
	else:
		print("No physics collider directly above drone.")
		
	# Find ALL VisualInstance3D nodes in radius 40m
	print("\nVisualInstance3D nodes within 35m of drone:")
	for node in level.find_children("*", "VisualInstance3D", true, false):
		var vi = node as VisualInstance3D
		if vi == null or not vi.visible:
			continue
		var gp = vi.global_position
		var d = pos.distance_to(gp)
		if d < 35.0:
			print(" - [dist=%.1f] %s (parent: %s, pos: %s)" % [d, vi.name, vi.get_parent().name if vi.get_parent() else "null", gp])
			
	print("\n=== FINISHED INSPECTION ===")
	get_tree().quit()
