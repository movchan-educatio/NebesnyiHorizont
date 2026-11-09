## Single normalized APC with axis rulers, top view.
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
	e.background_color = Color(0.16, 0.17, 0.19)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 1.7
	env.environment = e
	holder.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-1.0, 0.7, 0.0)
	sun.light_energy = 1.2
	holder.add_child(sun)

	var v = load("res://combat/vehicle.gd").new()
	v.kind = 1
	holder.add_child(v)
	v.set_physics_process(false)

	var model := v.get_node_or_null("Model") as Node3D
	if model != null:
		print("[SINGLE] model rot=", model.rotation_degrees,
				" basis=", model.global_transform.basis,
				" pos=", model.global_position)
	# Red ruler along +X at z = 7 (should be horizontal on screen).
	_ruler(holder, Vector3(0, 0.05, 7), Vector3(14, 0.1, 0.3), Color(1, 0.1, 0.1))
	# Green ruler along -Z at x = 7 (should be vertical on screen).
	_ruler(holder, Vector3(7, 0.05, 0), Vector3(0.3, 0.1, 14), Color(0.1, 1, 0.2))

	var cam := Camera3D.new()
	holder.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 24.0
	cam.position = Vector3(0.0, 40.0, 0.0)
	cam.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	cam.current = true

	for f in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(
			"C:/Users/USER_UA/AppData/Local/Temp/opencode/apc_single_top.png")
	print("[SINGLE] saved")
	quit()


func _ruler(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
