## QA: inspect skinned model bones after animation.
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
	var force_scale := float(OS.get_environment("MODEL_FORCE_SCALE"))
	if force_scale > 0.0:
		model.scale = Vector3.ONE * force_scale
		model.position = Vector3(
				float(OS.get_environment("MODEL_OFFSET_X")),
				float(OS.get_environment("MODEL_OFFSET_Y")),
				float(OS.get_environment("MODEL_OFFSET_Z")))
	var anim_name := OS.get_environment("MODEL_ANIM")
	if not anim_name.is_empty():
		var ap := _find_anim(model)
		if ap != null and ap.get_animation_list().has(anim_name):
			ap.play(anim_name)
			ap.seek(0.35, true)
	for i in range(3):
		await process_frame
	var sk := _find_skel(model)
	if sk == null:
		print("[SKEL] none")
		quit(0)
		return
	print("[SKEL] bones=", sk.get_bone_count(), " skel_transform=", sk.global_transform)
	for i in range(mini(sk.get_bone_count(), 12)):
		print("  bone ", i, " ", sk.get_bone_name(i), " global=", sk.global_transform * sk.get_bone_global_pose(i).origin)
	quit(0)

func _find_anim(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for c in node.get_children():
		var found := _find_anim(c)
		if found != null:
			return found
	return null

func _find_skel(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for c in node.get_children():
		var found := _find_skel(c)
		if found != null:
			return found
	return null
