extends SceneTree

func _init():
	var glb = load("res://Assets/Drones/ua_norm/falcon_x.glb")
	var inst = glb.instantiate()
	for name in ["motor_FL", "propeller_FL", "motor_BL", "propeller_BL"]:
		var node = inst.find_child(name, true, false)
		if node is MeshInstance3D and node.mesh != null:
			var aabb = node.mesh.get_aabb()
			print(name, ": node.pos=", node.position, " mesh.aabb=", aabb)
	quit()
