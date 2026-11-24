## Destructible ground target using authored 3D GLB models for tanks, armored
## trucks (GAZ Tigr), and infantry (rifleman), plus reinforced concrete bunkers.
class_name CombatTarget
extends StaticBody3D

signal destroyed(points: int)
signal damaged(health_left: float)

const ExplosionScript = preload("res://combat/explosion.gd")

enum Kind {TANK, TRUCK, BUNKER, INFANTRY}

const MODEL_PATHS := {
	Kind.TANK: "res://Assets/vehicles/low_poly_t-72_tank_-_game_ready.glb",
	Kind.TRUCK: "res://Assets/vehicles/gaz_tigr_low_poly.glb",
	Kind.INFANTRY: "res://Assets/combat/rifleman.glb",
}
const TARGET_SIZE_BOOST := 1.44
const MODEL_SIZE := {
	Kind.TANK: 8.8 * TARGET_SIZE_BOOST,
	Kind.TRUCK: 5.5 * TARGET_SIZE_BOOST,
	Kind.INFANTRY: 1.9 * TARGET_SIZE_BOOST,
}
const MODEL_YAW := {
	Kind.TANK: 0.0,
	Kind.TRUCK: PI,
	Kind.INFANTRY: 0.0,
}

@export var kind: Kind = Kind.TANK
@export var max_health := 320.0
@export var points := 400

var health := 0.0
var is_destroyed := false

var _meshes: Array[MeshInstance3D] = []
var _flash_material: StandardMaterial3D
var _burnt_material: StandardMaterial3D
var _flash_token := 0


func _ready() -> void:
	health = max_health
	add_to_group("combat_target")
	collision_layer = 1
	collision_mask = 1
	_build()


func take_damage(amount: float, hit_position: Vector3 = Vector3.ZERO) -> void:
	if is_destroyed:
		return
	health -= amount
	if hit_position != Vector3.ZERO and health > 0.0:
		ExplosionScript.spark_burst(get_parent(), hit_position)
	_flash()
	if health <= 0.0:
		_destroy()
	else:
		damaged.emit(health)


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
	await get_tree().create_timer(0.07).timeout
	if not is_instance_valid(self) or is_destroyed or token != _flash_token:
		return
	for mesh in _meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = null


func _destroy() -> void:
	if is_destroyed:
		return
	is_destroyed = true
	remove_from_group("combat_target")
	collision_layer = 0
	collision_mask = 0
	if _burnt_material == null:
		_burnt_material = StandardMaterial3D.new()
		_burnt_material.albedo_color = Color(0.045, 0.043, 0.04)
		_burnt_material.roughness = 1.0
	for mesh in _meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = null
			mesh.material_override = _burnt_material
	var parent := get_parent()
	if parent != null:
		ExplosionScript.spawn(parent, global_position + Vector3.UP * 1.1, 6.5, 140.0)
		ExplosionScript.smoke_column(parent, global_position + Vector3.UP * 1.6, 30.0)
		ExplosionScript.fire_column(parent, global_position + Vector3.UP * 0.6, 8.0)
	destroyed.emit(points)


# ---------------------------------------------------------------- construction

func _build() -> void:
	if MODEL_PATHS.has(kind):
		var path: String = MODEL_PATHS[kind]
		if ResourceLoader.exists(path) and _build_from_glb(path, float(MODEL_SIZE[kind]), float(MODEL_YAW[kind])):
			return
	match kind:
		Kind.TANK:
			_build_tank_fallback()
		Kind.TRUCK:
			_build_truck_fallback()
		Kind.BUNKER:
			_build_bunker()
		Kind.INFANTRY:
			_build_infantry_fallback()


