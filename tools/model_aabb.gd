extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _collect(node: Node, xform: Transform3D, acc: Array) -> void:
	var t := xform
	if node is Node3D:
		t = xform * (node as Node3D).transform
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var aabb: AABB = t * mi.mesh.get_aabb()
			acc[0] = aabb if acc[0] == null else (acc[0] as AABB).merge(aabb)
	for child in node.get_children():
		_collect(child, t, acc)


func _run() -> void:
	var paths := {
		"TANK": "res://Assets/vehicles/low_poly_t-72_tank_-_game_ready.glb",
		"BMP": "res://Assets/vehicles/low-poly_bmp-2m.glb",
		"APC": "res://Assets/vehicles/btr-90_ussr.glb",
		"HELI": "res://Assets/vehicles/apache_hecu_half-life.glb",
	}
	for name in paths:
		var packed: PackedScene = load(paths[name])
		var inst: Node3D = packed.instantiate()
		root.add_child(inst)
		await process_frame
		var acc := [null]
		_collect(inst, Transform3D.IDENTITY, acc)
		print("[AABB] ", name, " size=", (acc[0] as AABB).size, " pos=", (acc[0] as AABB).position)
		inst.queue_free()
		await process_frame
	quit()
