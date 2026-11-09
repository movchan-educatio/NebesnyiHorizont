extends Node3D

func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	var env := WorldEnvironment.new()
	var env_res := Environment.new()
	env_res.background_mode = Environment.BG_COLOR
	env_res.background_color = Color(0.25, 0.32, 0.40)
	env_res.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env_res.ambient_light_color = Color(0.65, 0.7, 0.75)
	env_res.ambient_light_energy = 0.9
	env.environment = env_res
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 55, 0)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(100, 100)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.28, 0.32, 0.22)
	ground.material_override = gmat
	add_child(ground)

	# Target drone high in front
	var drone_target := Node3D.new()
	drone_target.position = Vector3(0.0, 7.0, -18.0)
	add_child(drone_target)

	# Enemy rifleman at origin
	var soldier := EnemyRifleman.new()
	soldier.name = "EnemyRifleman"
	soldier.position = Vector3.ZERO
	add_child(soldier)
	soldier._drone = drone_target as Drone
	soldier._los_clear = true
	soldier._distance = 19.0

	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(2.4, 1.3, -2.2)
	cam.look_at(Vector3(0.0, 1.2, -0.6), Vector3.UP)
	cam.current = true

	# Set muzzle position directly to the calibrated barrel tip
	soldier._muzzle.position = Vector3(0.52, 0.967, -0.81)

	soldier.demo_warm_up()
	soldier._fire()

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	img.save_png("res://qa_shots/infantry_shooting_action.png")
	print("[QA] Saved infantry_shooting_action.png successfully")

	get_tree().quit(0)
