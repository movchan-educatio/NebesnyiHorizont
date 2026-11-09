## QA: preview the authored rifleman and dump its part positions.
extends SceneTree

const RIFLEMAN := "res://Assets/combat/rifleman.glb"


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
	e.ambient_light_energy = 1.1
	env.environment = e
	holder.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-1.0, 0.5, 0.0)
	sun.light_energy = 1.3
	holder.add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.33, 0.31, 0.24)
	ground.material_override = gm
	holder.add_child(ground)

	var packed := load(RIFLEMAN) as PackedScene
	var model := packed.instantiate() as Node3D
	holder.add_child(model)
	model.rotation.y = 0.0

	var hips := ["Thigh_R", "Shin_R", "Boot_R", "Thigh_L", "Shin_L", "Boot_L",
			"Upper_arm_R", "Forearm_R", "Glove_R", "Rifle_receiver", "Head", "Torso"]
	for n in hips:
		var node := model.find_child(n, true, false) as Node3D
		if node != null:
			print("[RIFLEMAN] ", n, " pos=", node.global_position, " rot=", node.global_rotation)

	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 50.0
	holder.add_child(cam)
	cam.position = Vector3(0.0, 1.45, -4.4)
	cam.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)

	for i in range(10):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	var path := "C:/Users/USER_UA/AppData/Local/Temp/opencode/rifleman_preview.png"
	var err := image.save_png(path)
	print("[RIFLEMAN] ", path, " err=", err)
	quit()
