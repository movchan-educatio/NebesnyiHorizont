## QA: line up the authored vehicles nose-forward (-Z) and take a top-down shot.
## Green marker = game forward (-Z), red marker = behind (+Z).
## Run: godot --path <proj> --resolution 1280x720 -s res://tools/vehicle_yaw_check.gd
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
	sky.sky_material = ProceduralSkyMaterial.new()
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 1.2
	env.environment = e
	holder.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-1.0, 0.6, 0.0)
	sun.light_energy = 1.4
	holder.add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(500, 500)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.32, 0.30, 0.24)
	ground.material_override = gm
	ground.position.y = -0.05
	holder.add_child(ground)

	var kinds := [0, 3, 1, 5]  # TANK, BMP, APC, HELI
	var names := ["TANK", "BMP", "APC", "HELI"]
	var vehicle_script := load("res://combat/vehicle.gd")
	for i in range(kinds.size()):
		var v = vehicle_script.new()
		v.kind = kinds[i]
		holder.add_child(v)
		v.global_position = Vector3(i * 30.0 - 45.0, 2.0, 0.0)
		v.rotation.y = 0.0
		v.set_physics_process(false)
		var model := v.get_node_or_null("Model") as Node3D
		if model != null:
			var box := _model_aabb(model)
			print("[YAW] ", names[i], " aabb_size=", box.size,
					" model_yaw=", model.rotation_degrees)
			print("[YAW] ", names[i], " basis_z=", model.global_transform.basis.z,
					" basis_x=", model.global_transform.basis.x,
					" model_pos=", model.global_position)
			if names[i] == "BMP":
				_dump_visuals(model)
		var label := Label3D.new()
		label.text = names[i]
		label.font_size = 64
		label.pixel_size = 0.025
		label.modulate = Color(1, 1, 0.5)
		label.rotation.x = -PI * 0.5
		label.position = Vector3(v.global_position.x, 16.0, 18.0)
		holder.add_child(label)
		_add_marker(holder, v.global_position + Vector3(0, 0.2, -11.0),
				Vector3(2.0, 0.2, 10.0), Color(0.1, 1.0, 0.2))
		_add_marker(holder, v.global_position + Vector3(0, 0.2, 11.0),
				Vector3(2.0, 0.2, 10.0), Color(1.0, 0.15, 0.1))

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 100.0
	cam.position = Vector3(0.0, 95.0, 0.0)
	cam.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	cam.current = true
	holder.add_child(cam)

	for i in range(10):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	var path := "C:/Users/USER_UA/AppData/Local/Temp/opencode/vehicle_yaw_lineup.png"
	var err := image.save_png(path)
	print("[VEHICLES] ", path, " err=", err)
	var meshes: Array[MeshInstance3D] = []
	_collect(holder, meshes)
	print("[VEHICLES] meshes=", meshes.size())
	quit()


func _add_marker(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	# Arrow head on the green marker's forward end.
	if color.g > 0.5:
		var tip := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(4.0, 0.2, 4.0)
		tip.mesh = prism
		tip.material_override = mat
		tip.position = pos + Vector3(0, 0, -7.0)
		tip.rotation.x = -PI * 0.5
		parent.add_child(tip)


func _collect(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect(child, out)


func _dump_visuals(root: Node) -> void:
	var rows: Array = []
	_visual_rows(root, rows)
	rows.sort_custom(func(a, b): return a[0] > b[0])
	for i in range(mini(8, rows.size())):
		print("[VIS] ", rows[i][1], " dim=", rows[i][0], " size=", rows[i][2])


func _visual_rows(node: Node, rows: Array) -> void:
	if node is VisualInstance3D:
		var v := node as VisualInstance3D
		var b: AABB = v.global_transform * v.get_aabb()
		rows.append([maxf(b.size.x, maxf(b.size.y, b.size.z)), node.name, b.size])
	for child in node.get_children():
		_visual_rows(child, rows)


func _model_aabb(node: Node) -> AABB:
	var acc := [null]
	_aabb_walk(node, Transform3D.IDENTITY, acc)
	return acc[0] if acc[0] != null else AABB()


func _aabb_walk(node: Node, xform: Transform3D, acc: Array) -> void:
	var t := xform
	if node is Node3D:
		t = xform * (node as Node3D).transform
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var b: AABB = t * mi.mesh.get_aabb()
			acc[0] = b if acc[0] == null else (acc[0] as AABB).merge(b)
	for child in node.get_children():
		_aabb_walk(child, t, acc)
