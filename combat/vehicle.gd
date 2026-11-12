## Ground & aerial combat vehicle (T-72 tank / BMP-2M / BTR-90 / GAZ Tigr /
## SAM launcher / Apache helicopter / Shahed-136) that patrols waypoints with
## unit-specific tactical behavior, strict terrain grounding, and forward-only
## locomotion.
class_name Vehicle
extends AnimatableBody3D

signal destroyed(points: int)

enum Kind {TANK, APC, TRUCK, BMP, SAM, HELI, SHAHED}

## Authored GLB models for all combat vehicle types.
const MODEL_PATHS := {
	Kind.TANK: "res://Assets/vehicles/low_poly_t-72_tank_-_game_ready.glb",
	Kind.BMP: "res://Assets/vehicles/low-poly_bmp-2m.glb",
	Kind.APC: "res://Assets/vehicles/btr-90_ussr.glb",
	Kind.TRUCK: "res://Assets/vehicles/gaz_tigr_low_poly.glb",
	Kind.SAM: "res://Assets/vehicles/btr-90_ussr.glb",
	Kind.HELI: "res://Assets/vehicles/apache_hecu_half-life.glb",
	Kind.SHAHED: "res://Assets/Drones/shahed-136.glb",
}
const MOBILE_HELI_MODEL := "res://Assets/vehicles/apache_hecu_half-life_mobile.glb"
const MODEL_SIZE := {
	Kind.TANK: 9.2,
	Kind.BMP: 7.2,
	Kind.APC: 8.2,
	Kind.TRUCK: 5.6,
	Kind.SAM: 8.2,
	Kind.HELI: 16.5,
	Kind.SHAHED: 3.8,
}
const MODEL_PITCH := {}
## Calibrated yaw so every authored GLB model has its visual front (gun barrel,
## nose, hood, cockpit, warhead) pointing strictly along -Z (Godot forward).
const MODEL_YAW := {
	Kind.TANK: 0.0,
	Kind.BMP: PI,
	Kind.APC: PI * 0.5,
	Kind.TRUCK: PI,
	Kind.SAM: PI * 0.5,
	Kind.HELI: PI,
	Kind.SHAHED: PI,
}
const MODEL_OFFSET := {}
const MODEL_BOX := {
	Kind.TANK: Vector3(3.6, 2.4, 7.6),
	Kind.BMP: Vector3(3.2, 2.4, 6.8),
	Kind.APC: Vector3(3.1, 2.6, 7.8),
	Kind.TRUCK: Vector3(2.4, 2.4, 5.4),
	Kind.SAM: Vector3(3.2, 3.6, 7.8),
}
const ENGINE_DB := {
	Kind.TANK: 3.5, Kind.BMP: 2.0, Kind.APC: 1.5, Kind.TRUCK: 0.5,
	Kind.SAM: 2.0, Kind.HELI: 4.5, Kind.SHAHED: 3.5,
}
const TracerScript = preload("res://combat/tracer.gd")
const ExplosionScript = preload("res://combat/explosion.gd")
const CombatSfxScript = preload("res://combat/sfx.gd")
const EnemyMarkingsScript = preload("res://combat/enemy_markings.gd")
const HitFxScript = preload("res://combat/hit_fx.gd")
const DestructionFxScript = preload("res://combat/destruction_fx.gd")
const FrontlineTerrainScript = preload("res://scripts/util/frontline_terrain.gd")

@export var fire_range := 78.0
@export var tracer_damage := 6.0
@export var fire_interval := 1.15
@export var tracer_speed := 120.0

@export var kind: int = Kind.TANK
@export var max_health := 320.0
@export var points := 300
@export var move_speed := 9.0
@export var hostile := false
@export var track_drone := false
@export var cruise_height := 45.0
@export var meander_amplitude := 0.0
@export var halt_interval := 0.0
@export var halt_duration := 4.0
@export var downwash_radius := 18.0
@export var downwash_strength := 8.0
## Chaos battle: fight another AI unit instead of the player drone.
@export var ai_vs_ai := false
@export var ai_team := 0
var ai_target: Node3D = null

var health := 0.0
var is_destroyed := false
var _stuck_time := 0.0
var _last_obstacle_normal := Vector3.ZERO

var _waypoints: PackedVector3Array = PackedVector3Array()
var _wp_index := 0
var _wheels: Array[Node3D] = []
var _front_wheels: Array[Node3D] = []
var _wheel_radius := 0.52
var _steer_angle := 0.0
var _turret: Node3D = null
var _barrel: Node3D = null
var _barrel_rest_z := 0.0
var _barrel_recoil := 0.0
var _radar: Node3D = null
var _rotor: Node3D = null
var _tail_rotor: Node3D = null
var _drone: Node3D = null
var _vehicle_model: Node3D = null
var _lod_proxy: Node3D = null
var _lod_tick := 0.0
var _visual_lod := 0
## Low-end presets tick distant vehicles at half rate.
var _ai_low := false
var _ai_tick := 0
var _ground := 0.0
var _ground_normal := Vector3.UP
var _prev_speed := 0.0
var _yaw_vel := 0.0
var _susp_pitch := 0.0
var _susp_roll := 0.0
var _damage_speed_mult := 1.0
var _smoke_started := false
var _fire_started := false
var _avoid_yaw := 0.0
var _flash_mesh: Array[MeshInstance3D] = []
var _flash_material: StandardMaterial3D = null
var _flash_token := 0
## Aerial wrecks fall out of the sky instead of freezing where they were hit.
var _crash_falling := false
var _crash_vel := Vector3.ZERO
var _crash_ground_y := 0.0
var _crash_spin := 0.0
var _crash_roll := 0.0
var _crash_pitch := 0.0
var _crash_trail_cd := 0.0
var _crash_smoke: GPUParticles3D = null
var _crash_fire: GPUParticles3D = null
var _fire_cd := 1.0
var _engaging := false
var _muzzle_height := 1.8
var _half_len := 3.0
var _step := 0.0
var _weave_phase := 0.0
var _halt_cd := 0.0
var _halt_left := 0.0
var _engine_player: AudioStreamPlayer3D = null
var _track_player: AudioStreamPlayer3D = null
var _engine_speed := 0.0
var _base_engine_pitch := 1.0
var _backfire_cd := 2.0
var _servo_cd := 0.6
var _turn_rate := 1.8
## Weak spots: a hit close to the engine deck or the ammunition rack does
## extra damage and awards bonus score the first time each module is hit.
var _weak_spots: Array[Dictionary] = []
var _weak_hits: Dictionary = {}
var _weak_markers: Array[MeshInstance3D] = []
var _bonus_points := 0
var _last_hit_fx_ms := 0
var _dust: CPUParticles3D = null
var _track_mats: Array[StandardMaterial3D] = []
static var _track_texture: ImageTexture = null
static var _wheel_texture: ImageTexture = null
static var _vehicle_normal: NoiseTexture2D = null
static var _vehicle_camo: NoiseTexture2D = null


func _ready() -> void:
	_configure_stats_by_kind()
	match Global.difficulty:
		Global.Difficulty.RECRUIT:
			tracer_damage *= 0.65
			fire_range *= 0.80
			fire_interval *= 1.35
		Global.Difficulty.ACE:
			tracer_damage *= 1.35
			fire_range *= 1.20
			fire_interval *= 0.80
	health = max_health
	add_to_group("combat_target")
	add_to_group("vehicle")
	collision_layer = 1
	collision_mask = 1
	sync_to_physics = false
	_build_body()
	_setup_weak_spots()
	_setup_engine_audio()
	if halt_interval > 0.0:
		_halt_cd = randf_range(halt_interval * 0.4, halt_interval)
	_weave_phase = randf() * TAU
	_drone = get_tree().current_scene.get_node_or_null("Drone") as Node3D
	_ai_low = QualityManager.get_active_level() == QualityManager.Level.LOW


func _configure_stats_by_kind() -> void:
	match kind:
		Kind.TANK:
			max_health = 420.0
			points = 450
			fire_range = 125.0
			fire_interval = 2.8
			tracer_damage = 14.0
			tracer_speed = 145.0
			_turn_rate = 1.35
		Kind.BMP:
			max_health = 280.0
			points = 350
			fire_range = 120.0
			fire_interval = 0.55
			tracer_damage = 5.5
			tracer_speed = 135.0
			_turn_rate = 2.2
		Kind.APC:
			max_health = 240.0
			points = 300
			fire_range = 110.0
			fire_interval = 0.75
			tracer_damage = 4.5
			tracer_speed = 125.0
			_turn_rate = 2.4
		Kind.TRUCK:
			max_health = 160.0
			points = 220
			fire_range = 75.0
			fire_interval = 1.4
			tracer_damage = 3.0
			tracer_speed = 110.0
			_turn_rate = 2.8
		Kind.SAM:
			max_health = 320.0
			points = 550
			fire_range = 150.0
			fire_interval = 0.65
			tracer_damage = 9.0
			tracer_speed = 160.0
			_turn_rate = 1.5
		Kind.HELI:
			max_health = 360.0
			points = 600
			fire_range = 140.0
			fire_interval = 0.45
			tracer_damage = 6.5
			tracer_speed = 140.0
			_turn_rate = 1.9
		Kind.SHAHED:
			max_health = 90.0
			points = 500
			fire_range = 0.0
			_turn_rate = 1.6


# ------------------------------------------------------------------ build
func _mat(color: Color, roughness := 0.7, metallic := 0.0, emission := Color(0, 0, 0)) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	if emission != Color(0, 0, 0):
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = 2.5
	return material


