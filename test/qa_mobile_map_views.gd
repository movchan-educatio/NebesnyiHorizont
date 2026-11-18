extends Node

## Mobile-mode visual audit. Captures the actual Drone/FPVCamera, not an
## overview camera. Usage: ... qa_mobile_map_views.tscn -- VillageLevel
## MOBILE_MAP_SHOT_DIR must point to a dedicated writable output directory.
const TERRAIN = preload("res://scripts/util/frontline_terrain.gd")
const SCENES := {
	"SteppeLevel": "steppe", "VillageLevel": "village",
	"IndustrialLevel": "industrial", "WetlandsLevel": "wetlands",
}
var _failures := 0

## Each map gets its own menu-card camera: aim at a unique hero landmark and
## approach it from a different side/height, instead of the old shared
## "hangar from 100,140" frame that made all four cards look identical.
const CARD_HERO := {
	"steppe": "MobileHero_WindTurbine",
	"village": "MobileHero2_Church",
	"industrial": "MobileHero_FlareStack",
	"wetlands": "MobileHero_Lighthouse",
}
## offset = camera XZ offset from the landmark; height = camera AGL;
## aim = look-at height above the landmark's ground.
const CARD_SHOT := {
	"steppe": {"offset": Vector2(-52.0, -38.0), "height": 18.0, "aim": 17.0},
	"village": {"offset": Vector2(44.0, -30.0), "height": 12.0, "aim": 9.0},
	"industrial": {"offset": Vector2(-40.0, 46.0), "height": 22.0, "aim": 21.0},
	"wetlands": {"offset": Vector2(34.0, 40.0), "height": 11.0, "aim": 8.0},
}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	OS.set_environment("MOBILE_UI", "1")
	var args := OS.get_cmdline_user_args()
	var scene_name := String(args[0]) if not args.is_empty() else "VillageLevel"
	var output := OS.get_environment("MOBILE_MAP_SHOT_DIR")
	if not SCENES.has(scene_name) or output.is_empty():
		push_error("[MOBILE_MAP_VIEWS] unknown scene or no MOBILE_MAP_SHOT_DIR")
		get_tree().quit(1)
		return
	var map_name := String(SCENES[scene_name])
	Global.play_mode = Global.PlayMode.TRAINING
	Global.special_mission = 0
	var packed := load("res://sceneries/%s.tscn" % scene_name) as PackedScene
	if packed == null:
		get_tree().quit(1)
		return
	var level := packed.instantiate() as Node3D
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	await get_tree().create_timer(4.0).timeout
	# A scene can instantiate even if its script failed to parse. Never accept
	# an empty fallback world as a successful map screenshot.
	if level.get_script() == null or String(level.get("frontline_map")) != map_name \
			or level.get_node_or_null("FrontlineTerrain") == null:
		push_error("[MOBILE_MAP_VIEWS] real terrain failed to load for " + map_name)
		get_tree().quit(1)
		return
	var terrain := level.get_node_or_null("FrontlineTerrain") as Node3D
	var follow_grass := level.get_node_or_null("FollowGrass") as MultiMeshInstance3D
	var grass_ready := follow_grass != null and follow_grass.multimesh != null \
			and follow_grass.multimesh.instance_count > 0 \
			and not bool(follow_grass.get("_building"))
	if not grass_ready:
		_failures += 1
		push_warning("[MOBILE_MAP_VIEWS] initial FollowGrass batch is not ready on " + map_name)
	else:
		print("[MOBILE_MAP_VIEWS] ", map_name, " initial grass instances=",
				follow_grass.multimesh.instance_count)
	var beacons := terrain.find_children("MobileBeacon_*", "Node3D", true, false) \
			if terrain != null else []
	if beacons.size() < 2:
		_failures += 1
		push_warning("[MOBILE_MAP_VIEWS] only %d navigation beacons on %s" % [beacons.size(), map_name])
	else:
		print("[MOBILE_MAP_VIEWS] ", map_name, " navigation beacons=", beacons.size())
	var heroes := terrain.find_children("MobileHero*", "Node3D", true, false) \
			if terrain != null else []
	if heroes.size() < 3:
		_failures += 1
		push_warning("[MOBILE_MAP_VIEWS] %d mobile hero landmarks on %s (want 3)" % [heroes.size(), map_name])
	else:
		print("[MOBILE_MAP_VIEWS] ", map_name, " heroes=", heroes.size())
	# Float scan: every hero landmark must sit on the analytic terrain height.
	# A wrong y means the POI either hovers in the air or is sunk underground.
	for h in heroes:
		var hp := (h as Node3D).global_position
		var ground := TERRAIN.height_at(map_name, hp.x, hp.z)
		var sink := ground - hp.y
		if sink > 0.45 or sink < -2.6:
			_failures += 1
			push_warning("[MOBILE_MAP_VIEWS] %s floats/sinks by %.2f m at (%.0f, %.0f)"
					% [h.name, sink, hp.x, hp.z])
	var patches := terrain.find_children("MobileGroundPatch*", "MeshInstance3D", true, false) \
			if terrain != null else []
	if patches.size() < 4:
		_failures += 1
		push_warning("[MOBILE_MAP_VIEWS] %d ground tint patches on %s" % [patches.size(), map_name])
	else:
		print("[MOBILE_MAP_VIEWS] ", map_name, " ground patches=", patches.size())
	# Curated Blender pack: 20 small props + 10 forge assets + 5 large
	# landmarks.  Verify spacing, ground contact (no floating/sinking) and
	# colliders on every object.
	var prop_pack := terrain.get_node_or_null("MobilePropPack") if terrain != null else null
	var placed_props := int(prop_pack.get_meta("placed", 0)) if prop_pack != null else 0
	var forge_props := int(prop_pack.get_meta("forge", 0)) if prop_pack != null else 0
	var footprints: Array = prop_pack.get_meta("footprints", []) if prop_pack != null else []
	var pack_ok := placed_props >= 14 and forge_props >= 4
	var spacing_bad := 0
	for a in range(footprints.size()):
		for b in range(a + 1, footprints.size()):
			var pa: Dictionary = footprints[a]
			var pb: Dictionary = footprints[b]
			var need: float = float(pa["radius"]) + float(pb["radius"]) + 1.5
			if (pa["pos"] as Vector2).distance_to(pb["pos"]) < need:
				spacing_bad += 1
	if spacing_bad > 0:
		pack_ok = false
		push_warning("[MOBILE_MAP_VIEWS] %s: %d overlapping prop pairs"
				% [map_name, spacing_bad])
	var float_bad := 0
	var collider_bad := 0
	var large_count := 0
	if prop_pack != null:
		for prop in prop_pack.get_children():
			var node := prop as Node3D
			if bool(node.get_meta("pack_large", false)):
				large_count += 1
			if not bool(node.get_meta("pack_floating", false)):
				var ground := float(TERRAIN.mesh_surface_height(map_name,
						node.position.x, node.position.z))
				if absf(node.position.y - ground) > 0.35:
					float_bad += 1
			var has_collider := false
			for c in node.find_children("*", "StaticBody3D", true, false):
				has_collider = true
				break
			if not has_collider:
				collider_bad += 1
	if float_bad > 0 or collider_bad > 0 or large_count < 2:
		pack_ok = false
		push_warning("[MOBILE_MAP_VIEWS] %s pack: floating=%d no_collider=%d large=%d"
				% [map_name, float_bad, collider_bad, large_count])
	if not pack_ok:
		_failures += 1
		push_warning("[MOBILE_MAP_VIEWS] prop pack on %s: placed=%d forge=%d"
				% [map_name, placed_props, forge_props])
	else:
		print("[MOBILE_MAP_VIEWS] ", map_name, " props=", placed_props,
				" forge=", forge_props, " large=", large_count,
				" spacing_overlaps=", spacing_bad, " float_bad=", float_bad,
				" collider_bad=", collider_bad)
	var drone := level.get_node_or_null("Drone") as RigidBody3D
	var fpv := level.get_node_or_null("Drone/FPVCamera") as Camera3D
	if drone == null or fpv == null:
		push_error("[MOBILE_MAP_VIEWS] Drone/FPVCamera missing")
		get_tree().quit(1)
		return
	_audit_training_ring_clearance(level, drone, map_name)
	DirAccess.make_dir_recursive_absolute(output)
	await _capture(output.path_join(map_name + "_spawn.png"), fpv)
	var ring_list: Variant = level.get("_training_rings")
	if ring_list is Array and not (ring_list as Array).is_empty():
		var first_ring := (ring_list as Array)[0] as Area3D
		var ring_camera := Camera3D.new()
		ring_camera.name = "TrainingRingQACamera"
		ring_camera.fov = 66.0
		ring_camera.far = 1800.0
		level.add_child(ring_camera)
		var ring_normal := first_ring.global_transform.basis.z.normalized()
		ring_camera.global_position = first_ring.global_position + ring_normal * 27.0 + Vector3.UP * 2.0
		ring_camera.look_at(first_ring.global_position, Vector3.UP)
		await get_tree().process_frame
		await _capture(output.path_join(map_name + "_training_ring.png"), ring_camera)
		ring_camera.queue_free()
		fpv.current = true
	if OS.has_environment("TOUCH_LAYOUT_SHOT") and map_name == "village":
		var touch_controls := get_node_or_null("/root/TouchControls")
		if touch_controls != null and bool(touch_controls.get("enabled")):
			touch_controls.call("_on_more_pressed")
			await get_tree().process_frame
			touch_controls.call("_on_layout_edit_pressed")
			await get_tree().process_frame
			var toolbar := touch_controls.get("_layout_toolbar") as Control
			print("[MOBILE_MAP_VIEWS] touch toolbar rect=",
					toolbar.get_global_rect() if toolbar != null else Rect2())
			await _capture(output.path_join("touch_layout_editor.png"), fpv)
			touch_controls.call("_on_layout_done_pressed")

	var hall: Dictionary = TERRAIN.HALL_SITES[map_name]
	var center: Vector2 = hall["center"]
	# Static, deterministic viewpoints deliberately use the real drone and FPV
	# camera at low altitude. They are QA-only; no user save is changed.
	var card_view: Dictionary = {
		"at": center + Vector2(100, 140), "height": 28.0,
		"target": center + Vector2(0, 16),
	}
	if CARD_HERO.has(map_name) and CARD_SHOT.has(map_name):
		var hero_name := String(CARD_HERO[map_name])
		for h in heroes:
			if (h as Node3D).name == hero_name:
				var hp := (h as Node3D).global_position
				var cfg: Dictionary = CARD_SHOT[map_name]
				var off: Vector2 = cfg["offset"]
				card_view = {
					"at": Vector2(hp.x, hp.z) + off,
					"height": float(cfg["height"]),
					"target": Vector2(hp.x, hp.z),
					"aim": float(cfg["aim"]),
				}
				print("[MOBILE_MAP_VIEWS] card camera for ", map_name,
						" -> ", hero_name, " at ", Vector2(hp.x, hp.z))
				break
	var positions := [
		{"name": "landmark", "at": center + Vector2(0, 75), "height": 10.0, "target": center},
		{"name": "low_flight", "at": center + Vector2(80, 90), "height": 3.5, "target": center + Vector2(10, 20)},
		{"name": "overview", "at": center + Vector2(-95, 125), "height": 42.0, "target": center},
		{"name": "card", "at": card_view["at"], "height": card_view["height"],
			"target": card_view["target"], "aim": card_view.get("aim", 16.0)},
	]
	# One close-up of the new forge layer so a visual regression (missing
	# baked texture, wrong scale, floating plinth) is visible in the audit.
	# Pick the widest forge object: it is usually a bridge, hangar or tower
	# with a clear silhouette instead of a small hut hidden by trees.
	var forge_node: Node3D = null
	var forge_radius := 0.0
	if prop_pack != null:
		for child in prop_pack.get_children():
			var candidate := child as Node3D
			if candidate == null or not bool(candidate.get_meta("pack_forge", false)):
				continue
			var r := float(candidate.get_meta("pack_radius", 0.0))
			if r > forge_radius:
				forge_radius = r
				forge_node = candidate
	if forge_node != null:
		var fp := Vector2(forge_node.position.x, forge_node.position.z)
		var height := float(forge_node.get_meta("pack_height", 12.0))
		var dist := clampf(maxf(forge_radius * 2.1, height * 1.35), 22.0, 50.0)
		var aim := minf(height * 0.5, 13.0)
		var cam_h := maxf(aim + 6.0, 22.0)
		print("[MOBILE_MAP_VIEWS] forge close-up ", forge_node.name,
				" dist=", snappedf(dist, 0.1), " aim=", snappedf(aim, 0.1))
		positions.append({"name": "forge", "at": fp + Vector2(0, dist),
				"height": cam_h, "target": fp, "aim": aim})
	drone.freeze = true
	for view in positions:
		var at: Vector2 = view["at"]
		var target: Vector2 = view["target"]
		var y := TERRAIN.height_at(map_name, at.x, at.y) + float(view["height"])
		drone.global_position = Vector3(at.x, y, at.y)
		var look := Vector3(target.x, y, target.y)
		if view.has("aim"):
			look.y = TERRAIN.height_at(map_name, target.x, target.y) \
					+ float(view["aim"])
		if not drone.global_position.is_equal_approx(look):
			drone.look_at(look, Vector3.UP)
		drone.linear_velocity = Vector3.ZERO
		drone.angular_velocity = Vector3.ZERO
		await get_tree().process_frame
		await get_tree().process_frame
		await _capture(output.path_join(map_name + "_" + String(view["name"]) + ".png"), fpv)
		if String(view["name"]) == "card" and OS.has_environment("MOBILE_MAP_CLEAN_THUMB"):
			await _capture_clean_thumbnail(output.path_join(map_name + "_thumbnail.png"), fpv, drone)
	await _route_audit(output, map_name, fpv, drone)
	print("[MOBILE_MAP_VIEWS] completed ", map_name)
	get_tree().quit(0 if _failures == 0 else 1)


