## Destructible enemy AA nest: a procedurally built twin-gun turret that tracks
## the armed player drone, fires visible tracers in bursts and damages its hull.
## Not part of the 10-target ground roster; it is a bonus threat worth extra score.
class_name AAGun
extends StaticBody3D

signal destroyed(points: int)

const TracerScript = preload("res://combat/tracer.gd")
const ExplosionScript = preload("res://combat/explosion.gd")
const CombatSfxScript = preload("res://combat/sfx.gd")

@export var max_health := 320.0
@export var points := 500
@export var detect_range := 46.0
@export var tracer_damage := 8.5
@export var tracer_speed := 130.0
@export var burst_shots := 5
@export var shot_interval := 0.11
@export var burst_pause_min := 1.35
@export var burst_pause_max := 1.85

var health := 0.0
var is_destroyed := false

var _drone: Drone = null
var _combat: Node = null
var _turret: Node3D = null
var _barrels: Node3D = null
var _muzzles: Array[Marker3D] = []
var _meshes: Array[MeshInstance3D] = []
var _warning_light: MeshInstance3D = null
var _label: Label3D = null
var _disabled := false

var _flash_material: StandardMaterial3D = null
var _burnt_material: StandardMaterial3D = null
var _flash_token := 0

var _los_clear := false
var _distance := 999.0
var _los_timer := 0.0
var _burst_left := 0
var _shot_cd := 0.0
var _recover := 1.2
var _muzzle_index := 0
var _aim_yaw := 0.0
var _demo_miss := false


func _ready() -> void:
	health = max_health
	add_to_group("combat_target")
	add_to_group("aa_gun")
	collision_layer = 1
	collision_mask = 1
	_disabled = _qa_disabled()
	_build()
	scale *= Vector3.ONE * 1.44
	var cs := get_tree().current_scene if get_tree() != null else null
	if cs != null:
		if _drone == null or not is_instance_valid(_drone):
			_drone = cs.get_node_or_null("Drone") as Drone
		if _combat == null:
			_combat = cs.get_node_or_null("CombatSystem")
	_recover = randf_range(1.0, 1.6)
	match Global.difficulty:
		Global.Difficulty.RECRUIT:
			detect_range = 48.0
			tracer_damage = 5.0
			burst_shots = 3
			shot_interval = 0.16
		Global.Difficulty.OPERATOR:
			detect_range = 64.0
			tracer_damage = 8.0
			burst_shots = 5
			shot_interval = 0.11
		Global.Difficulty.ACE:
			detect_range = 88.0
			tracer_damage = 12.5
			burst_shots = 7
			shot_interval = 0.09


func _process(_delta: float) -> void:
	if _warning_light == null or not is_instance_valid(_warning_light):
		return
	if is_destroyed or _disabled:
		_warning_light.visible = false
		return
	var pulse := 0.85 + sin(Time.get_ticks_msec() * 0.007) * 0.25
	_warning_light.scale = Vector3.ONE * pulse


func _physics_process(delta: float) -> void:
	if is_destroyed or _disabled:
		return
	if _drone == null or not is_instance_valid(_drone):
		var cs := get_tree().current_scene if get_tree() != null else null
		if cs != null:
			_drone = cs.get_node_or_null("Drone") as Drone
	if _drone == null:
		return

	_los_timer -= delta
	if _los_timer <= 0.0:
		_los_timer = 0.12
		_update_target()

	if not _can_engage():
		_burst_left = 0
		_recover = maxf(_recover, 0.45)
		return

	var aligned := _aim_at_drone(delta)
	if not aligned:
		return

	if _burst_left > 0:
		_shot_cd -= delta
		if _shot_cd <= 0.0:
			_fire()
			_burst_left -= 1
			_shot_cd = shot_interval
			if _burst_left <= 0:
				_recover = randf_range(burst_pause_min, burst_pause_max)
	else:
		_recover -= delta
		if _recover <= 0.0:
			_burst_left = burst_shots
			_shot_cd = 0.0


