class_name MobilePropPack
extends RefCounted

## Curated low-poly prop pack + five large landmarks for the four frontline
## maps.  Small props come from tools/build_map_props.py, landmarks from
## tools/build_map_landmarks.py.  A third layer adds ten hand-sculpted
## war-wear GLBs per map from tools/asset_forge (baked albedo, two LOD steps).
##
## Placement guarantees (also re-checked by qa_mobile_map_views):
##   * every object sits on the terrain height (no floating, no sinking),
##   * objects keep a real gap from each other and from existing POIs,
##   * small props get box colliders, landmarks keep their hollow -colonly
##     collision so the drone can fly inside and do stunts,
##   * low draw-call cost: one vertex-colour material per asset + distance LOD.
const PROP_ROOT := "res://Assets/handcrafted/props_lowpoly/"
const LANDMARK_ROOT := "res://Assets/handcrafted/landmarks/"
const FORGE_ROOT := "res://Assets/handcrafted/forge/"
const FrontlineTerrainScript = preload("res://scripts/util/frontline_terrain.gd")

const LOD_END := {
	"watchtower": 900.0, "water_tower_small": 900.0, "antenna_mast": 950.0,
	"billboard_ruined": 800.0, "silo_small": 850.0, "barn_small": 750.0,
	"container_stack": 650.0, "truck_wreck": 600.0, "apc_wreck": 600.0,
	"bus_stop": 520.0, "checkpoint_booth": 520.0, "greenhouse": 520.0,
	"well_house": 480.0, "haystack": 400.0, "fuel_barrels": 340.0,
	"ammo_crates": 320.0, "sandbag_nest": 380.0, "power_pole": 700.0,
	"tent_military": 420.0, "jersey_barriers": 360.0, "tank_traps": 300.0,
	"fence_section": 320.0, "ruined_wall": 420.0,
}

const LANDMARK_LOD := 1500.0

## [prop, Vector2(x, z), yaw degrees, scale]
const SITES := {
	"steppe": [
		["checkpoint_booth", Vector2(138, 132), 15.0, 1.0],
		["sandbag_nest", Vector2(118, 126), 40.0, 1.0],
		["watchtower", Vector2(-132, 108), 0.0, 1.0],
		["power_pole", Vector2(-124, 84), 0.0, 1.0],
		["haystack", Vector2(-82, 134), 30.0, 1.0],
		["haystack", Vector2(22, 140), 10.0, 1.0],
		["silo_small", Vector2(-114, 138), 0.0, 1.0],
		["greenhouse", Vector2(62, 136), 0.0, 1.0],
		["truck_wreck", Vector2(132, 82), 35.0, 1.0],
		["antenna_mast", Vector2(142, 52), 0.0, 1.0],
		["tank_traps", Vector2(118, 32), 0.0, 1.0],
		["ruined_wall", Vector2(-140, 28), 20.0, 1.0],
	],
	"village": [
		["bus_stop", Vector2(-118, 122), 10.0, 1.0],
		["well_house", Vector2(-134, 82), 0.0, 1.0],
		["haystack", Vector2(136, 114), 0.0, 1.0],
		["fence_section", Vector2(-136, 20), 0.0, 1.0],
		["power_pole", Vector2(140, -16), 0.0, 1.0],
		["truck_wreck", Vector2(112, 124), 30.0, 1.0],
		["water_tower_small", Vector2(-142, 136), 0.0, 1.0],
		["greenhouse", Vector2(88, 138), 0.0, 1.0],
		["checkpoint_booth", Vector2(-84, 138), 0.0, 1.0],
		["tent_military", Vector2(138, 72), 20.0, 1.0],
		["ruined_wall", Vector2(96, -122), 60.0, 1.0],
		["watchtower", Vector2(14, 140), 0.0, 1.0],
	],
	"industrial": [
		["container_stack", Vector2(138, 118), 0.0, 1.0],
		["truck_wreck", Vector2(114, 134), 30.0, 1.0],
		["apc_wreck", Vector2(-134, 126), 15.0, 1.0],
		["fuel_barrels", Vector2(132, 88), 0.0, 1.0],
		["checkpoint_booth", Vector2(-138, 92), 0.0, 1.0],
		["fence_section", Vector2(-112, 138), 0.0, 1.0],
		["fence_section", Vector2(98, -132), 0.0, 1.0],
		["power_pole", Vector2(-138, 28), 0.0, 1.0],
		["antenna_mast", Vector2(142, 46), 0.0, 1.0],
		["jersey_barriers", Vector2(132, 14), 15.0, 1.0],
		["tank_traps", Vector2(118, -28), 0.0, 1.0],
		["water_tower_small", Vector2(142, -52), 0.0, 1.0],
	],
	"wetlands": [
		["watchtower", Vector2(138, 126), 0.0, 1.0],
		["bus_stop", Vector2(-128, 128), 10.0, 1.0],
		["fence_section", Vector2(-140, 98), 0.0, 1.0],
		["power_pole", Vector2(-104, 140), 0.0, 1.0],
		["haystack", Vector2(112, 138), 30.0, 1.0],
		["barn_small", Vector2(-142, 64), 0.0, 1.0],
		["well_house", Vector2(-134, 34), 0.0, 1.0],
		["truck_wreck", Vector2(130, 96), 20.0, 1.0],
		["checkpoint_booth", Vector2(-78, 138), 0.0, 1.0],
		["ruined_wall", Vector2(-140, -82), 0.0, 1.0],
		["antenna_mast", Vector2(132, -98), 0.0, 1.0],
		["tank_traps", Vector2(84, 136), 0.0, 1.0],
	],
}

