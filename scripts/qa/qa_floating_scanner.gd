class_name QaFloatingScanner
extends RefCounted

## Pipeline / standalone QA: finds visible solid meshes and MultiMesh instances
## whose lowest world point floats above the collision surface below them.
##
## Entry points:
##   QaFloatingScanner.scan(root, map_name, strict)      # synchronous pipeline
##   await QaFloatingScanner.scan_scene(scene, strict)   # waits for GLB colliders
##   await QaFloatingScanner.scan_current_scene(strict)  # scans the active scene
##   await QaFloatingScanner.scan_from_env(strict)       # DRONE_FLOAT_SCAN_SCENE
##   await QaFloatingScanner.run_from_environment(strict) # alias of scan_from_env
##
## DRONE_FLOAT_SCAN_SCENE may be a .tscn/.glb such as
## res://sceneries/PromzonaPlavniLevel.tscn, LisLevel.tscn, OilRigLevel.tscn or
## AirportLevel.tscn.  When it is unset the current scene is used.  Authored
## GLB maps get six physics frames to create their colliders/builders first.
##
## Support is sampled with five downward rays per object on collision_mask 1
## (own body RIDs excluded), falling back to FrontlineTerrain.mesh_surface_height
## on procedural maps where a ray misses.  Non-destructive: transforms are
## never changed.

const Terrain = preload("res://scripts/util/frontline_terrain.gd")

const SCAN_SCENE_ENV := "DRONE_FLOAT_SCAN_SCENE"
const SUPPORT_LIMIT := 0.18
const CORNER_INSET := 0.15
const RAY_DROP := 200.0
const SCAN_MASK := 1
const SETTLE_FRAMES := 6

## Multi-tier structures whose upper crossbeams/trusses/arms are legitimately
## elevated above a grounded base.  Handcrafted_factory_complex is deliberately
## absent so its individual containers (cont0..8) keep being checked.
const COMPOSITE_ASSEMBLIES := [
	"herohall_", "herohalltrim", "plavnihall", "rotatingtowercrane",
	"movinggantrycrane", "radarrelaystation", "observationwatchtower",
	"constructionskeletonrubik", "scaffoldingfreestylecube",
	"heavyradargcicomplex", "pipelineoverpass", "pipelinepowerlooparch",
	"shippingcontainercomplex", "handcrafted_wetlands_dock", "pipebridge",
	"factorytower", "canalbridge", "opentower", "tankcluster", "watertower",
]
const COMPOSITE_DROP := 0.45
const SANDBAG_TIER_LIMIT := 0.42
## 3D dioramas rendered by UI sub-viewports are not part of the game world.
const NON_WORLD_PATHS := ["pausecanvaslayer", "mobilemenu", "flightschooltrack"]
const NON_WORLD_NAMES := ["zone_flow_paths", "col__m_paint", "col__m_rust"]
const HALL_SITES := ["herohall", "hero_hall", "assemblyhall", "exhibitionhall"]
const HALL_UPPER_TOKENS := [
	"frame", "light", "lamp", "beam", "truss", "rafter", "catwalk",
]

const PROCEDURAL_MAPS := [
	"steppe", "village", "industrial", "wetlands", "promzona_plavni",
]

const SKIP_TOKENS := [
	"terrain", "ground", "floor", "road", "water", "river", "ocean", "sea",
	"wave", "lake", "pond", "sky", "cloud", "horizon", "mountain", "backdrop",
	"atmosphere", "fx", "particle", "smoke", "plume", "mist", "fog", "fire",
	"flame", "muzzle", "trail", "spark", "dust", "flare", "explosion",
	"shockwave", "ring", "gate", "course", "ribbon", "tether", "arrow", "hoop",
	"checkpoint", "waypoint", "marker", "beacon", "shadow", "decal", "contact",
	"grass", "reed", "wheat", "bush", "flower", "leaf", "leaves", "crown",
	"foliage", "branch", "canopy", "impostor", "tuft", "weed", "crop",
	"drone", "uav", "fpv", "aircraft", "airplane", "plane", "heli", "jet",
	"missile", "rocket", "projectile", "kamikaze", "shahed", "lancet", "mavic",
	"orlan", "zala",
	"lamp", "floodlight", "fixture", "bulb", "lantern", "spotlight",
	"headlight", "polelight", "pole_light", "rooflight", "roof_light",
	"halllights", "hall_lights", "sapling", "scorch", "crater",
	"roof", "ceiling", "skylight", "beam", "truss", "girder", "arch",
	"awning", "eave", "lintel", "boom", "jib", "counterweight", "cabin",
	"trolley", "crossarm", "dish", "cupola", "balcony", "catwalk", "rafter",
	"gable", "chimney", "flue", "vent", "sign", "canopy",
	"spawnpad", "spawn_pad", "launchbarrel", "launch_barrel",
	"launchpad", "launch_pad", "startpad", "start_pad",
	"bridge", "barge", "boat", "cable", "wire", "powerline",
	"railing", "handrail", "banister", "ladder", "window", "glass",
]

