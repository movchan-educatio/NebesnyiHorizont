class_name MapEnricher
extends RefCounted

## One-pass tactical enrichment for the four frontline maps.
##
## Adds:
##   * a curated FPV stunt set per map (slalom gates, container canyon, pipe
##     culvert, pipeline overpass, bunker/arch) using the existing low-poly
##     military kit and its collision;
##   * clustered battlefield dressing (crates, barrels, ammo, sandbags, tires,
##     camo nets, pallets) using one MultiMesh per prop type, so hundreds of
##     pieces cost at most one draw call each;
##   * scorch marks around the clusters.
##
## Everything is placed against the rendered clipmap height, avoids halls,
## POIs, military structures, roads and water, and registers its footprint so
## the later tree/prop/world-detail passes do not grow through it.
## Visual batching runs afterward; collisions stay on the authored stunt kit.

const STUNTS := {
	"industrial": [
		{"builder": "build_shipping_container_complex", "base": Vector2(158.0, 102.0),
			"yaw": 0.35, "reserve": 34.0},
		{"builder": "build_pipeline_overpass", "base": Vector2(-118.0, 32.0),
			"yaw": 1.15, "reserve": 30.0},
	],
	"village": [
		{"builder": "build_fpv_slalom_gate_course", "base": Vector2(198.0, 118.0),
			"yaw": 0.15, "reserve": 42.0},
		{"builder": "build_damaged_hangar_arch", "base": Vector2(-162.0, 108.0),
			"yaw": -0.25, "reserve": 30.0},
	],
	"steppe": [
		{"builder": "build_fpv_slalom_gate_course", "base": Vector2(72.0, 198.0),
			"yaw": 0.0, "reserve": 42.0},
		{"builder": "build_hardened_trench_bunker", "base": Vector2(-152.0, 168.0),
			"yaw": 0.8, "reserve": 28.0},
	],
	"wetlands": [
		{"builder": "build_concrete_pipe_culvert_course", "base": Vector2(-148.0, 104.0),
			"yaw": 0.4, "reserve": 34.0},
		{"builder": "build_pipeline_overpass", "base": Vector2(138.0, -124.0),
			"yaw": 1.8, "reserve": 30.0},
	],
}

const DRESS_ANCHORS := {
	"industrial": [Vector2(48, 128), Vector2(172, 66), Vector2(-84, 96),
			Vector2(-178, 18), Vector2(148, -82), Vector2(-212, 118)],
	"village": [Vector2(20, 74), Vector2(138, 72), Vector2(-168, 74),
			Vector2(218, 12), Vector2(92, -48), Vector2(-132, -118)],
	"steppe": [Vector2(66, 122), Vector2(-136, 92), Vector2(182, 74),
			Vector2(-188, 18), Vector2(92, -56), Vector2(212, 178)],
	"wetlands": [Vector2(18, 70), Vector2(132, 88), Vector2(-148, 44),
			Vector2(162, -28), Vector2(-86, -126), Vector2(-168, 158)],
}

const DRESS_PROPS := {
	"industrial": ["prop_crate", "prop_barrel", "prop_pipe", "prop_tires",
			"prop_pallet", "prop_generator", "prop_fuel_tank", "prop_ammo",
			"prop_camo_net", "prop_barrier"],
	"village": ["prop_crate", "prop_barrel", "prop_hay", "prop_logs",
			"prop_fence", "prop_tires", "prop_ammo", "prop_pallet",
			"prop_sandbags", "prop_car_wreck"],
	"steppe": ["prop_ammo", "prop_crate", "prop_barrel", "prop_sandbags",
			"prop_tires", "prop_logs", "prop_fence", "prop_antenna",
			"prop_generator", "prop_car_wreck"],
	"wetlands": ["prop_barrel", "prop_crate", "prop_pallet", "prop_tires",
			"prop_pipe", "prop_camo_net", "prop_tent", "prop_sandbags",
			"prop_ammo", "prop_generator"],
}

const HANDCRAFTED_AVOID := {
	"industrial": [Vector2(-200, -180), Vector2(0, -15), Vector2(-125, 80)],
	"village": [Vector2(60, -110), Vector2(36, 58), Vector2(126, 96)],
	"steppe": [Vector2(40, 146), Vector2(225, -40), Vector2(245, -58)],
	"wetlands": [Vector2(-60, -140), Vector2(6, 60), Vector2(18, 22)],
}

## Mobile-only extra dressing anchors: two more themed clusters per map so the
## open fields between landmarks never read as empty. Placement still goes
## through the normal clear checks and the same MultiMesh batching.
const MOBILE_EXTRA_ANCHORS := {
	"industrial": [Vector2(225, 165), Vector2(-220, -195)],
	"village": [Vector2(215, -195), Vector2(-225, 195)],
	"steppe": [Vector2(215, 205), Vector2(-230, -195)],
	"wetlands": [Vector2(-235, 165), Vector2(215, -195)],
}


