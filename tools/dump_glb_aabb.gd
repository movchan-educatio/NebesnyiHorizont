## dump_glb_aabb.gd — headless GLB census with mesh AABBs.
## Run: godot --headless --path <proj> --script res://tools/dump_glb_aabb.gd -- <res.glb>
extends SceneTree


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: --script dump_glb_aabb.gd -- <res://path.glb>")
		quit(1)
		return
	var ps := load(args[0]) as PackedScene
	if ps == null:
		print("not a PackedScene: ", args[0])
		quit(1)
		return
	var inst := ps.instantiate()
	root.add_child(inst)
	await process_frame
	var rows: Array = []
	_walk(inst, rows)
	rows.sort_custom(func(a, b): return a[2] > b[2])
	for r in rows:
		print("MESH ", r[0], " center=", r[1], " size=", r[3], " top=", r[2])
	print("TOTAL ", rows.size())
	quit()


func _walk(node: Node, rows: Array) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var xf := mi.global_transform
		var aabb := xf * mi.get_aabb()
		rows.append([mi.name, aabb.get_center(), aabb.position.y + aabb.size.y, aabb.size])
	for child in node.get_children():
		_walk(child, rows)
