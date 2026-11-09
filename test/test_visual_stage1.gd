extends Node

const VisualEnhancer = preload("res://scripts/util/visual_enhancer.gd")

func _ready() -> void:
	print("==================================================")
	print("=== RUNNING VISUAL STAGE 1: ENVIRONMENT & LIGHTING ===")
	print("==================================================")
	
	# 1. Test Environment setup
	var env := Environment.new()
	VisualEnhancer.setup_world_environment(env)
	
	print("[TEST] Tonemap Mode: %d (Expected 3 = ACES)" % env.tonemap_mode)
	assert(env.tonemap_mode == Environment.TONE_MAPPER_ACES, "Tonemap must be ACES")
	assert(env.ssao_enabled == true, "SSAO must be enabled")
	assert(env.glow_enabled == true, "Glow must be enabled")
	assert(env.fog_enabled == true, "Atmospheric fog must be enabled")
	assert(env.sky != null, "Sky must be assigned")
	assert(env.sky.sky_material is PanoramaSkyMaterial or env.sky.sky_material is ProceduralSkyMaterial, "Sky material must be PanoramaSkyMaterial or ProceduralSkyMaterial")
	assert(env.ssil_enabled == true, "SSIL must be enabled")
	assert(env.volumetric_fog_enabled == true, "Volumetric fog must be enabled")
	
	if env.sky.sky_material is PanoramaSkyMaterial:
		print("[TEST] Sky: Poly Haven HDRI Skybox active (%s)" % (env.sky.sky_material as PanoramaSkyMaterial).panorama.resource_path)
	elif env.sky.sky_material is ProceduralSkyMaterial:
		var sky_mat := env.sky.sky_material as ProceduralSkyMaterial
		print("[TEST] Sky top color: %s, horizon: %s" % [sky_mat.sky_top_color, sky_mat.sky_horizon_color])
		assert(sky_mat.sky_top_color.b > sky_mat.sky_top_color.r, "Sky top color should be blue-dominant")
	
	# 2. Test DirectionalLight3D setup
	var sun := DirectionalLight3D.new()
	VisualEnhancer.setup_sun_lighting(sun)
	print("[TEST] Sun shadows: enabled=%s, mode=%d, blur=%.2f, blend_splits=%s" % [
		sun.shadow_enabled, sun.directional_shadow_mode, sun.shadow_blur, sun.directional_shadow_blend_splits
	])
	assert(sun.shadow_enabled == true, "Shadows must be enabled on Sun")
	assert(sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, "Shadow mode must be PSSM 4 splits")
	assert(sun.directional_shadow_blend_splits == true, "Shadow split blending must be true")
	assert(sun.shadow_blur > 1.0, "Shadow blur must be > 1.0 for soft shadows")
	
	# 3. Test BigLevel environment application
	var level_scene := load("res://sceneries/BigLevel.tscn") as PackedScene
	assert(level_scene != null, "BigLevel.tscn must load")
	var level := level_scene.instantiate() as Node3D
	
	var wenv := level.get_node_or_null("WorldEnvironment") as WorldEnvironment
	assert(wenv != null and wenv.environment != null, "BigLevel must have WorldEnvironment")
	VisualEnhancer.setup_world_environment(wenv.environment)
	assert(wenv.environment.tonemap_mode == Environment.TONE_MAPPER_ACES, "BigLevel environment tonemap must be ACES")
	assert(wenv.environment.ssao_enabled == true, "BigLevel SSAO must be active")
	
	level.free()
	sun.free()
	
	print("==================================================")
	print("=== VISUAL STAGE 1 TEST PASSED SUCCESSFULLY! ===")
	print("==================================================")
	get_tree().quit(0)
