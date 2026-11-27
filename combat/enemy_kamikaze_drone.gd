class_name EnemyKamikazeDrone
extends StaticBody3D
## Великий ворожий FPV-дрон-камікадзе (KT-8 «Гриф» / KT-12 «Василіск»).
## Pure ramming interceptor: never carries or drops bombs. It lead-pursues the
## pilot's drone with predictive guidance, dives aggressively, detonates on
## genuine contact/proximity, and banks away into a fresh attack run when the
## pilot evades. Uses the existing Explosion/DestructionFx/Sfx helpers.

signal destroyed(points: int)

const MODEL_PATHS := [
	"res://Assets/enemy_drones/KT8_Grif.glb",
	"res://Assets/enemy_drones/KT12_Basilisk.glb",
]

enum Phase { SPAWN, APPROACH, LOCK, DIVE, OVERSHOOT, FALLING, DEAD, REATTACK }

const PROXIMITY_FUSE := 2.2
const DIVE_SPEED_MIN := 24.0
const DIVE_SPEED_MAX := 36.0
const DIVE_BASE_SPEED := 30.0
const LEAD_TIME_MAX := 1.35

@export var variant: int = 0
@export var max_health: float = 140.0
@export var points: int = 260
@export var move_speed: float = 23.0
@export var dive_speed: float = 30.0
@export var turn_speed: float = 2.6
@export var prop_spin_speed: float = 14.0
@export var detect_range: float = 230.0
@export var dive_range: float = 78.0
@export var impact_damage: float = 34.0
@export var cruise_height: float = 58.0
@export var hostile: bool = true

var is_primary_target: bool = true
var impacted_player: bool = false
var phase: int = Phase.SPAWN
var health: float = 1.0
var _target: Node3D = null
var _model: Node3D = null
var _props: Array[Node3D] = []
var _engine: AudioStreamPlayer3D = null
var _buzz: AudioStreamPlayer3D = null
var _phase_timer: float = 0.0
var _align_timer: float = 0.0
var _closest_dive_dist: float = INF
var _prev_dist: float = 1.0e20
var _reattack_side: float = 1.0
var _dive_speed_smooth := 0.0
var _target_velocity := Vector3.ZERO
var _last_target_position := Vector3.ZERO
var _has_target_sample: bool = false
var _fall_velocity := Vector3.ZERO
var _fall_timer: float = 0.0
var _warned: bool = false
var _dead_notified: bool = false
var _level_ref: Node = null
var _cached_floor_cell: Vector2i = Vector2i(2147483647, 2147483647)
var _cached_floor_y: float = 0.0


func _ready() -> void:
	health = max_health
	add_to_group("combat_target")
	add_to_group("air_target")
	if is_primary_target:
		add_to_group("primary_combat_target")
	add_to_group("enemy_kamikaze")
	collision_layer = 1
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	# Proxy body only; the warhead fuse itself is the 2.2 m check in _try_impact.
	sphere.radius = 1.2
	shape.shape = sphere
	add_child(shape)
	_build_model()
	_build_audio()
	if OS.has_environment("DRONE_KAMIKAZE_DEBUG"):
		print("[KAMIKAZE] spawned variant=", variant, " hp=", health)


func _build_model() -> void:
	var path: String = MODEL_PATHS[clampi(variant, 0, MODEL_PATHS.size() - 1)]
	if not ResourceLoader.exists(path):
		push_warning("[KAMIKAZE] model missing: " + path)
		return
	var packed := load(path) as PackedScene
	if packed == null:
		return
	_model = packed.instantiate() as Node3D
	if _model == null:
		return
	_model.name = "Model"
	_model.scale = Vector3.ONE * 1.15
	add_child(_model)
	DroneCatalog.apply_pack_colors(_model)
	_setup_rotor_pivots(_model)
	print("[KAMIKAZE] model ", path, " props=", _props.size())


func set_primary_target(primary: bool) -> void:
	is_primary_target = primary
	set_meta("is_primary_target", primary)
	if primary:
		if not is_in_group("primary_combat_target"):
			add_to_group("primary_combat_target")
	else:
		if is_in_group("primary_combat_target"):
			remove_from_group("primary_combat_target")


