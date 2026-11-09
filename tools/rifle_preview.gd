## QA: preview the authored rifle mesh detached from the soldier.
extends Node3D

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.15, 0.17, 0.2)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.85, 0.9)
	e.ambient_light_energy = 1.2
	env.environment = e
	add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 35, 0)
	key.light_energy = 2.0
	add_child(key)

	var soldier := (load("res://Assets/combat/soldier_detailed.glb") as PackedScene).instantiate() as Node3D
	add_child(soldier)
	soldier.visible = false
	var rifle := _find_rifle_mesh(soldier)
	if rifle == null:
		print("[RIFLE] not found")
		get_tree().quit(1)
		return
	var box: AABB = rifle.get_aabb()
	print("[RIFLE] box=", box)
	var copy := MeshInstance3D.new()
	copy.mesh = rifle.mesh
	copy.position = -box.get_center()
	var pivot := Node3D.new()
	add_child(pivot)
	pivot.add_child(copy)
	pivot.rotation_degrees = Vector3(
			float(OS.get_environment("RIFLE_PITCH")),
			float(OS.get_environment("RIFLE_YAW")),
			float(OS.get_environment("RIFLE_ROLL")))

	# Origin axes: red +X, green +Y, blue +Z.
	_add_axis(Vector3.RIGHT, Color.RED)
	_add_axis(Vector3.UP, Color.GREEN)
	_add_axis(Vector3.BACK, Color.BLUE)

	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 40.0
	var yaw := deg_to_rad(float(OS.get_environment("CAM_YAW")))
	cam.position = Vector3(sin(yaw) * 1.6, 0.8, cos(yaw) * 1.6)
	add_child(cam)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	for i in range(10):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out := OS.get_environment("MODEL_OUT")
	if out.is_empty():
		out = "C:/Users/USER_UA/AppData/Local/Temp/opencode/rifle_preview.png"
	print("[RIFLE] saved ", out, " err=", img.save_png(out))
	get_tree().quit(0)

func _add_axis(dir: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = dir.abs() * 0.5 + Vector3(0.01, 0.01, 0.01)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = dir * 0.25
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mi.material_override = mat
	add_child(mi)

func _find_rifle_mesh(node: Node) -> MeshInstance3D:
	for n in node.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			var mat := mi.mesh.surface_get_material(s)
			if mat != null and String(mat.resource_name).contains("w_val"):
				return mi
	return null
