class_name DestructionFx
extends RefCounted

## Reusable hit / explosion / burning presentation for ground vehicles, aerial
## targets and infantry.
##
## The gallery in `test/destruction_gallery.tscn` previews it on the real GLB
## models.  Nothing here is wired into gameplay yet: the live `Vehicle._destroy`
## keeps its own path until the look is approved.
##
## Stages
##   hit()      sparks, metal flash, dust, a short physical jolt;
##   destroy()  fireball, shockwave, debris, charred hull, secondary cook-off,
##              persistent fire + smoke on the wreck;
##   aerial     the same, but the target spins down and impacts the ground
##              instead of freezing at the hit altitude.

const CHAR_COLOR := Color(0.11, 0.10, 0.09)
const FIRE_COLOR := Color(1.0, 0.48, 0.10, 1.0)
const SMOKE_COLOR := Color(0.20, 0.19, 0.18, 0.55)
const DUST_COLOR := Color(0.55, 0.46, 0.33, 0.55)

static var _char_mat: StandardMaterial3D = null
static var _spark_tex: GradientTexture2D = null
static var _smoke_tex: GradientTexture2D = null
static var _dust_tex: GradientTexture2D = null
static var _flame_tex: ImageTexture = null
static var _cloud_puff_tex: ImageTexture = null
static var _dust_ring_tex: ImageTexture = null
static var _debris_mesh_cache: Mesh = null
static var _shock_dome_shader: Shader = null
static var _flame_shader: Shader = null
static var _flame_atlas: ImageTexture = null
static var _fx_cleanup_wired: bool = false


const MAX_ACTIVE_BURNS := 10
const MAX_LOW_PARTICLE_SYSTEMS := 36
static var _active_burns := 0
static var _active_particle_systems := 0


static func _can_spawn_particles(needed: int = 1) -> bool:
	if not _low_quality():
		return true
	return _active_particle_systems + needed <= MAX_LOW_PARTICLE_SYSTEMS


static func _track_particle_system(node: Node) -> void:
	if node == null:
		return
	_active_particle_systems += 1
	if not node.tree_exiting.is_connected(_on_particle_system_exiting):
		node.tree_exiting.connect(_on_particle_system_exiting, CONNECT_ONE_SHOT)


static func _on_particle_system_exiting() -> void:
	_active_particle_systems = maxi(0, _active_particle_systems - 1)


static func _on_burn_exiting() -> void:
	_active_burns = maxi(0, _active_burns - 1)


static func clear_caches() -> void:
	_char_mat = null
	_spark_tex = null
	_smoke_tex = null
	_dust_tex = null
	_flame_tex = null
	_cloud_puff_tex = null
	_dust_ring_tex = null
	_debris_mesh_cache = null
	_shock_dome_shader = null
	_flame_shader = null
	_flame_atlas = null
	_fx_cleanup_wired = false
	_active_burns = 0
	_active_particle_systems = 0


static func _wire_cache_cleanup() -> void:
	if _fx_cleanup_wired:
		return
	var loop := Engine.get_main_loop()
	if loop is SceneTree and (loop as SceneTree).root != null:
		var root := (loop as SceneTree).root
		if not root.tree_exiting.is_connected(clear_caches):
			root.tree_exiting.connect(clear_caches, CONNECT_ONE_SHOT)
			_fx_cleanup_wired = true


## Procedural 64x64 radial noise-dithered puff texture (cached once), matching
## ExplosionSystem.ts::createCloudPuffTexture() within LOW-preset GPU memory.
static func create_cloud_puff_texture() -> ImageTexture:
	_wire_cache_cleanup()
	if _cloud_puff_tex != null:
		return _cloud_puff_tex
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half := float(size) * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = 64064
	for y in range(size):
		for x in range(size):
			var dx := (float(x) + 0.5 - half) / half
			var dy := (float(y) + 0.5 - half) / half
			var r := sqrt(dx * dx + dy * dy)
			var ang := atan2(dy, dx)
			var lobe := 0.86 + 0.14 * sin(ang * 3.0 + 0.7) * cos(ang * 2.0 - 0.4)
			var n := rng.randf_range(-0.08, 0.08)
			var d := clampf(r / lobe + n, 0.0, 1.0)
			var alpha := clampf(pow(1.0 - d, 1.75), 0.0, 1.0)
			# Soft radial shading (bright core -> cooler rim) so additive & alpha puffs read cleanly
			var shade := clampf(1.0 - d * 0.25, 0.65, 1.0)
			img.set_pixel(x, y, Color(shade, shade, shade, alpha))
	_cloud_puff_tex = ImageTexture.create_from_image(img)
	return _cloud_puff_tex


## Rolling dust-ring sprite: a thin, noisy annulus instead of a filled disc.
## Cached once at 64x64 - the ground shockwave reads as kicked-up dirt rather
## than a translucent pancake, at the cost of one extra alpha-blended quad.
static func create_dust_ring_texture() -> ImageTexture:
	_wire_cache_cleanup()
	if _dust_ring_tex != null:
		return _dust_ring_tex
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half := float(size) * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = 77021
	for y in range(size):
		for x in range(size):
			var dx := (float(x) + 0.5 - half) / half
			var dy := (float(y) + 0.5 - half) / half
			var r := sqrt(dx * dx + dy * dy)
			var ang := atan2(dy, dx)
			var wobble := 0.78 + 0.10 * sin(ang * 5.0) + 0.06 * sin(ang * 9.0 + 1.3)
			var n := rng.randf_range(-0.05, 0.05)
			var d := absf(r - wobble) + n
			var a := clampf(1.0 - d / 0.24, 0.0, 1.0)
			a *= a
			var shade := 0.74 + 0.26 * rng.randf()
			img.set_pixel(x, y, Color(shade, shade * 0.93, shade * 0.84, a))
	_dust_ring_tex = ImageTexture.create_from_image(img)
	return _dust_ring_tex


## One cached faceted shard used for every flying fragment.  A jittered cube
## still reads as a rectangle; an octahedron has only triangular faces, so no
## viewing angle produces a square silhouette.  Same 1-draw MultiMesh budget.
static func debris_mesh() -> Mesh:
	_wire_cache_cleanup()
	if _debris_mesh_cache != null:
		return _debris_mesh_cache
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var base := [
		Vector3(1.0, 0.0, 0.0), Vector3(-1.0, 0.0, 0.0),
		Vector3(0.0, 1.0, 0.0), Vector3(0.0, -1.0, 0.0),
		Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, -1.0),
	]
	var dims := Vector3(0.19, 0.12, 0.15)
	var pts := PackedVector3Array()
	for p in base:
		pts.append(Vector3(
			p.x * rng.randf_range(0.55, 1.45) * dims.x,
			p.y * rng.randf_range(0.40, 1.35) * dims.y,
			p.z * rng.randf_range(0.55, 1.45) * dims.z))
	var faces := [
		0, 2, 4, 2, 1, 4, 1, 3, 4, 3, 0, 4,
		2, 0, 5, 1, 2, 5, 3, 1, 5, 0, 3, 5,
	]
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	for i in range(0, faces.size(), 3):
		var a := pts[faces[i]]
		var b := pts[faces[i + 1]]
		var c := pts[faces[i + 2]]
		var n := (b - a).cross(c - a).normalized()
		if n.dot(a) < 0.0:
			# Swap winding so every face normal points away from the centre.
			var tmp := b
			b = c
			c = tmp
			n = -n
		verts.append(a)
		verts.append(b)
		verts.append(c)
		norms.append(n)
		norms.append(n)
		norms.append(n)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_debris_mesh_cache = mesh
	return mesh


static func _get_shock_dome_shader() -> Shader:
	_wire_cache_cleanup()
	if _shock_dome_shader != null:
		return _shock_dome_shader
	var s := Shader.new()
	s.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform float rim_power : hint_range(0.5, 6.0) = 2.4;