const OIL_RIG_SPAN_TOKENS := [
	"truss", "deck", "catwalk", "gantry", "crossbeam", "brace", "span",
	"platform", "walkway", "derrick", "crane", "pipe", "stair", "helipad",
	"structural",
]


static func _empty_result(map_name: String, scene_label: String = "") -> Dictionary:
	return {
		"map": map_name,
		"scene": scene_label,
		"checked": 0,
		"floating": 0,
		"multimesh_checked": 0,
		"multimesh_floating": 0,
		"scanned": 0,
		"floating_total": 0,
		"issues": [],
		"source_transforms": [],
	}


## Synchronous scan used by the build pipeline.  It scans every visible
## MeshInstance3D and every instance of every visible MultiMeshInstance3D under
## root, regardless of whether the map is procedural or an authored GLB.
static func scan(root: Node3D, map_name: String, strict: bool = false,
		scene_label: String = "") -> Dictionary:
	if root == null:
		return _empty_result(map_name, scene_label)
	var resolved_map := _resolve_map_name(root, map_name)
	var label := scene_label
	if label.is_empty():
		label = root.scene_file_path
	if label.is_empty():
		label = String(root.name)
	var result := _empty_result(resolved_map, label)
	if OS.has_environment("QA_NO_FLOAT_SCAN"):
		return result
	var procedural := PROCEDURAL_MAPS.has(resolved_map)
	var space: PhysicsDirectSpaceState3D = null
	var world := root.get_world_3d()
	if world != null:
		space = world.direct_space_state
	var oil_rig := _is_oil_rig(root, resolved_map, label)
	var issues: Array = result["issues"]
	var sources: Array = []
	var assembly_cache: Dictionary = {}

	# ------------------------------------------------ individual MeshInstance3D
	var mesh_nodes: Array[Node] = []
	if root is MeshInstance3D:
		mesh_nodes.append(root)
	mesh_nodes.append_array(root.find_children("*", "MeshInstance3D", true, false))
	for node in mesh_nodes:
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.is_visible_in_tree():
			continue
		# Sub-viewport 3D dioramas (PauseCanvasLayer / MobileMenu canvases)
		# live in a different World3D and are not gameplay geometry.
		if mi.get_world_3d() != world:
			continue
		if _is_airborne_visual(mi):
			continue
		var name_l := String(mi.name).to_lower()
		var path_l := String(mi.get_path()).to_lower()
		if _skip_visual(name_l, path_l, oil_rig):
			continue
		if mi.has_meta("qa_merged_batch"):
			continue
		var local_aabb := mi.get_aabb()
		var box := mi.global_transform * local_aabb
		if box.size.x <= 0.0001 and box.size.z <= 0.0001:
			continue
		var min_y := box.position.y
		# Attached decorative subparts bolted onto a grounded prop are not loose objects.
		if mi.has_meta("qa_attached_subpart") \
				or (mi.get_parent() != null and mi.get_parent().has_meta("qa_attached_subpart")):
			continue
		var assembly := _composite_assembly_ancestor(mi)
		if assembly != null:
			var info := _assembly_ground_info(assembly, assembly_cache, space,
					procedural, resolved_map, root)
			if bool(info["grounded"]) \
					and min_y > float(info["min_y"]) + COMPOSITE_DROP:
				continue
		if _skip_hall_upper(name_l, path_l, min_y, assembly, assembly_cache,
				space, procedural, resolved_map, root):
			continue
		var points := _footprint_points(box)
		var exclude := _own_body_rids(mi)
		var support := _support_height(space, procedural, resolved_map, points,
				min_y, box.end.y, root, exclude, name_l)
		result["checked"] = int(result["checked"]) + 1
		sources.append(mi.global_transform)
		var gap := min_y - support
		if gap > SUPPORT_LIMIT:
			result["floating"] = int(result["floating"]) + 1
			issues.append({
				"kind": "mesh", "node": String(mi.get_path()),
				"name": String(mi.name), "position": mi.global_position,
				"bottom": min_y, "ground": support, "gap": gap,
			})

	# ------------------------------------------------ every MultiMesh instance
	var mm_nodes: Array[Node] = []
	if root is MultiMeshInstance3D:
		mm_nodes.append(root)
	mm_nodes.append_array(root.find_children("*", "MultiMeshInstance3D", true, false))
	for node in mm_nodes:
		var mmi := node as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null or mmi.multimesh.mesh == null:
			continue
		if mmi.get_world_3d() != world:
			continue
		if not mmi.is_visible_in_tree():
			continue
		if _is_airborne_visual(mmi):
			continue
		var name_l := String(mmi.name).to_lower()
		var path_l := String(mmi.get_path()).to_lower()
		if _skip_visual(name_l, path_l, oil_rig):
			continue
		if mmi.has_meta("qa_merged_batch"):
			continue
		var mm := mmi.multimesh
		var local_aabb := mm.mesh.get_aabb()
		var count := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
		if count <= 0:
			continue
		var exclude := _own_body_rids(mmi)
		var headless := DisplayServer.get_name() == "headless"
		var meta_xfs: Array = mmi.get_meta("qa_instance_transforms", []) if mmi.has_meta("qa_instance_transforms") else []
		var assembly := _composite_assembly_ancestor(mmi)
		var assembly_info: Dictionary = {}
		if assembly != null:
			assembly_info = _assembly_ground_info(assembly, assembly_cache,
					space, procedural, resolved_map, root)
		var skip_indices: Dictionary = {}
		var attached_indices: Array = mmi.get_meta("qa_attached_subpart_indices", [])
		for idx in attached_indices:
			skip_indices[int(idx)] = true
		var batched_props := name_l.begins_with("batchedprops")
		for i in range(count):
			var inst_xf: Transform3D = meta_xfs[i] if i < meta_xfs.size() else mm.get_instance_transform(i)
			# In --headless dummy renderer, MultiMesh.get_instance_transform() returns IDENTITY stub;
			# prefer qa_instance_transforms meta when populated, and skip unpopulated headless stubs.
			if headless and meta_xfs.is_empty() and inst_xf.is_equal_approx(Transform3D.IDENTITY):
				continue
			if inst_xf.basis.get_scale().length_squared() < 1.0e-6:
				continue
			var world_xf := mmi.global_transform * inst_xf
			var box := world_xf * local_aabb
			if box.size.x <= 0.0001 and box.size.z <= 0.0001:
				continue
			var min_y := box.position.y
			# Attached dressing / interior hall frames are part of a grounded
			# assembly, never loose floating props.
			if skip_indices.has(i):
				continue
			if batched_props and mmi.has_meta("qa_attached_subpart"):
				continue
			if assembly != null \
					and bool(assembly_info.get("grounded", false)) \
					and min_y > float(assembly_info["min_y"]) + COMPOSITE_DROP:
				continue
			if _skip_hall_upper(name_l, path_l, min_y, assembly, assembly_cache,
					space, procedural, resolved_map, root):
				continue
			var points := _footprint_points(box)
			var support := _support_height(space, procedural, resolved_map, points,
					min_y, box.end.y, root, exclude, name_l)
			result["multimesh_checked"] = int(result["multimesh_checked"]) + 1
			sources.append(world_xf)
			var gap := min_y - support
			if gap > SUPPORT_LIMIT:
				result["multimesh_floating"] = int(result["multimesh_floating"]) + 1
				issues.append({
					"kind": "multimesh", "node": String(mmi.get_path()),
					"name": String(mmi.name), "index": i,
					"position": world_xf.origin,
					"bottom": min_y, "ground": support, "gap": gap,
				})

	result["scanned"] = int(result["checked"]) + int(result["multimesh_checked"])
	result["floating_total"] = int(result["floating"]) \
			+ int(result["multimesh_floating"])
	result["source_transforms"] = sources
	root.set_meta("qa_float_result", result)
	root.set_meta("qa_source_transforms", sources)
	_print_summary(result, strict)
	return result


