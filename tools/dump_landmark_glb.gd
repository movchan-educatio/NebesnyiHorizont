extends SceneTree

## Debug: confirm the Blender landmark GLBs import with a visual mesh and the
## hollow "-colonly" StaticBody3D that the glTF importer creates.
func _init() -> void:
	var dir := "res://Assets/handcrafted/landmarks/"
	for f in DirAccess.get_files_at(dir):
		if not String(f).ends_with(".glb"):
			continue
		var packed := load(dir + f) as PackedScene
		if packed == null:
			print("LANDMARK_GLB FAIL ", f)
			continue
		var model := packed.instantiate()
		var bodies := 0
		var meshes := 0
		var shapes := 0
		for n in model.find_children("*", "", true, false):
			if n is StaticBody3D:
				bodies += 1
			if n is MeshInstance3D:
				meshes += 1
			if n is CollisionShape3D:
				shapes += 1
		print("LANDMARK_GLB ", f, " meshes=", meshes, " bodies=", bodies,
				" shapes=", shapes)
		model.free()
	quit(0)
