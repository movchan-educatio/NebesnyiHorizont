class_name FollowGrass
extends MultiMeshInstance3D

## Dense grass carpet that follows the active camera across the whole map.
##
## The static spawn carpet gave beautiful blades only around the starting hall;
## flying 100 m away dropped back to a painted ground texture.  This node keeps
## a dense ring of clumps around whatever camera is active (FPV or spectator)
## and rebuilds only when the camera moves, so every map part gets the same
## near-field grass at one draw call.

const VEGETATION := preload("res://scripts/util/vegetation_assets.gd")
const GRASS_SHADER := preload("res://Assets/grass_wind.gdshader")
const FT := preload("res://scripts/util/frontline_terrain.gd")

var map_name := ""
var radius := 32.0
var count := 16000
var base_color := Color(0.08, 0.10, 0.035)
var tip_color := Color(0.24, 0.24, 0.09)
var _last_center := Vector3(1e20, 0.0, 0.0)
var _built := false
var _building := false
var _clear_center := Vector3.ZERO
var _clear_radius := 0.0
var _rng := RandomNumberGenerator.new()
## Fixed local blade pattern.  Regenerating random angles/radii on every
## rebuild made the carpet visibly "swim" and spent most of the rebuild budget
## on RNG + sin/cos.  The offsets and bases are generated once in setup(); a
## rebuild now only samples terrain height and uploads the buffer.
var _local_xz := PackedVector2Array()
var _local_basis: Array[Basis] = []


func set_spawn_clear(center: Vector3, radius: float) -> void:
	_clear_center = center
	_clear_radius = radius


## Build the first carpet while the loading card is still up, so the first
## visible frame does not pay the rebuild cost.
func prime(center: Vector3, wait_for_initial_build: bool = false) -> void:
	if not _built:
		return
	var ground_center := Vector3(center.x, 0.0, center.z)
	if wait_for_initial_build:
		await _rebuild(ground_center)
	else:
		_rebuild(ground_center)


func setup(p_map: String, quality: int) -> void:
	# The carpet is rebuilt from _process while the renderer runs; 3D physics
	# interpolation would otherwise try to interpolate the fresh MultiMesh
	# transforms and can leave the whole batch invisible.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	map_name = p_map
	_rng.seed = hash(map_name) + 90210
	radius = 34.0
	count = 6000
	if quality == QualityManager.Level.MEDIUM:
		radius = 26.0
		count = 2800
	elif quality == QualityManager.Level.LOW:
		radius = 20.0
		count = 1350
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
	var mesh: ArrayMesh = _make_lush_mesh()
	if mesh == null:
		mesh = FoliageSystem.create_grass_mesh(10, 1.2)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = GRASS_SHADER
	mat.set_shader_parameter("grass_base_color",
			Vector3(base_color.r, base_color.g, base_color.b))
	mat.set_shader_parameter("grass_tip_color",
			Vector3(tip_color.r, tip_color.g, tip_color.b))
	mat.set_shader_parameter("wind_strength", 0.12)
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visibility_range_end = radius + 35.0
	visibility_range_end_margin = 10.0
	visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	# Explicit local bounds: the MultiMesh AABB is only refreshed by the
	# renderer after a frame, so a zero-size batch could be frustum-culled on
	# its very first draw.
	custom_aabb = AABB(Vector3(-radius, -120.0, -radius),
			Vector3(radius * 2.0, 240.0, radius * 2.0))
	_build_pattern()
	_built = true


func _build_pattern() -> void:
	_local_xz.resize(count)
	_local_basis.resize(count)
	for i in range(count):
		var a := _rng.randf_range(0.0, TAU)
		var r := pow(_rng.randf(), 0.70) * radius
		_local_xz[i] = Vector2(cos(a) * r, sin(a) * r)
		var s := _rng.randf_range(1.0, 1.7)
		_local_basis[i] = Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(
				Vector3(s, _rng.randf_range(0.9, 1.5), s))


## Multi-blade crossed grass clumps built for the near camera. Grouping blades
## into 5 three-blade tufts inside one clump boosts apparent ground coverage ~3x
## per MultiMesh instance while keeping low-altitude silhouettes thick and crisp.
func _make_lush_mesh() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7719
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var clusters := 5
	for c in range(clusters):
		var c_angle := rng.randf() * TAU
		var c_dist := rng.randf_range(0.0, 0.28) if c > 0 else 0.0
		var cx := cos(c_angle) * c_dist
		var cz := sin(c_angle) * c_dist
		var base_yaw := rng.randf() * TAU
		for b in range(3):
			var yaw := base_yaw + float(b) * (TAU / 3.0) + rng.randf_range(-0.22, 0.22)
			var half_w := rng.randf_range(0.026, 0.044)
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


