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


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
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
	var beacons := terrain.find_children("MobileBeacon_*", "Node3D", true, false) \
			if terrain != null else []
	if beacons.size() < 2:
		_failures += 1
		push_warning("[MOBILE_MAP_VIEWS] only %d navigation beacons on %s" % [beacons.size(), map_name])
	else:
		print("[MOBILE_MAP_VIEWS] ", map_name, " navigation beacons=", beacons.size())
	var heroes := terrain.find_children("MobileHero*", "Node3D", true, false) \
			if terrain != null else []
	if heroes.size() < 2:
		_failures += 1
		push_warning("[MOBILE_MAP_VIEWS] %d mobile hero landmarks on %s" % [heroes.size(), map_name])
	else:
		print("[MOBILE_MAP_VIEWS] ", map_name, " heroes=", heroes.size())
	var patches := terrain.find_children("MobileGroundPatch*", "MeshInstance3D", true, false) \
			if terrain != null else []
	if patches.size() < 4:
		_failures += 1
		push_warning("[MOBILE_MAP_VIEWS] %d ground tint patches on %s" % [patches.size(), map_name])
	else:
		print("[MOBILE_MAP_VIEWS] ", map_name, " ground patches=", patches.size())
	var drone := level.get_node_or_null("Drone") as RigidBody3D
	var fpv := level.get_node_or_null("Drone/FPVCamera") as Camera3D
	if drone == null or fpv == null:
		push_error("[MOBILE_MAP_VIEWS] Drone/FPVCamera missing")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output)
	await _capture(output.path_join(map_name + "_spawn.png"), fpv)

	var hall: Dictionary = TERRAIN.HALL_SITES[map_name]
	var center: Vector2 = hall["center"]
	# Static, deterministic viewpoints deliberately use the real drone and FPV
	# camera at low altitude. They are QA-only; no user save is changed.
	var positions := [
		{"name": "landmark", "at": center + Vector2(0, 85), "height": 10.0, "target": center},
		{"name": "low_flight", "at": center + Vector2(95, 105), "height": 3.5, "target": center + Vector2(10, 25)},
		{"name": "overview", "at": center + Vector2(-110, 150), "height": 45.0, "target": center},
		{"name": "card", "at": center + Vector2(120, 185), "height": 28.0, "target": center + Vector2(0, 18)},
	]
	drone.freeze = true
	for view in positions:
		var at: Vector2 = view["at"]
		var target: Vector2 = view["target"]
		var y := TERRAIN.height_at(map_name, at.x, at.y) + float(view["height"])
		drone.global_position = Vector3(at.x, y, at.y)
		var look := Vector3(target.x, y, target.y)
		if not drone.global_position.is_equal_approx(look):
			drone.look_at(look, Vector3.UP)
		drone.linear_velocity = Vector3.ZERO
		drone.angular_velocity = Vector3.ZERO
		await get_tree().process_frame
		await get_tree().process_frame
		await _capture(output.path_join(map_name + "_" + String(view["name"]) + ".png"), fpv)
		if String(view["name"]) == "card" and OS.has_environment("MOBILE_MAP_CLEAN_THUMB"):
			await _capture_clean_thumbnail(output.path_join(map_name + "_thumbnail.png"), fpv, drone)
	print("[MOBILE_MAP_VIEWS] completed ", map_name)
	get_tree().quit(0 if _failures == 0 else 1)


func _capture(path: String, fpv: Camera3D) -> void:
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
