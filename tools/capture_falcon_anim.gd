extends SceneTree

func _init():
	var menu_scene = load("res://GUI/MainMenu.tscn")
	var menu = menu_scene.instantiate()
	root.add_child(menu)
	Global.drone_preset = 8
	DroneCatalog.apply(8)
	menu.call("_load_drone_model")
	menu.call("_update_drone_intel")
	
	# Warmup
	for f in range(10):
		await process_frame
		menu.call("_process", 1.0 / 60.0)
		
	# Capture 24 frames
	for f in range(24):
		await process_frame
		menu.call("_process", 1.0 / 60.0)
		var img = root.get_viewport().get_texture().get_image()
		img.save_png("res://tools/frames/falcon_frame_%02d.png" % f)
	print("CAPTURED 24 FRAMES FOR FALCON-X")
	quit(0)
