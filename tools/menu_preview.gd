## QA: render MainMenu or DroneSelectScreen at the current viewport resolution.
extends Node

func _ready() -> void:
	var which := OS.get_environment("MENU_SCENE")
	if which.is_empty():
		which = "MainMenu"
	var path := "res://GUI/%s.tscn" % which
	var packed := load(path) as PackedScene
	if packed == null:
		print("[MENU] load failed ", path)
		get_tree().quit(1)
		return
	var inst := packed.instantiate()
	add_child(inst)
	for i in range(20):
		await get_tree().process_frame
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out := OS.get_environment("MODEL_OUT")
	if out.is_empty():
		out = "C:/Users/USER_UA/AppData/Local/Temp/opencode/menu.png"
	print("[MENU] size=", img.get_size(), " saved=", out, " err=", img.save_png(out))
	get_tree().quit(0)
