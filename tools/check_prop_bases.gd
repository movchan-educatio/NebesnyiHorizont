extends SceneTree

func _init() -> void:
	var list: Array[String] = ["avata2.glb", "pisun_vtol.glb", "peleng.glb", "falcon_x.glb", "quad5_custom.glb"]
	for glb_name: String in list:
		var path: String = "res://Assets/Drones/ua_norm/" + glb_name
		var scn: PackedScene = load(path) as PackedScene
		if scn == null:
			continue
		var m: Node3D = scn.instantiate() as Node3D
		print("\n=== GLB: ", glb_name, " ===")
		var prop_names: Array[String] = ["propeller_FL", "propeller_FR", "propeller_BL", "propeller_BR"]
		for p_name: String in prop_names:
			var node: Node3D = m.find_child(p_name, true, false) as Node3D
			if node != null:
				print("  ", p_name, " pos=", node.position, " rot_deg=", node.rotation_degrees, " basis.y=", node.basis.y)
			else:
				print("  ", p_name, " NOT FOUND!")
	quit(0)
