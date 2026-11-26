class_name WorldDetail
extends RefCounted

## Outdoor "set dressing" pass for the four frontline maps.
##
## The hero halls already carry a full interior detail kit, but the fields
## around them were still mostly bare terrain with a handful of landmarks.
## This module dresses the parts the pilot actually sees after flying out of a
## hall: aprons with loading docks, containers and clutter, ruined outbuildings,
## cultivated fields with crop rows, orchards, rail yards and marsh details.
##
## Everything is either:
##   * a box/cylinder/prism created through FrontlineTerrain's helpers, which
##     are merged into a handful of MultiMeshes by _batch_static_props(), or
##   * one MultiMesh per repeated micro-detail type (rubble, crop tufts, weeds).
##
## That keeps the outdoor detail pass inside the same draw-call budget as the
## existing landmark pass instead of adding hundreds of unique MeshInstances.

const FT := preload("res://scripts/util/frontline_terrain.gd")
const ASSETS := preload("res://scripts/util/frontline_assets.gd")
const PROPS := preload("res://scripts/util/prop_assets.gd")
const FOLIAGE := preload("res://scripts/util/foliage_system.gd")
const VEGETATION := preload("res://scripts/util/vegetation_assets.gd")
const GRASS_SHADER := preload("res://Assets/grass_wind.gdshader")
const CROP_SHADER := preload("res://shaders/crop_field.gdshader")

static var _rng := RandomNumberGenerator.new()
static var _map := "steppe"

## Reused unit meshes for the cheap scatter passes.
static var _rubble_mesh: BoxMesh = null
static var _brick_mesh: BoxMesh = null
static var _plank_mesh: BoxMesh = null
static var _rebar_mesh: CylinderMesh = null
static var _crop_mesh: ArrayMesh = null
static var _weed_mesh: ArrayMesh = null
static var _pole_mesh: CylinderMesh = null

## Pending scatter buffers.  Every rubble/weed/prop call used to create its own
## MultiMesh (4-5 draw calls per pile, 1 per grass patch, 1 per prop group);
## across a map that added hundreds of draw calls.  All of them are accumulated
## here and flushed once at the end of the pass into a handful of MultiMeshes.
static var _p_chunks: Array = []
static var _p_chunk_cols: Array = []
static var _p_bricks: Array = []
static var _p_brick_cols: Array = []
static var _p_planks: Array = []
static var _p_plank_cols: Array = []
static var _p_rebar: Array = []
static var _p_weeds: Dictionary = {}       # palette key -> {"mat": Material, "xf": []}
static var _p_props: Dictionary = {}       # prop name -> transforms
static var _prop_mat: StandardMaterial3D = null
## Centres of already-placed fields / ruins / landmark clusters.  The
## procedural scatter uses these to avoid stacking a new site on top of an
## authored one.
static var _used_sites: Array = []


static func build(root: Node3D, map_name: String, _base_y: float) -> void:
	if root == null:
		return
	_map = map_name
	_rng = RandomNumberGenerator.new()
	_rng.seed = hash(map_name) + 8801
	_p_chunks.clear()
	_p_chunk_cols.clear()
	_p_bricks.clear()
	_p_brick_cols.clear()
	_p_planks.clear()
	_p_plank_cols.clear()
	_p_rebar.clear()
	_p_weeds.clear()
	_p_props.clear()
	_used_sites.clear()
	var level := QualityManager.get_active_level()
	var fallback := 0.35 if level == QualityManager.Level.HIGH else \
			(0.30 if level == QualityManager.Level.MEDIUM else 0.25)
	var factor := float(QualityManager.get_value("world_detail_factor", fallback))

	_dress_hall_sites(root, map_name, factor)
	_dress_ruins(root, map_name, factor)
	match map_name:
		"village":
			_dress_village(root, map_name, factor)
		"industrial":
			_dress_industrial(root, map_name, factor)
		"wetlands":
			_dress_wetlands(root, map_name, factor)
		"promzona_plavni":
			_dress_promzona_plavni(root, map_name, factor)
		_:
			_dress_steppe(root, map_name, factor)
	_dress_fields(root, map_name, factor)
	# Data-driven fill for the rest of the map: every map gets a deterministic
	# scatter of ruins / camps / wrecks / fields / checkpoints instead of a
	# handful of hand-placed coordinates.
	_scatter_procedural(root, map_name, factor)
	# 100 unique procedural props per map, themed with the biome materials.
	if not OS.has_environment("QA_NO_OBJECT_KIT"):
		var kit = load("res://scripts/util/object_kit.gd")
		if kit != null:
			kit.build(root, map_name, factor, _used_sites)
	_dress_ground_litter(root, map_name, factor)
	_flush_pending(root)
	root.set_meta("gfx_world_detail", true)
	root.set_meta("gfx_world_detail_factor", snappedf(factor, 0.01))
	print("[WorldDetail] dressed ", map_name, " (factor ", snappedf(factor, 0.01), ")")


# ===========================================================================
#  Shared helpers
# ===========================================================================
static func _h(x: float, z: float) -> float:
	return FT._height(_map, x, z)


## Rotate a local XZ offset by a yaw basis and return it as a ground-plane
## Vector2.  Keeps the field/house placement code readable.
static func _b2(b: Basis, v: Vector3) -> Vector2:
	var w := b * v
	return Vector2(w.x, w.z)


static func _free(x: float, z: float, pad: float = 2.0) -> bool:
	var detail_bound := 318.0 if _map == "promzona_plavni" else 160.0
	if absf(x) > detail_bound or absf(z) > detail_bound:
		return false
	if FT._road_factor(_map, x, z) >= 0.25:
		return false
	if _h(x, z) < FT.water_level(_map) + 0.35:
		return false
	if _map == "steppe" or _map == "village" or _map == "promzona_plavni":
		if FT._tutorial_clear_zone(x, z):
			return false
	if FT._hall_clear_zone(_map, x, z):
		return false
	if FT._structure_clear_zone(_map, x, z, pad):
		return false
	var pt := Vector2(x, z)
	for s in _used_sites:
		if (s as Vector2).distance_to(pt) < pad + 12.0:
			return false
	return true


