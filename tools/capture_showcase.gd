extends Node3D

const ARTIFACT_DIR := "C:/Users/USER_UA/.gemini/antigravity/brain/d3a48383-ba35-4c5d-a092-fbdb2b035535/"

func _ready():
	print("[Showcase] Starting comprehensive FPV trick structures showcase suite...")
	await _capture_industrial()
	await _capture_village()
	await _capture_steppe()
	print("[Showcase] All showcase screenshots captured successfully!")
	get_tree().quit()


func _capture_industrial():
	print("[Showcase] Loading Industrial map...")
	var scene = load("res://sceneries/BigLevel.tscn").instantiate()
	scene.frontline_map = "industrial"
	add_child(scene)
	
	# Wait for terrain, clipmaps, and props to initialize
	for i in range(50):
		await get_tree().process_frame

	var cam = Camera3D.new()
	cam.name = "ShowcaseCam"
	cam.fov = 68.0
	cam.near = 0.05
	cam.far = 4000.0
	add_child(cam)

	# 1. Trick: 3-Story Concrete Construction Skeleton ("Рубік")
	var rubik = scene.find_child("ConstructionSkeletonRubik", true, false) as Node3D
	if rubik != null:
		var rpos = rubik.global_position
		cam.global_position = rpos + Vector3(-14.0, 9.0, 16.0)
		cam.look_at(rpos + Vector3(0.0, 6.0, 0.0), Vector3.UP)
		cam.current = true
		for i in range(20):
			await get_tree().process_frame
		_save_shot("shot_trick_rubik_skeleton.png")

	# 2. Trick: Industrial Pipe & Truss Power-Loop Arch
	var pipe_arch = scene.find_child("PipelinePowerloopArch", true, false) as Node3D
	if pipe_arch != null:
		var ppos = pipe_arch.global_position
		cam.global_position = ppos + Vector3(-18.0, 7.5, 14.0)
		cam.look_at(ppos + Vector3(0.0, 6.5, 0.0), Vector3.UP)
		cam.current = true
		for i in range(20):
			await get_tree().process_frame
		_save_shot("shot_trick_powerloop_arch.png")

	# 3. Trick: Freestyle Slalom Gate Runway
	var slalom = scene.find_child("FreestyleSlalomGateCourse", true, false) as Node3D
	if slalom != null:
		var spos = slalom.global_position
		cam.global_position = spos + Vector3(-12.0, 5.0, 22.0)
		cam.look_at(spos + Vector3(0.0, 2.5, 0.0), Vector3.UP)
		cam.current = true
		for i in range(20):
			await get_tree().process_frame
		_save_shot("shot_trick_slalom_gates.png")

	# 4. Trick: Hollow Mega-Silo / Cooling Stack Dive Funnel
	var silo = scene.find_child("CoolingTowerDiveFunnel", true, false) as Node3D
	if silo != null:
		var spos = silo.global_position
		cam.global_position = spos + Vector3(-16.0, 18.0, 16.0)
		cam.look_at(spos + Vector3(0.0, 11.0, 0.0), Vector3.UP)
		cam.current = true
		for i in range(20):
			await get_tree().process_frame
		_save_shot("shot_trick_dive_funnel_silo.png")

	# 5. Trick: Stacked Shipping Container Complex (Tunnel & Rooftop Gap)
	var containers = scene.find_child("ShippingContainerComplex", true, false) as Node3D
	if containers != null:
		var cpos = containers.global_position
		cam.global_position = cpos + Vector3(-14.0, 6.5, 14.0)
		cam.look_at(cpos + Vector3(0.0, 4.0, 0.0), Vector3.UP)
		cam.current = true
		for i in range(20):
			await get_tree().process_frame
		_save_shot("shot_trick_container_complex.png")

	# 6. Trick: Triple Concrete Pipe Culvert Course
	var pipes = scene.find_child("ConcretePipeCulvertCourse", true, false) as Node3D
	if pipes != null:
		var ppos = pipes.global_position
		cam.global_position = ppos + Vector3(-10.0, 4.5, 15.0)
		cam.look_at(ppos + Vector3(0.0, 2.0, 0.0), Vector3.UP)
		cam.current = true
		for i in range(20):
			await get_tree().process_frame
		_save_shot("shot_trick_pipe_culverts.png")

	# 7. Road Entry Arch (Relocated to road, upgraded with military concrete & hazard stripes)
	cam.global_position = Vector3(-84.0, 5.0, 198.0)
	cam.look_at(Vector3(-100.0, 5.5, 170.0), Vector3.UP)
	cam.current = true
	for i in range(20):
		await get_tree().process_frame
	_save_shot("shot_arch_road_military.png")

	# 8. Industrial Apron, Factory Hall Facade & PBR Ground Relief
	cam.global_position = Vector3(48.0, 5.5, 155.0)
	cam.look_at(Vector3(50.0, 18.0, 80.0), Vector3.UP)
	cam.current = true
	for i in range(20):
		await get_tree().process_frame
	_save_shot("shot_industrial_facade_and_ground.png")

	# 9. Industrial Map Spread (Aerial overview of 30 distributed trick structures)
	cam.global_position = Vector3(20.0, 175.0, 190.0)
	cam.look_at(Vector3(0.0, 5.0, 60.0), Vector3.UP)
	cam.current = true
	for i in range(25):
		await get_tree().process_frame
	_save_shot("shot_industrial_pbr_spread.png")

	cam.queue_free()
	scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _capture_village():
	print("[Showcase] Loading Village map...")
	var scene = load("res://sceneries/BigLevel.tscn").instantiate()
	scene.frontline_map = "village"
	add_child(scene)
	
	for i in range(50):
		await get_tree().process_frame

	var cam = Camera3D.new()
	cam.name = "ShowcaseCamVillage"
	cam.fov = 68.0
	cam.near = 0.05
	cam.far = 4000.0
	add_child(cam)

	# 10. Village Cottages & Anchored Foundations
	cam.global_position = Vector3(65.0, 6.5, 88.0)
	cam.look_at(Vector3(30.0, 3.5, 60.0), Vector3.UP)
	cam.current = true
	for i in range(20):
		await get_tree().process_frame
	_save_shot("shot_village_cottages_and_terrain.png")

	# 11. Village Wide Aerial (30 distributed trick structures)
	cam.global_position = Vector3(50.0, 195.0, 190.0)
	cam.look_at(Vector3(0.0, 10.0, 50.0), Vector3.UP)
	cam.current = true
	for i in range(25):
		await get_tree().process_frame
	_save_shot("shot_village_pbr_spread.png")

	cam.queue_free()
	scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _capture_steppe():
	print("[Showcase] Loading Steppe map...")
	var scene = load("res://sceneries/BigLevel.tscn").instantiate()
	scene.frontline_map = "steppe"
	add_child(scene)
	
	for i in range(50):
		await get_tree().process_frame

	var cam = Camera3D.new()
	cam.name = "ShowcaseCamSteppe"
	cam.fov = 68.0
	cam.near = 0.05
	cam.far = 4000.0
	add_child(cam)

	# 12. Steppe Wide Aerial (PBR ground terrain and trick structures spread across landscape)
	cam.global_position = Vector3(80.0, 205.0, 210.0)
	cam.look_at(Vector3(40.0, 10.0, 80.0), Vector3.UP)
	cam.current = true
	for i in range(25):
		await get_tree().process_frame
	_save_shot("shot_steppe_pbr_spread.png")

	cam.queue_free()
	scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _save_shot(filename: String) -> void:
	var img = get_viewport().get_texture().get_image()
	if img != null:
		var full_path = ARTIFACT_DIR + filename
		var err = img.save_png(full_path)
		print("[Showcase] Wrote ", filename, " err=", err)
	else:
		push_error("[Showcase] Failed to grab viewport image for " + filename)
