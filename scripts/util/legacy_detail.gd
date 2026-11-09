class_name LegacyDetail
extends RefCounted

## Generic ground-detail scatter for the legacy GLB maps (city / valley).
##
## The four frontline maps use the hand-built WorldDetail pass.  Legacy maps
## are arbitrary imported scenes, so the only safe common denominator is a
## physics-raycast scatter: sample points over the map AABB, find walkable
## ground, and batch a few props/weeds around each hit.  One MultiMesh per prop
## type keeps the cost low.  Runs only when legacy maps are actually loaded.

const PROPS := preload("res://scripts/util/prop_assets.gd")
const FOLIAGE := preload("res://scripts/util/foliage_system.gd")
const GRASS_SHADER := preload("res://Assets/grass_wind.gdshader")


static func scatter(level: Node3D, map_root: Node3D, quality: int = -1) -> void:
	if level == null or map_root == null:
		return
	if quality < 0:
		quality = QualityManager.get_active_level()
	var clusters := 12
	if quality == QualityManager.Level.HIGH:
		clusters = 30
	elif quality == QualityManager.Level.MEDIUM:
		clusters = 18
	elif quality == QualityManager.Level.LOW:
		clusters = 6
	var bounds := _mesh_bounds(map_root)
	if bounds.size.x < 5.0 or bounds.size.z < 5.0:
		return
	var space := level.get_world_3d().direct_space_state
	if space == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 55127
	var spots: Array[Vector3] = []
	var attempts := clusters * 14
	while spots.size() < clusters and attempts > 0:
		attempts -= 1
		var x := rng.randf_range(bounds.position.x, bounds.end.x)
		var z := rng.randf_range(bounds.position.z, bounds.end.z)
		var from := Vector3(x, bounds.end.y + 80.0, z)
		var to := Vector3(x, bounds.position.y - 30.0, z)
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.collision_mask = 1
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var n: Vector3 = hit["normal"]
		if n.y < 0.82:
			continue
		var pos: Vector3 = hit["position"]
		var ok := true
		for other in spots:
			if other.distance_to(pos) < 26.0:
				ok = false
				break
		if not ok:
			continue
		spots.append(pos)
	if spots.is_empty():
		return
	var meshes := PROPS.meshes()
	var mats := StandardMaterial3D.new()
	mats.vertex_color_use_as_albedo = true
	mats.roughness = 0.9
	var by_type := {}
	var names := ["prop_crate", "prop_barrel", "prop_pallet", "prop_tire",
			"prop_ammo", "prop_sandbags", "prop_car_wreck"]
	for spot in spots:
		for i in range(rng.randi_range(2, 5)):
			var name: String = names[rng.randi_range(0, names.size() - 1)]
			if not meshes.has(name):
				continue
			if not by_type.has(name):
				by_type[name] = []
			var off := Vector3(rng.randf_range(-4.0, 4.0), 0.0,
					rng.randf_range(-4.0, 4.0))
			(by_type[name] as Array).append(Transform3D(
					Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(
							Vector3.ONE * rng.randf_range(0.85, 1.15)),
					spot + off))
	# Weeds / grass clusters around the props.
	var grass := FOLIAGE.create_grass_mesh(7, 1.8)
	var gm := ShaderMaterial.new()
	gm.shader = GRASS_SHADER
	gm.set_shader_parameter("grass_base_color", Vector3(0.05, 0.07, 0.025))
	gm.set_shader_parameter("grass_tip_color", Vector3(0.16, 0.18, 0.06))
	gm.set_shader_parameter("wind_strength", 0.14)
	var gx: Array = []
	for spot in spots:
		for i in range(rng.randi_range(2, 6)):
			gx.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU))
					.scaled(Vector3.ONE * rng.randf_range(0.7, 1.5)),
					spot + Vector3(rng.randf_range(-5.0, 5.0), 0.02,
					rng.randf_range(-5.0, 5.0))))
	if not gx.is_empty():
		_multimesh(map_root, "LegacyWeeds", grass, gm, gx, false, 130.0)
	var idx := 0
	for name in by_type.keys():
		var mesh: Mesh = meshes.get(name, null)
		if mesh == null:
			continue
		var xf: Array = by_type[name]
		if xf.is_empty():
			continue
		_multimesh(map_root, "LegacyProp%d" % idx, mesh, mats, xf, false, 260.0)
		idx += 1
	_building_trims(map_root, quality)
	print("[LegacyDetail] scattered ", spots.size(), " clusters into ",
			idx + 1, " batches")


