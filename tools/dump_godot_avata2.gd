extends SceneTree

func _init() -> void:
	var path := "res://Assets/Drones/ua_norm/avata2.glb"
	var scn := load(path) as PackedScene
	if scn == null:
		print("Failed to load ", path)
		quit(1)
		return
	var inst := scn.instantiate()
	_print_tree(inst, 0)
	quit(0)

func _print_tree(node: Node, depth: int) -> void:
	var indent := "  ".repeat(depth)
	print("%s%s (%s)" % [indent, node.name, node.get_class()])
	for child in node.get_children():
		_print_tree(child, depth + 1)
