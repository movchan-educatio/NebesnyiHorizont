extends Node


func _ready() -> void:
	var packed := load("res://sceneries/IndustrialLevel.tscn") as PackedScene
	var level := packed.instantiate()
	add_child(level)
	await get_tree().create_timer(5.0).timeout
	var ft := level.get_node_or_null("FrontlineTerrain")
	if ft == null:
		print("[LM] no terrain")
		get_tree().quit()
		return
	for node in ft.get_children():
		if not (node is MeshInstance3D):
			continue
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var box: AABB = mi.global_transform * mi.get_aabb()
		var mesh_name := mi.mesh.get_class()
		var surf := mi.mesh.get_surface_count()
		print("[LM] ", mi.name, " pos=", mi.global_position.snapped(Vector3.ONE * 0.1),
				" size=", box.size.snapped(Vector3.ONE * 0.1),
				" mesh=", mesh_name, " surf=", surf,
				" vis=", mi.is_visible_in_tree())
	get_tree().quit()
