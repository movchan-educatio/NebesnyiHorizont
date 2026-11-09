extends SceneTree

func _initialize() -> void:
	var t = load("res://scripts/util/frontline_terrain.gd")
	for map_name in ["village", "industrial", "steppe", "wetlands"]:
		print("--- ", map_name, " water=", t.water_level(map_name))
		for p in [Vector2(0, 0), Vector2(0, 100), Vector2(-16, 44), Vector2(90, 92),
				Vector2(60, 100), Vector2(-60, 40), Vector2(20, 120),
				Vector2(120, 60), Vector2(200, 132), Vector2(-230, 20),
				Vector2(250, 15), Vector2(-162, 192), Vector2(40, -90),
				Vector2(-120, -40), Vector2(24, 176), Vector2(84, 126),
				Vector2(-42, -172), Vector2(-124, 96), Vector2(260, -70)]:
			var h: float = t.height_at(map_name, p.x, p.y)
			print("  ", p, " h=", "%.2f" % h)
	quit()
