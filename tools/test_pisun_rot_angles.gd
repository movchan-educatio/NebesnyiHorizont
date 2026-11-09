extends SceneTree

func _init():
	var glb = load("res://Assets/Drones/ua_norm/pisun_vtol.glb")
	var inst = glb.instantiate()
	var DronePropellerSystem = load("res://scripts/util/DronePropellerSystem.gd")
	var pivs = DronePropellerSystem.setup_propellers(inst, 3, 7.0, 2)
	print("Checking rotation over 10 frames:")
	for f in range(10):
		DronePropellerSystem.animate_propellers(inst, 1.0 / 60.0)
		print("Frame ", f, ": motor_FL rot=", pivs[0].rotation_degrees)
	quit()
