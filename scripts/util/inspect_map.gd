extends SceneTree

func _init() -> void:
	var path := "res://Assets/maps/map_combat.glb"
	var ps := load(path) as PackedScene
	if ps:
		var n := ps.instantiate()
		_dump(n, "  ")
		n.free()
	quit()

func _dump(node: Node, indent: String) -> void:
	var info := node.name + " [" + node.get_class() + "]"
	if node is CollisionShape3D:
		info += " shape=" + str((node as CollisionShape3D).shape)
	print(indent, info)
	for c in node.get_children():
		_dump(c, indent + "  ")
