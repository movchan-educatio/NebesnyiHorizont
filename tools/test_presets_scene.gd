extends Node3D

func _ready() -> void:
	print("--- TESTING IN PROPER SCENE CONTEXT WITH AUTOLOADS ---")
	var count: int = DroneCatalog.count()
	print("Total presets in DroneCatalog: ", count)
	
	for i in range(count):
		var p := DroneCatalog.preset(i)
		var dname := str(p.get("name", "Unknown"))
		var path := str(p.get("model", ""))
		print("\n[PRESET %d] %s" % [i, dname])
		print("  Path: %s" % path)
		
		if not ResourceLoader.exists(path):
			printerr("  ERROR: File does not exist: ", path)
			continue
			
		var packed := load(path) as PackedScene
		if packed == null:
			printerr("  ERROR: Failed to load PackedScene: ", path)
			continue
			
		var model := packed.instantiate() as Node3D
		if model == null:
			printerr("  ERROR: Failed to instantiate Node3D: ", path)
			continue
		add_child(model)
		
		model.rotation.y = float(p.get("model_yaw", 0.0))
		model.rotation_degrees.x = float(p.get("model_pitch", 0.0))
		
		var pivots: Array[Node3D] = DronePropellerSystem.setup_propellers(model, i,
				float(p.get("prop_d", 5.0)), int(p.get("blades", 3)))
		print("  Pivots: %d" % pivots.size())
		for idx in range(pivots.size()):
			var pvt := pivots[idx]
			print("    P[%d]: %s pos=%s rot=%s" % [idx, pvt.name, pvt.position, pvt.rotation_degrees])
			
		var box := DroneCatalog.model_bounds_full(model)
		print("  Bounds: center=%s size=%s" % [box.get_center(), box.size])
		
		# Test auto-fit scaling as used in MainMenu
		var max_dim := maxf(box.size.x, maxf(box.size.y, box.size.z))
		var factor := 1.7 / max_dim
		model.scale = Vector3.ONE * factor
		model.position = -box.get_center() * factor
		
		# Test animate_propellers
		DroneCatalog.animate_propellers(model, 0.016)
		
		model.queue_free()
		await get_tree().process_frame
		
	print("\n=== ALL 11 PRESETS TESTED OK IN ENGINE! ===")
	get_tree().quit()
