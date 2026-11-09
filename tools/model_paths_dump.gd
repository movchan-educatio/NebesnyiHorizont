extends Node

func _ready() -> void:
	for idx in [5, 6, 11, 12, 13, 14, 15]:
		var p: Dictionary = DroneCatalog.preset(idx)
		var packed := load(str(p.get("model", ""))) as PackedScene
		if packed == null:
			continue
		var model := packed.instantiate() as Node3D
		add_child(model)
		await get_tree().process_frame
		print("[PATHS] preset=", idx, " ", p.get("name_en", p.get("name")))
		for n in model.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			var ln := String(mi.name).to_lower()
			if ln.contains("bomb") or ln.contains("morkva") or ln.contains("warhead") \
					or ln.contains("cam") or ln.contains("propeller") or ln.contains("prop_"):
				print("   ", mi.get_path(), " name=", mi.name)
		model.queue_free()
		await get_tree().process_frame
	get_tree().quit(0)
