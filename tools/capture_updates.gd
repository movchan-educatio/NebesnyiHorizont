extends Node3D

const ARTIFACT_DIR := "C:/Users/USER_UA/.gemini/antigravity/brain/d3a48383-ba35-4c5d-a092-fbdb2b035535/"

func _ready():
	print("[CaptureUpdates] Starting capture of updated standalone silos, cooling tower, windows, and moving objects...")
	await _capture_industrial()
	await _capture_village()
	await _capture_steppe()
	await _capture_wetlands()
	print("[CaptureUpdates] All updated screenshots captured successfully!")
	get_tree().quit()


func _capture_industrial():
	print("[CaptureUpdates] Loading Industrial map...")
	var scene = load("res://sceneries/BigLevel.tscn").instantiate()
	scene.frontline_map = "industrial"
	add_child(scene)
	
	for i in range(50):
		await get_tree().process_frame

	var cam = Camera3D.new()
	cam.fov = 68.0
	cam.near = 0.05
	cam.far = 4000.0
	add_child(cam)

	# 1. Standalone Factory Silo: galvanized steel PBR with hazard rings, isolated in open apron
	# Silo is at (-165.0, y, -68.0)
	var silo_pos := Vector3(-165.0, 2.0, -68.0)
	cam.global_position = silo_pos + Vector3(18.0, 8.0, 22.0)
	cam.look_at(silo_pos + Vector3(0.0, 9.0, 0.0), Vector3.UP)
	cam.current = true
	for i in range(25):
		await get_tree().process_frame
	_save_shot("shot_silos_standalone.png")

	# 2. Cooling Tower: Hyperboloid concrete shell, clear base (zero trees clipping), open top
	# Tower is at (-72.0, y, -214.0)
	var tower_pos := Vector3(-72.0, 1.8, -214.0)
	cam.global_position = tower_pos + Vector3(28.0, 14.0, 36.0)
	cam.look_at(tower_pos + Vector3(0.0, 15.0, 0.0), Vector3.UP)
	cam.current = true
	for i in range(25):
		await get_tree().process_frame
	_save_shot("shot_cooling_tower_clear.png")

	# 3. Dynamic Moving Tower Crane: 42m mast with 360-deg rotating jib & amber beacon
	var crane = scene.find_child("RotatingTowerCrane", true, false) as Node3D
	if crane != null:
		var cpos = crane.global_position
		cam.global_position = cpos + Vector3(-32.0, 22.0, 36.0)
		cam.look_at(cpos + Vector3(0.0, 22.0, 0.0), Vector3.UP)
		cam.current = true
		for i in range(25):
			await get_tree().process_frame
		_save_shot("shot_moving_crane_industrial.png")

	cam.queue_free()
	scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _capture_village():
	print("[CaptureUpdates] Loading Village map...")
	var scene = load("res://sceneries/BigLevel.tscn").instantiate()
	scene.frontline_map = "village"
	add_child(scene)
	
	for i in range(50):
		await get_tree().process_frame

	var cam = Camera3D.new()
	cam.fov = 65.0
	cam.near = 0.05
	cam.far = 4000.0
	add_child(cam)

	# 4. Village Cottages & Buildings with Large Open Windows & Architectural Frames
	# Look directly at the front of a cottage from close distance
	var cottage = scene.find_child("cottage_a", true, false) as Node3D
	if cottage != null:
		var cpos = cottage.global_position
		# Stand in front of the window facade
		cam.global_position = cpos + Vector3(-5.5, 2.6, 6.5)
		cam.look_at(cpos + Vector3(0.0, 2.2, 0.0), Vector3.UP)
	else:
		cam.global_position = Vector3(48.0, 4.2, 68.0)
		cam.look_at(Vector3(42.0, 3.0, 58.0), Vector3.UP)
	cam.current = true
	for i in range(25):
		await get_tree().process_frame
	_save_shot("shot_buildings_large_windows.png")

	# 5. Dynamic Moving Windmill: 4 rotating sails on the bluff overlooking the village
	var mill = scene.find_child("MovingWindmill", true, false) as Node3D
	if mill != null:
		var mpos = mill.global_position
		cam.global_position = mpos + Vector3(-16.0, 11.0, 18.0)
		cam.look_at(mpos + Vector3(0.0, 10.0, 0.0), Vector3.UP)
		cam.current = true
		for i in range(25):
			await get_tree().process_frame
		_save_shot("shot_moving_windmill_village.png")

	cam.queue_free()
	scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _capture_steppe():
	print("[CaptureUpdates] Loading Steppe map...")
	var scene = load("res://sceneries/BigLevel.tscn").instantiate()
	scene.frontline_map = "steppe"
	add_child(scene)
	
	for i in range(50):
		await get_tree().process_frame

	var cam = Camera3D.new()
	cam.fov = 68.0
	cam.near = 0.05
	cam.far = 4000.0
	add_child(cam)

	# 6. Dynamic Military Early Warning Radar Station
	var radar = scene.find_child("MovingRadar", true, false) as Node3D
	if radar != null:
		var rpos = radar.global_position
		cam.global_position = rpos + Vector3(-15.0, 11.0, 17.0)
		cam.look_at(rpos + Vector3(0.0, 8.5, 0.0), Vector3.UP)
		cam.current = true
		for i in range(25):
			await get_tree().process_frame
		_save_shot("shot_moving_radar_steppe.png")

	# 6b. Standalone Farm Grain Silo: Isolated in open paddock, completely clear of the road and trees
	# Silo is at (106.0, y, 152.0)
	var farm_silo_pos := Vector3(106.0, 1.8, 152.0)
	cam.global_position = farm_silo_pos + Vector3(-20.0, 10.0, 22.0)
	cam.look_at(farm_silo_pos + Vector3(0.0, 9.0, 0.0), Vector3.UP)
	cam.current = true
	for i in range(25):
		await get_tree().process_frame
	_save_shot("shot_farm_silo_standalone.png")

	cam.queue_free()
	scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _capture_wetlands():
	print("[CaptureUpdates] Loading Wetlands map...")
	var scene = load("res://sceneries/BigLevel.tscn").instantiate()
	scene.frontline_map = "wetlands"
	add_child(scene)
	
	for i in range(50):
		await get_tree().process_frame

	var cam = Camera3D.new()
	cam.fov = 65.0
	cam.near = 0.05
	cam.far = 4000.0
	add_child(cam)

	# 7. Dynamic Combat River Patrol Boat cruising the channel
	var boat = scene.find_child("MovingPatrolBoat", true, false) as Node3D
	if boat != null:
		var bpos = boat.global_position
		cam.global_position = bpos + Vector3(-12.0, 5.0, 14.0)
		cam.look_at(bpos + Vector3(0.0, 1.5, 0.0), Vector3.UP)
		cam.current = true
		for i in range(25):
			await get_tree().process_frame
		_save_shot("shot_moving_boat_wetlands.png")
	else:
		print("[CaptureUpdates] Warning: MovingPatrolBoat not found on wetlands")

	cam.queue_free()
	scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _save_shot(filename: String) -> void:
	var img = get_viewport().get_texture().get_image()
	if img != null:
		var full_path = ARTIFACT_DIR + filename
		var err = img.save_png(full_path)
		print("[CaptureUpdates] Saved ", filename, " err=", err)
	else:
		push_error("[CaptureUpdates] Failed to grab image for " + filename)
