extends Node

func _ready():
	var preset_idx: int = 8
	var env := OS.get_environment("CAPTURE_PRESET").strip_edges()
	if env.is_valid_int():
		preset_idx = int(env)
	print("STARTING CAPTURE FOR PRESET ", preset_idx)
	
	var menu_scene = load("res://GUI/MainMenu.tscn")
	var menu = menu_scene.instantiate()
	add_child(menu)
	Global.drone_preset = preset_idx
	DroneCatalog.apply(preset_idx)
	menu.call("_load_drone_model")
	menu.call("_update_drone_intel")
	
	# Warmup frames so models, textures, shaders compile
	for f in range(12):
		await get_tree().process_frame
		menu.call("_process", 1.0 / 60.0)
		
	# Capture 24 frames of live rotation
	for f in range(24):
		await get_tree().process_frame
		menu.call("_process", 1.0 / 60.0)
		var img = get_viewport().get_texture().get_image()
		img.save_png("res://tools/frames/preset_%d_frame_%02d.png" % [preset_idx, f])
		
	print("SUCCESSFULLY CAPTURED 24 FRAMES FOR PRESET ", preset_idx)
	get_tree().quit(0)