func _box(parent: Node3D, size: Vector3, pos: Vector3, material: StandardMaterial3D,
		rot := Vector3.ZERO) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = pos
	mesh.rotation = rot
	mesh.material_override = material
	parent.add_child(mesh)
	_flash_mesh.append(mesh)
	return mesh


func _cyl(parent: Node3D, radius: float, height: float, pos: Vector3,
		material: StandardMaterial3D, rot := Vector3.ZERO) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 12
	mesh.mesh = cyl
	mesh.position = pos
	mesh.rotation = rot
	mesh.material_override = material
	parent.add_child(mesh)
	_flash_mesh.append(mesh)
	return mesh


func _build_body() -> void:
	if MODEL_PATHS.has(kind):
		var path: String = MODEL_PATHS[kind]
		# The original Apache has 46 separate material-bearing mesh objects.
		# Use a mobile-only joined-by-material export (rotor pieces remain
		# separate) to cut scene-node traversal and draw submission; PC retains
		# its original authored asset.
		if kind == Kind.HELI and (OS.get_name() == "iOS" or OS.has_feature("mobile") \
				or OS.has_environment("MOBILE_UI")) \
				and ResourceLoader.exists(MOBILE_HELI_MODEL):
			path = MOBILE_HELI_MODEL
		if ResourceLoader.exists(path) and _build_from_model(path, float(MODEL_SIZE.get(kind, 7.0))):
			if kind == Kind.SAM:
				_attach_sam_radar_turret()
			return
	var hull := _mat(Color(0.20, 0.24, 0.16), 0.75)
	var dark := _mat(Color(0.07, 0.075, 0.08), 0.6)
	var metal := _mat(Color(0.16, 0.17, 0.19), 0.4, 0.7)
	var glass := _mat(Color(0.05, 0.09, 0.12), 0.2, 0.3)
	var light := _mat(Color(1.0, 0.9, 0.6), 0.3, 0.0, Color(1.0, 0.85, 0.5))
	_build_fallback_hull(hull, dark, metal, glass, light)


func _attach_sam_radar_turret() -> void:
	var hull := _mat(Color(0.22, 0.26, 0.18), 0.75)
	var metal := _mat(Color(0.16, 0.18, 0.20), 0.4, 0.7)
	var light := _mat(Color(1.0, 0.45, 0.15), 0.3, 0.0, Color(1.0, 0.35, 0.1))
	_turret = Node3D.new()
	_turret.position = Vector3(0.0, 2.35, 0.2)
	add_child(_turret)
	_box(_turret, Vector3(1.5, 0.65, 1.8), Vector3(0, 0.32, 0), hull)
	for side in [-0.55, 0.55]:
		_cyl(_turret, 0.18, 2.4, Vector3(side, 0.78, -0.35), metal, Vector3(deg_to_rad(62.0), 0, 0))
		_cyl(_turret, 0.18, 2.4, Vector3(side, 1.12, -0.35), metal, Vector3(deg_to_rad(62.0), 0, 0))
	_radar = Node3D.new()
	_radar.position = Vector3(0, 1.35, 0.45)
	_turret.add_child(_radar)
	_box(_radar, Vector3(1.65, 0.55, 0.14), Vector3(0, 0.25, 0), metal)
	_box(_radar, Vector3(0.22, 0.22, 0.22), Vector3(0, 0.62, 0), light)


func _build_fallback_hull(hull: StandardMaterial3D, dark: StandardMaterial3D,
		metal: StandardMaterial3D, _glass: StandardMaterial3D, _light: StandardMaterial3D) -> void:
	# Strictly aligned along -Z (forward) if a GLB is ever missing.
	_box(self, Vector3(3.0, 1.4, 6.2), Vector3(0, 0.9, 0), hull)
	_turret = Node3D.new()
	_turret.position = Vector3(0, 1.8, 0)
	add_child(_turret)
	_box(_turret, Vector3(2.0, 0.7, 2.4), Vector3.ZERO, hull)
	_cyl(_turret, 0.12, 3.2, Vector3(0, 0.05, -2.2), metal, Vector3(PI * 0.5, 0, 0))
	_add_collider(Vector3(3.2, 2.4, 6.4), Vector3(0, 1.2, 0))


func _normalise_model(model: Node3D, target_len: float) -> void:
	var box := DroneCatalog.model_bounds(model)
	var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	if longest <= 0.001:
		return
	model.scale = Vector3.ONE * (target_len / longest)


func _add_collider(size: Vector3, pos: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = pos
	add_child(col)


# ------------------------------------------------------------------ model
func _build_from_model(path: String, target: float) -> bool:
	var packed := load(path) as PackedScene
	if packed == null:
		return false
	var model := packed.instantiate() as Node3D
	if model == null:
		return false
	model.name = "Model"
	model.set_meta("source_glb", path)
	add_child(model)
	model.rotation = Vector3(float(MODEL_PITCH.get(kind, 0.0)),
			float(MODEL_YAW.get(kind, 0.0)), 0.0)
	_normalise_model(model, target)
	var bounds := DroneCatalog.model_bounds(model)
	var center := bounds.get_center()
	# Center X and Z on the Vehicle node origin, and place lowest vertex (wheels/tracks) right on Y = 0.
	model.global_position += Vector3(
			global_position.x - center.x,
			global_position.y - bounds.position.y,
			global_position.z - center.z)
	model.global_position += MODEL_OFFSET.get(kind, Vector3.ZERO)

	_apply_vehicle_style(model)
	_add_vehicle_detail()

	var box := DroneCatalog.model_bounds(model)
	var size: Vector3 = MODEL_BOX.get(kind, box.size)
	if size.length_squared() < 0.01:
		size = Vector3(target * 0.45, target * 0.32, target * 0.85)
	_vehicle_model = model
	if OS.get_name() == "iOS" or OS.has_feature("mobile") \
			or OS.has_environment("MOBILE_UI"):
		_setup_mobile_lod_proxy(size)
	if kind == Kind.APC or kind == Kind.TRUCK or kind == Kind.SAM:
		_setup_running_gear(size)
	_muzzle_height = clampf(size.y * 0.82, 1.4, 3.0)
	_half_len = maxf(size.z * 0.5, 2.0)

	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(size.x, 1.2), maxf(size.y, 1.2), maxf(size.z, 1.2))
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0.0, shape.size.y * 0.5, 0.0)
	add_child(col)

	_collect_meshes(model, _flash_mesh)
	if kind == Kind.TANK or kind == Kind.BMP:
		_setup_track_belts()
	if kind != Kind.HELI and kind != Kind.SHAHED:
		_setup_dust()
	if kind == Kind.HELI:
		_setup_glb_rotors(model)
	var player := _find_animation_player(model)
	if player != null:
		var names := player.get_animation_list()
		if not names.is_empty():
			player.play(names[0])
	return true


## A far-field silhouette for the Mobile renderer.  Full authored models stay
## visible near the FPV camera; beyond that, one/two unshaded boxes preserve
## the vehicle read at a fraction of the material/draw-call cost.  Collision,
## targeting, weapon logic and damage continue on the original node/model.
func _setup_mobile_lod_proxy(size: Vector3) -> void:
	if _lod_proxy != null:
		_lod_proxy.queue_free()
	_lod_proxy = Node3D.new()
	_lod_proxy.name = "MobileLodProxy"
	_lod_proxy.visible = false
	add_child(_lod_proxy)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = _lod_proxy_color()
	mat.roughness = 1.0
	match kind:
		Kind.HELI:
			_add_lod_box(Vector3(size.x * 0.34, size.y * 0.34, size.z * 0.72),
					Vector3(0.0, size.y * 0.52, 0.0), mat)
			_add_lod_box(Vector3(size.x * 1.45, 0.035, 0.07),
					Vector3.ZERO + Vector3.UP * size.y * 0.82, mat)
			_add_lod_box(Vector3(0.05, 0.035, size.z * 0.55),
					Vector3(0.0, size.y * 0.88, size.z * 0.56), mat)
		Kind.SHAHED:
			_add_lod_box(Vector3(size.x * 0.22, size.y * 0.18, size.z),
					Vector3(0.0, size.y * 0.54, 0.0), mat)
			_add_lod_box(Vector3(size.x, size.y * 0.06, size.z * 0.28),
					Vector3(0.0, size.y * 0.50, 0.0), mat)
		_:
			_add_lod_box(Vector3(size.x * 0.84, size.y * 0.42, size.z * 0.90),
					Vector3(0.0, size.y * 0.40, 0.0), mat)
			_add_lod_box(Vector3(size.x * 0.45, size.y * 0.25, size.z * 0.35),
					Vector3(0.0, size.y * 0.72, 0.0), mat)
	_lod_proxy.visible = false


