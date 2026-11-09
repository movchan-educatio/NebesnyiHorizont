extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	current_scene = holder
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.22, 0.42, 0.72)
	sm.sky_horizon_color = Color(0.72, 0.80, 0.88)
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 1.3
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	holder.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-28, 40, 0)
	sun.light_energy = 2.0
	holder.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.35, 0.33, 0.26)
	ground.material_override = gm
	holder.add_child(ground)
	var scene := load("res://Assets/Environment/street_city_buildings_8.glb") as PackedScene
	var inst := scene.instantiate() as Node3D
	holder.add_child(inst)
	var box := AABB()
	var first := true
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	print("[CITY] bounds=", box)
	var center := box.get_center()
	var max_dim := maxf(box.size.x, maxf(box.size.y, box.size.z))
	inst.scale = Vector3.ONE * (18.0 / maxf(max_dim, 0.1))
	inst.position = -center * inst.scale.x
	inst.position.y = 0.0
	var cam := Camera3D.new()
	holder.add_child(cam)
	cam.fov = 45.0
	cam.current = true
	cam.position = Vector3(22, 13, 24)
	cam.look_at(Vector3(0, 4, 0))
	for f in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	image.save_png("C:/Users/USER_UA/AppData/Local/Temp/opencode/city_block.png")
	print("[CITY] saved")
	quit()
