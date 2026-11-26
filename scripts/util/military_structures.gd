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
			if p.distance_to(Vector2(50.0, 80.0)) < 56.0: # Hero hall
				return true
			if p.distance_to(Vector2(-105.0, -98.0)) < 52.0: # factory_complex.glb
				return true
			if p.distance_to(Vector2(-92.0, 56.0)) < 44.0: # secondary hall
				return true
		"steppe":
			if p.distance_to(Vector2(88.0, 84.0)) < 56.0: # Hero hall
				return true
			if p.distance_to(Vector2(-28.0, 124.0)) < 48.0: # farm_complex.glb workshop
				return true
		"village":
			if p.distance_to(Vector2(96.0, 52.0)) < 54.0: # Hero hall
				return true
			if p.distance_to(Vector2(54.0, -96.0)) < 44.0: # village_house.glb
				return true
		"wetlands":
			if p.distance_to(Vector2(58.0, 48.0)) < 54.0: # Hero hall
				return true
			if p.distance_to(Vector2(-56.0, -118.0)) < 44.0: # wetlands_dock.glb
				return true
		"promzona_plavni":
			if p.distance_to(Vector2(52.0, -180.0)) < 62.0: # Promzona hero hall
				return true
			if p.distance_to(Vector2(-105.0, -245.0)) < 54.0: # factory_complex.glb
				return true
			if p.distance_to(Vector2(42.0, 165.0)) < 58.0: # Plavni hall/outpost
				return true
			if p.distance_to(Vector2(-56.0, 145.0)) < 46.0: # wetlands dock pad
				return true
			if p.distance_to(Vector2(-155.0, 110.0)) < 38.0: # half-sunk barge
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
		mat: Material, collide: bool = true, rot: Vector3 = Vector3.ZERO) -> Node3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	if collide:
		# The body owns the whole transform so the collision shape and the
		# visible mesh stay in lockstep even when the primitive is rotated.
		var body := StaticBody3D.new()
		body.position = pos
		body.rotation = rot
		body.collision_layer = 1
		body.collision_mask = 1
		mi.position = Vector3.ZERO
		mi.rotation = Vector3.ZERO
		body.add_child(mi)
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		body.add_child(cs)
		parent.add_child(body)
		return body
	else:
		parent.add_child(mi)
		return mi


static func _add_cyl(parent: Node3D, radius: float, height: float,
		pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO, collide: bool = true) -> Node3D:
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
		mi.rotation = Vector3.ZERO
		body.add_child(mi)
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = height
		cs.shape = shape
		body.add_child(cs)
		parent.add_child(body)
		return body
	else:
		parent.add_child(mi)
		return mi


## True hollow pass-through pipe: faceted wall slabs only, no end caps, so a
## drone can fly straight through the bore.  Wall slabs get matching rotated
## collision; hazard rings (non-colliding) mark both mouths when requested.
static func build_hollow_pipe(parent: Node3D, pos: Vector3, yaw: float,
		length: float = 10.0, inner_radius: float = 2.2,
		wall_thickness: float = 0.35, mat: Material = null,
		rim_mat: Material = null, segs: int = 12) -> Node3D:
	var root := Node3D.new()
	root.name = "HollowPipe"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var pipe_mat := mat if mat != null else \
			_get_mat("concrete", Color(0.76, 0.74, 0.70))
	var r_outer := inner_radius + wall_thickness
	var r_mid := inner_radius + wall_thickness * 0.5
	var seg_count := maxi(segs, 6)

	for s in range(seg_count):
		var a := float(s) * TAU / float(seg_count)
		var seg_w := (TAU * r_outer / float(seg_count)) * 1.04
		var px := sin(a) * r_mid
		var py := cos(a) * r_mid
		_add_box(root, Vector3(seg_w, wall_thickness, length),
				Vector3(px, py, 0.0), pipe_mat, true, Vector3(0.0, 0.0, -a))

	if rim_mat != null:
		for end_z in [-length * 0.5, length * 0.5]:
			for s in range(seg_count):
				var a := float(s) * TAU / float(seg_count)
				var seg_w := (TAU * r_outer / float(seg_count)) * 1.06
				var px := sin(a) * r_outer
				var py := cos(a) * r_outer
				_add_box(root, Vector3(seg_w, 0.25, 0.25),
						Vector3(px, py, end_z), rim_mat, false,
						Vector3(0.0, 0.0, -a))
	return root


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

	var w := 24.0
	var d := 20.0
	var h_floor := 5.6
	var total_h := h_floor * 3.0

	# 12 Massive Perimeter & Interior Columns (7.5m+ fly-through bays between them)
	var col_size := Vector3(0.85, total_h, 0.85)
	for cx in [-w * 0.5, -w * 0.17, w * 0.17, w * 0.5]:
		for cz in [-d * 0.5, 0.0, d * 0.5]:
			_add_box(root, col_size, Vector3(cx, total_h * 0.5, cz), concrete, true)

	# Floor 1 Slab (Deep concrete foundation skirt, embedded 5.5m into terrain)
	_add_box(root, Vector3(w + 1.4, 5.5, d + 1.4), Vector3(0.0, -2.35, 0.0), concrete, true)

	# Floor 2 Slab with Large Left Vertical Dive Cutout (8m x 8m gap)
	_add_box(root, Vector3(w * 0.5, 0.42, d), Vector3(w * 0.25, h_floor, 0.0), concrete, true)
	_add_box(root, Vector3(w * 0.5, 0.42, d * 0.3), Vector3(-w * 0.25, h_floor, d * 0.35), concrete, true)
	_add_box(root, Vector3(w * 0.5, 0.42, d * 0.3), Vector3(-w * 0.25, h_floor, -d * 0.35), concrete, true)
	_add_box(root, Vector3(0.25, 0.48, d * 0.4), Vector3(0.0, h_floor + 0.12, 0.0), hazard, false)

	# Floor 3 Slab with Large Right Vertical Dive Cutout (8m x 8m gap)
	_add_box(root, Vector3(w * 0.5, 0.42, d), Vector3(-w * 0.25, h_floor * 2.0, 0.0), concrete, true)
	_add_box(root, Vector3(w * 0.5, 0.42, d * 0.3), Vector3(w * 0.25, h_floor * 2.0, d * 0.35), concrete, true)
	_add_box(root, Vector3(w * 0.5, 0.42, d * 0.3), Vector3(w * 0.25, h_floor * 2.0, -d * 0.35), concrete, true)
	_add_box(root, Vector3(0.25, 0.48, d * 0.4), Vector3(0.0, h_floor * 2.0 + 0.12, 0.0), hazard, false)

	# Roof Slab with Huge Open Center Skylight (16m x 12m central dive hole from 17m altitude)
	_add_box(root, Vector3(w, 0.42, 4.0), Vector3(0.0, total_h, d * 0.5 - 2.0), concrete, true)
	_add_box(root, Vector3(w, 0.42, 4.0), Vector3(0.0, total_h, -d * 0.5 + 2.0), concrete, true)
	_add_box(root, Vector3(4.0, 0.42, d - 8.0), Vector3(-w * 0.5 + 2.0, total_h, 0.0), concrete, true)
	_add_box(root, Vector3(4.0, 0.42, d - 8.0), Vector3(w * 0.5 - 2.0, total_h, 0.0), concrete, true)
	_add_box(root, Vector3(w - 8.0, 0.32, 0.32), Vector3(0.0, total_h + 0.2, d * 0.5 - 4.0), hazard, false)
	_add_box(root, Vector3(w - 8.0, 0.32, 0.32), Vector3(0.0, total_h + 0.2, -d * 0.5 + 4.0), hazard, false)
	# Perimeter Safety Guardrails
	_add_box(root, Vector3(w, 0.18, 0.18), Vector3(0.0, total_h + 1.1, d * 0.5), steel, false)
	_add_box(root, Vector3(w, 0.18, 0.18), Vector3(0.0, total_h + 1.1, -d * 0.5), steel, false)
	return root


