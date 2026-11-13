extends RefCounted

const ASSETS := preload("res://scripts/util/frontline_assets.gd")
const FOLIAGE := preload("res://scripts/util/foliage_system.gd")
const VEGETATION := preload("res://scripts/util/vegetation_assets.gd")
const DESTRUCTIBLE_LANDMARK := preload("res://combat/destructible_landmark.gd")
const PROP_ASSETS := preload("res://scripts/util/prop_assets.gd")
const OPEN_TOWER := preload("res://scripts/util/open_tower.gd")
const MOVING_CRANE := preload("res://scripts/util/moving_crane.gd")
const MOVING_WINDMILL := preload("res://scripts/util/MovingWindmill.gd")
const MOVING_RADAR := preload("res://scripts/util/MovingRadar.gd")
const MOVING_PATROL_BOAT := preload("res://scripts/util/MovingPatrolBoat.gd")
const WATER_SHADER := preload("res://Assets/water.gdshader")
const GRASS_SHADER := preload("res://Assets/grass_wind.gdshader")
const GOD_RAY_SHADER := preload("res://shaders/god_ray.gdshader")

## Procedural Ukrainian front-line terrain.
##
## Four maps share one height field generator and one set of builders:
##   * "steppe"     - «Посадки та Окопи»: rolling plain, trench networks,
##                    windbreaks, shell craters, burnt armour;
##   * "village"    - «Зруйноване село»: river valley, ruined houses, church,
##                    orchards and PHYSICAL power lines (poles have collision);
##   * "industrial" - «Промзона»: flat yard, factory halls, chimneys, tanks,
##                    spoil heaps and a rail spur;
##   * "wetlands"   - «Водний плацдарм»: marsh, channels, dikes, reeds,
##                    sunken barges - the FPV / Magura battlefield.
##
## The mesh is a two-ring clipmap: a 256 m high-resolution centre (2 m cells)
## Terrain & backdrop layout for all four frontline battlegrounds.
## Outer grid is 614.4 m (8x8 x 76.8 m chunks) with a 153.6 m inner high-detail
## patch (1.6 m cells), surrounded by an extended themed horizon ring & backdrop
## so the battleground looks vast while cutting active terrain CPU/GPU cost.

const OUTER_SIZE := 614.4
const OUTER_CHUNKS := 8
const OUTER_CELLS := 32          # 4.8 m outer cell
const INNER_SIZE := 153.6
const INNER_CHUNKS := 2
const INNER_CELLS := 48          # 1.6 m inner cell

## Ruined concrete hall sites: one authored shell per map, the same kit and
## material set everywhere.  `half` is the flattened terrain pad (m), `scale`
## the hall multiplier, `sink` how deep the floor slab sits below terrain.
## Authored hero interiors.  Every frontline map now has its own large ruined
## industrial hall with a distinct industrial story, a floor-level spawn and an
## interior light/foliage pass.  `half` is the flattened terrain pad (m), not the
## full exterior footprint.
const HALL_SITES := {
	"industrial": {
		"center": Vector2(50.0, 80.0), "scale": 1.0, "yaw": 0.0,
		"sink": 0.0, "interior": true, "half": Vector2(68.0, 42.0),
		"asset": "industrial_hall.glb", "theme": "industrial",
		"spawn": Vector2(50.0, 142.0), "spawn_yaw": PI,
		"roof_height": 22.0,
	},
	"village": {
		"center": Vector2(192.0, 58.0), "scale": 1.0, "yaw": 0.0,
		"sink": 0.0, "interior": true, "half": Vector2(56.0, 36.0),
		"asset": "village_hall.glb", "theme": "village",
		"spawn": Vector2(192.0, 114.0), "spawn_yaw": PI,
		"roof_height": 16.0,
	},
	"steppe": {
		# Moved 96 m east of the old site: its 48x34 m pad overlapped the
		# farm-complex pad and lifted the hall floor 1.7 m above the fields.
		"center": Vector2(192.0, 116.0), "scale": 1.0, "yaw": 0.0,
		"sink": 0.0, "interior": true, "half": Vector2(63.0, 38.0),
		"asset": "steppe_hall.glb", "theme": "steppe",
		"spawn": Vector2(192.0, 174.0), "spawn_yaw": PI,
		"roof_height": 20.5,
	},
	"wetlands": {
		"center": Vector2(85.0, 60.0), "scale": 1.0, "yaw": 0.0,
		"sink": 0.0, "interior": true, "half": Vector2(59.0, 38.0),
		"asset": "wetlands_hall.glb", "theme": "wetlands",
		"spawn": Vector2(85.0, 120.0), "spawn_yaw": PI,
		"roof_height": 19.5,
	},
}

static var _trench_cache := {}
static var _crater_cache := {}
## Large hero trees are collected during the landmark pass and flushed into
## four MultiMeshes (oak/pine x trunk/leaves) so a dozen hero trees do not add
## a draw call each.
static var _hero_tree_slots := {"oak": [], "pine": []}
## Map-unique landmark positions (water tower, transformer yard, watch tower,
## burnt armour).  Filled before the military scatter pass so the random
## structures keep a 40 m berth and no tree/pole can grow through a POI.
static var _poi_positions: Array[Vector2] = []
## Footprints reserved by the tactical enrichment/FPV stunt pass.  Tree,
## object-kit and world-detail scatter passes keep out of these radii.
static var _reserved_zones: Array[Dictionary] = []


static func reserve_area(p: Vector2, radius: float) -> void:
	_reserved_zones.append({"pos": p, "radius": radius})


## Slow drift for the battle-smoke billboards: a vertical bob, a lateral sway
## and a tiny breathing scale.  The quads stay billboarded, so this reads as
## rising smoke without a particle system or a per-frame material update.
class SmokePlume:
	extends Node3D
	var _t := 0.0
	var _seed := 0.0
	var _quads: Array[MeshInstance3D] = []

	func setup(seed_value: float) -> void:
		_seed = seed_value

	func register_quad(q: MeshInstance3D, base_y: float) -> void:
		q.set_meta("base_y", base_y)
		_quads.append(q)

	func _process(delta: float) -> void:
		_t += delta
		for i in range(_quads.size()):
			var q := _quads[i]
			var by := float(q.get_meta("base_y", 0.0))
			var ph := _seed + float(i) * 1.7
			q.position = Vector3(
					sin(_t * 0.23 + ph * 0.7) * 2.2,
					by + sin(_t * 0.45 + ph) * 1.6,
					cos(_t * 0.19 + ph * 1.1) * 1.8)
			var s := 1.0 + sin(_t * 0.33 + ph) * 0.06
			q.scale = Vector3(s, s, s)


# ===========================================================================
#  Public entry points
# ===========================================================================
static func build_terrain(level: Node3D, map_name: String, base_y: float) -> void:
	if map_name == "":
		return
	_current_map = map_name
	_hero_tree_slots["oak"].clear()
	_hero_tree_slots["pine"].clear()
	_reserved_zones.clear()
	var root := Node3D.new()
	root.name = "FrontlineTerrain"
	level.add_child(root)
	root.position = Vector3(0.0, base_y, 0.0)

	var ground_mat := _ground_material(map_name)
	# 8 m cells for the outer ring at every preset: invisible from FPV altitude
	# and ~90k fewer triangles in the frame.
	var outer_cells := maxi(16, OUTER_CELLS / 2)

	# Outer ring: 8x8 chunks, skip the central 2x2 that the inner ring fills.
	var outer_chunk := OUTER_SIZE / float(OUTER_CHUNKS)
	var outer_meshes: Array = []
	for cz in range(OUTER_CHUNKS):
		for cx in range(OUTER_CHUNKS):
			if cx >= 3 and cx <= 4 and cz >= 3 and cz <= 4:
				continue
			var ox := -OUTER_SIZE * 0.5 + float(cx) * outer_chunk
			var oz := -OUTER_SIZE * 0.5 + float(cz) * outer_chunk
			outer_meshes.append(_build_chunk(root, map_name, ox, oz, outer_chunk,
					outer_cells, ground_mat))

	# Inner high-resolution patch.
	var inner_chunk := INNER_SIZE / float(INNER_CHUNKS)
	var inner_meshes: Array = []
	for cz in range(INNER_CHUNKS):
		for cx in range(INNER_CHUNKS):
			var ox := -INNER_SIZE * 0.5 + float(cx) * inner_chunk
			var oz := -INNER_SIZE * 0.5 + float(cz) * inner_chunk
			inner_meshes.append(_build_chunk(root, map_name, ox, oz, inner_chunk,
					INNER_CELLS, ground_mat))

	# One visual mesh for the whole outer ring and one for the inner patch:
	# 64 terrain draw calls collapse into 2 while collision stays chunked.
	_merge_visual_chunks(root, outer_meshes, ground_mat)
	_merge_visual_chunks(root, inner_meshes, ground_mat)

	_build_horizon_ring(root, map_name, ground_mat)
	_build_mountain_backdrop(root, map_name)
	_build_themed_horizon_props(root, map_name)
	_build_water(root, map_name)
	_build_roads(root, map_name)
	_build_trenches(root, map_name)
	_build_crater_marks(root, map_name)
	# Overhead power lines were removed: the 20 m pylon tops read as small
	# floating chimneys from FPV altitude (the player explicitly reported the
	# three boxes hanging in the air) and the catenary collision could snag the
	# drone.  Ground-level wooden poles in the village are kept.
	_build_landmarks(root, map_name)
	_build_hall_sites(root, map_name)
	# Occluder volumes for the hero halls: interior objects are culled while the
	# player flies outside, and the box is ignored from inside (backfaces).
	if not OS.has_environment("QA_NO_OCCLUDERS"):
		_build_hall_occluders(root, map_name)
	# One signature POI per frontline map.  Built before the military scatter
	# so the random builders reserve space around it and before the forest so
	# the clear-zone filter can reject trees.
	_build_unique_pois(root, map_name)
	_build_blender_landmarks(root, map_name)
	_spawn_handcrafted_assets(root, map_name)
	# War-wear dressing: charred ground, rust streaks and rubble on every
	# large building so the frontline reads as fought-over, not pristine.
	_add_war_wear(root, map_name)
	# Mobile-only navigation beacons: tall color-coded masts placed on clear
	# ground between the authored landmarks so pilots can read the map from a
	# distance instead of flying over unmarked fields.
	if (OS.get_name() == "iOS" or OS.has_feature("mobile") \
			or OS.has_environment("MOBILE_UI")) \
			and not OS.has_environment("QA_NO_MOBILE_BEACONS"):
		_build_mobile_beacons(root, map_name)
		_build_mobile_hero_landmarks(root, map_name)
	if map_name == "industrial":
		_build_industrial_river(root)
	else:
		_build_freight_train(root, map_name)
	_build_crop_fields(root, map_name)
	_dress_handcrafted_sites(root, map_name)
	_add_wall_decals(root, map_name)
	_add_map_mist(root, map_name)
	# Mobile-only ground tint patches: large low-alpha quads that break the
	# repetitive grass tiling without adding texture samples to the terrain
	# shader. They follow the height field and are placed away from the hall.
	if (OS.get_name() == "iOS" or OS.has_feature("mobile") \
			or OS.has_environment("MOBILE_UI")) \
			and not OS.has_environment("QA_NO_MOBILE_PATCHES"):
		_add_mobile_ground_patches(root, map_name)
	# Tactical FPV stunt course + battlefield dressing.  Runs after every
	# authored landmark/military structure (so it can reserve clear ground) and
	# before tree/prop/world-detail scatter; the reserved zones keep vegetation
	# out of the stunt corridors.
	if not OS.has_environment("QA_NO_ENRICH"):
		var enricher = load("res://scripts/util/map_enricher.gd")
		if enricher != null:
			enricher.build(root, map_name, QualityManager.get_active_level())
	# Battlefield landmarks, trenches and roads stay; rocks, flowers, debris and
	# outdoor set dressing are scaled per preset inside their build passes.
	_build_treelines(root, map_name)
	_build_ground_detail(root, map_name)
	_build_debris(root, map_name)
	if not OS.has_environment("QA_NO_PROPS"):
		_build_props(root, map_name)
	# Outdoor set dressing: hall aprons, ruins, fields, orchards, rail yards,
	# marsh detail.  Runs before the static batching pass so all of its boxes
	# and cylinders collapse into the same handful of MultiMeshes.
	if not OS.has_environment("QA_NO_WORLD_DETAIL"):
		var detail = load("res://scripts/util/world_detail.gd")
		if detail != null:
			detail.build(root, map_name, 0.0)
		else:
			push_warning("[FrontlineTerrain] world_detail.gd missing")
	_build_far_impostors(root, map_name)
	_flush_library_trees(root)
	# Small crates/posts/rails do not need a real shadow; trimming their shadow
	# casters saves shadow-map draw calls without touching the hero props.
	if QualityManager.get_active_level() != QualityManager.Level.HIGH:
		_trim_small_shadow_casters(root)
	# QA runs here, while every prop is still an individual MeshInstance3D and
	# before _batch_static_props() folds it into a monolith.  The scanner also
	# walks MultiMesh instance transforms and records the original supports on
	# the terrain root, so the post-batch audit keeps its evidence.
	var qa_scanner = load("res://scripts/qa/qa_floating_scanner.gd")
	if qa_scanner != null:
		qa_scanner.scan(root, map_name,
				OS.has_environment("QA_STRICT") or OS.has_environment("DRONE_FLOAT_AUDIT"))
	# Map-wide material upgrade: adds the missing PBR normal/roughness maps,
	# detail grain and heightmap parallax to every authored GLB landmark that
	# still used a flat placeholder material.  Runs before the static batching
	# pass so the upgraded materials can share batches.
	if not OS.has_environment("QA_NO_MATERIAL_UPGRADE"):
		var upgrader = load("res://scripts/util/material_upgrader.gd")
		if upgrader != null:
			upgrader.upgrade(root, map_name, QualityManager.get_active_level())
		_fix_untextured_white(root)
	_batch_static_props(root)
	# The remaining single-surface decoration (pipes, yard clutter, power-line
	# meshes, puddles, rail pieces) is created directly under the terrain root.
	# Merge it by material and 128 m cell so it stops costing one draw per prop.
	if not OS.has_environment("QA_NO_STATIC_MERGE"):
		_batch_static_meshes(root)
		_batch_multisurface_meshes(root)
	_texture_flat_large_meshes(root)
	# Curated Blender pack: 20 low-poly props + 5 large landmarks per map.  It
	# runs after the material upgrade, floating scan and static batching so the
	# new objects keep their own vertex-colour material, colliders and LOD
	# instead of being folded into the terrain batches.
	if (OS.get_name() == "iOS" or OS.has_feature("mobile") \
			or OS.has_environment("MOBILE_UI")) \
			and not OS.has_environment("QA_NO_MOBILE_PACK"):
		var pack = load("res://scripts/util/mobile_prop_pack.gd")
		if pack != null:
			pack.build(root, map_name)
	# Battle smoke: burning-wreck plumes are part of the map, not a post-drone
	# pass, so they must be added here (the old _add_smoke_plumes call lived in
	# the dead build() function and never ran).
	_add_smoke_plumes(root, map_name, base_y)

	print("[FrontlineTerrain] built ", map_name, " (", OUTER_SIZE, " m clipmap)")


## Props that can be placed after the drone has been positioned on the ground.
static func build(level: Node3D, map_name: String, base_y: float) -> void:
	if map_name == "":
		return
	var root := level.get_node_or_null("FrontlineTerrain") as Node3D
	if root == null:
		root = level
	# Battle smoke: a handful of cheap billboard plumes over burning vehicles.
	_add_smoke_plumes(root, map_name, base_y)


# ===========================================================================
#  Height field
# ===========================================================================
static func height_at(map_name: String, x: float, z: float) -> float:
	return _height(map_name, x, z)


## Height of the *rendered* terrain surface, not the analytic noise field.
## The clipmap only evaluates _height at 2 m (inner) / 8 m (outer) grid
## vertices and linearly interpolates between them.  On the outer ring the
## polygon can be several metres below the analytic value, which buried the
## decorative ring of farmhouses (only their chimneys poked out of the hill).
## This reproduces the exact triangle split used by _build_chunk.
static func mesh_surface_height(map_name: String, x: float, z: float) -> float:
	var outer_cells := maxi(16, OUTER_CELLS / 2)
	var step := OUTER_SIZE / float(OUTER_CHUNKS * outer_cells)
	if absf(x) <= INNER_SIZE * 0.5 and absf(z) <= INNER_SIZE * 0.5:
		step = INNER_SIZE / float(INNER_CHUNKS * INNER_CELLS)  # 1.6 m
	var x0 := floorf(x / step) * step
	var z0 := floorf(z / step) * step
	var h00 := _height(map_name, x0, z0)
	var h10 := _height(map_name, x0 + step, z0)
	var h01 := _height(map_name, x0, z0 + step)
	var h11 := _height(map_name, x0 + step, z0 + step)
	var u := clampf((x - x0) / step, 0.0, 1.0)
	var v := clampf((z - z0) / step, 0.0, 1.0)
	# _build_chunk splits the quad as (a,b,c) + (b,d,c): the diagonal runs
	# from (x0+step, z0) to (x0, z0+step), i.e. u + v = 1.
	if u + v <= 1.0:
		return h00 + u * (h10 - h00) + v * (h01 - h00)
	return h11 + (1.0 - u) * (h01 - h11) + (1.0 - v) * (h10 - h11)


## Highest rendered-surface sample under a rotated rectangular footprint.
## Placing a building at this height guarantees it is never buried by the
## coarse outer terrain mesh; the foundation skirt hides the downhill gap.
static func footprint_surface_height(map_name: String, p: Vector2,
		w: float, d: float, yaw: float) -> float:
	var basis := Basis(Vector3.UP, yaw)
	var h := mesh_surface_height(map_name, p.x, p.y)
	for sx in [-0.5, 0.0, 0.5]:
		for sz in [-0.5, 0.0, 0.5]:
			if sx == 0.0 and sz == 0.0:
				continue
			var off := basis * Vector3(w * sx, 0.0, d * sz)
			h = maxf(h, mesh_surface_height(map_name, p.x + off.x, p.y + off.z))
	return h


static func water_level(map_name: String) -> float:
	match map_name:
		"village":
			return -1.8
		"wetlands":
			return -1.2
	return -999.0


static func _height(map_name: String, x: float, z: float) -> float:
	var h := _base_height(map_name, x, z)
	h += _relief_offset(map_name, x, z)
	h += _trench_offset(map_name, x, z)
	h += _crater_offset(map_name, x, z)
	# Level a pad under each authored hall so the floor slab does not float or
	# sink into the rolling terrain.
	var site: Dictionary = HALL_SITES.get(map_name, {})
	if not site.is_empty():
		var c: Vector2 = site["center"]
		var half: Vector2 = site["half"]
		var pad := _base_height(map_name, c.x, c.y)
		var dx := maxf(absf(x - c.x) - half.x, 0.0)
		var dz := maxf(absf(z - c.y) - half.y, 0.0)
		var d := sqrt(dx * dx + dz * dz)
		h = lerpf(h, pad, 1.0 - smoothstep(0.0, 10.0, d))
	# Handcrafted industrial valley: flat pads under the new factory GLB and
	# the rail corridor so the authored buildings sit level.
	if map_name == "industrial":
		var fc := Vector2(-200.0, -180.0)
		var fh := Vector2(125.0, 95.0)
		var fdx := maxf(absf(x - fc.x) - fh.x, 0.0)
		var fdz := maxf(absf(z - fc.y) - fh.y, 0.0)
		var fd := sqrt(fdx * fdx + fdz * fdz)
		h = lerpf(h, 1.6, 1.0 - smoothstep(0.0, 14.0, fd))
		# Flat pad for the cooling tower so its fly-through base sits flush with ground
		h = _flatten_pad(h, x, z, Vector2(-72.0, -214.0), Vector2(20.0, 20.0), 1.6)
		if absf(z + 15.0) < 11.0 and absf(x) < 120.0:
			h = lerpf(h, 1.2, 1.0 - smoothstep(7.0, 11.0, absf(z + 15.0)))
	elif map_name == "village":
		h = _flatten_pad(h, x, z, Vector2(60.0, -110.0),
				Vector2(46.0, 32.0), 1.0)
	elif map_name == "steppe":
		# The farm pad used to be pinned to y=1.4 while the surrounding
		# steppe valley and the hero hall sit around -5 m.  Its 34-48 m apron
		# overlapped the hall site and lifted the hall centre 1.7 m above the
		# surrounding ground, leaving the floor slab hanging.  Flatten to the
		# actual local base height instead of an unrelated absolute value.
		h = _flatten_pad(h, x, z, Vector2(40.0, 146.0),
				Vector2(48.0, 34.0), _base_height(map_name, 40.0, 146.0))
	elif map_name == "wetlands":
		h = _flatten_pad(h, x, z, Vector2(-60.0, -140.0),
				Vector2(34.0, 26.0), -1.0)
	return h


static func _flatten_pad(h: float, x: float, z: float, c: Vector2,
		half: Vector2, level: float) -> float:
	var dx := maxf(absf(x - c.x) - half.x, 0.0)
	var dz := maxf(absf(z - c.y) - half.y, 0.0)
	var d := sqrt(dx * dx + dz * dz)
	return lerpf(h, level, 1.0 - smoothstep(0.0, 12.0, d))


## Rolling mounds and shallow gullies on top of the base field so the maps are
## not billiard tables.  Faded out near the spawn area (origin) and in water
## so launch pads, rivers and swamps keep their authored shape.
static func _relief_offset(map_name: String, x: float, z: float) -> float:
	var amp := 2.0
	match map_name:
		"village":
			amp = 3.2
		"industrial":
			amp = 2.2
		"wetlands":
			amp = 0.0
		_:
			amp = 2.4
	if amp <= 0.0 or OS.has_environment("QA_NO_RELIEF"):
		return 0.0
	# Two plain noise taps: the grass carpet samples the height field thousands
	# of times per rebuild, and a 5-octave version caused 50-100 ms spikes.
	var mounds := _noise2(x * 0.012 + 31.0, z * 0.012 - 17.0)
	var ridges := _noise2(x * 0.03 - 9.0, z * 0.03 + 5.0)
	var d2 := x * x + z * z
	if d2 < 900.0:
		return 0.0
	var spawn_fade := smoothstep(30.0, 110.0, sqrt(d2))
	return (mounds * amp + ridges * amp * 0.35) * spawn_fade


static func _base_height(map_name: String, x: float, z: float) -> float:
	match map_name:
		"village":
			var h := 1.2 + _fbm(x * 0.005, z * 0.005, 3) * 4.0
			var river := absf(x + 170.0 - 35.0 * sin(z * 0.008))
			h -= 7.5 * exp(-pow(river / 26.0, 2.0))
			return h
		"industrial":
			var h := 0.8 + _fbm(x * 0.006, z * 0.006, 2) * 1.8
			h += 17.0 * exp(-pow((x + 210.0) / 80.0, 2.0) - pow((z + 120.0) / 60.0, 2.0))
			h += 12.0 * exp(-pow((x - 230.0) / 70.0, 2.0) - pow((z - 180.0) / 70.0, 2.0))
			# Spoil heaps / embankments framing the compacted factory valley.
			h += 12.0 * exp(-pow((x + 60.0) / 50.0, 2.0) - pow((z + 235.0) / 34.0, 2.0))
			h += 9.0 * exp(-pow((x + 250.0) / 38.0, 2.0) - pow((z - 30.0) / 68.0, 2.0))
			h += 7.0 * exp(-pow((x - 245.0) / 48.0, 2.0) - pow((z + 55.0) / 40.0, 2.0))
			# Handcrafted river valley inside the southern boundary.
			var river_z := 252.0 + 18.0 * sin(x * 0.011)
			h -= 6.0 * exp(-pow((z - river_z) / 24.0, 2.0))
			return h
		"wetlands":
			var h := -0.4 + _fbm(x * 0.007, z * 0.007, 3) * 2.2
			for i in range(3):
				var cz := -210.0 + float(i) * 120.0 + 28.0 * sin(x * 0.007 + float(i) * 1.7)
				h -= 2.6 * exp(-pow((z - cz) / 16.0, 2.0))
			# Keep the southern launch approach dry.
			h += 2.2 * smoothstep(130.0, 210.0, z)
			return h
		_:
			# steppe
			var h := 1.4 + _fbm(x * 0.004, z * 0.004, 3) * 8.0
			h += _fbm(x * 0.02, z * 0.02, 2) * 0.9
			h += 13.0 * exp(-pow((z + 150.0) / 90.0, 2.0)) \
					* (0.7 + 0.3 * _noise2(x * 0.008, 0.0))
			h -= 4.0 * exp(-pow((x - 110.0) / 70.0, 2.0)) \
					* exp(-pow((z - 40.0) / 180.0, 2.0))
			return h


# --------------------------------------------------------------------- noise
static func _hash2(ix: int, iz: int) -> float:
	var h: int = ix * 374761393 + iz * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0x7FFFFFFF) / 2147483647.0


static func _noise2(x: float, z: float) -> float:
	var x0 := int(floor(x))
	var z0 := int(floor(z))
	var fx := x - float(x0)
	var fz := z - float(z0)
	var ux := fx * fx * (3.0 - 2.0 * fx)
	var uz := fz * fz * (3.0 - 2.0 * fz)
	var a := _hash2(x0, z0)
	var b := _hash2(x0 + 1, z0)
	var c := _hash2(x0, z0 + 1)
	var d := _hash2(x0 + 1, z0 + 1)
	return lerpf(lerpf(a, b, ux), lerpf(c, d, ux), uz) * 2.0 - 1.0


static func _fbm(x: float, z: float, octaves: int) -> float:
	var amp := 1.0
	var freq := 1.0
	var total := 0.0
	var norm := 0.0
	for i in range(octaves):
		total += _noise2(x * freq, z * freq) * amp
		norm += amp
		amp *= 0.5
		freq *= 2.03
	return total / maxf(norm, 0.001)


# ------------------------------------------------------------------- trenches
static func _trenches(map_name: String) -> Array:
	if _trench_cache.has(map_name):
		return _trench_cache[map_name]
	var lines: Array = []
	match map_name:
		"steppe":
			lines.append(PackedVector2Array([
				Vector2(-248, -40), Vector2(-175, -68), Vector2(-100, -38),
				Vector2(-25, -66), Vector2(45, -34), Vector2(120, -62),
				Vector2(185, -32), Vector2(248, -52)]))
			lines.append(PackedVector2Array([
				Vector2(-225, -152), Vector2(-135, -128), Vector2(-45, -156),
				Vector2(45, -126), Vector2(135, -152), Vector2(225, -120)]))
			lines.append(PackedVector2Array([
				Vector2(-115, -68), Vector2(-102, 10), Vector2(-65, 84)]))
			lines.append(PackedVector2Array([
				Vector2(145, -60), Vector2(138, 20), Vector2(172, 102)]))
		"village":
			lines.append(PackedVector2Array([
				Vector2(-240, -62), Vector2(-160, -88), Vector2(-80, -58),
				Vector2(10, -86), Vector2(100, -56), Vector2(175, -88), Vector2(240, -64)]))
			lines.append(PackedVector2Array([
				Vector2(-190, -140), Vector2(-90, -120), Vector2(20, -145),
				Vector2(120, -118), Vector2(215, -140)]))
			lines.append(PackedVector2Array([
				Vector2(-40, 30), Vector2(-30, -40), Vector2(-70, -100)]))
		"industrial":
			lines.append(PackedVector2Array([
				Vector2(-252, -148), Vector2(-175, -130), Vector2(-90, -152),
				Vector2(10, -128), Vector2(100, -150), Vector2(185, -126), Vector2(252, -145)]))
			lines.append(PackedVector2Array([
				Vector2(-60, -140), Vector2(-40, -60), Vector2(-90, 20)]))
			lines.append(PackedVector2Array([
				Vector2(155, -140), Vector2(175, -70), Vector2(150, 10)]))
		"wetlands":
			lines.append(PackedVector2Array([
				Vector2(-240, 40), Vector2(-155, 12), Vector2(-75, 40),
				Vector2(20, 10), Vector2(115, 38), Vector2(190, 8), Vector2(248, 30)]))
			lines.append(PackedVector2Array([
				Vector2(-215, -120), Vector2(-110, -95), Vector2(0, -125),
				Vector2(110, -92), Vector2(215, -118)]))
		_:
			lines.append(PackedVector2Array([
				Vector2(-235, -40), Vector2(-120, -40), Vector2(0, -40), Vector2(140, -40)]))
	_trench_cache[map_name] = lines
	return lines


static func _trench_offset(map_name: String, x: float, z: float) -> float:
	var p := Vector2(x, z)
	var cut := 0.0
	var wall := 0.0
	for line in _trenches(map_name):
		var pl: PackedVector2Array = line
		for i in range(pl.size() - 1):
			var a := pl[i]
			var b := pl[i + 1]
			var ab := b - a
			# Cheap bounding-box reject before the segment maths.
			if x < minf(a.x, b.x) - 6.0 or x > maxf(a.x, b.x) + 6.0:
				continue
			if z < minf(a.y, b.y) - 6.0 or z > maxf(a.y, b.y) + 6.0:
				continue
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
			var d := p.distance_to(a + ab * t)
			if d < 2.4:
				var k := 1.0 - d / 2.4
				cut = minf(cut, -1.9 * k * k * (3.0 - 2.0 * k))
			if d < 5.2:
				wall = maxf(wall, exp(-pow((d - 3.2) / 0.9, 2.0)) * 0.85)
	return cut + wall


# -------------------------------------------------------------------- craters
static func _craters(map_name: String) -> Array:
	if _crater_cache.has(map_name):
		return _crater_cache[map_name]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(map_name) * 31 + 7
	var list: Array = []
	var count := 30 if map_name != "wetlands" else 18
	for i in range(count):
		var px := rng.randf_range(-265.0, 265.0)
		var pz := rng.randf_range(-265.0, 265.0)
		# Keep the launch pad clear.
		if Vector2(px, pz).distance_to(Vector2(0, 175)) < 36.0:
			continue
		list.append({
			"pos": Vector2(px, pz),
			"r": rng.randf_range(2.2, 8.5),
			"d": rng.randf_range(0.7, 2.3),
		})
	_crater_cache[map_name] = list
	return list


static func _crater_offset(map_name: String, x: float, z: float) -> float:
	var h := 0.0
	for c in _craters(map_name):
		var pos: Vector2 = c["pos"]
		var r: float = c["r"]
		if absf(x - pos.x) > r * 1.6 or absf(z - pos.y) > r * 1.6:
			continue
		var d := Vector2(x, z).distance_to(pos)
		if d < r:
			var t := 1.0 - d / r
			h -= float(c["d"]) * t * t
		elif d < r * 1.55:
			h += float(c["d"]) * 0.22 * sin((d - r) / (r * 0.55) * PI)
	return h


# ===========================================================================
#  Ground mesh + collision
# ===========================================================================
static func _build_chunk(root: Node3D, map_name: String, ox: float, oz: float,
		size: float, cells: int, mat: Material) -> MeshInstance3D:
	var step := size / float(cells)
	var stride := cells + 3
	var hs := PackedFloat32Array()
	hs.resize(stride * stride)
	for gz in range(stride):
		for gx in range(stride):
			var wx := ox + (float(gx) - 1.0) * step
			var wz := oz + (float(gz) - 1.0) * step
			hs[gz * stride + gx] = _height(map_name, wx, wz)

	var vert_count := (cells + 1) * (cells + 1)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	verts.resize(vert_count)
	normals.resize(vert_count)
	uvs.resize(vert_count)
	colors.resize(vert_count)

	for j in range(cells + 1):
		for i in range(cells + 1):
			var vi := j * (cells + 1) + i
			var h := hs[(j + 1) * stride + (i + 1)]
			var wx := ox + float(i) * step
			var wz := oz + float(j) * step
			verts[vi] = Vector3(float(i) * step, h, float(j) * step)

			var dx := hs[(j + 1) * stride + (i + 2)] - hs[(j + 1) * stride + i]
			var dz := hs[(j + 2) * stride + (i + 1)] - hs[j * stride + (i + 1)]
			var n := Vector3(-dx, 2.0 * step, -dz).normalized()
			normals[vi] = n

			uvs[vi] = Vector2(wx, wz) * 0.08
			# Vertex colour is a cheap per-vertex macro mask consumed by
			# terrain_pbr.gdshader: R = broad 22 m patches (grass vs dirt),
			# G = 3 m grain, B = local slope.  The actual colour lives in the
			# four PBR textures, so no albedo is baked into the vertices.
			var slope := clampf((1.0 - n.y) * 2.6, 0.0, 1.0)
			var patch := _noise2(wx * 0.045 + 11.0, wz * 0.045 - 7.0) * 0.5 + 0.5
			var grain := _noise2(wx * 0.33, wz * 0.33) * 0.5 + 0.5
			colors[vi] = Color(patch, grain, slope, 1.0)

	var indices := PackedInt32Array()
	indices.resize(cells * cells * 6)
	var k := 0
	for j in range(cells):
		for i in range(cells):
			var a := j * (cells + 1) + i
			var b := a + 1
			var c := a + (cells + 1)
			var d := c + 1
			indices[k] = a
			indices[k + 1] = b
			indices[k + 2] = c
			indices[k + 3] = b
			indices[k + 4] = d
			indices[k + 5] = c
			k += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)

	var body := StaticBody3D.new()
	body.position = Vector3(ox, 0.0, oz)
	body.collision_layer = 1
	body.collision_mask = 1
	body.add_to_group("terrain_collision")
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	body.add_child(mi)
	var faces := PackedVector3Array()
	faces.resize(indices.size())
	for i in range(indices.size()):
		faces[i] = verts[indices[i]]
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	root.add_child(body)
	return mi


## Merges the visual meshes of several terrain chunks into one draw call.
## Collision bodies stay per chunk, so physics culling is unchanged.
static func _merge_visual_chunks(root: Node3D, meshes: Array, mat: Material) -> void:
	if meshes.size() < 2:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for mi in meshes:
		if mi == null or mi.mesh == null:
			continue
		st.append_from(mi.mesh, 0, (mi.get_parent() as Node3D).transform)
	var merged := st.commit()
	if merged == null:
		return
	var node := MeshInstance3D.new()
	node.name = "MergedTerrain"
	node.mesh = merged
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(node)
	for mi in meshes:
		if mi != null:
			mi.visible = false


## Distant mountain backdrop: two cheap unshaded rings around the map.  This is
## the scenic horizon from the mobile FPV references and costs two draw calls
## instead of relying on the sky texture alone.
static func _build_mountain_backdrop(root: Node3D, map_name: String) -> void:
	var segments := 256
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(map_name) + 7717
	var ph := [rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU),
			rng.randf_range(0.0, TAU)]
	var h_inner0 := 42.0
	var h_inner1 := 90.0
	var h_outer0 := 75.0
	var h_outer1 := 145.0
	var col_low := Color(0.15, 0.20, 0.15)
	var col_high := Color(0.34, 0.40, 0.42)
	var col_haze := Color(0.70, 0.77, 0.83)
	match map_name:
		"steppe":
			h_inner0 = 26.0
			h_inner1 = 55.0
			h_outer0 = 48.0
			h_outer1 = 92.0
			col_low = Color(0.24, 0.22, 0.14)
			col_high = Color(0.46, 0.44, 0.34)
			col_haze = Color(0.78, 0.77, 0.72)
		"village":
			h_inner0 = 38.0
			h_inner1 = 80.0
			h_outer0 = 70.0
			h_outer1 = 135.0
			col_low = Color(0.13, 0.20, 0.12)
			col_high = Color(0.32, 0.40, 0.34)
			col_haze = Color(0.70, 0.78, 0.84)
		"industrial":
			h_inner0 = 46.0
			h_inner1 = 88.0
			h_outer0 = 84.0
			h_outer1 = 155.0
			col_low = Color(0.16, 0.18, 0.20)
			col_high = Color(0.34, 0.38, 0.42)
			col_haze = Color(0.66, 0.72, 0.78)
		"wetlands":
			h_inner0 = 12.0
			h_inner1 = 26.0
			h_outer0 = 24.0
			h_outer1 = 48.0
			col_low = Color(0.12, 0.17, 0.13)
			col_high = Color(0.28, 0.36, 0.34)
			col_haze = Color(0.68, 0.76, 0.76)

	var rings := [
		{"radius": 1620.0, "base": -55.0, "h0": h_inner0, "h1": h_inner1,
			"bot": col_low, "mid": col_low.lerp(col_high, 0.5),
			"top": col_high, "shift": 0.0, "snow": 9999.0,
			"haze": 0.22},
		{"radius": 2120.0, "base": -55.0, "h0": h_outer0, "h1": h_outer1,
			"bot": col_low.lerp(col_high, 0.35), "mid": col_high,
			"top": col_high.lerp(col_haze, 0.35), "shift": 1.7, "snow": 9999.0,
			"haze": 0.38},
	]
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var rows := 4
	var row_t := [0.0, 0.40, 0.72, 1.0]
	for ring in rings:
		var start := verts.size()
		var bot: Color = ring["bot"]
		var middle: Color = ring["mid"]
		var top: Color = ring["top"]
		var haze := float(ring["haze"])
		for i in range(segments + 1):
			var a := TAU * float(i % segments) / float(segments)
			var x := cos(a) * float(ring["radius"])
			var z := sin(a) * float(ring["radius"])
			var ridge := 0.34 * absf(sin(a * 2.5 + ph[0] + float(ring["shift"])))
			ridge += 0.28 * absf(sin(a * 6.0 + ph[1]))
			ridge += 0.22 * absf(sin(a * 12.0 + ph[2]))
			ridge += 0.16 * absf(sin(a * 21.0 + ph[0] * 1.7 + 0.9))
			var h: float = float(ring["h0"]) + float(ring["h1"]) * pow(ridge, 1.45)
			h = maxf(14.0, h)
			for k in range(rows):
				var t: float = row_t[k]
				var y: float = float(ring["base"]) + (h - float(ring["base"])) * t
				var c: Color
				if t <= 0.40:
					c = bot.lerp(middle, t / 0.40)
				else:
					c = middle.lerp(top, (t - 0.40) / 0.60)
				c = c.lerp(col_haze, haze * (0.35 + 0.65 * t))
				verts.append(Vector3(x, y, z))
				colors.append(c)
		for i in range(segments):
			var b := start + i * rows
			var n := start + (i + 1) * rows
			for k in range(rows - 1):
				indices.append_array([b + k, n + k, b + k + 1,
						b + k + 1, n + k, n + k + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/mountain_backdrop.gdshader")
	mat.set_shader_parameter("color_low", col_low)
	mat.set_shader_parameter("color_high", col_high)
	mat.set_shader_parameter("color_haze", col_haze)
	mat.set_shader_parameter("haze_amount", 0.34)
	mat.set_shader_parameter("base_y", -55.0)
	mat.set_shader_parameter("top_y", h_outer0 + h_outer1)
	var mi := MeshInstance3D.new()
	mi.name = "MountainBackdrop"
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## Zero-collision distant silhouettes outside the shrunk ±307.2 m combat arena so
## every map continues visually toward the mountains with biome-matched landmarks
## at negligible CPU/GPU cost (2-4 unshadowed MultiMeshes total).
static func _build_themed_horizon_props(root: Node3D, map_name: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(map_name) + 9941
	var half_edge := OUTER_SIZE * 0.5  # 307.2 m
	var min_r := half_edge + 55.0
	var max_r := 1120.0
	var unit_box := BoxMesh.new()
	unit_box.size = Vector3.ONE
	var unit_cyl := CylinderMesh.new()
	unit_cyl.top_radius = 1.0
	unit_cyl.bottom_radius = 1.0
	unit_cyl.height = 1.0
	unit_cyl.radial_segments = 10
	unit_cyl.rings = 1

	var cone := CylinderMesh.new()
	cone.top_radius = 0.05
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = 8
	cone.rings = 1

	var _pick_outer := func(avoid_river_x := false) -> Vector2:
		for _t in range(24):
			var ang := rng.randf_range(0.0, TAU)
			var rad := rng.randf_range(min_r, max_r)
			var px := cos(ang) * rad
			var pz := sin(ang) * rad
			if absf(px) < half_edge + 35.0 and absf(pz) < half_edge + 35.0:
				continue
			if avoid_river_x and absf(px + 170.0) < 60.0:
				continue
			return Vector2(px, pz)
		return Vector2(min_r + 80.0, 0.0)

	var _add_bg_mm := func(name_id: String, mesh: Mesh, col: Color,
			xfs: Array, colors: Array = [], unshaded := false) -> void:
		if xfs.is_empty():
			return
		var mat := _mat(col, 0.96, 0.0)
		mat.disable_receive_shadows = true
		if unshaded:
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		if not colors.is_empty():
			mat.vertex_color_use_as_albedo = true
			mat.vertex_color_is_srgb = true
		var mmi := _multimesh(root, name_id, mesh, mat, xfs, false, colors)
		if mmi != null:
			mmi.visibility_range_begin = 140.0
			mmi.visibility_range_begin_margin = 40.0
			mmi.visibility_range_end = 2100.0
			mmi.visibility_range_end_margin = 150.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

	match map_name:
		"industrial":
			# Distant factory belt: cooling towers, tall chimneys, large halls, smoke discs.
			var hall_xfs: Array = []
			var hall_cols: Array = []
			var tower_xfs: Array = []
			var stack_xfs: Array = []
			var smoke_xfs: Array = []
			for i in range(44):
				var p: Vector2 = _pick_outer.call(false)
				var y := _height(map_name, p.x, p.y)
				var yaw := rng.randf_range(0.0, PI)
				var w := rng.randf_range(26.0, 62.0)
				var h := rng.randf_range(9.0, 18.0)
				var d := rng.randf_range(16.0, 32.0)
				hall_xfs.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(w, h, d)),
						Vector3(p.x, y + h * 0.45, p.y)))
				var g := rng.randf_range(0.24, 0.40)
				hall_cols.append(Color(g + 0.02, g + 0.01, g - 0.01))
			for i in range(14):
				var p: Vector2 = _pick_outer.call(false)
				var y := _height(map_name, p.x, p.y)
				var rad := rng.randf_range(8.5, 14.0)
				var h := rng.randf_range(26.0, 42.0)
				tower_xfs.append(Transform3D(Basis().scaled(Vector3(rad, h, rad)),
						Vector3(p.x, y + h * 0.45, p.y)))
				if i % 2 == 0:
					smoke_xfs.append(Transform3D(Basis().scaled(Vector3(16.0, 5.5, 16.0)),
							Vector3(p.x + 8.0, y + h + 10.0, p.y - 4.0)))
			for i in range(22):
				var p: Vector2 = _pick_outer.call(false)
				var y := _height(map_name, p.x, p.y)
				var h := rng.randf_range(34.0, 62.0)
				stack_xfs.append(Transform3D(Basis().scaled(Vector3(2.2, h, 2.2)),
						Vector3(p.x, y + h * 0.48, p.y)))
			_add_bg_mm.call("BgIndHalls", unit_box, Color(0.32, 0.32, 0.30), hall_xfs, hall_cols)
			_add_bg_mm.call("BgIndCoolingTowers", unit_cyl, Color(0.42, 0.42, 0.40), tower_xfs)
			_add_bg_mm.call("BgIndStacks", unit_cyl, Color(0.36, 0.24, 0.20), stack_xfs)
			_add_bg_mm.call("BgIndPlumes", unit_cyl, Color(0.68, 0.72, 0.75), smoke_xfs, [], true)

		"steppe":
			# Endless steppe: distant windbreak treeline strips, wind turbines, grain silos & barns.
			var tree_xfs: Array = []
			var tree_cols: Array = []
			var turbine_xfs: Array = []
			var turbine_blade_xfs: Array = []
			var barn_xfs: Array = []
			for i in range(36):
				var p: Vector2 = _pick_outer.call(false)
				var yaw := rng.randf_range(0.0, TAU)
				var dir := Vector2(cos(yaw), sin(yaw))
				var count := rng.randi_range(6, 11)
				for j in range(count):
					var q := p + dir * (float(j) * 14.0)
					var y := _height(map_name, q.x, q.y)
					var s := rng.randf_range(5.5, 10.5)
					tree_xfs.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s * 1.15, s)),
							Vector3(q.x, y + s * 0.45, q.y)))
					tree_cols.append(Color(rng.randf_range(0.18, 0.28), rng.randf_range(0.24, 0.34), rng.randf_range(0.12, 0.18)))
			for i in range(18):
				var p: Vector2 = _pick_outer.call(false)
				var y := _height(map_name, p.x, p.y)
				var h := rng.randf_range(44.0, 68.0)
				turbine_xfs.append(Transform3D(Basis().scaled(Vector3(1.1, h, 1.1)),
						Vector3(p.x, y + h * 0.5, p.y)))
				# Crossbar representing turbine rotor from afar
				turbine_blade_xfs.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, PI)).scaled(Vector3(24.0, 1.4, 1.4)),
						Vector3(p.x, y + h - 1.5, p.y)))
			for i in range(20):
				var p: Vector2 = _pick_outer.call(false)
				var y := _height(map_name, p.x, p.y)
				barn_xfs.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(22.0, 9.0, 14.0)),
						Vector3(p.x, y + 4.0, p.y)))
			_add_bg_mm.call("BgSteppeShelterbelts", cone, Color.WHITE, tree_xfs, tree_cols)
			_add_bg_mm.call("BgSteppeTurbines", unit_cyl, Color(0.80, 0.82, 0.80), turbine_xfs)
			_add_bg_mm.call("BgSteppeTurbineBlades", unit_cyl, Color(0.80, 0.82, 0.80), turbine_blade_xfs)
			_add_bg_mm.call("BgSteppeBarns", unit_box, Color(0.46, 0.40, 0.30), barn_xfs)

		"village":
			# Countryside vista: distant farm cottages, red-tiled roofs, woods & spires.
			var wall_xfs: Array = []
			var roof_xfs: Array = []
			var tree_xfs: Array = []
			var tree_cols: Array = []
			for i in range(52):
				var p: Vector2 = _pick_outer.call(true)
				var y := _height(map_name, p.x, p.y)
				var yaw := rng.randf_range(0.0, TAU)
				var w := rng.randf_range(9.0, 15.0)
				var d := rng.randf_range(7.0, 11.0)
				var h := rng.randf_range(4.2, 6.2)
				wall_xfs.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(w, h, d)),
						Vector3(p.x, y + h * 0.45, p.y)))
				roof_xfs.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(w * 0.72, 3.2, d * 0.72)),
						Vector3(p.x, y + h + 1.4, p.y)))
			for i in range(180):
				var p: Vector2 = _pick_outer.call(false)
				var y := _height(map_name, p.x, p.y)
				var s := rng.randf_range(6.0, 12.0)
				tree_xfs.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(s, s * 1.25, s)),
						Vector3(p.x, y + s * 0.5, p.y)))
				tree_cols.append(Color(rng.randf_range(0.14, 0.24), rng.randf_range(0.24, 0.36), rng.randf_range(0.10, 0.16)))
			_add_bg_mm.call("BgVillageWalls", unit_box, Color(0.76, 0.72, 0.64), wall_xfs)
			_add_bg_mm.call("BgVillageRoofs", cone, Color(0.54, 0.26, 0.18), roof_xfs)
			_add_bg_mm.call("BgVillageWoods", cone, Color.WHITE, tree_xfs, tree_cols)

		"wetlands":
			# Endless marsh delta: distant backwater lagoons, reed-covered islets & marsh trees.
			var lagoon_xfs: Array = []
			var islet_xfs: Array = []
			var tree_xfs: Array = []
			var wl := water_level(map_name)
			for i in range(48):
				var p: Vector2 = _pick_outer.call(false)
				var yaw := rng.randf_range(0.0, TAU)
				var sx := rng.randf_range(55.0, 140.0)
				var sz := rng.randf_range(35.0, 95.0)
				lagoon_xfs.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(sx, 0.3, sz)),
						Vector3(p.x, wl + 0.08, p.y)))
			for i in range(160):
				var p: Vector2 = _pick_outer.call(false)
				var s := rng.randf_range(7.0, 16.0)
				islet_xfs.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(s, 1.4, s * 0.8)),
						Vector3(p.x, wl + 0.4, p.y)))
				var ts := rng.randf_range(4.5, 9.5)
				tree_xfs.append(Transform3D(Basis().scaled(Vector3(ts * 0.7, ts * 1.4, ts * 0.7)),
						Vector3(p.x + rng.randf_range(-4.0, 4.0), wl + ts * 0.6, p.y + rng.randf_range(-4.0, 4.0))))
			_add_bg_mm.call("BgWetLagoons", unit_box, Color(0.11, 0.24, 0.25), lagoon_xfs, [], true)
			_add_bg_mm.call("BgWetIslets", unit_cyl, Color(0.22, 0.27, 0.14), islet_xfs)
			_add_bg_mm.call("BgWetTrees", cone, Color(0.14, 0.21, 0.11), tree_xfs)


## Static freight train + rails: the strongest composition anchor from the
## mobile FPV references.  Boxes share a handful of materials, so the static
## batching pass merges the whole train into ~5 draw calls.
static func _build_freight_train(root: Node3D, map_name: String) -> void:
	if map_name != "industrial" and map_name != "village":
		return
	var z := -15.0
	var start_x := -50.0
	var car_len := 13.0
	var gap := 2.0
	var palette := {
		"loco": Color(0.72, 0.58, 0.15),
		"blue": Color(0.16, 0.30, 0.44),
		"red": Color(0.55, 0.16, 0.12),
		"green": Color(0.18, 0.34, 0.20),
		"dark": Color(0.09, 0.09, 0.09),
		"rail": Color(0.30, 0.29, 0.27),
	}
	var groups := {}
	for key in palette.keys():
		groups[key] = []
	var order := ["loco", "blue", "red", "green", "blue", "red"]
	for i in range(order.size()):
		var x := start_x + float(i) * (car_len + gap)
		var y := _height(map_name, x, z) + 2.2
		var key: String = order[i]
		groups[key].append(Transform3D(Basis().scaled(
				Vector3(car_len, 2.8, 2.6)), Vector3(x, y, z)))
		# Solid collision for each train car
		var car_body := StaticBody3D.new()
		car_body.name = "TrainCarCol_%d" % i
		car_body.position = Vector3(x, y, z)
		car_body.collision_layer = 1
		car_body.collision_mask = 1
		var car_cs := CollisionShape3D.new()
		var car_shape := BoxShape3D.new()
		car_shape.size = Vector3(car_len, 2.8, 2.6)
		car_cs.shape = car_shape
		car_body.add_child(car_cs)
		root.add_child(car_body)
		if i == 0:
			groups[key].append(Transform3D(Basis().scaled(
					Vector3(4.6, 2.2, 2.3)), Vector3(x - 2.0, y + 2.3, z)))
			groups["dark"].append(Transform3D(Basis().scaled(
					Vector3(1.1, 1.4, 1.1)), Vector3(x + 3.6, y + 2.0, z)))
			groups["dark"].append(Transform3D(Basis().scaled(
					Vector3(1.8, 1.8, 2.2)),
					Vector3(x + car_len * 0.5 - 0.7, y - 0.2, z)))
		groups["dark"].append(Transform3D(Basis().scaled(
				Vector3(car_len + 0.4, 0.25, 2.7)), Vector3(x, y + 1.55, z)))
		for wx in [-car_len * 0.33, car_len * 0.33]:
			for wz in [-0.85, 0.85]:
				groups["dark"].append(Transform3D(Basis().scaled(
						Vector3(0.9, 0.9, 0.32)),
						Vector3(x + wx, y - 1.55, z + wz)))
	# Rails and sleepers follow the terrain height in 4 m pieces.
	var total := float(order.size()) * (car_len + gap) + 26.0
	var x0 := start_x - 13.0
	for i in range(int(total / 4.0)):
		var x := x0 + float(i) * 4.0
		var y := _height(map_name, x + 2.0, z)
		for rz in [-0.78, 0.78]:
			groups["rail"].append(Transform3D(Basis().scaled(
					Vector3(4.05, 0.10, 0.12)),
					Vector3(x + 2.0, y + 0.10, z + rz)))
		if i % 2 == 0:
			groups["dark"].append(Transform3D(Basis().scaled(
					Vector3(0.24, 0.10, 2.1)),
					Vector3(x + 2.0, y + 0.03, z)))
	var unit := BoxMesh.new()
	unit.size = Vector3.ONE
	for key in groups.keys():
		if groups[key].is_empty():
			continue
		_multimesh(root, "FreightTrain_" + key, unit, _mat(palette[key], 0.85),
				groups[key], true)


## Hand-placed industrial skyline for the factory map: a second hall, brick
## chimney, cooling tower, silos, warehouses and container stacks.  All boxes
## share cached PBR materials, so the static batching pass collapses them into
## a handful of draw calls.
static func _build_industrial_complex(root: Node3D) -> void:
	var concrete := _pbr("concrete", Color(0.78, 0.76, 0.71), 0.30)
	var brick := _pbr("brick", Color(0.62, 0.42, 0.34), 0.35)
	var steel := _mat(Color(0.42, 0.45, 0.47), 0.70)
	var rust := _mat(Color(0.40, 0.24, 0.16), 0.80)
	var roof := _mat(Color(0.20, 0.17, 0.15), 0.85)
	var glass := _mat(Color(0.045, 0.055, 0.07), 0.25)
	glass.metallic = 0.3
	glass.metallic_specular = 0.8
	var h := func(x: float, z: float) -> float: return _height("industrial", x, z)

	# Secondary factory hall to the west, with a window strip.
	var hx := -125.0
	var hz := 80.0
	var hy: float = h.call(hx, hz)
	_add_box(root, Vector3(hx, hy + 9.0, hz), Vector3(70.0, 18.0, 26.0),
			concrete, 0.0, true)
	_add_box(root, Vector3(hx, hy + 18.5, hz), Vector3(71.0, 0.7, 27.0),
			roof, 0.0, false)
	for i in range(6):
		var wz := hz - 10.0 + float(i) * 4.0
		# Large panoramic industrial windows with dark steel frames
		_add_box(root, Vector3(hx + 35.2, hy + 11.0, wz),
				Vector3(0.25, 2.6, 3.2), steel, 0.0, false)
		_add_box(root, Vector3(hx + 35.2, hy + 6.0, wz),
				Vector3(0.25, 2.6, 3.2), steel, 0.0, false)

	# Brick chimney: hollow, open top + a base arch (two fly-through openings).
	var cx := -55.0
	var cz := 35.0
	var cy: float = h.call(cx, cz)
	var chimney_inner := _pbr("brick", Color(0.42, 0.26, 0.20), 0.45)
	_open_tower(root, Vector3(cx, cy, cz), 3.4, 0.55, 36.0, brick, chimney_inner,
			{"deg": 62.0, "min_h": 0.0, "max_h": 5.0, "count": 2},
			"IndustrialChimney")
	for bh in [6.0, 30.0, 35.0]:
		_add_ring(root, Vector3(cx, cy + bh, cz), 3.55, 0.15, rust)

	# Cooling tower: hyperboloid profile, wide open top and a base bay.
	var tx := 155.0
	var tz := 30.0
	var ty: float = h.call(tx, tz)
	var cooling: Array[Vector2] = [
		Vector2(13.0, 0.0), Vector2(12.2, 3.0), Vector2(10.4, 10.0),
		Vector2(10.0, 16.0), Vector2(10.6, 21.0), Vector2(11.5, 26.0),
	]
	var tower_inner := _pbr("concrete", Color(0.56, 0.54, 0.50), 0.40)
	_open_tower_profile(root, Vector3(tx, ty, tz), cooling, 0.8,
			concrete, tower_inner,
			{"deg": 65.0, "min_h": 0.0, "max_h": 8.0, "count": 2},
			"IndustrialCoolingTower")

	# Storage silos: standalone individual placement (поодиноко) with open dive top & base bays.
	var silo_outer := _pbr("steel", Color(0.70, 0.72, 0.74), 0.22)
	var silo_inner := _pbr("concrete", Color(0.62, 0.60, 0.56), 0.38)
	var ind_silo_coords: Array[Vector2] = [
		Vector2(26.0, -32.0),
		Vector2(-50.0, 0.0),
	]
	for idx in range(ind_silo_coords.size()):
		var sp := ind_silo_coords[idx]
		var sy: float = h.call(sp.x, sp.y)
		_open_tower(root, Vector3(sp.x, sy, sp.y), 4.2, 0.5, 16.0, silo_outer, silo_inner,
				{"deg": 72.0, "min_h": 0.0, "max_h": 3.5, "count": 2},
				"IndustrialSilo%d" % idx)
		_add_ring(root, Vector3(sp.x, sy + 15.6, sp.y), 4.25, 0.25, rust)
		_add_ring(root, Vector3(sp.x, sy + 8.0, sp.y), 4.25, 0.15, steel)

	# Warehouse row north of the main hall (clear of the west tutorial lane).
	for i in range(2):
		var wx := 36.0 + float(i) * 46.0
		var wz := 165.0
		var wy: float = h.call(wx, wz)
		_add_box(root, Vector3(wx, wy + 5.0, wz), Vector3(40.0, 10.0, 18.0),
				steel, 0.0, true)
		_add_box(root, Vector3(wx, wy + 10.4, wz), Vector3(40.8, 0.5, 18.8),
				rust, 0.0, false)
		for j in range(5):
			_add_box(root, Vector3(wx - 14.0 + float(j) * 7.0, wy + 5.0, wz + 9.2),
					Vector3(4.0, 5.0, 0.2), roof, 0.0, false)

	# Container stacks near the rails.
	var palette := [Color(0.16, 0.30, 0.44), Color(0.55, 0.16, 0.12),
			Color(0.18, 0.34, 0.20), Color(0.62, 0.52, 0.18)]
	for i in range(8):
		var bx := -38.0 + float(i % 4) * 7.0
		var bz := 22.0 + float(i / 4) * 3.4
		var by: float = h.call(bx, bz)
		var mat := _mat(palette[i % palette.size()], 0.75)
		if i >= 4:
			by += 2.7
		_add_box(root, Vector3(bx, by + 1.4, bz), Vector3(6.4, 2.7, 2.6),
				mat, 0.0, false)


## Handcrafted river + bridge for the industrial valley.  The terrain height
## carves the channel; this adds the water ribbon and a concrete road bridge.
static func _build_industrial_river(root: Node3D) -> void:
	var steps := 96
	var half_w := 20.0
	var y := -2.2
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	for i in range(steps + 1):
		var x := -307.2 + 614.4 * float(i) / float(steps)
		var zc := 252.0 + 18.0 * sin(x * 0.011)
		verts.append(Vector3(x, y, zc - half_w))
		verts.append(Vector3(x, y, zc + half_w))
	for i in range(steps):
		var b := i * 2
		indices.append_array([b, b + 2, b + 1, b + 1, b + 2, b + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.10, 0.26, 0.32)
	water.roughness = 0.12
	water.metallic = 0.0
	water.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.name = "RiverWater"
	mi.mesh = mesh
	mi.material_override = water
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)

	# Concrete bridge across the channel at the map centre.
	var conc := _mat(Color(0.56, 0.54, 0.49), 0.9)
	var steel := _mat(Color(0.24, 0.25, 0.26), 0.8)
	var zc0 := 252.0
	_add_box(root, Vector3(0.0, 1.4, zc0), Vector3(36.0, 1.2, 17.0), conc,
			0.0, true)
	for px in [-14.0, 14.0]:
		for pz in [-6.5, 6.5]:
			_add_cylinder(root, Vector3(px, -2.4, zc0 + pz), 1.2, 9.0, conc,
					0.0, true)
	for px in [-16.0, 16.0]:
		_add_box(root, Vector3(px, 0.6, zc0), Vector3(1.0, 4.4, 17.0), conc,
				0.0, false)
	_add_box(root, Vector3(0.0, 2.4, zc0 - 7.6), Vector3(36.0, 0.35, 0.35),
			steel, 0.0, false)
	_add_box(root, Vector3(0.0, 2.4, zc0 + 7.6), Vector3(36.0, 0.35, 0.35),
			steel, 0.0, false)


static func spawn_handcrafted_on_ground(level: Node3D, path: String,
		x: float, z: float, yaw: float = 0.0) -> Node3D:
	if level == null or not is_instance_valid(level):
		return null
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var space := level.get_world_3d().direct_space_state
	var y := 0.0
	if space != null:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 400.0, z),
				Vector3(x, -200.0, z))
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			y = (hit["position"] as Vector3).y
	var n := ps.instantiate()
	level.add_child(n)
	n.position = Vector3(x, y, z)
	n.rotation.y = yaw
	_apply_triplanar(n)
	return n


## Handcrafted industrial assets exported from Blender (PBR factory kit and a
## detailed freight train).  They replace the box-based placeholder complex.
static func _spawn_handcrafted_assets(root: Node3D, map_name: String) -> void:
	var specs := {
		"industrial": [
			["res://Assets/handcrafted/factory_complex.glb",
				Vector3(-200.0, _height("industrial", -200.0, -180.0) - 0.15, -180.0)],
			["res://Assets/handcrafted/freight_train.glb",
				Vector3(0.0, _height("industrial", 0.0, -15.0) - 0.10, -15.0)],
		],
		"village": [
			["res://Assets/handcrafted/village_house.glb",
				Vector3(60.0, _height("village", 60.0, -110.0) - 0.15, -110.0)],
		],
		"steppe": [
			["res://Assets/handcrafted/farm_complex.glb",
				Vector3(40.0, _height("steppe", 40.0, 146.0) - 0.15, 146.0)],
		],
		"wetlands": [
			["res://Assets/handcrafted/wetlands_dock.glb",
				Vector3(-60.0, _height("wetlands", -60.0, -140.0) - 0.10, -140.0)],
		],
	}
	for spec in specs.get(map_name, []):
		var path: String = spec[0]
		if not ResourceLoader.exists(path):
			continue
		var ps := load(path) as PackedScene
		if ps == null:
			continue
		var n := ps.instantiate()
		n.name = "Handcrafted_" + path.get_file().get_basename()
		root.add_child(n)
		n.position = spec[1]
		_apply_triplanar(n)
		if path.ends_with("factory_complex.glb"):
			_replace_factory_chimney(root, n)
		elif path.ends_with("farm_complex.glb"):
			_replace_farm_silos(root, n)
		_hide_handcrafted_windows(n)
		_add_handcrafted_collision(n)


## The authored factory chimney is a closed square stack with no openings; a
## Boolean tunnel did not survive the glTF round-trip reliably.  Replace the
## visual mesh with a segmented shell that has two large opposite openings
## (about 4.6 x 8 m) and matching trimesh collision, so the pilot can fly
## through the tower.  The rest of the factory GLB is untouched.
static func _replace_factory_chimney(root: Node3D, factory: Node3D) -> void:
	for child in factory.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi != null and (String(mi.name).to_lower().begins_with("chim") \
				or String(mi.name).to_lower() == "factory_facade_detail"):
			mi.visible = false
	# The old solid stack was cut out of hall_main (Blender).  The open-top
	# replacement stands just east of the hall, clear of its wall and roof, so
	# both the top and the base arches are open to the outside air.
	var center := Vector3(-90.0, 0.0, -146.0)
	center.y = _height("industrial", center.x, center.z)
	var local_base := root.to_local(center)
	var height := 32.0
	var radius := 4.0
	var mat := _pbr("brick", Color(0.50, 0.23, 0.15), 0.38)
	var chimney_inner := _pbr("brick", Color(0.42, 0.26, 0.20), 0.45)
	_open_tower(root, local_base, radius, 0.72, height, mat, chimney_inner,
			{"deg": 70.0, "min_h": 0.0, "max_h": 6.0, "count": 2},
			"FactoryChimneyTop")
	for h in [7.6, 19.5, 31.2]:
		_add_ring(root, local_base + Vector3(0.0, h, 0.0),
				radius + 0.05, 0.15, mat)
	# Hyperboloid open-top cooling tower at (-72, -214) replacing the capped GLB tower.
	var concrete := _pbr("concrete", Color(0.76, 0.74, 0.69), 0.30)
	var steel := _pbr("steel", Color(0.70, 0.72, 0.74), 0.22)
	var rust := _pbr("steel", Color(0.48, 0.28, 0.18), 0.34)
	var tower_inner := _pbr("concrete", Color(0.56, 0.54, 0.50), 0.40)
	var ct_pos := Vector3(-72.0, _height("industrial", -72.0, -214.0), -214.0)
	var ct_profile: Array[Vector2] = [
		Vector2(14.5, 0.0), Vector2(13.5, 4.0), Vector2(11.2, 12.0),
		Vector2(10.5, 19.0), Vector2(11.3, 25.0), Vector2(12.2, 30.0),
	]
	_open_tower_profile(root, root.to_local(ct_pos), ct_profile, 0.80,
			concrete, tower_inner,
			{"deg": 65.0, "min_h": 0.0, "max_h": 7.5, "count": 2},
			"FactoryCoolingTower")
	# Standalone open-top cylindrical silos placed in open yard clear of roof eaves and workshops.
	var silo_inner := _pbr("concrete", Color(0.62, 0.60, 0.56), 0.38)
	var fac_silos: Array[Vector2] = [
		Vector2(-140.0, 20.0),
		Vector2(140.0, -50.0),
	]
	for i in range(fac_silos.size()):
		var fsp := fac_silos[i]
		var spos := Vector3(fsp.x, _height("industrial", fsp.x, fsp.y), fsp.y)
		_open_tower(root, root.to_local(spos), 4.5, 0.72, 19.0, steel, silo_inner,
				{"deg": 70.0, "min_h": 0.0, "max_h": 4.2, "count": 2},
				"FactorySilo%d" % i)
		for sh in [6.2, 12.5, 18.4]:
			_add_ring(root, root.to_local(spos) + Vector3(0.0, sh, 0.0),
					4.56, 0.12, rust)


static func _replace_farm_silos(root: Node3D, farm: Node3D) -> void:
	for child in farm.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi != null and (String(mi.name).to_lower().begins_with("silo") \
				or String(mi.name).to_lower().begins_with("wind") \
				or String(mi.name).to_lower().begins_with("head")):
			mi.visible = false
	var steel := _pbr("steel", Color(0.72, 0.74, 0.75), 0.20)
	var rust := _pbr("steel", Color(0.48, 0.30, 0.19), 0.34)
	var silo_inner := _pbr("concrete", Color(0.62, 0.60, 0.56), 0.38)
	# Standalone grain silos (поодиноко) in open paddocks clear of tracks, tree lines and workshops.
	var farm_silo_coords: Array[Vector2] = [
		Vector2(-180.0, 220.0),
		Vector2(240.0, -120.0),
	]
	for i in range(farm_silo_coords.size()):
		var fsp := farm_silo_coords[i]
		var spos := Vector3(fsp.x, _height("steppe", fsp.x, fsp.y), fsp.y)
		_open_tower(root, root.to_local(spos), 4.6, 0.72, 20.5, steel, silo_inner,
				{"deg": 70.0, "min_h": 0.0, "max_h": 4.2, "count": 2},
				"SteppeFarmSilo%d" % i)
		for sh in [6.5, 13.5, 19.8]:
			_add_ring(root, root.to_local(spos) + Vector3(0.0, sh, 0.0),
					4.66, 0.15, rust)


## Shared hook used by the procedural map decoration as well.
static func _open_tower(root: Node3D, base: Vector3, radius: float, wall: float,
		height: float, outer_mat: Material, inner_mat: Material, opening := {},
		node_name := "OpenTower") -> MeshInstance3D:
	return OPEN_TOWER.build_cylinder(root, base, radius, wall, height,
			outer_mat, inner_mat, opening, 32, node_name)


static func _open_tower_profile(root: Node3D, base: Vector3,
		profile: Array[Vector2], wall: float, outer_mat: Material,
		inner_mat: Material, opening := {},
		node_name := "OpenTower") -> MeshInstance3D:
	return OPEN_TOWER.build_profile(root, base, profile, wall, outer_mat,
			inner_mat, opening, 32, node_name)


## The authored kit uses glass panes and window cards on otherwise solid walls.
## The player asked for real openings, not windows, so remove the window cards;
## the Boolean-cut door/tunnel openings are the way in and out.
static func _hide_handcrafted_windows(node: Node) -> void:
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null:
			continue
		var nm := String(mi.name).to_lower()
		if nm.contains("win") or nm.contains("glass"):
			mi.visible = false


## Static trimesh collision for the authored handcrafted kit.  The GLBs were
## visual-only; the factory, cottages, barn and train could be flown through.
## Boolean-cut door openings are part of the same mesh, so they stay flyable.
## Adds collision for every surface of a mesh.  A multi-surface GLB mesh gave
## only one collidable surface with `create_trimesh_shape()`, which let the
## player fly through some walls/roofs (the village fly-through report).
static func _add_mesh_collision(body: StaticBody3D, mi: MeshInstance3D) -> void:
	if body == null or mi == null or mi.mesh == null:
		return
	for s in range(mi.mesh.get_surface_count()):
		var arrays := mi.mesh.surface_get_arrays(s)
		if arrays == null or arrays.size() == 0 \
				or arrays[Mesh.ARRAY_VERTEX] == null:
			continue
		var sm := ArrayMesh.new()
		sm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var shape := sm.create_trimesh_shape()
		if shape == null:
			continue
		shape.backface_collision = false
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.transform = mi.transform
		body.add_child(cs)


static func _add_handcrafted_collision(node: Node3D) -> void:
	# One small StaticBody per visual mesh, parented to the mesh itself.  The
	# shape is therefore in mesh-local space and inherits every parent transform
	# without relying on global transforms being up to date during map build.
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.visible:
			continue
		mi.set_meta("no_batch", true)
		var body := StaticBody3D.new()
		body.name = "HandcraftedCol_" + String(mi.name)
		body.collision_layer = 1
		body.collision_mask = 1
		for s in range(mi.mesh.get_surface_count()):
			var arrays := mi.mesh.surface_get_arrays(s)
			if arrays == null or arrays.size() == 0 \
					or arrays[Mesh.ARRAY_VERTEX] == null:
				continue
			var sm := ArrayMesh.new()
			sm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var shape := sm.create_trimesh_shape()
			if shape == null:
				continue
			shape.backface_collision = false
			var cs := CollisionShape3D.new()
			cs.shape = shape
			body.add_child(cs)
		mi.add_child(body)
	# Explicit thick roof safety slabs (1.2 m thick) for hollow handcrafted buildings
	# so high-speed FPV dives cannot tunnel into attics/halls.
	var roof_slabs: Array = []
	var nname := String(node.name)
	if nname == "Handcrafted_factory_complex":
		roof_slabs = [
			[Vector3(0.0, 20.1, 0.0), Vector3(64.4, 1.2, 26.4)],
			[Vector3(-92.0, 15.1, -24.0), Vector3(48.4, 1.2, 20.4)],
			[Vector3(96.0, 13.1, 18.0), Vector3(42.4, 1.2, 18.4)],
			[Vector3(-34.0, 10.1, -96.0), Vector3(40.4, 1.2, 18.4)],
			[Vector3(18.0, 10.1, -96.0), Vector3(40.4, 1.2, 18.4)],
		]
	elif nname == "Handcrafted_farm_complex":
		roof_slabs = [
			[Vector3(-25.0, 6.4, -2.0), Vector3(40.4, 1.2, 16.4)],
			[Vector3(10.0, 5.2, 28.0), Vector3(32.4, 1.2, 13.4)],
		]
	elif nname == "Handcrafted_village_house":
		roof_slabs = [
			[Vector3(-18.0, 4.1, 0.0), Vector3(12.4, 1.2, 8.4)],
			[Vector3(2.0, 3.7, -2.0), Vector3(9.4, 1.2, 7.4)],
			[Vector3(20.0, 3.9, 3.0), Vector3(10.4, 1.2, 7.4)],
			[Vector3(34.0, 5.8, -12.0), Vector3(16.4, 1.2, 12.4)],
			[Vector3(-34.0, 6.2, -8.0), Vector3(8.4, 1.2, 8.4)],
		]
	elif nname == "Handcrafted_wetlands_dock":
		roof_slabs = [
			[Vector3(0.0, 4.6, 2.0), Vector3(18.4, 1.2, 10.4)],
			[Vector3(22.0, 4.0, -4.0), Vector3(14.4, 1.2, 8.4)],
		]
	if not roof_slabs.is_empty():
		var rbody := StaticBody3D.new()
		rbody.name = "HandcraftedRoofSafety"
		rbody.collision_layer = 1
		rbody.collision_mask = 1
		for slab in roof_slabs:
			var cs := CollisionShape3D.new()
			var bshape := BoxShape3D.new()
			bshape.size = slab[1]
			cs.shape = bshape
			cs.position = slab[0]
			rbody.add_child(cs)
		node.add_child(rbody)


## World-space triplanar texturing for the Blender kit: box faces no longer
## stretch the albedo/normal maps, so concrete/brick keep a constant texel
## density on every building.
static func _apply_triplanar(node: Node) -> void:
	var seen := {}
	for mi_node in node.find_children("*", "MeshInstance3D", true, false):
		var mi := mi_node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			var mat: Material = mi.get_surface_override_material(s)
			if mat == null:
				mat = mi.mesh.surface_get_material(s)
			var sm := mat as StandardMaterial3D
			if sm == null or sm.albedo_texture == null:
				continue
			var id := sm.get_instance_id()
			if seen.has(id):
				continue
			seen[id] = true
			sm.uv1_triplanar = true
			sm.uv1_world_triplanar = true
			# Per-family world scale: brick and roof tiles need a much tighter
			# tile than 4.5 m concrete panels or they read as painted-on noise.
			var tex_path := ""
			if sm.albedo_texture != null:
				tex_path = sm.albedo_texture.resource_path.to_lower()
			var tri_scale := 0.22
			var tint := Color(1.0, 1.0, 1.0)
			if tex_path.contains("brick"):
				tri_scale = 0.55
				tint = Color(0.54, 0.31, 0.24)
			elif tex_path.contains("roof"):
				tri_scale = 0.45
				tint = Color(0.62, 0.58, 0.54)
			elif tex_path.contains("metal"):
				tri_scale = 0.30
				tint = Color(0.48, 0.51, 0.54)
			elif tex_path.contains("concrete"):
				tint = Color(0.66, 0.64, 0.60)
			sm.albedo_color = tint
			sm.uv1_scale = Vector3(tri_scale, tri_scale, tri_scale)
			# Authored shells are open; from inside/inverted FPV the backfaces
			# used to disappear and the player saw the sky through the roof.
			sm.cull_mode = BaseMaterial3D.CULL_DISABLED


## Farmland patches: a textured, terrain-conforming grid of crop rows.  This is
## the cheap density that makes the open maps read as working farmland instead
## of an empty green field.
static func _build_crop_fields(root: Node3D, map_name: String) -> void:
	var tex := load("res://Assets/handcrafted/textures/crop_rows.png") as Texture2D
	if tex == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(map_name) + 5150
	# Muted field tints: the raw crop texture read as bright lime next to the
	# terrain palette in the owner's recording.  Per-field vertex colours give
	# variety without extra materials.
	var field_tints := [
		Color(0.78, 0.80, 0.58), Color(0.86, 0.80, 0.52),
		Color(0.66, 0.76, 0.50), Color(0.72, 0.70, 0.46),
	]
	var placed := 0
	var fields: Array = []
	for _i in range(22):
		var x := rng.randf_range(-250.0, 250.0)
		var z := rng.randf_range(-250.0, 250.0)
		if _hall_clear_zone(map_name, x, z):
			continue
		if map_name == "industrial" \
				and Vector2(x, z).distance_to(Vector2(-200.0, -180.0)) < 155.0:
			continue
		if map_name == "village" \
				and Vector2(x, z).distance_to(Vector2(60.0, -110.0)) < 70.0:
			continue
		if map_name == "steppe" \
				and Vector2(x, z).distance_to(Vector2(40.0, 146.0)) < 80.0:
			continue
		if map_name == "wetlands" \
				and Vector2(x, z).distance_to(Vector2(-60.0, -140.0)) < 70.0:
			continue
		var w := rng.randf_range(38.0, 68.0)
		var d := rng.randf_range(30.0, 52.0)
		var cells := 8
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		var uvs := PackedVector2Array()
		var colors := PackedColorArray()
		var idx := PackedInt32Array()
		var tint: Color = field_tints[placed % field_tints.size()]
		for cz in range(cells + 1):
			for cx in range(cells + 1):
				var px := x - w * 0.5 + w * float(cx) / float(cells)
				var pz := z - d * 0.5 + d * float(cz) / float(cells)
				# Use the rendered terrain triangle height, not the analytic
				# field, so the crop plane cannot hover over a slope.
				verts.append(Vector3(px, mesh_surface_height(map_name, px, pz) + 0.06, pz))
				norms.append(Vector3.UP)
				uvs.append(Vector2(float(cx) / float(cells) * w / 10.0,
						float(cz) / float(cells) * d / 10.0))
				colors.append(tint)
		for cz in range(cells):
			for cx in range(cells):
				var a := cz * (cells + 1) + cx
				idx.append_array([a, a + 1, a + cells + 1,
						a + 1, a + cells + 2, a + cells + 1])
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance3D.new()
		mi.name = "CropField%d" % placed
		mi.mesh = mesh
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		fields.append(mi)
		placed += 1
		if placed >= 8:
			break
	if fields.size() > 1:
		_merge_visual_chunks(root, fields, mat)


## Foreground dressing around the handcrafted sites: bushes and rocks break the
## empty lawn around the factory/farm/village and frame the first frame.
static func _dress_handcrafted_sites(root: Node3D, map_name: String) -> void:
	var centers: Array = []
	match map_name:
		"industrial":
			centers = [Vector2(-200.0, -180.0), Vector2(50.0, 80.0)]
		"village":
			centers = [Vector2(60.0, -110.0), Vector2(192.0, 58.0)]
		"steppe":
			centers = [Vector2(40.0, 146.0)]
		"wetlands":
			centers = [Vector2(-60.0, -140.0)]
		_:
			return
	var bush_mesh := FOLIAGE.make_canopy_mesh(5, 2, 0.42, 0.55, 0.65)
	var bush_mat := FOLIAGE.make_wind_material(Color(0.12, 0.16, 0.06))
	var rock_mesh := FOLIAGE.make_canopy_mesh(5, 3, 0.30, 1.0, 1.2)
	var rock_mat := _mat(Color(0.44, 0.42, 0.38), 0.95)
	var rng := RandomNumberGenerator.new()
	for c in centers:
		var cc: Vector2 = c
		rng.seed = hash(map_name) + int(cc.x) * 31 + int(cc.y) * 17
		var bx: Array = []
		var rx: Array = []
		for _i in range(45):
			var a := rng.randf_range(0.0, TAU)
			var r := rng.randf_range(28.0, 85.0)
			var x: float = cc.x + cos(a) * r
			var z: float = cc.y + sin(a) * r
			if _hall_clear_zone(map_name, x, z) or _structure_clear_zone(map_name, x, z):
				continue
			var y := _height(map_name, x, z)
			var s := rng.randf_range(0.5, 1.3)
			bx.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU))
					.scaled(Vector3(s, s * 0.8, s)), Vector3(x, y + 0.1, z)))
		for _i in range(22):
			var a := rng.randf_range(0.0, TAU)
			var r := rng.randf_range(22.0, 70.0)
			var x: float = cc.x + cos(a) * r
			var z: float = cc.y + sin(a) * r
			if _hall_clear_zone(map_name, x, z) or _structure_clear_zone(map_name, x, z):
				continue
			var y := _height(map_name, x, z)
			var s := rng.randf_range(0.25, 0.7)
			rx.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU))
					.scaled(Vector3(s, s * 0.6, s)), Vector3(x, y + 0.05, z)))
		_multimesh(root, "SiteBushes_%d_%d" % [int(cc.x), int(cc.y)],
				bush_mesh, bush_mat, bx, true)
		_multimesh(root, "SiteRocks_%d_%d" % [int(cc.x), int(cc.y)],
				rock_mesh, rock_mat, rx, false)


## Rust/crack decal quads on the south facades of the main halls.  They are
## unshaded alpha quads (six draws per map) and break the flat concrete look.
## Mobile-only ground tint patches: large low-alpha quads laid flat over the
## terrain to break repeating grass tiling. Deterministic, height-field driven
## and cheap; transparent quads are not merged by the static batcher, so each
## tint costs a handful of draws.
static func _add_mobile_ground_patches(root: Node3D, map_name: String) -> void:
	var plans := {
		"steppe": [
			Vector2(-90.0, -120.0), Vector2(150.0, -170.0), Vector2(235.0, 60.0),
			Vector2(-220.0, -40.0), Vector2(40.0, 190.0), Vector2(-240.0, -200.0),
		],
		"village": [
			Vector2(-60.0, -140.0), Vector2(120.0, 200.0), Vector2(235.0, 120.0),
			Vector2(-240.0, 140.0), Vector2(80.0, -210.0), Vector2(-180.0, -60.0),
		],
		"industrial": [
			Vector2(-120.0, 195.0), Vector2(140.0, -180.0), Vector2(240.0, -60.0),
			Vector2(-245.0, -60.0), Vector2(-40.0, -215.0), Vector2(220.0, 190.0),
		],
		"wetlands": [
			Vector2(-120.0, 190.0), Vector2(160.0, 200.0), Vector2(240.0, -40.0),
			Vector2(-240.0, -120.0), Vector2(20.0, -210.0), Vector2(-200.0, -40.0),
		],
	}
	var tints := {
		"steppe": [Color(0.52, 0.46, 0.30, 0.14), Color(0.40, 0.42, 0.24, 0.12)],
		"village": [Color(0.44, 0.50, 0.26, 0.13), Color(0.52, 0.46, 0.30, 0.12)],
		"industrial": [Color(0.42, 0.40, 0.32, 0.14), Color(0.32, 0.36, 0.26, 0.12)],
		"wetlands": [Color(0.26, 0.38, 0.28, 0.14), Color(0.36, 0.34, 0.24, 0.12)],
	}
	var patch_tints: Array = tints.get(map_name, [Color(0.4, 0.4, 0.3, 0.12)])
	var placed := 0
	for i in range(plans.get(map_name, []).size()):
		var base: Vector2 = plans[map_name][i]
		if _hall_clear_zone(map_name, base.x, base.y) \
				or _structure_clear_zone(map_name, base.x, base.y):
			continue
		var gy := mesh_surface_height(map_name, base.x, base.y)
		if gy <= water_level(map_name) + 0.25:
			continue
		var quad := QuadMesh.new()
		quad.size = Vector2(randf_range(38.0, 74.0), randf_range(30.0, 56.0))
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = patch_tints[i % patch_tints.size()]
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var mi := MeshInstance3D.new()
		mi.name = "MobileGroundPatch%d" % placed
		mi.mesh = quad
		mi.material_override = mat
		mi.position = Vector3(base.x, gy + 0.06, base.y)
		mi.rotation.x = -PI * 0.5
		mi.rotation.z = randf_range(0.0, TAU)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		placed += 1
	print("[MobilePatches] ", map_name, " placed=", placed)


static func _add_wall_decals(root: Node3D, map_name: String) -> void:
	# Procedural smooth gradients, not the low-res decal bitmaps: the PNGs read
	# as blocky pixels once stretched over a wide facade.
	var rust := _rust_streak_tex()
	var crack := _crack_streak_tex()
	if rust == null:
		return
	var spots: Array = []
	match map_name:
		"industrial":
			spots = [Vector3(-222.0, 4.0, -166.4), Vector3(-205.0, 9.0, -166.4),
					Vector3(-188.0, 3.0, -166.4), Vector3(12.0, 4.0, 52.2),
					Vector3(45.0, 8.0, 52.2), Vector3(78.0, 3.0, 52.2)]
		"village":
			spots = [Vector3(150.0, 3.0, 31.2), Vector3(190.0, 7.0, 31.2),
					Vector3(225.0, 3.0, 31.2)]
		"steppe":
			spots = [Vector3(55.0, 3.0, 88.2), Vector3(95.0, 8.0, 88.2),
					Vector3(135.0, 3.0, 88.2)]
		"wetlands":
			spots = [Vector3(45.0, 3.0, 33.2), Vector3(85.0, 7.0, 33.2),
					Vector3(125.0, 3.0, 33.2)]
		_:
			return
	for i in range(spots.size()):
		var q := QuadMesh.new()
		q.size = Vector2(7.0, 4.5)
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = rust if i % 2 == 0 else crack
		mat.albedo_color = Color(0.85, 0.85, 0.85)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var mi := MeshInstance3D.new()
		mi.name = "Decal%d" % i
		mi.mesh = q
		mi.material_override = mat
		mi.position = spots[i]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)


# ===========================================================================
#  Materials
static func _ground_material(map_name: String) -> ShaderMaterial:
	# Photoreal four-layer PBR terrain.  The shader blends grass / dirt / rock /
	# mud by slope, height above water and the per-vertex macro mask, so every
	# map shares one draw call per chunk instead of a stack of overlay decals.
	#
	# The low-end presets use a cut-down variant: four texture fetches instead
	# of fourteen and no fBm.  Fragment cost, not geometry, is what limits the
	# integrated Intel GPUs, and the difference is invisible from FPV altitude.
	var mat := ShaderMaterial.new()
	var flat := false
	var use_lite := false
	var qa_shader := OS.get_environment("QA_TERRAIN_SHADER").to_lower()
	if qa_shader == "flat":
		flat = true
		use_lite = false
	elif qa_shader == "lite":
		flat = false
		use_lite = true
	elif qa_shader == "full":
		flat = false
		use_lite = false
	else:
		# Use full rich PBR terrain on Medium/High; use lite on Low preset
		var quality := QualityManager.get_active_level()
		use_lite = (quality == QualityManager.Level.LOW)
	if flat:
		mat.shader = load("res://shaders/terrain_flat.gdshader")
	else:
		mat.shader = load("res://shaders/terrain_pbr_lite.gdshader" if use_lite
				else "res://shaders/terrain_pbr.gdshader")
	# All variants share the public parameter names but some omit the normal
	# maps, so only set uniforms that actually exist.
	var uniforms := {}
	for entry in mat.shader.get_shader_uniform_list():
		uniforms[String(entry["name"])] = true
	if flat and uniforms.has("ground_albedo"):
		var flat_tex := load("res://Assets/textures/terrain/grass_albedo.png") as Texture2D
		if flat_tex != null:
			mat.set_shader_parameter("ground_albedo", flat_tex)
	for layer in ["grass", "dirt", "rock", "mud"]:
		for suffix in ["albedo", "normal"]:
			var path := "res://Assets/textures/terrain/%s_%s.png" % [layer, suffix]
			var tex := load(path) as Texture2D
			if tex != null:
				var param := "%s_%s" % [layer, suffix]
				if uniforms.has(param):
					mat.set_shader_parameter(param, tex)
			else:
				push_warning("[FrontlineTerrain] missing terrain texture: " + path)

	var cfg := {
		"steppe": {
			"grass_tint": Color(0.74, 0.80, 0.48),
			"dirt_tint": Color(0.88, 0.74, 0.56),
			"rock_tint": Color(0.92, 0.88, 0.80),
			"mud_tint": Color(0.72, 0.66, 0.52),
			"detail_scale": 0.26,
			"macro_scale": 0.014,
			"grass_bias": 0.12,
			"macro_contrast": 0.28,
			"normal_strength": 1.05,
		},
		"village": {
			"grass_tint": Color(0.72, 0.86, 0.46),
			"dirt_tint": Color(0.82, 0.70, 0.54),
			"rock_tint": Color(0.90, 0.87, 0.80),
			"mud_tint": Color(0.60, 0.56, 0.42),
			"detail_scale": 0.28,
			"macro_scale": 0.02,
			"grass_bias": 0.30,
			"macro_contrast": 0.30,
			"normal_strength": 1.1,
		},
		"industrial": {
			"grass_tint": Color(0.56, 0.72, 0.38),
			"dirt_tint": Color(0.76, 0.68, 0.52),
			"rock_tint": Color(0.92, 0.90, 0.84),
			"mud_tint": Color(0.70, 0.68, 0.58),
			"detail_scale": 0.30,
			"macro_scale": 0.016,
			"grass_bias": 0.35,
			"macro_contrast": 0.26,
			"normal_strength": 1.0,
		},
		"wetlands": {
			"grass_tint": Color(0.56, 0.76, 0.40),
			"dirt_tint": Color(0.70, 0.66, 0.50),
			"rock_tint": Color(0.82, 0.84, 0.76),
			"mud_tint": Color(0.56, 0.60, 0.42),
			"detail_scale": 0.26,
			"macro_scale": 0.018,
			"grass_bias": 0.20,
			"macro_contrast": 0.36,
			"normal_strength": 1.0,
		},
	}
	var conf: Dictionary = cfg.get(map_name, cfg["steppe"])
	if (OS.get_name() == "iOS" or OS.has_feature("mobile") \
			or OS.has_environment("MOBILE_UI")) \
			and not OS.has_environment("QA_NO_MOBILE_PALETTE"):
		conf = _mobile_ground_palette(map_name, conf)
	for key in conf:
		if uniforms.has(key):
			mat.set_shader_parameter(key, conf[key])

	var wl := water_level(map_name)
	mat.set_shader_parameter("wet_height", wl)
	mat.set_shader_parameter("mud_amount", 0.0)
	if map_name == "village":
		mat.set_shader_parameter("mud_amount", 0.26)
		mat.set_shader_parameter("wet_falloff", 2.2)
	elif map_name == "wetlands":
		mat.set_shader_parameter("mud_amount", 0.92)
		mat.set_shader_parameter("wet_falloff", 5.5)
	else:
		mat.set_shader_parameter("wet_falloff", 4.0)
	return mat


## Mobile-only colour grading of existing terrain textures. No new texture or
## shader samples are introduced; each map keeps its authored surface layers.
static func _mobile_ground_palette(map_name: String, source: Dictionary) -> Dictionary:
	var conf := source.duplicate(true)
	match map_name:
		"steppe":
			conf["grass_tint"] = Color(0.78, 0.76, 0.51)
			conf["macro_contrast"] = 0.34
		"village":
			conf["grass_tint"] = Color(0.67, 0.80, 0.45)
			conf["macro_contrast"] = 0.34
		"industrial":
			conf["grass_tint"] = Color(0.58, 0.65, 0.44)
			conf["dirt_tint"] = Color(0.70, 0.64, 0.56)
			conf["macro_contrast"] = 0.32
		"wetlands":
			conf["grass_tint"] = Color(0.49, 0.68, 0.44)
			conf["mud_tint"] = Color(0.49, 0.56, 0.45)
			conf["macro_contrast"] = 0.38
	return conf


## Mobile-only colour-coded navigation masts. Three per frontline map, placed
## on clear ground between the authored landmarks. Each mast is collidable, cheap
## (a handful of boxes plus one unshaded beacon light) and reserves its ground so
## later scatter passes keep it readable.
static func _build_mobile_beacons(root: Node3D, map_name: String) -> void:
	var specs := {
		"steppe": [
			Vector2(145.0, 225.0), Vector2(245.0, -70.0), Vector2(-235.0, 90.0),
		],
		"village": [
			Vector2(235.0, 205.0), Vector2(-235.0, -205.0), Vector2(40.0, -235.0),
		],
		"industrial": [
			Vector2(235.0, 195.0), Vector2(-235.0, -205.0), Vector2(235.0, -210.0),
		],
		"wetlands": [
			Vector2(235.0, 205.0), Vector2(-240.0, 40.0), Vector2(220.0, 225.0),
		],
	}
	var lights := [Color(0.95, 0.26, 0.18), Color(1.0, 0.62, 0.16),
			Color(0.24, 0.85, 0.46)]
	var placed := 0
	for i in range(specs.get(map_name, []).size()):
		var site: Vector2 = _resolve_mobile_beacon_site(map_name,
				specs[map_name][i])
		if site.x < -900.0:
			if OS.has_environment("DRONE_BEACON_DEBUG"):
				print("[MobileBeacons] ", map_name, " rejected ",
						specs[map_name][i])
			continue
		_add_mobile_beacon(root, map_name, site, lights[i % lights.size()])
		placed += 1
	print("[MobileBeacons] ", map_name, " placed=", placed)


static func _resolve_mobile_beacon_site(map_name: String, base: Vector2) -> Vector2:
	for ring in range(0, 10):
		var radius := 0.0 if ring == 0 else 20.0 * float(ring)
		var steps := 1 if ring == 0 else 16
		for i in range(steps):
			var a := TAU * float(i) / float(steps) + float(ring) * 0.31
			var p := base + Vector2(cos(a), sin(a)) * radius
			if _is_clear_beacon_site(map_name, p.x, p.y):
				return p
	return Vector2(-9999.0, -9999.0)


static func _is_clear_beacon_site(map_name: String, x: float, z: float) -> bool:
	if absf(x) > 265.0 or absf(z) > 265.0:
		return false
	if _hall_clear_zone(map_name, x, z) or _structure_clear_zone(map_name, x, z) \
			or _farm_clear_zone(map_name, x, z):
		return false
	var water := float(water_level(map_name))
	var ground := float(mesh_surface_height(map_name, x, z))
	if ground < water + 1.6:
		return false
	var e := 7.0
	var h0 := float(mesh_surface_height(map_name, x - e, z))
	var h1 := float(mesh_surface_height(map_name, x + e, z))
	var h2 := float(mesh_surface_height(map_name, x, z - e))
	var h3 := float(mesh_surface_height(map_name, x, z + e))
	if maxf(maxf(h0, h1), maxf(h2, h3)) - minf(minf(h0, h1), minf(h2, h3)) > 7.5:
		return false
	var roads: Array = _road_points(map_name)
	for line in roads:
		var pts: PackedVector2Array = line
		for i in range(pts.size() - 1):
			if Geometry2D.get_closest_point_to_segment(Vector2(x, z),
					pts[i], pts[i + 1]).distance_to(Vector2(x, z)) < 26.0:
				return false
	var mil_script = load("res://scripts/util/military_structures.gd")
	if mil_script != null and mil_script.spawned_positions.has(map_name):
		for mp in mil_script.spawned_positions[map_name]:
			if Vector2(x, z).distance_to(Vector2(mp)) < 45.0:
				return false
	return true


## One unique mobile hero landmark per map, built from the same box/cylinder
## kit as the authored POIs. They sit on clear ground, are collidable, and are
## registered in _poi_positions so later scatter passes keep their berth.
static func _build_mobile_hero_landmarks(root: Node3D, map_name: String) -> void:
	var specs := {
		"steppe": [
			["wind_turbine", Vector2(-175.0, 220.0)],
			["fuel_depot", Vector2(225.0, -215.0)],
			["silo_bank", Vector2(-240.0, -60.0)],
		],
		"village": [
			["grain_elevator", Vector2(-180.0, 205.0)],
			["church", Vector2(-240.0, 80.0)],
			["market_stalls", Vector2(240.0, -135.0)],
		],
		"industrial": [
			["flare_stack", Vector2(235.0, -120.0)],
			["pipe_rack", Vector2(-235.0, 195.0)],
			["water_cistern", Vector2(-240.0, 125.0)],
		],
		"wetlands": [
			["lighthouse", Vector2(240.0, 130.0)],
			["boathouse", Vector2(-220.0, 205.0)],
			["pier_house", Vector2(200.0, -220.0)],
		],
	}
	var list: Array = specs.get(map_name, [])
	for entry in list:
		var site := _resolve_mobile_beacon_site(map_name, entry[1])
		if site.x < -900.0:
			print("[MobileHero] ", map_name, " rejected ", entry[1])
			continue
		match String(entry[0]):
			"wind_turbine":
				_add_mobile_wind_turbine(root, map_name, site)
			"fuel_depot":
				_add_mobile_fuel_depot(root, map_name, site)
			"grain_elevator":
				_add_mobile_grain_elevator(root, map_name, site)
			"church":
				_add_mobile_church(root, map_name, site)
			"flare_stack":
				_add_mobile_flare_stack(root, map_name, site)
			"pipe_rack":
				_add_mobile_pipe_rack(root, map_name, site)
			"lighthouse":
				_add_mobile_lighthouse(root, map_name, site)
			"boathouse":
				_add_mobile_boathouse(root, map_name, site)
			"silo_bank":
				_add_mobile_silo_bank(root, map_name, site)
			"market_stalls":
				_add_mobile_market_stalls(root, map_name, site)
			"water_cistern":
				_add_mobile_water_cistern(root, map_name, site)
			"pier_house":
				_add_mobile_pier_house(root, map_name, site)
		_poi_positions.append(site)
		reserve_area(site, 30.0)
		print("[MobileHero] ", map_name, " ", entry[0], " at ", site)


static func _add_mobile_fuel_depot(root: Node3D, map_name: String, p: Vector2) -> void:
	var gy := _height(map_name, p.x, p.y)
	var node := Node3D.new()
	node.name = "MobileHero2_FuelDepot"
	node.position = Vector3(p.x, gy, p.y)
	root.add_child(node)
	var concrete := _pbr("hall_concrete", Color(0.54, 0.53, 0.50), 0.24)
	var tank := _pbr("hall_rust", Color(0.66, 0.50, 0.38), 0.28)
	var pipe := _pbr("steel", Color(0.60, 0.62, 0.60), 0.3)
	_add_box(node, Vector3(0.0, 0.16, 0.0), Vector3(12.0, 0.32, 9.0), concrete)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_add_cylinder(node, Vector3(sx * 4.0, 3.8, sz * 2.8), 1.7, 7.2, tank)
	_add_cylinder(node, Vector3(0.0, 1.6, 0.0), 0.35, 10.0, pipe, PI * 0.5, false)
	_add_box(node, Vector3(4.4, 2.0, 0.0), Vector3(0.9, 0.5, 6.0), pipe, 0.0, false)
	_keep_poi_detail(node, 1200.0)


static func _add_mobile_church(root: Node3D, map_name: String, p: Vector2) -> void:
	var gy := _height(map_name, p.x, p.y)
	var node := Node3D.new()
	node.name = "MobileHero2_Church"
	node.position = Vector3(p.x, gy, p.y)
	root.add_child(node)
	var white := _pbr("hall_concrete", Color(0.86, 0.86, 0.82), 0.2)
	var roof := _pbr("hall_rust", Color(0.62, 0.30, 0.22), 0.3)
	var stone := _pbr("hall_concrete", Color(0.70, 0.68, 0.62), 0.26)
	_add_box(node, Vector3(0.0, 4.0, 0.0), Vector3(8.0, 7.6, 5.6), white)
	_add_prism(node, Vector3(0.0, 8.2, 0.0), Vector3(9.4, 3.6, 7.0), roof)
	_add_box(node, Vector3(0.0, 10.4, -3.0), Vector3(3.0, 4.2, 2.6), white)
	_add_prism(node, Vector3(0.0, 13.0, -3.0), Vector3(4.4, 2.4, 4.0), roof)
	_add_box(node, Vector3(0.0, 12.2, -4.6), Vector3(0.16, 2.6, 0.16), stone, 0.0, false)
	_add_box(node, Vector3(0.0, 11.6, -4.6), Vector3(1.2, 0.16, 0.16), stone, 0.0, false)
	_keep_poi_detail(node, 1200.0)


static func _add_mobile_pipe_rack(root: Node3D, map_name: String, p: Vector2) -> void:
	var gy := _height(map_name, p.x, p.y)
	var node := Node3D.new()
	node.name = "MobileHero2_PipeRack"
	node.position = Vector3(p.x, gy, p.y)
	root.add_child(node)
	var steel := _pbr("hall_metal", Color(0.62, 0.64, 0.62), 0.24)
	var rust := _pbr("hall_rust", Color(0.60, 0.44, 0.32), 0.3)
	_add_box(node, Vector3(0.0, 0.12, 0.0), Vector3(20.0, 0.24, 6.0), steel)
	for i in range(5):
		for side in [-1.0, 1.0]:
			_add_box(node, Vector3(-8.0 + float(i) * 4.0, 4.2, side * 2.6),
					Vector3(0.34, 8.2, 0.34), steel)
	_add_cylinder(node, Vector3(0.0, 8.4, 0.0), 0.5, 20.6, rust, PI * 0.5)
	_add_cylinder(node, Vector3(0.0, 5.2, 0.0), 0.34, 20.6, rust, PI * 0.5)
	_keep_poi_detail(node, 1200.0)


static func _add_mobile_boathouse(root: Node3D, map_name: String, p: Vector2) -> void:
	var gy := _height(map_name, p.x, p.y)
	var node := Node3D.new()
	node.name = "MobileHero2_Boathouse"
	node.position = Vector3(p.x, gy, p.y)
	root.add_child(node)
	var wood := _pbr("wood", Color(0.62, 0.50, 0.36), 0.3)
	var roof := _pbr("hall_rust", Color(0.40, 0.44, 0.38), 0.32)
	for i in range(4):
		_add_box(node, Vector3(-3.3 + float(i) * 2.2, 0.9, 0.0),
				Vector3(0.4, 1.8, 5.2), wood)
	_add_box(node, Vector3(0.0, 2.0, 0.0), Vector3(8.0, 0.24, 5.4), wood)
	_add_prism(node, Vector3(0.0, 3.0, 0.0), Vector3(9.0, 2.2, 6.2), roof)
	_keep_poi_detail(node, 1200.0)


static func _add_mobile_silo_bank(root: Node3D, map_name: String, p: Vector2) -> void:
	var gy := _height(map_name, p.x, p.y)
	var node := Node3D.new()
	node.name = "MobileHero3_SiloBank"
	node.position = Vector3(p.x, gy, p.y)
	root.add_child(node)
	var concrete := _pbr("hall_concrete", Color(0.66, 0.64, 0.58), 0.22)
	var silo := _pbr("hall_metal", Color(0.72, 0.70, 0.62), 0.2)
	var rust := _pbr("hall_rust", Color(0.70, 0.52, 0.40), 0.26)
	_add_box(node, Vector3(0.0, 0.16, 0.0), Vector3(13.0, 0.32, 6.0), concrete)
	for i in range(4):
		_add_cylinder(node, Vector3(-4.5 + float(i) * 3.0, 6.2, 0.0), 1.5, 11.6, silo)
		_add_cylinder(node, Vector3(-4.5 + float(i) * 3.0, 12.1, 0.0), 1.56, 0.5, rust, 0.0, false)
	_add_cylinder(node, Vector3(0.0, 4.6, 0.0), 0.3, 10.0, rust, PI * 0.5, false)
	_keep_poi_detail(node, 1200.0)


static func _add_mobile_market_stalls(root: Node3D, map_name: String, p: Vector2) -> void:
	var gy := _height(map_name, p.x, p.y)
	var node := Node3D.new()
	node.name = "MobileHero3_MarketStalls"
	node.position = Vector3(p.x, gy, p.y)
	root.add_child(node)
	var wood := _pbr("wood", Color(0.58, 0.46, 0.32), 0.3)
	var awning := _pbr("hall_paint", Color(0.70, 0.26, 0.22), 0.3)
	var awning2 := _pbr("hall_paint", Color(0.24, 0.44, 0.62), 0.3)
	for row in range(2):
		for i in range(3):
			var bx := -5.0 + float(i) * 5.0
			var bz := -2.5 + float(row) * 5.0
			_add_box(node, Vector3(bx, 0.15, bz), Vector3(3.8, 0.3, 3.8), wood)
			for side in [-1.0, 1.0]:
				_add_box(node, Vector3(bx + side * 1.7, 1.15, bz), Vector3(0.15, 2.0, 3.8), wood)
			_add_prism(node, Vector3(bx, 1.8, bz), Vector3(4.2, 0.8, 4.2),
					awning if (i + row) % 2 == 0 else awning2)
	_keep_poi_detail(node, 1200.0)


static func _add_mobile_water_cistern(root: Node3D, map_name: String, p: Vector2) -> void:
	var gy := _height(map_name, p.x, p.y)
	var node := Node3D.new()
	node.name = "MobileHero3_WaterCistern"
	node.position = Vector3(p.x, gy, p.y)
	root.add_child(node)
	var concrete := _pbr("hall_concrete", Color(0.54, 0.53, 0.50), 0.24)
	var steel := _pbr("hall_metal", Color(0.62, 0.64, 0.64), 0.2)
	_add_box(node, Vector3(0.0, 0.2, 0.0), Vector3(8.0, 0.4, 8.0), concrete)
	var tank := _add_cylinder(node, Vector3(0.0, 7.0, 0.0), 3.0, 13.0, steel)
	_keep_poi_detail(tank)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_add_box(node, Vector3(sx * 2.6, 2.9, sz * 2.6), Vector3(0.3, 5.4, 0.3), steel)
	_add_cylinder(node, Vector3(0.0, 14.0, 0.0), 3.05, 0.5, steel, 0.0, false)
	_keep_poi_detail(node, 1200.0)


static func _add_mobile_pier_house(root: Node3D, map_name: String, p: Vector2) -> void:
	var gy := _height(map_name, p.x, p.y)
	var node := Node3D.new()
	node.name = "MobileHero3_PierHouse"
	node.position = Vector3(p.x, gy, p.y)
	root.add_child(node)
	var wood := _pbr("wood", Color(0.52, 0.42, 0.28), 0.3)
	var roof := _pbr("hall_rust", Color(0.34, 0.40, 0.34), 0.32)
	for i in range(6):
		_add_box(node, Vector3(-6.0 + float(i) * 2.4, 0.9, 0.0), Vector3(0.4, 1.8, 6.0), wood)
	_add_box(node, Vector3(0.0, 1.9, 0.0), Vector3(13.0, 0.3, 6.2), wood)
	_add_prism(node, Vector3(0.0, 3.2, 0.0), Vector3(14.0, 2.6, 7.0), roof)
	_add_box(node, Vector3(6.6, 0.6, 0.0), Vector3(1.6, 1.2, 3.0), wood)
	_keep_poi_detail(node, 1200.0)


static func _add_mobile_wind_turbine(root: Node3D, map_name: String, p: Vector2) -> void:
	var gy := _height(map_name, p.x, p.y)
	var node := Node3D.new()
	node.name = "MobileHero_WindTurbine"
	node.position = Vector3(p.x, gy, p.y)
	root.add_child(node)
	var concrete := _pbr("hall_concrete", Color(0.52, 0.52, 0.48), 0.22)
	var steel := _pbr("hall_metal", Color(0.72, 0.76, 0.78), 0.18)
	_add_box(node, Vector3(0.0, 0.35, 0.0), Vector3(6.0, 0.7, 6.0), concrete)
	_add_cylinder(node, Vector3(0.0, 14.5, 0.0), 0.9, 27.6, steel)
	var nacelle := _add_box(node, Vector3(0.0, 29.2, 0.6), Vector3(1.6, 1.7, 4.6), steel)
	_keep_poi_detail(nacelle)
	var blade_mat := _pbr("steel", Color(0.82, 0.85, 0.84), 0.24)
	for i in range(3):
		var yaw := TAU * float(i) / 3.0
		var blade := _add_box(node, Vector3(cos(yaw) * 7.4, 29.2, 0.6 + sin(yaw) * 7.4),
				Vector3(0.5, 0.34, 13.6), blade_mat, 0.0, false)
		blade.rotation.y = -yaw
		_keep_poi_detail(blade, 900.0)
	_keep_poi_detail(node, 1200.0)


static func _add_mobile_grain_elevator(root: Node3D, map_name: String, p: Vector2) -> void:
	var gy := _height(map_name, p.x, p.y)
	var node := Node3D.new()
	node.name = "MobileHero_GrainElevator"
	node.position = Vector3(p.x, gy, p.y)
	root.add_child(node)
	var concrete := _pbr("hall_concrete", Color(0.62, 0.60, 0.55), 0.24)
	var rust := _pbr("hall_rust", Color(0.72, 0.55, 0.42), 0.26)
	var silo := _pbr("hall_metal", Color(0.58, 0.62, 0.60), 0.2)
	for i in range(3):
		_add_cylinder(node, Vector3(-3.4 + float(i) * 3.4, 7.6, 0.0), 2.1, 14.2, silo)
		var cap := _add_cylinder(node, Vector3(-3.4 + float(i) * 3.4, 14.9, 0.0),
				2.15, 0.6, rust, 0.0, false)
		_keep_poi_detail(cap)
	_add_box(node, Vector3(0.0, 15.4, 0.0), Vector3(11.6, 3.6, 5.4), concrete)
	_add_box(node, Vector3(0.0, 15.4, 3.2), Vector3(1.0, 2.6, 1.0), rust, 0.0, false)
	_add_cylinder(node, Vector3(0.0, 9.2, 0.0), 0.5, 8.0, rust, 0.0, false)
	_keep_poi_detail(node, 1200.0)


static func _add_mobile_flare_stack(root: Node3D, map_name: String, p: Vector2) -> void:
	var gy := _height(map_name, p.x, p.y)
	var node := Node3D.new()
	node.name = "MobileHero_FlareStack"
	node.position = Vector3(p.x, gy, p.y)
	root.add_child(node)
	var concrete := _pbr("hall_concrete", Color(0.44, 0.44, 0.42), 0.24)
	var rust := _pbr("hall_rust", Color(0.62, 0.46, 0.34), 0.3)
	_add_box(node, Vector3(0.0, 0.4, 0.0), Vector3(5.6, 0.8, 5.6), concrete)
	var stack := _add_cylinder(node, Vector3(0.0, 17.5, 0.0), 0.75, 34.0, rust)
	_keep_poi_detail(stack)
	for i in range(4):
		var yaw := TAU * float(i) / 4.0
		_add_box(node, Vector3(cos(yaw) * 5.6, 8.5, sin(yaw) * 5.6),
				Vector3(0.2, 0.2, 8.0), rust, yaw, false)
	var flame_mat := StandardMaterial3D.new()
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.albedo_color = Color(1.0, 0.55, 0.16)
	flame_mat.emission_enabled = true
	flame_mat.emission = Color(1.0, 0.45, 0.10)
	flame_mat.emission_energy_multiplier = 2.6
	var flame := MeshInstance3D.new()
	flame.name = "FlareFlame"
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 0.9
	sphere_mesh.height = 1.8
	flame.mesh = sphere_mesh
	flame.material_override = flame_mat
	flame.position = Vector3(0.0, 35.2, 0.0)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flame.set_meta("no_batch", true)
	node.add_child(flame)
	_keep_poi_detail(node, 1200.0)


static func _add_mobile_lighthouse(root: Node3D, map_name: String, p: Vector2) -> void:
	var gy := _height(map_name, p.x, p.y)
	var node := Node3D.new()
	node.name = "MobileHero_Lighthouse"
	node.position = Vector3(p.x, gy, p.y)
	root.add_child(node)
	var concrete := _pbr("hall_concrete", Color(0.58, 0.58, 0.54), 0.24)
	var white := _pbr("hall_concrete", Color(0.82, 0.84, 0.82), 0.18)
	var band := _pbr("hall_rust", Color(0.68, 0.24, 0.18), 0.24)
	_add_box(node, Vector3(0.0, 0.3, 0.0), Vector3(8.0, 0.6, 8.0), concrete)
	var tower := _add_cylinder(node, Vector3(0.0, 10.6, 0.0), 2.3, 20.6, white)
	_keep_poi_detail(tower)
	for h in [3.4, 7.2, 11.0, 14.8]:
		_add_cylinder(node, Vector3(0.0, h, 0.0), 2.32, 0.5, band, 0.0, false)
	_add_box(node, Vector3(0.0, 21.6, 0.0), Vector3(5.6, 0.7, 5.6), band)
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lamp_mat.albedo_color = Color(0.20, 0.95, 0.55)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(0.16, 0.90, 0.50)
	lamp_mat.emission_energy_multiplier = 2.4
	var lamp := MeshInstance3D.new()
	lamp.name = "LighthouseLamp"
	var lamp_mesh := SphereMesh.new()
	lamp_mesh.radius = 0.7
	lamp_mesh.height = 1.4
	lamp.mesh = lamp_mesh
	lamp.material_override = lamp_mat
	lamp.position = Vector3(0.0, 22.4, 0.0)
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lamp.set_meta("no_batch", true)
	node.add_child(lamp)
	_keep_poi_detail(node, 1200.0)


static func _add_mobile_beacon(root: Node3D, map_name: String, p: Vector2,
		light_color: Color) -> void:
	var gy := _height(map_name, p.x, p.y)
	var node := Node3D.new()
	node.name = "MobileBeacon_%s_%d_%d" % [map_name, int(p.x), int(p.y)]
	root.add_child(node)
	var base_mat := _pbr("hall_concrete", Color(0.42, 0.42, 0.40), 0.35)
	_add_box(node, Vector3(0.0, 0.18, 0.0), Vector3(3.4, 0.36, 3.4), base_mat)
	var pole_mat := _pbr("hall_metal", Color(0.55, 0.57, 0.55), 0.32)
	_add_box(node, Vector3(0.0, 13.4, 0.0), Vector3(0.5, 26.0, 0.5), pole_mat)
	var plat_mat := _pbr("steel", Color(0.72, 0.30, 0.22), 0.40)
	_add_box(node, Vector3(0.0, 26.55, 0.0), Vector3(1.7, 0.3, 1.7), plat_mat)
	var light_mat := StandardMaterial3D.new()
	light_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	light_mat.albedo_color = light_color
	light_mat.emission_enabled = true
	light_mat.emission = light_color
	light_mat.emission_energy_multiplier = 2.0
	var sphere := MeshInstance3D.new()
	sphere.name = "BeaconLight"
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 0.55
	sphere_mesh.height = 1.1
	sphere.mesh = sphere_mesh
	sphere.material_override = light_mat
	sphere.position = Vector3(0.0, 27.35, 0.0)
	sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sphere.set_meta("no_batch", true)
	node.add_child(sphere)
	node.position = Vector3(p.x, gy, p.y)
	reserve_area(p, 26.0)


static func _mat(color: Color, rough: float = 0.9, metal: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	mat.metallic = metal
	return mat


static var _pbr_cache := {}
static var _village_kit: PackedScene = null
## Reuse the authored PBR texture sets that already ship with the landmark GLBs
## (plaster / brick / wood / concrete / steel).  Triplanar UVs keep the texture
## density consistent on boxes, roofs and MultiMesh-batched walls.
static func _pbr(kind: String, tint: Color = Color.WHITE, uv_scale: float = 0.22) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f|%.2f|%.3f" % [kind, tint.r, tint.g, tint.b, uv_scale]
	if _pbr_cache.has(key):
		return _pbr_cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.roughness = 0.9
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var base := ""
	match kind:
		"plaster":
			base = "res://Assets/frontline/village_textures/plaster"
		"brick":
			base = "res://Assets/frontline/village_textures/brick"
		"roof":
			base = "res://Assets/frontline/village_textures/roof"
		"wood":
			base = "res://Assets/frontline/village_textures/wood"
		"concrete":
			base = "res://Assets/frontline/admin_building_concrete"
		"steel":
			base = "res://Assets/frontline/factory_hall_steel"
		"asphalt":
			base = "res://Assets/frontline/admin_building_asphalt"
		"dirt":
			base = "res://Assets/textures/terrain/dirt"
		"sandbag":
			base = "res://Assets/frontline/sandbag_wall_sandbag"
		"hall_concrete":
			base = "res://Assets/frontline/industrial_hall/concrete_slab_wall"
		"hall_floor":
			base = "res://Assets/frontline/industrial_hall/concrete_floor_damaged_01"
		"hall_floor_seamless":
			# Mirror-tiled derivative of the Poly Haven floor set: removes the
			# visible 3.5 m tile seams in the long hero-hall nave.
			base = "res://Assets/frontline/industrial_hall/concrete_floor_seamless"
		"hall_moss":
			base = "res://Assets/frontline/industrial_hall/concrete_moss"
		"hall_rust":
			base = "res://Assets/frontline/industrial_hall/rusty_metal_02"
		"hall_metal":
			base = "res://Assets/frontline/industrial_hall/metal_plate_02"
		_:
			base = ""
	if base != "":
		var is_hall := base.find("industrial_hall") >= 0
		var albedo := load(base + ("_diff.jpg" if is_hall else "_albedo.png")) as Texture2D
		var normal := load(base + ("_nor_gl.jpg" if is_hall else "_normal.png")) as Texture2D
		var rough := load(base + "_rough.jpg" if is_hall else base + "_rough.png") as Texture2D
		var ao_path := base + ("_ao.jpg" if is_hall else "_ao.png")
		if albedo != null:
			mat.albedo_texture = albedo
			mat.uv1_triplanar = true
			mat.uv1_triplanar_sharpness = 8.0
			mat.uv1_scale = Vector3.ONE * uv_scale
		if normal != null:
			mat.normal_enabled = true
			mat.normal_texture = normal
			mat.normal_scale = 1.05
		if rough != null:
			mat.roughness_texture = rough
		if ResourceLoader.exists(ao_path):
			var ao := load(ao_path) as Texture2D
			if ao != null:
				mat.ao_enabled = true
				mat.ao_texture = ao
				mat.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	else:
		mat.roughness = 0.9
	_pbr_cache[key] = mat
	return mat


## Load and place the authored cottage/barn kit.  The GLB contains three
## joined meshes (`cottage_a`, `cottage_b`, `barn_a`); each mesh has material
## slots named plaster/brick/roof/wood/stone/glass, which are replaced with the
## village PBR materials here.
static func _load_village_kit() -> PackedScene:
	if _village_kit == null and ResourceLoader.exists("res://Assets/frontline/village_cottage.glb"):
		_village_kit = load("res://Assets/frontline/village_cottage.glb") as PackedScene
	return _village_kit


static func _clear_owners(node: Node) -> void:
	node.owner = null
	for child in node.get_children():
		_clear_owners(child)


static func _spawn_cottage(root: Node3D, variant: String, p: Vector2, y: float,
		yaw: float = 0.0, style: int = 0) -> Node3D:
	var kit := _load_village_kit()
	if kit == null:
		return null
	var library := kit.instantiate()
	var node := library.find_child(variant, true, false) as Node3D
	if node == null:
		library.queue_free()
		return null
	library.remove_child(node)
	# The kit nodes still carry the library as their scene owner; clear it so
	# adding them to the terrain does not print "inconsistent owner" warnings.
	_clear_owners(node)
	root.add_child(node)
	node.position = Vector3(p.x, y, p.y)
	node.rotation.y = yaw
	# The kit is authored at 1.0; a slight scale-down keeps the lane readable
	# from a 1 m FPV camera and prevents a two-storey brick wall from filling
	# the whole frame.
	node.scale = Vector3.ONE * (0.86 if variant.begins_with("cottage") else 0.90)
	_apply_cottage_materials(node, style)
	var body := StaticBody3D.new()
	body.name = "HouseCollision_" + variant
	body.collision_layer = 1
	body.collision_mask = 1
	node.add_child(body)
	var cottage_meshes: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		cottage_meshes.append(node as MeshInstance3D)
	for mesh_node in node.find_children("*", "MeshInstance3D", true, false):
		cottage_meshes.append(mesh_node as MeshInstance3D)
	var stone_mat := _pbr("stone", Color(0.42, 0.40, 0.38), 0.85)
	var bb_box := AABB(Vector3(-4.5, -4.0, -4.5), Vector3(9.0, 4.2, 9.0))
	for mi in cottage_meshes:
		if mi.mesh != null:
			var mb: AABB = mi.get_aabb()
			if mb.size.x > 3.0:
				bb_box = mb
				break
	var f_box := MeshInstance3D.new()
	var f_mesh := BoxMesh.new()
	f_mesh.size = Vector3(bb_box.size.x + 0.4, 7.0, bb_box.size.z + 0.4)
	f_box.mesh = f_mesh
	f_box.position = Vector3(bb_box.get_center().x, -3.4, bb_box.get_center().z)
	f_box.material_override = stone_mat
	node.add_child(f_box)

	var f_cs := CollisionShape3D.new()
	var f_shape := BoxShape3D.new()
	f_shape.size = f_mesh.size
	f_cs.shape = f_shape
	f_cs.position = f_box.position
	body.add_child(f_cs)
	for mi in cottage_meshes:
		if mi.mesh == null:
			continue
		var col_mi := mi
		if mi == node:
			for s in range(mi.mesh.get_surface_count()):
				var arrays := mi.mesh.surface_get_arrays(s)
				if arrays == null or arrays.size() == 0 or arrays[Mesh.ARRAY_VERTEX] == null:
					continue
				var sm := ArrayMesh.new()
				sm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				var shape := sm.create_trimesh_shape()
				if shape == null:
					continue
				shape.backface_collision = true
				var cs := CollisionShape3D.new()
				cs.shape = shape
				body.add_child(cs)
		else:
			_add_mesh_collision(body, col_mi)
		var bb: AABB = mi.get_aabb()
		if bb.size.y > 2.0:
			body.set_meta("roof_aabb", mi.global_transform * bb)
			var rcs := CollisionShape3D.new()
			var rshape := BoxShape3D.new()
			rshape.size = Vector3(maxf(bb.size.x - 0.4, 2.0), 0.7, maxf(bb.size.z - 0.4, 2.0))
			rcs.shape = rshape
			var c := bb.get_center()
			rcs.position = Vector3(c.x, bb.position.y + bb.size.y * 0.68, c.z)
			body.add_child(rcs)

	# Bold architectural framing around large fly-through window openings
	if variant.begins_with("cottage"):
		var frame_wood := _pbr("wood", Color(0.24, 0.17, 0.12), 0.45)
		for fz in [-3.15, 3.15]:
			for fx in [-2.35, 2.35]:
				# Top lintel
				var lintel := MeshInstance3D.new()
				var lm := BoxMesh.new()
				lm.size = Vector3(2.4, 0.22, 0.15)
				lintel.mesh = lm
				lintel.position = Vector3(fx, 3.25, fz)
				lintel.material_override = frame_wood
				node.add_child(lintel)
				# Bottom sill
				var sill := MeshInstance3D.new()
				var sm := BoxMesh.new()
				sm.size = Vector3(2.4, 0.18, 0.22)
				sill.mesh = sm
				sill.position = Vector3(fx, 1.45, fz)
				sill.material_override = frame_wood
				node.add_child(sill)
				# Side jambs
				for jx in [-1.15, 1.15]:
					var jamb := MeshInstance3D.new()
					var jm := BoxMesh.new()
					jm.size = Vector3(0.16, 1.7, 0.15)
					jamb.mesh = jm
					jamb.position = Vector3(fx + jx, 2.35, fz)
					jamb.material_override = frame_wood
					node.add_child(jamb)

	library.queue_free()
	return node


static var _cottage_mesh_cache := {}


## The authored cottage kit uses a glass surface for every pane.  Those panes
## are flush with solid walls on some sides and cover real openings on the long
## facades.  Remove the glass surface from the visual mesh BEFORE the trimesh
## collider is built: the long-facade windows then become genuinely flyable,
## and no transparent pane is left looking like a barrier.
static func _strip_glass_mesh(mesh: Mesh) -> Mesh:
	if mesh == null or mesh.get_surface_count() == 0:
		return mesh
	var cache_key := mesh.get_instance_id()
	if _cottage_mesh_cache.has(cache_key):
		return _cottage_mesh_cache[cache_key]
	var keep: Array[int] = []
	var removed := false
	for s in range(mesh.get_surface_count()):
		var mat := mesh.surface_get_material(s)
		var mat_name := ""
		if mat != null:
			mat_name = String(mat.resource_name).to_lower()
		if mat_name.contains("glass"):
			removed = true
		else:
			keep.append(s)
	if not removed or keep.is_empty():
		_cottage_mesh_cache[cache_key] = mesh
		return mesh
	var out := ArrayMesh.new()
	for s in keep:
		var arrays := mesh.surface_get_arrays(s)
		if arrays.is_empty():
			continue
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mat := mesh.surface_get_material(s)
		if mat != null:
			out.surface_set_material(out.get_surface_count() - 1, mat)
	_cottage_mesh_cache[cache_key] = out
	return out


static func _apply_cottage_materials(node: Node, style: int = 0) -> void:
	# Four plaster/roof combinations break the "clone army" look of a street
	# built from one kit; _pbr caches each tint, so this costs a handful of
	# material variants, not one per house.
	var plaster_tones := [
		Color(0.96, 0.92, 0.86),
		Color(0.88, 0.91, 0.93),
		Color(0.95, 0.89, 0.76),
		Color(0.90, 0.88, 0.84),
	]
	var brick_tones := [
		Color(0.94, 0.88, 0.82),
		Color(0.90, 0.83, 0.76),
		Color(0.86, 0.80, 0.72),
	]
	var roof_tones := [
		Color(0.96, 0.91, 0.86),
		Color(0.80, 0.79, 0.76),
		Color(0.88, 0.80, 0.70),
		Color(0.72, 0.74, 0.72),
	]
	var plaster_tint: Color = plaster_tones[style % plaster_tones.size()]
	var brick_tint: Color = brick_tones[style % brick_tones.size()]
	var roof_tint: Color = roof_tones[style % roof_tones.size()]
	var meshes: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		meshes.append(node as MeshInstance3D)
	for child in node.find_children("*", "MeshInstance3D", true, false):
		meshes.append(child as MeshInstance3D)
	for mi in meshes:
		if mi.mesh == null:
			continue
		var stripped := _strip_glass_mesh(mi.mesh)
		if stripped != mi.mesh:
			mi.mesh = stripped
		for s in range(mi.mesh.get_surface_count()):
			var source := mi.mesh.surface_get_material(s)
			var key := source.resource_name.to_lower() if source != null else ""
			var mat: Material
			match key:
				"plaster", "trim":
					mat = _pbr("plaster", plaster_tint, 0.34)
				"brick":
					mat = _pbr("brick", brick_tint, 0.36)
				"roof":
					mat = _pbr("roof", roof_tint, 0.32)
				"roof_metal", "metal":
					mat = _pbr("steel", Color(0.48, 0.50, 0.48), 0.18)
				"wood":
					mat = _pbr("wood", Color(0.86, 0.78, 0.66), 0.34)
				"stone":
					mat = _pbr("concrete", Color(0.84, 0.82, 0.76), 0.26)
				"glass":
					mat = _mat(Color(0.035, 0.055, 0.070), 0.10, 0.35)
				_:
					mat = _mat(Color(0.55, 0.48, 0.36), 0.9)
			mi.set_surface_override_material(s, mat)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


# ===========================================================================
#  Water
# ===========================================================================
## Low-detail continuation of the height field from the edge of the playable
## clipmap out to 3 km.  Without it the 1 km map reads as a square island
## floating in the sky when viewed from the air.
static func _build_horizon_ring(root: Node3D, map_name: String,
		_mat: ShaderMaterial) -> void:
	const EXTENT := 1843.2
	const STEP := 38.4
	const HOLE := 307.2
	var cells := int(EXTENT * 2.0 / STEP)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var base := -EXTENT
	var wl := water_level(map_name)
	var haze_col := Color(0.56, 0.63, 0.69)
	var grass := Color(0.24, 0.30, 0.14)
	var dry := Color(0.36, 0.34, 0.21)
	var rock := Color(0.32, 0.30, 0.25)
	match map_name:
		"steppe":
			grass = Color(0.29, 0.30, 0.14)
			dry = Color(0.42, 0.36, 0.20)
			rock = Color(0.36, 0.32, 0.24)
			haze_col = Color(0.62, 0.63, 0.58)
		"village":
			grass = Color(0.21, 0.30, 0.13)
			dry = Color(0.34, 0.32, 0.18)
			rock = Color(0.30, 0.28, 0.24)
			haze_col = Color(0.56, 0.63, 0.69)
		"industrial":
			grass = Color(0.20, 0.24, 0.15)
			dry = Color(0.30, 0.29, 0.25)
			rock = Color(0.28, 0.28, 0.26)
			haze_col = Color(0.52, 0.58, 0.63)
		"wetlands":
			grass = Color(0.15, 0.22, 0.11)
			dry = Color(0.22, 0.24, 0.15)
			rock = Color(0.10, 0.19, 0.20)
			haze_col = Color(0.54, 0.61, 0.60)
	for j in range(cells + 1):
		for i in range(cells + 1):
			var wx := base + float(i) * STEP
			var wz := base + float(j) * STEP
			var h := _height(map_name, wx, wz)
			if absf(wx) <= HOLE + 0.5 and absf(wz) <= HOLE + 0.5:
				h -= 0.06
			verts.append(Vector3(wx, h, wz))
			var dx := _height(map_name, wx + STEP, wz) - _height(map_name, wx - STEP, wz)
			var dz := _height(map_name, wx, wz + STEP) - _height(map_name, wx, wz - STEP)
			var n := Vector3(-dx, 2.0 * STEP, -dz).normalized()
			normals.append(n)
			uvs.append(Vector2(wx, wz) * 0.08)
			var slope := clampf((1.0 - n.y) * 2.6, 0.0, 1.0)
			var patch := _noise2(wx * 0.045 + 11.0, wz * 0.045 - 7.0) * 0.5 + 0.5
			var grain := _noise2(wx * 0.33, wz * 0.33) * 0.5 + 0.5
			var mix_t := clampf(patch * 0.58 + grain * 0.16, 0.0, 1.0)
			if map_name == "steppe" or map_name == "village":
				var field_wave := 0.5 + 0.5 * sin(wx * 0.011) * cos(wz * 0.011)
				mix_t = clampf(mix_t * 0.65 + field_wave * 0.35, 0.0, 1.0)
			var col := grass.lerp(dry, mix_t)
			if map_name == "wetlands" and h < wl + 0.35:
				col = col.lerp(rock, 0.70)
			else:
				col = col.lerp(rock, slope * 0.52)
			var dist := Vector2(wx, wz).length()
			var far_haze := smoothstep(900.0, EXTENT * 1.15, dist) * 0.52
			col = col.lerp(haze_col, far_haze)
			colors.append(col)
	for j in range(cells):
		for i in range(cells):
			var x0 := base + float(i) * STEP
			var z0 := base + float(j) * STEP
			if x0 >= -HOLE and x0 + STEP <= HOLE and z0 >= -HOLE and z0 + STEP <= HOLE:
				continue
			var a := j * (cells + 1) + i
			var b := a + 1
			var c := a + (cells + 1)
			var d := c + 1
			indices.append_array([a, b, c, b, d, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "HorizonRing"
	mi.mesh = mesh
	var flat := StandardMaterial3D.new()
	flat.albedo_color = Color.WHITE
	flat.vertex_color_use_as_albedo = true
	flat.vertex_color_is_srgb = true
	flat.roughness = 1.0
	flat.metallic = 0.0
	flat.disable_receive_shadows = true
	mi.material_override = flat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var body := StaticBody3D.new()
	body.name = "HorizonCollision"
	body.collision_layer = 1
	body.collision_mask = 1
	var shape: ConcavePolygonShape3D = mesh.create_trimesh_shape() as ConcavePolygonShape3D
	if shape != null:
		shape.backface_collision = true
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
	root.add_child(body)


static func _build_water(root: Node3D, map_name: String) -> void:
	var level := water_level(map_name)
	if level < -100.0:
		return
	# Animated water: two crossing ripple trains drive the normal, the fresnel
	# term drives both the colour and the opacity, and the vertex stage adds a
	# centimetre-scale swell so the shoreline silhouette is not razor straight.
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	# The Black Sea palette from the TAC-05 Crimean hydroelectric mission is
	# now the single water look on every map: deep navy in the middle, teal at
	# the banks, a bright sky reflection at grazing angles and a stronger
	# opacity so the riverbed never reads as flat green paint.
	mat.set_shader_parameter("deep_color", Color(0.012, 0.045, 0.080))
	mat.set_shader_parameter("shallow_color", Color(0.035, 0.135, 0.185))
	mat.set_shader_parameter("opacity", 0.95)
	mat.set_shader_parameter("ripple_scale", 0.025)
	mat.set_shader_parameter("ripple_strength", 0.50)
	mat.set_shader_parameter("ripple_speed", 0.85)
	mat.set_shader_parameter("wave_height", 0.05)
	mat.set_shader_parameter("sky_reflect", Color(0.30, 0.47, 0.72))
	mat.set_shader_parameter("sky_amount", 0.55)
	# Seamless noise normal: two scrolling samples in the shader replace the
	# regular sine ripples that looked like corrugated metal.
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.045
	noise.fractal_octaves = 4
	noise.fractal_gain = 0.55
	var normal_tex := NoiseTexture2D.new()
	normal_tex.width = 256
	normal_tex.height = 256
	normal_tex.seamless = true
	normal_tex.as_normal_map = true
	normal_tex.bump_strength = 7.0
	normal_tex.noise = noise
	mat.set_shader_parameter("ripple_normal", normal_tex)

	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)

	if map_name == "village":
		# A ribbon that follows the carved river channel.
		var steps := 128
		var verts := PackedVector3Array()
		var normals := PackedVector3Array()
		var uvs := PackedVector2Array()
		var indices := PackedInt32Array()
		for i in range(steps + 1):
			var z := -307.2 + float(i) * (614.4 / float(steps))
			var x := -170.0 + 35.0 * sin(z * 0.008)
			var dir := Vector2(35.0 * 0.008 * cos(z * 0.008), 1.0).normalized()
			var n := Vector2(-dir.y, dir.x)
			var left := Vector2(x, z) + n * 30.0
			var right := Vector2(x, z) - n * 30.0
			verts.append(Vector3(left.x, level, left.y))
			verts.append(Vector3(right.x, level, right.y))
			normals.append(Vector3.UP)
			normals.append(Vector3.UP)
			uvs.append(Vector2(0.0, float(i) * 0.5))
			uvs.append(Vector2(1.0, float(i) * 0.5))
			if i > 0:
				var a := (i - 1) * 2
				indices.append_array(PackedInt32Array([
					a, a + 1, a + 2, a + 1, a + 3, a + 2]))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, mat)
		mi.mesh = mesh
	else:
		var plane := PlaneMesh.new()
		plane.size = Vector2(640.0, 640.0)
		plane.subdivide_width = 16
		plane.subdivide_depth = 16
		plane.material = mat
		mi.mesh = plane
		mi.position = Vector3(0.0, level, 0.0)


# ===========================================================================
#  Roads / tracks / dikes
# ===========================================================================
static func _road_points(map_name: String) -> Array:
	match map_name:
		"village":
			return [
				PackedVector2Array([Vector2(-255, 235), Vector2(-180, 210), Vector2(-100, 195),
						Vector2(0, 170), Vector2(40, 80), Vector2(20, -40), Vector2(-40, -145),
						Vector2(-75, -255)]),
				PackedVector2Array([Vector2(-250, 60), Vector2(-150, 40), Vector2(-20, 60),
						Vector2(120, 40), Vector2(245, 65)]),
			]
		"industrial":
			return [
				PackedVector2Array([Vector2(-260, 200), Vector2(-185, 180), Vector2(-100, 165),
						Vector2(-30, 108), Vector2(-34, 24), Vector2(60, -120), Vector2(40, -245)]),
				PackedVector2Array([Vector2(-255, -40), Vector2(-170, -30), Vector2(-20, -45),
						Vector2(150, -30), Vector2(255, -48)]),
			]
		"wetlands":
			return [
				PackedVector2Array([Vector2(-255, 210), Vector2(-215, 165), Vector2(-190, 105),
						Vector2(-155, 20), Vector2(-60, -20), Vector2(80, -10),
						Vector2(185, 30), Vector2(255, 85)]),
				PackedVector2Array([Vector2(-230, -230), Vector2(-195, -120), Vector2(-175, 20),
						Vector2(-120, 140), Vector2(-40, 230)]),
			]
		_:
			return [
				PackedVector2Array([Vector2(-255, 225), Vector2(-205, 195), Vector2(-135, 170),
						Vector2(-55, 135), Vector2(30, 60), Vector2(80, -40), Vector2(90, -160),
						Vector2(65, -255)]),
			]


static func _build_roads(root: Node3D, map_name: String) -> void:
	# Larger texture scale: the old 0.28 UV repeat made the dirt tracks read as
	# a conveyor-belt pattern from the air on the owner's recording.
	var mat := _pbr("dirt", Color(0.70, 0.60, 0.43), 0.12)
	if map_name == "industrial":
		mat = _pbr("asphalt", Color(0.58, 0.58, 0.57), 0.10)
	var width := 7.0
	if map_name == "wetlands":
		width = 5.0
	# All road segments on a map share one material, so they go into a single
	# ArrayMesh.  Building one MeshInstance per ribbon cost 2-4 draws per map
	# and pushed Village over the 250-draw budget; the merged road is one draw.
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for pts in _road_points(map_name):
		# Resample the coarse control points before clipping.  The old two-point
		# road segments could pass straight through the hero hall because only
		# the endpoints were tested against the clear zone.  A 2 m step gives
		# the clip pass enough vertices to split exactly on the hall footprint.
		var dense := _resample_polyline(pts, 2.0)
		var current := PackedVector2Array()
		for p in dense:
			if _hall_clear_zone(map_name, p.x, p.y):
				if current.size() >= 2:
					_ribbon_append(current, width, 0.045, verts, normals, uvs, indices)
				current = PackedVector2Array()
			else:
				current.append(p)
		if current.size() >= 2:
			_ribbon_append(current, width, 0.045, verts, normals, uvs, indices)
	if verts.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = "Roads_" + map_name
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## Densify a coarse control polyline so height sampling, clipping and slope
## following happen at ~2 m intervals instead of once per authored waypoint.
static func _resample_polyline(pts: PackedVector2Array, step: float) -> PackedVector2Array:
	if pts.size() < 2:
		return pts
	var out := PackedVector2Array()
	var stride := maxf(step, 0.5)
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var seg := b - a
		var length := seg.length()
		if length < 0.001:
			continue
		var count := maxi(1, int(ceil(length / stride)))
		for k in range(count):
			if i > 0 and k == 0:
				continue  # avoid duplicating the shared waypoint
			out.append(a + seg * (float(k) / float(count)))
	if out.is_empty():
		out.append(pts[0])
	out.append(pts[pts.size() - 1])
	return out


## Normal of the rendered terrain surface.  Road ribbons previously used a
## hard-coded Vector3.UP normal, so a road on a slope was lit like a billiard
## table and read as a floating strip.
static func _surface_normal(map_name: String, x: float, z: float) -> Vector3:
	const E := 0.75
	var dx := mesh_surface_height(map_name, x + E, z) \
			- mesh_surface_height(map_name, x - E, z)
	var dz := mesh_surface_height(map_name, x, z + E) \
			- mesh_surface_height(map_name, x, z - E)
	return Vector3(-dx / (2.0 * E), 1.0, -dz / (2.0 * E)).normalized()


static func _ribbon_append(pts: PackedVector2Array, width: float, lift: float,
		verts: PackedVector3Array, normals: PackedVector3Array,
		uvs: PackedVector2Array, indices: PackedInt32Array) -> void:
	if pts.size() < 2:
		return
	var base := verts.size()
	var travelled := 0.0
	for i in range(pts.size()):
		var p := pts[i]
		var dir: Vector2
		if i == 0:
			dir = pts[1] - pts[0]
		elif i == pts.size() - 1:
			dir = pts[i] - pts[i - 1]
		else:
			dir = pts[i + 1] - pts[i - 1]
		dir = dir.normalized()
		var n := Vector2(-dir.y, dir.x)
		var left := p + n * width * 0.5
		var right := p - n * width * 0.5
		# Sample the *rendered* clipmap height at both ribbon edges.  The
		# analytic field and the actual triangle mesh differ by up to several
		# metres on the coarse outer ring; sampling only the centreline was the
		# cause of the brown ribbons hanging above the ground.
		var yl := mesh_surface_height(_current_map, left.x, left.y) + lift
		var yr := mesh_surface_height(_current_map, right.x, right.y) + lift
		verts.append(Vector3(left.x, yl, left.y))
		verts.append(Vector3(right.x, yr, right.y))
		var normal := _surface_normal(_current_map, p.x, p.y)
		normals.append(normal)
		normals.append(normal)
		uvs.append(Vector2(0.0, travelled * 0.25))
		uvs.append(Vector2(1.0, travelled * 0.25))
		if i > 0:
			var a := base + (i - 1) * 2
			indices.append_array(PackedInt32Array([
				a, a + 1, a + 2, a + 1, a + 3, a + 2]))
		if i < pts.size() - 1:
			travelled += p.distance_to(pts[i + 1])


static func _ribbon(root: Node3D, pts: PackedVector2Array, width: float,
		mat: Material, lift: float) -> void:
	if pts.size() < 2:
		return
	pts = _resample_polyline(pts, 2.0)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var travelled := 0.0
	for i in range(pts.size()):
		var p := pts[i]
		var dir: Vector2
		if i == 0:
			dir = pts[1] - pts[0]
		elif i == pts.size() - 1:
			dir = pts[i] - pts[i - 1]
		else:
			dir = pts[i + 1] - pts[i - 1]
		dir = dir.normalized()
		var n := Vector2(-dir.y, dir.x)
		var left := p + n * width * 0.5
		var right := p - n * width * 0.5
		var yl := mesh_surface_height(_current_map, left.x, left.y) + lift
		var yr := mesh_surface_height(_current_map, right.x, right.y) + lift
		verts.append(Vector3(left.x, yl, left.y))
		verts.append(Vector3(right.x, yr, right.y))
		var normal := _surface_normal(_current_map, p.x, p.y)
		normals.append(normal)
		normals.append(normal)
		uvs.append(Vector2(0.0, travelled * 0.25))
		uvs.append(Vector2(1.0, travelled * 0.25))
		if i > 0:
			var a := (i - 1) * 2
			indices.append_array(PackedInt32Array([
				a, a + 1, a + 2, a + 1, a + 3, a + 2]))
		if i < pts.size() - 1:
			travelled += p.distance_to(pts[i + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## Set by build_terrain so the ribbon helper can sample the right height field.
static var _current_map := "steppe"


# ===========================================================================
#  Trenches: sandbags + duckboards
# ===========================================================================
static func _build_trenches(root: Node3D, map_name: String) -> void:
	var sandbag_mesh := BoxMesh.new()
	sandbag_mesh.size = Vector3(1.05, 0.34, 0.52)
	var sandbag_mat := _pbr("sandbag", Color(0.94, 0.86, 0.66), 0.45)
	var transforms: Array = []
	var duck_transforms: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(map_name) + 91

	for line in _trenches(map_name):
		var pl: PackedVector2Array = line
		for i in range(pl.size() - 1):
			var a := pl[i]
			var b := pl[i + 1]
			var seg := b - a
			var length := seg.length()
			if length < 0.01:
				continue
			var dir := seg / length
			var n := Vector2(-dir.y, dir.x)
			var t := 0.0
			while t < length:
				var p := a + dir * t
				for side in [-1.0, 1.0]:
					for layer in range(2):
						var off: Vector2 = n * 2.65 * side + dir * rng.randf_range(-0.12, 0.12)
						var pos := p + off
						# Follow the rendered clipmap, not the analytic field:
						# on the outer 8 m ring the two differ by over a metre and
						# the sandbag rows visibly hovered over the grass.
						var support := mesh_surface_height(map_name, pos.x, pos.y)
						var y := support + 0.22 + float(layer) * 0.33
						var basis := Basis(Vector3.UP, atan2(dir.x, dir.y) + rng.randf_range(-0.09, 0.09))
						transforms.append(Transform3D(basis, Vector3(pos.x, y, pos.y)))
				if fmod(t, 3.0) < 1.2:
					var cy := mesh_surface_height(map_name, p.x, p.y) + 0.06
					var cb := Basis(Vector3.UP, atan2(dir.x, dir.y))
					duck_transforms.append(Transform3D(cb, Vector3(p.x, cy, p.y)))
				t += 1.55

	_multimesh(root, "Sandbags", sandbag_mesh, sandbag_mat, transforms, false)
	var duck_mesh := BoxMesh.new()
	duck_mesh.size = Vector3(2.4, 0.08, 1.5)
	_multimesh(root, "Duckboards", duck_mesh, _mat(Color(0.30, 0.24, 0.15), 1.0),
			duck_transforms, false)


# ===========================================================================
#  Craters: dark scorch discs
# ===========================================================================
static func _build_crater_marks(root: Node3D, map_name: String) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 0.06
	mesh.radial_segments = 10
	var mat := _mat(Color(0.17, 0.13, 0.09), 1.0)
	var transforms: Array = []
	for c in _craters(map_name):
		var pos: Vector2 = c["pos"]
		var r: float = c["r"]
		var y := _height(map_name, pos.x, pos.y) + 0.02
		var basis := Basis(Vector3.UP, float(hash(pos)) * 0.0001).scaled(
				Vector3(r * 0.92, 1.0, r * 0.92))
		transforms.append(Transform3D(basis, Vector3(pos.x, y, pos.y)))
	_multimesh(root, "CraterScorch", mesh, mat, transforms, false)


# ===========================================================================
#  Physical power lines
# ===========================================================================
static func _power_lines(map_name: String) -> Array:
	match map_name:
		"village":
			return [
				[Vector2(-245, 150), Vector2(-160, 140), Vector2(-60, 150),
						Vector2(50, 130), Vector2(150, 145), Vector2(245, 130)],
				[Vector2(-120, -230), Vector2(-110, -120), Vector2(-100, 10),
						Vector2(-90, 140)],
			]
		"industrial":
			return [
				[Vector2(-250, 60), Vector2(-170, 40), Vector2(-80, 55),
						Vector2(40, 35), Vector2(145, 50), Vector2(245, 30)],
				[Vector2(235, -230), Vector2(228, -120), Vector2(220, 20), Vector2(210, 150)],
			]
		"steppe":
			return [
				[Vector2(-245, 210), Vector2(-150, 200), Vector2(-40, 215),
						Vector2(70, 195), Vector2(170, 210), Vector2(248, 195)],
			]
	return []


static func _build_power_lines(root: Node3D, map_name: String) -> void:
	var lines := _power_lines(map_name)
	if lines.is_empty():
		return
	var wire_mat := StandardMaterial3D.new()
	wire_mat.albedo_color = Color(0.09, 0.09, 0.09)
	wire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wire_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	for line in lines:
		var pts: Array = line
		var tops: Array = []
		# One static body per line carries all catenary segments, so the wires
		# are physical without creating one body per 1 m cable segment.
		var wire_body := StaticBody3D.new()
		wire_body.name = "PowerLineWires"
		wire_body.collision_layer = 1
		wire_body.collision_mask = 1
		root.add_child(wire_body)
		for i in range(pts.size()):
			var p: Vector2 = pts[i]
			var y := _height(map_name, p.x, p.y)
			var dir2: Vector2
			if i == 0:
				dir2 = pts[1] - pts[0]
			elif i == pts.size() - 1:
				dir2 = pts[i] - pts[i - 1]
			else:
				dir2 = pts[i + 1] - pts[i - 1]
			dir2 = dir2.normalized()
			# Local Z of the pylon follows the line, local X matches the
			# crossarm; this keeps all three conductors over the insulators.
			var yaw := atan2(dir2.x, dir2.y)
			ASSETS.spawn(root, "pylon", Vector3(p.x, y, p.y), yaw)
			tops.append(Vector3(p.x, y + 20.2, p.y))

		var immediate := ImmediateMesh.new()
		immediate.surface_begin(Mesh.PRIMITIVE_LINES, wire_mat)
		for i in range(tops.size() - 1):
			var a: Vector3 = tops[i]
			var b: Vector3 = tops[i + 1]
			var flat := Vector3(b.x - a.x, 0.0, b.z - a.z)
			if flat.length_squared() < 0.001:
				continue
			flat = flat.normalized()
			var normal := Vector3(-flat.z, 0.0, flat.x)
			for offset in [-4.0, 0.0, 4.0]:
				var shifted := normal * float(offset)
				var prev := a + shifted
				var points: Array[Vector3] = [prev]
				for s in range(1, 7):
					var f := float(s) / 6.0
					var p := a.lerp(b, f) + shifted
					p.y -= sin(f * PI) * 1.6
					immediate.surface_add_vertex(prev)
					immediate.surface_add_vertex(p)
					prev = p
					points.append(p)
				for k in range(points.size() - 1):
					var a3: Vector3 = points[k]
					var b3: Vector3 = points[k + 1]
					var delta := b3 - a3
					var seg_len := delta.length()
					if seg_len < 0.001:
						continue
					var dir := delta / seg_len
					var seg := CylinderShape3D.new()
					seg.radius = 0.11
					seg.height = seg_len
					var basis := Basis.IDENTITY
					if dir.dot(Vector3.UP) < -0.9999:
						basis = Basis(Vector3.RIGHT, PI)
					elif dir.dot(Vector3.UP) < 0.9999:
						basis = Basis(Quaternion(Vector3.UP, dir))
					var cs := CollisionShape3D.new()
					cs.shape = seg
					cs.transform = Transform3D(basis, (a3 + b3) * 0.5)
					wire_body.add_child(cs)
		immediate.surface_end()
		var mi := MeshInstance3D.new()
		mi.mesh = immediate
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)


# ===========================================================================
#  Landmarks per map
# ===========================================================================
static func _build_landmarks(root: Node3D, map_name: String) -> void:
	match map_name:
		"village":
			_build_village(root, map_name)
		"industrial":
			# The handcrafted factory GLB replaces the procedural hall grid.
			pass
		"wetlands":
			_build_wetlands(root, map_name)
		_:
			_build_steppe(root, map_name)


# ===========================================================================
#  Authored Blender landmark pass
# ===========================================================================
## Adds the detailed GLB landmarks on top of the procedural terrain.  Positions
## are chosen to reinforce existing roads, river crossings, trench lines and
## industrial yards rather than replacing the map layout.
static func _build_blender_landmarks(root: Node3D, map_name: String) -> void:
	match map_name:
		"village":
			# Rural map: modern office/hospital towers removed; the handcrafted
			# cottage/mill cluster and the village hall carry the skyline.
			# Bridge deck must meet both banks; the river meanders along X here.
			var river_x := -170.0 + 35.0 * sin(40.0 * 0.008)
			var bridge_y := _bank_height(map_name, river_x, 40.0, 23.0) - 3.85 + 0.15
			var concrete_bridge := ASSETS.spawn(root, "concrete_bridge",
					Vector3(river_x, bridge_y, 40.0), 0.0)
			_wrap_landmark(root, concrete_bridge, 1900.0, 550)
			var river_x2 := -170.0 + 35.0 * sin(150.0 * 0.008)
			var bridge_y2 := _bank_height(map_name, river_x2, 150.0, 12.5) - 3.08 + 0.12
			var wooden_bridge := ASSETS.spawn(root, "wooden_bridge",
					Vector3(river_x2, bridge_y2, 150.0), 0.0)
			_wrap_landmark(root, wooden_bridge, 1200.0, 400)
			_destructible_on(root, map_name, "checkpoint", Vector2(28, 195), -0.2, 900.0, 300)
			_destructible_on(root, map_name, "observation_post", Vector2(-252, -58), 0.5, 800.0, 250)
			_destructible_on(root, map_name, "bunker", Vector2(-108, 22), 0.1, 1200.0, 400)
			_destructible_on(root, map_name, "bunker", Vector2(162, 20), -0.3, 1200.0, 400)
			for p in [Vector2(-10, 165), Vector2(35, 160), Vector2(72, 150),
					Vector2(-150, 70), Vector2(-170, 20)]:
				_asset_on(root, map_name, "hedgehog", p, float(p.x) * 0.01)
			_asset_on(root, map_name, "sandbag_wall", Vector2(-210, 102), 0.08)
			_asset_on(root, map_name, "sandbag_wall", Vector2(32, 202), -0.2)
			_asset_on(root, map_name, "vegetation/oak_hero", Vector2(48, -48), 0.7)
			_asset_on(root, map_name, "vegetation/oak_hero", Vector2(-178, 74), 1.4)
			_asset_on(root, map_name, "vegetation/pine_hero", Vector2(240, 212), 0.3)
			_asset_on(root, map_name, "vegetation/pine_hero", Vector2(-245, -172), 1.1)

			var MS = load("res://scripts/util/military_structures.gd")
			if MS != null:
				MS.spawn_map_military_objects(root, map_name)

		"industrial":
			# Road checkpoint & grand entry arch placed cleanly along the western approach road (-100, 170)
			# away from the hero hall facade so flight paths and roof approaches remain unobstructed.
			_destructible_on(root, map_name, "arch", Vector2(-100, 170), 0.55, 900.0, 300)
			_destructible_on(root, map_name, "checkpoint", Vector2(-135, 185), 0.35, 900.0, 300)
			_destructible_on(root, map_name, "bunker", Vector2(-240, -155), 0.35, 1200.0, 400)
			_destructible_on(root, map_name, "observation_post", Vector2(-242, 132), 0.8, 800.0, 250)
			for p in [Vector2(130, 92), Vector2(205, 92), Vector2(168, 54),
					Vector2(-155, 195), Vector2(-80, 155)]:
				_asset_on(root, map_name, "hedgehog", p, float(p.y) * 0.01)
			_asset_on(root, map_name, "sandbag_wall", Vector2(-128, 178), 0.35)
			_asset_on(root, map_name, "sandbag_wall", Vector2(-240, -145), 0.35)
			_asset_on(root, map_name, "rocks", Vector2(-225, -138), 0.4)
			_asset_on(root, map_name, "rocks", Vector2(235, 158), 1.2)
			_asset_on(root, map_name, "vegetation/pine_hero", Vector2(-248, 190), 0.4)
			_asset_on(root, map_name, "vegetation/pine_hero", Vector2(245, 195), 2.2)
			_asset_on(root, map_name, "vegetation/oak_hero", Vector2(22, 200), 1.0)

			var MC_ind = load("res://scripts/util/moving_crane.gd")
			if MC_ind != null:
				# Dynamic traveling gantry crane over the container yard
				var cy1 := _height(map_name, 65.0, 10.0)
				var gantry_crane: Node3D = MC_ind.create_gantry_crane(Vector3(65.0, cy1, 10.0), 0.0, 68.0)
				root.add_child(gantry_crane)
				# Dynamic rotating high-mast construction tower crane
				var cy2 := _height(map_name, -140.0, 20.0)
				var tower_crane: Node3D = MC_ind.create_rotating_tower_crane(Vector3(-140.0, cy2, 20.0), 0.25)
				root.add_child(tower_crane)

			var MS_ind = load("res://scripts/util/military_structures.gd")
			if MS_ind != null:
				MS_ind.spawn_map_military_objects(root, map_name)

		"wetlands":
			ASSETS.spawn(root, "destroyed_bridge", Vector3(0.0, water_level(map_name), -90.0), 0.0)
			ASSETS.spawn(root, "wooden_bridge", Vector3(120.0, water_level(map_name) - 0.15, -90.0), PI * 0.5)
			# Second crossing off the hall's west approach so the first frame has
			# water, reeds and a broken span instead of an empty bank.
			ASSETS.spawn(root, "destroyed_bridge", Vector3(16.0, water_level(map_name), 22.0), 0.0)
			_destructible_on(root, map_name, "bunker", Vector2(10, 54), 0.18, 1200.0, 400)
			_destructible_on(root, map_name, "bunker", Vector2(190, 80), -0.4, 1200.0, 400)
			_destructible_on(root, map_name, "bunker", Vector2(-190, -40), 1.1, 1200.0, 400)
			_asset_on(root, map_name, "sandbag_wall", Vector2(20, 58), 0.12)
			_asset_on(root, map_name, "hedgehog", Vector2(2, 62), 0.3)
			_asset_on(root, map_name, "hedgehog", Vector2(24, 68), 0.6)
			for p in [Vector2(-230, 20), Vector2(250, 15), Vector2(-60, 150)]:
				_destructible_on(root, map_name, "bunker", p, float(p.x) * 0.008, 1200.0, 400)
			_destructible_on(root, map_name, "checkpoint", Vector2(202, 132), 0.4, 900.0, 300)
			_destructible_on(root, map_name, "observation_post", Vector2(-162, 192), 0.6, 800.0, 250)
			for p in [Vector2(-40, 92), Vector2(0, 82), Vector2(42, 96),
					Vector2(92, 102), Vector2(142, 82), Vector2(-150, 62)]:
				_asset_on(root, map_name, "hedgehog", p, float(p.x) * 0.012)
			_asset_on(root, map_name, "sandbag_wall", Vector2(-230, 32), 0.2)
			_asset_on(root, map_name, "sandbag_wall", Vector2(250, 27), -0.3)
			_asset_on(root, map_name, "sandbag_wall", Vector2(202, 140), 0.4)
			_asset_on(root, map_name, "vegetation/pine_hero", Vector2(235, 205), 0.8)
			_asset_on(root, map_name, "vegetation/pine_hero", Vector2(-245, 210), 1.8)
			_asset_on(root, map_name, "vegetation/oak_hero", Vector2(158, 222), 2.6)

			var MS_wet = load("res://scripts/util/military_structures.gd")
			if MS_wet != null:
				MS_wet.spawn_map_military_objects(root, map_name)

		_:
			# Bunkers along the trench line, placed with wide spacing (>100m) clear of silos, radar and workshops
			for p in [Vector2(-110, -120), Vector2(40, -90), Vector2(150, -120)]:
				_destructible_on(root, map_name, "bunker", p, float(p.x) * 0.002, 1200.0, 400)
			_destructible_on(root, map_name, "observation_post", Vector2(-42, -172), 0.4, 800.0, 250)
			_destructible_on(root, map_name, "checkpoint", Vector2(-124, 96), 0.3, 900.0, 300)
			for p in [Vector2(-245, -10), Vector2(-210, -14), Vector2(-175, -8),
					Vector2(82, -12), Vector2(122, -9), Vector2(162, -13),
					Vector2(202, -8), Vector2(235, -12)]:
				_asset_on(root, map_name, "hedgehog", p, float(p.x) * 0.01)
			_asset_on(root, map_name, "sandbag_wall", Vector2(-215, -70), 0.2)
			_asset_on(root, map_name, "sandbag_wall", Vector2(44, -80), -0.1)
			_asset_on(root, map_name, "sandbag_wall", Vector2(240, -60), 0.45)
			_asset_on(root, map_name, "rocks", Vector2(-248, 138), 0.7)
			_asset_on(root, map_name, "rocks", Vector2(248, 162), 1.9)
			_asset_on(root, map_name, "vegetation/oak_hero", Vector2(-240, 112), 0.6)
			_asset_on(root, map_name, "vegetation/oak_hero", Vector2(-88, 162), 1.8)
			_asset_on(root, map_name, "vegetation/pine_hero", Vector2(242, 164), 0.3)
			_asset_on(root, map_name, "vegetation/pine_hero", Vector2(-248, -150), 1.2)
			_asset_on(root, map_name, "vegetation/pine_hero", Vector2(22, -215), 2.4)

			var MS_stp = load("res://scripts/util/military_structures.gd")
			if MS_stp != null:
				MS_stp.spawn_map_military_objects(root, map_name)


## Low-lying fog volumes: the atmospheric layer that makes the low sun read
## through the scene (morning mist over the river and marsh, dust over the
## steppe, cool air in the village lane).
static func _add_map_mist(root: Node3D, map_name: String) -> void:
	var specs: Array = []
	match map_name:
		"village":
			var rx := -170.0 + 35.0 * sin(60.0 * 0.008)
			specs = [
				[Vector2(rx, 60.0), Vector3(70.0, 8.0, 220.0), 0.018],
			]
		"wetlands":
			specs = [
				[Vector2(40.0, -60.0), Vector3(240.0, 6.0, 120.0), 0.020],
				[Vector2(-120.0, 90.0), Vector3(150.0, 5.0, 100.0), 0.014],
			]
		"steppe":
			specs = [
				[Vector2(40.0, 40.0), Vector3(260.0, 7.0, 140.0), 0.012],
				[Vector2(50.0, 150.0), Vector3(130.0, 6.0, 70.0), 0.008],
			]
	for spec in specs:
		var p: Vector2 = spec[0]
		var size: Vector3 = spec[1]
		var gy := _height(map_name, p.x, p.y)
		var fog := FogVolume.new()
		fog.position = Vector3(p.x, gy + size.y * 0.35, p.y)
		fog.size = size
		var fm := FogMaterial.new()
		fm.density = float(spec[2])
		fm.albedo = Color(0.84, 0.87, 0.90)
		fm.edge_fade = 0.8
		fm.height_falloff = 0.3
		fog.material = fm
		root.add_child(fog)


static func _asset_on(root: Node3D, map_name: String, asset_name: String,
		p: Vector2, yaw: float = 0.0, sink: float = 0.0,
		scale_f: float = 1.0) -> Node3D:
	# Hero oak/pine GLBs had a different silhouette and material set from the
	# MultiMesh forest.  Route them through the same authored library so every
	# tree on every map uses one style.
	if asset_name == "vegetation/oak_hero":
		return _spawn_library_tree(root, map_name, p, false, yaw, scale_f)
	if asset_name == "vegetation/pine_hero":
		return _spawn_library_tree(root, map_name, p, true, yaw, scale_f)
	var y := _height(map_name, p.x, p.y) - sink
	return ASSETS.spawn(root, asset_name, Vector3(p.x, y, p.y), yaw, scale_f)


## A single large tree from the shared Blender vegetation library.  Same trunk
## and leaf-card materials as the MultiMesh belts, just scaled for hero trees.
static func _spawn_library_tree(root: Node3D, map_name: String, p: Vector2,
		pine: bool, yaw: float, scale_f: float) -> Node3D:
	if _structure_clear_zone(map_name, p.x, p.y) or _hall_clear_zone(map_name, p.x, p.y):
		return null
	var variants := VEGETATION.trees()
	if variants.is_empty():
		return null
	var variant: Dictionary = {}
	for v in variants:
		if bool(v.get("pine", false)) == pine:
			variant = v
			break
	if variant.is_empty():
		return null
	var s := (2.6 if pine else 3.0) * maxf(scale_f, 0.25)
	var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s),
			Vector3(p.x, _height(map_name, p.x, p.y), p.y))
	if pine:
		(_hero_tree_slots["pine"] as Array).append(xf)
	else:
		(_hero_tree_slots["oak"] as Array).append(xf)
	return null


## Turn all collected hero-tree transforms into two MultiMesh draws (one oak
## trunk, one oak leaf card).  Using a single hero variant also keeps the
## 60 FPS draw budget intact while every tree still comes from the same library.
static func _flush_library_trees(root: Node3D) -> void:
	var variants := VEGETATION.trees()
	if variants.is_empty():
		return
	var xfs: Array = []
	xfs.append_array(_hero_tree_slots["oak"] as Array)
	xfs.append_array(_hero_tree_slots["pine"] as Array)
	(_hero_tree_slots["oak"] as Array).clear()
	(_hero_tree_slots["pine"] as Array).clear()
	if xfs.is_empty():
		return
	var variant: Dictionary = {}
	for v in variants:
		if not bool(v.get("pine", false)):
			variant = v
			break
	if variant.is_empty():
		return
	for part in ["trunk", "leaves"]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = variant[part]
		mm.instance_count = xfs.size()
		for i in range(xfs.size()):
			mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "HeroTrees_" + part
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON \
				if part == "trunk" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)

	# Trunk collision for hero trees so drones collide with tree trunks
	for xf in xfs:
		var t: Transform3D = xf
		var s: float = t.basis.get_scale().x
		var t_body := StaticBody3D.new()
		t_body.name = "HeroTreeTrunkCol"
		t_body.position = t.origin + Vector3(0.0, 3.2 * s, 0.0)
		t_body.collision_layer = 1
		t_body.collision_mask = 1
		var t_cs := CollisionShape3D.new()
		var t_shape := CylinderShape3D.new()
		t_shape.radius = 0.38 * s
		t_shape.height = 6.4 * s
		t_cs.shape = t_shape
		t_body.add_child(t_cs)
		root.add_child(t_body)


## Spawns a landmark and attaches a destructible proxy.  The proxy does not add
## geometry: it hides the GLB and replaces it with rubble when its HP reaches 0.
static func _destructible_on(root: Node3D, map_name: String, asset_name: String,
		p: Vector2, yaw: float = 0.0, hp: float = 1600.0, pts: int = 500,
		sink: float = 0.0) -> Node3D:
	var inst := _asset_on(root, map_name, asset_name, p, yaw, sink)
	_wrap_landmark(root, inst, hp, pts)
	return inst


static func _wrap_landmark(root: Node3D, inst: Node3D, hp: float, pts: int) -> void:
	if inst == null or OS.has_environment("QA_NO_DESTRUCTIBLES"):
		return
	var dl := DESTRUCTIBLE_LANDMARK.new()
	dl.name = "Destructible_" + String(inst.name)
	root.add_child(dl)
	dl.global_position = inst.global_position
	dl.setup(inst, hp, pts)
	var level := root.get_parent()
	if level != null and level.has_method("_on_building_destroyed"):
		dl.destroyed.connect(Callable(level, "_on_building_destroyed"))


static func _bank_height(map_name: String, x: float, z: float, half_span: float) -> float:
	return maxf(_height(map_name, x - half_span, z),
			_height(map_name, x + half_span, z))


static func _build_steppe(root: Node3D, map_name: String) -> void:
	# Farmstead by the training outpost: farm_complex.glb stands alone on this pad
	# with all sides completely open and unobstructed for freestyle flying.
	# Two more farmsteads across the map: the steppe must read as settled
	# farmland everywhere, not only around the training spawn.
	_spawn_cottage(root, "cottage_a", Vector2(-205, 40), _height(map_name, -205, 40), 0.4, 0)
	_spawn_cottage(root, "barn_a", Vector2(-225, 22), _height(map_name, -225, 22), 0.1, 2)
	_spawn_cottage(root, "cottage_b", Vector2(225, -40), _height(map_name, 225, -40), -0.3, 3)
	_spawn_cottage(root, "barn_a", Vector2(245, -58), _height(map_name, 245, -58), -0.6, 1)
	for p in [Vector2(-195, 30), Vector2(235, -30)]:
		ASSETS.spawn_prop(root, "prop_hay",
				Vector3(p.x, _height(map_name, p.x, p.y), p.y), 0.0, 1.0)
		ASSETS.spawn_prop(root, "prop_fence",
				Vector3(p.x + 8.0, _height(map_name, p.x + 8.0, p.y), p.y), 0.0, 1.0)
	# Farm track from the north field into the yard.
	_ribbon(root, PackedVector2Array([Vector2(58, 182), Vector2(50, 156),
			Vector2(40, 138)]), 3.0, _pbr("dirt", Color(0.80, 0.66, 0.50), 0.30), 0.06)
	for off in [-1.1, 1.1]:
		_ribbon(root, PackedVector2Array([Vector2(58.0 + off, 182), Vector2(50.0 + off, 156),
				Vector2(40.0 + off, 138)]), 0.42,
				_pbr("dirt", Color(0.45, 0.36, 0.27), 0.40), 0.075)
	_add_burnt_tank(root, map_name, Vector2(-120, -75), 0.6)
	_add_burnt_tank(root, map_name, Vector2(140, -85), 1.2)
	# Burnt armour along the trench line.
	for p in [Vector2(-170, -110), Vector2(-60, -25), Vector2(95, -100),
			Vector2(195, -55), Vector2(-240, -20)]:
		_add_burnt_tank(root, map_name, p, 0.6)

	# Windbreak shelterbelt.
	_add_windbreak(root, map_name, Vector2(-230, 120), Vector2(220, 145))

	# Active Military Early Warning Radar Station (dynamic 360-deg scanner, zero FPS cost)
	var radar_pos := Vector3(-225.0, _height(map_name, -225.0, -210.0), -210.0)
	var radar := MOVING_RADAR.create_radar(radar_pos, 0.4)
	root.add_child(radar)
	for p in [Vector2(-243, -190), Vector2(-207, -230)]:
		_asset_on(root, map_name, "vegetation/pine_hero", p, float(p.x) * 0.02)
	for p in [Vector2(-245, -225), Vector2(-210, -195)]:
		_asset_on(root, map_name, "vegetation/oak_hero", p, float(p.y) * 0.02)
	for p in [Vector2(-213, -202), Vector2(-237, -218)]:
		_asset_on(root, map_name, "hedgehog", p, float(p.y) * 0.01)
	for p in [Vector2(-219, -198), Vector2(-231, -222)]:
		ASSETS.spawn_prop(root, "prop_crate", Vector3(p.x, _height(map_name, p.x, p.y), p.y), 0.3)


static func _build_village(root: Node3D, map_name: String) -> void:
	# PBR village palette.  These reuse the authored landmark texture sets, so
	# the houses no longer read as flat beige boxes next to the detailed GLBs.
	var wall_plaster := _pbr("plaster", Color(0.96, 0.92, 0.86), 0.20)
	var wall_brick := _pbr("brick", Color(0.94, 0.88, 0.82), 0.24)
	var wall_burnt := _pbr("plaster", Color(0.24, 0.22, 0.19), 0.28)
	var roof_tile := _pbr("roof", Color(0.96, 0.91, 0.86), 0.26)
	var roof_metal := _pbr("steel", Color(0.46, 0.48, 0.46), 0.24)
	var stone := _pbr("concrete", Color(0.84, 0.82, 0.76), 0.22)
	var wood := _pbr("wood", Color(0.86, 0.78, 0.66), 0.30)
	var dark := _mat(Color(0.08, 0.08, 0.07), 0.85)
	var glass := _mat(Color(0.035, 0.055, 0.070), 0.10, 0.35)

	# Church with bell tower - the map landmark.
	var cp := Vector2(20, -70)
	var cy := _height(map_name, cp.x, cp.y)
	_add_box(root, Vector3(cp.x, cy + 0.35, cp.y), Vector3(14.2, 0.7, 23.2), stone, 0.0, true)
	_add_box(root, Vector3(cp.x, cy + 5.0, cp.y), Vector3(13.0, 10.0, 22.0), wall_brick, 0.0, true)
	_add_prism(root, Vector3(cp.x, cy + 11.2, cp.y), Vector3(14.4, 3.4, 23.4), roof_tile, 0.0)
	_add_box(root, Vector3(cp.x, cy + 11.0, cp.y - 12.0), Vector3(7.0, 22.0, 7.0), wall_brick, 0.0, true)
	_add_prism(root, Vector3(cp.x, cy + 23.5, cp.y - 12.0), Vector3(8.0, 4.0, 8.0), roof_metal, 0.0)
	_add_box(root, Vector3(cp.x, cy + 26.0, cp.y - 12.0), Vector3(0.16, 2.6, 0.16), dark, 0.0, false)
	_add_box(root, Vector3(cp.x, cy + 26.4, cp.y - 12.0), Vector3(1.4, 0.16, 0.16), dark, 0.0, false)
	# Buttresses, arched window frames and the west door.
	for z in [-8.0, -2.0, 4.0, 9.0]:
		for sx in [-1.0, 1.0]:
			_add_box(root, Vector3(cp.x + sx * 6.85, cy + 3.4, cp.y + z),
					Vector3(0.55, 6.8, 1.1), stone, 0.0, true)
			_add_box(root, Vector3(cp.x + sx * 6.53, cy + 5.0, cp.y + z),
					Vector3(0.08, 2.5, 0.95), glass, 0.0, false)
	_add_box(root, Vector3(cp.x, cy + 1.35, cp.y + 11.05), Vector3(1.8, 2.7, 0.22),
			wood, 0.0, false)
	_add_box(root, Vector3(cp.x, cy + 2.8, cp.y + 11.12), Vector3(2.2, 0.18, 0.34),
			roof_tile, 0.0, false)

	# Dynamic Scenic Windmill atop the village bluff (zero FPS cost)
	var windmill_pos := Vector3(-110.0, _height(map_name, -110.0, 115.0), 115.0)
	var windmill := MOVING_WINDMILL.create_windmill(windmill_pos, -0.2)
	root.add_child(windmill)

	# Dynamic River Patrol Boat cruising the village water channel (zero FPS cost)
	var village_river_wps: Array[Vector3] = [
		Vector3(30.0, -0.4, -45.0),
		Vector3(95.0, -0.4, -65.0),
		Vector3(165.0, -0.4, -55.0),
		Vector3(230.0, -0.4, -80.0),
		Vector3(165.0, -0.4, -55.0),
		Vector3(95.0, -0.4, -65.0),
	]
	var v_boat := MOVING_PATROL_BOAT.create_patrol_boat(village_river_wps, -0.4, 0.0)
	root.add_child(v_boat)

	# Houses and ruins.
	var rng := RandomNumberGenerator.new()
	rng.seed = 4411
	var houses := [
		# Main cottage street through the showcase spawn: both sides of z=70,
		# plus a back row, so the lane reads as a real village rather than four
		# isolated houses in a field.
		Vector2(12, 70), Vector2(42, 70), Vector2(66, 70), Vector2(90, 70),
		Vector2(114, 70), Vector2(138, 70),
		Vector2(30, 46), Vector2(54, 46), Vector2(78, 46), Vector2(104, 46),
		Vector2(128, 46), Vector2(152, 40),
		Vector2(36, 96), Vector2(60, 96), Vector2(88, 96), Vector2(114, 96),
		Vector2(140, 96),
		# Scattered farmsteads across the map.
		Vector2(-80, -30), Vector2(-40, -100), Vector2(70, -40), Vector2(120, -110),
		Vector2(-140, -140), Vector2(-190, -60), Vector2(180, 10), Vector2(-120, 40),
		Vector2(30, 110), Vector2(-60, 140), Vector2(160, 150),
		# Remote farmsteads across the compacted 614 m map.
		Vector2(-245, 60), Vector2(-248, -175), Vector2(248, 120),
		Vector2(235, -210), Vector2(-235, 225), Vector2(245, 235),
		Vector2(140, -245),
	]
	for i in range(houses.size()):
		var p: Vector2 = houses[i]
		# The hero grain-elevator / repair hall now owns the east end of the
		# lane.  Do not grow a cottage through its wall.
		if _hall_clear_zone(map_name, p.x, p.y):
			continue
		var yaw := 0.0 if i <= 16 else rng.randf_range(-0.35, 0.35)
		var w := rng.randf_range(7.0, 11.0)
		var d := rng.randf_range(6.0, 9.0)
		var h := rng.randf_range(3.2, 4.6)
		var y := footprint_surface_height(map_name, p, w, d, yaw) - 0.25
		var burnt := i > 16 and i % 8 == 5
		var house_mat: Material = wall_brick if i % 2 == 1 else wall_plaster
		if burnt:
			# Blown-out walls: two L-shaped stubs, no roof.
			_add_box(root, Vector3(p.x - w * 0.3, y + h * 0.5, p.y), Vector3(w * 0.4, h, 0.35),
					wall_burnt, yaw, true)
			_add_box(root, Vector3(p.x, y + h * 0.35, p.y + d * 0.45), Vector3(w, h * 0.7, 0.35),
					wall_burnt, yaw, true)
			_add_box(root, Vector3(p.x + w * 0.35, y + h * 0.25, p.y), Vector3(0.35, h * 0.5, d * 0.7),
					wall_burnt, yaw, true)
			for k in range(3):
				_add_box(root, Vector3(p.x - w * 0.2 + float(k) * 2.2, y + 0.25, p.y + d * 0.2),
						Vector3(1.8, 0.35, 0.4), dark, yaw + 0.2 * float(k), false)
		else:
			# Authored cottage/barn kit.  Glass panes are stripped from the
			# mesh before the trimesh collider is built, so the long-facade
			# windows are genuine openings; the old hollow boxes remain only
			# for the burnt ruins.
			var variant := "cottage_b" if i % 5 == 0 else "cottage_a"
			_spawn_cottage(root, variant, p, y, yaw, i)
			_add_cottage_yard(root, p, y, w, d, yaw, stone, wood)

	# A pair of authored barns gives the lane agricultural scale.
	var by1 := footprint_surface_height(map_name, Vector2(36, 58), 12.0, 10.0, 0.0) - 0.25
	_spawn_cottage(root, "barn_a", Vector2(36, 58), by1, 0.0, 2)
	if not _hall_clear_zone(map_name, 126.0, 96.0):
		var by2 := footprint_surface_height(map_name, Vector2(126, 96), 12.0, 10.0, PI) - 0.25
		_spawn_cottage(root, "barn_a", Vector2(126, 96), by2, PI, 3)

	# Village dressing: well, fences, power line.
	_add_well(root, Vector2(8, 42), _height(map_name, 8, 42), stone, wood, roof_tile)
	_add_well(root, Vector2(86, 62), _height(map_name, 86, 62), stone, wood, roof_tile)
	for p in [Vector2(-64, 4), Vector2(104, 92), Vector2(-156, -104)]:
		_add_power_pole(root, p, _height(map_name, p.x, p.y), wood, stone)
	# Farmyard props from the shared Blender props library.  They add the
	# mid-scale detail that was completely missing from the empty field.
	for entry in [
		["prop_hay", Vector2(60, 74), 1.0, 0.3],
		["prop_hay", Vector2(122, 62), 0.9, 1.2],
		["prop_hay", Vector2(82, 40), 1.1, 0.7],
		["prop_barrel", Vector2(82, 74), 1.0, 0.2],
		["prop_barrel", Vector2(98, 74), 1.0, 1.1],
		["prop_crate", Vector2(84, 66), 1.0, 0.4],
		["prop_crate", Vector2(96, 66), 1.0, 1.5],
		["prop_logs", Vector2(58, 66), 0.9, 0.3],
		["prop_barrel", Vector2(62, 65), 1.0, 0.0],
		["prop_crate", Vector2(64, 65), 0.9, 0.5],
		["prop_logs", Vector2(72, 42), 1.0, 0.6],
		["prop_logs", Vector2(122, 50), 1.0, 0.2],
		["prop_tires", Vector2(108, 94), 1.0, 0.8],
		["prop_fence", Vector2(74, 63), 1.0, 0.0],
		["prop_fence", Vector2(108, 53), 1.0, 0.0],
		# Foreground dressing on the showcase lane: a fence line, woodpile,
		# barrels and hay so the spawn view has a layered foreground instead of
		# an empty dirt field.
		["prop_fence", Vector2(54, 80), 0.0, 1.0],
		["prop_fence", Vector2(58, 80), 0.0, 1.0],
		["prop_fence", Vector2(62, 80), 0.0, 1.0],
		["prop_fence", Vector2(70, 80), 0.0, 1.0],
		["prop_fence", Vector2(74, 80), 0.0, 1.0],
		["prop_logs", Vector2(58, 85), 0.0, 1.1],
		["prop_barrel", Vector2(76, 85), 0.4, 1.0],
		["prop_hay", Vector2(46, 89), 0.2, 1.1],
		["prop_car_wreck", Vector2(102, 78), 0.4, 1.0],
	]:
		var prop_name: String = entry[0]
		var pp: Vector2 = entry[1]
		if _hall_clear_zone(map_name, pp.x, pp.y):
			continue
		var s_val: float = float(entry[3]) if float(entry[3]) > 0.05 else 1.0
		var y_val: float = float(entry[2])
		ASSETS.spawn_prop(root, prop_name,
				Vector3(pp.x, _height(map_name, pp.x, pp.y), pp.y),
				y_val, s_val)
	# The showcase cottage lane: a dirt path from the training spawn to the
	# hero house, with two mature oaks framing the view.
	_ribbon(root, PackedVector2Array([Vector2(90, 116), Vector2(90, 72),
			Vector2(96, 42)]), 2.6, _pbr("dirt", Color(0.58, 0.48, 0.38), 0.30), 0.06)
	# Cottage street path under the spawn, running the length of the lane.
	_ribbon(root, PackedVector2Array([Vector2(66, 118), Vector2(66, 70),
			Vector2(64, 34)]), 3.0, _pbr("dirt", Color(0.58, 0.48, 0.38), 0.30), 0.06)
	# The main village street (z=58): packed dirt with two darker wheel ruts,
	# ending at the factory gate so the lane has a destination.
	_ribbon(root, PackedVector2Array([Vector2(8, 58), Vector2(145, 58)]), 5.2,
			_pbr("dirt", Color(0.50, 0.42, 0.34), 0.30), 0.06)
	for rz in [56.3, 59.7]:
		_ribbon(root, PackedVector2Array([Vector2(8, rz), Vector2(145, rz)]), 0.55,
				_pbr("dirt", Color(0.34, 0.28, 0.22), 0.40), 0.075)
	for p in [Vector2(50, 82), Vector2(84, 84), Vector2(56, 110)]:
		if not _hall_clear_zone(map_name, p.x, p.y):
			_asset_on(root, map_name, "vegetation/oak_hero", p, float(p.x) * 0.02, 0.0, 0.62)
	# Street framing: two mature oaks in the yards and the skyline trees behind
	# the back row (smaller scale keeps the trunks off the street).
	for p in [Vector2(32, 74), Vector2(158, 66), Vector2(96, 104)]:
		if not _hall_clear_zone(map_name, p.x, p.y):
			_asset_on(root, map_name, "vegetation/oak_hero", p, float(p.x) * 0.03, 0.0, 0.62)
	for p in [Vector2(42, 56), Vector2(128, 58), Vector2(54, 116), Vector2(126, 114)]:
		if not _hall_clear_zone(map_name, p.x, p.y):
			_asset_on(root, map_name, "vegetation/pine_hero", p, float(p.y) * 0.03, 0.0, 0.68)
	# Outskirts: simple PBR farmhouses on a ring so the aerial view reads as a
	# settled village, not a single street in a field.  Authored cottages stay
	# in the playable centre; these are cheap batched boxes/prisms.
	for i in range(30):
		var a := TAU * float(i) / 30.0 + 0.11
		var r := 240.0 + float(i % 3) * 60.0
		var p := Vector2(cos(a) * r, sin(a) * r)
		if _height(map_name, p.x, p.y) < water_level(map_name) + 0.9:
			continue
		if _hall_clear_zone(map_name, p.x, p.y):
			continue
		_add_simple_house(root, map_name, p, a + PI * 0.5,
				7.0 + float(i % 4), 6.0 + float(i % 3),
				3.2 + float(i % 3) * 0.4,
				wall_brick if i % 3 == 0 else wall_plaster,
				roof_metal if i % 4 == 0 else roof_tile, stone)

	# Burnt vehicles on the road.
	for p in [Vector2(-30, 175), Vector2(60, 120), Vector2(-130, 20)]:
		_add_burnt_tank(root, map_name, p, 1.1)


## Facade trim, porch, shutters, chimney, foundation and front fence.  This is
## deliberately simple geometry, but PBR materials and the layered silhouette
## (plinth -> wall -> windows -> eaves -> roof -> chimney) break the box look.
static func _dress_house(root: Node3D, p: Vector2, y: float, w: float, d: float,
		h: float, yaw: float, wall: Material, roof: Material, stone: Material,
		wood: Material, glass: Material) -> void:
	var base := Vector3(p.x, y, p.y)
	var basis := Basis(Vector3.UP, yaw)
	# Stone plinth.
	_add_box(root, base + Vector3(0, 0.22, 0), Vector3(w + 0.55, 0.44, d + 0.55),
			stone, yaw, true)
	# Chimney.
	var chimney := base + basis * Vector3(w * 0.28, h + 2.65, d * 0.18)
	_add_box(root, chimney, Vector3(0.72, 3.1, 0.72), stone, yaw, true)
	_add_box(root, chimney + Vector3(0, 1.6, 0), Vector3(0.9, 0.16, 0.9), roof, yaw, false)
	# Front door + frame + porch.
	var door := base + basis * Vector3(0.0, 1.35, d * 0.5 + 0.02)
	_add_box(root, door, Vector3(1.3, 2.35, 0.12), wood, yaw, false)
	for sx in [-0.72, 0.72]:
		_add_box(root, base + basis * Vector3(sx, 1.35, d * 0.5 + 0.04),
				Vector3(0.14, 2.55, 0.18), stone, yaw, false)
	_add_box(root, base + basis * Vector3(0.0, 2.62, d * 0.5 + 0.04),
			Vector3(1.68, 0.16, 0.20), stone, yaw, false)
	var porch := base + basis * Vector3(0.0, 2.75, d * 0.5 + 0.85)
	_add_box(root, porch, Vector3(2.2, 0.16, 1.55), roof, yaw, false)
	for sx in [-0.92, 0.92]:
		_add_box(root, base + basis * Vector3(sx, 1.35, d * 0.5 + 1.45),
				Vector3(0.13, 2.7, 0.13), wood, yaw, true)
	# Window frames and shutters on both long facades.
	for sz in [-1.0, 1.0]:
		for cx in [-0.28 * w, 0.0, 0.28 * w]:
			var c := base + basis * Vector3(cx, 1.95, sz * (d * 0.5 + 0.06))
			_add_box(root, c + Vector3(0, 0.67, 0), Vector3(1.24, 0.12, 0.18), stone, yaw, false)
			_add_box(root, c - Vector3(0, 0.67, 0), Vector3(1.24, 0.12, 0.18), stone, yaw, false)
			for sx in [-0.59, 0.59]:
				_add_box(root, c + basis * Vector3(sx, 0, 0), Vector3(0.12, 1.46, 0.18),
						stone, yaw, false)
				# Open wooden shutters beside the opening.
				_add_box(root, base + basis * Vector3(cx + sx * 1.75, 1.95, sz * (d * 0.5 + 0.10)),
						Vector3(0.42, 1.18, 0.07), wood, yaw, false)
	# A small front garden and fence; posts collide, rails don't.
	var garden := base + basis * Vector3(w * 0.58, 0.06, d * 0.12)
	_add_box(root, garden, Vector3(w * 0.52, 0.12, d * 0.52),
			_mat(Color(0.14, 0.105, 0.065), 1.0), yaw, false)
	_add_fence_line(root, base + basis * Vector3(0.0, 0.0, d * 0.5 + 3.1),
			w + 3.8, yaw, wood)


static func _add_cottage_yard(root: Node3D, p: Vector2, y: float, w: float, d: float,
		yaw: float, stone: Material, wood: Material) -> void:
	var base := Vector3(p.x, y, p.y)
	var basis := Basis(Vector3.UP, yaw)
	# Front garden strip, pushed to the side so the porch remains readable.
	_add_box(root, base + basis * Vector3(w * 0.52, 0.06, d * 0.12),
			Vector3(w * 0.44, 0.12, d * 0.42),
			_mat(Color(0.085, 0.095, 0.048), 1.0), yaw, false)
	_add_fence_line(root, base + basis * Vector3(0.0, 0.0, d * 0.5 + 3.2),
			w + 4.0, yaw, wood)
	# A small woodpile beside every fourth cottage.
	_add_box(root, base + basis * Vector3(-w * 0.55, 0.35, d * 0.15),
			Vector3(1.0, 0.7, 1.6), _mat(Color(0.19, 0.13, 0.08), 1.0), yaw, true)


## Cheap batched farmhouse for the outskirts: hollow walls with real windows
## and a front door, a pitched roof and a chimney.
static func _add_simple_house(root: Node3D, map_name: String, p: Vector2,
		yaw: float, w: float, d: float, h: float, wall: Material,
		roof: Material, stone: Material) -> void:
	var y := footprint_surface_height(map_name, p, w, d, yaw) + 0.12
	var basis := Basis(Vector3.UP, yaw)
	var base := Vector3(p.x, y, p.y)
	# The outskirts ring sits on the coarse outer terrain mesh (8 m cells).
	# Placing the house at the analytic height buried it on uphill slopes, so
	# only the chimney/roof edge poked out of the ground.  The footprint max
	# puts the walls on the rendered surface; the buried stone skirt reaches
	# the downhill corners without any visible gap.
	_add_box(root, base + Vector3(0.0, -6.0, 0.0),
			Vector3(w + 0.7, 12.4, d + 0.7), stone, yaw, false)
	_add_house_shell(root, p, y, w, d, h, yaw, wall)
	_add_prism(root, base + Vector3(0, h + 1.1, 0), Vector3(w + 1.2, 2.2, d + 1.2),
			roof, yaw)
	_add_box(root, base + basis * Vector3(w * 0.32, h + 0.9, d * 0.2),
			Vector3(0.6, 1.8, 0.6), stone, yaw, true)
	# Prominent large stone/wood frames around real fly-through openings.
	var win_w := 2.4
	var win_bottom := 0.85
	var win_top := minf(h - 0.45, 2.75)
	var win_h := win_top - win_bottom
	var off := maxf(minf(w * 0.30, w * 0.5 - win_w * 0.5 - 0.20), 0.20)
	var front := base + basis * Vector3(0.0, 0.0, d * 0.5)
	var back := base + basis * Vector3(0.0, 0.0, -d * 0.5)
	for sx in [-1.0, 1.0]:
		_add_opening_frame(root, front, basis, yaw,
				Rect2(sx * off - win_w * 0.5, win_bottom, win_w, win_h),
				0.35, stone)
	_add_opening_frame(root, front, basis, yaw,
			Rect2(-win_w * 0.5, 0.0, win_w, minf(h - 0.30, 2.30)), 0.35, stone)
	for cx in [-off, 0.0, off]:
		_add_opening_frame(root, back, basis, yaw,
				Rect2(cx - win_w * 0.5, win_bottom, win_w, win_h), 0.35, stone)
	for sx in [-1.0, 1.0]:
		var side_basis := Basis(Vector3.UP, yaw + PI * 0.5)
		var side := base + basis * Vector3(sx * w * 0.5, 0.0, 0.0)
		_add_opening_frame(root, side, side_basis, yaw + PI * 0.5,
				Rect2(-win_w * 0.5, win_bottom, win_w, win_h), 0.35, stone)
	# Eave and chimney cap.
	_add_box(root, base + basis * Vector3(0.0, h + 0.06, -d * 0.5 - 0.10),
			Vector3(w + 0.9, 0.14, 0.45), roof, yaw, false)
	_add_box(root, base + basis * Vector3(w * 0.32, h + 2.05, d * 0.2),
			Vector3(0.85, 0.14, 0.85), stone, yaw, false)


static func _add_fence_line(root: Node3D, center: Vector3, length: float, yaw: float,
		wood: Material) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var count := maxi(2, int(length / 2.1))
	for i in range(count):
		var x := -length * 0.5 + (float(i) + 0.5) * (length / float(count))
		# Leave a two-metre gate opening in the middle.
		if absf(x) < 1.05:
			continue
		var post := center + basis * Vector3(x, 0.62, 0)
		for rail_y in [0.48, 0.98]:
			_add_box(root, post + basis * Vector3(0, rail_y - 0.62, 0),
					Vector3(length / float(count) - 0.08, 0.10, 0.09), wood, yaw, false)
		_add_box(root, post, Vector3(0.12, 1.28, 0.12), wood, yaw, true)


static func _add_well(root: Node3D, p: Vector2, y: float, stone: Material,
		wood: Material, roof: Material) -> void:
	var base := Vector3(p.x, y, p.y)
	_add_cylinder(root, base + Vector3(0, 0.55, 0), 0.95, 1.1, stone, 0.0, true)
	_add_cylinder(root, base + Vector3(0, 1.08, 0), 0.72, 0.08,
			_mat(Color(0.035, 0.055, 0.045), 0.25, 0.2), 0.0, false)
	for sx in [-0.82, 0.82]:
		_add_box(root, base + Vector3(sx, 1.45, 0), Vector3(0.12, 1.8, 0.12),
				wood, 0.0, true)
	_add_box(root, base + Vector3(0, 2.32, 0), Vector3(2.1, 0.14, 1.15), roof, 0.0, false)


static func _add_power_pole(root: Node3D, p: Vector2, y: float, wood: Material,
		stone: Material) -> void:
	var base := Vector3(p.x, y, p.y)
	_add_cylinder(root, base + Vector3(0, 4.0, 0), 0.17, 8.0, wood, 0.0, true)
	_add_box(root, base + Vector3(0, 7.35, 0), Vector3(2.5, 0.13, 0.13), wood, 0.0, false)
	for sx in [-1.05, 1.05]:
		_add_box(root, base + Vector3(sx, 7.55, 0), Vector3(0.12, 0.26, 0.12),
				stone, 0.0, false)


static func _build_industrial(root: Node3D, map_name: String) -> void:
	var q_low := QualityManager.get_active_level() == QualityManager.Level.LOW
	var concrete := _pbr("concrete", Color(0.84, 0.83, 0.79), 0.18)
	var brick := _pbr("brick", Color(0.82, 0.68, 0.58), 0.22)
	var metal := _pbr("steel", Color(0.52, 0.55, 0.57), 0.14)
	var rust := _pbr("steel", Color(0.52, 0.29, 0.17), 0.20)
	var dark := _mat(Color(0.07, 0.07, 0.07), 1.0)

	# Dynamic Industrial Rotating Tower Crane (zero FPS cost, full collision)
	var tower_crane_pos := Vector3(85.0, _height(map_name, 85.0, -95.0), -95.0)
	var tower_crane := MOVING_CRANE.create_rotating_tower_crane(tower_crane_pos, 0.2)
	root.add_child(tower_crane)

	# Dynamic Heavy Gantry Crane traveling on rails (zero FPS cost, full collision)
	var gantry_pos := Vector3(45.0, _height(map_name, 45.0, -40.0), -40.0)
	var gantry_crane := MOVING_CRANE.create_gantry_crane(gantry_pos, PI * 0.5, 60.0)
	root.add_child(gantry_crane)

	# Main halls.
	_add_hall(root, map_name, Vector2(-120, -40), 58.0, 14.0, 28.0, 0.0, brick, metal)
	_add_hall(root, map_name, Vector2(-30, -120), 42.0, 11.0, 22.0, 0.12, concrete, metal)
	_add_hall(root, map_name, Vector2(-210, 20), 34.0, 9.0, 20.0, -0.2, brick, metal)
	# Additional warehouses across the yard so the industrial zone reads as a
	# full complex from the air and from the far combat spawn.
	_add_hall(root, map_name, Vector2(225, -135), 42.0, 12.0, 22.0, 0.18, brick, metal)
	_add_hall(root, map_name, Vector2(-240, 115), 36.0, 10.0, 20.0, -0.14, concrete, metal)
	# Outer industrial belt inside ±260 m (clear of the southern river channel):
	for spec in [
		[Vector2(235, -210), 46.0, 12.0, 24.0, 0.20],
		[Vector2(-245, -215), 40.0, 10.0, 22.0, -0.10],
		[Vector2(240, 130), 38.0, 9.0, 20.0, 0.35],
		[Vector2(-235, 190), 42.0, 11.0, 22.0, -0.25],
		[Vector2(175, 195), 34.0, 9.0, 18.0, 0.15],
		[Vector2(-180, -240), 40.0, 10.0, 20.0, -0.05],
	]:
		if q_low and spec[0].length() > 245.0:
			continue
		_add_hall(root, map_name, spec[0], spec[1], spec[2], spec[3], spec[4],
				brick, metal)
	# Tank farms with bund walls.
	for centre in [Vector2(-80, -235), Vector2(235, 40), Vector2(-235, 165)]:
		for i in range(3):
			var tp: Vector2 = centre + Vector2(float(i) * 15.0, 0.0)
			var ty := _height(map_name, tp.x, tp.y)
			_add_cylinder(root, Vector3(tp.x, ty + 5.0, tp.y), 6.0, 10.0, metal, 0.0, true)
			_add_cylinder(root, Vector3(tp.x, ty + 10.2, tp.y), 6.1, 0.35, rust, 0.0, false)
	# Procedural outer yards: warehouse grid, container stacks and perimeter road.
	var yard_mat := _pbr("asphalt", Color(0.55, 0.55, 0.53), 0.18)
	var container_mats := [
		_pbr("steel", Color(0.58, 0.24, 0.16), 0.28),
		_pbr("steel", Color(0.18, 0.33, 0.44), 0.28),
		_pbr("steel", Color(0.20, 0.36, 0.24), 0.28),
		_pbr("steel", Color(0.46, 0.38, 0.20), 0.28),
	]
	var irng := RandomNumberGenerator.new()
	irng.seed = 9182
	var yards := 0
	for ix in range(-3, 4):
		for iz in range(-3, 4):
			var p := Vector2(float(ix) * 80.0, float(iz) * 80.0)
			if p.length() < 165.0 or absf(p.x) > 250.0 or p.y < -250.0 or p.y > 205.0:
				continue
			if p.distance_to(Vector2(168, 86)) < 85.0:
				continue
			if p.distance_to(Vector2(24, 176)) < 75.0:
				continue
			if q_low and p.length() > 225.0:
				continue
			if irng.randf() < 0.42:
				continue
			var w := irng.randf_range(24.0, 34.0)
			var d := irng.randf_range(15.0, 22.0)
			var h := irng.randf_range(8.0, 11.0)
			var yaw := 0.0 if irng.randf() < 0.5 else PI * 0.5
			_add_hall(root, map_name, p, w, h, d, yaw,
					brick if irng.randf() < 0.5 else concrete, metal)
			var gy := _height(map_name, p.x, p.y)
			_add_box(root, Vector3(p.x, gy + 0.04, p.y),
					Vector3(w + 18.0, 0.10, d + 18.0), yard_mat, yaw, false)
			for k in range(irng.randi_range(3, 5)):
				var off := Vector2(irng.randf_range(-1.0, 1.0) * (w * 0.5 + 8.0),
						irng.randf_range(-1.0, 1.0) * (d * 0.5 + 6.0))
				var cp := p + off
				var cy := _height(map_name, cp.x, cp.y) + 1.3
				if irng.randf() < 0.3:
					cy += 2.55
				_add_box(root, Vector3(cp.x, cy, cp.y),
						Vector3(6.0, 2.5, 2.4),
						container_mats[irng.randi_range(0, 3)],
						irng.randf_range(0.0, TAU), false)
			yards += 1
			if yards >= (7 if q_low else 14):
				break
		if yards >= (7 if q_low else 14):
			break
	# Perimeter road grid (north of southern river).
	for line in [
		[Vector2(-235, -245), Vector2(-235, 210)],
		[Vector2(235, -245), Vector2(235, 210)],
		[Vector2(-255, -235), Vector2(255, -235)],
		[Vector2(-255, 200), Vector2(255, 200)],
	]:
		_ribbon(root, PackedVector2Array(line), 8.0, yard_mat, 0.07)
	# Ruined workshop - collapsed roof beams.
	var rp := Vector2(60, -80)
	var ry := _height(map_name, rp.x, rp.y)
	_add_box(root, Vector3(rp.x, ry + 2.0, rp.y), Vector3(26.0, 4.0, 16.0), concrete, 0.0, true)
	for i in range(6):
		_add_box(root, Vector3(rp.x - 10.0 + float(i) * 4.0, ry + 4.3, rp.y),
				Vector3(0.35, 0.35, 17.0), rust, 0.0, false)

	# Chimneys.
	for p in [Vector2(-170, -75), Vector2(-100, -95)]:
		var y := _height(map_name, p.x, p.y)
		_add_cylinder(root, Vector3(p.x, y + 15.0, p.y), 1.7, 30.0, brick, 0.0, true)
		_add_cylinder(root, Vector3(p.x, y + 30.5, p.y), 1.55, 1.0, dark, 0.0, false)
		for band in range(3):
			_add_cylinder(root, Vector3(p.x, y + 22.0 + float(band) * 3.0, p.y),
					1.78, 0.8, concrete, 0.0, false)

	# Storage tanks.
	for i in range(4):
		var p := Vector2(120.0 + float(i) * 26.0, -30.0)
		var y := _height(map_name, p.x, p.y)
		_add_cylinder(root, Vector3(p.x, y + 6.0, p.y), 8.0, 12.0, metal, 0.0, true)
		_add_cylinder(root, Vector3(p.x, y + 12.2, p.y), 8.1, 0.4, rust, 0.0, false)

	# Pipe rack.
	for i in range(5):
		var p := Vector2(-250.0 + float(i) * 18.0, -10.0)
		var y := _height(map_name, p.x, p.y)
		_add_box(root, Vector3(p.x, y + 2.5, p.y), Vector3(0.4, 5.0, 0.4), rust, 0.0, true)
	for i in range(2):
		_add_box(root, Vector3(-210.0, _height(map_name, -210.0, -10.0) + 5.0 + float(i) * 0.9, -10.0),
				Vector3(74.0, 0.35, 0.35), rust, 0.0, false)

	# Rail spur embankment.
	_ribbon(root, PackedVector2Array([Vector2(-265, -220), Vector2(-130, -210),
			Vector2(0, -220), Vector2(130, -210), Vector2(265, -225)]),
			6.0, _mat(Color(0.30, 0.28, 0.25), 1.0), 0.12)

	# Spoil heap bunkers and burnt trucks.
	for p in [Vector2(-225, -145), Vector2(225, 145)]:
		_add_burnt_tank(root, map_name, p, 0.3)
	_add_burnt_tank(root, map_name, Vector2(40, 40), 1.9)
	# Training-spawn outpost: fill the foreground with detailed authored props
	# instead of a bare dirt field.
	_asset_on(root, map_name, "observation_post", Vector2(-45, 55), 0.4)
	_asset_on(root, map_name, "sandbag_wall", Vector2(-30, 48), 0.2)
	_asset_on(root, map_name, "checkpoint", Vector2(-78, 62), -0.3)
	for p in [Vector2(-92, 18), Vector2(-36, 12), Vector2(-10, 70), Vector2(-110, 72)]:
		_asset_on(root, map_name, "vegetation/pine_hero", p, float(p.x) * 0.02)
	for p in [Vector2(-24, 82), Vector2(-96, 92)]:
		_asset_on(root, map_name, "vegetation/oak_hero", p, float(p.y) * 0.02)
	for p in [Vector2(-100, 8), Vector2(-12, 84)]:
		_asset_on(root, map_name, "hedgehog", p, float(p.x) * 0.01)
	for p in [Vector2(-52, 34), Vector2(-42, 30), Vector2(-62, 48)]:
		ASSETS.spawn_prop(root, "prop_barrel", Vector3(p.x, _height(map_name, p.x, p.y), p.y), float(p.x) * 0.02)


# ===========================================================================
#  Map signature POIs (one distinct landmark per frontline map)
# ===========================================================================
static func _poi_site(map_name: String, p: Vector2) -> Vector2:
	var wl := water_level(map_name)
	for ring in range(0, 9):
		var radius := 9.0 * float(ring)
		var steps := 1 if ring == 0 else 12
		for i in range(steps):
			var a := TAU * float(i) / float(steps)
			var c := p + Vector2(cos(a), sin(a)) * radius
			if absf(c.x) > 255.0 or absf(c.y) > 255.0:
				continue
			if _height(map_name, c.x, c.y) <= wl + 0.6:
				continue
			if _hall_clear_zone(map_name, c.x, c.y):
				continue
			return c
	return p


static func _add_collision_box(parent: Node3D, pos: Vector3, size: Vector3,
		yaw: float = 0.0) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = yaw
	body.collision_layer = 1
	body.collision_mask = 1
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	parent.add_child(body)


static func _keep_poi_detail(node: Node3D, lod: float = 1500.0) -> void:
	if node is MeshInstance3D:
		node.set_meta("no_batch", true)
		(node as MeshInstance3D).visibility_range_end = lod
		(node as MeshInstance3D).visibility_range_end_margin = 90.0
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		mi.set_meta("no_batch", true)
		mi.visibility_range_end = lod
		mi.visibility_range_end_margin = 90.0


static func _build_unique_pois(root: Node3D, map_name: String) -> void:
	_poi_positions.clear()
	match map_name:
		"industrial":
			_poi_water_tower(root, map_name, Vector2(235.0, 165.0))
		"village":
			_poi_transformer_yard(root, map_name, Vector2(245.0, -40.0))
		"steppe":
			_poi_burnt_armour(root, map_name, Vector2(-225.0, 115.0))
		"wetlands":
			_poi_watchtower(root, map_name, Vector2(195.0, 70.0))
		_:
			return


## Industrial: a tall riveted water tower - the map's navigation landmark.
static func _poi_water_tower(root: Node3D, map_name: String, p: Vector2) -> Node3D:
	var site := _poi_site(map_name, p)
	var gy := footprint_surface_height(map_name, site, 9.0, 9.0, 0.0)
	var node := Node3D.new()
	node.name = "POI_WaterTower_" + map_name
	node.position = Vector3(site.x, gy, site.y)
	root.add_child(node)
	_poi_positions.append(site)
	var concrete := _pbr("hall_concrete", Color(0.78, 0.76, 0.70), 0.16)
	var steel := _pbr("hall_metal", Color(0.58, 0.62, 0.64), 0.14)
	var rust := _pbr("hall_rust", Color(0.78, 0.62, 0.50), 0.20)
	var band := _pbr("hall_rust", Color(0.72, 0.20, 0.14), 0.24)

	var base := _add_box(node, Vector3(0.0, 0.20, 0.0),
			Vector3(8.4, 1.2, 8.4), concrete)
	_keep_poi_detail(base)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var leg := _add_box(node, Vector3(sx * 2.8, 7.1, sz * 2.8),
					Vector3(0.38, 13.0, 0.38), steel)
			_keep_poi_detail(leg)
	for h in [4.8, 9.2, 13.2]:
		_add_box(node, Vector3(0.0, h, 0.0), Vector3(6.0, 0.22, 0.22),
				steel, 0.0, false)
		_add_box(node, Vector3(0.0, h, 0.0), Vector3(0.22, 0.22, 6.0),
				steel, 0.0, false)
	var tank := _add_cylinder(node, Vector3(0.0, 16.3, 0.0), 4.2, 5.0, steel)
	_keep_poi_detail(tank)
	_add_cylinder(node, Vector3(0.0, 14.25, 0.0), 4.26, 0.34, band, 0.0, false)
	_add_cylinder(node, Vector3(0.0, 17.85, 0.0), 4.26, 0.34, band, 0.0, false)
	var roof := CylinderMesh.new()
	roof.top_radius = 0.18
	roof.bottom_radius = 4.45
	roof.height = 1.7
	roof.radial_segments = 24
	var roof_mi := MeshInstance3D.new()
	roof_mi.mesh = roof
	roof_mi.material_override = rust
	roof_mi.position = Vector3(0.0, 19.65, 0.0)
	roof_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	node.add_child(roof_mi)
	_keep_poi_detail(roof_mi)
	# Roof collision so the tank remains solid from above.
	_add_collision_box(node, Vector3(0.0, 19.2, 0.0), Vector3(6.5, 1.4, 6.5))
	# Ladder on the south-west leg.
	for i in range(16):
		_add_box(node, Vector3(2.8, 1.4 + float(i) * 0.78, 2.55),
				Vector3(0.62, 0.055, 0.055), rust, 0.0, false)
	_add_box(node, Vector3(2.48, 7.2, 2.55), Vector3(0.055, 12.6, 0.055),
			rust, 0.0, false)
	_add_box(node, Vector3(3.12, 7.2, 2.55), Vector3(0.055, 12.6, 0.055),
			rust, 0.0, false)
	# Outlet riser down the north face.
	_add_cylinder(node, Vector3(0.0, 8.2, 4.35), 0.18, 15.6, rust, 0.0, false)
	print("[FrontlineTerrain] POI water tower at ", site)
	return node


## Village: fenced transformer substation with a pole line.
static func _poi_transformer_yard(root: Node3D, map_name: String, p: Vector2) -> Node3D:
	var site := _poi_site(map_name, p)
	var gy := footprint_surface_height(map_name, site, 16.0, 12.0, 0.0)
	var node := Node3D.new()
	node.name = "POI_TransformerYard_" + map_name
	node.position = Vector3(site.x, gy, site.y)
	node.rotation.y = 0.35
	root.add_child(node)
	_poi_positions.append(site)
	var concrete := _pbr("hall_concrete", Color(0.74, 0.72, 0.68), 0.16)
	var steel := _pbr("hall_metal", Color(0.50, 0.55, 0.57), 0.16)
	var rust := _pbr("hall_rust", Color(0.66, 0.52, 0.42), 0.18)
	var ceramic := _mat(Color(0.84, 0.82, 0.72), 0.32)
	var wood := _pbr("wood", Color(0.38, 0.28, 0.20), 0.35)

	# Concrete pad, 0.35 m proud of the grass and buried 0.4 m.
	var pad := _add_box(node, Vector3(0.0, -0.02, 0.0),
			Vector3(17.0, 0.75, 12.5), concrete)
	_keep_poi_detail(pad)
	# Chain-link fence posts + two rails; collision is a thin invisible wall.
	var post_h := 2.4
	for x in [-8.0, -4.0, 0.0, 4.0, 8.0]:
		for z in [-6.0, 6.0]:
			_add_box(node, Vector3(x, post_h * 0.5, z),
					Vector3(0.10, post_h, 0.10), steel, 0.0, false)
	for z in [-4.0, 0.0, 4.0]:
		for x in [-8.0, 8.0]:
			_add_box(node, Vector3(x, post_h * 0.5, z),
					Vector3(0.10, post_h, 0.10), steel, 0.0, false)
	for y in [0.85, 1.95]:
		_add_box(node, Vector3(0.0, y, -6.0), Vector3(16.4, 0.07, 0.07),
				steel, 0.0, false)
		_add_box(node, Vector3(0.0, y, 6.0), Vector3(16.4, 0.07, 0.07),
				steel, 0.0, false)
		_add_box(node, Vector3(-8.0, y, 0.0), Vector3(0.07, 0.07, 12.4),
				steel, 0.0, false)
		_add_box(node, Vector3(8.0, y, 0.0), Vector3(0.07, 0.07, 12.4),
				steel, 0.0, false)
	_add_collision_box(node, Vector3(0.0, 1.2, -6.0), Vector3(16.4, 2.4, 0.16))
	_add_collision_box(node, Vector3(0.0, 1.2, 6.0), Vector3(16.4, 2.4, 0.16))
	_add_collision_box(node, Vector3(-8.0, 1.2, 0.0), Vector3(0.16, 2.4, 12.4))
	_add_collision_box(node, Vector3(8.0, 1.2, 0.0), Vector3(0.16, 2.4, 12.4))

	# Two oil-filled transformers with radiator fins and ceramic bushings.
	var bodies := [[Vector3(-3.2, 0.36, -2.2), 3.8, 2.6, 2.6],
			[Vector3(2.8, 0.36, 2.0), 2.8, 2.1, 2.0]]
	for spec in bodies:
		var cp: Vector3 = spec[0]
		var bw := float(spec[1])
		var bh := float(spec[2])
		var bd := float(spec[3])
		var body := _add_box(node, cp + Vector3(0.0, bh * 0.5, 0.0),
				Vector3(bw, bh, bd), steel)
		_keep_poi_detail(body)
		var lid := _add_box(node, cp + Vector3(0.0, bh + 0.12, 0.0),
				Vector3(bw + 0.3, 0.22, bd + 0.3), rust, 0.0, false)
		_keep_poi_detail(lid)
		for side in [-1.0, 1.0]:
			for k in range(4):
				_add_box(node, cp + Vector3(
						side * (bw * 0.5 + 0.16), bh * 0.55,
						-bd * 0.30 + float(k) * bd * 0.20),
						Vector3(0.28, bh * 0.58, 0.10),
						rust, 0.0, false)
		for k in range(3):
			var bx := -bw * 0.28 + float(k) * bw * 0.28
			var bush := _add_cylinder(node,
					cp + Vector3(bx, bh + 0.68, 0.0),
					0.11, 0.92, ceramic, 0.0, false)
			_keep_poi_detail(bush, 900.0)

	# Pole line feeding the yard.
	var pole := _add_cylinder(node, Vector3(7.2, 5.4, -4.0), 0.16, 10.8, wood)
	_keep_poi_detail(pole, 1200.0)
	_add_box(node, Vector3(7.2, 9.6, -4.0), Vector3(3.2, 0.16, 0.16), wood,
			0.0, false)
	for xo in [-1.4, 0.0, 1.4]:
		_add_cylinder(node, Vector3(7.2 + xo, 10.0, -4.0), 0.10, 0.8, ceramic,
				0.0, false)
	# Hazard placard on the fence.
	_add_box(node, Vector3(-3.0, 1.5, -6.12), Vector3(1.15, 0.72, 0.05),
			_pbr("hall_rust", Color(0.88, 0.72, 0.10), 0.28), 0.0, false)
	print("[FrontlineTerrain] POI transformer yard at ", site)
	return node


## Steppe: a knocked-out armour pair beside the road - a readable POI and
## hard cover at the same time.
static func _poi_burnt_armour(root: Node3D, map_name: String, p: Vector2) -> void:
	var site := _poi_site(map_name, p)
	var MS = load("res://scripts/util/military_structures.gd")
	if MS == null:
		return
	var gy := footprint_surface_height(map_name, site, 12.0, 12.0, 0.0)
	# Sink the builder's earth-anchor pad below the grass; only the hull and
	# tracks should break the surface.
	var tank = MS.build_burnt_tank_hull(root,
			Vector3(site.x, gy - 0.45, site.y), 0.55)
	if tank != null:
		tank.name = "POI_BurntTank_" + map_name
		_poi_positions.append(site)
	var btr_site := _poi_site(map_name, site + Vector2(11.0, 7.0))
	var gy2 := footprint_surface_height(map_name, btr_site, 10.0, 10.0, 0.0)
	var btr = MS.build_burnt_btr_hull(root,
			Vector3(btr_site.x, gy2 - 0.45, btr_site.y), 1.65)
	if btr != null:
		btr.name = "POI_BurntBTR_" + map_name
		_poi_positions.append(btr_site)
	# Scorch ring ties the pair together as one scene event.
	var scorch := Decal.new()
	scorch.name = "POI_Scorch"
	var tex := GradientTexture2D.new()
	var grad := Gradient.new()
	# Softer, brighter scorch: the old near-black alpha-0.9 disc read as a
	# hard black hole from the air on the owner's device recording.
	grad.colors = PackedColorArray([Color(0.12, 0.10, 0.08, 0.55),
			Color(0.10, 0.09, 0.08, 0.0)])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	scorch.texture_albedo = tex
	scorch.size = Vector3(18.0, 7.0, 18.0)
	scorch.albedo_mix = 0.55
	scorch.cull_mask = 1
	scorch.position = Vector3(site.x + 5.0, gy + 3.0, site.y + 3.0)
	root.add_child(scorch)
	print("[FrontlineTerrain] POI burnt armour at ", site)


## Wetlands: a wooden watch tower on the dry bank plus a half-sunk BTR in the
## channel.  Gives the marsh map a vertical silhouette and a story.
static func _poi_watchtower(root: Node3D, map_name: String, p: Vector2) -> void:
	var site := _poi_site(map_name, p)
	var MS = load("res://scripts/util/military_structures.gd")
	if MS == null:
		return
	var gy := footprint_surface_height(map_name, site, 12.0, 12.0, 0.0)
	var tower = MS.build_observation_watchtower(root,
			Vector3(site.x, gy - 0.10, site.y), 0.25)
	if tower != null:
		tower.name = "POI_Watchtower_" + map_name
		_poi_positions.append(site)
	var wreck_site := _poi_site(map_name, site + Vector2(-24.0, 18.0))
	var wreck_y := water_level(map_name) - 0.35
	var wreck = MS.build_burnt_btr_hull(root,
			Vector3(wreck_site.x, wreck_y, wreck_site.y), 2.35)
	if wreck != null:
		wreck.name = "POI_SunkenBTR_" + map_name
		_poi_positions.append(wreck_site)
	print("[FrontlineTerrain] POI watchtower at ", site)


## Interior occluder volume for the hero hall.  A single box inside the hall
## hides the whole interior/far side while the camera is outside; the box is
## backface-culled when the player is inside, so the exterior stays visible.
static func _build_hall_occluders(root: Node3D, map_name: String) -> void:
	var site: Dictionary = HALL_SITES.get(map_name, {})
	if site.is_empty():
		return
	var c: Vector2 = site["center"]
	var wall_half := Vector2(60.0, 27.0)
	match map_name:
		"village":
			wall_half = Vector2(48.0, 23.0)
		"steppe":
			wall_half = Vector2(56.0, 25.0)
		"wetlands":
			wall_half = Vector2(52.0, 24.0)
	var roof := float(site.get("roof_height", 18.0))
	var gy := _height(map_name, c.x, c.y)
	var box := BoxOccluder3D.new()
	box.size = Vector3(wall_half.x * 1.88, roof * 0.90, wall_half.y * 1.88)
	var occ := OccluderInstance3D.new()
	occ.name = "HallOccluder_" + map_name
	occ.occluder = box
	occ.position = Vector3(c.x, gy + roof * 0.45, c.y)
	root.add_child(occ)


## Small clutter casts shadows that are barely visible at FPV speed but still
## cost a shadow-map draw.  Keep hero props and anything above 1.6 m.
static func _trim_small_shadow_casters(root: Node3D) -> void:
	var trimmed := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			continue
		var box: AABB = mi.global_transform * mi.get_aabb()
		var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
		if longest < 1.6:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			trimmed += 1
	if trimmed > 0:
		print("[FrontlineTerrain] shadow casters trimmed: ", trimmed)


## One authored ruined concrete hall per map.  Geometry is authored in Blender
## (tools/blender_industrial_hall.py); the same CC0 Poly Haven PBR maps and the
## same material recipe are applied everywhere.  The Industrial hall gets the
## full interior rig (shafts, dust, fog); the other maps use a dim fill because
## their halls are background landmarks seen from outside.
## War-wear dressing: charred ground, rust streaks and rubble on every large
## building so the frontline reads as fought-over, not pristine.  Visual only
## (no collision); cheap unshaded/opaque quads and small boxes.
static func _add_war_wear(root: Node3D, map_name: String) -> void:
	# Procedural smooth rust streak, not the low-res bitmap: the authored
	# decal_rust.png reads as blocky pixels when stretched over a wide wall.
	var rust_tex := _rust_streak_tex()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(map_name) + 7717
	var worn := 0
	for node in root.get_children():
		if not (node is Node3D):
			continue
		var aabb := _wear_aabb(node as Node3D)
		# Only the big halls/landmarks: dressing every shed and post (68 nodes)
		# blew up the load on the device and its draw budget for no visual gain.
		if aabb.size.y < 12.0 or maxf(aabb.size.x, aabb.size.z) < 10.0:
			continue
		if aabb.size.y > 70.0 or maxf(aabb.size.x, aabb.size.z) > 150.0:
			continue  # not a building
		_wear_building(node as Node3D, aabb, rust_tex, rng)
		worn += 1
	print("[WarWear] ", map_name, " buildings=", worn)


static func _wear_aabb(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var b := m.transform * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


static func _wear_building(node: Node3D, aabb: AABB, rust_tex: Texture2D,
		rng: RandomNumberGenerator) -> void:
	var base := aabb.position.y
	var hw := aabb.size.x * 0.5
	var hd := aabb.size.z * 0.5
	# Damage scales with the building so it reads from the air on the big halls
	# without overwhelming the small sheds.
	var wear := clampf(aabb.size.y / 12.0, 0.85, 1.8)
	_add_wear_char(node, Vector3(hw * 0.55, base + 0.05, hd * 0.55),
			rng.randf_range(13.0, 20.0) * wear)
	for sx in [-1.0, 1.0]:
		_add_wear_rubble(node, Vector3(sx * (hw + 2.0), base, hd * 0.6), rng, wear)
	# Shell damage on the front face: two dark impact holes with rubble beneath.
	var hole_tex := _shell_hole_tex()
	for i in range(3):
		var hx := rng.randf_range(-hw * 0.4, hw * 0.4)
		_add_shell_hole(node, Vector3(hx, base + rng.randf_range(3.0, 7.0) * wear,
				hd + 0.04), rng.randf_range(4.0, 7.0) * wear, hole_tex)
		_add_wear_rubble(node, Vector3(hx, base, hd + 1.6), rng, wear)
	if rust_tex != null:
		_add_wear_rust(node, Vector3(0.0, base + 2.0, hd + 0.04),
				Vector2(minf(aabb.size.x * 0.5, 20.0), 6.0 * wear), 0.0, rust_tex)
		_add_wear_rust(node, Vector3(0.0, base + 2.2, -hd - 0.04),
				Vector2(minf(aabb.size.x * 0.5, 20.0), 6.0 * wear), PI, rust_tex)


static var _shell_hole_tex_cache: Texture2D = null


static var _rust_streak_tex_cache: Texture2D = null


static var _crack_streak_tex_cache: Texture2D = null


static func _crack_streak_tex() -> Texture2D:
	if _crack_streak_tex_cache == null:
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		grad.colors = PackedColorArray([
			Color(0.05, 0.05, 0.05, 0.0),
			Color(0.10, 0.10, 0.10, 0.7),
			Color(0.06, 0.06, 0.06, 0.0),
		])
		var tex := GradientTexture2D.new()
		tex.gradient = grad
		tex.width = 64
		tex.height = 64
		tex.fill = GradientTexture2D.FILL_LINEAR
		tex.fill_from = Vector2(0.5, 0.0)
		tex.fill_to = Vector2(0.5, 1.0)
		_crack_streak_tex_cache = tex
	return _crack_streak_tex_cache


static func _rust_streak_tex() -> Texture2D:
	if _rust_streak_tex_cache == null:
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		grad.colors = PackedColorArray([
			Color(0.34, 0.18, 0.08, 0.0),
			Color(0.40, 0.22, 0.10, 0.55),
			Color(0.30, 0.16, 0.07, 0.0),
		])
		var tex := GradientTexture2D.new()
		tex.gradient = grad
		tex.width = 64
		tex.height = 64
		tex.fill = GradientTexture2D.FILL_LINEAR
		tex.fill_from = Vector2(0.5, 0.0)
		tex.fill_to = Vector2(0.5, 1.0)
		_rust_streak_tex_cache = tex
	return _rust_streak_tex_cache


static func _shell_hole_tex() -> Texture2D:
	if _shell_hole_tex_cache == null:
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
		grad.colors = PackedColorArray([
			Color(0.05, 0.045, 0.04, 0.95),
			Color(0.08, 0.07, 0.06, 0.6),
			Color(0.1, 0.09, 0.08, 0.0),
		])
		var tex := GradientTexture2D.new()
		tex.gradient = grad
		tex.width = 64
		tex.height = 64
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		_shell_hole_tex_cache = tex
	return _shell_hole_tex_cache


static func _add_shell_hole(node: Node3D, pos: Vector3, size: float,
		tex: Texture2D) -> void:
	var q := QuadMesh.new()
	q.size = Vector2(size, size * 1.15)
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = Color(1.0, 1.0, 1.0)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	node.add_child(mi)


static func _add_wear_char(node: Node3D, pos: Vector3, size: float) -> void:
	var q := QuadMesh.new()
	q.size = Vector2(size, size * 0.7)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.06, 0.055, 0.05, 0.5)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	mi.rotation.x = -PI * 0.5
	node.add_child(mi)


static func _add_wear_rubble(node: Node3D, pos: Vector3,
		rng: RandomNumberGenerator, wear: float = 1.0) -> void:
	for i in range(10):
		var w := rng.randf_range(0.5, 1.8) * wear
		var d := rng.randf_range(0.5, 1.5) * wear
		var h := rng.randf_range(0.25, 0.9) * wear
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(w, h, d)
		mi.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.42, 0.24, 0.12) if i % 3 == 0 \
				else Color(0.34, 0.33, 0.29)
		mat.roughness = 0.9
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = pos + Vector3(rng.randf_range(-2.8, 2.8) * wear, h * 0.5,
				rng.randf_range(-2.8, 2.8) * wear)
		mi.rotation = Vector3(rng.randf_range(-0.4, 0.4),
				rng.randf_range(0.0, TAU), 0.0)
		node.add_child(mi)


static func _add_wear_rust(node: Node3D, pos: Vector3, size: Vector2,
		yaw: float, tex: Texture2D) -> void:
	var q := QuadMesh.new()
	q.size = size
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = Color(0.9, 0.85, 0.8)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	mi.rotation.y = yaw
	node.add_child(mi)


static func _build_hall_sites(root: Node3D, map_name: String) -> void:
	var site: Dictionary = HALL_SITES.get(map_name, {})
	if site.is_empty():
		return
	var asset_name := String(site.get("asset", "industrial_hall.glb"))
	var path := "res://Assets/frontline/" + asset_name
	if not ResourceLoader.exists(path):
		push_warning("[FrontlineTerrain] missing hero hall: " + path)
		return
	var packed := load(path) as PackedScene
	if packed == null:
		return
	var hall := packed.instantiate() as Node3D
	if hall == null:
		return
	var theme := String(site.get("theme", map_name))
	var center: Vector2 = site["center"]
	var scale_f: float = site["scale"]
	var sink: float = float(site.get("sink", 0.0))
	var gy := _height(map_name, center.x, center.y)
	# The floor slab is 0.70 m thick before scaling.  Put its finished surface
	# 2 cm above the levelled pad, with an optional extra sink/raise for ruins.
	var floor_top := gy + 0.02 - sink
	hall.name = "HeroHall_" + map_name
	hall.position = Vector3(center.x, floor_top - 0.70 * scale_f, center.y)
	hall.rotation.y = float(site["yaw"])
	hall.scale = Vector3.ONE * scale_f
	root.add_child(hall)
	_apply_hall_materials(hall, theme)

	# The authored glass sheet closes every window bay with a transparent
	# surface.  It never had collision, but it reads as a barrier; hide it so
	# the real openings can be seen (and flown through).
	for mesh_node in hall.find_children("*", "MeshInstance3D", true, false):
		var glass_mi := mesh_node as MeshInstance3D
		if glass_mi == null or glass_mi.mesh == null \
				or glass_mi.mesh.get_surface_count() == 0:
			continue
		var glass_mat := glass_mi.mesh.surface_get_material(0)
		var glass_key := glass_mat.resource_name.to_lower() if glass_mat != null else ""
		if glass_key == "hall_glass":
			glass_mi.visible = false

	# Collision: one trimesh per material mesh, skipping only glass and water.
	# Dark/moss roof and trim surfaces used to be skipped too, which left the
	# roof without a collider; every opaque surface must stop the drone.
	var body := StaticBody3D.new()
	body.name = "HallCollision_" + map_name
	body.collision_layer = 1
	body.collision_mask = 1
	hall.add_child(body)
	for mesh_node in hall.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh_node as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.visible:
			continue
		var src := mi.mesh.surface_get_material(0)
		var key := src.resource_name.to_lower() if src != null else ""
		if key in ["hall_glass", "hall_water"]:
			continue
		_add_mesh_collision(body, mi)

	# (The arched roof trimesh already has backface collision enabled via _add_mesh_collision,
	# matching the exact curved geometry and allowing close flight near the roof and through openings).

	# Flat interior deck.  The authored floor has holes and the terrain/road
	# poked through as green/brown patches; this slab gives the interior one
	# clean concrete surface under the spawn/barrel.
	var hall_len := 120.0
	var hall_hw := 27.0
	match map_name:
		"village":
			hall_len = 96.0
			hall_hw = 23.0
		"steppe":
			hall_len = 112.0
			hall_hw = 25.0
		"wetlands":
			hall_len = 104.0
			hall_hw = 24.0
	# Small mobile-only facade signs make otherwise similar hall silhouettes
	# navigable from FPV without moving collision, spawn, or authored geometry.
	if (OS.get_name() == "iOS" or OS.has_feature("mobile") \
			or OS.has_environment("MOBILE_UI")) \
			and not OS.has_environment("QA_NO_MOBILE_HALL_SIGNS"):
		_add_mobile_hall_wayfinding(hall, map_name, hall_hw,
				float(site.get("roof_height", 18.0)))
	var deck := MeshInstance3D.new()
	deck.name = "HallFloor_" + map_name
	var deck_mesh := PlaneMesh.new()
	deck_mesh.size = Vector2(hall_len, hall_hw * 2.0)
	deck.mesh = deck_mesh
	var deck_mat := _pbr("hall_floor_seamless", Color(0.72, 0.69, 0.62), 0.12)
	deck_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Keep the floor close to the reference exposure and stop the old
	# mirror-sharp tiling from drawing dark plank-like bands down the nave.
	deck_mat.normal_scale = 0.75
	deck_mat.roughness = 0.62
	deck.material_override = deck_mat
	deck.position = Vector3(center.x, floor_top + 0.08, center.y)
	deck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(deck)

	# Render both sides of the hall shell.  The authored roof/walls are single
	# sided; from an inverted FPV view the backfaces vanished and the player saw
	# the sky through the roof.
	for mesh_node in hall.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh_node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			var mat := mi.get_surface_override_material(s) as StandardMaterial3D
			if mat == null:
				mat = mi.mesh.surface_get_material(s) as StandardMaterial3D
			if mat != null and mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	_add_hall_lighting(root, hall, site, map_name, floor_top)
	_add_hall_foliage(root, hall, site, map_name)
	_add_hall_props(root, hall, site, map_name)


static func _add_hall_lighting(root: Node3D, hall: Node3D, site: Dictionary,
		map_name: String, floor_y: float) -> void:
	if OS.has_environment("QA_NO_HALL_LIGHTS"):
		return
	var center: Vector2 = site["center"]
	var half: Vector2 = site["half"]
	var lights := Node3D.new()
	lights.name = "HallLights_" + map_name
	root.add_child(lights)
	var warm := Color(1.0, 0.83, 0.60)
	if map_name == "village":
		warm = Color(1.0, 0.78, 0.50)
	elif map_name == "wetlands":
		warm = Color(0.92, 0.88, 0.74)
	var qa_no_spots := OS.has_environment("QA_NO_HALL_SPOTS")
	var qa_no_spot_shadow := OS.has_environment("QA_NO_HALL_SPOT_SHADOW")
	var made := 0
	var markers := hall.find_children("skylight_*", "Node3D", true, false)
	var stride := maxi(1, int(ceil(float(markers.size()) / 9.0)))
	for i in range(0, markers.size(), stride):
		if made >= 9 or qa_no_spots:
			break
		var marker := markers[i] as Node3D
		if marker == null:
			continue
		var p := marker.global_position
		if p.y < floor_y + 4.0:
			continue
		var target := Vector3(p.x + 2.4, floor_y, p.z + 1.2)
		var spot := SpotLight3D.new()
		spot.position = p
		spot.spot_range = 58.0
		spot.spot_angle = 22.0
		spot.spot_attenuation = 1.3
		spot.light_energy = 4.2
		spot.light_color = warm
		spot.light_volumetric_fog_energy = 4.0
		spot.shadow_enabled = made < 3 and not qa_no_spot_shadow
		spot.shadow_bias = 0.035
		lights.add_child(spot)
		spot.look_at(target, Vector3.UP)
		made += 1
	# Fallback for the older hall asset: five shafts down the nave.
	if made == 0 and not qa_no_spots:
		for xoff in [-half.x * 0.42, -half.x * 0.20, 0.0,
				half.x * 0.20, half.x * 0.42]:
			var p := Vector3(center.x + xoff, floor_y + 18.5, center.y)
			var target := Vector3(p.x + 2.0, floor_y, p.z + 1.0)
			var spot := SpotLight3D.new()
			spot.position = p
			spot.spot_range = 58.0
			spot.spot_angle = 22.0
			spot.light_energy = 4.0
			spot.light_color = warm
			spot.light_volumetric_fog_energy = 4.0
			spot.shadow_enabled = made < 3
			lights.add_child(spot)
			spot.look_at(target, Vector3.UP)
			made += 1

	# Guaranteed hero shafts in the first half of the nave.  The marker pass
	# above follows the authored skylights; this pass puts dramatic, visible
	# cones exactly where the spawn camera looks, independent of the marker
	# order.  It is the difference between "a warehouse" and the reference.
	var roof_h := float(site.get("roof_height", 18.0))
	for lx in [-half.x * 0.35, half.x * 0.12]:
		for lz in [-half.y * 0.24, half.y * 0.24]:
			var src := hall.to_global(Vector3(lx, roof_h, lz))
			var dst := hall.to_global(Vector3(lx + 7.0, 1.0, lz + 4.0))
			var shaft := SpotLight3D.new()
			shaft.position = src
			shaft.spot_range = 62.0
			shaft.spot_angle = 19.0
			shaft.spot_attenuation = 1.25
			shaft.light_energy = 6.0
			shaft.light_color = warm
			shaft.light_volumetric_fog_energy = 4.0
			shaft.shadow_enabled = made < 5 and not qa_no_spot_shadow
			shaft.shadow_bias = 0.03
			lights.add_child(shaft)
			shaft.look_at(dst, Vector3.UP)
			if qa_no_spots:
				continue
			var pool := OmniLight3D.new()
			pool.position = dst + Vector3.UP * 1.8
			pool.omni_range = 18.0
			pool.light_energy = 1.1
			pool.light_color = warm
			pool.shadow_enabled = false
			lights.add_child(pool)
			made += 1
	# One unmistakable central shaft: the reference's hero beam.
	var hero_x := half.x * 0.44
	var hero_src := hall.to_global(Vector3(hero_x, roof_h, 0.0))
	var hero_dst := hall.to_global(Vector3(hero_x + 8.0, 1.0, 2.0))
	var hero := SpotLight3D.new()
	hero.position = hero_src
	hero.spot_range = 64.0
	hero.spot_angle = 18.0
	hero.spot_attenuation = 1.2
	hero.light_energy = 6.0
	hero.light_color = warm
	hero.light_volumetric_fog_energy = 4.0
	hero.shadow_enabled = not qa_no_spot_shadow
	hero.shadow_bias = 0.03
	lights.add_child(hero)
	hero.look_at(hero_dst, Vector3.UP)
	# The old solid god-ray cylinder is intentionally removed: it read as a
	# white pillar hanging in the nave and the user asked to take it out.
	# The spotlights still carve light pools on the floor without a visible beam.

	# Local haze: the reference's depth comes from layered air, not just fog.
	if not OS.has_environment("QA_NO_HALL_FOG"):
		var fog := FogVolume.new()
		fog.name = "HallFog"
		fog.position = Vector3(center.x, floor_y + 8.5, center.y)
		fog.size = Vector3(half.x * 2.0 - 8.0, 19.0, half.y * 2.0 - 6.0)
		var fog_mat := FogMaterial.new()
		fog_mat.density = 0.032 if map_name != "wetlands" else 0.042
		fog_mat.albedo = Color(0.80, 0.82, 0.84)
		fog_mat.edge_fade = 0.78
		fog_mat.height_falloff = 0.18
		fog.material = fog_mat
		lights.add_child(fog)
		var low_fog := FogVolume.new()
		low_fog.name = "HallFloorHaze"
		low_fog.position = Vector3(center.x, floor_y + 1.4, center.y)
		low_fog.size = Vector3(half.x * 2.0 - 12.0, 3.2, half.y * 2.0 - 8.0)
		var low_mat := FogMaterial.new()
		low_mat.density = 0.016
		low_mat.albedo = Color(0.78, 0.80, 0.80)
		low_mat.edge_fade = 0.88
		low_fog.material = low_mat
		lights.add_child(low_fog)

	# Dust motes in the shafts.
	if OS.has_environment("QA_NO_HALL_DUST"):
		return
	var dust := GPUParticles3D.new()
	dust.name = "HallDust"
	dust.position = Vector3(center.x, floor_y + 7.0, center.y)
	dust.amount = 700
	dust.lifetime = 14.0
	dust.preprocess = 8.0
	dust.visibility_aabb = AABB(Vector3(-half.x, -8.0, -half.y),
			Vector3(half.x * 2.0, 18.0, half.y * 2.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(half.x * 0.82, 7.0, half.y * 0.75)
	pm.direction = Vector3(0.22, 0.05, 0.12)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.02
	pm.initial_velocity_max = 0.18
	pm.gravity = Vector3(0.0, -0.012, 0.0)
	pm.scale_min = 0.4
	pm.scale_max = 1.4
	pm.color = Color(1.0, 0.9, 0.72, 0.55)
	dust.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.055, 0.055)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dm.albedo_color = Color(1.0, 0.9, 0.72, 0.5)
	dm.emission_enabled = true
	dm.emission = Color(1.0, 0.86, 0.62)
	dm.emission_energy_multiplier = 1.7
	dm.vertex_color_use_as_albedo = true
	quad.material = dm
	dust.draw_pass_1 = quad
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lights.add_child(dust)

	# Failing sodium / mercury fixtures authored in Blender.
	for lamp_node in hall.find_children("lamp_*", "Node3D", true, false):
		var lamp := lamp_node as Node3D
		if lamp == null:
			continue
		var omni := OmniLight3D.new()
		omni.position = lamp.global_position
		omni.omni_range = 18.0
		omni.light_energy = 0.9
		omni.light_color = Color(1.0, 0.66, 0.34)
		omni.light_volumetric_fog_energy = 0.4
		omni.shadow_enabled = false
		lights.add_child(omni)
		var bulb_mesh := SphereMesh.new()
		bulb_mesh.radius = 0.18
		bulb_mesh.height = 0.36
		var bulb := MeshInstance3D.new()
		bulb.mesh = bulb_mesh
		var bulb_mat := _mat(Color(1.0, 0.62, 0.30), 0.3)
		bulb_mat.emission_enabled = true
		bulb_mat.emission = Color(1.0, 0.55, 0.22)
		bulb_mat.emission_energy_multiplier = 3.0
		bulb.material_override = bulb_mat
		bulb.position = lamp.global_position
		bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lights.add_child(bulb)

	# Cool fills at the doors keep the near catwalk silhouettes readable.
	for xoff in [-half.x * 0.72, half.x * 0.72]:
		var fill := OmniLight3D.new()
		fill.position = Vector3(center.x + xoff, floor_y + 4.8, center.y)
		fill.omni_range = 34.0
		fill.light_energy = 0.5
		fill.light_color = Color(0.56, 0.70, 0.88)
		fill.shadow_enabled = false
		lights.add_child(fill)


static func _add_god_ray(parent: Node3D, from: Vector3, to: Vector3,
		color: Color, strength: float = 0.20) -> void:
	if OS.has_environment("QA_NO_GODRAY"):
		return
	var direction := to - from
	var dist := direction.length()
	if dist < 2.0:
		return
	var holder := Node3D.new()
	holder.name = "GodRay"
	holder.position = (from + to) * 0.5
	parent.add_child(holder)
	holder.look_at(to, Vector3.UP)
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.58
	mesh.bottom_radius = 2.4
	mesh.height = dist
	mesh.radial_segments = 16
	mesh.rings = 1
	mesh.cap_top = false
	mesh.cap_bottom = false
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.rotation_degrees.x = -90.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = GOD_RAY_SHADER
	mat.set_shader_parameter("ray_color", Color(1.0, 0.86, 0.66))
	mat.set_shader_parameter("intensity", strength)
	mat.set_shader_parameter("edge_softness", 0.64)
	mat.set_shader_parameter("dust_strength", 0.32)
	mi.material_override = mat
	holder.add_child(mi)


static func _add_hall_foliage(root: Node3D, hall: Node3D, site: Dictionary,
		map_name: String) -> void:
	var half: Vector2 = site["half"]
	var spawn: Vector2 = site.get("spawn", site["center"])
	var center: Vector2 = site["center"]
	var local_spawn := spawn - center
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(map_name) * 131 + 41
	var x_span := half.x - 5.0
	var z_span := half.y - 4.0
	# The wetlands floor is deliberately below the water table, so its grass
	# must stand on the shallow bed instead of being hidden by the water plane.
	var floor_local := 0.705 if map_name != "wetlands" else 0.90
	var base := Color(0.115, 0.150, 0.050)
	var tip := Color(0.330, 0.405, 0.150)
	if map_name == "village":
		base = Color(0.095, 0.155, 0.045)
		tip = Color(0.290, 0.385, 0.145)
	elif map_name == "steppe":
		base = Color(0.165, 0.155, 0.065)
		tip = Color(0.420, 0.380, 0.155)
	elif map_name == "wetlands":
		base = Color(0.060, 0.110, 0.034)
		tip = Color(0.180, 0.285, 0.100)
	var tuft_mesh: Mesh = VEGETATION.grass_mesh()
	if tuft_mesh == null:
		tuft_mesh = FOLIAGE.create_grass_mesh(14)
	var mat := ShaderMaterial.new()
	mat.shader = GRASS_SHADER
	mat.set_shader_parameter("grass_base_color", Vector3(base.r, base.g, base.b))
	mat.set_shader_parameter("grass_tip_color", Vector3(tip.r, tip.g, tip.b))
	mat.set_shader_parameter("wind_strength", 0.14)
	mat.set_shader_parameter("wind_speed", 0.75)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = tuft_mesh
	var xforms: Array[Transform3D] = []
	for i in range(1900):
		var lx := rng.randf_range(-x_span, x_span)
		var lz := rng.randf_range(-z_span, z_span)
		if absf(lx - local_spawn.x) < 9.0 and absf(lz - local_spawn.y) < 4.8:
			continue
		var s := rng.randf_range(0.8, 1.85)
		var yaw := rng.randf() * TAU
		var basis := Basis(Vector3.UP, yaw).scaled(
				Vector3(s, rng.randf_range(0.9, 1.6), s))
		var p := hall.to_global(Vector3(lx, floor_local, lz))
		xforms.append(Transform3D(basis, p))
	# Guaranteed foreground overgrowth on both sides of the spawn lane.
	for side in [-1, 1]:
		for i in range(16):
			var lx := local_spawn.x - rng.randf_range(8.0, 22.0)
			var lz: float = float(side) * rng.randf_range(5.8, 13.0)
			var s := rng.randf_range(1.0, 1.9)
			var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(
					Vector3(s, rng.randf_range(1.0, 1.7), s))
			xforms.append(Transform3D(b, hall.to_global(
					Vector3(lx, floor_local, lz))))
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var grass := MultiMeshInstance3D.new()
	grass.name = "HallGrass_" + map_name
	grass.multimesh = mm
	grass.material_override = mat
	grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	grass.visibility_range_end = 85.0
	grass.visibility_range_end_margin = 12.0
	root.add_child(grass)

	if map_name == "wetlands":
		# Tall emergent reeds rising out of the shallow flood.  The marsh
		# scatter outside is too sparse to read through the hall windows.
		var reed_mat := ShaderMaterial.new()
		reed_mat.shader = GRASS_SHADER
		reed_mat.set_shader_parameter("grass_base_color", Vector3(0.035, 0.070, 0.020))
		reed_mat.set_shader_parameter("grass_tip_color", Vector3(0.120, 0.200, 0.070))
		reed_mat.set_shader_parameter("wind_strength", 0.08)
		reed_mat.set_shader_parameter("wind_speed", 0.8)
		var reed_mm := MultiMesh.new()
		reed_mm.transform_format = MultiMesh.TRANSFORM_3D
		reed_mm.mesh = VEGETATION.grass_mesh() if VEGETATION.grass_mesh() != null \
				else FOLIAGE.create_grass_mesh(6, 2.8)
		var reed_xf: Array[Transform3D] = []
		for i in range(150):
			var lx := rng.randf_range(-x_span, x_span)
			var lz := rng.randf_range(-z_span, z_span)
			if absf(lx - local_spawn.x) < 12.0 and absf(lz - local_spawn.y) < 6.0:
				continue
			var s := rng.randf_range(0.9, 1.5)
			var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(
					Vector3(s, rng.randf_range(3.0, 6.5), s))
			reed_xf.append(Transform3D(b, hall.to_global(
					Vector3(lx, 0.88, lz))))
		reed_mm.instance_count = reed_xf.size()
		for i in reed_xf.size():
			reed_mm.set_instance_transform(i, reed_xf[i])
		var reeds := MultiMeshInstance3D.new()
		reeds.name = "HallReeds"
		reeds.multimesh = reed_mm
		reeds.material_override = reed_mat
		reeds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(reeds)

	# A deliberate rubble island in the near nave.  The authored Blender debris
	# frames the edges, but the reference needs a broken, layered middle ground
	# between the spawn lane and the collapsed bay.
	var rubble_mat := _pbr("hall_floor", Color(0.78, 0.78, 0.80), 0.22)
	for i in range(18):
		var lx := local_spawn.x - rng.randf_range(16.0, 27.0)
		var lz := rng.randf_range(-5.2, 5.2)
		var sx := rng.randf_range(0.8, 3.2)
		var sy := rng.randf_range(0.25, 1.05)
		var sz := rng.randf_range(0.8, 2.6)
		var chunk := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(sx, sy, sz)
		chunk.mesh = bm
		chunk.material_override = rubble_mat
		chunk.position = hall.to_global(Vector3(lx, 0.72 + sy * 0.5, lz))
		chunk.rotation = Vector3(rng.randf_range(-0.5, 0.5),
				rng.randf_range(0, TAU), rng.randf_range(-0.5, 0.5))
		chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(chunk)
	for i in range(2):
		var beam := MeshInstance3D.new()
		var bm2 := BoxMesh.new()
		bm2.size = Vector3(0.35, 0.35, rng.randf_range(6.0, 9.0))
		beam.mesh = bm2
		beam.material_override = _pbr("hall_rust", Color(0.9, 0.78, 0.68), 0.4)
		beam.position = hall.to_global(Vector3(
				local_spawn.x - 19.0 - i * 3.0, 1.0, -2.5 + i * 5.0))
		beam.rotation = Vector3(rng.randf_range(-0.4, 0.4),
				rng.randf_range(-0.8, 0.8), rng.randf_range(-0.5, 0.5))
		root.add_child(beam)

	# Moss decals on the wet concrete.  The 2K Poly Haven moss albedo is reused
	# as a projected stain, so it follows broken slabs and walls without more
	# geometry.
	var moss_path := "res://Assets/frontline/industrial_hall/concrete_moss_diff.jpg"
	if ResourceLoader.exists(moss_path):
		var moss_tex := load(moss_path) as Texture2D
		if moss_tex != null:
			for i in range(42):
				var lx := rng.randf_range(-x_span, x_span)
				var lz := rng.randf_range(-z_span, z_span)
				if absf(lx - local_spawn.x) < 8.0 and absf(lz - local_spawn.y) < 4.0:
					continue
				var r := rng.randf_range(1.2, 3.8)
				var decal := Decal.new()
				decal.name = "HallMoss"
				decal.texture_albedo = moss_tex
				decal.size = Vector3(r, 3.2, r)
				decal.position = hall.to_global(Vector3(lx, 1.65, lz))
				decal.albedo_mix = 0.74
				decal.modulate = Color(0.56, 0.76, 0.42, 1.0)
				decal.upper_fade = 0.55
				decal.lower_fade = 0.05
				decal.normal_fade = 0.35
				decal.cull_mask = 1
				root.add_child(decal)
			# A few guaranteed patches framing the spawn doorway.
			for side in [-1, 1]:
				for i in range(4):
					var lx := local_spawn.x - rng.randf_range(9.0, 18.0)
					var lz: float = float(side) * rng.randf_range(6.0, 11.0)
					var r := rng.randf_range(2.0, 4.2)
					var decal2 := Decal.new()
					decal2.name = "HallSpawnMoss"
					decal2.texture_albedo = moss_tex
					decal2.size = Vector3(r, 3.2, r)
					decal2.position = hall.to_global(Vector3(lx, 1.65, lz))
					decal2.albedo_mix = 0.70
					decal2.modulate = Color(0.58, 0.78, 0.44, 1.0)
					decal2.upper_fade = 0.55
					decal2.lower_fade = 0.05
					decal2.normal_fade = 0.35
					decal2.cull_mask = 1
					root.add_child(decal2)
			# One broad moss island in the centre of the near floor.
			for i in range(3):
				var mx := local_spawn.x - rng.randf_range(17.0, 23.0)
				var mz := (float(i) - 1.0) * 4.0
				var mr := rng.randf_range(3.2, 5.4)
				var md := Decal.new()
				md.texture_albedo = moss_tex
				md.size = Vector3(mr, 3.6, mr)
				md.position = hall.to_global(Vector3(mx, 1.75, mz))
				md.albedo_mix = 0.72
				md.modulate = Color(0.60, 0.80, 0.46, 1.0)
				md.upper_fade = 0.55
				md.lower_fade = 0.02
				md.normal_fade = 0.35
				md.cull_mask = 1
				root.add_child(md)

	# A handful of young trees have rooted in the debris.  Reuse the authored
	# wind-tree meshes at sapling scale instead of a second vegetation library.
	var trees := VEGETATION.trees()
	if not trees.is_empty():
		var spots := [
			Vector2(-half.x * 0.42, -half.y * 0.48),
			Vector2(half.x * 0.34, half.y * 0.46),
			Vector2(-half.x * 0.16, half.y * 0.52),
			Vector2(half.x * 0.46, -half.y * 0.40),
		]
		for i in spots.size():
			var local: Vector2 = spots[i]
			var variant: Dictionary = trees[i % trees.size()]
			var tree := Node3D.new()
			tree.name = "HallSapling"
			var trunk := MeshInstance3D.new()
			trunk.mesh = variant["trunk"]
			tree.add_child(trunk)
			var leaves := MeshInstance3D.new()
			leaves.mesh = variant["leaves"]
			tree.add_child(leaves)
			var s := rng.randf_range(0.26, 0.42)
			tree.scale = Vector3.ONE * s
			tree.position = hall.to_global(Vector3(local.x, floor_local, local.y))
			tree.rotation.y = rng.randf() * TAU
			root.add_child(tree)

	# Low scrub around the columns and rubble: a single MultiMesh gives the
	# concrete floor the "nature is taking it back" layer without hundreds of
	# draw calls.
	var bush_mesh: Mesh = FOLIAGE.make_canopy_mesh(5, 3, 0.34, 1.0, 1.6)
	var bush_mat := _mat(Color(0.055, 0.095, 0.028), 1.0)
	var bush_mm := MultiMesh.new()
	bush_mm.transform_format = MultiMesh.TRANSFORM_3D
	bush_mm.mesh = bush_mesh
	var bush_xf: Array[Transform3D] = []
	for i in range(24):
		var lx := rng.randf_range(-x_span, x_span)
		var lz := rng.randf_range(-z_span, z_span)
		if absf(lx - local_spawn.x) < 10.0 and absf(lz - local_spawn.y) < 5.0:
			continue
		var s := rng.randf_range(0.22, 0.62)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(
				Vector3(s, s * rng.randf_range(0.7, 1.2), s))
		bush_xf.append(Transform3D(b, hall.to_global(
				Vector3(lx, floor_local + 0.25, lz))))
	bush_mm.instance_count = bush_xf.size()
	for i in bush_xf.size():
		bush_mm.set_instance_transform(i, bush_xf[i])
	var bushes := MultiMeshInstance3D.new()
	bushes.name = "HallScrub_" + map_name
	bushes.multimesh = bush_mm
	bushes.material_override = bush_mat
	bushes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(bushes)


static func _add_hall_props(root: Node3D, hall: Node3D, site: Dictionary,
		map_name: String) -> void:
	var sets := {
		"industrial": [
			["prop_car_wreck", Vector2(18.0, -18.0), 0.7, 1.0],
			["prop_generator", Vector2(29.0, 14.0), 0.2, 1.0],
			["prop_pallet", Vector2(22.0, 17.0), 0.4, 1.0],
			["prop_oil_drum", Vector2(13.0, 19.0), 0.0, 1.0],
			["prop_tires", Vector2(31.0, -21.0), 0.3, 1.0],
			["prop_crate", Vector2(16.0, 15.0), 0.8, 1.0],
			["prop_barrier", Vector2(-28.0, 20.0), 1.4, 1.0],
			["prop_barrel", Vector2(43.0, -7.5), 0.2, 1.0],
			["prop_crate", Vector2(39.0, 7.0), 0.7, 1.0],
			["prop_oil_drum", Vector2(46.0, 9.0), 1.2, 1.0],
			["prop_car_wreck", Vector2(40.0, -14.0), 0.8, 1.2],
			["prop_fuel_tank", Vector2(44.0, 14.0), 0.3, 1.0],
			["prop_generator", Vector2(34.0, 13.0), 0.2, 1.0],
		],
		"village": [
			["prop_crate", Vector2(22.0, 15.0), 0.5, 1.0],
			["prop_barrel", Vector2(28.0, 17.0), 1.1, 1.0],
			["prop_tires", Vector2(12.0, -17.0), 0.3, 1.0],
			["prop_hay", Vector2(-24.0, 16.0), 0.0, 1.0],
			["prop_logs", Vector2(30.0, -18.0), 0.8, 1.0],
			["prop_pallet", Vector2(-15.0, -18.0), 0.2, 1.0],
			["prop_barrel", Vector2(36.0, -7.0), 1.1, 1.0],
			["prop_crate", Vector2(33.0, 8.0), 0.5, 1.0],
			["prop_tires", Vector2(40.0, 10.0), 0.3, 1.0],
			["prop_car_wreck", Vector2(37.0, 14.0), 0.6, 1.0],
			["prop_hay", Vector2(35.0, -14.0), 0.0, 1.0],
			["prop_logs", Vector2(30.0, 11.0), 0.8, 1.0],
		],
		"steppe": [
			["prop_barrel", Vector2(24.0, 17.0), 1.1, 1.0],
			["prop_crate", Vector2(19.0, 18.0), 0.5, 1.0],
			["prop_tires", Vector2(31.0, -18.0), 0.3, 1.0],
			["prop_generator", Vector2(-14.0, -18.0), 0.2, 1.0],
			["prop_oil_drum", Vector2(8.0, 18.0), 0.0, 1.0],
			["prop_barrel", Vector2(41.0, -8.0), 1.0, 1.0],
			["prop_crate", Vector2(38.0, 8.0), 0.4, 1.0],
			["prop_generator", Vector2(35.0, 14.0), 0.2, 1.0],
			["prop_crate", Vector2(42.0, 13.0), 0.6, 1.0],
		],
		"wetlands": [
			["prop_barrel", Vector2(22.0, 16.0), 1.1, 1.0],
			["prop_crate", Vector2(28.0, 18.0), 0.5, 1.0],
			["prop_pallet", Vector2(15.0, -17.0), 0.2, 1.0],
			["prop_tires", Vector2(31.0, -19.0), 0.3, 1.0],
			["prop_oil_drum", Vector2(-13.0, -18.0), 0.0, 1.0],
			["prop_barrel", Vector2(37.0, -8.0), 1.0, 1.0],
			["prop_crate", Vector2(34.0, 8.0), 0.4, 1.0],
			["prop_tires", Vector2(42.0, 10.0), 0.3, 1.0],
			["prop_oil_drum", Vector2(34.0, -13.0), 0.0, 1.0],
		],
	}
	for entry in sets.get(map_name, []):
		var name := String(entry[0])
		var local: Vector2 = entry[1]
		var pos := hall.to_global(Vector3(local.x, 0.70, local.y))
		ASSETS.spawn_prop(root, name, pos, float(entry[2]) + hall.rotation.y,
				float(entry[3]))


## A single contextual sign on the existing hall, rather than a new obstacle.
## It is attached to the facade and uses one background quad and one text draw.
static func _add_mobile_hall_wayfinding(hall: Node3D, map_name: String,
		half_width: float, roof_height: float) -> void:
	if hall == null or hall.get_node_or_null("MobileHallWayfinding") != null:
		return
	var names := {
		"steppe": "АГРОСКЛАД",
		"village": "СІЛЬСЬКИЙ СКЛАД",
		"industrial": "ЦЕХ 01",
		"wetlands": "ПРИЧАЛ",
	}
	if not names.has(map_name):
		return
	var sign := Node3D.new()
	sign.name = "MobileHallWayfinding"
	sign.position = Vector3(0.0, clampf(roof_height * 0.62, 7.0, 12.0),
			half_width + 3.1)
	hall.add_child(sign)
	var panel := MeshInstance3D.new()
	panel.name = "SignPanel"
	var quad := QuadMesh.new()
	quad.size = Vector2(18.0, 2.8)
	panel.mesh = quad
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.12, 0.16, 0.13)
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	panel.material_override = material
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	panel.visibility_range_end = 300.0
	sign.add_child(panel)
	var label := Label3D.new()
	label.name = "SignText"
	label.text = String(names[map_name])
	label.font_size = 100
	label.pixel_size = 0.014
	label.modulate = Color(0.87, 0.85, 0.72)
	label.outline_size = 3
	label.position.z = 0.025
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.visibility_range_end = 300.0
	sign.add_child(label)


static func _apply_hall_materials(node: Node, theme: String = "industrial") -> void:
	var meshes: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		meshes.append(node as MeshInstance3D)
	for child in node.find_children("*", "MeshInstance3D", true, false):
		meshes.append(child as MeshInstance3D)
	var concrete_tint := Color(0.82, 0.84, 0.86)
	var floor_tint := Color(0.80, 0.82, 0.85)
	var moss_tint := Color(0.52, 0.58, 0.40)
	var rust_tint := Color(0.68, 0.52, 0.40)
	var metal_tint := Color(0.56, 0.58, 0.60)
	var brick_tint := Color(0.90, 0.74, 0.64)
	var wood_tint := Color(0.80, 0.66, 0.50)
	match theme:
		"village":
			concrete_tint = Color(0.88, 0.84, 0.76)
			floor_tint = Color(0.82, 0.79, 0.72)
			brick_tint = Color(0.92, 0.70, 0.58)
			wood_tint = Color(0.78, 0.60, 0.42)
		"steppe":
			concrete_tint = Color(0.88, 0.87, 0.80)
			floor_tint = Color(0.84, 0.83, 0.76)
			moss_tint = Color(0.58, 0.56, 0.36)
		"wetlands":
			concrete_tint = Color(0.72, 0.78, 0.74)
			floor_tint = Color(0.66, 0.72, 0.68)
			moss_tint = Color(0.40, 0.52, 0.32)
			rust_tint = Color(0.84, 0.70, 0.56)
	for mi in meshes:
		if mi.mesh == null:
			continue
		var key := ""
		for s in range(mi.mesh.get_surface_count()):
			var source := mi.mesh.surface_get_material(s)
			key = source.resource_name.to_lower() if source != null else ""
			var mat: Material
			match key:
				"hall_concrete", "concrete_slab_wall":
					mat = _pbr("hall_concrete", concrete_tint, 0.26)
				"hall_floor", "concrete_floor_damaged_01":
					mat = _pbr("hall_floor", floor_tint, 0.20)
				"hall_moss", "concrete_moss":
					mat = _pbr("hall_moss", moss_tint, 0.40)
				"hall_rust", "rusty_metal_02":
					mat = _pbr("hall_rust", rust_tint, 0.34)
				"hall_metal", "metal_plate_02":
					mat = _pbr("hall_metal", metal_tint, 0.28)
				"hall_brick":
					mat = _pbr("brick", brick_tint, 0.22)
				"hall_wood":
					mat = _pbr("wood", wood_tint, 0.28)
				"hall_paint":
					mat = _pbr("steel", Color(0.38, 0.48, 0.42), 0.16)
				"hall_gravel":
					mat = _pbr("dirt", Color(0.62, 0.58, 0.48), 0.26)
				"hall_glass":
					mat = _mat(Color(0.72, 0.80, 0.86, 0.38), 0.06, 0.15)
					(mat as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					(mat as StandardMaterial3D).emission_enabled = true
					(mat as StandardMaterial3D).emission = Color(0.78, 0.86, 0.94)
					(mat as StandardMaterial3D).emission_energy_multiplier = 0.55
				"hall_dark":
					mat = _pbr("hall_rust", Color(0.28, 0.30, 0.32), 0.28)
				"hall_water":
					mat = _mat(Color(0.05, 0.06, 0.055), 0.04, 0.12)
				_:
					mat = _pbr("concrete", Color(0.68, 0.67, 0.64), 0.24)
			mi.set_surface_override_material(s, mat)
		var cast := GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if key in ["hall_glass", "hall_water", "hall_moss"]:
			cast = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.cast_shadow = cast


static func _build_wetlands(root: Node3D, map_name: String) -> void:
	var concrete := _pbr("concrete", Color(0.82, 0.80, 0.74), 0.18)
	var rust := _pbr("steel", Color(0.48, 0.27, 0.16), 0.22)
	var wood := _pbr("wood", Color(0.52, 0.50, 0.46), 0.46)
	var dark := _mat(Color(0.10, 0.10, 0.09), 1.0)
	var wl := water_level(map_name)

	# Dynamic Combat River Patrol Boat cruising the wetlands channel (zero FPS cost)
	var wet_boat_wps: Array[Vector3] = [
		Vector3(-140.0, wl, 45.0),
		Vector3(-40.0, wl, 85.0),
		Vector3(60.0, wl, 70.0),
		Vector3(150.0, wl, 35.0),
		Vector3(60.0, wl, 15.0),
		Vector3(-40.0, wl, 20.0),
	]
	var wet_patrol_boat := MOVING_PATROL_BOAT.create_patrol_boat(wet_boat_wps, wl, 0.0)
	root.add_child(wet_patrol_boat)

	# Timber boardwalk leads straight into the flooded pump-station door: the
	# first frame is a wet approach, then the dark nave of the hall.
	for i in range(13):
		var px := 6.0 + float(i) * 2.1
		var py := maxf(_height(map_name, px, 60.0), wl) + 0.28
		_add_box(root, Vector3(px, py, 60.0), Vector3(2.1, 0.14, 3.0), wood, 0.0, true)
		if i % 2 == 0:
			for sz in [-1.4, 1.4]:
				_add_cylinder(root, Vector3(px, py - 0.55, 60.0 + sz), 0.09, 1.3,
						wood, 0.0, false)

	# Sunken barges.
	for p in [Vector2(-120, -40), Vector2(180, -140), Vector2(250, 58)]:
		var y := _height(map_name, p.x, p.y)
		_add_box(root, Vector3(p.x, maxf(y, wl) + 0.7, p.y), Vector3(18.0, 2.6, 6.0), rust, 0.25, true)
		_add_box(root, Vector3(p.x, maxf(y, wl) + 2.2, p.y + 1.0), Vector3(6.0, 2.2, 3.4),
				concrete, 0.25, false)
		_add_cylinder(root, Vector3(p.x + 6.0, maxf(y, wl) + 2.4, p.y), 0.5, 4.0, dark, 0.0, false)
	# Half-sunken barge in the channel off the hall's west approach, and a
	# knocked-out APC on the bank: two strong mid-ground silhouettes.
	_add_box(root, Vector3(18.0, wl + 0.65, 30.0), Vector3(16.0, 2.4, 5.5), rust, 0.35, true)
	_add_box(root, Vector3(18.0, wl + 2.0, 30.8), Vector3(5.0, 2.0, 3.0), concrete, 0.35, false)
	_add_cylinder(root, Vector3(24.0, wl + 2.2, 30.0), 0.45, 3.6, dark, 0.0, false)
	ASSETS.spawn_prop(root, "prop_apc",
			Vector3(16.0, _height(map_name, 16.0, 70.0), 70.0), 1.15, 1.0)

	# The blown bridge and concrete pillboxes are authored GLB assets; see
	# _build_blender_landmarks().
	# Reeds: dense clumps in the marsh.  A clump mesh (six blades) reads as a
	# reed bed at 10-100 m, where single 6 cm boxes looked like scattered
	# sticks.  They use the grass wind shader so the marsh breathes with the
	# same gust as the fields while staying rooted in the water.
	var reed_mesh := FOLIAGE.create_grass_mesh(6, 2.8)
	var reed_mat := ShaderMaterial.new()
	reed_mat.shader = GRASS_SHADER
	reed_mat.set_shader_parameter("grass_base_color", Vector3(0.042, 0.062, 0.024))
	reed_mat.set_shader_parameter("grass_tip_color", Vector3(0.110, 0.140, 0.058))
	reed_mat.set_shader_parameter("backlight_strength", 0.10)
	reed_mat.set_shader_parameter("wind_strength", 0.055)
	reed_mat.set_shader_parameter("wind_speed", 1.15)
	var rng := RandomNumberGenerator.new()
	rng.seed = 771
	var transforms: Array = []
	var colors: Array = []
	# Reeds must stand in the emergent band, not 2 m under the surface: a broad
	# underwater band spent most instances behind the water shader and left a
	# handful of yellow stalks on screen.  Three clumps per seed make a bed
	# 2-4 m wide while keeping the instance count inside the 120 FPS budget.
	for i in range(4800):
		var p := Vector2(rng.randf_range(-275.0, 275.0), rng.randf_range(-275.0, 275.0))
		var h := _height(map_name, p.x, p.y)
		if h > wl + 0.40 or h < wl - 0.55:
			continue
		# Leave the flooded nave and the entry corridor readable.
		if _hall_clear_zone(map_name, p.x, p.y) and absf(p.y - 60.0) < 9.5:
			continue
		if p.distance_to(Vector2(38.0, 60.0)) < 10.0:
			continue
		var clumps := rng.randi_range(2, 4)
		for k in range(clumps):
			var q := p + Vector2(rng.randf_range(-1.3, 1.3), rng.randf_range(-1.3, 1.3))
			var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(
					Vector3(rng.randf_range(0.85, 1.35), rng.randf_range(6.0, 9.5),
							rng.randf_range(0.85, 1.35)))
			transforms.append(Transform3D(basis, Vector3(q.x, h, q.y)))
			var warm := rng.randf_range(0.86, 1.02)
			colors.append(Color(warm * 0.94, warm, warm * rng.randf_range(0.80, 0.94)))
	# Reed bed framing the spawn boardwalk: dense clumps in the shallow band
	# directly in front of the camera, where the procedural scatter is thin.
	for i in range(260):
		var q := Vector2(rng.randf_range(20.0, 44.0), rng.randf_range(38.0, 52.0))
		if absf(q.x - 30.0) < 1.6 and q.y > 46.0:
			continue
		var rb := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(
				Vector3(rng.randf_range(0.85, 1.35), rng.randf_range(6.0, 9.5),
						rng.randf_range(0.85, 1.35)))
		transforms.append(Transform3D(rb, Vector3(q.x, wl - 0.1, q.y)))
		var rwarm := rng.randf_range(0.86, 1.02)
		colors.append(Color(rwarm * 0.94, rwarm, rwarm * rng.randf_range(0.80, 0.94)))
	_multimesh(root, "Reeds", reed_mesh, reed_mat, transforms, false, colors)
	# Dry-bank outpost near the training spawn.
	_asset_on(root, map_name, "observation_post", Vector2(8, 154), 0.2)
	_asset_on(root, map_name, "sandbag_wall", Vector2(30, 160), -0.1)
	for p in [Vector2(-18, 188), Vector2(48, 184), Vector2(72, 204)]:
		_asset_on(root, map_name, "vegetation/oak_hero", p, float(p.x) * 0.02)
	for p in [Vector2(18, 198), Vector2(44, 190)]:
		_asset_on(root, map_name, "hedgehog", p, float(p.y) * 0.01)
	for p in [Vector2(24, 184), Vector2(36, 186)]:
		ASSETS.spawn_prop(root, "prop_crate", Vector3(p.x, _height(map_name, p.x, p.y), p.y), 0.3)


static func _add_hall(root: Node3D, map_name: String, p: Vector2, w: float, h: float,
		d: float, yaw: float, wall: Material, roof: Material) -> void:
	var y := _height(map_name, p.x, p.y)
	var base := Vector3(p.x, y, p.y)
	var basis := Basis(Vector3.UP, yaw)
	var trim := _pbr("steel", Color(0.42, 0.44, 0.43), 0.34)
	var rust := _pbr("steel", Color(0.45, 0.27, 0.17), 0.38)
	var grime := _mat(Color(0.16, 0.14, 0.11), 0.95)
	var roof_light := _mat(Color(0.14, 0.17, 0.18), 0.3, 0.2)
	var concrete_skirt := _pbr("concrete", Color(0.70, 0.68, 0.65), 0.35)
	# 6.4m thick concrete foundation skirt below base so hall never floats on uneven ground
	_add_box(root, base + Vector3(0.0, -3.2, 0.0), Vector3(w + 0.8, 6.4, d + 0.8), concrete_skirt, yaw, false)
	# Real openings.  The old hall was a solid box with painted-on windows,
	# which is exactly what made a convincing facade feel like an invisible
	# wall up close.
	var win_w := clampf(w * 0.075, 2.4, 3.4)
	var win_bottom := clampf(h * 0.34, 3.4, 5.0)
	var win_h := minf(clampf(h * 0.16, 2.0, 2.4),
			maxf(1.2, h - win_bottom - 0.6))
	var door_w := clampf(w * 0.055, 2.2, 3.0)
	var door_h := minf(h * 0.30, 3.6)
	var long_open: Array[Rect2] = []
	for k in range(4):
		var cx := (-0.42 + 0.28 * float(k)) * w
		long_open.append(Rect2(cx - win_w * 0.5, win_bottom, win_w, win_h))
	for sx in [-1.0, 1.0]:
		var dx: float = sx * 0.27 * w
		long_open.append(Rect2(dx - door_w * 0.5, 0.0, door_w, door_h))
	for side in [-1.0, 1.0]:
		_add_wall_with_openings(root, base + basis * Vector3(0.0, 0.0, side * d * 0.5),
				yaw, w, h, 0.5, wall, long_open, trim)
	var short_w := clampf(d * 0.09, 2.4, 3.4)
	var short_open: Array[Rect2] = []
	for k in range(2):
		var cx := (-0.25 + 0.5 * float(k)) * d
		short_open.append(Rect2(cx - short_w * 0.5, win_bottom, short_w, win_h))
	short_open.append(Rect2(-door_w * 0.5, 0.0, door_w, door_h))
	for sx in [-1.0, 1.0]:
		_add_wall_with_openings(root, base + basis * Vector3(sx * w * 0.5, 0.0, 0.0),
				yaw + PI * 0.5, d, h, 0.5, wall, short_open, trim)
	# Roof: solid, exact box collider.  Its visual overhang is the collider.
	_add_box(root, base + Vector3(0.0, h + 0.3, 0.0),
			Vector3(w + 1.0, 0.6, d + 1.0), roof, yaw, true)
	# Saw-tooth roof lights.
	for i in range(5):
		var off: Vector3 = basis * Vector3(-w * 0.36 + float(i) * w * 0.18, h + 0.9, 0.0)
		_add_box(root, base + off, Vector3(w * 0.12, 0.7, d * 0.7),
				roof_light, yaw, false)
	# Downpipes.
	for side in [-1.0, 1.0]:
		for k in range(3):
			var dp := base + basis * Vector3(-w * 0.44 + float(k) * w * 0.44, 0.0,
					side * (d * 0.5 + 0.16))
			_add_cylinder(root, Vector3(dp.x, y + h * 0.45, dp.z), 0.09,
					h * 0.9, rust, 0.0, false)
	# Grime band at the base and roof-edge trim.
	for side in [-1.0, 1.0]:
		var fz: float = side * (d * 0.5 + 0.13)
		_add_box(root, base + basis * Vector3(0.0, 0.35, fz),
				Vector3(w * 0.98, 0.7, 0.08), grime, yaw, false)
		_add_box(root, base + basis * Vector3(0.0, h + 0.62, fz),
				Vector3(w + 1.0, 0.20, 0.22), trim, yaw, false)
	# Roof vents.
	for i in range(3):
		var vo: Vector3 = basis * Vector3(-w * 0.28 + float(i) * w * 0.28, h + 1.05, 0.0)
		_add_cylinder(root, base + vo, 0.55, 1.1, trim, 0.0, false)


static func _add_burnt_tank(root: Node3D, map_name: String, p: Vector2, yaw: float) -> void:
	var y := footprint_surface_height(map_name, p, 5.8, 2.6, yaw) - 0.22
	var soot := _mat(Color(0.115, 0.105, 0.090), 0.98)
	var rust := _mat(Color(0.295, 0.170, 0.095), 0.94, 0.10)
	var steel := _mat(Color(0.205, 0.190, 0.165), 0.82, 0.38)
	var track := _mat(Color(0.070, 0.066, 0.058), 1.0)

	# Whole wreck in one local frame so it can sit at a knocked-out roll angle.
	var hull_node := Node3D.new()
	hull_node.position = Vector3(p.x, y, p.y)
	hull_node.rotation = Vector3(0.0, yaw, 0.045)
	root.add_child(hull_node)

	# Lower hull, upper hull and the sloped glacis plate.  The old wreck was a
	# single tall slab; separating the hull into two volumes gives the tank the
	# layered silhouette it needs at FPV distance.
	_add_box(hull_node, Vector3(0.0, 0.70, 0.0), Vector3(5.8, 0.88, 2.62), soot, 0.0, true)
	_add_box(hull_node, Vector3(-0.10, 1.20, 0.0), Vector3(5.2, 0.42, 2.38), soot, 0.0, false)
	_add_local_box(hull_node, Vector3(2.45, 1.06, 0.0),
			Vector3(1.45, 0.14, 2.36), rust, Vector3(0.0, 0.0, -0.80))
	_add_local_box(hull_node, Vector3(-2.92, 1.02, 0.0),
			Vector3(0.14, 0.72, 2.20), steel, Vector3(0.0, 0.0, -0.18))

	# Track assemblies: skirt + five road wheels per side, which is what reads
	# as "tank" instead of a flat box.
	var wheel_mesh := CylinderMesh.new()
	wheel_mesh.top_radius = 0.40
	wheel_mesh.bottom_radius = 0.40
	wheel_mesh.height = 0.30
	wheel_mesh.radial_segments = 12
	var rim_mesh := CylinderMesh.new()
	rim_mesh.top_radius = 0.22
	rim_mesh.bottom_radius = 0.22
	rim_mesh.height = 0.33
	rim_mesh.radial_segments = 10
	for side in [-1.0, 1.0]:
		_add_box(hull_node, Vector3(0.0, 0.62, 1.46 * side),
				Vector3(6.1, 0.70, 0.16), track, 0.0, false)
		for wx in [-2.15, -1.05, 0.05, 1.15, 2.20]:
			var wheel := MeshInstance3D.new()
			wheel.mesh = wheel_mesh
			wheel.material_override = steel
			wheel.position = Vector3(wx, 0.43, 1.44 * side)
			wheel.rotation.x = PI * 0.5
			wheel.set_meta("batch_cyl", Vector3(0.40, 0.30, 0.40))
			hull_node.add_child(wheel)
			var rim := MeshInstance3D.new()
			rim.mesh = rim_mesh
			rim.material_override = rust
			rim.position = Vector3(wx, 0.43, 1.46 * side)
			rim.rotation.x = PI * 0.5
			rim.set_meta("batch_cyl", Vector3(0.22, 0.33, 0.22))
			hull_node.add_child(rim)

	# Cast turret: a squashed cylinder reads as the rounded T-64/T-72 dome,
	# with a rear bustle, mantlet, cupola and a drooping gun barrel.
	var turret := MeshInstance3D.new()
	var turret_mesh := CylinderMesh.new()
	turret_mesh.top_radius = 0.82
	turret_mesh.bottom_radius = 1.02
	turret_mesh.height = 0.80
	turret_mesh.radial_segments = 12
	turret.mesh = turret_mesh
	turret.material_override = rust
	turret.position = Vector3(0.05, 1.70, 0.0)
	turret.scale = Vector3(1.22, 1.0, 0.92)
	hull_node.add_child(turret)
	_add_box(hull_node, Vector3(-1.05, 1.74, 0.0), Vector3(1.05, 0.58, 1.72), rust, 0.12, false)
	_add_box(hull_node, Vector3(1.18, 1.78, 0.0), Vector3(0.42, 0.62, 1.20), steel, 0.0, false)

	var barrel := MeshInstance3D.new()
	var barrel_mesh := CylinderMesh.new()
	barrel_mesh.top_radius = 0.060
	barrel_mesh.bottom_radius = 0.085
	barrel_mesh.height = 3.40
	barrel_mesh.radial_segments = 10
	barrel.mesh = barrel_mesh
	barrel.material_override = steel
	barrel.position = Vector3(2.90, 1.84, 0.02)
	# Rotate -90° around Z so the cylinder axis (+Y) points forward (+X), then
	# droop the muzzle: the barrel is visibly bent after the cook-off.
	barrel.rotation = Vector3(0.0, 0.0, -PI * 0.5 - 0.19)
	hull_node.add_child(barrel)

	var muzzle := MeshInstance3D.new()
	var muzzle_mesh := CylinderMesh.new()
	muzzle_mesh.top_radius = 0.105
	muzzle_mesh.bottom_radius = 0.105
	muzzle_mesh.height = 0.28
	muzzle_mesh.radial_segments = 10
	muzzle.mesh = muzzle_mesh
	muzzle.material_override = track
	muzzle.position = Vector3(4.58, 1.52, 0.02)
	muzzle.rotation = Vector3(0.0, 0.0, -PI * 0.5 - 0.19)
	muzzle.set_meta("batch_cyl", Vector3(0.105, 0.28, 0.105))
	hull_node.add_child(muzzle)

	# Cupola, hatch and a bent antenna.
	var cupola := MeshInstance3D.new()
	var cup_mesh := CylinderMesh.new()
	cup_mesh.top_radius = 0.30
	cup_mesh.bottom_radius = 0.34
	cup_mesh.height = 0.36
	cup_mesh.radial_segments = 8
	cupola.mesh = cup_mesh
	cupola.material_override = steel
	cupola.position = Vector3(0.38, 2.18, 0.52)
	cupola.set_meta("batch_cyl", Vector3(0.34, 0.36, 0.34))
	hull_node.add_child(cupola)
	var hatch := MeshInstance3D.new()
	var hatch_mesh := CylinderMesh.new()
	hatch_mesh.top_radius = 0.26
	hatch_mesh.bottom_radius = 0.26
	hatch_mesh.height = 0.07
	hatch_mesh.radial_segments = 8
	hatch.mesh = hatch_mesh
	hatch.material_override = track
	hatch.position = Vector3(0.38, 2.39, 0.52)
	hatch.set_meta("batch_cyl", Vector3(0.26, 0.07, 0.26))
	hull_node.add_child(hatch)
	var antenna := MeshInstance3D.new()
	var antenna_mesh := CylinderMesh.new()
	antenna_mesh.top_radius = 0.012
	antenna_mesh.bottom_radius = 0.022
	antenna_mesh.height = 2.3
	antenna_mesh.radial_segments = 5
	antenna.mesh = antenna_mesh
	antenna.material_override = steel
	antenna.position = Vector3(-1.28, 2.72, -0.78)
	antenna.rotation = Vector3(0.12, 0.0, 0.30)
	hull_node.add_child(antenna)

	# Stowage boxes on the fenders, one hanging open.
	_add_box(hull_node, Vector3(-1.85, 1.42, 1.18), Vector3(1.10, 0.34, 0.30), steel, 0.0, false)
	_add_box(hull_node, Vector3(-1.70, 1.38, -1.20), Vector3(1.25, 0.30, 0.28), rust, 0.0, false)


static func _add_local_box(parent: Node3D, pos: Vector3, size: Vector3,
		mat: Material, rot: Vector3) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi


static var _windbreak_positions: Dictionary = {}


## Windbreak shelterbelts are folded into the main Blender tree instancing:
## this only collects the belt positions, `_build_treelines` places the trees.
static func _add_windbreak(_root: Node3D, map_name: String, a: Vector2,
		b: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(a.x * 7.0 + a.y * 13.0 + b.x * 3.0 + b.y * 17.0))
	var positions: Array = []
	var seg := b - a
	var length := seg.length()
	var dir := seg / maxf(length, 0.001)
	var n := Vector2(-dir.y, dir.x)
	var wl := water_level(map_name)
	var t := 0.0
	while t < length:
		for row_v in [-3.2, 3.2]:
			if rng.randf() < 0.16:
				continue
			var row := float(row_v)
			var p := a + dir * (t + rng.randf_range(-1.6, 1.6)) \
					+ n * (row + rng.randf_range(-1.8, 1.8))
			var h := _height(map_name, p.x, p.y)
			if h < wl + 0.4:
				continue
			positions.append(Vector3(p.x, h, p.y))
		t += rng.randf_range(3.4, 5.4)
	# The belt has to survive the instance cap, so it goes first.
	_windbreak_positions[map_name] = positions


## Four long, slightly wavy hedgerows per map: they divide the open fields into
## farmland and give the aerial view structure without unique assets.
static func _hedgerows(map_name: String) -> Array:
	var lines: Array = []
	var zlines := [-200.0, 200.0]
	match map_name:
		"village":
			zlines = [-195.0, 210.0]
		"wetlands":
			zlines = [-190.0, 190.0]
	for z in zlines:
		var pts := PackedVector2Array()
		var x := -255.0
		while x <= 255.0:
			pts.append(Vector2(x, z + 6.0 * sin(x * 0.02)))
			x += 13.0
		lines.append(pts)
	for xline in [-210.0, 210.0]:
		var pts := PackedVector2Array()
		var z := -255.0
		while z <= 255.0:
			pts.append(Vector2(xline + 6.0 * sin(z * 0.02), z))
			z += 13.0
		lines.append(pts)
	return lines


# ===========================================================================
#  Trees: near multi-mesh + far octahedral impostors
# ===========================================================================
static func _treelines(map_name: String) -> Array:
	match map_name:
		"village":
			return [
				PackedVector2Array([Vector2(-245, -40), Vector2(-180, -85), Vector2(-115, -60),
						Vector2(-45, -95), Vector2(40, -70), Vector2(130, -105), Vector2(235, -80)]),
				PackedVector2Array([Vector2(-245, 205), Vector2(-145, 230), Vector2(-35, 215),
						Vector2(95, 235), Vector2(225, 215)]),
				PackedVector2Array([Vector2(-90, -200), Vector2(-40, -150), Vector2(10, -100)]),
			]
		"industrial":
			return [
				PackedVector2Array([Vector2(-250, -245), Vector2(-130, -230), Vector2(0, -245),
						Vector2(130, -225), Vector2(250, -240)]),
				PackedVector2Array([Vector2(-245, 200), Vector2(-130, 212), Vector2(0, 200),
						Vector2(130, 212), Vector2(245, 200)]),
			]
		"wetlands":
			return [
				PackedVector2Array([Vector2(-245, 160), Vector2(-140, 178), Vector2(-35, 165),
						Vector2(100, 185), Vector2(235, 170)]),
				PackedVector2Array([Vector2(-235, -210), Vector2(-120, -195), Vector2(0, -220),
						Vector2(120, -200), Vector2(235, -215)]),
			]
		_:
			return [
				PackedVector2Array([Vector2(-250, 130), Vector2(-160, 150), Vector2(-70, 135),
						Vector2(50, 158), Vector2(150, 140), Vector2(250, 152)]),
				PackedVector2Array([Vector2(-245, -210), Vector2(-135, -195), Vector2(-20, -220),
						Vector2(120, -205), Vector2(245, -215)]),
				PackedVector2Array([Vector2(-140, -40), Vector2(-150, 60), Vector2(-170, 160)]),
			]


## The flight-school strip must stay free of trees and props: the student flies
## a fixed 190 m course there.
static func _tutorial_clear_zone(x: float, z: float) -> bool:
	var is_tut := false
	var st := Engine.get_main_loop() as SceneTree
	if st != null and st.root != null:
		var g := st.root.get_node_or_null("Global")
		if g != null and g.get("play_mode") == 2:
			is_tut = true
	return is_tut and absf(x + 48.0) < 42.0 and z > 20.0 and z < 260.0


## Keep every authored hall interior and apron free of scattered trees and
## random prop clusters.
static func _hall_clear_zone(map_name: String, x: float, z: float) -> bool:
	var site: Dictionary = HALL_SITES.get(map_name, {})
	if site.is_empty():
		return false
	var c: Vector2 = site["center"]
	var half: Vector2 = site["half"]
	if absf(x - c.x) < half.x + 6.0 and absf(z - c.y) < half.y + 6.0:
		return true
	# The take-off apron sits just south of the hall.  Keep fences, power poles,
	# boom barriers and scattered props out of it: a low rail across the pad was
	# blocking the first climb-out on Steppe.  Use the authored spawn point for
	# the map rather than a hard-coded offset so the 18 m pad stays clear even
	# when a hall is resized.
	var spawn := Vector2(site.get("spawn", Vector2(c.x, c.y + half.y + 20.0)))
	return Vector2(x, z).distance_to(spawn) < 22.0


## The steppe farmstead is authored: no scattered tree may grow through a
## cottage wall or block the spawn view.
static func _farm_clear_zone(map_name: String, x: float, z: float) -> bool:
	if map_name == "steppe":
		if Vector2(x, z).distance_to(Vector2(52.0, 150.0)) < 34.0:
			return true
		if Vector2(x, z).distance_to(Vector2(-220.0, 30.0)) < 26.0:
			return true
		if Vector2(x, z).distance_to(Vector2(235.0, -45.0)) < 26.0:
			return true
		return false
	if map_name == "wetlands":
		return Vector2(x, z).distance_to(Vector2(30.0, 60.0)) < 14.0
	if map_name == "village":
		# Keep the whole cottage street clear of scattered trees: their 2.5 m
		# trunks read as dark blocks at close range.
		if absf(z - 58.0) < 16.0 and x > 20.0 and x < 186.0:
			return true
		for c in [Vector2(-245, 60), Vector2(-248, -175), Vector2(248, 120),
				Vector2(235, -210), Vector2(-235, 225), Vector2(245, 235),
				Vector2(140, -245)]:
			if Vector2(x, z).distance_to(c) < 17.0:
				return true
		return false
	return false


## Dedicated clear zones around all silos, cooling towers, chimneys, radar, and military structures
## so no tree, bush, fence or clutter can clip into or spawn inside them.
static func _structure_clear_zone(map_name: String, x: float, z: float) -> bool:
	var p := Vector2(x, z)
	# Signature POIs get a generous berth so no tree, fence or bush grows
	# through a water-tower leg or a substation fence.
	for poi in _poi_positions:
		if p.distance_to(poi) < 26.0:
			return true
	for zone in _reserved_zones:
		if p.distance_to(zone["pos"]) < float(zone["radius"]):
			return true
	# Check all 30 military trick structures dynamically
	var mil_script = load("res://scripts/util/military_structures.gd")
	if mil_script != null and mil_script.spawned_positions.has(map_name):
		var mil_list: Array = mil_script.spawned_positions[map_name]
		for mp in mil_list:
			if p.distance_to(mp) < 24.0:
				return true

	match map_name:
		"industrial":
			# Cooling towers (both procedural & handcrafted)
			if p.distance_to(Vector2(155.0, 30.0)) < 26.0:
				return true
			if p.distance_to(Vector2(-72.0, -214.0)) < 26.0:
				return true
			if p.distance_to(Vector2(-245.0, 155.0)) < 26.0:
				return true
			# Chimneys
			if p.distance_to(Vector2(-55.0, 35.0)) < 15.0:
				return true
			if p.distance_to(Vector2(-90.0, -146.0)) < 15.0:
				return true
			# Standalone silos
			if p.distance_to(Vector2(26.0, -32.0)) < 18.0:
				return true
			if p.distance_to(Vector2(-50.0, 0.0)) < 18.0:
				return true
			if p.distance_to(Vector2(-140.0, 20.0)) < 18.0:
				return true
			if p.distance_to(Vector2(140.0, -50.0)) < 18.0:
				return true
		"steppe":
			# Standalone farm grain silos & paddock
			if p.distance_to(Vector2(-180.0, 220.0)) < 20.0:
				return true
			if p.distance_to(Vector2(240.0, -120.0)) < 20.0:
				return true
			# Radar station
			if p.distance_to(Vector2(-225.0, -210.0)) < 24.0:
				return true
		"village":
			# Windmill bluff
			if p.distance_to(Vector2(-110.0, 115.0)) < 24.0:
				return true
	return false


static func _build_treelines(root: Node3D, map_name: String) -> void:
	if OS.has_environment("QA_NO_TREES"):
		return
	var variants := VEGETATION.trees()
	if variants.is_empty():
		_build_treelines_procedural(root, map_name)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(map_name) + 137
	var positions: Array = []
	var wl := water_level(map_name)

	# Windbreak belts first so they survive the instance cap.
	positions.append_array(_windbreak_positions.get(map_name, []))
	# Field hedgerows: long, slightly wavy tree lines that break the open
	# fields into farmland and give the aerial view structure.
	for line in _hedgerows(map_name):
		for point in line:
			var hp: Vector2 = point
			var hy := _height(map_name, hp.x, hp.y)
			if hy < wl + 0.4:
				continue
			positions.append(Vector3(hp.x, hy, hp.y))
	# Frame the northern approach field with two rows of proper Blender trees.
	# They sit outside the flight-school strip (x �70) but fill the otherwise
	# empty foreground at the combat spawn.  Added before the cap so they are
	# never truncated on UFDS.
	var edge_z := [168.0, 190.0, 212.0, 234.0, 254.0]
	for z in edge_z:
		for x in [-96.0, 96.0]:
			var edge_h := _height(map_name, x, z)
			if edge_h < wl + 0.4:
				continue
			positions.append(Vector3(x, edge_h, z))
	# A few proper Blender copses frame the open approach without touching the
	# x �70 training strip.  They give the foreground depth that the retired
	# procedural lollipops used to fake.
	var copse_centres := [Vector2(-78, 186), Vector2(78, 196), Vector2(-88, 214),
			Vector2(84, 228), Vector2(-76, 246), Vector2(82, 252),
			Vector2(-96, 234), Vector2(96, 182)]
	for centre in copse_centres:
		var centre_v: Vector2 = centre
		for j in range(4):
			var cx: float = centre_v.x + rng.randf_range(-8.0, 8.0)
			var cz: float = centre_v.y + rng.randf_range(-8.0, 8.0)
			var ch := _height(map_name, cx, cz)
			if ch < wl + 0.4:
				continue
			positions.append(Vector3(cx, ch, cz))

	for line in _treelines(map_name):
		var pl: PackedVector2Array = line
		for i in range(pl.size() - 1):
			var a := pl[i]
			var b := pl[i + 1]
			var seg := b - a
			var length := seg.length()
			var dir := seg / maxf(length, 0.001)
			var n := Vector2(-dir.y, dir.x)
			var t := 0.0
			while t < length:
				for band in [-4.0, 4.0, 9.0]:
					if rng.randf() < 0.35:
						continue
					var band_off := float(band) + rng.randf_range(-2.0, 2.0)
					var p := a + dir * t + n * band_off
					var h := _height(map_name, p.x, p.y)
					if h < wl + 0.4:
						continue
					positions.append(Vector3(p.x, h, p.y))
				t += rng.randf_range(4.0, 8.0)

	# Scattered orchard / copse clumps (compact 40% smaller arena).
	var clumps := 20 if map_name == "village" else 14
	for i in range(clumps):
		var c := Vector2(rng.randf_range(-255.0, 255.0), rng.randf_range(-255.0, 255.0))
		if Vector2(c.x, c.y).distance_to(Vector2(0, 175)) < 48.0:
			continue
		for j in range(rng.randi_range(6, 18)):
			var p := c + Vector2(rng.randf_range(-20.0, 20.0), rng.randf_range(-20.0, 20.0))
			var h := _height(map_name, p.x, p.y)
			if h < wl + 0.4:
				continue
			positions.append(Vector3(p.x, h, p.y))

	# Keep the flight-school runway clear of trees (visual + trunk collision).
	var is_tut := false
	var st := Engine.get_main_loop() as SceneTree
	if st != null and st.root != null:
		var g := st.root.get_node_or_null("Global")
		if g != null and g.get("play_mode") == 2:
			is_tut = true
	if is_tut:
		positions = positions.filter(func(p):
			return not _tutorial_clear_zone(p.x, p.z))
	# Clear halls, farmsteads, silos, chimneys, cooling towers, and radar stations
	positions = positions.filter(func(p):
		return not _hall_clear_zone(map_name, p.x, p.z) \
			and not _farm_clear_zone(map_name, p.x, p.z) \
			and not _structure_clear_zone(map_name, p.x, p.z))
	# Cap the instance count so 120 FPS holds on mid-range GPUs.  Every tree is
	# a full Blender mesh (trunk + alpha-cut leaf cards) instanced per variant,
	# so one variant is still a single pair of draw calls.
	var q_lvl := QualityManager.get_active_level()
	var tree_cap := 650
	if q_lvl == QualityManager.Level.LOW:
		tree_cap = 260
	elif q_lvl == QualityManager.Level.MEDIUM:
		tree_cap = 400
	if positions.size() > tree_cap:
		positions.resize(tree_cap)
	# Alpha-cut leaf cards and the branch-heavy trunks are expensive in the
	# shadow pass (a MultiMesh is culled as one huge AABB, so every tree is
	# rendered into both cascades).  LOW/MEDIUM/UFDS keep no tree-cast shadows;
	# the cinematic HIGH profile keeps the full trunk + crown shadows.
	var tree_shadows := q_lvl == 2
	if OS.has_environment("QA_NO_TREE_SHADOW"):
		tree_shadows = false
	var canopy_shadows := tree_shadows
	var veg_range := 1400.0
	match q_lvl:
		0:
			veg_range = 520.0
		1:
			veg_range = 820.0
		3:
			veg_range = 650.0
		4:
			veg_range = 420.0
		5:
			veg_range = 240.0
		6:
			veg_range = 160.0

	# Bucket every position into one of the five mesh variants.  The last two
	# entries are conifers, the rest are broadleaves.
	var conifer_first := maxi(0, variants.size() - 2)
	var broadleaf_last := maxi(0, conifer_first - 1)
	var buckets: Dictionary = {}
	for v in variants:
		buckets[v["name"]] = []
	for pos in positions:
		var v: Dictionary
		if rng.randf() < 0.34:
			v = variants[rng.randi_range(conifer_first, variants.size() - 1)]
		else:
			v = variants[rng.randi_range(0, broadleaf_last)]
		# The shared Blender trees were authored at a smaller unit scale than the
		# old placeholder forest, so the belts read as bushes.  Bring them up to
		# mature-tree size: 9-17 m crowns instead of 6-9 m.
		var scale := rng.randf_range(0.95, 1.70)
		var yaw := rng.randf_range(0.0, TAU)
		var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(
				Vector3(scale, scale, scale)), pos)
		buckets[v["name"]].append(xf)

	for v in variants:
		var xfs: Array = buckets[v["name"]]
		if xfs.is_empty():
			continue
		var leaf_mat := (v["leaves"] as ArrayMesh).surface_get_material(0) as ShaderMaterial
		if leaf_mat != null and q_lvl == QualityManager.Level.HIGH:
			leaf_mat.set_shader_parameter("leaf_detail",
					0.16 if v["pine"] else 0.32)
		var trunk_node := _multimesh(root, v["name"] + "_Trunks",
				v["trunk"], null, xfs, tree_shadows)
		var leaf_node: MultiMeshInstance3D = null
		if not OS.has_environment("QA_NO_LEAVES"):
			leaf_node = _multimesh(root, v["name"] + "_Leaves",
					v["leaves"], null, xfs, canopy_shadows)
		for node in [trunk_node, leaf_node]:
			if node != null:
				node.visibility_range_end = veg_range
				node.visibility_range_end_margin = 60.0
				node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	_add_tree_colliders(root, buckets)


## Trunk collision for the instanced forest.  The crowns stay pass-through (the
## pilot flies through leaves), but the wooden trunks are solid so the drone
## cannot ghost through a tree.  The boxes are grouped into ~96 m tiles so the
## physics broadphase (and the drone's CCD cast) only tests the nearby forest,
## not one map-sized concave shape.
static func _add_tree_colliders(root: Node3D, buckets: Dictionary) -> void:
	if root.get_node_or_null("TreeCollision") != null:
		return
	if OS.has_environment("QA_NO_TREE_COLLISION"):
		return
	var cells: Dictionary = {}
	for key in buckets.keys():
		var xfs: Array = buckets[key]
		for xf in xfs:
			var t: Transform3D = xf
			var s: float = t.basis.get_scale().x
			if absf(t.origin.x) > 275.0 or absf(t.origin.z) > 275.0:
				continue
			var cell := Vector2i(int(floor(t.origin.x / 96.0)),
					int(floor(t.origin.z / 96.0)))
			if not cells.has(cell):
				cells[cell] = [] as Array[Vector3]
			_append_box_faces(cells[cell], t.origin + Vector3(0.0, 2.55 * s, 0.0),
					Vector3(0.32 * s, 2.55 * s, 0.32 * s))
	for cell in cells.keys():
		var faces: Array[Vector3] = cells[cell]
		if faces.is_empty():
			continue
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(PackedVector3Array(faces))
		var body := StaticBody3D.new()
		body.name = "TreeCollision_%d_%d" % [cell.x, cell.y]
		body.collision_layer = 1
		body.collision_mask = 1
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)
		root.add_child(body)


static func _append_box_faces(faces: Array[Vector3], centre: Vector3,
		half: Vector3) -> void:
	var p := [
		centre + Vector3(-half.x, -half.y, -half.z),
		centre + Vector3(half.x, -half.y, -half.z),
		centre + Vector3(half.x, half.y, -half.z),
		centre + Vector3(-half.x, half.y, -half.z),
		centre + Vector3(-half.x, -half.y, half.z),
		centre + Vector3(half.x, -half.y, half.z),
		centre + Vector3(half.x, half.y, half.z),
		centre + Vector3(-half.x, half.y, half.z),
	]
	var quads := [[0, 1, 2, 3], [4, 7, 6, 5], [0, 4, 5, 1],
			[1, 5, 6, 2], [2, 6, 7, 3], [3, 7, 4, 0]]
	for q in quads:
		var a: Vector3 = p[q[0]]
		var b: Vector3 = p[q[1]]
		var c: Vector3 = p[q[2]]
		var d: Vector3 = p[q[3]]
		faces.append(a)
		faces.append(b)
		faces.append(c)
		faces.append(a)
		faces.append(c)
		faces.append(d)


## Fallback used when the Blender vegetation library is missing: the old
## procedural trunk + canopy-lobe tree lines.
static func _build_treelines_procedural(root: Node3D, map_name: String) -> void:
	# Legacy cylinder-and-ellipsoid trees are no longer used; if the Blender
	# library is missing, an empty forest is preferable to wrong-looking trees.
	return
	@warning_ignore("unreachable_code")
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(map_name) + 137
	var positions: Array = []
	var wl := water_level(map_name)

	for line in _treelines(map_name):
		var pl: PackedVector2Array = line
		for i in range(pl.size() - 1):
			var a := pl[i]
			var b := pl[i + 1]
			var seg := b - a
			var length := seg.length()
			var dir := seg / maxf(length, 0.001)
			var n := Vector2(-dir.y, dir.x)
			var t := 0.0
			while t < length:
				for band in [-4.0, 4.0, 9.0]:
					if rng.randf() < 0.35:
						continue
					var band_off := float(band) + rng.randf_range(-2.0, 2.0)
					var p := a + dir * t + n * band_off
					var h := _height(map_name, p.x, p.y)
					if h < wl + 0.4:
						continue
					positions.append(Vector3(p.x, h, p.y))
				t += rng.randf_range(4.0, 8.0)

	var clumps := 26 if map_name == "village" else 14
	for i in range(clumps):
		var c := Vector2(rng.randf_range(-430.0, 430.0), rng.randf_range(-430.0, 430.0))
		if Vector2(c.x, c.y).distance_to(Vector2(0, 220)) < 55.0:
			continue
		for j in range(rng.randi_range(8, 26)):
			var p := c + Vector2(rng.randf_range(-26.0, 26.0), rng.randf_range(-26.0, 26.0))
			var h := _height(map_name, p.x, p.y)
			if h < wl + 0.4:
				continue
			positions.append(Vector3(p.x, h, p.y))

	var q_lvl := QualityManager.get_active_level()
	var tree_cap := 650
	if q_lvl == QualityManager.Level.LOW:
		tree_cap = 260
	elif q_lvl == QualityManager.Level.MEDIUM:
		tree_cap = 400
	if positions.size() > tree_cap:
		positions.resize(tree_cap)
	var canopy_shadows := q_lvl == QualityManager.Level.HIGH

	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.09
	trunk_mesh.bottom_radius = 0.20
	trunk_mesh.height = 4.2
	trunk_mesh.radial_segments = 6
	trunk_mesh.rings = 1
	var leaf_mesh: ArrayMesh
	if q_lvl == QualityManager.Level.HIGH:
		leaf_mesh = FOLIAGE.make_canopy_mesh(7, 4, 0.27)
	else:
		leaf_mesh = FOLIAGE.make_canopy_mesh(6, 3, 0.22)
	var cone_mesh := FOLIAGE.make_cone_mesh(1.0, 1.0, 10, 0.16)

	var trunk_transforms: Array = []
	var leaf_transforms: Array = []
	var cone_transforms: Array = []
	var leaf_colors: Array = []
	var cone_colors: Array = []
	var trunk_colors: Array = []
	for pos in positions:
		var base: Vector3 = pos
		var scale := rng.randf_range(0.70, 1.55)
		var yaw := rng.randf_range(0.0, TAU)
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3(scale, scale, scale))
		trunk_transforms.append(Transform3D(basis, base + Vector3(0.0, 2.1 * scale, 0.0)))
		trunk_colors.append(Color(0.20, 0.15, 0.10).darkened(rng.randf_range(0.0, 0.25)))

		var tint := rng.randf_range(0.66, 1.18)
		if rng.randf() < 0.34:
			var pine_tint := tint * rng.randf_range(0.85, 1.0)
			for i in range(3):
				var s := scale * (1.0 - float(i) * 0.2)
				var h := scale * (2.5 - float(i) * 0.25)
				var y: float = base.y + scale * (3.1 + float(i) * 2.15)
				var b := Basis(Vector3.UP, yaw + float(i) * 0.6).scaled(
						Vector3(s * 2.05, h, s * 2.05))
				cone_transforms.append(Transform3D(b, Vector3(base.x, y, base.z)))
				cone_colors.append(Color(0.045 * pine_tint, 0.092 * pine_tint,
						0.038 * pine_tint))
		else:
			var leaf_tint := tint
			var crown_w := rng.randf_range(0.84, 1.16)
			var crown_h := rng.randf_range(0.90, 1.18)
			var lobes := [
				{"off": Vector3(0.0, 5.00, 0.0), "s": Vector3(1.55, 1.35, 1.55)},
				{"off": Vector3(-1.05, 4.60, 0.35), "s": Vector3(1.20, 1.05, 1.20)},
				{"off": Vector3(1.05, 4.75, -0.30), "s": Vector3(1.15, 1.00, 1.15)},
				{"off": Vector3(0.20, 6.05, 0.25), "s": Vector3(1.15, 1.00, 1.15)},
				{"off": Vector3(-0.75, 5.75, -0.65), "s": Vector3(0.95, 0.85, 0.95)},
				{"off": Vector3(0.95, 4.15, 0.75), "s": Vector3(0.90, 0.78, 0.90)},
				{"off": Vector3(-0.55, 4.05, -0.85), "s": Vector3(0.85, 0.75, 0.85)},
			]
			var lobe_order := [0, 1, 2, 3, 5, 4, 6]
			var lobe_count := 7
			if q_lvl == 0:
				lobe_count = 5
			elif q_lvl == 1:
				lobe_count = 6
			for li in range(lobe_count):
				var l: Dictionary = lobes[lobe_order[li]]
				var jitter := rng.randf_range(0.88, 1.12)
				var off := (l["off"] as Vector3) * scale
				off += Vector3(rng.randf_range(-0.30, 0.30),
						rng.randf_range(-0.20, 0.26),
						rng.randf_range(-0.30, 0.30)) * scale
				var lobe_scale := (l["s"] as Vector3) * scale * jitter
				lobe_scale.x *= crown_w
				lobe_scale.z *= crown_w
				lobe_scale.y *= crown_h
				var b := Basis(Vector3.UP, yaw + rng.randf_range(-0.55, 0.55)).scaled(
						lobe_scale)
				leaf_transforms.append(Transform3D(b, base + off))
				var ct := leaf_tint * rng.randf_range(0.86, 1.08)
				leaf_colors.append(Color(0.070 * ct, 0.118 * ct, 0.045 * ct))

	_multimesh(root, "TreeTrunks", trunk_mesh, _mat(Color(0.21, 0.16, 0.11), 1.0),
			trunk_transforms, true, trunk_colors)
	var canopy_mat := FOLIAGE.make_wind_material(Color(1.0, 1.0, 1.0))
	canopy_mat.set_shader_parameter("mottle_strength", 0.30)
	if q_lvl == QualityManager.Level.HIGH:
		canopy_mat.set_shader_parameter("leaf_detail", 0.32)
	_multimesh(root, "TreeCanopies", leaf_mesh, canopy_mat, leaf_transforms,
			canopy_shadows, leaf_colors)
	var pine_mat := FOLIAGE.make_wind_material(Color(0.92, 0.98, 0.86))
	if q_lvl == QualityManager.Level.HIGH:
		pine_mat.set_shader_parameter("leaf_detail", 0.16)
	_multimesh(root, "PineCanopies", cone_mesh, pine_mat, cone_transforms,
			canopy_shadows, cone_colors)


## Small ground detail that sells scale at FPV altitude: weathered stones and
## meadow flowers scattered over the fields.  Both are MultiMeshes (two draw
## calls) with per-instance colours, and the count is halved on the 120 FPS
## presets.  Placement uses the same analytic height field as the mesh, so the
## stones sit on the ground instead of floating.
static func _build_ground_detail(root: Node3D, map_name: String) -> void:
	if OS.has_environment("QA_NO_GROUND_DETAIL"):
		return
	var q_lvl := QualityManager.get_active_level()
	var high_detail := q_lvl == QualityManager.Level.HIGH
	var medium_detail := q_lvl == QualityManager.Level.MEDIUM
	var rock_target := 650 if high_detail else (420 if medium_detail else 160)
	var flower_target := 1100 if high_detail else (650 if medium_detail else 260)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(map_name) + 4242
	var wl := water_level(map_name)

	# A lumpy 5x3 sphere reads as a weathered boulder at 20-300 m; one unit
	# mesh with per-instance non-uniform scale covers every stone size.
	var rock_mesh := FOLIAGE.make_canopy_mesh(5, 3, 0.30, 1.0, 1.2)
	var rock_xf: Array = []
	var rock_col: Array = []
	var tries := rock_target * 6
	var rock_radius := 255.0 if high_detail else (190.0 if medium_detail else 120.0)
	while rock_xf.size() < rock_target and tries > 0:
		tries -= 1
		var x := rng.randf_range(-rock_radius, rock_radius)
		var z := rng.randf_range(-rock_radius, rock_radius)
		var y := mesh_surface_height(map_name, x, z)
		# Keep the immediate shoreline clear: a dense line of boulders on the
		# waterline read as scattered bin bags rather than a river bank.
		if y < wl + 0.9:
			continue
		var s := rng.randf_range(0.10, 0.55)
		var b := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(
				Vector3(s * rng.randf_range(1.0, 1.6), s * rng.randf_range(0.45, 0.75),
						s * rng.randf_range(0.9, 1.4)))
		rock_xf.append(Transform3D(b, Vector3(x, y + s * 0.18, z)))
		var g := rng.randf_range(0.38, 0.64)
		rock_col.append(Color(g * 1.04, g * 0.99, g * 0.90))

	# Flower heads: tiny bright dots that break the uniform green carpet.
	var flower_mesh := FOLIAGE.make_canopy_mesh(4, 2, 0.25, 1.0, 1.0)
	var flower_xf: Array = []
	var flower_col: Array = []
	var flower_radius := 245.0 if high_detail else (170.0 if medium_detail else 110.0)
	tries = flower_target * 5
	while flower_xf.size() < flower_target and tries > 0:
		tries -= 1
		var x := rng.randf_range(-flower_radius, flower_radius)
		var z := rng.randf_range(-flower_radius, flower_radius)
		var y := mesh_surface_height(map_name, x, z)
		if y < wl + 0.30:
			continue
		var s := rng.randf_range(0.018, 0.042)
		flower_xf.append(Transform3D(Basis().scaled(Vector3(s, s * 1.5, s)),
				Vector3(x, y + rng.randf_range(0.16, 0.42), z)))
		var kind := rng.randf()
		if kind < 0.62:
			flower_col.append(Color(0.92, 0.88, 0.62))
		elif kind < 0.86:
			flower_col.append(Color(0.86, 0.78, 0.36))
		else:
			flower_col.append(Color(0.72, 0.58, 0.62))

	# Low scrub / bush clumps between the stones and flowers.  One MultiMesh
	# adds a natural middle layer across the fields without more draw calls.
	var bush_target := 850 if high_detail else (220 if medium_detail else 65)
	var bush_radius := 245.0 if high_detail else (160.0 if medium_detail else 100.0)
	var bush_mesh := FOLIAGE.make_canopy_mesh(5, 2, 0.42, 0.55, 0.65)
	var bush_mat := FOLIAGE.make_wind_material(
			Color(0.11, 0.16, 0.055) if map_name == "wetlands" \
			else Color(0.14, 0.16, 0.065))
	var bush_xf: Array = []
	var tries_bush := bush_target * 5
	while bush_xf.size() < bush_target and tries_bush > 0:
		tries_bush -= 1
		var bx := rng.randf_range(-bush_radius, bush_radius)
		var bz := rng.randf_range(-bush_radius, bush_radius)
		var by := mesh_surface_height(map_name, bx, bz)
		if by < wl + 0.35:
			continue
		var bs := rng.randf_range(0.35, 1.05)
		bush_xf.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU))
				.scaled(Vector3(bs * 1.4, bs * rng.randf_range(0.55, 0.85),
						bs * 1.4)), Vector3(bx, by + bs * 0.18, bz)))
	_multimesh(root, "GroundScrub", bush_mesh, bush_mat, bush_xf, false)

	var rock_mat := _mat(Color(0.52, 0.50, 0.45), 1.0)
	rock_mat.vertex_color_use_as_albedo = true
	_multimesh(root, "GroundStones", rock_mesh, rock_mat, rock_xf, false, rock_col)
	var flower_mat := _mat(Color(1.0, 1.0, 1.0), 0.9)
	flower_mat.vertex_color_use_as_albedo = true
	flower_mat.emission_enabled = true
	flower_mat.emission = Color(1.0, 1.0, 0.55)
	flower_mat.emission_energy_multiplier = 0.12
	_multimesh(root, "Wildflowers", flower_mesh, flower_mat, flower_xf, false,
			flower_col)

	# Mid-distance field tufts.  The animated DenseGrassFoliage only covers the
	# first 16-23 m, so beyond that the terrain read as a flat painted carpet.
	# These 4-blade tufts are one draw call, fade out by distance and give the
	# fields the broken, grassy texture visible in the reference.
	var tuft_target := 4200 if high_detail else (1800 if medium_detail else 700)
	var tuft_radius := 220.0 if high_detail else (145.0 if medium_detail else 95.0)
	var tuft_base := Color(0.15, 0.20, 0.08)
	var tuft_tip := Color(0.36, 0.42, 0.18)
	match map_name:
		"steppe":
			tuft_base = Color(0.30, 0.27, 0.13)
			tuft_tip = Color(0.60, 0.52, 0.25)
		"industrial":
			tuft_base = Color(0.20, 0.22, 0.10)
			tuft_tip = Color(0.44, 0.42, 0.20)
		"wetlands":
			tuft_base = Color(0.12, 0.17, 0.07)
			tuft_tip = Color(0.30, 0.38, 0.15)
	var tuft_mesh: ArrayMesh = VEGETATION.tuft_mesh()
	if tuft_mesh == null:
		tuft_mesh = FOLIAGE.create_grass_mesh(4)
	var tuft_mat := ShaderMaterial.new()
	tuft_mat.shader = GRASS_SHADER
	tuft_mat.set_shader_parameter("grass_base_color",
			Vector3(tuft_base.r, tuft_base.g, tuft_base.b))
	tuft_mat.set_shader_parameter("grass_tip_color",
			Vector3(tuft_tip.r, tuft_tip.g, tuft_tip.b))
	tuft_mat.set_shader_parameter("wind_strength", 0.18)
	var tuft_xf: Array = []
	tries = tuft_target * 4
	while tuft_xf.size() < tuft_target and tries > 0:
		tries -= 1
		var x := rng.randf_range(-tuft_radius, tuft_radius)
		var z := rng.randf_range(-tuft_radius, tuft_radius)
		var y := _height(map_name, x, z)
		if y < wl + 0.15:
			continue
		var s := rng.randf_range(0.8, 1.9)
		tuft_xf.append(Transform3D(
				Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(
						Vector3(s, rng.randf_range(0.9, 1.6), s)),
				Vector3(x, y, z)))
	var tuft_node := _multimesh(root, "FieldTufts", tuft_mesh, tuft_mat, tuft_xf, false)
	if tuft_node != null:
		tuft_node.visibility_range_end = tuft_radius + 20.0
		tuft_node.visibility_range_end_margin = 20.0
	print("[GroundDetail] lvl=", q_lvl, " rocks=", rock_xf.size(),
			" flowers=", flower_xf.size(), " scrub=", bush_xf.size(),
			" tufts=", tuft_xf.size(), " radii=", rock_radius, "/",
			flower_radius, "/", bush_radius, "/", tuft_radius)


## Small-scale war debris across the whole map: broken concrete, splintered
## planks and bent rebar.  Three MultiMeshes (one draw call each) and no
## collision - it is ground clutter that sells scale without costing physics.
static func _build_debris(root: Node3D, map_name: String) -> void:
	if OS.has_environment("QA_NO_PROPS"):
		return
	var q_lvl := QualityManager.get_active_level()
	var per_site := 26 if q_lvl == QualityManager.Level.HIGH else \
			(10 if q_lvl == QualityManager.Level.MEDIUM else 3)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(map_name) + 5150
	var wl := water_level(map_name)
	var centers: Array = []
	match map_name:
		"industrial":
			centers = [Vector2(50, 80), Vector2(-120, -40), Vector2(-30, -120),
					Vector2(60, -80), Vector2(168, 86), Vector2(24, 176),
					Vector2(-210, 20), Vector2(120, -30), Vector2(-260, 60),
					Vector2(240, 120)]
		"village":
			centers = [Vector2(20, -70), Vector2(-210, 90), Vector2(-112, 188),
					Vector2(66, 70), Vector2(104, 46), Vector2(138, 70),
					Vector2(-60, 140), Vector2(160, 150), Vector2(-140, -140),
					Vector2(180, 10)]
		"wetlands":
			centers = [Vector2(10, 54), Vector2(30, 36), Vector2(0, -90),
					Vector2(-60, 150), Vector2(-230, 20), Vector2(250, 15),
					Vector2(120, -90), Vector2(-120, -40), Vector2(180, -140),
					Vector2(200, 130)]
		_:
			centers = [Vector2(52, 150), Vector2(30, 132), Vector2(-170, -110),
					Vector2(-60, -25), Vector2(95, -100), Vector2(195, -55),
					Vector2(-240, -20), Vector2(-205, 40), Vector2(235, -40),
					Vector2(40, -90)]
	# Random clusters keep the treatment from collapsing into islands.
	for i in range(7):
		centers.append(Vector2(rng.randf_range(-245.0, 245.0),
				rng.randf_range(-245.0, 245.0)))

	var chunk_xf: Array = []
	var chunk_col: Array = []
	var plank_xf: Array = []
	var plank_col: Array = []
	var rebar_xf: Array = []
	for c in centers:
		var cp: Vector2 = c
		for i in range(per_site):
			var a := rng.randf_range(0.0, TAU)
			var r := sqrt(rng.randf()) * 9.0
			var p := cp + Vector2(cos(a) * r, sin(a) * r)
			var y := _height(map_name, p.x, p.y)
			if y < wl + 0.05:
				continue
			var roll := rng.randf()
			if roll < 0.62:
				var s := Vector3(rng.randf_range(0.15, 0.65),
						rng.randf_range(0.06, 0.24), rng.randf_range(0.15, 0.55))
				var b := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(s)
				chunk_xf.append(Transform3D(b, Vector3(p.x, y + s.y * 0.5, p.y)))
				var g := rng.randf_range(0.42, 0.66)
				chunk_col.append(Color(g * 1.03, g, g * 0.94))
			elif roll < 0.86:
				var s := Vector3(rng.randf_range(1.4, 3.2),
						rng.randf_range(0.05, 0.11), rng.randf_range(0.12, 0.28))
				var b := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(s)
				plank_xf.append(Transform3D(b, Vector3(p.x, y + 0.08, p.y)))
				var w := rng.randf_range(0.34, 0.54)
				plank_col.append(Color(w * 1.05, w * 0.92, w * 0.80))
			else:
				var b := Basis(Vector3.UP, rng.randf_range(0.0, TAU)) \
						* Basis(Vector3.RIGHT, PI * 0.5) \
						* Basis().scaled(Vector3(0.025, rng.randf_range(1.0, 3.0), 0.025))
				rebar_xf.append(Transform3D(b, Vector3(p.x, y + 0.05, p.y)))

	var chunk_mesh := BoxMesh.new()
	chunk_mesh.size = Vector3.ONE
	var chunk_mat: StandardMaterial3D = (_pbr("concrete", Color(0.92, 0.92, 0.90), 0.55) as StandardMaterial3D).duplicate() as StandardMaterial3D
	chunk_mat.vertex_color_use_as_albedo = true
	_multimesh(root, "RubbleChunks", chunk_mesh, chunk_mat, chunk_xf, false, chunk_col)

	var plank_mesh := BoxMesh.new()
	plank_mesh.size = Vector3.ONE
	var plank_mat: StandardMaterial3D = (_pbr("wood", Color(0.82, 0.72, 0.58), 0.50) as StandardMaterial3D).duplicate() as StandardMaterial3D
	plank_mat.vertex_color_use_as_albedo = true
	_multimesh(root, "BrokenPlanks", plank_mesh, plank_mat, plank_xf, false, plank_col)

	var rebar_mesh := CylinderMesh.new()
	rebar_mesh.top_radius = 1.0
	rebar_mesh.bottom_radius = 1.0
	rebar_mesh.height = 1.0
	rebar_mesh.radial_segments = 6
	rebar_mesh.rings = 1
	_multimesh(root, "Rebar", rebar_mesh, _mat(Color(0.32, 0.19, 0.12), 0.7, 0.2),
			rebar_xf, false)


## Blender-authored set dressing: 20 prop types scattered per map, one
## MultiMesh per type (20 draw calls) and a single concave collider built from
## their approximate boxes.
static func _build_props(root: Node3D, map_name: String) -> void:
	if OS.has_environment("QA_NO_PROPS"):
		return
	var meshes := PROP_ASSETS.meshes()
	if meshes.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(map_name) + 2027
	var water := water_level(map_name)
	var q := QualityManager.get_active_level()
	var per_type := 5 if q == QualityManager.Level.HIGH else \
			(2 if q == QualityManager.Level.MEDIUM else 1)
	var is_combat := false
	var st_p := Engine.get_main_loop() as SceneTree
	if st_p != null and st_p.root != null:
		var gp := st_p.root.get_node_or_null("Global")
		if gp != null:
			is_combat = (gp.get("play_mode") == 1)
	if not is_combat:
		per_type = 1
	var boxes: Array = []
	var prop_mat := StandardMaterial3D.new()
	prop_mat.vertex_color_use_as_albedo = true
	prop_mat.roughness = 0.9
	prop_mat.metallic = 0.08
	# Weak presets keep the ten most common prop types (one draw call each) and
	# drop the long tail of rare crates/barrels.  This is 10 fewer draws on the
	# 60 FPS UHD profiles while the battlefield landmarks stay untouched.
	var prop_names: Array = meshes.keys()
	if q == QualityManager.Level.LOW and prop_names.size() > 10:
		prop_names = prop_names.slice(0, 10)
	for prop_name in prop_names:
		var mesh: Mesh = meshes[prop_name]
		var xfs: Array = []
		var half: Vector3 = PROP_ASSETS.half_extents(prop_name)
		var tries := 0
		while xfs.size() < per_type and tries < 120:
			tries += 1
			var x := rng.randf_range(-250.0, 250.0)
			var z := rng.randf_range(-250.0, 250.0)
			if _tutorial_clear_zone(x, z):
				continue
			if _hall_clear_zone(map_name, x, z) or _structure_clear_zone(map_name, x, z):
				continue
			var h := _height(map_name, x, z)
			if h < water + 0.9:
				continue
			if Vector2(x, z).distance_to(Vector2(0.0, 220.0)) < 22.0:
				continue
			var hx := _height(map_name, x + 2.0, z) - _height(map_name, x - 2.0, z)
			var hz := _height(map_name, x, z + 2.0) - _height(map_name, x, z - 2.0)
			if absf(hx) + absf(hz) > 2.4:
				continue
			var s := rng.randf_range(0.85, 1.15)
			var yaw := rng.randf_range(0.0, TAU)
			xfs.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)),
					Vector3(x, h, z)))
			boxes.append({
				"pos": Vector3(x, h + half.y * s, z),
				"size": Vector3(half.x * 2.0 * s, half.y * 2.0 * s,
						half.z * 2.0 * s),
			})
		if xfs.is_empty():
			continue
		var node := _multimesh(root, "Prop_" + prop_name, mesh, prop_mat, xfs, false)
		if node != null:
			node.visibility_range_end = 600.0
			node.visibility_range_end_margin = 60.0
	if boxes.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = "PropCollision"
	body.collision_layer = 1
	body.collision_mask = 1
	var unit := BoxShape3D.new()
	unit.size = Vector3.ONE
	for b in boxes:
		var data: Dictionary = b
		var col := CollisionShape3D.new()
		col.shape = unit
		col.position = data["pos"]
		col.scale = data["size"]
		body.add_child(col)
	root.add_child(body)


static func _build_far_impostors(root: Node3D, map_name: String) -> void:
	# The dark octahedral impostors read as floating shards on the horizon.
	# Detailed Blender trees already cover the playable field; keep the horizon
	# clean instead of adding geometric blobs.
	return
	@warning_ignore("unreachable_code")
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(map_name) + 907
	var mesh := _octahedron_mesh()
	var mat := _mat(Color(0.16, 0.23, 0.12), 1.0)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var transforms: Array = []
	for i in range(1500):
		# Annulus from 400 m to 2500 m, weighted towards the near band.
		var angle := rng.randf_range(0.0, TAU)
		var radius := 400.0 + pow(rng.randf(), 1.6) * 2100.0
		var x := cos(angle) * radius
		var z := sin(angle) * radius
		var h := _height(map_name, clampf(x, -512.0, 512.0), clampf(z, -512.0, 512.0))
		# Outside the playable terrain, keep the horizon line believable.
		if absf(x) > 500.0 or absf(z) > 500.0:
			h = 0.0 + _fbm(x * 0.002, z * 0.002, 2) * 9.0
		# Small, hazy silhouettes: the old 30-60 m octahedra read as dark
		# shards floating over the midground once the camera looked south.
		var s := rng.randf_range(3.5, 6.5)
		var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(
				Vector3(s, s * rng.randf_range(1.2, 1.9), s))
		transforms.append(Transform3D(basis, Vector3(x, h + s * 0.9, z)))
	var mmi := _multimesh(root, "FarTreeLine", mesh, mat, transforms, false)
	if mmi != null:
		mmi.visibility_range_begin = 650.0
		mmi.visibility_range_begin_margin = 40.0
		mmi.visibility_range_end = 2500.0
		mmi.visibility_range_end_margin = 200.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


static func _octahedron_mesh() -> ArrayMesh:
	var verts := PackedVector3Array([
		Vector3(0, 1, 0), Vector3(0, -1, 0),
		Vector3(1, 0, 0), Vector3(-1, 0, 0),
		Vector3(0, 0, 1), Vector3(0, 0, -1),
	])
	var indices := PackedInt32Array([
		0, 2, 4, 0, 4, 3, 0, 3, 5, 0, 5, 2,
		1, 4, 2, 1, 3, 4, 1, 5, 3, 1, 2, 5,
	])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# ===========================================================================
#  Small helpers
# ===========================================================================
static func _multimesh(root: Node3D, node_name: String, mesh: Mesh, mat: Material,
		transforms: Array, shadows: bool, colors: Array = []) -> MultiMeshInstance3D:
	if transforms.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.use_colors = not colors.is_empty()
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
		if mm.use_colors and i < colors.size():
			mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	if mat != null:
		mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)
	return mmi


static func _add_box(root: Node3D, pos: Vector3, size: Vector3, mat: Material,
		yaw: float = 0.0, collide: bool = true) -> Node3D:
	var box := BoxMesh.new()
	box.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.set_meta("batch_box", size)
	if not collide:
		mi.position = pos
		mi.rotation.y = yaw
		root.add_child(mi)
		return mi
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = yaw
	body.collision_layer = 1
	body.collision_mask = 1
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	root.add_child(body)
	return body


static func _add_ring(root: Node3D, pos: Vector3, radius: float, tube: float,
		mat: Material) -> MeshInstance3D:
	# A torus leaves the tower bore open; a CylinderMesh would cap it and block
	# the dive opening that the player specifically requested.
	var torus := TorusMesh.new()
	torus.inner_radius = maxf(radius - tube, 0.05)
	torus.outer_radius = radius + tube
	torus.rings = 24
	torus.ring_segments = 8
	var mi := MeshInstance3D.new()
	mi.mesh = torus
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(mi)
	return mi


static func _add_cylinder(root: Node3D, pos: Vector3, radius: float, height: float,
		mat: Material, yaw: float = 0.0, collide: bool = true) -> Node3D:
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 10
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.set_meta("batch_cyl", Vector3(radius, height, radius))
	if not collide:
		mi.position = pos
		mi.rotation.y = yaw
		root.add_child(mi)
		return mi
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = yaw
	body.collision_layer = 1
	body.collision_mask = 1
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	cs.shape = shape
	body.add_child(cs)
	root.add_child(body)
	return body


static func _add_prism(root: Node3D, pos: Vector3, size: Vector3, mat: Material,
		yaw: float = 0.0) -> void:
	var prism := PrismMesh.new()
	prism.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = prism
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = yaw
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.set_meta("batch_prism", size)
	root.add_child(mi)
	# Roofs used to be pure decoration: the drone flew straight through them.
	# A prism is convex, so its own convex hull is an exact collider.  The old
	# box shape matched the full bounds and left invisible wedges of collision
	# over the eaves, which stopped drones well above the visible roof.
	if OS.has_environment("QA_NO_ROOF_COLLISION"):
		return
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = yaw
	body.collision_layer = 1
	body.collision_mask = 1
	var col := CollisionShape3D.new()
	col.shape = prism.create_convex_shape()
	body.add_child(col)
	root.add_child(body)


## Hollow house shell with real door and window openings.  Every facade is
## split around the openings, so a small FPV drone can fly in through a window
## or the front door; the old box shell advertised windows but its collision
## was a solid block.
static func _add_house_shell(root: Node3D, p: Vector2, y: float, w: float,
		d: float, h: float, yaw: float, mat: Material) -> void:
	var t := 0.35
	var win_w := 2.4
	var win_bottom := 0.85
	var win_top := minf(h - 0.45, 2.75)
	if win_top <= win_bottom + 0.35:
		_add_box(root, Vector3(p.x, y + h * 0.5, p.y), Vector3(w, h, d), mat, yaw, true)
		return
	var base := Vector3(p.x, y, p.y)
	var basis := Basis(Vector3.UP, yaw)
	var win_h := win_top - win_bottom
	var off := maxf(minf(w * 0.30, w * 0.5 - win_w * 0.5 - 0.20), 0.20)
	# Front long facade (+Z): two windows and a real door in the middle.
	var front: Array[Rect2] = [Rect2(-win_w * 0.5, 0.0, win_w,
			minf(h - 0.30, 2.30))]
	for sx in [-1.0, 1.0]:
		front.append(Rect2(sx * off - win_w * 0.5, win_bottom, win_w, win_h))
	_add_wall_with_openings(root, base + basis * Vector3(0.0, 0.0, d * 0.5),
			yaw, w, h, t, mat, front)
	# Back long facade (-Z): three windows.
	var back: Array[Rect2] = []
	for cx in [-off, 0.0, off]:
		back.append(Rect2(cx - win_w * 0.5, win_bottom, win_w, win_h))
	_add_wall_with_openings(root, base + basis * Vector3(0.0, 0.0, -d * 0.5),
			yaw, w, h, t, mat, back)
	# Short facades (+/- X): one centred window each.
	for sx in [-1.0, 1.0]:
		var side: Array[Rect2] = [Rect2(-win_w * 0.5, win_bottom, win_w, win_h)]
		_add_wall_with_openings(root, base + basis * Vector3(sx * w * 0.5, 0.0, 0.0),
				yaw + PI * 0.5, d, h, t, mat, side)


## Generic solid-wall decomposition.  `openings` are Rect2s in wall-local
## coordinates: x is measured from the wall centre, y from its base.  The
## remaining wall is emitted as boxes on ONE StaticBody3D, so a building costs
## four bodies instead of dozens while the openings stay genuinely passable.
static func _add_wall_with_openings(root: Node3D, origin: Vector3, yaw: float,
		width: float, height: float, thickness: float, mat: Material,
		openings: Array, frame_mat: Material = null) -> void:
	var clean: Array[Rect2] = []
	for o in openings:
		var r := o as Rect2
		var x0: float = clampf(r.position.x, -width * 0.5, width * 0.5)
		var x1: float = clampf(r.position.x + r.size.x, -width * 0.5, width * 0.5)
		var y0: float = clampf(r.position.y, 0.0, height)
		var y1: float = clampf(r.position.y + r.size.y, 0.0, height)
		if x1 - x0 > 0.05 and y1 - y0 > 0.05:
			clean.append(Rect2(x0, y0, x1 - x0, y1 - y0))
	var xs: Array[float] = [-width * 0.5, width * 0.5]
	for r in clean:
		xs.append(r.position.x)
		xs.append(r.position.x + r.size.x)
	xs.sort()
	var body := StaticBody3D.new()
	body.position = origin
	body.rotation.y = yaw
	body.collision_layer = 1
	body.collision_mask = 1
	root.add_child(body)
	var basis := Basis(Vector3.UP, yaw)
	for i in range(xs.size() - 1):
		var x0: float = xs[i]
		var x1: float = xs[i + 1]
		if x1 - x0 < 0.04:
			continue
		var mid := (x0 + x1) * 0.5
		var bands: Array[Vector2] = []
		for r in clean:
			if mid <= r.position.x + 0.001 or mid >= r.position.x + r.size.x - 0.001:
				continue
			bands.append(Vector2(r.position.y, r.position.y + r.size.y))
		bands.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		var y := 0.0
		for band in bands:
			if band.x > y + 0.02:
				_add_wall_box(body, Vector3(mid, (y + band.x) * 0.5, 0.0),
						Vector3(x1 - x0, band.x - y, thickness), mat)
			y = maxf(y, band.y)
		if height > y + 0.02:
			_add_wall_box(body, Vector3(mid, (y + height) * 0.5, 0.0),
					Vector3(x1 - x0, height - y, thickness), mat)
	if frame_mat == null:
		return
	for r in clean:
		_add_opening_frame(root, origin, basis, yaw, r, thickness, frame_mat)


static func _add_wall_box(body: StaticBody3D, center: Vector3, size: Vector3,
		mat: Material) -> void:
	var box := BoxMesh.new()
	box.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.material_override = mat
	mi.position = center
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.set_meta("batch_box", size)
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = center
	body.add_child(cs)


static func _add_opening_frame(root: Node3D, origin: Vector3, basis: Basis,
		yaw: float, r: Rect2, thickness: float, mat: Material) -> void:
	var depth := thickness + 0.10
	var edge := 0.10
	var cx := r.position.x + r.size.x * 0.5
	var top := r.position.y + r.size.y
	_add_box(root, origin + basis * Vector3(cx, top + edge * 0.5, 0.0),
			Vector3(r.size.x + edge * 2.0, edge, depth), mat, yaw, false)
	if r.position.y > 0.15:
		_add_box(root, origin + basis * Vector3(cx, r.position.y - edge * 0.5, 0.0),
				Vector3(r.size.x + edge * 2.0, edge, depth), mat, yaw, false)
	for sx in [-1.0, 1.0]:
		_add_box(root, origin + basis * Vector3(
				cx + sx * (r.size.x * 0.5 + edge * 0.5),
				r.position.y + r.size.y * 0.5, 0.0),
				Vector3(edge, r.size.y, depth), mat, yaw, false)


## Merge the hundreds of individual prop boxes, cylinders and roof prisms into
## a handful of MultiMeshes: one per material and primitive type.
##
## Every building, wall, pipe and container used to be its own MeshInstance3D;
## the village alone issued ~540 draw calls.  These props are static and are
## never referenced individually after creation, so they can be rendered from a
## single MultiMesh per material.  Collision is untouched: the StaticBody3D
## nodes and their shapes stay exactly where they were.
static func _fix_untextured_white(root: Node3D) -> void:
	# Scan all visual meshes across the map.  Replace any missing, untextured,
	# or pure-white/light-grey placeholder materials with proper textured PBR
	# materials so no building or prop reads as plain white.
	var conc_alb := load("res://Assets/frontline/textures/concrete_albedo.png") as Texture2D
	var conc_nrm := load("res://Assets/frontline/textures/concrete_normal.png") as Texture2D
	var conc_rgh := load("res://Assets/frontline/textures/concrete_rough.png") as Texture2D
	var steel_alb := load("res://Assets/frontline/textures/steel_albedo.png") as Texture2D
	var steel_nrm := load("res://Assets/frontline/textures/steel_normal.png") as Texture2D
	var steel_rgh := load("res://Assets/frontline/textures/steel_rough.png") as Texture2D
	var wood_alb := load("res://Assets/frontline/textures/wood_albedo.png") as Texture2D
	var wood_nrm := load("res://Assets/frontline/textures/wood_normal.png") as Texture2D

	var cached_conc := StandardMaterial3D.new()
	cached_conc.albedo_color = Color(0.74, 0.72, 0.68)
	cached_conc.albedo_texture = conc_alb
	cached_conc.normal_enabled = true
	cached_conc.normal_texture = conc_nrm
	cached_conc.roughness_texture = conc_rgh
	cached_conc.roughness = 0.88
	cached_conc.uv1_triplanar = true
	cached_conc.uv1_world_triplanar = true
	cached_conc.uv1_scale = Vector3(0.22, 0.22, 0.22)
	cached_conc.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC

	var cached_steel := StandardMaterial3D.new()
	cached_steel.albedo_color = Color(0.42, 0.44, 0.46)
	cached_steel.albedo_texture = steel_alb
	cached_steel.normal_enabled = true
	cached_steel.normal_texture = steel_nrm
	cached_steel.roughness_texture = steel_rgh
	cached_steel.roughness = 0.55
	cached_steel.metallic = 0.60
	cached_steel.uv1_triplanar = true
	cached_steel.uv1_world_triplanar = true
	cached_steel.uv1_scale = Vector3(0.25, 0.25, 0.25)
	cached_steel.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC

	var cached_wood := StandardMaterial3D.new()
	cached_wood.albedo_color = Color(0.55, 0.46, 0.35)
	cached_wood.albedo_texture = wood_alb
	cached_wood.normal_enabled = true
	cached_wood.normal_texture = wood_nrm
	cached_wood.roughness = 0.82
	cached_wood.uv1_triplanar = true
	cached_wood.uv1_world_triplanar = true
	cached_wood.uv1_scale = Vector3(0.30, 0.30, 0.30)
	cached_wood.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC

	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var n_low := (String(mi.name) + " " + String(mi.get_parent().name)).to_lower()
		# Skip natural terrain/foliage/sky/water elements
		if n_low.contains("grass") or n_low.contains("leaf") or n_low.contains("pine") \
				or n_low.contains("water") or n_low.contains("horizon") or n_low.contains("sky") \
				or n_low.contains("decal") or n_low.contains("cloud") or n_low.contains("mist"):
			continue

		for s in range(mi.mesh.get_surface_count()):
			var m: Material = mi.get_surface_override_material(s)
			if m == null:
				m = mi.mesh.surface_get_material(s)

			var needs_fix := false
			if m == null:
				needs_fix = true
			elif m is StandardMaterial3D:
				var sm := m as StandardMaterial3D
				if sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or sm.emission_enabled:
					continue
				if sm.albedo_texture == null:
					var c := sm.albedo_color
					var bright := (c.r + c.g + c.b) / 3.0
					var rname := sm.resource_name.to_lower()
					if bright > 0.65 or c.r > 0.75 or rname.contains("white") \
							or rname.contains("default") or rname.contains("material"):
						needs_fix = true

			if needs_fix:
				var target_mat := cached_conc
				if n_low.contains("steel") or n_low.contains("metal") or n_low.contains("iron") \
						or n_low.contains("roof") or n_low.contains("pipe") or n_low.contains("rail") \
						or n_low.contains("tank") or n_low.contains("crane"):
					target_mat = cached_steel
				elif n_low.contains("wood") or n_low.contains("timber") or n_low.contains("fence") \
						or n_low.contains("hay") or n_low.contains("log") or n_low.contains("pallet"):
					target_mat = cached_wood
				mi.set_surface_override_material(s, target_mat)


static func _batch_static_props(root: Node3D) -> void:
	var groups := {}
	var victims: Array[Node] = []
	_collect_batchable(root, root, groups, victims)
	if victims.is_empty():
		return
	for node in victims:
		if is_instance_valid(node):
			node.get_parent().remove_child(node)
			node.queue_free()

	var unit_box := BoxMesh.new()
	unit_box.size = Vector3.ONE
	var unit_cyl := CylinderMesh.new()
	unit_cyl.top_radius = 1.0
	unit_cyl.bottom_radius = 1.0
	unit_cyl.height = 1.0
	unit_cyl.radial_segments = 10
	var unit_prism := PrismMesh.new()
	unit_prism.size = Vector3.ONE
	var meshes := {"box": unit_box, "cyl": unit_cyl, "prism": unit_prism}

	var index := 0
	for key in groups:
		var g: Dictionary = groups[key]
		var xforms: Array = g["xforms"]
		if xforms.is_empty():
			continue
		var use_color := bool(g.get("use_color", false))
		var out_mat: Material = g["mat"]
		if use_color:
			# Many props share one texture/roughness but differ only by a flat
			# albedo tint.  Bake the tint into the instance colour so all of
			# them fit in one MultiMesh instead of one material batch each.
			var tinted := (out_mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			tinted.albedo_color = Color.WHITE
			tinted.vertex_color_use_as_albedo = true
			out_mat = tinted
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[g["kind"]]
		mm.use_colors = use_color
		mm.instance_count = xforms.size()
		var colors: Array = g.get("colors", [])
		for j in range(xforms.size()):
			mm.set_instance_transform(j, xforms[j])
			if use_color and j < colors.size():
				mm.set_instance_color(j, colors[j])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "BatchedProps%d" % index
		mmi.multimesh = mm
		mmi.material_override = out_mat
		mmi.cast_shadow = int(g.get("shadow", GeometryInstance3D.SHADOW_CASTING_SETTING_ON))
		root.add_child(mmi)
		index += 1
	print("[FrontlineTerrain] batched ", victims.size(), " props into ",
			index, " draw calls")


## Merge the leftover single-surface decoration created directly under the
## terrain root.  These are opaque StandardMaterial3D meshes (pipes, yard
## clutter, rail parts, puddles, wire meshes) that used to cost one draw call
## each.  They are grouped by material, shadow mode and a 128 m spatial cell,
## so frustum culling still drops whole cells while the visible set needs only
## a handful of draws.  Animated, transparent, multi-surface and collision-only
## meshes are deliberately left alone.
## Fast SurfaceTool batcher for authored static scenes (the city block, course
## gates and track furniture).  Unlike the per-vertex merge above, this copies
## every surface through SurfaceTool.append_from, which stays in C++ and turns a
## multi-minute city rebuild into a fraction of a second.  All surfaces that
## share a StandardMaterial3D, shadow mode and vertex format are combined.
## Last-chance material pass for large flat-coloured buildings/roofs that the
## source kit shipped without an albedo map.  Small props and everything that
## already has a texture are left untouched.
static func _texture_flat_large_meshes(root: Node3D) -> void:
	var albedo := load("res://Assets/handcrafted/textures/concrete_albedo.png") as Texture2D
	var normal := load("res://Assets/handcrafted/textures/concrete_normal.png") as Texture2D
	var rough := load("res://Assets/handcrafted/textures/concrete_rough.png") as Texture2D
	var steel_albedo := load("res://Assets/frontline/factory_hall_steel_albedo.png") as Texture2D
	var steel_normal := load("res://Assets/frontline/factory_hall_steel_normal.png") as Texture2D
	var steel_rough := load("res://Assets/frontline/factory_hall_steel_rough.png") as Texture2D
	if albedo == null:
		return
	var seen := {}
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var nm := String(mi.name).to_lower()
		if nm.contains("horizon") or nm.contains("mountain") or nm.contains("terrain") \
				or nm.contains("water") or nm.contains("sky") or nm.contains("tree") \
				or nm.contains("leaf") or nm.contains("grass") or nm.contains("crop") \
				or nm.contains("field") or nm.contains("road") or nm.contains("decal"):
			continue
		# The authored industrial yard ships its shipping containers as flat
		# coloured boxes named cont0..cont8.  They are only ~6 m long, so the
		# large-mesh pass used to skip them and they read as plastic blocks.
		var is_container := nm.begins_with("cont") and steel_albedo != null
		var box: AABB = mi.global_transform * mi.get_aabb()
		if not is_container and maxf(box.size.x, maxf(box.size.y, box.size.z)) < 8.0:
			continue
		for s in range(mi.mesh.get_surface_count()):
			var mat := mi.get_surface_override_material(s) as StandardMaterial3D
			if mat == null:
				mat = mi.mesh.surface_get_material(s) as StandardMaterial3D
			if mat == null or mat.albedo_texture != null:
				continue
			if mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or mat.emission_enabled:
				continue
			var id := mat.get_instance_id()
			if seen.has(id):
				continue
			seen[id] = true
			if is_container:
				mat.albedo_texture = steel_albedo
				mat.normal_texture = steel_normal
				mat.roughness_texture = steel_rough
				mat.uv1_triplanar = true
				mat.uv1_world_triplanar = true
				mat.uv1_scale = Vector3(0.30, 0.30, 0.30)
				mat.roughness = 0.78
				mat.metallic = 0.25
				continue
			mat.albedo_texture = albedo
			mat.normal_texture = normal
			mat.roughness_texture = rough
			mat.uv1_triplanar = true
			mat.uv1_world_triplanar = true
			mat.uv1_scale = Vector3(0.16, 0.16, 0.16)
			mat.albedo_color = mat.albedo_color.lerp(Color(0.72, 0.68, 0.60), 0.7)
## alive when batch_static_fast frees the visual meshes, and render the shells
## two-sided so the Boolean-cut openings are visible from inside.
static func prepare_city(city: Node3D) -> void:
	var moved := 0
	for child in city.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			var mat := mi.get_surface_override_material(s) as StandardMaterial3D
			if mat == null:
				mat = mi.mesh.surface_get_material(s) as StandardMaterial3D
			if mat != null:
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				# The compact fpv_city kit ships with a golden baked facade that
				# reads as a desert town when scaled up.  Keep the white-city
				# language of the original City map: flat light concrete.
				var tex_path := ""
				if mat.albedo_texture != null:
					tex_path = mat.albedo_texture.resource_path.to_lower()
				# Some kit surfaces (roof caps, door reveals, the far block) ship
				# with no albedo map at all.  Every building mesh gets the same
				# concrete set so no roof reads as a flat white slab.
				var is_building := String(mi.name).begins_with("Bld")
				if mat.resource_name.to_lower().contains("build") \
						or tex_path.contains("build") \
						or (is_building and mat.albedo_texture == null):
					var albedo := load("res://Assets/handcrafted/textures/concrete_albedo.png") as Texture2D
					var normal := load("res://Assets/handcrafted/textures/concrete_normal.png") as Texture2D
					var rough := load("res://Assets/handcrafted/textures/concrete_rough.png") as Texture2D
					mat.albedo_texture = albedo
					mat.normal_texture = normal
					mat.roughness_texture = rough
					mat.uv1_triplanar = true
					mat.uv1_world_triplanar = true
					mat.uv1_scale = Vector3(0.14, 0.14, 0.14)
					mat.albedo_color = Color(0.80, 0.81, 0.83)
					mat.roughness = 0.9
					mat.metallic = 0.0
				# The kit also ships large flat lawn slabs and roof/deck caps with
				# no albedo map.  Texture the green slabs as grass and the neutral
				# ones as concrete; coloured glass/metal details are left alone.
				var span := maxf(mi.get_aabb().size.x, maxf(mi.get_aabb().size.y,
						mi.get_aabb().size.z))
				var col := mat.albedo_color
				var is_green := col.g > col.r * 1.25 and col.g > col.b * 1.15 \
						and col.g > 0.10
				if mat.albedo_texture == null and (is_green or span > 8.0):
					var neutral := maxf(col.r, maxf(col.g, col.b)) - \
							minf(col.r, minf(col.g, col.b)) < 0.13
					if is_green:
						var ga := load("res://Assets/textures/terrain/grass_albedo.png") as Texture2D
						var gn := load("res://Assets/textures/terrain/grass_normal.png") as Texture2D
						var gr := load("res://Assets/textures/terrain/grass_rough.png") as Texture2D
						if ga != null:
							mat.albedo_texture = ga
							mat.normal_texture = gn
							mat.roughness_texture = gr
							mat.uv1_triplanar = true
							mat.uv1_world_triplanar = true
							mat.uv1_scale = Vector3(0.09, 0.09, 0.09)
							mat.albedo_color = col.lerp(Color(0.42, 0.52, 0.32), 0.35)
							mat.roughness = 0.95
					elif neutral:
						var ca := load("res://Assets/handcrafted/textures/concrete_albedo.png") as Texture2D
						var cn := load("res://Assets/handcrafted/textures/concrete_normal.png") as Texture2D
						var cr := load("res://Assets/handcrafted/textures/concrete_rough.png") as Texture2D
						if ca != null:
							mat.albedo_texture = ca
							mat.normal_texture = cn
							mat.roughness_texture = cr
							mat.uv1_triplanar = true
							mat.uv1_world_triplanar = true
							mat.uv1_scale = Vector3(0.14, 0.14, 0.14)
							mat.albedo_color = col.lerp(Color(0.76, 0.76, 0.77), 0.5)
							mat.roughness = 0.9
		# city_environment built one trimesh/box body per mesh; reparent it to
		# the city root (keeping its world transform) before the visual merge.
		var col := mi.get_node_or_null("__city_collision") as Node3D
		if col != null:
			col.reparent(city, true)
			moved += 1
	print("[CityPrep] collision moved=", moved)


static func batch_static_fast(root: Node3D) -> void:
	var groups := {}
	var victims: Array[Node] = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.visible:
			continue
		if not mi.skeleton.is_empty():
			continue
		if mi.mesh is ImmediateMesh:
			continue
		if mi.mesh is ArrayMesh and (mi.mesh as ArrayMesh).get_blend_shape_count() > 0:
			continue
		var xf := root.global_transform.affine_inverse() * mi.global_transform
		var appended := false
		for s in range(mi.mesh.get_surface_count()):
			var mat: Material = mi.material_override
			if mat == null:
				mat = mi.get_surface_override_material(s)
			if mat == null:
				mat = mi.mesh.surface_get_material(s)
			var sm := mat as StandardMaterial3D
			if sm == null or sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				continue
			var arrays := mi.mesh.surface_get_arrays(s)
			if arrays == null or arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
				continue
			var flags := "%d%d%d" % [
				1 if arrays[Mesh.ARRAY_TEX_UV] != null else 0,
				1 if arrays[Mesh.ARRAY_COLOR] != null else 0,
				1 if arrays[Mesh.ARRAY_TANGENT] != null else 0]
			var key := "%s|%d|%.1f|%s" % [_material_key(sm), mi.cast_shadow,
					mi.visibility_range_end, flags]
			if not groups.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				groups[key] = {"mat": sm, "shadow": mi.cast_shadow,
						"end": mi.visibility_range_end, "st": st, "n": 0}
			var st: SurfaceTool = groups[key]["st"]
			st.append_from(mi.mesh, s, xf)
			groups[key]["n"] = int(groups[key]["n"]) + 1
			appended = true
		if appended:
			victims.append(mi)
	var batches := 0
	for key in groups:
		var g: Dictionary = groups[key]
		if int(g["n"]) == 0:
			continue
		var st: SurfaceTool = g["st"]
		var mesh := st.commit()
		if mesh == null:
			continue
		mesh.surface_set_material(0, g["mat"])
		var node := MeshInstance3D.new()
		node.name = "FastBatch%d" % batches
		node.mesh = mesh
		node.cast_shadow = int(g["shadow"])
		node.visibility_range_end = float(g["end"])
		root.add_child(node)
		batches += 1
	for v in victims:
		if is_instance_valid(v):
			v.queue_free()
	print("[FrontlineTerrain] fast-merged ", victims.size(),
			" static meshes into ", batches, " draw calls")


static func _batch_static_meshes(root: Node3D, unbounded := false) -> void:
	var groups := {}
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null or mi.mesh.get_surface_count() != 1:
			continue
		if mi.mesh is ImmediateMesh:
			continue
		if not mi.visible or mi.has_meta("batch_box") or mi.has_meta("batch_cyl") \
				or mi.has_meta("batch_prism") or mi.has_meta("no_batch"):
			continue
		if mi.mesh is ArrayMesh \
				and (mi.mesh as ArrayMesh).surface_get_primitive_type(0) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		if not mi.skeleton.is_empty():
			continue
		if mi.mesh is ArrayMesh and (mi.mesh as ArrayMesh).get_blend_shape_count() > 0:
			continue
		var box: AABB = mi.global_transform * mi.get_aabb()
		if not unbounded and maxf(box.size.x, maxf(box.size.y, box.size.z)) > 1200.0:
			continue
		var arrays := mi.mesh.surface_get_arrays(0)
		if arrays[Mesh.ARRAY_VERTEX] == null or arrays[Mesh.ARRAY_NORMAL] == null:
			continue
		if arrays[Mesh.ARRAY_TEX_UV2] != null or arrays[Mesh.ARRAY_CUSTOM0] != null:
			continue
		var mat: Material = mi.material_override
		if mat == null:
			mat = mi.mesh.surface_get_material(0)
		var sm := mat as StandardMaterial3D
		if sm == null or sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			continue
		var cell := Vector2i(0, 0)
		if not unbounded:
			# Coarser 512 m merge cells: the map is 1 km, so 16 cells still cull
			# well while halving the number of static batches.  The authored city
			# is one compact block, so it uses a single unbounded group instead.
			cell = Vector2i(int(floor(mi.global_position.x / 307.2)),
					int(floor(mi.global_position.z / 307.2)))
		var flags := "%d%d%d" % [
			1 if arrays[Mesh.ARRAY_TEX_UV] != null else 0,
			1 if arrays[Mesh.ARRAY_COLOR] != null else 0,
			1 if arrays[Mesh.ARRAY_TANGENT] != null else 0]
		var key := "%d,%d|%s|%d|%s|%s|%.1f|%.1f" % [
			cell.x, cell.y, _material_key(sm), mi.cast_shadow, flags,
			str(mi.visibility_range_begin), mi.visibility_range_end,
			mi.visibility_range_end_margin]
		if not groups.has(key):
			groups[key] = {
				"mat": sm, "shadow": mi.cast_shadow,
				"verts": PackedVector3Array(), "norms": PackedVector3Array(),
				"uvs": PackedVector2Array(), "colors": PackedColorArray(),
				"tangents": PackedFloat32Array(), "indices": PackedInt32Array(),
				"has_uv": arrays[Mesh.ARRAY_TEX_UV] != null,
				"has_color": arrays[Mesh.ARRAY_COLOR] != null,
				"has_tangent": arrays[Mesh.ARRAY_TANGENT] != null,
				"begin": mi.visibility_range_begin,
				"end": mi.visibility_range_end,
				"margin": mi.visibility_range_end_margin,
				"fade": mi.visibility_range_fade_mode,
				"src": [],
			}
		var g: Dictionary = groups[key]
		var xf := root.global_transform.affine_inverse() * mi.global_transform
		# A handful of authored Village decorations carry a zero scale on one
		# axis (invisible helper meshes).  Inverting that basis spams
		# "Condition det == 0" six times per load; skip them instead.
		if absf(xf.basis.determinant()) < 1e-7:
			# Zero-scale helper meshes are invisible anyway, but the renderer
			# still issued a draw call for each one.
			mi.visible = false
			continue
		var nb := xf.basis.inverse().transposed()
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs = arrays[Mesh.ARRAY_TEX_UV]
		var colors = arrays[Mesh.ARRAY_COLOR]
		var tangents = arrays[Mesh.ARRAY_TANGENT]
		var idx = arrays[Mesh.ARRAY_INDEX]
		var gv: PackedVector3Array = g["verts"]
		var gn: PackedVector3Array = g["norms"]
		var gu: PackedVector2Array = g["uvs"]
		var gc: PackedColorArray = g["colors"]
		var gt: PackedFloat32Array = g["tangents"]
		var gi: PackedInt32Array = g["indices"]
		var base := gv.size()
		for i in range(verts.size()):
			gv.append(xf * verts[i])
			gn.append((nb * norms[i]).normalized())
			if g["has_uv"]:
				gu.append(uvs[i])
			if g["has_color"]:
				gc.append(colors[i])
			if g["has_tangent"]:
				var t := Vector3(tangents[i * 4], tangents[i * 4 + 1], tangents[i * 4 + 2])
				t = (xf.basis * t).normalized()
				gt.append(t.x)
				gt.append(t.y)
				gt.append(t.z)
				gt.append(tangents[i * 4 + 3])
		if idx == null:
			for i in range(verts.size()):
				gi.append(base + i)
		else:
			for i in range(idx.size()):
				gi.append(base + int(idx[i]))
		g["verts"] = gv
		g["norms"] = gn
		g["uvs"] = gu
		g["colors"] = gc
		g["tangents"] = gt
		g["indices"] = gi
		(g["src"] as Array).append(mi)

	var merged := 0
	var batches := 0
	for key in groups:
		var g: Dictionary = groups[key]
		var srcs: Array = g["src"]
		if srcs.size() < 2:
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = g["verts"]
		arrays[Mesh.ARRAY_NORMAL] = g["norms"]
		if g["has_uv"]:
			arrays[Mesh.ARRAY_TEX_UV] = g["uvs"]
		if g["has_color"]:
			arrays[Mesh.ARRAY_COLOR] = g["colors"]
		if g["has_tangent"]:
			arrays[Mesh.ARRAY_TANGENT] = g["tangents"]
		arrays[Mesh.ARRAY_INDEX] = g["indices"]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, g["mat"])
		var node := MeshInstance3D.new()
		node.name = "BatchedMesh%d" % batches
		node.mesh = mesh
		node.cast_shadow = int(g["shadow"])
		node.visibility_range_begin = float(g["begin"])
		node.visibility_range_end = float(g["end"])
		node.visibility_range_end_margin = float(g["margin"])
		node.visibility_range_fade_mode = int(g["fade"])
		root.add_child(node)
		batches += 1
		for source in srcs:
			if is_instance_valid(source):
				for child in source.get_children():
					if child is StaticBody3D:
						(child as Node3D).reparent(root, true)
				source.queue_free()
				merged += 1
	print("[FrontlineTerrain] merged ", merged, " decoration meshes into ",
			batches, " draw calls")


## Multi-surface GLB landmarks (cottages, warehouses, the factory kit) used to
## cost one draw call per surface and were skipped by the single-surface
## batcher.  This pass merges every surface by material into one mesh per
## material/cell and frees the source nodes.
static func _batch_multisurface_meshes(root: Node3D) -> void:
	var groups := {}
	var victims: Array[Node] = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null or mi.mesh.get_surface_count() < 2:
			continue
		if mi.mesh is ImmediateMesh:
			continue
		if not mi.visible or mi.has_meta("batch_box") or mi.has_meta("batch_cyl") \
				or mi.has_meta("batch_prism") or mi.has_meta("no_batch"):
			continue
		if not mi.skeleton.is_empty():
			continue
		if mi.mesh is ArrayMesh and (mi.mesh as ArrayMesh).get_blend_shape_count() > 0:
			continue
		var box: AABB = mi.global_transform * mi.get_aabb()
		if maxf(box.size.x, maxf(box.size.y, box.size.z)) > 80.0:
			continue
		var surfaces := []
		var ok := true
		for s in range(mi.mesh.get_surface_count()):
			if mi.mesh is ArrayMesh \
					and (mi.mesh as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				ok = false
				break
			var arrays := mi.mesh.surface_get_arrays(s)
			if arrays == null or arrays.is_empty() \
					or arrays[Mesh.ARRAY_VERTEX] == null \
					or arrays[Mesh.ARRAY_NORMAL] == null:
				ok = false
				break
			if arrays[Mesh.ARRAY_TEX_UV2] != null or arrays[Mesh.ARRAY_CUSTOM0] != null:
				ok = false
				break
			var mat: Material = mi.material_override
			if mat == null:
				mat = mi.get_surface_override_material(s)
			if mat == null:
				mat = mi.mesh.surface_get_material(s)
			var sm := mat as StandardMaterial3D
			if sm == null or sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				ok = false
				break
			surfaces.append({"arrays": arrays, "mat": sm})
		if not ok or surfaces.is_empty():
			continue
		var xf := root.global_transform.affine_inverse() * mi.global_transform
		var nb := xf.basis.inverse().transposed()
		var cell := Vector2i(int(floor(mi.global_position.x / 128.0)),
				int(floor(mi.global_position.z / 128.0)))
		for entry in surfaces:
			var arrays: Array = entry["arrays"]
			var sm: StandardMaterial3D = entry["mat"]
			var flags := "%d%d%d" % [
				1 if arrays[Mesh.ARRAY_TEX_UV] != null else 0,
				1 if arrays[Mesh.ARRAY_COLOR] != null else 0,
				1 if arrays[Mesh.ARRAY_TANGENT] != null else 0]
			var key := "%s|%d|%s|%s|%.1f|%.1f" % [
				_material_key(sm), mi.cast_shadow, flags,
				str(mi.visibility_range_begin), mi.visibility_range_end,
				mi.visibility_range_end_margin]
			if not groups.has(key):
				groups[key] = {
					"mat": sm, "shadow": mi.cast_shadow,
					"verts": PackedVector3Array(), "norms": PackedVector3Array(),
					"uvs": PackedVector2Array(), "colors": PackedColorArray(),
					"tangents": PackedFloat32Array(),
					"indices": PackedInt32Array(),
					"has_uv": arrays[Mesh.ARRAY_TEX_UV] != null,
					"has_color": arrays[Mesh.ARRAY_COLOR] != null,
					"has_tangent": arrays[Mesh.ARRAY_TANGENT] != null,
					"begin": mi.visibility_range_begin,
					"end": mi.visibility_range_end,
					"margin": mi.visibility_range_end_margin,
					"fade": mi.visibility_range_fade_mode,
				}
			var g: Dictionary = groups[key]
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var uvs = arrays[Mesh.ARRAY_TEX_UV]
			var colors = arrays[Mesh.ARRAY_COLOR]
			var tangents = arrays[Mesh.ARRAY_TANGENT]
			var idx = arrays[Mesh.ARRAY_INDEX]
			var gv: PackedVector3Array = g["verts"]
			var gn: PackedVector3Array = g["norms"]
			var gu: PackedVector2Array = g["uvs"]
			var gc: PackedColorArray = g["colors"]
			var gt: PackedFloat32Array = g["tangents"]
			var gi: PackedInt32Array = g["indices"]
			var base := gv.size()
			for i in range(verts.size()):
				gv.append(xf * verts[i])
				gn.append((nb * norms[i]).normalized())
				if g["has_uv"]:
					gu.append(uvs[i])
				if g["has_color"]:
					gc.append(colors[i])
				if g["has_tangent"]:
					var t := Vector3(tangents[i * 4], tangents[i * 4 + 1],
							tangents[i * 4 + 2])
					t = (xf.basis * t).normalized()
					gt.append(t.x)
					gt.append(t.y)
					gt.append(t.z)
					gt.append(tangents[i * 4 + 3])
			if idx == null:
				for i in range(verts.size()):
					gi.append(base + i)
			else:
				for i in range(idx.size()):
					gi.append(base + int(idx[i]))
			g["verts"] = gv
			g["norms"] = gn
			g["uvs"] = gu
			g["colors"] = gc
			g["tangents"] = gt
			g["indices"] = gi
		victims.append(mi)
	var batches := 0
	for key in groups:
		var g: Dictionary = groups[key]
		var gv: PackedVector3Array = g["verts"]
		if gv.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = g["verts"]
		arrays[Mesh.ARRAY_NORMAL] = g["norms"]
		if g["has_uv"]:
			arrays[Mesh.ARRAY_TEX_UV] = g["uvs"]
		if g["has_color"]:
			arrays[Mesh.ARRAY_COLOR] = g["colors"]
		if g["has_tangent"]:
			arrays[Mesh.ARRAY_TANGENT] = g["tangents"]
		arrays[Mesh.ARRAY_INDEX] = g["indices"]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, g["mat"])
		var node := MeshInstance3D.new()
		node.name = "BatchedLandmark%d" % batches
		node.mesh = mesh
		node.cast_shadow = int(g["shadow"])
		node.visibility_range_begin = float(g["begin"])
		node.visibility_range_end = float(g["end"])
		node.visibility_range_end_margin = float(g["margin"])
		node.visibility_range_fade_mode = int(g["fade"])
		root.add_child(node)
		batches += 1
	for v in victims:
		if is_instance_valid(v):
			for child in v.get_children():
				if child is StaticBody3D:
					(child as Node3D).reparent(root, true)
			v.queue_free()
	print("[FrontlineTerrain] merged ", victims.size(),
			" multi-surface landmarks into ", batches, " draw calls")


static func _collect_batchable(node: Node, root: Node3D, groups: Dictionary,
		victims: Array[Node]) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			var kind := ""
			var size := Vector3.ONE
			if mi.has_meta("batch_box"):
				kind = "box"
				size = mi.get_meta("batch_box")
			elif mi.has_meta("batch_cyl"):
				kind = "cyl"
				size = mi.get_meta("batch_cyl")
			elif mi.has_meta("batch_prism"):
				kind = "prism"
				size = mi.get_meta("batch_prism")
			if kind != "":
				var mat := mi.material_override
				# Keep shadowed and non-shadowed instances in separate batches:
				# the detail pass marks its thousands of small trims/rails as
				# no-shadow, which removes an entire shadow pass for them.
				var shadow := mi.cast_shadow
				var sm := mat as StandardMaterial3D
				var use_color := sm != null \
						and sm.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED \
						and not OS.has_environment("QA_NO_PROP_COLOR_BATCH")
				var tint := sm.albedo_color if sm != null else Color.WHITE
				var key := kind + "|" + _material_key(mat, not use_color) \
						+ "|" + str(shadow)
				if not groups.has(key):
					groups[key] = {"kind": kind, "mat": mat, "xforms": [],
							"colors": [], "shadow": shadow,
							"use_color": use_color}
				var xf := root.global_transform.affine_inverse() * mi.global_transform
				xf.basis = xf.basis * Basis.from_scale(size)
				(groups[key]["xforms"] as Array).append(xf)
				if use_color:
					(groups[key]["colors"] as Array).append(tint)
				victims.append(mi)
				continue
		_collect_batchable(child, root, groups, victims)


static func _material_key(mat: Material, include_color := true) -> String:
	var sm := mat as StandardMaterial3D
	if sm == null:
		return str(mat.get_instance_id())
	var key := "%.3f|%.3f|%.2f|%s|%d|%d|%d|%s" % [
		sm.roughness, sm.metallic, sm.metallic_specular,
		sm.emission.to_html(), int(sm.emission_enabled),
		int(sm.transparency), int(sm.cull_mode),
		str(sm.albedo_texture.get_rid()) if sm.albedo_texture else ""]
	if include_color:
		key = sm.albedo_color.to_html() + "|" + key
	return key


static func _add_smoke_plumes(root: Node3D, map_name: String, _base_y: float) -> void:
	# Cheap, readable smoke: three stacked soft billboards per plume plus an
	# additive fire glow at the base.  The radial alpha texture is what makes
	# them read as smoke instead of hard-edged rectangles.
	var smoke_mat := StandardMaterial3D.new()
	smoke_mat.albedo_color = Color(0.20, 0.19, 0.18, 0.62)
	smoke_mat.albedo_texture = _soft_smoke_texture()
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	smoke_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	smoke_mat.disable_receive_shadows = true
	var fire_mat := StandardMaterial3D.new()
	fire_mat.albedo_color = Color(1.0, 0.5, 0.16, 0.8)
	fire_mat.albedo_texture = _soft_smoke_texture()
	fire_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fire_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fire_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fire_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fire_mat.disable_receive_shadows = true
	var quad := QuadMesh.new()
	quad.size = Vector2(16.0, 26.0)
	var fire_quad := QuadMesh.new()
	fire_quad.size = Vector2(8.0, 6.0)
	var spots: Array = []
	match map_name:
		"village":
			spots = [Vector2(20, -70), Vector2(-210, 90), Vector2(120, -110),
					Vector2(150, 20), Vector2(230, 90)]
		"industrial":
			spots = [Vector2(-120, -40), Vector2(-170, -75), Vector2(60, -80),
					Vector2(90, 30), Vector2(-60, 20)]
		"wetlands":
			spots = [Vector2(-120, -40), Vector2(180, -140), Vector2(40, 10),
					Vector2(140, 90)]
		_:
			spots = [Vector2(-170, -110), Vector2(95, -100), Vector2(205, -55),
					Vector2(150, 80), Vector2(240, 140)]
	for p in spots:
		var y := _height(map_name, p.x, p.y)
		var plume := SmokePlume.new()
		plume.position = Vector3(p.x, y + 8.0, p.y)
		plume.setup(float(p.x) * 0.11 + float(p.y) * 0.07)
		root.add_child(plume)
		for i in range(3):
			var mi := MeshInstance3D.new()
			mi.mesh = quad
			mi.material_override = smoke_mat
			mi.position = Vector3(float(i) * 3.0, float(i) * 16.0, 0.0)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			plume.add_child(mi)
			plume.register_quad(mi, float(i) * 16.0)
		# Flickering fire glow at the base.
		var fire := MeshInstance3D.new()
		fire.mesh = fire_quad
		fire.material_override = fire_mat
		fire.position = Vector3(0.0, 1.2, 0.0)
		fire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		plume.add_child(fire)
		plume.register_quad(fire, 0.6)


static func _soft_smoke_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	gradient.add_point(0.2, Color(1, 1, 1, 0.86))
	gradient.add_point(0.5, Color(1, 1, 1, 0.46))
	gradient.add_point(0.78, Color(1, 1, 1, 0.14))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 128
	tex.height = 128
	return tex




