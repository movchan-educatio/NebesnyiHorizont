## QA: inspect imported skinned meshes and skeleton binding.
extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var path := OS.get_environment("MODEL_PATH")
	var holder := Node3D.new()
	root.add_child(holder)
	current_scene = holder
	var model := (load(path) as PackedScene).instantiate() as Node3D
	holder.add_child(model)
	await process_frame
	var skel := _find_skel(model)
	print("[BIND] model=", path, " skeleton=", skel.get_path() if skel else "none")
	if skel != null:
		print("[BIND] skel parent=", skel.get_parent().get_path(), " xf=", skel.global_transform)
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null:
			continue
		print("[BIND] mesh=", mi.get_path(), " skin=", mi.skin, " skeleton_path=", mi.skeleton,
				" has_skel=", mi.skeleton != NodePath())
		if mi.skin != null and skel != null:
			mi.skeleton = mi.get_path_to(skel)
			print("   -> rebound to ", mi.skeleton)
	await process_frame
	await process_frame
	# Check whether the skeleton actually deforms the mesh by moving one bone.
	if skel != null and skel.get_bone_count() > 4:
		var before := skel.get_bone_global_pose(4).origin
		skel.set_bone_pose_position(4, before + Vector3(0, 0, 0.5))
		await process_frame
		print("[BIND] moved bone 4 from ", before, " to ", skel.get_bone_global_pose(4).origin)
	quit(0)

func _find_skel(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for c in node.get_children():
		var found := _find_skel(c)
		if found != null:
			return found
	return null