## 2. Enlarged Industrial Pipe & Truss Power-Loop Arch (Overhead Gantry with Dual Gaps)
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

	var span := 28.0
	var h_arch := 18.0

	for side in [-1.0, 1.0]:
		var lx: float = float(side) * span * 0.5
		_add_box(root, Vector3(3.0, 6.0, 5.6), Vector3(lx, -2.6, 0.0), concrete, true)
		_add_box(root, Vector3(1.5, h_arch, 1.5), Vector3(lx, h_arch * 0.5, -1.8), steel, true)
		_add_box(root, Vector3(1.5, h_arch, 1.5), Vector3(lx, h_arch * 0.5, 1.8), steel, true)
		_add_box(root, Vector3(1.0, 1.2, 4.6), Vector3(lx, h_arch * 0.32, 0.0), steel, true)
		_add_box(root, Vector3(1.0, 1.2, 4.6), Vector3(lx, h_arch * 0.68, 0.0), steel, true)

	_add_cyl(root, 1.05, span + 6.0, Vector3(0.0, h_arch, -1.5), rust, Vector3(0.0, 0.0, PI * 0.5), true)
	_add_cyl(root, 0.80, span + 6.0, Vector3(0.0, h_arch + 3.0, 1.5), steel, Vector3(0.0, 0.0, PI * 0.5), true)
	_add_box(root, Vector3(span, 0.45, 0.45), Vector3(0.0, h_arch + 4.8, 0.0), steel, true)
	_add_box(root, Vector3(span, 0.50, 0.50), Vector3(0.0, h_arch - 1.6, 0.0), hazard, true)
	return root


