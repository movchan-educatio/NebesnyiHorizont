extends "res://sceneries/Level.gd"
## Покинутий аеропорт — окремий фрістайл-рівень.
## Використовує стандартний дрон, радіо, HUD, паузу, тач-керування й
## VisualEnhancer через базовий Level.gd. Не змінює жоден існуючий рівень.

const AIRPORT_GLB := "res://Assets/maps/abandoned_airport.glb"
const GATE_BIG := "res://tracks/gates/Gate_7x6_Simple.tscn"
const GATE_SMALL := "res://tracks/gates/Gate_5x5_Simple.tscn"

var _payload_label: Label = null


func _ready() -> void:
	if Global.startup:
		Global.initialize()
	super._ready()
	_tune_airport_environment()
	_build_airport_collision()
	_place_drone_at_respawn()

	GameSettings.hud_config["crosshair"] = true
	GameSettings.hud_config["speed"] = true
	GameSettings.hud_config["altitude"] = true
	GameSettings.hud_config["heading"] = true
	var d := get_node_or_null("Drone") as Drone
	if d != null:
		d._on_hud_config_updated()
	var cam := get_node_or_null("Drone/FPVCamera") as Camera3D
	if cam != null:
		cam.cull_mask = 1
		cam.current = true
	_configure_drone_visuals_for_camera(true)
	_spawn_freestyle_gates()
	_setup_airport_hud()
	var en := MenuUI.is_english()
	print("[AirportLevel] ", "ready" if en else "готово", ", GLB=", AIRPORT_GLB)


func _spawn_freestyle_gates() -> void:
	# Справжні ігрові кільця/ворота (як на інших картах), додатково до
	# стаціонарних кілець із GLB.
	var gates := [
		[Vector3(-150, 6, 90), 0.0], [Vector3(-90, 9, 40), 0.2],
		[Vector3(-30, 7, -20), -0.3], [Vector3(30, 10, -70), 0.35],
		[Vector3(90, 8, -120), -0.2], [Vector3(150, 12, -170), 0.5],
		[Vector3(210, 7, -215), 0.1], [Vector3(-200, 9, -150), 0.7],
		[Vector3(-120, 8, -220), -0.4], [Vector3(60, 11, 150), 0.25],
		[Vector3(250, 10, 60), -0.6], [Vector3(-260, 7, 30), 0.15],
	]
	for i in gates.size():
		var path := GATE_BIG if i % 3 == 0 else GATE_SMALL
		var packed := load(path) as PackedScene
		if packed == null:
			continue
		var gate := packed.instantiate()
		gate.name = "FreestyleGate%d" % i
		add_child(gate)
		gate.global_position = gates[i][0]
		gate.global_rotation.y = float(gates[i][1])


func _setup_airport_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "AirportHUD"
	canvas.layer = 4
	add_child(canvas)
	var label := Label.new()
	label.name = "PayloadLabel"
	label.position = Vector2(22.0, 92.0)
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.55))
	canvas.add_child(label)
	_payload_label = label
	var en := MenuUI.is_english()
	var p: Dictionary = DroneCatalog.preset(Global.drone_preset)
	var combat := bool(p.get("combat", false))
	var has_drop := bool(p.get("has_drop", false))
	if Global.play_mode == Global.PlayMode.TUTORIAL:
		label.text = ("TUTORIAL: ARM → THROTTLE → STICKS" if en
			else "ТУТОРІАЛ: ARM → ГАЗ → СТІКИ")
	elif Global.play_mode == Global.PlayMode.COMBAT and combat:
		label.text = (("DROP %d  [G]" % 3 if has_drop else "WARHEAD 1x  [F]") if en
			else ("СКИД 3  [G]" if has_drop else "БЧ 1x  [F]"))
	else:
		label.text = ("FREESTYLE · ABANDONED AIRPORT" if en
			else "ФРІСТАЙЛ · ПОКИНУТИЙ АЕРОПОРТ")


