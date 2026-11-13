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
		["checkpoint_booth", Vector2(215, 195), 15.0, 1.0],
		["sandbag_nest", Vector2(195, 185), 40.0, 1.0],
		["ammo_crates", Vector2(208, 178), 0.0, 1.0],
		["fuel_barrels", Vector2(222, 185), 20.0, 1.0],
		["watchtower", Vector2(-195, 155), 0.0, 1.0],
		["power_pole", Vector2(-185, 132), 0.0, 1.0],
		["power_pole", Vector2(-155, 112), 0.0, 1.0],
		["haystack", Vector2(-115, 190), 30.0, 1.0],
		["haystack", Vector2(-102, 205), 70.0, 1.0],
		["haystack", Vector2(30, 198), 10.0, 1.0],
		["barn_small", Vector2(-135, 165), 0.0, 1.0],
		["silo_small", Vector2(-148, 192), 0.0, 1.0],
		["greenhouse", Vector2(85, 188), 0.0, 1.0],
		["truck_wreck", Vector2(160, 185), 35.0, 1.0],
		["tent_military", Vector2(185, 108), 10.0, 1.0],
		["antenna_mast", Vector2(225, 95), 0.0, 1.0],
		["jersey_barriers", Vector2(205, 72), 15.0, 1.0],
		["tank_traps", Vector2(175, 82), 0.0, 1.0],
		["fence_section", Vector2(135, 196), 0.0, 1.0],
		["ruined_wall", Vector2(-215, 42), 20.0, 1.0],
	],
	"village": [
		["bus_stop", Vector2(-165, 175), 10.0, 1.0],
		["well_house", Vector2(-185, 115), 0.0, 1.0],
		["barn_small", Vector2(-150, 198), 25.0, 1.0],
		["haystack", Vector2(205, 162), 0.0, 1.0],
		["haystack", Vector2(185, 188), 40.0, 1.0],
		["fence_section", Vector2(-198, 28), 0.0, 1.0],
		["fence_section", Vector2(-172, 16), 0.0, 1.0],
		["power_pole", Vector2(210, -20), 0.0, 1.0],
		["power_pole", Vector2(185, 0), 0.0, 1.0],
		["truck_wreck", Vector2(155, 162), 30.0, 1.0],
		["water_tower_small", Vector2(-215, 185), 0.0, 1.0],
		["greenhouse", Vector2(138, 188), 0.0, 1.0],
		["sandbag_nest", Vector2(-132, 162), 55.0, 1.0],
		["checkpoint_booth", Vector2(-115, 198), 0.0, 1.0],
		["ammo_crates", Vector2(-130, 186), 0.0, 1.0],
		["fuel_barrels", Vector2(-102, 186), 0.0, 1.0],
		["tent_military", Vector2(205, 108), 20.0, 1.0],
		["jersey_barriers", Vector2(175, 95), 15.0, 1.0],
		["ruined_wall", Vector2(128, -162), 60.0, 1.0],
		["watchtower", Vector2(16, 198), 0.0, 1.0],
	],
	"industrial": [
		["container_stack", Vector2(205, 172), 0.0, 1.0],
		["container_stack", Vector2(210, 138), 90.0, 1.0],
		["truck_wreck", Vector2(175, 182), 30.0, 1.0],
		["truck_wreck", Vector2(158, 196), 50.0, 1.0],
		["apc_wreck", Vector2(-198, 182), 15.0, 1.0],
		["fuel_barrels", Vector2(188, 155), 0.0, 1.0],
		["fuel_barrels", Vector2(-180, 166), 0.0, 1.0],
		["checkpoint_booth", Vector2(-210, 138), 0.0, 1.0],
		["fence_section", Vector2(-175, 194), 0.0, 1.0],
		["fence_section", Vector2(-150, 202), 0.0, 1.0],
		["fence_section", Vector2(138, -185), 0.0, 1.0],
		["power_pole", Vector2(-205, 38), 0.0, 1.0],
		["power_pole", Vector2(-185, 14), 0.0, 1.0],
		["antenna_mast", Vector2(215, 65), 0.0, 1.0],
		["jersey_barriers", Vector2(198, 28), 15.0, 1.0],
		["jersey_barriers", Vector2(185, 8), 15.0, 1.0],
		["tank_traps", Vector2(172, -38), 0.0, 1.0],
		["ammo_crates", Vector2(-162, 125), 0.0, 1.0],
		["ruined_wall", Vector2(-220, -28), 0.0, 1.0],
		["water_tower_small", Vector2(220, -52), 0.0, 1.0],
	],
	"wetlands": [
		["watchtower", Vector2(205, 185), 0.0, 1.0],
		["bus_stop", Vector2(-185, 185), 10.0, 1.0],
		["fence_section", Vector2(-210, 148), 0.0, 1.0],
		["fence_section", Vector2(-185, 136), 0.0, 1.0],
		["fence_section", Vector2(205, 95), 0.0, 1.0],
		["power_pole", Vector2(-155, 202), 0.0, 1.0],
		["power_pole", Vector2(-130, 212), 0.0, 1.0],
		["haystack", Vector2(162, 196), 30.0, 1.0],
		["haystack", Vector2(138, 212), 60.0, 1.0],
		["barn_small", Vector2(-215, 95), 0.0, 1.0],
		["well_house", Vector2(-198, 65), 0.0, 1.0],
		["truck_wreck", Vector2(192, 162), 20.0, 1.0],
		["sandbag_nest", Vector2(-162, 112), 40.0, 1.0],
		["checkpoint_booth", Vector2(-128, 202), 0.0, 1.0],
		["tent_military", Vector2(185, 125), 10.0, 1.0],
		["fuel_barrels", Vector2(168, 144), 0.0, 1.0],
		["ruined_wall", Vector2(-230, -112), 0.0, 1.0],
		["antenna_mast", Vector2(185, -138), 0.0, 1.0],
		["jersey_barriers", Vector2(-95, 185), 0.0, 1.0],
		["tank_traps", Vector2(125, 185), 0.0, 1.0],
	],
}