func _can_engage() -> bool:
	if _drone == null or not is_instance_valid(_drone):
		return false
	var controller := _drone.get_node_or_null("FlightController") as FlightController
	if controller == null or not controller.state_armed:
		return false
	if _combat != null and _combat.has_method("can_take_damage"):
		if not bool(_combat.call("can_take_damage")):
			return false
	return _los_clear and _distance <= detect_range and _distance > 4.0


func _update_target() -> void:
	_los_clear = false
	if _turret == null or _drone == null or not is_instance_valid(_drone):
		return
	_distance = _turret.global_position.distance_to(_drone.global_position)
	if _distance > detect_range:
		return
	var world := get_world_3d()
	if world == null:
		return
	var space := world.direct_space_state
	if space == null:
		return
	var from := _turret.global_position + Vector3.UP * 0.35
	var target := _drone.global_position
	var query := PhysicsRayQueryParameters3D.create(from, target)
	query.collision_mask = 1
	query.collide_with_areas = false
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		_los_clear = true
		return
	var collider = hit.get("collider")
	if collider == _drone:
		_los_clear = true
		return
	var point: Vector3 = hit.get("position", target)
	_los_clear = from.distance_to(point) >= from.distance_to(target) - 1.0


func _aim_at_drone(delta: float) -> bool:
	if _turret == null or _barrels == null or _drone == null or not is_instance_valid(_drone):
		return false
	var to := _drone.global_position - _turret.global_position
	var flat := Vector3(to.x, 0.0, to.z)
	if flat.length_squared() < 0.01:
		return false
	_aim_yaw = atan2(-flat.x, -flat.z)
	var parent_yaw: float = global_rotation.y
	var local_yaw := wrapf(_aim_yaw - parent_yaw, -PI, PI)
	_turret.rotation.y = lerp_angle(_turret.rotation.y, local_yaw, clampf(delta * 5.0, 0.0, 1.0))
	var pitch := atan2(to.y, flat.length())
	var clamped_pitch := clampf(pitch, -0.30, 1.32)
	_barrels.rotation.x = lerp_angle(_barrels.rotation.x, clamped_pitch,
			clampf(delta * 5.5, 0.0, 1.0))
	return absf(angle_difference(_turret.rotation.y, local_yaw)) < 0.26 \
			and absf(angle_difference(_barrels.rotation.x, clamped_pitch)) < 0.28


func _fire() -> void:
	if _muzzles.is_empty() or _drone == null or not is_instance_valid(_drone):
		return
	var muzzle := _muzzles[_muzzle_index % _muzzles.size()]
	if muzzle == null or not is_instance_valid(muzzle):
		return
	_muzzle_index += 1
	var muzzle_pos := muzzle.global_position
	var lead := (_distance / tracer_speed) * 0.8
	var target := _drone.global_position + _drone.linear_velocity * lead
	if _demo_miss:
		target += _barrels.global_transform.basis.x.normalized() * 1.15
	var dir := (target - muzzle_pos).normalized()
	var acc_scale := maxf(Global.get_difficulty_enemy_accuracy_scale(), 0.25)
	var spread := (0.007 + _distance * 0.00028) / acc_scale
	dir = (dir + Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)) * spread).normalized()
	var tracer = TracerScript.new()
	tracer.tracer_color = Color(1.0, 0.58, 0.16)
	tracer.tracer_width = 1.85
	tracer.add_to_group("aa_tracer")
	var tracer_parent := get_parent()
	if tracer_parent != null:
		tracer_parent.add_child(tracer)
		tracer.setup(muzzle_pos, dir, tracer_speed, tracer_damage, self)
	CombatSfxScript.play_autocannon(get_parent(), muzzle_pos, -5.0)
	_muzzle_flash(muzzle_pos)


func _muzzle_flash(position: Vector3) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var parent := get_parent()
	if parent == null:
		return
	var sphere := SphereMesh.new()
	sphere.radius = 0.34
	sphere.height = 0.68
	sphere.radial_segments = 8
	sphere.rings = 4
	var flash := MeshInstance3D.new()
	flash.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(1.0, 0.78, 0.25, 0.96)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.55, 0.10)
	material.emission_energy_multiplier = 7.5
	flash.material_override = material
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(flash)
	flash.global_position = position
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.16
	core_mesh.height = 0.32
	core_mesh.radial_segments = 6
	core_mesh.rings = 3
	var core := MeshInstance3D.new()
	core.mesh = core_mesh
	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.albedo_color = Color(1.0, 0.96, 0.78)
	core.material_override = core_mat
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash.add_child(core)
	var tween := flash.create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ONE * 2.8, 0.11)
	tween.tween_property(material, "albedo_color", Color(1.0, 0.42, 0.05, 0.0), 0.11)
	tween.chain().tween_callback(flash.queue_free)


