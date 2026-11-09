extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1, 2, 3)
	mi.mesh = bm
	root.add_child(mi)
	mi.position = Vector3(10, 0, 0)
	var local := mi.get_aabb()
	var world := mi.get_aabb() * mi.global_transform
	print("[AABB-TEST] local=", local, " world=", world)
	mi.queue_free()

	var inst: Node3D = load("res://Assets/vehicles/low-poly_bmp-2m.glb").instantiate()
	root.add_child(inst)
	print("[AABB-TEST] bmp root scale=", inst.scale)
	_dump(inst, 0)
	quit()


func _dump(node: Node, depth: int) -> void:
	if depth > 4:
		return
	if node is MeshInstance3D:
		var v := node as MeshInstance3D
		var la := v.get_aabb()
		var wa: AABB = la * v.global_transform
		print("[AABB-MESH] ", node.name, " local_size=", la.size, " world_size=", wa.size,
				" pos=", wa.position)
	for child in node.get_children():
		_dump(child, depth + 1)
