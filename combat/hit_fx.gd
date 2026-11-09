## Authored Blender hit-reaction VFX, one GLB per target class.
##
## Every scene contains a single "Hit" animation (flash, debris, sparks,
## dust/smoke and class-specific fragments).  A small active-effect budget keeps
## a rocket barrage from spawning dozens of multi-draw-call scenes at once.
class_name HitFx
extends RefCounted

const INFANTRY_SCENE := preload("res://Assets/combat/hit_infantry.glb")
const TANK_SCENE := preload("res://Assets/combat/hit_tank.glb")
const BMP_SCENE := preload("res://Assets/combat/hit_bmp.glb")
const APC_SCENE := preload("res://Assets/combat/hit_apc.glb")
const TRUCK_SCENE := preload("res://Assets/combat/hit_truck.glb")
const SAM_SCENE := preload("res://Assets/combat/hit_sam.glb")
const HELI_SCENE := preload("res://Assets/combat/hit_heli.glb")
const SHAHED_SCENE := preload("res://Assets/combat/hit_shahed.glb")
const VEHICLE_SCENE := preload("res://Assets/combat/hit_vehicle.glb")

const MAX_ACTIVE := 16
static var _active := 0
static var _spark_texture: Texture2D = null
static var _smoke_texture: Texture2D = null
static var _dust_texture: Texture2D = null


static func scene_for(kind: String) -> PackedScene:
	match kind:
		"infantry":
			return INFANTRY_SCENE
		"tank":
			return TANK_SCENE
		"bmp":
			return BMP_SCENE
		"apc":
			return APC_SCENE
		"truck":
			return TRUCK_SCENE
		"sam":
			return SAM_SCENE
		"heli":
			return HELI_SCENE
		"shahed":
			return SHAHED_SCENE
		_:
			return VEHICLE_SCENE


static func spawn(parent: Node, world_position: Vector3, kind: String = "vehicle",
		scale_mult: float = 1.0, power: float = 1.0) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	if DisplayServer.get_name() == "headless":
		return
	if _active >= MAX_ACTIVE:
		return
	var packed := scene_for(kind)
	if packed == null:
		return
	var fx := packed.instantiate() as Node3D
	if fx == null:
		return
	_active += 1
	parent.add_child(fx)
	fx.global_position = world_position
	var base_scale := 1.0
	match kind:
		"tank":
			base_scale = 2.0
		"bmp":
			base_scale = 1.8
		"apc":
			base_scale = 1.8
		"truck":
			base_scale = 1.6
		"sam":
			base_scale = 1.8
		"heli":
			base_scale = 2.2
		"shahed":
			base_scale = 1.5
		"infantry":
			base_scale = 1.3
	fx.scale = Vector3.ONE * scale_mult * base_scale * clampf(power, 0.25, 1.0)
	_spawn_particles(fx, kind, clampf(power, 0.25, 1.0))
	fx.tree_exited.connect(func() -> void:
		_active = maxi(_active - 1, 0))
	var players := fx.find_children("*", "AnimationPlayer", true, false)
	var ap: AnimationPlayer = null
	if not players.is_empty():
		ap = players[0] as AnimationPlayer
	if ap != null:
		var names := ap.get_animation_list()
		if names.has("Hit"):
			ap.play("Hit")
		elif not names.is_empty():
			ap.play(names[0])
		ap.animation_finished.connect(func(_name: String) -> void:
			if is_instance_valid(fx):
				fx.queue_free())
	else:
		var t := parent.get_tree().create_timer(1.2)
		t.timeout.connect(func() -> void:
			if is_instance_valid(fx):
				fx.queue_free())


## Engine-side particle layer around the authored GLB: soft smoke, dust and
## additive sparks.  The Blender scene supplies the big readable fragments and
## flash; these particles give the hit the fine, high-frame-rate detail that a
## small GLB cannot carry efficiently.
static func _spawn_particles(fx: Node3D, kind: String, power: float = 1.0) -> void:
	if _spark_texture == null:
		_spark_texture = _radial_texture([
			Color(1.0, 1.0, 0.95, 1.0),
			Color(1.0, 0.62, 0.16, 0.9),
			Color(1.0, 0.25, 0.02, 0.0),
		])
		_smoke_texture = _radial_texture([
			Color(1.0, 1.0, 1.0, 0.75),
			Color(0.55, 0.55, 0.55, 0.30),
			Color(0.2, 0.2, 0.2, 0.0),
		])
		_dust_texture = _radial_texture([
			Color(0.82, 0.69, 0.48, 0.65),
			Color(0.48, 0.38, 0.25, 0.25),
			Color(0.2, 0.15, 0.10, 0.0),
		])
	var is_inf := kind == "infantry"
	var spark_amount := int((10 if is_inf else 18) * (0.45 + 0.55 * power))
	var smoke_amount := int((7 if is_inf else 10) * (0.45 + 0.55 * power))
	var dust_amount := int((8 if is_inf else 14) * (0.45 + 0.55 * power))
	_particle_burst(fx, spark_amount, 0.55, Color(1.0, 0.55, 0.10, 1.0),
			_spark_texture, 3.5, 9.0, Vector3(0, -7.0, 0),
			0.05, 0.12, true)
	_particle_burst(fx, smoke_amount, 1.5, Color(0.32, 0.32, 0.31, 0.55),
			_smoke_texture, 0.8, 2.4, Vector3(0, 1.2, 0),
			0.5, 1.1, false)
	_particle_burst(fx, dust_amount, 1.0, Color(0.55, 0.43, 0.28, 0.55),
			_dust_texture, 1.0, 3.2, Vector3(0, -1.6, 0),
			0.35, 0.8, false)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.42, 0.08)
	light.light_energy = 2.4 * power
	light.omni_range = (9.0 if not is_inf else 4.0) * (0.6 + 0.4 * power)
	light.shadow_enabled = false
	fx.add_child(light)
	var tw := fx.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.30)
	tw.tween_callback(light.queue_free)


static func _radial_texture(colors: Array) -> GradientTexture2D:
	var grad := Gradient.new()
	var offsets := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in range(colors.size()):
		offsets.append(float(i) / float(maxi(colors.size() - 1, 1)))
		cols.append(colors[i] as Color)
	grad.offsets = offsets
	grad.colors = cols
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	return tex


static func _particle_burst(parent: Node3D, amount: int, lifetime: float,
		color: Color, tex: Texture2D, speed_min: float, speed_max: float,
		gravity: Vector3, size_min: float, size_max: float,
		additive: bool) -> void:
	var particles := GPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = lifetime
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.randomness = 0.45
	particles.fixed_fps = 30
	particles.local_coords = false
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.30
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 180.0
	process.initial_velocity_min = speed_min
	process.initial_velocity_max = speed_max
	process.gravity = gravity
	process.scale_min = size_min
	process.scale_max = size_max
	process.color = color
	process.damping_min = 1.0
	process.damping_max = 3.5
	process.angle_min = 0.0
	process.angle_max = TAU
	process.angular_velocity_min = -180.0
	process.angular_velocity_max = 180.0
	particles.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = tex
	mat.albedo_color = Color.WHITE
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	if additive:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	quad.material = mat
	particles.draw_pass_1 = quad
	particles.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))
	parent.add_child(particles)
	particles.emitting = true