func activate() -> void:
	if phase == Phase.SPAWN:
		phase = Phase.APPROACH
		_phase_timer = 0.0
		_prev_dist = 1.0e20
		_has_target_sample = false
		_target_velocity = Vector3.ZERO


func _rotor_prefix(node_name: String) -> String:
	for token in ["_Blade_", "_Tip_", "_Stripe_", "_HubScrew_", "_RootFairing_"]:
		var idx := node_name.find(token)
		if idx > 0:
			return node_name.substr(0, idx + 1)
	for suffix in ["_HubUpper", "_HubLower", "_Nut"]:
		if node_name.ends_with(suffix):
			return node_name.substr(0, node_name.length() - suffix.length() + 1)
	return ""


func _setup_rotor_pivots(root: Node) -> void:
	_props.clear()
	var groups := {}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		for ch in cur.get_children():
			stack.append(ch)
		if not (cur is Node3D):
			continue
		var n := String(cur.name)
		var prefix := _rotor_prefix(n)
		if prefix.is_empty():
			continue
		var p := cur.get_parent()
		if p == null:
			continue
		var key := "%d:%s" % [p.get_instance_id(), prefix]
		if not groups.has(key):
			groups[key] = {"parent": p, "prefix": prefix, "parts": [], "hub": null}
		var g: Dictionary = groups[key]
		(g["parts"] as Array).append(cur)
		if n.ends_with("_HubUpper"):
			g["hub"] = cur
	var keys := groups.keys()
	keys.sort()
	for k in keys:
		var g: Dictionary = groups[k]
		var p: Node = g["parent"]
		var parts: Array = g["parts"]
		if p == null or parts.is_empty():
			continue
		var hub: Node3D = g["hub"] as Node3D
		var origin := hub.transform.origin if hub != null else (parts[0] as Node3D).transform.origin
		var pivot := Node3D.new()
		pivot.name = "KamikazePivot_%d" % _props.size()
		pivot.transform = Transform3D(Basis.IDENTITY, origin)
		p.add_child(pivot)
		for part in parts:
			var nd := part as Node3D
			var xf := nd.transform
			p.remove_child(nd)
			pivot.add_child(nd)
			nd.transform = Transform3D(xf.basis, xf.origin - origin)
		_props.append(pivot)


func _build_audio() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_engine = CombatSfx.make_looping_player(
			CombatSfx.kamikaze_engine_stream(variant), -12.0, 14.0, 320.0)
	if _engine != null:
		_engine.name = "KamikazeEngine"
		add_child(_engine)
		_engine.play()
	# Dedicated close-approach buzz layer. It is silent until the drone closes,
	# then pitches up sharply as a terminal-cue over the engine drone.
	_buzz = CombatSfx.make_looping_player(
			CombatSfx.kamikaze_engine_stream(variant), -60.0, 9.0, 90.0)
	if _buzz != null:
		_buzz.name = "KamikazeBuzz"
		add_child(_buzz)
		_buzz.volume_db = -60.0
		_buzz.pitch_scale = 1.15
		_buzz.play()


func _find_level() -> Node:
	if not is_inside_tree():
		return null
	var p := get_parent()
	while p != null:
		if p.has_method("_spawn_special_or_campaign") or p.name == "BigLevel" \
				or p.name.begins_with("LisLevel") or p.name.begins_with("OilRigLevel") \
				or p.name.begins_with("AirportLevel") \
				or p.name.begins_with("PromzonaPlavniLevel"):
			return p
		p = p.get_parent()
	return null


func _find_target() -> Node3D:
	if not is_inside_tree():
		return null
	var level := _find_level()
	if level != null:
		var d := level.get_node_or_null("Drone") as Node3D
		if d != null and is_instance_valid(d):
			return d
	return null


