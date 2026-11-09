@tool
extends SceneTree

const DroneCatalog = preload("res://autoloads/DroneCatalog.gd")
const DronePropellerSystem = preload("res://scripts/util/DronePropellerSystem.gd")

func _init() -> void:
	var catalog = DroneCatalog.new()
	print("Testing all drone presets in DroneCatalog, MainMenu, and DroneSelectScreen...")
	var count: int = catalog.count()
	print("Total presets in DroneCatalog: ", count)
	
	for i in range(count):
		var p := catalog.preset(i)
		var name := str(p.get("name", "Unknown"))
		var path := str(p.get("model", ""))
		print("\n--- Preset %d: %s ---" % [i, name])
		print("Model path: ", path)
		
		if not ResourceLoader.exists(path):
			printerr("ERROR: File does not exist: ", path)
			continue
			
		var packed := load(path) as PackedScene
		if packed == null:
			printerr("ERROR: Failed to load PackedScene: ", path)
			continue
			
		var model := packed.instantiate() as Node3D
		if model == null:
			printerr("ERROR: Failed to instantiate Node3D: ", path)
			continue
			
		# Check propellers
		var pivots: Array[Node3D] = DronePropellerSystem.setup_propellers(model, i, float(p.get("prop_d", 5.0)))
		print("Propeller pivots found: ", pivots.size())
		for idx in range(pivots.size()):
			var pvt := pivots[idx]
			print("  Pivot[%d]: %s at %s" % [idx, pvt.name, pvt.position])
			
		# Check bounds
		var box := catalog.model_bounds_full(model)
		print("Bounds: center=%s size=%s" % [box.get_center(), box.size])
		
		# Test animation step
		DronePropellerSystem.animate_propellers(model, 0.016)
		print("Animate propellers: OK")
		
		model.queue_free()
		
	print("\nALL PRESETS TESTED SUCCESSFULLY!")
	quit()
