## QA: dump the visible meshes of each flagged airframe and where the flag
## anchor sits relative to every mesh surface below it.  Diagnoses flags that
## end up inside a canopy, dome or battery.
extends Node3D

const PRESETS := [0, 1, 3, 4, 5, 6, 7, 8, 9]


func _ready() -> void:
	for idx in PRESETS:
		var parent := Node3D.new()
		add_child(parent)
		var model := DroneCatalog.attach_model(parent, idx)
		await get_tree().process_frame
		if model == null:
			continue
		var mark := model.get_node_or_null("UkraineMark") as Node3D
		if mark == null:
			print("[VIS] preset=", idx, " no mark")
			parent.queue_free()
			continue
		var surfaces: Dictionary = DroneCatalog._collect_mark_surfaces(model)
		var box: AABB = surfaces["box"]
		var anchor_point: Vector3 = mark.position
		print("\n[VIS] ===== preset=", idx, " ", DroneCatalog.preset(idx).get("name", ""),
				" anchor=", anchor_point, " box=", box)
		# Gather every visible mesh triangle in model space.
		var all_tris: Array = []
		for v in DroneCatalog._visuals(model):
			var mi := v as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			if not mi.is_visible_in_tree():
				continue
			var xf := DroneCatalog._model_relative_xf(model, mi)
			var lb: AABB = xf * mi.mesh.get_aabb()
			var count := 0
			for s in range(mi.mesh.get_surface_count()):
				var arrays := mi.mesh.surface_get_arrays(s)
				if arrays.is_empty():
					continue
				var verts = arrays[Mesh.ARRAY_VERTEX]
				if verts == null:
					continue
				var idxs = arrays[Mesh.ARRAY_INDEX]
				var n: int = idxs.size() if idxs != null else verts.size()
				var i := 0
				while i + 2 < n:
					var ia: int = idxs[i] if idxs != null else i
					var ib: int = idxs[i + 1] if idxs != null else i + 1
					var ic: int = idxs[i + 2] if idxs != null else i + 2
					var a: Vector3 = xf * verts[ia]
					var b: Vector3 = xf * verts[ib]
					var c: Vector3 = xf * verts[ic]
					var cr := (b - a).cross(c - a)
					var ar := cr.length() * 0.5
					if ar > 0.000001:
						all_tris.append([a, b, c, cr / (ar * 2.0), ar, String(mi.name)])
						count += 1
					i += 3
			print("[VIS] mesh=", mi.name, " aabb=", lb, " tris=", count)
		# Topmost surface under the anchor and under the model centre.
		for probe in [anchor_point, Vector3(box.get_center().x, box.end.y + 0.2,
				box.get_center().z)]:
			var ox: float = probe.x
			var oz: float = probe.z
			var top_y := -INF
			var top_n := Vector3.ZERO
			var top_src := ""
			for t in all_tris:
				var d := DroneCatalog._ray_tri(Vector3(ox, box.end.y + 1.0, oz),
						Vector3.DOWN, t[0], t[1], t[2])
				if d < 0.0:
					continue
				var py: float = box.end.y + 1.0 - d
				if py > top_y:
					top_y = py
					top_n = t[3]
					top_src = t[5]
			print("[VIS] probe xz=(", snappedf(ox, 0.001), ",", snappedf(oz, 0.001),
					") top_y=", snappedf(top_y, 0.001), " normal_y=",
					snappedf(top_n.y, 0.01), " mesh=", top_src,
					" anchor_dy=", snappedf(top_y - anchor_point.y, 0.001))
		parent.queue_free()
		await get_tree().process_frame
	get_tree().quit()
