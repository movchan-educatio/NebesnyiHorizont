class_name FoliageSystem
extends Node3D

## High-performance procedural 3D grass and steppe foliage using MultiMeshInstance3D.
## Renders natural multi-blade 3D grass clumps with wind sway and distance fading.

const GRASS_SHADER = preload("res://Assets/grass_wind.gdshader")
const TREE_WIND_SHADER = preload("res://Assets/tree_wind.gdshader")
const VEGETATION = preload("res://scripts/util/vegetation_assets.gd")


## Canopy/bush material with the wind sway shader.  `tint` matches the old
## StandardMaterial albedo so existing instance colours keep their contrast.
static func make_wind_material(tint: Color = Color.WHITE) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = TREE_WIND_SHADER
	mat.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	mat.set_shader_parameter("leaf_detail", 0.22)
	mat.set_shader_parameter("backlight_strength", 0.34)
	mat.set_shader_parameter("crown_ao", 0.58)
	return mat


## A sphere with its vertices pushed along noise: the silhouette stops looking
## like a billiard ball and gains the ragged outline of a real crown, while the
## vertex count stays exactly the same as a plain SphereMesh.
static func make_canopy_mesh(segments: int = 7, rings: int = 4,
		lump: float = 0.16, radius: float = 1.0,
		height: float = 2.0) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = height
	sphere.radial_segments = segments
	sphere.rings = rings
	var arrays := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in range(verts.size()):
		var v := verts[i]
		var d := v.normalized()
		var n := sin(d.x * 4.7 + d.y * 2.9) * 0.55 \
				+ sin(d.z * 5.9 - d.x * 3.7) * 0.33 \
				+ sin((d.x + d.z) * 9.3) * 0.12
		# Scale the ORIGINAL vertex, not the unit direction: the crown keeps
		# its ellipsoid proportions instead of collapsing back to a ball.
		verts[i] = v * (1.0 + n * lump)
	arrays[Mesh.ARRAY_VERTEX] = verts
	return _rebuild_with_normals(arrays)


## Spruce / pine cone with a jagged branch silhouette instead of a smooth cone.
static func make_cone_mesh(bottom_radius: float = 1.0, height: float = 1.0,
		segments: int = 8, lump: float = 0.20) -> ArrayMesh:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0
	cyl.bottom_radius = bottom_radius
	cyl.height = height
	cyl.radial_segments = segments
	cyl.rings = 2
	var arrays := cyl.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in range(verts.size()):
		var v := verts[i]
		if Vector2(v.x, v.z).length() > 0.001:
			var ang := atan2(v.z, v.x)
			var j := sin(ang * 5.0 + v.y * 3.0) * 0.6 + sin(ang * 11.0) * 0.4
			var k := 1.0 + j * lump
			verts[i] = Vector3(v.x * k, v.y, v.z * k)
			# Droop the bottom rim slightly so the underside is not a perfectly
			# flat disc, and the tier reads as hanging branches.
			if v.y < -height * 0.45:
				verts[i] = Vector3(verts[i].x,
						verts[i].y - height * (0.03 + 0.035 * absf(j)),
						verts[i].z)
	arrays[Mesh.ARRAY_VERTEX] = verts
	# Keep the authored cylinder normals.  SurfaceTool.generate_normals()
	# averaged the big flat underside into the side normals, which lit the
	# bottom cap like a bright green plate and made the tiers look like paper.
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _rebuild_with_normals(arrays: Array) -> ArrayMesh:
	var tmp := ArrayMesh.new()
	tmp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var st := SurfaceTool.new()
	st.create_from(tmp, 0)
	st.generate_normals()
	return st.commit()