func _add_lod_box(box_size: Vector3, at: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = box_size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lod_proxy.add_child(instance)


func _lod_proxy_color() -> Color:
	match kind:
		Kind.TANK: return Color(0.31, 0.39, 0.23)
		Kind.BMP: return Color(0.27, 0.34, 0.21)
		Kind.APC: return Color(0.43, 0.49, 0.34)
		Kind.TRUCK: return Color(0.55, 0.51, 0.38)
		Kind.SAM: return Color(0.35, 0.42, 0.28)
		Kind.HELI: return Color(0.32, 0.37, 0.25)
		Kind.SHAHED: return Color(0.50, 0.35, 0.18)
	return Color(0.38, 0.42, 0.32)


func _update_mobile_lod(delta: float) -> void:
	if not (OS.has_feature("mobile") or OS.get_name() == "iOS" \
			or OS.has_environment("MOBILE_UI")):
		return
	_lod_tick -= delta
	if _lod_tick > 0.0:
		return
	_lod_tick = 0.25
	if is_destroyed:
		if _lod_proxy != null:
			_lod_proxy.visible = false
		return
	var cam := get_viewport().get_camera_3d()
	var viewer := cam.global_position if cam != null else \
			(_drone.global_position if _drone != null and is_instance_valid(_drone) else global_position)
	var dist := viewer.distance_to(global_position)
	var next_lod := 0 if dist < 180.0 else (1 if dist < 480.0 else 2)
	if next_lod == _visual_lod:
		return
	_visual_lod = next_lod
	if _vehicle_model != null and is_instance_valid(_vehicle_model):
		_vehicle_model.visible = next_lod == 0
	if _lod_proxy != null:
		_lod_proxy.visible = next_lod == 1


## Give every vehicle a weathered, theatre-appropriate finish.  Textured models
## keep their detail but get a green/olive tint; untextured low-poly meshes get
## a matte camo base.  A triplanar noise normal adds rivets/paint relief without
## requiring UVs (the BMP/BTR have none), which is what made them look like
## plastic toys.
func _apply_vehicle_style(model: Node3D) -> void:
	var tint := Color(0.80, 0.86, 0.70)
	match kind:
		Kind.TANK:
			tint = Color(0.66, 0.74, 0.52)
		Kind.BMP:
			tint = Color(0.31, 0.37, 0.22)
		Kind.APC:
			tint = Color(0.58, 0.65, 0.46)
		Kind.TRUCK:
			tint = Color(0.78, 0.74, 0.62)
		Kind.SAM:
			tint = Color(0.45, 0.51, 0.34)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := mi as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		for s in range(mesh.mesh.get_surface_count()):
			var source := mesh.mesh.surface_get_material(s)
			var mat: StandardMaterial3D
			if source is StandardMaterial3D:
				mat = (source as StandardMaterial3D).duplicate() as StandardMaterial3D
			else:
				mat = StandardMaterial3D.new()
			if mat.albedo_texture != null:
				mat.albedo_color = tint
			else:
				var base := Color(0.3, 0.3, 0.3)
				if source is StandardMaterial3D:
					base = (source as StandardMaterial3D).albedo_color
				if base.v < 0.13:
					# Tracks, tyres, grilles and vision blocks stay dark.
					mat.albedo_color = Color(0.055, 0.06, 0.055)
				else:
					mat.albedo_texture = _vehicle_camo_texture()
					mat.albedo_color = tint
					mat.uv1_triplanar = true
					mat.uv1_scale = Vector3(0.32, 0.32, 0.32)
			mat.roughness = clampf(maxf(mat.roughness, 0.62), 0.62, 0.94)
			mat.metallic = maxf(mat.metallic, 0.08)
			mat.normal_enabled = true
			mat.normal_texture = _vehicle_normal_texture()
			mat.uv1_triplanar = true
			mat.uv1_scale = Vector3(0.55, 0.55, 0.55)
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			mesh.set_surface_override_material(s, mat)


static func _vehicle_normal_texture() -> NoiseTexture2D:
	if _vehicle_normal != null:
		return _vehicle_normal
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.055
	noise.fractal_octaves = 4
	noise.fractal_gain = 0.55
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.as_normal_map = true
	tex.bump_strength = 1.8
	tex.noise = noise
	_vehicle_normal = tex
	return tex


static func _vehicle_camo_texture() -> NoiseTexture2D:
	if _vehicle_camo != null:
		return _vehicle_camo
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.035
	noise.fractal_octaves = 3
	noise.fractal_gain = 0.55
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.38, 0.62, 0.82, 1.0])
	grad.colors = PackedColorArray([
		Color(0.16, 0.19, 0.11), Color(0.27, 0.31, 0.18),
		Color(0.36, 0.37, 0.23), Color(0.22, 0.25, 0.15),
		Color(0.45, 0.43, 0.31),
	])
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = grad
	_vehicle_camo = tex
	return tex


func _setup_track_belts() -> void:
	if _track_texture == null:
		_track_texture = _make_track_texture()
	var box: Vector3 = MODEL_BOX.get(kind, Vector3(3.0, 2.0, 6.0))
	var length := maxf(box.z * 0.82, 3.0)
	for side in [-1.0, 1.0]:
		var belt := MeshInstance3D.new()
		belt.name = "TrackBelt_%s" % ("L" if side < 0 else "R")
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.18, 0.42, length)
		belt.mesh = mesh
		belt.position = Vector3(side * box.x * 0.38, 0.33, 0.0)
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = _track_texture
		mat.albedo_color = Color(0.62, 0.64, 0.58)
		mat.roughness = 0.92
		mat.metallic = 0.35
		mat.uv1_scale = Vector3(maxf(1.0, length * 1.1), 5.0, 1.0)
		mat.uv1_offset = Vector3(0, 0, 0)
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		belt.material_override = mat
		belt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(belt)
		_track_mats.append(mat)
		_flash_mesh.append(belt)


static func _make_track_texture() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.035, 0.038, 0.034, 1.0))
	for y in range(64):
		if y % 8 < 2:
			for x in range(64):
				img.set_pixel(x, y, Color(0.13, 0.14, 0.12, 1.0))
		elif y % 8 == 4:
			for x in range(0, 64, 8):
				img.set_pixel(x, y, Color(0.20, 0.21, 0.18, 1.0))
				img.set_pixel(x + 1, y, Color(0.16, 0.17, 0.15, 1.0))
	return ImageTexture.create_from_image(img)


## Wheeled running gear for BTR-90 / Tigr.  The source GLBs merge all wheels
## into the hull mesh, so a slightly larger animated tyre + spoked rim is laid
## over each axle.  The tyre bottom sits exactly on Y=0, the same contact plane
## the GLB was normalised to.


func _setup_running_gear(size: Vector3) -> void:
	if _wheel_texture == null:
		_wheel_texture = _make_wheel_texture()
	var radius := 0.56
	var width := 0.34
	var axles: Array[float] = []
	var half_x := size.x * 0.37
	if kind == Kind.TRUCK:
		radius = 0.49
		width = 0.30
		axles = [-size.z * 0.29, size.z * 0.29]
	else:
		# BTR-90: four axles per side.
		axles = [-size.z * 0.31, -size.z * 0.10,
				size.z * 0.10, size.z * 0.31]
	_wheel_radius = radius
	for side in [-1.0, 1.0]:
		for axle in axles:
			_add_wheel(Vector3(side * half_x, radius, axle), radius, width, axle < -0.05)


func _add_wheel(pos: Vector3, radius: float, width: float, is_front: bool = false) -> void:
	var pivot := Node3D.new()
	pivot.name = "WheelPivot"
	pivot.position = pos
	add_child(pivot)
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = width
	cyl.radial_segments = 18
	cyl.rings = 1
	mesh.mesh = cyl
	# Cylinder axis is +Y; rotate it onto the axle (+X).
	mesh.rotation.z = PI * 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _wheel_texture
	mat.albedo_color = Color(0.55, 0.56, 0.52)
	mat.roughness = 0.86
	mat.metallic = 0.16
	mat.uv1_scale = Vector3(1.0, 1.0, 1.0)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	pivot.add_child(mesh)
	_wheels.append(pivot)
	if is_front:
		_front_wheels.append(pivot)
	_flash_mesh.append(mesh)


static func _make_wheel_texture() -> ImageTexture:
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.045, 0.047, 0.042, 1.0))
	var center := Vector2(64.0, 64.0)
	for y in range(128):
		for x in range(128):
			var d := Vector2(x - center.x, y - center.y).length()
			if d > 63.0:
				continue
			# Tyre wall and tread.
			if d > 46.0:
				var tread := 0.055 if int((atan2(y - 64, x - 64) + PI) * 14.0) % 2 == 0 else 0.10
				img.set_pixel(x, y, Color(tread, tread + 0.006, tread - 0.004, 1.0))
			elif d > 31.0:
				# Steel rim with a dark recess.
				var rim := 0.24 + 0.10 * (1.0 - (d - 31.0) / 15.0)
				img.set_pixel(x, y, Color(rim, rim * 1.02, rim * 0.96, 1.0))
			else:
				# Eight bright spokes and a dark hub.
				var ang := atan2(y - 64, x - 64)
				var spoke := absf(sin(ang * 4.0))
				if spoke > 0.72:
					img.set_pixel(x, y, Color(0.48, 0.50, 0.45, 1.0))
				elif d < 9.0:
					img.set_pixel(x, y, Color(0.30, 0.31, 0.28, 1.0))
				else:
					img.set_pixel(x, y, Color(0.10, 0.105, 0.095, 1.0))
	return ImageTexture.create_from_image(img)


