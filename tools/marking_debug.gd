extends Node3D

func _ready() -> void:
	var soldier := EnemyRifleman.new()
	add_child(soldier)
	await get_tree().process_frame
	var rig = soldier.get("_detailed_rig")
	if rig == null:
		print("[MARKDBG] no rig")
		get_tree().quit(0)
		return
	print("[MARKDBG] rig scale=", rig.scale, " soldier scale=", soldier.scale)
	for n in rig.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if String(mi.name).contains("RussianMarking"):
			var q := mi.mesh as QuadMesh
			print("[MARKDBG] ", mi.name, " pos=", mi.position, " rot=", mi.rotation_degrees,
					" quad=", q.size if q != null else Vector2.ZERO,
					" global_scale=", mi.global_transform.basis.get_scale(),
					" aabb=", mi.global_transform * mi.get_aabb())
	get_tree().quit(0)
