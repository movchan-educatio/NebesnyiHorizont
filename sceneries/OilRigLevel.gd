extends "res://sceneries/BigLevel.gd"
## Нафтова платформа — тільки фрістайл, заміняє Умань у меню.
## Географія з maps/oil_rig (49 гейтів, 5 спавнів, WaterKillZone), усе інше —
## BigLevel. Бойові спавни навмисно заглушені, як в UmanLevel.

const MAP_SCENE := "res://maps/oil_rig/oil_rig_map.tscn"
const DEFAULT_SPAWN := Vector3(-204.0, 407.04, 510.0)

var _map_instance: Node3D = null
var _water_zone: Area3D = null


func _map_path() -> String:
	return MAP_SCENE


func _apply_map_materials(_node: Node) -> void:
	pass


func _scatter_legacy_map(_instance: Node3D) -> void:
	pass


func _ready() -> void:
	MAP_GROUND_SAFE = 1100.0
	MAP_FLIGHT_BOUND = 1400.0
	MAP_AIR_SAFE = 1300.0
	_ground_y = 0.0
	set_meta("disable_procedural_grass", true)
	skip_material_upgrade = true
	super._ready()


func _load_map() -> void:
	super._load_map()
	var root := get_node_or_null("MapRoot")
	if root != null:
		for c in root.get_children():
			if c is Node3D and c.name == "OilRigMap":
				_map_instance = c
				break
	_neutralize_map_extras()
	# BigLevel's fallback ground plane (3600x3600, brown) is far below a 400 m
	# offshore deck and was rendering over/through the authored ocean shader.
	var fallback_ground := get_node_or_null("Ground/MeshInstance3D") as MeshInstance3D
	if fallback_ground != null:
		fallback_ground.visible = false
	_attach_atlas_materials()
	_connect_water_kill()


func _neutralize_map_extras() -> void:
	if _map_instance == null:
		return
	for cam in _map_instance.find_children("FPVCamera", "Camera3D", true, false):
		var camera := cam as Camera3D
		camera.current = false
		camera.set_process(false)
	for we in _map_instance.find_children("WorldEnvironment", "WorldEnvironment", true, false):
		(we as WorldEnvironment).environment = null
	for light in _map_instance.find_children("Sun", "DirectionalLight3D", true, false):
		(light as DirectionalLight3D).visible = false


## Вихідна сцена НЕ активує oil_rig_materials.gd (скрипт є, але не підвішений),
## тому GLB-модулі імпортуються без текстур і виглядають білими. Підвішуємо
## відновлювач атласних матеріалів інакше карта пересвічена й без деталей.
func _attach_atlas_materials() -> void:
	if _map_instance == null:
		return
	# The source mini-project shipped oil_rig_materials.gd but never attached it
	# to a node, so a plain import of the GLBs is untextured/white.  Apply the
	# shared atlas materials on EVERY surface (the helper script only searched
	# its own children, which is why a child-node fixer did nothing).
	var shared := {
		"MAT_Structures": load("res://maps/oil_rig/materials/structures.tres"),
		"MAT_Deck": load("res://maps/oil_rig/materials/deck.tres"),
		"MAT_Emissive": load("res://maps/oil_rig/materials/emissive.tres"),
		"MAT_FlameCore": load("res://maps/oil_rig/materials/flame.tres"),
		"MAT_Light": load("res://maps/oil_rig/materials/light.tres"),
	}
	var applied := 0
	for child in _map_instance.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for surface in range(mi.mesh.get_surface_count()):
			var src: Material = mi.get_surface_override_material(surface)
			if src == null:
				src = mi.mesh.surface_get_material(surface)
			if src == null:
				continue
			var key := String(src.resource_name)
			if shared.has(key):
				mi.set_surface_override_material(surface, shared[key])
				applied += 1
	print("[OILRIG] atlas materials applied to %d surfaces" % applied)


## Світло BigLevel розраховане на ліси/цехи — для морської платформи воно
## спалює білі металеві палуби. Мʼякший контраст і нижча експозиція.
func _tune_map_environment() -> void:
	super._tune_map_environment()
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null:
		var env := we.environment
		env.tonemap_exposure = 0.98
		env.tonemap_white = 1.35
		env.ambient_light_energy = 0.55
		env.ambient_light_sky_contribution = 0.55
		env.adjustment_brightness = 0.98
		env.adjustment_contrast = 1.02
		env.adjustment_saturation = 1.08
		# Source Environment_env: linear fog, colour 0.55/0.70/0.80, density
		# 0.00085.  BigLevel's height fog is centred at _ground_y + 16 (~411 m)
		# and drowned the sea (at y=0) in grey — restore the authored fog mode.
		env.fog_height_density = 0.0
		env.fog_aerial_perspective = 0.0
		env.volumetric_fog_density = 0.0
		# The 0.00085 value in the source .tscn is authored for close FPV views;
		# from the review camera (1 km up) it whites out the whole rig.  Keep
		# the authored fog colour but only a trace of distance haze so the rig
		# reads like the Blender reference render.
		env.fog_light_color = Color(0.55, 0.70, 0.80, 1.0)
		env.fog_light_energy = 0.25
		env.fog_density = 0.000015
		env.glow_enabled = false
		# The Blender verification renders use the CC0 kloofendal HDRI that
		# ships with the source (scripts/cc0_cache/kloofendal_2k.hdr, 01_build_scene.py:470-492).
		# The Godot package never received it; restore it here so the clouds
		# and the metal reflections match renders/*.png. Kept inside the
		# oilrig map folder so no other level is affected.
		var pano := PanoramaSkyMaterial.new()
		pano.panorama = load("res://maps/oil_rig/textures/kloofendal_sky.png")
		var sky := Sky.new()
		sky.sky_material = pano
		env.sky = sky
		env.background_mode = Environment.BG_SKY
		env.background_color = Color(0.53, 0.70, 0.86, 1.0)
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		sun.rotation_degrees = Vector3(-38.0, 120.0, 0.0)
		sun.light_energy = 1.55
		sun.light_color = Color(1.0, 0.94, 0.84, 1.0)
	var fill := get_node_or_null("FillLight") as DirectionalLight3D
	if fill != null:
		fill.light_energy = 0.18


