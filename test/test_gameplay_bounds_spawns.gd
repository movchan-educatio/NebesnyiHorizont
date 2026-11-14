extends Node3D

## Comprehensive regression suite covering:
## 1. Helicopter / Shahed / SAM / BMP / APC / PatrolBoat / Infantry map & water bounds.
## 2. Player-to-enemy minimum spawn clearance across all 5 maps, TAC-01..04,
##    Special Ops 1..6, MEDIUM bonus frontline targets, and reinforcement waves.
## 3. Tutorial (FlightSchool) LandingPad collider, surface height, dry brake zone,
##    corridor clearance, and landing/disarm graduation.

const FT = preload("res://scripts/util/frontline_terrain.gd")
const MIN_GROUND_DIST := 75.0
const MIN_AIR_DIST := 95.0

var _failures := 0


func _ready() -> void:
	OS.set_environment("MOBILE_UI", "1")
	OS.set_environment("DRONE_QUALITY", "medium")
	call_deferred("_run")


func _check(ok: bool, msg: String) -> void:
	print("[BOUNDS_SPAWN_QA] ", "PASS " if ok else "FAIL ", msg)
	if not ok:
		_failures += 1


func _neutralize_self_colliders(vehicle: Vehicle) -> void:
	for body in vehicle.find_children("*", "StaticBody3D", true, false):
		(body as StaticBody3D).collision_layer = 0
		(body as StaticBody3D).collision_mask = 0


func _load_level(scene_path: String, play_mode: int, tac: int, spec: int,
		set_current: bool = true) -> Node3D:
	Global.chain_briefing_pending = false
	Global.drone_preset = 0
	Global.play_mode = play_mode
	Global.combat_mission = tac
	Global.special_mission = spec
	var packed := load(scene_path) as PackedScene
	if packed == null:
		_check(false, "load scene " + scene_path)
		return null
	var lvl := packed.instantiate() as Node3D
	add_child(lvl)
	if not set_current:
		get_tree().current_scene = null
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	get_tree().paused = false
	return lvl


func _free_level(lvl: Node) -> void:
	if lvl != null and is_instance_valid(lvl):
		lvl.queue_free()
	if get_tree().current_scene == null:
		get_tree().current_scene = self
	await get_tree().process_frame
	await get_tree().process_frame


func _within_sq_xz(p: Vector3, lim: float) -> bool:
	return absf(p.x) <= lim and absf(p.z) <= lim


