extends Node

func _ready() -> void:
	for idx in [0, 3, 6, 9, 12, 15]:
		var parent := Node3D.new()
		add_child(parent)
		var model := DroneCatalog.attach_model(parent, idx)
		await get_tree().process_frame
		if model == null:
			continue
		var before := model.position
		var box := MenuUI.fit_preview_model(model, 1.15, -0.30)
		await get_tree().process_frame
		var world := _world_box(model)
		print("[FITDBG] idx=", idx, " before=", before, " after=", model.position,
				" scale=", model.scale, " rot=", model.rotation, " top=", model.top_level,
				" box_y=", box.position.y, " world_bottom=", world.position.y)
		for c in model.get_children():
			if c is Node3D and (c as Node3D).top_level:
				print("  TOPLEVEL CHILD ", c.name)
		parent.queue_free()
		await get_tree().process_frame
	get_tree().quit()

func _world_box(model: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for n in model.find_children("*", "VisualInstance3D", true, false):
		var vi := n as VisualInstance3D
		var b: AABB = vi.global_transform * vi.get_aabb()
		if first:
			out = b
			first = false
		else:
			out = out.merge(b)
	return out
