extends Node

const ARTIFACT_DIR := "C:/Users/USER_UA/.gemini/antigravity/brain/978b47c4-dcc4-4721-b5bc-159b55cf7522"

func _ready() -> void:
	var hangar_scene = load("res://GUI/DroneSelectScreen.tscn")
	if hangar_scene == null:
		print("ERROR: Cannot load DroneSelectScreen.tscn")
		get_tree().quit(1)
		return
	var hangar = hangar_scene.instantiate()
	add_child(hangar)
	_run_audit(hangar)

func _run_audit(hangar: Node) -> void:
	var presets = [2, 3, 4, 8]
	for idx in presets:
		if hangar.has_method("_select_preview"):
			hangar.call("_select_preview", idx)
		for f in range(15):
			await get_tree().process_frame
			if hangar.has_method("_process"):
				hangar.call("_process", 1.0 / 60.0)
		var p = DroneCatalog.preset(idx)
		var p_name: String = str(p.get("name", "drone")).replace("«", "").replace("»", "").replace(" ", "_")
		var img = get_viewport().get_texture().get_image()
		var out_path = ARTIFACT_DIR + "/audit_live_hangar_" + str(idx) + "_" + p_name + ".png"
		img.save_png(out_path)
		print("[AUDIT HANGAR] Saved ", idx, " -> ", out_path)
	print(">>> ALL HANGAR AUDIT SCREENSHOTS CAPTURED <<<")
	get_tree().quit(0)
