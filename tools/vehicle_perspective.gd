## Perspective look at each authored vehicle with a green forward arrow (-Z).
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
	gm.albedo_color = Color(0.35, 0.33, 0.26)
	ground.material_override = gm
	holder.add_child(ground)

	var kinds := [0, 1, 5]
	var names := ["TANK", "BMP", "HELI"]
	var vehicle_script := load("res://combat/vehicle.gd")
	for i in range(kinds.size()):
		var v = vehicle_script.new()
		v.kind = kinds[i]
		holder.add_child(v)
		v.global_position = Vector3(i * 24.0 - 24.0, 0.0, 0.0)
		v.set_physics_process(false)
		var label := Label3D.new()
		label.text = names[i]
		label.font_size = 64
		label.pixel_size = 0.02
		label.position = Vector3(v.global_position.x, 9.0, 0.0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		holder.add_child(label)
		_add_arrow(holder, v.global_position + Vector3(0, 0.1, -7.0))
		print("[PV] ", names[i], " pos=", v.global_position)

	var cam := Camera3D.new()
	holder.add_child(cam)
	cam.position = Vector3(0.0, 12.0, 28.0)
	cam.look_at(Vector3(0, 2.5, 0))
	cam.fov = 50.0
	cam.current = true

	for i in range(10):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	var path := "C:/Users/USER_UA/AppData/Local/Temp/opencode/vehicle_perspective.png"
	image.save_png(path)
	print("[PV] screenshot ", path)
	quit()


func _add_arrow(parent: Node3D, base: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.1, 7.0)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 1.0, 0.2)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.position = base + Vector3(0, 0, 3.5)
	parent.add_child(mi)
	var tip := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(2.0, 0.1, 2.5)
	tip.mesh = prism
	tip.material_override = mat
	tip.position = base + Vector3(0, 0, -1.2)
	tip.rotation.x = -PI * 0.5
	parent.add_child(tip)
