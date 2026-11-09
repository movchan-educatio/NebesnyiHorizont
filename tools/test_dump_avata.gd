extends SceneTree

func _init():
	var glb = load("res://Assets/Drones/ua_norm/avata2.glb")
	if glb:
		var inst = glb.instantiate()
		print("--- Nodes in avata2.glb ---")
		_dump_nodes(inst, 0)
	quit()

func _dump_nodes(node: Node, depth: int):
	var pad = ""
	for i in range(depth): pad += "  "
	print(pad, node.name, " (", node.get_class(), ") pos=", (node as Node3D).position if node is Node3D else "")
	for c in node.get_children():
		_dump_nodes(c, depth + 1)