uniform float intensity : hint_range(0.0, 4.0) = 1.0;
uniform vec4 rim_color : source_color = vec4(1.0, 0.85, 0.65, 1.0);
void fragment() {
	float ndv = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float fresnel = pow(1.0 - ndv, rim_power);
	float core = 0.08 * intensity;
	ALBEDO = rim_color.rgb;
	ALPHA = clamp((fresnel * 0.92 + core) * intensity, 0.0, 0.95);
}
"""
	_shock_dome_shader = s
	return _shock_dome_shader


## An 8-frame flipbook of organic flame tongues, generated once at 48px/frame.
## Gaussian blobs along a swaying centreline read as fire; a static cone or a
## per-pixel noise field never did. Total texture: 384x48 RGBA (~72 KB).
static func flame_atlas() -> ImageTexture:
	_wire_cache_cleanup()
	if _flame_atlas != null:
		return _flame_atlas
	var frames := 8
	var size := 64
	var img := Image.create(size * frames, size, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	for f in range(frames):
		rng.seed = 700 + f * 131
		# Six separate tongues, each with its own height, width and sway.
		# Overlapping smooth blobs used to merge into one clipped teardrop.
		var tongues: Array = []
		for i in range(6):
			var tx := 0.16 + float(i) * 0.136 + rng.randf_range(-0.03, 0.03)
			var th := rng.randf_range(0.50, 0.98)
			var tw := rng.randf_range(0.045, 0.085)
			var sway := rng.randf_range(-0.17, 0.17)
			var phase := rng.randf_range(0.0, TAU)
			tongues.append([tx, th, tw, sway, phase])
		for py in range(size):
			# v = 0 at image bottom = hot base. The shader flips UV.y.
			var v := 1.0 - float(py) / float(size - 1)
			for px in range(size):
				var u := float(px) / float(size - 1)
				var ar := 0.0
				var ag := 0.0
				var ab := 0.0
				var aa := 0.0
				for t in tongues:
					var tx: float = t[0]
					var th: float = t[1]
					var tw: float = t[2]
					var sway: float = t[3]
					var phase: float = t[4]
					var hv := clampf(v / maxf(th, 0.01), 0.0, 1.0)
					if hv >= 1.0:
						continue
					var centre := tx + sway * hv * hv + sin(hv * 7.0 + phase) * 0.032 * hv
					var wide := tw * (1.0 - hv * 0.52) \
							* (1.0 + 0.30 * sin(hv * 9.0 + phase * 1.7))
					var dx := (u - centre) / maxf(wide, 0.004)
					var d2 := dx * dx
					if d2 > 7.0:
						continue
					var c := exp(-d2 * 1.15) * (1.0 - smoothstep(0.70, 1.0, hv))
					var cg := lerpf(0.94, 0.16, hv)
					var cb := lerpf(0.62, 0.01, clampf(hv * 1.5, 0.0, 1.0))
					var cr := 1.0 if hv < 0.60 else lerpf(1.0, 0.72, (hv - 0.60) / 0.40)
					ar += cr * c
					ag += cg * c
					ab += cb * c
					aa += c
				if aa > 0.0001:
					# Feather all four edges: no quad rectangle can ever show.
					var edge := smoothstep(0.0, 0.09, u) * (1.0 - smoothstep(0.91, 1.0, u))
					edge *= smoothstep(0.0, 0.03, v) * (1.0 - smoothstep(0.88, 1.0, v))
					img.set_pixel(f * size + px, py, Color(ar / aa, ag / aa,
							ab / aa, clampf(aa * 0.92, 0.0, 1.0) * edge))
				else:
					img.set_pixel(f * size + px, py, Color(0.0, 0.0, 0.0, 0.0))
	_flame_atlas = ImageTexture.create_from_image(img)
	return _flame_atlas


## Flame material: billboard quad that cycles through the flipbook atlas.
## One texture sample per pixel; billboarding happens in vertex().
static func _get_flame_shader() -> Shader:
	_wire_cache_cleanup()
	if _flame_shader != null:
		return _flame_shader
	var s := Shader.new()
	s.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform sampler2D flame_atlas : source_color;
uniform float fps : hint_range(1.0, 60.0) = 18.0;
uniform float frames : hint_range(2.0, 32.0) = 8.0;
uniform float seed_offset : hint_range(0.0, 64.0) = 0.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	float idx = floor(mod(TIME * fps + seed_offset * frames, frames));
	// The atlas is authored so UV.y=0 is the hot base; keep this orientation.
	vec2 uv = vec2((clamp(UV.x, 0.02, 0.98) + idx) / frames, UV.y);
	vec4 fire = texture(flame_atlas, uv);
	// Extra feather as a safety net - guarantees no square silhouette even if
	// a future atlas is generated with harder edges.
	float edge = smoothstep(0.0, 0.06, UV.x) * (1.0 - smoothstep(0.94, 1.0, UV.x))
			* smoothstep(0.0, 0.04, UV.y) * (1.0 - smoothstep(0.96, 1.0, UV.y));
	ALBEDO = fire.rgb;
	ALPHA = fire.a * edge;
}
"""
	_flame_shader = s
	return _flame_shader


