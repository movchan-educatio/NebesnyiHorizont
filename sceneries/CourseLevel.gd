extends "res://sceneries/Level.gd"


var _speed_started := false
var _help_layer: CanvasLayer = null


func _ready() -> void:
	if Global.startup:
		Global.initialize()
	super._ready()
	VisualEnhancer.apply_to_scene(self)
	use_urban_ground()

	GameSettings.hud_config["crosshair"] = true
	GameSettings.hud_config["horizon"] = true
	GameSettings.hud_config["speed"] = false
	GameSettings.hud_config["altitude"] = false
	GameSettings.hud_config["heading"] = true
	var d := get_node_or_null("Drone") as Drone
	if d != null:
		d._on_hud_config_updated()

	_help_layer = get_node_or_null("Help") as CanvasLayer
	if _help_layer != null:
		var ctrl := _help_layer.get_node_or_null("Controls") as Control
		if ctrl != null:
			var tween := create_tween()
			tween.tween_interval(10.0)
			tween.tween_property(ctrl, "modulate:a", 0.0, 1.2)
			tween.tween_callback(func(): _help_layer.visible = false)

	var city := get_node_or_null("City")
	if city != null and city.has_signal("spawn_ready"):
		if not city.spawn_ready.is_connected(_on_city_spawn_ready):
			city.spawn_ready.connect(_on_city_spawn_ready)
	else:
		_place_drone_at_respawn()

	_hide_drone_visuals(d)
	call_deferred("_spawn_handcrafted_showcase")


func _spawn_handcrafted_showcase() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var FT = load("res://scripts/util/frontline_terrain.gd")
	FT.spawn_handcrafted_on_ground(self,
			"res://Assets/handcrafted/farm_complex.glb", 80.0, 120.0, 0.0)

	var cam := get_node_or_null("Drone/FPVCamera") as Camera3D
	if cam != null:
		cam.cull_mask = 1
		cam.current = true

	if OS.has_environment("DRONE_AUTOTEST"):
		_run_autotest()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_H:
			if _help_layer != null:
				_help_layer.visible = not _help_layer.visible
				var ctrl := _help_layer.get_node_or_null("Controls") as Control
				if ctrl != null:
					ctrl.modulate.a = 1.0
			get_viewport().set_input_as_handled()


func _on_city_spawn_ready(_xform: Transform3D) -> void:
	_place_drone_at_respawn()
	call_deferred("_batch_city_static")


func _batch_city_static() -> void:
	# The gate course builds from the same spawn_ready signal; give it a beat
	# to finish creating its torus gates before the static merge walks the tree.
	await get_tree().create_timer(1.0).timeout
	var ft = load("res://scripts/util/frontline_terrain.gd")
	if ft == null:
		return
	for path in ["City", "Track", "Course"]:
		var node := get_node_or_null(path)
		if node != null:
			if path == "City":
				ft.prepare_city(node)
			ft.batch_static_fast(node)


func _place_drone_at_respawn() -> void:
	var d := get_node_or_null("Drone") as Drone
	var respawn := get_node_or_null("Respawn") as Node3D
	if d == null or respawn == null:
		return
	d.global_transform = respawn.global_transform
	# Never leave the start camera inside a road/building after the city asset
	# swap: sphere-test the spawn and lift until clear.
	var space := d.get_world_3d().direct_space_state
	if space != null:
		var sphere := SphereShape3D.new()
		sphere.radius = 0.9
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = sphere
		q.exclude = [d.get_rid()]
		for _i in range(20):
			q.transform = Transform3D(Basis.IDENTITY,
					d.global_position + Vector3(0.0, 0.6, 0.0))
			if space.intersect_shape(q, 1).is_empty():
				break
			d.global_position.y += 0.5
	d.linear_velocity = Vector3.ZERO
	d.angular_velocity = Vector3.ZERO
	d.freeze = true
	# Sync controller state with the teleported transform so no stale
	# position/velocity/PID state can cause a transient on the next arm.
	d.flight_controller.reset()
	DroneCatalog.apply_to_drone(d, Global.drone_preset)
	if not d.respawned.is_connected(_on_course_drone_respawned):
		d.connect("respawned", Callable(self, "_on_course_drone_respawned"))
	if d.flight_controller and not d.flight_controller.armed.is_connected(_on_course_drone_armed):
		d.flight_controller.connect("armed", Callable(self, "_on_course_drone_armed"))


