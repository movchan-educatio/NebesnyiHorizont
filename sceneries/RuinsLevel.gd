extends "res://sceneries/BigLevel.gd"
## Руїни (ruins) — урбанізована промислова локація (фрістайл крізь отвори/вікна/тунелі +
## усі 4 бойові місії, 13 спецоперацій, бойове тренування й туторіал).

const MAP_SCENE := "res://maps/ruins/FPV_Ruins_Map.glb"
const RUINS_HDRI_PATH := "res://maps/ruins/industrial_sunset_puresky.hdr"
const RuinsRingsScript = preload("res://maps/ruins/scripts/ruins_freestyle_rings.gd")
const DEFAULT_SPAWN := Vector3(25.0, 0.14, 72.0)

const RUINS_TEX_SLUGS := {
	"brick": "red_bricks_04",
	"concrete": "concrete_slab_wall_02",
	"concrete2": "concrete_block_wall_02",
	"floor": "damaged_concrete_floor",
	"asphalt": "asphalt_02",
	"road": "asphalt_02",
	"pavement": "brick_pavement_02",
	"rust": "rust_coarse_01",
	"rust2": "rust_coarse_01",
	"roof": "rusty_corrugated_iron",
	"grate": "metal_grate_rusty",
	"container": "container_side",
	"dirt": "brown_mud_02",
	"gravel": "gravel_floor_02",
	"grass": "grass_ground",
	"debris": "concrete_debris",
	"wood": "wood_planks_dirt",
}

const BARREL_FIRES_GODOT := [
	Vector3(-63.5, 2.2, 35.5),
	Vector3(8.0, 2.2, 6.5),
	Vector3(118.0, 2.2, -30.0),
	Vector3(-198.0, 2.2, 158.0),
]

## 2D AABBs (x0, z0, x1, z1) of buildings & dense obstacle blocks in Godot coords
## so ground units and spawns never appear inside walls, buildings, or on rooftops.
const BUILDING_EXCLUSIONS := [
	# Factory halls & warehouses
	[-140.0, 21.0, -70.0, 59.0],    # Hall #1
	[-158.0, -82.0, -102.0, -42.0], # Hall #2 (rotated 15 deg envelope)
	[-73.0, -21.0, -37.0, 5.0],     # Hall #3
	[-184.0, -4.0, -146.0, 24.0],   # Warehouse #4
	[159.0, 31.0, 201.0, 59.0],     # Warehouse #5
	[-46.0, -130.0, -18.0, -106.0], # Warehouse #6
	[104.0, 81.0, 132.0, 103.0],    # Warehouse #7
	# Apartments
	[44.0, 36.0, 116.0, 54.0],      # Apt #1
	[113.0, -82.0, 177.0, -48.0],   # Apt #2
	[31.0, -114.0, 89.0, -86.0],    # Apt #3
	# Ruin shells
	[-110.0, 76.0, -74.0, 100.0],   # Ruin52
	[120.0, 46.0, 150.0, 64.0],     # Ruin51
	[94.0, -24.0, 130.0, 0.0],      # Ruin54
	[-166.0, -40.0, -134.0, -16.0], # Ruin55
	[162.0, -106.0, 194.0, -78.0],  # Ruin56
	[-58.0, -155.0, -32.0, -135.0], # Ruin57
	# Industrial & freestyle structures
	[-238.0, 152.0, -192.0, 198.0], # Cooling tower
	[168.0, -156.0, 222.0, -114.0], # Pipe tunnel
	[-232.0, -165.0, -178.0, -135.0], # Container bridge
	[35.0, 85.0, 62.0, 99.0],       # Scaffold
	[-245.0, 36.0, -216.0, 60.0],   # Horizontal tanks
	[-204.0, -83.0, -166.0, -67.0], # Silos
	[-78.0, 182.0, -42.0, 198.0],   # Vertical tanks
	[-38.0, -56.0, -22.0, -40.0],   # Chimney 1
	[-76.0, -56.0, -64.0, -44.0],   # Chimney 2
	[8.0, -87.0, 22.0, -73.0],      # Water tower
	[-54.0, 70.0, -16.0, 86.0],     # Gantry crane
	[-22.0, 195.0, 62.0, 215.0],    # Slab slalom
	[208.0, 18.0, 222.0, 122.0],    # Pipe rack
	[138.0, 144.0, 162.0, 158.0],   # Billboard
	[-82.0, -8.0, -64.0, 42.0],     # Conveyor
]

static var _ruins_sky_mat: PanoramaSkyMaterial = null
static var _ruins_tex_cache: Dictionary = {}

var _map_instance: Node3D = null
var _sky_fill_light: DirectionalLight3D = null
var _fire_lights: Array[OmniLight3D] = []
var _guard_probe_ms := 0
var _guard_probe_xz := Vector2(1.0e20, 1.0e20)
var _guard_probe_y := 0.0


func _map_path() -> String:
	return MAP_SCENE


func _apply_map_materials(_node: Node) -> void:
	pass


func _scatter_legacy_map(_instance: Node3D) -> void:
	pass


func _ready() -> void:
	MAP_GROUND_SAFE = 240.0
	MAP_FLIGHT_BOUND = 278.0
	MAP_AIR_SAFE = 262.0
	_ground_y = 0.0
	set_meta("disable_procedural_grass", true)
	skip_material_upgrade = true
	super._ready()


func _load_map() -> void:
	super._load_map()
	var fallback_ground := get_node_or_null("Ground/MeshInstance3D") as MeshInstance3D
	if fallback_ground != null:
		fallback_ground.visible = false
	var root := get_node_or_null("MapRoot")
	if root != null and root.get_child_count() > 0:
		for c in root.get_children():
			if c is Node3D:
				_map_instance = c as Node3D
				break
	if _map_instance != null:
		_setup_ruins_collisions(_map_instance)
		_setup_ruins_animations(_map_instance)
		_apply_ruins_materials(_map_instance)
		_setup_ruins_atmosphere_fx(_map_instance)


func _setup_fpv_camera_for_preset() -> void:
	super._setup_fpv_camera_for_preset()
	var cam := get_node_or_null("Drone/FPVCamera") as Camera3D
	if cam != null:
		# Tight near/far ratio boosts 24-bit depth buffer precision across ruins & roads
		# without clipping horizon ridges, eliminating distant coplanar flicker.
		cam.near = maxf(cam.near, 0.05)
		cam.far = 2600.0