static func create_grass_mesh(blade_count: int = 14, width_scale: float = 1.0) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	for b in range(blade_count):
		var angle := rng.randf() * TAU
		var dist := rng.randf_range(0.02, 0.30)
		var bx := cos(angle) * dist
		var bz := sin(angle) * dist
		var blade_yaw := rng.randf() * TAU
		# Real grass blades are 5-10 mm wide, but at FPV altitude plus FSR they
		# aliased into dark wire below ~9 mm; 9-18 mm keeps the blade silhouette
		# while staying far from the old agave-leaf look.
		var w := rng.randf_range(0.009, 0.018) * width_scale
		var h := rng.randf_range(0.18, 0.40)
		var lean := rng.randf_range(0.04, 0.14)

		var right := Vector3(cos(blade_yaw), 0.0, sin(blade_yaw)) * w
		var forward := Vector3(-sin(blade_yaw), 0.0, cos(blade_yaw)) * lean
		var root := Vector3(bx, -0.02, bz)
		var mid := root + Vector3(0.0, h * 0.55, 0.0) + forward * 0.45
		var tip := root + Vector3(0.0, h, 0.0) + forward

		var v0 := vertices.size()
		vertices.append(root - right)
		vertices.append(root + right)
		vertices.append(mid - right * 0.55)
		vertices.append(mid + right * 0.55)
		vertices.append(tip)

		for _k in range(5):
			normals.append(Vector3(0.0, 1.0, 0.0))

		uvs.append(Vector2(0.0, 1.0))
		uvs.append(Vector2(1.0, 1.0))
		uvs.append(Vector2(0.2, 0.45))
		uvs.append(Vector2(0.8, 0.45))
		uvs.append(Vector2(0.5, 0.0))

		indices.append_array([
			v0, v0 + 1, v0 + 3,
			v0, v0 + 3, v0 + 2,
			v0 + 2, v0 + 3, v0 + 4
		])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func spawn_dense_grass(parent: Node, center: Vector3 = Vector3.ZERO, radius: float = 110.0, count: int = 3500,
		base_color: Color = Color(0.16, 0.20, 0.09), tip_color: Color = Color(0.28, 0.33, 0.15),
		map_name: String = "", clear_center: Vector3 = Vector3.ZERO,
		clear_radius: float = 0.0) -> MultiMeshInstance3D:
	if parent == null:
		return null

	var near := parent.get_node_or_null("DenseGrassFoliage") as MultiMeshInstance3D
	if near == null:
		near = _make_grass_node(parent, "DenseGrassFoliage",
				VEGETATION.grass_mesh(), true)
	var far := parent.get_node_or_null("DenseGrassFar") as MultiMeshInstance3D
	if far == null:
		far = _make_grass_node(parent, "DenseGrassFar",
				VEGETATION.tuft_mesh(), false)

	# Palette is per-map: dry steppe straw vs. green marsh grass.  Both nodes
	# share one material instance so the palette updates once.
	var grass_mat := near.material_override as ShaderMaterial
	if grass_mat == null:
		grass_mat = ShaderMaterial.new()
		grass_mat.shader = GRASS_SHADER
		near.material_override = grass_mat
	if far != null:
		far.material_override = grass_mat
	grass_mat.set_shader_parameter("grass_base_color",
			Vector3(base_color.r, base_color.g, base_color.b))
	grass_mat.set_shader_parameter("grass_tip_color",
			Vector3(tip_color.r, tip_color.g, tip_color.b))

	var rng := RandomNumberGenerator.new()
	rng.seed = 42

	var base_y := center.y
	var space: PhysicsDirectSpaceState3D = null
	if parent is Node3D and (parent as Node3D).is_inside_tree():
		var w3d := (parent as Node3D).get_world_3d()
		if w3d != null:
			space = w3d.direct_space_state
	# Procedural frontline maps have an analytic height field.  Sampling it is
	# much faster than a physics raycast per blade and, crucially, never lands
	# grass on a building roof.
	var terrain = null
	if not map_name.is_empty():
		terrain = load("res://scripts/util/frontline_terrain.gd")

	# Split the carpet into a near band with the full 14-blade clump and a far
	# band with the cheaper 6-blade tuft.  The far band is only a few pixels
	# tall at FPV speed, but it used to cost as many triangles as the near one.
	var near_xf: Array = []
	var far_xf: Array = []
	var near_radius := radius * 0.55
	for i in range(count):
		var r := sqrt(rng.randf()) * radius
		var theta := rng.randf() * 2.0 * PI
		var px := center.x + r * cos(theta)
		var pz := center.z + r * sin(theta)
		var py := base_y
		if clear_radius > 0.01 \
				and Vector2(px, pz).distance_to(Vector2(clear_center.x, clear_center.z)) < clear_radius:
			continue

		if terrain != null:
			var th := float(terrain.height_at(map_name, px, pz))
			if th < float(terrain.water_level(map_name)) + 0.12:
				continue
			py = th + 0.02
		elif space != null:
			var query := PhysicsRayQueryParameters3D.create(Vector3(px, 250.0, pz), Vector3(px, -150.0, pz))
			query.collision_mask = 1
			var hit := space.intersect_ray(query)
			if not hit.is_empty():
				py = (hit["position"] as Vector3).y

		var s := rng.randf_range(0.75, 1.35)
		var rot_y := rng.randf() * 2.0 * PI

		var xf := Transform3D()
		xf = xf.rotated(Vector3.UP, rot_y)
		xf = xf.scaled(Vector3(s, s, s))
		xf.origin = Vector3(px, py, pz)
		if r <= near_radius:
			near_xf.append(xf)
		else:
			far_xf.append(xf)

	_apply_instances(near, near_xf)
	if far != null:
		_apply_instances(far, far_xf)
	return near


