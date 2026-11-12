class_name VisualEnhancer
extends RefCounted

## Standardizes photorealistic rendering across all simulator levels:
## 1. ACES Tonemapping & HDRI Skybox (Poly Haven partly cloudy sky).
## 2. SSAO (soft contact shadows), SSIL (indirect bounce), and Volumetric Fog.
## 3. DirectionalLight3D with 4096 shadow map & 4-split PSSM.
## 4. MultiMesh dense grass foliage & multi-scale PBR terrain.
## 5. 110° FOV Camera with 30° physical tilt up.

const QUALITY_MANAGER = preload("res://scripts/util/quality_manager.gd")
const MOTION_BLUR_SCRIPT = preload("res://scripts/util/motion_blur.gd")

static func setup_world_environment(env: Environment) -> void:
	if env == null:
		return
	
	# 1. Background & Sky: Authentic HDRI Skybox (Poly Haven) with Procedural fallback
	env.background_mode = Environment.BG_SKY
	if env.sky == null:
		env.sky = Sky.new()
	
	var hdr_path := "res://Assets/sky_cloudy_1k.hdr"
	var mobile_sky := OS.get_name() == "iOS" or OS.has_feature("mobile") \
			or OS.has_environment("MOBILE_UI")
	if ResourceLoader.exists(hdr_path):
		var pano_mat := PanoramaSkyMaterial.new()
		pano_mat.panorama = load(hdr_path)
		env.sky.sky_material = pano_mat
		# The 1k panorama is not perfectly seamless. On phones, turn its seam
		# behind the usual starting heading instead of showing it down the nose.
		if mobile_sky and not OS.has_environment("QA_NO_MOBILE_SKY_ROTATION"):
			env.sky_rotation.y = PI
	elif not (env.sky.sky_material is ProceduralSkyMaterial):
		var sky_mat := ProceduralSkyMaterial.new()
		sky_mat.sky_top_color = Color(0.20, 0.42, 0.74, 1.0)
		sky_mat.sky_horizon_color = Color(0.72, 0.80, 0.88, 1.0)
		sky_mat.ground_bottom_color = Color(0.14, 0.13, 0.11, 1.0)
		sky_mat.ground_horizon_color = Color(0.52, 0.60, 0.66, 1.0)
		sky_mat.sun_angle_max = 28.0
		sky_mat.sun_curve = 0.08
		env.sky.sky_material = sky_mat
	
	# Ambient light from sky: keep the blue fill clearly below the sun so
	# surfaces get directional modelling instead of the flat, washed-out look.
	# The old 0.52/0.42 combination lifted every shadow to the same value as
	# the lit faces, which is why the outdoor maps read as a painted carpet.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.44
	env.ambient_light_energy = 0.62

	# 2. Tonemapping - ACES with a filmic white point and warm-key exposure.
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.02
	env.tonemap_white = 1.0
	# Slightly tame the HDR sky dome: the reference has a deep blue zenith and
	# only the clouds near the sun blow out, not the entire upper hemisphere.
	env.background_energy_multiplier = 0.72
	
	# 3. Screen Space Ambient Occlusion (SSAO) - soft contact shadows under bushes & structures
	# The Mobile renderer does not implement the screen-space stack; setting
	# these properties there only spams errors, and QualityManager disables
	# them on LOW/MEDIUM anyway.
	var mobile := RenderingServer.get_current_rendering_method() == "mobile"
	if not mobile:
		env.ssao_enabled = true
		env.ssao_radius = 1.2 # Calibrated in 1.0 - 1.5 range
		env.ssao_intensity = 2.2 # Calibrated in 2.0 - 3.0 range
		env.ssao_power = 1.6
		env.ssao_detail = 0.6
		env.ssao_horizon = 0.06

		# 4. Screen Space Indirect Lighting (SSIL) - grass indirect bounce on hulls & walls
		env.ssil_enabled = true
		env.ssil_radius = 4.0
		env.ssil_intensity = 1.0

		# 5. Volumetric Fog - the key to the reference look: visible light shafts
		# through tree lines, warm haze around the sun and depth separation.
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.0018
		env.volumetric_fog_albedo = Color(0.84, 0.87, 0.90, 1.0)
		env.volumetric_fog_emission = Color(0.01, 0.008, 0.005)
		env.volumetric_fog_emission_energy = 0.15
		env.volumetric_fog_anisotropy = 0.55
		env.volumetric_fog_length = 700.0
		env.volumetric_fog_sky_affect = 0.10
	
	# Analytic depth fog for the far backdrop.  Thin enough to keep the horizon
	# contrasty, but cool enough to separate the distance from the warm foreground.
	env.fog_enabled = true
	env.fog_light_color = Color(0.66, 0.74, 0.86, 1.0)
	env.fog_light_energy = 0.55
	env.fog_density = 0.00012
	env.fog_sky_affect = 0.06
	env.fog_depth_begin = 160.0
	env.fog_depth_end = 3400.0
	env.fog_aerial_perspective = 0.18
	
	# 6. Glow & post-process: gentle bloom only on the hottest highlights
	# (sunlit metal, windows, muzzle flashes), then filmic colour grading.
	env.glow_enabled = true
	env.glow_normalized = true
	env.glow_intensity = 0.30
	env.glow_bloom = 0.09
	env.glow_hdr_threshold = 1.05
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.00
	env.adjustment_contrast = 1.28
	env.adjustment_saturation = 1.05
	var grade := Gradient.new()
	grade.set_color(0, Color(0.84, 0.92, 1.04))
	grade.set_color(1, Color(1.04, 0.98, 0.90))
	grade.add_point(0.45, Color(0.99, 1.0, 1.0))
	grade.add_point(0.72, Color(1.02, 1.0, 0.96))
	var grade_tex := GradientTexture1D.new()
	grade_tex.gradient = grade
	grade_tex.width = 256
	# GradientTexture1D is not a valid colour-correction LUT in Godot 4 (it
	# produced a blown-out white frame); keep the neutral grade instead.
	env.adjustment_color_correction = null