func _on_drone_reset() -> void:
	# Same as Level, but skips tracks whose gates are not built yet.
	for track in tracks:
		if track is Track and not (track as Track).checkpoints.is_empty():
			(track as Track).reset_track()
	if Global.game_mode == Global.GameMode.RACE and Global.active_track:
		Global.active_track.initialize_replay(drone)
		Global.active_track.load_replays()
		Global.active_track.start_countdown()


func _run_autotest() -> void:
	await get_tree().create_timer(2.0).timeout
	var d := get_node_or_null("Drone") as Drone
	var radio := get_node_or_null("RadioController") as RadioController
	var track := get_node_or_null("Track") as Track
	if d == null or radio == null or d.flight_controller == null:
		print("[AUTOTEST] FAIL: nodes missing")
		return
	_place_drone_at_respawn()
	DroneCatalog.apply_to_drone(d, 0)
	print("[AUTOTEST] start pos: ", d.global_position)
	d.flight_controller.change_flight_mode(FlightController.FlightMode.LEVEL)
	# This model's throttle curve is calibrated to hover at 45%; higher values
	# are deliberate climb commands and send the drone above the gate course.
	# 45% is neutral hover with the drone level. The forward test pitch tilts the
	# thrust vector, so a hair more collective keeps it at gate height.
	radio.test_throttle = 0.455
	await get_tree().physics_frame
	await get_tree().physics_frame
	d.flight_controller.request_arm(true)
	await get_tree().create_timer(0.2).timeout
	d.flight_controller.change_flight_mode(FlightController.FlightMode.LEVEL)
	print("[AUTOTEST] armed: ", d.flight_controller.state_armed)
	if track == null or track.checkpoints.is_empty():
		print("[AUTOTEST] FAIL: no gates")
		return
	print("[AUTOTEST] gates: ", track.checkpoints.size())
	# Fly forward through gate 0 in self-levelled LEVEL mode.  A constant
	# throttle cannot both lift off and hold gate height for this lightweight
	# race preset, so use a small altitude controller during the run.
	radio.test_throttle = 0.43
	radio.test_pitch = -0.30
	var gate_y: float = (track.checkpoints[0] as Node3D).global_position.y
	for i in range(80):
		await get_tree().create_timer(0.1).timeout
		if i < 8:
			radio.test_throttle = 0.52
		else:
			var err := gate_y - d.global_position.y
			radio.test_throttle = clampf(0.40 + err * 0.04 \
					- d.linear_velocity.y * 0.02, 0.20, 0.70)
		if i % 10 == 9:
			var fcf := d.flight_controller
			print("[AUTOTEST] fly t+", (i + 1) / 10.0, "s pos=", d.global_position,
					" thr=", radio.test_throttle,
					" mode=", fcf.flight_mode,
					" tilt_deg=", rad_to_deg(fcf.angles.x), "/",
					rad_to_deg(fcf.angles.z))
		if d.flight_controller.flight_mode == FlightController.FlightMode.AUTO:
			print("[AUTOTEST] AUTO engaged, aborting flight")
			break
	radio.test_pitch = 0.0
	radio.test_throttle = 0.0
	print("[AUTOTEST] course progress: ", track.current, "/", track.course_list.size() - 1)
	print("[AUTOTEST] drone pos: ", d.global_position)
	if d.flight_controller.state_armed and track.current >= 1:
		print("[AUTOTEST] PASS gate fly-through")
	else:
		print("[AUTOTEST] FAIL gate fly-through")
	# Panorama phase (screenshots): slow yaw in place after the test.
	if OS.has_environment("DRONE_AUTOTEST_PAN"):
		radio.test_pitch = 2.0
		radio.test_throttle = 0.5
		radio.test_yaw = 0.35


func _on_course_drone_armed(_mode: int) -> void:
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
	if Global.play_mode == Global.PlayMode.SPEED and not _speed_started:
		_speed_started = true
		var track := get_node_or_null("Track") as Track
		if track != null:
			print("[Speed] countdown started")
			track.start_countdown()


func _on_course_drone_respawned() -> void:
	_speed_started = false
	_place_drone_at_respawn()
	var radio := get_node_or_null("RadioController") as RadioController
	if radio != null:
		radio.hover_assist = false
		radio.test_throttle = -1.0
		radio.test_pitch = 2.0


func _hide_drone_visuals(node: Node) -> void:
	if node == null:
		return
	if node is VisualInstance3D:
		(node as VisualInstance3D).visible = false
	for child in node.get_children():
		_hide_drone_visuals(child)