static func _no_shadow(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = \
				GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_no_shadow(child)


static func _box(root: Node3D, pos: Vector3, size: Vector3, mat: Material,
		yaw: float = 0.0, collide: bool = false) -> Node:
	var node := FT._add_box(root, pos, size, mat, yaw, collide)
	if node != null:
		_no_shadow(node)
	return node


static func _tag_attached(node: Node) -> void:
	if node != null:
		node.set_meta("qa_attached_subpart", true)


static func _cyl(root: Node3D, pos: Vector3, radius: float, height: float,
		mat: Material, collide: bool = false) -> void:
	var node := FT._add_cylinder(root, pos, radius, height, mat, 0.0, collide)
	if node != null:
		_no_shadow(node)


static func _prism(root: Node3D, pos: Vector3, size: Vector3, mat: Material,
		yaw: float = 0.0) -> void:
	FT._add_prism(root, pos, size, mat, yaw)


static func _prop(root: Node3D, name: String, x: float, z: float,
		yaw: float = 0.0, scale_f: float = 1.0) -> void:
	if not _free(x, z, 1.0):
		return
	ASSETS.spawn_prop(root, name, Vector3(x, _h(x, z), z), yaw, scale_f)


static func _asset_on(root: Node3D, p: Vector2, asset_name: String,
		scale_f: float = 1.0) -> Node3D:
	if not _free(p.x, p.y, 2.0):
		return null
	return ASSETS.spawn(root, asset_name, Vector3(p.x, _h(p.x, p.y), p.y),
			_rng.randf_range(0.0, TAU), scale_f)


static func _unit_meshes() -> void:
	if _rubble_mesh != null:
		return
	_rubble_mesh = BoxMesh.new()
	_rubble_mesh.size = Vector3.ONE
	_brick_mesh = BoxMesh.new()
	_brick_mesh.size = Vector3(0.24, 0.09, 0.11)
	_plank_mesh = BoxMesh.new()
	_plank_mesh.size = Vector3.ONE
	_rebar_mesh = CylinderMesh.new()
	_rebar_mesh.top_radius = 1.0
	_rebar_mesh.bottom_radius = 1.0
	_rebar_mesh.height = 1.0
	_rebar_mesh.radial_segments = 5
	_rebar_mesh.rings = 1
	_pole_mesh = CylinderMesh.new()
	_pole_mesh.top_radius = 1.0
	_pole_mesh.bottom_radius = 1.0
	_pole_mesh.height = 1.0
	_pole_mesh.radial_segments = 8


static func _rubble(root: Node3D, center: Vector2, radius: float, count: int,
		name: String, collide: bool = false) -> void:
	_unit_meshes()
	var chunk_xf: Array = []
	var brick_xf: Array = []
	var plank_xf: Array = []
	var rebar_xf: Array = []
	var chunk_col: Array = []
	var brick_col: Array = []
	var plank_col: Array = []
	for i in range(count):
		var a := _rng.randf_range(0.0, TAU)
		var r := sqrt(_rng.randf()) * radius
		var x := center.x + cos(a) * r
		var z := center.y + sin(a) * r
		if _h(x, z) < FT.water_level(_map) + 0.1:
			continue
		var y := _h(x, z)
		var roll := _rng.randf()
		if roll < 0.56:
			var s := Vector3(_rng.randf_range(0.18, 0.9), _rng.randf_range(0.06, 0.34),
					_rng.randf_range(0.18, 0.8))
			var b := Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(s)
			chunk_xf.append(Transform3D(b, Vector3(x, y + s.y * 0.45, z)))
			var g := _rng.randf_range(0.34, 0.68)
			chunk_col.append(Color(g * 1.03, g, g * 0.95))
		elif roll < 0.86:
			var s := Vector3(_rng.randf_range(1.0, 4.2), _rng.randf_range(0.05, 0.13),
					_rng.randf_range(0.10, 0.3))
			var b := Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(s)
			plank_xf.append(Transform3D(b, Vector3(x, y + 0.07, z)))
			var w := _rng.randf_range(0.28, 0.55)
			plank_col.append(Color(w * 1.05, w * 0.9, w * 0.72))
		else:
			var b := Basis(Vector3.UP, _rng.randf_range(0.0, TAU)) \
					* Basis(Vector3.RIGHT, PI * 0.5) \
					* Basis().scaled(Vector3(0.022, _rng.randf_range(0.9, 3.2), 0.022))
			rebar_xf.append(Transform3D(b, Vector3(x, y + 0.05, z)))
		for k in range(_rng.randi_range(0, 2)):
			var ba := _rng.randf_range(0.0, TAU)
			var br := _rng.randf_range(0.0, radius * 0.8)
			var bx := center.x + cos(ba) * br
			var bz := center.y + sin(ba) * br
			var by := _h(bx, bz)
			if by < FT.water_level(_map) + 0.1:
				continue
			var bb := Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(
					Vector3.ONE * _rng.randf_range(0.7, 1.3))
			brick_xf.append(Transform3D(bb, Vector3(bx, by + 0.05, bz)))
			var brc := _rng.randf_range(0.45, 0.72)
			brick_col.append(Color(brc, brc * 0.62, brc * 0.48))

	# Queue into the map-wide batches (flushed once at the end of build()).
	_p_chunks.append_array(chunk_xf)
	_p_chunk_cols.append_array(chunk_col)
	_p_bricks.append_array(brick_xf)
	_p_brick_cols.append_array(brick_col)
	_p_planks.append_array(plank_xf)
	_p_plank_cols.append_array(plank_col)
	_p_rebar.append_array(rebar_xf)
	if collide and not chunk_xf.is_empty():
		var body := StaticBody3D.new()
		body.name = name + "RubbleCollision"
		body.collision_layer = 1
		body.collision_mask = 1
		for i in range(0, mini(chunk_xf.size(), 18)):
			var xf: Transform3D = chunk_xf[i]
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(0.8, 0.6, 0.8)
			cs.shape = bs
			cs.position = xf.origin + Vector3(0, 0.2, 0)
			body.add_child(cs)
		root.add_child(body)


static func _weeds(root: Node3D, center: Vector2, radius: float, count: int,
		base: Color, tip: Color) -> void:
	_unit_meshes()
	if _weed_mesh == null:
		_weed_mesh = FOLIAGE.create_grass_mesh(8, 2.1)
	# Merge every patch with the same palette into one map-wide MultiMesh.
	var key := base.to_html() + "|" + tip.to_html()
	if not _p_weeds.has(key):
		var mat := ShaderMaterial.new()
		mat.shader = GRASS_SHADER
		mat.set_shader_parameter("grass_base_color", Vector3(base.r, base.g, base.b))
		mat.set_shader_parameter("grass_tip_color", Vector3(tip.r, tip.g, tip.b))
		mat.set_shader_parameter("wind_strength", 0.16)
		_p_weeds[key] = {"mat": mat, "xf": []}
	var bucket: Dictionary = _p_weeds[key]
	var xfs: Array = bucket["xf"]
	for i in range(count):
		var a := _rng.randf_range(0.0, TAU)
		var r := sqrt(_rng.randf()) * radius
		var x := center.x + cos(a) * r
		var z := center.y + sin(a) * r
		var y := _h(x, z)
		if y < FT.water_level(_map) + 0.15:
			continue
		var s := _rng.randf_range(0.65, 1.7)
		xfs.append(Transform3D(Basis(Vector3.UP, _rng.randf_range(0.0, TAU))
				.scaled(Vector3(s, _rng.randf_range(0.8, 1.7), s)),
				Vector3(x, y, z)))


static func _flush_pending(root: Node3D) -> void:
	_unit_meshes()
	if _p_chunks.is_empty() and _p_bricks.is_empty() and _p_planks.is_empty() \
			and _p_rebar.is_empty() and _p_weeds.is_empty() and _p_props.is_empty():
		return
	if not _p_chunks.is_empty():
		var cm: StandardMaterial3D = (FT._pbr("concrete", Color(0.70, 0.69, 0.65),
				0.42) as StandardMaterial3D).duplicate() as StandardMaterial3D
		cm.vertex_color_use_as_albedo = true
		var mm := FT._multimesh(root, "BatchRubbleChunks", _rubble_mesh, cm,
				_p_chunks, false, _p_chunk_cols)
		if mm != null:
			mm.visibility_range_end = 190.0
			mm.visibility_range_end_margin = 25.0
			mm.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	if not _p_bricks.is_empty():
		var bm: StandardMaterial3D = (FT._pbr("brick", Color(0.68, 0.48, 0.38),
				0.50) as StandardMaterial3D).duplicate() as StandardMaterial3D
		bm.vertex_color_use_as_albedo = true
		var mm := FT._multimesh(root, "BatchRubbleBricks", _brick_mesh, bm,
				_p_bricks, false, _p_brick_cols)
		if mm != null:
			mm.visibility_range_end = 120.0
			mm.visibility_range_end_margin = 18.0
			mm.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	if not _p_planks.is_empty():
		var pm: StandardMaterial3D = (FT._pbr("wood", Color(0.64, 0.52, 0.38),
				0.50) as StandardMaterial3D).duplicate() as StandardMaterial3D
		pm.vertex_color_use_as_albedo = true
		var mm := FT._multimesh(root, "BatchRubblePlanks", _plank_mesh, pm,
				_p_planks, false, _p_plank_cols)
		if mm != null:
			mm.visibility_range_end = 150.0
			mm.visibility_range_end_margin = 20.0
			mm.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	if not _p_rebar.is_empty():
		var mm := FT._multimesh(root, "BatchRubbleRebar", _rebar_mesh,
				FT._mat(Color(0.29, 0.16, 0.09), 0.72, 0.2), _p_rebar, false)
		if mm != null:
			mm.visibility_range_end = 90.0
			mm.visibility_range_end_margin = 14.0
			mm.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	for key in _p_weeds.keys():
		var b: Dictionary = _p_weeds[key]
		var xfs: Array = b["xf"]
		if xfs.is_empty():
			continue
		var mm := FT._multimesh(root, "BatchWeeds", _weed_mesh, b["mat"], xfs, false)
		if mm != null:
			mm.visibility_range_end = 130.0
			mm.visibility_range_end_margin = 20.0
			mm.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	if _prop_mat == null:
		var base_pbr := FT._pbr("hall_metal", Color.WHITE, 0.30) as StandardMaterial3D
		if base_pbr != null:
			_prop_mat = base_pbr.duplicate() as StandardMaterial3D
			_prop_mat.albedo_texture = null
			_prop_mat.uv1_triplanar = true
			_prop_mat.uv1_world_triplanar = true
		else:
			_prop_mat = StandardMaterial3D.new()
		_prop_mat.albedo_color = Color(1.06, 1.05, 1.02)
		_prop_mat.vertex_color_use_as_albedo = true
		_prop_mat.roughness = 0.84
		_prop_mat.metallic = 0.12
	var meshes: Dictionary = PROPS.meshes()
	for name in _p_props.keys():
		var mesh: Mesh = meshes.get(name, null)
		if mesh == null:
			continue
		var xfs: Array = _p_props[name]
		if xfs.is_empty():
			continue
		var mm := FT._multimesh(root, "BatchProp_" + String(name), mesh,
				_prop_mat, xfs, false)
		if mm != null:
			mm.visibility_range_end = 260.0
			mm.visibility_range_end_margin = 30.0
			mm.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


static func _puddle(root: Node3D, center: Vector2, radius: float) -> void:
	var y := _h(center.x, center.y)
	if y < FT.water_level(_map) + 0.25:
		return
	var mat := StandardMaterial3D.new()
	# A wet-mud puddle, not a mirror: the old metallic material reflected the
	# sky as a hard blue triangle in the middle of the village lane.
	mat.albedo_color = Color(0.075, 0.064, 0.048)
	mat.roughness = 0.72
	mat.metallic = 0.0
	mat.metallic_specular = 0.18
	var disc := SphereMesh.new()
	disc.radius = radius
	disc.height = 0.03
	disc.radial_segments = 16
	disc.rings = 2
	var mi := MeshInstance3D.new()
	mi.name = "GroundPuddle"
	mi.mesh = disc
	mi.material_override = mat
	mi.position = Vector3(center.x, y + 0.02, center.y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


static func _queue_prop(name: String, x: float, z: float,
		yaw: float = 0.0, scale_f: float = 1.0) -> void:
	if not _p_props.has(name):
		_p_props[name] = []
	(_p_props[name] as Array).append(Transform3D(
			Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale_f),
			Vector3(x, _h(x, z), z)))


static func _scatter_props(root: Node3D, center: Vector2, radius: float,
		names: Array, count: int) -> void:
	for i in range(count):
		var a := _rng.randf_range(0.0, TAU)
		var r := sqrt(_rng.randf()) * radius
		var x := center.x + cos(a) * r
		var z := center.y + sin(a) * r
		if not _free(x, z, 0.5):
			continue
		_queue_prop(names[_rng.randi_range(0, names.size() - 1)], x, z,
				_rng.randf_range(0.0, TAU), _rng.randf_range(0.85, 1.15))


# ===========================================================================
#  Hall aprons: the first thing the pilot sees after leaving the nave
# ===========================================================================
static func _dress_hall_sites(root: Node3D, map_name: String, factor: float) -> void:
	var site: Dictionary = FT.HALL_SITES.get(map_name, {})
	if site.is_empty():
		return
	var c: Vector2 = site["center"]
	var pad_half: Vector2 = site["half"]
	# Use the actual hall wall dimensions (half_len, half_w) so facade trim sits flush on the walls!
	var half := Vector2(60.0, 27.0)
	match map_name:
		"village":
			half = Vector2(48.0, 23.0)
		"steppe":
			half = Vector2(56.0, 25.0)
		"wetlands":
			half = Vector2(52.0, 24.0)
		"promzona_plavni":
			half = Vector2(58.0, 25.0)
	_used_sites.append(c)
	_used_sites.append(Vector2(c.x + pad_half.x + 32.0, c.y))
	var roof_h := float(site.get("roof_height", 18.0))
	var gy := _h(c.x, c.y)

	# All facade trim and wall-mounted dressing lives under one named container
	# so composite ground validation can tie every elevated trim back to the
	# grounded hall base.  The container is identity, so world positions do not
	# change.
	var trim_root := Node3D.new()
	trim_root.name = "HeroHallTrim_" + map_name
	root.add_child(trim_root)

	# ---- roof / facade rhythm ------------------------------------------------
	var metal := FT._pbr("hall_rust", Color(0.72, 0.52, 0.36), 0.34)
	var steel := FT._pbr("hall_metal", Color(0.44, 0.47, 0.49), 0.26)
	var dark := FT._mat(Color(0.055, 0.055, 0.05), 0.9)
	var concrete := FT._pbr("hall_concrete", Color(0.74, 0.75, 0.74), 0.26)
	var rust := FT._pbr("hall_rust", Color(0.62, 0.42, 0.27), 0.38)
	# Downpipes and wall pilasters on both long facades (roof vents are built directly into the arched GLB).
	var bays := int(maxf(4.0, round(9.0 * factor)))
	for side in [-1.0, 1.0]:
		for i in range(bays):
			var bx := -half.x * 0.86 + float(i) * (half.x * 1.72 / float(maxi(1, bays - 1)))
			var fx := c.x + bx
			var wall_z := half.y
			var fz: float = c.y + side * (wall_z + 0.18)
			_box(trim_root, Vector3(fx, gy + 2.5, fz), Vector3(0.18, 5.0, 0.22), metal)
			for row in range(2):
				var wy := gy + 4.0 + float(row) * 4.4
				_box(trim_root, Vector3(fx + 3.1, wy - 1.16, fz + side * 0.15),
						Vector3(4.5, 0.12, 0.24), concrete)
				_box(trim_root, Vector3(fx + 3.1, wy + 1.16, fz + side * 0.15),
						Vector3(4.5, 0.12, 0.24), concrete)
				for mx in [-1.45, 0.0, 1.45]:
					_box(trim_root, Vector3(fx + 3.1 + mx, wy, fz + side * 0.13),
							Vector3(0.10, 2.2, 0.16), metal)
	# Long-facade weathering: base grime, rust runs and moss patches.
	var side_wall_z := half.y
	for side in [-1.0, 1.0]:
		var fz2: float = c.y + side * (side_wall_z + 0.12)
		_box(trim_root, Vector3(c.x, gy + 0.45, fz2),
				Vector3(half.x * 1.72, 0.9, 0.08),
				FT._mat(Color(0.24, 0.21, 0.17), 0.95), 0, false)
		for k in range(7):
			var rx := c.x - half.x * 0.72 + float(k) * half.x * 0.24
			var rh := 1.8 + float(k % 3) * 0.8
			_box(trim_root, Vector3(rx, gy + 4.3, fz2 + side * 0.06),
					Vector3(0.16, rh, 0.06), FT._mat(Color(0.24, 0.15, 0.09), 0.95),
					0, false)
		for k in range(4):
			var mx := c.x - half.x * 0.55 + float(k) * half.x * 0.35
			_box(trim_root, Vector3(mx, gy + 0.55, fz2 + side * 0.08),
					Vector3(1.2, 1.1, 0.08), FT._pbr("hall_moss",
					Color(0.34, 0.39, 0.23), 0.4), 0, false)
		# Gutter along the eave.
		_box(trim_root, Vector3(c.x, gy + roof_h * 0.68, fz2 + side * 0.1),
				Vector3(half.x * 1.76, 0.22, 0.24),
				FT._pbr("steel", Color(0.38, 0.26, 0.18), 0.36), 0, false)
	# Service catwalk and pipe runs along both long facades.  The old version
	# floated a 1.9 m walkway at 9.6 m with short posts that reached nothing,
	# and the loose posts read as pieces of a ladder hanging in the air.  The
	# walkway is now a solid collidable deck with wall brackets, diagonal
	# braces and a proper outer railing.
	var catwalk_mat := FT._pbr("hall_metal", Color(0.40, 0.42, 0.40), 0.34)
	for side in [-1.0, 1.0]:
		var wz: float = c.y + side * (side_wall_z + 1.0)
		var wall_z: float = c.y + side * (side_wall_z + 0.10)
		var mid_z: float = (wz + wall_z) * 0.5
		var reach_z: float = absf(wz - wall_z) + 0.34
		_box(trim_root, Vector3(c.x, gy + 9.6, wz),
				Vector3(half.x * 1.55, 0.18, 1.9), catwalk_mat, 0, true)
		var rail_z: float = wz + side * 0.88
		_box(trim_root, Vector3(c.x, gy + 10.55, rail_z),
				Vector3(half.x * 1.55, 0.08, 0.08), steel, 0, false)
		var posts := 10
		for k in range(posts):
			var px := c.x - half.x * 0.72 + float(k) * half.x * 1.44 / float(posts - 1)
			# Outer railing post, resting on the deck.
			_box(trim_root, Vector3(px, gy + 10.08, rail_z),
					Vector3(0.08, 1.0, 0.08), steel, 0, false)
			# Horizontal bracket from the wall to the deck underside.
			_box(trim_root, Vector3(px, gy + 9.40, mid_z),
					Vector3(0.12, 0.16, reach_z), steel, 0, false)
			# Diagonal brace tying the bracket back to the wall.
			var brace := FT._add_box(trim_root, Vector3(px, gy + 8.67, mid_z),
					Vector3(0.09, 1.95, 0.09), steel)
			if brace != null:
				brace.rotation.x = -side * 0.62
				_no_shadow(brace)
			# Pipe brackets at both service pipes.
			for py in [5.0, 6.2]:
				_box(trim_root, Vector3(px, gy + float(py), mid_z),
						Vector3(0.10, 0.10, reach_z), steel, 0, false)
		# Two heavy service pipes below the catwalk.
		for py in [5.0, 6.2]:
			var pipe := MeshInstance3D.new()
			var pcyl := CylinderMesh.new()
			pcyl.top_radius = 0.18
			pcyl.bottom_radius = 0.18
			pcyl.height = half.x * 1.45
			pcyl.radial_segments = 8
			pipe.mesh = pcyl
			pipe.material_override = rust
			pipe.position = Vector3(c.x, gy + float(py), wz + side * 0.45)
			pipe.rotation = Vector3(0, 0, PI * 0.5)
			pipe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			trim_root.add_child(pipe)
	# Exterior lamps along the long facade (no shadows: cheap fill).
	for side in [-1.0, 1.0]:
		for i in range(3):
			var lx := c.x + (-half.x * 0.62 + float(i) * half.x * 0.62)
			var lz: float = c.y + side * (half.y + 0.28)
			_box(trim_root, Vector3(lx, gy + 6.9, lz), Vector3(0.22, 0.7, 0.22), dark)
			var lamp := OmniLight3D.new()
			lamp.position = Vector3(lx, gy + 6.65, lz + side * 0.2)
			lamp.omni_range = 14.0
			lamp.light_energy = 0.55
			lamp.light_color = Color(1.0, 0.78, 0.48)
			lamp.shadow_enabled = false
			trim_root.add_child(lamp)
			var bulb := SphereMesh.new()
			bulb.radius = 0.13
			bulb.height = 0.26
			var bm := MeshInstance3D.new()
			bm.mesh = bulb
			var bmat := FT._mat(Color(1.0, 0.82, 0.56), 0.4)
			bmat.emission_enabled = true
			bmat.emission = Color(1.0, 0.60, 0.28)
			bmat.emission_energy_multiplier = 2.2
			bm.material_override = bmat
			bm.position = lamp.position
			bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			trim_root.add_child(bm)

	# ---- end walls: portals, windows, pilasters and service pipes ----------
	for dir in [-1.0, 1.0]:
		_hall_end_details(trim_root, map_name, c, half, dir, gy, roof_h)

	# ---- loading apron at both doors ---------------------------------------
	for dir in [-1.0, 1.0]:
		var reach := half.x + 14.0
		var ap := Vector2(c.x + dir * reach, c.y)
		_dress_apron(root, map_name, ap, dir, factor)
	# Clean clear space around workshop walls (no adjacent structures, sheds or yards)
	pass


## Working yard on the spawn side of every hero hall.
##
## The apron pass only covers the first 20 m; beyond it the maps opened into a
## featureless lawn.  This pass lays a gravel/concrete yard that follows the
## terrain, fences it, adds a gate, floodlights, containers, pipe stacks, rail
## sidings and a couple of silos.  It fills the entire first exterior view with
## readable silhouettes and gives the pilot an obvious route out of the site.
static func _hall_yard(root: Node3D, map_name: String, c: Vector2, half: Vector2,
		factor: float) -> void:
	var yard_w := 66.0
	var yard_d := 54.0
	var yard_half_x := 52.0 if map_name == "village" else half.x
	var inner_x := c.x + yard_half_x + 14.0
	var center := Vector2(inner_x + yard_w * 0.5, c.y)
	# Terrain-conforming yard slab.  A flat box would clip through the first
	# hill and leave a visible seam, so reuse the field-patch grid.
	# The working yard is a poured concrete apron, not a dirt field: use the
	# same damaged hall-floor PBR set that carries the reference interior.
	var gravel: Material = FT._pbr("hall_floor", Color(0.78, 0.79, 0.80), 0.22)
	var mesh := _field_mesh(center, yard_w, yard_d, 0.0)
	if mesh == null:
		return
	# A packed-dirt margin under and around the concrete hides the hard
	# rectangular seam where the slab meets the grass.
	var margin_mat := FT._pbr("dirt", Color(0.56, 0.51, 0.43), 0.22)
	var margin_mesh := _field_mesh(center, yard_w + 16.0, yard_d + 16.0, 0.0)
	if margin_mesh != null:
		var margin := MeshInstance3D.new()
		margin.name = "HallYardMargin"
		margin.mesh = margin_mesh
		margin.material_override = margin_mat
		margin.position.y = -0.025
		margin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(margin)
	var mi := MeshInstance3D.new()
	mi.name = "HallYardSlab"
	mi.mesh = mesh
	mi.material_override = gravel
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	# Foreground clutter between the door and the gate: the eye-level view
	# otherwise had a clean concrete apron and nothing to read against it.
	_forecourt(root, Vector2(inner_x + 9.0, c.y + 3.0), factor)
	_forklift(root, Vector2(inner_x + 19.0, c.y + 9.0), -0.45)
	# Supplies staged along the wall: readable 0.5-1.5 m props at eye level.
	for i in range(6):
		_queue_prop("prop_barrel", inner_x + 2.5, c.y - 17.0 + float(i) * 1.35,
				float(i) * 0.7, 1.0)
	for i in range(4):
		_queue_prop("prop_crate", inner_x + 4.2, c.y + 14.0 + float(i) * 1.1,
				float(i) * 0.5, 1.0)
	for i in range(3):
		_queue_prop("prop_pallet", inner_x + 8.0, c.y - 22.0 + float(i) * 1.6,
				0.0, 1.0)
	# Rubble banked against the hall wall, where the roof drains and the
	# demolition crews left the broken slabs.
	_rubble(root, Vector2(inner_x - 1.0, c.y - 18.0), 5.0, 34, "WallRubble", true)
	_rubble(root, Vector2(inner_x - 1.0, c.y + 19.0), 5.0, 34, "WallRubble2", true)
	_yard_ground_detail(root, center, yard_w, yard_d)
	_pebbles(root, center, 30.0, int(maxf(400.0, 1500.0 * factor)))
	# A working yard always has a little broken concrete at the edges of the
	# apron; one cluster gives the foreground a readable texture.
	_rubble(root, Vector2(inner_x + yard_w * 0.62, c.y + yard_d * 0.30),
			8.0, int(maxf(30.0, 90.0 * factor)), "YardForegroundRubble", false)
	# Staged pallets/crates in the middle of the yard so the foreground is not
	# a blank concrete plane when the player turns around at the door.
	for i in range(5):
		_queue_prop("prop_pallet", inner_x + 30.0 + float(i) * 1.3,
				c.y + 9.0, float(i) * 0.4, 1.0)
	for i in range(4):
		_queue_prop("prop_crate", inner_x + 31.0 + float(i % 2) * 1.2,
				c.y + 11.0 + float(i / 2) * 1.2, float(i) * 0.5, 1.0)
	for i in range(3):
		_queue_prop("prop_barrel", inner_x + 8.0, c.y - 7.0 + float(i) * 1.2,
				float(i) * 0.7, 1.0)
	# Track marks: dark ribbons crossing the yard from gate to hall.
	# (No separate tyre-track ribbons: on the light concrete they read as
	# black paint strips.  The expansion joints and oil stains carry the yard
	# texture instead.)

	# Fence around three sides, with an 8 m vehicle gate in the far side.
	var metal := FT._pbr("steel", Color(0.34, 0.38, 0.39), 0.34)
	var concrete := FT._pbr("concrete", Color(0.66, 0.65, 0.60), 0.28)
	_yard_fence(root, Vector2(inner_x + yard_w, c.y - yard_d * 0.5),
			Vector2(inner_x + yard_w, c.y + yard_d * 0.5), metal, true)
	_yard_fence(root, Vector2(inner_x, c.y - yard_d * 0.5),
			Vector2(inner_x + yard_w, c.y - yard_d * 0.5), metal, false)
	_yard_fence(root, Vector2(inner_x, c.y + yard_d * 0.5),
			Vector2(inner_x + yard_w, c.y + yard_d * 0.5), metal, false)
	# Gate pillars + barrier arm.
	for gz in [-4.3, 4.3]:
		_box(root, Vector3(inner_x + yard_w, _h(inner_x + yard_w, c.y + gz) + 2.2,
				c.y + gz), Vector3(1.1, 4.4, 1.1), concrete, 0, true)
	_box(root, Vector3(inner_x + yard_w, _h(inner_x + yard_w, c.y) + 5.0, c.y),
			Vector3(1.1, 0.5, 10.0), metal, 0, false)
	var gate_y := _h(inner_x + yard_w, c.y) + 1.1
	var arm := MeshInstance3D.new()
	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3(0.16, 0.16, 7.4)
	arm.mesh = arm_mesh
	arm.material_override = FT._mat(Color(0.72, 0.22, 0.16), 0.6)
	arm.position = Vector3(inner_x + yard_w - 0.3, gate_y, c.y)
	root.add_child(arm)
	# Red/white hazard stripes on the barrier.
	for i in range(7):
		_box(root, Vector3(inner_x + yard_w - 0.3, gate_y,
				c.y - 3.3 + float(i) * 1.1), Vector3(0.19, 0.19, 0.55),
				FT._mat(Color(0.86, 0.82, 0.72) if i % 2 == 0
				else Color(0.62, 0.12, 0.09), 0.55), 0, false)
	# Blue works sign on a post beside the gate.
	var sign_post := Vector3(inner_x + yard_w - 2.2, _h(inner_x + yard_w, c.y + 7.0),
			c.y + 7.0)
	_cyl(root, sign_post + Vector3(0, 1.7, 0), 0.10, 3.4, metal)
	_box(root, sign_post + Vector3(0, 3.4, 0), Vector3(0.12, 1.2, 2.4),
			FT._mat(Color(0.10, 0.20, 0.28), 0.55), 0, false)
	var sign_label := Label3D.new()
	sign_label.text = "ПРОМЗОНА"
	sign_label.font_size = 80
	sign_label.pixel_size = 0.010
	sign_label.modulate = Color(0.88, 0.90, 0.86)
	sign_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	root.add_child(sign_label)
	sign_label.position = sign_post + Vector3(0.10, 3.4, 0)
	sign_label.rotation = Vector3(0, PI * 0.5, 0)

	# Floodlight masts were removed: their tiny lamp heads on 10 m poles read
	# as objects hanging in the air from FPV altitude (the player reported
	# them repeatedly).  The yard keeps its fence, containers and gate.

	# Container stacks inside the yard.
	for spec in [
		[Vector2(inner_x + 12.0, c.y + 16.0), 0.0, 1],
		[Vector2(inner_x + 26.0, c.y + 18.0), 0.0, 2],
		[Vector2(inner_x + 42.0, c.y - 17.0), PI * 0.5, 1],
		[Vector2(inner_x + 54.0, c.y + 10.0), PI * 0.5, 2],
	]:
		var cp: Vector2 = spec[0]
		var cyaw: float = spec[1]
		var stack: int = spec[2]
		for s in range(stack):
			var cmat := FT._pbr("steel", [Color(0.66, 0.29, 0.19),
					Color(0.24, 0.42, 0.52), Color(0.28, 0.46, 0.27)][
					(s + int(cp.x)) % 3], 0.34)
			_box(root, Vector3(cp.x, _h(cp.x, cp.y) + 1.28 + float(s) * 2.50, cp.y),
					Vector3(6.0, 2.5, 2.42), cmat, cyaw, true)
			var cb := Basis(Vector3.UP, cyaw)
			for rib in range(7):
				for side in [-1.0, 1.0]:
					var off: Vector3 = cb * Vector3(-2.5 + float(rib) * 0.83, 0.0,
							side * 1.24)
					_box(root, Vector3(cp.x, _h(cp.x, cp.y) + 1.28 + float(s) * 2.50,
							cp.y) + off, Vector3(0.06, 2.35, 0.05), metal, cyaw, false)
			# Top and bottom rails in a lighter steel break the flat colour.
			_box(root, Vector3(cp.x, _h(cp.x, cp.y) + 2.50 + float(s) * 2.50,
					cp.y), Vector3(6.15, 0.12, 2.55), metal, cyaw, false)

	# Pipe stacks: three long galvanised cylinders on timber baulks, with
	# rust rings and end caps so they do not read as black tubes.
	var rust := FT._pbr("steel", Color(0.48, 0.28, 0.17), 0.38)
	var pipe_mat := FT._pbr("hall_metal", Color(0.58, 0.60, 0.60), 0.38)
	var chock := FT._pbr("wood", Color(0.34, 0.27, 0.18), 0.55)
	for row in range(3):
		for k in range(2):
			var px := inner_x + 16.0
			var pz := c.y - 14.0 + float(row) * 1.0
			var py := _h(px, pz) + 0.55 + float(k) * 1.25
			var b := Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.RIGHT, PI * 0.5) * \
					Basis().scaled(Vector3(0.55, 9.0, 0.55))
			var pmi := MeshInstance3D.new()
			var pcyl := CylinderMesh.new()
			pcyl.top_radius = 1.0
			pcyl.bottom_radius = 1.0
			pcyl.height = 1.0
			pcyl.radial_segments = 14
			pmi.mesh = pcyl
			pmi.material_override = pipe_mat
			pmi.transform = Transform3D(b, Vector3(px, py, pz))
			pmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(pmi)
			for ring in range(3):
				var rim := MeshInstance3D.new()
				var rcyl := CylinderMesh.new()
				rcyl.top_radius = 1.0
				rcyl.bottom_radius = 1.0
				rcyl.height = 0.035
				rcyl.radial_segments = 14
				rim.mesh = rcyl
				rim.material_override = rust
				rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				rim.transform = Transform3D(b, Vector3(px + (float(ring) - 1.0) * 2.8,
						py, pz))
				root.add_child(rim)
			for side in [-1.0, 1.0]:
				_box(root, Vector3(px, _h(px, pz) + 0.25, pz + side * 0.9),
						Vector3(1.2, 0.5, 0.8), chock, 0, false)

	# Fuel tank / generator set and a guard hut.
	_queue_prop("prop_fuel_tank", inner_x + 8.0, c.y + 7.0, 0.0, 1.2)
	_queue_prop("prop_generator", inner_x + 9.5, c.y + 9.0, 0.0, 1.0)
	_guard_hut(root, Vector2(inner_x + yard_w - 7.0, c.y - 9.0))

	# Spoil heaps / rubble at the edges (the map's industrial story).
	_cone_heap(root, Vector2(inner_x + 6.0, c.y - 20.0), 4.5, 2.4)
	_cone_heap(root, Vector2(inner_x + 48.0, c.y + 22.0), 5.5, 3.0)
	_rubble(root, Vector2(inner_x + 34.0, c.y + 22.0), 8.0,
			int(maxf(40.0, 80.0 * factor)), "YardRubble", true)
	# Storage tanks and a chimney: batched primitives that give the yard an
	# industrial skyline on every quality preset.
	_tank_cluster(root, Vector2(inner_x + yard_w - 16.0, c.y - 16.0))
	# A tall brick stack in the working yard.  It used to sit at z=28, on top
	# of the two silos at z=21-26; the overlapping tubes produced the thin
	# "bugged" pipe and the white window seen inside it.  Keep it clear of the
	# silos and containers now.
	_chimney(root, Vector2(inner_x + 52.0, c.y + 22.0))
	# A larger ruined workshop just outside the gate gives the eye a layered,
	# mid-ground silhouette instead of an empty horizon behind the fence.
	if factor >= 0.6:
		_ruin_site(root, Vector2(inner_x + yard_w + 24.0, c.y + 24.0),
				-0.35, 20.0, 11.0, 5.4, "concrete")
	var rich := factor >= 0.85
	if rich:
		_burning_barrel(root, Vector2(inner_x + yard_w - 12.0,
				c.y - yard_d * 0.5 + 10.0))
		# Watchtower on the far corner: a vertical silhouette that breaks up
		# the flat green foreground every 20-30 m.
		_watchtower(root, Vector2(inner_x + yard_w - 8.0, c.y + yard_d * 0.5 - 5.0))
	# Puddles, line paint and weeds at the fence line.
	# (No standing puddles on the dry steppe/village concrete: the flat discs
	# caught the sky and read as grey paint.  Oil stains below do the job.)
	var paint := FT._mat(Color(0.68, 0.56, 0.18), 0.8)
	for i in range(4):
		_box(root, Vector3(inner_x + 8.0 + float(i) * 3.0, _h(inner_x + 8.0, c.y + 4.0) + 0.09,
				c.y + 4.0), Vector3(1.6, 0.04, 0.10), paint, 0, false)
	for i in range(5):
		_box(root, Vector3(inner_x + 44.0, _h(inner_x + 44.0, c.y - 6.0 + float(i) * 2.8) + 0.09,
				c.y - 6.0 + float(i) * 2.8), Vector3(5.0, 0.04, 0.10), paint, 0, false)
	# Dense edge growth: the transition from concrete to field should be a
	# ragged band of weeds, not a lawn-mower line.
	_weeds(root, Vector2(inner_x + 4.0, c.y), 12.0,
			int(maxf(400.0, 1000.0 * factor)), Color(0.045, 0.065, 0.020),
			Color(0.15, 0.17, 0.055))
	_weeds(root, Vector2(inner_x + yard_w, c.y), 12.0,
			int(maxf(400.0, 1000.0 * factor)), Color(0.045, 0.065, 0.020),
			Color(0.15, 0.17, 0.055))
	# (No grass carpet on the poured concrete itself; the two edge strips and
	# the fence-line bushes keep the weeds where they belong.)
	_bushes(root, Vector2(inner_x + yard_w * 0.5, c.y), yard_d * 0.58,
			int(maxf(40.0, 130.0 * factor)))

	# A rail spur along the south fence and two silos on the north side.
	if rich:
		_rail_yard(root, Vector2(inner_x + 30.0, c.y + yard_d * 0.5 + 8.0),
				58.0, 0.0, factor)
		_silos(root, Vector2(inner_x + 44.0, c.y - yard_d * 0.5 - 10.0), 1)

	# Access road from the gate toward the main farm track.
	var gate_p := Vector2(inner_x + yard_w + 2.0, c.y)
	FT._ribbon(root, PackedVector2Array([gate_p, gate_p + Vector2(34.0, 12.0),
			gate_p + Vector2(72.0, 22.0)]), 5.2,
			FT._pbr("dirt", Color(0.50, 0.43, 0.35), 0.28), 0.07)
	# Roadside utility poles and a line of trees frame the exit view and give
	# the horizon something other than a flat grass edge.
	var pole_wood := FT._pbr("wood", Color(0.38, 0.30, 0.20), 0.5)
	for i in range(6):
		var pp := gate_p + Vector2(16.0 + float(i) * 20.0,
				5.0 + 12.0 * float(i) / 5.0)
		_cyl(root, Vector3(pp.x, _h(pp.x, pp.y) + 4.0, pp.y), 0.14, 8.0, pole_wood)
		_box(root, Vector3(pp.x, _h(pp.x, pp.y) + 7.4, pp.y),
				Vector3(2.2, 0.12, 0.12), pole_wood, 0.0, false)
	# (No additional hero tree GLBs here: each one is a multi-mesh scene and
	# cost more draw calls than the whole yard.  The map's existing tree lines
	# already frame the horizon.)