## Five large landmarks per map: [landmark, Vector2(x, z), yaw degrees]
const LARGE_SITES := {
	"steppe": [
		["grain_elevator", Vector2(-205, 205), 25.0],
		["farm_complex", Vector2(-118, 224), 0.0],
		["warehouse", Vector2(208, 218), 200.0],
		["fuel_depot", Vector2(105, -205), 45.0],
		["factory_plant", Vector2(-225, -115), 90.0],
	],
	"village": [
		["grain_elevator", Vector2(195, 202), 20.0],
		["farm_complex", Vector2(-200, 206), 0.0],
		["warehouse", Vector2(-212, -196), 120.0],
		["fuel_depot", Vector2(52, 216), 0.0],
		["factory_plant", Vector2(185, -195), 80.0],
	],
	"industrial": [
		["factory_plant", Vector2(-215, 182), 45.0],
		["warehouse", Vector2(208, 178), 200.0],
		["warehouse", Vector2(-155, -212), 0.0],
		["fuel_depot", Vector2(212, -205), 30.0],
		["factory_plant", Vector2(-202, -198), 135.0],
	],
	"wetlands": [
		["cargo_ship", Vector2(145, -125), 15.0],
		["warehouse", Vector2(198, 205), 210.0],
		["farm_complex", Vector2(-208, 195), 0.0],
		["fuel_depot", Vector2(58, 218), 0.0],
		["grain_elevator", Vector2(-218, -185), 60.0],
	],
}

