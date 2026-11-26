extends ProceduralGate
class_name ProceduralGateTorus


@export var inner_radius := 1.5
@export var outer_radius := 2.0
@export var sides := 32
@export var ring_sides := 16
@export var collision_shape_count := 16


var _face_mat: StandardMaterial3D = null
var _glow_mat: StandardMaterial3D = null
var _blink_t: float = 0.0


func _process(delta: float) -> void:
	_blink_t += delta * 7.2
	if _face_mat != null:
		var st := 0 if (checkpoint != null and checkpoint.active) else 2
		FreestyleCourse.apply_gate_blink(_face_mat, _glow_mat, _blink_t, st, 0)


func _add_geometry() -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = FreestyleCourse.build_horizon_gate_mesh(1.0, false)
	mi.scale = Vector3.ONE * inner_radius
	_face_mat = FreestyleCourse.create_horizon_face_material(FreestyleCourse.GATE_PINK)
	mi.set_surface_override_material(0, FreestyleCourse.create_horizon_bezel_material())
	mi.set_surface_override_material(1, _face_mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	geometry = mi
	add_child(mi)
	var glow := MeshInstance3D.new()
	glow.mesh = FreestyleCourse.build_horizon_halo_mesh(1.0, false)
	glow.scale = Vector3.ONE * inner_radius
	_glow_mat = FreestyleCourse._glow_material(FreestyleCourse.GATE_PINK_HOT)
	glow.material_override = _glow_mat
	glow.visible = false
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glow)


func _add_collision() -> void:
	if static_body.get_child_count() > 0:
		for child in static_body.get_children():
			static_body.remove_child(child)
			child.queue_free()
	# Add capsule collision shapes
	var shape := CapsuleShape3D.new()
	shape.radius = (outer_radius - inner_radius) / 2.0
	var offset := inner_radius + shape.radius
	var length := 2 * PI * offset / collision_shape_count
	shape.height = length
	for i in range(collision_shape_count):
		var collision_shape := CollisionShape3D.new()
		collision_shape.shape = shape
		static_body.add_child(collision_shape)
		collision_shape.rotate_y(2 * PI * i / collision_shape_count)
		collision_shape.translate_object_local(Vector3(offset, 0, 0))
	static_body.rotate(Vector3.RIGHT, PI / 2.0)


func _add_checkpoint() -> void:
	var shape := CylinderShape3D.new()
	shape.height = 0.05
	shape.radius = inner_radius
	var collision := CollisionShape3D.new()
	collision.shape = shape
	checkpoint.add_child(collision)
	collision.rotate(Vector3.RIGHT, PI / 2.0)
