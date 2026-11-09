extends Node3D

## QA probe for the cottage kit: glass surfaces must be gone from both the
## visual mesh and the trimesh collider, and the large long-facade panes must
## be genuine openings a drone can pass through.

const TERRAIN := preload("res://scripts/util/frontline_terrain.gd")

var space: PhysicsDirectSpaceState3D


func _ready() -> void:
	var packed := load("res://Assets/frontline/village_cottage.glb") as PackedScene
	var lib := packed.instantiate()
	var source := lib.find_child("cottage_a", true, false) as MeshInstance3D
	var glass := _collect_glass(source)
	var walls := _collect_walls(source)
	lib.free()
	# Pick the largest glass triangle that has no wall directly behind it; that
	# is one of the real long-facade openings.
	var candidates: Array = glass.duplicate()
	candidates.sort_custom(func(a, b): return float(a["area"]) > float(b["area"]))
	var chosen: Dictionary = {}
	for t in candidates:
		var c: Vector3 = t["center"]
		var n: Vector3 = t["normal"]
		if _local_wall_hit(c + n * 0.05, -n, walls, 0.4) < 0.0:
			chosen = t
			break
	print("[COTTAGE] glass_tris=", glass.size(), " chosen=", not chosen.is_empty())
	if chosen.is_empty():
		get_tree().quit()
		return
	var root := Node3D.new()
	add_child(root)
	var node := TERRAIN._spawn_cottage(root, "cottage_a", Vector2.ZERO, 0.0, 0.0, 0)
	await get_tree().physics_frame
	space = get_world_3d().direct_space_state
	var glasses := 0
	for mi_node in node.find_children("*", "MeshInstance3D", true, false):
		var mi := mi_node as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			var mat := mi.mesh.surface_get_material(s)
			if mat != null and String(mat.resource_name).to_lower().contains("glass"):
				glasses += 1
	print("[COTTAGE] remaining_glass_surfaces=", glasses)
	print("[COTTAGE] passable=", glasses == 0)
	var wp: Vector3 = node.to_global(chosen["center"])
	var wn: Vector3 = (node.global_transform.basis * (chosen["normal"] as Vector3)).normalized()
	var q := PhysicsRayQueryParameters3D.create(wp + wn * 1.0, wp - wn * 0.6)
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	print("[COTTAGE] window_clear=", hit.is_empty(),
			" pane=", snappedf(float(chosen["area"]), 0.01),
			" local=", chosen["center"])
	if not hit.is_empty():
		print("[COTTAGE] blocking_collider=", hit.get("collider"),
				" at=", hit.get("position"))
	get_tree().quit()


func _collect_glass(source: MeshInstance3D) -> Array:
	var out: Array = []
	for s in range(source.mesh.get_surface_count()):
		var mat := source.mesh.surface_get_material(s)
		if mat == null or not String(mat.resource_name).to_lower().contains("glass"):
			continue
		var arrays := source.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx = arrays[Mesh.ARRAY_INDEX]
		var count: int = (idx as PackedInt32Array).size() if idx != null else verts.size()
		var i := 0
		while i + 2 < count:
			var ia: int = idx[i] if idx != null else i
			var ib: int = idx[i + 1] if idx != null else i + 1
			var ic: int = idx[i + 2] if idx != null else i + 2
			var a := verts[ia]
			var b := verts[ib]
			var c := verts[ic]
			var cross := (b - a).cross(c - a)
			var area := cross.length() * 0.5
			if area > 0.0001:
				out.append({"center": (a + b + c) / 3.0,
						"normal": (cross / (area * 2.0)).normalized(),
						"area": area})
			i += 3
	return out


func _collect_walls(source: MeshInstance3D) -> Array:
	var out: Array = []
	for s in range(source.mesh.get_surface_count()):
		var mat := source.mesh.surface_get_material(s)
		if mat != null and String(mat.resource_name).to_lower().contains("glass"):
			continue
		var arrays := source.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx = arrays[Mesh.ARRAY_INDEX]
		var count: int = (idx as PackedInt32Array).size() if idx != null else verts.size()
		var i := 0
		while i + 2 < count:
			var ia: int = idx[i] if idx != null else i
			var ib: int = idx[i + 1] if idx != null else i + 1
			var ic: int = idx[i + 2] if idx != null else i + 2
			out.append([verts[ia], verts[ib], verts[ic]])
			i += 3
	return out


func _local_wall_hit(origin: Vector3, dir: Vector3, tris: Array, max_dist: float) -> float:
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
