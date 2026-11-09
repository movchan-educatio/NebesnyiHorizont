extends SceneTree

func _init() -> void:
	var models = [
		"holka.glb", "pinapipe.glb", "avata2.glb", "pisun_vtol.glb",
		"peleng.glb", "grim7.glb", "grim7m.glb", "strila8.glb"
	]
	for m in models:
		print("\n===============================")
		print("MODEL: ", m)
		var scn = load("res://Assets/Drones/ua_norm/" + m)
		if scn:
			var inst: Node = scn.instantiate()
			_print_children(inst, 0)
	quit(0)

func _print_children(node: Node, depth: int) -> void:
	var prefix = "  ".repeat(depth)
	print("%s- %s (%s)" % [prefix, node.name, node.get_class()])
	for ch in node.get_children():
		_print_children(ch, depth + 1)
