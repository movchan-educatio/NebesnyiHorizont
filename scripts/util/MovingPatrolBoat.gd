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
	root.waypoints = wps
	root.water_level_y = water_y
	if not wps.is_empty():
		root.position = wps[0]
	root.rotation.y = yaw

	var FT = load("res://scripts/util/frontline_terrain.gd")
	var camo_hull: Material = FT._pbr("steel", Color(0.28, 0.35, 0.30), 0.28) # Olive-gray naval camo
	var deck_dark: Material = FT._pbr("steel", Color(0.22, 0.24, 0.25), 0.35)
	var superstructure: Material = FT._pbr("steel", Color(0.38, 0.42, 0.40), 0.26)
	var weapon_mat: Material = FT._pbr("steel", Color(0.18, 0.19, 0.20), 0.22)
	var glass_mat: Material = FT._mat(Color(0.04, 0.08, 0.10), 0.15, 0.35)
	var wake_mat: Material = FT._mat(Color(0.90, 0.95, 0.98), 0.60, 0.85)

	# 1. Boat Static/Animatable Body for Collision
	var boat_body := AnimatableBody3D.new()
	boat_body.name = "BoatBody"
	boat_body.collision_layer = 1
	boat_body.collision_mask = 1
	boat_body.sync_to_physics = false
	root.add_child(boat_body)

	# Hull dimensions: 15.6m long, 3.8m beam, 1.8m depth
	var length := 15.6
	var beam := 3.8

	# Main lower hull
	_add_box(boat_body, Vector3(beam, 1.4, length * 0.72),
			Vector3(0.0, 0.2, -length * 0.05), camo_hull, 0.0, true)

	# Tapered bow wedge
	_add_prism(boat_body, Vector3(beam, 1.4, length * 0.28),
			Vector3(0.0, 0.2, length * 0.45), camo_hull, PI, true)

	# Upper teak / non-slip deck
	_add_box(boat_body, Vector3(beam - 0.2, 0.12, length * 0.96),
			Vector3(0.0, 0.95, 0.0), deck_dark, 0.0, true)

	# Deck bulwarks / gunwales along edges
	for side in [-1.0, 1.0]:
		_add_box(boat_body, Vector3(0.12, 0.65, length * 0.85),
				Vector3(side * (beam * 0.5 - 0.08), 1.25, -length * 0.05), camo_hull, 0.0, false)

	# 2. Armored Pilothouse / Bridge (Midship)
	var bridge := _add_box(boat_body, Vector3(2.6, 1.9, 4.2),
			Vector3(0.0, 1.9, -0.6), superstructure, 0.0, true)

	# Bridge windows (forward, sides)
	_add_box(bridge, Vector3(2.3, 0.65, 0.1),
			Vector3(0.0, 0.35, 2.15), glass_mat, 0.0, false)
	for side in [-1.0, 1.0]:
		_add_box(bridge, Vector3(0.1, 0.65, 2.4),
				Vector3(side * 1.35, 0.35, 0.2), glass_mat, 0.0, false)

	# 3. Forward Armored Remote Weapon Turret (Bow 30mm Autocannon)
	var turret_mount := _add_cyl(boat_body, 0.95, 0.65,
			Vector3(0.0, 1.3, length * 0.26), weapon_mat, true)
	var turret_housing := _add_box(boat_body, Vector3(1.4, 0.9, 1.6),
			Vector3(0.0, 1.85, length * 0.26), weapon_mat, 0.0, true)
	# Dual 30mm gun barrels
	for gx in [-0.15, 0.15]:
		_add_cyl(boat_body, 0.06, 2.4,
				Vector3(gx, 1.95, length * 0.26 + 1.6), weapon_mat, false, Vector3(PI * 0.5, 0.0, 0.0))

	# 4. Mast with Rotating Radar Scanner
	var mast_y := 2.85
	_add_cyl(boat_body, 0.12, 3.2,
			Vector3(0.0, mast_y + 1.6, -1.2), superstructure, false)
	# Cross yardarm with navigation lights
	_add_box(boat_body, Vector3(1.8, 0.08, 0.08),
			Vector3(0.0, mast_y + 2.4, -1.2), superstructure, 0.0, false)

	# Rotating radar scanner bar atop mast
	var radar := Node3D.new()
	radar.name = "BoatRadarScanner"
	radar.position = Vector3(0.0, mast_y + 3.3, -1.2)
	boat_body.add_child(radar)
	root._radar_antenna = radar

	_add_box(radar, Vector3(1.4, 0.18, 0.22), Vector3.ZERO, weapon_mat, 0.0, false)

	# 5. Stern Transom, Outboard Drives, and Wake Trails
	_add_box(boat_body, Vector3(2.4, 0.9, 0.8),
			Vector3(0.0, 0.55, -length * 0.48), camo_hull, 0.0, true)

	# Twin foam wake planes trailing behind boat
	for side in [-1.0, 1.0]:
		var wake := _add_box(root, Vector3(1.2, 0.04, 7.5),
				Vector3(side * 1.5, 0.02, -length * 0.5 - 3.8), wake_mat, side * 0.12, false)

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
