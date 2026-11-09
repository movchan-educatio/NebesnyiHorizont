extends "res://sceneries/Level.gd"


func _ready() -> void:
	if Global.startup:
		Global.initialize()
	super._ready()
	VisualEnhancer.apply_to_scene(self)
	use_urban_ground()

	GameSettings.hud_config["crosshair"] = true
	GameSettings.hud_config["horizon"] = true
	GameSettings.hud_config["speed"] = true
	GameSettings.hud_config["altitude"] = true
	GameSettings.hud_config["heading"] = true
	var d := get_node_or_null("Drone") as Drone
	if d != null:
		d._on_hud_config_updated()

	var city := get_node_or_null("City")
	if city != null and city.has_signal("spawn_ready"):
		if not city.spawn_ready.is_connected(_on_city_spawn_ready):
			city.spawn_ready.connect(_on_city_spawn_ready)
	else:
		_place_drone_at_respawn()

	var cam := get_node_or_null("Drone/FPVCamera") as Camera3D
	if cam != null:
		cam.cull_mask = 1
		cam.current = true
	_configure_drone_visuals_for_camera(true)

	if OS.has_environment("DRONE_AUTOTEST"):
		_run_autotest()
	if OS.has_environment("DRONE_SKY_SCAN"):
		_sky_scan()
	call_deferred("_spawn_handcrafted_showcase")


func _spawn_handcrafted_showcase() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var FT = load("res://scripts/util/frontline_terrain.gd")
	FT.spawn_handcrafted_on_ground(self,
			"res://Assets/handcrafted/village_house.glb", -120.0, 60.0, 0.4)


## One-shot diagnostics: 6 rays from the hover point (kept for map swaps).
func _sky_scan() -> void:
	await get_tree().create_timer(1.0).timeout
	var d := get_node_or_null("Drone")
	if d == null:
		return
	var space := (d as RigidBody3D).get_world_3d().direct_space_state
	var origin: Vector3 = d.global_position + Vector3(0, 14.0, 0)
	for dir in [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * 60.0)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			print("[SKYSCAN] dir ", dir, ": clear 60m")
		else:
			print("[SKYSCAN] dir ", dir, ": HIT at ", (hit["position"] as Vector3 - origin).length(), "m")


func _on_city_spawn_ready(_xform: Transform3D) -> void:
	_place_drone_at_respawn()
	call_deferred("_batch_city_static")


func _batch_city_static() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var ft = load("res://scripts/util/frontline_terrain.gd")
	if ft == null:
		return
	var city := get_node_or_null("City")
	if city != null:
		ft.prepare_city(city)
		ft.batch_static_fast(city)


func _place_drone_at_respawn() -> void:
	var d := get_node_or_null("Drone") as Drone
	var respawn := get_node_or_null("Respawn") as Node3D
	if d == null or respawn == null:
		return
	d.global_transform = respawn.global_transform
	d.linear_velocity = Vector3.ZERO
	d.angular_velocity = Vector3.ZERO
	# The city spawner can move the drone after the controller first sampled its
	# transform. Reset gyro/PID history and the crash-detection velocity before
	# unfreezing so the first frame is not treated as a high-speed impact.
	d.reset_motion_history()
	d.flight_controller.reset()
	d.freeze = true
	DroneCatalog.apply_to_drone(d, Global.drone_preset)
	var cam := get_node_or_null("Drone/FPVCamera") as Camera3D
	_configure_drone_visuals_for_camera(cam != null and cam.current)
	if not d.respawned.is_connected(_on_city_drone_respawned):
		d.connect("respawned", Callable(self, "_on_city_drone_respawned"))
	if d.flight_controller and not d.flight_controller.armed.is_connected(_on_city_drone_armed):
		d.flight_controller.connect("armed", Callable(self, "_on_city_drone_armed"))


func _run_autotest() -> void:
	await get_tree().create_timer(2.0).timeout
	var d := get_node_or_null("Drone") as Drone
	var radio := get_node_or_null("RadioController") as RadioController
	if d == null or radio == null or d.flight_controller == null:
		print("[AUTOTEST] FAIL: nodes missing")
		return
	_place_drone_at_respawn()
	var start_y := d.global_position.y
	print("[AUTOTEST] start y: ", start_y, " pos: ", d.global_position)
	d.flight_controller.request_arm(true)
	await get_tree().create_timer(0.5).timeout
	print("[AUTOTEST] armed: ", d.flight_controller.state_armed)
	radio.test_throttle = 1.0
	for _i in range(6):
		await get_tree().create_timer(0.5).timeout
		print("[AUTOTEST] climb t+", (_i + 1) * 0.5, "s pos=", d.global_position,
			" vel=", d.linear_velocity, " mode=", d.flight_controller.flight_mode,
			" angles=", d.flight_controller.angles,
			" input=", d.flight_controller.input, " freeze=", d.freeze)
	# Hover assist is calibrated around 45% stick; 50% is a climb command.
	radio.test_throttle = 0.45
	if OS.has_environment("DRONE_AUTOTEST_PAN"):
		radio.test_yaw = 0.35
	var end_y := d.global_position.y
	print("[AUTOTEST] end y: ", end_y)
	print("[AUTOTEST] climb: ", end_y - start_y)
	if not (d.flight_controller.state_armed and end_y - start_y > 1.5):
		print("[AUTOTEST] FAIL climb")
		return
	for i in range(8):
		await get_tree().create_timer(1.0).timeout
		print("[AUTOTEST] hover t+", i + 1, "s pos: ", d.global_position)
	var hover_y := d.global_position.y
	print("[AUTOTEST] hover drift y: ", hover_y - end_y)
	if d.flight_controller.state_armed and absf(hover_y - end_y) < 8.0:
		print("[AUTOTEST] PASS")
	else:
		print("[AUTOTEST] FAIL hover")


func _on_city_drone_armed(_mode: int) -> void:
	var d := get_node_or_null("Drone") as Drone
	if d == null:
		return
	d.freeze = false
	var flight_controller := d.flight_controller as FlightController
	if flight_controller != null and flight_controller.flight_mode == FlightController.FlightMode.AUTO:
		flight_controller.change_flight_mode(FlightController.FlightMode.RATE)
	var radio := get_node_or_null("RadioController") as RadioController
	if radio != null:
		radio.hover_assist = true


func _on_city_drone_respawned() -> void:
	_place_drone_at_respawn()
	var radio := get_node_or_null("RadioController") as RadioController
	if radio != null:
		radio.hover_assist = false
		radio.test_throttle = -1.0


func _hide_drone_visuals(node: Node) -> void:
	if node == null:
		return
	if node is VisualInstance3D:
		(node as VisualInstance3D).visible = false
	for child in node.get_children():
		_hide_drone_visuals(child)
