class_name LisWaterMask
extends RefCounted
## Exact river water mask, shoreline buffer, slope filter, and dry-bank route
## builder for lis_forest_freestyle (600x600 m, river surface at y = -12.0 m).
##
## Matches the authored river_water mesh in terrain.glb to 0.0 m error:
##   Blender (x, y) -> Godot (x, z = -y)
##   river_center_x(gz) = 18.0 + 58.0 * sin((-gz)*0.0075) + 16.0 * sin((-gz)*0.021 + 1.4)
##   river_half_width(gz) = 26.0 + 8.0 * sin((-gz)*0.013)

const WATER_LEVEL := -12.0
const SAFE_HEIGHT_MARGIN_INF := 1.8
const SAFE_HEIGHT_MARGIN_VEH := 2.2
const SHORE_BUFFER_INF := 4.5
const SHORE_BUFFER_VEH := 6.5
const MAX_SLOPE_COS_INF := 0.78
const MAX_SLOPE_COS_VEH := 0.87
const ARENA_SAFE := 286.0

const GRID_STEP := 10.0
const GRID_HALF := 290.0

var _grid_n: int = 0
var _heights: PackedFloat32Array = PackedFloat32Array()
var _normals: PackedVector3Array = PackedVector3Array()
var _terrain_root: Node = null
var _space: PhysicsDirectSpaceState3D = null
var _non_terrain_rids: Array[RID] = []
var _structure_rids: Array[RID] = []
var _terrain_only_exclude: Array[RID] = []
var dry_list_west: Array[Vector3] = []
var dry_list_east: Array[Vector3] = []
var ready_ok: bool = false

static var _cache_ready: bool = false
static var _cached_grid_n: int = 0
static var _cached_heights: PackedFloat32Array = PackedFloat32Array()
static var _cached_normals: PackedVector3Array = PackedVector3Array()
static var _cached_dry_west: Array[Vector3] = []
static var _cached_dry_east: Array[Vector3] = []


static func river_center_x(gz: float) -> float:
	var by := -gz
	return 18.0 + 58.0 * sin(by * 0.0075) + 16.0 * sin(by * 0.021 + 1.4)


static func river_half_width(gz: float) -> float:
	var by := -gz
	return 26.0 + 8.0 * sin(by * 0.013)


## Signed horizontal distance outside the water channel edge (negative = over water).
static func distance_to_water_edge(x: float, gz: float) -> float:
	return absf(x - river_center_x(gz)) - river_half_width(gz)


## Returns -1 for west bank, +1 for east bank.
static func bank_side(x: float, gz: float) -> int:
	return -1 if x < river_center_x(gz) else 1


static func is_wet_point(x: float, gz: float, ground_y: float, for_vehicle: bool = false) -> bool:
	var h_margin := SAFE_HEIGHT_MARGIN_VEH if for_vehicle else SAFE_HEIGHT_MARGIN_INF
	if ground_y < WATER_LEVEL + h_margin:
		return true
	var buf := SHORE_BUFFER_VEH if for_vehicle else SHORE_BUFFER_INF
	return distance_to_water_edge(x, gz) < buf


func build(level: Node3D, map_instance: Node3D) -> void:
	ready_ok = false
	dry_list_west.clear()
	dry_list_east.clear()
	_non_terrain_rids.clear()
	_structure_rids.clear()
	_terrain_only_exclude.clear()
	if level == null or not level.is_inside_tree():
		return
	var world: World3D = level.get_world_3d()
	if world == null:
		return
	_space = world.direct_space_state
	if _space == null:
		return
	_terrain_root = map_instance.get_node_or_null("Terrain") if map_instance != null else null
	_collect_exclusions(level, map_instance)

	if _cache_ready and _cached_heights.size() > 0:
		_grid_n = _cached_grid_n
		_heights = _cached_heights
		_normals = _cached_normals
		dry_list_west = _cached_dry_west.duplicate()
		dry_list_east = _cached_dry_east.duplicate()
		ready_ok = true
		print("[LIS-WATER] mask ready (cached): grid=%dx%d, dry_west=%d, dry_east=%d" % [
			_grid_n, _grid_n, dry_list_west.size(), dry_list_east.size()
		])
		return

	_grid_n = int(round((GRID_HALF * 2.0) / GRID_STEP)) + 1
	_heights.resize(_grid_n * _grid_n)
	_normals.resize(_grid_n * _grid_n)

	var h_min := 1e9
	var h_max := -1e9
	for gz_i in range(_grid_n):
		var gz := -GRID_HALF + float(gz_i) * GRID_STEP
		for gx_i in range(_grid_n):
			var gx := -GRID_HALF + float(gx_i) * GRID_STEP
			var idx := gz_i * _grid_n + gx_i
			var res := _ray_terrain_raw(gx, gz)
			var ry := float(res["y"])
			h_min = minf(h_min, ry)
			h_max = maxf(h_max, ry)
			_heights[idx] = ry
			_normals[idx] = res["normal"] as Vector3

	ready_ok = true
	# Precompute verified obstacle-free dry fallback spots on both banks.
	for gz in range(-260, 261, 20):
		for gx in range(-260, 261, 20):
			var fx := float(gx)
			var fz := float(gz)
			if is_spot_valid(fx, fz, true):
				var p := Vector3(fx, float(sample_terrain(fx, fz)["y"]), fz)
				if bank_side(fx, fz) < 0:
					dry_list_west.append(p)
				else:
					dry_list_east.append(p)
	_cached_grid_n = _grid_n
	_cached_heights = _heights.duplicate()
	_cached_normals = _normals.duplicate()
	_cached_dry_west = dry_list_west.duplicate()
	_cached_dry_east = dry_list_east.duplicate()
	_cache_ready = true
	print("[LIS-WATER] mask ready: grid=%dx%d y=[%.1f..%.1f] dry_west=%d dry_east=%d" % [
		_grid_n, _grid_n, h_min, h_max, dry_list_west.size(), dry_list_east.size()
	])