func _setup_ruins_collisions(map_root: Node3D) -> void:
	# 1. Harden COLLISION-colonly (ensure layer/mask 1 and solid two-sided triangles)
	for sb in map_root.find_children("*", "StaticBody3D", true, false):
		var body := sb as StaticBody3D
		body.collision_layer = 1
		body.collision_mask = 1
		for ch in body.get_children():
			if ch is CollisionShape3D:
				var cs := ch as CollisionShape3D
				if cs.shape is ConcavePolygonShape3D:
					(cs.shape as ConcavePolygonShape3D).backface_collision = false

	# 2. Build exact hollow-preserving ConcavePolygonShape3D for hero structures
	# that had collide=False in Blender (cooling tower, pipe tunnel, billboard, hall roofs)
	var extra_tris := PackedVector3Array()
	var skip_mats := {"smoke": true, "fire": true, "water": true, "puddle": true,
		"dirt": true, "grass": true, "asphalt": true, "road": true,
		"pavement": true, "gravel": true, "wild_rooibos_bush": true,
		"fern_02": true, "grass_medium_01": true, "quiver_tree_01_leaf": true,
		"wild_rooibos_bush_twigs": true, "wild_rooibos_bush_leaves": true,
		"street_lamp_01_glass": true, "street_lamp_01_bulb": true,
		"loco_black": true, "loco_red": true, "brass": true, "glass": true, "lamp": true}
	for node in map_root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var mname := String(mi.name)
		if mname.begins_with("Train_") or mname.begins_with("EFFECTS_") or mname == "P_overhead_crane":
			continue
		var xf := mi.global_transform
		for s in range(mi.mesh.get_surface_count()):
			var mat := mi.get_active_material(s)
			var mat_name := String(mat.resource_name).to_lower() if mat != null else ""
			if skip_mats.has(mat_name):
				continue
			var arrays := mi.mesh.surface_get_arrays(s)
			if arrays.is_empty():
				continue
			var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
			if verts.is_empty():
				continue
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var tri_verts: int = indices.size() if not indices.is_empty() else verts.size()
			var i := 0
			while i + 2 < tri_verts:
				var v0 := xf * verts[indices[i] if not indices.is_empty() else i]
				var v1 := xf * verts[indices[i + 1] if not indices.is_empty() else (i + 1)]
				var v2 := xf * verts[indices[i + 2] if not indices.is_empty() else (i + 2)]
				var c := (v0 + v1 + v2) * (1.0 / 3.0)
				if absf(c.x) <= 290.0 and absf(c.z) <= 290.0 and c.y >= 0.25:
					extra_tris.append(v0)
					extra_tris.append(v1)
					extra_tris.append(v2)
				i += 3

	var struct_body := map_root.get_node_or_null("RuinsStructuralCollision") as StaticBody3D
	if struct_body == null and not extra_tris.is_empty():
		struct_body = StaticBody3D.new()
		struct_body.name = "RuinsStructuralCollision"
		struct_body.collision_layer = 1
		struct_body.collision_mask = 1
		var cs := CollisionShape3D.new()
		cs.name = "ConcaveHull"
		var cshape := ConcavePolygonShape3D.new()
		cshape.backface_collision = true
		cshape.set_faces(extra_tris)
		cs.shape = cshape
		struct_body.add_child(cs)
		# Analytical shapes for solid cylindrical tanks/silos & upper pipe rack / gantry truss
		_add_cyl_col(struct_body, "SiloW", Vector3(-194.0, 8.75, -75.0), 4.25, 17.5)
		_add_cyl_col(struct_body, "SiloC", Vector3(-185.0, 8.75, -75.0), 4.25, 17.5)
		_add_cyl_col(struct_body, "SiloE", Vector3(-176.0, 8.75, -75.0), 4.25, 17.5)
		_add_cyl_col(struct_body, "WaterTowerTank", Vector3(15.0, 20.0, -80.0), 5.25, 8.5)
		for hx in [-238.0, -230.0, -222.0]:
			_add_cyl_col(struct_body, "HorizTank_%d" % int(abs(hx)), Vector3(hx, 3.4, 48.0),
					2.5, 18.0, Vector3(PI * 0.5, 0.0, 0.0))
		_add_box_col(struct_body, "PipeRackOverhead", Vector3(215.0, 8.1, 70.0), Vector3(5.2, 1.8, 100.0))
		_add_box_col(struct_body, "GantryTopTruss", Vector3(-35.0, 17.1, 78.0), Vector3(30.4, 2.5, 9.6))
		map_root.add_child(struct_body)

	# 3. Dynamic colliders on the animated steam locomotive and overhead crane
	var loco := map_root.find_child("Train_SteamLoco", true, false) as Node3D
	if loco != null and loco.get_node_or_null("TrainCollider") == null:
		var tbody := AnimatableBody3D.new()
		tbody.name = "TrainCollider"
		tbody.sync_to_physics = false
		tbody.collision_layer = 1
		tbody.collision_mask = 1
		_add_box_col(tbody, "Boiler", Vector3(1.2, 2.55, 0.0), Vector3(8.2, 2.5, 2.3))
		_add_box_col(tbody, "Cab", Vector3(-3.78, 2.65, 0.0), Vector3(2.8, 2.8, 3.1))
		_add_box_col(tbody, "Tender", Vector3(-9.25, 2.1, 0.0), Vector3(6.7, 2.4, 2.8))
		loco.add_child(tbody)

	var crane := map_root.find_child("P_overhead_crane", true, false) as Node3D
	if crane != null and crane.get_node_or_null("CraneCollider") == null:
		var cbody := AnimatableBody3D.new()
		cbody.name = "CraneCollider"
		cbody.sync_to_physics = false
		cbody.collision_layer = 1
		cbody.collision_mask = 1
		_add_box_col(cbody, "BridgeGirder", Vector3(0.0, 0.4, 0.0), Vector3(28.0, 1.4, 2.8))
		crane.add_child(cbody)

	print("[RuinsLevel] structural collision ready: %d mesh tris + tanks/silos/train/crane" % (extra_tris.size() / 3))


static func _is_missing_structural_tri(c: Vector3, mat_name: String) -> bool:
	# Cooling Tower hyperboloid shell & catwalk (open arches + hollow funnel preserved!)
	if c.x >= -238.0 and c.x <= -192.0 and c.z >= 152.0 and c.z <= 198.0 and c.y >= 0.35 and c.y <= 45.5:
		return mat_name == "concrete" or mat_name == "grate"
	# 54 m Corrugated Pipe Tunnel (open bore + skylight preserved!)
	if c.x >= 166.0 and c.x <= 224.0 and c.z >= -156.0 and c.z <= -114.0 and c.y >= 0.5 and c.y <= 13.0:
		return mat_name == "rust2" or mat_name == "rust"
	# Torn Billboard panel & steel frame (all 3 holes preserved!)
	if c.x >= 138.0 and c.x <= 162.0 and c.z >= 142.0 and c.z <= 159.0 and c.y >= 6.4 and c.y <= 16.5:
		return mat_name == "roof" or mat_name == "metal"
	# Hall #1 roofs & gables (y >= 13.0 leaves gates & windows completely open!)
	if c.x >= -140.0 and c.x <= -70.0 and c.z >= 21.0 and c.z <= 59.0 and c.y >= 12.9:
		return mat_name == "roof" or mat_name == "brick"
	# Hall #2 roofs & gables
	if c.x >= -158.0 and c.x <= -102.0 and c.z >= -82.0 and c.z <= -42.0 and c.y >= 10.9:
		return mat_name == "roof" or mat_name == "brick"
	# Hall #3 roofs & gables
	if c.x >= -73.0 and c.x <= -37.0 and c.z >= -21.0 and c.z <= 5.0 and c.y >= 11.9:
		return mat_name == "roof" or mat_name == "brick"
	# Warehouses roofs (Warehouses 4, 5, 6, 7)
	if ((c.x >= -184.0 and c.x <= -146.0 and c.z >= -4.0 and c.z <= 24.0 and c.y >= 6.8)
			or (c.x >= 159.0 and c.x <= 201.0 and c.z >= 31.0 and c.z <= 59.0 and c.y >= 8.8)
			or (c.x >= -46.0 and c.x <= -18.0 and c.z >= -130.0 and c.z <= -106.0 and c.y >= 5.3)
			or (c.x >= 104.0 and c.x <= 132.0 and c.z >= 81.0 and c.z <= 103.0 and c.y >= 4.8)):
		return mat_name == "concrete"
	return false


static func _add_cyl_col(parent: Node3D, col_name: String, pos: Vector3,
		r: float, h: float, rot_euler: Vector3 = Vector3.ZERO) -> void:
	var cs := CollisionShape3D.new()
	cs.name = col_name
	var cyl := CylinderShape3D.new()
	cyl.radius = r
	cyl.height = h
	cs.shape = cyl
	cs.position = pos
	cs.rotation = rot_euler
	parent.add_child(cs)


