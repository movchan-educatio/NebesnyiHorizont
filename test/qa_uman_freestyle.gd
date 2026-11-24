extends Node

## Headless-QA для фрістайл-карти Умань.
## Перевіряє: завантаження GLB, відсутність бою, спавн дрона, обертові гвинти.

var _fails := 0


func _check(ok: bool, label: String) -> void:
	if not ok:
		_fails += 1
		print("[UMAN-QA] FAIL ", label)
	else:
		print("[UMAN-QA] PASS ", label)


func _ready() -> void:
	Global.menu_settings["selected_map"] = "uman"
	Global.play_mode = Global.PlayMode.TRAINING
	Global.combat_training = false
	DroneCatalog.apply(10)
	var packed := load("res://sceneries/UmanLevel.tscn") as PackedScene
	_check(packed != null, "UmanLevel.tscn завантажується")
	if packed == null:
		_get_tree_quit()
		return
	var level := packed.instantiate()
	add_child(level)
	for _i in range(12):
		await get_tree().physics_frame

	var map_root := level.get_node_or_null("MapRoot")
	_check(map_root != null and map_root.get_child_count() > 0, "GLB карти інстанційовано")
	var water := _find_prefix(level, "Water_Surface")
	_check(not water.is_empty(), "Water_Surface знайдено (водний шейдер)")
	var fx := _find_prefix(level, "FX_")
	_check(fx.size() >= 6, "маркери FX_ фонтанів знайдено (%d)" % fx.size())

	var vehicles := get_tree().get_nodes_in_group("vehicle")
	var infantry := get_tree().get_nodes_in_group("infantry")
	var destructibles := get_tree().get_nodes_in_group("destructible")
	_check(vehicles.is_empty(), "бойової техніки НЕМАЄ (%d)" % vehicles.size())
	_check(infantry.is_empty(), "піхоти НЕМАЄ (%d)" % infantry.size())
	_check(destructibles.is_empty(), "руйнованих цілей НЕМАЄ (%d)" % destructibles.size())

	var drone := level.get_node_or_null("Drone")
	_check(drone != null, "дрон на карті")
	if drone != null:
		var model := drone.get_node_or_null("DroneModel")
		_check(model != null, "3D-модель дрона підключена")
		if model != null:
			var pivots: Array = model.get_meta("prop_pivots", []) as Array
			_check(pivots.size() >= 4, "півоти гвинтів знайдено (%d)" % pivots.size())
			var before := Transform3D()
			if not pivots.is_empty() and pivots[0] is Node3D:
				before = (pivots[0] as Node3D).transform
			DroneCatalog.animate_propellers(model, 0.1, [300.0, 300.0, 300.0, 300.0])
			if not pivots.is_empty() and pivots[0] is Node3D:
				_check((pivots[0] as Node3D).transform != before, "гвинти обертаються під час польоту")
				# Реальні RPM залежать від газу/стіків — різна тяга дає різний кут за кадр.
				var p0: Node3D = pivots[0] as Node3D
				p0.transform = Transform3D.IDENTITY
				DroneCatalog.animate_propellers(model, 0.1, [80.0, 80.0, 80.0, 80.0])
				var low_angle: float = p0.transform.basis.get_euler().y
				p0.transform = Transform3D.IDENTITY
				DroneCatalog.animate_propellers(model, 0.1, [600.0, 600.0, 600.0, 600.0])
				var high_angle: float = p0.transform.basis.get_euler().y
				_check(absf(high_angle - low_angle) > 0.05,
						"швидкість обертання реагує на газ/стіки (%.3f → %.3f)" % [low_angle, high_angle])
		_check(drone.global_position.y > 0.0, "дрон не під ґрунтом (y=%.2f)" % drone.global_position.y)

	_check(level.get_node_or_null("UmanSafetyGround") != null,
			"суцільний ґрунт/колізія під карті є")
	_check(level.get_node_or_null("UmanGroundSkirt") != null,
			"край карти закритий «спідницею»")
	var gates := _count_prefix(level, "NeonGate")
	_check(gates >= 24, "неоновий маршрут із контрольними точками створено (%d)" % gates)
	var stunt_cols := _count_class(level, "StaticBody3D")
	var sample: Array[String] = []
	for c in level.get_children():
		if c is StaticBody3D:
			sample.append(String(c.name))
			if sample.size() >= 8:
				break
	print("[UMAN-QA] static bodies sample=", sample, " children=", level.get_child_count())
	_check(stunt_cols >= 80, "трюкові/крайові об'єкти мають колізії (%d)" % stunt_cols)

	# Авторестарт при падінні у воду.
	if drone != null:
		drone.global_position = Vector3(60.0, 0.4, 25.0)  # центр великої водойми
		drone.linear_velocity = Vector3.ZERO
		for _i in range(120):
			await get_tree().physics_frame
		var after: Vector3 = drone.global_position
		_check(after.distance_to(Vector3(60.0, 0.4, 25.0)) > 30.0,
				"після падіння у воду дрон автоматично рестартував (pos=%s)" % str(after))

	_check(DroneCatalog.is_uman(Global.drone_preset), "активний дрон — фрістайльний")
	_check(DroneCatalog.allowed_for_map("uman").size() >= 13, "в загальному ангарі на Умані >= 13 дронів")
	_check(DroneCatalog.allowed_for_map("industrial").size() >= 13, "в загальному ангарі на інших картах >= 13 дронів")
	_check(DroneCatalog.allowed_for_mode(Global.PlayMode.TRAINING).size() >= 13, "у фрістайлі доступні >= 13 дронів")
	_check(DroneCatalog.allowed_for_mode(Global.PlayMode.COMBAT).size() >= 10, "у бойовому режимі доступні >= 10 бойових дронів")
	print("[UMAN-QA] fails=", _fails)
	remove_child(level)
	level.free()
	_get_tree_quit()


func _get_tree_quit() -> void:
	await get_tree().process_frame
	get_tree().quit(0 if _fails == 0 else 1)


func _count_class(node: Node, cls: String) -> int:
	var n := 1 if node.is_class(cls) else 0
	for c in node.get_children():
		n += _count_class(c, cls)
	return n


func _count_name(node: Node, name_part: String) -> int:
	var n := 0
	if String(node.name).contains(name_part):
		n += 1
	for c in node.get_children():
		n += _count_name(c, name_part)
	return n


func _count_prefix(node: Node, prefix: String) -> int:
	var n := 0
	if String(node.name).begins_with(prefix):
		n += 1
	for c in node.get_children():
		n += _count_prefix(c, prefix)
	return n


func _find_prefix(node: Node, prefix: String) -> Array:
	var out: Array = []
	if node.name.begins_with(prefix):
		out.append(node)
	for c in node.get_children():
		out.append_array(_find_prefix(c, prefix))
	return out
