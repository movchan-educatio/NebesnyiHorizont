extends "res://sceneries/BigLevel.gd"
## Умань — фрістайл-карта (Софіївка + набережна).
## Як і AirportLevel, успадковуємо весь BigLevel (керування, HUD, фізику,
## якість, респавн) і підміняємо лише географію: замість процедурного терену
## завантажуємо authored GLB-карту з колізіями, водою та маркерами FX_.
## Бойові місії/техніка/піхота навмисно не створюються — карта тільки для
## вільного фрістайлу на трьох дронах з Assets/UmanFPV.

const UMAN_GLB := "res://Assets/maps/uman/Uman_FPV_Map.glb"
const UMAN_MODELS := "res://Assets/maps/uman/models/"
const UMAN_WATER_SHADER := "res://Assets/maps/uman/water_hq.gdshader"
const UMAN_PROPS := "res://Assets/maps/uman/props_library.glb"
const UMAN_POSTFX := "res://Assets/maps/uman/postfx.gdshader"
const UMAN_SKY := "res://Assets/maps/uman/sky_cloudy_1k.hdr"

const CC0_TREES := ["spruce-tree", "jungle-tree", "mangrove-tree",
		"spruce-tree", "jungle-tree"]
const CC0_BUILDINGS := ["city-block-filler", "general-store", "museum", "bank",
		"cinema", "grandstand", "pit-garage"]
const CC0_HERO_TREES := ["spruce-tree", "birch-grove", "jungle-tree",
		"mangrove-tree", "baobab-tree", "berry-bush"]

const FREESTYLE_MODELS := [
	"race-track-jump-ramp", "sp_launchramp", "sp_quarterpipe",
	"race-track-banked-curve", "race-track-chicane", "sp_grindbox",
	"sp_halfpipe", "sp_funbox", "sp_bowlcorner", "sp_flatrail",
	"sp_kinkedrail", "sp_pad", "sp_stairs", "tire-barrier-wall",
	"catch-fence", "chain-link-fence", "concrete-barrier", "boost-pad",
]

var _uman_ripples: Array = []
var _uman_placed: Array = []
var _uman_fx_ready := false


func _map_path() -> String:
	return UMAN_GLB


## GLB Умані вже має запечені PBR-матеріали — як і в аеропорту, не ховаємо меші.
func _apply_map_materials(_node: Node) -> void:
	pass


## Legacy-detail scattered не потрібен: карта повністю авторська.
func _scatter_legacy_map(_instance: Node3D) -> void:
	pass


func _ready() -> void:
	# Карта 360×360 м — стандартні межі BigLevel (152/182 м) занадто тісні.
	MAP_GROUND_SAFE = 176.0
	MAP_FLIGHT_BOUND = 196.0
	MAP_AIR_SAFE = 188.0
	_ground_y = 0.12
	set_meta("disable_procedural_grass", true)
	super._ready()
	var radio := get_node_or_null("RadioController")
	if radio != null:
		radio.set("hover_assist", false)
		radio.set("test_throttle", -1.0)


func _load_map() -> void:
	super._load_map()
	_uman_hide_static_jets()
	_uman_setup_water()
	# Повний візуал демо: CC0-дерева/будівлі замість примітивів GLB.
	_uman_replace_vegetation()
	_uman_spawn_cc0_models()
	_uman_spawn_fountains()
	_uman_spawn_freestyle_props()
	_uman_populate_stunts()
	_uman_setup_postfx()
	_uman_fx_ready = true


# GLB має власну поверхню ~y=0.1; процедурний height_at для "uman" даних не має.
func _find_ground_y(_x: float, _z: float) -> float:
	return 0.12


func _is_ground_spot_clear(x: float, z: float) -> bool:
	return absf(x) <= MAP_GROUND_SAFE and absf(z) <= MAP_GROUND_SAFE


func _special_ground_point(x: float, z: float) -> Vector3:
	return Vector3(clampf(x, -MAP_GROUND_SAFE, MAP_GROUND_SAFE), 0.14,
			clampf(z, -MAP_GROUND_SAFE, MAP_GROUND_SAFE))


func _map_water_level() -> float:
	return 0.0


