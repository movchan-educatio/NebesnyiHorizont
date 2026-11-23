class_name FrontlineAssets
extends RefCounted

## Loads and places the Blender-authored frontline props.
##
## The GLB files are exported with `*-colonly` / `*-convcolonly` collision
## meshes, so the Godot glTF importer creates StaticBody3D nodes automatically.
## Some Godot builds still expose the collision mesh as a MeshInstance3D; the
## helper hides those nodes and keeps their collision bodies active.

const ROOT := "res://Assets/frontline/"

## Distance culling per asset.  Big landmarks stay visible to the horizon,
## while small props drop out once they are a few pixels wide.
const LOD_END := {
	"hospital": 1800.0,
	"admin_building": 1500.0,
	"factory_hall": 1700.0,
	"arch": 1000.0,
	"concrete_bridge": 1300.0,
	"wooden_bridge": 1100.0,
	"destroyed_bridge": 1100.0,
	"bunker": 750.0,
	"observation_post": 950.0,
	"checkpoint": 800.0,
	"hedgehog": 240.0,
	"pylon": 1500.0,
	"sandbag_wall": 300.0,
	"vegetation/oak_hero": 750.0,
	"vegetation/pine_hero": 850.0,
	"rocks": 650.0,
}

static var _cache: Dictionary = {}


static func preload_all() -> void:
	for asset_name in LOD_END.keys():
		_load(asset_name)


## Spawn one prop from the shared props_library.glb (hay, barrels, crates,
## fence, logs, tires...).  The library is one scene, so duplicate the named
## child and discard the rest; this keeps the asset as a single GLB.
static var _props_library: PackedScene = null

static func spawn_prop(parent: Node3D, prop_name: String, pos: Vector3,
		yaw: float = 0.0, scale_factor: float = 1.0) -> Node3D:
	if parent == null:
		return null
	if _props_library == null:
		var path := ROOT + "props/props_library.glb"
		if not ResourceLoader.exists(path):
			return null
		_props_library = load(path) as PackedScene
	if _props_library == null:
		return null
	var library := _props_library.instantiate()
	var source := library.find_child(prop_name, true, false)
	if source == null:
		library.queue_free()
		return null
	var inst := source.duplicate() as Node3D
	if inst == null:
		library.queue_free()
		return null
	parent.add_child(inst)
	inst.position = pos
	inst.rotation.y = yaw
	if absf(scale_factor) > 0.01 and not is_equal_approx(scale_factor, 1.0):
		inst.scale = Vector3.ONE * scale_factor
	elif absf(scale_factor) <= 0.01:
		inst.scale = Vector3.ONE
	inst.add_to_group("frontline_asset")
	# Treat the supplied Y as the support plane and settle the prop onto it.
	# The library meshes have mixed pivots (some centre, some base), which is
	# why bales/barrels used to hover 0.3-0.6 m over the dirt.
	var support_y := inst.global_position.y
	var bounds := visual_aabb(inst)
	if bounds.size.y > 0.02:
		inst.global_position.y += (support_y - 0.06) - bounds.position.y
	# Hollow/concave props must never get a single convex hull: that plugs pipe
	# bores and inflates fences, wrecks, antennas and tyres into huge invisible
	# walls.  Use exact trimeshes for those; only genuinely solid blocks keep a
	# tight convex shape.  Walk *all* meshes, since the duplicated source is
	# often a plain Node3D with the geometry on children.
	var lower_name := prop_name.to_lower()
	var need_trimesh := false
	for token in ["pipe", "fence", "barrier", "wreck", "antenna", "tires",
			"arch", "ring", "gate", "frame", "tent", "camo"]:
		if lower_name.contains(token):
			need_trimesh = true
			break
	var need_convex := false
	for token in ["crate", "pallet", "barrel", "sandbag", "fuel_tank"]:
		if lower_name.contains(token):
			need_convex = true
			break
	# Any other prop (generator, ammo, logs, signs, oil drums, ...) is at least
	# partly concave, so it also gets exact trimesh collision rather than a
	# hull that would inflate its silhouette.
	need_trimesh = need_trimesh or not need_convex
	var meshes: Array[MeshInstance3D] = []
	var root_mi := inst as MeshInstance3D
	if root_mi != null and root_mi.mesh != null:
		meshes.append(root_mi)
	for child in inst.find_children("*", "MeshInstance3D", true, false):
		var child_mi := child as MeshInstance3D
		if child_mi != null and child_mi.mesh != null:
			meshes.append(child_mi)
	for mesh_mi in meshes:
		_texture_prop(mesh_mi, prop_name)
		var shape: Shape3D = null
		if need_trimesh:
			var tri := mesh_mi.mesh.create_trimesh_shape()
			if tri != null:
				tri.backface_collision = true
				shape = tri
		elif need_convex:
			shape = mesh_mi.mesh.create_convex_shape(true, false)
		if shape == null:
			continue
		var body := StaticBody3D.new()
		body.name = prop_name + ("_trimesh_col" if need_trimesh else "_col")
		body.collision_layer = 1
		body.collision_mask = 1
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		# Attach under the mesh so its local transform is inherited exactly.
		mesh_mi.add_child(body)
	library.queue_free()
	return inst