func _tune_airport_environment() -> void:
	# VisualEnhancer ставить спільне небо/експозицію; тут повертаємо теплу
	# гаму покинутого аеропорту й м'яку димку на обрії.
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null:
		var env := we.environment
		env.fog_enabled = true
		env.fog_light_color = Color(0.74, 0.67, 0.57, 1.0)
		env.fog_density = 0.0013
		env.tonemap_exposure = 0.92
		env.background_energy_multiplier = 0.62
		env.ambient_light_energy = 0.56
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		sun.rotation_degrees = Vector3(-42.0, -28.0, 18.0)
		sun.light_color = Color(1.0, 0.86, 0.72, 1.0)
		sun.light_energy = 2.05
		sun.set("directional_shadow_max_distance", 700.0)
	if get_node_or_null("FillLight") == null:
		var fill := DirectionalLight3D.new()
		fill.name = "FillLight"
		fill.rotation_degrees = Vector3(-28.0, 150.0, 0.0)
		fill.light_color = Color(0.55, 0.66, 0.86, 1.0)
		fill.light_energy = 0.20
		fill.shadow_enabled = false
		add_child(fill)


func _build_airport_collision() -> void:
	var root := get_node_or_null("MapRoot")
	if root == null:
		push_warning("[AirportLevel] MapRoot " + ("missing" if MenuUI.is_english() else "відсутній"))
		return
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(root, meshes)
	var built := 0
	for mi in meshes:
		# Далекий фон і дрібна рослинність не повинні кидати тіні
		if mi.name in ["DEC__M_Hill", "DEC__M_FarHill", "DEC__M_FarConc",
			"DEC__M_Green", "DEC__M_Ground"]:
			mi.cast_shadow = MeshInstance3D.SHADOW_CASTING_SETTING_OFF
		if not mi.name.begins_with("COL__"):
			continue
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		var faces := mesh.get_faces()
		if faces.is_empty():
			continue
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		var body := StaticBody3D.new()
		body.name = "Collision_" + mi.name
		body.collision_layer = 1
		body.collision_mask = 1
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		add_child(body)
		body.global_transform = mi.global_transform
		built += 1
	print("[AirportLevel] collision bodies: ", built)


func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect_meshes(child, out)


func _place_drone_at_respawn() -> void:
	var d := get_node_or_null("Drone") as Drone
	var respawn := get_node_or_null("Respawn") as Node3D
	if d == null or respawn == null:
		return
	d.global_transform = respawn.global_transform
	d.linear_velocity = Vector3.ZERO
	d.angular_velocity = Vector3.ZERO
	d.reset_motion_history()
	d.flight_controller.reset()
	d.freeze = true
	DroneCatalog.apply_to_drone(d, Global.drone_preset)
	var cam := get_node_or_null("Drone/FPVCamera") as Camera3D
	_configure_drone_visuals_for_camera(cam != null and cam.current)
	if not d.respawned.is_connected(_on_airport_drone_respawned):
		d.respawned.connect(_on_airport_drone_respawned)
	if d.flight_controller != null and not d.flight_controller.armed.is_connected(_on_airport_drone_armed):
		d.flight_controller.armed.connect(_on_airport_drone_armed)


func _on_airport_drone_armed(_mode: int) -> void:
	var d := get_node_or_null("Drone") as Drone
	if d == null:
		return
	d.freeze = false
	var flight_controller := d.flight_controller as FlightController
	if flight_controller != null and flight_controller.flight_mode == FlightController.FlightMode.AUTO:
		flight_controller.restore_preferred_flight_mode()
	var radio := get_node_or_null("RadioController") as RadioController
	if radio != null:
		radio.hover_assist = true


func _on_airport_drone_respawned() -> void:
	_place_drone_at_respawn()
	var radio := get_node_or_null("RadioController") as RadioController
	if radio != null:
		radio.hover_assist = false
		radio.test_throttle = -1.0
