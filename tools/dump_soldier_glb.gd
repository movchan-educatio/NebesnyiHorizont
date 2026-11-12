extends SceneTree

## Debug: dump mesh instance names, primitive counts and material names of the
## merged soldier GLB so the rifle-prop logic can be verified against reality.
func _init() -> void:
	var packed := load("res://Assets/combat/soldier_detailed_merged.glb") as PackedScene
	if packed == null:
		print("RIFLE_DUMP: model failed to load")
		quit(1)
		return
	var model := packed.instantiate() as Node3D
	if model == null:
		print("RIFLE_DUMP: instantiate failed")
		quit(1)
		return
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var surfaces := m.mesh.get_surface_count() if m.mesh != null else 0
		var mats: Array = []
		for s in range(surfaces):
			var mat := m.mesh.surface_get_material(s)
			mats.append("<none>" if mat == null else String(mat.resource_name))
		var box: AABB = mi.get_aabb()
		print("RIFLE_DUMP mesh=", m.name, " prims=", m.mesh.get_surface_count(),
				" aabb=%.2f x %.2f x %.2f" % [box.size.x, box.size.y, box.size.z],
				" mats=", str(mats))
	model.free()
	quit(0)
