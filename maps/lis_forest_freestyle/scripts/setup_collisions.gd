extends Node3D
## Builds collision from the real placed meshes. No proxy pile at world origin,
## no invisible walls between objects. Foliage uses alpha scissor (no shimmer).

const LisRingsScript = preload("res://maps/lis_forest_freestyle/scripts/lis_freestyle_rings.gd")
const TERRAIN_SHADER := preload("res://maps/lis_forest_freestyle/shaders/lis_terrain.gdshader")
const RIVER_SHADER := preload("res://maps/lis_forest_freestyle/shaders/lis_river.gdshader")

var bodies_created: int = 0
var _built: bool = false

## Existing authored textures, shared by every structure (GLB materials are
## global resources).  Loaded once; no new textures or extra draw calls.
static var _struct_textures := {}


static func _stex(path: String) -> Texture2D:
	if not _struct_textures.has(path):
		_struct_textures[path] = load(path) as Texture2D
	return _struct_textures[path] as Texture2D

func _ready() -> void:
	call_deferred("_build")

func _build() -> void:
	if _built:
		return
	_built = true
	var gates_node := LisRingsScript.build_markers(self)
	var scatter_node := get_node_or_null("ScatterMultiMesh") as Node3D
	LisRingsScript.clear_scatter_near_gates(scatter_node, gates_node, 8.5)
	_hide_kit_prototypes()
	_batch_bank_rocks()
	_apply_terrain_and_river_shaders()
	_fix_foliage_materials(self)
	_tune_materials(self)
	_upgrade_structure_materials(self)
	_optimize_freestyle_lods()
	var existing := _count_bodies(self)
	_walk(self)
	print("[LIS] collisions: %d prebuilt (-colonly) + %d runtime, foliage alpha-scissor" % [existing, bodies_created])


func _hide_kit_prototypes() -> void:
	var fg := get_node_or_null("FreestyleGeometry")
	if fg == null:
		return
	var hidden := 0
	for ch in fg.get_children():
		if String(ch.name).begins_with("kit_"):
			if ch is Node3D:
				(ch as Node3D).visible = false
			ch.queue_free()
			hidden += 1
	print("[LIS] removed %d unused kit_* prototypes at origin" % hidden)


func _batch_bank_rocks() -> void:
	var terrain := get_node_or_null("Terrain") as Node3D
	if terrain == null:
		return
	var rocks: Array[MeshInstance3D] = []
	for ch in terrain.get_children():
		if ch is MeshInstance3D and String(ch.name).begins_with("bank_rock_"):
			rocks.append(ch as MeshInstance3D)
	if rocks.is_empty():
		return
	var sample_mesh: Mesh = rocks[0].mesh
	if sample_mesh == null:
		return
	var existing := terrain.get_node_or_null("BankRocksBatched") as MultiMeshInstance3D
	if existing != null:
		return
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "BankRocksBatched"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = sample_mesh
	mm.instance_count = rocks.size()
	var inv_t := terrain.global_transform.affine_inverse()
	for i in range(rocks.size()):
		var r := rocks[i]
		var xf := inv_t * r.global_transform if r.is_inside_tree() else r.transform
		mm.set_instance_transform(i, xf)
		r.visible = false
		r.queue_free()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 260.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	var rmat := StandardMaterial3D.new()
	rmat.resource_name = "rock_09"
	rmat.albedo_texture = _stex("res://maps/lis_forest_freestyle/meshes/terrain_rock_09_diff_1k.jpg")
	rmat.normal_enabled = true
	rmat.normal_texture = _stex("res://maps/lis_forest_freestyle/meshes/terrain_rock_09_nor_gl_1k.jpg")
	rmat.roughness_texture = _stex("res://maps/lis_forest_freestyle/meshes/terrain_rock_09_arm_1k.jpg")
	rmat.roughness_texture_channel = StandardMaterial3D.TEXTURE_CHANNEL_GREEN
	rmat.albedo_color = Color(0.68, 0.66, 0.58, 1.0)
	rmat.roughness = 0.88
	rmat.metallic = 0.0
	mmi.material_override = rmat
	terrain.add_child(mmi)
	print("[LIS] batched %d bank_rock_* nodes into BankRocksBatched (1 draw call)" % rocks.size())