## Waits SETTLE_FRAMES physics frames so imported GLB colliders and runtime
## builders have settled, then scans scene.  Use this for authored maps and
## standalone QA.
static func scan_scene(scene: Node3D, strict: bool = false,
		scene_label: String = "") -> Dictionary:
	if scene == null or not is_instance_valid(scene):
		return _empty_result("", scene_label)
	var tree := scene.get_tree()
	if tree != null:
		for _i in range(SETTLE_FRAMES):
			await tree.physics_frame
	if not is_instance_valid(scene):
		return _empty_result("", scene_label)
	var label := scene_label
	if label.is_empty():
		label = scene.scene_file_path
	if label.is_empty():
		label = String(scene.name)
	return scan(scene, _resolve_map_name(scene, ""), strict, label)


## Scans the currently running scene after the same settle window.
static func scan_current_scene(strict: bool = false) -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		push_error("[FLOAT_SCAN] no SceneTree available")
		return _empty_result("", "")
	var scene := tree.current_scene as Node3D
	if scene == null:
		for child in tree.root.get_children():
			if child is Node3D:
				scene = child as Node3D
				break
	if scene == null:
		push_error("[FLOAT_SCAN] no current scene to scan")
		return _empty_result("", "")
	return await scan_scene(scene, strict)


## Loads DRONE_FLOAT_SCAN_SCENE when set, otherwise scans the current scene.
## A temporary env scene is removed again after the audit.
static func scan_from_env(strict: bool = false) -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		push_error("[FLOAT_SCAN] no SceneTree available")
		return _empty_result("", "")
	var env_path := OS.get_environment(SCAN_SCENE_ENV).strip_edges()
	if env_path.is_empty():
		return await scan_current_scene(strict)
	var packed := load(env_path) as PackedScene
	if packed == null:
		push_error("[FLOAT_SCAN] cannot load DRONE_FLOAT_SCAN_SCENE=" + env_path)
		return _empty_result("", env_path)
	var scene := packed.instantiate() as Node3D
	if scene == null:
		push_error("[FLOAT_SCAN] scene root is not Node3D: " + env_path)
		return _empty_result("", env_path)
	tree.root.add_child(scene)
	var result := await scan_scene(scene, strict, env_path)
	if is_instance_valid(scene):
		if scene.get_parent() != null:
			scene.get_parent().remove_child(scene)
		scene.queue_free()
	return result


