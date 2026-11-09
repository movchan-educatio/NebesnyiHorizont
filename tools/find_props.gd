extends SceneTree

func _init() -> void:
	var models = [
		"holka.glb", "pinapipe.glb", "avata2.glb", "pisun_vtol.glb",
		"peleng.glb", "grim7.glb", "grim7m.glb", "strila8.glb"
	]
	for m in models:
		print("========================================")
		print("MODEL: ", m)
		var scn = load("res://Assets/Drones/ua_norm/" + m)
		if scn:
			var inst: Node3D = scn.instantiate()
			_check_props(inst)
	quit(0)

func _check_props(node: Node) -> void:
	for ch in node.get_children():
		var n_lower: String = ch.name.to_lower()
		if ch is MeshInstance3D:
			var mi: MeshInstance3D = ch as MeshInstance3D
			var aabb: AABB = mi.get_aabb()
			# Check if name suggests propeller or rotor, or if flat disc shape
			var is_flat: bool = aabb.size.y < 0.03 and (aabb.size.x > 0.05 or aabb.size.z > 0.05)
			print("  Node '%s': pos=%s aabb_pos=%s aabb_sz=%s flat=%s" % [
				ch.name, str(mi.position), str(aabb.position), str(aabb.size), is_flat
			])
		_check_props(ch)