func take_damage(amount: float, hit_position: Vector3 = Vector3.ZERO) -> void:
	if is_destroyed:
		return
	health -= amount
	if hit_position != Vector3.ZERO:
		ExplosionScript.spark_burst(get_parent(), hit_position)
	_flash()
	if health <= 0.0:
		_destroy()


## QA-only: force a burst (slightly off-target) so the preview catches tracers.
func demo_warm_up() -> void:
	if is_destroyed or _disabled:
		return
	_demo_miss = true
	_recover = 0.0
	_burst_left = burst_shots
	_shot_cd = 0.0
	_muzzle_index = 0


func _flash() -> void:
	if _meshes.is_empty():
		return
	if _flash_material == null:
		_flash_material = StandardMaterial3D.new()
		_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_flash_material.albedo_color = Color(1.0, 0.75, 0.35, 0.65)
	_flash_token += 1
	var token := _flash_token
	for mesh in _meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = _flash_material
	var tree := get_tree()
	if tree == null or not is_inside_tree():
		return
	await tree.create_timer(0.07).timeout
	if not is_inside_tree() or not is_instance_valid(self) or is_destroyed or token != _flash_token:
		return
	for mesh in _meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = null


func _destroy() -> void:
	if is_destroyed:
		return
	is_destroyed = true
	remove_from_group("combat_target")
	remove_from_group("primary_combat_target")
	remove_from_group("bonus_combat_target")
	collision_layer = 0
	collision_mask = 0
	_burst_left = 0
	if _label != null:
		_label.visible = false
	if _warning_light != null:
		_warning_light.visible = false
	if _burnt_material == null:
		_burnt_material = StandardMaterial3D.new()
		_burnt_material.albedo_color = Color(0.045, 0.043, 0.04)
		_burnt_material.roughness = 1.0
	for mesh in _meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = null
			mesh.material_override = _burnt_material
	if _barrels != null:
		_barrels.rotation.x = -0.55
	if _turret != null:
		_turret.rotation.z = deg_to_rad(-8.0)
	var parent := get_parent()
	if parent != null:
		ExplosionScript.spawn(parent, global_position + Vector3.UP * 1.35, 7.0, 0.0)
		ExplosionScript.smoke_column(parent, global_position + Vector3.UP * 1.8, 32.0)
		ExplosionScript.fire_column(parent, global_position + Vector3.UP * 0.8, 9.0)
	destroyed.emit(points)


# ---------------------------------------------------------------- construction

