extends Node

## QA helper: list visible MeshInstance3D nodes that are direct children of
## FrontlineTerrain (the per-map "procedural" draw calls) with the reason the
## static batcher left them alone.

func _ready() -> void:
	var level_path := OS.get_environment("QA_UNBATCHED_LEVEL")
	if level_path.is_empty():
		level_path = "res://sceneries/VillageLevel.tscn"
	var packed := load(level_path) as PackedScene
	var level := packed.instantiate()
	add_child(level)
	await get_tree().create_timer(4.0).timeout
	var ft := level.get_node_or_null("FrontlineTerrain")
	if ft == null:
		print("[UNB] no terrain")
		get_tree().quit()
		return
	var rows: Array = []
	for node in ft.get_children():
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var mat := mi.material_override
		if mat == null and mi.mesh.get_surface_count() > 0:
			mat = mi.mesh.surface_get_material(0)
		var mat_type := "null"
		if mat != null:
			mat_type = mat.get_class()
		var arrays = mi.mesh.surface_get_arrays(0)
		var box: AABB = mi.global_transform * mi.get_aabb()
		rows.append("%s | surf=%d | mat=%s | size=%.1f | uv2=%s | custom=%s | visible=%s" % [
			String(mi.name), mi.mesh.get_surface_count(), mat_type,
			maxf(box.size.x, maxf(box.size.y, box.size.z)),
			"y" if arrays[Mesh.ARRAY_TEX_UV2] != null else "n",
			"y" if arrays[Mesh.ARRAY_CUSTOM0] != null else "n",
			str(mi.visible)])
	rows.sort()
	print("[UNB] level=", level_path, " direct_meshes=", rows.size())
	for r in rows:
		print("[UNB] ", r)
	get_tree().quit()