## Two perimeter landmarks per map in open outer corners: [landmark, Vector2(x, z), yaw degrees]
const LARGE_SITES := {
	"steppe": [
		["warehouse", Vector2(138, 138), 200.0],
		["fuel_depot", Vector2(78, -136), 45.0],
	],
	"village": [
		["warehouse", Vector2(-128, -126), 120.0],
		["fuel_depot", Vector2(134, -128), 0.0],
	],
	"industrial": [
		["warehouse", Vector2(134, 120), 200.0],
		["fuel_depot", Vector2(136, -134), 30.0],
	],
	"wetlands": [
		["cargo_ship", Vector2(98, -88), 15.0],
		["warehouse", Vector2(132, 134), 210.0],
	],
}

## Four hand-sculpted war-wear GLBs per map (one per quadrant, well separated).
## [glb, Vector2(x, z), yaw degrees]
const FORGE_SITES := {
	"steppe": [
		["steppe_01_lep_pylon_leaning", Vector2(-64, 44), 20.0],
		["steppe_03_lep_collapsed_arch", Vector2(58, -44), 15.0],
		["steppe_12_bunker_dot_breached", Vector2(118, 24), 0.0],
		["steppe_29_concrete_slab_fort", Vector2(-118, -96), 45.0],
	],
	"village": [
		["village_01_khata_breached_roof", Vector2(-82, 88), 10.0],
		["village_13_brick_church_belfry", Vector2(48, 114), 0.0],
		["village_15_river_bridge_wooden", Vector2(-36, -118), 15.0],
		["village_27_windmill_timber_frame", Vector2(108, -54), 0.0],
	],
	"industrial": [
		["industrial_04_gantry_crane_portal", Vector2(116, -48), 45.0],
		["industrial_10_pipe_rack_overpass", Vector2(-18, -68), 90.0],
		["industrial_19_loading_ramp_canopy", Vector2(122, 68), 180.0],
		["industrial_23_hangar_rib_tunnel", Vector2(-48, -124), 0.0],
	],
	"wetlands": [
		["swamp_01_flooded_pumping_station", Vector2(-56, 116), 0.0],
		["swamp_03_half_sunk_river_barge", Vector2(-90, -46), 15.0],
		["swamp_04_wooden_trestle_causeway", Vector2(28, -118), 0.0],
		["swamp_09_rotting_watchtower_marsh", Vector2(108, -46), 0.0],
	],
}

