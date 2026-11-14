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

static var _cache: Dictionary = {}
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
		"roughness": 0.55,
		"metallic": 0.55,
	},
	"rust": {
		"albedo": TEX_ROOT + "factory_hall_rust_albedo.png",
		"normal": TEX_ROOT + "factory_hall_rust_normal.png",
		"rough": TEX_ROOT + "factory_hall_rust_rough.png",
		"uv": 0.24,
		"roughness": 0.78,
		"metallic": 0.25,
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
		"roughness": 0.74,
		"metallic": 0.30,
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
		out.metallic = maxf(out.metallic, 0.20)
		out.metallic_specular = 0.75
		return out
	# Lightweight PBR tuning only: skip synchronous NoiseTexture2D / detail_enabled
	# cloning and per-mesh triplanar texture loads to prevent shader compilation hangs.
	var conf: Dictionary = SETS.get(cat, SETS["concrete"])
	out.roughness = float(conf.get("roughness", 0.90))
	out.metallic = float(conf.get("metallic", 0.0))
	out.metallic_specular = 0.42
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