static func _add_box_col(parent: Node3D, col_name: String, pos: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	cs.name = col_name
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = pos
	parent.add_child(cs)


func _setup_ruins_animations(map_root: Node3D) -> void:
	var ap := map_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap == null:
		return
	var anim_train: Animation = null
	var anim_crane: Animation = null
	if ap.has_animation("TrainShuttle"):
		anim_train = ap.get_animation("TrainShuttle").duplicate() as Animation
		anim_train.loop_mode = Animation.LOOP_LINEAR
		for ti in range(anim_train.get_track_count() - 1, -1, -1):
			if not String(anim_train.track_get_path(ti)).contains("Train_SteamLoco"):
				anim_train.remove_track(ti)
	if ap.has_animation("CraneTravel"):
		anim_crane = ap.get_animation("CraneTravel").duplicate() as Animation
		anim_crane.loop_mode = Animation.LOOP_LINEAR
		for ti in range(anim_crane.get_track_count() - 1, -1, -1):
			if not String(anim_crane.track_get_path(ti)).contains("P_overhead_crane"):
				anim_crane.remove_track(ti)

	var lib_train := AnimationLibrary.new()
	if anim_train != null:
		lib_train.add_animation("TrainShuttle", anim_train)
	if ap.has_animation_library(""):
		ap.remove_animation_library("")
	ap.add_animation_library("", lib_train)
	if anim_train != null:
		ap.play("TrainShuttle")
		ap.seek(8.0, true)

	if anim_crane != null:
		var ap_crane := AnimationPlayer.new()
		ap_crane.name = "CraneAnimationPlayer"
		ap_crane.root_node = ap.root_node
		var lib_crane := AnimationLibrary.new()
		lib_crane.add_animation("CraneTravel", anim_crane)
		ap_crane.add_animation_library("", lib_crane)
		ap.get_parent().add_child(ap_crane)
		ap_crane.play("CraneTravel")
		ap_crane.seek(3.0, true)


static func _get_ruins_tex(slug: String, kind: String) -> Texture2D:
	var key := "%s_%s" % [slug, kind]
	if _ruins_tex_cache.has(key):
		return _ruins_tex_cache[key] as Texture2D
	var path := "res://maps/ruins/textures/%s/%s_%s_1k.jpg" % [slug, slug, kind]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_ruins_tex_cache[key] = tex
	return tex


const NON_SHADOW_MATS := {
	"dirt": true, "grass": true, "gravel": true, "asphalt": true, "road": true,
	"pavement": true, "puddle": true, "water": true, "smoke": true, "fire": true,
	"debris": true, "rubber": true, "wood": true, "rebar": true,
	"fern_02": true, "grass_medium_01": true, "quiver_tree_01_leaf": true,
	"wild_rooibos_bush_twigs": true, "wild_rooibos_bush_leaves": true,
	"wild_rooibos_bush": true, "street_lamp_01_glass": true,
	"covered_car": true, "covered_car.001": true, "barrel_01": true, "barrel_02": true,
}

func _apply_ruins_materials(map_root: Node3D) -> void:
	var qlevel := QualityManager.get_active_level()
	var upgraded := {}
	for node in map_root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var nname := String(mi.name)
		var is_effect := nname.begins_with("EFFECTS_") or nname == "Train_Smoke"
		var aabb := mi.mesh.get_aabb()
		var ctr := mi.global_transform * (aabb.position + aabb.size * 0.5)
		var dist := Vector2(ctr.x, ctr.z).length()
		var is_clutter := aabb.size.length() < 90.0 and aabb.size.y < 10.0

		var shadow_dist := 135.0 if qlevel == QualityManager.Level.LOW else 220.0
		var all_non_shadow := is_effect or dist > shadow_dist
		if not all_non_shadow:
			all_non_shadow = true
			for s in range(mi.mesh.get_surface_count()):
				var sm := mi.get_active_material(s)
				var sn := String(sm.resource_name).to_lower() if sm != null else ""
				if not NON_SHADOW_MATS.has(sn):
					all_non_shadow = false
					break
		if all_non_shadow:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if nname.contains("grass") or nname.contains("fern") or nname.contains("bush"):
			mi.visibility_range_end = 125.0 if qlevel == QualityManager.Level.LOW else 260.0
			mi.visibility_range_end_margin = 18.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		elif (is_clutter and dist > 110.0) or (qlevel == QualityManager.Level.LOW and nname.contains("quiver_tree")):
			mi.visibility_range_end = 195.0 if qlevel == QualityManager.Level.LOW else 420.0
			mi.visibility_range_end_margin = 22.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		elif qlevel == QualityManager.Level.LOW and dist > 480.0:
			mi.visibility_range_end = 880.0
			mi.visibility_range_end_margin = 80.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

		# Raise puddle surface slightly (+1.2 cm) so shallow blobs never z-fight with asphalt.
		var has_puddle := false
		for s in range(mi.mesh.get_surface_count()):
			var mat := mi.get_active_material(s) as StandardMaterial3D
			if mat == null:
				continue
			var mname := String(mat.resource_name).to_lower()
			if mname == "puddle":
				has_puddle = true
			if mname.is_empty():
				continue
			if not upgraded.has(mname):
				var clone := mat.duplicate() as StandardMaterial3D
				_upgrade_ruins_material(clone, mname, qlevel)
				upgraded[mname] = clone
			mi.set_surface_override_material(s, upgraded[mname] as StandardMaterial3D)
		if has_puddle and mi.mesh.get_surface_count() == 1:
			mi.position.y += 0.014


func _upgrade_ruins_material(mat: StandardMaterial3D, mname: String, qlevel: int) -> void:
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if mname == "smoke":
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		mat.roughness = 1.0
		mat.metallic = 0.0
		mat.emission_enabled = true
		mat.emission = Color(0.46, 0.42, 0.37)
		mat.emission_energy_multiplier = 0.24
		return
	if mname == "fire":
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		mat.roughness = 1.0
		mat.metallic = 0.0
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.46, 0.10)
		mat.emission_energy_multiplier = 4.6
		return
	if mname == "puddle" or mname == "water":
		mat.vertex_color_use_as_albedo = false
		mat.albedo_color = Color(0.032, 0.038, 0.044, 1.0)
		mat.roughness = 0.18
		mat.metallic = 0.0
		mat.metallic_specular = 0.22
		mat.clearcoat_enabled = false
		var pnor := _get_ruins_tex("asphalt_02", "nor")
		if pnor != null:
			mat.normal_texture = pnor
			mat.normal_enabled = true
			mat.normal_scale = 0.18
		return
	if mname == "lamp":
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.78, 0.40)
		mat.emission_energy_multiplier = 6.5
		return
	if mname == "brass":
		mat.metallic = 0.92
		mat.roughness = 0.24
		return
	if mname == "glass":
		mat.roughness = 0.06
		mat.metallic = 0.15
		return
	if mname == "loco_black":
		mat.metallic = 0.55
		mat.roughness = 0.36
		return
	if mname == "loco_red":
		mat.metallic = 0.28
		mat.roughness = 0.42
		return
	if mname.contains("leaf") or mname.contains("leaves") or mname.contains("fern") \
			or mname.contains("grass_medium") or mname.contains("bush_twigs"):
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.45
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.backlight_enabled = true
		mat.backlight = Color(0.45, 0.38, 0.18)
		return

	# Architectural / terrain / rubble materials: enable baked vertex AO + swap 1K PBR maps
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	if RUINS_TEX_SLUGS.has(mname):
		var slug: String = String(RUINS_TEX_SLUGS[mname])
		var diff_t := _get_ruins_tex(slug, "diff")
		if diff_t != null:
			mat.albedo_texture = diff_t
		if qlevel > QualityManager.Level.LOW or mname in ["brick", "concrete", "concrete2", "asphalt", "rust", "rust2", "roof", "container"]:
			var nor_t := _get_ruins_tex(slug, "nor")
			if nor_t != null:
				mat.normal_texture = nor_t
				mat.normal_enabled = true
				mat.normal_scale = 1.30 if mname in ["brick", "concrete2", "rust", "rust2", "roof", "debris"] else 1.15
			var rough_t := _get_ruins_tex(slug, "rough")
			if rough_t != null:
				mat.roughness_texture = rough_t


func _setup_ruins_atmosphere_fx(map_root: Node3D) -> void:
	_fire_lights.clear()
	var lowspec := QualityManager.get_active_level() == QualityManager.Level.LOW
	for i in range(BARREL_FIRES_GODOT.size()):
		var pos: Vector3 = BARREL_FIRES_GODOT[i]
		var fl := OmniLight3D.new()
		fl.name = "RuinsFireGlow_%d" % i
		fl.position = pos
		fl.light_color = Color(1.0, 0.48, 0.15)
		fl.light_energy = 3.4
		fl.omni_range = 19.0
		fl.omni_attenuation = 1.55
		fl.shadow_enabled = false
		fl.distance_fade_enabled = true
		fl.distance_fade_begin = 95.0
		fl.distance_fade_length = 25.0
		map_root.add_child(fl)
		_fire_lights.append(fl)
		if not lowspec:
			_spawn_barrel_embers(map_root, pos, i)

	var loco := map_root.find_child("Train_SteamLoco", true, false) as Node3D
	if loco != null and loco.get_node_or_null("TrainHeadlampLight") == null:
		var hl := OmniLight3D.new()
		hl.name = "TrainHeadlampLight"
		hl.position = Vector3(5.8, 3.66, 0.0)
		hl.light_color = Color(1.0, 0.80, 0.44)
		hl.light_energy = 2.0
		hl.omni_range = 18.0
		hl.shadow_enabled = false
		loco.add_child(hl)


