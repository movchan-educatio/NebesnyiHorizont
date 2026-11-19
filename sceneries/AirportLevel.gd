extends "res://sceneries/BigLevel.gd"
## Покинутий аеропорт — ПОВНА паритетність з іншими картами.
## Успадковуємо весь BigLevel (місії, бойову систему, БЧ, льотну школу,
## РЕБ, погоду, HUD, треки, якість) і підміняємо лише географію карти.

const AIRPORT_GLB := "res://Assets/maps/abandoned_airport.glb"
const GATE_BIG := "res://tracks/gates/Gate_7x6_Simple.tscn"
const GATE_SMALL := "res://tracks/gates/Gate_5x5_Simple.tscn"
const TREE_OAK := "res://Assets/frontline/oak.glb"
const TREE_PINE := "res://Assets/frontline/pine.glb"

const HIDDEN_DEC := ["DEC__M_Green", "DEC__M_Ground", "DEC__M_Hill",
	"DEC__M_Corrugated", "DEC__M_Rust", "DEC__M_Steel", "DEC__M_Concrete", "DEC__M_Rubber"]

var _grass_hide_attempts := 0




func _map_path() -> String:
	return AIRPORT_GLB


## GLB уже має запечені PBR-матеріали — не ховаємо меші, як робить BigLevel
## для старих плейсхолдерних карт.
func _apply_map_materials(_node: Node) -> void:
	pass


func _scatter_legacy_map(_instance: Node3D) -> void:
	pass


