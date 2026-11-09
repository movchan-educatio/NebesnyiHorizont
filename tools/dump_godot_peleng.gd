@tool
extends SceneTree

func _init() -> void:
	var glb_path := "res://Assets/Drones/ua_norm/peleng.glb"
	var scene: PackedScene = load(glb_path)
	if scene == null:
		print("Failed to load peleng.glb")
		quit(1)
		return
	var root: Node3D = scene.instantiate()
	print("--- GODOT PELENG HIERARCHY ---")
	_print_tree(root, 0)
	quit(0)

func _print_tree(node: Node, depth: int) -> void:
	var prefix := "  ".repeat(depth)
	var info := ""
	if node is Node3D:
		var n3d := node as Node3D
		info = " pos=%s rot_deg=%s scale=%s" % [n3d.position, n3d.rotation_degrees, n3d.scale]
	print("%s- %s (%s)%s" % [prefix, node.name, node.get_class(), info])
	for child in node.get_children():
		_print_tree(child, depth + 1)
