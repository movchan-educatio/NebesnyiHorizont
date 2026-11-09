extends Node3D

func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	var env := WorldEnvironment.new()
	var env_res := Environment.new()
	env_res.background_mode = Environment.BG_COLOR
	env_res.background_color = Color(0.35, 0.42, 0.50)
	env_res.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env_res.ambient_light_color = Color(0.7, 0.75, 0.8)
	env_res.ambient_light_energy = 0.9
	env.environment = env_res
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 60, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120, 120)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.28, 0.33, 0.22)
	ground.material_override = gmat
	add_child(ground)

	# Drone dummy target in the air
	var drone_target := Node3D.new()
	drone_target.position = Vector3(8.0, 12.0, -28.0)
	add_child(drone_target)

	# Tank
	var tank := Vehicle.new()
	tank.name = "Tank_T72"
	tank.kind = Vehicle.Kind.TANK
	tank.position = Vector3(-4.0, 0.0, 0.0)
	tank.hostile = true
	tank.track_drone = true
	add_child(tank)
	tank._drone = drone_target

	# BMP
	var bmp := Vehicle.new()
	bmp.name = "BMP_2M"
	bmp.kind = Vehicle.Kind.BMP
	bmp.position = Vector3(6.0, 0.0, -3.0)
	bmp.hostile = true
	bmp.track_drone = true
	add_child(bmp)
	bmp._drone = drone_target

	# Camera viewing both armored vehicles and drone direction
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(12.0, 4.5, 9.0)
	cam.look_at(Vector3(1.0, 1.8, -10.0), Vector3.UP)
	cam.current = true

	# Wait a few frames for turrets to track the drone
	for i in range(25):
		tank._aim_turret(0.05)
		bmp._aim_turret(0.05)
		await get_tree().process_frame

	# Fire!
	tank._fire_at(drone_target.global_position)

	await get_tree().physics_frame
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	img.save_png("res://qa_shots/vehicle_combat_in_action.png")
	print("[QA] Saved vehicle_combat_in_action.png successfully")

	get_tree().quit(0)