func _spawn_barrel_embers(parent: Node3D, pos: Vector3, idx: int) -> void:
	var gp := GPUParticles3D.new()
	gp.name = "BarrelEmbers_%d" % idx
	gp.position = pos + Vector3(0.0, 0.1, 0.0)
	gp.amount = 18
	gp.lifetime = 2.2
	gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gp.visibility_aabb = AABB(Vector3(-4.0, -0.5, -4.0), Vector3(8.0, 10.0, 8.0))
	gp.visibility_range_end = 135.0
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.18, 1.0, -0.10).normalized()
	pm.spread = 22.0
	pm.initial_velocity_min = 1.4
	pm.initial_velocity_max = 3.2
	pm.gravity = Vector3(0.0, 0.35, 0.0)
	pm.scale_min = 0.05
	pm.scale_max = 0.11
	var em_mat := StandardMaterial3D.new()
	em_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	em_mat.albedo_color = Color(1.0, 0.62, 0.18, 0.92)
	em_mat.emission_enabled = true
	em_mat.emission = Color(1.0, 0.56, 0.14)
	em_mat.emission_energy_multiplier = 4.2
	em_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	em_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var qm := QuadMesh.new()
	qm.size = Vector2(0.08, 0.08)
	qm.material = em_mat
	gp.process_material = pm
	gp.draw_pass_1 = qm
	parent.add_child(gp)


func _process(delta: float) -> void:
	super._process(delta)
	if not _fire_lights.is_empty():
		var t := float(Time.get_ticks_msec()) * 0.001
		for i in range(_fire_lights.size()):
			var fl := _fire_lights[i]
			if is_instance_valid(fl):
				fl.light_energy = 3.1 + 0.65 * sin(t * (7.3 + float(i) * 1.4)) + 0.30 * cos(t * 13.7 + float(i))


func _tune_map_environment() -> void:
	super._tune_map_environment()
	var lowspec := QualityManager.get_active_level() == QualityManager.Level.LOW
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null:
		var env := we.environment
		if env.sky != null:
			if _ruins_sky_mat == null and ResourceLoader.exists(RUINS_HDRI_PATH):
				var hdr := load(RUINS_HDRI_PATH) as Texture2D
				if hdr != null:
					var pm := PanoramaSkyMaterial.new()
					pm.panorama = hdr
					pm.filter = true
					_ruins_sky_mat = pm
			if _ruins_sky_mat != null:
				env.sky.sky_material = _ruins_sky_mat
				env.sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
				env.sky.set_meta("lowspec_sky_sun_azimuth", 200.0)
		env.sky_rotation = Vector3(0.0, deg_to_rad(100.0), 0.0)
		env.background_mode = Environment.BG_SKY
		env.background_energy_multiplier = 0.85
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_sky_contribution = 0.72
		env.ambient_light_color = Color(0.50, 0.56, 0.68)
		env.ambient_light_energy = 0.62
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		env.tonemap_mode = Environment.TONE_MAPPER_AGX
		env.tonemap_exposure = 1.08
		env.tonemap_white = 6.0
		env.adjustment_enabled = true
		env.adjustment_brightness = 1.02
		env.adjustment_contrast = 1.10
		env.adjustment_saturation = 1.12
		env.volumetric_fog_enabled = false
		env.volumetric_fog_density = 0.0
		env.fog_height_density = 0.0
		env.ssr_enabled = false
		env.sdfgi_enabled = false
		env.ssao_enabled = false
		if _weather != 3:
			env.fog_enabled = true
			env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
			env.fog_density = 0.00046
			env.fog_light_color = Color(0.86, 0.72, 0.54)
			env.fog_light_energy = 0.85
			env.fog_sun_scatter = 0.46
			env.fog_aerial_perspective = 0.34
			env.fog_sky_affect = 0.30
		env.glow_enabled = not lowspec
		if not lowspec:
			env.glow_normalized = true
			env.glow_intensity = 0.32
			env.glow_strength = 0.56
			env.glow_bloom = 0.08
			env.glow_hdr_threshold = 1.22
			env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		sun.rotation_degrees = Vector3(-11.0, 20.0, 0.0)
		sun.light_color = Color(1.0, 0.82, 0.58)
		sun.light_energy = 2.85
		sun.light_volumetric_fog_energy = 0.0
		sun.shadow_bias = 0.03
		sun.shadow_normal_bias = 1.5
		var act_lvl := QualityManager.get_active_level()
		if act_lvl == QualityManager.Level.LOW:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			sun.directional_shadow_max_distance = 100.0
			var fpv := get_node_or_null("Drone/FPVCamera") as Camera3D
			if fpv != null and fpv.far > 1100.0:
				fpv.far = 1100.0
		elif act_lvl == QualityManager.Level.MEDIUM:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			sun.directional_shadow_max_distance = 175.0
		else:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			sun.directional_shadow_max_distance = 200.0

	if (_sky_fill_light == null or not is_instance_valid(_sky_fill_light)) and is_inside_tree():
		_sky_fill_light = DirectionalLight3D.new()
		_sky_fill_light.name = "RuinsSkyFill"
		_sky_fill_light.rotation_degrees = Vector3(-42.0, -145.0, 0.0)
		_sky_fill_light.light_color = Color(0.54, 0.68, 0.94)
		_sky_fill_light.light_energy = 0.34
		_sky_fill_light.shadow_enabled = false
		add_child(_sky_fill_light)


func _authored_freestyle_waypoints() -> Array:
	return RuinsRingsScript.waypoints()


func _build_freestyle_ring_positions() -> bool:
	var ground_fn := Callable(self, "_find_ground_y")
	var specs := RuinsRingsScript.build_specs(ground_fn)
	if specs.is_empty():
		return false
	_freestyle_ring_specs = specs
	for spec in specs:
		_training_ring_positions.append(spec["pos"])
	return true


var _ground_y_cache: Dictionary = {}


func _find_ground_y(x: float, z: float) -> float:
	var cell := Vector2i(int(round(x * 0.5)), int(round(z * 0.5)))
	if _ground_y_cache.has(cell):
		return float(_ground_y_cache[cell])
	var space := get_world_3d().direct_space_state
	if space == null:
		return 0.0
	var exclude: Array[RID] = []
	var drone := get_node_or_null("Drone")
	if drone is CollisionObject3D:
		exclude.append((drone as CollisionObject3D).get_rid())
	var tree := get_tree()
	if tree != null:
		for grp in ["drone", "combat_target", "enemy_infantry", "enemy_vehicle", "kamikaze_drone"]:
			for n in tree.get_nodes_in_group(grp):
				if n is CollisionObject3D:
					var rid := (n as CollisionObject3D).get_rid()
					if not exclude.has(rid):
						exclude.append(rid)
	# Cast from low street height (2.2 m) downward so ground rays hit roads/pavement/dirt
	# and NEVER mistakenly land on 12-45 m rooftops or overpass decks.
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 2.2, z), Vector3(x, -4.0, z))
	q.collision_mask = 1
	q.exclude = exclude
	var hit := space.intersect_ray(q)
	var y_val := 0.0 if hit.is_empty() else clampf((hit["position"] as Vector3).y, -0.5, 2.0)
	_ground_y_cache[cell] = y_val
	return y_val


func _spawn_ground_height(x: float, z: float) -> float:
	return _find_ground_y(x, z)


static func _in_train_corridor(x: float, z: float, margin: float = 8.0) -> bool:
	return x >= -240.0 and x <= 42.0 and absf(z - 112.0) < margin


static func _in_building_footprint(x: float, z: float, pad: float = 2.5) -> bool:
	for box in BUILDING_EXCLUSIONS:
		if x >= float(box[0]) - pad and x <= float(box[2]) + pad \
				and z >= float(box[1]) - pad and z <= float(box[3]) + pad:
			return true
	return false


func _is_ground_spot_clear(x: float, z: float) -> bool:
	if absf(x) > MAP_GROUND_SAFE or absf(z) > MAP_GROUND_SAFE:
		return false
	if _in_train_corridor(x, z, 8.0):
		return false
	if _in_building_footprint(x, z, 2.5):
		return false
	return not _spawn_overlaps_geometry(x, z, _find_ground_y(x, z))


func _spawn_is_wet(_x: float, _z: float, _ground: float) -> bool:
	return false


func _find_dry_spot(x: float, z: float) -> Vector2:
	var cx := clampf(x, -MAP_GROUND_SAFE, MAP_GROUND_SAFE)
	var cz := clampf(z, -MAP_GROUND_SAFE, MAP_GROUND_SAFE)
	if _is_ground_spot_clear(cx, cz):
		return Vector2(cx, cz)
	for r_step in range(1, 16):
		var rad := 4.5 * float(r_step)
		for i in range(16):
			var ang := TAU * float(i) / 16.0
			var px := clampf(cx + cos(ang) * rad, -MAP_GROUND_SAFE, MAP_GROUND_SAFE)
			var pz := clampf(cz + sin(ang) * rad, -MAP_GROUND_SAFE, MAP_GROUND_SAFE)
			if _is_ground_spot_clear(px, pz):
				return Vector2(px, pz)
	return Vector2(25.0, 72.0)


