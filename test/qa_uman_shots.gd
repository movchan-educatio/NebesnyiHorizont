extends Node

## Генерує 20 скріншотів-підтверджень інтеграції карти Умань.
## Запуск (НЕ headless, потрібен рендер):
##   Godot_v4.6.1-stable_win64_console.exe --path . res://test/qa_uman_shots.tscn

const OUT := "res://qa_shots/uman/"
var _n := 0


func _shot(name: String) -> void:
	_n += 1
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s%02d_%s.png" % [OUT, _n, name]
	img.save_png(path)
	print("[UMAN-SHOT] ", path)


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _ready() -> void:
	get_window().size = Vector2i(1600, 900)
	DirAccess.make_dir_recursive_absolute(OUT)
	Global.menu_settings["selected_map"] = "uman"
	Global.play_mode = Global.PlayMode.TRAINING
	Global.combat_training = false
	DroneCatalog.apply(10)

	# ---------- Карта: 8 оглядових ракурсів ----------
	var packed := load("res://sceneries/UmanLevel.tscn") as PackedScene
	var level := packed.instantiate()
	add_child(level)
	await _wait(4.0)
	var cam := Camera3D.new()
	cam.fov = 80.0
	cam.far = 3000.0
	level.add_child(cam)
	cam.current = true
	var views := [
		[Vector3(0, 130, 240), Vector3(0, 0, 0), "map_overview"],
		[Vector3(122, 28, 118), Vector3(60, 4, 30), "waterfront"],
		[Vector3(-62, 30, 28), Vector3(-30, 4, -32), "sofiyivka"],
		[Vector3(12, 12, 12), Vector3(-28, 4.5, -30), "gate_to_pavilion"],
		[Vector3(118, 15, 112), Vector3(70, 5, 55), "fountains"],
		[Vector3(-30, 14, -34), Vector3(-24, 3, -34), "flora_rotunda"],
		[Vector3(70, 18, 20), Vector3(70, 2, 55), "pearl_pontoon"],
		[Vector3(150, 45, -40), Vector3(60, 4, 30), "freestyle_zones"],
	]
	for v in views:
		cam.global_position = v[0]
		cam.look_at(v[1], Vector3.UP)
		await _wait(0.6)
		await _shot(str(v[2]))

	# ---------- FPV: три дрони з обертовими гвинтами ----------
	cam.current = false
	var drone := level.get_node_or_null("Drone") as Node3D
	for idx in [10, 11, 12]:
		DroneCatalog.apply(idx)
		if drone != null:
			DroneCatalog.apply_to_drone(drone, idx)
			# Імітуємо реальний політ: мотори крутяться, лопаті зливаються в диск.
			var motors: Array = drone.get("motors") as Array
			for m in motors:
				m.rpm = 2600.0
			var model := drone.get_node_or_null("DroneModel")
			if model != null:
				DroneCatalog.animate_propellers(model, 0.25, [420.0, 420.0, 420.0, 420.0])
		await _wait(0.8)
		await _shot("fpv_" + DroneCatalog.preset(idx).get("id", "drone"))

	level.queue_free()
	await _wait(0.6)

	# ---------- ПК-меню: Умань + Фрістайл ----------
	var menu := (load("res://GUI/MainMenu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await _wait(2.0)
	await _shot("pc_main_menu_uman_freestyle")
	menu.queue_free()
	await _wait(0.5)

	# ---------- ПК-ангар: тільки 3 фрістайл-дрони ----------
	var hangar := (load("res://GUI/DroneSelectScreen.tscn") as PackedScene).instantiate()
	add_child(hangar)
	await _wait(2.0)
	await _shot("pc_hangar_3_freestyle_drones")
	hangar.queue_free()
	await _wait(0.5)

	# ---------- Мобільне меню: картки карт і режимів ----------
	var mobile := (load("res://GUI/mobile/MobileMenu.tscn") as PackedScene).instantiate()
	add_child(mobile)
	await _wait(2.5)
	await _shot("mobile_main")
	if mobile.has_method("_show"):
		mobile.call("_show", "play")
		await _wait(1.5)
		await _shot("mobile_maps_freestyle")
		mobile.call("_show", "drone")
		await _wait(1.5)
		await _shot("mobile_hangar_3_drones")
	mobile.queue_free()
	await _wait(0.5)

	# ---------- Додаткові підтвердження: прев'ю трьох дронів окремо ----------
	for idx in [10, 11, 12]:
		var viewer := (load("res://GUI/DroneSelectScreen.tscn") as PackedScene).instantiate()
		add_child(viewer)
		await _wait(1.2)
		if viewer.has_method("_show_model"):
			viewer.call("_show_model", idx)
		await _wait(1.2)
		await _shot("preview_" + DroneCatalog.preset(idx).get("id", "drone"))
		viewer.queue_free()
		await _wait(0.4)

	# ---------- Фінальне підтвердження: карта в польоті ----------
	var level2 := packed.instantiate()
	add_child(level2)
	await _wait(3.0)
	await _shot("final_uman_freestyle_flight")
	print("[UMAN-SHOT] TOTAL=", _n)
	get_tree().quit(0)