## Alias kept for callers that audit a scene through the environment variable.
static func run_from_environment(strict: bool = false) -> Dictionary:
	return await scan_from_env(strict)


static func _support_height(space: PhysicsDirectSpaceState3D, procedural: bool,
		map_name: String, points: Array[Vector2], min_y: float, top_y: float,
		level: Node, exclude: Array[RID], name_l: String = "") -> float:
	var best := -1.0e20
	# Start just above the lowest point, but never above a compact AABB slice:
	# tall façades cannot swallow the ray while a floating prop still gets a
	# clean support sample.
	var aabb_top_limited := minf(top_y, min_y + 4.0)
	var from_y := maxf(min_y + 0.35, aabb_top_limited)
	# Terrain / floor is sampled from high above so foundations, decks, raised
	# slabs and pilings are measured instead of the object's own footings.
	var ground_from_y := maxf(top_y + 20.0, 240.0)
	for p in points:
		var hit_y := -1.0e20
		var ground_y := -1.0e20
		if procedural:
			ground_y = float(Terrain.mesh_surface_height(map_name, p.x, p.y))
		else:
			if space != null:
				var gfrom := Vector3(p.x, ground_from_y, p.y)
				var gto := Vector3(p.x, min_y - RAY_DROP, p.y)
				var gquery := PhysicsRayQueryParameters3D.create(gfrom, gto, SCAN_MASK)
				gquery.collide_with_areas = false
				gquery.collide_with_bodies = true
				gquery.exclude = exclude
				var ghit := space.intersect_ray(gquery)
				if not ghit.is_empty():
					ground_y = (ghit["position"] as Vector3).y
			if level != null and is_instance_valid(level) \
					and level.has_method("_find_ground_y"):
				ground_y = maxf(ground_y,
						float(level.call("_find_ground_y", p.x, p.y)))
		if space != null:
			var from := Vector3(p.x, from_y, p.y)
			var to := Vector3(p.x, min_y - RAY_DROP, p.y)
			var query := PhysicsRayQueryParameters3D.create(from, to, SCAN_MASK)
			query.collide_with_areas = false
			query.collide_with_bodies = true
			query.exclude = exclude
			var hit := space.intersect_ray(query)
			if not hit.is_empty():
				hit_y = (hit["position"] as Vector3).y
		if hit_y < -1.0e19:
			if procedural:
				hit_y = ground_y
			elif level != null and is_instance_valid(level) \
					and level.has_method("_find_ground_y"):
				hit_y = float(level.call("_find_ground_y", p.x, p.y))
				ground_y = maxf(ground_y, hit_y)
		# Sunken / embedded footings: concrete foundations, bridge pilings,
		# hillside walls and dock posts reach down INTO solid ground.  When the
		# object's bottom is at or below the surface, that surface is its
		# support rather than a missed ray at -45 m.
		if ground_y > -1.0e19 and ground_y >= min_y - SUPPORT_LIMIT \
				and (top_y >= ground_y - 2.0 or min_y <= ground_y - 0.5):
			hit_y = maxf(hit_y, ground_y)
		if hit_y > best:
			best = hit_y
	# GLB hillside retaining foundations on authored maps slope sharply into
	# cliffside terrain while extending into steep gullies at one corner.
	if name_l.ends_with("_foundation"):
		best = min_y
	# Nothing measurable below the mesh: assume it rests on its own bottom
	# instead of reporting a support of -infinity.
	if best < -1.0e19:
		best = min_y
	# Tier 1 of a two-high sandbag wall sits directly on tier 0; only higher
	# tiers (more than 0.42 m above support) stay reportable.
	if name_l == "sandbags" and min_y - best <= SANDBAG_TIER_LIMIT:
		best = min_y
	return best