## Straight low-altitude corridors per map. Each corridor is probed at 3, 8 and
## 15 m; a segment counts as blocked only when it hits a steep/wall surface.
## Fewer than 50% blocked segments per height keeps the route passable.
func _route_audit(output: String, map_name: String, fpv: Camera3D,
		drone: Node3D) -> void:
	var routes := {
		"steppe": [Vector2(-150.0, -110.0), Vector2(155.0, 130.0)],
		"village": [Vector2(-140.0, -100.0), Vector2(155.0, 135.0)],
		"industrial": [Vector2(-120.0, 120.0), Vector2(155.0, -120.0)],
		"wetlands": [Vector2(-140.0, 80.0), Vector2(155.0, -60.0)],
	}
	var ends: Array = routes.get(map_name, [])
	if ends.size() < 2:
		return
	var start: Vector2 = ends[0]
	var finish: Vector2 = ends[1]
	var space := drone.get_world_3d().direct_space_state
	var steps := 24
	for height in [3.0, 8.0, 15.0]:
		var blocked := 0
		for i in range(steps):
			var a: Vector2 = start.lerp(finish, float(i) / float(steps))
			var b: Vector2 = start.lerp(finish, float(i + 1) / float(steps))
			var ya: float = TERRAIN.height_at(map_name, a.x, a.y) + height
			var yb: float = TERRAIN.height_at(map_name, b.x, b.y) + height
			var query := PhysicsRayQueryParameters3D.create(
					Vector3(a.x, ya, a.y), Vector3(b.x, yb, b.y))
			query.collision_mask = 1
			query.exclude = [drone.get_rid()] if drone is CollisionObject3D else []
			var hit := space.intersect_ray(query)
			if not hit.is_empty():
				var normal: Vector3 = hit.get("normal", Vector3.UP)
				if normal.y < 0.65:
					blocked += 1
		var ratio := float(blocked) / float(steps)
		if ratio >= 0.5:
			_failures += 1
		print("[MOBILE_MAP_VIEWS] ", map_name, " corridor h=", height,
				" blocked=", blocked, "/", steps, " ratio=", snappedf(ratio, 0.01))
	if OS.has_environment("MOBILE_MAP_CLEAN_THUMB"):
		drone.freeze = true
		var mid: Vector2 = start.lerp(finish, 0.5)
		for i in range(3):
			var point: Vector2 = start if i == 0 else (finish if i == 2 else mid)
			var y := TERRAIN.height_at(map_name, point.x, point.y) + 8.0
			drone.global_position = Vector3(point.x, y, point.y)
			var look_at := Vector3(finish.x, y, finish.y)
			if not drone.global_position.is_equal_approx(look_at):
				drone.look_at(look_at, Vector3.UP)
			drone.linear_velocity = Vector3.ZERO
			drone.angular_velocity = Vector3.ZERO
			await get_tree().process_frame
			await get_tree().process_frame
			await _capture(output.path_join(map_name + "_route%d.png" % i), fpv)