func _build_from_glb(path: String, target_len: float, yaw: float) -> bool:
	var packed := load(path) as PackedScene
	if packed == null:
		return false
	var model := packed.instantiate() as Node3D
	if model == null:
		return false
	model.name = "Model"
	add_child(model)
	model.rotation = Vector3(0.0, yaw, 0.0)
	var box := DroneCatalog.model_bounds(model)
	var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	if longest > 0.001:
		model.scale = Vector3.ONE * (target_len / longest)
	var after := DroneCatalog.model_bounds(model)
	var center := after.get_center()
	model.global_position += Vector3(
			global_position.x - center.x,
			global_position.y - after.position.y,
			global_position.z - center.z)
	_collect_meshes(model)
	var csize := after.size
	if kind == Kind.TANK:
		csize = Vector3(3.6, 2.4, 7.4) * TARGET_SIZE_BOOST
	elif kind == Kind.TRUCK:
		csize = Vector3(2.4, 2.4, 5.4) * TARGET_SIZE_BOOST
	elif kind == Kind.INFANTRY:
		csize = Vector3(0.75, 1.9, 0.75) * TARGET_SIZE_BOOST
	_add_collision(csize, Vector3(0.0, csize.y * 0.5, 0.0))
	return true


func _collect_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		_meshes.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child)


func _build_bunker() -> void:
	var concrete := Color(0.36, 0.35, 0.32)
	var dark := Color(0.06, 0.06, 0.06)
	var sandbag := Color(0.46, 0.41, 0.29)
	_add_box(Vector3(5.6, 1.95, 3.8), Vector3(0, 0.97, 0), concrete)
	_add_box(Vector3(6.2, 0.32, 4.4), Vector3(0, 2.02, 0), concrete.darkened(0.18))
	_add_box(Vector3(4.4, 0.42, 0.18), Vector3(0, 1.42, -1.91), dark)
	for i in range(-2, 3):
		_add_box(Vector3(1.1, 0.45, 0.55), Vector3(i * 1.15, 0.22, -2.2), sandbag)
		_add_box(Vector3(1.0, 0.42, 0.50), Vector3(i * 1.10, 0.64, -2.15), sandbag.darkened(0.08))
	_add_collision(Vector3(6.0, 2.3, 4.4), Vector3(0, 1.15, 0))


func _build_tank_fallback() -> void:
	scale = Vector3.ONE * TARGET_SIZE_BOOST
	var hull := Color(0.24, 0.28, 0.18)
	var dark := Color(0.08, 0.08, 0.08)
	_add_box(Vector3(2.8, 1.1, 6.0), Vector3(0, 0.7, 0), hull)
	_add_box(Vector3(2.0, 0.65, 2.5), Vector3(0, 1.55, 0.1), hull.darkened(0.08))
	_add_cylinder(0.11, 3.2, Vector3(0, 1.62, -2.4), Vector3(90, 0, 0), dark)
	_add_collision(Vector3(3.2, 2.2, 6.4), Vector3(0, 1.1, 0))


func _build_truck_fallback() -> void:
	scale = Vector3.ONE * TARGET_SIZE_BOOST
	var body := Color(0.26, 0.30, 0.19)
	_add_box(Vector3(2.3, 1.8, 5.2), Vector3(0, 1.1, 0), body)
	_add_collision(Vector3(2.5, 2.4, 5.6), Vector3(0, 1.2, 0))


func _build_infantry_fallback() -> void:
	scale = Vector3.ONE * TARGET_SIZE_BOOST
	var uniform := Color(0.26, 0.30, 0.18)
	_add_box(Vector3(0.52, 1.75, 0.35), Vector3(0, 0.9, 0), uniform)
	_add_collision(Vector3(0.62, 1.82, 0.62), Vector3(0, 0.91, 0))


func _add_box(size: Vector3, position: Vector3, color: Color, emission: float = 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _add_mesh(mesh, position, color, emission)


func _add_cylinder(radius: float, height: float, position: Vector3, rotation_deg: Vector3,
		color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	mesh.rings = 1
	var instance := _add_mesh(mesh, position, color, 0.0)
	instance.rotation_degrees = rotation_deg
	return instance


func _add_mesh(mesh: Mesh, position: Vector3, color: Color,
		emission: float) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	instance.material_override = material
	add_child(instance)
	_meshes.append(instance)
	return instance


func _add_collision(size: Vector3, position: Vector3) -> void:
	var box := BoxShape3D.new()
	box.size = size
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position = position
	add_child(shape)