static func build(root: Node3D, map_name: String, quality: int = -1) -> void:
	if root == null or not STUNTS.has(map_name):
		return
	var terrain = load("res://scripts/util/frontline_terrain.gd")
	var military = load("res://scripts/util/military_structures.gd")
	if terrain == null or military == null:
		return
	var q := quality
	if q < 0:
		q = QualityManager.get_active_level()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(map_name) * 977 + 41
	var stunt_sites: Array[Vector2] = []
	for spec in STUNTS[map_name]:
		var site := _find_site(terrain, military, map_name,
				spec["base"], float(spec["reserve"]) * 0.7)
		if site.x < -900.0:
			continue
		var yaw := float(spec["yaw"])
		var gy := float(terrain.footprint_surface_height(map_name, site,
				30.0, 24.0, yaw)) - 0.20
		var node: Node3D = _build_stunt(military, String(spec["builder"]), root,
				Vector3(site.x, gy, site.y), yaw)
		if node != null:
			node.name = "Enriched_" + String(node.name)
			stunt_sites.append(site)
			terrain.reserve_area(site, float(spec["reserve"]))
	# Battle-Dressing clusters are anchored around the stunts and the authored
	# road/farm hotspots, giving every map a lived-in layered foreground.
	var anchors: Array[Vector2] = []
	anchors.append_array(stunt_sites)
	for a in DRESS_ANCHORS.get(map_name, []):
		var av: Vector2 = a
		if _is_clear_prop(terrain, military, map_name, av.x, av.y, 5.0):
			anchors.append(av)
	if OS.get_name() == "iOS" or OS.has_feature("mobile") \
			or OS.has_environment("MOBILE_UI"):
		for a in MOBILE_EXTRA_ANCHORS.get(map_name, []):
			var av: Vector2 = a
			if _is_clear_prop(terrain, military, map_name, av.x, av.y, 5.0):
				anchors.append(av)
	# Keep the clutter spread over the map even when authored anchors happen to
	# sit inside a larger hall/farm/military clear radius.
	var anchor_tries := 0
	while anchors.size() < 6 and anchor_tries < 220:
		anchor_tries += 1
		var p := Vector2(rng.randf_range(-245.0, 245.0),
				rng.randf_range(-245.0, 245.0))
		if _is_clear_prop(terrain, military, map_name, p.x, p.y, 6.0):
			anchors.append(p)
	if anchors.is_empty():
		anchors.append(Vector2(0.0, 100.0))
	var mesh_set := PropAssets.meshes()
	var names: Array = DRESS_PROPS.get(map_name, []).filter(
			func(n): return mesh_set.has(str(n)))
	var budget := 7 if q == QualityManager.Level.LOW else \
			(15 if q == QualityManager.Level.MEDIUM else 24)
	if OS.get_name() == "iOS" or OS.has_feature("mobile") \
			or OS.has_environment("MOBILE_UI"):
		budget = int(round(budget * 1.3))
	var placed := 0
	for prop_name in names:
		var mesh: Mesh = mesh_set[str(prop_name)]
		var mat := _dress_material(terrain, str(prop_name))
		var xfs: Array[Transform3D] = []
		var tries := budget * 12
		while xfs.size() < budget and tries > 0:
			tries -= 1
			var anchor: Vector2 = anchors[rng.randi_range(0, anchors.size() - 1)]
			var radius := rng.randf_range(6.0, 30.0)
			var ang := rng.randf_range(0.0, TAU)
			var p := anchor + Vector2(cos(ang), sin(ang)) * radius
			if not _is_clear_prop(terrain, military, map_name, p.x, p.y, 3.0):
				continue
			var support := float(terrain.mesh_surface_height(map_name, p.x, p.y))
			var s := rng.randf_range(0.82, 1.22)
			var sy := rng.randf_range(0.9, 1.15) * s
			var aabb := mesh.get_aabb()
			# Put the visible bottom on the rendered surface; this also works
			# for library meshes whose pivot is at the centre instead of base.
			var y := support - aabb.position.y * sy + 0.02
			var b := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(
					Vector3(s, sy, s))
			xfs.append(Transform3D(b, Vector3(p.x, y, p.y)))
		if xfs.is_empty():
			continue
		var node: MultiMeshInstance3D = terrain._multimesh(root,
				"BattleDressing_" + str(prop_name), mesh, mat, xfs, false)
		if node != null:
			node.visibility_range_end = 520.0 if q == QualityManager.Level.LOW else 820.0
			node.visibility_range_end_margin = 50.0
			node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			placed += xfs.size()
	print("[MapEnricher] ", map_name, " stunts=", stunt_sites.size(),
			" dressing=", placed, " anchors=", anchors.size())
	if OS.has_environment("DRONE_ENRICH_DEBUG"):
		print("[MapEnricher] stunt_sites=", stunt_sites)
		print("[MapEnricher] anchors=", anchors)