## Long, open assets where the drone must be able to punch through a portal
## or under a deck.  They get a low base collider instead of a solid box.
const FORGE_OPEN_HINTS := [
	"arch", "bridge", "portal", "gate", "span", "tunnel", "overpass",
	"gantry", "canopy", "hangar", "trestle", "viaduct", "pipe_rack",
	"conveyor", "gallery", "causeway", "lock", "spillway", "stairwell",
	"frame", "skeleton", "truss", "boom", "pergola", "arcade", "portico",
	"belfry", "tower", "breached", "holed", "split", "collapsed", "ruined",
	"wreck", "slalom", "open",
]

static var _scenes := {}
static var _materials := {}
static var _radii := {}


static func build(root: Node3D, map_name: String) -> Node3D:
	if root == null or not SITES.has(map_name):
		return null
	var terrain = load("res://scripts/util/frontline_terrain.gd")
	var pack := Node3D.new()
	pack.name = "MobilePropPack"
	pack.set_meta("no_batch", true)
	root.add_child(pack)
	var placed: Array[Dictionary] = []
	# Place landmarks & forge assets before small props so large footprints claim
	# open corridors cleanly within ±155 m.
	for entry in LARGE_SITES.get(map_name, []):
		_place(root, pack, terrain, map_name, entry, placed, true)
	var forge_count := 0
	for entry in FORGE_SITES.get(map_name, []):
		if _place_forge(root, pack, terrain, map_name, entry, placed):
			forge_count += 1
	for entry in SITES[map_name]:
		_place(root, pack, terrain, map_name, entry, placed, false)
	pack.set_meta("placed", placed.size())
	pack.set_meta("small", SITES[map_name].size())
	pack.set_meta("large", LARGE_SITES.get(map_name, []).size())
	pack.set_meta("forge", forge_count)
	pack.set_meta("footprints", placed)
	print("[MobilePropPack] ", map_name, " placed=", placed.size(),
			" (small ", SITES[map_name].size(), ", forge ", forge_count,
			", large ", LARGE_SITES.get(map_name, []).size(), ")")
	return pack


static func _place(root: Node3D, pack: Node3D, terrain, map_name: String,
		entry: Array, placed: Array[Dictionary], large: bool) -> void:
	var prop_name: String = entry[0]
	var base: Vector2 = entry[1]
	var yaw := deg_to_rad(float(entry[2]))
	var scl := float(entry[3]) if entry.size() > 3 else 1.0
	var scene := _scene(prop_name, large)
	if scene == null:
		return
	var radius := _radius(prop_name, large) * scl
	# The cargo ship floats; every other object must stand on dry ground.
	var floating := prop_name == "cargo_ship"
	var site := Vector2.ZERO
	if floating:
		site = _find_water_site(terrain, map_name, base, radius, yaw, placed)
		if site == Vector2.INF:
			push_warning("[MobilePropPack] no water site for " + prop_name)
			return
	else:
		site = _find_ground_site(terrain, map_name, base, radius, placed, root)
		if site == Vector2.INF:
			push_warning("[MobilePropPack] no clear site for " + prop_name)
			return
	var ground: float = terrain.call("mesh_surface_height", map_name, site.x, site.y)
	var base_y := ground + 0.02 if not floating else \
			float(terrain.call("water_level", map_name)) + 0.25
	var inst := scene.instantiate() as Node3D
	if inst == null:
		return
	inst.name = "Prop_" + prop_name + "_%d" % placed.size()
	pack.add_child(inst)
	inst.position = Vector3(site.x, base_y, site.y)
	inst.rotation.y = yaw
	inst.scale = Vector3.ONE * scl
	if inst.is_inside_tree():
		inst.force_update_transform()
	_apply_material(inst, prop_name)
	var lod := LANDMARK_LOD if large else float(LOD_END.get(prop_name, 420.0))
	for child in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		mi.visibility_range_end = lod
		mi.visibility_range_end_margin = 40.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if not large:
		_add_box_collider(inst, _local_aabb(inst))
	inst.set_meta("pack_radius", radius)
	inst.set_meta("pack_ground", ground)
	inst.set_meta("pack_large", large)
	inst.set_meta("pack_floating", floating)
	if terrain != null:
		terrain.call("reserve_area", site, radius + (4.5 if (large or radius >= 3.5) else 1.5))
		if not floating:
			terrain.call("add_contact_shadow", root, map_name, site, maxf(radius * 0.88, 1.35), prop_name, 0.76)
	placed.append({"pos": site, "radius": radius, "name": prop_name,
			"large": large})