func _apply_terrain_and_river_shaders() -> void:
	var terrain := get_node_or_null("Terrain")
	if terrain == null:
		return
	var t_mat := ShaderMaterial.new()
	t_mat.shader = TERRAIN_SHADER
	t_mat.set_shader_parameter("tex_floor", _stex("res://maps/lis_forest_freestyle/meshes/terrain_forest_ground_04_diff.jpg"))
	t_mat.set_shader_parameter("tex_moss", _stex("res://maps/lis_forest_freestyle/meshes/terrain_forest_ground_05_diff.jpg"))
	t_mat.set_shader_parameter("tex_cliff", _stex("res://maps/lis_forest_freestyle/meshes/structures_cliff_side_diff.jpg"))
	for tname in ["terrain_playable", "terrain_horizon", "terrain_playable_001"]:
		var node := terrain.find_child(tname, true, false) as MeshInstance3D
		if node != null:
			node.material_override = t_mat
	var rw := terrain.find_child("river_water", true, false) as MeshInstance3D
	if rw != null:
		var r_mat := ShaderMaterial.new()
		r_mat.shader = RIVER_SHADER
		r_mat.set_shader_parameter("wave_norm", _stex("res://maps/lis_forest_freestyle/meshes/terrain_rock_09_nor_gl_1k.jpg"))
		rw.material_override = r_mat
		rw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rf := terrain.find_child("river_foam", true, false) as MeshInstance3D
	if rf != null:
		rf.visible = false
	var zfp := terrain.find_child("zone_flow_paths", true, false) as MeshInstance3D
	if zfp != null:
		var zmat := StandardMaterial3D.new()
		zmat.resource_name = "mat_flow_path"
		zmat.albedo_texture = _stex("res://maps/lis_forest_freestyle/meshes/terrain_forest_ground_04_diff.jpg")
		zmat.albedo_color = Color(0.48, 0.56, 0.36, 1.0)
		zmat.roughness = 0.96
		zmat.metallic = 0.0
		zmat.uv1_triplanar = true
		zmat.uv1_scale = Vector3(0.08, 0.08, 0.08)
		zfp.material_override = zmat
		zfp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _optimize_freestyle_lods() -> void:
	var fg := get_node_or_null("FreestyleGeometry")
	if fg == null:
		return
	for ch in fg.find_children("FS_*_geo", "MeshInstance3D", true, false):
		var mi := ch as MeshInstance3D
		var nm := String(mi.name)
		mi.visibility_range_end = 320.0 if nm.contains("DIVE") else 240.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		if nm.contains("SLALOM") or nm.contains("GAP"):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _count_bodies(node: Node) -> int:
	var n: int = 0
	if node is StaticBody3D:
		n += 1
	for c in node.get_children():
		n += _count_bodies(c)
	return n

func _fix_foliage_materials(node: Node) -> void:
	if node is MeshInstance3D:
		for i in range(node.mesh.get_surface_count() if node.mesh else 0):
			var m: Material = node.mesh.surface_get_material(i)
			if m is BaseMaterial3D:
				var nm: String = m.resource_name.to_lower()
				if nm.contains("needle") or nm.contains("fern") or nm.contains("shrub") \
						or nm.contains("grass") or nm.contains("leaf") or nm.contains("foliage"):
					m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
					m.alpha_scissor_threshold = 0.5
	for c in node.get_children():
		_fix_foliage_materials(c)