func _test_vehicle_and_infantry_bounds() -> void:
	print("--- Phase 1: Vehicle, Boat & Infantry Bounds (Village + Valley) ---")
	var lvl := await _load_level("res://sceneries/VillageLevel.tscn",
			Global.PlayMode.TRAINING, 1, 0, false)
	_check(lvl != null and String(lvl.get("frontline_map")) == "village",
			"VillageLevel instantiated with current_scene == null")
	if lvl == null:
		return

	var drone := lvl.get_node_or_null("Drone") as Node3D
	_check(drone != null, "VillageLevel has Drone node")
	if drone == null:
		await _free_level(lvl)
		return
	var fc = drone.get("flight_controller")
	if fc != null and fc.has_method("set_armed"):
		fc.set_armed(true)

	# 1a. HELI waypoint clamping + edge mobile orbit deflection (never OOB, never pinned)
	var heli := Vehicle.new()
	heli.kind = Vehicle.Kind.HELI
	heli.hostile = true
	heli.fire_range = 160.0
	heli.move_speed = 18.0
	heli.cruise_height = 24.0
	lvl.add_child(heli)
	_neutralize_self_colliders(heli)
	heli._drone = drone
	heli.set_waypoints([Vector3(310.0, 0.0, 310.0), Vector3(260.0, 0.0, -290.0), Vector3(-280.0, 0.0, 270.0)])
	var wp_clamped := true
	for i in range(heli._waypoints.size()):
		if not _within_sq_xz(heli._waypoints[i], Vehicle.VEHICLE_AIR_BOUND + 0.01):
			wp_clamped = false
	_check(wp_clamped, "HELI set_waypoints clamped within +-%.1fm" % Vehicle.VEHICLE_AIR_BOUND)

	var ground_y := float(lvl.call("_find_ground_y", 156.0, 156.0))
	heli.global_position = Vector3(156.0, ground_y + 24.0, 156.0)
	drone.global_position = Vector3(112.0, ground_y + 24.0, 112.0)
	var heli_in_bounds := true
	var heli_pos_early := Vector3.ZERO
	var heli_pos_late := Vector3.ZERO
	for step_i in range(150):
		heli._physics_process(1.0 / 30.0)
		if not _within_sq_xz(heli.global_position, Vehicle.VEHICLE_AIR_BOUND + 0.05):
			heli_in_bounds = false
			break
		if step_i == 60:
			heli_pos_early = heli.global_position
		elif step_i == 149:
			heli_pos_late = heli.global_position
	_check(heli_in_bounds, "HELI mobile orbit stays within +-%.1fm for 5s sim" % Vehicle.VEHICLE_AIR_BOUND)
	_check(Vector2(heli_pos_early.x - heli_pos_late.x,
			heli_pos_early.z - heli_pos_late.z).length() > 0.5,
			"HELI deflects tangentially near perimeter instead of pinning on wall")

	# 1b. SHAHED mobile intercept chasing an OOB armed drone
	var shahed := Vehicle.new()
	shahed.kind = Vehicle.Kind.SHAHED
	shahed.hostile = true
	shahed.fire_range = 100.0
	shahed.move_speed = 26.0
	shahed.cruise_height = 20.0
	lvl.add_child(shahed)
	_neutralize_self_colliders(shahed)
	shahed._drone = drone
	shahed.set_waypoints([Vector3(165.0, 0.0, 165.0), Vector3(-120.0, 0.0, -120.0)])
	shahed.global_position = Vector3(152.0, ground_y + 20.0, 152.0)
	drone.global_position = Vector3(245.0, ground_y + 20.0, 245.0)
	var shahed_ok := true
	for _s in range(120):
		shahed._physics_process(1.0 / 30.0)
		if not _within_sq_xz(shahed.global_position, Vehicle.VEHICLE_AIR_BOUND + 0.05):
			shahed_ok = false
			break
	_check(shahed_ok, "SHAHED intercepting OOB drone stays within +-%.1fm" % Vehicle.VEHICLE_AIR_BOUND)

	# 1c. SAM / BMP / APC retreat stays within ground bound & out of water
	var wl := FT.water_level("village")
	var shore_dry := Vector2.ZERO
	var shore_wet := Vector2.ZERO
	var found_shore := false
	for gx in range(-120, 121, 8):
		for gz in range(-120, 121, 8):
			var h := FT.height_at("village", float(gx), float(gz))
			if h < wl - 0.15:
				for ox in [-10.0, 10.0, 0.0]:
					for oz in [-10.0, 10.0, 0.0]:
						if ox == 0.0 and oz == 0.0:
							continue
						var dh := FT.height_at("village", float(gx) + ox, float(gz) + oz)
						if dh >= wl + 0.55 and absf(float(gx) + ox) < 140.0 and absf(float(gz) + oz) < 140.0:
							shore_wet = Vector2(float(gx), float(gz))
							shore_dry = Vector2(float(gx) + ox, float(gz) + oz)
							found_shore = true
							break
					if found_shore:
						break
			if found_shore:
				break
		if found_shore:
			break
	_check(found_shore, "Located dry shoreline point adjacent to village river")

	for ground_kind in [Vehicle.Kind.SAM, Vehicle.Kind.BMP, Vehicle.Kind.APC]:
		var unit := Vehicle.new()
		unit.kind = ground_kind
		unit.hostile = true
		unit.fire_range = 140.0
		unit.move_speed = 11.0
		lvl.add_child(unit)
		_neutralize_self_colliders(unit)
		unit._drone = drone
		unit.global_position = Vector3(149.5, FT.height_at("village", 149.5, 149.5), 149.5)
		drone.global_position = Vector3(128.0, unit.global_position.y + 4.0, 128.0)
		var g_in_bounds := true
		for _t in range(45):
			unit._physics_process(1.0 / 30.0)
			if not _within_sq_xz(unit.global_position, Vehicle.VEHICLE_GROUND_BOUND + 0.05):
				g_in_bounds = false
				break
		_check(g_in_bounds, "Vehicle kind=%d edge retreat stays within +-%.1fm" % [ground_kind, Vehicle.VEHICLE_GROUND_BOUND])

		if found_shore:
			var push_from := shore_dry + (shore_dry - shore_wet).normalized() * 14.0
			unit.global_position = Vector3(shore_dry.x, FT.height_at("village", shore_dry.x, shore_dry.y), shore_dry.y)
			drone.global_position = Vector3(push_from.x, unit.global_position.y + 3.0, push_from.y)
			var stayed_dry := true
			for _w in range(45):
				unit._physics_process(1.0 / 30.0)
				if FT.height_at("village", unit.global_position.x, unit.global_position.z) < wl + 0.25:
					stayed_dry = false
					break
			_check(stayed_dry, "Vehicle kind=%d retreat stays out of river hazard" % ground_kind)

	# 1d. EnemyRifleman & ChaosSoldier bounds + water guard + null current_scene safety
	var rifleman := EnemyRifleman.new()
	lvl.add_child(rifleman)
	rifleman.global_position = Vector3(205.0, 3.0, -205.0)
	for _r in range(4):
		rifleman._physics_process(1.0 / 30.0)
	_check(_within_sq_xz(rifleman.global_position, EnemyRifleman.INFANTRY_MAP_BOUND + 0.05),
			"EnemyRifleman clamped inside +-%.1fm (got %.1f, %.1f)" % [
				EnemyRifleman.INFANTRY_MAP_BOUND, rifleman.global_position.x, rifleman.global_position.z])
	rifleman.global_position = Vector3(EnemyRifleman.INFANTRY_MAP_BOUND - 0.3, 1.0, 0.0)
	_check(not bool(rifleman.call("_can_step", Vector3(1.0, 0.0, 0.0), 1.0)),
			"EnemyRifleman _can_step rejects OOB XZ")
	if found_shore:
		rifleman.global_position = Vector3(
				shore_dry.x, FT.height_at("village", shore_dry.x, shore_dry.y), shore_dry.y)
		var to_wet := Vector3(shore_wet.x - shore_dry.x, 0.0, shore_wet.y - shore_dry.y)
		_check(not bool(rifleman.call("_can_step", to_wet.normalized(),
				maxf(0.1, to_wet.length() - 0.55))),
				"EnemyRifleman _can_step rejects water cell")

	var chaos := ChaosSoldier.new()
	lvl.add_child(chaos)
	chaos.global_position = Vector3(-198.0, 3.0, 198.0)
	chaos.call("_snap_to_ground")
	_check(_within_sq_xz(chaos.global_position, EnemyRifleman.INFANTRY_MAP_BOUND + 0.05),
			"ChaosSoldier clamped inside +-%.1fm" % EnemyRifleman.INFANTRY_MAP_BOUND)

	# 1e. MovingPatrolBoat waypoint clamp
	var boat := MovingPatrolBoat.create_patrol_boat(
			[Vector3(-250.0, 0.0, -240.0), Vector3(260.0, 0.0, 230.0)] as Array[Vector3], 0.0)
	var boat_ok := true
	for bwp in boat.waypoints:
		if not _within_sq_xz(bwp, 178.01):
			boat_ok = false
	_check(boat_ok, "MovingPatrolBoat waypoints clamped within +-178m")
	boat.free()

	await _free_level(lvl)

	# 1f. Valley (frontline_map == "") vehicle bounds verification
	var valley := await _load_level("res://sceneries/BigLevel.tscn",
			Global.PlayMode.TRAINING, 1, 0, true)
	if valley != null:
		var v_heli := Vehicle.new()
		v_heli.kind = Vehicle.Kind.HELI
		v_heli.hostile = true
		v_heli.cruise_height = 22.0
		valley.add_child(v_heli)
		v_heli.set_waypoints([Vector3(160.0, 0.0, 160.0), Vector3(-160.0, 0.0, -160.0)])
		v_heli.global_position = Vector3(210.0, 30.0, -210.0)
		v_heli._physics_process(1.0 / 30.0)
		_check(_within_sq_xz(v_heli.global_position, Vehicle.VEHICLE_AIR_BOUND + 0.05),
				"Valley HELI enforced within +-%.1fm" % Vehicle.VEHICLE_AIR_BOUND)
		await _free_level(valley)


func _audit_spawned_enemies(lvl: Node3D, label: String, map_name: String) -> void:
	var drone := lvl.get_node_or_null("Drone") as Node3D
	_check(drone != null, "%s has Drone" % label)
	if drone == null:
		return
	var dp := Vector2(drone.global_position.x, drone.global_position.z)
	_check(_within_sq_xz(drone.global_position, 178.0),
			"%s Drone spawn within +-178m (%.1f, %.1f)" % [label, dp.x, dp.y])

	var wl := FT.water_level(map_name) if not map_name.is_empty() else -999.0
	var min_seen_ground := 9999.0
	var min_seen_air := 9999.0
	var vehs: Array = lvl.get("_vehicles")
	for uv in vehs:
		var v := uv as Vehicle
		if v == null or not is_instance_valid(v):
			continue
		var is_air := (v.kind == Vehicle.Kind.HELI or v.kind == Vehicle.Kind.SHAHED)
		var v_lim := Vehicle.VEHICLE_AIR_BOUND if is_air else Vehicle.VEHICLE_GROUND_BOUND
		_check(_within_sq_xz(v.global_position, v_lim + 0.05),
				"%s vehicle kind=%d within +-%.1fm (%.1f, %.1f)" % [
					label, v.kind, v_lim, v.global_position.x, v.global_position.z])
		if v.hostile:
			var dist := dp.distance_to(Vector2(v.global_position.x, v.global_position.z))
			var req := MIN_AIR_DIST if is_air else MIN_GROUND_DIST
			if is_air:
				min_seen_air = minf(min_seen_air, dist)
			else:
				min_seen_ground = minf(min_seen_ground, dist)
			_check(dist >= req - 0.1,
					"%s hostile vehicle kind=%d distance %.1fm >= %.1fm" % [label, v.kind, dist, req])
		if not is_air and not map_name.is_empty() and wl > -100.0:
			var vh := FT.height_at(map_name, v.global_position.x, v.global_position.z)
			_check(vh >= wl + 0.30,
					"%s ground vehicle dry (h=%.2f wl=%.2f)" % [label, vh, wl])

	var infs: Array = lvl.get("_infantry_units")
	for ui in infs:
		var inf := ui as Node3D
		if inf == null or not is_instance_valid(inf):
			continue
		_check(_within_sq_xz(inf.global_position, EnemyRifleman.INFANTRY_MAP_BOUND + 0.05),
				"%s infantry within +-%.1fm (%.1f, %.1f)" % [
					label, EnemyRifleman.INFANTRY_MAP_BOUND, inf.global_position.x, inf.global_position.z])
		var dist_i := dp.distance_to(Vector2(inf.global_position.x, inf.global_position.z))
		min_seen_ground = minf(min_seen_ground, dist_i)
		_check(dist_i >= MIN_GROUND_DIST - 0.1,
				"%s enemy infantry distance %.1fm >= %.1fm" % [label, dist_i, MIN_GROUND_DIST])
		if not map_name.is_empty() and wl > -100.0:
			var ih := FT.height_at(map_name, inf.global_position.x, inf.global_position.z)
			_check(ih >= wl + 0.30,
					"%s infantry dry (h=%.2f wl=%.2f)" % [label, ih, wl])


