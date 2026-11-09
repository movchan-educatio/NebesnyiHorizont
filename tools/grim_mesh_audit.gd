extends Node

## QA: list mesh names, bounds and materials inside the Grim-7M GLB.

func _ready() -> void:
	var packed := load("res://Assets/Drones/ua_norm/grim7m.glb") as PackedScene
	var model := packed.instantiate() as Node3D
	add_child(model)
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var aabb := mi.get_aabb()
		print("[GRIM] ", mi.name, " size=", aabb.size, " pos=", aabb.position,
				" global_pos=", mi.global_position)
		for s in range(mi.mesh.get_surface_count()):
			var mat := mi.mesh.surface_get_material(s)
			var mat_name := ""
			var tex_path := ""
			var albedo := Color.BLACK
			if mat is StandardMaterial3D:
				mat_name = String(mat.resource_name)
				albedo = mat.albedo_color
				if mat.albedo_texture != null:
					tex_path = mat.albedo_texture.resource_path
			print("    surface ", s, " mat=", mat_name, " albedo=", albedo,
					" tex=", tex_path,
					" override=", mi.get_surface_override_material(s))
	get_tree().quit(0)
