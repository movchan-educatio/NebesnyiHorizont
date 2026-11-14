class_name MaterialUpgrader
extends RefCounted

## Map-wide material upgrade pass.
##
## The four frontline maps have hand-built hero detail, but they also load
## dozens of authored GLB landmarks (hospitals, factories, villages, bridges,
## props) and the legacy city map uses its own imported materials.  Upgrading
## those assets one by one was not maintainable, so this pass walks every
## MeshInstance3D on a map and:
##   * classifies each material (concrete / brick / plaster / roof / metal /
##     wood / glass / ground),
##   * attaches the matching PBR albedo / normal / roughness set when a flat
##     placeholder material is found,
##   * keeps authored albedo textures but adds the missing normal/roughness,
##   * adds a high-frequency detail normal + albedo layer and optional
##     heightmap parallax for close-up surface depth,
##   * caches the result per source material so batching still merges meshes.
##
## It deliberately skips vegetation, characters, drones, water and anything
## with a custom ShaderMaterial.  All effects are quality-gated.

const TEX_ROOT := "res://Assets/frontline/"
const HALL_ROOT := "res://Assets/frontline/industrial_hall/"

const ARCH_WEATHER_SHADER := preload("res://shaders/arch_weathering.gdshader")
const ARCH_WEATHER_DOUBLE_SHADER := preload("res://shaders/arch_weathering_double.gdshader")

static var _cache: Dictionary = {}
static var _weather_cache: Dictionary = {}
static var _detail_albedo_tex: Texture2D = null
static var _detail_normal_tex: Texture2D = null
static var _height_tex: Texture2D = null

## Texture sets per material family.  Only files that exist are loaded.
const SETS := {
	"concrete": {
		"albedo": TEX_ROOT + "admin_building_concrete_albedo.png",
		"normal": TEX_ROOT + "admin_building_concrete_normal.png",
		"rough": TEX_ROOT + "admin_building_concrete_rough.png",
		"uv": 0.22,
		"roughness": 0.92,
	},
	"brick": {
		"albedo": TEX_ROOT + "village_textures/brick_albedo.png",
		"normal": TEX_ROOT + "village_textures/brick_normal.png",
		"rough": TEX_ROOT + "village_textures/brick_rough.png",
		"uv": 0.26,
		"roughness": 0.92,
	},
	"plaster": {
		"albedo": TEX_ROOT + "village_textures/plaster_albedo.png",
		"normal": TEX_ROOT + "village_textures/plaster_normal.png",
		"rough": TEX_ROOT + "village_textures/plaster_rough.png",
		"uv": 0.22,
		"roughness": 0.94,
	},
	"roof": {
		"albedo": TEX_ROOT + "village_textures/roof_albedo.png",
		"normal": TEX_ROOT + "village_textures/roof_normal.png",
		"rough": TEX_ROOT + "village_textures/roof_rough.png",
		"uv": 0.28,
		"roughness": 0.88,
	},
	"metal": {
		"albedo": TEX_ROOT + "factory_hall_steel_albedo.png",
		"normal": TEX_ROOT + "factory_hall_steel_normal.png",
		"rough": TEX_ROOT + "factory_hall_steel_rough.png",
		"uv": 0.18,
		"roughness": 0.78,
		"metallic": 0.12,
	},
	"rust": {
		"albedo": TEX_ROOT + "factory_hall_rust_albedo.png",
		"normal": TEX_ROOT + "factory_hall_rust_normal.png",
		"rough": TEX_ROOT + "factory_hall_rust_rough.png",
		"uv": 0.24,
		"roughness": 0.84,
		"metallic": 0.08,
	},
	"wood": {
		"albedo": TEX_ROOT + "village_textures/wood_albedo.png",
		"normal": TEX_ROOT + "village_textures/wood_normal.png",
		"rough": TEX_ROOT + "village_textures/wood_rough.png",
		"uv": 0.34,
		"roughness": 0.86,
	},
	"asphalt": {
		"albedo": TEX_ROOT + "admin_building_asphalt_albedo.png",
		"normal": TEX_ROOT + "admin_building_asphalt_normal.png",
		"rough": TEX_ROOT + "admin_building_asphalt_rough.png",
		"uv": 0.18,
		"roughness": 0.94,
	},
	"hall_concrete": {
		"albedo": HALL_ROOT + "concrete_slab_wall_diff.jpg",
		"normal": HALL_ROOT + "concrete_slab_wall_nor_gl.jpg",
		"rough": HALL_ROOT + "concrete_slab_wall_rough.jpg",
		"uv": 0.24,
		"roughness": 0.90,
	},
	"hall_floor": {
		"albedo": HALL_ROOT + "concrete_floor_damaged_01_diff.jpg",
		"normal": HALL_ROOT + "concrete_floor_damaged_01_nor_gl.jpg",
		"rough": HALL_ROOT + "concrete_floor_damaged_01_rough.jpg",
		"uv": 0.20,
		"roughness": 0.88,
	},
	"hall_rust": {
		"albedo": HALL_ROOT + "rusty_metal_02_diff.jpg",
		"normal": HALL_ROOT + "rusty_metal_02_nor_gl.jpg",
		"rough": HALL_ROOT + "rusty_metal_02_rough.jpg",
		"uv": 0.28,
		"roughness": 0.82,
		"metallic": 0.10,
	},
}

