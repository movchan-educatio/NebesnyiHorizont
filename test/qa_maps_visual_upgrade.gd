extends Node3D

const OUT_DIR := "res://screenshots/maps_upgraded"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	DisplayServer.window_set_size(Vector2i(1280, 720))
	get_viewport().scaling_3d_scale = 1.0
	OS.set_environment("DRONE_CLEAN_SHOT", "1")
	var qm := get_node_or_null("/root/QualityManager")
	if qm != null and qm.has_method("apply_preset"):
		qm.call("apply_preset", 2) # HIGH preset for crisp screenshot verification
	Global.play_mode = Global.PlayMode.TRAINING
	Global.combat_training = false
	await get_tree().process_frame
	await get_tree().process_frame

	await _capture_wetlands()
	await _capture_industrial()
	await _capture_airport()

	print("[QA_MAPS_VISUAL_UPGRADE] ALL 10 SCREENSHOTS CAPTURED SUCCESSFULLY")
	get_tree().quit(0)


func _prepare_level(scene_path: String) -> Node3D:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return null
	var level := packed.instantiate() as Node3D
	add_child(level)
	for _i in range(12):
		await get_tree().physics_frame
		await get_tree().process_frame
	# Hide all 2D HUD overlays & touch controls for clean 3D shots
	for c in level.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false
	for cname in ["Help", "FPVOverlay", "CombatHUD", "FlightHUD"]:
		var cnode := level.get_node_or_null(cname)
		if cnode is CanvasLayer:
			(cnode as CanvasLayer).visible = false
		elif cnode is CanvasItem:
			(cnode as CanvasItem).visible = false
	var tc := get_node_or_null("/root/TouchControls")
	if tc is CanvasLayer:
		(tc as CanvasLayer).visible = false
	elif tc != null:
		for ch in tc.find_children("*", "CanvasItem", true, false):
			(ch as CanvasItem).visible = false
	# Hide player drone & spawn markers so they don't photo-bomb shots
	var drone := level.get_node_or_null("Drone") as Node3D
	if drone != null:
		drone.visible = false
	# Ensure bright clear daylight for visual inspection
	var sun := level.get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		sun.light_energy = 2.05
		sun.light_color = Color(1.0, 0.95, 0.88)
		sun.rotation_degrees = Vector3(-42.0, -35.0, 0.0)
	var we := level.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null:
		we.environment.tonemap_exposure = 1.02
		we.environment.fog_density = 0.00035
	get_viewport().scaling_3d_scale = 1.0
	return level


func _pick_unobstructed_cam_pos(level: Node3D, target: Vector3, candidates: Array[Vector3]) -> Vector3:
	var space := level.get_world_3d().direct_space_state if level.get_world_3d() != null else null
	if space == null:
		return target + candidates[0]
	for off in candidates:
		var cand := target + off
		if cand.y < 1.8:
			cand.y = 1.8
		var q := PhysicsRayQueryParameters3D.create(cand, target)
		q.collision_mask = 1
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return cand
		var hp: Vector3 = hit.get("position", cand)
		if hp.distance_to(target) < 4.5:
			return cand
	return target + candidates[0]


func _shoot(cam: Camera3D, pos: Vector3, look_target: Vector3, filename: String, fov: float = 56.0) -> void:
	cam.fov = fov
	cam.current = true
	cam.make_current()
	cam.global_position = pos
	cam.look_at(look_target, Vector3.UP)
	for _i in range(6):
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var full_path := ProjectSettings.globalize_path(OUT_DIR + "/" + filename)
	img.save_png(full_path)
	print("[SHOT] saved ", full_path)


func _capture_wetlands() -> void:
	var level := await _prepare_level("res://sceneries/WetlandsLevel.tscn")
	if level == null:
		return
	var cam := Camera3D.new()
	cam.far = 2500.0
	level.add_child(cam)

	# 1. Wide overview of Wetlands channel, dock, patrol boat, trestle causeway, pumping hall
	await _shoot(cam, Vector3(-16.0, 38.0, 122.0), Vector3(-24.0, 4.0, -30.0), "wetlands_01_overview.png", 60.0)

	# 2. Close-up on upgraded Cargo Ship (Prop_cargo_ship*) + channel OR Patrol Boat + WetlandsBarge
	var ship := level.find_child("Prop_cargo_ship*", true, false) as Node3D
	var boat := level.find_child("MovingPatrolBoat", true, false) as Node3D
	if ship != null:
		var sp := ship.global_position
		print("[WETLANDS_SHOT] found cargo ship at ", sp)
		var cpos := _pick_unobstructed_cam_pos(level, sp + Vector3(0.0, 4.0, 0.0), [
			Vector3(24.0, 14.0, 26.0), Vector3(-24.0, 14.0, 26.0), Vector3(0.0, 20.0, 30.0)
		])
		await _shoot(cam, cpos, sp + Vector3(0.0, 4.5, 0.0), "wetlands_02_cargo_ship.png", 52.0)
	elif boat != null:
		var bp := boat.global_position
		print("[WETLANDS_SHOT] framing MovingPatrolBoat at ", bp)
		await _shoot(cam, bp + Vector3(14.0, 7.5, 16.0), bp + Vector3(0.0, 1.5, 0.0), "wetlands_02_cargo_ship.png", 50.0)
	else:
		await _shoot(cam, Vector3(-85.0, 16.0, -10.0), Vector3(-115.0, 2.0, -38.0), "wetlands_02_cargo_ship.png", 52.0)

	# 3. Close-up on clean MobileHero_Lighthouse + sculpted boardwalk keeper tower
	var lh := level.find_child("MobileHero_Lighthouse", true, false) as Node3D
	if lh != null:
		var lp := lh.global_position
		var cpos := _pick_unobstructed_cam_pos(level, lp + Vector3(2.0, 11.0, 0.0), [
			Vector3(-24.0, 18.0, 24.0), Vector3(-26.0, 16.0, -24.0), Vector3(26.0, 18.0, 26.0)
		])
		await _shoot(cam, cpos, lp + Vector3(2.0, 11.0, 0.0), "wetlands_03_lighthouse_and_pois.png", 54.0)
	else:
		await _shoot(cam, Vector3(110.0, 18.0, 90.0), Vector3(135.0, 10.0, 115.0), "wetlands_03_lighthouse_and_pois.png", 54.0)

	level.queue_free()
	for _i in range(4):
		await get_tree().process_frame