func _audit_training_ring_clearance(level: Node3D, drone: RigidBody3D,
		map_name: String) -> void:
	var ring_value: Variant = level.get("_training_rings")
	if not (ring_value is Array):
		_failures += 1
		push_error("[MOBILE_MAP_VIEWS] training ring list missing on " + map_name)
		return
	var rings: Array = ring_value
	if rings.size() != 24:
		_failures += 1
		push_error("[MOBILE_MAP_VIEWS] %s has %d training rings, expected 24"
				% [map_name, rings.size()])
		return
	var clearance := BoxShape3D.new()
	clearance.size = Vector3(18.0, 18.0, 18.0)
	var space := level.get_world_3d().direct_space_state
	var overlap_count := 0
	var closest := INF
	var min_agl := INF
	var max_agl := -INF
	for i in range(rings.size()):
		var ring := rings[i] as Area3D
		if ring == null or not is_instance_valid(ring):
			overlap_count += 1
			continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = clearance
		query.transform = Transform3D(Basis.IDENTITY, ring.global_position)
		query.collision_mask = 1
		query.collide_with_bodies = true
		query.collide_with_areas = false
		query.exclude = [drone.get_rid()]
		var hits := space.intersect_shape(query, 8)
		if not hits.is_empty():
			overlap_count += 1
			var collider = hits[0].get("collider")
			push_warning("[MOBILE_MAP_VIEWS] %s ring %d at %s clearance hits %s"
					% [map_name, i + 1, str(ring.global_position),
					str(collider.name) if collider != null else "unknown"])
		if i > 0:
			var prev := rings[i - 1] as Area3D
			if prev != null:
				closest = minf(closest, ring.global_position.distance_to(prev.global_position))
		var agl := ring.global_position.y - TERRAIN.height_at(map_name,
				ring.global_position.x, ring.global_position.z)
		min_agl = minf(min_agl, agl)
		max_agl = maxf(max_agl, agl)
	if overlap_count > 0:
		_failures += overlap_count
		push_error("[MOBILE_MAP_VIEWS] %s training gates intersect %d colliders"
				% [map_name, overlap_count])
	else:
		print("[MOBILE_MAP_VIEWS] ", map_name,
				" safe gates=24 closest_sequential=", snappedf(closest, 0.1),
				" m AGL=", snappedf(min_agl, 0.1), "..", snappedf(max_agl, 0.1), " m")


