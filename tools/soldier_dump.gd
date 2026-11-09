## QA: dump skeleton bones, meshes and material names for the detailed soldier.
extends Node3D

func _ready() -> void:
	await get_tree().process_frame
	var model := (load("res://Assets/combat/soldier_detailed.glb") as PackedScene).instantiate() as Node3D
	add_child(model)
	model.rotation_degrees.x = 90.0
	var skel := _find_skel(model)
	if skel != null:
		print("[SOLDIER] bones=", skel.get_bone_count())
		for i in range(skel.get_bone_count()):
			var p := skel.get_bone_global_pose(i).origin
			print("  ", i, " ", skel.get_bone_name(i), " pos=", p)
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null:
			continue
		var mats: Array[String] = []
		if mi.mesh != null:
			for s in range(mi.mesh.get_surface_count()):
				var m := mi.mesh.surface_get_material(s)
				if m != null:
					mats.append(String(m.resource_name))
		print("[SOLDIER] mesh=", mi.name, " aabb=", mi.get_aabb(), " mats=", mats)
	get_tree().quit(0)

func _find_skel(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for c in node.get_children():
		var f := _find_skel(c)
		if f != null:
			return f
	return null
