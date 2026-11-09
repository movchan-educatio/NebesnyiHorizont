class_name ChaosSoldier
extends EnemyRifleman

## AI soldier for the two-sided "Бойовий хаос" simulation.  It reuses the
## authored rifleman model, rig, muzzle flash, tracer, sfx and death animation
## from EnemyRifleman, but targets another AI soldier/vehicle instead of the
## player drone.

@export var team := 0
@export var engage_range := 62.0
@export var advance_range := 30.0
@export var walk_speed := 2.1
@export var damage := 2.2

var battle: Node = null
var target: Node3D = null

var _chaos_burst := 0
var _chaos_cd := 0.4
var _chaos_recover := 1.2
var _chaos_aim_timer := 0.0
var _chaos_strafe := 0.0
var _flank_time := 0.0
var _flank_dir := 1.0


func _ready() -> void:
	super._ready()
	add_to_group("chaos_soldier")
	max_health = 100.0
	health = max_health
	_patrol_active = false
	if _label != null:
		_label.text = "СИНІ" if team == 0 else "ЧЕРВОНІ"
		_label.modulate = Color(0.45, 0.78, 1.0) if team == 0 \
				else Color(1.0, 0.42, 0.30)
		_label.font_size = 44
	# The parent starts with the drone as target; chaos overrides processing.
	_drone = null
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if is_destroyed or _disabled:
		return
	if battle == null or not is_instance_valid(battle):
		return
	_update_lod(delta)
	if _reload_timer > 0.0:
		_reload_timer = maxf(0.0, _reload_timer - delta)
	if _suppress_timer > 0.0:
		_suppress_timer = maxf(0.0, _suppress_timer - delta)
	if target == null or not is_instance_valid(target) \
			or bool(target.get("is_destroyed")):
		target = battle.call("assign_target", self)
		_chaos_burst = 0
		_chaos_recover = randf_range(0.4, 1.1)
	_apply_recoil(delta)
	if target == null:
		_crouching = false
		if not _using_proxy:
			_update_pose(delta)
		_set_locomotion(delta, 0.0)
		_snap_to_ground()
		return
	var to := target.global_position - global_position
	var flat := Vector3(to.x, 0.0, to.z)
	var dist := flat.length()
	# Keep a fire line: advance to rifle range, then hold and shoot.
	if dist > advance_range:
		_crouching = false
		if not _using_proxy:
			_update_pose(delta)
		if flat.length_squared() > 0.01:
			var desired_yaw := atan2(-flat.x, -flat.z)
			rotation.y = lerp_angle(rotation.y, desired_yaw,
					clampf(delta * 4.0, 0.0, 1.0))
			var forward := -global_transform.basis.z
			forward.y = 0.0
			if forward.length_squared() > 0.0001:
				var fnorm := forward.normalized()
				var step_len := walk_speed * delta
				if _can_step(fnorm, step_len):
					global_position += fnorm * step_len
		_set_locomotion(delta, walk_speed)
		_snap_to_ground()
		return
	_crouching = (_reload_timer > 0.0) or (_suppress_timer > 0.0)
	if not _using_proxy:
		_update_pose(delta)
	_set_locomotion(delta, 0.0)
	_snap_to_ground()
	if dist > engage_range:
		return
	var los := _los_to(target)
	if not los:
		# Trees, containers and collapsed walls block the firing line.  Hold
		# and stare at the trunk forever and the battle stalls; instead sidestep
		# around the obstruction until the target is visible again.
		if _flank_time <= 0.0:
			_flank_time = 1.1
			_flank_dir = -_flank_dir
		_flank_time -= delta
		var dir := flat.normalized()
		var side := dir.cross(Vector3.UP) * _flank_dir
		var move := (dir * 0.55 + side).normalized()
		rotation.y = lerp_angle(rotation.y, atan2(-move.x, -move.z),
				clampf(delta * 5.0, 0.0, 1.0))
		var step_len := walk_speed * delta
		if _can_step(move, step_len):
			global_position += move * step_len
		else:
			_flank_dir = -_flank_dir
		_set_locomotion(delta, walk_speed)
		_snap_to_ground()
		return
	if _reload_timer > 0.0:
		return
	_aim_at_target(target, delta)
	if _chaos_burst > 0:
		_chaos_cd -= delta
		if _chaos_cd <= 0.0:
			_fire_at_target(target)
			_chaos_burst -= 1
			_mag_rounds -= 1
			_chaos_cd = shot_interval
			if _mag_rounds <= 0:
				_chaos_burst = 0
				_mag_rounds = _mag_capacity
				_reload_timer = 1.75
				_chaos_recover = 1.9
				if _detailed_rig != null:
					_detailed_rig.start_reload(1.75)
			elif _chaos_burst <= 0:
				_chaos_recover = randf_range(burst_pause_min, burst_pause_max)
	else:
		_chaos_recover -= delta
		if _chaos_recover <= 0.0:
			_chaos_burst = burst_shots
			_chaos_cd = 0.0


func _aim_at_target(t: Node3D, delta: float) -> void:
	var to := t.global_position + Vector3.UP * 1.0 - global_position
	var flat := Vector3(to.x, 0.0, to.z)
	if flat.length_squared() < 0.01:
		return
	var desired_yaw := atan2(-flat.x, -flat.z)
	rotation.y = lerp_angle(rotation.y, desired_yaw, clampf(delta * 7.0, 0.0, 1.0))
	var desired_pitch := clampf(atan2(to.y - 1.25, flat.length()), -0.16, 0.40)
	if _detailed_rig != null:
		_detailed_rig.set_aim_pitch(desired_pitch)
	elif _pitch != null:
		_pitch.rotation.x = lerp_angle(_pitch.rotation.x, desired_pitch,
				clampf(delta * 6.0, 0.0, 1.0))


func _los_to(t: Node3D) -> bool:
	if _muzzle == null:
		return false
	var from := _muzzle.global_position
	var aim := t.global_position + Vector3.UP * 0.9
	var query := PhysicsRayQueryParameters3D.create(from, aim)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	return hit.get("collider") == t


func _fire_at_target(t: Node3D) -> void:
	if _muzzle == null:
		return
	if _detailed_rig != null:
		_detailed_rig.kick()
	if _anim != null and _anim.get_animation_list().has("Fire"):
		_anim.play("Fire")
	var muzzle_pos := _muzzle.global_position
	var aim := t.global_position + Vector3.UP * randf_range(0.55, 1.25)
	var dir := (aim - muzzle_pos).normalized()
	var spread := 0.022 + global_position.distance_to(t.global_position) * 0.0009
	dir = (dir + Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)) * spread).normalized()
	var tracer = TracerScript.new()
	tracer.tracer_color = Color(0.55, 0.82, 1.0) if team == 0 \
			else Color(1.0, 0.58, 0.34)
	tracer.tracer_width = 0.65
	get_parent().add_child(tracer)
	tracer.setup(muzzle_pos, dir, tracer_speed, 0.0, self)
	# Direct damage: the stock AATracer only routes damage to the player drone.
	var ray := PhysicsRayQueryParameters3D.create(muzzle_pos, muzzle_pos + dir * 90.0)
	ray.collision_mask = 1
	ray.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty() and hit.get("collider") == t and t.has_method("take_damage"):
		t.call("take_damage", damage, hit.get("position"))
	CombatSfxScript.play_rifle(get_parent(), muzzle_pos, -9.0)
	_muzzle_flash(muzzle_pos)
	_recoil = 0.065
