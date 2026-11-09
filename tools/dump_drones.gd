extends SceneTree

func _initialize() -> void:
	for p in ["res://Assets/Drones/pisun_vtol.glb", "res://Assets/Drones/peleng.glb", "res://Assets/Drones/pinapipe.glb"]:
		if ResourceLoader.exists(p):
			print("=== ", p, " ===")
			var node = load(p).instantiate()
			_print_children(node, "")
	quit()

func _print_children(n: Node, ind: String) -> void:
	print(ind, n.name, " (", n.get_class(), ")")
	for c in n.get_children():
		_print_children(c, ind + "  ")
