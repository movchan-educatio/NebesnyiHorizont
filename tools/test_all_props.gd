extends Node3D

func _ready() -> void:
	print("================ DETAILED PROPELLER AUDIT IN GODOT ================")
	for idx in range(16):
		var p: Dictionary = DroneCatalog.preset(idx)
		var p_name: String = str(p.get("name", "Unknown"))
		var path: String = str(p.get("model", ""))
		if not ResourceLoader.exists(path):
			print("[%d] %s: FILE NOT FOUND %s" % [idx, p_name, path])
			continue
		var packed := load(path) as PackedScene
		var model := packed.instantiate() as Node3D
		add_child(model)
		
		var pivots: Array[Node3D] = DronePropellerSystem.setup_propellers(model, idx, float(p.get("prop_d", 5.0)))
		print("[%d] %s (model: %s): pivots=%d" % [idx, p_name, path.get_file(), pivots.size()])
		if pivots.is_empty():
			print("   !!! WARNING: NO PIVOTS FOUND FOR %s !!!" % p_name)
		for i in range(pivots.size()):
			var p_node := pivots[i]
			var initial_rot := p_node.rotation
			# Simulate 1 frame of animation
			DronePropellerSystem.animate_propellers(model, 0.016, [3000.0, 3000.0, 3000.0, 3000.0])
			var new_rot := p_node.rotation
			var diff := (new_rot - initial_rot).length()
			print("   Prop %d: '%s' class=%s pos=%s rot_diff=%.4f (SPINNING: %s)" % [
				i, p_node.name, p_node.get_class(), str(p_node.position), diff, str(diff > 0.0001)
			])
		model.queue_free()
	print("================ AUDIT COMPLETED ================")
	get_tree().quit()
