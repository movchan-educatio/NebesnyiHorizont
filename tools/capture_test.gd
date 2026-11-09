extends Node3D

func _ready() -> void:
	print("--- SCREENSHOT CAPTURE TEST ---")
	await get_tree().create_timer(0.5).timeout
	var vp := get_viewport()
	var img := vp.get_texture().get_image()
	if img != null:
		var save_path := "C:/Users/USER_UA/.gemini/antigravity/brain/978b47c4-dcc4-4721-b5bc-159b55cf7522/godot_live_test.png"
		var err := img.save_png(save_path)
		print("Saved screenshot to ", save_path, " err=", err)
	else:
		print("img is null")
	get_tree().quit()
