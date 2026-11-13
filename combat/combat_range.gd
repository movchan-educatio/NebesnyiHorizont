## Procedural combat range: places destructible ground targets, AA guns, and
## infantry squads across distributed tactical sectors far from the player's
## forward launch site so the pilot must reconnoiter the valley and engage them.
class_name CombatRange
extends Node3D

signal target_spawned(target: Node3D)
signal aa_spawned(gun: Node3D)
signal infantry_spawned(unit: Node3D)
signal range_ready(count: int)

const CombatTargetScript = preload("res://combat/combat_target.gd")
const AAGunScript = preload("res://combat/aa_gun.gd")
const EnemyRiflemanScript = preload("res://combat/enemy_infantry.gd")

var _targets: Array[Node3D] = []
var _aa_guns: Array[Node3D] = []
var _infantry: Array[Node3D] = []
var _built := false


func _ready() -> void:
	if Global.play_mode != Global.PlayMode.COMBAT:
		print("[CombatRange] disabled (mode ", Global.play_mode, ")")
		set_process(false)
		set_physics_process(false)
		return
	if get_parent() != null and get_parent().has_method("_spawn_combat_mission"):
		print("[CombatRange] delegated to BigLevel structured combat missions")
		set_process(false)
		set_physics_process(false)
		return
	var city := get_parent().get_node_or_null("City")
	if city != null and city.has_signal("spawn_ready"):
		if not city.spawn_ready.is_connected(_on_spawn_ready):
			city.spawn_ready.connect(_on_spawn_ready)
	else:
		call_deferred("_deferred_build")


func _deferred_build() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	var respawn := get_parent().get_node_or_null("Respawn") as Node3D
	if respawn != null:
		_build(respawn.global_transform)


func _on_spawn_ready(spawn: Transform3D) -> void:
	_build(spawn)


func _build(spawn: Transform3D) -> void:
	if _built:
		return
	_built = true
	var space := get_world_3d().direct_space_state
	var exclude := _drone_rids()
	var forward := -spawn.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		forward = Vector3(0, 0, -1)
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP).normalized()

	# Distributed tactical sectors (210m to 580m from the player's distant launch site):
	# Sector A: Forward Treeline Outpost (210-270m)
	# Sector B: Western Trench & Ridge (290-380m, left flank)
	# Sector C: Industrial Factory & Rail Depot (370-460m, center)
	# Sector D: Eastern Convoy Road (310-440m, right flank)
	# Sector E: Deep Rear Command Sector (500-580m)
	var specs := [
		{"d": 135.0, "side": -1.0, "off": 38.0, "kind": CombatTargetScript.Kind.TRUCK},
		{"d": 150.0, "side": 1.0, "off": 48.0, "kind": CombatTargetScript.Kind.INFANTRY},
		{"d": 175.0, "side": -1.0, "off": 78.0, "kind": CombatTargetScript.Kind.TANK},
		{"d": 190.0, "side": 1.0, "off": 84.0, "kind": CombatTargetScript.Kind.TRUCK},
		{"d": 205.0, "side": -1.0, "off": 32.0, "kind": CombatTargetScript.Kind.TANK},
		{"d": 220.0, "side": 1.0, "off": 30.0, "kind": CombatTargetScript.Kind.BUNKER},
		{"d": 230.0, "side": -1.0, "off": 68.0, "kind": CombatTargetScript.Kind.INFANTRY},
		{"d": 240.0, "side": 1.0, "off": 74.0, "kind": CombatTargetScript.Kind.TANK},
		{"d": 250.0, "side": -1.0, "off": 46.0, "kind": CombatTargetScript.Kind.INFANTRY},
		{"d": 265.0, "side": 1.0, "off": 52.0, "kind": CombatTargetScript.Kind.TRUCK},
	]

	for spec in specs:
		var placed := _try_place(spawn, forward, right, space, exclude, spec)
		if placed == null:
			var retry: Dictionary = spec.duplicate()
			retry["off"] = float(spec["off"]) * 0.55
			placed = _try_place(spawn, forward, right, space, exclude, retry)
		if placed != null:
			_targets.append(placed)
			target_spawned.emit(placed)

	var aa_specs := [
		{"d": 185.0, "side": -1.0, "off": 55.0},
		{"d": 235.0, "side": 1.0, "off": 44.0},
	]
	for spec in aa_specs:
		var gun := _try_place_aa(spawn, forward, right, space, exclude, spec)
		if gun != null:
			_aa_guns.append(gun)
			aa_spawned.emit(gun)

	var inf_specs := [
		{"d": 235.0, "side": -1.0, "off": 55.0},
		{"d": 275.0, "side": 1.0, "off": 78.0},
		{"d": 330.0, "side": -1.0, "off": 130.0},
		{"d": 395.0, "side": 1.0, "off": 62.0},
		{"d": 425.0, "side": -1.0, "off": 44.0},
		{"d": 485.0, "side": 1.0, "off": 115.0},
		{"d": 530.0, "side": -1.0, "off": 70.0},
		{"d": 565.0, "side": 1.0, "off": 88.0},
	]
	for spec in inf_specs:
		var unit := _try_place_infantry(spawn, forward, right, space, exclude, spec)
		if unit != null:
			_infantry.append(unit)
			infantry_spawned.emit(unit)

	print("[CombatRange] placed %d targets, %d AA, %d INF across sectors" %
			[_targets.size(), _aa_guns.size(), _infantry.size()])
	range_ready.emit(_targets.size())


