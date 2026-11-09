## One close 3/4 render per authored vehicle, with a green forward arrow (-Z).
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
	gm.albedo_color = Color(0.35, 0.33, 0.26)
	ground.material_override = gm
	holder.add_child(ground)

	var cam := Camera3D.new()
	holder.add_child(cam)
	cam.fov = 45.0
	cam.current = true

	var kinds := [0, 1, 3, 5]
	var names := ["TANK", "APC", "BMP", "HELI"]
	var vehicle_script := load("res://combat/vehicle.gd")
	for i in range(kinds.size()):
		var v = vehicle_script.new()
		v.kind = kinds[i]
		holder.add_child(v)
		v.set_physics_process(false)
		_add_arrow(holder, Vector3.ZERO)
		cam.position = Vector3(13.0, 7.0, 14.0)
		cam.look_at(Vector3(0.0, 2.0, 0.0))
		for f in range(6):
			await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_viewport().get_texture().get_image()
		var path: String = OUT + names[i].to_lower() + "_view.png"
		image.save_png(path)
		print("[VIEW] ", names[i], " -> ", path)
		v.queue_free()
		for c in holder.get_children():
			if c is MeshInstance3D:
				c.queue_free()
		await process_frame
	quit()


func _add_arrow(parent: Node3D, base: Vector3) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 1.0, 0.2)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.4, 0.08, 9.0)
	mi.mesh = box
	mi.material_override = mat
	mi.position = base + Vector3(0, 0.08, 1.5)
	parent.add_child(mi)
	var tip := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(1.6, 0.08, 2.4)
	tip.mesh = prism
	tip.material_override = mat
	tip.position = base + Vector3(0, 0.08, -4.2)
	tip.rotation.x = -PI * 0.5
	parent.add_child(tip)