## 3. Freestyle Slalom Gate Runway (4 Arched Gates for Knife-Edge Banking)
static func build_fpv_slalom_gate_course(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.name = "FreestyleSlalomGateCourse"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var hazard := _get_mat("hazard")
	var steel := _get_mat("steel", Color(0.32, 0.34, 0.36))

	var gate_w := 5.2
	var gate_h := 4.2
	var gate_thick := 0.34

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

		# Top hazard banner: the old dark camo banner vanished into the ground
		# palette at range and read as a floating black slab.  Hazard stripes
		# keep the gate readable from several hundred metres.
		_add_box(root, Vector3(gate_w * 0.94, 0.75, 0.07), Vector3(gx, gate_h + 0.45, gz), hazard, false)
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

	var h := 32.0
	var r := 6.6
	var segs := 16

	# Deep foundation collar embedded 7m into terrain (prevents hovering on slopes)
	_add_cyl(root, r + 0.6, 7.0, Vector3(0.0, -3.3, 0.0), concrete, Vector3.ZERO, true)

	# Hollow faceted cylinder wall with 5.2m wide x 5.0m tall exit breaches at N & S
	for s in range(segs):
		var ang := float(s) * TAU / float(segs)
		var is_breach := (s == 0 or s == 1 or s == segs / 2 or s == segs / 2 + 1)

		var px := sin(ang) * r
		var pz := cos(ang) * r
		var panel_w := (TAU * r / float(segs)) * 1.05

		if is_breach:
			var wall_h := h - 5.0
			_add_box(root, Vector3(panel_w, wall_h, 0.55),
					Vector3(px, 5.0 + wall_h * 0.5, pz), concrete, true,
					Vector3(0.0, ang, 0.0))
			_add_box(root, Vector3(panel_w, 0.5, 0.6),
					Vector3(px, 5.0, pz), hazard, true,
					Vector3(0.0, ang, 0.0))
		else:
			var wall_h := h + 6.5
			_add_box(root, Vector3(panel_w, wall_h, 0.55),
					Vector3(px, (h - 6.5) * 0.5, pz), concrete, true,
					Vector3(0.0, ang, 0.0))

	for s in range(segs):
		var ang := float(s) * TAU / float(segs)
		var px := sin(ang) * r
		var pz := cos(ang) * r
		var panel_w := (TAU * r / float(segs)) * 1.08
		_add_box(root, Vector3(panel_w, 0.6, 0.85), Vector3(px, h, pz),
				hazard, true, Vector3(0.0, ang, 0.0))

	_add_cyl(root, 0.45, h + 3.0, Vector3(r + 0.85, h * 0.5, 0.0), rust, Vector3.ZERO, true)
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

	var r_outer := 2.75
	var r_inner := 2.40
	var pipe_len := 8.0
	var segs := 14

	# 3 Concrete Culverts in a row with slight curve
	for p in range(3):
		var pz := float(p - 1.0) * 11.0
		var px := sin(float(p) * 0.7) * 2.5
		var pipe_yaw := float(p - 1.0) * 0.15

		var pipe_node := Node3D.new()
		pipe_node.position = Vector3(px, r_outer, pz)
		pipe_node.rotation.y = pipe_yaw
		root.add_child(pipe_node)

		# Deep Concrete Support Cradle Base.  With this offset its top is at
		# -r_outer + 0.15 (-2.60), i.e. 0.20 m below the inner bore floor
		# (-r_inner = -2.40), so the fly-through stays completely open.
		_add_box(pipe_node, Vector3(r_outer * 2.4, 5.0, pipe_len * 0.95),
				Vector3(0.0, -r_outer - 2.35, 0.0), concrete, true)

		# Hollow Barrel Segments (Leaves interior bore completely open)
		for s in range(segs):
			var a := float(s) * TAU / float(segs)
			var seg_w := (TAU * r_outer / float(segs)) * 1.04
			var sx := sin(a) * ((r_outer + r_inner) * 0.5)
			var sy := cos(a) * ((r_outer + r_inner) * 0.5)
			_add_box(pipe_node, Vector3(seg_w, 0.35, pipe_len),
					Vector3(sx, sy, 0.0), concrete, true,
					Vector3(0.0, 0.0, -a))

		# High-visibility Hazard Lip at entrances
		for end_z in [-pipe_len * 0.5, pipe_len * 0.5]:
			for s in range(segs):
				var a := float(s) * TAU / float(segs)
				var seg_w := (TAU * r_outer / float(segs)) * 1.06
				var sx := sin(a) * r_outer
				var sy := cos(a) * r_outer
				_add_box(pipe_node, Vector3(seg_w, 0.25, 0.25),
						Vector3(sx, sy, end_z), hazard, false,
						Vector3(0.0, 0.0, -a))
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
			# Splay slope: pass the rotation in so the collider follows it.
			_add_box(root, Vector3(0.35, 16.0, 0.35),
					Vector3(sx * 2.5, 8.0, sz * 2.5), steel, true,
					Vector3(-sz * 0.09, 0.0, sx * 0.09))

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

	var length := 34.0
	var w := 22.0
	var h := 10.6

	# Deep Concrete Foundation Curbs (embedded 6m into terrain)
	_add_box(root, Vector3(2.2, 6.0, length + 1.2), Vector3(-w * 0.5, -2.4, 0.0), concrete, true)
	_add_box(root, Vector3(2.2, 6.0, length + 1.2), Vector3(w * 0.5, -2.4, 0.0), concrete, true)
	_add_box(root, Vector3(w, 5.5, length), Vector3(0.0, -2.6, 0.0), concrete, true)

	# 9 Curved Steel Truss Ribs
	for i in range(9):
		var rz := float(i - 4) * (length / 8.0)
		_add_box(root, Vector3(0.55, 5.8, 0.55), Vector3(-w * 0.5, 2.9, rz), steel, true)
		_add_box(root, Vector3(0.55, 5.8, 0.55), Vector3(w * 0.5, 2.9, rz), steel, true)
		_add_box(root, Vector3(12.2, 0.45, 0.55),
				Vector3(-w * 0.25, 8.2, rz), steel, true,
				Vector3(0.0, 0.0, -0.42))
		_add_box(root, Vector3(12.2, 0.45, 0.55),
				Vector3(w * 0.25, 8.2, rz), steel, true,
				Vector3(0.0, 0.0, 0.42))

	# Corrugated Roof Panels leaving 16m central skylight dive bay
	_add_box(root, Vector3(w * 0.5, 0.16, 9.0), Vector3(-w * 0.26, 8.4, 12.5), corrugated, true)
	_add_box(root, Vector3(w * 0.5, 0.16, 9.0), Vector3(w * 0.26, 8.4, 12.5), corrugated, true)
	_add_box(root, Vector3(w * 0.5, 0.16, 9.0), Vector3(-w * 0.26, 8.4, -12.5), corrugated, true)
	_add_box(root, Vector3(w * 0.5, 0.16, 9.0), Vector3(w * 0.26, 8.4, -12.5), corrugated, true)

	_add_box(root, Vector3(w, 0.4, 0.4), Vector3(0.0, h, length * 0.5), hazard, false)
	_add_box(root, Vector3(w, 0.4, 0.4), Vector3(0.0, h, -length * 0.5), hazard, false)
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
		_add_box(root, Vector3(1.8, 0.28, 0.28),
				Vector3(px, h + 3.0 + py, 0.0), hazard, true,
				Vector3(0.0, 0.0, -a))
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
		_add_box(root, Vector3(3.0, 1.6, 1.4), p, sandbag, true,
				Vector3(0.0, a, 0.0))

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
		_add_box(root, Vector3(3.2, 1.5, 1.2), p, sandbag, true,
				Vector3(0.0, a, 0.0))

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

	var h := 15.0
	# 3 Massive Concrete Piers forming twin 9m x 14.5m portals
	for px in [-11.5, 0.0, 11.5]:
		_add_box(root, Vector3(3.2, 6.0, 4.2), Vector3(px, -2.5, 0.0), concrete, true)
		_add_box(root, Vector3(2.6, h, 3.6), Vector3(px, h * 0.5, 0.0), concrete, true)

	# Overhead Command Catwalk
	_add_box(root, Vector3(27.0, 2.2, 4.0), Vector3(0.0, h + 1.1, 0.0), concrete, true)
	_add_box(root, Vector3(9.0, 0.4, 0.4), Vector3(-5.75, h - 0.5, 0.0), hazard, false)
	_add_box(root, Vector3(9.0, 0.4, 0.4), Vector3(5.75, h - 0.5, 0.0), hazard, false)
	_add_box(root, Vector3(27.0, 1.2, 0.14), Vector3(0.0, h + 2.8, 1.9), steel, false)
	return root


## 29. Enlarged 3D Scaffolding Cube Maze (3-Tier Freestyle Trick Playground)
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

	var size := 16.0
	var h := 13.5

	_add_box(root, Vector3(size + 1.6, 5.5, size + 1.6), Vector3(0.0, -2.6, 0.0), concrete, true)

	for cx in [-size * 0.5, 0.0, size * 0.5]:
		for cz in [-size * 0.5, 0.0, size * 0.5]:
			_add_box(root, Vector3(0.28, h, 0.28), Vector3(cx, h * 0.5, cz), steel, true)

	for y in [4.5, 9.0, 13.5]:
		for cx in [-size * 0.5, 0.0, size * 0.5]:
			_add_box(root, Vector3(0.2, 0.2, size), Vector3(cx, y, 0.0), steel, true)
		for cz in [-size * 0.5, 0.0, size * 0.5]:
			_add_box(root, Vector3(size, 0.2, 0.2), Vector3(0.0, y, cz), steel, true)

	# Alternating 8m x 8m wooden decks leaving full vertical dive wells
	_add_box(root, Vector3(size * 0.5, 0.14, size * 0.5), Vector3(-size * 0.25, 4.56, -size * 0.25), wood, true)
	_add_box(root, Vector3(size * 0.5, 0.14, size * 0.5), Vector3(size * 0.25, 4.56, size * 0.25), wood, true)
	_add_box(root, Vector3(size * 0.5, 0.14, size * 0.5), Vector3(size * 0.25, 9.06, -size * 0.25), wood, true)
	_add_box(root, Vector3(size * 0.5, 0.14, size * 0.5), Vector3(-size * 0.25, 13.56, size * 0.25), wood, true)
	_add_box(root, Vector3(size * 0.5, 0.28, 0.14), Vector3(-size * 0.25, 4.75, 0.0), hazard, false)
	_add_box(root, Vector3(size * 0.5, 0.28, 0.14), Vector3(size * 0.25, 9.25, 0.0), hazard, false)
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


## 31. SAM Battery Launch Gantry (Angled Missile Canisters + Open Under-Arch)
static func build_sam_battery_gantry(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.name = "SamBatteryGantry"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var concrete := _get_mat("concrete", Color(0.68, 0.67, 0.63))
	var steel := _get_mat("steel", Color(0.32, 0.36, 0.38))
	var camo := _get_mat("camo", Color(0.28, 0.36, 0.22))
	var rust := _get_mat("rust", Color(0.46, 0.30, 0.20))
	var hazard := _get_mat("hazard")

	# Deep Concrete Launch Apron (22 x 18m)
	_add_box(root, Vector3(22.0, 6.0, 18.0), Vector3(0.0, -2.5, 0.0), concrete, true)
	# Flanking Reinforced Blast Walls
	for sx in [-1.0, 1.0]:
		_add_box(root, Vector3(2.0, 4.8, 17.5), Vector3(sx * 9.5, 2.4, 0.0), concrete, true)
		_add_box(root, Vector3(1.4, 15.0, 1.4), Vector3(sx * 5.8, 7.5, -2.0), steel, true)
		_add_box(root, Vector3(1.4, 15.0, 1.4), Vector3(sx * 5.8, 7.5, 2.0), steel, true)
		_add_box(root, Vector3(1.0, 1.0, 4.4), Vector3(sx * 5.8, 8.2, 0.0), steel, true)

	# Overhead Steel Cross-Gantry & Lower Hazard Arch (10.2m x 7.2m open pass-through)
	_add_box(root, Vector3(14.0, 1.3, 4.8), Vector3(0.0, 14.5, 0.0), steel, true)
	_add_box(root, Vector3(10.6, 0.5, 0.5), Vector3(0.0, 7.6, 2.1), hazard, false)
	_add_box(root, Vector3(10.6, 0.5, 0.5), Vector3(0.0, 7.6, -2.1), hazard, false)

	# Launcher Cradle Platform at Y=8.5m + 4 Angled Olive/Rust Missile Tubes
	_add_box(root, Vector3(9.6, 0.9, 5.2), Vector3(0.0, 8.6, 0.0), camo, true)
	for i in range(4):
		var tx := -3.3 + float(i) * 2.2
		_add_cyl(root, 0.65, 9.6, Vector3(tx, 11.4, 0.6), camo if i % 2 == 0 else rust,
				Vector3(-0.62, 0.0, 0.0), true)
	return root


## 32. Fortified Helipad Hangar (Open-Ended Armored Nave + Skylight Dive Bay)
static func build_fortified_helipad_hangar(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.name = "FortifiedHelipadHangar"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var concrete := _get_mat("concrete", Color(0.66, 0.65, 0.62))
	var corrugated := _get_mat("corrugated", Color(0.36, 0.40, 0.34))
	var steel := _get_mat("steel", Color(0.32, 0.35, 0.38))
	var hazard := _get_mat("hazard")

	var w := 22.0
	var l := 30.0
	var h := 11.5
	# Deep Foundation Pad
	_add_box(root, Vector3(w + 2.0, 6.0, l + 2.0), Vector3(0.0, -2.5, 0.0), concrete, true)
	# Lower Concrete Flank Walls & Tall Corrugated Upper Sidewalls (Ends completely open)
	for sx in [-1.0, 1.0]:
		_add_box(root, Vector3(2.2, 5.0, l), Vector3(sx * 10.0, 2.5, 0.0), concrete, true)
		_add_box(root, Vector3(0.5, h - 5.0, l), Vector3(sx * 10.0, 5.0 + (h - 5.0) * 0.5, 0.0), corrugated, true)
	# Armored Roof Wings with Wide Open Central Skylight (10m x 18m dive hole!)
	for sz in [-1.0, 1.0]:
		_add_box(root, Vector3(w + 0.6, 0.6, 10.0), Vector3(0.0, h, sz * 10.0), concrete, true)
		_add_box(root, Vector3(w - 3.0, 0.4, 0.4), Vector3(0.0, h - 0.5, sz * 5.0), hazard, false)
	# Internal Overhead Gantry Crane Beam at Y=8.5m for Inverted / Under-Arch Passes
	_add_box(root, Vector3(19.0, 0.9, 1.0), Vector3(0.0, 8.5, 0.0), hazard, true)
	_add_box(root, Vector3(2.4, 1.8, 2.4), Vector3(0.0, 7.3, 0.0), steel, true)
	return root


## 33. Bailey Military Truss Bridge (Under-Deck & Inside-Truss Dual Fly-Through)
static func build_bailey_truss_bridge(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.name = "BaileyTrussBridge"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var concrete := _get_mat("concrete", Color(0.68, 0.66, 0.62))
	var steel := _get_mat("steel", Color(0.36, 0.40, 0.42))
	var rust := _get_mat("rust", Color(0.46, 0.34, 0.24))
	var wood := _get_mat("wood", Color(0.45, 0.36, 0.26))
	var hazard := _get_mat("hazard")

	var span := 32.0
	var bw := 10.5
	var deck_y := 6.2
	var truss_h := 6.2

	# Deep Concrete Abutments Leaving 23m Wide x 5.8m High Open Span Underneath
	for sz in [-1.0, 1.0]:
		_add_box(root, Vector3(bw + 1.6, 12.0, 4.6), Vector3(0.0, 0.2, sz * 14.0), concrete, true)
		_add_box(root, Vector3(bw - 1.0, 0.4, 0.4), Vector3(0.0, deck_y + truss_h - 0.3, sz * (span * 0.5)), hazard, false)

	# Bridge Roadway Deck (Steel Stringers + Wood Planking)
	_add_box(root, Vector3(bw, 0.6, span), Vector3(0.0, deck_y, 0.0), steel, true)
	_add_box(root, Vector3(bw - 1.2, 0.16, span - 0.6), Vector3(0.0, deck_y + 0.38, 0.0), wood, true)

	# Side Lattice Trusses + Overhead Portal Cross-Frames
	for sx in [-1.0, 1.0]:
		_add_box(root, Vector3(0.6, 0.6, span), Vector3(sx * (bw * 0.5 - 0.3), deck_y + truss_h, 0.0), rust, true)
	for i in range(6):
		var pz := -span * 0.5 + float(i) * (span / 5.0)
		for sx in [-1.0, 1.0]:
			_add_box(root, Vector3(0.55, truss_h, 0.55), Vector3(sx * (bw * 0.5 - 0.3), deck_y + truss_h * 0.5, pz), steel, true)
		_add_box(root, Vector3(bw, 0.55, 0.55), Vector3(0.0, deck_y + truss_h, pz), steel, true)
	return root


## 34. Heavy GCI Radar Tower Complex (3 Stacked Fly-Through Lattice Bays + Dish)
static func build_heavy_radar_gci_complex(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.name = "HeavyRadarGciComplex"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var concrete := _get_mat("concrete", Color(0.70, 0.68, 0.65))
	var steel := _get_mat("steel", Color(0.38, 0.42, 0.44))
	var camo := _get_mat("camo", Color(0.30, 0.38, 0.24))
	var hazard := _get_mat("hazard")

	# Deep Concrete Podium with Open Pass-Through Tunnel Along X
	_add_box(root, Vector3(16.0, 5.5, 16.0), Vector3(0.0, -2.5, 0.0), concrete, true)
	for sz in [-1.0, 1.0]:
		_add_box(root, Vector3(15.0, 3.8, 3.8), Vector3(0.0, 1.9, sz * 5.6), concrete, true)
	_add_box(root, Vector3(15.0, 1.0, 15.0), Vector3(0.0, 4.3, 0.0), concrete, true)

	# 20m Tall Open 4-Leg Steel Lattice Tower (3 Open 8m Bays at Y=4.8..24.8)
	var base_y := 4.8
	var tower_h := 20.0
	var hw := 4.5
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_add_box(root, Vector3(0.65, tower_h, 0.65), Vector3(sx * hw, base_y + tower_h * 0.5, sz * hw), steel, true)
	for lvl_y in [base_y + 6.5, base_y + 13.0, base_y + tower_h]:
		for s in [-1.0, 1.0]:
			_add_box(root, Vector3(hw * 2.0 + 0.6, 0.45, 0.45), Vector3(0.0, lvl_y, s * hw), hazard, true)
			_add_box(root, Vector3(0.45, 0.45, hw * 2.0 + 0.6), Vector3(s * hw, lvl_y, 0.0), steel, true)

	# Rotating GCI Radar Reflector Crown
	_add_cyl(root, 1.6, 2.4, Vector3(0.0, base_y + tower_h + 1.2, 0.0), camo, Vector3.ZERO, true)
	_add_box(root, Vector3(14.0, 5.2, 0.45),
			Vector3(0.0, base_y + tower_h + 4.4, 0.0), steel, true,
			Vector3(-0.18, 0.0, 0.0))
	_add_box(root, Vector3(14.0, 0.4, 0.5), Vector3(0.0, base_y + tower_h + 6.9, -0.45), hazard, false)
	return root


## 35. Twin-Casemate Artillery Bunker Fortress (Open Central Tunnel + Dual Barrels)
static func build_artillery_bunker_complex(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.name = "ArtilleryBunkerComplex"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var concrete := _get_mat("concrete", Color(0.64, 0.63, 0.60))
	var sandbag := _get_mat("sandbag", Color(0.56, 0.50, 0.36))
	var steel := _get_mat("steel", Color(0.28, 0.30, 0.34))
	var camo := _get_mat("camo", Color(0.28, 0.36, 0.22))
	var hazard := _get_mat("hazard")

	# Deep Concrete Foundation Slab (26 x 18m)
	_add_box(root, Vector3(26.0, 6.0, 18.0), Vector3(0.0, -2.5, 0.0), concrete, true)
	# Left & Right Casemates Leaving Clear 7.5m x 5.2m Central Blast Corridor
	for sx in [-1.0, 1.0]:
		_add_box(root, Vector3(8.5, 5.5, 14.0), Vector3(sx * 8.0, 2.75, 0.0), concrete, true)
		_add_box(root, Vector3(2.2, 2.6, 16.0), Vector3(sx * 13.0, 1.3, 0.0), sandbag, true)
		# Long Heavy Coastal/Field Gun Barrel Protruding Out Front
		_add_cyl(root, 0.55, 11.0, Vector3(sx * 8.0, 4.1, 8.5), steel, Vector3(PI * 0.5 - 0.12, 0.0, 0.0), true)
		_add_box(root, Vector3(2.6, 2.2, 3.0), Vector3(sx * 8.0, 4.0, 5.5), camo, true)

	# Upper Armored Command Span Over Central Tunnel + Spotting Cupola
	_add_box(root, Vector3(26.0, 1.6, 13.0), Vector3(0.0, 6.3, 0.0), concrete, true)
	_add_cyl(root, 2.6, 2.0, Vector3(0.0, 8.1, -1.5), steel, Vector3.ZERO, true)
	_add_box(root, Vector3(7.5, 0.4, 0.4), Vector3(0.0, 5.3, 6.6), hazard, false)
	_add_box(root, Vector3(7.5, 0.4, 0.4), Vector3(0.0, 5.3, -6.6), hazard, false)
	return root


# =============================================================================
#  CIVILIAN PARK / PROMENADE FREESTYLE KIT (Uman + urban maps)
#  Warm limestone & sandstone, park timber, dark architectural steel, clean
#  concrete and hazard trim.  No camo tarps, no sandbag bunkers.  Every portal,
#  bore and oculus stays 100% fly-through clean; only real members get colliders.
# =============================================================================

## 36. Connected limestone + timber pergola arches on a gentle S-curve.
## Four 6.5 m wide x 5.2 m tall open portals, linked by continuous top timber
## beams for powerloops, consecutive gate flow and Split-S around the bars.
static func build_park_pergola_arches(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.name = "ParkPergolaArches"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var limestone := _get_mat("concrete", Color(0.88, 0.83, 0.72))
	var timber := _get_mat("wood", Color(0.74, 0.58, 0.40))
	var steel := _get_mat("steel", Color(0.22, 0.24, 0.26))
	var hazard := _get_mat("hazard")

	var half_w := 3.25
	var height := 5.2
	for i in range(4):
		var gz := float(i - 1.5) * 11.5
		var gx := sin(float(i) * 0.85) * 2.0
		var arch := Node3D.new()
		arch.name = "PergolaArch_%d" % i
		arch.position = Vector3(gx, 0.0, gz)
		arch.rotation.y = sin(float(i) * 0.85) * 0.16
		root.add_child(arch)

		for side in [-1.0, 1.0]:
			var px: float = side * half_w
			# Deep limestone pier embedded in the park lawn (never floating).
			_add_box(arch, Vector3(1.2, 4.5, 1.2), Vector3(px, -1.9, 0.0), limestone, true)
			_add_box(arch, Vector3(0.9, height, 0.9), Vector3(px, height * 0.5, 0.0), limestone, true)
			# Dark steel shoe where timber meets stone.
			_add_box(arch, Vector3(1.05, 0.35, 1.05), Vector3(px, height - 0.25, 0.0), steel, true)
			# Hazard trim on the inner face of each upright.
			_add_box(arch, Vector3(0.12, 1.1, 0.16), Vector3(px - side * 0.5, 1.5, 0.0), hazard, false)

		# Wide top timber lintel - the clear Split-S bar.
		_add_box(arch, Vector3(half_w * 2.0 + 1.1, 0.5, 0.85),
				Vector3(0.0, height, 0.0), timber, true)
		# Diagonal knee braces, aligned with a rotated collider.
		for side in [-1.0, 1.0]:
			_add_box(arch, Vector3(1.9, 0.22, 0.22),
					Vector3(side * (half_w - 0.7), height - 0.85, 0.0), timber, true,
					Vector3(0.0, 0.0, side * 0.62))

	# Continuous longitudinal timber runners tie the portals into one flow line.
	for side in [-1.0, 1.0]:
		_add_box(root, Vector3(0.55, 0.42, 37.0), Vector3(side * half_w, height + 0.15, 0.0),
				timber, true)
	return root


## 37. Twin offset architectural conduit pipes in low limestone cradles.
static func build_park_tunnel_pipes(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.name = "ParkTunnelPipes"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var limestone := _get_mat("concrete", Color(0.90, 0.85, 0.74))
	var timber := _get_mat("wood", Color(0.72, 0.56, 0.38))
	var steel := _get_mat("steel", Color(0.24, 0.26, 0.28))
	var hazard := _get_mat("hazard")

	var bore_y := 2.5
	for side in [-1.0, 1.0]:
		var px: float = side * 5.1
		# Low cradle: top at y = 0, below the bore floor (bore_y - 2.3 = 0.2).
		_add_box(root, Vector3(6.6, 1.4, 10.2), Vector3(px, -0.7, 0.0), limestone, true)
		var pipe := build_hollow_pipe(root, Vector3(px, bore_y, 0.0), 0.0,
				9.5, 2.3, 0.35, limestone, hazard, 14)
		pipe.name = "ParkConduit_%s" % ("L" if side < 0.0 else "R")

	# Connecting entry arch frame spanning both conduits (open central portal).
	for side in [-1.0, 1.0]:
		_add_box(root, Vector3(1.2, 8.6, 1.2), Vector3(side * 8.7, 1.4, -6.4), limestone, true)
		_add_box(root, Vector3(1.2, 4.0, 1.2), Vector3(side * 8.7, -1.6, -6.4), limestone, true)
	_add_box(root, Vector3(18.6, 0.7, 1.1), Vector3(0.0, 5.7, -6.4), timber, true)
	_add_box(root, Vector3(18.6, 0.3, 0.3), Vector3(0.0, 6.25, -6.4), steel, false)
	_add_box(root, Vector3(1.0, 0.25, 0.25), Vector3(0.0, 5.7, -6.4), hazard, false)
	return root


## 38. Open 16 m steel-and-timber observation / dive tower.
## Multi-tier 7.5 m open-bay Split-S decks and a 4.5 m octagonal oculus.
static func build_park_gazebo_tower(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.name = "ParkGazeboDiveTower"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var timber := _get_mat("wood", Color(0.76, 0.60, 0.42))
	var steel := _get_mat("steel", Color(0.20, 0.22, 0.24))
	var limestone := _get_mat("concrete", Color(0.88, 0.83, 0.72))
	var hazard := _get_mat("hazard")

	var half := 5.5
	var total_h := 16.0
	# 4 corner columns with deep stone footings.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_add_box(root, Vector3(1.4, 4.5, 1.4), Vector3(sx * half, -1.9, sz * half), limestone, true)
			_add_box(root, Vector3(0.7, total_h, 0.7), Vector3(sx * half, total_h * 0.5, sz * half), steel, true)

	# Two open 7.5 m bay decks: perimeter ring only, center fully open.
	for y_lvl in [5.6, 10.8]:
		_add_box(root, Vector3(half * 2.0 + 0.8, 0.45, 1.75), Vector3(0.0, y_lvl, half), timber, true)
		_add_box(root, Vector3(half * 2.0 + 0.8, 0.45, 1.75), Vector3(0.0, y_lvl, -half), timber, true)
		_add_box(root, Vector3(1.75, 0.45, 7.5), Vector3(half, y_lvl, 0.0), timber, true)
		_add_box(root, Vector3(1.75, 0.45, 7.5), Vector3(-half, y_lvl, 0.0), timber, true)
		# Open guardrail strips (non-colliding hazard trim).
		for side in [-1.0, 1.0]:
			_add_box(root, Vector3(half * 2.0, 0.16, 0.16), Vector3(0.0, y_lvl + 1.1, side * half), hazard, false)
			_add_box(root, Vector3(0.16, 0.16, half * 2.0), Vector3(side * half, y_lvl + 1.1, 0.0), hazard, false)

	# Top octagonal open-ring oculus (4.5 m clear inner aperture).
	var r_in := 2.25
	var r_out := 3.35
	var r_mid := (r_in + r_out) * 0.5
	var seg_w := (TAU * r_mid / 8.0) * 1.04
	for s in range(8):
		var a := float(s) * TAU / 8.0
		_add_box(root, Vector3(seg_w, 0.5, r_out - r_in),
				Vector3(sin(a) * r_mid, total_h, cos(a) * r_mid),
				timber, true, Vector3(0.0, a, 0.0))
	_add_box(root, Vector3(half * 2.0 + 1.2, 0.5, 0.5), Vector3(0.0, total_h, half), steel, true)
	_add_box(root, Vector3(half * 2.0 + 1.2, 0.5, 0.5), Vector3(0.0, total_h, -half), steel, true)
	return root


## 39. Three graduated timber/steel goal frames on a staggered portal line.
static func build_park_split_s_frames(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.name = "ParkSplitSFrames"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var timber := _get_mat("wood", Color(0.78, 0.62, 0.44))
	var steel := _get_mat("steel", Color(0.22, 0.24, 0.26))
	var limestone := _get_mat("concrete", Color(0.88, 0.83, 0.72))
	var hazard := _get_mat("hazard")

	var heights := [4.2, 6.2, 8.4]
	var widths := [7.2, 6.8, 6.4]
	for i in range(3):
		var fz := float(i - 1.0) * 13.5
		var fx := sin(float(i) * 1.1) * 2.6
		var frame := Node3D.new()
		frame.name = "SplitSFrame_%d" % i
		frame.position = Vector3(fx, 0.0, fz)
		frame.rotation.y = sin(float(i) * 1.1) * 0.12
		root.add_child(frame)
		var h: float = heights[i]
		var w: float = widths[i]
		for side in [-1.0, 1.0]:
			var px: float = side * w * 0.5
			_add_box(frame, Vector3(1.1, 4.2, 1.1), Vector3(px, -1.8, 0.0), limestone, true)
			_add_box(frame, Vector3(0.55, h, 0.55), Vector3(px, h * 0.5, 0.0), timber, true)
			_add_box(frame, Vector3(0.7, 0.3, 0.7), Vector3(px, h - 0.2, 0.0), steel, true)
			_add_box(frame, Vector3(0.14, 1.0, 0.16), Vector3(px - side * 0.32, 1.4, 0.0), hazard, false)
		# Clear top bar for Split-S / Trippy spins.
		_add_box(frame, Vector3(w + 0.9, 0.5, 0.8), Vector3(0.0, h, 0.0), timber, true)
		_add_box(frame, Vector3(w + 0.9, 0.22, 0.22), Vector3(0.0, h + 0.35, 0.0), hazard, false)
	return root


# =============================================================================
#  MAP SPAWNER: DISTINCT STRUCTURES SPREAD ORGANICALLY WITHOUT CLUTTER
# =============================================================================

static func _is_valid_mil_spot(terrain, map_name: String, px: float, pz: float,
		hc: Vector2, hhalf: Vector2, sp: Vector2, wl: float) -> bool:
	var spot_bound := 310.0 if map_name == "promzona_plavni" else 158.0
	if absf(px) > spot_bound or absf(pz) > spot_bound:
		return false
	if bool(terrain.call("_tutorial_clear_zone", px, pz)):
		return false
	if is_near_workshop(map_name, px, pz):
		return false
	if absf(px - hc.x) < hhalf.x + 28.0 and absf(pz - hc.y) < hhalf.y + 28.0:
		return false
	if Vector2(px, pz).distance_to(sp) < 38.0:
		return false
	for poi in terrain._poi_positions:
		if Vector2(px, pz).distance_to(poi) < 34.0:
			return false
	var h: float = float(terrain.height_at(map_name, px, pz))
	if map_name == "wetlands" and h < wl + 0.8:
		return false
	if map_name == "industrial":
		if absf(pz + 15.0) < 16.0 or pz > 148.0:
			return false
	if map_name == "village":
		var rx := -140.0 + 18.0 * sin(pz * 0.011)
		if absf(px - rx) < 22.0:
			return false
		if absf(pz - 58.0) < 16.0 and px > 12.0 and px < 156.0:
			return false
	if map_name == "promzona_plavni":
		if h < wl + 0.8:
			return false
		# Keep the flat training strip completely free of structures.
		if absf(px + 225.0) < 44.0 and pz >= -170.0 and pz <= 235.0:
			return false
		# Both bridge decks and their approaches.
		var canal_z := 10.0 + 12.0 * sin(px * 0.012)
		for bx in [-110.0, 110.0]:
			if absf(px - bx) < 18.0 and absf(pz - canal_z) < 42.0:
				return false
		# Southern launch plateau / spawn.
		if Vector2(px, pz).distance_to(Vector2(0.0, 275.0)) < 66.0:
			return false
	return true


static func spawn_map_military_objects(root: Node3D, map_name: String) -> void:
	var terrain := load("res://scripts/util/frontline_terrain.gd")
	if terrain == null:
		return

	# Desktop gets the full seven-sector freestyle flow line; phones and LOW
	# keep a lighter five-structure budget (LOWSPEC/mobile stays healthy).
	var is_mobile := OS.get_name() == "iOS" or OS.has_feature("mobile") \
			or OS.has_environment("MOBILE_UI")
	var low_profile := QualityManager.get_active_level() == QualityManager.Level.LOW
	var max_mil_structs := 5 if (is_mobile or low_profile) else 7
	var site: Dictionary = terrain.HALL_SITES.get(map_name, {})
	var hc: Vector2 = site.get("center", Vector2.ZERO)
	var hhalf: Vector2 = site.get("half", Vector2(40.0, 28.0))
	var sp: Vector2 = site.get("spawn", Vector2(88.0, 114.0))
	var wl: float = terrain.water_level(map_name)

	# 7 well-separated arena sectors across the compacted ±158 m playable field.
	var sectors: Array[Vector2] = [
		Vector2(-108.0, -98.0),
		Vector2(108.0, -98.0),
		Vector2(-112.0, 102.0),
		Vector2(102.0, 108.0),
		Vector2(-128.0, 4.0),
		Vector2(126.0, -6.0),
		Vector2(-4.0, -124.0),
	]
	var fallback_radius := 144.0
	if map_name == "promzona_plavni":
		max_mil_structs = 8
		fallback_radius = 288.0
		sectors = [
			Vector2(-270.0, -280.0), Vector2(-285.0, -195.0),
			Vector2(170.0, -130.0), Vector2(270.0, -270.0),
			Vector2(-270.0, 210.0), Vector2(-120.0, 260.0),
			Vector2(170.0, 200.0), Vector2(280.0, 280.0),
			Vector2(-50.0, -280.0), Vector2(50.0, 250.0),
		]
	var picked: Array[Vector2] = []
	var reserve_r := 18.0 if map_name == "promzona_plavni" else 12.0

	for sector_idx in range(sectors.size()):
		if picked.size() >= max_mil_structs:
			break
		var base_c: Vector2 = sectors[sector_idx]
		var found := false
		for rad in [0.0, 16.0, 32.0, 48.0, 64.0]:
			var steps := 1 if rad == 0.0 else 12
			for s in range(steps):
				var ang := (TAU * float(s)) / float(steps) + float(sector_idx) * 0.4
				var px: float = base_c.x + cos(ang) * rad
				var pz: float = base_c.y + sin(ang) * rad
				if not _is_valid_mil_spot(terrain, map_name, px, pz, hc, hhalf, sp, wl):
					continue
				if bool(terrain.try_reserve_structure(root, map_name,
						Vector2(px, pz), reserve_r, 28.0, false)):
					picked.append(Vector2(px, pz))
					found = true
					break
			if found:
				break

	var fb_tries := 0
	while picked.size() < max_mil_structs and fb_tries < 220:
		fb_tries += 1
		var fx := sin(float(fb_tries) * 11.3 + float(hash(map_name) % 7)) * fallback_radius
		var fz := cos(float(fb_tries) * 17.7 + float(hash(map_name) % 11)) * fallback_radius
		if not _is_valid_mil_spot(terrain, map_name, fx, fz, hc, hhalf, sp, wl):
			continue
		if bool(terrain.try_reserve_structure(root, map_name,
				Vector2(fx, fz), reserve_r, 28.0, false)):
			picked.append(Vector2(fx, fz))

	spawned_positions[map_name] = picked

	# Curated, map-themed freestyle pools: connected flow lines of powerloop
	# arches -> slalom gates -> hollow pipes -> split-S frames -> dive towers.
	var builder_pools := {
		"industrial": [0, 3, 5, 1, 4, 28, 2],
		"wetlands": [5, 32, 19, 8, 14, 7, 2],
		"village": [32, 5, 14, 22, 1, 7, 2],
		"steppe": [6, 5, 33, 4, 1, 34, 2],
		"promzona_plavni": [0, 5, 32, 19, 8, 14, 7, 28, 2],
	}
	var pool: Array = builder_pools.get(map_name, [0, 8, 9, 14])

	for i in range(picked.size()):
		var p2 := picked[i]
		var yaw := float(i) * 0.85 + sin(float(i) * 2.3) * 0.5
		var y: float = float(terrain.footprint_min_height(map_name, p2, 10.0, 10.0, yaw)) - 0.20
		var pos3 := Vector3(p2.x, y, p2.y)
		var builder_id := int(pool[i % pool.size()])
		terrain.add_contact_shadow(root, map_name, p2, 14.0, "MilStruct_%d" % i)

		match builder_id:
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
			30: build_sam_battery_gantry(root, pos3, yaw)
			31: build_fortified_helipad_hangar(root, pos3, yaw)
			32: build_bailey_truss_bridge(root, pos3, yaw)
			33: build_heavy_radar_gci_complex(root, pos3, yaw)
			34: build_artillery_bunker_complex(root, pos3, yaw)
			35: build_park_pergola_arches(root, pos3, yaw)
			36: build_park_tunnel_pipes(root, pos3, yaw)
			37: build_park_gazebo_tower(root, pos3, yaw)
			38: build_park_split_s_frames(root, pos3, yaw)

	print("[MilitaryStructures] Spawned %d non-overlapping freestyle military structures on %s" % [picked.size(), map_name])