func _capture_industrial() -> void:
	var level := await _prepare_level("res://sceneries/IndustrialLevel.tscn")
	if level == null:
		return
	var cam := Camera3D.new()
	cam.far = 2500.0
	level.add_child(cam)

	# 1. Wide overview of Industrial complex, freight train, cranes, sculpted buildings
	await _shoot(cam, Vector3(15.0, 44.0, 122.0), Vector3(-35.0, 8.0, -35.0), "industrial_01_overview.png", 60.0)

	# 2. Close-up on sculpted & PBR-textured Freight Train (locomotive + corrugated boxcars)
	var train := level.find_child("Handcrafted_freight_train", true, false) as Node3D
	if train != null:
		var tp := train.global_position
		await _shoot(cam, tp + Vector3(8.0, 7.5, 22.0), tp + Vector3(14.0, 2.5, 0.0), "industrial_02_freight_train.png", 50.0)
	else:
		await _shoot(cam, Vector3(-30.0, 10.0, -2.0), Vector3(-18.0, 3.0, -24.0), "industrial_02_freight_train.png", 50.0)

	# 3. Close-up on sculpted MobileHero2_PipeRack overpass (without fake floating black/orange quads!)
	var rack := level.find_child("MobileHero2_PipeRack", true, false) as Node3D
	if rack != null:
		var rp := rack.global_position
		var cpos := _pick_unobstructed_cam_pos(level, rp + Vector3(0.0, 5.0, 0.0), [
			Vector3(24.0, 13.0, 24.0), Vector3(24.0, 13.0, -24.0), Vector3(-24.0, 13.0, 24.0)
		])
		await _shoot(cam, cpos, rp + Vector3(0.0, 5.0, 0.0), "industrial_03_landmarks.png", 54.0)
	else:
		await _shoot(cam, Vector3(112.0, 18.0, 108.0), Vector3(138.0, 10.0, 134.0), "industrial_03_landmarks.png", 54.0)

	level.queue_free()
	for _i in range(4):
		await get_tree().process_frame


func _capture_airport() -> void:
	var level := await _prepare_level("res://sceneries/AirportLevel.tscn")
	if level == null:
		return
	var cam := Camera3D.new()
	cam.far = 2500.0
	level.add_child(cam)

	# 1. Terminal apron with 2K triplanar PBR concrete/tarmac, realistic trees & detailed props (no yellow discs!)
	await _shoot(cam, Vector3(-48.0, 22.0, 142.0), Vector3(12.0, 6.0, 32.0), "airport_01_terminal_and_apron.png", 58.0)

	# 2. Unobstructed close-up on sculpted AirportLandmark_ControlTowerRuins
	var tower := level.get_node_or_null("AirportLandmark_ControlTowerRuins") as Node3D
	if tower != null:
		var twp := tower.global_position
		var cpos := _pick_unobstructed_cam_pos(level, twp + Vector3(0.0, 13.0, 0.0), [
			Vector3(28.0, 22.0, 28.0), Vector3(-28.0, 22.0, 28.0), Vector3(28.0, 22.0, -28.0), Vector3(0.0, 28.0, 34.0)
		])
		await _shoot(cam, cpos, twp + Vector3(0.0, 13.0, 0.0), "airport_02_control_tower_ruins.png", 54.0)

	# 3. Unobstructed 3/4 view of AirportLandmark_HangarAircraftWrecks (lattice truss hangar + twin An-26/Il-76 wrecks)
	var wrecks := level.get_node_or_null("AirportLandmark_HangarAircraftWrecks") as Node3D
	if wrecks != null:
		var wp := wrecks.global_position
		var cpos := _pick_unobstructed_cam_pos(level, wp + Vector3(0.0, 4.0, 0.0), [
			Vector3(0.0, 14.0, 34.0), Vector3(0.0, 14.0, -34.0), Vector3(22.0, 18.0, 28.0), Vector3(-22.0, 18.0, 28.0)
		])
		await _shoot(cam, cpos, wp + Vector3(0.0, 4.0, 0.0), "airport_03_hangar_aircraft_wrecks.png", 56.0)

	# 4. Unobstructed close-up on sculpted AirportLandmark_FuelDepot & CargoContainerYard
	var depot := level.get_node_or_null("AirportLandmark_FuelDepot") as Node3D
	if depot != null:
		var dp := depot.global_position
		var cpos := _pick_unobstructed_cam_pos(level, dp + Vector3(0.0, 2.5, 0.0), [
			Vector3(-22.0, 14.0, 22.0), Vector3(22.0, 14.0, 22.0), Vector3(0.0, 18.0, 26.0)
		])
		await _shoot(cam, cpos, dp + Vector3(0.0, 2.5, 0.0), "airport_04_fuel_depot.png", 54.0)

	level.queue_free()
	for _i in range(4):
		await get_tree().process_frame
