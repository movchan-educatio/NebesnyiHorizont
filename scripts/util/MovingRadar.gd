class_name MovingRadar
extends Node3D

## High-performance active military Air Defense / Early Warning Radar station
## for the Steppe map. Features a 14m steel lattice mast, maintenance platform,
## an active 360-degree rotating parabolic radar scanner with feed horn,
## and a pulsing red hazard beacon.
## Zero FPS overhead (single transform rotation in _process).

@export var rotation_speed: float = 0.72 # rad/s (~6.9 RPM)

var _scanner_node: Node3D = null
var _beacon_mesh: MeshInstance3D = null
var _t: float = 0.0


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	if _scanner_node != null and is_instance_valid(_scanner_node):
		_scanner_node.rotation.y += delta * rotation_speed
		if _scanner_node.rotation.y > TAU:
			_scanner_node.rotation.y -= TAU

	# Flashing red aviation warning beacon on the mast apex
	if _beacon_mesh != null and is_instance_valid(_beacon_mesh):
		var mat := _beacon_mesh.material_override as StandardMaterial3D
		if mat != null:
			var flash := sin(_t * 5.0) > 0.15
			mat.emission_energy_multiplier = 3.5 if flash else 0.2


## Static factory creating a complete military radar installation.
static func create_radar(pos: Vector3, yaw: float = 0.0) -> Node3D:
	var script: GDScript = load("res://scripts/util/MovingRadar.gd") as GDScript
	var root: Node3D = script.new() as Node3D
	root.name = "MovingRadar"
	root.set_meta("no_batch", true)
	root.position = pos
	root.rotation.y = yaw

	var FT = load("res://scripts/util/frontline_terrain.gd")
	var concrete: Material = FT._pbr("concrete", Color(0.72, 0.70, 0.66), 0.32)
	var camo_green: Material = FT._pbr("steel", Color(0.24, 0.34, 0.22), 0.26)
	var steel_dark: Material = FT._pbr("steel", Color(0.30, 0.32, 0.34), 0.30)
	var steel_gray: Material = FT._pbr("steel", Color(0.55, 0.58, 0.60), 0.22)
	var rust: Material = FT._pbr("steel", Color(0.45, 0.28, 0.18), 0.35)

	# 1. Base Concrete Hardstand & Shelter Container
	var base_body := StaticBody3D.new()
	base_body.name = "RadarBaseBody"
	base_body.collision_layer = 1
	base_body.collision_mask = 1
	root.add_child(base_body)

	# Deep reinforced concrete octagon foundation plinth (6m deep to prevent floating on ridges)
	_add_cyl(base_body, 7.8, 6.0, Vector3(0.0, -2.2, 0.0), concrete, true)

	# Military hardware equipment shelter / electronics bunker
	_add_box(base_body, Vector3(4.8, 2.6, 3.2), Vector3(-3.2, 1.7, 0.0), camo_green, 0.0, true)
	# Air conditioning units on shelter roof
	_add_box(base_body, Vector3(1.4, 0.9, 1.2), Vector3(-3.2, 3.45, 0.0), steel_dark, 0.0, true)

	# Diesel generator trailer on side
	_add_box(base_body, Vector3(2.4, 1.6, 1.8), Vector3(3.8, 1.2, -2.5), camo_green, 0.2, true)
	_add_cyl(base_body, 0.12, 1.4, Vector3(4.4, 2.6, -2.5), rust, true)

	# 2. Lattice Tower Mast (13.5m tall steel lattice pyramid)
	var mast_h := 13.5
	var base_span := 2.2
	var top_span := 1.1

	for lx in [-1.0, 1.0]:
		for lz in [-1.0, 1.0]:
			var b_pos := Vector3(lx * base_span, 0.8, lz * base_span)
			var t_pos := Vector3(lx * top_span, mast_h + 0.8, lz * top_span)
			var mid_pos := (b_pos + t_pos) * 0.5
			var leg := _add_box(base_body, Vector3(0.24, mast_h, 0.24), mid_pos, camo_green, 0.0, true)
			leg.rotation.z = -lx * 0.08
			leg.rotation.x = lz * 0.08

	# Horizontal tie bars & diagonal cross bracings
	for stage in range(1, 5):
		var sy: float = 0.8 + float(stage) * 2.8
		var cur_span := lerpf(base_span, top_span, float(stage) / 5.0)
		for side in [-1.0, 1.0]:
			_add_box(base_body, Vector3(cur_span * 2.0, 0.15, 0.15),
					Vector3(0.0, sy, side * cur_span), camo_green, 0.0, false)
			_add_box(base_body, Vector3(0.15, 0.15, cur_span * 2.0),
					Vector3(side * cur_span, sy, 0.0), camo_green, 0.0, false)

	# Maintenance Platform with safety railing
	var plat_y := mast_h + 0.8
	_add_box(base_body, Vector3(top_span * 2.8, 0.16, top_span * 2.8),
			Vector3(0.0, plat_y, 0.0), steel_dark, 0.0, true)
	for rx in [-top_span * 1.35, top_span * 1.35]:
		_add_box(base_body, Vector3(0.08, 1.1, top_span * 2.8),
				Vector3(rx, plat_y + 0.55, 0.0), steel_gray, 0.0, false)
	for rz in [-top_span * 1.35, top_span * 1.35]:
		_add_box(base_body, Vector3(top_span * 2.8, 0.1, 0.08),
				Vector3(0.0, plat_y + 0.55, rz), steel_gray, 0.0, false)

	# 3. Rotating Radar Scanner Assembly (Pedestal + Parabolic Dish + Feed Horn)
	var scanner_root := Node3D.new()
	scanner_root.name = "RotatingScannerRoot"
	scanner_root.position = Vector3(0.0, plat_y + 0.1, 0.0)
	root.add_child(scanner_root)
	root._scanner_node = scanner_root

	# Pedestal rotary gear drive
	_add_cyl(scanner_root, 0.85, 1.2, Vector3(0.0, 0.6, 0.0), steel_dark, true)

	# Parabolic curved radar reflector (7.2m wide, curved mesh array)
	var dish_center_y := 2.6
	var dish_w := 7.4
	var dish_h := 2.6

	# Curved faceted dish panels (5 curved segments approximating parabolic curvature)
	for seg in range(-2, 3):
		var frac := float(seg) / 2.0
		var seg_x := frac * (dish_w * 0.42)
		var curve_z := -pow(frac, 2.0) * 0.85
		var seg_yaw := frac * 0.32
		_add_box(scanner_root, Vector3(dish_w * 0.22, dish_h, 0.12),
				Vector3(seg_x, dish_center_y, curve_z), camo_green, seg_yaw, true)

	# Dish rear truss support ribs
	_add_box(scanner_root, Vector3(dish_w * 0.85, 0.3, 0.3),
			Vector3(0.0, dish_center_y, -0.6), steel_dark, 0.0, false)
	_add_box(scanner_root, Vector3(dish_w * 0.85, 0.3, 0.3),
			Vector3(0.0, dish_center_y - 0.8, -0.4), steel_dark, 0.0, false)
	_add_box(scanner_root, Vector3(dish_w * 0.85, 0.3, 0.3),
			Vector3(0.0, dish_center_y + 0.8, -0.4), steel_dark, 0.0, false)

	# Forward cantilever feed horn boom & microwave collector
	_add_box(scanner_root, Vector3(0.18, 0.18, 2.4),
			Vector3(0.0, dish_center_y - 0.4, 1.2), steel_gray, 0.0, false)
	_add_box(scanner_root, Vector3(0.65, 0.55, 0.75),
			Vector3(0.0, dish_center_y, 2.3), steel_dark, 0.0, true)

	# Secondary IFF antenna array (Identification Friend or Foe bar atop dish)
	_add_box(scanner_root, Vector3(dish_w * 0.95, 0.35, 0.25),
			Vector3(0.0, dish_center_y + dish_h * 0.5 + 0.25, -0.2), camo_green, 0.0, false)

	# 4. Red Hazard Beacon atop mast center
	var beacon_mat := StandardMaterial3D.new()
	beacon_mat.albedo_color = Color(0.9, 0.1, 0.1)
	beacon_mat.emission_enabled = true
	beacon_mat.emission = Color(1.0, 0.15, 0.15)
	beacon_mat.emission_energy_multiplier = 3.5
	var beacon := _add_cyl(scanner_root, 0.16, 0.35,
			Vector3(0.0, dish_center_y + dish_h * 0.5 + 0.65, -0.2), beacon_mat, false)
	root._beacon_mesh = beacon

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
