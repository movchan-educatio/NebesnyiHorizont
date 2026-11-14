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
		{"builder": "build_shipping_container_complex", "base": Vector2(124.0, 86.0),
			"yaw": 0.35, "reserve": 13.0, "clear": 20.0},
		{"builder": "build_pipeline_overpass", "base": Vector2(-112.0, -34.0),
			"yaw": 1.15, "reserve": 12.0, "clear": 18.0},
	],
	"village": [
		{"builder": "build_fpv_slalom_gate_course", "base": Vector2(128.0, 118.0),
			"yaw": 0.15, "reserve": 14.0, "clear": 22.0},
		{"builder": "build_damaged_hangar_arch", "base": Vector2(-118.0, 92.0),
			"yaw": -0.25, "reserve": 12.0, "clear": 18.0},
	],
	"steppe": [
		{"builder": "build_fpv_slalom_gate_course", "base": Vector2(-120.0, 110.0),
			"yaw": 0.0, "reserve": 14.0, "clear": 22.0},
		{"builder": "build_hardened_trench_bunker", "base": Vector2(118.0, -108.0),
			"yaw": 0.8, "reserve": 12.0, "clear": 18.0},
	],
	"wetlands": [
		{"builder": "build_concrete_pipe_culvert_course", "base": Vector2(-118.0, 96.0),
			"yaw": 0.4, "reserve": 13.0, "clear": 20.0},
		{"builder": "build_pipeline_overpass", "base": Vector2(116.0, -108.0),
			"yaw": 1.8, "reserve": 12.0, "clear": 18.0},
	],
}

const DRESS_ANCHORS := {
	"industrial": [Vector2(48, 124), Vector2(132, 62), Vector2(-84, 92),
			Vector2(-138, 18), Vector2(128, -78), Vector2(-142, 112)],
	"village": [Vector2(20, 74), Vector2(124, 72), Vector2(-128, 72),
			Vector2(142, 14), Vector2(88, -48), Vector2(-124, -108)],
	"steppe": [Vector2(66, 116), Vector2(-118, 88), Vector2(134, 68),
			Vector2(-138, 18), Vector2(88, -54), Vector2(136, 132)],
	"wetlands": [Vector2(18, 68), Vector2(122, 84), Vector2(-128, 42),
			Vector2(132, -26), Vector2(-82, -116), Vector2(-136, 128)],
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
	"industrial": [Vector2(-105, -98), Vector2(0, -15), Vector2(-92, 56)],
	"village": [Vector2(54, -96), Vector2(36, 58), Vector2(126, 96)],
	"steppe": [Vector2(36, 128), Vector2(76, -78), Vector2(142, -52)],
	"wetlands": [Vector2(-56, -118), Vector2(8, 146), Vector2(18, 22)],
}

