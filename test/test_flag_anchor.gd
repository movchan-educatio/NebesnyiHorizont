extends Node3D

## Regression: player airframes must not carry Ukrainian flag decals or authored
## flag meshes.  The old test verified flag placement; this version verifies the
## opposite after the markings were removed.

const PRESETS := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]

var failures := 0


func _ready() -> void:
	for idx in PRESETS:
		var parent := Node3D.new()
		add_child(parent)
		var model := DroneCatalog.attach_model(parent, idx)
		await get_tree().process_frame
		if model == null:
			print("[FLAG] preset=", idx, " MODEL MISSING")
			failures += 1
			parent.queue_free()
			continue
		if model.get_node_or_null("UkraineMark") != null:
			printerr("[FLAG] preset=", idx, " runtime UkraineMark still attached")
			failures += 1
		var visible_flags := 0
		for n in model.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi == null or not mi.visible:
				continue
			var lower := String(mi.name).to_lower()
			if lower.contains("flag") or lower.contains("ukraine_mark") \
					or lower.contains("ukrainemark"):
				visible_flags += 1
		if visible_flags > 0:
			printerr("[FLAG] preset=", idx, " visible flag meshes=", visible_flags)
			failures += 1
		else:
			print("[FLAG] preset=", idx, " clean")
		parent.queue_free()
		await get_tree().process_frame
	print("[FLAG] result failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
