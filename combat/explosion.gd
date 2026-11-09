## Reusable explosion: procedural VFX, radius damage, chain reactions and a
## short knockback impulse for the player drone. No external assets required.
class_name Explosion
extends Node3D

const CombatSfxScript = preload("res://combat/sfx.gd")

const BINBUN_GROUND := "res://Assets/BinbunVFX_Vol2/ExplosionFX/effects/ground/vfx_ground_explosion_01.tscn"
const BINBUN_AIR := "res://Assets/BinbunVFX_Vol2/ExplosionFX/effects/air/vfx_air_explosion_01.tscn"

var radius := 8.0
var damage := 450.0
var _damage_pending := true
var _age := 0.0


static func spawn(parent: Node, world_position: Vector3, blast_radius: float = 8.0,
		blast_damage: float = 450.0) -> Explosion:
	var explosion := Explosion.new()
	explosion.radius = blast_radius
	explosion.damage = blast_damage
	parent.add_child(explosion)
	explosion.global_position = world_position
	return explosion


func _ready() -> void:
	call_deferred("_build_vfx")


func _physics_process(delta: float) -> void:
	_age += delta
	if _damage_pending:
		_damage_pending = false
		_apply_damage()
	if _age > 4.0:
		queue_free()


func _apply_damage() -> void:
	if damage <= 0.0:
		return
	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, global_position)
	query.collision_mask = 1
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var seen: Dictionary = {}
	for hit in space.intersect_shape(query, 64):
		var body = hit.get("collider")
		if body == null or not is_instance_valid(body):
			continue
		if not body.is_in_group("combat_target") or not body.has_method("take_damage"):
			continue
		var id: int = body.get_instance_id()
		if seen.has(id):
			continue
		seen[id] = true
		var center: Vector3 = (body as Node3D).global_position + Vector3.UP * 0.8
		var distance := global_position.distance_to(center)
		var falloff := clampf(1.0 - distance / maxf(radius, 0.01), 0.15, 1.0)
		body.take_damage(damage * falloff, global_position)
	_push_drone()


func _push_drone() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var drone := scene.get_node_or_null("Drone")
	if not (drone is RigidBody3D):
		return
	var body := drone as RigidBody3D
	var distance := body.global_position.distance_to(global_position)
	var reach := radius * 1.6
	if distance > reach:
		return
	var strength := 5.0 * clampf(1.0 - distance / reach, 0.0, 1.0) * body.mass
	var dir := (body.global_position - global_position).normalized()
	if dir == Vector3.ZERO:
		dir = Vector3.UP
	body.apply_central_impulse((dir + Vector3.UP * 0.35).normalized() * strength)


func _build_vfx() -> void:
	if not is_inside_tree():
		return
	if DisplayServer.get_name() == "headless":
		return
	CombatSfxScript.play_boom(get_parent(), global_position)
	if damage > 0.0:
		# A delayed, quieter tail makes the blast read as a real pressure wave
		# rather than a single dry sample.  Ambient explosions skip it to keep
		# the horizon mix clean.
		var tail_parent := get_parent()
		var tail_pos := global_position
		var tail := get_tree().create_timer(0.32)
		tail.timeout.connect(func() -> void:
			if is_instance_valid(tail_parent):
				CombatSfxScript.play_boom(tail_parent, tail_pos, -13.0))
	vfx_burst(get_parent(), global_position, clampf(radius / 8.0, 0.9, 2.2), global_position.y > 6.0)
	_spawn_fire()
	_spawn_smoke()
	_spawn_flash()
	_spawn_light()
	_spawn_crater()


static var _crater_texture: GradientTexture2D = null


