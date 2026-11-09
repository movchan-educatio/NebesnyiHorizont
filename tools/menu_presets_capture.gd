## QA: capture MainMenu at 1600x900 for each Ukrainian airframe so the preview
## framing and the runtime flag decal can be inspected together.
extends Node

const OUT_DIR := "C:/Users/USER_UA/AppData/Local/Temp/opencode/flag_qa"
const PRESETS := [0, 1, 3, 4, 5, 6, 7, 8, 9]


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var packed := load("res://GUI/MainMenu.tscn") as PackedScene
	# Variant, not Control: the harness calls MainMenu script members that are
	# not part of the Control API and must stay dynamically checked.
	var menu: Variant = packed.instantiate()
	add_child(menu)
	for i in range(10):
		await get_tree().process_frame
	menu._auto_orbit = false
	for idx in PRESETS:
		Global.drone_preset = idx
		menu._update_drone_intel()
		menu._load_drone_model()
		for f in range(12):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var full: Image = get_viewport().get_texture().get_image()
		var full_path := "%s/menu_%02d.png" % [OUT_DIR, idx]
		full.save_png(full_path)
		var sub: Image = menu._sub_viewport.get_texture().get_image()
		var sub_path := "%s/preview_%02d.png" % [OUT_DIR, idx]
		sub.save_png(sub_path)
		print("[MENUQA] preset=", idx, " full=", full.get_size(), " sub=", sub.get_size(),
				" container=", menu._viewport_container.size, " saved=", full_path)
	get_tree().quit()
