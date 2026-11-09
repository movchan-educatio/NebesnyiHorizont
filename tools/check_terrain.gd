@tool
extends SceneTree

func _init():
	var scene = load("res://sceneries/BigLevel.tscn")
	if scene:
		var inst = scene.instantiate()
		root.add_child(inst)
		var space = inst.get_world_3d().direct_space_state
		print("=== TERRAIN ELEVATION AUDIT ===")
		for z in [200.0, 240.0, 280.0, 300.0, 320.0, 340.0, 360.0]:
			for x in [-80.0, -40.0, 0.0, 40.0, 80.0]:
				var from = Vector3(x, 400.0, z)
				var to = Vector3(x, -200.0, z)
				var query = PhysicsRayQueryParameters3D.create(from, to)
				query.collision_mask = 1
				var hit = space.intersect_ray(query)
				if hit:
					print("X=", x, " Z=", z, " -> Y=", hit.position.y, " col=", hit.collider.name)
	quit()
