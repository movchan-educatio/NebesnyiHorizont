class_name MovingCrane
extends Node3D

## High-performance dynamic rail-mounted gantry crane and rotating tower crane
## for the Industrial map.
##
## Provides live kinetic movement in the world without any FPS degradation.
## Physics collision is fully functional so drones can land on, dive through,
## or collide with moving elements.

enum CraneType {
	GANTRY_RAIL,
	ROTATING_TOWER,
}

@export var crane_type: CraneType = CraneType.GANTRY_RAIL
@export var travel_distance: float = 64.0
@export var travel_speed: float = 3.2
@export var jib_rotation_speed: float = 0.06

var _t: float = 0.0
var _gantry_body: AnimatableBody3D = null
var _trolley_node: Node3D = null
var _spreader_node: Node3D = null
var _beacon_mesh: MeshInstance3D = null
var _tower_jib: AnimatableBody3D = null
var _cable_mesh: MeshInstance3D = null
var _initial_pos := Vector3.ZERO
var _cur_pos_x := 0.0
var _vel_x := 0.0


func _ready() -> void:
	_initial_pos = position
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	# Flashing amber warning beacon
	if _beacon_mesh != null and is_instance_valid(_beacon_mesh):
		var mat := _beacon_mesh.material_override as StandardMaterial3D
		if mat != null:
			var flash := sin(_t * 8.0) > 0.1
			mat.emission_energy_multiplier = 4.0 if flash else 0.2

	if crane_type == CraneType.GANTRY_RAIL:
		_process_gantry(delta)
	elif crane_type == CraneType.ROTATING_TOWER:
		_process_tower(delta)


func _process_gantry(delta: float) -> void:
	if _gantry_body == null or not is_instance_valid(_gantry_body):
		return
	# Smooth sinusoidal back-and-forth travel along the track
	var travel_cycle := sin(_t * (travel_speed / maxf(travel_distance, 1.0)))
	var target_x := travel_cycle * (travel_distance * 0.5)
	_vel_x = (target_x - _cur_pos_x) / maxf(delta, 0.001)
	_cur_pos_x = target_x
	_gantry_body.position.x = _cur_pos_x

	# Trolley traverse across the bridge beam
	if _trolley_node != null and is_instance_valid(_trolley_node):
		var trolley_z := sin(_t * 0.45) * 11.0
		_trolley_node.position.z = trolley_z

	# Suspended load pendulum sway reacting to crane acceleration
	if _spreader_node != null and is_instance_valid(_spreader_node):
		var sway_z := sin(_t * 1.8) * 0.08
		var sway_x := clampf(-_vel_x * 0.035 + sin(_t * 1.4) * 0.06, -0.22, 0.22)
		_spreader_node.rotation.z = sway_x
		_spreader_node.rotation.x = sway_z


func _process_tower(delta: float) -> void:
	if _tower_jib == null or not is_instance_valid(_tower_jib):
		return
	# Smooth slow 360-degree rotation of upper slewing unit
	_tower_jib.rotation.y += delta * jib_rotation_speed
	if _tower_jib.rotation.y > TAU:
		_tower_jib.rotation.y -= TAU

	# Trolley moving along the jib
	if _trolley_node != null and is_instance_valid(_trolley_node):
		var t_dist := 12.0 + (sin(_t * 0.32) * 0.5 + 0.5) * 22.0
		_trolley_node.position.z = -t_dist

	# Swaying suspended skip / hook block
	if _spreader_node != null and is_instance_valid(_spreader_node):
		var sway := sin(_t * 1.6) * 0.07
		_spreader_node.rotation.x = sway
		_spreader_node.rotation.z = sin(_t * 1.3) * 0.05


