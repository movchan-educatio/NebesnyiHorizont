extends SceneTree

func _init():
	var DronePropellerSystem = load("res://scripts/util/DronePropellerSystem.gd")
	var models = [
		["holka.glb", 0],
		["pinapipe.glb", 1],
		["avata2.glb", 2],
		["pisun_vtol.glb", 3],
		["peleng.glb", 4],
		["grim7.glb", 5],
		["grim7m.glb", 6],
		["strila8.glb", 7],
		["falcon_x.glb", 8],
		["quad5_custom.glb", 9],
	]
	for item in models:
		var glb_path = "res://Assets/Drones/ua_norm/" + item[0]
		var i = item[1]
		var glb = load(glb_path)
		if not glb:
			print("PRESET ", i, " FAIL TO LOAD ", glb_path)
			continue
		var inst = glb.instantiate()
		var pivs = DronePropellerSystem.setup_propellers(inst, i, 5.0)
		print("PRESET ", i, " (", item[0], "): pivots count = ", pivs.size())
		for idx in range(pivs.size()):
			var piv = pivs[idx]
			print("   [", idx, "] ", piv.name, " parent=", piv.get_parent().name if piv.get_parent() else "None", " pos=", piv.position)
	quit()
