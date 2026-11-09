## QA: list the mesh hierarchy of wheeled vehicles.
extends Node3D

func _ready() -> void:
	for kind_name in ["APC", "TRUCK", "BMP", "TANK"]:
		var v := Vehicle.new()
		v.kind = int(Vehicle.Kind[kind_name])
		v.hostile = true
		v.move_speed = 0.0
		add_child(v)
		await get_tree().process_frame
		await get_tree().process_frame
		print("[VNODES] === ", kind_name, " ===")
		var model := v.get_node_or_null("Model")
		if model == null:
			print("  no model")
		else:
			for n in model.find_children("*", "MeshInstance3D", true, false):
				var mi := n as MeshInstance3D
				var aabb := mi.global_transform * mi.get_aabb()
				print("  ", mi.name, " path=", mi.get_path(), " pos=", aabb.get_center(),
						" size=", aabb.size)
		v.queue_free()
		await get_tree().process_frame
	get_tree().quit(0)
