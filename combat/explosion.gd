## Reusable explosion: procedural VFX, radius damage, chain reactions and a
## short knockback impulse for the player drone. No external assets required.
class_name Explosion
extends Node3D

const CombatSfxScript = preload("res://combat/sfx.gd")

const BINBUN_GROUND := "res://Assets/BinbunVFX_Vol2/ExplosionFX/effects/ground/vfx_ground_explosion_01.tscn"
const BINBUN_AIR := "res://Assets/BinbunVFX_Vol2/ExplosionFX/effects/air/vfx_air_explosion_01.tscn"

## Fragmentation reaches further through an airframe than through soil or
## sandbags.  Without this, a bomb that detonated a few metres from a flying
## helicopter or Shahed dealt no damage at all, so the campaign air targets
## could only be hit by a perfect physical contact.
const AIR_TARGET_BLAST_SCALE := 1.45
const AIR_TARGET_BLAST_BONUS := 2.0

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
	for hit in space.intersect_shape(query, 256):
		var body = hit.get("collider")
		if body == null or not is_instance_valid(body):
			continue
		if not body.is_in_group("combat_target") or not body.has_method("take_damage"):
			continue
		var id: int = body.get_instance_id()
		if seen.has(id):
			continue
		var owner_ref: Variant = body.get("landmark")
		if owner_ref is Object and is_instance_valid(owner_ref) and seen.has(owner_ref.get_instance_id()):
			continue
		seen[id] = true
		if owner_ref is Object and is_instance_valid(owner_ref):
			seen[owner_ref.get_instance_id()] = true
		var center: Vector3 = (body as Node3D).global_position + Vector3.UP * 0.8
		var distance := global_position.distance_to(center)
		var falloff := clampf(1.0 - distance / maxf(radius, 0.01), 0.15, 1.0)
		body.take_damage(damage * falloff, global_position)
	# Direct distance sweep guarantees infantry/targets near dense geometry
	# still receive splash damage even if physics shape overlap hits saturate.
	var tree := get_tree()
	if tree != null:
		for target in tree.get_nodes_in_group("combat_target"):
			if target == null or not is_instance_valid(target) or not (target is Node3D):
				continue
			if not target.has_method("take_damage"):
				continue
			var id: int = target.get_instance_id()
			if seen.has(id):
				continue
			var owner_ref: Variant = target.get("landmark")
			if owner_ref is Object and is_instance_valid(owner_ref) and seen.has(owner_ref.get_instance_id()):
				continue
			var effective_radius := radius
			if target.is_in_group("air_target"):
				effective_radius = radius * AIR_TARGET_BLAST_SCALE + AIR_TARGET_BLAST_BONUS
			var max_dist := effective_radius + 1.0
			var center: Vector3 = (target as Node3D).global_position + Vector3.UP * 0.8
			var distance := global_position.distance_to(center)
			if distance > max_dist:
				continue
			seen[id] = true
			if owner_ref is Object and is_instance_valid(owner_ref):
				seen[owner_ref.get_instance_id()] = true
			var falloff := clampf(1.0 - distance / maxf(effective_radius, 0.01),
					0.25 if target.is_in_group("air_target") else 0.15, 1.0)
			target.take_damage(damage * falloff, global_position)
		var alert_dist := maxf(radius * 2.4, 24.0)
		for soldier in tree.get_nodes_in_group("enemy_infantry"):
			if soldier == null or not is_instance_valid(soldier) or not (soldier is Node3D):
				continue
			if (soldier as Node3D).global_position.distance_to(global_position) <= alert_dist:
				if soldier.has_method("notify_blast"):
					soldier.call("notify_blast", global_position, alert_dist)
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


func _route_last_sfx_bus(parent: Node, bus_name: StringName) -> void:
	if parent == null or not is_instance_valid(parent) or parent.get_child_count() <= 0:
		return
	var p := parent.get_child(parent.get_child_count() - 1)
	if p is AudioStreamPlayer3D or p is AudioStreamPlayer:
		p.set("bus", bus_name)


func _build_vfx() -> void:
	if not is_inside_tree():
		return
	if DisplayServer.get_name() == "headless":
		return
	var p := get_parent()
	CombatSfxScript.play_boom(p, global_position)
	_route_last_sfx_bus(p, &"Combat")
	if damage > 0.0:
		# A delayed, quieter tail makes the blast read as a real pressure wave
		# rather than a single dry sample.  Ambient explosions skip it to keep
		# the horizon mix clean.
		var tail_parent_ref: WeakRef = weakref(p)
		var tail_pos := global_position
		var tail := Timer.new()
		tail.one_shot = true
		tail.wait_time = 0.32
		p.add_child(tail)
		tail.timeout.connect(func() -> void:
			var tp := tail_parent_ref.get_ref() as Node
			if tp != null and is_instance_valid(tp):
				CombatSfxScript.play_boom(tp, tail_pos, -13.0)
				_route_last_sfx_bus(tp, &"Combat")
			tail.queue_free())
		tail.start()
	var true_ground_y := _resolve_ground_y(global_position)
	var is_aerial := (global_position.y - true_ground_y) > 6.0
	var dfx = load("res://combat/destruction_fx.gd")
	var blast_scale := clampf(radius / 8.0, 0.85, 1.75)
	if dfx != null and damage > 0.0:
		dfx.spawn_multiphase_explosion(p, global_position, blast_scale,
				true_ground_y, is_aerial)
	else:
		vfx_burst(p, global_position, clampf(radius / 8.0, 0.9, 2.2), is_aerial)
		_spawn_fire()
		_spawn_smoke()
	_spawn_flash()
	_spawn_light()
	_spawn_crater()


