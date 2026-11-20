class_name GroundRoutePlanner
extends RefCounted
## One-shot A* route planner for ground units on large, cluttered maps.
##
## The escort convoy used to follow a hard-coded five-point route that crossed
## the middle of the abandoned airport.  The GLB has hangars, wrecks and gates
## everywhere, so the truck spent the mission bumping into them and being
## teleported by the stall watchdogs.  This planner samples the *actual*
## physics world, finds a corridor with a real safety margin and smooths it
## into a short list of waypoints the ordinary vehicle steering can follow.

const CELL := 18.0
const SAMPLE_STEP := 6.0
## Flat map surfaces are colliders too, but they are walkable.  Everything
## else (walls, gates, wrecks, crates, trees) counts as an obstacle.
const FLAT_SURFACES := [
	"COL__M_Ground", "COL__M_Tarmac", "DEC__M_Tarmac", "DEC__M_FarConc",
	"COL__M_Paint", "DEC__M_Paint", "COL__M_Yellow", "COL__M_Glass",
]

var _space: PhysicsDirectSpaceState3D
var _exclude: Array[RID] = []
var _radius := 9.0
var _size := 0
var _limit := 420.0
var _blocked: Array[bool] = []
var _cache: Dictionary = {}
## Hard wall-clock budget.  A route is a nice-to-have, never a reason to
## freeze the level load on a slow phone.
var _deadline := 0


static func plan(level: Node, from: Vector3, to: Vector3,
		clearance: float = 9.0, arena_limit: float = 420.0) -> Array[Vector3]:
	var planner := GroundRoutePlanner.new()
	return planner._plan(level, from, to, clearance, arena_limit)


## Cheap point test reused by the corridor reservation code in AirportLevel.
static func is_point_clear(level: Node, pos: Vector3, radius: float = 9.0) -> bool:
	var planner := GroundRoutePlanner.new()
	planner._setup(level, radius, 420.0)
	return planner._point_clear(pos)


func _setup(level: Node, clearance: float, arena_limit: float) -> void:
	_radius = clearance
	_limit = arena_limit
	_size = maxi(3, int(floor(2.0 * _limit / CELL)) + 1)
	var world: World3D = level.get_world_3d()
	_space = world.direct_space_state if world != null else null
	_exclude.clear()
	var tree := level.get_tree()
	if tree != null:
		var drone := level.get_node_or_null("Drone")
		if drone is CollisionObject3D:
			_exclude.append((drone as CollisionObject3D).get_rid())
		for node in tree.get_nodes_in_group("vehicle"):
			if node is CollisionObject3D:
				_exclude.append((node as CollisionObject3D).get_rid())


func _plan(level: Node, from: Vector3, to: Vector3,
		clearance: float, arena_limit: float) -> Array[Vector3]:
	_setup(level, clearance, arena_limit)
	var started := Time.get_ticks_usec()
	_deadline = started + 1_500_000
	var start_cell := _nearest_free(from)
	var goal_cell := _nearest_free(to)
	var result: Array[Vector3] = []
	if start_cell < 0 or goal_cell < 0:
		return result
	var path := _astar(start_cell, goal_cell)
	if path.is_empty():
		return result
	var smoothed := _smooth(path)
	var gy: float = 0.12
	if level.has_method("_find_ground_y"):
		gy = float(level.call("_find_ground_y", from.x, from.z))
	for cell in smoothed:
		var p := _cell_pos(cell)
		result.append(Vector3(p.x, gy, p.y))
	# Exact endpoints keep the spawn/destination metadata truthful.
	if not result.is_empty():
		result[0] = Vector3(from.x, gy, from.z)
		result[result.size() - 1] = Vector3(to.x, gy, to.z)
	print("[RoutePlanner] %d cells, %d waypoints, %.1f ms" % [
		_size * _size, result.size(), (Time.get_ticks_usec() - started) / 1000.0])
	return result


func _is_flat(collider: Object) -> bool:
	if collider == null or not (collider is CollisionObject3D):
		return false
	var name := String((collider as Node).name) if collider is Node else ""
	for suffix in FLAT_SURFACES:
		if name.contains(suffix):
			return true
	return false


