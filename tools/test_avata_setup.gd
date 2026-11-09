extends SceneTree

func _init():
	var glb = load("res://Assets/Drones/ua_norm/avata2.glb")
	var inst = glb.instantiate()
	var DronePropellerSystem = load("res://scripts/util/DronePropellerSystem.gd")
	var pivs = DronePropellerSystem.setup_propellers(inst, 2, 3.0)
	print("AVATA 2 pivots count = ", pivs.size())
	for p in pivs:
		print("  pivot: ", p.name, " class=", p.get_class(), " pos=", p.position, " rot=", p.rotation_degrees)
		for c in p.get_children():
			print("    child: ", c.name, " class=", c.get_class(), " pos=", c.position)
	quit()