const SKIP_WORDS := [
	"leaf", "leaves", "foliage", "tree", "trunk", "grass", "bush", "plant",
	"flower", "reed", "water", "ocean", "river", "soldier", "rifleman",
	"infantry", "drone", "propeller", "rotor", "hud", "ui", "sprite",
	"cloud", "sky", "muzzle", "tracer", "explosion", "smoke", "fire",
	"batchedprops", "batch", "weeds", "pebbles", "rubble", "cropfield",
	"ground", "terrain", "landscape", "floor_plane", "water", "sea",
]


static func upgrade(root: Node3D, biome: String, quality: int = -1) -> void:
	if root == null:
		return
	if quality < 0:
		quality = QualityManager.get_active_level()
	var high := quality == QualityManager.Level.HIGH
	var force_shared := quality == QualityManager.Level.LOW
	var upgraded := 0
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	for node in meshes:
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var names := String(mi.name).to_lower()
		if _skip_name(names):
			continue
		var override := mi.material_override as StandardMaterial3D
		if override != null and override.normal_enabled and override.albedo_texture != null \
				and not force_shared:
			continue
		var surfaces := mi.mesh.get_surface_count()
		for s in range(surfaces):
			var src: Material = mi.get_surface_override_material(s)
			if src == null:
				src = mi.mesh.surface_get_material(s)
			if src == null or src is ShaderMaterial:
				continue
			var sm := src as StandardMaterial3D
			if sm == null:
				continue
			var cat := _classify(sm, names)
			if cat == "":
				continue
			var tex_key := ""
			if sm.albedo_texture != null:
				tex_key = String(sm.albedo_texture.resource_path)
			var key := "%s|%s|%s|%d|%d|%d" % [cat, tex_key,
					sm.albedo_color.to_html(), int(high), int(sm.transparency),
					int(sm.emission_enabled)]
			var out: StandardMaterial3D = _cache.get(key, null)
			if out == null:
				out = _upgrade_one(sm, cat, high)
				_cache[key] = out
			if out != null:
				mi.set_surface_override_material(s, out)
				upgraded += 1
	root.set_meta("gfx_material_upgrades", upgraded)


static func _skip_name(n: String) -> bool:
	for w in SKIP_WORDS:
		if n.contains(String(w)):
			return true
	return false


static func _classify(sm: StandardMaterial3D, names: String) -> String:
	var rn := ""
	if sm.resource_name != "":
		rn = String(sm.resource_name).to_lower()
	var key := rn + " " + names
	if key.contains("glass") or key.contains("window") or key.contains("glazing"):
		return "glass"
	if key.contains("rust"):
		return "rust"
	if key.contains("brick"):
		return "brick"
	if key.contains("plaster") or key.contains("stucco") or key.contains("house"):
		return "plaster"
	if key.contains("roof") or key.contains("tile") or key.contains("shingle"):
		return "roof"
	if key.contains("wood") or key.contains("timber") or key.contains("plank"):
		return "wood"
	if key.contains("steel") or key.contains("metal") or key.contains("iron"):
		return "metal"
	if key.contains("asphalt") or key.contains("road"):
		return "asphalt"
	if key.contains("concrete") or key.contains("cement") or key.contains("wall") \
			or key.contains("facade") or key.contains("block") or key.contains("floor") \
			or key.contains("building") or key.contains("tower") or key.contains("office"):
		return "concrete"
	if sm.albedo_texture != null:
		# Textured assets that did not match a known name: still add detail
		# maps if they are opaque and not emissive.
		if sm.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and not sm.emission_enabled:
			return "concrete"
	return ""


