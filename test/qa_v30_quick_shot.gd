extends Node

func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	Global.menu_settings["selected_map"] = "oilrig"
	Global.play_mode = Global.PlayMode.TRAINING
	DroneCatalog.apply(0)
	var packed := load("res://sceneries/OilRigLevel.tscn") as PackedScene
	var level := packed.instantiate()
	add_child(level)
	await get_tree().create_timer(2.0).timeout
	var cam := Camera3D.new()
	cam.far = 6000.0
	level.add_child(cam)
	cam.global_position = Vector3(-420.0, 720.0, 880.0)
	cam.look_at(Vector3(0.0, 400.0, 0.0), Vector3.UP)
	cam.current = true
	await get_tree().create_timer(0.8).timeout
	for _i in range(3):
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("res://qa_shots/v30_mobile_oilrig.png")
	print("[QUICKSHOT] done")
	get_tree().quit()
