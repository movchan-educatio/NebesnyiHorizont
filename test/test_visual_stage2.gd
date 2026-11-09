extends Node

const VisualEnhancer = preload("res://scripts/util/visual_enhancer.gd")

func _ready() -> void:
	print("==================================================")
	print("=== RUNNING VISUAL STAGE 2: GROUND SHADER & TEXTURES ===")
	print("==================================================")
	
	# 1. Test GroundMaterial loading and shader configuration
	var mat_res := load("res://Assets/GroundMaterial.tres") as ShaderMaterial
	assert(mat_res != null, "GroundMaterial.tres must load")
	assert(mat_res.shader != null, "GroundShader must be attached to material")
	
	var bump := float(mat_res.get_shader_parameter("bump_strength"))
	var macro := float(mat_res.get_shader_parameter("macro_scale"))
	var micro := float(mat_res.get_shader_parameter("micro_scale"))
	print("[TEST] Ground material parameters: bump=%.2f, macro=%.4f, micro=%.2f" % [
		bump, macro, micro
	])
	assert(bump > 0.0, "Bump strength must be > 0.0 for terrain relief")
	assert(macro < micro, "Macro scale must be smaller than micro scale for multi-tiling")
	
	# 2. Test Ground enhancement on scene node
	var ground_body := StaticBody3D.new()
	var ground_mesh := MeshInstance3D.new()
	ground_mesh.mesh = PlaneMesh.new()
	ground_body.add_child(ground_mesh)
	
	VisualEnhancer.enhance_ground(ground_body)
	assert(ground_mesh.material_override == mat_res, "Ground mesh material_override must be set to GroundMaterial")
	print("[TEST] Ground node successfully enhanced with ShaderMaterial")
	
	ground_body.free()
	
	print("==================================================")
	print("=== VISUAL STAGE 2 TEST PASSED SUCCESSFULLY! ===")
	print("==================================================")
	get_tree().quit(0)