## Ground bursts leave a scorch decal, a dark crater disc and a ring of dirt
## clods.  This is a visual crater (the terrain mesh is not carved) but from an
## FPV camera it reads exactly like a fresh impact hole.
func _spawn_crater() -> void:
	if damage <= 0.0:
		return  # ambient battle noise: no decal spam on the horizon
	var cam := get_viewport().get_camera_3d()
	if cam != null and cam.global_position.distance_to(global_position) > 180.0:
		return
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	var query := PhysicsRayQueryParameters3D.create(
			global_position + Vector3.UP * 40.0,
			global_position + Vector3.DOWN * 40.0)
	query.collision_mask = 1
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return
	var ground: Vector3 = hit["position"]
	if absf(ground.y - global_position.y) > 5.0:
		return  # airborne burst, no ground crater
	var crater_r := clampf(radius * 0.95, 3.0, 24.0)
	if _crater_texture == null:
		# Built-in radial gradient instead of a per-pixel image loop: the old
		# 16k set_pixel loop caused a one-second hitch on the first impact.
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.55, 0.88, 1.0])
		grad.colors = PackedColorArray([
			Color(0.020, 0.017, 0.013, 0.96),
			Color(0.055, 0.043, 0.031, 0.80),
			Color(0.120, 0.095, 0.065, 0.35),
			Color(0.20, 0.16, 0.11, 0.0),
		])
		_crater_texture = GradientTexture2D.new()
		_crater_texture.gradient = grad
		_crater_texture.width = 128
		_crater_texture.height = 128
		_crater_texture.fill = GradientTexture2D.FILL_RADIAL
		_crater_texture.fill_from = Vector2(0.5, 0.5)
		_crater_texture.fill_to = Vector2(1.0, 0.5)
	var decal := Decal.new()
	decal.texture_albedo = _crater_texture
	decal.size = Vector3(crater_r * 2.1, 7.0, crater_r * 2.1)
	decal.cull_mask = 1
	decal.albedo_mix = 0.9
	decal.upper_fade = 0.45
	decal.lower_fade = 0.35
	decal.position = Vector3(ground.x, ground.y + 3.2, ground.z)
	get_parent().add_child(decal)
	# The old hard cylinder "crater bowl" read as a black disc from a low FPV
	# angle.  Keep only the soft scorch decal and the dirt clods; they blend
	# into the terrain instead of floating on it.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.09, 0.075, 0.055)
	mat.roughness = 1.0
	# Dirt clods thrown out of the rim.
	for i in range(7):
		var a := TAU * float(i) / 7.0 + randf() * 0.4
		var clod := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(randf_range(0.12, 0.42), randf_range(0.08, 0.25),
				randf_range(0.12, 0.42))
		clod.mesh = box
		clod.material_override = mat
		clod.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		get_parent().add_child(clod)
		clod.global_position = Vector3(
				ground.x + cos(a) * crater_r * randf_range(0.45, 0.85),
				ground.y + randf_range(0.02, 0.10),
				ground.z + sin(a) * crater_r * randf_range(0.45, 0.85))
		clod.rotation.y = randf() * TAU
	_free_after(decal, 75.0)


## Instantiates the authored "BinbunVFX" explosion at a world position. The scene
## autoplays and removes itself.
static func vfx_burst(parent: Node, world_position: Vector3, size: float = 1.0,
		airborne: bool = false) -> void:
	if DisplayServer.get_name() == "headless" or parent == null:
		return
	var path := BINBUN_AIR if airborne else BINBUN_GROUND
	if not ResourceLoader.exists(path):
		return
	var packed := load(path) as PackedScene
	if packed == null:
		return
	var fx := packed.instantiate() as Node3D
	if fx == null:
		return
	# The authored effect autoplays, but its default `one_shot` is false, which
	# makes it restart forever. Force a single blast and let it self-clean.
	fx.set("one_shot", true)
	parent.add_child(fx)
	fx.global_position = world_position
	fx.scale = Vector3.ONE * clampf(size, 0.5, 2.5)
	if fx.has_signal("finished"):
		fx.connect("finished", fx.queue_free)
	_free_after(fx, 6.0)