func _special_ground_point(x: float, z: float) -> Vector3:
	var dry := _find_dry_spot(x, z)
	return Vector3(dry.x, _find_ground_y(dry.x, dry.y) + 0.05, dry.y)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_guard_drone_above_terrain()


func _guard_drone_above_terrain() -> void:
	var drone := get_node_or_null("Drone") as RigidBody3D
	if drone == null or not is_instance_valid(drone) or drone.freeze:
		return
	var p := drone.global_position
	if absf(p.x) > MAP_FLIGHT_BOUND or absf(p.z) > MAP_FLIGHT_BOUND:
		return
	var now := Time.get_ticks_msec()
	var xz := Vector2(p.x, p.z)
	if now - _guard_probe_ms >= 500 or _guard_probe_xz.distance_squared_to(xz) > 9.0:
		_guard_probe_ms = now
		_guard_probe_xz = xz
		_guard_probe_y = _find_ground_y(p.x, p.z)
	var gy := _guard_probe_y
	if p.y < gy - 0.8:
		drone.global_position = Vector3(p.x, gy + 0.9, p.z)
		var lv := drone.linear_velocity
		if lv.y < 0.0:
			drone.linear_velocity = Vector3(lv.x, 0.0, lv.z)


func _find_ruins_spawn() -> Dictionary:
	var raw_xz := Vector2(25.0, 72.0)
	var yaw := 0.0
	if Global.play_mode == Global.PlayMode.TUTORIAL or (Global.play_mode == Global.PlayMode.TRAINING and Global.combat_training):
		# Open north Main Avenue straight facing south (+Z) away from northern edge.
		raw_xz = Vector2(25.0, -210.0)
		yaw = PI
	elif Global.play_mode == Global.PlayMode.COMBAT and Global.special_mission in [2, 11]:
		# Behind Convoy A on open west East-West Street facing east toward Avenue.
		raw_xz = Vector2(-218.0, -30.0)
		yaw = -PI * 0.5
	elif Global.play_mode == Global.PlayMode.TRAINING:
		# Freestyle launch on left lane of avenue, centered cleanly in viaduct span toward Gate 1.
		raw_xz = Vector2(21.0, 72.0)
		yaw = 0.0
	else:
		# Combat / Special Ops: open north Main Avenue apron facing south toward skyline.
		raw_xz = Vector2(25.0, -175.0)
		yaw = PI

	var resolved := _resolve_spawn_position(raw_xz)
	var pos2: Vector2 = resolved["pos"]
	var gy := _find_ground_y(pos2.x, pos2.y)
	return {"xz": pos2, "ground": gy, "yaw": yaw}


func _place_drone_over_ground() -> void:
	var d := get_node_or_null("Drone") as Drone
	if d == null:
		return
	var sp := _find_ruins_spawn()
	var pos2: Vector2 = sp["xz"]
	var gy := float(sp["ground"])
	var yaw := float(sp["yaw"])
	_ground_y = gy
	var barrel_top := _setup_launch_barrel(Vector3(pos2.x, gy, pos2.y))
	var spawn_y := maxf(gy + SPAWN_SAFE_OFFSET, gy + barrel_top + 0.03)
	var pos := Vector3(pos2.x, spawn_y, pos2.y)
	var spawn_xform := Transform3D(Basis(Vector3.UP, yaw), pos)
	var respawn := get_node_or_null("Respawn") as Node3D
	if respawn != null:
		respawn.global_transform = spawn_xform
	_add_spawn_pad(pos2, gy)
	d.global_transform = spawn_xform
	_drone_prev_pos = d.global_position
	_drone_last_speed = 0.0
	_drone_peak_speed = 0.0
	d.linear_velocity = Vector3.ZERO
	d.angular_velocity = Vector3.ZERO
	if d.has_method("reset_motion_history"):
		d.reset_motion_history()
	var fc = d.get("flight_controller")
	if fc != null and fc.has_method("reset"):
		fc.reset()
	d.freeze = true
	var existing_model := d.get_node_or_null("DroneModel")
	if existing_model == null or int(existing_model.get_meta("preset_index", -1)) != Global.drone_preset:
		DroneCatalog.apply_to_drone(d, Global.drone_preset)
	else:
		_sync_fpv_drone_model(false, false, true)
	if fc != null:
		if not fc.armed.is_connected(_on_drone_armed):
			fc.armed.connect(_on_drone_armed)
		if not fc.arm_failed.is_connected(_on_arm_failed):
			fc.arm_failed.connect(_on_arm_failed)
	if not d.respawned.is_connected(_on_respawned):
		d.respawned.connect(_on_respawned)


# ---------------------------------------------------------------------------
#  Vehicles, Campaign Missions 1..4, and Special Ops 1..13 on Ruins Streets
# ---------------------------------------------------------------------------
func _spawn_vehicles() -> void:
	var lowspec := QualityManager.get_active_level() == QualityManager.Level.LOW
	var ew_street := [
		Vector3(-210.0, 0.0, -30.0), Vector3(-100.0, 0.0, -30.0),
		Vector3(25.0, 0.0, -30.0), Vector3(160.0, 0.0, -30.0),
	]
	var south_service := [
		Vector3(-190.0, 0.0, 72.0), Vector3(-60.0, 0.0, 72.0),
		Vector3(25.0, 0.0, 72.0), Vector3(145.0, 0.0, 72.0),
	]
	_add_vehicle(Vehicle.Kind.TRUCK, ew_street, 8.5, false, false, 0.0, false)
	_add_vehicle(Vehicle.Kind.APC, south_service, 9.0, false, false, 0.0, false)
	if not lowspec:
		_add_vehicle(Vehicle.Kind.TANK, [
			Vector3(25.0, 0.0, -140.0), Vector3(25.0, 0.0, -30.0),
			Vector3(25.0, 0.0, 72.0), Vector3(25.0, 0.0, -30.0),
		], 6.4, false, false, 0.0, false)
		_add_vehicle(Vehicle.Kind.HELI,
			_loop_waypoints(0.0, 0.0, 155.0, 8, 0.4), 12.0, false, false, 70.0, false)