func _test_spawn_distances_and_reinforcements() -> void:
	print("--- Phase 2: Spawn Distances & Bounds (5 Maps x TAC-1..4 + SpecOps + Reinforcements) ---")
	var maps := [
		["res://sceneries/SteppeLevel.tscn", "steppe"],
		["res://sceneries/VillageLevel.tscn", "village"],
		["res://sceneries/IndustrialLevel.tscn", "industrial"],
		["res://sceneries/WetlandsLevel.tscn", "wetlands"],
		["res://sceneries/BigLevel.tscn", ""],
	]
	for pair in maps:
		var scene_path := String(pair[0])
		var map_name := String(pair[1])
		var m_label := map_name if not map_name.is_empty() else "valley"
		for tac in [1, 2, 3, 4]:
			var lvl := await _load_level(scene_path, Global.PlayMode.COMBAT, tac, 0, true)
			if lvl == null:
				continue
			var tag := "%s TAC-%02d" % [m_label, tac]
			_audit_spawned_enemies(lvl, tag, map_name)
			if tac == 1:
				lvl.call("_spawn_reinforcement_wave")
				_audit_spawned_enemies(lvl, tag + " +ReinfWave", map_name)
			await _free_level(lvl)

	# Also sweep all 6 Special Ops missions on village and industrial
	for sp_pair in [["res://sceneries/VillageLevel.tscn", "village"],
			["res://sceneries/IndustrialLevel.tscn", "industrial"]]:
		var s_path := String(sp_pair[0])
		var s_map := String(sp_pair[1])
		for spec_id in [1, 2, 3, 4, 5, 6]:
			var slvl := await _load_level(s_path, Global.PlayMode.COMBAT, 1, spec_id, true)
			if slvl == null:
				continue
			_audit_spawned_enemies(slvl, "%s SPEC-%02d" % [s_map, spec_id], s_map)
			await _free_level(slvl)


