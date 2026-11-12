extends SceneTree

## Debug: print terrain heights at the four new MobileHero3 sites so their
## placement can be sanity-checked against the water level before QA screenshots.
func _init() -> void:
	var terrain = load("res://scripts/util/frontline_terrain.gd")
	var sites := {
		"steppe": [Vector2(-350.0, -60.0)],
		"village": [Vector2(340.0, -140.0)],
		"industrial": [Vector2(-360.0, 140.0)],
		"wetlands": [Vector2(200.0, -240.0)],
	}
	for map_name in sites:
		var wl: float = terrain.water_level(map_name)
		for p: Vector2 in sites[map_name]:
			var h: float = terrain._height(map_name, p.x, p.y)
			print("POI_HEIGHT map=", map_name, " at=", p, " ground=", h,
					" water=", wl, " dry=", h > wl + 0.9)
	quit(0)