## Multi-stage explosion (ExplosionSystem.ts port tuned for LOW/mobile GPU budget):
## 1) GroundShockRing (expanding 18-24 m fading dust shock ring)
## 2) ShockwaveDome (Fresnel rim flash sphere in first 0.35 s)
## 3) FireballCore (0.4 s hot white-orange transition to billowing smoke mushroom)
## 4) 10-16 ballistic tumbling DebrisChunks (1 batched MultiMeshInstance3D draw)
## 5) Velocity-aligned SparkStreaks
static func spawn_multiphase_explosion(parent: Node, pos: Vector3, scale_factor: float = 1.0,
		ground_y: float = -1.0e9, is_aerial: bool = false) -> Node3D:
	if parent == null or not is_instance_valid(parent) or not parent.is_inside_tree():
		return null
	_wire_cache_cleanup()
	var low := _low_quality()
	var puff_tex := create_cloud_puff_texture()
	var s := clampf(scale_factor, 0.55, 2.2)

	var fx_root := Node3D.new()
	fx_root.name = "MultiphaseExplosion"
	parent.add_child(fx_root)
	fx_root.global_position = pos

	# 1. GroundShockRing (skip if high aerial explosion > 14 m above ground)
	var gy := ground_y
	if gy < -1.0e6:
		gy = _resolve_ground_y(parent, pos)
	var ring_mesh: MeshInstance3D = null
	var ring_mat: StandardMaterial3D = null
	if not is_aerial or absf(pos.y - gy) < 14.0:
		ring_mesh = MeshInstance3D.new()
		ring_mesh.name = "GroundShockRing"
		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.0
		cyl.bottom_radius = 1.0
		cyl.height = 0.08
		cyl.radial_segments = 24 if low else 32
		cyl.rings = 1
		ring_mesh.mesh = cyl
		ring_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring_mat = StandardMaterial3D.new()
		ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		ring_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		ring_mat.albedo_color = Color(0.55, 0.47, 0.36, 0.34)
		ring_mat.albedo_texture = create_dust_ring_texture()
		ring_mesh.material_override = ring_mat
		ring_mesh.position = Vector3(0.0, clampf(gy - pos.y + 0.14, -12.0, 0.35), 0.0)
		fx_root.add_child(ring_mesh)

	# 2. ShockwaveDome (Fresnel sphere expanding in first 0.35 s)
	var dome_mesh := MeshInstance3D.new()
	dome_mesh.name = "ShockwaveDome"
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 16 if low else 24
	sphere.rings = 10 if low else 14
	dome_mesh.mesh = sphere
	dome_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var dome_mat := ShaderMaterial.new()
	dome_mat.shader = _get_shock_dome_shader()
	dome_mat.set_shader_parameter("rim_power", 3.1)
	dome_mat.set_shader_parameter("intensity", 0.85)
	dome_mat.set_shader_parameter("rim_color", Color(1.0, 0.82, 0.52, 1.0))
	dome_mesh.material_override = dome_mat
	fx_root.add_child(dome_mesh)

	# 2b. Additive ground flash ring. This is the bright leading edge the eye
	# actually reads as a shockwave, so the translucent dome can stay faint.
	# One short-lived quad, reuses the cached dust-ring texture.
	var flash_mesh := MeshInstance3D.new()
	flash_mesh.name = "ShockFlashRing"
	var flash_plane := PlaneMesh.new()
	flash_plane.size = Vector2(2.0, 2.0)
	flash_mesh.mesh = flash_plane
	flash_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var flash_mat := StandardMaterial3D.new()
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flash_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	flash_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	flash_mat.albedo_texture = puff_tex
	flash_mat.albedo_color = Color(1.0, 0.76, 0.48, 0.20)
	flash_mesh.material_override = flash_mat
	flash_mesh.rotation.x = -PI * 0.5
	flash_mesh.position.y = 0.16
	fx_root.add_child(flash_mesh)

	# 3. FireballCore (hot white-orange expanding core -> dark-grey mushroom smoke)
	var core_mesh := MeshInstance3D.new()
	core_mesh.name = "FireballCore"
	var core_sphere := SphereMesh.new()
	core_sphere.radius = 1.0
	core_sphere.height = 2.0
	core_sphere.radial_segments = 14 if low else 20
	core_sphere.rings = 8 if low else 12
	core_mesh.mesh = core_sphere
	core_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	core_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	core_mat.albedo_color = Color(1.0, 0.94, 0.78, 0.95)
	# Soft-edged puff instead of a hard sphere - the fireball now reads as a
	# luminous cloud and the dark smoke stage blends into it naturally.
	core_mat.albedo_texture = puff_tex
	core_mesh.material_override = core_mat
	fx_root.add_child(core_mesh)

	# Tiny white-hot ignition core; lives only ~0.3 s and sells the detonation.
	var hot_mesh := MeshInstance3D.new()
	hot_mesh.name = "HotCore"
	var hot_sphere := SphereMesh.new()
	hot_sphere.radius = 1.0
	hot_sphere.height = 2.0
	hot_sphere.radial_segments = 10 if low else 14
	hot_sphere.rings = 6 if low else 8
	hot_mesh.mesh = hot_sphere
	hot_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var hot_mat := StandardMaterial3D.new()
	hot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hot_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hot_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	hot_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	hot_mat.albedo_color = Color(1.0, 0.96, 0.82, 1.0)
	hot_mat.albedo_texture = puff_tex
	hot_mesh.material_override = hot_mat
	fx_root.add_child(hot_mesh)

	# Billowing smoke mushroom puffs (cloud_puff_texture)
	if _can_spawn_particles(1):
		var plume := GPUParticles3D.new()
		plume.name = "FireballSmokePlume"
		plume.emitting = true
		plume.one_shot = true
		plume.explosiveness = 0.72
		plume.amount = 14 if low else 24
		plume.lifetime = 2.6 if low else 3.1
		plume.visibility_aabb = AABB(Vector3(-36, -4, -36), Vector3(72, 44, 72))
		var wind := _scene_wind(parent)
		var wind_speed := wind.length()
		var pmat := ParticleProcessMaterial.new()
		pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pmat.emission_sphere_radius = 1.2 * s
		pmat.direction = (Vector3(0.0, 1.0, 0.0) + wind * 0.14).normalized()
		pmat.spread = 32.0
		pmat.initial_velocity_min = 3.8 * s + wind_speed * 0.20
		pmat.initial_velocity_max = 9.2 * s + wind_speed * 0.38
		pmat.gravity = Vector3(0.0, 2.2, 0.0) + wind * 0.45
		pmat.damping_min = 2.4
		pmat.damping_max = 3.6
		pmat.scale_min = 2.2 * s
		pmat.scale_max = 5.4 * s
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.14, 0.40, 1.0])
		grad.colors = PackedColorArray([
			Color(1.0, 0.92, 0.65, 0.92),
			Color(1.0, 0.45, 0.10, 0.84),
			Color(0.24, 0.22, 0.21, 0.68),
			Color(0.14, 0.14, 0.14, 0.0),
		])
		var ramp := GradientTexture1D.new()
		ramp.gradient = grad
		pmat.color_ramp = ramp
		plume.process_material = pmat
		var puff_quad := QuadMesh.new()
		puff_quad.size = Vector2(1.4, 1.4)
		var puff_mat := StandardMaterial3D.new()
		puff_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		puff_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		puff_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		puff_mat.billboard_keep_scale = true
		puff_mat.vertex_color_use_as_albedo = true
		puff_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		puff_mat.albedo_texture = puff_tex
		puff_quad.material = puff_mat
		plume.draw_pass_1 = puff_quad
		fx_root.add_child(plume)
		_track_particle_system(plume)

	# Rising embers: reuses the cached spark texture and the shared emitter
	# helper, so it adds detail without a new shader or texture upload.
	var embers := _emitter(fx_root, "Embers", 10 if low else 18, 1.5,
			Color(1.0, 0.52, 0.12, 1.0), _texture("spark"),
			5.0 * s, 11.0 * s, Vector3(0.0, -4.0, 0.0), 0.05 * s, 0.13 * s, true)
	if embers != null:
		embers.one_shot = true
		embers.explosiveness = 0.85

	# 4. 10-16 ballistic tumbling DebrisChunks (single batched MultiMesh draw)
	var chunk_count := 10 if low else 16
	var debris_mmi := MultiMeshInstance3D.new()
	debris_mmi.name = "DebrisChunks"
	debris_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = chunk_count
	var chunk_mat := StandardMaterial3D.new()
	chunk_mat.roughness = 0.88
	chunk_mat.metallic = 0.12
	chunk_mat.metallic_specular = 0.25
	chunk_mat.vertex_color_use_as_albedo = true
	var chunk_mesh := debris_mesh()
	chunk_mesh.surface_set_material(0, chunk_mat)
	mm.mesh = chunk_mesh
	debris_mmi.multimesh = mm
	fx_root.add_child(debris_mmi)

	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var chunk_pos := PackedVector3Array()
	var chunk_vel := PackedVector3Array()
	var chunk_rot := PackedVector3Array()
	var chunk_spin := PackedVector3Array()
	var chunk_scale := PackedFloat32Array()
	var chunk_shape := PackedVector3Array()
	chunk_pos.resize(chunk_count)
	chunk_vel.resize(chunk_count)
	chunk_rot.resize(chunk_count)
	chunk_spin.resize(chunk_count)
	chunk_scale.resize(chunk_count)
	chunk_shape.resize(chunk_count)
	var v_scale := clampf(s, 0.85, 1.25)
	for i in range(chunk_count):
		var a := rng.randf_range(0.0, TAU)
		var spd := rng.randf_range(6.5, 17.5) * v_scale
		chunk_pos[i] = Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(0.2, 0.9), rng.randf_range(-0.6, 0.6))
		chunk_vel[i] = Vector3(cos(a) * spd, rng.randf_range(6.5, 15.5) * v_scale, sin(a) * spd)
		chunk_rot[i] = Vector3(rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU))
		chunk_spin[i] = Vector3(rng.randf_range(-9.0, 9.0), rng.randf_range(-9.0, 9.0), rng.randf_range(-9.0, 9.0))
		chunk_scale[i] = rng.randf_range(0.65, 1.55) * s
		# Non-uniform per-instance scaling makes identical meshes read as
		# different jagged splinters instead of repeated rectangular blocks.
		chunk_shape[i] = Vector3(rng.randf_range(0.55, 1.60),
				rng.randf_range(0.40, 1.05), rng.randf_range(0.55, 1.55))
		var glow_hot := 1.0 if i < 4 else rng.randf_range(0.18, 0.36)
		mm.set_instance_color(i, Color(glow_hot, glow_hot * 0.42, 0.14) if i < 4 else Color(0.14, 0.13, 0.12))
		mm.set_instance_transform(i, Transform3D(Basis.from_euler(chunk_rot[i]).scaled(chunk_shape[i] * chunk_scale[i]), chunk_pos[i]))

	# 5. Fast glowing SparkStreaks
	if _can_spawn_particles(1):
		var sparks := GPUParticles3D.new()
		sparks.name = "SparkStreaks"
		sparks.emitting = true
		sparks.one_shot = true
		sparks.explosiveness = 0.95
		sparks.amount = 14 if low else 24
		sparks.lifetime = 0.85
		sparks.visibility_aabb = AABB(Vector3(-16, -4, -16), Vector3(32, 24, 32))
		var smat := ParticleProcessMaterial.new()
		smat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		smat.emission_sphere_radius = 0.5 * s
		smat.direction = Vector3(0.0, 1.0, 0.0)
		smat.spread = 80.0
		smat.initial_velocity_min = 14.0 * s
		smat.initial_velocity_max = 30.0 * s
		smat.gravity = Vector3(0.0, -18.0, 0.0)
		smat.damping_min = 0.8
		smat.damping_max = 1.6
		smat.particle_flag_align_y = true
		var sgrad := Gradient.new()
		sgrad.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		sgrad.colors = PackedColorArray([
			Color(1.0, 0.96, 0.72, 1.0),
			Color(1.0, 0.55, 0.14, 0.90),
			Color(0.60, 0.15, 0.02, 0.0),
		])
		var sramp := GradientTexture1D.new()
		sramp.gradient = sgrad
		smat.color_ramp = sramp
		sparks.process_material = smat
		var streak_quad := QuadMesh.new()
		streak_quad.size = Vector2(0.08 * s, 0.65 * s)
		var streak_mat := StandardMaterial3D.new()
		streak_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		streak_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		streak_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		streak_mat.vertex_color_use_as_albedo = true
		streak_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		streak_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		streak_mat.albedo_texture = _texture("spark")
		streak_quad.material = streak_mat
		sparks.draw_pass_1 = streak_quad
		fx_root.add_child(sparks)
		_track_particle_system(sparks)

	# Drive expansion, color transitions, debris ballistics, and clean auto-free in 1 light controller
	var driver := _MultiphaseDriver.new()
	driver.ring_mesh = ring_mesh
	driver.ring_mat = ring_mat
	driver.dome_mesh = dome_mesh
	driver.dome_mat = dome_mat
	driver.flash_mesh = flash_mesh
	driver.flash_mat = flash_mat
	driver.core_mesh = core_mesh
	driver.core_mat = core_mat
	driver.hot_mesh = hot_mesh
	driver.hot_mat = hot_mat
	driver.debris_mmi = debris_mmi
	driver.chunk_pos = chunk_pos
	driver.chunk_vel = chunk_vel
	driver.chunk_rot = chunk_rot
	driver.chunk_spin = chunk_spin
	driver.chunk_scale = chunk_scale
	driver.chunk_shape = chunk_shape
	driver.local_ground_y = gy - pos.y + 0.10
	driver.scale_factor = s
	driver.max_life = 3.5
	fx_root.add_child(driver)
	return fx_root


