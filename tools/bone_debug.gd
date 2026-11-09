extends Node3D

func _ready() -> void:
	var soldier := EnemyRifleman.new()
	add_child(soldier)
	await get_tree().process_frame
	var rig = soldier.get("_detailed_rig")
	if rig == null:
		get_tree().quit(0)
		return
	var skel: Skeleton3D = rig.get("skeleton")
	if skel == null:
		get_tree().quit(0)
		return
	for i in range(skel.get_bone_count()):
		var bn := skel.get_bone_name(i)
		if bn.contains("UpperArm") or bn.contains("Shoulder") or bn.contains("Clavicle"):
			var gp := skel.global_transform * skel.get_bone_global_pose(i) * Vector3.ZERO
			var tail := skel.global_transform * skel.get_bone_global_pose(i) * Vector3(0, 0.25, 0)
			print("[BONE] ", bn, " idx=", i, " global_head=", gp, " global_tail=", tail)
	get_tree().quit(0)