func _spawn_fire() -> void:
	var fire := GPUParticles3D.new()
	fire.amount = 72
	fire.lifetime = 0.9
	fire.one_shot = true
	fire.explosiveness = 0.95
	fire.emitting = true
	fire.visibility_aabb = AABB(Vector3(-35, -35, -35), Vector3(70, 70, 70))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.4
	process.direction = Vector3.UP
	process.spread = 180.0
	process.initial_velocity_min = 4.0
	process.initial_velocity_max = 15.0
	process.gravity = Vector3(0.0, -7.0, 0.0)
	process.damping_min = 2.0
	process.damping_max = 4.0
	process.scale_min = 0.4
	process.scale_max = 1.35
	process.angle_min = -180.0
	process.angle_max = 180.0
	process.color_ramp = _ramp(Color(1.0, 0.92, 0.55, 1.0), Color(1.0, 0.35, 0.05, 0.85),
			Color(0.35, 0.08, 0.02, 0.0))
	fire.process_material = process
	fire.draw_pass_1 = _particle_quad(0.95, Color(1.0, 0.55, 0.15), true)
	add_child(fire)


func _spawn_smoke() -> void:
	var smoke := GPUParticles3D.new()
	smoke.amount = 46
	smoke.lifetime = 3.2
	smoke.one_shot = true
	smoke.explosiveness = 0.8
	smoke.emitting = true
	smoke.visibility_aabb = AABB(Vector3(-45, -20, -45), Vector3(90, 70, 90))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.8
	process.direction = Vector3.UP
	process.spread = 80.0
	process.initial_velocity_min = 1.5
	process.initial_velocity_max = 5.0
	process.gravity = Vector3(0.0, 0.8, 0.0)
	process.damping_min = 1.0
	process.damping_max = 2.0
	process.scale_min = 1.2
	process.scale_max = 3.6
	process.angle_min = -180.0
	process.angle_max = 180.0
	process.color_ramp = _ramp(Color(0.30, 0.28, 0.25, 0.65), Color(0.12, 0.11, 0.10, 0.35),
			Color(0.05, 0.05, 0.05, 0.0))
	smoke.process_material = process
	smoke.draw_pass_1 = _particle_quad(1.7, Color(0.5, 0.5, 0.5), false)
	add_child(smoke)


func _spawn_flash() -> void:
	var flash := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	flash.mesh = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.albedo_texture = _radial_texture()
	material.albedo_color = Color(1.0, 0.95, 0.78, 1.0)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.5, 0.12)
	material.emission_energy_multiplier = 3.0
	flash.material_override = material
	flash.scale = Vector3.ONE * 0.7
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flash)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ONE * radius * 0.8, 0.28) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color", Color(1.0, 0.35, 0.08, 0.0), 0.38)
	tween.chain().tween_callback(flash.queue_free)


func _spawn_light() -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 10.0
	light.omni_range = radius * 2.6
	light.shadow_enabled = false
	add_child(light)
	var tween := create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.45)


## Persistent smoke column for a destroyed target / burning wreck.
static func smoke_column(parent: Node, world_position: Vector3, duration: float = 26.0) -> void:
	if DisplayServer.get_name() == "headless" or parent == null:
		return
	var smoke := GPUParticles3D.new()
	smoke.amount = 20
	smoke.lifetime = 3.8
	smoke.emitting = true
	smoke.visibility_aabb = AABB(Vector3(-15, -5, -15), Vector3(30, 60, 30))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.5
	process.direction = Vector3.UP
	process.spread = 10.0
	process.initial_velocity_min = 1.0
	process.initial_velocity_max = 2.8
	process.gravity = Vector3(0.0, 0.6, 0.0)
	process.scale_min = 1.4
	process.scale_max = 3.2
	process.angle_min = -180.0
	process.angle_max = 180.0
	process.color_ramp = _ramp(Color(0.10, 0.10, 0.10, 0.55), Color(0.22, 0.21, 0.20, 0.35),
			Color(0.35, 0.34, 0.32, 0.0))
	smoke.process_material = process
	smoke.draw_pass_1 = _particle_quad(1.8, Color(0.5, 0.5, 0.5), false)
	parent.add_child(smoke)
	smoke.global_position = world_position
	_free_after(smoke, duration)