func _try_place_aa(spawn: Transform3D, forward: Vector3, right: Vector3,
		space: PhysicsDirectSpaceState3D, exclude: Array[RID],
		spec: Dictionary) -> Node3D:
	var offset := float(spec["off"])
	var side := float(spec["side"])
	for attempt in range(5):
		var lateral := offset
		if attempt == 1:
			side = -side
		elif attempt == 2:
			lateral = offset * 0.72
		elif attempt == 3:
			lateral = offset * 0.45
		elif attempt == 4:
			lateral = 18.0
		var hint: Vector3 = spawn.origin + forward * float(spec["d"]) + right * side * lateral
		var ground := _ground_below(space, hint, spawn.origin.y + 120.0, spawn.origin.y - 80.0, exclude)
		if ground.y < -9000.0:
			continue
		if not _is_clear(space, ground, 2.4, exclude):
			continue
		if _too_close_to_other(ground, 2.4):
			continue
		var blocked := false
		for other in _aa_guns:
			if is_instance_valid(other) and other.global_position.distance_to(ground) < 9.0:
				blocked = true
				break
		if blocked:
			continue
		return _spawn_aa(ground, spawn)
	return null


func _spawn_aa(ground: Vector3, spawn: Transform3D) -> Node3D:
	var gun = AAGunScript.new()
	gun.name = "AA_%d" % _aa_guns.size()
	add_child(gun)
	gun.global_position = ground
	var approach: Vector3 = spawn.origin - gun.global_position
	approach.y = 0.0
	if approach.length_squared() > 0.01:
		gun.look_at(gun.global_position + approach.normalized() * 10.0, Vector3.UP)
	return gun


func _try_place_infantry(spawn: Transform3D, forward: Vector3, right: Vector3,
		space: PhysicsDirectSpaceState3D, exclude: Array[RID],
		spec: Dictionary) -> Node3D:
	var offset := float(spec["off"])
	var side := float(spec["side"])
	for attempt in range(5):
		var lateral := offset
		if attempt == 1:
			side = -side
		elif attempt == 2:
			lateral = offset * 0.80
		elif attempt == 3:
			lateral = offset * 0.55
		elif attempt == 4:
			lateral = 14.0
		var hint: Vector3 = spawn.origin + forward * float(spec["d"]) + right * side * lateral
		var ground := _ground_below(space, hint, spawn.origin.y + 120.0, spawn.origin.y - 80.0, exclude)
		if ground.y < -9000.0:
			continue
		if not _is_clear(space, ground, 1.25, exclude):
			continue
		if _too_close_to_other(ground, 1.3):
			continue
		var blocked := false
		for gun in _aa_guns:
			if is_instance_valid(gun) and gun.global_position.distance_to(ground) < 9.0:
				blocked = true
				break
		if not blocked:
			for unit in _infantry:
				if is_instance_valid(unit) and unit.global_position.distance_to(ground) < 4.5:
					blocked = true
					break
		if blocked:
			continue
		return _spawn_infantry(ground, spawn)
	return null


