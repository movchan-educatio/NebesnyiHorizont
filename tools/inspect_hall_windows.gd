extends SceneTree

# Check whether the authored industrial hall's glass panes cover real holes
# (no wall directly behind) or are mounted on solid walls.

func _init() -> void:
	var packed := load("res://Assets/frontline/industrial_hall.glb") as PackedScene
	var root := packed.instantiate()
	var glass_tris := []
	var solid_tris := []
	for mi_node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := mi_node as MeshInstance3D
		var key := ""
		if mi.mesh != null and mi.mesh.get_surface_count() > 0:
			var mat := mi.mesh.surface_get_material(0)
			key = mat.resource_name.to_lower() if mat != null else ""
		var xf := mi.transform
		for s in range(mi.mesh.get_surface_count()):
			var arrays := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if idx.is_empty():
				for i in range(0, verts.size(), 3):
					idx.append(i)
			for i in range(0, idx.size(), 3):
				var a := xf * verts[idx[i]]
				var b := xf * verts[idx[i + 1]]
				var c := xf * verts[idx[i + 2]]
				var n := (b - a).cross(c - a)
				var area := n.length() * 0.5
				if area < 0.00001:
					continue
				n = n.normalized()
				if key == "hall_glass":
					glass_tris.append({"c": (a + b + c) / 3.0, "n": n, "area": area})
				elif key in ["hall_dark", "hall_moss", "hall_water"]:
					pass  # not collision either
				else:
					solid_tris.append([a, b, c])
	print("glass tris=", glass_tris.size(), " solid tris=", solid_tris.size())
	# Print glass bounds and sample hit distance behind each pane triangle.
	var gb := AABB(glass_tris[0]["c"], Vector3.ZERO)
	for t in glass_tris:
		gb = gb.expand(t["c"])
	print("glass bounds=", gb)
	var hits := 0
	var open := 0
	for i in range(0, glass_tris.size(), maxi(1, glass_tris.size() / 40)):
		var t: Dictionary = glass_tris[i]
		var c: Vector3 = t["c"]
		var nn: Vector3 = t["n"]
		var d := _nearest_hit(c - nn * 0.02, -nn, solid_tris, 3.0)
		if d >= 0.0 and d < 0.35:
			hits += 1
		else:
			open += 1
		print(" pane ", c, " n=", nn, " solid_behind=", snappedf(d, 0.001))
	print("sampled with wall immediately behind=", hits, " open=", open)
	root.free()
	quit()

func _nearest_hit(origin: Vector3, dir: Vector3, tris: Array, max_dist: float) -> float:
	var best := INF
	for t in tris:
		var d := _ray_tri(origin, dir, t[0], t[1], t[2])
		if d > 0.0001 and d < best and d <= max_dist:
			best = d
	return best if best < INF else -1.0

func _ray_tri(o: Vector3, d: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var e1 := b - a
	var e2 := c - a
	var p := d.cross(e2)
	var det := e1.dot(p)
	if absf(det) < 0.0000001:
		return -1.0
	var inv := 1.0 / det
	var tv := o - a
	var u := tv.dot(p) * inv
	if u < -0.001 or u > 1.001:
		return -1.0
	var q := tv.cross(e1)
	var v := d.dot(q) * inv
	if v < -0.001 or u + v > 1.001:
		return -1.0
	return e2.dot(q) * inv
