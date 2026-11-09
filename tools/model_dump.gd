## QA: dump every mesh instance in a GLB and its AABB.
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
	print("[DUMP] ", path)
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var gb: AABB = mi.global_transform * mi.get_aabb()
		print("  mesh=", mi.name, " visible=", mi.visible, " skel=", mi.skeleton,
				" pos=", mi.global_position, " aabb=", gb.position, " size=", gb.size,
				" surfaces=", mi.mesh.get_surface_count())
	for n in model.find_children("*", "Skeleton3D", true, false):
		var sk := n as Skeleton3D
		print("  skeleton=", sk.get_path(), " bones=", sk.get_bone_count(), " xf=", sk.global_transform)
	for n in model.find_children("*", "AnimationPlayer", true, false):
		var ap := n as AnimationPlayer
		print("  animplayer=", ap.get_path(), " list=", ap.get_animation_list())
	quit(0)