func _physics_process(delta: float) -> void:
	if not is_inside_tree():
		return
	if phase == Phase.FALLING:
		_process_fall(delta)
		return
	if phase == Phase.DEAD:
		return
	if phase == Phase.SPAWN:
		var lvl := _find_level()
		if lvl == null or bool(lvl.get("_mission_started")):
			activate()
		else:
			return
	_spin_props(delta)
	if _target == null or not is_instance_valid(_target):
		var found := _find_target()
		if found != _target:
			_has_target_sample = false
			_target_velocity = Vector3.ZERO
		_target = found
	if _target == null or not is_instance_valid(_target):
		_prev_dist = 1.0e20
		return
	_update_target_velocity(delta)
	var target_pos := _target.global_position
	var to_target := target_pos - global_position
	var dist := to_target.length()
	var forward := -global_transform.basis.z.normalized()
	var speed_scale := _difficulty_factor()
	_phase_timer += delta
	_update_attack_audio(dist, delta)

	# Pure ramming interceptor: no bomb release, no standoff loiter and no
	# ordnance drop at any distance. The warhead only fires on real contact
	# inside LOCK/DIVE (see _try_impact).
	match phase:
		Phase.APPROACH:
			_approach(delta, move_speed * speed_scale)
			if dist < detect_range and not _warned:
				_warned = true
				CombatSfx.play_kamikaze_warning(self, global_position)
			if dist <= dive_range or _phase_timer > 14.0:
				phase = Phase.LOCK
				_phase_timer = 0.0
				_align_timer = 0.0
				CombatSfx.play_kamikaze_warning(self, global_position)
		Phase.LOCK:
			_approach(delta, maxf(move_speed, 24.0) * speed_scale)
			var lock_dist_now := global_position.distance_to(_target.global_position)
			if _try_impact(lock_dist_now < _prev_dist - 0.002):
				return
			var lock_dir := _aim_direction(_terminal_dive_speed())
			var alignment := clampf(forward.dot(lock_dir), -1.0, 1.0)
			if alignment >= 0.88:
				_align_timer += delta
			else:
				_align_timer = 0.0
			if _phase_timer >= 2.4 or dist <= dive_range * 0.55 \
					or _align_timer >= 0.2:
				_enter_dive()
		Phase.DIVE:
			var dive_speed := _terminal_dive_speed(delta)
			_approach(delta, dive_speed)
			var dist_now := global_position.distance_to(_target.global_position)
			if _try_impact(dist_now < _prev_dist - 0.002):
				return
			var to_now := _target.global_position - global_position
			var forward_now := -global_transform.basis.z.normalized()
			_closest_dive_dist = minf(_closest_dive_dist, dist_now)
			# The pilot broke the lock and the range is opening behind us:
			# bank/climb back to APPROACH for a fresh lead-pursuit pass.
			var opening_evade := _phase_timer > 1.0 and dist_now > 28.0 \
					and to_now.length_squared() > 0.0001 \
					and forward_now.dot(to_now.normalized()) < -0.25
			if opening_evade:
				_enter_approach()
			elif _should_reattack(dist_now, to_now):
				_begin_reattack()
		Phase.REATTACK, Phase.OVERSHOOT:
			_fly_reattack(delta)
			var re_dist := global_position.distance_to(_target.global_position)
			var re_dir := _aim_direction(
					maxf(move_speed, 24.0) * speed_scale)
			var re_align := (-global_transform.basis.z.normalized()).dot(re_dir)
			if (re_dist <= dive_range and re_align >= 0.9) or _phase_timer >= 3.0:
				_enter_dive()

	_prev_dist = global_position.distance_to(_target.global_position)


## Predictive lead-pursuit: steer at the player's future position, not their
## current one. Pure interception; this function never releases ordnance.
func _approach(delta: float, spd: float) -> void:
	if not is_inside_tree():
		return
	if _target == null or not is_instance_valid(_target):
		return
	_fly_toward(delta, _aim_direction(spd), spd, phase == Phase.DIVE)


func _aim_direction(spd: float) -> Vector3:
	var aim_pos := _lead_point(spd)
	var to_aim := aim_pos - global_position
	if to_aim.length_squared() < 0.0001:
		return -global_transform.basis.z.normalized()
	return to_aim.normalized()


