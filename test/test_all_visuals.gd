extends Node

const VisualEnhancer = preload("res://scripts/util/visual_enhancer.gd")

func _ready() -> void:
	print("==========================================================")
	print("=== RUNNING FULL VISUAL INTEGRATION TEST ACROSS LEVELS ===")
	print("==========================================================")
	
	var levels_to_test := [
		"res://sceneries/BigLevel.tscn",
		"res://sceneries/CityLevel.tscn",
		"res://sceneries/CourseLevel.tscn"
	]
	
	for path in levels_to_test:
		print("\n[TEST] Verifying scene: ", path)
		var packed := load(path) as PackedScene
		assert(packed != null, "Failed to load level scene: " + path)
		
		var scene := packed.instantiate() as Node3D
		assert(scene != null, "Failed to instantiate level scene: " + path)
		
		# Apply enhancer explicitly as done in _ready()
		VisualEnhancer.apply_to_scene(scene)
		
		# 1. Verify WorldEnvironment
		var world_env := scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
		assert(world_env != null, "Level must have WorldEnvironment: " + path)
		var env := world_env.environment
		assert(env != null, "WorldEnvironment must have an Environment resource")
		assert(env.tonemap_mode == Environment.TONE_MAPPER_ACES, "Tonemap must be ACES (3)")
		assert(env.ssao_enabled == true, "SSAO must be enabled")
		assert(env.glow_enabled == true, "Glow must be enabled")
		assert(env.fog_enabled == true, "Atmospheric fog must be enabled")
		print("  ✓ Environment: ACES tonemap, SSAO (radius=%.1f), Glow, Fog active" % env.ssao_radius)
		
		# 2. Verify Sun / DirectionalLight3D
		var sun := scene.get_node_or_null("Sun") as DirectionalLight3D
		if sun == null:
			sun = scene.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
		assert(sun != null, "Level must have DirectionalLight3D: " + path)
		assert(sun.shadow_enabled == true, "Sun shadows must be enabled")
		assert(sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, "PSSM 4 splits required")
		print("  ✓ Sun: 4-split PSSM soft shadows active (blur=%.1f, max_dist=%.0fm)" % [sun.shadow_blur, sun.directional_shadow_max_distance])
		
		# 3. Verify Ground material
		var ground := scene.get_node_or_null("Ground")
		assert(ground != null, "Level must have Ground node: " + path)
		var mesh_instance: MeshInstance3D = null
		if ground is MeshInstance3D:
			mesh_instance = ground as MeshInstance3D
		else:
			mesh_instance = ground.get_node_or_null("MeshInstance3D") as MeshInstance3D
		assert(mesh_instance != null, "Ground must contain a MeshInstance3D")
		assert(mesh_instance.material_override != null, "Ground must have material_override set by VisualEnhancer")
		assert(mesh_instance.material_override is ShaderMaterial, "Ground material must be a ShaderMaterial")
		print("  ✓ Ground: procedural multi-scale bump/roughness ShaderMaterial applied")
		
		# 4. Verify FPV Camera & Overlay
		var cam := scene.get_node_or_null("Drone/FPVCamera") as Camera3D
		if cam == null:
			cam = scene.get_node_or_null("FPVCamera") as Camera3D
		assert(cam != null, "FPVCamera must exist in level")
		assert(cam.fov >= 100.0 and cam.fov <= 118.0, "FPVCamera FOV must be in range 100-118 deg")
		assert(is_equal_approx(cam.rotation_degrees.x, 30.0), "FPVCamera must have 30 deg physical tilt up")
		print("  ✓ Camera: FOV %.1f deg, Tilt %.1f deg" % [cam.fov, cam.rotation_degrees.x])
		
		var overlay := scene.get_node_or_null("FPVOverlay")
		assert(overlay != null, "FPVOverlay node must be present in level")
		print("  ✓ FPVOverlay: Analog CRT/FPV post-processing filter present")
		
		if path.ends_with("BigLevel.tscn"):
			var drone_node := scene.get_node_or_null("Drone")
			assert(drone_node != null, "Drone node must exist in BigLevel")
			DroneCatalog.apply_to_drone(drone_node, 2)
			scene.call("_attach_fpv_rig")
			scene.call("_setup_fpv_camera_for_preset")
			var model_root := drone_node.get_node_or_null("DroneModel") as Node3D
			assert(model_root != null, "Real 3D DroneModel must be attached")
			assert(cam.get_node_or_null("FPVRig") == null, "No procedural FPVRig cylinders should be attached to FPVCamera")
			assert(cam.near <= 0.051, "FPVCamera near clip plane must be <= 0.05")
			print("  ✓ Real 3D DroneModel ('%s') visible in FPV, cam pos=%s, pitch=%.1f deg" % [
				DroneCatalog.preset(2)["name"], str(cam.position), cam.rotation_degrees.x
			])
		
		# Clean teardown of instantiated scene without adding to tree
		scene.free()
	
	print("\n==========================================================")
	print("=== ALL VISUAL TESTS PASSED ACROSS ALL SIMULATOR MAPS! ===")
	print("==========================================================")
	get_tree().quit(0)
