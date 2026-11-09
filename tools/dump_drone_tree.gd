@tool
extends SceneTree

func _init() -> void:
	var drones: Array[String] = ["pisun_vtol.glb", "peleng.glb", "falcon_x.glb", "avata2.glb"]
	for d: String in drones:
		var path: String = "res://Assets/Drones/ua_norm/" + d
		var res: PackedScene = load(path) as PackedScene
		if res == null:
			print("FAILED TO LOAD ", path)
			continue
		var inst: Node3D = res.instantiate() as Node3D
		print("========================================")
		print("DRONE: ", d)
		print("========================================")
		_dump_nodes(inst, 0)
		inst.free()
	quit()

func _dump_nodes(node: Node, depth: int) -> void:
	var prefix := "  ".repeat(depth)
	var info := ""
	if node is Node3D:
		var n3d := node as Node3D
		info = " pos=" + str(n3d.position) + " rot=" + str(n3d.rotation_degrees) + " scale=" + str(n3d.scale)
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var aabb: AABB = mi.get_aabb()
		info += " aabb_center=" + str(aabb.get_center()) + " aabb_size=" + str(aabb.size)
	print(prefix + "- " + node.name + " (" + node.get_class() + ")" + info)
	for c in node.get_children():
		_dump_nodes(c, depth + 1)
