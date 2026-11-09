## Fast enemy AA tracer. Uses a segment raycast every physics frame so it
## cannot tunnel through the small drone at 130 m/s.
class_name AATracer
extends Node3D

const ExplosionScript = preload("res://combat/explosion.gd")

var velocity := Vector3.ZERO
var damage := 8.5
var life := 3.0
var shooter: CollisionObject3D = null
var tracer_color := Color(1.0, 0.94, 0.55)
var tracer_width := 1.0
var _core: MeshInstance3D
var _glow: MeshInstance3D


func setup(origin: Vector3, direction: Vector3, speed: float, hit_damage: float,
		from_shooter: CollisionObject3D) -> void:
	global_position = origin
	velocity = direction.normalized() * speed
	damage = hit_damage
	shooter = from_shooter
	var flat := direction.normalized()
	if flat.length_squared() > 0.0001 and absf(flat.dot(Vector3.UP)) < 0.985:
		look_at(origin + flat, Vector3.UP)
	elif flat.length_squared() > 0.0001:
		look_at(origin + flat, Vector3.FORWARD)


func _ready() -> void:
	var width := maxf(tracer_width, 0.2)
	var core_mesh := BoxMesh.new()
	core_mesh.size = Vector3(0.055, 0.055, 1.5) * width
	_core = MeshInstance3D.new()
	_core.mesh = core_mesh
	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.albedo_color = tracer_color
	core_mat.emission_enabled = true
	core_mat.emission = tracer_color
	core_mat.emission_energy_multiplier = 6.0
	_core.material_override = core_mat
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_core)

	var glow_mesh := BoxMesh.new()
	glow_mesh.size = Vector3(0.10, 0.10, 1.9) * width
	_glow = MeshInstance3D.new()
	_glow.mesh = glow_mesh
	var glow_mat := StandardMaterial3D.new()
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow_mat.albedo_color = Color(tracer_color.r, tracer_color.g * 0.55,
			tracer_color.b * 0.18, 0.14)
	glow_mat.emission_enabled = true
	glow_mat.emission = tracer_color
	glow_mat.emission_energy_multiplier = 2.0
	_glow.material_override = glow_mat
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_glow)


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	var from := global_position
	var to := from + velocity * delta
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.collide_with_areas = false
	if shooter != null and is_instance_valid(shooter):
		query.exclude = [shooter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var collider = hit.get("collider")
		var point: Vector3 = hit.get("position", to)
		var scene := get_tree().current_scene
		if collider is Drone:
			if scene != null:
				var combat := scene.get_node_or_null("CombatSystem")
				if combat != null and combat.has_method("damage_drone"):
					var source_pos := Vector3.ZERO
					if shooter != null and is_instance_valid(shooter) and shooter is Node3D:
						source_pos = (shooter as Node3D).global_position
					combat.call("damage_drone", damage, point, source_pos)
		elif scene != null:
			ExplosionScript.spark_burst(scene, point)
		queue_free()
		return
	global_position = to
