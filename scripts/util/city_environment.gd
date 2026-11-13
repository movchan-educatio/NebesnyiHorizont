## Fits an imported city GLB, orients Y-up, builds collision, and finds a street spawn.
extends Node3D

signal spawn_ready(xform: Transform3D)

@export var target_footprint_m: float = 0.0
@export var fit_to_ground: bool = true
@export var generate_collision: bool = true
@export var max_trimesh_triangles: int = 500000
@export var spawn_height_m: float = 2.6
@export var spawn_clearance_m: float = 18.0

var _fitted_height: float = 0.0
var spawn_transform := Transform3D.IDENTITY


func _ready() -> void:
	var started := Time.get_ticks_msec()
	_auto_orient_height()
	if fit_to_ground:
		_fit_to_ground()
	if generate_collision:
		_build_collision(self)
	_build_city_skyline_backdrop()
	print("[CityEnvironment] fitted in %d ms, height %.1f m" % [Time.get_ticks_msec() - started, _fitted_height])
	call_deferred("_deferred_spawn")


func _deferred_spawn() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	spawn_transform = _find_street_spawn()
	var level := get_parent()
	var respawn := level.get_node_or_null("Respawn") as Node3D
	if respawn != null:
		respawn.global_transform = spawn_transform
		_lift_respawn_out_of_geometry(respawn)
		spawn_transform = respawn.global_transform
	print("[CityEnvironment] spawn at ", spawn_transform.origin)
	spawn_ready.emit(spawn_transform)


## Guarantees the drone never spawns inside/overlapping static geometry:
## sphere-cast at the marker; nudge straight up until free (max +12 m).
func _lift_respawn_out_of_geometry(respawn: Node3D) -> void:
	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 0.6
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.exclude = _drone_rids()
	for i in range(25):
		q.transform = respawn.global_transform
		var hit := space.intersect_shape(q, 1)
		if hit.is_empty():
			if i > 0:
				print("[CityEnvironment] spawn lifted +%.1fm to clear geometry" % (i * 0.5))
			return
		respawn.global_transform.origin.y += 0.5
	print("[CityEnvironment] WARNING: spawn still overlapping geometry")


func _auto_orient_height() -> void:
	var bounds := _world_aabb()
	if bounds.size == Vector3.ZERO:
		return
	# City height is usually the shortest axis. Rotate the GLB child, not this node.
	var root := get_child(0) as Node3D
	if root == null:
		return
	if bounds.size.y <= bounds.size.x and bounds.size.y <= bounds.size.z:
		return
	if bounds.size.z <= bounds.size.x and bounds.size.z <= bounds.size.y:
		root.rotate_x(deg_to_rad(-90.0))
		return
	root.rotate_z(deg_to_rad(90.0))


func _fit_to_ground() -> void:
	var bounds := _world_aabb()
	if bounds.size == Vector3.ZERO:
		push_warning("[CityEnvironment] No meshes found to fit.")
		return

	var footprint := maxf(bounds.size.x, bounds.size.z)
	var s := 1.0
	if target_footprint_m > 1.0 and footprint > 0.001:
		s = target_footprint_m / footprint
	scale = Vector3.ONE * s
	position = Vector3(
		-bounds.get_center().x * s,
		-bounds.position.y * s,
		-bounds.get_center().z * s
	)
	_fitted_height = bounds.size.y * s


func _world_aabb() -> AABB:
	var boxes: Array[AABB] = []
	_collect_aabbs(self, Transform3D.IDENTITY, boxes)
	if boxes.is_empty():
		return AABB()
	var bounds := boxes[0]
	for b in boxes:
		bounds = bounds.merge(b)
	return bounds


func _collect_aabbs(node: Node, xform: Transform3D, out: Array[AABB]) -> void:
	for child in node.get_children():
		var t := xform
		if child is Node3D:
			t = xform * (child as Node3D).transform
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if mi.mesh != null:
				out.append(t * mi.mesh.get_aabb())
		_collect_aabbs(child, t, out)