func _spawn_combat_mission(mission_id: int) -> void:
	_mission_targets_total = 0
	_mission_targets_destroyed = 0
	_kills.clear()
	randomize()
	_offset_targets = false
	_mission_offset = Vector3(randf_range(-8.0, 8.0), 0.0, randf_range(-8.0, 8.0))

	match mission_id:
		1:
			var centers := [
				Vector3(-105.0, 0.0, -28.0),
				Vector3(120.0, 0.0, 20.0),
				Vector3(-55.0, 0.0, 72.0),
			]
			var base_center := (centers[randi() % centers.size()] as Vector3) + _mission_offset
			var dry_bc := _find_dry_spot(base_center.x, base_center.z)
			base_center = Vector3(dry_bc.x, 0.0, dry_bc.y)
			var sp_xz := _player_spawn_xz()
			if Vector2(base_center.x, base_center.z).distance_to(sp_xz) < 95.0:
				var safe_bc := _ensure_enemy_xz_clearance(
					Vector2(base_center.x, base_center.z), 98.0, MAP_GROUND_SAFE - 18.0, false)
				base_center = Vector3(safe_bc.x, 0.0, safe_bc.y)
			var inf_count := 6
			if Global.difficulty == Global.Difficulty.RECRUIT:
				inf_count = 4
			elif Global.difficulty == Global.Difficulty.ACE:
				inf_count = 8
			for i in range(inf_count):
				var angle := (float(i) / float(inf_count)) * TAU + randf_range(-0.2, 0.2)
				var dist := randf_range(10.0, 20.0)
				var raw_p := base_center + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
				var dry_i := _find_dry_spot(raw_p.x, raw_p.z)
				var pos := Vector3(dry_i.x, 0.0, dry_i.y)
				var patrol_ang := randf() * TAU
				var axis := Vector3(cos(patrol_ang), 0.0, sin(patrol_ang))
				var inf_var := "spetsnaz" if (Global.difficulty == Global.Difficulty.ACE and i >= 6) else ""
				_add_mission_infantry(pos, axis, randf_range(7.0, 11.0), randf_range(1.05, 1.35), true, inf_var)

		2:
			var tank_route := [
				Vector3(-195.0, 0.0, -30.0), Vector3(25.0, 0.0, -30.0),
				Vector3(25.0, 0.0, 72.0), Vector3(25.0, 0.0, -30.0),
			]
			var apc_route := [
				Vector3(-165.0, 0.0, 72.0), Vector3(135.0, 0.0, 72.0),
			]
			_add_vehicle(Vehicle.Kind.TANK, tank_route, randf_range(5.4, 6.4), true, true)
			_mission_targets_total += 1
			_add_vehicle(Vehicle.Kind.APC, apc_route, randf_range(9.5, 11.0), true, true)
			_mission_targets_total += 1
			if Global.difficulty == Global.Difficulty.ACE:
				var bmp_route := [
					Vector3(25.0, 0.0, 20.0), Vector3(155.0, 0.0, 20.0),
				]
				_add_vehicle(Vehicle.Kind.BMP, bmp_route, 8.8, true, true)
				_mission_targets_total += 1
			_add_mission_infantry(_special_ground_point(8.0, 15.0), Vector3(1.0, 0.0, 0.0), 10.0, 1.7, false)
			if Global.difficulty != Global.Difficulty.RECRUIT:
				_add_mission_infantry(_special_ground_point(-80.0, 72.0), Vector3(-1.0, 0.0, 0.0), 10.0, 1.7, false)
			_add_aa_gun(_special_ground_point(85.0, -28.0), false)

		3:
			var heli_pts := _loop_waypoints(0.0, 0.0, 140.0, 8, 0.25)
			_add_vehicle(Vehicle.Kind.HELI, heli_pts, randf_range(11.5, 13.5), true, true, randf_range(64.0, 74.0))
			_mission_targets_total += 1
			var sam_route := [
				Vector3(25.0, 0.0, -30.0), Vector3(165.0, 0.0, -30.0),
			]
			_add_vehicle(Vehicle.Kind.SAM, sam_route, 4.4, true, true)
			_mission_targets_total += 1
			if Global.difficulty == Global.Difficulty.ACE:
				var m3_bmp := [
					Vector3(-175.0, 0.0, 72.0), Vector3(120.0, 0.0, 72.0),
				]
				_add_vehicle(Vehicle.Kind.BMP, m3_bmp, 8.6, true, true)
				_mission_targets_total += 1
			_add_aa_gun(_special_ground_point(-115.0, -28.0), false)
			_add_aa_gun(_special_ground_point(115.0, 72.0), false)

		4:
			var p_pts1 := [
				Vector3(-215.0, 0.0, -175.0), Vector3(215.0, 0.0, -120.0),
				Vector3(205.0, 0.0, 165.0), Vector3(-210.0, 0.0, 110.0),
			]
			var p_pts2 := [
				Vector3(215.0, 0.0, -170.0), Vector3(-200.0, 0.0, -135.0),
				Vector3(-215.0, 0.0, 180.0), Vector3(210.0, 0.0, 125.0),
			]
			_add_vehicle(Vehicle.Kind.SHAHED, p_pts1, randf_range(17.5, 21.5), true, false, randf_range(72.0, 84.0))
			_mission_targets_total += 1
			_add_vehicle(Vehicle.Kind.SHAHED, p_pts2, randf_range(17.5, 21.5), true, false, randf_range(76.0, 88.0))
			_mission_targets_total += 1
			var m4_sam := [
				Vector3(-190.0, 0.0, 72.0), Vector3(25.0, 0.0, 72.0),
			]
			_add_vehicle(Vehicle.Kind.SAM, m4_sam, 4.6, true, true)
			_mission_targets_total += 1
			if Global.difficulty != Global.Difficulty.RECRUIT:
				var m4_bmp := [
					Vector3(25.0, 0.0, -30.0), Vector3(175.0, 0.0, -30.0),
				]
				_add_vehicle(Vehicle.Kind.BMP, m4_bmp, 9.0, true, true)
				_mission_targets_total += 1
			if Global.difficulty == Global.Difficulty.ACE:
				var m4_apc := [
					Vector3(-200.0, 0.0, -30.0), Vector3(-50.0, 0.0, -30.0),
				]
				_add_vehicle(Vehicle.Kind.APC, m4_apc, 9.4, true, true, 0.0, true, "btr8")
				_mission_targets_total += 1
			_add_aa_gun(_special_ground_point(-125.0, 72.0), false)
			_add_aa_gun(_special_ground_point(130.0, 20.0), false)

	_offset_targets = false
	if mission_id != 1:
		_spawn_frontline_bonus_targets()
	print("[RuinsLevel] spawned Combat Mission %d/4 with %d required targets" % [mission_id, _mission_targets_total])


func _spawn_frontline_bonus_targets() -> void:
	var spots := [
		[_special_ground_point(10.0, 12.0), Vector3(1.0, 0.0, 0.0), 10.0],
		[_special_ground_point(-100.0, -28.0), Vector3(0.0, 0.0, 1.0), 10.0],
		[_special_ground_point(135.0, 72.0), Vector3(-1.0, 0.0, 0.0), 10.0],
	]
	for spot in spots:
		_add_mission_infantry(spot[0] as Vector3, spot[1] as Vector3, float(spot[2]), 1.65, false)


func _spawn_reinforcement_wave() -> void:
	if _mission_finished or _reinforcement_wave >= 4:
		return
	_reinforcement_wave += 1
	if _reinforcement_wave >= 4:
		var timer := get_node_or_null("ReinforcementTimer") as Timer
		if timer != null:
			timer.stop()
	var anchors := [Vector2(-105.0, -28.0), Vector2(130.0, 20.0), Vector2(-60.0, 72.0), Vector2(125.0, 72.0)]
	var anc: Vector2 = anchors[(_reinforcement_wave - 1) % anchors.size()]
	var dry := _find_dry_spot(anc.x + randf_range(-16.0, 16.0), anc.y + randf_range(-12.0, 12.0))
	_add_mission_infantry(Vector3(dry.x, 0.0, dry.y), Vector3(1.0, 0.0, 0.2), 9.0, 1.75, false)
	_set_flash("ПІДКРІПЛЕННЯ ПРОТИВНИКА · ПІХОТА" if not MenuUI.is_english()
			else "ENEMY REINFORCEMENTS · INFANTRY")


func _spawn_special_mission(mission_id: int) -> void:
	_mission_targets_total = 0
	_mission_targets_destroyed = 0
	_kills.clear()
	_special_index = 0
	_special_hold = 0.0
	_special_zones.clear()
	_special_beacons.clear()
	_special_convoy = null
	_special_convoy_far_timer = 0.0
	_special_convoy_warned = false
	_special_convoy_stall_anchor = Vector3.ZERO
	_special_convoy_stall = 0.0
	_special_convoy_recoveries = 0
	_special_convoy_b = null
	_special_convoy_b_dest = Vector3.ZERO
	_special_convoy_b_start = Vector3.ZERO
	_special_convoy_b_stall_anchor = Vector3.ZERO
	_special_convoy_b_stall = 0.0
	_special_convoy_b_recoveries = 0
	_dawn_defense_pos = Vector3.ZERO
	_dawn_defense_beacon = null
	_reserved_ground_route.clear()
	_special_extract_active = false
	_special_extract_hold = 0.0
	_special_extract_point = _special_ground_point(25.0, -175.0)
	_special_extract_beacon = null
	_special_pickup_prop = null
	_offset_targets = false
	_intercept_wave = 0
	_intercept_timer = 0.0
	_intercept_warned = false
	_intercept_leaks = 0
	_intercept_missiles.clear()

	match mission_id:
		1:
			_add_special_zone(_special_ground_point(-105.0, -28.0), 40.0, 2.0, "РОЗВІДКА 1/3")
			_add_special_zone(_special_ground_point(150.0, -28.0), 40.0, 2.0, "РОЗВІДКА 2/3")
			_add_special_zone(_special_ground_point(125.0, 72.0), 42.0, 2.0, "РОЗВІДКА 3/3")
			_spawn_special_guards([
				_special_ground_point(-80.0, -28.0),
				_special_ground_point(120.0, -28.0),
				_special_ground_point(80.0, 72.0),
			])
		2:
			_setup_special_escort()
		3:
			_add_special_zone(_special_ground_point(130.0, 72.0), 38.0, 2.5, "ЕВАКУАЦІЯ · ПІЛОТ")
			_add_special_zone(_special_ground_point(25.0, -175.0), 46.0, 2.5, "ЕВАКУАЦІЯ · БАЗА")
			_special_pickup_prop = _spawn_special_pickup_marker(_special_zones[0]["pos"], true)
			_spawn_special_guards([
				_special_ground_point(95.0, 72.0),
				_special_ground_point(150.0, 72.0),
			])
		4:
			_add_special_zone(_special_ground_point(-145.0, -30.0), 36.0, 2.0, "ВАНТАЖ · ЗАБРАТИ")
			_add_special_zone(_special_ground_point(135.0, 20.0), 38.0, 2.0, "ВАНТАЖ · ДОСТАВИТИ")
			_special_pickup_prop = _spawn_special_pickup_marker(_special_zones[0]["pos"], false)
			_spawn_special_guards([
				_special_ground_point(-85.0, -30.0),
				_special_ground_point(80.0, 20.0),
			])
		5:
			_spawn_special_strike(false)
		6:
			_spawn_special_strike(true)
		7:
			_spawn_special_rear_convoy()
		8:
			_spawn_special_oreshnik(false)
		9:
			_spawn_special_oreshnik(true)
		10:
			_spawn_special_missile_intercept()
		11:
			_setup_special_dual_escort()
		12:
			_setup_special_dawn_defense()
		13:
			_setup_special_sar_landing()

	if mission_id >= 5 and mission_id <= 10:
		_special_extract_beacon = _spawn_special_beacon(_special_extract_point,
				_txt("ВИХІД · БАЗА", "EXFIL · BASE"), Color(0.35, 0.95, 0.75))
		_special_extract_beacon.visible = false
	print("[RuinsLevel] spawned Special Operation %d (%s), targets=%d" % [
		mission_id, Global.get_special_mission_name(mission_id), _mission_targets_total
	])


