## Orthographic top + side + front views of one kind, with axis arrows.
## Usage: godot --path <proj> -s res://tools/vehicle_ortho.gd -- <kind>
extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var kind := 0
	var name := "TANK"
	if args.size() > 0:
		match args[0]:
			"BMP": kind = 3; name = "BMP"
			"APC": kind = 1; name = "APC"
			"HELI": kind = 5; name = "HELI"
	var holder := Node3D.new()
	root.add_child(holder)
	current_scene = holder

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.18, 0.19, 0.2)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 1.6
	env.environment = e
	holder.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-1.0, 0.7, 0.0)
	sun.light_energy = 1.2
	sun.shadow_enabled = false
	holder.add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.28, 0.29, 0.3)
	ground.material_override = gm
	holder.add_child(ground)

	var vehicle_script := load("res://combat/vehicle.gd")
	var v = vehicle_script.new()
	v.kind = kind
	holder.add_child(v)
	v.set_physics_process(false)

	_add_arrow(holder, Vector3.ZERO)

	var cam := Camera3D.new()
	holder.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 18.0
	cam.current = true

	var shots := {
		"top": Vector3(0.0, 40.0, 0.0),
		"side": Vector3(30.0, 3.0, 0.0),
		"front": Vector3(0.0, 3.0, -30.0),
	}
	for shot in shots:
		cam.position = shots[shot]
		if shot == "top":
			cam.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
		else:
			cam.look_at(Vector3(0.0, 2.0, 0.0))
		for f in range(6):
			await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_viewport().get_texture().get_image()
		var path: String = "C:/Users/USER_UA/AppData/Local/Temp/opencode/%s_ortho_%s.png" % [name.to_lower(), shot]
		image.save_png(path)
		print("[ORTHO] ", path)
	quit()


func _add_arrow(parent: Node3D, base: Vector3) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 1.0, 0.2)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.3, 0.06, 8.0)
	mi.mesh = box
	mi.material_override = mat
	mi.position = base + Vector3(0, 0.06, 1.0)
	parent.add_child(mi)
	var tip := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(1.2, 0.06, 2.0)
	tip.mesh = prism
	tip.material_override = mat
	tip.position = base + Vector3(0, 0.06, -4.0)
	tip.rotation.x = -PI * 0.5
	parent.add_child(tip)