func _build_collision(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if mi.mesh != null and mi.get_node_or_null("__city_collision") == null:
				_add_collision(mi)
		_build_collision(child)


func _add_collision(mi: MeshInstance3D) -> void:
	var body := StaticBody3D.new()
	body.name = "__city_collision"
	var shape := CollisionShape3D.new()

	var triangles := 0
	for i in mi.mesh.get_surface_count():
		var arrays := mi.mesh.surface_get_arrays(i)
		if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] != null:
			triangles += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		elif arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] != null:
			triangles += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3

	if triangles <= max_trimesh_triangles:
		shape.shape = mi.mesh.create_trimesh_shape()
		if shape.shape is ConcavePolygonShape3D:
			(shape.shape as ConcavePolygonShape3D).backface_collision = true
	else:
		var box := BoxShape3D.new()
		var aabb := mi.mesh.get_aabb()
		box.size = aabb.size
		shape.shape = box
		shape.position = aabb.get_center()

	if shape.shape == null:
		body.queue_free()
		return

	body.add_child(shape)
	mi.add_child(body)


func _find_street_spawn() -> Transform3D:
	var bounds := _global_aabb()
	var space := get_world_3d().direct_space_state
	var best_pos := Vector3(0.0, spawn_height_m, 0.0)
	var best_dir := Vector3(0.0, 0.0, -1.0)
	var best_score := -1.0
	var fallback_pos := best_pos
	var fallback_dir := best_dir
	var fallback_score := -1.0
	var grid := 18
	var exclude := _drone_rids()
	var n_no_ground := 0
	var n_steep := 0
	var n_high := 0
	var n_nosky := 0
	var n_not_street := 0
	var n_low_obstacle := 0
	var max_up := 0.0
	var max_up_at := Vector3.ZERO
	var spawn_shape := SphereShape3D.new()
	spawn_shape.radius = 1.5
	var spawn_q := PhysicsShapeQueryParameters3D.new()
	spawn_q.shape = spawn_shape
	spawn_q.exclude = exclude

	for gx in range(grid):
		for gz in range(grid):
			var x := lerpf(bounds.position.x + bounds.size.x * 0.15, bounds.end.x - bounds.size.x * 0.15, (gx + 0.5) / grid)
			var z := lerpf(bounds.position.z + bounds.size.z * 0.15, bounds.end.z - bounds.size.z * 0.15, (gz + 0.5) / grid)
			var from := Vector3(x, bounds.end.y + 80.0, z)
			var to := Vector3(x, bounds.position.y - 5.0, z)
			var q := PhysicsRayQueryParameters3D.create(from, to)
			q.exclude = exclude
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				n_no_ground += 1
				continue
			var n: Vector3 = hit.normal
			var ground: Vector3 = hit.position
			if n.y < 0.55:
				n_steep += 1
				continue
			var height_ratio := 0.0
			if bounds.size.y > 0.001:
				height_ratio = (ground.y - bounds.position.y) / bounds.size.y
			if height_ratio > 0.28:
				n_high += 1
				continue
			var open_dir := Vector3.ZERO
			var open := 0.0
			for dir in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
				var clearance := _forward_clearance(space, ground, dir, exclude)
				if clearance > open:
					open = clearance
					open_dir = dir
			# Face along streets flanked by buildings, not into empty desert:
			# rerank the 4 axis directions by clearance + side buildings.
			open_dir = _best_facing(space, ground, exclude)
			var up_clear := _forward_clearance(space, ground, Vector3.UP, exclude, 40.0)
			if up_clear > max_up:
				max_up = up_clear
				max_up_at = ground
			# Hard reject only tunnel-like spots; low decks/wires are fine.
			if up_clear < 8.0:
				n_nosky += 1
				continue
			# Reject barriers, fences and low rails right next to the spawn: at
			# 2.6 m eye height a 0.5-1.5 m rail cuts across the first-person view
			# and can catch a rotor on take-off.
			var low_hit := false
			for i in range(8):
				var ang := TAU * float(i) / 8.0
				var low_dir := Vector3(cos(ang), 0.0, sin(ang))
				for h in [0.55, 1.45]:
					var ray_from := ground + Vector3(0.0, float(h), 0.0)
					var lq := PhysicsRayQueryParameters3D.create(ray_from,
							ray_from + low_dir * 5.0)
					lq.exclude = exclude
					if not space.intersect_ray(lq).is_empty():
						low_hit = true
						break
				if low_hit:
					break
			if low_hit:
				n_low_obstacle += 1
				continue
			# And keep 1.5 m of air around the airframe itself, so the first
			# camera frame is never half-inside a facade.
			spawn_q.transform = Transform3D(Basis.IDENTITY,
					ground + Vector3(0.0, spawn_height_m, 0.0))
			if not space.intersect_shape(spawn_q, 1).is_empty():
				n_low_obstacle += 1
				continue
			# Prefer real streets: buildings within 10-60 m at +10 m height.
			# Pure desert (all clear) scores zero here.
			var urban := _urban_score(space, ground, exclude)
			# Strongly prefer a corridor with buildings on BOTH sides (a real
			# street). Without this the old scoring picked the city edge, where
			# one side is open desert but still "close to a building".
			var street := _street_score(space, ground, exclude)
			if street <= 0.0:
				n_not_street += 1
				var fallback := open + minf(up_clear, 30.0) + urban - height_ratio * 40.0
				if fallback > fallback_score:
					fallback_score = fallback
					fallback_pos = ground + Vector3(0.0, spawn_height_m, 0.0)
					fallback_dir = open_dir if open_dir != Vector3.ZERO else Vector3(0, 0, -1)
				continue
			var score := open + minf(up_clear, 30.0) + urban + street * 2.0 - height_ratio * 40.0
			if score > best_score:
				best_score = score
				best_pos = ground + Vector3(0.0, spawn_height_m, 0.0)
				best_dir = open_dir if open_dir != Vector3.ZERO else Vector3(0, 0, -1)

	if best_score < 0.0 and fallback_score >= 0.0:
		best_score = fallback_score
		best_pos = fallback_pos
		best_dir = fallback_dir
	if best_score < 0.0:
		print("[CityEnvironment] no candidate passed (no_ground=%d steep=%d high=%d nosky=%d not_street=%d low=%d) max_up=%.1f at %s" % [n_no_ground, n_steep, n_high, n_nosky, n_not_street, n_low_obstacle, max_up, str(max_up_at)])
		best_pos = Vector3(0.0, spawn_height_m, 0.0)
		best_dir = Vector3(0.0, 0.0, -1.0)

	var basis := Basis.looking_at(best_dir, Vector3.UP)
	return Transform3D(basis, best_pos)


