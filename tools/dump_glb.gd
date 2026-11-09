## dump_glb.gd — headless GLB census, no project changes.
## Run: godot --headless --path <proj> --script res://tools/dump_glb.gd -- <res.glb>
extends SceneTree


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: --script dump_glb.gd -- <res://path.glb>")
		quit(1)
		return
	var ps := load(args[0]) as PackedScene
	if ps == null:
		print("not a PackedScene: ", args[0])
		quit(1)
		return
	var inst := ps.instantiate()
	root.add_child(inst)
	var boxes: Array = []
	_walk(inst, boxes)
	print("MESH INSTANCES: ", boxes.size())
	var i := 0
	for b in boxes:
		if i < 15:
			print("  ", b)
		i += 1
	print("GLOBAL TRANSFORMS (first 12 MeshInstance3D):")
	_walk2(inst, [0])
	quit()


func _walk2(node: Node, counter: Array) -> void:
	if counter[0] >= 12:
		return
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		print("  ", mi.name, " origin=", mi.global_transform.origin,
			" basis=", mi.global_transform.basis.get_scale())
		counter[0] += 1
	for c in node.get_children():
		_walk2(c, counter)


func _walk(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var aabb := mi.mesh.get_aabb()
			var mats := []
			for s in range(mi.mesh.get_surface_count()):
				mats.append(mi.mesh.surface_get_material(s))
			out.append("%s mesh_aabb=%s surfaces=%d mats=%s visible=%s layer=%d" % [
				mi.name, str(aabb), mi.mesh.get_surface_count(), str(mats),
				str(mi.visible), mi.layers])
	for c in node.get_children():
		_walk(c, out)
