extends SceneTree

func _init():
	var glb = load("res://Assets/Drones/ua_norm/avata2.glb")
	var inst = glb.instantiate()
	var DronePropellerSystem = load("res://scripts/util/DronePropellerSystem.gd")
	var pivs = DronePropellerSystem.setup_propellers(inst, 2, 3.0)
	print("Testing Avata 2 rotation over 5 frames:")
	for f in range(5):
		DronePropellerSystem.animate_propellers(inst, 1.0 / 60.0)
		print("Frame ", f, ": motor_FL rot_deg=", pivs[0].rotation_degrees, " prop_FL rot_deg=", pivs[0].get_child(0).rotation_degrees)
	quit()