static func _bushes(root: Node3D, center: Vector2, radius: float, count: int) -> void:
	# Low, ragged scrub along the fence line.  The first version used large
	# smooth spheres and read as bright green plastic blobs on the concrete.
	var mesh := FOLIAGE.make_canopy_mesh(5, 2, 0.52, 0.45, 0.55)
	var mat := FOLIAGE.make_wind_material(Color(0.10, 0.15, 0.055))
	var xfs: Array = []
	for i in range(count):
		var a := _rng.randf_range(0.0, TAU)
		var r := radius * (0.82 + _rng.randf() * 0.24)
		var x := center.x + cos(a) * r
		var z := center.y + sin(a) * r
		var y := _h(x, z)
		if y < FT.water_level(_map) + 0.2:
			continue
		var s := _rng.randf_range(0.35, 1.05)
		xfs.append(Transform3D(Basis(Vector3.UP, _rng.randf_range(0.0, TAU))
				.scaled(Vector3(s * 1.4, s * _rng.randf_range(0.55, 0.9), s * 1.4)),
				Vector3(x, y + 0.18 * s, z)))
	var mmi := FT._multimesh(root, "YardBushes", mesh, mat, xfs, false)
	if mmi != null:
		mmi.visibility_range_end = 240.0
		mmi.visibility_range_end_margin = 30.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


static func _forklift(root: Node3D, p: Vector2, yaw: float) -> void:
	var y := _h(p.x, p.y)
	var basis := Basis(Vector3.UP, yaw)
	var yellow := FT._pbr("steel", Color(0.82, 0.58, 0.08), 0.28)
	var dark := FT._mat(Color(0.05, 0.05, 0.045), 0.9)
	var steel := FT._pbr("steel", Color(0.34, 0.36, 0.35), 0.35)
	var wheel_mesh := CylinderMesh.new()
	wheel_mesh.top_radius = 0.42
	wheel_mesh.bottom_radius = 0.42
	wheel_mesh.height = 0.26
	wheel_mesh.radial_segments = 12
	# Chassis and counterweight.
	_box(root, Vector3(p.x, y + 0.55, p.y), Vector3(2.2, 1.1, 1.2), yellow, yaw, true)
	_box(root, Vector3(p.x, y + 1.25, p.y), Vector3(0.9, 0.5, 1.2), dark, yaw, false)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var w := MeshInstance3D.new()
			w.mesh = wheel_mesh
			w.material_override = dark
			w.position = Vector3(p.x, y + 0.42, p.y) + basis * Vector3(sx * 0.82, 0, sz * 0.62)
			w.rotation = Vector3(0, yaw, PI * 0.5)
			root.add_child(w)
	# Cab frame and roof.
	for sx in [-0.75, 0.75]:
		for sz in [-0.42, 0.42]:
			_box(root, Vector3(p.x, y + 1.85, p.y) + basis * Vector3(sx, 0, sz),
					Vector3(0.09, 1.6, 0.09), steel, yaw, false)
	_box(root, Vector3(p.x, y + 2.65, p.y), Vector3(1.9, 0.12, 1.3), yellow, yaw, false)
	# Mast, forks and hydraulic ram.
	var mast_p := Vector3(p.x, y, p.y) + basis * Vector3(1.25, 0, 0)
	_box(root, mast_p + Vector3(0, 1.7, 0), Vector3(0.18, 3.4, 0.9), steel, yaw, false)
	_box(root, mast_p + basis * Vector3(0.35, 0.18, 0), Vector3(0.9, 0.10, 0.18), steel, yaw, false)
	_box(root, mast_p + basis * Vector3(0.35, 0.18, 0.55), Vector3(0.9, 0.10, 0.18), steel, yaw, false)
	_cyl(root, mast_p + basis * Vector3(-0.35, 1.6, 0), 0.08, 2.2, steel)


static func _burning_barrel(root: Node3D, p: Vector2) -> void:
	var y := _h(p.x, p.y)
	# Blackened barrel, fire glow and a thin smoke column.
	var barrel := FT._pbr("steel", Color(0.16, 0.14, 0.12), 0.45)
	_cyl(root, Vector3(p.x, y + 0.5, p.y), 0.34, 1.0, barrel)
	var fire_mat := FT._mat(Color(1.0, 0.55, 0.15), 0.4)
	fire_mat.emission_enabled = true
	fire_mat.emission = Color(1.0, 0.42, 0.08)
	fire_mat.emission_energy_multiplier = 4.0
	_cyl(root, Vector3(p.x, y + 1.02, p.y), 0.20, 0.08, fire_mat)
	var light := OmniLight3D.new()
	light.position = Vector3(p.x, y + 1.5, p.y)
	light.omni_range = 12.0
	light.light_energy = 2.4
	light.light_color = Color(1.0, 0.55, 0.24)
	light.shadow_enabled = false
	root.add_child(light)
	# Smoke: low particles, only one emitter per yard.
	var smoke := GPUParticles3D.new()
	smoke.amount = 28
	smoke.lifetime = 5.0
	smoke.preprocess = 2.0
	smoke.position = Vector3(p.x, y + 1.2, p.y)
	smoke.visibility_aabb = AABB(Vector3(-8, -2, -8), Vector3(16, 14, 16))
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.25
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.0
	pm.gravity = Vector3(0.15, 0.1, 0.05)
	pm.scale_min = 0.4
	pm.scale_max = 1.5
	pm.color = Color(0.18, 0.16, 0.14, 0.22)
	smoke.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(2.4, 2.4)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	sm.albedo_texture = FT._soft_smoke_texture()
	sm.albedo_color = Color(0.20, 0.18, 0.16, 0.20)
	quad.material = sm
	smoke.draw_pass_1 = quad
	root.add_child(smoke)
	smoke.emitting = true


static func _pebbles(root: Node3D, center: Vector2, radius: float, count: int) -> void:
	_unit_meshes()
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 0.6
	mesh.radial_segments = 5
	mesh.rings = 2
	var mat := FT._pbr("rock", Color(0.56, 0.53, 0.46), 0.45)
	var xfs: Array = []
	for i in range(count):
		var a := _rng.randf_range(0.0, TAU)
		var r := sqrt(_rng.randf()) * radius
		var x := center.x + cos(a) * r
		var z := center.y + sin(a) * r
		var y := _h(x, z)
		var s := _rng.randf_range(0.035, 0.16)
		xfs.append(Transform3D(Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(
				Vector3(s * _rng.randf_range(0.8, 1.6), s * 0.45, s)), Vector3(x, y + s * 0.12, z)))
	var mmi := FT._multimesh(root, "YardPebbles", mesh, mat, xfs, false)
	if mmi != null:
		mmi.visibility_range_end = 70.0
		mmi.visibility_range_end_margin = 12.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


static func _yard_ground_detail(root: Node3D, center: Vector2, w: float, d: float) -> void:
	var concrete := FT._pbr("concrete", Color(0.75, 0.73, 0.67), 0.30)
	var crack := FT._mat(Color(0.10, 0.09, 0.08), 0.95)
	var stain := FT._mat(Color(0.12, 0.11, 0.09), 0.85)
	var patches := [
		[Vector2(-w * 0.28, -d * 0.24), Vector2(7.0, 4.5)],
		[Vector2(w * 0.18, d * 0.26), Vector2(9.0, 5.0)],
		[Vector2(w * 0.30, -d * 0.10), Vector2(6.0, 7.0)],
	]
	for p in patches:
		var pp: Vector2 = center + (p[0] as Vector2)
		var sz: Vector2 = p[1]
		_box(root, Vector3(pp.x, _h(pp.x, pp.y) + 0.075, pp.y),
				Vector3(sz.x, 0.05, sz.y), concrete,
				_rng.randf_range(-0.2, 0.2), false)
	# Expansion joints: segmented so they follow the terrain height instead of
	# cutting a straight line through a hill.
	var joint := FT._mat(Color(0.13, 0.12, 0.10), 0.95)
	var joint_cols := int(w / 8.0)
	var joint_rows := int(d / 8.0)
	for j in range(joint_rows):
		for i in range(joint_cols):
			var gx := center.x - w * 0.5 + (float(i) + 0.5) * 8.0
			var gz := center.y - d * 0.5 + float(j) * 8.0
			_box(root, Vector3(gx, _h(gx, gz) + 0.075, gz),
					Vector3(0.07, 0.02, 8.0), joint, 0, false)
			_box(root, Vector3(gx, _h(gx, gz) + 0.075, gz),
					Vector3(8.0, 0.02, 0.07), joint, 0, false)
	# Manhole covers and a drain grate.
	for mp in [center + Vector2(-12.0, 8.0), center + Vector2(14.0, -9.0)]:
		var disc := CylinderMesh.new()
		disc.top_radius = 0.62
		disc.bottom_radius = 0.62
		disc.height = 0.04
		disc.radial_segments = 16
		var mm := MeshInstance3D.new()
		mm.mesh = disc
		mm.material_override = FT._pbr("steel", Color(0.28, 0.27, 0.24), 0.55)
		mm.position = Vector3(mp.x, _h(mp.x, mp.y) + 0.075, mp.y)
		mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mm)
	# Cracks: a handful of long, thin dark seams.
	for i in range(9):
		var a := _rng.randf_range(0.0, TAU)
		var r := sqrt(_rng.randf()) * 22.0
		var px := center.x + cos(a) * r
		var pz := center.y + sin(a) * r
		var length := _rng.randf_range(3.0, 9.0)
		_box(root, Vector3(px, _h(px, pz) + 0.085, pz),
				Vector3(length, 0.02, 0.08), crack,
				_rng.randf_range(0.0, TAU), false)
	# Oil stains under the wreck and around the containers.
	for i in range(4):
		var a := _rng.randf_range(0.0, TAU)
		var r := sqrt(_rng.randf()) * 16.0
		var px := center.x + cos(a) * r
		var pz := center.y + sin(a) * r
		var disc := SphereMesh.new()
		disc.radius = _rng.randf_range(0.6, 1.6)
		disc.height = 0.025
		disc.radial_segments = 16
		disc.rings = 2
		var mi := MeshInstance3D.new()
		mi.mesh = disc
		mi.material_override = stain
		mi.position = Vector3(px, _h(px, pz) + 0.06, pz)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)


static func _forecourt(root: Node3D, center: Vector2, factor: float = 1.0) -> void:
	var y := _h(center.x, center.y)
	var concrete := FT._pbr("concrete", Color(0.64, 0.63, 0.58), 0.30)
	var rust := FT._pbr("steel", Color(0.46, 0.27, 0.17), 0.38)
	var wood := FT._pbr("wood", Color(0.46, 0.36, 0.25), 0.45)
	var steel := FT._pbr("steel", Color(0.36, 0.39, 0.40), 0.34)
	# Concrete pipes, stacked in a pyramid (heavier geometry only on High).
	for row in range(2 if factor >= 0.6 else 0):
		for i in range(2 - row):
			var px := center.x - 2.0 + float(i) * 2.2 + float(row) * 1.1
			var py := y + 0.78 + float(row) * 1.38
			var b := Basis(Vector3.UP, 0.15) * Basis(Vector3.RIGHT, PI * 0.5) * \
					Basis().scaled(Vector3(0.78, 4.4, 0.78))
			var mi := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 1.0
			cyl.bottom_radius = 1.0
			cyl.height = 1.0
			cyl.radial_segments = 14
			mi.mesh = cyl
			mi.material_override = concrete
			mi.transform = Transform3D(b, Vector3(px, py, center.y - 5.0))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			root.add_child(mi)
	# Workbench and tool clutter.
	_box(root, Vector3(center.x + 4.0, y + 0.85, center.y + 1.8),
			Vector3(2.8, 0.12, 1.0), wood, 0, false)
	for sx in [-1.2, 1.2]:
		for sz in [-0.35, 0.35]:
			_box(root, Vector3(center.x + 4.0 + sx, y + 0.4, center.y + 1.8 + sz),
					Vector3(0.10, 0.8, 0.10), steel, 0, false)
	# Pallets with crates, barrels and a generator around the door.
	_queue_prop("prop_pallet", center.x - 4.0, center.y + 5.0, 0.2, 1.0)
	_queue_prop("prop_crate", center.x - 4.0, center.y + 5.0, 0.5, 1.0)
	_queue_prop("prop_crate", center.x - 2.8, center.y + 5.4, 0.1, 0.9)
	_queue_prop("prop_barrel", center.x - 5.2, center.y + 4.0, 0.0, 1.0)
	_queue_prop("prop_barrel", center.x - 5.2, center.y + 5.2, 0.4, 1.0)
	_queue_prop("prop_generator", center.x + 6.0, center.y + 4.0, 0.3, 1.0)
	_prop(root, "prop_car_wreck", center.x + 1.0, center.y + 8.0, 1.2, 1.15)
	# Cable spools: a pair of large wooden discs on a steel axle.
	for i in range(2 if factor >= 0.6 else 0):
		var sp := Vector3(center.x + 7.0 + float(i) * 1.4, y + 0.85,
				center.y - 2.0)
		for side in [-1.0, 1.0]:
			var disc := CylinderMesh.new()
			disc.top_radius = 0.8
			disc.bottom_radius = 0.8
			disc.height = 0.12
			disc.radial_segments = 14
			var dmi := MeshInstance3D.new()
			dmi.mesh = disc
			dmi.material_override = wood
			dmi.position = sp + Vector3(0, 0, side * 0.65)
			dmi.rotation = Vector3(PI * 0.5, 0, 0)
			root.add_child(dmi)
		_box(root, sp, Vector3(0.12, 0.12, 1.3), steel, 0, false)
	# Sandbag position facing the gate.
	_asset_on(root, center + Vector2(8.0, 0.0), "sandbag_wall", 1.0)