## Forge layer: hand-sculpted GLBs keep their baked albedo material, so this
## path deliberately skips _apply_material().  Tall towers and portal assets
## get a low base collider; compact solid ruins get a full box.
static func _place_forge(root: Node3D, pack: Node3D, terrain, map_name: String,
		entry: Array, placed: Array[Dictionary]) -> bool:
	var prop_name := String(entry[0])
	var base: Vector2 = entry[1]
	var yaw := deg_to_rad(float(entry[2]))
	var scl := float(entry[3]) if entry.size() > 3 else 1.0
	var scene := _forge_scene(prop_name)
	if scene == null:
		return false
	var radius := _forge_radius(prop_name) * scl
	# The half-sunk barge belongs in the river, like the cargo-ship landmark.
	var floating := prop_name.contains("barge")
	var site := Vector2.ZERO
	if floating:
		site = _find_water_site(terrain, map_name, base, radius, yaw, placed)
		if site == Vector2.INF:
			push_warning("[MobilePropPack] no water site for " + prop_name)
			return false
	else:
		site = _find_ground_site(terrain, map_name, base, radius, placed, root)
		if site == Vector2.INF:
			push_warning("[MobilePropPack] no clear site for " + prop_name)
			return false
	var ground: float = terrain.call("mesh_surface_height", map_name, site.x, site.y)
	var base_y := ground + 0.02
	if floating:
		# Sink the hull two metres below the waterline so it reads as a wreck
		# instead of a boat resting on the surface.
		base_y = float(terrain.call("water_level", map_name)) - 2.0
	var inst := scene.instantiate() as Node3D
	if inst == null:
		return false
	inst.name = "Forge_" + prop_name + "_%d" % placed.size()
	pack.add_child(inst)
	inst.position = Vector3(site.x, base_y, site.y)
	inst.rotation.y = yaw
	inst.scale = Vector3.ONE * scl
	if inst.is_inside_tree():
		inst.force_update_transform()
	var box := _local_aabb(inst)
	var lod := clampf(650.0 + box.size.y * 12.0, 650.0, 1200.0)
	for child in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		mi.visibility_range_end = lod
		mi.visibility_range_end_margin = 40.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if _forge_has_opening(prop_name) or box.size.y > 14.0:
		_add_base_collider(inst, box)
	else:
		_add_box_collider(inst, box)
	inst.set_meta("pack_radius", radius)
	inst.set_meta("pack_height", box.size.y)
	inst.set_meta("pack_ground", ground)
	inst.set_meta("pack_large", false)
	inst.set_meta("pack_floating", floating)
	inst.set_meta("pack_forge", true)
	# Tall forge halls/hangars only get a 2.8 m plinth collider so their openings
	# stay flyable.  Register an analytic exclusion so AI vehicles cannot cross
	# the visible upper mesh; physics alone cannot stop kinematic vehicles.
	if box.size.y * scl > 12.0:
		FrontlineTerrainScript.register_structure_exclusion(
				site, Vector2(radius, radius), ground + box.size.y * scl)
	if terrain != null:
		terrain.call("reserve_area", site, radius + 4.5)
		if not floating:
			terrain.call("add_contact_shadow", root, map_name, site, maxf(radius * 0.92, 2.2), "Forge_" + prop_name, 0.78)
	placed.append({"pos": site, "radius": radius, "name": prop_name,
			"large": false, "forge": true})
	return true


static func _forge_scene(prop_name: String) -> PackedScene:
	var key := "F:" + prop_name
	if _scenes.has(key):
		return _scenes[key]
	var path := FORGE_ROOT + prop_name + ".glb"
	if not ResourceLoader.exists(path):
		push_warning("[MobilePropPack] missing " + path)
		_scenes[key] = null
		return null
	_scenes[key] = load(path) as PackedScene
	return _scenes[key]


