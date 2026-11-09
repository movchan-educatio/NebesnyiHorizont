extends Node

func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	var env := WorldEnvironment.new()
	var env_res := Environment.new()
	env_res.background_mode = Environment.BG_COLOR
	env_res.background_color = Color(0.2, 0.25, 0.3)
	env.environment = env_res
	add_child(env)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 45, 0)
	add_child(light)

	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(2.6, 0.95, -1.1)
	cam.look_at(Vector3(0, 0.9, 0), Vector3.UP)
	cam.current = true

	var rig := DetailedSoldierRig.new()
	add_child(rig)
	rig.setup_rig(0)
	rig.set_walk(1.5, 1.0)

	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://qa_shots/soldier_walk_pose.png")
	print("[SOLDIER] saved soldier_walk_pose.png")
	get_tree().quit(0)