## World-space AABB of every visible mesh under a node.  Used by the prop
## placement pass to put the lowest vertex on the support plane instead of
## trusting the GLB pivot.
static func visual_aabb(root: Node) -> AABB:
	var box := AABB()
	var has_box := false
	var meshes: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		meshes.append(root as MeshInstance3D)
	meshes.append_array(root.find_children("*", "MeshInstance3D", true, false))
	for node in meshes:
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.visible:
			continue
		var world := mi.global_transform * mi.get_aabb()
		if not has_box:
			box = world
			has_box = true
		else:
			box = box.merge(world)
	return box if has_box else AABB()


static func _snap_upright_asset(inst: Node3D, asset_name: String) -> void:
	# Upright battlefield props must sit *in* the terrain, never hover on a
	# slope.  Bridges are anchored to the water line and large buildings use
	# their own footprint/foundation pass, so only this set is adjusted.
	var sink := -1.0
	match asset_name:
		"pylon":
			sink = 0.35
		"hedgehog":
			sink = 0.20
		"sandbag_wall":
			sink = 0.24
		"bunker":
			sink = 0.35
		"observation_post":
			sink = 0.28
		"checkpoint":
			sink = 0.28
		"arch":
			sink = 0.25
		"rocks":
			sink = 0.30
		_:
			return
	var bounds := visual_aabb(inst)
	if bounds.size.y < 0.02:
		return
	var support_y := inst.global_position.y
	inst.global_position.y += (support_y - sink) - bounds.position.y


static func _load(asset_name: String) -> PackedScene:
	if _cache.has(asset_name):
		return _cache[asset_name] as PackedScene
	var path := ROOT + asset_name + ".glb"
	if not ResourceLoader.exists(path):
		push_warning("[FrontlineAssets] missing " + path)
		_cache[asset_name] = null
		return null
	var packed := load(path) as PackedScene
	_cache[asset_name] = packed
	return packed


static func spawn(parent: Node3D, asset_name: String, pos: Vector3,
		yaw: float = 0.0, scale_factor: float = 1.0) -> Node3D:
	if parent == null:
		return null
	var packed := _load(asset_name)
	if packed == null:
		return null
	var inst := packed.instantiate() as Node3D
	if inst == null:
		return null
	inst.name = asset_name.get_file()
	inst.add_to_group("frontline_asset")
	parent.add_child(inst)
	inst.position = pos
	inst.rotation.y = yaw
	if absf(scale_factor) > 0.01 and not is_equal_approx(scale_factor, 1.0):
		inst.scale = Vector3.ONE * scale_factor
	elif absf(scale_factor) <= 0.01:
		inst.scale = Vector3.ONE
	_prepare(inst, asset_name)
	_snap_upright_asset(inst, asset_name)
	return inst


## Spawn with the origin snapped to the procedural terrain surface.
static func spawn_on_terrain(parent: Node3D, map_name: String, asset_name: String,
		x: float, z: float, yaw: float = 0.0, scale_factor: float = 1.0,
		sink: float = 0.0) -> Node3D:
	var terrain = load("res://scripts/util/frontline_terrain.gd")
	if terrain == null:
		return null
	var y: float = terrain.height_at(map_name, x, z) - sink
	return spawn(parent, asset_name, Vector3(x, y, z), yaw, scale_factor)


static func _prepare(inst: Node3D, asset_name: String) -> void:
	var lod: float = float(LOD_END.get(asset_name, 1200.0))
	_hide_collision_meshes(inst)
	for node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.visible:
			mi.visibility_range_end = lod
			mi.visibility_range_end_margin = minf(80.0, lod * 0.12)
	for node in inst.find_children("*", "StaticBody3D", true, false):
		var body := node as StaticBody3D
		body.collision_layer = 1
		body.collision_mask = 1
	if asset_name == "arch":
		_fix_arch(inst)
	# Blender-authored vegetation carries a baked wind animation (two shape
	# keys driven out of phase) - loop it from the first frame.
	var ap := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap != null and ap.get_animation_list().size() > 0:
		if OS.has_environment("VEG_DEBUG"):
			print("[FrontlineAssets] animation ", asset_name, " -> ",
					ap.get_animation_list())
		ap.play(ap.get_animation_list()[0])


