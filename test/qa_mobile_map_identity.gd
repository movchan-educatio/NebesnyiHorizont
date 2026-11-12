extends Node3D

const TERRAIN = preload("res://scripts/util/frontline_terrain.gd")
var _failures := 0


func _ready() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	print("[MOBILE_MAP_IDENTITY] ", "PASS " if ok else "FAIL ", label)
	if not ok:
		_failures += 1


func _run() -> void:
	var names := {"steppe": "АГРОСКЛАД", "village": "СІЛЬСЬКИЙ СКЛАД",
			"industrial": "ЦЕХ 01", "wetlands": "ПРИЧАЛ"}
	var palette_source := {"grass_tint": Color.WHITE, "macro_contrast": 0.1}
	var observed_colours: Array[Color] = []
	for map_name in names:
		var palette: Dictionary = TERRAIN._mobile_ground_palette(map_name, palette_source)
		var tint: Color = palette["grass_tint"]
		_check(not observed_colours.has(tint), map_name + " has a distinct mobile ground tint")
		observed_colours.append(tint)
		_check(palette_source["grass_tint"] == Color.WHITE
				and palette_source["macro_contrast"] == 0.1,
				map_name + " mobile palette does not mutate source values")
		var hall := Node3D.new()
		add_child(hall)
		TERRAIN._add_mobile_hall_wayfinding(hall, map_name, 25.0, 20.0)
		var sign := hall.get_node_or_null("MobileHallWayfinding") as Node3D
		var text := sign.get_node_or_null("SignText") as Label3D if sign != null else null
		var panel := sign.get_node_or_null("SignPanel") as MeshInstance3D if sign != null else null
		_check(sign != null and text != null and text.text == names[map_name]
				and panel != null, map_name + " gets its contextual facade sign")
		_check(sign != null and sign.find_children("*", "CollisionObject3D", true, false).is_empty(),
				map_name + " sign adds no flight obstacle")
		TERRAIN._add_mobile_hall_wayfinding(hall, map_name, 25.0, 20.0)
		_check(hall.get_children().size() == 1, map_name + " sign is not duplicated")
		hall.free()
	print("[MOBILE_MAP_IDENTITY] failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)