## Builds a heavy rail-mounted industrial container gantry crane.
static func create_gantry_crane(pos: Vector3, yaw: float, travel_len: float = 70.0) -> Node3D:
	var script: GDScript = load("res://scripts/util/moving_crane.gd") as GDScript
	var root: Node3D = script.new() as Node3D
	root.name = "MovingGantryCrane"
	root.crane_type = CraneType.GANTRY_RAIL
	root.travel_distance = travel_len
	root.position = pos
	root.rotation.y = yaw

	var steel_yellow := _pbr_mat(Color(0.88, 0.62, 0.12), 0.55, 0.35)
	var steel_dark := _pbr_mat(Color(0.24, 0.26, 0.28), 0.70, 0.40)
	var steel_rust := _pbr_mat(Color(0.42, 0.25, 0.18), 0.85, 0.10)
	var concrete_mat := _pbr_mat(Color(0.58, 0.56, 0.52), 0.92, 0.0)
	var beacon_mat := _beacon_material()

	var rail_z := 15.0
	# 1. Ground rails and deep concrete track bed foundations
	for rz in [-rail_z, rail_z]:
		# Concrete foundation sleeper strip (4.5m deep to anchor on slopes)
		_add_box(root, Vector3(travel_len + 12.0, 4.5, 2.2),
				Vector3(0.0, -1.8, rz), concrete_mat, true)
		# Steel rail tracks
		for roff in [-0.55, 0.55]:
			_add_box(root, Vector3(travel_len + 10.0, 0.22, 0.16),
					Vector3(0.0, 0.5, rz + roff), steel_rust, false)
		# Rail buffer end stops
		for rx in [-(travel_len * 0.5 + 4.0), travel_len * 0.5 + 4.0]:
			_add_box(root, Vector3(1.2, 1.4, 1.6),
					Vector3(rx, 0.9, rz), steel_yellow, true)

	# 2. Moving Gantry Body (AnimatableBody3D for physics collision)
	var gantry := AnimatableBody3D.new()
	gantry.name = "GantryCarrier"
	gantry.collision_layer = 1
	gantry.collision_mask = 1
	gantry.sync_to_physics = false
	root.add_child(gantry)
	root._gantry_body = gantry

	var span_w := rail_z * 2.0
	var leg_h := 18.0

	# 4 Heavy wheeled bogies
	for rz in [-rail_z, rail_z]:
		var bogie := _add_box(gantry, Vector3(6.4, 1.1, 1.5),
				Vector3(0.0, 0.8, rz), steel_dark, true)
		# Wheel cylinders
		for wx in [-2.4, -0.8, 0.8, 2.4]:
			_add_cyl(bogie, 0.45, 0.28, Vector3(wx, -0.15, 0.0),
					steel_dark, Vector3(PI * 0.5, 0.0, 0.0))

	# 4 Angled A-frame legs
	var leg_thick := 0.65
	for rz_val in [-1.0, 1.0]:
		var rz_sign: float = float(rz_val)
		var leg_z: float = rail_z * rz_sign
		for rx_val in [-1.0, 1.0]:
			var rx_sign: float = float(rx_val)
			var lx: float = rx_sign * 2.0
			var top_x: float = rx_sign * 0.8
			var top_z: float = leg_z - rz_sign * 1.5
			var mid_x: float = (lx + top_x) * 0.5
			var mid_z: float = (leg_z + top_z) * 0.5
			var mid_y: float = leg_h * 0.5 + 1.0
			var leg := _add_box(gantry, Vector3(leg_thick, leg_h, leg_thick),
					Vector3(mid_x, mid_y, mid_z), steel_yellow, true)
			leg.rotation.z = -rx_sign * 0.07
			leg.rotation.x = rz_sign * 0.08
		# Horizontal leg tie beam
		_add_box(gantry, Vector3(4.2, 0.5, 0.5),
				Vector3(0.0, 6.0, leg_z - rz_sign * 0.6), steel_yellow, true)
		_add_box(gantry, Vector3(3.2, 0.5, 0.5),
				Vector3(0.0, 12.0, leg_z - rz_sign * 1.1), steel_yellow, true)

	# Main Overhead Box Girders (Twin parallel beams spanning 32m)
	var beam_len := span_w + 5.0
	var beam_y := leg_h + 1.4
	for bx in [-1.1, 1.1]:
		_add_box(gantry, Vector3(0.7, 1.8, beam_len),
				Vector3(bx, beam_y, 0.0), steel_yellow, true)
	# Upper maintenance walkway with grating
	_add_box(gantry, Vector3(2.6, 0.12, beam_len),
			Vector3(0.0, beam_y + 1.0, 0.0), steel_dark, true)
	# Walkway handrails
	for sx in [-1.35, 1.35]:
		_add_box(gantry, Vector3(0.08, 1.1, beam_len),
				Vector3(sx, beam_y + 1.55, 0.0), steel_yellow, false)

	# Operator Cab under the bridge
	var cab := _add_box(gantry, Vector3(3.0, 2.4, 2.6),
			Vector3(0.0, beam_y - 1.8, -span_w * 0.5 + 4.0), steel_yellow, true)
	# Cab windows
	_add_box(cab, Vector3(2.2, 1.2, 0.1),
			Vector3(0.0, 0.2, 1.35), _glass_mat(), false)

	# Amber warning beacons on top corners
	for corner in [
		Vector3(-1.3, beam_y + 2.2, beam_len * 0.5 - 0.4),
		Vector3(1.3, beam_y + 2.2, beam_len * 0.5 - 0.4),
		Vector3(-1.3, beam_y + 2.2, -beam_len * 0.5 + 0.4),
		Vector3(1.3, beam_y + 2.2, -beam_len * 0.5 + 0.4)
	]:
		var b_cyl := _add_cyl(gantry, 0.18, 0.35, corner, beacon_mat)
		if root._beacon_mesh == null:
			root._beacon_mesh = b_cyl

	# 3. Trolley Crab that rolls across the bridge
	var trolley := Node3D.new()
	trolley.name = "CrabTrolley"
	trolley.position = Vector3(0.0, beam_y + 1.25, 0.0)
	gantry.add_child(trolley)
	root._trolley_node = trolley
	_add_box(trolley, Vector3(2.6, 0.7, 2.8), Vector3.ZERO, steel_dark, true)

	# 4. Suspended Spreader Bar & Container
	var hoist_y := -9.5
	var hoist_rig := Node3D.new()
	hoist_rig.name = "HoistRig"
	hoist_rig.position = Vector3(0.0, 0.0, 0.0)
	trolley.add_child(hoist_rig)
	root._spreader_node = hoist_rig

	# 4 Steel hoist cables
	for cx in [-0.9, 0.9]:
		for cz in [-1.1, 1.1]:
			_add_cyl(hoist_rig, 0.035, absf(hoist_y),
					Vector3(cx, hoist_y * 0.5, cz), steel_dark)

	# Container spreader frame
	var spreader := _add_box(hoist_rig, Vector3(2.6, 0.45, 6.2),
			Vector3(0.0, hoist_y, 0.0), steel_yellow, true)
	# Suspended 20ft military/cargo container
	var cont_mat := _pbr_mat(Color(0.20, 0.38, 0.22), 0.65, 0.15) # Military olive drab
	_add_box(spreader, Vector3(2.4, 2.6, 6.0),
			Vector3(0.0, -1.5, 0.0), cont_mat, true)

	return root


