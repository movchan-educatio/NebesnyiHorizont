extends Node
## v30 extra visual QA: 21 additional screenshots of maps, drones, enemies and UI.
## Run windowed: Godot.exe --path . res://test/qa_v30_extra_shots.tscn

var _cam: Camera3D = null
var _shot_index := 0


func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	await _shoot_forest()
	await _shoot_ace()
	await _shoot_oilrig()
	await _shoot_ui()
	await _shoot_final_two()
	print("[V30-EXTRA] done, shots=", _shot_index)
	get_tree().quit()


func _save(label: String) -> void:
	_shot_index += 1
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null:
		var name := "qa_shots/v30_extra_%02d_%s.png" % [_shot_index, label]
		img.save_png("res://" + name)
		print("[V30-EXTRA] ", name)


func _set_cam(parent: Node, at: Vector3, look: Vector3, fov: float = 76.0) -> void:
	if _cam == null or not is_instance_valid(_cam):
		_cam = Camera3D.new()
		_cam.far = 6000.0
		parent.add_child(_cam)
	_cam.fov = fov
	_cam.global_position = at
	_cam.look_at(look, Vector3.UP)
	_cam.current = true


func _clear_cam() -> void:
	if _cam != null and is_instance_valid(_cam):
		_cam.queue_free()
	_cam = null


func _shoot_forest() -> void:
	Global.menu_settings["selected_map"] = "lis_forest_freestyle"
	Global.play_mode = Global.PlayMode.COMBAT
	Global.special_mission = 0
	Global.difficulty = Global.Difficulty.OPERATOR
	DroneCatalog.apply(0)
	var packed := load("res://sceneries/LisLevel.tscn") as PackedScene
	var level := packed.instantiate()
	add_child(level)
	await get_tree().create_timer(3.5).timeout
	var drone := level.get_node_or_null("Drone") as Node3D

	_set_cam(level, Vector3(0.0, 150.0, 430.0), Vector3(0.0, 20.0, 0.0), 70.0)
	await get_tree().create_timer(0.5).timeout
	await _save("forest_aerial")

	_set_cam(level, Vector3(-235.0, 22.0, -225.0), Vector3(-215.0, 12.0, -205.0))
	await get_tree().create_timer(0.4).timeout
	await _save("forest_spawn")

	# Infantry close-up
	var infantry := get_tree().get_nodes_in_group("enemy_infantry")
	if not infantry.is_empty():
		var pos := (infantry[0] as Node3D).global_position
		_set_cam(level, pos + Vector3(-9.0, 3.2, 9.0), pos + Vector3(0.0, 1.0, 0.0))
		await get_tree().create_timer(0.4).timeout
		await _save("forest_infantry")

	# River from low altitude
	_set_cam(level, Vector3(10.0, 28.0, 130.0), Vector3(0.0, 8.0, -20.0))
	await get_tree().create_timer(0.4).timeout
	await _save("forest_river")

	# Kamikaze far/close (freeze so it stays in frame)
	var kzs := get_tree().get_nodes_in_group("enemy_kamikaze")
	if not kzs.is_empty():
		var kz := kzs[0] as Node3D
		kz.set_physics_process(false)
		var kpos := kz.global_position
		_set_cam(level, kpos + Vector3(0.0, 8.0, 70.0), kpos, 60.0)
		await get_tree().create_timer(0.5).timeout
		await _save("kamikaze_far")
		kz.scale = Vector3.ONE * 3.0
		_set_cam(level, kpos + Vector3(0.0, 1.2, 4.0), kpos)
		await get_tree().create_timer(0.4).timeout
		await _save("kamikaze_close")

	# Freestyle ring course
	var rings: Variant = level.get("_training_ring_positions")
	if rings is Array and not (rings as Array).is_empty():
		var rp: Vector3 = (rings as Array)[0]
		_set_cam(level, rp + Vector3(0.0, 7.0, 18.0), rp + Vector3(0.0, 2.0, -8.0))
		await get_tree().create_timer(0.4).timeout
		await _save("forest_gates")

	# Three new flyable drones, chase camera with props/body visible
	for entry in [[13, "wraith"], [14, "komar"], [15, "shmel"]]:
		var idx: int = int(entry[0])
		if drone != null:
			DroneCatalog.apply_to_drone(drone, idx)
			await get_tree().process_frame
			var dp := drone.global_position
			_set_cam(level, dp + Vector3(0.0, 1.1, 3.2), dp + Vector3(0.0, 0.1, 0.0), 68.0)
			await get_tree().create_timer(0.6).timeout
			await _save("new_drone_" + String(entry[1]))

	_clear_cam()
	level.queue_free()
	for _i in range(4):
		await get_tree().physics_frame


