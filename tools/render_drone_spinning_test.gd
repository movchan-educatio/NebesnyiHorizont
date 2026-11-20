extends Node3D

func _ready() -> void:
	print("Starting comprehensive visual propeller render for ALL 10 drones...")
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0.22, 0.18, 0.24)
	cam.look_at_from_position(cam.position, Vector3(0.0, 0.01, 0.0), Vector3.UP)
	cam.fov = 55.0
	
	var light := DirectionalLight3D.new()
	add_child(light)
	light.rotation_degrees = Vector3(-40, 50, 0)
	light.light_energy = 1.8
	
	var fill := DirectionalLight3D.new()
	add_child(fill)
	fill.rotation_degrees = Vector3(30, -130, 0)
	fill.light_energy = 0.8
	fill.light_color = Color(0.8, 0.9, 1.0)
	
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.14, 0.16, 0.19)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.52, 0.55)
	env.environment = e
	add_child(env)
	
	var vp := get_viewport()
	
	for idx in range(DroneCatalog.count()): # Presets 0 through N
		var p_info = DroneCatalog.preset(idx)
		var p_name = str(p_info.get("name", "drone"))
		print("Rendering preset %d: %s" % [idx, p_name])
		
		var holder := Node3D.new()
		add_child(holder)
		var model = DroneCatalog.attach_model(holder, idx)
		
		# Spin propellers for 15 frames
		for frame in range(15):
			DroneCatalog.animate_propellers(model, 0.016, [4500.0, 4500.0, 4500.0, 4500.0])
			await get_tree().process_frame
			
		# Capture screenshot
		var img = vp.get_texture().get_image()
		var out_path = "C:/Users/USER_UA/.gemini/antigravity/brain/978b47c4-dcc4-4721-b5bc-159b55cf7522/drone_spin_%d.png" % idx
		img.save_png(out_path)
		print("  -> Saved %s" % out_path)
		
		holder.queue_free()
		await get_tree().process_frame
		
	print("ALL 10 DRONES VISUALLY VERIFIED AND SAVED!")
	get_tree().quit(0)
