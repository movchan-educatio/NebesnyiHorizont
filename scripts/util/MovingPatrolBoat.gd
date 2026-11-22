class_name MovingPatrolBoat
extends Node3D

## High-performance active Military River Patrol Boat for Wetlands and Village maps.
## Features an armored hull, forward weapon turret, pilothouse, communication
## mast with rotating navigation radar, and twin stern wake meshes.
## Smoothly navigates along a scenic river patrol loop with zero FPS overhead.

@export var waypoints: Array[Vector3] = []
@export var speed: float = 4.8 # m/s (~17 km/h river patrol speed)
@export var water_level_y: float = 0.0

var _cur_idx: int = 0
var _t_param: float = 0.0
var _radar_antenna: Node3D = null
var _wake_left: MeshInstance3D = null
var _wake_right: MeshInstance3D = null
var _t: float = 0.0


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	_t += delta

	# Spin the top mast navigation radar antenna
	if _radar_antenna != null and is_instance_valid(_radar_antenna):
		_radar_antenna.rotation.y += delta * 3.5

	# Waypoint navigation along the water channel
	if waypoints.size() < 2:
		return

	var p0 := waypoints[_cur_idx]
	var next_idx := (_cur_idx + 1) % waypoints.size()
	var p1 := waypoints[next_idx]

	var seg_vec := p1 - p0
	var seg_len := seg_vec.length()
	if seg_len < 0.01:
		_cur_idx = next_idx
		return

	_t_param += (speed * delta) / seg_len
	if _t_param >= 1.0:
		_t_param -= 1.0
		_cur_idx = next_idx
		p0 = waypoints[_cur_idx]
		next_idx = (_cur_idx + 1) % waypoints.size()
		p1 = waypoints[next_idx]
		seg_vec = p1 - p0

	var cur_pos := p0.lerp(p1, _t_param)
	# Gentle wave bobbing & roll
	var bob := sin(_t * 2.2) * 0.08
	var roll := sin(_t * 1.7) * 0.035
	position = Vector3(cur_pos.x, water_level_y + bob, cur_pos.z)

	var target_yaw := atan2(seg_vec.x, seg_vec.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, delta * 2.5)
	rotation.z = roll