static func _forge_radius(prop_name: String) -> float:
	var key := "F:" + prop_name
	if _radii.has(key):
		return _radii[key]
	var scene := _forge_scene(prop_name)
	if scene == null:
		return 2.0
	var dummy := scene.instantiate() as Node3D
	var box := _local_aabb(dummy)
	dummy.free()
	var rx := maxf(absf(box.position.x), absf(box.position.x + box.size.x))
	var rz := maxf(absf(box.position.z), absf(box.position.z + box.size.z))
	var r := maxf(rx, rz)
	_radii[key] = maxf(r, 1.0)
	return _radii[key]


static func _forge_has_opening(prop_name: String) -> bool:
	for hint in FORGE_OPEN_HINTS:
		if prop_name.contains(String(hint)):
			return true
	return false


## Spiral search for a site that is on dry land, outside halls/POIs and at a
## real distance from every already placed object.
static func _is_ground_site_valid(terrain, map_name: String, root: Node3D,
		c: Vector2, radius: float, placed: Array[Dictionary],
		min_ground_y: float, res_gap: float) -> bool:
	if absf(c.x) > 155.0 or absf(c.y) > 155.0:
		return false
	if float(terrain.call("_road_factor", map_name, c.x, c.y)) >= 0.22:
		return false
	var ground: float = terrain.call("mesh_surface_height", map_name, c.x, c.y)
	if ground <= min_ground_y:
		return false
	if bool(terrain.call("_hall_clear_zone", map_name, c.x, c.y)):
		return false
	var sites_dict = terrain.get("HALL_SITES")
	if sites_dict is Dictionary:
		var hsite: Dictionary = (sites_dict as Dictionary).get(map_name, {})
		if not hsite.is_empty():
			var spawn := Vector2(hsite.get("spawn", Vector2.ZERO))
			if spawn != Vector2.ZERO and c.distance_to(spawn) < radius + 26.0:
				return false
			var hcenter := Vector2(hsite.get("center", Vector2.ZERO))
			if radius >= 3.5:
				var ov_cam := hcenter + Vector2(-95.0, 125.0)
				var ov_mid := hcenter + Vector2(-52.0, 72.0)
				if c.distance_to(ov_cam) < radius + 34.0 or c.distance_to(ov_mid) < radius + 24.0:
					return false
	if bool(terrain.call("_structure_clear_zone", map_name, c.x, c.y,
			radius + minf(res_gap, 5.0))):
		return false
	if not _far_from_existing(root, terrain, c, radius, res_gap):
		return false
	var min_sep := 5.0 if res_gap < 2.0 else -1.0
	return _far_from_placed(placed, c, radius, min_sep)


static func _find_ground_site(terrain, map_name: String, base: Vector2,
		radius: float, placed: Array[Dictionary], root: Node3D) -> Vector2:
	var water: float = float(terrain.call("water_level", map_name))
	var water_margins := [0.7, 0.25] if map_name == "wetlands" else [0.7]
	var a_seed := base.angle() if base.length_squared() > 1.0 else 0.0
	var gap_tiers := [20.0, 14.0, 10.0] if radius >= 3.5 else [12.0, 8.0, 5.0]
	for wm in water_margins:
		var min_y := water + float(wm)
		for c0 in [base, Vector2.ZERO]:
			var center: Vector2 = c0
			for res_gap in gap_tiers:
				var max_rings := 22 if center == base else 28
				var ring_step := 9.0 if center == base else 8.0
				var steps_per_ring := 16 if center == base else 24
				for ring in range(0, max_rings):
					var ring_r := ring_step * float(ring)
					var steps := 1 if ring == 0 else steps_per_ring
					for i in range(steps):
						var a := a_seed + TAU * float(i) / float(steps) + float(ring) * 0.65
						var c: Vector2 = center + Vector2(cos(a), sin(a)) * ring_r
						if _is_ground_site_valid(terrain, map_name, root, c,
								radius, placed, min_y, float(res_gap)):
							return c
	return Vector2.INF