static func _yard_fence(root: Node3D, a: Vector2, b: Vector2, mat: Material,
		gate: bool) -> void:
	var length := a.distance_to(b)
	var dir := (b - a) / maxf(length, 0.001)
	var count := int(length / 3.0)
	for i in range(count + 1):
		var p := a + dir * float(i) * 3.0
		if gate and absf(p.y - (a.y + b.y) * 0.5) < 4.4:
			continue
		var y := _h(p.x, p.y)
		_box(root, Vector3(p.x, y + 1.35, p.y), Vector3(0.10, 2.7, 0.10), mat)
		if i < count:
			var q := a + dir * (float(i) + 0.5) * 3.0
			var qy := _h(q.x, q.y)
			if gate and absf(q.y - (a.y + b.y) * 0.5) < 4.4:
				continue
			var yaw := atan2(dir.x, dir.y)
			for ry in [0.55, 1.25, 2.45]:
				_box(root, Vector3(q.x, qy + ry, q.y), Vector3(0.06, 0.06, 3.0),
						mat, yaw, false)


static func _floodlight(root: Node3D, p: Vector2) -> void:
	var y := _h(p.x, p.y)
	var steel := FT._pbr("steel", Color(0.36, 0.38, 0.37), 0.35)
	_cyl(root, Vector3(p.x, y + 5.2, p.y), 0.13, 10.4, steel)
	_box(root, Vector3(p.x, y + 10.5, p.y), Vector3(0.9, 0.28, 0.55), steel)
	var lamp_mat := FT._mat(Color(1.0, 0.86, 0.60), 0.4)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.72, 0.40)
	lamp_mat.emission_energy_multiplier = 2.8
	_box(root, Vector3(p.x, y + 10.32, p.y), Vector3(0.72, 0.10, 0.42), lamp_mat, 0, false)
	var light := OmniLight3D.new()
	light.position = Vector3(p.x, y + 10.0, p.y)
	light.omni_range = 36.0
	light.light_energy = 1.3
	light.light_color = Color(1.0, 0.80, 0.52)
	light.shadow_enabled = false
	root.add_child(light)


static func _guard_hut(root: Node3D, p: Vector2) -> void:
	var y := _h(p.x, p.y)
	var concrete := FT._pbr("concrete", Color(0.64, 0.63, 0.58), 0.3)
	var rust := FT._pbr("steel", Color(0.42, 0.27, 0.17), 0.38)
	var wood := FT._pbr("wood", Color(0.46, 0.38, 0.27), 0.45)
	var dark := FT._mat(Color(0.045, 0.045, 0.04), 0.9)
	_box(root, Vector3(p.x, y + 0.20, p.y), Vector3(4.2, 0.4, 3.6), concrete, 0, true)
	_box(root, Vector3(p.x, y + 1.7, p.y), Vector3(3.6, 2.9, 3.2), concrete, 0, true)
	_box(root, Vector3(p.x, y + 3.3, p.y), Vector3(4.0, 0.25, 3.6), rust, 0, false)
	_box(root, Vector3(p.x - 1.82, y + 2.0, p.y), Vector3(0.08, 1.2, 1.8), dark, 0, false)
	_box(root, Vector3(p.x, y + 1.0, p.y + 1.62), Vector3(1.0, 2.0, 0.08), wood, 0, false)
	# Small stove pipe.
	_cyl(root, Vector3(p.x + 1.2, y + 4.1, p.y + 0.8), 0.12, 1.6, rust)


static func _tank_cluster(root: Node3D, p: Vector2) -> void:
	var y := _h(p.x, p.y)
	var steel := FT._pbr("hall_metal", Color(0.50, 0.50, 0.46), 0.34)
	var rust := FT._pbr("hall_rust", Color(0.62, 0.42, 0.27), 0.38)
	var concrete := FT._pbr("concrete", Color(0.64, 0.63, 0.58), 0.30)
	# Composite assembly: tanks, ladders, rings, pipe bridge and bund share one
	# named container so the elevated runs validate against the grounded base.
	var tank_root := Node3D.new()
	tank_root.name = "TankCluster"
	root.add_child(tank_root)
	for k in range(2):
		var tx := p.x + float(k) * 9.0
		var tz := p.y + float(k % 2) * 4.0
		var ty := _h(tx, tz)
		_cyl(tank_root, Vector3(tx, ty + 4.5, tz), 3.2, 9.0, steel, true)
		_cyl(tank_root, Vector3(tx, ty + 9.1, tz), 3.3, 0.4, rust, false)
		_cyl(tank_root, Vector3(tx, ty + 9.5, tz), 1.1, 0.8, steel, false)
		for band in range(3):
			_cyl(tank_root, Vector3(tx, ty + 1.8 + float(band) * 2.8, tz), 3.3, 0.18,
					rust, false)
		for sz in [-0.35, 0.35]:
			_box(tank_root, Vector3(tx + 3.4, ty + 4.3, tz + sz),
					Vector3(0.07, 8.0, 0.07), steel, 0, false)
		for step in range(9):
			_box(tank_root, Vector3(tx + 3.4, ty + 0.4 + float(step) * 0.9, tz),
					Vector3(0.08, 0.08, 0.7), steel, 0, false)
	# Low bund wall around the tank farm.
	_box(tank_root, Vector3(p.x + 4.5, y + 0.5, p.y - 4.0), Vector3(22.0, 1.0, 0.5),
			concrete, 0, true)
	_box(tank_root, Vector3(p.x + 4.5, y + 0.5, p.y + 7.0), Vector3(22.0, 1.0, 0.5),
			concrete, 0, true)
	for sx in [-1.0, 1.0]:
		_box(tank_root, Vector3(p.x + 4.5 + sx * 10.8, y + 0.5, p.y + 1.5),
				Vector3(0.5, 1.0, 11.5), concrete, 0, true)
	# Pipe bridge between the tanks: give it real supports and collision so it
	# no longer reads as a beam floating in mid-air that the drone can cross.
	_box(tank_root, Vector3(p.x + 4.5, y + 6.5, p.y + 1.5), Vector3(10.0, 0.28, 0.28),
			rust, 0, true)
	for sx in [-4.5, 4.5]:
		_box(tank_root, Vector3(p.x + 4.5 + sx, y + 3.25, p.y + 1.5),
				Vector3(0.18, 6.5, 0.18), steel, 0, true)


static func _chimney(root: Node3D, p: Vector2) -> void:
	var y := _h(p.x, p.y)
	var brick := FT._pbr("hall_rust", Color(0.44, 0.30, 0.23), 0.40)
	var rust := FT._pbr("concrete", Color(0.52, 0.50, 0.46), 0.36)
	var dark := FT._mat(Color(0.06, 0.06, 0.055), 0.9)
	# Hollow brick stack with an open top and a base arch: the player can dive
	# in from above and leave through the bottom side.
	FT._open_tower(root, Vector3(p.x, y, p.y), 2.1, 0.72, 18.0,
			brick, dark,
			{"deg": 70.0, "min_h": 0.0, "max_h": 4.2, "count": 2},
			"HallChimney")
	for bh in [5.8, 9.8, 13.8, 17.4]:
		FT._add_ring(root, Vector3(p.x, y + bh, p.y),
				2.15, 0.15, rust)
	# Ladder on the solid side (at z + 2.50, clear of the +/-X base openings).
	# Two continuous side rails keep the rungs from reading as floating blocks
	# when the player flies past the chimney at FPV altitude.
	for sx in [-0.30, 0.30]:
		_box(root, Vector3(p.x + sx, y + 8.8, p.y + 2.35),
				Vector3(0.07, 16.6, 0.07), rust, 0, false)
	for step in range(13):
		_box(root, Vector3(p.x, y + 0.5 + float(step) * 1.30, p.y + 2.35),
				Vector3(0.6, 0.08, 0.08), rust, 0, false)


static func _watchtower(root: Node3D, p: Vector2) -> void:
	var y := _h(p.x, p.y)
	var steel := FT._pbr("steel", Color(0.32, 0.36, 0.35), 0.36)
	var wood := FT._pbr("wood", Color(0.42, 0.34, 0.24), 0.46)
	var rust := FT._pbr("steel", Color(0.44, 0.27, 0.17), 0.4)
	var dark := FT._mat(Color(0.05, 0.05, 0.045), 0.9)
	# Four splayed legs, three braces and a platform 8 m up.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_cyl(root, Vector3(p.x + sx * 1.35, y + 4.0, p.y + sz * 1.35), 0.13,
					8.0, steel)
	for h in [2.5, 5.0, 7.5]:
		var span := 2.7 - float(h) * 0.08
		_box(root, Vector3(p.x, y + h, p.y - span * 0.5), Vector3(span, 0.10, 0.10), steel)
		_box(root, Vector3(p.x, y + h, p.y + span * 0.5), Vector3(span, 0.10, 0.10), steel)
		_box(root, Vector3(p.x - span * 0.5, y + h, p.y), Vector3(0.10, 0.10, span), steel)
		_box(root, Vector3(p.x + span * 0.5, y + h, p.y), Vector3(0.10, 0.10, span), steel)
	_box(root, Vector3(p.x, y + 8.05, p.y), Vector3(3.6, 0.22, 3.6), wood, 0, true)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(root, Vector3(p.x + sx * 1.6, y + 9.0, p.y + sz * 1.6),
					Vector3(0.12, 2.0, 0.12), wood, 0, true)
	_box(root, Vector3(p.x, y + 10.05, p.y), Vector3(4.2, 0.18, 4.2), rust, 0, false)
	_box(root, Vector3(p.x, y + 10.2, p.y), Vector3(2.4, 0.8, 2.4), dark, 0, false)
	# Sandbag parapet and a searchlight.
	for i in range(6):
		_box(root, Vector3(p.x - 1.7 + float(i) * 0.68, y + 8.5, p.y + 1.7),
				Vector3(0.65, 0.55, 0.45), FT._pbr("sandbag", Color(0.52, 0.48, 0.34), 0.18),
				0, false)
	_box(root, Vector3(p.x + 1.9, y + 8.8, p.y), Vector3(0.6, 0.5, 0.6), rust, 0, false)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(p.x, y + 9.2, p.y)
	lamp.omni_range = 24.0
	lamp.light_energy = 0.8
	lamp.light_color = Color(1.0, 0.82, 0.55)
	lamp.shadow_enabled = false
	root.add_child(lamp)
	# Ladder.
	for sx in [-0.30, 0.30]:
		_box(root, Vector3(p.x - 2.2 + sx, y + 4.0, p.y),
				Vector3(0.07, 7.6, 0.07), steel, 0, false)
	for i in range(12):
		_box(root, Vector3(p.x - 2.2, y + 0.4 + float(i) * 0.65, p.y),
				Vector3(0.6, 0.07, 0.07), steel, 0, false)