## The authored GLB materials are neutral white over a brown gravel texture.
## Under the shared BigLevel sun/sky this reads as bright orange sand instead of
## the olive forest floor of the source previews.  Cheap runtime tint: no new
## textures, no per-instance materials, no extra draw calls (mobile budget).
func _tune_materials(node: Node) -> void:
	var seen: Dictionary = {}
	for mi in node.find_children("*", "GeometryInstance3D", true, false):
		var mesh: Mesh = null
		if mi is MeshInstance3D:
			mesh = (mi as MeshInstance3D).mesh
		elif mi is MultiMeshInstance3D:
			var mm := (mi as MultiMeshInstance3D).multimesh
			mesh = mm.mesh if mm != null else null
		if mesh == null:
			continue
		for i in range(mesh.get_surface_count()):
			var mat := mesh.surface_get_material(i)
			if not (mat is StandardMaterial3D) or seen.has(mat.get_instance_id()):
				continue
			var sm := mat as StandardMaterial3D
			var nm := sm.resource_name.to_lower()
			if nm.contains("terrain_blend"):
				sm.albedo_color = Color(0.58, 0.68, 0.46, 1.0)
			elif nm.contains("flow_path"):
				# Authored as metallic=1, which turns the path orange in the sun.
				sm.metallic = 0.0
				sm.albedo_color = Color(0.60, 0.66, 0.44, 1.0)
			elif nm == "rock_09":
				sm.albedo_color = Color(0.70, 0.68, 0.60, 1.0)
			elif nm.contains("needle"):
				sm.albedo_color = Color(0.80, 0.92, 0.78, 1.0)
			else:
				continue
			seen[mat.get_instance_id()] = true
			print("[LIS] tinted material ", sm.resource_name, " -> ", sm.albedo_color)