static func _find_water_site(terrain, map_name: String, base: Vector2,
		radius: float, yaw: float, placed: Array[Dictionary]) -> Vector2:
	var water: float = float(terrain.call("water_level", map_name))
	var axis := Vector2(cos(yaw), -sin(yaw))
	var probes: Array[float] = [-0.7, -0.35, 0.0, 0.35, 0.7]
	for ring in range(0, 18):
		var ring_r := 14.0 * float(ring)
		var steps := 1 if ring == 0 else 16
		for i in range(steps):
			var a := TAU * float(i) / float(steps) + float(ring) * 0.5
			var c := base + Vector2(cos(a), sin(a)) * ring_r
			if absf(c.x) > 155.0 or absf(c.y) > 155.0:
				continue
			var wet := true
			for f in probes:
				var probe := c + axis * (radius * f)
				if absf(probe.x) > 158.0 or absf(probe.y) > 158.0:
					wet = false
					break
				if float(terrain.call("mesh_surface_height", map_name,
						probe.x, probe.y)) > water - 0.25:
					wet = false
					break
			if wet and _far_from_placed(placed, c, radius):
				return c
	return Vector2.INF


static func _far_from_placed(placed: Array[Dictionary], c: Vector2,
		radius: float, min_gap_override: float = -1.0) -> bool:
	for p in placed:
		var other: Vector2 = p["pos"]
		var pr: float = float(p["radius"])
		var gap: float
		if radius >= 3.5 and pr >= 3.5:
			gap = 24.0 if min_gap_override < 0.0 else maxf(min_gap_override, 20.0)
		elif radius >= 3.5 or pr >= 3.5:
			gap = 14.0 if min_gap_override < 0.0 else maxf(min_gap_override, 12.0)
		else:
			gap = 12.0 if min_gap_override < 0.0 else maxf(min_gap_override, 8.0)
		if c.distance_to(other) < radius + pr + gap:
			return false
	return true


## Keeps new objects away from authored heroes, beacons, POIs, halls and reserved structures.
static func _far_from_existing(root: Node3D, terrain, c: Vector2,
		radius: float, min_res_gap: float = 12.0) -> bool:
	var checks := [["MobileHero", 24.0], ["MobileBeacon", 12.0], ["POI_", 20.0],
			["Enriched_", 12.0], ["Handcrafted_", 24.0]]
	for spec in checks:
		for n in root.find_children(String(spec[0]) + "*", "Node3D", true, false):
			var np := (n as Node3D).transform.origin if terrain == null \
					else (terrain.call("_local_transform_to_root", n, root) as Transform3D).origin
			if Vector2(np.x, np.z).distance_to(c) < radius + float(spec[1]):
				return false
	if terrain != null:
		for res in terrain.get_reserved_structures(root):
			var rp: Vector2 = res["pos"]
			var rr: float = float(res["radius"])
			if rp.distance_to(c) < rr + radius + min_res_gap:
				return false
		var ms = load("res://scripts/util/military_structures.gd")
		if ms != null:
			var mname := String(terrain.get("_current_map"))
			for mp in ms.spawned_positions.get(mname, []):
				if (mp as Vector2).distance_to(c) < radius + maxf(min_res_gap, 14.0):
					return false
	return true


static func _radius(prop_name: String, large: bool) -> float:
	var key := ("L:" if large else "S:") + prop_name
	if _radii.has(key):
		return _radii[key]
	var scene := _scene(prop_name, large)
	if scene == null:
		return 2.0
	var dummy := scene.instantiate() as Node3D
	var box := _local_aabb(dummy)
	dummy.free()
	var rx := maxf(absf(box.position.x), absf(box.position.x + box.size.x))
	var rz := maxf(absf(box.position.z), absf(box.position.z + box.size.z))
	var r := maxf(rx, rz)
	_radii[key] = maxf(r, 1.0)
	return _radii[key]


static func _scene(prop_name: String, large: bool) -> PackedScene:
	var key := ("L:" if large else "S:") + prop_name
	if _scenes.has(key):
		return _scenes[key]
	var path := (LANDMARK_ROOT if large else PROP_ROOT) + prop_name + ".glb"
	if not ResourceLoader.exists(path):
		push_warning("[MobilePropPack] missing " + path)
		_scenes[key] = null
		return null
	_scenes[key] = load(path) as PackedScene
	return _scenes[key]


