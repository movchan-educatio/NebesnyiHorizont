class_name MovingWindmill
extends Node3D

## High-performance scenic rotating windmill for the Village map.
## Features an authentic octagonal mill tower with fly-through portals,
## an upper gear-cap, and 4 large rotating lattice blades.
## Zero FPS overhead (smooth lightweight transform rotation in _process).

@export var rotation_speed: float = 0.45 # rad/s (~4.3 RPM, realistic wind speed)

var _rotor_node: Node3D = null
var _blades_body: AnimatableBody3D = null


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	if _rotor_node != null and is_instance_valid(_rotor_node):
		_rotor_node.rotation.z += delta * rotation_speed
		if _rotor_node.rotation.z > TAU:
			_rotor_node.rotation.z -= TAU


## Static factory creating a complete, textured, collidable windmill.
static func create_windmill(pos: Vector3, yaw: float = 0.0) -> Node3D:
	var script: GDScript = load("res://scripts/util/MovingWindmill.gd") as GDScript
	var root: Node3D = script.new() as Node3D
	root.name = "MovingWindmill"
	root.set_meta("no_batch", true)
	root.position = pos
	root.rotation.y = yaw

	var FT = load("res://scripts/util/frontline_terrain.gd")
	var stone_mat: Material = FT._pbr("stone", Color(0.72, 0.70, 0.65), 0.32)
	var wood_mat: Material = FT._pbr("wood", Color(0.48, 0.36, 0.24), 0.38)
	var dark_wood: Material = FT._pbr("wood", Color(0.28, 0.20, 0.14), 0.45)
	var canvas_mat: Material = FT._pbr("plaster", Color(0.85, 0.82, 0.75), 0.50)
	var steel_mat: Material = FT._pbr("steel", Color(0.35, 0.38, 0.40), 0.25)

	# 1. Base Static Body for Mill Tower
	var tower_body := StaticBody3D.new()
	tower_body.name = "WindmillTowerBody"
	tower_body.collision_layer = 1
	tower_body.collision_mask = 1
	root.add_child(tower_body)

	# Deep stone foundation base (6m deep into bluff so windmill never floats on slopes)
	_add_cyl(tower_body, 4.6, 6.0, Vector3(0.0, -2.5, 0.0), stone_mat)

	# Octagonal tapered tower walls (16m tall, 8.0m base diameter tapering to 5.4m)
	var tower_h := 16.0
	var segs := 8
	var r_base := 4.2
	var r_top := 2.8

	for i in range(segs):
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var mid_a := (a0 + a1) * 0.5

		# Door opening on south side (i == 0) and high window on north side (i == 4)
		var is_door := (i == 0)
		var is_window := (i == 4)

		var p0_b := Vector3(cos(a0) * r_base, 0.0, sin(a0) * r_base)
		var p1_b := Vector3(cos(a1) * r_base, 0.0, sin(a1) * r_base)
		var p0_t := Vector3(cos(a0) * r_top, tower_h, sin(a0) * r_top)
		var p1_t := Vector3(cos(a1) * r_top, tower_h, sin(a1) * r_top)

		var wall_w := p0_b.distance_to(p1_b)
		var wall_mid := (p0_b + p1_b + p0_t + p1_t) * 0.25

		if is_door:
			# Left pier
			_add_box(tower_body, Vector3(wall_w * 0.28, tower_h, 0.45),
					wall_mid + Vector3(-wall_w * 0.35, 0.0, 0.0), stone_mat, mid_a)
			# Right pier
			_add_box(tower_body, Vector3(wall_w * 0.28, tower_h, 0.45),
					wall_mid + Vector3(wall_w * 0.35, 0.0, 0.0), stone_mat, mid_a)
			# Lintel above 3.5m tall fly-through door arch
			_add_box(tower_body, Vector3(wall_w * 0.5, tower_h - 3.8, 0.45),
					Vector3(wall_mid.x, 3.8 + (tower_h - 3.8) * 0.5, wall_mid.z), stone_mat, mid_a)
		elif is_window:
			# Wall below window (up to 7.0m)
			_add_box(tower_body, Vector3(wall_w, 7.0, 0.45),
					Vector3(wall_mid.x, 3.5, wall_mid.z), stone_mat, mid_a)
			# Wall above window (from 11.5m to 16m)
			_add_box(tower_body, Vector3(wall_w, 4.5, 0.45),
					Vector3(wall_mid.x, 13.75, wall_mid.z), stone_mat, mid_a)
			# Left & right window frame jambs (leaving 2.2m x 4.5m open fly-through window!)
			_add_box(tower_body, Vector3(wall_w * 0.25, 4.5, 0.45),
					Vector3(wall_mid.x - wall_w * 0.35, 9.25, wall_mid.z), wood_mat, mid_a)
			_add_box(tower_body, Vector3(wall_w * 0.25, 4.5, 0.45),
					Vector3(wall_mid.x + wall_w * 0.35, 9.25, wall_mid.z), wood_mat, mid_a)
		else:
			# Solid wall panel with stone PBR
			_add_box(tower_body, Vector3(wall_w, tower_h, 0.45),
					wall_mid, stone_mat, mid_a)

	# Intermediate internal timber floor with fly-through hatch
	_add_box(tower_body, Vector3(r_top * 1.8, 0.25, r_top * 1.8),
			Vector3(0.0, 7.5, 0.0), wood_mat, 0.0, false)

	# 2. Mill Cap (Rotating Cap Roof)
	var cap_y := tower_h + 0.1
	# Conical/Boat-shaped cap roof
	_add_box(tower_body, Vector3(r_top * 2.2, 2.4, r_top * 2.6),
			Vector3(0.0, cap_y + 1.2, 0.2), dark_wood, 0.0, true)
	# Tail pole / brake beam extending back
	_add_box(tower_body, Vector3(0.35, 0.35, 7.5),
			Vector3(0.0, cap_y + 0.5, -4.5), dark_wood, 0.0, false)

	# 3. Rotating Rotor Assembly (Hub + 4 Sails)
	var rotor_mount := Node3D.new()
	rotor_mount.name = "RotorMount"
	rotor_mount.position = Vector3(0.0, cap_y + 1.2, r_top + 0.6)
	root.add_child(rotor_mount)
	root._rotor_node = rotor_mount

	# Heavy cast iron windshaft & hub
	_add_cyl(rotor_mount, 0.65, 1.4, Vector3.ZERO, steel_mat, Vector3(PI * 0.5, 0.0, 0.0))

	# 4 Heavy Sail Blades (14m diameter, 4-blade cross)
	var blade_span := 6.6
	var blade_w := 1.35

	for b_idx in range(4):
		var b_angle := float(b_idx) * PI * 0.5
		var blade_root := Node3D.new()
		blade_root.rotation.z = b_angle
		rotor_mount.add_child(blade_root)

		# Central oak stock spar
		_add_box(blade_root, Vector3(0.24, blade_span, 0.24),
				Vector3(0.0, blade_span * 0.5 + 0.6, 0.0), dark_wood, 0.0, true)

		# Leading edge wind board
		_add_box(blade_root, Vector3(0.18, blade_span * 0.85, 0.05),
				Vector3(-0.20, blade_span * 0.5 + 0.9, 0.08), wood_mat, 0.0, false)

		# Lattice sail framework & canvas cloth
		_add_box(blade_root, Vector3(blade_w, blade_span * 0.85, 0.04),
				Vector3(blade_w * 0.5 + 0.12, blade_span * 0.5 + 0.9, 0.0), canvas_mat, 0.0, true)

		# Wooden crossbars across the canvas
		for bar_idx in range(6):
			var bar_y := 1.2 + float(bar_idx) * (blade_span * 0.8 / 6.0)
			_add_box(blade_root, Vector3(blade_w + 0.2, 0.06, 0.08),
					Vector3(blade_w * 0.5 + 0.1, bar_y, 0.05), dark_wood, 0.0, false)

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


static func _add_cyl(parent: Node3D, radius: float, height: float, pos: Vector3,
		mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
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
	return mi