class _MultiphaseDriver extends Node:
	var ring_mesh: MeshInstance3D = null
	var ring_mat: StandardMaterial3D = null
	var dome_mesh: MeshInstance3D = null
	var dome_mat: ShaderMaterial = null
	var flash_mesh: MeshInstance3D = null
	var flash_mat: StandardMaterial3D = null
	var core_mesh: MeshInstance3D = null
	var core_mat: StandardMaterial3D = null
	var hot_mesh: MeshInstance3D = null
	var hot_mat: StandardMaterial3D = null
	var debris_mmi: MultiMeshInstance3D = null
	var chunk_pos := PackedVector3Array()
	var chunk_vel := PackedVector3Array()
	var chunk_rot := PackedVector3Array()
	var chunk_spin := PackedVector3Array()
	var chunk_scale := PackedFloat32Array()
	var chunk_shape := PackedVector3Array()
	var local_ground_y := -1.0
	var scale_factor := 1.0
	var max_life := 4.4
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		if _t >= max_life:
			var p := get_parent()
			if p != null and is_instance_valid(p):
				p.queue_free()
			return

		# 1. GroundShockRing expands 1.5 -> 21 m * scale_factor over ~0.85 s
		if ring_mesh != null and ring_mat != null:
			var rt := clampf(_t / 0.85, 0.0, 1.0)
			if rt >= 1.0:
				ring_mesh.visible = false
			else:
				var radius := lerpf(1.4, 21.0 * scale_factor, 1.0 - pow(1.0 - rt, 2.2))
				ring_mesh.scale = Vector3(radius, 1.0, radius)
				ring_mat.albedo_color.a = 0.30 * pow(1.0 - rt, 1.8)

		# 2. Shockwave: a flat, fast pressure lens rather than a giant bubble.
		# Squashing Y keeps the volume cue but removes the translucent-ball look.
		if dome_mesh != null and dome_mat != null:
			var dt := clampf(_t / 0.28, 0.0, 1.0)
			if dt >= 1.0:
				dome_mesh.visible = false
			else:
				var dr := lerpf(1.4, 7.0 * scale_factor, 1.0 - pow(1.0 - dt, 2.0))
				dome_mesh.scale = Vector3(dr, dr * 0.09, dr)
				dome_mat.set_shader_parameter("intensity", 0.20 * pow(1.0 - dt, 2.2))

		# 2b. Bright additive leading edge, gone in a fifth of a second.
		if flash_mesh != null and flash_mat != null:
			var ft2 := clampf(_t / 0.22, 0.0, 1.0)
			if ft2 >= 1.0:
				flash_mesh.visible = false
			else:
				var fr := lerpf(1.6, 9.0 * scale_factor, 1.0 - pow(1.0 - ft2, 2.4))
				flash_mesh.scale = Vector3(fr, fr, 1.0)
				flash_mat.albedo_color.a = 0.20 * pow(1.0 - ft2, 1.8)

		# 3. FireballCore: hot white-orange (0..0.4 s) -> billowing smoke mushroom (0.4..1.5 s)
		if core_mesh != null and core_mat != null:
			var ft := clampf(_t / 1.45, 0.0, 1.0)
			if ft >= 1.0:
				core_mesh.visible = false
			else:
				var phase_fire := clampf(_t / 0.40, 0.0, 1.0)
				var cr := lerpf(0.9, 4.0 * scale_factor, 1.0 - pow(1.0 - ft, 2.1))
				# Keep the detonation a fireball, not a vertical torch: the
				# rising column is made by the smoke plume and flame billboards.
				core_mesh.scale = Vector3(cr, cr * (1.0 + ft * 0.10), cr)
				core_mesh.position.y = lerpf(0.2, 2.6 * scale_factor, ft)
				if phase_fire < 1.0:
					var c1 := Color(1.0, 0.96, 0.78).lerp(Color(1.0, 0.46, 0.09), phase_fire)
					c1.a = lerpf(0.95, 0.78, phase_fire)
					core_mat.albedo_color = c1
				else:
					var st := ( _t - 0.40 ) / 1.05
					var c2 := Color(1.0, 0.46, 0.09).lerp(Color(0.18, 0.17, 0.17), clampf(st * 1.4, 0.0, 1.0))
					c2.a = 0.76 * (1.0 - clampf(st, 0.0, 1.0))
					core_mat.albedo_color = c2

		# 3b. White-hot ignition flash, gone before the smoke takes over.
		if hot_mesh != null and hot_mat != null:
			var ht := clampf(_t / 0.30, 0.0, 1.0)
			if ht >= 1.0:
				hot_mesh.visible = false
			else:
				var hr := lerpf(0.6, 2.8 * scale_factor, 1.0 - pow(1.0 - ht, 2.0))
				hot_mesh.scale = Vector3.ONE * hr
				hot_mesh.position.y = 0.4 + ht * 1.1
				hot_mat.albedo_color = Color(1.0, lerpf(0.97, 0.52, ht),
						lerpf(0.82, 0.16, ht), 1.0 - ht)

		# 4. Ballistic DebrisChunks (settle on local_ground_y and free cleanly by ~3.2 s)
		if debris_mmi != null and is_instance_valid(debris_mmi) and debris_mmi.multimesh != null:
			if _t > 3.2:
				debris_mmi.visible = false
				debris_mmi.queue_free()
				debris_mmi = null
			else:
				var mm := debris_mmi.multimesh
				var fade := clampf(1.0 - (_t - 2.3) / 0.9, 0.0, 1.0) if _t > 2.3 else 1.0
				for i in range(chunk_pos.size()):
					var vel := chunk_vel[i]
					var p := chunk_pos[i]
					if p.y > local_ground_y or vel.y > 0.0:
						vel.y -= 20.0 * delta
						p += vel * delta
						if p.y <= local_ground_y:
							p.y = local_ground_y
							if absf(vel.y) < 1.2:
								vel = Vector3.ZERO
								chunk_spin[i] = Vector3.ZERO
							else:
								vel.y = absf(vel.y) * 0.25
								vel.x *= 0.55
								vel.z *= 0.55
					chunk_pos[i] = p
					chunk_vel[i] = vel
					if chunk_spin[i] != Vector3.ZERO:
						chunk_rot[i] += chunk_spin[i] * delta
					var sc := chunk_scale[i] * fade
					mm.set_instance_transform(i, Transform3D(Basis.from_euler(chunk_rot[i]).scaled(chunk_shape[i] * sc), p))
