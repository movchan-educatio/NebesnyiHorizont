extends Node3D

## Mobile visual QA: compare the runtime detailed rig with its baked LOD atlas.
func _ready() -> void:
	OS.set_environment("MOBILE_UI", "1")
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.13, 0.17, 0.18)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.74, 0.79, 0.72)
	environment.ambient_light_energy = 1.15
	environment_node.environment = environment
	add_child(environment_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, -25.0, 0.0)
	sun.light_energy = 1.4
	add_child(sun)
	var floor := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(30.0, 30.0)
	floor.mesh = floor_mesh
	floor.position.y = -0.02
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.20, 0.23, 0.19)
	floor_mat.roughness = 1.0
	floor.material_override = floor_mat
	add_child(floor)
	var camera := Camera3D.new()
	camera.current = true
	camera.position = Vector3(3.2, 2.35, 11.0)
	camera.fov = 46.0
	add_child(camera)
	camera.look_at(Vector3(3.2, 1.45, 0.0), Vector3.UP)

	var detailed := EnemyRifleman.new()
	detailed.name = "DetailedMobileSoldier"
	detailed.position = Vector3(-1.15, 0.0, 0.0)
	detailed.rotation.y = PI
	add_child(detailed)
	var impostor := EnemyRifleman.new()
	impostor.name = "MobileImpostorSoldier"
	impostor.position = Vector3(1.15, 0.0, 0.0)
	impostor.rotation.y = PI
	add_child(impostor)
	await get_tree().process_frame
	await get_tree().process_frame
	# Hold both examples at a near camera distance so this comparison screenshot
	# is readable; the LOD transition itself is verified by qa_mobile_infantry_lod.
	var impostor_proxy := impostor.get("_lod_proxy") as Node3D
	var impostor_sprite := impostor.get("_lod_impostor") as Sprite3D
	var impostor_model := impostor.get("_model") as Node3D
	if impostor_proxy != null and impostor_sprite != null and impostor_model != null:
		impostor_model.visible = false
		impostor.set("_using_proxy", true)
		impostor_proxy.visible = true
	var near_label := Label3D.new()
	near_label.text = "DETAILED RIG"
	near_label.font_size = 36
	near_label.pixel_size = 0.003
	near_label.position = Vector3(-1.15, 3.55, 0.0)
	near_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(near_label)
	var impostor_label := Label3D.new()
	impostor_label.text = "4-VIEW IMPOSTOR"
	impostor_label.font_size = 36
	impostor_label.pixel_size = 0.003
	impostor_label.position = Vector3(1.15, 3.55, 0.0)
	impostor_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(impostor_label)
