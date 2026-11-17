class_name FollowGrass
extends MultiMeshInstance3D

## Static whole-map chunked MultiMesh grass with distance-based LOD and density
## falloff. Built once during level setup so grass is visible across the entire
## playable arena from the very first frame without runtime rebuild stalls or
## mid-flight pop-in.

const VEGETATION := preload("res://scripts/util/vegetation_assets.gd")
const GRASS_SHADER := preload("res://Assets/grass_wind.gdshader")
const FT := preload("res://scripts/util/frontline_terrain.gd")

const GRID_SIDE := 4
const ARENA_HALF := 160.0
const CHUNK_SIZE := (ARENA_HALF * 2.0) / float(GRID_SIDE)

var map_name := ""
var radius := 160.0
var count := 0
var base_color := Color(0.08, 0.10, 0.035)
var tip_color := Color(0.24, 0.24, 0.09)
var _built := false
var _building := false
var _clear_center := Vector3.ZERO
var _clear_radius := 0.0
var _quality := 0
var _rng := RandomNumberGenerator.new()
var _mat: ShaderMaterial = null
var _mesh_near: ArrayMesh = null
var _mesh_mid: ArrayMesh = null
var _mesh_far: ArrayMesh = null
var _chunks_populated := false


func set_spawn_clear(center: Vector3, p_radius: float) -> void:
	_clear_center = center
	_clear_radius = p_radius


## Build all map chunks up front during level load so frame 1 has complete
## arena coverage and zero runtime rebuilds occur in flight.
func prime(_center: Vector3, _wait_for_initial_build: bool = false) -> void:
	if not _built:
		return
	if not _chunks_populated:
		_populate_all_chunks()


func setup(p_map: String, quality: int) -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	map_name = p_map
	_quality = quality
	_rng.seed = hash(map_name) + 90210
	radius = ARENA_HALF
	if map_name == "steppe":
		base_color = Color(0.052, 0.078, 0.024)
		tip_color = Color(0.19, 0.24, 0.062)
	elif map_name == "village":
		base_color = Color(0.055, 0.09, 0.024)
		tip_color = Color(0.18, 0.26, 0.065)
	elif map_name == "wetlands":
		base_color = Color(0.04, 0.075, 0.022)
		tip_color = Color(0.13, 0.22, 0.055)
	else:
		base_color = Color(0.055, 0.075, 0.026)
		tip_color = Color(0.19, 0.22, 0.065)

	_mesh_near = _make_clump_mesh(2, 3, 1.0)
	_mesh_mid = _make_clump_mesh(2, 2, 1.25)
	_mesh_far = _make_clump_mesh(1, 3, 1.45)

	_mat = ShaderMaterial.new()
	_mat.shader = GRASS_SHADER
	_mat.set_shader_parameter("grass_base_color",
			Vector3(base_color.r, base_color.g, base_color.b))
	_mat.set_shader_parameter("grass_tip_color",
			Vector3(tip_color.r, tip_color.g, tip_color.b))
	_mat.set_shader_parameter("wind_strength", 0.12)
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_built = true
	_building = false


func _populate_all_chunks() -> void:
	_building = true
	for c in get_children():
		c.queue_free()

	var is_frontline := not map_name.is_empty() and map_name != "valley"
	var step := 8.0
	var cells := int(ceil((ARENA_HALF + 8.0) / step))
	var side := cells * 2 + 1
	var grid := PackedFloat32Array()
	var water := -999.0
	var flat_y := _clear_center.y
	if is_frontline:
		water = FT.water_level(map_name)
		grid.resize(side * side)
		for gz in range(-cells, cells + 1):
			for gx in range(-cells, cells + 1):
				grid[(gz + cells) * side + (gx + cells)] = FT.height_at(map_name,
						float(gx) * step, float(gz) * step)

	var base_chunk_count := 250
	var max_vis_near := 145.0
	var max_vis_mid := 180.0
	var max_vis_far := 215.0
	if _quality == QualityManager.Level.LOW:
		base_chunk_count = 115
		max_vis_near = 110.0
		max_vis_mid = 135.0
		max_vis_far = 160.0
	elif _quality == QualityManager.Level.MEDIUM:
		base_chunk_count = 185
		max_vis_near = 130.0
		max_vis_mid = 160.0
		max_vis_far = 190.0

	var focus_xz := Vector2(_clear_center.x, _clear_center.z)
	var half_chunk := CHUNK_SIZE * 0.5
	var root_assigned := false
	var total_instances := 0

	for rz in range(GRID_SIDE):
		for rx in range(GRID_SIDE):
			var cx := -ARENA_HALF + (float(rx) + 0.5) * CHUNK_SIZE
			var cz := -ARENA_HALF + (float(rz) + 0.5) * CHUNK_SIZE
			var dist_focus := Vector2(cx, cz).distance_to(focus_xz)
			var tier := 0
			var density_mult := 1.0
			if dist_focus < 75.0:
				tier = 0
				density_mult = 1.0
			elif dist_focus < 135.0:
				tier = 1
				density_mult = 0.62 if _quality != QualityManager.Level.LOW else 0.48
			else:
				tier = 2
				density_mult = 0.36 if _quality != QualityManager.Level.LOW else 0.24

			var target_n := maxi(24, int(round(float(base_chunk_count) * density_mult)))
			var buf := PackedFloat32Array()
			buf.resize(target_n * 12)
			var n := 0
			for i in range(target_n):
				var lx := _rng.randf_range(-half_chunk, half_chunk)
				var lz := _rng.randf_range(-half_chunk, half_chunk)
				var wx := cx + lx
				var wz := cz + lz
				if _clear_radius > 0.01 and Vector2(wx, wz).distance_to(focus_xz) < _clear_radius:
					continue
				if is_frontline and FT._hall_clear_zone(map_name, wx, wz):
					continue
				var wy := flat_y
				if is_frontline:
					wy = _sample_arena_grid(grid, side, cells, step, wx, wz)
					if wy < water + 0.12:
						continue
				var s := _rng.randf_range(0.95, 1.65)
				var b := Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(
						Vector3(s, _rng.randf_range(0.88, 1.45), s))
				var j := n * 12
				buf[j + 0] = b.x.x
				buf[j + 1] = b.y.x
				buf[j + 2] = b.z.x
				buf[j + 3] = lx
				buf[j + 4] = b.x.y
				buf[j + 5] = b.y.y
				buf[j + 6] = b.z.y
				buf[j + 7] = wy + 0.015
				buf[j + 8] = b.x.z
				buf[j + 9] = b.y.z
				buf[j + 10] = b.z.z
				buf[j + 11] = lz
				n += 1
			if n == 0:
				continue
			buf.resize(n * 12)
			total_instances += n

			var chunk_mesh := _mesh_near if tier == 0 else (_mesh_mid if tier == 1 else _mesh_far)
			var vis_end := max_vis_near if tier == 0 else (max_vis_mid if tier == 1 else max_vis_far)
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = chunk_mesh
			mm.instance_count = n
			mm.set_buffer(buf)

			var target_node: MultiMeshInstance3D = null
			if not root_assigned and tier == 0:
				target_node = self
				root_assigned = true
			else:
				target_node = MultiMeshInstance3D.new()
				target_node.name = "GrassChunk_%d_%d" % [rx, rz]
				target_node.material_override = _mat
				target_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				target_node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
				add_child(target_node)

			target_node.multimesh = mm
			target_node.visibility_range_end = vis_end
			target_node.visibility_range_end_margin = 16.0
			target_node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			target_node.custom_aabb = AABB(
					Vector3(-half_chunk - 4.0, -90.0, -half_chunk - 4.0),
					Vector3(CHUNK_SIZE + 8.0, 180.0, CHUNK_SIZE + 8.0))
			if target_node == self:
				global_position = Vector3(cx, 0.0, cz)
			else:
				target_node.global_position = Vector3(cx, 0.0, cz)

	count = total_instances
	_chunks_populated = true
	_building = false


