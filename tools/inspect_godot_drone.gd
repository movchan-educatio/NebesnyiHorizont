@tool
extends SceneTree

func _init():
	var drones = [
		"pisun_vtol.glb",
		"peleng.glb",
		"falcon_x.glb",
		"quad5_custom.glb",
		"grim7.glb",
		"grim7m.glb",
		"strila8.glb",
		"holka.glb",
		"pinapipe.glb",
		"avata2.glb"
	]
	for d in drones:
		var path = "res://Assets/Drones/ua_norm/" + d
		var scene = load(path)
		if scene:
			var inst = scene.instantiate()
			print("=== GODOT INSPECTION: ", d, " ===")
			for child in inst.get_children():
				if child.name.begins_with("propeller"):
					print("  [PROP] ", child.name, " pos: ", child.position, " rot_deg: ", child.rotation_degrees)
				elif child.get_child_count() > 0:
					print("  [PARENT] ", child.name, " rot_deg: ", child.rotation_degrees)
					for sub in child.get_children():
						if sub.name.begins_with("propeller"):
							print("    [SUB-PROP] ", sub.name, " pos: ", sub.position, " rot_deg: ", sub.rotation_degrees)
	quit()