static func _hide_collision_meshes(node: Node) -> void:
	var node_name := String(node.name)
	if node is MeshInstance3D and (node_name.contains("-col") or node_name.contains("-convcol")):
		var mi := node as MeshInstance3D
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_hide_collision_meshes(child)


static var _prop_mat_cache := {}
static var _hazard_prop_tex: ImageTexture = null

static func _get_hazard_texture() -> Texture2D:
	if _hazard_prop_tex != null:
		return _hazard_prop_tex
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var col_yellow := Color(0.94, 0.76, 0.08)
	var col_black := Color(0.12, 0.12, 0.14)
	for y in range(128):
		for x in range(128):
			var stripe := int(x + y) / 16 % 2
			img.set_pixel(x, y, col_yellow if stripe == 0 else col_black)
	img.generate_mipmaps()
	_hazard_prop_tex = ImageTexture.create_from_image(img)
	return _hazard_prop_tex


static func _resolve_tex_path(base_no_ext: String) -> String:
	for ext in [".png", ".jpg"]:
		var p: String = base_no_ext + str(ext)
		if ResourceLoader.exists(p):
			return p
	return ""


static func _get_prop_mat(kind: String, tint: Color, rough: float = 0.7, metal: float = 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f|%.2f|%.2f|%.2f" % [kind, tint.r, tint.g, tint.b, rough, metal]
	if _prop_mat_cache.has(key):
		return _prop_mat_cache[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	m.metallic = metal
	m.metallic_specular = 0.28
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_triplanar_sharpness = 8.0
	m.uv1_scale = Vector3.ONE * 0.32

	var alb_path := _resolve_tex_path("res://Assets/frontline/textures/%s_albedo" % kind)
	var nrm_path := _resolve_tex_path("res://Assets/frontline/textures/%s_normal" % kind)
	var rgh_path := _resolve_tex_path("res://Assets/frontline/textures/%s_rough" % kind)
	var ao_path := _resolve_tex_path("res://Assets/frontline/textures/%s_ao" % kind)
	if kind == "concrete":
		alb_path = _resolve_tex_path("res://Assets/frontline/industrial_hall/concrete_slab_wall_diff")
		nrm_path = _resolve_tex_path("res://Assets/frontline/industrial_hall/concrete_slab_wall_nor_gl")
		rgh_path = _resolve_tex_path("res://Assets/frontline/industrial_hall/concrete_slab_wall_rough")
		ao_path = _resolve_tex_path("res://Assets/frontline/industrial_hall/concrete_slab_wall_ao")
	elif kind == "steel":
		alb_path = _resolve_tex_path("res://Assets/frontline/industrial_hall/metal_plate_02_diff")
		nrm_path = _resolve_tex_path("res://Assets/frontline/industrial_hall/metal_plate_02_nor_gl")
		rgh_path = _resolve_tex_path("res://Assets/frontline/industrial_hall/metal_plate_02_rough")
		ao_path = _resolve_tex_path("res://Assets/frontline/industrial_hall/metal_plate_02_ao")
	elif kind == "rust":
		alb_path = _resolve_tex_path("res://Assets/frontline/industrial_hall/rusty_metal_02_diff")
		nrm_path = _resolve_tex_path("res://Assets/frontline/industrial_hall/rusty_metal_02_nor_gl")
		rgh_path = _resolve_tex_path("res://Assets/frontline/industrial_hall/rusty_metal_02_rough")
		ao_path = _resolve_tex_path("res://Assets/frontline/industrial_hall/rusty_metal_02_ao")

	if alb_path != "":
		m.albedo_texture = load(alb_path) as Texture2D
	if nrm_path != "":
		m.normal_enabled = true
		m.normal_texture = load(nrm_path) as Texture2D
		m.normal_scale = 1.15
	if rgh_path != "":
		m.roughness_texture = load(rgh_path) as Texture2D
	if ao_path != "":
		var ao_tex := load(ao_path) as Texture2D
		if ao_tex != null:
			m.ao_enabled = true
			m.ao_texture = ao_tex
			m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	_prop_mat_cache[key] = m
	return m


## Fixes arch.glb by clearing out 32 blocking faces across the arch tunnel
## and replacing placeholder white surfaces with realistic textured PBR materials.
static func _fix_arch(inst: Node3D) -> void:
	# 1. Clean collision opening
	for cs in inst.find_children("*", "CollisionShape3D", true, false):
		var shape := cs.shape as ConcavePolygonShape3D
		if shape != null:
			var faces := shape.get_faces()
			var new_faces := PackedVector3Array()
			for i in range(0, faces.size(), 3):
				var p1 := faces[i]
				var p2 := faces[i + 1]
				var p3 := faces[i + 2]
				var mid := (p1 + p2 + p3) / 3.0
				# Arch tunnel opening: x in [-2.4, 2.4], y in [0.6, 8.5]
				if absf(mid.x) < 2.4 and mid.y > 0.6 and mid.y < 8.5:
					continue # Drop blocking interior face
				new_faces.append(p1)
				new_faces.append(p2)
				new_faces.append(p3)
			var clean_shape := ConcavePolygonShape3D.new()
			clean_shape.set_faces(new_faces)
			clean_shape.backface_collision = false
			cs.shape = clean_shape

	# 2. Fix materials: replace white/untextured surfaces with weathered military PBR
	var arch_concrete := _get_prop_mat("concrete", Color(0.78, 0.76, 0.72), 0.88, 0.0)
	var arch_dark_trim := _get_prop_mat("concrete", Color(0.32, 0.31, 0.29), 0.90, 0.0)
	var sign_camo_metal := _get_prop_mat("steel", Color(0.28, 0.35, 0.24), 0.55, 0.50)

	var hazard_mat := StandardMaterial3D.new()
	hazard_mat.albedo_texture = _get_hazard_texture()
	hazard_mat.uv1_triplanar = true
	hazard_mat.uv1_triplanar_sharpness = 8.0
	hazard_mat.uv1_scale = Vector3.ONE * 0.45
	hazard_mat.roughness = 0.50
	hazard_mat.metallic = 0.30

	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m != null and m.mesh != null:
			for s in range(m.mesh.get_surface_count()):
				if s == 0:
					m.set_surface_override_material(0, arch_concrete)
				elif s == 1:
					m.set_surface_override_material(1, arch_dark_trim)
				elif s == 2:
					m.set_surface_override_material(2, sign_camo_metal)
				elif s == 3:
					m.set_surface_override_material(3, hazard_mat)


static func _texture_prop(mi: MeshInstance3D, prop_name: String) -> void:
	if mi == null or mi.mesh == null:
		return
	# All 20 sculpted props in props_library.glb carry baked multi-part vertex colors + AO.
	# Use balanced PBR surface multipliers so vertex colors + triplanar normal/roughness shine through.
	var mat: StandardMaterial3D = null
	match prop_name:
		"prop_ammo":
			mat = _get_prop_mat("steel", Color(1.12, 1.14, 1.08), 0.65, 0.35)
		"prop_antenna":
			mat = _get_prop_mat("steel", Color(1.15, 1.16, 1.18), 0.48, 0.55)
		"prop_apc":
			mat = _get_prop_mat("steel", Color(1.10, 1.12, 1.06), 0.72, 0.22)
		"prop_barrel", "prop_oil_drum":
			mat = _get_prop_mat("steel", Color(1.14, 1.14, 1.16), 0.55, 0.45)
		"prop_barrier":
			mat = _get_prop_mat("concrete", Color(1.12, 1.10, 1.06), 0.88, 0.0)
		"prop_camo_net", "prop_tent":
			mat = _get_prop_mat("camo", Color(1.08, 1.10, 1.04), 0.86, 0.0)
		"prop_car_wreck":
			mat = _get_prop_mat("rust", Color(1.12, 1.08, 1.04), 0.84, 0.18)
		"prop_crate", "prop_pallet":
			mat = _get_prop_mat("wood", Color(1.10, 1.06, 1.00), 0.82, 0.0)
		"prop_fence", "prop_logs":
			mat = _get_prop_mat("wood", Color(1.08, 1.04, 0.98), 0.86, 0.0)
		"prop_fuel_tank":
			mat = _get_prop_mat("steel", Color(1.14, 1.15, 1.16), 0.52, 0.48)
		"prop_generator":
			mat = _get_prop_mat("steel", Color(1.12, 1.14, 1.10), 0.56, 0.42)
		"prop_hay":
			mat = _get_prop_mat("wood", Color(1.16, 1.12, 0.98), 0.92, 0.0)
		"prop_pipe":
			mat = _get_prop_mat("rust", Color(1.12, 1.10, 1.08), 0.58, 0.48)
		"prop_sandbags":
			mat = _get_prop_mat("sandbag", Color(1.10, 1.08, 1.02), 0.88, 0.0)
		"prop_sign":
			mat = _get_prop_mat("steel", Color(1.18, 1.16, 1.10), 0.52, 0.35)
		"prop_tires":
			mat = _get_prop_mat("asphalt", Color(0.92, 0.92, 0.94), 0.90, 0.0)
		_:
			mat = _get_prop_mat("concrete", Color(1.08, 1.06, 1.04), 0.85, 0.0)

	for s in range(mi.mesh.get_surface_count()):
		mi.set_surface_override_material(s, mat)