func _test_tutorial_landing_pad() -> void:
	print("--- Phase 3: Tutorial LandingPad Surface, Colliders & Graduation ---")
	var tut_maps := [
		["res://sceneries/VillageLevel.tscn", "village"],
		["res://sceneries/SteppeLevel.tscn", "steppe"],
		["res://sceneries/IndustrialLevel.tscn", "industrial"],
		["res://sceneries/WetlandsLevel.tscn", "wetlands"],
		["res://sceneries/BigLevel.tscn", ""],
	]
	for pair in tut_maps:
		var scene_path := String(pair[0])
		var map_name := String(pair[1])
		var m_label := map_name if not map_name.is_empty() else "valley"
		var lvl := await _load_level(scene_path, Global.PlayMode.TUTORIAL, 1, 0, true)
		if lvl == null:
			continue

		var school = lvl.get("_flight_school")
		_check(school != null, "%s Tutorial FlightSchool initialized" % m_label)
		if school == null:
			await _free_level(lvl)
			continue

		var drone := lvl.get_node_or_null("Drone") as Node3D
		var pad := lvl.find_child("LandingPad", true, false) as Node3D
		var col := pad.find_child("LandingPadCollider", true, false) as StaticBody3D if pad != null else null
		_check(pad != null and col != null,
				"%s Tutorial LandingPad & LandingPadCollider present" % m_label)

		var lpos: Vector3 = school.landing_pos
		var bpos: Vector3 = school.brake_pos
		if not map_name.is_empty():
			var wl := FT.water_level(map_name)
			if wl > -100.0:
				_check(lpos.y >= wl + 0.30,
						"%s Tutorial landing_pos above water (y=%.2f wl=%.2f)" % [m_label, lpos.y, wl])
				_check(bpos.y >= wl + 0.30,
						"%s Tutorial brake_pos above water (y=%.2f wl=%.2f)" % [m_label, bpos.y, wl])

		# 3x3 downward physics raycasts across LandingPad footprint (-2.4..+2.4 m):
		# pad surface must be solid and NO terrain mound/ridge/silo may poke through it.
		var space := lvl.get_world_3d().direct_space_state
		var excl: Array[RID] = []
		if drone is CollisionObject3D:
			excl.append((drone as CollisionObject3D).get_rid())
		var pad_surface_ok := true
		var bad_detail := ""
		for ox in [-2.4, 0.0, 2.4]:
			for oz in [-2.4, 0.0, 2.4]:
				var px := lpos.x + float(ox)
				var pz := lpos.z + float(oz)
				var q := PhysicsRayQueryParameters3D.create(
						Vector3(px, lpos.y + 4.0, pz), Vector3(px, lpos.y - 3.5, pz))
				q.collision_mask = 1
				q.exclude = excl
				var hit := space.intersect_ray(q)
				if hit.is_empty():
					pad_surface_ok = false
					bad_detail = "miss at (%.1f, %.1f)" % [px, pz]
					break
				var hy := (hit["position"] as Vector3).y
				if hy > lpos.y + 0.16 or hy < lpos.y - 0.35:
					pad_surface_ok = false
					bad_detail = "hit y=%.2f vs pad=%.2f at (%.1f, %.1f)" % [hy, lpos.y, px, pz]
					break
			if not pad_surface_ok:
				break
		_check(pad_surface_ok, "%s Tutorial LandingPad clear & solid 3x3 (%s)" % [
			m_label, "ok" if bad_detail.is_empty() else bad_detail])

		# End-to-end landing graduation check on default tutorial map (village) and valley
		if m_label == "village" or m_label == "valley":
			if drone != null:
				school.current_step = school.Step.LANDING
				drone.global_position = lpos + Vector3(0.3, 0.25, -0.3)
				if drone is RigidBody3D:
					(drone as RigidBody3D).linear_velocity = Vector3.ZERO
				var dfc = drone.get("flight_controller")
				if dfc != null and dfc.has_method("set_armed"):
					dfc.set_armed(false)
				school.update_flight_school(0.05)
				_check(school.current_step == school.Step.COMPLETED,
						"%s Tutorial completes cleanly upon landing on LandingPad (step=%d)" % [
							m_label, int(school.current_step)])

		await _free_level(lvl)


func _run() -> void:
	await _test_vehicle_and_infantry_bounds()
	await _test_spawn_distances_and_reinforcements()
	await _test_tutorial_landing_pad()
	if _failures == 0:
		print("=== RESULT: BOUNDS, SPAWNS & TUTORIAL QA PASS (0 failures) ===")
		get_tree().quit(0)
	else:
		printerr("=== RESULT: BOUNDS, SPAWNS & TUTORIAL QA FAIL (%d failures) ===" % _failures)
		get_tree().quit(1)
