extends Node

## QA: list model nodes/materials that carry flag or stencil markings.

func _ready() -> void:
	for idx in range(DroneCatalog.count()):
		var p := DroneCatalog.preset(idx)
		var path := str(p.get("model", ""))
		if path.is_empty() or not ResourceLoader.exists(path):
			continue
		var model := (load(path) as PackedScene).instantiate() as Node3D
		if model == null:
			continue
		add_child(model)
		for n in model.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			var mats := PackedStringArray()
			for s in range(mi.mesh.get_surface_count()):
				var mat := mi.mesh.surface_get_material(s)
				if mat != null and not String(mat.resource_name).is_empty():
					mats.append(String(mat.resource_name))
			var line := (String(mi.name) + " | " + " / ".join(mats)).to_lower()
			if line.contains("flag") or line.contains("ukrain") or line.contains("stencil") \
					or line.contains("tryzub") or line.contains("trident"):
				print("[MARK] idx=", idx, " ", p.get("name", ""), " node='", mi.name,
						"' mats='", " / ".join(mats), "'")
		model.queue_free()
	await get_tree().process_frame
	get_tree().quit()