## Add roof-edge trim and a foundation plinth to every large building mesh on
## a legacy map.  This is one MultiMesh for all buildings, so the whole city
## gets a layered silhouette for two draw calls.
static func _building_trims(root: Node3D, quality: int) -> void:
	if quality < QualityManager.Level.MEDIUM:
		return
	var xfs: Array = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var n := String(mi.name).to_lower()
		if n.contains("ground") or n.contains("terrain") or n.contains("road") \
				or n.contains("tree") or n.contains("leaf") or n.contains("water"):
			continue
		var sm := mi.mesh.surface_get_material(0) as StandardMaterial3D
		if sm != null and sm.albedo_texture != null:
			var tp := String(sm.albedo_texture.resource_path).to_lower()
			if tp.contains("leaf") or tp.contains("tree") or tp.contains("bark") \
					or tp.contains("grass") or tp.contains("pine") or tp.contains("oak"):
				continue
		var box := mi.global_transform * mi.get_aabb()
		if box.size.y < 4.5 or box.size.x < 4.0 or box.size.z < 4.0:
			continue
		if box.size.x > 260.0 or box.size.z > 260.0:
			continue
		var cx := (box.position.x + box.end.x) * 0.5
		var cz := (box.position.z + box.end.z) * 0.5
		var yt := box.end.y - 0.15
		var yb := box.position.y + 0.30
		var sx := box.size.x
		var sz := box.size.z
		# Roof trim.
		for edge in [
			[Vector3(cx, yt, box.position.z), Vector3(sx + 0.4, 0.28, 0.28)],
			[Vector3(cx, yt, box.end.z), Vector3(sx + 0.4, 0.28, 0.28)],
			[Vector3(box.position.x, yt, cz), Vector3(0.28, 0.28, sz + 0.4)],
			[Vector3(box.end.x, yt, cz), Vector3(0.28, 0.28, sz + 0.4)],
		]:
			xfs.append(Transform3D(Basis().scaled(edge[1] as Vector3), edge[0] as Vector3))
		# Foundation plinth.
		for edge in [
			[Vector3(cx, yb, box.position.z), Vector3(sx + 0.5, 0.55, 0.35)],
			[Vector3(cx, yb, box.end.z), Vector3(sx + 0.5, 0.55, 0.35)],
			[Vector3(box.position.x, yb, cz), Vector3(0.35, 0.55, sz + 0.5)],
			[Vector3(box.end.x, yb, cz), Vector3(0.35, 0.55, sz + 0.5)],
		]:
			xfs.append(Transform3D(Basis().scaled(edge[1] as Vector3), edge[0] as Vector3))
	if xfs.is_empty():
		return
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.54, 0.53, 0.50)
	mat.roughness = 0.88
	var albedo := "res://Assets/frontline/admin_building_concrete_albedo.png"
	if ResourceLoader.exists(albedo):
		mat.albedo_texture = load(albedo) as Texture2D
		mat.uv1_triplanar = true
		mat.uv1_scale = Vector3.ONE * 0.35
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in range(xfs.size()):
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "LegacyBuildingTrim"
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 700.0
	mmi.visibility_range_end_margin = 60.0
	root.add_child(mmi)


static func _multimesh(parent: Node3D, name: String, mesh: Mesh, mat: Material,
		xfs: Array, shadows: bool, range_end: float) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in range(xfs.size()):
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = name
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = range_end
	mmi.visibility_range_end_margin = minf(30.0, range_end * 0.15)
	parent.add_child(mmi)


static func _mesh_bounds(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var low := String(mi.name).to_lower()
		if low.contains("sky") or low.contains("cloud") or low.contains("horizon"):
			continue
		var box := mi.global_transform * mi.get_aabb()
		if box.size.x > 1800.0 or box.size.z > 1800.0:
			continue
		if first:
			out = box
			first = false
		else:
			out = out.merge(box)
	return out