static func _cone_heap(root: Node3D, p: Vector2, radius: float, height: float) -> void:
	var y := _h(p.x, p.y)
	var mat := FT._pbr("dirt", Color(0.38, 0.34, 0.27), 0.28)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.15
	cone.bottom_radius = radius
	cone.height = height
	cone.radial_segments = 16
	cone.rings = 3
	var mi := MeshInstance3D.new()
	mi.mesh = cone
	mi.material_override = mat
	mi.position = Vector3(p.x, y + height * 0.5, p.y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	# Spilled material around the base.
	_rubble(root, p, radius * 1.4, 22, "HeapSpill")


## Skylight strips and ridge vents.  The reference interior is defined by its
## broken roof lights; from outside the hall was a featureless black barrel.
static func _hall_roof_details(root: Node3D, c: Vector2, half: Vector2,
		gy: float, roof_h: float) -> void:
	var glass := FT._mat(Color(0.12, 0.18, 0.22), 0.12, 0.35)
	glass.emission_enabled = true
	glass.emission = Color(0.30, 0.42, 0.48)
	glass.emission_energy_multiplier = 0.35
	var frame := FT._pbr("steel", Color(0.44, 0.46, 0.44), 0.34)
	var dark := FT._mat(Color(0.045, 0.045, 0.04), 0.9)
	# Four longitudinal skylight runs; the roof height falls off towards the
	# eaves, so each row sits at an arch height derived from its z offset.
	for zoff in [-0.55, -0.18, 0.18, 0.55]:
		var z: float = c.y + half.y * float(zoff)
		var arch := gy + roof_h - pow(absf(float(zoff)) * 1.45, 2.0) * 2.0
		for i in range(4):
			var x := c.x - half.x * 0.42 + float(i) * half.x * 0.28
			_box(root, Vector3(x, arch + 0.18, z), Vector3(half.x * 0.23, 0.08, 2.4), glass)
			_box(root, Vector3(x, arch + 0.25, z - 1.22),
					Vector3(half.x * 0.24, 0.10, 0.12), frame, 0, false)
			_box(root, Vector3(x, arch + 0.25, z + 1.22),
					Vector3(half.x * 0.24, 0.10, 0.12), frame, 0, false)
		# Missing panels: one dark hole per run, like the authored interior.
		var miss := int(round(absf(float(zoff)) * 10.0)) % 4
		var mx := c.x - half.x * 0.42 + float(miss) * half.x * 0.28
		_box(root, Vector3(mx, arch + 0.27, z), Vector3(half.x * 0.2, 0.06, 2.1), dark, 0, false)
	# Ridge vents.
	for i in range(5):
		var vx := c.x - half.x * 0.65 + float(i) * half.x * 0.32
		_cyl(root, Vector3(vx, gy + roof_h + 1.0, c.y), 0.55, 1.8, frame)
		_box(root, Vector3(vx, gy + roof_h + 1.95, c.y), Vector3(1.3, 0.10, 1.3), dark, 0, false)


## Dresses the short end walls.  These are the first thing a pilot sees when
## flying out of the nave, but the authored hall is one flat concrete box on
## that face.  Portals, window grids, pilasters, downpipes and a tall painted
## sign turn it into a believable factory elevation.
static func _hall_end_details(root: Node3D, map_name: String, c: Vector2,
		half: Vector2, dir: float, gy: float, roof_h: float) -> void:
	var x := c.x + dir * (half.x + 0.10)
	var out := dir * 0.18
	var concrete := FT._pbr("hall_concrete", Color(0.76, 0.76, 0.74), 0.28)
	var rust := FT._pbr("steel", Color(0.48, 0.29, 0.18), 0.36)
	var steel := FT._pbr("hall_metal", Color(0.40, 0.43, 0.45), 0.32)
	var dark := FT._mat(Color(0.045, 0.045, 0.042), 0.9)
	var paint := FT._mat(Color(0.68, 0.59, 0.38), 0.65, 0.05)
	var grime := FT._mat(Color(0.25, 0.22, 0.18), 0.95)

	# Two roller-shutter loading doors, away from the central annex.
	for dz in [-15.0, 15.0]:
		var z: float = c.y + dz
		_box(root, Vector3(x + out, gy + 3.2, z), Vector3(0.18, 6.4, 6.4), dark)
		# Corrugated shutter ribs.
		for k in range(12):
			_box(root, Vector3(x + out * 1.8, gy + 0.5 + float(k) * 0.5, z),
					Vector3(0.06, 0.12, 6.2), rust)
		# Portal frame.
		for sz in [-1.0, 1.0]:
			_box(root, Vector3(x + out * 2.0, gy + 3.2, z + sz * 3.35),
					Vector3(0.35, 6.8, 0.35), concrete)
		_box(root, Vector3(x + out * 2.0, gy + 6.7, z),
				Vector3(0.35, 0.35, 7.1), concrete)
		# Dock light + number plate above the door.
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(x + dir * 1.0, gy + 7.4, z)
		lamp.omni_range = 16.0
		lamp.light_energy = 0.7
		lamp.light_color = Color(1.0, 0.78, 0.45)
		lamp.shadow_enabled = false
		root.add_child(lamp)
		_box(root, Vector3(x + out * 2.2, gy + 7.5, z),
				Vector3(0.12, 1.1, 2.2), paint)

	# Window grid on both sides of the central annex.
	for side in [-1.0, 1.0]:
		for row in range(2):
			for col in range(4):
				var wz: float = c.y + side * (8.5 + float(col) * 5.2)
				var wy := gy + 6.2 + float(row) * 4.4
				_box(root, Vector3(x + out * 1.6, wy - 1.45, wz),
						Vector3(0.18, 0.16, 2.7), concrete)
				_box(root, Vector3(x + out * 1.6, wy + 1.45, wz),
						Vector3(0.18, 0.16, 2.7), concrete)
				for mz in [-1.28, 0.0, 1.28]:
					_box(root, Vector3(x + out * 1.4, wy, wz + mz),
							Vector3(0.18, 2.7, 0.11), steel)

	# ---- entrance portal frame (keeps the central 14x11 m doorway completely open!) ----
	var annex_depth := 2.2
	var front_x := x + dir * annex_depth
	var cladding := FT._pbr("hall_metal", Color(0.32, 0.36, 0.37), 0.30)
	for side_z in [-7.8, 7.8]:
		_box(root, Vector3(x + dir * annex_depth * 0.5, gy + 5.6, c.y + side_z),
				Vector3(annex_depth, 11.2, 0.45), cladding)
		_box(root, Vector3(front_x, gy + 5.6, c.y + side_z),
				Vector3(0.45, 11.4, 0.65), steel)
	_box(root, Vector3(x + dir * annex_depth * 0.5, gy + 11.3, c.y),
			Vector3(annex_depth, 0.38, 16.2), cladding)
	# Canopy over the open entrance doorway.
	_box(root, Vector3(front_x + dir * 1.4, gy + 11.6, c.y),
			Vector3(4.8, 0.28, 17.0), steel)
	for cz in [-7.2, 7.2]:
		_box(root, Vector3(front_x + dir * 3.0, gy + 10.8, c.y + cz),
				Vector3(0.22, 1.4, 0.22), steel)
	# Concrete bollards to the sides of the open portal.
	for bz in [-9.2, -7.8, 7.8, 9.2]:
		_cyl(root, Vector3(front_x + dir * 5.2, gy + 0.55, c.y + bz),
				0.32, 1.1, concrete)
	# Warm entrance lighting under the canopy.
	for lz in [-4.0, 0.0, 4.0]:
		var entry_lamp := OmniLight3D.new()
		entry_lamp.position = Vector3(front_x + dir * 1.2, gy + 11.1, c.y + lz)
		entry_lamp.omni_range = 26.0
		entry_lamp.light_energy = 2.2
		entry_lamp.light_color = Color(1.0, 0.78, 0.50)
		entry_lamp.shadow_enabled = false
		root.add_child(entry_lamp)
	var wash := SpotLight3D.new()
	wash.position = Vector3(front_x + dir * 1.0, gy + 11.2, c.y)
	wash.spot_range = 34.0
	wash.spot_angle = 42.0
	wash.spot_attenuation = 1.2
	wash.light_energy = 3.6
	wash.light_color = Color(1.0, 0.80, 0.55)
	wash.light_volumetric_fog_energy = 2.5
	wash.shadow_enabled = false
	root.add_child(wash)
	FT._apply_look_at(wash, Vector3(front_x + dir * 7.0, gy + 0.5, c.y), Vector3.UP)

	# Pilasters and horizontal bands break the huge concrete plane.
	for pz in [-22.0, -11.0, 11.0, 22.0]:
		_box(root, Vector3(x + out * 0.8, gy + roof_h * 0.48, c.y + pz),
				Vector3(0.22, roof_h * 0.94, 0.55), concrete)
	# Corrugated metal cladding above the window head (from 11.8 m up to roof_h - 0.7 m, cleanly above the 11 m doorway).
	var corrugated := FT._pbr("hall_metal", Color(0.58, 0.60, 0.58), 0.30)
	if map_name == "village":
		corrugated = FT._pbr("brick", Color(0.78, 0.56, 0.44), 0.28)
	elif map_name == "wetlands":
		corrugated = FT._pbr("hall_rust", Color(0.56, 0.47, 0.36), 0.40)
	var clad_y0 := gy + 11.8
	var clad_y1 := gy + roof_h - 0.7
	_box(root, Vector3(x + out * 0.32, (clad_y0 + clad_y1) * 0.5, c.y),
			Vector3(0.10, clad_y1 - clad_y0, half.y * 1.94), corrugated, 0, false)
	for i in range(28):
		var rz: float = c.y - half.y * 0.95 + float(i) * half.y * 1.9 / 27.0
		_box(root, Vector3(x + out * 0.45, (clad_y0 + clad_y1) * 0.5, rz),
				Vector3(0.14, clad_y1 - clad_y0, 0.10), corrugated, 0, false)
	_box(root, Vector3(x + out * 0.50, clad_y0, c.y),
			Vector3(0.18, 0.22, half.y * 1.94), steel, 0, false)
	# Grime/water staining on the side wings (never across the central doorway).
	for side_s in [-1.0, 1.0]:
		var wing_w := half.y - 8.0
		if wing_w > 2.0:
			_box(root, Vector3(x + out * 0.55, gy + 0.45, c.y + side_s * (8.0 + wing_w * 0.5)),
					Vector3(0.10, 0.9, wing_w), grime, 0, false)
			for by in [4.6, 10.8]:
				_box(root, Vector3(x + out * 0.7, gy + by, c.y + side_s * (8.0 + wing_w * 0.5)),
						Vector3(0.16, 0.24, wing_w), concrete)
	for side in [-1.0, 1.0]:
		for col in range(4):
			var wz: float = c.y + side * (8.5 + float(col) * 5.2)
			var streak_h := 2.4 + float((col + 3) % 4) * 0.8
			_box(root, Vector3(x + out * 0.45, gy + 4.6 - streak_h * 0.5, wz),
					Vector3(0.08, streak_h, 0.22), grime, 0, false)
	# Downpipes at the corners and a sagging conduit.
	for pz in [-half.y + 1.0, half.y - 1.0]:
		_cyl(root, Vector3(x + dir * 0.55, gy + roof_h * 0.42, c.y + pz),
				0.12, roof_h * 0.84, rust)
	_box(root, Vector3(x + out * 2.4, gy + 8.6, c.y - half.y * 0.55),
			Vector3(0.12, 0.20, half.y * 0.75), rust)
	# Service pipes and weather streaks break up the remaining wall areas.
	for pz in [-18.0, 18.0]:
		_cyl(root, Vector3(x + out * 1.6, gy + 6.0, c.y + pz), 0.10, 11.6, rust)
		for by in [3.0, 6.5, 9.5]:
			_box(root, Vector3(x + out * 1.4, gy + by, c.y + pz),
					Vector3(0.28, 0.12, 0.28), steel, 0, false)
	for pz in [-20.0, -12.0, 12.0, 20.0]:
		var streak_h := 2.2 + float(int(absf(pz)) % 3) * 0.9
		_box(root, Vector3(x + out * 0.35, gy + roof_h * 0.92 - streak_h * 0.5,
				c.y + pz), Vector3(0.08, streak_h, 0.65), grime, 0, false)
	for pz in [-16.0, -9.0, 9.0, 16.0]:
		_box(root, Vector3(x + out * 0.45, gy + 0.55, c.y + pz),
				Vector3(0.14, 1.1, 1.2), FT._pbr("hall_moss",
				Color(0.35, 0.40, 0.24), 0.4), 0, false)
	# Faded works number painted directly on the concrete, instead of floating
	# 3D text: a small board keeps it in the material palette.
	var sign_board := FT._mat(Color(0.20, 0.19, 0.16), 0.75)
	_box(root, Vector3(front_x + dir * 0.30, gy + 12.4, c.y),
			Vector3(0.10, 2.2, 5.4), sign_board)
	var label := Label3D.new()
	label.text = "ЦЕХ 1" if dir > 0.0 else "ЦЕХ 2"
	label.font_size = 150
	label.pixel_size = 0.013
	label.modulate = Color(0.86, 0.78, 0.58, 0.92)
	label.outline_size = 12
	label.outline_modulate = Color(0.12, 0.11, 0.09, 0.9)
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.no_depth_test = false
	root.add_child(label)
	label.position = Vector3(front_x + dir * 0.40, gy + 12.4, c.y)
	label.rotation = Vector3(0.0, dir * PI * 0.5, 0.0)
	# A bolt-on steel staircase to the upper window level.
	for k in range(7):
		var step_x := x + dir * (1.0 + float(k) * 0.55)
		_box(root, Vector3(step_x, gy + 0.55 + float(k) * 0.62,
				c.y - half.y * 0.72), Vector3(0.55, 0.16, 1.1), steel, 0, false)
	for k in range(7):
		_box(root, Vector3(x + dir * (1.2 + float(k) * 0.55),
				gy + 1.2 + float(k) * 0.62, c.y - half.y * 0.72 - 0.65),
				Vector3(0.08, 1.0, 0.08), steel, 0, false)
	_box(root, Vector3(x + dir * 4.6, gy + 7.8, c.y - half.y * 0.72),
			Vector3(4.4, 0.16, 1.1), steel, 0, false)


static func _dress_apron(root: Node3D, map_name: String, p: Vector2,
		dir: float, factor: float) -> void:
	var gy := _h(p.x, p.y)
	var asphalt := FT._pbr("asphalt", Color(0.43, 0.43, 0.41), 0.20)
	var steel := FT._pbr("steel", Color(0.32, 0.38, 0.42), 0.26)
	var rust := FT._pbr("steel", Color(0.52, 0.29, 0.17), 0.24)
	var concrete := FT._pbr("concrete", Color(0.76, 0.75, 0.71), 0.24)
	var wood := FT._pbr("wood", Color(0.62, 0.52, 0.40), 0.38)
	var dark := FT._mat(Color(0.07, 0.07, 0.06), 0.9)

	# Big gravel/asphalt apron in front of the doors.
	_box(root, Vector3(p.x, gy + 0.025, p.y), Vector3(22.0, 0.05, 27.0), asphalt,
			0.0, false)
	_box(root, Vector3(p.x + dir * 5.0, gy + 0.06, p.y),
			Vector3(7.0, 0.06, 22.0), concrete, 0.0, false)

	# Containers: strong colour blocks with corrugations (thin vertical ribs).
	var containers := int(maxf(1.0, round(3.0 * factor)))
	for i in range(containers):
		var cx := p.x + dir * _rng.randf_range(2.0, 7.0)
		var cz := p.y + _rng.randf_range(-12.0, 12.0)
		var base_y := FT.footprint_min_height(_map, Vector2(cx, cz),
				6.05, 2.42, 0.0) - 0.06
		var cy := base_y + 1.25
		var col: Color = [Color(0.46, 0.20, 0.14), Color(0.20, 0.30, 0.38),
				Color(0.22, 0.34, 0.22)][i % 3]
		var cmat := FT._pbr("steel", col, 0.34)
		var stack := 1 + i % 2
		for s in range(stack):
			var box := _box(root, Vector3(cx, cy + float(s) * 2.50, cz),
					Vector3(6.05, 2.5, 2.42), cmat, 0.0, true)
			if s > 0:
				_tag_attached(box)
			for rib in range(7):
				_tag_attached(_box(root, Vector3(cx - 2.5 + float(rib) * 0.82,
						cy + float(s) * 2.50, cz - 1.24),
						Vector3(0.06, 2.35, 0.05), rust))
	# Concrete blocks / jersey barriers around the working area.
	for i in range(int(maxf(2.0, round(5.0 * factor)))):
		var bx := p.x + dir * _rng.randf_range(-2.0, 9.0)
		var bz := p.y + _rng.randf_range(-13.0, 13.0)
		var by := FT.footprint_min_height(_map, Vector2(bx, bz),
				2.4, 0.7, 0.0) + 0.46
		_box(root, Vector3(bx, by, bz), Vector3(2.4, 1.05, 0.7), concrete, 0.0, true)
		_tag_attached(_box(root, Vector3(bx, by + 0.55, bz),
				Vector3(1.1, 0.16, 0.55), rust))
		for hz in [-0.22, 0.0, 0.22]:
			_tag_attached(_box(root, Vector3(bx, by + 0.08, bz + hz),
					Vector3(2.42, 0.12, 0.13),
					FT._mat(Color(0.78, 0.62, 0.10) if int((hz + 0.22) * 100.0) % 2 == 0
					else Color(0.10, 0.09, 0.08), 0.65), 0, false))
	# Pallet stacks, crates and drums.
	_scatter_props(root, p, 10.0,
			["prop_crate", "prop_pallet", "prop_barrel", "prop_tire",
			"prop_generator", "prop_fuel_tank", "prop_ammo"], int(10.0 * factor))
	# A wrecked truck / APC gives the apron a story and a human scale.
	if _rng.randf() < 0.85:
		var wx := p.x + dir * _rng.randf_range(7.0, 11.0)
		var wz := p.y + _rng.randf_range(-6.0, 6.0)
		_prop(root, "prop_car_wreck", wx, wz, _rng.randf_range(0.0, TAU), 1.1)
	# Rubble + weeds at the edges of the apron.
	_rubble(root, Vector2(p.x + dir * 9.0, p.y), 8.0,
			int(maxf(28.0, 55.0 * factor)), "ApronRubble")
	var weed_base := Color(0.08, 0.11, 0.04)
	var weed_tip := Color(0.24, 0.26, 0.10)
	if map_name == "steppe":
		weed_base = Color(0.075, 0.080, 0.032)
		weed_tip = Color(0.22, 0.20, 0.075)
	elif map_name == "wetlands":
		weed_base = Color(0.07, 0.11, 0.04)
		weed_tip = Color(0.20, 0.28, 0.10)
	_weeds(root, p, 13.0, int(maxf(90.0, 220.0 * factor)), weed_base, weed_tip)
	if map_name == "wetlands":
		_puddle(root, Vector2(p.x + dir * 1.0, p.y + 4.0), 1.2)
		_puddle(root, Vector2(p.x + dir * 4.5, p.y - 3.0), 0.8)

	# Loading dock bumpers / door frame on the hall face.
	var door_x := p.x + dir * 1.2
	var door_z := p.y
	var door_gy := FT.footprint_min_height(_map, Vector2(door_x, door_z),
			0.6, 6.4, 0.0) - 0.08
	_box(root, Vector3(door_x, door_gy + 2.4, door_z - 3.0),
			Vector3(0.5, 4.8, 0.4), dark)
	_box(root, Vector3(door_x, door_gy + 2.4, door_z + 3.0),
			Vector3(0.5, 4.8, 0.4), dark)
	_tag_attached(_box(root, Vector3(door_x, door_gy + 4.9, door_z),
			Vector3(0.5, 0.4, 6.4), rust))

	# Workshop apron kept clear of buildings, huts and structures
	pass


static func _dress_loading_dock(root: Node3D, map_name: String, p: Vector2,
		length: float, factor: float) -> void:
	var gy := _h(p.x, p.y)
	var concrete := FT._pbr("concrete", Color(0.70, 0.69, 0.65), 0.30)
	var rust := FT._pbr("steel", Color(0.50, 0.30, 0.18), 0.28)
	var steel := FT._pbr("steel", Color(0.40, 0.44, 0.46), 0.30)
	# Raised dock slab + steps.
	_box(root, Vector3(p.x, gy + 0.45, p.y), Vector3(length, 0.9, 5.0), concrete, 0, true)
	for i in range(3):
		_box(root, Vector3(p.x + length * 0.5 - 1.5 - float(i) * 1.1,
				gy + 0.15 + float(i) * 0.22, p.y + 3.2),
				Vector3(1.1, 0.22, 1.0), concrete, 0, false)
	# Steel canopy over the dock, supported by slim columns.
	for i in range(int(maxf(3.0, round(length / 9.0)))):
		var cx := p.x - length * 0.45 + float(i) * (length * 0.9 /
				float(maxi(1, int(maxf(3.0, round(length / 9.0))) - 1)))
		_box(root, Vector3(cx, gy + 3.0, p.y - 2.2), Vector3(0.16, 6.0, 0.16), steel, 0, true)
	_box(root, Vector3(p.x, gy + 6.1, p.y - 1.4), Vector3(length, 0.18, 5.2), rust, 0, false)
	# Dock bumpers, crates and barrels.
	for i in range(int(maxf(4.0, round(10.0 * factor)))):
		var bx := p.x + _rng.randf_range(-length * 0.45, length * 0.45)
		var bz := p.y - 2.2 + _rng.randf_range(-0.5, 0.5)
		_box(root, Vector3(bx, gy + 1.1, bz), Vector3(0.3, 0.35, 0.3), rust)
		if i % 3 == 0:
			_queue_prop("prop_pallet", bx + 0.9, p.y - 1.6,
					_rng.randf_range(0.0, TAU), 1.0)
		elif i % 3 == 1:
			_queue_prop("prop_crate", bx, p.y - 1.6,
					_rng.randf_range(0.0, TAU), 1.0)


# ===========================================================================
#  Ruined outbuildings
# ===========================================================================
static func _dress_ruins(_root: Node3D, _map_name: String, _factor: float) -> void:
	return


static func _ruin_site(root: Node3D, p: Vector2, yaw: float, w: float, d: float,
		h: float, style: String) -> void:
	_used_sites.append(p)
	var gy := _h(p.x, p.y)
	var basis := Basis(Vector3.UP, yaw)
	var base := Vector3(p.x, gy, p.y)
	var wall: Material
	var slab: Material
	var wood: Material
	match style:
		"concrete":
			wall = FT._pbr("hall_concrete", Color(0.68, 0.68, 0.65), 0.34)
			slab = FT._pbr("hall_concrete", Color(0.60, 0.60, 0.58), 0.30)
		"plaster":
			wall = FT._pbr("plaster", Color(0.62, 0.58, 0.48), 0.32)
			slab = FT._pbr("concrete", Color(0.62, 0.60, 0.55), 0.30)
		_:
			wall = FT._pbr("brick", Color(0.62, 0.42, 0.34), 0.34)
			slab = FT._pbr("concrete", Color(0.62, 0.60, 0.55), 0.30)
	wood = FT._pbr("wood", Color(0.42, 0.32, 0.22), 0.45)
	var rust := FT._pbr("steel", Color(0.42, 0.24, 0.15), 0.38)

	# Foundation.
	_box(root, base + Vector3(0, 0.16, 0), Vector3(w + 0.8, 0.32, d + 0.8),
			slab, yaw, false)
	# Front wall with three window openings: sill, lintel and piers.
	var front_origin := base + basis * Vector3(0.0, 0.0, d * 0.5)
	var win_bottom := 1.1
	var win_top := minf(h - 0.45, 2.55)
	var win_w := 1.15
	var centers := [-w * 0.28, 0.0, w * 0.28]
	var edges: Array[float] = [-w * 0.5]
	for c in centers:
		edges.append(c - win_w * 0.5)
		edges.append(c + win_w * 0.5)
	edges.append(w * 0.5)
	for i in range(0, edges.size(), 2):
		var a: float = edges[i]
		var b: float = edges[i + 1]
		if b - a < 0.08:
			continue
		_box(root, front_origin + basis * Vector3((a + b) * 0.5, win_bottom * 0.5, 0),
				Vector3(b - a, win_bottom, 0.42), wall, yaw, true)
		var top_h := maxf(h - win_top, 0.15)
		_box(root, front_origin + basis * Vector3((a + b) * 0.5,
				win_top + top_h * 0.5, 0), Vector3(b - a, top_h, 0.42), wall, yaw, true)
	# Jagged side walls: three height chunks, one fallen.
	for sx in [-1.0, 1.0]:
		var side_o := base + basis * Vector3(sx * w * 0.5, 0.0, 0.0)
		var seg := d / 3.0
		for k in range(3):
			var sh: float = [h * 0.72, h * 0.44, h * 0.18][(k + (0 if sx > 0.0 else 1)) % 3]
			_box(root, side_o + basis * Vector3(0.0, sh * 0.5, -d * 0.5 + seg * (float(k) + 0.5)),
					Vector3(0.42, sh, seg - 0.1), wall, yaw, true)
	# Back wall stub.
	_box(root, base + basis * Vector3(-w * 0.22, h * 0.22, -d * 0.5),
			Vector3(w * 0.56, h * 0.44, 0.42), wall, yaw, true)
	# Collapsed roof slab leaning into the shell.
	var slab_pos := base + basis * Vector3(w * 0.10, h * 0.72, 0.0)
	var slab_xf := Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, 0.48),
			slab_pos)
	var slab_mi := MeshInstance3D.new()
	var slab_mesh := BoxMesh.new()
	slab_mesh.size = Vector3(w * 0.78, 0.28, d * 0.86)
	slab_mi.mesh = slab_mesh
	slab_mi.material_override = slab
	slab_mi.transform = slab_xf
	slab_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(slab_mi)
	# Roof beams protruding from the slab.
	for i in range(6):
		var bp := base + basis * Vector3(-w * 0.3 + float(i) * w * 0.12,
				h * 1.05, _rng.randf_range(-d * 0.35, d * 0.35))
		var b := Basis(Vector3.UP, yaw + _rng.randf_range(-0.5, 0.5)) \
				* Basis(Vector3.RIGHT, PI * 0.5 + _rng.randf_range(-0.2, 0.2)) \
				* Basis().scaled(Vector3(0.09, _rng.randf_range(2.0, 4.0), 0.09))
		var bm := MeshInstance3D.new()
		var bmesh := BoxMesh.new()
		bmesh.size = Vector3.ONE
		bm.mesh = bmesh
		bm.material_override = wood
		bm.transform = Transform3D(b, bp)
		root.add_child(bm)
	# Window frames around the real openings; the panes themselves are gone.
	for c in centers:
		_box(root, front_origin + basis * Vector3(c, win_top + 0.04, 0.18),
				Vector3(win_w + 0.18, 0.12, 0.2), slab, yaw, false)
		_box(root, front_origin + basis * Vector3(c, win_bottom - 0.06, 0.18),
				Vector3(win_w + 0.24, 0.12, 0.28), slab, yaw, false)
		for sx in [-1.0, 1.0]:
			_box(root, front_origin + basis * Vector3(c + sx * (win_w * 0.5 + 0.08),
					1.8, 0.2), Vector3(0.12, 1.5, 0.2), slab, yaw, false)
	# Rubble, bricks and weeds inside and outside.
	var q_level := QualityManager.get_active_level()
	var rubble_scale := 1.0 if q_level == QualityManager.Level.HIGH else \
			(0.55 if q_level == QualityManager.Level.MEDIUM else 0.3)
	_rubble(root, p, 9.0, int(maxf(24.0, 42.0 * rubble_scale)), "RuinRubble", true)
	_weeds(root, p, 8.0, 120, Color(0.11, 0.14, 0.055),
			Color(0.32, 0.34, 0.13))
	# A fallen sign / beam outside.
	_box(root, base + basis * Vector3(-w * 0.5 - 2.0, 0.25, d * 0.15),
			Vector3(3.0, 0.12, 0.5), wood, yaw + 0.5, false)
	_box(root, base + basis * Vector3(w * 0.5 + 1.2, 0.7, -d * 0.2),
			Vector3(0.35, 1.4, 0.35), rust, yaw, true)


