## QA: verify the Apache main rotor gets a pivot and visibly spins.
extends SceneTree

const OUT := "C:/Users/USER_UA/AppData/Local/Temp/opencode/"


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
	sky.sky_material = ProceduralSkyMaterial.new()
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 1.4
	env.environment = e
	holder.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-1.0, 0.7, 0.0)
	sun.light_energy = 1.5
	holder.add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.32, 0.30, 0.24)
	ground.material_override = gm
	holder.add_child(ground)

	var v = load("res://combat/vehicle.gd").new()
	v.kind = 5
	holder.add_child(v)
	v.global_position = Vector3(0, 6, 0)

	var rotor := v.get_node_or_null("Model/MainRotor") as Node3D
	if rotor == null:
		# The pivot is added under the model node, which may be nested.
		for n in v.find_children("*", "Node3D", true, false):
			if n.name == "MainRotor":
				rotor = n
				break
	if rotor == null:
		print("[ROTOR] FAIL no MainRotor pivot")
		quit()
		return
	print("[ROTOR] pivot=", rotor.get_path(), " initial_y=", rotor.rotation.y)

	var cam := Camera3D.new()
	holder.add_child(cam)
	cam.position = Vector3(26.0, 18.0, 26.0)
	cam.look_at(Vector3(0, 7.0, 0))
	cam.fov = 45.0
	cam.current = true

	await create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OUT + "heli_rotor_a.png")
	var a := rotor.rotation.y
	await create_timer(0.45).timeout
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OUT + "heli_rotor_b.png")
	var b := rotor.rotation.y
	print("[ROTOR] rotation_a=", a, " rotation_b=", b, " delta=", b - a)
	quit()
