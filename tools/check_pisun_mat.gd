@tool
extends SceneTree

func _init() -> void:
	var path := "res://Assets/Drones/ua_norm/pisun_vtol.glb"
	var scn := load(path) as PackedScene
	var inst := scn.instantiate()
	for child in inst.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			print("Child: ", mi.name)
			if mi.mesh:
				for s in range(mi.mesh.get_surface_count()):
					var mat: Material = mi.mesh.surface_get_material(s)
					if mat is StandardMaterial3D:
						var sm := mat as StandardMaterial3D
						print("  mesh surface ", s, " mat: albedo=", sm.albedo_color, " tex=", sm.albedo_texture)
					else:
						print("  mesh surface ", s, " mat: ", mat)
	quit()
