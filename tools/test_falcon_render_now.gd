extends SceneTree

func _init():
	var menu_scene = load("res://GUI/MainMenu.tscn")
	var menu = menu_scene.instantiate()
	root.add_child(menu)
	Global.drone_preset = 8
	DroneCatalog.apply(8)
	menu.call("_load_drone_model")
	menu.call("_update_drone_intel")
	for f in range(20):
		await process_frame
		menu.call("_process", 1.0 / 60.0)
	var img = root.get_viewport().get_texture().get_image()
	img.save_png("res://tools/test_falcon_current_mainmenu.png")
	print("SAVED CURRENT FALCON MAINMENU")
	quit()