static func _dress_material(terrain, prop_name: String) -> Material:
	# Reuse the map PBR families per prop type instead of a single flat
	# vertex-colour material.  One material per type still means one draw call
	# per MultiMesh, but crates now read as timber and drums as painted steel.
	match prop_name:
		"prop_crate", "prop_pallet", "prop_logs", "prop_fence":
			return terrain._pbr("wood", Color(0.76, 0.66, 0.52), 0.24)
		"prop_hay":
			return terrain._pbr("wood", Color(0.90, 0.78, 0.50), 0.20)
		"prop_barrel", "prop_oil_drum", "prop_generator", "prop_pipe", "prop_antenna", "prop_ammo", "prop_barrier", "prop_fuel_tank":
			return terrain._pbr("hall_metal", Color(0.58, 0.60, 0.60), 0.16)
		"prop_car_wreck":
			return terrain._pbr("hall_rust", Color(0.72, 0.55, 0.44), 0.22)
		"prop_tires":
			return terrain._pbr("asphalt", Color(0.22, 0.22, 0.23), 0.24)
		"prop_sandbags":
			return terrain._pbr("sandbag", Color(0.88, 0.80, 0.62), 0.28)
		"prop_camo_net", "prop_tent":
			return terrain._pbr("hall_moss", Color(0.46, 0.53, 0.34), 0.32)
		_:
			var m := StandardMaterial3D.new()
			m.vertex_color_use_as_albedo = true
			m.roughness = 0.90
			m.metallic = 0.08
			return m


static func _find_site(terrain, military, map_name: String, base: Vector2,
		clearance: float) -> Vector2:
	for ring in range(0, 9):
		var radius := 0.0 if ring == 0 else 18.0 * float(ring)
		var steps := 1 if ring == 0 else 16
		for i in range(steps):
			var a := TAU * float(i) / float(steps) + float(ring) * 0.3
			var p := base + Vector2(cos(a), sin(a)) * radius
			if _is_clear_prop(terrain, military, map_name, p.x, p.y, clearance):
				return p
	return Vector2(-9999.0, -9999.0)


static func _is_clear_prop(terrain, military, map_name: String, x: float,
		z: float, clearance: float) -> bool:
	if absf(x) > 265.0 or absf(z) > 265.0:
		return false
	if terrain._hall_clear_zone(map_name, x, z):
		return false
	if terrain._structure_clear_zone(map_name, x, z):
		return false
	if terrain._farm_clear_zone(map_name, x, z):
		return false
	var water := float(terrain.water_level(map_name))
	var ground := float(terrain.mesh_surface_height(map_name, x, z))
	if ground < water + 0.75:
		return false
	# Keep clear of the authored handcrafted pads.
	for c in HANDCRAFTED_AVOID.get(map_name, []):
		if Vector2(x, z).distance_to(c) < 48.0:
			return false
	for poi in terrain._poi_positions:
		if Vector2(x, z).distance_to(poi) < maxf(30.0, clearance):
			return false
	# Do not drop crates in the middle of a road.  Stunt footprints need a much
	# larger berth so a 56 m slalom run cannot straddle the carriageway.
	if _near_road(terrain, map_name, Vector2(x, z), maxf(11.0, clearance)):
		return false
	# Keep the stunt footprint from straddling a cliff.
	var e := 7.0
	var h0 := float(terrain.mesh_surface_height(map_name, x - e, z))
	var h1 := float(terrain.mesh_surface_height(map_name, x + e, z))
	var h2 := float(terrain.mesh_surface_height(map_name, x, z - e))
	var h3 := float(terrain.mesh_surface_height(map_name, x, z + e))
	if maxf(maxf(h0, h1), maxf(h2, h3)) - minf(minf(h0, h1), minf(h2, h3)) > 7.5:
		return false
	# Existing military/POI positions have a 24 m radius; the caller-provided
	# clearance protects the actual stunt footprint.
	if clearance > 24.0:
		for pos in military.spawned_positions.get(map_name, []):
			if Vector2(x, z).distance_to(pos) < clearance:
				return false
	return true


static func _build_stunt(military, builder: String, root: Node3D, pos: Vector3,
		yaw: float) -> Node3D:
	match builder:
		"build_shipping_container_complex":
			return military.build_shipping_container_complex(root, pos, yaw)
		"build_pipeline_overpass":
			return military.build_pipeline_overpass(root, pos, yaw)
		"build_fpv_slalom_gate_course":
			return military.build_fpv_slalom_gate_course(root, pos, yaw)
		"build_damaged_hangar_arch":
			return military.build_damaged_hangar_arch(root, pos, yaw)
		"build_hardened_trench_bunker":
			return military.build_hardened_trench_bunker(root, pos, yaw)
		"build_concrete_pipe_culvert_course":
			return military.build_concrete_pipe_culvert_course(root, pos, yaw)
	return null


static func _near_road(terrain, map_name: String, p: Vector2, dist: float) -> bool:
	var roads: Array = terrain._road_points(map_name)
	for line in roads:
		var pts: PackedVector2Array = line
		for i in range(pts.size() - 1):
			var closest := Geometry2D.get_closest_point_to_segment(p,
					pts[i], pts[i + 1])
			if closest.distance_to(p) < dist:
				return true
	return false