func _forward_clearance(space: PhysicsDirectSpaceState3D, ground: Vector3, dir: Vector3, exclude: Array[RID], length: float = -1.0) -> float:
	if length <= 0.0:
		length = spawn_clearance_m
	var origin := ground + Vector3(0, 1.4, 0)
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * length)
	q.exclude = exclude
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return length
	return origin.distance_to(hit.position)


## 0 in open desert, up to 45 on streets flanked by buildings.
func _urban_score(space: PhysicsDirectSpaceState3D, ground: Vector3, exclude: Array[RID]) -> float:
	var nearest := 60.0
	for dir in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var origin := ground + Vector3(0, 10, 0)
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 60.0)
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			nearest = minf(nearest, origin.distance_to(hit.position))
	return clampf(60.0 - nearest, 0.0, 45.0)


## 0 when at least one side of the candidate is open (city edge / plaza).
## High when walls stand on both sides of a street ~18 m apart.
func _street_score(space: PhysicsDirectSpaceState3D, ground: Vector3, exclude: Array[RID]) -> float:
	var best := 0.0
	for axis in [Vector3(1, 0, 0), Vector3(0, 0, 1)]:
		var a := _wall_distance(space, ground, axis, exclude)
		var b := _wall_distance(space, ground, -axis, exclude)
		if a < 6.0 or b < 6.0:
			continue
		var s := 52.0 - absf(a - 18.0) - absf(b - 18.0)
		best = maxf(best, s)
	return best


func _wall_distance(space: PhysicsDirectSpaceState3D, ground: Vector3, dir: Vector3,
		exclude: Array[RID]) -> float:
	var origin := ground + Vector3(0, 5.0, 0)
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 55.0)
	q.exclude = exclude
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return -1.0
	return origin.distance_to(hit.position)