func _process(_delta: float) -> void:
	if not _built or map_name.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var p := cam.global_position
	if FT._hall_clear_zone(map_name, p.x, p.z):
		visible = false
		return
	visible = true
	# A rebuild is spread over several frames so a 6000-12000 blade carpet
	# never stalls one frame.  The old carpet stays visible until the new
	# buffer is uploaded.
	if _building:
		return
	# Rebuild only on meaningful horizontal travel.  Including camera altitude
	# here made a climbing drone rebuild every 12 m of climb (a 70-100 ms spike
	# several times per second); grass is a ground carpet, so vertical motion
	# must not trigger it.
	var dx := p.x - _last_center.x
	var dz := p.z - _last_center.z
	var threshold := maxf(12.0, radius * 0.8)
	if dx * dx + dz * dz < threshold * threshold and multimesh.instance_count > 0:
		return
	_rebuild(p)


func _rebuild(center: Vector3) -> void:
	_building = true
	# Height lookups are expensive (noise + craters + trenches).  Sampling
	# 2200-20000 blades individually cost 70-100 ms per rebuild on the UHD.
	# Build one coarse local height grid and bilinearly sample it instead.
	var step := 3.0 if radius < 30.0 else 4.0
	var cells := int(ceil((radius + 2.0) / step))
	var side := cells * 2 + 1
	var grid := PackedFloat32Array()
	grid.resize(side * side)
	for gz in range(-cells, cells + 1):
		for gx in range(-cells, cells + 1):
			grid[(gz + cells) * side + (gx + cells)] = FT.height_at(map_name,
					center.x + float(gx) * step, center.z + float(gz) * step)
	var water := FT.water_level(map_name)
	var buf := PackedFloat32Array()
	buf.resize(_local_xz.size() * 12)
	var n := 0
	for i in range(_local_xz.size()):
		var lx := _local_xz[i].x
		var lz := _local_xz[i].y
		if _clear_radius > 0.01 and Vector2(center.x + lx, center.z + lz).distance_to(
				Vector2(_clear_center.x, _clear_center.z)) < _clear_radius:
			continue
		var y := _grid_height(grid, side, cells, step, lx, lz)
		if y < water + 0.12:
			continue
		# Write the 3x4 instance matrix directly: one buffer upload, no
		# intermediate Array[Transform3D], no per-instance engine calls.
		var b: Basis = _local_basis[i]
		var j := n * 12
		buf[j + 0] = b.x.x
		buf[j + 1] = b.y.x
		buf[j + 2] = b.z.x
		buf[j + 3] = lx
		buf[j + 4] = b.x.y
		buf[j + 5] = b.y.y
		buf[j + 6] = b.z.y
		buf[j + 7] = y + 0.015
		buf[j + 8] = b.x.z
		buf[j + 9] = b.y.z
		buf[j + 10] = b.z.z
		buf[j + 11] = lz
		n += 1
		# Yield every 700 blades: ~2-3 ms per frame instead of a 15-30 ms
		# stall, while the previous carpet remains fully visible.
		if (i & 0x2FF) == 0x2FF:
			if not is_inside_tree():
				return
			await get_tree().process_frame
	buf.resize(n * 12)
	global_position = Vector3(center.x, 0.0, center.z)
	multimesh.instance_count = n
	multimesh.set_buffer(buf)
	_last_center = center
	_building = false
	print("[GRASS] spread rebuild map=", map_name, " count=", n,
			" radius=", radius)


## Bilinear sample of the local rebuild grid.  lx/lz are offsets from center.
func _grid_height(grid: PackedFloat32Array, side: int, cells: int, step: float,
		lx: float, lz: float) -> float:
	var gx := (lx + float(cells) * step) / step
	var gz := (lz + float(cells) * step) / step
	var x0 := clampi(int(floor(gx)), 0, side - 2)
	var z0 := clampi(int(floor(gz)), 0, side - 2)
	var fx := clampf(gx - float(x0), 0.0, 1.0)
	var fz := clampf(gz - float(z0), 0.0, 1.0)
	var i := z0 * side + x0
	return lerpf(lerpf(grid[i], grid[i + 1], fx),
			lerpf(grid[i + side], grid[i + side + 1], fx), fz)