## Static factory creating a complete military river patrol boat.
static func create_patrol_boat(wps: Array[Vector3], water_y: float, yaw: float = 0.0) -> Node3D:
	var script: GDScript = load("res://scripts/util/MovingPatrolBoat.gd") as GDScript
	var root: Node3D = script.new() as Node3D
	root.name = "MovingPatrolBoat"
	var clamped_wps: Array[Vector3] = []
	for wp in wps:
		clamped_wps.append(Vector3(clampf(wp.x, -178.0, 178.0), wp.y, clampf(wp.z, -178.0, 178.0)))
	root.waypoints = clamped_wps
	root.water_level_y = water_y
	if not clamped_wps.is_empty():
		root.position = clamped_wps[0]
	root.rotation.y = yaw

	var FT = load("res://scripts/util/frontline_terrain.gd")
	var camo_hull: Material = FT._pbr("hall_metal", Color(0.28, 0.35, 0.30), 0.28)
	var weapon_mat: Material = FT._pbr("hall_metal", Color(0.18, 0.19, 0.20), 0.22)

	# 1. Boat Static/Animatable Body for Collision
	var boat_body := AnimatableBody3D.new()
	boat_body.name = "BoatBody"
	boat_body.collision_layer = 1
	boat_body.collision_mask = 1
	boat_body.sync_to_physics = false
	root.add_child(boat_body)

	var length := 15.6
	var beam := 3.8
	var sculpted_hull: Mesh = FT._get_shared_landmark_mesh("PatrolBoatHull") if FT.has_method("_get_shared_landmark_mesh") else null
	if sculpted_hull != null:
		var hull_pbr := FT._pbr("hall_metal", Color.WHITE, 0.32) as StandardMaterial3D
		var hull_mat := hull_pbr.duplicate() as StandardMaterial3D if hull_pbr != null else StandardMaterial3D.new()
		hull_mat.albedo_texture = null
		hull_mat.albedo_color = Color(1.06, 1.06, 1.04)
		hull_mat.uv1_triplanar = true
		hull_mat.uv1_world_triplanar = true
		hull_mat.vertex_color_use_as_albedo = true
		hull_mat.roughness = 0.68
		hull_mat.metallic = 0.24
		var hull_mi := MeshInstance3D.new()
		hull_mi.name = "SculptedPatrolBoatHull"
		hull_mi.mesh = sculpted_hull
		hull_mi.material_override = hull_mat
		hull_mi.scale = Vector3(1.42, 1.42, 1.48)
		hull_mi.position = Vector3(0.0, -0.35, 0.0)
		hull_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		hull_mi.set_meta("no_batch", true)
		boat_body.add_child(hull_mi)
		var cs := CollisionShape3D.new()
		var bshape := BoxShape3D.new()
		bshape.size = Vector3(beam, 2.6, length)
		cs.shape = bshape
		cs.position = Vector3(0.0, 1.1, 0.0)
		boat_body.add_child(cs)
	else:
		_add_box(boat_body, Vector3(beam, 1.4, length * 0.72),
				Vector3(0.0, 0.2, -length * 0.05), camo_hull, 0.0, true)

	# Rotating radar scanner bar atop mast
	var radar := Node3D.new()
	radar.name = "BoatRadarScanner"
	radar.position = Vector3(0.0, 4.45, -0.5)
	boat_body.add_child(radar)
	root._radar_antenna = radar
	_add_box(radar, Vector3(1.4, 0.18, 0.22), Vector3.ZERO, weapon_mat, 0.0, false)

	# Translucent feathered foam wake trails behind stern (replacing opaque white boxes)
	var wake_grad := Gradient.new()
	wake_grad.colors = PackedColorArray([
		Color(0.92, 0.96, 0.98, 0.0),
		Color(0.92, 0.96, 0.98, 0.34),
		Color(0.88, 0.94, 0.96, 0.14),
		Color(0.85, 0.92, 0.95, 0.0),
	])
	wake_grad.offsets = PackedFloat32Array([0.0, 0.22, 0.65, 1.0])
	var wake_tex := GradientTexture2D.new()
	wake_tex.gradient = wake_grad
	wake_tex.fill = GradientTexture2D.FILL_RADIAL
	wake_tex.fill_from = Vector2(0.5, 0.25)
	wake_tex.fill_to = Vector2(0.5, 1.0)
	var wake_mat := StandardMaterial3D.new()
	wake_mat.albedo_texture = wake_tex
	wake_mat.albedo_color = Color(0.92, 0.96, 0.98, 0.42)
	wake_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wake_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wake_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	wake_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	for side in [-1.0, 1.0]:
		var wake_q := QuadMesh.new()
		wake_q.size = Vector2(1.8, 8.5)
		var wake_mi := MeshInstance3D.new()
		wake_mi.mesh = wake_q
		wake_mi.material_override = wake_mat
		wake_mi.position = Vector3(side * 1.45, 0.04, -length * 0.5 - 3.6)
		wake_mi.rotation = Vector3(-PI * 0.5, side * 0.14, 0.0)
		wake_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wake_mi.set_meta("no_batch", true)
		root.add_child(wake_mi)

	return root


static func _add_box(parent: Node3D, size: Vector3, pos: Vector3,
		mat: Material, yaw: float = 0.0, col: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = yaw
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	if col:
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		cs.position = pos
		cs.rotation.y = yaw
		parent.add_child(cs)
	return mi


static func _add_prism(parent: Node3D, size: Vector3, pos: Vector3,
		mat: Material, yaw: float = 0.0, col: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = size
	mi.mesh = prism
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = yaw
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	if col:
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size * 0.85
		cs.shape = shape
		cs.position = pos
		cs.rotation.y = yaw
		parent.add_child(cs)
	return mi


static func _add_cyl(parent: Node3D, radius: float, height: float, pos: Vector3,
		mat: Material, col: bool = false, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 16
	mi.mesh = cyl
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	if col:
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = height
		cs.shape = shape
		cs.position = pos
		cs.rotation = rot
		parent.add_child(cs)
	return mi
