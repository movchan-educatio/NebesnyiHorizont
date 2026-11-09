extends Node3D

## QA-only draw-call breakdown: builds one map and counts the scene nodes that
## become draw calls, grouped by material, so the performance work targets the
## actual hot spots instead of guessing.

const TERRAIN := preload("res://scripts/util/frontline_terrain.gd")
const MAPS := ["village", "industrial", "steppe", "wetlands"]


func _ready() -> void:
	await get_tree().process_frame
	for map_name in MAPS:
		var root := Node3D.new()
		add_child(root)
		TERRAIN.build_terrain(root, map_name, 0.0)
		await get_tree().process_frame
		var counts := {"mesh": 0, "multimesh": 0, "surfaces": 0, "mm_surfaces": 0}
		var by_mat := {}
		_count(root, counts, by_mat)
		print("[DRAWS] %s mesh=%d surfaces=%d multimesh=%d mm_surfaces=%d materials=%d" % [
			map_name, counts["mesh"], counts["surfaces"], counts["multimesh"],
			counts["mm_surfaces"], by_mat.size()])
		var top: Array = []
		for mat_name in by_mat:
			top.append([by_mat[mat_name], mat_name])
		top.sort_custom(func(a, b): return a[0] > b[0])
		for i in range(mini(top.size(), 8)):
			print("    ", top[i][0], " x ", top[i][1])
		root.queue_free()
		await get_tree().process_frame
	get_tree().quit()


func _count(node: Node, counts: Dictionary, by_mat: Dictionary) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		counts["mesh"] += 1
		if mi.mesh != null:
			counts["surfaces"] += mi.mesh.get_surface_count()
		var key := "no-material"
		if mi.material_override != null:
			key = _mat_name(mi.material_override)
		elif mi.mesh != null and mi.mesh.get_surface_count() > 0:
			var m := mi.mesh.surface_get_material(0)
			if m != null:
				key = _mat_name(m)
		by_mat[key] = int(by_mat.get(key, 0)) + 1
	elif node is MultiMeshInstance3D:
		var mmi := node as MultiMeshInstance3D
		counts["multimesh"] += 1
		if mmi.multimesh != null and mmi.multimesh.mesh != null:
			counts["mm_surfaces"] += mmi.multimesh.mesh.get_surface_count()
	for child in node.get_children():
		_count(child, counts, by_mat)


func _mat_name(mat: Material) -> String:
	if mat is ShaderMaterial:
		var sm := mat as ShaderMaterial
		return "shader:" + (sm.shader.resource_path.get_file() if sm.shader != null else "?")
	if mat is StandardMaterial3D:
		var s := mat as StandardMaterial3D
		return "std:" + s.albedo_color.to_html(false) + ":" + str(s.albedo_texture.resource_path.get_file() if s.albedo_texture != null else "-")
	return mat.get_class()