## True for composite multi-tier structures whose elevated parts are attached
## to a grounded base.  Enriched_ assemblies qualify too, except standalone
## battle dressing.
static func _is_composite_assembly(name_l: String) -> bool:
	if name_l.contains("battledressing_"):
		return false
	if name_l.contains("enriched_"):
		return true
	for token in COMPOSITE_ASSEMBLIES:
		if name_l.contains(String(token)):
			return true
	return false


static func _composite_assembly_ancestor(node: Node) -> Node3D:
	var cur: Node = node
	while cur != null:
		if cur is Node3D and _is_composite_assembly(String(cur.name).to_lower()):
			return cur as Node3D
		cur = cur.get_parent()
	return null


## Combined visible world AABB of every mesh owned by an assembly.
static func _assembly_aabb(node: Node3D) -> AABB:
	var nodes: Array[Node] = []
	if node is MeshInstance3D:
		nodes.append(node)
	nodes.append_array(node.find_children("*", "MeshInstance3D", true, false))
	var merged := AABB()
	var found := false
	for n in nodes:
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.is_visible_in_tree():
			continue
		if _is_airborne_visual(mi):
			continue
		var box := mi.global_transform * mi.get_aabb()
		if box.size.x <= 0.0001 and box.size.z <= 0.0001:
			continue
		merged = box if not found else merged.merge(box)
		found = true
	return merged if found else AABB()


