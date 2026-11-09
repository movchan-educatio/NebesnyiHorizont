extends SceneTree

# Inspect the cottage kit: print glass planes and test whether a wall exists
# immediately behind each glass pane.  This tells us whether removing the glass
# collision is enough (real hole) or the facade is solid.

func _init() -> void:
	var packed := load("res://Assets/frontline/village_cottage.glb") as PackedScene
	var root := packed.instantiate()
	for name in ["cottage_a", "cottage_b"]:
		var mi := root.find_child(name, true, false) as MeshInstance3D
		print("\n==== ", name, " ====")
		_analyze(mi)
	root.free()
	quit()

func _analyze(mi: MeshInstance3D) -> void:
	var glass_tris := []  # each: {c: Vector3, n: Vector3, area: float}
	var wall_tris := []  # each: [a,b,c]
	for s in range(mi.mesh.get_surface_count()):
		var mat := mi.mesh.surface_get_material(s)
		var key := mat.resource_name.to_lower() if mat != null else ""
		var arrays := mi.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			for i in range(0, verts.size(), 3):
				idx.append(i)
		for i in range(0, idx.size(), 3):
			var a := verts[idx[i]]
			var b := verts[idx[i + 1]]
			var c := verts[idx[i + 2]]
			var n := (b - a).cross(c - a)
			var area := n.length() * 0.5
			if area < 0.00001:
				continue
			n = n.normalized()
			if key == "glass":
				glass_tris.append({"c": (a + b + c) / 3.0, "n": n, "area": area})
			else:
				wall_tris.append([a, b, c])
	print("glass tris=", glass_tris.size(), " wall tris=", wall_tris.size())
	# Cluster glass triangles by dominant axis normal.
	var planes := {}
	for t in glass_tris:
		var n: Vector3 = t["n"]
		var axis := "X" if absf(n.x) > maxf(absf(n.y), absf(n.z)) else ("Y" if absf(n.y) > absf(n.z) else "Z")
		var sign := 1 if (n.x if axis == "X" else (n.y if axis == "Y" else n.z)) > 0.0 else -1
		var key := axis + ("+" if sign > 0 else "-")
		if not planes.has(key):
			planes[key] = []
		planes[key].append(t)
	for key in planes:
		var list: Array = planes[key]
		var cen := Vector3.ZERO
		var area := 0.0
		for t in list:
			cen += t["c"] * t["area"]
			area += t["area"]
		cen /= area
		print(" plane ", key, " tris=", list.size(), " area=", snappedf(area, 0.01), " center=", cen)
		# Cluster by distance along the plane's lateral axes into panes.
		var panes := {}
		for t in list:
			var c: Vector3 = t["c"]
			var lat := Vector2(c.x, c.y) if key.begins_with("Z") else (Vector2(c.z, c.y) if key.begins_with("X") else Vector2(c.x, c.z))
			var pk := Vector2i(roundi(lat.x * 2.0), roundi(lat.y * 2.0))
			if not panes.has(pk):
				panes[pk] = []
			panes[pk].append(t)
		# Ray tests for each unique pane cluster center.
		var tested := 0
		for pk in panes:
			var pts: Array = panes[pk]
			var c := Vector3.ZERO
			var a := 0.0
			var nn: Vector3 = pts[0]["n"]
			for t in pts:
				c += t["c"] * t["area"]
				a += t["area"]
			c /= a
			var origin := c - nn * 0.02
			var hit := _nearest_hit(origin, -nn, wall_tris, 2.0)
			if hit < 0.35:
				tested += 1
				if tested <= 8:
					print("   pane at ", c, " glass_area=", snappedf(a, 0.01), " wall_behind=", snappedf(hit, 0.001))
		print("   panes=", panes.size(), " with_wall_immediately_behind=", tested)

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
