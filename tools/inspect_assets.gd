extends SceneTree

func _init() -> void:
	_dump("res://Assets/frontline/village_cottage.glb")
	_dump("res://Assets/frontline/industrial_hall.glb")
	quit()

func _dump(path: String) -> void:
	print("\n==== ", path, " ====")
	var packed := load(path) as PackedScene
	if packed == null:
		print("  MISSING")
		return
	var root := packed.instantiate()
	print("root=", root.name, " type=", root.get_class())
	_walk(root, "  ")
	root.free()

func _walk(n: Node, indent: String) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var aabb := mi.mesh.get_aabb() if mi.mesh != null else AABB()
		print(indent, n.name, " [Mesh] aabb=", aabb, " surfaces=", mi.mesh.get_surface_count() if mi.mesh else 0)
		if mi.mesh != null:
			for s in range(mi.mesh.get_surface_count()):
				var mat := mi.mesh.surface_get_material(s)
				var mn := mat.resource_name if mat != null else "<none>"
				var tri := 0
				var arrays := mi.mesh.surface_get_arrays(s)
				if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] != null:
					tri = (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
				elif arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] != null:
					tri = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
				print(indent, "   surf ", s, " mat='", mn, "' tris=", tri)
	elif n is Node3D:
		var n3 := n as Node3D
		print(indent, n.name, " [", n.get_class(), "] pos=", n3.position, " rot=", n3.rotation, " scale=", n3.scale)
	else:
		print(indent, n.name, " [", n.get_class(), "]")
	for c in n.get_children():
		_walk(c, indent + "  ")