func _sample_arena_grid(grid: PackedFloat32Array, side: int, cells: int, step: float,
		wx: float, wz: float) -> float:
	var gx := (wx + float(cells) * step) / step
	var gz := (wz + float(cells) * step) / step
	var x0 := clampi(int(floor(gx)), 0, side - 2)
	var z0 := clampi(int(floor(gz)), 0, side - 2)
	var fx := clampf(gx - float(x0), 0.0, 1.0)
	var fz := clampf(gz - float(z0), 0.0, 1.0)
	var i := z0 * side + x0
	return lerpf(lerpf(grid[i], grid[i + 1], fx),
			lerpf(grid[i + side], grid[i + side + 1], fx), fz)


func _make_clump_mesh(clusters: int, blades_per_cluster: int, width_mult: float) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7719 + clusters * 31 + blades_per_cluster * 7
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for c in range(clusters):
		var c_angle := rng.randf() * TAU
		var c_dist := rng.randf_range(0.0, 0.28) if c > 0 else 0.0
		var cx := cos(c_angle) * c_dist
		var cz := sin(c_angle) * c_dist
		var base_yaw := rng.randf() * TAU
		for b in range(blades_per_cluster):
			var yaw := base_yaw + float(b) * (TAU / float(blades_per_cluster)) + rng.randf_range(-0.22, 0.22)
			var half_w := rng.randf_range(0.028, 0.048) * width_mult
			var h := rng.randf_range(0.32, 0.68)
			var lean := rng.randf_range(0.07, 0.24)
			var right := Vector3(cos(yaw), 0.0, sin(yaw)) * half_w
			var forward := Vector3(-sin(yaw), 0.0, cos(yaw)) * lean
			var bx := cx + forward.x * 0.08
			var bz := cz + forward.z * 0.08
			var root := Vector3(bx, -0.02, bz)
			var mid := root + Vector3(0.0, h * 0.56, 0.0) + forward * 0.42
			var tip := root + Vector3(0.0, h, 0.0) + forward
			var v0 := vertices.size()
			vertices.append(root - right)
			vertices.append(root + right)
			vertices.append(mid - right * 0.58)
			vertices.append(mid + right * 0.58)
			vertices.append(tip)
			uvs.append(Vector2(0.0, 1.0))
			uvs.append(Vector2(1.0, 1.0))
			uvs.append(Vector2(0.2, 0.45))
			uvs.append(Vector2(0.8, 0.45))
			uvs.append(Vector2(0.5, 0.0))
			var shade := rng.randf_range(0.80, 1.14)
			colors.append(Color(0.42, 0.40, 0.32) * shade)
			colors.append(Color(0.42, 0.40, 0.32) * shade)
			colors.append(Color(0.76, 0.74, 0.58) * shade)
			colors.append(Color(0.76, 0.74, 0.58) * shade)
			colors.append(Color(1.02, 1.00, 0.88) * shade)
			for _k in range(5):
				normals.append(Vector3(0.0, 1.0, 0.0))
			indices.append_array([v0, v0 + 1, v0 + 3,
				v0, v0 + 3, v0 + 2, v0 + 2, v0 + 3, v0 + 4])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
