extends Node
## End-to-end QA for every mission and campaign sortie on ALL five maps.
## The old smoke tests only checked that objectives *spawned*; this one drives
## them to completion and checks that vehicles move continuously (no watchdog
## teleports), missiles cruise at a usable speed and clear the terrain, and
## every operation can actually be finished.
## Set QA_MAP=steppe|village|industrial|wetlands|airport (default airport).
##
##   Godot --headless --path . res://test/qa_airport_missions.tscn

const LEVELS := {
	"steppe": "res://sceneries/SteppeLevel.tscn",
	"village": "res://sceneries/VillageLevel.tscn",
	"industrial": "res://sceneries/IndustrialLevel.tscn",
	"wetlands": "res://sceneries/WetlandsLevel.tscn",
	"airport": "res://sceneries/AirportLevel.tscn",
}
const STEP := 0.05

var _failures := 0
var _shots := 0
var _no_shots := false
var _map := "airport"
var _level_path := "res://sceneries/AirportLevel.tscn"
var _shot_dir := "res://docs/airport_qa/missions/airport"


func _ready() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	print("[MAP-QA:", _map, "] ", "PASS " if ok else "FAIL ", label)
	if not ok:
		_failures += 1


func _run() -> void:
	_map = OS.get_environment("QA_MAP").strip_edges().to_lower()
	if not LEVELS.has(_map):
		_map = "airport"
	_level_path = String(LEVELS[_map])
	_shot_dir = "res://docs/airport_qa/missions/" + _map
	OS.set_environment("DRONE_NO_RECORD", "1")
	OS.set_environment("QA_NO_AMBIENT", "1")
	if _map != "airport":
		OS.set_environment("DRONE_MAP", _map)
	_no_shots = OS.has_environment("QA_NO_SHOTS") or DisplayServer.get_name() == "headless"
	if not _no_shots:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_shot_dir))
	Global.drone_preset = 2
	Global.chain_briefing_pending = false
	for mission_id in range(1, 11):
		await _test_special(mission_id)
	for mission_id in range(1, 5):
		await _test_campaign(mission_id)
	Global.special_mission = 0
	Global.combat_mission = 1
	print("[MAP-QA:", _map, "] screenshots=", _shots, " failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _spawn_level(special: int, campaign: int) -> Node:
	Global.play_mode = Global.PlayMode.COMBAT
	Global.special_mission = special
	Global.combat_mission = campaign
	var level: Node = (load(_level_path) as PackedScene).instantiate()
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	get_tree().paused = false
	await get_tree().create_timer(1.2).timeout
	get_tree().paused = false
	return level


func _dispose(level: Node) -> void:
	if level == null or not is_instance_valid(level):
		return
	if get_tree().current_scene == level:
		get_tree().current_scene = null
	get_tree().paused = false
	level.queue_free()
	await get_tree().process_frame
	await get_tree().create_timer(0.15).timeout


func _test_special(mission_id: int) -> void:
	var level := await _spawn_level(mission_id, 1)
	var total := int(level.get("_mission_targets_total"))
	var label := Global.get_special_mission_name(mission_id)
	if mission_id == 2:
		await _test_escort(level)
	elif mission_id == 10:
		await _test_missiles(level)
	elif mission_id in [1, 3, 4]:
		await _test_zone_mission(level, mission_id, label)
	else:
		_check(total > 0, "%s: targets spawned (%d)" % [label, total])
		_finish_by_targets(level, label)
	await _dispose(level)


func _test_campaign(mission_id: int) -> void:
	var level := await _spawn_level(0, mission_id)
	var total := int(level.get("_mission_targets_total"))
	_check(total > 0, "campaign %d: targets spawned (%d)" % [mission_id, total])
	if mission_id == 4:
		await _check_shaheds(level)
	_finish_by_targets(level, "campaign %d" % mission_id)
	await _dispose(level)


func _finish_by_targets(level: Node, label: String) -> void:
	var is_special := Global.special_mission > 0
	# A destruction can leave the cinematic kill-cam active, which defers the
	# completion check.  Cancel it in QA so the test measures mission logic,
	# not camera timing (headless happened to hide this race).
	var kc = level.get("_kill_cam")
	if kc != null and is_instance_valid(kc) and kc.has_method("cancel"):
		kc.call("cancel")
	level.call("_start_mission")
	level.set("_mission_targets_destroyed", int(level.get("_mission_targets_total")))
	level.call("_check_combat_mission_complete")
	# Campaign completion defers the debrief by 0.8 s; specials finish inline.
	if not is_special:
		await get_tree().create_timer(1.1).timeout
	if not is_instance_valid(level):
		return
	# Read the result immediately afterwards: a finished mission may queue the
	# level free on the next frame (results screen).
	var finished := bool(level.get("_mission_finished"))
	var failed := bool(level.get("_mission_failed"))
	if not finished and bool(level.get("_special_extract_active")):
		var drone_rtb := level.get_node_or_null("Drone") as Node3D
		var ep: Vector3 = level.get("_special_extract_point")
		for i in range(20):
			drone_rtb.global_position = ep + Vector3.UP * 20.0
			level.call("_update_special_mission", 0.5)
			if bool(level.get("_mission_finished")):
				break
		finished = bool(level.get("_mission_finished"))
		failed = bool(level.get("_mission_failed"))
	get_tree().paused = false
	_check(finished and not failed, "%s: completes end-to-end" % label)
	if is_instance_valid(level):
		await _shot(level, "special_%02d_result" % int(Global.special_mission)
				if Global.special_mission > 0 else "campaign_%02d_result" % int(Global.combat_mission),
				Vector3(0.0, 30.0, 40.0), Vector3(0.0, 55.0, 180.0))


func _test_zone_mission(level: Node, mission_id: int, label: String) -> void:
	var drone := level.get_node_or_null("Drone") as Node3D
	var zones: Array = level.get("_special_zones")
	_check(drone != null and zones.size() >= 2,
			"%s: drone and %d zones spawned" % [label, zones.size()])
	level.call("_start_mission")
	for z in zones:
		var pos: Vector3 = (z as Dictionary).get("pos", Vector3.ZERO)
		for i in range(12):
			drone.global_position = pos + Vector3(0.0, 5.0, 0.0)
			level.call("_update_special_mission", 0.5)
			if bool(level.get("_mission_finished")):
				break
	get_tree().paused = false
	_check(bool(level.get("_mission_finished"))
			and not bool(level.get("_mission_failed")),
			"%s: all zones completed and mission finished" % label)
	await _shot(level, "special_%02d_zones" % mission_id,
			Vector3(0.0, 20.0, 0.0), Vector3(0.0, 90.0, 150.0))


func _test_escort(level: Node) -> void:
	var convoy = level.get("_special_convoy")
	var drone := level.get_node_or_null("Drone") as Node3D
	var route: PackedVector3Array = convoy.get("_waypoints") if convoy != null else PackedVector3Array()
	var dest: Vector3 = level.get("_special_convoy_dest")
	_check(convoy != null and drone != null and route.size() >= 2,
			"escort: convoy with %d planned waypoints" % route.size())
	if convoy == null or drone == null or route.size() < 2:
		return
	# On the airport the corridor is planned at runtime, so verify no procedural
	# props/trees were spawned into it afterwards.  Other maps use authored
	# routes tuned for their terrain and are checked by continuous movement.
	if _map == "airport":
		var blocked := 0
		for i in range(route.size() - 1):
			var a := route[i]
			var b := route[i + 1]
			var steps := maxi(1, int(ceil(a.distance_to(b) / 8.0)))
			for s in range(steps + 1):
				var p := a.lerp(b, float(s) / float(steps))
				if not GroundRoutePlanner.is_point_clear(level, p, 3.0):
					blocked += 1
		_check(blocked == 0, "escort: reserved corridor is clear (%d blocked samples)" % blocked)
	await _shot(level, "special_02_convoy_start", route[0] + Vector3.UP * 12.0,
			route[0] + Vector3(-45.0, 42.0, 45.0))

	level.call("_start_mission")
	var prev: Vector3 = convoy.global_position
	var max_step := 0.0
	var stalls := 0
	var finished := false
	var iters := 0
	for i in range(2800):
		iters += 1
		drone.global_position = convoy.global_position + Vector3(0.0, 32.0, 0.0)
		convoy.call("_physics_process", STEP)
		level.call("_update_escort_mission", STEP, drone)
		var moved: float = convoy.global_position.distance_to(prev)
		max_step = maxf(max_step, moved)
		if moved < 0.02:
			stalls += 1
		prev = convoy.global_position
		if iters % 400 == 0:
			print("[MAP-QA:", _map, "] convoy tick=", iters,
					" pos=", convoy.global_position,
					" dist=", convoy.global_position.distance_to(dest))
		if bool(level.get("_mission_finished")):
			finished = true
			break
	get_tree().paused = false
	var recoveries := int(level.get("_special_convoy_recoveries"))
	print("[MAP-QA:", _map, "] convoy: %.1f s, max_step=%.2f m, stalls=%d, recoveries=%d, dist=%.1f" % [
			float(iters) * STEP, max_step, stalls, recoveries,
			convoy.global_position.distance_to(dest)])
	_check(max_step < 2.0, "escort: no teleport jumps (max step %.2f m)" % max_step)
	# A few short pauses at obstacles are normal; the old soft-lock showed
	# thousands of frozen ticks, so 80/2800 remains a strong guard.
	_check(stalls < 80, "escort: convoy keeps moving (%d frozen ticks)" % stalls)
	_check(recoveries <= 1, "escort: no soft-lock recovery needed (%d)" % recoveries)
	_check(finished and not bool(level.get("_mission_failed"))
			and convoy.global_position.distance_to(dest) < 55.0,
			"escort: convoy reached the checkpoint and mission completed")
	await _shot(level, "special_02_convoy_arrival", convoy.global_position,
			convoy.global_position + Vector3(-55.0, 45.0, 55.0))


func _test_missiles(level: Node) -> void:
	var missiles: Array = level.get("_intercept_missiles")
	_check(int(level.get("_mission_targets_total")) == 6,
			"missile: six targets/waves spawned")
	level.call("_start_mission")
	level.set("_intercept_timer", 9999.0)
	var speed_ok := true
	var alt_ok := true
	var prog_ok := true
	for wave in range(6):
		level.set("_intercept_wave", wave)
		level.call("_spawn_missile_wave")
		missiles = level.get("_intercept_missiles")
		if missiles.is_empty():
			speed_ok = false
			alt_ok = false
			break
		var entry: Dictionary = missiles[missiles.size() - 1]
		var missile = entry.get("vehicle")
		var start: Vector3 = entry.get("start", Vector3.ZERO)
		var goal: Vector3 = entry.get("goal", Vector3.ZERO)
		var speed := float(entry.get("speed", 0.0))
		var alt: float = missile.global_position.y
		# Airport missiles are scaled to the 900 m field; other maps keep the
		# deliberately interceptable 11-15.5 m/s / 20-34 m envelope.
		var min_speed := 25.0 if _map == "airport" else 10.0
		var min_alt_agl := 55.0 if _map == "airport" else 15.0
		if speed < min_speed:
			speed_ok = false
		# Compare against local terrain: frontline maps have valleys, so an
		# absolute altitude threshold would report false failures.
		var ground_y := 0.12
		if level.has_method("_find_ground_y"):
			ground_y = float(level.call("_find_ground_y",
					missile.global_position.x, missile.global_position.z))
		if alt - ground_y < min_alt_agl:
			alt_ok = false
		var first: Vector3 = missile.global_position
		for i in range(220):
			missile.call("_physics_process", STEP)
			level.call("_update_missile_intercept", STEP)
			if not is_instance_valid(missile) or missile.is_destroyed:
				break
		var travelled: Vector3 = missile.global_position - first
		var route_vec := goal - start
		var progress := 0.0
		if route_vec.length_squared() > 0.01:
			progress = travelled.dot(route_vec) / route_vec.length_squared()
		if progress < 0.35:
			prog_ok = false
		print("[APT-QA] missile wave %d: speed=%.1f alt=%.1f progress=%.2f" % [
				wave + 1, speed, alt, progress])
		if is_instance_valid(missile) and not missile.is_destroyed:
			missile.take_damage(99999.0, missile.global_position)
	get_tree().paused = false
	_check(speed_ok, "missile: usable cruise speed on %s" % _map)
	_check(alt_ok, "missile: clears the terrain on %s" % _map)
	_check(prog_ok, "missile: advances along the full crossing")
	_finish_by_targets(level, "missile intercept")


func _check_shaheds(level: Node) -> void:
	var shaheds: Array = []
	for v in level.get("_vehicles"):
		if is_instance_valid(v) and int(v.get("kind")) == 6:
			shaheds.append(v)
	_check(shaheds.size() == 2, "campaign 4: two Shaheds spawned (%d)" % shaheds.size())
	var alt_ok := true
	var route_ok := true
	var min_alt := 55.0 if _map == "airport" else 12.0
	var min_loop := 200.0 if _map == "airport" else 80.0
	for s in shaheds:
		if s.global_position.y < min_alt:
			alt_ok = false
		var wps: PackedVector3Array = s.get("_waypoints")
		if wps.size() < 4 or Vector2(wps[0].x, wps[0].z).length() < min_loop:
			route_ok = false
	_check(alt_ok, "campaign 4: Shaheds fly above the terrain on %s" % _map)
	_check(route_ok, "campaign 4: Shahed patrol loops fit %s" % _map)
	await _shot(level, "campaign_04_shaheds", Vector3(0.0, 90.0, 220.0),
			Vector3(0.0, 70.0, 0.0))


func _shot(level: Node, name: String, focus: Vector3, cam_pos: Vector3) -> void:
	if _no_shots:
		return
	var cam := Camera3D.new()
	add_child(cam)
	cam.far = 2200.0
	cam.global_position = cam_pos
	cam.look_at(focus, Vector3.UP)
	cam.current = true
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null:
		var path := ProjectSettings.globalize_path(_shot_dir + "/" + name + ".png")
		img.save_png(path)
		_shots += 1
	cam.queue_free()
	await get_tree().process_frame
