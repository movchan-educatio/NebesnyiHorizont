extends Node

## QA: capture the Graphics settings screen after the preset cleanup.
func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		get_window().size = Vector2i(1280, 720)
		get_window().move_to_center()
	var scr: Control = load("res://GUI/GraphicsScreen.tscn").instantiate()
	add_child(scr)
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://qa_shots/graphics_menu.png")
	print("[GMENU] saved")
	get_tree().quit()
