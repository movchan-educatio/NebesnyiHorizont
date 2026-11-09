@tool
extends SceneTree

const DroneCatalogScript = preload("res://autoloads/DroneCatalog.gd")

func _init() -> void:
	var catalog = DroneCatalogScript.new()
	print("--- TEST PELENG IN GODOT ---")
	var path := "res://Assets/Drones/ua_norm/peleng.glb"
	var scene := load(path) as PackedScene
	var root := Node3D.new()
	var inst := scene.instantiate() as Node3D
	root.add_child(inst)
	
	print("Inst position: ", inst.position, " rot: ", inst.rotation)
	for c in inst.get_children():
		if c is Node3D:
			var n := c as Node3D
			print("Child '", n.name, "' pos: ", n.position, " rot: ", n.rotation_degrees, " scale: ", n.scale)
			if n is MeshInstance3D:
				var mi := n as MeshInstance3D
				print("   aabb: ", mi.get_aabb())

	print("\n--- NOW SIMULATE MAIN MENU SETUP ---")
	inst.rotation.y = 0.0
	inst.rotation_degrees.x = 0.0 # Peleng pitch is 0
	DronePropellerSystem.setup_propellers(inst, 4, 5.1, 2)
	
	var box := catalog.model_bounds_full(inst)
	var max_dim := maxf(box.size.x, maxf(box.size.y, box.size.z))
	var factor := 1.7 / max_dim
	print("Auto-fit factor: ", factor, " box center: ", box.get_center())
	inst.scale = Vector3.ONE * factor
	inst.position = -box.get_center() * factor
	
	print("\n--- AFTER AUTO-FIT ---")
	for c in inst.get_children():
		if c is Node3D:
			var n := c as Node3D
			print("Child '", n.name, "' pos: ", n.position)
			
	print("\n--- ANIMATING 10 FRAMES ---")
	for i in range(10):
		DronePropellerSystem.animate_propellers(inst, 0.016)
	for c in inst.get_children():
		if c.name.begins_with("propeller"):
			var n := c as Node3D
			print("Prop '", n.name, "' rot: ", n.rotation_degrees, " pos: ", n.position)
			
	quit()