static func setup_sun_lighting(sun: DirectionalLight3D) -> void:
	if sun == null:
		return
	
	# Warm late-afternoon key light: strong directional modelling, blue sky fill.
	# A lower sun angle produces long, readable shadows across the village and
	# reveals the PBR plaster/wood/brick instead of flat midday lighting.
	sun.rotation_degrees = Vector3(-26.0, 45.0, 0.0)
	sun.light_color = Color(1.0, 0.86, 0.70, 1.0)
	sun.light_energy = 2.80
	sun.light_indirect_energy = 0.92
	# God rays: the volumetric fog only shows light shafts when the light itself
	# contributes strongly to the fog volume.
	sun.light_volumetric_fog_energy = 3.0
	sun.light_specular = 0.85
	
	# High quality 4-split PSSM soft shadows
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_max_distance = 800.0
	sun.shadow_blur = 1.2
	sun.directional_shadow_split_1 = 0.04
	sun.directional_shadow_split_2 = 0.12
	sun.directional_shadow_split_3 = 0.35
	
	# Configure shadow atlas size to 4096 for sharp, flicker-free shadows
	RenderingServer.directional_shadow_atlas_set_size(4096, true)


static func enhance_ground(ground_node: Node) -> void:
	if ground_node == null:
		return
	var mat := preload("res://Assets/GroundMaterial.tres")
	if ground_node is MeshInstance3D:
		(ground_node as MeshInstance3D).material_override = mat
	for child in ground_node.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).material_override = mat


static func enhance_camera(cam: Camera3D) -> void:
	if cam == null:
		return
	# FOV in 100° – 115° range: 110.0° provides authentic wide peripheral speed sense
	cam.fov = 110.0
	cam.near = 0.002
	cam.far = 4000.0
	# Camera physically tilted up 30° unless overridden by a specific drone model mount
	cam.rotation_degrees.x = 30.0
	# Fixed filmic exposure: the reference look depends on deep, readable
	# shadows and a bright sky, which auto-exposure flattens away.  The ACES
	# tonemap in the Environment provides the highlight roll-off instead.
	var attrs := cam.attributes as CameraAttributesPractical
	if attrs == null:
		attrs = CameraAttributesPractical.new()
		cam.attributes = attrs
	attrs.auto_exposure_enabled = false
	attrs.exposure_multiplier = 1.0


