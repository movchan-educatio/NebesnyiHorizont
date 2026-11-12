extends SceneTree

## Debug: settle every MobilePropPack site and report ground vs water, so the
## wetlands rejects (17/20) can be moved onto dry land.
func _init() -> void:
	var terrain = load("res://scripts/util/frontline_terrain.gd")
	var pack = load("res://scripts/util/mobile_prop_pack.gd")
	for map_name in ["wetlands"]:
		var wl: float = terrain.call("water_level", map_name)
		for entry in pack.SITES[map_name]:
			var base: Vector2 = entry[1]
			var site: Vector2 = terrain.call("_poi_site", map_name, base)
			var ground: float = terrain.call("mesh_surface_height", map_name, site.x, site.y)
			var ok := ground > wl + 0.7 and absf(site.x) <= 430.0 and absf(site.y) <= 430.0
			print("PROP_SITE ", map_name, " ", entry[0], " base=", base, " site=", site,
					" ground=%.2f water=%.2f ok=" % [ground, wl], ok)
	quit(0)