## Whether the assembly's own footprint rests on terrain / a floor.  Cached per
## node so each assembly is measured once per scan.
static func _assembly_ground_info(assembly: Node3D, cache: Dictionary,
		space: PhysicsDirectSpaceState3D, procedural: bool, map_name: String,
		level: Node) -> Dictionary:
	var key := assembly.get_instance_id()
	if cache.has(key):
		return cache[key]
	var info := {"min_y": 0.0, "grounded": false}
	var box := _assembly_aabb(assembly)
	if box.size.x > 0.0001 or box.size.z > 0.0001:
		var min_y := box.position.y
		var support := _support_height(space, procedural, map_name,
				_footprint_points(box), min_y, box.end.y, level,
				_own_body_rids(assembly), "")
		info = {"min_y": min_y, "grounded": min_y <= support + SUPPORT_LIMIT}
	cache[key] = info
	return info


## HeroHall interior upper frames/lights and BatchedProps dressing attached to
## a grounded hall are not loose props.
static func _skip_hall_upper(name_l: String, path_l: String, min_y: float,
		assembly: Node3D, cache: Dictionary,
		space: PhysicsDirectSpaceState3D, procedural: bool, map_name: String,
		level: Node) -> bool:
	var in_hall := false
	for token in HALL_SITES:
		if path_l.contains(String(token)) or name_l.contains(String(token)):
			in_hall = true
			break
	if not in_hall:
		return false
	if assembly != null:
		var info := _assembly_ground_info(assembly, cache, space, procedural,
				map_name, level)
		if bool(info["grounded"]) and min_y > float(info["min_y"]) + 0.4:
			return true
	if name_l.begins_with("batchedprops"):
		for token in HALL_UPPER_TOKENS:
			if name_l.contains(String(token)):
				return true
	return false


static func _footprint_points(box: AABB) -> Array[Vector2]:
	var x0 := lerpf(box.position.x, box.end.x, CORNER_INSET)
	var x1 := lerpf(box.position.x, box.end.x, 1.0 - CORNER_INSET)
	var z0 := lerpf(box.position.z, box.end.z, CORNER_INSET)
	var z1 := lerpf(box.position.z, box.end.z, 1.0 - CORNER_INSET)
	var cx := (box.position.x + box.end.x) * 0.5
	var cz := (box.position.z + box.end.z) * 0.5
	return [
		Vector2(cx, cz),
		Vector2(x0, z0), Vector2(x1, z0),
		Vector2(x0, z1), Vector2(x1, z1),
	]


## Excludes the collision body that owns this visual (ancestors, descendants
## and a same-named sibling imported by some GLB pipelines), but never excludes
## unrelated terrain/world colliders.
static func _own_body_rids(node: Node) -> Array[RID]:
	var rids: Array[RID] = []
	var cur: Node = node
	while cur != null:
		if cur is CollisionObject3D:
			var rid := (cur as CollisionObject3D).get_rid()
			if not rids.has(rid):
				rids.append(rid)
		cur = cur.get_parent()
	_collect_collision_rids(node, rids)
	var parent := node.get_parent()
	if parent != null:
		var own_name := String(node.name).to_lower()
		for sibling in parent.get_children():
			if sibling == node or not (sibling is CollisionObject3D):
				continue
			var sib_name := String(sibling.name).to_lower()
			if sib_name == own_name or sib_name == own_name + "_body" \
					or sib_name.begins_with(own_name + "_col") \
					or own_name.begins_with(sib_name + "_col"):
				var rid := (sibling as CollisionObject3D).get_rid()
				if not rids.has(rid):
					rids.append(rid)
	return rids


static func _collect_collision_rids(node: Node, rids: Array[RID]) -> void:
	for child in node.get_children():
		if child is CollisionObject3D:
			var rid := (child as CollisionObject3D).get_rid()
			if not rids.has(rid):
				rids.append(rid)
		_collect_collision_rids(child, rids)


static func _is_airborne_visual(node: Node) -> bool:
	return node.is_in_group("air_target") or node.is_in_group("enemy_kamikaze") \
			or node.is_in_group("projectile") or node.is_in_group("missile")


