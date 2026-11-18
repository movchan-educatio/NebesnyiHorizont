extends Node

## Regression test for the campaign air-intercept missions (3 and 4).
##
## User report: the helicopter and Shaheds were effectively impossible to
## shoot down.  Root causes covered here:
##   * targets cruised above the practical climb/dive envelope (30-54 m),
##   * the Shahed crossed at 23-28 m/s,
##   * the kamikaze proximity spheres (4.8 m / 3.2 m) were smaller than the
##     airframes,
##   * the helicopter's hold-position servo was uncapped and outran the player,
##   * blast damage ignored nearby airborne targets,
##   * free-fall payloads had no proximity fuzing against aircraft.

const BigLevelScene := preload("res://sceneries/BigLevel.tscn")
const BigLevelScript := preload("res://sceneries/BigLevel.gd")
const VehicleScript := preload("res://combat/vehicle.gd")
const PayloadScript := preload("res://combat/payload.gd")
const ExplosionScript := preload("res://combat/explosion.gd")
const AIR_FUSE_RADIUS := 7.5

var _failures := 0


class DummyTarget extends Node3D:
	var health := 1000.0
	var hits := 0
	var hostile := true
	var is_destroyed := false

	func take_damage(amount: float, _hit_position: Vector3 = Vector3.ZERO) -> void:
		health -= amount
		hits += 1


func _ready() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	print("[AIRKILL] ", "PASS " if ok else "FAIL ", label)
	if not ok:
		_failures += 1


