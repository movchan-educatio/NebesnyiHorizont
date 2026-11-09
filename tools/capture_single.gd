extends Node3D

const ARTIFACT_DIR := "C:/Users/USER_UA/.gemini/antigravity/brain/d3a48383-ba35-4c5d-a092-fbdb2b035535/"

func _ready():
	var args := OS.get_cmdline_user_args()
	var target_map := "wetlands"
	for a in args:
		if a.begins_with("--map="):
			target_map = a.trim_prefix("--map=")
	print("[CaptureSingle] Target map: ", target_map)
	await _capture_map(target_map)
	print("[CaptureSingle] Completed map: ", target_map)
	get_tree().quit()


func _capture_map(map_name: String) -> void:
	var scene = load("res://sceneries/BigLevel.tscn").instantiate()
	scene.frontline_map = map_name
	add_child(scene)
	
	for i in range(45):
		await get_tree().process_frame

	# Ensure no other cameras override our capture camera
	for c in scene.find_children("*", "Camera3D", true, false):
		(c as Camera3D).current = false

	var cam = Camera3D.new()
	cam.fov = 65.0
	cam.near = 0.05
	cam.far = 4000.0
	add_child(cam)

	if map_name == "wetlands":
		# Dynamic Combat River Patrol Boat
		var boat: Node3D = null
		for ch in scene.find_children("*", "Node3D", true, false):
			if ch.name.to_lower().contains("boat"):
				boat = ch as Node3D
				break
		if boat != null:
			var bpos = boat.global_position
			print("[CaptureSingle] Boat found at: ", bpos)
			cam.global_position = bpos + Vector3(-12.0, 4.0, 12.0)
			cam.look_at(bpos + Vector3(0.0, 1.2, 0.0), Vector3.UP)
		else:
			print("[CaptureSingle] Boat not found, using waypoint 0")
			var bpos := Vector3(-140.0, 0.0, 45.0)
			cam.global_position = bpos + Vector3(-12.0, 4.0, 12.0)
			cam.look_at(bpos + Vector3(0.0, 1.2, 0.0), Vector3.UP)
		
		cam.make_current()
		for i in range(20):
			await get_tree().process_frame
		_save_shot("shot_moving_boat_wetlands.png")

	elif map_name == "village":
		# Large open windows on village cottage
		# Camera placed directly in front of cottage facade on main lane
		cam.global_position = Vector3(42.0, 4.5, 78.5)
		cam.look_at(Vector3(42.0, 3.6, 70.0), Vector3.UP)
		cam.make_current()
		for i in range(20):
			await get_tree().process_frame
		_save_shot("shot_buildings_large_windows.png")

	cam.queue_free()
	scene.queue_free()


func _save_shot(filename: String) -> void:
	var img = get_viewport().get_texture().get_image()
	if img != null:
		var full_path = ARTIFACT_DIR + filename
		var err = img.save_png(full_path)
		print("[CaptureSingle] Saved ", filename, " err=", err)
	else:
		push_error("[CaptureSingle] Failed to grab image for " + filename)