func _collect_exclusions(level: Node, map_instance: Node3D) -> void:
	var stack: Array[Node] = [level]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur == null or not is_instance_valid(cur):
			continue
		if cur is CollisionObject3D:
			var co := cur as CollisionObject3D
			var rid := co.get_rid()
			var is_terrain := (_terrain_root != null) and (cur == _terrain_root or _terrain_root.is_ancestor_of(cur))
			if is_terrain:
				_terrain_only_exclude.append(rid)
			else:
				_non_terrain_rids.append(rid)
				if map_instance != null and map_instance.is_ancestor_of(cur):
					_structure_rids.append(rid)
		for ch in cur.get_children():
			stack.append(ch)


func _ray_terrain_raw(x: float, gz: float) -> Dictionary:
	if _space == null:
		return {"y": 8.0, "normal": Vector3.UP}
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(x, 220.0, gz), Vector3(x, -120.0, gz))
	query.collision_mask = 1
	query.exclude = _non_terrain_rids
	var hit := _space.intersect_ray(query)
	if hit.is_empty():
		return {"y": 8.0, "normal": Vector3.UP}
	var pos: Vector3 = hit["position"]
	var n: Vector3 = hit.get("normal", Vector3.UP)
	if n.length_squared() < 0.01:
		n = Vector3.UP
	return {"y": pos.y, "normal": n.normalized()}


func sample_terrain(x: float, gz: float) -> Dictionary:
	if ready_ok and absf(x) <= GRID_HALF and absf(gz) <= GRID_HALF:
		var fx := clampf((x + GRID_HALF) / GRID_STEP, 0.0, float(_grid_n - 1))
		var fz := clampf((gz + GRID_HALF) / GRID_STEP, 0.0, float(_grid_n - 1))
		var ix := mini(int(floor(fx)), _grid_n - 2)
		var iz := mini(int(floor(fz)), _grid_n - 2)
		var tx := fx - float(ix)
		var tz := fz - float(iz)
		var i00 := iz * _grid_n + ix
		var i10 := i00 + 1
		var i01 := i00 + _grid_n
		var i11 := i01 + 1
		var h0 := lerpf(_heights[i00], _heights[i10], tx)
		var h1 := lerpf(_heights[i01], _heights[i11], tx)
		var n0 := _normals[i00].lerp(_normals[i10], tx)
		var n1 := _normals[i01].lerp(_normals[i11], tx)
		return {"y": lerpf(h0, h1, tz), "normal": n0.lerp(n1, tz).normalized()}
	return _ray_terrain_raw(x, gz)


func _overlaps_structure(x: float, y: float, gz: float, radius: float) -> bool:
	if _space == null:
		return false
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sphere
	q.collision_mask = 1
	q.collide_with_areas = false
	q.exclude = _terrain_only_exclude
	q.transform = Transform3D(Basis.IDENTITY, Vector3(x, y + radius + 0.35, gz))
	return not _space.intersect_shape(q, 1).is_empty()


func is_spot_valid(x: float, gz: float, for_vehicle: bool = false, check_structures: bool = true) -> bool:
	if absf(x) > ARENA_SAFE or absf(gz) > ARENA_SAFE:
		return false
	var t := sample_terrain(x, gz)
	var gy := float(t["y"])
	var n: Vector3 = t["normal"]
	if is_wet_point(x, gz, gy, for_vehicle):
		return false
	var min_cos := MAX_SLOPE_COS_VEH if for_vehicle else MAX_SLOPE_COS_INF
	if n.y < min_cos:
		return false
	if check_structures and _overlaps_structure(x, gy, gz, 2.2 if for_vehicle else 0.75):
		return false
	return true


func nearest_dry_spot(x: float, gz: float, for_vehicle: bool = false, same_bank: bool = true) -> Vector3:
	var target_bank := bank_side(x, gz)
	var cx := clampf(x, -ARENA_SAFE, ARENA_SAFE)
	var cz := clampf(gz, -ARENA_SAFE, ARENA_SAFE)
	if is_spot_valid(cx, cz, for_vehicle) and (not same_bank or bank_side(cx, cz) == target_bank):
		return Vector3(cx, float(sample_terrain(cx, cz)["y"]), cz)

	# Push immediately inland if starting inside or right near the water edge.
	var rx := river_center_x(cz)
	var hw := river_half_width(cz)
	var min_off := hw + (SHORE_BUFFER_VEH if for_vehicle else SHORE_BUFFER_INF) + 4.0
	if absf(cx - rx) < min_off:
		cx = clampf(rx + float(target_bank) * min_off, -ARENA_SAFE, ARENA_SAFE)
		if is_spot_valid(cx, cz, for_vehicle) and bank_side(cx, cz) == target_bank:
			return Vector3(cx, float(sample_terrain(cx, cz)["y"]), cz)

	# Spiral search on the requested bank.
	for ring in range(1, 13):
		var rad := 8.0 * float(ring)
		for i in range(16):
			var ang := TAU * float(i) / 16.0 + float(ring) * 0.27
			var px := clampf(cx + cos(ang) * rad, -ARENA_SAFE, ARENA_SAFE)
			var pz := clampf(cz + sin(ang) * rad, -ARENA_SAFE, ARENA_SAFE)
			if same_bank and bank_side(px, pz) != target_bank:
				continue
			if is_spot_valid(px, pz, for_vehicle):
				return Vector3(px, float(sample_terrain(px, pz)["y"]), pz)

	# Guaranteed fallback from precomputed dry list (never wet).
	var pool := (dry_list_west if target_bank < 0 else dry_list_east)
	if pool.is_empty():
		pool = dry_list_east if target_bank < 0 else dry_list_west
	var best := Vector3(-215.0, 6.0, 205.0)
	var best_d2 := 1.0e18
	var orig := Vector2(x, gz)
	for cand in pool:
		var d2 := Vector2(cand.x, cand.z).distance_squared_to(orig)
		if d2 < best_d2:
			best_d2 = d2
			best = cand
	return best


func build_dry_route(waypoints: Array, for_vehicle: bool = true, closed_loop: bool = true) -> Array[Vector3]:
	var clean: Array[Vector3] = []
	if waypoints.is_empty():
		return clean
	var first_raw := waypoints[0] as Vector3
	var route_bank := bank_side(first_raw.x, first_raw.z)
	for wp in waypoints:
		var v := wp as Vector3
		var vx := v.x
		var vz := clampf(v.z, -ARENA_SAFE, ARENA_SAFE)
		if bank_side(vx, vz) != route_bank:
			var rx := river_center_x(vz)
			var hw := river_half_width(vz)
			vx = clampf(rx + float(route_bank) * (hw + SHORE_BUFFER_VEH + 10.0), -ARENA_SAFE, ARENA_SAFE)
		var dry := nearest_dry_spot(vx, vz, for_vehicle, true)
		clean.append(Vector3(dry.x, dry.y + 0.05, dry.z))

	# Subdivide and push any segment sample approaching the river bend inland.
	for _pass in range(3):
		var refined: Array[Vector3] = []
		var count := clean.size()
		for i in range(count):
			var a := clean[i]
			refined.append(a)
			if i == count - 1 and not closed_loop:
				continue
			var b := clean[(i + 1) % count]
			var seg_len := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
			var steps := maxi(1, int(ceil(seg_len / 12.0)))
			for s in range(1, steps):
				var p := a.lerp(b, float(s) / float(steps))
				var t := sample_terrain(p.x, p.z)
				var gy := float(t["y"])
				var buf := (SHORE_BUFFER_VEH + 3.0) if for_vehicle else (SHORE_BUFFER_INF + 2.0)
				if distance_to_water_edge(p.x, p.z) < buf or is_wet_point(p.x, p.z, gy, for_vehicle):
					var rx := river_center_x(p.z)
					var hw := river_half_width(p.z)
					var target_x := clampf(rx + float(route_bank) * (hw + buf + 8.0), -ARENA_SAFE, ARENA_SAFE)
					var detour := nearest_dry_spot(target_x, p.z, for_vehicle, true)
					refined.append(Vector3(detour.x, detour.y + 0.05, detour.z))
				elif not is_spot_valid(p.x, p.z, for_vehicle, true):
					var safe_pt := nearest_dry_spot(p.x, p.z, for_vehicle, true)
					refined.append(Vector3(safe_pt.x, safe_pt.y + 0.05, safe_pt.z))
		clean = refined

	var dedup: Array[Vector3] = []
	for p in clean:
		if dedup.is_empty() or Vector2(dedup[dedup.size() - 1].x, dedup[dedup.size() - 1].z).distance_to(Vector2(p.x, p.z)) >= 6.0:
			dedup.append(p)
	return dedup if not dedup.is_empty() else clean
