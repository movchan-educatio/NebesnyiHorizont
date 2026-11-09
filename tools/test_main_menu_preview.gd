extends Node

func _ready() -> void:
	print("TESTING MAIN MENU 3D PREVIEW FOR ALL DRONES...")
	# Load MainMenu scene
	var main_menu = load("res://GUI/MainMenu.tscn").instantiate()
	get_tree().root.add_child(main_menu)
	
	await get_tree().process_frame
	await get_tree().process_frame
	
	var vp := get_viewport()
	
	for idx in range(10): # 0 to 9
		Global.drone_preset = idx
		main_menu._selected_drone = idx
		main_menu._load_drone_model()
		main_menu._update_drone_intel()
		
		# Let it animate for 20 frames
		for f in range(20):
			await get_tree().process_frame
			
		var img = vp.get_texture().get_image()
		var out_path = "C:/Users/USER_UA/.gemini/antigravity/brain/978b47c4-dcc4-4721-b5bc-159b55cf7522/menu_preview_%d.png" % idx
		img.save_png(out_path)
		print("Captured MainMenu preview for preset %d to %s" % [idx, out_path])
		
	print("ALL MAIN MENU PREVIEWS CAPTURED!")
	get_tree().quit(0)