## Cap simultaneous burning wrecks; a large chaos battle must not end up with
## dozens of continuous particle systems and lights.
static func _scene_wind(node: Node) -> Vector3:
	var tree: SceneTree = null
	if node != null and node.is_inside_tree():
		tree = node.get_tree()
	if tree == null:
		tree = Engine.get_main_loop() as SceneTree
	var raw: Variant = null
	if tree != null and tree.current_scene != null:
		raw = tree.current_scene.get("_current_wind_vector")
	if not (raw is Vector3) and node != null:
		raw = node.get("_current_wind_vector")
	if raw is Vector3:
		var w := raw as Vector3
		return Vector3(w.x, 0.0, w.z)
	return Vector3.ZERO


static func _resolve_ground_y(parent: Node, pos: Vector3) -> float:
	if parent is Node3D:
		var w3d := (parent as Node3D).get_world_3d()
		if w3d != null and w3d.direct_space_state != null:
			var q := PhysicsRayQueryParameters3D.create(
					pos + Vector3.UP * 1.0,
					pos + Vector3.DOWN * 80.0)
			q.collision_mask = 1
			q.collide_with_bodies = true
			q.collide_with_areas = false
			var hit := w3d.direct_space_state.intersect_ray(q)
			if not hit.is_empty():
				return (hit["position"] as Vector3).y
	var tree := parent.get_tree() if parent != null and parent.is_inside_tree() else Engine.get_main_loop() as SceneTree
	var scene := tree.current_scene if tree != null else null
	if scene != null and scene.has_method("_find_ground_y"):
		return float(scene.call("_find_ground_y", pos.x, pos.z))
	return pos.y


static func _low_quality() -> bool:
	return QualityManager.get_active_level() == QualityManager.Level.LOW


static func _char_material() -> StandardMaterial3D:
	if _char_mat == null:
		_char_mat = StandardMaterial3D.new()
		_char_mat.albedo_color = Color(0.12, 0.105, 0.09)
		_char_mat.roughness = 0.98
		_char_mat.metallic = 0.06
	return _char_mat


static func _texture(kind: String) -> Texture2D:
	match kind:
		"spark":
			if _spark_tex == null:
				_spark_tex = _radial([
					Color(1.0, 1.0, 0.92, 1.0),
					Color(1.0, 0.58, 0.12, 0.9),
					Color(1.0, 0.20, 0.02, 0.0),
				])
			return _spark_tex
		"flame":
			return _flame_texture()
		"dust":
			if _dust_tex == null:
				_dust_tex = _radial([
					Color(0.82, 0.70, 0.50, 0.65),
					Color(0.48, 0.38, 0.25, 0.25),
					Color(0.20, 0.15, 0.10, 0.0),
				])
			return _dust_tex
		_:
			if _smoke_tex == null:
				_smoke_tex = _radial([
					Color(0.72, 0.70, 0.66, 0.62),
					Color(0.38, 0.37, 0.35, 0.28),
					Color(0.12, 0.12, 0.12, 0.0),
				])
			return _smoke_tex


## Organic flame sprite.  The old version drew a clean pointed cone, which is
## why every particle looked like a burning triangle.  This one is a soft,
## noise-warped tongue: rounded bright base, turbulent edges, a hot white core
## and a smoky red tip.  Still one cached 64x64 texture, no flipbook.
static func _flame_texture() -> ImageTexture:
	if _flame_tex != null:
		return _flame_tex
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var phase_a := rng.randf_range(0.0, TAU)
	var phase_b := rng.randf_range(0.0, TAU)
	for y in range(size):
		# v = 0 at the image BOTTOM (base), 1 at the TOP (tip).
		var v := 1.0 - float(y) / float(size - 1)
		for x in range(size):
			var u := (float(x) + 0.5 - float(size) * 0.5) / (float(size) * 0.5)
			# A turbulent, rounded blob - no straight tapering edges.
			var turb := sin(v * 8.0 + u * 4.5 + phase_a) * 0.055 \
					+ sin(v * 14.0 - u * 7.0 + phase_b) * 0.035
			var du := u - turb
			var rx := 0.42 - 0.18 * v
			var rp := sqrt((du / rx) * (du / rx)
					+ ((v - 0.44) / 0.50) * ((v - 0.44) / 0.50))
			var a := 1.0 - smoothstep(0.52, 1.02, rp)
			a *= 1.0 - smoothstep(0.66, 1.0, v)
			a *= 0.55 + 0.45 * smoothstep(0.0, 0.16, v)
			a = clampf(a, 0.0, 1.0)
			a *= a
			# Hot lower core -> orange body -> dark smoky tip.
			var heat := clampf(1.15 - rp * 0.85 - v * 0.30, 0.0, 1.0)
			var col := Color(0.42, 0.04, 0.01).lerp(
					Color(1.0, 0.38, 0.03), clampf(heat * 1.8, 0.0, 1.0))
			col = col.lerp(Color(1.0, 0.96, 0.74),
					clampf((heat - 0.48) * 2.4, 0.0, 1.0))
			col.a = a
			img.set_pixel(x, y, col)
	_flame_tex = ImageTexture.create_from_image(img)
	return _flame_tex


static func _radial(colors: Array) -> GradientTexture2D:
	var grad := Gradient.new()
	var offsets := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in range(colors.size()):
		offsets.append(float(i) / float(maxi(colors.size() - 1, 1)))
		cols.append(colors[i] as Color)
	grad.offsets = offsets
	grad.colors = cols
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	return tex


## ------------------------------- hit ---------------------------------------
static func hit(parent: Node, unit: Node3D, pos: Vector3, kind: String = "vehicle",
		power: float = 1.0) -> void:
	if parent == null or not is_instance_valid(parent) or unit == null:
		return
	# Infantry: the proper rig already has a flinch animation; keep the hit
	# readable with a small ground puff instead of a fireball-sized spark halo.
	if kind == "infantry":
		if unit.has_method("hit_react"):
			unit.hit_react(true)
		_jolt(unit, 0.45)
		var foot := unit.global_position
		_dust(parent, Vector3(foot.x, foot.y + 0.12, foot.z), 3)
		return
	_sparks(parent, pos, int(10.0 * (0.6 + 0.4 * power)))
	_flash(parent, pos, 0.8 * power, Color(1.0, 0.72, 0.30))
	_jolt(unit, 0.9 * power)
	_hit_overlay(unit)
	if unit.has_method("hit_react"):
		unit.hit_react(true)
	# A tank hit throws more metal; a truck hit burns with a dirtier flash.
	if kind == "tank":
		_sparks(parent, pos, 10)
	elif kind == "truck":
		_flash(parent, pos, 0.6, Color(1.0, 0.46, 0.12))


## Short additive flash on the hull itself so the player sees *what* was hit,
## not only a spark burst in the air next to it.
static func _hit_overlay(unit: Node3D) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.0, 0.88, 0.62, 0.16)
	var mesh_refs: Array = []
	for node in unit.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi != null:
			mi.material_overlay = mat
			mesh_refs.append(weakref(mi))
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = 0.14
	unit.add_child(timer)
	timer.timeout.connect(func() -> void:
		for r in mesh_refs:
			var mi := (r as WeakRef).get_ref() as MeshInstance3D
			if mi != null and is_instance_valid(mi) and mi.material_overlay == mat:
				mi.material_overlay = null
		if is_instance_valid(timer):
			timer.queue_free())
	timer.start()


