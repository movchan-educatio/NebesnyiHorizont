extends SceneTree

## Debug: confirm the Blender prop pack imported with vertex colours and a
## single material, so the shared vertex-colour override renders in-game.
func _init() -> void:
	var dir := "res://Assets/handcrafted/props_lowpoly/"
	var files := DirAccess.get_files_at(dir)
	var checked := 0
	for f in files:
		if not String(f).ends_with(".glb"):
			continue
		var packed := load(dir + f) as PackedScene
		if packed == null:
			print("PROP_GLB FAIL load ", f)
			continue
		var model := packed.instantiate() as Node3D
		var meshes := 0
		var has_color := true
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var mesh := (mi as MeshInstance3D).mesh
			if mesh == null:
				continue
			meshes += 1
			for s in range(mesh.get_surface_count()):
				var arrays := mesh.surface_get_arrays(s)
				if arrays[Mesh.ARRAY_COLOR] == null:
					has_color = false
		print("PROP_GLB ", f, " meshes=", meshes, " color=", has_color)
		model.free()
		checked += 1
	print("PROP_GLB total=", checked)
	quit(0)
