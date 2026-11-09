extends SceneTree

func _init():
	var glb = load("res://Assets/Drones/ua_norm/pisun_vtol.glb")
	var inst = glb.instantiate()
	var DronePropellerSystem = load("res://scripts/util/DronePropellerSystem.gd")
	var pivs = DronePropellerSystem.setup_propellers(inst, 3, 7.0, 2)
	print("PISUN pivots count = ", pivs.size())
	for p in pivs:
		print("  pivot: ", p.name, " pos=", p.position, " rot=", p.rotation_degrees)
		for c in p.get_children():
			print("    child: ", c.name, " pos=", c.position, " rot=", c.rotation_degrees)
	quit()