static func _jolt(unit: Node3D, power: float) -> void:
	if not is_instance_valid(unit):
		return
	var base_rot := unit.rotation
	var tw := unit.create_tween()
	tw.tween_property(unit, "rotation:z", base_rot.z + 0.055 * power, 0.06)
	tw.tween_property(unit, "rotation:z", base_rot.z, 0.16)
	tw.parallel().tween_property(unit, "position", unit.position + Vector3(
			randf_range(-0.08, 0.08), 0.03, randf_range(-0.08, 0.08)) * power, 0.06)
	tw.tween_property(unit, "position", unit.position, 0.18)


## ----------------------------- destruction ---------------------------------
## kind: tank/bmp/apc/truck/sam/heli/shahed/infantry/vehicle
## Largest visual AABB dimension of a unit. Pure read, no allocation per frame.
static func _unit_extent(unit: Node3D) -> float:
	if not is_instance_valid(unit):
		return 6.0
	var best := 0.0
	for n in unit.find_children("*", "VisualInstance3D", true, false):
		var vi := n as VisualInstance3D
		if vi == null:
			continue
		var b: AABB = vi.global_transform * vi.get_aabb()
		best = maxf(best, maxf(b.size.x, maxf(b.size.y, b.size.z)))
	return best


static func destroy(parent: Node, unit: Node3D, kind: String = "vehicle",
		ground_y: float = 0.0, options: Dictionary = {}) -> void:
	if parent == null or not is_instance_valid(parent) or unit == null:
		return
	var do_char: bool = bool(options.get("char_unit", true))
	var do_move: bool = bool(options.get("move_unit", true))
	var do_burn: bool = bool(options.get("burn", true))
	var do_debris: bool = bool(options.get("debris", true))
	# Real silhouette extent drives every effect size: a Shahed must not burn
	# like an Apache, and a soldier must not burn like a tank.
	var extent := _unit_extent(unit)
	var pos := unit.global_position
	if kind == "infantry":
		# The fallen figure is only ~0.3 m tall; a 1 m offset floated the
		# fireball and every child effect above the body.
		pos += Vector3.UP * 0.10
	elif kind == "heli" or kind == "shahed":
		pos += Vector3.UP * 0.8
	else:
		pos += Vector3.UP * 1.2
	if do_char:
		_char(unit)
	if kind == "infantry":
		_flash(parent, pos, 4.2, Color(1.0, 0.62, 0.18))
		_shockwave(parent, Vector3(pos.x, maxf(ground_y + 0.08, pos.y - 1.0), pos.z), 2.0)
		_fireball(parent, pos, kind)
		if do_debris:
			_spawn_debris(parent, pos, kind)
	else:
		var scale_f := clampf(extent / 7.5, 0.45, 2.4)
		var aerial := (kind == "heli" or kind == "shahed")
		spawn_multiphase_explosion(parent, pos, scale_f, ground_y, aerial)
		_flash(parent, pos, 4.5, Color(1.0, 0.62, 0.18))
	# Secondary cook-off: ammunition / fuel cooking a moment after the hit.
	var parent_ref: WeakRef = weakref(parent)
	for delay in [0.42, 0.85]:
		var t := Timer.new()
		t.one_shot = true
		t.wait_time = delay
		parent.add_child(t)
		t.timeout.connect(func() -> void:
			var p := parent_ref.get_ref() as Node
			if p != null and is_instance_valid(p):
				var off := Vector3(randf_range(-1.2, 1.2), randf_range(0.2, 1.0),
						randf_range(-1.2, 1.2))
				_flash(p, pos + off, 1.8, Color(1.0, 0.55, 0.12))
				_sparks(p, pos + off, 8 if _low_quality() else 12)
				_dust(p, pos + off, 4 if _low_quality() else 6)
			if is_instance_valid(t):
				t.queue_free())
		t.start()

	if kind == "heli" or kind == "shahed":
		if do_move:
			_aerial_fall(parent, unit, kind, ground_y, pos)
		# The plume must not be created here: for aerial targets burn() is
		# called on impact by _aerial_fall() (or by the live Vehicle.impact()),
		# otherwise a flame stays stranded at the hit altitude.
	elif kind == "infantry":
		# Use the proper rigged soldier model, but fall the whole rig instead
		# of the rig's internal death pose (the latter clips through the floor
		# in this standalone preview).
		if do_move:
			_collapse_infantry(unit)
		if do_burn:
			burn(unit, pos, kind, 5.0, ground_y)
	else:
		if do_move:
			_collapse(unit)
		if do_burn:
			burn(unit, pos, kind, 22.0, ground_y)


## Shared flipbook plume quad. One draw call, no particle simulation.
static func _plume(parent: Node3D, name: String, width: float, height: float) -> MeshInstance3D:
	var fire := MeshInstance3D.new()
	fire.name = name
	var fquad := QuadMesh.new()
	fquad.size = Vector2(width, height)
	var fmat := ShaderMaterial.new()
	fmat.shader = _get_flame_shader()
	fmat.set_shader_parameter("flame_atlas", flame_atlas())
	fmat.set_shader_parameter("seed_offset", randf() * 64.0)
	fquad.material = fmat
	fire.mesh = fquad
	fire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(fire)
	return fire


## Burning trail attached to a falling airframe.  Used by the live Vehicle
## crash path so the approved preview look matches the game.
static func trail(unit: Node3D) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var fire := _plume(unit, "CrashFire", 1.8, 3.0)
	fire.position = Vector3(0.0, 1.4, 0.0)
	_emitter(unit, "CrashSmoke", 18, 1.9, SMOKE_COLOR,
			_texture("smoke"), 0.5, 1.5, Vector3(0, 1.2, 0), 0.7, 1.6, false)


static func stop_trail(unit: Node3D) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	for n in unit.find_children("CrashFire", "MeshInstance3D", true, false):
		(n as MeshInstance3D).visible = false
	for n in unit.find_children("CrashSmoke", "GPUParticles3D", true, false):
		(n as GPUParticles3D).emitting = false


## Impact of an already-falling airframe: char, fireball, debris, burning
## wreck.  Does not move the unit; the live Vehicle keeps its physics fall.
static func impact(parent: Node, unit: Node3D, kind: String,
		ground_y: float) -> void:
	if parent == null or not is_instance_valid(parent) or unit == null:
		return
	var pos := unit.global_position + Vector3.UP * 0.9
	_char(unit)
	_flash(parent, pos, 5.0, Color(1.0, 0.58, 0.14))
	spawn_multiphase_explosion(parent, pos, 1.2, ground_y, false)
	burn(unit, pos, kind, 22.0, ground_y)


static func _char(unit: Node3D) -> void:
	if not is_instance_valid(unit):
		return
	var mat := _char_material()
	for node in unit.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi != null:
			# A dark charred override guarantees the burned-out look on every
			# imported material (some GLBs ignore material_overlay).
			mi.material_overlay = null
			mi.material_override = mat


static func _collapse(unit: Node3D) -> void:
	if not is_instance_valid(unit):
		return
	var tw := unit.create_tween()
	tw.set_parallel(true)
	tw.tween_property(unit, "position:y", unit.position.y - 0.34, 0.55)
	tw.tween_property(unit, "rotation:x", deg_to_rad(10.0), 0.55)
	tw.tween_property(unit, "rotation:z", deg_to_rad(-7.0), 0.55)
	tw.tween_property(unit, "scale", Vector3(1.03, 0.82, 1.03), 0.55)


static func _collapse_infantry(unit: Node3D) -> void:
	if not is_instance_valid(unit):
		return
	var tw := unit.create_tween()
	tw.set_parallel(true)
	# The caller places infantry on a ground-level pivot, so a ~90 deg X twist
	# lays the whole body flat. The Z roll makes the fall read as uncontrolled.
	tw.tween_property(unit, "rotation:x", deg_to_rad(88.0), 0.42) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(unit, "rotation:z", deg_to_rad(randf_range(-22.0, 22.0)), 0.42)
	# The gallery positions infantry on a pivot at its body centre (~0.93 m),
	# so the body has to come down by roughly half its height to lie on ground.
	tw.tween_property(unit, "position:y", unit.position.y - 0.80, 0.42)