# ===========================================================================
#  Fields, orchards and crop rows
# ===========================================================================
static func _dress_fields(root: Node3D, map_name: String, factor: float) -> void:
	if map_name == "industrial" or map_name == "wetlands" \
			or map_name == "promzona_plavni":
		return
	var fields: Array = []
	if map_name == "steppe":
		fields = [
			[Vector2(-40.0, 118.0), 82.0, 52.0, 0.0, "wheat"],
			[Vector2(110.0, 118.0), 74.0, 48.0, 0.10, "stubble"],
			[Vector2(-115.0, -48.0), 76.0, 52.0, 0.22, "wheat"],
			[Vector2(-48.0, 22.0), 70.0, 46.0, -0.35, "stubble"],
		]
	else:
		fields = [
			[Vector2(-28.0, 124.0), 78.0, 50.0, 0.15, "wheat"],
			[Vector2(114.0, 122.0), 70.0, 46.0, -0.20, "stubble"],
			[Vector2(-118.0, -24.0), 72.0, 48.0, 0.40, "plowed"],
			[Vector2(56.0, -96.0), 68.0, 48.0, 0.0, "orchard"],
		]
	for i in range(fields.size()):
		if factor < 0.6 and i > 2:
			break
		var f: Array = fields[i]
		_crop_field(root, f[0], float(f[1]), float(f[2]), float(f[3]),
				String(f[4]), factor)


static func _crop_field(root: Node3D, center: Vector2, w: float, d: float,
		yaw: float, kind: String, factor: float) -> void:
	# Field origin must be dry and outside the hero hall pad; otherwise the
	# rows would climb over the building or sink into a pond.
	var basis := Basis(Vector3.UP, yaw)
	for corner in [Vector2(-w * 0.5, -d * 0.5), Vector2(w * 0.5, -d * 0.5),
			Vector2(-w * 0.5, d * 0.5), Vector2(w * 0.5, d * 0.5)]:
		var cp := center + Vector2(basis.x.x * corner.x + basis.z.x * corner.y,
				basis.x.z * corner.x + basis.z.z * corner.y)
		if not _free(cp.x, cp.y, 0.0):
			return
	_used_sites.append(center)
	# Terrain-conforming patch with procedurally drawn rows.  A flat box used
	# to hover over the undulating ground and its 500 individual row boxes read
	# as painted stripes from the air; the shader path follows every hill and
	# keeps the field to one draw call.
	_field_patch(root, center, w, d, yaw, kind)
	if kind == "orchard":
		_orchard_rows(root, center, w, d, yaw, factor)
	# Field-edge track and boundary posts.
	var edge := center + Vector2(basis.z.x, basis.z.z) * (d * 0.5 + 3.0)
	FT._ribbon(root, PackedVector2Array([
			edge - Vector2(basis.x.x, basis.x.z) * w * 0.5,
			edge + Vector2(basis.x.x, basis.x.z) * w * 0.5]),
			3.0, FT._pbr("dirt", Color(0.42, 0.34, 0.26), 0.30), 0.07)
	var post_mat := FT._pbr("wood", Color(0.40, 0.32, 0.22), 0.45)
	for i in range(8):
		var px := -w * 0.5 + float(i) * w / 7.0
		var pp := center + _b2(basis, Vector3(px, 0.0, d * 0.5 + 4.0))
		if not _free(pp.x, pp.y, 0.0):
			continue
		var py := _h(pp.x, pp.y)
		_box(root, Vector3(pp.x, py + 0.65, pp.y), Vector3(0.14, 1.3, 0.14),
				post_mat, yaw, false)
	# A few hay bales / crop tufts at the edge, so the field reads at eye level.
	if kind == "wheat" or kind == "stubble":
		for i in range(int(maxf(5.0, 14.0 * factor))):
			var hp := center + _b2(basis, Vector3(
					_rng.randf_range(-w * 0.4, w * 0.4),
					0.0, _rng.randf_range(-d * 0.4, d * 0.4)))
			if not _free(hp.x, hp.y, 0.0):
				continue
			if _rng.randf() < 0.5:
				ASSETS.spawn_prop(root, "prop_hay",
						Vector3(hp.x, _h(hp.x, hp.y), hp.y),
						_rng.randf_range(0.0, TAU), _rng.randf_range(0.9, 1.35))
			else:
				_round_bale(root, Vector3(hp.x, _h(hp.x, hp.y), hp.y))


static func _field_patch(root: Node3D, center: Vector2, w: float, d: float,
		yaw: float, kind: String) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = CROP_SHADER
	var albedo := load("res://Assets/textures/terrain/dirt_albedo.png") as Texture2D
	var normal := load("res://Assets/textures/terrain/dirt_normal.png") as Texture2D
	var grass_n := load("res://Assets/textures/terrain/grass_normal.png") as Texture2D
	if albedo != null:
		mat.set_shader_parameter("dirt_albedo", albedo)
	if normal != null:
		mat.set_shader_parameter("dirt_normal", normal)
	if grass_n != null:
		mat.set_shader_parameter("grass_normal", grass_n)
	# Per-field material tuning: wheat, cut stubble, ploughed soil, orchard.
	var crop := Color(0.56, 0.47, 0.24)
	var soil := Color(0.34, 0.27, 0.18)
	var straw := Color(0.72, 0.61, 0.34)
	var spacing := 1.9
	var width := 0.48
	var stubble := 0.0
	var plowed := 0.0
	var trams := 1.0
	var rough := 0.92
	match kind:
		"stubble":
			crop = Color(0.52, 0.46, 0.29)
			soil = Color(0.36, 0.30, 0.21)
			spacing = 2.4
			width = 0.24
			stubble = 0.85
			trams = 0.0
		"plowed":
			crop = Color(0.33, 0.26, 0.18)
			soil = Color(0.31, 0.24, 0.16)
			spacing = 1.1
			width = 0.0
			plowed = 1.0
			trams = 0.0
			rough = 0.95
		"orchard":
			crop = Color(0.33, 0.42, 0.18)
			soil = Color(0.30, 0.30, 0.18)
			spacing = 4.0
			width = 1.0
			stubble = 0.15
			trams = 0.0
	mat.set_shader_parameter("crop_color", crop)
	mat.set_shader_parameter("soil_color", soil)
	mat.set_shader_parameter("straw_color", straw)
	mat.set_shader_parameter("row_spacing", spacing)
	mat.set_shader_parameter("row_width", width)
	mat.set_shader_parameter("stubble", stubble)
	mat.set_shader_parameter("plowed", plowed)
	mat.set_shader_parameter("tramlines", trams)
	mat.set_shader_parameter("roughness_base", rough)
	mat.set_shader_parameter("field_size", Vector2(w, d))
	var mesh := _field_mesh(center, w, d, yaw)
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.name = "CropField_" + kind
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