func _connect_water_kill() -> void:
	if _map_instance == null:
		return
	_water_zone = _map_instance.find_child("WaterKillZone", true, false) as Area3D
	if _water_zone != null and not _water_zone.body_entered.is_connected(_on_oilrig_water_body):
		_water_zone.body_entered.connect(_on_oilrig_water_body)


func _on_oilrig_water_body(body: Node3D) -> void:
	if body != null and (body == get_node_or_null("Drone") or body.is_in_group("drone")):
		request_respawn()


func _authored_freestyle_waypoints() -> Array:
	var out: Array = []
	if _map_instance != null:
		var gates := _map_instance.find_child("FPVGates", true, false)
		if gates != null:
			var markers := gates.get_children()
			var step: int = maxi(1, markers.size() / 16)
			for i in range(0, markers.size(), step):
				var m = markers[i]
				if m is Node3D:
					out.append((m as Node3D).global_position)
			if out.size() >= 8:
				return out
	return [
		Vector3(-120, 177, -80), Vector3(0, 182, -180), Vector3(180, 177, -60),
		Vector3(240, 182, 120), Vector3(40, 187, 200), Vector3(-160, 182, 140),
		Vector3(-280, 177, 0), Vector3(-80, 179, -200),
	]


func _find_ground_y(_x: float, _z: float) -> float:
	return 0.0


func _map_water_level() -> float:
	return 0.0


func _is_ground_spot_clear(x: float, z: float) -> bool:
	return absf(x) <= MAP_GROUND_SAFE and absf(z) <= MAP_GROUND_SAFE


func _special_ground_point(x: float, z: float) -> Vector3:
	return Vector3(clampf(x, -MAP_GROUND_SAFE, MAP_GROUND_SAFE), 0.0,
			clampf(z, -MAP_GROUND_SAFE, MAP_GROUND_SAFE))


func _find_oilrig_spawn() -> Vector3:
	if _map_instance != null:
		var points := _map_instance.find_child("SpawnPoints", true, false)
		if points != null:
			var markers := points.get_children()
			if not markers.is_empty():
				var marker = markers[randi() % markers.size()]
				if marker is Node3D:
					return (marker as Node3D).global_position
	var respawn := get_node_or_null("Respawn") as Node3D
	if respawn != null:
		return respawn.global_position
	return DEFAULT_SPAWN


func _place_drone_over_ground() -> void:
	var d := get_node_or_null("Drone")
	if d == null:
		return
	var pos := _find_oilrig_spawn() + Vector3(0.0, 2.0, 0.0)
	var spawn_xform := Transform3D(Basis.IDENTITY, pos)
	var respawn := get_node_or_null("Respawn") as Node3D
	if respawn != null:
		respawn.global_transform = spawn_xform
	d.global_transform = spawn_xform
	_drone_prev_pos = d.global_position
	_drone_last_speed = 0.0
	_drone_peak_speed = 0.0
	d.set("linear_velocity", Vector3.ZERO)
	d.set("angular_velocity", Vector3.ZERO)
	if d.has_method("reset_motion_history"):
		d.reset_motion_history()
	var fc = d.get("flight_controller")
	if fc != null and fc.has_method("reset"):
		fc.reset()
	d.freeze = true
	var existing_model := d.get_node_or_null("DroneModel")
	if existing_model == null or int(existing_model.get_meta("preset_index", -1)) != Global.drone_preset:
		DroneCatalog.apply_to_drone(d, Global.drone_preset)
	else:
		_sync_fpv_drone_model(false, false, true)
	if fc != null:
		if not fc.armed.is_connected(_on_drone_armed):
			fc.armed.connect(_on_drone_armed)
		if not fc.arm_failed.is_connected(_on_arm_failed):
			fc.arm_failed.connect(_on_arm_failed)
	if not d.respawned.is_connected(_on_respawned):
		d.respawned.connect(_on_respawned)


# --- фрістайл-карта: жодних місій, техніки, піхоти чи руйнованих цілей. ---
## The source map removed all visual neon rings — FPVGates are invisible
## Marker3D only.  BigLevel would otherwise spawn a 24-ring cyan course that
## does not exist in the authored scene, so keep this empty.
func _build_frontline_props() -> void:
	pass


func _spawn_training_rings() -> void:
	pass


func _spawn_vehicles() -> void:
	pass


func _spawn_frontline_bonus_targets() -> void:
	pass


func _spawn_special_or_campaign() -> void:
	pass


func _spawn_combat_mission(_mission_id: int) -> void:
	pass


func _spawn_kamikaze_drones() -> void:
	pass


func _start_reinforcements() -> void:
	pass