## Mobile-only extra dressing anchors inside the compact 384 m playable arena.
const MOBILE_EXTRA_ANCHORS := {
	"industrial": [Vector2(140, 125), Vector2(-140, -135)],
	"village": [Vector2(135, -132), Vector2(-142, 132)],
	"steppe": [Vector2(138, 136), Vector2(-140, -128)],
	"wetlands": [Vector2(-140, 128), Vector2(138, -132)],
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
		var site := _find_reserved_site(terrain, military, root, map_name,
				spec["base"], float(spec.get("clear", 20.0)),
				float(spec.get("reserve", 13.0)))
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
			terrain.reserve_area(site, float(spec.get("clear", 20.0)))
			terrain.add_contact_shadow(root, map_name, site, 14.0, node.name)
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
		var p := Vector2(rng.randf_range(-152.0, 152.0),
				rng.randf_range(-152.0, 152.0))
		if _is_clear_prop(terrain, military, map_name, p.x, p.y, 6.0):
			anchors.append(p)
	if anchors.is_empty():
		anchors.append(Vector2(0.0, 100.0))
	var mesh_set := PropAssets.meshes()
	var names: Array = DRESS_PROPS.get(map_name, []).filter(
			func(n): return mesh_set.has(str(n)))
	var budget := 4 if q == QualityManager.Level.LOW else \
			(6 if q == QualityManager.Level.MEDIUM else 8)
	var placed_dress: Array[Vector2] = []
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
			if not _is_clear_prop(terrain, military, map_name, p.x, p.y, 4.0):
				continue
			var overlap := false
			for prev in placed_dress:
				if p.distance_to(prev) < 7.5:
					overlap = true
					break
			if overlap:
				continue
			placed_dress.append(p)
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
	_add_road_markers(terrain, root, map_name, q)
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


static func _find_reserved_site(terrain, military, root: Node3D, map_name: String,
		base: Vector2, clearance: float, reserve_radius: float) -> Vector2:
	for ring in range(0, 10):
		var radius := 0.0 if ring == 0 else 16.0 * float(ring)
		var steps := 1 if ring == 0 else 16
		for i in range(steps):
			var a := TAU * float(i) / float(steps) + float(ring) * 0.35
			var p := base + Vector2(cos(a), sin(a)) * radius
			if absf(p.x) > 158.0 or absf(p.y) > 158.0:
				continue
			if not _is_clear_prop(terrain, military, map_name, p.x, p.y, clearance):
				continue
			if bool(terrain.try_reserve_structure(root, map_name, p,
					reserve_radius, 28.0, false)):
				return p
	return Vector2(-9999.0, -9999.0)


static func _add_road_markers(terrain, root: Node3D, map_name: String, q: int) -> void:
	var xfs: Array[Transform3D] = []
	var water := float(terrain.water_level(map_name))
	var roads: Array = terrain._road_points(map_name)
	for line in roads:
		var pts: PackedVector2Array = line
		for i in range(pts.size() - 1):
			var a := pts[i]
			var b := pts[i + 1]
			var seg := b - a
			var len_seg := seg.length()
			if len_seg < 12.0:
				continue
			var dir := seg / len_seg
			var perp := Vector2(-dir.y, dir.x)
			var dist := 16.0
			var side := 1.0
			while dist < len_seg - 8.0:
				var mp := a + dir * dist + perp * (side * 8.2)
				side = -side
				dist += 34.0
				if absf(mp.x) > 158.0 or absf(mp.y) > 158.0:
					continue
				if terrain._hall_clear_zone(map_name, mp.x, mp.y) \
						or terrain._structure_clear_zone(map_name, mp.x, mp.y):
					continue
				if float(terrain._road_factor(map_name, mp.x, mp.y)) > 0.55:
					continue
				var gy := float(terrain.mesh_surface_height(map_name, mp.x, mp.y))
				if gy < water + 0.35:
					continue
				var yaw := atan2(dir.x, dir.y)
				xfs.append(Transform3D(Basis(Vector3.UP, yaw),
						Vector3(mp.x, gy + 1.15, mp.y)))
	if xfs.is_empty():
		return
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.08
	post_mesh.bottom_radius = 0.11
	post_mesh.height = 2.4
	post_mesh.radial_segments = 6
	post_mesh.rings = 1
	var post_mat: Material = terrain._pbr("wood", Color(0.56, 0.46, 0.34), 0.35)
	var mmi: MultiMeshInstance3D = terrain._multimesh(root,
			"BattleDressing_RoadMarkers", post_mesh, post_mat, xfs, false)
	if mmi != null:
		mmi.visibility_range_end = 420.0 if q == QualityManager.Level.LOW else 680.0
		mmi.visibility_range_end_margin = 40.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


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
	if absf(x) > 158.0 or absf(z) > 158.0:
		return false
	if float(terrain._road_factor(map_name, x, z)) >= 0.22:
		return false
	if terrain._hall_clear_zone(map_name, x, z):
		return false
	if terrain._structure_clear_zone(map_name, x, z, clearance):
		return false
	if terrain._farm_clear_zone(map_name, x, z):
		return false
	var water := float(terrain.water_level(map_name))
	var ground := float(terrain.mesh_surface_height(map_name, x, z))
	if ground < water + 0.75:
		return false
	# Keep clear of the authored handcrafted pads.
	for c in HANDCRAFTED_AVOID.get(map_name, []):
		if Vector2(x, z).distance_to(c) < 42.0:
			return false
	for poi in terrain._poi_positions:
		if Vector2(x, z).distance_to(poi) < maxf(28.0, clearance):
			return false
	# Do not drop crates in the middle of a road.  Stunt footprints need a much
	# larger berth so a slalom run cannot straddle the carriageway.
	if _near_road(terrain, map_name, Vector2(x, z), maxf(9.0, minf(clearance, 18.0))):
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
	if clearance > 20.0:
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
