## Minimal rotation test: raw APC GLB with yaw 90, plus a red X ruler.
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
	e.background_color = Color(0.15, 0.16, 0.18)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 1.8
	env.environment = e
	holder.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-1.0, 0.7, 0.0)
	sun.light_energy = 1.2
	holder.add_child(sun)

	var inst: Node3D = load("res://Assets/vehicles/btr-90_ussr.glb").instantiate()
	holder.add_child(inst)
	inst.rotation.y = PI * 0.5
	print("[RAW] inst rot=", inst.rotation_degrees)

	var red := MeshInstance3D.new()
	var rb := BoxMesh.new()
	rb.size = Vector3(10.0, 0.1, 0.4)
	red.mesh = rb
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(1, 0.1, 0.1)
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	red.material_override = rm
	red.position = Vector3(0, 0.1, 8.0)
	holder.add_child(red)

	var green := MeshInstance3D.new()
	var gb := BoxMesh.new()
	gb.size = Vector3(0.4, 0.1, 10.0)
	green.mesh = gb
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.1, 1.0, 0.2)
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	green.material_override = gm
	green.position = Vector3(8.0, 0.1, 0)
	holder.add_child(green)

	var cam := Camera3D.new()
	holder.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 30.0
	cam.position = Vector3(0.0, 40.0, 0.0)
	cam.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	cam.current = true

	for f in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(
			"C:/Users/USER_UA/AppData/Local/Temp/opencode/apc_raw_rot.png")
	print("[RAW] saved")
	quit()
