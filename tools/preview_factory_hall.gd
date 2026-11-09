extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	current_scene = holder
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.04, 0.045, 0.05)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.58, 0.60)
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.volumetric_fog_enabled = true
	e.volumetric_fog_density = 0.01
	e.volumetric_fog_albedo = Color(0.8, 0.82, 0.85)
	env.environment = e
	holder.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-70, 20, 0)
	sun.light_energy = 4.0
	sun.light_color = Color(1.0, 0.86, 0.65)
	sun.light_volumetric_fog_energy = 4.0
	holder.add_child(sun)
	var scene := load("res://Assets/frontline/factory_hall.glb") as PackedScene
	var inst := scene.instantiate() as Node3D
	holder.add_child(inst)
	var cam := Camera3D.new()
	holder.add_child(cam)
	cam.fov = 70.0
	cam.current = true
	cam.position = Vector3(0, 10, 0)
	cam.look_at(Vector3(0, 10, 20))
	for f in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	image.save_png("C:/Users/USER_UA/AppData/Local/Temp/opencode/factory_hall.png")
	print("[FACTORY] saved")
	quit()

