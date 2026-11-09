extends SceneTree

func _init():
	var paths = [
		"res://Assets/Drones/ua_norm/holka.glb",
		"res://Assets/Drones/ua_norm/pinapipe.glb",
		"res://Assets/Drones/ua_norm/avata2.glb",
		"res://Assets/Drones/ua_norm/pisun_vtol.glb",
		"res://Assets/Drones/ua_norm/peleng.glb",
		"res://Assets/Drones/ua_norm/grim7.glb",
		"res://Assets/Drones/ua_norm/grim7m.glb",
		"res://Assets/Drones/ua_norm/strila8.glb",
		"res://Assets/Drones/ua_norm/falcon_x.glb",
		"res://Assets/Drones/ua_norm/quad5_custom.glb"
	]
	for p in paths:
		print("------------------------------------------")
		print("CHECKING SCENE: ", p)
		var scn = load(p) as PackedScene
		if scn == null:
			print("  FAIL TO LOAD")
			continue
		var root_node = scn.instantiate()
		_dump_tree(root_node, 0)
		root_node.queue_free()
	quit()

func _dump_tree(n: Node, depth: int):
	var indent = ""
	for i in range(depth):
		indent += "  "
	var extra = ""
	if n is Node3D:
		extra = " pos=%s rot=%s scale=%s" % [n.position, n.rotation_degrees, n.scale]
	if "prop" in n.name.to_lower() or "vint" in n.name.to_lower():
		print(indent, ">>> [PROP MATCH] '", n.name, "' (", n.get_class(), ")", extra)
	else:
		if depth <= 2:
			print(indent, "'", n.name, "' (", n.get_class(), ")", extra)
	for c in n.get_children():
		_dump_tree(c, depth + 1)
