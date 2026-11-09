extends SceneTree

func _init():
	var glb = load("res://Assets/Drones/ua_norm/falcon_x.glb")
	if not glb:
		print("ERROR LOADING FALCON_X.GLB")
		quit()
	var inst = glb.instantiate()
	print("--- FALCON_X GODOT NODES ---")
	_print_tree(inst, 0)
	quit()

func _print_tree(n: Node, depth: int):
	var indent = ""
	for i in range(depth):
		indent += "  "
	var pos_str = ""
	if n is Node3D:
		pos_str = " pos=" + str(n.position) + " rot=" + str(n.rotation_degrees)
	print(indent + n.name + " (" + n.get_class() + ")" + pos_str)
	for c in n.get_children():
		_print_tree(c, depth + 1)
