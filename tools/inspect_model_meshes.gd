extends SceneTree

func _init() -> void:
	var models = [
		"holka.glb", "pinapipe.glb", "avata2.glb", "pisun_vtol.glb",
		"peleng.glb", "grim7.glb", "grim7m.glb", "strila8.glb"
	]
	for m in models:
		print("========================================")
		print("MODEL: ", m)
		var scn = load("res://Assets/Drones/ua_norm/" + m)
		if scn:
			var inst: Node3D = scn.instantiate()
			var meshes := []
			_find_meshes(inst, meshes)
			print("Total MeshInstances: ", meshes.size())
			for mi: MeshInstance3D in meshes:
				var aabb := mi.get_aabb()
				print("  Mesh: '%s' pos=%s size=%s parent='%s'" % [
					mi.name, str(mi.position), str(aabb.size), mi.get_parent().name
				])
	quit(0)

func _find_meshes(node: Node, list: Array) -> void:
	if node is MeshInstance3D:
		list.append(node)
	for ch in node.get_children():
		_find_meshes(ch, list)