static func _aerial_fall(parent: Node, unit: Node3D, kind: String, ground_y: float,
		impact_pos: Vector3) -> void:
	if not is_instance_valid(unit):
		return
	var fall := maxf(0.9, minf(3.2, (unit.global_position.y - ground_y) / 9.5))
	# One continuous flame quad follows the falling wreck - no particle trail.
	# Scale the trail to the airframe: an Apache burns far bigger than a Shahed.
	# The quad is billboarded around its centre, so lifting it by ~half its
	# height puts the hot base INSIDE the hull instead of hanging below it.
	var fs := clampf(_unit_extent(unit) / 12.0, 0.42, 1.35)
	var fh := 4.6 * fs
	var trail := _plume(unit, "CrashFire", 3.4 * fs, fh)
	trail.position = Vector3(0.0, fh * 0.55, 0.0)
	var smoke := _emitter(unit, "CrashSmoke", 18, 1.9, SMOKE_COLOR,
			_texture("smoke"), 0.5, 1.5, Vector3(0, 1.2, 0), 0.7, 1.6, false)
	var tw := unit.create_tween()
	tw.set_parallel(true)
	tw.tween_property(unit, "global_position:y", ground_y + 0.22, fall)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(unit, "rotation:x", deg_to_rad(38.0), fall)
	tw.tween_property(unit, "rotation:y", unit.rotation.y + randf_range(4.0, 8.0), fall)
	tw.tween_property(unit, "rotation:z", deg_to_rad(randf_range(-24.0, 24.0)), fall)
	tw.finished.connect(func() -> void:
		if not is_instance_valid(unit):
			return
		if is_instance_valid(trail):
			trail.visible = false
		if is_instance_valid(smoke):
			smoke.emitting = false
		var p := unit.global_position + Vector3.UP * 0.5
		_flash(parent, p, 5.0, Color(1.0, 0.58, 0.14))
		_shockwave(parent, Vector3(p.x, ground_y + 0.08, p.z), 10.0)
		_fireball(parent, p, kind)
		_spawn_debris(parent, p, kind)
		burn(unit, p, kind, 22.0, ground_y)
		print("[DESTRUCTION] ", kind, " impacted at ", p))
	# The wreck keeps a little forward drift even with the tween.
	unit.rotation.y += 0.01


## ------------------------------- fire --------------------------------------
static func burn(unit: Node3D, pos: Vector3, kind: String, duration: float,
		ground_y: float = 0.0) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	if _active_burns >= MAX_ACTIVE_BURNS:
		return
	_active_burns += 1
	# Infantry: a small smoke wisp next to the body, not a bonfire that hides
	# the death pose.  Vehicles get the full burning wreck.
	if kind == "infantry":
		var wisp := Node3D.new()
		wisp.name = "BurnAnchor"
		wisp.position = Vector3(0.0, 0.10, 0.0)
		wisp.tree_exiting.connect(_on_burn_exiting, CONNECT_ONE_SHOT)
		unit.add_child(wisp)
		var smoke := _emitter(wisp, "WreckSmoke", 5, 1.8, SMOKE_COLOR,
				_texture("smoke"), 0.2, 0.7, Vector3(0, 0.8, 0),
				0.12, 0.30, false)
		var timer := Timer.new()
		timer.one_shot = true
		timer.wait_time = 2.2
		wisp.add_child(timer)
		timer.timeout.connect(func() -> void:
			if is_instance_valid(smoke):
				smoke.emitting = false
			if is_instance_valid(wisp):
				wisp.queue_free())
		timer.start()
		return
	# Fire scales with the wreck's real silhouette, not with a hard-coded class.
	var s := clampf(_unit_extent(unit) / 8.0, 0.30, 1.8)
	var is_inf := kind == "infantry"
	if is_inf:
		s = 0.65
	var anchor := Node3D.new()
	anchor.name = "BurnAnchor"
	anchor.tree_exiting.connect(_on_burn_exiting, CONNECT_ONE_SHOT)
	var host: Node = unit.get_parent() if unit.get_parent() != null else unit
	if kind == "heli" or kind == "shahed":
		# A crashed airframe lies on its side; a local-space flame would be
		# buried inside the hull.  Anchor the plume above the wreck in world
		# space instead.
		host.add_child(anchor)
		anchor.global_position = unit.global_position + Vector3.UP * (
				2.0 if kind == "heli" else 0.7)
	elif is_inf:
		# The infantry pivot is rotated ~90 deg on collapse, so a local-space
		# anchor would slide sideways out of the body. Pin the flame in world
		# space just above the fallen figure instead.
		host.add_child(anchor)
		# Ground-locked to the body's footprint: the death pivot keeps spinning
		# for a moment, so a unit-relative anchor would trail off the corpse.
		anchor.global_position = Vector3(pos.x, ground_y + 0.02, pos.z)
	else:
		unit.add_child(anchor)
		anchor.position = Vector3(0.0, 1.25, 0.0)
	# One continuous flipbook flame instead of a stack of identical sprites.
	var fire := _plume(anchor, "WreckFire", 2.6 * s, (2.1 if is_inf else 3.0) * s)
	fire.position = Vector3(0.0, (0.0 if is_inf else 1.6) * s, 0.0)
	var fire_flick := fire.create_tween().set_loops(int(maxf(1.0, duration / 0.22)))
	fire_flick.tween_property(fire, "scale:y", 1.10, 0.11)
	fire_flick.tween_property(fire, "scale:y", 0.92, 0.11)
	var smoke := _emitter(anchor, "WreckSmoke", int(22 * (0.55 if _low_quality() else 1.0)),
			2.4, SMOKE_COLOR, _texture("smoke"), 0.4, 1.4, Vector3(0, 1.8, 0),
			0.9 * s, 2.2 * s, false)
	# A handful of rising embers makes the fire feel alive; still one cached
	# texture and one GPU particle draw, disabled on LOW beyond 6 small sparks.
	var embers := _emitter(anchor, "WreckEmbers", 6 if _low_quality() else 12, 1.6,
			Color(1.0, 0.46, 0.10, 1.0), _texture("spark"), 1.8, 4.5,
			Vector3(0, -1.6, 0), 0.04, 0.11, true)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.48, 0.12)
	light.light_energy = 1.6 * s
	light.omni_range = 9.0 * s
	light.shadow_enabled = false
	light.position = Vector3(0, 1.0, 0)
	anchor.add_child(light)
	var flick := anchor.create_tween().set_loops(int(maxf(1.0, duration / 0.18)))
	flick.tween_property(light, "light_energy", 0.75 * s, 0.09)
	flick.tween_property(light, "light_energy", 1.55 * s, 0.09)
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = maxf(1.0, duration)
	anchor.add_child(timer)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(fire):
			fire.visible = false
		if is_instance_valid(smoke):
			smoke.emitting = false
		if is_instance_valid(anchor):
			anchor.queue_free())
	timer.start()