static func _upgrade_one(src: StandardMaterial3D, cat: String, _high: bool) -> StandardMaterial3D:
	var out: StandardMaterial3D = src.duplicate() as StandardMaterial3D
	if cat == "glass":
		out.roughness = minf(out.roughness, 0.18)
		out.metallic = clampf(out.metallic, 0.08, 0.14)
		out.metallic_specular = 0.45
		return out
	# Lightweight PBR tuning only: skip synchronous NoiseTexture2D / detail_enabled
	# cloning and per-mesh triplanar texture loads to prevent shader compilation hangs.
	var conf: Dictionary = SETS.get(cat, SETS["concrete"])
	var is_metal := cat in ["metal", "rust", "hall_rust"]
	out.metallic = clampf(float(conf.get("metallic", 0.0)), 0.0, 0.14 if is_metal else 0.0)
	out.metallic_specular = 0.28 if is_metal else 0.22
	out.roughness = maxf(float(conf.get("roughness", 0.90)), 0.72 if is_metal else 0.85)
	out.detail_enabled = false
	return out


static func _detail_albedo() -> Texture2D:
	if _detail_albedo_tex != null:
		return _detail_albedo_tex
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.22
	noise.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.72, 0.72, 0.72, 1.0))
	ramp.set_color(1, Color(1.0, 1.0, 1.0, 1.0))
	tex.color_ramp = ramp
	_detail_albedo_tex = tex
	return tex


static func _detail_normal() -> Texture2D:
	if _detail_normal_tex != null:
		return _detail_normal_tex
	var p := "res://Assets/textures/terrain/dirt_normal.png"
	if ResourceLoader.exists(p):
		_detail_normal_tex = load(p) as Texture2D
	return _detail_normal_tex


static func _height_texture() -> Texture2D:
	if _height_tex != null:
		return _height_tex
	var p := "res://Assets/textures/terrain/dirt_albedo.png"
	if ResourceLoader.exists(p):
		_height_tex = load(p) as Texture2D
	return _height_tex


## Post-batching architectural weathering pass: swaps concrete, brick and
## plaster StandardMaterial3D surfaces onto a lightweight ShaderMaterial that
## adds bottom ~1.55 m grime/dampness near the ground and subtle panel variation
## without breaking static batching or adding draw calls.
static func apply_arch_weathering(root: Node3D, map_name: String,
		height_tex: Texture2D = null, half_extent: float = 192.0,
		flat_ground_y: float = 0.0, enable_grime: bool = true) -> int:
	if root == null:
		return 0
	var count := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.is_visible_in_tree():
			continue
		if mi.get_meta("no_batch", false):
			continue
		var names := String(mi.name).to_lower()
		var pnames := String(mi.get_parent().name).to_lower() if mi.get_parent() != null else ""
		var combined_names := names + " " + pnames
		if _skip_arch_node(combined_names):
			continue
		var mat_override := mi.material_override
		if mat_override is StandardMaterial3D:
			var sm_ov := mat_override as StandardMaterial3D
			var cat_ov := _classify_arch(sm_ov, combined_names)
			if cat_ov != "":
				var wmat_ov := _get_weather_mat(sm_ov, cat_ov, map_name, height_tex,
						half_extent, flat_ground_y, enable_grime)
				if wmat_ov != null:
					mi.material_override = wmat_ov
					count += 1
					continue
		for s in range(mi.mesh.get_surface_count()):
			var src: Material = mi.get_surface_override_material(s)
			if src == null:
				src = mi.mesh.surface_get_material(s)
			var sm := src as StandardMaterial3D
			if sm == null:
				continue
			var cat := _classify_arch(sm, combined_names)
			if cat == "":
				continue
			var wmat := _get_weather_mat(sm, cat, map_name, height_tex,
					half_extent, flat_ground_y, enable_grime)
			if wmat != null:
				mi.set_surface_override_material(s, wmat)
				count += 1
	root.set_meta("gfx_arch_weathering", count)
	return count


static func _skip_arch_node(names: String) -> bool:
	for w in ["terrain", "horizon", "mountain", "water", "river", "road",
			"crater", "contactshadow", "tree", "leaf", "leaves", "grass",
			"reed", "scrub", "bush", "weed", "tuft", "flower", "rubble",
			"pebble", "debris", "crop", "soldier", "infantry", "drone",
			"rotor", "vehicle", "tank", "apc", "truck", "smoke", "fire",
			"cloud", "sky", "beacon", "ring", "gate", "target",
			"train", "loco", "boxcar", "gondola", "rail"]:
		if names.contains(String(w)):
			return true
	return false


