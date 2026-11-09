## Free-fall bomb / mortar mine / anti-tank mine dropped from the drone.
## The aerodynamic model is shared with BombBallistics so the bomb-sight CCIP
## and the physical body always agree (including wind drift).
class_name Payload
extends RigidBody3D

signal exploded

const ExplosionScript = preload("res://combat/explosion.gd")
const Ballistics = preload("res://combat/ballistics.gd")

var damage := 480.0
var blast_radius := 9.0
var arm_time := 0.35
var kind := "vog"
var wind := Vector3.ZERO
## Optional per-munition mass (kg).  When > 0 it overrides the profile mass so
## every drone drops a projectile that matches its own payload_mass.
var mass_override := 0.0

var _age := 0.0
var _exploded := false


func _ready() -> void:
	mass = mass_override if mass_override > 0.0 else Ballistics.mass_for(kind)
	gravity_scale = 1.0
	# A freshly released store must simulate on the very next physics tick.
	# Without an explicit wake-up a rigid body that was created at rest can
	# spend one or more ticks asleep, which read as input/release lag.
	sleeping = false
	can_sleep = false
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 4
	linear_damp = 0.01
	angular_damp = 0.15
	_build()
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_age += delta
	if _exploded:
		return
	var scene := get_tree().current_scene
	if scene != null and scene.get("_current_wind_vector") != null:
		wind = scene.get("_current_wind_vector")
	Ballistics.apply_drag(self, wind, kind)
	if _age > 60.0 or global_position.y < -40.0:
		queue_free()
		return
	if _age > arm_time and not get_colliding_bodies().is_empty():
		explode()


func _on_body_entered(_body: Node) -> void:
	if _exploded or _age < arm_time:
		return
	explode()


func explode() -> void:
	if _exploded:
		return
	_exploded = true
	var parent := get_parent()
	var at := global_position + Vector3.UP * 0.6
	if parent != null:
		ExplosionScript.spawn(parent, at, blast_radius, damage)
	exploded.emit()
	queue_free()


func _build() -> void:
	var dark := Color(0.18, 0.19, 0.15)
	var metal := Color(0.30, 0.31, 0.26)
	var olive := Color(0.12, 0.14, 0.055)
	match kind:
		"120mm":
			_build_82mm(0.060, 0.40, 0.18, olive, metal)
		"tm62":
			_build_tm62(olive, dark, metal)
		_:
			_build_82mm(0.041, 0.28, 0.13, olive, metal)
	_build_trail()


func _build_82mm(radius: float, length: float, nose: float, body_color: Color,
		metal: Color) -> void:
	# mortar mine body, rounded/ogive nose and tail fins
	_add_cylinder(radius, length, Vector3(0.0, 0.0, 0.0), body_color)
	var cone := _add_cone(radius, nose, Vector3(0.0, -length * 0.5 - nose * 0.5, 0.0),
			body_color)
	_add_cylinder(radius * 0.72, 0.018, Vector3(0.0, -length * 0.5 + 0.01, 0.0),
			metal)
	_add_cylinder(radius * 0.55, 0.055, Vector3(0.0, length * 0.52, 0.0), metal)
	for i in range(4):
		var ang := TAU * float(i) / 4.0
		var fin := BoxMesh.new()
		fin.size = Vector3(radius * 0.7, 0.075, 0.008)
		var mi := MeshInstance3D.new()
		mi.mesh = fin
		mi.position = Vector3(cos(ang) * radius * 0.9, length * 0.60,
				sin(ang) * radius * 0.9)
		mi.rotation.y = ang
		mi.material_override = _mat(metal)
		add_child(mi)
	# yellow band
	_add_cylinder(radius * 1.03, 0.018, Vector3(0.0, length * 0.32, 0.0),
			Color(0.75, 0.30, 0.03))
	var shape := SphereShape3D.new()
	shape.radius = radius * 1.35
	var collider := CollisionShape3D.new()
	collider.shape = shape
	add_child(collider)


func _build_tm62(olive: Color, dark: Color, metal: Color) -> void:
	# flat anti-tank mine with central fuze and carry handle
	_add_cylinder(0.16, 0.075, Vector3.ZERO, olive)
	_add_cylinder(0.165, 0.012, Vector3(0.0, 0.043, 0.0), metal)
	_add_cylinder(0.052, 0.025, Vector3(0.0, 0.065, 0.0), dark)
	_add_cylinder(0.036, 0.012, Vector3(0.0, 0.080, 0.0), metal)
	for sx in [-1, 1]:
		var strap := BoxMesh.new()
		strap.size = Vector3(0.035, 0.085, 0.34)
		var mi := MeshInstance3D.new()
		mi.mesh = strap
		mi.position = Vector3(sx * 0.10, 0.0, 0.0)
		mi.material_override = _mat(dark)
		add_child(mi)
	var shape := CylinderShape3D.new()
	shape.radius = 0.16
	shape.height = 0.09
	var collider := CollisionShape3D.new()
	collider.shape = shape
	add_child(collider)


func _add_cylinder(radius: float, height: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _mat(color)
	add_child(mi)
	return mi


func _add_cone(radius: float, height: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = 0.0
	mesh.height = height
	mesh.radial_segments = 16
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _mat(color)
	add_child(mi)
	return mi


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.72
	return m


func _build_trail() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var trail := GPUParticles3D.new()
	trail.amount = 10
	trail.lifetime = 0.6
	trail.local_coords = false
	trail.emitting = true
	trail.visibility_aabb = AABB(Vector3(-4, -8, -4), Vector3(8, 16, 8))
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 8.0
	process.initial_velocity_min = 0.2
	process.initial_velocity_max = 0.6
	process.gravity = Vector3(0.0, 0.2, 0.0)
	process.scale_min = 0.2
	process.scale_max = 0.45
	process.color_ramp = _ramp()
	trail.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.25, 0.25)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(0.6, 0.6, 0.6)
	quad.material = material
	trail.draw_pass_1 = quad
	add_child(trail)


func _ramp() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([
		Color(0.55, 0.55, 0.55, 0.35),
		Color(0.35, 0.35, 0.35, 0.15),
		Color(0.25, 0.25, 0.25, 0.0),
	])
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture
