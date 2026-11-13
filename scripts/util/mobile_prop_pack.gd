class_name MobilePropPack
extends RefCounted

## Curated low-poly prop pack + five large landmarks for the four frontline
## maps.  Small props come from tools/build_map_props.py, landmarks from
## tools/build_map_landmarks.py.
##
## Placement guarantees (also re-checked by qa_mobile_map_views):
##   * every object sits on the terrain height (no floating, no sinking),
##   * objects keep a real gap from each other and from existing POIs,
##   * small props get box colliders, landmarks keep their hollow -colonly
##     collision so the drone can fly inside and do stunts,
##   * low draw-call cost: one vertex-colour material per asset + distance LOD.
const PROP_ROOT := "res://Assets/handcrafted/props_lowpoly/"
const LANDMARK_ROOT := "res://Assets/handcrafted/landmarks/"

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
	for entry in LARGE_SITES.get(map_name, []):
		_place(root, pack, terrain, map_name, entry, placed, true)
	pack.set_meta("placed", placed.size())
	pack.set_meta("small", SITES[map_name].size())
	pack.set_meta("large", LARGE_SITES.get(map_name, []).size())
	pack.set_meta("footprints", placed)
	print("[MobilePropPack] ", map_name, " placed=", placed.size(),
			" (small ", SITES[map_name].size(), ", large ",
			LARGE_SITES.get(map_name, []).size(), ")")
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