static func apply_to_scene(scene_root: Node3D) -> void:
	if scene_root == null:
		return
	var world_env := scene_root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env != null:
		setup_world_environment(world_env.environment)
	var sun := scene_root.get_node_or_null("Sun") as DirectionalLight3D
	if sun == null:
		sun = scene_root.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if sun != null:
		setup_sun_lighting(sun)
	var ground := scene_root.get_node_or_null("Ground")
	if ground != null:
		enhance_ground(ground)
	
	# Enhance drone FPV camera with 110° FOV and 30° physical tilt
	var cam := scene_root.get_node_or_null("Drone/FPVCamera") as Camera3D
	if cam == null:
		cam = scene_root.get_node_or_null("FPVCamera") as Camera3D
	if cam != null:
		enhance_camera(cam)
	
	# Grass is spawned by BigLevel once the drone is placed on the terrain: it
	# knows the exact ground height and the per-map palette.  Spawning a second
	# cluster here used a hard-coded 100 m radius, which diluted the MultiMesh
	# to a few sparse clumps per 100 m2 and cost an extra round of raycasts.
	
	# Ensure authentic FPV post-processing overlay is present
	var overlay := scene_root.get_node_or_null("FPVOverlay")
	if overlay == null:
		var overlay_packed := load("res://fpv/fpv_overlay.tscn") as PackedScene
		if overlay_packed != null:
			var overlay_node = overlay_packed.instantiate()
			scene_root.add_child(overlay_node)
	
	# Screen-space motion blur: canvas pass above the 3D scene but below the
	# FPV analogue overlay and HUD, so the OSD stays razor sharp.
	if scene_root.get_node_or_null("MotionBlur") == null:
		var blur = MOTION_BLUR_SCRIPT.new()
		blur.name = "MotionBlur"
		scene_root.add_child(blur)

	# Floating dust caught in the light: the tiny specks that make the air feel
	# volumetric in the reference.  Emitted in camera space, so it follows the
	# drone without another world-space emitter to manage.
	if cam != null:
		_spawn_air_dust(cam)

	# Apply active graphics quality tier (LOW / MEDIUM / HIGH)
	QUALITY_MANAGER.apply_to_scene(scene_root)

	# Adaptive internal resolution keeps the 120 FPS target on weaker GPUs.
	if scene_root.get_node_or_null("PerformanceGovernor") == null:
		var governor = load("res://scripts/util/performance_governor.gd").new()
		governor.name = "PerformanceGovernor"
		scene_root.add_child(governor)
		governor.configure(QUALITY_MANAGER.params())


static func _spawn_air_dust(cam: Camera3D) -> void:
	if cam.get_node_or_null("AirDust") != null:
		return
	var particles := GPUParticles3D.new()
	particles.name = "AirDust"
	particles.amount = 44
	particles.lifetime = 7.0
	particles.preprocess = 3.0
	particles.local_coords = true
	particles.position = Vector3(0.0, 0.0, -1.8)
	particles.visibility_aabb = AABB(Vector3(-18.0, -9.0, -18.0), Vector3(36.0, 18.0, 36.0))
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(5.0, 2.5, 5.0)
	process.direction = Vector3(0.0, 0.2, 0.0)
	process.spread = 180.0
	process.initial_velocity_min = 0.02
	process.initial_velocity_max = 0.14
	process.gravity = Vector3(0.0, -0.012, 0.0)
	process.scale_min = 0.008
	process.scale_max = 0.022
	process.color = Color(1.0, 0.93, 0.78, 0.20)
	particles.process_material = process

	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _soft_dot_texture()
	mat.albedo_color = Color(1.0, 0.93, 0.78, 0.20)
	mat.disable_receive_shadows = true
	quad.material = mat
	particles.draw_pass_1 = quad
	cam.add_child(particles)
	particles.emitting = true


static func _soft_dot_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	gradient.add_point(0.28, Color(1, 1, 1, 0.72))
	gradient.add_point(0.62, Color(1, 1, 1, 0.22))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	return tex
