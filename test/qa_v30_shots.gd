extends Node
## v30 screenshot capture: two new maps, enemy kamikaze and the coin UI.
## Run windowed: Godot.exe --path . res://test/qa_v30_shots.tscn

var _cam: Camera3D = null


func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	await _shoot_level("res://sceneries/LisLevel.tscn", "lis_forest_freestyle", false)
	await _shoot_level("res://sceneries/OilRigLevel.tscn", "oilrig", true)
	await _shoot_menu()
	print("[V30-SHOT] done")
	get_tree().quit()


func _make_camera(parent: Node) -> void:
	_cam = Camera3D.new()
	_cam.fov = 76.0
	_cam.far = 6000.0
	parent.add_child(_cam)
	_cam.current = true


func _save(name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("res://qa_shots/v30_%s.png" % name)
		print("[V30-SHOT] saved qa_shots/v30_%s.png" % name)


func _shoot_level(path: String, id: String, oilrig: bool) -> void:
	Global.menu_settings["selected_map"] = id
	Global.play_mode = Global.PlayMode.COMBAT if not oilrig else Global.PlayMode.TRAINING
	Global.special_mission = 0
	Global.difficulty = Global.Difficulty.OPERATOR
	DroneCatalog.apply(0)
	var packed := load(path) as PackedScene
	if packed == null:
		return
	var level := packed.instantiate()
	add_child(level)
	await get_tree().create_timer(4.0).timeout
	_make_camera(level)
	var views: Array
	if oilrig:
		views = [
			[Vector3(-420, 720, 880), Vector3(0, 400, 0)],
			[Vector3(-260, 450, 330), Vector3(0, 400, 40)],
		]
	else:
		views = [
			[Vector3(40, 170, 330), Vector3(0, 25, 0)],
			[Vector3(-230, 60, -230), Vector3(-80, 15, -110)],
		]
	for i in range(views.size()):
		_cam.global_position = views[i][0]
		_cam.look_at(views[i][1], Vector3.UP)
		await get_tree().create_timer(0.8).timeout
		await _save("%s_%d" % [id, i])
	if not oilrig:
		# Enemy kamikaze close-up: spawn one large drone in front of the camera.
		var script := load("res://combat/enemy_kamikaze_drone.gd")
		if script != null:
			var enemy = script.new()
			level.add_child(enemy)
			enemy.global_position = Vector3(-70.0, 26.0, -100.0)
			enemy.set_physics_process(false)
			enemy.scale = Vector3.ONE * 4.0  # QA-zoom only
			_cam.global_position = enemy.global_position + Vector3(0.0, 0.7, 2.6)
			_cam.look_at(enemy.global_position, Vector3.UP)
			await get_tree().create_timer(0.8).timeout
			await _save("enemy_kamikaze")
	level.queue_free()
	for _i in range(3):
		await get_tree().physics_frame


func _shoot_menu() -> void:
	var menu_scene := load("res://GUI/MainMenu.tscn") as PackedScene
	if menu_scene == null:
		return
	var menu := menu_scene.instantiate()
	add_child(menu)
	await get_tree().create_timer(4.0).timeout
	_cam = null
	await _save("menu_coins")