static func _classify_arch(sm: StandardMaterial3D, node_names: String) -> String:
	if sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or sm.emission_enabled:
		return ""
	if sm.metallic > 0.15 or sm.roughness < 0.68:
		return ""
	var tex_p := sm.albedo_texture.resource_path.to_lower() if sm.albedo_texture != null else ""
	var rn := String(sm.resource_name).to_lower()
	var key := tex_p + " " + rn + " " + node_names
	for reject in ["grass", "dirt", "mud", "sand", "asphalt", "road", "roof",
			"tile", "shingle", "wood", "timber", "steel", "metal", "iron",
			"rust", "moss", "glass", "window", "glazing", "floor", "car",
			"truck", "crate", "barrel", "tyre", "tire"]:
		if key.contains(String(reject)):
			return ""
	if tex_p.contains("brick") or rn.contains("brick"):
		return "brick"
	if tex_p.contains("plaster") or tex_p.contains("stucco") or rn.contains("plaster"):
		return "plaster"
	if tex_p.contains("concrete") or tex_p.contains("wall") or tex_p.contains("cement"):
		return "concrete"
	for kw in ["concrete", "cement", "brick", "plaster", "stucco", "facade",
			"wall", "bld", "building", "hall", "hangar", "bunker", "bridge",
			"pillar", "tower", "office", "block", "factory", "annex",
			"station", "terminal", "platform", "silo", "revetment"]:
		if (rn + " " + node_names).contains(String(kw)):
			return "concrete"
	return ""


static func _get_weather_mat(sm: StandardMaterial3D, cat: String, map_name: String,
		height_tex: Texture2D, half_extent: float, flat_ground_y: float,
		enable_grime: bool) -> ShaderMaterial:
	var key := "%d|%s|%s|%d|%.1f" % [sm.get_instance_id(), map_name, cat,
			1 if enable_grime else 0, flat_ground_y]
	if _weather_cache.has(key):
		return _weather_cache[key]
	var sh := ARCH_WEATHER_DOUBLE_SHADER if sm.cull_mode == BaseMaterial3D.CULL_DISABLED \
			else ARCH_WEATHER_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("albedo_color", sm.albedo_color)
	mat.set_shader_parameter("has_albedo_tex", sm.albedo_texture != null)
	if sm.albedo_texture != null:
		mat.set_shader_parameter("albedo_tex", sm.albedo_texture)
	var has_norm := sm.normal_enabled and sm.normal_texture != null
	mat.set_shader_parameter("has_normal_tex", has_norm)
	if has_norm:
		mat.set_shader_parameter("normal_tex", sm.normal_texture)
		mat.set_shader_parameter("normal_strength", sm.normal_scale)
	var has_rough := sm.roughness_texture != null
	mat.set_shader_parameter("has_rough_tex", has_rough)
	if has_rough:
		mat.set_shader_parameter("rough_tex", sm.roughness_texture)
	var has_ao := sm.ao_enabled and sm.ao_texture != null
	mat.set_shader_parameter("has_ao_tex", has_ao)
	if has_ao:
		mat.set_shader_parameter("ao_tex", sm.ao_texture)
		mat.set_shader_parameter("ao_strength", clampf(sm.ao_light_affect, 0.35, 0.85))
	mat.set_shader_parameter("use_triplanar", sm.uv1_triplanar or sm.uv1_world_triplanar)
	mat.set_shader_parameter("use_vertex_color", sm.vertex_color_use_as_albedo)
	mat.set_shader_parameter("uv_scale", maxf(sm.uv1_scale.x, 0.01))
	mat.set_shader_parameter("roughness_base", clampf(sm.roughness, 0.25, 0.98))
	mat.set_shader_parameter("metallic_base", clampf(sm.metallic, 0.0, 0.25))
	mat.set_shader_parameter("specular_base", clampf(sm.metallic_specular, 0.1, 0.6))
	mat.set_shader_parameter("use_heightmap", height_tex != null)
	if height_tex != null:
		mat.set_shader_parameter("terrain_height_tex", height_tex)
	mat.set_shader_parameter("terrain_half_extent", half_extent)
	mat.set_shader_parameter("flat_ground_y", flat_ground_y)
	mat.set_shader_parameter("grime_height", 1.55)

	var grime_col := Color(0.20, 0.18, 0.14)
	var grime_str := 0.44 if cat != "plaster" else 0.36
	var var_str := 0.12 if cat != "plaster" else 0.09
	match map_name:
		"steppe":
			grime_col = Color(0.30, 0.25, 0.17)
			grime_str = 0.44
		"wetlands":
			grime_col = Color(0.14, 0.17, 0.12)
			grime_str = 0.54
		"industrial":
			grime_col = Color(0.15, 0.15, 0.14)
			grime_str = 0.48
		"city", "course":
			grime_col = Color(0.24, 0.23, 0.21)
			grime_str = 0.36
			var_str = 0.09
	if not enable_grime:
		grime_str = 0.0
	mat.set_shader_parameter("grime_color", Vector3(grime_col.r, grime_col.g, grime_col.b))
	mat.set_shader_parameter("grime_strength", grime_str)
	mat.set_shader_parameter("micro_var_strength", var_str)
	_weather_cache[key] = mat
	return mat
