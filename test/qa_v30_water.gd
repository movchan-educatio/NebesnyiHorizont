extends Node
## QA: ground units on the forest map must never stand in the river.
const FrontlineTerrainScript = preload("res://scripts/util/frontline_terrain.gd")

var _fails := 0


func _check(ok: bool, label: String) -> void:
	if ok:
		print("[WATER-QA] PASS ", label)
	else:
		_fails += 1
		print("[WATER-QA] FAIL ", label)


func _ready() -> void:
	Global.menu_settings["selected_map"] = "lis_forest_freestyle"
	Global.play_mode = Global.PlayMode.COMBAT
	Global.special_mission = 0
	Global.drone_preset = 0
	DroneCatalog.apply(0)
	var packed := load("res://sceneries/LisLevel.tscn") as PackedScene
	var level := packed.instantiate()
	add_child(level)
	for _i in range(30):
		await get_tree().physics_frame
	var units: Array[Node3D] = []
	for n in get_tree().get_nodes_in_group("vehicle"):
		units.append(n as Node3D)
	for n in get_tree().get_nodes_in_group("enemy_infantry"):
		units.append(n as Node3D)
	var in_water := 0
	for u in units:
		if not is_instance_valid(u):
			continue
		var p := u.global_position
		if FrontlineTerrainScript.forest_is_water(p.x, p.z, p.y):
			in_water += 1
	_check(in_water == 0, "немає юнітів у річці на Лісі (%d/%d)" % [in_water, units.size()])
	_check(is_equal_approx(float(level.call("_map_water_level")), -12.0),
			"рівень води на Лісі = -12.0")
	print("[WATER-QA] failures=", _fails)
	level.queue_free()
	for _f in range(3):
		await get_tree().process_frame
	get_tree().quit(0 if _fails == 0 else 1)
