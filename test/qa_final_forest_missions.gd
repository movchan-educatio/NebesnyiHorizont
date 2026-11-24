extends Node
## End-to-end headless QA for ALL modes and missions on lis_forest_freestyle:
## - TUTORIAL (FlightSchool)
## - TRAINING Freestyle (+ 3x respawn cycles)
## - TRAINING CombatTraining
## - COMBAT Campaign 1..4 (OPERATOR + ACE)
## - COMBAT Special Operations 1..13 (including Night #5, Missiles #10, Dual Escort #11, Dawn #12, SAR #13)
## Samples 20 points/segment along every ground route and steps 120 physics
## frames on active ground missions to verify 0 wet spawns / 0 wet movement.

const LisWaterMaskScript = preload("res://maps/lis_forest_freestyle/scripts/lis_water_mask.gd")
const LEVEL_PATH := "res://sceneries/LisLevel.tscn"

var _fails := 0
var _checked_points := 0
var _wet_points := 0


func _check(ok: bool, label: String) -> void:
	if ok:
		print("[LIS-MISSIONS-QA] PASS ", label)
	else:
		_fails += 1
		print("[LIS-MISSIONS-QA] FAIL ", label)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	OS.set_environment("DRONE_NO_RECORD", "1")
	OS.set_environment("QA_NO_AMBIENT", "1")
	Global.chain_briefing_pending = false
	DroneCatalog.apply(0)

	await _test_tutorial()
	await _test_freestyle_and_respawns()
	await _test_combat_training()

	for m_id in range(1, 5):
		await _test_campaign_mission(m_id, Global.Difficulty.OPERATOR)
	for m_id in [1, 2, 4]:
		await _test_campaign_mission(m_id, Global.Difficulty.ACE)

	for s_id in range(1, 14):
		await _test_special_mission(s_id)

	Global.play_mode = Global.PlayMode.COMBAT
	Global.special_mission = 0
	Global.combat_mission = 1
	Global.combat_training = false
	Global.difficulty = Global.Difficulty.OPERATOR

	_check(_wet_points == 0, "Усі перевірені точки спавнів і маршрутів сухі (checked=%d wet=%d)" % [_checked_points, _wet_points])
	print("[LIS-MISSIONS-QA] SUMMARY checked_points=%d wet=%d failures=%d" % [_checked_points, _wet_points, _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _spawn_lis(mode: int, special: int, campaign: int, combat_train: bool = false, diff: int = Global.Difficulty.OPERATOR) -> Node:
	Global.play_mode = mode
	Global.special_mission = special
	Global.combat_mission = campaign
	Global.combat_training = combat_train
	Global.difficulty = diff
	var level := (load(LEVEL_PATH) as PackedScene).instantiate()
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	get_tree().paused = false
	for _i in range(10):
		await get_tree().physics_frame
	return level


func _dispose(level: Node) -> void:
	if level != null and is_instance_valid(level):
		if get_tree().current_scene == level:
			get_tree().current_scene = null
		get_tree().paused = false
		level.queue_free()
	for _i in range(4):
		await get_tree().process_frame


func _sample_ground_point(level: Node, x: float, z: float, for_vehicle: bool) -> bool:
	_checked_points += 1
	var gy := float(level.call("_find_ground_y", x, z))
	var wet := LisWaterMaskScript.is_wet_point(x, z, gy, for_vehicle)
	if wet:
		_wet_points += 1
		print("[LIS-MISSIONS-QA] WET POINT at (%.1f, %.1f, %.1f) vehicle=%s dist_water=%.1f" % [
			x, gy, z, str(for_vehicle), LisWaterMaskScript.distance_to_water_edge(x, z)
		])
	return not wet


func _verify_drone_spawn(level: Node, label: String) -> void:
	var drone := level.get_node_or_null("Drone") as Node3D
	_check(drone != null, "%s: Drone присутній" % label)
	if drone == null:
		return
	var p := drone.global_position
	var finite := is_finite(p.x) and is_finite(p.y) and is_finite(p.z)
	var gy := float(level.call("_find_ground_y", p.x, p.z))
	var dry := _sample_ground_point(level, p.x, p.z, false)
	var in_bounds := absf(p.x) <= 290.0 and absf(p.z) <= 290.0
	_check(finite and dry and in_bounds and p.y >= gy - 0.1 and p.y <= gy + 12.0,
			"%s: спавн дрона валідний і сухий (%.1f, %.1f, %.1f / gy=%.1f)" % [label, p.x, p.y, p.z, gy])


func _verify_units_and_routes(level: Node, label: String, sim_frames: int = 0) -> void:
	var tree := get_tree()
	var inf_list := tree.get_nodes_in_group("enemy_infantry")
	for n in inf_list:
		if not is_instance_valid(n) or not level.is_ancestor_of(n):
			continue
		var p := (n as Node3D).global_position
		_check(_sample_ground_point(level, p.x, p.z, false),
				"%s: піхотинець %s не у воді (%.1f, %.1f)" % [label, n.name, p.x, p.z])

	for n in tree.get_nodes_in_group("vehicle"):
		if not is_instance_valid(n) or not level.is_ancestor_of(n):
			continue
		var v := n as Node3D
		var k := int(v.get("kind"))
		var wps = v.get("_waypoints")
		if k == Vehicle.Kind.HELI or k == Vehicle.Kind.SHAHED:
			var alt := float(v.get("cruise_height"))
			_check(alt >= 45.0, "%s: повітряна ціль висота >= 45м (%.1f)" % [label, alt])
			continue
		var vp := v.global_position
		_check(_sample_ground_point(level, vp.x, vp.z, true),
				"%s: техніка %s старт сухий (%.1f, %.1f)" % [label, v.name, vp.x, vp.z])
		if wps is Array and not (wps as Array).is_empty():
			var arr := wps as Array
			var closed := not v.is_in_group("escort_convoy")
			var seg_count := arr.size() if closed else arr.size() - 1
			var seg_wet := 0
			for si in range(seg_count):
				var a := arr[si] as Vector3
				var b := arr[(si + 1) % arr.size()] as Vector3
				for step in range(21):
					var pt := a.lerp(b, float(step) / 20.0)
					if not _sample_ground_point(level, pt.x, pt.z, true):
						seg_wet += 1
			_check(seg_wet == 0, "%s: маршрут %s без води (%d точок/seg)" % [label, v.name, arr.size()])

	if sim_frames > 0:
		level.call("_start_mission")
		var sim_wet := 0
		for f in range(sim_frames):
			await tree.physics_frame
			if f % 10 == 0 or f == sim_frames - 1:
				for n in tree.get_nodes_in_group("enemy_infantry"):
					if is_instance_valid(n) and level.is_ancestor_of(n) and not bool(n.get("is_destroyed")):
						var ip := (n as Node3D).global_position
						if not _sample_ground_point(level, ip.x, ip.z, false):
							sim_wet += 1
				for n in tree.get_nodes_in_group("vehicle"):
					if is_instance_valid(n) and level.is_ancestor_of(n) and not bool(n.get("is_destroyed")):
						var k := int(n.get("kind"))
						if k != Vehicle.Kind.HELI and k != Vehicle.Kind.SHAHED:
							var vp := (n as Node3D).global_position
							if not _sample_ground_point(level, vp.x, vp.z, true):
								sim_wet += 1
		_check(sim_wet == 0, "%s: симуляція руху %d кадрів — мокрих=0 (%d)" % [label, sim_frames, sim_wet])


func _test_tutorial() -> void:
	var level := await _spawn_lis(Global.PlayMode.TUTORIAL, 0, 1)
	_verify_drone_spawn(level, "TUTORIAL")
	var fs = level.get("_flight_school")
	_check(fs != null and is_instance_valid(fs), "TUTORIAL: FlightSchool створено")
	if fs != null:
		for key in ["hover_pos", "brake_pos", "landing_pos"]:
			var pt: Vector3 = fs.get(key)
			_check(absf(pt.x) <= 290.0 and absf(pt.z) <= 290.0 and _sample_ground_point(level, pt.x, pt.z, false),
					"TUTORIAL: %s сухий і в межах (%.1f, %.1f)" % [key, pt.x, pt.z])
	await _dispose(level)


func _test_freestyle_and_respawns() -> void:
	var level := await _spawn_lis(Global.PlayMode.TRAINING, 0, 1, false)
	_verify_drone_spawn(level, "FREESTYLE")
	await _verify_units_and_routes(level, "FREESTYLE", 40)
	for cycle in range(1, 4):
		level.call("_on_respawned")
		await get_tree().physics_frame
		_verify_drone_spawn(level, "FREESTYLE respawn #%d" % cycle)
	await _dispose(level)


func _test_combat_training() -> void:
	var level := await _spawn_lis(Global.PlayMode.TRAINING, 0, 1, true)
	for _i in range(6):
		await get_tree().physics_frame
	_verify_drone_spawn(level, "COMBAT_TRAINING")
	var ct = level.get("_combat_training")
	_check(ct != null and is_instance_valid(ct), "COMBAT_TRAINING: інстанційовано")
	if ct != null:
		var tpos: Vector3 = ct.get("target_pos")
		_check(absf(tpos.x) <= 290.0 and absf(tpos.z) <= 290.0 and _sample_ground_point(level, tpos.x, tpos.z, true),
				"COMBAT_TRAINING: танк-ціль сухий (%.1f, %.1f)" % [tpos.x, tpos.z])
	await _dispose(level)


func _test_campaign_mission(mission_id: int, diff: int) -> void:
	var tag := "CAMPAIGN M%d (diff=%d)" % [mission_id, diff]
	var level := await _spawn_lis(Global.PlayMode.COMBAT, 0, mission_id, false, diff)
	_verify_drone_spawn(level, tag)
	var total := int(level.get("_mission_targets_total"))
	_check(total > 0, "%s: цілі створено (%d)" % [tag, total])
	var sim_frames := 120 if (diff == Global.Difficulty.OPERATOR and mission_id in [1, 2]) else 0
	await _verify_units_and_routes(level, tag, sim_frames)
	await _dispose(level)


func _test_special_mission(special_id: int) -> void:
	var tag := "SPECIAL %02d (%s)" % [special_id, Global.get_special_mission_name(special_id)]
	var level := await _spawn_lis(Global.PlayMode.COMBAT, special_id, 1, false, Global.Difficulty.OPERATOR)
	_verify_drone_spawn(level, tag)
	var zones: Array = level.get("_special_zones") if level.get("_special_zones") is Array else []
	for zi in range(zones.size()):
		var zp: Vector3 = zones[zi]["pos"]
		_check(absf(zp.x) <= 290.0 and absf(zp.z) <= 290.0 and _sample_ground_point(level, zp.x, zp.z, false),
				"%s: зона %d суха (%.1f, %.1f)" % [tag, zi + 1, zp.x, zp.z])
	if special_id in [5, 12]:
		_check(int(level.get("_weather")) == 3, "%s: нічне освітлення (_weather=3)" % tag)
	if special_id >= 5 and special_id <= 10:
		var ex: Vector3 = level.get("_special_extract_point")
		_check(_sample_ground_point(level, ex.x, ex.z, false), "%s: точка евакуації суха (%.1f, %.1f)" % [tag, ex.x, ex.z])
	if special_id == 10:
		level.call("_start_mission")
		level.call("_spawn_missile_wave")
		var ms: Array = level.get("_intercept_missiles")
		_check(not ms.is_empty(), "%s: хвиля крилатих ракет запущена (%d)" % [tag, ms.size()])
	if special_id in [2, 11]:
		var convoy := level.get("_special_convoy") as Node3D
		var drone := level.get_node_or_null("Drone") as Node3D
		if convoy != null and drone != null:
			var dist := drone.global_position.distance_to(convoy.global_position)
			_check(dist < 250.0, "%s: дрон в радіусі супроводу (%.1fm)" % [tag, dist])
	var sim_frames := 120 if special_id in [2, 11, 12] else 0
	await _verify_units_and_routes(level, tag, sim_frames)
	await _dispose(level)
