extends Node


func _ready() -> void:
	for scene_path in ["res://sceneries/CityLevel.tscn", "res://sceneries/CourseLevel.tscn"]:
		var packed := load(scene_path) as PackedScene
		var level := packed.instantiate()
		add_child(level)
		await get_tree().create_timer(4.0).timeout
		var found: Array = []
		for node in level.find_children("*", "Node3D", true, false):
			var n := String(node.name).to_lower()
			if n.contains("village_house") or n.contains("farm_complex"):
				found.append(node.name)
		print("[HANDCRAFTED] ", scene_path.get_file(), " nodes=", found)
		level.queue_free()
		await get_tree().process_frame
	get_tree().quit()