func _run() -> void:
	OS.set_environment("DRONE_NO_RECORD", "1")
	_check_constants()
	_check_kamikaze_envelopes()
	await _check_blast_envelope()
	await _check_payload_fuse()
	await _check_spawned_missions()

	print("[AIRKILL] failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check_constants() -> void:
	var heli_alt: Vector2 = BigLevelScript.AIR_MISSION_HELI_ALT
	var heli_speed: Vector2 = BigLevelScript.AIR_MISSION_HELI_SPEED
	var sh1: Vector2 = BigLevelScript.AIR_MISSION_SHAHED_ALT_1
	var sh2: Vector2 = BigLevelScript.AIR_MISSION_SHAHED_ALT_2
	var sh_speed: Vector2 = BigLevelScript.AIR_MISSION_SHAHED_SPEED
	_check(heli_alt.y <= 32.0,
			"helicopter ceiling stays inside a strike-quad climb band (%.1f m)" % heli_alt.y)
	_check(heli_speed.y <= 14.0,
			"helicopter speed stays chaseable (%.1f m/s)" % heli_speed.y)
	_check(sh1.y <= 32.0 and sh2.y <= 32.0,
			"both Shahed lanes stay reachable (%.1f / %.1f m)" % [sh1.y, sh2.y])
	_check(sh_speed.y <= 22.0,
			"Shahed speed leaves a usable interception window (%.1f m/s)" % sh_speed.y)
	_check(heli_alt.x < heli_alt.y and sh1.x < sh1.y and sh2.x < sh2.y,
			"altitude bands are ordered ranges")


func _check_kamikaze_envelopes() -> void:
	var heli := VehicleScript.new()
	heli.kind = VehicleScript.Kind.HELI
	var shahed := VehicleScript.new()
	shahed.kind = VehicleScript.Kind.SHAHED
	var truck := VehicleScript.new()
	truck.kind = VehicleScript.Kind.TRUCK
	var soldier := Node3D.new()
	soldier.add_to_group("enemy_infantry")

	_check(CombatSystem.kamikaze_hit_radius(heli) >= 6.5,
			"helicopter kamikaze envelope covers the rotor disc (%.1f m)" %
					CombatSystem.kamikaze_hit_radius(heli))
	_check(CombatSystem.kamikaze_hit_radius(shahed) >= 4.5,
			"Shahed kamikaze envelope covers the airframe (%.1f m)" %
					CombatSystem.kamikaze_hit_radius(shahed))
	_check(CombatSystem.kamikaze_hit_radius(truck) > 0.0,
			"ground vehicles keep a finite kamikaze envelope")
	_check(CombatSystem.kamikaze_hit_radius(soldier) > 0.0,
			"infantry keep their kamikaze envelope")

	# The envelopes must resolve the old near-miss geometry as a hit.
	_check(6.5 <= CombatSystem.kamikaze_hit_radius(heli),
			"a 6.5 m pass on the helicopter registers as a kill")
	_check(4.5 <= CombatSystem.kamikaze_hit_radius(shahed),
			"a 4.5 m pass on the Shahed registers as a kill")
	var wall := StaticBody3D.new()
	_check(CombatSystem.kamikaze_hit_radius(wall) == 0.0,
			"static geometry is not treated as a proximity target")
	heli.free()
	shahed.free()
	truck.free()
	soldier.free()
	wall.free()


func _check_blast_envelope() -> void:
	var air := DummyTarget.new()
	air.add_to_group("combat_target")
	air.add_to_group("air_target")
	add_child(air)
	air.global_position = Vector3(0.0, 12.0, 0.0)
	var ground := DummyTarget.new()
	ground.add_to_group("combat_target")
	add_child(ground)
	ground.global_position = Vector3(2.0, 12.0, 0.0)
	await get_tree().physics_frame

	var blast := ExplosionScript.new()
	blast.radius = 9.0
	blast.damage = 480.0
	add_child(blast)
	blast.global_position = Vector3.ZERO
	await get_tree().physics_frame
	blast.call("_apply_damage")

	_check(air.hits > 0 and air.health < 1000.0,
			"air blast reaches an airborne target outside the ground radius (hp %.0f)" %
					air.health)
	_check(ground.hits == 0,
			"the same blast does not reach a ground target at the same distance")
	air.queue_free()
	ground.queue_free()
	blast.queue_free()
	await get_tree().process_frame


func _check_payload_fuse() -> void:
	var air := DummyTarget.new()
	air.add_to_group("air_target")
	air.add_to_group("combat_target")
	add_child(air)
	air.global_position = Vector3(0.0, 22.0, 0.0)
	var store := PayloadScript.new()
	store.kind = "vog"
	store.set("_age", 1.0)
	add_child(store)
	store.global_position = Vector3(0.0, 16.0, 0.0)
	await get_tree().physics_frame

	_check(bool(store.call("_air_proximity_fuse")),
			"a store passing %.1f m from a Shahed/Hind fuzes" % AIR_FUSE_RADIUS)
	store.global_position = Vector3(0.0, 13.0, 0.0)
	_check(not bool(store.call("_air_proximity_fuse")),
			"a store beyond the fuse radius stays inert")
	air.queue_free()
	store.queue_free()
	await get_tree().process_frame


func _check_spawned_missions() -> void:
	var saved_mode := Global.play_mode
	var saved_mission := Global.combat_mission
	var saved_special := Global.special_mission
	var saved_preset := Global.drone_preset
	Global.play_mode = Global.PlayMode.COMBAT
	Global.special_mission = 0
	Global.drone_preset = 0
	Global.chain_briefing_pending = false

	# Mission 3: one helicopter inside the tuned envelope.
	Global.combat_mission = 3
	var m3 := await _spawn_level()
	if m3 != null:
		var heli := _first_vehicle(m3, VehicleScript.Kind.HELI)
		_check(heli != null, "mission 3 spawns a helicopter")
		if heli != null:
			_check(heli.is_in_group("air_target"),
					"the helicopter joins the air_target group")
			_check(heli.cruise_height <= 32.0,
					"mission 3 helicopter cruises at %.1f m" % heli.cruise_height)
			_check(heli.move_speed <= 14.0,
					"mission 3 helicopter moves at %.1f m/s" % heli.move_speed)
		_free_level(m3)
		await get_tree().process_frame

	# Mission 4: both Shahed lanes inside the tuned envelope.
	Global.combat_mission = 4
	var m4 := await _spawn_level()
	if m4 != null:
		var shaheds := _vehicles_of(m4, VehicleScript.Kind.SHAHED)
		_check(shaheds.size() == 2, "mission 4 spawns two Shaheds")
		var bad_alt := 0
		var bad_speed := 0
		var grouped := 0
		for v in shaheds:
			if v.cruise_height > 32.0:
				bad_alt += 1
			if v.move_speed > 22.0:
				bad_speed += 1
			if v.is_in_group("air_target"):
				grouped += 1
		_check(bad_alt == 0, "every Shahed cruises below 32 m")
		_check(bad_speed == 0, "every Shahed stays below 22 m/s")
		_check(grouped == shaheds.size(), "every Shahed joins the air_target group")
		_free_level(m4)
		await get_tree().process_frame

	Global.play_mode = saved_mode
	Global.combat_mission = saved_mission
	Global.special_mission = saved_special
	Global.drone_preset = saved_preset


func _spawn_level() -> Node:
	var level := BigLevelScene.instantiate() as Node3D
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	await get_tree().create_timer(2.5).timeout
	if not is_instance_valid(level):
		return null
	return level


func _free_level(level: Node) -> void:
	if level == null or not is_instance_valid(level):
		return
	if get_tree().current_scene == level:
		get_tree().current_scene = null
	level.queue_free()


func _vehicles_of(level: Node, kind: int) -> Array:
	var out: Array = []
	if level == null:
		return out
	for node in get_tree().get_nodes_in_group("vehicle"):
		if node is Vehicle and (node as Vehicle).kind == kind \
				and level.is_ancestor_of(node):
			out.append(node)
	return out


func _first_vehicle(level: Node, kind: int) -> Vehicle:
	var found := _vehicles_of(level, kind)
	return found[0] if not found.is_empty() else null
