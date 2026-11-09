extends Node

func _ready() -> void:
	var p: Dictionary = DroneCatalog.preset(13)
	var packed := load(str(p["model"])) as PackedScene
	var model := packed.instantiate() as Node3D
	add_child(model)
	DroneCatalog._apply_composite_detail(model, 13)
	await get_tree().process_frame
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var mats: Array[String] = []
		if mi.mesh != null:
			for s in range(mi.mesh.get_surface_count()):
				var m := mi.mesh.surface_get_material(s)
				mats.append(str(m.resource_name) if m != null else "null")
		print("[LELEKA] mesh=", mi.name, " override=", mi.material_override,
				" override_color=", (mi.material_override as StandardMaterial3D).albedo_color
				if mi.material_override is StandardMaterial3D else "n/a",
				" mats=", mats)
	get_tree().quit(0)
