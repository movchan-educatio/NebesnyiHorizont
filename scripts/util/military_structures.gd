class_name MilitaryStructures
extends RefCounted

## Suite of 30 distinct military & industrial freestyle trick structures
## specifically engineered for FPV acrobatic flight (power loops, vertical dives,
## split-S, slaloms, tight gap punches, and matty flips) and realistic frontline warfare.
##
## Photoreal PBR textures:
## - Concrete: 2K weathered slab wall with seams, cracks, micro-roughness & AO.
## - Steel: 2K riveted industrial metal plate.
## - Rust: 2K corroded corrugated metal with flaking rust.
## - Corrugated: 2K CC0 ribbed sheet metal.
## - Hazard: high-contrast yellow & black safety chevrons.
## - Camouflage, sandbags, and weathered timber.
##
## Collision rules:
## - ALL fly-through openings, doorways, arches, skylights, pipe bores, and dive shafts
##   have ZERO blocking collision.
## - Colliders exist exclusively on solid physical members (pillars, beams, slabs, walls).
## - High physics performance guaranteed (box and cylinder primitives).

static var _mat_cache: Dictionary = {}
static var _hazard_tex: ImageTexture = null
static var spawned_positions: Dictionary = {}


## Strict exclusion zones around all workshops / halls on every map.
## No military structure may spawn near any workshop.
static func is_near_workshop(map_name: String, px: float, pz: float) -> bool:
	var p := Vector2(px, pz)
	match map_name:
		"industrial":
			if p.distance_to(Vector2(50.0, 80.0)) < 115.0: # Hero hall
				return true
			if p.distance_to(Vector2(-200.0, -180.0)) < 125.0: # factory_complex.glb
				return true
			if p.distance_to(Vector2(-125.0, 80.0)) < 95.0: # secondary hall
				return true
		"steppe":
			if p.distance_to(Vector2(192.0, 116.0)) < 115.0: # Hero hall
				return true
			if p.distance_to(Vector2(40.0, 146.0)) < 125.0: # farm_complex.glb workshop
				return true
		"village":
			if p.distance_to(Vector2(192.0, 58.0)) < 110.0: # Hero hall
				return true
			if p.distance_to(Vector2(60.0, -110.0)) < 95.0: # village_house.glb
				return true
		"wetlands":
			if p.distance_to(Vector2(85.0, 60.0)) < 110.0: # Hero hall
				return true
			if p.distance_to(Vector2(-60.0, -140.0)) < 95.0: # wetlands_dock.glb
				return true
	return false


static func _get_hazard_texture() -> Texture2D:
	if _hazard_tex != null:
		return _hazard_tex
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var col_yellow := Color(0.94, 0.76, 0.08)
	var col_black := Color(0.12, 0.12, 0.14)
	for y in range(128):
		for x in range(128):
			var stripe := int(x + y) / 16 % 2
			img.set_pixel(x, y, col_yellow if stripe == 0 else col_black)
	img.generate_mipmaps()
	_hazard_tex = ImageTexture.create_from_image(img)
	return _hazard_tex


