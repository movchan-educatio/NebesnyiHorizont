extends SceneTree

## Debug: inspect the imported warehouse collision body and cast rays in a
## minimal physics world (much faster than loading the whole level).
func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var packed := load("res://Assets/handcrafted/landmarks/warehouse.glb") as PackedScene
	var inst := packed.instantiate() as Node3D
	root.add_child(inst)
	for n in inst.find_children("*", "", true, false):
		if n is StaticBody3D:
			var body := n as StaticBody3D
			print("BODY name=", body.name, " layer=", body.collision_layer,
					" mask=", body.collision_mask, " pos=", body.position,
					" children=", body.get_child_count())
			for c in body.get_children():
				if c is CollisionShape3D:
					print("  SHAPE disabled=", (c as CollisionShape3D).disabled,
							" shape=", (c as CollisionShape3D).shape)
	await physics_frame
	await physics_frame
	var space := root.get_world_3d().direct_space_state
	for z in [12.0, 9.0, 0.0, -9.0]:
		var from := inst.to_global(Vector3(0.0, 2.5, z))
		var to := inst.to_global(Vector3(0.0, 2.5, z - 1.0))
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.collision_mask = 1
		var hit := space.intersect_ray(q)
		print("RAY z=", z, " hit=", not hit.is_empty(),
				" y=", hit.get("position", Vector3.ZERO))
	quit(0)
