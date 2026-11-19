extends Node

## Verifies that kinematic AI vehicles never cross large hall/workshop meshes
## and keep moving past them.  Uses the industrial map's hero hall (roof 22 m).

const VehicleScript = preload("res://combat/vehicle.gd")
const TerrainScript = preload("res://scripts/util/frontline_terrain.gd")

var _failures := 0

func _check(value: bool, label: String) -> void:
	if value:
		print("[STRUCT] PASS ", label)
	else:
		printerr("[STRUCT] FAIL ", label)
		_failures += 1


func _inside(pos: Vector3, e: Dictionary) -> bool:
	var c: Vector2 = e.get("center", Vector2.ZERO)
	var h: Vector2 = e.get("half", Vector2.ZERO)
	return absf(pos.x - c.x) < h.x and absf(pos.z - c.y) < h.y


func _make_vehicle(level: Node, kind: int, from: Vector3, speed: float,
		alt: float) -> Vehicle:
	var v := VehicleScript.new()
	v.kind = kind
	v.hostile = true
	v.move_speed = speed
	v.cruise_height = alt
	# Keep test vehicles on their route instead of halting to engage the drone.
	v.fire_range = 0.0
	level.add_child(v)
	v.global_position = from
	v.set_waypoints([from, Vector3(130.0, 0.0, from.z)])
	return v


func _ready() -> void:
	Global.play_mode = Global.PlayMode.COMBAT
	Global.special_mission = 0
	Global.combat_mission = 1
	var level = load("res://sceneries/IndustrialLevel.tscn").instantiate()
	add_child(level)
	await get_tree().create_timer(4.0).timeout

	var exclusions: Array[Dictionary] = TerrainScript.structure_exclusions()
	_check(exclusions.size() > 0, "structure exclusions registered (%d)" % exclusions.size())
	if exclusions.is_empty():
		get_tree().quit(1)
		return
	for e in exclusions:
		print("[STRUCT] zone center=", e.get("center"), " half=", e.get("half"),
				" top=", e.get("top"))
	var hall: Dictionary = exclusions[0]

	var heli := _make_vehicle(level, VehicleScript.Kind.HELI,
			Vector3(-120.0, 24.0, 68.0), 18.0, 21.0)
	var shahed := _make_vehicle(level, VehicleScript.Kind.SHAHED,
			Vector3(-120.0, 24.0, 74.0), 18.0, 21.0)
	var bmp := _make_vehicle(level, VehicleScript.Kind.BMP,
			Vector3(-120.0, 0.0, 68.0), 10.0, 0.0)

	var violations := {"heli": 0, "shahed": 0, "bmp": 0}
	var min_heli_y_over_hall := 1.0e9
	for i in range(900):
		await get_tree().physics_frame
		if _inside(heli.global_position, hall):
			min_heli_y_over_hall = minf(min_heli_y_over_hall,
					heli.global_position.y)
		for e in exclusions:
			for key in violations.keys():
				var v: Vehicle = {"heli": heli, "shahed": shahed, "bmp": bmp}[key]
				if not is_instance_valid(v):
					continue
				if v.global_position.y > float(e.get("top", 0.0)) + 4.0:
					continue
				if _inside(v.global_position, e):
					violations[key] += 1

	for key in violations.keys():
		_check(int(violations[key]) == 0, "%s never enters hall (%d frames)" % [key, violations[key]])

	# Over the hall the helicopter must climb above the arched roof.
	_check(min_heli_y_over_hall >= float(hall.get("top", 0.0)) + 8.0,
			"heli climbs above arched roof (min y=%.1f, roof=%.1f)" % [
			min_heli_y_over_hall, float(hall.get("top", 0.0))])

	# Vehicles must still make progress toward the far waypoint.
	_check(heli.global_position.x > -40.0, "heli keeps moving past hall (x=%.1f)" % heli.global_position.x)
	_check(shahed.global_position.x > -40.0, "shahed keeps moving past hall (x=%.1f)" % shahed.global_position.x)
	_check(bmp.global_position.x > -60.0, "bmp keeps moving past hall (x=%.1f)" % bmp.global_position.x)

	print("[STRUCT] failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)
