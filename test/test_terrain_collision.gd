extends Node3D

## QA-only collision audit for the procedural frontline terrain.
## Builds every map, raycasts a 50 m grid and reports missing terrain
## collision or surfaces that sit below the analytic height field.
##
## Run:
##   Godot --headless --path GodotDrone-master res://test/test_terrain_collision.tscn

const TERRAIN := preload("res://scripts/util/frontline_terrain.gd")
const MAPS := ["village", "industrial", "steppe", "wetlands"]
const STEP := 20
const EXTENT := 500


func _ready() -> void:
	await get_tree().process_frame
	var failed := false
	for map_name in MAPS:
		var root := Node3D.new()
		root.name = "CollisionProbe_" + map_name
		add_child(root)
		TERRAIN.build_terrain(root, map_name, 0.0)
		await get_tree().physics_frame
		await get_tree().physics_frame

		var space := get_world_3d().direct_space_state
		var total := 0
		var hits := 0
		var misses := 0
		var below := 0
		var worst := 0.0
		for z in range(-EXTENT, EXTENT + 1, STEP):
			for x in range(-EXTENT, EXTENT + 1, STEP):
				var query := PhysicsRayQueryParameters3D.create(
						Vector3(float(x), 400.0, float(z)),
						Vector3(float(x), -120.0, float(z)))
				query.collision_mask = 1
				var hit := space.intersect_ray(query)
				total += 1
				if hit.is_empty():
					misses += 1
					continue
				var collider := hit.get("collider") as Node
				if collider == null or not collider.is_in_group("terrain_collision"):
					continue
				hits += 1
				var y := (hit["position"] as Vector3).y
				var expected: float = TERRAIN.height_at(map_name, float(x), float(z))
				var delta := y - expected
				# A 4 m collision cell linearly interpolates the analytic field, so
				# crater rims can legally sit up to ~1.8 m below a point sample.
				# Only flag surfaces that are truly buried (missing/holes).
				if delta < -2.5:
					below += 1
					worst = minf(worst, delta)
		var ok := misses == 0 and below == 0
		failed = failed or not ok
		print("[COL] %s grid=%d terrain_hits=%d misses=%d below=%d worst=%.2fm %s"
				% [map_name, total, hits, misses, below, worst,
				"OK" if ok else "FAIL"])
		root.queue_free()
		await get_tree().process_frame
	print("[COL] RESULT ", "FAIL" if failed else "PASS")
	get_tree().quit(1 if failed else 0)