## Ten hand-sculpted war-wear GLBs per map.  These are larger than the small
## prop kit, so they sit in the open middle ring and double as stunt openings;
## the baked albedo material is kept as-is (no vertex-colour override).
## [glb, Vector2(x, z), yaw degrees]
const FORGE_SITES := {
	"steppe": [
		["steppe_01_lep_pylon_leaning", Vector2(-60, 55), 20.0],
		["steppe_03_lep_collapsed_arch", Vector2(60, -40), 15.0],
		["steppe_09_harvester_skeleton", Vector2(-130, -60), 30.0],
		["steppe_12_bunker_dot_breached", Vector2(140, 30), 0.0],
		["steppe_13_pillbox_trench_bridge", Vector2(30, 20), 10.0],
		["steppe_14_radar_revetment_wall", Vector2(-150, 115), 0.0],
		["steppe_15_watchtower_steppe", Vector2(90, 150), 0.0],
		["steppe_18_gully_bridge_broken", Vector2(-40, 180), 0.0],
		["steppe_23_rozhnovsky_tower_standing", Vector2(60, 100), 0.0],
		["steppe_29_concrete_slab_fort", Vector2(-160, -140), 45.0],
	],
	"village": [
		["village_01_khata_breached_roof", Vector2(-80, 130), 10.0],
		["village_02_brick_house_split", Vector2(30, 150), 0.0],
		["village_04_kolkhoz_hangar_holed", Vector2(-130, -80), 75.0],
		["village_07_silo_twin_bridge", Vector2(60, -120), 0.0],
		["village_10_house_of_culture_portico", Vector2(-90, 0), 90.0],
		["village_13_brick_church_belfry", Vector2(60, 140), 0.0],
		["village_15_river_bridge_wooden", Vector2(-40, -160), 15.0],
		["village_17_azs_canopy_wreck", Vector2(130, 170), 200.0],
		["village_19_cowbarn_rafters_slalom", Vector2(-150, 100), 0.0],
		["village_27_windmill_timber_frame", Vector2(120, -60), 0.0],
	],
	"industrial": [
		["industrial_03_smokestack_breached_flue", Vector2(-100, 30), 0.0],
		["industrial_04_gantry_crane_portal", Vector2(150, -60), 45.0],
		["industrial_07_unfinished_workshop_3f", Vector2(-150, -60), 0.0],
		["industrial_10_pipe_rack_overpass", Vector2(0, -80), 90.0],
		["industrial_13_cooling_tower_breached", Vector2(-170, 120), 0.0],
		["industrial_17_workshop_truss_roof", Vector2(100, 160), 0.0],
		["industrial_19_loading_ramp_canopy", Vector2(160, 100), 180.0],
		["industrial_23_hangar_rib_tunnel", Vector2(-60, -160), 0.0],
		["industrial_24_blast_furnace_shell", Vector2(100, -160), 0.0],
		["industrial_27_transformer_yard_portal", Vector2(-140, 190), 180.0],
	],
	"wetlands": [
		["swamp_01_flooded_pumping_station", Vector2(-60, 150), 0.0],
		["swamp_03_half_sunk_river_barge", Vector2(-120, -60), 15.0],
		["swamp_04_wooden_trestle_causeway", Vector2(30, -160), 0.0],
		["swamp_07_flooded_bunker_stilts", Vector2(-160, 40), 0.0],
		["swamp_09_rotting_watchtower_marsh", Vector2(130, -60), 0.0],
		["swamp_11_flooded_power_pylon", Vector2(160, 150), 0.0],
		["swamp_15_abandoned_hydro_lock", Vector2(-80, -120), 0.0],
		["swamp_18_camo_radar_mound_marsh", Vector2(60, 190), 0.0],
		["swamp_22_marsh_boardwalk_tower", Vector2(0, 0), 45.0],
		["swamp_27_military_bailey_truss_span", Vector2(-210, -60), 90.0],
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
	root.add_child(pack)
	var placed: Array[Dictionary] = []
	for entry in SITES[map_name]:
		_place(root, pack, terrain, map_name, entry, placed, false)
	var forge_count := 0
	for entry in FORGE_SITES.get(map_name, []):
		if _place_forge(root, pack, terrain, map_name, entry, placed):
			forge_count += 1
	# Landmarks go last: their far-edge berths have priority over the new
	# middle-ring forge layer.
	for entry in LARGE_SITES.get(map_name, []):
		_place(root, pack, terrain, map_name, entry, placed, true)
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
	var r := maxf(box.size.x, box.size.z) * 0.5
	_radii[key] = maxf(r, 1.0)
	return _radii[key]


static func _forge_has_opening(prop_name: String) -> bool:
	for hint in FORGE_OPEN_HINTS:
		if prop_name.contains(String(hint)):
			return true
	return false


## Spiral search for a site that is on dry land, outside halls/POIs and at a
## real distance from every already placed object.
static func _find_ground_site(terrain, map_name: String, base: Vector2,
		radius: float, placed: Array[Dictionary], root: Node3D) -> Vector2:
	var water: float = float(terrain.call("water_level", map_name))
	for ring in range(0, 10):
		var ring_r := 14.0 * float(ring)
		var steps := 1 if ring == 0 else 12
		for i in range(steps):
			var a := TAU * float(i) / float(steps) + float(ring) * 0.7
			var c := base + Vector2(cos(a), sin(a)) * ring_r
			if absf(c.x) > 260.0 or absf(c.y) > 260.0:
				continue
			var ground: float = terrain.call("mesh_surface_height", map_name, c.x, c.y)
			if ground <= water + 0.7:
				continue
			if bool(terrain.call("_hall_clear_zone", map_name, c.x, c.y)):
				continue
			if bool(terrain.call("_structure_clear_zone", map_name, c.x, c.y)):
				continue
			if not _far_from_existing(root, c, radius):
				continue
			if not _far_from_placed(placed, c, radius):
				continue
			return c
	return Vector2.INF


static func _find_water_site(terrain, map_name: String, base: Vector2,
		radius: float, yaw: float, placed: Array[Dictionary]) -> Vector2:
	var water: float = float(terrain.call("water_level", map_name))
	# Hulls are long and narrow: probe along the ship's own axis, not a circle,
	# otherwise a narrow river can never satisfy the test.
	var axis := Vector2(cos(yaw), -sin(yaw))
	var probes: Array[float] = [-0.7, -0.35, 0.0, 0.35, 0.7]
	for ring in range(0, 14):
		var ring_r := 30.0 * float(ring)
		var steps := 1 if ring == 0 else 12
		for i in range(steps):
			var a := TAU * float(i) / float(steps) + float(ring) * 0.5
			var c := base + Vector2(cos(a), sin(a)) * ring_r
			if absf(c.x) > 255.0 or absf(c.y) > 255.0:
				continue
			var wet := true
			for f in probes:
				var probe := c + axis * (radius * f)
				if float(terrain.call("mesh_surface_height", map_name,
						probe.x, probe.y)) > water - 0.25:
					wet = false
					break
			if wet and _far_from_placed(placed, c, radius):
				return c
	return Vector2.INF


static func _far_from_placed(placed: Array[Dictionary], c: Vector2,
		radius: float) -> bool:
	for p in placed:
		var other: Vector2 = p["pos"]
		if c.distance_to(other) < radius + float(p["radius"]) + 2.0:
			return false
	return true


## Keeps new objects away from the authored heroes, beacons, POIs and halls.
static func _far_from_existing(root: Node3D, c: Vector2, radius: float) -> bool:
	var checks := [["MobileHero", 16.0], ["MobileBeacon", 10.0], ["POI_", 14.0],
			["Enriched_", 8.0]]
	for spec in checks:
		for n in root.find_children(String(spec[0]) + "*", "Node3D", true, false):
			var np := (n as Node3D).global_position
			if Vector2(np.x, np.z).distance_to(c) < radius + float(spec[1]):
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
	var r := maxf(box.size.x, box.size.z) * 0.5
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
		mat = StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.9
		mat.metallic = 0.0
		_materials[prop_name] = mat
	for child in node.find_children("*", "MeshInstance3D", true, false):
		(child as MeshInstance3D).material_override = mat


static func _local_aabb(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		var b: AABB = mi.transform * mi.get_aabb()
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