func _build() -> void:
	var concrete := Color(0.34, 0.33, 0.30)
	var olive := Color(0.28, 0.32, 0.20)
	var dark := Color(0.075, 0.08, 0.07)
	var rust := Color(0.36, 0.20, 0.10)

	_add_box(self, Vector3(3.6, 0.55, 3.4), Vector3(0, 0.28, 0), concrete)
	for i in range(6):
		var angle := TAU * float(i) / 6.0
		_add_box(self, Vector3(0.95, 0.45, 0.62),
				Vector3(cos(angle) * 1.55, 0.25, sin(angle) * 1.45),
				rust.darkened(0.10 + 0.04 * float(i % 2)))

	_add_cylinder(self, 0.52, 1.05, Vector3(0, 0.95, 0), Vector3.ZERO, concrete.darkened(0.18))
	_add_cylinder(self, 0.72, 0.16, Vector3(0, 0.50, 0), Vector3.ZERO, concrete.darkened(0.24))

	_turret = Node3D.new()
	_turret.name = "Turret"
	_turret.position = Vector3(0, 1.45, 0)
	add_child(_turret)
	_add_box(_turret, Vector3(1.7, 0.62, 1.5), Vector3(0, 0.30, 0.0), olive)
	_add_box(_turret, Vector3(1.95, 0.80, 0.12), Vector3(0, 0.52, -0.72), olive.darkened(0.18))
	_add_box(_turret, Vector3(0.52, 0.40, 0.52), Vector3(0.82, 0.30, 0.12), dark)
	_add_box(_turret, Vector3(0.40, 0.26, 0.34), Vector3(-0.62, 0.62, 0.20), rust)
	_warning_light = _add_sphere(_turret, 0.18, Vector3(0.55, 0.76, 0.32),
			Color(1.0, 0.24, 0.04), 5.0)

	var antenna := _add_cylinder(self, 0.035, 2.4, Vector3(-1.15, 1.55, 0.75),
			Vector3.ZERO, dark)
	antenna.rotation.z = deg_to_rad(8.0)
	_add_sphere(self, 0.10, Vector3(-1.30, 2.76, 0.75), Color(1.0, 0.28, 0.05), 4.0)

	_barrels = Node3D.new()
	_barrels.name = "Barrels"
	_barrels.position = Vector3(0, 0.55, 0)
	_turret.add_child(_barrels)
	for x in [-0.30, 0.30]:
		_add_cylinder(_barrels, 0.075, 2.9, Vector3(x, 0, -1.45), Vector3(90, 0, 0), dark)
		_add_cylinder(_barrels, 0.115, 0.52, Vector3(x, 0, -2.45), Vector3(90, 0, 0),
				olive.darkened(0.20))
		_add_cylinder(_barrels, 0.105, 0.22, Vector3(x, 0, -2.86), Vector3(90, 0, 0), rust)
		var marker := Marker3D.new()
		marker.name = "Muzzle"
		marker.position = Vector3(x, 0, -2.98)
		_barrels.add_child(marker)
		_muzzles.append(marker)
	_add_box(_barrels, Vector3(0.86, 0.18, 0.34), Vector3(0, 0, -0.82), dark)
	_add_box(_turret, Vector3(0.38, 0.28, 0.44), Vector3(0.62, 0.62, 0.18), rust)
	_add_cylinder(_turret, 0.04, 0.42, Vector3(0.0, 0.85, -0.45), Vector3(0, 0, 0), dark)

	_label = Label3D.new()
	_label.text = "AA"
	_label.font_size = 64
	_label.pixel_size = 0.008
	_label.modulate = Color(1.0, 0.32, 0.14)
	_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.92)
	_label.outline_size = 14
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = false
	_label.position = Vector3(0, 3.5, 0)
	_label.visible = false
	add_child(_label)

	var shape := BoxShape3D.new()
	shape.size = Vector3(3.6, 2.7, 3.6)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = Vector3(0, 1.35, 0)
	add_child(collision)


func _add_box(parent: Node3D, size: Vector3, position: Vector3, color: Color,
		emission: float = 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _add_mesh(parent, mesh, position, color, emission, Vector3.ZERO)


func _add_cylinder(parent: Node3D, radius: float, height: float, position: Vector3,
		rotation_deg: Vector3, color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	mesh.rings = 1
	var instance := _add_mesh(parent, mesh, position, color, 0.0, rotation_deg)
	return instance


func _add_sphere(parent: Node3D, radius: float, position: Vector3, color: Color,
		emission: float) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	return _add_mesh(parent, mesh, position, color, emission, Vector3.ZERO)


func _add_mesh(parent: Node3D, mesh: Mesh, position: Vector3, color: Color,
		emission: float, rotation_deg: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	instance.rotation_degrees = rotation_deg
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	instance.material_override = material
	parent.add_child(instance)
	_meshes.append(instance)
	return instance


func _qa_disabled() -> bool:
	if OS.has_environment("DRONE_AA_DEMO"):
		return false
	var qa := OS.has_environment("DRONE_AUTOTEST") or OS.has_environment("DRONE_AUTOTEST_COMBAT") or OS.has_environment("DRONE_SCREENSHOT") or OS.has_environment("DRONE_SHOWCASE") or OS.has_environment("DRONE_COMBAT_DEMO")
	return qa
