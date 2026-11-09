## QA: render the four ground vehicle kinds with their new materials/detail.
extends Node3D

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.18, 0.21)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.80, 0.84, 0.9)
	e.ambient_light_energy = 1.1
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, 35, 0)
	key.light_energy = 2.2
	key.shadow_enabled = true
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(25, -140, 0)
	fill.light_energy = 0.8
	fill.light_color = Color(0.72, 0.84, 1.0)
	add_child(fill)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(100, 100)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.30, 0.29, 0.26)
	gm.roughness = 0.95
	ground.material_override = gm
	add_child(ground)

	var kinds := [Vehicle.Kind.TANK, Vehicle.Kind.BMP, Vehicle.Kind.APC, Vehicle.Kind.TRUCK]
	var x := -9.0
	for k in kinds:
		var v := Vehicle.new()
		v.kind = k
		v.hostile = true
		v.move_speed = 0.0
		v.fire_range = 0.0
		add_child(v)
		v.position = Vector3(x, 0.0, 0.0)
		v.rotation.y = deg_to_rad(float(OS.get_environment("VEHICLE_YAW")))
		x += 6.0
		await get_tree().process_frame

	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 42.0
	cam.position = Vector3(0.0, 9.0, 26.0)
	add_child(cam)
	cam.look_at(Vector3(0.0, 1.3, 0.0), Vector3.UP)
	for i in range(12):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out := OS.get_environment("MODEL_OUT")
	if out.is_empty():
		out = "C:/Users/USER_UA/AppData/Local/Temp/opencode/vehicles.png"
	print("[VEHICLES] saved ", out, " err=", img.save_png(out))
	get_tree().quit(0)
