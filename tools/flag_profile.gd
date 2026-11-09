extends Node

func _ready() -> void:
	for idx in [1, 7, 9]:
		var parent := Node3D.new()
		add_child(parent)
		var p := DroneCatalog.preset(idx)
		var packed := load(str(p["model"])) as PackedScene
		var model := packed.instantiate() as Node3D
		parent.add_child(model)
		await get_tree().process_frame
		var t0 := Time.get_ticks_msec()
		var data := DroneCatalog._collect_mark_surfaces(model)
		var t1 := Time.get_ticks_msec()
		var anchor := DroneCatalog._pick_mark_anchor(data["tris"], data["box"])
		var t2 := Time.get_ticks_msec()
		var tris: Dictionary = data["tris"]
		print("[PROF] preset=", idx, " collect_ms=", t1 - t0, " pick_ms=", t2 - t1,
				" tris=", (tris["a"] as PackedVector3Array).size(),
				" anchor=", anchor)
		parent.queue_free()
		await get_tree().process_frame
	get_tree().quit()
