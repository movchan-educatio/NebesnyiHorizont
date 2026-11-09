extends Node3D

## QA: inspect the authored hero halls for baked collision.  Any StaticBody3D
## imported from the GLB with oversized box shapes is an invisible wall around
## the visible facade.
const ASSETS := ["industrial_hall.glb", "village_hall.glb", "steppe_hall.glb",
		"wetlands_hall.glb"]


func _ready() -> void:
	for asset in ASSETS:
		var path := "res://Assets/frontline/" + asset
		if not ResourceLoader.exists(path):
			print("[HALLCOL] ", asset, " missing")
			continue
		var packed := load(path) as PackedScene
		var inst := packed.instantiate()
		add_child(inst)
		await get_tree().process_frame
		var bodies: Array = inst.find_children("*", "CollisionObject3D", true, false)
		print("[HALLCOL] ", asset, " bodies=", bodies.size())
		for b in bodies:
			var shapes: Array = b.find_children("*", "CollisionShape3D", true, false)
			print("   body=", b.name, " class=", b.get_class(), " shapes=", shapes.size())
			for s in shapes:
				var cs := s as CollisionShape3D
				if cs.shape == null:
					print("      shape=null")
					continue
				var aabb := AABB()
				if cs.shape is BoxShape3D:
					var bs := cs.shape as BoxShape3D
					aabb = AABB(-bs.size * 0.5, bs.size)
				elif cs.shape is ConcavePolygonShape3D:
					var tri := cs.shape as ConcavePolygonShape3D
					var faces: PackedVector3Array = tri.get_faces()
					for v in faces:
						if aabb.size == Vector3.ZERO:
							aabb = AABB(v, Vector3.ZERO)
						else:
							aabb = aabb.expand(v)
					print("      trimesh_faces=", faces.size())
				print("      shape=", cs.shape.get_class(), " aabb=", aabb,
						" xf_pos=", cs.position)
		inst.queue_free()
		await get_tree().process_frame
	get_tree().quit()
