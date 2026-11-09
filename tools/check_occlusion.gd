extends SceneTree


func _init() -> void:
	print("[OCC-CHECK] set_vertices=", ClassDB.class_has_method("ArrayOccluder3D", "set_vertices"))
	print("[OCC-CHECK] set_indices=", ClassDB.class_has_method("ArrayOccluder3D", "set_indices"))
	var has_prop := false
	for p in ClassDB.class_get_property_list("Viewport"):
		if String(p.get("name", "")) == "use_occlusion_culling":
			has_prop = true
	print("[OCC-CHECK] viewport_prop=", has_prop)
	print("[OCC-CHECK] project=", ProjectSettings.get_setting("rendering/occlusion_culling/use_occlusion_culling"))
	quit()
