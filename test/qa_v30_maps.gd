extends Node
## v30 QA: нові карти Ліс і Нафтова платформа разом із BigLevel.

var _fails := 0


func _check(ok: bool, label: String) -> void:
	if ok:
		print("[V30-MAP] PASS ", label)
	else:
		_fails += 1
		print("[V30-MAP] FAIL ", label)


func _ready() -> void:
	await _test_map("res://sceneries/LisLevel.tscn", "lis_forest_freestyle",
			"LisFreestyleMap", false)
	await _test_map("res://sceneries/OilRigLevel.tscn", "oilrig",
			"OilRigMap", true)
	await _test_ace_count()
	print("[V30-MAP] failures=", _fails)
	get_tree().quit(0 if _fails == 0 else 1)


func _test_map(path: String, map_id: String, root_name: String, freestyle_only: bool) -> void:
	Global.menu_settings["selected_map"] = map_id
	Global.play_mode = Global.PlayMode.COMBAT if not freestyle_only else Global.PlayMode.TRAINING
	Global.special_mission = 0
	DroneCatalog.apply(0)
	var packed := load(path) as PackedScene
	_check(packed != null, "%s завантажується" % map_id)
	if packed == null:
		return
	var level := packed.instantiate()
	add_child(level)
	for _i in range(20):
		await get_tree().physics_frame
	var map_root := level.get_node_or_null("MapRoot")
	_check(map_root != null and map_root.get_child_count() > 0,
			"%s: геометрія карти інстанційована" % map_id)
	var authored := map_root.find_child(root_name, true, false) if map_root != null else null
	_check(authored != null, "%s: авторська сцена на MapRoot" % map_id)
	if map_id == "lis_forest_freestyle" and authored != null:
		var scatter := authored.find_child("ScatterMultiMesh", true, false)
		var instances := 0
		var trunk_chunks := 0
		if scatter != null:
			for mmi in scatter.find_children("*", "MultiMeshInstance3D", true, false):
				var mm := (mmi as MultiMeshInstance3D).multimesh
				if mm != null:
					instances += mm.instance_count
					if String(mmi.name).contains("pine") or String(mmi.name).contains("fir"):
						if String(mmi.name).ends_with("_p1"):
							trunk_chunks += 1
		_check(instances > 1500, "Ліс: розсіяні дерева/рослинність присутні (%d)" % instances)
		_check(trunk_chunks >= 4, "Ліс: стовбури хвойних відновлені (%d чанків)" % trunk_chunks)
		_check(is_equal_approx(float(level.call("_map_water_level")), -12.0),
				"Ліс: рівень води -12.0")
	elif map_id == "oilrig" and authored != null:
		var helipad := authored.find_child("Spawn_Helipad_P1", true, false) as Node3D
		_check(helipad != null and helipad.global_position.y >= 400.0,
				"OilRig: оригінальна висота геліпада >=400м (%s)" % [
						str(helipad.global_position.y) if helipad != null else "null"])
		_check(int(level.get("_rings_total")) == 0,
				"OilRig: без зайвих неонових кілець (_rings_total=%d)" % int(level.get("_rings_total")))
	var drone := level.get_node_or_null("Drone")
	_check(drone != null, "%s: дрон є" % map_id)
	if drone != null:
		var p: Vector3 = drone.global_position
		_check(not is_nan(p.x) and not is_nan(p.y) and not is_nan(p.z),
				"%s: позиція дрона без NaN" % map_id)
		_check(p.y > -50.0, "%s: дрон не під ґрунтом (y=%.2f)" % [map_id, p.y])
	var vehicles := get_tree().get_nodes_in_group("vehicle")
	var infantry := get_tree().get_nodes_in_group("enemy_infantry")
	if freestyle_only:
		_check(vehicles.is_empty(), "%s: техніки немає (%d)" % [map_id, vehicles.size()])
		_check(infantry.is_empty(), "%s: піхоти немає (%d)" % [map_id, infantry.size()])
	else:
		_check(vehicles.size() + infantry.size() > 0,
				"%s: бойові юніти створюються (техніка=%d піхота=%d)" % [
						map_id, vehicles.size(), infantry.size()])
		var kamikazes := get_tree().get_nodes_in_group("enemy_kamikaze")
		_check(kamikazes.size() == 1, "%s: OPERATOR — 1 камікадзе (%d)" % [
				map_id, kamikazes.size()])
	level.queue_free()
	for _f in range(3):
		await get_tree().process_frame


func _test_ace_count() -> void:
	Global.menu_settings["selected_map"] = "lis_forest_freestyle"
	Global.play_mode = Global.PlayMode.COMBAT
	Global.special_mission = 0
	Global.difficulty = Global.Difficulty.ACE
	DroneCatalog.apply(0)
	var packed := load("res://sceneries/LisLevel.tscn") as PackedScene
	if packed == null:
		return
	var level := packed.instantiate()
	add_child(level)
	for _i in range(12):
		await get_tree().physics_frame
	var kamikazes := get_tree().get_nodes_in_group("enemy_kamikaze")
	_check(kamikazes.size() == 2, "АС на Лісі — 2 камікадзе (%d)" % kamikazes.size())
	Global.difficulty = Global.Difficulty.OPERATOR
	level.queue_free()
	for _f in range(3):
		await get_tree().process_frame