func _setup_dust() -> void:
	_dust = CPUParticles3D.new()
	_dust.name = "DustTrail"
	_dust.amount = 18
	_dust.lifetime = 1.15
	_dust.local_coords = false
	_dust.position = Vector3(0.0, 0.35, 2.2)
	_dust.direction = Vector3(0.0, 0.25, 1.0)
	_dust.spread = 28.0
	_dust.initial_velocity_min = 1.0
	_dust.initial_velocity_max = 2.8
	_dust.gravity = Vector3(0.0, 0.5, 0.0)
	_dust.scale_amount_min = 0.35
	_dust.scale_amount_max = 1.15
	_dust.emitting = false
	var quad := QuadMesh.new()
	quad.size = Vector2(1.25, 1.25)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	grad.colors = PackedColorArray([
		Color(0.52, 0.45, 0.32, 0.34),
		Color(0.48, 0.42, 0.30, 0.18),
		Color(0.45, 0.40, 0.30, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	quad.material = mat
	_dust.mesh = quad
	add_child(_dust)


## Bolt-on silhouette detail: side skirts, ERA blocks, stowage, fuel drums,
## antennas and machine guns.  These do not change hitboxes or behaviour; they
## simply stop the low-poly hulls reading as smooth plastic figurines.
func _add_vehicle_detail() -> void:
	var armor := _mat(Color(0.20, 0.24, 0.15), 0.82, 0.10)
	var dark := _mat(Color(0.07, 0.08, 0.06), 0.70, 0.20)
	var metal := _mat(Color(0.15, 0.16, 0.17), 0.46, 0.65)
	match kind:
		Kind.TANK:
			# Track skirts and rubber flaps.
			for side in [-1.0, 1.0]:
				_box(self, Vector3(0.10, 0.52, 4.9),
						Vector3(side * 1.42, 0.62, 0.0), armor)
				_box(self, Vector3(0.16, 0.16, 4.7),
						Vector3(side * 1.40, 0.30, 0.0), dark)
			# ERA bricks across the glacis.
			for i in range(7):
				_box(self, Vector3(0.30, 0.16, 0.13),
						Vector3(-0.93 + i * 0.31, 0.98, -2.86), armor)
			# Rear fuel drums and stowage.
			for side in [-1.0, 1.0]:
				_cyl(self, 0.27, 0.82, Vector3(side * 0.92, 1.02, 2.55),
						metal, Vector3(0.0, 0.0, PI * 0.5))
			# Articulated turret mount + recoil barrel
			_turret = Node3D.new()
			_turret.name = "TurretMount"
			_turret.position = Vector3(0.0, 1.80, 0.0)
			add_child(_turret)
			for side in [-1.0, 1.0]:
				for i in range(3):
					_box(_turret, Vector3(0.22, 0.18, 0.30),
							Vector3(side * (0.62 + i * 0.13), 0.0,
									-0.55 + i * 0.26), armor,
							Vector3(0.0, side * 0.28, 0.0))
			_box(_turret, Vector3(1.10, 0.30, 0.55), Vector3(0.0, 0.38, 0.62), dark)
			_box(_turret, Vector3(0.12, 0.12, 0.62), Vector3(0.42, 0.62, -0.62), metal)
			_cyl(_turret, 0.014, 1.35, Vector3(-0.78, 0.75, 0.72), dark)
			_barrel = Node3D.new()
			_barrel.name = "BarrelPivot"
			_barrel.position = Vector3(0.0, 0.18, -0.95)
			_barrel_rest_z = _barrel.position.z
			_turret.add_child(_barrel)
			_cyl(_barrel, 0.075, 2.85, Vector3(0.0, 0.0, -1.42), metal,
					Vector3(PI * 0.5, 0.0, 0.0))
		Kind.BMP, Kind.APC:
			for side in [-1.0, 1.0]:
				_box(self, Vector3(0.09, 0.46, 4.5),
						Vector3(side * 1.33, 0.55, 0.0), armor)
			_box(self, Vector3(0.90, 0.28, 0.42), Vector3(-0.55, 1.70, 1.65), dark)
			_box(self, Vector3(2.5, 0.16, 0.28), Vector3(0.0, 0.62, -2.95), dark)
			_turret = Node3D.new()
			_turret.name = "TurretMount"
			_turret.position = Vector3(0.0, 1.85, -0.15)
			add_child(_turret)
			_cyl(_turret, 0.014, 1.25, Vector3(0.82, 0.60, 0.80), dark)
			_barrel = Node3D.new()
			_barrel.name = "BarrelPivot"
			_barrel.position = Vector3(0.0, 0.35, -0.45)
			_barrel_rest_z = _barrel.position.z
			_turret.add_child(_barrel)
			if kind == Kind.BMP:
				_cyl(_barrel, 0.065, 1.65, Vector3(0.0, 0.0, -0.82), metal,
						Vector3(PI * 0.5, 0.0, 0.0))
				_box(_turret, Vector3(0.30, 0.18, 0.40), Vector3(0.0, 0.39, -0.03), dark)
			else:
				_cyl(_barrel, 0.055, 1.45, Vector3(0.0, 0.0, -0.72), metal,
						Vector3(PI * 0.5, 0.0, 0.0))
				_box(_turret, Vector3(0.42, 0.26, 0.46), Vector3(0.55, 0.40, -0.20), metal)
		Kind.TRUCK:
			# Roof machine gun, spare wheel and antennas.
			_turret = Node3D.new()
			_turret.name = "TurretMount"
			_turret.position = Vector3(0.0, 2.78, -0.35)
			add_child(_turret)
			_box(_turret, Vector3(0.12, 0.12, 0.58), Vector3.ZERO, metal)
			_barrel = Node3D.new()
			_barrel.name = "BarrelPivot"
			_barrel.position = Vector3(0.0, 0.0, -0.28)
			_barrel_rest_z = _barrel.position.z
			_turret.add_child(_barrel)
			_cyl(_barrel, 0.030, 0.62, Vector3(0.0, 0.0, -0.32), metal,
					Vector3(PI * 0.5, 0.0, 0.0))
			_cyl(self, 0.38, 0.20, Vector3(0.0, 1.35, 2.42), dark,
					Vector3(PI * 0.5, 0.0, 0.0))
			_cyl(self, 0.014, 1.15, Vector3(-0.92, 2.35, 0.55), dark)
			_box(self, Vector3(2.15, 0.16, 0.20), Vector3(0.0, 0.95, -2.55), metal)
		Kind.SAM:
			# The radar turret is added separately; dress the hull.
			for side in [-1.0, 1.0]:
				_box(self, Vector3(0.10, 0.50, 4.7),
						Vector3(side * 1.35, 0.60, 0.0), armor)
			_box(self, Vector3(1.2, 0.28, 0.5), Vector3(0.0, 1.75, 1.8), dark)
	if EnemyMarkingsScript.is_russian_vehicle(self):
		var mark_box: Vector3 = MODEL_BOX.get(kind, Vector3(3.0, 1.8, 5.0))
		if kind == Kind.HELI:
			mark_box = Vector3(3.6, 2.8, 12.0)
		elif kind == Kind.SHAHED:
			mark_box = Vector3(2.1, 0.9, 3.2)
		EnemyMarkingsScript.mark_vehicle(self, mark_box)


## Two exposed modules per vehicle.  The engine is at the rear (+Z, opposite
## the -Z nose) and the ammunition rack sits in the middle of the hull or in
## the turret.  Hits inside the module radius deal 60-70% extra damage; the
## first hit on each module also awards score, so a skilled pilot is rewarded
## for aiming instead of spraying the thickest armour.
func _setup_weak_spots() -> void:
	var box: Vector3 = MODEL_BOX.get(kind, Vector3(3.0, 1.7, 6.0))
	var engine := Vector3(0.0, box.y * 0.55, box.z * 0.36)
	var ammo := Vector3(box.x * 0.30, box.y * 0.74, -box.z * 0.08)
	var engine_size := Vector3(0.95, 0.42, 0.08)
	var ammo_size := Vector3(0.08, 0.40, 0.72)
	var ammo_rot := Vector3(0.0, PI * 0.5, 0.0)
	if kind == Kind.HELI:
		# Engine exhausts are under the rotor mast at the tail; the ammo bay is
		# in the forward fuselage behind the cockpit.
		engine = Vector3(0.0, 1.15, 4.9)
		ammo = Vector3(0.85, 1.05, -1.3)
		ammo_rot = Vector3(0.0, PI * 0.5, 0.0)
	elif kind == Kind.SHAHED:
		engine = Vector3(0.0, 0.45, 1.45)
		ammo = Vector3(0.0, 0.55, 0.15)
		ammo_size = Vector3(0.55, 0.10, 0.55)
		ammo_rot = Vector3.ZERO
	_register_weak_spot("engine", engine, 1.35, 1.70, 35,
			engine_size, Vector3.ZERO)
	_register_weak_spot("ammo", ammo, 1.15, 1.60, 50,
			ammo_size, ammo_rot)


func _register_weak_spot(spot_name: String, local_pos: Vector3, radius: float,
		damage_mult: float, bonus: int, plate_size: Vector3,
		plate_rot: Vector3) -> void:
	_weak_spots.append({
		"name": spot_name,
		"pos": local_pos,
		"radius": radius,
		"mult": damage_mult,
		"bonus": bonus,
	})
	var marker := MeshInstance3D.new()
	marker.name = "WeakSpot_" + spot_name
	var mesh := BoxMesh.new()
	mesh.size = plate_size
	marker.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.16, 0.06)
	mat.roughness = 0.65
	mat.emission_enabled = true
	mat.emission = Color(0.95, 0.34, 0.08)
	mat.emission_energy_multiplier = 0.85
	marker.material_override = mat
	marker.position = local_pos
	marker.rotation = plate_rot
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(marker)
	_weak_markers.append(marker)
	_flash_mesh.append(marker)


func _weak_spot_multiplier(hit_position: Vector3) -> float:
	if hit_position == Vector3.ZERO or _weak_spots.is_empty():
		return 1.0
	var best := 1.0
	for spot in _weak_spots:
		var world: Vector3 = to_global(spot["pos"])
		if hit_position.distance_to(world) > float(spot["radius"]):
			continue
		best = maxf(best, float(spot["mult"]))
		var id: String = spot["name"]
		if not _weak_hits.has(id):
			_weak_hits[id] = true
			_bonus_points += int(spot["bonus"])
			ExplosionScript.spark_burst(get_parent(), world)
			_hide_weak_marker(id)
	return best


func _hide_weak_marker(spot_name: String) -> void:
	var marker_name := "WeakSpot_" + spot_name
	for marker in _weak_markers:
		if is_instance_valid(marker) and String(marker.name) == marker_name:
			marker.visible = false


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _setup_glb_rotors(model: Node3D) -> void:
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(model, meshes)
	if meshes.is_empty():
		return
	var total := AABB()
	var first := true
	for mi in meshes:
		var b: AABB = mi.global_transform * mi.get_aabb()
		if first:
			total = b
			first = false
		else:
			total = total.merge(b)
	var blades: Array[MeshInstance3D] = []
	for mi in meshes:
		var b: AABB = mi.global_transform * mi.get_aabb()
		var s := b.size
		if s.y < total.size.y * 0.14 and s.x > total.size.x * 0.55 \
				and s.z > total.size.z * 0.55:
			blades.append(mi)
	_rotor = _make_rotor_pivot(model, blades, "MainRotor")


func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if out.size() >= 2:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 550.0
		out.append(mi)
	for child in node.get_children():
		_collect_meshes(child, out)


func _make_rotor_pivot(parent: Node3D, parts: Array[MeshInstance3D],
		pivot_name: String) -> Node3D:
	if parts.is_empty():
		return null
	var union := AABB()
	var first := true
	for mi in parts:
		var b: AABB = mi.global_transform * mi.get_aabb()
		if first:
			union = b
			first = false
		else:
			union = union.merge(b)
	var pivot := Node3D.new()
	pivot.name = pivot_name
	parent.add_child(pivot)
	pivot.global_position = union.get_center()
	for mi in parts:
		mi.reparent(pivot, true)
	return pivot


# ------------------------------------------------------------------ audio
func _setup_engine_audio() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var stream := _engine_stream_for_kind()
	if stream == null:
		return
	_engine_player = CombatSfxScript.make_looping_player(stream,
			float(ENGINE_DB.get(kind, 2.0)), 75.0, 1200.0)
	_engine_player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	add_child(_engine_player)
	_engine_player.play()
	# Tracked vehicles get a second clatter layer: the diesel alone reads as a
	# truck, the metallic clanks are what make a T-72 recognisable.
	if kind == Kind.TANK or kind == Kind.BMP:
		_track_player = CombatSfxScript.make_looping_player(
				CombatSfxScript.track_clatter_stream(), -8.0, 65.0, 850.0)
		_track_player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
		add_child(_track_player)
		_track_player.play()
		_track_player.volume_db = -8.0
	if OS.has_environment("DRONE_AUDIO_DEBUG"):
		print("[AUDIO] vehicle kind=", kind, " engine=", _engine_player != null,
				" track=", _track_player != null)
	if kind == Kind.HELI or kind == Kind.SHAHED:
		_base_engine_pitch = 1.0
	else:
		_base_engine_pitch = 0.82


func _engine_stream_for_kind() -> AudioStreamWAV:
	match kind:
		Kind.TANK:
			return CombatSfxScript.tank_engine_stream()
		Kind.BMP:
			return CombatSfxScript.bmp_engine_stream()
		Kind.APC, Kind.SAM:
			return CombatSfxScript.apc_engine_stream()
		Kind.HELI:
			return CombatSfxScript.heli_rotor_stream()
		Kind.SHAHED:
			return CombatSfxScript.shahed_engine_stream()
		_:
			return CombatSfxScript.truck_engine_stream()


func _update_engine_audio(delta: float) -> void:
	if _engine_player == null or not is_instance_valid(_engine_player):
		return
	if is_destroyed:
		_engine_player.stop()
		if _track_player != null and is_instance_valid(_track_player):
			_track_player.stop()
		return
	if not _engine_player.playing:
		_engine_player.play()
	var speed_ratio := clampf(_engine_speed / maxf(move_speed, 0.1), 0.0, 1.0)
	var target_pitch := _base_engine_pitch
	if kind == Kind.HELI:
		target_pitch = 0.95 + speed_ratio * 0.12
	elif kind == Kind.SHAHED:
		target_pitch = 0.98 + speed_ratio * 0.10
	else:
		target_pitch = _base_engine_pitch + speed_ratio * 0.42
	_engine_player.pitch_scale = lerpf(_engine_player.pitch_scale, target_pitch,
			clampf(delta * 3.0, 0.0, 1.0))
	var base_db := float(ENGINE_DB.get(kind, 2.0))
	_engine_player.volume_db = base_db + speed_ratio * 4.0
	if _track_player != null and is_instance_valid(_track_player):
		var move_ratio := clampf(_engine_speed / maxf(move_speed, 0.1), 0.0, 1.0)
		_track_player.volume_db = lerpf(-10.0, 3.0, move_ratio)
		_track_player.pitch_scale = 0.92 + move_ratio * 0.26
	# Occasional exhaust pop under acceleration (trucks and tanks only).
	if kind == Kind.TRUCK or kind == Kind.TANK:
		_backfire_cd -= delta
		if _backfire_cd <= 0.0:
			_backfire_cd = randf_range(3.5, 9.0)
			if speed_ratio > 0.2:
				CombatSfxScript.play_backfire(get_parent(), _muzzle_world(), -19.0)


# ------------------------------------------------------------------ driving
func set_waypoints(points: Array) -> void:
	_waypoints = PackedVector3Array()
	for p in points:
		_waypoints.append(p)
	_wp_index = 0
	var info := _sample_ground(global_position.x, global_position.z)
	_ground = info["y"]
	_ground_normal = info["normal"]
	if kind == Kind.HELI or kind == Kind.SHAHED:
		global_position.y = _ground + cruise_height
	else:
		global_position.y = _ground
	# Immediately orient nose (-Z) toward the next waypoint so the vehicle
	# starts already aligned with its route and never backs up on spawn.
	if _waypoints.size() > 1:
		var next_wp := _waypoints[1]
		var flat := next_wp - global_position
		flat.y = 0.0
		if flat.length_squared() > 0.01:
			rotation.y = atan2(-flat.x, -flat.z)
			_wp_index = 1


func _physics_process(delta: float) -> void:
	_update_mobile_lod(delta)
	if _ai_low and _drone != null and is_instance_valid(_drone):
		var d2 := global_position.distance_squared_to(_drone.global_position)
		if d2 > 62500.0:
			var step := 4 if d2 > 202500.0 else 2
			_ai_tick += 1
			if _ai_tick % step != 0:
				return
	_combat_engage(delta)
	if kind == Kind.HELI:
		_apply_downwash(delta)
	if is_destroyed:
		_update_crash_fall(delta)
		_update_engine_audio(delta)
		return
	if _waypoints.is_empty():
		_engine_speed = 0.0
		_update_height(delta)
		if kind == Kind.HELI:
			if _rotor != null:
				_rotor.rotation.y += delta * 30.0
			if _tail_rotor != null:
				_tail_rotor.rotation.x += delta * 45.0
		if _radar != null:
			_radar.rotation.y += delta * 1.4
		_update_engine_audio(delta)
		return
	_update_halt(delta)
	var holding := _halt_left > 0.0
	var hovering := _engaging and kind == Kind.HELI
	if not holding and not hovering:
		_move_along_route(delta)
	else:
		_step = 0.0
	_update_height(delta)
	_engine_speed = _step / maxf(delta, 0.0001)
	_animate(delta)
	_aim_turret(delta)
	_update_engine_audio(delta)


func _move_along_route(delta: float) -> void:
	var target := _waypoints[_wp_index]
	var flat := target - global_position
	flat.y = 0.0
	var wp_reach := 8.0 if (kind == Kind.HELI or kind == Kind.SHAHED) else 5.5
	if flat.length() < wp_reach:
		_wp_index = (_wp_index + 1) % _waypoints.size()
		target = _waypoints[_wp_index]
		flat = target - global_position
		flat.y = 0.0
		if flat.length_squared() < 0.01:
			_step = 0.0
			return

	var desired_yaw := atan2(-flat.x, -flat.z)
	if meander_amplitude > 0.0 and not _engaging and kind != Kind.HELI and kind != Kind.SHAHED:
		_weave_phase += delta * (0.75 if kind == Kind.TANK else 1.25)
		desired_yaw += sin(_weave_phase) * meander_amplitude

	var prev_yaw := rotation.y
	var yaw_diff := angle_difference(rotation.y, desired_yaw)
	rotation.y = lerp_angle(rotation.y, desired_yaw, clampf(delta * _turn_rate, 0.0, 1.0))
	_yaw_vel = angle_difference(prev_yaw, rotation.y) / maxf(delta, 0.001)
	_steer_angle = clampf(yaw_diff * 0.65, -0.46, 0.46)

	# Distinct speed modulation by unit type:
	var effective_speed := move_speed * _damage_speed_mult
	if kind == Kind.TRUCK and _drone != null and is_instance_valid(_drone):
		# Reconnaissance/supply Tigr accelerates when an armed drone approaches!
		var d_dist := global_position.distance_to(_drone.global_position)
		if d_dist < 85.0:
			effective_speed = move_speed * 1.38 * _damage_speed_mult
	elif kind != Kind.HELI and kind != Kind.SHAHED:
		# Slow down during sharp turns so tracked/wheeled vehicles turn tightly
		# and always move strictly forward along their nose (-Z).
		var turn_factor := clampf(1.0 - (absf(yaw_diff) / PI) * 0.65, 0.35, 1.0)
		effective_speed *= turn_factor

	# Aerial units bank smoothly into turns; ground units align to terrain slope in _update_height.
	if kind == Kind.HELI:
		rotation.z = lerpf(rotation.z, clampf(-yaw_diff * 0.35, -0.32, 0.32), clampf(delta * 3.0, 0.0, 1.0))
		rotation.x = lerpf(rotation.x, deg_to_rad(-6.0), clampf(delta * 2.5, 0.0, 1.0))
	elif kind == Kind.SHAHED:
		rotation.z = lerpf(rotation.z, clampf(-yaw_diff * 0.45, -0.40, 0.40), clampf(delta * 3.0, 0.0, 1.0))
		rotation.x = 0.0

	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() > 0.0001:
		forward = forward.normalized()
	else:
		forward = Vector3.FORWARD
	_step = effective_speed * delta

	var blocked := false
	if kind != Kind.HELI and kind != Kind.SHAHED:
		blocked = _is_path_blocked(forward, _step + 2.2)
		if blocked:
			_step = 0.0
			_stuck_time += delta
			# If halted by a wall or building, turn away or advance waypoint
			if _stuck_time > 1.2:
				_wp_index = (_wp_index + 1) % max(_waypoints.size(), 1)
				_stuck_time = 0.0
				if _last_obstacle_normal != Vector3.ZERO:
					var avoid_dir := forward.bounce(_last_obstacle_normal).normalized()
					avoid_dir.y = 0.0
					if avoid_dir.length_squared() > 0.01:
						rotation.y = atan2(-avoid_dir.x, -avoid_dir.z)
		else:
			_stuck_time = maxf(0.0, _stuck_time - delta * 0.5)

	if not blocked:
		global_position += forward * _step


func _is_path_blocked(forward: Vector3, dist: float) -> bool:
	# Hero Hall bounding box hard avoidance: vehicles must NEVER drive through or clip factory hall walls
	var map := _frontline_map()
	if map != "":
		var site: Dictionary = FrontlineTerrainScript.HALL_SITES.get(map, {})
		if not site.is_empty():
			var hc: Vector2 = site["center"]
			var hh: Vector2 = site["half"]
			var test_pos := global_position + forward * dist
			if absf(test_pos.x - hc.x) < hh.x + 3.0 and absf(test_pos.z - hc.y) < hh.y + 3.0:
				var to_center := Vector2(test_pos.x - hc.x, test_pos.z - hc.y)
				_last_obstacle_normal = Vector3(to_center.x, 0.0, to_center.y).normalized()
				return true

	var space := get_world_3d().direct_space_state
	if space == null:
		return false
	var excl: Array[RID] = [get_rid()]
	if _drone is CollisionObject3D:
		excl.append((_drone as CollisionObject3D).get_rid())
	for node in get_tree().get_nodes_in_group("vehicle"):
		if node is CollisionObject3D and node != self:
			excl.append((node as CollisionObject3D).get_rid())

	var center_y := global_position.y + 0.9
	var start_center := Vector3(global_position.x, center_y, global_position.z)
	var right_dir := Vector3(forward.z, 0.0, -forward.x).normalized()
	var half_w := 1.4 if kind == Kind.TANK else 1.1

	var origins := [
		start_center,
		start_center + right_dir * half_w,
		start_center - right_dir * half_w
	]

	for origin in origins:
		var query := PhysicsRayQueryParameters3D.create(origin, origin + forward * dist)
		query.collision_mask = 1
		query.exclude = excl
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			var n: Vector3 = hit.get("normal", Vector3.UP)
			# Wall, building, or steep structure (not gently sloping terrain)
			if n.y < 0.65:
				_last_obstacle_normal = n
				return true
	return false


func _update_halt(delta: float) -> void:
	if kind == Kind.HELI or kind == Kind.SHAHED or kind == Kind.TRUCK or halt_interval <= 0.0:
		_halt_left = 0.0
		return
	if _halt_left > 0.0:
		_halt_left -= delta
		return
	_halt_cd -= delta
	if _halt_cd <= 0.0:
		_halt_left = halt_duration * randf_range(0.75, 1.3)
		_halt_cd = halt_interval * randf_range(0.75, 1.25)


func _update_height(delta: float) -> void:
	var gy := _ground
	var n := _ground_normal
	if (Engine.get_physics_frames() + abs(get_instance_id())) % 3 == 0:
		var info := _sample_ground(global_position.x, global_position.z)
		gy = info["y"]
		n = info["normal"]
	if kind == Kind.HELI or kind == Kind.SHAHED:
		global_position.y = lerpf(global_position.y, gy + cruise_height,
				clampf(delta * 2.0, 0.0, 1.0))
	else:
		# Strictly clamp ground vehicles to the terrain surface so they never float.
		_ground = lerpf(_ground, gy, clampf(delta * 18.0, 0.0, 1.0))
		global_position.y = _ground
		_ground_normal = _ground_normal.lerp(n, clampf(delta * 8.0, 0.0, 1.0)).normalized()
		# Pitch and roll gently follow terrain slope + suspension dynamics while preserving yaw.
		var accel := (_engine_speed - _prev_speed) / maxf(delta, 0.004)
		_prev_speed = _engine_speed
		var dyn_pitch := clampf(-accel * 0.0035, -0.045, 0.045)
		var dyn_roll := clampf(_yaw_vel * _engine_speed * 0.004, -0.055, 0.055)
		_susp_pitch = move_toward(_susp_pitch, 0.0, delta * 0.14)
		_susp_roll = move_toward(_susp_roll, 0.0, delta * 0.14)
		var fwd := Vector3(-sin(rotation.y), 0.0, -cos(rotation.y))
		var right := Vector3(cos(rotation.y), 0.0, -sin(rotation.y))
		var target_pitch := clampf(asin(clampf(fwd.dot(_ground_normal), -0.35, 0.35)) + dyn_pitch + _susp_pitch, -0.28, 0.28)
		var target_roll := clampf(-asin(clampf(right.dot(_ground_normal), -0.35, 0.35)) + dyn_roll + _susp_roll, -0.22, 0.22)
		rotation.x = lerpf(rotation.x, target_pitch, clampf(delta * 8.0, 0.0, 1.0))
		rotation.z = lerpf(rotation.z, target_roll, clampf(delta * 8.0, 0.0, 1.0))


func _animate(delta: float) -> void:
	var spin := _step / maxf(_wheel_radius, 0.28)
	for wheel in _wheels:
		wheel.rotation.x += spin
	for fw in _front_wheels:
		fw.rotation.y = lerpf(fw.rotation.y, _steer_angle, clampf(delta * 8.5, 0.0, 1.0))
	if _step <= 0.0001:
		_steer_angle = move_toward(_steer_angle, 0.0, delta * 2.5)
		_yaw_vel = move_toward(_yaw_vel, 0.0, delta * 4.0)
	_step = 0.0
	if _dust != null:
		_dust.emitting = not is_destroyed and _engine_speed > 0.4
	for i in range(_track_mats.size()):
		var mat := _track_mats[i]
		if mat != null:
			var side_sign := -1.0 if i == 0 else 1.0
			var track_v := _engine_speed + side_sign * _yaw_vel * 1.35
			var off: Vector3 = mat.uv1_offset
			off.y -= track_v * delta * 0.9
			mat.uv1_offset = off
	if _barrel != null:
		_barrel_recoil = move_toward(_barrel_recoil, 0.0, delta * 3.8)
		var recoil_dist := 0.28 if kind == Kind.TANK else 0.12
		_barrel.position.z = _barrel_rest_z + _barrel_recoil * recoil_dist
	if _rotor != null:
		_rotor.rotation.y += delta * 30.0
	if _tail_rotor != null:
		_tail_rotor.rotation.x += delta * 45.0
	if _radar != null:
		_radar.rotation.y += delta * 1.4


func _aim_turret(delta: float) -> void:
	if _turret == null:
		return
	var before := _turret.rotation.y
	var aim_pos := Vector3.ZERO
	var has_aim := false
	if ai_vs_ai and ai_target != null and is_instance_valid(ai_target):
		aim_pos = ai_target.global_position + Vector3.UP * 0.9
		has_aim = true
	elif (track_drone or _engaging) and _drone != null and is_instance_valid(_drone):
		aim_pos = _drone.global_position
		has_aim = true
	if has_aim:
		var to := aim_pos - global_position
		var flat_to := Vector3(to.x, 0.0, to.z)
		if flat_to.length_squared() > 0.1:
			var world_yaw := atan2(-flat_to.x, -flat_to.z)
			_turret.rotation.y = lerp_angle(_turret.rotation.y,
					world_yaw - rotation.y, clampf(delta * 2.5, 0.0, 1.0))
			if _barrel != null:
				var desired_elev := clampf(atan2(to.y - _muzzle_height, flat_to.length()), -0.10, 0.55)
				_barrel.rotation.x = lerp_angle(_barrel.rotation.x, desired_elev, clampf(delta * 4.0, 0.0, 1.0))
		_turret_servo_audio(before, delta)
		return
	_turret.rotation.y = lerp_angle(_turret.rotation.y, 0.0,
			clampf(delta * 2.0, 0.0, 1.0))
	if _barrel != null:
		_barrel.rotation.x = lerp_angle(_barrel.rotation.x, 0.0, clampf(delta * 3.0, 0.0, 1.0))
	_turret_servo_audio(before, delta)


## A brief electric whine when a heavy turret traverses; silent while parked.
func _turret_servo_audio(before: float, delta: float) -> void:
	if kind != Kind.TANK and kind != Kind.BMP and kind != Kind.SAM:
		return
	_servo_cd -= delta
	if _servo_cd > 0.0:
		return
	if absf(_turret.rotation.y - before) < 0.004:
		return
	_servo_cd = 1.5
	CombatSfxScript.play_servo(get_parent(), _turret.global_position, -19.0)


func _apply_downwash(_delta: float) -> void:
	if not hostile or is_destroyed or _combat_disabled():
		return
	if _drone == null or not is_instance_valid(_drone):
		return
	var body := _drone as Drone
	if body == null:
		return
	var fc = _drone.get("flight_controller")
	if fc == null or not bool(fc.state_armed):
		return
	var to := _drone.global_position - global_position
	if to.y > 2.0 or to.y < -16.0:
		return
	var flat := Vector2(to.x, to.z).length()
	if flat > downwash_radius:
		return
	var falloff := 1.0 - flat / downwash_radius
	var outward := Vector3(to.x, 0.0, to.z)
	if outward.length_squared() > 0.01:
		outward = outward.normalized()
	var force := Vector3.DOWN * downwash_strength * falloff \
			+ outward * downwash_strength * falloff * 0.35
	body.apply_external_force(force)


# ------------------------------------------------------------------ combat
func _combat_engage(delta: float) -> void:
	_engaging = false
	if ai_vs_ai:
		_chaos_engage(delta)
		return
	if not hostile or is_destroyed or _combat_disabled():
		return
	if kind == Kind.SHAHED or kind == Kind.TRUCK:
		return
	_fire_cd -= delta
	if _drone == null or not is_instance_valid(_drone):
		return
	var fc = _drone.get("flight_controller")
	if fc == null or not bool(fc.state_armed):
		return
	var muzzle := _muzzle_world()
	var to := _drone.global_position - muzzle
	var dist := to.length()
	if dist > fire_range or dist < 3.0:
		return
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(muzzle, _drone.global_position)
	q.collision_mask = 1
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if not hit.is_empty() and hit.get("collider") != _drone:
		return
	_engaging = true
	if kind == Kind.HELI:
		var flat := Vector3(to.x, 0.0, to.z)
		if flat.length_squared() > 0.25:
			rotation.y = lerp_angle(rotation.y, atan2(-flat.x, -flat.z),
					clampf(delta * 2.4, 0.0, 1.0))
			rotation.x = lerpf(rotation.x, 0.0, clampf(delta * 3.0, 0.0, 1.0))
			rotation.z = lerpf(rotation.z, 0.0, clampf(delta * 3.0, 0.0, 1.0))
	if _fire_cd <= 0.0:
		_fire_cd = fire_interval + randf_range(-0.12, 0.20)
		var lead := Vector3.ZERO
		if _drone is RigidBody3D:
			lead = (_drone as RigidBody3D).linear_velocity * (dist / tracer_speed) * 0.8
		_fire_at(_drone.global_position + lead)


func _chaos_engage(delta: float) -> void:
	if is_destroyed or ai_target == null or not is_instance_valid(ai_target):
		return
	if bool(ai_target.get("is_destroyed")):
		ai_target = null
		return
	_fire_cd -= delta
	var muzzle := _muzzle_world()
	var to := ai_target.global_position + Vector3.UP * 0.7 - muzzle
	var dist := to.length()
	if dist > fire_range or dist < 3.0:
		return
	# Direct line of sight only; the chaos battlefield is open ground.
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(muzzle,
			ai_target.global_position + Vector3.UP * 0.7)
	q.collision_mask = 1
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if not hit.is_empty() and hit.get("collider") != ai_target:
		return
	_engaging = true
	if _fire_cd <= 0.0:
		_fire_cd = fire_interval + randf_range(-0.2, 0.3)
		_fire_at_unit(ai_target)


func _fire_at_unit(target: Node3D) -> void:
	var muzzle := _muzzle_world()
	var aim := target.global_position + Vector3.UP * 0.9
	var dir := (aim - muzzle).normalized()
	dir = (dir + Vector3(randf_range(-0.018, 0.018), randf_range(-0.018, 0.018),
			randf_range(-0.018, 0.018))).normalized()
	# Visual tracer (damage handled directly so AI-vs-AI works for every unit).
	var tracer = TracerScript.new()
	tracer.tracer_color = Color(1.0, 0.55, 0.25) if kind == Kind.TANK \
			else Color(1.0, 0.86, 0.4)
	tracer.tracer_width = 1.15 if kind == Kind.TANK else 0.8
	get_parent().add_child(tracer)
	tracer.setup(muzzle, dir, tracer_speed, 0.0, self)
	# Damage with the same falloff/aim model, applied directly.
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(muzzle, aim)
	q.collision_mask = 1
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		var collider = hit.get("collider")
		if collider == target and target.has_method("take_damage"):
			target.call("take_damage", tracer_damage, hit.get("position"))
	_barrel_recoil = 1.0
	_susp_pitch = clampf(_susp_pitch + (0.045 if kind == Kind.TANK else 0.018), -0.08, 0.08)
	_spawn_muzzle_flash(muzzle)
	match kind:
		Kind.TANK:
			CombatSfxScript.play_cannon(get_parent(), muzzle, -3.0)
		Kind.BMP, Kind.APC, Kind.SAM:
			CombatSfxScript.play_autocannon(get_parent(), muzzle, -6.0)
		Kind.HELI:
			CombatSfxScript.play_autocannon(get_parent(), muzzle, -9.0)
		_:
			CombatSfxScript.play_shot(get_parent(), muzzle, -8.0)


func _muzzle_world() -> Vector3:
	if _barrel != null and is_instance_valid(_barrel):
		var b_fwd := -_barrel.global_transform.basis.z
		var b_len := 2.8 if kind == Kind.TANK else 1.5
		return _barrel.global_position + b_fwd * b_len
	var forward := -global_transform.basis.z
	return global_position + Vector3.UP * _muzzle_height + forward * (_half_len * 0.6)


func _spawn_muzzle_flash(pos: Vector3) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var parent := get_parent()
	if parent != null and kind == Kind.TANK:
		ExplosionScript.spark_burst(parent, pos)


func _fire_at(target: Vector3) -> void:
	var muzzle := _muzzle_world()
	var dir := (target - muzzle).normalized()
	dir = (dir + Vector3(randf_range(-0.035, 0.035), randf_range(-0.035, 0.035),
			randf_range(-0.035, 0.035))).normalized()
	var tracer = TracerScript.new()
	tracer.tracer_color = Color(1.0, 0.55, 0.25) if kind == Kind.TANK else Color(1.0, 0.86, 0.4)
	tracer.tracer_width = 1.15 if kind == Kind.TANK else 0.85
	get_parent().add_child(tracer)
	tracer.setup(muzzle, dir, tracer_speed, tracer_damage, self)
	_barrel_recoil = 1.0
	_susp_pitch = clampf(_susp_pitch + (0.045 if kind == Kind.TANK else 0.018), -0.08, 0.08)
	_spawn_muzzle_flash(muzzle)
	# Each weapon class gets its own report: a 125 mm cannon is not a rifle.
	match kind:
		Kind.TANK:
			CombatSfxScript.play_cannon(get_parent(), muzzle, -3.0)
		Kind.BMP, Kind.APC, Kind.SAM:
			CombatSfxScript.play_autocannon(get_parent(), muzzle, -7.0)
		Kind.HELI:
			CombatSfxScript.play_autocannon(get_parent(), muzzle, -10.0)
		_:
			CombatSfxScript.play_shot(get_parent(), muzzle, -8.0)


func _combat_disabled() -> bool:
	for name in ["DRONE_AUTOTEST", "DRONE_AUTOTEST_COMBAT", "DRONE_FULLTEST", "DRONE_FLYTEST"]:
		if OS.has_environment(name):
			return true
	return false


func _frontline_map() -> String:
	var scene := get_tree().current_scene
	if scene == null:
		return ""
	return String(scene.get("frontline_map")) if scene.get("frontline_map") != null else ""


## On the procedural frontline maps the analytic terrain is authoritative.
## A downward physics ray can hit a warehouse roof or a bridge deck, which is
## exactly how vehicles ended up driving on rooftops.  Use the height field for
## ground units; only fall back to raycasts on the legacy GLB maps.
func _terrain_ground(x: float, z: float) -> Dictionary:
	var map := _frontline_map()
	if map.is_empty():
		return {}
	var y := FrontlineTerrainScript.height_at(map, x, z)
	var dx := FrontlineTerrainScript.height_at(map, x + 1.5, z) \
			- FrontlineTerrainScript.height_at(map, x - 1.5, z)
	var dz := FrontlineTerrainScript.height_at(map, x, z + 1.5) \
			- FrontlineTerrainScript.height_at(map, x, z - 1.5)
	var n := Vector3(-dx, 3.0, -dz).normalized()
	return {"y": y, "normal": n}


func _sample_ground(x: float, z: float) -> Dictionary:
	var terrain := _terrain_ground(x, z)
	if not terrain.is_empty():
		return terrain
	var space := get_world_3d().direct_space_state
	var excl: Array[RID] = [get_rid()]
	if _drone is CollisionObject3D:
		excl.append((_drone as CollisionObject3D).get_rid())
	for node in get_tree().get_nodes_in_group("combat_target"):
		if node is CollisionObject3D:
			excl.append((node as CollisionObject3D).get_rid())
	for node in get_tree().get_nodes_in_group("vehicle"):
		if node is CollisionObject3D:
			excl.append((node as CollisionObject3D).get_rid())
	var query := PhysicsRayQueryParameters3D.create(
			Vector3(x, 260.0, z), Vector3(x, -120.0, z))
	query.collision_mask = 1
	query.exclude = excl
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return {"y": _ground, "normal": Vector3.UP}
	var pos: Vector3 = hit["position"]
	var n: Vector3 = hit.get("normal", Vector3.UP)
	if n.y < 0.35:
		n = Vector3.UP
	return {"y": pos.y, "normal": n.normalized()}


func _ground_y(x: float, z: float) -> float:
	return float(_sample_ground(x, z)["y"])


# ------------------------------------------------------------------ damage
func take_damage(amount: float, hit_position: Vector3 = Vector3.ZERO) -> void:
	if is_destroyed:
		return
	var multiplier := _weak_spot_multiplier(hit_position)
	var applied := amount * multiplier
	health -= applied
	var hp_ratio := health / maxf(max_health, 1.0)
	if hp_ratio < 0.60 and hp_ratio > 0.0 and not _smoke_started:
		_smoke_started = true
		_damage_speed_mult = 0.72
		if get_parent() != null:
			ExplosionScript.smoke_column(get_parent(), global_position + Vector3.UP * 1.4, 14.0)
	if hp_ratio < 0.30 and hp_ratio > 0.0 and not _fire_started:
		_fire_started = true
		_damage_speed_mult = 0.45
		if get_parent() != null:
			ExplosionScript.fire_column(get_parent(), global_position + Vector3.UP * 1.1, 8.0)
	if hit_position != Vector3.ZERO and health > 0.0:
		ExplosionScript.spark_burst(get_parent(), hit_position)
		DestructionFxScript.hit(get_parent(), self, hit_position, _fx_kind(),
				clampf(applied / 70.0, 0.28, 1.0))
	if health <= 0.0:
		_destroy()


func _spawn_hit_fx(hit_position: Vector3, power: float = 1.0) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_hit_fx_ms < 110:
		return
	_last_hit_fx_ms = now
	var pos := hit_position if hit_position != Vector3.ZERO \
			else global_position + Vector3.UP * _muzzle_height * 0.6
	DestructionFxScript.hit(get_parent(), self, pos, _fx_kind(), power)


func _fx_kind() -> String:
	match kind:
		Kind.TANK:
			return "tank"
		Kind.BMP:
			return "bmp"
		Kind.APC:
			return "apc"
		Kind.TRUCK:
			return "truck"
		Kind.SAM:
			return "sam"
		Kind.HELI:
			return "heli"
		Kind.SHAHED:
			return "shahed"
	return "vehicle"


func _flash() -> void:
	if _flash_mesh.is_empty():
		return
	if _flash_material == null:
		_flash_material = StandardMaterial3D.new()
		_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_flash_material.albedo_color = Color(1.0, 0.7, 0.3, 0.6)
	_flash_token += 1
	var token := _flash_token
	for mesh in _flash_mesh:
		if is_instance_valid(mesh):
			mesh.material_overlay = _flash_material
	await get_tree().create_timer(0.08).timeout
	if not is_instance_valid(self):
		return
	if is_destroyed:
		# The killing hit landed inside the 80 ms flash window.  The old code
		# returned here and left the additive overlay on the wreck forever,
		# which is why burned-out vehicles glowed pink/yellow.
		_clear_flash_overlay()
		return
	if token != _flash_token:
		return
	for mesh in _flash_mesh:
		if is_instance_valid(mesh):
			mesh.material_overlay = null


func _clear_flash_overlay() -> void:
	_flash_token += 1
	for mesh in _all_meshes():
		if is_instance_valid(mesh):
			mesh.material_overlay = null


func _all_meshes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for node in find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi != null:
			out.append(mi)
	return out


func _destroy() -> void:
	is_destroyed = true
	if _dust != null:
		_dust.emitting = false
	remove_from_group("combat_target")
	collision_layer = 0
	collision_mask = 0
	_clear_flash_overlay()
	if _engine_player != null and is_instance_valid(_engine_player):
		_engine_player.stop()
	if _track_player != null and is_instance_valid(_track_player):
		_track_player.stop()
	var parent := get_parent()
	var aerial := kind == Kind.HELI or kind == Kind.SHAHED
	var gy := _ground_y(global_position.x, global_position.z)
	if parent != null:
		# Approved DestructionFx look.  The live Vehicle keeps its own char
		# timing and its physics crash fall, so the presentation layer only
		# supplies the blast, debris and fire.
		DestructionFxScript.destroy(parent, self, _fx_kind(), gy, {
			"char_unit": false,
			"move_unit": false,
			"burn": not aerial,
			"debris": true,
		})
		CombatSfxScript.play_boom(parent, global_position, -4.0)
		if not aerial:
			CombatSfxScript.start_burning(parent, global_position, 28.0)

	if aerial:
		_start_crash_fall(gy)
	else:
		_char_hull()
		_settle_wreck()

	destroyed.emit(points + _bonus_points)


## Burn the hull to a dark, rough wreck and remove weak-spot markers.
func _char_hull() -> void:
	var scorch_mat := StandardMaterial3D.new()
	scorch_mat.albedo_color = Color(0.12, 0.11, 0.10)
	scorch_mat.roughness = 0.98
	scorch_mat.metallic = 0.08
	# Char every mesh, including the enemy markings and weak-spot decals that
	# are not part of _flash_mesh.  Otherwise a bright yellow marking kept
	# glowing on the burned-out hull.
	for mesh in _all_meshes():
		if is_instance_valid(mesh):
			mesh.material_overlay = null
			mesh.material_override = scorch_mat
	for marker in _weak_markers:
		if is_instance_valid(marker):
			marker.visible = false


## Ground vehicles collapse onto their suspension and settle into the terrain.
func _settle_wreck() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	# Catastrophic hull collapse: chassis sinks down onto broken suspension / blown tracks
	tween.tween_property(self, "position:y", position.y - 0.38, 0.6)
	tween.tween_property(self, "rotation:x", deg_to_rad(12.0), 0.6)
	tween.tween_property(self, "rotation:z", deg_to_rad(-8.5), 0.6)
	tween.tween_property(self, "scale", Vector3(1.02, 0.82, 1.02), 0.6)

	# If vehicle has a turret, dislodge and blow it open
	if _turret != null and is_instance_valid(_turret):
		tween.tween_property(_turret, "rotation:x", deg_to_rad(16.0), 0.5)
		tween.tween_property(_turret, "rotation:y", _turret.rotation.y + deg_to_rad(28.0), 0.5)
		tween.tween_property(_turret, "position:y", _turret.position.y + 0.30, 0.5)


func _start_crash_fall(ground_y: float = 1.0e20) -> void:
	_crash_falling = true
	var fwd := -global_transform.basis.z
	var carry := fwd * (_engine_speed * 0.35)
	_crash_vel = Vector3(carry.x, -3.0, carry.z)
	# Sample the ground once, before the new debris pieces exist.  A per-frame
	# raycast would hit our own falling debris and "land" the wreck in mid-air.
	_crash_ground_y = ground_y if ground_y < 1.0e19 \
			else _ground_y(global_position.x, global_position.z)
	_crash_spin = randf_range(-2.4, 2.4)
	_crash_roll = randf_range(-1.4, 1.4)
	_crash_pitch = deg_to_rad(randf_range(24.0, 55.0))
	_crash_trail_cd = 0.0
	# Approved fire/smoke trail follows the falling wreck.
	DestructionFxScript.trail(self)
	if _rotor != null:
		_rotor.rotation.y += randf_range(0.0, TAU)


func _update_crash_fall(delta: float) -> void:
	if not _crash_falling:
		return
	if kind == Kind.HELI:
		if _rotor != null:
			_rotor.rotation.y += delta * 14.0
		if _tail_rotor != null:
			_tail_rotor.rotation.x += delta * 20.0
	_crash_vel.y -= 21.0 * delta
	_crash_vel.x *= 1.0 - delta * 0.35
	_crash_vel.z *= 1.0 - delta * 0.35
	global_position += _crash_vel * delta
	rotation.y += _crash_spin * delta
	rotation.z += _crash_roll * delta
	rotation.x = lerp_angle(rotation.x, _crash_pitch, clampf(delta * 1.4, 0.0, 1.0))
	_crash_trail_cd -= delta
	if _crash_trail_cd <= 0.0:
		_crash_trail_cd = 0.12
		var parent := get_parent()
		if parent != null:
			ExplosionScript.fire_column(parent, global_position, 2.4)
			ExplosionScript.smoke_column(parent, global_position + Vector3.UP * 0.6, 6.0)
	var gy := _crash_ground_y
	if global_position.y <= gy + 0.55:
		_crash_impact(gy)


func _crash_impact(gy: float) -> void:
	_crash_falling = false
	_crash_vel = Vector3.ZERO
	global_position.y = gy + 0.18
	rotation.x = deg_to_rad(14.0)
	rotation.z += randf_range(-0.28, 0.28)
	scale = Vector3(1.05, 0.72, 1.05)
	var parent := get_parent()
	DestructionFxScript.stop_trail(self)
	if parent != null:
		DestructionFxScript.impact(parent, self, _fx_kind(), gy)
		CombatSfxScript.play_boom(parent, global_position, 1.0)
		CombatSfxScript.start_burning(parent, global_position, 30.0)


func _spawn_debris(parent: Node) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var debris_mat := StandardMaterial3D.new()
	debris_mat.albedo_color = Color(0.15, 0.13, 0.12)
	debris_mat.roughness = 0.95
	var count := 5
	for i in range(count):
		var piece := RigidBody3D.new()
		piece.mass = 4.0
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var s := Vector3(randf_range(0.2, 0.5), randf_range(0.15, 0.3), randf_range(0.3, 0.7))
		bm.size = s
		mi.mesh = bm
		mi.material_override = debris_mat
		piece.add_child(mi)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = s
		cs.shape = bs
		piece.add_child(cs)
		parent.add_child(piece)
		piece.global_position = global_position + Vector3(randf_range(-1.2, 1.2), 1.2, randf_range(-1.2, 1.2))
		var impulse := Vector3(randf_range(-6.0, 6.0), randf_range(6.0, 14.0), randf_range(-6.0, 6.0))
		piece.apply_central_impulse(impulse * piece.mass)
		piece.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
		var timer := get_tree().create_timer(6.0)
		timer.timeout.connect(func() -> void:
			if is_instance_valid(piece):
				piece.queue_free())