## Builds a high-altitude construction tower crane with rotating jib.
static func create_rotating_tower_crane(pos: Vector3, yaw: float) -> Node3D:
	var script: GDScript = load("res://scripts/util/moving_crane.gd") as GDScript
	var root: Node3D = script.new() as Node3D
	root.name = "RotatingTowerCrane"
	root.crane_type = CraneType.ROTATING_TOWER
	root.position = pos
	root.rotation.y = yaw

	var steel_yellow := _pbr_mat(Color(0.92, 0.65, 0.08), 0.55, 0.35)
	var steel_dark := _pbr_mat(Color(0.20, 0.22, 0.24), 0.70, 0.40)
	var crane_concrete := _pbr_mat(Color(0.55, 0.54, 0.52), 0.94, 0.0)
	var beacon_mat := _beacon_material()

	# 1. Foundation Slab (Deep 6.5m concrete pier embedded in terrain)
	_add_box(root, Vector3(12.5, 6.5, 12.5), Vector3(0.0, -1.6, 0.0), crane_concrete, true)
	_add_box(root, Vector3(8.0, 1.0, 8.0), Vector3(0.0, 2.1, 0.0), crane_concrete, true)

	# 2. Lattice Mast (42m tall square tower)
	var mast_h := 42.0
	var leg_w := 0.32
	var mast_span := 1.4
	for lx in [-mast_span, mast_span]:
		for lz in [-mast_span, mast_span]:
			_add_box(root, Vector3(leg_w, mast_h, leg_w),
					Vector3(lx, mast_h * 0.5 + 2.5, lz), steel_yellow, true)
	# Mast cross lacings every 4m
	for mi in range(1, int(mast_h / 4.0)):
		var my := 2.5 + float(mi) * 4.0
		_add_box(root, Vector3(mast_span * 2.0, 0.2, 0.2),
				Vector3(0.0, my, mast_span), steel_yellow, false)
		_add_box(root, Vector3(mast_span * 2.0, 0.2, 0.2),
				Vector3(0.0, my, -mast_span), steel_yellow, false)
		_add_box(root, Vector3(0.2, 0.2, mast_span * 2.0),
				Vector3(mast_span, my, 0.0), steel_yellow, false)
		_add_box(root, Vector3(0.2, 0.2, mast_span * 2.0),
				Vector3(-mast_span, my, 0.0), steel_yellow, false)

	# 3. Upper Slewing Unit & Rotating Jib (AnimatableBody3D)
	var slewing := AnimatableBody3D.new()
	slewing.name = "SlewingJib"
	slewing.position = Vector3(0.0, mast_h + 2.6, 0.0)
	slewing.collision_layer = 1
	slewing.collision_mask = 1
	slewing.sync_to_physics = false
	root.add_child(slewing)
	root._tower_jib = slewing

	# Slewing ring & cab
	_add_cyl(slewing, 1.8, 1.2, Vector3(0.0, 0.6, 0.0), steel_dark)
	var cab := _add_box(slewing, Vector3(2.4, 2.4, 2.6),
			Vector3(1.8, 1.8, -1.0), steel_yellow, true)
	_add_box(cab, Vector3(0.1, 1.2, 1.8),
			Vector3(-1.25, 0.2, 0.0), _glass_mat(), false)

	# A-frame tower peak
	var apex_h := 8.5
	_add_box(slewing, Vector3(0.4, apex_h, 0.4),
			Vector3(0.0, apex_h * 0.5 + 1.2, 0.0), steel_yellow, true)
	var b_light := _add_cyl(slewing, 0.2, 0.4,
			Vector3(0.0, apex_h + 1.4, 0.0), beacon_mat)
	root._beacon_mesh = b_light

	# Front Jib (extending 44m along -Z)
	var jib_len := 44.0
	# Bottom twin chords
	for jx in [-1.0, 1.0]:
		_add_box(slewing, Vector3(0.25, 0.25, jib_len),
				Vector3(jx, 1.2, -jib_len * 0.5), steel_yellow, true)
	# Top ridge chord
	_add_box(slewing, Vector3(0.25, 0.25, jib_len),
			Vector3(0.0, 3.4, -jib_len * 0.5), steel_yellow, true)
	# Jib walkway
	_add_box(slewing, Vector3(1.6, 0.08, jib_len),
			Vector3(0.0, 1.25, -jib_len * 0.5), steel_dark, true)

	# Rear Counter-Jib (extending 16m along +Z)
	var r_len := 16.0
	_add_box(slewing, Vector3(2.2, 1.6, r_len),
			Vector3(0.0, 1.8, r_len * 0.5), steel_yellow, true)
	# 4 Concrete counterweight blocks
	for bi in range(4):
		var bz := 9.0 + float(bi) * 1.5
		_add_box(slewing, Vector3(3.2, 2.2, 1.2),
				Vector3(0.0, 2.2, bz), crane_concrete, true)

	# 4. Trolley & Dangling Skip
	var trolley := Node3D.new()
	trolley.name = "TowerTrolley"
	trolley.position = Vector3(0.0, 0.9, -20.0)
	slewing.add_child(trolley)
	root._trolley_node = trolley
	_add_box(trolley, Vector3(1.6, 0.4, 1.6), Vector3.ZERO, steel_dark, true)

	var hoist := Node3D.new()
	hoist.name = "TowerHoist"
	trolley.add_child(hoist)
	root._spreader_node = hoist

	var rope_len := 22.0
	_add_cyl(hoist, 0.04, rope_len, Vector3(0.0, -rope_len * 0.5, 0.0), steel_dark)
	# Heavy concrete skip hopper
	var skip := _add_box(hoist, Vector3(2.4, 2.0, 2.4),
			Vector3(0.0, -rope_len, 0.0), steel_yellow, true)
	_add_box(skip, Vector3(2.0, 0.2, 2.0),
			Vector3(0.0, 0.9, 0.0), steel_dark, false)

	return root


