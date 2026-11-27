## Wraps an authored Blender landmark (hospital, factory hall, bridge, bunker)
## and makes it destructible without rebuilding its mesh.
##
## The landmark stays a normal GLB scene until its health reaches zero; then the
## visible meshes are hidden, its collision is switched off and a rubble pile +
## dust + fire column take its place.  Explosions damage it through the standard
## "combat_target" group, so payload drops, kamikaze hits and enemy tank shells
## all work without extra wiring.
class_name DestructibleLandmark
extends StaticBody3D

signal destroyed(points: int)

const ExplosionScript = preload("res://combat/explosion.gd")
const CombatSfxScript = preload("res://combat/sfx.gd")
const DestructibleProxyScript = preload("res://combat/destructible_proxy.gd")

var health := 1600.0
var max_health := 1600.0
var points := 500
var target: Node3D = null
var is_destroyed := false

var _rubble_material: StandardMaterial3D = null


func setup(target_node: Node3D, hit_points: float = 1600.0,
		award: int = 500) -> void:
	target = target_node
	health = maxf(1.0, hit_points)
	max_health = health
	points = award

	var target_bodies := target.find_children("*", "StaticBody3D", true, false)
	if not target_bodies.is_empty():
		# The authored GLB already has real collision bodies (e.g. arch opening,
		# doorway, bridges). Use them directly so open spaces remain flyable.
		collision_layer = 0
		collision_mask = 0
		for node in target_bodies:
			var body := node as StaticBody3D
			body.set_script(DestructibleProxyScript)
			body.set("landmark", self)
			body.add_to_group("combat_target")
			body.add_to_group("destructible")
	else:
		# Fallback for models without authored collision: use mesh bounds
		collision_layer = 1
		collision_mask = 1
		var bounds := AABB()
		var has_bounds := false
		for node in target.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			var box := mi.global_transform * mi.get_aabb()
			bounds = box if not has_bounds else bounds.merge(box)
			has_bounds = true
		if has_bounds:
			var col := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(maxf(bounds.size.x, 2.0), maxf(bounds.size.y, 2.0),
					maxf(bounds.size.z, 2.0))
			col.shape = shape
			col.position = bounds.get_center() - global_position
			add_child(col)


func _ready() -> void:
	add_to_group("combat_target")
	add_to_group("destructible")


func take_damage(amount: float, hit_position: Vector3 = Vector3.ZERO) -> void:
	if is_destroyed or target == null:
		return
	health -= amount
	if hit_position != Vector3.ZERO and health > 0.0:
		ExplosionScript.spark_burst(get_parent(), hit_position)
		CombatSfxScript.play_target_hit(get_parent(), hit_position, false, true)
	if health <= 0.0:
		_destroy()


func _destroy() -> void:
	if is_destroyed:
		return
	is_destroyed = true
	remove_from_group("combat_target")
	collision_layer = 0
	collision_mask = 0
	var centre := target.global_position
	for node in target.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).visible = false
	for node in target.find_children("*", "StaticBody3D", true, false):
		var body := node as StaticBody3D
		body.collision_layer = 0
		body.collision_mask = 0
		body.remove_from_group("combat_target")
		body.remove_from_group("destructible")
	var parent := get_parent()
	if parent != null:
		# Visual-only blast: the building itself is already gone, so no second
		# damage pass is needed.
		ExplosionScript.spawn(parent, centre + Vector3.UP * 3.0, 13.0, 0.0)
		ExplosionScript.fire_column(parent, centre + Vector3.UP * 2.0, 14.0)
		ExplosionScript.smoke_column(parent, centre + Vector3.UP * 6.0, 42.0)
		CombatSfxScript.play_boom(parent, centre, 4.5, true, true)
		CombatSfxScript.play_hitmarker(parent, true, 0.5)
		_spawn_rubble(parent, centre)
	destroyed.emit(points)


func _spawn_rubble(parent: Node, centre: Vector3) -> void:
	if _rubble_material == null:
		_rubble_material = StandardMaterial3D.new()
		_rubble_material.albedo_color = Color(0.33, 0.31, 0.28)
		_rubble_material.roughness = 0.98
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(target.name)) + 17
	for i in range(14):
		var chunk := RigidBody3D.new()
		var size := Vector3(rng.randf_range(0.4, 1.8), rng.randf_range(0.25, 0.9),
				rng.randf_range(0.4, 1.8))
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		mesh.mesh = box
		mesh.material_override = _rubble_material
		mesh.rotation = Vector3(rng.randf_range(-0.5, 0.5),
				rng.randf_range(0.0, TAU), rng.randf_range(-0.5, 0.5))
		chunk.add_child(mesh)
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		chunk.add_child(shape)
		parent.add_child(chunk)
		chunk.global_position = centre + Vector3(
				rng.randf_range(-5.0, 5.0), rng.randf_range(0.4, 4.0),
				rng.randf_range(-5.0, 5.0))
		chunk.apply_central_impulse(Vector3(
				rng.randf_range(-2.0, 2.0), rng.randf_range(1.0, 4.0),
				rng.randf_range(-2.0, 2.0)) * chunk.mass * 8.0)
		chunk.angular_velocity = Vector3(rng.randf_range(-3, 3),
				rng.randf_range(-3, 3), rng.randf_range(-3, 3))
		var timer := get_tree().create_timer(10.0)
		timer.timeout.connect(func() -> void:
			if is_instance_valid(chunk):
				chunk.queue_free())