## Старт — на маркері PlayerSpawn з GLB (набережна). Якщо маркера немає,
## безпечна запасна точка у повітрі над набережною.
func _place_drone_over_ground() -> void:
	_ground_y = 0.12
	var spawn := _uman_find_spawn()
	var d := get_node_or_null("Drone") as Drone
	if d == null:
		return
	var pos := spawn + Vector3(0.0, 3.0, 0.0)
	d.global_transform = Transform3D(Basis(), pos)
	_drone_prev_pos = d.global_position
	_drone_last_speed = 0.0
	_drone_peak_speed = 0.0
	d.linear_velocity = Vector3.ZERO
	d.angular_velocity = Vector3.ZERO
	if d.has_method("reset_motion_history"):
		d.reset_motion_history()
	if d.flight_controller != null and d.flight_controller.has_method("reset"):
		d.flight_controller.reset()
	d.freeze = true
	var existing_model := d.get_node_or_null("DroneModel")
	if existing_model == null or int(existing_model.get_meta("preset_index", -1)) != Global.drone_preset:
		DroneCatalog.apply_to_drone(d, Global.drone_preset)
	else:
		_sync_fpv_drone_model(false, false, true)
	# Батьківський обробник ARM/respawn не підключиться (ми перевизначили метод),
	# тому робимо це самі — інакше дрон лишається замороженим.
	var fc = d.flight_controller
	if fc != null:
		if not fc.armed.is_connected(_uman_armed):
			fc.armed.connect(_uman_armed)
		if not fc.arm_failed.is_connected(_on_arm_failed):
			fc.arm_failed.connect(_on_arm_failed)
	if not d.respawned.is_connected(_on_respawned):
		d.respawned.connect(_on_respawned)


func _uman_find_spawn() -> Vector3:
	var root := get_node_or_null("MapRoot")
	if root != null:
		var marker := root.find_child("PlayerSpawn", true, false)
		if marker is Node3D:
			return (marker as Node3D).global_position
	return Vector3(120.0, 1.0, 118.0)


func _uman_armed(_mode: int) -> void:
	var d := get_node_or_null("Drone") as Drone
	if d != null:
		d.freeze = false
		d.linear_velocity = Vector3.UP * 0.1
	var help := get_node_or_null("Help")
	if help is CanvasLayer:
		(help as CanvasLayer).visible = false


## Тільки фрістайл: ніяких місій, техніки, піхоти й спецоперацій.
func _build_frontline_props() -> void:
	if Global.play_mode == Global.PlayMode.TRAINING:
		_queue_training_ring_spawn()


## Наступні заглуровки — страховка: навіть якщо батьківський код викличе
## бойові спавни з іншого шляху, на фрістайл-карті нічого не з'явиться.
func _start_mission() -> void:
	pass


func _spawn_vehicles() -> void:
	pass


func _spawn_frontline_bonus_targets() -> void:
	pass


func _spawn_special_or_campaign() -> void:
	pass


func _spawn_combat_mission(_mission_id: int) -> void:
	pass


func _start_reinforcements() -> void:
	pass


func _tune_map_environment() -> void:
	super._tune_map_environment()
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null:
		var env := we.environment
		env.background_mode = Environment.BG_SKY
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_sky_contribution = 0.44
		env.ambient_light_energy = 0.62
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.tonemap_exposure = 1.02
		env.fog_enabled = true
		env.fog_light_color = Color(0.66, 0.74, 0.86, 1.0)
		env.fog_density = 0.00018
		env.glow_enabled = true
		env.glow_intensity = 0.30
		env.glow_bloom = 0.09
		env.glow_hdr_threshold = 1.05
		if ResourceLoader.exists(UMAN_SKY):
			var hdr: Resource = load(UMAN_SKY)
			if hdr is Texture2D:
				var sky := Sky.new()
				var pano := PanoramaSkyMaterial.new()
				pano.panorama = hdr as Texture2D
				sky.sky_material = pano
				env.sky = sky
				env.background_energy_multiplier = 0.72
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = 800.0
		sun.rotation_degrees = Vector3(-26.0, 45.0, 0.0)
		sun.light_color = Color(1.0, 0.86, 0.70, 1.0)
		sun.light_energy = 2.4
	var fill := get_node_or_null("UmanFill") as DirectionalLight3D
	if fill == null:
		fill = DirectionalLight3D.new()
		fill.name = "UmanFill"
		add_child(fill)
	fill.rotation_degrees = Vector3(-26.0, -120.0, 0.0)
	fill.light_color = Color(0.57, 0.70, 0.89, 1.0)
	fill.light_energy = 0.28
	fill.shadow_enabled = false


# --------------------------------------------------------------- scenery -----

func _uman_hide_static_jets() -> void:
	for n in _uman_find_with_prefix(self, "Fountain_Water_Jets"):
		var node := n as Node3D
		if node != null:
			node.visible = false