func _update_target_velocity(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		_target_velocity = Vector3.ZERO
		_has_target_sample = false
		return
	var pos := _target.global_position
	var tracked := Vector3.ZERO
	var has_declared := false
	if _target is RigidBody3D:
		tracked = (_target as RigidBody3D).linear_velocity
		has_declared = true
	else:
		var linear: Variant = _target.get("linear_velocity")
		if linear is Vector3:
			tracked = linear
			has_declared = true
		elif _target.has_method("get_velocity"):
			var via_method: Variant = _target.call("get_velocity")
			if via_method is Vector3:
				tracked = via_method
				has_declared = true
		else:
			var plain: Variant = _target.get("velocity")
			if plain is Vector3:
				tracked = plain
				has_declared = true
	if not has_declared:
		if _has_target_sample and delta > 0.0001:
			tracked = (pos - _last_target_position) / delta
		else:
			tracked = _target_velocity
	_target_velocity = tracked.limit_length(80.0)
	_last_target_position = pos
	_has_target_sample = true


func _lead_point(spd: float) -> Vector3:
	if _target == null or not is_instance_valid(_target):
		return global_position
	var dist := global_position.distance_to(_target.global_position)
	var lead_t := clampf(dist / maxf(spd, 18.0), 0.0, LEAD_TIME_MAX)
	var aim_pos := _target.global_position + _target_velocity * (lead_t * 0.85)
	return aim_pos


func _terminal_dive_speed(delta: float = -1.0) -> float:
	var base := clampf(maxf(dive_speed, DIVE_BASE_SPEED),
			DIVE_SPEED_MIN, DIVE_SPEED_MAX)
	var target := clampf(base * _difficulty_factor(),
			DIVE_SPEED_MIN, DIVE_SPEED_MAX)
	if _dive_speed_smooth <= 0.0:
		_dive_speed_smooth = maxf(move_speed * _difficulty_factor(), 24.0)
	if delta >= 0.0:
		_dive_speed_smooth = move_toward(_dive_speed_smooth, target, 24.0 * delta)
	return _dive_speed_smooth


func _difficulty_factor() -> float:
	match Global.difficulty:
		Global.Difficulty.RECRUIT:
			return 0.82
		Global.Difficulty.ACE:
			return 1.22
		_:
			return 1.0


func _try_impact(closing: bool) -> bool:
	if phase != Phase.LOCK and phase != Phase.DIVE:
		return false
	if _target == null or not is_instance_valid(_target):
		return false
	if not is_inside_tree():
		return false
	var dist := global_position.distance_to(_target.global_position)
	if dist > PROXIMITY_FUSE or not closing:
		return false
	# Sphere touch / genuine proximity only, and only while closing on the
	# impact. There is deliberately no bomb-style trigger in this interceptor.
	_impact()
	return true


func _enter_dive() -> void:
	phase = Phase.DIVE
	_phase_timer = 0.0
	_align_timer = 0.0
	_closest_dive_dist = INF
	_dive_speed_smooth = maxf(move_speed * _difficulty_factor(), 24.0)
	if _engine != null and is_instance_valid(_engine):
		_engine.pitch_scale = 1.25


func _enter_approach() -> void:
	phase = Phase.APPROACH
	_phase_timer = 0.0
	_align_timer = 0.0
	_closest_dive_dist = INF
	_prev_dist = 1.0e20
	if _engine != null and is_instance_valid(_engine):
		_engine.pitch_scale = minf(_engine.pitch_scale, 1.25)


func _begin_reattack() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	phase = Phase.REATTACK
	_phase_timer = 0.0
	_align_timer = 0.0
	_closest_dive_dist = INF
	_prev_dist = 1.0e20
	var right := global_transform.basis.x.normalized()
	var to_target := _target.global_position - global_position
	_reattack_side = 1.0 if to_target.dot(right) >= 0.0 else -1.0
	if _engine != null and is_instance_valid(_engine):
		_engine.pitch_scale = 1.05


func _should_reattack(dist: float, to_target: Vector3) -> bool:
	var forward := -global_transform.basis.z.normalized()
	var passed := to_target.dot(forward) < 1.0 and dist > 7.0
	var range_opened := _closest_dive_dist < 24.0 \
			and dist > _closest_dive_dist + 7.0
	return passed or range_opened or dist > dive_range * 1.1 or _phase_timer > 8.0


func _fly_toward(delta: float, desired: Vector3, speed: float,
		terminal: bool) -> void:
	if not is_inside_tree():
		return
	var floor_y := _ground_floor_y()
	if phase == Phase.APPROACH and global_position.y < floor_y + cruise_height * 0.65:
		desired.y = maxf(desired.y, 0.35)
	elif phase == Phase.LOCK or phase == Phase.REATTACK \
			or phase == Phase.OVERSHOOT:
		if global_position.y < floor_y + cruise_height * 0.45:
			desired.y = maxf(desired.y, 0.22)
	desired = desired.normalized()
	var forward := -global_transform.basis.z.normalized()
	var cross := forward.cross(desired)
	var angle := acos(clampf(forward.dot(desired), -1.0, 1.0))
	var rate := turn_speed * (1.65 if terminal else 1.0)
	if cross.length_squared() > 0.000001 and angle > 0.0001:
		var turn := minf(angle, rate * delta)
		var rot := Quaternion(cross.normalized(), turn)
		global_transform.basis = (Basis(rot) * global_transform.basis).orthonormalized()
	global_position += desired * speed * delta
	var min_y := floor_y + (1.5 if terminal else cruise_height * 0.45)
	if global_position.y < min_y:
		global_position.y = lerpf(global_position.y, min_y,
				clampf(delta * 3.5, 0.0, 1.0))
	var bank := clampf(cross.y * 1.7, -0.8, 0.8) * (1.25 if terminal else 0.75)
	_bank_visual(delta, bank)


func _fly_reattack(delta: float) -> void:
	if not is_inside_tree() or _target == null or not is_instance_valid(_target):
		return
	var target_pos := _target.global_position
	var to_target := target_pos - global_position
	var flat := Vector3(to_target.x, 0.0, to_target.z)
	var side := Vector3.ZERO
	if flat.length_squared() > 0.01:
		side = flat.normalized().cross(Vector3.UP) * _reattack_side
	var floor_y := _ground_floor_y()
	var climb_y := maxf(target_pos.y, floor_y + cruise_height * 0.55) + 16.0
	var aim := target_pos + Vector3.UP * 16.0 + side * 18.0
	if global_position.y > climb_y + 8.0:
		aim.y = target_pos.y + 6.0
	var to_aim := aim - global_position
	var dir := to_aim.normalized() if to_aim.length_squared() > 0.0001 \
			else -global_transform.basis.z.normalized()
	_fly_toward(delta, dir,
			maxf(move_speed * 1.15, 24.0) * _difficulty_factor(), false)


func _update_attack_audio(dist: float, delta: float) -> void:
	if not is_inside_tree():
		return
	var near := clampf(1.0 - (dist - PROXIMITY_FUSE) / 45.0, 0.0, 1.0)
	var base_pitch := 0.95
	if phase == Phase.DIVE:
		base_pitch = 1.20
	elif phase == Phase.REATTACK or phase == Phase.OVERSHOOT:
		base_pitch = 1.02
	var target_pitch := base_pitch + near * 0.85
	if phase == Phase.DIVE:
		# Terminal cue rises smoothly from 1.35 to 1.55 as the range closes.
		var dive_near := clampf(1.0 - dist / maxf(dive_range, 1.0), 0.0, 1.0)
		target_pitch = clampf(maxf(target_pitch,
				lerpf(1.35, 1.55, dive_near)), 1.35, 1.55)
	else:
		target_pitch = clampf(target_pitch, 0.60, 1.85)
	var blend := clampf(delta * 8.0, 0.0, 1.0)
	if _engine != null and is_instance_valid(_engine):
		_engine.pitch_scale = lerpf(_engine.pitch_scale, target_pitch, blend)
	if _buzz != null and is_instance_valid(_buzz):
		_buzz.volume_db = lerpf(_buzz.volume_db,
				lerpf(-60.0, -4.0, near * near), blend)
		_buzz.pitch_scale = lerpf(_buzz.pitch_scale,
				lerpf(1.15, 2.2, near), blend)


func _bank_visual(delta: float, target_roll: float) -> void:
	if _model == null or not is_instance_valid(_model):
		return
	_model.rotation.z = lerp_angle(_model.rotation.z, target_roll,
			clampf(delta * 4.0, 0.0, 1.0))


func _spin_props(delta: float) -> void:
	var spin := 1.0
	if phase == Phase.DIVE:
		spin = 1.7
	elif phase == Phase.REATTACK or phase == Phase.OVERSHOOT:
		spin = 1.25
	var step := prop_spin_speed * delta * spin
	for i in range(_props.size()):
		var p := _props[i]
		if is_instance_valid(p):
			var dir := 1.0 if (i % 2 == 0) else -1.0
			p.rotate_object_local(Vector3.UP, step * dir)


func _ground_floor_y() -> float:
	if not is_inside_tree():
		return 0.0
	var cell := Vector2i(int(floor(global_position.x * 0.5)), int(floor(global_position.z * 0.5)))
	if cell == _cached_floor_cell:
		return _cached_floor_y
	if _level_ref == null or not is_instance_valid(_level_ref):
		_level_ref = _find_level()
	if _level_ref != null and _level_ref.has_method("_find_ground_y"):
		_cached_floor_y = float(_level_ref.call("_find_ground_y", global_position.x, global_position.z))
	else:
		_cached_floor_y = 0.0
	_cached_floor_cell = cell
	return _cached_floor_y


func take_damage(amount: float, _hit_position: Vector3 = Vector3.ZERO) -> void:
	if phase == Phase.FALLING or phase == Phase.DEAD:
		return
	health -= amount
	if OS.has_environment("DRONE_KAMIKAZE_DEBUG"):
		print("[KAMIKAZE] hit remaining=", health)
	if health <= 0.0:
		_begin_fall(false)


func _impact() -> void:
	if phase == Phase.FALLING or phase == Phase.DEAD:
		return
	if not is_inside_tree():
		return
	if _target != null and is_instance_valid(_target):
		var level := _find_level()
		var combat: Node = null
		if level != null:
			combat = level.get_node_or_null("CombatSystem")
		var dmg := impact_damage
		if Global.difficulty == Global.Difficulty.RECRUIT:
			dmg *= 0.7
		elif Global.difficulty == Global.Difficulty.ACE:
			dmg *= 1.35
		if combat != null and combat.has_method("damage_drone"):
			combat.call("damage_drone", dmg, _target.global_position, global_position)
		elif _target.has_method("take_damage"):
			_target.call("take_damage", dmg)
	impacted_player = true
	if _engine != null and is_instance_valid(_engine):
		_engine.stop()
	if _buzz != null and is_instance_valid(_buzz):
		_buzz.stop()
	if not _dead_notified:
		_dead_notified = true
		destroyed.emit(points)
	_explode()


func _begin_fall(impacted: bool) -> void:
	if phase == Phase.FALLING or phase == Phase.DEAD:
		return
	if not is_inside_tree():
		return
	phase = Phase.FALLING
	_fall_timer = 0.0
	_fall_velocity = Vector3(randf_range(-6.0, 6.0), -8.0 if impacted else -3.0,
			randf_range(-6.0, 6.0))
	collision_layer = 0
	collision_mask = 0
	if _engine != null and is_instance_valid(_engine):
		_engine.pitch_scale = 0.6
	if _buzz != null and is_instance_valid(_buzz):
		_buzz.stop()
	CombatSfx.play_kamikaze_fall(self, global_position)
	DestructionFx.trail(self)
	if not _dead_notified:
		_dead_notified = true
		destroyed.emit(points)


func _process_fall(delta: float) -> void:
	if not is_inside_tree():
		return
	_fall_timer += delta
	_fall_velocity.y -= 18.0 * delta
	global_position += _fall_velocity * delta
	if _model != null and is_instance_valid(_model):
		_model.rotate_x(4.5 * delta)
		_model.rotate_z(3.1 * delta)
	_spin_props(delta * 0.4)
	if _fall_timer >= 1.4:
		_explode()


func _explode() -> void:
	if phase == Phase.DEAD:
		return
	phase = Phase.DEAD
	if _engine != null and is_instance_valid(_engine):
		_engine.stop()
	if _buzz != null and is_instance_valid(_buzz):
		_buzz.stop()
	if not _dead_notified:
		_dead_notified = true
		destroyed.emit(points)
	if is_inside_tree():
		var parent := get_parent()
		if parent != null:
			Explosion.spawn(parent, global_position, 7.5, 0.0)
			DestructionFx.destroy(parent, self, "shahed", 0.0,
					{"char_unit": false, "move_unit": false, "burn": false, "debris": true})
			CombatSfx.play_boom(parent, global_position, -2.0)
	queue_free()


func get_points() -> int:
	return points