func _build_ruins_street_route(raw_pts: Array) -> Array[Vector3]:
	var route: Array[Vector3] = []
	for p2 in raw_pts:
		var v2: Vector2 = p2 as Vector2
		route.append(_special_ground_point(v2.x, v2.y))
	return route


func _setup_special_escort() -> void:
	# Clean paved street route: West EW Street -> Main Avenue -> South Service Road (never hits train/buildings)
	var route := _build_ruins_street_route([
		Vector2(-205.0, -30.0), Vector2(-100.0, -30.0), Vector2(25.0, -30.0),
		Vector2(25.0, 20.0), Vector2(25.0, 72.0), Vector2(145.0, 72.0),
	])
	var vehicle := VEHICLE.new()
	vehicle.kind = Vehicle.Kind.TRUCK
	vehicle.hostile = false
	vehicle.track_drone = false
	vehicle.move_speed = 11.0
	add_child(vehicle)
	vehicle.max_health = 480.0
	vehicle.health = 480.0
	vehicle.global_position = route[0] + Vector3.UP * 0.2
	vehicle.set_waypoints(route)
	vehicle.remove_from_group("combat_target")
	vehicle.add_to_group("escort_convoy")
	vehicle.destroyed.connect(_on_escort_destroyed)
	_special_convoy = vehicle
	_special_convoy_start = route[0]
	_special_convoy_dest = route[route.size() - 1]
	_spawn_special_guards([
		_special_ground_point(-85.0, -18.0),
		_special_ground_point(10.0, 12.0),
		_special_ground_point(95.0, 62.0),
	])
	_add_vehicle(Vehicle.Kind.APC, [
		_special_ground_point(145.0, 72.0),
		_special_ground_point(55.0, 72.0),
	], 5.6, true, false, 0.0, false, "btr8")


func _update_escort_mission(delta: float, drone: Drone) -> void:
	if _special_convoy == null or not is_instance_valid(_special_convoy):
		_special_fail("КОЛОНУ ЗНИЩЕНО — СУПРОВІД ПРОВАЛЕНО")
		return
	var max_leash := maxf(260.0, MAP_GROUND_SAFE * 0.95)
	var dist := drone.global_position.distance_to(_special_convoy.global_position)
	if dist > max_leash:
		_special_convoy_far_timer += delta
		if _special_convoy_far_timer > 4.0 and not _special_convoy_warned:
			_special_convoy_warned = true
			_set_flash(_txt("НЕ ВІДРИВАЙТЕСЯ ВІД КОЛОНИ!", "STAY WITH THE CONVOY!"))
			_play_radio_callout(_txt("ТРИМАЙТЕСЬ БЛИЖЧЕ ДО КОЛОНИ", "KEEP CLOSER TO THE CONVOY"), true)
		if _special_convoy_far_timer > 12.0:
			_special_fail("КОЛОНУ ВТРАЧЕНО — СУПРОВІД ПРОВАЛЕНО")
			return
	else:
		_special_convoy_far_timer = maxf(_special_convoy_far_timer - delta * 2.0, 0.0)
		if _special_convoy_far_timer < 1.0:
			_special_convoy_warned = false
	if _special_convoy.global_position.distance_to(_special_convoy_dest) < 55.0:
		_finish_special_success()
		return
	if _special_convoy_stall_anchor == Vector3.ZERO:
		_special_convoy_stall_anchor = _special_convoy.global_position
	if _special_convoy.global_position.distance_to(_special_convoy_stall_anchor) < 0.35:
		_special_convoy_stall += delta
	else:
		_special_convoy_stall_anchor = _special_convoy.global_position
		_special_convoy_stall = 0.0
	if _special_convoy_stall >= 4.0:
		_special_convoy_stall = 0.0
		_special_convoy.call("escort_emergency_advance")


func _setup_special_dual_escort() -> void:
	_setup_special_escort()
	var route_b := _build_ruins_street_route([
		Vector2(25.0, -185.0), Vector2(25.0, -80.0), Vector2(25.0, -30.0),
		Vector2(25.0, 72.0), Vector2(-145.0, 72.0),
	])
	var vehicle_b := VEHICLE.new()
	vehicle_b.kind = Vehicle.Kind.TRUCK
	vehicle_b.hostile = false
	vehicle_b.track_drone = false
	vehicle_b.move_speed = 10.5
	add_child(vehicle_b)
	vehicle_b.max_health = 480.0
	vehicle_b.health = 480.0
	vehicle_b.global_position = route_b[0] + Vector3.UP * 0.2
	vehicle_b.set_waypoints(route_b)
	vehicle_b.remove_from_group("combat_target")
	vehicle_b.add_to_group("escort_convoy")
	vehicle_b.destroyed.connect(_on_escort_destroyed)
	_special_convoy_b = vehicle_b
	_special_convoy_b_start = route_b[0]
	_special_convoy_b_dest = route_b[route_b.size() - 1]


func _update_dual_escort_mission(delta: float, drone: Drone) -> void:
	if _special_convoy == null or not is_instance_valid(_special_convoy) \
			or _special_convoy_b == null or not is_instance_valid(_special_convoy_b):
		_special_fail("КОЛОНУ ЗНИЩЕНО — СУПРОВІД ПРОВАЛЕНО")
		return
	var max_leash := maxf(270.0, MAP_GROUND_SAFE)
	var dist := minf(drone.global_position.distance_to(_special_convoy.global_position),
			drone.global_position.distance_to(_special_convoy_b.global_position))
	if dist > max_leash:
		_special_convoy_far_timer += delta
		if _special_convoy_far_timer > 4.0 and not _special_convoy_warned:
			_special_convoy_warned = true
			_set_flash(_txt("НЕ ВІДРИВАЙТЕСЯ ВІД КОЛОН!", "STAY WITH THE CONVOYS!"))
		if _special_convoy_far_timer > 12.0:
			_special_fail("КОЛОНУ ВТРАЧЕНО — СУПРОВІД ПРОВАЛЕНО")
			return
	else:
		_special_convoy_far_timer = maxf(_special_convoy_far_timer - delta * 2.0, 0.0)
	var a_arrived := _special_convoy.global_position.distance_to(_special_convoy_dest) < 55.0
	var b_arrived := _special_convoy_b.global_position.distance_to(_special_convoy_b_dest) < 55.0
	if a_arrived and b_arrived:
		_finish_special_success()
		return
	if not a_arrived:
		if _special_convoy_stall_anchor == Vector3.ZERO:
			_special_convoy_stall_anchor = _special_convoy.global_position
		if _special_convoy.global_position.distance_to(_special_convoy_stall_anchor) < 0.35:
			_special_convoy_stall += delta
		else:
			_special_convoy_stall_anchor = _special_convoy.global_position
			_special_convoy_stall = 0.0
		if _special_convoy_stall >= 4.0:
			_special_convoy_stall = 0.0
			_special_convoy.call("escort_emergency_advance")
	if not b_arrived:
		if _special_convoy_b_stall_anchor == Vector3.ZERO:
			_special_convoy_b_stall_anchor = _special_convoy_b.global_position
		if _special_convoy_b.global_position.distance_to(_special_convoy_b_stall_anchor) < 0.35:
			_special_convoy_b_stall += delta
		else:
			_special_convoy_b_stall_anchor = _special_convoy_b.global_position
			_special_convoy_b_stall = 0.0
		if _special_convoy_b_stall >= 4.0:
			_special_convoy_b_stall = 0.0
			_special_convoy_b.call("escort_emergency_advance")


