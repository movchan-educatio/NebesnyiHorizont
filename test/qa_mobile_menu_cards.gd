extends Node

## Mobile-only visual check for map-card thumbnails and the Play screen.
## Output: MOBILE_MENU_SHOT_DIR/play.png plus one image per selected map.
const MENU := preload("res://GUI/mobile/MobileMenu.tscn")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var output := OS.get_environment("MOBILE_MENU_SHOT_DIR")
	if output.is_empty():
		push_error("[MOBILE_MENU_SHOTS] missing MOBILE_MENU_SHOT_DIR")
		get_tree().quit(1)
		return
	OS.set_environment("MOBILE_UI", "1")
	DirAccess.make_dir_recursive_absolute(output)
	if DisplayServer.get_name() == "headless":
		# The menu's hero SubViewport is not renderable under the dummy
		# headless display. Validate the card assets without pretending a
		# screenshot was captured.
		var missing := []
		for map_id in ["steppe", "village", "industrial", "wetlands"]:
			var path := "res://Assets/Branding/mobile_map_%s.png" % map_id
			var texture := load(path) as Texture2D
			if texture == null or texture.get_width() <= 0 or texture.get_height() <= 0:
				missing.append(path)
		print("[MOBILE_MENU_SHOTS] headless card-resource check ",
				"PASS" if missing.is_empty() else "FAIL: " + str(missing))
		get_tree().quit(0 if missing.is_empty() else 1)
		return
	var menu := MENU.instantiate() as Control
	add_child(menu)
	await get_tree().create_timer(1.0).timeout
	_menu_show(menu, "play")
	await get_tree().create_timer(0.8).timeout
	await _save(output.path_join("play.png"))
	for map_id in ["steppe", "village", "industrial", "wetlands"]:
		menu.call("_select_map", map_id)
		await get_tree().create_timer(0.35).timeout
		await _save(output.path_join("play_" + map_id + ".png"))
	print("[MOBILE_MENU_SHOTS] complete")
	get_tree().quit(0)


func _menu_show(menu: Control, screen: String) -> void:
	if menu.has_method("_show"):
		menu.call("_show", screen)


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	if err != OK:
		push_error("[MOBILE_MENU_SHOTS] save failed: %s (%d)" % [path, err])
	else:
		print("[MOBILE_MENU_SHOTS] saved ", path)
