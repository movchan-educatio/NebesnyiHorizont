extends Node3D

func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	var env := WorldEnvironment.new()
	var env_res := Environment.new()
	env_res.background_mode = Environment.BG_COLOR
	env_res.background_color = Color(0.24, 0.30, 0.38)
	env_res.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env_res.ambient_light_color = Color(0.65, 0.70, 0.75)
	env_res.ambient_light_energy = 0.95
	env.environment = env_res
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 55, 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(100, 100)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.28, 0.34, 0.22)
	ground.material_override = gmat
	add_child(ground)

	# 1) Left soldier: Patrol walking with full stride flexion & shadow
	var walker := EnemyRifleman.new()
	walker.name = "PatrolSoldier"
	walker.position = Vector3(-1.25, 0.0, -0.2)
	walker.rotation_degrees.y = 150.0
	add_child(walker)
	walker.demo_warm_up()
	if walker._detailed_rig != null:
		walker._detailed_rig.set_walk(1.15, 1.0)

	# 2) Right soldier: Combat firing stance with muzzle flash & tracer
	var firer := EnemyRifleman.new()
	firer.name = "FiringSoldier"
	firer.position = Vector3(1.15, 0.0, 0.1)
	firer.rotation_degrees.y = 180.0
	add_child(firer)
	firer.demo_warm_up()

	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0.0, 1.45, 3.4)
	cam.look_at(Vector3(0.0, 1.25, 0.0), Vector3.UP)
	cam.current = true

	# Wait frames to settle transforms
	await get_tree().process_frame
	await get_tree().process_frame

	# Fire shot
	firer._fire()

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	img.save_png("res://qa_shots/showcase_infantry.png")
	print("[QA] Saved showcase_infantry.png successfully")

	get_tree().quit(0)