## ----------------------------- particles -----------------------------------
static func _emitter(parent: Node3D, name: String, amount: int, lifetime: float,
		color: Color, tex: Texture2D, speed_min: float, speed_max: float,
		gravity: Vector3, size_min: float, size_max: float,
		additive: bool) -> GPUParticles3D:
	if not _can_spawn_particles(1):
		return null
	var p := GPUParticles3D.new()
	p.name = name
	p.amount = amount
	p.lifetime = lifetime
	p.randomness = 0.45
	p.fixed_fps = 30
	p.local_coords = false
	p.emitting = true
	p.visibility_aabb = AABB(Vector3(-36, -24, -36), Vector3(72, 60, 72))
	var apply_wind := name.contains("Smoke") or tex == _texture("smoke") or tex == _texture("dust")
	var is_flame := (tex == _flame_texture())
	var wind := _scene_wind(parent) if apply_wind else Vector3.ZERO
	var wind_speed := wind.length()
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.45
	mat.direction = (Vector3(0, 1, 0) + wind * 0.16).normalized()
	mat.spread = 26.0
	mat.initial_velocity_min = speed_min + wind_speed * 0.20
	mat.initial_velocity_max = speed_max + wind_speed * 0.35
	mat.gravity = gravity + Vector3(wind.x, 0.0, wind.z) * 0.45
	mat.damping_min = 1.0
	mat.damping_max = 2.6
	mat.scale_min = size_min
	mat.scale_max = size_max
	mat.color = color
	# Smoke and dust tumble freely; flames stay upright with only a gentle
	# flicker.  Random 360-degree spin was what turned each flame into a
	# recognizable spinning triangle.
	if is_flame:
		mat.angle_min = -0.16
		mat.angle_max = 0.16
		mat.angular_velocity_min = -14.0
		mat.angular_velocity_max = 14.0
	else:
		mat.angle_min = 0.0
		mat.angle_max = TAU
		mat.angular_velocity_min = -120.0
		mat.angular_velocity_max = 120.0
	# Fade each particle out and shrink it near the end of its life instead of
	# popping it out at full size; this is what separates fire from balloons.
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(0.45, 0.85))
	curve.add_point(Vector2(1.0, 0.10))
	var curve_tex := CurveTexture.new()
	curve_tex.curve = curve
	mat.scale_curve = curve_tex
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	ramp.colors = PackedColorArray([
		Color(color.r, color.g, color.b, color.a),
		Color(color.r * 0.8, color.g * 0.6, color.b * 0.45, color.a * 0.55),
		Color(color.r * 0.4, color.g * 0.35, color.b * 0.3, 0.0),
	])
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	mat.color_ramp = ramp_tex
	p.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	if is_flame:
		# Real animated fire: turbulence + rising motion computed per pixel.
		# The shader billboards itself, so no StandardMaterial3D is needed.
		var fm := ShaderMaterial.new()
		fm.shader = _get_flame_shader()
		fm.set_shader_parameter("flame_atlas", flame_atlas())
		fm.set_shader_parameter("seed_offset", randf() * 64.0)
		quad.material = fm
	else:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.albedo_texture = tex
		m.albedo_color = Color.WHITE
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.vertex_color_use_as_albedo = true
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
		quad.material = m
	p.draw_pass_1 = quad
	parent.add_child(p)
	_track_particle_system(p)
	return p


static func _sparks(parent: Node, pos: Vector3, amount: int) -> void:
	_burst(parent, pos, mini(amount, 6), 0.28, Color(1.0, 0.66, 0.20, 1.0),
			_texture("spark"), 3.0, 7.0, Vector3(0, -9.0, 0), 0.012, 0.032, false)


## A compact fireball built from three independent billboard bursts: hot core,
## rolling smoke and metal sparks.  This replaces the imported Binbun VFX in
## the gallery so every class shares one readable style.
static func _fireball(parent: Node, pos: Vector3, kind: String) -> void:
	var s := 0.55 if kind == "infantry" else 1.0
	var q := 0.55 if _low_quality() else 1.0
	_burst(parent, pos, int(58 * s * q), 0.55, Color(1.0, 0.82, 0.42, 1.0),
			_texture("flame"), 2.6, 8.2, Vector3(0, 3.6, 0), 0.16, 0.52, false)
	_burst(parent, pos + Vector3.UP * 0.5, int(26 * s * q), 2.4,
			Color(0.26, 0.25, 0.23, 0.55), _texture("smoke"),
			0.5, 1.9, Vector3(0, 1.5, 0), 0.80, 1.9, false)
	_burst(parent, pos + Vector3.UP * 0.3, int(16 * s * q), 1.1,
			Color(0.55, 0.46, 0.33, 0.55), _texture("dust"),
			1.2, 3.6, Vector3(0, -1.5, 0), 0.35, 0.9, false)
	_sparks(parent, pos + Vector3.UP * 0.5, int(18 * s * q))


static func _dust(parent: Node, pos: Vector3, amount: int) -> void:
	_burst(parent, pos, amount, 1.0, DUST_COLOR, _texture("dust"),
			1.0, 3.4, Vector3(0, -1.6, 0), 0.35, 0.85, false)


static func _burst(parent: Node, pos: Vector3, amount: int, lifetime: float,
		color: Color, tex: Texture2D, speed_min: float, speed_max: float,
		gravity: Vector3, size_min: float, size_max: float,
		additive: bool) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.global_position = pos
	var p := _emitter(holder, "Burst", amount, lifetime, color, tex,
			speed_min, speed_max, gravity, size_min, size_max, additive)
	if p == null:
		holder.queue_free()
		return
	p.one_shot = true
	p.explosiveness = 1.0
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = lifetime + 0.6
	holder.add_child(timer)
	timer.timeout.connect(holder.queue_free)
	timer.start()


static func _flash(parent: Node, pos: Vector3, radius: float, color: Color) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 4.0
	light.omni_range = radius * 3.2
	light.shadow_enabled = false
	parent.add_child(light)
	light.global_position = pos
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.28)
	tw.tween_callback(light.queue_free)


static func _shockwave(parent: Node, pos: Vector3, radius: float) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.94
	torus.outer_radius = 1.0
	torus.rings = 24
	torus.ring_segments = 6
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.88, 0.66, 0.36, 0.12)
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(ring)
	ring.global_position = pos
	ring.scale = Vector3.ONE * 0.4
	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(radius, 0.10, radius), 0.55)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.55)
	tw.chain().tween_callback(ring.queue_free)
	# Wider, darker dust ring that lingers behind the flash ring.
	var dust := MeshInstance3D.new()
	var dtorus := TorusMesh.new()
	dtorus.inner_radius = 0.94
	dtorus.outer_radius = 1.0
	dtorus.rings = 20
	dtorus.ring_segments = 5
	dust.mesh = dtorus
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.albedo_color = Color(0.30, 0.27, 0.22, 0.30)
	dust.material_override = dmat
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(dust)
	dust.global_position = pos
	dust.scale = Vector3.ONE * 0.4
	var dw := dust.create_tween()
	dw.set_parallel(true)
	dw.tween_property(dust, "scale", Vector3(radius * 1.3, 0.12, radius * 1.3), 0.8)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	dw.tween_property(dmat, "albedo_color:a", 0.0, 0.8)
	dw.chain().tween_callback(dust.queue_free)


## ------------------------------- debris ------------------------------------
static func _spawn_debris(parent: Node, pos: Vector3, kind: String) -> void:
	var mats: Array[StandardMaterial3D] = []
	var olive := StandardMaterial3D.new()
	olive.albedo_color = Color(0.24, 0.27, 0.17)
	olive.roughness = 0.85
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.09, 0.09, 0.08)
	dark.roughness = 0.9
	var rust := StandardMaterial3D.new()
	rust.albedo_color = Color(0.40, 0.24, 0.14)
	rust.roughness = 0.9
	mats = [olive, dark, rust]
	var count := 9
	if kind == "tank":
		count = 15
	elif kind == "heli":
		count = 14
	elif kind == "shahed":
		count = 8
	elif kind == "infantry":
		count = 3
	if _low_quality():
		count = maxi(3, int(float(count) * 0.5))
	for i in range(count):
		var piece := RigidBody3D.new()
		piece.mass = 3.0
		var mi := MeshInstance3D.new()
		var s := Vector3(randf_range(0.18, 0.55), randf_range(0.10, 0.28),
				randf_range(0.25, 0.85))
		mi.mesh = debris_mesh()
		# The cached shard is ~0.34 units across; scale it to the old box size.
		mi.scale = s / Vector3(0.34, 0.22, 0.28)
		mi.material_override = mats[randi() % mats.size()]
		piece.add_child(mi)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = s
		cs.shape = bs
		piece.add_child(cs)
		parent.add_child(piece)
		piece.global_position = pos + Vector3(randf_range(-0.7, 0.7),
				randf_range(0.0, 0.9), randf_range(-0.7, 0.7))
		piece.apply_central_impulse(Vector3(randf_range(-6.0, 6.0),
				randf_range(5.0, 13.0), randf_range(-6.0, 6.0)) * (2.0 + float(i % 3)))
		piece.angular_velocity = Vector3(randf_range(-9, 9), randf_range(-9, 9),
				randf_range(-9, 9))
		var timer := Timer.new()
		timer.one_shot = true
		timer.wait_time = 9.0
		piece.add_child(timer)
		timer.timeout.connect(piece.queue_free)
		timer.start()