func _resolve_ground_y(pos: Vector3) -> float:
	var w3d := get_world_3d()
	if w3d != null and w3d.direct_space_state != null:
		var q := PhysicsRayQueryParameters3D.create(
				pos + Vector3.UP * 1.0,
				pos + Vector3.DOWN * 80.0)
		q.collision_mask = 1
		q.collide_with_bodies = true
		q.collide_with_areas = false
		var hit := w3d.direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			return (hit["position"] as Vector3).y
	var tree := get_tree()
	var scene := tree.current_scene if tree != null else null
	if scene != null and scene.has_method("_find_ground_y"):
		return float(scene.call("_find_ground_y", pos.x, pos.z))
	var p := get_parent()
	if p != null and p.has_method("_find_ground_y"):
		return float(p.call("_find_ground_y", pos.x, pos.z))
	return pos.y - 0.5


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
	var parent_node := get_parent()
	if parent_node == null or not is_instance_valid(parent_node):
		return
	var decal := Decal.new()
	decal.texture_albedo = _crater_texture
	decal.size = Vector3(crater_r * 2.1, 4.5, crater_r * 2.1)
	decal.cull_mask = 1
	decal.albedo_mix = 0.55
	decal.upper_fade = 0.45
	decal.lower_fade = 0.35
	parent_node.add_child(decal)
	decal.global_position = Vector3(ground.x, ground.y + 1.5, ground.z)
	_free_after(decal, 75.0)
	# Keep ground clods parented under parent_node directly on the terrain
	# (never as children of the elevated decal) and clean them up quickly.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.09, 0.075, 0.055)
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.metallic_specular = 0.20
	var clods_root := Node3D.new()
	clods_root.name = "CraterClods"
	parent_node.add_child(clods_root)
	clods_root.global_position = Vector3.ZERO
	for i in range(7):
		var a := TAU * float(i) / 7.0 + randf() * 0.4
		var dist := crater_r * randf_range(0.45, 0.85)
		var cx := ground.x + cos(a) * dist
		var cz := ground.z + sin(a) * dist
		var clod_y := ground.y
		var cq := PhysicsRayQueryParameters3D.create(
				Vector3(cx, ground.y + 3.0, cz),
				Vector3(cx, ground.y - 3.0, cz))
		cq.collision_mask = 1
		var chit := space.intersect_ray(cq)
		if not chit.is_empty():
			clod_y = (chit["position"] as Vector3).y
		var h := randf_range(0.08, 0.25)
		var clod := MeshInstance3D.new()
		var w := randf_range(0.12, 0.42)
		var d := randf_range(0.12, 0.42)
		clod.mesh = DestructionFx.debris_mesh()
		clod.scale = Vector3(w / 0.34, h / 0.22, d / 0.28)
		clod.material_override = mat
		clod.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		clods_root.add_child(clod)
		clod.global_position = Vector3(cx, clod_y + h * 0.35, cz)
		clod.rotation.y = randf() * TAU
	_free_after(clods_root, 3.0)


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
	var wind := _scene_wind(self)
	var wind_speed := wind.length()
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.8
	process.direction = (Vector3.UP + wind * 0.14).normalized()
	process.spread = 80.0
	process.initial_velocity_min = 1.5 + wind_speed * 0.25
	process.initial_velocity_max = 5.0 + wind_speed * 0.45
	process.gravity = Vector3(0.0, 0.8, 0.0) + wind * 0.45
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
	smoke.visibility_aabb = AABB(Vector3(-35, -5, -35), Vector3(70, 65, 70))
	var wind := _scene_wind(parent)
	var wind_speed := wind.length()
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.5
	process.direction = (Vector3.UP + wind * 0.18).normalized()
	process.spread = 10.0
	process.initial_velocity_min = 1.0 + wind_speed * 0.22
	process.initial_velocity_max = 2.8 + wind_speed * 0.42
	process.gravity = Vector3(0.0, 0.6, 0.0) + wind * 0.45
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


static func _scene_wind(node: Node) -> Vector3:
	var tree: SceneTree = null
	if node != null and node.is_inside_tree():
		tree = node.get_tree()
	if tree == null:
		tree = Engine.get_main_loop() as SceneTree
	var raw: Variant = null
	if tree != null and tree.current_scene != null:
		raw = tree.current_scene.get("_current_wind_vector")
	if not (raw is Vector3) and node != null:
		raw = node.get("_current_wind_vector")
	if raw is Vector3:
		var w := raw as Vector3
		return Vector3(w.x, 0.0, w.z)
	return Vector3.ZERO


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