func _point_clear(p: Vector3) -> bool:
	if _space == null:
		return true
	var key := Vector2i(int(round(p.x / 2.0)), int(round(p.z / 2.0)))
	if _cache.has(key):
		return bool(_cache[key])
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = _radius
	query.shape = sphere
	query.transform = Transform3D(Basis(), Vector3(p.x, 1.6, p.z))
	query.collision_mask = 1
	query.exclude = _exclude
	# Ask for several hits: the flat tarmac is always in range and must not
	# hide a wall or a crate that overlaps the same sphere.
	# max_results is an argument of intersect_shape(), not a parameter property.
	var hits := _space.intersect_shape(query, 8)
	var clear := true
	for hit in hits:
		if not _is_flat(hit.get("collider")):
			clear = false
			break
	_cache[key] = clear
	return clear


func _cell_pos(index: int) -> Vector2:
	var gx := index % _size
	var gz := index / _size
	return Vector2(gx * CELL - _limit, gz * CELL - _limit)


func _cell_index(gx: int, gz: int) -> int:
	if gx < 0 or gz < 0 or gx >= _size or gz >= _size:
		return -1
	return gz * _size + gx


func _nearest_free(p: Vector3) -> int:
	var cx := clampi(int(round((p.x + _limit) / CELL)), 0, _size - 1)
	var cz := clampi(int(round((p.z + _limit) / CELL)), 0, _size - 1)
	for ring in range(0, maxi(_size, 12)):
		if ring > 0 and ring % 8 == 0 and Time.get_ticks_usec() > _deadline:
			return -1
		for dz in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if ring > 0 and absi(dx) != ring and absi(dz) != ring:
					continue
				var idx := _cell_index(cx + dx, cz + dz)
				if idx < 0:
					continue
				var c := _cell_pos(idx)
				if _point_clear(Vector3(c.x, 0.0, c.y)):
					return idx
	return -1


func _segment_clear(a: Vector2, b: Vector2) -> bool:
	var dist := a.distance_to(b)
	var steps := maxi(1, int(ceil(dist / SAMPLE_STEP)))
	for i in range(steps + 1):
		var p := a.lerp(b, float(i) / float(steps))
		if not _point_clear(Vector3(p.x, 0.0, p.y)):
			return false
	return true


func _astar(start: int, goal: int) -> Array[int]:
	var open: Array[int] = [start]
	var came_from := {}
	var g_score := {}
	var f_score := {}
	g_score[start] = 0.0
	f_score[start] = _cell_pos(start).distance_to(_cell_pos(goal))
	var goal_pos := _cell_pos(goal)
	var guard := 0
	while not open.is_empty() and guard < 6000:
		guard += 1
		if guard % 32 == 0 and Time.get_ticks_usec() > _deadline:
			print("[RoutePlanner] time budget hit; falling back to authored route")
			return []
		var best_i := 0
		var best_f := float(f_score.get(open[0], 1.0e12))
		for i in range(1, open.size()):
			var f := float(f_score.get(open[i], 1.0e12))
			if f < best_f:
				best_f = f
				best_i = i
		var current: int = open[best_i]
		open.remove_at(best_i)
		if current == goal:
			var path: Array[int] = [current]
			while came_from.has(current):
				current = int(came_from[current])
				path.push_front(current)
			return path
		var cgx := current % _size
		var cgz := current / _size
		for dz in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				if dx == 0 and dz == 0:
					continue
				var nx := _cell_index(cgx + dx, cgz + dz)
				if nx < 0:
					continue
				var np := _cell_pos(nx)
				if not _point_clear(Vector3(np.x, 0.0, np.y)):
					continue
				if dx != 0 and dz != 0:
					# No cutting diagonally through a corner.
					var ix := _cell_index(cgx + dx, cgz)
					var iz := _cell_index(cgx, cgz + dz)
					if ix >= 0:
						var px := _cell_pos(ix)
						if not _point_clear(Vector3(px.x, 0.0, px.y)):
							continue
					if iz >= 0:
						var pz := _cell_pos(iz)
						if not _point_clear(Vector3(pz.x, 0.0, pz.y)):
							continue
				var step := 1.0 if (dx == 0 or dz == 0) else 1.41421
				var tentative := float(g_score.get(current, 1.0e12)) + step
				if tentative < float(g_score.get(nx, 1.0e12)):
					came_from[nx] = current
					g_score[nx] = tentative
					f_score[nx] = tentative + np.distance_to(goal_pos) / CELL
					if not open.has(nx):
						open.append(nx)
	return []


func _smooth(path: Array[int]) -> Array[int]:
	if path.size() <= 2:
		return path
	var out: Array[int] = [path[0]]
	var i := 0
	while i < path.size() - 1:
		var j := path.size() - 1
		while j > i + 1:
			var a := _cell_pos(path[i])
			var b := _cell_pos(path[j])
			if _segment_clear(a, b):
				break
			j -= 1
		out.append(path[j])
		i = j
	return out
