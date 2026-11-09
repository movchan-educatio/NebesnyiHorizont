## QA: measure the HECU soldier from its skeleton pose (mesh AABBs lie for skinning).
extends SceneTree

const SOLDIER := "res://Assets/vehicles_anim/hecu_half-life_anim.glb"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	current_scene = holder
	var packed := load(SOLDIER) as PackedScene
	var model := packed.instantiate() as Node3D
	holder.add_child(model)
	await process_frame
	var anim := _find_anim(model)
	if anim != null and anim.get_animation_list().has("Walk"):
		anim.play("Walk")
	for i in range(10):
		await process_frame
	_report(model, "posed")
	quit()


func _report(model: Node3D, tag: String) -> void:
	var skeletons: Array[Skeleton3D] = []
	_find_skel(model, skeletons)
	print("[HECU] ", tag, " skeletons=", skeletons.size())
	for sk in skeletons:
		var lo := Vector3(1e18, 1e18, 1e18)
		var hi := Vector3(-1e18, -1e18, -1e18)
		for i in range(sk.get_bone_count()):
			var p := sk.get_bone_global_pose(i).origin
			lo.x = minf(lo.x, p.x); lo.y = minf(lo.y, p.y); lo.z = minf(lo.z, p.z)
			hi.x = maxf(hi.x, p.x); hi.y = maxf(hi.y, p.y); hi.z = maxf(hi.z, p.z)
		print("[HECU] bones=", sk.get_bone_count(), " skel=", sk.name,
				" local_lo=", lo, " local_hi=", hi, " size=", hi - lo,
				" global_xf=", sk.global_transform)
		var names := ["Bip01 Head_046", "Bip01 Pelvis_02", "Bip01 L Foot_053"]
		for nm in names:
			var idx := sk.find_bone(nm)
			if idx >= 0:
				var gp := sk.global_transform * sk.get_bone_global_pose(idx).origin
				print("[HECU] bone ", nm, " idx=", idx, " global=", gp)


func _find_skel(node: Node, out: Array[Skeleton3D]) -> void:
	if node is Skeleton3D:
		out.append(node as Skeleton3D)
	for child in node.get_children():
		_find_skel(child, out)


func _find_anim(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_anim(child)
		if found != null:
			return found
	return null
