extends Node

func _ready() -> void:
	for idx in [13, 14, 15]:
		var p: Dictionary = DroneCatalog.preset(idx)
		var path := str(p.get("model", ""))
		var packed := load(path) as PackedScene
		if packed == null:
			print("[MODELDUMP] ", idx, " missing ", path)
			continue
		var model := packed.instantiate() as Node3D
		add_child(model)
		await get_tree().process_frame
		print("[MODELDUMP] preset=", idx, " name=", p.get("name_en", p.get("name")),
				" combat=", p.get("combat"), " fixed=", p.get("fixed_wing", false),
				" payload=", p.get("payload"))
		for n in model.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			var box := mi.get_aabb()
			print("   ", mi.name, " pos=", box.position, " size=", box.size)
		model.queue_free()
		await get_tree().process_frame
	get_tree().quit(0)