## Short flames on a wreck, removed after `duration` seconds.
static func fire_column(parent: Node, world_position: Vector3, duration: float = 7.0) -> void:
	if DisplayServer.get_name() == "headless" or parent == null:
		return
	var fire := GPUParticles3D.new()
	fire.amount = 14
	fire.lifetime = 1.0
	fire.emitting = true
	fire.visibility_aabb = AABB(Vector3(-10, -5, -10), Vector3(20, 20, 20))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.7
	process.direction = Vector3.UP
	process.spread = 25.0
	process.initial_velocity_min = 1.2
	process.initial_velocity_max = 2.6
	process.gravity = Vector3(0.0, 0.4, 0.0)
	process.scale_min = 0.7
	process.scale_max = 1.7
	process.angle_min = -180.0
	process.angle_max = 180.0
	process.color_ramp = _ramp(Color(1.0, 0.9, 0.5, 0.9), Color(1.0, 0.4, 0.05, 0.6),
			Color(0.3, 0.05, 0.0, 0.0))
	fire.process_material = process
	fire.draw_pass_1 = _particle_quad(0.9, Color(1.0, 0.5, 0.12), true)
	parent.add_child(fire)
	fire.global_position = world_position
	_free_after(fire, duration)


## Small hit spark burst (used when a target is damaged but survives).
static func spark_burst(parent: Node, world_position: Vector3) -> void:
	if DisplayServer.get_name() == "headless" or parent == null:
		return
	var sparks := GPUParticles3D.new()
	sparks.amount = 12
	sparks.lifetime = 0.45
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.emitting = true
	sparks.visibility_aabb = AABB(Vector3(-6, -6, -6), Vector3(12, 12, 12))
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 100.0
	process.initial_velocity_min = 2.0
	process.initial_velocity_max = 6.0
	process.gravity = Vector3(0.0, -9.0, 0.0)
	process.scale_min = 0.3
	process.scale_max = 0.7
	process.color_ramp = _ramp(Color(1.0, 0.95, 0.6, 1.0), Color(1.0, 0.5, 0.1, 0.8),
			Color(0.4, 0.1, 0.0, 0.0))
	sparks.process_material = process
	sparks.draw_pass_1 = _particle_quad(0.35, Color(1.0, 0.7, 0.2), true)
	parent.add_child(sparks)
	sparks.global_position = world_position
	_free_after(sparks, 1.2)


static func _free_after(node: Node, seconds: float) -> void:
	var timer := Timer.new()
	timer.wait_time = maxf(seconds, 0.1)
	timer.one_shot = true
	timer.autostart = true
	node.add_child(timer)
	timer.timeout.connect(node.queue_free)


static func _soft_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.4, 0.75, 1.0])
	gradient.colors = PackedColorArray([
		Color(1, 1, 1, 1),
		Color(1, 1, 1, 0.8),
		Color(1, 1, 1, 0.3),
		Color(1, 1, 1, 0.0),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 128
	texture.height = 128
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture


static func _radial_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.35, 0.72, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 0.98, 0.86, 1.0),
		Color(1.0, 0.72, 0.26, 0.88),
		Color(0.95, 0.28, 0.04, 0.32),
		Color(0.3, 0.05, 0.0, 0.0),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 128
	texture.height = 128
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture


static func _particle_quad(size: float, color: Color, additive: bool) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = _soft_texture()
	material.albedo_color = color
	if additive:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 2.0
	quad.material = material
	return quad


static func _ramp(a: Color, b: Color, c: Color) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	gradient.colors = PackedColorArray([a, b, c])
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture
