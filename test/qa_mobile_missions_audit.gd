extends Node
## Mobile-profile audit of EVERY mission on ALL five maps.
##
## Runs with MOBILE_UI + TOUCH_CONTROLS emulated (the same flags used by the
## existing mobile QA), then checks:
##   * infantry and vehicles sit at their OWN ground height (height field on
##     frontline maps, flat apron on airport), including after 6 s of simulated
##     movement with mobile LOD + ground snapping enabled,
##   * aerial units cruise at the right altitude for each map,
##   * zone / extraction objectives stay inside the reachable arena,
##   * no mission already failed or produced NaN positions,
##   * touch controls are active in every sortie.
## Logic completion is covered by qa_airport_missions (also map-parameterised).
## Set QA_MAP=steppe|village|industrial|wetlands|airport (default airport).

const LEVELS := {
	"steppe": "res://sceneries/SteppeLevel.tscn",
	"village": "res://sceneries/VillageLevel.tscn",
	"industrial": "res://sceneries/IndustrialLevel.tscn",
	"wetlands": "res://sceneries/WetlandsLevel.tscn",
	"airport": "res://sceneries/AirportLevel.tscn",
	"lis_forest_freestyle": "res://sceneries/LisLevel.tscn",
}
const STEP := 0.05

var _failures := 0
var _shots := 0
var _no_shots := false
var _saved := {}
var _map := "airport"
var _level_path := "res://sceneries/AirportLevel.tscn"
var _shot_dir := "res://docs/airport_qa/mobile/airport"


func _ready() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	print("[MOB-QA:", _map, "] ", "PASS " if ok else "FAIL ", label)
	if not ok:
		_failures += 1


func _remember(key: String) -> void:
	_saved[key] = {
		"had": OS.has_environment(key),
		"value": OS.get_environment(key),
	}


func _restore() -> void:
	for key in _saved.keys():
		var entry: Dictionary = _saved[key]
		if bool(entry["had"]):
			OS.set_environment(key, String(entry["value"]))
		else:
			OS.unset_environment(key)


func _run() -> void:
	_map = OS.get_environment("QA_MAP").strip_edges().to_lower()
	if not LEVELS.has(_map):
		_map = "airport"
	_level_path = String(LEVELS[_map])
	_shot_dir = "res://docs/airport_qa/mobile/" + _map
	for key in ["MOBILE_UI", "TOUCH_CONTROLS", "DRONE_NO_RECORD", "QA_NO_AMBIENT", "DRONE_MAP"]:
		_remember(key)
	OS.set_environment("MOBILE_UI", "1")
	OS.set_environment("TOUCH_CONTROLS", "1")
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
		await _audit(mission_id, 1, "SPECIAL %d" % mission_id)
	for mission_id in range(1, 5):
		await _audit(0, mission_id, "CAMPAIGN %d" % mission_id)
	_restore()
	print("[MOB-QA:", _map, "] screenshots=", _shots, " failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _spawn(special: int, campaign: int) -> Node:
	Global.play_mode = Global.PlayMode.COMBAT
	Global.special_mission = special
	Global.combat_mission = campaign
	var level: Node = (load(_level_path) as PackedScene).instantiate()
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	get_tree().paused = false
	await get_tree().create_timer(1.4).timeout
	get_tree().paused = false
	return level


func _audit(special: int, campaign: int, label: String) -> void:
	var level := await _spawn(special, campaign)
	var touch := get_node_or_null("/root/TouchControls")
	_check(touch != null and bool(touch.get("enabled")),
			"%s: mobile touch controls active" % label)
	_check(not bool(level.get("_mission_failed")),
			"%s: no premature mission failure" % label)

	# Targets: escort and pure zone/strike ops intentionally register zero
	# combat targets, so only strike/campaign sorties need a positive count.
	if special >= 5 or special == 10 or special == 0:
		_check(int(level.get("_mission_targets_total")) > 0,
				"%s: primary targets registered (%d)" % [
						label, int(level.get("_mission_targets_total"))])

	var infs: Array = level.get("_infantry_units")
	var vehs: Array = level.get("_vehicles")
	_check_infantry(level, infs, label, "spawn")
	_check_vehicles(level, vehs, label, "spawn")
	_check_zones(level, label)

	# Simulate movement with the mobile LOD / AI throttle active.
	var drone := level.get_node_or_null("Drone") as Node3D
	if drone != null:
		var convoy = level.get("_special_convoy")
		if convoy != null and is_instance_valid(convoy):
			drone.global_position = (convoy as Node3D).global_position + Vector3(0.0, 30.0, 0.0)
		else:
			drone.global_position = Vector3(0.0, 70.0, 255.0)
	for i in range(120):
		for u in infs:
			if is_instance_valid(u) and u.has_method("_physics_process"):
				u.call("_physics_process", STEP)
		for v in vehs:
			if is_instance_valid(v) and v.has_method("_physics_process"):
				v.call("_physics_process", STEP)
	get_tree().paused = false
	_check_infantry(level, infs, label, "after 6s")
	_check_vehicles(level, vehs, label, "after 6s")
	_check(not bool(level.get("_mission_failed")),
			"%s: still no failure after movement" % label)

	if special == 2:
		await _shot(level, "mobile_02_escort", Vector3(0.0, 20.0, 0.0),
				Vector3(0.0, 90.0, 180.0))
	elif special == 10:
		await _shot(level, "mobile_10_missiles", Vector3(0.0, 70.0, 0.0),
				Vector3(0.0, 130.0, 260.0))
	elif special == 0 and campaign == 4:
		await _shot(level, "mobile_04_shaheds", Vector3(0.0, 80.0, 0.0),
				Vector3(0.0, 140.0, 240.0))
	await _dispose(level)


func _finite(p: Vector3) -> bool:
	return is_finite(p.x) and is_finite(p.y) and is_finite(p.z)


func _ground_at(level: Node, x: float, z: float) -> float:
	if level != null and level.has_method("_find_ground_y"):
		return float(level.call("_find_ground_y", x, z))
	return 0.0


func _arena_limit(level: Node) -> float:
	var lim := float(level.get("MAP_GROUND_SAFE")) if level.get("MAP_GROUND_SAFE") != null else 152.0
	return lim + 10.0


func _check_infantry(level: Node, units: Array, label: String, when: String) -> void:
	var bad := 0
	for u in units:
		if not is_instance_valid(u):
			continue
		var p: Vector3 = (u as Node3D).global_position
		var gy := _ground_at(level, p.x, p.z)
		if not _finite(p) or absf(p.y - gy) > 1.2:
			bad += 1
			if bad <= 2:
				print("[MOB-QA:", _map, "] bad infantry ", label, " ", when,
						" ", p, " expected y=", gy)
	_check(bad == 0,
			"%s: %s — %d infantry grounded at their own height" % [
					label, when, units.size()])


func _check_vehicles(level: Node, units: Array, label: String, when: String) -> void:
	var ground_bad := 0
	var air_bad := 0
	var min_shahed := 55.0 if _map == "airport" else (35.0 if _map == "lis_forest_freestyle" else 10.0)
	for v in units:
		if not is_instance_valid(v):
			continue
		var p: Vector3 = (v as Node3D).global_position
		if not _finite(p):
			ground_bad += 1
			continue
		var kind := int(v.get("kind"))
		var gy := _ground_at(level, p.x, p.z)
		var agl := p.y - gy
		if kind == 5:
			# Campaign 3 helicopter climbs clear of valley hills / tree canopies.
			if agl < 6.0 or agl > 80.0:
				air_bad += 1
		elif kind == 6:
			# Shaheds clear the airport ruins / forest canopy.
			if agl < min_shahed or agl > 200.0:
				air_bad += 1
		elif absf(p.y - gy) > 2.0:
			ground_bad += 1
	_check(ground_bad == 0 and air_bad == 0,
			"%s: %s — %d vehicles grounded, %d air units at correct altitude" % [
					label, when, units.size(), air_bad])


func _check_zones(level: Node, label: String) -> void:
	var bad := 0
	var lim := _arena_limit(level)
	for z in level.get("_special_zones"):
		var p: Vector3 = (z as Dictionary).get("pos", Vector3.ZERO)
		if not _finite(p) or absf(p.y - _ground_at(level, p.x, p.z)) > 3.0 \
				or absf(p.x) > lim or absf(p.z) > lim:
			bad += 1
	var ep: Vector3 = level.get("_special_extract_point")
	if not _finite(ep) or absf(ep.x) > lim or absf(ep.z) > lim:
		bad += 1
	_check(bad == 0, "%s: all zone/extraction points inside the arena" % label)


func _shot(level: Node, name: String, focus: Vector3, cam_pos: Vector3) -> void:
	if _no_shots or not is_instance_valid(level):
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
		img.save_png(ProjectSettings.globalize_path(_shot_dir + "/" + name + ".png"))
		_shots += 1
	cam.queue_free()
	await get_tree().process_frame


func _dispose(level: Node) -> void:
	if level == null or not is_instance_valid(level):
		return
	if get_tree().current_scene == level:
		get_tree().current_scene = null
	get_tree().paused = false
	level.queue_free()
	await get_tree().process_frame
