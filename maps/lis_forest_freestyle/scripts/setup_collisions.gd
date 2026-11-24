extends Node3D
## Builds collision from the real placed meshes. No proxy pile at world origin,
## no invisible walls between objects. Foliage uses alpha scissor (no shimmer).

const LisRingsScript = preload("res://maps/lis_forest_freestyle/scripts/lis_freestyle_rings.gd")

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
	_fix_foliage_materials(self)
	_tune_materials(self)
	_tune_sawmill_materials(self)
	var existing := _count_bodies(self)
	_walk(self)
	print("[LIS] collisions: %d prebuilt (-colonly) + %d runtime, foliage alpha-scissor" % [existing, bodies_created])

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


## Sawmill-only material upgrade.  The GLB structure materials are shared with
## every bridge/tower/props kit on the map, so clone the three surface materials
## and override them ONLY on z02_sawmill_* meshes.  All textures already ship
## with the map; no new assets, meshes or draw calls.
func _tune_sawmill_materials(node: Node) -> void:
	var overrides := {}
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.name.to_lower().contains("sawmill"):
			continue
		for i in range(m.mesh.get_surface_count()):
			var mat := m.mesh.surface_get_material(i)
			if not (mat is StandardMaterial3D):
				continue
			var src := mat as StandardMaterial3D
			var nm := src.resource_name.to_lower()
			if nm != "mat_concrete" and nm != "mat_wood" and nm != "mat_metal":
				continue
			if not overrides.has(nm):
				var sm := src.duplicate() as StandardMaterial3D
				match nm:
					"mat_concrete":
						sm.albedo_texture = _stex("res://maps/lis_forest_freestyle/meshes/freestyle_protos_brick_moss_001_diff.jpg")
						sm.normal_texture = _stex("res://maps/lis_forest_freestyle/meshes/freestyle_protos_brick_moss_001_nor_gl.jpg")
						sm.roughness_texture = _stex("res://maps/lis_forest_freestyle/meshes/freestyle_protos_brick_moss_001_arm.jpg")
						sm.metallic = 0.0
						sm.roughness = 0.95
						sm.uv1_scale = Vector3(0.22, 0.22, 0.22)
					"mat_wood":
						sm.albedo_texture = _stex("res://maps/lis_forest_freestyle/meshes/proto_modular_wooden_pier_modular_wooden_pier_planks_diff_1k.jpg")
						sm.normal_texture = _stex("res://maps/lis_forest_freestyle/meshes/proto_modular_wooden_pier_modular_wooden_pier_planks_nor_gl_1k.jpg")
						sm.roughness_texture = _stex("res://maps/lis_forest_freestyle/meshes/proto_modular_wooden_pier_modular_wooden_pier_planks_arm_1k.jpg")
						sm.metallic = 0.0
						sm.roughness = 0.82
						sm.uv1_scale = Vector3(0.35, 0.35, 0.35)
					"mat_metal":
						sm.metallic = 0.35
						sm.roughness = 0.58
						sm.albedo_color = Color(0.95, 0.96, 1.0, 1.0)
				overrides[nm] = sm
				print("[LIS] sawmill material upgraded: ", nm)
			m.set_surface_override_material(i, overrides[nm])


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
