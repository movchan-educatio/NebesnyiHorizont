extends "res://sceneries/BigLevel.gd"
## Покинутий аеропорт — ПОВНА паритетність з іншими картами.
## Успадковуємо весь BigLevel (місії, бойову систему, БЧ, льотну школу,
## РЕБ, погоду, HUD, треки, якість) і підміняємо лише географію карти.

const AIRPORT_GLB := "res://Assets/maps/abandoned_airport.glb"
const GATE_BIG := "res://tracks/gates/Gate_7x6_Simple.tscn"
const GATE_SMALL := "res://tracks/gates/Gate_5x5_Simple.tscn"


func _map_path() -> String:
	return AIRPORT_GLB


## GLB уже має запечені PBR-матеріали — не ховаємо меші, як робить BigLevel
## для старих плейсхолдерних карт.
func _apply_map_materials(_node: Node) -> void:
	pass


func _scatter_legacy_map(_instance: Node3D) -> void:
	pass


func _ready() -> void:
	super._ready()
	await get_tree().physics_frame
	await get_tree().physics_frame
	_setup_payload_hud()


func _setup_payload_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "AirportPayloadHUD"
	canvas.layer = 6
	add_child(canvas)
	var label := Label.new()
	label.name = "Payload"
	label.position = Vector2(22.0, 152.0)
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.42))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	label.add_theme_constant_override("outline_size", 4)
	canvas.add_child(label)
	var en := MenuUI.is_english()
	var p: Dictionary = DroneCatalog.preset(Global.drone_preset)
	if bool(p.get("combat", false)) and DroneCatalog.supports_payload_actions(Global.drone_preset):
		label.text = ("DROP 3  [G]" if bool(p.get("has_drop", false)) else "WARHEAD 1x  [F]") if en \
			else ("СКИД 3  [G]" if bool(p.get("has_drop", false)) else "БЧ 1x  [F]")
	else:
		label.text = ("NO PAYLOAD" if en else "БЧ ВІДСУТНЯ")


func _load_map() -> void:
	super._load_map()
	_build_airport_collision()
	_spawn_airport_gates()
	_apply_airport_grade()


## Замість процедурної фронтової/local_procedural карти — наш GLB уже містить
## усі будівлі, техніку й перешкоди. Але місії/тренування/школа лишаються.
func _build_frontline_props() -> void:
	var d := get_node_or_null("Drone") as Drone
	if Global.play_mode == Global.PlayMode.COMBAT:
		_spawn_special_or_campaign()
		_start_reinforcements()
	if Global.play_mode == Global.PlayMode.TRAINING:
		if Global.combat_training:
			_combat_training = CombatTrainingScript.new()
			add_child(_combat_training)
			_combat_training.initialize(self, d, _ground_y)
		else:
			_queue_training_ring_spawn()
	if Global.play_mode == Global.PlayMode.TUTORIAL:
		_flight_school = FlightSchool.new()
		add_child(_flight_school)
		_flight_school.initialize(self, d, _ground_y)


func _tune_map_environment() -> void:
	super._tune_map_environment()
	_apply_airport_grade()


func _apply_airport_grade() -> void:
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null:
		var env := we.environment
		env.fog_enabled = true
		env.fog_light_color = Color(0.74, 0.67, 0.57, 1.0)
		env.fog_density = 0.0013
		env.tonemap_exposure = 0.95
		env.background_energy_multiplier = 0.72
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		sun.rotation_degrees = Vector3(-42.0, -28.0, 18.0)
		sun.light_color = Color(1.0, 0.86, 0.72, 1.0)
		sun.light_energy = 2.1


func _build_airport_collision() -> void:
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(get_node_or_null("MapRoot"), meshes)
	var built := 0
	for mi in meshes:
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
	print("[Airport] collision bodies: ", built)


func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node == null:
		return
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect_meshes(child, out)


func _spawn_airport_gates() -> void:
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
