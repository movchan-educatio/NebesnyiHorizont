## QA: render the actual MainMenu loading overlay before the scene changes.
extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var menu := (load("res://GUI/MainMenu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await get_tree().create_timer(0.25).timeout
	menu.call("_begin_loading", "res://sceneries/VillageLevel.tscn")
	await get_tree().create_timer(0.32).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out := "C:/Users/USER_UA/AppData/Local/Temp/opencode/loading_menu.png"
	print("[LOADINGMENU] ", out, " err=", img.save_png(out))
	get_tree().quit(0)
