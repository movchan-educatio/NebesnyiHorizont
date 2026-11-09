extends Node

func _ready() -> void:
	var scn = load("res://GUI/OtherSettingsScreen.tscn").instantiate()
	add_child(scn)
	await get_tree().create_timer(0.6).timeout
	var img = get_viewport().get_texture().get_image()
	img.save_png("C:/Users/USER_UA/.gemini/antigravity/brain/0cd53f75-2554-4ee2-a2e8-b90bed015057/verify_hud_settings_fixed.png")
	print("[SHOT] saved verify_hud_settings_fixed.png")
	get_tree().quit(0)