func _spawn_infantry(ground: Vector3, spawn: Transform3D) -> Node3D:
	var unit = EnemyRiflemanScript.new()
	unit.name = "INF_%d" % _infantry.size()
	add_child(unit)
	unit.global_position = ground
	var approach: Vector3 = spawn.origin - unit.global_position
	approach.y = 0.0
	if approach.length_squared() < 0.01:
		approach = Vector3.FORWARD
	else:
		approach = approach.normalized()
	# Patrol along a cross-axis or road axis, and start already facing the initial patrol direction!
	var patrol_axis := approach.rotated(Vector3.UP, deg_to_rad(35.0 if _infantry.size() % 2 == 0 else -40.0)).normalized()
	unit.look_at(unit.global_position + patrol_axis * 10.0, Vector3.UP)
	if unit.has_method("set_patrol"):
		unit.call("set_patrol", unit.global_position, patrol_axis, 14.0, 1.55)
	return unit


func _try_place(spawn: Transform3D, forward: Vector3, right: Vector3,
		space: PhysicsDirectSpaceState3D, exclude: Array[RID],
		spec: Dictionary) -> Node3D:
	var offset := float(spec["off"])
	var side := float(spec["side"])
	for attempt in range(5):
		var lateral := offset
		if attempt == 1:
			side = -side
		elif attempt == 2:
			lateral = offset * 0.75
		elif attempt == 3:
			lateral = offset * 0.50
		elif attempt == 4:
			lateral = 20.0
		var hint: Vector3 = spawn.origin + forward * float(spec["d"]) + right * side * lateral
		var ground := _ground_below(space, hint, spawn.origin.y + 120.0, spawn.origin.y - 80.0, exclude)
		if ground.y < -9000.0:
			continue
		var radius := 3.0
		if int(spec["kind"]) == CombatTargetScript.Kind.BUNKER:
			radius = 4.2
		if not _is_clear(space, ground, radius, exclude):
			continue
		if _too_close_to_other(ground, radius):
			continue
		return _spawn_target(ground, spawn, int(spec["kind"]))
	return null


func _spawn_target(ground: Vector3, spawn: Transform3D, kind: int) -> Node3D:
	var target = CombatTargetScript.new()
	match kind:
		CombatTargetScript.Kind.TANK:
			target.max_health = 320.0
			target.points = 400
		CombatTargetScript.Kind.TRUCK:
			target.max_health = 180.0
			target.points = 250
		CombatTargetScript.Kind.BUNKER:
			target.max_health = 650.0
			target.points = 600
		CombatTargetScript.Kind.INFANTRY:
			target.max_health = 60.0
			target.points = 100
	target.kind = kind
	target.name = "Target_%s_%d" % [["TANK", "TRUCK", "BUNKER", "INFANTRY"][kind], _targets.size()]
	add_child(target)
	target.global_position = ground
	var approach: Vector3 = spawn.origin - (target as Node3D).global_position
	approach.y = 0.0
	if approach.length_squared() > 0.01:
		var side: Vector3 = approach.normalized().cross(Vector3.UP).normalized()
		target.look_at(target.global_position + side * 10.0, Vector3.UP)
		target.rotate_y(deg_to_rad(18.0))
	return target


func _ground_below(space: PhysicsDirectSpaceState3D, hint: Vector3, top: float, bottom: float,
		exclude: Array[RID]) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(Vector3(hint.x, top, hint.z), Vector3(hint.x, bottom, hint.z))
	query.exclude = exclude
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return Vector3(0.0, -99999.0, 0.0)
	var normal: Vector3 = hit["normal"]
	if normal.y < 0.65:
		return Vector3(0.0, -99999.0, 0.0)
	return hit["position"]


func _is_clear(space: PhysicsDirectSpaceState3D, ground: Vector3, radius: float,
		exclude: Array[RID]) -> bool:
	for i in range(8):
		var angle := TAU * float(i) / 8.0
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		for height in [0.9, 2.0]:
			var from: Vector3 = ground + Vector3.UP * float(height)
			var query := PhysicsRayQueryParameters3D.create(from, from + dir * radius)
			query.exclude = exclude
			if not space.intersect_ray(query).is_empty():
				return false
	return true


func _too_close_to_other(ground: Vector3, radius: float) -> bool:
	for target in _targets:
		if is_instance_valid(target) and target.global_position.distance_to(ground) < radius + 1.2:
			return true
	return false


func _drone_rids() -> Array[RID]:
	var out: Array[RID] = []
	var drone := get_parent().get_node_or_null("Drone")
	if drone is CollisionObject3D:
		out.append((drone as CollisionObject3D).get_rid())
	return out