func _uman_setup_water() -> void:
	var found := _uman_find_with_prefix(self, "Water_Surface")
	if found.is_empty():
		return
	var water: Variant = found[0]
	if not (water is MeshInstance3D):
		return
	var mat := ShaderMaterial.new()
	mat.shader = load(UMAN_WATER_SHADER) as Shader
	if mat.shader == null:
		return
	var noise := NoiseTexture2D.new()
	var fnl := FastNoiseLite.new()
	fnl.noise_type = FastNoiseLite.TYPE_PERLIN
	fnl.frequency = 0.045
	noise.noise = fnl
	noise.width = 256
	noise.height = 256
	noise.seamless = true
	noise.generate_mipmaps = true
	mat.set_shader_parameter("ripple_normal", noise)
	mat.set_shader_parameter("deep_color", Color(0.035, 0.10, 0.095))
	mat.set_shader_parameter("shallow_color", Color(0.11, 0.24, 0.21))
	mat.set_shader_parameter("ripple_scale", 0.055)
	mat.set_shader_parameter("ripple_speed", 1.0)
	mat.set_shader_parameter("ripple_strength", 0.55)
	mat.set_shader_parameter("wave_height", 0.035)
	mat.set_shader_parameter("sky_amount", 0.55)
	(water as MeshInstance3D).material_override = mat
	(water as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _uman_spawn_fountains() -> void:
	var mobile := OS.has_feature("mobile") or OS.get_name() == "iOS"
	for n in _uman_find_with_prefix(self, "FX_"):
		var marker := n as Node3D
		if marker == null:
			continue
		var pos := marker.global_position
		var tall := marker.name == "FX_SnakeFountain"
		_uman_add_jet(pos, marker.name + "_core", tall, 0, mobile)
		_uman_add_jet(pos, marker.name + "_mist", tall, 1, mobile)
		if not mobile:
			_uman_add_jet(pos, marker.name + "_splash", tall, 2, false)
		if mobile:
			continue
		for k in range(3):
			var ring := MeshInstance3D.new()
			var torus := TorusMesh.new()
			torus.inner_radius = 0.55 + k * 0.45
			torus.outer_radius = 0.70 + k * 0.45
			torus.rings = 6
			ring.mesh = torus
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.82, 0.96, 1.0, 0.34)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.emission_enabled = true
			mat.emission = Color(0.55, 0.8, 1.0)
			ring.material_override = mat
			add_child(ring)
			ring.global_position = pos + Vector3(0, 0.12, 0)
			_uman_ripples.append({"node": ring, "phase": k * 0.33})