## Broad meadow carpet: one MultiMesh with grass clustered around a grid of
## centres.  The old dense-grass node only covered the immediate spawn/yard;
## this puts real grass across the whole map at a tiny draw-call cost.
static func spawn_meadow_grass(parent: Node, centers: Array, count_per_center: int,
		radius: float, base_color: Color, tip_color: Color,
		map_name: String = "") -> MultiMeshInstance3D:
	if parent == null or centers.is_empty():
		return null
	var node := MultiMeshInstance3D.new()
	node.name = "MeadowGrass"
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh: ArrayMesh = VEGETATION.tuft_mesh()
	if mesh == null:
		mesh = create_grass_mesh(6, 1.2)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	node.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = GRASS_SHADER
	mat.set_shader_parameter("grass_base_color",
			Vector3(base_color.r, base_color.g, base_color.b))
	mat.set_shader_parameter("grass_tip_color",
			Vector3(tip_color.r, tip_color.g, tip_color.b))
	mat.set_shader_parameter("wind_strength", 0.14)
	node.material_override = mat
	parent.add_child(node)
	var terrain = null
	if not map_name.is_empty():
		terrain = load("res://scripts/util/frontline_terrain.gd")
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(map_name) + 8081
	var xfs: Array = []
	for center in centers:
		var c: Vector3 = center
		for i in range(count_per_center):
			var a := rng.randf_range(0.0, TAU)
			var r := sqrt(rng.randf()) * radius
			var px := c.x + cos(a) * r
			var pz := c.z + sin(a) * r
			var py := c.y
			if terrain != null:
				py = float(terrain.height_at(map_name, px, pz))
				if py < float(terrain.water_level(map_name)) + 0.12:
					continue
			if terrain == null:
				var space := (parent as Node3D).get_world_3d().direct_space_state
				if space != null:
					var q := PhysicsRayQueryParameters3D.create(
							Vector3(px, c.y + 200.0, pz), Vector3(px, c.y - 100.0, pz))
					q.collision_mask = 1
					var hit := space.intersect_ray(q)
					if not hit.is_empty():
						py = (hit["position"] as Vector3).y
			var s := rng.randf_range(0.8, 1.6)
			xfs.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU))
					.scaled(Vector3(s, rng.randf_range(0.8, 1.5), s)),
					Vector3(px, py + 0.02, pz)))
	mm.instance_count = xfs.size()
	for i in range(xfs.size()):
		mm.set_instance_transform(i, xfs[i])
	node.visibility_range_end = radius + 95.0
	node.visibility_range_end_margin = 18.0
	node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	return node


static func _make_grass_node(parent: Node, node_name: String, mesh: ArrayMesh,
		near: bool) -> MultiMeshInstance3D:
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = 95.0
	node.visibility_range_end_margin = 6.0
	node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	if mesh != null:
		mm.mesh = mesh
	else:
		var blades := 14 if near else 6
		mm.mesh = create_grass_mesh(blades, 1.0 if near else 1.6)
	node.multimesh = mm
	parent.add_child(node)
	return node


static func _apply_instances(node: MultiMeshInstance3D, transforms: Array) -> void:
	var mm := node.multimesh
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
