extends Node

const VisualEnhancer = preload("res://scripts/util/visual_enhancer.gd")

func _ready() -> void:
	print("--- Running Test Visual Stage 3: FPV Camera & Post-Processing ---")
	
	# 1. Test Camera FOV & Clipping settings
	var cam := Camera3D.new()
	cam.fov = 75.0
	VisualEnhancer.enhance_camera(cam)
	
	assert(cam.fov >= 100.0 and cam.fov <= 118.0, "Camera FOV must be in range 100-118 deg")
	assert(is_equal_approx(cam.rotation_degrees.x, 30.0), "Camera tilt must be 30 deg")
	assert(cam.near <= 0.02, "Camera near clip must be <= 0.02")
	assert(cam.far >= 3000.0, "Camera far clip must be at least 3000.0")
	print("✓ Camera FOV verified: ", cam.fov, " deg, Tilt: ", cam.rotation_degrees.x, " deg, near: ", cam.near, ", far: ", cam.far)
	cam.free()
	
	# 2. Test FPV Overlay packed scene and shader parameters
	var overlay_scene := load("res://fpv/fpv_overlay.tscn") as PackedScene
	assert(overlay_scene != null, "fpv_overlay.tscn must be loadable")
	var overlay = overlay_scene.instantiate()
	assert(overlay != null, "fpv_overlay must instantiate")
	
	var rect := overlay.get_node_or_null("Overlay") as ColorRect
	assert(rect != null, "Overlay ColorRect must exist")
	assert(rect.material is ShaderMaterial, "Overlay material must be ShaderMaterial")
	
	var mat := rect.material as ShaderMaterial
	var aberration: float = mat.get_shader_parameter("aberration")
	var scanline_amount: float = mat.get_shader_parameter("scanline_amount")
	var noise_amount: float = mat.get_shader_parameter("noise_amount")
	var vignette_amount: float = mat.get_shader_parameter("vignette_amount")
	var barrel: float = mat.get_shader_parameter("barrel")
	
	print("  Overlay shader params: aberration=", aberration, ", scanlines=", scanline_amount, ", noise=", noise_amount, ", vignette=", vignette_amount, ", barrel=", barrel)
	assert(aberration >= 0.001 and aberration <= 0.01, "Chromatic aberration parameter out of range")
	assert(scanline_amount >= 0.05 and scanline_amount <= 0.25, "Scanline amount out of range")
	assert(noise_amount >= 0.01 and noise_amount <= 0.10, "Noise amount out of range")
	assert(vignette_amount >= 0.30 and vignette_amount <= 0.85, "Vignette amount out of range")
	assert(barrel >= 0.02 and barrel <= 0.10, "Barrel distortion parameter out of range")
	print("✓ Analog FPV shader parameters verified (scanlines, chromatic aberration, noise, vignette, barrel)")
	overlay.free()
	
	# 3. Test VisualEnhancer auto-adds FPVOverlay if missing from scene
	var mock_scene := Node3D.new()
	var mock_cam := Camera3D.new()
	mock_cam.name = "FPVCamera"
	mock_scene.add_child(mock_cam)
	
	assert(mock_scene.get_node_or_null("FPVOverlay") == null, "Should not have FPVOverlay initially")
	VisualEnhancer.apply_to_scene(mock_scene)
	
	assert(mock_scene.get_node_or_null("FPVOverlay") != null, "VisualEnhancer must inject FPVOverlay if absent")
	assert(is_equal_approx(mock_cam.fov, 110.0), "mock_cam FOV should be updated to 110.0 by apply_to_scene")
	assert(is_equal_approx(mock_cam.rotation_degrees.x, 30.0), "mock_cam tilt should be updated to 30.0 deg by apply_to_scene")
	print("✓ VisualEnhancer auto-injects FPVOverlay and configures FPVCamera successfully")
	
	mock_scene.free()
	
	print("=== VISUAL STAGE 3 TEST PASSED ===")
	get_tree().quit(0)
	get_tree().quit(0)
