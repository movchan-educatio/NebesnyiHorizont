extends Node


func _ready() -> void:
	var packed := load("res://sceneries/CityLevel.tscn") as PackedScene
	var level := packed.instantiate()
	add_child(level)
	await get_tree().create_timer(5.0).timeout
	var city := level.get_node_or_null("City")
	if city == null:
		print("[CITY] no City node")
		get_tree().quit()
		return
	var meshes := 0
	var surfaces := 0
	var skinned := 0
	var transparent := 0
	var unique_mats := {}
	var big := 0
	for node in city.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		meshes += 1
		surfaces += mi.mesh.get_surface_count()
		if not mi.skeleton.is_empty():
			skinned += 1
		var box: AABB = mi.global_transform * mi.get_aabb()
		if maxf(box.size.x, maxf(box.size.y, box.size.z)) > 80.0:
			big += 1
		for s in range(mi.mesh.get_surface_count()):
			var mat: Material = mi.get_surface_override_material(s)
			if mat == null:
				mat = mi.mesh.surface_get_material(s)
			var sm := mat as StandardMaterial3D
			if sm == null:
				unique_mats["non_standard:" + str(mat)] = true
				continue
			if sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				transparent += 1
			unique_mats[sm.albedo_color.to_html() + "|" + str(sm.albedo_texture)] = true
	print("[CITY] meshes=%d surfaces=%d skinned=%d transparent=%d big=%d unique_mats=%d" % [
			meshes, surfaces, skinned, transparent, big, unique_mats.size()])
	get_tree().quit()