func _uman_add_jet(pos: Vector3, nm: String, tall: bool, kind: int, mobile: bool) -> void:
	var p := GPUParticles3D.new()
	p.name = "VFX_" + nm
	add_child(p)
	p.global_position = pos
	p.local_coords = false
	p.emitting = true
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.gravity = Vector3(0, -9.8, 0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	var mesh := SphereMesh.new()
	mesh.radial_segments = 6
	mesh.rings = 3
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	var scale := 0.5 if mobile else 1.0
	if kind == 0:
		p.amount = int((260 if tall else 170) * scale)
		p.lifetime = 2.5 if tall else 1.8
		pm.spread = 9.0
		pm.emission_sphere_radius = 0.22
		pm.initial_velocity_min = 20.0 if tall else 10.0
		pm.initial_velocity_max = 30.0 if tall else 16.0
		pm.scale_min = 0.55
		pm.scale_max = 1.25
		pm.color = Color(0.92, 0.98, 1.0, 0.88)
		mesh.radius = 0.085
		mesh.height = 0.17
		m.albedo_color = Color(0.94, 0.99, 1.0, 0.88)
		m.emission = Color(0.65, 0.85, 1.0)
	elif kind == 1:
		p.amount = int(220 * scale)
		p.lifetime = 1.25
		pm.spread = 34.0
		pm.emission_sphere_radius = 0.7
		pm.initial_velocity_min = 5.0
		pm.initial_velocity_max = 11.0
		pm.scale_min = 0.18
		pm.scale_max = 0.55
		pm.color = Color(0.80, 0.93, 1.0, 0.38)
		mesh.radius = 0.12
		mesh.height = 0.24
		m.albedo_color = Color(0.88, 0.96, 1.0, 0.34)
		m.emission = Color(0.5, 0.75, 1.0)
	else:
		p.amount = 130
		p.lifetime = 0.85
		pm.spread = 68.0
		pm.emission_sphere_radius = 0.35
		pm.initial_velocity_min = 4.0
		pm.initial_velocity_max = 8.0
		pm.scale_min = 0.3
		pm.scale_max = 0.8
		pm.color = Color(0.88, 0.97, 1.0, 0.6)
		mesh.radius = 0.1
		mesh.height = 0.2
		m.albedo_color = Color(0.9, 0.98, 1.0, 0.6)
		m.emission = Color(0.6, 0.85, 1.0)
	p.process_material = pm
	mesh.material = m
	p.draw_pass_1 = mesh


## Замінює примітивні крони GLB на текстуровані CC0-дерева й кущі
## (рівно як у демо-проєкті карти — саме це дає «красивий» вигляд).
func _uman_replace_vegetation() -> void:
	var heights := {}
	for m in CC0_TREES:
		var inst := _uman_simple_model(UMAN_MODELS + m + ".glb", Vector3.ZERO, 0.0, 1.0)
		if inst != null:
			heights[m] = maxf(_uman_visual_aabb(inst).size.y, 1.0)
			inst.queue_free()
	var placed := 0
	for n in _uman_find_with_prefix(self, "Tree_"):
		var node := n as Node3D
		if node == null or node.name.contains("Collider"):
			continue
		if placed >= 380:
			break
		var h := _uman_visual_aabb(node).size.y
		if h < 2.0:
			continue
		node.visible = false
		var m: String = CC0_TREES[placed % CC0_TREES.size()]
		var s := clampf(h / maxf(float(heights.get(m, 1.0)), 1.0), 0.55, 2.1)
		_uman_simple_model(UMAN_MODELS + m + ".glb", node.global_position,
				randf() * TAU, s)
		placed += 1
	var shrubs := 0
	for n in _uman_find_with_prefix(self, "Shrub_"):
		var node := n as Node3D
		if node == null:
			continue
		node.visible = false
		if shrubs < 150:
			_uman_simple_model(UMAN_MODELS + "berry-bush.glb", node.global_position,
					randf() * TAU, randf_range(0.8, 1.6))
		shrubs += 1
	print("[UMAN] CC0 trees=", placed, " bushes=", shrubs)


func _uman_spawn_cc0_models() -> void:
	var used := 0
	for n in _uman_find_with_prefix(self, "City_Building"):
		var node := n as Node3D
		if node == null:
			continue
		node.visible = false
		var model: String = CC0_BUILDINGS[used % CC0_BUILDINGS.size()]
		var inst := _uman_simple_model(UMAN_MODELS + model + ".glb",
				node.global_position, randf() * TAU, 1.0)
		if inst != null:
			var box := _uman_visual_aabb(inst)
			if box.size.y > 0.5:
				inst.scale = Vector3.ONE * clampf(22.0 / box.size.y, 0.55, 1.8)
		used += 1
	var tree_spots := [
		Vector3(-30, 1, -38), Vector3(-18, 1, -46), Vector3(-45, 1, -30),
		Vector3(-62, 1, -22), Vector3(-105, 1, -18), Vector3(-128, 1, -8),
		Vector3(-40, 1, 44), Vector3(-12, 1, 55), Vector3(28, 1, 62),
		Vector3(70, 1, 78), Vector3(110, 1, 70), Vector3(138, 1, 55),
		Vector3(96, 1, 8), Vector3(130, 1, -14), Vector3(-85, 1, 92),
	]
	for i in range(tree_spots.size()):
		var model: String = CC0_HERO_TREES[i % CC0_HERO_TREES.size()]
		_uman_simple_model(UMAN_MODELS + model + ".glb", tree_spots[i],
				randf() * TAU, randf_range(0.8, 1.35))
	print("[UMAN] CC0 buildings=", used, " hero trees=", tree_spots.size())


func _uman_simple_model(path: String, pos: Vector3, yaw: float, s: float) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var inst := packed.instantiate() as Node3D
	if inst == null:
		return null
	add_child(inst)
	inst.position = pos
	inst.rotation.y = yaw
	inst.scale = Vector3.ONE * s
	return inst


func _uman_visual_aabb(node: Node) -> AABB:
	var result := AABB()
	var first := true
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			var b := mi.global_transform * mi.mesh.get_aabb()
			if first:
				result = b
				first = false
			else:
				result = result.merge(b)
		for c in n.get_children():
			stack.append(c)
	return result


## Легкий кольоровий грейд демо (без SSAO/volumetric — тільки для LOWSPEC/mobile).
func _uman_setup_postfx() -> void:
	if not ResourceLoader.exists(UMAN_POSTFX):
		return
	var layer := CanvasLayer.new()
	layer.name = "UmanPostFX"
	layer.layer = 10
	add_child(layer)
	var rect := ColorRect.new()
	rect.name = "UmanGrade"
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = load(UMAN_POSTFX) as Shader
	rect.material = mat
	layer.add_child(rect)


func _uman_spawn_freestyle_props() -> void:
	if not ResourceLoader.exists(UMAN_PROPS):
		return
	var packed := load(UMAN_PROPS) as PackedScene
	if packed == null:
		return
	var lib := packed.instantiate()
	var names := ["prop_crate", "prop_barrier", "prop_tires", "prop_barrel",
			"prop_oil_drum", "prop_pipe", "prop_sandbags", "prop_fence",
			"prop_pallet", "prop_generator"]
	var anchors := [Vector3(140, 1, 62), Vector3(96, 1, 18), Vector3(-42, 1, 82),
			Vector3(128, 1, 4), Vector3(62, 1, 8), Vector3(18, 1, 92)]
	var count := 0
	for a in anchors:
		for k in range(4):
			var nm: String = names[(count + k) % names.size()]
			var src := lib.find_child(nm, true, false)
			if src == null:
				continue
			var inst := src.duplicate() as Node3D
			if inst == null:
				continue
			add_child(inst)
			inst.position = a + Vector3((k - 1.5) * 3.2, 0.0, float(count % 2) * 2.5)
			inst.rotation.y = randf() * TAU
			count += 1
	lib.queue_free()


func _uman_populate_stunts() -> void:
	var mobile := OS.has_feature("mobile") or OS.get_name() == "iOS"
	var zones = [
		{"c": Vector3(132, 0, 62), "n": 18},
		{"c": Vector3(58, 0, 112), "n": 16},
		{"c": Vector3(112, 0, -18), "n": 14},
		{"c": Vector3(-62, 0, -32), "n": 18},
		{"c": Vector3(-112, 0, 52), "n": 16},
		{"c": Vector3(24, 0, 42), "n": 14},
	]
	var total := 0
	var limit := 40 if mobile else 122
	for zone in zones:
		var made := 0
		var tries := 0
		while made < int(zone.n) and total < limit and tries < int(zone.n) * 14:
			tries += 1
			var a := randf() * TAU
			var rr: float = sqrt(randf()) * 42.0
			var p: Vector3 = (zone.c as Vector3) + Vector3(cos(a) * rr, 0.0, sin(a) * rr)
			if absf(p.x) > 172.0 or absf(p.z) > 172.0:
				continue
			var too_close := false
			for q in _uman_placed:
				if p.distance_to(q) < 6.0:
					too_close = true
					break
			if too_close:
				continue
			if _uman_near_landmark(p):
				continue
			var model: String = FREESTYLE_MODELS[total % FREESTYLE_MODELS.size()]
			if _uman_spawn_model(UMAN_MODELS + model + ".glb", p,
					randf() * TAU, randf_range(0.9, 1.35)) != null:
				_uman_placed.append(Vector3(p.x, 0.0, p.z))
				made += 1
				total += 1


func _uman_near_landmark(p: Vector3) -> bool:
	if Vector2(p.x + 24.0, p.z + 34.0).length() < 19.0:
		return true
	if Vector2(p.x - 70.0, p.z - 55.0).length() < 26.0:
		return true
	if Vector2(p.x + 85.0, p.z + 20.0).length() < 12.0:
		return true
	return false


func _uman_spawn_model(path: String, pos: Vector3, yaw: float, s: float) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var inst := packed.instantiate() as Node3D
	if inst == null:
		return null
	add_child(inst)
	inst.position = pos
	inst.rotation.y = yaw
	inst.scale = Vector3.ONE * s
	var meshes := _uman_find_meshes(inst)
	for mi in meshes:
		if mi.mesh == null:
			continue
		var shape: Shape3D = mi.mesh.create_trimesh_shape()
		if shape == null:
			continue
		var body := StaticBody3D.new()
		body.name = "uman_stunt_col"
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		mi.add_child(body)
	return inst


func _uman_find_meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_uman_find_meshes(c))
	return out


func _uman_find_with_prefix(node: Node, prefix: String) -> Array:
	var out: Array = []
	if node.name.begins_with(prefix):
		out.append(node)
	for c in node.get_children():
		out.append_array(_uman_find_with_prefix(c, prefix))
	return out


func _process(delta: float) -> void:
	super._process(delta)
	if not _uman_fx_ready:
		return
	for r in _uman_ripples:
		var node := r.node as MeshInstance3D
		if node == null:
			continue
		var phase: float = fmod(Time.get_ticks_msec() * 0.00045 + float(r.phase), 1.0)
		node.scale = Vector3.ONE * (0.55 + phase * 2.4)
		var mat := node.material_override as StandardMaterial3D
		if mat != null:
			mat.albedo_color.a = (1.0 - phase) * 0.38