func _shoot_ace() -> void:
	Global.difficulty = Global.Difficulty.ACE
	DroneCatalog.apply(0)
	var packed := load("res://sceneries/LisLevel.tscn") as PackedScene
	var level := packed.instantiate()
	add_child(level)
	await get_tree().create_timer(3.0).timeout
	var kzs := get_tree().get_nodes_in_group("enemy_kamikaze")
	for k in kzs:
		(k as Node3D).set_physics_process(false)
	if kzs.size() >= 2:
		var a := (kzs[0] as Node3D).global_position
		var b := (kzs[1] as Node3D).global_position
		var mid := (a + b) * 0.5
		_set_cam(level, mid + Vector3(0.0, 22.0, 95.0), mid, 70.0)
		await get_tree().create_timer(0.5).timeout
		await _save("ace_two_kamikazes")
	Global.difficulty = Global.Difficulty.OPERATOR
	_clear_cam()
	level.queue_free()
	for _i in range(4):
		await get_tree().physics_frame


func _shoot_oilrig() -> void:
	Global.menu_settings["selected_map"] = "oilrig"
	Global.play_mode = Global.PlayMode.TRAINING
	DroneCatalog.apply(0)
	var packed := load("res://sceneries/OilRigLevel.tscn") as PackedScene
	var level := packed.instantiate()
	add_child(level)
	await get_tree().create_timer(3.5).timeout

	_set_cam(level, Vector3(0.0, 1500.0, 50.0), Vector3(0.0, 400.0, 0.0), 78.0)
	await get_tree().create_timer(0.5).timeout
	await _save("oilrig_top")

	_set_cam(level, Vector3(-180.0, 430.0, 250.0), Vector3(0.0, 400.0, 60.0))
	await get_tree().create_timer(0.4).timeout
	await _save("oilrig_deck")

	_set_cam(level, Vector3(-260.0, 425.0, 560.0), Vector3(-204.0, 407.0, 510.0))
	await get_tree().create_timer(0.4).timeout
	await _save("oilrig_helipad")

	_set_cam(level, Vector3(300.0, 460.0, -220.0), Vector3(160.0, 420.0, -80.0))
	await get_tree().create_timer(0.4).timeout
	await _save("oilrig_derrick")

	var gates_node := level.find_child("FPVGates", true, false)
	if gates_node != null and not gates_node.get_children().is_empty():
		var gp := (gates_node.get_children()[0] as Node3D).global_position
		_set_cam(level, gp + Vector3(0.0, 10.0, 40.0), gp + Vector3(0.0, 2.0, -12.0))
		await get_tree().create_timer(0.4).timeout
		await _save("oilrig_gates")

	_set_cam(level, Vector3(-700.0, 12.0, 700.0), Vector3(0.0, 0.0, 0.0))
	await get_tree().create_timer(0.4).timeout
	await _save("oilrig_ocean")

	var drone := level.get_node_or_null("Drone") as Node3D
	if drone != null:
		DroneCatalog.apply_to_drone(drone, 13)
		await get_tree().process_frame
		var dp := drone.global_position
		_set_cam(level, dp + Vector3(0.0, 1.2, 3.4), dp + Vector3(0.0, 0.1, 0.0), 68.0)
		await get_tree().create_timer(0.6).timeout
		await _save("oilrig_wraith")

	_clear_cam()
	level.queue_free()
	for _i in range(4):
		await get_tree().physics_frame


func _shoot_ui() -> void:
	var hangar := (load("res://GUI/DroneSelectScreen.tscn") as PackedScene).instantiate()
	add_child(hangar)
	await get_tree().create_timer(2.5).timeout
	await _save("hangar_new_drones")
	hangar.queue_free()
	await get_tree().process_frame

	var mobile := (load("res://GUI/mobile/MobileMenu.tscn") as PackedScene).instantiate()
	add_child(mobile)
	await get_tree().create_timer(2.5).timeout
	await _save("mobile_menu_maps")
	mobile.queue_free()
	await get_tree().process_frame


func _shoot_final_two() -> void:
	# Freestyle ring course on the forest map (training mode actually spawns rings).
	Global.menu_settings["selected_map"] = "lis_forest_freestyle"
	Global.play_mode = Global.PlayMode.TRAINING
	DroneCatalog.apply(0)
	var packed := load("res://sceneries/LisLevel.tscn") as PackedScene
	var level := packed.instantiate()
	add_child(level)
	await get_tree().create_timer(3.0).timeout
	var rings: Variant = level.get("_training_ring_positions")
	if rings is Array and not (rings as Array).is_empty():
		var rp: Vector3 = (rings as Array)[0]
		_set_cam(level, rp + Vector3(0.0, 8.0, 20.0), rp + Vector3(0.0, 2.0, -10.0))
		await get_tree().create_timer(0.5).timeout
		await _save("forest_freestyle_gates")
	_clear_cam()
	level.queue_free()
	for _i in range(4):
		await get_tree().physics_frame

	# Desktop menu with the new map cards and coin counter.
	var menu := (load("res://GUI/MainMenu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await get_tree().create_timer(2.5).timeout
	await _save("main_menu_coins")
	menu.queue_free()
	await get_tree().process_frame
