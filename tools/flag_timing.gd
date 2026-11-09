extends Node

func _ready() -> void:
	for idx in [0, 1, 3, 4, 5, 6, 7, 8, 9]:
		var parent := Node3D.new()
		add_child(parent)
		var t0 := Time.get_ticks_msec()
		var model := DroneCatalog.attach_model(parent, idx)
		var dt := Time.get_ticks_msec() - t0
		print("[TIME] preset=", idx, " attach_ms=", dt, " model=", model != null)
		parent.queue_free()
		await get_tree().process_frame
	get_tree().quit()
