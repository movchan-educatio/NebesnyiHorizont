## Destructible building for the combat arena.
##
## A Godot-native replacement for the Rust voxel addon (which targets Godot 4.7
## and ships no binaries). The building is assembled from floors; when it takes
## enough damage it shatters into physics chunks with dust and fire, so bomb and
## kamikaze hits feel destructive without any native dependency.
class_name DestructibleBuilding
extends StaticBody3D

signal destroyed(points: int)

@export var max_health := 420.0
@export var points := 400
@export var floors := 4
@export var footprint := Vector3(18.0, 0.0, 18.0)

var health := 0.0
var is_destroyed := false

var _size := Vector3(18.0, 0.0, 18.0)
var _height := 36.0
var _parts: Array[GeometryInstance3D] = []
var _batches: Dictionary = {}
var _unit_box: BoxMesh = null
var _body_material: StandardMaterial3D = null
var _band_material: StandardMaterial3D = null
var _glass_material: StandardMaterial3D = null
var _flash_material: StandardMaterial3D = null
var _flash_token := 0


func configure(p_size: Vector3, p_floors: int, base_color: Color) -> void:
	footprint = p_size
	floors = maxi(2, p_floors)
	_body_material = _mat(base_color, 0.9)
	_band_material = _mat(base_color.darkened(0.45), 0.8)


func _mat(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material


func _ready() -> void:
	health = max_health
	add_to_group("combat_target")
	add_to_group("destructible")
	collision_layer = 1
	collision_mask = 1
	if _body_material == null:
		_body_material = _mat(Color(0.42, 0.40, 0.36), 0.9)
		_band_material = _mat(Color(0.22, 0.21, 0.20), 0.8)
	if _glass_material == null:
		_glass_material = _mat(Color(0.095, 0.14, 0.19), 0.16)
		_glass_material.metallic = 0.55
		_glass_material.metallic_specular = 0.85
	_build()


func _build() -> void:
	var w := footprint.x
	var d := footprint.z
	var fh := 8.5
	_height = floors * fh
	for i in range(floors):
		var y := fh * (i + 0.5)
		var inset := 0.0 if i % 2 == 0 else 0.8
		var half_w := (w - inset) * 0.5
		var half_d := (d - inset) * 0.5
		_add_box(Vector3(w - inset, fh * 0.9, d - inset), Vector3(0, y, 0),
				_body_material)
		_add_box(Vector3(w + 0.3, fh * 0.18, d + 0.3),
				Vector3(0, y + fh * 0.3, 0), _band_material)
		# A dark glazed band on all four facades. It sits just proud of the
		# concrete so it cannot z-fight with the wall.
		var window_y := fh * i + fh * 0.40
		var window_h := fh * 0.30
		_add_box(Vector3((w - inset) * 0.78, window_h, 0.16),
				Vector3(0, window_y, half_d + 0.07), _glass_material)
		_add_box(Vector3((w - inset) * 0.78, window_h, 0.16),
				Vector3(0, window_y, -half_d - 0.07), _glass_material)
		_add_box(Vector3(0.16, window_h, (d - inset) * 0.78),
				Vector3(half_w + 0.07, window_y, 0), _glass_material)
		_add_box(Vector3(0.16, window_h, (d - inset) * 0.78),
				Vector3(-half_w - 0.07, window_y, 0), _glass_material)

	# Vertical corner pilasters and a rooftop parapet sharpen the silhouette.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_add_box(Vector3(0.55, _height, 0.55),
					Vector3(sx * (w * 0.5 - 0.12), _height * 0.5,
							sz * (d * 0.5 - 0.12)), _band_material)
	_add_box(Vector3(w + 0.55, 0.85, 0.45),
			Vector3(0, _height + 0.42, d * 0.5), _band_material)
	_add_box(Vector3(w + 0.55, 0.85, 0.45),
			Vector3(0, _height + 0.42, -d * 0.5), _band_material)
	_add_box(Vector3(0.45, 0.85, d + 0.55),
			Vector3(w * 0.5, _height + 0.42, 0), _band_material)
	_add_box(Vector3(0.45, 0.85, d + 0.55),
			Vector3(-w * 0.5, _height + 0.42, 0), _band_material)
	_add_box(Vector3(w * 0.9, 0.5, d * 0.9), Vector3(0, _height + 0.15, 0),
			_band_material)
	# Rooftop plant/AC block and a street-level entrance.
	_add_box(Vector3(w * 0.24, 1.6, d * 0.24),
			Vector3(w * 0.17, _height + 1.0, -d * 0.14), _band_material)
	_add_box(Vector3(2.6, 4.2, 0.24), Vector3(0, 2.1, d * 0.5 + 0.08),
			_glass_material)
	_build_batches()
	var shape := BoxShape3D.new()
	shape.size = Vector3(w, _height, d)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0, _height * 0.5, 0)
	add_child(col)


