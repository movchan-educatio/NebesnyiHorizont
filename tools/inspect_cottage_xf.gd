extends SceneTree

func _init() -> void:
	var packed := load("res://Assets/frontline/village_cottage.glb") as PackedScene
	var lib := packed.instantiate()
	for name in ["barn_a", "cottage_a", "cottage_b"]:
		var mi := lib.find_child(name, true, false) as Node3D
		if mi != null:
			print(name, " transform=", mi.transform)
	lib.free()
	quit()