## Best spawn facing: clear path ahead plus buildings visible to the sides.
func _best_facing(space: PhysicsDirectSpaceState3D, ground: Vector3, exclude: Array[RID]) -> Vector3:
	var best := Vector3(0, 0, -1)
	var best_score := -1.0
	for dir in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var ahead := _forward_clearance(space, ground, dir, exclude)
		var side := Vector3(-dir.z, 0, dir.x)
		var score := minf(ahead, 40.0) + 0.5 * _side_urban(space, ground, side, exclude)
		if score > best_score:
			best_score = score
			best = dir
	return best


func _side_urban(space: PhysicsDirectSpaceState3D, ground: Vector3, side: Vector3, exclude: Array[RID]) -> float:
	var total := 0.0
	for sgn in [1.0, -1.0]:
		var origin := ground + Vector3(0, 6, 0)
		var q := PhysicsRayQueryParameters3D.create(origin, origin + side * sgn * 60.0)
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			total += clampf(60.0 - origin.distance_to(hit.position), 0.0, 45.0)
	return total


func _global_aabb() -> AABB:
	var boxes: Array[AABB] = []
	_collect_global_aabbs(self, boxes)
	if boxes.is_empty():
		return AABB(Vector3(-50, 0, -50), Vector3(100, 40, 100))
	var bounds := boxes[0]
	for b in boxes:
		bounds = bounds.merge(b)
	return bounds


func _collect_global_aabbs(node: Node, out: Array[AABB]) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if mi.mesh != null:
				out.append(mi.global_transform * mi.mesh.get_aabb())
		_collect_global_aabbs(child, out)


func _drone_rids() -> Array[RID]:
	var out: Array[RID] = []
	var drone := get_parent().get_node_or_null("Drone")
	if drone is CollisionObject3D:
		out.append((drone as CollisionObject3D).get_rid())
	return out


## Builds a lightweight, shadowless, collision-free distant skyscraper & urban
## outskirts silhouette ring outside the shrunk city GLB so the skyline feels
## expansive without taxing CPU or GPU.
func _build_city_skyline_backdrop() -> void:
	var level := get_parent()
	if level == null or level.get_node_or_null("CityHorizonBackdrop") != null:
		return
	var bounds := _global_aabb()
	var half_span := maxf(maxf(bounds.size.x, bounds.size.z) * 0.5, maxf(target_footprint_m * 0.5, 110.0))
	var inner_r := half_span * 1.18
	var outer_r := maxf(inner_r * 2.4, inner_r + 220.0)
	var holder := Node3D.new()
	holder.name = "CityHorizonBackdrop"

	var rng := RandomNumberGenerator.new()
	rng.seed = 20261112
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 1.0, 1.0)
	mm.mesh = box
	var count := 160
	mm.instance_count = count
	for i in range(count):
		var a := (float(i) / float(count)) * TAU + rng.randf_range(-0.025, 0.025)
		var ring_t := rng.randf()
		var r := lerpf(inner_r, outer_r, pow(ring_t, 0.85))
		var w := rng.randf_range(12.0, 32.0) * (0.7 + 0.6 * (half_span / 360.0))
		var d := rng.randf_range(12.0, 32.0) * (0.7 + 0.6 * (half_span / 360.0))
		var h := rng.randf_range(14.0, 72.0) * lerpf(1.0, 0.65, ring_t)
		var pos := Vector3(cos(a) * r, h * 0.5 - 1.0, sin(a) * r)
		var basis := Basis(Vector3.UP, a + rng.randf_range(-0.4, 0.4)).scaled(Vector3(w, h, d))
		mm.set_instance_transform(i, Transform3D(basis, pos))
		var shade := lerpf(0.24, 0.36, rng.randf())
		var warm := lerpf(0.0, 0.06, ring_t)
		mm.set_instance_color(i, Color(shade + warm, shade + warm * 0.4, shade + 0.02))

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.94
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "DistantCityBlocks"
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mmi)
	level.add_child.call_deferred(holder)
