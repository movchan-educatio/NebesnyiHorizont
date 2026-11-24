extends Node

var _fails := 0


func _check(ok: bool, label: String) -> void:
	if ok:
		print("[COLOR] PASS ", label)
	else:
		_fails += 1
		print("[COLOR] FAIL ", label)


func _ready() -> void:
	for idx in [13, 14, 15]:
		var holder := Node3D.new()
		add_child(holder)
		var model := DroneCatalog.attach_model(holder, idx)
		var mats := {}
		var carbon_tex := false
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			for s in range(mi.mesh.get_surface_count() if mi.mesh != null else 0):
				var m := (mi as MeshInstance3D).get_active_material(s)
				if m is StandardMaterial3D:
					var sm := m as StandardMaterial3D
					var key := String(sm.resource_name)
					if key == "Carbon_Weave" and sm.albedo_texture != null:
						carbon_tex = true
					if not mats.has(key):
						mats[key] = {"color": sm.albedo_color, "tex": sm.albedo_texture != null}
		print("[COLOR] preset=", idx, " mats=", mats)
		_check(carbon_tex, "preset %d Carbon_Weave має checker-текстуру" % idx)
		holder.queue_free()
		for _f in range(2):
			await get_tree().process_frame
	await get_tree().process_frame
	print("[COLOR] failures=", _fails)
	get_tree().quit(0 if _fails == 0 else 1)