static func _field_mesh(center: Vector2, w: float, d: float, yaw: float) -> ArrayMesh:
	var nx := clampi(int(w / 2.5), 8, 100)
	var nz := clampi(int(d / 2.5), 8, 80)
	var stepx := w / float(nx)
	var stepz := d / float(nz)
	var basis := Basis(Vector3.UP, yaw)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var colors := PackedColorArray()
	verts.resize((nx + 1) * (nz + 1))
	normals.resize(verts.size())
	uvs.resize(verts.size())
	uv2s.resize(verts.size())
	colors.resize(verts.size())
	for j in range(nz + 1):
		for i in range(nx + 1):
			var vi := j * (nx + 1) + i
			var lx := -w * 0.5 + float(i) * stepx
			var lz := -d * 0.5 + float(j) * stepz
			var wp := Vector3(center.x, 0.0, center.y) + basis * Vector3(lx, 0.0, lz)
			var y := _h(wp.x, wp.z) + 0.055
			verts[vi] = wp + Vector3(0.0, y - wp.y, 0.0)
			verts[vi].y = y
			uvs[vi] = Vector2(lx, lz)
			uv2s[vi] = Vector2(wp.x, wp.z)
			# Macro/grain mask for the terrain shader (used by the yard slab;
			# the crop shader ignores vertex colours).
			var patch := 0.16 + 0.16 * (0.5 + 0.5 * sin(wp.x * 0.041 + wp.z * 0.027))
			var grain := 0.5 + 0.5 * sin(wp.x * 0.37 - wp.z * 0.29)
			colors[vi] = Color(patch, grain, 0.0, 1.0)
			# Analytic normal from the height field, matching the terrain mesh.
			var dhx := _h(wp.x + 0.8, wp.z) - _h(wp.x - 0.8, wp.z)
			var dhz := _h(wp.x, wp.z + 0.8) - _h(wp.x, wp.z - 0.8)
			normals[vi] = Vector3(-dhx, 1.6, -dhz).normalized()
	var indices := PackedInt32Array()
	indices.resize(nx * nz * 6)
	var k := 0
	for j in range(nz):
		for i in range(nx):
			var a := j * (nx + 1) + i
			var b := a + 1
			var c := a + (nx + 1)
			var dd := c + 1
			indices[k] = a
			indices[k + 1] = b
			indices[k + 2] = c
			indices[k + 3] = b
			indices[k + 4] = dd
			indices[k + 5] = c
			k += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _round_bale(root: Node3D, pos: Vector3) -> void:
	var mat := FT._pbr("grass", Color(0.72, 0.62, 0.38), 0.9)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.75
	cyl.bottom_radius = 0.75
	cyl.height = 1.15
	cyl.radial_segments = 12
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	mi.material_override = mat
	mi.position = pos + Vector3(0, 0.76, 0)
	mi.rotation = Vector3(PI * 0.5, _rng.randf_range(0.0, TAU), 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


static func _orchard_rows(root: Node3D, center: Vector2, w: float, d: float,
		yaw: float, factor: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var step := 12.0
	var rows := int(w / step)
	var cols := int(d / step)
	# The old orchard used a cylinder trunk and a smooth ellipsoid crown, which
	# read as a different species from the authored forest.  Use the shared
	# Blender oak library for every orchard row, batched into MultiMeshes.
	var oak: Dictionary = {}
	for v in VEGETATION.trees():
		if not bool(v.get("pine", false)):
			oak = v
			break
	if oak.is_empty():
		return
	var transforms: Array[Transform3D] = []
	for r in range(rows):
		for c in range(cols):
			if _rng.randf() < 0.12:
				continue
			var wp := Vector3(center.x, 0, center.y) + basis * Vector3(
					-w * 0.5 + (float(r) + 0.5) * step,
					0.0, -d * 0.5 + (float(c) + 0.5) * step)
			if not _free(wp.x, wp.z, 8.0):
				continue
			var p2 := Vector2(wp.x, wp.z)
			var too_close := false
			for tp in FT._placed_tree_positions:
				if p2.distance_to(tp) < 13.5:
					too_close = true
					break
			if too_close:
				continue
			FT._placed_tree_positions.append(p2)
			var y := _h(wp.x, wp.z)
			var s := _rng.randf_range(0.95, 1.35)
			var b := Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(
					Vector3(s, s, s))
			transforms.append(Transform3D(b, Vector3(wp.x, y, wp.z)))
	if transforms.is_empty():
		return
	for part in ["trunk", "leaves"]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = oak[part]
		mm.instance_count = transforms.size()
		for i in range(transforms.size()):
			mm.set_instance_transform(i, transforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Orchard_" + part
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)
	# The shader patch under the trees already supplies the orchard floor.


# ===========================================================================
#  Biome-specific set pieces
# ===========================================================================
static func _dress_steppe(root: Node3D, map_name: String, factor: float) -> void:
	# Fence line along the farm edge (kept compact inside ±150 m).
	var wood := FT._pbr("wood", Color(0.46, 0.37, 0.25), 0.45)
	for i in range(int(maxf(8.0, 18.0 * factor))):
		var x := 16.0 + float(i) * 4.5
		var z := 142.0 + 2.0 * sin(x * 0.05)
		if not _free(x, z, 0.0):
			continue
		var y := _h(x, z)
		_box(root, Vector3(x, y + 0.58, z), Vector3(0.12, 1.16, 0.12), wood)
		if i > 0:
			_box(root, Vector3(x - 2.25, y + 0.93, z), Vector3(4.4, 0.09, 0.07), wood)
			_box(root, Vector3(x - 2.25, y + 0.48, z), Vector3(4.4, 0.09, 0.07), wood)
	for i in range(int(maxf(3.0, 6.0 * factor))):
		var p := Vector2(54.0 + float(i) * 2.4, 146.0 + float(i % 3) * 1.4)
		if _free(p.x, p.y, 0.0):
			_round_bale(root, Vector3(p.x, _h(p.x, p.y), p.y))
	_tall_flowers(root, Vector2(36.0, 136.0), 10.0, int(maxf(20.0, 60.0 * factor)))


static func _dress_village(root: Node3D, map_name: String, factor: float) -> void:
	# Kitchen gardens + picket fences behind the showcase lane.
	var wood := FT._pbr("wood", Color(0.56, 0.44, 0.29), 0.45)
	var green := FT._pbr("grass", Color(0.30, 0.42, 0.16), 1.0)
	var soil := FT._pbr("dirt", Color(0.33, 0.26, 0.18), 0.25)
	for i in range(int(maxf(6.0, 14.0 * factor))):
		var x := 22.0 + float(i % 7) * 16.0 + _rng.randf_range(-2.0, 2.0)
		var z := 22.0 + float(i / 7) * 14.0 + _rng.randf_range(-2.0, 2.0)
		if not _free(x, z, 0.0):
			continue
		var y := _h(x, z)
		# vegetable beds
		_box(root, Vector3(x, y + 0.06, z), Vector3(4.2, 0.12, 2.5), soil, 0.0, false)
		for r in range(3):
			_box(root, Vector3(x - 1.3 + float(r) * 1.3, y + 0.17, z),
					Vector3(0.5, 0.15, 2.2), green, 0.0, false)
		# picket fence along the road side
		for k in range(6):
			_box(root, Vector3(x - 2.5 + float(k), y + 0.45, z + 1.55),
					Vector3(0.08, 0.9, 0.08), wood, 0.0, false)
	# Haystacks / woodpiles around the barns.
	for i in range(int(maxf(5.0, 12.0 * factor))):
		var p := Vector2(40.0 + _rng.randf_range(-10.0, 80.0),
				44.0 + _rng.randf_range(-12.0, 16.0))
		if not _free(p.x, p.y, 0.0):
			continue
		if i % 2 == 0:
			_round_bale(root, Vector3(p.x, _h(p.x, p.y), p.y))
		else:
			ASSETS.spawn_prop(root, "prop_logs",
					Vector3(p.x, _h(p.x, p.y), p.y), _rng.randf_range(0.0, TAU), 1.0)
	if factor >= 0.85:
		# Village pond with reeds and a small jetty.
		_pond(root, Vector2(-96.0, 96.0), 18.0, factor)
		# A small roadside bus stop / well shelter: strong human-scale detail.
		_bus_stop(root, Vector2(26.0, 62.0), 0.0)
		# Orchard behind the church.
		_orchard_block(root, Vector2(-18.0, -100.0), 58.0, 36.0, 0.0, factor)


static func _dress_industrial(root: Node3D, _map_name: String, factor: float) -> void:
	var rich := factor >= 0.85
	var scrap_p := Vector2(-42.0, 134.0)
	if _free(scrap_p.x, scrap_p.y, 16.0):
		_scrap_yard(root, scrap_p, 20.0, factor)
		if rich:
			_gantry_crane(root, scrap_p, 20.0, 14.0)
		FT.reserve_area(scrap_p, 18.0)
		_used_sites.append(scrap_p)
	# Container stacks in a clear yard outside hero halls & reserved corridors.
	for i in range(int(maxf(3.0, 6.0 * factor))):
		var p := Vector2(-64.0 + _rng.randf_range(-24.0, 24.0),
				68.0 + _rng.randf_range(-24.0, 24.0))
		if not _free(p.x, p.y, 6.0):
			continue
		FT.reserve_area(p, 5.0)
		_used_sites.append(p)
		var y := _h(p.x, p.y)
		var cmat := FT._pbr("steel", [Color(0.52, 0.22, 0.16),
				Color(0.18, 0.32, 0.42), Color(0.24, 0.38, 0.24)][i % 3], 0.32)
		for s in range(1 + i % 2):
			_box(root, Vector3(p.x, y + 1.3 + float(s) * 2.50, p.y),
					Vector3(6.0, 2.5, 2.4), cmat, _rng.randf_range(0.0, TAU), true)


static func _dress_wetlands(root: Node3D, _map_name: String, factor: float) -> void:
	# Wooden walkways through the reeds, a couple of boats and a drowned
	# concrete structure — only on open spots outside halls & reserved zones.
	if factor >= 0.85:
		for i in range(2):
			var start := Vector2(-88.0 + float(i) * 48.0, 96.0)
			if not FT._hall_clear_zone("wetlands", start.x, start.y) \
					and not FT._structure_clear_zone("wetlands", start.x, start.y, 8.0):
				_boardwalk(root, start, 32.0, PI * 0.5 + float(i) * 0.4, factor)
		for bw in [[Vector2(-46.0, 106.0), 0.4], [Vector2(-108.0, 64.0), 1.2]]:
			var bp: Vector2 = bw[0]
			if not FT._hall_clear_zone("wetlands", bp.x, bp.y) \
					and not FT._structure_clear_zone("wetlands", bp.x, bp.y, 8.0):
				_boat_wreck(root, bp, float(bw[1]))
				FT.reserve_area(bp, 8.0)
	var pump := Vector2(-24.0, 62.0)
	var steel := FT._pbr("steel", Color(0.34, 0.38, 0.34), 0.30)
	var concrete := FT._pbr("concrete", Color(0.55, 0.58, 0.54), 0.28)
	if _free(pump.x, pump.y, 8.0):
		var gy := _h(pump.x, pump.y)
		_box(root, Vector3(pump.x, gy + 0.9, pump.y), Vector3(3.0, 1.8, 3.0), concrete, 0.0, true)
		_cyl(root, Vector3(pump.x, gy + 2.2, pump.y), 0.7, 1.2, steel, false)
		_cyl(root, Vector3(pump.x, gy + 2.9, pump.y), 0.35, 0.8, steel, false)
		FT.reserve_area(pump, 7.0)
		_used_sites.append(pump)
	var stack := Vector2(-110.0, -76.0)
	if _free(stack.x, stack.y, 12.0):
		var sy := _h(stack.x, stack.y)
		var dark := FT._mat(Color(0.07, 0.06, 0.05), 0.95)
		FT._open_tower(root, Vector3(stack.x, sy, stack.y), 2.6, 0.72, 24.0,
				concrete, dark,
				{"deg": 70.0, "min_h": 0.0, "max_h": 4.2, "count": 2},
				"WetlandsChimney")
		for bh in [5.8, 13.5, 22.8]:
			FT._add_ring(root, Vector3(stack.x, sy + bh, stack.y),
					2.66, 0.15, steel)
		FT.reserve_area(stack, 12.0)
		_used_sites.append(stack)
	# Reeds along the new walkway edges.
	_reeds(root, Vector2(50.0, 100.0), 22.0, int(maxf(160.0, 420.0 * factor)))
	# Fallen power poles in the marsh: dark diagonal lines.
	for i in range(int(maxf(2.0, 5.0 * factor))):
		var p := Vector2(-60.0 + float(i) * 42.0, 120.0)
		if not _free(p.x, p.y, 0.0):
			continue
		var y := _h(p.x, p.y)
		var basis := Basis(Vector3.UP, _rng.randf_range(0.0, TAU)) \
				* Basis(Vector3.RIGHT, 0.9) \
				* Basis().scaled(Vector3(0.14, 7.0, 0.14))
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 1.0
		cm.bottom_radius = 1.0
		cm.height = 1.0
		cm.radial_segments = 6
		mi.mesh = cm
		mi.material_override = FT._pbr("wood", Color(0.27, 0.23, 0.17), 0.50)
		mi.transform = Transform3D(basis, Vector3(p.x, y + 0.4, p.y))
		root.add_child(mi)


## Merged map: industrial yard dressing in the north, marsh dressing in the
## south, and nothing on the authored training strip or bridge approaches.
static func _dress_promzona_plavni(root: Node3D, _map_name: String, factor: float) -> void:
	var rich := factor >= 0.85
	var north_sites := [Vector2(-170.0, -150.0), Vector2(-20.0, -120.0),
			Vector2(130.0, -130.0), Vector2(-70.0, -220.0)]
	for i in range(north_sites.size()):
		var p: Vector2 = north_sites[i]
		if absf(p.x + 225.0) < 42.0 or not _free(p.x, p.y, 10.0):
			continue
		if i == 0:
			_scrap_yard(root, p, 18.0, factor)
			if rich:
				_gantry_crane(root, p, 18.0, 13.0)
		elif i == 1:
			for k in range(4):
				var q := p + Vector2(float(k) * 7.0, 0.0)
				if not _free(q.x, q.y, 4.0):
					continue
				var y := _h(q.x, q.y)
				var cmat := FT._pbr("steel", [Color(0.52, 0.22, 0.16),
						Color(0.18, 0.32, 0.42), Color(0.24, 0.38, 0.24)][k % 3], 0.32)
				var cyaw := _rng.randf_range(0.0, TAU)
				var cy := FT.footprint_min_height(_map, q, 6.0, 2.4, cyaw)
				_box(root, Vector3(q.x, cy + 1.15, q.y), Vector3(6.0, 2.5, 2.4),
						cmat, cyaw, true)
		elif i == 2:
			_tank_cluster(root, p)
		else:
			_pipe_bridge(root, p + Vector2(-28.0, 0.0), p + Vector2(28.0, 0.0))
		FT.reserve_area(p, 14.0)
		_used_sites.append(p)
	var south_sites := [Vector2(-70.0, 195.0), Vector2(112.0, 188.0),
			Vector2(150.0, 258.0), Vector2(-120.0, 235.0)]
	for i in range(south_sites.size()):
		var p: Vector2 = south_sites[i]
		if absf(p.x + 225.0) < 42.0 or not _free(p.x, p.y, 10.0):
			continue
		match i:
			0:
				_boat_wreck(root, p, _rng.randf_range(0.0, TAU))
			1:
				_wind_pump(root, p)
			2:
				_drowned_ruin(root, p, 0.4)
			3:
				_boardwalk(root, p, 30.0, PI * 0.5, factor)
		FT.reserve_area(p, 12.0)
		_used_sites.append(p)
	_reeds(root, Vector2(110.0, 205.0), 26.0,
			int(maxf(220.0, 520.0 * factor)))
	_reeds(root, Vector2(-80.0, 260.0), 22.0,
			int(maxf(160.0, 380.0 * factor)))


# ===========================================================================
#  Reusable set pieces
# ===========================================================================
static func _wind_pump(root: Node3D, p: Vector2) -> void:
	if not _free(p.x, p.y, 0.0):
		return
	var y := _h(p.x, p.y)
	var steel := FT._pbr("steel", Color(0.38, 0.40, 0.39), 0.35)
	var rust := FT._pbr("steel", Color(0.48, 0.27, 0.16), 0.40)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var b := Basis(Vector3.UP, 0.78 * float(1 if sx * sz > 0 else -1))
			var mi := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.13, 7.2, 0.13)
			mi.mesh = box
			mi.material_override = steel
			mi.transform = Transform3D(b, Vector3(p.x + sx * 1.3, y + 3.5, p.y + sz * 1.3))
			root.add_child(mi)
	_box(root, Vector3(p.x, y + 7.2, p.y), Vector3(3.1, 0.18, 3.1), rust)
	_cyl(root, Vector3(p.x, y + 7.8, p.y), 0.16, 1.2, steel, false)
	var wheel := MeshInstance3D.new()
	var fan := CylinderMesh.new()
	fan.top_radius = 2.8
	fan.bottom_radius = 2.8
	fan.height = 0.10
	fan.radial_segments = 14
	wheel.mesh = fan
	wheel.material_override = rust
	wheel.position = Vector3(p.x, y + 8.3, p.y + 0.2)
	wheel.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	root.add_child(wheel)
	# Tail vane.
	_box(root, Vector3(p.x, y + 7.9, p.y - 3.0), Vector3(0.1, 1.3, 3.4), steel, 0, false)
	for i in range(8):
		var a := TAU * float(i) / 8.0
		_box(root, Vector3(p.x + cos(a) * 1.6, y + 8.3, p.y + 0.25 + sin(a) * 1.6),
				Vector3(0.08, 2.0, 0.08), steel, 0, false)


static func _water_tower(root: Node3D, p: Vector2) -> void:
	if not _free(p.x, p.y, 0.0):
		return
	var y := _h(p.x, p.y)
	var concrete := FT._pbr("concrete", Color(0.66, 0.65, 0.60), 0.30)
	var steel := FT._pbr("steel", Color(0.36, 0.40, 0.41), 0.32)
	var rust := FT._pbr("steel", Color(0.46, 0.28, 0.18), 0.36)
	# Composite assembly: legs, colliders, rings, tank and ladder share one
	# named container so the elevated parts validate against the grounded legs.
	var tower_root := Node3D.new()
	tower_root.name = "WaterTower"
	root.add_child(tower_root)
	# Four tapered legs.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var b := Basis(Vector3.UP, 0.0).scaled(Vector3(0.28, 9.0, 0.28))
			b = b.rotated(Vector3.RIGHT, 0.08 * sz).rotated(Vector3.FORWARD, -0.08 * sx)
			var leg := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3.ONE
			leg.mesh = box
			leg.material_override = steel
			leg.transform = Transform3D(b, Vector3(p.x + sx * 2.1, y + 4.5, p.y + sz * 2.1))
			tower_root.add_child(leg)
			# Solid layer-1 collider for each tapered steel leg.
			var leg_body := StaticBody3D.new()
			leg_body.name = "WaterTowerLegCollision"
			leg_body.collision_layer = 1
			leg_body.collision_mask = 1
			leg_body.transform = Transform3D(b.orthonormalized(), leg.transform.origin)
			var leg_shape := BoxShape3D.new()
			leg_shape.size = Vector3(0.28, 9.0, 0.28)
			var leg_cs := CollisionShape3D.new()
			leg_cs.shape = leg_shape
			leg_body.add_child(leg_cs)
			tower_root.add_child(leg_body)
	for h in [3.0, 6.0]:
		_box(tower_root, Vector3(p.x, y + h, p.y), Vector3(4.6 - (h - 3.0) * 0.3, 0.12, 4.6 - (h - 3.0) * 0.3), steel)
	# Open-top, open-bottom tank: a vertical fly-through landmark.
	FT._open_tower(tower_root, Vector3(p.x, y + 9.5, p.y), 3.0, 0.30, 3.4,
			concrete, FT._mat(Color(0.07, 0.06, 0.05), 0.95), {},
			"WaterTowerTank")
	FT._add_ring(tower_root, Vector3(p.x, y + 9.5, p.y), 3.0, 0.12, rust)
	FT._add_ring(tower_root, Vector3(p.x, y + 12.9, p.y), 3.0, 0.12, rust)
	# Ladder up the side.
	for sz in [-0.40, 0.40]:
		_box(tower_root, Vector3(p.x + 3.1, y + 6.2, p.y + sz),
				Vector3(0.07, 11.4, 0.07), steel, 0, false)
	for i in range(14):
		_box(tower_root, Vector3(p.x + 3.1, y + 0.5 + float(i) * 0.8, p.y),
				Vector3(0.08, 0.1, 0.8), steel, 0, false)


static func _bus_stop(root: Node3D, p: Vector2, yaw: float) -> void:
	if not _free(p.x, p.y, 0.0):
		return
	var y := _h(p.x, p.y)
	var brick := FT._pbr("brick", Color(0.62, 0.46, 0.36), 0.32)
	var concrete := FT._pbr("concrete", Color(0.66, 0.64, 0.58), 0.30)
	var wood := FT._pbr("wood", Color(0.42, 0.34, 0.24), 0.45)
	var dark := FT._mat(Color(0.07, 0.07, 0.06), 0.9)
	_box(root, Vector3(p.x, y + 0.12, p.y), Vector3(4.6, 0.24, 2.6), concrete, yaw, true)
	for sx in [-1.1, 1.1]:
		_box(root, Vector3(p.x + sx, y + 1.45, p.y - 0.6), Vector3(0.16, 2.5, 0.16), wood, yaw, true)
	_box(root, Vector3(p.x, y + 2.75, p.y - 0.6), Vector3(3.0, 0.15, 2.5), concrete, yaw, true)
	_box(root, Vector3(p.x, y + 0.85, p.y - 1.05), Vector3(3.8, 0.1, 0.45), wood, yaw, false)
	# A faded poster board and bench.
	_box(root, Vector3(p.x + 2.2, y + 1.4, p.y - 0.2), Vector3(0.12, 1.8, 1.1), dark, yaw, true)
	_box(root, Vector3(p.x - 0.6, y + 0.7, p.y - 0.3), Vector3(1.6, 0.12, 0.5), wood, yaw, false)


static func _pond(root: Node3D, center: Vector2, radius: float, factor: float) -> void:
	var y := FT.water_level(_map) + 0.02
	# Water disc; the existing water shader is loaded by FrontlineTerrain.
	var water_path := "res://Assets/water.gdshader"
	if not ResourceLoader.exists(water_path):
		return
	var mat := ShaderMaterial.new()
	mat.shader = load(water_path)
	mat.set_shader_parameter("ripple_normal", FT._water_normal_tex())
	mat.set_shader_parameter("ripple_scale", 0.055)
	mat.set_shader_parameter("sky_reflect", Color(0.36, 0.55, 0.80))
	mat.set_shader_parameter("sky_amount", 0.62)
	var disc := SphereMesh.new()
	disc.radius = radius
	disc.height = 0.05
	disc.radial_segments = 24
	disc.rings = 2
	var mi := MeshInstance3D.new()
	mi.mesh = disc
	mi.material_override = mat
	mi.position = Vector3(center.x, y, center.y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	# Muddy bank ring: a darker disc slightly larger and a touch lower.
	var bank := SphereMesh.new()
	bank.radius = radius + 2.5
	bank.height = 0.06
	bank.radial_segments = 24
	bank.rings = 2
	var bm := MeshInstance3D.new()
	bm.mesh = bank
	bm.material_override = FT._pbr("mud", Color(0.46, 0.38, 0.24), 0.2)
	bm.position = Vector3(center.x, y - 0.04, center.y)
	bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(bm)
	# Jetty.
	var wood := FT._pbr("wood", Color(0.34, 0.28, 0.19), 0.5)
	for i in range(6):
		_box(root, Vector3(center.x + radius * 0.35 + float(i) * 1.6, y + 0.32,
				center.y), Vector3(1.6, 0.12, 2.4), wood, 0, false)
		if i % 2 == 0:
			_cyl(root, Vector3(center.x + radius * 0.35 + float(i) * 1.6, y + 0.1, center.y + 1.0),
					0.1, 1.3, wood, false)
	_reeds(root, center, radius * 0.9, int(maxf(60.0, 160.0 * factor)))


static func _reeds(root: Node3D, center: Vector2, radius: float, count: int) -> void:
	if _crop_mesh == null:
		_crop_mesh = FOLIAGE.create_grass_mesh(6, 2.8)
	var mat := ShaderMaterial.new()
	mat.shader = GRASS_SHADER
	mat.set_shader_parameter("grass_base_color", Vector3(0.040, 0.060, 0.023))
	mat.set_shader_parameter("grass_tip_color", Vector3(0.110, 0.140, 0.058))
	mat.set_shader_parameter("wind_strength", 0.08)
	var xfs: Array = []
	for i in range(count):
		var a := _rng.randf_range(0.0, TAU)
		var r := radius + _rng.randf_range(-5.0, 4.0)
		var x := center.x + cos(a) * r
		var z := center.y + sin(a) * r
		var y := _h(x, z)
		if y < FT.water_level(_map) - 0.3 or y > FT.water_level(_map) + 0.7:
			continue
		var b := Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(
				Vector3(_rng.randf_range(0.8, 1.4), _rng.randf_range(5.0, 8.5),
						_rng.randf_range(0.8, 1.4)))
		xfs.append(Transform3D(b, Vector3(x, y, z)))
	var mmi := FT._multimesh(root, "PondReeds", _crop_mesh, mat, xfs, false)
	if mmi != null:
		mmi.visibility_range_end = 160.0
		mmi.visibility_range_end_margin = 22.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


static func _tall_flowers(root: Node3D, center: Vector2, radius: float, count: int) -> void:
	var stem := FT._pbr("grass", Color(0.32, 0.38, 0.12), 0.9)
	var head := FT._pbr("grass", Color(0.92, 0.68, 0.12), 0.8)
	for i in range(count):
		var a := _rng.randf_range(0.0, TAU)
		var r := sqrt(_rng.randf()) * radius
		var x := center.x + cos(a) * r
		var z := center.y + sin(a) * r
		if not _free(x, z, 0.0):
			continue
		var y := _h(x, z)
		_cyl(root, Vector3(x, y + 0.75, z), 0.025, 1.5, stem, false)
		_cyl(root, Vector3(x, y + 1.52, z), 0.16, 0.08, head, false)


static func _orchard_block(root: Node3D, center: Vector2, w: float, d: float,
		yaw: float, factor: float) -> void:
	_crop_field(root, center, w, d, yaw, "orchard", factor)


static func _rail_yard(root: Node3D, center: Vector2, length: float, yaw: float,
		factor: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var steel := FT._pbr("steel", Color(0.30, 0.29, 0.27), 0.34)
	var wood := FT._pbr("wood", Color(0.28, 0.23, 0.17), 0.55)
	var gravel := FT._pbr("dirt", Color(0.35, 0.33, 0.29), 0.3)
	var gy := _h(center.x, center.y)
	_box(root, Vector3(center.x, gy + 0.04, center.y), Vector3(length, 0.08, 6.0),
			gravel, yaw, false)
	for side in [-1.0, 1.0]:
		_box(root, Vector3(center.x, gy + 0.18, center.y) +
				basis * Vector3(0.0, 0.0, side * 0.72),
				Vector3(length, 0.12, 0.12), steel, yaw)
	for i in range(int(length / 1.2)):
		_box(root, Vector3(center.x, gy + 0.12, center.y) +
				basis * Vector3(-length * 0.5 + float(i) * 1.2, 0.0, 0.0),
				Vector3(0.9, 0.12, 2.0), wood, yaw)
	# Two freight wagons: box body, wheels, rusty roof.
	for w in range(2):
		var wp := Vector3(center.x, gy, center.y) + basis * Vector3(
				-length * 0.2 + float(w) * 15.0, 0.0, 0.0)
		var body_mat := FT._pbr("steel", Color(0.28, 0.30, 0.28) if w == 0
				else Color(0.40, 0.22, 0.16), 0.36)
		_box(root, wp + Vector3(0, 1.9, 0), Vector3(8.6, 2.8, 2.8), body_mat, yaw, true)
		_box(root, wp + Vector3(0, 3.4, 0), Vector3(8.9, 0.14, 3.0),
				FT._pbr("steel", Color(0.34, 0.24, 0.18), 0.4), yaw, true)
		for side in [-1.0, 1.0]:
			for i in range(4):
				var wheel := MeshInstance3D.new()
				var cyl := CylinderMesh.new()
				cyl.top_radius = 0.38
				cyl.bottom_radius = 0.38
				cyl.height = 0.22
				cyl.radial_segments = 10
				wheel.mesh = cyl
				wheel.material_override = steel
				wheel.position = wp + basis * Vector3(-3.1 + float(i) * 2.05, 0.42, side * 1.25)
				wheel.rotation = Vector3(PI * 0.5, yaw, 0.0)
				root.add_child(wheel)


static func _scrap_yard(root: Node3D, center: Vector2, radius: float, factor: float) -> void:
	_rubble(root, center, radius, int(maxf(60.0, 150.0 * factor)), "ScrapRubble", true)
	for i in range(int(maxf(8.0, 20.0 * factor))):
		var a := _rng.randf_range(0.0, TAU)
		var r := sqrt(_rng.randf()) * radius
		var x := center.x + cos(a) * r
		var z := center.y + sin(a) * r
		if not _free(x, z, 0.0):
			continue
		var y := _h(x, z)
		var mat := FT._pbr("steel", [Color(0.36, 0.26, 0.18),
				Color(0.28, 0.30, 0.32), Color(0.42, 0.20, 0.14)][i % 3], 0.34)
		_box(root, Vector3(x, y + 0.4, z),
				Vector3(_rng.randf_range(1.0, 3.2), _rng.randf_range(0.3, 1.1),
						_rng.randf_range(0.8, 2.4)), mat,
				_rng.randf_range(0.0, TAU), false)


static func _gantry_crane(root: Node3D, center: Vector2, width: float,
		height: float) -> void:
	var steel := FT._pbr("steel", Color(0.42, 0.34, 0.22), 0.34)
	var y := _h(center.x, center.y)
	# Composite assembly: legs, bridge beam, trolley and hook share one named
	# container so the elevated runs validate against the grounded legs.
	var gantry := Node3D.new()
	gantry.name = "MovingGantryCrane"
	root.add_child(gantry)
	for side in [-1.0, 1.0]:
		for end in [-1.0, 1.0]:
			_box(gantry, Vector3(center.x + side * width * 0.5, y + height * 0.5,
					center.y + end * 3.0), Vector3(0.35, height, 0.35), steel, 0, true)
		_box(gantry, Vector3(center.x + side * width * 0.5, y + height,
				center.y), Vector3(0.35, 0.3, 6.5), steel, 0, true)
	_box(gantry, Vector3(center.x, y + height + 0.9, center.y),
			Vector3(width + 3.0, 0.5, 0.5), steel, 0, true)
	# Trolley + hook.
	_box(gantry, Vector3(center.x + 2.0, y + height + 0.35, center.y),
			Vector3(1.4, 0.6, 1.2), steel, 0, true)
	for i in range(5):
		_cyl(gantry, Vector3(center.x + 2.0, y + height - 0.2 - float(i) * 0.85,
				center.y), 0.035, 0.85, steel, false)
	_box(gantry, Vector3(center.x + 2.0, y + height - 4.6, center.y),
			Vector3(0.5, 0.5, 0.5), steel, 0, true)


static func _pipe_bridge(root: Node3D, a: Vector2, b: Vector2) -> void:
	var mid := (a + b) * 0.5
	var y := _h(mid.x, mid.y)
	var dir := b - a
	var yaw := atan2(dir.x, dir.y)
	var length := dir.length()
	var steel := FT._pbr("steel", Color(0.38, 0.38, 0.34), 0.36)
	var pipe_center := Vector3(mid.x, y + 7.0, mid.y)
	# Composite assembly: pipes, colliders, columns and saddles share one named
	# container so the elevated span validates against the grounded supports.
	var pb := Node3D.new()
	pb.name = "PipeBridge"
	root.add_child(pb)
	# Three parallel pipes on a light support frame.  Each pipe gets an exact
	# cylinder collider so the drone cannot fly through the horizontal steel.
	for side in [-0.7, 0.0, 0.7]:
		var b2 := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5) * \
				Basis().scaled(Vector3(0.26, length, 0.26))
		var mi := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.0
		cyl.bottom_radius = 1.0
		cyl.height = 1.0
		cyl.radial_segments = 8
		mi.mesh = cyl
		mi.material_override = steel
		var offset: Vector3 = Vector3(cos(yaw), 0.0, -sin(yaw)) * side
		var pipe_xf := Transform3D(b2, pipe_center + offset)
		mi.transform = pipe_xf
		pb.add_child(mi)
		var pipe_body := StaticBody3D.new()
		pipe_body.name = "PipeBridgePipeCollision"
		pipe_body.collision_layer = 1
		pipe_body.collision_mask = 1
		pipe_body.transform = Transform3D(b2.orthonormalized(), pipe_center + offset)
		var pipe_shape := CylinderShape3D.new()
		pipe_shape.radius = 0.26
		pipe_shape.height = length
		var pipe_cs := CollisionShape3D.new()
		pipe_cs.shape = pipe_shape
		pipe_body.add_child(pipe_cs)
		pb.add_child(pipe_body)
	# Vertical support columns every ~14 m, anchored 0.5 m below the lowest
	# terrain point so no horizontal pipe span can float in mid-air.
	var support_count := maxi(1, int(ceil(length / 14.0)))
	for i in range(support_count + 1):
		var t := float(i) / float(support_count)
		var sp := a.lerp(b, t)
		var gy := _h(sp.x, sp.y)
		var bottom := minf(gy, y) - 0.5
		var top := y + 7.0
		if top <= bottom + 0.5:
			continue
		var col_center := Vector3(sp.x, (bottom + top) * 0.5, sp.y)
		_cyl(pb, col_center, 0.28, top - bottom, steel, true)
		# Saddle under the pipe trio keeps the frame reading as a bridge.
		_box(pb, Vector3(sp.x, top - 0.32, sp.y),
				Vector3(2.4, 0.24, 0.32), steel, yaw, true)


static func _cooling_tower(root: Node3D, p: Vector2) -> void:
	if not _free(p.x, p.y, 0.0):
		return
	var y := _h(p.x, p.y)
	var concrete := FT._pbr("concrete", Color(0.74, 0.73, 0.69), 0.28)
	var rust := FT._pbr("steel", Color(0.40, 0.24, 0.15), 0.4)
	var interior := FT._pbr("concrete", Color(0.56, 0.54, 0.50), 0.42)
	# Hyperboloid profile: wide base, narrow waist, flared top.  The top is
	# fully open; two opposite 38-degree bays below it let the pilot dive in
	# from above and leave through the base of the shell.
	var profile: Array[Vector2] = [
		Vector2(15.5, 0.0), Vector2(14.2, 2.0), Vector2(12.4, 7.5),
		Vector2(10.6, 12.0), Vector2(9.4, 17.0), Vector2(9.0, 22.0),
		Vector2(9.4, 27.0), Vector2(10.3, 31.0), Vector2(11.0, 34.0),
	]
	FT._open_tower_profile(root, Vector3(p.x, y, p.y), profile, 0.80,
			concrete, interior,
			{"deg": 65.0, "min_h": 0.0, "max_h": 7.5, "count": 2},
			"CoolingTower")
	for i in range(8):
		var a := TAU * float(i) / 8.0
		_box(root, Vector3(p.x + cos(a) * 15.2, y + 0.9, p.y + sin(a) * 15.2),
				Vector3(0.35, 1.8, 0.35), rust, a, false)


## Segmented silo shell with two large opposite fly-through bays (4-12 m).
## A plain CylinderMesh left no way in; this lathe keeps the silhouette but
## omits side quads and builds matching trimesh collision.
static func _silo_shell(root: Node3D, base: Vector3, radius: float, height: float,
		mat: Material) -> void:
	var interior := FT._pbr("concrete", Color(0.62, 0.60, 0.56), 0.38)
	FT._open_tower(root, base, radius, 0.72, height, mat, interior,
			{"deg": 72.0, "min_h": 0.0, "max_h": 3.6, "count": 2},
			"SiloShell")


static func _silos(root: Node3D, p: Vector2, count: int) -> void:
	var concrete := FT._pbr("concrete", Color(0.70, 0.69, 0.64), 0.30)
	var steel := FT._pbr("steel", Color(0.42, 0.44, 0.43), 0.34)
	for i in range(count):
		var x := p.x + float(i) * 9.5
		var z := p.y + float(i % 2) * 5.5
		if not _free(x, z, 0.0):
			continue
		var y := _h(x, z)
		# Deep concrete foundation collar ensures the silo is never floating on terrain slopes
		_cyl(root, Vector3(x, y - 4.5, z), 3.8, 9.0, concrete, true)
		_silo_shell(root, Vector3(x, y, z), 3.6, 18.0, concrete)
		for sh in [5.5, 11.5, 17.5]:
			FT._add_ring(root, Vector3(x, y + sh, z), 3.65, 0.14, steel)
		# Ladder + pipe on +/-Z (clear of the +/-X base openings).
		for k in range(10):
			_box(root, Vector3(x, y + 1.0 + float(k) * 1.7, z + 3.7),
					Vector3(0.7, 0.08, 0.08), steel, 0, false)
		_cyl(root, Vector3(x, y + 8.0, z - 3.85), 0.22, 16.0, steel, false)


static func _boardwalk(root: Node3D, start: Vector2, length: float, yaw: float,
		factor: float) -> void:
	var wood := FT._pbr("wood", Color(0.35, 0.29, 0.20), 0.5)
	var basis := Basis(Vector3.UP, yaw)
	var n := int(length / 1.6)
	for i in range(n):
		var wp := Vector3(start.x, 0, start.y) + basis * Vector3(0, 0, float(i) * 1.6)
		var y := maxf(_h(wp.x, wp.z), FT.water_level(_map)) + 0.35
		_box(root, Vector3(wp.x, y, wp.z), Vector3(2.6, 0.14, 1.6), wood, yaw, true)
		if i % 3 == 0:
			for sx in [-1.1, 1.1]:
				_cyl(root, Vector3(wp.x + sx, y - 0.5, wp.z), 0.1, 1.5, wood, true)
	# Rail on one side.
	for i in range(n):
		var wp := Vector3(start.x, 0, start.y) + basis * Vector3(1.25, 0, float(i) * 1.6)
		var y := maxf(_h(wp.x, wp.z), FT.water_level(_map)) + 1.0
		_box(root, Vector3(wp.x, y, wp.z), Vector3(0.1, 1.2, 0.1), wood, yaw, true)
		if i > 0:
			_box(root, Vector3(wp.x - basis.z.x * 0.8, y + 0.55, wp.z - basis.z.z * 0.8),
					Vector3(0.08, 0.08, 1.7), wood, yaw, true)


static func _boat_wreck(root: Node3D, p: Vector2, yaw: float) -> void:
	var y := maxf(_h(p.x, p.y), FT.water_level(_map)) + 0.3
	var rust := FT._pbr("steel", Color(0.36, 0.25, 0.18), 0.42)
	var dark := FT._mat(Color(0.08, 0.08, 0.07), 0.95)
	var basis := Basis(Vector3.UP, yaw)
	# Hull: a wide flat box, a raised bow wedge and a cabin.
	_box(root, Vector3(p.x, y, p.y), Vector3(8.0, 0.8, 2.6), rust, yaw, true)
	_box(root, Vector3(p.x, y + 0.5, p.y), Vector3(4.8, 0.6, 2.0), dark, yaw, true)
	_box(root, Vector3(p.x + 3.4, y + 0.25, p.y), Vector3(1.6, 0.5, 2.0), rust,
			yaw + 0.2, true)
	_cyl(root, Vector3(p.x - 1.4, y + 1.4, p.y), 0.12, 1.8, dark, true)


static func _drowned_ruin(root: Node3D, p: Vector2, yaw: float) -> void:
	var y := maxf(_h(p.x, p.y), FT.water_level(_map)) - 0.4
	var concrete := FT._pbr("hall_concrete", Color(0.58, 0.60, 0.56), 0.34)
	var rust := FT._pbr("steel", Color(0.40, 0.25, 0.16), 0.4)
	_box(root, Vector3(p.x, y + 0.4, p.y), Vector3(9.0, 1.0, 7.0), concrete, yaw, true)
	for sx in [-1.0, 1.0]:
		_box(root, Vector3(p.x + sx * 4.2, y + 2.0, p.y), Vector3(0.5, 4.0, 7.0),
				concrete, yaw, true)
	_box(root, Vector3(p.x, y + 3.8, p.y), Vector3(9.4, 0.4, 7.4), concrete, yaw, true)
	for i in range(5):
		_box(root, Vector3(p.x - 3.0 + float(i) * 1.5, y + 4.2, p.y),
				Vector3(0.2, 0.4, 7.5), rust, yaw, false)


# ===========================================================================
#  Ground litter: chips, bricks, weeds and puddles around the whole map
# ===========================================================================
## Deterministic, quality-scaled POI scatter.  This is the "scale" pass: every
## map gets ruins, camps, wrecks, fields, tanks and checkpoints distributed by
## seeded sampling instead of a fixed list of hand-authored coordinates.
static func _scatter_procedural(root: Node3D, map_name: String, factor: float) -> void:
	for node in root.find_children("*", "Node3D", true, false):
		var n3 := node as Node3D
		if n3 == null or not n3.is_in_group("frontline_asset"):
			continue
		var ln := String(n3.name).to_lower()
		if not (ln.contains("hero") or ln.contains("checkpoint")
				or ln.contains("bunker") or ln.contains("observation")
				or ln.contains("hospital") or ln.contains("factory")
				or ln.contains("admin") or ln.contains("bridge")):
			continue
		var n_pos := FT._local_transform_to_root(n3, root).origin
		_used_sites.append(Vector2(n_pos.x, n_pos.z))
	var kinds: Array = []
	match map_name:
		"wetlands":
			kinds = ["camp", "wreck", "pond"]
		"promzona_plavni":
			kinds = ["camp", "wreck", "pond"]
		_:
			kinds = ["camp", "wreck", "tank"]
	var count := mini(2, maxi(1, int(round(4.0 * factor))))
	var scatter_half := 300.0 if map_name == "promzona_plavni" else 148.0
	var max_attempts := count * 50
	var placed := 0
	while placed < count and max_attempts > 0:
		max_attempts -= 1
		var p := Vector2(_rng.randf_range(-scatter_half, scatter_half),
				_rng.randf_range(-scatter_half, scatter_half))
		if not _free(p.x, p.y, 12.0):
			continue
		var kind: String = kinds[_rng.randi_range(0, kinds.size() - 1)]
		var clearance := 46.0
		if _too_close(p, clearance):
			continue
		# Keep fields and camps off the drivable road ribbons.
		var near_road := false
		for road in FT._road_points(map_name):
			var pts := road as PackedVector2Array
			for pt in pts:
				if pt.distance_to(p) < 22.0:
					near_road = true
					break
			if near_road:
				break
		if near_road:
			continue
		# Expensive authored assets only on High; lighter procedural kit is
		# used on UFDS / Medium / Low.
		var rich := factor >= 0.85
		match kind:
			"ruin":
				_ruin_site(root, p, _rng.randf_range(0.0, TAU),
						_rng.randf_range(12.0, 24.0), _rng.randf_range(7.0, 12.0),
						_rng.randf_range(3.4, 5.6),
						["brick", "concrete", "plaster"][_rng.randi_range(0, 2)])
			"camp":
				_procedural_camp(root, p, rich)
			"wreck":
				_procedural_wreck(root, p)
			"field":
				_crop_field(root, p, _rng.randf_range(70.0, 140.0),
						_rng.randf_range(50.0, 85.0), _rng.randf_range(-0.5, 0.5),
						["wheat", "stubble", "plowed"][_rng.randi_range(0, 2)], factor)
			"orchard":
				_crop_field(root, p, _rng.randf_range(45.0, 75.0),
						_rng.randf_range(35.0, 55.0), _rng.randf_range(-0.4, 0.4),
						"orchard", factor)
			"farm":
				if rich:
					var variant: String = ["cottage_a", "cottage_b", "barn_a"][
							_rng.randi_range(0, 2)]
					FT._spawn_cottage(root, variant, p, _h(p.x, p.y),
							_rng.randf_range(0.0, TAU), _rng.randi_range(0, 3))
					_queue_prop("prop_hay", p.x + 8.0, p.y + 4.0,
							_rng.randf_range(0.0, TAU), 1.1)
					_queue_prop("prop_fence", p.x - 6.0, p.y + 6.0,
							_rng.randf_range(0.0, TAU), 1.0)
					_rubble(root, p, 5.0, 30, "FarmRubble")
				else:
					_procedural_camp(root, p, false)
			"tank":
				_tank_cluster(root, p)
			"pond":
				_pond(root, p, _rng.randf_range(10.0, 18.0), factor)
			"checkpoint":
				if rich:
					_asset_on(root, p, "checkpoint", _rng.randf_range(0.9, 1.1))
					_asset_on(root, p + Vector2(4.0, 3.0), "sandbag_wall", 1.0)
				else:
					_procedural_camp(root, p, false)
		_used_sites.append(p)
		FT.reserve_area(p, 14.0)
		placed += 1


static func _too_close(p: Vector2, min_dist: float) -> bool:
	for s in _used_sites:
		if (s as Vector2).distance_to(p) < min_dist:
			return true
	return false


static func _procedural_camp(root: Node3D, p: Vector2, rich: bool) -> void:
	var names := ["prop_tent", "prop_camo_net", "prop_crate", "prop_barrel",
			"prop_ammo", "prop_generator", "prop_sandbags"]
	for i in range(_rng.randi_range(4, 8)):
		var q := p + Vector2(_rng.randf_range(-7.0, 7.0),
				_rng.randf_range(-7.0, 7.0))
		_queue_prop(names[_rng.randi_range(0, names.size() - 1)], q.x, q.y,
				_rng.randf_range(0.0, TAU), _rng.randf_range(0.9, 1.2))
	_rubble(root, p, 5.0, int(maxf(18.0, 34.0 * (1.0 if rich else 0.6))),
			"CampRubble")
	_weeds(root, p, 8.0, 80, Color(0.08, 0.11, 0.04), Color(0.24, 0.25, 0.10))
	if rich:
		_asset_on(root, p + Vector2(8.0, -5.0), "observation_post", 1.0)


static func _procedural_wreck(root: Node3D, p: Vector2) -> void:
	var wreck := "prop_car_wreck" if _rng.randf() < 0.65 else "prop_apc"
	_queue_prop(wreck, p.x, p.y, _rng.randf_range(0.0, TAU),
			_rng.randf_range(0.95, 1.15))
	_rubble(root, p, 6.0, 48, "WreckRubble", true)
	_weeds(root, p, 7.0, 110, Color(0.07, 0.10, 0.035),
			Color(0.22, 0.23, 0.09))
	if _rng.randf() < 0.5:
		_add_burning_hulk(root, p + Vector2(2.0, 3.0))


static func _add_burning_hulk(root: Node3D, p: Vector2) -> void:
	# Small orange glow and smoke at a wreck; no complex physics.
	_burning_barrel(root, p)


static func _dress_ground_litter(root: Node3D, map_name: String, factor: float) -> void:
	# Small clusters at the places the pilot actually flies past: hall aprons,
	# farmsteads, road junctions and the ruin sites.  The existing debris pass
	# was uniform and random; these clusters read as "something happened here".
	var centers: Array = []
	var site: Dictionary = FT.HALL_SITES.get(map_name, {})
	if not site.is_empty():
		var c: Vector2 = site["center"]
		var half: Vector2 = site["half"]
		centers.append(c + Vector2(half.x + 14.0, 0.0))
		centers.append(c + Vector2(-half.x - 14.0, 0.0))
	match map_name:
		"steppe":
			centers.append_array([Vector2(36, 128), Vector2(66, 70), Vector2(-132, 40),
					Vector2(142, -40), Vector2(-48, 126), Vector2(-128, 68)])
		"village":
			centers.append_array([Vector2(90, 70), Vector2(30, 46), Vector2(130, 96),
					Vector2(-140, 84), Vector2(-108, 138), Vector2(12, 16)])
		"industrial":
			centers.append_array([Vector2(138, 86), Vector2(92, 30), Vector2(-115, -36),
					Vector2(24, 140), Vector2(116, -30), Vector2(-140, -28)])
		"wetlands":
			centers.append_array([Vector2(30, 60), Vector2(52, 106), Vector2(-82, 30),
					Vector2(138, 126), Vector2(-142, 20)])
		"promzona_plavni":
			centers.append_array([Vector2(-150, -180), Vector2(120, -110),
					Vector2(-40, -260), Vector2(100, 210), Vector2(-90, 180),
					Vector2(160, 260)])
	var litter_half := 300.0 if map_name == "promzona_plavni" else 148.0
	for i in range(int(maxf(2.0, 6.0 * factor))):
		centers.append(Vector2(_rng.randf_range(-litter_half, litter_half),
				_rng.randf_range(-litter_half, litter_half)))
	var litter := int(clampf(round(14.0 * factor), 3.0, 6.0))
	for c in centers:
		var cp: Vector2 = c
		if not _free(cp.x, cp.y, 0.0):
			continue
		_rubble(root, cp, 7.0, litter, "Litter")
		if _rng.randf() < 0.5:
			_weeds(root, cp, 6.0, int(maxf(20.0, 55.0 * factor)),
					Color(0.09, 0.12, 0.045), Color(0.28, 0.28, 0.11))
		if map_name == "wetlands" and _rng.randf() < 0.3:
			_puddle(root, cp + Vector2(_rng.randf_range(-3, 3), _rng.randf_range(-3, 3)),
					_rng.randf_range(0.5, 1.6))