static func _get_mat(kind: String, tint: Color = Color.WHITE, rough: float = 0.7, metal: float = 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f|%.2f|%.2f|%.2f" % [kind, tint.r, tint.g, tint.b, rough, metal]
	if _mat_cache.has(key):
		return _mat_cache[key] as StandardMaterial3D

	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.roughness = rough
	m.metallic = metal
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_triplanar_sharpness = 8.0
	m.uv1_scale = Vector3.ONE * 0.25

	match kind:
		"concrete":
			var alb := "res://Assets/frontline/industrial_hall/concrete_slab_wall_diff.jpg"
			var nrm := "res://Assets/frontline/industrial_hall/concrete_slab_wall_nor_gl.jpg"
			var rgh := "res://Assets/frontline/industrial_hall/concrete_slab_wall_rough.jpg"
			var ao := "res://Assets/frontline/industrial_hall/concrete_slab_wall_ao.jpg"
			if ResourceLoader.exists(alb):
				m.albedo_texture = load(alb) as Texture2D
				m.uv1_scale = Vector3.ONE * 0.22
			if ResourceLoader.exists(nrm):
				m.normal_enabled = true
				m.normal_texture = load(nrm) as Texture2D
				m.normal_scale = 1.2
			if ResourceLoader.exists(rgh):
				m.roughness_texture = load(rgh) as Texture2D
			if ResourceLoader.exists(ao):
				m.ao_enabled = true
				m.ao_texture = load(ao) as Texture2D
			m.roughness = 0.88
			m.metallic = 0.0

		"steel":
			var alb := "res://Assets/frontline/industrial_hall/metal_plate_02_diff.jpg"
			var nrm := "res://Assets/frontline/industrial_hall/metal_plate_02_nor_gl.jpg"
			var rgh := "res://Assets/frontline/industrial_hall/metal_plate_02_rough.jpg"
			if ResourceLoader.exists(alb):
				m.albedo_texture = load(alb) as Texture2D
				m.uv1_scale = Vector3.ONE * 0.26
			if ResourceLoader.exists(nrm):
				m.normal_enabled = true
				m.normal_texture = load(nrm) as Texture2D
				m.normal_scale = 1.1
			if ResourceLoader.exists(rgh):
				m.roughness_texture = load(rgh) as Texture2D
			m.roughness = rough if rough != 0.7 else 0.52
			m.metallic = metal if metal != 0.0 else 0.65

		"rust":
			var alb := "res://Assets/frontline/industrial_hall/rusty_metal_02_diff.jpg"
			var nrm := "res://Assets/frontline/industrial_hall/rusty_metal_02_nor_gl.jpg"
			var rgh := "res://Assets/frontline/industrial_hall/rusty_metal_02_rough.jpg"
			if ResourceLoader.exists(alb):
				m.albedo_texture = load(alb) as Texture2D
				m.uv1_scale = Vector3.ONE * 0.28
			if ResourceLoader.exists(nrm):
				m.normal_enabled = true
				m.normal_texture = load(nrm) as Texture2D
			if ResourceLoader.exists(rgh):
				m.roughness_texture = load(rgh) as Texture2D
			m.roughness = 0.82
			m.metallic = 0.20

		"corrugated":
			var alb := "res://Assets/handcrafted/cc0/Metal032_2K-JPG/Metal032_2K-JPG_Color.jpg"
			var nrm := "res://Assets/handcrafted/cc0/Metal032_2K-JPG/Metal032_2K-JPG_NormalGL.jpg"
			var rgh := "res://Assets/handcrafted/cc0/Metal032_2K-JPG/Metal032_2K-JPG_Roughness.jpg"
			if ResourceLoader.exists(alb):
				m.albedo_texture = load(alb) as Texture2D
				m.uv1_scale = Vector3.ONE * 0.24
			if ResourceLoader.exists(nrm):
				m.normal_enabled = true
				m.normal_texture = load(nrm) as Texture2D
			if ResourceLoader.exists(rgh):
				m.roughness_texture = load(rgh) as Texture2D
			m.roughness = 0.65
			m.metallic = 0.55

		"hazard":
			m.albedo_texture = _get_hazard_texture()
			m.uv1_scale = Vector3.ONE * 0.40
			m.roughness = 0.45
			m.metallic = 0.25

		"camo":
			var alb := "res://Assets/frontline/textures/camo_albedo.png"
			var nrm := "res://Assets/frontline/textures/camo_normal.png"
			var rgh := "res://Assets/frontline/textures/camo_rough.png"
			if ResourceLoader.exists(alb):
				m.albedo_texture = load(alb) as Texture2D
				m.uv1_scale = Vector3.ONE * 0.35
			if ResourceLoader.exists(nrm):
				m.normal_enabled = true
				m.normal_texture = load(nrm) as Texture2D
			if ResourceLoader.exists(rgh):
				m.roughness_texture = load(rgh) as Texture2D
			m.roughness = 0.85
			m.metallic = 0.05

		"sandbag":
			var alb := "res://Assets/frontline/textures/sandbag_albedo.png"
			var nrm := "res://Assets/frontline/textures/sandbag_normal.png"
			var rgh := "res://Assets/frontline/textures/sandbag_rough.png"
			if ResourceLoader.exists(alb):
				m.albedo_texture = load(alb) as Texture2D
				m.uv1_scale = Vector3.ONE * 0.45
			if ResourceLoader.exists(nrm):
				m.normal_enabled = true
				m.normal_texture = load(nrm) as Texture2D
			if ResourceLoader.exists(rgh):
				m.roughness_texture = load(rgh) as Texture2D
			m.roughness = 0.90
			m.metallic = 0.0

		"wood":
			var alb := "res://Assets/frontline/textures/wood_albedo.png"
			var nrm := "res://Assets/frontline/textures/wood_normal.png"
			var rgh := "res://Assets/frontline/textures/wood_rough.png"
			if ResourceLoader.exists(alb):
				m.albedo_texture = load(alb) as Texture2D
				m.uv1_scale = Vector3.ONE * 0.30
			if ResourceLoader.exists(nrm):
				m.normal_enabled = true
				m.normal_texture = load(nrm) as Texture2D
			if ResourceLoader.exists(rgh):
				m.roughness_texture = load(rgh) as Texture2D
			m.roughness = 0.84
			m.metallic = 0.0

	_mat_cache[key] = m
	return m


# =============================================================================
#  Primitives Helpers
# =============================================================================

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
		var body := StaticBody3D.new()
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
		pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO, collide: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 14
	mi.mesh = cyl
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	if collide:
		var body := StaticBody3D.new()
		body.position = pos
		body.rotation = rot
		body.collision_layer = 1
		body.collision_mask = 1
		mi.position = Vector3.ZERO
		body.add_child(mi)
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = height
		cs.shape = shape
		body.add_child(cs)
		parent.add_child(body)
		return mi
	else:
		parent.add_child(mi)
		return mi


# =============================================================================
#  30 FPV FREESTYLE TRICK STRUCTURES & MILITARY FORTIFICATIONS
# =============================================================================

## 1. "РУБІК" / 3-Story Concrete Construction Skeleton (Vertical Dives & Floor Gaps)
static func build_construction_skeleton_rubik(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.name = "ConstructionSkeletonRubik"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var concrete := _get_mat("concrete", Color(0.82, 0.80, 0.76))
	var hazard := _get_mat("hazard")
	var steel := _get_mat("steel", Color(0.35, 0.38, 0.40))

	var w := 16.0
	var d := 14.0
	var h_floor := 4.2
	var total_h := h_floor * 3.0

	# 12 Perimeter & Interior Columns (Solid pillars with full fly-through bays between them)
	var col_size := Vector3(0.65, total_h, 0.65)
	for cx in [-w * 0.5, -w * 0.16, w * 0.16, w * 0.5]:
		for cz in [-d * 0.5, 0.0, d * 0.5]:
			_add_box(root, col_size, Vector3(cx, total_h * 0.5, cz), concrete, true)

	# Floor 1 Slab (Deep concrete foundation skirt, embedded 4.6m into terrain to eliminate floating gaps)
	_add_box(root, Vector3(w + 1.0, 5.0, d + 1.0), Vector3(0.0, -2.1, 0.0), concrete, true)

	# Floor 2 Slab with Large Left Vertical Dive Cutout (6m x 5m gap)
	_add_box(root, Vector3(w * 0.5, 0.35, d), Vector3(w * 0.25, h_floor, 0.0), concrete, true)
	_add_box(root, Vector3(w * 0.5, 0.35, d * 0.3), Vector3(-w * 0.25, h_floor, d * 0.35), concrete, true)
	_add_box(root, Vector3(w * 0.5, 0.35, d * 0.3), Vector3(-w * 0.25, h_floor, -d * 0.35), concrete, true)
	# Hazard striping along the dive shaft edge
	_add_box(root, Vector3(0.2, 0.4, d * 0.4), Vector3(0.0, h_floor + 0.1, 0.0), hazard, false)

	# Floor 3 Slab with Large Right Vertical Dive Cutout (6m x 5m gap)
	_add_box(root, Vector3(w * 0.5, 0.35, d), Vector3(-w * 0.25, h_floor * 2.0, 0.0), concrete, true)
	_add_box(root, Vector3(w * 0.5, 0.35, d * 0.3), Vector3(w * 0.25, h_floor * 2.0, d * 0.35), concrete, true)
	_add_box(root, Vector3(w * 0.5, 0.35, d * 0.3), Vector3(w * 0.25, h_floor * 2.0, -d * 0.35), concrete, true)
	_add_box(root, Vector3(0.2, 0.4, d * 0.4), Vector3(0.0, h_floor * 2.0 + 0.1, 0.0), hazard, false)

	# Roof Slab with Open Center Skylight (7m x 6m central dive hole from 13m altitude)
	_add_box(root, Vector3(w, 0.35, 3.5), Vector3(0.0, total_h, d * 0.5 - 1.75), concrete, true)
	_add_box(root, Vector3(w, 0.35, 3.5), Vector3(0.0, total_h, -d * 0.5 + 1.75), concrete, true)
	_add_box(root, Vector3(3.5, 0.35, d - 7.0), Vector3(-w * 0.5 + 1.75, total_h, 0.0), concrete, true)
	_add_box(root, Vector3(3.5, 0.35, d - 7.0), Vector3(w * 0.5 - 1.75, total_h, 0.0), concrete, true)
	# Perimeter Safety Guardrails with hazard stripe
	_add_box(root, Vector3(w, 0.15, 0.15), Vector3(0.0, total_h + 1.0, d * 0.5), steel, false)
	_add_box(root, Vector3(w, 0.15, 0.15), Vector3(0.0, total_h + 1.0, -d * 0.5), steel, false)
	return root


## 2. Industrial Pipe & Truss Power-Loop Arch (Overhead Gantry with Dual Gaps)
static func build_pipeline_powerloop_arch(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.name = "PipelinePowerloopArch"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var steel := _get_mat("steel", Color(0.38, 0.42, 0.45))
	var rust := _get_mat("rust", Color(0.55, 0.35, 0.25))
	var hazard := _get_mat("hazard")
	var concrete := _get_mat("concrete", Color(0.70, 0.68, 0.64))

	var span := 18.0
	var h_arch := 13.0

	# Left and Right Heavy A-frame Trestle Legs with Deep Foundation Piers
	for side in [-1.0, 1.0]:
		var lx: float = float(side) * span * 0.5
		# Deep concrete foundation blocks buried 5.5m into terrain
		_add_box(root, Vector3(2.4, 5.5, 4.8), Vector3(lx, -2.4, 0.0), concrete, true)
		_add_box(root, Vector3(1.2, h_arch, 1.2), Vector3(lx, h_arch * 0.5, -1.5), steel, true)
		_add_box(root, Vector3(1.2, h_arch, 1.2), Vector3(lx, h_arch * 0.5, 1.5), steel, true)
		# Diagonal brace
		_add_box(root, Vector3(0.8, 1.0, 3.8), Vector3(lx, h_arch * 0.3, 0.0), steel, true)

	# Main Overhead Heavy Pipeline 1 (Diameter 1.6m, at Y=12m)
	_add_cyl(root, 0.8, span + 4.0, Vector3(0.0, h_arch, -1.2), rust, Vector3(0.0, 0.0, PI * 0.5), true)
	# Secondary Overhead Pipeline 2 (Diameter 1.2m, at Y=14m)
	_add_cyl(root, 0.6, span + 4.0, Vector3(0.0, h_arch + 2.2, 1.2), steel, Vector3(0.0, 0.0, PI * 0.5), true)

	# Upper Truss Beam Frame (Creates upper 3.5m x 14m knife-edge gap slot!)
	_add_box(root, Vector3(span, 0.35, 0.35), Vector3(0.0, h_arch + 3.4, 0.0), steel, true)

	# Lower Yellow-Black Hazard Gantry Bar (Marks main 10.5m x 15m power-loop opening)
	_add_box(root, Vector3(span, 0.4, 0.4), Vector3(0.0, h_arch - 1.2, 0.0), hazard, true)
	return root


## 3. Freestyle Slalom Gate Runway (4 Arched Gates for Knife-Edge Banking)
static func build_fpv_slalom_gate_course(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.name = "FreestyleSlalomGateCourse"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var hazard := _get_mat("hazard")
	var camo := _get_mat("camo", Color(0.28, 0.38, 0.22))
	var steel := _get_mat("steel", Color(0.32, 0.34, 0.36))

	var gate_w := 5.2
	var gate_h := 4.2
	var gate_thick := 0.22

	for i in range(4):
		var gz := float(i - 1.5) * 14.0
		# Staggered offset in X for realistic slalom weave
		var gx := sin(float(i) * 1.5) * 3.5

		# Left Post
		_add_box(root, Vector3(gate_thick, gate_h, gate_thick), Vector3(gx - gate_w * 0.5, gate_h * 0.5, gz), hazard, true)
		# Right Post
		_add_box(root, Vector3(gate_thick, gate_h, gate_thick), Vector3(gx + gate_w * 0.5, gate_h * 0.5, gz), hazard, true)
		# Top Arch Crossbar
		_add_box(root, Vector3(gate_w, gate_thick, gate_thick), Vector3(gx, gate_h, gz), hazard, true)
		# 45-degree Corner Gusset Brackets
		_add_box(root, Vector3(1.0, 0.18, 0.18), Vector3(gx - gate_w * 0.5 + 0.4, gate_h - 0.4, gz), hazard, true)
		_add_box(root, Vector3(1.0, 0.18, 0.18), Vector3(gx + gate_w * 0.5 - 0.4, gate_h - 0.4, gz), hazard, true)

		# Top Camo Banner (Visual FPV racing flag)
		_add_box(root, Vector3(gate_w * 0.9, 0.6, 0.05), Vector3(gx, gate_h + 0.4, gz), camo, false)
		# Deep Base Anchor Piers (embedded 4.5m into terrain so never floating)
		_add_box(root, Vector3(0.9, 4.5, 0.9), Vector3(gx - gate_w * 0.5, -2.0, gz), steel, true)
		_add_box(root, Vector3(0.9, 4.5, 0.9), Vector3(gx + gate_w * 0.5, -2.0, gz), steel, true)
	return root


## 4. Hollow Mega-Silo / Industrial Cooling Stack (Vertical Dive Funnel & Side Breach)
static func build_cooling_tower_dive_funnel(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.name = "CoolingTowerDiveFunnel"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var concrete := _get_mat("concrete", Color(0.72, 0.70, 0.66))
	var hazard := _get_mat("hazard")
	var rust := _get_mat("rust", Color(0.48, 0.32, 0.22))

	var h := 22.0
	var r := 4.2
	var segs := 16

	# Deep foundation collar embedded 6.5m into terrain (prevents hovering on slopes)
	_add_cyl(root, r + 0.4, 6.5, Vector3(0.0, -3.2, 0.0), concrete, Vector3.ZERO, true)

	# Hollow faceted cylinder wall (Constructed as segment panels leaving top 100% open,
	# and two bottom panels omitted at North & South for 4m x 3.5m exit breaches!)
	for s in range(segs):
		var ang := float(s) * TAU / float(segs)
		var is_breach := (s == 0 or s == segs / 2) # South and North ground breach exits

		var px := sin(ang) * r
		var pz := cos(ang) * r
		var panel_w := (TAU * r / float(segs)) * 1.05

		if is_breach:
			# Wall starts at Y=3.6m above the breach opening!
			var wall_h := h - 3.6
			var mi := _add_box(root, Vector3(panel_w, wall_h, 0.45), Vector3(px, 3.6 + wall_h * 0.5, pz), concrete, true)
			mi.rotation.y = ang
			# Hazard stripe over the exit breach header
			var hb := _add_box(root, Vector3(panel_w, 0.4, 0.5), Vector3(px, 3.6, pz), hazard, true)
			hb.rotation.y = ang
		else:
			# Deep anchored solid wall panel extending into ground
			var wall_h := h + 6.0
			var mi := _add_box(root, Vector3(panel_w, wall_h, 0.45), Vector3(px, (h - 6.0) * 0.5, pz), concrete, true)
			mi.rotation.y = ang

	# Top Red/Yellow Hazard Lip Rim (Marks the 7.5m diameter dive target)
	for s in range(segs):
		var ang := float(s) * TAU / float(segs)
		var px := sin(ang) * r
		var pz := cos(ang) * r
		var panel_w := (TAU * r / float(segs)) * 1.08
		var rim := _add_box(root, Vector3(panel_w, 0.5, 0.7), Vector3(px, h, pz), hazard, true)
		rim.rotation.y = ang

	# External Maintenance Ladder & Caged Flue Pipe
	_add_cyl(root, 0.35, h + 2.0, Vector3(r + 0.6, h * 0.5, 0.0), rust, Vector3.ZERO, true)
	return root


## 5. Stacked ISO Cargo Container Complex (16m Tunnel + Rooftop Bridge Gap)
static func build_shipping_container_complex(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.name = "ShippingContainerComplex"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var corrugated_olive := _get_mat("corrugated", Color(0.32, 0.38, 0.26))
	var corrugated_rust := _get_mat("rust", Color(0.58, 0.36, 0.24))
	var steel_blue := _get_mat("steel", Color(0.24, 0.32, 0.42))
	var hazard := _get_mat("hazard")

	var cw := 2.6
	var ch := 2.8
	var cl := 12.2

	# Deep foundation pad embedded 5m into terrain
	var concrete := _get_mat("concrete", Color(0.68, 0.66, 0.62))
	_add_box(root, Vector3(cl + 2.0, 5.0, cl * 2.0 + 2.0), Vector3(0.0, -2.4, 0.0), concrete, true)

	# Bottom Tunnel: Two containers placed end-to-end with open doors (24.4m continuous tunnel!)
	for i in [0, 1]:
		var cz: float = (float(i) - 0.5) * (cl - 0.1)
		# Left Wall
		_add_box(root, Vector3(0.12, ch, cl), Vector3(-cw * 0.5, ch * 0.5, cz), corrugated_olive, true)
		# Right Wall
		_add_box(root, Vector3(0.12, ch, cl), Vector3(cw * 0.5, ch * 0.5, cz), corrugated_olive, true)
		# Roof
		_add_box(root, Vector3(cw, 0.12, cl), Vector3(0.0, ch, cz), corrugated_olive, true)
		# Floor
		_add_box(root, Vector3(cw, 0.15, cl), Vector3(0.0, 0.08, cz), steel_blue, true)
		# Entrance Hazard Perimeter
		_add_box(root, Vector3(cw + 0.2, 0.2, 0.2), Vector3(0.0, ch, cz + (cl * 0.5 if i == 1 else -cl * 0.5)), hazard, false)

	# Tier 2: Two Crosswise Containers with a 4.5m Gap Between Them
	# Container Left (Tier 2)
	_add_box(root, Vector3(cl, ch, cw), Vector3(0.0, ch + ch * 0.5, -4.5), corrugated_rust, true)
	# Container Right (Tier 2)
	_add_box(root, Vector3(cl, ch, cw), Vector3(0.0, ch + ch * 0.5, 4.5), steel_blue, true)

	# Tier 3: Top Cantilevered Container Perch (Height 8.4m, perfect for wall taps)
	_add_box(root, Vector3(cw, ch, cl), Vector3(2.5, ch * 2.0 + ch * 0.5, 0.0), corrugated_olive, true)
	# Slim support columns: the top container is a deliberate FPV perch, but it
	# must not read as a shipping container floating in the air.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_add_box(root, Vector3(0.22, ch * 2.0 + ch * 0.5, 0.22),
					Vector3(2.5 + sx * 1.15, (ch * 2.0 + ch * 0.5) * 0.5, sz * 5.3),
					steel_blue, true)
	return root


## 6. Triple Concrete Culvert Pipe Course (Giant 3.4m Conduit Tubes)
static func build_concrete_pipe_culvert_course(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.name = "ConcretePipeCulvertCourse"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var concrete := _get_mat("concrete", Color(0.76, 0.74, 0.70))
	var hazard := _get_mat("hazard")

	var r_outer := 1.9
	var r_inner := 1.55
	var pipe_len := 7.5
	var segs := 12

	# 3 Concrete Culverts in a row with slight curve
	for p in range(3):
		var pz := float(p - 1.0) * 11.0
		var px := sin(float(p) * 0.7) * 2.5
		var pipe_yaw := float(p - 1.0) * 0.15

		var pipe_node := Node3D.new()
		pipe_node.position = Vector3(px, r_outer, pz)
		pipe_node.rotation.y = pipe_yaw
		root.add_child(pipe_node)

		# Deep Concrete Support Cradle Base (embedded 5m into terrain)
		_add_box(pipe_node, Vector3(r_outer * 2.4, 5.0, pipe_len * 0.95), Vector3(0.0, -r_outer - 1.7, 0.0), concrete, true)

		# Hollow Barrel Segments (Leaves interior bore completely open)
		for s in range(segs):
			var a := float(s) * TAU / float(segs)
			var seg_w := (TAU * r_outer / float(segs)) * 1.04
			var sx := sin(a) * ((r_outer + r_inner) * 0.5)
			var sy := cos(a) * ((r_outer + r_inner) * 0.5)
			var mi := _add_box(pipe_node, Vector3(seg_w, 0.35, pipe_len), Vector3(sx, sy, 0.0), concrete, true)
			mi.rotation.z = -a

		# High-visibility Hazard Lip at entrances
		for end_z in [-pipe_len * 0.5, pipe_len * 0.5]:
			for s in range(segs):
				var a := float(s) * TAU / float(segs)
				var seg_w := (TAU * r_outer / float(segs)) * 1.06
				var sx := sin(a) * r_outer
				var sy := cos(a) * r_outer
				var rim := _add_box(pipe_node, Vector3(seg_w, 0.25, 0.25), Vector3(sx, sy, end_z), hazard, false)
				rim.rotation.z = -a
	return root


## 7. High-Voltage Steel Lattice Pylon (26m Tower with Central Diamond Gap)
static func build_high_voltage_pylon(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.name = "HighVoltagePylon"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var steel := _get_mat("steel", Color(0.40, 0.42, 0.45))
	var hazard := _get_mat("hazard")
	var concrete := _get_mat("concrete", Color(0.70, 0.68, 0.64))

	var total_h := 26.0

	# 4 Concrete Foundation Piers (Deeply embedded 5m into ground to prevent floating on slopes)
	for sx in [-4.0, 4.0]:
		for sz in [-4.0, 4.0]:
			_add_box(root, Vector3(1.6, 5.5, 1.6), Vector3(sx, -2.0, sz), concrete, true)

	# 4 Tapered Main Lattice Corner Girders (From 8m base to 3m neck at Y=16m)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var mi := _add_box(root, Vector3(0.35, 16.0, 0.35), Vector3(sx * 2.5, 8.0, sz * 2.5), steel, true)
			# Splay slope
			mi.rotation.x = -sz * 0.09
			mi.rotation.z = sx * 0.09

	# Horizontal Braces every 4m with open center
	for y_lvl in [4.0, 8.0, 12.0, 16.0]:
		var half_span: float = lerpf(3.8, 1.6, float(y_lvl) / 16.0)
		_add_box(root, Vector3(half_span * 2.0, 0.25, 0.25), Vector3(0.0, float(y_lvl), half_span), steel, true)
		_add_box(root, Vector3(half_span * 2.0, 0.25, 0.25), Vector3(0.0, float(y_lvl), -half_span), steel, true)
		_add_box(root, Vector3(0.25, 0.25, half_span * 2.0), Vector3(half_span, float(y_lvl), 0.0), steel, true)
		_add_box(root, Vector3(0.25, 0.25, half_span * 2.0), Vector3(-half_span, float(y_lvl), 0.0), steel, true)

	# Central Fly-Through Diamond Aperture (At Y=16m to Y=20m, 3.8m x 3.8m gap!)
	_add_box(root, Vector3(0.3, 10.0, 0.3), Vector3(-1.6, 21.0, -1.6), steel, true)
	_add_box(root, Vector3(0.3, 10.0, 0.3), Vector3(1.6, 21.0, -1.6), steel, true)
	_add_box(root, Vector3(0.3, 10.0, 0.3), Vector3(-1.6, 21.0, 1.6), steel, true)
	_add_box(root, Vector3(0.3, 10.0, 0.3), Vector3(1.6, 21.0, 1.6), steel, true)

	# Crossarm Booms (Span 18m at Y=21m and 14m at Y=24m)
	_add_box(root, Vector3(18.0, 0.4, 0.4), Vector3(0.0, 21.0, 0.0), steel, true)
	_add_box(root, Vector3(14.0, 0.4, 0.4), Vector3(0.0, 24.5, 0.0), steel, true)
	# Hazard warning flags on tips
	_add_box(root, Vector3(0.5, 0.5, 0.5), Vector3(-9.0, 21.0, 0.0), hazard, false)
	_add_box(root, Vector3(0.5, 0.5, 0.5), Vector3(9.0, 21.0, 0.0), hazard, false)
	return root


## 8. Damaged Aircraft / Vehicle Shelter (22m Hangar with Roof Skylight Breaches)
static func build_damaged_hangar_arch(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.name = "DamagedHangarArch"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var corrugated := _get_mat("corrugated", Color(0.38, 0.44, 0.36))
	var steel := _get_mat("steel", Color(0.35, 0.38, 0.42))
	var concrete := _get_mat("concrete", Color(0.74, 0.72, 0.68))
	var hazard := _get_mat("hazard")

	var length := 22.0
	var w := 14.0
	var h := 7.5

	# Deep Concrete Foundation Curbs (embedded 5.5m into terrain)
	_add_box(root, Vector3(1.8, 5.5, length + 1.0), Vector3(-w * 0.5, -2.2, 0.0), concrete, true)
	_add_box(root, Vector3(1.8, 5.5, length + 1.0), Vector3(w * 0.5, -2.2, 0.0), concrete, true)
	_add_box(root, Vector3(w, 5.0, length), Vector3(0.0, -2.4, 0.0), concrete, true)

	# 7 Curved Steel Truss Ribs
	for i in range(7):
		var rz := float(i - 3) * (length / 6.0)
		# Left vertical wall
		_add_box(root, Vector3(0.4, 3.8, 0.4), Vector3(-w * 0.5, 2.0, rz), steel, true)
		# Right vertical wall
		_add_box(root, Vector3(0.4, 3.8, 0.4), Vector3(w * 0.5, 2.0, rz), steel, true)
		# Left roof pitch
		var mi1 := _add_box(root, Vector3(7.6, 0.35, 0.4), Vector3(-w * 0.25, 5.6, rz), steel, true)
		mi1.rotation.z = -0.45
		# Right roof pitch
		var mi2 := _add_box(root, Vector3(7.6, 0.35, 0.4), Vector3(w * 0.25, 5.6, rz), steel, true)
		mi2.rotation.z = 0.45

	# Corrugated Roof Panels: Middle ribs have sections REMOVED creating two 4.5m x 5m Skylight Dive Holes!
	# Front roof section
	_add_box(root, Vector3(w * 0.5, 0.12, 6.0), Vector3(-w * 0.26, 5.7, 7.5), corrugated, true)
	_add_box(root, Vector3(w * 0.5, 0.12, 6.0), Vector3(w * 0.26, 5.7, 7.5), corrugated, true)
	# Rear roof section
	_add_box(root, Vector3(w * 0.5, 0.12, 6.0), Vector3(-w * 0.26, 5.7, -7.5), corrugated, true)
	_add_box(root, Vector3(w * 0.5, 0.12, 6.0), Vector3(w * 0.26, 5.7, -7.5), corrugated, true)

	# Portal Portals Hazard Striping
	_add_box(root, Vector3(w, 0.3, 0.3), Vector3(0.0, h, length * 0.5), hazard, false)
	_add_box(root, Vector3(w, 0.3, 0.3), Vector3(0.0, h, -length * 0.5), hazard, false)
	return root


## 9. Military Radar Relay & Fly-Through Aperture Ring
static func build_radar_relay_station(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.name = "RadarRelayStation"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var steel := _get_mat("steel", Color(0.38, 0.40, 0.42))
	var hazard := _get_mat("hazard")
	var concrete := _get_mat("concrete", Color(0.70, 0.68, 0.65))

	# Deep Concrete Foundation (embedded 6m into terrain)
	_add_box(root, Vector3(5.6, 6.0, 5.6), Vector3(0.0, -2.5, 0.0), concrete, true)

	# 4 Steel Mast Legs
	var h := 18.0
	for sx in [-1.5, 1.5]:
		for sz in [-1.5, 1.5]:
			_add_box(root, Vector3(0.35, h, 0.35), Vector3(sx, h * 0.5 + 0.5, sz), steel, true)
	for y in [4.0, 8.0, 12.0, 16.0]:
		_add_box(root, Vector3(3.3, 0.25, 0.25), Vector3(0.0, y, 1.5), steel, true)
		_add_box(root, Vector3(3.3, 0.25, 0.25), Vector3(0.0, y, -1.5), steel, true)
		_add_box(root, Vector3(0.25, 0.25, 3.3), Vector3(1.5, y, 0.0), steel, true)
		_add_box(root, Vector3(0.25, 0.25, 3.3), Vector3(-1.5, y, 0.0), steel, true)

	# Top Platform with Circular Fly-Through Radar Ring (Diameter 4.0m, hollow bore)
	_add_box(root, Vector3(4.5, 0.4, 4.5), Vector3(0.0, h, 0.0), steel, true)
	var ring_r := 2.2
	for s in range(8):
		var a := float(s) * TAU / 8.0
		var px := sin(a) * ring_r
		var py := cos(a) * ring_r
		var seg := _add_box(root, Vector3(1.8, 0.28, 0.28), Vector3(px, h + 3.0 + py, 0.0), hazard, true)
		seg.rotation.z = -a
	return root


## 10. Fortified Trench Pillbox Bunker (3 Panoramic Embrasures + Rear Trench Exit)
static func build_hardened_trench_bunker(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.name = "HardenedTrenchBunker"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var concrete := _get_mat("concrete", Color(0.66, 0.65, 0.62))
	var sandbag := _get_mat("sandbag", Color(0.58, 0.52, 0.38))
	var steel := _get_mat("steel", Color(0.30, 0.32, 0.35))

	var bw := 11.0
	var bd := 8.0
	var bh := 3.2

	# Deep Solid Base Slab (embedded 6m into terrain)
	_add_box(root, Vector3(bw + 0.6, 6.0, bd + 0.6), Vector3(0.0, -2.75, 0.0), concrete, true)
	# Heavy Reinforced Roof Cap (1.2m thick blast slab)
	_add_box(root, Vector3(bw + 0.8, 1.2, bd + 0.8), Vector3(0.0, bh + 0.6, 0.0), concrete, true)

	# Left and Right Outer Blast Walls
	_add_box(root, Vector3(1.4, bh, bd), Vector3(-bw * 0.5 + 0.7, bh * 0.5, 0.0), concrete, true)
	_add_box(root, Vector3(1.4, bh, bd), Vector3(bw * 0.5 - 0.7, bh * 0.5, 0.0), concrete, true)

	# Front Facade: 2 Piers dividing 3 Firing Slits (2.4m x 1.2m open embrasures!)
	_add_box(root, Vector3(1.2, bh, 1.2), Vector3(-1.8, bh * 0.5, bd * 0.5 - 0.6), concrete, true)
	_add_box(root, Vector3(1.2, bh, 1.2), Vector3(1.8, bh * 0.5, bd * 0.5 - 0.6), concrete, true)
	# Lower window sill
	_add_box(root, Vector3(bw - 2.8, 1.0, 1.0), Vector3(0.0, 0.5, bd * 0.5 - 0.6), concrete, true)

	# Rear Open Trench Corridor (Zero rear wall, allowing drone to punch in front slit and exit back!)
	_add_box(root, Vector3(1.0, 1.8, 6.0), Vector3(-2.2, 0.9, -bd * 0.5 - 3.0), sandbag, true)
	_add_box(root, Vector3(1.0, 1.8, 6.0), Vector3(2.2, 0.9, -bd * 0.5 - 3.0), sandbag, true)
	return root


## 11. Dragon's Teeth Anti-Tank Pyramid Line (Slalom Course)
static func build_dragons_teeth_line(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.name = "DragonsTeethLine"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var concrete := _get_mat("concrete", Color(0.72, 0.70, 0.66))
	var rust := _get_mat("rust", Color(0.50, 0.32, 0.22))

	for i in range(7):
		var px := float(i - 3) * 3.2
		var pz := (float(i % 2) - 0.5) * 2.2
		# Stepped pyramid tooth with 4.5m deep foundation block
		_add_box(root, Vector3(2.0, 4.5, 2.0), Vector3(px, -1.75, pz), concrete, true)
		_add_box(root, Vector3(1.2, 0.7, 1.2), Vector3(px, 0.85, pz), concrete, true)
		_add_box(root, Vector3(0.6, 0.6, 0.6), Vector3(px, 1.5, pz), concrete, true)
	# Connecting Heavy Steel Cable
	_add_box(root, Vector3(21.0, 0.08, 0.08), Vector3(0.0, 1.1, 0.0), rust, false)
	return root


## 12. Roadblock Checkpoint Chicane & Gate
static func build_checkpoint_fortification(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.name = "CheckpointFortification"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var concrete := _get_mat("concrete", Color(0.74, 0.72, 0.68))
	var sandbag := _get_mat("sandbag", Color(0.58, 0.52, 0.38))
	var hazard := _get_mat("hazard")
	var steel := _get_mat("steel", Color(0.36, 0.38, 0.40))

	# Deep concrete foundation pad (embedded 4.5m into terrain)
	_add_box(root, Vector3(14.0, 4.5, 9.0), Vector3(0.0, -2.2, 0.0), concrete, true)

	_add_box(root, Vector3(5.0, 1.2, 0.8), Vector3(-3.2, 0.6, -2.5), concrete, true)
	_add_box(root, Vector3(5.0, 1.2, 0.8), Vector3(3.2, 0.6, 2.5), concrete, true)
	_add_box(root, Vector3(2.5, 1.4, 2.5), Vector3(-6.0, 0.7, 0.0), sandbag, true)
	_add_box(root, Vector3(6.5, 0.25, 0.25), Vector3(0.5, 1.4, 0.0), hazard, true)
	_add_box(root, Vector3(0.7, 2.0, 0.7), Vector3(-3.5, 1.0, 0.0), steel, true)
	return root


## 13. Sandbag Mortar Pit (Circular Bowl for Dive-Bomb Loops)
static func build_sandbag_mortar_pit(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.name = "SandbagMortarPit"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var sandbag := _get_mat("sandbag", Color(0.58, 0.52, 0.38))
	var wood := _get_mat("wood", Color(0.48, 0.40, 0.30))
	var camo := _get_mat("camo", Color(0.30, 0.38, 0.24))

	var r := 4.8
	var count := 10

	# Deep circular foundation base embedded 4.5m into terrain
	_add_cyl(root, r + 1.2, 4.5, Vector3(0.0, -2.0, 0.0), sandbag, Vector3.ZERO, true)

	for i in range(count):
		var a := float(i) * TAU / float(count)
		var p := Vector3(sin(a) * r, 0.8, cos(a) * r)
		var b := _add_box(root, Vector3(3.0, 1.6, 1.4), p, sandbag, true)
		b.rotation.y = a

	_add_box(root, Vector3(1.4, 0.8, 1.0), Vector3(1.8, 0.4, 1.0), wood, true)
	_add_box(root, Vector3(3.5, 0.1, 9.5), Vector3(-2.4, 2.6, 0.0), camo, false)
	return root


## 14. Twin Fuel Storage Revetment & Catwalk Gap
static func build_fuel_storage_revetment(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.name = "FuelStorageRevetment"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var rust := _get_mat("rust", Color(0.52, 0.35, 0.25))
	var steel := _get_mat("steel", Color(0.38, 0.42, 0.46))
	var concrete := _get_mat("concrete", Color(0.72, 0.70, 0.66))
	var hazard := _get_mat("hazard")

	# Deep concrete foundation pad (embedded 5m into terrain)
	_add_box(root, Vector3(20.0, 5.0, 16.0), Vector3(0.0, -2.4, 0.0), concrete, true)

	# Concrete Berm Retaining Wall
	_add_box(root, Vector3(18.0, 1.4, 1.0), Vector3(0.0, 0.7, -6.5), concrete, true)
	_add_box(root, Vector3(18.0, 1.4, 1.0), Vector3(0.0, 0.7, 6.5), concrete, true)
	_add_box(root, Vector3(1.0, 1.4, 14.0), Vector3(-9.0, 0.7, 0.0), concrete, true)
	_add_box(root, Vector3(1.0, 1.4, 14.0), Vector3(9.0, 0.7, 0.0), concrete, true)

	# Twin Cylindrical Tanks (Diameter 6.4m, Height 6m)
	_add_cyl(root, 3.2, 6.0, Vector3(-4.5, 3.0, 0.0), rust, Vector3.ZERO, true)
	_add_cyl(root, 3.2, 6.0, Vector3(4.5, 3.0, 0.0), steel, Vector3.ZERO, true)

	# Elevated Skybridge Catwalk between tanks (Height 5m, creates 3m wide fly-through slot underneath!)
	_add_box(root, Vector3(3.0, 0.25, 1.4), Vector3(0.0, 5.2, 0.0), steel, true)
	_add_box(root, Vector3(3.0, 0.9, 0.1), Vector3(0.0, 5.75, 0.7), steel, false)
	_add_box(root, Vector3(3.0, 0.9, 0.1), Vector3(0.0, 5.75, -0.7), steel, false)
	_add_box(root, Vector3(3.0, 0.3, 0.3), Vector3(0.0, 5.0, 0.0), hazard, false)
	return root


## 15. Observation Watchtower (14m Elevated Platform with 360 Open Windows)
static func build_observation_watchtower(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.name = "ObservationWatchtower"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var wood := _get_mat("wood", Color(0.48, 0.40, 0.30))
	var steel := _get_mat("steel", Color(0.36, 0.38, 0.40))
	var camo := _get_mat("camo", Color(0.28, 0.36, 0.22))

	var h := 13.0
	var concrete := _get_mat("concrete", Color(0.70, 0.68, 0.64))
	for sx in [-2.0, 2.0]:
		for sz in [-2.0, 2.0]:
			# Deep concrete pier embedded 5.5m into terrain
			_add_box(root, Vector3(1.2, 5.5, 1.2), Vector3(sx, -2.4, sz), concrete, true)
			_add_box(root, Vector3(0.35, h, 0.35), Vector3(sx, h * 0.5, sz), wood, true)
	for y in [3.5, 7.0, 10.5]:
		_add_box(root, Vector3(4.2, 0.2, 0.2), Vector3(0.0, y, 2.0), wood, true)
		_add_box(root, Vector3(4.2, 0.2, 0.2), Vector3(0.0, y, -2.0), wood, true)
		_add_box(root, Vector3(0.2, 0.2, 4.2), Vector3(2.0, y, 0.0), wood, true)
		_add_box(root, Vector3(0.2, 0.2, 4.2), Vector3(-2.0, y, 0.0), wood, true)

	# Upper Cabin Platform Floor
	_add_box(root, Vector3(4.8, 0.3, 4.8), Vector3(0.0, h, 0.0), wood, true)
	# 4 Cabin Corner Posts
	for cx in [-2.2, 2.2]:
		for cz in [-2.2, 2.2]:
			_add_box(root, Vector3(0.25, 2.4, 0.25), Vector3(cx, h + 1.2, cz), steel, true)
	# Half-height parapet (leaves 1.4m high open 360-degree window gap to fly in and out!)
	for side in [-2.2, 2.2]:
		_add_box(root, Vector3(4.4, 0.9, 0.12), Vector3(0.0, h + 0.45, side), camo, true)
		_add_box(root, Vector3(0.12, 0.9, 4.4), Vector3(side, h + 0.45, 0.0), camo, true)
	# Overhanging Pyramid Roof
	_add_box(root, Vector3(5.4, 0.3, 5.4), Vector3(0.0, h + 2.5, 0.0), wood, true)
	return root


## 16. Military Container Field HQ
static func build_military_container_hq(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.name = "MilitaryContainerHQ"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var camo := _get_mat("camo", Color(0.30, 0.38, 0.24))
	var steel := _get_mat("steel", Color(0.34, 0.36, 0.38))
	var concrete := _get_mat("concrete", Color(0.72, 0.70, 0.66))

	# Deep reinforced concrete footings (embedded 5.5m into terrain)
	_add_box(root, Vector3(1.2, 5.5, 3.2), Vector3(-5.5, -2.0, 0.0), concrete, true)
	_add_box(root, Vector3(1.2, 5.5, 3.2), Vector3(5.5, -2.0, 0.0), concrete, true)

	# Main 40ft Command Container
	_add_box(root, Vector3(12.2, 2.6, 2.5), Vector3(0.0, 2.1, 0.0), camo, true)
	# Upper Sunshade Camo Canopy (1.2m gap above roof!)
	_add_box(root, Vector3(13.5, 0.1, 4.0), Vector3(0.0, 4.2, 0.0), camo, false)
	# Radio Whip Mast (12m high)
	_add_cyl(root, 0.08, 12.0, Vector3(-5.5, 9.0, 1.2), steel, Vector3.ZERO, true)
	return root


## 17. ZU-23 Air Defense Emplacement
static func build_zu23_aa_emplacement(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.name = "ZU23AAEmplacement"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var sandbag := _get_mat("sandbag", Color(0.58, 0.52, 0.38))
	var steel := _get_mat("steel", Color(0.30, 0.34, 0.28))

	# Octagonal Sandbag Wall with deep foundation pad (4.5m deep)
	var r := 4.2
	_add_cyl(root, r + 0.8, 4.5, Vector3(0.0, -2.0, 0.0), sandbag, Vector3.ZERO, true)
	for i in range(8):
		var a := float(i) * TAU / 8.0
		var p := Vector3(sin(a) * r, 0.75, cos(a) * r)
		var b := _add_box(root, Vector3(3.2, 1.5, 1.2), p, sandbag, true)
		b.rotation.y = a

	# Gun Mount Pedestal & Dual Barrels
	_add_cyl(root, 0.9, 1.2, Vector3(0.0, 0.6, 0.0), steel, Vector3.ZERO, true)
	_add_cyl(root, 0.08, 3.8, Vector3(-0.25, 2.2, 1.2), steel, Vector3(0.45, 0.0, 0.0), false)
	_add_cyl(root, 0.08, 3.8, Vector3(0.25, 2.2, 1.2), steel, Vector3(0.45, 0.0, 0.0), false)
	return root


## 18. Burnt T-72 Tank Wreckage Obstacle
static func build_burnt_tank_hull(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.name = "BurntTankHull"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var rust := _get_mat("rust", Color(0.36, 0.25, 0.20))
	var steel := _get_mat("steel", Color(0.22, 0.22, 0.24))

	# Main Hull and buried earth anchor pad
	var dirt_concrete := _get_mat("concrete", Color(0.48, 0.44, 0.38))
	_add_box(root, Vector3(4.8, 4.0, 8.2), Vector3(0.0, -1.8, 0.0), dirt_concrete, true)
	_add_box(root, Vector3(3.8, 1.4, 7.2), Vector3(0.0, 0.9, 0.0), rust, true)
	# Tracks
	_add_box(root, Vector3(0.8, 1.1, 7.4), Vector3(-2.0, 0.65, 0.0), steel, true)
	_add_box(root, Vector3(0.8, 1.1, 7.4), Vector3(2.0, 0.65, 0.0), steel, true)
	# Displaced Blown Turret resting tilted on hull (freestyle obstacle)
	var turret := _add_cyl(root, 1.6, 1.2, Vector3(0.6, 2.3, -0.4), rust, Vector3(0.3, 0.4, 0.2), true)
	# 125mm Main Gun Barrel pointing into sky
	_add_cyl(root, 0.15, 5.5, Vector3(1.2, 4.0, 1.5), rust, Vector3(0.8, 0.2, 0.0), true)
	return root


## 19. Burnt BTR APC Hull
static func build_burnt_btr_hull(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.name = "BurntBTRHull"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var rust := _get_mat("rust", Color(0.38, 0.26, 0.20))
	var dirt_concrete := _get_mat("concrete", Color(0.48, 0.44, 0.38))
	# Buried earth anchor pad
	_add_box(root, Vector3(3.8, 4.0, 8.4), Vector3(0.0, -1.8, 0.0), dirt_concrete, true)
	# Slanted APC Hull
	_add_box(root, Vector3(3.0, 1.5, 7.8), Vector3(0.0, 1.0, 0.0), rust, true)
	_add_box(root, Vector3(2.2, 0.8, 4.5), Vector3(0.0, 2.0, -0.6), rust, true)
	return root


## 20. Pipeline Overpass & Valve Loop
static func build_pipeline_overpass(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.name = "PipelineOverpass"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var rust := _get_mat("rust", Color(0.55, 0.35, 0.25))
	var steel := _get_mat("steel", Color(0.36, 0.38, 0.42))
	var hazard := _get_mat("hazard")

	var span := 20.0
	var h := 7.0

	var concrete := _get_mat("concrete", Color(0.70, 0.68, 0.64))
	_add_box(root, Vector3(2.0, 5.5, 2.0), Vector3(-span * 0.5, -2.4, 0.0), concrete, true)
	_add_box(root, Vector3(2.0, 5.5, 2.0), Vector3(span * 0.5, -2.4, 0.0), concrete, true)
	_add_box(root, Vector3(1.2, h, 1.2), Vector3(-span * 0.5, h * 0.5, 0.0), steel, true)
	_add_box(root, Vector3(1.2, h, 1.2), Vector3(span * 0.5, h * 0.5, 0.0), steel, true)
	# Heavy Overhead Pipe (Diameter 1.2m at Y=6.5m)
	_add_cyl(root, 0.6, span, Vector3(0.0, h, 0.0), rust, Vector3(0.0, 0.0, PI * 0.5), true)
	_add_box(root, Vector3(span, 0.3, 0.3), Vector3(0.0, h - 0.9, 0.0), hazard, false)
	return root


## 21. Concrete Blast Wall Chicane (Slalom Alley)
static func build_concrete_blast_wall_lane(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.name = "ConcreteBlastWallLane"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var concrete := _get_mat("concrete", Color(0.74, 0.72, 0.68))
	var hazard := _get_mat("hazard")

	# 5 Staggered T-walls forming a high-speed bank-turn chicane (embedded 5m into terrain)
	for i in range(5):
		var pz := float(i - 2) * 8.0
		var px := (float(i % 2) - 0.5) * 6.0
		_add_box(root, Vector3(5.5, 8.5, 0.8), Vector3(px, 1.75 - 2.5, pz), concrete, true)
		_add_box(root, Vector3(5.5, 0.3, 0.65), Vector3(px, 3.5, pz), hazard, false)
	return root


## 22. Electronic Warfare Jammer Mast
static func build_ew_jammer_mast(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.name = "EWJammerMast"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var steel := _get_mat("steel", Color(0.38, 0.40, 0.44))
	var concrete := _get_mat("concrete", Color(0.70, 0.68, 0.64))
	var h := 22.0

	# Deep concrete base plinth (embedded 5.5m into terrain)
	_add_box(root, Vector3(4.0, 5.5, 4.0), Vector3(0.0, -2.2, 0.0), concrete, true)
	_add_cyl(root, 0.4, h, Vector3(0.0, h * 0.5 + 0.4, 0.0), steel, Vector3.ZERO, true)
	for y in [8.0, 14.0, 20.0]:
		_add_box(root, Vector3(6.5, 0.25, 0.25), Vector3(0.0, y, 0.0), steel, true)
		_add_box(root, Vector3(0.25, 0.25, 6.5), Vector3(0.0, y, 0.0), steel, true)
	return root


## 23. Camouflage Vehicle Pavilion (Open 4-Pillar Fly-Through Canopy)
static func build_camo_vehicle_shed(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.name = "CamoVehicleShed"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var camo := _get_mat("camo", Color(0.28, 0.36, 0.22))
	var steel := _get_mat("steel", Color(0.35, 0.38, 0.40))

	var w := 12.0
	var d := 10.0
	var h := 5.2

	# 4 Corner Steel Posts with 5.5m deep concrete foundation piers
	var concrete := _get_mat("concrete", Color(0.70, 0.68, 0.64))
	for cx in [-w * 0.5, w * 0.5]:
		for cz in [-d * 0.5, d * 0.5]:
			_add_box(root, Vector3(1.2, 5.5, 1.2), Vector3(cx, -2.4, cz), concrete, true)
			_add_box(root, Vector3(0.4, h, 0.4), Vector3(cx, h * 0.5, cz), steel, true)

	# Roof Perimeter Frame
	_add_box(root, Vector3(w, 0.3, 0.3), Vector3(0.0, h, d * 0.5), steel, true)
	_add_box(root, Vector3(w, 0.3, 0.3), Vector3(0.0, h, -d * 0.5), steel, true)
	_add_box(root, Vector3(0.3, 0.3, d), Vector3(w * 0.5, h, 0.0), steel, true)
	_add_box(root, Vector3(0.3, 0.3, d), Vector3(-w * 0.5, h, 0.0), steel, true)
	# Tensioned Camo Canvas Tarp
	_add_box(root, Vector3(w + 1.0, 0.15, d + 1.0), Vector3(0.0, h + 0.1, 0.0), camo, true)
	return root


## 24. Forward Repair Station & Overhead Gantry Crane Frame
static func build_forward_repair_station(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.name = "ForwardRepairStation"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var steel := _get_mat("steel", Color(0.36, 0.40, 0.44))
	var hazard := _get_mat("hazard")
	var concrete := _get_mat("concrete", Color(0.72, 0.70, 0.66))

	var w := 10.0
	var h := 7.0

	# 5.0m Deep Concrete Foundation Slab
	_add_box(root, Vector3(w + 4.0, 5.0, 14.0), Vector3(0.0, -2.35, 0.0), concrete, true)
	# Overhead A-frame Gantry Crane (10m wide x 6.5m clear fly-through bay)
	_add_box(root, Vector3(0.6, h, 0.6), Vector3(-w * 0.5, h * 0.5, 0.0), steel, true)
	_add_box(root, Vector3(0.6, h, 0.6), Vector3(w * 0.5, h * 0.5, 0.0), steel, true)
	_add_box(root, Vector3(w + 1.5, 0.8, 0.8), Vector3(0.0, h, 0.0), hazard, true)
	return root


## 25. Industrial Electrical Substation Maze
static func build_generator_substation(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.name = "GeneratorSubstation"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var steel := _get_mat("steel", Color(0.32, 0.36, 0.40))
	var rust := _get_mat("rust", Color(0.50, 0.34, 0.24))
	var concrete := _get_mat("concrete", Color(0.72, 0.70, 0.66))

	# 5.0m Deep Concrete Foundation Slab
	_add_box(root, Vector3(14.5, 5.0, 12.5), Vector3(0.0, -2.35, 0.0), concrete, true)
	# 3 Heavy Transformer Units
	_add_box(root, Vector3(3.0, 3.2, 2.5), Vector3(-3.5, 1.75, 0.0), steel, true)
	_add_box(root, Vector3(3.0, 3.2, 2.5), Vector3(3.5, 1.75, 0.0), rust, true)
	return root


## 26. Dug-In Artillery Firing Position
static func build_artillery_firing_position(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.name = "ArtilleryFiringPosition"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var wood := _get_mat("wood", Color(0.46, 0.38, 0.28))
	var sandbag := _get_mat("sandbag", Color(0.58, 0.52, 0.38))
	var camo := _get_mat("camo", Color(0.30, 0.38, 0.24))

	# 4.5m Deep Foundation Base
	_add_box(root, Vector3(13.0, 4.5, 12.0), Vector3(0.0, -2.1, 0.0), wood, true)
	_add_box(root, Vector3(12.0, 1.8, 1.2), Vector3(0.0, 0.9, -5.0), wood, true)
	_add_box(root, Vector3(1.2, 1.8, 10.0), Vector3(-5.5, 0.9, 0.0), sandbag, true)
	_add_box(root, Vector3(1.2, 1.8, 10.0), Vector3(5.5, 0.9, 0.0), sandbag, true)
	# Camo canopy over rear
	_add_box(root, Vector3(11.0, 0.1, 5.0), Vector3(0.0, 3.0, -2.5), camo, false)
	return root


## 27. Geodesic Radar Dome Stilt Platform (Elevated with Fly-Under Crawlway)
static func build_air_defense_radar_dome(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.name = "AirDefenseRadarDome"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var concrete := _get_mat("concrete", Color(0.74, 0.72, 0.68))
	var steel := _get_mat("steel", Color(0.38, 0.42, 0.46))

	# 4 Heavy Concrete Stilt Legs with 5.5m deep foundation piers
	for cx in [-3.5, 3.5]:
		for cz in [-3.5, 3.5]:
			_add_box(root, Vector3(1.4, 5.5, 1.4), Vector3(cx, -2.4, cz), concrete, true)
			_add_box(root, Vector3(0.8, 4.5, 0.8), Vector3(cx, 2.25, cz), concrete, true)

	# Elevated Deck Slab
	_add_box(root, Vector3(9.0, 0.5, 9.0), Vector3(0.0, 4.75, 0.0), concrete, true)
	# Radar Dome Shell
	_add_cyl(root, 3.8, 3.5, Vector3(0.0, 6.75, 0.0), steel, Vector3.ZERO, true)
	return root


## 28. Fortified Military Gate Portal (Dual-Lane Arched Gateway)
static func build_military_arch_portal(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.name = "MilitaryArchPortal"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var concrete := _get_mat("concrete", Color(0.70, 0.68, 0.64))
	var hazard := _get_mat("hazard")
	var steel := _get_mat("steel", Color(0.32, 0.35, 0.38))

	var h := 10.0
	# 3 Massive Concrete Piers with 5.5m deep foundation piers
	for px in [-7.0, 0.0, 7.0]:
		_add_box(root, Vector3(2.4, 5.5, 3.2), Vector3(px, -2.4, 0.0), concrete, true)
		_add_box(root, Vector3(2.0, h, 2.8), Vector3(px, h * 0.5, 0.0), concrete, true)

	# Overhead Command Catwalk
	_add_box(root, Vector3(16.5, 1.8, 3.2), Vector3(0.0, h + 0.9, 0.0), concrete, true)
	_add_box(root, Vector3(6.0, 0.3, 0.3), Vector3(-3.5, h - 0.5, 0.0), hazard, false)
	_add_box(root, Vector3(6.0, 0.3, 0.3), Vector3(3.5, h - 0.5, 0.0), hazard, false)
	_add_box(root, Vector3(16.5, 1.0, 0.1), Vector3(0.0, h + 2.3, 1.5), steel, false)
	return root


## 29. 3D Scaffolding Cube Maze (Freestyle Trick Playground)
static func build_scaffolding_freestyle_cube(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.name = "ScaffoldingFreestyleCube"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var steel := _get_mat("steel", Color(0.42, 0.44, 0.46))
	var wood := _get_mat("wood", Color(0.55, 0.45, 0.32))
	var hazard := _get_mat("hazard")
	var concrete := _get_mat("concrete", Color(0.70, 0.68, 0.64))

	var size := 10.0
	var h := 8.0

	# 5.0m Deep Concrete Foundation Slab
	_add_box(root, Vector3(size + 1.0, 5.0, size + 1.0), Vector3(0.0, -2.4, 0.0), concrete, true)

	# 9 Vertical Scaffolding Steel Poles
	for cx in [-size * 0.5, 0.0, size * 0.5]:
		for cz in [-size * 0.5, 0.0, size * 0.5]:
			_add_box(root, Vector3(0.2, h, 0.2), Vector3(cx, h * 0.5, cz), steel, true)

	# Horizontal Ledger Tubes at Y=4m and Y=8m
	for y in [4.0, 8.0]:
		for cx in [-size * 0.5, 0.0, size * 0.5]:
			_add_box(root, Vector3(0.15, 0.15, size), Vector3(cx, y, 0.0), steel, true)
		for cz in [-size * 0.5, 0.0, size * 0.5]:
			_add_box(root, Vector3(size, 0.15, 0.15), Vector3(0.0, y, cz), steel, true)

	# Wooden Plank Walkways (Leaves alternating cube cells 100% open for vertical and diagonal dives!)
	_add_box(root, Vector3(size * 0.5, 0.1, size * 0.5), Vector3(-size * 0.25, 4.05, -size * 0.25), wood, true)
	_add_box(root, Vector3(size * 0.5, 0.1, size * 0.5), Vector3(size * 0.25, 4.05, size * 0.25), wood, true)
	_add_box(root, Vector3(size * 0.5, 0.1, size * 0.5), Vector3(size * 0.25, 8.05, -size * 0.25), wood, true)
	# Hazard safety toe-boards
	_add_box(root, Vector3(size * 0.5, 0.2, 0.1), Vector3(-size * 0.25, 4.2, 0.0), hazard, false)
	return root


## 30. High Communications Spire with Guy Wire Anchors
static func build_communication_mast_guyed(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.name = "CommunicationMastGuyed"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var steel := _get_mat("steel", Color(0.40, 0.42, 0.45))
	var hazard := _get_mat("hazard")
	var concrete := _get_mat("concrete", Color(0.70, 0.68, 0.65))

	var h := 30.0
	# 5.5m Deep Concrete Center Pier
	_add_box(root, Vector3(3.5, 5.5, 3.5), Vector3(0.0, -2.25, 0.0), concrete, true)
	# Central Lattice Spire
	_add_cyl(root, 0.5, h, Vector3(0.0, h * 0.5 + 0.5, 0.0), steel, Vector3.ZERO, true)
	# 3 Guy Wire Anchor Blocks with 5.0m deep foundation blocks at 15m radius
	for a in [0.0, TAU / 3.0, TAU * 2.0 / 3.0]:
		var px: float = sin(float(a)) * 15.0
		var pz: float = cos(float(a)) * 15.0
		_add_box(root, Vector3(2.0, 5.0, 2.0), Vector3(px, -1.9, pz), concrete, true)
		# Guy cable
		_add_box(root, Vector3(0.08, 0.08, 16.0), Vector3(px * 0.5, h * 0.35, pz * 0.5), steel, false)

	# High Warning Beacons (Hazard stripes at top 6m)
	_add_box(root, Vector3(0.8, 1.5, 0.8), Vector3(0.0, h - 2.0, 0.0), hazard, false)
	_add_box(root, Vector3(0.8, 1.5, 0.8), Vector3(0.0, h, 0.0), hazard, false)
	return root


# =============================================================================
#  MAP SPAWNER: 30 DISTINCT STRUCTURES SPREAD ORGANICALLY WITHOUT CLUTTER
# =============================================================================

static func spawn_map_military_objects(root: Node3D, map_name: String) -> void:
	var terrain := load("res://scripts/util/frontline_terrain.gd")
	if terrain == null:
		return

	var site: Dictionary = terrain.HALL_SITES.get(map_name, {})
	var hc: Vector2 = site.get("center", Vector2.ZERO)
	var hhalf: Vector2 = site.get("half", Vector2(60.0, 40.0))
	var sp: Vector2 = site.get("spawn", Vector2(100.0, 80.0))
	var wl: float = terrain.water_level(map_name)

	# Deterministic 6x5 Grid covering the 700x700m playable space
	var rows := 6
	var cols := 5
	var x_min := -340.0
	var x_max := 340.0
	var z_min := -320.0
	var z_max := 320.0
	var dx := (x_max - x_min) / float(cols)
	var dz := (z_max - z_min) / float(rows)

	var picked: Array[Vector2] = []

	for r in range(rows):
		for c in range(cols):
			var idx := r * cols + c
			var cx := x_min + (float(c) + 0.5) * dx
			var cz := z_min + (float(r) + 0.5) * dz

			# Deterministic organic offset inside sector
			var off_x := sin(float(idx) * 1.7 + 0.5) * (dx * 0.28)
			var off_z := cos(float(idx) * 2.1 + 0.8) * (dz * 0.28)

			var found := false
			for rad in [0.0, 15.0, 30.0, 45.0, 60.0, 75.0]:
				var steps := 1 if rad == 0.0 else 12
				for s in range(steps):
					var ang := (TAU * float(s)) / float(steps) if steps > 1 else 0.0
					var px: float = cx + off_x + cos(ang) * rad
					var pz: float = cz + off_z + sin(ang) * rad

					if absf(px) > 360.0 or absf(pz) > 360.0:
						continue

					# Strict exclusion zone around all workshops/halls (no structures near workshops!)
					if is_near_workshop(map_name, px, pz):
						continue

					# Hero Hall clear zone (with 45m safety apron)
					if absf(px - hc.x) < hhalf.x + 45.0 and absf(pz - hc.y) < hhalf.y + 45.0:
						continue
					# Start spawn clearance (50m clear)
					if Vector2(px, pz).distance_to(sp) < 50.0:
						continue
					# Signature POIs (water tower, substation, burnt armour,
					# watch tower) keep a 40 m exclusion radius.
					var poi_blocked := false
					for poi in terrain._poi_positions:
						if Vector2(px, pz).distance_to(poi) < 40.0:
							poi_blocked = true
							break
					if poi_blocked:
						continue

					var h: float = float(terrain.height_at(map_name, px, pz))
					if map_name == "wetlands" and h < wl + 0.8:
						continue
					if map_name == "industrial":
						if absf(pz - (-15.0)) < 16.0: # Rail line
							continue
						if pz < -165.0: # Industrial bay water
							continue
					if map_name == "village":
						var rx := -170.0 + 35.0 * sin(pz * 0.008)
						if absf(px - rx) < 35.0: # River buffer
							continue
						# Keep village road clear
						if absf(pz - 58.0) < 18.0 and px > 20.0 and px < 190.0:
							continue

					# Check minimum clearance to all previously picked objects (>= 48m)
					var ok := true
					for prev in picked:
						if Vector2(px, pz).distance_to(prev) < 48.0:
							ok = false
							break
					if ok:
						picked.append(Vector2(px, pz))
						found = true
						break
				if found:
					break

	# Fallback if any sector was blocked
	var fb_tries := 0
	while picked.size() < 30 and fb_tries < 300:
		fb_tries += 1
		var fx := sin(float(fb_tries) * 11.3) * 320.0
		var fz := cos(float(fb_tries) * 17.7) * 300.0
		if map_name == "industrial" and fz < -155.0:
			fz = -155.0 + absf(fz + 155.0)
		var ok := true
		if absf(fx - hc.x) < hhalf.x + 45.0 and absf(fz - hc.y) < hhalf.y + 45.0:
			continue
		if is_near_workshop(map_name, fx, fz):
			continue
		if Vector2(fx, fz).distance_to(sp) < 50.0:
			continue
		var poi_blocked_fb := false
		for poi in terrain._poi_positions:
			if Vector2(fx, fz).distance_to(poi) < 40.0:
				poi_blocked_fb = true
				break
		if poi_blocked_fb:
			continue
		for prev in picked:
			if Vector2(fx, fz).distance_to(prev) < 42.0:
				ok = false
				break
		if ok:
			picked.append(Vector2(fx, fz))

	spawned_positions[map_name] = picked

	# Dispatch each of the 30 distinct military trick structures
	for i in range(mini(30, picked.size())):
		var p2 := picked[i]
		var y: float = float(terrain.footprint_surface_height(map_name, p2, 10.0, 10.0, 0.0)) - 0.15
		var pos3 := Vector3(p2.x, y, p2.y)
		var yaw := float(i) * 0.85 + sin(float(i) * 2.3) * 0.5

		match i:
			0: build_construction_skeleton_rubik(root, pos3, yaw)
			1: build_pipeline_powerloop_arch(root, pos3, yaw)
			2: build_fpv_slalom_gate_course(root, pos3, yaw)
			3: build_cooling_tower_dive_funnel(root, pos3, yaw)
			4: build_shipping_container_complex(root, pos3, yaw)
			5: build_concrete_pipe_culvert_course(root, pos3, yaw)
			6: build_high_voltage_pylon(root, pos3, yaw)
			7: build_damaged_hangar_arch(root, pos3, yaw)
			8: build_radar_relay_station(root, pos3, yaw)
			9: build_hardened_trench_bunker(root, pos3, yaw)
			10: build_dragons_teeth_line(root, pos3, yaw)
			11: build_checkpoint_fortification(root, pos3, yaw)
			12: build_sandbag_mortar_pit(root, pos3, yaw)
			13: build_fuel_storage_revetment(root, pos3, yaw)
			14: build_observation_watchtower(root, pos3, yaw)
			15: build_military_container_hq(root, pos3, yaw)
			16: build_zu23_aa_emplacement(root, pos3, yaw)
			17: build_burnt_tank_hull(root, pos3, yaw)
			18: build_burnt_btr_hull(root, pos3, yaw)
			19: build_pipeline_overpass(root, pos3, yaw)
			20: build_concrete_blast_wall_lane(root, pos3, yaw)
			21: build_ew_jammer_mast(root, pos3, yaw)
			22: build_camo_vehicle_shed(root, pos3, yaw)
			23: build_forward_repair_station(root, pos3, yaw)
			24: build_generator_substation(root, pos3, yaw)
			25: build_artillery_firing_position(root, pos3, yaw)
			26: build_air_defense_radar_dome(root, pos3, yaw)
			27: build_military_arch_portal(root, pos3, yaw)
			28: build_scaffolding_freestyle_cube(root, pos3, yaw)
			29: build_communication_mast_guyed(root, pos3, yaw)

	print("[MilitaryStructures] Spawned 30 non-overlapping freestyle military structures on ", map_name)