func _add_box(size: Vector3, pos: Vector3, material: StandardMaterial3D) -> void:
	# Accumulate boxes per material; _build_batches turns each material into a
	# single MultiMesh so a whole building costs three draw calls, not ~36.
	if not _batches.has(material):
		_batches[material] = []
	(_batches[material] as Array).append(Transform3D(Basis().scaled(size), pos))


func _build_batches() -> void:
	if _unit_box == null:
		_unit_box = BoxMesh.new()
		_unit_box.size = Vector3.ONE
	for material in _batches.keys():
		var xfs: Array = _batches[material]
		if xfs.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _unit_box
		mm.instance_count = xfs.size()
		for i in range(xfs.size()):
			mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = material
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mmi)
		_parts.append(mmi)
	_batches.clear()


func take_damage(amount: float, hit_position: Vector3 = Vector3.ZERO) -> void:
	if is_destroyed:
		return
	health -= amount
	if hit_position != Vector3.ZERO and health > 0.0:
		ExplosionScript.spark_burst(get_parent(), hit_position)
		CombatSfxScript.play_target_hit(get_parent(), hit_position, false, true)
	_flash()
	if health <= 0.0:
		_destroy()


func _flash() -> void:
	if _parts.is_empty():
		return
	if _flash_material == null:
		_flash_material = StandardMaterial3D.new()
		_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_flash_material.albedo_color = Color(1.0, 0.7, 0.3, 0.55)
	_flash_token += 1
	var token := _flash_token
	for part in _parts:
		if is_instance_valid(part):
			part.material_overlay = _flash_material
	var tree := get_tree()
	if tree == null or not is_inside_tree():
		return
	await tree.create_timer(0.08).timeout
	if not is_inside_tree() or not is_instance_valid(self) or is_destroyed or token != _flash_token:
		return
	for part in _parts:
		if is_instance_valid(part):
			part.material_overlay = null


func _destroy() -> void:
	is_destroyed = true
	remove_from_group("combat_target")
	collision_layer = 0
	collision_mask = 0
	var parent := get_parent()
	var centre := global_position + Vector3.UP * _height * 0.5
	if parent != null:
		ExplosionScript.spawn(parent, centre, 9.0, 0.0)
		ExplosionScript.fire_column(parent, global_position + Vector3.UP * 2.0, 12.0)
		ExplosionScript.smoke_column(parent, centre, 40.0)
		CombatSfxScript.play_boom(parent, global_position, 4.0, true, true)
		CombatSfxScript.play_hitmarker(parent, true, 0.5)
	_spawn_chunks(parent)
	for part in _parts:
		if is_instance_valid(part):
			part.queue_free()
	destroyed.emit(points)


func _spawn_chunks(parent: Node) -> void:
	if parent == null:
		return
	var tree := get_tree()
	if tree == null:
		return
	var chunk_material := _body_material
	var per_floor := 4
	for i in range(floors):
		for j in range(per_floor):
			var chunk := RigidBody3D.new()
			var size := Vector3(
					footprint.x / 2.6,
					6.5,
					footprint.z / 2.6)
			var mesh := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = size
			mesh.mesh = box
			mesh.material_override = chunk_material
			chunk.add_child(mesh)
			var shape := BoxShape3D.new()
			shape.size = size
			var col := CollisionShape3D.new()
			col.shape = shape
			chunk.add_child(col)
			parent.add_child(chunk)
			var y := 8.5 * (i + 0.5)
			chunk.global_position = global_position + Vector3(
					randf_range(-footprint.x * 0.3, footprint.x * 0.3), y,
					randf_range(-footprint.z * 0.3, footprint.z * 0.3))
			var dir := Vector3(randf_range(-1.0, 1.0), randf_range(0.4, 1.6),
					randf_range(-1.0, 1.0)).normalized()
			chunk.apply_central_impulse(dir * randf_range(40.0, 130.0))
			chunk.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-4, 4),
					randf_range(-4, 4))
			var timer := tree.create_timer(8.0)
			timer.timeout.connect(func() -> void:
				if is_instance_valid(chunk):
					chunk.queue_free())


const ExplosionScript = preload("res://combat/explosion.gd")
const CombatSfxScript = preload("res://combat/sfx.gd")
