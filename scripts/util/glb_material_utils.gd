class_name GlbMaterialUtils
extends RefCounted

## Generation-time material wrapper for inherited GLB/glTF assets.
##
## Imported assets from the legacy project often carry a flat StandardMaterial3D
## (solid albedo, no normal/roughness/AO) or an unshaded placeholder.  This
## pass upgrades those materials *without replacing authored albedo textures or
## paint colours*:
##   * unshaded placeholders become per-pixel PBR;
##   * known families (concrete, steel, rust, wood, brick, plaster, roof,
##     asphalt) get the matching normal/roughness/AO maps;
##   * carbon/composite/rubber/fabric/leather keep their colours but get a
##     plausible metallic/roughness response;
##   * glass/lens materials keep their authored transparency.
##
## It is shared by the editor post-import hook and the runtime model wrapper, so
## a GLB looks identical in the hangar and in flight even if its .import settings
## were authored before the PBR library existed.

const UPGRADER = preload("res://scripts/util/material_upgrader.gd")
const HALL := "res://Assets/frontline/industrial_hall/"
const AO_PATHS := {
	"concrete": HALL + "concrete_slab_wall_ao.jpg",
	"metal": HALL + "metal_plate_02_ao.jpg",
	"rust": HALL + "rusty_metal_02_ao.jpg",
	"hall_concrete": HALL + "concrete_slab_wall_ao.jpg",
	"hall_rust": HALL + "rusty_metal_02_ao.jpg",
}
const PLACEHOLDER_WORDS := [
	"placeholder", "mat_old", "old_material", "default_material", "material",
	"no_material", "untextured", "flat",
]
const EMISSIVE_WORDS := [
	"led", "nav_", "beacon", "light", "lamp", "screen", "display", "glow",
	"stencil", "warning", "hazard",
]

static var _cache := {}


static func ensure_pbr(root: Node) -> int:
	if root == null:
		return 0
	var changed := 0
	var upgraded_by_source := {}
	var meshes: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		meshes.append(root as MeshInstance3D)
	meshes.append_array(root.find_children("*", "MeshInstance3D", true, false))
	for node in meshes:
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var mesh_name := String(mi.name).to_lower()
		for surface in range(mi.mesh.get_surface_count()):
			var source := mi.get_surface_override_material(surface)
			if source == null:
				source = mi.mesh.surface_get_material(surface)
			if source == null or source is ShaderMaterial:
				continue
			var sm := source as StandardMaterial3D
			if sm == null or sm.has_meta("glb_pbr_upgraded"):
				continue
			var source_id := sm.get_instance_id()
			var target: StandardMaterial3D = upgraded_by_source.get(source_id)
			if target == null:
				target = _upgrade_one(sm, mesh_name)
				upgraded_by_source[source_id] = target
			if target != null and target != sm:
				mi.set_surface_override_material(surface, target)
				changed += 1
	return changed


static func _upgrade_one(src: StandardMaterial3D, mesh_name: String) -> StandardMaterial3D:
	var key := "|".join([String(src.resource_name), mesh_name,
			str(src.albedo_color), str(src.albedo_texture != null),
			src.resource_path])
	if _cache.has(key):
		return _cache[key]
	var category := _classify(src, mesh_name)
	var out := src.duplicate() as StandardMaterial3D
	if out == null:
		return src
	out.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if out.metallic_specular < 0.01:
		out.metallic_specular = 0.5
	var lower := (String(src.resource_name) + " " + mesh_name).to_lower()
	var keep_unshaded := _contains_any(lower, EMISSIVE_WORDS) or src.emission_enabled
	if out.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and not keep_unshaded:
		out.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	var placeholder := _is_placeholder(src, lower)
	if category == "glass" or category == "lens":
		out.roughness = minf(out.roughness, 0.16)
		out.metallic = maxf(out.metallic, 0.15)
	elif category == "composite":
		# Carbon/composite/plastic/rubber/fabric: preserve pigment, just give
		# the surface a physical response instead of a flat unshaded fill.
		if out.roughness >= 0.99:
			out.roughness = 0.62
		if out.metallic <= 0.01 and _contains_any(lower, ["carbon", "metal",
				"alloy", "steel"]):
			out.metallic = 0.35
	elif category == "":
		if placeholder and out.roughness >= 0.99:
			out.roughness = 0.82
	elif category != "":
		var conf: Dictionary = UPGRADER.SETS.get(category, {})
		if not conf.is_empty():
			if placeholder and out.albedo_texture == null:
				var albedo := _load_tex(String(conf.get("albedo", "")))
				if albedo != null:
					out.albedo_texture = albedo
					out.uv1_scale = Vector3.ONE * float(conf.get("uv", 0.24))
					out.uv1_triplanar = true
					out.uv1_triplanar_sharpness = 8.0
			if out.normal_texture == null:
				var normal := _load_tex(String(conf.get("normal", "")))
				if normal != null:
					out.normal_enabled = true
					out.normal_texture = normal
					out.normal_scale = 1.0
			if out.roughness_texture == null:
				var rough := _load_tex(String(conf.get("rough", "")))
				if rough != null:
					out.roughness_texture = rough
			if not out.ao_enabled:
				var ao := _load_tex(String(AO_PATHS.get(category, "")))
				if ao != null:
					out.ao_enabled = true
					out.ao_texture = ao
					out.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
			out.roughness = float(conf.get("roughness", out.roughness))
			out.metallic = maxf(out.metallic, float(conf.get("metallic", 0.0)))
	if out == src:
		return src
	out.set_meta("glb_pbr_upgraded", true)
	_cache[key] = out
	return out


static func _classify(src: StandardMaterial3D, mesh_name: String) -> String:
	var n := (String(src.resource_name) + " " + mesh_name).to_lower()
	if _contains_any(n, ["glass", "lens", "optical", "window", "glazing"]):
		return "lens"
	if _contains_any(n, ["carbon", "composite", "plastic", "rubber", "fabric",
			"leather", "foam", "nylon"]):
		return "composite"
	if n.contains("rust") or n.contains("corroded"):
		return "rust"
	if n.contains("brick"):
		return "brick"
	if n.contains("plaster") or n.contains("stucco") or n.contains("concrete") \
			or n.contains("cement") or n.contains("facade") or n.contains("wall") \
			or n.contains("building"):
		return "concrete"
	if n.contains("roof") or n.contains("tile") or n.contains("shingle"):
		return "roof"
	if n.contains("wood") or n.contains("timber") or n.contains("plank"):
		return "wood"
	if n.contains("asphalt") or n.contains("road"):
		return "asphalt"
	if n.contains("steel") or n.contains("metal") or n.contains("iron") \
			or n.contains("alloy") or n.contains("machined") \
			or n.contains("gun_") or n.contains("duralumin"):
		return "metal"
	return ""


static func _is_placeholder(src: StandardMaterial3D, lower: String) -> bool:
	if _contains_any(lower, PLACEHOLDER_WORDS):
		return true
	if src.albedo_texture == null:
		var c := src.albedo_color
		if c.r >= 0.92 and c.g >= 0.92 and c.b >= 0.92 and src.roughness >= 0.98:
			return true
	return false


static func _load_tex(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


static func _contains_any(text: String, words: Array) -> bool:
	for w in words:
		if text.contains(String(w)):
			return true
	return false
