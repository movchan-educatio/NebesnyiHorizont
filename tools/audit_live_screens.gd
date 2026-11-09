extends Node

const ARTIFACT_DIR := "C:/Users/USER_UA/.gemini/antigravity/brain/978b47c4-dcc4-4721-b5bc-159b55cf7522"

func _ready() -> void:
	var menu_scene = load("res://GUI/MainMenu.tscn")
	if menu_scene == null:
		print("ERROR: Cannot load MainMenu.tscn")
		get_tree().quit(1)
		return
	var menu = menu_scene.instantiate()
	add_child(menu)
	_run_audit(menu)

func _run_audit(menu: Node) -> void:
	var presets_to_audit = [
		0, # Голка
		2, # DJI Avata 2
		3, # «Пісюн» VTOL
		4, # «Пеленг»
		6, # «Грім-7М»
		8, # «Falcon-X» Digital
	]
	
	for idx in presets_to_audit:
		Global.drone_preset = idx
		DroneCatalog.apply(idx)
		if menu.has_method("_load_drone_model"):
			menu.call("_load_drone_model")
		if menu.has_method("_update_drone_intel"):
			menu.call("_update_drone_intel")
			
		# Wait several frames for model, materials, and propeller animations to update
		for f in range(15):
			await get_tree().process_frame
			if menu.has_method("_process"):
				menu.call("_process", 1.0 / 60.0)
				
		var p = DroneCatalog.preset(idx)
		var p_name: String = str(p.get("name", "drone")).replace("«", "").replace("»", "").replace(" ", "_")
		var img = get_viewport().get_texture().get_image()
		var out_path = ARTIFACT_DIR + "/audit_live_preset_" + str(idx) + "_" + p_name + ".png"
		var err = img.save_png(out_path)
		print("[AUDIT] Saved preset ", idx, " (", p_name, ") -> ", out_path, " err=", err)
		
	print(">>> ALL AUDIT SCREENSHOTS CAPTURED SUCCESSFULLY <<<")
	get_tree().quit(0)
