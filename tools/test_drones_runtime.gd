extends Node

func _ready() -> void:
	print("=================================================================")
	print("TESTING GODOT RUNTIME PROPELLERS FOR ALL PRESETS")
	print("=================================================================")
	
	for idx in range(10): # 0 to 9
		var p_info = DroneCatalog.preset(idx)
		var d_name = str(p_info.get("name", "Unknown"))
		var model_path = str(p_info.get("model", ""))
		print("\n-------------------------------------------------------------")
		print("DRONE PRESET %d: %s (%s)" % [idx, d_name, model_path.get_file()])
		print("-------------------------------------------------------------")
		
		var root := Node3D.new()
		add_child(root)
		
		var model := DroneCatalog.attach_model(root, idx)
		if model == null:
			print("  [ERROR] attach_model returned null!")
			root.queue_free()
			continue
			
		var pivots = model.get_meta("prop_pivots", [])
		print("  Pivots count in meta: %d" % pivots.size())
		
		if pivots.size() < 4:
			print("  [CRITICAL ERROR] Drone has %d pivots (expected 4)!" % pivots.size())
		
		var names := ["FL", "FR", "BR", "BL"]
		for i in range(pivots.size()):
			var p: Node3D = pivots[i]
			if p == null:
				print("    Pivot %d is NULL!" % i)
				continue
			var name_tag = names[i] if i < names.size() else str(i)
			var gpos: Vector3 = p.global_position
			var lpos: Vector3 = p.position
			var lrot: Vector3 = p.rotation_degrees
			var spin_dir = p.get_meta("spin_dir", 0.0)
			
			# Test rotation
			var rot_before: Vector3 = p.rotation
			p.rotate_y(1.0)
			var rot_after: Vector3 = p.rotation
			var rotated: bool = (rot_after != rot_before)
			
			print("    [%s] '%s' loc_pos=(%.4f, %.4f, %.4f) glob_pos=(%.4f, %.4f, %.4f) rot_deg=(%.1f, %.1f, %.1f) spin_dir=%s can_spin=%s" % [
				name_tag, p.name, lpos.x, lpos.y, lpos.z, gpos.x, gpos.y, gpos.z, lrot.x, lrot.y, lrot.z, str(spin_dir), str(rotated)
			])
			
		root.queue_free()
		
	print("\n=================================================================")
	print("AUDIT COMPLETE")
	print("=================================================================")
	get_tree().quit(0)