static func _skip_visual(name_l: String, path_l: String, oil_rig: bool) -> bool:
	# UI sub-viewport dioramas and non-world decorations.
	for token in NON_WORLD_PATHS:
		if path_l.contains(String(token)):
			return true
	for token in NON_WORLD_NAMES:
		if name_l.contains(String(token)):
			return true
	# Merged map-wide batches span hundreds of metres across unrelated props,
	# so their aggregate AABB says nothing about any individual object.
	if name_l.begins_with("batchedmesh") \
			or name_l.begins_with("batched_mesh"):
		return true
	# Strip wrapper container names like "FrontlineTerrain" so matching
	# "terrain" on ancestors does not swallow every child structure/prop.
	var clean_path := path_l.replace("frontlineterrain", "").replace("promzonaplavnilevel", "")
	var hay := name_l + "|" + clean_path
	for token in SKIP_TOKENS:
		var t := String(token)
		if t in ["terrain", "ground", "floor", "road"]:
			if name_l.contains(t):
				return true
		elif hay.contains(t):
			return true
	# Fixtures/mounts bolted above a roof or pole are attached hardware, not
	# ground-standing props.
	if (path_l.contains("roof") or path_l.contains("pole")) \
			and (name_l.contains("fixture") or name_l.contains("housing") \
			or name_l.contains("mount") or name_l.contains("lens") \
			or name_l.contains("cap") or name_l.contains("vent")):
		return true
	if oil_rig:
		for token in OIL_RIG_SPAN_TOKENS:
			if hay.contains(String(token)):
				return true
	return false


static func _is_oil_rig(root: Node3D, map_name: String,
		scene_label: String) -> bool:
	var hay := (map_name + " " + scene_label + " " + root.scene_file_path \
			+ " " + String(root.name)).to_lower()
	return hay.contains("oilrig") or hay.contains("oil_rig") \
			or hay.contains("oil rig")


static func _resolve_map_name(root: Node3D, map_name: String) -> String:
	var raw := map_name.strip_edges()
	if raw.is_empty():
		raw = root.scene_file_path.get_file().get_basename()
	if raw.is_empty():
		raw = String(root.name)
	return _normalize_map_name(raw)


static func _normalize_map_name(raw: String) -> String:
	var s := raw.strip_edges().to_lower()
	if s.contains("/") or s.contains("\\"):
		s = s.get_file()
	s = s.trim_suffix(".tscn").trim_suffix(".glb").trim_suffix(".scn")
	s = s.replace(" ", "_").replace("-", "_")
	if s.begins_with("promzona"):
		return "promzona_plavni"
	if s.begins_with("lis"):
		return "lis_forest_freestyle"
	if s.begins_with("oilrig") or s.begins_with("oil_rig"):
		return "oil_rig"
	if s.begins_with("airport"):
		return "airport"
	if s.begins_with("ruins"):
		return "ruins"
	return s


static func _print_summary(result: Dictionary, strict: bool) -> void:
	var scanned := int(result["scanned"])
	var floating := int(result["floating_total"])
	var verbose := strict or OS.has_environment("DRONE_FLOAT_AUDIT") \
			or OS.has_environment("DRONE_FLOAT_SCAN_SCENE") \
			or OS.has_environment("QA_STRICT")
	if verbose:
		for issue in result["issues"]:
			var node_label := String(issue["node"])
			if issue.has("index"):
				node_label += "[%d]" % int(issue["index"])
			print("[FLOAT_SCAN] FLOATING node=", node_label,
					" pos=", _fmt_v3(issue["position"]),
					" min_y=", _fmt_f(issue["bottom"]),
					" support=", _fmt_f(issue["ground"]),
					" gap=", _fmt_f(issue["gap"]))
	print("[FLOAT_SCAN] TOTAL scene=", result["scene"],
			" scanned=", scanned, " floating=", floating)
	if strict and floating > 0:
		push_error("[FLOAT_SCAN] %d floating object(s) detected on %s" % [
			floating, result["scene"]])


static func _fmt_f(value) -> String:
	return String.num(float(value), 3)


static func _fmt_v3(value) -> String:
	var v: Vector3 = value
	return "(" + _fmt_f(v.x) + ", " + _fmt_f(v.y) + ", " + _fmt_f(v.z) + ")"
