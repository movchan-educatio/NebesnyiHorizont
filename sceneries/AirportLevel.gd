extends "res://sceneries/Level.gd"
## Покинутий аеропорт — окремий фрістайл-рівень.
## Використовує стандартний дрон, радіо, HUD, паузу, тач-керування й
## VisualEnhancer через базовий Level.gd. Не змінює жоден існуючий рівень.

const AIRPORT_GLB := "res://Assets/maps/abandoned_airport.glb"


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
	var en := MenuUI.is_english()
	print("[AirportLevel] ", "ready" if en else "готово", ", GLB=", AIRPORT_GLB)


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
