extends Node

func _ready() -> void:
	await get_tree().process_frame
	print("Loading BigLevel...")
	var packed := load("res://sceneries/BigLevel.tscn") as PackedScene
	var scene: Node = packed.instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("BigLevel loaded, finding PauseMenu...")
	var canvas := scene.get_node_or_null("PauseCanvasLayer")
	var pause_menu = canvas.get_child(0) if canvas != null and canvas.get_child_count() > 0 else null
	if pause_menu == null:
		print("FAIL: PauseMenu not found")
		get_tree().quit(1)
		return
	print("Calling pause_menu._on_main_menu_pressed()...")
	pause_menu._on_main_menu_pressed()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	print("Scene after main menu press: ", get_tree().current_scene.name)
	print("PASS")
	get_tree().quit(0)
