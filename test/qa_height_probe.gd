extends SceneTree

## QA helper: prints analytic and rendered-clipmap heights for camera planning.


func _init() -> void:
	var map_name := OS.get_environment("MAP").strip_edges().to_lower()
	if map_name.is_empty():
		map_name = "village"
	var terrain = load("res://scripts/util/frontline_terrain.gd")
	var points := []
	var raw := OS.get_environment("PROBE_POINTS")
	if not raw.is_empty():
		for pair in raw.split(";"):
			var parts := pair.split(",")
			if parts.size() == 2:
				points.append(Vector2(float(parts[0]), float(parts[1])))
	else:
		points = [Vector2(-100, 40), Vector2(0, 60), Vector2(100, 80),
				Vector2(310, -40), Vector2(265, 185), Vector2(-250, 120),
				Vector2(200, 70), Vector2(192, 114)]
	for p in points:
		print("[HEIGHT] ", map_name, " ", p, " analytic=",
				terrain.height_at(map_name, p.x, p.y), " mesh=",
				terrain.mesh_surface_height(map_name, p.x, p.y),
				" base=", terrain._base_height(map_name, p.x, p.y))
	print("[SITE] ", terrain.HALL_SITES.get(map_name, {}))
	quit()