func _ready() -> void:
	# Карта 900×900 м — стандартні межі BigLevel (152/182 м) занадто тісні.
	MAP_GROUND_SAFE = 430.0
	MAP_FLIGHT_BOUND = 470.0
	MAP_AIR_SAFE = 450.0
	super._ready()
	_force_touch_mode()
	var radio := get_node_or_null("RadioController")
	if radio != null:
		radio.set("hover_assist", false)
		radio.set("test_throttle", -1.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_connect_horizon_assist()
	_hide_procedural_grass()
	_replace_trees()
	_spawn_detailed_props()


## Стартовий баррель BigLevel стоїть біля початку координат і ставить дрон
## нижче рівня нашого GLB-ґрунту. Для аеропорту використовуємо власну безпечну
## точку в повітрі над льотним полем.
func _place_drone_over_ground() -> void:
	var d := get_node_or_null("Drone") as Drone
	if d == null:
		return
	d.global_transform = Transform3D(Basis(), Vector3(0.0, 62.0, 255.0))
	d.linear_velocity = Vector3.ZERO
	d.angular_velocity = Vector3.ZERO
	if d.has_method("reset_motion_history"):
		d.reset_motion_history()
	if d.flight_controller != null and d.flight_controller.has_method("reset"):
		d.flight_controller.reset()
	d.freeze = true
	DroneCatalog.apply_to_drone(d, Global.drone_preset)
	# Ми перевизначили _place_drone_over_ground, тому батьківський обробник ARM
	# не підключається — робимо це самі, інакше дрон лишається замороженим.
	var fc = d.flight_controller
	if fc != null and not fc.armed.is_connected(_on_airport_armed):
		fc.armed.connect(_on_airport_armed)


## Обробник ARM без примусової зміни режиму: BigLevel викликає
## restore_preferred_flight_mode(), який перезаписує вибір кнопкою режиму
## (HORIZON не зберігається як preferred). Тут просто знімаємо freeze,
## запускаємо місію й лишаємо режим, обраний пілотом.
func _connect_horizon_assist() -> void:
	var d := get_node_or_null("Drone")
	if d == null or d.flight_controller == null:
		return
	var armed = d.flight_controller.armed
	if not armed.is_connected(_on_airport_armed):
		armed.connect(_on_airport_armed)


func _on_airport_armed(_mode: int) -> void:
	var d := get_node_or_null("Drone") as Drone
	if d != null:
		d.freeze = false
		d.linear_velocity = Vector3.UP * 0.1
	var help := get_node_or_null("Help")
	if help is CanvasLayer:
		(help as CanvasLayer).visible = false
	if not _mission_started and not _mission_finished:
		_start_mission()


## Трава BigLevel розрахована на процедурний height_field і на нашій карті
## висіла в повітрі — вимикаємо її повністю.
func _hide_procedural_grass() -> void:
	_grass_hide_attempts += 1
	for n in ["DenseGrassFoliage", "DenseGrassFar", "FollowGrass"]:
		var node := get_node_or_null(n)
		if node != null:
			node.visible = false
	# BigLevel створює частину трави відкладено — перестраховуємося кількома кадрами.
	if _grass_hide_attempts < 6:
		call_deferred("_hide_procedural_grass")


func _process(delta: float) -> void:
	super._process(delta)
	var d := get_node_or_null("Drone") as RigidBody3D
	var radio := get_node_or_null("RadioController")
	if d == null or radio == null or d.freeze:
		return
	var inp: Array = radio.get("input")
	if inp.is_empty():
		return
	var throttle: float = float(inp[0])  # input[0] = газ, [1]=йав, [2]=рол, [3]=пігч
	var fc = d.get("flight_controller")
	var armed := fc != null and bool(fc.get("state_armed"))
	# Газ 0 або двигуни вимкнені — гальмуємо ковзання біля землі.
	if (throttle <= 0.05 or not armed) and d.global_position.y < 15.0:
		var v := d.linear_velocity
		var flat := Vector2(v.x, v.z)
		if flat.length() > 0.05:
			var damped := flat * 0.80
			d.linear_velocity = Vector3(damped.x, v.y, damped.y)
		if d.global_position.y < 2.0 and flat.length() < 1.5:
			d.linear_velocity = Vector3(0.0, v.y, 0.0)


## На телефоні стіки мають працювати завжди, якщо немає активного ELRS-пульту.
func _force_touch_mode() -> void:
	var touch := get_node_or_null("/root/TouchControls")
	if touch == null or not bool(touch.get("enabled")):
		return
	# Якщо пульт (ELRS Wi-Fi) активний — НЕ перемикаємо на сенсор, інакше
	# TouchControls перехоплює ввід і пульт «відвалюється».
	var wifi := get_node_or_null("/root/ElrsWifiInput")
	var elrs_ok := wifi != null and (bool(wifi.get("valid"))
			or bool(wifi.call("was_recently_active", 20000)))
	if elrs_ok:
		if bool(touch.get("touch_mode")):
			touch.call("set_controller_only", true)
		return
	if OS.get_name() == "iOS" or OS.has_environment("TOUCH_CONTROLS"):
		touch.call("set_controller_only", false)


# Наш GLB має власну плоску поверхню y≈0.1; процедурний height_at для
# "airport" повертає хибні висоти — через це техніка й піхота були під/над ґрунтом.
func _find_ground_y(_x: float, _z: float) -> float:
	return 0.12


func _is_ground_spot_clear(x: float, z: float) -> bool:
	return absf(x) <= MAP_GROUND_SAFE and absf(z) <= MAP_GROUND_SAFE


func _special_ground_point(x: float, z: float) -> Vector3:
	return Vector3(clampf(x, -MAP_GROUND_SAFE, MAP_GROUND_SAFE), 0.14,
			clampf(z, -MAP_GROUND_SAFE, MAP_GROUND_SAFE))


func _replace_trees() -> void:
	var found: Array[MeshInstance3D] = []
	var root := get_node_or_null("MapRoot")
	if root != null:
		_find_dec_mesh(root, found)
	for m in found:
		if m.name == "COL__M_Ground":
			# Беремо той самий матеріал, що й у льотного поля, — межі не буде видно.
			var tarmac := _find_named_mesh(get_node_or_null("MapRoot"), "COL__M_Tarmac")
			var mat: Material = null
			if tarmac != null and tarmac.mesh != null and tarmac.mesh.get_surface_count() > 0:
				mat = tarmac.mesh.surface_get_material(0)
			if mat != null:
				m.material_override = mat
			continue
		# DEC__M_Ground — схил із «травою», DEC__M_Green — конус-дерева,
		# DEC__M_Hill — штучна темна смуга на обрії.
		m.visible = false
	var oak := load(TREE_OAK) as PackedScene
	var pine := load(TREE_PINE) as PackedScene
	if oak == null and pine == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in range(150):
		var packed := pine if (i % 3 == 0 and pine != null) else oak
		if packed == null:
			packed = pine if pine != null else oak
		var a := rng.randf_range(0.0, TAU)
		var r := rng.randf_range(220.0, 560.0)
		var x := cos(a) * r
		var z := sin(a) * r
		var tree := packed.instantiate()
		tree.name = "AirportTree%d" % i
		add_child(tree)
		tree.global_position = Vector3(x, 0.05, z)
		tree.global_rotation.y = rng.randf_range(0.0, TAU)
		var s := rng.randf_range(0.85, 1.35)
		tree.scale = Vector3(s, s, s)


## Деталізовані пропси з бібліотеки основного проєкту замість наших
## примітивних коробок. spawn_prop сам дає кожному пропсу колізію.
func _spawn_detailed_props() -> void:
	var assets = load("res://scripts/util/frontline_assets.gd")
	if assets == null:
		return
	var names := ["prop_barrel", "prop_crate", "prop_pallet", "prop_tires",
		"prop_fuel_tank", "prop_barrier", "prop_generator", "prop_pipe",
		"prop_sandbags", "prop_sign", "prop_antenna", "prop_car_wreck"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7777
	var spawned := 0
	for i in range(96):
		var nm: String = str(names[i % names.size()])
		var a := rng.randf_range(0.0, TAU)
		var r := rng.randf_range(25.0, 390.0)
		var x := cos(a) * r
		var z := sin(a) * r
		if Vector2(x, z).distance_to(Vector2(0.0, 255.0)) < 45.0:
			continue
		var prop = assets.spawn_prop(self, nm, Vector3(x, 0.12, z),
				rng.randf_range(0.0, TAU), rng.randf_range(0.85, 1.25))
		if prop != null:
			prop.name = "DetailedProp%d" % i
			# spawn_prop дає convex-hull колізію — у тонких антен/знаків/труб
			# вона виходить товстою. Для декоративних тонких пропсів прибираємо.
			if nm == "prop_antenna" or nm == "prop_sign" or nm == "prop_pipe":
				for c in prop.get_children():
					if c is StaticBody3D:
						c.queue_free()
			spawned += 1
	print("[Airport] detailed props: ", spawned)


func _find_named_mesh(node: Node, target: String) -> MeshInstance3D:
	if node == null:
		return null
	if node is MeshInstance3D and node.name == target:
		return node
	for c in node.get_children():
		var found := _find_named_mesh(c, target)
		if found != null:
			return found
	return null


func _find_dec_mesh(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and (node.name in HIDDEN_DEC or node.name == "COL__M_Ground"):
		out.append(node)
	for c in node.get_children():
		_find_dec_mesh(c, out)


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
		var flat_dec := ["DEC__M_Marking", "DEC__M_Oil", "DEC__M_Yellow", "DEC__M_Glass"]
		if mi.name.begins_with("DEC__") and (mi.name in HIDDEN_DEC or mi.name in flat_dec):
			continue
		if not mi.name.begins_with("COL__") and not mi.name.begins_with("DEC__"):
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