func _upgrade_structure_materials(node: Node) -> void:
	var structures := node.get_node_or_null("Structures")
	if structures == null:
		structures = node
	var cache := {}
	var upgraded_meshes := 0
	for mi in structures.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or "-colonly" in String(m.name):
			continue
		var m_lower := String(m.name).to_lower()
		var is_foundation := m_lower.contains("foundation")
		for i in range(m.mesh.get_surface_count()):
			var mat := m.mesh.surface_get_material(i)
			if not (mat is StandardMaterial3D):
				continue
			var src := mat as StandardMaterial3D
			var nm := src.resource_name.to_lower()
			if nm != "mat_concrete" and nm != "mat_wood" and nm != "mat_metal" and nm != "mat_stone":
				continue
			var key := nm + ("_found" if is_foundation else "")
			if not cache.has(key):
				var sm := src.duplicate() as StandardMaterial3D
				sm.uv1_triplanar = true
				sm.metallic = 0.0
				match key:
					"mat_concrete_found":
						sm.albedo_texture = _stex("res://maps/lis_forest_freestyle/meshes/freestyle_protos_brick_moss_001_diff.jpg")
						sm.normal_enabled = true
						sm.normal_texture = _stex("res://maps/lis_forest_freestyle/meshes/freestyle_protos_brick_moss_001_nor_gl.jpg")
						sm.roughness_texture = _stex("res://maps/lis_forest_freestyle/meshes/freestyle_protos_brick_moss_001_arm.jpg")
						sm.roughness_texture_channel = StandardMaterial3D.TEXTURE_CHANNEL_GREEN
						sm.albedo_color = Color(0.56, 0.60, 0.52, 1.0)
						sm.roughness = 0.96
						sm.uv1_scale = Vector3(0.20, 0.20, 0.20)
					"mat_concrete":
						sm.albedo_texture = _stex("res://maps/lis_forest_freestyle/meshes/structures_concrete_floor_worn_001_diff.jpg")
						sm.normal_enabled = true
						sm.normal_texture = _stex("res://maps/lis_forest_freestyle/meshes/structures_concrete_floor_worn_001_nor_gl.jpg")
						sm.roughness_texture = _stex("res://maps/lis_forest_freestyle/meshes/structures_concrete_floor_worn_001_arm.jpg")
						sm.roughness_texture_channel = StandardMaterial3D.TEXTURE_CHANNEL_GREEN
						sm.albedo_color = Color(0.76, 0.77, 0.72, 1.0)
						sm.roughness = 0.92
						sm.uv1_scale = Vector3(0.22, 0.22, 0.22)
					"mat_stone", "mat_stone_found":
						sm.albedo_texture = _stex("res://maps/lis_forest_freestyle/meshes/structures_cliff_side_diff.jpg")
						sm.normal_enabled = true
						sm.normal_texture = _stex("res://maps/lis_forest_freestyle/meshes/structures_cliff_side_nor_gl.jpg")
						sm.roughness_texture = _stex("res://maps/lis_forest_freestyle/meshes/structures_cliff_side_arm.jpg")
						sm.roughness_texture_channel = StandardMaterial3D.TEXTURE_CHANNEL_GREEN
						sm.albedo_color = Color(0.70, 0.72, 0.66, 1.0)
						sm.roughness = 0.90
						sm.uv1_scale = Vector3(0.18, 0.18, 0.18)
					"mat_wood", "mat_wood_found":
						sm.albedo_texture = _stex("res://maps/lis_forest_freestyle/meshes/proto_modular_wooden_pier_modular_wooden_pier_planks_diff_1k.jpg")
						sm.normal_enabled = true
						sm.normal_texture = _stex("res://maps/lis_forest_freestyle/meshes/proto_modular_wooden_pier_modular_wooden_pier_planks_nor_gl_1k.jpg")
						sm.roughness_texture = _stex("res://maps/lis_forest_freestyle/meshes/proto_modular_wooden_pier_modular_wooden_pier_planks_arm_1k.jpg")
						sm.roughness_texture_channel = StandardMaterial3D.TEXTURE_CHANNEL_GREEN
						sm.albedo_color = Color(0.84, 0.80, 0.74, 1.0)
						sm.roughness = 0.82
						sm.uv1_scale = Vector3(0.32, 0.32, 0.32)
					"mat_metal", "mat_metal_found":
						sm.albedo_texture = _stex("res://maps/lis_forest_freestyle/meshes/structures_black_painted_planks_diff.jpg")
						sm.normal_enabled = true
						sm.normal_texture = _stex("res://maps/lis_forest_freestyle/meshes/structures_black_painted_planks_nor_gl.jpg")
						sm.metallic = 0.42
						sm.roughness = 0.56
						sm.albedo_color = Color(0.72, 0.76, 0.79, 1.0)
						sm.uv1_scale = Vector3(0.28, 0.28, 0.28)
				cache[key] = sm
			m.set_surface_override_material(i, cache[key])
			upgraded_meshes += 1
	print("[LIS] upgraded %d structure surfaces across %d material variants" % [upgraded_meshes, cache.size()])


func _walk(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var n: String = child.name
			var is_freestyle: bool = n.begins_with("FS_") and n.ends_with("_geo")
			var is_colonly: bool = "-colonly" in n or "-convcolonly" in n
			if (is_freestyle or is_colonly) and child.mesh != null:
				var concave_struct: bool = ("bridge" in n or "trestle" in n or "sawmill" in n \
						or "watchtower" in n or "ruins" in n or "treehouse" in n)
				_make_body(child as MeshInstance3D, is_freestyle or concave_struct)
		_walk(child)

func _make_body(src: MeshInstance3D, use_trimesh: bool) -> void:
	var faces: PackedVector3Array = src.mesh.get_faces()
	if faces.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = src.name.replace("-", "_") + "_body"
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape: Shape3D
	if use_trimesh:
		var tri := ConcavePolygonShape3D.new()
		tri.set_faces(faces)
		shape = tri
	else:
		shape = src.mesh.create_convex_shape(true, false)
	if shape == null:
		return
	cs.shape = shape
	body.add_child(cs)
	body.transform = src.transform
	src.add_sibling(body)
	if not use_trimesh:
		src.visible = false
	bodies_created += 1
