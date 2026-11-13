## Procedural gate course: builds ProceduralGateTorus gates starting from the
## level spawn, walking in the spawn facing direction and steering around
## obstacles. Works on any city map fitted by city_environment.
extends Node3D

@export var gate_count := 7
@export var gate_spacing := 20.0
@export var gate_height := 3.2
@export var inner_radius := 2.5
@export var outer_radius := 3.1
@export var max_course_radius := 95.0

var track: Track = null


func _ready() -> void:
	var city := get_parent().get_node_or_null("City")
	if city != null and city.has_signal("spawn_ready"):
		if not city.spawn_ready.is_connected(_on_spawn_ready):
			city.spawn_ready.connect(_on_spawn_ready)
	else:
		call_deferred("_deferred_build")


func _deferred_build() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var respawn := get_parent().get_node_or_null("Respawn") as Node3D
	if respawn != null:
		_on_spawn_ready(respawn.global_transform)


func _on_spawn_ready(spawn: Transform3D) -> void:
	track = get_parent().get_node_or_null("Track") as Track
	if track == null:
		push_warning("[GateCourse] No Track sibling found.")
		return
	_build_course(spawn)
	track.update_checkpoints()
	if track.checkpoints.is_empty():
		push_warning("[GateCourse] No gates placed.")
		return
	# Track._ready ran before the gates existed, so (re)connect here.
	for cp in track.checkpoints:
		if not cp.passed.is_connected(Callable(track, "_on_checkpoint_passed")):
			cp.passed.connect(Callable(track, "_on_checkpoint_passed"))
	track.update_course()
	var heights: Array = []
	for c in track.checkpoints:
		heights.append(snappedf((c as Node3D).global_position.y, 0.1))
	print("[GateCourse] built %d gates at heights %s" % [track.checkpoints.size(), str(heights)])


func _build_course(spawn: Transform3D) -> void:
	var space := get_world_3d().direct_space_state
	var exclude := _drone_rids()
	var start := spawn.origin
	var fwd := -spawn.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		fwd = Vector3(0, 0, -1)
	var dir := fwd.normalized()
	var pos := start
	var prev_y := start.y

	for i in range(gate_count):
		# Place each gate one step ahead so gate 0 is not at the spawn
		# itself (the drone would start inside its checkpoint area).
		var at := pos + dir * gate_spacing
		var ground := _ground_below(space, at, exclude)
		if ground.y < -9000.0:
			break
		var gy := clampf(ground.y + gate_height, prev_y - 3.0, prev_y + 3.0)
		gy = maxf(gy, ground.y + 2.5)
		var gate := ProceduralGateTorus.new()
		gate.inner_radius = inner_radius
		gate.outer_radius = outer_radius
		track.add_child(gate)
		gate.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), Vector3(at.x, gy, at.z))
		prev_y = gy
		pos = Vector3(at.x, start.y, at.z)
		# Advance along the path, steering around obstacles and back
		# towards the start area when wandering too far.
		var to_start := start - Vector3(pos.x, start.y, pos.z)
		if to_start.length() > max_course_radius:
			dir = (dir + to_start.normalized() * 1.5).normalized()
		var ahead := _forward_clearance_at(space, Vector3(pos.x, gy, pos.z), dir, gate_spacing, exclude)
		if ahead < gate_spacing * 0.7:
			var left := dir.rotated(Vector3.UP, deg_to_rad(35.0))
			var right := dir.rotated(Vector3.UP, deg_to_rad(-35.0))
			var cl := _forward_clearance_at(space, Vector3(pos.x, gy, pos.z), left, gate_spacing, exclude)
			var cr := _forward_clearance_at(space, Vector3(pos.x, gy, pos.z), right, gate_spacing, exclude)
			if cl < gate_spacing * 0.5 and cr < gate_spacing * 0.5:
				break
			dir = left if cl >= cr else right


func _ground_below(space: PhysicsDirectSpaceState3D, pos: Vector3, exclude: Array[RID]) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 30, 0), pos - Vector3(0, 15, 0))
	q.exclude = exclude
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return Vector3(0, -99999, 0)
	return hit["position"]


func _forward_clearance_at(space: PhysicsDirectSpaceState3D, origin: Vector3, dir: Vector3, length: float, exclude: Array[RID]) -> float:
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * length)
	q.exclude = exclude
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return length
	return origin.distance_to(hit["position"])


func _drone_rids() -> Array[RID]:
	var out: Array[RID] = []
	var drone := get_parent().get_node_or_null("Drone")
	if drone is CollisionObject3D:
		out.append((drone as CollisionObject3D).get_rid())
	return out
