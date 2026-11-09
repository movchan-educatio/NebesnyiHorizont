extends Node

func _ready():
	var menu_scene = load("res://GUI/MainMenu.tscn")
	var menu = menu_scene.instantiate()
	add_child(menu)
	Global.drone_preset = 3
	DroneCatalog.apply(3)
	menu.call("_load_drone_model")
	menu.call("_update_drone_intel")
	
	# Wait for setup
	for f in range(10):
		await get_tree().process_frame
		menu.call("_process", 1.0 / 60.0)
		
	# Capture 20 frames of live rotation
	for f in range(20):
		await get_tree().process_frame
		menu.call("_process", 1.0 / 60.0)
		var img = get_viewport().get_texture().get_image()
		img.save_png("res://tools/frames/pisun_frame_%02d.png" % f)
	print("CAPTURED 20 FRAMES FOR PISUN")
	get_tree().quit(0)