# --- Helper utilities ---
static func _add_box(parent: Node3D, size: Vector3, pos: Vector3,
		mat: Material, collide: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	if collide:
		var body: StaticBody3D = null
		if parent is AnimatableBody3D or parent is StaticBody3D:
			# Directly add collision shape to animatable parent
			var cs := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = size
			cs.shape = shape
			cs.position = pos
			parent.add_child(cs)
			parent.add_child(mi)
			return mi
		else:
			body = StaticBody3D.new()
			body.position = pos
			body.collision_layer = 1
			body.collision_mask = 1
			mi.position = Vector3.ZERO
			body.add_child(mi)
			var cs := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = size
			cs.shape = shape
			body.add_child(cs)
			parent.add_child(body)
			return mi
	else:
		parent.add_child(mi)
		return mi


static func _add_cyl(parent: Node3D, radius: float, height: float,
		pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 10
	mi.mesh = cyl
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi


static var _crane_mat_cache: Dictionary = {}

static func _pbr_mat(albedo: Color, rough: float, metal: float) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f" % [albedo.to_html(), rough, metal]
	if _crane_mat_cache.has(key):
		return _crane_mat_cache[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(
		clampf(albedo.r * 1.32 + 0.06, 0.14, 1.15),
		clampf(albedo.g * 1.32 + 0.06, 0.14, 1.15),
		clampf(albedo.b * 1.32 + 0.06, 0.14, 1.15),
		1.0
	)
	m.roughness = rough
	m.metallic = metal
	m.metallic_specular = 0.30
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_triplanar_sharpness = 8.0
	m.uv1_scale = Vector3.ONE * 0.30
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var diff_p := "res://Assets/frontline/industrial_hall/metal_plate_02_diff.jpg"
	var nor_p := "res://Assets/frontline/industrial_hall/metal_plate_02_nor_gl.jpg"
	var rgh_p := "res://Assets/frontline/industrial_hall/metal_plate_02_rough.jpg"
	if metal < 0.15:
		diff_p = "res://Assets/frontline/industrial_hall/concrete_slab_wall_diff.jpg"
		nor_p = "res://Assets/frontline/industrial_hall/concrete_slab_wall_nor_gl.jpg"
		rgh_p = "res://Assets/frontline/industrial_hall/concrete_slab_wall_rough.jpg"
	elif albedo.r > albedo.b * 1.4:
		diff_p = "res://Assets/frontline/industrial_hall/rusty_metal_02_diff.jpg"
		nor_p = "res://Assets/frontline/industrial_hall/rusty_metal_02_nor_gl.jpg"
		rgh_p = "res://Assets/frontline/industrial_hall/rusty_metal_02_rough.jpg"
	if ResourceLoader.exists(diff_p):
		m.albedo_texture = load(diff_p) as Texture2D
	if ResourceLoader.exists(nor_p):
		m.normal_enabled = true
		m.normal_texture = load(nor_p) as Texture2D
		m.normal_scale = 0.95
	if ResourceLoader.exists(rgh_p):
		m.roughness_texture = load(rgh_p) as Texture2D
	_crane_mat_cache[key] = m
	return m


static func _beacon_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.65, 0.1)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.65, 0.1)
	m.emission_energy_multiplier = 3.5
	return m


static func _glass_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.15, 0.25, 0.32, 0.85)
	m.roughness = 0.15
	m.metallic = 0.4
	return m
