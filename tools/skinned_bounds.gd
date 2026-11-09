## QA: compute the true skinned bounds of a GLB (MeshInstance AABBs ignore skinning).
## Run: godot --headless --path <proj> -s res://tools/skinned_bounds.gd
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
	_report(model, "rest")
	var anim := _find_anim(model)
	if anim != null and anim.get_animation_list().has("Walk"):
		anim.play("Walk")
	for i in range(10):
		await process_frame
	_report(model, "walk")
	quit()


func _report(model: Node3D, tag: String) -> void:
	var lo := Vector3(1e18, 1e18, 1e18)
	var hi := Vector3(-1e18, -1e18, -1e18)
	var meshes: Array[MeshInstance3D] = []
	_collect(model, meshes)
	var sampled := 0
	for mi in meshes:
		var skin := mi.skin
		var skel := mi.get_node_or_null(mi.skeleton) as Skeleton3D
		var mesh := mi.mesh
		if mesh == null:
			continue
		if skin == null or skel == null:
			var b: AABB = mi.global_transform * mi.get_aabb()
			_merge(b, lo, hi)
			continue
		for s in range(mesh.get_surface_count()):
			var arrays := mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			if verts.is_empty() or bones.is_empty():
				continue
			var stride := maxi(1, verts.size() / 200)
			for i in range(0, verts.size(), stride):
				var v := verts[i]
				var p := Vector3.ZERO
				var idx := i * 4
				var total := 0.0
				for k in range(4):
					var w := weights[idx + k]
					if w <= 0.0:
						continue
					var bi := bones[idx + k]
					var bone_idx := skin.get_bind_bone(bi)
					var bind := skin.get_bind_pose(bi)
					var pose := skel.get_bone_global_pose(bone_idx)
					p += (pose * bind * v) * w
					total += w
				if total <= 0.0:
					p = v
				p = mi.global_transform * p
				lo.x = minf(lo.x, p.x); lo.y = minf(lo.y, p.y); lo.z = minf(lo.z, p.z)
				hi.x = maxf(hi.x, p.x); hi.y = maxf(hi.y, p.y); hi.z = maxf(hi.z, p.z)
				sampled += 1
	print("[SKINNED] ", tag, " sampled=", sampled, " lo=", lo, " hi=", hi, " size=", hi - lo)


func _merge(b: AABB, lo: Vector3, hi: Vector3) -> void:
	lo.x = minf(lo.x, b.position.x); lo.y = minf(lo.y, b.position.y); lo.z = minf(lo.z, b.position.z)
	hi.x = maxf(hi.x, b.position.x + b.size.x)
	hi.y = maxf(hi.y, b.position.y + b.size.y)
	hi.z = maxf(hi.z, b.position.z + b.size.z)


func _collect(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect(child, out)


func _find_anim(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_anim(child)
		if found != null:
			return found
	return null