func _spawn_special_strike(ew_breach: bool) -> void:
	_add_vehicle(Vehicle.Kind.SAM, [
		Vector3(25.0, 0.0, -30.0), Vector3(170.0, 0.0, -30.0),
	], 4.8, true, true)
	_mission_targets_total += 1
	_add_vehicle(Vehicle.Kind.BMP, [
		Vector3(-175.0, 0.0, 72.0), Vector3(120.0, 0.0, 72.0),
	], 9.0, true, true)
	_mission_targets_total += 1
	_spawn_special_guards([
		_special_ground_point(80.0, -30.0),
		_special_ground_point(-75.0, 72.0),
	], false, "spetsnaz" if ew_breach else "")
	_add_aa_gun(_special_ground_point(-120.0, -30.0), false)
	if ew_breach:
		_spawn_special_guards([_special_ground_point(115.0, 72.0)], false, "spetsnaz")
		_add_aa_gun(_special_ground_point(125.0, 20.0), false)


func _spawn_special_rear_convoy() -> void:
	_add_vehicle(Vehicle.Kind.APC, [
		Vector3(-190.0, 0.0, -30.0), Vector3(25.0, 0.0, -30.0),
	], 9.0, true, true, 0.0, true, "btr8")
	_mission_targets_total += 1
	_add_vehicle(Vehicle.Kind.APC, [
		Vector3(25.0, 0.0, 20.0), Vector3(155.0, 0.0, 20.0),
	], 7.2, true, true, 0.0, true, "mtsm")
	_mission_targets_total += 1
	_add_vehicle(Vehicle.Kind.TRUCK, [
		Vector3(-165.0, 0.0, 72.0), Vector3(135.0, 0.0, 72.0),
	], 8.0, true, false, 0.0, true, "ural")
	_mission_targets_total += 1
	_spawn_special_guards([
		_special_ground_point(10.0, 12.0),
		_special_ground_point(-90.0, 72.0),
	], true, "spetsnaz")
	_add_aa_gun(_special_ground_point(95.0, -30.0), false)


func _spawn_special_oreshnik(deep_strike: bool) -> void:
	_add_vehicle(Vehicle.Kind.SAM, [
		Vector3(85.0, 0.0, 72.0), Vector3(165.0, 0.0, 72.0),
	], 3.6 if deep_strike else 3.4, true, true, 0.0, true, "oreshnik")
	_mission_targets_total += 1
	_add_vehicle(Vehicle.Kind.APC, [
		Vector3(-190.0, 0.0, -30.0), Vector3(25.0, 0.0, -30.0),
	], 9.0 if deep_strike else 8.4, true, true, 0.0, true, "btr8")
	_mission_targets_total += 1
	_add_aa_gun(_special_ground_point(-45.0, 72.0), false)
	if deep_strike:
		_add_vehicle(Vehicle.Kind.SAM, [
			Vector3(35.0, 0.0, -30.0), Vector3(165.0, 0.0, -30.0),
		], 4.6, true, true)
		_mission_targets_total += 1
		_add_vehicle(Vehicle.Kind.APC, [
			Vector3(25.0, 0.0, 20.0), Vector3(155.0, 0.0, 20.0),
		], 7.2, true, true, 0.0, true, "mtsm")
		_mission_targets_total += 1
		_spawn_special_guards([
			_special_ground_point(25.0, -30.0),
			_special_ground_point(110.0, 72.0),
		], true, "spetsnaz")
		_add_aa_gun(_special_ground_point(-125.0, -30.0), false)
	else:
		_add_vehicle(Vehicle.Kind.TRUCK, [
			Vector3(25.0, 0.0, 20.0), Vector3(155.0, 0.0, 20.0),
		], 7.2, true, false, 0.0, true, "ural")
		_mission_targets_total += 1
		_spawn_special_guards([
			_special_ground_point(65.0, 20.0),
			_special_ground_point(-80.0, -30.0),
		], false, "spetsnaz")


func _spawn_missile_wave() -> void:
	var count: int = MISSILE_WAVE_COUNTS[_intercept_wave]
	var wave_no := _intercept_wave + 1
	var edge_x := 250.0
	var lane_half := 180.0
	var lane_step := (lane_half * 2.0) / maxf(float(count) - 1.0, 1.0)
	for i in range(count):
		var lane := randf_range(-lane_half, lane_half) if count == 1 \
				else -lane_half + lane_step * float(i) + randf_range(-8.0, 8.0)
		var goal_lane := clampf(lane + randf_range(-16.0, 16.0), -lane_half, lane_half)
		var altitude := randf_range(80.0, 98.0)
		var speed := randf_range(26.0, 35.0) * Global.get_difficulty_missile_speed_scale()
		var start := Vector3(-edge_x, 0.0, lane)
		var goal := Vector3(edge_x, 0.0, goal_lane)
		var missile := _add_vehicle(Vehicle.Kind.SHAHED, [start, goal], speed, false, false, altitude, true, "cruise_missile")
		if missile == null:
			continue
		var beacon := missile.get_node_or_null("FriendlyConvoyBeacon")
		if beacon != null:
			beacon.queue_free()
		missile.set_meta("intercept_target", true)
		_intercept_missiles.append({
			"vehicle": missile, "goal": goal, "start": start,
			"speed": speed, "spawned": _mission_time,
		})
	_intercept_wave += 1
	_set_flash(_txt("ХВИЛЯ %d — РАКЕТИ В ПОВІТРІ!" % wave_no, "WAVE %d — MISSILES AIRBORNE!" % wave_no))
	_play_alert("incoming")


func _setup_special_dawn_defense() -> void:
	_dawn_defense_pos = _special_ground_point(25.0, -145.0)
	_dawn_defense_beacon = _spawn_special_beacon(_dawn_defense_pos, "ОПОРНИЙ ПУНКТ", Color(0.95, 0.76, 0.28))
	_add_vehicle(Vehicle.Kind.BMP, [
		Vector3(25.0, 0.0, 72.0), Vector3(25.0, 0.0, -90.0),
	], 7.6, true, true)
	_mission_targets_total += 1
	_add_vehicle(Vehicle.Kind.APC, [
		Vector3(-170.0, 0.0, -30.0), Vector3(25.0, 0.0, -30.0), Vector3(25.0, 0.0, -95.0),
	], 8.0, true, true, 0.0, true, "btr8")
	_mission_targets_total += 1
	if Global.difficulty == Global.Difficulty.ACE:
		_add_vehicle(Vehicle.Kind.TANK, [
			Vector3(165.0, 0.0, -30.0), Vector3(25.0, 0.0, -30.0), Vector3(25.0, 0.0, -100.0),
		], 5.8, true, true)
		_mission_targets_total += 1
	_spawn_special_guards([
		_special_ground_point(10.0, -70.0),
		_special_ground_point(35.0, -60.0),
	], true, "spetsnaz")
	_add_aa_gun(_special_ground_point(25.0, -15.0), false)


func _setup_special_sar_landing() -> void:
	_add_special_zone(_special_ground_point(135.0, 72.0), 38.0, 2.5, "РЯТУВАЛЬНА ЗОНА · ПОСАДКА")
	_add_special_zone(_special_ground_point(25.0, -175.0), 44.0, 2.5, "БАЗА · ПОСАДКА")
	_special_pickup_prop = _spawn_special_pickup_marker(_special_zones[0]["pos"], true)
	_spawn_special_guards([
		_special_ground_point(90.0, 72.0),
		_special_ground_point(155.0, 72.0),
	], false)


func _spawn_kamikaze_drones() -> void:
	super._spawn_kamikaze_drones()
	for kz in get_tree().get_nodes_in_group("enemy_kamikaze"):
		if kz is Node3D:
			var n := kz as Node3D
			var p := n.global_position
			if p.y < 78.0:
				n.global_position = Vector3(p.x, 78.0, p.z)


func _setup_reb() -> void:
	super._setup_reb()
	if _reb != null:
		_reb.base_range_m = maxf(880.0, MAP_FLIGHT_BOUND * 2.6)
