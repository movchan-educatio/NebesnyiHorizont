class_name VegetationAssets
extends RefCounted

## Loads the Blender-authored vegetation library and hands out ready-to-use
## meshes/materials for the MultiMesh systems:
##   * a 3D grass clump and a lighter field tuft (grass wind shader);
##   * five full tree meshes (trunk + leaf cards) with bark and wind materials.
##
## All tree meshes keep a single surface each, so one MultiMesh stays one draw
## call; the leaf surface uses the alpha-cut wind shader, the trunk surface the
## bark PBR shader.

const LIB_PATH := "res://Assets/frontline/vegetation/vegetation_library.glb"
const LEAF_ATLAS := preload("res://Assets/frontline/vegetation/leaf_atlas.png")
const PINE_ATLAS := preload("res://Assets/frontline/vegetation/pine_atlas.png")
const BARK_ALBEDO := preload("res://Assets/frontline/vegetation/bark_albedo.png")
const TREE_SHADER := preload("res://Assets/tree_wind.gdshader")
const BARK_SHADER := preload("res://Assets/bark_pbr.gdshader")

static var _ready := false
static var _grass_mesh: ArrayMesh = null
static var _tuft_mesh: ArrayMesh = null
# { "name": String, "trunk": Mesh, "leaves": Mesh, "pine": bool, "height": float }
static var _trees: Array[Dictionary] = []


static func available() -> bool:
	return ResourceLoader.exists(LIB_PATH)


static func grass_mesh() -> ArrayMesh:
	_ensure()
	return _grass_mesh


static func tuft_mesh() -> ArrayMesh:
	_ensure()
	return _tuft_mesh


## All tree variants.  `trunk` and `leaves` are single-surface meshes whose
## materials are already set; the leaves mesh is the alpha-cut wind surface.
static func trees() -> Array[Dictionary]:
	_ensure()
	return _trees


static func bark_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = BARK_SHADER
	mat.set_shader_parameter("albedo_tex", BARK_ALBEDO)
	mat.set_shader_parameter("roughness", 0.92)
	return mat


## Leaf wind material for a Blender card mesh.  `pine` picks the needle atlas
## and a lighter crown AO; `detail` enables the cinematic leaf shading.
static func leaf_material(pine: bool, tint: Color = Color.WHITE,
		detail: bool = false) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = TREE_SHADER
	mat.set_shader_parameter("leaf_atlas", PINE_ATLAS if pine else LEAF_ATLAS)
	mat.set_shader_parameter("use_atlas", true)
	mat.set_shader_parameter("use_vertex_sway", true)
	mat.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	mat.set_shader_parameter("sway", 0.055)
	mat.set_shader_parameter("gust", 0.026)
	mat.set_shader_parameter("speed", 1.05)
	mat.set_shader_parameter("mottle_strength", 0.28)
	mat.set_shader_parameter("crown_ao", 0.40 if pine else 0.60)
	mat.set_shader_parameter("backlight_strength", 0.32 if pine else 0.38)
	mat.set_shader_parameter("leaf_detail", 0.34 if detail else 0.20)
	return mat


static func _ensure() -> void:
	if _ready:
		return
	_ready = true
	if not available():
		push_warning("[VegetationAssets] missing " + LIB_PATH)
		return
	var packed := load(LIB_PATH) as PackedScene
	if packed == null:
		push_warning("[VegetationAssets] failed to load " + LIB_PATH)
		return
	var scene := packed.instantiate()
	_grass_mesh = _extract(scene, "grass_clump")
	_tuft_mesh = _extract(scene, "grass_tuft")
	for spec in [["oak_a", false], ["oak_b", false], ["oak_c", false],
			["pine_a", true], ["pine_b", true]]:
		var root := scene.find_child(spec[0], true, false) as Node3D
		if root == null:
			continue
		var trunk_mesh: ArrayMesh = null
		var leaf_mesh: ArrayMesh = null
		var trunk_uv_scale := Vector2(1.0, 1.0)
		for child in root.get_children():
			var mi := child as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			var child_name := String(child.name).to_lower()
			if child_name.contains("trunk"):
				trunk_mesh = _copy_surface(mi.mesh)
			elif child_name.contains("leav") or child_name.contains("needle"):
				leaf_mesh = _copy_surface(mi.mesh)
		if trunk_mesh == null or leaf_mesh == null:
			continue
		var bark := bark_material()
		trunk_mesh.surface_set_material(0, bark)
		var leaf := leaf_material(spec[1])
		leaf_mesh.surface_set_material(0, leaf)
		if OS.has_environment("VEG_DEBUG"):
			print("[VegetationAssets] ", spec[0],
					" trunk verts=", trunk_mesh.surface_get_array_len(0),
					" leaf verts=", leaf_mesh.surface_get_array_len(0),
					" leaf has color=", leaf_mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] != null)
		_trees.append({
			"name": spec[0],
			"trunk": trunk_mesh,
			"leaves": leaf_mesh,
			"pine": spec[1],
		})
	scene.free()


## Copy one mesh surface into a fresh single-surface ArrayMesh (the GLB meshes
## are shared resources; tree placement never mutates them, but keeping our
## own copy makes material assignment safe for the MultiMesh batching).
static func _copy_surface(src: Mesh) -> ArrayMesh:
	var out := ArrayMesh.new()
	if src == null:
		return out
	var arrays: Array = src.surface_get_arrays(0)
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


static func _extract(scene: Node, node_name: String) -> ArrayMesh:
	var mi := scene.find_child(node_name, true, false) as MeshInstance3D
	if mi == null or mi.mesh == null:
		return null
	return _copy_surface(mi.mesh)