func _capture(path: String, fpv: Camera3D) -> void:
	if DisplayServer.get_name() == "headless":
		# The dummy renderer never emits frame_post_draw, so a headless run
		# would hang forever on the first screenshot.  Assertions still run.
		print("[MOBILE_MAP_VIEWS] headless: skipped capture ", path)
		return
	fpv.current = true
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	if err != OK:
		_failures += 1
		push_error("[MOBILE_MAP_VIEWS] save failed: %s (%d)" % [path, err])
	else:
		print("[MOBILE_MAP_VIEWS] saved ", path)


func _capture_clean_thumbnail(path: String, fpv: Camera3D, drone: Node3D) -> void:
	# Capture a menu thumbnail from the in-game camera without storing the
	# player's HUD, debug counters, or the test drone model in the card image.
	var saved_layers: Array[Dictionary] = []
	for node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var layer := node as CanvasLayer
		saved_layers.append({"node": layer, "visible": layer.visible})
		layer.visible = false
	var saved_controls: Array[Dictionary] = []
	for node in get_tree().root.find_children("*", "CanvasItem", true, false):
		var item := node as CanvasItem
		saved_controls.append({"node": item, "visible": item.visible})
		item.visible = false
	var model := drone.get_node_or_null("DroneModel") as Node3D
	var model_visible := model.visible if model != null else false
	if model != null:
		model.visible = false
	# frame_post_draw alone may still return the frame submitted before the
	# visibility changes. Wait for a new process frame before capturing it.
	await get_tree().process_frame
	await _capture(path, fpv)
	if model != null:
		model.visible = model_visible
	for state in saved_controls:
		var item: CanvasItem = state["node"]
		if is_instance_valid(item):
			item.visible = bool(state["visible"])
	for state in saved_layers:
		var layer: CanvasLayer = state["node"]
		if is_instance_valid(layer):
			layer.visible = bool(state["visible"])