static func _apply_material(node: Node3D, prop_name: String) -> void:
	var mat: StandardMaterial3D = _materials.get(prop_name)
	if mat == null:
		var finish := _surface_finish(prop_name)
		mat = StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = finish.x
		mat.metallic = finish.y
		mat.metallic_specular = 0.34 if finish.y >= 0.12 else 0.22
		mat.uv1_triplanar = true
		mat.uv1_world_triplanar = true
		mat.uv1_triplanar_sharpness = 8.0
		mat.uv1_scale = Vector3.ONE * 0.28
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		var nrm_path := "res://Assets/frontline/industrial_hall/concrete_slab_wall_nor_gl.jpg"
		var rgh_path := "res://Assets/frontline/industrial_hall/concrete_slab_wall_rough.jpg"
		if finish.y >= 0.14 or prop_name in ["cargo_ship", "fuel_depot", "factory_plant", "grain_elevator"]:
			nrm_path = "res://Assets/frontline/industrial_hall/metal_plate_02_nor_gl.jpg"
			rgh_path = "res://Assets/frontline/industrial_hall/metal_plate_02_rough.jpg"
		elif prop_name in ["power_pole", "fence_section", "barn_small", "well_house", "watchtower", "farm_complex"]:
			nrm_path = "res://Assets/frontline/textures/wood_normal.jpg"
			rgh_path = "res://Assets/frontline/textures/wood_rough.jpg"
		if ResourceLoader.exists(nrm_path):
			mat.normal_enabled = true
			mat.normal_texture = load(nrm_path) as Texture2D
			mat.normal_scale = 0.85
		if ResourceLoader.exists(rgh_path):
			mat.roughness_texture = load(rgh_path) as Texture2D
		_materials[prop_name] = mat
	for child in node.find_children("*", "MeshInstance3D", true, false):
		(child as MeshInstance3D).material_override = mat


## Keep the mobile prop meshes vertex-coloured and batched, but stop steel,
## timber and concrete from all reading as the same dead-matte plastic. This is
## material-only (no extra textures, meshes, or draw calls).
static func _surface_finish(prop_name: String) -> Vector2:
	match prop_name:
		"antenna_mast":
			return Vector2(0.48, 0.42)
		"fuel_barrels":
			return Vector2(0.58, 0.30)
		"water_tower_small", "silo_small", "container_stack":
			return Vector2(0.68, 0.20)
		"truck_wreck", "apc_wreck":
			return Vector2(0.74, 0.16)
		"tank_traps":
			return Vector2(0.62, 0.30)
		"power_pole", "fence_section", "barn_small", "well_house", "haystack", "tent_military", "watchtower":
			return Vector2(0.90, 0.02)
		"greenhouse", "bus_stop", "checkpoint_booth", "billboard_ruined":
			return Vector2(0.78, 0.08)
		"jersey_barriers", "ruined_wall", "sandbag_nest":
			return Vector2(0.96, 0.0)
		_:
			return Vector2(0.88, 0.03)


static func _local_aabb(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var cur: Node = mi
		while cur != null and cur != node:
			if cur is Node3D:
				xf = (cur as Node3D).transform * xf
			cur = cur.get_parent()
		var b: AABB = xf * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## A low plinth keeps the asset solid at ground level while leaving portals,
## decks and broken upper floors open for FPV passes.
static func _add_base_collider(node: Node3D, box: AABB) -> void:
	var height := minf(box.size.y, 2.8)
	var base := AABB(box.position,
			Vector3(box.size.x, maxf(height, 0.2), box.size.z))
	_add_box_collider(node, base)


static func _add_box_collider(node: Node3D, box: AABB) -> void:
	if box.size.length_squared() < 0.001:
		return
	var body := StaticBody3D.new()
	body.name = "PropCollider"
	body.collision_layer = 1
	body.collision_mask = 1
	body.position = box.get_center()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(box.size.x, 0.2), maxf(box.size.y, 0.2), maxf(box.size.z, 0.2))
	cs.shape = shape
	body.add_child(cs)
	node.add_child(body)
